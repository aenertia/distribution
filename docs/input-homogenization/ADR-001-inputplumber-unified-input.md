# ADR-001: InputPlumber as Unified Input Router for All Devices

## Status

Accepted — implementation in progress on `input-homogenization` branch.

## Context

ROCKNIX has accumulated a fragmented input stack across 45+ device variants:

| Component | Role | Scope |
|-----------|------|-------|
| `rocknix-joypad` | Kernel module (6 driver variants) | RK3326, RK3566, RK3568, RK3399, S922X, H700 |
| `oga_controls` | C daemon for keyboard/mouse emulation | RK3326, S922X only |
| `gptokeyb` (rocknix-hotkey) | Gamepad-to-keyboard mapper | PortMaster ports, standalones |
| `gamecontrollerdb` | SDL controller mapping database | All devices (24 custom entries) |
| `retroarch-joypads` | RetroArch autoconfig profiles | All devices |
| `control-gen` / `list-guid` | Controller discovery | All devices |
| `100-gamecontroller-functions` | Nintendo/Xbox layout transforms | All devices |
| Per-device quirk scripts | GPIO, PWM rumble, modifiers | 50+ quirk directories |

This creates maintenance burden: each new device requires C patches, DTS modifications, gamecontrollerdb entries, RetroArch joypad configs, and quirk scripts. Button layout differences (Nintendo vs Xbox) are handled inconsistently across the stack.

## Decision

Adopt **InputPlumber** (v0.75.2) as the unified input routing daemon for all device targets.

InputPlumber is a Rust-based evdev/uinput/hidraw userspace daemon that:
- Reads N physical input devices (evdev, hidraw, IIO)
- Applies YAML capability maps to normalize events
- Creates virtual composite gamepad(s) via uinput
- Hides source devices from applications
- Supports runtime profile switching via DBus

### Why InputPlumber over alternatives

- **Already in ROCKNIX** for SM8550/SM8650 (Qualcomm devices)
- **YAML config** replaces per-device C patches and scripts
- **Composite device** model — multiple physical inputs → one clean virtual gamepad
- **IIO integration** — gyro/accel compositing for RG-DS IMU
- **DBus API** — runtime profile switching from runemu.sh
- **Pre-built aarch64 binary** — no Rust cross-compilation needed

### What InputPlumber does NOT replace

- **gptokeyb** — kept for PortMaster ports (they expect it specifically)
- **rocknix-joypad kernel driver** — still needed as the evdev source device
- **gamecontrollerdb** — still needed for the virtual gamepad's SDL mapping

## Consequences

- All devices get a consistent virtual Xbox Series gamepad
- Per-device input differences become YAML capability maps
- Button layout normalization moves from SDL/RetroArch layer to InputPlumber layer
- IMU integration becomes native (no CemuhookUDP bridge)
- oga_controls can be deprecated (Phase 3, after validation)
- CONFIG_HID_BPF=y enables future hardware-level input fixes

## Architecture

```
Hardware Input
    |
    v
Kernel Driver (rocknix-joypad / retroid-gamepad / odin-gamepad)
    |
    v
/dev/input/eventX (evdev)
    |
    v
InputPlumber daemon
    |--- reads source device (exclusive grab)
    |--- applies capability map (YAML)
    |--- creates virtual composite device
    v
/dev/input/eventY (virtual Xbox Series gamepad)
    |
    +---> EmulationStation (SDL)
    +---> RetroArch (SDL/udev)
    +---> Standalone emulators (SDL)
    +---> gptokeyb (for PortMaster ports)
```

## Related ADRs

- ADR-002: Capability Map Design (button layout normalization)
- ADR-003: Per-Device Implementation Status
