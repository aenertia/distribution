#!/bin/bash

# 1. Define the Root Directory
TARGET_DIR="projects/ROCKNIX/devices"

# ==============================================================================
# GLOBAL CONFIGURATION (Applied to ALL Kernels 5.18 -> 6.19)
# ==============================================================================
read -r -d '' GLOBAL_CONFIGS << 'EOM'
# --- Networking Defaults (Critical for BBR/FQ_CODEL) ---
# Forces hidden booleans so string defaults are accepted by Kconfig
CONFIG_NET_SCHED=y
CONFIG_NET_SCH_FQ_CODEL=y
CONFIG_NET_SCH_DEFAULT=y
CONFIG_DEFAULT_FQ_CODEL=y
CONFIG_DEFAULT_NET_SCH="fq_codel"
CONFIG_TCP_CONG_ADVANCED=y
CONFIG_TCP_CONG_BBR=y
CONFIG_DEFAULT_BBR=y
CONFIG_DEFAULT_TCP_CONG="bbr"
CONFIG_TCP_CONG_CUBIC=y

# --- Core Networking ---
CONFIG_INET=y
CONFIG_IPV6=y
CONFIG_IP_FORWARD=y
CONFIG_IP_MULTICAST=y
CONFIG_IP_ADVANCED_ROUTER=y
CONFIG_IP_MULTIPLE_TABLES=y
CONFIG_IP_MROUTE=y
CONFIG_IP_MROUTE_COMMON=y
CONFIG_IPV6_ROUTER_PREF=y
CONFIG_IPV6_ROUTE_INFO=y
CONFIG_IPV6_OPTIMISTIC_DAD=y
CONFIG_IPV6_MULTIPLE_TABLES=y
CONFIG_IPV6_SUBTREES=y
CONFIG_IPV6_MROUTE=y
CONFIG_IPV6_PIMSM_V2=y
CONFIG_FIB_RULES=y

# --- Netfilter / Firewall (Standardized) ---
CONFIG_NETFILTER=y
CONFIG_NETFILTER_ADVANCED=y
CONFIG_NF_CONNTRACK=m
CONFIG_NF_CONNTRACK_IPV6=m
CONFIG_NF_TABLES=m
CONFIG_NF_TABLES_INET=y
CONFIG_NF_TABLES_IPV4=y
CONFIG_NF_TABLES_IPV6=y
CONFIG_NFT_NAT=m
CONFIG_NFT_MASQ=m
CONFIG_NFT_MASQ_IPV6=m
CONFIG_NETFILTER_XTABLES=m
CONFIG_NFT_COMPAT=m
CONFIG_IP_NF_IPTABLES=m
CONFIG_IP_NF_FILTER=m
CONFIG_IP_NF_TARGET_MASQUERADE=m
CONFIG_IP_NF_MANGLE=m
CONFIG_IP6_NF_IPTABLES=m
CONFIG_IP6_NF_FILTER=m
CONFIG_IP6_NF_MANGLE=m
CONFIG_NF_DEFRAG_IPV4=m
CONFIG_NF_DEFRAG_IPV6=m

# --- VPN & Bridging (Minimal Support) ---
# Removed IPVLAN/MACVLAN to prevent NET_L3_MASTER_DEV enablement
CONFIG_TUN=m
CONFIG_WIREGUARD=m
CONFIG_BRIDGE=m
CONFIG_BRIDGE_IGMP_SNOOPING=y
CONFIG_BRIDGE_NETFILTER=m
CONFIG_VLAN_8021Q=m

# --- Bluetooth Networking ---
CONFIG_BT_BNEP=m
CONFIG_BT_BNEP_MC_FILTER=y
CONFIG_BT_BNEP_PROTO_FILTER=y

