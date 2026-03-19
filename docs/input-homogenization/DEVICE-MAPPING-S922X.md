# S922X Input Mapping: Current State → Target State

## Platform Summary

| Property | Value |
|----------|-------|
| SoC | Amlogic S922X (A311D, A73+A53 big.LITTLE) |
| Kernel driver | `rocknix-joypad` (NOT singleadc variant) |
| DTS patch | `0005-arm64-meson-odroid-go-ultra-add-joypad.patch` |
| Compatible | `rocknix-joypad` |
| Vendor ID | 0x484B (assumed, vendor not set in DTS — driver default) |
| Product ID | 0x1000 (from DTS `joypad-product = <0x1000>`) |
| Device name | `GO-Ultra Gamepad` |
| ADC | SARADC channels 0-3, scale=4 |
| Deadzone | 64 (GO-Ultra), 400 (RGB10 MAX 3 Pro) |
| A/B swap | **Yes** — BTN_EAST=Physical A, BTN_SOUTH=Physical B |
| Extra button | **BTN_C registered** — shifts SDL button indices |

## Devices (2 total)

| Device | Model String | DTS Base | Notes |
|--------|-------------|----------|-------|
| Hardkernel ODROID-GO-Ultra | Hardkernel ODROID-GO-Ultra | meson-g12b-odroid-go-ultra | Primary |
| Powkiddy RGB10 MAX 3 Pro | Powkiddy RGB10 MAX 3 Pro | Derives from GO-Ultra | Different GPIO pins for sw12-sw18, higher deadzone |

## Current Input Flow (without InputPlumber)

```
GPIO/ADC Hardware (Amlogic GPIOX_0 through GPIOX_19)
    ↓
rocknix-joypad (kernel module, compatible = "rocknix-joypad")
    ↓
/dev/input/eventX (GO-Ultra Gamepad)
/dev/input/by-path/platform-platform-gou_joypad-event-joystick
    ├── Face: BTN_EAST(A), BTN_SOUTH(B), BTN_NORTH(X), BTN_WEST(Y)
    ├── BTN_C (function key — shifts SDL indices!)
    ├── BTN_TL, BTN_TR, BTN_TL2, BTN_TR2
    ├── BTN_SELECT, BTN_START, BTN_MODE
    ├── BTN_THUMBL, BTN_THUMBR
    ├── BTN_DPAD_UP/DOWN/LEFT/RIGHT
    └── ABS_X/Y (left stick), ABS_RX/RY (right stick)
    ↓
oga_controls daemon (keyboard/mouse emulation from joypad)
    device path: platform-platform-gou_joypad-event-joystick
    ↓
SDL2 (gamecontrollerdb.txt)
    Entry: 03001354474f2d556c74726120476100,GO-Ultra Gamepad
    Mapping: a:b1,b:b0,x:b3,y:b4,guide:b11
    ↓
EmulationStation / RetroArch / Standalones
```

## The BTN_C Index Shift Problem

The S922X driver registers **BTN_C (0x132)** as a function button. This code sits
between BTN_EAST (0x131) and BTN_NORTH (0x133) in the evdev bitmap, shifting all
subsequent SDL button indices by +1 compared to devices without BTN_C:

```
evdev code    SDL index   S922X          RK3566 (no BTN_C)
──────────    ─────────   ────────────   ─────────────────
BTN_SOUTH     b0          Physical B     Physical A
BTN_EAST      b1          Physical A     Physical B
BTN_C         b2          Function key   (not registered)
BTN_NORTH     b3          Physical X     b2 ← different index!
BTN_WEST      b4          Physical Y     b3 ← different index!
BTN_TL        b5          L1             b4
BTN_TR        b6          R1             b5
BTN_TL2       b7          L2             b6
BTN_TR2       b8          R2             b7
BTN_SELECT    b9          Select         b8
BTN_START     b10         Start          b9
BTN_MODE      b11         Guide          b10
BTN_THUMBL    b12         L3             b11
BTN_THUMBR    b13         R3             b12
BTN_DPAD_UP   b14         D-Up           b13
BTN_DPAD_DOWN b15         D-Down         b14
BTN_DPAD_LEFT b16         D-Left         b15
BTN_DPAD_RIGHT b17        D-Right        b16
```

This is why the gamecontrollerdb entry has `x:b3,y:b4` (shifted) instead of the
usual `x:b2,y:b3`. The InputPlumber capability map works at the evdev code level,
so this index shift does NOT affect the mapping — BTN_NORTH is still BTN_NORTH
regardless of its SDL index.

