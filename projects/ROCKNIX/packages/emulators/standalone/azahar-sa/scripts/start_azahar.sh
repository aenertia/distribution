#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

. /etc/profile
. /usr/lib/rocknix-display/display-core.sh
set_kill set "-9 azahar"

# Load gptokeyb support files
control-gen_init.sh
source /storage/.config/gptokeyb/control.ini
get_controls

# Filesystem vars
IMMUTABLE_CONF_DIR="/usr/config/azahar"
CONF_DIR="/storage/.config/azahar"
CONF_FILE="${CONF_DIR}/qt-config.ini"
ROMS_DIR="/storage/roms/3ds"
SAVESTATES_DIR="/storage/roms/savestates/3ds"
SWAY_CONFIG="/storage/.config/sway/config"

# Make sure azahar config directory exists
[ ! -d ${CONF_DIR} ] && cp -r ${IMMUTABLE_CONF_DIR} /storage/.config
[ ! -d ${CONF_DIR}/log ] && mkdir -p ${CONF_DIR}/log

# Move sdmc & nand to 3ds roms folder
[ ! -d /storage/roms/3ds/azahar/sdmc ] && mkdir -p ${ROMS_DIR}/azahar/sdmc
rm -rf ${CONF_DIR}/sdmc
ln -sf ${ROMS_DIR}/azahar/sdmc ${CONF_DIR}/sdmc

[ ! -d ${ROMS_DIR}/azahar/nand ] && mkdir -p ${ROMS_DIR}/azahar/nand
rm -rf ${CONF_DIR}/nand
ln -sf ${ROMS_DIR}/azahar/nand ${CONF_DIR}/nand

# Move states to savestates folder
[ ! -d ${SAVESTATES_DIR} ] && mkdir -p ${SAVESTATES_DIR}
rm -rf ${CONF_DIR}/states
ln -sf ${SAVESTATES_DIR} ${CONF_DIR}/states

# RK3588 - handle different config files for ACE / CM5
if [ "${HW_DEVICE}" = "RK3588" ] && [ ! -f "${CONF_FILE}" ]; then
  if echo ${QUIRK_DEVICE} | grep CM5; then
    cp ${IMMUTABLE_CONF_DIR}/qt-config_CM5.ini ${CONF_FILE}
  else
    cp ${IMMUTABLE_CONF_DIR}/qt-config_ACE.ini ${CONF_FILE}
  fi
fi

# Make sure QT config file exists
[ ! -f "${CONF_FILE}" ] && cp ${IMMUTABLE_CONF_DIR}/qt-config.ini ${CONF_DIR}

# Make sure gptokeyb mapping files exist
[ ! -f "${CONF_DIR}/azahar.gptk" ] && cp ${IMMUTABLE_CONF_DIR}/azahar.gptk ${CONF_DIR}
[ ! -f "${CONF_DIR}/azahar_mouse_addon.gptk" ] && cp ${IMMUTABLE_CONF_DIR}/azahar_mouse_addon.gptk ${CONF_DIR}

# Emulation Station Features
GAME=$(echo "${1}"| sed "s#^/.*/##")
PLATFORM=$(echo "${2}"| sed "s#^/.*/##")
CPU=$(get_setting cpu_speed "${PLATFORM}" "${GAME}")
EMOUSE=$(get_setting emulate_mouse "${PLATFORM}" "${GAME}")
RENDERER=$(get_setting graphics_backend "${PLATFORM}" "${GAME}")
RES=$(get_setting resolution_scale "${PLATFORM}" "${GAME}")
INTEGER_SCALING=$(get_setting integer_scaling "${PLATFORM}" "${GAME}")
ROTATE=$(get_setting rotate_screen "${PLATFORM}" "${GAME}")
SLAYOUT=$(get_setting screen_layout "${PLATFORM}" "${GAME}")
CSHADERS=$(get_setting cache_shaders "${PLATFORM}" "${GAME}")
HSHADERS=$(get_setting hardware_shaders "${PLATFORM}" "${GAME}")
ACCURATE_HW_SHADERS=$(get_setting accurate_hardware_shaders "${PLATFORM}" "${GAME}")
DISABLE_RIGHT_EYE_RENDER=$(get_setting disable_right_eye_render "${PLATFORM}" "${GAME}")

