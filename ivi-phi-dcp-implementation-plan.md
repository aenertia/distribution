# ROCKNIX NPU/DSP Compute Acceleration Blueprint

## 1. Executive Summary

This blueprint outlines the integration of **mainline Linux NPU and DSP compute acceleration** into the ROCKNIX emulation OS, using the upstream kernel `accel` subsystem (target 6.18+) and the **Mesa Teflon/Rocket** userspace stack. No BSP or vendor SDK is used.

Traditional emulators perform all work — rendering, audio synthesis, texture decoding, and CPU emulation — on the primary ARM cores. On low-power SoCs like the RK3566 (4× Cortex-A55), this creates severe CPU contention. Modern ARM SoCs ship with dedicated compute accelerators (Rockchip RKNN NPUs, Qualcomm Hexagon DSPs) that sit idle during emulation.

By offloading three classes of work to these accelerators — **AI super-resolution upscaling**, **audio DSP batch processing**, and **texture decompression** — we free CPU cycles for the emulation core loop without modifying GPU rendering pipelines.

### What This Plan Does NOT Do

The upstream Φᵈᶜᵖ IVI algorithm is an **integer factorization** method, not a general-purpose arithmetic accelerator. Emulator carry-chain arithmetic (e.g., PowerPC `ADDE`, x86 `ADC`) operates on **known operands** producing **known results** in single clock cycles. Offloading individual ALU instructions to an NPU (with microsecond-scale dispatch latency) for work that completes in nanoseconds on the CPU would be a net negative. This plan does not pursue that path.

Instead, we use the NPU/DSP for workloads that are:
1. **Batch-oriented** — operating on buffers (audio frames, texture blocks, image tiles), not single instructions
2. **Latency-tolerant** — results needed within milliseconds, not nanoseconds
3. **Embarrassingly parallel** — hundreds to thousands of independent operations per dispatch
4. **CPU-competitive** — each dispatch must save more CPU time than it costs in overhead

### Relationship to Φᵈᶜᵖ

The IVI algorithm's per-step evaluation (100 multiply-accumulate + constraint checks per branch, across N branches) is a legitimate NPU compute workload. A native C implementation running on the Teflon/Rocket stack serves as the **validation benchmark** for the compute pipeline described in this plan — proving the DMA-BUF, NIR lowering, and job submission paths work before emulator integration begins. It is not used for emulation acceleration.

## 2. Performance Projections

### 2.1 Per-Platform Compute Capabilities

| SoC | NPU/DSP | Mainline Driver | Compute (TOPS) | Dispatch Latency | Primary Use |
|-----|---------|----------------|-----------------|-----------------|-------------|
| **RK3566** | RKNN (3-core) | `accel/rocket` | 1 (INT8) | ~0.5–2 ms | AI upscaling, audio batch |
| **RK3588** | RKNN (3-core) | `accel/rocket` | 6 (INT8) | ~0.3–1 ms | AI upscaling (1080p), audio, texture |
| **SDM845** | Hexagon 685 DSP | `fastrpc` | ~3 (INT8) | ~0.3–1 ms | Audio DSP, upscaling via GPU compute |
| **SM8250** | Hexagon 698 DSP | `fastrpc` | ~15 (INT8) | ~0.2–0.8 ms | Audio DSP, AI upscaling |
| **SM8550** | Hexagon DSP + NPU | `fastrpc` | ~45 (INT8) | ~0.1–0.5 ms | All workloads at high throughput |
| **SM8650** | Hexagon DSP + NPU | `fastrpc` | ~45+ (INT8) | ~0.1–0.5 ms | All workloads at high throughput |

### 2.2 AI Upscaling Latency Estimates (RK3566, 1 TOPS NPU)

*Lightweight INT8-quantized super-resolution models (FSRCNN/ESPCN class).*

| Source Resolution | Emulator Context | Scale | Output | Est. Latency | 60fps Budget |
|-------------------|-----------------|-------|--------|-------------|-------------|
| 240×160 | GBA | 2× | 480×320 | ~1–2 ms | Fits easily |
| 256×224 | SNES/Genesis | 2× | 512×448 | ~1–3 ms | Fits easily |
| 320×240 | PS1, N64 | 2× | 640×480 | ~2–5 ms | Fits |
| 400×240 | 3DS (top) | 2× | 800×480 | ~3–6 ms | Fits |
| 320×224 | Saturn, DC | 2× | 640×448 | ~2–5 ms | Fits |
| 640×448 | PS2 | 2× | 1280×896 | ~10–20 ms | 30fps only |

### 2.3 Per-Emulator Impact Projections (RK3566)

*Conservative estimates. "Headroom" = CPU cycles freed for emulation core loop.*

| Emulator | System | Baseline FPS | NPU Workloads | Headroom Freed | Projected FPS |
|----------|--------|-------------|---------------|----------------|---------------|
| **Flycast** | Dreamcast | 30–40 | AICA 64ch audio offload, 1× render + upscale | ~10–15% CPU | 35–50 |
| **Azahar** | 3DS | 20–30 | Audio HLE offload, 1× render + 2× upscale | ~10–20% CPU | 25–35 |
| **Yabasanshiro** | Saturn | 20–30 | SCSP 32ch audio offload, texture decode | ~10–20% CPU | 25–35 |
| **Dolphin** | GC/Wii | 15–20 | Audio DSP offload, 1× render + upscale | ~5–15% CPU | 18–24 |
| **AetherSX2** | PS2 | 10–15 | SPU2 48ch audio offload, 1× render + upscale | ~10–20% CPU | 12–18 |
| **DuckStation** | PS1 | 55–60 | 1× render + 2× NPU upscale (visual quality, not FPS) | ~0% CPU | 55–60 (sharper) |
| **PPSSPP** | PSP | 40–60 | Atrac3 decode offload, 1× + upscale | ~5–10% CPU | 45–60 |

*On RK3588 (6 TOPS) and SM8550 (45 TOPS), all the above improve further. RPCS3 and Switch emulators become realistic targets on those platforms.*

### 2.4 Per-Emulator Impact Projections (RK3588, SM8250, SM8550)

| Emulator | System | SoC | Baseline FPS | NPU Workloads | Projected FPS |
|----------|--------|-----|-------------|---------------|---------------|
| **RPCS3** | PS3 | RK3588 | <5 (unplayable) | SPU audio offload (6 TOPS), 1× + upscale | 8–15 (marginal) |
| **RPCS3** | PS3 | SM8550 | 15–30 | Hexagon SPU audio, upscale | 25–40 |
| **Dolphin** | GC/Wii | SM8250 | 40–55 | DSP audio offload, upscale | 55–60 |
| **Azahar** | 3DS | SM8250 | 45–60 | Audio offload, 4× upscale | 60 (locked, higher res) |
| **Xemu** | Xbox | SM8250 | 25–35 | Audio offload, texture batch | 30–45 |
| **Xemu** | Xbox | SM8550 | 35–50 | Hexagon audio, texture, upscale | 50–60 |
| **AetherSX2** | PS2 | SM8550 | 40–55 | SPU2 Hexagon offload, upscale | 55–60 |
| **FEX + Proton** | PC/x86 | SM8550 | 30–45 | Hexagon audio decode, upscale | 40–55 |
| **Citron/Eden** | Switch | SM8550 | 20–40 | Audio decode offload, upscale | 30–50 |

