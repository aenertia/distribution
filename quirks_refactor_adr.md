# Architecture Decision Record: Refactoring the Hardware Quirks and Package System

**Date:** 2026-02-27
**Status:** Proposed
**Author:** ROCKNIX Architecture Review

## 1. Context and Problem Statement

ROCKNIX is built as an immutable Linux distribution targeting specific SoCs/Platforms (e.g., `RK3566`, `SDM845`, `H700`). The build system suffers from high coupling between global package definitions, platform-specific logic, and upstream LibreELEC compatibility. This manifests in several critical areas:

### A. The Hardware Quirks System

Currently, the `quirks` package structure is flattened at the top level, causing wildcard copies to include **every** platform's folder in **every** OS image. Furthermore, the quirk scripts themselves are littered with internal conditionals (`if [ "$DEVICE" = ... ]`), making maintenance brittle.

### B. Proliferation of Hardcoded Device States in Packages

Across the broader package system (e.g., `linux`, `libmali`, `ffmpeg`), project-level `package.mk` files use hardcoded `case ${DEVICE} in` statements. For example, `ffmpeg/package.mk` manually disables `V4L2_SUPPORT` specifically if the device is `RK3588`. This requires a grep-and-patch expedition across global files for every new SoC.

### C. Hardware Revision Fragmentation and Boot Sequencing

Devices frequently undergo silent hardware revisions (e.g., new LCD panels). Currently, this is handled inconsistently:

1. **XML DTB Proliferation:** The `rocknix-config.xml` defines entirely new OS images/DTBs for minor revisions (e.g., `rev6-panel`). This dramatically inflates the CI build matrix and runner consumption.
2. **The `mipi-panel.dtbo` Hack:** Some devices rely on users manually swapping a global `/overlays/mipi-panel.dtbo` to fix black screens.
3. **Improper Sequencing:** Attempts to apply panel DTBOs via userspace scripts (`dtb_overlay apply`) occur *after* the kernel DRM subsystem has already probed and failed, rendering them ineffective.

### D. Upstream Rebase Friction

ROCKNIX tracks LibreELEC upstream. When we modify shared package makefiles to insert our `$DEVICE` checks, it creates continuous, painful merge conflicts during rebases.

## 2. Decision

We will restructure the `quirks` package to a **Platform-First Hierarchy**, enforce **Inversion of Control (IoC)** via explicit variable contracts, formalize a **Boot-Aware Revision Pipeline**, and establish a **Rebase-Safe Override Strategy**.

### Proposed Changes:

**A. Quirks Restructuring & Intra-Quirk Cleanup**

1. **Nesting:** Physical devices must be nested within their platform: `quirks/platforms/RK3566/devices/Powkiddy x55/`.
2. **Internal Logic:** Because scripts are now isolated by platform, all `if [ "$DEVICE" = ... ]` conditionals *inside* the scripts must be stripped.
3. **Cross-Platform Drift:** For vendor devices released across multiple SoCs (e.g., Anbernic RG35XX), shared logic will live in `quirks/common/devices/` and be symlinked into the respective platform directories to prevent configuration drift.

**B. Package System Decoupling (Inversion of Control)**
Global and Project-level `package.mk` files must be hardware-agnostic.

1. **Strict Variable Contracts:** The `devices/$DEVICE/options` file is the absolute source of truth. If `ffmpeg` needs a specific flag, the options file defines `V4L2_SUPPORT="no"`. The package makefile consumes this variable without ever checking the `$DEVICE` string.
2. **Rebase-Safe Overrides & Inheritance Model:** For packages inherited from LibreELEC, we will use ROCKNIX-local overrides in `projects/ROCKNIX/packages/<pkg>/package.mk` (or device-specific `devices/$DEVICE/packages/`). 
    * **Variable Merging:** Variables like `PKG_DEPENDS_TARGET` must be *appended* (`+=`), not replaced, to preserve upstream dependencies.
    * **Function Overrides:** If overriding a function like `post_makeinstall_target`, the override *completely replaces* the upstream function. Maintainers must ensure upstream logic is replicated if still required.

**C. Boot-Aware Revision Handling Pipeline**
To handle multi-panel devices without XML bloat or user intervention, we establish a strict sequencing pipeline:

