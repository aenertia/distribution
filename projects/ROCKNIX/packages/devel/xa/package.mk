# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="xa"
PKG_VERSION="2.4.1"
PKG_LICENSE="GPL"
PKG_SITE="http://tinycorelinux.net"
PKG_URL="${PKG_SITE}/15.x/x86/tcz/src/xa/xa-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_DEPENDS_HOST="ccache:host"
PKG_LONGDESC="xa is a high-speed, two-pass portable cross-assembler."
# Makefile has 'all: killxa xa' where killxa runs 'rm -f xa'.
# Parallel make races killxa against xa, deleting the binary after build.
PKG_MAKE_OPTS_HOST="-j1"

makeinstall_host() {
  mkdir -p ${TOOLCHAIN}/bin
  cp -f file65 ldo65 mkrom.sh printcbm reloc65 uncpk xa ${TOOLCHAIN}/bin
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp -f file65 ldo65 mkrom.sh printcbm reloc65 uncpk xa ${INSTALL}/usr/bin
}
