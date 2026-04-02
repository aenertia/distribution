#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present Joel Wiramu Pauling <aenertia@aenertia.net>
# Copyright (C) 2026-present ROCKNIX (https://rocknix.org)
#
# Trigger NFS game share mount.
# Runs in foreground inside foot — ES waits for the mount to complete,
# then the gamelist is reloaded via ES HTTP API (non-destructive).
# Config file: /storage/.nfs-mount (NFS_PATH=server:/share)

exec /usr/bin/nfs-game-mount
