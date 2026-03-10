# RK3566 Power Profiling: DMC Devfreq, Power Management, and Undervolt on ROCKNIX Handheld Devices

**Author**: Joel Wiramu Pauling
**Date**: 2026-03-04 to 2026-03-06
**Devices**: Powkiddy RGB30 (1GB), Anbernic RG353P (2GB)
**Distribution**: ROCKNIX (`353p-dmc` branch, kernel 6.18.13)
**Instrument**: FNIRSI FNB58 USB power meter (100 sps USB HID, 4 sps BLE)

## 1. Abstract

This report presents 30 hours of continuous 100 sps power measurement across 15 sessions on two RK3566-based gaming handhelds. Three frequency domains were independently characterized: CPU (408–1800 MHz, 3.79W range), GPU (200–800 MHz, 0.14W range), and DDR memory controller (324–1056 MHz, 0.08W range). One-way ANOVA confirms CPU frequency as the dominant power variable (F(5,7590) = 28509.3, p < 0.0001, η² = 0.95), with GPU and DDR reaching statistical significance but with negligible practical effect sizes (η² = 0.058 and 0.015 respectively). DDR devfreq's primary benefit is bandwidth matching for GPU-shared memory workloads, not power savings. Five firmware builds were iteratively validated, evolving from zero DDR transitions (Build 1) to stable scaling with 100ms HWFFC cooldown (Build 5). Seven crash events were categorized across four root causes: thermal shutdown, HWFFC collision, zram compression storm, and USB power brownout. An optional undervolt DTBO provides 1W savings and 17°C thermal reduction at high CPU frequencies, enabling sustained 1800 MHz operation where stock voltages cause thermal shutdown. Suspend power measured at 0.09W with DMC devfreq, DFI monitoring, and TEO idle governor all surviving the suspend/resume cycle.

## 2. Introduction

### 2.1 Motivation

RK3566-based gaming handhelds run demanding emulators (N64, GameCube, PSP) that simultaneously stress CPU, GPU, and DDR subsystems. Prior to this work, DDR frequency was locked at the boot rate with no runtime scaling. Users reported thermal shutdowns during heavy emulation, and no quantitative power characterization existed for this SoC in handheld form factor.

### 2.2 Scope

- **Independent variables**: CPU frequency (7 OPPs, 408–1800 MHz), GPU frequency (6 OPPs, 200–800 MHz), DDR frequency (4 OPPs, 324–1056 MHz)
- **Configurations**: 5 firmware builds, 3 power management configurations (no PM, DMC+PM, DMC+PM+UV L3)
- **Devices**: RGB30 (battery-less inline measurement) and RG353P (battery with charging overhead)
- **Workloads**: Synthetic stress (busy-loop, dd, urandom→fb0) and real emulation (Dolphin SSBM, N64 SSB, PPSSPP GOW, Lumines)

### 2.3 Contributions

1. First quantitative per-domain power characterization of RK3566 in gaming handheld form factor
2. Empirical demonstration that DDR devfreq saves 0.08W while providing bandwidth matching
3. Governor tuning methodology driven by crash analysis at 100 sps temporal resolution
4. Open-source profiling toolchain: FNB58 daemon logger, UDP marker injection, automated 6-phase profiling script

## 3. Hardware

### 3.1 RK3566 SoC

- Quad Cortex-A55 (ARMv8.2-A), up to 1992 MHz (turbo)
- Mali-G52 EE (Bifrost, single execution engine), 200–800 MHz
- DDR4/LPDDR4/LPDDR4X controller, 324–1056 MHz (ATF FSP-trained)
- Shared memory architecture: GPU uses system RAM, no dedicated VRAM
- DFI (DDR Frequency Interface) monitors memory utilization for devfreq

### 3.2 Power Domains

| Domain | Regulator | Status During Idle |
|--------|-----------|-------------------|
| CPU | vdd_cpu (SYR827, 712–1390 mV) | Active |
| GPU (PD_GPU) | vdd_gpu (DCDC_REG2, 500–1350 mV) | **OFF** (coarse_demand) |
| DDR (center) | vdd_logic (DCDC_REG1, 500–1350 mV) | Active |
| VOP2 (PD_VO) | — | Active (display) |
| VENC (PD_VENC) | — | **OFF** |
| VDEC (PD_VDEC) | — | **OFF** |
| VPU (PD_VPU) | — | **OFF** |
| RGA (PD_RGA) | — | **OFF** |

