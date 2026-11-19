#!/bin/bash
# U-Boot (exynos-mobile) for gtactive2lte, chainloaded by S-Boot from BOOT.
# bootcmd: boot /extlinux/extlinux.conf from USERDATA (mmc 0:18 = p24); on ANY failure -> TWRP
# (PMU INFORM3 0x1048080c = 0x12345674 is S-Boot's "recovery" reason). Volume-Down menu: TWRP / Download / U-Boot shell.
set -x
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq git gcc gcc-aarch64-linux-gnu make bison flex libssl-dev python3 python3-setuptools python3-dev swig libgnutls28-dev device-tree-compiler bc python3-pyelftools uuid-dev >/dev/null
W=/w/ub; mkdir -p $W; cd $W
[ -d u-boot/.git ] || git clone -q --depth 1 https://github.com/u-boot/u-boot.git u-boot || exit 1
cd u-boot; git log -1 --format='%h %s' | head -1
ls configs | grep -i exynos-mobile; ls dts/upstream/src/arm64/exynos/ | grep 7870
cp /in/ub_gta2.dts dts/upstream/src/arm64/exynos/exynos7870-gtactive2lte.dts
cp /in/ub_gta2-u-boot.dtsi arch/arm/dts/exynos7870-gtactive2lte-u-boot.dtsi
grep -q gtactive2lte dts/upstream/src/arm64/exynos/Makefile 2>/dev/null || echo 'dtb-$(CONFIG_ARCH_EXYNOS) += exynos7870-gtactive2lte.dtb' >> dts/upstream/src/arm64/exynos/Makefile
export CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm
make exynos-mobile_defconfig >/dev/null || exit 1
./scripts/config -e CMD_I2C -e CMD_MEMORY -e CMD_SYSBOOT -e CMD_EXT4 -e CMD_FS_GENERIC -e CMD_BOOTMENU -e BOOTDELAY_ESC \
  --set-str DEFAULT_DEVICE_TREE "exynos/exynos7870-gtactive2lte" --set-str DEVICE_TREE "exynos/exynos7870-gtactive2lte" \
  -e USE_BOOTCOMMAND --set-str BOOTCOMMAND "run gta2_boot" --set-val BOOTDELAY 1 -e USE_PREBOOT --set-str PREBOOT "" \
  -e ENV_VARS_UBOOT_CONFIG
grep -q gta2_boot include/env/*.env 2>/dev/null
cat >> board/samsung/exynos-mobile/exynos-mobile.env 2>/dev/null <<'E'
gta2_rec=echo gta2: -> TWRP; mw.l 0x1048080c 0x12345674; sleep 1; reset
gta2_dl=echo gta2: -> download mode; mw.l 0x1048080c 0x12345671; sleep 1; reset
gta2_boot=if sysboot mmc 0:18 any ${scriptaddr} /extlinux/extlinux.conf; then; fi; echo gta2: extlinux boot failed; run gta2_rec
bootmenu_0=Ubuntu Server Mini (mainline)=run gta2_boot
bootmenu_1=TWRP recovery=run gta2_rec
bootmenu_2=Download mode=run gta2_dl
bootmenu_3=U-Boot console=echo
E
ls board/samsung/exynos-mobile/
make olddefconfig >/dev/null; grep -E "BOOTCOMMAND|DEVICE_TREE=|CMD_I2C=|CMD_SYSBOOT=" .config
make -j$(nproc) 2>&1 | grep -E "error|Error|warning: .*gtactive" | head -20
ls -l u-boot.bin u-boot-nodtb.bin u-boot.dtb 2>&1
strings u-boot.bin | grep -c gta2_boot
python3 - u-boot.bin /in/uboot_base.img /out/boot_uboot_gta2.img <<'PY'
import struct,hashlib,sys
K=open(sys.argv[1],'rb').read(); b=open(sys.argv[2],'rb').read()
ks,rs,ss,ps,ds=[struct.unpack_from('<I',b,o)[0] for o in (8,16,24,36,40)]
al=lambda n:(n+ps-1)//ps*ps
R=b[ps+al(ks):ps+al(ks)+rs]; D=b[ps+al(ks)+al(rs)+al(ss):ps+al(ks)+al(rs)+al(ss)+ds]
h=bytearray(b[:ps]); struct.pack_into('<I',h,8,len(K))
sh=hashlib.sha1()
for x in (K,R,b'',D): sh.update(x); sh.update(struct.pack('<I',len(x)))
h[576:608]=sh.digest().ljust(32,b'\0')
pad=lambda x:x+b'\0'*(al(len(x))-len(x))
open(sys.argv[3],'wb').write(bytes(h)+pad(K)+pad(R)+pad(D)+b'SEANDROIDENFORCE'); print('uboot boot.img', len(K), rs, ds)
PY
echo UBDONE