## 3. OS Architectural Design (Zero-Loss Integration)

The compute acceleration layer is **strictly additive**. No existing rendering path, driver, or emulator behavior is modified. If NPU/DSP hardware is absent or the feature is disabled, all emulators function identically to current builds.

```
┌─────────────────────────────────────────────────────────┐
│                    ROCKNIX Userspace                     │
│                                                         │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────────┐ │
│  │ Emulator │  │ Emulator │  │   libnpu-accel.so      │ │
│  │ Renderer │  │ Audio    │  │   (Middleware)          │ │
│  │          │  │ Engine   │  │                        │ │
│  └────┬─────┘  └────┬─────┘  └──┬──────────┬─────────┘ │
│       │              │           │          │           │
│  ┌────▼─────┐   ┌────▼──────────▼──┐  ┌────▼─────────┐ │
│  │ libmali  │   │ Mesa Teflon      │  │ freedreno    │ │
│  │ (blob)   │   │ (Rocket backend) │  │ (Mesa)       │ │
│  │ or       │   │                  │  │ Vulkan       │ │
│  │ panfrost │   │                  │  │ Compute      │ │
│  └────┬─────┘   └────┬─────────────┘  └────┬─────────┘ │
└───────┼──────────────┼──────────────────────┼───────────┘
        │              │                      │
   ─────┼──────────────┼──────────────────────┼───── Kernel
        │              │                      │
   ┌────▼─────┐   ┌────▼─────────┐       ┌───▼──────────┐
   │ DRM/KMS  │   │ DRM/accel    │       │ DRM/MSM      │
   │ rockchip │   │ rocket       │       │ + fastrpc    │
   │ or msm   │   │              │       │              │
   └────┬─────┘   └────┬─────────┘       └───┬──────────┘
        │              │                      │
   ┌────▼─────┐   ┌────▼─────────┐       ┌───▼──────────┐
   │ Mali GPU  │   │ RKNN NPU    │       │ Adreno GPU   │
   │ /dev/     │   │ /dev/accel/ │       │ Hexagon DSP  │
   │ mali0     │   │ rocket0     │       │ /dev/fastrpc │
   └──────────┘   └──────────────┘       └──────────────┘
```

### Design Rules

1. **GPU Pipeline** (`/dev/mali0`, `/dev/kgsl-3d0`): Handles pure rendering (OpenGL/Vulkan). **Unmodified.**
2. **NPU/DSP Pipeline** (`/dev/accel/rocket0` or `/dev/fastrpc`): Handles compute offload — inference, audio batch, texture decode. Accessed exclusively through `libnpu-accel`.
3. **Memory Sharing** (`DMA-BUF`): Zero-copy buffer exchange between CPU and accelerator. The CPU writes input data (audio samples, texture blocks, low-res frames), the NPU/DSP processes it, and the CPU reads results. No `memcpy` overhead.
4. **Fallback**: Every offloaded operation has a CPU software fallback. If `libnpu-accel` initialization fails (no hardware, no driver), the emulator transparently uses the existing CPU path.

### Rockchip-Specific Constraint

On RK3566/RK3588, the GPU uses **proprietary libmali blobs** for OpenGL/Vulkan. The Mesa build for these platforms must include the Rocket gallium driver for NPU compute **without** enabling any GL/Vulkan/EGL/GBM drivers that would conflict with libmali. This is achieved via a dedicated `mesa-npu` package or build-time conditionals (see §5).

### Qualcomm-Specific Architecture

On SDM845/SM8250/SM8550/SM8650, the GPU uses **Mesa freedreno** (fully open-source). This means:
- GPU rendering: freedreno OpenGL/Vulkan — **unmodified**
- GPU compute: Vulkan compute shaders via freedreno — available for upscaling workloads that can share GPU idle time
- DSP compute: Hexagon via FastRPC — dedicated, does not touch GPU
- Preferred path: **Hexagon DSP for audio/batch work**, Vulkan compute for upscaling (amortized during vsync gaps)

## 4. Platform-Specific Kernel Configurations

### 4.1 Rockchip RK3566 (Mainline `accel/rocket`)

**Current state**: `CONFIG_DRM_ACCEL` is disabled. No NPU support.

**Required changes** to `projects/ROCKNIX/devices/RK3566/linux/linux.aarch64.conf`:

```text
# --- NPU Compute Acceleration (additive, does not touch GPU) ---
CONFIG_DRM_ACCEL=y
CONFIG_ACCEL_ROCKET=m
```

**Device Tree**: The RK3566 NPU node exists in mainline DT (`arch/arm64/boot/dts/rockchip/rk3568.dtsi`). Verify `status = "okay"` is set:

```dts
npu: npu@fde40000 {
    compatible = "rockchip,rk3568-rknn";
    reg = <0x0 0xfde40000 0x0 0x10000>;
    interrupts = <GIC_SPI 151 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&cru CLK_NPU>, <&cru HCLK_NPU>,
             <&cru PCLK_NPU>;
    clock-names = "npu", "hclk", "pclk";
    resets = <&cru SRST_A_NPU>, <&cru SRST_H_NPU>;
    reset-names = "srst_a", "srst_h";
    power-domains = <&power RK3568_PD_NPU>;
    status = "okay";
};
```

### 4.2 Rockchip RK3588 (Mainline `accel/rocket`, replacing BSP RKNPU)

**Current state**: Uses BSP `CONFIG_ROCKCHIP_RKNPU=y` with vendor kernel driver. Must migrate to mainline.

**Required changes** to `projects/ROCKNIX/devices/RK3588/linux/linux.aarch64.conf`:

```text
# --- Remove BSP RKNPU ---
# CONFIG_ROCKCHIP_RKNPU is not set
# CONFIG_ROCKCHIP_RKNPU_DEBUG_FS is not set
# CONFIG_ROCKCHIP_RKNPU_DRM_GEM is not set

# --- Enable Mainline Rocket ---
CONFIG_DRM_ACCEL=y
CONFIG_ACCEL_ROCKET=m
```

The RK3588 NPU (3-core, 6 TOPS) will be exposed as `/dev/accel/rocket0` on mainline. Same Teflon userspace as RK3566 — only the hardware capabilities differ.

### 4.3 Qualcomm SDM845 / SM8250 / SM8550 / SM8650 (Mainline FastRPC)

**Current state**: `CONFIG_QCOM_FASTRPC` is already enabled (`=y` on SM8250/SM8550/SM8650, `=m` on SDM845). `CONFIG_DRM_ACCEL` is disabled.

**Required changes** for all Qualcomm platforms:

```text
# --- Ensure FastRPC and DSP support ---
CONFIG_QCOM_FASTRPC=y
CONFIG_QCOM_SYSMON=y

# --- Enable DRM accel subsystem for future mainline NPU drivers ---
CONFIG_DRM_ACCEL=y
```

**SDM845-specific**: Change `CONFIG_QCOM_FASTRPC=m` to `=y` for consistent behavior:

```text
# projects/ROCKNIX/devices/SDM845/linux/linux.aarch64.conf
CONFIG_QCOM_FASTRPC=y
```

**Audio offload infrastructure** (already enabled on SM8250+):
```text
CONFIG_SND_COMPRESS_OFFLOAD=y
CONFIG_SND_COMPRESS_ACCEL=y
CONFIG_SND_SOC_QDSP6=y
```

