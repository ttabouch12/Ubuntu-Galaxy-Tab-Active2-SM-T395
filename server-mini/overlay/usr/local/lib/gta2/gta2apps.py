"""gta2apps: desktop apps (Pi-Apps, apt, flatpak) for the gta2 home screen. Used by gta2-dash (runs as root).

GET  /apps            -> {"apps": [...], "piapps": bool}  user-facing apps, newest first
GET  /icon?id=<id>    -> PNG icon (theme lookup, SVG rendered with rsvg-convert, cached; letter tile fallback)
GET  /apps/job        -> state of the running/last install-uninstall job
ctl  launch {id}      -> start the app in the X session as gta2
ctl  uninstall {id}   -> Pi-Apps uninstall or apt-get remove (denylist protects the system), runs as a job
"""
import configparser, glob, hashlib, json, os, re, subprocess, time

USER, UHOME = 'gta2', '/home/gta2'
PIAPPS = UHOME + '/pi-apps'
DIRS = ['/usr/share/applications', '/usr/local/share/applications', UHOME + '/.local/share/applications',
        '/var/lib/flatpak/exports/share/applications']
CACHE = '/var/cache/gta2/icons'
JOB = '/run/gta2/apps-job.json'
ID_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,120}$')
PKG_RE = re.compile(r'^[a-z0-9][a-z0-9+.-]{1,100}$')
FIELD_CODES = re.compile(r'\s%[fFuUdDnNickvm]')
# never offered for removal: the system, the tablet UI, desktop mode itself, server stack
DENY = re.compile(r'^(surf|xterm|x11-.*|xserver-.*|xorg.*|xinit|matchbox.*|qml.*|libqt.*|qt6-.*|plymouth.*|picom|'
                  r'lxqt.*|pcmanfm.*|qterminal|openbox|featherpad|breeze.*|yad|docker.*|containerd.*|casaos.*|'
                  r'network-manager.*|openssh.*|systemd.*|sudo|bash|coreutils|python3.*|libc.*|mesa.*|libgl.*|'
                  r'moonlight-qt|tigervnc.*|ffmpeg|pi-hole.*|gta2.*)$')
# not apps: settings panels, session pieces, helpers
HIDE_ID = re.compile(r'^(lxqt-(?!.*runner).*|pcmanfm-qt-desktop.*|openbox.*|org\.freedesktop\..*|xterm|uxterm|'
                     r'debian-.*|yad-.*|display-im6.*|mimeinfo|gta2.*|surf|matchbox.*|vncviewer|.*-settings|'
                     r'nm-.*|software-properties.*|python.*|.*kcm.*|kde-.*|org\.kde\.kwalletd.*|'
                     r'kwalletd.*|org\.kde\.kded.*|ibus.*|im-config|rsvg.*)$')
ALWAYS_HIDE = {'debian-xterm', 'debian-uxterm', 'picom', 'qterminal-drop', 'pcmanfm', 'lxterminal'}
KEEP_CAT = {'TerminalEmulator', 'FileManager', 'WebBrowser', 'TextEditor'}


def _desktop_files():
    seen = {}
    for d in DIRS:
        for f in glob.glob(d + '/*.desktop'):
            i = os.path.basename(f)[:-8]
            if ID_RE.match(i): seen[i] = f          # later dirs (user) override system ones
    return seen


def _parse(f):
    c = configparser.RawConfigParser(interpolation=None, strict=False)
    c.optionxform = str
    try:
        c.read(f, encoding='utf-8')
        return dict(c['Desktop Entry'])
    except Exception:
        return None


def _piapps_status():
    """{pi-apps app name: True} for apps Pi-Apps says are installed, plus {package: app} it installed."""
    inst, pkg2app = {}, {}
    for st in glob.glob(PIAPPS + '/data/status/*'):
        try:
            if open(st).read().strip() == 'installed': inst[os.path.basename(st)] = True
        except OSError: pass
    for a in inst:
        for src in (PIAPPS + '/apps/%s/packages' % a, PIAPPS + '/data/installed-packages/%s' % a):
            try:
                for p in open(src).read().split():
                    if PKG_RE.match(p): pkg2app[p] = a
            except OSError: pass
    return inst, pkg2app


def _owners(files):
    """deb package owning each .desktop file (one dpkg -S call)."""
    out = {}
    if not files: return out
    try:
        r = subprocess.run(['dpkg', '-S'] + files, capture_output=True, text=True, timeout=10)
        for l in r.stdout.splitlines():
            pk, _, path = l.partition(': ')
            out[path.strip()] = pk.split(':')[0].split(',')[0].strip()
    except Exception: pass
    return out


