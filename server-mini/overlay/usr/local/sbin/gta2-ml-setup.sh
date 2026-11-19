#!/bin/sh
# mainline kernel only: install its modules + Wi-Fi firmware from /userdata/gta2srv/ml, then load ath10k_sdio.
# Board data: Samsung's own bdwlan30.bin from the vendor partition (not redistributable, read at runtime).
S=/userdata/gta2srv/ml; KR=$(uname -r)
[ -d /lib/modules/$KR ] || { [ -f $S/modules.tgz ] && tar xzf $S/modules.tgz -C / && depmod -a $KR; }
F=/lib/firmware/ath10k/QCA9377/hw1.0; mkdir -p $F
[ -d $S/firmware ] && cp -a $S/firmware/. /lib/firmware/
[ -f /vendor/firmware/bdwlan30.bin ] && cp /vendor/firmware/bdwlan30.bin $F/board.bin
modprobe ath10k_sdio
exit 0
