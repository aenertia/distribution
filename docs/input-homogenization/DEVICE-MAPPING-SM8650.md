# SM8650 Input Mapping: Current State → Target State

## Platform Summary

| Property | Value |
|----------|-------|
| SoC | Qualcomm Snapdragon 8 Gen3 (SM8650) |
| Input source | AYANEO serial MCU (HID gamepad) |
| Kernel driver | Serial MCU via /dev/ttyHS0 |
| ROCKNIX_JOYPAD | **No** — uses vendor HID |
| InputPlumber | **Already deployed** — device config in filesystem overlay |
| 32-bit support | Disabled (ENABLE_32BIT="no") |

## Devices (2 total)

| Device | Model String | MCU Vendor:Product | Layout |
|--------|-------------|-------------------|--------|
| AYANEO Pocket S2 | AYANEO Pocket S2 | 1c4f:0002 or 045e:028e | Standard (NO swap) |
| KONKR Pocket FIT | KONKR Pocket FIT | 1c4f:0002 or 045e:028e | Standard (NO swap) |

## Key Difference from SM8550

SM8650 devices use the **AYANEO Standard** layout, NOT the Japanese layout:
- **SM8550 AYANEO:** Full ABXY swap (Japanese controller convention)
- **SM8650 AYANEO:** No swap — 1:1 mapping (Standard/Western convention)

Both platforms use the same serial MCU protocol to switch to Xbox mode.

## Serial MCU Protocol

**Identical to SM8550 AYANEO devices:**
```bash
SERIAL_DEVICE="/dev/ttyHS0"
stty -F $SERIAL_DEVICE 115200 -clocal -opost -isig -icanon -echo
printf '\xe7\x55\x05\x01\x00\x00\x00\x00\x00\x5b\xed' > $SERIAL_DEVICE
sleep 0.1
printf '55050100000000000000000000000000' > $SERIAL_DEVICE
```

## InputPlumber Configuration (ALREADY DEPLOYED)

### Device Config

**`devices/SM8650/filesystem/usr/share/inputplumber/devices/01-ayaneo-controller.yaml`:**
- Matches: KONKR Pocket FIT, AYANEO Pocket S2
- Source: evdev vendor 1c4f:0002 AND 045e:028e
- Cap map: `ayaneo_mcu_xbox_standard`
- Target: xbox-series, mouse, keyboard

### Capability Map

**`devices/SM8650/filesystem/usr/share/inputplumber/capability_maps/ayaneo_mcu_xbox_standard.yaml`:**

| Source evdev | Target | Notes |
|-------------|--------|-------|
| BTN_SOUTH | South | 1:1 — no swap |
| BTN_EAST | East | 1:1 — no swap |
| BTN_NORTH | North | 1:1 — no swap |
| BTN_WEST | West | 1:1 — no swap |
| ABS_BRAKE | LeftTrigger | AYANEO analog trigger |
| ABS_GAS | RightTrigger | AYANEO analog trigger |
| ABS_HAT0X/Y | D-pad | Axis-based d-pad |
| BTN5 | QuickAccess2 | AYANEO special button |
| BTN_Z/BTN_C | Paddles | Left/Right paddle buttons |

This is structurally identical to the Japanese map except face buttons are NOT swapped.

## Supporting Files

| File | Purpose |
|------|---------|
| `quirks/devices/AYANEO Pocket S2/020-set-xbox-gamepad` | Serial MCU init |
| `quirks/devices/AYANEO Pocket S2/001-device_config` | GPU overclock flag |
| `quirks/devices/KONKR Pocket FIT/020-set-xbox-gamepad` | Serial MCU init |
| `quirks/devices/KONKR Pocket FIT/001-device_config` | GPU overclock flag |

## Comparison: SM8550 vs SM8650 InputPlumber Stack

| Aspect | SM8550 | SM8650 |
|--------|--------|--------|
| AYANEO layout | Japanese (full ABXY swap) | Standard (no swap) |
| AYN devices | Yes (Odin 2, Thor, RP6) | No |
| Capability maps | 2 (ayaneo_japanese + ayn_mcu) | 1 (ayaneo_standard) |
| Device configs | 3 (ayaneo + dmg + ayn) | 1 (ayaneo) |
| Trigger axes | ABS_BRAKE/GAS (AYANEO), ABS_Z/RZ (AYN) | ABS_BRAKE/GAS only |
| D-pad type | ABS_HAT0 (AYANEO), BTN_DPAD (AYN) | ABS_HAT0 only |
| Paddle buttons | BTN_Z/BTN_C | BTN_Z/BTN_C |
| Quick access | BTN5 (AYANEO), BTN_BACK (AYN) | BTN5 |
| gamepadcalibration | Included | Not included |
| screen-switch | Included | Not included |

## Status

**COMPLETE — no changes needed.**

SM8650 InputPlumber configuration is correct and functional. The AYANEO Standard
capability map provides 1:1 face button mapping with proper analog trigger handling
via ABS_BRAKE/ABS_GAS.
