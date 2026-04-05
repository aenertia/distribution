# ROCKNIX Distribution — Project Knowledge Base

**Generated:** 2026-04-05
**Commit:** 82a2a040fa
**Branch:** nert/switch-emu

## OVERVIEW

Embedded Linux distribution for handheld gaming devices. Fork of JELOS/LibreELEC with Wayland/sway compositor, EmulationStation-next frontend, and 60+ emulator packages. Targets 11 SoC families (Rockchip, Qualcomm Snapdragon, Allwinner, Amlogic) across 50+ devices.

## STOCK FIRMWARE REFERENCE

Stock firmware images and flashing artifacts for all supported devices are mirrored at:

- **Path**: `~/build/stock-handhelds/` (real location)
- **Symlink**: `distribution/stock-handhelds` → `~/build/stock-handhelds`
- **Source**: Google Drive folder `16pg2A7gDIvUhqkt5Z1cFG7MqWaVvp4IW` (owner: 3d@aenertia.net)

Structure mirrors the Drive folder hierarchy — one subdirectory per vendor/device family (AYANEO, AYN, Retroid, KONKR, Mangmi, etc.), each containing the flat-build zip, QPST/QFIL tools, and flashing guides.

Useful when: porting to a new device (reference stock partition layout), debugging bootloader issues (compare against known-good firmware), or extracting vendor blobs.

### RP5 SLPI Firmware Extraction (SM8250 gyro support)

**Pre-extracted blobs**: `stock-handhelds/Retroid/RP5/20241127/extracted-slpi/`
- `slpi.mbn` — assembled MBN ready to install (MD5: `c0be0c7346d5ba58679b59849cd51499`)
- `slpi.mdt` + `slpi.b00`–`slpi.b20` — raw MDT segments from vendor firmware
- `README.md` — full extraction procedure and reassembly script

**Why vendor firmware**: ROCKNIX default uses Thundercomm RB5 SLPI (`SLPI.HY.3.1-00049-SM8250AZL-2`) which has NO LSM6DST sensor support. Vendor RP5 firmware (`SLPI.HY.3.0-00270-SM8250AZL-1`) has 246 LSM6DST string matches.

**Installed at**: `projects/ROCKNIX/devices/SM8250/filesystem/usr/lib/firmware/qcom/sm8250/slpi.mbn`

**Critical extraction notes** (do NOT repeat this work — use pre-extracted blobs):
- Firmware is in `NON-HLOS.bin` (FAT16 image), **NOT** `dspso.bin` (ext4 DSP userspace libs)
- `NON-HLOS.bin` uses 4096-byte sectors — standard `mount -o loop` fails; use Python FAT parser
- Files stored flat in root dir with LFN entries; short names are mangled (e.g. `YKAN5Z~2.MDT`)
- Reassemble MDT+segments → MBN using ELF program headers from `slpi.mdt`
- See `extracted-slpi/README.md` for the full Python extraction and reassembly scripts

## STRUCTURE

