#!/bin/bash

# 1. Define the Root Directory
TARGET_DIR="projects/ROCKNIX/devices"

# 2. Define the Configuration List
# NOTE: Critical Networking & USB dependencies are forced to 'y' here
# to prevent 'make oldconfig' from dropping dependent features (like Dual Role).
read -r -d '' NEW_CONFIGS << 'EOM'
# =================================================================
# NETWORKING SCHEDULING & CONGESTION
# =================================================================
CONFIG_NET_SCHED=y
CONFIG_NET_SCH_FQ_CODEL=y
CONFIG_NET_SCH_DEFAULT=y
CONFIG_DEFAULT_FQ_CODEL=y
CONFIG_DEFAULT_NET_SCH="fq_codel"
CONFIG_TCP_CONG_BBR=y
CONFIG_DEFAULT_BBR=y
CONFIG_DEFAULT_TCP_CONG="bbr"

# =================================================================
# CORE NETWORKING & ROUTING
# =================================================================
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

# =================================================================
# NETFILTER: FIREWALL & NAT
# =================================================================
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

# =================================================================
# VPN, BRIDGING & AP SUPPORT
# =================================================================
CONFIG_TUN=m
CONFIG_WIREGUARD=m
CONFIG_BRIDGE=m
CONFIG_BRIDGE_IGMP_SNOOPING=y
CONFIG_BRIDGE_NETFILTER=m
CONFIG_VLAN_8021Q=m
CONFIG_MACVLAN=m
CONFIG_IPVLAN=m
CONFIG_IPVLAN_L3S=y
CONFIG_VETH=y

# =================================================================
# CRYPTO API
# =================================================================
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

# =================================================================
# USB GADGET & DUAL ROLE (Forced Y to prevent drops)
# =================================================================
CONFIG_USB_GADGET=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_F_RNDIS=y
CONFIG_USB_CONFIGFS_F_ECM=y
CONFIG_USB_CONFIGFS_F_FS=y
CONFIG_CONFIGFS_FS=y

# Inject Missing Dual Role Items
CONFIG_USB_DWC2_DUAL_ROLE=y
CONFIG_USB_DWC3_DUAL_ROLE=y
CONFIG_USB_MUSB_DUAL_ROLE=y
CONFIG_USB_CDNS3_GADGET=y

# =================================================================
# FILESYSTEMS & MISC
# =================================================================
CONFIG_CIFS=m
CONFIG_CIFS_ALLOW_INSECURE_LEGACY=y
CONFIG_RANDOM_TRUST_CPU=y
CONFIG_NETFS_SUPPORT=m
CONFIG_NLS_UCS2_UTILS=m
EOM

# 3. Execution Loop
echo "Starting configuration update for devices in: $TARGET_DIR"
echo "---------------------------------------------------------"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR not found. Please run this from the 'distribution' folder root."
    exit 1
fi

# Loop through each device directory
for device in "$TARGET_DIR"/*; do
    if [ -d "$device" ]; then
        config_file="$device/linux/linux.aarch64.conf"
        device_name=$(basename "$device")

        if [ -f "$config_file" ]; then
            echo "Processing: $device_name"
            
            # Create a backup just in case
            cp "$config_file" "${config_file}.bak"

            # Process every line in the NEW_CONFIGS variable
            echo "$NEW_CONFIGS" | while read -r line; do
                # Skip empty lines or comments in the source list
                [[ -z "$line" || "$line" =~ ^# ]] && continue

                # Parse Key and Value from list
                key=$(echo "$line" | cut -d'=' -f1)
                new_val=$(echo "$line" | cut -d'=' -f2-)
                
                # Check current state in the file
                # Regex looks for: Start of line, optional #, optional space, KEY, then = or space
                current_line=$(grep -E "^#? ?${key}(=| is not set)" "$config_file")
                
                # Determine current value in the file
                current_val="unset"
                if [[ -n "$current_line" ]]; then
                    if [[ "$current_line" =~ ${key}=([yYmM]) ]]; then
                        current_val="${BASH_REMATCH[1]}"
                    elif [[ "$current_line" =~ "is not set" ]]; then
                        current_val="unset"
                    fi
                fi

                # --- UPGRADE PROTECTION LOGIC ---
                # 1. If script wants 'm', but file has 'y', KEEP 'y' (Don't downgrade)
                if [[ "$new_val" == "m" && "$current_val" == "y" ]]; then
                    continue
                fi

                # 2. If script wants 'y', FORCE 'y' (Upgrade 'm' or 'unset' to 'y')
                # This ensures your Core Networking & Dual Role items are enforced.
                
                # Define the final line to write
                final_line="${key}=${new_val}"
                
                # Escape special chars for sed
                escaped_final_line=$(printf '%s\n' "$final_line" | sed -e 's/[\/&]/\\&/g')

                if [[ -n "$current_line" ]]; then
                    # Replace existing line (whether active or commented)
                    sed -i "s|^#\? \?${key}\(=.*\| is not set\)|\1|; s|^#\? \?${key}\(=.*\| is not set\)|$escaped_final_line|" "$config_file"
                else
                    # Key not found in file, append it
                    echo "$final_line" >> "$config_file"
                fi
            done
        else
            echo "Skipping:   $device_name (No linux.aarch64.conf found)"
        fi
    fi
done

echo "---------------------------------------------------------"
echo "Update complete. Backups saved as .conf.bak"
