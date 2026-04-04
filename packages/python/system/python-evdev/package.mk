# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="python-evdev"
PKG_VERSION="1.9.3"
PKG_LICENSE="BSD-3-Clause"
PKG_SITE="https://github.com/gvalkov/python-evdev"
PKG_URL="https://github.com/gvalkov/python-evdev/archive/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain Python3 setuptools:host"
PKG_LONGDESC="Python bindings to the Linux input handling subsystem"
PKG_TOOLCHAIN="python"

pre_configure_target() {
  export CFLAGS="${CFLAGS} -I${SYSROOT_PREFIX}/usr/include"
}

post_makeinstall_target() {
  python_remove_source
}