## DTS Button Mapping

| Switch | GPIO | Label | evdev Code | Physical Button |
|--------|------|-------|------------|-----------------|
| sw1 | GPIOX_0 | DPAD-UP | BTN_DPAD_UP | D-pad Up |
| sw2 | GPIOX_1 | DPAD-DOWN | BTN_DPAD_DOWN | D-pad Down |
| sw3 | GPIOX_2 | DPAD-LEFT | BTN_DPAD_LEFT | D-pad Left |
| sw4 | GPIOX_3 | DPAD-RIGHT | BTN_DPAD_RIGHT | D-pad Right |
| sw5 | GPIOX_4 | BTN-A | **BTN_EAST** | A (SWAPPED) |
| sw6 | GPIOX_5 | BTN-B | **BTN_SOUTH** | B (SWAPPED) |
| sw7 | GPIOX_6 | BTN-Y | BTN_WEST | Y |
| sw8 | GPIOX_7 | BTN-X | BTN_NORTH | X |
| sw11 | GPIOX_10 | F2 | BTN_MODE | Guide/Function |
| sw12 | GPIOX_11 | F3 | BTN_THUMBL | L3 |
| sw13 | GPIOX_12 | F4 | BTN_THUMBR | R3 |
| sw14 | GPIOX_13 | F5 | BTN_C | Function (extra) |
| sw15 | GPIOX_14 | TOP-LEFT | BTN_TL | L1 |
| sw16 | GPIOX_15 | TOP-RIGHT | BTN_TR | R1 |
| sw17 | GPIOX_16 | F6 | BTN_START | Start |
| sw18 | GPIOX_17 | F1 | BTN_SELECT | Select |
| sw19 | GPIOX_18 | TOP-RIGHT2 | BTN_TR2 | R2 |
| sw20 | GPIOX_19 | TOP-LEFT2 | BTN_TL2 | L2 |

Volume buttons on separate gpio-keys driver:
- GPIOX_8 → KEY_VOLUMEUP
- GPIOX_9 → KEY_VOLUMEDOWN

### RGB10 MAX 3 Pro Differences

Different GPIO assignments for function buttons (sw12-sw18), higher ADC deadzone (400 vs 64),
but same evdev codes and button mapping. Same InputPlumber config applies.

## Supporting Files (current)

| File | Purpose |
|------|---------|
| `gamecontrollerdb/config/gamecontrollerdb.txt` line 14 | SDL mapping |
| `retroarch-joypads/gamepads/GO-Ultra Gamepad.cfg` | RetroArch autoconfig |
| `oga_controls/patches/S922X/000-platform.patch` | Keyboard/mouse emulation |
| `quirks/platforms/S922X/050-modifiers` | BTN_MODE + BTN_START modifiers |
| `quirks/devices/Hardkernel ODROID-GO-Ultra/001-device_config` | Fake jacksense |
| `quirks/devices/Hardkernel ODROID-GO-Ultra/050-audio_path` | Audio routing |

## Target Input Flow (with InputPlumber)

```
GPIO/ADC Hardware
    ↓
rocknix-joypad (kernel module)
    ↓
/dev/input/eventX (GRABBED — hidden from apps)
    ↓
InputPlumber daemon
    Config: composite config matching 484b:1000
    Cap map: A/B swap (BTN_SOUTH↔BTN_EAST) + BTN_C→QuickAccess2
    ↓
Virtual Xbox Series Gamepad (/dev/input/eventY)
    ↓
SDL2: InputPlumber GameController (standard Xbox mapping)
    ↓
oga_controls: BYPASSED (InputPlumber handles keyboard/mouse emulation)
```

## Button-by-Button Verification (target state)

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
| F5 | BTN_C | QuickAccess2 | (misc) | (misc) | ✓ |
| L3 | BTN_THUMBL | LeftStick | BTN_THUMBL | SDL LS | ✓ |
| R3 | BTN_THUMBR | RightStick | BTN_THUMBR | SDL RS | ✓ |
| D-pad | BTN_DPAD_* | DPad* | ABS_HAT0* | SDL D-pad | ✓ |
| Sticks | ABS_X/Y/RX/RY | Sticks | ABS_X/Y/RX/RY | SDL axes | ✓ |

## Implementation Requirements

### New Files Needed
1. **Composite device config** matching vendor `484b`, product `1000`
   - Can add as entry in existing `50-retrogame-joypad.yaml` or create
     `50-go-ultra-gamepad.yaml`
   - Use `retrogame_joypad_ab_swap` capability map (same A/B swap as H700/RK3326)
   - Also map BTN_C → QuickAccess2

