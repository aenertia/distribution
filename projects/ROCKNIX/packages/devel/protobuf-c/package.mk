# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2025 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="protobuf-c"
PKG_VERSION="1.5.0"
PKG_SHA256="d4cb022d55f49796959b07a9d83040822e39129bc0eb28f4e8301da17d758f62"
PKG_LICENSE="BSD"
PKG_SITE="https://github.com/protobuf-c/protobuf-c"
PKG_URL="${PKG_SITE}/archive/v${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Protocol Buffers implementation in C"
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DBUILD_PROTOC=OFF \
                        -DBUILD_TESTS=OFF \
                        -DBUILD_SHARED_LIBS=ON \
                        -DCMAKE_BUILD_TYPE=Release"

configure_package() {
  PKG_CMAKE_SCRIPT="${PKG_BUILD}/build-cmake/CMakeLists.txt"
}

pre_configure_target() {
  # Patch CMakeLists.txt to make Protobuf dependency conditional on BUILD_PROTOC
  # The runtime library (libprotobuf-c) is pure C and does not need protobuf C++
  sed -i 's/^FIND_PACKAGE(Protobuf REQUIRED)/if(BUILD_PROTOC)\nFIND_PACKAGE(Protobuf REQUIRED)\nendif()/' \
    ${PKG_BUILD}/build-cmake/CMakeLists.txt
  # Also make the absl find conditional
  sed -i 's/^find_package(absl CONFIG)/if(BUILD_PROTOC)\nfind_package(absl CONFIG)\nendif()/' \
    ${PKG_BUILD}/build-cmake/CMakeLists.txt
}

post_makeinstall_target() {
  # We only need the runtime library, not protoc-gen-c
  rm -rf ${INSTALL}/usr/bin
}
