#!/bin/bash
# /usr/lib/rocknix-display/display-core.sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025-present ROCKNIX (https://github.com/ROCKNIX)
#
# Unified N-output display management for ROCKNIX
#
# Architecture: sourced by emulator start scripts, display-cycle CLI,
# and hotplug handlers. Replaces per-emulator bespoke sway manipulation
# with a shared library that queries output geometry at runtime via sway IPC.
#
# Supports any number of outputs (DSI, HDMI, DP, DisplayPort, USB-C DP).
# External outputs (HDMI/DP) are automatically promoted to primary.
# All dimensions computed from sway GET_OUTPUTS rect (post-transform,
# post-scale logical coordinates) — zero hardcoded panel sizes.
#
# Output data is stored as indexed variables:
#   DISPLAY_NAME_0, DISPLAY_W_0, DISPLAY_H_0, DISPLAY_TX_0  (primary)
#   DISPLAY_NAME_1, DISPLAY_W_1, DISPLAY_H_1, DISPLAY_TX_1  (secondary)
#   DISPLAY_NAME_2, ...                                       (tertiary, etc.)
#   DISPLAY_COUNT = total number of active outputs
#
# Backward-compatible aliases:
#   DISPLAY_PRIMARY = DISPLAY_NAME_0
#   DISPLAY_SECONDARY = DISPLAY_NAME_1
#   PANEL_W/PANEL_H = DISPLAY_W_0/DISPLAY_H_0
#   PANEL2_W/PANEL2_H = DISPLAY_W_1/DISPLAY_H_1
#
# Dependencies: swaymsg, python3
# See: ADR-consistent-coordinate-space.md

# --- State files (shared with display-cycle) ---
DISPLAY_STATE_DIR="/run/rocknix"
DISPLAY_STATE_FILE="${DISPLAY_STATE_DIR}/display_state"
DISPLAY_ACTIVE_FILE="${DISPLAY_STATE_DIR}/active_output"
DISPLAY_PRE_GAME_FILE="${DISPLAY_STATE_DIR}/display_pre_game"

# --- Indexed variable accessors ---
# Usage: display_get_name 0  → output name for index 0
#        display_get_width 2  → width for index 2
display_get_name()   { eval echo "\$DISPLAY_NAME_$1"; }
display_get_width()  { eval echo "\$DISPLAY_W_$1"; }
display_get_height() { eval echo "\$DISPLAY_H_$1"; }
display_get_tx()     { eval echo "\$DISPLAY_TX_$1"; }

# --- Initialization (idempotent, auto-called on first use) ---

