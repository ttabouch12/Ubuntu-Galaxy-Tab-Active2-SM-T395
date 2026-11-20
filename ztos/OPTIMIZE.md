# ztOS on the Galaxy Tab Active2: performance plan

Target: Exynos 7870 (8x Cortex-A53, 1.79 GHz OC max), 3 GB RAM, Mali-T830 (panfrost, untested),
800x1280 DSI panel, eMMC, our 6.18 mainline kernel. Written 2026-11-20 from `out/.config`
(the r4 build), `notes/gta2-full.config`, `ztos-device-samsung-gtactive2lte/` and `ztos_research.md`.

Each item is marked **[build: kernel]**, **[build: layer.sh]** or **[runtime]**. The runtime items
can be tried with `sysctl -w`/`echo` before they are baked into the layer.

Hard limits that this plan never crosses:
- CPU stays at most **1794 MHz**. 1.9–2.0 GHz hung the tablet in tests: never add those OPPs.
- GPU stays at the S-Boot clock until panfrost DVFS has ECT voltages (1001 MHz max, 0.900 V).
- Keep the debug safety net (lockup panics, pstore, trialguard) until ztOS has booted cleanly
  several times. The debug items in section 1.4 are for the "stable" build only.

---

## 1. Kernel config deltas (`notes/gta2-full.config`, then `olddefconfig`) [build: kernel]

Merge these on top of the current config and `kernel/ztos.config`.

### 1.1 Required by ztOS (contract)
```
CONFIG_PSI=y
# CONFIG_PSI_DEFAULT_DISABLED is not set
CONFIG_ANDROID_BINDER_IPC=y          # Waydroid only; leave out if Waydroid stays off
CONFIG_ANDROID_BINDERFS=y
CONFIG_ANDROID_BINDER_DEVICES=""
```
PSI is missing from the r3/r4 config today (`PSI=` empty). Without it the ztOS memory policy
and systemd-oomd have nothing to read, and the IAL contract check fails.

### 1.2 Memory: zram + MGLRU (highest impact on 3 GB)
```
CONFIG_LRU_GEN=y
CONFIG_LRU_GEN_ENABLED=y
CONFIG_ZRAM=y
CONFIG_ZRAM_BACKEND_LZ4=y
CONFIG_ZRAM_BACKEND_ZSTD=y
CONFIG_ZRAM_DEF_COMP_LZ4=y           # fast on A53; zstd as a recompression option
CONFIG_ZRAM_MULTI_COMP=y
CONFIG_ZRAM_WRITEBACK=n
CONFIG_CRYPTO_LZ4=y
CONFIG_CRYPTO_ZSTD=y
# CONFIG_ZSWAP is not set             # zram only; do not stack zswap on zram
# CONFIG_TRANSPARENT_HUGEPAGE is not set
# CONFIG_KSM is not set               # nothing on a tablet uses MADV_MERGEABLE; saves a thread
# CONFIG_NUMA is not set              # single node SoC; NUMA=y in r4 only adds overhead
# CONFIG_MEMORY_HOTPLUG is not set
CONFIG_CMA_SIZE_MBYTES=64             # DECON scanout buffers when DRM runs without the sysmmu (safe5)
```
- Today the zram backend is LZO only (`ZRAM_BACKEND_FORCE_LZO=y`), and MGLRU is off.
- MGLRU cuts page-reclaim CPU time and avoids thrashing under memory pressure. This matters
  a lot with Qt/WebKit apps on 3 GB.
- THP: on 4K pages with 3 GB RAM it causes compaction stalls and wastes memory. Turn it off.

