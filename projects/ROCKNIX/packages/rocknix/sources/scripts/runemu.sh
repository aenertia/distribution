#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2019-present Shanti Gilbert (https://github.com/shantigilbert)
# Copyright (C) 2023 JELOS (https://github.com/JustEnoughLinuxOS)

# Source predefined functions and variables
. /etc/profile
. /etc/os-release
. /usr/lib/rocknix-display/display-core.sh

### Switch to performance mode early to speed up configuration and reduce time it takes to get into games.
performance

# Command line schema
# $1 = Game/Port
# $2 = Platform
# $3 = Core
# $4 = Emulator

ARGUMENTS="$@"
PLATFORM="${ARGUMENTS##*-P}"  # read from -P onwards
PLATFORM="${PLATFORM%% *}"  # until a space is found
CORE="${ARGUMENTS##*--core=}"  # read from --core= onwards
CORE="${CORE%% *}"  # until a space is found
EMULATOR="${ARGUMENTS##*--emulator=}"  # read from --emulator= onwards
EMULATOR="${EMULATOR%% *}"  # until a space is found
ROMNAME="$1"
BASEROMNAME=${ROMNAME##*/}
GAMEFOLDER="${ROMNAME//${BASEROMNAME}}"

### Define the variables used throughout the script
BLUETOOTH_STATE=$(get_setting controllers.bluetooth.enabled)
ES_CONFIG="/storage/.emulationstation/es_settings.cfg"
VERBOSE=false
LOG_DIRECTORY="/var/log"
LOG_FILE="exec.log"
RUN_SHELL="/usr/bin/bash"
RETROARCH_TEMP_CONFIG="/storage/.config/retroarch/retroarch.cfg"
RETROARCH_APPEND_CONFIG="/tmp/.retroarch.cfg"
NETWORK_PLAY="No"
SET_SETTINGS_TMP="/tmp/shader"
OUTPUT_LOG="${LOG_DIRECTORY}/${LOG_FILE}"
SCRIPT_NAME=$(basename "$0")

### Export Game Guide Path
GAME_GUIDE_PATH_CHECK="${1%.*}.txt"
if [ ! -f "${GAME_GUIDE_PATH_CHECK}" ]; then
  GAME_GUIDE_PATH_CHECK="No Game Guide Found"
fi
  /usr/bin/game-guides-tool "${1}"

### InputPlumber profile management
INPUTPLUMBER_HAS_SERVICE=false

function inputplumber_init() {
        if ! busctl --quiet status org.shadowblip.InputPlumber 2>/dev/null; then
                return 0
        fi
        INPUTPLUMBER_HAS_SERVICE=true
        ${VERBOSE} && log $0 "InputPlumber service detected"
}

function inputplumber_set_profile() {
        local profile_path="$1"
        [ "${INPUTPLUMBER_HAS_SERVICE}" = "true" ] || return 0
        [ -f "${profile_path}" ] || return 0
        local devices
        devices=$(busctl tree --list org.shadowblip.InputPlumber 2>/dev/null | grep "/CompositeDevice[0-9]" || true)
        for dev in ${devices}; do
                busctl call org.shadowblip.InputPlumber "${dev}" \
                        org.shadowblip.Input.CompositeDevice LoadProfilePath \
                        s "${profile_path}" 2>/dev/null || true
                ${VERBOSE} && log $0 "InputPlumber: loaded profile ${profile_path} on ${dev}"
        done
}

function inputplumber_resolve_profile() {
        # Resolve profile name to path: user dropin > system
        local name="$1"
        local user_path="/storage/.config/inputplumber/profiles/${name}.yaml"
        local sys_path="/usr/share/inputplumber/profiles/${name}.yaml"
        if [ -f "${user_path}" ]; then
                echo "${user_path}"
        elif [ -f "${sys_path}" ]; then
                echo "${sys_path}"
        fi
}

function inputplumber_restore() {
        [ "${INPUTPLUMBER_HAS_SERVICE}" = "true" ] || return 0
        local user_profile=$(get_setting system.inputplumber.default_profile 2>/dev/null)
        if [ -n "${user_profile}" ]; then
                local profile_path=$(inputplumber_resolve_profile "${user_profile}")
                if [ -n "${profile_path}" ]; then
                        inputplumber_set_profile "${profile_path}"
                        ${VERBOSE} && log $0 "InputPlumber: restored profile ${profile_path}"
                        return 0
                fi
        fi
        # Fallback: InputPlumber built-in default
        local devices
        devices=$(busctl tree --list org.shadowblip.InputPlumber 2>/dev/null | grep "/CompositeDevice[0-9]" || true)
        for dev in ${devices}; do
                busctl call org.shadowblip.InputPlumber "${dev}" \
                        org.shadowblip.Input.CompositeDevice LoadDefaultProfile \
                        2>/dev/null || true
        done
        ${VERBOSE} && log $0 "InputPlumber: restored default profiles"
}

### Function Library
function log() {
        if [ ${LOG} == true ]
        then
                if [[ ! -d "$LOG_DIRECTORY" ]]
                then
                        mkdir -p "$LOG_DIRECTORY"
                fi
                echo "${SCRIPT_NAME}: $*" 2>&1 | tee -a ${LOG_DIRECTORY}/${LOG_FILE}
        else
                echo "${SCRIPT_NAME}: $*"
        fi
}

function loginit() {
        if [ ${LOG} == true ]
        then
                if [ -e ${LOG_DIRECTORY}/${LOG_FILE} ]
                then
                        rm -f ${LOG_DIRECTORY}/${LOG_FILE}
                fi
                cat <<EOF >${LOG_DIRECTORY}/${LOG_FILE}
Emulation Run Log - Started at $(date)

ARG1: $1
ARG2: $2
ARG3: $3
ARG4: $4
ARGS: $*
EMULATOR: ${EMULATOR}
PLATFORM: ${PLATFORM}
CORE: ${CORE}
ROM NAME: ${ROMNAME}
BASE ROM NAME: ${ROMNAME##*/}
USING CONFIG: ${RETROARCH_TEMP_CONFIG}
USING APPENDCONFIG : ${RETROARCH_APPEND_CONFIG}
GAME GUIDE PATH: ${GAME_GUIDE_PATH_CHECK}

EOF
        else
                log $0 "Emulation Run Log - Started at $(date)"
        fi
}

function quit() {
        ${VERBOSE} && log $0 "Cleaning up and exiting"
        bluetooth enable
        set_kill set "emulationstation"
        clear_screen
        # Kill window mover if still running
        [ -n "${EMU_WINDOW_MOVER_PID}" ] && kill ${EMU_WINDOW_MOVER_PID} 2>/dev/null
        # Restore panel-off state from before game launch (use runtime-queried output names)
        if display_is_dual; then
            case "${PRE_GAME_DISPLAY_STATE}" in
                top_off)   swaymsg "output ${DISPLAY_SECONDARY} power off" >/dev/null 2>&1 ;;
                bottom_off) swaymsg "output ${DISPLAY_PRIMARY} power off" >/dev/null 2>&1 ;;
            esac
        fi
        DEVICE_CPU_GOVERNOR=$(get_setting system.cpugovernor)
        ${DEVICE_CPU_GOVERNOR}
        exit $1
}

