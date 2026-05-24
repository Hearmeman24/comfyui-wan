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

# ComfyUI source stays in the image (ephemeral, fast local disk). Models,
# workflows, outputs, inputs, and user-added custom_nodes live on the
# network volume via extra_model_paths.yaml + --user/output/input-directory
# flags. This avoids the 5-minute mv of /ComfyUI to MooseFS on first boot.
COMFYUI_DIR="/ComfyUI"
PERSIST_ROOT="$NETWORK_VOLUME/ComfyUI"
WORKFLOW_DIR="$PERSIST_ROOT/user/default/workflows"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"

mkdir -p "$PERSIST_ROOT/models" "$PERSIST_ROOT/user" \
         "$PERSIST_ROOT/output" "$PERSIST_ROOT/input" \
         "$PERSIST_ROOT/custom_nodes"

# Generate extra_model_paths.yaml from the live $PERSIST_ROOT so paths
# always match the actual network volume (not a baked-in /workspace
# assumption). Skip the file + flag when there's no real persistent
# volume — PERSIST_ROOT would equal COMFYUI_DIR and ComfyUI's defaults
# already cover those paths.
EXTRA_PATHS_FLAG=""
if [ "$NETWORK_VOLUME" != "/" ]; then
    cat > "$COMFYUI_DIR/extra_model_paths.yaml" <<EOF
network_volume:
    base_path: $PERSIST_ROOT
    checkpoints: models/checkpoints
    clip: models/clip
    clip_vision: models/clip_vision
    controlnet: models/controlnet
    diffusion_models: models/diffusion_models
    embeddings: models/embeddings
    loras: models/loras
    style_models: models/style_models
    text_encoders: models/text_encoders
    unet: models/unet
    upscale_models: models/upscale_models
    latent_upscale_models: models/latent_upscale_models
    detection: models/detection
    vae: models/vae
    custom_nodes: custom_nodes
EOF
    EXTRA_PATHS_FLAG="--extra-model-paths-config $COMFYUI_DIR/extra_model_paths.yaml"
else
    rm -f "$COMFYUI_DIR/extra_model_paths.yaml"
fi

echo "Downloading CivitAI download script to /usr/local/bin"
git clone "https://github.com/Hearmeman24/CivitAI_Downloader.git" || { echo "Git clone failed"; exit 1; }
mv CivitAI_Downloader/download_with_aria.py "/usr/local/bin/" || { echo "Move failed"; exit 1; }
chmod +x "/usr/local/bin/download_with_aria.py" || { echo "Chmod failed"; exit 1; }
rm -rf CivitAI_Downloader  # Clean up the cloned repo
pip install onnxruntime-gpu &
ONNX_PID=$!

# Custom nodes to provision at boot. Format: "<git-url>" or "<git-url>|<pinned-sha>".
CUSTOM_NODE_REPOS=(
    "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git|204f6d5"
    "https://github.com/wildminder/ComfyUI-VibeVoice.git"
    "https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git"
    "https://github.com/obisin/ComfyUI-FSampler.git"
    "https://github.com/cmeka/ComfyUI-WanMoEScheduler.git"
    "https://github.com/lrzjason/ComfyUI-VAE-Utils.git"
    "https://github.com/wallen0322/ComfyUI-Wan22FMLF.git"
)

for entry in "${CUSTOM_NODE_REPOS[@]}"; do
    url="${entry%%|*}"
    pin=""
    [[ "$entry" == *"|"* ]] && pin="${entry#*|}"
    name="$(basename "$url" .git)"
    dir="$CUSTOM_NODES_DIR/$name"
    if [ ! -d "$dir" ]; then
        git clone "$url" "$dir"
    else
        echo "Updating $name"
        git -C "$dir" pull
    fi
    if [ -n "$pin" ]; then
        git -C "$dir" reset --hard "$pin"
    fi
done


echo "🔧 Installing KJNodes packages..."
pip install -r $CUSTOM_NODES_DIR/ComfyUI-KJNodes/requirements.txt &
KJ_PID=$!

echo "🔧 Installing WanVideoWrapper packages..."
pip install -r $CUSTOM_NODES_DIR/ComfyUI-WanVideoWrapper/requirements.txt &
WAN_PID=$!

echo "🔧 Installing VibeVoice packages..."
pip install -r $CUSTOM_NODES_DIR/ComfyUI-VibeVoice/requirements.txt &
VIBE_PID=$!

echo "🔧 Installing WanAnimatePreprocess packages..."
pip install -r $CUSTOM_NODES_DIR/ComfyUI-WanAnimatePreprocess/requirements.txt &
WAN_ANIMATE_PID=$!

