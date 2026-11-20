set -e
export PATH=/tmp/flexinst/bin:$PATH
cd /home/claude/gta2ml/linux; O=/home/claude/gta2ml/out; mkdir -p $O
M="make O=$O ARCH=arm64 LLVM=1"
$M defconfig >/dev/null
for a in $(grep -oE "^CONFIG_ARCH_[A-Z0-9_]+=y" $O/.config | cut -d= -f1 | sed 's/CONFIG_//'); do case $a in ARCH_EXYNOS|ARCH_MMAP_RND*|ARCH_HAS*|ARCH_SUPPORTS*|ARCH_WANT*|ARCH_USE*|ARCH_INLINE*|ARCH_KEEP*|ARCH_PROC*|ARCH_SPARSEMEM*|ARCH_SELECT*|ARCH_HIBER*|ARCH_FORCE*|ARCH_BINFMT*|ARCH_SUSPEND*|ARCH_CORRECT*|ARCH_STACKWALK|ARCH_ENABLE*|ARCH_FLATMEM*|ARCH_DMA*|ARCH_NR*|ARCH_HAVE*) ;; *) ./scripts/config --file $O/.config -d $a;; esac; done
for s in DRM_NOUVEAU DRM_AMDGPU DRM_RADEON DRM_I915 DRM_MSM DRM_TEGRA SND SOUND MEDIA_SUPPORT VIDEO_DEV DVB_CORE INFINIBAND CAN WLAN_VENDOR_INTEL WLAN_VENDOR_REALTEK WLAN_VENDOR_BROADCOM WLAN_VENDOR_MARVELL WLAN_VENDOR_MEDIATEK WLAN_VENDOR_TI NET_VENDOR_INTEL NET_VENDOR_MELLANOX NET_VENDOR_BROADCOM NET_VENDOR_REALTEK STAGING; do ./scripts/config --file $O/.config -d $s; done
./scripts/kconfig/merge_config.sh -m -O $O $O/.config ../notes/gta2-full.config >/dev/null
$M olddefconfig >/dev/null
for k in CPUFREQ_DT LOCALVERSION EXTCON_SM5705 MFD_SM5705 CHARGER_SM5705 BATTERY_SM5705 CPUFREQ_DT REGULATOR_S2MPS11 TOUCHSCREEN_STM_FTS8 DRM_EXYNOS DRM_PANEL_SAMSUNG_S6D7AA0 DRM_PANFROST ATH10K_SDIO USB_CONFIGFS_RNDIS SYSCON_REBOOT_MODE S3C2410_WATCHDOG I2C_CHARDEV OVERLAY_FS; do grep -E "^(# )?CONFIG_$k[= ]" $O/.config || echo "CONFIG_$k missing"; done
$M -j2 Image dtbs modules 2>&1 | grep -E "error:|Error [0-9]|warning: .*gta2|fts8" | head -40
ls -l $O/arch/arm64/boot/Image $O/arch/arm64/boot/dts/exynos/exynos7870-gtactive2lte.dtb
echo BUILD_DONE
