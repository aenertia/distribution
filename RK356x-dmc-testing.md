# RK3566 DMC Devfreq Validation Report

Devices: Anbernic RG353P (RK3566, 2GB LPDDR4), Powkiddy RGB30 (RK3566, 1GB)
Date: 2026-03-04
Power meter: FNIRSI FNB58 (BLE 4 sps on RG353P, USB HID 100 sps on RGB30)
Branch: `353p-dmc`

## Executive Summary

DDR memory controller devfreq (dynamic frequency scaling) has been
implemented and validated on RK3566 across 5 iterative builds. The governor
tunes DDR between 324–1056 MHz based on DFI utilization. Power profiling
reveals that **CPU frequency is the dominant power variable** (3.8W range)
while DDR frequency changes contribute only 0.08W — confirming the primary
benefit of DDR devfreq is bandwidth/latency matching for GPU-shared memory
workloads, not power savings.

Key outcomes:
- DDR devfreq is stable with tuned governor (15%/50ms) and 100ms HWFFC cooldown
- All 15 RK356x devices enabled via DTS patches and overlays
- ATF FSP-matched OPP table (324/528/780/1056 MHz) validated
- Memory manager tweaks (swappiness=30) prevent zram-induced crashes on emulator exit
- RGB30 thermal limit is 1416 MHz sustained CPU (passive cooling only)
- Battery-less USB operation causes brownout resets at >6W peak draw

## Build Matrix

| Build | OPP Table | Governor Tuning | Other |
|-------|-----------|-----------------|-------|
| 1 | 400/528/666/780/920 MHz | 25%/200ms | Initial |
| 2 | 324/528/780/1056 MHz | 25%/200ms | ATF FSP-matched |
| 3 | 324/528/780/1056 MHz | 15%/50ms | Tuned for GPU bursts |
| 4 | Same | Same | + RGA patch, schedutil, memory manager tweaks |
| 5 | Same | Same | + 100ms HWFFC transition cooldown |

## Commit History (353p-dmc)

```
ea762b4 linux: add 100ms DDR transition cooldown to prevent HWFFC crashes
68a8af4 linux: RK3566 schedutil default governor, memory manager tweaks
a61f4a6 wlroots: cherry-pick RGA hardware scaling for Rockchip testing
04f16b3 linux: tune DMC devfreq governor for GPU-shared memory workloads
4f8748b linux: update DMC OPP table to match ATF FSPs (324/528/780/1056 MHz)
5baa226 linux: add DMC devfreq DTS nodes, bump rkbin and ATF for RK356x
```

## ATF Firmware

- BL31: v1.45 (`rk3568_bl31_v1.45.elf`) — bumped from v1.44 for DCF fixes
- ATF DDR version reported: 0x102 (meets >= 0x101 requirement)
- Trained FSPs: 324 / 528 / 780 / 1056 MHz
- Boot rate: 528 MHz
- rkbin pin: `ef49d0c2` (2025-03-04)

Build 1's OPP table (400/528/666/780/920) only matched 2 of 4 FSPs (528, 780).
Three OPPs were disabled at probe: 400, 666, 920 MHz.

## Device Coverage

All 15 RK356x devices have DMC enabled via:
- Patch 1013: DMC node + OPP table in rk356x-base.dtsi (disabled by default)
- Patch 1014: Anbernic enablement via rk3566-anbernic-rgxx3.dtsi (7 devices)
- Patch 1015: Powkiddy X55/X35S enablement
- DTS overlay: rk3566-powkiddy-rk2023.dtsi (5 Powkiddy devices)
- DTS overlay: rk3568-anbernic-rg-ds.dts (RG-DS)

All use `center-supply = <&vdd_logic>` (DCDC_REG1, 500-1350mV).

---

## Full System Power Profile — RGB30

Measurement: FNIRSI FNB58 USB HID inline (100 sps, battery disconnected)
Build 5 firmware, 353p-dmc branch, kernel 6.18.13

### Power by Frequency Domain

