# Created by HearmemanAI https://www.hearmemanai.com

[![Sponsor](https://readme.cash/i/pift670zt5.svg)](https://readme.cash/c/pift670zt5)

# Troubleshooting guide in case you encounter any errors:
[click here](https://docs.google.com/document/d/1822H-x7AevWz2T_jzMu8-9e5UlQ-zrH0FhCFmQ6FtRc/edit?usp=sharing)
---
# v12 — Major Refactor (May 2026)
> ⚠️ **Breaking change for existing users.**
> The old per-resolution / per-feature flags are gone. If you're updating an existing pod template, **delete** the removed env vars below and **add** the new ones — otherwise nothing will download.

> ⚠️ **CUDA 12.8 required.** Before deploying, open Additional Filters and select CUDA 12.8.
> Fallback (older CUDA): https://runpod.io/console/deploy?template=0b7tk92912&ref=uyjfcrgy

---

## What's new in v12
- **Workflow-driven downloads.** The pod now reads the workflows you choose and downloads only the models those workflows actually reference. No more redundant multi-gigabyte downloads.
- **Faster HF transfers.** Hugging Face's `hf_xet` accelerator is enabled image-wide (`HF_XET_HIGH_PERFORMANCE=1`), typically 1.5–3× faster than aria2 on HF.
- **Live download manager.** A 3-way pool with an append-only status snapshot every 10s (active %, speed, ETA; queued list; done count). No more interleaved aria2 spam.
- **Faster boot.** `comfy-aimdo` / `comfy-kitchen` now install in the background instead of blocking startup; redundant apt/pip steps removed.
- **Slimmer workflow set.** Obsolete Wan-Fun-SDXL helper, legacy VACE preview, and the unused Video Extend workflow have been removed.

---

## ⚙️ Environment Variables

Set the flags you want to **`true`** (lowercase, as strings). Multiple may be enabled at once — shared models are deduplicated automatically.

### Download flags (new in v12)

| Variable | Downloads + provisions |
|---|---|
| `download_wan21` | Wan 2.1 (incl. VACE) + Infinite Talk workflows + their models |
| `download_wan22` | Wan 2.2 + SVI Video Extension workflows + their models |
| `download_wan_animate` | Wan Animate workflows + models |
| `download_steady_dancer` | Steady Dancer workflow + models |

Only the workflows for enabled flags are copied into your ComfyUI workflows folder — you'll see exactly what your models can run.

### Removed in v12 (delete these from your template if you're upgrading)
`download_480p_native_models`, `download_720p_native_models`, `download_wan_fun_and_sdxl_helper`, `download_vace`, `download_vace_debug`, `download_wan_animate_only`, `debug_models`

### CivitAI (unchanged)

| Variable | Description |
|---|---|
| `civitai_token` | Your CivitAI token (auto-download LoRAs and Checkpoints) |
| `LORAS_IDS_TO_DOWNLOAD` | Comma-separated CivitAI LoRA version IDs |
| `CHECKPOINT_IDS_TO_DOWNLOAD` | Comma-separated CivitAI Checkpoint version IDs |

👉 [CivitAI Downloader README](https://github.com/Hearmeman24/CivitAI_Downloader/blob/main/README.md)

---

## 🚀 Deploying

1. Set your env vars (at least one `download_*` flag set to `"true"`).
2. Click **Deploy**.
3. Wait for setup (5–20 minutes depending on flags + network).
4. Future deployments are faster on a persistent network volume.

## 🌐 Accessing ComfyUI
1. Click **Connect**
2. Open **port 8188**

## 📓 Accessing JupyterLab
1. Click **Connect**
2. Open **port 8888**

---

## 🛠️ Troubleshooting

### Fixing Missing Custom Nodes
If you see `IMPORT FAILED` in ComfyUI:
1. Open the **Manager** menu
2. Click **Install missing custom nodes**
3. Click **Try fix**

### User-supplied LoRAs
If a workflow references a LoRA that isn't bundled (your personal training LoRAs, NSFW pack, etc.), the boot log will list them as "user-supplied". Drop them into `/workspace/ComfyUI/models/loras/` manually or via `LORAS_IDS_TO_DOWNLOAD`.

> ℹ️ **For my other templates**:
> [Click HERE](https://docs.google.com/spreadsheets/d/1NfbfZLzE9GIAD5B_y6xjK1IdW95c14oS1JuIG9QihL8/edit?usp=sharing)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/W7W81FM4M1)
