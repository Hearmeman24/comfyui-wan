#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# This is in case there's any special installs or overrides that needs to occur when starting the machine before starting ComfyUI
if [ -f "/workspace/additional_params.sh" ]; then
    chmod +x /workspace/additional_params.sh
    echo "Executing additional_params.sh..."
    /workspace/additional_params.sh
else
    echo "additional_params.sh not found in /workspace. Skipping..."
fi

if ! which aria2 > /dev/null 2>&1; then
    echo "Installing aria2..."
    apt-get update && apt-get install -y aria2
else
    echo "aria2 is already installed"
fi

if ! which curl > /dev/null 2>&1; then
    echo "Installing curl..."
    apt-get update && apt-get install -y curl
else
    echo "curl is already installed"
fi

# Start SageAttention build in the background
echo "Starting SageAttention build..."
(
    export EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" MAX_JOBS=32
    cd /tmp
    git clone https://github.com/thu-ml/SageAttention.git
    cd SageAttention
    git reset --hard 68de379
    pip install -e .
    echo "SageAttention build completed" > /tmp/sage_build_done
) > /tmp/sage_build.log 2>&1 &
SAGE_PID=$!
echo "SageAttention build started in background (PID: $SAGE_PID)"

# Set the network volume path
NETWORK_VOLUME="/workspace"
URL="http://127.0.0.1:8188"

# Check if NETWORK_VOLUME exists; if not, use root directory instead
if [ ! -d "$NETWORK_VOLUME" ]; then
    echo "NETWORK_VOLUME directory '$NETWORK_VOLUME' does not exist. You are NOT using a network volume. Setting NETWORK_VOLUME to '/' (root directory)."
    NETWORK_VOLUME="/"
    echo "NETWORK_VOLUME directory doesn't exist. Starting JupyterLab on root directory..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/ &
else
    echo "NETWORK_VOLUME directory exists. Starting JupyterLab..."
    jupyter-lab --ip=0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --ServerApp.allow_origin='*' --ServerApp.allow_credentials=True --notebook-dir=/workspace &
fi

COMFYUI_DIR="$NETWORK_VOLUME/ComfyUI"
WORKFLOW_DIR="$NETWORK_VOLUME/ComfyUI/user/default/workflows"

# Set the target directory
CUSTOM_NODES_DIR="$NETWORK_VOLUME/ComfyUI/custom_nodes"

if [ ! -d "$COMFYUI_DIR" ]; then
    mv /ComfyUI "$COMFYUI_DIR"
else
    echo "Directory already exists, skipping move."
fi

echo "Downloading CivitAI download script to /usr/local/bin"
git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" || { echo "Git clone failed"; exit 1; }
mv CivitAI_Downloader/download_with_aria.py "/usr/local/bin/" || { echo "Move failed"; exit 1; }
chmod +x "/usr/local/bin/download_with_aria.py" || { echo "Chmod failed"; exit 1; }
rm -rf CivitAI_Downloader  # Clean up the cloned repo
pip install onnxruntime-gpu &

if [ ! -d "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanVideoWrapper" ]; then
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git
else
    echo "Updating WanVideoWrapper"
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanVideoWrapper
    git pull
fi
if [ ! -d "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-KJNodes" ]; then
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes
    git clone https://github.com/kijai/ComfyUI-KJNodes.git
else
    echo "Updating KJ Nodes"
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-KJNodes
    git pull
fi

if [ ! -d "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-VibeVoice" ]; then
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes
    git clone https://github.com/wildminder/ComfyUI-VibeVoice.git
else
    echo "Updating VibeVoice"
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-VibeVoice
    git pull
fi

if [ ! -d "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanAnimatePreprocess" ]; then
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes
    git clone https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git
else
    echo "Updating WanAnimatePreprocess"
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanAnimatePreprocess
    git pull
fi


if [ ! -d "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-FSampler" ]; then
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes
    git clone https://github.com/obisin/ComfyUI-FSampler.git
