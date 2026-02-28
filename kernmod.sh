#!/bin/bash
DEVICES="H700 RK3326 RK3399 RK3566 RK3588 S922X SDM845 SM8250 SM8550 SM8650"

for DEVICE in $DEVICES; do
    echo "=========================================="
    echo "Processing $DEVICE..."

    # 1. Run the adjustment tool
    # Explicitly passing ARCH ensures no ambiguity
    PROJECT=ROCKNIX DEVICE=$DEVICE ARCH=aarch64 ./tools/adjust_kernel_config olddefconfig
    git diff project/ROCKNIX/$DEVICE/linux/linux.aarch64.conf

done
