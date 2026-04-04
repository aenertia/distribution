#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present Joel Wiramu Pauling <aenertia@aenertia.net>
# Copyright (C) 2026-present ROCKNIX (https://rocknix.org)
#
# Disconnect NFS game share and restore local storage.
# Runs in foreground inside foot — ES waits for the unmount to complete,
# then the gamelist is reloaded via ES HTTP API (non-destructive).

exec /usr/bin/nfs-game-unmount