#Set the cores to use
CORES=$(get_setting "cores" "${PLATFORM}" "${GAME}")
unset EMUPERF
[ "${CORES}" = "little" ] && EMUPERF="${SLOW_CORES}"
[ "${CORES}" = "big" ] && EMUPERF="${FAST_CORES}"

# CPU Underclock - default to 100% CPU speed
sed -i '/^cpu_clock_percentage\\default=/c\cpu_clock_percentage\\default=false' ${CONF_FILE}

case "${CPU}" in
  1) sed -i '/^cpu_clock_percentage=/c\cpu_clock_percentage=90' ${CONF_FILE};;
  2) sed -i '/^cpu_clock_percentage=/c\cpu_clock_percentage=80' ${CONF_FILE};;
  3) sed -i '/^cpu_clock_percentage=/c\cpu_clock_percentage=70' ${CONF_FILE};;
  4) sed -i '/^cpu_clock_percentage=/c\cpu_clock_percentage=60' ${CONF_FILE};;
  5) sed -i '/^cpu_clock_percentage=/c\cpu_clock_percentage=50' ${CONF_FILE};;
  *) sed -i '/^cpu_clock_percentage=/c\cpu_clock_percentage=100' ${CONF_FILE};;
esac

# Resolution Scale - default to Native 3DS
sed -i '/^resolution_factor\\default=/c\resolution_factor\\default=false' ${CONF_FILE}

case "${RES}" in
  0) sed -i '/^resolution_factor=/c\resolution_factor=0' ${CONF_FILE};;
  2) sed -i '/^resolution_factor=/c\resolution_factor=2' ${CONF_FILE};;
  3) sed -i '/^resolution_factor=/c\resolution_factor=3' ${CONF_FILE};;
  *) sed -i '/^resolution_factor=/c\resolution_factor=1' ${CONF_FILE};;
esac

# Integer scaling - default to false
sed -i '/^use_integer_scaling\\default=/c\use_integer_scaling\\default=false' ${CONF_FILE}

case "${INTEGER_SCALING}" in
  1) sed -i '/^use_integer_scaling=/c\use_integer_scaling=true' ${CONF_FILE};;
  *) sed -i '/^use_integer_scaling=/c\use_integer_scaling=false' ${CONF_FILE};;
esac

# Rotate Screen - default to false
sed -i '/^upright_screen\\default=/c\upright_screen\\default=false' ${CONF_FILE}

case "${ROTATE}" in
  1) sed -i '/^upright_screen=/c\upright_screen=true' ${CONF_FILE};;
  *) sed -i '/^upright_screen=/c\upright_screen=false' ${CONF_FILE};;
esac

# Cache Shaders - default to true
sed -i '/^use_disk_shader_cache\\default=/c\use_disk_shader_cache\\default=false' ${CONF_FILE}

case "${CSHADERS}" in
  0) sed -i '/^use_disk_shader_cache=/c\use_disk_shader_cache=false' ${CONF_FILE};;
  *) sed -i '/^use_disk_shader_cache=/c\use_disk_shader_cache=true' ${CONF_FILE};;
esac

# Hardware Shaders - default to true
sed -i '/^use_hw_shader\\default=/c\use_hw_shader\\default=false' ${CONF_FILE}

case "${HSHADERS}" in
  0) sed -i '/^use_hw_shader=/c\use_hw_shader=false' ${CONF_FILE};;
  *) sed -i '/^use_hw_shader=/c\use_hw_shader=true' ${CONF_FILE};;
esac

# Use accurate multiplication in hardware shaders - default to true
sed -i '/^shaders_accurate_mul\\default=/c\shaders_accurate_mul\\default=false' ${CONF_FILE}

case "${ACCURATE_HW_SHADERS}" in
  0) sed -i '/^shaders_accurate_mul=/c\shaders_accurate_mul=false' ${CONF_FILE};;
  *) sed -i '/^shaders_accurate_mul=/c\shaders_accurate_mul=true' ${CONF_FILE};;
esac

