# ADR-002: Capability Map Design — Button Layout Normalization

## Status

Accepted — critical bugs identified, fixes planned.

## Context

### The BTN_SOUTH / BTN_EAST Problem

The Linux kernel defines face button aliases:
```c
#define BTN_A       BTN_SOUTH   /* 0x130 */
#define BTN_B       BTN_EAST    /* 0x131 */
#define BTN_X       BTN_NORTH   /* 0x133 */
#define BTN_Y       BTN_WEST    /* 0x134 */
```

These follow the **Xbox controller's xpad driver** convention. However, different ROCKNIX
device DTS files assign these codes **inconsistently** to physical buttons:

| Platform | Physical A button | evdev code | Physical B button | evdev code |
|----------|-------------------|------------|-------------------|------------|
| RK3566 | sw5 (bottom) | BTN_SOUTH ✓ | sw6 (right) | BTN_EAST ✓ |
| H700 | sw5 (bottom) | **BTN_EAST** ✗ | sw6 (right) | **BTN_SOUTH** ✗ |
| SM8250 Retroid | MCU byte 7 | **BTN_EAST** ✗ | MCU byte 6 | **BTN_SOUTH** ✗ |
| RK3326 (most) | varies | **BTN_EAST** ✗ | varies | **BTN_SOUTH** ✗ |
| RK3326 (G350) | sw5 | BTN_SOUTH ✓ | sw6 | BTN_EAST ✓ |

The existing `gamecontrollerdb.txt` compensates for each device:
- RK3566 retrogame_joypad: `a:b0` (b0=BTN_SOUTH) — standard
- H700 Gamepad: `a:b1` (b1=BTN_EAST) — compensated
- Retroid Pocket: `a:b1` (b1=BTN_EAST) — compensated

### The InputPlumber Virtual Gamepad

InputPlumber's xbox-series target creates a virtual controller with a fixed mapping
(from `gamecontrollerdb.txt` line 26):
```
InputPlumber GameController: a:b0, b:b1, x:b2, y:b3
```
Where b0=BTN_SOUTH, b1=BTN_EAST, b2=BTN_NORTH, b3=BTN_WEST.

This means: **the capability map must ensure that the physical A button always produces
BTN_SOUTH on the virtual gamepad**, regardless of what evdev code the source device uses.

## Decision

### Three Capability Map Categories

**Category 1: Standard (1:1)** — `retrogame_joypad`
- BTN_SOUTH → South, BTN_EAST → East (no swap)
- Used by: RK3566 retrogame_joypad, BatleXP G350, RG ARC

**Category 2: A/B Swap** — `retrogame_joypad_ab_swap`
- BTN_SOUTH → **East**, BTN_EAST → **South** (swap A↔B)
- BTN_NORTH → North, BTN_WEST → West (no X/Y swap)
- Used by: Most RK3326 singleadc devices, RK3399 RG552, Retroid Pocket

**Category 3: H700** — `h700_gamepad`
- BTN_SOUTH → **East**, BTN_EAST → **South** (swap A↔B)
- BTN_NORTH → North, BTN_WEST → West (no X/Y swap)
- Structurally identical to Category 2, but kept separate for clarity and
  because H700 has different deadzone/tuning characteristics

### Trigger Axis Mapping

| Driver | Left Trigger | Right Trigger | Type |
|--------|-------------|---------------|------|
| rocknix-singleadc-joypad | BTN_TL2 | BTN_TR2 | Digital (button) |
| retroid-pocket-gamepad | **ABS_HAT2X** | **ABS_HAT2Y** | Analog (axis) |
| AYN MCU (SM8550) | ABS_Z / ABS_RZ | ABS_Z / ABS_RZ | Analog (axis) |

**Critical bug found:** The current `retroid_pocket_gamepad.yaml` maps ABS_Z/ABS_RZ as
triggers, but the Retroid driver uses ABS_HAT2X/ABS_HAT2Y. ABS_Z and ABS_RZ are the
Z-axes of the analog sticks (third axis), not the triggers.

## Consequences

- Each device family needs a composite device config referencing the correct capability map
- The gamecontrollerdb.txt already has an InputPlumber entry — no SDL-level changes needed
- X/Y buttons use 1:1 mapping on all devices (BTN_NORTH→North, BTN_WEST→West) because
  the kernel aliases BTN_X=BTN_NORTH and BTN_Y=BTN_WEST consistently across all platforms
- H700 X/Y behavior changes from position-based to label-based mapping (consistent with RK3566)

## Verification Matrix

For each device, verify: Physical button press → correct SDL action

| Test | Expected |
|------|----------|
| Press physical A | SDL GameControllerGetButton returns SDL_CONTROLLER_BUTTON_A |
| Press physical B | SDL GameControllerGetButton returns SDL_CONTROLLER_BUTTON_B |
| Press physical L2 | SDL GameControllerGetAxis returns SDL_CONTROLLER_AXIS_TRIGGERLEFT > 0 |
| Press physical R2 | SDL GameControllerGetAxis returns SDL_CONTROLLER_AXIS_TRIGGERRIGHT > 0 |
