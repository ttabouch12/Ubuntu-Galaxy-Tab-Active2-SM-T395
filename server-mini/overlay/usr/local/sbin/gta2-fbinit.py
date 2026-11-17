#!/usr/bin/python3
# gta2: no hwcomposer here. Set fb0 to XRGB8888 (bitfields are empty at boot, Xorg needs them),
# unblank, and FBIOPAN_DISPLAY once so decon scans out the fb0 window.
import os, fcntl, struct, sys
fd = os.open('/dev/fb0', os.O_RDWR)
v = bytearray(fcntl.ioctl(fd, 0x4600, bytes(160)))  # FBIOGET_VSCREENINFO
if '--put' in sys.argv or struct.unpack_from('I', v, 32)[0] == 0:   # red.offset/len empty
    struct.pack_into('9I', v, 32, 16, 8, 0, 8, 8, 0, 0, 8, 0)        # red, green, blue
    struct.pack_into('3I', v, 68, 24, 8, 0)                           # transp
    v = bytearray(fcntl.ioctl(fd, 0x4601, bytes(v)))                  # FBIOPUT_VSCREENINFO
try: fcntl.ioctl(fd, 0x4611, 0)   # FBIOBLANK unblank
except OSError: pass
fcntl.ioctl(fd, 0x4606, bytes(v))  # FBIOPAN_DISPLAY
print('fb0 bitfields', struct.unpack_from('12I', v, 32))
