#!/bin/bash
# mainline 6.15 for gtactive2lte: linux-6.15 + pmaports exynos7870 patch set + our DT + gta2srv config
set -x
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq git bc make python3 cpio xz-utils curl libssl-dev flex bison gcc gcc-aarch64-linux-gnu ca-certificates kmod dpkg-dev busybox-static >/dev/null
W=/w/ml; mkdir -p $W; cd $W
ls /in/gta2-patches/*.patch >/dev/null 2>&1 || { echo "no gta2 patches yet"; exit 0; }
[ -d linux/.git ] || git clone -q --depth 1 -b v6.18 https://github.com/torvalds/linux.git linux || exit 1
cd linux; git config user.email b@b; git config user.name b; git reset -q --hard; git clean -qfdx -e out
for p in /in/gta2-patches/*.patch; do git am -q --3way $p || { echo "PATCHFAIL $p"; git am --abort; }; done; cd ..
pkgver=6.18; ln -sfn linux linux-$pkgver
echo SRC_READY
cd $W/linux-$pkgver
D=arch/arm64/boot/dts/exynos/exynos7870-gtactive2lte.dts
grep -n "reboot-mode\|syscon-reboot" arch/arm64/boot/dts/exynos/exynos7870.dtsi | head -3
grep -q "reboot-mode" arch/arm64/boot/dts/exynos/exynos7870.dtsi || cat >> $D <<'DT'
&pmu_system_controller {
	reboot-mode {
		compatible = "syscon-reboot-mode";
		offset = <0x080c>;
		mode-bootloader = <0x1234567d>;
		mode-download = <0x12345671>;
		mode-recovery = <0x12345674>;
	};
};
DT
O=$W/out; mkdir -p $O
M="make O=$O ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-"
$M defconfig >/dev/null; ./scripts/kconfig/merge_config.sh -m -O $O $O/.config /in/gta2.config >/dev/null; $M olddefconfig >/dev/null
./scripts/config --file $O/.config -e I2C_CHARDEV -e NETFILTER_XT_MATCH_ADDRTYPE -e NETFILTER_XT_MATCH_CONNTRACK -e IP_NF_TARGET_MASQUERADE -e NF_NAT \
 -e OVERLAY_FS -e BRIDGE -e BRIDGE_NETFILTER -e VETH -e CGROUP_PIDS -e MEMCG -e CGROUP_BPF -e POSIX_MQUEUE -e USER_NS -e DRM_FBDEV_EMULATION -e FB \
 -e BLK_DEV_INITRD -e RD_GZIP -e EXT4_FS -e ZRAM -e FW_LOADER -e BLK_DEV_LOOP -e WATCHDOG -e S3C2410_WATCHDOG -e POWER_RESET -e POWER_RESET_SYSCON \
 -e REBOOT_MODE -e SYSCON_REBOOT_MODE -e USB_CONFIGFS_RNDIS -e USB_CONFIGFS_ECM -e EXTCON_SM5502 -e CFG80211 -e MAC80211 -m ATH10K -m ATH10K_SDIO \
 --set-str LOCALVERSION "-gta2srv" -d LOCALVERSION_AUTO
$M olddefconfig >/dev/null; $M mod2yesconfig >/dev/null
./scripts/config --file $O/.config -m ATH10K -m ATH10K_SDIO -m ATH10K_CE; $M olddefconfig >/dev/null
for k in I2C_CHARDEV ATH10K_SDIO SYSCON_REBOOT_MODE S3C2410_WATCHDOG USB_CONFIGFS_RNDIS DRM_SIMPLEDRM FB_SIMPLE OVERLAY_FS USER_NS MODULES; do grep -E "^(# )?CONFIG_$k[= ]" $O/.config; done
$M -j$(nproc) Image dtbs modules 2>&1 | grep -E " error|Error " | head -20
ls -l $O/arch/arm64/boot/Image $O/arch/arm64/boot/dts/exynos/exynos7870-gtactive2lte.dtb || exit 1
rm -rf $W/mod; $M INSTALL_MOD_PATH=$W/mod modules_install >/dev/null; KR=$(ls $W/mod/lib/modules); echo KR=$KR
# --- initramfs: busybox, MUIC->USB, boot-attempt counter (2 failed boots -> TWRP), loop rootfs, switch_root
I=$W/initramfs; rm -rf $I; mkdir -p $I/bin $I/dev $I/proc $I/sys $I/data $I/newroot
cp /bin/busybox $I/bin/busybox
cp /in/ml_init $I/init; chmod 755 $I/init
(cd $I && find . | cpio -o -H newc 2>/dev/null | gzip -9) > $O/initramfs.cpio.gz
# --- payload: /data/extlinux + /data/gta2srv/ml + modules tarball for the rootfs
P=/out/ml; rm -rf $P; mkdir -p $P/gta2srv/ml $P/extlinux
cp $O/arch/arm64/boot/Image $O/arch/arm64/boot/dts/exynos/exynos7870-gtactive2lte.dtb $O/initramfs.cpio.gz $P/gta2srv/ml/
cp /in/ml_extlinux.conf $P/extlinux/extlinux.conf
tar czf $P/gta2srv/ml/modules.tgz -C $W/mod lib
mkdir -p $P/gta2srv/ml/firmware/ath10k/QCA9377/hw1.0; for f in firmware-sdio-5.bin board-2.bin; do curl -sfL -o $P/gta2srv/ml/firmware/ath10k/QCA9377/hw1.0/$f https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath10k/QCA9377/hw1.0/$f; done
cp $O/.config /out/ml_kernel.config; ls -lR $P | head -30; echo MLDONE