### 4.4 Remaining Platforms (S922X, RK3326, RK3399)

These SoCs have no accessible NPU or DSP via mainline drivers. The `libnpu-accel` middleware detects this at init and returns `NULL`, causing all emulators to use CPU fallback paths. **No kernel changes needed.** No regressions.

## 5. Mesa / Teflon Build Integration

### 5.1 Rockchip: Dedicated `mesa-npu` Package

A separate Mesa build that enables **only** the Rocket gallium driver and Teflon runtime. This avoids any header, library, or symbol conflicts with the proprietary `libmali` blobs.

**`projects/ROCKNIX/packages/graphics/mesa-npu/package.mk`:**

```makefile
PKG_NAME="mesa-npu"
PKG_VERSION="$(get_pkg_version mesa)"
PKG_SITE="$(get_pkg_setting mesa PKG_SITE)"
PKG_URL="$(get_pkg_setting mesa PKG_URL)"
PKG_DEPENDS_TARGET="toolchain libdrm"
PKG_LONGDESC="Mesa Teflon/Rocket NPU compute runtime (no GL/Vulkan)"

# Only build for devices with Rockchip NPUs
PKG_SUPPORTED_DEVICES="RK3566 RK3588"

configure_target() {
  # Rocket gallium driver + Teflon runtime ONLY
  # All graphics APIs disabled to prevent libmali conflicts
  meson setup ${PKG_BUILD}/.${TARGET_NAME} ${PKG_BUILD} \
    --prefix=/usr \
    --cross-file=${MESON_CROSS_FILE} \
    -Dgallium-drivers=rocket \
    -Dvulkan-drivers="" \
    -Dopengl=false \
    -Dglx=disabled \
    -Degl=disabled \
    -Dgbm=disabled \
    -Dteflon=true \
    -Dshader-cache=disabled \
    -Dplatforms="" \
    -Dbuildtype=release
}

make_target() {
  ninja -C ${PKG_BUILD}/.${TARGET_NAME} -j${CONCURRENCY_MAKE_LEVEL}
}

makeinstall_target() {
  DESTDIR=${INSTALL} ninja -C ${PKG_BUILD}/.${TARGET_NAME} install

  # Safety: remove any GL/EGL/GBM headers or libs that might leak
  rm -rf ${INSTALL}/usr/include/GL
  rm -rf ${INSTALL}/usr/include/EGL
  rm -rf ${INSTALL}/usr/include/GLES*
  rm -rf ${INSTALL}/usr/include/gbm.h
  rm -f ${INSTALL}/usr/lib/libGL*
  rm -f ${INSTALL}/usr/lib/libEGL*
  rm -f ${INSTALL}/usr/lib/libgbm*
}
```

### 5.2 Qualcomm: Mesa Compute Extensions

On Qualcomm devices, Mesa is already the primary graphics stack (freedreno). Vulkan compute is available through the existing build. No separate package is needed.

For AI upscaling via Vulkan compute, add the SPIR-V compute shaders to the existing `mesa` package configuration. The `libnpu-accel` middleware uses `VkComputePipeline` for upscaling on Qualcomm, falling back to Hexagon FastRPC for audio/batch work.

No changes to `projects/ROCKNIX/packages/graphics/mesa/package.mk` are needed — Vulkan compute support is already included when `VULKAN_SUPPORT=yes`.

## 6. Compute Workload Architecture

Three classes of work are offloaded. Each has a well-defined CPU hot-path, a batched data-parallel equivalent, and a measurable dispatch cost that must be exceeded by the CPU savings.

### 6.1 AI Super-Resolution Upscaling

**Problem**: Emulators rendering at native resolution (240p–480p) produce visually poor output on modern displays. Running at higher internal resolution (2×–4×) increases GPU and CPU load, reducing FPS.

**Solution**: Render at native (1×) resolution. After the emulator produces a frame, dispatch it to the NPU/DSP for 2× super-resolution upscaling. The upscaled frame is displayed. The GPU never renders at higher-than-native resolution, freeing both GPU and CPU headroom.

**Model Requirements** (INT8 quantized for NPU):

| Model Class | Parameters | RK3566 Latency | RK3588 Latency | Quality |
|-------------|-----------|----------------|----------------|---------|
| ESPCN | ~20K | ~1 ms | <0.5 ms | Acceptable |
| FSRCNN | ~100K | ~2–5 ms | ~1–2 ms | Good |
| ESRGAN-lite | ~300K | ~8–15 ms | ~3–6 ms | Very good |
| Real-ESRGAN-mobile | ~1M | ~15–30 ms | ~5–10 ms | Excellent |

**Integration point**: Post-processing filter in the display output pipeline, after the emulator's own rendering is complete. Applies to all emulators uniformly via `libnpu-accel`'s `npu_upscale_frame()` API.

**Frame pipeline**:
```
Emulator renders 320×240 frame → CPU writes to DMA-BUF →
NPU runs SR model → 640×480 result in DMA-BUF →
Display compositor reads upscaled frame
```

### 6.2 Audio DSP Batch Offload

**Problem**: Emulated audio subsystems (PS2 SPU2, Saturn SCSP, Dreamcast AICA, 3DS DSP) perform multi-voice mixing, ADPCM decoding, reverb, and FM synthesis. This runs per-audio-buffer on the CPU, consuming 3–15% of a single A55 core — cycles that could serve the emulation main loop instead.

**Solution**: Express audio mixing as batched matrix operations. A buffer of N voices × M samples is a natural matrix multiply / accumulate workload. Dispatch the entire buffer to the NPU/DSP in one call.

**Workload characteristics**:

| Audio Subsystem | Voices | Sample Rate | Buffer Size | CPU Cost | Offload Viable? |
|----------------|--------|-------------|-------------|----------|-----------------|
| PS2 SPU2 | 48 | 48 kHz | 512 samples | ~5–10% | Yes — 48×512 matrix |
| Saturn SCSP | 32 | 44.1 kHz | 512 samples | ~5–15% | Yes — FM synthesis batch |
| DC AICA | 64 | 44.1 kHz | 512 samples | ~3–8% | Yes — 64-voice mix |
| 3DS DSP HLE | 24 | 32.8 kHz | 160 samples | ~3–8% | Yes — batch decode+mix |
| GC/Wii DSP | 64 | 32 kHz | 256 samples | ~3–10% | Yes — ADPCM + mixing |
| PSP Atrac3+ | 2–8 | 44.1 kHz | 1024 samples | ~2–5% | Marginal — small batch |

**Integration point**: Hook the audio backend's mixing/output function. Instead of per-voice CPU loops, marshal voice buffers into a DMA-BUF and dispatch via `npu_audio_mix()`.

**Buffer pipeline**:
```
Emulator fills per-voice ADPCM buffers →
CPU writes N×M voice matrix to DMA-BUF →
NPU/DSP runs decode + mix + effects →
Mixed stereo output in DMA-BUF →
Audio backend reads and submits to ALSA/PulseAudio
```

### 6.3 Texture Decompression Offload

**Problem**: Console-native texture formats (S3TC/CMPR on GC/Wii, VQ on Dreamcast, PVRTC on various) must be decompressed to GPU-native formats before upload. On Rockchip platforms where the GPU is accessed via proprietary blobs, this decompression happens on the CPU. During texture-heavy scenes (level transitions, open worlds), this creates stalls.

