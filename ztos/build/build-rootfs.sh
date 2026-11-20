#!/bin/bash
# build-rootfs.sh: ztOS (Zerone-Laboratories) root filesystem for the Galaxy Tab
# Active2 LTE (SM-T395, gtactive2lte) as an ext4 IMAGE FILE, for the gta2srv boot
# chain (S-Boot -> U-Boot -> extlinux.conf on USERDATA -> our kernel + built-in
# initramfs, which loop-mounts /data/gta2srv/zt/rootfs.img and switch_roots).
# No boot.img, no fastboot/heimdall: ztConflo's flow is not used.
#
# Runs as root on an aarch64 Linux (native, or the linux/arm64 Docker container
# of BUILD.md, started with --privileged). Steps:
#   1. (--build-gsi) build ztOS's generic system image from a ztOS checkout:
#      installer/ztos build --target gsi  -> ztos-gsi-<ver>-aarch64.tar.zst
#      (no GSI is published: ztconflo/gsi.py's GSI_URL
#       https://github.com/Zerone-Laboratories/ztos-build/releases/download/v<ver>/ztos-gsi-<ver>-aarch64.tar.zst
#       answered 404 for 0.2.0 and 0.2.1 on 2026-11-20)
#   2. unpack the GSI, add packages.txt, ztMETRO's 180-degree patch, the device
#      layer (layer.sh: /vendor/ztos manifest, overlay, our modules, firmware),
#      the user, and enable the units
#   3. mke2fs -d: ext4 image, no loop mount needed
#
# Usage:
#   build-rootfs.sh --build-gsi --ztos-src /work/ztOS --modules /in/modules.tgz [options]
#   build-rootfs.sh --gsi /work/ztos-gsi-0.2.1-aarch64.tar.zst --modules /in/modules.tgz [options]
# Options:
#   --device DIR      the device repo (default: ztos-device-samsung-gtactive2lte next to this script)
#   --firmware DIR    copied into /usr/lib/firmware (see the device repo's firmware/README.md)
#   --kconfig FILE    our kernel's .config: checked against ztOS's kernel contract
#   --size SIZE       image size, default 4G; raised if the root does not fit
#   --user NAME --password PW   default zerone / toor (ztOS's documented defaults)
#   --hostname NAME   default gtactive2lte;  --timezone ZONE  default UTC
#   --ssh-key FILE    authorized_keys for the user
#   --work DIR        scratch (default /work/zt); --out FILE (default /out/ztos-rootfs.img)
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEVICE=$HERE/ztos-device-samsung-gtactive2lte
GSI= BUILD_GSI=0 ZTOS_SRC= MODULES= FIRMWARE= KCONFIG=
SIZE=4G USERNAME=zerone PASSWORD=toor HOSTNAME_=gtactive2lte TIMEZONE=UTC SSHKEY=
WORK=/work/zt OUT=/out/ztos-rootfs.img

while [ $# -gt 0 ]; do
	case $1 in
	--gsi) GSI=$2; shift ;;
	--build-gsi) BUILD_GSI=1 ;;
	--ztos-src) ZTOS_SRC=$2; shift ;;
	--device) DEVICE=$2; shift ;;
	--modules) MODULES=$2; shift ;;
	--firmware) FIRMWARE=$2; shift ;;
	--kconfig) KCONFIG=$2; shift ;;
	--size) SIZE=$2; shift ;;
	--user) USERNAME=$2; shift ;;
	--password) PASSWORD=$2; shift ;;
	--hostname) HOSTNAME_=$2; shift ;;
	--timezone) TIMEZONE=$2; shift ;;
	--ssh-key) SSHKEY=$2; shift ;;
	--work) WORK=$2; shift ;;
	--out) OUT=$2; shift ;;
	-h|--help) sed -n 2,40p "$0"; exit 0 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done

say() { echo "zt-gta2: $*"; }
die() { echo "zt-gta2: ERROR: $*" >&2; exit 1; }
step() { echo; echo "=== $* ==="; }

