# ADR-003: Per-Device Implementation Status

## Status

In progress — RK3566 working, others need fixes.

---

## RK3566 — COMPLETE

### Current State (without InputPlumber)
```
rocknix-singleadc-joypad (kernel)
  → /dev/input/eventX (retrogame_joypad, vendor 0x484B, product 0x1101)
  → SDL: gamecontrollerdb a:b0,b:b1,x:b2,y:b3
  → RetroArch: retrogame_joypad.cfg
  → Quirks: 020-gpios (PWM rumble), 050-modifiers (BTN_SELECT/BTN_START)
```

### Target State (with InputPlumber)
```
rocknix-singleadc-joypad (kernel)
  → /dev/input/eventX (grabbed by InputPlumber)
  → Capability map: retrogame_joypad (1:1, no swap)
  → Virtual Xbox Series gamepad (/dev/input/eventY)
  → SDL: InputPlumber GameController a:b0,b:b1,x:b2,y:b3
  → Quirks: 020-gpios still needed for PWM rumble setup
```

### Devices
| Device | Model String | Product ID | Status |
|--------|-------------|------------|--------|
| Anbernic RG353P | Anbernic RG353P | 0x1101 | DONE |
| Anbernic RG353PS | Anbernic RG353PS | 0x1101 | DONE |
| Anbernic RG353V | Anbernic RG353V | 0x1101 | DONE |
| Anbernic RG353VS | Anbernic RG353VS | 0x1101 | DONE |
| Anbernic RG353M | Anbernic RG353M | 0x1101 | DONE |
| Anbernic RG503 | Anbernic RG503 | 0x1101 | DONE |
| Anbernic RG ARC-D | Anbernic RG ARC-D | 0x1101 | DONE |
| Anbernic RG ARC-S | Anbernic RG ARC-S | 0x1101 | DONE |
| Powkiddy RGB30 | Powkiddy RGB30 | 0x1101 | DONE |
| Powkiddy RK2023 | Powkiddy RK2023 | 0x1101 | DONE |
| Powkiddy x35s | Powkiddy x35s | 0x1101 | DONE |
| Powkiddy x55 | Powkiddy x55 | 0x1101 | DONE |
| Powkiddy RGB10MAX3 | Powkiddy RGB10MAX3 | 0x1101 | DONE |
| Powkiddy RGB20Pro | Powkiddy RGB20 Pro | 0x1101 | DONE |
| Powkiddy RGB20SX | Powkiddy RGB20SX | 0x1101 | DONE |
| Anbernic RG DS | Anbernic RG DS | 0x1121 | DONE (+ IMU) |

### Config Files
- Capability map: `retrogame_joypad.yaml` (shared, in inputplumber package)
- Composite device: `50-retrogame-joypad.yaml` (matches 484b:1101 and 484b:1121)
- RG-DS override: `01-anbernic-rg-ds.yaml` (adds ICM-42607P IIO, ds5 target)

---

## H700 — NEEDS FIX

### Current State (without InputPlumber)
```
rocknix-singleadc-joypad (kernel)
  → /dev/input/eventX (H700 Gamepad, vendor 0x484B, product 0x14DF)
  → SDL: gamecontrollerdb a:b1,b:b0,x:b3,y:b2 (A/B swapped, X/Y position-mapped)
  → RetroArch: (uses gamecontrollerdb mapping)
  → Quirks: 010-analog_sticks_led_control
```

### Target State (with InputPlumber)
```
rocknix-singleadc-joypad (kernel)
  → /dev/input/eventX (grabbed by InputPlumber)
  → Capability map: h700_gamepad (swap BTN_SOUTH↔BTN_EAST)
  → Virtual Xbox Series gamepad
  → SDL: InputPlumber GameController a:b0,b:b1,x:b2,y:b3
  → Note: X/Y changes from position-matched to label-matched
```

### What's Broken Now
1. Product 0x14DF not matched → InputPlumber ignores the device entirely
2. Even if matched, 1:1 map would swap A/B actions