```
distribution/
├── Makefile              # Device build targets: make SM8250, make RK3588, etc.
├── config/               # Build system config: options cascade, arch flags, emulator defs
│   ├── options           # Global config loader (sources distro→project→device cascade)
│   ├── path              # All build paths (BUILD, TOOLCHAIN, SYSROOT, STAMPS)
│   ├── functions         # 1890-line build function library (hooks, patches, deps)
│   ├── arch.{arm,aarch64}# Per-arch compiler flags and CPU tuning
│   ├── multithread       # Parallel build orchestration (pkgjson→genbuildplan→pkgbuilder)
│   └── emulators/        # 137 system configs (psx.conf, nds.conf — ES-next metadata)
├── scripts/              # Build pipeline: build, unpack, install, image, build_compat
├── packages/             # Base packages (upstream LibreELEC heritage)
├── projects/
│   └── ROCKNIX/          # ★ Project-level overrides — THE key directory
│       ├── options       # Project defaults (mesa, swaywm-env, lzo compression)
│       ├── devices/      # Per-device: SM8250/, RK3588/, H700/ (options, patches)
│       └── packages/     # Package overrides: wayland/, emulators/, ui/, apps/
├── distributions/ROCKNIX/# Distro metadata (version, branding)
├── sources/              # Fetched source tarballs (git-ignored build artifacts)
└── target/               # Build output images
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add new device | `projects/ROCKNIX/devices/NEWDEVICE/options` | Copy existing device, modify CPU/GPU/bootloader |
| Override a package | `projects/ROCKNIX/packages/CATEGORY/PKG/package.mk` | Overrides `packages/CATEGORY/PKG/` by search order |
| Device-specific patch | `projects/ROCKNIX/devices/DEVICE/patches/PKG/*.patch` | Applied LAST (highest priority) |
| Emulator config | `config/emulators/SYSTEM.conf` | Defines ROM paths, extensions, platform ID for ES-next |
| Sway/compositor | `projects/ROCKNIX/packages/wayland/compositor/sway/` | Config, autostart, systemd units |
| Display management | `projects/ROCKNIX/packages/apps/screen-switch/` | display-core.sh library, display-cycle CLI |
| Color/gamma | `projects/ROCKNIX/packages/rocknix/sources/scripts/color_gamma` | wlsunset + Vulkan color profiles |
| Emulator launch | `projects/ROCKNIX/packages/rocknix/sources/scripts/runemu.sh` | Orchestrator: display→perf→launch→cleanup |
| RetroArch settings | `projects/ROCKNIX/packages/rocknix/sources/scripts/setsettings.sh` | Per-game config generation |
| Device quirks | `projects/ROCKNIX/packages/hardware/quirks/` | platforms/DEVICE/, devices/NAME/ |
| Dual-screen emu cfg | `projects/ROCKNIX/packages/emulators/standalone/*/config/DEVICE/` | Per-device INI/XML for melonDS, azahar, drastic |
| ES-next features | `projects/ROCKNIX/packages/ui/emulationstation/config/common/es_features.cfg` | UI option→emulator setting mappings |

## CONVENTIONS

- **Package hooks**: `pre_configure_target`, `make_target`, `makeinstall_target` — standard lifecycle in `package.mk`
- **3-level override**: `packages/` (base) → `projects/ROCKNIX/packages/` (project) → `projects/ROCKNIX/devices/DEVICE/packages/` (device)
- **Patch order**: base → project → device (device patches applied last, win conflicts)
- **Stamp system**: `build.DEVICE.ARCH/.stamps/PKG/build_target` contains `PKG_DEEPHASH` — rebuild only on content change
- **arm32 compat**: SM8250/SM8550/SM8650 build BOTH `arm` and `aarch64` via `scripts/build_compat`
- **arm32 CPU**: Must use `cortex-a55` (not cortex-a77) — `armv8.2-a` breaks GCC 32-bit bootstrap
- **Build dirs**: `build.ROCKNIX-SM8250.aarch64/` (64-bit), `build.ROCKNIX-SM8250.arm/` (32-bit compat)

## ANTI-PATTERNS (THIS PROJECT)

- **NEVER** hardcode panel dimensions — use `display-core.sh` runtime queries via sway IPC
- **NEVER** use `cortex-a77` for arm32 TARGET_CPU — generates `armv8.2-a` which GCC bootstrap rejects
- **NEVER** assume single output — always check `DISPLAY_COUNT` or `display_is_dual()`
- **NEVER** use `current_mode` for dimensions — use `rect` (post-transform, post-scale logical coords)
- **NEVER** skip arm32 x264/x265 encoding exclusion — no arm32 emulator needs H.264/H.265 encode
- Patch hunk counts must match actual line counts (off-by-one causes `malformed patch`)
- `PKG_TOOLCHAIN="manual"` requires explicit `make_target()` — won't auto-detect

## UNIQUE STYLES

- Shell scripts use `. /etc/profile` (not `source`) for POSIX compat
- `get_setting KEY [PLATFORM] [GAME]` — hierarchical settings reader (system→platform→per-game)
- Display state persisted to `/run/rocknix/` (tmpfs — survives session, clears on reboot)
- `WLR_CON` env var tracks active output — updated by display-cycle, read by emulators
- Touch calibration uses 2x3 affine matrices composed with rotation + stacking geometry

## COMMANDS

```bash
make SM8250                    # Build SM8250 (arm32 compat + aarch64 + image)
make RK3588                    # Build RK3588
make world                     # Build ALL devices
make docker-SM8250             # Build via Docker
```

## NOTES

- **Vulkan renderer**: Only on Qualcomm (SM8250/SM8550/SM8650/SDM845/SM6115) — `WLR_RENDERER=vulkan` in 095-sway
- **wlroots 0.20.0** with `-Dcolor-management=enabled` — sway 1.12-rc1 uses `output * color_profile gamma22`
- **sway 1.12 breaking change**: `srgb` transfer function now uses real piece-wise curve, so explicit `gamma22` needed for backward compat
- **libmali quirk**: wl-mirror doesn't work on Mali GPUs — falls back to sway output overlap for mirroring
- **Build parallelism**: Uses `pkgbuilder.py` thread pool (32 slots on builder) with dependency graph from `genbuildplan.py`
- **lilipod**: Requires `pty.tar.gz` pre-built (go:embed) — `make_target` must build pty agent first
