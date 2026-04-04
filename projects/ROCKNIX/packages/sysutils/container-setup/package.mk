# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="container-setup"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/ROCKNIX"
PKG_URL=""
PKG_DEPENDS_TARGET=""
PKG_LONGDESC="First-boot container storage initialization for immutable rootfs"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  install -m 0755 ${PKG_DIR}/sources/container-storage-setup.sh ${INSTALL}/usr/bin/

  mkdir -p ${INSTALL}/usr/lib/systemd/system
  install -m 0644 ${PKG_DIR}/system.d/container-storage.service ${INSTALL}/usr/lib/systemd/system/

  # Enable by default
  mkdir -p ${INSTALL}/usr/lib/systemd/system/multi-user.target.wants
  ln -sf ../container-storage.service ${INSTALL}/usr/lib/systemd/system/multi-user.target.wants/
}