| Domain | Range | Power Delta | Notes |
|--------|-------|-------------|-------|
| CPU (408–1608 MHz) | 2.01–5.80W | **3.79W** | Dominant |
| GPU (200–800 MHz) | 2.21–2.35W | **0.14W** | Minimal (workload was CPU-bound) |
| DDR (324–1056 MHz) | 2.31–2.40W | **0.08W** | Minimal (bandwidth, not power) |
| Baseline idle (all powersave) | 1.69W | — | Display + SoC floor |

### CPU Frequency vs Power

All 4 Cortex-A55 cores under busy-loop stress. GPU pinned 200 MHz, DDR 324 MHz.

| CPU Freq | Avg Power | Delta | Temp | Notes |
|----------|-----------|-------|------|-------|
| 408 MHz | 2.01W | — | 47°C | |
| 600 MHz | 2.20W | +0.19W | 49°C | |
| 816 MHz | 2.39W | +0.38W | 51°C | |
| 1104 MHz | 3.21W | +1.20W | 59°C | Nonlinear increase begins |
| 1416 MHz | 4.56W | +2.55W | 73°C | Max sustainable |
| 1608 MHz | 5.80W | +3.79W | 84°C | Throttled to 1416 MHz |
| 1800 MHz | RESET | — | >85°C | Thermal shutdown in <15s |

Power scales roughly quadratically with frequency above 1 GHz. The RGB30's
passive cooling cannot sustain 4-core load above 1416 MHz.

### GPU Frequency vs Power

Framebuffer write workload (dd urandom → /dev/fb0). CPU and DDR at powersave.

| GPU Freq | Avg Power | Delta |
|----------|-----------|-------|
| 800 MHz | 2.35W | — |
| 700 MHz | 2.27W | -0.09W |
| 600 MHz | 2.25W | -0.10W |
| 400 MHz | 2.22W | -0.13W |
| 300 MHz | 2.21W | -0.14W |
| 200 MHz | 2.21W | -0.14W |

GPU frequency has minimal power impact (0.14W range). The framebuffer write
workload is CPU-bound (urandom generation), not GPU compute-bound. A proper
shader stress test would show larger deltas but the Mali-G52 EE in the
RK3566 is a small GPU with limited power envelope.

### DDR Frequency vs Power

Memory bandwidth stress (dd zero → /dev/null). CPU and GPU at powersave.

| DDR Freq | Avg Power | Delta |
|----------|-----------|-------|
| 324 MHz | 2.31W | — |
| 528 MHz | 2.35W | +0.03W |
| 780 MHz | 2.40W | +0.08W |
| 1056 MHz | 2.37W | +0.06W |

DDR frequency has very small power impact (0.08W range). The 1056 MHz
reading is slightly lower than 780 MHz — the workload completes faster at
higher DDR rate, reducing sustained current draw. This confirms the primary
benefit of DDR devfreq is bandwidth matching for GPU-shared memory, not
power savings.

### Combined Scaling (governors active)

schedutil (CPU), simple_ondemand (GPU + DDR, 15%/50ms tuning)

| Workload | Avg Power | Min | Max |
|----------|-----------|-----|-----|
| Idle (ES menu) | 2.68W | 1.96W | 4.96W |
| Memory stress | 2.98W | 2.02W | 6.33W |
| CPU+mem combined | RESET | — | 6.55W peak |

---

## Power States — RG353P (2GB, with battery, BLE measurement)

| State | DDR Freq | Avg Current | Avg Power | Notes |
|-------|----------|-------------|-----------|-------|
| Power off | — | 0.003A | 0.015W | PMIC quiescent |
| Pre-boot (charging) | — | 0.128A | 0.65W | Battery trickle charge |
| BROM/SPL | — | 0.147A | 0.75W | |
| DDR init | 528 MHz | 0.208A | 1.05W | |
| U-Boot | — | 0.294A | 1.49W | |
| Kernel peak | — | 0.513A | 2.58W | Build 1 |
| First-boot peak | — | 1.35A | 6.55W | Build 3, init + DMC scaling |
| Idle (screen+wifi) | 324 MHz | 0.330A | 1.67W | Build 2 |

## Power States — RGB30 (1GB, no battery, USB HID measurement)

