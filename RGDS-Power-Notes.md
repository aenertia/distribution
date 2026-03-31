# RG-DS (RK3568) PMIC Power Notes

> **Date**: 2026-03-20
> **Device**: Anbernic RG DS (RK3568, RK817 PMIC)
> **Method**: ADB i2c register tracing on GammaOS/Android 14 (kernel 6.1.141)

---

## 1. RK817 PMIC Identity

| Register | Value | Meaning |
|----------|-------|---------|
| CHIP_NAME_H (0xED) | 0x81 | |
| CHIP_NAME_L (0xEE) | 0x75 | RK8175 (RK817) |
| CHIP_VER (0xEF) | 0x05 | Silicon revision 5 |
| OTP_VER (0xF0) | 0xC0 | OTP version |

I2C bus: 0, address: 0x20

## 2. Android Running State — Full Register Dump

### System Configuration
| Register | Addr | Value | Decode |
|----------|------|-------|--------|
| SYS_CFG(0) | 0xF1 | 0xAC | Short press=2, Long press=10s, OFF time=12s |
| SYS_CFG(1) | 0xF2 | 0xA0 | |
| SYS_CFG(2) | 0xF3 | 0x40 | |
| SYS_CFG(3) | 0xF4 | 0x18 | **SLPPOL=LOW(0), SLPPIN=RST(3), DEV_OFF=0** |
| SYS_STS | 0xF5 | 0x80 | Power state: ACTIVE |

### Power Enable
| Register | Addr | Value | Decode |
|----------|------|-------|--------|
| POWER_EN(0) | 0xB1 | 0x0F | DCDC1-4 all enabled |
| POWER_EN(1) | 0xB2 | 0x0F | LDO1-4 all enabled |
| POWER_EN(2) | 0xB3 | 0x0F | LDO5-8 all enabled |
| POWER_EN(3) | 0xB4 | 0x03 | LDO9=on, BOOST=on, **OTG=OFF**, SW1=off |

### Sleep Configuration
| Register | Addr | Value | Decode |
|----------|------|-------|--------|
| SLP_DCDC_EN | 0xBE | 0x22 | Sleep: DCDC2 on, others off |
| SLP_LDO_EN(0) | 0xBF | 0x20 | |
| SLP_LDO_EN(1) | 0xC0 | 0x64 | |

### ON/OFF Source (persists across reboot)
| Register | Addr | Value | Decode |
|----------|------|-------|--------|
| ON_SOURCE | 0xF6 | 0x04 | Bit 2: DCIN plug (USB power) |
| OFF_SOURCE | 0xF7 | 0x06 | Bit 1: UVLO, Bit 2: OVP — **brownout flags!** |

### Interrupt Status (persists across reboot)
| Register | Addr | Value | Decode |
|----------|------|-------|--------|
| INT_STS(0) | 0xF8 | 0x00 | No plug/unplug events |
| INT_STS(1) | 0xF9 | 0xDC | PWRON, PWRON_LP, HOTDIE, RTC_ALARM, USB_OV |
| INT_STS(2) | 0xFA | 0x00 | |
| INT_MSK(0) | 0xFB | 0xFC | |
| INT_MSK(1) | 0xFC | 0x00 | |
| INT_MSK(2) | 0xFD | 0xFF | |

### Regulators (Android)
| Regulator | Name | Voltage | State |
|-----------|------|---------|-------|
| regulator.5 | vdd_cpu | 950mV | enabled |
| regulator.6 | vdd_logic | 900mV | enabled |
| regulator.7 | vdd_gpu | 925mV | enabled |
| regulator.8 | vcc_ddr | 500mV | enabled |
| regulator.19 | boost | 5000mV | enabled |
| regulator.20 | otg_switch | — | **disabled** |

**Note**: vdd_cpu is regulator.5 on Android (regulator.25 on our 7.0-rc4 kernel).
Different driver probe order changes regulator numbering.

## 3. Android Shutdown Sequence (traced)

### Timeline
```
01:18:52  PMIC monitor started — baseline registers captured
01:19:37  Last polls — ALL registers IDENTICAL to baseline
01:19:39  ShutdownThread: "Logging pre-reboot information..."
01:19:39  ShutdownThread: "Sending shutdown broadcast..."
01:19:39  ShutdownThread: "Shutting down activity manager..."
01:19:40  ShutdownThread: "Shutting down package manager..."
01:19:40  ShutdownThread: "Waiting for Radio... Radio shutdown complete."
01:19:40  ShutdownThread: "Performing low-level shutdown..."
01:19:40  LAST POLL — registers STILL UNCHANGED
          (power cuts here — kernel sets DEV_OFF, PMIC powers down)
```

