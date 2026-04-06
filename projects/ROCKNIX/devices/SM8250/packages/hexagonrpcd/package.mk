# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="hexagonrpcd"
PKG_VERSION="0.4.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/ROCKNIX"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="hexagonrpcd — FastRPC filesystem server for Qualcomm SLPI sensor DSP"
PKG_TOOLCHAIN="manual"

make_target() {
  cp -a ${PKG_DIR}/sources/* ${PKG_BUILD}/
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/hexagonrpcd ${INSTALL}/usr/bin/
  chmod 0755 ${INSTALL}/usr/bin/hexagonrpcd

  mkdir -p ${INSTALL}/usr/lib/systemd/system
  cp ${PKG_BUILD}/hexagonrpcd.service ${INSTALL}/usr/lib/systemd/system/

  mkdir -p ${INSTALL}/usr/share/hexagonrpcd
  cp -a ${PKG_BUILD}/dsp ${INSTALL}/usr/share/hexagonrpcd/
}

post_install() {
  enable_service hexagonrpcd.service
}