def list_apps():
    files = _desktop_files()
    inst, pkg2app = _piapps_status()
    owners = _owners([f for f in files.values() if f.startswith('/usr/')])
    apps = []
    for i, f in files.items():
        e = _parse(f)
        if not e or e.get('Type') != 'Application' or not e.get('Exec'): continue
        if e.get('NoDisplay', '').lower() == 'true' or e.get('Hidden', '').lower() == 'true': continue
        if e.get('Terminal', '').lower() == 'true' or 'OnlyShowIn' in e: continue
        cats = set(filter(None, e.get('Categories', '').split(';')))
        if i in ALWAYS_HIDE: continue  # duplicates / system tools that only clutter the home screen
        if HIDE_ID.match(i) and not cats & KEEP_CAT: continue
        if ('Settings' in cats or 'DesktopSettings' in cats) and not cats & KEEP_CAT: continue
        if 'gta2' in e.get('Exec', '') and 'Pi-Apps' not in e.get('Name', ''): continue
        pkg = owners.get(f)
        piapp = pkg2app.get(pkg) if pkg else None
        if not piapp:                              # script-installed Pi-Apps apps: match by name
            n = e.get('Name', '').lower()
            piapp = next((a for a in inst if a.lower() == n or a.lower() in n.split(' (')[0]), None)
        src = 'pi-apps' if piapp else 'flatpak' if '/flatpak/' in f else 'apt' if pkg else 'local'
        removable = bool(piapp) or (src == 'apt' and pkg and not DENY.match(pkg))
        if i == 'pi-apps': removable, piapp = False, None   # the store itself
        apps.append({'id': i, 'name': e.get('Name', i), 'comment': e.get('Comment', ''),
                     'icon': '/icon?id=%s&v=%d' % (i, int(os.path.getmtime(f))),
                     'source': src, 'piapp': piapp, 'pkg': pkg, 'removable': bool(removable),
                     'installed': int(os.path.getmtime(f)), 'categories': sorted(cats)})
    apps.sort(key=lambda a: (-a['installed'], a['name'].lower()))
    return {'apps': apps, 'piapps': os.path.isfile(PIAPPS + '/manage')}


# ---------------- icons
THEMES = ['breeze', 'breeze-dark', 'hicolor', 'Adwaita', 'gnome', 'Papirus']


def _find_icon(name):
    if not name: return None
    if name.startswith('/'): return name if os.path.isfile(name) else None
    name = os.path.basename(name)
    best = None
    for t in THEMES:
        base = '/usr/share/icons/' + t
        if not os.path.isdir(base): continue
        for size in ('256x256', '192x192', '128x128', '96x96', '64x64', '48', '64', '96', '128', '256'):
            for c in glob.glob('%s/%s/*/%s.png' % (base, size, name)) + glob.glob('%s/*/%s/%s.png' % (base, size, name)):
                return c
        for c in glob.glob('%s/scalable/*/%s.svg' % (base, name)) + glob.glob('%s/*/*/%s.svg' % (base, name)) \
                + glob.glob('%s/*/*/%s.svgz' % (base, name)):
            best = best or c
        if best: return best
    for ext in ('png', 'svg', 'xpm'):
        p = '/usr/share/pixmaps/%s.%s' % (name, ext)
        if os.path.isfile(p): return p
    for p in glob.glob(UHOME + '/.local/share/icons/**/%s.*' % name, recursive=True):
        return p
    return None


def _letter_svg(text, seed):
    cols = ['#2d89ef', '#2b5797', '#1e7145', '#603cba', '#9f00a7', '#7e3878', '#da532c', '#00aba9', '#e3a21a', '#b91d47']
    c = cols[int(hashlib.md5(seed.encode()).hexdigest(), 16) % len(cols)]
    ch = (text.strip()[:1] or '?').upper().replace('&', '&amp;').replace('<', '&lt;')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><rect width="128" height="128" fill="%s"/>'
            '<text x="64" y="88" font-family="Noto Sans,DejaVu Sans" font-size="68" font-weight="300" fill="#fff" '
            'text-anchor="middle">%s</text></svg>' % (c, ch))


