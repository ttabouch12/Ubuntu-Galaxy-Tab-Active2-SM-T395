#!/usr/bin/python3
"""gta2-ytd: persistent YouTube helper for the gta2 YouTube app (127.0.0.1:8099 only, runs as the desktop user).

Metadata comes straight from YouTube's InnerTube JSON API (search/browse/next, ~0.7-1.2 s) instead of spawning
yt-dlp per request (~5 s). yt-dlp (Python module, loaded once) only resolves stream URLs, H.264 so the Exynos MFC
decodes them; resolved URLs are cached for 5 h and the first results are pre-resolved in the background.

GET  /search?q=&cont=   /home?cont=   /channel?id=&cont=   /video?id=   /suggest?q=   /resolve?id=
     /thumb?id=&q=mq|hq (disk-cached JPEG)   /lists (subs, history, watch later)
POST /play {id,title,channel,channel_id,dur,meta}   /sub {channel_id,name,on}   /later {item,on}   /hist_clear
"""
import http.client, json, os, re, subprocess, threading, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8099
CFG = os.path.expanduser('~/.config/gta2/yt.json')
THUMBS = os.path.expanduser('~/.cache/gta2-youtube/thumbs')
ID_RE = re.compile(r'^[A-Za-z0-9_-]{11}$')
CH_RE = re.compile(r'^UC[A-Za-z0-9_-]{22}$')
CTX = {'client': {'clientName': 'WEB', 'clientVersion': '2.20251120.01.00', 'hl': 'en', 'gl': 'TR'}}
FMT = 'bv*[vcodec^=avc1][height<=1080][fps<=30]+ba[ext=m4a]/bv*[vcodec^=avc1][height<=720]+ba[ext=m4a]/b[vcodec^=avc1]/b'
POOL = ThreadPoolExecutor(6)
LOCK = threading.Lock()
_tls = threading.local()
_cache = {}          # key -> (time, value)
_streams = {}        # video id -> (time, info dict)
_resolving = {}      # video id -> Event


# ---------- InnerTube ----------
def _conn():
    c = getattr(_tls, 'c', None)
    if c is None:
        c = _tls.c = http.client.HTTPSConnection('www.youtube.com', timeout=10)
    return c


def it(ep, body):
    data = json.dumps(dict(context=CTX, **body))
    for attempt in (0, 1):   # keep-alive connection; reconnect once if the server closed it
        try:
            c = _conn()
            c.request('POST', '/youtubei/v1/%s?prettyPrint=false' % ep, data, {'Content-Type': 'application/json'})
            r = c.getresponse(); raw = r.read()
            if r.status != 200: raise RuntimeError('HTTP %d' % r.status)
            return json.loads(raw)
        except Exception:
            _tls.c = None
            if attempt: raise


def cached(key, ttl, fn):
    now = time.time()
    with LOCK:
        v = _cache.get(key)
        if v and now - v[0] < ttl: return v[1]
    val = fn()
    with LOCK: _cache[key] = (now, val)
    return val


def walk(o, fn):
    if isinstance(o, dict):
        if fn(o) is not False:
            for v in o.values(): walk(v, fn)
    elif isinstance(o, list):
        for v in o: walk(v, fn)


def txt(o):
    if not o: return ''
    if isinstance(o, str): return o
    if 'simpleText' in o: return o['simpleText']
    if 'content' in o: return o['content']
    return ''.join(r.get('text', '') for r in o.get('runs', []))


def first(o, pred):
    out = []
    def f(d):
        if out: return False
        if pred(d): out.append(d); return False
    walk(o, f)
    return out[0] if out else None


def chan_id(o):
    d = first(o, lambda d: isinstance(d.get('browseEndpoint'), dict) and str(d['browseEndpoint'].get('browseId', '')).startswith('UC'))
    return d['browseEndpoint']['browseId'] if d else ''


def from_renderer(v):   # classic videoRenderer / compactVideoRenderer / gridVideoRenderer
    i = v.get('videoId', '')
    if not ID_RE.match(i): return None
    ch = v.get('ownerText') or v.get('longBylineText') or v.get('shortBylineText') or {}
    views = txt(v.get('shortViewCountText')) or txt(v.get('viewCountText'))
    age = txt(v.get('publishedTimeText'))
    return {'id': i, 'title': txt(v.get('title')), 'channel': txt(ch), 'channel_id': chan_id(ch),
            'dur': txt(v.get('lengthText')), 'meta': ' · '.join(x for x in (views, age) if x)}


