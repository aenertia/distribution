# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2022-2024 JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="rkbin"
PKG_LICENSE="nonfree"
PKG_SITE="https://github.com/rockchip-linux/rkbin"
PKG_LONGDESC="rkbin: Rockchip Firmware and Tool Binaries"
PKG_TOOLCHAIN="manual"

case "${DEVICE}" in
  RK3566)
    # Bumped for BL31 v1.45 + ddrbin_tool.py fix (required for DMC devfreq)
    PKG_VERSION="ef49d0c2852b16ce0d72d7ee4849638cb5de27b7"
    ;;
  RK3588|S922X)
    # Pin to known-good version (S922X libmali breakage reported with 74213af1)
    PKG_VERSION="7c35e21a8529b3758d1f051d1a5dc62aae934b2b"
    ;;
  *)
    PKG_VERSION="74213af1e952c4683d2e35952507133b61394862"
    ;;
esac

PKG_URL="https://github.com/rockchip-linux/rkbin/archive/${PKG_VERSION}.tar.gz"

post_unpack() {
 if [ "${DEVICE}" == "RK3326" ]; then
  # RK3326: tune TPL for UART5 used on K36 clones
  cp -v ${PKG_BUILD}/bin/rk33/rk3326_ddr_333MHz_*.bin ${PKG_BUILD}/rk3326_ddr_uart5.bin
  if [ -f "${PKG_BUILD}/tools/ddrbin_tool.py" ]; then
    python3 ${PKG_BUILD}/tools/ddrbin_tool.py rk3326 -g ${PKG_BUILD}/rk3326_ddr_uart5.txt ${PKG_BUILD}/rk3326_ddr_uart5.bin
    sed -i 's|uart id=.*$|uart id=5|' ${PKG_BUILD}/rk3326_ddr_uart5.txt
    python3 ${PKG_BUILD}/tools/ddrbin_tool.py rk3326 ${PKG_BUILD}/rk3326_ddr_uart5.txt ${PKG_BUILD}/rk3326_ddr_uart5.bin >/dev/null
  else
    ${PKG_BUILD}/tools/ddrbin_tool rk3326 -g ${PKG_BUILD}/rk3326_ddr_uart5.txt ${PKG_BUILD}/rk3326_ddr_uart5.bin
    sed -i 's|uart id=.*$|uart id=5|' ${PKG_BUILD}/rk3326_ddr_uart5.txt
    ${PKG_BUILD}/tools/ddrbin_tool rk3326 ${PKG_BUILD}/rk3326_ddr_uart5.txt ${PKG_BUILD}/rk3326_ddr_uart5.bin >/dev/null
  fi
 fi
}
