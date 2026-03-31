# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="qt6"
PKG_VERSION_MAJOR="6.8"
PKG_VERSION="${PKG_VERSION_MAJOR}.3"
PKG_LICENSE="GPL"
PKG_SITE="https://download.qt.io"
PKG_URL="${PKG_SITE}/archive/qt/${PKG_VERSION_MAJOR}/${PKG_VERSION}/single/qt-everywhere-src-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain qt6:host openssl libjpeg-turbo libpng pcre2 sqlite zlib freetype SDL2 gstreamer gst-plugins-base gst-plugins-good gst-libav"
PKG_DEPENDS_HOST="gcc:host llvm:host mesa:host"
PKG_LONGDESC="A cross-platform application and UI framework"

# Apply project-specific patches
PKG_PATCH_DIRS="${PROJECT}"

# Set OpenGL or OpenGLES support for CMake
if [ "${OPENGL_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_HOST+=" ${OPENGL}"
  PKG_DEPENDS_TARGET+=" ${OPENGL}"
  PKG_CMAKE_OPTS_TARGET+=" -DQT_FEATURE_opengl=ON -DQT_FEATURE_opengles2=OFF"
elif [ "${OPENGLES_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_HOST+=" ${OPENGLES}"
  PKG_DEPENDS_TARGET+=" ${OPENGLES}"
  PKG_CMAKE_OPTS_TARGET+=" -DQT_FEATURE_opengles2=ON -DQT_FEATURE_opengl=OFF"
else
  PKG_CMAKE_OPTS_TARGET+=" -DQT_FEATURE_opengl=OFF -DQT_FEATURE_opengles2=OFF"
fi

# XCB support for X11
if [ "${DISPLAYSERVER}" = "x11" ]; then
  PKG_DEPENDS_TARGET+=" xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm libxcb-cursor libxkbcommon"
fi

# Wayland support
if [ "${DISPLAYSERVER}" = "wl" ]; then
  PKG_DEPENDS_TARGET+=" wayland xcb-util xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm libxcb-cursor libxkbcommon"
  PKG_CMAKE_OPTS_TARGET+=" -DBUILD_qtwayland=ON"
else
  PKG_CMAKE_OPTS_TARGET+=" -DBUILD_qtwayland=OFF"
fi

# Vulkan support
if [ "${VULKAN_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" ${VULKAN}"
  PKG_CMAKE_OPTS_TARGET+=" -DQT_FEATURE_vulkan=ON"
else
  PKG_CMAKE_OPTS_TARGET+=" -DQT_FEATURE_vulkan=OFF"
fi


pre_configure_host() {
  export LDFLAGS="${LDFLAGS} -lgio-2.0 -lgobject-2.0 -lglib-2.0"
  echo "LDFLAGS are $LDFLAGS"

  unset HOST_CMAKE_OPTS

  # --- HOST build cmake opts ---
  # The host build needs its own disable list since PKG_CMAKE_OPTS_HOST
  # is what scripts/build passes to cmake for host builds.
  HOST_MODULES_TO_DISABLE=("qt3d" "qt5compat" "qtactiveqt" "qtcoap" "qtconnectivity"
                           "qtdatavis3d" "qtdoc" "qtgraphs" "qtgrpc" "qthttpserver"
                           "qtlocation" "qtlottie" "qtmqtt" "qtnetworkauth" "qtopcua"
                           "qtpositioning" "qtquick3d" "qtquick3dphysics" "qtquickeffectmaker"
                           "qtquicktimeline" "qtremoteobjects" "qtscxml" "qtsensors"
                           "qtspeech" "qttranslations" "qtvirtualkeyboard"
                           "qtwebchannel" "qtwebengine" "qtwebview")
  for module in "${HOST_MODULES_TO_DISABLE[@]}"; do
    PKG_CMAKE_OPTS_HOST+=" -DBUILD_${module}=OFF"
  done
  HOST_MODULES_TO_ENABLE=("qtbase" "qtshadertools" "qtdeclarative" "qtsvg"
                          "qtlanguageserver" "qtimageformats" "qttools" "qtwayland"
                          "qtcharts")
  for module in "${HOST_MODULES_TO_ENABLE[@]}"; do
    PKG_CMAKE_OPTS_HOST+=" -DBUILD_${module}=ON"
  done
  PKG_CMAKE_OPTS_HOST+=" -DCMAKE_INSTALL_PREFIX=${TOOLCHAIN}/usr/local/qt6 \
                          -DCMAKE_BUILD_TYPE=Release \
                          -DQT_BUILD_EXAMPLES=OFF \
                          -DQT_BUILD_TESTS=OFF \
                          -DQT_USE_CCACHE=ON \
                          -DQT_GENERATE_SBOM=OFF \
                          -DQT_FEATURE_icu=OFF \
                          -DQT_FEATURE_wayland=ON \
                          -DBUILD_WITH_PCH=OFF \
                          -DFEATURE_clang=OFF \
                          -DFEATURE_clangcpp=OFF"

}

pre_configure_target() {
  # Target build cmake opts — must be set here (not in pre_configure_host)
  # because the build system sources package.mk fresh for each phase.
  MODULES_TO_DISABLE=("qt3d" "qt5compat" "qtactiveqt" "qtcoap" "qtconnectivity" "qtdatavis3d"
                      "qtdoc" "qtgraphs" "qtgrpc" "qthttpserver" "qtlocation" "qtlottie" "qtmqtt"
                      "qtnetworkauth" "qtopcua" "qtpositioning" "qtquick3d" "qtquick3dphysics"
                      "qtquickeffectmaker" "qtquicktimeline" "qtremoteobjects"
                      "qtscxml" "qtsensors" "qtspeech" "qttranslations" "qtvirtualkeyboard"
                      "qtwebchannel" "qtwebengine" "qtwebview")
  for module in "${MODULES_TO_DISABLE[@]}"; do
    PKG_CMAKE_OPTS_TARGET+=" -DBUILD_${module}=OFF"
  done

  MODULES_TO_ENABLE=("qtbase" "qtmultimedia" "qtshadertools" "qtdeclarative" "qtserialbus"
                     "qtserialport" "qtsvg" "qttools" "qtwebsockets" "qtlanguageserver"
                     "qtcharts")
  for module in "${MODULES_TO_ENABLE[@]}"; do
    PKG_CMAKE_OPTS_TARGET+=" -DBUILD_${module}=ON"
  done

  PKG_CMAKE_OPTS_TARGET+=" -DQT_HOST_PATH=${TOOLCHAIN}/usr/local/qt6 \
                           -DQT_DEBUG_FIND_PACKAGE=ON \
                           -DBUILD_SHARED_LIBS=ON \
                           -DQT_BUILD_EXAMPLES=OFF \
                           -DQT_BUILD_TESTS=OFF \
                           -DQT_FEATURE_printer=OFF \
                           -DQT_USE_CCACHE=ON \
                           -DQT_FEATURE_xcb=ON \
                           -DQT_GENERATE_SBOM=OFF \
                           -DBUILD_WITH_PCH=OFF \
                           -DQT_FEATURE_icu=OFF \
                           -DFEATURE_clang=OFF \
                           -DFEATURE_clangcpp=OFF"
}

post_makeinstall_target() {
  rm -rf ${INSTALL}/usr

  mkdir -p ${INSTALL}/usr/lib
  mkdir -p ${INSTALL}/usr/plugins
  mkdir -p ${INSTALL}/usr/qml

  cp -rf ${PKG_BUILD}/.${TARGET_NAME}/qtbase/lib/*.so* ${INSTALL}/usr/lib/
  cp -rf ${PKG_BUILD}/.${TARGET_NAME}/qtbase/plugins/* ${INSTALL}/usr/plugins/
  cp -rf ${PKG_BUILD}/.${TARGET_NAME}/qtbase/qml/* ${INSTALL}/usr/qml/
}