| State | DDR Freq | Avg Current | Avg Power | Notes |
|-------|----------|-------------|-----------|-------|
| BROM standby | — | 0.178A | 0.90W | True SoC quiescent |
| Boot peak (+10s) | — | 0.968A | 4.76W | DDR init + kernel |
| Idle (screen, no wifi) | 324 MHz | 0.168A | 0.85W | True SoC idle |
| Idle (screen+wifi) | 324 MHz | ~0.44A | ~2.2W | |
| All-powersave baseline | 324 MHz | 0.325A | 1.69W | Profiling reference |

### RG353P vs RGB30 Baseline Comparison

| Metric | RGB30 (no battery) | RG353P (battery) | Delta |
|--------|-------------------|-------------------|-------|
| BROM standby | 0.178A / 0.90W | 0.209A / 1.06W | +0.16W charge circuit |
| Idle (screen on) | 0.168A / 0.85W | 0.469A / 2.34W | +1.49W charge + PMIC |

The RG353P's battery charging circuit adds ~1.5W constant overhead, making
the RGB30 significantly better for isolating DDR frequency scaling power
deltas.

## Power States — RG353P Direct PD (no dock, no DMC, battery charging)

Measurement: FNIRSI FNB58 USB HID inline (100 sps), direct PD→FNB58→353P
chain without USB dock current limiting. Battery charging throughout.
Build: `rga-output-scale-settings` branch (no DMC patches), kernel 6.18.13.
Date: 2026-03-05

| State | Avg Power | Avg V | Avg A | Min | Max | Duration |
|-------|-----------|-------|-------|-----|-----|----------|
| Boot (BROM→kernel→init) | 7.25W | 4.93V | 1.47A | 6.34W | 8.23W | 181s |
| Idle + charging (no WiFi) | 6.39W | 4.97V | 1.29A | 4.50W | 8.33W | 269s |
| Idle + WiFi + charging @58% | 6.38W | 4.97V | 1.28A | 4.86W | 8.47W | 189s |
| PPSSPP Vulkan (GOW) + charging | 5.75W | 5.00V | 1.15A | 2.49W | 8.46W | 533s |
| Dolphin half-scale (SSBM) + charging | 4.51W | 5.06V | 0.89A | 2.92W | 8.32W | 343s |

### Observations

**Direct PD vs dock-gated measurement**: Previous 353P measurements through
the USB dock showed lower power (idle 1.67W) because the dock limited
current to ~500mA. Direct PD removes this limit, showing true system +
charging draw. The battery charging circuit adds 3-4W constant overhead.

**PPSSPP vs Dolphin power**: PPSSPP GOW (5.75W avg) drew more than Dolphin
SSBM at half-scale (4.51W avg). The output scale reduces GPU shader work
by 4x (320x240 vs 640x480), which explains the lower Dolphin power despite
SSBM being a heavier title. This confirms the output scale feature delivers
real power savings.

**Thermal resets**: Two thermal resets occurred during this session:
1. PPSSPP GOW at full resolution — reset after ~9 minutes, SoC reached ~88°C
2. Dolphin SSBM at half-scale — reset after ~6 minutes at 88.7°C
Both caused by cumulative heat from battery charging (4W) + emulation.
Not reproducible without battery charging overhead.

**No DMC baseline**: DDR frequency fixed at boot rate (no devfreq governor).
This provides a reference for comparison with DMC-enabled builds where DDR
scales between 324-1056 MHz.

### Comparison: Direct PD vs Dock-Gated (RG353P)

| State | Direct PD (charging) | Direct PD (full) | Dock-Gated | Notes |
|-------|---------------------|------------------|------------|-------|
| Idle (screen+wifi) | 6.38W | 1.58W | 1.67W | Charge adds 4.8W |
| Boot peak | 8.23W | — | 6.55W | |
| N64 (DK64) native | — | 4.60W | — | |
| N64 (DK64) half scale | — | 3.16W | — | VOP2 upscale, -31% |
| Dolphin SSBM half scale | 4.51W | 2.44W | 3.50W | |
| Lumines native | — | 1.72W | — | CPU-bound |
| Lumines half scale | — | 1.64W | — | Minimal GPU savings |
| PPSSPP GOW (charging) | 5.75W | — | — | Thermal reset |

