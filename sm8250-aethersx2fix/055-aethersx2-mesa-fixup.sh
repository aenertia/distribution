#!/bin/bash
# SPDX-License-Identifier: MIT
# AetherSX2 Mesa 24.1.7 Vulkan fix for ROCKNIX SM8250 (Adreno 650)
#
# Self-healing autostart hook. Runs on every boot from /storage/.config/autostart/
# Patches start_aethersx2.sh to use Mesa 24.1.7 freedreno instead of the system
# Mesa which has Adreno 650 rendering regressions in 24.2+.
#
# SCOPE: Only affects the AetherSX2 process. No system-wide Mesa/Vulkan changes.
# Install: /storage/.config/autostart/055-aethersx2-mesa-fixup.sh

MESA_COMPAT_DIR="/storage/.config/mesa-compat"
START_SCRIPT="/storage/.config/aethersx2/start_aethersx2.sh"
MARKER="# AETHERSX2_MESA24_FIX"

# Bail if mesa-compat dir doesn't exist (fix not installed)
if [ ! -d "$MESA_COMPAT_DIR" ]; then
    exit 0
fi

# Wait up to 30s for ROCKNIX to scaffold start_aethersx2.sh
WAIT=0
while [ ! -f "$START_SCRIPT" ] && [ "$WAIT" -lt 30 ]; do
    sleep 1
    WAIT=$((WAIT + 1))
done

if [ ! -f "$START_SCRIPT" ]; then
    exit 0
fi

# Idempotency: if already patched, nothing to do
if grep -q "$MARKER" "$START_SCRIPT"; then
    exit 0
fi

# Inject Mesa override env vars BEFORE the aethersx2 launch line
python3 - "$START_SCRIPT" << 'PYEOF'
import sys

path = sys.argv[1]
marker = "# AETHERSX2_MESA24_FIX"
inject_lines = [
    "# AETHERSX2_MESA24_FIX — Mesa 24.1.7 Vulkan override (AetherSX2 process only)\n",
    'export VK_DRIVER_FILES="/storage/.config/mesa-compat/share/vulkan/icd.d/freedreno_icd.aarch64.json"\n',
    'export LIBGL_DRIVERS_PATH="/storage/.config/mesa-compat/lib/dri"\n',
    'export LD_LIBRARY_PATH="/storage/.config/mesa-compat/lib:${LD_LIBRARY_PATH}"\n',
    'export MESA_NO_ERROR=1\n',
    '\n',
]

with open(path, 'r') as f:
    lines = f.readlines()

out = []
injected = False
skip_words = {'kill', 'bios', 'log', 'mkdir', 'config', 'inis', 'marker'}

for line in lines:
    lower = line.lower().strip()
    # Find the actual aethersx2 launch line (not comments, not housekeeping)
    if (not injected
            and 'aethersx2' in lower
            and not lower.startswith('#')
            and not any(w in lower for w in skip_words)):
        out.extend(inject_lines)
        injected = True
    out.append(line)

# Fallback: if no launch line found, append at end
if not injected:
    out.append('\n')
    out.extend(inject_lines)

with open(path, 'w') as f:
    f.writelines(out)
PYEOF

exit 0