1. **The `rocknix-config.xml` Boundary:** The XML registry strictly owns **"Distinct Physical Motherboards"**. It dictates entirely separate OS images. Minor panel revisions are strictly forbidden from having unique XML entries.
2. **Bootloader Hardware ID:** U-Boot acts as the hardware arbiter, passing ADC values to the kernel via `uboot.hwid_adc=`.
3. **Universal Drivers (Preferred for Displays):** For simple panel variations, heavily utilize the `rocknix,generic-dsi` driver. The kernel auto-probes the panel based on timing arrays within a unified base DTS.
4. **Bootloader Overlay Injection:** If a display DTBO is absolutely required, U-Boot's `boot.ini` / `boot.scr` must conditionally apply the overlay *before* kernel handoff.
5. **Userspace Runtime Injection (`001-detect-revision`):** Strictly for late-init non-display devices (audio routing, GPIO button maps, LED matrices).

**D. Standardized Runtime Capability Flags**
To decouple global scripts from SoC-specific commands, we establish a standard variable naming convention injected at runtime by the `001-device_config` quirks scripts:
* **Binary Capabilities:** `DEVICE_HAS_TOUCHSCREEN="true"`, `DEVICE_HAS_DUAL_SCREEN="true"`
* **Configuration Strings:** `DEVICE_CPU_GOVERNOR_PERFORMANCE="performance"`, `DEVICE_GPU_FREQ_MAX="800000000"`

**E. Virtual Packages as Pure Aggregators**
Virtual packages (`packages/virtual/*`) must act solely as pure aggregators by directly ingesting arrays like `${ADDITIONAL_DRIVERS}` and `${ADDITIONAL_PACKAGES}` defined in the device options file.

## 3. Consequences

### Positive

* **Cleaner Rebases:** Moving device logic out of global shared packages and into isolated options files drastically reduces merge conflicts with LibreELEC upstream.
* **Optimized CI/CD Cache & Resources:** Cleaner per-device options files improve build caching and parallelization. Consolidating minor panel revisions via `generic-dsi` prevents unnecessary XML bloat and distinct OS image generation.
* **Rapid Platform Bring-up:** A new SoC target requires only a new `options` file and a platform quirks folder.
* **Robust Hardware Support:** Multi-panel devices boot reliably. Display changes are handled by `generic-dsi` or U-Boot, while input/audio changes are handled seamlessly by runtime scripts.

### Negative / Mitigation

* **Migration Complexity:** The migration must touch almost every device target. It requires careful extraction of hardcoded variables from global makefiles into individual device options files, as well as significant cleanup of intra-quirk bash logic.

## 4. Implementation Phasing

To mitigate risk, this architecture will be implemented in four distinct phases:

* **Phase 1: Quirks Directory Restructure.** Move physical device folders into platform subdirectories and update `quirks_package.mk`. Establish the `common/` symlink pattern for cross-platform devices.
* **Phase 2: Formalize Options Contracts & Validate Rebases.** Extract variables (e.g., `MALI_DRIVER_VERSION`, `V4L2_SUPPORT`) from global `package.mk` files and inject them into `devices/$DEVICE/options`. 
    * *Validation Step:* Perform a simulated rebase pulling recent LibreELEC commits on high-risk packages (`ffmpeg`, `mesa`, `wlroots`) to guarantee clean merges.
* **Phase 3: Revision Pipeline & Display Handoff.** Audit the `rocknix-config.xml` for redundant panel definitions. Migrate display overlays to U-Boot pre-kernel injection or `generic-dsi`. Implement `001-detect-revision` strictly for non-display quirks.
* **Phase 4: Virtual Packages Strictness.** Audit and enforce the virtual packages constraint, removing any lingering `$DEVICE` case statements.

## 5. Implementation Examples

### Example 1: Rebase-Safe Variable Contracts (ffmpeg)

**Anti-pattern (Current `projects/ROCKNIX/packages/multimedia/ffmpeg/package.mk`):**
```makefile
case ${DEVICE} in
  RK3588*) V4L2_SUPPORT=no ;;
esac
```

**After (Inversion of Control):**
*In `devices/RK3588/options`:*
```bash
V4L2_SUPPORT="no"
# Add other specific overrides like PKG_FFMPEG_V4L2 flags here if needed
```

*In `projects/ROCKNIX/packages/multimedia/ffmpeg/package.mk`:*
```makefile
# Variables are blindly inherited from the device options file.
if [ "${V4L2_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" libdrm"
  # ...
fi
```

### Example 2: Userspace Runtime Revision Injection (Non-Display)

*Note: This is strictly for late-init devices (audio muxes, input). Display DTBOs must be handled by U-Boot.*

