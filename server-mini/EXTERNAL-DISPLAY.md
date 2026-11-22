# External display (HDMI) on the Galaxy Tab Active2

**USB-C docks with HDMI do not work, and cannot be made to work.** The HyperDrive HD4003GL (and most USB-C
docks) drive HDMI through *DisplayPort Alt Mode*: the dock shows up as a VIA Labs VL822 hub plus a USB
Billboard device advertising SVID `0xff01` (VESA DisplayPort), state "unspecified" (never configured).
Alt Mode needs the phone/tablet SoC to output DisplayPort on the USB-C pins. The Exynos 7870 has one display
controller (DECON at 0x14830000) feeding one MIPI DSI (0x14800000) for the built-in panel. Samsung's own
kernel (`decon_7870`) has no DisplayPort, HDMI or MHL block, and the Type-C port only carries USB 2.0.

**What works: a USB graphics adapter** (USB-A or USB-C, plugged into the dock or the tablet). The drivers are
built for the 6.18 kernel and load automatically on plug-in; `gta2-extdisplay` (udev rule
`81-gta2-extdisplay.rules`) attaches it to X and mirrors the tablet (desktop mode can extend instead).

| Adapter chip | Driver | Notes |
|---|---|---|
| MacroSilicon MS9132 / MS9120 (USB → HDMI, ~10-20 $) | `ms912x` ([rhgndf/ms912x](https://github.com/rhgndf/ms912x), open source; one-line API fix for 6.18) | best value; over USB 2.0 expect 1080p at low frame rate, 720p smoother |
| DisplayLink DL-1x5 (old USB 2.0) | `udl` (in kernel) | up to ~1280x1024 |
| DisplayLink DL-3xxx/5xxx/6xxx | `evdi` ([DisplayLink/evdi](https://github.com/DisplayLink/evdi)) + DisplayLink's closed `DisplayLinkManager` (arm64 Ubuntu package from synaptics.com) | compressed, best quality over USB 2.0 |
| GUD gadgets (e.g. a Raspberry Pi Zero as display adapter) | `gud` (in kernel) | DIY |

Modules: `/lib/modules/6.18.0-gta2srv-r7+/extra/usbdisp/`. Over USB 2.0 (480 Mbit/s) a USB adapter is fine for a
desktop, browser and documents; full-screen video will drop frames. Wireless alternatives: Moonlight/VNC to a TV box.
