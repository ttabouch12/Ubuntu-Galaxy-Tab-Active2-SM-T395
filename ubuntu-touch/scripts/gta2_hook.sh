# gta2 Ubuntu Touch boot hook (/userdata/gta2_hook.sh, run by gta2-hook.service before lxc/lightdm)
mkdir -p /run/gta2 /run/udev/rules.d
# touch + pen flipped 180 (lomiri shell is rotated 180 for the upside-down panel)
echo 'SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="sec_touchscreen|sec_e-pen", ENV{LIBINPUT_CALIBRATION_MATRIX}="-1 0 1 0 -1 1"' > /run/udev/rules.d/99-gta2-touch.rules
udevadm control --reload; udevadm trigger --subsystem-match=input --action=change
systemctl mask --runtime gta2-audiofix.service 2>/dev/null
# bluetooth (QCA9377 over ttySAC0): HAL runs as bluetooth(1002) and needs the UART + rfkill; BD addr comes from persist.service.bdroid.bdaddr (set once in the container)
echo 'KERNEL=="ttySAC0", OWNER="1002", GROUP="1002", MODE="0660"' > /run/udev/rules.d/99-gta2-bt.rules
chown 1002:1002 /dev/ttySAC0 2>/dev/null; chmod 660 /dev/ttySAC0 2>/dev/null
for r in /sys/class/rfkill/*; do [ "$(cat $r/name)" = bt_power ] && chown 1002:1002 $r/state && chmod 664 $r/state; done
# boot spinner draws in panel orientation (panel is mounted 180) -> show a 180-rotated logo
[ -f /userdata/gta2/logo_rot.png ] && mount --bind /userdata/gta2/logo_rot.png /usr/share/ubuntutouch-artwork/ubuntu_touch_logo_2025_dark.png
# capacitive keys: back -> Esc, recents -> Super+W (spread) via uinput helper
[ -f /userdata/gta2/gta2_keys.py ] && systemd-run --unit=gta2-keys --property=Restart=always /usr/bin/python3 /userdata/gta2/gta2_keys.py
# modem: talk to Samsung RIL over binder (IRadio slot1) instead of the rild socket
printf '[Settings]\n\n[ril_0]\ntransport=binder:name=slot1\n' > /run/gta2/ril_subscription.conf
mount --bind /run/gta2/ril_subscription.conf /etc/ofono/ril_subscription.conf
# audio: 64-bit PA -> audio.primary.default.so (= halium audio.hidl_compat, copied into /vendor/lib64/hw) -> 32-bit vendor HAL service over HIDL
mkdir -p /run/systemd/user/pulseaudio.service.d
printf '[Service]\nEnvironment=HYBRIS_USE_VENDOR_NAMESPACE=0\nEnvironment=HYBRIS_LD_LIBRARY_PATH=/system/lib64:/apex/com.android.vndk.v33/lib64:/vendor/lib64\nEnvironment=GLIBC_TUNABLES=glibc.rtld.optional_static_tls=16384\nEnvironment=PULSE_MODULES_DROID_EXTRA_CARD_ARGS=use_legacy_stream_set_parameters=true\n' > /run/systemd/user/pulseaudio.service.d/zz-gta2.conf
# USB networking: android_usb RNDIS (0525:a4a2, Windows built-in driver) -> 10.15.19.82, DHCP, ssh (key only)
( sleep 30; systemctl stop usb-moded 2>/dev/null; A=/sys/class/android_usb/android0
  echo 0 > $A/enable; sleep 1; echo 0525 > $A/idVendor; echo a4a2 > $A/idProduct; echo 1 > $A/f_rndis/wceis; echo rndis > $A/functions; echo 1 > $A/enable; i=0; while [ "$(cat $A/state)" != CONFIGURED ] && [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done
  if [ "$(cat $A/state)" != CONFIGURED ]; then echo 0 > $A/enable; echo 0 > $A/f_rndis/wceis; echo 1 > $A/enable; sleep 5; fi
  ip link set rndis0 up; ip addr add 10.15.19.82/24 dev rndis0 2>/dev/null
  dnsmasq --interface=rndis0 --bind-interfaces --port=0 --dhcp-range=10.15.19.100,10.15.19.110,255.255.255.0,1h --dhcp-option=3 --dhcp-option=6 --pid-file=/run/gta2/dnsmasq.pid
  [ -f /userdata/gta2/authorized_keys ] || exit 0; cp /userdata/gta2/authorized_keys /run/gta2/ak; chmod 600 /run/gta2/ak; ssh-keygen -q -t ed25519 -N '' -f /run/gta2/hk
  mkdir -p /run/sshd; /usr/sbin/sshd -h /run/gta2/hk -o ListenAddress=10.15.19.82 -o PermitRootLogin=prohibit-password -o PasswordAuthentication=no -o AuthorizedKeysFile=/run/gta2/ak -o PidFile=/run/gta2/sshd.pid ) &
exit 0
