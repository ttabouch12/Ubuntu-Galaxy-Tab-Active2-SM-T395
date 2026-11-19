#!/bin/bash
# build the 3.18 gta2srv kernel (LineageOS 22.2 exynos7870 + OC + Halium/UT + gta2srv fixes) and repack boot.img
set -x
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq git bc make python3 cpio xz-utils curl libssl-dev flex bison gcc ca-certificates >/dev/null
W=/w; mkdir -p $W; cd $W
if [ ! -x $W/gcc/bin/aarch64-linux-android-gcc ]; then mkdir -p gcc; curl -sfL -o /tmp/gcc.tgz https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-9.0.0_r61.tar.gz; ls -l /tmp/gcc.tgz; tar xzf /tmp/gcc.tgz -C gcc; fi
ls gcc/bin | head -3
if [ ! -d k/.git ]; then git clone -q --depth 1 -b lineage-22.2 https://github.com/samsungexynos7870/android_kernel_samsung_exynos7870 k || exit 1
  cd k; git apply --whitespace=nowarn /in/oc.patch && echo OC_OK; git apply --whitespace=nowarn --exclude=arch/arm64/configs/halium.config --reject /in/ut.patch; echo UT_RC=$?; find . -name '*.rej' | head; cd ..; fi
cd k
python3 - <<'PY'
p='drivers/video/fbdev/exynos/decon_7870/decon-int_drv.c'; s=open(p).read()
old="""		var->bits_per_pixel	= 32;
		var->red.offset		= 16;
		var->red.length		= 8;
		var->green.offset	= 8;
		var->green.length	= 8;
		var->blue.offset	= 0;
		var->blue.length	= 8;"""
new="""		var->bits_per_pixel	= 32;
		/* gta2srv: this DECON window format is R,G,B,X in memory (Android RGBA_8888) */
		var->red.offset		= 0;
		var->red.length		= 8;
		var->green.offset	= 8;
		var->green.length	= 8;
		var->blue.offset	= 16;
		var->blue.length	= 8;"""
if 'gta2srv: this DECON' not in s:
    assert s.count(old)==1, 'check_var pattern'
    s=s.replace(old,new); open(p,'w').write(s); print('COLOR_PATCHED')
PY
python3 - <<'PY2'
p='drivers/thermal/samsung/exynos_tmu.c'; s=open(p).read()
old="""	ret = exynos_tmu_ect_set_information(pdev);
	if (ret) {
		dev_err(&pdev->dev, "Failed to ect\\n");
		goto err;
	}
#endif
"""
new=old+"""
	/* gta2srv: no thermal throttling below 90 C (trips 90,92,94,.. until the vendor ones are higher) */
	for (i = 0; i < pdata->freq_tab_count && i < MAX_TRIP_COUNT; i++) {
		int n = 90 + 2 * i;
		if (pdata->trigger_type[i] == HW_TRIP || pdata->trigger_type[i] == SW_TRIP)
			break;
		if (pdata->trigger_levels[i] < n) {
			pdata->trigger_levels[i] = n;
			pdata->freq_tab[i].temp_level = n;
		}
	}
	if (pdata->hotplug_enable && pdata->hotplug_out_threshold < 96) {
		int d = 96 - pdata->hotplug_out_threshold;
		pdata->hotplug_in_threshold += d;
		pdata->hotplug_out_threshold += d;
	}
"""
if 'gta2srv: no thermal throttling' not in s:
    assert s.count(old)==1, 'tmu pattern'
    s=s.replace(old,new); open(p,'w').write(s); print('TMU_PATCHED')
PY2
O=$W/out; mkdir -p $O; cp /in/kernel.config $O/.config
./scripts/config --file $O/.config -e POSIX_MQUEUE -e CFS_BANDWIDTH -e DUMMY -d USER_NS
export PATH=$W/gcc/bin:$PATH; M="make O=$O ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- CC=aarch64-linux-android-gcc-4.9.x"
$M olddefconfig >/dev/null 2>&1; grep -E "USER_NS|POSIX_MQUEUE=" $O/.config
$M -j$(nproc) Image 2>&1 | grep -E " error|Error " | head -20
ls -l $O/arch/arm64/boot/Image || exit 1
python3 - $O/arch/arm64/boot/Image /in/boot_base.img /out/boot_srv5.img <<'PY'
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
open(sys.argv[3],'wb').write(bytes(h)+pad(K)+pad(R)+pad(D)+b'SEANDROIDENFORCE'); print('boot',len(K),len(R),len(D))
PY
cp $O/.config /out/k318.config; md5sum /out/boot_srv5.img; echo K318DONE