**Solution**: Batch-dispatch texture blocks to the NPU. S3TC/CMPR decompression is a fixed-function block decode (4×4 pixel blocks, 64-bit input → 16-pixel output) that is trivially parallelizable.

**Workload characteristics**:

| Format | Block Size | Decode Complexity | Batch Size (typical) | CPU Savings |
|--------|-----------|-------------------|---------------------|-------------|
| S3TC/DXT1 (GC CMPR) | 4×4, 64-bit | Low | 256–4096 blocks | 2–5% |
| VQ (Dreamcast) | 2×2 codebook | Very low | 1024+ entries | 1–3% |
| ETC1/ETC2 (3DS) | 4×4, 64-bit | Low | 256–2048 blocks | 2–5% |
| PVRTC (PSP) | Variable | Medium | 256–1024 blocks | 3–8% |

**Integration point**: Hook the texture cache upload path. When a batch of compressed textures is queued, dispatch to NPU instead of CPU decode loop.

## 7. Universal Middleware (`libnpu-accel`)

This C library abstracts the hardware interface. Emulators link against it to access NPU/DSP compute without knowing the underlying platform.

**`projects/ROCKNIX/packages/compute/libnpu-accel/sources/include/npu_accel.h`:**

```c
#ifndef NPU_ACCEL_H
#define NPU_ACCEL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque context — holds platform-specific state */
typedef struct NpuContext NpuContext;

/* Buffer handle for zero-copy DMA-BUF exchange */
typedef struct NpuBuffer NpuBuffer;

/* Platform capabilities */
typedef struct {
    int has_npu;              /* Rocket NPU available */
    int has_dsp;              /* Hexagon DSP available */
    int has_vulkan_compute;   /* Vulkan compute available (freedreno) */
    int npu_tops;             /* INT8 TOPS (0 if no NPU) */
    int max_upscale_width;    /* Max input width for upscaling */
    int max_upscale_height;   /* Max input height for upscaling */
} NpuCaps;

/* --- Lifecycle --- */
NpuContext* npu_accel_init(void);
void        npu_accel_destroy(NpuContext* ctx);
NpuCaps     npu_accel_caps(NpuContext* ctx);

/* --- Buffer Management --- */
NpuBuffer*  npu_buffer_alloc(NpuContext* ctx, size_t size);
void*       npu_buffer_map(NpuBuffer* buf);    /* CPU-accessible pointer */
int         npu_buffer_fd(NpuBuffer* buf);      /* DMA-BUF fd for sharing */
void        npu_buffer_free(NpuBuffer* buf);

/* --- AI Upscaling --- */

typedef enum {
    NPU_UPSCALE_FAST,     /* ESPCN — lowest latency */
    NPU_UPSCALE_BALANCED, /* FSRCNN — good quality/latency tradeoff */
    NPU_UPSCALE_QUALITY   /* ESRGAN-lite — best quality */
} NpuUpscaleModel;

/* Load an upscaling model. Returns 0 on success. */
int npu_upscale_load_model(NpuContext* ctx, NpuUpscaleModel model, int scale);

/* Upscale a frame. src/dst are NpuBuffers in RGBA8 format.
 * Non-blocking: returns a fence fd. Poll or sync before reading dst. */
int npu_upscale_frame(NpuContext* ctx,
                      NpuBuffer* src, int src_w, int src_h,
                      NpuBuffer* dst, int dst_w, int dst_h);

/* Blocking upscale (convenience wrapper). */
int npu_upscale_frame_sync(NpuContext* ctx,
                           NpuBuffer* src, int src_w, int src_h,
                           NpuBuffer* dst, int dst_w, int dst_h);

/* --- Audio DSP Offload --- */

typedef enum {
    NPU_AUDIO_PCM_S16,     /* Signed 16-bit PCM */
    NPU_AUDIO_PCM_F32,     /* 32-bit float */
    NPU_AUDIO_ADPCM_PS2,   /* PS2 SPU2 ADPCM */
    NPU_AUDIO_ADPCM_GC,    /* GameCube/Wii DSP ADPCM */
    NPU_AUDIO_ADPCM_IMA    /* IMA ADPCM (generic) */
} NpuAudioFormat;

/* Decode + mix N voices into stereo output.
 * voice_data: array of N voice buffer pointers (in DMA-BUF)
 * volumes: per-voice L/R volume pairs (N×2 floats)
 * output: stereo interleaved output buffer (in DMA-BUF)
 * Returns 0 on success, -1 on fallback-to-CPU. */
int npu_audio_mix(NpuContext* ctx,
                  NpuAudioFormat fmt,
                  const void** voice_data, int num_voices,
                  int samples_per_voice,
                  const float* volumes,
                  void* output);

/* --- Texture Decompression --- */

typedef enum {
    NPU_TEX_S3TC_DXT1,     /* BC1 / GC CMPR */
    NPU_TEX_S3TC_DXT3,     /* BC2 */
    NPU_TEX_S3TC_DXT5,     /* BC3 */
    NPU_TEX_ETC1,          /* ETC1 */
    NPU_TEX_ETC2_RGB,      /* ETC2 RGB */
    NPU_TEX_VQ_DC          /* Dreamcast VQ */
} NpuTexFormat;

/* Batch-decompress texture blocks.
 * src: compressed data, dst: decompressed RGBA8 output.
 * num_blocks: number of 4×4 blocks to process.
 * Returns 0 on success, -1 on fallback-to-CPU. */
int npu_tex_decompress(NpuContext* ctx,
                       NpuTexFormat fmt,
                       const void* src, void* dst,
                       int num_blocks);

#ifdef __cplusplus
}
#endif
#endif /* NPU_ACCEL_H */
```

**`projects/ROCKNIX/packages/compute/libnpu-accel/sources/src/npu_accel.c`** (platform dispatch):

