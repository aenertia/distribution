# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="ssc-iio-bridge"
PKG_VERSION="0.1.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/ROCKNIX"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain linux"
PKG_LONGDESC="SSC IIO Bridge — bridges Qualcomm SLPI sensors to Linux IIO devices via QRTR"
PKG_TOOLCHAIN="manual"

make_target() {
  cp -a ${PKG_DIR}/sources/* ${PKG_BUILD}/

  # Build userspace daemon
  cd ${PKG_BUILD}
  make CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"

  # Build kernel module
  cd ${PKG_BUILD}/module
  kernel_make -C $(get_build_dir linux) M=${PKG_BUILD}/module modules
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/ssc-iio-bridge ${INSTALL}/usr/bin/
  chmod 0755 ${INSTALL}/usr/bin/ssc-iio-bridge

  mkdir -p ${INSTALL}/usr/lib/systemd/system
  cp ${PKG_BUILD}/ssc-iio-bridge.service ${INSTALL}/usr/lib/systemd/system/

  mkdir -p ${INSTALL}/$(get_full_module_dir)/extra
  cp ${PKG_BUILD}/module/bmi260-virt-iio.ko ${INSTALL}/$(get_full_module_dir)/extra/
}

post_install() {
  enable_service ssc-iio-bridge.service
}
