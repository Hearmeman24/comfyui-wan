#!/usr/bin/env python3
"""Shim: run the shared runtime's model validator against this repo.

The real validator lives in comfyui-runtime/tools/validate_models.py (the
reconciled family superset: registry/workflow coverage incl. subgraphs and
folder prefixes, HF model-API existence checks that follow repo renames,
ranged-GET size checks). This shim fetches comfyui-runtime at the exact
`runtime_ref` pinned in pins.json, so CI validates against the runtime this
template actually boots, not whatever sits on the runtime's main.

Extra args (e.g. --offline) pass straight through.

Stdlib only.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
RUNTIME_URL = "https://github.com/Hearmeman24/comfyui-runtime.git"
# Reuse one cached clone across runs.
CACHE = Path.home() / ".cache" / "comfyui-runtime-validator"


def _git(*args: str) -> None:
    subprocess.run(["git", "-C", str(CACHE), *args], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def resolve_runtime(ref: str) -> Path:
    if not (CACHE / ".git").is_dir():
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "--quiet", RUNTIME_URL, str(CACHE)],
                       check=True)
    # Fetch only when the pinned ref is not already local, so repeat runs
    # stay offline once the ref has been seen.
    try:
        _git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    except subprocess.CalledProcessError:
        _git("fetch", "--quiet", "origin", ref)
        ref = "FETCH_HEAD"
    _git("checkout", "--quiet", "--force", ref)
    return CACHE


def runtime_dir() -> Path:
    """The pinned runtime checkout.

    COMFYUI_RUNTIME_DIR points at a local runtime checkout, used AS IS (no
    git ops on it), for working on the two repos side by side. Otherwise
    pins.json's runtime_ref decides; a missing or malformed pins.json is a
    one-line FATAL, never a silent fallback.
    """
    local = os.environ.get("COMFYUI_RUNTIME_DIR")
    if local:
        return Path(local)
    try:
        ref = json.loads((REPO / "pins.json").read_text())["runtime_ref"]
    except (OSError, ValueError, KeyError, TypeError) as e:
        raise SystemExit(
            f"FATAL: could not read runtime_ref from pins.json: {e}")
    try:
        return resolve_runtime(ref)
    except subprocess.CalledProcessError as e:
        raise SystemExit(
            f"FATAL: could not fetch comfyui-runtime at runtime_ref {ref!r}: {e}")


def main() -> int:
    runtime = runtime_dir()
    cmd = [sys.executable, str(runtime / "tools" / "validate_models.py"),
           "--registry", str(REPO / "src" / "models_registry.json"),
           "--workflows", str(REPO / "workflows"),
           "--template", str(REPO / "template.json"),
           *sys.argv[1:]]
    return subprocess.run(cmd).returncode


if __name__ == "__main__":
    raise SystemExit(main())
