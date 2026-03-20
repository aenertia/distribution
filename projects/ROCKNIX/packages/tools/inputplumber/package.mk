# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="inputplumber"
# TEMPORARY: using binary-patched v0.75.2 from our fork with ICM42607 IIO support.
# Revert to upstream release once https://github.com/ShadowBlip/InputPlumber/pull/XXX
# (feat/icm42607-iio-support) is merged and a new release is cut.
PKG_VERSION="20570a4"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/aenertia/InputPlumber"
PKG_URL="https://raw.githubusercontent.com/aenertia/InputPlumber/${PKG_VERSION}/prebuilt/inputplumber-aarch64"
PKG_DEPENDS_TARGET="toolchain systemd libevdev libiio polkit"
PKG_LONGDESC="Open source input router and remapper daemon for Linux"
PKG_TOOLCHAIN="manual"

unpack() {
  mkdir -p ${PKG_BUILD}/usr/bin
  cp ${SOURCES}/${PKG_NAME}/${PKG_NAME}-${PKG_VERSION}.inputplumber-aarch64 ${PKG_BUILD}/usr/bin/inputplumber
  chmod +x ${PKG_BUILD}/usr/bin/inputplumber
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr
  rsync -ar ${PKG_BUILD}/usr/ ${INSTALL}/usr/
  rsync -ar ${PKG_DIR}/sources/usr/ ${INSTALL}/usr/
}

post_install() {
  enable_service inputplumber.service
}
