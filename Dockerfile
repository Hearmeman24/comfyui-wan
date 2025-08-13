# Step 1: Start from the official RunPod ComfyUI base image.
# Using '-base' gives us a clean slate without extra models.
FROM runpod/worker-comfyui:5.1.0-base

# Step 2: Install the custom nodes needed for video generation.
# This uses the 'comfy-node-install' tool that comes with the base image.
RUN comfy-node-install ComfyUI-AnimateDiff-Evolved ComfyUI-VideoHelperSuite ComfyUI-Manager

# Step 3: Download the necessary models using the 'comfy model download' tool.
# We need the main AnimateDiff model and a motion module.

# AnimateDiff V3 Model
RUN comfy model download --url https://huggingface.co/guoyww/animatediff/resolve/main/mm_sd_v15_v2.ckpt \
                         --relative-path models/animatediff_models \
                         --filename mm_sd_v15_v2.ckpt

# A popular motion module for smoother animation
RUN comfy model download --url https://huggingface.co/guoyww/animatediff/resolve/main/v3_sd15_mm.ckpt \
                         --relative-path models/animatediff_models \
                         --filename v3_sd15_mm.ckpt

# A base checkpoint model to generate the video from (e.g., Realistic Vision)
RUN comfy model download --url https://civitai.com/api/download/models/130072 \
                         --relative-path models/checkpoints \
                         --filename realisticVisionV60B1_v51VAE.safetensors

# --- Optional Steps (uncomment and use if needed) ---

# If you need a specific LoRA, uncomment the line below
# RUN comfy model download --url <URL_TO_YOUR_LORA> --relative-path models/loras --filename <YOUR_LORA_NAME>.safetensors

# If you need to add static input files (like an initial video or images)
# 1. Create a folder named 'input' in your GitHub repo.
# 2. Place your files inside it.
# 3. Uncomment the line below.
# COPY input/ /comfyui/input/
