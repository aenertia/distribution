PKG_NAME="rxnm"
PKG_VERSION="b1520683281eb7e00a3db524785edc7266ba34b1"
PKG_LICENSE="GPLv2+"
PKG_SITE="https://codeberg.org/aenertia/rxnm"
PKG_URL="https://codeberg.org/aenertia/rxnm.git"
PKG_DEPENDS_TARGET="toolchain jq systemd iwd"
PKG_SECTION="network"
PKG_SHORTDESC="ROCKNIX Network Manager"
PKG_LONGDESC="A lightning-fast, modular CLI suite and API gateway for systemd-networkd and iwd."

PKG_TOOLCHAIN="make"

build_target() {
  # Build the static agent (tiny profile)
  make -C ${PKG_BUILD} tiny CC="${CC}"
}

makeinstall_target() {
  # Install core components (binaries, libs, templates, completions) using upstream Makefile
  make -C ${PKG_BUILD} install PREFIX="${INSTALL}/usr"

  # Install systemd units (not handled by upstream Makefile)
  mkdir -p ${INSTALL}/usr/lib/systemd/system
  cp ${PKG_BUILD}/systemd/*.service ${INSTALL}/usr/lib/systemd/system/
  cp ${PKG_BUILD}/systemd/*.socket ${INSTALL}/usr/lib/systemd/system/
}

post_install() {
  enable_service rocknix-network-manager.service
  # Note: rxnm-roaming.service and rxnm-api.socket are installed but disabled by default.
}