# Screen Layout - default to Top / Bottom, swap = false
sed -i '/^layout_option\\default=/c\layout_option\\default=false' ${CONF_FILE}
sed -i '/^swap_screen\\default=/c\swap_screen\\default=false' ${CONF_FILE}

case "${SLAYOUT}" in
  1a)
    # Single Screen (TOP)
    sed -i '/^layout_option=/c\layout_option=1' ${CONF_FILE}
    sed -i '/^swap_screen=/c\swap_screen=false' ${CONF_FILE}
    ;;
  1b)
    # Single Screen (BOTTOM)
    sed -i '/^layout_option=/c\layout_option=1' ${CONF_FILE}
    sed -i '/^swap_screen=/c\swap_screen=true' ${CONF_FILE}
    ;;
  2)
    # Large Screen, Small Screen
    sed -i '/^layout_option=/c\layout_option=2' ${CONF_FILE}
    sed -i '/^swap_screen=/c\swap_screen=false' ${CONF_FILE}
    ;;
  3)
    # Side by Side
    sed -i '/^layout_option=/c\layout_option=3' ${CONF_FILE}
    sed -i '/^swap_screen=/c\swap_screen=false' ${CONF_FILE}
    ;;
  5)
    # Separate windows
    sed -i '/^layout_option=/c\layout_option=4' "${CONF_FILE}"
    sed -i '/^swap_screen=/c\swap_screen=false' "${CONF_FILE}"
    ;;
  *)
    if display_is_dual && [ "$(get_setting system.stretched_mode)" = "1" ]; then
      # Stretched mode: vertical stacked in single window (watcher handles sway float)
      sed -i '/^layout_option=/c\layout_option=0' "${CONF_FILE}"
    elif display_is_dual; then
      # Dual-screen: custom layout — top 3DS screen fills top panel, bottom fills bottom panel
      # Dimensions queried from sway at runtime via display-core.sh
      # Must set both value AND \default=false — azahar ignores values when \default=true
      sed -i '/^layout_option=/c\layout_option=6' "${CONF_FILE}"
      sed -i '/^layout_option\\default=/c\layout_option\\default=false' "${CONF_FILE}"
      sed -i '/^fullscreen=/c\fullscreen=false' "${CONF_FILE}"
      sed -i '/^fullscreen\\default=/c\fullscreen\\default=false' "${CONF_FILE}"
      sed -i '/^screen_top_stretch=/c\screen_top_stretch=true' "${CONF_FILE}"
      sed -i '/^screen_top_stretch\\default=/c\screen_top_stretch\\default=false' "${CONF_FILE}"
      sed -i '/^screen_bottom_stretch=/c\screen_bottom_stretch=true' "${CONF_FILE}"
      sed -i '/^screen_bottom_stretch\\default=/c\screen_bottom_stretch\\default=false' "${CONF_FILE}"
      sed -i "/^custom_top_x=/c\custom_top_x=0" "${CONF_FILE}"
      sed -i '/^custom_top_x\\default=/c\custom_top_x\\default=false' "${CONF_FILE}"
      sed -i "/^custom_top_y=/c\custom_top_y=0" "${CONF_FILE}"
      sed -i '/^custom_top_y\\default=/c\custom_top_y\\default=false' "${CONF_FILE}"
      sed -i "/^custom_top_width=/c\custom_top_width=${PANEL_W}" "${CONF_FILE}"
      sed -i '/^custom_top_width\\default=/c\custom_top_width\\default=false' "${CONF_FILE}"
      sed -i "/^custom_top_height=/c\custom_top_height=${PANEL_H}" "${CONF_FILE}"
      sed -i '/^custom_top_height\\default=/c\custom_top_height\\default=false' "${CONF_FILE}"
      sed -i "/^custom_bottom_x=/c\custom_bottom_x=0" "${CONF_FILE}"
      sed -i '/^custom_bottom_x\\default=/c\custom_bottom_x\\default=false' "${CONF_FILE}"
      sed -i "/^custom_bottom_y=/c\custom_bottom_y=${PANEL_H}" "${CONF_FILE}"
      sed -i '/^custom_bottom_y\\default=/c\custom_bottom_y\\default=false' "${CONF_FILE}"
      sed -i "/^custom_bottom_width=/c\custom_bottom_width=${PANEL2_W}" "${CONF_FILE}"
      sed -i '/^custom_bottom_width\\default=/c\custom_bottom_width\\default=false' "${CONF_FILE}"
      sed -i "/^custom_bottom_height=/c\custom_bottom_height=${PANEL2_H}" "${CONF_FILE}"
      sed -i '/^custom_bottom_height\\default=/c\custom_bottom_height\\default=false' "${CONF_FILE}"
      # Hide Qt menubar and statusbar for clean fullscreen
      sed -i '/^displayTitleBars=/c\displayTitleBars=false' "${CONF_FILE}"
      sed -i '/^displayTitleBars\\default=/c\displayTitleBars\\default=false' "${CONF_FILE}"
      sed -i '/^showFilterBar=/c\showFilterBar=false' "${CONF_FILE}"
      sed -i '/^showFilterBar\\default=/c\showFilterBar\\default=false' "${CONF_FILE}"
      sed -i '/^showStatusBar=/c\showStatusBar=false' "${CONF_FILE}"
      sed -i '/^showStatusBar\\default=/c\showStatusBar\\default=false' "${CONF_FILE}"
      AZAHAR_DUAL=true
    else
      # Single screen: top / bottom stacked
      sed -i '/^layout_option=/c\layout_option=0' "${CONF_FILE}"
    fi
    sed -i '/^swap_screen=/c\swap_screen=false' "${CONF_FILE}"
    ;;
