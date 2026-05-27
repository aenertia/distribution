# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)

PKG_NAME="m4"
PKG_VERSION="1.4.20"
PKG_SHA256="ac6989ee5d2aed81739780630cc2ce097e2a6546feb96a4a54db37d46a1452e4"
PKG_LICENSE="GPL"
PKG_SITE="http://www.gnu.org/software/m4/"
PKG_URL="https://ftpmirror.gnu.org/m4/${PKG_NAME}-${PKG_VERSION}.tar.bz2"
PKG_DEPENDS_HOST="ccache:host"
PKG_LONGDESC="The m4 macro processor."
PKG_BUILD_FLAGS="-cfg-libs:host"

# Workaround: gnulib bundled in m4 1.4.20 has _Generic / fflush.c issues
# with GCC-15 + glibc 2.41. Force -std=gnu17 for host build.
pre_configure_host() {
  export CFLAGS="${CFLAGS} -std=gnu17"
}

PKG_CONFIGURE_OPTS_HOST="gl_cv_func_gettimeofday_clobber=no --target=${TARGET_NAME}"

post_makeinstall_host() {
  make prefix=${SYSROOT_PREFIX}/usr install
}
