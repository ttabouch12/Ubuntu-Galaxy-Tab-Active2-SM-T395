// gta2 panel: single-page UI. No external code. Talks to /api/* (POST needs the X-Gta2 header).
'use strict';
const TILE = ['#5b8cff', '#7a5cff', '#22b8cf', '#38c172', '#f2a93b', '#ef6f9a', '#8e9aaf', '#ef5a5a'];
const $ = (s, r = document) => r.querySelector(s);
const HOST = location.hostname;

// ---------- helpers
function h(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'class') e.className = v;
    else if (k === 'style') e.style.cssText = v;
    else if (k === 'html') e.innerHTML = v;
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const k of kids.flat()) if (k != null && k !== false) e.append(k.nodeType ? k : document.createTextNode(String(k)));
  return e;
}
async function api(path, body) {
  const opt = body === undefined ? {} : {method: 'POST', headers: {'X-Gta2': '1', 'Content-Type': 'application/json'}, body: JSON.stringify(body)};
  const r = await fetch(path, {credentials: 'same-origin', ...opt});
  if (r.status === 401 && path !== '/api/login') { showLogin(); throw new Error('login required'); }
  const ct = r.headers.get('Content-Type') || '';
  const d = ct.includes('json') ? await r.json() : await r.text();
  if (!r.ok) throw new Error((d && d.error) || r.statusText);
  return d;
}
let toastT;
function toast(msg, bad) {
  const t = $('#toast');
  t.textContent = msg; t.className = 'toast' + (bad || /^error/i.test(msg) ? ' bad' : '');
  clearTimeout(toastT); toastT = setTimeout(() => t.classList.add('hidden'), 5000);
}
async function act(path, body, okmsg) {
  try { const d = await api(path, body); toast(d.msg || okmsg || 'done', d.ok === false); return d; }
  catch (e) { toast('error: ' + e.message, true); }
}
function modal(title, body, btns) {
  $('#mtitle').textContent = title;
  const b = $('#mbody'); b.innerHTML = ''; b.append(body);
  const f = $('#mbtns'); f.innerHTML = '';
  const close = () => $('#modal').classList.add('hidden');
  for (const [txt, cls, fn] of (btns || [['Close', '', null]])) f.append(h('button', {class: 'btn ' + cls, onclick: () => { close(); fn && fn(); }}, txt));
  $('#modal').classList.remove('hidden');
}
function confirmDo(text, fn, label = 'Confirm', cls = 'bad') { modal('Are you sure?', h('p', {}, text), [['Cancel', '', null], [label, cls, fn]]); }
const fmtB = n => n > 1e12 ? (n / 1e12).toFixed(1) + ' TB' : n > 1e9 ? (n / 1e9).toFixed(1) + ' GB' : n > 1e6 ? (n / 1e6).toFixed(1) + ' MB' : n > 1e3 ? (n / 1e3).toFixed(0) + ' KB' : n + ' B';
const bar = (frac, col) => h('div', {class: 'bar'}, h('i', {style: `width:${Math.max(0, Math.min(100, frac * 100))}%;background:${col || (frac < .6 ? 'var(--ok)' : frac < .85 ? 'var(--warn)' : 'var(--bad)')}`}));
const sw = (on, fn) => { const i = h('input', {type: 'checkbox'}); i.checked = !!on; i.onchange = () => fn(i.checked); return h('label', {class: 'sw'}, i, h('span')); };
function seg(opts, val, fn) {
  const w = h('div', {class: 'seg'});
  for (const [v, t] of opts) w.append(h('button', {class: v === val ? 'on' : '', onclick: e => { for (const b of w.children) b.classList.remove('on'); e.target.classList.add('on'); fn(v); }}, t));
  return w;
}
const line = (label, sub, ctl) => h('div', {class: 'line'}, h('div', {class: 'l'}, label, sub ? h('small', {}, sub) : null), ctl);
const card = (title, sub, ...kids) => h('div', {class: 'card'}, title ? h('h3', {}, title) : null, sub ? h('p', {class: 'note', style: 'margin-top:-6px'}, sub) : null, ...kids);
const initials = s => s.replace(/^gta2-/, '').split(/[-_ .]/).filter(Boolean).slice(0, 2).map(x => x[0].toUpperCase()).join('');
const colorOf = s => TILE[[...s].reduce((a, c) => a + c.charCodeAt(0), 0) % TILE.length];

