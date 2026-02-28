#!/bin/bash

# Target to scan: Can be a file or a directory (defaults to current directory)
TARGET="${1:-.}"
# File pattern to search for when a directory is provided
FILE_PATTERN="linux*.conf"

FILES_TO_PROCESS=()

if [ -f "$TARGET" ]; then
    FILES_TO_PROCESS+=("$TARGET")
elif [ -d "$TARGET" ]; then
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

# ==========================================
# 1. Define Config Groups
# ==========================================

# Common Gadget Framework (Applied to ALL devices)
COMMON_GADGET_CONFIGS=(
    "CONFIG_USB_GADGET"
    "CONFIG_USB_CONFIGFS"
    "CONFIG_USB_ROLE_SWITCH"
    "CONFIG_USB_CONFIGFS_SERIAL"
    "CONFIG_USB_CONFIGFS_ACM"
    "CONFIG_USB_CONFIGFS_NCM"
    "CONFIG_USB_CONFIGFS_ECM"
    "CONFIG_USB_CONFIGFS_ECM_SUBSET"
    "CONFIG_USB_CONFIGFS_RNDIS"
    "CONFIG_USB_CONFIGFS_MASS_STORAGE"
    "CONFIG_USB_CONFIGFS_F_FS"
)

# Controller: DWC3 Dual Role
DWC3_CONTROLLER_CONFIGS=(
    "CONFIG_USB_DWC3"
    "CONFIG_USB_DWC3_DUAL_ROLE"
)

# Controller: DWC2 Dual Role
DWC2_CONTROLLER_CONFIGS=(
    "CONFIG_USB_DWC2"
    "CONFIG_USB_DWC2_DUAL_ROLE"
)

# Rockchip Specific Glue & PHYs
RK_GLUE_CONFIGS=(
    "CONFIG_USB_DWC3_OF_SIMPLE"
    "CONFIG_PHY_ROCKCHIP_INNO_USB2"
)

# RK3399 Specific
RK3399_PHY_CONFIGS=(
    "CONFIG_PHY_ROCKCHIP_TYPEC"
)

# RK356x/RK3588 Specific
RK_NANENG_PHY_CONFIGS=(
    "CONFIG_PHY_ROCKCHIP_NANENG_COMBO_PHY"
)

# ==========================================
# 2. Conflict Handling Lists
# ==========================================
# These must be disabled to allow Dual Role to take precedence.
# We do this to ensure we don't accidentally leave a "Host Only" flag set,
# which would conflict with Dual Role and break the build or functionality.

DWC3_CONFLICTS=(
    "CONFIG_USB_DWC3_GADGET"
    "CONFIG_USB_DWC3_HOST"
)

DWC2_CONFLICTS=(
    "CONFIG_USB_DWC2_PERIPHERAL"
    "CONFIG_USB_DWC2_HOST"
)

# ==========================================
# 3. Processing Loop
# ==========================================

echo "Found ${#FILES_TO_PROCESS[@]} file(s) to process."