Power domain gating verified via `/sys/kernel/debug/pm_genpd/pm_genpd_summary` — unused blocks (VENC, VDEC, VPU, RGA) confirmed OFF during gameplay.

### 3.3 Test Devices

| Specification | Powkiddy RGB30 | Anbernic RG353P |
|---------------|---------------|-----------------|
| Panel | 720×720 (square) | 640×480 |
| RAM | 1 GB LPDDR4 | 2 GB LPDDR4 |
| Cooling | Passive only | Passive only |
| Battery | Disconnectable (used for inline measurement) | Fixed 3200 mAh |
| Charging overhead | N/A (battery removed) | ~4.7W constant |

### 3.4 Thermal Design

- No active cooling on either device
- TSADC hardware shutdown: 95°C
- ROCKNIX thermal trips: CPU 83°C/88°C passive, GPU 80°C/88°C passive (raised from kernel defaults of 70°C/75°C)
- Thermal governor: step_wise (incremental frequency throttling)

## 4. Firmware and Kernel

### 4.1 ATF and rkbin

| Component | Version | Notes |
|-----------|---------|-------|
| rkbin | `ef49d0c2` (2025-03-04) | Bumped for DCF fixes |
| BL31 (RK3566) | v1.45 | From v1.44, adds DCF/DFI fixes |
| BL32 (RK3566) | v2.15 | From v2.14 |
| ATF DDR version | 0x102 | Minimum 0x101 required for DMC |
| Trained FSPs | 324/528/780/1056 MHz | Reported by ATF at boot |

Key ATF v1.45 changes:
- DCF (DDR Change Frequency) mechanism support used by DMC driver
- DFI monitor disable during system sleep
- LP4/LP4X single-channel ODT fix for multi-CS stability

### 4.2 Kernel Patches (6.18.13)

| Patch | Description |
|-------|-------------|
| 1011 | DFI PM: re-prime utilization baseline counters on enable/resume |
| 1012 | RK3568 DMC devfreq driver: BSP V2 SIP protocol, MCU-based HWFFC |
| 1013 | DMC DTS node + OPP table in rk356x-base.dtsi (disabled by default) |
| 1014 | Anbernic RGxx3 DMC enablement (7 devices) |
| 1015 | Powkiddy X55/X35S DMC enablement |
| 1016 | CPU energy model (dynamic-power-coefficient=138, sustainable-power=1000) |
| 0008 | Mali-bifrost DTS: GPU power_policy=coarse_demand, power models |
| 1001 | CPU idle states: PSCI CPU_SLEEP (100µs entry, 120µs exit) |
| 0001 | 1992 MHz CPU OPP with turbo-mode flag |

### 4.3 Build Evolution

| Build | OPP Table | Governor | Cooldown | Memory Mgr | Transitions | Outcome |
|-------|-----------|----------|----------|------------|-------------|---------|
| 1 | 400/528/666/780/920 | 25%/200ms | — | Default | 0 (3 OPPs disabled) | No scaling |
| 2 | 324/528/780/1056 | 25%/200ms | — | Default | 1 (stuck 324) | Too conservative |
| 3 | 324/528/780/1056 | 15%/50ms | — | Default | 220+ | Active, crashes on exit |
| 4 | 324/528/780/1056 | 15%/50ms | — | Tuned | 514 | Exits stable, load crashes |
| 5 | 324/528/780/1056 | 15%/100ms | 100ms | Tuned | 100 | **Level 3 survived** |

### 4.4 Governor Tuning

| Parameter | Build 1–2 | Build 3 | Build 5 | Rationale |
|-----------|-----------|---------|---------|-----------|
| polling_ms | 200 | 50 | **100** | 50ms caught bursts but caused level-load crashes |
| upthreshold | 25% | **15%** | 15% | GPU shared memory generates <25% DFI utilization |
| downdifferential | 15 | **10** | 10 | Scale down at <5% utilization |
| cooldown_ms | — | — | **100** | Prevents HWFFC collisions during burst allocation |

Combined 100ms polling + 100ms HWFFC cooldown = 200ms minimum transition spacing.

### 4.5 Memory Manager Tuning

| Parameter | Default | Tuned | Rationale |
|-----------|---------|-------|-----------|
| vm.swappiness | 100 | **30** | Prevents zram targeting GPU buffers via MGLRU |
| vm.page-cluster | 3 | **0** | Eliminates zram readahead bursts during GPU fault-ins |
| vm.watermark_scale_factor | 10 | **150** | Earlier kswapd wakeup prevents exhaustion bursts |
| Compaction | Always | **Guard** | Skip when system load ≥ CPU count |