else
    echo "Updating FSampler"
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-FSampler
    git pull
fi

if [ ! -d "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanMoEScheduler" ]; then
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes
    git clone https://github.com/cmeka/ComfyUI-WanMoEScheduler.git
else
    echo "Updating WanMoEScheduler"
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanMoEScheduler
    git pull
fi

if [ ! -d "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-VAE-Utils" ]; then
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes
    git clone https://github.com/lrzjason/ComfyUI-VAE-Utils.git
else
    echo "Updating VAE Utils"
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-VAE-Utils
    git pull
fi

if [ ! -d "$NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-Wan22FMLF" ]; then
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes
    git clone https://github.com/wallen0322/ComfyUI-Wan22FMLF.git
else
    echo "Updating Wan22FMLF"
    cd $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-Wan22FMLF
    git pull
fi


echo "🔧 Installing KJNodes packages..."
pip install --no-cache-dir -r $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-KJNodes/requirements.txt &
KJ_PID=$!

echo "🔧 Installing WanVideoWrapper packages..."
pip install --no-cache-dir -r $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanVideoWrapper/requirements.txt &
WAN_PID=$!

echo "🔧 Installing VibeVoice packages..."
pip install --no-cache-dir -r $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-VibeVoice/requirements.txt &
VIBE_PID=$!

echo "🔧 Installing WanAnimatePreprocess packages..."
pip install --no-cache-dir -r $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-WanAnimatePreprocess/requirements.txt &
WAN_ANIMATE_PID=$!


export change_preview_method="true"


# Change to the directory
cd "$CUSTOM_NODES_DIR" || exit 1

# Function to download a model using huggingface-cli
download_model() {
    local url="$1"
    local full_path="$2"

    local destination_dir=$(dirname "$full_path")
    local destination_file=$(basename "$full_path")

    mkdir -p "$destination_dir"

    # Simple corruption check: file < 10MB or .aria2 files
    if [ -f "$full_path" ]; then
        local size_bytes=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo 0)
        local size_mb=$((size_bytes / 1024 / 1024))

        if [ "$size_bytes" -lt 10485760 ]; then  # Less than 10MB
            echo "🗑️  Deleting corrupted file (${size_mb}MB < 10MB): $full_path"
            rm -f "$full_path"
        else
            echo "✅ $destination_file already exists (${size_mb}MB), skipping download."
            return 0
        fi
    fi

    # Check for and remove .aria2 control files
    if [ -f "${full_path}.aria2" ]; then
        echo "🗑️  Deleting .aria2 control file: ${full_path}.aria2"
        rm -f "${full_path}.aria2"
        rm -f "$full_path"  # Also remove any partial file
    fi

    echo "📥 Downloading $destination_file to $destination_dir..."

    # Download without falloc (since it's not supported in your environment)
    aria2c -x 16 -s 16 -k 1M --continue=true -d "$destination_dir" -o "$destination_file" "$url" &

    echo "Download started in background for $destination_file"
}

# Define base paths
DIFFUSION_MODELS_DIR="$NETWORK_VOLUME/ComfyUI/models/diffusion_models"
TEXT_ENCODERS_DIR="$NETWORK_VOLUME/ComfyUI/models/text_encoders"
CLIP_VISION_DIR="$NETWORK_VOLUME/ComfyUI/models/clip_vision"
VAE_DIR="$NETWORK_VOLUME/ComfyUI/models/vae"
LORAS_DIR="$NETWORK_VOLUME/ComfyUI/models/loras"
DETECTION_DIR="$NETWORK_VOLUME/ComfyUI/models/detection"

# Download 480p native models
if [ "$download_480p_native_models" == "true" ]; then
  echo "Downloading 480p native models..."
  download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_i2v_480p_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_i2v_480p_14B_bf16.safetensors"
  download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_14B_bf16.safetensors"
  download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_1.3B_bf16.safetensors"
