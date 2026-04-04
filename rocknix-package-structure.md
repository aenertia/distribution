# ROCKNIX Package & Boot System — Complete Reference

> Documented 2026-03-01 from build host `kurarua:~/build/distribution/`
> Focus on RK3326 device, XF40H bringup.

---

## 1. Package Directory Layout

All ROCKNIX-specific packages live under:
```
projects/ROCKNIX/packages/
```

Key subdirectories:
```
rocknix/              -- Meta package + autostart scripts + system config + utilities
sysutils/
  busybox/            -- Init script (baked into initramfs via CONFIG_INITRAMFS_SOURCE)
  autostart/          -- Autostart launcher script
linux-drivers/
  mali-bifrost/       -- GPU driver (out-of-tree)
  sv6160/             -- SV6160 WiFi driver (out-of-tree)
```

Device-specific overrides:
```
projects/ROCKNIX/devices/RK3326/
  options             -- Device build options (CPU, kernel, bootloader, display server)
  linux/
    dts/rockchip/     -- XF40H DTS file
    linux.aarch64.conf -- Kernel config
  packages/
    u-boot/patches/   -- U-Boot patches (k36 clone support, XF40H SD UHS fix)
  patches/
    linux/            -- Kernel patches (DTS, panel, input, WiFi, USB role-switch)
    mali-bifrost/     -- Mali patches (lowercase-interrupts, MGLRU)
```

---

## 2. Complete Boot Chain

### Phase 1: U-Boot

U-Boot loads `extlinux.conf` from the FLASH partition (vfat, LABEL=ROCKNIX).

Kernel cmdline constructed from:
- `projects/ROCKNIX/devices/RK3326/options`: `EXTRA_CMDLINE="console=ttyS2,1500000 console=tty0 systemd.debug_shell=ttyS2"`
- `boot=LABEL=ROCKNIX disk=LABEL=ROCKNIX_STORAGE` (set by `mkimage_extlinux()`)
- User additions via extlinux.conf APPEND line

### Phase 2: Initramfs (busybox init)

**File:** `projects/ROCKNIX/packages/sysutils/busybox/scripts/init`

The initramfs is baked into the kernel via `CONFIG_INITRAMFS_SOURCE`. Contents:
- `/init` — main init script
- `/usr/bin/busybox` — statically linked
- `/functions` — progress meter helpers (spinner, percent, countdown)
- `/device.init` — device-specific init (empty for RK3326)
- `/usr/bin/rocknix-splash` — splash screen binary

**Important**: `rdinit=` overrides the initramfs init, NOT `init=`. The `init=` parameter
is only for real rootfs boot. Since ROCKNIX uses initramfs, `init=/bin/sh` has no effect.

Boot steps executed in sequence (each echoed as `>>> BOOT_STEP:` / `<<< BOOT_STEP: done`):

| Step | Function | What it does |
|------|----------|-------------|
| 1 | `load_modules` | Loads modules from `/etc/modules` in initramfs |
| 2 | `recovery_mode` | Checks VOL_DOWN button → USB mass storage + ACM serial shell |
| 3 | `check_disks` | `fsck` on boot (vfat) and storage (ext4) partitions |
| 4 | `mount_flash` | Mounts `boot=LABEL=ROCKNIX` at `/flash` (ro) |
| 5 | `set_consolefont` | Sets spleen font based on framebuffer resolution |
| 6 | `cleanup_flash` | Removes old RPi EEPROM files |
| 7 | `update_bootmenu` | Updates syslinux/grub default |
| 8 | `mount_sysroot` | Mounts `/flash/SYSTEM` (squashfs) via loop at `/sysroot` (ro) |
| 9 | `mount_storage` | Mounts `disk=LABEL=ROCKNIX_STORAGE` at `/storage` (rw) |
| 10 | `check_update` | Checks `/storage/.update/` for OTA files, applies + reboots |
| 11 | `prepare_sysroot` | Moves `/flash` and `/storage` into `/sysroot/flash` and `/sysroot/storage` |

### Phase 2.5: Final (still in initramfs)

After all boot steps:

```sh
# Move pseudo-filesystems into sysroot
mount --move /dev /sysroot/dev
mount --move /proc /sysroot/proc
mount --move /sys /sysroot/sys
mount --move /run /sysroot/run

# Set up kernel module/firmware overlays (runs in chroot)
chroot /sysroot /usr/sbin/kernel-overlays-setup

# Determine systemd target
if [ -f /sysroot/storage/.please_resize_me ]; then
    INIT_UNIT="--unit=fs-resize.target"
elif [ -f /sysroot/storage/.cache/reset_oe -o ... ]; then
    INIT_UNIT="--unit=factory-reset.target"
elif [ -f "${BACKUP_FILE}" ]; then
    INIT_UNIT="--unit=backup-restore.target"
fi

# THE PIVOT
exec switch_root /sysroot /usr/lib/systemd/systemd ${INIT_ARGS} ${INIT_UNIT}
```

### Phase 3: kernel-overlays-setup

**File:** `projects/ROCKNIX/packages/sysutils/busybox/scripts/kernel-overlays-setup`

Runs inside `chroot /sysroot` before switch_root:
1. Creates `/run/kernel-overlays/modules/<kver>/` and `/run/kernel-overlays/firmware/`
2. Symlinks modules/firmware from `/usr/lib/kernel-overlays/base/`
3. Processes user overlays from `/storage/.cache/kernel-overlays/*.conf`
4. Copies user firmware from `/storage/.config/firmware/`
5. Runs `depmod -a` if any module overlays were applied

### Phase 4: systemd

**Package:** `projects/ROCKNIX/packages/sysutils/systemd/package.mk`
**Version:** 255.8 (heavily stripped down)

#### Build Configuration (key meson options)
```
-Ddefault-hierarchy=hybrid     # cgroup v1+v2 hybrid
-Ddbus=false                   # D-Bus compiled OUT
-Dvconsole=false               # No vconsole setup
-Dnetworkd=false               # No networkd
-Dcoredump=false               # No coredump handler
-Dseccomp=false                # No seccomp
-Dlogind=true                  # Logind enabled
-Dresolve=true                 # systemd-resolved enabled
-Dtimesyncd=true               # Time sync enabled
-Dtmpfiles=true                # tmpfiles enabled
-Dhwdb=true                    # Hardware database enabled
-Drfkill=true                  # RF kill switch support
```

#### Stripped Components (removed in post_makeinstall)
- **ALL getty services removed**: `console-getty`, `getty@`, `serial-getty@`, `getty.target`
- **ALL system generators removed** except `systemd-debug-generator`
- **ALL presets disabled**: `echo "disable *" > 99-default.preset`
- nspawn, timedatectl, growfs, makefs — all removed
- Catalog, network adapter renaming rules — removed

#### Explicitly Enabled Services
```
machine-id.service              # Machine ID setup (custom script)
debugconfig.service             # Debug configuration
userconfig.service              # User config setup
usercache.service               # User cache setup
network-base.service            # Network base setup
systemd-timesyncd.service       # NTP time sync
systemd-timesyncd-setup.service # Time sync setup
systemd-resolved.service        # DNS resolver
debug-shell.service             # Debug shell (on ttyS2 per cmdline)
```

#### Important Implications
- **`emergency.target` has no getty** — cannot spawn a shell (all getty services removed)
- **`systemd.unit=emergency.target` will hang** — systemd starts but emergency.service
  needs a console/sulogin which depends on removed getty infrastructure
- **`debug-shell.service` is enabled** — provides root shell on `systemd.debug_shell=`
  TTY, but only works if the correct UART is configured (see UART5 note below)
- **No system generators** — fstab entries won't auto-generate mount units; all mounts
  must be explicit systemd units or handled by autostart scripts
- **Systemd output goes to journal by default** — `systemd.log_target=console` needed
  to see output on screen, but only works if systemd actually starts

#### fs-resize.target (First Boot)
```ini
# fs-resize.target
[Unit]
Requires=fs-resize.service
After=fs-resize.service

# fs-resize.service
[Service]
Type=idle                      # Waits for all other jobs to complete
ExecStart=/usr/lib/rocknix/fs-resize
StandardInput=tty-force        # Requires TTY
```

**Gotcha**: If `.please_resize_me` exists on the storage partition, the init script
hardcodes `--unit=fs-resize.target` as an exec argument to systemd, **overriding** any
`systemd.unit=` on the kernel cmdline (exec args take precedence over /proc/cmdline).