_display_init() {
    [ -n "${_DISPLAY_INITED:-}" ] && return 0
    _DISPLAY_INITED=1
    mkdir -p "$DISPLAY_STATE_DIR"

    SWAYSOCK="${SWAYSOCK:-/run/0-runtime-dir/sway-ipc.0.sock}"
    export SWAYSOCK

    # Query sway for active outputs via IPC
    local outputs_json
    outputs_json=$(swaymsg -t get_outputs -r 2>/dev/null) || return 1

    # Parse N outputs with priority sorting via python3.
    # External connectors (HDMI/DP/DisplayPort) are promoted to front.
    # CRITICAL: use rect (post-transform, post-scale) not current_mode.
    # rect gives the logical size in sway's virtual coordinate space:
    #   - A 1024x600 panel with transform=270 has rect 600x1024 (swapped)
    #   - A panel with scale=1.4 has rect dimensions scaled down accordingly
    eval "$(printf '%s' "$outputs_json" | python3 -c "
import json, sys

def output_priority(o):
    n = o['name']
    # External outputs get highest priority (promoted to primary)
    if n.startswith(('HDMI', 'DP-', 'DisplayPort')):
        return (0, n)
    # Built-in DSI panels
    if n.startswith('DSI'):
        return (1, n)
    # Everything else (HEADLESS, etc.)
    return (2, n)

outs = [o for o in json.load(sys.stdin) if o.get('active')]
if not outs:
    sys.exit(0)

outs.sort(key=output_priority)

print(f'DISPLAY_COUNT={len(outs)}')
for i, o in enumerate(outs):
    r = o.get('rect', {})
    w = r.get('width', o['current_mode']['width'])
    h = r.get('height', o['current_mode']['height'])
    tx = o.get('transform', 'normal')
    print(f'DISPLAY_NAME_{i}=\"{o[\"name\"]}\"')
    print(f'DISPLAY_W_{i}={w}')
    print(f'DISPLAY_H_{i}={h}')
    print(f'DISPLAY_TX_{i}=\"{tx}\"')
" 2>/dev/null)"

    # Defaults if sway query failed
    DISPLAY_COUNT="${DISPLAY_COUNT:-1}"
    DISPLAY_NAME_0="${DISPLAY_NAME_0:-${WLR_CON:-DSI-1}}"
    DISPLAY_W_0="${DISPLAY_W_0:-640}"
    DISPLAY_H_0="${DISPLAY_H_0:-480}"
    DISPLAY_TX_0="${DISPLAY_TX_0:-normal}"

    # --- Backward-compatible aliases ---
    DISPLAY_PRIMARY="$DISPLAY_NAME_0"
    PANEL_W="$DISPLAY_W_0"
    PANEL_H="$DISPLAY_H_0"
    DISPLAY_PRIMARY_TRANSFORM="$DISPLAY_TX_0"

    DISPLAY_SECONDARY=""
    PANEL2_W="$PANEL_W"
    PANEL2_H="$PANEL_H"
    DISPLAY_SECONDARY_TRANSFORM="normal"
    if [ "$DISPLAY_COUNT" -ge 2 ]; then
        DISPLAY_SECONDARY="$DISPLAY_NAME_1"
        PANEL2_W="$DISPLAY_W_1"
        PANEL2_H="$DISPLAY_H_1"
        DISPLAY_SECONDARY_TRANSFORM="$DISPLAY_TX_1"
    fi

    # Legacy aliases
    DISPLAY_TOP="$DISPLAY_PRIMARY"
    DISPLAY_BOTTOM="$DISPLAY_SECONDARY"

    # --- Re-apply session-persisted transforms ---
    # Transform state files survive within a session (tmpfs) but reset on reboot.
    local _saved_tx _i _name _cur_tx
    for _i in $(seq 0 $((DISPLAY_COUNT - 1))); do
        if [ -f "${DISPLAY_STATE_DIR}/transform_${_i}" ]; then
            read -r _saved_tx < "${DISPLAY_STATE_DIR}/transform_${_i}"
            _name=$(display_get_name $_i)
            _cur_tx=$(display_get_tx $_i)
            if [ -n "$_saved_tx" ] && [ "$_saved_tx" != "$_cur_tx" ]; then
                swaymsg "output ${_name} transform ${_saved_tx}" 2>/dev/null
                eval "DISPLAY_TX_${_i}=\"${_saved_tx}\""
            fi
        fi
    done

    # Apply device-mandated secondary transform (e.g., AYANEO PDS DSI-2 at 270)
    if [ -n "${ROCKNIX_SECONDARY_TRANSFORM:-}" ] && [ "$DISPLAY_COUNT" -ge 2 ]; then
        if [ "$DISPLAY_TX_1" != "$ROCKNIX_SECONDARY_TRANSFORM" ]; then
            swaymsg "output ${DISPLAY_NAME_1} transform ${ROCKNIX_SECONDARY_TRANSFORM}" 2>/dev/null
            DISPLAY_TX_1="$ROCKNIX_SECONDARY_TRANSFORM"
        fi
    fi
    # Update backward compat aliases after transform re-application
    DISPLAY_PRIMARY_TRANSFORM="$DISPLAY_TX_0"
    [ "$DISPLAY_COUNT" -ge 2 ] && DISPLAY_SECONDARY_TRANSFORM="$DISPLAY_TX_1"

    # --- N-output canvas geometry (vertical stacking) ---
    # Canvas width = max of all panel widths
    # Canvas height = sum of all panel heights
    # Per-output: VSTACK_X_{i} = centering offset, VSTACK_Y_{i} = cumulative Y
    CANVAS_W=0
    CANVAS_H=0
    local _w _h _cum_y=0
    for _i in $(seq 0 $((DISPLAY_COUNT - 1))); do
        _w=$(display_get_width $_i)
        _h=$(display_get_height $_i)
        [ "$_w" -gt "$CANVAS_W" ] && CANVAS_W="$_w"
        CANVAS_H=$((_cum_y + _h))
        eval "VSTACK_Y_${_i}=${_cum_y}"
        _cum_y=$((CANVAS_H))
    done
    # Compute centering offsets
    for _i in $(seq 0 $((DISPLAY_COUNT - 1))); do
        _w=$(display_get_width $_i)
        eval "VSTACK_X_${_i}=$(( (CANVAS_W - _w) / 2 ))"
    done
    # Legacy aliases for 2-output callers
    VSTACK_PRI_X="${VSTACK_X_0:-0}"
    VSTACK_SEC_X="${VSTACK_X_1:-0}"

    # Horizontal stack geometry (for 2-output compat)
    if [ "$DISPLAY_COUNT" -ge 2 ]; then
        CANVAS_W_HORIZ=$((PANEL_W + PANEL2_W))
        if [ "$PANEL_H" -ge "$PANEL2_H" ]; then
            CANVAS_H_HORIZ="$PANEL_H"
        else
            CANVAS_H_HORIZ="$PANEL2_H"
        fi
    else
        CANVAS_W_HORIZ="$PANEL_W"
        CANVAS_H_HORIZ="$PANEL_H"
    fi

    # --- Auto-detect touch devices ---
    # Detect all touch devices, store first as TOUCH_DEVICE for compat
    TOUCH_DEVICE=""
    local inputs_json
    inputs_json=$(swaymsg -t get_inputs -r 2>/dev/null) || true
    if [ -n "$inputs_json" ]; then
        TOUCH_DEVICE=$(printf '%s' "$inputs_json" | python3 -c "
import json, sys
for i in json.load(sys.stdin):
    if i.get('type') == 'touch':
        print(i['identifier']); break
" 2>/dev/null)
    fi
    TOUCH_DEVICE="${ROCKNIX_TOUCH_DEVICE:-$TOUCH_DEVICE}"

    return 0
}

# --- Predicates ---

display_is_dual()   { _display_init; [ "$DISPLAY_COUNT" -ge 2 ]; }
display_is_triple() { _display_init; [ "$DISPLAY_COUNT" -ge 3 ]; }
display_output_count() { _display_init; echo "$DISPLAY_COUNT"; }

display_get_primary() {
    _display_init
    printf '%s' "$DISPLAY_PRIMARY"
}

display_get_secondary() {
    _display_init
    printf '%s' "$DISPLAY_SECONDARY"
}

# --- Layout Actions ---

# Stack all outputs vertically: first on top, each subsequent below.
# Handles asymmetric panels by centering narrower outputs.
# Works for any number of outputs (1, 2, 3, ...).
display_stack_vertical() {
    _display_init
    local _i _name _x _y
    for _i in $(seq 0 $((DISPLAY_COUNT - 1))); do
        _name=$(display_get_name $_i)
        _x=$(eval echo "\$VSTACK_X_${_i}")
        _y=$(eval echo "\$VSTACK_Y_${_i}")
        swaymsg "output ${_name} power on" 2>/dev/null
        swaymsg "output ${_name} pos ${_x} ${_y}" 2>/dev/null
    done
}

# Stack outputs horizontally: primary on left, rest to the right.
# (2-output compat — for N>2, consider display_stack_vertical)
display_stack_horizontal() {
    _display_init
    local hstack_pri_y=0 hstack_sec_y=0
    if [ "$PANEL_H" -ge "$PANEL2_H" ]; then
        hstack_sec_y=$(( (PANEL_H - PANEL2_H) / 2 ))
    else
        hstack_pri_y=$(( (PANEL2_H - PANEL_H) / 2 ))
    fi
    swaymsg "output ${DISPLAY_PRIMARY} power on" 2>/dev/null
    swaymsg "output ${DISPLAY_SECONDARY} power on" 2>/dev/null
    swaymsg "output ${DISPLAY_PRIMARY} pos 0 ${hstack_pri_y}" 2>/dev/null
    swaymsg "output ${DISPLAY_SECONDARY} pos ${PANEL_W} ${hstack_sec_y}" 2>/dev/null
}

# --- Window Management ---

# Wait for a window matching CRITERIA to appear (polls sway tree).
# Usage: display_wait_window 'app_id="drastic"' [timeout_seconds]
display_wait_window() {
    local criteria="$1" timeout="${2:-10}" i=0
    while [ "$i" -lt "$timeout" ]; do
        sleep 1
        i=$((i + 1))
        swaymsg "[$criteria]" nop 2>/dev/null && return 0
    done
    return 1
}

# Float window and resize to span all outputs (vertical stack).
# Uses the computed canvas geometry — no hardcoded dimensions.
# Usage: display_span_window 'app_id="org.azahar_emu.Azahar"'
display_span_window() {
    local criteria="$1"
    _display_init
    # Window origin at leftmost output x coordinate
    local win_x="$CANVAS_W" _i _x
    for _i in $(seq 0 $((DISPLAY_COUNT - 1))); do
        _x=$(eval echo "\$VSTACK_X_${_i}")
        [ "$_x" -lt "$win_x" ] && win_x="$_x"
    done
    swaymsg "[$criteria]" floating enable, fullscreen disable, border none, \
        resize set "$CANVAS_W" "$CANVAS_H", \
        move to output "$DISPLAY_PRIMARY", \
        move absolute position "$win_x" 0 2>/dev/null
}

# Fullscreen each window on its own output (melonDS dual-window pattern).
# Usage: display_fullscreen_split 'title="\[w1\].*melonDS"' 'title="\[w2\].*melonDS"'
display_fullscreen_split() {
    local criteria_top="$1" criteria_bottom="$2"
    _display_init
    swaymsg "[$criteria_top]" move to output "$DISPLAY_TOP", fullscreen enable 2>/dev/null
    swaymsg "[$criteria_bottom]" move to output "$DISPLAY_BOTTOM", fullscreen enable 2>/dev/null
}

# --- Per-Output Transform (Rotation) ---
#
# Transforms are managed per-output by index and persisted within a session
# via /run/rocknix/transform_{index} state files (tmpfs, cleared on reboot).
# Sway transform values: normal, 90, 180, 270,
#   flipped, flipped-90, flipped-180, flipped-270

# Set transform on a specific output by index or position name.
# Persists to session state file. Forces re-init to pick up new rect geometry.
# Usage: display_set_transform 0|1|2|top|bottom normal|90|180|270|flipped|...
display_set_transform() {
    local position="$1" transform="$2"
    _display_init
    local idx output
    case "$position" in
        top)    idx=0 ;;
        bottom) idx=1 ;;
        *)      idx="$position" ;;
    esac
    output=$(display_get_name $idx)
    [ -z "$output" ] && return 1
    swaymsg "output ${output} transform ${transform}" 2>/dev/null
    sleep 0.1
    printf '%s' "$transform" > "${DISPLAY_STATE_DIR}/transform_${idx}"
    _DISPLAY_INITED=""
    _display_init
}

