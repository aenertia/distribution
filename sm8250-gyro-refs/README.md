# SM8250 Gyro/IMU IIO Reference Artifacts

Reference material for implementing a QRTR→IIO daemon to expose Qualcomm SSC
(Snapdragon Sensor Core) sensors as Linux IIO devices on SM8250 (Kona) SoCs.

## Artifact Index

| Path | Source URL | Purpose |
|------|-----------|---------|
| `patches-v2/v2-series.mbox` | [patchew.org](https://patchew.org/linux/20250710-qcom-smgr-v2-0-f6e198b7aa8e@protonmail.com/mbox) | Yassine Oudjana's v2 QRTR bus + Qualcomm Sensor Manager IIO driver patch series |
| `references/libssc/` | [codeberg.org/DylanVanAssche/libssc](https://codeberg.org/DylanVanAssche/libssc) | Reference SSC client library with protobuf `.proto` definitions for SSC wire format |
| `references/sns-reg/` | [gitlab.com/msm8996-mainline/sns-reg](https://gitlab.com/msm8996-mainline/sns-reg) | Sensor registry daemon — generates sensor config from device tree for SSC |
| `references/protocol-blog-p1.md` | [emainline.gitlab.io (Oct 2021)](https://emainline.gitlab.io/2021/10/06/Unlocking_SSC_P1.html) | Blog: "Unlocking the Qualcomm Snapdragon Sensor Core" Part 1 — SLPI boot/DT setup |
| `references/protocol-blog-p2.md` | [emainline.gitlab.io (Apr 2022)](https://emainline.gitlab.io/2022/04/08/Unlocking_SSC_P2.html) | Blog: Part 2 — strace-based protocol reverse engineering, QRTR message decoding |
| `references/vendor-configs/` | Extracted from stock RP5 firmware (`/tmp/rp5-stock/vendor-sensors/config/`) | 81 vendor JSON sensor configs (kona_lsm6dst_0.json, sns_gyro_cal.json, etc.) |
| `pmaports/mr4118.md` | [gitlab.postmarketos.org MR#4118](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/4118) | postmarketOS pmaports MR: "Qualcomm Sensor Manager support (MSM8996 & Co. SSC)" |
| `hexagonrpc/` | [github.com/linux-msm/hexagonrpc](https://github.com/linux-msm/hexagonrpc) v0.4.0 | hexagonrpcd daemon — serves AP filesystem to SLPI via FastRPC so SLPI sensor PD can read JSON sensor configs |

## V2 Patch Series (4 patches)

1. `[PATCH v2 1/4] net: qrtr: smd: Rename qdev to qsdev` — Prep rename to avoid conflict with QRTR bus device
2. `[PATCH v2 2/4] net: qrtr: Turn QRTR into a bus` — Converts QRTR from netlink-only to a proper Linux bus
3. `[PATCH v2 3/4] net: qrtr: Define macro to convert QMI version and instance to QRTR instance` — Helper for service matching
4. `[PATCH v2 4/4] iio: Add Qualcomm Sensor Manager driver` — The actual IIO driver using QRTR bus to talk to SSC

## Critical Files

### Protobuf Definitions (libssc)
The `.proto` files define the SSC wire protocol — these are the MOST CRITICAL artifacts:
- `data/ssc-common.proto` — Common message types
- `data/ssc-sensor-accelerometer.proto` — Accel sensor events
- `data/ssc-sensor-gyroscope.proto` — Gyro sensor events
- `data/ssc-sensor-suid.proto` — Sensor UID lookup
- `data/ssc-sensor-light.proto`, `ssc-sensor-magnetometer.proto`, etc.

### Key Vendor Configs
- `vendor-configs/kona_lsm6dst_0.json` — Primary LSM6DST (accel+gyro) config for Kona/SM8250
- `vendor-configs/kona_lsm6dst_1.json` — Secondary LSM6DST instance
- `vendor-configs/kona_default_sensors.json` — Default sensor platform config
- `vendor-configs/sns_gyro_cal.json` — Gyroscope calibration parameters

## hexagonrpcd Virtual Filesystem Layout

hexagonrpcd maps SLPI-requested paths to physical paths under `-R <rootdir>`. The physical rootdir (e.g. `/storage/dsp/`) must have this structure:

```
<rootdir>/
└── sensors/
    ├── config/                  ← SLPI sees as /vendor/etc/sensors/config/ and /system/etc/sensors/config/
    │   ├── kona_lsm6dst_0.json  ← 81 vendor JSON sensor configs
    │   └── ...
    ├── registry/                ← SLPI sees as /persist/sensors/registry/
    ├── sns_reg.conf             ← SLPI sees as /vendor/etc/sensors/sns_reg_config (OMIT if empty — empty causes crash)
    └── sns_reg_version          ← appears at root of SLPI virtual FS as sns_reg_version
```

The virtual FS also provides (from rootdir subdirs):
- `acdb/` → SLPI sees `/vendor/etc/acdbdata`
- `dsp/<dsp>/` → SLPI sees `/usr/lib/qcom/adsp` ($ADSP_LIBRARY_PATH)
- `socinfo/` → SLPI sees `/sys/devices/soc0`

**CRITICAL**: `sns_reg.conf` must NOT be a 0-byte file — SLPI tries to parse it as a sensor registry and crashes if empty. Either omit it or provide valid content.

## Notes

- The v1 patch series (3 patches, April 2025) is superseded by v2 (4 patches, July 2025)
- `patches-v1/` directory exists but is intentionally empty — v1 is obsolete
- LWN coverage of the patch series: https://lwn.net/Articles/1016590/
- The pmaports MR#4118 is in "Draft" state and marked stale as of fetch date
- hexagonrpc v0.4.0 uses short CLI flags: `-f /dev/fastrpc-sdsp -s -R /storage/dsp` (NOT `--domain`, `--rootdir`)
- `/dev/fastrpc-sdsp` only appears when SLPI remoteproc is in `running` state — hexagonrpcd must start AFTER SLPI boots