### 1.3 CPU / scheduler / MMU
```
CONFIG_PREEMPT_DYNAMIC=y              # keep full PREEMPT for UI latency; allows preempt=voluntary to test
CONFIG_PREEMPT=y
CONFIG_HZ_300=y                       # 250 today; 300 suits 60 Hz frame pacing better at negligible cost
CONFIG_NO_HZ_IDLE=y
CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y
CONFIG_ENERGY_MODEL=y
CONFIG_SCHED_MC=y
CONFIG_SCHED_CLUSTER=y
CONFIG_UCLAMP_TASK=y                  # lets systemd/ztOS boost the compositor (CPUQuotaPeriod/uclamp)
CONFIG_UCLAMP_TASK_GROUP=y
CONFIG_ARM64_VA_BITS_39=y             # 52 today; the A53 has no LVA, 39-bit = 3-level page tables = cheaper TLB misses
CONFIG_RCU_LAZY=y                     # fewer RCU wakeups on idle
```
- `ARM64_VA_BITS_39` is safe: it gives 512 GB of virtual space against 3 GB of RAM. It removes
  one page-table level from every TLB miss on the A53 (4-level to 3-level).
- Keep `PREEMPT` (full). ztMETRO draws the whole shell on the CPU side until panfrost works,
  so latency matters more than throughput here.

### 1.4 Debug options to drop in the "stable" build only
Leave these on until ztOS has booted cleanly 3 times:
```
# CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC is not set
# CONFIG_BOOTPARAM_HARDLOCKUP_PANIC is not set
# CONFIG_BOOTPARAM_HUNG_TASK_PANIC is not set
# CONFIG_PANIC_ON_OOPS is not set     # an oops in a GPU/Wi-Fi module should not reboot the UI
# CONFIG_DEBUG_INFO is not set        # smaller modules.tgz and Image, faster builds
CONFIG_DEBUG_INFO_NONE=y
# CONFIG_HARDLOCKUP_DETECTOR is not set
```
Keep `PSTORE_RAM` and `S3C2410_WATCHDOG`. They cost almost nothing and catch hangs.

---

## 2. Memory and VM tuning for 3 GB RAM

### 2.1 zram swap [build: layer.sh] (systemd zram-generator, which is in the Arch repos)
`/etc/systemd/zram-generator.conf`:
```
[zram0]
zram-size = min(ram, 3072)
compression-algorithm = lz4 (type=huge_idle) zstd
swap-priority = 100
fs-type = swap
```
Add `zram-generator` to `packages.txt`. Use no disk swap file: eMMC swap is slow and wears the flash.

### 2.2 sysctl [build: layer.sh] as `/etc/sysctl.d/90-gta2.conf` (try at runtime first)
```
vm.swappiness = 150              # zram is far cheaper than dropping file cache on eMMC
vm.page-cluster = 0              # zram: read one page at a time, no readahead
vm.watermark_scale_factor = 125  # start kswapd earlier, fewer direct-reclaim stalls
vm.watermark_boost_factor = 0    # boosting causes reclaim bursts after fragmentation events
vm.vfs_cache_pressure = 80
vm.dirty_background_ratio = 3
vm.dirty_ratio = 10              # small writeback bursts on eMMC, no multi-second UI freezes
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 1500
vm.compaction_proactiveness = 0
vm.min_free_kbytes = 16384
kernel.sched_autogroup_enabled = 0   # the compositor should not share a group with terminals
```

### 2.3 OOM handling [build: layer.sh]
- Use **systemd-oomd** (it uses PSI, and ztOS already ships systemd). Do not add earlyoom as well.
  Enable `systemd-oomd.service`.
- `/etc/systemd/oomd.conf.d/gta2.conf`:
  ```
  [OOM]
  SwapUsedLimit=90%
  DefaultMemoryPressureLimit=60%
  DefaultMemoryPressureDurationSec=20s
  ```
- Protect the compositor with a drop-in for ztMETRO's unit (or the session scope):
  `ManagedOOMPreference=avoid`, `MemoryLow=200M`, `OOMScoreAdjust=-900`.
- Mark app scopes `ManagedOOMMemoryPressure=kill`.

