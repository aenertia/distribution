#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2022-present JELOS (https://github.com/JustEnoughLinuxOS)

. /etc/profile
. /etc/os-release

set_kill set "-9 drastic"

#Get game/platform info
GAME=$(echo "${1}"| sed "s#^/.*/##")
PLATFORM="nds"

#Get ES feature settings
HIRES3D=$(get_setting hires_3d "${PLATFORM}" "${GAME}")
THREADED3D=$(get_setting threaded_3d "${PLATFORM}" "${GAME}")
FOLLOW3D=$(get_setting follow_3d_renderer "${PLATFORM}" "${GAME}")
MICTHRESH=$(get_setting microphone_sensitivity "${PLATFORM}" "${GAME}")

#load gptokeyb support files
control-gen_init.sh
source /storage/.config/gptokeyb/control.ini
get_controls

#Copy drastic files to .config
if [ ! -d "/storage/.config/drastic" ]; then
  mkdir -p /storage/.config/drastic/
  cp -r /usr/config/drastic/* /storage/.config/drastic/
fi

if [ ! -d "/storage/.config/drastic/system" ]; then
  mkdir -p /storage/.config/drastic/system
fi

for bios in nds_bios_arm9.bin nds_bios_arm7.bin
do
  if [ ! -e "/storage/.config/drastic/system/${bios}" ]; then
     if [ -e "/storage/roms/bios/${bios}" ]; then
       ln -sf /storage/roms/bios/${bios} /storage/.config/drastic/system
     fi
  fi
done

#Copy drastic files to .config
if [ ! -f "/storage/.config/drastic/drastic.gptk" ]; then
  cp -r /usr/config/drastic/drastic.gptk /storage/.config/drastic/
fi

#Make drastic savestate folder
if [ ! -d "/storage/roms/savestates/nds" ]; then
  mkdir -p /storage/roms/savestates/nds
fi

#Link savestates to roms/savestates/nds
rm -rf /storage/.config/drastic/savestates
ln -sf /storage/roms/savestates/nds /storage/.config/drastic/savestates

#Link saves to roms/nds/saves
rm -rf /storage/.config/drastic/backup
ln -sf /storage/roms/nds /storage/.config/drastic/backup

#Apply ES features to config (only override when user has explicitly set a value)
case "${HIRES3D}" in
    1) sed -i 's/^hires_3d = .*/hires_3d = 1/' /storage/.config/drastic/config/drastic.cfg ;;
    0) sed -i 's/^hires_3d = .*/hires_3d = 0/' /storage/.config/drastic/config/drastic.cfg ;;
esac

case "${THREADED3D}" in
    1) sed -i 's/^threaded_3d = .*/threaded_3d = 1/' /storage/.config/drastic/config/drastic.cfg ;;
    0) sed -i 's/^threaded_3d = .*/threaded_3d = 0/' /storage/.config/drastic/config/drastic.cfg ;;
esac

case "${FOLLOW3D}" in
    1) sed -i 's/^fix_main_2d_screen = .*/fix_main_2d_screen = 1/' /storage/.config/drastic/config/drastic.cfg ;;
    0) sed -i 's/^fix_main_2d_screen = .*/fix_main_2d_screen = 0/' /storage/.config/drastic/config/drastic.cfg ;;
esac

cd /storage/.config/drastic/

# Dual-screen layout: side-by-side for per-panel, vertical stacked for stretched
if [ "${DEVICE_HAS_DUAL_SCREEN}" = "true" ]; then
  STRETCHED=$(get_setting "system.stretched_mode")
  if [ "${STRETCHED}" = "1" ]; then
    sed -i 's/^screen_orientation = .*/screen_orientation = 0/' /storage/.config/drastic/config/drastic.cfg
  else
    sed -i 's/^screen_orientation = .*/screen_orientation = 1/' /storage/.config/drastic/config/drastic.cfg
  fi
fi

# RGDS: vertical stacked layout to span both panels
if [ "${QUIRK_DEVICE}" = "Anbernic RG DS" ] && [ "${DEVICE_HAS_DUAL_SCREEN}" = "true" ]; then
    DRASTIC_RGDS_DUAL=true
    CON="${WLR_CON:-DSI-2}"
    SECOND_CON=$([[ "$CON" = "DSI-1" ]] && echo "DSI-2" || echo "DSI-1")
    sed -i 's/^screen_orientation = .*/screen_orientation = 0/' /storage/.config/drastic/config/drastic.cfg
fi

@HOTKEY@

$GPTOKEYB "drastic" -c "drastic.gptk" &
# Fix actual touch inputs by replacing touch->mouse translation and add hw mic support
export LD_PRELOAD="/usr/lib/libdrastouch.so"
export SDL_TOUCH_MOUSE_EVENTS="0"
export DSHOOK_MIC_THRESH="${MICTHRESH}"

# Remove sway border after window appears (drastic defaults to "normal" with title bar)
(sleep 2; swaymsg '[app_id="drastic"]' border none) &

# RGDS: launch in background, stack outputs after window appears
if [ "${DRASTIC_RGDS_DUAL}" = "true" ]; then
    ./drastic "$1" &
    DPID=$!

    swaymsg output "${CON}" pos 0 0
    swaymsg output "${SECOND_CON}" power on, output "${SECOND_CON}" pos 0 480
    swaymsg floating_maximum_size 640 x 960

    for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        if swaymsg '[app_id="drastic"]' floating enable, fullscreen disable, \
            resize set 640 960, move to output "${CON}", move absolute position 0 0 2>/dev/null; then
            break
        fi
    done

    swaymsg 'input "1046:911:Goodix_Capacitive_TouchScreen" calibration_matrix 1 0 0 0 0.5 0.5'
    wait $DPID
    swaymsg floating_maximum_size 0 x 0
    swaymsg output "${SECOND_CON}" power off
    swaymsg output "${CON}" pos 0 0
    swaymsg 'input "1046:911:Goodix_Capacitive_TouchScreen" calibration_matrix 1 0 0 0 1 0'
else
    ./drastic "$1"
fi
kill -9 $(pidof gptokeyb)
