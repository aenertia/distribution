# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="wl-gammarelay-rs"
PKG_VERSION="v1.0.1"
PKG_LICENSE="GPL-3.0"
PKG_SITE="https://github.com/MaxVerevkin/wl-gammarelay-rs"
PKG_URL="${PKG_SITE}/archive/refs/tags/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain wayland dbus"
PKG_LONGDESC="DBus interface to control gamma, temperature, and brightness via wlr-gamma-control-unstable-v1 protocol"
PKG_TOOLCHAIN="rust"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/.${TARGET_NAME}/release/wl-gammarelay-rs ${INSTALL}/usr/bin/
}
