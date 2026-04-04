#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present Joel Wiramu Pauling <aenertia@aenertia.net>
# Copyright (C) 2026-present ROCKNIX (https://rocknix.org)
#
# Trigger NFS game share mount via systemd service.
# Returns instantly — the mount runs asynchronously so ES does not freeze.
# Mount progress is logged to: journalctl -u rocknix-nfs-mount
# Config file: /storage/.nfs-mount (NFS_PATH=server:/share)

systemctl start rocknix-nfs-mount.service &
exit 0
