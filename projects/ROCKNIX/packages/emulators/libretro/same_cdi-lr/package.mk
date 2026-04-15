# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2022-present AmberELEC (https://github.com/AmberELEC)

PKG_NAME="same_cdi-lr"
PKG_VERSION="2184aa6d87a31fb6c64534b9b7b2d26e36bae757" # last-known-tag: none
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/libretro/same_cdi"
PKG_URL="${PKG_SITE}.git"
PKG_DEPENDS_TARGET="toolchain expat zlib flac sqlite"
PKG_LONGDESC="SAME_CDI is a Single Arcade/Machine Emulator for libretro"
PKG_TOOLCHAIN="make"

PKG_MAKE_OPTS_TARGET="REGENIE=1 \
                      VERBOSE=1 \
                      NOWERROR=1 \
                      OPENMP=1 \
                      CROSS_BUILD=1 \
                      TOOLS=0 \
                      RETRO=1 \
                      PTR64= \
                      NOASM=0 \
                      PYTHON_EXECUTABLE=python3 \
                      CONFIG=libretro \
                      LIBRETRO_OS=unix \
                      LIBRETRO_CPU= \
                      PLATFORM=arm64 \
                      ARCH= \
                      TARGET=mame \
                      OSD=retro \
                      USE_SYSTEM_LIB_EXPAT=1 \
                      USE_SYSTEM_LIB_ZLIB=1 \
                      USE_SYSTEM_LIB_FLAC=1 \
                      USE_SYSTEM_LIB_SQLITE3=1"

pre_configure_target() {
  sed -i "s/-static-libstdc++//g" scripts/genie.lua
  # Remove -m64 from genie's gcc toolchain — x86-only flag that aarch64 GCC rejects.
  # Three sources: gcc.lua (platform defs), toolchain.lua (build configs), scripts.c (patched separately)
  sed -i '/"-m64"/d' 3rdparty/genie/src/tools/gcc.lua
  sed -i '/-m64/d' scripts/toolchain.lua
}

make_target() {
  # same_cdi is an x86-centric MAME fork — AsmJIT has no ARM backend,
  # genie hardcodes x86/x64 flags. Skip on aarch64 until upstream adds ARM support.
  if [ "${TARGET_ARCH}" = "aarch64" ]; then
    echo "same_cdi-lr: skipping build on aarch64 (no ARM AsmJIT backend)"
    return 0
  fi
  unset ARCH
  unset DISTRO
  unset PROJECT
  export ARCHOPTS="-D__aarch64__"
  make -f Makefile.libretro ${PKG_MAKE_OPTS_TARGET} OVERRIDE_CC=${CC} OVERRIDE_CXX=${CXX} OVERRIDE_LD=${LD} AR=${AR} ${MAKEFLAGS}
}

makeinstall_target() {
  if [ "${TARGET_ARCH}" = "aarch64" ]; then
    return 0
  fi
  mkdir -p ${INSTALL}/usr/lib/libretro
  cp same_cdi_libretro.so ${INSTALL}/usr/lib/libretro/
}
