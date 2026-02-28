#!/bin/bash
# scripts/xf40h-uboot-spl-fix.sh
# Fixes SPL SD Card initialization and Board Detection for XiFan XF40H
# This script is immune to patch fuzz and should be run during the U-Boot build phase.

# The ROCKNIX build system changes the current working directory to the package
# build directory before running pre_make_target. Let's check if we are already there.
if [ -f "dts/upstream/src/arm64/rockchip/rk3326-common-handheld.dts" ]; then
    UBOOT_DIR="."
elif [ -n "$PKG_BUILD" ] && [ -d "$PKG_BUILD" ]; then
    UBOOT_DIR="$PKG_BUILD"
else
    # Fallback if run manually from the distribution root
    UBOOT_DIR=$(ls -d build.*/build/u-boot-* 2>/dev/null | head -n 1)
fi

if [ -z "$UBOOT_DIR" ] || [ ! -d "$UBOOT_DIR" ]; then
    echo "Error: U-Boot build directory not found. Please ensure source is unpacked."
    exit 1
fi

DTS_FILE="$UBOOT_DIR/dts/upstream/src/arm64/rockchip/rk3326-common-handheld.dts"
GO2_C="$UBOOT_DIR/board/hardkernel/odroid_go2/go2.c"

# --- Part 1: U-Boot SPL Device Tree Fixes ---
if [ -f "$DTS_FILE" ]; then
    echo "Applying XF40H SPL SD-Card Workarounds via sed to $DTS_FILE..."

    # 1. Strip all UHS-I speed negotiations and existing voltage supplies.
    # The base ROCKNIX file has them commented out, which breaks budget cards.
    sed -i '/sd-uhs-sdr/d' "$DTS_FILE"
    sed -i '/vmmc-supply/d' "$DTS_FILE"
    sed -i '/vqmmc-supply/d' "$DTS_FILE"

    # 2. Append the necessary SPL flags safely at the end of the file.
    # CRITICAL: We MUST explicitly supply power to the SD card (vmmc-supply) 
    # otherwise the SPL will brownout the card and lock up the CPU.
    if ! grep -q "XF40H SPL Stability Overrides" "$DTS_FILE"; then
        cat << 'EOF' >> "$DTS_FILE"

/* XF40H SPL Stability Overrides appended via scripts/xf40h-uboot-spl-fix.sh */
/ {
    chosen {
        u-boot,spl-boot-order = &sdmmc, &emmc;
    };
};

&sdmmc {
    bus-width = <4>;
    disable-wp;
    max-frequency = <50000000>;
    no-1-8-v;
    u-boot,spl-fifo-mode;
    card-detect-delay = <800>;
    vmmc-supply = <&vcc_sd>;
    vqmmc-supply = <&vccio_sd>;
};

&sdio {
    bus-width = <4>;
    disable-wp;
    max-frequency = <50000000>;
    no-1-8-v;
    u-boot,spl-fifo-mode;
    vmmc-supply = <&vcc_sd>;
    vqmmc-supply = <&vccio_sd>;
};
EOF
        echo "Successfully appended XF40H overrides to U-Boot DTS."
    else
        echo "DTS overrides already present. Skipping append."
    fi
else
    echo "Warning: Target DTS file $DTS_FILE not found."
fi

# --- Part 2: U-Boot Board Detection (go2.c) Fixes ---
if [ -f "$GO2_C" ]; then
    echo "Applying XF40H Board Detection Workarounds via sed to $GO2_C..."

    if ! grep -q "XiFan XF40H" "$GO2_C"; then
        # Inject our fallback before the standard error check.
        # This completely bypasses the need to modify the volatile enum/struct arrays.
        sed -i '/if (board_id < 0)/i \
\t/* XF40H Fallback: ADC channel 1 is floating/maxed out (~65000) */\n\
\tif (board_id < 0 && adc_info > 50000) {\n\
\t\tenv_set("board_name", "XiFan XF40H");\n\
\t\tenv_set("fdtfile", "rockchip/rk3326-xifan-xf40h.dtb");\n\
\t\tenv_set_ulong("hwid_adc", adc_info);\n\
\t\treturn 0;\n\
\t}\n' "$GO2_C"

        # Expose hwid_adc for standard boards too
        sed -i '/env_set("fdtfile"/a \
\tenv_set_ulong("hwid_adc", adc_info);' "$GO2_C"

        echo "Successfully injected XF40H board detection into go2.c."
    else
        echo "Board detection logic already present. Skipping go2.c injection."
    fi
else
    echo "Warning: Target C file $GO2_C not found."
fi
