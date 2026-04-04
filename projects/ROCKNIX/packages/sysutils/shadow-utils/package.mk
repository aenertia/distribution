# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="shadow-utils"
PKG_VERSION="4.17.3"
PKG_LICENSE="BSD-3-Clause"
PKG_SITE="https://github.com/shadow-maint/shadow"
PKG_URL="https://github.com/shadow-maint/shadow/releases/download/${PKG_VERSION}/shadow-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Minimal shadow-utils for container user namespace support (getsubids, newuidmap, newgidmap)"
PKG_TOOLCHAIN="autotools"

PKG_CONFIGURE_OPTS_TARGET="--disable-man \
  --disable-shadowgrp \
  --disable-account-tools-setuid \
  --disable-utmpx \
  --enable-subordinate-ids \
  --without-pam --without-acl --without-attr --without-audit \
  --without-selinux --without-libbsd --without-btrfs \
  --without-nscd --without-skey --without-sssd \
  --without-su --without-tcb"

post_makeinstall_target() {
  # Only ship the 3 tools lilipod needs
  rm -rf ${INSTALL}
  mkdir -p ${INSTALL}/usr/bin
  # Install compiled binaries from .libs/ (not the libtool wrapper scripts in src/)
  cp ${PKG_BUILD}/.${TARGET_NAME}/src/.libs/getsubids ${INSTALL}/usr/bin/ 2>/dev/null || \
    cp ${PKG_BUILD}/.${TARGET_NAME}/src/getsubids ${INSTALL}/usr/bin/
  cp ${PKG_BUILD}/.${TARGET_NAME}/src/.libs/newuidmap ${INSTALL}/usr/bin/ 2>/dev/null || \
    cp ${PKG_BUILD}/.${TARGET_NAME}/src/newuidmap ${INSTALL}/usr/bin/
  cp ${PKG_BUILD}/.${TARGET_NAME}/src/.libs/newgidmap ${INSTALL}/usr/bin/ 2>/dev/null || \
    cp ${PKG_BUILD}/.${TARGET_NAME}/src/newgidmap ${INSTALL}/usr/bin/
  chmod 4755 ${INSTALL}/usr/bin/newuidmap
  chmod 4755 ${INSTALL}/usr/bin/newgidmap
  chmod 0755 ${INSTALL}/usr/bin/getsubids

  # Ship subuid/subgid for root user
  mkdir -p ${INSTALL}/etc
  echo "root:100000:65536" > ${INSTALL}/etc/subuid
  echo "root:100000:65536" > ${INSTALL}/etc/subgid
}
