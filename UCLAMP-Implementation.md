# UCLAMP / cgroupv2 Integration — Architecture Decision Record

> Documented 2026-03-18 from build host `kurarua:~/build/distribution/`
> Reference implementation: `uclamp` branch (RK3566 verified)

---

## 1. Problem Statement

ROCKNIX uses the `performance` CPU governor by default, running all cores at maximum frequency regardless of workload. This wastes power and thermal headroom on light workloads (8/16-bit emulators) while providing no benefit. On big.LITTLE SoCs, there is no scheduler hint to prefer big cores for demanding emulators — placement is arbitrary.

The `schedutil` governor can dynamically scale frequency based on utilization, but without utilization clamping (uclamp), it under-provisions CPU during emulator startup (causing frame drops) and has no mechanism to express per-workload demand levels.

## 2. Solution: uclamp + cgroupv2 Unified Hierarchy

**uclamp** (utilization clamping, Linux 5.3+) allows setting per-task or per-cgroup minimum and maximum utilization hints (0–1024 scale). The scheduler uses these to:

- Set a **frequency floor** for a task (uclamp_min) — prevents under-provisioning
- Set a **frequency ceiling** for a task (uclamp_max) — prevents over-provisioning
- Bias **core placement** on big.LITTLE — higher uclamp_min prefers big cores

**cgroupv2 unified hierarchy** is required for per-slice CPU controller delegation (e.g., capping background services via `background.slice`).

### Key Design Principles

1. **Graceful degradation**: All uclamp code gated behind `has_uclamp()` — devices without kernel support are unaffected
2. **No daemon**: `uclampset` wraps exec, values persist for process lifetime
3. **Composable**: `uclampset` chains with existing `taskset` (EMUPERF)
4. **Per-game override**: Users can set `uclamp_min` per platform/game via existing `get_setting` infrastructure

## 3. Device Readiness Matrix

### Kernel Config Status

| Device | SoC | CPU Topology | UCLAMP_TASK | CFS_BW | Buckets | Action |
|--------|-----|-------------|-------------|--------|---------|--------|
| RK3566 | RK3566 | 4×A55 (sym) | YES | YES | 5 | Reference — done |
| RK3588 | RK3588 | 4×A76 + 4×A55 | YES | YES | 20 | Add cmdline only |
| RK3326 | PX30 | 4×A35 (sym) | NO | NO | — | Enable all |
| RK3399 | RK3399 | 2×A72 + 4×A53 | NO | NO | — | Enable all |
| S922X | S922X | 4×A73 + 2×A53 | NO | YES | — | Enable uclamp |
| H700 | H700 | 4×A53 (sym) | NO | NO | — | Enable all |
| SDM845 | SDM845 | 4×A75 + 4×A55 | NO | NO | — | Enable all |
| SM8250 | SM8250 | 1×X1+3×A77+4×A55 | NO | NO | — | Enable all |
| SM8550 | SM8550 | 1×X3+2×A715+2×A710+3×A510 | NO | NO | — | Enable all |
| SM8650 | SM8650 | 1×X4+3×A720+2×A520 | NO | NO | — | Enable all |

### Kernel Symbols Required

```
CONFIG_UCLAMP_TASK=y
CONFIG_UCLAMP_TASK_GROUP=y          # cgroupv2 per-slice uclamp
CONFIG_UCLAMP_BUCKETS_COUNT=N       # 5 (symmetric), 10 (big.LITTLE), 20 (3+ clusters)
CONFIG_CFS_BANDWIDTH=y              # CPU bandwidth control for slices
CONFIG_CGROUP_SCHED=y               # Already present on all devices
CONFIG_FAIR_GROUP_SCHED=y           # Already present on all devices
```

### Boot Cmdline Addition

All devices: append `systemd.unified_cgroup_hierarchy=1` to EXTRA_CMDLINE in device `options`.

## 4. Architecture: Demand Tiers + Platform Scale

### Problem
A 3DS emulator is "heavy" everywhere, but "heavy" means different things on different hardware. On RK3566 (4×A55 @1.8GHz), 3DS needs maximum frequency. On SM8650 (X4 @3.3GHz), 3DS is routine.

### Solution: Two-layer mapping

**Layer 1 — Emulator demand tier** (intrinsic, defined once):
```
LIGHT       → 8/16-bit: NES, SNES, GB, GBA, Genesis, SMS, etc.
MEDIUM      → PS1, N64, DS, Dreamcast, Saturn, arcade
HEAVY       → PSP, GameCube, Wii, PS2, Xbox
VERY_HEAVY  → 3DS, PS3, Wii U, Switch, Vita
```

**Layer 2 — Platform scale** (per-device, in 010-governors quirk):
```
Each platform maps tier names to concrete uclamp_min values.
Weak hardware: HEAVY→768, VERY_HEAVY→1024
Strong hardware: HEAVY→256, VERY_HEAVY→384
```

### Per-Platform Tier Values

| Platform | LIGHT | MEDIUM | HEAVY | VERY_HEAVY | SoC Class |
|----------|-------|--------|-------|------------|-----------|
| RK3326 | 0 | 320 | 768 | 1024 | Weak symmetric A35 |
| H700 | 0 | 320 | 768 | 1024 | Weak symmetric A53 |
| RK3566 | 0 | 256 | 512 | 896 | Mid symmetric A55 |
| RK3399 | 0 | 256 | 448 | 768 | big.LITTLE A72+A53 |
| S922X | 0 | 240 | 420 | 700 | big.LITTLE A73+A53 |
| SDM845 | 0 | 220 | 384 | 640 | big.LITTLE A75+A55 |
| RK3588 | 0 | 200 | 384 | 512 | big.LITTLE A76+A55 |
| SM8250 | 0 | 180 | 340 | 480 | Tri-cluster X1+A77+A55 |
| SM8550 | 0 | 160 | 300 | 420 | Quad-cluster ARMv9 |
| SM8650 | 0 | 128 | 256 | 384 | Flagship ARMv9 |

