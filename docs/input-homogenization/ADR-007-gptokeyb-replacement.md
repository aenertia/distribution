# ADR-007: gptokeyb Replacement Strategy

## Status

Accepted — phased deprecation, keep for PortMaster permanently.

## Context

`gptokeyb` (packaged as `rocknix-hotkey`) is a C++ daemon that translates gamepad
input to keyboard/mouse events for applications that don't support gamepads natively.
With InputPlumber providing gamepad normalization and profile switching, the question
is whether gptokeyb is still needed.

## gptokeyb Architecture

```
SDL2 GameController API
    ↓
gptokeyb daemon (C++, background process)
    ├── reads .gptk config file (button→key mappings)
    ├── creates uinput virtual keyboard + mouse
    ├── translates: gamepad button → KEY_* event
    ├── translates: analog stick → REL_X/REL_Y mouse movement
    └── monitors START+SELECT for kill switch
    ↓
/dev/input/eventX (virtual keyboard)
/dev/input/eventY (virtual mouse)
    ↓
Application (expects keyboard/mouse, not gamepad)
```

### What gptokeyb Provides

| Function | Description | Usage Frequency |
|----------|-------------|-----------------|
| Gamepad → keyboard | Map BTN_SOUTH → KEY_X, etc. | Every .gptk config |
| Analog → mouse | Left stick → mouse cursor movement | Most configs |
| Kill switch | START+SELECT kills target process | Every launch |
| Text input | D-pad character entry (arcade-style) | Rare |
| Hotkey combos | Guide + button → extra key bindings | Some configs |

### All .gptk Config Files

| Config | Emulator | What It Actually Maps | Real Need |
|--------|----------|----------------------|-----------|
| `default.gptk` | Fallback | Full keyboard layout (back=esc, a=x, etc.) | Used by misc ports |
| `azahar.gptk` | 3DS | All buttons → `\\` (no-op) | Kill switch only |
| `azahar_mouse_addon.gptk` | 3DS | Mouse addon for touch emulation | Mouse emulation |
| `drastic.gptk` | NDS | Touch key bindings (l2=shift, r2=ctrl) | Touch screen sim |
| `melonDS.gptk` | NDS | Minimal (most → `\\`) | Kill switch only |
| `flycast.gptk` | Dreamcast | Hotkey-only mappings | Kill switch + hotkeys |
| `skyemu.gptk` | GB/NES | Basic mapping | Kill switch + keys |
| `solarus-run.gptk` | Solarus engine | Full keyboard mapping | Full key mapping |
| `display-cycle.gptk` | Screen switch | Display mode cycling | Key mapping |

**Key insight:** Most standalone emulators map buttons to `\\` (no-op) because they
read gamepad input directly via SDL. They only use gptokeyb for the **kill switch**
(START+SELECT → kill process) and occasionally mouse emulation.

### All gptokeyb Launch Sites

```bash
# Universal pattern in every start_*.sh:
control-gen_init.sh                    # Auto-detect controller
source /storage/.config/gptokeyb/control.ini  # Set $GPTOKEYB
${GPTOKEYB} <app_name> -c <config>.gptk &     # Background daemon
# ... run emulator ...
kill -9 $(pidof gptokeyb)             # Cleanup
```

| Script | App | Config |
|--------|-----|--------|
| `start_azahar.sh` | azahar | azahar.gptk |
| `start_drastic.sh` | drastic | drastic.gptk |
| `start_melonds.sh` | melonDS | melonDS.gptk |
| `start_dolphin_gc.sh` | dolphin-emu | (default) |
| `start_dolphin_wii.sh` | dolphin-emu | (default) |
| `start_flycast.sh` | flycast | flycast.gptk |
| `start_skyemu.sh` | skyemu | skyemu.gptk |
| `start_portmaster.sh` | PortMaster | (PortMaster's own gptokeyb) |

## Can InputPlumber Replace gptokeyb?

### What InputPlumber CAN Do

InputPlumber profiles support remapping gamepad events to keyboard/mouse output:
- `keyboard` is a target device type (creates virtual keyboard via uinput)
- `mouse` is a target device type (creates virtual mouse via uinput)
- Profiles loadable at runtime via DBus: `busctl call ... LoadProfilePath`
- The existing `runemu.sh` already has `inputplumber_set_profile()` helper

A YAML profile could define:
```yaml
# Theoretical InputPlumber keyboard profile
mapping:
  - source: gamepad.button.South
    target: keyboard.key.KEY_X
  - source: gamepad.button.East
    target: keyboard.key.KEY_Z
  - source: gamepad.axis.LeftStick
    target: mouse.motion
```

### What InputPlumber CANNOT Do

| Gap | Why | Workaround |
|-----|-----|------------|
| Kill switch (START+SELECT → kill process) | InputPlumber can't execute shell commands | runemu.sh trap / DBus watcher |
| Interactive text input (D-pad character entry) | Not a remapping function | Keep gptokeyb or use wvkbd |
| Per-game auto-load from .gptk | Different config format | Convert .gptk → YAML or write shim |

### The PortMaster Problem

PortMaster ships its own `gptokeyb` binary in `/storage/roms/ports/PortMaster/gptokeyb`.
At port launch, it copies this binary into the port directory and runs it. We cannot
control this — PortMaster is a third-party project with its own release cycle.

PortMaster ports are ported PC games that REQUIRE keyboard/mouse input. gptokeyb is
fundamental to their operation. Even if we remove the system gptokeyb, PortMaster
brings its own.

## Decision

### Phase 1: Coexistence (Current State)

Both InputPlumber and gptokeyb run. InputPlumber normalizes the gamepad hardware.
gptokeyb reads from InputPlumber's virtual Xbox pad (or from SDL GameController API
which detects the virtual pad). No changes needed.

