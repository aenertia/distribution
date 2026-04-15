# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2019-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2021-present 351ELEC (https://github.com/351ELEC)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="openbor4"
PKG_VERSION="a1ee56d0acffff2cc30080675e44c78895df2296" # last-known-tag: v7533
PKG_LICENSE="BSD-3-Clause"
PKG_SITE="https://github.com/DCurrent/openbor"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain SDL2 libogg libvorbisidec libvpx libpng"
PKG_LONGDESC="OpenBOR 4.0 - The ultimate 2D side scrolling engine (latest master with 2+ years of bugfixes)"
PKG_TOOLCHAIN="make"
GET_HANDLER_SUPPORT="git"

pre_configure_target() {
  PKG_MAKE_OPTS_TARGET="BUILD_LINUX_${ARCH}=1 -C ${PKG_BUILD}/engine SDKPATH=${SYSROOT_PREFIX} PREFIX=${TARGET_NAME}"
  cd ${PKG_BUILD}

  # Remove -Werror flags
  sed -i "s|-Werror||g" engine/Makefile

  # Add BUILD_LINUX_aarch64 target if it doesn't exist
  if ! grep -q "BUILD_LINUX_aarch64" engine/Makefile; then
    sed -i '/^ifdef BUILD_LINUX_LE_arm/i \
ifdef BUILD_LINUX_aarch64\
TARGET          = $(VERSION_NAME).elf\
TARGET_FINAL    = $(VERSION_NAME)\
TARGET_PLATFORM = LINUX\
BUILD_LINUX     = 1\
BUILD_SDL       = 1\
BUILD_GFX       = 1\
BUILD_PTHREAD   = 1\
BUILD_SDL_IO    = 1\
BUILD_VORBIS    = 1\
BUILD_WEBM      = 1\
BUILDING        = 1\
INCLUDES        = $(SDKPATH)/usr/include \\\
                  $(SDKPATH)/usr/include/SDL2\
OBJTYPE         = elf\
LIBRARIES       = $(SDKPATH)/usr/lib\
CFLAGS          += -Wno-error=format-overflow -Wno-error=stringop-truncation -Wno-error=implicit-function-declaration -Wno-error=unused-variable -Wno-error=unused-label -Wno-error=stringop-overflow\
endif\
' engine/Makefile
  fi

  # Fix STRIP command for cross-compilation
  sed -i 's|$(LNXDEV)/$(PREFIX)strip|$(PREFIX)-strip|g' engine/Makefile
}

pre_make_target() {
  cd ${PKG_BUILD}/engine
  chmod +x ./version.sh
  ./version.sh
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin

  if [ -f ${PKG_BUILD}/engine/OpenBOR ]; then
    cp ${PKG_BUILD}/engine/OpenBOR ${INSTALL}/usr/bin/OpenBOR4
  else
    BORFOUND=$(find ${PKG_BUILD} -name "OpenBOR" -type f -executable | head -1)
    if [ -n "${BORFOUND}" ]; then
      cp "${BORFOUND}" ${INSTALL}/usr/bin/OpenBOR4
    else
      echo "ERROR: OpenBOR binary not found after build"
      exit 1
    fi
  fi

  cp ${PKG_DIR}/sources/start_OpenBOR4.sh ${INSTALL}/usr/bin
  chmod 0755 ${INSTALL}/usr/bin/OpenBOR4
  chmod 0755 ${INSTALL}/usr/bin/start_OpenBOR4.sh

  mkdir -p ${INSTALL}/usr/config/openbor4
  if [ -f ${PKG_DIR}/config/master.cfg ]; then
    cp ${PKG_DIR}/config/master.cfg ${INSTALL}/usr/config/openbor4/master.cfg
  fi
}
