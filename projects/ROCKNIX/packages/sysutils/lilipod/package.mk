# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="lilipod"
PKG_VERSION="0.0.3"
PKG_LICENSE="GPL-3.0"
PKG_SITE="https://github.com/89luca89/lilipod"
PKG_URL="https://github.com/89luca89/lilipod/archive/refs/tags/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain go:host"
PKG_LONGDESC="Lightweight OCI container manager using Linux namespaces"
PKG_TOOLCHAIN="manual"

configure_target() {
  go_configure
  export CGO_ENABLED=0
}

make_target() {
  HOME=${ROOT} GOCACHE=${ROOT}/.cache/go-build \
    ${GOLANG} build -mod vendor -ldflags "-s -w" -o bin/lilipod -v .
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp bin/lilipod ${INSTALL}/usr/bin/
  chmod 0755 ${INSTALL}/usr/bin/lilipod
}
