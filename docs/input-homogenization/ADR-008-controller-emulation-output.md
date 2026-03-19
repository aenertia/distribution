# ADR-008: Controller Emulation Output — USB Gadget + Bluetooth HID Device Mode

## Status

Proposed — infrastructure research complete, implementation planned.

## Context

ROCKNIX gaming handhelds have physical gamepads, analog sticks, triggers, and (on some
devices) IMU sensors. The goal is to expose the handheld itself as a gamepad to external
consoles and PCs — making it function as a wireless or wired controller for PS5, Switch,
Xbox, Wii U, PC, and any Bluetooth HID or USB HID host.

This requires:
1. **Runtime switching** of emulated controller type (DualSense, Xbox, Switch Pro, etc.)
2. **USB gadget mode** — device appears as USB HID gamepad when plugged in
3. **Bluetooth HID device mode** — device advertises as BT gamepad for wireless use
4. **ES integration** — UI to select controller type and enable/disable
5. **InputPlumber as the bridge** — reads internal gamepad, writes to output target

## Reference Projects

| Project | Platform | What It Does |
|---------|----------|-------------|
| [inputtino](https://github.com/games-on-whales/inputtino) | Linux (C++) | Creates virtual Xbox/PS5/Switch controllers via UHID, proven with Steam games |
| [joycontrol](https://github.com/mart1nro/joycontrol) | Linux (Python) | Emulates Switch Pro Controller over Bluetooth (BR/EDR L2CAP), works with real Switch |
| [OGX-Mini](https://github.com/wiredopposite/OGX-Mini) | RP2040/RP2350 | USB gamepad emulation for Xbox OG, PS3, Switch, Xbox 360, Wii, Generic HID |
| [Santroller](https://github.com/Santroller/Santroller) | Microcontroller | PS2/PS3/PS4/PS5, Wii, Switch, Xbox OG/360/One HID descriptors |
| [BluePad32](https://github.com/ricardoquesada/bluepad32) | ESP32 | BT gamepad host (reads controllers), not directly relevant for device mode |

## Architecture

```
Internal Gamepad (rocknix-joypad / retroid-gamepad / HID MCU)
    ↓
InputPlumber (reads evdev, normalizes)
    ↓ runtime target switching via DBus
    ├── xbox-series target → USB Gadget f_hid (Xbox HID descriptor)
    ├── ds5 target → USB Gadget f_hid (DualSense HID descriptor)
    ├── switch-pro target → BT HID (Switch Pro BT protocol via joycontrol)
    ├── generic-hid target → USB Gadget f_hid (standard gamepad)
    └── (internal use) → virtual evdev for local emulators
    ↓
External Console / PC reads the gadget/BT device as a controller
```

### Two Output Paths

**Path 1: USB Gadget HID (wired)**
```
InputPlumber → writes HID reports → /dev/hidgN (kernel gadget HID function)
    ↓
USB cable → External host sees USB HID gamepad
```

**Path 2: Bluetooth HID Device (wireless)**
```
InputPlumber → writes HID reports → L2CAP socket (joycontrol-style)
    ↓
Bluetooth radio → External host sees BT HID gamepad
```

## USB Gadget HID — Ready to Enable

### Current Kernel State

All ROCKNIX devices already have the core infrastructure:

| Config | RK3566 | S922X | SM8250 | SM8550 | SM8650 | H700 |
|--------|--------|-------|--------|--------|--------|------|
| `CONFIG_USB_GADGET` | =y | =y | =y | =y | =y | =y |
| `CONFIG_USB_CONFIGFS` | =y | =y | =y | =y | =y | =y |
| `CONFIG_USB_CONFIGFS_F_HID` | **not set** | **not set** | **not set** | **not set** | **not set** | **not set** |
| `CONFIG_USB_ROLE_SWITCH` | =y | =y | =y | =y | =y | =y |
| USB controller | DWC2 (OTG) | DWC2 | DWC3 (DRD) | DWC3 (DRD) | DWC3 (DRD) | MUSB/DWC2 |

**Only missing:** `CONFIG_USB_CONFIGFS_F_HID=y` — one kernel config line per device.

### How USB Gadget HID Works

1. Enable `CONFIG_USB_CONFIGFS_F_HID=y` in kernel
2. At runtime, create gadget via ConfigFS:
   ```bash
   cd /sys/kernel/config/usb_gadget
   mkdir gamepad && cd gamepad
   echo 0x045e > idVendor   # Microsoft (for Xbox)
   echo 0x0b12 > idProduct  # Xbox Series
   mkdir configs/c.1
   mkdir functions/hid.usb0
   echo 1 > functions/hid.usb0/protocol
   echo 1 > functions/hid.usb0/subclass
   echo 64 > functions/hid.usb0/report_length
   # Write HID report descriptor for Xbox gamepad
   cat xbox_descriptor.bin > functions/hid.usb0/report_desc
   ln -s functions/hid.usb0 configs/c.1
   echo <UDC_NAME> > UDC    # Bind to USB device controller
   ```
3. Userspace writes HID reports to `/dev/hidg0`
4. Host sees a USB HID gamepad

### Controller Type HID Descriptors Needed

| Type | VID:PID | Report Size | Source |
|------|---------|-------------|--------|
| Xbox 360 | 045e:028e | 20 bytes | xpad driver / OGX-Mini |
| Xbox Series | 045e:0b12 | 64 bytes | InputPlumber / xpad |
| DualShock 4 | 054c:05c4 | 64 bytes | ds4drv / inputtino |
| DualSense | 054c:0ce6 | 64 bytes | dualsense driver / inputtino |
| Switch Pro | 057e:2009 | 49 bytes | joycontrol / hid-nintendo |
| Generic HID | configurable | configurable | USB HID spec 1.11 |
| Wii U Pro | 057e:0330 | 16 bytes | Wii U HID spec |
| GameCube (via adapter) | 057e:0337 | 37 bytes | GC adapter spec |

### InputPlumber Integration

InputPlumber already creates virtual devices via uinput. For USB gadget output,
it would need a new output backend that writes HID reports to `/dev/hidgN` instead
of (or in addition to) uinput. This could be:

1. **InputPlumber modification** — add a `usb-gadget` target device type
2. **Bridge daemon** — separate process reads InputPlumber's virtual evdev and
   writes to `/dev/hidgN` (simpler, no InputPlumber changes)
3. **inputtino integration** — use inputtino as the HID report generator

## Bluetooth HID Device Mode — Harder but Feasible

### The BlueZ Problem

BlueZ (Linux's Bluetooth stack) does **not natively support HID Device role** for
classic Bluetooth (BR/EDR). It only acts as HID Host (connecting TO controllers).

### Working Solutions

**1. joycontrol (Switch Pro over BT) — Proven**
- Python daemon that opens raw L2CAP sockets (bypasses BlueZ HID profile)
- Successfully emulates Switch Pro Controller to real Nintendo Switch
- Handles Switch-specific pairing, button reports, stick data, IMU
- Could be packaged for ROCKNIX + integrated with InputPlumber
- Limitation: Switch only (proprietary protocol)

**2. Custom L2CAP HID server — Generic**
- Register SDP service record for HID Profile
- Open L2CAP PSM 17 (control) and PSM 19 (interrupt) sockets
- Send HID reports in the correct format for target device
- This is what joycontrol does, but could be generalized for other controller types
- Requires root or `CAP_NET_RAW` for L2CAP socket access

**3. BLE HID Over GATT (HoG) — Limited**
- Works over Bluetooth LE using GATT service
- Supported by BlueZ D-Bus API (register GATT service)
- But: most consoles use BR/EDR for controllers, not BLE
- Useful for: PC (any OS), Android, iOS — NOT consoles

### Console BT Compatibility

| Console | Protocol | Feasible? | How |
|---------|----------|-----------|-----|
| Nintendo Switch | BR/EDR, custom HID | **Yes** | joycontrol (proven) |
| PS4/PS5 | BR/EDR, DualShock/DualSense HID | **Maybe** | Need DS4/DS5 BT protocol RE |
| Xbox | No standard BT gamepad support | **No** | Xbox uses proprietary wireless |
| PC (Windows/Linux/macOS) | BR/EDR HID Profile | **Yes** | Standard L2CAP HID server |
| Android | BR/EDR or BLE HID | **Yes** | Standard HID profile |
| Wii U | Custom BT | **Unlikely** | Proprietary pairing |
| Steam Deck | Standard BT | **Yes** | Any HID gamepad |

## InputPlumber Target Switching

InputPlumber already supports runtime target switching via DBus. Current target types:

```
mouse, keyboard, gamepad, hori-steam, xb360, xbox-elite, xbox-series,
deck, ds5, ds5-edge, touchpad, touchscreen
```

For controller output, we need to **extend** InputPlumber (or add a bridge) with:
- `usb-gadget-xbox` — writes Xbox HID reports to /dev/hidgN
- `usb-gadget-ds5` — writes DualSense HID reports to /dev/hidgN
- `usb-gadget-generic` — writes standard HID reports to /dev/hidgN
- `bt-switch-pro` — runs joycontrol-style BT protocol
- `bt-generic-hid` — runs generic BT HID L2CAP server

The DBus API (`SetTargetDevices`) could switch between these at runtime.

## EmulationStation Integration

### UI Design

New menu in ES Settings → CONTROLLER OUTPUT:

```
Controller Output Mode: [Disabled | USB Gadget | Bluetooth]
Controller Type: [Xbox Series | DualSense | Switch Pro | Generic HID]
[Connect] / [Disconnect]
Status: Connected to <host_name> / Not connected
```

### Implementation

ES would call scripts/DBus to:
1. Switch InputPlumber target to the selected gadget/BT type
2. Configure USB gadget via ConfigFS (for USB mode)
3. Start BT HID server (for Bluetooth mode)
4. Switch USB port to device mode (role switch)

### Hotkey

Guide + specific combo → cycle through output modes (similar to display-cycle):
- Off → USB Xbox → USB DualSense → BT Switch Pro → Off

## Kernel Changes Needed

| Config | Change | All Devices |
|--------|--------|-------------|
| `CONFIG_USB_CONFIGFS_F_HID` | `not set` → `=y` | Yes |
| `CONFIG_UHID` | Already `=y` (except H700) | Enable on H700 |

No other kernel changes required — USB gadget, ConfigFS, role switch, DWC2/DWC3
dual-role, and BT HIDP are all already enabled.

## Implementation Phases

### Phase 1: USB Gadget HID (Wired Output)
1. Enable `CONFIG_USB_CONFIGFS_F_HID=y` on all devices
2. Create `rocknix-gadget-controller` package:
   - ConfigFS setup script for each controller type (Xbox, DS5, Generic)
   - HID report descriptor binaries
   - Systemd service for gadget lifecycle
3. Create bridge daemon: reads InputPlumber virtual evdev → writes `/dev/hidgN`
4. ES menu for enabling/disabling and type selection
5. Test with PC, PS5 (via DS5 descriptor), Switch (via generic HID)

### Phase 2: Bluetooth Switch Pro (Wireless Output)
1. Package joycontrol (Python) or rewrite in Rust/C
2. Integrate with InputPlumber — read virtual evdev, feed to joycontrol
3. ES menu for BT pairing and connection
4. Test with real Nintendo Switch

### Phase 3: Extended BT HID (Generic Wireless)
1. Generalize BT L2CAP HID server for multiple controller types
2. Add DualShock 4 / DualSense BT protocol (if RE'd sufficiently)
3. Add generic HID gamepad over BR/EDR
4. BLE HoG support for PC/Android/iOS clients

### Phase 4: InputPlumber Native Integration
1. Add `usb-gadget` and `bt-hid` as native InputPlumber target backends
2. Eliminate the bridge daemon — InputPlumber writes HID reports directly
3. Full DBus API: `SetTargetDevices as ["usb-gadget-ds5"]`

## Relation to Input Homogenization

This ADR extends the input pipeline BEYOND the device:

```
Hardware → Kernel Driver → InputPlumber → [Internal emulators]
                                        → [USB Gadget → External console]
                                        → [BT HID → External console]
```

InputPlumber is the natural point for this — it already normalizes all internal
input into a unified stream. Adding output targets is an extension of its
composite device architecture, not a new system.

The controller type switching (Xbox ↔ DS5 ↔ Switch Pro) maps directly to
InputPlumber's existing `SetTargetDevices` DBus API. The only new work is the
output backend (ConfigFS HID / L2CAP socket) and the HID report generators.

## Related

- ADR-001: InputPlumber architecture (target device types)
- ADR-004: Extended input modalities (haptics, touch — also output-relevant)
- InputPlumber schema: `target_devices` enum already includes `xb360`, `xbox-series`, `ds5`, `ds5-edge`, `deck`
- Kernel: USB gadget ConfigFS already enabled, just needs F_HID function
