# InputPlumber Implementation Plan

## Overview

Phased migration from fragmented per-device input handling to unified InputPlumber routing.
See ADR-001 through ADR-003 for architecture decisions and per-device status.

---

## Phase 1: Core Infrastructure (DONE — commit 87459b8bbc)

- [x] Add `inputplumber` to ADDITIONAL_PACKAGES for all 10 device targets
- [x] Update `package.mk` to install shared configs from sources/
- [x] Create `retrogame_joypad` capability map (1:1, for RK3566)
- [x] Create `retroid_pocket_gamepad` capability map (has bugs — see Phase 2)
- [x] Create `50-retrogame-joypad.yaml` composite config (484b:1101, 484b:1121)
- [x] Create `50-retroid-pocket-gamepad.yaml` composite config (2020:3001)
- [x] Create `01-anbernic-rg-ds.yaml` (RG-DS joypad + IMU composite, ds5 target)
- [x] Add InputPlumber DBus helpers to runemu.sh
- [x] Enable CONFIG_HID_BPF=y on all 7.0-rc4 kernels
- [x] Enable CONFIG_BPF_JIT=y on S922X

## Phase 2: Fix Critical Bugs

### 2a: Fix SM8250 Retroid Trigger Mapping (CRITICAL)

The current `retroid_pocket_gamepad.yaml` maps triggers to the wrong evdev axes.
L2/R2 are completely non-functional.

**File:** `packages/tools/inputplumber/sources/usr/share/inputplumber/capability_maps/retroid_pocket_gamepad.yaml`

| Change | From | To |
|--------|------|-----|
| Left Trigger source | ABS_Z (stick Z-axis) | ABS_HAT2X (actual trigger) |
| Right Trigger source | ABS_RZ (stick Z-axis) | ABS_HAT2Y (actual trigger) |
| BTN_SOUTH target | South | **East** (A/B swap) |
| BTN_EAST target | East | **South** (A/B swap) |

### 2b: Create H700 Capability Map + Composite Config

H700 devices are completely unmanaged — product 0x14DF not matched.

**New files:**
1. `capability_maps/h700_gamepad.yaml` — swap BTN_SOUTH↔BTN_EAST
2. `devices/50-h700-gamepad.yaml` — match vendor 484b, product 14df

**Capability map h700_gamepad:**
```yaml
mapping:
  - BTN_SOUTH → East    # Physical B → Xbox B
  - BTN_EAST  → South   # Physical A → Xbox A
  - BTN_NORTH → North   # Physical X → Xbox X (no swap)
  - BTN_WEST  → West    # Physical Y → Xbox Y (no swap)
  # All other mappings identical to retrogame_joypad
```

### 2c: Create A/B-Swap Capability Map for Remaining Devices

Many RK3326 singleadc devices and the RK3399 RG552 have swapped A/B but use
different product IDs not currently matched.

**New file:** `capability_maps/retrogame_joypad_ab_swap.yaml`
- Identical to `retrogame_joypad.yaml` except BTN_SOUTH↔BTN_EAST targets swapped

**Update:** `devices/50-retrogame-joypad.yaml` — add source_device entries:

| Vendor | Product | Name | Capability Map |
|--------|---------|------|---------------|
| 484b | 1211 | retrogame_joypad_s1_f2 | retrogame_joypad_ab_swap |
| 484b | 1177 | RGB20S Gamepad | retrogame_joypad_ab_swap |
| 484b | 0111 | rg552_joypad | retrogame_joypad_ab_swap |
| 0001 | 0aa2 | r33s_joypad | retrogame_joypad_ab_swap |
| 0001 | 1188 | r36s_Gamepad | retrogame_joypad_ab_swap |

## Phase 3: RK3326 Legacy Drivers

**Prerequisite:** Read kernel driver source from `packages/linux-drivers/rocknix-joypad/`
to determine exact evdev codes for each driver variant.

### 3a: Analyze Driver Sources