for CONFIG_FILE in "${FILES_TO_PROCESS[@]}"; do
    echo "--------------------------------------------------------"
    echo "Processing: $CONFIG_FILE"

    # Identify Device from Path
    DEVICE_NAME="UNKNOWN"
    if [[ "$CONFIG_FILE" =~ devices/([^/]+)/ ]]; then
        DEVICE_NAME="${BASH_REMATCH[1]}"
    fi
    echo "Detected Target: $DEVICE_NAME"

    # Start with the Common List
    APPLY_LIST=("${COMMON_GADGET_CONFIGS[@]}")

    # Flag to track which conflicts we need to clean for this specific file
    CLEAN_DWC3=false
    CLEAN_DWC2=false

    # --- Device Specific Logic ---
    case "$DEVICE_NAME" in
        "H700")
            # H700 uses MUSB (Sunxi). 
            # We ONLY apply common gadget framework. 
            # We do NOT touch DWC2/DWC3 settings to avoid breaking MUSB Host.
            ;;
            
        "RK3326")
            # Uses DWC2. Switch to Dual Role (includes Host).
            APPLY_LIST+=("${DWC2_CONTROLLER_CONFIGS[@]}")
            APPLY_LIST+=("CONFIG_PHY_ROCKCHIP_INNO_USB2")
            CLEAN_DWC2=true
            ;;
            
        "RK3399")
            # Uses DWC3 (Type-C) and DWC2. Switch both to Dual Role.
            APPLY_LIST+=("${DWC3_CONTROLLER_CONFIGS[@]}")
            APPLY_LIST+=("${DWC2_CONTROLLER_CONFIGS[@]}")
            APPLY_LIST+=("${RK_GLUE_CONFIGS[@]}")
            APPLY_LIST+=("${RK3399_PHY_CONFIGS[@]}")
            CLEAN_DWC3=true
            CLEAN_DWC2=true
            ;;
            
        "RK3566"|"RK3588")
            # Modern Rockchip DWC3. Switch to Dual Role.
            APPLY_LIST+=("${DWC3_CONTROLLER_CONFIGS[@]}")
            APPLY_LIST+=("${RK_GLUE_CONFIGS[@]}")
            APPLY_LIST+=("${RK_NANENG_PHY_CONFIGS[@]}")
            CLEAN_DWC3=true
            ;;
            
        "S922X")
            # Amlogic DWC3. Switch to Dual Role.
            APPLY_LIST+=("${DWC3_CONTROLLER_CONFIGS[@]}")
            CLEAN_DWC3=true
            ;;
            
        "SDM845"|"SM8250"|"SM8550"|"SM8650")
            # Qualcomm DWC3. Switch to Dual Role.
            # QCOM has its own glue (CONFIG_USB_DWC3_QCOM), typically already set.
            APPLY_LIST+=("${DWC3_CONTROLLER_CONFIGS[@]}")
            APPLY_LIST+=("${DWC2_CONTROLLER_CONFIGS[@]}") # Often used for legacy/debug
            CLEAN_DWC3=true
            CLEAN_DWC2=true
            ;;
            
        *)
            echo "Warning: Unknown device '$DEVICE_NAME'. Applying only common gadget configs."
            ;;
    esac

    # --- Step 1: Clean Conflicts (Preserve Host by ensuring Dual Role can take over) ---
    
    if [ "$CLEAN_DWC3" = true ]; then
        for CONFLICT in "${DWC3_CONFLICTS[@]}"; do
            if grep -q "^$CONFLICT=y" "$CONFIG_FILE"; then
                echo -e "[\e[34mDIS\e[0m] Disabling conflicting $CONFLICT (Switching to Dual Role)"
                sed -i "s/^$CONFLICT=y/# $CONFLICT is not set/" "$CONFIG_FILE"
            fi
        done
    fi

    if [ "$CLEAN_DWC2" = true ]; then
        for CONFLICT in "${DWC2_CONFLICTS[@]}"; do
            if grep -q "^$CONFLICT=y" "$CONFIG_FILE"; then
                echo -e "[\e[34mDIS\e[0m] Disabling conflicting $CONFLICT (Switching to Dual Role)"
                sed -i "s/^$CONFLICT=y/# $CONFLICT is not set/" "$CONFIG_FILE"
            fi
        done
    fi

    # --- Step 2: Apply Target Configs ---
    
    for CFG in "${APPLY_LIST[@]}"; do
        if grep -q "^$CFG=" "$CONFIG_FILE"; then
            # It exists (y or m)
            CURRENT_VAL=$(grep "^$CFG=" "$CONFIG_FILE" | cut -d'=' -f2)
            if [ "$CURRENT_VAL" == "y" ]; then
                echo -e "[\e[32mOK\e[0m] $CFG is set to 'y'"
            else
                echo -e "[\e[33mMOD\e[0m] $CFG was '$CURRENT_VAL'. Changing to 'y'..."
                sed -i "s/^$CFG=.*/$CFG=y/" "$CONFIG_FILE"
            fi
        elif grep -q "^# $CFG is not set" "$CONFIG_FILE"; then
            # Commented out
            echo -e "[\e[33mSET\e[0m] $CFG was 'not set'. Enabling..."
            sed -i "s/^# $CFG is not set/$CFG=y/" "$CONFIG_FILE"
        else
            # Missing
            echo -e "[\e[31mNEW\e[0m] $CFG not found. Appending..."
            echo "$CFG=y" >> "$CONFIG_FILE"
        fi
    done

done

echo "--------------------------------------------------------"
echo "Done. Please rebuild the kernel."
