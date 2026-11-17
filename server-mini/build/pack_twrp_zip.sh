#!/bin/bash
# build the TWRP flashable zip: boot.img + rootfs.img.gz + installer
set -e
O=/home/builder/srv/release; mkdir -p $O; V=$(date +%Y%m%d)
gzip -6 -c /home/builder/srv/rootfs.img > $O/rootfs.img.gz
python3 - "$O" "$V" <<'PY'
import zipfile,sys,os
O,V=sys.argv[1:3]; z=O+'/ubuntu-server-mini-24.04-gtactive2lte-%s.zip'%V
with zipfile.ZipFile(z,'w') as f:
    for a,n,c in (('/root/upload/srv_zip/META-INF/com/google/android/update-binary','META-INF/com/google/android/update-binary',zipfile.ZIP_DEFLATED),
                  ('/root/upload/srv_zip/META-INF/com/google/android/updater-script','META-INF/com/google/android/updater-script',zipfile.ZIP_DEFLATED),
                  ('/root/upload/boot_srv.img','boot.img',zipfile.ZIP_DEFLATED),(O+'/rootfs.img.gz','rootfs.img.gz',zipfile.ZIP_STORED)):
        f.write(a,n,compress_type=c)
print(z, os.path.getsize(z))
PY
cd $O; md5sum *.zip > $(ls *.zip | tail -1).md5; ls -l
