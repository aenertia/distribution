#!/bin/bash
# Will be called by PortMaster mod_ROCKNIX.txt

. /etc/profile
. /usr/lib/rocknix-display/display-core.sh

if echo "${UI_SERVICE}" | grep -q "sway"; then
    # Call the function to fullscreen the window for app_id asynchronously
    sway_fullscreen "${1}" &

    # Create a virtual touch keyboard device if there are two displays
    if display_is_dual; then
        TSKEY=$(get_setting "rocknix.touchscreen-keyboard.enabled")
        if [[ "${TSKEY}" == "1" ]]; then
            swaymsg "output ${DISPLAY_SECONDARY} power on"
            (
              sleep 2
              swaymsg 'seat seat1 fallback yes'
            ) &
        fi
    fi
fi
