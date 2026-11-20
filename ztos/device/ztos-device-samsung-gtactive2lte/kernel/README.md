# Kernel

Our own mainline 6.18 tree (gta2ml), not built here. ztOS needs from it:

- the options in `ztos.config` (PSI is the only HARD gap in out/.config);
- a working KMS chain: exynosdrm (DECON `samsung,exynos7870-decon`) + samsung-dsim +
  panel-samsung-s6d7aa0 (gtactive2 variant), a backlight in /sys/class/backlight;
- panfrost bound to gpu@11400000 (`/dev/dri/renderD128`), `&gpu` enabled in the DTS;
- the modules tarball of the SAME build (`uname -r` must equal the folder name in
  lib/modules/; the payload modules.tgz in pkg/ is for 6.18.0-gta2srv+ and has no
  exynosdrm/panfrost modules, i.e. it predates the current out/.config).

Mesa side: Arch Linux ARM's `mesa` carries panfrost_dri and the kmsro "exynos"
loader name; build-rootfs.sh checks /usr/lib/dri for both.
