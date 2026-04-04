#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Toggle stretched/dual-screen mode for devices with two panels.
# Uses display-core.sh for runtime output geometry — works on any
# dual-screen device (built-in DSI panels, HDMI, DP, USB-C).

. /etc/profile
. /usr/lib/rocknix-display/display-core.sh

if ! display_is_dual; then
    echo "This device does not have dual screens."
    sleep 3
    exit 0
fi

CURRENT=$(get_setting "system.stretched_mode")

HELPER=/tmp/stretched_helper.sh

if [ "${CURRENT}" = "1" ]; then
    # --- DISABLE stretched mode ---
    set_setting "system.stretched_mode" "0"

    cat > "${HELPER}" <<HELPEREOF
#!/bin/bash
. /usr/lib/rocknix-display/display-core.sh
export SWAYSOCK=${SWAYSOCK}
# Stop watcher
systemctl stop stretched-watcher 2>/dev/null
rm -f /tmp/stretched_watcher.sh
# Destroy any stale HEADLESS outputs from older implementations
for h in \$(swaymsg -t get_outputs -r 2>/dev/null | python3 -c "
import json,sys
for o in json.load(sys.stdin):
    if 'HEADLESS' in o['name']: print(o['name'])
" 2>/dev/null); do
    swaymsg output "\${h}" unplug
done
# Restart ES (will launch without --windowed since setting is now 0)
systemctl restart essway
sleep 3
# Reset touch and restore display
display_calibrate_touch_reset
display_restore
rm -f /tmp/stretched_helper.sh
HELPEREOF
    chmod 755 "${HELPER}"
    systemd-run --no-block "${HELPER}"

else
    # --- ENABLE stretched mode ---
    set_setting "system.stretched_mode" "1"

    # Write the watcher daemon script
    cat > /tmp/stretched_watcher.sh <<WATCHEREOF
#!/bin/bash
. /usr/lib/rocknix-display/display-core.sh
export SWAYSOCK=${SWAYSOCK}
swaymsg -t subscribe -m '["window"]' | while read -r event; do
    APP_ID=\$(printf '%s' "\$event" | python3 -c "import json,sys; print(json.load(sys.stdin).get('container',{}).get('app_id',''))" 2>/dev/null)
    NAME=\$(printf '%s' "\$event" | python3 -c "import json,sys; print(json.load(sys.stdin).get('container',{}).get('name',''))" 2>/dev/null)
    # Skip dual-screen emulator windows — existing sway rules handle them
    case "\$NAME" in *\[w1\]*|*\[w2\]*|*Secondary*|*Bottom*|*"Screen 2"*|*GamePad*) continue ;; esac
    # Re-stack outputs
    display_stack_vertical
    # Float the triggering window to span both panels
    if [ -n "\$APP_ID" ]; then
        sleep 0.3
        display_span_window "app_id=\"\${APP_ID}\""
        swaymsg "[app_id=\"\${APP_ID}\"]" focus
    fi
done
WATCHEREOF
    chmod 755 /tmp/stretched_watcher.sh

    cat > "${HELPER}" <<HELPEREOF
#!/bin/bash
. /usr/lib/rocknix-display/display-core.sh
export SWAYSOCK=${SWAYSOCK}
# Stack outputs
display_stack_vertical
# Touch calibration for stacked layout
display_calibrate_touch_stacked
# Start watcher daemon
systemctl stop stretched-watcher 2>/dev/null
systemd-run --no-block --unit=stretched-watcher /tmp/stretched_watcher.sh
# Restart ES (will launch with --windowed --resolution)
systemctl restart essway
# Wait for ES window to appear
display_wait_window 'app_id="emulationstation"' 15
sleep 1
# Float ES to span both panels
display_span_window 'app_id="emulationstation"'
swaymsg '[app_id="emulationstation"]' focus
rm -f /tmp/stretched_helper.sh
HELPEREOF
    chmod 755 "${HELPER}"
    systemd-run --no-block "${HELPER}"
fi
