# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="inputplumber"
PKG_VERSION="v0.76.0"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/ShadowBlip/InputPlumber"
PKG_URL="https://github.com/ShadowBlip/InputPlumber/releases/download/${PKG_VERSION}/inputplumber-aarch64.tar.gz"
PKG_DEPENDS_TARGET="toolchain systemd libevdev libiio polkit"
PKG_LONGDESC="Open source input router and remapper daemon for Linux"
PKG_TOOLCHAIN="manual"

unpack() {
  mkdir -p ${PKG_BUILD}
  tar -xzf ${SOURCES}/${PKG_NAME}/${PKG_NAME}-${PKG_VERSION}.tar.gz -C ${PKG_BUILD} --strip-components=1
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr
  # Install upstream binary and default configs
  rsync -ar ${PKG_BUILD}/usr/ ${INSTALL}/usr/
  # Overlay ROCKNIX-specific device configs, capability maps, and profiles
  rsync -ar ${PKG_DIR}/sources/usr/ ${INSTALL}/usr/
}

post_install() {
  enable_service inputplumber.service
}
