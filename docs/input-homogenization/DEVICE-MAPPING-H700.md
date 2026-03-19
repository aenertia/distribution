# H700 Input Mapping: Current State → Target State

## Platform Summary

| Property | Value |
|----------|-------|
| SoC | Allwinner H700 (H616 family) |
| Kernel driver | `rocknix-singleadc-joypad` |
| DTS patch | `0140-rg35xx-2024-use-rocknix-joypad-driver.patch` |
| Vendor ID | 0x484B |
| Product ID | **0x14DF** (distinct from RK3566 0x1101) |
| Device name | `H700 Gamepad` |
| ADC | GPADC channel 0, no multiplexing |
| Poll interval | 10ms |
| Deadzone | 128 (vs 64 on RK3566) |
| Tuning | 70% (vs 245% on RK3566) |
| A/B swap | **Yes** — BTN_SOUTH and BTN_EAST are swapped in DTS |

## Devices (11 total)

Anbernic: RG28XX, RG34XX, RG34XX-SP, RG35XX Pro, RG35XX 2024, RG35XX H,
RG35XX Plus, RG35XX SP, RG40XX H, RG40XX V, RG CubeXX

## Current Input Flow (without InputPlumber)

```
GPIO/ADC Hardware (Allwinner PIO PA/PE pins)
    ↓
rocknix-singleadc-joypad (kernel module)
    ↓
/dev/input/eventX (H700 Gamepad, 484B:14DF)
    ├── sw5: PA0 → BTN_EAST  (Physical A — SWAPPED from RK3566!)
    ├── sw6: PA1 → BTN_SOUTH (Physical B — SWAPPED from RK3566!)
    ├── sw7: PA3 → BTN_NORTH (Physical X — same as RK3566)
    ├── sw8: PA2 → BTN_WEST  (Physical Y — same as RK3566)
    ├── BTN_TL, BTN_TR, BTN_TL2, BTN_TR2 (digital)
    ├── ABS_X/Y, ABS_RX/RY (analog sticks)
    ├── BTN_DPAD_UP/DOWN/LEFT/RIGHT
    └── BTN_SELECT, BTN_START, BTN_MODE, BTN_THUMBL, BTN_THUMBR
    ↓
SDL2 (gamecontrollerdb.txt)
    Entry: 1900f6a24b480000df14000000010000,H700 Gamepad
    Mapping: a:b1,b:b0,x:b3,y:b2 (COMPENSATES for swap)
    ↓
EmulationStation / RetroArch / Standalones
```

### The A/B Swap Explained

The H700 DTS assigns BTN_EAST to the physical A button (sw5) and BTN_SOUTH to
the physical B button (sw6). This is the **opposite** of RK3566 where sw5=BTN_SOUTH
and sw6=BTN_EAST.

The `gamecontrollerdb.txt` entry for H700 compensates: `a:b1` maps SDL A to button
index 1 (BTN_EAST), so pressing the physical A button correctly triggers SDL A.

### Supporting Files (current)

| File | Purpose |
|------|---------|
| `gamecontrollerdb/config/gamecontrollerdb.txt` line 20 | SDL mapping with A/B swap |
| `quirks/devices/Anbernic RG40XX H/010-analog_sticks_led_control` | LED control flag |
| `quirks/devices/Anbernic RG40XX V/010-analog_sticks_led_control` | LED control flag |
| `quirks/devices/Anbernic RG CubeXX/010-analog_sticks_led_control` | LED control flag |

## Target Input Flow (with InputPlumber)

```
GPIO/ADC Hardware
    ↓
rocknix-singleadc-joypad (kernel module)
    ↓
/dev/input/eventX (GRABBED — hidden from apps)
    ↓
InputPlumber daemon
    Config: 50-h700-gamepad.yaml (match 484b:14df)
    Cap map: h700_gamepad.yaml (swap BTN_SOUTH↔BTN_EAST)
    ↓
Virtual Xbox Series Gamepad (/dev/input/eventY)
    ├── BTN_SOUTH → Physical A (correct!)
    ├── BTN_EAST → Physical B (correct!)
    └── (all other buttons pass through normally)
    ↓
SDL2 (gamecontrollerdb.txt)
    Entry: InputPlumber GameController a:b0,b:b1,x:b2,y:b3
    ↓
EmulationStation / RetroArch / Standalones
```

## Button-by-Button Verification

