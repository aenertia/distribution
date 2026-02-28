#!/bin/bash

TARGET_FILE="linux.aarch64.conf"

# The symbols we want to ensure are set
declare -A SYMBOLS=(
    ["CONFIG_BT_BNEP"]="m"
    ["CONFIG_BT_BNEP_MC_FILTER"]="y"
    ["CONFIG_BT_BNEP_PROTO_FILTER"]="y"
    ["CONFIG_BT_HIDP"]="m"
)

# Use find to locate files in subdirectories
find . -type f -name "$TARGET_FILE" | while read -r FILE; do
    echo "Processing: $FILE"
    
    for SYMBOL in "${!SYMBOLS[@]}"; do
        VALUE=${SYMBOLS[$SYMBOL]}
        
        # Check if it's currently commented out as "not set"
        if grep -q "# $SYMBOL is not set" "$FILE"; then
            # Replace the "not set" comment with the actual assignment
            sed -i "s|^# $SYMBOL is not set.*|$SYMBOL=$VALUE|" "$FILE"
            echo "  Converted 'not set' -> $SYMBOL=$VALUE"
            
        # Check if it exists but is set to something else (e.g., =n)
        elif grep -q "^$SYMBOL=" "$FILE"; then
            sed -i "s|^$SYMBOL=.*|$SYMBOL=$VALUE|" "$FILE"
            echo "  Updated existing entry -> $SYMBOL=$VALUE"
            
        # If it's not found at all, append it
        elif ! grep -q "$SYMBOL" "$FILE"; then
            echo "$SYMBOL=$VALUE" >> "$FILE"
            echo "  Appended new entry -> $SYMBOL=$VALUE"
        fi
    done
done

echo "Update sequence complete."
