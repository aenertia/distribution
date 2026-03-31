# Architecture Decision Record: Investigation of Torzu Emulator Integration into Rocknix

**Date:** March 31, 2026

**Status:** Draft / Research Phase

**Context:** Rocknix OS Build System (LibreELEC/CoreELEC `package.mk` structure)

**Target Architecture:** Linux Aarch64 (Specifically targeting Qualcomm Snapdragon sm8250 and sm8550 SoCs)

## 1. Context and Problem Statement

Following the DMCA takedown of the Yuzu repository and its immediate successors, the Nintendo Switch emulation scene on Linux Aarch64 is highly fragmented. We require a stable, privacy-focused codebase that actively maintains **NCE (Native Code Execution)**. NCE is theorized to be critical for Aarch64 devices as it allows ARMv8 instructions to execute natively without JIT overhead, potentially dramatically improving battery life and performance.

We propose evaluating **Torzu**, currently believed to be the most active and resilient NCE-capable fork, for inclusion in the Rocknix build system.

To ensure optimal execution on high-end ARM SBCs and handhelds, this proposed build strategy suggests:

1. Utilizing the in-buildroot (Rocknix environment) versions of `llvm`, `clang`, and `ffmpeg`.

2. Applying specific microarchitecture optimizations (`-mcpu`, `-march`, `-mtune`) targeting the Snapdragon 865 (`sm8250`) and Snapdragon 8 Gen 2 (`sm8550`).

> **\[Agent Action Required: Ecosystem Check\]** > *Prompt:* "Search GitHub, Gitea, and GitLab for the most recently updated Nintendo Switch emulator forks with 'NCE' and 'Linux' in their commit histories. Verify if Torzu is still actively maintained as of today, or if a new fork (e.g., Sudachi-mirrors, Kenji NX) has superseded it."

## 2. Proposed Decision

We suggest introducing a new experimental Rocknix package definition for Torzu at `packages/emulation/torzu/package.mk`.

### 2.1 Build System & Toolchain

Torzu appears to require modern C++ features and heavy shader compilation. We hypothesize that forcing the use of Clang over GCC for compiling the target binary will yield better results, as community reports suggest Clang's optimization passes for Aarch64 NCE memory mapping are vastly superior in the Yuzu-fork ecosystem.

We intend to rely on Rocknix's internal dependencies using `PKG_DEPENDS_TARGET` rather than fetching pre-compiled external binaries to keep the image size down.

> **\[Agent Action Required: Toolchain Validation\]** > *Prompt:* "Analyze the Rocknix `packages/emulation` directory. Confirm if other heavy emulators (like Ryujinx or Dolphin) successfully use `PKG_DEPENDS_TARGET=\"llvm clang\"` or if they rely on statically linked pre-built binaries. Output a summary of the preferred Rocknix methodology for LLVM/Clang dependency injection."

### 2.2 Microarchitecture Optimizations

To potentially maximize NCE stability and rendering performance, we plan to inject conditional compiler flags based on the target SoC. The following optimizations are hypothesized to provide the best performance:

* **sm8250 (Snapdragon 865):** Built around Cortex-A77/A55 cores. We propose targeting `-mcpu=cortex-a77` to ensure the compiler schedules instructions efficiently for the big cores.

* **sm8550 (Snapdragon 8 Gen 2):** Built around Cortex-X3/A715/A510 cores. We suggest utilizing ARMv9-A instructions and SVE2 where applicable via `-mcpu=cortex-x3` and `-march=armv9-a+sve2`.

> **\[Agent Action Required: Compiler Flag Verification\]** > *Prompt:* "Cross-reference the LLVM/Clang documentation for ARMv9-A architecture. Verify if `-mcpu=cortex-x3` natively implies `-march=armv9-a+sve2`, or if explicitly declaring both flags causes compiler conflicts in Clang 18+."

### 2.3 Proposed `package.mk` Implementation Template

*Note to AI Assistants: This is a tentative template. Use the agent prompts above to validate these variables before generating the final `package.mk`.*

