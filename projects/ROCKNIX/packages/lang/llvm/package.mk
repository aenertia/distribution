# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="llvm"
PKG_VERSION="22.1.2"
PKG_SHA256="62f2f13ff25b1bb28ea507888e858212d19aafb65e8e72b4a65ee0629ec4ae0c"
PKG_LICENSE="Apache-2.0"
PKG_SITE="http://llvm.org/"
PKG_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${PKG_VERSION}/llvm-project-${PKG_VERSION/-/}.src.tar.xz"
PKG_DEPENDS_HOST="toolchain:host"
PKG_DEPENDS_TARGET="toolchain llvm:host zlib"
PKG_LONGDESC="Low-Level Virtual Machine (LLVM) is a compiler infrastructure."
PKG_TOOLCHAIN="cmake"

if listcontains "${GRAPHIC_DRIVERS}" "(iris|panfrost|freedreno)"; then
  PKG_DEPENDS_UNPACK="spirv-headers spirv-llvm-translator"
fi

PKG_CMAKE_OPTS_COMMON="-DLLVM_INCLUDE_TOOLS=ON \
                       -DLLVM_BUILD_TOOLS=ON \
                       -DLLVM_BUILD_UTILS=OFF \
                       -DLLVM_BUILD_EXAMPLES=OFF \
                       -DLLVM_INCLUDE_EXAMPLES=OFF \
                       -DLLVM_BUILD_TESTS=OFF \
                       -DLLVM_INCLUDE_TESTS=OFF \
                       -DLLVM_BUILD_BENCHMARKS=OFF \
                       -DLLVM_INCLUDE_BENCHMARKS=OFF \
                       -DLLVM_BUILD_DOCS=OFF \
                       -DLLVM_INCLUDE_DOCS=OFF \
                       -DLLVM_ENABLE_DOXYGEN=OFF \
                       -DLLVM_ENABLE_SPHINX=OFF \
                       -DLLVM_ENABLE_OCAMLDOC=OFF \
                       -DLLVM_ENABLE_BINDINGS=OFF \
                       -DLLVM_ENABLE_ASSERTIONS=OFF \
                       -DLLVM_ENABLE_WERROR=OFF \
                       -DLLVM_ENABLE_ZLIB=OFF \
                       -DLLVM_ENABLE_ZSTD=OFF \
                       -DLLVM_ENABLE_LIBXML2=OFF \
                       -DLLVM_BUILD_LLVM_DYLIB=ON \
                       -DLLVM_LINK_LLVM_DYLIB=ON \
                       -DLLVM_OPTIMIZED_TABLEGEN=ON \
                       -DLLVM_APPEND_VC_REV=OFF \
                       -DLLVM_ENABLE_RTTI=ON \
                       -DLLVM_ENABLE_UNWIND_TABLES=OFF \
                       -DLLVM_ENABLE_Z3_SOLVER=OFF \
                       -DLLVM_SPIRV_INCLUDE_TESTS=OFF \
                       -DCMAKE_SKIP_RPATH=ON"

post_unpack() {
  if listcontains "${GRAPHIC_DRIVERS}" "(iris|panfrost|freedreno)"; then
    mkdir -p "${PKG_BUILD}"/llvm/projects/{SPIRV-Headers,SPIRV-LLVM-Translator}
      tar --strip-components=1 \
        -xf "${SOURCES}/spirv-headers/spirv-headers-$(get_pkg_version spirv-headers).tar.gz" \
        -C "${PKG_BUILD}/llvm/projects/SPIRV-Headers"
      tar --strip-components=1 \
        -xf "${SOURCES}/spirv-llvm-translator/spirv-llvm-translator-$(get_pkg_version spirv-llvm-translator).tar.gz" \
        -C "${PKG_BUILD}/llvm/projects/SPIRV-LLVM-Translator"
  fi
}

pre_configure() {
  PKG_CMAKE_SCRIPT=${PKG_BUILD}/llvm/CMakeLists.txt
}

pre_configure_host() {
  case "${MACHINE_HARDWARE_NAME}" in
    "aarch64")
      LLVM_BUILD_TARGETS="AArch64"
      ;;
    "arm")
      LLVM_BUILD_TARGETS="ARM"
      ;;
    "x86_64")
      LLVM_BUILD_TARGETS="X86"
      ;;
  esac

  case "${TARGET_ARCH}" in
    "aarch64")
      LLVM_BUILD_TARGETS+="\;AArch64"
      ;;
    "arm")
      LLVM_BUILD_TARGETS+="\;ARM"
      ;;
    "x86_64")
      LLVM_BUILD_TARGETS+="\;X86\;AMDGPU"
      ;;
  esac

  mkdir -p ${PKG_BUILD}/.${HOST_NAME}
  cd ${PKG_BUILD}/.${HOST_NAME}
  PKG_CMAKE_OPTS_HOST="${PKG_CMAKE_OPTS_COMMON} \
                       -DCMAKE_BINARY_DIR=${PKG_BUILD}/.${HOST_NAME} \
                       -DLLVM_NATIVE_BUILD=${PKG_BUILD}/.${HOST_NAME}/native \
                       -DLLVM_ENABLE_PROJECTS='clang;lld' \
                       -DCLANG_LINK_CLANG_DYLIB=ON \
                       -DLLVM_TARGETS_TO_BUILD=${LLVM_BUILD_TARGETS}"
}