### Devices
| Device | Product ID | Status |
|--------|------------|--------|
| Anbernic RG28XX | 0x14DF | BLOCKED — needs h700_gamepad cap map + composite config |
| Anbernic RG34XX | 0x14DF | BLOCKED |
| Anbernic RG34XX-SP | 0x14DF | BLOCKED |
| Anbernic RG35XX Pro | 0x14DF | BLOCKED |
| Anbernic RG35XX 2024 | 0x14DF | BLOCKED |
| Anbernic RG35XX H | 0x14DF | BLOCKED |
| Anbernic RG35XX Plus | 0x14DF | BLOCKED |
| Anbernic RG35XX SP | 0x14DF | BLOCKED |
| Anbernic RG40XX H | 0x14DF | BLOCKED |
| Anbernic RG40XX V | 0x14DF | BLOCKED |
| Anbernic RG CubeXX | 0x14DF | BLOCKED |

### Fix Required
- Create `h700_gamepad.yaml` capability map (swap BTN_SOUTH↔BTN_EAST)
- Create `50-h700-gamepad.yaml` composite config (match 484b:14df)

### DTS Button Reference
```
sw5: PA0 → BTN_EAST   (Physical A — SWAPPED from RK3566)
sw6: PA1 → BTN_SOUTH  (Physical B — SWAPPED from RK3566)
sw7: PA3 → BTN_NORTH  (Physical X — same as RK3566)
sw8: PA2 → BTN_WEST   (Physical Y — same as RK3566)
```
Triggers: BTN_TL2/BTN_TR2 (digital, same as RK3566)
Deadzone: 128 (vs 64 on RK3566), tuning: 70% (vs 245% on RK3566)

---

## SM8250 (Retroid Pocket) — NEEDS FIX (CRITICAL)

### Current State (without InputPlumber)
```
retroid-pocket-gamepad (kernel, UART16 serial @ 115200)
  → /dev/input/eventX (Retroid Pocket Gamepad, vendor 0x2020, product 0x3001)
  → udev: 99-retroid-pocket.rules (MODE="0666", ID_INPUT_JOYSTICK="1")
  → SDL: gamecontrollerdb a:b1,b:b0,lefttrigger:a6,righttrigger:a7
  → RetroArch: Retroid Pocket Gamepad.cfg
  → Calibration: gamepadcalibration (GPcal) package
  → Quirks: touchscreen disable on dual-screen models
```

### Target State (with InputPlumber)
```
retroid-pocket-gamepad (kernel, UART16 serial)
  → /dev/input/eventX (grabbed by InputPlumber)
  → Capability map: retroid_pocket_gamepad (swap A/B, fix triggers)
  → Virtual Xbox Series gamepad
  → SDL: InputPlumber GameController
```

### What's Broken Now
1. **CRITICAL: Triggers are completely broken** — mapped to ABS_Z/ABS_RZ (stick Z-axes)
   instead of ABS_HAT2X/ABS_HAT2Y (actual trigger axes). L2/R2 produce stick data, not trigger data.
2. **A/B swapped** — Physical A→BTN_EAST→East→SDL B (should be SDL A)

### Axis Map (from kernel driver)
```
ABS_X    (0x00) → Left Stick X     (range ±0x580)
ABS_Y    (0x01) → Left Stick Y     (range ±0x580)
ABS_Z    (0x02) → Left Stick Z     (NOT a trigger — third stick axis)
ABS_RX   (0x03) → Right Stick X    (range ±0x580)
ABS_RY   (0x04) → Right Stick Y    (range ±0x580)
ABS_RZ   (0x05) → Right Stick Z    (NOT a trigger — third stick axis)
ABS_HAT2X(0x14) → LEFT TRIGGER     (range 0–0x610, fuzz=30)  ← CORRECT
ABS_HAT2Y(0x15) → RIGHT TRIGGER    (range 0–0x610, fuzz=30)  ← CORRECT
```