function clear_screen() {
        ${VERBOSE} && log $0 "Clearing screen"
        clear
}

function bluetooth() {
        if [ "$1" == "disable" ]
        then
                ${VERBOSE} && log $0 "Disabling BT"
                if [[ "${BLUETOOTH_STATE}" == "1" ]]
                then
                        NPID=$(pgrep -f rocknix-bluetooth-agent)
                        if [[ ! -z "$NPID" ]]; then
                                kill "$NPID"
                        fi
                fi
        elif [ "$1" == "enable" ]
        then
                ${VERBOSE} && log $0 "Enabling BT"
                if [[ "${BLUETOOTH_STATE}" == "1" ]]
                then
                        systemd-run rocknix-bluetooth-agent
                fi
        fi
}

### Enable logging
case $(get_setting system.loglevel) in
  off|none)
    LOG=false
  ;;
  verbose)
    LOG=true
    VERBOSE=true
  ;;
  *)
    LOG=true
  ;;
esac

### Prepare to load our emulator and game.
loginit "$1" "$2" "$3" "$4"
clear_screen
bluetooth disable
set_kill stop
inputplumber_init

### Determine which emulator we're launching and make appropriate adjustments before launching.
${VERBOSE} && log $0 "Configuring for ${EMULATOR}"
case ${EMULATOR} in
  mednafen)
    set_kill set "-9 mednafen"
    RUNTHIS='${RUN_SHELL} /usr/bin/start_mednafen.sh "${ROMNAME}" "${CORE}" "${PLATFORM}"'
  ;;
  retroarch)
    # Make sure NETWORK_PLAY isn't defined before we start our tests/configuration.
    del_setting netplay.mode

    case ${ARGUMENTS} in
      *"--host"*)
        ${VERBOSE} && log $0 "Setup netplay host."
        NETWORK_PLAY="${ARGUMENTS##*--host}"  # read from --host onwards
        NETWORK_PLAY="${NETWORK_PLAY%%--nick*}"  # until --nick is found
        NETWORK_PLAY="--host ${NETWORK_PLAY} --nick"
        set_setting netplay.mode "host"
      ;;
      *"--connect"*)
        ${VERBOSE} && log $0 "Setup netplay client."
        NETWORK_PLAY="${ARGUMENTS##*--connect}"  # read from --connect onwards
        NETWORK_PLAY="${NETWORK_PLAY%%--nick*}"  # until --nick is found
        NETWORK_PLAY="--connect ${NETWORK_PLAY} --nick"
        set_setting netplay.mode "client"
      ;;
      *"--netplaymode spectator"*)
        ${VERBOSE} && log $0 "Setup netplay spectator."
        set_setting "netplay.mode" "spectator"
      ;;
    esac

    ### Set set_kill to kill the appropriate retroarch
    set_kill set "retroarch retroarch32"

    ### Assume we're running 64bit Retroarch
    RABIN="retroarch"

    case ${HW_ARCH} in
      aarch64)
        if [[ "${CORE}" =~ pcsx_rearmed32 ]] || \
           [[ "${CORE}" =~ gpsp ]] || \
           [[ "${CORE}" =~ desmume ]]
        then
          ### Configure for 32bit Retroarch
          ${VERBOSE} && log $0 "Configuring for 32bit cores."
          export RABIN="retroarch32"
        fi
      ;;
    esac


    ### Configure specific emulator requirements
    case ${CORE} in
      freej2me*)
        ${VERBOSE} && log $0 "Setup freej2me requirements."
        /usr/bin/freej2me.sh
        JAVA_HOME='/storage/jdk'
        export JAVA_HOME
        PATH="$JAVA_HOME/bin:$PATH"
        export PATH
        export _JAVA_OPTIONS="-Djava.awt.headless=true"
      ;;
      easyrpg*)
        # easyrpg needs runtime files to be downloaded on the first run
        ${VERBOSE} && log $0 "Setup easyrpg requirements."
        /usr/bin/easyrpg.sh
      ;;
    esac


    RUNTHIS='${EMUPERF} /usr/bin/${RABIN} -L /tmp/cores/${CORE}_libretro.so --config ${RETROARCH_TEMP_CONFIG} --appendconfig ${RETROARCH_APPEND_CONFIG} "${ROMNAME}"'

    CONTROLLERCONFIG="${ARGUMENTS#*--controllers=*}"

    if [[ "${ARGUMENTS}" == *"-state_slot"* ]]
    then
      CONTROLLERCONFIG="${CONTROLLERCONFIG%% -state_slot*}"  # until -state is found
      SNAPSHOT="${ARGUMENTS#*-state_slot *}" # -state_slot x
      SNAPSHOT="${SNAPSHOT%% -*}"
        if [[ "${ARGUMENTS}" == *"-autosave"* ]]; then
          CONTROLLERCONFIG="${CONTROLLERCONFIG%% -autosave*}"  # until -autosave is found
          AUTOSAVE="${ARGUMENTS#*-autosave *}" # -autosave x
          AUTOSAVE="${AUTOSAVE%% -*}"
        else
          AUTOSAVE=""
        fi
    else
      CONTROLLERCONFIG="${CONTROLLERCONFIG%% --*}"  # until a -- is found
      SNAPSHOT=""
      AUTOSAVE=""
    fi

    # Configure platform specific requirements
    case ${PLATFORM} in
      "atomiswave")
        rm ${ROMNAME}.nvmem*
      ;;
      "scummvm")
        GAMEDIR=$(cat "${ROMNAME}" | awk 'BEGIN {FS="\""}; {print $2}')
        cd "${GAMEDIR}"
        RUNTHIS='${RUN_SHELL} /usr/bin/start_scummvm.sh libretro .'
      ;;
    esac

    ### Configure retroarch
    if [ -e "${SET_SETTINGS_TMP}" ]
    then
      rm -f "${SET_SETTINGS_TMP}"
    fi
    ${VERBOSE} && log $0 "Execute setsettings (${PLATFORM} ${ROMNAME} ${CORE} --controllers=${CONTROLLERCONFIG} --autosave=${AUTOSAVE} --snapshot=${SNAPSHOT})"
    (/usr/bin/setsettings.sh "${PLATFORM}" "${ROMNAME}" "${CORE}" --controllers="${CONTROLLERCONFIG}" --autosave="${AUTOSAVE}" --snapshot="${SNAPSHOT}" >${SET_SETTINGS_TMP})

    ### If setsettings wrote data in the background, grab it and assign it to EXTRAOPTS
    if [ -e "${SET_SETTINGS_TMP}" ]
    then
      EXTRAOPTS=$(cat ${SET_SETTINGS_TMP})
      rm -f ${SET_SETTINGS_TMP}
      ${VERBOSE} && log $0 "Extra Options: ${EXTRAOPTS}"
    fi

    if [[ ${EXTRAOPTS} != 0 ]]; then
      RUNTHIS=$(echo ${RUNTHIS} | sed "s|--config|${EXTRAOPTS} --config|")
    fi
  ;;
  *)
    case ${PLATFORM} in
      "setup")
        RUNTHIS='${RUN_SHELL} "${ROMNAME}"'
      ;;
      "gamecube"|"triforce")
        RUNTHIS='${RUN_SHELL} /usr/bin/start_dolphin_gc.sh "${ROMNAME}" "${PLATFORM}" "${CORE}"'
      ;;
      "wii"|"wiiware")
        RUNTHIS='${RUN_SHELL} /usr/bin/start_dolphin_wii.sh "${ROMNAME}" "${PLATFORM}" "${CORE}"'
      ;;
      "ports")
        RUNTHIS='${EMUPERF} ${RUN_SHELL} "${ROMNAME}"'
	      sed -i "/^ACTIVE_GAME=/c\ACTIVE_GAME=\"${ROMNAME}\"" /storage/.config/PortMaster/mapper.txt
        sed -i "/^ACTIVE_PLATFORM=/c\ACTIVE_PLATFORM=\"${PLATFORM}\"" /storage/.config/PortMaster/mapper.txt
      ;;
      "windows")
        RUNTHIS='${EMUPERF} ${RUN_SHELL} "${ROMNAME}"'
        # Hook into Portmaster control mapping
        sed -i "/^ACTIVE_GAME=/c\ACTIVE_GAME=\"${ROMNAME}\"" /storage/.config/PortMaster/mapper.txt
        sed -i "/^ACTIVE_PLATFORM=/c\ACTIVE_PLATFORM=\"${PLATFORM}\"" /storage/.config/PortMaster/mapper.txt
      ;;
      "shell")
        RUNTHIS='${RUN_SHELL} "${ROMNAME}"'
      ;;
      *)
        RUNTHIS='${RUN_SHELL} "/usr/bin/start_${CORE%-*}.sh" "${ROMNAME}" "${PLATFORM}"'
      ;;
    esac
  ;;
