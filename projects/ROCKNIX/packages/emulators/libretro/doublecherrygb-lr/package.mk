# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="doublecherrygb-lr"
PKG_VERSION="2e7a8bd5442ad7b2cb98ea07dbb5000ac95193e9" # tag 0.18.1 | last-known-tag: 0.18.1 # reverted: HEAD adds libmobile git submodule not fetched by tarball, breaks make build
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/TimOelrichs/doublecherryGB-libretro"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="DoubleCherryGB is an open source (GPLv2) GB/GBC emulator."
PKG_TOOLCHAIN="make"

make_target() {
  cd ${PKG_BUILD}
  make
}

if [ "${OPENGL_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGL} glu libglvnd"
fi

if [ "${OPENGLES_SUPPORT}" = yes ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGLES}"
fi

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  cp ${PKG_BUILD}/DoubleCherryGB_libretro.so ${INSTALL}/usr/lib/libretro/
}