def icon_png(i):
    files = _desktop_files()
    f = files.get(i)
    if not f: return None
    os.makedirs(CACHE, exist_ok=True)
    out = '%s/%s-%d.png' % (CACHE, i, int(os.path.getmtime(f)))
    if os.path.isfile(out): return open(out, 'rb').read()
    e = _parse(f) or {}
    src = _find_icon(e.get('Icon', ''))
    try:
        if src and src.endswith('.png'):
            data = open(src, 'rb').read()
        elif src and (src.endswith('.svg') or src.endswith('.svgz')):
            data = subprocess.run(['rsvg-convert', '-w', '128', '-h', '128', '-a', src], capture_output=True, timeout=10).stdout
        else:
            data = b''
        if not data:
            data = subprocess.run(['rsvg-convert', '-w', '128', '-h', '128'], input=_letter_svg(e.get('Name', i), i).encode(),
                                  capture_output=True, timeout=10).stdout
    except Exception:
        return None
    for old in glob.glob('%s/%s-*.png' % (CACHE, i)):
        try: os.remove(old)
        except OSError: pass
    open(out, 'wb').write(data)
    return data


# ---------------- actions
def _job_state():
    try: return json.load(open(JOB))
    except Exception: return {'state': 'idle'}


def ctl(a, v):
    v = v or {}
    i = v.get('id') if isinstance(v, dict) else v
    files = _desktop_files()
    if a == 'apps_job': return _job_state()
    if not isinstance(i, str) or not ID_RE.match(i) or i not in files: return None
    if a == 'launch':
        e = _parse(files[i]) or {}
        cmd = FIELD_CODES.sub('', ' ' + e.get('Exec', '')).strip()
        if not cmd: return None
        unit = 'gta2app-%s-%d' % (re.sub(r'[^A-Za-z0-9]', '', i)[:40], int(time.time()))
        subprocess.Popen(['systemd-run', '--quiet', '--collect', '--unit=' + unit, '--uid=gta2', '--gid=gta2',
                          '--setenv=DISPLAY=:0', '--setenv=HOME=' + UHOME, '--setenv=XDG_RUNTIME_DIR=/run/user/1000',
                          '--setenv=QT_QPA_PLATFORMTHEME=lxqt', '--working-directory=' + UHOME, 'sh', '-c', cmd],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {'ok': True, 'unit': unit}
    if a == 'uninstall':
        if _job_state().get('state') == 'running': return {'ok': False, 'error': 'another job is running'}
        app = next((x for x in list_apps()['apps'] if x['id'] == i), None)
        if not app or not app['removable']: return {'ok': False, 'error': 'not removable'}
        if app['piapp'] and os.path.isdir(PIAPPS + '/apps/' + app['piapp']):
            argv = ['runuser', '-u', USER, '--', PIAPPS + '/manage', 'uninstall', app['piapp']]
            what = 'Pi-Apps: ' + app['piapp']
        elif app['pkg'] and PKG_RE.match(app['pkg']) and not DENY.match(app['pkg']):
            argv = ['env', 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 'remove', '-y', app['pkg']]
            what = 'apt: ' + app['pkg']
        else:
            return {'ok': False, 'error': 'not removable'}
        os.makedirs(os.path.dirname(JOB), exist_ok=True)
        json.dump({'state': 'running', 'action': 'uninstall', 'id': i, 'name': app['name'], 'what': what,
                   'started': int(time.time()), 'log': ''}, open(JOB, 'w'))
        subprocess.Popen(['systemd-run', '--quiet', '--collect', '--unit=gta2-apps-job-%d' % int(time.time()),
                          '/usr/bin/python3', '/usr/local/lib/gta2/gta2apps.py', 'job'] + argv,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {'ok': True, 'job': 'started', 'what': what}
    return None


def handle(meth, path, query, send):
    """GET routes; returns True when handled."""
    if meth != 'GET': return False
    if path == '/apps':
        send('200 OK', 'application/json', json.dumps(list_apps()), 'Access-Control-Allow-Origin: *\r\n')
    elif path == '/apps/job':
        send('200 OK', 'application/json', json.dumps(_job_state()), 'Access-Control-Allow-Origin: *\r\n')
    elif path == '/icon':
        i = (query.get('id') or [''])[0]
        data = icon_png(i) if ID_RE.match(i) else None
        if data: send('200 OK', 'image/png', data, 'Cache-Control: max-age=86400\r\n')
        else: send('404 Not Found', 'text/plain', 'no icon')
    else:
        return False
    return True


if __name__ == '__main__' and len(os.sys.argv) > 2 and os.sys.argv[1] == 'job':   # detached job runner
    st = _job_state()
    try:
        r = subprocess.run(os.sys.argv[2:], capture_output=True, text=True, timeout=1800)
        st.update(state='done' if r.returncode == 0 else 'failed', code=r.returncode,
                  log=(r.stdout + r.stderr)[-3000:])
    except Exception as e:
        st.update(state='failed', log=str(e))
    st['finished'] = int(time.time())
    json.dump(st, open(JOB, 'w'))
