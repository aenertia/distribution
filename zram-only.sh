#!/bin/bash
# ROCKNIX Memory Manager - Explicit Multi-Comp & Backend Activation
# Includes optional LZ4/LZ4HC backends while maintaining LZO-RLE/ZSTD tiering

TARGET_CONFIGS=$(find projects/ROCKNIX/devices -name "linux.aarch64.conf")

for CONF in $TARGET_CONFIGS; do
    echo "Processing: $CONF"

    # 1. PSI & Cgroup Freezer (Core Requirements)
    # Enable PSI for pressure monitoring and Freezer for suspend stability [cite: 1, 34, 35]
    sed -i 's/# CONFIG_PSI is not set/CONFIG_PSI=y\n# CONFIG_PSI_DEFAULT_DISABLED is not set/' "$CONF"
    sed -i 's/# CONFIG_CGROUP_FREEZER is not set/CONFIG_CGROUP_FREEZER=y/' "$CONF"
    grep -q "CONFIG_FREEZER=y" "$CONF" || echo "CONFIG_FREEZER=y" >> "$CONF"

    # 2. Modularize ZRAM and ZSMALLOC
    # Required for runtime algorithm switching and hybrid tiering [cite: 6, 11, 19, 25]
    sed -i 's/CONFIG_ZRAM=y/CONFIG_ZRAM=m/' "$CONF"
    sed -i 's/# CONFIG_ZRAM is not set/CONFIG_ZRAM=m/' "$CONF"
    sed -i 's/CONFIG_ZSMALLOC=y/CONFIG_ZSMALLOC=m/' "$CONF"
    sed -i 's/# CONFIG_ZSMALLOC is not set/CONFIG_ZSMALLOC=m/' "$CONF"

    # 3. Explicit Multi-Comp & Backend Alignment
    # Purge existing ZRAM settings to prevent conflicts with legacy defaults [cite: 23]
    sed -i '/CONFIG_ZRAM_BACKEND/d' "$CONF"
    sed -i '/CONFIG_ZRAM_DEF_COMP/d' "$CONF"
    sed -i '/CONFIG_ZRAM_MULTI_COMP/d' "$CONF"
    sed -i '/CONFIG_ZRAM_WRITEBACK/d' "$CONF"

    # Inject the hybrid pipeline + optional LZ4/LZ4HC backends
    # Primary: LZO-RLE (latency) | Secondary: ZSTD (density) [cite: 66, 173]
    sed -i '/CONFIG_ZRAM=m/a \
CONFIG_ZRAM_BACKEND_LZ4=y\
CONFIG_ZRAM_BACKEND_LZ4HC=y\
CONFIG_ZRAM_BACKEND_LZO=y\
CONFIG_ZRAM_BACKEND_ZSTD=y\
CONFIG_ZRAM_DEF_COMP_LZORLE=y\
CONFIG_ZRAM_DEF_COMP="lzo-rle"\
CONFIG_ZRAM_WRITEBACK=y\
CONFIG_ZRAM_MULTI_COMP=y' "$CONF"

    # 4. Standardize ZSMALLOC
    # Ensure standardized chain size 8 [cite: 1, 13, 28, 42]
    sed -i '/CONFIG_ZSMALLOC_CHAIN_SIZE/d' "$CONF"
    sed -i '/CONFIG_ZSMALLOC=m/a CONFIG_ZSMALLOC_CHAIN_SIZE=8' "$CONF"

    # 5. Global Memory Tuning (KSM & THP)
    # Enable deduplication and force THP to madvise [cite: 7, 13, 19, 28]
    sed -i 's/# CONFIG_KSM is not set/CONFIG_KSM=y/' "$CONF"
    sed -i 's/CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y/# CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS is not set/' "$CONF"
    sed -i 's/# CONFIG_TRANSPARENT_HUGEPAGE_MADVISE is not set/CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y/' "$CONF"

    # 6. Built-in Compression Support
    # Required as built-ins to support modular ZRAM backends [cite: 12, 18, 27, 33]
    sed -i 's/CONFIG_CRYPTO_ZSTD=m/CONFIG_CRYPTO_ZSTD=y/' "$CONF"
    sed -i 's/# CONFIG_CRYPTO_ZSTD is not set/CONFIG_CRYPTO_ZSTD=y/' "$CONF"
    sed -i 's/# CONFIG_CRYPTO_LZO is not set/CONFIG_CRYPTO_LZO=y/' "$CONF"

    # 7. SM8650 Specific Hardware Preservation
    # Toggles target-specific hardware symbols in-place [cite: 55, 60, 61]
    if [[ "$CONF" == *"SM8650"* ]]; then
        sed -i 's/# CONFIG_DRM_PANEL_AR14 is not set/CONFIG_DRM_PANEL_AR14=y/' "$CONF"
        sed -i 's/CONFIG_DRM_PANEL_AR14=m/CONFIG_DRM_PANEL_AR14=y/' "$CONF"
        sed -i 's/# CONFIG_PCI_PWRCTRL_UPD720201 is not set/CONFIG_PCI_PWRCTRL_UPD720201=m/' "$CONF"
    fi

done

echo "ROCKNIX Memory Subsystem Standardized with Optional LZ4 Backends."
