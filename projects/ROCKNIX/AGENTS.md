# ROCKNIX Project — Knowledge Base

## OVERVIEW

ROCKNIX project overlay. Contains ALL device definitions, package overrides, and platform-specific customizations. This directory is THE central hub — base `packages/` upstream is rarely modified.

## STRUCTURE

```
ROCKNIX/
├── options                   # Project defaults: mesa, swaywm-env, lzo
├── devices/                  # Per-SoC device definitions (11 platforms)
│   ├── SM8250/               # Snapdragon 865 (Retroid Pocket 5/Mini/Flip2)
│   │   ├── options           # CPU, GPU, bootloader, additional packages
│   │   ├── patches/linux/    # Kernel patches (applied LAST)
│   │   └── packages/         # Device-specific package overrides
│   ├── RK3588/               # RK3588 (RG Cube, AYN Odin/Thor)
│   ├── SM8550/               # Snapdragon 8 Gen2 (AYANEO Pocket series)
│   └── ...                   # H700, RK3326, RK3566, RK3399, S922X, SDM845, SM6115, SM8650
└── packages/                 # Package overrides (win over base packages/)
    ├── wayland/              # Compositor stack: wlroots 0.20.0, sway 1.12-rc1
    │   ├── lib/wlroots/      # Color-mgmt enabled, Vulkan renderer, Mali patches
    │   ├── compositor/sway/  # Kiosk config, autostart/111-sway-init, systemd units
    │   └── tools/            # wlsunset, wl-mirror, wlr-randr
    ├── emulators/
    │   ├── standalone/       # melonds-sa, azahar-sa, drastic-sa, eden-sa, cemu-sa, rpcs3-src...
    │   │   └── */config/DEVICE/ # Per-device emulator configs (INI, XML, qt-config)
    │   └── libretro/         # RetroArch + 40+ libretro cores
    │       └── retroarch/sources/DEVICE/ # Per-device retroarch.cfg + core-options.cfg
    ├── apps/
    │   └── screen-switch/    # Display management: display-core.sh, display-cycle, screen_switch
    ├── ui/emulationstation/  # ES-next: es_features.cfg, start_es.sh, es_systems.cfg
    ├── rocknix/              # Core scripts: runemu.sh, setsettings.sh, color_gamma, vertical-check
    │   ├── sources/scripts/  # Runtime scripts installed to /usr/bin
    │   ├── profile.d/        # Shell profile fragments (001-functions)
    │   └── autostart/        # Boot-time init scripts
    └── hardware/quirks/      # Per-platform + per-device hardware quirks
        ├── platforms/DEVICE/ # SoC-level: governors, affinity, audio, display, thermal
        ├── devices/NAME/     # Per-device: display adj, LED, special configs
        └── autostart/        # 080-dual_screen_mode (modetest connector detection)
```

## DISPLAY STACK (wlroots 0.20 + sway 1.12-rc1)

**Compositor init**: `autostart/111-sway-init` detects DRM outputs, writes `095-sway` env file
- Vulkan renderer on Qualcomm: `WLR_RENDERER=vulkan`
- Color profile: `output * color_profile gamma22` (sway 1.12 changed srgb TF)
- Per-device quirks: Retroid Dual Screen (DP-1@270), AYANEO Pocket DS (DSI-2@270), Anbernic RG DS

**display-core.sh** (769 lines): N-output management library
- Runtime sway IPC queries — zero hardcoded dimensions
- External output priority (HDMI/DP promoted to primary)
- Canvas geometry: vertical stacking with centering
- Touch calibration: affine matrix composition with rotation
- State files: `/run/rocknix/{display_state, active_output, transform_N}`

**display-cycle**: `move` (swap panels), `off` (power cycle), `mirror` (overlap or wl-mirror)

## EMULATOR LAUNCH PIPELINE

```
ES-next → runemu.sh → {setsettings.sh (RetroArch) | start_*.sh (standalone)}
                     → display-core.sh (dual-screen setup)
                     → InputPlumber profile load
                     → systemd-run (rocknix-foreground.slice)
                     → [emulator runs]
                     → cleanup (restore display, perf, InputPlumber)
```

## DUAL-SCREEN EMULATOR DEFAULTS