```c
#include "npu_accel.h"
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

struct NpuContext {
    int accel_fd;           /* /dev/accel/rocket0 or -1 */
    int fastrpc_fd;         /* /dev/fastrpc or -1 */
    int backend;            /* 0=none, 1=rocket, 2=hexagon, 3=vulkan_compute */
    void* model_data;       /* Loaded upscale model */
    /* Platform-specific opaque state */
    void* platform;
};

struct NpuBuffer {
    int dmabuf_fd;
    void* mapped;
    size_t size;
    int accel_handle;
};

NpuContext* npu_accel_init(void) {
    NpuContext* ctx = calloc(1, sizeof(NpuContext));
    if (!ctx) return NULL;

    ctx->accel_fd = -1;
    ctx->fastrpc_fd = -1;
    ctx->backend = 0;

    /* Try Rocket NPU first (Rockchip) */
    ctx->accel_fd = open("/dev/accel/accel0", O_RDWR | O_CLOEXEC);
    if (ctx->accel_fd >= 0) {
        ctx->backend = 1; /* Rocket */
        return ctx;
    }

    /* Try FastRPC (Qualcomm Hexagon) */
    ctx->fastrpc_fd = open("/dev/fastrpc-adsp", O_RDWR | O_CLOEXEC);
    if (ctx->fastrpc_fd < 0)
        ctx->fastrpc_fd = open("/dev/fastrpc-cdsp", O_RDWR | O_CLOEXEC);
    if (ctx->fastrpc_fd >= 0) {
        ctx->backend = 2; /* Hexagon */
        return ctx;
    }

    /* No accelerator available — all calls will return fallback */
    return ctx;
}

NpuCaps npu_accel_caps(NpuContext* ctx) {
    NpuCaps caps = {0};
    if (!ctx) return caps;

    switch (ctx->backend) {
    case 1: /* Rocket */
        caps.has_npu = 1;
        /* Query actual TOPS from sysfs or ioctl */
        caps.npu_tops = 1; /* Conservative default for RK3566 */
        caps.max_upscale_width = 1280;
        caps.max_upscale_height = 960;
        break;
    case 2: /* Hexagon */
        caps.has_dsp = 1;
        caps.npu_tops = 15; /* Varies by SoC — query at runtime */
        caps.max_upscale_width = 1920;
        caps.max_upscale_height = 1080;
        break;
    }

    return caps;
}

void npu_accel_destroy(NpuContext* ctx) {
    if (!ctx) return;
    if (ctx->accel_fd >= 0) close(ctx->accel_fd);
    if (ctx->fastrpc_fd >= 0) close(ctx->fastrpc_fd);
    free(ctx->model_data);
    free(ctx->platform);
    free(ctx);
}

/* Audio mix — dispatches to platform backend or returns -1 for CPU fallback */
int npu_audio_mix(NpuContext* ctx, NpuAudioFormat fmt,
                  const void** voice_data, int num_voices,
                  int samples_per_voice, const float* volumes,
                  void* output) {
    if (!ctx || ctx->backend == 0)
        return -1; /* No accelerator — caller should use CPU path */

    switch (ctx->backend) {
    case 1: /* Rocket NPU */
        /* Marshal voice matrix into DMA-BUF, submit NIR compute job */
        /* ... platform-specific implementation ... */
        return 0;
    case 2: /* Hexagon DSP */
        /* FastRPC call to DSP-side audio mixer */
        /* ... platform-specific implementation ... */
        return 0;
    default:
        return -1;
    }
}

/* Texture decompress — dispatches to platform backend or returns -1 */
int npu_tex_decompress(NpuContext* ctx, NpuTexFormat fmt,
                       const void* src, void* dst, int num_blocks) {
    if (!ctx || ctx->backend == 0 || num_blocks < 64)
        return -1; /* Below threshold — CPU is faster due to dispatch overhead */

    /* Minimum batch size ensures dispatch cost is amortized */
    switch (ctx->backend) {
    case 1: /* Rocket */
        return 0;
    case 2: /* Hexagon */
        return 0;
    default:
        return -1;
    }
}
```

**`projects/ROCKNIX/packages/compute/libnpu-accel/package.mk`:**

```makefile
PKG_NAME="libnpu-accel"
PKG_VERSION="0.1.0"
PKG_DEPENDS_TARGET="toolchain libdrm"
PKG_LONGDESC="NPU/DSP compute acceleration middleware for ROCKNIX"

# Conditional deps based on platform
ifeq ($(findstring RK,$(DEVICE)),RK)
  PKG_DEPENDS_TARGET+=" mesa-npu"
endif

PKG_CMAKE_OPTS_TARGET="-DCMAKE_BUILD_TYPE=Release"
```

## 8. Per-Emulator Integration

Each integration follows the same pattern:
1. Link against `libnpu-accel`
2. Call `npu_accel_init()` at startup — if it returns a valid context, NPU paths are enabled
3. Hook the specific audio/texture/display paths described below
4. Provide `ROCKNIX_NPU_ENABLE=1/0` environment variable to toggle at runtime

### 8.1 Dolphin (GameCube / Wii)

**Platforms**: SM8250, SM8550, SDM845, SM8650, RK3399 (CPU fallback), RK3566 (if added), RK3588

**Primary Bottleneck**: JIT recompilation quality on ARM64, GX texture decoding, DSP HLE audio processing.

**NPU Integration Points**:

- **Audio DSP offload** — Dolphin's DSP HLE processes 64 voices of GC/Wii ADPCM audio. The `AudioCommon::Mixer` accumulates per-voice samples into the output buffer in a tight CPU loop. This is the hook point.
  - **Target**: `Source/Core/AudioCommon/Mixer.cpp` — `CMixer::Mix()`
  - **Strategy**: Before the per-voice mixing loop, check if `npu_audio_mix()` is available. Marshal the voice array (up to 64 voices × 256 samples × S16) into a DMA-BUF. If NPU returns 0, skip the CPU mixing loop. If -1, fall through to existing CPU path.
  - **Expected saving**: 3–10% CPU on audio-heavy titles (Zelda: Wind Waker, Metroid Prime)

- **Texture decompression** — GC/Wii uses CMPR (S3TC DXT1 variant) extensively. Dolphin decodes these on CPU before GPU upload.
  - **Target**: `Source/Core/VideoCommon/TextureDecoder_*.cpp` — `TexDecoder_Decode()`
  - **Strategy**: When decoding CMPR format, batch 4×4 blocks and dispatch via `npu_tex_decompress(NPU_TEX_S3TC_DXT1, ...)`. Minimum batch of 64 blocks to amortize dispatch.
  - **Expected saving**: 2–5% CPU during texture-heavy scenes

- **AI upscaling** — Render at native 640×480 (GC) or 640×528 (Wii), upscale to 1280×960 via NPU.
  - **Target**: Display output filter in ROCKNIX frontend (RetroArch or EmulationStation), not inside Dolphin itself.
  - **Impact**: Equivalent visual quality to 2× internal resolution without the GPU/CPU cost of rendering at 2×.

**Patch approach**: Compile-time `#ifdef ROCKNIX_NPU` guards around the audio mixer and texture decoder hot paths. Controlled by CMake option `-DROCKNIX_NPU=ON` (default OFF).

### 8.2 AetherSX2 / LRPS2 (PlayStation 2)

**Platforms**: RK3566, SM8250, SM8550, SM8650, RK3588

**Primary Bottleneck**: VU (Vector Unit) recompilation, GS (Graphics Synthesizer) to Vulkan translation, SPU2 48-voice audio.

**NPU Integration Points**:

- **SPU2 audio offload** — The PS2 SPU2 processes 48 voices with per-voice ADPCM decode, pitch interpolation, envelope, and reverb. This is one of the heaviest audio subsystems in emulation.
  - **Target**: `pcsx2/SPU2/Mixer.cpp` — `V_Core::Mix()`
  - **Strategy**: Batch all 48 voice channels (ADPCM → PCM decode + volume + pan) into a single NPU dispatch. The reverb wet/dry bus mixing is also batchable.
  - **Expected saving**: 5–15% CPU. On RK3566 where PS2 emulation is heavily CPU-constrained, this is the difference between 10 FPS and 14 FPS in demanding titles.

- **AI upscaling** — PS2 renders at 640×448 (most common) internally. NPU 2× upscale to 1280×896 provides visual improvement without the massive GPU cost of 2× internal resolution.
  - **Expected saving**: If the user currently runs at 2× internal res and drops to 1×, GPU load halves, freeing significant headroom.

> **Note**: AetherSX2 is distributed as a pre-built AppImage. Direct source patching is not possible. Integration would require either: (a) switching to the LRPS2 open-source fork, (b) using LD_PRELOAD hooks on the audio/display output, or (c) upscaling via the display frontend only.

### 8.3 Azahar (Nintendo 3DS)

