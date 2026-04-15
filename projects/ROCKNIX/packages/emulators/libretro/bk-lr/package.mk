# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="bk-lr"
PKG_VERSION="50a6a6e9b542da25f2d1bdf37f6f53b97929e141" # last-known-tag: none
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/libretro/bk-emulator"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Linux/SDL emulator for Soviet (russian) Electronica BK serie"
PKG_TOOLCHAIN="make"

pre_make_target() {
  mv ${PKG_BUILD}/Makefile.libretro ${PKG_BUILD}/Makefile
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  cp -r ${PKG_BUILD}/bk_libretro.so ${INSTALL}/usr/lib/libretro/
}
