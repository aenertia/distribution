# ADR: rxnm Integration into EmulationStation-next

**Status:** Active / Implementing
**Date:** 2026-03-17 (updated)
**Author:** Joel Wiramu Pauling

## Context

ROCKNIX replaced ConnMan with rxnm for L3 networking. rxnm is a stateless network manager that accepts JSON input and produces JSON output via its CLI. EmulationStation-next previously used `wifictl` shell scripts which chain through `iwctl` CLI and a Python3 D-Bus wrapper (`iwd_get-networks`) to enumerate WiFi networks. This chain had unnecessary complexity and a Python3 runtime dependency.

Furthermore, ES previously treated networking as a simplistic "WiFi On/Off" toggle with a single static "IP ADDRESS" display. Modern handhelds require advanced power management (Nullify Mode) and visibility into multiple interfaces (e.g., USB Gadgets, Ethernet docks, WiFi, and VPNs).

rxnm provides a clean JSON schema interface consumed directly from ES using rapidjson (already an ES dependency) to expose these advanced tunables safely.

## Architecture Evolution

### Phase 1: Core JSON Bridge (Complete)

```text
ES → RxnmNetwork::exec("rxnm <cmd> --format json") → parse JSON → display
ES → RxnmNetwork::getSystemStatus() → rxnm system status --json → live UI
```

- `RxnmNetwork` C++ wrapper: 314 lines, thin bridge pattern
- Async polling: `getSystemStatusAsync()` + `std::future` for non-blocking UI
- Live-updating per-interface detail pages (2s poll interval)

### Phase 2: Unified Tool Chain (Current)

```text
┌──────────────┐     ┌──────────────────────┐     ┌──────────────────┐
│   ES-next    │────▶│  RxnmNetwork (C++)   │────▶│  rxnm CLI (JSON) │
│  GuiMenu     │     │  exec() / reload()   │     │  wifi/bt/system  │
│  GuiNetIface │     │  scanNetworks()      │     │  nullify/profile │
│  ApiSystem   │     │  listBluetoothDevices│     │  vpn/interface   │
└──────────────┘     └──────────────────────┘     └──────────────────┘
                                                         │
    ┌─────────────┐    ┌──────────────────┐              │
    │  wifictl    │───▶│  rxnm shim       │──────────────┘
    │  (legacy)   │    │  (backward compat)│
    └─────────────┘    └──────────────────┘
                                                         │
    ┌─────────────────┐    ┌──────────────────┐          │
    │rocknix-bluetooth│───▶│  rxnm shim       │──────────┘
    │  (legacy)       │    │  + python agent   │
    └─────────────────┘    │  (live discovery) │
                           └──────────────────┘
```

**Key changes:**
- `wifictl` → thin rxnm shim (eliminates Python3 `iwd_get-networks` dependency)
- `rocknix-bluetooth` → hybrid rxnm shim (BT operations via rxnm JSON, live discovery via Python agent)
- `sleep.sh` → rxnm-aware (defers to rxnm-resume hook when available)
- rxnm bluetooth extended with `connect`, `disconnect`, `list` actions

## Bug Fixes Applied

### Domain Name (UseDomains=yes)
rxnm's `.network` files (`80-wifi-station.network`, `80-wired.network`) lacked `UseDomains=yes` in `[DHCPv4]`. Without this, systemd-networkd received the DHCP domain but didn't propagate it to systemd-resolved. ES's `resolvectl domain` call returned empty, falling back to `.local`.

**Fix:** Added `UseDomains=yes` to `[DHCPv4]` and `[IPv6AcceptRA]` sections in both files.

### Domain Name (UseDomains + JSON)
Three issues combined to prevent domain display:
1. `.network` files lacked `UseDomains=yes` — DHCP domain not propagated to resolved
2. ES used `awk '/link/'` but BusyBox `resolvectl` outputs `Link` (uppercase) — case mismatch
3. rxnm agent didn't include domain in JSON status output

**Fix:** rxnm agent now reads `/run/systemd/resolve/resolv.conf` `search` directive and includes `"domain"` in status JSON. All three status paths (C agent, Bash+jq, POSIX fallback) produce it consistently. ES reads `sysStatus.domain` from rxnm JSON — no more shell-out to resolvectl. `build_network_config()` defaults `UseDomains=yes` for all DHCP configs. api-schema.json updated.

### Sleep/Resume Conflicts
The ROCKNIX `sleep.sh` script called `wifictl disable`/`wifictl enable` which competed with rxnm's `rxnm-resume` hook. Both scripts tried to manage WiFi state independently, causing slow or failed reconnection on resume.

**Fix:** `sleep.sh` now detects rxnm and defers WiFi/BT management to the rxnm-resume hook.

