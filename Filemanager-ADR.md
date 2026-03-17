# ADR: ROCKNIX File Manager

**Status:** Proposed
**Date:** 2026-03-15
**Author:** Joel Wiramu Pauling

---

## Context

ROCKNIX ships two SDL2-based file managers selected at build time per device:

| Manager | Devices | Layout | Input | Upstream |
|---------|---------|--------|-------|----------|
| **commander** | RK3326, RK3399, RK3566, RK3588, S922X, SDM845, SM8250, SM8550, SM8650 | Dual-pane (Norton Commander style) | Native SDL2 gamepad | [od-contrib/commander](https://github.com/od-contrib/commander) |
| **fileman** | All others (H700, legacy) | Single-pane list | gptokeyb (gamepad-to-keyboard daemon) | [ROCKNIX/fileman](https://github.com/ROCKNIX/fileman) (fork of [Tardigrade-nx/351Files](https://github.com/Tardigrade-nx/351Files)) |

Both are C++ / SDL2 applications with SDL2_image, SDL2_gfx, SDL2_ttf dependencies. Selection logic is in `projects/ROCKNIX/packages/misc/modules/package.mk`.

### Problems with the status quo

1. **Commander** is functional but has limited UX — basic file operations only, no bookmarks, no archive handling, no preview, no search
2. **Fileman** requires gptokeyb (external daemon) for gamepad input rather than native SDL2 gamepad handling
3. Neither has been substantially developed recently
4. No unified solution — two codebases to maintain
5. Both lack modern file manager features (fuzzy search, bulk operations, previews, compression)

### Requirements for a replacement

- **Tiny footprint** — handhelds have limited storage (squashfs rootfs) and RAM (512MB–4GB)
- **Gamepad-native input** — D-pad navigation, A/B confirm/cancel, shoulder buttons for page up/down; must work without keyboard
- **All-platform** — single solution for all ROCKNIX devices (ARM64 + x86_64)
- **Intuitive UX** — usable without documentation on a handheld with 3.5–7" screen
- **File operations** — copy, move, delete, rename, create directory, view text/images
- **Integration** — launches from EmulationStation Tools menu via shell script in `/usr/config/modules/`

---

## ROCKNIX Infrastructure Constraints

### Available in base image
- **SDL2 v2.32.10** + SDL2_image, SDL2_gfx, SDL2_ttf, SDL2_mixer
- **ncurses** (full terminfo)
- **foot** (Wayland terminal emulator)
- **Sway** (Wayland compositor) — apps run fullscreen via `sway_fullscreen`
- **gamecontrollerdb** — standardized SDL2 gamepad mappings at `/usr/config/SDL-GameControllerDB/gamecontrollerdb.txt`
- **bash, coreutils, busybox** — standard POSIX utilities
- **PipeWire** — audio
- **libinput** — Wayland input stack

### NOT available in base image
- Python 3 interpreter (build-time only)
- Lua / Love2D runtime
- Godot runtime
- Qt / GTK
- X11 libraries (pure Wayland stack)

### Launch pattern
```bash
#!/bin/bash
. /etc/profile
set_kill set "appname"
sway_fullscreen "appname" &
/usr/bin/appname
```

---

## Option 1: Enhance Commander (RECOMMENDED)

### Description
Improve the existing od-contrib/commander with missing features. It already has native SDL2 gamepad support, dual-pane layout, and is built for all modern devices.

### Upstream
- **Repository:** https://github.com/od-contrib/commander
- **Language:** C++ with CMake
- **Origin:** Fork of DinguxCommander, originally built for Dingoo A320 handhelds
- **Related forks:** [shauninman/DinguxCommander-sdl2](https://github.com/shauninman/DinguxCommander-sdl2), [zfteam/DinguxCommander-sdl2](https://github.com/zfteam/DinguxCommander-sdl2)
- **License:** MIT
- **Activity:** Moderate — last commits in 2024/2025

### Current features
- Dual-pane Norton Commander layout
- Copy, move, delete, rename files/directories
- Text viewer and editor
- Image viewer (zoom, fit, navigate)
- Disk usage calculation
- Virtual keyboard for text input
- DPI-aware scaling (PPU settings per device)
- Dark theme (ROCKNIX patches)
- Controller button mapping (A=open, B=parent, configurable via CMake)

### What would need adding
- Bookmarks / quick-navigate (e.g. /storage/roms, /storage/.config)
- Archive viewing/extraction (p7zip already in image)
- File search / filter
- Batch select and operations
- Sort options (name, size, date, type)
- Status bar with free space / path info
- Better theming / font size options

### Pros
- Already built, tested, and deployed on all modern ROCKNIX devices
- Native SDL2 gamepad — no gptokeyb needed
- Proven handheld lineage (DinguxCommander heritage)
- Small binary (~200KB)
- MIT license — easy to fork and extend
- Same dependency set as everything else (SDL2 stack)

### Cons
- Upstream (od-contrib) activity is moderate — may need ROCKNIX fork
- C++ codebase is moderately complex (21 source files)
- Adding features means maintaining a fork

### Effort: Low–Medium

---

## Option 2: TUI File Manager + Gamepad Wrapper

### Description
Use a lightweight terminal file manager (nnn, lf, vifm, or fff) running in foot terminal, with gamepad-to-keyboard input translation.

### Candidates

#### nnn — https://github.com/jarun/nnn
- **Language:** C
- **Binary size:** 50–55 KB (stripped), 125 KB with icons
- **Memory:** <3.5 MB resident
- **Dependencies:** ncurses (available in ROCKNIX)
- **License:** BSD-2-Clause
- **Activity:** Very active, well-maintained
- **Features:** Plugins, bookmarks, batch rename, archive support, file preview, fuzzy search, disk usage, type-to-nav
- **Cross-compile:** Straightforward (C + ncurses, supports musl)
- **Verdict:** Best TUI candidate — tiny, feature-rich, designed for constrained environments

#### lf — https://github.com/gokcehan/lf
- **Language:** Go
- **Binary size:** ~6–8 MB (static)
- **Dependencies:** None (single static binary) + terminfo
- **License:** MIT
- **Activity:** Active
- **Features:** Preview, bookmarks, async operations, bulk rename, shell commands
- **Cross-compile:** `GOARCH=arm64 go build` — trivial
- **Verdict:** Good option — single binary simplicity, but Go binary size is 100x nnn

#### vifm — https://github.com/vifm/vifm
- **Language:** C
- **Binary size:** ~2.8 MB
- **Dependencies:** ncurses, glib2
- **License:** GPL-2.0
- **Features:** Dual-pane, vim-like keybindings, preview, trash, marks, tabs
- **Verdict:** Powerful but vim keybindings assume keyboard familiarity

#### fff — https://github.com/dylanaraps/fff
- **Language:** Bash (script)
- **Binary size:** ~10 KB script
- **Dependencies:** bash, coreutils
- **License:** MIT
- **Activity:** Archived/unmaintained
- **Features:** Minimal — navigate, open, delete, rename
- **Verdict:** Ultra-minimal fallback option, unmaintained

#### ranger — https://github.com/ranger/ranger
- **Language:** Python 3
- **Dependencies:** Python 3 + libraries (NOT in ROCKNIX base image)
- **Verdict:** Rejected — Python not available, too heavy for handhelds

### Gamepad input translation approaches

1. **gptokeyb** — already used by fileman; maps gamepad buttons to keyboard keys. Works but adds a daemon dependency and has edge cases with text input modes.

2. **evdev-to-uinput daemon** — Custom C/Python daemon reading /dev/input/eventX gamepad events and synthesizing keyboard events via uinput. More control but another component to maintain.

3. **SDL2 gamepad-to-stdin bridge** — Small SDL2 app that reads gamepad via SDL_GameController API and writes escape sequences to stdout, piped to the TUI app. Elegant but needs careful terminal interaction.

4. **oga_controls** — Existing ROCKNIX tool (libevdev + SDL2) for legacy devices that emulates keyboard/mouse from gamepad. Could potentially be repurposed.

### Architecture
```
EmulationStation → launch script
    └─ foot (Wayland terminal)
        ├─ gptokeyb or evdev mapper (gamepad → keyboard)
        └─ nnn/lf/vifm (TUI file manager)
```

### Pros
- Access to mature, feature-rich file managers (nnn has everything)
- nnn is 55KB — smallest possible binary
- TUI apps are inherently keyboard-driven with single-key shortcuts that map well to gamepad buttons
- foot terminal already available

### Cons
- Requires gamepad-to-keyboard translation layer (extra complexity/daemon)
- TUI rendering on small screens (480p) may be hard to read
- No image preview without terminal image protocol support (sixel/kitty)
- Two processes (mapper + app) to manage lifecycle
- Edge cases: text input, special key combos, virtual keyboard

### Effort: Medium

---

## Option 3: SDL2/SDL3 Terminal Wrapper

### Description
Build a custom SDL2 application that embeds a pseudo-terminal (pty), renders terminal output as SDL2 textures (using a bitmap/TTF font), and captures SDL2 gamepad input to inject as keyboard sequences into the pty. Essentially an SDL2 terminal emulator with native gamepad support, running nnn/lf inside.

### Architecture
```
SDL2 App
  ├─ SDL_GameController → escape sequences → pty master
  ├─ pty slave → nnn/lf/vifm
  └─ VT parser → SDL2_ttf glyph rendering → SDL_Renderer
```

### Existing prior art
- **sdl2text** — already in ROCKNIX tree (`projects/ROCKNIX/packages/apps/sdl2text/`), SDL2 text reader with gamepad controls. Proves the rendering approach works.
- **st (suckless terminal)** — simple terminal emulator, ~4500 LOC C. Could be adapted as reference for VT parsing.
- **libvterm** — C library for VT terminal emulation (used by neovim). Could provide the parsing layer.

### Pros
- Native SDL2 gamepad — no external mapper daemon
- Pixel-perfect rendering for small screens (custom font sizes, scaling)
- Could support image preview via custom escape sequences
- Single process — clean lifecycle management
- Reusable as a general "gamepad terminal" tool for ROCKNIX

### Cons
- Significant development effort (VT100/xterm escape sequence parsing is complex)
- Maintaining a terminal emulator is a large ongoing commitment
- Essentially building a custom terminal emulator just to run a file manager
- Over-engineered for the problem

### Effort: High

---

## Option 4: Love2D / Godot Wrapper

### Description
Build a file manager UI in Love2D (Lua) or Godot (GDScript) that wraps filesystem operations, providing a game-like UI with native gamepad support through the engine's input system.

### Love2D
- **Runtime overhead:** ~10–20 MB
- **Not in ROCKNIX base image** — would need Love2D package added
- **Gamepad support:** Built-in via love.joystick
- **Existing file managers:** None found
- **Would need:** Complete file browser UI from scratch in Lua
- **Reference:** Love2D is used by some ROCKNIX ports (PortMaster)

### Godot
- **Runtime overhead:** 30–50+ MB (Godot 4 export template)
- **Not in ROCKNIX base image** — massive addition
- **Gamepad support:** Built-in via Input system
- **Existing file managers:** One toy "RPG file explorer" found on r/godot (not usable)
- **Would need:** Complete file browser UI from scratch in GDScript

### Pros
- Rich UI toolkit with animations, transitions, theming
- Native gamepad support through engine input systems
- Rapid development (scripting languages vs C++)
- Could create a visually distinctive experience

### Cons
- **Love2D:** 10–20 MB runtime overhead for a file manager; no existing implementations to build on
- **Godot:** 30–50 MB runtime — unacceptable for a squashfs-constrained handheld
- Neither framework is in the base image — adds permanent dependency
- Building a complete file manager from scratch regardless of framework
- Over-engineered — game engine for file management

### Effort: High (Love2D), Very High (Godot)

---

## Option 5: Sunflower File Manager

### Description
[Sunflower](https://sunflower-fm.org/) is a small, highly customizable twin-panel file manager for Linux with plugin support. Written in Python 3 with GTK3, it integrates with GNOME but is not limited to it. Fully compatible with Wayland compositors.

### Upstream
- **Repository:** https://github.com/MeanEYE/Sunflower (preferred: GitLab)
- **Website:** https://sunflower-fm.org/
- **Language:** Python 3 (99% Python)
- **UI toolkit:** GTK3 (PyGObject / GObject Introspection bindings)
- **License:** GPL-3.0
- **Version:** 0.5 (current release), v0.4 was the GTK3/Python3 migration
- **Activity:** 3,159 commits, 441 stars, moderate activity — long development history
- **Packages:** Arch AUR, Ubuntu PPA, Gentoo

### Features
- Twin-panel (Norton Commander / Total Commander style) layout
- Tabbed interface with sessions (saved tab sets)
- Built-in terminal (VTE or external)
- Plugin system (image manipulation, SQLite viewer, extract-here, etc.)
- Emblems for visual file marking
- Multithreaded file operations
- Keyboard-oriented design
- Bookmarks and mounts integration
- Multiple rename tool
- Customizable via configuration

### Dependencies required (NOT in ROCKNIX base image)
- **Python 3** — interpreter not shipped in ROCKNIX runtime (build-time only)
- **GTK3** — not available (ROCKNIX is pure Wayland/SDL2, no GTK)
- **PyGObject** (gi) — GObject Introspection Python bindings
- **VTE** — terminal widget library (optional but expected)
- **GLib/GIO** — GNOME platform libraries
- **pango, cairo, gdk-pixbuf** — some available via wlroots chain but not the full GTK stack

### Analysis for ROCKNIX

**Showstopper issues:**

1. **Python 3 not in base image** — ROCKNIX deliberately excludes Python from the runtime squashfs to save space. Adding CPython would add ~15-25 MB to the image. The `rocknix-systems` script uses Python at boot but via a minimal build-time inclusion, not a full interpreter.

2. **GTK3 not available** — ROCKNIX uses a pure SDL2 + Wayland (Sway/wlroots) stack. GTK3 and its full dependency chain (ATK, at-spi2, GLib schemas, icon themes, gsettings, dconf) would add 30-50+ MB and pull in a large portion of the GNOME platform. This fundamentally conflicts with the embedded/minimal design.

3. **No gamepad input** — Sunflower is keyboard-oriented with GTK keyboard event handling. It has no SDL2 gamepad support and no gamepad-to-keyboard abstraction. Adding gamepad support would require either:
   - gptokeyb-style mapper (external daemon)
   - Patching PyGObject/GTK event handling to read from evdev (major effort)
   - Running under an accessibility layer

4. **Display size** — GTK3 widgets with GNOME styling are designed for desktop monitors. On a 480x320 or 640x480 handheld screen, GTK widgets would be either unusably small or require extensive CSS/theme work for touch-sized targets.

5. **Startup time** — Python + GTK3 cold start on a Cortex-A55 @ 1.8 GHz would be several seconds, compared to sub-second for SDL2 native apps.

### Pros
- Very feature-rich — plugins, tabs, sessions, terminal, emblems
- Wayland compatible (confirmed by upstream)
- Keyboard-oriented design maps somewhat to gamepad D-pad navigation
- Active community with translations

### Cons
- **Python 3 + GTK3 dependency chain is a non-starter** for ROCKNIX's embedded squashfs model
- Adding GTK3 stack would increase image size by 30-50+ MB
- No gamepad support — keyboard-only input model
- GTK3 widgets unsuitable for 3.5-5" handheld screens without major theming
- Performance overhead (Python + GTK vs native C/SDL2)
- GPL-3.0 (more restrictive than commander's MIT)

### Verdict
**Not recommended for ROCKNIX.** Sunflower is an excellent desktop file manager but its Python 3 + GTK3 dependency chain makes it fundamentally incompatible with ROCKNIX's embedded constraints. The combined overhead of Python interpreter + GTK3 + PyGObject + GNOME platform libraries (~45-75 MB) is unacceptable for a squashfs-based handheld OS where the entire rootfs is typically 200-400 MB. Even if dependencies could be satisfied, the lack of gamepad input and desktop-oriented widget sizing would require extensive modification.

However, Sunflower's **feature set and UX design** are worth studying as a reference for what a fully-featured file manager should offer — particularly its plugin architecture, session management, and bookmarks/mounts integration. These features could inform enhancements to commander (Option 1).

### Effort: Very High (porting infeasible)

---

## Option 6: Replace Both with Single Improved SDL2 File Manager

### Description
Write a new SDL2 file manager from scratch (or major rewrite of commander) that unifies the fileman/commander split and adds modern features. Target all platforms with a single, responsive-layout binary.

### Design goals
- Single-pane list view (simpler than dual-pane for small screens)
- Responsive layout that works from 320x240 to 1920x1080
- Native SDL2 gamepad via SDL_GameController
- Bookmarks (quick-nav to /storage/roms, /storage/.config, etc.)
- Archive support (view/extract via p7zip CLI)
- Sort/filter with type-ahead search
- Text viewer (reuse sdl2text approach)
- Image thumbnail preview
- File size and disk usage display

### Pros
- Purpose-built for ROCKNIX
- Eliminates the fileman/commander split
- Can leverage existing SDL2 infrastructure and patterns from both codebases
- Optimal for all screen sizes

### Cons
- Significant development effort from scratch
- Ongoing maintenance burden
- Could diverge from upstream community work

### Effort: High

---

## Comparison Matrix

| Criteria | Enhance Commander | TUI + Wrapper | SDL2 Terminal | Love2D/Godot | Sunflower | New SDL2 App |
|----------|:-:|:-:|:-:|:-:|:-:|:-:|
| Binary size | ~200 KB | 55 KB–8 MB + mapper | ~500 KB + TUI app | 10–50 MB | 45–75 MB (Python+GTK3) | ~300 KB |
| Gamepad native | Yes | Via mapper | Yes | Yes | No | Yes |
| Dev effort | Low–Med | Medium | High | High | Very High (port) | High |
| Feature richness | Medium (extensible) | High (nnn/lf) | High (nnn/lf) | Custom | Very High | Custom |
| Maintenance | Fork od-contrib | Upstream + mapper | Custom terminal | Custom + engine | Upstream + patches | Fully custom |
| New dependencies | None | None (ncurses exists) | libvterm optional | Love2D/Godot runtime | Python3, GTK3, PyGObject | None |
| Risk | Low | Medium | High | Medium–High | Very High | Medium |
| All platforms | Yes (extend to all) | Yes | Yes | Yes | No (GTK3 missing) | Yes |

---

## Recommendation

### Primary: Option 1 — Enhance Commander

**Rationale:**
1. Commander is already deployed on most ROCKNIX devices with native gamepad support
2. Its DinguxCommander heritage means it was literally designed for this exact use case
3. Smallest incremental effort — add features to working code rather than building from scratch
4. MIT license permits forking to ROCKNIX org if upstream becomes inactive
5. Same SDL2 dependency set — zero new runtime additions

**Immediate actions:**
- Fork od-contrib/commander to ROCKNIX org
- Add bookmarks panel (L1/R1 to switch, pre-populated with /storage/roms, /storage/.config)
- Add sort options (name/size/date toggle via Select button)
- Add file search/filter (virtual keyboard input → filter displayed files)
- Extend to ALL devices (replace fileman entirely) with per-device PPU scaling

**Future enhancements:**
- Archive viewing via p7zip CLI integration
- Batch select (Y to toggle, then operate on selection)
- Status bar with free space and current path

### Fallback: Option 2 — nnn + gptokeyb

If commander enhancement proves too limited or the codebase is too rigid:
- Package nnn as `projects/ROCKNIX/packages/apps/nnn/package.mk`
- Launch via foot terminal with gptokeyb mapping D-pad→arrows, A→Enter, B→Backspace, X→delete, Y→rename, L1/R1→PgUp/PgDn
- nnn's plugin system and bookmarks provide immediate feature richness at 55KB
- ncurses already in base image — zero new dependencies

### Not recommended
- **Love2D/Godot:** Runtime overhead unacceptable, no existing implementations
- **SDL2 terminal wrapper:** Over-engineered, building a terminal emulator to run a file manager
- **Sunflower:** Python 3 + GTK3 dependency chain (~45–75 MB) incompatible with embedded squashfs model; no gamepad support; desktop widget sizing unsuitable for handheld screens. Excellent feature reference though.
- **New SDL2 app from scratch:** High effort when commander already exists and works
- **ranger:** Python not available in base image
- **yazi:** Rust binary too large (~15 MB), build toolchain overhead

---

## References

### Existing ROCKNIX packages
- Commander package: `projects/ROCKNIX/packages/apps/commander/package.mk`
- Fileman package: `projects/ROCKNIX/packages/apps/fileman/package.mk`
- Module selection: `projects/ROCKNIX/packages/misc/modules/package.mk`
- Commander launcher: `projects/ROCKNIX/packages/misc/modules/sources/commander.sh`
- Fileman launcher: `projects/ROCKNIX/packages/misc/modules/sources/fileman.sh`
- SDL2 package: `projects/ROCKNIX/packages/graphics/SDL2/package.mk`
- sdl2text: `projects/ROCKNIX/packages/apps/sdl2text/`
- gamecontrollerdb: `projects/ROCKNIX/packages/apps/gamecontrollerdb/`

### Desktop file managers (reference only)
- Sunflower: https://sunflower-fm.org/ / https://github.com/MeanEYE/Sunflower

### External projects
- od-contrib/commander: https://github.com/od-contrib/commander
- DinguxCommander (original): https://github.com/shauninman/DinguxCommander-sdl2
- ROCKNIX/fileman (351Files fork): https://github.com/ROCKNIX/fileman
- Tardigrade-nx/351Files (original): https://github.com/Tardigrade-nx/351Files
- nnn: https://github.com/jarun/nnn
- lf: https://github.com/gokcehan/lf
- vifm: https://github.com/vifm/vifm
- fff: https://github.com/dylanaraps/fff (archived)
- ranger: https://github.com/ranger/ranger
- yazi: https://github.com/sxyazi/yazi
- filebrowser (web): https://filebrowser.org
- Midnight Commander: https://www.midnight-commander.org
