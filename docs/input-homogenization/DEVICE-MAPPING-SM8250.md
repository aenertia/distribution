# SM8250 Input Mapping: Current State → Target State

## Platform Summary

| Property | Value |
|----------|-------|
| SoC | Qualcomm Snapdragon 865 (SM8250) |
| Kernel driver | `retroid-pocket-gamepad` (serial/UART) |
| Interface | UART16 @ 115200 baud, custom binary protocol |
| Vendor ID | 0x2020 |
| Product ID | 0x3001 |
| Device name | `Retroid Pocket Gamepad` |
| Analog triggers | **Yes** — ABS_HAT2X (L2), ABS_HAT2Y (R2) |
| Stick Z-axes | **Yes** — ABS_Z (L stick Z), ABS_RZ (R stick Z) |
| A/B swap | **Yes** — BTN_EAST=Physical A, BTN_SOUTH=Physical B |
| Touchscreen | Focaltech FT5452 (I2C13), device-specific inversion |
| GPIO MCU control | boot=GPIO110, enable=GPIO111, reset=GPIO109 |

## Devices (4 total)

| Device | Display | Touch | Variant |
|--------|---------|-------|---------|
| Retroid Pocket 5 | 1080x1920 | inverted X/Y | Primary |
| Retroid Pocket Flip2 | 1080x1920 | inverted X/Y | Symlink → RP5 |
| Retroid Pocket Mini | 960x1280 | normal | Primary |
| Retroid Pocket Mini V2 | 960x1280 | normal | Symlink → RPMini |

## Current Input Flow (without InputPlumber)

```
MCU Gamepad (serial protocol over UART16)
    ↓
retroid-pocket-gamepad (kernel serdev driver)
    ├── Probe: GPIO sequence (boot→reset→enable)
    ├── Init: 6 command packets with 100ms delays
    └── Receive: 14-byte input data packets (buttons + axes)
    ↓
/dev/input/eventX (Retroid Pocket Gamepad, 2020:3001)
    ├── 16 buttons: BTN_DPAD_* (4), BTN_NORTH/WEST/EAST/SOUTH (4),
    │               BTN_TL/TR (2), BTN_SELECT/START (2),
    │               BTN_THUMBL/THUMBR (2), BTN_MODE (1), BTN_BACK (1)
    ├── 8 axes:    ABS_X/Y/Z (left stick XYZ)
    │               ABS_RX/RY/RZ (right stick XYZ)
    │               ABS_HAT2X (LEFT TRIGGER, 0–0x610)
    │               ABS_HAT2Y (RIGHT TRIGGER, 0–0x610)
    └── udev: 99-retroid-pocket.rules (MODE=0666, ID_INPUT_JOYSTICK=1)
    ↓
SDL2 (gamecontrollerdb.txt)
    Entry: 0300f353202000000130000001000000,Retroid Pocket Gamepad
    Mapping: a:b1,b:b0,x:b2,y:b3,lefttrigger:a6,righttrigger:a7
    ↓
EmulationStation / RetroArch / Standalones
    ├── RetroArch: Retroid Pocket Gamepad.cfg
    ├── Flycast: SDL_Retroid Pocket Gamepad.cfg
    ├── Mupen64Plus: mupen64plus.cfg [Retroid Pocket Gamepad]
    ├── RPCS3: Default.yml (SDL handler)
    └── gamepadcalibration (GPcal) for runtime calibration
```

### Kernel Driver Axis Layout

```
evdev code → SDL axis index → SDL gamecontrollerdb mapping
ABS_X      (0x00) → a0 → leftx
ABS_Y      (0x01) → a1 → lefty
ABS_Z      (0x02) → a2 → (LEFT STICK Z — NOT a trigger!)
ABS_RX     (0x03) → a3 → rightx
ABS_RY     (0x04) → a4 → righty
ABS_RZ     (0x05) → a5 → (RIGHT STICK Z — NOT a trigger!)
ABS_HAT2X  (0x14) → a6 → lefttrigger  ← ACTUAL LEFT TRIGGER
ABS_HAT2Y  (0x15) → a7 → righttrigger ← ACTUAL RIGHT TRIGGER
```

### Kernel Driver Button Layout (from keymap[] array)