# --- Crypto API (Software Fallbacks) ---
CONFIG_KEYS=y
CONFIG_KEY_DH_OPERATIONS=y
CONFIG_ASYMMETRIC_KEY_TYPE=y
CONFIG_ASYMMETRIC_PUBLIC_KEY_SUBTYPE=y
CONFIG_X509_CERTIFICATE_PARSER=y
CONFIG_PKCS7_MESSAGE_PARSER=y
CONFIG_CRYPTO_USER=m
CONFIG_CRYPTO_USER_API_HASH=m
CONFIG_CRYPTO_USER_API_SKCIPHER=m
CONFIG_CRYPTO_USER_API_RNG=m
CONFIG_CRYPTO_USER_API_AEAD=m
CONFIG_CRYPTO_AES=m
CONFIG_CRYPTO_ECB=m
CONFIG_CRYPTO_SHA1=m
CONFIG_CRYPTO_SHA256=m
CONFIG_CRYPTO_SHA512=m
CONFIG_CRYPTO_CMAC=m
CONFIG_CRYPTO_HMAC=m
CONFIG_CRYPTO_DES=m
CONFIG_CRYPTO_ARC4=m
CONFIG_RANDOM_TRUST_CPU=y
EOM

# ==============================================================================
# DEVICE SPECIFIC OVERRIDES (Hardware Crypto & Kernel Fixes)
# ==============================================================================

# 1. SDM845 (Kernel 5.18) - Clean up Android/Legacy PM cruft
read -r -d '' SDM845_OVERRIDES << 'EOM'
# CONFIG_SUSPEND_FREEZER is not set
# CONFIG_PM_AUTOSLEEP is not set
# CONFIG_PM_WAKELOCKS is not set
# CONFIG_PM_GENERIC_DOMAINS_SLEEP is not set
# CONFIG_ACPI_TAD is not set
CONFIG_LEDS_CLASS_MULTICOLOR=y
CONFIG_PM_SLEEP=n
CONFIG_SUSPEND=n
EOM

# 2. Hardware Crypto Groups (Set to 'm' to enable if missing, but respect 'y')
read -r -d '' HW_CRYPTO_ROCKCHIP << 'EOM'
CONFIG_CRYPTO_DEV_ROCKCHIP=m
# --- REMOVE NFTABLES BLOAT & PENALTY ---
# Disable the entire Nftables subsystem to save RAM and CPU cycles
CONFIG_NF_TABLES=n
CONFIG_NF_TABLES_INET=n
CONFIG_NF_TABLES_IPV4=n
CONFIG_NF_TABLES_IPV6=n
CONFIG_NFT_COMPAT=n

# --- KILL THE TRANSLATION LAYER ---
# This stops the kernel from trying to emulate iptables
CONFIG_NETFILTER_XTABLES_COMPAT=n

# --- KEEP LEGACY FAST PATH ---
# Ensure these are enabled (y) or modular (m) to support your scripts
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_FILTER=y
CONFIG_IP_NF_MANGLE=m
CONFIG_IP_NF_NAT=m
EOM

read -r -d '' HW_CRYPTO_QCOM << 'EOM'
CONFIG_CRYPTO_DEV_QCE=m
CONFIG_CRYPTO_DEV_QCOM_RNG=m
EOM

read -r -d '' HW_CRYPTO_AMLOGIC << 'EOM'
CONFIG_CRYPTO_DEV_AMLOGIC_GXL=m
EOM

read -r -d '' HW_CRYPTO_ALLWINNER << 'EOM'
CONFIG_CRYPTO_DEV_SUN8I_CE=m
CONFIG_CRYPTO_DEV_SUN8I_SS=m
CONFIG_CRYPTO_DEV_ALLWINNER=m
EOM

