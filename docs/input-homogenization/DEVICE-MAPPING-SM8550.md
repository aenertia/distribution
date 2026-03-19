# SM8550 Input Mapping: Current State → Target State

## Platform Summary

| Property | Value |
|----------|-------|
| SoC | Qualcomm Snapdragon 8 Gen2 (SM8550) |
| Input sources | HID MCU gamepads (AYANEO serial, AYN rsinput) |
| Kernel driver | CONFIG_JOYSTICK_RSINPUT=y (AYN), serial MCU (AYANEO) |
| ROCKNIX_JOYPAD | **No** — uses vendor HID, not rocknix-joypad |
| InputPlumber | **Already deployed** — device configs in filesystem overlay |

## Devices (11 total)

### AYANEO Devices (Japanese Layout)
| Device | Model String | MCU Vendor:Product | Layout |
|--------|-------------|-------------------|--------|
| AYANEO Pocket ACE | AYANEO Pocket ACE | 1c4f:0002 or 045e:028e | Japanese (ABXY swap) |
| AYANEO Pocket S 2K | AYANEO Pocket S 2K | 1c4f:0002 or 045e:028e | Japanese |
| AYANEO Pocket EVO | AYANEO Pocket EVO | 1c4f:0002 or 045e:028e | Japanese |
| AYANEO Pocket DS | AYANEO Pocket DS | 1c4f:0002 or 045e:028e | Japanese |
| AYANEO Pocket DMG | AYANEO Pocket DMG | 045e:028e only | Japanese |

### AYN Devices (Standard Layout)
| Device | Model String | MCU Path | Layout |
|--------|-------------|----------|--------|
| AYN Odin 2 | AYN Odin 2 | rsinput-gamepad/input0 | AYN MCU |
| AYN Odin 2 Mini | AYN Odin 2 Mini | rsinput-gamepad/input0 | AYN MCU |
| AYN Odin 2 Portal | AYN Odin 2 Portal | rsinput-gamepad/input0 | AYN MCU |
| AYN Thor | AYN Thor | rsinput-gamepad/input0 | AYN MCU |
| Retroid Pocket 6 | Retroid Pocket 6 | rsinput-gamepad/input0 | AYN MCU |
| Retroid Pocket 6 TOP-DPAD | Retroid Pocket 6 TOP-DPAD | rsinput-gamepad/input0 | AYN MCU |

## AYANEO Serial MCU Protocol

Before InputPlumber manages input, the MCU must be switched to Xbox 360 emulation mode:

**Quirk script:** `020-set-xbox-gamepad` (identical across all AYANEO devices)
```bash
SERIAL_DEVICE="/dev/ttyHS0"
stty -F $SERIAL_DEVICE 115200 -clocal -opost -isig -icanon -echo
printf '\xe7\x55\x05\x01\x00\x00\x00\x00\x00\x5b\xed' > $SERIAL_DEVICE
sleep 0.1
printf '55050100000000000000000000000000' > $SERIAL_DEVICE
```

This runs at boot before InputPlumber starts. After this, the MCU presents as either
vendor 1c4f:0002 (native AYANEO) or 045e:028e (Xbox 360 compatible).

## InputPlumber Configuration (ALREADY DEPLOYED)

### Device Configs (in `devices/SM8550/filesystem/usr/share/inputplumber/`)

**01-ayaneo-controller.yaml** (AYANEO Japanese Layout):
- Matches: AYANEO Pocket S 2K, ACE, EVO, DS
- Source: evdev vendor 1c4f:0002 AND 045e:028e
- Cap map: `ayaneo_mcu_xbox_japanese`
- Target: xbox-series, mouse, keyboard

**01-pocket-dmg-controller.yaml** (AYANEO DMG):
- Matches: AYANEO Pocket DMG
- Source: evdev vendor 045e:028e only
- Cap map: `ayaneo_mcu_xbox_japanese`
- Target: xbox-series, mouse, keyboard

**02-ayn-controller.yaml** (AYN/Retroid):
- Matches: AYN Odin 2/Mini/Portal, AYN Thor, Retroid Pocket 6/TOP-DPAD
- Source: evdev phys_path `rsinput-gamepad/input0`
- Cap map: `ayn_mcu`
- Target: xbox-series, mouse, keyboard

### Capability Maps

**ayaneo_mcu_xbox_japanese** (Japanese button swap):
| Source evdev | Target | Notes |
|-------------|--------|-------|
| BTN_EAST | South | Physical A → Xbox A (Japanese ABXY swap) |
| BTN_SOUTH | East | Physical B → Xbox B |
| BTN_NORTH | West | Physical X → Xbox X (Japanese swap) |
| BTN_WEST | North | Physical Y → Xbox Y |
| ABS_BRAKE | LeftTrigger | AYANEO analog trigger |
| ABS_GAS | RightTrigger | AYANEO analog trigger |
| ABS_HAT0X/Y | D-pad | Axis-based d-pad |
| BTN5 | QuickAccess2 | AYANEO special button |
| BTN_Z/BTN_C | Paddles | Left/Right paddle buttons |

**ayn_mcu** (AYN standard with X/Y swap):
| Source evdev | Target | Notes |
|-------------|--------|-------|
| BTN_SOUTH | South | Standard (no A/B swap) |
| BTN_EAST | East | Standard |
| BTN_NORTH | **West** | X/Y swap (MCU reports NORTH for X position) |
| BTN_WEST | **North** | X/Y swap (MCU reports WEST for Y position) |
| ABS_Z | LeftTrigger | AYN analog trigger |
| ABS_RZ | RightTrigger | AYN analog trigger |
| BTN_DPAD_* | D-pad | Discrete button d-pad |
| BTN_BACK | QuickAccess2 | AYN special button |
| BTN_Z/BTN_C | Paddles | Left/Right paddle buttons |

