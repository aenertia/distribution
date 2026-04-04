#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

source /etc/profile

export GDK_BACKEND=wayland
set_kill set "cemu"

sway_fullscreen "cemu" "app_id" &

exec /usr/bin/cemu
