# Mainline Linux 6.18 on the Galaxy Tab Active2 (experimental)

Ubuntu Server Mini can also boot a **mainline Linux 6.18** kernel instead of Samsung's 3.18. The kernel is the
upstream tree plus the patches in [`mainline/patches/`](mainline/patches/). It boots the same Ubuntu userland and UI.

## Status

| Part | Status |
|---|---|
| Boot | S-Boot → U-Boot (in the BOOT partition) → `extlinux.conf` on the data partition → kernel with a built-in initramfs → Ubuntu on a loop image |
| Display | **simple framebuffer** (the bootloader's), Xorg fbdev. DRM (DECON + DSIM + S6D7AA0 panel) is in the patches but **hangs at takeover**, so it is off in the default device tree |
| Touch | STM FTS8 (new driver, patch 0001) |
| Wi-Fi | QCA9377 on SDIO, `ath10k_sdio`; board data read from the tablet's vendor partition |
| Bluetooth | HCI comes up over UART (QCA). Needs `qca/rampatch_00230302.bin` + `qca/nvm_00230302.bin` from linux-firmware for full use |
| Battery / charger | SM5705 MUIC, charger, fuel gauge (new drivers). The charger has `charge_behaviour` (auto / inhibit-charge), which the charge limit uses |
| Temperature | Minimal Exynos 7870 TMU driver (new), thermal zone with a 90 °C passive trip |
| **CPU frequency** | **Works.** New CMU_CPUCL0/1 clock driver + OPP tables, `cpufreq-dt`. 343 MHz–1586 MHz, plus boost 1690/1794 MHz. Before this, the mainline kernel ran at the bootloader's 902 MHz |
| SD card | `dw_mmc` channel 2, card-detect GPIO |
| GPU, audio, camera, modem | Not yet |
| Docker | cgroup v2, overlay2 and user namespaces available (unlike 3.18) |

### CPU voltages and overclocking

The vendor kernel gets per-chip voltages from Samsung's ECT firmware table. The mainline OPP table uses the values
read from this unit on the vendor kernel: 1586 MHz at 1.00625 V, 1690 MHz at 1.06875 V, and 1794 MHz at 1.0875 V.
1794 MHz passed a 90 s, 8-core run that checksums 32 MB in a loop, with zero errors. It reached 82 °C without
throttling. The lower OPPs reuse safe margins until a full ECT dump is done.

Single-core speed for one SHA-256 of 32 MB:

| Clock | Time |
|---|---|
| 902 MHz (old mainline) | 119 ms |
| 1586 MHz | 74 ms |
| 1794 MHz | 67 ms |

**1.9–2.0 GHz is not possible on this chip.** 1924/2002 MHz already reset under 8-core load on the vendor kernel
(the power IC hits its current limit). On mainline, 1898–2002 MHz ran on 4 cores only (cluster 1) at up to
1.275 V and the tablet hung. 1794 MHz is the ceiling. Settings → CPU offers Saver / Stock / 1.7 / 1.8 GHz.

## Safe testing (how new kernels are tried without bricking)

* `extlinux.conf.good` is the last known-good config. A test kernel is booted **once**: if `/extlinux/trial`
  exists, the initramfs copies `extlinux.conf.good` back as the first thing it does. Any crash or reset therefore
  lands on the good kernel.
* `gta2-trialguard.service` reboots back to the good kernel 8 minutes after a test boot unless you confirm it
  (`mv /userdata/extlinux/trial.booted /userdata/extlinux/trial.ok`). This covers kernels that boot but lose the network.
* After 2 failed boots in a row the initramfs disarms `extlinux.conf` and U-Boot drops to TWRP.
* Holding **Volume Down** during U-Boot opens a menu: Ubuntu / TWRP / Download / console.
* A kernel that hangs *before* the initramfs runs (a built-in driver at probe) is the one case this cannot catch.
  That is how the DRM test froze. Recovery: hold Power + Volume Down, then pick TWRP in U-Boot.

## Build

```
# Linux v6.18 + patches
git clone --depth 1 -b v6.18 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
cd linux && git am ../mainline/patches/*.patch
# config: arm64 defconfig trimmed to ARCH_EXYNOS + mainline/gta2.config (see mainline/build.sh)
# initramfs: mainline/initramfs-init + a static busybox, listed in mainline/initramfs.list
make ARCH=arm64 LLVM=1 Image dtbs modules
```

Install: copy `Image` and `exynos7870-gtactive2lte-safe3.dtb` to `/data/gta2srv/ml/`, and the modules as
`/data/gta2srv/ml/modules-<kernel release>.tgz`; `gta2-ml-setup` installs them on first boot. Point
`/data/extlinux/extlinux.conf` at them. The U-Boot image and its environment are built by `build/docker/ub.sh`.

## Credits

Exynos 7870 mainline work: Kaustabh Chakraborty and the exynos7870-mainline / postmarketOS community.
SM5705, FTS8, TMU, CPU clock, charger and board support for this tablet: this repo. All GPL-2.0.