Full battery idle (1.58W) vs charging idle (6.38W) confirms battery
charging circuit adds **4.8W constant overhead**. All emulation power
data at full battery is the true system draw without charge load.

---

## Emulation Power Profiles (Dolphin — Super Smash Bros Melee, RG353P)

### Full resolution, default rendering

| Build | DDR Pattern | Avg Power | CPU Load |
|-------|-------------|-----------|----------|
| 2 (25%/200ms) | 324 MHz stuck | 2.95W | 4.7 |
| 2 (perf override) | 1056 MHz locked | 4.40W | — |
| 3 (15%/50ms) | 324/528/1056 active | 3.50W | ~4.0 |
| 4 (+ schedutil) | 324/528/1056 active | 3.00W | 2.37 |

### Peak gameplay snapshot (Build 4, GPU active at 800 MHz)

| Component | Freq | Notes |
|-----------|------|-------|
| DDR | 1056 MHz | Max, under memory pressure |
| GPU | 800 MHz | Max, hardware rendering |
| CPU | 1800 MHz | Near max |
| Power | 5.2W peak, 6.3W absolute max | Combined GPU+CPU+DDR |

### DDR frequency pattern during gameplay (Build 3)
```
1056 MHz ████████████████████  (9 samples — peak DDR demand)
 324 MHz ██████████████        (6 samples — idle between frames)
 528 MHz ████████████          (5 samples — moderate demand)
```

---

## DDR Frequency Scaling Behavior

### Build 1 (400/528/666/780/920 MHz OPPs, 25%/200ms)
- Only 528/780 MHz available (3 OPPs disabled by ATF)
- **0 transitions** in 8 minutes — stuck at 528 MHz
- Governor never triggered: no low-power OPP to scale down to

### Build 2 (324/528/780/1056 MHz OPPs, 25%/200ms)
- All 4 OPPs available
- **1 transition** total (528 -> 324 at boot, stayed there)
- Governor too conservative: 25% DFI utilization threshold never hit
- DDR stuck at 324 MHz even during Dolphin (GameCube) emulation
- Manually forcing performance governor (1056 MHz) confirmed smoother gameplay

### Build 3 (324/528/780/1056 MHz OPPs, 15%/50ms)
- All 4 OPPs available
- **220+ transitions** in first session
- Active scaling: 324 <-> 528 <-> 1056 MHz during gameplay
- Governor correctly responds to GPU memory bursts
- 780 MHz OPP never used (governor jumps 528 -> 1056 directly)

### Build 4 (+ memory manager tweaks)
- 514 transitions in 15+ minutes
- Clean emulator exits (2x) — no crash on exit
- swappiness=30 prevented zram compression storm during teardown
- 0 bytes swapped despite 666MB used

### Build 5 (+ 100ms transition cooldown)
- 110 transitions in 5 min on RGB30
- 90 transitions in 6 min on RGB30 second session
- Cooldown prevents rapid back-to-back HWFFC transitions

---

## Crash / Reboot Events and Analysis

### Crash Event Log

| # | Build | Device | Context | Power | Cause |
|---|-------|--------|---------|-------|-------|
| 1 | 3 | RG353P | Emulator exit (hotkey combo) | 0.40A→0A instant | DDR downscale + zram storm |
| 2 | 2 | RG353P | Governor switch during gameplay | — | DDR transition |
| 3 | 4 | RG353P | Melee stage load | — | Rapid 324→1056 DDR upscale |
| 4 | 4 | RG353P | PPSSPP Vulkan gameplay | — | Combined GPU+DDR |
| 5 | 5 | RGB30 | NFS mount, 0.49A | 0.5A→0.02A | USB PD hub current limit |
| 6 | 5 | RGB30 | CPU 1800 MHz stress | 3.56W avg, 5.02W peak | Thermal shutdown >85°C |
| 7 | 5 | RGB30 | CPU+mem combined stress | 3.44W avg, 6.55W peak | Brownout at 53°C |

