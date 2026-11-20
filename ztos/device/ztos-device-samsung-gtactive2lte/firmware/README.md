# Firmware for gtactive2lte under ztOS

Nothing here is committed (no blobs in this repo, as in our kernel patches).
`build-rootfs.sh --firmware <dir>` copies `<dir>/.` into `/usr/lib/firmware/`.

| Part | Driver | Files the kernel asks for | Where from | Status |
|---|---|---|---|---|
| Wi-Fi QCA9377 (SDIO, mmc1) | `ath10k_sdio` | `ath10k/QCA9377/hw1.0/firmware-sdio-5.bin`, `board-2.bin` or `board.bin` | firmware: `linux-firmware-atheros` (packages.txt). Board data: the generic `board-2.bin` may not hold this card's ID; then convert the stock `bdwlan30.bin` (vendor `/vendor/firmware/` or `/system/etc/firmware/wlan/qca_cld/`) into `ath10k/QCA9377/hw1.0/board.bin` | UNVERIFIED (notes/dt.md: SDIO DMA untested; add `pio-mode` to &mmc1 if transfers fail) |
| Bluetooth QCA9377 (UART ttySAC0, serdev) | `hci_uart` + `btqca` | `qca/rampatch_00230302.bin`, `qca/nvm_00230302.bin` | `linux-firmware-atheros` | UNVERIFIED (3 Mbaud on Exynos UART untested) |
| GPU Mali-T830 | `panfrost` | none (Midgard needs no firmware) | - | - |
| Touch STM FTS8 | `stm_fts8` | none at runtime (we keep the flashed `fts8cd56_gtactive2` firmware) | - | notes/touch.md |
| Display DECON/DSIM, S6D7AA0 | exynosdrm, samsung-dsim, panel | none | - | - |
| MFC (video decode) | s5p-mfc | `s5p-mfc-v*.fw` | stock `/vendor/firmware` | not used by ztOS yet |

Folder layout to pass with `--firmware`:

```
fw/
  ath10k/QCA9377/hw1.0/board.bin     (only if board-2.bin has no matching entry)
```

Check on the tablet: `dmesg | grep -iE 'ath10k|qca|firmware'`.
