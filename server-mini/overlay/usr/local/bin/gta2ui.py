# gta2ui: shared look and touch helpers for the gta2srv Tk apps (v2: rounded, anti-aliased widgets drawn with PIL)
import tkinter as tk, subprocess, time
from functools import lru_cache
try:
    from PIL import Image, ImageDraw, ImageTk
except ImportError:  # still usable without PIL (flat widgets)
    Image = None

# palette (dark, Material-like)
BG, CARD, CARD2, LINE = '#0f1115', '#1a1d24', '#252a33', '#2e3440'
FG, DIM, FAINT = '#eef1f6', '#9aa3b2', '#5c6574'
ACC, OK, WARN, BAD = '#5b8cff', '#38c172', '#f2a93b', '#ef5a5a'
TILE = ['#5b8cff', '#7a5cff', '#22b8cf', '#38c172', '#f2a93b', '#ef6f9a', '#8e9aaf', '#ef5a5a']
F = 'DejaVu Sans'
MONO = 'DejaVu Sans Mono'


class Drag:
    dragged = False
    y = 0
    acc = 0
    target = None


def sh(c, t=10):
    try:
        p = subprocess.run(c, shell=isinstance(c, str), capture_output=True, text=True, timeout=t)
        return (p.stdout + p.stderr).strip()
    except Exception as e:
        return str(e)


def rd(p, d='?'):
    try:
        return open(p).read().strip()
    except OSError:
        return d


def keyboard(show=True):
    if show:
        subprocess.Popen('pgrep -x matchbox-keyboa >/dev/null || matchbox-keyboard', shell=True, start_new_session=True)
    else:
        subprocess.Popen('pkill -x matchbox-keyboa', shell=True)


@lru_cache(maxsize=256)
def _rr(w, h, r, fill, outline=None, ow=0):
    """anti-aliased rounded rectangle (supersampled) as RGBA PIL image"""
    s = 3
    im = Image.new('RGBA', (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w * s - 1, h * s - 1), r * s, fill=fill, outline=outline, width=ow * s)
    return im.resize((w, h), Image.LANCZOS)


_keep = []


def rrect(w, h, r=18, fill=CARD, outline=None, ow=0):
    """PhotoImage of a rounded rectangle (kept alive)"""
    if Image is None:
        return None
    ph = ImageTk.PhotoImage(_rr(max(2, int(w)), max(2, int(h)), r, fill, outline, ow))
    _keep.append(ph)
    if len(_keep) > 600:
        del _keep[:200]
    return ph