fi

if [ "$debug_models" == "true" ]; then
  echo "Downloading 480p native models..."
  download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_i2v_480p_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_i2v_480p_14B_fp16.safetensors"
fi

# Handle full download (with SDXL)
if [ "$download_wan_fun_and_sdxl_helper" == "true" ]; then
  echo "Downloading Wan Fun 14B Model"

  download_model "https://huggingface.co/alibaba-pai/Wan2.1-Fun-14B-Control/resolve/main/diffusion_pytorch_model.safetensors" "$DIFFUSION_MODELS_DIR/diffusion_pytorch_model.safetensors"

  UNION_DIR="$NETWORK_VOLUME/ComfyUI/models/controlnet/SDXL/controlnet-union-sdxl-1.0"
  mkdir -p "$UNION_DIR"
  if [ ! -f "$UNION_DIR/diffusion_pytorch_model_promax.safetensors" ]; then
    download_model "https://huggingface.co/xinsir/controlnet-union-sdxl-1.0/resolve/main/diffusion_pytorch_model_promax.safetensors" "$UNION_DIR/diffusion_pytorch_model_promax.safetensors"
  fi
fi


if [ "$download_wan22" == "true" ]; then
  echo "Downloading Wan 2.2"

  download_model "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_t2v_high_noise_14B_fp16.safetensors"

  download_model "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_t2v_low_noise_14B_fp16.safetensors"

  download_model "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_i2v_high_noise_14B_fp16.safetensors"

  download_model "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_i2v_low_noise_14B_fp16.safetensors"

  download_model "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_ti2v_5B_fp16.safetensors"

  download_model "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan2.2_vae.safetensors" "$VAE_DIR/wan2.2_vae.safetensors"
  
fi


if [ "$download_vace" == "true" ]; then
  echo "Downloading Wan 1.3B and 14B"

  download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_1.3B_bf16.safetensors"

  download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_14B_bf16.safetensors"

  echo "Downloading VACE 14B Model"

  download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1-VACE_module_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/Wan2_1-VACE_module_14B_bf16.safetensors"

  download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1-VACE_module_1_3B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/Wan2_1-VACE_module_1_3B_bf16.safetensors"

fi

if [ "$download_vace_debug" == "true" ]; then
  download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_vace_14B_fp16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_vace_14B_fp16.safetensors"
fi

# Download 720p native models
if [ "$download_720p_native_models" == "true" ]; then
  echo "Downloading 720p native models..."

  download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_i2v_720p_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_i2v_720p_14B_bf16.safetensors"

  download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_14B_bf16.safetensors"

  download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.1_t2v_1.3B_bf16.safetensors"
fi

# Download Wan Animate model
if [ "$download_wan_animate" == "true" ]; then
  echo "Downloading Wan Animate model..."

  download_model "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_animate_14B_bf16.safetensors" "$DIFFUSION_MODELS_DIR/wan2.2_animate_14B_bf16.safetensors"
fi

# Download Steady Dancer model
if [ "$download_steady_dancer" == "true" ]; then
  echo "Downloading Steady Dancer model..."

  download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/SteadyDancer/Wan21_I2V_SteadyDancer_fp16.safetensors" "$DIFFUSION_MODELS_DIR/Wan21_I2V_SteadyDancer_fp16.safetensors"
fi

echo "Downloading InfiniteTalk model"
download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/InfiniteTalk/Wan2_1-InfiniTetalk-Single_fp16.safetensors" "$DIFFUSION_MODELS_DIR/Wan2_1-InfiniTetalk-Single_fp16.safetensors"

