# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="wlsunset"
PKG_VERSION="0.4.0"
PKG_LICENSE="MIT"
PKG_SITE="https://git.sr.ht/~kennylevinsen/wlsunset"
PKG_URL="https://github.com/kennylevinsen/wlsunset/archive/refs/tags/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain wayland wayland-protocols seatd"
PKG_LONGDESC="Wayland color temperature and gamma adjustment tool"
PKG_TOOLCHAIN="meson"

PKG_MESON_OPTS_TARGET="-Dman-pages=disabled"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/.${TARGET_NAME}/wlsunset ${INSTALL}/usr/bin/
}