### Resolution Order (in runemu.sh)

1. **Explicit per-game setting** — `get_setting "uclamp_min" PLATFORM GAME`
2. **Platform-scaled tier** — `get_system_uclamp_tier(PLATFORM)` → tier → platform value
3. **Platform default** — `UCLAMP_EMU_MIN` fallback

### System → Tier Mapping

```
LIGHT:
  gb, gbc, gba, nes, snes, sms, gamegear, genesis, megadrive, mastersystem,
  segacd, megacd, sega32x, atari*, coleco*, msx*, vectrex, wonderswan*,
  pcengine, tg16, supergrafx, supervision, channelf, odyssey2, intellivision

MEDIUM:
  psx, n64, nds, dreamcast, saturn, arcade, mame, fbneo, neogeo*,
  jaguar, 3do, pce-cd, segast-v

HEAVY:
  psp, gamecube, gc, wii, ps2, xbox

VERY_HEAVY:
  3ds, ps3, wiiu, switch, vita
```

## 5. Runtime Infrastructure

### Boot Flow (008-perfmode)

```bash
if has_uclamp; then
  # Delegate CPU controller to cgroupv2 hierarchy
  echo "+cpu" > /sys/fs/cgroup/cgroup.subtree_control
  echo "+cpu" > /sys/fs/cgroup/system.slice/cgroup.subtree_control
  # System defaults: full range for all tasks
  set_system_uclamp 0 1024
  # RT tasks get a floor to avoid priority inversion
  set_rt_uclamp 512
  # Background services capped
  set_slice_uclamp "background.slice" 0 "${UCLAMP_BG_MAX:-50}"
fi
```

### Helper Functions (099-freqfunctions)

```bash
has_uclamp()                    # Check /proc/sys/kernel/sched_util_clamp_min exists
set_system_uclamp(min, max)     # Write to /proc/sys/kernel/sched_util_clamp_{min,max}
set_rt_uclamp(min)              # Write to /proc/sys/kernel/sched_util_clamp_min_rt_default
set_slice_uclamp(slice, min, max) # Write to cgroupv2 cpu.uclamp.{min,max}
get_system_uclamp_tier(platform)  # Map platform name → demand tier
```

### Game Launch (runemu.sh)

```bash
if has_uclamp && command -v uclampset >/dev/null 2>&1; then
  TIER=$(get_system_uclamp_tier "${PLATFORM}")
  # Resolve: explicit setting > tier > platform default
  EMU_UCLAMP_MIN=$(resolve_uclamp_min "${PLATFORM}" "${ROMNAME}" "${TIER}")
  RUNTHIS="uclampset -m ${EMU_UCLAMP_MIN} -M ${EMU_UCLAMP_MAX} ${RUNTHIS}"
fi
```

### Systemd Slice (background.slice)

```ini
[Slice]
CPUWeight=50
```

## 6. Implementation Phases

### Phase 1: Kernel + cgroupv2 Foundation
- Enable kernel configs on all 8 missing devices
- Add cgroupv2 cmdline to all 9 missing devices
- Port 099-freqfunctions, 008-perfmode, background.slice from uclamp branch
- Verify with `tools/adjust_kernel_config` per device
- Build and test on RK3566 (reference)

### Phase 2: Per-Emulator Demand Tiers
- Implement `get_system_uclamp_tier()` in 099-freqfunctions
- Add UCLAMP_LIGHT/MEDIUM/HEAVY/VERY_HEAVY to all platform 010-governors
- Update runemu.sh with tier-based resolution
- Test on hardware: verify light games get low freq, heavy games get high freq

## 7. Critical Lessons Learned

### PMIC SLPPIN and Suspend (DO NOT USE PINCTRL FOR SUSPEND)

The upstream kernel's suspend/resume for RK817 is **register-only** (SLPPIN_SLP_FUN / SLPPIN_NULL_FUN). Muxing GPIO0_PA2 to PMU_SLEEP func during suspend engages hardware-level PMIC sleep mode, which cuts power to rails needed for the wakeup interrupt path. This prevents the power button from waking the device.

**Rule**: Pinctrl for SLPPIN is ONLY used in the shutdown path (GPIO output_low for SLPPIN_DN_FUN). Suspend/resume must remain register-only.

### cgroupv2 Session Freeze

systemd 255+ with cgroupv2 unified hierarchy tries to freeze user sessions before suspend (`SYSTEMD_SLEEP_FREEZE_USER_SESSIONS`). On ARM, this can prevent proper s2idle wakeup. Disable via systemd-suspend drop-in:
```ini
[Service]
Environment=SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false
```

## 8. References

- Linux uclamp documentation: `Documentation/scheduler/sched-util-clamp.rst`
- cgroupv2 CPU controller: `Documentation/admin-guide/cgroup-v2.rst`
- RK3566 uclamp branch: verified on Anbernic RG353P, Powkiddy RGB30
- PMIC powerpin PR: `nert-next/rk356x-powerpin-additions` (verified)
- Profiling data: `memory/v5-profiling-rgds.md` (schedutil 99.4% of performance governor)