esac

### Load emulator-specific InputPlumber profile (ADR-007 Phase 2)
### User dropins in /storage/.config/inputplumber/profiles/ override system profiles
case "${CORE}" in
  azahar-sa|azahar)
    inputplumber_set_profile "$(inputplumber_resolve_profile emulator-3ds)"
    ;;
  melonds-sa|melonds)
    inputplumber_set_profile "$(inputplumber_resolve_profile emulator-nds)"
    ;;
  flycast-sa|flycast)
    inputplumber_set_profile "$(inputplumber_resolve_profile emulator-dc)"
    ;;
  skyemu-sa|skyemu|SkyEmu)
    inputplumber_set_profile "$(inputplumber_resolve_profile emulator-gb)"
    ;;
esac

### Execution time.
clear_screen

# Ensure emulator launches on the same output as ES.
# Power on all panels so sway can place the window, then move it to the
# active output via a background watcher. Panel-off state restored on exit.
PRE_GAME_DISPLAY_STATE=$(cat /run/rocknix/display_state 2>/dev/null)
EMU_WINDOW_MOVER_PID=""
if [ -n "${WLR_CON}" ] && display_is_dual; then
  swaymsg "output * power on" >/dev/null 2>&1
  # Background: wait for non-ES window then move it to active output
  (
    for _try in 1 2 3 4 5 6 7 8 9 10; do
      sleep 1
      swaymsg "[app_id!=emulationstation] move to output ${WLR_CON}, fullscreen enable" >/dev/null 2>&1 && break
    done
  ) &
  EMU_WINDOW_MOVER_PID=$!
