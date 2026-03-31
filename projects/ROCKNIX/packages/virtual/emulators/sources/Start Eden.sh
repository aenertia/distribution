#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

. /etc/profile

# Check if eden exists in .config
if [ ! -d "/storage/.config/eden" ]; then
    mkdir -p "/storage/.config/eden"
    cp -r "/usr/config/eden" "/storage/.config/"
fi

# Link .config/eden to .local/share/eden
rm -rf /storage/.local/share/eden
ln -sf /storage/.config/eden /storage/.local/share/eden

export QT_QPA_PLATFORM=wayland-egl
export SDL_AUDIODRIVER=pulseaudio

sway_fullscreen

set_kill set "-9 eden"
/usr/bin/eden &
