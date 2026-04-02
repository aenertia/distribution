# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="rpcs3-src"
PKG_VERSION="6dc06b3ff5126469a15fb45a8cd86b3e8e922b3e"
PKG_LICENSE="GPLv2"
PKG_SITE="https://github.com/RPCS3/rpcs3"
PKG_URL="${PKG_SITE}.git"
PKG_GIT_CLONE_BRANCH="master"
PKG_DEPENDS_TARGET="toolchain llvm mesa qt6 libevdev zlib curl \
                     openal-soft vulkan-loader vulkan-headers wayland \
                     SDL3 ffmpeg mimalloc"
PKG_LONGDESC="PS3 Emulator - compiled from source with device-specific optimizations"
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DUSE_NATIVE_INSTRUCTIONS=OFF \
                         -DUSE_PRECOMPILED_HEADERS=OFF \
                         -DDISABLE_LTO=TRUE \
                         -DUSE_SYSTEM_CURL=ON \
                         -DUSE_SDL=ON \
                         -DUSE_SYSTEM_SDL=ON \
                         -DUSE_SYSTEM_FFMPEG=ON \
                         -DUSE_SYSTEM_OPENCV=OFF \
                         -DUSE_SYSTEM_ZLIB=ON \
                         -DUSE_SYSTEM_ZSTD=OFF \
                         -DUSE_SYSTEM_LIBUSB=OFF \
                         -DUSE_SYSTEM_LIBPNG=OFF \
                         -DUSE_SYSTEM_OPENAL=ON \
                         -DUSE_DISCORD_RPC=OFF \
                         -DUSE_VULKAN=ON \
                         -DUSE_GAMEMODE=OFF \
                         -DUSE_LIBEVDEV=ON \
                         -DOpenGL_GL_PREFERENCE=LEGACY \
                         -DCMAKE_DISABLE_FIND_PACKAGE_X11=TRUE \
                         -DBUILD_RPCS3_TESTS=OFF \
                         -DBUILD_LLVM=OFF \
                         -DSTATIC_LINK_LLVM=ON \
                         -DLLVM_DIR=${SYSROOT_PREFIX}/usr/lib/cmake/llvm \
                         -DLLVM_USE_PERF=OFF"
# LLVM JIT fallback: If system LLVM 22 causes JIT segfaults at runtime,
# switch to RPCS3's bundled LLVM 19.1.x by replacing the last 3 lines with:
#                        -DBUILD_LLVM=ON
#                        -DLLVM_TARGETS_TO_BUILD=AArch64
# This lets RPCS3 build its own pinned LLVM for the JIT backend, avoiding
# ABI mismatches between system LLVM and RPCS3's customized JIT internals.
# If BUILD_LLVM=ON, also remove the !/llvm/ filter from post_unpack() below.

if [ "${VULKAN_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${VULKAN}"
fi

pre_configure_target() {
  # Use host Clang 22 as a cross-compiler instead of GCC 14.2.
  # GCC 14.2 has an ICE (internal compiler error / segfault) processing
  # abseil's any_invocable.h templates used by protobuf.
  # Clang is a natural cross-compiler — just pass --target and --sysroot.
  # Use libstdc++ (not libc++) — Clang+libc++ 22 is broken for RPCS3 (#18306).
  #
  # Create a wrapper toolchain file that includes the original but overrides
  # the compiler. This is necessary because cmake processes the toolchain file
  # AFTER -C cache files, so cache preload can't override the compiler.
  mkdir -p ${PKG_BUILD}/.${TARGET_NAME}
  # Filter GCC-specific flags from TARGET_CFLAGS/CXXFLAGS for Clang compatibility.
  # -mabi=lp64 : Clang error "unknown target ABI 'lp64'" (default on aarch64 anyway)
  # -Wno-psabi : GCC-specific warning flag, not recognized by Clang
  CLANG_CFLAGS=$(echo "${TARGET_CFLAGS}" | sed 's/-mabi=lp64//g; s/-Wno-psabi//g')
  CLANG_CXXFLAGS=$(echo "${TARGET_CXXFLAGS}" | sed 's/-mabi=lp64//g; s/-Wno-psabi//g')

  CLANG_TOOLCHAIN="${PKG_BUILD}/.${TARGET_NAME}/clang-toolchain.cmake"
  cat > "${CLANG_TOOLCHAIN}" <<EOF
# Cross-compilation identification (from original ROCKNIX toolchain)
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_FIND_ROOT_PATH ${SYSROOT_PREFIX})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Use host Clang 20 as cross-compiler (Clang 22 has RPCS3 compat issues #18306)
set(CMAKE_C_COMPILER   "${TOOLCHAIN}/bin/clang-20")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN}/bin/clang-20")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN}/bin/clang-20")