# Cycle transform for an output through all 8 sway transforms.
# Usage: display_cycle_transform 0|1|2|top|bottom
display_cycle_transform() {
    local position="$1"
    _display_init
    local idx
    case "$position" in
        top)    idx=0 ;;
        bottom) idx=1 ;;
        *)      idx="$position" ;;
    esac
    local current
    current=$(display_get_tx $idx)

    local next
    case "$current" in
        normal)      next="90" ;;
        90)          next="180" ;;
        180)         next="270" ;;
        270)         next="flipped" ;;
        flipped)     next="flipped-90" ;;
        flipped-90)  next="flipped-180" ;;
        flipped-180) next="flipped-270" ;;
        flipped-270) next="normal" ;;
        *)           next="normal" ;;
    esac

    display_set_transform "$idx" "$next"
}

# Get the current transform for an output by index or position.
# Usage: display_get_transform 0|1|top|bottom
display_get_transform() {
    local position="$1"
    _display_init
    local idx
    case "$position" in
        top)    idx=0 ;;
        bottom) idx=1 ;;
        *)      idx="$position" ;;
    esac
    display_get_tx "$idx"
}

# --- Touch Calibration ---
#
# The sway calibration_matrix is a 2x3 affine transform (6 floats: a b c d e f):
#   logical_x = a * physical_x + b * physical_y + c
#   logical_y = d * physical_x + e * physical_y + f
#
# Base rotation matrices (assuming touch reports physical panel coordinates):
#   normal:      1  0  0   0  1  0
#   90 (CW):     0 -1  1   1  0  0
#   180:        -1  0  1   0 -1  1
#   270 (CW):    0  1  0  -1  0  1
#   flipped:    -1  0  1   0  1  0
#   flipped-90:  0 -1  1  -1  0  1
#   flipped-180: 1  0  0   0 -1  1
#   flipped-270: 0  1  0   1  0  0