```
PKG_NAME="torzu"
PKG_VERSION="master" # TENTATIVE: Should pin to specific commit hash in production
PKG_SITE="[https://gitee.com/Jumy/torzu](https://gitee.com/Jumy/torzu)" # TENTATIVE: Needs live verification of mirror status
PKG_URL="[https://gitee.com/Jumy/torzu/repository/archive/master.zip](https://gitee.com/Jumy/torzu/repository/archive/master.zip)"
PKG_DEPENDS_TARGET="toolchain llvm clang ffmpeg sdl2 vulkan-headers vulkan-loader libva"
PKG_NEED_UNPACK="$PKG_DEPENDS_TARGET"
PKG_LONGDESC="Torzu is an experimental, privacy-focused fork of Yuzu, evaluating NCE support for Linux Aarch64."
PKG_TOOLCHAIN="cmake"

# Hypothesis: Clang produces better NCE/ARMv8 codegen than GCC
export CC="clang"
export CXX="clang++"

# Proposed base configuration for Aarch64 NCE
PKG_CMAKE_OPTS="-GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DYUZU_USE_EXTERNAL_SDL2=ON \
    -DYUZU_USE_EXTERNAL_VULKAN_HEADERS=ON \
    -DENABLE_COMPATIBILITY_LIST_DOWNLOAD=OFF \
    -DENABLE_NCE=ON \
    -DYUZU_TESTS=OFF"

# Proposed SoC Specific Optimizations
ifeq ($(DEVICE), sm8250)
    # Snapdragon 865 (Cortex-A77 / Cortex-A55)
    TARGET_CXXFLAGS += -mcpu=cortex-a77 -mtune=cortex-a77.cortex-a55 -O3
    TARGET_CFLAGS += -mcpu=cortex-a77 -mtune=cortex-a77.cortex-a55 -O3
else ifeq ($(DEVICE), sm8550)
    # Snapdragon 8 Gen 2 (Cortex-X3 / Cortex-A715 / Cortex-A510)
    TARGET_CXXFLAGS += -mcpu=cortex-x3 -mtune=cortex-x3.cortex-a715 -march=armv9-a+sve2+crypto -O3
    TARGET_CFLAGS += -mcpu=cortex-x3 -mtune=cortex-x3.cortex-a715 -march=armv9-a+sve2+crypto -O3
else
    # Generic Aarch64 Fallback
    TARGET_CXXFLAGS += -march=armv8-a -mtune=generic -O3
endif

# Ensure we attempt to use in-tree FFmpeg and LLVM provided by Rocknix
PKG_CMAKE_OPTS += "-DFFmpeg_DIR=$(SYSROOT_PREFIX)/usr/lib/cmake/ffmpeg \
                   -DLLVM_DIR=$(SYSROOT_PREFIX)/usr/lib/cmake/llvm"

post_makeinstall_target() {
    # Cleanup unnecessary dev headers if installed by cmake
    rm -rf $(INSTALL)/$(PKG_DIR)/usr/include
}

```

## 3. Hypothesized Consequences and Risks

* **Potential Benefit:** NCE may function efficiently on Linux Aarch64 handhelds, providing near-native execution overhead compared to standard JIT compilation.

* **Potential Benefit:** By attempting to rely on `PKG_DEPENDS_TARGET="llvm clang ffmpeg"`, we might successfully prevent library duplication in the Rocknix image.

* **High Risk (Availability):** Because Torzu relies on self-hosted infrastructure (e.g., Gitea/Dark Git), the `PKG_URL` and `PKG_SITE` are highly volatile. The build system will likely break if the hosts face DDOS or legal pressure.

* **Critical Risk (Kernel Page Size):** It is theorized that NCE strictly requires the Linux Kernel to be compiled with `CONFIG_ARM64_4K_PAGES=y`. If the specific Rocknix board configuration uses 16K pages, NCE will likely crash at runtime regardless of user-space compiler optimizations.

> **\[Agent Action Required: Kernel Page Size Audit\]** > *Prompt:* "Scan the Rocknix kernel configurations (typically found in `projects/Rockchip/devices/.../linux/` or `projects/Qualcomm/...`). Check the `CONFIG_ARM64_4K_PAGES` and `CONFIG_ARM64_16K_PAGES` flags for the `sm8250` and `sm8550` target devices. If they are using 16K pages, flag this ADR for immediate architectural revision, as NCE will inherently fail."

## 4. Open Research Questions

1. Does the inclusion of `-march=armv9-a+sve2+crypto` on `sm8550` cause runtime crashes in Torzu's standard ARMv8 NCE translation layer?

2. Are there any proprietary Vulkan driver issues (e.g., Turnip vs Freedreno) on Rocknix that conflict with Torzu's memory manager?

## 5. References

* **Rocknix Package Documentation:** <https://rocknix.org/contribute/packages/>

* **Torzu Arch Linux AUR (Context for dependencies):** <https://aur.archlinux.org/packages/torzu-git>

* **GCC/Clang ARM Options (sm8250/sm8550 tuning):** [Arm Compiler Documentation](https://developer.arm.com/community/arm-community-blogs/b/tools-software-ides-blog/posts/compiler-flags-across-architectures-march-mtune-and-mcpu)
