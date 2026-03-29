#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2022-present JELOS (https://github.com/JustEnoughLinuxOS)

. /etc/profile
. /usr/lib/rocknix-display/display-core.sh

set_kill set "-9 melonDS"


CONF_DIR="/storage/.config/melonDS"
MELONDS_INI="melonDS.ini"
SWAY_CONFIG="/storage/.config/sway/config"

if [ ! -d "${CONF_DIR}" ]; then
	cp -r "/usr/config/melonDS" "/storage/.config/"
fi

if [ ! -d "/storage/roms/savestates/nds" ]; then
	mkdir -p "/storage/roms/savestates/nds"
fi

#Make sure melonDS gptk config exists
if [ ! -f "${CONF_DIR}/melonDS.gptk" ]; then
	cp -r "/usr/config/melonDS/melonDS.gptk" "${CONF_DIR}/melonDS.gptk"
fi

#Make sure melonDS config exists
if [ ! -f "${CONF_DIR}/${MELONDS_INI}" ]; then
	cp -r "/usr/config/melonDS/melonDS.ini" "${CONF_DIR}/${MELONDS_INI}"
fi

#Emulation Station Features
GAME=$(echo "${1}" | sed "s#^/.*/##")
PLATFORM=$(echo "${2}"| sed "s#^/.*/##")
CONTYPE=$(get_setting console_type "${PLATFORM}" "${GAME}")
DBOOT=$(get_setting direct_boot "${PLATFORM}" "${GAME}")
GRENDERER=$(get_setting graphics_backend "${PLATFORM}" "${GAME}")
IRES=$(get_setting internal_resolution "${PLATFORM}" "${GAME}")
SORIENTATION=$(get_setting screen_orientation "${PLATFORM}" "${GAME}")
SLAYOUT=$(get_setting screen_layout "${PLATFORM}" "${GAME}")
SWAP=$(get_setting screen_swap "${PLATFORM}" "${GAME}")
SROTATION=$(get_setting screen_rotation "${PLATFORM}" "${GAME}")
VSYNC=$(get_setting vsync "${PLATFORM}" "${GAME}")

#Set the cores to use
CORES=$(get_setting "cores" "${PLATFORM}" "${GAME}")
unset EMUPERF
[ "${CORES}" = "little" ] && EMUPERF="${SLOW_CORES}"
[ "${CORES}" = "big" ] && EMUPERF="${FAST_CORES}"

#Console Type
if [ "$PLATFORM" = "ndsiware" ]; then
    sed -i '/^ConsoleType=/c\ConsoleType=1' /storage/.config/melonDS/melonDS.ini
else
    if [ "$CONTYPE" = "1" ]; then
        sed -i '/^ConsoleType=/c\ConsoleType=1' /storage/.config/melonDS/melonDS.ini
    else
        sed -i '/^ConsoleType=/c\ConsoleType=0' /storage/.config/melonDS/melonDS.ini
    fi
fi

#Direct Boot
if [ "$PLATFORM" = "ndsiware" ]; then
    sed -i '/^DirectBoot=/c\DirectBoot=0' /storage/.config/melonDS/melonDS.ini
else
    if [ "$DBOOT" = "0" ]; then
        sed -i '/^DirectBoot=/c\DirectBoot=0' /storage/.config/melonDS/melonDS.ini
        sed -i '/^ExternalBIOSEnable=/c\ExternalBIOSEnable=1' /storage/.config/melonDS/melonDS.ini
    else
        sed -i '/^DirectBoot=/c\DirectBoot=1' /storage/.config/melonDS/melonDS.ini
        sed -i '/^ExternalBIOSEnable=/c\ExternalBIOSEnable=0' /storage/.config/melonDS/melonDS.ini
    fi
fi

#Graphics Backend
case "$GRENDERER" in
  "1"|"2")
    sed -i "/^ScreenUseGL=/c\ScreenUseGL=1" "${CONF_DIR}/${MELONDS_INI}"
    sed -i "/^3DRenderer=/c\3DRenderer=$GRENDERER" "${CONF_DIR}/${MELONDS_INI}"
  ;;
  *)
    sed -i '/^ScreenUseGL=/c\ScreenUseGL=0' "${CONF_DIR}/${MELONDS_INI}"
    sed -i '/^3DRenderer=/c\3DRenderer=0' "${CONF_DIR}/${MELONDS_INI}"
  ;;
esac

#Internal Resolution
if [ "$IRES" -gt "0" ]; then
        sed -i "/^GL_ScaleFactor=/c\GL_ScaleFactor=$IRES" "${CONF_DIR}/${MELONDS_INI}"
else
        sed -i '/^GL_ScaleFactor=/c\GL_ScaleFactor=1' "${CONF_DIR}/${MELONDS_INI}"
fi

#Screen Orientation
if [ "$SORIENTATION" -gt "0" ]; then
	sed -i "/^ScreenLayout=/c\ScreenLayout=$SORIENTATION" "${CONF_DIR}/${MELONDS_INI}"
