#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2022-present JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2026 Joel Wirāmu Pauling <aenertia@aenertia.net>

. /etc/profile

#Check if aethersx2 exists in .config
if [ ! -d "/storage/.config/aethersx2" ]; then
    mkdir -p "/storage/.config/aethersx2"
        cp -r "/usr/config/aethersx2" "/storage/.config/"
fi

#Make Aethersx2 bios folder
if [ ! -d "/storage/roms/bios/aethersx2" ]; then
    mkdir -p "/storage/roms/bios/aethersx2"
fi

#Create PS2 savestates folder
if [ ! -d "/storage/roms/savestates/ps2" ]; then
    mkdir -p "/storage/roms/savestates/ps2"
fi

#Emulation Station Features
GAME=$(echo "${1}"| sed "s#^/.*/##")
PLATFORM=$(echo "${2}"| sed "s#^/.*/##")
ASPECT=$(get_setting aspect_ratio "${PLATFORM}" "${GAME}")
FILTER=$(get_setting bilinear_filtering "${PLATFORM}" "${GAME}")
FPS=$(get_setting show_fps "${PLATFORM}" "${GAME}")
RATE=$(get_setting ee_cycle_rate "${PLATFORM}" "${GAME}")
SKIP=$(get_setting ee_cycle_skip "${PLATFORM}" "${GAME}")
HWDOWNLOAD=$(get_setting hw_download_mode "${PLATFORM}" "${GAME}")
GRENDERER=$(get_setting graphics_backend "${PLATFORM}" "${GAME}")
IRES=$(get_setting internal_resolution "${PLATFORM}" "${GAME}")
VSYNC=$(get_setting vsync "${PLATFORM}" "${GAME}")
ENABLE_WIDESCREEN_PATCHES=$(get_setting enable_widescreen_patches "${PLATFORM}" "${GAME}")

#Set the cores to use
CORES=$(get_setting "cores" "${PLATFORM}" "${GAME}")
if [ "${CORES}" = "little" ]; then
  EMUPERF="${SLOW_CORES}"
elif [ "${CORES}" = "big" ]; then
  EMUPERF="${FAST_CORES}"
else
  unset EMUPERF
fi

###############################################################################
# Per-device GPU driver configuration
#
# Two GPU families:
#   freedreno (Adreno/Qualcomm): SDM845, SM6115, SM8250, SM8550, SM8650
#     - Vulkan via Turnip, OpenGL via Freedreno Gallium
#     - Adreno natively supports GL 3.3+, no MESA override needed
#
#   panfrost/mali (Rockchip/Allwinner/Amlogic): RK3326, RK3399, RK3566, RK3588, S922X, H700
#     - Vulkan via PanVK or Mali blob
#     - OpenGL via Panfrost — needs GL 3.3 version override
###############################################################################
case "${DEVICE}" in
  SDM845|SM6115|SM8250|SM8550|SM8650)
    unset MESA_GL_VERSION_OVERRIDE
    unset MESA_GLSL_VERSION_OVERRIDE
    # SM8250: default to Vulkan (Turnip) when user hasn't explicitly chosen
    if [ "${DEVICE}" = "SM8250" ]; then
      if [ -z "${GRENDERER}" ] || [ "${GRENDERER}" = "0" ]; then
        GRENDERER="1"
      fi
    fi
    ;;
  *)
    # Panfrost/Mali: force GL 3.3 advertisement
    export MESA_GL_VERSION_OVERRIDE=3.3
    export MESA_GLSL_VERSION_OVERRIDE=330
    ;;