post_make_host() {
  ninja ${NINJA_OPTS} llvm-config llvm-objcopy llvm-tblgen clang-tblgen

  if listcontains "${GRAPHIC_DRIVERS}" "(iris|panfrost|freedreno)"; then
    ninja ${NINJA_OPTS} llvm-as llvm-link llvm-spirv opt
  fi
}

post_makeinstall_host() {
  mkdir -p ${TOOLCHAIN}/bin
    cp -a bin/llvm-config ${TOOLCHAIN}/bin
    cp -a bin/llvm-objcopy ${TOOLCHAIN}/bin
    cp -a bin/llvm-tblgen ${TOOLCHAIN}/bin
    cp -a bin/clang-tblgen ${TOOLCHAIN}/bin
    # LLD linker — needed for linking clang-compiled objects (LLVM bitcode)
    cp -a bin/ld.lld ${TOOLCHAIN}/bin
    cp -a bin/lld ${TOOLCHAIN}/bin

  if listcontains "${GRAPHIC_DRIVERS}" "(iris|panfrost|freedreno)"; then
    cp -a bin/{llvm-as,llvm-link,llvm-spirv,opt} "${TOOLCHAIN}/bin"
  fi
}

pre_configure_target() {
  # Select LLVM backends and subprojects based on target architecture.
  # aarch64: AArch64 backend + Clang/LLD (for RPCS3 JIT, Mesa freedreno, build tools)
  # x86_64:  AMDGPU;X86 backends (for Mesa radeonsi/amdvlk)
  case "${TARGET_ARCH}" in
    "aarch64")
      LLVM_TARGET_BACKENDS="AArch64"
      LLVM_TARGET_EXTRA_OPTS="-DCLANG_TABLEGEN=${TOOLCHAIN}/bin/clang-tblgen"
      ;;
    "x86_64")
      LLVM_TARGET_BACKENDS="AMDGPU\;X86"
      LLVM_TARGET_EXTRA_OPTS=""
      ;;
    *)
      LLVM_TARGET_BACKENDS="AArch64"
      LLVM_TARGET_EXTRA_OPTS=""
      ;;
  esac

  mkdir -p ${PKG_BUILD}/.${TARGET_NAME}
  cd ${PKG_BUILD}/.${TARGET_NAME}

  # For aarch64, write a cmake initial-cache file to pass LLVM_ENABLE_PROJECTS
  # as a proper cmake list. The \; escaping in bash/cmake CLI doesn't work for
  # cmake lists that go through foreach() validation in LLVM's CMakeLists.txt.
  if [ "${TARGET_ARCH}" = "aarch64" ]; then
    LLVM_PROJECTS_CACHE="${PKG_BUILD}/.${TARGET_NAME}/llvm_projects.cmake"
    echo 'set(LLVM_ENABLE_PROJECTS "clang;lld" CACHE STRING "" FORCE)' > "${LLVM_PROJECTS_CACHE}"
    LLVM_TARGET_EXTRA_OPTS+=" -C ${LLVM_PROJECTS_CACHE}"
  fi
  PKG_CMAKE_OPTS_TARGET="${PKG_CMAKE_OPTS_COMMON} \
                          -DCMAKE_BINARY_DIR=${PKG_BUILD}/.${TARGET_NAME} \
                          -DLLVM_NATIVE_BUILD=${PKG_BUILD}/.${HOST_NAME} \
                          -DCMAKE_CROSSCOMPILING=ON \
                          -DLLVM_TARGETS_TO_BUILD=${LLVM_TARGET_BACKENDS} \
                          -DLLVM_TARGET_ARCH="${TARGET_ARCH}" \
                          -DLLVM_HOST_TRIPLE=${TARGET_ARCH}-unknown-linux-gnu \
                          -DLLVM_DEFAULT_TARGET_TRIPLE=${TARGET_ARCH}-unknown-linux-gnu \
                          -DLLVM_TABLEGEN=${TOOLCHAIN}/bin/llvm-tblgen \
                          ${LLVM_TARGET_EXTRA_OPTS}"
}

post_makeinstall_target() {
  mkdir -p ${SYSROOT_PREFIX}/usr/bin
    cp -a ${TOOLCHAIN}/bin/llvm-config ${SYSROOT_PREFIX}/usr/bin

  # Remove binaries/tools from target image (they're build-time only).
  # Clang+LLD libraries remain in the sysroot for packages like rpcs3-src.
  rm -rf ${INSTALL}/usr/bin
  rm -rf ${INSTALL}/usr/lib/LLVMHello.so
  rm -rf ${INSTALL}/usr/lib/libLTO.so
  rm -rf ${INSTALL}/usr/libexec
  rm -rf ${INSTALL}/usr/share
}
