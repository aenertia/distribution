#!/bin/bash

# Target to scan: Can be a file or a directory (defaults to current directory)
TARGET="${1:-.}"
# File pattern to search for when a directory is provided
FILE_PATTERN="linux*.conf"

FILES_TO_PROCESS=()

if [ -f "$TARGET" ]; then
    # User provided a specific file
    FILES_TO_PROCESS+=("$TARGET")
elif [ -d "$TARGET" ]; then
    # User provided a directory, scan recursively
    echo "Scanning '$TARGET' recursively for files matching '$FILE_PATTERN'..."
    while IFS= read -r -d '' file; do
        FILES_TO_PROCESS+=("$file")
    done < <(find "$TARGET" -type f -name "$FILE_PATTERN" -print0)
else
    echo "Error: '$TARGET' is not a valid file or directory."
    exit 1
fi

if [ ${#FILES_TO_PROCESS[@]} -eq 0 ]; then
    echo "No config files found."
    exit 0
fi

# List of symbols to enforce as Built-in (=y)
TARGET_CONFIGS=(
    # --- Core Gadget Support ---
    "CONFIG_USB_GADGET"
    "CONFIG_USB_CONFIGFS"
    "CONFIG_USB_ROLE_SWITCH"  # Critical for 6.x Dual Role
    
    # --- ConfigFS Functions (Minimal Set: Network, Serial, Storage, MTP) ---
    "CONFIG_USB_CONFIGFS_SERIAL"       # Serial Gadget
    "CONFIG_USB_CONFIGFS_ACM"          # CDC ACM (Serial)
    "CONFIG_USB_CONFIGFS_NCM"          # CDC NCM (Modern Network)
    "CONFIG_USB_CONFIGFS_ECM"          # CDC ECM (Legacy Network)
    "CONFIG_USB_CONFIGFS_ECM_SUBSET"   # CDC ECM Subset
    "CONFIG_USB_CONFIGFS_RNDIS"        # RNDIS (Windows Network)
    "CONFIG_USB_CONFIGFS_MASS_STORAGE" # Mass Storage
    "CONFIG_USB_CONFIGFS_F_FS"         # FunctionFS (Required for Userspace MTP/ADB)

    # --- Controller Drivers (Mainline) ---
    "CONFIG_USB_DWC3"
    "CONFIG_USB_DWC3_DUAL_ROLE" # Preferred over GADGET_ONLY for OTG ports
    "CONFIG_USB_DWC3_OF_SIMPLE" # Mainline glue for Rockchip
    "CONFIG_USB_DWC2"
    "CONFIG_USB_DWC2_DUAL_ROLE" # Critical for RK3326/DWC2 hardware
    
    # --- PHY Drivers (Rockchip Mainline) ---
    "CONFIG_PHY_ROCKCHIP_INNO_USB2"        # RK3399/Generic
    "CONFIG_PHY_ROCKCHIP_TYPEC"            # RK3399 Type-C
    "CONFIG_PHY_ROCKCHIP_NANENG_COMBO_PHY" # RK356x / RK3588
)

# Symbols to Explicitly Disable (Conflict with Dual Role)
CONFLICT_CONFIGS=(
    "CONFIG_USB_DWC3_GADGET" # Conflicts with DWC3_DUAL_ROLE
    "CONFIG_USB_DWC3_HOST"   # Conflicts with DWC3_DUAL_ROLE
)

echo "Found ${#FILES_TO_PROCESS[@]} file(s) to process."

for CONFIG_FILE in "${FILES_TO_PROCESS[@]}"; do
    echo "--------------------------------------------------------"
    echo "Processing: $CONFIG_FILE"
    
    # 1. Disable Conflicts First
    for CONFLICT in "${CONFLICT_CONFIGS[@]}"; do
        if grep -q "^$CONFLICT=y" "$CONFIG_FILE"; then
            echo -e "[\e[34mDIS\e[0m] Disabling conflicting $CONFLICT (forcing to 'is not set')"
            sed -i "s/^$CONFLICT=y/# $CONFLICT is not set/" "$CONFIG_FILE"
        fi
    done

    # 2. Enable Target Configs
    for CFG in "${TARGET_CONFIGS[@]}"; do
        # check if grep finds the string at all
        if grep -q "^$CFG=" "$CONFIG_FILE"; then
            # It is set (either y or m)
            CURRENT_VAL=$(grep "^$CFG=" "$CONFIG_FILE" | cut -d'=' -f2)
            if [ "$CURRENT_VAL" == "y" ]; then
                echo -e "[\e[32mOK\e[0m] $CFG is already set to 'y'"
            else
                echo -e "[\e[33mMOD\e[0m] $CFG was '$CURRENT_VAL'. Changing to 'y'..."
                sed -i "s/^$CFG=.*/$CFG=y/" "$CONFIG_FILE"
            fi
        elif grep -q "^# $CFG is not set" "$CONFIG_FILE"; then
            # It is commented out
            echo -e "[\e[33mSET\e[0m] $CFG was 'not set'. Enabling..."
            sed -i "s/^# $CFG is not set/$CFG=y/" "$CONFIG_FILE"
        else
            # It is missing completely
            echo -e "[\e[31mNEW\e[0m] $CFG not found. Appending..."
            echo "$CFG=y" >> "$CONFIG_FILE"
        fi
    done
done

echo "--------------------------------------------------------"
echo "Done. Please rebuild the kernel."
