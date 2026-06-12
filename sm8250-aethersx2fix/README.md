# AetherSX2 SM8250 Vulkan Fix — Mesa 24.1.7 freedreno

Fixes severe graphical corruption in AetherSX2 (PS2 emulator) on SM8250 / Adreno 650 devices running ROCKNIX.

## The Problem

ROCKNIX SM8250 nightlies (20260529+) and UzuCore forks (20260528+) ship Mesa 24.2+ which introduced a
regression in the freedreno Vulkan driver affecting Adreno 650 (Snapdragon 865). AetherSX2 renders with
missing textures, garbled polygons, and broken lighting when using the Vulkan backend.

**OpenGL/Gallium is unaffected** — but AetherSX2 runs significantly better on Vulkan and some games require it.

## Affected Hardware

- SM8250 / Snapdragon 865 / Adreno 650 devices:
  - Retroid Pocket Mini v2
  - Retroid Pocket 5

**Not needed on** RK3326, RK3566, RK3588, SM6115, S922X or other devices.

## Known-Good vs Broken Mesa Versions

| Mesa Version | Status | Notes |
|---|---|---|
| ≤ 24.1.7 | ✅ Working | Last known-good freedreno Vulkan for Adreno 650 |
| 24.2.x | ❌ Broken | freedreno Vulkan regression introduced |
| 25.x | ❌ Broken | Shipped in ROCKNIX 20260529+, UzuCore 20260528+ |

**Evidence / References:**
- Mesa 24.1.7 release tag: https://gitlab.freedesktop.org/mesa/mesa/-/tags/mesa-24.1.7
- freedreno Vulkan issue tracker: https://gitlab.freedesktop.org/mesa/mesa/-/issues?label_name=freedreno
- ROCKNIX Mesa package: https://github.com/ROCKNIX/distribution/tree/next/packages/graphics/mesa
- This fix was validated on ROCKNIX 20260529 nightly and UzuCore 20260528

## Quick Install

```sh
# 1. Copy to device (replace <device-ip>)
scp aethersx2-sm8250fix.tar.gz root@<device-ip>:/storage/

# 2. Extract
ssh root@<device-ip> 'cd /storage && tar xzf aethersx2-sm8250fix.tar.gz'

# 3. Install
ssh root@<device-ip> 'bash /storage/aethersx2-sm8250fix/aethersx2-sm8250fix.sh'
```

Relaunch AetherSX2 — graphical corruption should be gone.

## What It Does NOT Touch

- ✅ All other emulators (RetroArch, eden, PPSSPP, Dolphin, etc.) continue using system Mesa
- ✅ No system-wide Vulkan/Mesa changes
- ✅ No `/usr/` modifications (would be wiped on OTA anyway)
- ✅ Only the `aethersx2` process inherits the Mesa override

## Surviving ROCKNIX OTA Updates

This fix is **self-healing**. After every ROCKNIX OTA update and reboot:

1. The autostart hook at `/storage/.config/autostart/055-aethersx2-mesa-fixup.sh` runs automatically
2. It detects that `start_aethersx2.sh` was re-scaffolded by ROCKNIX (marker comment gone)
3. It re-injects the Mesa override env vars, no user intervention needed

The Mesa 24.1.7 libs at `/storage/.config/mesa-compat/` are never touched by OTA updates.

## Uninstall

```sh
rm -rf /storage/.config/mesa-compat
rm -f /storage/.config/autostart/055-aethersx2-mesa-fixup.sh
# Then reboot
```

## Validated On

| Device | ROCKNIX Build | Games Tested |
|---|---|---|
| Retroid Pocket Mini v2 (SM8250) | ROCKNIX 20260529 nightly | Shadow of the Colossus, Kingdom Hearts, Ratchet & Clank: Going Commando |
| Retroid Pocket Mini v2 (SM8250) | UzuCore 20260528 | Shadow of the Colossus |

## Technical Details

**How the override works:**

The fix places Mesa 24.1.7 freedreno Vulkan driver libs at `/storage/.config/mesa-compat/lib/`. An autostart
hook (`055-aethersx2-mesa-fixup.sh`) patches `/storage/.config/aethersx2/start_aethersx2.sh` on every boot
to inject these env vars immediately before the aethersx2 binary is launched:

```bash
export VK_DRIVER_FILES="/storage/.config/mesa-compat/share/vulkan/icd.d/freedreno_icd.aarch64.json"
export LIBGL_DRIVERS_PATH="/storage/.config/mesa-compat/lib/dri"
export LD_LIBRARY_PATH="/storage/.config/mesa-compat/lib:${LD_LIBRARY_PATH}"
export MESA_NO_ERROR=1
```

These vars are inherited **only** by the aethersx2 child process, not by EmulationStation or any other app.

**Included libs (Mesa 24.1.7, aarch64):**
- `libvulkan_freedreno.so` — Vulkan 1.3.255, Adreno 6xx freedreno driver
- `libEGL_mesa.so.0.0.0` — Mesa EGL implementation
- `libgbm.so.1.0.0` — Generic Buffer Manager
- `libglapi.so.0.0.0` — Mesa GL API dispatch
- `lib/dri/msm_dri.so`, `kgsl_dri.so` — Gallium freedreno DRI drivers

**Idempotency:** The autostart hook uses a marker comment (`# AETHERSX2_MESA24_FIX`) to detect if
`start_aethersx2.sh` is already patched, making repeated runs harmless.
