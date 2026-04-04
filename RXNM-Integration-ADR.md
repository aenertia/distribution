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