def from_lockup(v):     # new lockupViewModel (channel pages, related videos)
    if v.get('contentType') not in (None, 'LOCKUP_CONTENT_TYPE_VIDEO'): return None
    i = v.get('contentId', '')
    if not ID_RE.match(i): return None
    md = (v.get('metadata') or {}).get('lockupMetadataViewModel') or {}
    rows = []
    walk(md.get('metadata') or {}, lambda d: rows.append([txt(p.get('text')) for p in d['metadataParts']]) if 'metadataParts' in d else None)
    rows = [[p for p in r if p] for r in rows]
    dur = ''
    def bd(d):
        nonlocal dur
        t = d.get('thumbnailBadgeViewModel', {}).get('text', '')
        if not dur and re.match(r'^\d+(:\d\d)+$', t): dur = t
    walk(v.get('contentImage') or {}, bd)
    ch = rows[0][0] if len(rows) > 1 and rows[0] else ''
    meta = ' · '.join(rows[-1]) if rows else ''
    return {'id': i, 'title': txt(md.get('title')), 'channel': ch, 'channel_id': chan_id(v), 'dur': dur, 'meta': meta}


def items(d):
    res, seen = [], set()
    def f(o):
        for k, conv in (('videoRenderer', from_renderer), ('compactVideoRenderer', from_renderer),
                        ('gridVideoRenderer', from_renderer), ('lockupViewModel', from_lockup)):
            if k in o and isinstance(o[k], dict):
                x = conv(o[k])
                if x and x['id'] not in seen: seen.add(x['id']); res.append(x)
                return False
        if 'reelShelfRenderer' in o or 'shortsLockupViewModel' in o or 'gridShelfViewModel' in o: return False   # no Shorts
    walk(d, f)
    tok = first(d, lambda o: isinstance(o.get('continuationCommand'), dict))
    return res, (tok['continuationCommand'].get('token', '') if tok else '')


def search(q, cont=''):
    body = {'continuation': cont} if cont else {'query': q, 'params': 'EgIQAQ%3D%3D'}   # videos only
    r, c = items(it('search', body))
    return {'items': r, 'cont': c}


def channel(cid, cont=''):
    body = {'continuation': cont} if cont else {'browseId': cid, 'params': 'EgZ2aWRlb3PyBgQKAjoA'}   # "Videos" tab
    r, c = items(it('browse', body))
    return {'items': r, 'cont': c}


def home(cont='', subs_feed=False):
    subs = cfg()['subs']
    if subs_feed:
        if not subs: return {'items': [], 'cont': ''}
        feeds = list(POOL.map(lambda s: cached('ch:' + s['channel_id'], 900, lambda: channel(s['channel_id'])), subs[:12]))
        out, k = [], 0
        while any(k < len(f['items']) for f in feeds) and len(out) < 60:   # interleave newest videos of each channel
            for f in feeds:
                if k < len(f['items']): out.append(f['items'][k])
            k += 1
        return {'items': out, 'cont': ''}
    # YouTube removed the public trending page (browse FEtrending -> 400): most-viewed videos of this week across topics
    topics = ['music', 'gaming', 'news', 'football', 'technology', 'comedy']
    feeds = list(POOL.map(lambda t: cached('pop:' + t, 1800, lambda: _popular(t)), topics))
    out, seen, k = [], set(), 0
    while any(k < len(f) for f in feeds) and len(out) < 60:
        for f in feeds:
            if k < len(f) and f[k]['id'] not in seen: seen.add(f[k]['id']); out.append(f[k])
        k += 1
    return {'items': out, 'cont': ''}


def _popular(topic):
    body = {'query': topic, 'params': 'CAMSBAgDEAE%3D'}   # sort by views, uploaded this week, videos only
    return items(it('search', body))[0][:12]


def video(vid):
    d = it('next', {'videoId': vid})
    prim = first(d, lambda o: 'videoPrimaryInfoRenderer' in o)
    sec = first(d, lambda o: 'videoSecondaryInfoRenderer' in o)
    p = prim['videoPrimaryInfoRenderer'] if prim else {}
    s = sec['videoSecondaryInfoRenderer'] if sec else {}
    own = (s.get('owner') or {}).get('videoOwnerRenderer') or {}
    rel, _ = items(first(d, lambda o: 'secondaryResults' in o) or {})
    vc = first(p, lambda o: 'videoViewCountRenderer' in o)
    return {'id': vid, 'title': txt(p.get('title')), 'channel': txt(own.get('title')), 'channel_id': chan_id(own),
            'subs': txt(own.get('subscriberCountText')),
            'views': txt((vc or {}).get('videoViewCountRenderer', {}).get('shortViewCount')) or txt((vc or {}).get('videoViewCountRenderer', {}).get('viewCount')),
            'date': txt(p.get('relativeDateText')) or txt(p.get('dateText')),
            'desc': txt(s.get('attributedDescription')) or txt(s.get('description')), 'related': rel[:20]}


