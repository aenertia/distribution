# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2019-present Team CoreELEC (https://coreelec.org)

PKG_NAME="neocd_lr"
PKG_VERSION="9216ca226f24e01e77fc2670035e97da154f3de4" # last-known-tag: v0.5
PKG_LICENSE="LGPLv3.0"
PKG_SITE="https://github.com/libretro/neocd_libretro"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain flac libogg libvorbis"
PKG_LONGDESC="Neo Geo CD emulator for libretro "
PKG_TOOLCHAIN="make"
GET_HANDLER_SUPPORT="git"

make_target() {
cd ${PKG_BUILD}
CFLAGS=${CFLAGS} CXXFLAGS="${CXXFLAGS}" CXX="${CXX}" CC="${CC}" LD="$LD" RANLIB="$RANLIB" AR="${AR}" make
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  cp ${PKG_BUILD}/neocd_libretro.so ${INSTALL}/usr/lib/libretro/
}
