# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="azahar-lr"
PKG_VERSION="afbaf8e485d004e855f14c7063cadb3233f4e308" # tag 2125.1 | last-known-tag: 2125.0-alpha6
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/azahar-emu/azahar"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain ffmpeg mesa boost zlib libusb zstd"
PKG_LONGDESC="Azahar - Nintendo 3DS emulator (libretro core)"
PKG_TOOLCHAIN="cmake"

if [ ! "${OPENGL}" = "no" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGL} glu libglvnd"
fi

if [ "${OPENGLES_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGLES}"
fi

if [ "${VULKAN_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${VULKAN}"
  PKG_AZAHAR_VULKAN="-DENABLE_VULKAN=ON"
else
  PKG_AZAHAR_VULKAN="-DENABLE_VULKAN=OFF"
fi

TARGET_CXXFLAGS+=-fpch-preprocess

PKG_CMAKE_OPTS_TARGET+="-DENABLE_LIBRETRO=ON \
                        -DENABLE_OPENGL=ON \
                        -DENABLE_QT=OFF \
                        -DENABLE_QT_TRANSLATION=OFF \
                        -DENABLE_ROOM=OFF \
                        -DENABLE_SDL2_FRONTEND=OFF \
                        -DENABLE_SDL2=OFF \
                        -DENABLE_TESTS=OFF \
                        ${PKG_AZAHAR_VULKAN} \
                        -DUSE_DISCORD_PRESENCE=OFF"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/lib/libretro
  cp ${PKG_BUILD}/.${TARGET_NAME}/bin/Release/azahar_libretro.so ${INSTALL}/usr/lib/libretro/azahar_libretro.so
}
