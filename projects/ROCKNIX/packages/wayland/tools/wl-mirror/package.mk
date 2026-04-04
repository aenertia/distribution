# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="wl-mirror"
PKG_VERSION="0.18.5"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/Ferdi265/wl-mirror"
PKG_URL="https://github.com/Ferdi265/wl-mirror/archive/refs/tags/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain wayland wayland-protocols wlroots libdrm mesa"
PKG_LONGDESC="Wayland output mirror client for sway/wlroots compositors"
PKG_TOOLCHAIN="cmake"

pre_configure_target() {
  # Create wlr-protocols layout expected by wl-mirror
  # It needs unstable/*.xml under WLR_PROTOCOL_DIR
  WLR_PROTO_STAGING="${PKG_BUILD}/proto/wlr-protocols"
  mkdir -p "${WLR_PROTO_STAGING}/unstable"
  WLROOTS_DIR=$(ls -d ${BUILD}/build/wlroots-*/protocol/ 2>/dev/null | head -1)
  if [ -n "${WLROOTS_DIR}" ]; then
    cp -f "${WLROOTS_DIR}"/wlr-screencopy-unstable-v1.xml "${WLR_PROTO_STAGING}/unstable/"
    cp -f "${WLROOTS_DIR}"/wlr-export-dmabuf-unstable-v1.xml "${WLR_PROTO_STAGING}/unstable/"
  fi

  PKG_CMAKE_OPTS_TARGET="-DINSTALL_EXAMPLE_SCRIPTS=OFF \
                          -DINSTALL_DOCUMENTATION=OFF \
                          -DWITH_LIBDECOR=OFF \
                          -DWITH_GBM=ON \
                          -DFORCE_SYSTEM_WL_PROTOCOLS=ON \
                          -DFORCE_SYSTEM_WLR_PROTOCOLS=ON \
                          -DWL_PROTOCOL_DIR=${SYSROOT_PREFIX}/usr/share/wayland-protocols \
                          -DWLR_PROTOCOL_DIR=${WLR_PROTO_STAGING}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/.${TARGET_NAME}/wl-mirror ${INSTALL}/usr/bin/
}