@lru_cache(maxsize=64)
def _circle(d, fill):
    s = 3
    im = Image.new('RGBA', (d * s, d * s), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((0, 0, d * s - 1, d * s - 1), fill=fill)
    return im.resize((d, d), Image.LANCZOS)


def circle(d, fill):
    if Image is None:
        return None
    ph = ImageTk.PhotoImage(_circle(d, fill))
    _keep.append(ph)
    return ph


class RButton(tk.Canvas):
    """rounded, anti-aliased button; ignores taps that were finger scrolls"""

    def __init__(self, master, text, cmd, bg=ACC, fg='white', font=None, h=52, r=14, width=None, parent_bg=None, **k):
        pb = parent_bg or (master.cget('bg') if 'bg' in master.keys() else BG)
        super().__init__(master, height=h, bg=pb, highlightthickness=0, bd=0, **({'width': width} if width else {}))
        self.text, self.cmd, self.col, self.fg, self.r, self.h = text, cmd, bg, fg, r, h
        self.font = font or (F, 15, 'bold')
        self.bind('<Configure>', lambda e: self.draw())
        self.bind('<ButtonPress-1>', lambda e: self.draw(True))
        self.bind('<ButtonRelease-1>', self._rel)

    def draw(self, pressed=False):
        self.delete('all')
        w = max(10, self.winfo_width())
        col = _shade(self.col, 0.82) if pressed else self.col
        img = rrect(w, self.h, self.r, col)
        if img:
            self.create_image(0, 0, image=img, anchor='nw')
        else:
            self.create_rectangle(0, 0, w, self.h, fill=col, width=0)
        self.create_text(w // 2, self.h // 2, text=self.text, fill=self.fg, font=self.font)

    def set(self, text=None, bg=None):
        if text is not None:
            self.text = text
        if bg is not None:
            self.col = bg
        self.draw()

    def _rel(self, e):
        self.draw()
        if not Drag.dragged and 0 <= e.x <= self.winfo_width() and 0 <= e.y <= self.h:
            self.cmd()


def _shade(hexcol, f):
    hexcol = hexcol.lstrip('#')
    r, g, b = (int(hexcol[i:i + 2], 16) for i in (0, 2, 4))
    return '#%02x%02x%02x' % (int(r * f), int(g * f), int(b * f))


def btn(p, t, cmd, bg=ACC, font=None, **k):
    k.pop('width', None)
    return RButton(p, t, cmd, bg=bg, font=font or (F, 14, 'bold'), parent_bg=p.cget('bg'))


def lbl(p, t='', fg=FG, bg=None, font=None, **k):
    return tk.Label(p, text=t, fg=fg, bg=bg or p.cget('bg'), font=font or (F, 15), **k)


def entry(p, val='', show=None, width=None, font=None):
    e = tk.Entry(p, font=font or (F, 16), show=show, bg=CARD2, fg=FG, insertbackground=FG, relief='flat', bd=8,
                 highlightthickness=2, highlightbackground=CARD2, highlightcolor=ACC)
    if width:
        e.configure(width=width)
    e.insert(0, val)
    e.bind('<FocusIn>', lambda ev: keyboard(True))
    return e


def section(p, title, sub=None):
    """card with a title; returns the inner frame"""
    outer = tk.Frame(p, bg=BG)
    outer.pack(fill='x', padx=14, pady=8)
    f = tk.Frame(outer, bg=CARD, highlightthickness=0)
    f.pack(fill='x')
    tk.Label(f, text=title.upper(), font=(F, 11, 'bold'), bg=CARD, fg=ACC).pack(anchor='w', padx=16, pady=(14, 0))
    if sub:
        tk.Label(f, text=sub, font=(F, 11), bg=CARD, fg=DIM, justify='left', wraplength=700).pack(anchor='w', padx=16)
    inner = tk.Frame(f, bg=CARD)
    inner.pack(fill='x', padx=10, pady=(6, 12))
    return inner


def row(p, label, widget_factory=None, sub=None):
    """settings row: label (+ sub text) on the left, widget on the right"""
    r = tk.Frame(p, bg=p.cget('bg'))
    r.pack(fill='x', padx=6, pady=5)
    left = tk.Frame(r, bg=r.cget('bg'))
    left.pack(side='left', fill='x', expand=True)
    tk.Label(left, text=label, font=(F, 15), bg=r.cget('bg'), fg=FG, anchor='w').pack(anchor='w')
    if sub:
        tk.Label(left, text=sub, font=(F, 11), bg=r.cget('bg'), fg=DIM, anchor='w', justify='left', wraplength=460).pack(anchor='w')
    w = widget_factory(r) if widget_factory else None
    if w is not None:
        w.pack(side='right')
    return r, w


class Toggle(tk.Canvas):
    """iOS/Material style switch"""

    def __init__(self, master, value=False, cmd=None):
        super().__init__(master, width=70, height=40, bg=master.cget('bg'), highlightthickness=0, bd=0)
        self.v, self.cmd = bool(value), cmd
        self.bind('<ButtonRelease-1>', self._tap)
        self.draw()

    def draw(self):
        self.delete('all')
        img = rrect(64, 34, 17, ACC if self.v else LINE)
        if img:
            self.create_image(3, 3, image=img, anchor='nw')
        c = circle(26, 'white')
        x = 38 if self.v else 7
        if c:
            self.create_image(x, 7, image=c, anchor='nw')

    def get(self):
        return self.v

    def set(self, v):
        self.v = bool(v)
        self.draw()

    def _tap(self, e):
        if Drag.dragged:
            return
        self.v = not self.v
        self.draw()
        if self.cmd:
            self.cmd(self.v)


class Stepper(tk.Frame):
    """− value + control"""

    def __init__(self, master, value, lo, hi, step=1, fmt='%d', cmd=None):
        super().__init__(master, bg=master.cget('bg'))
        self.v, self.lo, self.hi, self.step, self.fmt, self.cmd = value, lo, hi, step, fmt, cmd
        RButton(self, '−', lambda: self.bump(-1), bg=CARD2, width=52, h=44, font=(F, 18, 'bold'), parent_bg=self.cget('bg')).pack(side='left')
        self.l = tk.Label(self, text=fmt % value, font=(F, 16, 'bold'), bg=self.cget('bg'), fg=FG, width=6)
        self.l.pack(side='left')
        RButton(self, '+', lambda: self.bump(1), bg=CARD2, width=52, h=44, font=(F, 18, 'bold'), parent_bg=self.cget('bg')).pack(side='left')

    def bump(self, d):
        self.v = max(self.lo, min(self.hi, self.v + d * self.step))
        self.l.config(text=self.fmt % self.v)
        if self.cmd:
            self.cmd(self.v)

    def get(self):
        return self.v


class Choice(tk.Frame):
    """segmented control"""

    def __init__(self, master, options, value, cmd=None):
        super().__init__(master, bg=master.cget('bg'))
        self.opts, self.v, self.cmd, self.b = options, value, cmd, {}
        for val, txt in options:
            b = RButton(self, txt, lambda val=val: self.pick(val), bg=CARD2, h=46, width=10, font=(F, 13, 'bold'), parent_bg=self.cget('bg'))
            b.pack(side='left', expand=True, fill='x', padx=3)
            self.b[val] = b
        self.pick(value, silent=True)

    def pick(self, val, silent=False):
        self.v = val
        for k, b in self.b.items():
            b.set(bg=ACC if k == val else CARD2)
        if self.cmd and not silent:
            self.cmd(val)

    def get(self):
        return self.v


class Page(tk.Frame):
    """Vertically scrollable page; drag anywhere with a finger to scroll."""

    def __init__(self, master):
        super().__init__(master, bg=BG)
        self.cv = tk.Canvas(self, bg=BG, highlightthickness=0, bd=0)
        self.cv.pack(side='left', fill='both', expand=True)
        self.body = tk.Frame(self.cv, bg=BG)
        self.win = self.cv.create_window(0, 0, window=self.body, anchor='nw')
        self.body.bind('<Configure>', lambda e: self.cv.configure(scrollregion=self.cv.bbox('all')))
        self.cv.bind('<Configure>', lambda e: self.cv.itemconfigure(self.win, width=e.width))

    def scroll_px(self, dy):
        h = max(1, self.body.winfo_height())
        if h <= self.cv.winfo_height():
            return
        self.cv.yview_moveto(max(0.0, self.cv.yview()[0] - dy / h))

    def top(self):
        self.cv.yview_moveto(0)


def _target(w):
    while w is not None:
        if isinstance(w, (tk.Scale, tk.Scrollbar)) or type(w).__name__ == 'Slider':
            return None
        if isinstance(w, (tk.Listbox, Page)):
            return w
        w = getattr(w, 'master', None)
    return None


def _press(e):
    Drag.dragged = False
    Drag.y = e.y_root
    Drag.acc = 0
    Drag.target = _target(e.widget)


def _motion(e):
    t = Drag.target
    if t is None:
        return
    dy = e.y_root - Drag.y
    if not Drag.dragged and abs(dy) < 14:
        return
    Drag.dragged = True
    Drag.y = e.y_root
    if isinstance(t, tk.Listbox):
        Drag.acc += dy
        n = int(Drag.acc / 30)
        if n:
            t.yview_scroll(-n, 'units')
            Drag.acc -= n * 30
    else:
        t.scroll_px(dy)


def install_drag(root):
    root.bind_all('<ButtonPress-1>', _press, add='+')
    root.bind_all('<B1-Motion>', _motion, add='+')


def touch_list(lb, on_select=None):
    """Listbox that scrolls with a finger and selects on tap (not while dragging)."""
    def press(e):
        _press(e)
        return 'break'

    def motion(e):
        _motion(e)
        return 'break'

    def release(e):
        if not Drag.dragged:
            i = lb.nearest(e.y)
            lb.selection_clear(0, 'end')
            lb.selection_set(i)
            lb.activate(i)
            if on_select:
                on_select(i)
        return 'break'
    lb.bind('<ButtonPress-1>', press)
    lb.bind('<B1-Motion>', motion)
    lb.bind('<ButtonRelease-1>', release)
    return lb


def listbox(p, height=8, font=None):
    f = tk.Frame(p, bg=p.cget('bg'))
    lb = tk.Listbox(f, font=font or (F, 16), height=height, bg=CARD2, fg=FG, selectbackground=ACC, selectforeground='white',
                    activestyle='none', bd=0, highlightthickness=0, exportselection=0, relief='flat')
    sb = tk.Scrollbar(f, orient='vertical', command=lb.yview, width=26, bg=CARD, troughcolor=CARD2, bd=0)
    lb.configure(yscrollcommand=sb.set)
    sb.pack(side='right', fill='y')
    lb.pack(side='left', fill='both', expand=True)
    return f, lb


def bar(p, w=300, h=8, bg=CARD2):
    c = tk.Canvas(p, width=w, height=h, bg=p.cget('bg'), highlightthickness=0, bd=0)

    def set_(frac, color=None):
        frac = max(0.0, min(1.0, frac))
        c.delete('all')
        W = c.winfo_width() if c.winfo_width() > 1 else w
        t = rrect(W, h, h // 2, bg)
        if t:
            c.create_image(0, 0, image=t, anchor='nw')
        col = color or (OK if frac < .6 else WARN if frac < .85 else BAD)
        if frac > 0.01:
            fw = max(h, int(W * frac))
            f = rrect(fw, h, h // 2, col)
            if f:
                c.create_image(0, 0, image=f, anchor='nw')
    c.set = set_
    return c


def header(root, title, back=None, right=None):
    """app bar: ‹ back, title, optional right button"""
    top = tk.Frame(root, bg=BG)
    top.pack(fill='x', pady=(14, 6), padx=10)
    if back:
        RButton(top, '‹', back, bg=CARD, width=56, h=50, r=25, font=(F, 24, 'bold'), parent_bg=BG).pack(side='left')
    tk.Label(top, text=title, font=(F, 24, 'bold'), bg=BG, fg=FG).pack(side='left', padx=14)
    if right:
        for t, c in right:
            RButton(top, t, c, bg=CARD, width=56, h=50, r=25, font=(F, 18), parent_bg=BG).pack(side='right', padx=3)
    return top


def glyph(cv, cx, cy, ic, size=30, fill='white'):
    """draw an icon centered at (cx, cy): vector shapes for symbols DejaVu lacks, else the text glyph"""
    s = size / 30.0
    w = max(2, int(3 * s))
    if ic == 'power':
        cv.create_arc(cx - 12 * s, cy - 11 * s, cx + 12 * s, cy + 13 * s, start=125, extent=290, style='arc', outline=fill, width=w)
        cv.create_line(cx, cy - 15 * s, cx, cy + 1 * s, fill=fill, width=w, capstyle='round')
    elif ic == 'bt':
        p = [(-7, -7), (7, 7), (0, 14), (0, -14), (7, -7), (-7, 7)]
        cv.create_line(*[v for x, y in p for v in (cx + x * s, cy + y * s)], fill=fill, width=w, capstyle='round', joinstyle='round')
    elif ic == 'vpn':
        p = [(0, -14), (12, -9), (11, 3), (0, 14), (-11, 3), (-12, -9)]
        cv.create_polygon(*[v for x, y in p for v in (cx + x * s, cy + y * s)], outline=fill, fill='', width=w, joinstyle='round')
        cv.create_line(cx - 5 * s, cy, cx - 1 * s, cy + 4 * s, cx + 6 * s, cy - 4 * s, fill=fill, width=w, capstyle='round')
    elif ic == 'docker':
        for i in range(3):
            for j in range(2 if i < 2 else 1):
                x = cx - 11 * s + i * 8 * s; y = cy - 2 * s - j * 7 * s
                cv.create_rectangle(x, y, x + 6 * s, y + 5 * s, outline='', fill=fill)
        cv.create_line(cx - 14 * s, cy + 5 * s, cx + 13 * s, cy + 5 * s, cx + 10 * s, cy + 11 * s, cx - 9 * s, cy + 11 * s,
                       cx - 14 * s, cy + 5 * s, fill=fill, width=w, joinstyle='round')
    elif ic == 'wifi':
        for k in (1, 2, 3):
            rr = 5 * k * s
            cv.create_arc(cx - rr, cy + 8 * s - rr, cx + rr, cy + 8 * s + rr, start=45, extent=90, style='arc', outline=fill, width=w)
        cv.create_oval(cx - 2 * s, cy + 6 * s, cx + 2 * s, cy + 10 * s, fill=fill, outline='')
    else:
        cv.create_text(cx, cy, text=ic, fill=fill, font=(F, int(size * 0.6) if len(ic) > 1 else size, 'bold'))


class Slider(tk.Canvas):
    """touch slider: rounded track, filled part, round knob"""

    def __init__(self, master, lo, hi, value, cmd=None, h=48):
        super().__init__(master, height=h, bg=master.cget('bg'), highlightthickness=0, bd=0)
        self.lo, self.hi, self.v, self.cmd, self.h = lo, hi, value, cmd, h
        self._last = 0
        self.bind('<Configure>', lambda e: self.draw())
        self.bind('<ButtonPress-1>', self._set)
        self.bind('<B1-Motion>', self._set)
        self.bind('<ButtonRelease-1>', lambda e: (self._set(e), self.cmd and self.cmd(self.v)))

    def draw(self):
        self.delete('all')
        w = max(40, self.winfo_width()); k = self.h - 8; th = 12; y0 = (self.h - th) // 2
        t = rrect(w - k, th, th // 2, CARD2)
        if t:
            self.create_image(k // 2, y0, image=t, anchor='nw')
        frac = (self.v - self.lo) / max(1, self.hi - self.lo)
        x = k // 2 + frac * (w - k)
        if frac > 0.01:
            f = rrect(max(th, int(x - k // 2)), th, th // 2, ACC)
            if f:
                self.create_image(k // 2, y0, image=f, anchor='nw')
        c = circle(k, 'white')
        if c:
            self.create_image(x - k // 2, 4, image=c, anchor='nw')

    def _set(self, e):
        w = max(40, self.winfo_width()); k = self.h - 8
        frac = max(0.0, min(1.0, (e.x - k / 2) / max(1, w - k)))
        self.v = int(self.lo + frac * (self.hi - self.lo))
        self.draw()
        if self.cmd and time.time() - self._last > 0.08:
            self._last = time.time(); self.cmd(self.v)