fi

${VERBOSE} && log $0 "executing game: ${ROMNAME}"
${VERBOSE} && log $0 "script to execute: ${RUNTHIS}"

### Set the cores to use
CORES=$(get_setting "cores" "${PLATFORM}" "${ROMNAME##*/}")
${VERBOSE} && log $0 "Configure big.little (${CORES})"
case ${CORES} in
  little)
    EMUPERF="${SLOW_CORES}"
  ;;
  big)
    EMUPERF="${FAST_CORES}"
  ;;
  *)
    unset EMUPERF
  ;;
esac

### We need the original system cooling profile later so get it now!
COOLINGPROFILE=$(get_setting cooling.profile)

### Configure GPU performance mode
GPUPERF=$(get_setting "gpuperf" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z ${GPUPERF} ]
then
  ${VERBOSE} && log $0 "Set GPU performance to (${GPUPERF})"
  gpu_performance_level ${GPUPERF}
  get_gpu_performance_level >/tmp/.gpu_performance_level
fi

if [ "${DEVICE_HAS_FAN}" = "true" ]
then
  ### Set any custom fan profile (make this better!)
  GAMEFAN=$(get_setting "cooling.profile" "${PLATFORM}" "${ROMNAME##*/}")
  if [ ! -z "${GAMEFAN}" ]
  then
    ${VERBOSE} && log $0 "Set fan profile to (${GAMEFAN})"
    set_setting cooling.profile ${GAMEFAN}
    systemctl restart fancontrol
  fi