# Internal: get the base rotation matrix for a transform string.
_display_touch_rotation_matrix() {
    local transform="$1"
    case "$transform" in
        normal|"")   echo "1 0 0 0 1 0" ;;
        90)          echo "0 -1 1 1 0 0" ;;
        180)         echo "-1 0 1 0 -1 1" ;;
        270)         echo "0 1 0 -1 0 1" ;;
        flipped)     echo "-1 0 1 0 1 0" ;;
        flipped-90)  echo "0 -1 1 -1 0 1" ;;
        flipped-180) echo "1 0 0 0 -1 1" ;;
        flipped-270) echo "0 1 0 1 0 0" ;;
        *)           echo "1 0 0 0 1 0" ;;
    esac
}

# Calibrate touch for vertical stacking with rotation awareness.
# Composes primary output's rotation matrix with Y-axis scaling for stacking.
display_calibrate_touch_stacked() {
    _display_init
    [ -z "$TOUCH_DEVICE" ] && return 0

    local sy
    sy=$(awk "BEGIN { printf \"%.4f\", ${PANEL_H} / ${CANVAS_H} }")

    local matrix a b c d e f
    matrix=$(_display_touch_rotation_matrix "$DISPLAY_PRIMARY_TRANSFORM")
    read -r a b c d e f <<< "$matrix"

    local ds es fs
    ds=$(awk "BEGIN { printf \"%.4f\", ${d} * ${sy} }")
    es=$(awk "BEGIN { printf \"%.4f\", ${e} * ${sy} }")
    fs=$(awk "BEGIN { printf \"%.4f\", ${f} * ${sy} }")

    swaymsg "input \"$TOUCH_DEVICE\" calibration_matrix ${a} ${b} ${c} ${ds} ${es} ${fs}" 2>/dev/null
}

