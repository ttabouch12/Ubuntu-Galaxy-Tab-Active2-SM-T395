#!/bin/bash
# Ubuntu Server Mini rootfs, built inside an arm64 ubuntu:24.04 container (docker export -> ext4 image later)
set -x
export DEBIAN_FRONTEND=noninteractive
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod 755 /usr/sbin/policy-rc.d
sed -i 's/^Components: main.*/Components: main universe/' /etc/apt/sources.list.d/ubuntu.sources
apt-get update -qq
apt-get install -y -qq --no-install-recommends systemd-sysv udev dbus kmod iproute2 iputils-ping python3-cryptography python3-requests plymouth plymouth-label lxqt-panel lxqt-session lxqt-runner lxqt-config lxqt-qtplugin lxqt-globalkeys lxqt-notificationd lxqt-policykit pcmanfm-qt qterminal openbox breeze breeze-icon-theme breeze-cursor-theme fonts-noto-core featherpad yad librsvg2-bin git openssh-server network-manager wpasupplicant \
  sudo nano less ca-certificates curl htop systemd-timesyncd e2fsprogs tzdata dnsmasq-base \
  xserver-xorg-core xserver-xorg-video-fbdev xserver-xorg-input-libinput xinit x11-xserver-utils xinput xterm xdotool x11-utils \
  matchbox-window-manager matchbox-keyboard python3-tk python3-pil python3-pil.imagetk fonts-dejavu-core surf samba wsdd bluez \
  docker.io iptables \
  libsdl2-2.0-0 libavcodec60 libopus0 libcurl4t64 libevdev2 libavahi-client3 libasound2t64 libpulse0 libegl1 libgles2 2>&1 | tail -2
tar xzf /in/ml_bin.tgz -C /usr/local; ldconfig; ldd /usr/local/bin/moonlight | grep "not found"
tar xzf /in/ov.tgz --no-same-owner -C /
(cd / && tar tzf /in/ov.tgz) | grep '/$' | while read d; do chmod 755 "/$d"; done
(cd / && tar tzf /in/ov.tgz) | grep -v '/$' | while read f; do chmod go+r,go-w "/$f"; done
chmod 755 /usr/local/bin/* /usr/local/sbin/*; chmod 644 /etc/systemd/system/*.service /etc/systemd/system/*.socket
for g in video input render docker dialout; do getent group $g >/dev/null || groupadd -r $g; done
userdel -r ubuntu 2>/dev/null; useradd -u 1000 -m -s /bin/bash -G sudo,video,input,render,docker,dialout,adm,systemd-journal gta2; echo gta2:gta2 | chpasswd; passwd -l root
echo 'gta2 ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/gta2; chmod 440 /etc/sudoers.d/gta2
printf 'allowed_users=anybody\nneeds_root_rights=yes\n' > /etc/X11/Xwrapper.config
update-alternatives --set iptables /usr/sbin/iptables-legacy; update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
printf 'PasswordAuthentication yes\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/gta2.conf; rm -f /etc/ssh/ssh_host_*
cat > /etc/systemd/system/gta2-sshkeys.service <<S
[Unit]
Description=gta2: generate ssh host keys
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key
[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
[Install]
WantedBy=multi-user.target
S
cat > /etc/systemd/system/gta2-zram.service <<S
[Unit]
Description=gta2: 1.5G lz4 zram swap
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo 1 > /sys/block/zram0/reset; echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null; echo 1610612736 > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon -p 100 /dev/zram0'
[Install]
WantedBy=multi-user.target
S
systemctl disable nmbd 2>/dev/null; systemctl mask samba-ad-dc 2>/dev/null; rm -f /etc/samba/smb.conf
update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/gta2/gta2.plymouth 200 || true  # gta2 boot splash
systemctl enable gta2-lpm gta2-share smbd gta2-wsdd gta2-bootok gta2-wdt gta2-ml-setup gta2-cpu gta2-thermal gta2-import gta2-wlan gta2-usbnet gta2-fbinit gta2-gui gta2-portainer gta2-sshkeys gta2-zram gta2-perf gta2-dash.socket gta2-panel.socket gta2-charge gta2-trialguard gta2-netmon gta2-router gta2-dsicheck docker NetworkManager ssh systemd-timesyncd
systemctl disable getty@tty1 apt-daily-upgrade.timer apt-daily.timer dpkg-db-backup.timer e2scrub_all.timer motd-news.timer e2scrub_reap.service systemd-pstore.service 2>/dev/null
systemctl mask systemd-networkd-wait-online NetworkManager-wait-online ModemManager systemd-hostnamed e2scrub_reap
systemctl set-default multi-user.target
dpkg-divert --local --rename --add /usr/sbin/init; ln -sf /usr/local/sbin/gta2-init /usr/sbin/init
G=/usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstvideo4linux2.so; [ -f $G ] && dpkg-divert --local --rename --add $G
ln -sf /usr/share/zoneinfo/Europe/Istanbul /etc/localtime; echo Europe/Istanbul > /etc/timezone
mkdir -p /vendor /userdata; echo gta2srv > /etc/hostname
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /var/lib/apt/lists/* /var/cache/apt/*.bin /usr/sbin/policy-rc.d
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' -exec rm -rf {} +
apt-get clean; : > /etc/machine-id; du -sh / --exclude=/proc --exclude=/sys 2>/dev/null; echo ROOTFSDONE_ML
