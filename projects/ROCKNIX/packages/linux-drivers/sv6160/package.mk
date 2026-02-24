# SPDX-License-Identifier: GPL-2.0
PKG_NAME="sv6160"
PKG_VERSION="main"
PKG_LICENSE="GPL"
PKG_SITE="https://codeberg.org/aenertia/sv6160-rk915"
PKG_URL="https://codeberg.org/aenertia/sv6160-rk915.git"
PKG_DEPENDS_TARGET="linux"

make_target() {
    # Build the driver out-of-tree using the compiled ROCKNIX kernel
    cd ${PKG_BUILD}/drivers/net/wireless/seekwave/sv6160
    $(MAKE) -C "${LINUX_OUT}" M="$(pwd)" ARCH="${TARGET_KERNEL_ARCH}" CROSS_COMPILE="${TARGET_KERNEL_PREFIX}" modules
}

makeinstall_target() {
    # 1. Install the compiled kernel module
    cd ${PKG_BUILD}/drivers/net/wireless/seekwave/sv6160
    $(MAKE) -C "${LINUX_OUT}" M="$(pwd)" ARCH="${TARGET_KERNEL_ARCH}" INSTALL_MOD_PATH="${INSTALL}/usr" modules_install
    
    # 2. Install the latency optimization config
    mkdir -p "${INSTALL}/usr/lib/modprobe.d"
    cp -av ${PKG_BUILD}/conf/sv6160.conf "${INSTALL}/usr/lib/modprobe.d/"
    
    # 3. Install the firmware blobs directly to the rootfs
    mkdir -p "${INSTALL}/usr/lib/firmware"
    cp -av ${PKG_BUILD}/firmware/*.bin "${INSTALL}/usr/lib/firmware/"
}
