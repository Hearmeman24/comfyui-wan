#!/usr/bin/env python3
"""Workflow-driven model provisioner.

Reads enabled flags (download_wan21, download_wan22, download_wan_animate,
download_steady_dancer), walks the matching workflow folders, resolves model
basenames against models_registry.json, emits a tab-separated download manifest
for hf_download_manager.py, and copies the selected workflow JSONs into the
user's ComfyUI workflows directory.

Source of truth is the workflows tree itself. Adding a model reference to a
workflow without a corresponding registry entry surfaces as a user-supplied
warning (not a hard error here — the CI validator in tools/validate_models.py
enforces registry coverage at merge time).
"""
import argparse
import json
import os
import re
import shutil
import sys
from pathlib import Path

FLAG_DIRS = {
    "download_wan21": ["Wan 2.1", "Infinite Talk"],
    "download_wan22": ["Wan 2.2", "SVI_Video_Extension_Wan2.2"],
    "download_wan_animate": ["Wan Animate"],
    "download_steady_dancer": ["Steady Dancer"],
}

# Fetched at runtime by custom nodes (controlnet_aux, segment-anything-2, etc.)
AUTO_DOWNLOAD = {
    "rife49.pth",
    "depth_anything_v2_vitl.pth",
    "sam2_hiera_base_plus.safetensors",
    "sam2.1_hiera_base_plus.safetensors",
    "yolox_l.onnx",
}

# Baked into the docker image
IMAGE_BAKED = {"4xLSDIR.pth"}

MODEL_PAT = re.compile(r'"([^"]+\.(?:safetensors|bin|onnx|pth|ckpt))"')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--registry", required=True)
    ap.add_argument("--workflows-src", required=True)
    ap.add_argument("--workflows-dst", required=True)
    ap.add_argument("--models-root", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--flag", action="append", dest="flags", default=[])
    args = ap.parse_args()

    registry = json.loads(Path(args.registry).read_text())
    src_root = Path(args.workflows_src)
    dst_root = Path(args.workflows_dst)
    models_root = Path(args.models_root)
    manifest = Path(args.manifest)

    if not args.flags:
        print("[provisioner] no flags enabled — empty manifest, no workflows copied")
        manifest.write_text("")
        return 0

    folders = []
    for f in args.flags:
        if f not in FLAG_DIRS:
            print(f"[provisioner] unknown flag: {f}", file=sys.stderr)
            return 2
        folders.extend(FLAG_DIRS[f])

    refs: dict[str, set[str]] = {}
    workflow_files: list[Path] = []
    for folder in folders:
        d = src_root / folder
        if not d.is_dir():
            print(f"[provisioner] warning: workflow folder missing: {d}")
            continue
        for wf in d.rglob("*.json"):
            workflow_files.append(wf)
            for m in MODEL_PAT.findall(wf.read_text()):
                refs.setdefault(os.path.basename(m), set()).add(str(wf))

    queued: dict[str, dict] = {}
    user_supplied: list[str] = []
    for b in refs:
        if b in IMAGE_BAKED or b in AUTO_DOWNLOAD:
            continue
        if b in registry:
            queued[b] = registry[b]
        else:
            user_supplied.append(b)

    # Auto-include sidecars whose trigger is in the queue (e.g. vitpose .bin)
    for b, entry in registry.items():
        trigger = entry.get("auto_include_with")
        if trigger and trigger in queued:
            queued[b] = entry

    # Skip files that already exist on disk above a sanity threshold.
    # Matches the pre-refactor bash behavior (10 MB cutoff catches
    # complete files while still re-fetching obviously-truncated ones).
    MIN_OK_SIZE = 10 * 1024 * 1024
    skipped_existing = []
    lines = []
    for b in sorted(queued):
        entry = queued[b]
        dest = models_root / entry["subdir"] / b
        if dest.is_file() and dest.stat().st_size >= MIN_OK_SIZE:
            skipped_existing.append(b)
            continue
        lines.append(f"{entry['url']}\t{dest}")
    manifest.write_text("\n".join(lines) + ("\n" if lines else ""))

    dst_root.mkdir(parents=True, exist_ok=True)
    copied = 0
    for wf in workflow_files:
        rel = wf.relative_to(src_root)
        out = dst_root / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(wf, out)
        copied += 1

    print(f"[provisioner] flags: {','.join(args.flags)}")
    print(f"[provisioner] workflows copied: {copied}")
    print(f"[provisioner] models queued: {len(lines)} "
          f"({len(skipped_existing)} already on disk, skipped)")
    if user_supplied:
        print(f"[provisioner] {len(user_supplied)} user-supplied LoRA(s) referenced "
              "but not in registry — place them manually or via "
              "CHECKPOINT_IDS_TO_DOWNLOAD/LORAS_IDS_TO_DOWNLOAD:")
        for b in sorted(user_supplied):
            print(f"  - {b}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
