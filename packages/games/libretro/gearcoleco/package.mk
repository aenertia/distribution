################################################################################
#
#  Copyright (C) 2021      351ELEC team (https://github.com/351ELEC/351ELEC)
#
#  This Program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2, or (at your option)
#  any later version.
#
#  This Program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
################################################################################

PKG_NAME="gearcoleco"
PKG_VERSION="223b96c6f92fe2ece238df8a463334e2dfadaa7d"
PKG_SHA256="36684b0d60e9f9edd203931e4ce8c31f6e95da75e074619ead55a73cc063337e"
PKG_REV="1"
PKG_ARCH="any"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/drhelius/Gearcoleco"
PKG_URL="$PKG_SITE/archive/$PKG_VERSION.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_PRIORITY="optional"
PKG_SECTION="libretro"
PKG_SHORTDESC="Gearcoleco is a very accurate cross-platform ColecoVision emulator written in C++ that runs on Windows, macOS, Linux, BSD, Raspberry Pi and RetroArch."
PKG_LONGDESC="Gearcoleco is a very accurate cross-platform ColecoVision emulator written in C++ that runs on Windows, macOS, Linux, BSD, Raspberry Pi and RetroArch."

PKG_IS_ADDON="no"
PKG_TOOLCHAIN="make"
PKG_AUTORECONF="no"

make_target() {
  make -C platforms/libretro/
}

makeinstall_target() {
  mkdir -p $INSTALL/usr/lib/libretro
  cp platforms/libretro/gearcoleco_libretro.so $INSTALL/usr/lib/libretro/
}
