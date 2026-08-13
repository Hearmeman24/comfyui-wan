#!/usr/bin/env bash
# Version guard for pre-migration images (v25 and earlier). NOT the boot script.
#
# Placement IS the detection: only a pre-migration image-baked entrypoint ever
# copies this file to /start.sh and executes it (the old start_script.sh
# hard-resets the clone to origin/master on every boot, copies /start.sh out
# of it, and runs `bash /start.sh`). The migrated entrypoint execs
# /comfyui-runtime/src/start.sh and never touches this file. So if this script
# is executing at all, the image is pre-migration, unconditionally. Do NOT
# "improve" this with a version check, an env probe or any conditional.
#
# Fails CLOSED: no partial boot, no ComfyUI launch, no downloads, no network
# calls, no writes to the network volume. Print the banner and park.
#
# Expected noise: before this runs, the old entrypoint's `cp -f` of
# src/hf_download_manager.py and src/workflow_provisioner.py (both deleted by
# the migration) emits two "cp: cannot stat" lines to stderr. The old
# entrypoint has no `set -e`, so they are non-fatal, and the banner below
# dominates the log. Do not add stub .py files to suppress them.
# (src/models_registry.json is still copied and still real: the runtime reads
# it from the template dir, so it stays in the repo.)

cat <<'BANNER'
============================================================

  This template has been updated.

  Your pod is running an old image, and the files it boots
  from have moved. Nothing is broken and your network volume
  is untouched, but this pod cannot start ComfyUI on the old
  image.

  To get running again:

    1. Edit your RunPod template and set the image to:
         hearmeman/comfyui-wan-template:v26
    2. Deploy a new pod on that tag.

  Your models, outputs and workflows live on your network
  volume and the new version picks them up as is.

  Need help? Discord: https://discord.gg/ZVWVhT43GW

============================================================
This pod will now idle so you can read this message.
BANNER

# sleep infinity so the pod stays up with a readable log instead of
# crash-looping: a customer can only read the message if the pod survives to
# show it, and RunPod restart loops would bury it (never let the container
# exit when the app dies).
sleep infinity
