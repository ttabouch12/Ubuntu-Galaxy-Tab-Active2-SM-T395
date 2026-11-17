#!/bin/bash
# gta2srv stage2: config overlay, user, services, moonlight-embedded, image
set -x
export DEBIAN_FRONTEND=noninteractive
R=/home/builder/srv/root; B=/home/builder/srv/build
grep -q STAGE1DONE /root/srv_build1.log || { echo "stage1 not done"; exit 1; }
mnt() { for d in proc sys dev dev/pts; do mount --bind /$d $1/$d; done; cp /etc/resolv.conf $1/etc/resolv.conf; }
umnt() { for d in dev/pts dev sys proc; do umount $1/$d; done; }
# --- moonlight-embedded build in a throwaway copy
if [ ! -x /home/builder/srv/ml/usr/local/bin/moonlight ]; then
  rm -rf $B; cp -a $R $B; mnt $B
  chroot $B apt-get install -y --no-install-recommends git cmake make gcc g++ pkg-config libopus-dev libexpat1-dev libssl-dev libasound2-dev libudev-dev libavahi-client-dev libcurl4-openssl-dev libevdev-dev libavcodec-dev libavutil-dev libsdl2-dev uuid-dev libpulse-dev
  chroot $B sh -c 'cd /root && rm -rf me && git clone --depth 1 --recursive https://github.com/moonlight-stream/moonlight-embedded.git me && cd me && git log -1 --format=%H && mkdir b && cd b && cmake .. -DCMAKE_BUILD_TYPE=Release && make -j8 && make install DESTDIR=/root/mlinst'
  rm -rf /home/builder/srv/ml; cp -a $B/root/mlinst /home/builder/srv/ml
  chroot $B sh -c 'ldd /root/mlinst/usr/local/bin/moonlight' | tee /home/builder/srv/ml_ldd.txt
  umnt $B
fi
ls -lR /home/builder/srv/ml | head -30
cp -a /home/builder/srv/ml/usr/local/. $R/usr/local/
# --- main rootfs
mnt $R
chroot $R apt-get install -y --no-install-recommends dnsmasq-base xdotool x11-utils libsdl2-2.0-0 libavcodec60 libopus0 libcurl4t64 libevdev2 libavahi-client3 libasound2t64 libpulse0 libegl1 libgles2
chroot $R ldconfig
chroot $R sh -c 'ldd /usr/local/bin/moonlight | grep "not found"'
cp -a /root/upload/srv_ov/. $R/
(cd /root/upload/srv_ov && find . -type d) | while read d; do chmod 755 "$R/$d"; done; (cd /root/upload/srv_ov && find .) | while read p; do chown -h 0:0 "$R/$p"; done
chmod 755 $R/usr/local/bin/* $R/usr/local/sbin/*
chmod 644 $R/etc/systemd/system/*.service
echo gta2srv > $R/etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 gta2srv\n' > $R/etc/hosts
chroot $R sh -c 'for g in video input render docker dialout; do getent group $g >/dev/null || groupadd -r $g; done; id gta2 || useradd -m -s /bin/bash -G sudo,video,input,render,docker,dialout gta2; echo gta2:gta2 | chpasswd; passwd -l root'
echo 'gta2 ALL=(ALL) NOPASSWD:ALL' > $R/etc/sudoers.d/gta2; chmod 440 $R/etc/sudoers.d/gta2
printf 'allowed_users=anybody\nneeds_root_rights=yes\n' > $R/etc/X11/Xwrapper.config
chroot $R update-alternatives --set iptables /usr/sbin/iptables-legacy
chroot $R update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
chroot $R systemctl enable gta2-cpu gta2-import gta2-wlan gta2-usbnet gta2-fbinit gta2-gui gta2-portainer docker NetworkManager ssh
chroot $R systemctl disable getty@tty1 2>/dev/null
chroot $R systemctl mask systemd-networkd-wait-online NetworkManager-wait-online ModemManager 2>/dev/null
chroot $R systemctl set-default multi-user.target
chroot $R systemctl disable apt-daily-upgrade.timer apt-daily.timer dpkg-db-backup.timer e2scrub_all.timer motd-news.timer e2scrub_reap.service systemd-pstore.service 2>/dev/null
chroot $R systemctl mask systemd-hostnamed.service e2scrub_reap.service
chroot $R sh -c 'dpkg-divert --local --rename --add /usr/sbin/init && ln -sf /usr/local/sbin/gta2-init /usr/sbin/init'
chroot $R apt-get purge -y locales 2>/dev/null; chroot $R apt-get autoremove --purge -y
mkdir -p $R/vendor $R/userdata
# SSH: password + key login for gta2; host keys are generated on first boot (none shipped)
rm -f $R/etc/ssh/ssh_host_*
cat > $R/etc/systemd/system/gta2-sshkeys.service <<S
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
chroot $R systemctl enable gta2-sshkeys
printf 'PasswordAuthentication yes\nPermitRootLogin prohibit-password\n' > $R/etc/ssh/sshd_config.d/gta2.conf
# zram swap 512M
cat > $R/etc/systemd/system/gta2-zram.service <<S
[Unit]
Description=gta2: 512M zram swap
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo 1 > /sys/block/zram0/reset; echo 536870912 > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon -p 100 /dev/zram0'
[Install]
WantedBy=multi-user.target
S
chroot $R systemctl enable gta2-zram
# slim: docs, man, locales
rm -rf $R/usr/share/doc/* $R/usr/share/man/* $R/usr/share/info/* $R/var/cache/apt/*.bin $R/var/lib/apt/lists/*
find $R/usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' -exec rm -rf {} +
chroot $R apt-get clean
: > $R/etc/machine-id
rm -f $R/etc/resolv.conf; ln -s /run/systemd/resolve/stub-resolv.conf $R/etc/resolv.conf 2>/dev/null
[ -e $R/lib/systemd/systemd-resolved ] || { rm -f $R/etc/resolv.conf; : > $R/etc/resolv.conf; }
umnt $R
du -sh $R
# --- image (ext4, no metadata_csum for the 3.18 kernel)
I=/home/builder/srv/rootfs.img; rm -f $I; truncate -s 2400M $I
mkfs.ext4 -q -F -O ^metadata_csum,^64bit,^orphan_file,^metadata_csum_seed -L gta2srv -d $R $I
e2fsck -fn $I | tail -2; ls -l $I
echo STAGE2DONE
