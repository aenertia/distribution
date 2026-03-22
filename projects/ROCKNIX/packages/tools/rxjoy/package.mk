# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="rxjoy"
PKG_VERSION="3b342dd"
PKG_GIT_CLONE_BRANCH="main"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://codeberg.org/aenertia/rxjoy"
PKG_URL="https://codeberg.org/aenertia/rxjoy.git"
PKG_DEPENDS_TARGET="toolchain pipewire"
PKG_LONGDESC="Multi-system USB+BT gamepad emulator daemon (26 profiles: Xbox, PS3/4/5, Switch, GameCube, Wiimote, instruments)"
PKG_TOOLCHAIN="manual"

make_target() {
  cd ${PKG_BUILD}
  make CC="${CC}" \
       CFLAGS="${TARGET_CFLAGS} -O3 -Wall -Wextra -std=c11 -D_DEFAULT_SOURCE -march=armv8-a+crc" \
       LDFLAGS="${TARGET_LDFLAGS} -lpthread" \
       ENABLE_MBEDTLS=1 \
       ENABLE_BTSTACK=1 \
       ENABLE_PIPEWIRE=1 \
       both
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  mkdir -p ${INSTALL}/usr/lib/systemd/system
  mkdir -p ${INSTALL}/usr/share/rxjoy

  # Main gamepad emulator + audio daemon
  install -m 0755 ${PKG_BUILD}/rxjoy ${INSTALL}/usr/bin/
  install -m 0755 ${PKG_BUILD}/rxjoy-audio ${INSTALL}/usr/bin/

  # Audio bridge helper script
  if [ -f ${PKG_BUILD}/scripts/rxjoy-audio-bridge ]; then
    install -m 0755 ${PKG_BUILD}/scripts/rxjoy-audio-bridge ${INSTALL}/usr/bin/
  fi

  # Systemd template unit
  cp ${PKG_DIR}/sources/rxjoy@.service ${INSTALL}/usr/lib/systemd/system/
}
