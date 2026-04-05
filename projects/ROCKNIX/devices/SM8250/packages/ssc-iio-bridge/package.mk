# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="ssc-iio-bridge"
PKG_VERSION="0.1.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/ROCKNIX"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain protobuf-c"
PKG_LONGDESC="SSC IIO Bridge — bridges Qualcomm SLPI sensors to Linux IIO devices via QRTR"
PKG_TOOLCHAIN="manual"

make_target() {
  cp -a ${PKG_DIR}/sources/* ${PKG_BUILD}/
  cd ${PKG_BUILD}
  make CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/ssc-iio-bridge ${INSTALL}/usr/bin/
  chmod 0755 ${INSTALL}/usr/bin/ssc-iio-bridge

  mkdir -p ${INSTALL}/usr/lib/systemd/system
  cp ${PKG_BUILD}/ssc-iio-bridge.service ${INSTALL}/usr/lib/systemd/system/
}

post_install() {
  enable_service ssc-iio-bridge.service
}