else
	sed -i '/^ScreenLayout=/c\ScreenLayout=2' "${CONF_DIR}/${MELONDS_INI}"
fi

#Screen Layout
# Screen Layout
sed -i '/^Screen1Enabled=/c\Screen1Enabled=0' "${CONF_DIR}/${MELONDS_INI}"

enable_second_screen() {
    sed -i '/^ScreenSizing=/c\ScreenSizing=4' "${CONF_DIR}/${MELONDS_INI}"
    sed -i '/^Screen1Enabled=/d$ a Screen1Enabled=1' "${CONF_DIR}/${MELONDS_INI}"
    sed -i '/^Screen1Layout=/d$ a Screen1Layout=2' "${CONF_DIR}/${MELONDS_INI}"
}

if [ "$SLAYOUT" = "6" ]; then
    enable_second_screen
elif [ -n "$SLAYOUT" ] && [ "$SLAYOUT" != "0" ]; then
    sed -i "/^ScreenSizing=/c\ScreenSizing=$SLAYOUT" "${CONF_DIR}/${MELONDS_INI}"
elif display_is_dual; then
    enable_second_screen
else
    sed -i '/^ScreenSizing=/c\ScreenSizing=0' "${CONF_DIR}/${MELONDS_INI}"
fi

# Screen Swap
if display_is_dual && [[ -z "$SLAYOUT" || "$SLAYOUT" = "6" ]]; then
    if [ "$SWAP" = "1" ]; then
        sed -i '/^ScreenSizing=/c\ScreenSizing=5' "${CONF_DIR}/${MELONDS_INI}"
        sed -i '/^Screen1Sizing=/d$ a Screen1Sizing=4' "${CONF_DIR}/${MELONDS_INI}"
    else
        sed -i '/^ScreenSizing=/c\ScreenSizing=4' "${CONF_DIR}/${MELONDS_INI}"
        sed -i '/^Screen1Sizing=/d$ a Screen1Sizing=5' "${CONF_DIR}/${MELONDS_INI}"
    fi
else
    sed -i "/^ScreenSwap=/c\ScreenSwap=${SWAP:-0}" "${CONF_DIR}/${MELONDS_INI}"
fi

#Screen Rotation
if [ "$SROTATION" -gt "0" ]; then
	sed -i "/^ScreenRotation=/c\ScreenRotation=$SROTATION" "${CONF_DIR}/${MELONDS_INI}"
else
	sed -i '/^ScreenRotation=/c\ScreenRotation=0' "${CONF_DIR}/${MELONDS_INI}"
fi

#Vsync
if [ "$VSYNC" = "1" ]; then
	sed -i '/^ScreenVSync=/c\ScreenVSync=1' "${CONF_DIR}/${MELONDS_INI}"
else
	sed -i '/^ScreenVSync=/c\ScreenVSync=0' "${CONF_DIR}/${MELONDS_INI}"
fi

# Extract archive to /tmp/melonds
TEMP="/tmp/melonds"
rm -rf "${TEMP}"
mkdir -p "${TEMP}"
if [[ "${1}" == *.zip ]]; then
    unzip -o "${1}" -d "${TEMP}"
    ROM=$(find "${TEMP}" -maxdepth 1 -type f -name "*.nds" | head -n 1)
elif [[ "${1}" == *.7z ]]; then
    7z x -y -o"${TEMP}" "${1}"
    ROM=$(find "${TEMP}" -maxdepth 1 -type f -name "*.nds" | head -n 1)
else
    ROM="${1}"
fi

# QT platform - default to xcb
export QT_QPA_PLATFORM=xcb

# QT platform - some device / driver combinations need wayland
case ${HW_DEVICE} in
    RK3566|RK3588|S922X)
        [[ $(/usr/bin/gpudriver) == "libmali" ]] && export QT_QPA_PLATFORM=wayland
    ;;
esac

@PANFROST@
@HOTKEY@
@LIBMALI@

#Generate a new MelonDS.toml each run (temporary hack)
rm -rf "${CONF_DIR}/melonDS.toml"

#Retroachievements
/usr/bin/cheevos_melonds.sh

#Run MelonDS emulator

# Dual-screen: stack outputs vertically, launch in background, position windows
if display_is_dual; then
    display_save_state
    display_stack_vertical

    ${EMUPERF} /usr/bin/melonDS -f "${ROM}" &
    MPID=$!

    # Wait for [w1] window to appear, then fullscreen each on its output
    display_wait_window 'title="\[w1\].*melonDS"' 15
    sleep 0.5
    display_fullscreen_split 'title="\[w1\].*melonDS"' 'title="\[w2\].*melonDS"'

    # Map touch to bottom panel (where [w2] / DS touch screen is)
    display_map_touch_to "$DISPLAY_BOTTOM"

    wait $MPID
    display_restore
else
    ${EMUPERF} /usr/bin/melonDS -f "${ROM}"
fi
