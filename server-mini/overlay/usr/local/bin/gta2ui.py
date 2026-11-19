# gta2ui: shared look and touch helpers for the gta2srv Tk apps (finger scrolling, buttons, pages)
import tkinter as tk, subprocess
BG, CARD, CARD2, FG, DIM, ACC, OK, WARN, BAD = '#0d1117', '#161b22', '#1f2630', '#e6edf3', '#8b949e', '#2f81f7', '#3fb950', '#d29922', '#f85149'
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


def btn(p, t, cmd, bg=ACC, font=None, **k):
    return tk.Button(p, text=t, command=lambda: None if Drag.dragged else cmd(), font=font or (F, 16), bg=bg, fg='white',
                     relief='flat', bd=0, activebackground='#3c82c8', activeforeground='white', padx=12, pady=10, **k)


def lbl(p, t='', fg=FG, bg=BG, font=None, **k):
    return tk.Label(p, text=t, fg=fg, bg=bg, font=font or (F, 16), **k)


def entry(p, val='', show=None, width=None, font=None):
    e = tk.Entry(p, font=font or (F, 16), show=show, bg=CARD2, fg=FG, insertbackground=FG, relief='flat', bd=6)
    if width:
        e.configure(width=width)
    e.insert(0, val)
    e.bind('<FocusIn>', lambda ev: keyboard(True))
    return e


def section(p, title):
    f = tk.Frame(p, bg=CARD)
    f.pack(fill='x', padx=12, pady=8)
    tk.Label(f, text=title, font=(F, 13, 'bold'), bg=CARD, fg=DIM).pack(anchor='w', padx=12, pady=(10, 2))
    return f


class Page(tk.Frame):
    """Vertically scrollable page; drag anywhere with a finger to scroll."""

    def __init__(self, master):
        super().__init__(master, bg=BG)
        self.cv = tk.Canvas(self, bg=BG, highlightthickness=0, bd=0)
        sb = tk.Scrollbar(self, orient='vertical', command=self.cv.yview, width=22)
        self.cv.configure(yscrollcommand=sb.set)
        sb.pack(side='right', fill='y')
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


def _target(w):
    while w is not None:
        if isinstance(w, (tk.Scale, tk.Scrollbar)):
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


def bar(p, w=300, h=16, bg=CARD2):
    c = tk.Canvas(p, width=w, height=h, bg=bg, highlightthickness=0, bd=0)
    c.r = c.create_rectangle(0, 0, 0, h, fill=ACC, width=0)

    def set_(frac, color=None):
        frac = max(0.0, min(1.0, frac))
        W = c.winfo_width() if c.winfo_width() > 1 else w
        c.coords(c.r, 0, 0, W * frac, h)
        c.itemconfigure(c.r, fill=color or (OK if frac < .6 else WARN if frac < .85 else BAD))
    c.set = set_
    return c