fi

### Display mode for emulation
DISPLAY_MODE=$(get_setting "display_mode" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z "${DISPLAY_MODE}" ] && [ "${DISPLAY_MODE}" != "default" ]
then
  set_refresh_rate "${DISPLAY_MODE}"
fi

### Stretched mode: force RetroArch windowed so SDL surface matches combined resolution
if display_is_dual && [ "${EMULATOR}" = "retroarch" ]; then
  STRETCHED_SETTING=$(get_setting "system.stretched_mode")
  if [ "${STRETCHED_SETTING}" = "1" ] && [ -n "${RETROARCH_APPEND_CONFIG}" ]; then
    STRETCHED_W="${CANVAS_W}"
    STRETCHED_H="${CANVAS_H}"
    sed -i '/^video_fullscreen\b/d;/^video_windowed_fullscreen\b/d;/^video_window/d;/^video_ctx_scaling\b/d' "${RETROARCH_APPEND_CONFIG}"
    sed -i "1i\\
video_fullscreen = \"false\"\\
video_windowed_fullscreen = \"false\"\\
video_windowed_position_width = \"${STRETCHED_W}\"\\
video_windowed_position_height = \"${STRETCHED_H}\"\\
video_windowed_position_x = \"0\"\\
video_windowed_position_y = \"0\"\\
video_window_custom_size_enable = \"true\"\\
video_ctx_scaling = \"true\"" "${RETROARCH_APPEND_CONFIG}"
    ${VERBOSE} && log $0 "Stretched mode: RetroArch windowed ${STRETCHED_W}x${STRETCHED_H}"
  fi
