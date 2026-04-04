# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="distrobox"
PKG_VERSION="1.8.2.4"
PKG_LICENSE="GPL-3.0"
PKG_SITE="https://github.com/89luca89/distrobox"
PKG_URL="https://github.com/89luca89/distrobox/archive/refs/tags/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain lilipod"
PKG_LONGDESC="Container wrapper using lilipod for mutable Linux environments"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  for script in distrobox distrobox-create distrobox-enter distrobox-list \
                distrobox-rm distrobox-stop distrobox-export distrobox-init \
                distrobox-host-exec distrobox-ephemeral distrobox-upgrade \
                distrobox-assemble distrobox-generate-entry; do
    install -m 0755 ${PKG_BUILD}/${script} ${INSTALL}/usr/bin/
  done

  # Default config for immutable rootfs
  mkdir -p ${INSTALL}/usr/config/distrobox
  cp ${PKG_DIR}/config/distrobox/distrobox.conf ${INSTALL}/usr/config/distrobox/
}
