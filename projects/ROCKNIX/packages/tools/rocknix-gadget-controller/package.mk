# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="rocknix-gadget-controller"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/ROCKNIX/distribution"
PKG_DEPENDS_TARGET="toolchain python-evdev"
PKG_LONGDESC="USB HID gadget controller - present device as gamepad to external hosts"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  mkdir -p ${INSTALL}/usr/lib/systemd/system
  mkdir -p ${INSTALL}/usr/share/rocknix-gadget-controller

  cp ${PKG_DIR}/sources/gadget-controller ${INSTALL}/usr/bin/
  chmod 0755 ${INSTALL}/usr/bin/gadget-controller

  cp ${PKG_DIR}/sources/gadget-hid-bridge ${INSTALL}/usr/bin/
  chmod 0755 ${INSTALL}/usr/bin/gadget-hid-bridge

  cp ${PKG_DIR}/sources/rocknix-gadget-controller.service ${INSTALL}/usr/lib/systemd/system/
}
