# SM8250 (Retroid Pocket 5) System Profile — 2026-03-31

Build: `ROCKNIX-SM8250.aarch64-20260331` (commit `86fa2a5d`, branch `nert/switch-emu`)
Kernel: `6.19.5 SMP PREEMPT`, Boot time: 11.3s (3s kernel + 8.3s userspace)

---

## 1. SD Card / MMC Status

### Current Boot (Kioxia 16GB)
```
[    0.950724] sdhci_msm 8804000.mmc: Got CD GPIO
[    0.982388] mmc0: SDHCI controller on 8804000.mmc [8804000.mmc] using ADMA 64-bit
[    1.079537] mmc0: new UHS-I speed DDR50 SDHC card at address 13ab
[    1.080037] mmcblk0: mmc0:13ab SE016 14.4 GiB
[    1.082463]  mmcblk0: p1 p2
```

**Card probe to block device: ~130ms** (0.950s -> 1.082s). Very fast.

### sdhci-caps-mask Status

**CRITICAL: This device has the OLD build** with `sdhci-caps-mask = <0x3 0x0>` (only SDR50+SDR104 masked). The updated `<0x7 0x0>` build was not yet flashed.

**DDR50 is STILL ENABLED** — the Kioxia 16GB card is running in DDR50 mode. This means:
- The Samsung 512GB SDXC card would also attempt DDR50
- The 1.8V voltage switch (CMD11) IS happening
- The `<0x3 0x0>` mask is insufficient

Live DTB value: `00 00 00 03 00 00 00 00` = `<0x3 0x0>`
Needed: `00 00 00 07 00 00 00 00` = `<0x7 0x0>` (mask DDR50 too)

### SD Card Boot Partition
```
/dev/mmcblk0p1: LABEL="ROCKNIX" TYPE="vfat" (2.0G, 95% used)
/dev/mmcblk0p2: LABEL="STORAGE" TYPE="ext4" (12.3G, 7% used)
```

### IRQ Assignment
```
IRQ 174: GICv3 236 Level mmc0      — 4524 interrupts (data)
IRQ 179: GICv3 254 Level 8804000.mmc — 3 interrupts (power)
IRQ 207: msmgpio 77 Edge cd         — 0 interrupts (card detect)
```
All on CPU0 — no IRQ affinity spreading.

---

## 2. CPU / Scheduler

### Topology
```
CPU 0-3:  Kryo-4XX-Silver (Cortex-A55)  300-1804 MHz   (17 OPPs)
CPU 4-6:  Cortex-A77 (Gold)             710-2419 MHz   (18 OPPs)
CPU 7:    Cortex-A77 (Prime)            844-2841 MHz   (20 OPPs)
```

### Governor: `schedutil` (correct for EAS)
| CPU | Governor | Current | Min | Max |
|-----|----------|---------|-----|-----|
| cpu0 | schedutil | 1344 MHz | 300 MHz | 1804 MHz |
| cpu1 | schedutil | 1248 MHz | 300 MHz | 1804 MHz |
| cpu2 | schedutil | 1248 MHz | 300 MHz | 1804 MHz |
| cpu3 | schedutil | 1420 MHz | 300 MHz | 1804 MHz |
| cpu4 | schedutil | 1574 MHz | 710 MHz | 2419 MHz |
| cpu5 | schedutil | 1574 MHz | 710 MHz | 2419 MHz |
| cpu6 | schedutil | 1478 MHz | 710 MHz | 2419 MHz |
| cpu7 | schedutil | 1862 MHz | 844 MHz | 2841 MHz |

### Scheduler Config
| Parameter | Value | Notes |
|-----------|-------|-------|
| `sched_energy_aware` | 1 | EAS enabled (good) |
| `sched_autogroup_enabled` | 1 | Auto-grouping on |
| `sched_util_clamp_min` | 0 | No minimum utilization floor |
| `sched_util_clamp_max` | 1024 | No ceiling cap |
| `sched_util_clamp_min_rt_default` | 512 | RT tasks get 50% floor |
| `CONFIG_PREEMPT` | y | Full preemption (good for latency) |
| `CONFIG_HZ` | 250 | Tick rate |
| `CONFIG_NO_HZ_IDLE` | y | Tickless idle |
| `CONFIG_ENERGY_MODEL` | y | Energy model for EAS |
| `CONFIG_UCLAMP_TASK` | y | Per-task UCLAMP supported |

