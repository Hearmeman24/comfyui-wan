# Contract — CUDA 13 + NVFP4 experimental image tag

Work type: **feature / infra**. Backwards compatibility of the cu128 path is the spine.

## 1. Problem
`comfyui-wan` ships a single CUDA 12.8 image (`Dockerfile:2`, `--index-url .../nightly/cu128`
at `Dockerfile:31-32`). NVFP4 quant loading requires cu130 torch + cuBLAS 13.x (on cu128 cuBLAS
returns `NOT_SUPPORTED` and ComfyUI falls back to fp16/fp8). Users want an opt-in cutting-edge
image without breaking the heavily-used cu128 template.

## 2. Approach (cited)
- **Two images from one git tag.** CI currently builds one image: `TAG="${CIRCLE_TAG:-latest}"`,
  `docker build -t comfyui-wan-template:${TAG}` then pushes + refreshes a `buildcache` tag
  (`.circleci/config.yml`, `build_and_push` job). Add a second `docker build` with cu130 build-args →
  `:${TAG}-cuda13`, using a distinct `buildcache-cuda13` cache tag.
- **One parametrized Dockerfile.** Today's base/torch are hardcoded (`Dockerfile:2`, `:31-32`).
  Introduce ARGs whose **defaults equal the current literals**, so a no-arg build is content-identical.
- **Shared `src/start.sh` with wheel-probe + source-build fallback.** Today start.sh builds sage from
  source in the background unconditionally (`src/start.sh:16-28`), waits on it (`:382-394`), and
  launches with a hardcoded `--use-sage-attention` (`:400`). Replace with: try baked wheel first on
  the cu130 variant; fall back to the existing source build; gate the launch flag on actual sage
  availability.
- **Reuse the prebuilt wheel.** `remote_comfy_generator/serverless-docker/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl`
  (cp312, torch 2.11.0+cu130, arch `8.0;8.9;12.0`). This repo uses python3.12 (`Dockerfile:14,20`) →
  cp312 match. Pin cu130 torch to `2.11.0`/`0.26.0`/`2.11.0` to match the wheel (same pins as
  `remote_comfy_generator/serverless-docker/Dockerfile:42`).

## 3. Acceptance criteria
1. **(outcome)** A user pulling `comfyui-wan-template:vN-cuda13` gets a CUDA 13 ComfyUI where NVFP4
   quants load natively on Blackwell sm_120; `comfyui-wan-template:vN` is byte-equivalent in content
   to the pre-change cu128 build.
2. cu130 image: a Dockerfile import-probe asserts `torch.version.cuda` starts with `13` and
   `import sageattention` succeeds (fail the build otherwise).
3. cu130 runtime, supported GPU: `start.sh` installs the baked wheel, the import+kernel probe passes,
   no source build runs, ComfyUI launches with `--use-sage-attention`.
4. cu130 runtime, unsupported GPU (wheel probe fails): `start.sh` falls back to the source build; if
   that also yields no working sage, ComfyUI launches **without** the flag (never crashes on it).
5. cu128 image (default build): start.sh behavior is unchanged — background source build, then launch.
6. CI publishes both `:vN` and `:vN-cuda13` on a `vN` git tag, each refreshing its own buildcache tag.

## 4. Non-goals
- No change to `docker-bake.hcl` (stale/unused — wrong repo `timpietruskyblibla/runpod-worker-comfy`,
  `MODEL_TYPE` arg absent from Dockerfile; CI does not invoke bake).
- No `nodes.lock` SHA pinning. No serverless handler. No rebuild of the sage wheel.
- No change to the custom-node list.

## 5. Scale / risk
Build-time only: CI now builds two images per tag (~2× build minutes; mitigated by separate
buildcache tags + DLC). Runtime: cu130 wheel path removes the ~5-min cold-start sage build for
supported GPUs; unsupported GPUs keep today's cold start. No request-path scale concern (template,
not a service).

