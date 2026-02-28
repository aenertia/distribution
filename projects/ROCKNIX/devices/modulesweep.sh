#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) ROCKNIX
# Copyright (C) Joel Wirāmu Pauling <aenertia@aenertia.net>
#
# README:
# This script should be run from the top level ROCKNIX/devices tree.
# It recursively finds linux configuration files and applies optimization blocks.
#
# ORGANIZATION:
# Configuration blocks are organized in Parent:Child hierarchy to allow for
# granular cherry-picking of features in future revisions.
#
# USAGE:
# Default (Network Only):  ./modulesweep.sh
# Enable Platform Fixes:   ENABLE_PLATFORM=true ./modulesweep.sh
# Enable Debloat:          ENABLE_DEBLOAT=true ./modulesweep.sh
# Enable Tuning:           ENABLE_SCHED_TUNING=true ./modulesweep.sh
# Enable Containers:       ENABLE_CONTAINERS=true ./modulesweep.sh
# Full Optimization:       ENABLE_ALL=true ./modulesweep.sh

# ==============================================================================
# ROCKNIX KERNEL OPTIMIZER V38 - "STRICT NETWORK DEFAULT"
# ==============================================================================

# ------------------------------------------------------------------------------
# [PARENT] NETWORKING (DEFAULT ENABLED)
# ------------------------------------------------------------------------------

# [Child] Base Protocols & TCP Congestion
NET_BASE_PROTOCOLS="
CONFIG_TCP_CONG_ADVANCED=y
CONFIG_TCP_CONG_BBR=y
CONFIG_DEFAULT_BBR=y
CONFIG_DEFAULT_TCP_CONG=\"bbr\"
CONFIG_NET_SCH_FQ_CODEL=y
CONFIG_NET_SCH_DEFAULT=y
CONFIG_DEFAULT_FQ_CODEL=y
CONFIG_DEFAULT_NET_SCH=\"fq_codel\"
CONFIG_IP_ADVANCED_ROUTER=y
CONFIG_IP_MULTIPLE_TABLES=y
CONFIG_IPV6=y
CONFIG_IPV6_MULTIPLE_TABLES=y
CONFIG_IPV6_MROUTE=y
CONFIG_IPV6_ROUTER_PREF=y
CONFIG_IPV6_OPTIMISTIC_DAD=y
"

# [Child] Netfilter Infrastructure (Conntrack/Logging)
NET_NETFILTER_CORE="
CONFIG_NF_CONNTRACK=y
CONFIG_NF_CONNTRACK_PROCFS=y
CONFIG_NETFILTER_NETLINK=m
CONFIG_NETFILTER_NETLINK_GLUE_CT=y
CONFIG_BRIDGE_NETFILTER=m
"

# [Child] Modern NFTables (Enabled) vs Legacy Compat (Disabled)
NET_NFTABLES_MODERN="
CONFIG_NF_TABLES=m
CONFIG_NFT_COMPAT=n
CONFIG_IP_NF_FILTER=y
CONFIG_IP_NF_TARGET_REJECT=y
CONFIG_IP_NF_MANGLE=y
"

# [Child] Legacy IPTables Support (User-space compatibility)
NET_IPTABLES_LEGACY="
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_IPTABLES_LEGACY=y
CONFIG_IP6_NF_IPTABLES=m
CONFIG_IP6_NF_IPTABLES_LEGACY=m
"

# [Child] Virtual Interfaces & Bridging
# Kept modular to reduce boot overhead unless needed (Hotspot/Containers).
NET_VIRTUAL_IFACES="
CONFIG_VETH=m
CONFIG_BRIDGE=m
"

# [Child] VPN & Tunnels (Core Requirement)
NET_VPN_TUNNELS="
CONFIG_TUN=m
CONFIG_WIREGUARD=m
"

# [Child] USB Networking Drivers (Common Dongles)
# Moved to SAFE_MODULES (Platform Fixes) as they are hardware support, not core net architecture.

# >> AGGREGATE: CORE_NET
# Combines all networking children into the master variable applied by the loop.
# This is the ONLY block applied by default in V38.
CORE_NET="${NET_BASE_PROTOCOLS} ${NET_NETFILTER_CORE} ${NET_NFTABLES_MODERN} ${NET_IPTABLES_LEGACY} ${NET_VPN_TUNNELS} ${NET_VIRTUAL_IFACES}"