### Critical Finding
**Android does NOT modify ANY PMIC registers during shutdown.**

54 polls over 48 seconds — every register stayed identical to baseline.
The "low-level shutdown" call triggers `kernel pm_power_off()` → `rk808-core.c`
→ sets DEV_OFF bit (bit 0 of SYS_CFG(3)) → PMIC powers down all rails instantly.

No SLPPIN manipulation, no SLPPOL change, no pinctrl, no gradual rail sequence.
Just one register bit: DEV_OFF.

### Post-Reboot State
| Register | Value | Meaning |
|----------|-------|---------|
| ON_SOURCE | 0x80 | Bit 7: power button press |
| OFF_SOURCE | 0x06 | STILL UVLO+OVP from brownout (not cleared!) |
| SYS_CFG(3) | 0x18 | Back to RST mode (bootloader reinit) |
| INT_STS(1) | 0xDC | Interrupts NOT cleared across reboot |

## 4. SLPPIN Analysis

### What Android Uses
```
SYS_CFG(3) = 0x18 = 0b00011000
  Bit 5 (SLPPOL_H) = 0  → LOW polarity
  Bits 4:3 (SLPPIN) = 11 → RST mode (value 3)
  Bit 0 (DEV_OFF)   = 0  → Not powered off (active)
```

### What Our Patches Did (WRONG)
```
We set: SLPPOL_H = 1 (HIGH polarity) — WRONG, should be LOW
We set: SLPPIN = SHUTDOWN (value 2) — UNNECESSARY, bootloader uses RST (3)
We used: pinctrl to drive GPIO0_PA2 — NOT NEEDED, DEV_OFF handles poweroff
```

### Why Our Shutdown Was Broken
1. **Wrong polarity**: SLPPOL_H=1 means "active on rising edge". But the
   bootloader expects SLPPOL=LOW(0) meaning "active on falling edge".
   Our pinctrl drove the pin LOW, which with HIGH polarity = INACTIVE.

2. **Wrong function**: Changing SLPPIN from RST(3) to SHUTDOWN(2) altered
   the PMIC's power state machine. The bootloader expects RST mode on
   next boot — changing it breaks the boot sequence.

3. **Unnecessary complexity**: The standard `DEV_OFF` mechanism is all
   that's needed. One register write, instant power down.

## 5. Brownout Behavior (RK3568 vs RK3566)

### RK3566 (353P) Brownout
- Voltage droop → SoC lockup → watchdog reset → clean reboot
- Auto-recovers, no user intervention needed
- No PMIC fault flags latched

### RK3568 (RG-DS) Brownout
- Current surge → PMIC OCP (over-current protection) triggers
- Red status LED latches (PWM7 LED_FUNCTION_STATUS)
- BOOST regulator (backlight) drops to minimum output
- Hard power hold (10s) required to clear PMIC fault
- Brightness resets to minimum across both panels
- Android boot required to fully clear PMIC fault registers
- Power button unreliable after soft shutdown
- OFF_SOURCE shows UVLO (0x02) + OVP (0x04) = 0x06

### Root Cause
RK3568 brownout is **CURRENT-limited** (PMIC OCP), not voltage-floor.
Stock 1150mV@1800MHz → P=V²f draws too much current → PMIC trips OCP.
UV-optimal 975mV → less current → no OCP trip.
Higher voltage = MORE brownout risk (counterintuitive).

## 6. Stale Flag Problem

OFF_SOURCE (0xF7) and INT_STS (0xF8-0xFA) registers persist across reboot.
Android never clears them. Our revised patch clears INT_STS on shutdown
(W1C — write 1 to clear). OFF_SOURCE is read-only and cleared by the
PMIC hardware on next power-on event.

INT_STS(1) = 0xDC flags that persisted from the brownout:
- Bit 2: PWRON (power button event)
- Bit 3: PWRON_LP (long press)
- Bit 4: HOTDIE (thermal event)
- Bit 6: RTC_ALARM
- Bit 7: USB_OV (USB over-voltage)

## 7. Revised PR #2440 Approach

Based on this analysis, PR #2440 was revised:

**REMOVED:**
- SLPPIN function manipulation (leave as RST, bootloader default)
- SLPPOL_H override (leave as LOW, bootloader default)
- Pinctrl GPIO driving (not needed, DEV_OFF handles poweroff)
- DTS pinctrl states (patch 0031 deleted)
- rk808.h struct changes (pinctrl fields removed)

