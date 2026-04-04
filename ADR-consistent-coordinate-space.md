# ADR: Consistent Coordinate Space for Multi-Output Emulator Handling

## Status: PROPOSED

## Date: 2026-03-26

## Author: Joel Wiramu Pauling (aenertia@aenertia.net)

## PR Context

> I've been experimenting with different ways to handle this for multi-screen
> devices; I am of the opinion, we likely need to have a think about a
> consistent approach/wrapper script that is usable for any emu that has
> multiple outputs. And likewise provides a standard co-ordinate space
> irrespective of how the actual outputs are wired (rg-ds dsi is side by side,
> not sure about the thor, but it's conceivable we end up with a device that is
> proper above/bellow at some point, and certainly when considering hdmi/dp - as
> outputs this is a 'common' situation). Otherwise we are going to end up with
> specific emu quirks over and over again and don't fix it in the 'generic'
>
> — [PR #2473 comment](https://github.com/ROCKNIX/distribution/pull/2473)

---

## Context

ROCKNIX supports a growing matrix of multi-output devices and dual-screen
emulators. The physical wiring of outputs varies dramatically between devices,
but the **logical requirement** is always the same: "I need a top screen and a
bottom screen" or "I need a left screen and a right screen."

### Device Matrix (physical wiring varies)

| Device | Outputs | Physical Wiring | Panel Resolution | Notes |
|--------|---------|----------------|-----------------|-------|
| Anbernic RG DS | DSI-1 + DSI-2 | Side-by-side (electrically) | 640x480 each | Presented as top/bottom via sway positioning |
| AYANEO Pocket DS | DSI-1 + DSI-2 | True top/bottom (clamshell) | 1024x600 each | Direct vertical mapping |
| AYN Thor | DSI-1 + DSI-2 | Side-by-side (landscape) | 1080x340 + 1080x1920 | Asymmetric panels, needs scaling |
| Retroid RDS | DSI-1 + DP-1 | USB-C Lontium add-on dock | Mixed | External via DisplayPort alt-mode |
| Any + HDMI | DSI-1 + HDMI-A-1 | External monitor | Mixed | Common use case: 353P + TV |
| Future vertical | ? + ? | True above/below | ? | Inevitable as form factors evolve |

### Emulator Matrix (window models vary)

| Emulator | System | Window Model | Current Dual-Screen Handling |
|----------|--------|-------------|----------------------------|
| [Azahar](https://azahar-emu.org/) | 3DS | Single window, custom layout regions | 35 lines of RGDS-specific sway code in `start_azahar.sh` |
| [DraStic](https://www.drastic-ds.com/) | NDS | Single window, `screen_orientation` config | 20 lines + LD_PRELOAD hook (`libdrastouch.c`) |
| [melonDS](https://melonds.kuribo64.net/) | NDS | Separate windows `[w1]`/`[w2]` | Per-window fullscreen + title matching |
| [RetroArch](https://www.retroarch.com/) | Various | Core-dependent (DS cores, vertical MAME) | `vertical-check` script with device-specific stacking |
| Cemu (future) | Wii U | GamePad on second screen | Not yet implemented |

### The Maintenance Problem

Every emulator implements its own sway output stacking with hardcoded
device-specific values. This is the current code pattern, repeated with
variations in every dual-screen emulator:

```bash
# From start_azahar.sh lines 257-294 — RGDS-specific, 640/480/960 hardcoded
# Source: projects/ROCKNIX/packages/emulators/standalone/azahar-sa/scripts/start_azahar.sh

if [ "${AZAHAR_RGDS_DUAL}" = "true" ]; then
    CON="${WLR_CON:-DSI-2}"
    SECOND_CON=$([[ "$CON" = "DSI-1" ]] && echo "DSI-2" || echo "DSI-1")

    ${EMUPERF} /usr/bin/azahar "${1}" &
    AZPID=$!

    # Stack outputs: primary at top, secondary below
    swaymsg output "${CON}" pos 0 0
    swaymsg output "${SECOND_CON}" power on, output "${SECOND_CON}" pos 0 480

    # Allow floating windows to span both panels (640x960 total)
    swaymsg floating_maximum_size 640 x 960

    # Wait for azahar window to appear, then float to span both panels
    for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        if swaymsg '[app_id="org.azahar_emu.Azahar"]' floating enable, fullscreen disable, \
            resize set 640 960, move to output "${CON}", move absolute position 0 0 2>/dev/null; then
            break
        fi
    done

    # Touch calibration for stacked layout
    swaymsg 'input "1046:911:Goodix_Capacitive_TouchScreen" calibration_matrix 1 0 0 0 0.5 0.5'
    wait $AZPID
else
    ${EMUPERF} /usr/bin/azahar "${1}"
fi

# RGDS: restore single-screen
if [ "${AZAHAR_RGDS_DUAL}" = "true" ]; then
    swaymsg floating_maximum_size 0 x 0
    swaymsg output "${SECOND_CON}" power off
    swaymsg output "${CON}" pos 0 0
    swaymsg 'input "1046:911:Goodix_Capacitive_TouchScreen" calibration_matrix 1 0 0 0 1 0'
fi
```

**Problems with this approach:**

1. `640`, `480`, `960` are hardcoded — breaks on non-640x480 panels (AYANEO 1024x600, AYN Thor 1080x1920)
2. `DSI-1`/`DSI-2` connector names hardcoded — breaks with HDMI/DP outputs
3. `1046:911:Goodix_Capacitive_TouchScreen` hardcoded — breaks on devices with different touch controllers
4. 10-iteration wait loop duplicated in every emulator
5. Cleanup (power off, reset touch) duplicated in every emulator
6. Adding a new device = patching every emulator script
7. Adding a new emulator = copying 35+ lines from an existing script

This creates an **O(devices × emulators)** maintenance burden that scales poorly.

### What display-cycle Already Does

The `display-cycle` script (`projects/ROCKNIX/packages/apps/screen-switch/scripts/display-cycle`)
already solves several of these problems for ES panel switching:

```bash
# From display-cycle — runtime output query, no hardcoded values
# Source: projects/ROCKNIX/packages/apps/screen-switch/scripts/display-cycle

OUTPUTS=($(swaymsg -t get_outputs -r | python3 -c "
import json,sys
for o in json.load(sys.stdin):
    if o['active']: print(o['name'])
" 2>/dev/null))

OUT1="${OUTPUTS[0]}"
OUT2="${OUTPUTS[1]}"

PANEL_H=$(swaymsg -t get_outputs -r | python3 -c "
import json,sys
for o in json.load(sys.stdin):
    if o['name'] == '${OUT1}':
        print(o['current_mode']['height']); break
" 2>/dev/null)

restore_stacked() {
    swaymsg "output ${OUT1} power on"
    swaymsg "output ${OUT2} power on"
    swaymsg "output ${OUT1} pos 0 0"
    swaymsg "output ${OUT2} pos 0 ${PANEL_H}"
}
```

But this infrastructure is **not shared** with emulator scripts. Each emulator
re-implements the same logic with hardcoded values instead.

---

## Decision Drivers

1. **New devices shouldn't require emulator patches.** Adding an AYANEO Pocket S2 with different panel sizes should work with existing emulator scripts unchanged.
2. **New emulators shouldn't require device patches.** A Wii U emulator should use the same API as azahar/drastic.
3. **Physical wiring must be abstracted.** Whether outputs are electrically side-by-side (RGDS), true vertical (future clamshell), or external (HDMI/DP), the logical coordinate space is consistent.
4. **Touch calibration follows automatically.** If you stack outputs vertically, touch y-axis calibration adjusts to match the virtual coordinate space.
5. **State management is centralized.** `display-cycle`, `runemu.sh`, and emulator scripts all share the same state file and functions.
6. **Integrated with display-cycle.** Not a separate layer — the same functions that `display-cycle` uses for panel switching are available to emulator scripts.

---

## Considered Options

### Option A: Per-Emulator Bespoke (Status Quo)

Each emulator script contains full sway manipulation code with device-specific conditionals.

- **Pro:** Each emulator has full control, can handle edge cases
- **Con:** O(devices × emulators) maintenance, duplicated code, inconsistent behavior, breaks on new devices

### Option B: Shared Shell Library integrated with display-cycle

Extract common functions from `display-cycle` and emulator scripts into a shared library (`display-core.sh`). Emulators source it and call standard functions. `display-cycle` refactored to use the same library.

- **Pro:** Single implementation, device-independent, tested once, integrated with existing state management
- **Con:** Shell library sourcing adds ~50ms to emulator startup (acceptable)
- **Architecture fit:** Aligns with ROCKNIX `profile.d` / lib pattern (e.g., `099-freqfunctions`)

### Option C: Dedicated Compositor Extension (sway IPC daemon)

Write a sway IPC daemon that monitors window creation events and auto-positions windows based on rules.

- **Pro:** Zero emulator changes needed, handles window creation races cleanly
- **Con:** New daemon = new failure mode, complex state management, overkill for <10 emulators, adds resident memory
- **Architecture fit:** Poor for battery-powered handhelds

### Option D: sway `for_window` Rules Only

Use declarative sway config rules to auto-position windows by `app_id`.

- **Pro:** Declarative, no shell code in emulator scripts
- **Con:** sway rules are window-scoped — can't control output power, output positioning, touch calibration, or floating_maximum_size. Insufficient for the full lifecycle.
- **Architecture fit:** Good supplement but insufficient alone

---

## Decision

**Option B: Shared Shell Library** — integrated with `display-cycle` as a library + CLI pattern.

---

## Detailed Design

### The Coordinate Space Abstraction

sway's [output positioning](https://man.archlinux.org/man/sway-output.5.en)
(`output NAME pos X Y`) creates a **virtual coordinate space** that is
independent of physical wiring. Whether DSI panels are electrically wired
side-by-side (RGDS) or truly vertical (future clamshell), sway positions them
in virtual space according to our commands.

The library leverages this to present a consistent logical layout — but
**panels are NOT assumed to be the same size.** This is critical for:

- **AYN Thor:** 1080x340 (status bar) + 1080x1920 (main screen) — same width, vastly different heights
- **353P + HDMI:** 640x480 (DSI) + 1920x1080 (TV) — different width AND height
- **AYANEO Pocket DS:** 1024x600 each, but DSI-2 needs `transform 270` (rotation) making its effective size 600x1024
- **Retroid Pocket Mini:** 1080x930 (DSI) + 1920x1080 (DP) — different width, offset needed

### The Asymmetric Panel Problem

When panels differ in resolution, naive stacking breaks:

```
WRONG — naively stacking 640x480 + 1920x1080:

┌──────┐
│ DSI  │ 640x480
│640x480│
├──────┤
│      │
│ HDMI │ 1920x1080
│      │  ← left edge doesn't align
│      │  ← sway coordinate space has a 1280px gap on the right
└──────┘

Floating window at 640x1560 would only cover DSI width on the HDMI output.
HDMI content would be cropped to 640px wide.
```

The framework must compute the **bounding box** of both outputs and position
the floating window correctly within it, accounting for:

1. **Width mismatch:** Center narrower panel, or left-align with offset
2. **Height mismatch:** Already handled by separate PANEL_H / PANEL2_H
3. **Scaling:** sway `output scale` affects the logical coordinate space
4. **Transforms:** 90°/270° rotation swaps a panel's effective width/height

### Computed Virtual Canvas

Instead of hardcoded dimensions, the framework computes a **virtual canvas**
that encompasses both outputs:

```
Vertical stack with asymmetric panels:

Given: DSI = 640x480, HDMI = 1920x1080

Canvas width  = max(640, 1920) = 1920
Canvas height = 480 + 1080     = 1560

Output positions (centered alignment):
  DSI:  pos 640  0     (centered: (1920-640)/2 = 640)
  HDMI: pos 0    480   (full width, below DSI)

Window: 1920 x 1560 at (0, 0)

┌────────────────────────────────────┐
│         ┌──────────┐               │
│         │   DSI    │               │  y=0 to 480
│         │ 640x480  │               │
│         └──────────┘               │
├────────────────────────────────────┤
│                                    │
│              HDMI                  │  y=480 to 1560
│           1920x1080                │
│                                    │
└────────────────────────────────────┘
```

Or left-aligned (simpler, matches current RGDS/Thor behavior):

```
Left-aligned stack:

  DSI:  pos 0  0
  HDMI: pos 0  480

Window: max_w x (480+1080) at (0, 0)

┌──────────┐
│   DSI    │
│ 640x480  │
├──────────┴─────────────────────────┐
│                                    │
│              HDMI                  │
│           1920x1080                │
│                                    │
└────────────────────────────────────┘
```

The framework computes `CANVAS_W`, `CANVAS_H`, `OFFSET_X`, `OFFSET_Y` and
uses these for window sizing and positioning.

### Real-World Stacking Geometry (from `vertical-check`)

The existing `vertical-check` script already handles these cases but with
per-device hardcoded values. Here's what the framework must reproduce
generically:

```bash
# Source: projects/ROCKNIX/packages/rocknix/sources/scripts/vertical-check

# AYN Thor: 1080x340 (DSI-1) + 1080x1920 (DSI-2)
# DSI-2 at top (0,0), DSI-1 offset right at (340, 1080)
# Window: 1240 x 2160 — wider than either panel!
swaymsg output DSI-2 pos 0 0, output DSI-1 pos 340 1080
swaymsg resize set 1240 2160, move absolute position 340 0

# RGDS: 640x480 + 640x480 (symmetric)
# Simple vertical stack, no offset
swaymsg output DSI-2 pos 0 0, output DSI-1 pos 0 480
swaymsg resize set 640 960, move absolute position 0 0

# AYANEO Pocket DS: 1024x600 (DSI-1) + 600x1024 (DSI-2 rotated 270°)
# DSI-1 scaled 1.40x, DSI-2 rotated
# Window: 1024 x 1544
swaymsg output DSI-1 scale 1.40
swaymsg output DSI-2 transform 270
swaymsg output DSI-1 pos 0 0, output DSI-2 pos 160 776
swaymsg resize set 1024 1544, move absolute position 160 0

# Retroid Pocket 5: DSI-1 (1080x1920) + DP-1 (1920x1080)
# DP-1 at top, DSI-1 below
swaymsg output DP-1 pos 0 0, output DSI-1 pos 0 1080
swaymsg resize set 1920 2160

# Retroid Pocket Mini: DSI-1 (1080x930) + DP-1 (1920x1080)
# DP-1 at top, DSI-1 offset right at (340, 1080)
swaymsg output DP-1 pos 0 0, output DSI-1 pos 340 1080
swaymsg resize set 1240 2010
```

**The pattern:** each device has a unique `(offset_x, offset_y, canvas_w, canvas_h)`
tuple. The framework must compute this from panel dimensions + any scaling/transforms.

**The emulator sees the same coordinate space regardless of physical wiring.**

### Per-Panel Scaling Modes

A critical requirement is **independent scaling per output**. When a 3DS game
renders at 400x240 (top) + 320x240 (bottom) and the device has 640x480 +
1920x1080 panels, the user must be able to independently choose how each
screen maps to its panel.

**Three scaling modes per panel:**

| Mode | Behavior | Window Size on Panel | Visual |
|------|----------|---------------------|--------|
| **Stretch** | Fill panel, ignore aspect ratio | `PANEL_W x PANEL_H` | Distorted but full coverage |
| **Aspect Fit** | Maintain aspect ratio, letterbox | Computed from content AR | Black bars, correct proportions |
| **Integer Scale** | Nearest integer multiple of native | `native_w * N x native_h * N` where `N = floor(min(PANEL_W/native_w, PANEL_H/native_h))` | Pixel-perfect, may have large borders |

**Per-panel cycling:** The user can independently cycle each panel's scaling
mode via hotkeys (e.g., FN+L1 cycles top panel, FN+R1 cycles bottom panel).

#### Aspect Ratio Calculation

Given content dimensions `(cw, ch)` and panel dimensions `(pw, ph)`:

```
Aspect Fit:
  scale = min(pw/cw, ph/ch)
  fit_w = floor(cw * scale)
  fit_h = floor(ch * scale)
  offset_x = floor((pw - fit_w) / 2)
  offset_y = floor((ph - fit_h) / 2)
  → window: fit_w x fit_h at (panel_origin_x + offset_x, panel_origin_y + offset_y)
  → sway bg fills the letterbox area (already black by default)

Integer Scale:
  N = floor(min(pw/cw, ph/ch))
  int_w = cw * N
  int_h = ch * N
  offset_x = floor((pw - int_w) / 2)
  offset_y = floor((ph - int_h) / 2)
```

#### Implementation: Two Window Models

**Model A: Single window spanning both panels** (azahar, drastic)

The emulator controls internal layout. Per-panel scaling is configured via
emulator-specific settings (azahar: `screen_top_stretch`, drastic:
`screen_orientation`). The framework provides the canvas dimensions and the
emulator's own renderer handles aspect ratio within each region.

For this model, the framework exposes:
- `DISPLAY_TOP_W`, `DISPLAY_TOP_H` — logical area available for top content
- `DISPLAY_BOTTOM_W`, `DISPLAY_BOTTOM_H` — logical area available for bottom content
- Emulator config scripts translate these into their internal layout parameters

**Model B: Separate windows per panel** (melonDS, future Cemu)

Each window is independently positioned and sized on its output. Per-panel
scaling is directly controlled by the framework:

```bash
# Stretch: fill panel
display_window_stretch 'title="\[w1\]"' top
display_window_stretch 'title="\[w2\]"' bottom

# Aspect fit: letterbox on panel
display_window_fit 'title="\[w1\]"' top 400 240   # 3DS top screen native
display_window_fit 'title="\[w2\]"' bottom 320 240 # 3DS bottom screen native

# Integer scale: pixel-perfect
display_window_integer 'title="\[w1\]"' top 400 240
```

#### Per-Panel Scale Mode API

```bash
# State: per-output scaling mode persisted in /run/rocknix/
# /run/rocknix/scale_mode_top    = stretch | fit | integer
# /run/rocknix/scale_mode_bottom = stretch | fit | integer

# Set scaling mode for a specific panel position
# Usage: display_set_scale_mode top|bottom stretch|fit|integer [content_w content_h]
display_set_scale_mode() {
    local position="$1" mode="$2"
    local content_w="${3:-0}" content_h="${4:-0}"
    _display_init

    local panel_w panel_h panel_x panel_y output
    if [ "$position" = "top" ]; then
        panel_w="$PANEL_W"; panel_h="$PANEL_H"
        panel_x="$VSTACK_PRI_X"; panel_y=0
        output="$DISPLAY_TOP"
    else
        panel_w="$PANEL2_W"; panel_h="$PANEL2_H"
        panel_x="$VSTACK_SEC_X"; panel_y="$PANEL_H"
        output="$DISPLAY_BOTTOM"
    fi

    printf '%s' "$mode" > "${DISPLAY_STATE_DIR}/scale_mode_${position}"

    # Return computed window geometry for this mode
    case "$mode" in
        stretch)
            SCALE_W="$panel_w"; SCALE_H="$panel_h"
            SCALE_X="$panel_x"; SCALE_Y="$panel_y"
            ;;
        fit)
            if [ "$content_w" -gt 0 ] && [ "$content_h" -gt 0 ]; then
                eval "$(awk "BEGIN {
                    sw = ${panel_w} / ${content_w}
                    sh = ${panel_h} / ${content_h}
                    s = (sw < sh) ? sw : sh
                    w = int(${content_w} * s)
                    h = int(${content_h} * s)
                    ox = int((${panel_w} - w) / 2)
                    oy = int((${panel_h} - h) / 2)
                    printf \"SCALE_W=%d SCALE_H=%d SCALE_X=%d SCALE_Y=%d\", w, h, ${panel_x}+ox, ${panel_y}+oy
                }")"
            else
                SCALE_W="$panel_w"; SCALE_H="$panel_h"
                SCALE_X="$panel_x"; SCALE_Y="$panel_y"
            fi
            ;;
        integer)
            if [ "$content_w" -gt 0 ] && [ "$content_h" -gt 0 ]; then
                eval "$(awk "BEGIN {
                    nx = int(${panel_w} / ${content_w})
                    ny = int(${panel_h} / ${content_h})
                    n = (nx < ny) ? nx : ny
                    if (n < 1) n = 1
                    w = ${content_w} * n
                    h = ${content_h} * n
                    ox = int((${panel_w} - w) / 2)
                    oy = int((${panel_h} - h) / 2)
                    printf \"SCALE_W=%d SCALE_H=%d SCALE_X=%d SCALE_Y=%d\", w, h, ${panel_x}+ox, ${panel_y}+oy
                }")"
            else
                SCALE_W="$panel_w"; SCALE_H="$panel_h"
                SCALE_X="$panel_x"; SCALE_Y="$panel_y"
            fi
            ;;
    esac
}

# Apply computed scale to a window on a specific panel
# Usage: display_apply_scale 'title="\[w1\]"' top
display_apply_scale() {
    local criteria="$1" position="$2"
    swaymsg "[$criteria]" floating enable, resize set "$SCALE_W" "$SCALE_H", \
        move absolute position "$SCALE_X" "$SCALE_Y" 2>/dev/null
}

# Cycle scaling mode for a panel and re-apply
# Usage: display_cycle_scale top|bottom [content_w content_h]
display_cycle_scale() {
    local position="$1"
    local content_w="${2:-0}" content_h="${3:-0}"
    local current
    current=$(cat "${DISPLAY_STATE_DIR}/scale_mode_${position}" 2>/dev/null || echo "stretch")

    local next
    case "$current" in
        stretch)  next="fit" ;;
        fit)      next="integer" ;;
        integer)  next="stretch" ;;
        *)        next="stretch" ;;
    esac

    display_set_scale_mode "$position" "$next" "$content_w" "$content_h"
}
```

#### Scaling Mode Cycling Hotkeys

Added to `display-cycle` CLI:

```bash
display-cycle scale-top [content_w content_h]     # Cycle top panel: stretch → fit → integer
display-cycle scale-bottom [content_w content_h]  # Cycle bottom panel independently
```

Bound to hotkeys via `input_sense` or sway bindsym:
- FN + L1: `display-cycle scale-top`
- FN + R1: `display-cycle scale-bottom`

#### Concrete Example: 3DS on 353P + HDMI

```
Device: 353P (DSI 640x480) + HDMI TV (1920x1080)
Game: 3DS (top 400x240, bottom 320x240)

Top panel (DSI 640x480), content 400x240:
  stretch:  640x480 at (0, 0)           — fills panel, 1.6:1 → 1.33:1 distortion
  fit:      640x384 at (0, 48)          — letterboxed, 48px bars top+bottom
  integer:  400x240 at (120, 120)       — 1x scale, large borders

Bottom panel (HDMI 1920x1080), content 320x240:
  stretch:  1920x1080 at (0, 480)       — fills TV, massive distortion
  fit:      1440x1080 at (240, 480)     — letterboxed, 240px bars left+right
  integer:  1280x960 at (320, 540)      — 4x scale, small borders

User can independently set: top=fit, bottom=integer (pixel-perfect on big TV)
```

### The `floating_maximum_size` Problem and Resolution

**Problem:** sway's `floating_maximum_size` is a **global** setting — it
applies to ALL floating windows, not per-window. The current approach sets it
to `CANVAS_W x CANVAS_H` to allow a single window to span both outputs. But
this means:

1. A separate-window emulator (melonDS `[w1]` + `[w2]`) can't have windows
   sized independently — both are constrained by the same global maximum
2. Per-panel scaling (stretch vs fit vs integer) requires different window sizes
   on each panel, which is impossible if the global max is set to the spanning size
3. Any other floating window (OSD, keyboard, menu) is affected too

**This is a fundamental architectural constraint of sway's tiling model.**

#### Resolution: Two Strategies, No `floating_maximum_size`

The framework MUST NOT use `floating_maximum_size`. Instead, it uses two
strategies depending on the emulator's window model:

**Strategy 1: Per-Output Fullscreen (separate windows)**

For emulators that create separate windows per screen (melonDS, future Cemu):

```bash
# Each window is moved to its output and fullscreened independently.
# No floating needed. No floating_maximum_size needed.
# Per-panel scaling handled by the emulator's own renderer filling the fullscreen.

swaymsg '[title="\[w1\].*melonDS"]' move to output "$DISPLAY_TOP", fullscreen enable
swaymsg '[title="\[w2\].*melonDS"]' move to output "$DISPLAY_BOTTOM", fullscreen enable
```

For aspect-fit on a specific panel, use floating WITHOUT global max:

```bash
# Float window, resize to aspect-fit dimensions, center on output
# sway default floating_maximum_size is 0x0 = unlimited
swaymsg '[title="\[w1\]"]' move to output "$DISPLAY_TOP", \
    floating enable, resize set $FIT_W $FIT_H, \
    move position $CENTER_X $CENTER_Y
```

**No global `floating_maximum_size` needed.** Each window is independently
sized and positioned on its own output. The default `0 x 0` (unlimited) allows
any size.

**Strategy 2: Output-Scoped Rendering (single spanning window)**

For emulators that render both screens in a single window (azahar, drastic),
the emulator's **internal layout engine** handles per-screen sizing. The
framework's job is to:

1. Stack outputs in the virtual coordinate space
2. Tell the emulator the available canvas dimensions
3. Let the emulator handle how it draws top vs bottom within that canvas

Instead of floating a window across both outputs, use **`fullscreen global`**:

```bash
# fullscreen global: window spans ALL outputs, filling the combined virtual canvas.
# sway composites the window across output boundaries automatically.
# No floating_maximum_size needed.

swaymsg '[app_id="org.azahar_emu.Azahar"]' fullscreen global
```

`fullscreen global` fills the entire sway virtual coordinate space (all
outputs combined). The emulator renders at the canvas resolution and sway
clips/composites each output's portion correctly.

**Trade-off:** `fullscreen global` doesn't support per-pixel window
positioning (it fills everything). If the canvas has asymmetric centering
offsets, the emulator must handle content positioning internally. For most
dual-screen emulators (azahar custom layout, drastic screen_orientation),
they already do this.

**Strategy 3: Intermediate Virtual Output (advanced)**

For cases where neither Strategy 1 nor 2 is sufficient (e.g., asymmetric
panels where the emulator can't handle the offset), create a HEADLESS
virtual output at the exact desired size:

```bash
# Create a virtual output matching the desired canvas
swaymsg "output HEADLESS-1 mode ${CANVAS_W}x${CANVAS_H}, pos 0 0"

# Emulator renders to the virtual output (fullscreen)
swaymsg '[app_id="emulator"]' move to output HEADLESS-1, fullscreen enable

# wl-mirror projects regions of the virtual output to each physical panel
# Top half → DISPLAY_TOP (aspect fit or stretch)
wl-mirror -s fit --region 0,0,${CANVAS_W},${PANEL_H} \
    --fullscreen-output "$DISPLAY_TOP" HEADLESS-1 &

# Bottom half → DISPLAY_BOTTOM (independent scaling mode)
wl-mirror -s stretch --region 0,${PANEL_H},${CANVAS_W},${PANEL2_H} \
    --fullscreen-output "$DISPLAY_BOTTOM" HEADLESS-1 &
```

This is the most flexible approach — each physical output gets an
independently-scaled projection of a region of the virtual canvas. But it
requires wl-mirror and adds GPU overhead (extra composition pass).

**Note:** wl-mirror's `--region` cropping depends on `wp_viewporter` protocol
support, which is available on Mesa (panfrost/freedreno/turnip) but NOT on
libmali. For libmali devices (RK3566 with Mali blob), Strategy 3 falls back
to Strategy 1 or 2.

#### Strategy Selection Logic

```bash
display_select_strategy() {
    local window_model="$1"  # "spanning" or "separate"
    _display_init

    if [ "$window_model" = "separate" ]; then
        # Strategy 1: per-output fullscreen, no floating needed
        echo "per_output_fullscreen"
    elif [ "$PANEL_W" -eq "$PANEL2_W" ] && [ "$PANEL_H" -eq "$PANEL2_H" ]; then
        # Symmetric panels: fullscreen global works perfectly
        echo "fullscreen_global"
    elif command -v wl-mirror >/dev/null && [ "$(/usr/bin/gpudriver)" != "libmali" ]; then
        # Asymmetric + Mesa: virtual output + wl-mirror projection
        echo "virtual_output_mirror"
    else
        # Asymmetric + libmali: fullscreen global (emulator handles internal layout)
        echo "fullscreen_global"
    fi
}
```

#### Updated API (no `floating_maximum_size` anywhere)

```bash
# Spanning window: use fullscreen global
display_span_window() {
    local criteria="$1"
    _display_init
    swaymsg "[$criteria]" fullscreen global 2>/dev/null
}

# Separate windows: per-output fullscreen
display_fullscreen_split() {
    local criteria_top="$1" criteria_bottom="$2"
    _display_init
    swaymsg "[$criteria_top]" move to output "$DISPLAY_TOP", fullscreen enable 2>/dev/null
    swaymsg "[$criteria_bottom]" move to output "$DISPLAY_BOTTOM", fullscreen enable 2>/dev/null
}

# Per-panel aspect fit (separate window model only)
display_window_fit() {
    local criteria="$1" position="$2"
    local content_w="$3" content_h="$4"
    display_set_scale_mode "$position" "fit" "$content_w" "$content_h"
    # SCALE_W, SCALE_H, SCALE_X, SCALE_Y now set
    swaymsg "[$criteria]" floating enable, border none, \
        resize set "$SCALE_W" "$SCALE_H", \
        move absolute position "$SCALE_X" "$SCALE_Y" 2>/dev/null
}

# Per-panel stretch (separate window model only)
display_window_stretch() {
    local criteria="$1" position="$2"
    local output
    if [ "$position" = "top" ]; then output="$DISPLAY_TOP"; else output="$DISPLAY_BOTTOM"; fi
    swaymsg "[$criteria]" move to output "$output", fullscreen enable 2>/dev/null
}
```

### sway IPC Data Sources

All dimensions are queried at runtime via [sway IPC](https://man.archlinux.org/man/sway-ipc.7.en):

```bash
# GET_OUTPUTS (message type 3) — returns JSON array
swaymsg -t get_outputs -r
# Each output has: name, active, power, current_mode.{width,height,refresh}, rect.{x,y,width,height}

# GET_INPUTS (message type 100) — returns JSON array
swaymsg -t get_inputs -r
# Each input has: identifier, name, type (touchpad/touch/keyboard/pointer)
```

### Architecture: Library + CLI

```
/usr/lib/rocknix-display/display-core.sh   ← Shared functions (sourced by emulators + display-cycle)
/usr/bin/display-cycle                      ← CLI tool (thin wrapper, sources display-core.sh)
```

### Concrete Asymmetric Panel Calculations

The framework computes stacking geometry at runtime. Here are the computed
values for every current multi-output device:

| Device | Panel 1 (WxH) | Panel 2 (WxH) | Canvas WxH | Pri X | Sec X | Sec Y | Touch Scale Y |
|--------|--------------|--------------|------------|-------|-------|-------|--------------|
| **RGDS** | 640x480 | 640x480 | 640x960 | 0 | 0 | 480 | 0.5000 |
| **AYANEO PDS** | 1024x600 | 600x1024¹ | 1024x1624 | 0 | 212² | 600 | 0.3695 |
| **AYN Thor** | 1080x340 | 1080x1920 | 1080x2260 | 0 | 0 | 340 | 0.1504 |
| **Retroid P5** | 1080x1920³ | 1920x1080 | 1920x3000 | 420 | 0 | 1920 | 0.6400 |
| **Retroid Mini** | 1080x930³ | 1920x1080 | 1920x2010 | 420 | 0 | 930 | 0.4627 |
| **353P + HDMI** | 640x480 | 1920x1080 | 1920x1560 | 640 | 0 | 480 | 0.3077 |
| **353P + 1080p TV** | 640x480 | 1920x1080 | 1920x1560 | 640 | 0 | 480 | 0.3077 |

¹ AYANEO PDS DSI-2 is 1024x600 with `transform 270` → effective 600x1024 in sway coordinates
² Centered: (1024 - 600) / 2 = 212
³ Retroid DSI is portrait; DP-1 is landscape at top

**All values computed from `swaymsg -t get_outputs` at runtime — zero hardcoding.**

### display-core.sh — Full API

```bash
#!/bin/bash
# /usr/lib/rocknix-display/display-core.sh
# Unified multi-output display management for ROCKNIX
#
# Architecture: sourced by emulator start scripts and display-cycle CLI
# Dependencies: swaymsg, python3 (for JSON parsing, already in display-cycle)

# --- State files (shared with display-cycle) ---
DISPLAY_STATE_DIR="/run/rocknix"
DISPLAY_STATE_FILE="${DISPLAY_STATE_DIR}/display_state"
DISPLAY_ACTIVE_FILE="${DISPLAY_STATE_DIR}/active_output"
DISPLAY_PRE_GAME_FILE="${DISPLAY_STATE_DIR}/display_pre_game"

# --- Initialization (auto-called on source) ---

_display_init() {
    [ -n "${_DISPLAY_INITED:-}" ] && return
    _DISPLAY_INITED=1
    mkdir -p "$DISPLAY_STATE_DIR"

    SWAYSOCK="${SWAYSOCK:-/run/0-runtime-dir/sway-ipc.0.sock}"
    export SWAYSOCK

    # Query sway for active outputs
    local outputs_json
    outputs_json=$(swaymsg -t get_outputs -r 2>/dev/null) || return

    # Parse output names and dimensions via python3 (precedent: display-cycle)
    # CRITICAL: use rect (post-transform, post-scale) not current_mode (hardware pixels)
    # rect gives the logical size in sway's virtual coordinate space, which is
    # what we need for positioning. A 1024x600 panel with transform=270 has
    # rect 600x1024 (swapped). A panel with scale=1.4 has rect scaled down.
    eval "$(printf '%s' "$outputs_json" | python3 -c "
import json, sys
outs = [o for o in json.load(sys.stdin) if o.get('active')]
if not outs: sys.exit(0)
pri = outs[0]
# rect = post-transform, post-scale logical size in virtual coordinate space
r = pri.get('rect', pri.get('current_mode', {}))
print(f'DISPLAY_PRIMARY=\"{pri[\"name\"]}\"')
print(f'PANEL_W={r.get(\"width\", pri[\"current_mode\"][\"width\"])}')
print(f'PANEL_H={r.get(\"height\", pri[\"current_mode\"][\"height\"])}')
if len(outs) > 1:
    sec = outs[1]
    r2 = sec.get('rect', sec.get('current_mode', {}))
    print(f'DISPLAY_SECONDARY=\"{sec[\"name\"]}\"')
    print(f'PANEL2_W={r2.get(\"width\", sec[\"current_mode\"][\"width\"])}')
    print(f'PANEL2_H={r2.get(\"height\", sec[\"current_mode\"][\"height\"])}')
" 2>/dev/null)"

    # Defaults if query failed
    DISPLAY_PRIMARY="${DISPLAY_PRIMARY:-${WLR_CON:-DSI-1}}"
    DISPLAY_SECONDARY="${DISPLAY_SECONDARY:-}"
    PANEL_W="${PANEL_W:-640}"
    PANEL_H="${PANEL_H:-480}"
    PANEL2_W="${PANEL2_W:-$PANEL_W}"
    PANEL2_H="${PANEL2_H:-$PANEL_H}"

    # Logical aliases (default: vertical stacking, primary on top)
    DISPLAY_TOP="$DISPLAY_PRIMARY"
    DISPLAY_BOTTOM="$DISPLAY_SECONDARY"
    DISPLAY_LEFT="$DISPLAY_PRIMARY"
    DISPLAY_RIGHT="$DISPLAY_SECONDARY"

    # Asymmetric panel geometry — computed canvas for stacking
    # Vertical stack: wider panel determines canvas width, offset centers the narrower
    if [ "$PANEL_W" -ge "$PANEL2_W" ]; then
        CANVAS_W="$PANEL_W"
        VSTACK_OFFSET_X=$(( (PANEL_W - PANEL2_W) / 2 ))
        VSTACK_PRI_X=0
        VSTACK_SEC_X="$VSTACK_OFFSET_X"
    else
        CANVAS_W="$PANEL2_W"
        VSTACK_OFFSET_X=$(( (PANEL2_W - PANEL_W) / 2 ))
        VSTACK_PRI_X="$VSTACK_OFFSET_X"
        VSTACK_SEC_X=0
    fi
    CANVAS_H=$((PANEL_H + PANEL2_H))

    # Horizontal stack: taller panel determines canvas height
    if [ "$PANEL_H" -ge "$PANEL2_H" ]; then
        CANVAS_H_HORIZ="$PANEL_H"
    else
        CANVAS_H_HORIZ="$PANEL2_H"
    fi
    CANVAS_W_HORIZ=$((PANEL_W + PANEL2_W))

    # Legacy aliases (for simple symmetric cases)
    COMBINED_H="$CANVAS_H"
    COMBINED_W="$CANVAS_W_HORIZ"

    # Auto-detect touch device
    TOUCH_DEVICE=""
    local inputs_json
    inputs_json=$(swaymsg -t get_inputs -r 2>/dev/null) || true
    if [ -n "$inputs_json" ]; then
        TOUCH_DEVICE=$(printf '%s' "$inputs_json" | python3 -c "
import json, sys
for i in json.load(sys.stdin):
    if i.get('type') == 'touch':
        print(i['identifier']); break
" 2>/dev/null)
    fi
}

# --- Predicates ---

display_is_dual() {
    _display_init
    [ -n "$DISPLAY_SECONDARY" ]
}

display_get_primary()   { _display_init; printf '%s' "$DISPLAY_PRIMARY"; }
display_get_secondary() { _display_init; printf '%s' "$DISPLAY_SECONDARY"; }

# --- Layout Actions ---

# Stack outputs vertically: TOP at (offset,0), BOTTOM at (offset, PANEL_H)
# Handles asymmetric panels by centering the narrower output.
# E.g., 640x480 + 1920x1080: DSI at (640,0), HDMI at (0,480), canvas 1920x1560
# E.g., 640x480 + 640x480:  DSI-1 at (0,0), DSI-2 at (0,480), canvas 640x960
display_stack_vertical() {
    _display_init
    swaymsg "output ${DISPLAY_PRIMARY} power on" 2>/dev/null
    swaymsg "output ${DISPLAY_SECONDARY} power on" 2>/dev/null
    swaymsg "output ${DISPLAY_PRIMARY} pos ${VSTACK_PRI_X} 0" 2>/dev/null
    swaymsg "output ${DISPLAY_SECONDARY} pos ${VSTACK_SEC_X} ${PANEL_H}" 2>/dev/null
    # NOTE: no floating_maximum_size — it's global and breaks per-window sizing.
    # Window sizing is handled by display_span_window (fullscreen global) or
    # display_window_fit/stretch (per-output positioning).
}

# Stack outputs horizontally: LEFT at (0,offset), RIGHT at (PANEL_W, offset)
# Handles asymmetric panels by centering the shorter output vertically.
display_stack_horizontal() {
    _display_init
    local hstack_pri_y=0 hstack_sec_y=0
    if [ "$PANEL_H" -ge "$PANEL2_H" ]; then
        hstack_sec_y=$(( (PANEL_H - PANEL2_H) / 2 ))
    else
        hstack_pri_y=$(( (PANEL2_H - PANEL_H) / 2 ))
    fi
    swaymsg "output ${DISPLAY_PRIMARY} power on" 2>/dev/null
    swaymsg "output ${DISPLAY_SECONDARY} power on" 2>/dev/null
    swaymsg "output ${DISPLAY_PRIMARY} pos 0 ${hstack_pri_y}" 2>/dev/null
    swaymsg "output ${DISPLAY_SECONDARY} pos ${PANEL_W} ${hstack_sec_y}" 2>/dev/null
}

# --- Window Management ---

# Wait for a window matching CRITERIA to appear (polls sway)
# Usage: display_wait_window 'app_id="drastic"' [timeout_seconds]
display_wait_window() {
    local criteria="$1" timeout="${2:-10}" i=0
    while [ "$i" -lt "$timeout" ]; do
        sleep 1; i=$((i + 1))
        # swaymsg returns success if criteria matches an existing window
        if swaymsg "[$criteria]" nop 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# Float window and resize to span both outputs (vertical stack)
# Positions at (min_offset_x, 0) with size CANVAS_W x CANVAS_H
# For symmetric panels: (0,0) 640x960. For asymmetric: computed offset.
# Usage: display_span_window 'app_id="drastic"'
display_span_window() {
    local criteria="$1"
    _display_init
    # Window origin is at (0,0) of the virtual canvas — the leftmost edge
    # of whichever output starts at x=0
    local win_x=0
    [ "$VSTACK_PRI_X" -gt 0 ] && win_x="$VSTACK_PRI_X"
    swaymsg "[$criteria]" floating enable, fullscreen disable, \
        resize set "$CANVAS_W" "$CANVAS_H", \
        move to output "$DISPLAY_PRIMARY", \
        move absolute position "$win_x" 0 2>/dev/null
}

# Float window and resize to span both outputs (horizontal stack)
display_span_window_horizontal() {
    local criteria="$1"
    _display_init
    swaymsg "[$criteria]" floating enable, fullscreen disable, \
        resize set "$CANVAS_W_HORIZ" "$CANVAS_H_HORIZ", \
        move to output "$DISPLAY_PRIMARY", \
        move absolute position 0 0 2>/dev/null
}

# melonDS-style: fullscreen each window on its own output
# Usage: display_fullscreen_split 'title="\[w1\]"' 'title="\[w2\]"'
display_fullscreen_split() {
    local criteria_top="$1" criteria_bottom="$2"
    _display_init
    swaymsg "[$criteria_top]" move to output "$DISPLAY_PRIMARY", fullscreen enable 2>/dev/null
    swaymsg "[$criteria_bottom]" move to output "$DISPLAY_SECONDARY", fullscreen enable 2>/dev/null
}

# --- Touch Calibration ---

# Calibrate touch for vertical stacking
# The calibration matrix maps physical touch coordinates to the virtual canvas.
# For symmetric panels (640+640=1280): scale_y=0.5, offset_y=0.5
# For asymmetric (480+1080=1560): scale_y=480/1560≈0.308, offset_y=0.308
# The touch device covers the PRIMARY panel, so:
#   scale_y = PANEL_H / CANVAS_H
#   offset_y = scale_y (touch starts at y=0 which maps to top of primary)
display_calibrate_touch_stacked() {
    _display_init
    [ -z "$TOUCH_DEVICE" ] && return
    # Compute scale factor: primary panel height / total canvas height
    # Use awk for floating point (POSIX-compatible, no bc dependency)
    local scale_y offset_y
    scale_y=$(awk "BEGIN { printf \"%.4f\", ${PANEL_H} / ${CANVAS_H} }")
    offset_y="$scale_y"
    swaymsg "input \"$TOUCH_DEVICE\" calibration_matrix 1 0 0 0 ${scale_y} ${offset_y}" 2>/dev/null
}

# Reset touch to identity matrix
display_calibrate_touch_reset() {
    _display_init
    [ -n "$TOUCH_DEVICE" ] && \
        swaymsg "input \"$TOUCH_DEVICE\" calibration_matrix 1 0 0 0 1 0" 2>/dev/null
}

# Map touch input to a specific output
display_map_touch_to() {
    local output="$1"
    _display_init
    [ -n "$TOUCH_DEVICE" ] && \
        swaymsg "input \"$TOUCH_DEVICE\" map_to_output $output" 2>/dev/null
}

# --- Lifecycle (Pre/Post Game) ---

# Save current display state before game launch
display_save_state() {
    _display_init
    local state
    state=$(cat "$DISPLAY_STATE_FILE" 2>/dev/null || echo "normal_top")
    printf '%s' "$state" > "$DISPLAY_PRE_GAME_FILE"
}

# Restore display state after game exit
display_restore() {
    _display_init
    swaymsg "output ${DISPLAY_SECONDARY} power off" 2>/dev/null
    swaymsg "output ${DISPLAY_PRIMARY} pos 0 0" 2>/dev/null
    display_calibrate_touch_reset

    # Restore pre-game display-cycle state if saved
    if [ -f "$DISPLAY_PRE_GAME_FILE" ]; then
        local pre_state
        read -r pre_state < "$DISPLAY_PRE_GAME_FILE"
        rm -f "$DISPLAY_PRE_GAME_FILE"
        printf '%s' "$pre_state" > "$DISPLAY_STATE_FILE"
    fi
}

# WLR_CON management (shared with display-cycle)
display_update_active() {
    local new_con="$1"
    sed -i "s|^WLR_CON=.*|WLR_CON=${new_con}|" /storage/.config/profile.d/095-sway 2>/dev/null
    export WLR_CON="${new_con}"
    printf '%s' "${new_con}" > "$DISPLAY_ACTIVE_FILE"
}

# Auto-init on source
_display_init
```

### Emulator Integration Pattern

**Before** (azahar — 35 lines of RGDS-specific code):

```bash
# Current: projects/ROCKNIX/packages/emulators/standalone/azahar-sa/scripts/start_azahar.sh
# Lines 257-294 — ONLY works on RGDS, hardcoded 640/480/960

if [ "${AZAHAR_RGDS_DUAL}" = "true" ]; then
    CON="${WLR_CON:-DSI-2}"
    SECOND_CON=$([[ "$CON" = "DSI-1" ]] && echo "DSI-2" || echo "DSI-1")
    ${EMUPERF} /usr/bin/azahar "${1}" &
    AZPID=$!
    swaymsg output "${CON}" pos 0 0
    swaymsg output "${SECOND_CON}" power on, output "${SECOND_CON}" pos 0 480
    swaymsg floating_maximum_size 640 x 960
    for i in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        if swaymsg '[app_id="org.azahar_emu.Azahar"]' floating enable, fullscreen disable, \
            resize set 640 960, move to output "${CON}", move absolute position 0 0 2>/dev/null; then
            break
        fi
    done
    swaymsg 'input "1046:911:Goodix_Capacitive_TouchScreen" calibration_matrix 1 0 0 0 0.5 0.5'
    wait $AZPID
    swaymsg floating_maximum_size 0 x 0
    swaymsg output "${SECOND_CON}" power off
    swaymsg output "${CON}" pos 0 0
    swaymsg 'input "1046:911:Goodix_Capacitive_TouchScreen" calibration_matrix 1 0 0 0 1 0'
else
    ${EMUPERF} /usr/bin/azahar "${1}"
fi
```

**After** (8 lines, works on ALL dual-screen devices):

```bash
# Proposed: generic dual-screen azahar launch — works on ALL devices
. /usr/lib/rocknix-display/display-core.sh

if display_is_dual; then
    display_save_state
    display_stack_vertical
    # Export canvas dimensions for emulator config scripts
    export DISPLAY_CANVAS_W="$CANVAS_W" DISPLAY_CANVAS_H="$CANVAS_H"
fi

${EMUPERF} /usr/bin/azahar "${1}" &
AZPID=$!

if display_is_dual; then
    display_wait_window 'app_id="org.azahar_emu.Azahar"' 10
    display_span_window 'app_id="org.azahar_emu.Azahar"'  # fullscreen global
    display_calibrate_touch_stacked
fi

wait $AZPID
display_is_dual && display_restore
```

**Zero device-specific code.** Works on RGDS (640x480 DSI), AYANEO Pocket DS
(1024x600 DSI), 353P+HDMI (mixed resolution), and any future device — all
dimensions queried at runtime via sway IPC.

### display-cycle Refactoring

`display-cycle` becomes a thin CLI wrapper with new `scale-*` commands:

```bash
#!/bin/bash
# /usr/bin/display-cycle — panel cycling CLI
. /usr/lib/rocknix-display/display-core.sh

display_is_dual || exit 0

case "$1" in
    move)         display_cycle_move ;;
    off)          display_cycle_power ;;
    mirror)       display_cycle_mirror ;;
    scale-top)    display_cycle_scale top "$2" "$3" ;;     # cycle top: stretch → fit → integer
    scale-bottom) display_cycle_scale bottom "$2" "$3" ;;  # cycle bottom independently
esac
```

Per-panel scale state persisted in `/run/rocknix/scale_mode_{top,bottom}`.

Content dimensions (for fit/integer calculation) passed as arguments or pre-set
by emulator start scripts via environment variables:
- `DISPLAY_CONTENT_TOP_W`, `DISPLAY_CONTENT_TOP_H`
- `DISPLAY_CONTENT_BOTTOM_W`, `DISPLAY_CONTENT_BOTTOM_H`

Hotkeys: FN+L1 → `display-cycle scale-top`, FN+R1 → `display-cycle scale-bottom`
```

Same state file (`/run/rocknix/display_state`), same functions, no duplication.

---

## Source References

### Current Implementation Files

| File | Purpose | Lines of device-specific code |
|------|---------|------------------------------|
| [`start_azahar.sh`](projects/ROCKNIX/packages/emulators/standalone/azahar-sa/scripts/start_azahar.sh) | 3DS dual-screen (RGDS only) | ~35 lines |
| [`start_drastic.sh`](projects/ROCKNIX/packages/emulators/standalone/drastic-sa/scripts/start_drastic.sh) | NDS dual-screen (RGDS only) | ~25 lines |
| [`start_melonds.sh`](projects/ROCKNIX/packages/emulators/standalone/melonds-sa/scripts/start_melonds.sh) | NDS separate windows | ~20 lines |
| [`vertical-check`](projects/ROCKNIX/packages/rocknix/sources/scripts/vertical-check) | RetroArch vertical games | ~40 lines (4 device branches) |
| [`display-cycle`](projects/ROCKNIX/packages/apps/screen-switch/scripts/display-cycle) | Panel switching CLI | ~100 lines (shared infra exists here) |
| [`111-sway-init`](projects/ROCKNIX/packages/wayland/compositor/sway/autostart/111-sway-init) | Boot-time output config | ~50 lines per-device |
| [`libdrastouch.c`](projects/ROCKNIX/packages/emulators/standalone/drastic-sa/sources/libdrastouch.c) | DraStic C-level window hook | LD_PRELOAD, `system("swaymsg ...")` |
| [`runemu.sh`](projects/ROCKNIX/packages/rocknix/sources/scripts/runemu.sh) | Emulator launch wrapper | Pre/post display state save/restore |

### External Documentation

| Resource | URL |
|----------|-----|
| sway output configuration | https://man.archlinux.org/man/sway-output.5.en |
| sway IPC protocol (GET_OUTPUTS, GET_INPUTS) | https://man.archlinux.org/man/sway-ipc.7.en |
| sway input configuration (calibration_matrix) | https://man.archlinux.org/man/sway-input.5.en |
| wlroots output management | https://gitlab.freedesktop.org/wlroots/wlroots |
| PR #2473 (DraStic dual-screen fix) | https://github.com/ROCKNIX/distribution/pull/2473 |

### Environment Variables (set by ROCKNIX boot scripts)

| Variable | Source | Description |
|----------|--------|-------------|
| `WLR_CON` | `095-sway` profile | Active output name (updated by display-cycle) |
| `DEVICE_HAS_DUAL_SCREEN` | `080-dual_screen_mode` | `true` if 2 connectors detected |
| `QUIRK_DEVICE` | `rocknix-info` / device tree | Device model string |
| `SWAYSOCK` | sway runtime | IPC socket path |

---

## Consequences

### Positive

- **O(1) device additions:** New devices work with existing emulator scripts — dimensions queried at runtime
- **O(1) emulator additions:** New emulators need ~8 lines of display code instead of ~35
- **Consistent coordinate space:** Emulators always see the same logical layout regardless of physical wiring
- **Touch calibration automatic:** Correct for any panel geometry, auto-detected input device
- **Centralized state:** `display-cycle` and emulators share state — no conflicts on game exit
- **HDMI becomes natural:** 353P+HDMI treated as dual-screen automatically

### Negative

- Shell library sourcing adds ~50ms to emulator startup (acceptable — emulators take seconds to load)
- Python3 one-liner for sway JSON parsing (already present in display-cycle, not a new dependency)
- Migration effort: 4 emulator scripts + vertical-check + display-cycle need updating
- Some emulators (Wii U) may need asymmetric panel sizing not covered by equal-split API

### Risks

- **Output transforms (rotation):** AYANEO Pocket DS rotates DSI-2 by 270°, which swaps width/height in sway's coordinate space. The framework must query `rect` (post-transform size in virtual space) from GET_OUTPUTS, not `current_mode` (pre-transform hardware pixels). sway IPC provides both.
- **Scaling factors:** sway `output scale 1.40` changes the logical coordinate space. The `rect` from GET_OUTPUTS is post-scale, so the framework should use `rect.width`/`rect.height` for canvas calculations instead of `current_mode`.
- **Touch with multiple inputs:** Devices with 2 touch controllers (AYANEO Pocket DS: Goodix + generic_ft5x06) need per-output mapping. Framework auto-detects first touch input; devices needing explicit mapping can override via `ROCKNIX_TOUCH_DEVICE` env var in their quirk profile.
- **Very large resolution differences:** 640x480 + 4K HDMI creates a massive canvas. Emulators may not render efficiently at 3840x2640. Use `output scale` to bring the HDMI output's logical size closer to the DSI panel before stacking.

---

## Implementation Phases

| Phase | Scope | Files |
|-------|-------|-------|
| 1 | Create `display-core.sh`, refactor `display-cycle`, migrate `start_azahar.sh` + `start_drastic.sh` | 4 files |
| 2 | Migrate `start_melonds.sh` + `vertical-check` | 2 files |
| 3 | HDMI hotplug integration (353P+HDMI = automatic dual-screen) | 1 file |
| 4 | Merge PR #2473 `libdrastouch.c` improvements alongside framework | 2 files |

---

## Related ADRs

- [ADR: schedutil boost frequency selection fix](memory/adr-schedutil-boost-fix.md) — unrelated, same branch
