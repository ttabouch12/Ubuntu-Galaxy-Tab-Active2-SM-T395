/* gta2 router cards (add-on). Fetches /api router block, renders 4 cards in the Internet section.
   Uses page helper card(k,v,s,pct,col) or st2(k,v,sub,col,frac) when global, else own markup. */
(function () {
  var ID = 'gta2-router-cards';
  var hist = [];
  function api() {
    var h = location.port === '8088' ? '' : 'http://' + location.hostname + ':8088';
    return fetch(h + '/api', { cache: 'no-store' }).then(function (r) { return r.json(); });
  }
  function dur(s) {
    if (s == null) return '\u2013';
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    return d ? d + 'd ' + h + 'h' : h ? h + 'h ' + m + 'm' : m + 'm';
  }
  function gb(b) { if (b == null) return '\u2013'; return b >= 1e12 ? (b / 1e12).toFixed(2) + ' TB' : b >= 1e9 ? (b / 1e9).toFixed(1) + ' GB' : (b / 1e6).toFixed(0) + ' MB'; }
  function f(x) { return x == null ? '\u2013' : (x >= 100 ? x.toFixed(0) : x.toFixed(1)); }
  function spark(col) {
    if (hist.length < 2) return '';
    var max = Math.max.apply(null, hist.concat([1])), w = 120, h = 24;
    var pts = hist.map(function (v, i) { return (i * w / (hist.length - 1)).toFixed(1) + ',' + (h - v / max * h).toFixed(1); }).join(' ');
    return '<svg width="' + w + '" height="' + h + '" style="display:block;margin-top:4px"><polyline fill="none" stroke="' + col + '" stroke-width="1.5" points="' + pts + '"/></svg>';
  }
  function own(k, v, s, col, frac) {
    return '<div style="background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);border-radius:12px;padding:10px 12px;min-width:150px;flex:1">' +
      '<div style="font-size:12px;opacity:.7">' + k + '</div>' +
      '<div style="font-size:20px;font-weight:600;color:' + col + '">' + v + '</div>' +
      '<div style="font-size:11px;opacity:.6">' + (s || '') + '</div>' +
      (frac != null ? '<div style="height:3px;background:rgba(255,255,255,.08);border-radius:2px;margin-top:6px"><div style="height:3px;width:' + Math.min(100, frac * 100) + '%;background:' + col + ';border-radius:2px"></div></div>' : '') +
      '</div>';
  }
  function mk(k, v, s, col, frac) {
    try {
      if (typeof card === 'function') return card(k, v, s, frac == null ? null : frac * 100, col);
      if (typeof st2 === 'function') return st2(k, v, s, col, frac);
    } catch (e) {}
    return own(k, v, s, col, frac);
  }
  function anchor() {
    var els = document.querySelectorAll('h1,h2,h3,h4,.sec,.section-title,.title,summary,div,span');
    for (var i = 0; i < els.length; i++) {
      var e = els[i];
      if (e.children.length === 0 && /^\s*internet\s*$/i.test(e.textContent)) return e;
    }
    return null;
  }
  function place() {
    var box = document.getElementById(ID);
    if (box && document.body.contains(box)) return box;
    box = document.createElement('div');
    box.id = ID;
    box.style.cssText = 'display:flex;flex-wrap:wrap;gap:8px;margin:8px 0';
    var a = anchor();
    if (a) {
      var sib = a.nextElementSibling;
      (sib && sib.parentNode ? sib.parentNode.insertBefore(box, sib.nextSibling) : a.parentNode.insertBefore(box, a.nextSibling));
    } else document.body.appendChild(box);
    return box;
  }
  function render(r) {
    var box = place();
    if (!r) { box.innerHTML = mk('Router', 'no data', 'gta2-router not running', '#8e9aaf'); return; }
    if (!r.ok) { box.innerHTML = mk('Router', 'error', r.error || '', '#f87171'); return; }
    var stale = Date.now() / 1000 - (r.t || 0) > 90 ? ' (stale)' : '';
    if (r.rx_mbit != null) { hist.push(r.rx_mbit); if (hist.length > 60) hist.shift(); }
    var ld = r.line_down, lu = r.line_up, D = '\u2193 ', U = ' / \u2191 ';
    var lat = r.ping_wan == null ? '\u2013' : r.ping_wan.toFixed(1) + ' ms';
    var latCol = r.ping_wan == null ? '#f87171' : r.ping_wan < 30 ? '#34d399' : r.ping_wan < 80 ? '#fbbf24' : '#f87171';
    box.innerHTML =
      mk('Home traffic (router)', D + f(r.rx_mbit) + U + f(r.tx_mbit),
         'Mbit/s' + stale + ' \u00b7 1h avg ' + D + f(r.avg_rx_1h) + U + f(r.avg_tx_1h) +
         ' \u00b7 24h peak ' + D + f(r.peak_rx_24h) + U + f(r.peak_tx_24h) + spark('#22d3ee'),
         '#22d3ee', ld ? (r.rx_mbit || 0) / ld : null) +
      mk('Data today', D + gb(r.day_rx) + U + gb(r.day_tx),
         'month ' + D + gb(r.month_rx) + U + gb(r.month_tx) + ' \u00b7 since router boot ' + D + gb(r.rx_total) + U + gb(r.tx_total),
         '#f472b6', null) +
      mk('Latency (via router)', lat,
         (r.ping_host || 'internet') + ' \u00b7 router hop ' + (r.ping_gw == null ? '\u2013' : r.ping_gw.toFixed(1) + ' ms') +
         ' \u00b7 loss ' + (r.loss_wan == null ? '\u2013' : r.loss_wan.toFixed(0) + '%'),
         latCol, null) +
      mk('Devices online', r.clients == null ? '\u2013' : String(r.clients), r.wan_up === false ? 'WAN DOWN' : 'WAN up', '#a78bfa', null) +
      mk('Router uptime', dur(r.uptime), r.fw || '', '#8e9aaf', null) +
      mk('Line rate', ld ? ld + ' / ' + lu : '\u2013', 'Mbit/s down / up', '#34d399', null);
  }
  function tick() { api().then(function (j) { render(j.router); }).catch(function () {}); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', tick); else setTimeout(tick, 500);
  setInterval(tick, 5000);
})();