| Emulator | Layout Key | Default | Notes |
|----------|-----------|---------|-------|
| melonDS-sa | ScreenLayout | 2 (side-by-side) | ScreenSizing varies: SM8250=4, RK3588=3, S922X=1 |
| melonDS-lr | melonds_screen_layout | Left/Right | Universal across all devices |
| desmume-lr | desmume_screens_layout | left/right | Only in S922X core-options |
| azahar-sa | screen_gap | 0 | Layout via ES features: 0-6 options |
| drastic-sa | screen_orientation | 0 or 1 | 0=horizontal (wide screens), 1=vertical (tall/square) |
| cemu-sa | gamepad_enabled | per-device | TV+GamePad via controller profiles |

## DEVICE MATRIX

| Platform | SoC | GPU Driver | Screen | Multi-Output | Dual-Screen Emu |
|----------|-----|-----------|--------|-------------|----------------|
| SM8250 | Snapdragon 865 | freedreno | 16:9 OLED | screen-switch | Yes |
| SM8550 | Snapdragon 8G2 | freedreno | 16:9 OLED | screen-switch | Yes |
| SM8650 | Snapdragon 8G3 | freedreno | 16:9 OLED | HDMI | Yes |
| RK3588 | RK3588 | panfrost | 16:9/16:10 | HDMI | Yes |
| RK3566 | RK3566 | panfrost/mali | 4:3-16:9 | screen-switch | Yes |
| S922X | S922X | panfrost | 16:9 | No | Partial |
| RK3326 | RK3326 | panfrost/mali | 4:3/3:2 | No | Limited |
| H700 | H700 | panfrost | 16:9 | No | No |
| SDM845 | SDM845 | freedreno | 16:9 | HDMI | Yes |
| SM6115 | SM662 | freedreno | 16:9 | No | No |
| RK3399 | RK3399 | panfrost | varies | No | Partial |

## SM8250 GYRO / SENSOR SUPPORT

**Goal**: Enable LSM6DST 6-axis IMU on Retroid Pocket 5 via `ssc-iio-bridge` daemon.

**Architecture**: SLPI DSP runs sensor firmware. AP communicates via QRTR → SSC QMI (service 0x190) using protobuf. Daemon creates virtual IIO device for InputPlumber to consume.

**Key files**:
- `devices/SM8250/filesystem/usr/lib/firmware/qcom/sm8250/slpi.mbn` — vendor RP5 SLPI firmware (MUST use this, not Thundercomm RB5 default)
- `devices/SM8250/linux/linux.aarch64.conf` — kernel config (IIO configfs/sw-device enabled)
- `packages/devel/protobuf-c/package.mk` — protobuf-c v1.5.0 (dependency for ssc-iio-bridge)

**SLPI firmware**: Vendor RP5 firmware (`SLPI.HY.3.0-00270-SM8250AZL-1`) has LSM6DST support. Pre-extracted blobs at `stock-handhelds/Retroid/RP5/20241127/extracted-slpi/`. Do NOT use Thundercomm RB5 firmware (`SLPI.HY.3.1-00049-SM8250AZL-2`) — it has zero LSM6DST support.

**InputPlumber integration**: Needs `ds5-edge` target (not `xbox-series`) to expose SDL_SENSOR_ACCEL+GYRO. IIO device must be named `bmi260` and expose all 6 channels (accel+gyro) on a single `/dev/iio:deviceN`.

**Protocol**: SSC QMI service ID `0x190`, SUID discovery via well-known SUID `0xABABABABABABABAB`, data in `SscAccelerometerResponse`/`SscGyroscopeResponse` (field 1 = repeated float). No libqmi/GLib needed — raw AF_QIPCRTR + manual QMI TLV + protobuf-c.

## KEY FILES

- `packages/rocknix/sources/scripts/runemu.sh` — Emulator orchestrator
- `packages/rocknix/sources/scripts/setsettings.sh` — RetroArch config generator
- `packages/apps/screen-switch/sources/display-core.sh` — Display management library
- `packages/wayland/compositor/sway/autostart/111-sway-init` — Sway initialization
- `packages/rocknix/sources/scripts/color_gamma` — Color temperature/gamma control
- `packages/rocknix/sources/scripts/vertical-check` — Auto-vertical layout for DS/arcade in RetroArch
- `packages/ui/emulationstation/config/common/es_features.cfg` — ES-next feature definitions
- `packages/hardware/quirks/autostart/080-dual_screen_mode` — Dual-screen detection