### Observations
- **EAS is properly configured** — `schedutil` + `ENERGY_MODEL` + `sched_energy_aware=1`
- **UCLAMP is available** but not actively used (min=0, max=1024). Could set `sched_util_clamp_min` for emulator processes to pin them to big cores
- **HZ=250** is standard. 1000Hz would reduce scheduling latency but increase power consumption. For gaming handhelds, 300 is the sweet spot used by many distros
- **No core pinning** observed — emulator processes rely on EAS to select appropriate cores
- **Available governors**: `ondemand powersave performance schedutil` — no `conservative`

### Potential Optimizations
1. **Set `sched_util_clamp_min` for emulator processes** (e.g., `uclamp_min=768`) to keep them on A77 cores
2. **Consider `CONFIG_HZ=300`** for better frame pacing at 30/60 FPS
3. **CPU max frequency is NOT throttled** — cpu7 can reach 2841 MHz. Thermal management relies on `step_wise` policy

---

## 3. GPU (Adreno 650)

```
Device: 3d00000.gpu
Governor: simple_ondemand
Current: 305 MHz
Min: 305 MHz
Max: 800 MHz
Available: 305 400 441 490 525 587 650 700 750 800 MHz
```

### Observations
- **`simple_ondemand`** governor is appropriate for GPU
- **800 MHz max** is the full Adreno 650 clock
- **GPU is idle at 305 MHz** (menu/desktop)
- No GPU cooling device overrides

### UFS Controller
```
Device: 1d84000.ufshc
Governor: simple_ondemand
Current: 37.5 MHz (idle)
Max: 300 MHz
```

---

## 4. Memory

### Physical RAM: 7.0 GiB (7,311,364 kB)
```
Total:     7.0 GiB
Used:      1.4 GiB
Free:      5.1 GiB
Available: 5.5 GiB
Buffers:   8.6 MiB
Cached:    784 MiB
Slab:      422 MiB (354 MiB reclaimable)
```

### ZRAM Swap
```
Device:      /dev/zram0
Algorithm:   lz4 (selected from: lzo-rle lzo lz4 lz4hc zstd)
Disk size:   3.5 GiB (~50% of RAM)
Used:        4 KiB (effectively unused)
Priority:    100
```

### VM Tunables
| Tunable | Value | Assessment |
|---------|-------|------------|
| `swappiness` | 100 | **Aggressive swap** — good for ZRAM (compressed RAM is better than OOM) |
| `vfs_cache_pressure` | 100 | Default — could lower to 50 for gaming (keep dentries/inodes cached) |
| `dirty_ratio` | 5 | Low (good for SD card — prevents large writeback bursts) |
| `dirty_background_ratio` | 3 | Low (start background writeback early) |
| `overcommit_memory` | 1 | **Always overcommit** — no OOM until actually out of memory. Good for emulators |
| `min_free_kbytes` | 45056 (44 MiB) | Reasonable for 7 GiB RAM |
| `page-cluster` | 0 | **Optimal for ZRAM** — read 1 page at a time (ZRAM is random-access, not sequential) |
| `watermark_boost_factor` | 15000 | Default |
| `watermark_scale_factor` | 100 | Default (could increase to 150 for more aggressive reclaim) |
| `compaction_proactiveness` | 40 | Moderate (default 20) — more proactive compaction |
| THP | `madvise` | Only for processes that request it — correct for embedded |
| THP defrag | `defer+madvise` | Deferred defrag — correct |

### Potential Optimizations
1. **`vfs_cache_pressure=50`** — keep filesystem metadata cached longer (less re-reading from SD)
2. **ZRAM algorithm**: `lz4` is good for speed. `zstd` gives better compression but higher CPU. Current choice is correct for gaming
3. **`watermark_scale_factor=150`** — slightly more aggressive reclaim could prevent latency spikes during memory pressure

---

## 5. Thermal

All zones are cool (35-39C at idle):
| Zone | Temp | Notes |
|------|------|-------|
| cpu0-7 | 36-38C | All cores idle-warm |
| gpu-top | 36C | Idle |
| gpu-bottom | 35C | Idle |
| battery | 32C | Normal |
| pm8150 | 38.7C | PMIC slightly warm |
| pm8150l | 39.5C | PMIC slightly warm |
| skin-msm | -40C | **Sensor not connected/calibrated** |
| pm8150l-pcb | -40C | **Sensor not connected/calibrated** |

### Cooling Devices
| Device | Type | State |
|--------|------|-------|
| cooling_device0 | cpufreq-cpu0 | 0/16 (not throttling) |
| cooling_device1 | cpufreq-cpu4 | 0/17 (not throttling) |
| cooling_device2 | cpufreq-cpu7 | 0/19 (not throttling) |
| cooling_device3 | devfreq-gpu | 0/9 (not throttling) |
| cooling_device4 | **pwm-fan** | **1/4** (fan on, low speed) |
| cooling_device5 | ath11k_thermal | 0/100 (WiFi not throttling) |

