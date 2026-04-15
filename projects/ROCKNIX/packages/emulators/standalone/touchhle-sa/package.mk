# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="touchhle-sa"
PKG_LICENSE="MPLv2"
PKG_VERSION="d7668926268eded91545fa8ffae6590871ecf5b1" # last-known-tag: v0.2.3
PKG_SITE="https://github.com/touchHLE/touchHLE"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain cargo:host cargo rust SDL2 sndio"
PKG_LONGDESC="touchHLE: high-level emulator for iPhone OS apps"
PKG_TOOLCHAIN="manual"

make_target() {
  unset CMAKE
  export RUSTFLAGS="-C link-arg=-lasound"
  # Override release profile opt-level from 3 to 2 — works around LLVM 22.1.2
  # ICE in the vectorizer (VPSingleDefRecipe cast assertion in ttf-parser 0.15.2)
  # RUSTFLAGS -C opt-level is ignored by Cargo profile, must use env override.
  export CARGO_PROFILE_RELEASE_OPT_LEVEL=2

  cargo build \
    --target ${TARGET_NAME} \
    --release
}


makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp -rf ${PKG_BUILD}/.${TARGET_NAME}/target/${TARGET_NAME}/release/touchHLE ${INSTALL}/usr/bin
  cp -rf ${PKG_DIR}/scripts/* ${INSTALL}/usr/bin
  mkdir -p ${INSTALL}/usr/lib/touchHLE/touchHLE_dylibs
  cp -rf ${PKG_BUILD}/touchHLE_dylibs/lib* ${INSTALL}/usr/lib/touchHLE/touchHLE_dylibs/
  mkdir -p ${INSTALL}/usr/lib/touchHLE/touchHLE_fonts
  cp -rf ${PKG_BUILD}/touchHLE_fonts/LiberationSans-* ${INSTALL}/usr/lib/touchHLE/touchHLE_fonts
  cp -rf ${PKG_BUILD}/touchHLE_default_options.txt ${INSTALL}/usr/lib/touchHLE/
  mkdir -p ${INSTALL}/usr/config/touchHLE
  cp -rf ${PKG_BUILD}/touchHLE_options.txt ${INSTALL}/usr/config/touchHLE/
  chmod +x ${INSTALL}/usr/bin/*
}
