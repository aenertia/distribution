#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

. /etc/profile

# Check if eden exists in .config
if [ ! -d "/storage/.config/eden" ]; then
    mkdir -p "/storage/.config/eden"
    cp -r "/usr/config/eden" "/storage/.config/"
fi

# Check if qt-config.ini exists in .config/eden
if [ ! -f "/storage/.config/eden/qt-config.ini" ]; then
    cp -r "/usr/config/eden/qt-config.ini" "/storage/.config/eden/qt-config.ini"
fi

# Move Nand / Saves to switch roms folder
if [ ! -d "/storage/roms/bios/eden/nand" ]; then
    mkdir -p "/storage/roms/bios/eden/nand"
fi
rm -rf /storage/.config/eden/nand
ln -sf /storage/roms/bios/eden/nand /storage/.config/eden/nand

# Link eden keys to bios folder
if [ ! -d "/storage/roms/bios/eden/keys" ]; then
    mkdir -p "/storage/roms/bios/eden/keys"
fi
# Pre-populate keys from image defaults if not already present
if [ -d "/usr/config/eden/keys" ] && [ ! -f "/storage/roms/bios/eden/keys/prod.keys" ]; then
    cp -n /usr/config/eden/keys/*.keys /storage/roms/bios/eden/keys/ 2>/dev/null
fi
rm -rf /storage/.config/eden/keys
ln -sf /storage/roms/bios/eden/keys /storage/.config/eden/keys

# Ensure firmware directory exists (firmware NCAs must be installed
# manually — they are too large for the system image)
mkdir -p "/storage/roms/bios/eden/nand/system/Contents/registered"

# Link .config/eden to .local/share/eden
rm -rf /storage/.local/share/eden
ln -sf /storage/.config/eden /storage/.local/share/eden

# Qt6 requires UTF-8 locale — ROCKNIX defaults to POSIX/C which causes
# Qt to hang or show locale warning dialogs
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Set QT Platform to wayland (ROCKNIX uses sway compositor)
export QT_QPA_PLATFORM=wayland

# Audio driver
export SDL_AUDIODRIVER=pulseaudio

# Freedreno/Turnip GPU tuning for Adreno (SM8250/SM8550/SM8650)
#   noflushall  — skip unnecessary cache flushes between draws (perf gain)
export TU_DEBUG=noflushall
# Crash cleanly on GPU fault — better than silent corruption/hangs
export MESA_VK_ABORT_ON_DEVICE_LOSS=1

set_kill set "-9 eden"

# Run eden emulator
# When called without a game path (menu/configuration mode), omit -g
# to prevent eden from trying to load an empty path
if [ -n "${1}" ]; then
  /usr/bin/eden -f -g "${1}"
else
  /usr/bin/eden -f
fi