Fan is running at level 1/4. Two skin thermal sensors read -40C which indicates they're disconnected or uncalibrated — these should probably be disabled in DTS to avoid false trip points.

---

## 6. Services

### Running (22 services)
Key services: `essway`, `sway`, `inputplumber`, `pipewire`, `wireplumber`, `iwd`, `sshd`, `avahi-daemon`, `smbd/nmbd`, `fancontrol`, `powerstate`, `seatd`

### Failed (2 services)
```
systemd-rfkill.service — "Failed to set up special execution directory in /var/lib: Too many levels of symbolic links"
systemd-rfkill.socket  — same
```
**Root cause:** `/var/lib` is likely a symlink chain that's too deep. This prevents rfkill state from being persisted. WiFi/Bluetooth soft-kill state won't survive reboots.

### Boot Blame (top 5)
| Time | Service |
|------|---------|
| 4.37s | `rocknix-autostart.service` |
| 2.31s | `dev-mmcblk0p2.device` |
| 2.29s | `dev-mmcblk0p1.device` |
| 1.46s | `dev-loop0.device` |
| 1.10s | `dev-zram0.device` |

---

## 7. WayVNC Issue

### Root Cause: `Failed to load config`

The journal shows:
```
wayvnc[4274]: ERROR: ../src/main.c: 2433: Failed to load config. Success
```

This is NOT the IPv4/IPv6 issue previously hypothesized. The error is at `main.c:2433` — wayvnc fails to load its config file and exits immediately. The "Success" in the error message is a bug in wayvnc's error reporting (it prints `strerror(errno)` but errno is 0 since the failure was a parse error, not a syscall error).

### Service Config
```ini
[Service]
Environment=WAYLAND_DISPLAY=wayland-1
Environment=XDG_RUNTIME_DIR=/run/0-runtime-dir
Environment=SWAYSOCK=/run/0-runtime-dir/sway-ipc.0.sock
ExecStart=/usr/bin/wayvnc --render-cursor 0.0.0.0
ConditionPathExists=|/storage/.cache/services/wayvnc.conf
```

The `ConditionPathExists=|` (note the pipe — optional) means the service starts even without the config file. But wayvnc itself requires a valid config at `~/.config/wayvnc/config` or `/etc/wayvnc/config`.

### Fix Needed
1. Create a default config file: `/storage/.config/wayvnc/config` or `/usr/config/wayvnc/config`
2. The config needs at minimum:
```
address=::
port=5900
```
3. Also fix the listen address from `0.0.0.0` to `::` in the service ExecStart
4. The service has restarted **58 times** before giving up — `StartLimitInterval=0` allows infinite restarts but systemd eventually stops it

### Why Manual Launch Works
When launched manually with `-a sm8250.3d.ae.net.nz`, wayvnc skips config file loading (CLI args override) and binds directly to the specified address. The config file failure path is never hit.

---

## 8. USB Gadget Issue

### Root Cause: `dr_mode = "host"` in DTS

```
/sys/firmware/devicetree/base/soc@0/usb@a6f8800/usb@a600000/dr_mode = "host"
/sys/class/udc/ = (empty)
```

The DWC3 controller is hardcoded to host-only mode. No UDC is registered, so `usbgadget` exits at line 248:
```sh
UDC_NAME=$(ls -1 /sys/class/udc 2>/dev/null | head -n1)
[ -z "${UDC_NAME}" ] && exit 1
```

### Type-C Port Capabilities
```
port0: data_role=host [device]  power_role=source [sink]  port_type=[dual]
```
The hardware supports dual-role (host+device), but the DTS overrides it to host-only.

### Kernel Support
All gadget kernel configs are built-in:
```
CONFIG_USB_GADGET=y
CONFIG_USB_DWC3_DUAL_ROLE=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_F_ACM=y, CONFIG_USB_F_NCM=y, CONFIG_USB_F_MASS_STORAGE=y, CONFIG_USB_F_HID=y
```

### Fix Needed
1. Change `dr_mode = "host"` to `dr_mode = "otg"` in the DTS patch for `usb@a600000`
2. EmulationStation should also hide the USB gadget selector when `usbgadget --options` returns empty (UI fix)

### DWC3 Dependency Cycles
dmesg shows **14 "Fixed dependency cycle" messages** involving the USB, PHY, Type-C mux, and PMIC connector nodes. These are resolved by the kernel but indicate the DTS structure could be cleaner. Not blocking but worth noting.

---

## 9. Other Issues Found

