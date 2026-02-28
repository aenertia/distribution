#!/bin/bash

# ROCKNIX Kernel Memory Tuning Applicator
# Features: Process Madvise, Read-Only THP for FS, THP Swap, Shmem THP Madvise
# Targets: H700, RK3326, RK3399, RK3566, RK3588, S922X, SDM845, SM8250, SM8550, SM8650

# Array of target devices
TARGETS=("H700" "RK3326" "RK3399" "RK3566" "RK3588" "S922X" "SDM845" "SM8250" "SM8550" "SM8650")

# Base path to devices directory (relative to rocknix root)
BASE_PATH="projects/ROCKNIX/devices"

# Configuration options to enable
# Format: [CONFIG_KEY]="VALUE"
declare -A KERNEL_OPTS
KERNEL_OPTS["CONFIG_PROCESS_MADVISE"]="y"
KERNEL_OPTS["CONFIG_READ_ONLY_THP_FOR_FS"]="y"
KERNEL_OPTS["CONFIG_THP_SWAP"]="y"
KERNEL_OPTS["CONFIG_TRANSPARENT_HUGEPAGE_SHMEM_HUGE_MADVISE"]="y"

# Optional: ARM64 Contiguous PTEs (kernel 6.7+)
# We try to set it; if the kernel is too old, Kconfig will just ignore it.
KERNEL_OPTS["CONFIG_ARM64_CONTPTE"]="y"

echo "Starting kernel tuning for memory optimizations..."

for TARGET in "${TARGETS[@]}"; do
    CONFIG_FILE="${BASE_PATH}/${TARGET}/linux/linux.aarch64.conf"

    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Processing ${TARGET}..."
        
        for CONFIG in "${!KERNEL_OPTS[@]}"; do
            VALUE="${KERNEL_OPTS[$CONFIG]}"
            NEW_LINE="${CONFIG}=${VALUE}"
            
            # Check if the config exists in the file (active or commented out)
            if grep -qE "^#? ?${CONFIG}(=| is not set)" "$CONFIG_FILE"; then
                # Edit in place: preserve location, update value
                # Use a temporary file to ensure safe editing
                sed -i "s|^#\? \?${CONFIG}.*|${NEW_LINE}|" "$CONFIG_FILE"
                echo "  Updated: ${CONFIG}"
            else
                # Append to end if not found
                echo "${NEW_LINE}" >> "$CONFIG_FILE"
                echo "  Appended: ${CONFIG}"
            fi
        done
    else
        echo "Warning: Config file not found for ${TARGET} at ${CONFIG_FILE}"
    fi
done

echo "Done."
