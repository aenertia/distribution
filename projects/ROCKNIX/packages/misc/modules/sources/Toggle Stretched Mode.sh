#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Toggle stretched/dual-screen mode for devices with two panels (e.g. RGDS)
# Self-contained: manages output stacking, ES restart, and watcher daemon.
# Does NOT modify sway config — works alongside existing sway rules.

. /etc/profile

if [ "${DEVICE_HAS_DUAL_SCREEN}" != "true" ]; then
    echo "This device does not have dual screens."
    sleep 3
    exit 0
fi

CURRENT=$(get_setting "system.stretched_mode")
CON="${WLR_CON:-DSI-1}"
SECOND_CON=$([[ "$CON" = "DSI-1" ]] && echo "DSI-2" || echo "DSI-1")
PANEL_W=$(fbwidth)
PANEL_H=$(fbheight)
COMBINED_H=$((PANEL_H * 2))

HELPER=/tmp/stretched_helper.sh

if [ "${CURRENT}" = "1" ]; then
    # --- DISABLE stretched mode ---
    set_setting "system.stretched_mode" "0"

    cat > "${HELPER}" <<HELPEREOF
#!/bin/bash
export SWAYSOCK=${SWAYSOCK}
# Stop watcher
systemctl stop stretched-watcher 2>/dev/null
rm -f /tmp/stretched_watcher.sh
# Destroy any stale HEADLESS outputs from older implementations
for h in \$(swaymsg -t get_outputs -r 2>/dev/null | jq -r '.[] | select(.name | contains("HEADLESS")) | .name' 2>/dev/null); do
    swaymsg output "\${h}" unplug
done
# Restart ES (will launch without --windowed since setting is now 0)
systemctl restart essway
sleep 3
# Reset touch calibration
swaymsg 'input "1046:911:Goodix_Capacitive_TouchScreen" calibration_matrix 1 0 0 0 1 0'
# Power off secondary, reset primary position
swaymsg output ${SECOND_CON} power off
swaymsg output ${CON} pos 0 0
swaymsg "floating_maximum_size 0 x 0"
rm -f /tmp/stretched_helper.sh
HELPEREOF
    chmod 755 "${HELPER}"
    systemd-run --no-block "${HELPER}"

else
    # --- ENABLE stretched mode ---
    set_setting "system.stretched_mode" "1"

    # Write the watcher daemon script (dimensions baked in)
    cat > /tmp/stretched_watcher.sh <<WATCHEREOF
#!/bin/bash
export SWAYSOCK=${SWAYSOCK}
swaymsg -t subscribe -m '["window"]' | while read -r event; do
    APP_ID=\$(echo "\$event" | jq -r '.container.app_id // empty' 2>/dev/null)
    NAME=\$(echo "\$event" | jq -r '.container.name // empty' 2>/dev/null)
    # Skip dual-screen emulator windows — existing sway rules handle them
    case "\$NAME" in *\[w1\]*|*\[w2\]*|*Secondary*|*Bottom*|*"Screen 2"*|*GamePad*) continue ;; esac
    # Re-stack outputs (exec_always power-off rule may have fired)
    swaymsg output ${CON} power on, output ${CON} pos 0 0
    swaymsg output ${SECOND_CON} power on, output ${SECOND_CON} pos 0 ${PANEL_H}
    # Float the triggering window to span both panels
    if [ -n "\$APP_ID" ]; then
        sleep 0.3
        swaymsg "floating_maximum_size ${PANEL_W} x ${COMBINED_H}"
        swaymsg "[app_id=\"\${APP_ID}\"]" floating enable, border none, resize set ${PANEL_W} ${COMBINED_H}, move absolute position 0 0
        swaymsg "[app_id=\"\${APP_ID}\"]" focus
        sleep 0.2
        swaymsg "floating_maximum_size 0 x 0"
    fi
done
WATCHEREOF
    chmod 755 /tmp/stretched_watcher.sh

    cat > "${HELPER}" <<HELPEREOF
#!/bin/bash
export SWAYSOCK=${SWAYSOCK}
# Stack outputs: primary at top, secondary below
swaymsg output ${CON} power on, output ${CON} pos 0 0
swaymsg output ${SECOND_CON} power on, output ${SECOND_CON} pos 0 ${PANEL_H}
# Touch calibration for stacked layout
swaymsg 'input "1046:911:Goodix_Capacitive_TouchScreen" calibration_matrix 1 0 0 0 0.5 0.5'
# Start watcher daemon
systemctl stop stretched-watcher 2>/dev/null
systemd-run --no-block --unit=stretched-watcher /tmp/stretched_watcher.sh
# Restart ES (will launch with --windowed --resolution)
systemctl restart essway
# Wait for ES window to appear
TRIES=0
while [ \$TRIES -lt 30 ]; do
    TRIES=\$((TRIES + 1))
    sleep 0.5
    swaymsg -t get_tree -r 2>/dev/null | jq -e '.. | select(.app_id? == "emulationstation")' >/dev/null 2>&1 && break
done
sleep 1
# Float ES to span both panels
swaymsg "floating_maximum_size ${PANEL_W} x ${COMBINED_H}"
swaymsg '[app_id="emulationstation"]' floating enable, border none, resize set ${PANEL_W} ${COMBINED_H}, move absolute position 0 0
swaymsg '[app_id="emulationstation"]' focus
sleep 0.2
swaymsg "floating_maximum_size 0 x 0"
rm -f /tmp/stretched_helper.sh
HELPEREOF
    chmod 755 "${HELPER}"
    systemd-run --no-block "${HELPER}"
fi
