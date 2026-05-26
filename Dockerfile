# Use multi-stage build with caching optimizations
FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04 AS base

# Consolidated environment variables
ENV DEBIAN_FRONTEND=noninteractive \
   PIP_PREFER_BINARY=1 \
   PYTHONUNBUFFERED=1 \
   CMAKE_BUILD_PARALLEL_LEVEL=8 \
   HF_XET_HIGH_PERFORMANCE=1

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.12 python3.12-venv python3.12-dev \
        python3-pip \
        curl ffmpeg ninja-build git aria2 git-lfs wget vim \
        libgl1 libglib2.0-0 build-essential gcc && \
    \
    # make Python3.12 the default python & pip
    ln -sf /usr/bin/python3.12 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip && \
    \
    python3.12 -m venv /opt/venv && \
    \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Use the virtual environment
ENV PATH="/opt/venv/bin:$PATH"

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --pre torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/nightly/cu128

# Core Python tooling
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install packaging setuptools wheel

# Runtime libraries
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install pyyaml gdown triton jupyterlab jupyterlab-lsp \
        jupyter-server jupyter-server-terminals \
        ipykernel jupyterlab_code_formatter

# huggingface_hub (provides `hf` CLI + bundled hf_xet accelerator)
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --upgrade huggingface_hub

# ------------------------------------------------------------
# ComfyUI install — direct clone + pip install. Replaces comfy-cli,
# which used to clone the same repo and create a private .venv we then
# deleted anyway. Simpler, fewer indirection layers, no ~7 GB .venv.
# ------------------------------------------------------------
RUN --mount=type=cache,target=/root/.cache/pip \
    git clone --depth=1 https://github.com/comfyanonymous/ComfyUI.git /ComfyUI \
    && pip install -r /ComfyUI/requirements.txt

FROM base AS final
# Make sure to use the virtual environment here too
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install opencv-python

RUN for repo in \
    https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git \
    https://github.com/kijai/ComfyUI-KJNodes.git \
    https://github.com/rgthree/rgthree-comfy.git \
    https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git \
    https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git \
    https://github.com/Jordach/comfy-plasma.git \
    https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git \
    https://github.com/bash-j/mikey_nodes.git \
    https://github.com/ltdrdata/ComfyUI-Impact-Pack.git \
    https://github.com/Fannovel16/comfyui_controlnet_aux.git \
    https://github.com/yolain/ComfyUI-Easy-Use.git \
    https://github.com/kijai/ComfyUI-Florence2.git \
    https://github.com/ShmuelRonen/ComfyUI-LatentSyncWrapper.git \
    https://github.com/WASasquatch/was-node-suite-comfyui.git \
    https://github.com/theUpsider/ComfyUI-Logic.git \
    https://github.com/cubiq/ComfyUI_essentials.git \
    https://github.com/chrisgoringe/cg-image-picker.git \
    https://github.com/chflame163/ComfyUI_LayerStyle.git \
    https://github.com/chrisgoringe/cg-use-everywhere.git \
    https://github.com/kijai/ComfyUI-segment-anything-2.git \
    https://github.com/ClownsharkBatwing/RES4LYF \
    https://github.com/welltop-cn/ComfyUI-TeaCache.git \
    https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git \
    https://github.com/Jonseed/ComfyUI-Detail-Daemon.git \
    https://github.com/kijai/ComfyUI-WanVideoWrapper.git \
    https://github.com/chflame163/ComfyUI_LayerStyle_Advance.git \
    https://github.com/BadCafeCode/masquerade-nodes-comfyui.git \
    https://github.com/1038lab/ComfyUI-RMBG.git \
    https://github.com/M1kep/ComfyLiterals.git \
    https://github.com/city96/ComfyUI-GGUF.git; \
    do \
        cd /ComfyUI/custom_nodes; \
        repo_dir=$(basename "$repo" .git); \
        if [ "$repo" = "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git" ]; then \
            git clone --recursive "$repo"; \
        else \
            git clone "$repo"; \
        fi; \
        if [ -f "/ComfyUI/custom_nodes/$repo_dir/requirements.txt" ]; then \
            pip install -r "/ComfyUI/custom_nodes/$repo_dir/requirements.txt"; \
        fi; \
        if [ -f "/ComfyUI/custom_nodes/$repo_dir/install.py" ]; then \
            python "/ComfyUI/custom_nodes/$repo_dir/install.py"; \
        fi; \
    done

# Force GPU onnxruntime. Several custom node requirements.txt files
# pull in plain `onnxruntime` (CPU) which shadows our GPU install
# because both packages provide the same `onnxruntime` Python module —
# last install wins. Reinstalling after the clone loop guarantees the
# image ships with the CUDA provider available.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip uninstall -y onnxruntime onnxruntime-gpu 2>/dev/null || true; \
    pip install onnxruntime-gpu

# ComfyUI-Manager. Cloned as lowercase `comfyui-manager` so it loads
# after the other custom_nodes (ComfyUI loads alphabetically — capital
# letters first), which is required for Manager to detect IMPORT FAILED
# states in earlier-loaded nodes.
RUN --mount=type=cache,target=/root/.cache/pip \
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git \
        /ComfyUI/custom_nodes/comfyui-manager \
    && if [ -f /ComfyUI/custom_nodes/comfyui-manager/requirements.txt ]; then \
         pip install -r /ComfyUI/custom_nodes/comfyui-manager/requirements.txt; \
       fi

COPY src/start_script.sh /start_script.sh
RUN chmod +x /start_script.sh
COPY 4xLSDIR.pth /4xLSDIR.pth

CMD ["/start_script.sh"]