### 4.6 Power Management Changes

| Change | Effect |
|--------|--------|
| GPU coarse_demand (was always_on) | GPU cores power down between frame submissions |
| TEO CPU idle governor | Timer-event prediction for bursty gaming workloads |
| CPU energy model (patch 1016) | DTS-correct but inert on SCMI systems (ATF doesn't implement est_power_get) |
| mali-bifrost devicetree backend | Fixes GPU clock/power domain coordination on Rockchip |

**Note on cpufreq-dt vs SCMI**: `CONFIG_CPUFREQ_DT=y` is compiled but never probes on RK3566 — SCMI cpufreq wins because CPU nodes use `clocks = <&scmi_clk 0>`. cpufreq-dt is retained for arm32 first-stage build compatibility. SCMI is required for DMC coordination, PVTM calibration, and secure PMIC voltage sequencing.

## 5. Methodology

### 5.1 Measurement Instrument

FNIRSI FNB58 USB power meter:
- USB HID: 100 samples/second (4 samples per 64-byte packet)
- Voltage accuracy: ±0.01V, Current accuracy: ±1 mA
- Firmware V1.1.1
- Protocol: hidraw-based Linux daemon with CRC-8 (poly=0x39, init=0x42)
- Public repository: https://codeberg.org/aenertia/fnirsi-fnb58

### 5.2 Measurement Topologies

**RGB30 inline** (primary): PD adapter → FNB58 → RGB30 (battery disconnected). Measures true SoC power without charging overhead. Used for frequency domain isolation.

**RG353P inline** (validation): PD adapter → FNB58 → RG353P. Measures system + battery charging. Charging overhead derived from GPU sweep baseline (identical workload across runs).

### 5.3 Charging Overhead Derivation

GPU sweep phases produce identical system workload across all runs. The power delta between battery-connected and battery-disconnected runs at identical GPU frequencies gives the charging overhead:

| Run | GPU 800 MHz avg | Offset |
|-----|----------------|--------|
| Run 1 (no battery) | 2.344W | 0 (reference) |
| Run 2 (charging, no UV) | 7.008W | **+4.664W** |
| Run 3 (charging, UV L3) | 6.266W | **+3.922W** |

The lower offset in Run 3 reflects reduced system power from undervolting, causing the charge controller to draw more current.

**Caveat**: Charging current varies inversely with system load — when the SoC draws less, the charger draws more. This introduces systematic error in adjusted low-frequency readings (appearing ~0.5W higher than true system power at 408 MHz).

### 5.4 Profiling Protocol

Automated 6-phase script (`rgb30_profile.sh`):

| Phase | Duration | Workload | Pinned |
|-------|----------|----------|--------|
| 1. Baseline idle | 30s | None (ES menu) | All powersave |
| 2. CPU sweep | 15s×7 + 10s cooldown | 4-core busy-loop | GPU+DDR low |
| 3. GPU sweep | 15s×6 | urandom→/dev/fb0 | CPU+DDR low |
| 4. DDR sweep | 15s×4 | dd zero→/dev/null | CPU+GPU low |
| 5. Combined | 15s×3 | Idle, memstress, combined | Governors active |
| 6. Suspend/resume | Variable | echo mem > /sys/power/state | — |

### 5.5 Marker Correlation

UDP marker injection on port 5858 labels CSV rows with phase identifiers. Both logger host and device use NTP wall-clock for correlation. Format: `MARKER:PHASE:N:DOMAIN_FREQMHz_START/END`.

### 5.6 Statistical Methods

| Analysis | Method | Purpose |
|----------|--------|---------|
| Per-phase power | Mean, SD, 95% CI (n≈1200-2800) | Base statistics |
| Frequency vs power | One-way ANOVA + η² | Significance and effect size |
| CPU power model | Quadratic regression P=af²+bf+c | Dynamic power scaling model |
| Undervolt impact | Cohen's d effect size | Practical significance |
| Cross-run comparison | Charging-adjusted means | Configuration impact |

First 3 seconds of each phase trimmed to remove frequency-transition transients.

### 5.7 Data Inventory

15 CSV sessions totaling ~10.8 million samples (~30 hours at 100 sps). Three primary profile runs:

| Run | Device | Battery | Configuration | Phases Completed |
|-----|--------|---------|---------------|-----------------|
| 1 | RGB30 | Disconnected | No PM changes | 5 of 6 (combined crashed) |
| 2 | RGB30 | Charging | DMC+PM, no UV | 5 of 6 (combined crashed) |
| 3 | RGB30 | Charging | DMC+PM+UV L3 | **6 of 6 (complete)** |

## 6. Results

### 6.1 Baseline Power Budget

RGB30 idle power breakdown (battery disconnected):

| State | Power | Source |
|-------|-------|--------|
| BROM standby | 0.90W | Pre-boot |
| SoC idle (screen on, no WiFi) | 0.85W | Display + SoC floor |
| All powersave (profiling baseline) | 1.69W ± 0.10 (95% CI ±0.004) | Phase 1 (n=2792) |
| Governors active idle | 2.68W | Phase 5 idle |

### 6.2 CPU Frequency vs Power

One-way ANOVA: **F(5, 7590) = 28509.3, p < 0.0001, η² = 0.949**

CPU frequency explains 94.9% of power variance — the dominant power variable.

| CPU Freq | Mean Power | SD | 95% CI | n | Temp |
|----------|-----------|-----|--------|---|------|
| 408 MHz | 2.012W | 0.069 | ±0.004 | 1296 | 47°C |
| 600 MHz | 2.202W | 0.073 | ±0.004 | 1280 | 49°C |
| 816 MHz | 2.399W | 0.103 | ±0.006 | 1268 | 51°C |
| 1104 MHz | 3.224W | 0.143 | ±0.008 | 1256 | 59°C |
| 1416 MHz | 4.600W | 0.262 | ±0.015 | 1248 | 73°C |
| 1608 MHz | 5.790W | 0.715 | ±0.040 | 1248 | 84°C* |
| 1800 MHz | RESET | — | — | — | >85°C |

*Throttled to 1416 MHz during measurement at 1608 MHz.

**Quadratic fit** (f in GHz):

P = 2.781f² − 2.522f + 2.627 (R² = 0.999)

Power scales superlinearly above 1 GHz, consistent with CMOS dynamic power P ∝ CV²f where voltage increases with frequency in the OPP table.

### 6.3 GPU Frequency vs Power

One-way ANOVA: **F(5, 8366) = 102.7, p < 0.001, η² = 0.058**

Statistically significant but practically negligible — GPU frequency explains only 5.8% of power variance.

| GPU Freq | Mean Power | SD | 95% CI | n |
|----------|-----------|-----|--------|---|
| 800 MHz | 2.344W | 0.244 | ±0.013 | 1396 |
| 700 MHz | 2.264W | 0.204 | ±0.011 | 1400 |
| 600 MHz | 2.255W | 0.198 | ±0.010 | 1396 |
| 400 MHz | 2.220W | 0.164 | ±0.009 | 1392 |
| 300 MHz | 2.214W | 0.153 | ±0.008 | 1396 |
| 200 MHz | 2.208W | 0.141 | ±0.007 | 1392 |

Total range: 0.14W. The workload (urandom→framebuffer) is CPU-bound — true GPU shader stress would show larger deltas, but the Mali-G52 EE is a single execution engine with limited power envelope.

### 6.4 DDR Frequency vs Power

One-way ANOVA: **F(3, 5120) = 26.5, p < 0.01, η² = 0.015**

Statistically significant but trivially small effect — DDR frequency explains only 1.5% of power variance.

| DDR Freq | Mean Power | SD | 95% CI | n |
|----------|-----------|-----|--------|---|
| 324 MHz | 2.277W | 0.184 | ±0.010 | 1296 |
| 528 MHz | 2.307W | 0.204 | ±0.011 | 1280 |
| 780 MHz | 2.350W | 0.226 | ±0.012 | 1284 |
| 1056 MHz | 2.304W | 0.229 | ±0.013 | 1264 |

Total range: 0.08W. The 1056 MHz reading is lower than 780 MHz — the workload completes faster at higher DDR rate, reducing sustained current draw. This inverts the expected frequency-power relationship and confirms DDR devfreq's benefit is bandwidth matching, not power savings.

### 6.5 Combined Scaling

| Workload | Power (Run 1) | Power (Run 3 adj) | Notes |
|----------|--------------|-------------------|-------|
| Idle (governors active) | 2.736W | 2.185W | Governors scaling normally |
| Memory stress | 2.574W | 2.170W | DDR scaling active |
| Combined CPU+mem | RESET | 3.316W | **First successful completion (UV L3)** |

### 6.6 Undervolt L3 Impact

Comparison of Run 1 (no PM, no battery) vs Run 3 (DMC+PM+UV L3, adjusted for 3.922W charging overhead):

| Phase | No PM | UV L3 (adj) | Delta | Cohen's d |
|-------|-------|-------------|-------|-----------|
| Idle (powersave) | 1.685W | 2.409W | +0.724W | −6.01* |
| CPU 408 MHz | 2.012W | 2.637W | +0.625W | −8.20* |
| CPU 1104 MHz | 3.224W | 2.986W | **−0.238W** | 2.22 |
| CPU 1416 MHz | 4.600W | 3.180W | **−1.420W** | 7.46 |
| CPU 1608 MHz | 5.790W | 3.267W | **−2.523W** | 4.97 |
| GPU 800 MHz | 2.344W | 2.332W | −0.011W | 0.05 |
| DDR 324 MHz | 2.277W | 2.223W | −0.055W | 0.30 |
| Combined idle | 2.736W | 2.185W | **−0.552W** | 1.46 |
| Memory stress | 2.574W | 2.170W | **−0.404W** | 1.12 |

*Negative Cohen's d at low frequencies reflects charging overhead artifact (charger draws more when SoC draws less), not a real power increase.

**Thermal comparison** (RGB30 with battery):

| CPU Freq | No UV | UV L3 | Delta |
|----------|-------|-------|-------|
| 1416 MHz | 73°C | **63°C** | −10°C |
| 1608 MHz | 85°C RESET | **67°C** | −18°C |
| 1800 MHz | RESET | **71°C** | Survived |
| Combined stress | RESET | **68°C** | Survived |

### 6.7 Output Scale (VOP2 Plane Scaling)

Sway output scale reduces logical resolution; VOP2 display controller upscales via KMS plane scaling (supports 1:8 to 8:1). Measured on RG353P at full battery:

| Title | Native | Half Scale | Savings |
|-------|--------|------------|---------|
| N64 DK64 (GPU-bound) | 4.60W / 86°C | 3.16W / 67°C | **−1.44W (31%), −19°C** |
| Dolphin SSBM (GPU-bound) | — | 2.44W / 61°C | — |
| Lumines (CPU-bound) | 1.72W / 57°C | 1.64W / 56°C | −0.08W (5%) |

RGA hardware scaling never engages — all Wayland apps (RetroArch, PPSSPP, PICO-8, Dolphin) submit display-matched surface buffers. VOP2 handles all scaling natively.

### 6.8 Boot Power Profile (RGB30, no battery)

| Phase | Power |
|-------|-------|
| BROM standby | 0.90W |
| SPL/DDR init | 1.13W |
| U-Boot | 1.41W |
| Kernel peak | 4.76W |
| Init settling | 2.81W |
| Idle | 0.85W |

### 6.9 Suspend Power

Run 3 (UV L3), Phase 6:

| Metric | Value |
|--------|-------|
| Raw power | 4.011W |
| Adjusted (−3.922W charging) | **0.089W** |
| Duration | 225 seconds |
| Minimum | 2.645W raw |

All subsystems survived suspend/resume: DMC governor restored to simple_ondemand at 324 MHz, DFI counters re-primed (patch 1011), TEO idle governor active, power domains correct.

## 7. Crash Analysis

### 7.1 Event Catalog

| # | Build | Device | Context | Power | Root Cause |
|---|-------|--------|---------|-------|------------|
| 1 | 3 | RG353P | Emulator exit | 0.40A→0A | DDR downscale + zram storm |
| 2 | 2 | RG353P | Governor switch mid-game | — | DDR transition |
| 3 | 4 | RG353P | Melee stage load | — | Rapid 324→1056 DDR upscale |
| 4 | 4 | RG353P | PPSSPP Vulkan gameplay | — | Combined GPU+DDR |
| 5 | 5 | RGB30 | NFS mount, 0.49A | 0.5A→0.02A | USB PD hub current limit |
| 6 | 5 | RGB30 | CPU 1800 MHz stress | 5.02W peak | Thermal shutdown >85°C |
| 7 | 5 | RGB30 | CPU+mem combined | 6.55W peak | PMIC brownout at 53°C |

### 7.2 Root Cause Categories

| Category | Events | Mitigation | Status |
|----------|--------|------------|--------|
| Thermal shutdown | #6 | Passive cooling limit; UV L3 provides headroom | Mitigated with UV |
| HWFFC collision | #1, #2, #3 | 100ms transition cooldown + 100ms polling | **Fixed** |
| Zram storm | #1 | swappiness 100→30, page-cluster=0 | **Fixed** |
| USB brownout | #5, #7 | Battery capacitive buffer; avoid >6W transients | Device limitation |
| Combined GPU+DDR | #4 | Cooldown + memory manager tweaks | **Mitigated** |

### 7.3 Crash Power Signatures (100 sps data)

**Event #6 (CPU 1800 MHz thermal)**:
- Final 2s average: 3.56W @ 5.10V
- Peak before crash: 5.02W
- Post-crash: power drops to 1.71W (reboot baseline)

**Event #7 (Combined brownout)**:
- Final 2s average: 3.44W @ 5.11V
- Peak before crash: **6.55W**
- Temperature: only 53°C — not thermal, PMIC overcurrent
- Post-crash: power drops to 1.72W

## 8. Cross-Device Comparison

### 8.1 Comparable States

| State | RGB30 (no battery) | RG353P (full battery) | RG353P (charging) |
|-------|-------------------|-----------------------|-------------------|
| Idle + WiFi | 1.69W | 1.58W | 6.38W |
| N64 native | — | 4.60W | — |
| Dolphin half scale | — | 2.44W | 4.51W |
| Boot peak | 4.76W | — | 8.23W |
| BROM standby | 0.90W | — | 1.06W |

Battery charging adds **4.8W constant overhead**. The RG353P without charging (1.58W idle) is comparable to the RGB30 (1.69W), confirming the charging circuit dominates the power difference.

### 8.2 RG353P -dev Baseline (R13, V4 Profiler)

A separate V4 profile was run on the RG353P using the -dev branch (ondemand governor, no DMC, no UV) to establish an additional baseline reference. Since the FNB58 power meter was not inline with this device, only telemetry markers (voltage, temperature, governor state) were captured — no direct power measurements.

**Thermal profile (stock voltages, ondemand governor):**

| CPU Freq | Voltage | Post-Stress Temp | Notes |
|----------|---------|------------------|-------|
| 408 MHz  | 850 mV  | 50.0°C | Idle baseline |
| 600 MHz  | 850 mV  | 51.9°C | Minimal thermal delta |
| 816 MHz  | 850 mV  | 54.4°C | |
| 1104 MHz | 900 mV  | 62.8°C | First voltage step |
| 1416 MHz | 1030 mV | 78.1°C | Approaching thermal limit |
| 1608 MHz | 1100 mV | **90.0°C** | **At thermal shutdown threshold** |

**Key observations:**
- At 1608 MHz with stock voltages and 4-thread stress, the 353P reaches **90°C** — at the thermal shutdown boundary. This confirms the UV DTBO's value: the same frequency runs at 53°C with UV-optimal.
- 1800 MHz was skipped (MAX_CPU_FREQ=1608000) as a previous attempt caused thermal reset.
- Governor was `ondemand` (not schedutil). Boost was disabled. No TEO (idle governor was `menu`).
- CPU idle used `menu` governor instead of `teo`, confirming the -dev branch did not have TEO activation at this point.
- Memory: stable at 371-375 MB used, no swap pressure.

## 9. Emulation Workload Profiles

### 9.1 Dolphin (GameCube) — Super Smash Bros Melee

| Configuration | DDR Pattern | Power | CPU Load |
|---------------|------------|-------|----------|
| Build 2 (25%/200ms) | 324 MHz stuck | 2.95W | 4.7 |
| Build 3 (15%/50ms) | 324/528/1056 scaling | 3.50W | ~4.0 |
| Build 4 (+ schedutil) | 324/528/1056 scaling | 3.00W | 2.37 |
| Half scale (353P) | — | 2.44W | — |

### 9.2 N64 — Super Smash Bros

| Configuration | Power | Temp | CPU | Stable? |
|---------------|-------|------|-----|---------|
| No DMC, no UV (353P) | 4.60W | 86°C | 1800→throttled | Reset on level load |
| DMC 100ms, no UV (353P) | 3.76W | 80°C | 1800→1416 | Survived level 3 |
| DMC 100ms + UV L3 (353P) | **3.03W** | **62°C** | **1800 (no throttle)** | **Fully stable** |

### 9.3 Output Scale Impact

31% power savings for GPU-bound titles (N64 DK64: 4.60W → 3.16W) with no perceptible quality loss on 640×480 panel. CPU-bound titles (Lumines: 1.72W → 1.64W, 5% savings) show negligible benefit — confirming the bottleneck is CPU, not rendering.

## 10. DDR Devfreq Scaling Behavior

### 10.1 OPP Table

| Frequency | Voltage | ATF FSP | Notes |
|-----------|---------|---------|-------|
| 324 MHz | 900 mV | FSP 0 | Idle/light |
| 528 MHz | 900 mV | FSP 1 | Boot rate |
| 780 MHz | 900 mV | FSP 2 | **Never used** (governor jumps 528→1056) |
| 1056 MHz | 900 mV | FSP 3 | Peak demand |

### 10.2 DMC Driver Architecture

BSP V2 SIP protocol with MCU-based HWFFC:

1. Kernel writes target Hz to ATF shared memory page
2. SET_RATE SIP call returns −6 ("started, wait for MCU")
3. MCU performs Hardware Fast Frequency Change
4. Completion via GIC_SPI 10 IRQ
5. POST_SET_RATE cleanup

### 10.3 780 MHz OPP Anomaly

The 780 MHz OPP is never selected by the simple_ondemand governor. At 15% upthreshold, DFI utilization either stays below 15% (DDR at 324/528 MHz) or spikes above it (triggering immediate jump to 1056 MHz). The governor has no intermediate-step logic — it selects the minimum frequency that satisfies the threshold.

## 11. Discussion

### 11.1 CPU Dominance

CPU frequency explains 94.9% of power variance (η² = 0.949) while GPU and DDR contribute 5.8% and 1.5% respectively. Power optimization ROI is overwhelmingly in CPU governor tuning. The schedutil governor with TEO idle provides the best balance of performance and power efficiency for gaming workloads.

### 11.2 Why DDR Devfreq Matters Despite 0.08W Savings

1. Prevents thermal shutdown when locked at 1056 MHz (95°C with performance governor)
2. Reduces memory latency variance for GPU-shared workloads
3. Enables system-wide power domain coordination

### 11.3 Undervolt as Opt-In

The undervolt L3 DTBO provides dramatic thermal and power improvements but **cannot be a default** — silicon binning varies between devices. A voltage marginally below the stability threshold causes data corruption, not just crashes. The DTBO mechanism allows informed users to opt in without rebuilding.

### 11.4 Measurement Limitations

1. GPU workload (urandom→framebuffer) is CPU-bound — GPU power characterization represents a floor
2. Charging overhead subtraction introduces systematic error at low system loads
3. No per-rail measurement — total system power only, cannot isolate CPU controller vs memory controller
4. Single FNB58 unit — no inter-instrument validation

## 12. Recommendations

### 12.1 Safe Defaults (ship as-is)

- GPU coarse_demand: production default, saves idle power
- TEO CPU idle governor: mature mainline, better for gaming
- DMC simple_ondemand: 15%/100ms polling, 100ms HWFFC cooldown
- Memory manager: swappiness=30, page-cluster=0, watermark=150

### 12.2 User-Facing Options

- Output scale (Off/Half/Quarter): significant savings for GPU-bound titles
- Undervolt DTBO: advanced opt-in for compatible silicon
- Virtual resolution: sway headless output for ports requiring specific resolutions

### 12.3 What NOT to Change

- **DDR performance governor**: causes thermal shutdown at 95°C
- **Lower thermal trip points**: affects all workloads, not just edge cases
- **CPU max frequency cap**: hurts CPU-bound emulators that need burst capability

## 13. Conclusion

This study provides the first comprehensive power characterization of the RK3566 SoC in gaming handheld form factor. CPU frequency is the dominant power variable (3.79W range, η² = 0.95), while DDR memory controller frequency scaling provides negligible power savings (0.08W) but essential bandwidth matching for GPU-shared memory workloads. The iterative firmware development across 5 builds, guided by 100 sps power traces and 7 categorized crash events, produced a stable DDR devfreq implementation with 100ms polling and 100ms HWFFC cooldown that survives sustained gaming including level transitions. The combination of GPU coarse_demand power policy, TEO CPU idle governor, and tuned memory manager provides measurable power savings at combined workloads (−10% idle, −16% memory stress) without risking stability. An optional undervolt DTBO provides 1W savings and 17°C thermal reduction, enabling sustained 1800 MHz CPU operation where stock voltages cause thermal shutdown — but must remain opt-in due to silicon binning variability. All power management changes, including DMC devfreq, survive suspend/resume with measured suspend power of 0.09W.

---

## Appendix A: Tools and Reproducibility

- FNB58 USB logger daemon: https://codeberg.org/aenertia/fnirsi-fnb58
- Profiling scripts: `rgb30_profile_v3.sh` (6-phase), `rgb30_profile_v4.sh` (7-phase + governor comparison)
- V4 additions: configurable P5_GOVERNOR, Phase 7 boost governor comparison, thermal cutoff (THERMAL_CUTOFF env var), MAX_CPU_FREQ limit
- Frequency logger: `freq_logger.sh` (1 Hz sidecar for CPU/GPU/DDR/temp)
- Marker injection: UDP port 5858, `python3 -c "import socket; ..."`
- Data extraction: `extract_all_runs.py` (V1/V2/V3/V4 marker support → `all_runs.json`)
- R statistical analysis: `rk3566_analysis.R` (12 analyses, 17 plots)
- Python analysis: `analyze_v3.py` (ANOVA, Cohen's d, branch comparison)
- ROCKNIX distribution: https://github.com/ROCKNIX/distribution (`353p-dmc` branch)

## Appendix B: Statistical Summary

### B.1 ANOVA Results

| Domain | F | df | p | η² | Interpretation |
|--------|---|-----|---|-----|----------------|
| CPU (6 levels) | 28509.3 | 5, 7590 | <0.0001 | 0.949 | Very large effect |
| GPU (6 levels) | 102.7 | 5, 8366 | <0.001 | 0.058 | Small effect |
| DDR (4 levels) | 26.5 | 3, 5120 | <0.01 | 0.015 | Trivial effect |

### B.2 CPU Power Model

P = 2.781f² − 2.522f + 2.627 (R² = 0.999, f in GHz)

### B.3 Undervolt Effect Sizes

Meaningful effect (|d| > 1.0) observed at:
- CPU 1104 MHz: d = 2.22
- CPU 1416 MHz: d = 7.46
- CPU 1608 MHz: d = 4.97
- Combined idle: d = 1.46
- Memory stress: d = 1.12

### B.4 Updated R Analysis (16 runs, March 2026)

Updated analysis incorporating R13 (353P -dev baseline, V4 profiler):

**Correlation matrix** (84 observations):
- V²f ↔ power: r = 0.952 (very strong)
- Voltage ↔ power: r = 0.878
- Frequency ↔ power: r = 0.837
- Power ↔ temperature: r = 0.549

**CMOS dynamic power model** (log-log regression, R² = 0.943):
- Voltage exponent: 1.47 (theoretical = 2.0; lower due to static power component)
- Frequency exponent: 0.24 (theoretical = 1.0; compressed by voltage co-variation)

**Structural Equation Model** (CFI = 0.998, RMSEA = 0.053, SRMR = 0.022):
- voltage → power: β = 0.648 (p < 0.001)
- frequency → power: β = 0.378 (p < 0.001)
- power → temperature: β = 0.558 (p < 0.001)

**PCA**: PC1 (65.4%) + PC2 (28.7%) = 94.1% variance explained

**Thermal model**: T = 39.3 + 4.8 × P (R² = 0.30). Predicted 72.9°C at 7W.

**353P thermal validation**: 1608 MHz at stock voltages reaches 90°C (R13),
confirming UV DTBO reduces this to 53°C (R10/R11) — a 37°C delta.

### B.5 Run Inventory

| ID | Branch | Config | Device | Battery | Profiler |
|----|--------|--------|--------|---------|----------|
| R1 | dev | no-UV | RGB30 | disconnected | V1 |
| R2 | dev | no-UV | RGB30 | connected | V2 (partial) |
| R3 | dev | UV-L3 | RGB30 | connected | V3 |
| R4 | dev | UV-L3 | RGB30 | connected | V3 |
| R5 | dmc | baseline | RGB30 | connected | V3 |
| R6 | dmc | UV-L3 | RGB30 | connected | V3 |
| R7 | dmc | UV-L3+Boost | RGB30 | connected | V3 |
| R8 | dmc | UV-L1 | RGB30 | connected | V3 |
| R9 | dmc | UV-L2 | RGB30 | connected | V3 |
| R10 | dmc | UV-optimal | RGB30 | connected | V3 |
| R11 | dmc | UV-opt+50ms | RGB30 | connected | V3 |
| R12 | dmc | UV-opt+turbo+schedfix | RGB30 | connected | V3 |
| R13 | dev | 353P-baseline | RG353P | connected | V4 (telemetry only) |
