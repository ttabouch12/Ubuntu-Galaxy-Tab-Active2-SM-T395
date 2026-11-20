# The Galaxy Tab Active2 LTE (gtactive2lte) device layer, in the shape of
# ztos-device-samsung-starlte/layer.sh: sourced after the GSI part with
#   $R       the root being built          $DEVSRC  this folder (vendor/, overlay/, packages.txt)
#   $DEVROOT this repository (firmware/, kernel/, ztmetro/)
#   $P       pacman command line            step, ch  (show a step, run in the root)
# by ztOS's installer (ZTOS_DEVICE=<this repo>) or by ../build-rootfs.sh.
# Optional inputs (environment):
#   GTA2_MODULES   modules tarball of OUR kernel (lib/modules/<kver>/...), e.g. modules.tgz
#   GTA2_FIRMWARE  folder whose contents go to /usr/lib/firmware (Wi-Fi board data etc.)
D=$DEVSRC

step "adding the Galaxy Tab Active2 device layer"

# ztOSIAL: the manifest and this tablet's backends
install -d "$R/vendor/ztos"
cp -a "$D/vendor/ztos/." "$R/vendor/ztos/"
chown -R 0:0 "$R/vendor"

cp -a "$D/overlay/." "$R/"
chown -R 0:0 "$R/etc/systemd/system" "$R/etc/udev/rules.d" "$R/etc/ztos" "$R/usr/local/sbin" \
	"$R/etc/modules-load.d" "$R/etc/NetworkManager/conf.d"
chmod 755 "$R"/usr/local/sbin/gta2-* 2>/dev/null || true

# The root is a loop-mounted image file that our initramfs mounts rw before
# switch_root, and /data is moved to /userdata. Nothing for systemd to fsck or
# remount: no root line in fstab (an ALARM LABEL= line would wait forever).
cat > "$R/etc/fstab" <<'FSTAB'
# gtactive2lte: / is /data/gta2srv/zt/rootfs.img, loop-mounted rw by the gta2srv
# initramfs; /data (USERDATA, mmcblk0p24) is moved to /userdata before switch_root.
FSTAB

# The kernel is ours (U-Boot sysboot, extlinux.conf), never a package
sed -i 's/^#\?IgnorePkg *=.*/IgnorePkg   = linux-aarch64 linux-aarch64-headers/' "$R/etc/pacman.conf"

# our kernel's modules
if [ -n "${GTA2_MODULES:-}" ] && [ -f "$GTA2_MODULES" ]; then
	step "adding the kernel modules ($(basename "$GTA2_MODULES"))"
	M=$(mktemp -d)
	tar -xf "$GTA2_MODULES" -C "$M"
	# lib/ is a symlink to usr/lib in Arch: never let tar replace it
	for k in "$M"/lib/modules/* "$M"/usr/lib/modules/*; do
		[ -d "$k" ] || continue
		kver=$(basename "$k")
		rm -rf "$R/usr/lib/modules/$kver"
		install -d "$R/usr/lib/modules"
		cp -a "$k" "$R/usr/lib/modules/$kver"
		rm -f "$R/usr/lib/modules/$kver/build" "$R/usr/lib/modules/$kver/source"
		chown -R 0:0 "$R/usr/lib/modules/$kver"
		ch depmod -a "$kver" > /dev/null 2>&1 || echo "(depmod $kver failed)"
		echo "modules: $kver"
	done
	rm -rf "$M"
else
	echo "WARNING: no GTA2_MODULES: the image has no kernel modules (exynosdrm, panfrost, ath10k_sdio are =m)" >&2
fi

# firmware the packages do not carry (Samsung-calibrated board data): firmware/README.md
if [ -n "${GTA2_FIRMWARE:-}" ] && [ -d "$GTA2_FIRMWARE" ]; then
	step "adding firmware from $GTA2_FIRMWARE"
	install -d "$R/usr/lib/firmware"
	cp -a "$GTA2_FIRMWARE/." "$R/usr/lib/firmware/"
	chown -R 0:0 "$R/usr/lib/firmware"
fi

# no system suspend on this kernel yet (Sleep1 says so too: vendor/ztos/ial/gtactive2lte.py)
for t in sleep suspend hibernate hybrid-sleep suspend-then-hibernate; do
	ln -sf /dev/null "$R/etc/systemd/system/$t.target"
done

# Off on this tablet:
#  - zrnperfd: tuned for the S9 (hotplug, Mongoose steps); gta2-thermal owns cpufreq here
#  - waydroid-container, ztos-waydroid-images: no binder in our kernel; the images
#    unit would download ~1 GB of Android at first boot for nothing
# (zrnperfd.service lives in /etc/systemd/system itself (ztmetro/Makefile): it is
# kept aside, not lost, so `mv` it back to turn zrnperfd on again.)
# + S9-only units the GSI enables: Shannon modem boot (no driver), SSP sensor hub (no driver).
#   ztOSCoreSensorFramework's own list is overlay/etc/ztoscoresensorframework/components.
for u in zrnperfd waydroid-container ztos-waydroid-images ztoscorenetworking-modem ztoscsf-sensord ztoscsf-sensorhub; do
	f=$R/etc/systemd/system/$u.service
	if [ -f "$f" ] && [ ! -L "$f" ]; then
		install -d "$R/usr/local/share/ztos/gta2-off"
		mv "$f" "$R/usr/local/share/ztos/gta2-off/"
	fi
	rm -f "$R"/etc/systemd/system/*.wants/$u.service
	ln -sf /dev/null "$f"
done

# the units the installer (or build-rootfs.sh) enables after this layer
# r5 perf (handoff/ztos/OPTIMIZE.md): new overlay dirs owned by root, perf script executable
chown -R 0:0 "$R/etc/ztoscoresensorframework" "$R/etc/sysctl.d" "$R/etc/systemd/oomd.conf.d" "$R/etc/systemd/journald.conf.d" "$R/etc/systemd/zram-generator.conf" 2>/dev/null || true
chmod 755 "$R/usr/local/sbin/gta2-perf"
install -d -m 755 "$R/var/cache/mesa"
# mask what this tablet cannot use (only units the GSI actually has), OPTIMIZE.md 6
for u in ModemManager.service cups.service cups.socket avahi-daemon.service avahi-daemon.socket \
	systemd-networkd-wait-online.service NetworkManager-wait-online.service lvm2-monitor.service \
	geoclue.service iio-sensor-proxy.service man-db.timer shadow.timer archlinux-keyring-wkd-sync.timer \
	pacman-filesdb-refresh.timer; do
	if [ -e "$R/usr/lib/systemd/system/$u" ] || [ -e "$R/etc/systemd/system/$u" ]; then
		rm -f "$R"/etc/systemd/system/*.wants/$u
		ln -sf /dev/null "$R/etc/systemd/system/$u"; echo "masked $u"
	fi
done

DEVICE_UNITS="zboot-usb-gadget gta2-bootok gta2-thermal bluetooth gta2-bt-addr gta2-perf systemd-oomd fstrim.timer"
