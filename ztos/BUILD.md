# ztOS root filesystem for the Galaxy Tab Active2 LTE (SM-T395): build on Windows with Docker

The output is `ztos-rootfs.img`, an ext4 image file of about 4–6 GB. It goes at
`/data/gta2srv/zt/rootfs.img` and the gta2srv initramfs loop-mounts it, the same way
it mounts the Ubuntu image. The tablet's boot chain stays as it is: S-Boot → U-Boot →
extlinux.conf on USERDATA → our 6.18 kernel with its built-in initramfs. ztOS's own
flow (boot.img, fastboot, Heimdall, ztConflo's `flash.sh`) is not used.

## How it works

ztOS is a generic system image (GSI) plus a device layer per device.

- **No GSI is published.** ztConflo looks for one at
  `https://github.com/Zerone-Laboratories/ztos-build/releases/download/v<ver>/ztos-gsi-<ver>-aarch64.tar.zst`
  (`ztconflo/ztconflo/gsi.py`, `GSI_URL`). That address returned HTTP 404 for 0.2.0 and
  0.2.1 on 2026-11-20. `releases/latest/download/` on both ztOS and ztos-build also had no
  `ztos-gsi-*`, `ztos-starlte-root.img.*` or `ztos-qemu.img.*`.
- **So we build the GSI ourselves** from the ztOS monorepo
  (https://github.com/Zerone-Laboratories/ztOS, VERSION `0.2.1-BETA-1.1`, tested at commit
  `8bfb090`) with `installer/ztos build --target gsi`. The installer lives in
  `installer/ztos_installer/build.py`. The split `ztos-build` repo cannot build alone: it
  has no `os/`, `ial/`, `ztmetro/`, `sdk/`, `rootfs/` or `prebuilts/`.
- **`build-rootfs.sh` then adds our device layer.** It unpacks the GSI, installs
  `packages.txt`, rebuilds ztMETRO with the 180° patch if needed, and runs our
  `layer.sh`. That script adds the `/vendor/ztos/manifest.toml` and backend, the
  overlay, **our kernel modules** and the firmware. Finally the script creates the user
  and enables the units, then writes the image with `mke2fs -d`. Nothing is
  loop-mounted.

The container runs Arch Linux ARM as `linux/arm64`, emulated by Docker Desktop's qemu.
The installer sees an aarch64 host and needs no binfmt setup of its own. It uses
`unshare`, `mount` and `chroot`, so the container must run with `--privileged`.

## 0. What you need

- Windows 10/11, Docker Desktop with the WSL 2 backend, about 40 GB free on the Docker disk.
- From the kernel build (`/home/claude/gta2ml`), the outputs of **one and the same build**:
  - `modules.tgz`, containing `lib/modules/<uname -r>/...`. This is the layout of
    `pkg/payload/gta2srv/ml/modules.tgz`.
  - `.config` (optional), used to check ztOS's kernel contract.
- This folder (`/mnt/user-data/outputs/ztos/`): `build-rootfs.sh` and
  `ztos-device-samsung-gtactive2lte/`.

Check that arm64 containers run. This should print `aarch64`:

```powershell
docker run --rm --platform linux/arm64 alpine uname -m
```

## 1. Lay out the folders (PowerShell)

```powershell
mkdir C:\ztos\in, C:\ztos\out -Force
# copy build-rootfs.sh and ztos-device-samsung-gtactive2lte\ into C:\ztos\in\
# copy modules.tgz and the kernel .config (as kernel.config) into C:\ztos\in\
cd C:\ztos
curl.exe -L -o C:\ztos\in\ArchLinuxARM-aarch64-latest.tar.gz http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
```

## 2. Make the build container (Arch Linux ARM itself)

```powershell
docker import --platform linux/arm64 C:\ztos\in\ArchLinuxARM-aarch64-latest.tar.gz alarm-build
docker volume create ztos-work
docker run -it --privileged --platform linux/arm64 --name ztos-build `
  -v ztos-work:/work -v C:\ztos\in:/in:ro -v C:\ztos\out:/out `
  alarm-build /bin/bash
```

The working tree stays in the Docker volume `/work`, an ext4 filesystem inside the WSL VM.
The Windows folders would break ownership and modes and make the build slow. Only the
finished image is written to `C:\ztos\out`.

## 3. Inside the container: the build tools

```bash
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf     # no real mount table in a container
pacman-key --init && pacman-key --populate archlinuxarm
pacman --disable-sandbox -Syu --noconfirm --needed \
  base-devel git python python-pip pyside6 mesa util-linux libarchive dosfstools mtools \
  e2fsprogs zstd patch curl shadow
```

## 4. Get ztOS and reuse the tarball you already downloaded

```bash
cd /work
git clone https://github.com/Zerone-Laboratories/ztOS ztOS
git -C ztOS checkout 8bfb09011757f06c68a055fbfd95ea07d5e4fbe1   # the commit this port was written against (optional)
mkdir -p ztOS/build && cp /in/ArchLinuxARM-aarch64-latest.tar.gz ztOS/build/alarm.tar.gz
```

You do not need git-lfs. `prebuilts/ztOSAndroidRuntimeV1/packages`, which the installer
requires, and `prebuilts/ztos-media` are ordinary files in the repo.

## 5. Build: the GSI first, then the tablet's root filesystem

```bash
bash /in/build-rootfs.sh --build-gsi --ztos-src /work/ztOS \
  --device /in/ztos-device-samsung-gtactive2lte \
  --modules /in/modules.tgz --kconfig /in/kernel.config \
  --size 4G --user zerone --password toor --timezone Europe/Berlin \
  --work /work/zt --out /out/ztos-rootfs.img
# optional: --firmware /in/fw   (Wi-Fi board data, see ztos-device-.../firmware/README.md)
#           --ssh-key /in/id_ed25519.pub
```

- The GSI step takes 1–3 h under emulation. It produces
  `/work/ztOS/build/ztos/gsi/ztos-gsi-0.2.1-aarch64.tar.zst`, plus a `.sha256`.
- If you only change the device layer, rebuild from that GSI:
  `bash /in/build-rootfs.sh --gsi /work/ztOS/build/ztos/gsi/ztos-gsi-0.2.1-aarch64.tar.zst --modules /in/modules.tgz ...`
- If the root is larger than `--size`, the image grows to fit. The script reports the
  final size. Expect about 4–5 GB, because the GSI carries base-devel, Qt6/PySide6,
  WPE WebKit and GStreamer.
- At the end, the "checks" step shows:
  - the output of `ztos-ial check`;
  - whether Mesa has `panfrost_dri.so`, `exynos_dri.so` and `kmsro_dri.so`;
  - the module directory name, which must equal the kernel's `uname -r`;
  - the kernel contract checked against your `.config`.

Result: `C:\ztos\out\ztos-rootfs.img` and `ztos-rootfs.img.sha256`.

## 6. Put it on the tablet

Copy it from TWRP (adb) or from the running Ubuntu system (scp over USB networking or Wi-Fi).

```bash
# TWRP (USERDATA mounted at /data):
adb shell mkdir -p /data/gta2srv/zt/inject
adb push ztos-rootfs.img /data/gta2srv/zt/rootfs.img
# or from Ubuntu, where /data is /userdata:
scp ztos-rootfs.img <user>@<tablet>:/userdata/gta2srv/zt/rootfs.img
```

## 7. Boot it: an initramfs change and an extlinux label (for the kernel engineer)

The current `pkg/initramfs/init` hard-codes `R=/data/gta2srv/ml/rootfs.img` and the
`ml/inject` folder. Make the system selectable from the kernel command line instead,
keeping `ml` as the default:

```sh
SYS=ml; for a in $(cat /proc/cmdline); do case $a in gta2.sys=*) SYS=${a#gta2.sys=} ;; esac; done
R=/data/gta2srv/$SYS/rootfs.img          # was /data/gta2srv/ml/rootfs.img
INJ=/data/gta2srv/$SYS/inject            # was /data/gta2srv/ml/inject
```

Then add a label to `/data/extlinux/extlinux.conf`. Booting it once as a trial uses the
existing `trial` / `extlinux.conf.good` mechanism.

```
label ztos
  menu label ztOS (mainline)
  linux /gta2srv/ml/Image
  fdt /gta2srv/ml/exynos7870-gtactive2lte.dtb
  append console=tty0 loglevel=5 panic=10 clk_ignore_unused pd_ignore_unused s3c2410_wdt.tmr_atboot=1 s3c2410_wdt.tmr_margin=60 gta2.sys=zt
```

- Drop `fbcon=rotate:2` here: ztMETRO owns the screen.
- The boot counter stays in `/data/gta2srv/ml/tries`. The image's `gta2-bootok.service`
  resets it 30 s after boot. Without that, the third ztOS boot would disarm extlinux.

## 8. First boot: what to check (over `ssh zerone@172.16.42.1`, the USB NCM gadget)

```bash
ls -l /dev/dri/                     # card0 (exynos) + renderD128 (panfrost) expected
modetest -M exynos -c               # connector DSI-1 connected, 800x1280 mode
eglinfo -B 2>/dev/null | grep -i renderer   # must say Mali-T830 / Panfrost, not llvmpipe
ztos-ial status; ztos-ial test      # Power1 on sm5705-fuelgauge, Display1 on the backlight
journalctl -b -u greetd; cat ~/.local/state/ztmetro.log
libinput list-devices | grep -A5 -i fts     # then tap the corners: see 90-gta2-touch.rules
```

Until panfrost works, you can run ztMETRO on llvmpipe for a KMS-only test: uncomment the
three software-GL lines in `/etc/ztos/session.env`. It is slow, and ztConflo's
promotion refuses llvmpipe.
