#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2019-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2021-present 351ELEC (https://github.com/351ELEC)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

# OpenBOR 4.0 launcher
# OpenBOR only works with Pak files, if you have an extracted game you will need to create a pak first.

pakname=$(basename "$1")
pakname="${pakname%.*}"

CONFIGDIR="/storage/openbor4"
PAKS="${CONFIGDIR}/Paks"
SAVES="${CONFIGDIR}/Saves"

# Make sure the folders exist
  mkdir -p "${CONFIGDIR}"
  mkdir -p "${PAKS}"
  mkdir -p "${SAVES}"

# Check if master.cfg exists
  if [ ! -f "${CONFIGDIR}/master.cfg" ]; then
    cp -f "/usr/config/openbor4/master.cfg" "${CONFIGDIR}/" 2>/dev/null || true
  fi

# Clear PAKS folder to avoid getting the launcher on next run
  rm -rf ${PAKS}/*

# make a symlink to the pak
  ln -sf "$1" "${PAKS}"

# only create symlink to master.cfg if its the first time running the pak
  if [ ! -f "${SAVES}/${pakname}.cfg" ]; then
    if [ -f "${CONFIGDIR}/master.cfg" ]; then
      ln -sf "${CONFIGDIR}/master.cfg" "${SAVES}/${pakname}.cfg"
    fi
  fi

# We start the fake keyboard
  gptokeyb openbor4 &

# Run OpenBOR4 in the config folder
  cd "${CONFIGDIR}"
  OpenBOR4

# We stop the fake keyboard
  killall gptokeyb &
