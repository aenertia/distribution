#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)
#
# ES Tools launcher for Eden (Nintendo Switch emulator).
# Delegates to start_eden.sh which handles config setup, env vars,
# and locale.  Runs in foreground so foot (the terminal wrapper from
# es_systems.cfg) stays open for the session — ES resumes when eden exits.

. /etc/profile

# Fullscreen eden's window once it creates its Wayland surface
(
  sleep 2
  sway_fullscreen "eden" "app_id"
) &

# Launch eden in standalone (menu) mode — foreground so foot/ES wait
exec /usr/bin/start_eden.sh
