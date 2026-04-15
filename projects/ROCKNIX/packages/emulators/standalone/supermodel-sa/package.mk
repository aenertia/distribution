# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="supermodel-sa"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/DirtBagXon/model3emu-code-sinden"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="${OPENGL} ${OPENGLES} glu toolchain SDL2 SDL2_net zlib"
PKG_LONGDESC="Supermodel is a Sega Model 3 arcade emulator"
PKG_TOOLCHAIN="make"
GET_HANDLER_SUPPORT="git"

case ${TARGET_ARCH} in
  aarch64|arm)
    PKG_VERSION="6ae0cf2f237586c4a3cc791514ec1b0f3cd4c56c"
    PKG_GIT_CLONE_BRANCH="arm"
  ;;
  *)
    PKG_VERSION="155e4cbb944d3c04268fe5910bc836cfc249b6a6"
    PKG_GIT_CLONE_BRANCH="main"
  ;;
esac

PKG_MAKE_OPTS="NET_BOARD=1"

pre_patch() {
  cp ${PKG_BUILD}/Makefiles/Makefile.UNIX ${PKG_BUILD}/Makefile
}

post_patch() {
  # Add proper include directory
  sed -e "s+MUSASHI_CFLAGS =+MUSASHI_CFLAGS = -I${SYSROOT_PREFIX}/usr/include+g" -i ${PKG_BUILD}/Makefiles/Rules.inc

  sed -i "s|sdl2-config|${SYSROOT_PREFIX}/usr/bin/sdl2-config|g" ${PKG_BUILD}/Makefile
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp -a ${PKG_BUILD}/bin/supermodel ${INSTALL}/usr/bin/supermodel
  cp -a ${PKG_DIR}/scripts/start_supermodel.sh ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/start_supermodel.sh
  mkdir -p ${INSTALL}/usr/config/supermodel
  mkdir -p ${INSTALL}/usr/config/supermodel/Config
  cp ${PKG_BUILD}/Config/Games.xml ${INSTALL}/usr/config/supermodel/Config
  cp -r ${PKG_DIR}/config/${DEVICE}/* ${INSTALL}/usr/config/supermodel/Config
}
