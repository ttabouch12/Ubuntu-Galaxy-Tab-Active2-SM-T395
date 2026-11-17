#!/bin/sh
# One-time setup of the Android vendor partition (CACHE, p19) for Ubuntu Touch on SM-T395.
# Run as root on the booted Ubuntu Touch system (e.g. over USB ssh). Idempotent.
set -e
V=/android/vendor
mount -o remount,rw $V
# 1) Real vendor vndservicemanager. SELinux is off on this 3.18 kernel, so preload Halium's selinux stubs
#    (the stock binary aborts in android::Access::Access(), whose restart storm kills hwcomposer -> black screen).
printf '%s\n' 'service vndservicemanager /vendor/bin/vndservicemanager /dev/vndbinder' '    class core' '    user system' \
  '    group system readproc' '    setenv LD_PRELOAD /system/lib64/libselinux_stubs.so' '    shutdown critical' > $V/etc/init/vndservicemanager.rc
# 2) The real audio HAL is 32-bit only (lib/hw/audio.primary.exynos7870.so). Run the Android audio HAL service
#    (Halium disables it under its stock name) and give 64-bit pulseaudio-droid Halium's HIDL compat module as
#    audio.primary.default.so, so PulseAudio talks to the 32-bit HAL over binder.
printf '%s\n' 'service gta2.audio-hal /vendor/bin/hw/android.hardware.audio.service' '    class hal' '    user audioserver' \
  '    group audio camera drmrpc inet media mediadrm net_bt net_bt_admin net_bw_acct wakelock' '    capabilities BLOCK_SUSPEND SYS_NICE' > $V/etc/init/gta2-audio.rc
cd $V/lib64/hw
[ -f audio.primary.default.so.gta2orig ] || mv audio.primary.default.so audio.primary.default.so.gta2orig
cp /android/system/lib64/hw/audio.hidl_compat.default.so audio.primary.default.so; chmod 644 audio.primary.default.so
# 3) Android perf rc from the OC ROM is fine on UT too (CPU/GPU/MIF profile)
[ -f $V/etc/init/init.gta2.perf.rc.off-ut ] && mv $V/etc/init/init.gta2.perf.rc.off-ut $V/etc/init/init.gta2.perf.rc
sync; mount -o remount,ro $V
# 4) Bluetooth address: the HAL looks for /efs/bluetooth/bt_addr, which the Halium container doesn't have
A=$(lxc-attach -n android -- /system/bin/cat /mnt/vendor/efs/bluetooth/bt_addr 2>/dev/null | tr -d '\r\n')
[ -n "$A" ] && lxc-attach -n android -- /system/bin/setprop persist.service.bdroid.bdaddr "$A" && echo "BT address set"
echo "vendor setup done - reboot"