### Capability Map Note
The `retrogame_joypad_ab_swap` map (created for RK3326/H700) should work for S922X
since the evdev codes are the same standard Linux input codes. The only addition
needed is the BTN_C → QuickAccess2 mapping (which the standard `retrogame_joypad`
map already includes from RG-DS BTN_Z handling — but BTN_C is a different code).

If `retrogame_joypad_ab_swap` already maps BTN_C, it works. If not, S922X may need
its own capability map variant, or BTN_C mapping should be added to the ab_swap map.

### oga_controls Deprecation
Once InputPlumber is validated on S922X, oga_controls becomes redundant:
- InputPlumber's virtual keyboard + mouse targets replace oga_controls functionality
- The S922X-specific oga_controls patch can be removed
- oga_controls daemon no longer needs to start on S922X devices

## DTS Pin-Level Button Map (patch 0005 — GO-Ultra)

| sw | GPIO Pin | Label | evdev Code | IP Map (needed) |
|----|----------|-------|------------|-----------------|
| sw1 | GPIOX_0 | DPAD-UP | BTN_DPAD_UP | DPadUp |
| sw2 | GPIOX_1 | DPAD-DOWN | BTN_DPAD_DOWN | DPadDown |
| sw3 | GPIOX_2 | DPAD-LEFT | BTN_DPAD_LEFT | DPadLeft |
| sw4 | GPIOX_3 | DPAD-RIGHT | BTN_DPAD_RIGHT | DPadRight |
| sw5 | GPIOX_4 | BTN-A | **BTN_EAST (0x131)** | → **South** (SWAP) |
| sw6 | GPIOX_5 | BTN-B | **BTN_SOUTH (0x130)** | → **East** (SWAP) |
| sw7 | GPIOX_6 | BTN-Y | **BTN_WEST (0x134)** | West |
| sw8 | GPIOX_7 | BTN-X | **BTN_NORTH (0x133)** | North |
| sw11 | GPIOX_10 | F2 | BTN_MODE | Guide |
| sw12 | GPIOX_11 | F3 | BTN_THUMBL | LeftStick |
| sw13 | GPIOX_12 | F4 | BTN_THUMBR | RightStick |
| sw14 | GPIOX_13 | F5 | BTN_C (0x132) | QuickAccess2 |
| sw15 | GPIOX_14 | TOP-LEFT | BTN_TL | LeftBumper |
| sw16 | GPIOX_15 | TOP-RIGHT | BTN_TR | RightBumper |
| sw17 | GPIOX_16 | F6 | BTN_START | Start |
| sw18 | GPIOX_17 | F1 | BTN_SELECT | Select |
| sw19 | GPIOX_18 | TOP-RIGHT2 | BTN_TR2 | RightTrigger |
| sw20 | GPIOX_19 | TOP-LEFT2 | BTN_TL2 | LeftTrigger |

Volume keys (separate gpio-keys driver): GPIOX_8 (VOL_UP), GPIOX_9 (VOL_DOWN).

**Note:** sw7=BTN_WEST (Y), sw8=BTN_NORTH (X) — reversed from RK3566's
sw7=BTN_NORTH, sw8=BTN_WEST. This doesn't affect the capability map since the
evdev codes are the same; only the physical GPIO wiring differs.

### RGB10 MAX 3 Pro Overrides (patch 0008)

Inherits all button codes from GO-Ultra but overrides GPIO pins for function keys:
- sw12 → GPIOX_17 (was GPIOX_11)
- sw13 → GPIOX_16 (was GPIOX_12)
- sw14 → GPIOX_11 (was GPIOX_13)
- sw17 → GPIOX_13 (was GPIOX_16)
- sw18 → GPIOX_12 (was GPIOX_17)
- ADC deadzone: 400 (vs 64 on GO-Ultra), fuzz: 64 (vs 32)

Same evdev codes — same InputPlumber capability map applies.

## Rumble

| Feature | Details |
|---------|---------|
| Type | PWM motor |
| Configured by | `020-gpios` quirk (exports PWM, sets period) |
| Period | 1000000ns (1kHz) |

## LEDs

No status LEDs, no RGB LEDs, no analog stick LEDs on S922X devices.

## Touchscreen

No touchscreen on any S922X device.

## IMU

No IMU on any S922X device.

**Status: NEEDS composite device config + A/B swap capability map (product 0x1000 not matched).**
