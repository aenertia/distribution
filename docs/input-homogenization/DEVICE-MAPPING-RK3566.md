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

## DTS Pin-Level Button Map (rk3566-powkiddy-rk2023.dtsi)

| sw | GPIO Pin | Label | evdev Code | IP Map | Correct? |
|----|----------|-------|------------|--------|----------|
| sw1 | GPIO3_PA3 | DPAD-UP | BTN_DPAD_UP | DPadUp | ✓ |
| sw2 | GPIO3_PA4 | DPAD-DOWN | BTN_DPAD_DOWN | DPadDown | ✓ |
| sw3 | GPIO3_PA6 | DPAD-LEFT | BTN_DPAD_LEFT | DPadLeft | ✓ |
| sw4 | GPIO3_PA5 | DPAD-RIGHT | BTN_DPAD_RIGHT | DPadRight | ✓ |
| sw5 | GPIO3_PC3 | BTN-A | BTN_SOUTH (0x130) | South | ✓ |
| sw6 | GPIO3_PC2 | BTN-B | BTN_EAST (0x131) | East | ✓ |
| sw7 | GPIO3_PC0 | BTN-X | BTN_NORTH (0x133) | North | ✓ |
| sw8 | GPIO3_PC1 | BTN-Y | BTN_WEST (0x134) | West | ✓ |
| sw9 | GPIO3_PB6 | SELECT | BTN_SELECT | Select | ✓ |
| sw10 | GPIO3_PB5 | START | BTN_START | Start | ✓ |
| sw11 | GPIO3_PB7 | BTN_F | BTN_MODE | Guide | ✓ |
| sw12 | GPIO3_PB1 | BTN_TL | BTN_TL | LeftBumper | ✓ |
| sw13 | GPIO3_PB3 | BTN_TR | BTN_TR | RightBumper | ✓ |
| sw14 | GPIO3_PB2 | BTN_TL2 | BTN_TL2 | LeftTrigger | ✓ |
| sw15 | GPIO3_PB4 | BTN_TR2 | BTN_TR2 | RightTrigger | ✓ |
| sw16 | GPIO3_PA1 | THUMBL | BTN_THUMBL | LeftStick | ✓ |
| sw17 | GPIO3_PA2 | THUMBR | BTN_THUMBR | RightStick | ✓ |

ADC: SARADC ch3, 4-channel mux (GPIO0_PB5/PB6/PB7), tuning 245%, deadzone 64, poll 10ms.
All RK3566 devices (353P/V/PS/VS/M, 503, RGB30, RK2023, x35s, x55, RGB10MAX3, RGB20Pro, RGB20SX)
inherit this template without button code overrides.

## Rumble

| Device | Type | PWM | Period | Quirk |
|--------|------|-----|--------|-------|
| RG353P/PS | PWM motor | pwmchip1 | 1000000ns | `020-gpios` |
| RG353V/VS | PWM motor | pwmchip1 | 1000000ns | `020-gpios` (jack detect GPIO86) |
| RGB30 | PWM motor | pwmchip1 | 1000000ns | `020-gpios` |
| RG ARC-D/S | PWM motor | pwmchip1 | 1000000ns | `020-gpios` |
| RG-DS | PWM motor | PWM14 | 100000ns (100kHz) | DTS `pwm-names = "enable"` |
| Others | PWM motor | pwmchip1 | 1000000ns | `020-gpios` |

DTS rumble properties (rk3566-powkiddy-rk2023.dtsi):
```
pwm-names = "enable";
rumble-boost-weak = <0x00>;
rumble-boost-strong = <0x00>;
```

InputPlumber impact: None — FF_RUMBLE passthrough works via the kernel driver's
PWM output. The `020-gpios` quirk scripts configure PWM via sysfs before
InputPlumber starts.

## LEDs

| Device | LED Type | Pin/PWM | Function |
|--------|----------|---------|----------|
| RK2023 template | 2x PWM LED | PWM6 (green), PWM7 (red) | Status, Charging |
| RG-DS | 3x PWM LED | PWM5 (green), PWM6 (amber), PWM7 (red) | Power, Charging, Status |