**Directory Structure:**
```text
quirks/platforms/RK3326/devices/Game Console R36S/
├── 001-detect-revision
└── revisions/
    ├── v1-audio/
    │   └── sound_routing.dtbo
    └── v2-audio/
        └── sound_routing.dtbo
```

**Inside `001-detect-revision`:**
```bash
#!/bin/bash
# Extract the ADC/Hardware ID passed by U-Boot in the kernel cmdline
HWID_ADC=$(sed -n 's/^.* uboot.hwid_adc=\([^, ]*\).*$/\1/p' /proc/cmdline)

if [ "$HWID_ADC" -lt 500 ]; then
    export DEVICE_REVISION="v1-audio"
else
    export DEVICE_REVISION="v2-audio"
fi

OVERLAY_PATH="/usr/lib/autostart/quirks/platforms/$DEVICE/devices/$QUIRK_DEVICE/revisions/$DEVICE_REVISION/sound_routing.dtbo"

if [ -f "$OVERLAY_PATH" ]; then
    # Guard against missing dtb_overlay tool if the options file didn't include it
    if command -v dtb_overlay &> /dev/null; then
        dtb_overlay apply "$OVERLAY_PATH"
    else
        echo "Error: dtb_overlay not found but required by revision quirks."
    fi
fi
```

### Example 3: Virtual Package Aggregation

**`packages/virtual/linux-drivers/package.mk`:**
```makefile
PKG_NAME="linux-drivers"
PKG_SECTION="virtual"

# Ingest array defined strictly in projects/ROCKNIX/devices/$DEVICE/options
if [ -n "${ADDITIONAL_DRIVERS}" ]; then
  PKG_DEPENDS_TARGET+=" ${ADDITIONAL_DRIVERS}"
fi
```

## 6. Comprehensive Implementation Plan / Remediation Ledger

Based on a comprehensive codebase audit, the following files exhibit anti-patterns and must be migrated according to the strategies defined below.

### 6.1 OS Core, Kernel, & Bootloader Files
The core system must utilize LibreELEC's `devices/$DEVICE/packages/` override system rather than bloating global makefiles with massive `case` statements.

| Target File | Current Anti-Pattern | Remediation Strategy | Required `options` Variable / Action |
| :--- | :--- | :--- | :--- |
| `bootloader/mkimage`, `bootloader/rkhelper` | Hardcoded `case $DEVICE` switching payloads (`u-boot.bin` vs `rk3326-uboot.bin` vs `dtb.img`). | **Config Registry:** Move payload definitions into `rocknix-config.xml` attributes or `$DEVICE/options`. | `UBOOT_PAYLOAD_NAME="u-boot.bin"` |
| `packages/linux/package.mk` | Massive `case ${DEVICE} in` to define `PKG_VERSION`, `PKG_URL`, and custom firmware copying. | **Device Override:** Migrate highly divergent kernel configurations to `devices/$DEVICE/packages/linux/package.mk`. | Completely decouple `linux` per major SoC variant. |
| `packages/linux-firmware/kernel-firmware/package.mk` | Hardcoded directory copying for `SM8250`, `SDM845`, `H700` (`rtl_bt`, `rtw88`, `panels`). | **IoC:** Define required firmware paths in the device options file to be ingested blindly. | `EXTRA_FIRMWARE_DIRS="rtl_bt rtw88 panels"` |
| `packages/kernel-drivers/device-tree-overlays/package.mk` | Checks `if [ ${DEVICE} != "RK3326" ]` to install `dtb_overlay`. | **IoC:** Control via standard options boolean. | `INSTALL_DTB_OVERLAY="yes|no"` |

### 6.2 Graphics & Multimedia Subsystems
These packages incorrectly query the device to establish driver versions and hardware acceleration flags.

