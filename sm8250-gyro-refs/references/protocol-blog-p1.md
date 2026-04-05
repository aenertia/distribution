Unlocking the Qualcomm Snapdragon Sensor Core

[-EMAINLINE](https://emainline.gitlab.io)

[

Home

](/)

[

About

](/about.html)

[

](/feed.xml)

# Unlocking the Qualcomm Snapdragon Sensor Core

## Part 1: Preparation

Yassine Oudjana

Posted on 6th Oct 2021

Sensors have generally been some of the easier components to support on the mainline Linux kernel; considering that on most devices, all it takes to enable a sensor is to enable the I2C or SPI interface it is connected to, describe it in the device tree, and in the worst case scenario, write a driver for it with the help of detailed, publicly available datasheets.

This, however, became longer the case in devices using Qualcomm SoCs. With the release of the Snapdragon 820, the Snapdragon Sensor Core (SSC) – sometimes also referred to as the Sensor Low Power Island (SLPI) – was introduced. It is a sensor hub consisting of GPIOs that provide I2C, SPI and serial interfaces to receive data from sensors, and a Hexagon core to process the data. It was introduced as a power-saving measure which reduces power consumption by offloading the processing of sensor data to a low-power DSP, allowing the more power-hungry CPUs to work less and even be put to deeper sleep states when idle.

Unfortunately, this means that handling sensors is entirely done in proprietary firmware which communicates with a proprietary HAL driver on Android. With no source code nor documentation, we are left with nothing to work with on Linux. What makes matters worse is that there is no way, at least on consumer devices, to bypass SSC entirely and directly access the GPIOs to which the sensors are connected. If this was possible, it would have at least allowed for driving them similar to older devices, albeit with a degradation in idle battery life.

This series will go through the process of reverse engineering the proprietary driver for SSC on Snapdragon 820, and in the end, hopefully writing an open source driver to make use of SSC on Linux.

I will be testing on the [Xiaomi Mi Note 2](https://emainline.gitlab.io/about.html#xiaomi-mi-note-2) in this series.

The model name of Snapdragon 820 is MSM8996, and as so it will be referred to as that throughout this series.

## First steps

Before doing any actual reversing, it must be made sure that SLPI can be booted on Linux.
The `qcom_q6v5_pas` kernel driver handles loading firmware into and booting QDSP6 – or Hexagon – remote processors such as SLPI and ADSP. The firmware is first loaded into a predefined region of memory and authenticated in the secure world, then the remote processor gets reset and starts executing it. These memory regions should be reserved so that Linux does not map them, and leaves them to be exclusively used by the remote processor and the driver that loads its firmware. These are the reserved memory regions originally defined in the MSM8996 device tree:

```
reserved-memory {
#address-cells = <2>;
#size-cells = <2>;
ranges;

mba_region: mba@91500000 {
reg = <0x0 0x91500000 0x0 0x200000>;
no-map;
};

slpi_region: slpi@90b00000 {
reg = <0x0 0x90b00000 0x0 0xa00000>;
no-map;
};

venus_region: venus@90400000 {
reg = <0x0 0x90400000 0x0 0x700000>;
no-map;
};

adsp_region: adsp@8ea00000 {
reg = <0x0 0x8ea00000 0x0 0x1a00000>;
no-map;
};

mpss_region: mpss@88800000 {
reg = <0x0 0x88800000 0x0 0x6200000>;
no-map;
};

smem_mem: smem-mem@86000000 {
reg = <0x0 0x86000000 0x0 0x200000>;
no-map;
};

memory@85800000 {
reg = <0x0 0x85800000 0x0 0x800000>;
no-map;
};

memory@86200000 {
reg = <0x0 0x86200000 0x0 0x2600000>;
no-map;
};

rmtfs@86700000 {
compatible = "qcom,rmtfs-mem";

size = <0x0 0x200000>;
alloc-ranges = <0x0 0xa0000000 0x0 0x2000000>;
no-map;

qcom,client-id = <1>;
qcom,vmid = <15>;
};

zap_shader_region: gpu@8f200000 {
compatible = "shared-dma-pool";
reg = <0x0 0x90b00000 0x0 0xa00000>;
no-map;
};
};

```

Taking a closer look at `slpi_region` and `zap_shader_region`, it seems that somehow they ended
up having the same address:

```
slpi_region: slpi@90b00000 {
reg = <0x0 0x90b00000 0x0 0xa00000>;
no-map;
};

```

```
zap_shader_region: gpu@8f200000 {
compatible = "shared-dma-pool";
reg = <0x0 0x90b00000 0x0 0xa00000>;
no-map;
};

```

This will cause problems, as both the GPU and SLPI drivers will try to load firmware into the same region. Fixing this is required before doing anything about SLPI.

Looking at the downstream kernel, there are no specific memory regions for each remote processor, but rather [one big shared region](https://github.com/LineageOS/android_kernel_xiaomi_msm8996/blob/lineage-17.1/arch/arm/boot/dts/qcom/msm8996.dtsi#L189-L193):

```
peripheral_mem: peripheral_region@8ea00000 {
compatible = "removed-dma-pool";
no-map;
reg = <0 0x8ea00000 0 0x2d00000>;
};

```

Fortunately though, the downstream drivers report the memory ranges they load firmware into in the kernel log:

```
# dmesg | grep "loading from"
[   10.272396] subsys-pil-tz 1c00000.qcom,ssc: slpi: loading from 0x000000008fe00000 to 0x0000000090800000
[   10.273749] subsys-pil-tz 9300000.qcom,lpass: adsp: loading from 0x0000000090800000 to 0x0000000092300000
[   11.229705] pil-q6v5-mss 2080000.qcom,mss: modem: loading from 0x0000000089c00000 to 0x000000008fe00000
[   11.751973] subsys-pil-tz soc:qcom,kgsl-hyp: a530_zap: loading from 0x0000000092300000 to 0x0000000092302000
[   26.233731] subsys-pil-tz ce0000.qcom,venus: venus: loading from 0x0000000092400000 to 0x0000000092900000

```

Comparing those ranges to `peripheral_mem` above, it is found that they are actually shifted forward by 0x1400000 on this device, and this is further confirmed by taking a quick look at [the device DTS](https://github.com/LineageOS/android_kernel_xiaomi_msm8996/blob/lineage-17.1/arch/arm/boot/dts/qcom/msm8996-xiaomi-common.dtsi#L1815-L1820), where the original region defined in the SoC DTS is overwritten:

```
/delete-node/ peripheral_region@8ea00000;
peripheral_mem: peripheral_region@8fe00000 {
compatible = "removed-dma-pool";
no-map;
reg = <0x0 0x8fe00000 0x0 0x2b00000>;
};

```

Putting all of this information together gives the final regions:

Region
Address
Size

MPSS
`0x88800000`
`0x6200000`

ADSP
`0x8ea00000`
`0x1b00000`

SLPI
`0x90500000`
`0xa00000`

GPU (Zap Shader)
`0x90f00000`
`0x100000`

Venus
`0x91000000`
`0x500000`

MBA
`0x91500000`
`0x200000`

[This patch](https://lore.kernel.org/linux-arm-msm/20210926190555.278589-2-y.oudjana@protonmail.com/) takes those regions and defines them in the SoC DTS, and updates the shifted ranges in the device DTS to match.

With reserved memory taken care of, now we can start working on booting SLPI.

## Adding SLPI to the device tree

Following the [device tree schema for `qcom_q6v5_pas`](https://gitlab.com/msm8996-mainline/linux-msm8996/-/blob/msm8996-staging/Documentation/devicetree/bindings/remoteproc/qcom,adsp.yaml), we can start writing a node for SLPI, with [`reg` taken from the downstream device tree](https://github.com/LineageOS/android_kernel_xiaomi_msm8996/blob/lineage-17.1/arch/arm/boot/dts/qcom/msm8996.dtsi#L2355):

```
slpi_pil: remoteproc@1c00000 {
compatible = "qcom,msm8996-slpi-pil";
reg = <0x01c00000 0x4000>;
};

```

### Interrupts

There are five interrupts in total: [One real interrupt](https://github.com/LineageOS/android_kernel_xiaomi_msm8996/blob/lineage-17.1/arch/arm/boot/dts/qcom/msm8996.dtsi#L2356)  belonging to the global interrupt controller used for a watchdog signal, and [four virtual SMP2P (Shared Memory Point to Point) interrupts](https://github.com/LineageOS/android_kernel_xiaomi_msm8996/blob/lineage-17.1/arch/arm/boot/dts/qcom/msm8996.dtsi#L2379-L2382) used to signal various events. Details about shared memory will come later.

```
slpi_pil: remoteproc@1c00000 {
...
interrupts-extended = <&intc 0 390 IRQ_TYPE_EDGE_RISING>,
<&slpi_smp2p_in 0 IRQ_TYPE_EDGE_RISING>,
<&slpi_smp2p_in 1 IRQ_TYPE_EDGE_RISING>,
<&slpi_smp2p_in 2 IRQ_TYPE_EDGE_RISING>,
<&slpi_smp2p_in 3 IRQ_TYPE_EDGE_RISING>;
interrupt-names = "wdog",
"fatal",
"ready",
"handover",
"stop-ack";
};

```

### Clocks

There are [two clocks](https://github.com/LineageOS/android_kernel_xiaomi_msm8996/blob/lineage-17.1/arch/arm/boot/dts/qcom/msm8996.dtsi#L2364-L2366) driving SLPI: One is the on-board oscillator (`xo_board`), and the other is the bus clock of the NoC (Network-on-Chip) SLPI is connected to (`aggre2`):

```
slpi_pil: remoteproc@1c00000 {
...
clocks = <&xo_board>,
<&rpmcc RPM_SMD_AGGR2_NOC_CLK>;
clock-names = "xo", "aggre2";
};

```

### Memory region

A reference to the reserved memory region defined earlier is needed to load firmware into:

```
slpi_pil: remoteproc@1c00000 {
...
memory-region = <&slpi_mem>;
};

```

### Shared memory

Qualcomm SoCs make use of a region in memory that is shared between multiple processors on the SoC, through which the CPU – usually referred to as the AP, or Application Processor – can communicate with remote processors on the chip. Each processor, or shared memory device (SMD), is called an “edge”, and has a unique identifier `smd-edge`, as well as a remote identifier `remote-pid` used by other processors to refer to it. They also use interrupts and mailbox doorbells to signal events such as opening a SMD channel or receiving a message.

`remote-pid` has alredy been added to the [mainline DTS in the SLPI SMP2P node](https://gitlab.com/msm8996-mainline/linux-msm8996/-/blob/v5.14/arch/arm64/boot/dts/qcom/msm8996.dtsi#L562), so it can be simply copied over:

```
slpi_pil: remoteproc@1c00000 {
...
smd-edge {
qcom,remote-pid = <3>;
};
};

```

Searching for `dsps` which is the SMD label for SLPI, the remaining properties are found:

```
qcom,smd-dsps {
compatible = "qcom,smd";
qcom,smd-edge = <3>;
qcom,smd-irq-offset = <0x0>;
qcom,smd-irq-bitmask = <0x2000000>;
interrupts = <0 176 1>;
label = "dsps";
};

```

`smd-edge`, `label`, as well as a single interrupt are all clear, so they can be directly added to our SLPI node:

```
slpi_pil: remoteproc@1c00000 {
...
smd-edge {
interrupts = <GIC_SPI 176 IRQ_TYPE_EDGE_RISING>;

label = "dsps";
qcom,smd-edge = <3>;
qcom,remote-pid = <3>;
};
};

```

The mailbox doorbell was not obvious though; it took me a while to figure out that it was actually the position of the enabled bit in `smd-irq-bitmask`, which is 25 here. Adding that completes the smd-edge subnode:

```
slpi_pil: remoteproc@1c00000 {
...
smd-edge {
interrupts = <GIC_SPI 176 IRQ_TYPE_EDGE_RISING>;

label = "dsps";
mboxes = <&apcs_glb 25>;
qcom,smd-edge = <3>;
qcom,remote-pid = <3>;
};
};

```

The last thing to add is `qcom,smem-states`, which are according to the [DT schema](https://gitlab.com/msm8996-mainline/linux-msm8996/-/blob/msm8996-staging/Documentation/devicetree/bindings/remoteproc/qcom%2Cadsp.yaml#L98), “states used by the AP to signal the Hexagon core”. In this case, there is only one state:

```
slpi_pil: remoteproc@1c00000 {
...
qcom,smem-states = <&slpi_smp2p_out 0>;
qcom,smem-state-names = "stop";

smd-edge {
...
};
};

```

### Final Touches

To finish it off, the node is disabled by default to make SLPI optional since not all devices use it:

```
slpi_pil: remoteproc@1c00000 {
...
status = "disabled";
...
};

```

And with that done, the node is complete:

```
slpi_pil: remoteproc@1c00000 {
compatible = "qcom,msm8996-slpi-pil";
reg = <0x01c00000 0x4000>;

interrupts-extended = <&intc 0 390 IRQ_TYPE_EDGE_RISING>,
<&slpi_smp2p_in 0 IRQ_TYPE_EDGE_RISING>,
<&slpi_smp2p_in 1 IRQ_TYPE_EDGE_RISING>,
<&slpi_smp2p_in 2 IRQ_TYPE_EDGE_RISING>,
<&slpi_smp2p_in 3 IRQ_TYPE_EDGE_RISING>;
interrupt-names = "wdog",
"fatal",
"ready",
"handover",
"stop-ack";

clocks = <&xo_board>,
<&rpmcc RPM_SMD_AGGR2_NOC_CLK>;
clock-names = "xo", "aggre2";

memory-region = <&slpi_mem>;

qcom,smem-states = <&slpi_smp2p_out 0>;
qcom,smem-state-names = "stop";

status = "disabled";

smd-edge {
interrupts = <GIC_SPI 176 IRQ_TYPE_EDGE_RISING>;

label = "dsps";
mboxes = <&apcs_glb 25>;
qcom,smd-edge = <3>;
qcom,remote-pid = <3>;
};
};

```

### Enabling SLPI

With the SLPI node added to the SoC DTS, what remains is to enable it in the device DTS and add a firmware path to load device-specific firmware, as well as the PX supply, which can be found in the [downstream DTS](https://github.com/LineageOS/android_kernel_xiaomi_msm8996/blob/lineage-17.1/arch/arm/boot/dts/qcom/msm8996.dtsi#L2359):

```
&slpi_pil {
status = "okay";

px-supply = <&vreg_lvs2a_1p8>;
firmware-name = "qcom/msm8996/scorpio/slpi.mbn";
};

```

## Getting firmware

SLPI firmware can be found in `/vendor/firmware_mnt/image` on this device:

```
# ls /vendor/firmware_mnt/image | grep slpi
slpi_a1.b00
slpi_a1.b01
slpi_a1.b02
slpi_a1.b03
slpi_a1.b04
slpi_a1.b05
slpi_a1.b06
slpi_a1.b07
slpi_a1.b08
slpi_a1.b09
slpi_a1.b10
slpi_a1.b11
slpi_a1.b12
slpi_a1.b13
slpi_a1.b14
slpi_a1.mdt
slpi_a4.b00
slpi_a4.b01
slpi_a4.b02
slpi_a4.b03
slpi_a4.b04
slpi_a4.b05
slpi_a4.b06
slpi_a4.b07
slpi_a4.b08
slpi_a4.b09
slpi_a4.b10
slpi_a4.b11
slpi_a4.b12
slpi_a4.b13
slpi_a4.b14
slpi_a4.mdt
slpi_a7.b00
slpi_a7.b01
slpi_a7.b02
slpi_a7.b03
slpi_a7.b04
slpi_a7.b05
slpi_a7.b06
slpi_a7.b07
slpi_a7.b08
slpi_a7.b09
slpi_a7.b10
slpi_a7.b11
slpi_a7.b12
slpi_a7.b13
slpi_a7.b14
slpi_a7.mdt

```

For some reason, Xiaomi decided to ship SLPI firmware for all of their MSM8996 devices on each one of them. The Mi Note 2 is A4 according to the [downstream kernel](https://github.com/LineageOS/android_kernel_xiaomi_msm8996/blob/lineage-17.1/drivers/platform/xiaomi/Kconfig#L24-L28), so the `slpi_a4.*` files are what we are looking for.

While it is possible to use the firmware in its current segmented form, combining the segments into one file is preferred. This can be done using [`pil-squasher`](https://github.com/andersson/pil-squasher). The result is a single `.mbn` file.

## Testing

With all of that done, it is time to test everything added so far. If all goes well, a message confirming the successful boot of SLPI should be found in the kernel log.

…But of course, things do not always go as planned.

```
# dmesg | grep 1c00000
[    6.952588] qcom_q6v5_pas 1c00000.remoteproc: supply cx not found, using dummy regulator
[    7.065288] remoteproc remoteproc0: 1c00000.remoteproc is available
[    7.107279] remoteproc remoteproc0: powering up 1c00000.remoteproc
[    7.189399] qcom_q6v5_pas 1c00000.remoteproc: failed to authenticate image and release reset
[    7.192502] remoteproc remoteproc0: can't start rproc 1c00000.remoteproc: -22

```

### Troubleshooting

Upon further investigation, I found that there is a missing power domain that has to be voted on. Power domains are basically regulators or other resources used by multiple parts of the system usually having different power requirements. Consumers attach to the power domain, then request it to be turned on, and in some cases, set the performance level to fulfill their needs. The power domain then is set to the highest performance level requested in order to statisfy all consumers.

A [patch](https://lore.kernel.org/linux-arm-msm/20210926190555.278589-3-y.oudjana@protonmail.com/) to `qcom_q6v5_pas` was needed to make it attach to the power domain that powers SLPI. Once that was done, the power domain had to be added to the DTS node:

```
slpi_pil: remoteproc@1c00000 {
...
power-domains = <&rpmpd MSM8996_VDDSSCX>;
power-domain-names = "ssc_cx";
...
};

```

Now SLPI boots successfully:

```
# dmesg | grep 1c00000
[    6.952588] qcom_q6v5_pas 1c00000.remoteproc: supply cx not found, using dummy regulator
[    7.065288] remoteproc remoteproc0: 1c00000.remoteproc is available
[    7.107279] remoteproc remoteproc0: powering up 1c00000.remoteproc
[   15.117415] remoteproc remoteproc1: remote processor 1c00000.remoteproc is now up

```

QMI services provided by SLPI can be found using `qrtr-lookup`:

```
$ qrtr-lookup
Service Version Instance Node  Port
...
15       1        8    9     1 Test service
66       1       20    9     4 Service registry notification service
43       2       22    9     6 Subsystem control service
15       1        9    9     7 Test service
771       1        1    9     9 Peripheral Access Control Manager service

```

[The final patchset](https://lore.kernel.org/linux-arm-msm/20210926190555.278589-1-y.oudjana@protonmail.com/) also includes bringing up the modem, which is done in a similar way.

With SLPI booting on the mainline kernel, it is time to start communicating with it.
Part 2 will cover decoding messages dumped from the proprietary HAL driver in order to understand the way it talks to the remote processor, then attempt to do the same in the open source driver.

`return -EMAINLINE;`

[

](https://ko-fi.com/X8X4EKZJ1)

[
@y_oudjana

](https://twitter.com/y_oudjana)

@tooniis:matrix.org

[
Tooniis
](https://gitlab.com/Tooniis)