# Calibrate touch for a specific output in the vertical stack.
# Maps touch to the region of the canvas occupied by output at index.
# Usage: display_calibrate_touch_for_output INDEX [touch_device_id]
display_calibrate_touch_for_output() {
    local target_idx="$1"
    local touch_dev="${2:-$TOUCH_DEVICE}"
    _display_init
    [ -z "$touch_dev" ] && return 0

    local panel_h target_y tx
    panel_h=$(display_get_height $target_idx)
    target_y=$(eval echo "\$VSTACK_Y_${target_idx}")
    tx=$(display_get_tx $target_idx)

    local sy oy
    sy=$(awk "BEGIN { printf \"%.4f\", ${panel_h} / ${CANVAS_H} }")
    oy=$(awk "BEGIN { printf \"%.4f\", ${target_y} / ${CANVAS_H} }")

    local matrix a b c d e f
    matrix=$(_display_touch_rotation_matrix "$tx")
    read -r a b c d e f <<< "$matrix"

    # Compose rotation with stacking: scale d/e row by sy, offset f by oy
    local ds es fs
    ds=$(awk "BEGIN { printf \"%.4f\", ${d} * ${sy} }")
    es=$(awk "BEGIN { printf \"%.4f\", ${e} * ${sy} }")
    fs=$(awk "BEGIN { printf \"%.4f\", ${f} * ${sy} + ${oy} }")

    swaymsg "input \"$touch_dev\" calibration_matrix ${a} ${b} ${c} ${ds} ${es} ${fs}" 2>/dev/null
}

