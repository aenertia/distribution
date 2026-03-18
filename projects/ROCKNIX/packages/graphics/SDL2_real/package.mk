# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

# Real SDL2 library (not sdl2-compat) for PortMaster binary compatibility.
# PortMaster ships pre-compiled aarch64 ports linked against real SDL2.
# The system SDL2 is now sdl2-compat (SDL3 wrapper) which segfaults
# with some port binaries. This builds the genuine SDL2 2.30.12 and
# installs it to /usr/lib/compat/ where PortMaster's control.txt
# sets LD_LIBRARY_PATH.

PKG_NAME="SDL2_real"
PKG_VERSION="2.30.12"
PKG_LICENSE="Zlib"
PKG_SITE="https://www.libsdl.org/"
PKG_URL="https://www.libsdl.org/release/SDL2-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain alsa-lib systemd dbus libdrm pipewire pulseaudio"
PKG_LONGDESC="Real SDL2 library for PortMaster binary compatibility"
PKG_TOOLCHAIN="cmake"

pre_configure_target() {
  export LDFLAGS="${LDFLAGS} -ludev"

  PKG_CMAKE_OPTS_TARGET="-DSDL_STATIC=OFF \
                          -DSDL_SHARED=ON \
                          -DSDL_TESTS=OFF \
                          -DSDL_X11=OFF \
                          -DSDL_DIRECTFB=OFF \
                          -DSDL_PIPEWIRE=ON \
                          -DSDL_PULSEAUDIO=ON \
                          -DSDL_ALSA=ON \
                          -DSDL_KMSDRM=ON \
                          -DSDL_WAYLAND=ON \
                          -DSDL_OPENGLES=ON \
                          -DSDL_OPENGL=OFF \
                          -DSDL_VULKAN=OFF \
                          -DSDL_HIDAPI=ON \
                          -DSDL_HIDAPI_JOYSTICK=ON \
                          -DSDL_INSTALL=OFF"
}

makeinstall_target() {
  # Install ONLY the shared library to compat dir — don't pollute system
  mkdir -p ${INSTALL}/usr/lib/compat
  cp -P ${PKG_BUILD}/.${TARGET_NAME}/libSDL2-2.0.so* ${INSTALL}/usr/lib/compat/
  # Ensure the soname symlink exists
  cd ${INSTALL}/usr/lib/compat
  ln -sf libSDL2-2.0.so.0.*.* libSDL2-2.0.so.0 2>/dev/null || true
}
