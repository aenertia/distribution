#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ROCKNIX (https://github.com/ROCKNIX)

### setup is the same
. $(dirname $0)/es_settings

ES_ARGS="--log-path /var/log --no-splash"

# Dual-screen stretched mode: launch windowed at combined resolution
if [ "${DEVICE_HAS_DUAL_SCREEN}" = "true" ]; then
  STRETCHED=$(get_setting "system.stretched_mode")
  if [ "${STRETCHED}" = "1" ]; then
    STRETCHED_W=$(fbwidth)
    STRETCHED_H=$(($(fbheight) * 2))
    ES_ARGS="${ES_ARGS} --windowed --resolution ${STRETCHED_W} ${STRETCHED_H}"
  fi
fi

emulationstation ${ES_ARGS}