# Calibrate touch for a single output (no stacking) with rotation.
display_calibrate_touch_rotated() {
    _display_init
    [ -z "$TOUCH_DEVICE" ] && return 0
    local transform="${1:-$DISPLAY_PRIMARY_TRANSFORM}"
    local matrix
    matrix=$(_display_touch_rotation_matrix "$transform")
    swaymsg "input \"$TOUCH_DEVICE\" calibration_matrix ${matrix}" 2>/dev/null
}

# Reset touch calibration to identity matrix.
display_calibrate_touch_reset() {
    _display_init
    [ -n "$TOUCH_DEVICE" ] && \
        swaymsg "input \"$TOUCH_DEVICE\" calibration_matrix 1 0 0 0 1 0" 2>/dev/null
}

# Map touch input directly to a specific output.
display_map_touch_to() {
    local output="$1"
    _display_init
    [ -n "$TOUCH_DEVICE" ] && \
        swaymsg "input \"$TOUCH_DEVICE\" map_to_output $output" 2>/dev/null
}

# --- Lifecycle (Pre/Post Game) ---

# Save current display state before game launch.
display_save_state() {
    _display_init
    local state
    state=$(cat "$DISPLAY_STATE_FILE" 2>/dev/null || echo "active_0")
    printf '%s' "$state" > "$DISPLAY_PRE_GAME_FILE"
}

# Restore display state after game exit.
# Powers off all non-primary outputs, resets primary position, resets touch.
display_restore() {
    _display_init
    local _i _name
    for _i in $(seq 1 $((DISPLAY_COUNT - 1))); do
        _name=$(display_get_name $_i)
        swaymsg "output ${_name} power off" 2>/dev/null
    done
    swaymsg "output ${DISPLAY_PRIMARY} pos 0 0" 2>/dev/null
    display_calibrate_touch_reset

    if [ -f "$DISPLAY_PRE_GAME_FILE" ]; then
        local pre_state
        read -r pre_state < "$DISPLAY_PRE_GAME_FILE"
        rm -f "$DISPLAY_PRE_GAME_FILE"
        printf '%s' "$pre_state" > "$DISPLAY_STATE_FILE"
    fi
}

# Update WLR_CON (shared with display-cycle and 095-sway profile).
display_update_active() {
    local new_con="$1"
    sed -i "s|^WLR_CON=.*|WLR_CON=${new_con}|" /storage/.config/profile.d/095-sway 2>/dev/null
    export WLR_CON="${new_con}"
    printf '%s' "${new_con}" > "$DISPLAY_ACTIVE_FILE"
}

# Update SDL_VIDEO_DISPLAY_PRIORITY to reflect current output ordering.
display_update_sdl_priority() {
    _display_init
    local prio="" _i
    for _i in $(seq 0 $((DISPLAY_COUNT - 1))); do
        [ -n "$prio" ] && prio="${prio},"
        prio="${prio}$(display_get_name $_i)"
    done
    sed -i "s|^SDL_VIDEO_DISPLAY_PRIORITY=.*|SDL_VIDEO_DISPLAY_PRIORITY=${prio}|" \
        /storage/.config/profile.d/095-sway 2>/dev/null
    export SDL_VIDEO_DISPLAY_PRIORITY="${prio}"
}

# --- Mirror Mode ---
#
# Two mirror strategies:
# 1. Sway overlap: all outputs at pos 0,0. Sway renders the same virtual
#    content to all, applying each output's transform independently.
# 2. wl-mirror: captures screencopy from source, renders to each target.

MIRROR_PID_FILE="${DISPLAY_STATE_DIR}/wl-mirror.pid"
MIRROR_SCALE_FILE="${DISPLAY_STATE_DIR}/mirror_scale"

display_gpu_supports_wl_mirror() {
    local drv
    drv=$(/usr/bin/gpudriver 2>/dev/null)
    [ "$drv" != "libmali" ]
}

# Check if all outputs have the same post-transform logical dimensions
display_outputs_same_res() {
    _display_init
    [ "$DISPLAY_COUNT" -lt 2 ] && return 0
    local _i _w _h
    for _i in $(seq 1 $((DISPLAY_COUNT - 1))); do
        _w=$(display_get_width $_i)
        _h=$(display_get_height $_i)
        [ "$_w" -ne "$PANEL_W" ] || [ "$_h" -ne "$PANEL_H" ] && return 1
    done
    return 0
}