```
Hardware → InputPlumber → Virtual Xbox Pad
                              ↓
                    gptokeyb reads SDL
                              ↓
                    Virtual keyboard/mouse
                              ↓
                    Application
```

### Phase 2: Replace gptokeyb for "Kill Switch Only" Emulators — COMPLETED (2026-03-21)

Implemented on `rk356x-inputplumber` branch. InputPlumber profiles replace gptokeyb
for emulators that only used it as a kill switch + simple hotkeys.

**New InputPlumber profiles** (in `inputplumber/sources/usr/share/inputplumber/profiles/`):
- `emulator-3ds.yaml` — azahar: L2→F10 (4-state stretch cycle), R2→F9 (swap), RStick→mouse
- `emulator-nds.yaml` — melonDS: L2→F9 (swap), R2→F (fast fwd), RStick→mouse
- `emulator-dc.yaml` — flycast: R2→F (fast forward)
- `emulator-gb.yaml` — skyemu: RStick→mouse, R3→click

**Key design:** 3DS/NDS have no L2/R2, so triggers are mapped directly to keyboard
keys — no combo modifier needed. Avoids conflict with input_sense's FN+L2/R2
display-cycle hotkeys (which are skipped when a game is running).

**Changes:**
- `runemu.sh`: loads profile per core via `inputplumber_set_profile()` before launch
- gptokeyb removed from: `start_azahar.sh`, `start_melonds.sh`, `start_flycast.sh`, `start_skyemu.sh`
- `input_sense`: display-cycle skipped when `pgrep -f runemu.sh` succeeds

**Remaining on gptokeyb:** drastic (full keyboard mapping), solarus (custom layout).

### Phase 3: InputPlumber Profiles for Keyboard-Needing Apps

For emulators/ports that need actual keyboard mapping (drastic touch sim, solarus):
- Convert .gptk → InputPlumber YAML profiles
- `runemu.sh` loads the profile via `inputplumber_set_profile()` before launch
- On exit, `inputplumber_restore()` resets to default gamepad mode

### Phase 4: gptokeyb Shim

Create `/usr/bin/gptokeyb` as a thin shell script wrapper:

```bash
#!/bin/bash
# gptokeyb shim — loads InputPlumber profile instead of running real gptokeyb
APP_NAME="$1"
shift
GPTK_CONFIG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c) GPTK_CONFIG="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Convert .gptk path to InputPlumber profile path
PROFILE="/usr/share/inputplumber/profiles/${GPTK_CONFIG%.gptk}.yaml"
if [ -f "${PROFILE}" ]; then
    inputplumber_set_profile "${PROFILE}"
fi

# Wait for the app to exit (gptokeyb normally runs until killed)
while kill -0 $(pidof "${APP_NAME}") 2>/dev/null; do
    sleep 1
done

inputplumber_restore
```

This maintains backward compatibility with all existing start scripts that call
`${GPTOKEYB} appname -c config.gptk &`.

### PortMaster: Keep Forever

PortMaster's own gptokeyb binary continues to work because:
1. It reads from SDL GameController API
2. SDL detects InputPlumber's virtual Xbox pad via gamecontrollerdb
3. gptokeyb creates its own virtual keyboard/mouse via uinput
4. The port application reads from those virtual devices

No interference between InputPlumber and PortMaster's gptokeyb.

## Consequences

- Standalone emulators that only need kill switch can drop gptokeyb entirely
- InputPlumber profiles replace .gptk configs for keyboard mapping
- PortMaster is unaffected — their gptokeyb binary is self-contained
- The system `rocknix-hotkey` package can eventually be dropped from builds
  (PortMaster ships its own, system gptokeyb becomes the shim script)
- `control-gen` and `control-gen_init.sh` become unnecessary when gptokeyb is
  replaced — InputPlumber handles controller discovery via YAML device configs

## Related

- ADR-001: InputPlumber architecture (runemu.sh profile helpers)
- ADR-005: Input source inventory (gptokeyb in consumer list)
- ADR-006: input_sense (separate hotkey system, not replaced by gptokeyb changes)
- Source: `packages/apps/rocknix-hotkey/package.mk`
- Configs: `packages/emulators/standalone/*/config/*.gptk` (8 files)
