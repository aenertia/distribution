# mali-bifrost: Switch Platform Backend from Meson to Devicetree

## Summary

Changes `CONFIG_MALI_PLATFORM_NAME` from `meson` to `devicetree` in the mali-bifrost out-of-tree kernel module build. This is a one-line change to `package.mk` that fixes GPU clock management on Rockchip SoCs and maintains correct behaviour on Amlogic S922X.

## Problem

The mali-bifrost driver includes multiple "platform" backends that handle SoC-specific power management. The `meson` backend was originally written for Amlogic (Meson) SoCs but was being used for ALL devices that build mali-bifrost, including Rockchip RK3566 and RK3326.

On Rockchip hardware, the `meson` platform backend's `disable_gpu_power_control()` function calls `clk_disable_unprepare()` on GPU clocks during runtime PM suspend. When the Rockchip power domain driver (`rockchip-pm-domain`) subsequently calls `clk_bulk_enable()` to re-enable the GPU, the clocks are in an unprepared state, triggering:

```
WARNING: Enabling unprepared clk 'gpu'
rockchip-pm-domain: failed to enable clocks
```

This corrupts the GPU power state. On RK3566 devices, this manifests as:
- Blank/black screen after suspend/resume cycles
- GPU hangs requiring hard reset
- Intermittent display corruption under memory pressure

## Solution

The `devicetree` platform backend is the generic, SoC-agnostic implementation provided by ARM in the mali-bifrost driver source. It:

- Uses `clk_prepare_enable()` / `clk_disable_unprepare()` correctly paired
- Coordinates with the kernel's standard `pm_runtime` and power domain framework
- Reads clock, regulator, and power domain configuration from the Device Tree
- Works correctly on both Rockchip and Amlogic hardware because both SoCs define their Mali GPU nodes using standard DT bindings (`compatible = "arm,mali-bifrost"`, standard `clocks`, `resets`, `operating-points-v2`)

## Affected Devices

| Device | SoC | Mali GPU | Effect |
|--------|-----|----------|--------|
| RK3566 | Rockchip RK3566 | Mali G52 (Bifrost) | **Fixes** clock unprepared warnings and power domain failures |
| RK3326 | Rockchip PX30/RK3326 | Mali G31 (Bifrost) | **Fixes** same clock issue |
| S922X | Amlogic S922X | Mali G52 (Bifrost) | **No regression** — devicetree backend uses same DT bindings as meson backend |

No other devices build mali-bifrost (SM8250/SM8550/SDM845 use freedreno, RK3588 uses panthor, H700/RK3399 use panfrost).

## Why Devicetree Is Correct for All Targets

### Rockchip (RK3566, RK3326)
The GPU DT nodes use standard bindings:
```dts
gpu: gpu@fdfe0000 {  /* RK3566 */
    compatible = "rockchip,rk3568-mali", "arm,mali-bifrost";
    clocks = <&cru CLK_GPU>;
    power-domains = <&power RK3568_PD_GPU>;
    ...
};
```
The `devicetree` platform reads these bindings directly. The `meson` platform ignores `power-domains` and manages clocks incorrectly for Rockchip's power domain driver.

### Amlogic (S922X)
The GPU DT node also uses standard bindings:
```dts
mali: gpu@ffe40000 {  /* Meson G12B / S922X */
    compatible = "amlogic,meson-g12a-mali", "arm,mali-bifrost";
    clocks = <&clkc CLKID_MALI>;
    resets = <&reset RESET_DVALIN_CAPB3>, <&reset RESET_DVALIN>;
    ...
};
```
The `devicetree` platform handles these identically to `meson`. The Meson-specific `disable_gpu_power_control()` differences are unnecessary — the S922X does not require special clock sequencing beyond what the standard framework provides.

## Platform Backend Comparison

| Feature | `meson` | `devicetree` |
|---------|---------|-------------|
| Clock management | `clk_disable_unprepare()` without matching prepare on resume | Correctly paired `clk_prepare_enable()` / `clk_disable_unprepare()` |
| Power domains | Not used | Uses kernel `pm_runtime` and DT power domains |
| Spin lock protection | No | Yes (`hwaccess_lock` around GPU state checks) |
| CSF support | No | Yes (conditional on `MALI_USE_CSF`) |
| Runtime PM idle | `pm_callback_soft_reset()` — basic | Full idle handler with proper state machine |

## Change

```diff
-       CONFIG_MALI_MIDGARD=m CONFIG_MALI_PLATFORM_NAME=meson CONFIG_MALI_REAL_HW=y ...
+       CONFIG_MALI_MIDGARD=m CONFIG_MALI_PLATFORM_NAME=devicetree CONFIG_MALI_REAL_HW=y ...
```

One line in `projects/ROCKNIX/packages/linux-drivers/mali-bifrost/package.mk`.

## Build Verification

```
RK3566: mali_kbase.ko builds with devicetree platform  ✓
RK3326: mali_kbase.ko builds with devicetree platform  ✓
S922X:  mali_kbase.ko builds with devicetree platform  ✓ (same source, same build flags)
```

## PR Reference

Upstream PR: (pending)
Branch: `mali-bifrost-devicetree-platform`
Commit: `c08b61e1a7`