esac

# Force Disable Shader JIT
sed -i '/^use_shader_jit=/c\use_shader_jit=false' ${CONF_FILE}
sed -i '/^use_shader_jit\\default=/c\use_shader_jit\\default=false' ${CONF_FILE}

# Video Backend - default to Vulkan
sed -i '/^graphics_api\\default=/c\graphics_api\\default=false' ${CONF_FILE}

case "${RENDERER}" in
  1) sed -i '/^graphics_api=/c\graphics_api=1' ${CONF_FILE};;
  *) sed -i '/^graphics_api=/c\graphics_api=2' ${CONF_FILE};;
esac

# Disable Right Eye Rendering - default to false
sed -i '/^disable_right_eye_render\\default=/c\disable_right_eye_render\\default=false' ${CONF_FILE}

case "${DISABLE_RIGHT_EYE_RENDER}" in
  1) sed -i '/^disable_right_eye_render=/c\disable_right_eye_render=true' ${CONF_FILE};;
  *) sed -i '/^disable_right_eye_render=/c\disable_right_eye_render=false' ${CONF_FILE};;
esac

rm -rf /storage/.local/share/azahar
ln -sf ${CONF_DIR} /storage/.local/share/azahar

# QT platform - default to xcb, use wayland for libmali
export QT_QPA_PLATFORM=xcb
case ${HW_DEVICE} in
    RK3566|RK3588|S922X)
        [[ $(/usr/bin/gpudriver) == "libmali" ]] && export QT_QPA_PLATFORM=wayland
    ;;
esac

# Run Azahar Emulator
if [ "${EMOUSE}" = "0" ]; then
  # Use base gptk file
  ${GPTOKEYB} azahar -c ${CONF_DIR}/azahar.gptk &
else
  # Combine base gptk file with mouse control gptk file, inserting line break in between
  cat ${CONF_DIR}/azahar.gptk <(echo) ${CONF_DIR}/azahar_mouse_addon.gptk > /tmp/azahar.gptk
  ${GPTOKEYB} azahar -c /tmp/azahar.gptk &
fi

# Dual-screen: launch in background, stack outputs, position window
if [ "${AZAHAR_DUAL}" = "true" ]; then
    display_save_state
    display_stack_vertical

    ${EMUPERF} /usr/bin/azahar "${1}" &
    AZPID=$!

    display_wait_window 'app_id="org.azahar_emu.Azahar"' 10
    display_span_window 'app_id="org.azahar_emu.Azahar"'
    display_calibrate_touch_stacked

    wait $AZPID
else
    ${EMUPERF} /usr/bin/azahar "${1}"
fi
kill -9 $(pidof gptokeyb) 2>/dev/null

# Dual-screen: restore single-screen layout
if [ "${AZAHAR_DUAL}" = "true" ]; then
    display_restore
fi
