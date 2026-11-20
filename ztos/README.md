# ztOS on the Galaxy Tab Active2 LTE (SM-T395): experimental, not continued

[ztOS](https://github.com/Zerone-Laboratories/ztOS) (Arch Linux ARM + the ztMETRO shell) running on the
tablet with our mainline 6.18 kernel. It boots and is usable, but the project stopped here: the
display and audio need too much driver work for this tablet. This folder keeps everything as it was
on 2026-11-20 so anyone can pick it up.

## Status

| Part | State |
|---|---|
| Boot (S-Boot → U-Boot → extlinux → 6.18 + initramfs, `gta2.sys=zt`) | works |
| ztMETRO shell, touch, rotation (180°), all hardware keys | works |
| Wi-Fi (QCA9377, ath10k_sdio), Bluetooth, internet | works |
| GPU: Mali-T830 MC1 on panfrost, DVFS 343–1001 MHz (0.900–0.925 V) | works (`Mali-T830 MC1 (Panfrost)`, Mesa 26.3) |
| Display path used: simpledrm shows, panfrost renders (`WLR_RENDER_DRM_DEVICE`) | works, some lag (CPU copy per frame) |
| Web browser (WPE WebKit) | needs `WEBKIT_SKIA_ENABLE_CPU_RENDERING=1` (black pages with GPU raster) |
| Real display driver (exynosdrm DECON + DSIM + s6d7aa0) | binds and lights the panel without the DECON sysmmu, see below |
| Screen off on lock, hardware brightness | no (needs the real display driver) |
| Sound | no driver (see `audio/AUDIO_PLAN.md`) |
| Camera, modem, sensor hub, vibrator | no mainline drivers; ztOS components for them are turned off |
| Wi-Fi bars in the status bar | show low although the link is -38 dBm / 100 % (source of the bars not found) |

## What is in here

- `device/ztos-device-samsung-gtactive2lte/`: the ztOS device layer (`layer.sh`, overlay, ztOSIAL
  manifest and backend, packages, ztMETRO 180° patch). It includes the performance profile from
  `OPTIMIZE.md`: lz4/zstd zram, a 3 GB sysctl profile, systemd-oomd, volatile journald, eMMC I/O
  rules, `gta2-perf` (schedutil 2 ms, 1794 MHz cap, ~900 MHz floor), masked S9-only units, and a
  trimmed `ztoscoresensorframework` component list.
- `build/`: `build-rootfs.sh` (GSI → tablet image with our modules) and the Docker scripts used on
  Windows (`zt_gsi5.sh` builds the GSI, `zt_rootfs2.sh` builds the image). Pacman runs without the
  10 s download timeout and with several mirrors; a killed run's stale `db.lck` is removed.
- `BUILD.md`, `OPTIMIZE.md`: build guide and the optimisation plan.
- `audio/`: findings and plan for sound (COD3026X codec inside the PMIC, s1402x mixer, 10-bit I2C),
  a draft device tree and the hsi2c 10-bit patch (compiled, not tested).
- Kernel: `../server-mini/mainline/` (patches 0001–0026, `gta2.config`, `initramfs-init` with the
  `gta2.sys=<name>` selector).

Not in here: Wi-Fi board data (`board.bin` is Samsung's `bdwlan30.bin`, read from the tablet's own
vendor partition) and the 6 GB image.

## Kernel notes

- **r4**: `CONFIG_RESET_GPIO=y`. Without it `pwrseq_simple` waits forever for WLAN_EN and the SDIO
  Wi-Fi card never powers up (`pwrseq_simple: reset control not ready`).
- **simplefb** is `x8r8g8b8` (patch 0023). `x8b8g8r8` swapped red and blue.
- **r5**: PSI (required by ztOS), MGLRU, lz4 zram, 39-bit VA, HZ 300, uclamp, binder.
- **r6g**: G3D PLL table and DVFS for panfrost (patch 0024), `safe3g` dtb.
- **exynosdrm without the DECON sysmmu** (patch 0025): physical DMA when the sub device has no IOMMU,
  and no vblank handling before bind (the bootloader leaves DECON's frame IRQ on; a failed bind
  used to crash in `drm_crtc_handle_vblank`).

## Where the display work stopped

With `safe5g` (DECON sysmmu disabled) the full DRM stack binds: `card0-DSI-1 connected 800x1280`,
backlight `14800000.dsi.0`, ztMETRO runs on it. Two problems remain:

1. Text is doubled with colour fringes after the first modeset. A DPMS off/on (lock/unlock) clears
   it, so the panel needs a proper reset when the driver takes it over from the bootloader.
2. `exynos_drm_gem_prime_import_sg_table: buffer chunks must be mapped contiguously`: without the
   sysmmu, DECON can only scan out physically contiguous buffers, so GPU/client buffers cannot be
   imported. The UI gets slower and the browser does not start. The fix is to run DECON behind its
   sysmmu, which needs the bootloader's splash at `0x67000000` to stay mapped while the IOMMU takes
   over (an earlier test with the sysmmu froze the tablet at takeover).