## 6. Files to change
| File | Change |
|---|---|
| `Dockerfile` | Add ARGs: `CUDA_BASE_IMAGE` (default `nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04`), `TORCH_PACKAGES` (default `--pre torch torchvision torchaudio`), `TORCH_INDEX_URL` (default `https://download.pytorch.org/whl/nightly/cu128`), `CUDA_VARIANT` (default `cu128`). `FROM ${CUDA_BASE_IMAGE} AS base`. Torch install line uses the two ARGs. `ENV CUDA_VARIANT=${CUDA_VARIANT}`. After torch install, freeze `torch/torchvision/torchaudio/torchsde` to `/torch-constraint.txt` and pass `--constraint /torch-constraint.txt` in the custom-node `pip install` loop (`Dockerfile:107-109`). Always `COPY` the wheel to `/opt/sage/`. Add a final import-probe `RUN` that, when `CUDA_VARIANT=cu130`, asserts torch CUDA 13 + `import sageattention`. |
| `sageattention-2.2.0-cp312-cp312-linux_x86_64.whl` | New — copy from `remote_comfy_generator/serverless-docker/`. Committed at repo root (next to `4xLSDIR.pth`). |
| `src/start.sh` | Replace the unconditional background sage build (`:16-28`), wait (`:382-394`), and launch flag (`:400`) with: (a) `SAGE_FLAG=""`; (b) if `CUDA_VARIANT=cu130` and `/opt/sage/*.whl` present → `pip install --no-deps` it, then run an import+kernel probe (mirror `remote_comfy_generator/serverless-runtime/start.sh:93-99`); on pass set `SAGE_FLAG=--use-sage-attention` and skip build; (c) else kick off the existing source build in background, wait for it, probe, set `SAGE_FLAG` if it works; (d) launch with `$SAGE_FLAG` instead of hardcoded flag. Make the `:413-415` troubleshooting text variant-aware (don't tell cu130 users to pick CUDA 12.8; drop the B200 line for cu130). |
| `.circleci/config.yml` | After the existing build/push, add a second build with `--build-arg CUDA_BASE_IMAGE=nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04 --build-arg TORCH_PACKAGES="torch==2.11.0 torchvision==0.26.0 torchaudio==2.11.0" --build-arg TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130 --build-arg CUDA_VARIANT=cu130`, tag `:${TAG}-cuda13`, push, and refresh a `buildcache-cuda13` cache tag (use `--cache-from`/`--cache-to` against `buildcache-cuda13`, not the cu128 `buildcache`). |
| `README.md` | One section documenting the `-cuda13` opt-in tag + the Blackwell/NVFP4 caveat. |

## 7. Dispatch
Small, tightly-coupled change — **freeze the shared interface first, then implement inline** (a
parallel fan-out is not worth it for ~5 files that share these contract symbols).

**Frozen interface (all files must agree on these literals):**
- ENV/ARG name: `CUDA_VARIANT`, values `cu128` | `cu130`.
- Baked wheel path in image: `/opt/sage/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl`.
- cu130 torch pins: `torch==2.11.0 torchvision==0.26.0 torchaudio==2.11.0`, index `.../whl/cu130`.
- cu130 base image: `nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04`.
- Image tags: `${TAG}` (cu128) and `${TAG}-cuda13`; cache tags `buildcache` and `buildcache-cuda13`.

```yaml
dispatch:
  frozen:
    - "Dockerfile: ARG/ENV CUDA_VARIANT + wheel path /opt/sage/ + cu130 torch pins"
  slices:
    - id: dockerfile
      writes: [Dockerfile, sageattention-2.2.0-cp312-cp312-linux_x86_64.whl]
    - id: runtime
      writes: [src/start.sh]
    - id: ci
      writes: [.circleci/config.yml]
    - id: docs
      writes: [README.md]
  testRunner: "docker build (cu128 default) + docker build --build-arg CUDA_VARIANT=cu130 ...; assert import-probe passes"
```

## 8. Assumptions (open)
- The committed cp312 sage wheel imports + runs under `torch 2.11.0+cu130` on this image (verified in
  `remote_comfy_generator`, not re-verified here).
- NVFP4 needs no extra ComfyUI flag on cu130 (per serverless Dockerfile `:36-39` notes).
- thu-ml SHA `68de379` compiles under cu130 nvcc on a non-wheel GPU (fallback path, untested).
- `--cache-from/--cache-to` style needed for the second cache tag works with the machine-executor DLC
  build as currently configured (the existing job uses `BUILDKIT_INLINE_CACHE=1` + `--cache-from`;
  replicate that pattern for `buildcache-cuda13`).