Read and document the evdev output for:
1. `odroidgo2-joypad` — used by OGA, RG351M, RG351V
2. `odroidgo2-v11-joypad` — used by OGA-BE, RGB10
3. `odroidgo3-joypad` — used by OGS
4. `xu10-joypad` — used by XU10, XU Mini M (completely unique layout)

For each driver, determine:
- What KEY events are registered (BTN_SOUTH, BTN_EAST, or different codes?)
- What ABS events are registered (same as singleadc?)
- The vendor_id and product_id set in the driver
- Whether the button bitmap ordering matches gamecontrollerdb indices

### 3b: Create Per-Driver Capability Maps

Based on analysis, create:
- `odroidgo2_joypad.yaml` capability map
- `odroidgo2_v11_joypad.yaml` capability map
- `odroidgo3_joypad.yaml` capability map
- `xu10_joypad.yaml` capability map
- `xu_mini_m_joypad.yaml` capability map (if different from xu10)

### 3c: Create Composite Device Entries

Add to `50-retrogame-joypad.yaml` or create separate composite configs:
- `0226:0001` → odroidgo2_joypad map
- `dea8:0002` → odroidgo2_v11_joypad map
- `c3ea:0001` → odroidgo3_joypad map
- `c3b0:0200` → xu10_joypad map
- `c3bb:0200` → xu_mini_m_joypad map

### 3d: Handle Special Cases

- **GameForce Chi:** Uses standard kernel `adc-joystick` + `adc-keys` drivers.
  Need to determine vendor/product or use name matching.
- **GameForce ACE:** Has analog triggers on negative ABS_Z/ABS_RZ axes (`-a2/-a5`
  in gamecontrollerdb). May need special trigger handling.
- **RG ARC:** Vendor 0x0001, product 0x0A2C. Non-standard x:b4 (gap in button bitmap).

## Phase 4: Deprecate oga_controls

**After validation** that InputPlumber correctly handles all RK3326 and S922X devices:

1. Remove `oga_controls` from package dependencies
2. Remove per-platform patches (`patches/RK3326/`, `patches/S922X/`)
3. InputPlumber's virtual keyboard + mouse targets replace oga_controls functionality

## Phase 5: SDM845 / S922X Configs

These devices use unique kernel drivers without standard USB vendor/product IDs:

- **SDM845 AYN Odin:** `odin-gamepad` platform driver. Match by evdev name
  "AYN Odin Gamepad" or phys_path. Analog triggers on ABS axes.
- **S922X GO-Ultra:** Different button index layout (x:b3, y:b4, guide:b11).
  Needs driver source analysis.

## Phase 6: HID-BPF Device Fixes

CONFIG_HID_BPF=y is enabled. Future work:
- Create `udev-hid-bpf` package for deploying BPF-based HID quirk fixes
- Lower latency than userspace for dead zone, axis inversion, report descriptor fixes
- Complementary to InputPlumber (fixes happen at HID layer, before evdev)

## Phase 7: RG-ARC 6-Button Capability Map

The RG ARC-D/S uses a 6-button layout (A,B,C,X,Y,Z) with BTN_C (0x132) and BTN_Z (0x135)
as extra face buttons. These shift SDL button indices and require a unique capability map.

- Create `rg_arc_joypad.yaml` capability map:
  - BTN_A/BTN_SOUTH → South (no swap — a:b0 in gamecontrollerdb)
  - BTN_B/BTN_EAST → East
  - BTN_C → RightPaddle1 (extra face button, mapped to paddle)
  - BTN_X/BTN_NORTH → North
  - BTN_Y/BTN_WEST → West
  - BTN_Z → LeftPaddle1 (extra face button, mapped to paddle)
- Create composite entry for vendor 0x0001, product 0x0A2C
- Also has single Goodix GT911 touchscreen (i2c3 @ 0x14, 640x480, X-Y swapped)

## Phase 8: Extended Modality Integration (Future)

### Touch Routing via InputPlumber
For dual-screen devices (RG-DS, AYN Thor, AYANEO PocketDS):
- InputPlumber `touchscreen` source group can composite two touch panels
- Replace udev LIBINPUT_CALIBRATION_MATRIX with InputPlumber orientation/width/height config
- Simplify dual-screen touch mapping

