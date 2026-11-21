#!/bin/bash
# stdin: docker export tar of the rootfs container -> rootfs.img (ext4 for kernel 3.18) -> TWRP zip
set -x
apt-get update -qq && apt-get install -y -qq e2fsprogs zip python3 >/dev/null
R=/r; mkdir -p $R; tar -x -C $R
rm -f $R/.dockerenv; echo gta2srv > $R/etc/hostname; printf '127.0.0.1 localhost\n127.0.1.1 gta2srv\n' > $R/etc/hosts; rm -f $R/etc/resolv.conf; : > $R/etc/resolv.conf
chmod 755 $R; stat -c '%a %U %n' $R $R/etc $R/usr $R/home/gta2 $R/etc/sudoers.d/gta2
I=/tmp/rootfs-ml.img; truncate -s 3000M $I
mkfs.ext4 -q -F -O ^metadata_csum,^64bit,^orphan_file,^metadata_csum_seed -L gta2srv -d $R $I; e2fsck -fn $I | tail -1
cp $I /out/rootfs-ml.img && md5sum $I /out/rootfs-ml.img; ls -l /out/rootfs-ml.img; echo MKIMGDONE_ML
