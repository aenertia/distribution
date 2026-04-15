# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2022-present JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="arduous-lr"
PKG_VERSION="fba6f3e418218cf35a17cda8aac62133ff327f2c" # last-known-tag: latest
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/libretro/arduous"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="A Libretro emulator core for the Arduboy"

PKG_CMAKE_OPTS_TARGET="-DCMAKE_POLICY_VERSION_MINIMUM=3.5"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  cp arduous_libretro.so ${INSTALL}/usr/lib/libretro/
}
