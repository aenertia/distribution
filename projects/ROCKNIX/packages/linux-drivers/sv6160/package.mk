# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2025 Joel Wirāmu Pauling <aenertia@aenertia.net>
PKG_NAME="sv6160"
PKG_VERSION="0d1364a"
PKG_LICENSE="GPL"
PKG_SITE="https://codeberg.org/aenertia/sv6160-rk915"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="linux"

# Required by ROCKNIX for out-of-tree kernel modules
PKG_TOOLCHAIN="manual"
PKG_IS_KERNEL_PKG="yes"

make_target() {
    # Execute make from the kernel directory, pointing back to our module source.
    # We must pass CONFIG_SV6160=m so the kbuild system knows to compile it.
    kernel_make -C $(kernel_path) M=${PKG_BUILD}/drivers/net/wireless/seekwave/sv6160 CONFIG_SV6160=m modules
}
makeinstall_target() {
    # 1. Install the compiled kernel module
    mkdir -p ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}
    cp ${PKG_BUILD}/drivers/net/wireless/seekwave/sv6160/sv6160.ko ${INSTALL}/$(get_full_module_dir)/${PKG_NAME}/

    # 2. Install the latency optimization config
    mkdir -p "${INSTALL}/usr/lib/modprobe.d"
    cp -av ${PKG_BUILD}/conf/sv6160.conf "${INSTALL}/usr/lib/modprobe.d/"

    # 3. Install the firmware blobs directly to /lib/firmware (ROCKNIX safe path)
    mkdir -p "${INSTALL}/$(get_kernel_overlay_dir)/lib/firmware"
    cp -av ${PKG_BUILD}/firmware/*.bin "${INSTALL}/$(get_kernel_overlay_dir)/lib/firmware/"
}