**Platforms**: RK3566, SM8250, SM8550, SM8650, RK3588

**Primary Bottleneck**: PICA200 software vertex shader execution, ARM11 JIT, audio HLE DSP processing.

**NPU Integration Points**:

- **Audio HLE offload** — The 3DS DSP processes up to 24 audio sources with ADPCM decode, mixing, and effects. Azahar's HLE implementation runs this entirely on CPU.
  - **Target**: `src/audio_core/hle/` — `DspHle::PipelineStage()`
  - **Strategy**: Marshal the 24-source audio state into a DMA-BUF, dispatch decode+mix to NPU. The 3DS audio runs at 32.768 kHz with 160-sample buffers, producing ~5ms real-time windows.
  - **Expected saving**: 3–8% CPU

- **AI upscaling** — The 3DS top screen renders at 400×240 — one of the lowest-resolution targets. NPU 2× upscale to 800×480 transforms visual quality dramatically.
  - **Target**: Display output path. The 3DS has two screens; upscale each independently.
  - **Impact**: Huge visual improvement. At this resolution, even the lightest ESPCN model produces good results in ~1–2ms on RK3566 NPU.

- **Texture decode** — The 3DS PICA200 uses ETC1 compressed textures. Batch decode is viable.
  - **Target**: `src/video_core/texture/` — texture decode path
  - **Expected saving**: 2–5% CPU during texture-heavy 3D titles

**Patch approach**: Azahar is built from source (`PKG_CMAKE_OPTS_TARGET` in package.mk). Add `-DROCKNIX_NPU=ON` and guard integration behind compile-time checks.

### 8.4 Flycast (Dreamcast)

**Platforms**: RK3566, SM8250, SM8550, SM8650, RK3588, RK3326 (CPU fallback), RK3399

**Primary Bottleneck**: SH-4 FPU emulation, PowerVR tile-based rendering translation, AICA audio.

**NPU Integration Points**:

- **AICA audio offload** — The Dreamcast AICA processes up to 64 channels of ADPCM audio with per-channel effects. Flycast's AICA implementation is a significant CPU consumer.
  - **Target**: `core/hw/aica/aica.cpp` — `AICA_Update()`
  - **Strategy**: Batch 64-channel ADPCM decode + mixing into a single NPU dispatch. The AICA runs at 44.1 kHz with configurable buffer sizes.
  - **Expected saving**: 5–10% CPU. On RK3566, this can push Flycast from 35 FPS to 45+ FPS in audio-heavy titles.

- **VQ texture decode** — Dreamcast uses VQ (Vector Quantization) texture compression. Decoding is a codebook lookup per 2×2 block — trivially parallelizable.
  - **Target**: `core/hw/pvr/` — texture decode path
  - **Expected saving**: 1–3% CPU

- **AI upscaling** — DC renders at 640×480 (typical). NPU upscale to 1280×960.

### 8.5 Yabasanshiro (Sega Saturn)

**Platforms**: RK3566, SM8250, SM8550, SM8650, RK3588

**Primary Bottleneck**: Dual SH-2 CPU emulation, VDP2 layer compositing, SCSP audio synthesis.

**NPU Integration Points**:

- **SCSP audio offload** — The Saturn SCSP is one of the most complex audio subsystems in retro gaming: 32-channel FM synthesis with per-channel envelopes, LFO, and effects. It consumes substantial CPU time.
  - **Target**: `yabause/src/scsp.c` — `ScspExec()` / sound generation loop
  - **Strategy**: The FM synthesis inner loop (phase accumulation, envelope, waveform lookup, mixing) over 32 channels is expressible as a batched compute operation. Marshal channel state into DMA-BUF, dispatch to NPU.
  - **Expected saving**: 8–15% CPU. Saturn emulation on RK3566 is heavily CPU-bound; SCSP offload provides meaningful FPS improvement.

- **SCU DSP offload** — The Saturn SCU DSP performs geometry transforms (matrix multiply, perspective divide). While game-dependent, titles that use the SCU heavily (Panzer Dragoon, Burning Rangers) bottleneck here.
  - **Target**: `yabause/src/scu.c` — `ScuExec()`
  - **Strategy**: Batch consecutive DSP instructions (MAC sequences) and dispatch as a single matrix operation. Only dispatch when a batch of ≥16 operations is queued, to amortize overhead.
  - **Expected saving**: 3–10% CPU on SCU-heavy titles

### 8.6 RPCS3 (PlayStation 3)

**Platforms**: RK3588, SM8550, SM8650

**Primary Bottleneck**: Cell SPU thread scheduling, RSX GPU command translation, SPU audio processing.

**NPU Integration Points**:

- **SPU audio thread offload** — PS3 games typically dedicate 1–2 SPU threads to audio processing (Dolby, SRC, mixing). These threads run tight SIMD loops. On ARM64, the SPU recompiler translates these to NEON, but the scheduling overhead across 6 emulated SPU threads is the real cost.
  - **Target**: `rpcs3/Emu/Cell/SPUThread.cpp` — SPU thread audio detection heuristic
  - **Strategy**: When an SPU thread is identified as an audio processor (by its access patterns and output buffers), redirect its output buffer processing to Hexagon DSP / NPU. This avoids recompiling and scheduling an entire SPU thread for what amounts to batch audio math.
  - **Expected saving**: 10–20% total CPU on RK3588 (freeing 1 of 6 SPU emulation threads). On SM8550 with Hexagon, this is even more significant.

- **AI upscaling** — RPCS3 rendering at 720p native, NPU upscale to 1080p.
  - **Impact**: On RK3588 where RPCS3 is marginally playable, running at 720p + NPU upscale instead of attempting 1080p native saves critical GPU resources.

### 8.7 Xemu (Original Xbox)

**Platforms**: SM8250, SM8550, SM8650

**Primary Bottleneck**: NV2A GPU emulation (GeForce 3 class), x86 CPU translation via TCG.

**NPU Integration Points**:

- **Audio offload** — Xbox APU processes 256 voices via hardware DSP. Xemu emulates this in software.
  - **Target**: `hw/xbox/mcpx/apu.c` — voice processing loop
  - **Strategy**: Batch voice decode + mixing via `npu_audio_mix()`.
  - **Expected saving**: 5–10% CPU

- **Texture decode** — Xbox uses DXT1/DXT3/DXT5 compressed textures heavily.
  - **Target**: `hw/xbox/nv2a/` — texture upload path
  - **Strategy**: Batch S3TC decompress via `npu_tex_decompress()`.
  - **Expected saving**: 2–5% CPU

### 8.8 PPSSPP (PlayStation Portable)

**Platforms**: RK3566, SM8250, SM8550, SM8650, RK3588, RK3326 (CPU fallback)

**Primary Bottleneck**: VFPU emulation, GE (Graphics Engine) command translation, Atrac3+ audio decode.

**NPU Integration Points**:

- **Atrac3+ audio decode** — PSP games use Sony's Atrac3+ codec for music. PPSSPP decodes this in software. The codec has relatively high CPU cost per frame.
  - **Target**: `Core/HW/MediaEngine.cpp` — `Atrac3plus_Decode()`
  - **Strategy**: Atrac3+ decode is a batch DSP operation (MDCT + windowing). Dispatch complete audio frames to NPU/DSP.
  - **Expected saving**: 2–5% CPU

