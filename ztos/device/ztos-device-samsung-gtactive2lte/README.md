# ztos-device-samsung-gtactive2lte

The device layer for ztOS on the Samsung Galaxy Tab Active2 LTE (SM-T395, Exynos 7870,
Mali-T830 MP1, 3 GB RAM, 800x1280 S6D7AA0 DSI panel mounted upside down, STM FTS8 touch,
QCA9377 Wi-Fi (ath10k_sdio) and Bluetooth (hci_uart QCA), SM5705 charger and fuel gauge,
microSD).

It goes on top of the ztOS GSI (`installer/ztos build --target gsi` in
github.com/Zerone-Laboratories/ztOS) and talks to it only through ztOSIAL. The layout copies
`ztos-device-samsung-starlte`.

| Path | What |
|---|---|
| `vendor/ztos/manifest.toml` | which ztOSIAL backend serves each interface, with this tablet's nodes (every unchecked value is marked UNVERIFIED) |
| `vendor/ztos/ial/gtactive2lte.py` | the one vendor backend: Sleep1 reports that suspend is off |
| `layer.sh`, `overlay/`, `packages.txt` | what goes into the GSI for this tablet. `layer.sh` follows the installer's contract (`$R $DEVSRC $DEVROOT step ch`) |
| `ztmetro/rotate-180.patch` | `ZTMETRO_ROTATE=180` for ztMETRO, which draws with raw GL and ignores wlroots output transforms |
| `kernel/ztos.config`, `kernel/README.md` | the kernel options ztOS needs that our 6.18 config lacks |
| `firmware/README.md` | which firmware files are needed and where they come from (no blobs in this repo) |
| `registry/devices/samsung-gtactive2lte/device.toml` | a draft entry for ztos-devices |

## Differences from starlte

- **Boot.** There is no `boot.img`, `scripts/build-boot.sh` or `flash.sh`. U-Boot
  `sysboot` boots our kernel from USERDATA, and our initramfs loop-mounts
  `/data/gta2srv/zt/rootfs.img`. `/etc/fstab` therefore has no root line, and
  `zboot-firstboot` is not armed, because it would try to shrink the mounted loop root.
- **Off on this tablet.** `layer.sh` masks these:
  - zrnperfd, which is tuned for the S9. `gta2-thermal` owns cpufreq here.
  - Waydroid, because the kernel has no binder.
  - the sleep targets.
- **Added units:**
  - `gta2-bootok` resets the initramfs boot counter.
  - `gta2-thermal` sets 1794 MHz boost with a step-down from 90 °C.
  - `gta2-bt-addr` sets the QCA9377 BD address.

The build is described in `../BUILD.md` and `../build-rootfs.sh`.