| Target File | Current Anti-Pattern | Remediation Strategy | Required `options` Variable / Action |
| :--- | :--- | :--- | :--- |
| `packages/graphics/libmali/package.mk` | Hardcodes `g13p0` for RK3588, `r51p0` for S922X, `g24p0` default. | **IoC:** Read version directly from environment options. | `MALI_DRIVER_VERSION="g13p0"` |
| `packages/graphics/wlroots/package.mk` | Hardcodes specific git hashes and `PKG_VERSION` strings per device family. | **IoC:** Provide the Git hash/version tag via the options file. | `WLROOTS_VERSION="0.17.4-rk"` |
| `packages/graphics/vulkan-wsi-layer/package.mk` | Sets `HEAP_NAME=cma` if RK3588, else `linux,cma`. | **IoC:** Specify the heap string in options. | `VULKAN_WSI_HEAP_NAME="cma"` |
| `packages/multimedia/ffmpeg/package.mk` | Highly coupled logic checking `RK3588*`, `PC|RK*|S922X` for V4L2 and request API. | **IoC:** Flatten to boolean toggles in the options file. | `V4L2_SUPPORT="no"`, `PKG_V4L2_REQUEST="yes"` |
| `packages/graphics/mesa/package.mk` | S922X specific file removal `rm -f ${INSTALL}/usr/lib/libvulkan_panfrost.so`. | **Device Override:** Put the cleanup logic in a `post_makeinstall_target` override in `devices/S922X/packages/mesa/package.mk`. *(Note: Ensure upstream `post_makeinstall_target` logic is preserved if overwritten).* | N/A |

### 6.3 Emulators, Ports, & Apps
Applications are hardcoding hotkeys and performance variables at *build time*, which breaks portability.

| Target File | Current Anti-Pattern | Remediation Strategy | Required `options` Variable / Action |
| :--- | :--- | :--- | :--- |
| `packages/apps/moonlight/package.mk` | Injects `librga rkmpp` if `RK*`. | **Virtual Package Dependency:** Add to `ADDITIONAL_PACKAGES` in options. | N/A |
| `packages/emulators/standalone/drastic-sa/package.mk` | Injects `HOTKEY="guide"` specifically for RK3588 via `sed`. | **Quirks Engine:** Build scripts must be generic. Start scripts should source a config fragment: `[ -f /usr/lib/autostart/quirks/platforms/$DEVICE/emulator_env ] && . /usr/lib/autostart/quirks/platforms/$DEVICE/emulator_env` before launch. | N/A |
| `standalone/cemu-sa/scripts/start_cemu.sh`<br>`standalone/azahar-sa/scripts/start_azahar.sh` | Shell scripts executing `if [ "$DEVICE" = ... ]` for performance tuning. | **Quirks Engine:** Rely on platform environment hooks or universal feature flags set by `001-device_config` at runtime. | Check `$DEVICE_HAS_TOUCHSCREEN` instead of `$DEVICE`. |

### 6.4 Global Scripts & System Utilities
Base OS utilities must be decoupled from device names and rely instead on generic system capability flags or quirk hooks.

| Target File | Current Anti-Pattern | Remediation Strategy | Required `options` Variable / Action |
| :--- | :--- | :--- | :--- |
| `sysutils/powerstate/sources/powerstate.sh`<br>`sysutils/sleep/sources/sleep.sh` | Massive case blocks defining CPU governors, GPU frequencies, and fan controls per device. | **Data Driven Execution:** Global scripts should read generic capability variables exported by `001-device_config` (e.g., `$DEVICE_CPU_GOV_PERFORMANCE`), falling back to safe defaults, rather than creating 15 separate device-forked hook scripts. | Define `$DEVICE_CPU_GOV_*`, `$DEVICE_GPU_FREQ_*` in quirks runtime config. |
| `rocknix/sources/scripts/rocknix-info`<br>`runemu.sh`<br>`setsettings.sh` | Logic forks for specific hardware naming conventions and capabilities. | **Data Driven Execution:** Map these via standard environment variables initialized by `001-device_config` in the quirks folder. | Export `DEVICE_USES_ZRAM="yes"`, `DEVICE_HAS_DUAL_SCREEN="true"` |
| `packages/hardware/quirks/package.mk` | Checks `if [ "${DEVICE}" = "RK3566" ]` to enable `volume-fixup.service`. | **Platform Isolation:** Relocate `volume-fixup.service` to `quirks/platforms/RK3566/system.d/`. `post_install()` will blindly iterate and enable any `.service` found in the platform's `system.d/` dir. | N/A |

## 7. Device Migration Matrix

The following matrix dictates the required folder reorganization for Phase 1. It moves the flat `quirks/devices/*` structure into the explicit `quirks/platforms/$DEVICE/devices/*` hierarchy, establishing runtime isolation.

