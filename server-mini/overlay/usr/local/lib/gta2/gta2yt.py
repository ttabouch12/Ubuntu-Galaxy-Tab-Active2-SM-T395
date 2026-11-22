"""gta2 YouTube helper for gta2-dash: search / trending / channel feeds via yt-dlp, local subscriptions + history.
GET /yt?op=search&q=..|op=trending|op=channel&c=UC..|@handle|op=subs|op=hist   (read-only, JSON)
ctl yt_play {id,title,channel,channel_id}   ctl yt_sub {channel_id,name,on}   ctl yt_hist_clear
yt-dlp always runs as the desktop user (never root), with a timeout; results are cached for 10 minutes."""
import hashlib, json, os, re, subprocess, time

CFG = '/home/gta2/.config/gta2/yt.json'
CACHE = '/tmp/gta2yt'
ID_RE = re.compile(r'^[A-Za-z0-9_-]{11}$')
CH_RE = re.compile(r'^(UC[A-Za-z0-9_-]{22}|@[A-Za-z0-9._-]{2,40})$')


def _ytdlp():
    for p in ('/usr/local/bin/yt-dlp', '/usr/bin/yt-dlp'):
        if os.path.exists(p): return [p]
    return ['python3', '-m', 'yt_dlp']


def _cfg(upd=None):
    try: c = json.load(open(CFG))
    except Exception: c = {}
    c.setdefault('subs', []); c.setdefault('hist', [])
    if upd is not None:
        os.makedirs(os.path.dirname(CFG), exist_ok=True)
        json.dump(upd, open(CFG, 'w')); os.system('chown gta2:gta2 ' + CFG)
    return c


def _items(url, n=24, ttl=600):
    key = os.path.join(CACHE, hashlib.sha1(url.encode()).hexdigest() + '.json')
    try:
        if time.time() - os.path.getmtime(key) < ttl: return json.load(open(key))
    except Exception: pass
    cmd = ['runuser', '-u', 'gta2', '--'] + _ytdlp() + ['--flat-playlist', '-J', '--playlist-end', str(n),
                                                         '--no-warnings', '--ignore-errors', url]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=40).stdout
        d = json.loads(out or '{}')
    except Exception:
        return []
    res = []
    for e in d.get('entries') or []:
        i = e.get('id') or ''
        if not ID_RE.match(i): continue   # skips shorts shelves / channels in mixed results
        res.append({'id': i, 'title': e.get('title') or '', 'channel': e.get('channel') or e.get('uploader') or d.get('channel') or '',
                    'channel_id': e.get('channel_id') or d.get('channel_id') or '', 'duration': e.get('duration'),
                    'views': e.get('view_count'), 'thumb': 'https://i.ytimg.com/vi/%s/mqdefault.jpg' % i})
    os.makedirs(CACHE, exist_ok=True)
    json.dump(res, open(key, 'w'))
    return res


def handle(meth, path, query, send):
    if meth != 'GET' or path != '/yt': return False
    op = (query.get('op') or ['search'])[0]
    q = (query.get('q') or [''])[0].strip()[:100]
    c = (query.get('c') or [''])[0]
    if op == 'search' and q: res = _items('ytsearch24:' + q)
    elif op == 'trending':
        res = _items('https://www.youtube.com/feed/trending', ttl=1800) or _items('ytsearch24:trending today', ttl=1800)
    elif op == 'channel' and CH_RE.match(c):
        res = _items('https://www.youtube.com/%s/videos' % (c if c.startswith('@') else 'channel/' + c))
    elif op == 'subs': res = _cfg()['subs']
    elif op == 'hist': res = _cfg()['hist']
    else: res = []
    send('200 OK', 'application/json', json.dumps(res))
    return True


def ctl(a, v, x):
    v = v if isinstance(v, dict) else {}
    c = _cfg()
    if a == 'yt_play':
        i = str(v.get('id', ''))
        if not ID_RE.match(i): return None
        e = {'id': i, 'title': str(v.get('title', ''))[:200], 'channel': str(v.get('channel', ''))[:100],
             'channel_id': str(v.get('channel_id', ''))[:40], 'thumb': 'https://i.ytimg.com/vi/%s/mqdefault.jpg' % i}
        c['hist'] = [e] + [h for h in c['hist'] if h.get('id') != i][:99]
        _cfg(c)
        x('/usr/local/bin/gta2-ytplay ' + i)   # id is validated: [A-Za-z0-9_-]{11}
        return {'ok': True}
    if a == 'yt_sub':
        ch = str(v.get('channel_id', ''))
        if not CH_RE.match(ch): return None
        c['subs'] = [s for s in c['subs'] if s.get('channel_id') != ch]
        if v.get('on', True): c['subs'].insert(0, {'channel_id': ch, 'name': str(v.get('name', ''))[:100]})
        _cfg(c)
        return {'ok': True, 'subs': c['subs']}
    if a == 'yt_hist_clear':
        c['hist'] = []; _cfg(c); return {'ok': True}
    return None
