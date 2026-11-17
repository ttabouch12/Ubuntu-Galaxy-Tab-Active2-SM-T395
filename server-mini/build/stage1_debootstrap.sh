#!/bin/bash
# gta2srv stage1: debootstrap Ubuntu 24.04 arm64 minbase + packages
set -x
export DEBIAN_FRONTEND=noninteractive
apt-get install -y debootstrap qemu-user-static binfmt-support >/dev/null
R=/home/builder/srv/root
mkdir -p /home/builder/srv
if [ ! -x $R/bin/bash ]; then
  rm -rf $R
  debootstrap --arch=arm64 --variant=minbase --components=main,universe --include=systemd-sysv,udev,dbus,kmod,apt-utils noble $R http://ports.ubuntu.com/ubuntu-ports || exit 1
fi
cat > $R/etc/apt/sources.list <<S
deb http://ports.ubuntu.com/ubuntu-ports noble main universe
deb http://ports.ubuntu.com/ubuntu-ports noble-updates main universe
deb http://ports.ubuntu.com/ubuntu-ports noble-security main universe
S
for d in proc sys dev dev/pts; do mount --bind /$d $R/$d; done
cp /etc/resolv.conf $R/etc/resolv.conf
chroot $R apt-get update
chroot $R apt-cache policy moonlight-qt moonlight-embedded fuse-overlayfs docker.io matchbox-keyboard onboard | grep -E '^[a-z]|Candidate'
chroot $R apt-get install -y --no-install-recommends \
  iproute2 iputils-ping openssh-server network-manager wpasupplicant sudo nano less ca-certificates curl htop \
  xserver-xorg-core xserver-xorg-video-fbdev xserver-xorg-input-libinput xinit x11-xserver-utils xinput xterm \
  matchbox-window-manager matchbox-keyboard python3-tk fonts-dejavu-core \
  docker.io fuse-overlayfs iptables e2fsprogs tzdata
chroot $R apt-get clean
for d in dev/pts dev sys proc; do umount $R/$d; done
du -sh $R
echo STAGE1DONE
