# ADR-006: input_sense Integration with InputPlumber

## Status

Accepted — compatible with minor testing required.

## Context

`input_sense` is the system-wide hotkey daemon in ROCKNIX. It handles volume, brightness,
screenshots, display cycling, suspend, and all modifier-key combos. When InputPlumber hides
raw joypad devices and exposes a virtual Xbox gamepad, input_sense must still function.

## Architecture

```
/dev/input/event0 (gpio-keys: volume, power, lid)
/dev/input/event1 (joypad or InputPlumber virtual Xbox pad)
/dev/input/event2 (touchscreen, if present)
    ↓
input_sense daemon (shell script, systemd: input.service)
    ├── spawns parallel evtest per device
    ├── pipes combined stdout into single while-read loop
    ├── pattern-matches evtest text output (bash case + regex)
    └── dispatches actions (volume, brightness, screenshot, etc.)
```

### Device Discovery

`get_devices()` scans `/dev/input/ev*` via `udevadm info`, matching:
- `ID_INPUT_KEY=1` — keyboards
- `ID_INPUT_JOYSTICK=1` — gamepads
- `ID_INPUT_TOUCHSCREEN=1` — touchscreens

Requires BOTH keyboard AND joystick to be found (retries 5x with 1s delay).

### Event Pattern Matching

Every hotkey is a bash case pattern against evtest text output:

```bash
# Example: evtest output line
# Event: time ..., type 1 (EV_KEY), code 304 (BTN_SOUTH), value 1
# Pattern matches on: *(BTN_SOUTH), value 1*
```

### Complete Hotkey Table

| Combo | Event Pattern | Action |
|-------|--------------|--------|
| Volume Up | `*(KEY_VOLUME*UP), value *` | `volume up` (with repeat) |
| Volume Down | `*(KEY_VOLUME*DOWN), value *` | `volume down` (with repeat) |
| FN_A + Vol Up | modifier + volume | `brightness up` |
| FN_B + Vol Up | modifier + volume | `ledcontrol` |
| FN_A + FN_B + Vol Up | both + volume | `wifictl enable` |
| Power press | `*(KEY_POWER), value 1` | `rocknix-fake-suspend power` |
| Lid close | `*(SW_LID), value 1` | `rocknix-fake-suspend lid close` |
| Lid open | `*(SW_LID), value 0` | `rocknix-fake-suspend lid open` |
| L1 + East | `*(BTN_EAST), value 1` + HOTKEY_A | `rocknix-screenshot` |
| L1 + West | `*(BTN_WEST), value 1` + HOTKEY_A | `mangohud_set toggle` |
| L1 + North | `*(BTN_NORTH), value 1` + HOTKEY_A | `game-guides-tool` |
| L1 + Back | `*(BTN_BACK), value 1` + HOTKEY_A | `screen_switch` |
| L1 + Touch | `*(BTN_TOUCH), value 1` + HOTKEY_A | toggle wvkbd |
| FN_A + D-pad | `*(BTN_DPAD_*), value 1` | volume/brightness |
| FN_A + Hat | `*(ABS_HAT0*), value ±1` | volume/brightness |
| L1 + Select + Start | all three modifiers | `execute_kill` |

### Modifier Keys (device-configurable)

| Modifier | Default | Configured By |
|----------|---------|---------------|
| FN_A | `BTN_SELECT` (RK3566), `BTN_MODE` (S922X, RG-DS) | `DEVICE_FUNC_KEYA_MODIFIER` |
| FN_B | `BTN_START` | `DEVICE_FUNC_KEYB_MODIFIER` |
| HOTKEY_A | `BTN_TL` (L1) | `key.hotkey.a` setting |
| HOTKEY_B | `BTN_SELECT` | `key.hotkey.b` setting |
| HOTKEY_C | `BTN_START` | `key.hotkey.c` setting |

## Compatibility Analysis with InputPlumber

### What Works Without Changes

| Aspect | Why It Works |
|--------|-------------|
| Button events (BTN_SOUTH, BTN_EAST, etc.) | InputPlumber virtual Xbox pad uses same evdev code names |
| Modifier detection (BTN_TL, BTN_SELECT, BTN_START) | Same codes on virtual pad |
| Volume/power/lid events | Come from gpio-keys, NOT joypad — unaffected by InputPlumber |
| D-pad via hat switch (ABS_HAT0X/Y) | input_sense ALREADY handles hat patterns alongside BTN_DPAD_* |
| Device discovery | Virtual pad has `ID_INPUT_JOYSTICK=1` in udev |
| Hot-reload on device change | `99-input.rules` kills input_sense; systemd restarts it |

### Attention Points

**1. HIDE_DEVICES_FROM_ROOT=1 (InputPlumber service env)**

InputPlumber hides raw joypad from all processes including root. input_sense
(running as root) sees only the virtual Xbox pad. This is CORRECT — we want
input_sense reading the normalized virtual device, not the raw hardware.

**2. rocknix-fake-suspend input blocking**

During suspend, `rocknix-fake-suspend` runs `evtest --grab` on all input devices
except a whitelist (power buttons: axp20x-pek, rk805 pwrkey, pmic_pwrkey, gpio-keys).
The virtual Xbox pad WILL be grabbed (blocked) during suspend — correct behavior,
since we don't want gamepad input during sleep.

**3. mkcontroller GUID change**

`mkcontroller` discovers controller GUID via `control-gen` (SDL2). After InputPlumber,
it discovers the virtual pad's GUID (`0300f5a35e040000120b000001000000`) instead of the
raw joypad's. The gamecontrollerdb already has an `InputPlumber GameController` entry
(line 26) so SDL mapping works. mkcontroller's button mapping extraction from
`es_input.cfg` may need an InputPlumber-specific entry.

**4. BTN_TOUCH events**

The L1+BTN_TOUCH combo toggles the virtual keyboard. BTN_TOUCH comes from
touchscreen devices (separate from joypad). InputPlumber does NOT manage
touchscreens → BTN_TOUCH events are unaffected.

**5. BTN_BACK / KEY_RECORD events**

The L1+BTN_BACK combo triggers screen_switch. BTN_BACK (0x116) is registered
on some devices (S922X, Retroid). InputPlumber's virtual Xbox pad may or may not
emit BTN_BACK. If the capability map maps BTN_BACK → QuickAccess2, it will appear
as a different evdev code on the virtual pad. **This needs verification** — the
screen_switch hotkey may need to match the virtual pad's code instead.

## Decision

**No redesign needed.** input_sense is architecturally compatible with InputPlumber
because it pattern-matches evdev code names (not device paths or button indices),
and it already handles both D-pad formats.

**Testing checklist before deployment:**
1. Volume up/down with repeat — works on virtual pad
2. FN_A (Select) + volume = brightness — modifier detected on virtual pad
3. L1 + East = screenshot — combo detected on virtual pad
4. Power button suspend — unaffected (gpio-keys)
5. Lid close/open — unaffected (gpio-keys)
6. L1 + Back = screen_switch — verify BTN_BACK exists on virtual pad
7. Device hotplug — BT controller add triggers reload
8. Suspend input blocking — virtual pad grabbed, power button passes through

## Related

- ADR-001: InputPlumber architecture
- ADR-005: Input source inventory
- Source: `packages/sysutils/system-utils/sources/scripts/input_sense`
- Service: `packages/sysutils/system-utils/system.d/input.service`
- Udev: `packages/sysutils/system-utils/udev.d/99-input.rules`
