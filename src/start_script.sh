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

# Preflight. RunPod's "global networking" blocks outbound DNS, so the first
# thing that touches the network dies with "Could not resolve host:
# github.com" and sends the user off to check GitHub instead of the pod
# setting that actually broke it. Resolve two known hosts up front and, if
# neither answers, say what it is and stop — before the retry loop turns one
# clear cause into 75 seconds of git errors.
TIMEOUT=""
command -v timeout >/dev/null 2>&1 && TIMEOUT="timeout 5"
check_host() {
    # shellcheck disable=SC2086  # $TIMEOUT is a command prefix, not an argument
    $TIMEOUT getent hosts "$1" >/dev/null 2>&1 && return 0
    $TIMEOUT python3 -c 'import socket,sys; socket.gethostbyname(sys.argv[1])' "$1" >/dev/null 2>&1
}

if ! check_host github.com && ! check_host huggingface.co; then
    cat >&2 <<'EOF'

════════════════════════════════════════════════════════════════════════
❌  No DNS. Nothing can be downloaded, so the pod is stopping here.

    The cause is almost always GLOBAL NETWORKING being enabled on this
    pod. It blocks outbound DNS, so github.com and huggingface.co stop
    resolving and ComfyUI, the custom nodes and every model download
    fail before they start.

    Fix: disable global networking and redeploy.
      RunPod console -> your pod -> Edit Pod -> uncheck "Global
      Networking" -> Save. On a new pod the same checkbox is on the
      deploy screen, under the network volume picker.

    If global networking is already off, the pod has no outbound
    network at all — try a different region or data center.
════════════════════════════════════════════════════════════════════════

EOF
    exit 1
fi

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
