# Wan 2.1 and 2.2 video generation, ComfyUI on RunPod

Created by HearmemanAI. Something not working, or a question about a workflow? Ask in
help-and-support on [my Discord](https://discord.gg/ZVWVhT43GW). That is the only place I do
support, and it is also where new releases are announced.

## Before you deploy

Set all of this on the template before you click Deploy, not after.

Click Edit Template and open the environment variables tab. Set at least one download flag to
true. They are all off by default. A pod with no flag set boots a working but empty ComfyUI, so the
workflows open with blank loader dropdowns and look broken. The full list is in the next section.

If you want your own CivitAI LoRAs or checkpoints on the pod, set `civitai_token` and the ID
variables below. The steps are
[written up on my Discord](https://discord.com/channels/1359855405613715495/1536707221788950708),
and in
[this article](https://civitai.red/articles/12333/how-to-use-hearmemans-civitai-downloader-when-deploying-a-runpod-template).

Then deploy. The first boot takes 5 to 20 minutes depending on which flags you set. ComfyUI comes
up while the models are still downloading, so you can look around before it finishes. Later deploys
on the same network volume are much faster.

FYI: this template is built for CUDA 13.0 and above.

## Environment variables

| Variable | Default | What it does |
|---|---|---|
| `download_wan21` | false | Wan 2.1 text to video and image to video, with their workflows and models |
| `download_wan22` | false | Wan 2.2 text to video, image to video, still images and SVI video extension |
| `download_wan_animate` | false | Wan Animate: motion and expression transfer onto a character |
| `download_steady_dancer` | false | Steady Dancer workflow and models |
| `DOWNLOAD_SCAIL2` | false | SCAIL-2 workflow and models. Note the uppercase. |
| `civitai_token` | empty | Your CivitAI API token |
| `CIVITAI_LORAS` | empty | Comma-separated CivitAI version IDs. They go to `models/loras`. |
| `CIVITAI_CHECKPOINTS` | empty | Comma-separated CivitAI version IDs. They go to `models/checkpoints`. |
| `HF_TOKEN` | empty | Optional. Raises your Hugging Face rate limit, which makes a first boot less likely to stall. |

Turn on as many download flags as you want. A model that two of them share is only downloaded once.
Only the workflows belonging to the flags you enabled are installed, so the menu shows you what your
models can actually run.

## Once it is up

Click Connect, then open port 8188 for ComfyUI or port 8888 for JupyterLab. The boot log is at
`/workspace/comfyui.log`.

Open the Workflows tab in ComfyUI. Every workflow carries notes in the graph telling you what it
does and which settings matter, which is a better place to read than this page. The pod also writes
three notes into the top of that same list on first boot: Welcome, Adding Models, and
Troubleshooting.

[My other templates](https://docs.google.com/spreadsheets/d/1NfbfZLzE9GIAD5B_y6xjK1IdW95c14oS1JuIG9QihL8/edit)