// ---------- login / nav
function showLogin() { $('#app').classList.add('hidden'); $('#login').classList.remove('hidden'); stopTimers(); $('#pw').focus(); }
$('#loginform').onsubmit = async e => {
  e.preventDefault(); $('#loginerr').textContent = '';
  try { await api('/api/login', {password: $('#pw').value}); $('#pw').value = ''; start(); }
  catch (err) { $('#loginerr').textContent = err.message; }
};
$('#logout').onclick = async () => { await api('/api/logout', {}).catch(() => 0); showLogin(); };
let timers = [];
function stopTimers() { timers.forEach(clearInterval); timers = []; scrStop(); }
function every(ms, fn) { fn(); timers.push(setInterval(() => { if (!document.hidden) fn(); }, ms)); }
const PAGES = {home: pHome, store: pStore, files: pFiles, screen: pScreen, settings: pSettings};
let cur = 'home';
function go(p) {
  stopTimers(); cur = p;
  for (const a of document.querySelectorAll('nav a[data-page]')) a.classList.toggle('active', a.dataset.page === p);
  for (const s of document.querySelectorAll('.page')) s.classList.add('hidden');
  const el = $('#p-' + p); el.classList.remove('hidden'); el.innerHTML = '';
  PAGES[p](el); history.replaceState(null, '', '#' + p);
}
for (const a of document.querySelectorAll('nav a[data-page]')) a.onclick = () => go(a.dataset.page);
async function start() {
  const me = await api('/api/me');
  $('#loginhost').textContent = me.host; $('#hostname').textContent = me.host; document.title = me.host + ' · panel';
  if (!me.auth) return showLogin();
  $('#login').classList.add('hidden'); $('#app').classList.remove('hidden');
  go(PAGES[location.hash.slice(1)] ? location.hash.slice(1) : 'home');
}

// ---------- Home
function pHome(el) {
  const head = h('div', {class: 'head'}, h('img', {src: '/logo.png', alt: ''}), h('div', {}, h('div', {class: 't', id: 'hclock'}, ''), h('div', {class: 'dim', id: 'hdate'})));
  const chips = h('div', {class: 'chips'});
  const stats = h('div', {class: 'grid g4'});
  const extra = h('div', {class: 'grid g2', style: 'margin-top:14px'});
  const apps = h('div', {class: 'grid g3'});
  el.append(head, chips, h('div', {class: 'sec'}, 'System'), stats, extra, h('div', {class: 'sec'}, 'Apps'), apps,
    h('p', {class: 'note', style: 'margin-top:20px'}, 'Terminal: ssh gta2@' + HOST + '   ·   Status page: http://' + HOST + ':8088'));
  every(3000, async () => {
    const s = await api('/api/stats').catch(() => null); if (!s) return;
    $('#hclock').textContent = s.time; $('#hdate').textContent = s.date + ' · ' + s.host;
    const up = s.uptime, upt = `${Math.floor(up / 86400)}d ${Math.floor(up % 86400 / 3600)}h ${Math.floor(up % 3600 / 60)}m`;
    chips.replaceChildren(...s.ips.map(i => h('span', {class: 'chip'}, i.if + ' ' + i.ip)), h('span', {class: 'chip'}, 'up ' + upt), h('span', {class: 'chip'}, 'kernel ' + s.kernel));
    const used = s.mem.total - s.mem.avail;
    const t = s.temps.length ? Math.max(...s.temps.map(x => x.c)) : null;
    const b = s.battery, cap = +(b.capacity || 0), chg = /charg/i.test(b.status || '') && !/dis|not/i.test(b.status || '');
    const stat = (k, v, sub, frac, col) => h('div', {class: 'card stat'}, h('div', {class: 'k'}, k), h('div', {class: 'v'}, v), frac != null ? bar(frac, col) : null, h('div', {class: 's', style: 'margin-top:6px'}, sub || ''));
    stats.replaceChildren(
      stat('CPU', s.cpu + '%', s.mhz.length ? s.mhz.join(' ') + ' MHz' : s.cores + ' cores · load ' + s.load.join(' '), s.cpu / 100, TILE[0]),
      stat('MEMORY', used + ' MB', 'of ' + s.mem.total + ' MB · ' + s.mem.avail + ' MB free', used / s.mem.total, TILE[1]),
      stat('TEMPERATURE', t == null ? '–' : t + ' °C', s.temps.map(x => x.name + ' ' + x.c).join(' · '), t == null ? 0 : t / 100, TILE[4]),
      stat('BATTERY', (b.capacity || '?') + '%' + (chg ? ' ⚡' : ''), (b.status || '') + (b.source ? ' · ' + b.source : ''), cap / 100, cap > 20 ? 'var(--ok)' : 'var(--bad)'));
    extra.replaceChildren(card('Storage', null, ...s.disks.map(d => h('div', {style: 'margin:8px 0'}, h('div', {class: 'row sp'}, h('span', {}, d.path), h('span', {class: 'dim'}, fmtB(d.total - d.free) + ' / ' + fmtB(d.total))), bar((d.total - d.free) / d.total)))));
  });
  every(10000, async () => {
    const c = await api('/api/containers').catch(() => null); if (!c) return;
    if (!c.ok) return apps.replaceChildren(card('Docker is not running', c.error, h('button', {class: 'btn acc', onclick: () => act('/api/ctl', {area: 'docker', action: 'service', args: ['start']}).then(() => go('home'))}, 'Start Docker')));
    if (!c.items.length) return apps.replaceChildren(card('No apps yet', 'Install some from the App store.', h('button', {class: 'btn acc', onclick: () => go('store')}, 'Open App store')));
    apps.replaceChildren(...c.items.map(appTile));
  });
}
function appTile(c) {
  const on = c.state === 'running';
  const links = on ? c.ports.map(p => { const s = c.web === 'https' || [443, 8443, 9443].includes(p) ? 'https' : 'http'; return h('a', {href: `${s}://${HOST}:${p}${c.path || ''}`, target: '_blank', rel: 'noopener'}, `:${p} ↗`); }) : [];
  const doit = a => act('/api/docker', {action: a, name: c.name}).then(() => go('home'));
  return h('div', {class: 'card tile'},
    h('div', {class: 'top'}, h('div', {class: 'ico', style: 'background:' + colorOf(c.name)}, initials(c.name)),
      h('div', {style: 'min-width:0'}, h('div', {class: 'name'}, c.name), h('div', {class: 'sub'}, h('span', {class: 'dot' + (on ? ' on' : '')}), c.status))),
    h('div', {class: 'links'}, links.length ? links : h('span', {class: 'faint', style: 'font-size:13px'}, on ? 'no web port' : 'stopped')),
    h('div', {class: 'row'}, on ? h('button', {class: 'btn sm', onclick: () => doit('stop')}, 'Stop') : h('button', {class: 'btn sm acc', onclick: () => doit('start')}, 'Start'),
      h('button', {class: 'btn sm', onclick: () => doit('restart')}, 'Restart'),
      h('button', {class: 'btn sm', onclick: () => showLogs(c.name)}, 'Logs')));
}
async function showLogs(name) {
  const pre = h('pre', {class: 'log'}, 'loading…');
  modal('Logs · ' + name, pre);
  const d = await api('/api/logs?name=' + encodeURIComponent(name)).catch(e => ({log: e.message}));
  pre.textContent = d.log || '(empty)'; pre.scrollTop = pre.scrollHeight;
}