```
Protocol   evdev code      evdev     SDL
byte bit   (keymap index)  value     index   Physical
────────── ─────────────── ──────── ────── ─────────
byte0 b0   BTN_DPAD_UP     0x220    b11    D-pad Up
byte0 b1   BTN_DPAD_DOWN   0x221    b12    D-pad Down
byte0 b2   BTN_DPAD_LEFT   0x222    b13    D-pad Left
byte0 b3   BTN_DPAD_RIGHT  0x223    b14    D-pad Right
byte0 b4   BTN_NORTH       0x133    b2     Face X
byte0 b5   BTN_WEST        0x134    b3     Face Y
byte0 b6   BTN_EAST        0x131    b1     Face A ← SWAPPED
byte0 b7   BTN_SOUTH       0x130    b0     Face B ← SWAPPED
byte1 b0   BTN_TL          0x136    b4     L1
byte1 b1   BTN_TR          0x137    b5     R1
byte1 b2   BTN_SELECT      0x13a    b6     Select
byte1 b3   BTN_START       0x13b    b7     Start
byte1 b4   BTN_THUMBL      0x13d    b9     L3
byte1 b5   BTN_THUMBR      0x13e    b10    R3
byte1 b6   BTN_MODE        0x13c    b8     Guide
byte1 b7   BTN_BACK        0x116    b15    Back/Misc
```

### Supporting Files (current)

| File | Purpose |
|------|---------|
| `gamecontrollerdb/config/gamecontrollerdb.txt` line 18 | SDL mapping (A/B swap + triggers a6/a7) |
| `retroarch-joypads/gamepads/Retroid Pocket Gamepad.cfg` | RetroArch autoconfig |
| `flycast-sa/config/SM8250/mappings/SDL_Retroid Pocket Gamepad.cfg` | Flycast bindings |
| `mupen64plus-sa/.../config/SM8250/mupen64plus.cfg` | N64 controller mapping |
| `rpcs3-sa/config/SM8250/.../Default.yml` | PS3 controller mapping |
| `SM8250/filesystem/.../99-retroid-pocket.rules` | udev joystick + haptics |
| `SM8250/packages/gamepadcalibration/` | GPcal runtime calibration |
| `quirks/devices/Retroid Pocket 5/001-device_config` | Touchscreen + GPU OC flags |

## BUGS IN CURRENT INPUTPLUMBER IMPLEMENTATION

### Bug 1: CRITICAL — Triggers Mapped to Wrong Axes

The `retroid_pocket_gamepad.yaml` currently maps:
```yaml
# WRONG — ABS_Z is left stick Z-axis, not left trigger
- name: Left Trigger
  source_events:
    - evdev:
        event_code: ABS_Z      ← WRONG! Should be ABS_HAT2X
        value_type: trigger

# WRONG — ABS_RZ is right stick Z-axis, not right trigger
- name: Right Trigger
  source_events:
    - evdev:
        event_code: ABS_RZ     ← WRONG! Should be ABS_HAT2Y
        value_type: trigger
```

**Impact:** L2/R2 triggers read data from the analog stick Z-axes instead of the
actual trigger hardware. Triggers are completely non-functional.

### Bug 2: A/B Face Buttons Swapped

Physical A button generates BTN_EAST (0x131). The 1:1 map sends this to `East`
on the virtual pad, which becomes SDL B. User presses A, gets B action.

## Target Input Flow (with InputPlumber, after fixes)

```
MCU Gamepad (serial protocol)
    ↓
retroid-pocket-gamepad (kernel serdev driver)
    ↓
/dev/input/eventX (GRABBED — hidden from apps)
    ↓
InputPlumber daemon
    Config: 50-retroid-pocket-gamepad.yaml (match 2020:3001)
    Cap map: retroid_pocket_gamepad.yaml (FIXED: A/B swap + correct triggers)
    ↓
Virtual Xbox Series Gamepad (/dev/input/eventY)
    ├── BTN_SOUTH = Physical A (CORRECTED via swap)
    ├── BTN_EAST = Physical B (CORRECTED via swap)
    ├── ABS_Z = L2 trigger (from ABS_HAT2X source)
    ├── ABS_RZ = R2 trigger (from ABS_HAT2Y source)
    └── All other buttons/axes pass through
    ↓
SDL2: InputPlumber GameController (standard Xbox mapping)
    ↓
EmulationStation / RetroArch / Standalones
```

## Button-by-Button Verification (after fix)