# ------------------------------------------------------------------------------
# [PARENT] INPUT & PERIPHERALS (TOGGLE: ENABLE_PLATFORM)
# ------------------------------------------------------------------------------

# [Child] USB Networking Drivers (Common Dongles)
NET_USB_ADAPTERS="
CONFIG_USB_NET_DRIVERS=m
CONFIG_USB_RTL8152=m
CONFIG_USB_USBNET=m
CONFIG_USB_NET_AX8817X=m
CONFIG_USB_NET_AX88179_178A=m
CONFIG_USB_NET_CDCETHER=m
CONFIG_USB_NET_SMSC95XX=m
CONFIG_USB_NET_ASIX=m
"

# [Child] Joystick Core (Legacy & Xpad)
INPUT_JOYSTICK_CORE="
CONFIG_JOYSTICK_XPAD=m
CONFIG_JOYSTICK_XPAD_FF=y
CONFIG_JOYSTICK_XPAD_LEDS=y
CONFIG_JOYSTICK_PSXPAD_SPI=m
"

# [Child] Gamepad Drivers (Vendor Specific)
INPUT_GAMEPADS_EXTRA="
CONFIG_HID_STEAM=m
CONFIG_STEAM_FF=y
CONFIG_HID_NINTENDO=m
CONFIG_NINTENDO_FF=y
CONFIG_HID_SONY=m
CONFIG_SONY_FF=y
CONFIG_HID_PLAYSTATION=m
CONFIG_PLAYSTATION_FF=y
CONFIG_HID_DRAGONRISE=m
CONFIG_DRAGONRISE_FF=y
CONFIG_HID_GREENASIA=m
CONFIG_GREENASIA_FF=y
CONFIG_HID_PANTHERLORD=m
CONFIG_PANTHERLORD_FF=y
CONFIG_HID_SMARTJOYPLUS=m
CONFIG_SMARTJOYPLUS_FF=y
CONFIG_HID_ZEROPLUS=m
CONFIG_ZEROPLUS_FF=y
"

# [Child] Touchscreens (Handheld Critical)
# Must be built-in (=y) to avoid UI race conditions at boot.
INPUT_TOUCHSCREEN_HANDHELD="
CONFIG_INPUT_JOYDEV=m
CONFIG_TOUCHSCREEN_GOODIX=y
CONFIG_TOUCHSCREEN_ELAN=y
CONFIG_TOUCHSCREEN_EDT_FT5X06=y
CONFIG_TOUCHSCREEN_FTS=y
"

# [Child] Tablets & Digitisers
INPUT_TABLETS="
CONFIG_HID_WACOM=m
CONFIG_HID_UCLOGIC=m
"

# [Child] Audio & MIDI
INPUT_AUDIO_MIDI="
CONFIG_SND_RAWMIDI=m
CONFIG_SND_SEQ_MIDI=m
CONFIG_SND_USB_AUDIO=m
CONFIG_SND_USB_AUDIO_USE_MEDIA_CONTROLLER=y
"

# ------------------------------------------------------------------------------
# [PARENT] FILESYSTEMS & STORAGE (TOGGLE: ENABLE_PLATFORM)
# ------------------------------------------------------------------------------

# [Child] Recovery & Boot (FAT/ExFAT)
FS_CORE_RECOVERY="
CONFIG_FAT_FS=y
CONFIG_VFAT_FS=y
CONFIG_EXFAT_FS=y
CONFIG_FAT_DEFAULT_UTF8=y
CONFIG_NLS_CODEPAGE_437=y
CONFIG_NLS_ISO8859_1=y
CONFIG_NLS_UTF8=y
CONFIG_NLS_UCS2_UTILS=m
"

# [Child] NTFS Support (Read/Write/Compression)
FS_NTFS_SUPPORT="
CONFIG_NTFS3_FS=m
CONFIG_NTFS3_LZX_XPRESS=y
CONFIG_NTFS3_FS_POSIX_ACL=y
"

# [Child] Network Filesystems (SMB/CIFS)
FS_NETWORK_SHARES="
CONFIG_CIFS=m
CONFIG_SMBFS=m
"

# [Child] Optical & FUSE
FS_OPTICAL_FUSE="
CONFIG_ISO9660_FS=m
CONFIG_UDF_FS=m
CONFIG_FUSE_FS=m
CONFIG_CUSE=m
"

