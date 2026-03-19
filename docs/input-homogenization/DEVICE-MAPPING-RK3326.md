# RK3326 Input Mapping: Current State → Target State

## Platform Summary

| Property | Value |
|----------|-------|
| SoC | Rockchip RK3326 (PX30) |
| Kernel drivers | **6 distinct drivers** (see below) |
| Joypad package | `rocknix-joypad` (contains all driver variants) |
| A/B swap | **Most devices YES**, a few NO |

## The RK3326 Complexity

Unlike RK3566 (one driver, one layout), RK3326 has **6 different joypad kernel drivers**
inherited from ODROID-GO and various vendor implementations. Each has different:
- Vendor/product IDs
- Button-to-evdev-code mappings
- SDL gamecontrollerdb button index ordering
- Some have analog triggers, some digital

Additionally, `oga_controls` daemon runs on RK3326 for keyboard/mouse emulation.

## Driver Inventory

### Driver 1: odroidgo2-joypad

| Property | Value |
|----------|-------|
| Compatible | `odroidgo2-joypad` |
| Vendor:Product | 0x0226:0x0001 |
| GUID | `19000226010000000100000001010000` |
| gamecontrollerdb | `a:b1,b:b0,x:b2,y:b3,dpup:b6,dpdown:b7` |
| A/B swap | **Yes** |
| Unique traits | D-pad at b6-b9 (vs b13-b16 for singleadc), no guide button |

**Devices:** ODROID-GO Advance, Anbernic RG351M, Anbernic RG351V

**gamecontrollerdb entry:**
```
a:b1,b:b0,x:b2,y:b3,back:b10,start:b13,dpleft:b8,dpdown:b7,dpright:b9,dpup:b6,
leftshoulder:b4,lefttrigger:b11,rightshoulder:b5,righttrigger:b12,leftx:a0,lefty:a1
```

**Note:** Button indices differ significantly from singleadc (dpup at b6 vs b13).
This implies the driver registers additional KEY codes between BTN_WEST and BTN_DPAD_UP,
or uses entirely different event codes. **Driver source analysis required** before creating
the capability map.

### Driver 2: odroidgo2-v11-joypad

| Property | Value |
|----------|-------|
| Compatible | `odroidgo2-v11-joypad` |
| Vendor:Product | 0xDEA8:0x0002 |
| GUID | `1900dea8010000000200000001010000` |
| gamecontrollerdb | `a:b1,b:b0,x:b2,y:b3` |
| A/B swap | **Yes** |
| Unique traits | Has thumb sticks (b10, b11), different from v10 |

**Devices:** ODROID-GO Advance Black Edition, Powkiddy RGB10

**gamecontrollerdb entry:**
```
a:b1,b:b0,x:b2,y:b3,back:b8,start:b9,dpleft:b14,dpdown:b13,dpright:b15,dpup:b12,
leftshoulder:b4,lefttrigger:b6,rightshoulder:b5,righttrigger:b7,leftstick:b10,rightstick:b11,
leftx:a0,lefty:a1
```

### Driver 3: odroidgo3-joypad

| Property | Value |
|----------|-------|
| Compatible | `odroidgo3-joypad` |
| Vendor:Product | 0xC3EA:0x0001 |
| GUID | `1900c3ea010000000100000001010000` |
| gamecontrollerdb | `a:b1,b:b0,x:b2,y:b3` |
| A/B swap | **Yes** |
| Unique traits | Dual analog sticks, signed axis notation in gamecontrollerdb |

**Devices:** ODROID-GO Super

**gamecontrollerdb entry:**
```
a:b1,b:b0,dpdown:b13,dpleft:b14,+lefty:+a1,-leftx:-a0,+leftx:+a0,-lefty:-a1,
leftshoulder:b4,leftstick:b10,lefttrigger:b6,dpright:b15,+righty:+a3,-rightx:-a2,
+rightx:+a2,-righty:-a3,rightshoulder:b5,rightstick:b11,righttrigger:b7,back:b8,
start:b9,dpup:b12,x:b2,y:b3
```

