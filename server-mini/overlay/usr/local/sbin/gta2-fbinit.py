#!/usr/bin/python3
# gta2: drive the Exynos DECON fb0 without Android's hwcomposer.
#   (no arg)  boot: set XRGB bitfields (RGBX byte order on this panel) + pan once -> decon scans out fb0
#   --wake    after X starts or screen-on: unblank, set mode, pan (X blanks/unblanks fb0 at start,
#             after which decon only scans out again after a fresh FBIOPUT + FBIOPAN)
#   --sleep   screen off (FB_BLANK_POWERDOWN: panel + decon off)
import os, fcntl, struct, sys, time
# mainline (6.x): simpledrm needs nothing (it is already XRGB; the 3.18 DECON bitfields would swap red/blue).
# exynosdrm (DECON + DSI + s6d7aa0): --sleep powers the panel down; boot/--wake power-cycle it, because the
# first modeset after the bootloader's splash leaves a doubled, colour-fringed image until the panel is reset.
if int(os.uname().release.split('.')[0]) >= 6:
    try: name = open('/sys/class/graphics/fb0/name').read()
    except OSError: name = ''
    if 'exynos' not in name: sys.exit(0)
    fd = os.open('/dev/fb0', os.O_RDWR)
    def blank(m):
        try: fcntl.ioctl(fd, 0x4611, m)                           # FBIOBLANK
        except OSError: pass
    if '--sleep' in sys.argv: blank(4); sys.exit(0)               # FB_BLANK_POWERDOWN: panel off
    blank(4); time.sleep(0.3); blank(0); sys.exit(0)              # power-cycle, then on
fd = os.open('/dev/fb0', os.O_RDWR)
def io(req, arg):
    try: return fcntl.ioctl(fd, req, arg)
    except OSError: return None
if '--sleep' in sys.argv:
    io(0x4611, 4); sys.exit(0)
if '--wake' in sys.argv:
    io(0x4611, 0); time.sleep(0.3)
v = bytearray(fcntl.ioctl(fd, 0x4600, bytes(160)))                 # FBIOGET_VSCREENINFO
struct.pack_into('6I', v, 0, 800, 1280, 800, 1280, 0, 0); struct.pack_into('I', v, 24, 32)  # 800x1280x32
struct.pack_into('9I', v, 32, 0, 8, 0, 8, 8, 0, 16, 8, 0)          # red@0 green@8 blue@16
struct.pack_into('3I', v, 68, 24, 8, 0)                             # transp@24
struct.pack_into('I', v, 80, 0x80)                                  # activate = FB_ACTIVATE_FORCE
r = io(0x4601, bytes(v))                                            # FBIOPUT_VSCREENINFO
if r: v = bytearray(r)
io(0x4611, 0)
io(0x4606, bytes(v))                                                # FBIOPAN_DISPLAY
