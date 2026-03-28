#!/bin/bash
# /usr/lib/rocknix-display/display-core.sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025-present ROCKNIX (https://github.com/ROCKNIX)
#
# Unified multi-output display management for ROCKNIX
#
# Architecture: sourced by emulator start scripts and display-cycle CLI.
# Replaces per-emulator bespoke sway manipulation with a shared library
# that queries output geometry at runtime via sway IPC.
#
# All dimensions are computed from sway GET_OUTPUTS rect (post-transform,
# post-scale logical coordinates) — zero hardcoded panel sizes.
#
# Dependencies: swaymsg, python3 (already present in display-cycle)
#
# See: ADR-consistent-coordinate-space.md

# --- State files (shared with display-cycle) ---
DISPLAY_STATE_DIR="/run/rocknix"
DISPLAY_STATE_FILE="${DISPLAY_STATE_DIR}/display_state"
DISPLAY_ACTIVE_FILE="${DISPLAY_STATE_DIR}/active_output"
DISPLAY_PRE_GAME_FILE="${DISPLAY_STATE_DIR}/display_pre_game"

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

    # Parse output names, dimensions, and transforms via python3 (precedent: display-cycle)
    # CRITICAL: use rect (post-transform, post-scale) not current_mode (hardware pixels).
    # rect gives the logical size in sway's virtual coordinate space:
    #   - A 1024x600 panel with transform=270 has rect 600x1024 (swapped)
    #   - A panel with scale=1.4 has rect dimensions scaled down accordingly
    # transform is returned as a string: "normal", "90", "180", "270",
    #   "flipped", "flipped-90", "flipped-180", "flipped-270"
    eval "$(printf '%s' "$outputs_json" | python3 -c "
import json, sys
outs = [o for o in json.load(sys.stdin) if o.get('active')]
if not outs:
    sys.exit(0)
pri = outs[0]
r = pri.get('rect', {})
w = r.get('width', pri['current_mode']['width'])
h = r.get('height', pri['current_mode']['height'])
print(f'DISPLAY_PRIMARY=\"{pri[\"name\"]}\"')
print(f'PANEL_W={w}')
print(f'PANEL_H={h}')
print(f'DISPLAY_PRIMARY_TRANSFORM=\"{pri.get(\"transform\", \"normal\")}\"')
if len(outs) > 1:
    sec = outs[1]
    r2 = sec.get('rect', {})
    w2 = r2.get('width', sec['current_mode']['width'])
    h2 = r2.get('height', sec['current_mode']['height'])
    print(f'DISPLAY_SECONDARY=\"{sec[\"name\"]}\"')
    print(f'PANEL2_W={w2}')
    print(f'PANEL2_H={h2}')
    print(f'DISPLAY_SECONDARY_TRANSFORM=\"{sec.get(\"transform\", \"normal\")}\"')