| Physical | Source evdev | Cap map target | Virtual evdev | SDL result | Correct? |
|----------|-------------|----------------|---------------|------------|----------|
| A | **BTN_EAST** | **South** ← SWAP | BTN_SOUTH | SDL A | ✓ |
| B | **BTN_SOUTH** | **East** ← SWAP | BTN_EAST | SDL B | ✓ |
| X | BTN_NORTH | North | BTN_NORTH | SDL X | ✓ |
| Y | BTN_WEST | West | BTN_WEST | SDL Y | ✓ |
| L1 | BTN_TL | LeftBumper | BTN_TL | SDL LB | ✓ |
| R1 | BTN_TR | RightBumper | BTN_TR | SDL RB | ✓ |
| L2 | BTN_TL2 | LeftTrigger | ABS_Z (analog) | SDL LT | ✓ |
| R2 | BTN_TR2 | RightTrigger | ABS_RZ (analog) | SDL RT | ✓ |
| Select | BTN_SELECT | Select | BTN_SELECT | SDL Back | ✓ |
| Start | BTN_START | Start | BTN_START | SDL Start | ✓ |
| Guide | BTN_MODE | Guide | BTN_MODE | SDL Guide | ✓ |
| L3 | BTN_THUMBL | LeftStick | BTN_THUMBL | SDL LS | ✓ |
| R3 | BTN_THUMBR | RightStick | BTN_THUMBR | SDL RS | ✓ |
| D-pad | BTN_DPAD_* | DPad* | ABS_HAT0* | SDL D-pad | ✓ |
| Sticks | ABS_X/Y/RX/RY | Sticks | ABS_X/Y/RX/RY | SDL axes | ✓ |

## X/Y Behavior Change

The H700 gamecontrollerdb previously mapped `x:b3=BTN_WEST, y:b2=BTN_NORTH` (position-based
for Xbox layout). With InputPlumber's 1:1 X/Y mapping (BTN_NORTH→North, BTN_WEST→West),
the virtual gamepad uses `x:b2=BTN_NORTH, y:b3=BTN_WEST`.

**Effect:** The top face button (labeled X in Nintendo convention) now maps to SDL X
instead of SDL Y. This changes from position-matched to label-matched, consistent with
RK3566. In practice, this means on-screen prompts saying "Press X" now correspond to the
button physically labeled X on the device.

## Files Required

### New Files
| File | Content |
|------|---------|
| `capability_maps/h700_gamepad.yaml` | Copy of retrogame_joypad with BTN_SOUTH↔BTN_EAST swapped |
| `devices/50-h700-gamepad.yaml` | Composite: vendor 484b, product 14df, cap map h700_gamepad |

### Unchanged Files
- `quirks/devices/*/010-analog_sticks_led_control` — sysfs-based, unaffected
- `systemd/hwdb.d/20-joypad.hwdb` — still marks joypad for wake detection

## DTS Pin-Level Button Map (patch 0140)

| sw | GPIO Pin | Label | evdev Code | IP Map (needed) |
|----|----------|-------|------------|-----------------|
| sw1 | PA6 | DPAD-UP | BTN_DPAD_UP | DPadUp |
| sw2 | PE0 | DPAD-DOWN | BTN_DPAD_DOWN | DPadDown |
| sw3 | PA8 | DPAD-LEFT | BTN_DPAD_LEFT | DPadLeft |
| sw4 | PA9 | DPAD-RIGHT | BTN_DPAD_RIGHT | DPadRight |
| sw5 | PA0 | BTN-A | **BTN_EAST (0x131)** | → **South** (SWAP) |
| sw6 | PA1 | BTN-B | **BTN_SOUTH (0x130)** | → **East** (SWAP) |
| sw7 | PA3 | BTN-X | BTN_NORTH (0x133) | North |
| sw8 | PA2 | BTN-Y | BTN_WEST (0x134) | West |
| sw9 | PA5 | SELECT | BTN_SELECT | Select |
| sw10 | PA4 | START | BTN_START | Start |
| sw11 | PE3 | BTN_F | BTN_MODE | Guide |
| sw12 | PE8 | THUMBL | BTN_THUMBL | LeftStick |
| sw13 | PE9 | THUMBR | BTN_THUMBR | RightStick |
| sw14 | PA12 | BTN_TR | BTN_TR | RightBumper |
| sw15 | PA7 | BTN_TR2 | BTN_TR2 | RightTrigger |
| sw16 | PA10 | BTN_TL | BTN_TL | LeftBumper |
| sw17 | PA11 | BTN_TL2 | BTN_TL2 | LeftTrigger |

ADC: GPADC ch0, no mux, tuning 70%, deadzone 128 (double RK3566), poll 10ms.

## Rumble

No PWM rumble motor in any H700 device DTS. No force-feedback driver.

## LEDs

| Feature | Details |
|---------|---------|
| Status LED | GPIO RGB (PI7), `LED_FUNCTION_KBD_BACKLIGHT`, `LED_COLOR_ID_RGB` |
| Analog stick LEDs | `DEVICE_ANALOG_STICKS_LED_CONTROL=true` on RG40XX H/V, RG CubeXX |
| Control script | `bin/analog_sticks_ledcontrol` in quirk directories |
| Colors | 7 presets: red, green, blue, white, orange, yellow, purple |

LED control is sysfs-based via `/sys/class/leds/` — not managed by InputPlumber.

## Touchscreen

No touchscreen on any H700 device.

## IMU

No IMU on any H700 device.

**Status: BLOCKED — needs h700_gamepad capability map + composite config.**
