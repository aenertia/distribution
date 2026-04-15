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

---

# ADR Amendment: Wave 2 Version Bumps + RK3566 Clean Build (2026-04-15)

## Status: Implemented

## Context

Second wave audit of all ROCKNIX emulator packages, triggered by user request to:
- Bump sway to 1.12-rc2 (wlroots 0.20 compositor stack continuation)
- Bump azahar to 2125.1 (new tagged release)
- Audit all non-blocklisted -sa/-lr cores against upstream and update to latest

**Audit scope:** All ~155 non-blocklisted emulator packages
**Build target:** `make RK3566` → `ROCKNIX-RK3566.aarch64-20260415-{Generic,Specific}.img.gz`
**Build iterations:** 13 builds, 10 package failures identified and resolved

## Changes Applied

### Wave 1: Targeted Bumps (Commits 1–2)

| Package | Old Version | New Version | Notes |
|---------|------------|-------------|-------|
| sway | 1.12-rc1 | 1.12-rc2 | Simple PKG_VERSION string swap; tarball URL auto-updates |
| azahar-sa | 2125.0.1 (`7e58ac5b`) | 2125.1 (`afbaf8e4`) | Patches applied cleanly (fuzz 2/offset 4 acceptable) |
| azahar-lr | 2125.0-alpha6 (`e351fa56`) | 2125.1 (`afbaf8e4`) | No patches, zero risk |

### Wave 2: Standalone Emulators Audit + Update (Commit 3)

| Package | Change | Notes |
|---------|--------|-------|
| bigpemu-sa | v119 → v121 | richwhitehouse.com release |
| portmaster | 2025.12.07-0332 → 2026.04.01-1426 | Simple version string; located in apps/ not emulators/ |
| mupen64plus-sa-core | Bumped to latest HEAD | |
| mupen64plus-sa-audio-sdl | Bumped to latest HEAD | |
| mupen64plus-sa-input-sdl | Bumped to latest HEAD | |
| mupen64plus-sa-rsp-cxd4 | Bumped to latest HEAD | |
| mupen64plus-sa-rsp-hle | Bumped to latest HEAD | |
| mupen64plus-sa-video-glide64mk2 | Bumped to latest HEAD | |
| mupen64plus-sa-video-rice | Bumped to latest HEAD | |
| daedalusx64-sa | Bumped to latest HEAD | |
| gopher64-sa | Bumped to latest HEAD | |
| hatarisa | Bumped to latest HEAD | |
| hypseus-singe | Bumped to latest HEAD | |
| rpcs3-src | Bumped to latest HEAD | |
| supermodel-sa | Bumped to latest HEAD | |
| touchhle-sa | Bumped to latest HEAD | |
| xemu-sa | Bumped to latest HEAD | |
| yabasanshiro-sa | Bumped to latest HEAD | |
| ppsspp-sa | DEFERRED — stays at v1.20.2 | 002-fullscreen-drm.patch fails at v1.20.3 |
| cemu-sa, mednafen, minivmacsa, openbor4, skyemu-sa | No change | Already at latest |

### Wave 3: Libretro Cores Audit + Update (Commits 4–5)

Cores 81-lr through yabasanshiro-lr were audited. All non-blocklisted cores bumped to latest HEAD SHA. Key highlights:

| Package | Change | Notes |
|---------|--------|-------|
| libxmp-lite (easyrpg sub-dep) | 4.5.0 → 4.7.0 | Tagged release bump |
| easyrpg-lr sub-deps (liblcf, libspeexdsp) | Bumped | |
| ~80 libretro cores | Bumped to latest HEAD | All annotated with last-known-tag |
| common-shaders | Bumped | |
| core-info | Bumped | |
| glsl-shaders | Bumped | |
| slang-shaders | Bumped | |
| flycast-lr | DEFERRED — stays at 05b270f0 | gcc15 SpvBuilder.h path changed; patch broken |
| gpsp-lr | DEFERRED — stays at b0d5d27a | Makefile restructured upstream |
| kronos-lr | DEFERRED — stays at 46e687cb | ygl-width patch broken on all versions after this SHA |
| play-lr | DEFERRED — stays at previous SHA | CMakeLists.txt hunk failed |
| mu-lr, sameboy-lr | NOT CHECKED | git.libretro.com auth required |
| retroarch | NOT UPDATED | Blocklisted (manual-only); stays at v1.22.2 |

## Build Failure Log and Resolutions