fi

FORCEPACK=$(get_setting "forcepack" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z "${FORCEPACK}" ] && [ "${FORCEPACK}" = "On" ]
then
    ${VERBOSE} && log $0 "Enabling panfrost forcepack"
    export PAN_MESA_DEBUG=forcepack
fi

### Offline all but the number of threads we need for this game if configured.
NUMTHREADS=$(get_setting "threads" "${PLATFORM}" "${ROMNAME##*/}")
if [ -n "${NUMTHREADS}" ] &&
   [ ! ${NUMTHREADS} = "default" ]
then
  ${VERBOSE} && log $0 "Configure active cores (${NUMTHREADS})"
  onlinethreads ${NUMTHREADS} 0
fi

### Set the governor mode for emulation
CPU_GOVERNOR=$(get_setting "cpugovernor" "${PLATFORM}" "${ROMNAME##*/}")
${VERBOSE} && log $0 "Set emulation performance mode to (${CPU_GOVERNOR})"
${CPU_GOVERNOR}

### Set uclamp hints for this emulator (frequency floor + cap)
if has_uclamp && command -v uclampset >/dev/null 2>&1; then
  EMU_UCLAMP_MIN=$(get_setting "uclamp_min" "${PLATFORM}" "${ROMNAME##*/}")
  UCLAMP_TIER_SETTING=$(get_setting "uclamp_tier" "${PLATFORM}" "${ROMNAME##*/}")

  if [ -n "${UCLAMP_TIER_SETTING}" ] && [ "${UCLAMP_TIER_SETTING}" != "default" ]; then
    if [ "${UCLAMP_TIER_SETTING}" = "manual" ]; then
      [ -z "${EMU_UCLAMP_MIN}" ] && EMU_UCLAMP_MIN="${UCLAMP_EMU_MIN:-384}"
      UCLAMP_TIER="manual(${EMU_UCLAMP_MIN})"
    elif [ "${UCLAMP_TIER_SETTING}" = "maximum" ]; then
      EMU_UCLAMP_MIN=1024
      UCLAMP_TIER="maximum"
    else
      EMU_UCLAMP_MIN=$(resolve_uclamp_tier "${UCLAMP_TIER_SETTING}")
      UCLAMP_TIER="${UCLAMP_TIER_SETTING}"
    fi
  elif [ -z "${EMU_UCLAMP_MIN}" ] || [ "${EMU_UCLAMP_MIN}" = "default" ]; then
    UCLAMP_TIER=$(get_system_uclamp_tier "${PLATFORM}")
    EMU_UCLAMP_MIN=$(resolve_uclamp_tier "${UCLAMP_TIER}")
  else
    UCLAMP_TIER="explicit"
  fi

  EMU_UCLAMP_MAX=$(get_setting "uclamp_max" "${PLATFORM}" "${ROMNAME##*/}")
  [ -z "${EMU_UCLAMP_MAX}" -o "${EMU_UCLAMP_MAX}" = "default" ] && EMU_UCLAMP_MAX="${UCLAMP_EMU_MAX:-1024}"
  RUNTHIS="uclampset -m ${EMU_UCLAMP_MIN} -M ${EMU_UCLAMP_MAX} ${RUNTHIS}"
  ${VERBOSE} && log $0 "Uclamp: tier=${UCLAMP_TIER} min=${EMU_UCLAMP_MIN} max=${EMU_UCLAMP_MAX}"
fi

### Per-game memory tunables (applied before launch, reverted on exit)

# Drop caches before launch (default: yes)
EMU_DROP_CACHES=$(get_setting "drop_caches" "${PLATFORM}" "${ROMNAME##*/}")
if [ "${EMU_DROP_CACHES}" != "0" ]; then
  sync && echo 3 > /proc/sys/vm/drop_caches
  ${VERBOSE} && log $0 "Dropped caches before launch"
fi