### Reset Precondition Analysis (from FNB58 100 sps data)

**Reset 6 — CPU 1800 MHz thermal shutdown**:
- Phase: CPU frequency sweep, all 4 cores busy-loop at 1800 MHz
- Duration: ~15s into the test window
- Final 2s average: 3.56W @ 5.10V
- Peak before crash: 5.02W
- Preceding temp: 84°C at 1608 MHz (10s cooldown between steps)
- Post-crash: power drops to 1.71W (reboot baseline)
- Cause: cumulative thermal load. Despite 10s cooldown between OPPs,
  the SoC never cooled below 73°C after 1416 MHz. 1800 MHz added >1W
  instantaneously, pushing past the thermal trip point.

**Reset 7 — Combined CPU+memory brownout**:
- Phase: Phase 5 combined (4-core busy-loop + dd memory stress + governor scaling)
- Duration: ~15s
- Final 2s average: 3.44W @ 5.11V
- Peak before crash: **6.55W**
- Starting temp: only 53°C (cooled from Phase 4 DDR sweep)
- Post-crash: power drops to 1.72W (reboot baseline)
- Cause: **NOT thermal** — temp was well within limits. The 6.55W peak
  power spike indicates a PMIC overcurrent or USB power delivery brownout.
  The RGB30 without battery has no capacitive buffer for transient current
  surges during combined CPU load + HWFFC DDR transitions.

### Root Cause Classification

| Category | Events | Mitigation |
|----------|--------|------------|
| Thermal | #6 | Thermal governor limits; passive cooling limit is ~4.5W sustained |
| DDR HWFFC collision | #1, #2, #3 | 100ms transition cooldown (Build 5) |
| Zram storm | #1 | swappiness=30, page-cluster=0 (Build 4) |
| USB power brownout | #5, #7 | Battery buffer required; USB hub current limit |
| Combined GPU+DDR | #4 | Partially mitigated by cooldown |

### Contributing Factors

1. `vm.swappiness=100` with zram — aggressively targets GPU buffers via MGLRU
2. `page-cluster` default causes zram readahead bursts during GPU fault-ins
3. Memory compaction under load causes THP promotion races + voltage spikes
4. Rapid DDR transitions during burst allocation (no cooldown)
5. RGB30 without battery has no capacitive buffer for transients

### Mitigations Applied

| Build | Mitigation | Result |
|-------|------------|--------|
| 4 | Swappiness 100→30, page-cluster=0, watermark=150 | Fixed emu exit crashes |
| 4 | Compaction guard (skip under high load) | Reduced voltage spikes |
| 4 | schedutil CPU governor | Lower load, better freq pacing |
| 5 | 100ms HWFFC transition cooldown | Prevents rapid oscillation |

---

## Governor Tuning Rationale

| Parameter | Build 1-2 | Build 3+ | Why |
|-----------|-----------|----------|-----|
| polling_ms | 200 | 50 | Catch GPU memory bursts (bursty, not sustained) |
| upthreshold | 25% | 15% | GPU shared memory generates <25% DFI utilization even under load |
| downdifferential | 15 | 10 | Scale down when util < 5% (tight hysteresis) |
| cooldown_ms | — | 100 | Prevent HWFFC collisions during burst allocation |

The RK3566 GPU shares system RAM (no dedicated VRAM). GPU memory access is
bursty — high bandwidth in short bursts that average below conservative
thresholds over long polling windows. The 50ms/15% combination catches these
bursts and scales DDR appropriately.

The 100ms cooldown prevents back-to-back MCU HWFFC (Hardware Fast Frequency
Change) operations which can cause PMIC resets when colliding with heavy
memory allocation.

---

## Output Scale Power Impact (RG353P, full battery, no DMC)

Sway output scale reduces the logical resolution emulators render at.
VOP2 display controller upscales to the panel via KMS plane scaling.