" 2>/dev/null)"

    # Defaults if sway query failed or returned nothing
    DISPLAY_PRIMARY="${DISPLAY_PRIMARY:-${WLR_CON:-DSI-1}}"
    DISPLAY_SECONDARY="${DISPLAY_SECONDARY:-}"
    PANEL_W="${PANEL_W:-640}"
    PANEL_H="${PANEL_H:-480}"
    PANEL2_W="${PANEL2_W:-$PANEL_W}"
    PANEL2_H="${PANEL2_H:-$PANEL_H}"
    DISPLAY_PRIMARY_TRANSFORM="${DISPLAY_PRIMARY_TRANSFORM:-normal}"
    DISPLAY_SECONDARY_TRANSFORM="${DISPLAY_SECONDARY_TRANSFORM:-normal}"

    # Re-apply session-persisted transforms if they differ from current sway state.
    # Transform state files survive within a session (tmpfs) but reset on reboot.
    local _saved_tx
    if [ -f "${DISPLAY_STATE_DIR}/transform_top" ]; then
        read -r _saved_tx < "${DISPLAY_STATE_DIR}/transform_top"
        if [ -n "$_saved_tx" ] && [ "$_saved_tx" != "$DISPLAY_PRIMARY_TRANSFORM" ]; then
            swaymsg "output ${DISPLAY_PRIMARY} transform ${_saved_tx}" 2>/dev/null
            DISPLAY_PRIMARY_TRANSFORM="$_saved_tx"
        fi
    fi
    if [ -n "$DISPLAY_SECONDARY" ] && [ -f "${DISPLAY_STATE_DIR}/transform_bottom" ]; then
        read -r _saved_tx < "${DISPLAY_STATE_DIR}/transform_bottom"
        if [ -n "$_saved_tx" ] && [ "$_saved_tx" != "$DISPLAY_SECONDARY_TRANSFORM" ]; then
            swaymsg "output ${DISPLAY_SECONDARY} transform ${_saved_tx}" 2>/dev/null
            DISPLAY_SECONDARY_TRANSFORM="$_saved_tx"
        fi
    fi

    # Apply device-mandated secondary transform (set by 111-sway-init quirks).
    # E.g., AYANEO Pocket DS needs DSI-2 at 270 whenever it's active.
    if [ -n "${ROCKNIX_SECONDARY_TRANSFORM:-}" ] && [ -n "$DISPLAY_SECONDARY" ]; then
        if [ "$DISPLAY_SECONDARY_TRANSFORM" != "$ROCKNIX_SECONDARY_TRANSFORM" ]; then
            swaymsg "output ${DISPLAY_SECONDARY} transform ${ROCKNIX_SECONDARY_TRANSFORM}" 2>/dev/null
            DISPLAY_SECONDARY_TRANSFORM="$ROCKNIX_SECONDARY_TRANSFORM"
        fi
    fi

    # Logical aliases (default: vertical stacking, primary on top)
    DISPLAY_TOP="$DISPLAY_PRIMARY"
    DISPLAY_BOTTOM="$DISPLAY_SECONDARY"

    # --- Asymmetric panel geometry ---
    # Vertical stack: wider panel determines canvas width.
    # Narrower panel is centered (offset computed).
    if [ "$PANEL_W" -ge "$PANEL2_W" ]; then
        CANVAS_W="$PANEL_W"
        VSTACK_PRI_X=0
        VSTACK_SEC_X=$(( (PANEL_W - PANEL2_W) / 2 ))
    else
        CANVAS_W="$PANEL2_W"
        VSTACK_PRI_X=$(( (PANEL2_W - PANEL_W) / 2 ))
        VSTACK_SEC_X=0
    fi
    CANVAS_H=$((PANEL_H + PANEL2_H))

    # Horizontal stack: taller panel determines canvas height.
    if [ "$PANEL_H" -ge "$PANEL2_H" ]; then
        CANVAS_H_HORIZ="$PANEL_H"
    else
        CANVAS_H_HORIZ="$PANEL2_H"
    fi
    CANVAS_W_HORIZ=$((PANEL_W + PANEL2_W))

    # --- Auto-detect touch device ---
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
    # Allow device-specific override via env
    TOUCH_DEVICE="${ROCKNIX_TOUCH_DEVICE:-$TOUCH_DEVICE}"

    return 0
}

# --- Predicates ---

display_is_dual() {
    _display_init
    [ -n "$DISPLAY_SECONDARY" ]
}

display_get_primary() {
    _display_init
    printf '%s' "$DISPLAY_PRIMARY"
}

display_get_secondary() {
    _display_init
    printf '%s' "$DISPLAY_SECONDARY"
}

# --- Layout Actions ---

# Stack outputs vertically: primary on top, secondary below.
# Handles asymmetric panels by centering the narrower output.
# E.g., 640x480 + 640x480:  DSI-1 at (0,0), DSI-2 at (0,480), canvas 640x960
# E.g., 640x480 + 1920x1080: DSI at (640,0), HDMI at (0,480), canvas 1920x1560
display_stack_vertical() {
    _display_init
    swaymsg "output ${DISPLAY_PRIMARY} power on" 2>/dev/null
    swaymsg "output ${DISPLAY_SECONDARY} power on" 2>/dev/null
    swaymsg "output ${DISPLAY_PRIMARY} pos ${VSTACK_PRI_X} 0" 2>/dev/null
    swaymsg "output ${DISPLAY_SECONDARY} pos ${VSTACK_SEC_X} ${PANEL_H}" 2>/dev/null
    # NOTE: no floating_maximum_size — it's global and breaks per-window sizing.
}

