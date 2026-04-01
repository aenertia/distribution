#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)
#
# Initialize container storage hierarchy on /storage (rw partition).
# Runs once on first boot; skipped on subsequent boots via .initialized marker.

# Container data directories
mkdir -p /storage/containers/lilipod
mkdir -p /storage/containers/home
mkdir -p /storage/containers/waydroid/data

# Symlinks for tools that expect standard paths
ln -sf /storage/containers/lilipod /var/lib/lilipod 2>/dev/null
ln -sf /storage/containers/waydroid /var/lib/waydroid 2>/dev/null

# Environment variables for lilipod/distrobox
mkdir -p /storage/.config/profile.d
cat > /storage/.config/profile.d/020-containers <<'EOF'
export LILIPOD_HOME="/storage/containers/lilipod"
export DBX_CONTAINER_CUSTOM_HOME="/storage/containers/home"
export DBX_CONTAINER_MANAGER="lilipod"
EOF

touch /storage/containers/.initialized