- **AI upscaling** — PSP renders at 480×272. NPU 2× to 960×544 is visually transformative and fits comfortably in the RK3566 NPU latency budget (~2–4ms).

### 8.9 DuckStation (PlayStation 1)

**Platforms**: RK3566, SM8250, SM8550, SM8650, RK3588, RK3326 (CPU fallback)

**Primary Bottleneck**: Already runs at full speed on most platforms. Not CPU-constrained.

**NPU Integration Points**:

- **AI upscaling only** — PS1 renders at 320×240 (or 256×224). NPU 2× upscale to 640×480 provides a dramatic visual improvement with near-zero performance cost (~1–2ms on RK3566).
  - This is purely a **visual quality enhancement**, not an FPS improvement. DuckStation already hits 60 FPS.

- **No audio/texture offload needed** — PS1 audio (SPU, 24 voices) and texture decode are lightweight enough that CPU handles them trivially. NPU dispatch overhead would exceed CPU cost.

### 8.10 Box64 (x86-64 to ARM64 Translation)

**Platforms**: SM8250, SM8550, SM8650, RK3588

**Primary Bottleneck**: Instruction translation overhead, memory ordering, AVX/AVX2 emulation via NEON.

**NPU Integration Points**:

- **Audio codec offload** — When x86 games running under Box64 use software audio codecs (Vorbis, Opus, MP3, FLAC), the decode runs through Box64's translated code path, adding translation overhead on top of the codec CPU cost. Intercepting common audio codec calls and redirecting to native ARM64 DSP offload skips the translation entirely.
  - **Target**: Box64's function wrapping mechanism — intercept well-known audio codec entry points (e.g., `ov_read`, `opus_decode`, `mpg123_read`)
  - **Strategy**: When a wrapped function is detected, call the native ARM64 codec library directly (already in ROCKNIX rootfs), then optionally dispatch batch decode to NPU/DSP if the buffer is large enough.
  - **Expected saving**: 5–15% CPU for audio-heavy translated applications

- **AI upscaling** — Games running under Box64 + DXVK often render at low internal resolutions for performance. NPU upscale at the display output.

### 8.11 FEX-Emu (x86-64 to ARM64 Translation)

**Platforms**: SM8550, SM8650

**Primary Bottleneck**: Same as Box64 — translation overhead, memory ordering, signal handling.

**NPU Integration Points**:

- Same audio codec interception strategy as Box64. FEX's thunk system provides a cleaner hook point for redirecting library calls to native implementations + NPU offload.
  - **Target**: `ThunkLibs/` — audio codec thunks
  - **Strategy**: Thunks for `libvorbis`, `libopus`, `libmpg123` bypass translation entirely and call native libs. Add optional NPU batch decode within the thunk.

### 8.12 Switch Emulators (Citron / Sudachi / Eden)

**Platforms**: SM8550, SM8650, RK3588

**Primary Bottleneck**: Guest ARM JIT (Dynarmic), Maxwell GPU command translation, audio DSP.

**NPU Integration Points**:

- **Audio decode offload** — Switch games use Opus and ADPCM audio. The emulated audio DSP decodes these in software.
  - **Target**: `src/audio_core/` — `AudioRenderer` sink processing
  - **Strategy**: Batch Opus frame decode + voice mixing to Hexagon DSP / NPU. Switch audio typically has 24 voices at 48 kHz.
  - **Expected saving**: 3–8% CPU

- **AI upscaling** — Switch games render at 720p (docked) or lower. NPU upscale is viable on SM8550/SM8650 with their high-throughput NPUs, but 720p input pushes the latency budget.
  - On SM8550 (45 TOPS): 720p → 1080p via lightweight model in ~3–5ms — viable at 30fps.
  - On RK3588 (6 TOPS): Marginal. Only viable for games rendering below 720p.

### 8.13 Cemu (Wii U)

**Platforms**: SM8550, SM8650, RK3588

**Primary Bottleneck**: PowerPC Espresso JIT, GX2 to Vulkan translation.

**NPU Integration Points**:

- **Audio offload** — Wii U DSP processes 96 voices. Same batched mixing strategy.
  - **Target**: `src/Cafe/HW/Latte/AudioSystem/`
  - **Expected saving**: 5–10% CPU

- **Texture decode** — Wii U uses BC1–BC5 compressed textures. Batch decompress via NPU.
  - **Expected saving**: 2–5% CPU during streaming

### 8.14 Xenia (Xbox 360)

**Platforms**: SM8550, SM8650

**Primary Bottleneck**: Three Xenon cores (PowerPC with VMX128) via JIT, Xenos GPU translation.

**NPU Integration Points**:

- **XMA audio decode** — Xbox 360 uses XMA (a WMA variant) for all game audio. XMA decode is CPU-intensive and a known bottleneck in Xenia.
  - **Target**: `src/xenia/apu/` — XMA decoder
  - **Strategy**: XMA frame decode is a batch DSP operation. Dispatch to Hexagon DSP.
  - **Expected saving**: 5–15% CPU (XMA decode is a significant Xenia bottleneck)

- **Texture decode** — Xbox 360 uses DXT formats with Xbox-specific tiling. Untile + decompress as a batch operation.
  - **Expected saving**: 3–8% CPU during texture streaming

## 9. PC Gaming Synergy: Wine, Proton, and DXVK

Running PC games on ARM64 via Box64/FEX + Wine/Proton + DXVK involves three heavy translation layers. The NPU/DSP accelerates this stack at specific, well-defined points — not by replacing x86 instruction translation (which is per-instruction and latency-critical), but by:

1. **Offloading audio codecs** — PC games using DirectSound/XAudio2 rely on software codecs (Vorbis, Opus, MP3) that run through the x86 translation layer. Intercepting these at the Wine/native boundary and dispatching to NPU/DSP eliminates both translation overhead and CPU decode cost simultaneously.

2. **AI upscaling at the display output** — Games running under DXVK often render at reduced internal resolution for performance. NPU upscaling applied at the Wayland/display compositor level benefits all translated games uniformly without per-game configuration.

3. **Texture streaming offload** — When DXVK uploads BC1–BC7 compressed textures, batch decompress via NPU before GPU upload. This is viable on Qualcomm where freedreno handles GPU uploads directly.

**What this does NOT do**: It does not accelerate x86 instruction translation, AVX emulation, or Wine system call processing. Those remain CPU-bound. The NPU contribution is freeing the 5–15% CPU currently spent on audio/texture work so it's available for the translation layers.

## 10. IVI Validation Benchmark

The Φᵈᶜᵖ IVI algorithm serves as the **compute pipeline validation tool**. It exercises every component of the NPU acceleration stack:

- DMA-BUF allocation and zero-copy mapping
- NIR compute job submission via Rocket driver
- NPU MAC array utilization (multiply-accumulate on digit pairs)
- Job completion synchronization
- Result readback

**`projects/ROCKNIX/packages/compute/libnpu-accel/sources/tests/ivi_npu_bench.c`:**