# ==============================================================================
# LOGIC: Apply Config Function
# ==============================================================================
apply_config() {
    local config_list="$1"
    local target_file="$2"
    
    echo "$config_list" | while read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        # Parse the requested change
        if [[ "$line" =~ "is not set" ]]; then
            # Requesting to disable: "# CONFIG_FOO is not set"
            key=$(echo "$line" | awk '{print $2}')
            new_val="n" # Internal flag for 'not set'
            search_pattern="^#? ?${key}(=| is not set)"
            replace_line="# ${key} is not set"
        else
            # Requesting to enable: "CONFIG_FOO=y" or "CONFIG_FOO=m"
            key=$(echo "$line" | cut -d'=' -f1)
            new_val=$(echo "$line" | cut -d'=' -f2-)
            search_pattern="^#? ?${key}(=| is not set)"
            replace_line="${key}=${new_val}"
        fi

        # Find current state in the file
        current_match=$(grep -E "$search_pattern" "$target_file" | head -n 1)

        # --- LOGIC: Respect Existing 'y' (Upgrade Protection) ---
        # If we requested 'm', but the file already has 'y', we DO NOT downgrade it.
        # This keeps existing HW crypto drivers built-in if the maintainer wanted them that way.
        if [[ -n "$current_match" ]]; then
            if [[ "$current_match" =~ ${key}=y ]]; then
                # Only skip if we asked for 'm'. If we asked for 'n', we force the disable.
                if [[ "$new_val" == "m" ]]; then
                    continue
                fi
            fi
        fi

        # --- APPLY: In-Place Edit or Append ---
        # Escape special chars for sed (standard / delimiter)
        escaped_line=$(printf '%s\n' "$replace_line" | sed -e 's/[\/&]/\\&/g')
        
        if [[ -n "$current_match" ]]; then
            # Update existing line (active or commented)
            # Use '/' delimiter and -E flag for regex safety
            sed -i -E "s/$search_pattern.*/$escaped_line/" "$target_file"
        else
            # Append if missing completely
            echo "$replace_line" >> "$target_file"
        fi
    done
}

# ==============================================================================
# EXECUTION LOOP
# ==============================================================================
echo "Starting configuration update..."
echo "Target Directory: $TARGET_DIR"
echo "---------------------------------------------------------"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR not found."
    exit 1
fi

for device_path in "$TARGET_DIR"/*; do
    if [ -d "$device_path" ]; then
        config_file="$device_path/linux/linux.aarch64.conf"
        device_name=$(basename "$device_path")

        if [ -f "$config_file" ]; then
            echo "Processing: $device_name"
            
            # Create Backup
            cp "$config_file" "${config_file}.bak"

            # 1. Apply Global Defaults (All Kernels)
            apply_config "$GLOBAL_CONFIGS" "$config_file"

            # 2. Apply Device-Specific Overrides (Fixes)
            case "$device_name" in
                SDM845)
                    echo "  -> Applying SDM845 (Kernel 5.18) Specific Fixes..."
                    apply_config "$SDM845_OVERRIDES" "$config_file"
                    ;;
            esac

            # 3. Apply Hardware Crypto (Enable as Module if missing)
            # Match based on device prefix or specific name
            case "$device_name" in
                RK3326)
                    # RK3326, RK3399, RK3566, RK3588
                    echo "  -> Applying Rockchip Crypto..."
                    apply_config "$HW_CRYPTO_ROCKCHIP" "$config_file"
                    ;;
                SDM845|SM8250|SM8550|SM8650)
                    echo "  -> Applying Qualcomm Crypto..."
                    apply_config "$HW_CRYPTO_QCOM" "$config_file"
                    ;;
                S922X)
                    echo "  -> Applying Amlogic Crypto..."
                    apply_config "$HW_CRYPTO_AMLOGIC" "$config_file"
                    ;;
                H700)
                    echo "  -> Applying Allwinner Crypto..."
                    apply_config "$HW_CRYPTO_ALLWINNER" "$config_file"
                    ;;
            esac

        else
            echo "Skipping:   $device_name (No linux.aarch64.conf found)"
        fi
    fi
done

echo "---------------------------------------------------------"
echo "Update complete. Backups saved as .conf.bak"