# Use the GCC toolchain's linker, ar, ranlib, etc.
set(CMAKE_AR      "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-ar")
set(CMAKE_RANLIB  "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-ranlib")
set(CMAKE_STRIP   "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-strip")
set(CMAKE_OBJCOPY "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-objcopy")

# Clang cross-compilation flags (GCC-incompatible flags filtered out)
# --gcc-toolchain tells clang where the GCC installation lives so it can find
# libstdc++, libgcc_s, crtbegin, and all GCC runtime libraries automatically.
set(CMAKE_C_FLAGS_INIT   "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} ${CLANG_CFLAGS}")
set(CMAKE_CXX_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -stdlib=libstdc++ ${CLANG_CXXFLAGS}")

# LLD linker flags (BEFORE objects in cmake's link rule — only driver flags here, NO -l libs)
# --rtlib=libgcc -unwindlib=libgcc: explicit GCC runtime selection for cross-compilation
set(CMAKE_EXE_LINKER_FLAGS_INIT    "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -fuse-ld=lld -stdlib=libstdc++ --rtlib=libgcc -unwindlib=libgcc")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -fuse-ld=lld -stdlib=libstdc++ --rtlib=libgcc -unwindlib=libgcc")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -fuse-ld=lld -stdlib=libstdc++ --rtlib=libgcc -unwindlib=libgcc")

# System libraries (AFTER objects in cmake's link rule — correct position for lld's
# strict left-to-right symbol resolution). CMAKE_CXX_STANDARD_LIBRARIES maps to
# <LINK_LIBRARIES> in cmake's link template, which appears after all .a archives.
# -lstdc++ must be explicit because clang's implicit libstdc++ link fails in this
# cross-compilation setup (--exclude-libs,ALL + gcc-toolchain interaction).
set(CMAKE_CXX_STANDARD_LIBRARIES "-lstdc++ -latomic -lpthread -lm -lGLEW -lGL" CACHE STRING "" FORCE)
set(CMAKE_C_STANDARD_LIBRARIES "-latomic -lpthread -lm" CACHE STRING "" FORCE)
EOF
  # Clear environment CFLAGS/CXXFLAGS — they contain GCC-specific flags
  # (-mabi=lp64, -Wno-psabi) that cause Clang errors. Our toolchain file
  # already sets all the correct flags via CMAKE_C_FLAGS_INIT.
  export CFLAGS=""
  export CXXFLAGS=""
  export LDFLAGS=""

  # Prepend our toolchain file override to PKG_CMAKE_OPTS_TARGET.
  # scripts/build passes -DCMAKE_TOOLCHAIN_FILE in TARGET_CMAKE_OPTS first,
  # then PKG_CMAKE_OPTS_TARGET is appended. When cmake sees duplicate -D flags,
  # the last one wins. So putting ours at the start of PKG_CMAKE_OPTS_TARGET
  # means it appears after TARGET_CMAKE_OPTS and overrides the default toolchain.
  PKG_CMAKE_OPTS_TARGET="-DCMAKE_TOOLCHAIN_FILE=${CLANG_TOOLCHAIN} ${PKG_CMAKE_OPTS_TARGET}"
}

post_unpack() {
  # Initialize submodules selectively -- skip llvm (we use system LLVM),
  # skip curl, zlib, SDL (use system versions).
  # This matches what the RPCS3 CI does in .ci/build-linux-aarch64.sh
  cd ${PKG_BUILD}
  git submodule -q update --init \
    $(awk '/path/ && !/llvm/ && !/curl/ && !/zlib/ && !/SDL/ { print $3 }' .gitmodules)
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/.${TARGET_NAME}/bin/rpcs3 ${INSTALL}/usr/bin/rpcs3-src
  cp -rf ${PKG_DIR}/scripts/start_rpcs3_src.sh ${INSTALL}/usr/bin
  chmod 755 ${INSTALL}/usr/bin/*

  mkdir -p ${INSTALL}/usr/config/rpcs3
  # Install device-specific config (config.yml, GuiConfigs)
  if [ -d "${PKG_DIR}/config/${DEVICE}" ]; then
    cp -rfH ${PKG_DIR}/config/${DEVICE}/* ${INSTALL}/usr/config/rpcs3/
  fi
  # Install InputPlumber controller config
  if [ -d "${PKG_DIR}/config/InputPlumber" ]; then
    mkdir -p ${INSTALL}/usr/config/rpcs3/input_configs
    cp -rfH ${PKG_DIR}/config/InputPlumber/* ${INSTALL}/usr/config/rpcs3/input_configs/
  fi
}
