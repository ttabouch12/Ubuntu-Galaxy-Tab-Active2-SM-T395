#!/bin/bash
# runs inside the alarm-build container (linux/arm64, --privileged): build the tablet ztOS rootfs from the GSI (r5 modules + OPTIMIZE.md layer)
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
# skip pacman entirely when the base image already has the tools
ok=0; command -v bsdtar && command -v mke2fs && command -v zstd && command -v patch && ok=1
[ $ok = 1 ] || for i in 1 2 3; do
  pacman --disable-sandbox --disable-download-timeout --cachedir /work/pacman-cache -Syu --noconfirm --needed \
    libarchive e2fsprogs zstd patch util-linux && { ok=1; break; }
  echo "pacman attempt $i failed, retrying"; sleep 20
done
[ $ok = 1 ] || exit 1
echo PACMAN_DONE
bash /in/dev2/build-rootfs.sh --gsi /work/ztOS/build/ztos/gsi/ztos-gsi-0.2.1-aarch64.tar.zst --ztos-src /work/ztOS \
  --device /in/dev2/ztos-device-samsung-gtactive2lte \
  --modules /in/modules-r5.tgz --kconfig /in/kernel-r5.config --firmware /in/fw \
  --ssh-key /in/id_gta2build.pub \
  --size 4G --user gta2 --password gta2 --timezone Europe/Istanbul \
  --work /work/zt --out /out/ztos-rootfs.img && md5sum /out/ztos-rootfs.img && echo ROOTFS_DONE
