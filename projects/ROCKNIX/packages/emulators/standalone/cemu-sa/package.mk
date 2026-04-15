# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2022-present Frank Hartung (supervisedthinking (@) gmail.com)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

PKG_NAME="cemu-sa"
PKG_VERSION="94213643a2b55c5fa7f5deb0a7b0f5090faa9be7" # last-known-tag: v2.6
PKG_LICENSE="MPL-2.0"
PKG_SITE="https://github.com/cemu-project/Cemu"
# Local clone for dev iteration (rxnext branch with ROCKNIX patches)
PKG_URL="/var/home/aenertia/build/cemu/.git"
PKG_DEPENDS_TARGET="toolchain libzip glslang glm curl rapidjson openssl boost libfmt pugixml libpng gtk3 wxwidgets SDL2 libsodium hidapi spirv-tools llvm"
PKG_LONGDESC="Cemu is a Wii U emulator that is able to run most Wii U games and homebrew in a playable state"
PKG_GIT_CLONE_BRANCH="rxnext"
GET_HANDLER_SUPPORT="git"
#PKG_BUILD_FLAGS="+lto"

configure_package() {
  # Displayserver Support
  if [ "${DISPLAYSERVER}" = "x11" ]; then
    PKG_DEPENDS_TARGET+=" xwayland"
  elif [ "${DISPLAYSERVER}" = "wl" ]; then
    PKG_DEPENDS_TARGET+=" wayland"
  fi

  # OpenGL Support
  if [ "${OPENGL_SUPPORT}" = "yes" ]; then
    PKG_DEPENDS_TARGET+=" ${OPENGL}"
  fi

  # Vulkan Support
  if [ "${VULKAN_SUPPORT}" = "yes" ]; then
    PKG_DEPENDS_TARGET+=" ${VULKAN}"
  fi
}

pre_configure_target() {
  # Force build of cubeb submodule
  sed -e '/find_package(cubeb)/d' -i ${PKG_BUILD}/CMakeLists.txt
  # Fix glm linking
  sed -e "s#glm::glm#glm#" -i ${PKG_BUILD}/src/{Common,input}/CMakeLists.txt

  # Use host Clang 20 as a cross-compiler instead of GCC.
  # Clang is a natural cross-compiler — just pass --target and --sysroot.
  # Use libstdc++ (not libc++) for GCC runtime compatibility.
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

# Use host Clang 20 as cross-compiler
set(CMAKE_C_COMPILER   "${TOOLCHAIN}/bin/clang-20")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN}/bin/clang-20")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN}/bin/clang-20")

# Use the GCC toolchain's linker, ar, ranlib, etc.
set(CMAKE_AR      "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-ar")
set(CMAKE_RANLIB  "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-ranlib")
set(CMAKE_STRIP   "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-strip")
set(CMAKE_OBJCOPY "${TOOLCHAIN}/bin/aarch64-rocknix-linux-gnu-objcopy")

# Clang cross-compilation flags (GCC-incompatible flags filtered out)
set(CMAKE_C_FLAGS_INIT   "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} ${CLANG_CFLAGS}")
set(CMAKE_CXX_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -stdlib=libstdc++ ${CLANG_CXXFLAGS}")
# Use GNU assembler for .s files — ih264d assembly uses GAS syntax unsupported by Clang integrated-as
set(CMAKE_ASM_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -fno-integrated-as")

# LLD linker flags
set(CMAKE_EXE_LINKER_FLAGS_INIT    "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -fuse-ld=lld -stdlib=libstdc++ --rtlib=libgcc -unwindlib=libgcc")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -fuse-ld=lld -stdlib=libstdc++ --rtlib=libgcc -unwindlib=libgcc")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "--target=aarch64-rocknix-linux-gnu --sysroot=${SYSROOT_PREFIX} --gcc-toolchain=${TOOLCHAIN} -fuse-ld=lld -stdlib=libstdc++ --rtlib=libgcc -unwindlib=libgcc")

# System libraries (cemu-specific — sharpyuv for WebP texture decode)
set(CMAKE_CXX_STANDARD_LIBRARIES "-lstdc++ -latomic -lpthread -lm -lsharpyuv" CACHE STRING "" FORCE)
set(CMAKE_C_STANDARD_LIBRARIES "-latomic -lpthread -lm" CACHE STRING "" FORCE)
EOF
  # Clear environment CFLAGS/CXXFLAGS/LDFLAGS — they contain GCC-specific flags
  export CFLAGS=""
  export CXXFLAGS=""
  export LDFLAGS=""

  PKG_CMAKE_OPTS_TARGET="-DCMAKE_TOOLCHAIN_FILE=${CLANG_TOOLCHAIN} \
                         -D ENABLE_VCPKG=OFF \
                         -D PORTABLE=OFF \
                         -D ENABLE_DISCORD_RPC=OFF \
                         -D ENABLE_SDL=ON \
                         -D ENABLE_CUBEB=ON \
                         -D ENABLE_WXWIDGETS=ON \
                         -D CMAKE_BUILD_TYPE=Release \
                         -D ENABLE_FERAL_GAMEMODE=OFF \
                         -Wno-dev"

  # Wayland Support
  if [ "${DISPLAYSERVER}" = "wl" ]; then
    PKG_CMAKE_OPTS_TARGET+=" -D ENABLE_WAYLAND=ON"
  else
    PKG_CMAKE_OPTS_TARGET+=" -D ENABLE_WAYLAND=OFF"
  fi

  # OpenGL Support
  if [ "${OPENGL_SUPPORT}" = "yes" ]; then
    PKG_CMAKE_OPTS_TARGET+=" -D ENABLE_OPENGL=ON"
  else
    PKG_CMAKE_OPTS_TARGET+=" -D ENABLE_OPENGL=OFF"
  fi

  # Vulkan Support
  if [ "${VULKAN_SUPPORT}" = "yes" ]; then
    PKG_CMAKE_OPTS_TARGET+=" -D ENABLE_VULKAN=ON"
  else
    PKG_CMAKE_OPTS_TARGET+=" -D ENABLE_VULKAN=OFF"
  fi
}

makeinstall_target() {
  # Copy binary, scripts & config files
  mkdir -p ${INSTALL}/usr/bin
    cp -v ${PKG_BUILD}/bin/Cemu_* ${INSTALL}/usr/bin/cemu
    cp -v ${PKG_DIR}/scripts/*    ${INSTALL}/usr/bin/
    chmod 0755 ${INSTALL}/usr/bin/*

  mkdir -p ${INSTALL}/usr/config/Cemu
  # Install per-device settings.xml (renderer defaults, audio config)
  if [ -d "${PKG_DIR}/config/${DEVICE}" ]; then
    cp -rfH ${PKG_DIR}/config/${DEVICE}/* ${INSTALL}/usr/config/Cemu/
  fi
  # Install InputPlumber controller profiles (overlay on top of device config)
  if [ -d "${PKG_DIR}/config/InputPlumber" ]; then
    cp -rfH ${PKG_DIR}/config/InputPlumber/* ${INSTALL}/usr/config/Cemu/
  fi

  # Copy system files
  mkdir -p ${INSTALL}/usr/share/Cemu
    cp -PR ${PKG_BUILD}/bin/{gameProfiles,resources} ${INSTALL}/usr/share/Cemu
}