# Capture current values for revert
_ORIG_SWAPPINESS=$(cat /proc/sys/vm/swappiness)
_ORIG_MAX_MAP=$(cat /proc/sys/vm/max_map_count)
_ORIG_OVERCOMMIT=$(cat /proc/sys/vm/overcommit_memory)
_ORIG_VFS_CACHE=$(cat /proc/sys/vm/vfs_cache_pressure)

EMU_SWAPPINESS=$(get_setting "vm_swappiness" "${PLATFORM}" "${ROMNAME##*/}")
if [ -n "${EMU_SWAPPINESS}" ] && [ "${EMU_SWAPPINESS}" != "default" ]; then
  sysctl -w vm.swappiness=${EMU_SWAPPINESS} >/dev/null
  ${VERBOSE} && log $0 "Set vm.swappiness=${EMU_SWAPPINESS}"
fi

EMU_MAX_MAP=$(get_setting "vm_max_map_count" "${PLATFORM}" "${ROMNAME##*/}")
if [ -n "${EMU_MAX_MAP}" ] && [ "${EMU_MAX_MAP}" != "default" ]; then
  sysctl -w vm.max_map_count=${EMU_MAX_MAP} >/dev/null
  ${VERBOSE} && log $0 "Set vm.max_map_count=${EMU_MAX_MAP}"
fi

EMU_OVERCOMMIT=$(get_setting "vm_overcommit" "${PLATFORM}" "${ROMNAME##*/}")
if [ -n "${EMU_OVERCOMMIT}" ] && [ "${EMU_OVERCOMMIT}" != "default" ]; then
  sysctl -w vm.overcommit_memory=${EMU_OVERCOMMIT} >/dev/null
  ${VERBOSE} && log $0 "Set vm.overcommit_memory=${EMU_OVERCOMMIT}"
fi

EMU_VFS_CACHE=$(get_setting "vm_vfs_cache_pressure" "${PLATFORM}" "${ROMNAME##*/}")
if [ -n "${EMU_VFS_CACHE}" ] && [ "${EMU_VFS_CACHE}" != "default" ]; then
  sysctl -w vm.vfs_cache_pressure=${EMU_VFS_CACHE} >/dev/null
  ${VERBOSE} && log $0 "Set vm.vfs_cache_pressure=${EMU_VFS_CACHE}"
fi

### Check whether MangoHud is supported and enabled
if [ "${DEVICE_MANGOHUD_SUPPORT}" == "true" ]; then
  MANGOHUD_ENABLED=$(get_setting "rocknix.mangohud.enabled"  "${PLATFORM}" "${ROMNAME##*/}")
  if [ "${MANGOHUD_ENABLED}" = "1" ]; then
    # Enable GPU profiling and MangoHud
    gpu_profiling "on"
    RUNTHIS="/usr/bin/mangohud ${RUNTHIS}"
    ${VERBOSE} && log $0 "Enabling MangoHud"
  fi
fi

# Build systemd-run properties for cgroup slice placement
SLICE_PROPS="--slice=rocknix-foreground.slice --collect --quiet --pipe"

# Core affinity via cpuset controller (supplements taskset in EMUPERF)
if [ -n "${CORES}" ]; then
  case ${CORES} in
    big)    [ -n "${FAST_CORE_IDS}" ] && SLICE_PROPS="${SLICE_PROPS} --property=AllowedCPUs=${FAST_CORE_IDS}" ;;
    little) [ -n "${SLOW_CORE_IDS}" ] && SLICE_PROPS="${SLICE_PROPS} --property=AllowedCPUs=${SLOW_CORE_IDS}" ;;
  esac
fi

# If the rom is a shell script just execute it, useful for DOSBOX and ScummVM scan scripts
if [[ "${ROMNAME}" == *".sh" ]] && [ ! "${PLATFORM}" = "ports" ] && [ ! "${PLATFORM}" = "windows" ]; then
        ${VERBOSE} && log $0 "Executing shell script ${ROMNAME} (slice: rocknix-foreground)"
        systemd-run ${SLICE_PROPS} "${ROMNAME}" &>>${OUTPUT_LOG}
        ret_error=$?
