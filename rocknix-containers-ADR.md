# Architecture Decision Record: Containerization Strategy for ROCKNIX

**Date:** March 2026 (revised April 2026)
**Status:** Accepted
**Scope:** All ROCKNIX aarch64 targets (excluding SDM845)

## 1. Context & Architecture Constraints

ROCKNIX is an immutable, single-user Linux OS for aarch64 gaming handhelds. The rootfs is a read-only squashfs image (`/flash/SYSTEM`) loop-mounted at `/`, with `/storage` as the only read-write partition (ext4 on SD card or eMMC). User configs live in `/storage/.config/`, populated from `/usr/config/` defaults on first boot via rsync.

### Hard Constraints

- **Root-only, single-user:** The entire OS runs as `root`. No UID namespacing is needed for the primary use case.
- **Immutable root:** The squashfs rootfs is replaced atomically during OTA updates. All mutable state must live in `/storage/`.
- **Cgroup v2 unified hierarchy:** All devices pass `systemd.unified_cgroup_hierarchy=1`. Two custom slices exist: `rocknix-foreground.slice` (CPUWeight=800) and `rocknix-background.slice` (CPUWeight=50, CPUQuota=80%).
- **SD card I/O constraints:** Random writes on ext4/SD cause latency spikes and flash wear. Volatile data must use tmpfs.
- **Diverse GPU landscape:** Qualcomm Adreno (freedreno/turnip), ARM Mali Bifrost (panfrost), ARM Mali Valhall (panthor) — each with different driver maturity.

### Target Devices

| SoC | GPU | Kernel Driver | Vulkan Status | RAM |
|-----|-----|---------------|---------------|-----|
| SM8250 | Adreno 650 | `msm` | Vulkan 1.3 (Turnip) | 4-8GB |
| SM8550 | Adreno 740 | `msm` | Vulkan 1.3 (Turnip) | 8-12GB |
| SM8650 | Adreno 750 | `msm` | Vulkan 1.3 (Turnip) | 8-16GB |
| SM6115 | Adreno 618 | `msm` | Vulkan 1.3 (Turnip) | 4GB |
| RK3326 | Mali G31 MP2 | `panfrost` | Experimental PanVK | 1-2GB |
| RK3566 | Mali G52 MP4 | `panfrost` | Experimental PanVK | 1-4GB |
| RK3588 | Mali G610 MP4 | `panthor` | Vulkan 1.2 (PanVK) | 4-8GB |
| S922X | Mali G52 MP4 | `panfrost` | Experimental PanVK | 2-4GB |
| H700 | Mali G31 MP2 | `panfrost` | Experimental PanVK | 1-2GB |

## 2. Decisions

### Decision 1: Mutable Linux Sandbox — Distrobox + Lilipod

**Decision:** Use Distrobox (v1.8.2+) backed by Lilipod (v0.0.3+) for mutable Linux containers.

**Rationale:** Lilipod is a single static Go binary (~10MB) that provides OCI image management with zero cgroup overhead — it uses only `unshare`/`nsenter`/`pivot_root`. Since ROCKNIX runs as root, rootless user-namespace machinery is unnecessary. Full Podman/Docker would create complex cgroup hierarchies conflicting with our foreground/background slice setup.

**Limitations:** Lilipod has no cgroup, seccomp, or capability management. If resource limits are needed, wrap the container launch in `systemd-run --slice=rocknix-background.slice`.

**Storage:** Set `LILIPOD_HOME=/storage/containers/distrobox` and `DBX_CONTAINER_CUSTOM_HOME=/storage/containers/home`.

### Decision 2: Android Subsystem — Waydroid + LXC (Android 13 / LineageOS 20)

**Decision:** Use Waydroid (v1.6.2+) backed by LXC (v4.0+) with a custom-built, aggressively stripped LineageOS 20 (Android 13) arm64_only system image targeting <350MB compressed.

**Rationale:** Waydroid's Python daemon requires `python3-lxc` bindings to boot Android's `init` system; Lilipod cannot run system containers. We target Android 13 (LineageOS 20) because it is Waydroid's current shipping default — Android 11 (LineageOS 18.1) is no longer actively maintained. LXC 4.0+ is required for proper cgroup v2 unified hierarchy support via eBPF device controller.

**Build approach:** Custom build based on GammaOS Core stripping techniques (already optimized for RK3566 gaming handhelds with 1GB RAM). Build workspace at `~/build/rxandroid/`, Codeberg: `codeberg.org/aenertia/rxandroid`. See `AGENTS.md` in that repo for complete build instructions.

**Lunch target:** `lineage_waydroid_arm64_only-userdebug` — drops all 32-bit (armeabi-v7a) libraries, saving ~200-400MB. Most modern Android games ship arm64 native libraries.

