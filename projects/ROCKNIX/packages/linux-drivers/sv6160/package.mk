# SPDX-License-Identifier: GPL-2.0
PKG_NAME="sv6160"
PKG_VERSION="main"
PKG_LICENSE="GPL"
PKG_SITE="https://codeberg.org/aenertia/sv6160-rk915"
PKG_URL="https://codeberg.org/aenertia/sv6160-rk915.git"
PKG_DEPENDS_TARGET="linux"

# Required by ROCKNIX for out-of-tree kernel modules
PKG_TOOLCHAIN="manual"
PKG_IS_KERNEL_PKG="yes"

make_target() {
    # Use the ROCKNIX kernel_make wrapper
    cd ${PKG_BUILD}/drivers/net/wireless/seekwave/sv6160
    kernel_make KDIR=$(kernel_path) M=$(pwd) modules
}

makeinstall_target() {
    # 1. Install the compiled kernel module using the ROCKNIX path helper
    cd ${PKG_BUILD}/drivers/net/wireless/seekwave/sv6160
    mkdir -p ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}
    cp sv6160.ko ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}/

    # 2. Install the latency optimization config
    mkdir -p "${INSTALL}/usr/lib/modprobe.d"
    cp -av ${PKG_BUILD}/conf/sv6160.conf "${INSTALL}/usr/lib/modprobe.d/"

    # 3. Install the firmware blobs directly to the rootfs
    mkdir -p "${INSTALL}/usr/lib/firmware"
    cp -av ${PKG_BUILD}/firmware/*.bin "${INSTALL}/usr/lib/firmware/"
}
