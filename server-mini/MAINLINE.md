# Mainline Linux 6.18 on the Galaxy Tab Active2 (experimental)

Ubuntu Server Mini can also boot a **mainline Linux 6.18** kernel instead of Samsung's 3.18. The kernel is the
upstream tree plus the patches in [`mainline/patches/`](mainline/patches/). It boots the same Ubuntu userland and UI.

## Status

| Part | Status |
|---|---|
| Boot | S-Boot → U-Boot (in the BOOT partition) → `extlinux.conf` on the data partition → kernel with a built-in initramfs → Ubuntu on a loop image |
| Display | **DRM (DECON + DSIM + S6D7AA0 panel) works** with the `safe5g` device tree: the DECON sysmmu is off (physical scanout, patch 0025), Xorg fbdev on `exynosdrmfb`. Real backlight (`/sys/class/backlight/14800000.dsi.0`, Settings slider and volume keys) and real panel power-off (Power key). `gta2-fbinit` power-cycles the panel once when the session starts, which clears a doubled image left by the takeover from the bootloader. Fallback: `safe3`/`safe3g` (simple framebuffer, no backlight control) |
| Touch | STM FTS8 (new driver, patch 0001) |
| Wi-Fi | QCA9377 on SDIO, `ath10k_sdio`; board data read from the tablet's vendor partition. Needs `CONFIG_RESET_GPIO=y` (WLAN_EN is a `reset-gpios` of `mmc-pwrseq-simple`; without it mmc1 never powers up) |
| Bluetooth | HCI comes up over UART (QCA). Needs `qca/rampatch_00230302.bin` + `qca/nvm_00230302.bin` from linux-firmware for full use |
| Battery / charger | SM5705 MUIC, charger, fuel gauge (new drivers). The charger has `charge_behaviour` (auto / inhibit-charge), which the charge limit uses |
| Temperature | Minimal Exynos 7870 TMU driver (new), thermal zone with a 90 °C passive trip |
| **CPU frequency** | **Works.** New CMU_CPUCL0/1 clock driver + OPP tables, `cpufreq-dt`. 343 MHz–1586 MHz, plus boost 1690/1794 MHz. Before this, the mainline kernel ran at the bootloader's 902 MHz |
| SD card | `dw_mmc` channel 2, card-detect GPIO |
| GPU | **Mali-T830 MP1 on panfrost** (patch 0024: G3D PLL table, DVFS 343–1001 MHz at 0.900–0.925 V on BUCK2). OpenGL ES 3.1 / GL 3.1 through Mesa, `/dev/dri/renderD128` (also usable from Docker with `--device /dev/dri/renderD128`). No Vulkan, OpenCL or video decode |
| Audio, camera, modem | Not yet (audio plan: [`../ztos/audio/AUDIO_PLAN.md`](../ztos/audio/AUDIO_PLAN.md)) |
| Docker | cgroup v2, overlay2 and user namespaces available (unlike 3.18). The kernel has no iptables `raw` table, so `docker.service` runs with `DOCKER_INSECURE_NO_IPTABLES_RAW=1` (otherwise Docker 28 cannot start containers) |

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

## Recommended setup (2026-11-21)

Kernel `Image` from this tree with all patches (0001–0026) and `mainline/gta2.config`, device tree
`exynos7870-gtactive2lte-safe5g.dtb` (DRM display + GPU). `extlinux.conf` on the data partition:

```
default good
timeout 1
label good
  menu label Ubuntu Server Mini (mainline 6.18)
  linux /gta2srv/ml/Image
  fdt /gta2srv/ml/exynos7870-gtactive2lte-safe5g.dtb
  append console=tty0 loglevel=4 fbcon=logo-count:1 panic=10 clk_ignore_unused pd_ignore_unused fbcon=rotate:2 s3c2410_wdt.tmr_atboot=0
```

Notes:
* The simple-framebuffer node is `x8r8g8b8` (patch 0023); `x8b8g8r8` swapped red and blue.
* The display modules are loaded at boot by `/etc/modules-load.d/gta2-display.conf` (they do not autoload).
* `gta2.sys=<name>` on the command line picks `/data/gta2srv/<name>/rootfs.img` (default `ml`).

### Performance profile (in the overlay)

* zram: 1.5 GB, lz4 (`gta2-zram`); sysctl `90-gta2.conf`: swappiness 150, page-cluster 0,
  watermark_scale_factor 125, dirty 3/10, fq_codel, TCP Fast Open.
* I/O: no scheduler on eMMC, zram and the loop root, readahead 128 kB (`60-gta2-io.rules`).
* CPU: `gta2-perf` caps both clusters at 1794 MHz and sets schedutil's rate limit; MGLRU on.
* journald: volatile, 16 MB. Time zone: `rootfs_ml.sh` sets Europe/Istanbul; change it with `sudo timedatectl set-timezone <zone>`.

### Clean install (mainline only)

`build/docker/drootfs_ml.bat` builds a fresh Ubuntu 24.04 root image on Windows with Docker
(`rootfs_ml.sh` in an arm64 `ubuntu:24.04` container, then `mkimg_ml.sh` writes a 3 GB ext4
`rootfs-ml.img`). Copy it to `/data/gta2srv/ml/rootfs.img` from TWRP (`adb push`), next to the
kernel, dtb and `modules-<uname -r>.tgz`. On first boot add Wi-Fi in Settings (or drop a
`.nmconnection` into `/userdata/gta2srv/wifi/`) and an SSH key into `/userdata/gta2srv/authorized_keys`.

### Docker apps

Portainer (`:9443`) starts with the 500+ app catalogue from
[Lissy93/portainer-templates](https://github.com/Lissy93/portainer-templates) (`--templates`).
The built-in App store's Pi-hole sets `FTLCONF_dns_listeningMode=ALL`: in Docker's bridge network
Pi-hole 6's default `LOCAL` mode ignores queries from the LAN.

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
