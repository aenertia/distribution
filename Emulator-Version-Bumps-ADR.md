# ADR: Emulator & Core Version Bumps (2026-03-29)

## Status: Implemented

## Context

As part of the inputplumber branch comprehensive review, all standalone emulators (-sa) and libretro cores (-lr) were audited against their upstream repositories to identify version bumps. This audit was conducted alongside the wlroots 0.20 + sway 1.12-rc1 compositor stack migration.

**Audit scope:** 171 packages (128 libretro, 42 standalone, 1 compat)

## Decision

Update 19 packages to their latest upstream versions. Defer 2 packages (Amiberry, OpenBOR) that require additional integration work.

## Changes Applied

### Libretro Cores — Small Deltas (Wave 1)

| Core | Old Commit | New Commit | Delta | Key Changes |
|------|-----------|-----------|-------|-------------|
| pcsx_rearmed-lr | `228c14e1` | `9f8b6f24` | ~120 commits | r26 release: SPU fixes, GPU heuristic cleanup |
| nestopia-lr | `5deada54` | `c0ae3bcb` | 3 commits | Null pointer crash fix, VS System palette fix |
| mupen64plus-nx-lr | `7c7f1106` | `3a676196` | 12 commits | freedreno GPU fix, audio pops fix, GL context reset |
| genesis-plus-gx-lr | `e48a3717` | `d446078a` | 15 commits | Sega CD Word-RAM emulation fix |
| gambatte-lr | `6924c76b` | `d3c39fa1` | 3 commits | Translation/i18n updates |

### Libretro Cores — Large Deltas (Wave 2)

| Core | Old Commit | New Commit | Delta | Key Changes |
|------|-----------|-----------|-------|-------------|
| beetle-psx-lr | `4e0cb4dd` | `8fcb04d6` | ~49 commits | Vulkan hang fix, OpenBIOS support, CHD improvements, GL state leak fix |
| fbneo-lr | `012dbe9d` | `7290e952` | ~412 commits | Continuous upstream sync, new game drivers |
| flycast-lr | `c57b2e1a` | `05b270f0` | ~389 commits | DCNet features, i18n locale detection, input fixes |
| duckstation-lr | `24c37324` | `459a6fcf` | ~8,134 commits | ffmpeg 8.1, UI improvements, refresh rate fixes |
| dolphin-lr | `89a4df72` | `ae95d31e` | ~12,500 commits | 2603a release, cheat integration, RetroAchievements, FIFO fixes |

### Libretro Cores — Heavyweight (Wave 3)

| Core | Old Commit | New Commit | Delta | Key Changes |
|------|-----------|-----------|-------|-------------|
| ppsspp-lr | `afbc66a3` (v1.20.2) | `d357e6a3` (v1.20.3) | ~151 commits | 7z archive support, bugfixes |
| mame-lr | `a90e86e1` | `a10380b4` | ~1,654 commits | MAME 0.286 bump, major driver additions |

### Standalone Emulators — Tagged Releases (Wave 4)

| Emulator | Old Version | New Version | Key Changes |
|----------|------------|-------------|-------------|
| ppsspp-sa | v1.20.2 (`afbc66a3`) | v1.20.3 (`d357e6a3`) | Bugfix release |
| scummvmsa | 2026.1.0 | 2026.2.0 | 8 new games, PC-Speaker emulation, TinyGL optimizations |
| vice-sa | 3.8 | 3.10 | Accuracy improvements, USBSID-Pico support |
| hatarisa | `6da06056` | v2.6.1 (`6a8e26d6`) | MegaSTE 16MHz cache, TT SCU emulation, Falcon Videl fixes |
| nanoboyadvance-sa | `3bb6f478` | v1.8.2 (`b7bd0b0b`) | PPU rewrite (v1.7), save states, solar sensor, archive loading |
| gopher64-sa | `acf5e08b` | v1.1.15 (`1c6e23b7`) | Rust toolchain update, dependency refresh |

### Standalone Emulators — Major Jumps (Wave 5)

| Emulator | Old Version | New Version | Key Changes |
|----------|------------|-------------|-------------|
| dolphin-sa | `cddffd2e`/`e6583f8b` | 2603 (`d8558142`) | Triforce arcade emulation, MMU perf optimizations |

## Packages Confirmed Current (No Action)

| Package | Current Version | Reason |
|---------|----------------|--------|
| azahar-sa | 2125.0.1 | Already on latest release |
| flycast-sa | v2.6 | Already on latest release |
| skyemu-sa/lr | v5 (`46efbcbd`) | Commit matches v5 tag exactly |
| gzdoom-sa | g4.14.2 | Already on latest release |
| mednafen | 1.32.1 | Already on latest stable |
| melonds-sa | `bdd85c9c` | Post-1.1 development commit (3 months ahead of release) |
| retroarch | `fae7468d` | Post-v1.22.2 commit (3.5 months ahead of release) |
| snes9x-lr | `5a40cd55` | Already at latest commit |
| mgba-lr | `c758314a` | Already at latest commit |

## Deferred Packages

### Amiberry v8.1.2

**Reason:** SDL3 hard dependency change. Amiberry v8.x removed SDL2 entirely and requires SDL3 + SDL3_image as hard dependencies. While ROCKNIX ships SDL3 3.4.2 as the base runtime, there is no SDL3_image package yet. Additionally, Amiberry v8 replaced the Guisan GUI framework with Dear ImGui, which is a complete UI rewrite requiring testing on handheld displays.

**Action required:**
1. Package SDL3_image for ROCKNIX
2. Update PKG_SITE from `midwan/amiberry` to `BlitterStudio/amiberry` (repo migrated, GitHub redirects still work but are fragile)
3. Test ImGui rendering on handheld screens
4. Verify that `BUNDLE_SDL` option could be used as fallback

### OpenBOR v4.0

**Reason:** Complete engine rewrite from v3.0. Build 7533 represents OpenBOR 4.0 which includes 1000+ changes and 5+ years of development. PAK file compatibility with existing game mods needs thorough testing.

### DuckStation-sa

**Reason:** Prebuilt binary distribution. The INI parser change (simpleini removed, replaced with built-in parser) needs config file migration verification. The 42 rolling builds behind is incremental.

## Build Results

All 19 packages compiled and linked successfully for RK3566 (aarch64) target:
- **18/18** built on first pass (0 failures)
- **mame-lr** built separately (long compile time ~30 minutes)
- Non-fatal `unpack` warnings on packages where stale source directories existed (auto-recovered)

## Consequences

- All RK3566 images built after this change will include updated emulators
- The dolphin-sa bump unifies both device tracks to the same 2603 commit
- The ppsspp-sa and ppsspp-lr now share the same v1.20.3 source
- Full image rebuild recommended to catch any transitive dependency issues
- Hardware testing needed for: dolphin-sa Triforce support, NanoBoyAdvance PPU rewrite performance