# Stack outputs horizontally: primary on left, secondary on right.
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
        # swaymsg returns 0 when the criteria matches an existing window
        swaymsg "[$criteria]" nop 2>/dev/null && return 0
    done
    return 1
}

# Float window and resize to span both outputs (vertical stack).
# Uses the computed canvas geometry — no hardcoded dimensions.
# Usage: display_span_window 'app_id="org.azahar_emu.Azahar"'
display_span_window() {
    local criteria="$1"
    _display_init
    local win_x=0
    # Window origin should be at the leftmost output x coordinate
    [ "$VSTACK_PRI_X" -lt "$VSTACK_SEC_X" ] && win_x="$VSTACK_PRI_X" || win_x="$VSTACK_SEC_X"
    swaymsg "[$criteria]" floating enable, fullscreen disable, border none, \
        resize set "$CANVAS_W" "$CANVAS_H", \
        move to output "$DISPLAY_PRIMARY", \
        move absolute position "$win_x" 0 2>/dev/null
}

# melonDS-style: fullscreen each window on its own output.
# Usage: display_fullscreen_split 'title="\[w1\].*melonDS"' 'title="\[w2\].*melonDS"'
display_fullscreen_split() {
    local criteria_top="$1" criteria_bottom="$2"
    _display_init
    swaymsg "[$criteria_top]" move to output "$DISPLAY_TOP", fullscreen enable 2>/dev/null
    swaymsg "[$criteria_bottom]" move to output "$DISPLAY_BOTTOM", fullscreen enable 2>/dev/null
}

# --- Per-Output Transform (Rotation) ---
#
# Transforms are managed per-output and persisted within a session via
# /run/rocknix/transform_{top,bottom} state files (tmpfs, cleared on reboot).
# This allows rotation set in ES to survive through runemu → emulator → back.
#
# Sway transform values: normal, 90, 180, 270,
#   flipped, flipped-90, flipped-180, flipped-270

# Set transform on a specific output.
# Persists to session state file. Forces re-init to pick up new rect geometry.
# Usage: display_set_transform top|bottom normal|90|180|270|flipped|flipped-*
display_set_transform() {
    local position="$1" transform="$2"
    _display_init
    local output
    [ "$position" = "top" ] && output="$DISPLAY_TOP" || output="$DISPLAY_BOTTOM"
    swaymsg "output ${output} transform ${transform}" 2>/dev/null
    # Small delay for sway to process the transform before re-querying
    sleep 0.1
    # Persist for session
    printf '%s' "$transform" > "${DISPLAY_STATE_DIR}/transform_${position}"
    # Force re-init — rect dimensions change after transform (90/270 swap W/H)
    _DISPLAY_INITED=""
    _display_init
}

# Cycle transform for an output through all 8 sway transforms.
# Cycle: normal → 90 → 180 → 270 → flipped → flipped-90 → flipped-180 → flipped-270 → normal
# Usage: display_cycle_transform top|bottom
display_cycle_transform() {
    local position="$1"
    _display_init
    local current
    if [ "$position" = "top" ]; then
        current="$DISPLAY_PRIMARY_TRANSFORM"
    else
        current="$DISPLAY_SECONDARY_TRANSFORM"
    fi

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

    display_set_transform "$position" "$next"
}