### Decision 3: Unified Container Storage — `/storage/containers/`

**Decision:** All container data, images, and overlays are localized to `/storage/containers/`.

**Implementation:**
```
/storage/containers/
  waydroid/
    system.sfs       # Stripped Android system (squashfs+zstd, read-only)
    vendor.sfs       # Mesa/gralloc vendor (squashfs+zstd, read-only)
    data/            # Persistent Android app data (rw, ext4)
    waydroid.cfg     # Waydroid configuration
    waydroid.prop    # User property overrides
  distrobox/
    images/          # OCI container images
    containers/      # Container rootfs instances
  home/              # Shared home for containerized apps
```

A systemd oneshot service creates these directories and symlinks on first boot:
- `/var/lib/waydroid` → `/storage/containers/waydroid/`
- `/root/.local/share/waydroid` → `/storage/containers/waydroid/`
- `/root/.local/share/containers` → `/storage/containers/distrobox/`

### Decision 4: Android App Distribution via EmulationStation

**Decision:** Users drop `.apk` files into `/storage/roms/android/`. EmulationStation scans and launches them via a bash wrapper that extracts the package name, installs if missing, and launches directly — hiding the Android OS behind the appliance UI.

### Decision 5: Filesystem Sharing — Bypass Scoped Storage

**Decision:** Disable Android 13's Scoped Storage FUSE enforcement at build time and inject an LXC bind-mount for `/storage`.

**Implementation:**
- Build-time: `persist.sys.fflag.override.settings_fuse=false` in system props. Apply Waydroid's standard framework patches (included in `apply-waydroid-patches`).
- LXC config: `lxc.mount.entry = /storage mnt/host_storage none bind,create=dir 0 0`

### Decision 6: Security — Unconfined Privileged Container

**Decision:** Run the Waydroid LXC container fully unconfined: no SELinux, no seccomp, no AppArmor, root-mapped UID.

**Rationale:** ROCKNIX's security model relies on its immutable rootfs. Android's security layers add CPU/RAM overhead and complicate GPU passthrough. The container runs as a privileged extension of the host.

### Decision 7: SD Card Write Mitigation

**Decision:** Aggressively redirect volatile writes to tmpfs and disable logging daemons.

**Implementation:**
- Host: `/storage` mounted with `noatime,nodiratime`
- Android build: disable `logd`, `tombstoned`, `traced`, `statsd` daemons
- LXC config: mount `/data/log`, `/data/tombstones`, `/data/misc/trace`, `/data/local/tmp` as tmpfs
- Distrobox: map `/var/cache` and `~/.cache` to tmpfs
- Android props: `debug.sqlite.journalmode=WAL` (reduce journal write thrashing)

### Decision 8: GPU Acceleration — Direct DRM Passthrough

**Decision:** Use **direct DRM device passthrough** via LXC bind mounts. The Android container runs Mesa drivers that talk directly to the host kernel's DRM driver through `/dev/dri/renderD*`.

> **Correction from v1:** The original ADR specified Venus/Zink (virtio-gpu protocol translation). This was incorrect. Venus and VirGL are VM technologies for QEMU/crosvm. Waydroid is an LXC container sharing the host kernel — GPU access is direct with zero protocol translation overhead. Performance is near-native.

**Waydroid auto-detection:** Waydroid's `gpu.py` maps the host kernel DRM driver to the corresponding Android Vulkan HAL:

| Host Kernel Driver | Android Vulkan HAL | Auto-Detect |
|--------------------|--------------------|-------------|
| `msm` / `msm_dpu` | `freedreno` (Turnip) | YES |
| `panfrost` | `panfrost` (PanVK) | YES |
| `panthor` | — | **NO** — must patch `gpu.py` |
| `amdgpu` | `radeon` (RADV) | YES |

**RK3588 patch required:** Add `"panthor": "panfrost"` to `gpu.py`'s driver mapping table. PanVK serves both panfrost and panthor kernel drivers.

**mali_kbase incompatibility:** mali_kbase is a miscdevice driver exposing `/dev/mali0`, NOT a DRM driver. It does not create `/dev/dri/renderD*` nodes. Waydroid's `gpu.py` requires DRM render nodes — without them it falls back to SwiftShader software rendering. On dual-driver devices (RK3566, S922X) where mali_kbase is the default, the `gpudriver` script provides `--waydroid-ensure` and `--waydroid-restore` hooks that temporarily switch to panfrost/panthor when Waydroid starts, then restore libmali when it stops. These are called from Waydroid's systemd service `ExecStartPre=/usr/bin/gpudriver --waydroid-ensure` and `ExecStopPost=/usr/bin/gpudriver --waydroid-restore`.

