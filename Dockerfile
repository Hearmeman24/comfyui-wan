# syntax=docker/dockerfile:1
# ============================================================================
# comfyui-wan template image, built FROM the shared base
# (hearmeman/comfyui-base, comfyui-runtime/base/Dockerfile).
#
# The base owns: python 3.12 + /opt/venv (on PATH), the pinned torch trio +
# /torch-constraint.txt applied via ENV PIP_CONSTRAINT, pip tooling, pyyaml/
# gdown/triton/jupyterlab, huggingface_hub + hf_xet, opencv-python, ComfyUI
# pinned at COMFYUI_REF (v0.32.0) with /comfyui-approved-ref, ComfyUI-Manager,
# both SageAttention wheels under /opt/sage/, the CivitAI downloader, and
# ENV ORT_INDEX_ARGS (the per-CUDA-variant onnxruntime index nuance).
#
# This layer adds ONLY the wan node set, the onnxruntime-gpu reassert, and
# the entrypoint. BASE_IMAGE is passed by CI from pins.json's "base_image";
# the default below mirrors that pin so a plain build stays coherent.
# cu130 only: the cu128 default and the -cuda13 sibling variant are gone
# (spec M-A), so the four CUDA override ARGs the old Dockerfile carried are
# gone with them.
# ============================================================================
ARG BASE_IMAGE=hearmeman/comfyui-base:cu130-comfy0.32.0-torch2.11.0
FROM ${BASE_IMAGE}

# The wan node set, culled 2026-08-13 to the packs the 29 shipped workflows
# actually resolve nodes from, plus the Tier 1 packs kept on every template
# (rgthree-comfy for its UI layer; OpenRouter is boot-cloned via
# template.json's custom_nodes.repos, spec D4, not baked here). Removed from
# the old 30-pack loop, each verified unused by every workflow including
# subgraph definitions (spec grounding section 7): UltimateSDUpscale,
# Comfyroll, comfy-plasma, mikey_nodes, Florence2, LatentSyncWrapper,
# TeaCache, Detail-Daemon, cg-image-picker.
#
# KJNodes and WanVideoWrapper are ALSO in template.json's custom_nodes.repos:
# the runtime's clone loop finds the baked dir and takes its update branch,
# so they keep tracking upstream at boot with no dual clone.
#
# No ADD cache-busters on any pack: none was present before and none of these
# packs version-gates a model release, so pack HEADs freeze in the layer cache
# until this loop line changes, the same deliberate family shape as before.
# PIP_CONSTRAINT (base-owned) applies to every requirements install below.
RUN for repo in \
    https://github.com/kijai/ComfyUI-KJNodes.git \
    https://github.com/rgthree/rgthree-comfy.git \
    https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git \
    https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
    https://github.com/ltdrdata/ComfyUI-Impact-Pack.git \
    https://github.com/Fannovel16/comfyui_controlnet_aux.git \
    https://github.com/yolain/ComfyUI-Easy-Use.git \
    https://github.com/WASasquatch/was-node-suite-comfyui.git \
    https://github.com/theUpsider/ComfyUI-Logic.git \
    https://github.com/cubiq/ComfyUI_essentials.git \
    https://github.com/chflame163/ComfyUI_LayerStyle.git \
    https://github.com/chrisgoringe/cg-use-everywhere.git \
    https://github.com/kijai/ComfyUI-segment-anything-2.git \
    https://github.com/ClownsharkBatwing/RES4LYF \
    https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git \
    https://github.com/kijai/ComfyUI-WanVideoWrapper.git \
    https://github.com/chflame163/ComfyUI_LayerStyle_Advance.git \
    https://github.com/BadCafeCode/masquerade-nodes-comfyui.git \
    https://github.com/1038lab/ComfyUI-RMBG.git \
    https://github.com/M1kep/ComfyLiterals.git \
    https://github.com/city96/ComfyUI-GGUF.git; \
    do \
        cd /ComfyUI/custom_nodes; \
        repo_dir=$(basename "$repo" .git); \
        git clone "$repo"; \
        if [ -f "/ComfyUI/custom_nodes/$repo_dir/requirements.txt" ]; then \
            pip install -r "/ComfyUI/custom_nodes/$repo_dir/requirements.txt"; \
        fi; \
        if [ -f "/ComfyUI/custom_nodes/$repo_dir/install.py" ]; then \
            python "/ComfyUI/custom_nodes/$repo_dir/install.py"; \
        fi; \
    done

# Force GPU onnxruntime. A node requirements file can pull in plain
# `onnxruntime` (CPU), which shadows the GPU install because both provide the
# same `onnxruntime` module and last install wins. This reassert therefore
# comes AFTER the clone loop, and no later RUN may pip install anything
# (comfyui-runtime base Dockerfile, onnxruntime ordering trap). ORT_INDEX_ARGS
# is base-owned data: the Azure onnxruntime-cuda-12 index on cu128, empty on
# cu130 where PyPI's onnxruntime-gpu links CUDA 13.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip uninstall -y onnxruntime onnxruntime-gpu 2>/dev/null || true; \
    pip install onnxruntime-gpu $ORT_INDEX_ARGS

# Build-time gate: the shipped image must expose the CUDA provider. Provider
# enumeration is import-only and works with no GPU present, so this fails the
# CI build, not a customer pod. CI greps this Dockerfile for the
# CUDAExecutionProvider assertion and for the no-pip-install-after-it rule.
RUN python3 -c "import onnxruntime; p = onnxruntime.get_available_providers(); assert 'CUDAExecutionProvider' in p, p; print('onnxruntime providers OK:', p)"

COPY src/start_script.sh /start_script.sh
RUN chmod +x /start_script.sh

CMD ["/start_script.sh"]