[ "$(id -u)" = 0 ] || die "run as root (inside the --privileged container)"
[ "$(uname -m)" = aarch64 ] || die "run on aarch64 (docker run --platform linux/arm64 ...): the chroot runs ARM pacman"
for t in bsdtar mke2fs e2fsck zstd patch mount chroot; do
	command -v $t > /dev/null || die "missing $t (pacman -S libarchive e2fsprogs zstd patch util-linux)"
done
[ -f "$DEVICE/vendor/ztos/manifest.toml" ] || die "no device repo at $DEVICE"
[ -z "$MODULES" ] || [ -f "$MODULES" ] || die "no modules tarball $MODULES"

# A device repo that came through Windows (Docker Desktop bind mount, git with
# autocrlf) has 0777 modes and CRLF line ends: systemd and udev complain about
# world-writable files, and a CRLF shebang does not run. Work on a clean copy.
mkdir -p "$WORK"
rm -rf "$WORK/device"; cp -r "$DEVICE" "$WORK/device"; DEVICE=$WORK/device
find "$DEVICE" -type d -exec chmod 755 {} +
find "$DEVICE" -type f -exec chmod 644 {} +
find "$DEVICE/overlay/usr/local/sbin" -type f -exec chmod 755 {} +
find "$DEVICE" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.toml' -o -name '*.rules' -o -name '*.service' \
	-o -name '*.conf' -o -name '*.env' -o -name '*.txt' -o -name '*.patch' -o -path '*/sbin/*' -o -name target \) \
	-exec sed -i 's/\r$//' {} +
PATCH=$DEVICE/ztmetro/rotate-180.patch

# ---- 1. the GSI ------------------------------------------------------------------
if [ "$BUILD_GSI" = 1 ]; then
	[ -f "$ZTOS_SRC/installer/ztos" ] || die "--build-gsi needs --ztos-src <ztOS checkout> (github.com/Zerone-Laboratories/ztOS)"
	step "ztMETRO: the 180-degree patch into $ZTOS_SRC"
	if grep -q ZTMETRO_ROTATE "$ZTOS_SRC/ztmetro/ztmetro.c"; then
		say "already patched"
	else
		patch -p1 -d "$ZTOS_SRC" < "$PATCH"
	fi
	step "building the ztOS GSI (installer/ztos build --target gsi; 1-3 h under qemu)"
	( cd "$ZTOS_SRC" && python3 installer/ztos build --target gsi )
	GSI=$(ls -t "$ZTOS_SRC"/build/ztos/gsi/ztos-gsi-*-aarch64.tar.zst | head -n1)
fi
[ -n "$GSI" ] && [ -f "$GSI" ] || die "no GSI: give --gsi <tarball> or --build-gsi"
say "GSI: $GSI"

# ---- 2. the root -----------------------------------------------------------------
R=$WORK/root
cleanup() {
	for m in var/cache/pacman/pkg tmp proc sys dev; do
		mountpoint -q "$R/$m" 2>/dev/null && umount -lR "$R/$m" || true
	done
	mountpoint -q "$R" 2>/dev/null && umount -l "$R" || true
}
trap cleanup EXIT

step "unpacking the GSI"
cleanup
rm -rf "$R"; mkdir -p "$R" "$WORK/pkg-cache"
bsdtar -xpf "$GSI" -C "$R" --numeric-owner
[ -f "$R/usr/share/ztos/gsi.json" ] || die "$GSI is not a ztOS GSI (no /usr/share/ztos/gsi.json)"
say "GSI version $(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$R/usr/share/ztos/gsi.json" | head -n1)"

mount --bind "$R" "$R"
mount --rbind /dev "$R/dev"
mount -t proc proc "$R/proc"
mount -t sysfs sysfs "$R/sys"
mount -t tmpfs tmpfs "$R/tmp"
mkdir -p "$R/var/cache/pacman/pkg"
mount --bind "$WORK/pkg-cache" "$R/var/cache/pacman/pkg"
rm -f "$R/etc/resolv.conf"; cp -L /etc/resolv.conf "$R/etc/resolv.conf"
ch() { chroot "$R" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/bin HOME=/root LANG=C.UTF-8 "$@"; }
P="pacman --disable-sandbox --noconfirm --disable-download-timeout"
# gta2: reuse the build container's mirror list (several mirrors, ParallelDownloads)
cp /etc/pacman.d/mirrorlist "$R/etc/pacman.d/mirrorlist"
grep -q '^ParallelDownloads' "$R/etc/pacman.conf" || sed -i '/^\[options\]/a ParallelDownloads = 10' "$R/etc/pacman.conf"
rm -f "$R/var/lib/pacman/db.lck"

step "the tablet's packages ($DEVICE/packages.txt)"
PKGS=$(sed 's/#.*//' "$DEVICE/packages.txt" | xargs)
ch sh -c 'pacman-key --init >/dev/null 2>&1; pacman-key --populate archlinuxarm >/dev/null 2>&1' || true
if ! ch $P -Syu --needed $PKGS; then
	say "one transaction failed: one package at a time"
	for p in $PKGS; do
		ch $P -S --needed "$p" || {
			[ "$p" = linux-firmware-atheros ] && ch $P -S --needed linux-firmware || say "skipped $p"
		}
	done