echo "🔧 Installing comfy-aimdo + comfy-kitchen..."
pip install comfy-aimdo comfy-kitchen &
COMFY_EXTRAS_PID=$!


export change_preview_method="true"


# Change to the directory
cd "$CUSTOM_NODES_DIR" || exit 1

# ---------------------------------------------------------------
# Workflow-driven model provisioning. The provisioner walks the
# workflow folders for each enabled flag, resolves model basenames
# via models_registry.json, emits a manifest for hf_download_manager,
# and copies the matching workflow JSONs to $WORKFLOW_DIR.
#
# Recognized flags (env vars set to "true"):
#   download_wan21   download_wan22   download_wan_animate   download_steady_dancer
# ---------------------------------------------------------------
HF_QUEUE_FILE="/tmp/hf_download_queue.tsv"
PROVISIONER_FLAGS=()
for v in download_wan21 download_wan22 download_wan_animate download_steady_dancer; do
    if [ "${!v}" = "true" ]; then
        PROVISIONER_FLAGS+=(--flag "$v")
    fi
done

if [ ${#PROVISIONER_FLAGS[@]} -eq 0 ]; then
    echo "ℹ️  No download_wan21/wan22/wan_animate/steady_dancer flag enabled — skipping model phase."
    : > "$HF_QUEUE_FILE"
else
    python3 /workflow_provisioner.py \
        --registry /models_registry.json \
        --workflows-src /comfyui-wan/workflows \
        --workflows-dst "$WORKFLOW_DIR" \
        --models-root "$NETWORK_VOLUME/ComfyUI/models" \
        --manifest "$HF_QUEUE_FILE" \
        "${PROVISIONER_FLAGS[@]}"

    echo "🔽 Starting HF download manager..."
    python3 /hf_download_manager.py "$HF_QUEUE_FILE"
fi

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


# Workflow copying is handled by the provisioner above (per enabled flag).
cd /

if [ "$change_preview_method" == "true" ]; then
    echo "Updating default preview method..."
    sed -i '/id: *'"'"'VHS.LatentPreview'"'"'/,/defaultValue:/s/defaultValue: false/defaultValue: true/' $CUSTOM_NODES_DIR/ComfyUI-VideoHelperSuite/web/js/VHS.core.js
    CONFIG_PATH="$PERSIST_ROOT/user/default/ComfyUI-Manager"
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


# Wait for all background pip installs to complete; abort on any failure.
declare -A INSTALL_PIDS=(
    [KJNodes]=$KJ_PID
    [WanVideoWrapper]=$WAN_PID
    [VibeVoice]=$VIBE_PID
    [WanAnimatePreprocess]=$WAN_ANIMATE_PID
    [onnxruntime-gpu]=$ONNX_PID
    [comfy-aimdo+comfy-kitchen]=$COMFY_EXTRAS_PID
)
for name in "${!INSTALL_PIDS[@]}"; do
    if wait "${INSTALL_PIDS[$name]}"; then
        echo "✅ $name install complete"
    else
        echo "❌ $name install failed."
        exit 1
    fi
done

echo "Renaming loras downloaded as zip files to safetensors files"
cd $LORAS_DIR
for file in *.zip; do
    mv "$file" "${file%.zip}.safetensors"
done

# Wait for SageAttention build to complete
echo "Waiting for SageAttention build to complete..."
while ps -p $SAGE_PID > /dev/null 2>&1 && ! [ -f /tmp/sage_build_done ]; do
    echo "⚙️  SageAttention build in progress, this may take up to 5 minutes."
    sleep 5
done

if [ -f /tmp/sage_build_done ]; then
    echo "✅ SageAttention build completed successfully!"
else
    echo "⚠️  SageAttention build process ended without a completion marker. Check logs at /tmp/sage_build.log"
    echo "Continuing with ComfyUI startup..."
fi

# Start ComfyUI

echo "▶️  Starting ComfyUI"

nohup python3 "$COMFYUI_DIR/main.py" --listen --enable-cors-header '*' --use-sage-attention \
    $EXTRA_PATHS_FLAG \
    --user-directory "$PERSIST_ROOT/user" \
    --output-directory "$PERSIST_ROOT/output" \
    --input-directory "$PERSIST_ROOT/input" \
    > "$NETWORK_VOLUME/comfyui_${RUNPOD_POD_ID}_nohup.log" 2>&1 &

    # Counter for timeout
    counter=0
    max_wait=70

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