// ---------- App store
function pStore(el) {
  const info = h('p', {class: 'dim'}, 'One tap installs a ready-to-use app in Docker. Data lives in /userdata/gta2srv/apps/<app>.');
  const grid = h('div', {class: 'grid g3'});
  el.append(h('h2', {}, 'App store'), info, grid);
  let running = {};
  const load = async () => {
    const [d, jobs] = await Promise.all([api('/api/store'), api('/api/jobs')]).catch(() => [null, null]); if (!d) return;
    running = jobs;
    info.replaceChildren('One tap installs a ready-to-use app in Docker. Free memory now: ',
      h('b', {style: d.mem_avail < 500 ? 'color:var(--bad)' : ''}, d.mem_avail + ' MB'), ' of ' + d.mem_total + ' MB.');
    const cats = {};
    for (const a of d.apps) (cats[a.cat] = cats[a.cat] || []).push(a);
    grid.replaceChildren(...d.apps.map(a => storeCard(a, d, jobs[a.id], load)));
  };
  every(4000, () => { if (Object.values(running || {}).some(j => j.state === 'running') || !grid.children.length) load(); });
}
function storeCard(a, d, job, reload) {
  const busy = job && job.state === 'running';
  const low = a.ram > d.mem_avail - 250;
  const btn = a.installed
    ? h('button', {class: 'btn sm', disabled: busy, onclick: () => { const cb = h('input', {type: 'checkbox'}); modal('Remove ' + a.name + '?', h('div', {}, h('p', {}, 'The container and its image are removed.'), h('label', {class: 'row'}, cb, 'Also delete its data (' + '/userdata/gta2srv/apps/' + a.id + ')')), [['Cancel', '', null], ['Remove', 'bad', () => act('/api/store/uninstall', {id: a.id, delete: cb.checked}).then(reload)]]); }}, 'Remove')
    : h('button', {class: 'btn sm acc', disabled: busy, onclick: () => {
        const go_ = () => act('/api/store/install', {id: a.id}).then(reload);
        if (a.heavy || low) confirmDo(`${a.name} needs about ${a.ram} MB of RAM${low ? ' and only ' + d.mem_avail + ' MB is free now' : ''}. Install anyway?`, go_, 'Install', 'acc'); else go_();
      }}, 'Install');
  const link = a.installed && a.state === 'running' && a.web_port ? h('a', {href: `${a.scheme || 'http'}://${HOST}:${a.web_port}${a.web_path || ''}`, target: '_blank', rel: 'noopener', class: 'btn sm', style: 'text-decoration:none'}, 'Open ↗') : null;
  return h('div', {class: 'card tile'},
    h('div', {class: 'top'}, h('div', {class: 'ico', style: 'background:' + colorOf(a.id)}, initials(a.name)),
      h('div', {style: 'min-width:0'}, h('div', {class: 'name'}, a.name, a.heavy ? h('span', {class: 'badge warn'}, 'heavy') : null, a.installed ? h('span', {class: 'badge ok'}, a.state || 'installed') : null),
        h('div', {class: 'sub'}, a.cat + ' · ~' + a.ram + ' MB RAM'))),
    h('div', {class: 'dim', style: 'font-size:13px'}, a.desc),
    a.note ? h('div', {class: 'note'}, a.note) : null,
    job ? h('div', {class: 'note'}, busy ? h('span', {class: 'spin'}) : null, ' ', job.state === 'failed' ? h('span', {style: 'color:var(--bad)'}, 'failed: ' + job.log.slice(-160)) : job.state) : null,
    h('div', {class: 'row'}, btn, link));
}

