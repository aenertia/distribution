# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="eden-sa"
PKG_VERSION="d1b7824443093345992026fdaeba50f76bd5d8c0"
PKG_LICENSE="GPL-3.0-or-later"
PKG_SITE="https://git.eden-emu.dev/eden-emu/eden"
# Local clone for dev iteration. Switch to remote URL for production:
# PKG_URL="${PKG_SITE}.git"
PKG_URL="file:///var/home/aenertia/build/eden"
PKG_DEPENDS_TARGET="toolchain llvm mesa SDL2 boost libevdev libdrm ffmpeg \
                     zlib libusb zstd openal-soft pulseaudio alsa-lib \
                     qt6 libfmt openssl vulkan-loader vulkan-headers \
                     wayland mimalloc lz4 opus nlohmann-json"
PKG_LONGDESC="Eden - Nintendo Switch emulator with NCE support, compiled from source"
PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DCMAKE_BUILD_TYPE=Release \
                         -DENABLE_QT=ON \
                         -DENABLE_QT6=ON \
                         -DYUZU_CMD=ON \
                         -DENABLE_NCE=ON \
                         -DENABLE_CUBEB=ON \
                         -DENABLE_LIBUSB=ON \
                         -DENABLE_OPENGL=ON \
                         -DENABLE_WEB_SERVICE=OFF \
                         -DENABLE_UPDATE_CHECKER=OFF \
                         -DUSE_DISCORD_PRESENCE=OFF \
                         -DYUZU_TESTS=OFF \
                         -DYUZU_ROOM=OFF \
                         -DYUZU_ROOM_STANDALONE=OFF \
                         -DYUZU_CRASH_DUMPS=OFF \
                         -DYUZU_USE_QT_WEB_ENGINE=OFF \
                         -DYUZU_USE_QT_MULTIMEDIA=ON \
                         -DYUZU_USE_BUNDLED_FFMPEG=OFF \
                         -DYUZU_USE_BUNDLED_SDL2=OFF \
                         -DYUZU_USE_EXTERNAL_SDL2=OFF \
                         -DYUZU_USE_BUNDLED_OPENSSL=OFF \
                         -DYUZU_DOWNLOAD_TIME_ZONE_DATA=ON \
                         -DCPMUTIL_FORCE_SYSTEM=OFF \
                         -Dfmt_FORCE_SYSTEM=ON \
                         -Dlz4_FORCE_SYSTEM=ON \
                         -Dzstd_FORCE_SYSTEM=ON \
                         -DZLIB_FORCE_SYSTEM=ON \
                         -DOpus_FORCE_SYSTEM=ON \
                         -Dnlohmann_json_FORCE_SYSTEM=ON \
                         -Dlibusb_FORCE_SYSTEM=ON \
                         -DBoost_FORCE_SYSTEM=ON \
                         -DVulkanHeaders_FORCE_BUNDLED=ON \
                         -DCMAKE_DISABLE_FIND_PACKAGE_X11=TRUE"

if [ "${VULKAN_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${VULKAN}"
fi

if [ "${OPENGL_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${OPENGL}"
fi

pre_configure_target() {
  # Use host Clang 20 as a cross-compiler instead of GCC 14.2.
  # Reuse the proven rpcs3-src pattern: custom cmake toolchain file
  # with GCC-specific flags filtered out.

  # Filter GCC-specific flags from TARGET_CFLAGS/CXXFLAGS
  CLANG_CFLAGS=$(echo "${TARGET_CFLAGS}" | sed 's/-mabi=lp64//g; s/-Wno-psabi//g')
  CLANG_CXXFLAGS=$(echo "${TARGET_CXXFLAGS}" | sed 's/-mabi=lp64//g; s/-Wno-psabi//g')

  mkdir -p ${PKG_BUILD}/.${TARGET_NAME}
  CLANG_TOOLCHAIN="${PKG_BUILD}/.${TARGET_NAME}/clang-toolchain.cmake"
  cat > "${CLANG_TOOLCHAIN}" <<EOF
# Cross-compilation identification
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_FIND_ROOT_PATH ${SYSROOT_PREFIX})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Use host Clang 20 as cross-compiler
set(CMAKE_C_COMPILER   "${TOOLCHAIN}/bin/clang-20")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN}/bin/clang-20")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN}/bin/clang-20")