# ------------------------------------------------------------------------------
# [PARENT] SYSTEM & HARDWARE (TOGGLE: ENABLE_PLATFORM)
# ------------------------------------------------------------------------------

# [Child] Systemd Requirements
SYS_SYSTEMD_REQS="
CONFIG_NET_SCHED=y
CONFIG_NET_SCH_FIFO=y
CONFIG_CGROUP_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_NETFILTER_NETLINK=m
CONFIG_CRYPTO_USER=m
CONFIG_CRYPTO_USER_API_AEAD=m
CONFIG_CRYPTO_USER_API_HASH=y
CONFIG_CRYPTO_USER_API_SKCIPHER=y
CONFIG_KEY_DH_OPERATIONS=y
"

# [Child] Architecture Compat
SYS_COMPAT_32BIT="
CONFIG_COMPAT=y
"

# [Child] Wireless Power Management
SYS_WIRELESS_PM="
CONFIG_WIRELESS=y
CONFIG_CFG80211=m
CONFIG_MAC80211=m
CONFIG_RFKILL=m
CONFIG_RFKILL_INPUT=y
CONFIG_RFKILL_GPIO=m
"

# [Child] Bluetooth Stack
SYS_BLUETOOTH_STACK="
CONFIG_BT=m
CONFIG_BT_BREDR=y
CONFIG_BT_LE=y
CONFIG_BT_HIDP=m
CONFIG_BT_HCIUART=m
CONFIG_BT_HCIBTUSB=m
CONFIG_BT_HCIBTUSB_MTK=y
CONFIG_BT_MTK=m
CONFIG_BT_ATH3K=m
"

# [Child] WLAN Drivers
SYS_WLAN_DRIVERS="
CONFIG_WLAN=y
CONFIG_RTL8187=m
CONFIG_RTL_CARDS=m
CONFIG_RTL8192CU=m
CONFIG_RTL8xxxU=m
CONFIG_RTW88=m
CONFIG_RTW89=m
CONFIG_BRCMFMAC=m
CONFIG_MWIFIEX=m
CONFIG_MT7601U=m
CONFIG_MT76x0U=m
CONFIG_MT76x2U=m
"

# [Child] Sensors (IIO)
SYS_SENSORS_IIO="
CONFIG_IIO=y
CONFIG_IIO_BUFFER=y
CONFIG_IIO_TRIGGER=y
CONFIG_IIO_ST_ACCEL_3AXIS=m
CONFIG_IIO_ST_GYRO_3AXIS=m
CONFIG_IIO_ST_MAGN_3AXIS=m
CONFIG_IIO_ST_LSM6DSX=m
"

# >> AGGREGATE: SAFE_MODULES (Combined Platform Fixes)
# Applied via ENABLE_PLATFORM=true
SAFE_MODULES="
${FS_NTFS_SUPPORT}
${FS_OPTICAL_FUSE}
${FS_NETWORK_SHARES}
${INPUT_JOYSTICK_CORE}
${INPUT_GAMEPADS_EXTRA}
${INPUT_TABLETS}
${INPUT_AUDIO_MIDI}
${NET_USB_ADAPTERS}
"

# >> AGGREGATE: RECOVERY_ESSENTIALS
RECOVERY_ESSENTIALS="${FS_CORE_RECOVERY}"

# >> AGGREGATE: SYSTEMD_REQ
SYSTEMD_REQ="${SYS_SYSTEMD_REQS} ${SYS_COMPAT_32BIT}"

# >> AGGREGATE: WIRELESS_MODULAR
WIRELESS_MODULAR="${SYS_WIRELESS_PM} ${SYS_BLUETOOTH_STACK} ${SYS_WLAN_DRIVERS}"

# >> AGGREGATE: AGGRESSIVE_MODULES (Optional/Toggle)
AGGRESSIVE_MODULES="${SYS_SENSORS_IIO}"

# >> AGGREGATE: HANDHELD_INPUT (Device Specific / Critical)
HANDHELD_INPUT="${INPUT_TOUCHSCREEN_HANDHELD}"

# ------------------------------------------------------------------------------
# [PARENT] MEDIA & VIDEO (TOGGLE: ENABLE_MEDIA)
# ------------------------------------------------------------------------------