// ---------- Files
function pFiles(el) {
  let path = 'share';
  const crumbs = h('div', {class: 'crumbs'});
  const roots = h('div', {class: 'seg', style: 'max-width:320px'});
  const tbl = h('table', {class: 'files'});
  const file = h('input', {type: 'file', multiple: true, class: 'hidden'});
  const drop = h('div', {class: 'drop'}, 'Drop files here or ', h('a', {href: '#', onclick: e => { e.preventDefault(); file.click(); }}, 'choose files'), file);
  const progs = h('div');
  el.append(h('div', {class: 'row sp'}, h('h2', {style: 'margin:0'}, 'Files'), roots),
    h('p', {class: 'note'}, 'Same folder as the SMB share \\\\' + HOST + '\\share'),
    card(null, null, h('div', {class: 'row sp'}, crumbs, h('button', {class: 'btn sm', onclick: mkdir}, '+ Folder')), drop, progs, tbl));
  file.onchange = () => upload([...file.files]);
  drop.ondragover = e => { e.preventDefault(); drop.classList.add('over'); };
  drop.ondragleave = () => drop.classList.remove('over');
  drop.ondrop = e => { e.preventDefault(); drop.classList.remove('over'); upload([...e.dataTransfer.files]); };
  async function load(p) {
    const d = await api('/api/files?path=' + encodeURIComponent(p)).catch(e => ({error: e.message}));
    if (d.error) return toast('error: ' + d.error, true);
    path = d.path;
    roots.replaceChildren(...d.roots.map(r => h('button', {class: path.split('/')[0] === r.key ? 'on' : '', disabled: !r.mounted, title: r.mounted ? '' : 'not inserted', onclick: () => load(r.key)}, r.key === 'share' ? 'Share' : 'SD card' + (r.mounted ? '' : ' (none)'))));
    const parts = path.split('/');
    crumbs.replaceChildren(...parts.flatMap((p, i) => [...(i ? [h('span', {class: 'faint'}, '/')] : []), h('a', {onclick: () => load(parts.slice(0, i + 1).join('/'))}, i ? p : (p === 'share' ? 'Share' : 'SD card'))]));
    tbl.replaceChildren(...(parts.length > 1 ? [h('tr', {}, h('td', {class: 'n', onclick: () => load(parts.slice(0, -1).join('/'))}, '⤴  ..'), h('td'), h('td'), h('td'))] : []),
      ...d.items.map(it => {
        const ip = path + '/' + it.name;
        return h('tr', {},
          h('td', {class: 'n', onclick: () => it.dir ? load(ip) : location.assign('/api/download?path=' + encodeURIComponent(ip))}, (it.dir ? '▸  ' : '    ') + it.name),
          h('td', {class: 'r'}, it.dir ? '' : fmtB(it.size)),
          h('td', {class: 'r'}, new Date(it.mtime * 1000).toLocaleString()),
          h('td', {class: 'r'}, h('button', {class: 'btn sm', onclick: () => rename(ip, it.name)}, 'Rename'), ' ',
            h('button', {class: 'btn sm bad', onclick: () => confirmDo(`Delete "${it.name}"${it.dir ? ' and everything in it' : ''}?`, () => act('/api/files/op', {op: 'delete', path: ip}).then(() => load(path)), 'Delete')}, 'Delete')));
      }));
    if (!d.items.length) tbl.append(h('tr', {}, h('td', {class: 'faint', colspan: 4}, '(empty folder)')));
  }
  function mkdir() {
    const i = h('input', {type: 'text', placeholder: 'Folder name'});
    modal('New folder', i, [['Cancel', '', null], ['Create', 'acc', () => act('/api/files/op', {op: 'mkdir', path, name: i.value.trim()}).then(() => load(path))]]);
    setTimeout(() => i.focus(), 50);
  }
  function rename(ip, name) {
    const i = h('input', {type: 'text', value: name});
    modal('Rename', i, [['Cancel', '', null], ['Rename', 'acc', () => act('/api/files/op', {op: 'rename', path: ip, to: i.value.trim()}).then(() => load(path))]]);
  }
  function upload(files) {
    let left = files.length;
    for (const f of files) {
      const p = h('i', {style: 'width:0'}), row = h('div', {class: 'note'}, f.name + ' (' + fmtB(f.size) + ')', h('div', {class: 'prog'}, p));
      progs.append(row);
      const x = new XMLHttpRequest();
      x.open('POST', '/api/upload?path=' + encodeURIComponent(path) + '&name=' + encodeURIComponent(f.name));
      x.setRequestHeader('X-Gta2', '1');
      x.upload.onprogress = e => { if (e.lengthComputable) p.style.width = (100 * e.loaded / e.total) + '%'; };
      x.onloadend = () => { row.remove(); if (x.status !== 200) toast('error: upload of ' + f.name + ' failed (' + x.status + ')', true); if (--left === 0) { toast('upload finished'); load(path); } };
      x.send(f);
    }
  }
  load(path);
}

