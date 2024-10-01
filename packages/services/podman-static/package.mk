# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="podman-static"
PKG_VERSION="5.2.3"
PKG_ARCH="aarch64"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/mgoltzsche/podman-static"
PKG_URL="${PKG_SITE}/releases/download/v${PKG_VERSION}/podman-linux-arm64.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Arm64 Satically Linked Podman runc and Dependancies"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
 # Systemd and related units and configs
 mkdir -p ${INSTALL}/etc/containers
  cp -P etc/containers/* ${INSTALL}/etc/containers
 mkdir -p ${INSTALL}/usr/lib/systemd/system
  cp -P usr/lib/systemd/system/* ${INSTALL}/usr/lib/systemd/system
 mkdir -p ${INSTALL}/usr/lib/systemd/user 
  cp -P usr/lib/systemd/user/* ${INSTALL}/usr/lib/systemd/user
 
 # Binaries
 mkdir -p ${INSTALL}/usr/local/bin
  cp -P usr/local/bin/* ${INSTALL}/usr/local/bin
 mkdir -p ${INSTALL}/usr/local/lib/podman
  cp -P usr/local/lib/podman/* ${INSTALL}/usr/local/lib/podman
}