# [Child] Media Core (UVC)
MEDIA_CORE_UVC="
CONFIG_MEDIA_SUPPORT=y
CONFIG_MEDIA_CAMERA_SUPPORT=y
CONFIG_VIDEO_DEV=y
CONFIG_VIDEO_V4L2=y
CONFIG_VIDEO_V4L2_SUBDEV_API=y
CONFIG_MEDIA_USB_SUPPORT=y
CONFIG_VIDEOBUF2_CORE=y
CONFIG_VIDEOBUF2_V4L2=y
CONFIG_VIDEOBUF2_MEMOPS=y
CONFIG_VIDEOBUF2_DMA_CONTIG=y
CONFIG_VIDEOBUF2_VMALLOC=y
CONFIG_VIDEOBUF2_DMA_SG=y
CONFIG_USB_VIDEO_CLASS=m
CONFIG_USB_VIDEO_CLASS_INPUT_EVDEV=y
CONFIG_V4L2_MEM2MEM_DEV=m
CONFIG_UVC_COMMON=m
"

# [Child] Media Debloat (No TV)
MEDIA_STRIP_TV="
CONFIG_MEDIA_ANALOG_TV_SUPPORT=n
CONFIG_MEDIA_DIGITAL_TV_SUPPORT=n
CONFIG_MEDIA_RADIO_SUPPORT=n
CONFIG_MEDIA_SDR_SUPPORT=n
CONFIG_MEDIA_TUNER=n
CONFIG_DVB_CORE=n
CONFIG_DVB_NET=n
CONFIG_DVB_MAX_ADAPTERS=0
CONFIG_VIDEO_EM28XX=n
CONFIG_VIDEO_USBTV=n
CONFIG_VIDEO_GO7007=n
CONFIG_VIDEO_HDPVR=n
CONFIG_VIDEO_PVRUSB2=n
CONFIG_VIDEO_STK1160=n
CONFIG_VIDEO_CX231XX=n
CONFIG_VIDEO_TM6000=n
CONFIG_VIDEO_AU0828=n
CONFIG_VIDEO_TLG2300=n
CONFIG_USB_GSPCA=n
CONFIG_USB_PWC=n
CONFIG_USB_AIRSPY=n
CONFIG_USB_HACKRF=n
CONFIG_USB_MSI2500=n
"

# ------------------------------------------------------------------------------
# [PARENT] CONTAINER SUPPORT (TOGGLE: ENABLE_CONTAINERS)
# ------------------------------------------------------------------------------

# [Child] Namespaces & Cgroups
CONT_NAMESPACES="
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_CGROUPS=y
CONFIG_MEMCG=y
CONFIG_CGROUP_PIDS=y
CONFIG_CPUSETS=y
CONFIG_NET_CLS_CGROUP=m
CONFIG_CGROUP_NET_PRIO=y
CONFIG_CGROUP_NET_CLASSID=y
"

# [Child] Android IPC
CONT_ANDROID_IPC="
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_ASHMEM=y
"

# [Child] Container Networking (Extra Modules)
CONT_NET_EXTRAS="
CONFIG_NETFILTER_XT_MATCH_COMMENT=m
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=m
CONFIG_NETFILTER_XT_MATCH_CONNTRACK=m
CONFIG_NETFILTER_XT_MARK=m
CONFIG_NETFILTER_XT_TARGET_MASQUERADE=m
CONFIG_MACVLAN=m
CONFIG_IPVLAN=m
"

# [Child] Container Disabled (Stripping)
CONT_STRIP_NET="
CONFIG_NET_CLS_CGROUP=n
"

# >> AGGREGATE: CONTAINER_CORE
CONTAINER_CORE="${CONT_NAMESPACES} ${CONT_ANDROID_IPC} ${CONT_NET_EXTRAS}"
CONTAINER_DISABLED="${CONT_STRIP_NET}"


# ------------------------------------------------------------------------------
# [PARENT] PERFORMANCE & TUNING (TOGGLE: ENABLE_SCHED_TUNING)
# ------------------------------------------------------------------------------

# [Child] Scheduler Hierarchy
SCHED_EEVDF_TEO="
CONFIG_CGROUP_SCHED=y
CONFIG_FAIR_GROUP_SCHED=y
CONFIG_RT_GROUP_SCHED=y
CONFIG_UCLAMP_TASK=y
CONFIG_CPU_IDLE_GOV_TEO=y
CONFIG_ENERGY_MODEL=y
"