### LED Profile Integration
For AYN/AYANEO/H700 devices with RGB LEDs:
- InputPlumber `led` source group can manage LED state via YAML profiles
- Per-profile LED colors (e.g., "gaming" = blue, "charging" = amber)
- Replace per-device shell scripts with unified InputPlumber profiles
- Runtime LED switching via DBus from runemu.sh

### Haptic Surface Readiness
No ROCKNIX device currently has haptic trackpads (Steam Deck-style).
InputPlumber supports `touchpad` as both source and target device type.
When hardware arrives:
- Create composite config with touchpad source
- Map touch area to gamepad axes or mouse movement
- Route haptic feedback via FF API

See ADR-004 for full modality inventory and strategy.

---

## File Inventory

### Existing (created in Phase 1)
```
packages/tools/inputplumber/
├── package.mk                          # Updated: rsync sources/
└── sources/usr/
    ├── lib/systemd/system/inputplumber.service
    └── share/inputplumber/
        ├── capability_maps/
        │   ├── retrogame_joypad.yaml       # 1:1 map (RK3566) ✓
        │   └── retroid_pocket_gamepad.yaml  # BUG: wrong triggers + A/B
        └── devices/
            ├── 50-retrogame-joypad.yaml     # 484b:1101/1121 ✓
            └── 50-retroid-pocket-gamepad.yaml # 2020:3001 ✓

devices/RK3566/filesystem/usr/share/inputplumber/devices/
└── 01-anbernic-rg-ds.yaml                  # RG-DS joypad+IMU ✓
```

### To Create (Phase 2)
```
packages/tools/inputplumber/sources/usr/share/inputplumber/
├── capability_maps/
│   ├── h700_gamepad.yaml                    # A/B swap for H700
│   └── retrogame_joypad_ab_swap.yaml        # A/B swap for RK3326/RK3399
└── devices/
    └── 50-h700-gamepad.yaml                 # 484b:14df composite
```

### To Create (Phase 3)
```
packages/tools/inputplumber/sources/usr/share/inputplumber/
├── capability_maps/
│   ├── odroidgo2_joypad.yaml
│   ├── odroidgo2_v11_joypad.yaml
│   ├── odroidgo3_joypad.yaml
│   ├── xu10_joypad.yaml
│   └── xu_mini_m_joypad.yaml
└── devices/
    └── (entries added to 50-retrogame-joypad.yaml or new files)
```

### To Create (Phase 7)
```
packages/tools/inputplumber/sources/usr/share/inputplumber/
├── capability_maps/
│   └── rg_arc_joypad.yaml              # 6-button A/B/C/X/Y/Z for RG ARC
└── devices/
    └── (entry for 0001:0a2c)
```

---

## Testing Checklist

### Per-Device Validation
For each device, after InputPlumber is enabled:

- [ ] InputPlumber service starts (`systemctl status inputplumber`)
- [ ] Virtual gamepad created (`busctl tree org.shadowblip.InputPlumber`)
- [ ] Source device hidden (`ls /dev/input/by-id/` — no retrogame_joypad)
- [ ] ES navigation works (A=confirm, B=back)
- [ ] RetroArch input works (correct button mapping in-game)
- [ ] D-pad, sticks, all buttons functional
- [ ] L2/R2 triggers functional (analog on SM8250, digital on RK3566/H700/RK3326)
- [ ] Hotplug: connect BT controller → second virtual pad appears
- [ ] PortMaster ports still work (gptokeyb coexistence)
- [ ] No latency regression vs direct evdev

### Regression Checks
- [ ] PWM rumble still works (sysfs-based, not evdev — should be unaffected)
- [ ] Sleep/wake input detection works (systemd hwdb marks joypad for wake)
- [ ] gamepadcalibration (GPcal) still works on SM8250
- [ ] Screen-switch hotkeys still work (ES guide+L1/R1)
