#!/bin/bash

# 1. Define the Root Directory
TARGET_DIR="projects/ROCKNIX/devices"

# 2. Define the Configuration List
# Using the exact validated list provided + critical dependencies for defaults.
read -r -d '' NEW_CONFIGS << 'EOM'
# =================================================================
# NETWORKING SCHEDULING & CONGESTION
# =================================================================
CONFIG_NET_SCHED=y
CONFIG_NET_SCH_FQ_CODEL=y
CONFIG_NET_SCH_DEFAULT=y
CONFIG_DEFAULT_FQ_CODEL=y
CONFIG_DEFAULT_NET_SCH="fq_codel"
CONFIG_TCP_CONG_ADVANCED=y
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
CONFIG_IPV6_ROUTER_PREF=y
CONFIG_IPV6_ROUTE_INFO=y
CONFIG_IPV6_OPTIMISTIC_DAD=y
CONFIG_IPV6_MULTIPLE_TABLES=y
CONFIG_IPV6_SUBTREES=y
CONFIG_IPV6_MROUTE=y
CONFIG_IPV6_PIMSM_V2=y

# =================================================================
# NETFILTER: FIREWALL, NAT & COMPATIBILITY
# =================================================================
CONFIG_NETFILTER=y
CONFIG_NETFILTER_ADVANCED=y
CONFIG_NF_CONNTRACK=m
CONFIG_NF_CONNTRACK_IPV6=m
CONFIG_NF_TABLES=m
CONFIG_NF_TABLES_INET=y
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

# =================================================================
# VPN, TUNNELS & BRIDGING
# =================================================================
CONFIG_TUN=m
CONFIG_WIREGUARD=m
CONFIG_BRIDGE=m
CONFIG_BRIDGE_IGMP_SNOOPING=y
CONFIG_VLAN_8021Q=m

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
EOM

# 3. Execution Loop
echo "Starting configuration update for devices in: $TARGET_DIR"
echo "---------------------------------------------------------"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR not found. Please run this from the 'distribution' folder root."
    exit 1
fi

for device in "$TARGET_DIR"/*; do
    if [ -d "$device" ]; then
        config_file="$device/linux/linux.aarch64.conf"
        device_name=$(basename "$device")

        if [ -f "$config_file" ]; then
            echo "Processing: $device_name"
            
            # Create a backup just in case
            cp "$config_file" "${config_file}.bak"

            # Iterate through the config list
            echo "$NEW_CONFIGS" | while read -r line; do
                # Skip comments and empty lines in list
                [[ -z "$line" || "$line" =~ ^# ]] && continue

                # Parse Key and Value
                key=$(echo "$line" | cut -d'=' -f1)
                new_val=$(echo "$line" | cut -d'=' -f2-)
                
                # Check current state in file (Matches active 'FOO=y' OR commented '# FOO is not set')
                current_match=$(grep -E "^#? ?${key}(=| is not set)" "$config_file" | head -n 1)
                
                if [[ -z "$current_match" ]]; then
                    # Case 1: Entry does not exist -> Append to end
                    echo "$line" >> "$config_file"
                else
                    # Case 2: Entry exists -> Check value to ensure minimal changes
                    
                    # Extract current value for comparison
                    if [[ "$current_match" =~ ${key}=(.*) ]]; then
                        current_val="${BASH_REMATCH[1]}"
                    elif [[ "$current_match" =~ "is not set" ]]; then
                        current_val="n"
                    else
                        current_val="unknown"
                    fi
                    
                    # Minimal Change Check: If values match, do nothing (preserves timestamp/git noise)
                    # Note: We quote values to handle strings like "bbr" vs bbr safely
                    if [[ "$current_val" == "$new_val" || "$current_val" == "\"$new_val\"" ]]; then
                        continue
                    fi

                    # Respect Existing 'y': If we want 'm', but it is already 'y', leave it alone.
                    if [[ "$new_val" == "m" && "$current_val" == "y" ]]; then
                        continue
                    fi

                    # Apply Edit: In-place replacement of the specific line found
                    # Escape special chars for sed
                    escaped_line=$(printf '%s\n' "$line" | sed -e 's/[\/&]/\\&/g')
                    
                    # Regex matches the line (active or commented) and replaces it entirely
                    sed -i "s|^#\? \?${key}\(=.*\| is not set\)|$escaped_line|" "$config_file"
                fi
            done
        else
            echo "Skipping:   $device_name (No linux.aarch64.conf found)"
        fi
    fi
done

echo "---------------------------------------------------------"
echo "Update complete. Backups saved as .conf.bak"