# ------------------------------------------------------------------------------
# [PARENT] DEBLOAT (TOGGLE: ENABLE_DEBLOAT)
# ------------------------------------------------------------------------------

# [Child] Enterprise Network Stripping
DEBLOAT_NET_ENTERPRISE="
CONFIG_NET_TEAM=n
CONFIG_BONDING=n
CONFIG_ATM=n
CONFIG_CAN=n
CONFIG_HAMRADIO=n
CONFIG_NET_DSA=n
CONFIG_NET_FC=n
CONFIG_FDDI=n
CONFIG_HIPPI=n
CONFIG_ARCNET=n
CONFIG_WIMAX=n
CONFIG_X25=n
CONFIG_LAPB=n
CONFIG_PHONET=n
CONFIG_IEEE802154=n
"

# [Child] General Bloat
DEBLOAT_GENERAL="
CONFIG_NET_9P=m
CONFIG_NET_9P_VIRTIO=m
CONFIG_NET_9P_FD=m
CONFIG_NETCONSOLE=m
CONFIG_NETCONSOLE_DYNAMIC=y
"

# ------------------------------------------------------------------------------
# [PARENT] DEVICE SPECIFIC LOGIC
# ------------------------------------------------------------------------------

# [Child] NFTables Configurations
NFT_NAT_HIGH_END="
CONFIG_NF_NAT=y
CONFIG_NF_NAT_MASQUERADE=y
CONFIG_IP_NF_NAT=y
CONFIG_IP_NF_TARGET_MASQUERADE=y
CONFIG_IP_NF_TARGET_REDIRECT=m
CONFIG_NFT_NAT=y
"

NFT_NAT_LOW_END="
CONFIG_NF_NAT=m
CONFIG_NF_NAT_MASQUERADE=m
CONFIG_IP_NF_NAT=m
CONFIG_IP_NF_TARGET_MASQUERADE=m
CONFIG_IP_NF_TARGET_REDIRECT=m
CONFIG_NFT_NAT=m
"

# [Child] DSA Toggles
DSA_ON="
CONFIG_NET_DSA=m
CONFIG_NET_SWITCHDEV=y
CONFIG_NET_L3_MASTER_DEV=y
CONFIG_NET_VRF=m
CONFIG_NET_DSA_TAG_BRCM=m
CONFIG_NET_DSA_TAG_BRCM_COMMON=m
CONFIG_NET_DSA_TAG_DSA=m
CONFIG_NET_DSA_TAG_EDSA=m
CONFIG_NET_DSA_TAG_RTL4_A=m
CONFIG_NET_DSA_TAG_OCELOT=m
CONFIG_NET_DSA_TAG_OCELOT_8021Q=m
CONFIG_NET_DSA_MSCC_FELIX=m
"

DSA_OFF="
CONFIG_NET_L3_MASTER_DEV=n
CONFIG_NET_VRF=n
CONFIG_NET_DSA=n
CONFIG_NET_SWITCHDEV=n
CONFIG_NET_DSA_TAG_BRCM=n
CONFIG_NET_DSA_TAG_BRCM_COMMON=n
CONFIG_NET_DSA_TAG_DSA=n
CONFIG_NET_DSA_TAG_EDSA=n
CONFIG_NET_DSA_TAG_RTL4_A=n
CONFIG_NET_DSA_TAG_OCELOT=n
CONFIG_NET_DSA_MSCC_FELIX=n
"

# ------------------------------------------------------------------------------
# [PARENT] FINAL SAFETY ENFORCER
# ------------------------------------------------------------------------------
SAFETY_ENFORCER="
CONFIG_NETFILTER_XTABLES=y
CONFIG_NETFILTER_XTABLES_COMPAT=y
"

# ==============================================================================
# SCRIPT LOGIC
# ==============================================================================

