# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Lukas Rusak (lrusak@libreelec.tv)
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)

PKG_NAME="go"
PKG_VERSION="1.24.2"
PKG_LICENSE="BSD"
PKG_SITE="https://golang.org"
PKG_URL="https://github.com/golang/go/archive/${PKG_NAME}${PKG_VERSION}.tar.gz"
PKG_DEPENDS_HOST="toolchain"
PKG_LONGDESC="An programming language that makes it easy to build simple, reliable, and efficient software."
PKG_TOOLCHAIN="manual"

configure_host() {
  local _user_home="$(getent passwd $(whoami) | cut -d: -f6)"
  export HOME=${ROOT}
  export GOOS=linux
  export GOROOT_FINAL=${TOOLCHAIN}/lib/golang
  export GOCACHE=${HOME}/.cache/go-build

  # Go 1.24+ requires Go >= 1.22.6 for bootstrap.
  # Check user-installed bootstrap first, then system paths.
  if [ -x "${_user_home}/go-bootstrap/bin/go" ]; then
    export GOROOT_BOOTSTRAP="${_user_home}/go-bootstrap"
  elif [ -x /usr/lib/go/bin/go ]; then
    export GOROOT_BOOTSTRAP=/usr/lib/go
  else
    export GOROOT_BOOTSTRAP=/usr/lib/golang
  fi
  case ${TARGET_ARCH} in
    aarch64|arm)
      export GOARCH=amd64
    ;;
  esac

  if [ ! -d ${GOROOT_BOOTSTRAP} ]; then
    cat <<EOF
####################################################################
# On Fedora 'dnf install golang' will install go to /usr/lib/golang
#
# On Ubuntu you need to install golang:
# $ sudo apt install golang-go
#
# Go 1.24+ requires Go >= 1.22.6 for bootstrap.
# Install a recent Go to ~/go-bootstrap if system Go is too old.
####################################################################
EOF
    return 1
  fi
}

make_host() {
  cd ${PKG_BUILD}/src
  bash make.bash --no-banner
}

pre_makeinstall_host() {
  # need to cleanup old golang version when updating to a new version
  rm -rf ${TOOLCHAIN}/lib/golang
}

makeinstall_host() {
  mkdir -p ${TOOLCHAIN}/lib/golang
  cp -av ${PKG_BUILD}/* ${TOOLCHAIN}/lib/golang/
}