| Title | Scale | Avg Power | Temp | GPU-bound? | Savings |
|-------|-------|-----------|------|------------|---------|
| N64 DK64 | Native | 4.60W | 86°C | Yes | — |
| N64 DK64 | Half | 3.16W | 67°C | Yes | **-1.44W (31%)** |
| Dolphin SSBM | Half | 2.44W | 61°C | Yes | — |
| Lumines | Native | 1.72W | 57°C | No (CPU) | — |
| Lumines | Half | 1.64W | 56°C | No (CPU) | -0.08W (5%) |

**Conclusions**:
- GPU-heavy titles see 31% power savings and 19°C thermal reduction
- CPU-bound titles see negligible savings — the bottleneck is CPU, not rendering
- VOP2 plane scaling (1:8–8:1 supported) handles all upscaling — RGA never engages
- RetroArch always submits display-matched buffers regardless of `video_ctx_scaling`
- All Wayland apps (RetroArch, PPSSPP, PICO-8, Dolphin) create surfaces matching output

### Vulkan ICD Fix Impact

Both PPSSPP and Dolphin confirmed using Vulkan after VK_ICD_FILENAMES fix:
- Dolphin window title shows "Vulkan" backend
- PPSSPP process env shows `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/mali.json`
- `FailedGraphicsBackends` empty (no Vulkan init failure)
- Fix is safe across all 10 device targets (validated against all OPTIONS files)

---

## rkbin Bump Details

rkbin pinned to `ef49d0c2` (2025-03-04) for rk3568_bl31_v1.45:
- "Add support ddr ecc poison by dcf" — DCF mechanism used by DMC driver
- "Disable monitor when system sleep" — DFI suspend fix
- "Only enable one ca odt in same channel" — LP4/LP4X multi-CS stability

Cascading changes from rkbin bump:
- RK3566: BL31 v1.44→v1.45, BL32 v2.14→v2.15
- RK3588: BL31 v1.47→v1.49, DDR lp4_2112/lp5_2400 v1.18
  (old lp4_1848/lp5_2736 variant discontinued upstream Dec 2024)
- RK3326/RK3399: unchanged (files still present)
- `ddrbin_tool` binary replaced with `ddrbin_tool.py` (python3 in post_unpack)

---

## Technical Details

### DMC Driver Architecture
- BSP V2 SIP protocol with MCU-based DCF
- SET_RATE returns -6 ("started, wait for MCU completion")
- MCU performs HWFFC (Hardware Fast Frequency Change)
- Completion via GIC_SPI 10 IRQ
- Shared memory at SIP_SHARE_MEM for frequency parameters
- No `reg` property needed (SIP shared memory, not direct register access)
- Clock: `<&cru CLK_DDR1X>` for rate readback (not scmi_clk — 0=CPU, 1=GPU)

### DTS Node Structure
- DMC node in rk356x-base.dtsi (shared by all RK356x), `status = "disabled"`
- Per-device enablement adds `center-supply = <&vdd_logic>` + `status = "okay"`
- OPP table in base dtsi, ATF disables non-matching FSPs at probe
- DTS overlays applied AFTER patches (rsync in post_patch)

### Memory Manager Tweaks
- `vm.swappiness=30` — prevents aggressive zram targeting of GPU buffers
- `vm.page-cluster=0` — no zram readahead bursts during GPU fault-ins
- `vm.watermark_scale_factor=150` — earlier kswapd wakeup
- Compaction guard — skip `compact_memory` when load >= nproc

---

## Boot Timing

### RG353P Build 3 (BLE 4 sps)
| Phase | Elapsed | Duration |
|-------|---------|----------|
| Power off | 0.0s | 1.5s |
| BROM spike | +1.5s | — |
| Peak boot power (5.26W) | +16s | — |
| Boot-to-idle settled | +54s | ~54s total boot |

### RGB30 Build 5 (USB HID 100 sps)
| Phase | Elapsed | Power |
|-------|---------|-------|
| BROM standby | 0s | 0.90W |
| SPL/DDR init | +0s | 1.13W |
| U-Boot | +5s | 1.41W |
| Kernel peak | +10s | 4.76W |
| Init settling | +30s | 2.81W |
| Idle | +50s | 0.85W |

---

## FNB58 Power Meter

