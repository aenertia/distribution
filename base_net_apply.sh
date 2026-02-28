#!/bin/bash

# 1. Define the Root Directory
# Adjust this path if you run the script from a different location
TARGET_DIR="projects/ROCKNIX/devices"

# 2. Define the Configuration List
# Using a HEREDOC variable to store the exact list provided
read -r -d '' NEW_CONFIGS << 'EOM'
CONFIG_NET_SCHED=y
CONFIG_NET_SCH_FQ_CODEL=y
CONFIG_NET_SCH_DEFAULT=y
CONFIG_DEFAULT_NET_SCH="fq_codel"
CONFIG_TCP_CONG_BBR=y
CONFIG_DEFAULT_TCP_CONG="bbr"
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
CONFIG_TUN=m
CONFIG_WIREGUARD=m
CONFIG_BRIDGE=m
CONFIG_BRIDGE_IGMP_SNOOPING=y
CONFIG_BRIDGE_NETFILTER=m
CONFIG_VLAN_8021Q=m
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
CONFIG_CONFIGFS_FS=y
CONFIG_CIFS=m
CONFIG_CIFS_ALLOW_INSECURE_LEGACY=y
CONFIG_RANDOM_TRUST_CPU=y
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

                # Extract the Key (e.g., CONFIG_NET_SCHED)
                key=$(echo "$line" | cut -d'=' -f1)
                
                # Escape special characters in the new line for sed (like slashes)
                escaped_line=$(printf '%s\n' "$line" | sed -e 's/[\/&]/\\&/g')

                # Check if the key exists in the file (active, module, or commented out "is not set")
                # Regex looks for: Start of line, optional #, optional space, KEY, then = or space
                if grep -q "^#\? \?${key}\b" "$config_file"; then
                    # Replace the existing line using sed
                    sed -i "s|^#\? \?${key}[= ].*|$escaped_line|" "$config_file"
                else
                    # Key not found, append to end of file
                    echo "$escaped_line" >> "$config_file"
                fi
            done
        else
            echo "Skipping:   $device_name (No linux.aarch64.conf found)"
        fi
    fi
done

echo "---------------------------------------------------------"
echo "Update complete. Backups saved as .conf.bak"
