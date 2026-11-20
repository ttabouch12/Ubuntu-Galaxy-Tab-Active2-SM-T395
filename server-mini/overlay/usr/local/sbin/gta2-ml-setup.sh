#!/bin/sh
# mainline kernel only: install its modules + Wi-Fi firmware from /userdata/gta2srv/ml, then load ath10k_sdio.
# Modules: $S/modules-<uname -r>.tgz (one per kernel build, so a test kernel never mixes with the good one),
# else the legacy $S/modules.tgz. Re-extracted when the tarball changes (md5 stamp).
# Board data: Samsung's own bdwlan30.bin from the vendor partition (not redistributable, read at runtime).
S=/userdata/gta2srv/ml; KR=$(uname -r)
M=$S/modules-$KR.tgz; [ -f $M ] || M=$S/modules.tgz
if [ -f $M ]; then
  SUM=$(md5sum $M | cut -d' ' -f1)
  if [ ! -d /lib/modules/$KR ] || [ "$(cat /lib/modules/$KR/.gta2stamp 2>/dev/null)" != "$SUM" ]; then
    tar xzf $M --keep-directory-symlink -C / && depmod -a $KR && echo $SUM > /lib/modules/$KR/.gta2stamp
  fi
fi
F=/lib/firmware/ath10k/QCA9377/hw1.0; mkdir -p $F
[ -d $S/firmware ] && cp -a $S/firmware/. /lib/firmware/
[ -f /vendor/firmware/bdwlan30.bin ] && cp /vendor/firmware/bdwlan30.bin $F/board.bin
modprobe ath10k_sdio
modprobe cpufreq-dt 2>/dev/null
exit 0
