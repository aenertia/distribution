#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present Joel Wiramu Pauling <aenertia@aenertia.net>
# Copyright (C) 2026-present ROCKNIX (https://rocknix.org)
#
# Disconnect NFS game share and restore local storage.
# Runs asynchronously so ES does not freeze.

/usr/bin/nfs-game-unmount &
exit 0
