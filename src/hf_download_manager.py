#!/usr/bin/env python3
"""Unified manifest-driven Hugging Face download manager.

Reads a manifest of `<url>\\t<dest_full_path>` lines, downloads each via
hf_hub_download (with hf_xet acceleration), using a thread pool of 3 and a
single snapshot logger that prints append-only status every 10 seconds.
"""
import os
import re
import shutil
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from huggingface_hub import HfFileSystem, hf_hub_download

POOL_SIZE = 3
SNAPSHOT_INTERVAL = 10  # seconds

# https://huggingface.co/<repo_id>/resolve/<revision>/<file_in_repo>[?...]
HF_URL_RE = re.compile(
    r"^https?://huggingface\.co/(?P<repo>[^/]+/[^/]+)/resolve/(?P<rev>[^/]+)/(?P<file>.+?)(?:\?.*)?$"
)


@dataclass
class Job:
    url: str
    dest: Path
    repo_id: str
    revision: str
    filename: str
    total_bytes: int = 0
    status: str = "queued"  # queued | active | done | failed
    start_ts: float = 0.0
    end_ts: float = 0.0
    stage_dir: Optional[Path] = None
    error: Optional[str] = None


def parse_manifest(path: Path) -> list[Job]:
    jobs = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "\t" not in line:
            print(f"[hf-manager] skip malformed line: {line}", flush=True)
            continue
        url, dest = line.split("\t", 1)
        m = HF_URL_RE.match(url)
        if not m:
            print(f"[hf-manager] skip non-HF url: {url}", flush=True)
            continue
        jobs.append(Job(
            url=url,
            dest=Path(dest),
            repo_id=m["repo"],
            revision=m["rev"],
            filename=m["file"],
        ))
    return jobs


def fetch_sizes(jobs: list[Job]) -> None:
    fs = HfFileSystem()
    for j in jobs:
        try:
            info = fs.info(f"{j.repo_id}/{j.filename}", revision=j.revision)
            j.total_bytes = int(info.get("size") or 0)
        except Exception as e:
            print(f"[hf-manager] size lookup failed for {j.dest.name}: {e}", flush=True)


def fmt_bytes(n: float) -> str:
    n = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}TB"


def fmt_dur(secs: float) -> str:
    secs = int(max(secs, 0))
    h, rem = divmod(secs, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def stage_bytes(job: Job) -> int:
    if not job.stage_dir or not job.stage_dir.exists():
        return 0
    total = 0
    for root, _, files in os.walk(job.stage_dir):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def run_job(job: Job, lock: threading.Lock) -> None:
    with lock:
        job.status = "active"
        job.start_ts = time.time()
    try:
        job.dest.parent.mkdir(parents=True, exist_ok=True)
        stage = job.dest.parent / ".hf_stage" / job.dest.name
        if stage.exists():
            shutil.rmtree(stage, ignore_errors=True)
        stage.mkdir(parents=True, exist_ok=True)
        with lock:
            job.stage_dir = stage

        local_path = hf_hub_download(
            repo_id=job.repo_id,
            filename=job.filename,
            revision=job.revision,
            local_dir=str(stage),
        )
        src = Path(local_path)
        if src.resolve() != job.dest.resolve():
            shutil.move(str(src), str(job.dest))
        shutil.rmtree(stage, ignore_errors=True)

        with lock:
            job.status = "done"
            job.end_ts = time.time()
    except Exception as e:
        with lock:
            job.status = "failed"
            job.error = str(e)
            job.end_ts = time.time()


def snapshot(jobs: list[Job], started_at: float, lock: threading.Lock,
             prev_bytes: dict) -> bool:
    with lock:
        active = [j for j in jobs if j.status == "active"]
        queued = [j for j in jobs if j.status == "queued"]
        done = [j for j in jobs if j.status == "done"]
        failed = [j for j in jobs if j.status == "failed"]

    now = time.time()
    elapsed = now - started_at
    lines = [
        f"=== HF Downloads @ {fmt_dur(elapsed)} — "
        f"{len(done)}/{len(jobs)} done, {len(active)} active, "
        f"{len(queued)} queued, {len(failed)} failed ==="
    ]
    if active:
        lines.append("ACTIVE")
        for j in active:
            cur = stage_bytes(j)
            pct = (cur / j.total_bytes * 100) if j.total_bytes else 0.0
            prev_t, prev_b = prev_bytes.get(id(j), (j.start_ts, 0))
            dt = max(now - prev_t, 0.001)
            speed = max(cur - prev_b, 0) / dt
            eta = (j.total_bytes - cur) / speed if speed > 0 and j.total_bytes else 0
            prev_bytes[id(j)] = (now, cur)
            lines.append(
                f"  {j.dest.name:<60} {pct:5.1f}%  "
                f"{fmt_bytes(cur):>9}/{fmt_bytes(j.total_bytes):<9}  "
                f"{fmt_bytes(speed)}/s  ETA {fmt_dur(eta)}"
            )
    if queued:
        names = ", ".join(j.dest.name for j in queued[:8])
        more = "" if len(queued) <= 8 else f", +{len(queued) - 8} more"
        lines.append(f"QUEUED ({len(queued)}): {names}{more}")
    if failed:
        lines.append("FAILED")
        for j in failed:
            lines.append(f"  {j.dest.name}: {j.error}")
    print("\n".join(lines), flush=True)
    return bool(active or queued)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: hf_download_manager.py <manifest>", file=sys.stderr)
        return 2
    manifest = Path(sys.argv[1])
    if not manifest.exists():
        print(f"[hf-manager] manifest not found: {manifest}", flush=True)
        return 0
    jobs = parse_manifest(manifest)
    if not jobs:
        print("[hf-manager] empty manifest, nothing to do", flush=True)
        return 0

    print(f"[hf-manager] {len(jobs)} files queued; resolving sizes...", flush=True)
    fetch_sizes(jobs)
    total = sum(j.total_bytes for j in jobs)
    print(f"[hf-manager] total size: {fmt_bytes(total)}; starting {POOL_SIZE}-way pool", flush=True)

    lock = threading.Lock()
    started_at = time.time()
    prev_bytes: dict = {}

    with ThreadPoolExecutor(max_workers=POOL_SIZE) as pool:
        futures = [pool.submit(run_job, j, lock) for j in jobs]
        while True:
            time.sleep(SNAPSHOT_INTERVAL)
            still_running = snapshot(jobs, started_at, lock, prev_bytes)
            if not still_running and all(f.done() for f in futures):
                break

    snapshot(jobs, started_at, lock, prev_bytes)
    failed = [j for j in jobs if j.status == "failed"]
    if failed:
        print(f"[hf-manager] {len(failed)} failures", flush=True)
        return 1
    print(f"[hf-manager] all {len(jobs)} downloads complete in {fmt_dur(time.time() - started_at)}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
