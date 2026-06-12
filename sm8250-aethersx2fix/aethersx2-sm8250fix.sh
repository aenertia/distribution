#!/bin/bash
# AetherSX2 SM8250 Mesa 24.1.7 Vulkan Fix — One-Shot Installer
# Installs mesa-compat libs, autostart self-heal hook, and optionally fixes PCSX2.ini
# Idempotent — safe to run multiple times.
# Non-interactive — no prompts.
set -euo pipefail

# ── Step 1: Determine script location ────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ERRORS=0
PCSX2_STATUS="SKIPPED (config not found)"

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
fail() { echo "[ERROR] $*"; ERRORS=$((ERRORS + 1)); }

# ── Step 2: Sanity check — SM8250 ────────────────────────────────────────────
if [ ! -f /usr/bin/aethersx2-sa ]; then
    warn "aethersx2-sa not found at /usr/bin/aethersx2-sa — are you on SM8250?"
    warn "Continuing anyway (you may be testing on another device)."
fi

# ── Preflight: mesa-compat dir must exist in the package ─────────────────────
if [ ! -d "$SCRIPT_DIR/mesa-compat/lib" ]; then
    echo "======================================"
    echo "AetherSX2 SM8250 Mesa Fix — FAILED"
    echo "======================================"
    echo ""
    echo "ERROR: mesa-compat/lib/ not found relative to this script."
    echo "Expected at: $SCRIPT_DIR/mesa-compat/lib/"
    echo ""
    echo "Make sure you extracted the full tarball and are running"
    echo "the script from inside the extracted directory."
    echo "======================================"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/055-aethersx2-mesa-fixup.sh" ]; then
    echo "======================================"
    echo "AetherSX2 SM8250 Mesa Fix — FAILED"
    echo "======================================"
    echo ""
    echo "ERROR: 055-aethersx2-mesa-fixup.sh not found next to this script."
    echo "Expected at: $SCRIPT_DIR/055-aethersx2-mesa-fixup.sh"
    echo "======================================"
    exit 1
fi

# ── Step 3: Install mesa-compat libs ─────────────────────────────────────────
MESA_DEST="/storage/.config/mesa-compat"
log "Installing Mesa 24.1.7 freedreno libs to $MESA_DEST ..."

mkdir -p "$MESA_DEST/lib/dri" "$MESA_DEST/share/vulkan/icd.d"
cp -a "$SCRIPT_DIR/mesa-compat/lib/"* "$MESA_DEST/lib/"
cp -a "$SCRIPT_DIR/mesa-compat/share/"* "$MESA_DEST/share/"

# Verify
if [ -f "$MESA_DEST/lib/libvulkan_freedreno.so" ]; then
    log "Mesa libs installed OK."
else
    fail "libvulkan_freedreno.so missing after copy — something went wrong."
fi

# ── Step 4: Install autostart self-heal hook ─────────────────────────────────
AUTOSTART_DIR="/storage/.config/autostart"
log "Installing autostart hook to $AUTOSTART_DIR ..."

mkdir -p "$AUTOSTART_DIR"
cp "$SCRIPT_DIR/055-aethersx2-mesa-fixup.sh" "$AUTOSTART_DIR/"
chmod +x "$AUTOSTART_DIR/055-aethersx2-mesa-fixup.sh"
log "Autostart hook installed."

# ── Step 5: Remove old manual autostart if present ───────────────────────────
if [ -f "$AUTOSTART_DIR/050-aethersx2-mesa.sh" ]; then
    log "Removing old 050-aethersx2-mesa.sh autostart hook ..."
    rm -f "$AUTOSTART_DIR/050-aethersx2-mesa.sh"
fi

# ── Step 6: Run the fixup immediately ────────────────────────────────────────
log "Running fixup hook now (don't wait for reboot) ..."
bash "$AUTOSTART_DIR/055-aethersx2-mesa-fixup.sh" || warn "Fixup hook returned non-zero (may be OK on non-SM8250)."

# ── Step 7: Fix AetherSX2 PCSX2.ini if it exists ────────────────────────────
PCSX2_INI="/storage/.config/aethersx2/inis/PCSX2.ini"
if [ -f "$PCSX2_INI" ]; then
    log "Patching PCSX2.ini ..."

    # Fix BIOS path
    if grep -q 'BiosDirectory' "$PCSX2_INI"; then
        sed -i 's|BiosDirectory\s*=.*|BiosDirectory = /storage/roms/bios/aethersx2|' "$PCSX2_INI"
        log "BIOS path set to /storage/roms/bios/aethersx2"
    fi

    # Set Vulkan renderer (value 14 in AetherSX2)
    if grep -q '^Renderer' "$PCSX2_INI"; then
        sed -i 's|^Renderer\s*=.*|Renderer = 14|' "$PCSX2_INI"
        log "Renderer set to 14 (Vulkan)."
    fi

    PCSX2_STATUS="SET"
else
    log "PCSX2.ini not found — skipping config patch (will be applied on first run if needed)."
fi

# ── Step 8: Summary ──────────────────────────────────────────────────────────
echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "======================================"
    echo "AetherSX2 SM8250 Mesa Fix — FAILED ($ERRORS error(s))"
    echo "======================================"
    echo "Check the errors above and retry."
    echo "======================================"
    exit 1
fi

echo "======================================"
echo "AetherSX2 SM8250 Mesa Fix — INSTALLED"
echo "======================================"
echo "Mesa 24.1.7 freedreno libs: $MESA_DEST/lib/"
echo "Autostart self-heal hook:   $AUTOSTART_DIR/055-aethersx2-mesa-fixup.sh"
echo "PCSX2.ini Vulkan renderer:  $PCSX2_STATUS"
echo ""
echo "This fix survives ROCKNIX OTA updates automatically."
echo "Only AetherSX2 is affected — all other emulators use system Mesa."
echo ""
echo "To uninstall:"
echo "  rm -rf /storage/.config/mesa-compat"
echo "  rm -f /storage/.config/autostart/055-aethersx2-mesa-fixup.sh"
echo "  Then reboot."
echo "======================================"
