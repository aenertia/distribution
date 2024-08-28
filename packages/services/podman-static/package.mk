# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="podman-static"
PKG_VERSION="5.2.3"
PKG_ARCH="aarch64"
PKG_LICENSE="GPLv3"
PKG_SITE="https://github.com/mgoltzsche/podman-static"
PKG_URL="${PKG_SITE}/releases/download/v${PKG_VERSION}/podman-linux-arm64.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Arm64 Satically Linked Podman runc and Dependancies"
PKG_TOOLCHAIN="manual"
