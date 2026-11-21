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
| eMMC | **HS200** (patches 0031–0032: `cap-mmc-highspeed`, `mmc-hs200-1_8v`, CIU clock 800 MHz): 157 MB/s read (DDR52: 81, legacy 25 MHz: 22.5). Writes ~27–32 MB/s, limited by the card. If a test dtb leaves the eMMC unreadable, the initramfs reboots into TWRP instead of looping |
| CPU | 8× A53 up to **1794 MHz** (boost OPPs). schedutil never selects the boost OPPs, so `gta2-perf` uses `ondemand` (up_threshold 70): ~11 % faster, 77 °C after 140 s all-core load. 1.9–2.0 GHz hangs |
| **USB-C host / docks** | **Works** (patches 0027–0030). New minimal S2MM005 CCIC driver (role switch + PD start commands), SM5705 OTG VBUS regulator, dwc3 `otg`. Tested with a HyperDrive Next 7-port dock (HD4003GL): RTL8153 gigabit Ethernet, USB ports, USB storage; with a PD charger in the dock the tablet charges and stays host (data-role swap by the CCIC firmware). USB 2.0 only (480 Mbit/s): Ethernet ~200+ Mbit/s. No HDMI (no DisplayPort alt mode). The RTL8153B wants `rtl_nic/rtl8153b-2.fw` from linux-firmware (works without it) |
| GPU | **Mali-T830 MP1 on panfrost** (patch 0024: G3D PLL table, DVFS 343–1001 MHz at 0.900–0.925 V on BUCK2). OpenGL ES 3.1 / GL 3.1 through Mesa, `/dev/dri/renderD128` (also usable from Docker with `--device /dev/dri/renderD128`). No Vulkan, OpenCL or video decode |
| Audio, camera, modem | Not yet (audio plan: [`../ztos/audio/AUDIO_PLAN.md`](../ztos/audio/AUDIO_PLAN.md)) |
| Docker | cgroup v2, overlay2 and user namespaces available (unlike 3.18). Kernels before r7 have no iptables `raw` table, so `docker.service` runs with `DOCKER_INSECURE_NO_IPTABLES_RAW=1` (otherwise Docker 28 cannot start containers); r7 has `IP_NF_RAW` |

### What was wrong with USB host (for anyone porting another S2MM005/SM5705 device)

1. **The CCIC waits for the AP.** As a source it sits in `PE_SRC_Wait_New_Capabilities` (pd_state 14) until the AP sends the vendor "alternate mode start" (`0x10 <- 03 31`) and "power nego start" (`0x10 <- 03 42`) commands. Turning VBUS on before the CCIC reaches a source state (3..7) makes it drop the attach and discharge VBUS against the boost: the tablet browned out once in testing. A PD dock also re-negotiated every 30–60 s without these commands.
2. **SM5705 MUIC `CONTROL.SW_OPEN` (bit 4) is active low.** It must be 1 (vendor init value `0x1f`) or the D+/D- switches stay open. Device mode happened to work anyway; a host never saw the attached device.
3. **The HS PHY needs a host tune.** With the device-mode `PHYPARAM0` the port detects a device but every port reset fails ("Cannot enable"). Host mode needs `COMPDISTUNE=7`, `TXVREFTUNE=5` and the D+/D- pull-downs (vendor `host_usbphy_hstune_parameter`), applied through `phy_set_mode()` (patch 0030).

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

Kernel `Image` from this tree with all patches (0001–0031) and `mainline/gta2.config` +
`mainline/usb-host.config` + `mainline/r7.config` (r7: BBR + fq, exFAT/NTFS3/F2FS, WireGuard, iptables raw, UAS),
device tree `exynos7870-gtactive2lte-safe5g.dtb` (DRM display + GPU + USB-C host + eMMC DDR52). `extlinux.conf` on the data partition:

```
default good
timeout 1
label good
  menu label Ubuntu Server Mini (mainline 6.18, r7)
  linux /gta2srv/ml/Image
  fdt /gta2srv/ml/exynos7870-gtactive2lte-safe5g.dtb
  append console=tty0 loglevel=4 fbcon=logo-count:1 panic=10 clk_ignore_unused pd_ignore_unused fbcon=rotate:2 s3c2410_wdt.tmr_atboot=0
```

Notes:
* The simple-framebuffer node is `x8r8g8b8` (patch 0023); `x8b8g8r8` swapped red and blue.
* The display modules are loaded at boot by `/etc/modules-load.d/gta2-display.conf` (they do not autoload).
* Do not enable `CONFIG_ATH10K_DEBUGFS`: its calibration-data read at start-up breaks `ath10k_sdio` (SDIO timeouts, no Wi-Fi).
* `gta2.sys=<name>` on the command line picks `/data/gta2srv/<name>/rootfs.img` (default `ml`).

### Performance profile (in the overlay)

* zram: 1.5 GB, lz4 (`gta2-zram`); sysctl `90-gta2.conf`: swappiness 150, page-cluster 0,
  watermark_scale_factor 125, dirty 3/10, fq_codel, TCP Fast Open.
* I/O: no scheduler on eMMC, zram and the loop root, readahead 128 kB (`60-gta2-io.rules`).
* CPU: `gta2-perf` caps both clusters at 1794 MHz and sets schedutil's rate limit; MGLRU on.
* Network (r7): BBR congestion control, `fq` qdisc (`92-gta2-net.conf`); Wi-Fi power saving off (`90-gta2-wifi-nopowersave.conf`).
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