# --- HELPER ---
apply_config() {
    local config_block="$1"
    local file="$2"
    echo "$config_block" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^#\ .*is\ not\ set ]]; then
            key="${BASH_REMATCH[1]}"
            value="is not set"
        elif [[ "$line" =~ ^# ]]; then
            continue
        elif [[ "$line" =~ ^(CONFIG_[^=]+)=(.*) ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi

        # Clean previous entries
        sed -i "/^${key}[= ]/d" "$file"
        sed -i "/^# ${key} is not set/d" "$file"

        if [[ "$value" == "is not set" ]]; then
            echo "# $key is not set" >> "$file"
        else
            echo "$key=$value" >> "$file"
        fi
    done
}

# --- MAIN ---
echo "Starting ROCKNIX Kernel Optimizer V38..."

# Resolve Enable All flag
if [[ "$ENABLE_ALL" == "true" ]]; then
    ENABLE_PLATFORM="true"
    ENABLE_DEBLOAT="true"
    ENABLE_CONTAINERS="true"
    ENABLE_SCHED_TUNING="true"
    ENABLE_MEDIA="true"
    ENABLE_AGGRESSIVE="true"
fi

if [[ "$ENABLE_PLATFORM" == "true" ]]; then
    echo ">> [MODE] Platform Fixups Enabled (Safe Modules, WiFi, Input, Recovery)"
else
    echo ">> [MODE] Core Network Only (Platform Fixes Disabled)"
fi

find . -type f -name "linux*.conf" | while read -r conf_file; do
    DEVICE=$(basename "$(dirname "$(dirname "$conf_file")")")
    echo "   Processing: $DEVICE"

    # 1. Base Application (Core Network Only)
    apply_config "$CORE_NET" "$conf_file"

    # 2. Platform Fixups (Input/WiFi/FS - Toggleable)
    if [[ "$ENABLE_PLATFORM" == "true" ]]; then
        apply_config "$SAFE_MODULES" "$conf_file"
        apply_config "$WIRELESS_MODULAR" "$conf_file"
        apply_config "$RECOVERY_ESSENTIALS" "$conf_file"
        apply_config "$SYSTEMD_REQ" "$conf_file"
        apply_config "$HANDHELD_INPUT" "$conf_file"
    fi

    # 3. Per-Device Logic (NAT/NFT Modes)
    case "$DEVICE" in
        SM8550|SM8650|SDM845|SM8250|RK3588)
            apply_config "$NFT_COMMON" "$conf_file"
            apply_config "$NFT_BOOLEAN" "$conf_file"
            apply_config "$NFT_NAT_HIGH_END" "$conf_file"
            
            if [[ "$ENABLE_DEBLOAT" == "true" ]]; then
                 apply_config "$DSA_ON" "$conf_file"
            fi
            ;;
        S922X)
            apply_config "$NFT_COMMON" "$conf_file"
            apply_config "$NFT_BOOLEAN" "$conf_file"
            apply_config "$NFT_NAT_LOW_END" "$conf_file"

             if [[ "$ENABLE_DEBLOAT" == "true" ]]; then
                 apply_config "$DSA_ON" "$conf_file"
            fi
            ;;
        *)
            apply_config "$NFT_COMMON" "$conf_file"
            apply_config "$NFT_TRISTATE" "$conf_file"
            apply_config "$NFT_NAT_HIGH_END" "$conf_file"
            
            if [[ "$ENABLE_DEBLOAT" == "true" ]]; then
                 apply_config "$DSA_OFF" "$conf_file"
            fi
            ;;
    esac

    # 4. Toggles
    if [[ "$ENABLE_DEBLOAT" == "true" ]]; then
        apply_config "$DEBLOAT_NET_ENTERPRISE" "$conf_file"
        apply_config "$MEDIA_STRIP_TV" "$conf_file"
        apply_config "$DEBLOAT_GENERAL" "$conf_file"
    fi

    if [[ "$ENABLE_CONTAINERS" == "true" ]]; then
        apply_config "$CONTAINER_CORE" "$conf_file"
    else
        apply_config "$CONTAINER_DISABLED" "$conf_file"
    fi

    if [[ "$ENABLE_SCHED_TUNING" == "true" ]]; then
        apply_config "$SCHED_EEVDF_TEO" "$conf_file"
    fi

    if [[ "$ENABLE_MEDIA" == "true" ]]; then
        apply_config "$MEDIA_CORE_UVC" "$conf_file"
    fi

    if [[ "$ENABLE_AGGRESSIVE" == "true" ]]; then
        apply_config "$AGGRESSIVE_MODULES" "$conf_file"
    fi

    # Safety Net
    apply_config "$SAFETY_ENFORCER" "$conf_file"
    
    sort -u -o "$conf_file" "$conf_file"
    echo "   [CMD] DEVICE=$DEVICE tools/adjust_kernel_config oldconfig"
done

echo "Batch optimization complete."
