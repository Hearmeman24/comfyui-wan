#!/usr/bin/env python3
"""CI validator: registry coverage + URL reachability.

- Coverage: every model basename referenced in workflows/**/*.json must be
  either in src/models_registry.json, in the auto-download allowlist (fetched
  by a custom node at runtime), or image-baked. Anything else is flagged as
  user-supplied (warning, not error) — the user is expected to provide it via
  CHECKPOINT_IDS/LORAS_IDS at runtime.
- Reachability: every registry URL must return 200/301/302 on HEAD.

Exit non-zero on any reachability failure or unparseable workflow JSON.
"""
import asyncio
import json
import os
import re
import sys
from pathlib import Path

import httpx

AUTO_DOWNLOAD = {
    "rife49.pth",
    "depth_anything_v2_vitl.pth",
    "sam2_hiera_base_plus.safetensors",
    "sam2.1_hiera_base_plus.safetensors",
    "yolox_l.onnx",
}
IMAGE_BAKED = {"4xLSDIR.pth"}
MODEL_PAT = re.compile(r'"([^"]+\.(?:safetensors|bin|onnx|pth|ckpt))"')

REPO = Path(__file__).resolve().parents[1]


def collect_workflow_refs() -> dict[str, set[str]]:
    refs: dict[str, set[str]] = {}
    for wf in (REPO / "workflows").rglob("*.json"):
        try:
            text = wf.read_text()
        except Exception as e:
            print(f"❌ cannot read workflow {wf}: {e}")
            sys.exit(1)
        try:
            json.loads(text)
        except Exception as e:
            print(f"❌ invalid JSON in workflow {wf}: {e}")
            sys.exit(1)
        for m in MODEL_PAT.findall(text):
            refs.setdefault(os.path.basename(m), set()).add(
                str(wf.relative_to(REPO))
            )
    return refs


async def head(client: httpx.AsyncClient, url: str) -> tuple[int | None, str | None]:
    try:
        r = await client.head(url, follow_redirects=True, timeout=30)
        return r.status_code, None
    except Exception as e:
        return None, str(e)


async def main() -> int:
    registry = json.loads((REPO / "src" / "models_registry.json").read_text())
    refs = collect_workflow_refs()

    warnings: list[str] = []
    for b, wfs in sorted(refs.items()):
        if b in AUTO_DOWNLOAD or b in IMAGE_BAKED or b in registry:
            continue
        warnings.append(f"user-supplied (not in registry): {b}  [{len(wfs)} workflow(s)]")

    errors: list[str] = []
    async with httpx.AsyncClient(http2=True) as client:
        urls = [(b, e["url"]) for b, e in registry.items()]
        results = await asyncio.gather(*[head(client, u) for _, u in urls])
    for (b, url), (status, err) in zip(urls, results):
        if err:
            errors.append(f"UNREACHABLE: {b}: {err} ({url})")
        elif status not in (200, 301, 302):
            errors.append(f"BAD STATUS {status}: {b} -> {url}")

    if warnings:
        print(f"⚠️  {len(warnings)} warning(s):")
        for w in warnings:
            print(f"   {w}")
    if errors:
        print(f"❌ {len(errors)} reachability error(s):")
        for e in errors:
            print(f"   {e}")
        return 1
    print(
        f"✅ registry ok: {len(registry)} entries, all URLs reachable; "
        f"{len(refs)} unique basenames referenced across workflows"
    )
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
