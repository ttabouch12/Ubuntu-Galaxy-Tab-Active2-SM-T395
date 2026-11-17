# Ubuntu Touch 24.04 (Halium 13) for Galaxy Tab Active2 LTE (SM-T395, Exynos 7870)

Community port, **alpha**. Built on the same kernel tree as the [LineageOS 20 OC ROM](https://github.com/ttabouch12/LineageOS-20-Galaxy-Tab-Active2-SM-T395)
(samsungexynos7870 lineage-22.2 base, kernel 3.18), Halium 13 GSI and the Ubuntu Touch 24.04-2.x rootfs.

## Status (2026-11-16)

| Works | Notes |
|---|---|
| Boot to Lomiri, display, touch, S Pen | Panel is mounted 180°: Lomiri shell rotated + libinput touch calibration |
| Wi-Fi | QCA9377 (firmware path set to /vendor/firmware) |
| Mobile network, SIM, IMEI | oFono over binder (`transport=binder:name=slot1`), LTE registration |
| Bluetooth | QCA9377 over ttySAC0 via bluebinder; BD address taken from EFS |
| Speakers (stereo TFA9896 amps), earpiece, microphones | PulseAudio-droid -> Halium HIDL compat -> 32-bit vendor audio HAL service |
| Volume / power / home keys, Back (Esc) and Recents (app spread) | capacitive keys via a small uinput helper |
| Vibration (hardware), brightness, battery, sensors (accel/gyro/light/prox/mag) | |
| USB networking (RNDIS, 10.15.19.82) + ssh (key only) | gadget is the legacy `android_usb`, usb-moded can't drive it |
| Camera HAL, GNSS HAL running | camera app works (its own UI is rotated, see below); GPS needs an outdoor test |

| Known issues | |
|---|---|
| Rotation is done in Lomiri, not in the compositor | apps that rotate themselves from the sensor (camera) show a flipped UI; boot splash is drawn by the system compositor |
| Recents key also opens the app drawer | Super is released after the spread shortcut |
| Bluetooth occasionally drops | under investigation |
| No auto-brightness, mobile data APN not configured | |
| Upstream UT rough edges | e.g. some click/X apps (Tux Racer) don't start |

## What it took (root causes found while porting)

1. ext4 `metadata_csum` on the rootfs image breaks on 3.18 after an unclean reset ("invalid superblock checksum") -> image built without it.
2. systemd sandboxing (`ProtectSystem`, `PrivateTmp`, namespaces...) fails on 3.18 -> drop-ins disabling it per unit.
3. Vendor `vndservicemanager` aborts with SELinux off -> its restart storm kills hwcomposer (black screen). Fixed by preloading Halium's `libselinux_stubs.so`.
4. Kernel panic ~25 s after boot: `gst-plugin-scan` probes `/dev/video*` and Samsung's fimc-is `VIDIOC_QUERYCAP` dereferences NULL -> kernel guard + GStreamer v4l2 plugins removed + `panic_on_oops=0`.
5. Lomiri abort "gralloc-mapper is missing": `/dev/hwbinder` was 0600 root, the phablet session couldn't reach the mapper -> udev rule 0666.
6. Audio HAL is 32-bit only -> HIDL compat path + `HYBRIS_USE_VENDOR_NAMESPACE=0` + `use_legacy_stream_set_parameters=true` (audio patches unsupported by this HAL).
7. Bluetooth HAL aborts "No Bluetooth Address!" (`/efs` doesn't exist in the container) -> `persist.service.bdroid.bdaddr`.

## Benchmarks (same tablet, Ubuntu Touch vs the Android container on the same kernel)

| Test | Ubuntu Touch 24.04 | Android userspace (container) |
|---|---|---|
| SHA-256, 1 thread (Python/OpenSSL, ARMv8 crypto) | 698 MB/s | – |
| SHA-256, 8 threads | 3496 MB/s | – |
| SHA-256 200 MB, coreutils vs toybox | 417 ms | 563 ms |
| Memory copy (dd /dev/zero -> /dev/null, 4 GB) | 6.2 GB/s | 5.7 GB/s |
| /userdata write 256 MB (fsync) | 50.6 MB/s | |
| Boot to userspace done | 25.3 s (4.3 kernel + 20.9 userspace) | |
| RAM used after boot (Lomiri + Android container) | ~1.33 GB of 2.75 GB | |

CPU runs the OC kernel (1.79 GHz both clusters, interactive governor), GPU DVFS max 1146 MHz.
Raw CPU/memory throughput is the same as Android (same kernel); UI smoothness depends on Lomiri/Mir rather than SurfaceFlinger.

## Install (from TWRP; wipes data)

1. Flash/keep the LineageOS 20 OC ROM's **vendor** (it lives in the CACHE partition) - the port reuses it.
2. In TWRP format `/data` as ext4, then push the images:
   ```
   adb push rootfs_ut-gta2.img      /data/rootfs.img          # unxz first
   adb push android-rootfs.img      /data/android-rootfs.img  # Halium 13 GSI (arm64)
   adb shell dd if=/tmp/boot.img of=/dev/block/mmcblk0p10    # boot_ut-gta2.img
   ```
3. Boot, then run `scripts/vendor_setup.sh` once as root and copy `scripts/gta2_hook.sh` to `/userdata/gta2_hook.sh`
   (`gta2_keys.py` to `/userdata/gta2/`). Optional: put your ssh public key in `/userdata/gta2/authorized_keys`
   for root ssh over USB (`ssh root@10.15.19.82`).

## Files

- `kernel_k22_to_ut-halium.patch` - kernel changes on top of the OC kernel tree (Halium config, AppArmor backport, tty0 console, fimc-is guard, panel `gta2_madctl` sysfs).
- `kernel.config`, `deviceinfo`, `overlay.tar.gz` - halium-generic-adaptation-build-tools inputs.
- `ut_repack.py` - builds the Samsung boot image (header SHA1 + `SEANDROIDENFORCE`).
- `scripts/` - boot hook, vendor setup, key mapper, Mir rotation experiment.