**Gralloc:** Use `ro.hardware.gralloc=minigbm_gbm_mesa` (better game compatibility than the default `gbm`, confirmed by Roblox-on-Waydroid and Garuda Linux testing).

**Device nodes** (auto-configured by Waydroid's LXC helper):
```
/dev/dri/renderD*      # DRM render node (primary GPU access)
/dev/dri/card*         # DRM master
/dev/dma_heap/*        # DMA-BUF heaps
/dev/sw_sync           # HWC fence sync
```

### Decision 9: Cgroup v2 Slice Integration

**Decision:** Run the Waydroid container inside ROCKNIX's existing cgroup slice hierarchy. Add `Delegate=yes` to both slices so LXC can manage sub-cgroups.

**Current state:** The `rocknix-foreground.slice` and `rocknix-background.slice` are defined and enabled but underutilized — emulators bypass slices entirely, using per-process `uclampset` instead.

**Container integration design:**

1. Waydroid LXC container starts in `rocknix-background.slice` (CPUWeight=50)
2. When an Android game is actively running, promote to `rocknix-foreground.slice` (CPUWeight=800)
3. Slice modifications needed:

```ini
# rocknix-foreground.slice
[Slice]
CPUWeight=800
Delegate=yes

# rocknix-background.slice
[Slice]
CPUWeight=50
CPUQuota=80%
Delegate=yes
```

4. Boot-time delegation (add to `008-perfmode`):
```bash
echo "+cpu +memory +io +pids" > /sys/fs/cgroup/cgroup.subtree_control
echo "+cpu +memory +io +pids" > /sys/fs/cgroup/system.slice/cgroup.subtree_control
```

5. Per-container memory limits via LXC config:
```
lxc.cgroup2.memory.max = 2147483648    # 2GB
lxc.cgroup2.memory.high = 1879048192   # 1.75GB soft limit
```

**UCLAMP per-cgroup:** Requires `CONFIG_UCLAMP_TASK_GROUP=y`. Enabled on all devices: SM8250, SM8550, SM8650, RK3588, RK3566, SM6115, S922X, H700.

### Decision 10: Android Image Build Strategy

**Decision:** Build from LineageOS 20 source with Waydroid integration, using GammaOS Core's stripping techniques as reference. Build workspace: `~/build/rxandroid/` (Codeberg: `codeberg.org/aenertia/rxandroid`).

**Key build choices:**
- Lunch target: `lineage_waydroid_arm64_only-userdebug`
- `OVERRIDE_TARGET_FLATTEN_APEX := true` (eliminate loop-mount overhead)
- `ro.config.low_ram=true` (aggressive memory management)
- `WITH_SU=true` (root access without Magisk complexity)
- Strip: CJK fonts, telephony, camera, NFC, launcher, browser, settings UI
- Post-build: convert ext4 → squashfs+zstd for read-only deployment (<350MB target)

See `~/build/rxandroid/AGENTS.md` for complete build instructions, stripping plan, and package lists.

### Decision 11: Gamepad Input Passthrough

**Decision:** Use Waydroid's native udev/uevent passthrough for gamepad input from the host.

**Implementation:**
```bash
waydroid prop set persist.waydroid.udev true
waydroid prop set persist.waydroid.uevent true
```

Controllers must be connected AFTER the Waydroid session starts for hot-plug detection. The host's InputPlumber virtual DualSense device is passed through to Android.

For advanced input mapping (keyboard/mouse → touch for games), XtMapper (`Xtr126/XtMapper`) can run inside the Android container.

### Decision 12: App Store & Google Services

**Decision:** Ship without Google Play Services. Offer MicroG as an optional lightweight replacement. Use F-Droid and Aurora Store for app distribution.

**Rationale:** Google Play Services adds ~200MB of proprietary blobs and constant background activity. MicroG provides essential API compatibility (push notifications, location) at a fraction of the cost. F-Droid provides FOSS apps. Aurora Store provides access to the Google Play catalog without a Google account.

**Installation:** Via `casualsnek/waydroid_script` or `waydroid-helper` GUI tool post-deployment.

## 3. Kernel Configuration Requirements

### Changes needed — ALL devices (currently MISSING on all)

```
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
```

### Changes needed — specific devices

| Config | Missing On | Purpose |
|--------|-----------|---------|
| `CONFIG_USER_NS=y` | RK3399, RK3566, S922X | Rootless containers (Distrobox) |
| `CONFIG_PSI=y` | SM6115 | Android LMKD pressure monitoring |
| `CONFIG_BPF_SYSCALL=y` | Verify all | LXC cgroup2 device controller |
| `CONFIG_CGROUP_BPF=y` | Verify all | LXC cgroup2 device controller |
| `CONFIG_FUSE_FS=y` | Verify all | Android storage layer |
| `CONFIG_TMPFS_XATTR=y` | Verify all | Android security labels |
| `CONFIG_MEMFD_CREATE=y` | Verify all | Shared memory (sys.use_memfd=true) |

### Already present on all devices

```
CONFIG_NAMESPACES=y        CONFIG_VETH=m
CONFIG_CGROUPS=y           CONFIG_BRIDGE=m
CONFIG_MEMCG=y             CONFIG_OVERLAY_FS=y/m
CONFIG_SQUASHFS_ZSTD=y     CONFIG_CPUSETS=y
```

### Binderfs host setup

```bash
# /etc/modules-load.d/waydroid.conf
binder_linux

# /etc/tmpfiles.d/waydroid.conf
d! /dev/binderfs 0755 root root

# Mount (fstab or systemd .mount unit)
none /dev/binderfs binder nofail 0 0
```

## 4. Package Dependencies

### Lilipod/Distrobox stack
`distrobox`, `lilipod`

### Waydroid stack
`waydroid`, `python3-lxc`, `lxc` (v4.0+), `libgbinder`, `python3-gbinder`, `dnsmasq`, `nftables`, `aapt`

## 5. What Does NOT Apply to aarch64

- **ARM translation layers** (libhoudini, libndk_translation) — x86_64 host only. Native ARM64 execution needs zero translation.
- **Venus / VirGL / virtio-gpu** — VM technologies for QEMU/crosvm. Waydroid is an LXC container, not a VM. GPU access is direct DRM passthrough.
- **Android kernel builds** — The container shares the ROCKNIX host kernel. No Android kernel is built.
- **32-bit ARM compat** — The `arm64_only` image drops 32-bit support. APKs shipping only `armeabi-v7a` libs will not work. Most modern games ship `arm64-v8a`. If needed, use `waydroid_arm64` target + `CONFIG_COMPAT=y`.

## 6. References

| Resource | URL |
|----------|-----|
| rxandroid repo (build workspace) | https://codeberg.org/aenertia/rxandroid |
| GammaOS Core | https://github.com/TheGammaSqueeze/GammaOSCore |
| GammaOS Core Distribution | https://github.com/TheGammaSqueeze/GammaOSCoreDistribution |
| GammaPad | https://github.com/TheGammaSqueeze/GammaPad |
| Waydroid | https://github.com/waydroid/waydroid |
| Waydroid build docs | https://docs.waydro.id/development/compile-waydroid-lineage-os-based-images |
| Waydroid vendor | https://github.com/waydroid/android_vendor_waydroid |
| Waydroid GPU source | https://github.com/waydroid/waydroid/blob/main/tools/helpers/gpu.py |
| Waydroid LXC source | https://github.com/waydroid/waydroid/blob/main/tools/helpers/lxc.py |
| Waydroid prop options | https://docs.waydro.id/usage/waydroid-prop-options |
| Waydroid pre-built images | https://sourceforge.net/projects/waydroid/files/images/ |
| casualsnek/waydroid_script | https://github.com/casualsnek/waydroid_script |
| waydroid-helper | https://github.com/waydroid-helper/waydroid-helper |
| Garuda Waydroid guide | https://forum.garudalinux.org/t/ultimate-guide-to-install-waydroid-in-any-arch-based-distro-especially-garuda/15902 |
| Roblox on Waydroid (gralloc) | https://gitlab.com/TestingPlant/roblox-on-waydroid-guide |
| Lilipod | https://github.com/89luca89/lilipod |
| Distrobox | https://github.com/89luca89/distrobox |
| LXC 4.0 cgroup2 | https://linuxcontainers.org/lxc/news/2020_03_25_13_03.html |
| Kernel cgroup v2 docs | https://docs.kernel.org/admin-guide/cgroup-v2.html |
| Mesa freedreno | https://docs.mesa3d.org/drivers/freedreno.html |
| PanVK Vulkan 1.2 | https://www.collabora.com/news-and-blog/ |
| SurfaceFlinger props | https://source.android.com/docs/core/graphics/surfaceflinger-props |
| ART runtime config | https://source.android.com/docs/core/runtime/configure |
| GammaOS interview | https://gardinerbryant.com/the-developer-the-handheld-scene-depends-on-an-interview-with-gamma/ |
| MagiskOnWaydroid | https://github.com/pagkly/MagiskOnWaydroid |
| XtMapper (input mapping) | https://github.com/Xtr126/XtMapper |