### 2.4 Android runtime (Waydroid) [build: layer.sh]
- It is off today: layer.sh masks `waydroid-container` and `ztos-waydroid-images`, and the
  manifest sets `binder = "none"`. Keep it off on 3 GB unless it is really needed.
- If it is turned on: lower `[android] memory_budget_mb` from 1024 to **768**. Start the
  container only on demand, never at boot. Run it with `MemoryHigh=700M MemoryMax=900M` and
  `ManagedOOMPreference=omit` on `waydroid-container.service`.

---

## 3. eMMC I/O

| Setting | Value | Where |
|---|---|---|
| Scheduler for mmcblk0 | `none` (or `mq-deadline`) | [build: layer.sh] udev rule |
| read_ahead_kb | 128 | same udev rule |
| zram scheduler | `none` | same |
| fstrim | weekly `fstrim.timer` on `/userdata` | [build: layer.sh] `systemctl enable fstrim.timer` |
| journald | volatile, 32 MB | [build: layer.sh] |

The udev rule, `/etc/udev/rules.d/60-gta2-io.rules`:
```
ACTION=="add|change", KERNEL=="mmcblk[0-9]", ATTR{queue/scheduler}="none", ATTR{queue/read_ahead_kb}="128"
ACTION=="add|change", KERNEL=="zram[0-9]", ATTR{queue/scheduler}="none"
```

**Mount options.** `/` is a loop-mounted ext4 image on the USERDATA ext4. The gta2srv
initramfs mounts both.
- [build: kernel, in initramfs-init] mount USERDATA with `noatime,commit=30` and the loop root
  with `noatime,commit=30`. Today the root has `noatime` only.
- [build: layer.sh] loop device: write `/sys/block/loop0/queue/scheduler=none` and set
  direct I/O if the losetup supports it (`losetup --direct-io=on`). This cuts the
  double-caching of the image file, which on 3 GB is otherwise a big waste of page cache.
  It needs `busybox losetup` with `-D` support or util-linux.

journald, `/etc/systemd/journald.conf.d/gta2.conf`:
```
[Journal]
Storage=volatile
RuntimeMaxUse=32M
```

---

## 4. CPU [runtime, then build: layer.sh]
- Governor: `schedutil` (already the default).
  `/sys/devices/system/cpu/cpufreq/policy{0,4}/schedutil/rate_limit_us = 2000` (the default is
  usually 10000, which ramps too slowly for touch).
- Ceiling: `scaling_max_freq = 1794000` on both policies, matching manifest Perf1 caps.
  Never higher.
- Floor while the screen is on: `scaling_min_freq = 902000` on policy0, so touch response
  does not start from 343 MHz. Go back to the minimum when the screen is off.
- Keep all 8 cores online (manifest `hotplug = false`). `zrnperfd` stays masked: it is tuned
  for the S9.
- `gta2-thermal` owns throttling. It must lower `scaling_max_freq`, never offline cores.
- Put this in `gta2-thermal` or a small `gta2-perf.service` [build: layer.sh] instead of
  zrnperfd.

---

## 5. GPU and compositor

### 5.1 With panfrost working (target)
[build: layer.sh] `/etc/ztos/session.env` additions:
```
export PAN_MESA_DEBUG=            # keep empty; never "sync" outside debugging
export MESA_SHADER_CACHE_DIR=/var/cache/mesa   # persistent cache: skips shader recompiles on every boot
export MESA_SHADER_CACHE_MAX_SIZE=128M
export QSG_RENDER_LOOP=basic      # threaded render loop thrashes the 8 small cores with T830 sync
export QT_QUICK_BACKEND=          # leave default (rhi/gles) when panfrost works
export ZTMETRO_SCALE=1.5          # 1.75 today; fewer pixels per glyph/tile = less GPU fill
```
- Bake the shader cache in: run ztMETRO once on the tablet, then keep `/var/cache/mesa`
  (it lives on the rootfs, so it persists).