### Button Map (from kernel driver keymap[])
```
Index  0: BTN_DPAD_UP      Index  8: BTN_TL
Index  1: BTN_DPAD_DOWN     Index  9: BTN_TR
Index  2: BTN_DPAD_LEFT     Index 10: BTN_SELECT
Index  3: BTN_DPAD_RIGHT    Index 11: BTN_START
Index  4: BTN_NORTH          Index 12: BTN_THUMBL
Index  5: BTN_WEST           Index 13: BTN_THUMBR
Index  6: BTN_EAST  ← Phys A Index 14: BTN_MODE
Index  7: BTN_SOUTH ← Phys B Index 15: BTN_BACK
```

### Devices
| Device | Variant | Status |
|--------|---------|--------|
| Retroid Pocket 5 | RP5 (1080x1920, touch inverted) | BROKEN — triggers + A/B |
| Retroid Pocket Mini | RPMini (960x1280) | BROKEN |
| Retroid Pocket Mini V2 | symlink → RPMini | BROKEN |
| Retroid Pocket Flip2 | symlink → RP5 | BROKEN |

### Fix Required
- Update `retroid_pocket_gamepad.yaml`:
  - `ABS_Z` → `ABS_HAT2X` for LeftTrigger
  - `ABS_RZ` → `ABS_HAT2Y` for RightTrigger
  - `BTN_SOUTH` target: South → **East**
  - `BTN_EAST` target: East → **South**

### Emulator-Specific Configs (existing, may need updates post-InputPlumber)
- Flycast: `config/SM8250/mappings/SDL_Retroid Pocket Gamepad.cfg`
- Mupen64Plus: `config/SM8250/mupen64plus.cfg` (section [Retroid Pocket Gamepad])
- RPCS3: `config/SM8250/input_configs/global/Default.yml`

---

## RK3326 — PARTIAL, COMPLEX

### Current State (without InputPlumber)
```
6 different kernel drivers, each with unique vendor:product IDs:
  1. odroidgo2-joypad        (0x0226:0x0001) — OGA, RG351M/V
  2. odroidgo2-v11-joypad    (0xDEA8:0x0002) — OGA-BE, RGB10
  3. odroidgo3-joypad        (0xC3EA:0x0001) — OGS
  4. rocknix-singleadc-joypad(0x484B:varies)  — G350, RGB10X, RGB20S, R33S, R36S
  5. xu10-joypad             (0xC3B0/0xC3BB:0x0200) — XU10, XU Mini M
  6. adc-joystick+adc-keys   (standard)       — GameForce Chi

Each has a unique gamecontrollerdb entry with different button indices.
oga_controls daemon provides keyboard/mouse emulation on RK3326/S922X.
```

### Target State (with InputPlumber)
```
Each driver matched by vendor:product in InputPlumber composite config
  → Appropriate capability map applied (most need A/B swap)
  → Virtual Xbox Series gamepad
  → oga_controls becomes redundant (Phase 3 removal)
```

### singleadc-joypad Devices (can be fixed now)

| Device | Vendor:Product | Name | A/B Swap? | Status |
|--------|---------------|------|-----------|--------|
| BatleXP G350 | 484B:1101 | retrogame_joypad | No | DONE (matches existing config) |
| RGB10X | 484B:1211 | retrogame_joypad_s1_f2 | Yes | NEEDS composite entry + ab_swap map |
| RGB20S | 484B:1177 | RGB20S Gamepad | Yes | NEEDS composite entry + ab_swap map |
| R33S | 0001:0AA2 | r33s_joypad | Yes | NEEDS composite entry + ab_swap map |
| R36S | 0001:1188 | r36s_Gamepad | Yes | NEEDS composite entry + ab_swap map |

### Legacy Driver Devices (need driver source analysis first)

