# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2018-present Frank Hartung (supervisedthinking (@) gmail.com)
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="amiberry"
PKG_ARCH="aarch64"
PKG_VERSION="37896181fb36ec3ce39322827dabdbf311eea716" # v8.1.2
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/BlitterStudio/amiberry"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain linux glibc bzip2 zlib SDL3 SDL3_image capsimg freetype libxml2 flac libogg mpg123 libpng libmpeg2 libserialport curl nlohmann-json"
PKG_LONGDESC="Amiberry is an optimized Amiga emulator (v8.x with SDL3 + ImGui)."
GET_HANDLER_SUPPORT="git"
PKG_TOOLCHAIN="cmake"

if [ "${OPENGLES_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGLES}"
  PKG_CMAKE_OPTS_TARGET+=" -DUSE_GLES2=ON -DUSE_OPENGL=OFF"
elif [ "${OPENGL_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGL} glu libglvnd"
  PKG_CMAKE_OPTS_TARGET+=" -DUSE_OPENGL=ON -DUSE_GLES2=OFF"
fi

if [ "${VULKAN_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${VULKAN}"
  PKG_CMAKE_OPTS_TARGET+=" -DUSE_VULKAN=ON"
else
  PKG_CMAKE_OPTS_TARGET+=" -DUSE_VULKAN=OFF"
fi

PKG_CMAKE_OPTS_TARGET+=" -DCMAKE_BUILD_TYPE=Release \
                         -DUSE_DBUS=OFF \
                         -DUSE_GPIOD=OFF \
                         -DUSE_PORTMIDI=OFF \
                         -DUSE_UAENET_PCAP=OFF \
                         -DBUNDLE_SDL=OFF"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  mkdir -p ${INSTALL}/usr/lib
  mkdir -p ${INSTALL}/usr/config/amiberry

  # Copy binary
  if [ -f ${PKG_BUILD}/.${TARGET_NAME}/amiberry ]; then
    cp ${PKG_BUILD}/.${TARGET_NAME}/amiberry ${INSTALL}/usr/bin/amiberry
  elif [ -f ${PKG_BUILD}/.${TARGET_NAME}/bin/amiberry ]; then
    cp ${PKG_BUILD}/.${TARGET_NAME}/bin/amiberry ${INSTALL}/usr/bin/amiberry
  else
    AMIFOUND=$(find ${PKG_BUILD}/.${TARGET_NAME} -name "amiberry" -type f -executable | head -1)
    if [ -n "${AMIFOUND}" ]; then
      cp "${AMIFOUND}" ${INSTALL}/usr/bin/amiberry
    else
      echo "ERROR: amiberry binary not found"
      exit 1
    fi
  fi

  # Copy config and resources
  cp -ra ${PKG_DIR}/config/*           ${INSTALL}/usr/config/amiberry/
  if [ -d ${PKG_BUILD}/data ]; then
    cp -a ${PKG_BUILD}/data            ${INSTALL}/usr/config/amiberry/
  fi
  if [ -d ${PKG_BUILD}/savestates ]; then
    cp -a ${PKG_BUILD}/savestates      ${INSTALL}/usr/config/amiberry/
  fi
  if [ -d ${PKG_BUILD}/screenshots ]; then
    cp -a ${PKG_BUILD}/screenshots     ${INSTALL}/usr/config/amiberry/
  fi
  if [ -d ${PKG_BUILD}/whdboot ]; then
    cp -a ${PKG_BUILD}/whdboot         ${INSTALL}/usr/config/amiberry/
  fi
  ln -s /storage/roms/bios            ${INSTALL}/usr/config/amiberry/kickstarts

  # Create links to Retroarch controller files
  ln -s "/usr/share/libretro/autoconfig" "${INSTALL}/usr/config/amiberry/controller"

  # Copy scripts & link libcapsimg
  cp -a ${PKG_DIR}/scripts/*          ${INSTALL}/usr/bin
  ln -sf /usr/lib/libcapsimage.so.5.1 ${INSTALL}/usr/config/amiberry/capsimg.so
}