echo "Downloading optimization loras"
download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_CausVid_14B_T2V_lora_rank32.safetensors" "$LORAS_DIR/Wan21_CausVid_14B_T2V_lora_rank32.safetensors"
download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors" "$LORAS_DIR/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors"
download_model "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_animate_14B_relight_lora_bf16.safetensors" "$LORAS_DIR/wan2.2_animate_14B_relight_lora_bf16.safetensors"
download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors" "$LORAS_DIR/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors"
download_model "https://huggingface.co/lightx2v/Wan2.2-Lightning/resolve/main/Wan2.2-T2V-A14B-4steps-lora-rank64-Seko-V1.1/high_noise_model.safetensors" "$LORAS_DIR/t2v_lightx2v_high_noise_model.safetensors"
download_model "https://huggingface.co/lightx2v/Wan2.2-Lightning/resolve/main/Wan2.2-T2V-A14B-4steps-lora-rank64-Seko-V1.1/low_noise_model.safetensors" "$LORAS_DIR/t2v_lightx2v_low_noise_model.safetensors"
download_model "https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/main/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors" "$LORAS_DIR/i2v_lightx2v_high_noise_model.safetensors"
download_model "https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/main/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors" "$LORAS_DIR/i2v_lightx2v_low_noise_model.safetensors"
download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Stable-Video-Infinity/v2.0/SVI_v2_PRO_Wan2.2-I2V-A14B_HIGH_lora_rank_128_fp16.safetensors" "$LORAS_DIR/SVI_v2_PRO_Wan2.2-I2V-A14B_HIGH_lora_rank_128_fp16.safetensors"
download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Stable-Video-Infinity/v2.0/SVI_v2_PRO_Wan2.2-I2V-A14B_LOW_lora_rank_128_fp16.safetensors" "$LORAS_DIR/SVI_v2_PRO_Wan2.2-I2V-A14B_LOW_lora_rank_128_fp16.safetensors"

# Download text encoders
echo "Downloading text encoders..."

download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$TEXT_ENCODERS_DIR/umt5_xxl_fp8_e4m3fn_scaled.safetensors"

download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors" "$TEXT_ENCODERS_DIR/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors"

download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-bf16.safetensors" "$TEXT_ENCODERS_DIR/umt5-xxl-enc-bf16.safetensors"

# Create CLIP vision directory and download models
mkdir -p "$CLIP_VISION_DIR"
download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" "$CLIP_VISION_DIR/clip_vision_h.safetensors"

# Download VAE
echo "Downloading VAE..."
download_model "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors" "$VAE_DIR/Wan2_1_VAE_bf16.safetensors"

download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "$VAE_DIR/wan_2.1_vae.safetensors"

download_model "https://huggingface.co/spacepxl/Wan2.1-VAE-upscale2x/resolve/main/Wan2.1_VAE_upscale2x_imageonly_real_v1.safetensors" "$VAE_DIR/Wan2.1_VAE_upscale2x_imageonly_real_v1.safetensors"

# Download detection models for WanAnimatePreprocess
echo "Downloading detection models..."
mkdir -p "$DETECTION_DIR"
download_model "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx" "$DETECTION_DIR/yolov10m.onnx"
download_model "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_data.bin" "$DETECTION_DIR/vitpose_h_wholebody_data.bin"
download_model "https://huggingface.co/Kijai/vitpose_comfy/resolve/main/onnx/vitpose_h_wholebody_model.onnx" "$DETECTION_DIR/vitpose_h_wholebody_model.onnx"

# Keep checking until no aria2c processes are running
while pgrep -x "aria2c" > /dev/null; do
    echo "🔽 Model Downloads still in progress..."
    sleep 5  # Check every 5 seconds
done

declare -A MODEL_CATEGORIES=(
    ["$NETWORK_VOLUME/ComfyUI/models/checkpoints"]="$CHECKPOINT_IDS_TO_DOWNLOAD"
    ["$NETWORK_VOLUME/ComfyUI/models/loras"]="$LORAS_IDS_TO_DOWNLOAD"
)

# Counter to track background jobs
download_count=0

