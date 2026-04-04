#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Toggle stretched/dual-screen mode for devices with two panels (e.g. RGDS)
# When enabled: creates HEADLESS output at combined resolution, moves ES to it
# When disabled: destroys HEADLESS, returns ES to primary physical panel

. /etc/profile

if [ "${DEVICE_HAS_DUAL_SCREEN}" != "true" ]; then
    echo "This device does not have dual screens."
    sleep 3
    exit 0
fi

CURRENT=$(get_setting "system.stretched_mode")

if [ "${CURRENT}" = "1" ]; then
    # --- DISABLE stretched mode ---
    set_setting "system.stretched_mode" "0"

    CON="${WLR_CON:-DSI-1}"
    SECOND_CON=$([[ "$CON" = "DSI-1" ]] && echo "DSI-2" || echo "DSI-1")

    # Move ES workspace back to primary physical output
    swaymsg workspace 1 output "${CON}"
    swaymsg focus output "${CON}"
    swaymsg '[app_id="emulationstation"]' fullscreen enable

    # Destroy any HEADLESS outputs
    for h in $(swaymsg -t get_outputs -r 2>/dev/null | \
        python3 -c "import sys,json; [print(o['name']) for o in json.load(sys.stdin) if 'HEADLESS' in o['name']]" 2>/dev/null); do
        swaymsg output "${h}" unplug
    done

    # Power off secondary, reset positions
    swaymsg output "${SECOND_CON}" power off
    swaymsg output "${CON}" pos 0 0

    # Reset touch calibration
    if [ "${QUIRK_DEVICE}" = "Anbernic RG DS" ]; then
        swaymsg 'input "1046:911:Goodix_Capacitive_TouchScreen" calibration_matrix 1 0 0 0 1 0'
    fi

    echo "Stretched mode DISABLED — single screen (640x480)"

else
    # --- ENABLE stretched mode ---
    set_setting "system.stretched_mode" "1"

    CON="${WLR_CON:-DSI-1}"
    SECOND_CON=$([[ "$CON" = "DSI-1" ]] && echo "DSI-2" || echo "DSI-1")
    PANEL_W=640
    PANEL_H=480
    COMBINED_H=$((PANEL_H * 2))

    # Stack physical outputs vertically
    swaymsg output "${SECOND_CON}" pos 0 0, power on
    swaymsg output "${CON}" pos 0 "${PANEL_H}", power on

    # Create headless output at combined resolution
    swaymsg create_output
    sleep 0.5

    # Find the HEADLESS output
    HEADLESS=$(swaymsg -t get_outputs -r 2>/dev/null | \
        python3 -c "import sys,json; outs=json.load(sys.stdin); print(next((o['name'] for o in outs if 'HEADLESS' in o['name']), ''))" 2>/dev/null)

    if [ -z "${HEADLESS}" ]; then
        echo "ERROR: Failed to create headless output"
        set_setting "system.stretched_mode" "0"
        swaymsg output "${SECOND_CON}" power off
        sleep 3
        exit 1
    fi

    # Configure headless at combined resolution
    swaymsg output "${HEADLESS}" mode --custom "${PANEL_W}x${COMBINED_H}"
    swaymsg output "${HEADLESS}" pos 0 0

    # Move ES workspace to headless output
    swaymsg workspace 1 output "${HEADLESS}"
    swaymsg focus output "${HEADLESS}"
    swaymsg '[app_id="emulationstation"]' move workspace to output "${HEADLESS}"
    swaymsg '[app_id="emulationstation"]' fullscreen enable

    # Touch calibration for stacked layout
    if [ "${QUIRK_DEVICE}" = "Anbernic RG DS" ]; then
        swaymsg 'input "1046:911:Goodix_Capacitive_TouchScreen" calibration_matrix 1 0 0 0 0.5 0.5'
    fi

    echo "Stretched mode ENABLED — both screens (${PANEL_W}x${COMBINED_H})"
fi

sleep 2