# Use GCC toolchain's ar, ranlib, strip, assembler
set(CMAKE_AR      "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-ar")
set(CMAKE_RANLIB  "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-ranlib")
set(CMAKE_STRIP   "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-strip")
set(CMAKE_OBJCOPY "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-objcopy")
# Override the ASM compile rule to use clang with correct --target flag.
# cmake's default ASM rule doesn't propagate CMAKE_ASM_FLAGS_INIT and
# passes CXX flags (with clang-specific warnings) which break both
# clang-for-wrong-target and gcc-cross-assembler approaches.
set(CMAKE_ASM_COMPILE_OBJECT "${TOOLCHAIN}/bin/clang-20 --target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} <DEFINES> <INCLUDES> -x assembler-with-cpp -c <SOURCE> -o <OBJECT>")

# Clang cross-compilation flags
set(CMAKE_C_FLAGS_INIT   "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} ${CLANG_CFLAGS}")
set(CMAKE_CXX_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -stdlib=libstdc++ ${CLANG_CXXFLAGS}")
set(CMAKE_ASM_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN}")
set(CMAKE_ASM_FLAGS "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN}" CACHE STRING "" FORCE)

# LLD linker with GCC runtime libs in correct link order
set(CMAKE_EXE_LINKER_FLAGS_INIT    "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -fuse-ld=lld -stdlib=libstdc++ --rtlib=libgcc -unwindlib=libgcc")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -fuse-ld=lld -stdlib=libstdc++ --rtlib=libgcc -unwindlib=libgcc")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -fuse-ld=lld -stdlib=libstdc++ --rtlib=libgcc -unwindlib=libgcc")

# System libraries AFTER objects for correct lld link order
set(CMAKE_CXX_STANDARD_LIBRARIES "-lstdc++ -latomic -lpthread -lm -lGLEW -lGL" CACHE STRING "" FORCE)
set(CMAKE_C_STANDARD_LIBRARIES "-latomic -lpthread -lm" CACHE STRING "" FORCE)
EOF

  # Clear environment CFLAGS/CXXFLAGS — they contain GCC-specific flags
  export CFLAGS=""
  export CXXFLAGS=""
  export LDFLAGS=""

  PKG_CMAKE_OPTS_TARGET="-DCMAKE_TOOLCHAIN_FILE=${CLANG_TOOLCHAIN} ${PKG_CMAKE_OPTS_TARGET}"
}

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_BUILD}/.${TARGET_NAME}/bin/eden ${INSTALL}/usr/bin/eden
  cp -rf ${PKG_DIR}/scripts/start_eden.sh ${INSTALL}/usr/bin
  chmod 755 ${INSTALL}/usr/bin/*

  mkdir -p ${INSTALL}/usr/config/eden
  if [ -d "${PKG_DIR}/config/${DEVICE}" ]; then
    cp -rfH ${PKG_DIR}/config/${DEVICE}/* ${INSTALL}/usr/config/eden/
  fi

  # Install InputPlumber config if present
  if [ -d "${PKG_DIR}/config/InputPlumber" ]; then
    mkdir -p ${INSTALL}/usr/config/eden/InputPlumber
    cp -rfH ${PKG_DIR}/config/InputPlumber/* ${INSTALL}/usr/config/eden/InputPlumber/
  fi

  # Install mimalloc shared library for LD_PRELOAD
  mkdir -p ${INSTALL}/usr/lib
  cp -P ${SYSROOT_PREFIX}/usr/lib/libmimalloc.so* ${INSTALL}/usr/lib/ 2>/dev/null || true

  # Pre-install prod keys (LOCAL ONLY — not for public repos)
  # Keys are small (~25KB) and go into the squashfs at /usr/config/eden/keys/
  if [ -d "${PKG_DIR}/sources/keys" ]; then
    mkdir -p ${INSTALL}/usr/config/eden/keys
    cp -f ${PKG_DIR}/sources/keys/*.keys ${INSTALL}/usr/config/eden/keys/
  fi

  # NOTE: Firmware NCAs (~350MB) are too large for the system image.
  # They must be installed manually to /storage/roms/bios/eden/nand/
  # system/Contents/registered/ via SCP, NFS, or SD card.
  # The sources/firmware/ directory in the repo is for local reference
  # and SCP deployment — it is NOT included in the built image.
}
