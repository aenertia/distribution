# ADR-004: Extended Input Modalities — Touch, Rumble, LEDs, Haptics

## Status

Accepted — inventory complete, integration phases planned.

## Context

Beyond buttons, sticks, and triggers, ROCKNIX devices expose several additional
input/output modalities that InputPlumber can potentially manage:

- **Rumble / Force Feedback** — motor vibration for game feedback
- **Touchscreens** — capacitive touch panels, including dual-screen setups
- **LEDs** — status indicators, RGB rings, analog stick lighting
- **Haptic surfaces** — not present today, but anticipated (Steam Deck-style trackpads)
- **IMU / Motion** — gyroscope + accelerometer (RG-DS only, already handled)

## Hardware Inventory

| Platform | Rumble | Touch | Dual Touch | LEDs | IMU | Haptic |
|----------|--------|-------|------------|------|-----|--------|
| RK3326 | PWM (some) | No | No | No | No | No |
| RK3566 | PWM14 | RG-DS (GT911) | RG-DS (2x) | PWM status (2-3) | RG-DS (ICM-42607P) | No |
| RK3566 ARC | PWM14 | GT911 (1x) | No | PWM status | No | No |
| H700 | No | No | No | GPIO RGB (1) | No | No |
| S922X | PWM | No | No | No | No | No |
| SM8250 | SPMI haptics | FT5452 | No | HTR3212 (12ch) | No | No |
| SM8550 | SPMI haptics | 6 ICs | Thor + PocketDS | 4x RGB + HTR3212 | No | No |
| SM8650 | SPMI haptics | GT911 | No | HTR3212 | No | No |
| SDM845 | FF_RUMBLE | No | No | No | No | No |
| RK3588 | Polldev | GT911 (ACE) | No | No | No | No |

## Rumble / Force Feedback

### Current Implementation

Three distinct rumble mechanisms exist:

**1. PWM Motor (RK3326, RK3566/RK3568, S922X)**
- Kernel: `rocknix-singleadc-joypad` driver with `pwm-names = "enable"` property
- DTS: `rumble-boost-weak`, `rumble-boost-strong` tuning values
- Sysfs: `/sys/class/pwm/pwmchipN/pwm0/{period,duty_cycle,enable}`
- Quirks: `020-gpios` exports PWM channel, sets period (1000000ns), enables
- Runtime: `020-rumble` autostart script in quirks/autostart/

**2. QCOM SPMI Haptics (SM8250, SM8550, SM8650)**
- Kernel: `qcom-spmi-haptics` driver (pmi8998 PMIC)
- Interface: Linux `INPUT_FF_MEMLESS` force-feedback
- Udev: `99-retroid-pocket.rules` tags `pmi8998_haptics` with `FEEDBACKD_TYPE=vibra`
- No PWM sysfs — uses standard evdev force-feedback API

**3. Platform FF_RUMBLE (SDM845)**
- Kernel: `odin-gamepad` driver exposes `FF_RUMBLE` effect type
- Standard evdev force-feedback interface

### InputPlumber Rumble Strategy

InputPlumber's `xbox-series` and `ds5` targets include force-feedback output.
When the virtual gamepad receives an FF_RUMBLE event from an application,
InputPlumber forwards it to the source device.

**For PWM rumble devices:** The joypad kernel driver already handles FF_RUMBLE
via its PWM output. InputPlumber passes through transparently.

**For SPMI haptics:** The haptics driver is a separate evdev device from the
gamepad. It can be added as a source device in the InputPlumber composite config
to route rumble from the virtual gamepad to the haptics hardware.

**No changes needed for Phase 1-3.** Rumble passthrough works automatically
when InputPlumber grabs the source device, because the kernel driver handles
the FF_RUMBLE → PWM/SPMI translation.

## Touchscreens

### Current Implementation

Touchscreens are managed by **libinput + sway**, NOT by InputPlumber:

1. Kernel driver (goodix, focaltech, hynitron, synaptics) creates `/dev/input/eventX`
2. libinput reads touch events
3. sway compositor maps touch to output display
4. `sway-touch.sh` auto-maps touchscreen to focused output
5. `touchcontrol` quirk files apply LIBINPUT_CALIBRATION_MATRIX for dual-screen
6. `runemu.sh` disables secondary touchscreen during emulation

### Touchscreen Controller Inventory

| IC | Manufacturer | Devices | I2C | Resolution |
|----|-------------|---------|-----|------------|
| Goodix GT911 | Goodix | RG-DS (2x), RG ARC-D, AYANEO PocketDS, S2K, PS2, GameForce ACE | 0x14 or 0x5d | 640x480 — 1440x2560 |
| Goodix GT927 | Goodix | RG552 | 0x14 | 1152x1920 |
| Focaltech FT5426 | Focaltech | AYN Thor (2x), Odin 2 Portal, RP6, AYANEO EVO | 0x38 | 1080x1920 |
| Focaltech FT5452 | Focaltech | SM8250 Retroid (4x), AYN Thor secondary | 0x38 | 960x1280 — 1080x1920 |
| Hynitron CST340 | Hynitron | AYN Odin 2 Mini | 0x1a | 1920x1080 |
| Synaptics RMI4 | Synaptics | AYN Odin 2, AYANEO Pocket ACE | I2C | Varies |

