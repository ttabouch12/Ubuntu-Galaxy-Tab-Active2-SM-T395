#!/bin/bash
# stdin: docker export tar of the rootfs container -> rootfs.img (ext4 for kernel 3.18) -> TWRP zip
set -x
apt-get update -qq && apt-get install -y -qq e2fsprogs zip python3 >/dev/null
R=/r; mkdir -p $R; tar -x -C $R
rm -f $R/.dockerenv; echo gta2srv > $R/etc/hostname; printf '127.0.0.1 localhost\n127.0.1.1 gta2srv\n' > $R/etc/hosts; rm -f $R/etc/resolv.conf; : > $R/etc/resolv.conf
chmod 755 $R; stat -c '%a %U %n' $R $R/etc $R/usr $R/home/gta2 $R/etc/sudoers.d/gta2
I=/tmp/rootfs.img; truncate -s 2400M $I
mkfs.ext4 -q -F -O ^metadata_csum,^64bit,^orphan_file,^metadata_csum_seed -L gta2srv -d $R $I; e2fsck -fn $I | tail -1
V=1.2; Z=/out/ubuntu-server-mini-$V-24.04-gtactive2lte.zip; rm -f $Z
mkdir -p /tmp/z/META-INF/com/google/android; cp /in/update-binary /tmp/z/META-INF/com/google/android/; echo '# dummy' > /tmp/z/META-INF/com/google/android/updater-script
cp /in/boot.img /tmp/z/boot.img; gzip -6 -c $I > /tmp/z/rootfs.img.gz
(cd /tmp/z && zip -q -r $Z META-INF boot.img && zip -q -0 $Z rootfs.img.gz)
cd /out && md5sum $(basename $Z) > $(basename $Z).md5; ls -l /out; echo MKIMGDONE
