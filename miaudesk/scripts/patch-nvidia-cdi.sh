#!/usr/bin/env bash
set -e

echo "Patching /etc/cdi/nvidia.yaml..."

# 1. Fix the executable path
# Replaces "path: /usr/bin/nvidia-cdi-hook" with "path: /run/current-system/sw/bin/nvidia-ctk"
sudo sed -i 's|path: /usr/bin/nvidia-cdi-hook|path: /run/current-system/sw/bin/nvidia-ctk|g' /etc/cdi/nvidia.yaml

# 2. Fix the arguments
# Replaces "- nvidia-cdi-hook" with "- nvidia-ctk" followed by a new line with "- hook"
# This changes the command from executing "nvidia-cdi-hook ..." to "nvidia-ctk hook ..."
sudo sed -i 's|    - nvidia-cdi-hook|    - nvidia-ctk\n    - hook|g' /etc/cdi/nvidia.yaml

echo "Done. File patched."

