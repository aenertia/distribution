#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ROCKNIX (https://github.com/ROCKNIX)

### setup is the same
. $(dirname $0)/es_settings
. /usr/lib/rocknix-display/display-core.sh

ES_ARGS="--log-path /var/log --no-splash"

# Dual-screen stretched mode: launch windowed at combined resolution
if display_is_dual; then
  STRETCHED=$(get_setting "system.stretched_mode")
  if [ "${STRETCHED}" = "1" ]; then
    ES_ARGS="${ES_ARGS} --windowed --resolution ${CANVAS_W} ${CANVAS_H}"
  fi
fi

emulationstation ${ES_ARGS}