Controlled via `/sys/class/leds/` — no InputPlumber integration needed.

## Touchscreen

| Device | IC | I2C | Resolution | Inversion | Notes |
|--------|-----|-----|------------|-----------|-------|
| RG-DS (lower) | Goodix GT911 | i2c5 @ 0x14 | 640x480 | None | Primary panel |
| RG-DS (upper) | Goodix GT911 | i2c3 @ 0x14 | 640x480 | X+Y inverted | Secondary |
| RG ARC-D | Goodix GT911 | i2c3 @ 0x14 | 640x480 | X-Y swapped | Patch 0025 fixes |

Standard RK3566 devices (353P, RGB30, etc.) have NO touchscreen.

RG-DS dual-touch calibration (`touchcontrol` quirk):
- Left panel (i2c5): `LIBINPUT_CALIBRATION_MATRIX="0.5 0 0 0 1 0"`
- Right panel (i2c3): `LIBINPUT_CALIBRATION_MATRIX="0.5 0 0.5 0 1 0"`

## RG-DS Special Case

The RG-DS has an additional InputPlumber config (`01-anbernic-rg-ds.yaml`) that:
- Matches model string "Anbernic RG DS" (takes priority over generic 50- config)
- Adds ICM-42607P IIO IMU source (gyroscope + accelerometer)
- Uses `ds5` (DualSense) target instead of `xbox-series` (for motion sensor API)
- Mount matrix: x=[-1,0,0], y=[0,1,0], z=[0,0,-1]
- Additional button: BTN_Z (Home, from ADC) → QuickAccess2

**Status: COMPLETE — no changes needed.**

## RG ARC-D/S — 6-Button Layout (NEEDS UNIQUE CAPABILITY MAP)

The RG ARC uses a **6-button Genesis/Mega Drive layout** (A,B,C bottom row; X,Y,Z top row)
applied via patch `0005-arm64-dts-rockchip-fixup-anbernic-controls.patch`.

This REPLACES the standard sw5-sw8 nodes with named button nodes using BTN_A/B/C/X/Y/Z:

| Node | GPIO Pin | evdev Code | SDL Index | gamecontrollerdb |
|------|----------|------------|-----------|------------------|
| button-a | GPIO3_PC3 | BTN_A (0x130 = BTN_SOUTH) | b0 | a:b0 |
| button-b | GPIO3_PC2 | BTN_B (0x131 = BTN_EAST) | b1 | b:b1 |
| button-c | GPIO3_PA2 | **BTN_C (0x132)** | b2 | rightstick:b2 |
| button-x | GPIO3_PC0 | BTN_X (0x133 = BTN_NORTH) | b3 | — |
| button-y | GPIO3_PC1 | BTN_Y (0x134 = BTN_WEST) | b4 | x:b4 |
| button-z | GPIO3_PA1 | **BTN_Z (0x135)** | b5 | leftstick:b5 |

The extra BTN_C (0x132) and BTN_Z (0x135) buttons shift all subsequent SDL
button indices by 2 compared to standard 4-button devices.

**gamecontrollerdb:** `a:b0,b:b1,x:b4,y:b3,rightstick:b2,leftstick:b5`

The gamecontrollerdb maps BTN_C→rightstick and BTN_Z→leftstick as workarounds
since there are no SDL C/Z button mappings. This works for existing SDL-based
input but is semantically incorrect.

**InputPlumber status:** NOT correctly handled. The current `retrogame_joypad`
capability map does not map BTN_C or BTN_Z. The RG ARC needs a dedicated
capability map (`rg_arc_joypad.yaml`) that maps:
- BTN_C → RightPaddle1 or QuickAccess (extra face button)
- BTN_Z → LeftPaddle1 or QuickAccess2 (extra face button)
- Face buttons A/B are NOT swapped on RG ARC (a:b0 = standard)

**Vendor:Product:** 0x0001:0x0A2C (different vendor from standard retrogame_joypad)

**Status: NEEDS dedicated capability map + composite config.**