```c
#include "npu_accel.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

/*
 * IVI NPU Benchmark
 *
 * Validates the Teflon/Rocket compute pipeline by running the IVI
 * factorization workfunction on the NPU. This exercises DMA-BUF,
 * job submission, and MAC array utilization.
 *
 * The IVI work function evaluates 100 (pk, qk) digit pairs against
 * the Diophantine constraint:
 *   sum(p_i * q_{k-i+1}) + carry_in = n_k + 10 * carry_out
 *
 * Each evaluation is a multiply-accumulate + comparison — a natural
 * fit for NPU MAC arrays.
 */

typedef struct {
    int target_digit;
    int carry_in;
    int k_depth;
    int p_history[64];
    int q_history[64];
    int hist_len;
} IVIState;

/* CPU reference implementation */
static int ivi_evaluate_cpu(IVIState* state, uint8_t* mask_out) {
    int valid = 0;
    memset(mask_out, 0, 13); /* 100 bits = 13 bytes */

    int baseSum = 0;
    for (int i = 2; i < state->k_depth; i++) {
        int p_idx = i - 1;
        int q_idx = state->k_depth - i;
        if (p_idx < state->hist_len && q_idx < state->hist_len)
            baseSum += state->p_history[p_idx] * state->q_history[q_idx];
    }

    int p1 = state->hist_len > 0 ? state->p_history[0] : 0;
    int q1 = state->hist_len > 0 ? state->q_history[0] : 0;

    for (int pk = 0; pk <= 9; pk++) {
        for (int qk = 0; qk <= 9; qk++) {
            int idx = pk * 10 + qk;
            int sum = (state->k_depth == 1)
                ? pk * qk
                : baseSum + p1 * qk + pk * q1;
            int total = sum + state->carry_in;

            if (total >= state->target_digit) {
                int rem = total - state->target_digit;
                if (rem % 10 == 0) {
                    int carry_out = rem / 10;
                    int maxCarry = (81 * state->k_depth + state->carry_in) / 10;
                    if (carry_out <= maxCarry) {
                        mask_out[idx / 8] |= (1 << (idx % 8));
                        valid++;
                    }
                }
            }
        }
    }
    return valid;
}

int main(void) {
    printf("IVI NPU Pipeline Benchmark\n");
    printf("==========================\n\n");

    NpuContext* ctx = npu_accel_init();
    NpuCaps caps = npu_accel_caps(ctx);

    printf("Platform: %s\n",
           caps.has_npu ? "Rocket NPU" :
           caps.has_dsp ? "Hexagon DSP" : "CPU only (no accelerator)");
    printf("Compute: %d TOPS\n\n", caps.npu_tops);

    /* Benchmark: 1000 IVI evaluations (simulating frontier processing) */
    IVIState state = {
        .target_digit = 7,
        .carry_in = 3,
        .k_depth = 5,
        .p_history = {3, 1, 7, 9},
        .q_history = {9, 3, 1, 7},
        .hist_len = 4
    };

    uint8_t mask[13];
    int iterations = 1000;

    /* CPU baseline */
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < iterations; i++) {
        ivi_evaluate_cpu(&state, mask);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);

    double cpu_us = (t1.tv_sec - t0.tv_sec) * 1e6 +
                    (t1.tv_nsec - t0.tv_nsec) / 1e3;
    printf("CPU: %d iterations in %.1f us (%.2f us/iter)\n",
           iterations, cpu_us, cpu_us / iterations);

    /* NPU dispatch (if available) */
    if (caps.has_npu || caps.has_dsp) {
        NpuBuffer* in_buf = npu_buffer_alloc(ctx, sizeof(IVIState) * iterations);
        NpuBuffer* out_buf = npu_buffer_alloc(ctx, 13 * iterations);

        /* Fill input buffer with repeated states */
        IVIState* in_ptr = (IVIState*)npu_buffer_map(in_buf);
        for (int i = 0; i < iterations; i++)
            memcpy(&in_ptr[i], &state, sizeof(IVIState));

        clock_gettime(CLOCK_MONOTONIC, &t0);
        /* Batch dispatch all iterations as a single NPU job */
        /* npu_ivi_batch(ctx, in_buf, out_buf, iterations); */
        clock_gettime(CLOCK_MONOTONIC, &t1);

        double npu_us = (t1.tv_sec - t0.tv_sec) * 1e6 +
                        (t1.tv_nsec - t0.tv_nsec) / 1e3;
        printf("NPU: %d iterations in %.1f us (%.2f us/iter)\n",
               iterations, npu_us, npu_us / iterations);
        printf("Speedup: %.1fx\n", cpu_us / npu_us);

        npu_buffer_free(in_buf);
        npu_buffer_free(out_buf);
    }

    npu_accel_destroy(ctx);
    return 0;
}
```

## 11. Implementation Roadmap

### Phase 0: Kernel / Driver Foundation
1. Enable `CONFIG_DRM_ACCEL=y` + `CONFIG_ACCEL_ROCKET=m` on RK3566 and RK3588
2. Remove BSP `CONFIG_ROCKCHIP_RKNPU` from RK3588 config
3. Verify NPU device tree nodes are enabled on both platforms
4. Promote SDM845 `CONFIG_QCOM_FASTRPC` from `=m` to `=y`
5. Build-test all affected kernel configs
6. Validate `/dev/accel/accel0` appears on RK3566 and RK3588 boots

### Phase 1: Mesa Teflon / Rocket Userspace
1. Create `mesa-npu` package with Rocket gallium driver + Teflon runtime
2. Verify no GL/Vulkan/EGL symbol conflicts with libmali
3. Validate Teflon model loading and compute dispatch on RK3566 hardware
4. Run IVI validation benchmark (§10) to prove the full pipeline

### Phase 2: `libnpu-accel` Middleware
1. Implement Rocket NPU backend (buffer alloc, model load, job submit)
2. Implement Hexagon DSP backend (FastRPC calls)
3. Implement CPU fallback paths for all APIs
4. Implement `npu_upscale_*` with pre-trained INT8 SR models
5. Implement `npu_audio_mix` with batched ADPCM decode + mixing
6. Implement `npu_tex_decompress` for S3TC/DXT1
7. Package as `libnpu-accel` with proper ROCKNIX build integration

### Phase 3: AI Upscaling Integration (Highest Impact)
1. Integrate `npu_upscale_frame()` into ROCKNIX display output pipeline
2. Train/quantize lightweight SR models (ESPCN, FSRCNN) for INT8 NPU
3. Add per-emulator upscale configuration (model quality, scale factor)
4. Benchmark on RK3566 across PS1, 3DS, GBA, Saturn, Dreamcast targets
5. Validate visual quality vs. existing software upscale filters

### Phase 4: Audio Offload (Per-Emulator)
1. Flycast AICA offload (64-voice, well-documented audio path)
2. Yabasanshiro SCSP offload (32-voice FM synthesis)
3. Azahar 3DS audio HLE offload (24-voice)
4. Dolphin DSP HLE offload (64-voice ADPCM)
5. Benchmark CPU savings on RK3566 for each emulator

### Phase 5: Texture Decode + Remaining Emulators
1. Dolphin CMPR texture batch decode
2. Flycast VQ texture decode
3. Xemu DXT texture decode
4. AetherSX2 SPU2 offload (via LRPS2 fork or LD_PRELOAD)
5. RPCS3 SPU audio thread detection + offload (RK3588/SM8550)
6. Switch emulator audio offload (SM8550/SM8650)

### Phase 6: Box64/FEX Audio Codec Interception
1. Box64 wrapper functions for libvorbis, libopus, libmpg123
2. FEX thunk implementations for same codecs
3. Optional NPU batch decode within wrappers
4. Benchmark PC gaming audio overhead reduction
