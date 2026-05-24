#!/usr/bin/env bash
git clone https://github.com/Hearmeman24/comfyui-wan.git
mv comfyui-wan/src/start.sh /
mv comfyui-wan/src/hf_download_manager.py /
mv comfyui-wan/src/workflow_provisioner.py /
cp comfyui-wan/src/models_registry.json /
bash /start.sh