| Physical Device | Target SoC (`$DEVICE`) | Current Quirks Path | Proposed Quirks Path |
| :--- | :--- | :--- | :--- |
| **Anbernic RG CubeXX** | **H700** | `devices/Anbernic RG CubeXX/` | `platforms/H700/devices/Anbernic RG CubeXX/` |
| **Anbernic RG40XX H** | **H700** | `devices/Anbernic RG40XX H/` | `platforms/H700/devices/Anbernic RG40XX H/` |
| **Anbernic RG40XX V** | **H700** | `devices/Anbernic RG40XX V/` | `platforms/H700/devices/Anbernic RG40XX V/` |
| **Anbernic RG DS** | **RK3326** | `devices/Anbernic RG DS/` | `platforms/RK3326/devices/Anbernic RG DS/` |
| **Anbernic RG351M** | **RK3326** | `devices/Anbernic RG351M/` | `platforms/RK3326/devices/Anbernic RG351M/` |
| **Anbernic RG351V** | **RK3326** | `devices/Anbernic RG351V/` | `platforms/RK3326/devices/Anbernic RG351V/` |
| **Game Console R33S** | **RK3326** | `devices/Game Console R33S/` | `platforms/RK3326/devices/Game Console R33S/` |
| **Game Console R36S** | **RK3326** | `devices/Game Console R36S/` | `platforms/RK3326/devices/Game Console R36S/` |
| **Gameforce CHI** | **RK3326** | `devices/Gameforce CHI/` | `platforms/RK3326/devices/Gameforce CHI/` |
| **Generic EE clone** | **RK3326** | `devices/Generic EE clone/` | `platforms/RK3326/devices/Generic EE clone/` |
| **MagicX XU Mini M** | **RK3326** | `devices/MagicX XU Mini M/` | `platforms/RK3326/devices/MagicX XU Mini M/` |
| **MagicX XU10** | **RK3326** | `devices/MagicX XU10/` | `platforms/RK3326/devices/MagicX XU10/` |
| **ODROID-GO Advance** | **RK3326** | `devices/ODROID-GO Advance/` | `platforms/RK3326/devices/ODROID-GO Advance/` |
| **ODROID-GO Advance Black Edition** | **RK3326** | `devices/ODROID-GO Advance Black Edition/` | `platforms/RK3326/devices/ODROID-GO Advance Black Edition/` |
| **ODROID-GO Super** | **RK3326** | `devices/ODROID-GO Super/` | `platforms/RK3326/devices/ODROID-GO Super/` |
| **Powkiddy RGB10** | **RK3326** | `devices/Powkiddy RGB10/` | `platforms/RK3326/devices/Powkiddy RGB10/` |
| **Powkiddy RGB10X** | **RK3326** | `devices/Powkiddy RGB10X/` | `platforms/RK3326/devices/Powkiddy RGB10X/` |
| **Powkiddy RGB20 Pro** | **RK3326** | `devices/Powkiddy RGB20 Pro/` | `platforms/RK3326/devices/Powkiddy RGB20 Pro/` |
| **Powkiddy RGB20S** | **RK3326** | `devices/Powkiddy RGB20S/` | `platforms/RK3326/devices/Powkiddy RGB20S/` |
| **Anbernic RG552** | **RK3399** | `devices/Anbernic RG552/` | `platforms/RK3399/devices/Anbernic RG552/` |
| **Anbernic RG ARC-D** | **RK3566** | `devices/Anbernic RG ARC-D/` | `platforms/RK3566/devices/Anbernic RG ARC-D/` |
| **Anbernic RG ARC-S** | **RK3566** | `devices/Anbernic RG ARC-S/` | `platforms/RK3566/devices/Anbernic RG ARC-S/` |
| **Anbernic RG353M** | **RK3566** | `devices/Anbernic RG353M/` | `platforms/RK3566/devices/Anbernic RG353M/` |
| **Anbernic RG353P** | **RK3566** | `devices/Anbernic RG353P/` | `platforms/RK3566/devices/Anbernic RG353P/` |
| **Anbernic RG353PS** | **RK3566** | `devices/Anbernic RG353PS/` | `platforms/RK3566/devices/Anbernic RG353PS/` |
| **Anbernic RG353V** | **RK3566** | `devices/Anbernic RG353V/` | `platforms/RK3566/devices/Anbernic RG353V/` |
| **Anbernic RG353VS** | **RK3566** | `devices/Anbernic RG353VS/` | `platforms/RK3566/devices/Anbernic RG353VS/` |
| **Anbernic RG503** | **RK3566** | `devices/Anbernic RG503/` | `platforms/RK3566/devices/Anbernic RG503/` |
| **Powkiddy RGB10 Max 3** | **RK3566** | `devices/Powkiddy RGB10 Max 3/` | `platforms/RK3566/devices/Powkiddy RGB10 Max 3/` |
| **Powkiddy RGB20SX** | **RK3566** | `devices/Powkiddy RGB20SX/` | `platforms/RK3566/devices/Powkiddy RGB20SX/` |
| **Powkiddy RGB30** | **RK3566** | `devices/Powkiddy RGB30/` | `platforms/RK3566/devices/Powkiddy RGB30/` |
| **Powkiddy RK2023** | **RK3566** | `devices/Powkiddy RK2023/` | `platforms/RK3566/devices/Powkiddy RK2023/` |
| **Powkiddy x35s** | **RK3566** | `devices/Powkiddy x35s/` | `platforms/RK3566/devices/Powkiddy x35s/` |
| **Powkiddy x55** | **RK3566** | `devices/Powkiddy x55/` | `platforms/RK3566/devices/Powkiddy x55/` |
| **GameForce ACE** | **RK3588** | `devices/GameForce ACE/` | `platforms/RK3588/devices/GameForce ACE/` |
| **RetrOLED CM5** | **RK3588** | `devices/RetrOLED CM5/` | `platforms/RK3588/devices/RetrOLED CM5/` |
| **Retro Lite CM5** | **RK3588** | `devices/Retro Lite CM5/` | `platforms/RK3588/devices/Retro Lite CM5/` |
| **Hardkernel ODROID-GO-Ultra** | **S922X** | `devices/Hardkernel ODROID-GO-Ultra/` | `platforms/S922X/devices/Hardkernel ODROID-GO-Ultra/` |
| **Powkiddy RGB10 MAX 3 Pro** | **S922X** | `devices/Powkiddy RGB10 MAX 3 Pro/` | `platforms/S922X/devices/Powkiddy RGB10 MAX 3 Pro/` |
| **AYN Odin** | **SDM845** | `devices/AYN Odin/` | `platforms/SDM845/devices/AYN Odin/` |
| **Retroid Pocket 5** | **SM8250** | `devices/Retroid Pocket 5/` | `platforms/SM8250/devices/Retroid Pocket 5/` |
| **Retroid Pocket Flip2** | **SM8250** | `devices/Retroid Pocket Flip2/` | `platforms/SM8250/devices/Retroid Pocket Flip2/` |
| **Retroid Pocket Mini** | **SM8250** | `devices/Retroid Pocket Mini/` | `platforms/SM8250/devices/Retroid Pocket Mini/` |
| **Retroid Pocket Mini V2** | **SM8250** | `devices/Retroid Pocket Mini V2/` | `platforms/SM8250/devices/Retroid Pocket Mini V2/` |
| **AYANEO Pocket ACE** | **SM8550** | `devices/AYANEO Pocket ACE/` | `platforms/SM8550/devices/AYANEO Pocket ACE/` |
| **AYANEO Pocket DMG** | **SM8550** | `devices/AYANEO Pocket DMG/` | `platforms/SM8550/devices/AYANEO Pocket DMG/` |
| **AYANEO Pocket EVO** | **SM8550** | `devices/AYANEO Pocket EVO/` | `platforms/SM8550/devices/AYANEO Pocket EVO/` |
| **AYN Odin 2** | **SM8550** | `devices/AYN Odin 2/` | `platforms/SM8550/devices/AYN Odin 2/` |
| **AYN Odin 2 Portal** | **SM8550** | `devices/AYN Odin 2 Portal/` | `platforms/SM8550/devices/AYN Odin 2 Portal/` |
| **AYN Thor** | **SM8550** | `devices/AYN Thor/` | `platforms/SM8550/devices/AYN Thor/` |
| **AYANEO Pocket DS** | **SM8650** | `devices/AYANEO Pocket DS/` | `platforms/SM8650/devices/AYANEO Pocket DS/` |
| **AYANEO Pocket S2** | **SM8650** | `devices/AYANEO Pocket S2/` | `platforms/SM8650/devices/AYANEO Pocket S2/` |
| **KONKR Pocket FIT** | **SM8650** | `devices/KONKR Pocket FIT/` | `platforms/SM8650/devices/KONKR Pocket FIT/` |
| **Retroid Pocket 6** | **SM8650** | `devices/Retroid Pocket 6/` | `platforms/SM8650/devices/Retroid Pocket 6/` |

*(Note: If future devices share a physical name across different SoC targets, common scripts should be established in `quirks/common/devices/` and symlinked into the respective platform directories below to prevent code drift.)*
