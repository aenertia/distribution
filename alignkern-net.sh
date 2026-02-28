#!/bin/bash

# 1. Target Files
TARGET_FILES=(
    "projects/ROCKNIX/devices/H700/linux/linux.aarch64.conf"
    "projects/ROCKNIX/devices/RK3326/linux/linux.aarch64.conf"
    "projects/ROCKNIX/devices/RK3399/linux/linux.aarch64.conf"
    "projects/ROCKNIX/devices/RK3566/linux/linux.aarch64.conf"
    "projects/ROCKNIX/devices/RK3588/linux/linux.aarch64.conf"
    "projects/ROCKNIX/devices/S922X/linux/linux.aarch64.conf"
    "projects/ROCKNIX/devices/SDM845/linux/linux.aarch64.conf"
    "projects/ROCKNIX/devices/SM8250/linux/linux.aarch64.conf"
    "projects/ROCKNIX/devices/SM8550/linux/linux.aarch64.conf"
    "projects/ROCKNIX/devices/SM8650/linux/linux.aarch64.conf"
)

# 2. Universal Network Stack (Applied to ALL)
# Includes BBR, FQ_Codel, IPv6, Bridge/AP support, and Userspace Crypto API
UNIVERSAL_FRAGMENT=$(cat <<EOF

# --- NETWORK STACK ALIGNMENT (Systemd-resolved / IWD / Containers) ---
# TCP Performance Defaults
CONFIG_TCP_CONG_ADVANCED=y
CONFIG_TCP_CONG_BBR=y
CONFIG_DEFAULT_BBR=y
CONFIG_DEFAULT_TCP_CONG="bbr"
CONFIG_NET_SCH_FQ_CODEL=y
CONFIG_DEFAULT_FQ_CODEL=y
CONFIG_DEFAULT_NET_SCH="fq_codel"

# IPv6 Router & AP Features
CONFIG_IPV6_ROUTER_PREF=y
CONFIG_IPV6_MULTIPLE_TABLES=y
CONFIG_IPV6_SUBTREES=y
CONFIG_IPV6_MROUTE=y
CONFIG_IPV6_MROUTE_MULTIPLE_TABLES=y
CONFIG_IPV6_PIMSM_V2=y

# Container & Bridge Primitives
CONFIG_BRIDGE=y
CONFIG_BRIDGE_NETFILTER=y
CONFIG_VETH=y
CONFIG_TUN=y
CONFIG_TAP=y
CONFIG_MACVLAN=m
CONFIG_IPVLAN=m

# Generic Crypto APIs (Required for IWD/WPA3)
CONFIG_CRYPTO_USER_API_HASH=y
CONFIG_CRYPTO_USER_API_SKCIPHER=y
CONFIG_CRYPTO_USER_API_AEAD=y
CONFIG_KEY_DH_OPERATIONS=y
# --------------------------------------------------------------
EOF
)

# 3. Define Keys to Strip (To avoid duplicates/warnings)
KEYS_TO_REMOVE=(
    "CONFIG_TCP_CONG_ADVANCED" "CONFIG_TCP_CONG_BBR" "CONFIG_DEFAULT_BBR" "CONFIG_DEFAULT_CUBIC"
    "CONFIG_DEFAULT_TCP_CONG" "CONFIG_NET_SCH_FQ_CODEL" "CONFIG_DEFAULT_FQ_CODEL" "CONFIG_DEFAULT_NET_SCH"
    "CONFIG_IPV6_ROUTER_PREF" "CONFIG_IPV6_MULTIPLE_TABLES" "CONFIG_IPV6_SUBTREES" "CONFIG_IPV6_MROUTE"
    "CONFIG_IPV6_MROUTE_MULTIPLE_TABLES" "CONFIG_IPV6_PIMSM_V2"
    "CONFIG_BRIDGE" "CONFIG_BRIDGE_NETFILTER" "CONFIG_VETH" "CONFIG_TUN" "CONFIG_TAP" "CONFIG_MACVLAN" "CONFIG_IPVLAN"
    "CONFIG_CRYPTO_USER_API_HASH" "CONFIG_CRYPTO_USER_API_SKCIPHER" "CONFIG_CRYPTO_USER_API_AEAD" "CONFIG_KEY_DH_OPERATIONS"
    # Hardware Crypto Keys to strip before re-adding
    "CONFIG_CRYPTO_DEV_ROCKCHIP" "CONFIG_CRYPTO_DEV_QCE" "CONFIG_CRYPTO_DEV_QCOM_RNG"
    "CONFIG_CRYPTO_DEV_AMLOGIC_GXL" "CONFIG_CRYPTO_DEV_SUN8I_CE" "CONFIG_CRYPTO_DEV_SUN8I_SS"
)

echo "Starting Network & Crypto Alignment..."

for FILE in "${TARGET_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        # 4. Identify Device/SoC from file path
        DEVICE_TYPE=""
        SOC_CRYPTO_FRAGMENT=""
        
        if [[ "$FILE" == *"RK"* ]]; then
            DEVICE_TYPE="Rockchip"
            SOC_CRYPTO_FRAGMENT="CONFIG_CRYPTO_DEV_ROCKCHIP=y"
        elif [[ "$FILE" == *"SDM"* ]] || [[ "$FILE" == *"SM"* ]]; then
            DEVICE_TYPE="Qualcomm"
            SOC_CRYPTO_FRAGMENT=$(cat <<EOF
CONFIG_CRYPTO_DEV_QCE=y
CONFIG_CRYPTO_DEV_QCE_SKCIPHER=y
CONFIG_CRYPTO_DEV_QCE_SHA=y
CONFIG_CRYPTO_DEV_QCE_AEAD=y
CONFIG_CRYPTO_DEV_QCOM_RNG=y
EOF
)
        elif [[ "$FILE" == *"S922X"* ]]; then
            DEVICE_TYPE="Amlogic"
            SOC_CRYPTO_FRAGMENT="CONFIG_CRYPTO_DEV_AMLOGIC_GXL=y"
        elif [[ "$FILE" == *"H700"* ]]; then
            DEVICE_TYPE="Allwinner"
            SOC_CRYPTO_FRAGMENT=$(cat <<EOF
CONFIG_CRYPTO_DEV_SUN8I_CE=y
CONFIG_CRYPTO_DEV_SUN8I_SS=y
EOF
)
        fi

        echo "Processing: $FILE ($DEVICE_TYPE)"
        
        # A. Reset file to upstream/next
        git checkout upstream/next -- "$FILE"
        
        # B. Strip existing keys
        for KEY in "${KEYS_TO_REMOVE[@]}"; do
            sed -i "/^${KEY}[= ]/d" "$FILE"
            sed -i "/^# ${KEY} is not set/d" "$FILE"
        done

        # C. Append Configuration
        echo "$UNIVERSAL_FRAGMENT" >> "$FILE"
        
        if [ ! -z "$SOC_CRYPTO_FRAGMENT" ]; then
            echo "# --- SoC Specific Hardware Crypto ---" >> "$FILE"
            echo "$SOC_CRYPTO_FRAGMENT" >> "$FILE"
        fi

    else
        echo "Warning: File not found: $FILE"
    fi
done

echo "Alignment complete. Network stack + SoC specific crypto applied."