_display_mirror_transform() {
    local source_tx="$1" target_tx="$2"
    [ "$source_tx" = "$target_tx" ] && { echo "normal"; return; }
    # wl-mirror auto-corrects for source/target transforms when fullscreened
    echo "normal"
}

# Kill any running wl-mirror processes
display_kill_mirror() {
    if [ -f "$MIRROR_PID_FILE" ]; then
        local _pid
        while read -r _pid; do
            kill "$_pid" 2>/dev/null
        done < "$MIRROR_PID_FILE"
        rm -f "$MIRROR_PID_FILE"
    fi
    killall wl-mirror 2>/dev/null
    rm -f "$MIRROR_SCALE_FILE"
}

# Mirror via sway output overlap (all outputs at pos 0,0).
display_mirror_overlap() {
    local criteria="${1:-[app_id=\"emulationstation\"]}"
    _display_init
    display_kill_mirror
    local _i _name
    for _i in $(seq 0 $((DISPLAY_COUNT - 1))); do
        _name=$(display_get_name $_i)
        swaymsg "output ${_name} power on" 2>/dev/null
        swaymsg "output ${_name} pos 0 0" 2>/dev/null
    done
    swaymsg "${criteria}" fullscreen enable 2>/dev/null
    display_update_active "${DISPLAY_PRIMARY}"
    echo "mirror" > "$DISPLAY_STATE_FILE"
}

# Mirror via wl-mirror to all non-primary outputs.
display_mirror_wl() {
    local scale_mode="${1:-fit}"
    _display_init
    local source="${WLR_CON:-$DISPLAY_PRIMARY}"

    display_kill_mirror
    display_stack_vertical

    local source_tx _i _target _target_tx _mirror_tx
    source_tx=$(display_get_transform 0)

    # Launch a wl-mirror instance for each non-primary output
    rm -f "$MIRROR_PID_FILE"
    for _i in $(seq 1 $((DISPLAY_COUNT - 1))); do
        _target=$(display_get_name $_i)
        _target_tx=$(display_get_tx $_i)
        _mirror_tx=$(_display_mirror_transform "$source_tx" "$_target_tx")

        local wl_args="-S -b screencopy -s $scale_mode -F --fullscreen-output $_target"
        [ "$_mirror_tx" != "normal" ] && wl_args="$wl_args -t $_mirror_tx"

        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/0-runtime-dir}" \
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
            /usr/bin/wl-mirror $wl_args "$source" &
        echo $! >> "$MIRROR_PID_FILE"
    done
    echo "$scale_mode" > "$MIRROR_SCALE_FILE"
    echo "mirror" > "$DISPLAY_STATE_FILE"
}

# Cycle wl-mirror scaling mode.
display_cycle_mirror_scale() {
    if [ ! -f "$MIRROR_PID_FILE" ]; then
        return 1
    fi
    local _first_pid
    read -r _first_pid < "$MIRROR_PID_FILE"
    kill -0 "$_first_pid" 2>/dev/null || return 1

    local current_scale="fit"
    [ -f "$MIRROR_SCALE_FILE" ] && read -r current_scale < "$MIRROR_SCALE_FILE"

    local new_scale
    case "$current_scale" in
        fit)   new_scale="cover" ;;
        cover) new_scale="exact" ;;
        exact) new_scale="fit" ;;
        *)     new_scale="fit" ;;
    esac

    # Send to all wl-mirror instances
    local _pid
    while read -r _pid; do
        echo "-s $new_scale" > /proc/${_pid}/fd/0 2>/dev/null
    done < "$MIRROR_PID_FILE"
    echo "$new_scale" > "$MIRROR_SCALE_FILE"
}

# Auto-select best mirror method.
display_mirror_auto() {
    local criteria="${1:-[app_id=\"emulationstation\"]}"
    _display_init
    local _all_same_tx=true _i
    for _i in $(seq 1 $((DISPLAY_COUNT - 1))); do
        [ "$(display_get_tx $_i)" != "$DISPLAY_PRIMARY_TRANSFORM" ] && _all_same_tx=false
    done

    if display_outputs_same_res && [ "$_all_same_tx" = true ]; then
        display_mirror_overlap "$criteria"
    elif display_gpu_supports_wl_mirror && [ -x /usr/bin/wl-mirror ]; then
        display_mirror_wl "fit"
    else
        display_mirror_overlap "$criteria"
    fi
}

