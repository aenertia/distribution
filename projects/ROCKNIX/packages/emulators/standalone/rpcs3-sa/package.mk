# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="rpcs3-sa"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/RPCS3/rpcs3-binaries-linux"
PKG_DEPENDS_TARGET="toolchain libevdev SDL2 qt6 mesa libcom-err"
PKG_LONGDESC="PS3 Emulator appimage"
PKG_TOOLCHAIN="manual"
PKG_VERSION="6dc06b3ff5126469a15fb45a8cd86b3e8e922b3e"
PKG_REL_VERSION="0.0.40-19132-6dc06b3f"

case ${TARGET_ARCH} in
  x86_64)
    PKG_URL="${PKG_SITE}/releases/download/build-${PKG_VERSION}/rpcs3-v${PKG_REL_VERSION}_linux64.AppImage"
  ;;
  aarch64)
    PKG_URL="${PKG_SITE}-arm64/releases/download/build-${PKG_VERSION}/rpcs3-v${PKG_REL_VERSION}_linux_aarch64.AppImage"
  ;;
esac

makeinstall_target() {
  # Redefine strip or the AppImage will be stripped rendering it unusable.
  export STRIP=true
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/${PKG_NAME}-${PKG_VERSION}.AppImage ${INSTALL}/usr/bin/${PKG_NAME}
  cp -rf ${PKG_DIR}/scripts/start_rpcs3.sh ${INSTALL}/usr/bin
  chmod 755 ${INSTALL}/usr/bin/*
  mkdir -p ${INSTALL}/usr/config/rpcs3
  if [ -d "${PKG_DIR}/config/InputPlumber" ]; then
    cp -rfH ${PKG_DIR}/config/InputPlumber/* ${INSTALL}/usr/config/rpcs3/
  else
    cp -rfH ${PKG_DIR}/config/${DEVICE}/* ${INSTALL}/usr/config/rpcs3/
  fi
}