else
        ${VERBOSE} && log $0 "Executing $(eval echo ${RUNTHIS}) (slice: rocknix-foreground)"
        eval systemd-run ${SLICE_PROPS} ${RUNTHIS} &>>${OUTPUT_LOG}
        ret_error=$?
fi

### Restore InputPlumber to default profile
inputplumber_restore

### Switch back to performance mode to clean up
performance

clear_screen

### Disable touch on the secondary screen for dual screen devices
if display_is_dual; then
  # Disable touch events for Retroid Pocket devices to prevent focus loss
  if [[ "${QUIRK_DEVICE}" == "Retroid Pocket 5" || "${QUIRK_DEVICE}" == "Retroid Pocket Flip2" || "${QUIRK_DEVICE}" == "Retroid Pocket Mini" || "${QUIRK_DEVICE}" == "Retroid Pocket Mini V2" ]]; then
    swaymsg input "0:0:generic_ft5x06_(a0)" events disabled
    swaymsg input "0:0:generic_ft5x06_(8d)" events disabled
  fi
fi

### Go back to system display mode , if we had specialized mode defined
DISPLAY_MODE=$(get_setting "display_mode" "${PLATFORM}" "${ROMNAME##*/}")
if [ ! -z "${DISPLAY_MODE}" ] && [ "${DISPLAY_MODE}" != "default" ]
then
  DISPLAY_MODE=$(get_setting "system.display_mode")
  DISPLAY_OUTPUT="${WLR_CON:-$(/usr/bin/wlr-randr | awk 'NR==1{print $1;}')}"
  if [ -z "${DISPLAY_MODE}" ]; then
    # if we have no system mode use the displays preferred mode
    /usr/bin/wlr-randr --output ${DISPLAY_OUTPUT} --preferred
  else
    # If we have user specifed system mode set that
    set_refresh_rate "${DISPLAY_MODE}"
  fi
fi

### Restore cooling profile.
if [ "${DEVICE_HAS_FAN}" = "true" ]
then
  ${VERBOSE} && log $0 "Restore system cooling profile (${COOLINGPROFILE})"
  set_setting cooling.profile ${COOLINGPROFILE}
  systemctl restart fancontrol &
fi

### Restore system GPU performance mode
GPUPERF=$(get_setting "system.gpuperf")
if [ ! -z ${GPUPERF} ]
then
  ${VERBOSE} && log $0 "Restore system GPU performance mode (${GPUPERF})"
  gpu_performance_level ${GPUPERF} &
else
  ${VERBOSE} && log $0 "Restore system GPU performance mode (auto)"
  gpu_performance_level auto &
fi
rm -f /tmp/.gpu_performance_level 2>/dev/null

### Reset the number of cores to use.
NUMTHREADS=$(get_setting "system.threads")
${VERBOSE} && log $0 "Restore active threads (${NUMTHREADS})"
if [ -n "${NUMTHREADS}" ]
then
        onlinethreads ${NUMTHREADS} 0 &
else
        onlinethreads all 1 &
fi

### Revert per-game memory tunables
sysctl -w vm.swappiness=${_ORIG_SWAPPINESS} >/dev/null 2>&1
sysctl -w vm.max_map_count=${_ORIG_MAX_MAP} >/dev/null 2>&1
sysctl -w vm.overcommit_memory=${_ORIG_OVERCOMMIT} >/dev/null 2>&1
sysctl -w vm.vfs_cache_pressure=${_ORIG_VFS_CACHE} >/dev/null 2>&1

### Disable GPU profiling
gpu_profiling "off"

### Backup save games
CLOUD_BACKUP=$(get_setting "cloud.backup")
if [ "${CLOUD_BACKUP}" = "1" ]
then
  INETUP=$(/usr/bin/amionline >/dev/null 2>&1)
  if [ $? == 0 ]
  then
    log $0 "backup saves to the cloud."
    /usr/bin/run /usr/bin/cloud_backup
  fi
fi

${VERBOSE} && log $0 "Checking errors: ${ret_error} "
if [ "${ret_error}" == "0" ]
then
        quit 0
else
        log $0 "exiting with ${ret_error}"
        quit 1
fi