Default target: `rocknix.target`
```ini
[Unit]
Description=rocknix
Requires=multi-user.target graphical.target
After=graphical.target
AllowIsolate=yes
[Install]
Alias=default.target
```

#### ROCKNIX-specific systemd services
- `rocknix-autostart.service` — runs autostart script (Before weston, After network+graphical)
- `rocknix-automount.service` — mounts user storage
- `rocknix-memory-manager.service` — ZRAM/swap setup
- `save-sysconfig.service` — config backup on shutdown
- `bluetooth-agent.service` — BT pairing agent
- `hdmi-hotplug.{path,service}` — HDMI hot-plug detection

### Phase 5: Autostart

**File:** `projects/ROCKNIX/packages/sysutils/autostart/sources/autostart`

Runs numbered scripts in order:
```
001-setup          -- Init dirs, runtime, chksysconfig
003-upgrade        -- Post-update migration
006-display        -- Set brightness
007-rootpw         -- Root password
008-perfmode       -- CPU governor + threads
009-sleepmode      -- Suspend mode
010-uimode         -- Weston kiosk vs desktop, startup app
050-audio          -- Pipewire/ALSA mixer config
055-hdmi-check     -- DRM mode for HDMI
081-usbgadget      -- USB gadget mode
099-networkservices -- Daemons (SSH, Samba, etc)
```

Also runs:
- Platform quirks: `/usr/lib/autostart/quirks/platforms/${HW_DEVICE}/`
- Device quirks: `/usr/lib/autostart/quirks/devices/${QUIRK_DEVICE}/`
- User scripts: `/storage/.config/autostart/`

### Phase 6: UI Launch

For RK3326, set by platform quirk `090-ui_service`:
```sh
UI_SERVICE="sway.service essway.service"
```

Launches Sway window manager → EmulationStation via `essway.service`.

---

## 3. RK3326-Specific Configuration

**Device options** (`projects/ROCKNIX/devices/RK3326/options`):
- CPU: `cortex-a35`, `aarch64`
- Kernel: `Image` target
- Cmdline: `console=ttyS2,1500000 console=tty0 systemd.debug_shell=ttyS2`
  - **NOTE**: XF40H physical UART is UART5, not UART2. The `console=ttyS2` and
    `systemd.debug_shell=ttyS2` are pointing at the wrong UART. eeclone DTS disables
    uart2 and uses uart5. Should be `console=ttyS5,1500000` and `systemd.debug_shell=ttyS5`.
- Bootloader: U-Boot with rkbin firmware
- GPU: Mali Bifrost G31 (mali-bifrost + panfrost)
- Display server: Wayland with Sway
- Additional drivers: sv6160, mali-bifrost

**Platform quirks** (from `projects/ROCKNIX/packages/rocknix/`):
- `002-turbo-mode_config` — enables turbo mode
- `010-governors` — sets CPU/GPU/DMC sysfs paths
- `050-audio_path` — `DEVICE_PLAYBACK_PATH="Playback Mux"`
- `050-modifiers` — function key = SELECT/START
- `060-game_settings` — performance governors for demanding emulators
- `075-mangohud-supported` — MangoHud if panfrost detected
- `090-ui_service` — `UI_SERVICE="sway.service essway.service"`
- `091-ui_shader` — `UI_SHADER="glslp"`

**No XF40H-specific quirks exist** — device would need a quirk directory matching its DT
model string for any device-specific behavior.

### GPU Driver Switching (`gpudriver`)

**Package:** `projects/ROCKNIX/packages/graphics/gpudriver/`

ROCKNIX ships BOTH panfrost (in-tree, open-source) and mali_kbase (out-of-tree, for
libmali proprietary blob) as kernel modules. Both are **blacklisted** by default via
`/etc/modprobe.d/mali-gpu-noauto.conf` to prevent auto-loading probe conflicts.

Runtime switching via `/usr/bin/gpudriver`:
- `gpudriver libmali` — unloads panfrost, loads mali_kbase, bind-mounts libmali libs
- `gpudriver panfrost` — unloads mali_kbase, loads panfrost, unmounts libmali overrides
- `gpudriver --start` — loads the user's saved preference (called by `003-gpudriver` autostart)
- `gpudriver --options` — lists available drivers ("panfrost libmali")

