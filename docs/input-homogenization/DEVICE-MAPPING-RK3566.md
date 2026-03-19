# RK3566 Input Mapping: Current State → Target State

## Platform Summary

| Property | Value |
|----------|-------|
| SoC | Rockchip RK3566 / RK3568 |
| Kernel driver | `rocknix-singleadc-joypad` |
| DTS template | `rk3566-powkiddy-rk2023.dtsi` |
| Vendor ID | 0x484B |
| Product IDs | 0x1101 (standard), 0x1121 (skeleton/RG-DS) |
| Device name | `retrogame_joypad` |
| ADC | SARADC channel 3, 4-channel mux (GPIO) |
| Poll interval | 10ms (standard), 5ms (RG-DS) |
| A/B swap | **No** — matches Xbox convention |

## Devices (16 total)

Anbernic: RG353P, RG353PS, RG353V, RG353VS, RG353M, RG503, RG ARC-D, RG ARC-S, RG DS
Powkiddy: RGB30, RK2023, x35s, x55, RGB10MAX3, RGB20Pro, RGB20SX

## Current Input Flow (without InputPlumber)

```
GPIO/ADC Hardware
    ↓
rocknix-singleadc-joypad (kernel module)
    ↓
/dev/input/eventX
    ├── evdev: BTN_SOUTH(A), BTN_EAST(B), BTN_NORTH(X), BTN_WEST(Y)
    ├── evdev: BTN_TL, BTN_TR, BTN_TL2, BTN_TR2 (digital)
    ├── evdev: ABS_X/Y (left stick), ABS_RX/RY (right stick)
    ├── evdev: BTN_DPAD_UP/DOWN/LEFT/RIGHT
    ├── evdev: BTN_SELECT, BTN_START, BTN_MODE
    └── evdev: BTN_THUMBL, BTN_THUMBR
    ↓
SDL2 (gamecontrollerdb.txt)
    Entry: 19009b4d4b4800000111000000010000,retrogame_joypad
    Mapping: a:b0,b:b1,x:b2,y:b3 (matches Xbox standard)
    ↓
EmulationStation / RetroArch / Standalones
```

### Supporting Files (current)

| File | Purpose |
|------|---------|
| `gamecontrollerdb/config/gamecontrollerdb.txt` line 5-6 | SDL mapping (2 GUID variants) |
| `retroarch-joypads/gamepads/retrogame_joypad.cfg` | RetroArch autoconfig |
| `quirks/devices/Anbernic RG353P/020-gpios` | PWM rumble on pwmchip1 |
| `quirks/devices/Anbernic RG DS/050-modifiers` | BTN_MODE + BTN_START modifiers |
| `quirks/devices/Anbernic RG DS/110-retroarch-joypad` | Hotkey override to btn 10 |
| `systemd/hwdb.d/20-joypad.hwdb` | Mark as tablet for wake detection |

## Target Input Flow (with InputPlumber)

```
GPIO/ADC Hardware
    ↓
rocknix-singleadc-joypad (kernel module)
    ↓
/dev/input/eventX (GRABBED — hidden from apps)
    ↓
InputPlumber daemon
    Config: 50-retrogame-joypad.yaml
    Cap map: retrogame_joypad.yaml (1:1, no swap)
    ↓
Virtual Xbox Series Gamepad (/dev/input/eventY)
    ├── evdev: BTN_SOUTH(A), BTN_EAST(B), BTN_NORTH(X), BTN_WEST(Y)
    ├── evdev: ABS_Z (L2 trigger analog), ABS_RZ (R2 trigger analog)
    ├── evdev: ABS_X/Y, ABS_RX/RY (sticks)
    └── evdev: ABS_HAT0X/HAT0Y (d-pad as hat switch)
    ↓
SDL2 (gamecontrollerdb.txt)
    Entry: 0300f5a35e040000120b000001000000,InputPlumber GameController
    Mapping: a:b0,b:b1,x:b2,y:b3 (standard Xbox)
    ↓
EmulationStation / RetroArch / Standalones
```

### New/Changed Files (target)

| File | Purpose |
|------|---------|
| `inputplumber/capability_maps/retrogame_joypad.yaml` | 1:1 evdev→gamepad mapping |
| `inputplumber/devices/50-retrogame-joypad.yaml` | Composite: 484b:1101/1121 |
| `gamecontrollerdb/config/gamecontrollerdb.txt` line 26 | InputPlumber virtual pad SDL |

### Files Unchanged
- `quirks/devices/*/020-gpios` — PWM rumble setup via sysfs (not evdev, unaffected)
- `quirks/devices/*/050-modifiers` — env vars for gptokeyb (still used by PortMaster)
- `systemd/hwdb.d/20-joypad.hwdb` — still needed for virtual device wake

## Button-by-Button Verification

| Physical | Source evdev | Cap map target | Virtual evdev | SDL result | Correct? |
|----------|-------------|----------------|---------------|------------|----------|
| A | BTN_SOUTH | South | BTN_SOUTH | SDL A | ✓ |
| B | BTN_EAST | East | BTN_EAST | SDL B | ✓ |
| X | BTN_NORTH | North | BTN_NORTH | SDL X | ✓ |
| Y | BTN_WEST | West | BTN_WEST | SDL Y | ✓ |
| L1 | BTN_TL | LeftBumper | BTN_TL | SDL LB | ✓ |
| R1 | BTN_TR | RightBumper | BTN_TR | SDL RB | ✓ |
| L2 | BTN_TL2 | LeftTrigger | ABS_Z (analog) | SDL LT | ✓ |
| R2 | BTN_TR2 | RightTrigger | ABS_RZ (analog) | SDL RT | ✓ |
| Select | BTN_SELECT | Select | BTN_SELECT | SDL Back | ✓ |
| Start | BTN_START | Start | BTN_START | SDL Start | ✓ |
| Guide/F | BTN_MODE | Guide | BTN_MODE | SDL Guide | ✓ |
| L3 | BTN_THUMBL | LeftStick | BTN_THUMBL | SDL LS | ✓ |
| R3 | BTN_THUMBR | RightStick | BTN_THUMBR | SDL RS | ✓ |
| D-Up | BTN_DPAD_UP | DPadUp | ABS_HAT0Y- | SDL DUp | ✓ |
| D-Down | BTN_DPAD_DOWN | DPadDown | ABS_HAT0Y+ | SDL DDown | ✓ |
| D-Left | BTN_DPAD_LEFT | DPadLeft | ABS_HAT0X- | SDL DLeft | ✓ |
| D-Right | BTN_DPAD_RIGHT | DPadRight | ABS_HAT0X+ | SDL DRight | ✓ |
| Left Stick | ABS_X/Y | LeftStick | ABS_X/Y | SDL LS axis | ✓ |
| Right Stick | ABS_RX/RY | RightStick | ABS_RX/RY | SDL RS axis | ✓ |

## RG-DS Special Case

The RG-DS has an additional InputPlumber config (`01-anbernic-rg-ds.yaml`) that:
- Matches model string "Anbernic RG DS" (takes priority over generic 50- config)
- Adds ICM-42607P IIO IMU source (gyroscope + accelerometer)
- Uses `ds5` (DualSense) target instead of `xbox-series` (for motion sensor API)
- Mount matrix: x=[-1,0,0], y=[0,1,0], z=[0,0,-1]
- Additional button: BTN_Z (Home, from ADC) → QuickAccess2

**Status: COMPLETE — no changes needed.**
