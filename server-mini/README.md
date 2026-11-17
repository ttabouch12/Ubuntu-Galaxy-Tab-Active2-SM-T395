# Ubuntu Server Mini for Galaxy Tab Active2 LTE (SM-T395)

Native Ubuntu 24.04 LTS (arm64), **no Android underneath**, built to turn the tablet into a small
always-on server with a touch screen. Install and first steps are in the [main README](../README.md).

## What's in it

| Part | How |
|---|---|
| Kernel | LineageOS samsungexynos7870 3.18.140 (same tree as the OC ROM, OC to 1.79 GHz), Halium config + Docker options |
| Boot | `boot.img` with a Halium initramfs + a small hook: if `/data/gta2srv/enabled` exists it loop-mounts `/data/gta2srv/rootfs.img` as `/` |
| Init | systemd 255, cgroup v1 (see below) |
| Display | plain fbdev on the Exynos DECON (`/dev/fb0`, 800x1280), Xorg `fbdev` + shadowfb, rotated 180° (panel is mounted upside down) |
| UI | matchbox WM (one fullscreen app at a time), Tk launcher / settings / second-screen apps, xterm, matchbox-keyboard |
| Network | NetworkManager + wpa_supplicant (QCA9377, qcacld driver, firmware from the vendor partition), USB RNDIS gadget with DHCP for the laptop |
| Server | OpenSSH, Docker 29 (`vfs` storage, data in `/data/gta2srv/docker`), Portainer CE |
| Second screen | moonlight-embedded (SDL, software H.264 decode) |
| Memory | 512 MB zram swap, volatile journal (32 MB) |

Measured on the tablet: **~240 MB RAM used** with the launcher on screen (Ubuntu Touch: 1.33 GB),
~280 MB with Portainer running, 830 MB on disk, boot 12-19 s (systemd-analyze), Docker containers start in ~1 s.
Tested as a clean install from the TWRP zip: SSH key + Wi-Fi import, Docker (bridge network, port publishing, `-m`/`--cpus` limits), Portainer, launcher, NTP.

## Removed on purpose

Android container and all HALs, Lomiri/Mir, PulseAudio, Bluetooth stack, oFono/modem, camera,
sensors, GPS, avahi, snapd, apt timers, docs/man pages/locales.

## How the hard parts were solved

1. **Display without Android.** The DECON fbdev driver only scans out after `FBIOPAN_DISPLAY`, and its
   bitfields are empty at boot. `gta2-fbinit` sets XRGB8888 and pans once; Xorg then draws normally.
   This only works because Android's hwcomposer never touches DECON here.
2. **Docker crashed the kernel.** `runc` + `CONFIG_USER_NS` hit a Samsung RKP/credential bug
   (`sget_userns` with a garbage user namespace). User namespaces are disabled in this kernel (Docker
   doesn't need them).
3. **Docker on the backported cgroup2** fails (`bpf_prog_query(BPF_CGROUP_DEVICE)`). The Samsung
   bootloader ignores the boot.img cmdline, so `/usr/sbin/init` is a tiny wrapper
   (`gta2-init`) that hands systemd `systemd.unified_cgroup_hierarchy=0` through
   `SYSTEMD_PROC_CMDLINE`. With cgroup v1, memory/CPU limits work (`docker run -m 64m --cpus 0.5`).
4. **Overlay storage**: 3.18 overlayfs has no multi-lowerdir and Docker 29 dropped
   fuse-overlayfs, so the `vfs` driver is used. Images take their full size on disk; fine for light services.
5. **Random kernel panics at boot**: udev's `v4l_id` probing the Exynos camera nodes. The rule is masked.

## Headless setup (no screen needed)

From TWRP (or any Linux reading the data partition), before the first boot:

```
/data/gta2srv/authorized_keys          -> appended to gta2's ~/.ssh/authorized_keys
/data/gta2srv/wifi/<name>.nmconnection -> NetworkManager keyfile, auto-connects
```

Example Wi-Fi keyfile:

```
[connection]
id=home
type=wifi
[wifi]
ssid=MyWiFi
[wifi-security]
key-mgmt=wpa-psk
psk=secretpassword
[ipv4]
method=auto
```

## Files on the tablet

| Path | |
|---|---|
| `/data/gta2srv/rootfs.img` | the whole OS (2.4 GB ext4 image, `/`) |
| `/data/gta2srv/enabled` | delete it to disable this OS (the boot image then falls back to Ubuntu Touch / Halium layout) |
| `/data/gta2srv/docker` | Docker images, containers and volumes |
| `/userdata` | the full data partition, mounted inside the OS |

## Known limits

* No GPU acceleration (Mali-T830 needs the Android blob), so Moonlight decodes on the CPU.
* Kernel 3.18: no user namespaces (rootless containers, userns-remap), no overlay2, no blkio throttling.
* No virtual machines (EL2 is taken by Samsung's hypervisor, no KVM in this kernel).
* Moonlight touch input and Sunshine pairing are not tested end to end yet (no Sunshine host during development).

## Build it yourself

On any Debian/Ubuntu x86_64 machine with `qemu-user-binfmt`:

```
sudo bash build/stage1_debootstrap.sh     # Ubuntu 24.04 arm64 minbase + packages
sudo bash build/stage2_configure.sh       # overlay/, user, services, moonlight-embedded, rootfs.img
sudo bash build/pack_twrp_zip.sh          # boot.img + rootfs.img.gz -> TWRP zip
```

Paths inside the scripts point at the author's build box (`/home/builder/srv`, `/root/upload`), adjust them.
The kernel is the [Ubuntu Touch kernel patch](../ubuntu-touch/) with `CONFIG_USER_NS` off and
`POSIX_MQUEUE`, `CFS_BANDWIDTH`, `DUMMY` on; the initramfs hook is in `build/initrd_gta2srv.patch`.

## Roadmap (v2)

* Docker Swarm cluster mode (several tablets / PCs, managed from Portainer)
* Mainline-based kernel (postmarketOS exynos7870 work) for overlay2, user namespaces, cgroup v2
* Trim the kernel (camera/modem/audio drivers) and reclaim the modem/GNSS reserved RAM (~150 MB)
