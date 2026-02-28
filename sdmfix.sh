SDM_FILE="projects/ROCKNIX/devices/SDM845/linux/linux.aarch64.conf"
if [ -f "$SDM_FILE" ]; then
    # Revert PM changes
    sed -i '/CONFIG_SUSPEND_FREEZER=y/d' "$SDM_FILE"
    sed -i '/CONFIG_PM_SLEEP=y/d' "$SDM_FILE"
    sed -i '/CONFIG_PM_SLEEP_SMP=y/d' "$SDM_FILE"
    sed -i '/CONFIG_PM_GENERIC_DOMAINS_SLEEP=y/d' "$SDM_FILE"
    sed -i '/CONFIG_FREEZER=y/d' "$SDM_FILE"
    sed -i '/CONFIG_VT_CONSOLE_SLEEP=y/d' "$SDM_FILE"
    
    # Revert Misc
    sed -i '/CONFIG_FW_CACHE=y/d' "$SDM_FILE"
    
fi