# --- Per-Panel Scaling ---

# Compute window geometry for a given scaling mode on a panel by index.
# Sets SCALE_W, SCALE_H, SCALE_X, SCALE_Y.
# Usage: display_set_scale_mode 0|1|top|bottom stretch|fit|integer [content_w content_h]
display_set_scale_mode() {
    local position="$1" mode="$2"
    local content_w="${3:-0}" content_h="${4:-0}"
    _display_init

    local idx
    case "$position" in
        top)    idx=0 ;;
        bottom) idx=1 ;;
        *)      idx="$position" ;;
    esac

    local panel_w panel_h panel_x panel_y
    panel_w=$(display_get_width $idx)
    panel_h=$(display_get_height $idx)
    panel_x=$(eval echo "\$VSTACK_X_${idx}")
    panel_y=$(eval echo "\$VSTACK_Y_${idx}")

    printf '%s' "$mode" > "${DISPLAY_STATE_DIR}/scale_mode_${idx}"

    case "$mode" in
        stretch)
            SCALE_W="$panel_w"; SCALE_H="$panel_h"
            SCALE_X="$panel_x"; SCALE_Y="$panel_y"
            ;;
        fit)
            if [ "$content_w" -gt 0 ] && [ "$content_h" -gt 0 ]; then
                eval "$(awk "BEGIN {
                    sw = ${panel_w} / ${content_w}
                    sh = ${panel_h} / ${content_h}
                    s = (sw < sh) ? sw : sh
                    w = int(${content_w} * s)
                    h = int(${content_h} * s)
                    ox = int((${panel_w} - w) / 2)
                    oy = int((${panel_h} - h) / 2)
                    printf \"SCALE_W=%d SCALE_H=%d SCALE_X=%d SCALE_Y=%d\", w, h, ${panel_x}+ox, ${panel_y}+oy
                }")"
            else
                SCALE_W="$panel_w"; SCALE_H="$panel_h"
                SCALE_X="$panel_x"; SCALE_Y="$panel_y"
            fi
            ;;
        integer)
            if [ "$content_w" -gt 0 ] && [ "$content_h" -gt 0 ]; then
                eval "$(awk "BEGIN {
                    nx = int(${panel_w} / ${content_w})
                    ny = int(${panel_h} / ${content_h})
                    n = (nx < ny) ? nx : ny
                    if (n < 1) n = 1
                    w = ${content_w} * n
                    h = ${content_h} * n
                    ox = int((${panel_w} - w) / 2)
                    oy = int((${panel_h} - h) / 2)
                    printf \"SCALE_W=%d SCALE_H=%d SCALE_X=%d SCALE_Y=%d\", w, h, ${panel_x}+ox, ${panel_y}+oy
                }")"
            else
                SCALE_W="$panel_w"; SCALE_H="$panel_h"
                SCALE_X="$panel_x"; SCALE_Y="$panel_y"
            fi
            ;;
    esac
}

# Cycle scaling mode: stretch → fit → integer → stretch
display_cycle_scale() {
    local position="$1"
    local content_w="${2:-0}" content_h="${3:-0}"
    local idx
    case "$position" in
        top)    idx=0 ;;
        bottom) idx=1 ;;
        *)      idx="$position" ;;
    esac
    local current
    current=$(cat "${DISPLAY_STATE_DIR}/scale_mode_${idx}" 2>/dev/null || echo "stretch")

    local next
    case "$current" in
        stretch)  next="fit" ;;
        fit)      next="integer" ;;
        integer)  next="stretch" ;;
        *)        next="stretch" ;;
    esac

    display_set_scale_mode "$position" "$next" "$content_w" "$content_h"
}

# Apply computed scale to a window.
display_apply_scale() {
    local criteria="$1"
    swaymsg "[$criteria]" floating enable, border none, \
        resize set "$SCALE_W" "$SCALE_H", \
        move absolute position "$SCALE_X" "$SCALE_Y" 2>/dev/null
}