# Get the current transform for a position.
# Usage: display_get_transform top|bottom
display_get_transform() {
    local position="$1"
    _display_init
    if [ "$position" = "top" ]; then
        printf '%s' "$DISPLAY_PRIMARY_TRANSFORM"
    else
        printf '%s' "$DISPLAY_SECONDARY_TRANSFORM"
    fi
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
#
# When vertically stacked, the d/e/f row is scaled by sy = PANEL_H / CANVAS_H
# to constrain touch to the primary panel's portion of the virtual canvas.
#
# NOTE: Touch coordinate assumption is that the controller reports in the
# physical panel orientation. This is the standard for most capacitive
# touchscreens. If a specific device's controller reports pre-rotated
# coordinates, override via ROCKNIX_TOUCH_DEVICE or device-specific calibration
# in 111-sway-init.

# Internal: get the base rotation matrix (6 values) for a transform string.
# Returns space-separated "a b c d e f"
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
# Composes the primary output's rotation matrix with the Y-axis scaling
# needed to map touch to only the primary panel's portion of the canvas.
display_calibrate_touch_stacked() {
    _display_init
    [ -z "$TOUCH_DEVICE" ] && return 0

    local sy
    sy=$(awk "BEGIN { printf \"%.4f\", ${PANEL_H} / ${CANVAS_H} }")

    # Get base rotation matrix for primary output
    local matrix
    matrix=$(_display_touch_rotation_matrix "$DISPLAY_PRIMARY_TRANSFORM")

    # Parse the 6 matrix values
    local a b c d e f
    read -r a b c d e f <<< "$matrix"

    # Compose with vertical stacking: scale the bottom row (d, e, f) by sy
    # This constrains touch Y to the primary panel's fraction of the canvas
    local ds es fs
    ds=$(awk "BEGIN { printf \"%.4f\", ${d} * ${sy} }")
    es=$(awk "BEGIN { printf \"%.4f\", ${e} * ${sy} }")
    fs=$(awk "BEGIN { printf \"%.4f\", ${f} * ${sy} }")

    swaymsg "input \"$TOUCH_DEVICE\" calibration_matrix ${a} ${b} ${c} ${ds} ${es} ${fs}" 2>/dev/null
}

# Calibrate touch for a single output (no stacking) with rotation.
# Applies only the rotation matrix without Y-axis scaling.
# Usage: display_calibrate_touch_rotated [transform_override]
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
# Used by melonDS where touch goes to the bottom panel only.
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
    state=$(cat "$DISPLAY_STATE_FILE" 2>/dev/null || echo "normal_top")
    printf '%s' "$state" > "$DISPLAY_PRE_GAME_FILE"
}

# Restore display state after game exit.
# Powers off secondary, resets primary position, resets touch.
display_restore() {
    _display_init
    swaymsg "output ${DISPLAY_SECONDARY} power off" 2>/dev/null
    swaymsg "output ${DISPLAY_PRIMARY} pos 0 0" 2>/dev/null
    display_calibrate_touch_reset

    # Restore pre-game display-cycle state if saved
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

# --- Per-Panel Scaling (for separate-window emulators) ---

# Compute window geometry for a given scaling mode on a panel.
# Sets SCALE_W, SCALE_H, SCALE_X, SCALE_Y.
# Usage: display_set_scale_mode top|bottom stretch|fit|integer [content_w content_h]
display_set_scale_mode() {
    local position="$1" mode="$2"
    local content_w="${3:-0}" content_h="${4:-0}"
    _display_init

    local panel_w panel_h panel_x panel_y
    if [ "$position" = "top" ]; then
        panel_w="$PANEL_W"; panel_h="$PANEL_H"
        panel_x="$VSTACK_PRI_X"; panel_y=0
    else
        panel_w="$PANEL2_W"; panel_h="$PANEL2_H"
        panel_x="$VSTACK_SEC_X"; panel_y="$PANEL_H"
    fi

    printf '%s' "$mode" > "${DISPLAY_STATE_DIR}/scale_mode_${position}"

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

# Cycle scaling mode for a panel: stretch → fit → integer → stretch
# Usage: display_cycle_scale top|bottom [content_w content_h]
display_cycle_scale() {
    local position="$1"
    local content_w="${2:-0}" content_h="${3:-0}"
    local current
    current=$(cat "${DISPLAY_STATE_DIR}/scale_mode_${position}" 2>/dev/null || echo "stretch")

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
# Usage: display_apply_scale 'title="\[w1\]"'
display_apply_scale() {
    local criteria="$1"
    swaymsg "[$criteria]" floating enable, border none, \
        resize set "$SCALE_W" "$SCALE_H", \
        move absolute position "$SCALE_X" "$SCALE_Y" 2>/dev/null
}