- The Mali-T830 has very little fill rate. Avoid full-screen blur and translucency in ztMETRO
  if it has a setting for them (`ZTMETRO_*`; check `ztmetro --help` and its README).
- `ZTMETRO_NO_PLANE=1` is already set. Keep it.

### 5.2 Fallback until panfrost works (llvmpipe)
[runtime] uncomment in `session.env`:
```
export WLR_RENDERER_ALLOW_SOFTWARE=1
export LIBGL_ALWAYS_SOFTWARE=1
export LP_NUM_THREADS=4           # llvmpipe on 4 cores, leave 4 for apps; 8 threads stalls input
export WLR_NO_HARDWARE_CURSORS=1
export QSG_RENDER_LOOP=basic
export QT_QUICK_BACKEND=software  # Qt apps skip GL entirely on llvmpipe: much faster
export ZTMETRO_SCALE=1.25         # least pixels while on CPU rendering
```
llvmpipe will not pass ztOS's promote check ("boots" status). It is for bring-up only.

### 5.3 GPU DVFS (later) [build: kernel]
Apply `handoff/kernel/gpu` (G3D PLL table + OPPs + mali-supply BUCK2). Then set
`manifest.toml [ial.Perf1] gpu_devfreq = "/sys/class/devfreq/11400000.gpu"` with the
`simple_ondemand` governor, max 1001 MHz (0.900 V). Do not use the 1146–1300 MHz entries
until thermal is proven.

---

## 6. systemd trimming [build: layer.sh]

Mask (`ln -sf /dev/null /etc/systemd/system/<unit>`) whatever the GSI ships that this tablet
cannot use. Check each name with `systemctl list-unit-files` on the first boot and mask only
the ones that exist:
```
ModemManager.service           # Shannon modem: no mainline driver
cups.service cups.socket       # if present
avahi-daemon.service avahi-daemon.socket   # pulled in by the GSI (avahi in the upgrade list)
systemd-networkd-wait-online.service NetworkManager-wait-online.service   # boot time
lvm2-monitor.service dmraid* mdmonitor*    # if present
geoclue.service                # no GPS
iio-sensor-proxy.service       # no IIO sensors in the DT yet
man-db.timer shadow.timer archlinux-keyring-wkd-sync.timer   # background I/O on eMMC
pacman-filesdb-refresh.timer   # if present
```
Also:
- `zrnperfd`, `waydroid-container` and `ztos-waydroid-images` are already masked by `layer.sh`.
- Do not mask `bluetooth`, `NetworkManager`, `systemd-oomd`, `systemd-timesyncd`, `zboot-usb-gadget`,
  `gta2-*` or anything `ztos-*` other than the Waydroid images.
- Boot check: `systemd-analyze blame` and `systemd-analyze critical-chain` after the first
  good boot. Mask the top offenders that are not needed.

---

## 7. Measuring (before and after each change) [runtime]
```
systemd-analyze; systemd-analyze blame | head -20
free -m; cat /proc/pressure/memory /proc/pressure/cpu /proc/pressure/io
zramctl
cat /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq
eglinfo -B | grep -i renderer        # must say Mali-T830 (Panfrost), not llvmpipe
glmark2-es2-drm --off-screen          # after panfrost; compare scores per change
```
Change one group at a time. Keep the trial boot mechanism in place for kernel changes.

---

## 8. Order to apply
1. Kernel r5: section 1.1 + 1.2 + 1.3 (PSI, MGLRU, zram LZ4/zstd, THP off, NUMA off, VA 39-bit, HZ 300, uclamp).
   Boot it as a trial under Ubuntu first: it is the same kernel for both systems.
2. layer.sh: zram-generator, sysctl, oomd, udev I/O rule, journald volatile, fstrim, masks.
3. session.env: llvmpipe fallback values until panfrost works, then the 5.1 values.
4. After 3 clean boots: kernel "stable" variant with section 1.4.
5. GPU DVFS last.
