#!/usr/bin/python3
# gta2: map Samsung capacitive keys for Lomiri. BACK(158) -> Esc, RECENT(254) -> Super+W (app spread). HOME stays native.
import os, struct, fcntl, glob, time
EV_SYN, EV_KEY = 0, 1
KEY_ESC, KEY_W, KEY_LEFTMETA = 1, 17, 125
def find():
    for d in glob.glob('/sys/class/input/event*'):
        try:
            if open(d + '/device/name').read().strip() == 'gpio_keys':
                return '/dev/input/' + os.path.basename(d)
        except OSError: pass
src = None
while not src:
    src = find(); time.sleep(0 if src else 2)
u = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(u, 0x40045564, EV_KEY)
for k in (KEY_ESC, KEY_W, KEY_LEFTMETA): fcntl.ioctl(u, 0x40045565, k)
os.write(u, struct.pack('80sHHHHi', b'gta2-keys', 0x06, 0x1, 0x1, 1, 0) + b'\0' * (4 * 64 * 4))
fcntl.ioctl(u, 0x5501)
def emit(seq):
    for c, v in seq:
        os.write(u, struct.pack('qqHHi', 0, 0, EV_KEY, c, v)); os.write(u, struct.pack('qqHHi', 0, 0, EV_SYN, 0, 0))
f = open(src, 'rb', buffering=0)
while True:
    ev = f.read(24)
    if len(ev) < 24: continue
    _, _, t, c, v = struct.unpack('qqHHi', ev)
    if t != EV_KEY or v != 1: continue
    if c == 158: emit([(KEY_ESC, 1), (KEY_ESC, 0)])
    elif c == 254: emit([(KEY_LEFTMETA, 1), (KEY_W, 1), (KEY_W, 0), (KEY_LEFTMETA, 0)])