# Ensure directories exist and schedule downloads in background
for TARGET_DIR in "${!MODEL_CATEGORIES[@]}"; do
    mkdir -p "$TARGET_DIR"
    MODEL_IDS_STRING="${MODEL_CATEGORIES[$TARGET_DIR]}"

    # Skip if the value is the default placeholder
    if [[ "$MODEL_IDS_STRING" == "replace_with_ids" ]]; then
        echo "⏭️  Skipping downloads for $TARGET_DIR (default value detected)"
        continue
    fi

    IFS=',' read -ra MODEL_IDS <<< "$MODEL_IDS_STRING"

    for MODEL_ID in "${MODEL_IDS[@]}"; do
        sleep 1
        echo "🚀 Scheduling download: $MODEL_ID to $TARGET_DIR"
        (cd "$TARGET_DIR" && download_with_aria.py -m "$MODEL_ID") &
        ((download_count++))
    done
done

echo "📋 Scheduled $download_count downloads in background"

# Wait for all downloads to complete
echo "⏳ Waiting for downloads to complete..."
while pgrep -x "aria2c" > /dev/null; do
    echo "🔽 LoRA Downloads still in progress..."
    sleep 5  # Check every 5 seconds
done


echo "✅ All models downloaded successfully!"

echo "All downloads completed!"


echo "Downloading upscale models"
mkdir -p "$NETWORK_VOLUME/ComfyUI/models/upscale_models"
if [ ! -f "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xLSDIR.pth" ]; then
    if [ -f "/4xLSDIR.pth" ]; then
        mv "/4xLSDIR.pth" "$NETWORK_VOLUME/ComfyUI/models/upscale_models/4xLSDIR.pth"
        echo "Moved 4xLSDIR.pth to the correct location."
    else
        echo "4xLSDIR.pth not found in the root directory."
    fi
else
    echo "4xLSDIR.pth already exists. Skipping."
fi

echo "Finished downloading models!"


echo "Checking and copying workflow..."
mkdir -p "$WORKFLOW_DIR"

# Ensure the file exists in the current directory before moving it
cd /

SOURCE_DIR="/comfyui-wan/workflows"

# Ensure destination directory exists
mkdir -p "$WORKFLOW_DIR"

SOURCE_DIR="/comfyui-wan/workflows"

# Ensure destination directory exists
mkdir -p "$WORKFLOW_DIR"

# Loop over each subdirectory in the source directory
for dir in "$SOURCE_DIR"/*/; do
    # Skip if no directories match (empty glob)
    [[ -d "$dir" ]] || continue

    dir_name="$(basename "$dir")"
    dest_dir="$WORKFLOW_DIR/$dir_name"

    if [[ -e "$dest_dir" ]]; then
        echo "Directory already exists in destination. Deleting source: $dir"
        rm -rf "$dir"
    else
        echo "Moving: $dir to $WORKFLOW_DIR"
        mv "$dir" "$WORKFLOW_DIR/"
    fi
done

if [ "$change_preview_method" == "true" ]; then
    echo "Updating default preview method..."
    sed -i '/id: *'"'"'VHS.LatentPreview'"'"'/,/defaultValue:/s/defaultValue: false/defaultValue: true/' $NETWORK_VOLUME/ComfyUI/custom_nodes/ComfyUI-VideoHelperSuite/web/js/VHS.core.js
    CONFIG_PATH="/ComfyUI/user/default/ComfyUI-Manager"
    CONFIG_FILE="$CONFIG_PATH/config.ini"

# Ensure the directory exists
mkdir -p "$CONFIG_PATH"

# Create the config file if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Creating config.ini..."
    cat <<EOL > "$CONFIG_FILE"
[default]
preview_method = auto
git_exe =
use_uv = False
channel_url = https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main
share_option = all
bypass_ssl = False
file_logging = True
component_policy = workflow
update_policy = stable-comfyui
windows_selector_event_loop_policy = False
model_download_by_agent = False
downgrade_blacklist =
security_level = normal
skip_migration_check = False
always_lazy_install = False
network_mode = public
db_mode = cache
EOL
else
    echo "config.ini already exists. Updating preview_method..."
    sed -i 's/^preview_method = .*/preview_method = auto/' "$CONFIG_FILE"