// ---------- Screen
let scrRun = false, scrTimer = null;
function scrStop() { scrRun = false; clearTimeout(scrTimer); }
function pScreen(el) {
  const img = h('img', {id: 'scr', alt: 'tablet screen'});
  let root = [800, 1280], url = null;
  const fps = h('span', {class: 'dim'});
  const txt = h('input', {type: 'text', placeholder: 'Type text on the tablet…'});
  const key = k => api('/api/input', {type: 'key', key: k}).catch(e => toast('error: ' + e.message, true));
  el.append(h('h2', {}, 'Screen'), h('div', {class: 'screenwrap'}, img,
    h('div', {class: 'scrside'},
      card('Remote control', 'Click or tap the picture to tap the tablet.',
        h('div', {class: 'row'}, h('button', {class: 'btn acc', onclick: () => key('home')}, '⌂ Home'), h('button', {class: 'btn', onclick: () => key('back')}, '‹ Back'),
          h('button', {class: 'btn', onclick: () => key('keyboard')}, '⌨ Keyboard'))),
      card('Keyboard', null, txt, h('div', {class: 'row', style: 'margin-top:8px'},
        h('button', {class: 'btn acc', onclick: () => { if (txt.value) api('/api/input', {type: 'text', text: txt.value}).then(() => { txt.value = ''; }); }}, 'Send text'),
        ...['BackSpace', 'Tab', 'Return'].map(k => h('button', {class: 'btn sm', onclick: () => key(k)}, {BackSpace: '⌫', Tab: 'Tab', Return: 'Enter ⏎'}[k])),
        ...['Left', 'Up', 'Down', 'Right'].map(k => h('button', {class: 'btn sm', onclick: () => key(k)}, {Left: '←', Up: '↑', Down: '↓', Right: '→'}[k])))),
      h('div', {}, fps))));
  txt.onkeydown = e => { if (e.key === 'Enter' && txt.value) { api('/api/input', {type: 'text', text: txt.value}).then(() => key('Return')); txt.value = ''; } };
  img.onclick = e => {
    const r = img.getBoundingClientRect();
    const x = Math.round((e.clientX - r.left) / r.width * root[0]), y = Math.round((e.clientY - r.top) / r.height * root[1]);
    api('/api/input', {type: 'tap', x, y}).then(() => { clearTimeout(scrTimer); scrTimer = setTimeout(frame, 250); }).catch(err => toast('error: ' + err.message, true));
  };
  scrRun = true;
  let n = 0, t0 = performance.now();
  async function frame() {
    if (!scrRun) return;
    if (document.hidden) { scrTimer = setTimeout(frame, 1000); return; }
    try {
      const r = await fetch('/api/screen?q=65', {credentials: 'same-origin'});
      if (r.status === 401) return showLogin();
      if (!r.ok) throw new Error(await r.text());
      const sz = (r.headers.get('X-Root-Size') || '800x1280').split('x').map(Number);
      root = sz;
      const b = await r.blob();
      if (url) URL.revokeObjectURL(url);
      url = URL.createObjectURL(b); img.src = url;
      n++; const dt = (performance.now() - t0) / 1000; if (dt > 3) { fps.textContent = (n / dt).toFixed(1) + ' fps · ' + Math.round(b.size / 1024) + ' KB/frame'; n = 0; t0 = performance.now(); }
    } catch (e) { fps.textContent = 'screen unavailable: ' + e.message; }
    if (scrRun) scrTimer = setTimeout(frame, 450);
  }
  frame();
}

