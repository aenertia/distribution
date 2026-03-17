# ADR: ROCKNIX Virtual Output Management

**Status:** Implemented (physical stacking approach)
**Date:** 2026-03-15
**Author:** Joel Wiramu Pauling

---

## Context

ROCKNIX supports dual-screen handheld devices (Anbernic RG DS, Retroid Pocket 5/Mini, AYANEO Pocket DS) that have two physical display panels. To present a unified surface to applications, the system needs to combine both panels into a single logical display (e.g. 640x960 for RGDS's 2x 640x480 DSI panels).

---

## Approaches Evaluated

### HEADLESS Virtual Output (ABANDONED)

Created a sway HEADLESS virtual output at 640x960 and moved workspaces to it.

**Why it failed:** HEADLESS outputs are invisible off-screen render buffers. Apps render to them but content never displays on physical panels. Sway does not mirror HEADLESS outputs to physical displays.

Additional issues:
- `swaymsg create_output` is undocumented (GitHub #5553), auto-names HEADLESS-N
- python3 was used for JSON parsing but isn't in the runtime image
- `mode --custom` is not a valid swaymsg flag
- `output X pos 0 0, power on` sends bare `power on` without output context

### Catch-all `for_window` Rules (ABANDONED)

Added `for_window [app_id=".*"]` rule to float+resize all windows.

**Why it failed:** Fights with existing window management — ES gets repositioned, melonDS dual-screen windows get clamped.

### Global `floating_maximum_size` in Config (ABANDONED)

Added `floating_maximum_size 640 x 960` to sway config file.

**Why it failed:** Global setting clamps ALL windows, not just ES. MelonDS dual-screen windows (WindowWidth=1920, WindowHeight=1152) get clamped to 960px, causing the top DS screen to be cropped. Must be set transiently via `swaymsg` only when needed, then reset to `0 x 0`.

### Physical Output Stacking + Watcher Daemon (IMPLEMENTED)

Stack DSI panels vertically, use sway IPC event watcher to enforce ES layout.

**Why it works:** Sway treats stacked outputs as contiguous coordinate space. A floating window at (0,0) sized 640x960 spans DSI-2 (top, 0-479) and DSI-1 (bottom, 480-959). A watcher daemon monitors window events via sway IPC subscription and re-applies the float+resize whenever ES changes state, with transient `floating_maximum_size` that doesn't affect other apps.

---

## Implementation

### Architecture (v2 — minimal touch redesign)

```
Toggle Stretched Mode.sh (self-contained module)
  ├─ set_setting system.stretched_mode 0|1
  └─ systemd-run helper script:
      ├─ Enable: stack outputs → start watcher → restart essway → float ES
      └─ Disable: stop watcher → restart essway → reset outputs

stretched-watcher daemon (systemd transient service)
  ├─ sway IPC subscribe ["window"] — monitors ALL window events
  ├─ On every event (except [w1]/[w2]/Secondary):
  │   ├─ Re-stack outputs (undoes exec_always power-off rule)
  │   ├─ Transient floating_max → float+resize+focus window → reset floating_max
  │   └─ Works WITH existing sway rules, not against them
  │
start_es.sh: --windowed --resolution $(fbwidth) $(($(fbheight)*2))
runemu.sh: RetroArch appendconfig (windowed, ctx_scaling) — dimensions via fbwidth/fbheight
start_drastic.sh: screen_orientation=0 when stretched
start_azahar.sh: layout_option=0, skip AZAHAR_RGDS_DUAL when stretched

No modifications to: 001-functions, sway config, vertical-check
```

### Key discoveries

| Issue | Root cause | Fix |
|-------|-----------|-----|
| Window clamped to 480px | Sway default floating_maximum_size | Set transiently via swaymsg, reset after |
| floating_maximum_size in config | Clamps ALL windows (melonDS, etc.) | MUST NOT be in config, only via swaymsg |
| floating_maximum_size trailing comment | Parsed as extra argument, not comment | Use separate `#marker` lines for block identification |
| ES resets to single panel | `for_window [emulationstation] reload` triggers cascade | Disable rule via sed markers during stretched mode |
| ES renders only 480px tall | SDL surface created at output resolution | Launch ES with `--windowed --resolution 640 960` |
| ES un-floats after game exit | ES calls SDL_SetWindowFullscreen on resume | Watcher daemon + for_window rule catch and re-float |
| Delayed re-float via systemd-run | Single 2s delay unreliable, ES may re-fullscreen later | Watcher daemon monitors continuously via IPC subscription |
| ES loses button input after re-float | Sway focus not on ES window | Watcher must `swaymsg focus` after re-float (touch works without focus) |
| Toggle script dies with ES | Script runs as ES child, killed by systemctl restart | Write helper to /tmp, run via `systemd-run --no-block` |
| systemd-run inline bash -c escaping | `$((TRIES + 1))` breaks with triple-backslash escaping | Write helper to file, run file via systemd-run |
| `swaymsg reload` resets positions | Config only defines DSI-2, DSI-1 goes to default | Reposition outputs AFTER reload |
| RetroArch renders 480px internally | Fullscreen RA creates 480px SDL surface | Force windowed via appendconfig overrides |
| RetroArch appendconfig conflicts | setsettings.sh writes same keys before our overrides | Strip conflicting keys with sed, prepend our overrides |
| RetroArch letterboxed in center | aspect_ratio_index and video_ctx_scaling overridden | Must be first in appendconfig (first occurrence wins) |
| python3 not in runtime | Build-time only dependency | Replace with jq (dep of rocknix-screenshot, rxnm) |
| Leading `#` on for_window rule | Sway treats as comment on entire line | Use trailing comment: `for_window [...] ... #MARKER` |
| `for_window` position centering | `move absolute position 0 0` processed before resize completes | for_window + watcher combination ensures correct positioning |
| SWAYSOCK not in systemd-run env | Transient services don't inherit profile environment | Bake SWAYSOCK path into helper scripts |
| `STRETCHED_ACTIVE` env var lost | Each runemu.sh invocation is a new shell | Detect via config markers: `grep -q '^#STRETCHED#' config` |

### sway_dual_stack_enable()

```
001-functions:
1. Check idempotency (skip if #STRETCHED# markers exist in config)
2. Disable ES sway rules (sed markers in config)
3. Add for_window rule for ES float+resize+border none
4. swaymsg reload
5. Stack outputs: CON@(0,0), SECOND_CON@(0,PANEL_H)
6. Start stretched-watcher daemon (if not running)
7. Touch calibration for stacked layout
```

### Watcher daemon (stretched-watcher.service)

Runs as a systemd transient service via `systemd-run --unit=stretched-watcher`.

```bash
swaymsg -t subscribe -m '["window"]' | while read -r event; do
    # Only act on ES window events
    if APP_ID == "emulationstation":
        swaymsg "floating_maximum_size 640 x 960"   # raise limit transiently
        swaymsg '[app_id="emulationstation"]' float+resize+position
        swaymsg '[app_id="emulationstation"]' focus  # buttons need focus
        swaymsg "floating_maximum_size 0 x 0"        # reset limit for other apps
done
```

### start_es.sh

Checks `system.stretched_mode` + `DEVICE_HAS_DUAL_SCREEN`, passes `--windowed --resolution 640 960` so ES creates a 960-tall SDL surface. Without this, ES renders 480px regardless of sway container size.

### runemu.sh — RetroArch overrides

When stretched mode active and emulator is retroarch:
```bash
# Strip conflicting keys set by setsettings (first occurrence wins in appendconfig)
sed -i '/^video_fullscreen\b/d; ...' "${RETROARCH_APPEND_CONFIG}"
# Prepend stretched overrides
sed -i '1i\
video_fullscreen = "false"\
video_windowed_position_width = "640"\
video_windowed_position_height = "960"\
video_window_custom_size_enable = "true"\
aspect_ratio_index = "24"\
video_ctx_scaling = "true"' "${RETROARCH_APPEND_CONFIG}"
```

**Critical ordering:** This code must run AFTER `STRETCHED_MODE` is set (line ~390), not in the `retroarch)` case block (line ~290) which executes before the stretched mode detection.

### Toggle Stretched Mode

- Writes helper script to `/tmp/stretched_helper.sh` with all variables pre-expanded
  (heredoc with single-quoted delimiter avoids escaping issues)
- Sed replaces placeholder strings with actual values
- `systemd-run --no-block /tmp/stretched_helper.sh` — independent of ES process tree
- Helper: restarts essway, waits for ES window (jq retry loop), floats+resizes

---

## Sway command reference

```bash
# Output positioning (comma = separate commands, each needs output prefix)
swaymsg output DSI-2 power on, output DSI-2 pos 0 0
swaymsg output DSI-1 power on, output DSI-1 pos 0 480

# Floating size limit (x separator required, no trailing comments allowed)
swaymsg "floating_maximum_size 640 x 960"
swaymsg "floating_maximum_size 0 x 0"                    # reset to default

# Float + resize + position (single command)
swaymsg '[app_id="emulationstation"]' floating enable, border none, resize set 640 960, move absolute position 0 0

# for_window rules — trailing comment OK, leading # = entire line commented
for_window [app_id="emulationstation"] floating enable, border none, resize set 640 960, move absolute position 0 0
# NOT: floating_maximum_size 640 x 960 #MARKER  ← parsed as 4th argument, error

# Static IPC socket (ROCKNIX patches sway to remove PID from path)
SWAYSOCK="/var/run/0-runtime-dir/sway-ipc.0.sock"
```

---

## Emulator compatibility

### Working in stretched mode
| Emulator | Type | Notes |
|----------|------|-------|
| EmulationStation | Frontend | `--windowed --resolution WxH`, watcher re-floats on every window event |
| RetroArch cores | libretro | appendconfig: windowed WxH, aspect_ratio Full, ctx_scaling. Dimensions via fbwidth()/fbheight(). |
| yabasanshiro (Saturn/SegaCD) | Standalone SDL | Watcher floats, renders at native res stretched by sway |
| Sonic (genesis_plus_gx) | RetroArch | Tested, stretches correctly |
| Dreamcast (flycast) | RetroArch | Tested, works in-game |
| PSX (PCSX-ReARMed) | RetroArch | Tested, works with Full aspect ratio |

### Partially working
| Emulator | Visual | Input | Issue |
|----------|--------|-------|-------|
| Drastic | Both DS screens visible (vertical stacked) | Buttons OK, touch broken | `libdrastouch.so` Y coords 2x off due to 480→960 stretch |

### Not working in stretched mode
| Emulator | Issue | Root cause |
|----------|-------|------------|
| azahar-SA | Fullscreen constrains to one output in stretched mode | Qt windowed mode causes artifacts. Non-stretched RGDS mode WORKS with custom layout + bar-hiding patch. |
| melonDS-SA | Separate windows conflict with float approach | ScreenSizing=4 creates [w1]+[w2] windows. Needs ScreenSizing=2 (single window stacked) in stretched mode. |
| AetherSX2 | Splits menu on top panel, game on bottom, can't exit | Standalone emulator with own window management |

### Three categories of emulator stretched mode support

1. **Generic single-window (works now):** RetroArch cores, most standalone emulators without custom window management. Handled by runemu.sh appendconfig overrides + watcher float.

2. **Single-window with touch (needs per-emulator fix):** Drastic — renders both DS screens in one SDL surface. Visual works but touch coordinates are wrong because `libdrastouch.so` doesn't account for sway's 480→960 stretch. Fix: patch `libdrastouch.c` to detect stretched mode, or adjust touch calibration matrix.

3. **Dual-window emulators (needs redesign):** melonDS-SA (ScreenSizing=4), azahar-SA (layout_option=4). These create separate windows for each screen — fundamentally incompatible with "one window spanning both panels". Must either:
   - Switch to single-window vertical layout in stretched mode (melonDS ScreenSizing=2, azahar layout_option=0)
   - Or handle window placement explicitly in start scripts (like azahar's existing RGDS code)

### Drastic implementation details

- `start_drastic.sh` detects stretched mode and sets `screen_orientation = 0` (vertical stacked)
- RGDS default is `screen_orientation = 1` (side-by-side, for per-output dual-screen mode)
- Config file: `/storage/.config/drastic/config/drastic.cfg`
- RGDS device config source: `drastic-sa/config/RK3566/drastic.cfg.rgds`
- Touch library: `libdrastouch.so` (source: `drastic-sa/sources/libdrastouch.c`)
  - Loaded via `LD_PRELOAD` in start_drastic.sh
  - Replaces SDL touch→mouse translation with direct DS touch mapping
  - Coordinate system assumes SDL surface matches sway container — broken when stretched
- `SDL_TOUCH_MOUSE_EVENTS=0` disables default SDL touch handling
- app_id: `drastic` — needs `border none` (defaults to "normal" with title bar)
- Drastic is closed-source binary — no `--windowed` flag available

---

## ES Theme

- system-theme (Art Book Next) has aspect ratio variants: 4:3, 16:9, 16:10, 3:2, 1:1
- No 2:3 variant for 640x960 — auto-detection falls back to first non-auto entry
- Theme uses normalized coordinates (0.0–1.0) so layout renders but isn't optimized
- Future: create `aspect-ratio-2-3.xml` for proper tall-screen layout

---

## Remaining work

### High priority
- **Reboot persistence:** Watcher daemon not started on boot. Need autostart script or `111-sway-init` hook to check `system.stretched_mode` and start watcher + stack outputs.
- **Drastic touch:** Patch `libdrastouch.c` to handle stretched coordinates
- **melonDS stretched mode:** `start_melonds.sh` should use ScreenSizing=2 (vertical stacked single window) when stretched active

### Medium priority
- **azahar stretched mode:** Needs source patches — Qt windowed mode causes menubar + scanline artifacts. Consider patching azahar to hide menubar in windowed mode or support a stretched layout natively.
- **AetherSX2:** Investigate window management — splits menu/game across panels
- **Stale HEADLESS cleanup:** Qt/wayland emulators (azahar) create parasitic HEADLESS outputs. Watcher should periodically clean these.
- **Theme 2:3 aspect ratio:** system-theme `aspect-ratio-2-3.xml` for optimized tall-screen layout

### Low priority
- **Toggle UX:** Brief black screen during ES restart
- **Watcher as proper systemd service:** Currently /tmp script via systemd-run transient
- **Other standalone emulators:** Test PPSSPP-SA, dolphin-SA in stretched mode

---

## Files

| File | Role |
|------|------|
| `projects/ROCKNIX/packages/rocknix/profile.d/001-functions` | enable/disable/float + watcher daemon |
| `projects/ROCKNIX/packages/misc/modules/sources/Toggle Stretched Mode.sh` | User-facing toggle (ES Tools menu) |
| `projects/ROCKNIX/packages/rocknix/sources/scripts/runemu.sh` | RetroArch overrides + emulator float watcher |
| `projects/ROCKNIX/packages/ui/emulationstation/sources/start_es.sh` | Windowed ES launch |
| `projects/ROCKNIX/packages/wayland/compositor/sway/autostart/111-sway-init` | Sway config generation (regenerates on boot) |
| `projects/ROCKNIX/packages/wayland/compositor/sway/scripts/sway-touch.sh` | jq + retry loop pattern reference |
| `projects/ROCKNIX/packages/rocknix/sources/scripts/vertical-check` | Per-emulator physical output stacking |
| `projects/ROCKNIX/packages/emulators/standalone/drastic-sa/scripts/start_drastic.sh` | Drastic stretched mode orientation override |
| `projects/ROCKNIX/packages/emulators/standalone/drastic-sa/sources/libdrastouch.c` | Touch coordinate mapping (needs stretched fix) |
| `projects/ROCKNIX/packages/emulators/standalone/melonds-sa/scripts/start_melonds.sh` | melonDS RGDS dual-screen (needs stretched mode) |
| `projects/ROCKNIX/packages/emulators/standalone/azahar-sa/scripts/start_azahar.sh` | azahar RGDS dual-screen (needs stretched test) |

---

## On-device testing methodology

```bash
# Deploy files to persistent storage on device
sshpass -p rocknix scp file root@rk3566:/storage/tests/file

# Bind mount over squashfs originals (updates take effect immediately)
sshpass -p rocknix ssh root@rk3566 'mount --bind /storage/tests/file /usr/bin/file'

# Bind mounts lost on reboot — re-apply or add to /storage/.config/autostart/

# SWAYSOCK must be exported explicitly in SSH sessions:
export SWAYSOCK=/var/run/0-runtime-dir/sway-ipc.0.sock

# Recovery from broken state:
sshpass -p rocknix ssh root@rk3566 'bash -c "
  export SWAYSOCK=/var/run/0-runtime-dir/sway-ipc.0.sock
  source /etc/profile
  set_setting system.stretched_mode 0
  sed -i \"s/^#STRETCHED# //\" /storage/.config/sway/config
  sed -i \"/STRETCHED_ES_FLOAT/d\" /storage/.config/sway/config
  systemctl stop stretched-watcher
  systemctl restart essway
"'
```