fi

step "ztMETRO with ZTMETRO_ROTATE (panel mounted 180 degrees)"
if grep -aq ZTMETRO_ROTATE "$R/usr/local/bin/ztmetro"; then
	say "the GSI's ztmetro already has it"
else
	SRC=
	for d in /usr/src/ztmetro /usr/src/ztos/ztmetro; do [ -f "$R$d/ztmetro.c" ] && SRC=$d && break; done
	if [ -z "$SRC" ] && [ -n "$ZTOS_SRC" ]; then
		rm -rf "$R/usr/src/ztmetro"; cp -a "$ZTOS_SRC/ztmetro" "$R/usr/src/ztmetro"; SRC=/usr/src/ztmetro
	fi
	[ -n "$SRC" ] || die "the GSI has no ztmetro source and no --ztos-src: cannot add the rotation"
	grep -q ZTMETRO_ROTATE "$R$SRC/ztmetro.c" || patch -p2 -d "$R$SRC" < "$PATCH"
	# only the compositor: `make install` would also put back ztmetro/ztmetro-session,
	# which does not read /etc/ztos/session.env (os/overlay's does)
	ch sh -c "cd $SRC && make ztmetro && install -Dm755 ztmetro /usr/local/bin/ztmetro && rm -f ztmetro"
fi

step "the device layer"
DEVSRC=$DEVICE DEVROOT=$DEVICE
export GTA2_MODULES=$MODULES GTA2_FIRMWARE=$FIRMWARE
DEVICE_UNITS=
. "$DEVICE/layer.sh"

step "the user ($USERNAME)"
# the GSI has none (ztos-build installer/README.md); same steps as the installer's build.py
if [ "$USERNAME" != alarm ] && ch id alarm > /dev/null 2>&1; then
	ch userdel -r alarm > /dev/null 2>&1 || ch userdel alarm
fi
ch id "$USERNAME" > /dev/null 2>&1 || ch useradd -m -u 1000 -G wheel,video,audio,input -s /bin/bash "$USERNAME"
for g in render seat; do ch getent group $g > /dev/null && ch gpasswd -a "$USERNAME" $g > /dev/null || true; done
printf '%s:%s\n' "$USERNAME" "$PASSWORD" | ch chpasswd
ch passwd -l root > /dev/null
install -Dm440 /dev/stdin "$R/etc/sudoers.d/10-wheel" <<'SUDO'
%wheel ALL=(ALL:ALL) ALL
SUDO
if [ -f "$R/etc/sudoers.d/99-ztos-alarm" ] && [ "$USERNAME" != alarm ]; then
	sed -i "s/^alarm /$USERNAME /" "$R/etc/sudoers.d/99-ztos-alarm"