def suggest(q):
    u = 'https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=' + urllib.parse.quote(q)
    return json.loads(urllib.request.urlopen(u, timeout=4).read().decode('utf-8', 'replace'))[1][:8]


# ---------- streams (yt-dlp) ----------
_ydl = None
def ydl():
    global _ydl
    if _ydl is None:
        try: import yt_dlp
        except ImportError:   # yt-dlp installed with pipx: use its venv's site-packages
            import glob, sys
            sys.path[:0] = glob.glob('/usr/local/pipx/venvs/yt-dlp/lib/python3*/site-packages')
            import yt_dlp
        _ydl = yt_dlp.YoutubeDL({'format': FMT, 'quiet': True, 'no_warnings': True, 'noplaylist': True})
    return _ydl


def resolve(vid, wait=True):
    with LOCK:
        s = _streams.get(vid)
        if s and time.time() - s[0] < 5 * 3600: return s[1]
        ev = _resolving.get(vid)
        mine = ev is None
        if mine: ev = _resolving[vid] = threading.Event()
    if not mine:
        if wait: ev.wait(30)
        with LOCK: s = _streams.get(vid)
        return s[1] if s else None
    try:
        info = ydl().extract_info('https://www.youtube.com/watch?v=' + vid, download=False)
        fs = info.get('requested_formats') or [info]
        val = {'video': fs[0]['url'], 'audio': fs[1]['url'] if len(fs) > 1 else '',
               'headers': fs[0].get('http_headers') or {}, 'height': fs[0].get('height')}
        with LOCK: _streams[vid] = (time.time(), val)
        return val
    except Exception:
        return None
    finally:
        with LOCK: _resolving.pop(vid, None)
        ev.set()


def prefetch(lst, n=2):
    for x in (lst or [])[:n]: POOL.submit(resolve, x['id'], False)


def play(it_):
    vid = it_.get('id', '')
    if not ID_RE.match(vid): return False
    subprocess.call(['pkill', '-x', 'mpv'])
    s = resolve(vid)
    common = ['mpv', '--force-window=immediate', '--hwdec=v4l2m2m-copy', '--vo=gpu', '--gpu-context=x11egl', '--profile=fast',
              '--cache=yes', '--demuxer-max-bytes=64MiB', '--demuxer-readahead-secs=20', '--hr-seek=no', '--keep-open=no',
              '--script-opts=osc-scalewindowed=2,osc-scalefullscreen=2,osc-layout=bottombar,osc-hidetimeout=2500,osc-deadzonesize=0',
              '--title=' + (it_.get('title') or 'youtube')[:80]]
    if s:   # direct URLs: no yt-dlp start-up in mpv -> first frame much sooner
        hdr = ','.join('%s: %s' % (k, v) for k, v in s['headers'].items() if k.lower() in ('user-agent', 'referer', 'origin'))
        cmd = common + (['--http-header-fields=' + hdr] if hdr else []) + (['--audio-file=' + s['audio']] if s['audio'] else []) + [s['video']]
    else:   # fall back to mpv's own yt-dlp hook
        cmd = ['/usr/local/bin/gta2-ytplay', vid]
    subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    c = cfg(); h = [x for x in c['hist'] if x.get('id') != vid]
    h.insert(0, {k: it_.get(k, '') for k in ('id', 'title', 'channel', 'channel_id', 'dur', 'meta')})
    c['hist'] = h[:200]; cfg(c)
    return True


# ---------- local lists ----------
def cfg(upd=None):
    with LOCK:
        if upd is not None:
            os.makedirs(os.path.dirname(CFG), exist_ok=True)
            tmp = CFG + '.tmp'; json.dump(upd, open(tmp, 'w')); os.replace(tmp, CFG)
            return upd
        try: c = json.load(open(CFG))
        except Exception: c = {}
    for k in ('subs', 'hist', 'later'): c.setdefault(k, [])
    for k in ('hist', 'later'):   # older history entries (agent Y format) -> card fields
        for x in c[k]: x.setdefault('dur', ''); x.setdefault('meta', '')
    return c


