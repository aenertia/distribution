# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ROCKNIX (https://github.com/ROCKNIX)

# Inherit nearly everything — disable desktop OpenGL but keep Vulkan
OPENGL_SUPPORT=no
_SAVE_VULKAN_SUPPORT=${VULKAN_SUPPORT}
. $(get_pkg_directory SDL2)/package.mk
VULKAN_SUPPORT=${_SAVE_VULKAN_SUPPORT}

# Ensure Vulkan wayland surface support is compiled in
if [ "${VULKAN_SUPPORT}" = "yes" ]; then
  PKG_CMAKE_OPTS_TARGET+=" -DSDL_VULKAN=ON -DVIDEO_VULKAN=ON"
fi

PKG_NAME="SDL2_glesonly"
PKG_DEPENDS_UNPACK+=" SDL2"

makeinstall_target() {
  mkdir -p "${INSTALL}/usr/lib/glesonly"
  cp -a libSDL2-2.0.so.0.* "${INSTALL}/usr/lib/glesonly/"
}

post_makeinstall_target() {
  :
}
