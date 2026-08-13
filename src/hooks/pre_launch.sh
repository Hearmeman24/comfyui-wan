# shellcheck shell=bash
# pre_launch hook for comfyui-wan (CONTRACTS.md section 7).
# No shebang on purpose: this file is SOURCED, never executed.
#
# SOURCED by /comfyui-runtime/src/start.sh immediately before the ComfyUI
# launch. Sourcing rules: no `exit`, no `set -e`, runs on every boot and must
# be idempotent, own errors handled here.
#
# Install comfy-aimdo + comfy-kitchen, deliberately unpinned so pods track
# the latest release (maintainer's choice; ported from the pre-migration
# src/start.sh:215-217). ComfyUI routes some quantized-attention ops through
# comfy-kitchen, so a failed install degrades those paths but must never kill
# the boot: the old `exit 1` in the wait loop (pre-migration src/start.sh:427)
# does NOT transfer (hooks are sourced; exiting here would kill start.sh).
# pip is a near no-op once both are installed, so restarts are cheap.
echo "🔧 Installing comfy-aimdo + comfy-kitchen..."
if ! pip install comfy-aimdo comfy-kitchen > /tmp/pip_comfy_extras.log 2>&1; then
    echo "⚠️  comfy-aimdo/comfy-kitchen install failed (see /tmp/pip_comfy_extras.log)."
    echo "   Quantized attention paths may be degraded this boot. Restarting the pod retries the install."
    report_warn "comfy-aimdo/comfy-kitchen install failed; quantized attention paths may be degraded this boot. Restart the pod to retry the install."
else
    echo "✅ comfy-aimdo + comfy-kitchen installed"
fi
