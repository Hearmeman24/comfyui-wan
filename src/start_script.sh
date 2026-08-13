#!/usr/bin/env bash
# Image entrypoint (baked into the image; changing it needs a vN tag).
# Dual sync, then hand off to the shared runtime:
#
#   1. sync the template repo   /comfyui-wan       -> origin/master
#   2. read runtime_ref from    /comfyui-wan/pins.json
#   3. sync the shared runtime  /comfyui-runtime   -> that pinned ref
#   4. exec bash /comfyui-runtime/src/start.sh /comfyui-wan
#
# Nothing is copied to / (CONTRACTS.md section 12.1); the runtime scripts run
# in place from /comfyui-runtime.
#
# On container restarts the writable layer persists, so a plain `git clone`
# would refuse to clone into the existing dir; always fetch + hard-reset.
# Each sync runs in a retry loop with backoff: a transient DNS/network blip
# at boot used to abort the old set -e entrypoint and kill the container. If
# GitHub stays unreachable we boot from whatever repo copy is already on disk
# rather than bricking the pod, and abort only when there is no copy at all.
# The DNS preflight naming RunPod's Global Networking setting lives in the
# shared start.sh; it is not duplicated here.

TEMPLATE_DIR=/comfyui-wan
TEMPLATE_URL=https://github.com/Hearmeman24/comfyui-wan.git
TEMPLATE_BRANCH=master    # wan's default branch is master, not main
RUNTIME_DIR=/comfyui-runtime
RUNTIME_URL=https://github.com/Hearmeman24/comfyui-runtime.git

sync_template() {
    if [ -d "$TEMPLATE_DIR/.git" ]; then
        git -C "$TEMPLATE_DIR" fetch --depth=1 origin "$TEMPLATE_BRANCH" &&
        git -C "$TEMPLATE_DIR" reset --hard "origin/$TEMPLATE_BRANCH"
    else
        rm -rf "$TEMPLATE_DIR" &&
        git clone --depth=1 --branch "$TEMPLATE_BRANCH" "$TEMPLATE_URL" "$TEMPLATE_DIR"
    fi
}

ok=""
for attempt in 1 2 3 4 5; do
    if sync_template; then ok=1; break; fi
    echo "⚠️  template repo sync attempt $attempt failed (network/DNS?). Retrying in $((attempt * 5))s..."
    sleep $((attempt * 5))
done

if [ -z "$ok" ]; then
    if [ -d "$TEMPLATE_DIR/.git" ]; then
        echo "⚠️  GitHub unreachable after retries. Booting with the existing on-disk template copy (may be stale)."
    else
        echo "❌ Could not clone $TEMPLATE_URL after retries and no local copy exists. Aborting." >&2
        exit 1
    fi
fi

# The runtime commit this template boots against, pinned in pins.json
# (CONTRACTS.md section 6). Unreadable pins fall back to the runtime's main
# branch, loudly: an unpinned runtime is better than a dead pod.
RUNTIME_REF="$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['runtime_ref'])" "$TEMPLATE_DIR/pins.json" 2>/dev/null)"
if [ -z "$RUNTIME_REF" ]; then
    echo "⚠️  Could not read runtime_ref from $TEMPLATE_DIR/pins.json. Falling back to the runtime's main branch (UNPINNED)."
    RUNTIME_REF=main
fi

# Tracks whether THIS boot created the runtime checkout. It decides which
# fallback message is true when the pinned-ref fetch fails every retry: a kept
# pre-existing checkout is potentially STALE, but a fresh clone left at main
# HEAD is UNPINNED and NEWER than the pin.
runtime_fresh_clone=""

sync_runtime() {
    if [ ! -d "$RUNTIME_DIR/.git" ]; then
        rm -rf "$RUNTIME_DIR"
        git clone "$RUNTIME_URL" "$RUNTIME_DIR" || return 1
        runtime_fresh_clone=1
    fi
    git -C "$RUNTIME_DIR" fetch origin "$RUNTIME_REF" &&
    git -C "$RUNTIME_DIR" reset --hard FETCH_HEAD
}

ok=""
for attempt in 1 2 3 4 5; do
    if sync_runtime; then ok=1; break; fi
    echo "⚠️  runtime repo sync attempt $attempt failed (network/DNS?). Retrying in $((attempt * 5))s..."
    sleep $((attempt * 5))
done

if [ -z "$ok" ]; then
    if [ -d "$RUNTIME_DIR/.git" ]; then
        if [ -n "$runtime_fresh_clone" ]; then
            echo "⚠️  Cloned the runtime but could not fetch the pinned ref $RUNTIME_REF. Booting the runtime's main HEAD: UNPINNED and NEWER than the pin."
        else
            echo "⚠️  Could not sync the runtime to $RUNTIME_REF. Booting with the existing on-disk runtime copy (may be stale)."
        fi
    else
        echo "❌ Could not clone $RUNTIME_URL after retries and no local copy exists. Aborting." >&2
        exit 1
    fi
fi

exec bash /comfyui-runtime/src/start.sh /comfyui-wan