### Driver 4: rocknix-singleadc-joypad (on RK3326)

Same driver as RK3566, but with different DTS configurations per device, resulting in
different device names and product IDs.

| Device | Vendor:Product | Name | A/B | gamecontrollerdb |
|--------|---------------|------|-----|------------------|
| BatleXP G350 | 484B:1101 | retrogame_joypad | **No** | a:b0,b:b1 |
| RGB10X | 484B:1211 | retrogame_joypad_s1_f2 | **Yes** | a:b1,b:b0 |
| RGB20S | 484B:1177 | RGB20S Gamepad | **Yes** | a:b1,b:b0 |
| R33S | 0001:0AA2 | r33s_joypad | **Yes** | a:b1,b:b0 |
| R36S | 0001:1188 | r36s_Gamepad | **Yes** | a:b1,b:b0 |
| EE clone | (TBD) | (TBD) | (TBD) | (TBD) |

**Status:**
- G350 (484B:1101): Already matched by existing config ✓
- Others: Need composite entries + ab_swap capability map

### Driver 5: xu10-joypad

| Property | Value |
|----------|-------|
| Vendor:Product (XU10) | 0xC3B0:0x0200 |
| Vendor:Product (XU Mini M) | 0xC3BB:0x0200 |

**XU10 gamecontrollerdb (UNIQUE LAYOUT):**
```
x:b3,a:b2,b:b1,y:b0,back:b8,guide:b16,start:b9,dpleft:b14,dpdown:b13,dpright:b15,
dpup:b12,leftshoulder:b4,lefttrigger:b7,rightshoulder:b5,righttrigger:b6,leftstick:b10,
rightstick:b11,leftx:a0,lefty:a1,rightx:a2,righty:a3
```
- `a:b2` = BTN_NORTH is the A button (!)
- `y:b0` = BTN_SOUTH is the Y button (!)
- `lefttrigger:b7, righttrigger:b6` = triggers swapped (!)
- This is a **completely unique mapping** unlike any other device.

**XU Mini M gamecontrollerdb (different from XU10!):**
```
x:b2,a:b1,b:b0,y:b3,back:b8,guide:b16,start:b9,...
lefttrigger:b6,righttrigger:b7,...
```
- Standard A/B swap (`a:b1,b:b0`)
- Triggers NOT swapped (unlike XU10)

### Driver 6: adc-joystick + adc-keys (GameForce Chi)

Uses the standard Linux `adc-joystick` driver (not ROCKNIX-specific) combined with
`adc-keys` for buttons. Completely different architecture from all other joypad drivers.

**Status:** Needs separate investigation. The standard adc-joystick driver may use
different evdev codes and capability registration.

### Special: GameForce ACE

| Property | Value |
|----------|-------|
| GUID | `03001a3447616d65466f726365204100` |
| gamecontrollerdb | `a:b1,b:b0,x:b3,y:b4` |
| A/B swap | **Yes** |
| Triggers | **Analog, negative axis:** `lefttrigger:-a2, righttrigger:-a5` |

**Note:** X is at b3 (not b2), Y is at b4 (not b3). Triggers use negative axis values
(`-a2` means ABS_Z negative direction). This is unique and needs a custom capability map
with trigger axis direction handling.

## Current Input Flow (without InputPlumber)

```
GPIO/ADC Hardware (RK3326 SARADC + GPIO)
    ↓
One of 6 kernel drivers (device-specific)
    ↓
/dev/input/eventX (device-specific name and vendor:product)
    ↓
SDL2 (gamecontrollerdb.txt — per-device entry compensates for layout)
    ↓
oga_controls (optional — keyboard/mouse emulation from joypad)
    device path: /dev/input/by-path/platform-*-joypad-event-joystick
    ↓
EmulationStation / RetroArch / Standalones
    RetroArch: per-device joypad cfg files
    Flycast: per-device SDL mappings in config/RK3326/mappings/
```

### Supporting Files (current)