fi
echo "Config file setup complete!"
    echo "Default preview method updated to 'auto'"
else
    echo "Skipping preview method update (change_preview_method is not 'true')."
fi

# Workspace as main working directory
echo "cd $NETWORK_VOLUME" >> ~/.bashrc


# Install dependencies
wait $KJ_PID
  KJ_STATUS=$?

wait $WAN_PID
WAN_STATUS=$?

wait $VIBE_PID
VIBE_STATUS=$?

wait $WAN_ANIMATE_PID
WAN_ANIMATE_STATUS=$?

echo "✅ KJNodes install complete"
echo "✅ WanVideoWrapper install complete"
echo "✅ VibeVoice install complete"
echo "✅ WanAnimatePreprocess install complete"

# Check results
if [ $KJ_STATUS -ne 0 ]; then
  echo "❌ KJNodes install failed."
  exit 1
fi

if [ $WAN_STATUS -ne 0 ]; then
  echo "❌ WanVideoWrapper install failed."
  exit 1
fi

if [ $VIBE_STATUS -ne 0 ]; then
  echo "❌ VibeVoice install failed."
  exit 1
fi

if [ $WAN_ANIMATE_STATUS -ne 0 ]; then
  echo "❌ WanAnimatePreprocess install failed."
  exit 1
fi

echo "Renaming loras downloaded as zip files to safetensors files"
cd $LORAS_DIR
for file in *.zip; do
    mv "$file" "${file%.zip}.safetensors"
done

# Wait for SageAttention build to complete
echo "Waiting for SageAttention build to complete..."
while ! [ -f /tmp/sage_build_done ]; do
    if ps -p $SAGE_PID > /dev/null 2>&1; then
        echo "⚙️  SageAttention build in progress, this may take up to 5 minutes."
        sleep 5
    else
        # Process finished but no completion marker - check if it failed
        if ! [ -f /tmp/sage_build_done ]; then
            echo "⚠️  SageAttention build process ended unexpectedly. Check logs at /tmp/sage_build.log"
            echo "Continuing with ComfyUI startup..."
            break
        fi
    fi
done

if [ -f /tmp/sage_build_done ]; then
    echo "✅ SageAttention build completed successfully!"
fi

# Start ComfyUI

echo "▶️  Starting ComfyUI"

nohup python3 "$NETWORK_VOLUME/ComfyUI/main.py" --listen --use-sage-attention > "$NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log" 2>&1 &

    # Counter for timeout
    counter=0
    max_wait=45

    until curl --silent --fail "$URL" --output /dev/null; do
        if [ $counter -ge $max_wait ]; then
            echo "⚠️  ComfyUI should be up by now. If it's not running, there's probably an error."
            echo ""
            echo "🛠️  Troubleshooting Tips:"
            echo "1. Make sure that your CUDA Version is set to 12.8/12.9 by selecting that in the additional filters tab before deploying the template"
            echo "2. If you are deploying using network storage, try deploying without it"
            echo "3. If you are using a B200 GPU, it is currently not supported"
            echo "4. If all else fails, open the web terminal by clicking \"connect\", \"enable web terminal\" and running:"
            echo "   cat comfyui_${RUNPOD_POD_ID}_nohup.log"
            echo "   This should show a ComfyUI error. Please paste the error in HearmemanAI Discord Server for assistance."
            echo ""
            echo "📋 Startup logs location: $NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log"
            break
        fi

        echo "🔄  ComfyUI Starting Up... You can view the startup logs here: $NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log"
        sleep 2
        counter=$((counter + 2))
    done

    # Only show success message if curl succeeded
    if curl --silent --fail "$URL" --output /dev/null; then
        echo "🚀 ComfyUI is UP"
    fi

    sleep infinity
fi
