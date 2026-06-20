# Spec — CUDA 13 + NVFP4 experimental image tag

**30-second review surface.** Full contract in `spec.claude.md`.

## What you'll get
A second image published from each `vN` git tag:
- `comfyui-wan-template:vN` — **CUDA 12.8, unchanged.** Your whole user base keeps pulling this.
- `comfyui-wan-template:vN-cuda13` — **CUDA 13.0 + torch cu130 + NVFP4.** Users opt in by appending `-cuda13`.

On the `-cuda13` image, `start.sh` installs a **baked SageAttention cu130 wheel** and skips the
5-minute build — *if* it imports and a real kernel launches on the worker's GPU. If that probe fails
(unsupported GPU, e.g. B200/sm_100, or a cu128 image), it falls back to the **existing source build**.
NVFP4 quants load natively on Blackwell consumer GPUs (sm_120); on other GPUs they degrade to fp16/fp8.

## ⚠️ Decisions you're approving
1. **One parametrized Dockerfile, not two.** ARGs default to today's cu128 values, so a plain
   `docker build` yields the **same** cu128 image content. cu130 is the same file with 4 build-args
   overridden. *Alternative: a separate `Dockerfile.cuda13` (zero risk to the proven file, but two
   node-lists drift apart).* — chose single-file to avoid maintenance drift.
2. **torch-constraint guard becomes always-on** (freeze torch after install, pass `--constraint` to
   every custom-node `pip install`). This *touches the cu128 image*: a node that today silently
   upgrades torch would now be pinned. Low risk, arguably a latent-bug fix — but it is a change to the
   proven image. *Alternative: cu130-only, via conditional Dockerfile branching (uglier).*
3. **Reuse the committed wheel** from `remote_comfy_generator` as-is, and **pin cu130 torch to
   2.11.0** to match it (cp312 / sm_80;8.9;12.0). If you ever bump that torch pin, the wheel must be
   rebuilt.
4. **Tag scheme:** suffix `-cuda13` on the same `vN` git tag; CI builds both images per tag.

## ✂️ Not asked for — cut
- Touching `docker-bake.hcl` — it's **stale/unused** (wrong repo name, `MODEL_TYPE` arg the Dockerfile
  doesn't have; CI uses plain `docker build`). Left alone. **Cut.**
- A `nodes.lock` SHA-pinning system like the serverless repo. Out of scope. **Cut.**
- Rebuilding the sage wheel. **Cut** (reusing existing).

## 🎲 Riding on these assumptions
- The committed `sageattention-2.2.0-cp312-cp312` wheel works against `torch 2.11.0+cu130` on this
  image's python3.12 — verified in `remote_comfy_generator`, assumed transferable here.
- cu130 base image `nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04` + `torch==2.11.0+cu130` is the same
  proven combo as the serverless repo.
- NVFP4 needs no ComfyUI flag — cu130 torch + cuBLAS 13 enables it automatically (per the serverless
  repo's Dockerfile notes). **Not independently re-verified here.**
- The runtime source-build fallback (thu-ml SHA `68de379`) compiles under the cu130 toolchain on a
  GPU not covered by the wheel. Assumed; only exercised on the failure path.

## 🪤 Gotchas
- `start.sh:400` passes `--use-sage-attention` **unconditionally** today → must become `$SAGE_FLAG`.
- `start.sh:413-415` troubleshooting text ("set CUDA to 12.8/12.9", "B200 not supported") is wrong on
  the cu130 path → make variant-aware.
- CI cache: the two images need **separate buildcache tags** or they thrash each other's layer cache.

## How we'll know it works
1. `:vN-cuda13` builds green; import-probe in Dockerfile passes (torch reports CUDA 13.x, sage imports).
2. `:vN` image content is unchanged vs the last release (same base + torch).
3. On a cu130 worker with a supported GPU: log shows "wheel probe passed — skipping build"; ComfyUI
   starts with sage. On an unsupported GPU: log shows fallback to source build; ComfyUI still starts.