// ---------- Settings
const ctl = (area, action, ...args) => api('/api/ctl', {area, action, args});
const ctlSay = (area, action, ...args) => act('/api/ctl', {area, action, args});
const kv = s => Object.fromEntries((s || '').split(/\s+/).filter(x => x.includes('=')).map(x => [x.slice(0, x.indexOf('=')), x.slice(x.indexOf('=') + 1)]));
function pSettings(el) {
  const grid = h('div', {class: 'grid g2'});
  el.append(h('h2', {}, 'Settings'), grid);
  const S = [sWifi, sDisplay, sSaver, sBattery, sCpu, sBt, sShare, sDocker, sSsh, sVpn, sHotspot, sTime, sDevice, sUpdate, sPower];
  for (const f of S) { const c = h('div', {class: 'card'}); grid.append(c); f(c).catch(e => c.append(h('p', {class: 'err'}, e.message))); }
}
async function sWifi(c) {
  const list = h('div', {class: 'list'}), pw = h('input', {type: 'password', placeholder: 'Password'});
  let sel = null;
  const radio = h('span');
  c.append(h('h3', {}, 'Wi-Fi'), list, h('div', {class: 'row', style: 'margin-top:10px'}, pw),
    h('div', {class: 'row', style: 'margin-top:10px'},
      h('button', {class: 'btn', onclick: () => load(true)}, 'Scan'),
      h('button', {class: 'btn acc', onclick: () => sel ? act('/api/wifi', {op: 'connect', ssid: sel, password: pw.value}).then(() => load()) : toast('select a network', true)}, 'Connect'),
      h('button', {class: 'btn', onclick: () => sel && confirmDo('Forget ' + sel + '?', () => act('/api/wifi', {op: 'forget', ssid: sel}).then(() => load()), 'Forget')}, 'Forget')),
    line('Wi-Fi radio', 'If you are connected over Wi-Fi, turning it off disconnects this page', radio));
  async function load(rescan) {
    list.replaceChildren(h('div', {}, h('span', {class: 'spin'}), ' scanning…'));
    const d = await api('/api/wifi' + (rescan ? '?rescan=1' : ''));
    radio.replaceChildren(sw(d.radio, v => confirmDo('Turn Wi-Fi ' + (v ? 'on' : 'off') + '?', () => act('/api/wifi', {op: 'radio', state: v ? 'on' : 'off'}), 'Yes', 'acc')));
    list.replaceChildren(...d.nets.map(n => {
      const r = h('div', {onclick: () => { for (const x of list.children) x.classList.remove('sel'); r.classList.add('sel'); sel = n.ssid; }},
        h('span', {}, (n.active ? '● ' : '') + n.ssid), h('span', {class: 'dim'}, '▂▄▆█'.slice(0, Math.max(1, Math.min(4, Math.floor(n.signal / 25) + 1))) + (n.secure ? ' ⚷' : '')));
      return r;
    }));
    if (!d.nets.length) list.replaceChildren(h('div', {}, 'no networks found'));
  }
  load();
}
async function sDisplay(c) {
  const d = await api('/api/display');
  const rng = h('input', {type: 'range', min: Math.max(1, Math.floor(d.max / 50)), max: d.max, value: d.brightness});
  let t; rng.oninput = () => { clearTimeout(t); t = setTimeout(() => api('/api/brightness', {value: +rng.value}), 120); };
  const sto = h('input', {type: 'number', min: 0, max: 120, value: d.screensaver.screen_off || 0, style: 'width:90px'});
  sto.onchange = () => act('/api/prefs', {screensaver: {screen_off: +sto.value}});
  c.append(h('h3', {}, 'Display'), line('Brightness', null, h('div', {style: 'width:55%'}, rng)),
    h('div', {class: 'line', style: 'display:block'}, h('div', {class: 'l', style: 'margin-bottom:8px'}, 'Rotation', h('small', {}, 'Restarts the tablet interface')),
      seg([['portrait', 'Portrait'], ['portrait-flip', 'Upside'], ['landscape', 'Landscape'], ['landscape-flip', 'Land. flip']], d.rotation, v => ctlSay('screen', 'rotation', v))),
    line('Screen timeout (min)', '0 = never; used when the screensaver is off', sto),
    h('div', {class: 'line', style: 'display:block'}, h('div', {class: 'l', style: 'margin-bottom:8px'}, 'On-screen keyboard size'),
      seg([['S', 'Small'], ['M', 'Medium'], ['L', 'Large']], d.osk_size, v => act('/api/prefs', {osk_size: v}))));
}
async function sSaver(c) {
  const d = await api('/api/display'), s = d.screensaver;
  const save = (k, v) => act('/api/prefs', {screensaver: {[k]: v}});
  const num = (k, lo, hi) => { const i = h('input', {type: 'number', min: lo, max: hi, value: s[k], style: 'width:90px'}); i.onchange = () => save(k, +i.value); return i; };
  const imgsel = h('select', {}, h('option', {value: ''}, '(first image)'), ...d.images.map(n => h('option', {value: n, selected: s.image.endsWith('/' + n)}, n)));
  imgsel.onchange = () => save('image', imgsel.value);
  c.append(h('h3', {}, 'Screensaver'), line('Enabled', null, sw(s.enabled, v => save('enabled', v))),
    h('div', {class: 'line', style: 'display:block'}, seg([['image', 'One image'], ['slideshow', 'Slideshow'], ['clock', 'Clock only']], s.mode, v => save('mode', v))),
    line('Image', 'Images live in the share\'s Screensaver folder', h('div', {style: 'width:50%'}, imgsel)),
    line('Clock over the image', null, sw(s.clock, v => save('clock', v))),
    line('Start after (min)', null, num('after', 1, 120)), line('Slideshow every (s)', null, num('interval', 3, 600)),
    line('Then screen off after (min)', '0 = never', num('off_after', 0, 600)),
    h('div', {class: 'row', style: 'margin-top:8px'}, h('button', {class: 'btn acc', onclick: () => act('/api/prefs', {preview: true}, 'showing it on the tablet')}, 'Preview on tablet')));
}
async function sBattery(c) {
  const [s, st] = await Promise.all([api('/api/stats'), ctl('battery', 'status')]);
  const b = s.battery, v = +(b.voltage_now || 0), cur_ = +(b.current_now || 0);
  const lim = h('input', {type: 'number', min: 50, max: 100, step: 5, value: (st.msg.match(/limit (\d+)/) || [0, 100])[1], style: 'width:90px'});
  lim.onchange = () => ctlSay('battery', 'limit', String(lim.value));
  c.append(h('h3', {}, 'Battery & charging'), h('div', {class: 'row sp'}, h('b', {style: 'font-size:22px'}, (b.capacity || '?') + '%'), h('span', {class: 'dim'}, (b.status || '') + (b.source ? ' · ' + b.source : ''))),
    bar((+b.capacity || 0) / 100, 'var(--ok)'),
    h('p', {class: 'dim mono'}, `${(v > 10000 ? v / 1e6 : v / 1000).toFixed(2)} V · ${Math.round(Math.abs(cur_) > 10000 ? cur_ / 1000 : cur_)} mA · ${(+(b.temp || 0) / 10).toFixed(1)} °C · health ${b.health || '?'}`),
    line('Charge limit (%)', 'Stop at this level, resume 5% below. 100 = normal. ' + st.msg, lim));
}
async function sCpu(c) {
  const st = kv((await ctl('cpu', 'status')).msg);
  const trip = h('input', {type: 'number', min: 60, max: 95, step: 5, value: st.trip || 90, style: 'width:90px'});
  trip.onchange = () => ctlSay('cpu', 'trip', String(trip.value));
  c.append(h('h3', {}, 'CPU & thermal'),
    st.gov && st.gov !== 'none'
      ? h('div', {class: 'line', style: 'display:block'}, h('div', {class: 'l', style: 'margin-bottom:8px'}, 'Speed profile', h('small', {}, 'max ' + Math.round((+st.top || 0) / 1000) + ' MHz')),
        seg([['powersave', 'Saver'], ['schedutil', 'Balanced'], ['performance', 'Max']], st.gov, v => ctlSay('cpu', 'gov', v)))
      : h('p', {class: 'note'}, 'This kernel runs the CPU at a fixed clock (no frequency scaling).'),
    line('Throttle at (°C)', 'Above this the clock steps down', trip));
}
async function sBt(c) {
  const out = h('pre', {class: 'mono dim', style: 'white-space:pre-wrap;margin:0'});
  const list = h('div', {class: 'list'});
  let sel = null;
  const refresh = async () => { const s = await ctl('bt', 'status'); out.textContent = s.msg; return s.msg; };
  const st = await refresh();
  c.append(h('h3', {}, 'Bluetooth'), line('Bluetooth', null, sw(/Powered: yes/.test(st), v => ctlSay('bt', 'power', v ? 'on' : 'off').then(refresh))), out,
    h('div', {class: 'row', style: 'margin:10px 0'},
      h('button', {class: 'btn', onclick: async () => { list.replaceChildren(h('div', {}, h('span', {class: 'spin'}), ' scanning 10 s…')); const d = await ctl('bt', 'scan');
        const devs = d.msg.split('\n').filter(l => l.startsWith('Device ')).map(l => l.split(' '));
        list.replaceChildren(...devs.map(([, mac, ...n]) => { const r = h('div', {onclick: () => { for (const x of list.children) x.classList.remove('sel'); r.classList.add('sel'); sel = mac; }}, h('span', {}, n.join(' ') || mac), h('span', {class: 'dim mono'}, mac)); return r; })); }}, 'Scan'),
      h('button', {class: 'btn acc', onclick: () => sel && ctlSay('bt', 'pair', sel).then(refresh)}, 'Pair'),
      h('button', {class: 'btn', onclick: () => sel && ctlSay('bt', 'remove', sel).then(refresh)}, 'Remove')), list);
}
async function sShare(c) {
  const s = await api('/api/share');
  const pw = h('input', {type: 'password', placeholder: 'New share password'});
  c.append(h('h3', {}, 'File sharing'), h('p', {class: 'note mono'}, `\\\\${HOST}\\share   ·   sftp://gta2@${HOST}`),
    line('Windows / Mac share (SMB)', null, sw(s.smb === 'on', v => act('/api/share', {action: 'smb', value: v ? 'on' : 'off'}))),
    line('Guest access', 'No password; Windows 11 blocks guest shares by default', sw(s.guest === 'on', v => act('/api/share', {action: 'guest', value: v ? 'on' : 'off'}))),
    h('div', {class: 'row', style: 'margin-top:8px;flex-wrap:nowrap'}, pw, h('button', {class: 'btn acc', onclick: () => act('/api/share', {action: 'passwd', value: pw.value}).then(() => { pw.value = ''; })}, 'Set')));
}
async function sDocker(c) {
  c.append(h('h3', {}, 'Docker'), h('p', {class: 'note'}, 'Stopping Docker frees ~100 MB of RAM. Containers are managed on the Home page.'),
    h('div', {class: 'row'}, h('button', {class: 'btn acc', onclick: () => ctlSay('docker', 'service', 'start')}, 'Start Docker'),
      h('button', {class: 'btn', onclick: () => confirmDo('Stop Docker and all its apps?', () => ctlSay('docker', 'service', 'stop'), 'Stop')}, 'Stop Docker'),
      h('button', {class: 'btn', onclick: () => confirmDo('Remove stopped containers and unused images?', () => ctlSay('docker', 'prune'), 'Clean up')}, 'Clean up')),
    h('p', {class: 'note'}, 'Portainer (full Docker UI): ', h('a', {href: `https://${HOST}:9443`, target: '_blank', rel: 'noopener'}, `https://${HOST}:9443`)));
}
async function sSsh(c) {
  const st = kv((await ctl('ssh', 'status')).msg);
  c.append(h('h3', {}, 'SSH access'), h('p', {class: 'note mono'}, 'ssh gta2@' + HOST + '  ·  ' + (st.keys || 0) + ' key(s)'),
    line('SSH server', 'Off also blocks remote fixes over USB', sw(st.ssh === 'active', v => v ? ctlSay('ssh', 'on') : confirmDo('Turn SSH off?', () => ctlSay('ssh', 'off'), 'Turn off'))),
    line('Password login', 'Off = keys only (safer)', sw(st.password === 'on', v => ctlSay('ssh', 'password', v ? 'on' : 'off'))),
    line('Add a key', 'Copy your public key into the share as authorized_keys.txt first', h('button', {class: 'btn sm', onclick: () => ctlSay('ssh', 'addkey')}, 'Add key')));
}
async function sVpn(c) {
  const out = h('pre', {class: 'mono dim', style: 'white-space:pre-wrap;margin:0 0 8px'});
  const refresh = async () => { out.textContent = (await ctl('vpn', 'status')).msg.replace(' tailscale=', '\ntailscale='); };
  await refresh();
  const b = (t, a, cls) => h('button', {class: 'btn sm ' + (cls || ''), onclick: () => { toast('working…'); ctl('vpn', a).then(d => { modal(t, h('pre', {class: 'log'}, d.msg)); refresh(); }); }}, t);
  c.append(h('h3', {}, 'VPN'), out,
    line('Tailscale', 'Sign in shows a login link', h('div', {class: 'row'}, b('Install', 'ts-install'), b('Sign in / up', 'ts-up', 'acc'), b('Down', 'ts-down'))),
    line('WireGuard', 'Put wg0.conf in the share first', h('div', {class: 'row'}, b('Install', 'wg-install'), b('Up', 'wg-up', 'acc'), b('Down', 'wg-down'))));
}
async function sHotspot(c) {
  const st = kv((await ctl('hotspot', 'status')).msg);
  const ss = h('input', {type: 'text', placeholder: 'Hotspot name', value: HOST + '-ap'}), pw = h('input', {type: 'password', placeholder: 'Password (8+ characters)'});
  c.append(h('h3', {}, 'Hotspot & USB tether'), h('div', {class: 'row', style: 'flex-wrap:nowrap'}, ss, pw),
    h('div', {class: 'row', style: 'margin:8px 0'}, h('button', {class: 'btn acc', onclick: () => confirmDo('The tablet leaves your Wi-Fi to become a hotspot. This page will disconnect if you use it over Wi-Fi.', () => ctlSay('hotspot', 'on', ss.value, pw.value), 'Start', 'acc')}, 'Start hotspot'),
      h('button', {class: 'btn', onclick: () => ctlSay('hotspot', 'off')}, 'Stop')),
    line('USB tether', 'A laptop on the USB cable gets internet through the tablet', sw(st.tether === 'on', v => ctlSay('hotspot', v ? 'tether-on' : 'tether-off'))));
}
async function sTime(c) {
  const st = kv((await ctl('time', 'status')).msg);
  const sel = h('select', {}, h('option', {}, st.tz || 'UTC'));
  c.append(h('h3', {}, 'Date & time'), h('p', {class: 'dim mono'}, (st.now || '') + '  ·  ' + (st.tz || '')),
    line('Network time (NTP)', null, sw(st.ntp === 'yes', v => ctlSay('time', 'ntp', v ? 'true' : 'false'))), line('Time zone', null, h('div', {style: 'width:60%'}, sel)));
  ctl('time', 'zones').then(d => { sel.replaceChildren(...d.msg.split('\n').filter(z => z.includes('/') || z === 'UTC').map(z => h('option', {value: z, selected: z === st.tz}, z))); });
  sel.onchange = () => ctlSay('time', 'tz', sel.value);
}
async function sDevice(c) {
  const hn = h('input', {type: 'text', value: HOST.match(/^\d/) ? '' : HOST.replace(/\.local$/, ''), placeholder: 'device name'});
  const p1 = h('input', {type: 'password', placeholder: 'New password'}), p2 = h('input', {type: 'password', placeholder: 'Repeat'});
  c.append(h('h3', {}, 'Device'), h('div', {class: 'row', style: 'flex-wrap:nowrap'}, hn, h('button', {class: 'btn acc', onclick: () => ctlSay('device', 'hostname', hn.value.trim())}, 'Rename')),
    h('p', {class: 'note'}, 'Login password of user gta2 (SSH, this panel, sudo). Default gta2: change it.'),
    h('div', {class: 'row', style: 'flex-wrap:nowrap'}, p1, p2, h('button', {class: 'btn acc', onclick: () => p1.value !== p2.value ? toast('the passwords differ', true) : ctlSay('device', 'passwd', p1.value).then(() => { p1.value = p2.value = ''; })}, 'Change')));
}
async function sUpdate(c) {
  c.append(h('h3', {}, 'Updates & cleanup'), h('p', {class: 'note'}, 'Ubuntu security and bug-fix updates (needs internet).'),
    h('div', {class: 'row'}, h('button', {class: 'btn', onclick: () => { toast('checking…'); ctlSay('update', 'check'); }}, 'Check'),
      h('button', {class: 'btn acc', onclick: () => confirmDo('Install all updates now? Keep the tablet plugged in.', () => { toast('updating, this can take a while…'); ctlSay('update', 'run'); }, 'Update', 'acc')}, 'Install updates'),
      h('button', {class: 'btn', onclick: () => ctlSay('update', 'clean')}, 'Free space')));
}
async function sPower(c) {
  const p = (t, m, cls) => h('button', {class: 'btn ' + cls, style: 'flex:1;padding:18px', onclick: () => confirmDo(t + ' the tablet?', () => act('/api/power', {mode: m}), t)}, t);
  c.append(h('h3', {}, 'Power'), h('div', {class: 'row'}, p('Reboot', 'system', 'acc'), p('Shut down', 'poweroff', 'bad')),
    h('div', {class: 'row', style: 'margin-top:10px'}, p('Recovery (TWRP)', 'recovery', ''), p('Download mode', 'download', '')));
}

start().catch(() => showLogin());