### Nullify Mode (Verified Working)
XDP eBPF + BT HCI air-gap tested on RK3566 RGDS device:
- `rxnm system nullify enable` → mode: "bt,xdp" (both layers active)
- XDP successfully drops all incoming packets at driver level
- BT adapter powered down via HCI
- State files created in `/run/rocknix/`
- SSH connection correctly blocked by XDP (verified by connection timeout)

## UI Architecture

### Main Network Settings Page (Simplified)
```
NETWORK SETTINGS
  INFORMATION
    HOSTNAME             ROCKNIX.home
  INTERFACES
    wlan3 (WiFi)  172.16.1.52     →  [per-interface detail]
    gadget (USB)  192.168.213.1   →  [per-interface detail]
  VPN
    WIREGUARD                     →  [VPN config sub-page]
  SETTINGS
    HOSTNAME / ENABLE WIFI / SHOW NETWORK INDICATOR
```

### Per-Interface Detail Page (Enriched for WiFi)
```
wlan3 SETTINGS
  STATUS         (live-updating: state, MAC, driver)
  WIFI           (live-updating: SSID, signal, frequency)
                 FORGET THIS NETWORK
  WIFI MANAGEMENT
    KNOWN NETWORKS  →  [list with forget actions]
    WIFI HOTSPOT    →  [AP config sub-page]
    CHECK INTERNET  [action]
  IPV4 / IPV6    (live-updating addresses and gateways)
  IP CONFIGURATION
    SET DHCP / SET STATIC IP
  POWER MANAGEMENT
    NULLIFY MODE    [ON/OFF]
  PROFILES
    SAVE PROFILE    [action]
```

### Live Update Strategy
1. UI list rows constructed statically on menu open
2. `std::shared_ptr<TextComponent>` pointers retained for dynamic fields
3. `update(int deltaTime)` override polls `rxnm system status --json` every 2s
4. Text values updated **in-place** via `setValue()` — no list reconstruction, no focus loss

## Key Files

| File | Role |
|------|------|
| `es-app/src/RxnmNetwork.h/cpp` | Central JSON bridge (exec, status, scan, BT list) |
| `es-app/src/guis/GuiNetworkInterface.h/cpp` | Per-interface detail with live updates |
| `es-app/src/guis/GuiMenu.cpp` | Main network settings page |
| `rxnm/lib/rxnm-bluetooth.sh` | BT connect/disconnect/list (new) |
| `rxnm/bin/rxnm` | Dispatcher with BT extensions |
| `rxnm/usr/lib/systemd/network/80-wifi-station.network` | UseDomains fix |
| `rocknix/sources/scripts/wifictl` | rxnm shim |
| `rocknix/sources/scripts/rocknix-bluetooth` | Hybrid rxnm shim |
| `sysutils/sleep/sources/sleep.sh` | rxnm-aware sleep hook |
| `rxnm/lib/rxnm-diagnostics.sh` | Domain in all 3 status paths |
| `rxnm/lib/rxnm-config-builder.sh` | UseDomains=yes default for DHCP |
| `rxnm/src/rxnm-agent.c` | Domain from resolv.conf in JSON |
| `rxnm/api-schema.json` | Contract: domain, BT actions |
| `es-app/src/guis/GuiControllersSettings.cpp` | BT PAN tethering entry |

## Uclamp / cgroupv2 Integration

### Motivation
schedutil frequency ramp-up latency causes frame drops when emulators start demanding cycles. Background services waste power/thermal headroom on big cores.

### Implementation
- `CONFIG_UCLAMP_TASK=y` enabled on RK3566 (5 buckets, TASK_GROUP)
- `systemd.unified_cgroup_hierarchy=1` in kernel cmdline forces cgroupv2 unified
- `099-freqfunctions`: `has_uclamp()`, `set_system_uclamp()`, `set_rt_uclamp()`, `set_slice_uclamp()`
- `runemu.sh`: wraps emulator launch with `uclampset -m MIN -M MAX` using per-game settings
- `background.slice`: systemd slice with CPUWeight=50, uclamp capped at boot
- Per-device defaults in `010-governors` quirk files
- Boot: `set_system_uclamp 0 1024` + `set_rt_uclamp 512` + background slice cap

### Per-Device Defaults
| Device | UCLAMP_EMU_MIN | UCLAMP_BG_MAX | Topology |
|--------|----------------|---------------|----------|
| RK3566 | 384 (~37%) | 50% | Symmetric 4xA55 |
| RK3588 | 512 (50%) | 25% | big.LITTLE 4xA76+4xA55 |

### Key Design Choices
- No daemon — `uclampset` wraps exec, values persist for process lifetime
- Graceful fallback — `has_uclamp` no-op if kernel lacks support
- Composable — `uclampset` chains with existing `taskset` (`EMUPERF`)
- Per-game override via existing `get_setting "uclamp_min" PLATFORM GAME`
