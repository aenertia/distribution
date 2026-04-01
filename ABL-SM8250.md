# ABL-SM8250: SD Card Boot Failure Investigation

## Executive Summary

**Problem:** Samsung Evo Plus V30 A2 512GB (UHS-I, U3, V30, A2, SDXC) fails to boot ROCKNIX on both Retroid Pocket 5 (SM8250) and AYN Odin2 Mini (SM8550) after flashing ROCKNIX ABL. Kioxia 16GB (UHS-I, U1, SDHC) works fine on both. The same Samsung card boots normally with stock Android ABLs on both devices.

**Root Cause (revised April 2026):** The ROCKNIX ABL's `ConnectAllControllers()` / `BootESP` code path interacts with XBL's SDCC UEFI driver differently from the stock Android ABL, leaving the card and/or SDHCI controller in a state that the Linux kernel's `sdhci-msm` driver cannot recover from during its re-initialization. The initial hypothesis (UHS-I SDR104 re-negotiation failure) was tested and disproven — `sdhci-caps-mask` at `<0x3 0x0>` and `<0x7 0x0>` both failed to resolve the issue. The caps-mask may actually worsen the problem by forcing a speed downgrade after XBL already negotiated UHS-I.

**Fix (current approach):** Remove `sdhci-caps-mask`, add `resets = <&gcc GCC_SDCC2_BCR>` (full SDCC controller reset to POR state), `post-power-on-delay-ms = <200>` (Samsung's complex NAND FTL needs initialization time), and `broken-cd` (bypass GPIO card-detect timing issues).

**The ABL binary is the TRIGGER but cannot be modified.** The kernel DTS must compensate for the state the ROCKNIX ABL leaves behind.

---

## Table of Contents

1. [Boot Architecture](#1-boot-architecture)
2. [Failure Mechanism](#2-failure-mechanism)
3. [ABL Binary Analysis](#3-abl-binary-analysis)
4. [Stock vs ROCKNIX ABL Comparison](#4-stock-vs-rocknix-abl-comparison)
5. [SDHCI Driver Deep-Dive](#5-sdhci-driver-deep-dive)
6. [DTS Configuration Comparison](#6-dts-configuration-comparison)
7. [SD Card Specification Differences](#7-sd-card-specification-differences)
8. [Upstream Kernel History](#8-upstream-kernel-history)
9. [Recommended Fix](#9-recommended-fix)
10. [References](#10-references)

---

## 1. Boot Architecture

### SM8250 Boot Chain (ROCKNIX)

```
PBL (ROM)
  └── XBL (eXtensible Boot Loader) [UEFI firmware, closed-source]
        ├── Initializes SDHCI controller via SDCC DXE driver
        ├── Exposes SD card as EFI Block IO device
        └── ABL (Android Boot Loader) [ROCKNIX custom LinuxLoader]
              ├── BootCFW entry point
              ├── ConnectAllControllers() -- binds UEFI drivers to devices
              ├── Strategy 1: LoadBootImg -- searches for ANDROID! header (fails for arm-efi)
              └── Strategy 2: BootESP -- loads \EFI\BOOT\BOOTAA64.EFI
                    └── GRUB (arm64-efi)
                          ├── Reads grub.cfg from /boot/grub/
                          ├── Kernel cmdline: boot=LABEL=ROCKNIX disk=LABEL=STORAGE
                          └── Linux Kernel 7.0-rc5
                                ├── sdhci-msm driver probes SDCC2
                                ├── GCC controller reset (if resets= present)
                                ├── Re-initializes SD card from scratch
                                └── init mounts LABEL=ROCKNIX partition
```

**Critical distinction:** SM8250 uses a three-stage boot (ABL -> GRUB -> Linux), while SM8550/SM8650 use two-stage (ABL -> Linux directly via `qcom-abl` bootloader type).

### Two-Phase SD Card Initialization

| Phase | Component | SD Card State | Works? |
|-------|-----------|---------------|--------|
| Phase 1 | XBL SDCC driver (UEFI) | HS mode, 3.3V, basic | **YES** -- GRUB boots fine |
| Phase 2 | Linux sdhci-msm driver | Full reset, UHS-I negotiation | **FAILS** on Samsung A2 |

The PR #2496 investigation confirmed: "GRUB menu shows up fine, the kernel boots, but init fails at `mount_part LABEL=ROCKNIX`" -- proving Phase 1 succeeds and Phase 2 fails.

---

## 2. Failure Mechanism

### Precise Chain of Events

1. **XBL boots** -- Initializes SD card at basic HS speed (50MHz, 3.3V). Card works fine.

2. **ABL runs** -- Uses XBL's Block IO protocol to read SD card. Finds `\EFI\BOOT\BOOTAA64.EFI` (GRUB). Loads it. GRUB reads `grub.cfg`, boots kernel with correct cmdline.

3. **Linux kernel loads** -- `sdhci-msm` driver probes `8804000.sdhci` (sdhc_2):
   - `sdhci_msm_gcc_reset()` -- **FULL GCC HARDWARE RESET** (`reset_control_assert` -> 200us -> `deassert` -> 200us)
   - Writes `CORE_VENDOR_SPEC_POR_VAL` (0xa9c) -- wipes vendor registers
   - `sdhci_reset_for_all()` -- software reset, clears all SDHCI state
   - **All XBL/ABL card initialization is now destroyed**

4. **Card re-initialization** (`mmc_rescan` -> `mmc_attach_sd`):
   - `mmc_power_up()` -> starts at 3.3V
   - CMD0, CMD8, ACMD41 -- card identified as SDHC/SDXC with CCS=1
   - Card advertises UHS-I capabilities (SDR50, SDR104)
   - `vqmmc` regulator (`vreg_l6c_2p96`) supports 1.8V -> UHS modes NOT stripped
   - No `sdhci-caps-mask` -> SDR50/SDR104 bits NOT masked from SDHCI CAPABILITIES_1
   - **Kernel attempts 1.8V voltage switch (CMD11)** for UHS-I SDR104
   - SDR104 tuning at 202MHz -- 16-phase DLL sweep
   - **Tuning fails or voltage switch doesn't converge** on Samsung A2 512GB
   - Card enters undefined/stuck state

5. **Init script** (`busybox/scripts/init:118-135`):
   - Tries to mount `LABEL=ROCKNIX` up to 15 times, 1 second apart
   - Block device never appears (card init failed)
   - After 15 seconds: `"Unable to find $1, powering off..."`

### Why Kioxia 16GB Works

| Property | Samsung Evo A2 512GB | Kioxia 16GB |
|----------|---------------------|-------------|
| SD Family | SDXC | SDHC |
| Speed Class | U3 (SDR104 capable) | U1 (SDR50 or HS) |
| App Performance | A2 (cmd queuing) | None |
| UHS-I negotiation | Aggressively negotiates SDR104 (208MHz) | May settle for HS (50MHz) |
| Voltage switch | Requires 1.8V for SDR104 | May stay at 3.3V (HS mode) |

The Kioxia card either doesn't advertise SDR104 at all, or the lower speed mode succeeds where SDR104 fails.

---

## 2a. Revised Failure Analysis (April 2026)

The original hypothesis (Section 2) was tested and disproven through multiple build/test cycles.

### Tests Conducted

| Build Date | Kernel | sdhci-caps-mask | Samsung 512GB Result | Kioxia 16GB Result |
|------------|--------|-----------------|----------------------|-------------------|
| 2026-03-30 | 6.19.5 | None | Fails (GRUB loads, "Unable to find ROCKNIX") | Works |
| 2026-03-31 | 6.19.5 | `<0x3 0x0>` (SDR50+SDR104) | Fails (same) | Works (DDR50 mode) |
| 2026-04-01 | 6.19.5 | `<0x7 0x0>` (SDR50+SDR104+DDR50) | Fails (same) | Works (HS mode) |
| 2026-04-01 | 7.0-rc5 | `<0x7 0x0>` | Fails (**immediately**, not after 30s timeout) | Works (HS 50MHz, 3.3V) |
| SM8550 nightly | 7.0-rc5 | `<0x3 0x0>` | **Fails** (no GRUB, straight to power-off) | Not tested |

### Critical Finding: Cross-Platform Failure

The Samsung 512GB card fails on **both** SM8250 (Retroid Pocket 5) and SM8550 (AYN Odin2 Mini). The same card boots normally with stock Android ABLs on both devices. This proves:

1. The failure is **not SM8250-specific** — it's a ROCKNIX ABL / kernel interaction issue
2. `sdhci-caps-mask` is **not the root cause** — the card fails regardless of speed mode masking
3. The ROCKNIX ABL is the **trigger** — its `ConnectAllControllers()` / `BootESP` code path leaves the XBL SDCC driver or the card in a state that the kernel cannot recover from
4. On SM8250, GRUB loads (ABL can read the card), but the kernel re-init fails
5. On SM8550, even the ABL can't read the card (no GRUB, immediate power-off)

### Failure Timing

The Samsung card fails **immediately** — not after the 30-second mount retry timeout. This means the card is not being detected by the kernel at all. The `mmc_rescan()` function either:
- Gets `cd-gpio = 0` (no card) and aborts instantly, OR
- The card doesn't respond to CMD0/CMD8/ACMD41 during the initial probe

### Live Device Diagnostics (Kioxia card, SSH via root@sm8250.3d.ae.net.nz)

```
Kernel:          7.0.0-rc5 SMP PREEMPT
Card:            SE016 14.4 GiB SDHC (Kioxia 16GB)
Speed:           high speed (50MHz, 3.3V) — caps-mask working correctly
Caps:            0x4040020f (no SDR50/SDR104/DDR50)
Caps2:           0x004a0000
Signal voltage:  3.30V
vqmmc (l6c):     2.904V (range 1.8-2.96V)
vmmc (l9c):      2.904V (range 2.7-2.96V)
GPIO CD:         gpio77 LOW (card present, active-low)
broken-cd:       NOT present
resets:          NOT present (GCC reset is no-op)
post-power-on-delay-ms: 0 (zero extra time)
pinctrl:         "default" only (no "sleep" state)
```

---

## 2b. DTS Comparison: SM8250 vs SM8550 vs SM8650

Property-by-property comparison of the `sdhc_2` (SD card) node:

### Upstream SoC DTSI

| Property | SM8250 | SM8550 | SM8650 |
|----------|--------|--------|--------|
| XO clock | `RPMH_CXO_CLK` (19.2MHz) | `bi_tcxo_div2` (19.2MHz) | `bi_tcxo_div2` (19.2MHz) |
| interconnects | **ABSENT** | Present (sdhc-ddr + cpu-sdhc) | Present |
| dma-coherent | **ABSENT** | Present | Present |
| qcom,dll-config | `0x0007642c` | `0x0007642c` | `0x0007642c` |
| resets | **ABSENT** | **ABSENT** | **ABSENT** |

### Board-Level Overrides (ROCKNIX)

| Property | SM8250 (RP5) | SM8550 (Odin2) | SM8650 (AYANEO) |
|----------|-------------|----------------|-----------------|
| pinctrl-names | `"default"` only | `"default", "sleep"` | `"default", "sleep"` |
| vqmmc-supply | `vreg_l6c_2p96` (1.8-2.96V) | `vreg_l8b_1p8` (1.8V) | `vreg_l8b_1p8` (1.8-2.96V) |
| sdhci-caps-mask | `<0x7 0x0>` (all UHS-I masked) | `<0x3 0x0>` (SDR50+SDR104) | `<0x3 0x0>` |
| max-sd-hs-hz | ABSENT | `<37500000>` | ABSENT |
| qcom,dll-config | ABSENT (SoC default) | `<0x0007442c>` (override) | ABSENT |
| broken-cd | **ABSENT** | **ABSENT** | **ABSENT** |
| resets | **ABSENT** | **ABSENT** | **ABSENT** |
| post-power-on-delay-ms | **0** | **ABSENT** | **ABSENT** |

**Key observation:** None of the Qualcomm SDHCI nodes have `resets`, `broken-cd`, or `post-power-on-delay-ms`. The `GCC_SDCC2_BCR` reset control exists in all three SoCs' GCC headers but is never referenced from the sdhc_2 node.

---

## 2c. A2 Command Queuing Investigation

The Samsung EVO Plus V30 A2 512GB supports Command Queuing (CQ) per the SD 6.0 specification. Investigation findings:

### CQ Protocol Summary

A2-rated SD cards implement Command Queuing through the Performance Enhancement Extension Register (read via CMD48, enabled via CMD49). Commands CMD44/CMD45/CMD46/CMD47 are used for queued I/O operations.

### Linux Kernel CQ Status

- **Hardware CQHCI** (`CONFIG_MMC_CQHCI=y`): Present and enabled on all Qualcomm platforms, but for **eMMC only**
- **SD card CQ detection**: Kernel reads the Extension Register and detects `SD_EXT_PERF_CMD_QUEUE` flag (sd.c:1192-1194)
- **SD card CQ usage**: **NOT implemented**. The flag is detected but never acted upon. SD cards get HSQ (Host Software Queue) — a software command scheduler that does NOT send CQ commands to the card
- **Samsung A2 CQ firmware bugs**: Well-documented on Raspberry Pi (#6561) — Samsung A2 cards have broken CQ firmware causing "running CQE recovery" errors during I/O

### CQ as Root Cause? NO

CQ is a **post-initialization feature**. It does not affect the card's response to CMD0/CMD8/ACMD41 during basic initialization. Per the SD spec, CMD0 returns the card to Idle state even from CQ mode. XBL almost certainly does not enable SD card CQ (it only needs sequential block reads for boot). The kernel's SD card CQ protocol is unimplemented — no CMD44/CMD45 are ever sent.

**CQ is not the root cause of the boot failure.** The Samsung A2 CQ bugs are real but manifest as runtime I/O errors, not initialization failures.

---

## 2d. Root Cause Confirmed: Stale GPT Partition Table (April 2026)

### The Actual Root Cause

The `scripts/mkimage` script hardcoded **MBR (msdos)** partition tables for all non-syslinux bootloaders, despite every Qualcomm device declaring `PARTITION_TABLE="gpt"` in its options. The `PARTITION_TABLE` variable was **dead code** — set in 11 device options files but never consumed by any build script.

When a ROCKNIX image (with MBR) was written to a large SD card that previously had a GPT layout (from any prior OS), the **GPT backup header at the end of the card survived** because:
- The ROCKNIX image is ~2GB
- `dd` only writes ~2GB to the start of the card
- The GPT backup header lives at the last 33 sectors of the card (~512GB mark on a 512GB card)
- The kernel's partition scanner finds both the fresh MBR AND the stale GPT backup header, **prefers the GPT**, and reads partition boundaries that don't match where the image actually wrote its FAT32/ext4 data
- `blkid` can't find `LABEL=ROCKNIX` because the GPT partition offsets point to the wrong sectors
- `mount_common` fails immediately and init powers off

The Kioxia 16GB card worked because:
- On a 16GB card, the 2GB image write covers a larger proportion of the card
- Any previous GPT backup header was closer to the end and may have been overwritten
- Or the card never had GPT (simpler card, less likely to have had a different OS)

### The Fix (commit `8cf88b7645`)

1. **`scripts/image`**: Pass `PARTITION_TABLE` environment variable to `mkimage`
2. **`scripts/mkimage`**: Use `PARTITION_TABLE` from device options instead of hardcoding MBR. Set ESP flag (not `legacy_boot`) for `arm-efi` and `qcom-abl` UEFI bootloaders

### Verification

Samsung EVO Plus V30 A2 512GB card now boots successfully:
```
mmc0: new UHS-I speed SDR104 SDXC card at address 59b4
mmcblk0: mmc0:59b4 EF8S5 478 GiB
 mmcblk0: p1 p2
```

The card runs at **SDR104 (202MHz, 1.8V)** — full UHS-I speed, no caps-mask degradation:
```
clock:          202000000 Hz
timing spec:    6 (sd uhs SDR104)
signal voltage: 1 (1.80 V)
```

Storage partition expanded to full 473.6GB on first boot via `fs-resize`.

### What Was NOT the Root Cause

| Hypothesis | Status | Why Eliminated |
|------------|--------|----------------|
| UHS-I SDR104 speed negotiation | **Wrong** | Card runs at SDR104 perfectly once GPT is correct |
| sdhci-caps-mask missing | **Wrong** | Caps-mask was a red herring; removing it works fine |
| DDR50 voltage switching | **Wrong** | Card does 1.8V voltage switch successfully |
| Missing GCC SDCC reset | **Helpful but not root cause** | `resets = <&gcc GCC_SDCC2_BCR>` is good practice but wasn't the fix |
| Power-on delay too short | **Helpful but not root cause** | 200ms delay is good practice but wasn't the fix |
| Card-detect GPIO timing | **Wrong** | `broken-cd` didn't fix it alone |
| A2 Command Queuing firmware bugs | **Wrong** | CQ is post-init, doesn't affect boot |
| Samsung card hardware defect | **Wrong** | Card works at full speed with correct GPT |
| ROCKNIX ABL interaction with XBL | **Contributory** | The ABL changes card state, but the real issue was the partition table |

### DTS Mitigations Retained

The `resets`, `post-power-on-delay-ms`, and `broken-cd` DTS properties are retained as defense-in-depth even though the GPT fix was the actual solution. They improve robustness:
- `resets = <&gcc GCC_SDCC2_BCR>`: clean controller state after XBL
- `post-power-on-delay-ms = <200>`: safety margin for complex SDXC cards
- `broken-cd`: eliminates card-detect GPIO as a failure path

---

## 3. ABL Binary Analysis

### Binary Overview

| Property | Value |
|----------|-------|
| File | `abl_signed-SM8250.elf` |
| Size | 258,048 bytes (252 KB) |
| Format | ELF 32-bit LSB, ARM, statically linked |
| Entry | `0x9fa00000` |
| Payload | LZMA-compressed UEFI FV -> 630,984 bytes decompressed |
| Signing | `qtestsign Attestation CA - NOT SECURE` (Qualcomm test keys) |
| Build | `/home/runner/work/abl/abl/LinuxLoader/` (GitHub Actions CI) |

### SD Card Handling in ABL

**The ABL contains NO SD/MMC driver code.** Zero SDHCI registers, zero MMC commands, zero UHS mode strings. It operates purely through UEFI protocols:

- `EFI_BLOCK_IO_PROTOCOL` -- block-level storage access
- `gEfiMemCardInfoProtocolGuid` -- card info queries
- `EFI_SIMPLE_FILE_SYSTEM_PROTOCOL` -- filesystem access

The ABL enumerates all `SimpleFileSystem` handles (provided by XBL's SDCC driver), searches for boot files, and loads them. It has no ability to influence SD card speed modes or voltage.

### Boot File Search Paths

```
Strategy 1 (BootImg):   Searches all volumes for boot image with ANDROID! header
Strategy 2 (BootESP):   \EFI\ROCKNIX\BOOTAA64.EFI
                         \EFI\BOOT\BOOTAA64.EFI
Other references:        \KERNEL, \boot\Image, \boot\reglinux.update
```

### Cluster Size Enforcement

The ABL enforces `VerifyClusterSize: Invalid cluster size. Expected 16384 (16KB).` on the boot partition. This is for the `LoadBootImg` path only (not the BootESP/GRUB path). Since SM8250 uses the BootESP/GRUB path, this check is not exercised in the normal boot flow.

---

## 4. Stock vs ROCKNIX ABL Comparison

| Property | ROCKNIX ABL | Stock Android ABL |
|----------|-------------|-------------------|
| ELF size | 252 KB (actual) | 1 MB (padded, 200 KB actual FV) |
| Decompressed | 631 KB | 553 KB |
| Build source | Custom LinuxLoader fork (CI) | Qualcomm edk2 VENDOR.13 (developer) |
| EFI boot (ESP) | Yes | No |
| SD card boot | Yes (via ESP) | No |
| NVMe support | Yes | No |
| Device model selection | Yes (multi-device UI) | No |
| Own SD/MMC driver | **No** (uses XBL) | **No** (uses XBL) |
| UBI/NAND flash | No | Yes |
| Threaded flashing | No | Yes |
| FFBM/Factory mode | No | Yes |

**Neither ABL contains SD card driver code.** Both rely entirely on XBL's closed-source SDCC UEFI driver for storage I/O. The ABL is not the layer causing the boot failure.

Stock ABL source: https://github.com/TheGammaSqueeze/Retroid_Pocket_Stock_Firmware
Stock ABL binary saved: `/var/mnt/awa/working/rocknix-abl-v1.0.0/abl_stock_android-SM8250-RP5.elf` (1,048,576 bytes)

---

## 5. SDHCI Driver Deep-Dive

### sdhci-msm.c (kernel 6.19.5)

**Source:** `drivers/mmc/host/sdhci-msm.c` (2895 lines)

**Compatible string:** SM8250 matches `"qcom,sdhci-msm-v5"` -> `sdhci_msm_v5_var` (no SM8250-specific entry).

**Variant properties:**
- `mci_removed = true`
- `restore_dll_config = false` (SDM845 sets this `true` -- potential concern for suspend/resume)
- `uses_tassadar_dll` depends on runtime `core_minor >= 0x71` (SM8250 is estimated 0x49-0x5E, so NO)

### Clock Configuration

| Clock | Source | Frequency |
|-------|--------|-----------|
| `xo_board` | Board TCXO | 38.4 MHz |
| `RPMH_CXO_CLK` | `bi_tcxo_div2` = xo/2 | **19.2 MHz** (correct) |
| sdhc_2 "xo" | `&rpmhcc RPMH_CXO_CLK` | 19.2 MHz |
| sdhc_2 "core" max | `gcc_sdcc2_apps_clk_src` | 202 MHz (floor ops) |

The XO clock fix (commit `74097d805edb`, v5.11.3) is present -- SM8250 correctly uses `RPMH_CXO_CLK` (19.2 MHz), not the raw `xo_board` (38.4 MHz).

The SDCC2 clock source uses `clk_rcg2_floor_ops` -- rounds DOWN, never overclocks. Requesting 208 MHz yields 202 MHz.

### SDCC2 Frequency Table (gcc-sm8250.c:704-712)

```
400 KHz    (TCXO/12 * 1/4)
19.2 MHz   (TCXO)
25 MHz     (GPLL0_EVEN/12)
50 MHz     (GPLL0_EVEN/6)
100 MHz    (GPLL0_MAIN/6)
202 MHz    (GPLL9/4)
```

### Voltage Switching

The MSM-specific voltage switch handler (`sdhci_msm_start_signal_voltage_switch()` at sdhci-msm.c:2330) toggles `SDHCI_CTRL_VDD_180` and relies on the power IRQ mechanism to call `mmc_regulator_set_vqmmc()`. The `vreg_l6c_2p96` regulator supports both 1.8V and 3.0V:

```
regulator-min-microvolt = <1800000>;   -> CORE_1_8V_SUPPORT = true
regulator-max-microvolt = <2960000>;   -> CORE_3_0V_SUPPORT = true
```

This means UHS-I voltage switching IS attempted. The power IRQ timeout is 5 seconds (`MSM_PWR_IRQ_TIMEOUT_MS`).

### SDR104 Tuning

`sdhci_msm_execute_tuning()` (sdhci-msm.c:1202-1316) tests all 16 DLL phases using `mmc_send_tuning()`. If all 16 pass (which often means none are truly reliable), it retries up to 10 times. If no phase converges, returns `-EIO`. The DLL FLL uses the XO clock ratio -- at 202 MHz with 19.2 MHz XO, the mclk_freq value is ~42 or ~84 depending on FLL_CYCLE_CNT, both within valid range.

### FIFO Clock Toggle Patch

SM8550/SM8650 have patch `0042_mmc--sdhci-msm--Toggle-the-FIFO-write-clock-after-.patch` which fixes async FIFO corruption after clock ungating. This gates on `core_minor >= 0x6B`. SM8250's SDCC is estimated at 0x49-0x5E, so this patch would be a no-op and is **not needed**.

---

## 6. DTS Configuration Comparison

### sdhc_2 (SD Card Controller) Cross-Platform

| Property | SM8250 (RP5) | SM8550 (Odin2) | SM8650 (AYANEO) |
|----------|-------------|----------------|-----------------|
| `vmmc-supply` | `vreg_l9c_2p96` (2.7-2.96V) | `vreg_l9b_2p9` | `vreg_l9b_2p9` (2.95-2.96V) |
| `vqmmc-supply` | `vreg_l6c_2p96` (1.8-2.96V) | `vreg_l8b_1p8` | `vreg_l8b_1p8` (1.8-2.96V) |
| `bus-width` | 4 | 4 | 4 |
| `no-sdio` | yes | yes | yes |
| `no-mmc` | yes | yes | yes |
| **`sdhci-caps-mask`** | **ABSENT** | **`<0x3 0x0>`** | **`<0x3 0x0>`** |
| `max-sd-hs-hz` | absent | `37500000` | absent |
| `qcom,dll-config` | absent (SoC default) | `<0x0007442c>` | absent |
| pinctrl sleep | **NO** | no | **YES** |
| FIFO toggle patch | **NO** | YES | YES |
| XO clock fix patch | N/A (fixed upstream) | YES | YES |
| **UHS-I SDR50/SDR104** | **ENABLED** | **DISABLED** | **DISABLED** |

### What `sdhci-caps-mask = <0x3 0x0>` Does

The SDHCI specification defines a 64-bit CAPABILITIES register. The `sdhci-caps-mask` property masks bits from this register before the kernel uses it:

```
Bit 33 (CAPABILITIES_1 bit 1) = SDHCI_SUPPORT_SDR104
Bit 32 (CAPABILITIES_1 bit 0) = SDHCI_SUPPORT_SDR50
```

`sdhci-caps-mask = <0x3 0x0>` masks bits 33:32, disabling SDR104 and SDR50 capabilities. This forces the card to fall back to High Speed mode (50MHz, 3.3V, no voltage switching).

Applied in `sdhci.c:4160-4173` via `__sdhci_read_caps()`:
```c
device_property_read_u64(mmc_dev(host->mmc), "sdhci-caps-mask", &dt_caps_mask);
host->caps &= ~lower_32_bits(dt_caps_mask);
host->caps1 &= ~upper_32_bits(dt_caps_mask);
```

### SM8250 DTS -- Current (Problematic)

```dts
/* projects/ROCKNIX/devices/SM8250/patches/linux/
   0000-sm8250-retroidpocket-common.patch:1149-1159 */
&sdhc_2 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&sdc2_default_state &sdc2_card_det_n>;
    vmmc-supply = <&vreg_l9c_2p96>;
    vqmmc-supply = <&vreg_l6c_2p96>;
    cd-gpios = <&tlmm 77 GPIO_ACTIVE_LOW>;
    bus-width = <4>;
    no-sdio;
    no-mmc;
    /* NO sdhci-caps-mask -- SDR104/SDR50 UHS-I modes are ENABLED */
};
```

### SM8650 DTS -- Fixed (Working)

```dts
/* projects/ROCKNIX/devices/SM8650/linux/dts/qcom/
   sm8650-ayaneo-common.dtsi:1440-1455 */
&sdhc_2 {
    cd-gpios = <&pm8550_gpios 12 GPIO_ACTIVE_LOW>;
    vmmc-supply = <&vreg_l9b_2p9>;
    vqmmc-supply = <&vreg_l8b_1p8>;
    bus-width = <4>;
    no-sdio;
    no-mmc;
    sdhci-caps-mask = <0x3 0x0>;       /* Disables SDR50/SDR104 */
    pinctrl-0 = <&sdc2_default>, <&sdc2_card_det_n>;
    pinctrl-1 = <&sdc2_sleep>, <&sdc2_card_det_n>;
    pinctrl-names = "default", "sleep";
    status = "okay";
};
```

---

## 7. SD Card Specification Differences

### SDHC vs SDXC at Protocol Level

At the electrical/command level, SDHC and SDXC are identical -- both use block addressing (CCS=1), same CMD8/ACMD41 initialization. The differences are:

| Feature | SDHC (Kioxia 16GB) | SDXC (Samsung 512GB) |
|---------|---------------------|----------------------|
| Capacity | 4-32 GB | 64 GB - 2 TB |
| Default FS | FAT32 | exFAT |
| Addressing | 32-bit block | 32-bit block (same) |
| Max sectors | ~67M | ~1B (30 bits, within 32-bit range) |

### A2 Application Performance Class

A2 cards (Samsung 512GB) support Command Queuing (CMD44/CMD45) and require host CQ support for full performance. Without CQ, A2 cards operate in legacy mode. The card's internal firmware is optimized for queued workloads, and without CQ the cache may not be properly managed. This shouldn't cause boot failure directly but the card firmware may behave differently than simpler cards.

### UHS-I Speed Modes

| Mode | Clock | Bandwidth | Voltage | Samsung A2? | Kioxia? |
|------|-------|-----------|---------|-------------|---------|
| DS | 25 MHz | 12.5 MB/s | 3.3V | Yes | Yes |
| HS | 50 MHz | 25 MB/s | 3.3V | Yes | Yes |
| SDR50 | 100 MHz | 50 MB/s | **1.8V** | Yes | Unlikely |
| SDR104 | 208 MHz | 104 MB/s | **1.8V** | **Yes (U3)** | No |
| DDR50 | 50 MHz | 50 MB/s | 1.8V | Yes | Possible |

The Samsung A2 card's U3 rating means it will negotiate SDR104. The kernel will attempt 1.8V voltage switching and SDR104 tuning, which is where the failure occurs.

---

## 8. Upstream Kernel History

### SM8250 XO Clock Bug (FIXED in v5.11.3)

**Commit `74097d805edb`** -- "arm64: dts: qcom: sm8250: correct sdhc_2 xo clk"
- Changed XO from `&xo_board` (38.4MHz) to `&rpmhcc RPMH_CXO_CLK` (19.2MHz)
- Author: Dmitry Baryshkov
- Ref: https://lore.kernel.org/all/20210109011252.3436533-1-dmitry.baryshkov@linaro.org/

### SDCC Clock Floor Ops (FIXED in v6.1.53)

SM8250's `gcc_sdcc2_apps_clk_src` already uses `clk_rcg2_floor_ops` (rounds down), preventing SD card overclocking. This was the root cause fix for the SM8450 UHS-I problem.
- Ref: https://lwn.net/Articles/944358/

### Vladimir Zapolskiy's UHS-I Patch Series (2026-03-14, v2)

6-patch series to properly fix UHS-I SDR50/SDR104 on SM8450/SM8550/SM8650:
1. Fix XO clock to use `bi_tcxo_div2` (SM8550, SM8650, Hamoa)
2. Remove `sdhci-caps-mask` from upstream DTS (SM8450, SM8550, SM8650)

**However:** ROCKNIX re-added `sdhci-caps-mask` at the board level for both SM8550 (commit `83f424d903`, 2026-03-23, "revert removing sdhci-caps-mask") and SM8650 (commit `83d384dcea`, 2026-03-30, "sm8650: disable SD UHS-I -- still not stable").

- Ref: https://lore.kernel.org/all/20260314023715.357512-1-vladimir.zapolskiy@linaro.org/

### Qualcomm Level Shifter Patches (Sarthak Garg, in review)

Adds `max-sd-hs-frequency` DT property to cap HS mode speed. Currently applied to SM8550 at 37.5 MHz.
- Ref: https://patchew.org/linux/20250618072818.1667097-1-quic._5Fsartgarg@quicinc.com/

### Voltage Pad Switching

Qualcomm SDHCI pads are dual-voltage (3.0V/1.8V). The `IO_PAD_PWR_SWITCH` bit must be toggled correctly during voltage switching for UHS-I.
- Ref: https://patchwork.kernel.org/patch/10211841/

---

## 9. Recommended Fix (Revised April 2026)

### Approach: Clean Controller Reset + Power-On Delay + Bypass Card-Detect

The `sdhci-caps-mask` approach was tested at `<0x3 0x0>` and `<0x7 0x0>` — neither resolved the Samsung 512GB failure. The caps-mask is now considered a **red herring** that may actually worsen the problem by forcing a speed downgrade after XBL already negotiated UHS-I with the card.

The revised fix addresses the actual failure mode — the kernel's `sdhci-msm` probe fails to re-initialize the card after the ROCKNIX ABL's XBL interaction:

**File:** `projects/ROCKNIX/devices/SM8250/patches/linux/0000-sm8250-retroidpocket-common.patch`

**Before (current, broken):**
```dts
&sdhc_2 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&sdc2_default_state &sdc2_card_det_n>;
    vmmc-supply = <&vreg_l9c_2p96>;
    vqmmc-supply = <&vreg_l6c_2p96>;
    cd-gpios = <&tlmm 77 GPIO_ACTIVE_LOW>;
    bus-width = <4>;
    no-sdio;
    no-mmc;
    sdhci-caps-mask = <0x7 0x0>;
};
```

**After (revised fix):**
```dts
&sdhc_2 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&sdc2_default_state &sdc2_card_det_n>;
    vmmc-supply = <&vreg_l9c_2p96>;
    vqmmc-supply = <&vreg_l6c_2p96>;
    cd-gpios = <&tlmm 77 GPIO_ACTIVE_LOW>;
    bus-width = <4>;
    no-sdio;
    no-mmc;
    resets = <&gcc GCC_SDCC2_BCR>;
    post-power-on-delay-ms = <200>;
    broken-cd;
};
```

### Rationale for Each Change

**1. Remove `sdhci-caps-mask`**
The XBL firmware already successfully negotiated UHS-I (likely SDR104) with the Samsung card — proven by GRUB loading. When the kernel then forces a downgrade to HS mode (50MHz, 3.3V) via the caps-mask, the card's internal controller may be confused by the voltage/speed transition. Removing the mask lets the kernel negotiate the same mode XBL used, which is the path of least resistance.

**2. Add `resets = <&gcc GCC_SDCC2_BCR>` (value 29)**
Enables the GCC SDCC2 block-level hardware reset during `sdhci_msm_gcc_reset()`. Without this property, `reset_control_get_optional_exclusive()` returns NULL and the reset is a complete no-op. With it, the SDCC controller is reset to its power-on-reset (POR) state, wiping all clock configuration, DLL phase settings, and vendor register values left by XBL. This gives the kernel a clean starting point regardless of what the ROCKNIX ABL did.

The reset sequence adds ~400µs (200µs assert + 200µs deassert) — negligible.

**3. Add `post-power-on-delay-ms = <200>`**
Gives the Samsung card's internal controller 200ms after vmmc power-up before the first command (CMD0). The current delay is 0ms (effectively the kernel's default 10ms `power_delay_ms`). The Samsung EVO Plus 512GB has a complex multi-die NAND controller with a sophisticated FTL that may need significantly more initialization time than a simple 16GB SDHC card.

**4. Add `broken-cd`**
Always assume a card is present, bypassing the GPIO 77 card-detect check. If the ROCKNIX ABL's XBL interaction leaves the GPIO or the card-detect switch in a transient state, `mmc_rescan()` would abort immediately without even attempting card initialization. `broken-cd` eliminates this as a failure path.

Trade-off: Hot-removal detection is disabled. Acceptable for gaming handhelds where SD cards are not swapped during use.

### Verification

After applying the fix, boot with the Samsung 512GB card and verify via dmesg:
```bash
# Card should be detected and speed mode shown
dmesg | grep -i "mmc\|sdhci\|sdhc"
# Expected: "new ultra high speed SDR104 SDXC card" or "new high speed SDXC card"

# Verify reset was applied
dmesg | grep -i "reset"
# Expected: sdhci-msm reference to reset control
```

### Alternative Fixes (if primary fix is insufficient)

1. **Add `no-1-8-v` property** -- completely prevents 1.8V signaling. If UHS-I negotiation itself is the problem (not the ABL state), this would force HS mode without the caps-mask side effects.
2. **Add sleep pinctrl state** -- `pinctrl-1 = <&sdc2_sleep &sdc2_card_det_n>` with `pinctrl-names = "default", "sleep"`. Prevents pin state glitches during power transitions (SM8550/SM8650 both have this).
3. **Add `sdhci-caps-mask = <0x2 0x0>`** -- if UHS-I SDR104 specifically is unstable, mask only SDR104 while keeping SDR50 (100MHz, ~50MB/s).
4. **Add `max-sd-hs-hz = <37500000>`** -- cap HS mode speed (matches SM8550).
5. **Patch `restore_dll_config = true`** in sdhci-msm.c for SM8250 variant -- stabilize DLL across suspend/resume.

### Apply to All Qualcomm Platforms

The SM8550 Odin2 Mini also fails with the Samsung 512GB card (no GRUB, immediate power-off). The same `resets`, `post-power-on-delay-ms`, and `broken-cd` mitigations should be applied to SM8550 and SM8650.

| SoC | GCC_SDCC2_BCR Value | Header |
|-----|---------------------|--------|
| SM8250 | 29 | `qcom,gcc-sm8250.h` |
| SM8550 | 22 | `qcom,sm8550-gcc.h` |
| SM8650 | 23 | `qcom,sm8650-gcc.h` |

---

## 9a. UHS-I Speed Notes

With the caps-mask removed, the SD card will negotiate its fastest supported speed mode. For the Samsung EVO Plus V30 A2 512GB (U3), this would be SDR104 (208MHz, ~104MB/s) with 1.8V voltage switching.

If UHS-I proves unstable in practice (CRC errors, timeout during operation), the escalation path is:

1. Add `sdhci-caps-mask = <0x2 0x0>` -- disable SDR104 only, keep SDR50 (100MHz, ~50MB/s)
2. Add `sdhci-caps-mask = <0x3 0x0>` -- disable SDR50+SDR104, keep DDR50
3. Add `sdhci-caps-mask = <0x7 0x0>` -- disable all UHS-I, force HS (50MHz, 25MB/s)
4. Add `no-1-8-v` -- force 3.3V only, no voltage switching at all

The SM8250's XO clock is correct at 19.2MHz and its GCC uses `clk_rcg2_floor_ops`, so the clock infrastructure should support UHS-I correctly. Board-level signal integrity (PCB traces, level shifters) is the main unknown.

### Upstream References

- Vladimir Zapolskiy UHS-I v2 series: https://lore.kernel.org/all/20260314023715.357512-1-vladimir.zapolskiy@linaro.org/
- Sarthak Garg level shifter patches: https://lore.kernel.org/all/20250523105745.6210-3-quic_sartgarg@quicinc.com/
- SM8450 floor ops fix: commit `a27ac3806b0a`
- SC7180 restore_dll_config: https://lore.kernel.org/all/20200827024906.14due9a64kwa7ry7@pbase3.gemini.binaryheaven.com/

---

## 10. References

### ROCKNIX Repositories
| Resource | URL |
|----------|-----|
| ROCKNIX ABL repo | https://github.com/ROCKNIX/abl |
| ROCKNIX distribution | https://github.com/ROCKNIX/distribution |
| PR #2496 (investigation) | https://github.com/ROCKNIX/distribution/pull/2496 |
| RetroidPocket U-Boot | https://github.com/RetroidPocket/u-boot |
| Stock firmware (TheGammaSqueeze) | https://github.com/TheGammaSqueeze/Retroid_Pocket_Stock_Firmware |

### Renegade Project (EDK2/UEFI for Qualcomm)
| Resource | URL |
|----------|-----|
| edk2-msm (UEFI firmware) | https://github.com/edk2-porting/edk2-msm |
| Documentation | https://renegade-doc.readthedocs.io/en/latest/edk2/Overview.html |
| SM8250 device page | https://renegade-doc.readthedocs.io/en/latest/devices/sm8250/index.html |
| Custom LinuxLoader (Odin 2) | https://renegade-project.tech/en/ayn-odin2/linuxloader |

### Qualcomm ABL / Boot Chain Analysis
| Resource | URL |
|----------|-----|
| ABL Analysis Part 1 (Inoki) | https://blog.inoki.cc/2021/10/18/android-bootloader-analysis-abl-1-en/ |
| ABL Analysis Part 3 (Inoki) | https://blog.inoki.cc/2024/04/20/android-bootloader-analysis-abl-3-en/ |
| XBL comparison (worthdoingbadly) | https://worthdoingbadly.com/qcomxbl/ |
| xbltools | https://github.com/linux-msm/xbltools |
| Qualcomm bootloader docs | https://docs.qualcomm.com/bundle/publicresource/topics/80-70014-4/bootloader.html |
| Qualcomm SD boot docs | https://docs.qualcomm.com/bundle/publicresource/topics/80-70020-27/boot_linux_operating_system_from_sdcard.html |
| Bootchain zero-day analysis | https://tryigit.dev/qualcomm-uefi-gbl-bootchain-zero-day-exploit/ |

### Upstream Kernel Patches
| Resource | URL |
|----------|-----|
| SM8250 XO clock fix (v5.11.3) | https://lore.kernel.org/all/20210109011252.3436533-1-dmitry.baryshkov@linaro.org/ |
| Vladimir Zapolskiy UHS-I v2 series | https://lore.kernel.org/all/20260314023715.357512-1-vladimir.zapolskiy@linaro.org/ |
| SM8650 XO clock fix (spinics) | https://www.spinics.net/lists/devicetree/msg906184.html |
| SM8450 floor ops analysis | https://www.spinics.net/lists/devicetree/msg871967.html |
| Level shifter patches (Sarthak Garg) | https://patchew.org/linux/20250618072818.1667097-1-quic._5Fsartgarg@quicinc.com/ |
| Voltage pad switching | https://patchwork.kernel.org/patch/10211841/ |
| Linux 6.1.53 stable (clock fixes) | https://lwn.net/Articles/944358/ |

### SD Card Specifications and Analysis
| Resource | URL |
|----------|-----|
| SD Physical Layer Spec (simplified) | https://academy.cba.mit.edu/classes/networking_communications/SD/SD.pdf |
| elm-chan SD/MMC guide | https://elm-chan.org/docs/mmc/mmc_e.html |
| SD Assoc. A2 overview | https://www.sdcard.org/press/thoughtleadership/applications-in-action-introducing-the-newest-application-performance-class/ |
| SD Assoc. Low Voltage Signaling | https://www.sdcard.org/developers/sd-standard-overview/low-voltage-signaling/ |
| A1 vs A2 analysis (Thomas Kaiser) | https://github.com/ThomasKaiser/Knowledge/blob/master/articles/A1_and_A2_rated_SD_cards.md |
| Jeff Geerling A2 follow-up | https://www.jeffgeerling.com/blog/2019/raspberry-pi-microsd-follow-sd-association-fools-me-twice/ |
| TI sdhci-caps-mask docs | https://www.ti.com/lit/pdf/sprad38 |

### SD Card Command Queuing / A2
| Resource | URL |
|----------|-----|
| Raspberry Pi Samsung CQ bug (#6561) | https://github.com/raspberrypi/linux/issues/6561 |
| SD 6.0 spec (CQ/A2 overview) | https://www.sdcard.org/press/thoughtleadership/applications-in-action-introducing-the-newest-application-performance-class/ |
| Thomas Kaiser A1/A2 deep-dive | https://github.com/ThomasKaiser/Knowledge/blob/master/articles/A1_and_A2_rated_SD_cards.md |

### Community / Related Projects
| Resource | URL |
|----------|-----|
| Linaro unified boot (Qualcomm) | https://www.linaro.org/blog/unified-boot-on-qualcomm-rbx-development-boards/ |
| Armbian SM8250 ABL PR | https://github.com/armbian/build/pull/7663 |
| ROCKNIX RP Mini guide | https://rocknix.org/devices/retroid/retroid-pocket-mini/ |
| RP5 dual-boot (amphyvi) | https://github.com/amphyvi/rp5-dualboot |
| XDA ABL packing/signing | https://xdaforums.com/t/qualcomm-abl-android-bootloader-packing-signing.4473815/ |
| KNULLI SM8250 patches | https://github.com/symbuzzer/fork-knulli-linux/tree/knulli-main/board/qualcomm/sm8250/linux_patches |

### Artifacts (Local)
| File | Path |
|------|------|
| ROCKNIX ABL | `/var/mnt/awa/working/rocknix-abl-v1.0.0/abl_signed-SM8250.elf` (252 KB) |
| Stock Android ABL | `/var/mnt/awa/working/rocknix-abl-v1.0.0/abl_stock_android-SM8250-RP5.elf` (1 MB) |
| ROCKNIX ABL strings | `/tmp/rocknix_abl_strings.txt` |
| Stock ABL strings | `/tmp/stock_abl_strings.txt` |
| Decompressed ABL | `/tmp/abl_extract/` |

---

## Appendix A: SM8250 Kernel SDHCI Source Locations

| Component | Path (relative to kernel tree) |
|-----------|------|
| sdhci-msm driver | `drivers/mmc/host/sdhci-msm.c` (2895 lines) |
| Generic SDHCI host | `drivers/mmc/host/sdhci.c` (5024 lines) |
| SM8250 GCC clocks | `drivers/clk/qcom/gcc-sm8250.c` (3683 lines) |
| SM8250 DTSI | `arch/arm64/boot/dts/qcom/sm8250.dtsi` |
| RPMH clock driver | `drivers/clk/qcom/clk-rpmh.c` |
| RCG2 floor ops | `drivers/clk/qcom/clk-rcg2.c` |

## Appendix B: ROCKNIX SM8250 DTS Patch Files

| Patch | Description |
|-------|-------------|
| `0000-sm8250-retroidpocket-common.patch` | Common DTS: SDHC2, audio, USB, display, thermal, regulators |
| `0002-sm8250-retroidpocket-rp5.patch` | RP5: 1080x1920 framebuffer |
| `0003-sm8250-retroidpocket-rpmini.patch` | RP Mini: 960x1280 framebuffer |
| `0004-pm8150b.patch` | PMIC support |
| `0016-fix-vol-up-with-custom-uboot.patch` | Volume Up button fix for custom U-Boot |
| `0018-...Retroid-Pocket.patch` | Retroid Pocket Mini V2 DTS |
| `0019-...Retroid-Pocket.patch` | Retroid Pocket Flip2 DTS |

## Appendix C: SDHCI Capabilities Register Layout

```
CAPABILITIES (32-bit, offset 0x40):
  [31:26] Slot Type, Async Int, 64-bit System Bus
  [25:24] Max Block Length
  [23:21] Base Clock Frequency
  [20]    Timeout Clock Unit
  [19:18] Timeout Clock Frequency
  ...

CAPABILITIES_1 (32-bit, offset 0x44):
  [0]  SDR50 Support       <-- Masked by caps-mask bit 32
  [1]  SDR104 Support      <-- Masked by caps-mask bit 33
  [2]  DDR50 Support
  [3]  Driver Type A
  [4]  Driver Type C
  [5]  Driver Type D
  [6]  Timer Count for Re-Tuning
  [13] Use Tuning for SDR50
  [14] Re-Tuning Modes
  [15] Clock Multiplier
  ...
```

## Appendix D: Boot Flow Timing

```
Phase 1 (XBL/ABL, ~2-5s):
  XBL SDCC init → negotiates UHS-I ...... card OK (SDR104/DDR50 likely)
  ABL ConnectAllControllers .............. card visible as SimpleFS
  ABL BootESP → GRUB loads .............. reads /boot/grub/grub.cfg
  GRUB boots kernel ...................... kernel + initramfs loaded from SD

Phase 2 (Linux kernel):
  sdhci-msm probe ...................... clock + regulator setup
  sdhci_msm_gcc_reset() ................ SDCC block reset (requires resets= in DTS!)
  sdhci_set_ios() → pwr_irq ........... vmmc OFF → vmmc ON
  post-power-on-delay .................. 200ms (requires post-power-on-delay-ms=)
  mmc_rescan:
    get_cd() check ..................... PASS (requires broken-cd or working GPIO)
    mmc_rescan_try_freq(400kHz) ........ CMD0 → CMD8 → ACMD41
    mmc_attach_sd() .................... card identified, speed negotiated
    mmc_blk_probe() .................... /dev/mmcblk0 + partitions created

Phase 3 (init, 30s timeout):
  mount_common tries LABEL=ROCKNIX ...... 30x with 1s sleep
  mount succeeds ....................... /flash mounted ro

FAILURE MODE (Samsung 512GB, WITHOUT fix):
  Phase 2 fails IMMEDIATELY:
    - No resets= → GCC reset skipped, stale XBL state in SDCC controller
    - post-power-on-delay = 0ms → card has no time to re-init after power cycle
    - get_cd() may return 0 → mmc_rescan aborts without sending any commands
    - Card never appears as /dev/mmcblk*
    - init sees no block device, prints "Unable to find ROCKNIX", powers off
```

## Appendix E: Test Log

| Date | Build | Kernel | DTS Changes | Samsung 512GB | Kioxia 16GB | Notes |
|------|-------|--------|-------------|---------------|-------------|-------|
| 2026-03-30 | 20260330 | 6.19.5 | None | **FAIL** (GRUB loads, no ROCKNIX label) | PASS | Baseline |
| 2026-03-31 | 20260331 | 6.19.5 | caps-mask `<0x3 0x0>` | **FAIL** (same) | PASS (DDR50 mode!) | DDR50 still enabled |
| 2026-04-01a | 20260401 | 6.19.5 | caps-mask `<0x7 0x0>`, 30s timeout | **FAIL** (same) | PASS (HS 50MHz) | All UHS-I masked |
| 2026-04-01b | 20260401 | 7.0-rc5 | caps-mask `<0x7 0x0>`, 30s timeout, HZ=300, TEO | **FAIL** (immediate) | PASS (HS 50MHz) | Kernel bump, scheduler tuning |
| 2026-04-01c | SM8550 nightly | 7.0-rc5 | caps-mask `<0x3 0x0>` (SM8550 default) | **FAIL** (no GRUB, straight to off) | N/T | Cross-platform confirmation |
| Stock ABL | - | - | (Android) | **PASS** | PASS | Both SM8250 and SM8550 stock ABLs work |
| 2026-04-01d | 20260401 | 7.0-rc5 | resets + delay-200ms + broken-cd, NO caps-mask | **FAIL** (immediate) | PASS | DTS mitigations alone insufficient |
| 2026-04-01e | 20260401 | 7.0-rc5 | Same DTS + **GPT partition table** (mkimage fix) | **PASS — SDR104 208MHz 1.8V** | PASS | **ROOT CAUSE CONFIRMED: stale GPT** |
