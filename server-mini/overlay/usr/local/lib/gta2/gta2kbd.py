#!/usr/bin/python3
# gta2-kbd helper: injects key presses into the focused X window with XTest (ctypes, no xdotool per key)
# and tells the QML keyboard when to show / hide (long-poll), so showing the keyboard never starts a process.
#   http://127.0.0.1:8097/key?c=<char>  /key?k=<BackSpace|Return|Left|Right|Up|Down|Tab|Escape|Delete|Home|End>
#   /show /hide /toggle   /wait?v=<n> (blocks until the state changes; QML side)   /state
import ctypes, ctypes.util, os, sys, threading, time, subprocess, signal
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, unquote

PORT = 8097
X = ctypes.cdll.LoadLibrary(ctypes.util.find_library('X11') or 'libX11.so.6')
XT = ctypes.cdll.LoadLibrary(ctypes.util.find_library('Xtst') or 'libXtst.so.6')
X.XOpenDisplay.restype = ctypes.c_void_p
X.XOpenDisplay.argtypes = [ctypes.c_char_p]
X.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
X.XKeysymToKeycode.restype = ctypes.c_ubyte
X.XkbKeycodeToKeysym.argtypes = [ctypes.c_void_p, ctypes.c_ubyte, ctypes.c_int, ctypes.c_int]
X.XkbKeycodeToKeysym.restype = ctypes.c_ulong
X.XChangeKeyboardMapping.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_ulong), ctypes.c_int]
X.XFlush.argtypes = [ctypes.c_void_p]
X.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
XT.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]

dpy = X.XOpenDisplay(os.environ.get('DISPLAY', ':0').encode())
if not dpy:
    sys.exit('gta2-kbd: no X display')
LOCK = threading.Lock()
NAMED = {'BackSpace': 0xff08, 'Return': 0xff0d, 'Tab': 0xff09, 'Escape': 0xff1b, 'Delete': 0xffff,
         'Left': 0xff51, 'Up': 0xff52, 'Right': 0xff53, 'Down': 0xff54, 'Home': 0xff50, 'End': 0xff57}
SHIFT = X.XKeysymToKeycode(dpy, 0xffe1)
# two spare keycodes (no symbols) for characters that are not on the keymap (ç ğ ı ö ş ü é € ...)
SCRATCH = [kc for kc in range(255, 8, -1) if X.XkbKeycodeToKeysym(dpy, kc, 0, 0) == 0][:2]
_sc = [0]


def tap(kc, shift=False):
    if shift: XT.XTestFakeKeyEvent(dpy, SHIFT, 1, 0)
    XT.XTestFakeKeyEvent(dpy, kc, 1, 0)
    XT.XTestFakeKeyEvent(dpy, kc, 0, 0)
    if shift: XT.XTestFakeKeyEvent(dpy, SHIFT, 0, 0)
    X.XFlush(dpy)


def send_keysym(ks):
    with LOCK:
        kc = X.XKeysymToKeycode(dpy, ks)
        if kc:
            if X.XkbKeycodeToKeysym(dpy, kc, 0, 0) == ks: return tap(kc)
            if X.XkbKeycodeToKeysym(dpy, kc, 0, 1) == ks: return tap(kc, True)
        if not SCRATCH: return
        kc = SCRATCH[_sc[0] % len(SCRATCH)]; _sc[0] += 1   # alternate so a remap never races the previous press
        arr = (ctypes.c_ulong * 1)(ks)
        X.XChangeKeyboardMapping(dpy, kc, 1, arr, 1); X.XSync(dpy, 0)
        time.sleep(0.012)            # let the focused client see the MappingNotify
        tap(kc)


def char_keysym(c):
    o = ord(c)
    if c == '\n': return NAMED['Return']
    if 0x20 <= o <= 0x7e or 0xa0 <= o <= 0xff: return o
    return 0x01000000 | o            # Unicode keysym


state = {'shown': False, 'v': 0}
cond = threading.Condition()


def set_shown(s):
    with cond:
        if s is None: s = not state['shown']
        if s != state['shown']:
            state['shown'] = s; state['v'] += 1; cond.notify_all()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def reply(self, body, code=200):
        b = body.encode()
        self.send_response(code); self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        u = urlparse(self.path); q = parse_qs(u.query)
        if u.path == '/key':
            if 'k' in q and q['k'][0] in NAMED: send_keysym(NAMED[q['k'][0]])
            elif 'c' in q:
                for ch in q['c'][0][:8]: send_keysym(char_keysym(ch))
            return self.reply('ok')
        if u.path in ('/show', '/hide', '/toggle'):
            set_shown({'/show': True, '/hide': False, '/toggle': None}[u.path]); return self.reply('ok')
        if u.path == '/state':
            return self.reply('%d %s' % (state['v'], 'show' if state['shown'] else 'hide'))
        if u.path == '/wait':
            v = int((q.get('v') or ['-1'])[0])
            with cond:
                cond.wait_for(lambda: state['v'] != v, timeout=25)
                return self.reply('%d %s' % (state['v'], 'show' if state['shown'] else 'hide'))
        self.reply('?', 404)
    do_POST = do_GET


DEBUG = bool(os.environ.get('GTA2_KBD_DEBUG'))
FIFO = '/tmp/gta2-kbd.fifo'   # fast path: the QML keyboard writes "c <char>" / "k <name>" lines here (~1 ms)


def fifo_loop():
    try: os.unlink(FIFO)
    except FileNotFoundError: pass
    os.mkfifo(FIFO, 0o600)
    while True:
        with open(FIFO, 'r', encoding='utf-8', errors='ignore') as f:   # blocks until a writer opens it
            for line in f:
                kind, _, val = line.rstrip('\n').partition(' ')
                if DEBUG: open('/tmp/gta2-kbd-times', 'a').write('%.3f %s\n' % (time.time(), line.strip()))
                if kind == 'k' and val in NAMED: send_keysym(NAMED[val])
                elif kind == 'c':
                    for ch in unquote(val)[:8]: send_keysym(char_keysym(ch))


if __name__ == '__main__':
    threading.Thread(target=fifo_loop, daemon=True).start()
    subprocess.run(['pkill', '-f', 'gta2/keyboard/Keyboard.qml'])   # never two keyboards (orphans of a killed helper)
    srv = ThreadingHTTPServer(('127.0.0.1', PORT), H); srv.daemon_threads = True
    env = dict(os.environ, QT_QPA_PLATFORM='xcb', QT_XCB_GL_INTEGRATION='xcb_egl', QSG_RENDER_LOOP='threaded', QML_XHR_ALLOW_FILE_READ='1', QML_XHR_ALLOW_FILE_WRITE='1')
    ui = subprocess.Popen(['/usr/lib/qt6/bin/qml', '/usr/share/gta2/keyboard/Keyboard.qml'], env=env,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    threading.Thread(target=lambda: (ui.wait(), os._exit(1)), daemon=True).start()   # restart both if the UI dies
    signal.signal(signal.SIGTERM, lambda *a: (ui.kill(), os._exit(0)))                 # and take the UI down with us
    srv.serve_forever()
