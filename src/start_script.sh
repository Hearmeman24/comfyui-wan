#!/usr/bin/env bash
# Image entrypoint. On container restarts the writable layer persists,
# so `git clone` would fail silently (refuses to clone into existing
# dir) and we'd ship the stale start.sh from the first boot. Always
# fetch + hard-reset to origin/master to guarantee the runtime scripts
# reflect what's on the repo.
#
# The sync is wrapped in a retry loop: a transient DNS/network blip at
# boot used to abort the whole entrypoint (set -e) and kill the
# container ("Could not resolve host: github.com"). Now we retry with
# backoff, and if GitHub stays unreachable we fall back to whatever repo
# copy is already on disk rather than bricking the pod.
REPO_DIR=/comfyui-wan
REPO_URL=https://github.com/Hearmeman24/comfyui-wan.git

sync_repo() {
    if [ -d "$REPO_DIR/.git" ]; then
        git -C "$REPO_DIR" fetch --depth=1 origin master &&
        git -C "$REPO_DIR" reset --hard origin/master
    else
        rm -rf "$REPO_DIR" &&
        git clone --depth=1 "$REPO_URL" "$REPO_DIR"
    fi
}

ok=""
for attempt in 1 2 3 4 5; do
    if sync_repo; then ok=1; break; fi
    echo "⚠️  repo sync attempt $attempt failed (network/DNS?). Retrying in $((attempt * 5))s..."
    sleep $((attempt * 5))
done

if [ -z "$ok" ]; then
    if [ -d "$REPO_DIR/.git" ]; then
        echo "⚠️  GitHub unreachable after retries — booting with the existing on-disk repo copy (may be stale)."
    else
        echo "❌ Could not clone $REPO_URL after retries and no local copy exists. Aborting." >&2
        exit 1
    fi
fi

cp -f "$REPO_DIR/src/start.sh" /
cp -f "$REPO_DIR/src/hf_download_manager.py" /
cp -f "$REPO_DIR/src/workflow_provisioner.py" /
cp -f "$REPO_DIR/src/models_registry.json" /
bash /start.sh