**KEPT:**
- OTG switch disable before poweroff (cuts USB VBUS)
- ON/OFF_SOURCE logging at probe (patch 0030)

**ADDED:**
- INT_STS register clearing (W1C) before poweroff
- Prevents stale UVLO/OVP/HOTDIE flags persisting

## 8. Charging-Only Boot Mode

The RK817 enters a charging-only mode when:
- Power is applied (USB/DCIN) but power button is NOT pressed
- Shows orange LED (PWM6 CHARGING) and charges battery
- Requires explicit power button press to boot to OS
- This is normal BSP/bootloader behavior, not a bug

ON_SOURCE = 0x04 (DCIN plug) confirms the device was powered by USB,
not by power button, when we plugged it in after the brownout.

## 9. Key Register Reference (RK817)

| Register | Address | Type | Description |
|----------|---------|------|-------------|
| SYS_CFG(0) | 0xF1 | RW | Power key timing |
| SYS_CFG(3) | 0xF4 | RW | SLPPOL, SLPPIN function, DEV_OFF |
| SYS_STS | 0xF5 | RO | Power state (active/standby) |
| ON_SOURCE | 0xF6 | RC | Last power-on reason |
| OFF_SOURCE | 0xF7 | RC | Last power-off reason |
| INT_STS(0) | 0xF8 | W1C | Plug/unplug interrupts |
| INT_STS(1) | 0xF9 | W1C | PWRON/thermal/RTC interrupts |
| INT_STS(2) | 0xFA | W1C | Charger interrupts |
| POWER_EN(3) | 0xB4 | RW | LDO9/BOOST/OTG/SW1 enable |

RC = Read to Clear, W1C = Write 1 to Clear, RW = Read/Write, RO = Read Only

## 10. Suspend/Resume Analysis (7.5 minute test)

### Test Setup
- Lid close trigger (hall sensor SW_LID)
- PMIC register polling at 250ms intervals
- 575 polls over ~14 minutes (including ~7.5 min asleep)
- Kernel sleep: 914s suspend → 1366s resume = **452 seconds (7.5 min)**

### Result: PMIC NEVER ENTERS SLEEP MODE

Every PMIC register was **IDENTICAL** across all 575 polls:
- SYS_CFG(3) = 0x18 throughout (SLPPIN=RST, no change)
- SYS_STS = 0x80 throughout (**ACTIVE**, never STANDBY)
- POWER_EN(3) = 0x03 throughout (OTG off, boost on)
- CPU voltage = 950mV throughout
- BOOST = 5V throughout
- SLP_DCDC/LDO config unchanged and **never activated**

`/sys/power/suspend_stats/success = 0` — kernel NEVER entered S2R.
`mHalAutoSuspendModeEnabled = false` — HAL auto-suspend disabled.

### What Android Actually Does During "Sleep"

1. **Screen off**: display controller and backlight PWM disabled
2. **Process freeze**: kernel freezer suspends userspace
3. **Touchscreen sleep**: Goodix GT911 enters I2C sleep mode
4. **WiFi early_suspend**: WLAN chip enters low-power mode
5. **CPU WFI**: ARM cores enter wait-for-interrupt (shallow idle)
6. **PMIC**: stays FULLY ACTIVE — all regulators at normal voltage

Android does NOT:
- Enter kernel S2R (`echo mem > /sys/power/state`)
- Use PMIC sleep mode (SLP_DCDC/SLP_LDO never activated)
- Change any PMIC registers during suspend/resume
- Use SLPPIN sleep function

### Doze Stages (configured but apparently not reaching kernel suspend)
- `light_after_inactive_to = 1 minute` — light doze
- `light_idle_to = 5 minutes` — light idle
- `idle_after_inactive_to = 1 minute` — deep idle starts
- Supported: `freeze mem` (both s2idle and S2R available)
- But `suspend_stats/success = 0` after 7.5 min of sleep

### Implications for ROCKNIX

1. **We can do better than Android** — use actual S2R via PSCI
2. **PMIC sleep mode is untested** on this hardware (Android never uses it)
3. **SLP_DCDC=0x22 keeps only DCDC2 on during PMIC sleep** — if we ever
   enable PMIC-level sleep, most rails would shut down (major power savings
   but needs careful validation of wake path)
4. **Battery life during ROCKNIX suspend should be compared to Android** —
   Android's shallow sleep wastes power; our S2R should be significantly better
5. **BOOST regulator stays at 5V during Android sleep** — we should disable it
   during suspend (backlight not needed, saves ~50-100mW)
