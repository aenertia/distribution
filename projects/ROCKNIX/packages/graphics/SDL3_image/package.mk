# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="SDL3_image"
PKG_VERSION="3.4.0"
PKG_LICENSE="Zlib"
PKG_SITE="https://github.com/libsdl-org/SDL_image"
PKG_URL="https://github.com/libsdl-org/SDL_image/releases/download/release-${PKG_VERSION}/SDL3_image-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain SDL3 libpng libjpeg-turbo"
PKG_LONGDESC="SDL3_image is an image file loading library for SDL3."
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DSDLIMAGE_AVIF=OFF \
                       -DSDLIMAGE_JXL=OFF \
                       -DSDLIMAGE_TIF=OFF \
                       -DSDLIMAGE_WEBP=OFF \
                       -DSDLIMAGE_BMP=ON \
                       -DSDLIMAGE_GIF=ON \
                       -DSDLIMAGE_JPG=ON \
                       -DSDLIMAGE_PNG=ON \
                       -DSDLIMAGE_VENDORED=OFF \
                       -DSDLIMAGE_BACKEND_STB=ON \
                       -DSDLIMAGE_SAMPLES=OFF \
                       -DSDLIMAGE_TESTS=OFF \
                       -DSDLIMAGE_INSTALL=ON \
                       -DBUILD_SHARED_LIBS=ON"

post_makeinstall_target() {
  # Fix pkg-config sysroot paths
  if [ -f "${SYSROOT_PREFIX}/usr/lib/pkgconfig/SDL3_image.pc" ]; then
    sed -e "s:\(['=LI]\)/usr:\\1${SYSROOT_PREFIX}/usr:g" -i ${SYSROOT_PREFIX}/usr/lib/pkgconfig/SDL3_image.pc 2>/dev/null || true
  fi
}
