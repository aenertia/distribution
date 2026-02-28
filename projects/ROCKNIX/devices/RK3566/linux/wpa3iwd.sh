#!/bin/bash
# Applies Crypto API config changes to rk3566-linux.aarch64.conf
# This ensures WPA3 SAE (Simultaneous Authentication of Equals) works in iwd.
# We compile the buggy Rockchip Hardware Crypto engine as a module so it can be 
# blacklisted by default but loaded manually if needed.
# The PKCS8 parser is baked in (=y) as it is strictly required by iwd.

CONFIG_FILE="linux.aarch64.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found in the current directory."
    exit 1
fi

# 1. Set the Rockchip Hardware Crypto driver to a module (m) instead of built-in (y)
# 2. Enable PKCS8 parser as built-in (y) to guarantee iwd can read keys/certs
sed -i \
    -e 's/^CONFIG_CRYPTO_DEV_ROCKCHIP=y/CONFIG_CRYPTO_DEV_ROCKCHIP=m/' \
    -e 's/^# CONFIG_PKCS8_PRIVATE_KEY_PARSER is not set/CONFIG_PKCS8_PRIVATE_KEY_PARSER=y/' \
    "$CONFIG_FILE"

echo "Successfully updated WPA3/Crypto settings in $CONFIG_FILE"
