#!/bin/bash
# runs inside the alarm-build container (linux/arm64, --privileged): build the ztOS GSI only
# v5 (stale db.lck cleanup); v4 (MAKEFLAGS=-j$(nproc), ParallelDownloads=10); v3 (adds installer patch); v2: several mirrors, ParallelDownloads, no download timeout, 3 retries, package cache kept in the ztos-work volume
set -x
export MAKEFLAGS=-j$(nproc)
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
grep -q '^ParallelDownloads' /etc/pacman.conf || sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
grep -q '^ParallelDownloads' /etc/pacman.conf || sed -i '/^\[options\]/a ParallelDownloads = 10' /etc/pacman.conf
cat > /etc/pacman.d/mirrorlist <<'M'
Server = http://de.mirror.archlinuxarm.org/$arch/$repo
Server = http://eu.mirror.archlinuxarm.org/$arch/$repo
Server = http://mirror.archlinuxarm.org/$arch/$repo
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://dk.mirror.archlinuxarm.org/$arch/$repo
M
mkdir -p /work/pacman-cache
pacman-key --init && pacman-key --populate archlinuxarm
ok=0
for i in 1 2 3; do
  pacman --disable-sandbox --disable-download-timeout --cachedir /work/pacman-cache -Syu --noconfirm --needed \
    base-devel git python python-pip pyside6 mesa util-linux libarchive dosfstools mtools e2fsprogs zstd patch curl shadow && { ok=1; break; }
  echo "pacman attempt $i failed, retrying"; sleep 20
done
[ $ok = 1 ] || exit 1
echo PACMAN_DONE
cd /work
[ -d ztOS/.git ] || git clone https://github.com/Zerone-Laboratories/ztOS ztOS || exit 1
git -C ztOS checkout 8bfb09011757f06c68a055fbfd95ea07d5e4fbe1 || true
mkdir -p ztOS/build && cp /in/ArchLinuxARM-aarch64-latest.tar.gz ztOS/build/alarm.tar.gz
cd ztOS
# v3: the installer's own chroot pacman uses the stock mirror + 10 s timeout: patch the stage script it writes
git checkout -- installer/ztos_installer/build.py
B=installer/ztos_installer/build.py
sed -i 's|^P="pacman --disable-sandbox --noconfirm"$|P="pacman --disable-sandbox --noconfirm --disable-download-timeout"\ncp /etc/pacman.d/mirrorlist "$R/etc/pacman.d/mirrorlist"\ngrep -q "^ParallelDownloads" "$R/etc/pacman.conf" \|\| sed -i "/^\\[options\\]/a ParallelDownloads = 10" "$R/etc/pacman.conf"|' $B
sed -i 's|^ch \$P -Syu$|ch $P -Syu \|\| { sleep 20; ch $P -Syu; } \|\| { sleep 40; ch $P -Syu; }|' $B
sed -i 's|^ch \$P -S --needed \$PACKAGES$|ch $P -S --needed $PACKAGES \|\| { sleep 20; ch $P -S --needed $PACKAGES; } \|\| { sleep 40; ch $P -S --needed $PACKAGES; }|' $B
sed -n '/^P="pacman/,+3p;/^ch \$P -S/p' $B
grep -c "disable-download-timeout" $B || exit 1
# v5: a killed run (wsl --shutdown) leaves pacman locks behind: clear them before the installer
rm -f /work/ztOS/build/ztos/gsi/root/var/lib/pacman/db.lck /var/lib/pacman/db.lck
MAKEFLAGS=-j$(nproc) python3 installer/ztos build --target gsi
ls -la /work/ztOS/build/ztos/gsi/ && cp /work/ztOS/build/ztos/gsi/ztos-gsi-*.tar.zst* /out/ && echo GSI_DONE
