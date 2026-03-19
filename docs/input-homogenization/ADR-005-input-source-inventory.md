# ADR-005: Complete Input Source Inventory for Unified Driver Refactor

## Status

Research complete — informs unified driver scope.

## Context

Before refactoring the 10 joypad driver codebases into a unified `rocknix-joypad.c`,
we need to understand every input source, consumer, and interceptor in the system to
avoid breaking non-gamepad input paths.

## Input Sources That Stay OUTSIDE the Unified Driver

### gpio-keys (Volume, Power, Lid — Separate Kernel Driver)

Every device has a separate `gpio-keys` driver instance. These produce:
- `KEY_VOLUMEUP` / `KEY_VOLUMEDOWN` — volume control
- `KEY_POWER` — suspend trigger
- `SW_LID` — RG-DS clamshell hall sensor
- `SW_HEADPHONE_INSERT` — some devices

These are independent evdev devices. InputPlumber must NOT grab them.
The `input_sense` daemon reads them for system hotkeys.

### HID Controllers (Bluetooth + USB)

External controllers use the standard kernel HID stack (19 modules as =m):
- Xbox (`CONFIG_JOYSTICK_XPAD`, `CONFIG_HID_MICROSOFT`)
- PlayStation (`CONFIG_HID_SONY`)
- Nintendo Switch Pro (`CONFIG_HID_NINTENDO`)
- Steam Controller (`CONFIG_HID_STEAM`)
- 8BitDo, OUYA, etc. via udev rules

InputPlumber can optionally manage these via HID device matching.
HID-BPF can fix broken descriptors at the HID layer.

### Touchscreens (libinput + sway)

6 touchscreen controller ICs across 7 platforms (Goodix GT911/GT927, Focaltech
FT5426/FT5452, Hynitron CST340, Synaptics RMI4). Managed by libinput + sway
compositor, not by InputPlumber or the joypad driver.

### AYANEO MCU Switching (Userspace)

SM8550/SM8650 AYANEO devices switch MCU to Xbox 360 mode via userspace serial
commands (`020-set-xbox-gamepad` quirk script). After switching, the MCU presents
as standard HID. This stays as a boot quirk.

### RK3588 adc-joystick (Standard Kernel Driver)

RK3588 devices use the stock kernel `adc-joystick` driver, not rocknix-joypad.
Leave as-is; InputPlumber handles normalization.

## Input Consumers That Must Be Validated

### input_sense — HIGHEST RISK

The central event dispatcher shell daemon. Runs parallel `evtest` processes on
ALL `/dev/input/ev*` devices. Detects button combos for:

| Combo | Action |
|-------|--------|
| KEY_VOLUMEUP/DOWN | Volume (with repeat) |
| KEY_POWER | Fake suspend |
| SW_LID | Fake suspend (RG-DS) |
| L1 (BTN_TL) + BTN_EAST | Screenshot |
| L1 + BTN_WEST | MangoHud toggle |
| L1 + BTN_NORTH | Game guide |
| L1 + BTN_TOUCH | Virtual keyboard toggle |
| L1 + BTN_BACK/KEY_RECORD | Screen switch |
| Modifier combos | Brightness, WiFi, LED control |

**CRITICAL:** When InputPlumber hides the raw joypad, input_sense loses direct
access to gamepad events. It must read from the virtual Xbox pad instead. Key risks:
1. D-pad changes from `BTN_DPAD_*` buttons to `ABS_HAT0X/HAT0Y` hat switch
2. Button event codes may differ (BTN_SOUTH vs virtual pad's BTN_SOUTH)
3. `evtest` output format for hat switches differs from button events

### gptokeyb / inputfilter.so

LD_PRELOAD input interception for PortMaster ports. Reads evdev devices directly.
When InputPlumber hides the raw joypad, gptokeyb sees the virtual Xbox pad.
The `.gptk` config files map by button names — **likely works but needs testing**.

### Per-Emulator Input Configs

These reference device names that change under InputPlumber:

| Emulator | Config Location | Device Name Referenced |
|----------|----------------|----------------------|
| Flycast | `config/{DEVICE}/mappings/SDL_*.cfg` | "Retroid Pocket Gamepad", "GO-Ultra Gamepad", etc. |
| Mupen64Plus | `config/{DEVICE}/mupen64plus.cfg` | [Retroid Pocket Gamepad] section |
| RPCS3 | `config/{DEVICE}/input_configs/global/Default.yml` | "Retroid Pocket Gamepad 1" |
| Dolphin | `config/{DEVICE}/.../GCPadNew.ini.*` | "Microsoft X-Box 360 pad" |
| Cemu | `config/{DEVICE}/.../wii_u_gamepad.xml` | UUID `0_0300f5a3...` |
| DrasticDS | `config/{DEVICE}/drastic.cfg.*` | Device-specific |

After InputPlumber: device name becomes "InputPlumber GameController" with UUID
`0300f5a35e040000120b000001000000`. Emulators using SDL gamecontrollerdb will
auto-detect; those with hardcoded device names need config updates.

### RetroArch

Uses `input_driver = "udev"` on all platforms. Per-device joypad autoconfig files
in `retroarch-joypads/gamepads/*.cfg` become unnecessary — one config for the
InputPlumber virtual pad. The existing `InputPlumber GameController` entry in
gamecontrollerdb (line 26) handles SDL mapping.

### systemd hwdb

`20-joypad.hwdb` matches `evdev:name:*joypad*` and `evdev:name:*Gamepad*` to set
`ID_INPUT_TABLET=1`. The pattern `*Gamepad*` matches "InputPlumber GameController"
but `*joypad*` does not. May need a pattern update for InputPlumber devices.

## Unified Driver Scope

### IN scope (rocknix-joypad.c):

| Transport | Source | Devices |
|-----------|--------|---------|
| Platform (GPIO+ADC) | GPIO buttons + IIO multi-channel | S922X |
| Platform (GPIO+mux ADC) | GPIO buttons + single ADC + analog mux | RK3566, RK3568, H700, RK3399 |
| Platform (GPIO+ADC) | GPIO buttons + per-channel SARADC | RK3326 (all 6 legacy variants) |
| Platform (GPIO+ADC) | GPIO buttons + PMIC ADC | SDM845 (AYN Odin) |
| Platform (Miyoo serial) | GPIO buttons + /dev/ttyS1 sticks | H700 (serial analog) |
| Serdev (UART MCU) | Binary protocol over UART16 | SM8250 (Retroid Pocket) |
| Platform (PWM FF) | Optional PWM rumble | RK3566, RK3326, S922X |

### OUT of scope:

| Component | Reason |
|-----------|--------|
| gpio-keys | Separate kernel driver for volume/power/lid |
| HID controllers (BT/USB) | Standard kernel HID stack + HID-BPF |
| Touchscreens | libinput + sway compositor |
| AYANEO MCU switching | Userspace quirk script |
| AYN rsinput (SM8550) | Vendor HID driver |
| RK3588 adc-joystick | Standard kernel driver |

## Decision

The unified driver handles ALL platform-based internal gamepads plus the Retroid
serdev path. Everything else stays in its existing subsystem. The `input_sense`
daemon is the highest-risk consumer and must be validated against InputPlumber's
virtual device output before any refactor ships.

## Related

- ADR-001: InputPlumber architecture
- ADR-002: Capability map design
- ADR-003: Per-device status
- ADR-004: Extended input modalities