| File | Purpose |
|------|---------|
| `gamecontrollerdb/config/gamecontrollerdb.txt` lines 3-4,7-13,17 | 10+ SDL entries |
| `retroarch-joypads/gamepads/retrogame_joypad.cfg` | singleadc RetroArch config |
| `retroarch-joypads/gamepads/retrogame_joypad_s1_f2.cfg` | s1_f2 variant |
| `retroarch-joypads/gamepads/odroidgo2_joypad.cfg` | OGA RetroArch config |
| `retroarch-joypads/gamepads/odroidgo2_v11_joypad.cfg` | OGA-v11 config |
| `retroarch-joypads/gamepads/odroidgo3_joypad.cfg` | OGS config |
| `retroarch-joypads/gamepads/r33s_joypad.cfg` | R33S config |
| `oga_controls/patches/RK3326/000-platform.patch` | Platform-specific paths |
| `quirks/platforms/RK3326/050-modifiers` | BTN_SELECT/BTN_START modifiers |
| Various `quirks/devices/*/050-modifiers` | Per-device overrides |
| `flycast-sa/config/RK3326/mappings/SDL_*.cfg` | Per-device Flycast mappings |

## Target Input Flow (with InputPlumber)

```
GPIO/ADC Hardware
    ↓
Kernel driver (one of 6 variants)
    ↓
/dev/input/eventX (GRABBED — hidden from apps)
    ↓
InputPlumber daemon
    Config: device-specific composite config
    Cap map: driver-specific capability map (with A/B swap where needed)
    ↓
Virtual Xbox Series Gamepad (/dev/input/eventY)
    ↓
SDL2: InputPlumber GameController (standard Xbox mapping)
    ↓
EmulationStation / RetroArch / Standalones
    ↓
oga_controls: BYPASSED (InputPlumber creates virtual keyboard/mouse targets)
```

## Implementation Status by Device

### Can Fix Now (singleadc devices with known product IDs)

| Device | Vendor:Product | Cap Map | Composite | Status |
|--------|---------------|---------|-----------|--------|
| BatleXP G350 | 484B:1101 | retrogame_joypad | 50-retrogame-joypad | ✓ DONE |
| RGB10X | 484B:1211 | retrogame_joypad_ab_swap | needs entry | TODO |
| RGB20S | 484B:1177 | retrogame_joypad_ab_swap | needs entry | TODO |
| R33S | 0001:0AA2 | retrogame_joypad_ab_swap | needs entry | TODO |
| R36S | 0001:1188 | retrogame_joypad_ab_swap | needs entry | TODO |

### Blocked (need driver source analysis)

| Device | Driver | Vendor:Product | Blocker |
|--------|--------|---------------|---------|
| OGA | odroidgo2 | 0226:0001 | Unknown evdev codes |
| OGA-BE | odroidgo2-v11 | DEA8:0002 | Unknown evdev codes |
| RG351M/V | odroidgo2 | 0226:0001 | Unknown evdev codes |
| RGB10 | odroidgo2-v11 | DEA8:0002 | Unknown evdev codes |
| OGS | odroidgo3 | C3EA:0001 | Unknown evdev codes |
| XU10 | xu10 | C3B0:0200 | Completely unique layout |
| XU Mini M | xu10 variant | C3BB:0200 | Unknown evdev codes |
| GameForce Chi | adc-joystick | ??? | Different driver architecture |
| GameForce ACE | ??? | ??? | Negative-axis analog triggers |
| EE clone | singleadc? | ??? | Unknown |

## Next Steps

1. **Phase 2c:** Create `retrogame_joypad_ab_swap.yaml` and add composite entries
   for the "Can Fix Now" devices above.
2. **Phase 3a:** Read kernel driver sources from `packages/linux-drivers/rocknix-joypad/`
   to determine evdev codes for odroidgo2, odroidgo2-v11, odroidgo3, xu10 drivers.
3. **Phase 3b:** Create per-driver capability maps based on analysis.
4. **Phase 4:** Once all devices validated, deprecate `oga_controls`.

**Status: PARTIAL — singleadc devices can be fixed now, legacy drivers blocked on
driver source analysis.**