Library switching uses bind mounts: libmali libraries in `/usr/lib/mali/` are mounted
over standard paths (`libEGL.so`, `libGLESv2.so`). When switching to panfrost, these
are unmounted and the mesa versions at the standard paths become active.

**Critical:** Do NOT disable `CONFIG_DRM_PANFROST=m` — it's required for this feature.

---

## 4. First Boot Flow

On first boot with a fresh SD card:
1. Init script finds `.please_resize_me` in storage
2. Sets `INIT_UNIT="--unit=fs-resize.target"`
3. `fs-resize.service` runs `/usr/lib/rocknix/fs-resize`:
   - `parted resizepart` to expand partition
   - `e2fsck` + `resize2fs`
   - `tune2fs` to regenerate UUIDs
   - Reboot
4. Second boot: no `.please_resize_me` → normal `rocknix.target`

---

## 5. Key Paths in Running System

| Path | Source | Contents |
|------|--------|----------|
| `/flash/` | FLASH partition (ro) | Kernel, SYSTEM squashfs, extlinux.conf |
| `/flash/SYSTEM` | Squashfs image | Root filesystem (loop-mounted at `/`) |
| `/storage/` | STORAGE partition (rw) | User data, configs, ROMs |
| `/storage/.config/` | User config | system.cfg, autostart scripts, firmware |
| `/storage/.cache/` | Cache | kernel-overlays, reset flags |
| `/usr/lib/kernel-overlays/` | Squashfs | Module/firmware overlay base |
| `/run/kernel-overlays/` | tmpfs | Assembled overlays (modules + firmware) |
| `/usr/lib/autostart/` | Squashfs | Autostart numbered scripts |
| `/usr/lib/autostart/quirks/` | Squashfs | Platform + device quirks |

---

## 6. Build System Notes

- `rocknix/package.mk` is a meta-package depending on `autostart`
- Autostart scripts are installed to `/usr/lib/autostart/common/`
- Profile scripts go to `/etc/profile.d/`
- Systemd units go to `/usr/lib/systemd/system/`
- The squashfs SYSTEM image is built from the assembled rootfs
- Initramfs is separate — baked into kernel, contains only busybox + init + splash
- Modifying init script requires cleaning linux+busybox+initramfs packages (initramfs baked into kernel)

---

## 7. Debugging Boot Issues

### Init script cmdline parameters
| Parameter | Effect |
|-----------|--------|
| `debugging` | Enables debug mode, calls `break_after` at each BOOT_STEP |
| `break=<step>` | Drops to shell after named boot step (needs keyboard) |
| `recovery` | Forces recovery mode (USB mass storage + ACM serial) |
| `quiet` | Suppresses kernel printk |
| `progress` | Adds `--show-status=1` to systemd args |
| `nofsck` | Skips filesystem checks |
| `toram` | Copies SYSTEM image to RAM |
| `overlay` | Enables overlay filesystem |

### Systemd debugging
| Parameter | Effect |
|-----------|--------|
| `systemd.log_target=console` | Send systemd logs to console (tty0) |
| `systemd.log_level=debug` | Verbose systemd logging |
| `systemd.debug_shell=ttyS5` | Root shell on specified TTY (needs correct UART!) |
| `systemd.unit=<target>` | Override boot target (**overridden by init script if `.please_resize_me` exists**) |
| `panic=0` | Kernel hangs on panic (don't reboot) |
| `panic=30` | Kernel reboots 30s after panic |

### Common pitfalls
1. **`init=/bin/sh` does NOT work** — initramfs uses `rdinit=`, not `init=`
2. **`.please_resize_me` overrides systemd.unit=** — init script passes `--unit=fs-resize.target` as exec arg which takes precedence over cmdline
3. **No getty services exist** — `emergency.target` and `rescue.target` cannot spawn shells
4. **`debug-shell.service` targets ttyS2** but XF40H physical UART is UART5 (ttyS5)
5. **systemd outputs to journal by default** — screen shows nothing after switch_root unless `systemd.log_target=console` is set AND systemd actually starts