### Setup
- Device: FNIRSI FNB58 (firmware V1.1.1)
- USB VID:PID: `0x2E3C:0x5558`
- Host: emiemi (Bazzite/Fedora Atomic)
- Logger: `fnb58_usb.py` daemon with auto-reconnect, CSV rotation, UDP markers
- Service: systemd user service with `loginctl enable-linger`
- Source: https://codeberg.org/aenertia/fnirsi-fnb58

### Measurement Methods
| Method | Rate | Device | Notes |
|--------|------|--------|-------|
| BLE | 4 sps | RG353P | Wireless, battery in circuit, BLE drops under high current |
| USB HID inline | 100 sps | RGB30 | Battery disconnected, inline measurement, reliable |

### Marker Correlation
UDP marker injection (port 5858) labels power CSV rows with phase
identifiers (e.g. `MARKER:PHASE:2:CPU_1416MHz_START`). Both logger host
and device use NTP; CSV timestamps correlate directly with `journalctl`
wall clock on the device.

---

## Open Items

1. **780 MHz OPP never used** — governor jumps 528→1056 directly. May want
   to investigate if intermediate step would reduce transition latency.

2. **GPU power profile incomplete** — framebuffer write workload is CPU-bound.
   Need a proper GL shader stress test to measure true GPU power envelope.

3. **Emu exit crashes: FIXED** by memory manager tweaks (swappiness=30).

4. **Emu load crashes: MITIGATED** by 100ms cooldown. Needs more soak testing.

5. **RGB30 USB power stability** — battery-less operation through USB hub
   causes brownout resets at >6W peak draw. Direct PD or battery-equipped
   devices are more stable.

6. **1800 MHz not achievable** — RGB30 passive cooling cannot sustain 4-core
   load at max frequency. schedutil naturally avoids this but max OPP may
   need capping for RGB30 or thermal governor tuning.

7. **Suspend/resume not tested** — profiler crashed before Phase 6. Needs
   separate test to verify DDR devfreq survives suspend/resume cycle (DFI
   PM ops in patch 1011 handle this).

8. **EmulationStation BATOCERA hostname default** — ES hardcodes "BATOCERA"
   as default hostname in SystemConf.cpp. After hard crash + config recovery,
   this surfaces as the visible hostname. Filed as separate issue; fix
   submitted in `failsafe-corrupt-fix` branch for config recovery logic.

## RGB30 DMC+PM Profile Comparison (2026-03-05)

Second RGB30 profile run with all PM improvements enabled (DMC devfreq,
GPU coarse_demand, TEO idle, energy model, 100ms polling). Battery
connected and charging (~4.66W overhead derived from GPU sweep baseline).

### CPU Sweep (adjusted for charging)

| Freq | No PM | DMC+PM (adj) | Delta |
|------|-------|-------------|-------|
| 408 MHz | 2.01W | 2.62W | +0.61W (charge current artifact) |
| 816 MHz | 2.39W | 2.78W | +0.39W (charge current artifact) |
| 1104 MHz | 3.21W | 2.96W | **-0.25W** |
| 1416 MHz | 4.56W | 2.98W | **-1.59W** |
| 1608 MHz | 5.80W | 3.75W | **-2.05W** |

### GPU + DDR Sweeps: Neutral (±0.08W)

No regression from PM changes. GPU coarse_demand and DDR devfreq
overhead is within measurement noise.

### Combined Workloads

| Workload | No PM | DMC+PM (adj) | Delta |
|----------|-------|-------------|-------|
| Idle (governors active) | 2.68W | 2.41W | **-0.27W (-10%)** |
| Memory stress | 2.98W | 2.49W | **-0.49W (-16%)** |
| Combined CPU+mem | RESET | RESET | Same crash pattern |

### Crash Pattern

Both profile runs crashed at the same points:
- CPU 1800 MHz stress (thermal, passive cooling limit)
- Phase 5 combined CPU+mem (brownout from current spike)

Battery charging adds thermal load that makes these crashes more likely.
The 353P with undervolt DTBO at full battery survived N64 sustained
gameplay at 62°C — the RGB30 needs either battery disconnect for
profiling or undervolt for stability.