| Device | Driver | Vendor:Product | A/B | Status |
|--------|--------|---------------|-----|--------|
| OGA | odroidgo2 | 0226:0001 | Swap | BLOCKED — need evdev code verification |
| OGA-BE | odroidgo2-v11 | DEA8:0002 | Swap | BLOCKED |
| RG351M | odroidgo2 | 0226:0001 | Swap | BLOCKED |
| RG351V | odroidgo2 | 0226:0001 | Swap | BLOCKED |
| RGB10 | odroidgo2-v11 | DEA8:0002 | Swap | BLOCKED |
| OGS | odroidgo3 | C3EA:0001 | Swap | BLOCKED |
| XU10 | xu10 | C3B0:0200 | **a:b2** (!!) | BLOCKED — completely unique layout |
| XU Mini M | xu10 variant | C3BB:0200 | Swap | BLOCKED |
| GameForce Chi | adc-joystick | ??? | ??? | BLOCKED — standard kernel driver |
| GameForce ACE | ??? | 341A:??? | Swap | BLOCKED — analog triggers on -a2/-a5 |
| R33S/R36S clones | varies | varies | Swap | BLOCKED |

### Key Difference: odroidgo2 Button Index Layout
The odroidgo2 driver produces a **completely different evdev button ordering** from singleadc:
```
singleadc:  b0=SOUTH, b1=EAST, ..., b6=TL2, b7=TR2, ..., b13=DPAD_UP
odroidgo2:  b0=SOUTH(?), b1=EAST(?), ..., b6=DPAD_UP, b7=DPAD_DOWN, ...
```
The d-pad buttons appear at indices b6-b9 (vs b13-b16 for singleadc), suggesting the driver
registers different/additional KEY codes that shift the bitmap indices. **The driver source
code must be read** to determine the exact evdev codes.

---

## Other Devices

### RK3399 (Anbernic RG552)
- Vendor:Product: 0x484B:0x0111
- gamecontrollerdb: `a:b1,b:b0,x:b2,y:b3` (A/B swapped)
- Status: NEEDS composite entry for product 0x0111 + ab_swap map

### S922X (ODROID-GO-Ultra, RGB10 MAX 3 Pro)
- Driver: `rocknix-joypad` (base, not singleadc)
- Vendor:Product: 0x484B:0x1000
- gamecontrollerdb: `a:b1,b:b0,x:b3,y:b4` (A/B swapped, BTN_C shifts indices)
- BTN_C registered as function key — shifts SDL indices by +1 after b1
- See `DEVICE-MAPPING-S922X.md` for full analysis
- Status: NEEDS composite entry for product 0x1000 + ab_swap map + BTN_C mapping

### RK3588 (RetrOLED CM5, Retro Lite CM5)
- gamecontrollerdb: `a:b0,b:b1,x:b2,y:b3` (standard, NO swap)
- Uses standard kernel adc-joystick driver
- Status: NEEDS composite entry (vendor/product TBD from gamecontrollerdb GUID)

### SDM845 (AYN Odin)
- gamecontrollerdb: `a:b1,b:b0,lefttrigger:a5,righttrigger:a4` (A/B swapped, analog triggers)
- Custom `odin-gamepad` platform driver
- Status: BLOCKED — needs evdev name/path for InputPlumber matching (no USB vendor/product)

### SM8550 (AYANEO, AYN, Retroid RP6) — DONE
- 11 devices across 3 controller families
- AYANEO (5 devices): Japanese layout, full ABXY swap via `ayaneo_mcu_xbox_japanese` map
- AYN (6 devices): Standard layout, X/Y swap only via `ayn_mcu` map
- Serial MCU init via `020-set-xbox-gamepad` quirk scripts
- See `DEVICE-MAPPING-SM8550.md` for full analysis
- Status: COMPLETE

### SM8650 (AYANEO Pocket S2, KONKR Pocket FIT) — DONE
- 2 devices, AYANEO Standard layout (NO swap, 1:1 map)
- Cap map: `ayaneo_mcu_xbox_standard`
- Same serial MCU protocol as SM8550
- See `DEVICE-MAPPING-SM8650.md` for full analysis
- Status: COMPLETE