| Physical | Source evdev | Cap map target | Virtual evdev | SDL result | Correct? |
|----------|-------------|----------------|---------------|------------|----------|
| A | **BTN_EAST** | **South** ← SWAP | BTN_SOUTH | SDL A | ✓ |
| B | **BTN_SOUTH** | **East** ← SWAP | BTN_EAST | SDL B | ✓ |
| X | BTN_NORTH | North | BTN_NORTH | SDL X | ✓ |
| Y | BTN_WEST | West | BTN_WEST | SDL Y | ✓ |
| L1 | BTN_TL | LeftBumper | BTN_TL | SDL LB | ✓ |
| R1 | BTN_TR | RightBumper | BTN_TR | SDL RB | ✓ |
| **L2** | **ABS_HAT2X** | LeftTrigger | ABS_Z (analog) | SDL LT | ✓ FIXED |
| **R2** | **ABS_HAT2Y** | RightTrigger | ABS_RZ (analog) | SDL RT | ✓ FIXED |
| Select | BTN_SELECT | Select | BTN_SELECT | SDL Back | ✓ |
| Start | BTN_START | Start | BTN_START | SDL Start | ✓ |
| Guide | BTN_MODE | Guide | BTN_MODE | SDL Guide | ✓ |
| Back | BTN_BACK | QuickAccess2 | (misc) | SDL Misc | ✓ |
| L3 | BTN_THUMBL | LeftStick | BTN_THUMBL | SDL LS | ✓ |
| R3 | BTN_THUMBR | RightStick | BTN_THUMBR | SDL RS | ✓ |
| D-pad | BTN_DPAD_* | DPad* | ABS_HAT0* | SDL D-pad | ✓ |
| L Stick | ABS_X/Y | LeftStick | ABS_X/Y | SDL axes | ✓ |
| R Stick | ABS_RX/RY | RightStick | ABS_RX/RY | SDL axes | ✓ |
| L Stick Z | ABS_Z | (unmapped) | — | — | N/A |
| R Stick Z | ABS_RZ | (unmapped) | — | — | N/A |

## Fix Required

Update `retroid_pocket_gamepad.yaml`:
1. LeftTrigger: `ABS_Z` → `ABS_HAT2X`
2. RightTrigger: `ABS_RZ` → `ABS_HAT2Y`
3. BTN_SOUTH target: `South` → `East` (A/B swap)
4. BTN_EAST target: `East` → `South` (A/B swap)

### Post-InputPlumber Considerations

- **gamepadcalibration (GPcal):** Calibrates the raw gamepad via sysfs module parameters.
  Should still work since it writes to the kernel driver, not the evdev device. The
  calibrated values flow through InputPlumber normally.
- **Touchscreen disabling:** runemu.sh disables touch via `swaymsg input ... events disabled`.
  This is compositor-level, unaffected by InputPlumber.
- **Emulator-specific configs:** Flycast, Mupen64Plus, RPCS3 configs reference
  "Retroid Pocket Gamepad" by name. Post-InputPlumber, they'll see "InputPlumber
  GameController". These configs may need updating to match the new device name,
  or the emulators can fall back to SDL gamecontrollerdb autodetection.

## Rumble / Haptics

| Feature | Details |
|---------|---------|
| Type | QCOM SPMI Haptics (pmi8998 PMIC) |
| Driver | `qcom-spmi-haptics` (INPUT_FF_MEMLESS) |
| Kernel patch | `0009-qcom-spmi-haptics.patch` + `0013-add-force-feedback.patch` |
| Udev | `99-retroid-pocket.rules`: tags `pmi8998_haptics` with `FEEDBACKD_TYPE=vibra` |
| Interface | Standard Linux force-feedback (evdev FF_RUMBLE) |

InputPlumber impact: SPMI haptics is a separate evdev device. It can be added to the
composite device config to route rumble from the virtual gamepad to the haptics hardware.

## Touchscreen

| Device | IC | I2C | Resolution | Inversion |
|--------|-----|-----|------------|-----------|
| Retroid Pocket 5 | Focaltech FT5452 | i2c13 @ 0x38 | 1080x1920 | X+Y inverted |
| Retroid Pocket Mini | Focaltech FT5452 | i2c13 @ 0x38 | 960x1280 | None |
| Retroid Pocket Flip2 | (symlink → RP5) | — | 1080x1920 | X+Y inverted |
| Retroid Pocket Mini V2 | (symlink → RPMini) | — | 960x1280 | None |

Touch GPIOs: reset=GPIO38, interrupt=GPIO39 (tlmm). Supplies: VCC 3.0V, IOVCC 1.8V.

During emulation, `runemu.sh` disables secondary touch:
```bash
swaymsg input "0:0:generic_ft5x06_(a0)" events disabled
swaymsg input "0:0:generic_ft5x06_(8d)" events disabled
```

`DEVICE_HAS_TOUCHSCREEN=true` in all RP quirk configs.

## LEDs

| Feature | Details |
|---------|---------|
| Controller | HTR3212 I2C 12-channel 8-bit PWM |
| Driver | `leds-htr3212` (kernel patch `0010-leds-htr3212.patch`) |
| Interface | `/sys/class/leds/` brightness + multi_intensity |

## IMU

No IMU on any SM8250 device.

**Status: BROKEN — needs critical trigger fix + A/B swap.**