fi
UHOME=$(ch getent passwd "$USERNAME" | cut -d: -f6)
install -Dm644 /dev/stdin "$R/etc/ztos/user.conf" <<USERCONF
ZTOS_USER=$USERNAME
ZTOS_UID=$(ch id -u "$USERNAME")
ZTOS_GID=$(ch id -g "$USERNAME")
ZTOS_HOME=$UHOME
USERCONF
ch /usr/local/sbin/ztos-user-dropins > /dev/null
if [ -n "$SSHKEY" ] && [ -f "$SSHKEY" ]; then
	install -d -m 700 "$R$UHOME/.ssh"
	install -m 600 "$SSHKEY" "$R$UHOME/.ssh/authorized_keys"
	ch chown -R "$USERNAME:" "$UHOME/.ssh"
fi

step "name, time, services"
echo "$HOSTNAME_" > "$R/etc/hostname"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$R/etc/localtime"
: > "$R/etc/machine-id"
for u in greetd NetworkManager systemd-resolved sshd ztos-iald $DEVICE_UNITS; do
	ch systemctl enable "$u" > /dev/null 2>&1 || say "(no unit $u)"
done
# the root is never grown or re-keyed by zboot-firstboot here: the image is a file
rm -f "$R/etc/zboot-firstboot"

step "checks"
ch /usr/bin/ztos-ial check || say "WARNING: ztos-ial check failed (see above)"
for d in panfrost exynos kmsro; do
	if ls "$R"/usr/lib/dri/${d}_dri.so > /dev/null 2>&1; then say "mesa: ${d}_dri.so present"
	else say "mesa: no ${d}_dri.so (exynos+panfrost are what kmsro needs here)"; fi
done
ls "$R/usr/lib/modules" 2>/dev/null | sed 's/^/modules: /' || true
if [ -n "$KCONFIG" ] && [ -f "$KCONFIG" ]; then
	say "kernel contract against $KCONFIG:"
	for o in CGROUPS MEMCG CPUSETS NAMESPACES PSI DRM_PANFROST DRM_EXYNOS ZRAM ANDROID_BINDER_IPC \
			ANDROID_BINDERFS MEMFD_CREATE VETH BRIDGE NF_TABLES INPUT_FF_MEMLESS USB_CONFIGFS_NCM BLK_DEV_LOOP; do
		v=$(grep -E "^CONFIG_$o=" "$KCONFIG" | cut -d= -f2 || true)
		printf '  %-22s %s\n' "$o" "${v:-MISSING}"
	done
fi

step "tidying up"
rm -f "$R/etc/resolv.conf"; ln -sf /run/systemd/resolve/stub-resolv.conf "$R/etc/resolv.conf"
rm -rf "$R/tmp/"* "$R/var/log/pacman.log"
date -u "+gtactive2lte %Y-%m-%dT%H:%MZ" >> "$R/etc/ztos/built"
cleanup
trap - EXIT

# ---- 3. the image ----------------------------------------------------------------
step "writing $OUT"
used_mb=$(du -sxm "$R" | cut -f1)
want_mb=$(( used_mb * 115 / 100 + 300 ))
case $SIZE in
	*G) size_mb=$(( ${SIZE%G} * 1024 )) ;;
	*M) size_mb=${SIZE%M} ;;
	*) size_mb=$SIZE ;;
esac
if [ "$size_mb" -lt "$want_mb" ]; then
	say "the root needs ${used_mb} MB: the image grows from ${size_mb} to ${want_mb} MB"
	size_mb=$want_mb
fi
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
mke2fs -q -t ext4 -L ztos-root -m 1 -O ^orphan_file -d "$R" "$OUT" "${size_mb}M"
e2fsck -fn "$OUT" | tail -n 2
sha256sum "$OUT" > "$OUT.sha256"
say "ready: $OUT (${size_mb} MB, root ${used_mb} MB); put it at /data/gta2srv/zt/rootfs.img"
