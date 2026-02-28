#!/bin/bash

SYMBOLS=(
    "CONFIG_TRANSPARENT_HUGEPAGE"
    "CONFIG_TRANSPARENT_HUGEPAGE_MADVISE"
    "CONFIG_READ_ONLY_THP_FOR_FS"
    "CONFIG_THP_SWAP"
    "CONFIG_SWIOTLB"
    "CONFIG_ARM64_CONT_PTE"
    "CONFIG_COMPACTION"
    "CONFIG_MIGRATION"
    "CONFIG_CONTIG_ALLOC"
)

MAX_ORDER_SYM="CONFIG_ARCH_FORCE_MAX_ORDER"
FILE_NAME="linux.aarch64.conf"

find . -type f -name "$FILE_NAME" | while read -r CONF_PATH; do
    echo "Surgically updating: $CONF_PATH"
    
    for SYM in "${SYMBOLS[@]}"; do
        # If symbol exists in any form, replace it in-place using awk
        if grep -qE "^(# )?${SYM}([ =]|$)" "$CONF_PATH"; then
            awk -v s="$SYM" -v v="y" '
                $0 ~ "^(# )?" s "([ =]|$)" { print s "=" v; next } 
                { print }
            ' "$CONF_PATH" > "${CONF_PATH}.tmp" && mv "${CONF_PATH}.tmp" "$CONF_PATH"
        else
            # Only append if totally missing
            echo "${SYM}=y" >> "$CONF_PATH"
        fi
    done

    # Handle MAX_ORDER: leave existing, add 10 if missing.
    if ! grep -q -w "$MAX_ORDER_SYM" "$CONF_PATH"; then
        echo "${MAX_ORDER_SYM}=10" >> "$CONF_PATH"
    fi
done

echo "Update complete. Logic maintained."