esac

  #Aspect Ratio
  case "$ASPECT" in
    0) sed -i '/^AspectRatio =/c\AspectRatio = 4:3' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    1) sed -i '/^AspectRatio =/c\AspectRatio = 16:9' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    2) sed -i '/^AspectRatio =/c\AspectRatio = Stretch' /storage/.config/aethersx2/inis/PCSX2.ini ;;
  esac

  #Bilinear Filtering
  case "$FILTER" in
    0|1|2|3) sed -i "/^filter =/c\filter = $FILTER" /storage/.config/aethersx2/inis/PCSX2.ini ;;
  esac

  #Graphics Backend — Renderer values: -1=auto, 12=Vulkan, 14=OpenGL, 13=Software
  case "$GRENDERER" in
    0) sed -i '/^Renderer =/c\Renderer = -1' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    1) sed -i '/^Renderer =/c\Renderer = 12' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    2) sed -i '/^Renderer =/c\Renderer = 14' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    3) sed -i '/^Renderer =/c\Renderer = 13' /storage/.config/aethersx2/inis/PCSX2.ini ;;
  esac

  #Internal Resolution
  if [ "$IRES" -gt "0" ] 2>/dev/null; then
    sed -i "/^upscale_multiplier =/c\upscale_multiplier = $IRES" /storage/.config/aethersx2/inis/PCSX2.ini
  else
    sed -i '/^upscale_multiplier =/c\upscale_multiplier = 1' /storage/.config/aethersx2/inis/PCSX2.ini
  fi

  #Show FPS
  case "$FPS" in
    true)  sed -i '/^OsdShowFPS =/c\OsdShowFPS = true' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    *)     sed -i '/^OsdShowFPS =/c\OsdShowFPS = false' /storage/.config/aethersx2/inis/PCSX2.ini ;;
  esac

  #EE Cycle Rate
  case "$RATE" in
    0) sed -i '/^EECycleRate =/c\EECycleRate = -3' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    1) sed -i '/^EECycleRate =/c\EECycleRate = -2' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    2) sed -i '/^EECycleRate =/c\EECycleRate = -1' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    3) sed -i '/^EECycleRate =/c\EECycleRate = 0' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    4) sed -i '/^EECycleRate =/c\EECycleRate = 1' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    5) sed -i '/^EECycleRate =/c\EECycleRate = 2' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    6) sed -i '/^EECycleRate =/c\EECycleRate = 3' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    *) sed -i '/^EECycleRate =/c\EECycleRate = 0' /storage/.config/aethersx2/inis/PCSX2.ini ;;
  esac

  #EE Cycle Skip
  case "$SKIP" in
    0|1|2|3) sed -i "/^EECycleSkip =/c\EECycleSkip = $SKIP" /storage/.config/aethersx2/inis/PCSX2.ini ;;
    *)       sed -i '/^EECycleSkip =/c\EECycleSkip = 0' /storage/.config/aethersx2/inis/PCSX2.ini ;;
  esac

  #HW download mode
  case "$HWDOWNLOAD" in
    0|1|2|3) sed -i "/^HWDownloadMode =/c\HWDownloadMode = $HWDOWNLOAD" /storage/.config/aethersx2/inis/PCSX2.ini ;;
    *)       sed -i '/^HWDownloadMode =/c\HWDownloadMode = 0' /storage/.config/aethersx2/inis/PCSX2.ini ;;
  esac

  #Widescreen patches
  case "$ENABLE_WIDESCREEN_PATCHES" in
    true) sed -i '/^EnableWideScreenPatches =/c\EnableWideScreenPatches = true' /storage/.config/aethersx2/inis/PCSX2.ini ;;
    *)    sed -i '/^EnableWideScreenPatches =/c\EnableWideScreenPatches = false' /storage/.config/aethersx2/inis/PCSX2.ini ;;
  esac

#Retroachievements
  /usr/bin/cheevos_aethersx2.sh

#Set QT environment to wayland
  export QT_QPA_PLATFORM=wayland

# Extra Libs needed to run
  export LD_LIBRARY_PATH=/usr/share/aethersx2-sa/libs

#Run Aethersx2 emulator
  export SDL_AUDIODRIVER=pulseaudio
  set_kill set "-9 aethersx2"
  ${EMUPERF} /usr/share/aethersx2-sa/aethersx2 -bigpicture -fullscreen "${1}"
