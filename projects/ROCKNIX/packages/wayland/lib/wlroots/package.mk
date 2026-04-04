# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2021-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="wlroots"
PKG_VERSION="0.20.0"
PKG_LICENSE="MIT"
PKG_SITE="https://gitlab.freedesktop.org/wlroots/wlroots/"
PKG_URL="${PKG_SITE}/-/archive/${PKG_VERSION}/wlroots-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain libinput libxkbcommon pixman libdrm libdisplay-info wayland wayland-protocols seatd xwayland hwdata libxcb xcb-util-wm glslang"
PKG_LONGDESC="A modular Wayland compositor library"
PKG_TOOLCHAIN="meson"
PKG_PATCH_DIRS+=" ${DEVICE}"

# RGA scanout scaling disabled — patch incompatible with wlroots 0.20.0 scene graph
# Causes blank screen on RK3566 after ES loads
# case ${DEVICE} in
#   RK3566|RK3326)
#     PKG_DEPENDS_TARGET+=" librga"
#     PKG_PATCH_DIRS+=" rockchip-rga"
#     ;;
# esac

# libmali zero-stride workaround for ARM Mali blob users
case ${DEVICE} in
  RK3326|RK3566|S922X|RK3588)
    PKG_PATCH_DIRS+=" libmali"
    ;;
esac

configure_package() {
  # OpenGLES Support
  if [ "${OPENGLES_SUPPORT}" = "yes" ]; then
    PKG_DEPENDS_TARGET+=" ${OPENGLES}"
  fi

  # Vulkan renderer — build both GLES2 and Vulkan on devices with Vulkan support
  if [ "${VULKAN_SUPPORT}" = "yes" ]; then
    PKG_DEPENDS_TARGET+=" vulkan-loader vulkan-headers"
    PKG_MESON_OPTS_TARGET+=" -Drenderers=gles2,vulkan"
  else
    PKG_MESON_OPTS_TARGET+=" -Drenderers=gles2"
  fi
}

PKG_MESON_OPTS_TARGET="-Dxcb-errors=disabled \
                       -Dxwayland=enabled \
                       -Dexamples=false \
                       -Dcolor-management=enabled \
                       -Dbackends=drm,libinput"

pre_configure_target() {
  # wlroots does not build without -Wno flags as all warnings being treated as errors
  export TARGET_CFLAGS=$(echo "${TARGET_CFLAGS} -Wno-unused-variable -Wno-unused-but-set-variable -Wno-unused-function -Wno-return-type")
}