### BFQ Scheduler for MMC
```
(udev-worker): mmcblk: ATTR{queue/scheduler}="bfq": Could not chase sysfs attribute
```
The udev rule `10-bfq-sched.rules` tries to set BFQ scheduler for MMC block devices but the sysfs path doesn't exist. This is harmless but the rule should be updated for kernel 6.19+ block layer changes.

### Soundwire Port Mismatches
```
qcom-soundwire 3210000.soundwire: din-ports (0) mismatch with controller (1)
qcom-soundwire 3210000.soundwire: dout-ports (5) mismatch with controller (6)
qcom-soundwire 3230000.soundwire: din-ports (5) mismatch with controller (6)
qcom-soundwire 3230000.soundwire: dout-ports (0) mismatch with controller (1)
qcom-soundwire 3250000.soundwire: din-ports (2) mismatch with controller (3)
```
The DTS soundwire port counts don't match the hardware. Audio still works but this generates warnings on every boot.

### DSI Error
```
dsi_err_worker: status=5
```
A display DSI error at ~67s after boot. Could be a panel power state transition issue. Status=5 is typically a timeout. Worth monitoring — if it happens during gameplay it could cause display glitches.

### PipeWire DBus
```
pipewire-pulse: Failed to acquire org.pulseaudio.Server: AccessDenied
```
PipeWire's PulseAudio compatibility layer can't register on DBus. Audio works via native PipeWire but some legacy apps expecting PulseAudio DBus interface will fail.

### NFS Mount
```
awa.3d.ae.net.nz:/exports/roms on /storage/games-external (14.6T, 94% used)
```
NFS ROM share is mounted. 14.6TB total, 13.6TB used.

---

## 10. Network

### Connectivity
- **WiFi**: `wlan0` (ath11k)
- **IPv4**: `172.16.1.247/24`
- **IPv6**: `2401:7000:c50a:8200::b30/128` (SLAAC)
- **IPv6 ULA**: `fd15:af69:ba1::b30/128`

---

## 11. Top Processes by Memory

| PID | %CPU | %MEM | RSS | Process |
|-----|------|------|-----|---------|
| 3287 | 39.6 | 7.2 | 530 MiB | emulationstation |
| 3166 | 2.6 | 0.4 | 36 MiB | sway |
| 763 | 0.1 | 0.2 | 19 MiB | wireplumber |
| 784 | 1.4 | 0.1 | 13 MiB | pipewire-pulse |
| 792 | 3.2 | 0.1 | 12 MiB | inputplumber |

EmulationStation uses 530 MiB (~7.2% of 7 GiB RAM). Total system usage ~1.4 GiB.

---

## 12. Action Items for Next Build

### Critical
| # | Issue | Fix | File |
|---|-------|-----|------|
| 1 | Samsung 512GB SD boot fails | Change `sdhci-caps-mask` to `<0x7 0x0>` | `0000-sm8250-retroidpocket-common.patch` |
| 2 | Init timeout too short for SDXC | Increase mount retry from 15 to 30 | `busybox/scripts/init` |

### High Priority
| # | Issue | Fix | File |
|---|-------|-----|------|
| 3 | WayVNC crashes on start (58 restarts) | Create default config + fix listen address | wayvnc packaging |
| 4 | USB Gadget not working (no UDC) | Change `dr_mode="host"` to `"otg"` | DTS patch |
| 5 | systemd-rfkill fails (symlink loop) | Fix `/var/lib` symlink chain | filesystem overlay |

### Medium Priority
| # | Issue | Fix | File |
|---|-------|-----|------|
| 6 | BFQ udev rule fails for MMC | Update sysfs path in rule | `10-bfq-sched.rules` |
| 7 | PipeWire DBus access denied | Fix DBus policy for pipewire-pulse | dbus config |
| 8 | Soundwire port count mismatches | Fix din/dout-ports in DTS | DTS patch |
| 9 | DSI error (status=5) | Investigate panel timing | DTS/driver |
| 10 | Skin thermal sensors read -40C | Disable uncalibrated zones | DTS |

### Tuning Opportunities
| # | Tunable | Current | Recommended | Why |
|---|---------|---------|-------------|-----|
| 11 | `vfs_cache_pressure` | 100 | 50 | Keep FS metadata cached, reduce SD reads |
| 12 | UCLAMP for emulators | min=0 | min=768 | Pin emulators to A77 big cores |
| 13 | `CONFIG_HZ` | 250 | 300 | Better frame pacing for 30/60 FPS |
| 14 | GPU governor | simple_ondemand | (fine) | Already appropriate |
| 15 | IRQ affinity for SDHCI | CPU0 only | spread | Reduce latency on CPU0 |