### Dual-Screen Touch Configurations

| Device | Primary | Secondary | Calibration |
|--------|---------|-----------|-------------|
| AYN Thor | FT5426 (i2c4) 1080x1920 | FT5452 (i2c_hub_3) 1080x1240 | 60.76% / 39.24% horizontal split |
| Anbernic RG-DS | GT911 (i2c5) 640x480 | GT911 (i2c3) 640x480, X/Y inverted | 50% / 50% width split |
| AYANEO PocketDS | GT911 (i2c2) 768x1024 | FT5426 (i2c4) | TBD |

### InputPlumber Touch Strategy

InputPlumber supports `touchscreen` as both a source device group and target device:

```yaml
# Source touchscreen config (from schema)
- group: touchscreen
  evdev:
    name: "Goodix*"
  config:
    touchscreen:
      orientation: normal | left | right | upsidedown
      width: 640
      height: 480
```

**Current approach:** Touchscreens remain managed by libinput/sway. InputPlumber
does NOT grab touch devices — they are independent input streams.

**Future consideration:** For dual-screen devices, InputPlumber could composite
two touchscreens into a single virtual touchscreen, replacing the udev
LIBINPUT_CALIBRATION_MATRIX approach. This would simplify dual-screen touch
configuration significantly.

## LEDs

### Current Implementation

LEDs are managed by **sysfs + quirk scripts**, NOT by InputPlumber:

**Status LEDs (kernel `pwm-leds` / `gpio-leds`):**
- RK3566: 2-3 PWM LEDs (green=power, amber=charging, red=status)
- H700: 1 GPIO RGB LED (PI7, `LED_FUNCTION_KBD_BACKLIGHT`)
- Controlled via `/sys/class/leds/*/brightness`

**Multi-color RGB LEDs (kernel `pwm-leds-multicolor`):**
- SM8550 AYN: 4x RGB LED groups (left side, left joystick, right side, right joystick)
- Controlled via `/sys/class/leds/*/multi_intensity` + `brightness`

**HTR3212 I2C LED Controller:**
- SM8250 AYANEO, SM8550 AYANEO, SM8650 AYANEO
- 12-channel 8-bit PWM via I2C
- Driver: `leds-htr3212`

**Analog Stick LED Control Scripts:**
- `bin/analog_sticks_ledcontrol` in device quirks
- 7 preset colors: red, green, blue, white, orange, yellow, purple
- Parameters: brightness + right RGB + left RGB
- Devices: AYN Odin 2, Thor, RP6; H700 RG40XX H/V, RG CubeXX

**Battery LED Status Scripts:**
- `bin/battery_led_status` in AYANEO device quirks
- Monitors battery level, updates LED color (orange 30%, red 20%, blink 10%)

### InputPlumber LED Strategy

InputPlumber supports `led` as a source device group:

```yaml
# LED source device config (from schema)
- group: led
  led:
    id: "led0"
    name: "ayn-odin2-*"
  config:
    led:
      fixed_color:
        r: 0
        g: 255
        b: 0
```

**Current approach:** LEDs remain managed by sysfs scripts. InputPlumber does NOT
control LEDs on any current device.

**Future consideration:** InputPlumber could manage LED state as part of the
composite device profile:
- Profile "gaming": joystick LEDs blue, brightness 128
- Profile "charging": LEDs amber/red based on battery
- Profile switch via DBus from runemu.sh

This would unify LED control across devices, replacing per-device shell scripts
with YAML profiles.

## Haptic Surfaces (Future)

No ROCKNIX device currently has a haptic trackpad (Steam Deck-style).

InputPlumber supports `touchpad` as a target device type. When devices with haptic
touchpads are added (likely via future AYANEO or Valve-adjacent hardware):

1. Physical trackpad → InputPlumber `touchscreen` source
2. Capability map translates touch area to gamepad axes
3. `touchpad` target emits touchpad events for applications expecting them
4. Haptic feedback routed via force-feedback API

**Preparation needed:** None. InputPlumber already has the schema support. When
hardware arrives, create a composite device config with touchpad source + target.

## Decision

1. **Rumble:** No InputPlumber changes needed — FF passthrough works automatically
2. **Touch:** Keep libinput/sway management; InputPlumber touch routing is future work
3. **LEDs:** Keep sysfs scripts; InputPlumber LED profiles are future work
4. **Haptics:** Schema ready; no action until hardware exists
5. **IMU:** Already handled (RG-DS IIO composite in Phase 2)

## Related ADRs

- ADR-001: InputPlumber architecture
- ADR-002: Capability map design
- ADR-003: Per-device status
