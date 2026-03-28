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

    # Parse output names and dimensions via python3 (precedent: display-cycle)
    # CRITICAL: use rect (post-transform, post-scale) not current_mode (hardware pixels).
    # rect gives the logical size in sway's virtual coordinate space:
    #   - A 1024x600 panel with transform=270 has rect 600x1024 (swapped)
    #   - A panel with scale=1.4 has rect dimensions scaled down accordingly
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
if len(outs) > 1:
    sec = outs[1]
    r2 = sec.get('rect', {})
    w2 = r2.get('width', sec['current_mode']['width'])
    h2 = r2.get('height', sec['current_mode']['height'])
    print(f'DISPLAY_SECONDARY=\"{sec[\"name\"]}\"')
    print(f'PANEL2_W={w2}')
    print(f'PANEL2_H={h2}')
" 2>/dev/null)"

    # Defaults if sway query failed or returned nothing
    DISPLAY_PRIMARY="${DISPLAY_PRIMARY:-${WLR_CON:-DSI-1}}"
    DISPLAY_SECONDARY="${DISPLAY_SECONDARY:-}"
    PANEL_W="${PANEL_W:-640}"
    PANEL_H="${PANEL_H:-480}"
    PANEL2_W="${PANEL2_W:-$PANEL_W}"
    PANEL2_H="${PANEL2_H:-$PANEL_H}"

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

# --- Touch Calibration ---

# Calibrate touch for vertical stacking.
# The calibration matrix maps physical touch coordinates to the virtual canvas.
# Touch covers the PRIMARY panel, so:
#   scale_y = PANEL_H / CANVAS_H
#   offset_y = scale_y (touch coordinate origin maps to top of primary)
display_calibrate_touch_stacked() {
    _display_init
    [ -z "$TOUCH_DEVICE" ] && return 0
    local scale_y
    scale_y=$(awk "BEGIN { printf \"%.4f\", ${PANEL_H} / ${CANVAS_H} }")
    swaymsg "input \"$TOUCH_DEVICE\" calibration_matrix 1 0 0 0 ${scale_y} ${scale_y}" 2>/dev/null
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
