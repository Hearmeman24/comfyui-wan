## What is in this template

This template runs the Wan family of video models. It ships five
workflow sets. Each one sits behind an environment variable, and the
pod downloads only the models for the sets you turn on. Leave them all
unset and the pod boots with no models.

Set these in the environment variables tab. Click Edit Template before
you deploy, or edit the variables on this pod and restart it. Set a
variable to true to turn its set on. You can turn on more than one;
models shared between sets are only downloaded once.

| Variable | What you get |
|---|---|
| download_wan21 | Wan 2.1: text to video and image to video. About 70 GB. |
| download_wan22 | Wan 2.2: text to video, image to video, image generation, SVI video extension. About 127 GB. |
| download_wan_animate | Wan Animate: transfer motion and expressions from a video onto a character. About 48 GB. |
| download_steady_dancer | Steady Dancer: dance videos driven by a reference video. About 49 GB. |
| DOWNLOAD_SCAIL2 | SCAIL-2 video generation. About 28 GB. Note this variable is uppercase. |

## CUDA

FYI: this template is built for CUDA 13.0 and above. There is nothing
for you to do about it. The template is scoped to that, so RunPod only
offers it to you on a host that supports it.

## Your own LoRAs

Some workflows come wired for LoRAs that are not bundled, including
personal ones. The boot log lists them as user supplied. To use your
own, drop them into /workspace/ComfyUI/models/loras, or have the pod
download them from CivitAI at boot; the Adding models note next to
this one shows how.

## Live previews while sampling

Animated previews of the video while it is sampling now follow
VideoHelperSuite's own default, which is off. Earlier versions of this
template switched it on for you. To turn it on, open Settings, find the
VHS section, and enable animated previews.