def thumb(vid, q):
    os.makedirs(THUMBS, exist_ok=True)
    name = 'hqdefault' if q == 'hq' else 'mqdefault'
    p = os.path.join(THUMBS, '%s_%s.jpg' % (vid, name))
    if not os.path.exists(p):
        data = urllib.request.urlopen('https://i.ytimg.com/vi/%s/%s.jpg' % (vid, name), timeout=8).read()
        tmp = p + '.tmp'; open(tmp, 'wb').write(data); os.replace(tmp, p)
    return open(p, 'rb').read()


class H(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *a): pass

    def out(self, obj, code=200, ctype='application/json'):
        b = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        self.send_response(code); self.send_header('Content-Type', ctype); self.send_header('Content-Length', str(len(b)))
        self.send_header('Access-Control-Allow-Origin', '*')
        if ctype.startswith('image'): self.send_header('Cache-Control', 'max-age=604800')
        self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
        p, cont = u.path, q.get('cont', '')[:2000]
        try:
            if p == '/search':
                s = q.get('q', '').strip()[:120]
                if not s and not cont: return self.out({'items': [], 'cont': ''})
                r = cached('s:%s:%s' % (s, cont), 600, lambda: search(s, cont)); prefetch(r['items'])
                return self.out(r)
            if p == '/home':
                sf = q.get('feed') == 'subs'
                return self.out(cached('home:%s:%s' % (sf, cont), 900, lambda: home(cont, sf)))
            if p == '/channel':
                c = q.get('id', '')
                if not CH_RE.match(c): return self.out({'error': 'bad id'}, 400)
                return self.out(cached('ch:%s:%s' % (c, cont), 900, lambda: channel(c, cont)))
            if p == '/video':
                v = q.get('id', '')
                if not ID_RE.match(v): return self.out({'error': 'bad id'}, 400)
                POOL.submit(resolve, v, False)
                return self.out(cached('v:' + v, 1800, lambda: video(v)))
            if p == '/suggest': return self.out(suggest(q.get('q', '')[:80]) if q.get('q') else [])
            if p == '/resolve':
                v = q.get('id', '')
                if ID_RE.match(v): POOL.submit(resolve, v, False)
                return self.out({'ok': True})
            if p == '/thumb':
                v = q.get('id', '')
                if not ID_RE.match(v): return self.out(b'', 400, 'text/plain')
                return self.out(thumb(v, q.get('q', 'mq')), 200, 'image/jpeg')
            if p == '/lists': return self.out(cfg())
            self.out({'error': 'not found'}, 404)
        except Exception as e:
            self.out({'error': str(e)[:200], 'items': [], 'cont': ''}, 502)

    def do_POST(self):
        n = min(int(self.headers.get('Content-Length') or 0), 65536)
        try: body = json.loads(self.rfile.read(n) or b'{}')
        except Exception: body = {}
        p = urllib.parse.urlparse(self.path).path
        try:
            if p == '/play': return self.out({'ok': play(body)})
            c = cfg()
            if p == '/sub':
                cid = body.get('channel_id', '')
                if not CH_RE.match(cid): return self.out({'error': 'bad id'}, 400)
                c['subs'] = [s for s in c['subs'] if s.get('channel_id') != cid]
                if body.get('on'): c['subs'].insert(0, {'channel_id': cid, 'name': str(body.get('name', ''))[:100]})
                with LOCK: [_cache.pop(k) for k in list(_cache) if k.startswith('home')]
            elif p == '/later':
                x = body.get('item') or {}
                if not ID_RE.match(x.get('id', '')): return self.out({'error': 'bad id'}, 400)
                c['later'] = [y for y in c['later'] if y.get('id') != x['id']]
                if body.get('on'): c['later'].insert(0, {k: str(x.get(k, ''))[:300] for k in ('id', 'title', 'channel', 'channel_id', 'dur', 'meta')})
            elif p == '/hist_clear': c['hist'] = []
            else: return self.out({'error': 'not found'}, 404)
            cfg(c); return self.out({'ok': True, 'lists': c})
        except Exception as e:
            self.out({'error': str(e)[:200]}, 502)


if __name__ == '__main__':
    POOL.submit(ydl)   # import yt-dlp once, in the background
    ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