## Supporting Files

| File | Purpose |
|------|---------|
| `quirks/devices/AYANEO Pocket */020-set-xbox-gamepad` | Serial MCU initialization |
| `quirks/devices/AYN Odin 2/010-analog_sticks_led_control` | LED control |
| `quirks/devices/AYN Thor/touchcontrol` | Dual touchscreen calibration |
| `gamecontrollerdb/config/gamecontrollerdb.txt` line 21 | AYN Odin2 SDL mapping |
| `gamecontrollerdb/config/gamecontrollerdb.txt` line 26 | InputPlumber virtual pad |
| `dolphin-sa/config/SM8550/...GCPadNew.ini.south` | Dolphin GC pad config |
| `cemu-sa/config/SM8550/.../wii_u_gamepad.xml` | Cemu WiiU pad config |

## Emulator Input Notes

Emulators on SM8550 see the **InputPlumber GameController** virtual device, not the
raw MCU device. Example from Cemu config:
```xml
<controller>
  <api>SDLController</api>
  <uuid>0_0300f5a35e040000120b000001000000</uuid>
  <!-- InputPlumber virtual gamepad UUID -->
</controller>
```

Dolphin references "Microsoft X-Box 360 pad" for button mapping but uses the
actual AYN Odin2 device for rumble feedback.

## Rumble / Haptics

| Feature | Details |
|---------|---------|
| Type | QCOM SPMI Haptics (inherited from SM8250 haptics stack) |
| Interface | Linux FF_MEMLESS force-feedback (evdev) |
| AYN Odin 2 rumble | evdev FF via `AYN Odin2 Gamepad:Strong` (Dolphin reference) |

Rumble is automatically passed through by InputPlumber's xbox-series target.

## Touchscreen Inventory

| Device | IC | I2C Bus | Resolution | Inversion | Dual? |
|--------|-----|---------|------------|-----------|-------|
| AYN Thor (primary) | FT5426 | i2c4 @ 0x38 | 1080x1920 | X-inv, XY-swap | Yes |
| AYN Thor (secondary) | FT5452 | i2c_hub_3 @ 0x38 | 1080x1240 | X-inv, XY-swap | Yes |
| AYN Odin 2 | Synaptics RMI4 | I2C | Varies | — | No |
| AYN Odin 2 Mini | Hynitron CST340 | i2c4 @ 0x1a | 1920x1080 | XY-swap, Y-inv | No |
| AYN Odin 2 Portal | FT5426 | i2c4 @ 0x38 | 1080x1920 | X-inv, XY-swap | No |
| Retroid Pocket 6 | FT5426 | i2c4 @ 0x38 | 1080x1920 | X-inv, XY-swap | No |
| AYANEO Pocket ACE | Synaptics RMI4 | I2C | Varies | — | No |
| AYANEO Pocket DS (primary) | GT911 | i2c2 @ 0x5d | 768x1024 | — | Yes |
| AYANEO Pocket DS (secondary) | FT5426 | i2c4 @ 0x38 | Varies | — | Yes |
| AYANEO Pocket DMG | None | — | — | — | No |
| AYANEO Pocket EVO | FT5426 | i2c4 @ 0x38 | Varies | — | No |
| AYANEO Pocket S2K | GT911 | i2c2 @ 0x5d | Varies | — | No |

### Dual-Screen Touch Calibration

**AYN Thor** (`touchcontrol` quirk):
- Left panel (platform-a90000.i2c): `LIBINPUT_CALIBRATION_MATRIX="0.607595 0 0 0 1 0"`
- Right panel (platform-98c000.i2c): `LIBINPUT_CALIBRATION_MATRIX="0.392405 0 0.607595 0 1 0"`

**AYANEO Pocket DS**: Dual GT911 + FT5426 — calibration TBD.

Touch managed by libinput/sway, not InputPlumber.

## LED Inventory

### AYN Devices (PWM multi-color RGB)
| LED Group | Location | Type | DTS Node |
|-----------|----------|------|----------|
| Left Side | Device left edge | RGB (3-channel PWM) | pwm-leds-multicolor |
| Left Joystick | Left analog ring | RGB (3-channel PWM) | pwm-leds-multicolor |
| Right Side | Device right edge | RGB (3-channel PWM) | pwm-leds-multicolor |
| Right Joystick | Right analog ring | RGB (3-channel PWM) | pwm-leds-multicolor |

Control: `/sys/class/leds/*/multi_intensity` (RGB) + `brightness` (0-255)
Script: `bin/analog_sticks_ledcontrol` — 7 preset colors, per-side control
Devices: AYN Odin 2, Odin 2 Mini, Odin 2 Portal, AYN Thor, Retroid Pocket 6

### AYANEO Devices (HTR3212 I2C LED)
| Feature | Details |
|---------|---------|
| Controller | HTR3212 I2C 12-channel 8-bit PWM |
| Driver | `leds-htr3212` |
| Interface | `/sys/class/leds/` brightness |
| Devices | AYANEO Pocket ACE, DMG, DS, EVO, S2K |

### Battery LED Status
AYANEO devices have `bin/battery_led_status` scripts:
- Orange at 30% battery
- Red at 20% battery
- Blinking red at 10% battery

All LED control is sysfs-based — not managed by InputPlumber currently.
InputPlumber's `led` source group could unify this in a future phase.

## Status

**COMPLETE — no changes needed.**

SM8550 was the first platform with InputPlumber. Device configs and capability maps
are correct and tested. The AYANEO Japanese layout swap and AYN X/Y swap are properly
handled by their respective capability maps.