| # | Package | Failure | Resolution |
|---|---------|---------|------------|
| 1 | wildmidi (easyrpg-lr sub-dep) | cmake 3.30 incompatibility: `WRITE_BASIC_PACKAGE_VERSION_FILE` missing `VERSION` arg; also missing `-D` prefix on cmake opt | Reverted to tag `wildmidi-0.4.3` SHA `405ca73a`; fixed `-DWANT_PLAYER=OFF` |
| 2 | arduous-lr | git submodule `simavr` not initialized (GET_HANDLER_SUPPORT="git") | Ran `git submodule update --init --recursive` in source cache |
| 3 | atari800-lr | Empty git clone in source cache (clone succeeded, working tree empty) | Deleted broken source cache dir; fresh `scripts/unpack` |
| 4 | doublecherrygb-lr | HEAD adds `libmobile` git submodule not in tarball → breaks `make`; build system creates `.aarch64-rocknix/` subdir from CMakeLists.txt | Reverted to tag 0.18.1 SHA `2e7a8bd5`; added `make_target() { cd ${PKG_BUILD}; make; }` |
| 5 | freechaf-lr | git submodule `src/deps/libretro-common` not initialized | Ran `git submodule update --init --recursive` in source cache |
| 6 | jaxe-lr | Empty git working tree (clone dir existed but no files) | Deleted broken source cache; fresh `scripts/unpack` |
| 7 | hatari-lr | `undefined reference to 'Console_Check'` — PR#113 "linux-aarch64 build" merged but linker error in new SHA `00af13a` | Reverted to previous SHA `7008194d` |
| 8 | mupen64plus-sa-simplecore | `000-cross-compile.patch` hunk#1 fails at new line 320 — upstream restructured Makefile SDL detection | Reverted to SHA `5340dafc` |
| 9 | easyrpg-lr | cmake `PlayerFindPackage` requires `liblcf 0.8` exactly; installed `liblcf 0.8.1` incompatible | Reverted to SHA `31de2a75` |
| 10 | mupen64plus-sa-video-gliden64 | `001-txfilter-stub-fix.patch` can't find `src/TxFilterStub.cpp` — new upstream removed this file | Reverted to SHA `85bdd452` |

## Key Build System Learnings

- **CMakeLists.txt + PKG_TOOLCHAIN="make"**: Build system creates `.aarch64-rocknix-linux-gnu/` subdir and CDs into it before calling `make_target()`. Fix: `make_target() { cd ${PKG_BUILD}; make; }`.
- **GET_HANDLER_SUPPORT="git" source cache**: Silent clone failures can leave empty working trees. Detection: check source cache dir for actual files. Fix: delete cache dir, re-run `scripts/unpack`.
- **Git submodule packages**: Submodules not initialized by default in tarball-style git clones. Fix: `git submodule update --init --recursive` in source cache dir (for runtime fix) or prefer SHA that doesn't require submodules.
- **Stamp files**: `scripts/clean` removes build dir + qa_checks but NOT stamps in `.stamps/<pkg>/` and `image/.stamps/<pkg>/`. The parallel build scheduler reassigns step numbers between runs.
- **Patch vs HEAD tracking**: When bumping to HEAD breaks a patch, always revert to the `last-known-tag` SHA annotated in package.mk. Do NOT attempt to maintain patches against a moving HEAD.

## Build Result

- **Build #13** — clean completion after 10 failure+fix iterations
- **698/698** packages installed successfully
- **Progress**: 695 done → mame-lr linked → mame2015-lr compiled → entware → image assembly
- **Output images** (created 2026-04-15 07:33 UTC):
  - `target/ROCKNIX-RK3566.aarch64-20260415-Generic.img.gz` (1.6 GB)
  - `target/ROCKNIX-RK3566.aarch64-20260415-Specific.img.gz` (1.6 GB)
  - Both with sha256 checksums
- **QA warning**: pre-existing `systemd-260/safe_remove` check — unrelated to emulator bumps

## Deferred Package Summary (Wave 2)

| Package | Reason | Action Required |
|---------|--------|-----------------|
| ppsspp-sa | `002-fullscreen-drm.patch` fails at v1.20.3 | Rebase patch against v1.20.3 DRM changes |
| flycast-lr | gcc15 `SpvBuilder.h` include path changed | Update patch for new header location |
| gpsp-lr | Makefile restructured upstream | Rewrite cross-compile patch for new structure |
| kronos-lr | `ygl-width` patch broken on all post-`46e687cb` SHAs | Investigate upstream Kronos Yabause restructuring |
| play-lr | CMakeLists.txt hunk failed | Update patch for new CMakeLists.txt layout |
| wildmidi | Stays at 0.4.3 (cmake 3.30 incompatible at 0.4.6) | Wait for wildmidi to fix cmake compatibility OR upgrade cmake |
| doublecherrygb-lr | Stays at 0.18.1 (libmobile submodule not in tarball) | Switch to GET_HANDLER_SUPPORT="git" to support submodules |
| hatari-lr | Stays at 7008194d (Console_Check linker error at HEAD) | Wait for upstream to fix linker issue |
| mupen64plus-sa-simplecore | Stays at 5340dafc (cross-compile patch breaks) | Rebase 000-cross-compile.patch for new SDL detection |
| easyrpg-lr | Stays at 31de2a75 (liblcf version mismatch) | Bump liblcf to match new easyrpg requirements |
| mupen64plus-sa-video-gliden64 | Stays at 85bdd452 (TxFilterStub removed) | Update patch to not reference removed file |
| mu-lr, sameboy-lr | git.libretro.com auth required | Use HTTPS mirror or add auth |
