# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2017-present Team LibreELEC (https://libreelec.tv)
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="x265"
PKG_VERSION="4.1"
PKG_SHA256="53c9363dba429eab3123ffcfda28065c5e7a8b5e21efa0a5f23bc5b89340d390"
PKG_LICENSE="GPL"
PKG_SITE="https://www.videolan.org/developers/x265.html"
PKG_URL="https://bitbucket.org/multicoreware/x265_git/get/${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="x265 - H.265/HEVC video encoder library"
PKG_TOOLCHAIN="make"

# Remove x86_64-only restriction from upstream — enable for aarch64 too
# PKG_ARCH="x86_64"  # Removed for ROCKNIX

pre_configure_target() {
  LDFLAGS+=" -ldl"

  if [ "${TARGET_ARCH}" = "aarch64" ]; then
    ${CMAKE} -G "Unix Makefiles" \
      -DENABLE_ASSEMBLY=ON \
      -DCROSS_COMPILE_ARM64=ON \
      -DCMAKE_ASM_FLAGS="${CFLAGS}" \
      ./source
  elif [ "${TARGET_ARCH}" = "arm" ]; then
    # ARM32: must enable PIC for shared library builds; disable assembly
    # (x265 arm asm targets armv6 soft-float, incompatible with our armv8-a hard-float)
    ${CMAKE} -G "Unix Makefiles" \
      -DENABLE_PIC=ON \
      -DCROSS_COMPILE_ARM=ON \
      -DENABLE_ASSEMBLY=OFF \
      ./source
  else
    ${CMAKE} -G "Unix Makefiles" ./source
  fi
}
