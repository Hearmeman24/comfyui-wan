#!/usr/bin/env bash
# Image entrypoint. On container restarts the writable layer persists,
# so `git clone` would fail silently (refuses to clone into existing
# dir) and we'd ship the stale start.sh from the first boot. Always
# fetch + hard-reset to origin/master to guarantee the runtime scripts
# reflect what's on the repo.
set -e
REPO_DIR=/comfyui-wan
REPO_URL=https://github.com/Hearmeman24/comfyui-wan.git
if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" fetch --depth=1 origin master
    git -C "$REPO_DIR" reset --hard origin/master
else
    rm -rf "$REPO_DIR"
    git clone --depth=1 "$REPO_URL" "$REPO_DIR"
fi
set +e
cp -f "$REPO_DIR/src/start.sh" /
cp -f "$REPO_DIR/src/hf_download_manager.py" /
cp -f "$REPO_DIR/src/workflow_provisioner.py" /
cp -f "$REPO_DIR/src/models_registry.json" /
bash /start.sh
