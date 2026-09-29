/* Cruscotto candele: legge i dati JSON (#cxd-data) e mostra sezioni scelte da menu a tendina, con grafici SVG/HTML e una tabella gemella.
   Serve anche a preparare il file compatto da incollare in chat (sezione "File per l'analisi"). Nessuna libreria esterna. */
(function () {
  'use strict';
  var root = document.getElementById('cxd');
  if (!root) return;
  var DATA = null, ST = {}, TIP = null, LASTW = 0;
  var TFORD = ['M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M10', 'M12', 'M15', 'M20', 'M30', 'H1', 'H2', 'H3', 'H4', 'H6', 'H8', 'H12', 'D1', 'W1', 'MN1'];
  var DIMS = [['hour', 'Ora del giorno'], ['min', "Minuto dell'ora"], ['dow', 'Giorno della settimana'], ['wom', 'Settimana del mese'], ['mon', 'Mese'], ['qtr', 'Trimestre'], ['yr', 'Anno']];
  // misure dei profili: indice nella riga [etichetta, n, rialziste, rendimento, range, grandi, impulsi, z x5, segni x5]
  var METS = [
    { k: 'rng', i: 4, z: 9, m: 14, n: 'Range medio (punti base)', u: ' pb', d: 2, kind: 'mag', all: 3 },
    { k: 'imp', i: 6, z: 11, m: 16, n: '% di impulsi', u: '%', d: 2, kind: 'mag', all: 5 },
    { k: 'big', i: 5, z: 10, m: 15, n: '% di candele oltre 1,5 ATR', u: '%', d: 1, kind: 'mag', all: 4 },
    { k: 'bull', i: 2, z: 7, m: 12, n: '% di candele rialziste', u: '%', d: 1, kind: 'pol', all: 1 },
    { k: 'ret', i: 3, z: 8, m: 13, n: 'Rendimento medio (ATR)', u: ' ATR', d: 3, kind: 'pol', all: 2 }
  ];
  var SECS = [
    ['sintesi', 'Sintesi del timeframe'], ['quando', 'Quando si muove (ora, giorno, mese...)'], ['eventi', 'Eventi più frequenti'],
    ['pattern', 'Pattern, forme e stati'], ['pre', 'Cosa c’è prima di un impulso'], ['rob', 'Confronti robusti'],
    ['conf', 'Confronto tra timeframe'], ['edge', 'Edge e strategie'], ['file', 'File per l’analisi (da copiare in chat)']
  ];
  var MK = ['', '§', '†'];

  /* ---------- utilità ---------- */
  function h(tag, cls, kids, attrs) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (attrs) for (var k in attrs) e.setAttribute(k, attrs[k]);
    add(e, kids);
    return e;
  }
  function add(e, kids) {
    if (kids == null) return;
    if (!Array.isArray(kids)) kids = [kids];
    kids.forEach(function (c) { if (c == null || c === false) return; e.appendChild(typeof c === 'object' ? c : document.createTextNode(String(c))); });
  }
  function svg(tag, attrs, kids) {
    var e = document.createElementNS('http://www.w3.org/2000/svg', tag);
    if (attrs) for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (kids) add(e, kids);
    return e;
  }
  function ent(s) { if (s == null) return ''; var t = document.createElement('textarea'); t.innerHTML = String(s); return t.value; }
  function nf(x, d) {
    if (x == null || !isFinite(x)) return '–';
    return Number(x).toLocaleString('it-IT', { minimumFractionDigits: d, maximumFractionDigits: d });
  }
  function sg(x, d) { if (x == null || !isFinite(x)) return '–'; return (x >= 0 ? '+' : '') + nf(x, d); }
  function zt(z, mk) { return z == null ? '' : 'z ' + sg(z, 1) + (mk ? ' ' + MK[mk] : ''); }
  function byId(id) { for (var i = 0; i < DATA.tfs.length; i++) if (DATA.tfs[i].id === id) return DATA.tfs[i]; return null; }
  function cur() { return byId(ST.tf) || DATA.tfs[0]; }
  function hlab(l) {
    var m = /^(\d\d)h$/.exec(l);
    if (!m || !DATA.ref) return l;
    var hh = +m[1], a = (hh + DATA.ref.a + 24) % 24, b = (hh + DATA.ref.b + 24) % 24;
    return l + ' (' + DATA.ref.s + ' ' + ('0' + a).slice(-2) + 'h' + (a !== b ? '/' + ('0' + b).slice(-2) + 'h' : '') + ')';
  }
  function nice(min, max, cnt) {
    if (max === min) { max = min + 1; }
    var span = max - min, step = Math.pow(10, Math.floor(Math.log10(span / cnt))), err = span / cnt / step;
    step *= err >= 7 ? 10 : err >= 3 ? 5 : err >= 1.5 ? 2 : 1;
    var lo = Math.floor(min / step) * step, hi = Math.ceil(max / step) * step, t = [];
    for (var v = lo; v <= hi + step * 0.001; v += step) t.push(+v.toFixed(10));
    return t;
  }
  function px(x) { return Math.round(x * 10) / 10; }

  /* ---------- suggerimento (tooltip) ---------- */
  function tipShow(el, ev) {
    var raw = el.getAttribute('data-tip');
    if (!raw) return;
    if (!TIP) { TIP = h('div', 'tip'); root.appendChild(TIP); }
    while (TIP.firstChild) TIP.removeChild(TIP.firstChild);
    var parts = raw.split('\n');
    TIP.appendChild(h('b', null, parts[0]));
    parts.slice(1).forEach(function (p) { TIP.appendChild(h('span', null, p)); });
    TIP.style.display = 'block';
    var r = root.getBoundingClientRect(), x = (ev ? ev.clientX : el.getBoundingClientRect().left) - r.left + 12, y = (ev ? ev.clientY : el.getBoundingClientRect().top) - r.top + 14;
    var w = TIP.offsetWidth;
    if (x + w > root.clientWidth) x = Math.max(0, root.clientWidth - w - 4);
    TIP.style.left = px(x) + 'px';
    TIP.style.top = px(y) + 'px';
  }
  function tipHide() { if (TIP) TIP.style.display = 'none'; }
  root.addEventListener('pointermove', function (ev) { var t = ev.target.closest ? ev.target.closest('[data-tip]') : null; if (t && root.contains(t)) tipShow(t, ev); else tipHide(); });
  root.addEventListener('pointerleave', tipHide);
  root.addEventListener('focusin', function (ev) { var t = ev.target.closest ? ev.target.closest('[data-tip]') : null; if (t) tipShow(t, null); });
  root.addEventListener('focusout', tipHide);

  /* ---------- elementi comuni ---------- */
  function select(id, label, opts, val, onchange) {
    var s = h('select', null, null, { id: 'cxd-' + id });
    opts.forEach(function (o) {
      if (o.g) { var og = h('optgroup', null, null, { label: o.g }); o.o.forEach(function (p) { og.appendChild(h('option', null, p[1], { value: p[0] })); }); s.appendChild(og); }
      else s.appendChild(h('option', null, o[1], { value: o[0] }));
    });
    s.value = val;
    s.addEventListener('change', function () { onchange(s.value); });
    return h('label', 'fld', [h('span', null, label), s]);
  }
  function kpi(l, v, s) { return h('div', 'ckpi', [h('span', null, l), h('b', null, v), s ? h('small', null, s) : null]); }
  function table(cols, rows, left) {
    left = left || [];
    var t = h('table'), th = h('thead'), tr = h('tr');
    cols.forEach(function (c, i) { tr.appendChild(h('th', left.indexOf(i) >= 0 ? 'tl' : null, c)); });
    th.appendChild(tr); t.appendChild(th);
    var tb = h('tbody');
    rows.forEach(function (r) { var q = h('tr'); r.forEach(function (c, i) { q.appendChild(h('td', left.indexOf(i) >= 0 || (typeof c === 'string' && c.length > 40) ? 'tl' : null, c)); }); tb.appendChild(q); });
    t.appendChild(tb);
    return h('div', 'ctw', t);
  }
  // pannello con grafico e tabella gemella (interruttore)
  function panel(title, sub, drawChart, drawTable) {
    var body = h('div'), on = 'g';
    var bg = h('button', 'seg on', 'Grafico', { type: 'button' }), bt = h('button', 'seg', 'Tabella', { type: 'button' });
    function show(w) {
      on = w; bg.className = 'seg' + (w === 'g' ? ' on' : ''); bt.className = 'seg' + (w === 't' ? ' on' : '');
      while (body.firstChild) body.removeChild(body.firstChild);
      body.appendChild(w === 'g' ? drawChart() : drawTable());
    }
    bg.addEventListener('click', function () { show('g'); });
    bt.addEventListener('click', function () { show('t'); });
    var cap = h('figcaption', null, [h('span', 't', title), drawTable ? h('span', 'segs', [bg, bt]) : null, sub ? h('span', 's', sub) : null]);
    show('g');
    return h('figure', null, [cap, body]);
  }
  function plotWidth() { var w = root.clientWidth; return Math.max(300, (w || 720) - 30); }
  function halfWidth() { var w = plotWidth(); return w >= 860 ? 560 : w; }

  /* ---------- grafico a colonne (profili) ---------- */
  // rows: {l: etichetta breve, v, tip, hi: 'pos'|'neg'|'dim'|'top', mk}
  function bars(rows, o) {
    var W = o.w || plotWidth(), H = o.h || 230, m = { l: 46, r: 10, t: 16, b: 30 };
    var pw = W - m.l - m.r, ph = H - m.t - m.b;
    var vs = rows.map(function (r) { return r.v; }).filter(function (v) { return v != null; });
    if (o.ref != null) vs.push(o.ref);
    var lo = Math.min.apply(null, vs.concat([0])), hi = Math.max.apply(null, vs.concat([0]));
    var tk = nice(lo, hi, 4); lo = tk[0]; hi = tk[tk.length - 1];
    var y = function (v) { return m.t + ph * (1 - (v - lo) / (hi - lo)); };
    var base = y(0);
    var s = svg('svg', { width: W, height: H, viewBox: '0 0 ' + W + ' ' + H, role: 'img', 'aria-label': o.aria || 'Grafico', style: 'width:100%;height:auto;max-width:' + px(W * 1.3) + 'px' });
    tk.forEach(function (t) {
      s.appendChild(svg('line', { x1: m.l, x2: W - m.r, y1: px(y(t)), y2: px(y(t)), stroke: 'var(--c-line,#1f2937)', 'stroke-width': 1 }));
      s.appendChild(svg('text', { x: m.l - 6, y: px(y(t)) + 4, 'text-anchor': 'end' }, o.yf ? o.yf(t) : nf(t, 0)));
    });
    s.appendChild(svg('line', { x1: m.l, x2: W - m.r, y1: px(base), y2: px(base), stroke: 'var(--c-axis,#374151)', 'stroke-width': 1 }));
    var n = rows.length, band = pw / n, bw = Math.min(24, band * 0.72), step = Math.max(1, Math.ceil(n * (o.lw || 26) / pw));
    var imax = -1, imin = -1;
    rows.forEach(function (r, i) { if (r.v == null) return; if (imax < 0 || r.v > rows[imax].v) imax = i; if (imin < 0 || r.v < rows[imin].v) imin = i; });
    rows.forEach(function (r, i) {
      var cx = m.l + band * (i + 0.5), x0 = cx - bw / 2;
      if (r.v != null) {
        var yy = y(r.v), up = r.v >= 0, top = Math.min(yy, base), hgt = Math.abs(base - yy);
        var col = r.hi === 'neg' ? 'var(--c-neg,#e66767)' : r.hi === 'negdim' ? 'var(--c-neg-dim,#6b3a3a)' : r.hi === 'dim' ? 'var(--c-s1-dim,#274a75)' : 'var(--c-s1,#3987e5)';
        if (hgt > 0.5) {
          var rr = Math.min(4, hgt), d;
          if (up) d = 'M' + px(x0) + ',' + px(base) + 'L' + px(x0) + ',' + px(top + rr) + 'Q' + px(x0) + ',' + px(top) + ' ' + px(x0 + rr) + ',' + px(top) + 'L' + px(x0 + bw - rr) + ',' + px(top) + 'Q' + px(x0 + bw) + ',' + px(top) + ' ' + px(x0 + bw) + ',' + px(top + rr) + 'L' + px(x0 + bw) + ',' + px(base) + 'Z';
          else d = 'M' + px(x0) + ',' + px(base) + 'L' + px(x0) + ',' + px(top + hgt - rr) + 'Q' + px(x0) + ',' + px(top + hgt) + ' ' + px(x0 + rr) + ',' + px(top + hgt) + 'L' + px(x0 + bw - rr) + ',' + px(top + hgt) + 'Q' + px(x0 + bw) + ',' + px(top + hgt) + ' ' + px(x0 + bw) + ',' + px(top + hgt - rr) + 'L' + px(x0 + bw) + ',' + px(base) + 'Z';
          s.appendChild(svg('path', { d: d, fill: col }));
        }
        if ((i === imax || i === imin) && n > 6 && (o.lab !== false)) {
          var above = up ? top - 4 : top + hgt + 11;
          s.appendChild(svg('text', { x: px(cx), y: px(above), 'text-anchor': 'middle', 'class': 'v' }, (o.vf || nf)(r.v)));
        }
        if (r.mk === 2) s.appendChild(svg('text', { x: px(cx), y: px(up ? top - (i === imax || i === imin ? 16 : 4) : top + hgt + (i === imax || i === imin ? 24 : 11)), 'text-anchor': 'middle' }, '†'));
      }
      if (i % step === 0) s.appendChild(svg('text', { x: px(cx), y: H - 10, 'text-anchor': 'middle' }, r.l));
      var hit = svg('rect', { x: px(m.l + band * i), y: m.t, width: px(band), height: ph, fill: 'transparent', tabindex: 0, 'data-tip': r.tip || '', 'aria-label': (r.l || '') + ': ' + (r.v == null ? 'n/d' : (o.vf || nf)(r.v)) });
      s.appendChild(hit);
    });
    if (o.ref != null) {
      s.appendChild(svg('line', { x1: m.l, x2: W - m.r, y1: px(y(o.ref)), y2: px(y(o.ref)), stroke: 'var(--c-fg,#e5e7eb)', 'stroke-width': 1, opacity: 0.55 }));
      s.appendChild(svg('text', { x: W - m.r, y: px(y(o.ref)) - 4, 'text-anchor': 'end' }, o.refl || 'media'));
    }
    return h('div', 'plot', s);
  }

  /* ---------- barre orizzontali (classifiche) ---------- */
  // rows: {l, sub, v, txt, cls, tip, tick, max}; se o.div le barre partono dal centro
  function hbars(rows, o) {
    o = o || {};
    var mx = 0;
    rows.forEach(function (r) { if (r.g) return; mx = Math.max(mx, Math.abs(r.v || 0), r.tick || 0); });
    if (o.max) mx = o.max;
    if (!(mx > 0)) mx = 1;
    var box = h('div', 'chb');
    rows.forEach(function (r) {
      if (r.g) { box.appendChild(h('div', 'hbr g', r.g)); if (r.gmax !== undefined) mx = r.gmax || 1; return; }
      var tr = h('div', 'tr');
      if (o.div) {
        tr.appendChild(h('b', 'mid'));
        var w = Math.min(50, Math.abs(r.v || 0) / mx * 50);
        var i = h('i', r.cls || (r.v >= 0 ? '' : 'neg'));
        i.style.width = px(w) + '%';
        i.style.left = r.v >= 0 ? '50%' : px(50 - w) + '%';
        tr.appendChild(i);
      } else {
        var i2 = h('i', r.cls || '');
        i2.style.left = '0';
        i2.style.width = px(Math.min(100, Math.abs(r.v || 0) / mx * 100)) + '%';
        tr.appendChild(i2);
        if (r.tick != null) { var u = h('u'); u.style.left = 'calc(' + px(Math.min(100, r.tick / mx * 100)) + '% - 1px)'; tr.appendChild(u); }
      }
      var row = h('div', 'hbr', [h('div', 'l', [r.l, r.sub ? h('small', null, r.sub) : null]), tr, h('div', 'v', r.txt)], { tabindex: 0, 'data-tip': r.tip || '' });
      box.appendChild(row);
    });
    return box;
  }

  /* ---------- sezioni ---------- */
  function profRows(t, dim, met) {
    var P = t.prof && t.prof[dim];
    if (!P) return null;
    return P.r.filter(function (r) { return r[1] > 0; });
  }
  function shortLab(dim, l) { if (dim === 'hour') { var m = /^(\d\d)h$/.exec(l); return m ? m[1] : l; } return l; }
  function bestWorst(t, dim, met) {
    var R = profRows(t, dim); if (!R || R.length < 2) return null;
    var a = R.filter(function (r) { return r[met.i] != null; }).slice().sort(function (x, y) { return y[met.i] - x[met.i]; });
    return { hi: a[0], lo: a[a.length - 1], all: a };
  }
  function fuTxt(t) { return t.fu === 'anno' ? 'all’anno' : 'al giorno di mercato'; }
  function nfm(met, x) { return nf(x, met.d) + met.u; }

  function secSintesi(box, t) {
    var k = h('div', 'ckpis', [
      kpi('Candele analizzate', nf(t.n, 0), t.t0 + ' → ' + t.t1), kpi('Rialziste', nf(t.bull, 1) + '%', 'corpo mediano ' + nf(t.body, 0) + '% del range'),
      kpi('Range mediano', nf(t.medR, 3) + '%', 'del prezzo'), kpi('Soglia dell’impulso', nf(t.thr, 1) + ' ATR', nf(t.nimp, 0) + ' impulsi, ' + nf(t.impP, 2) + '%'),
      kpi('Confronti robusti', nf(t.nrob, 0), 'su ' + nf(t.tst, 0) + ' con |z| ≥ 2')
    ]);
    box.appendChild(k);
    var say = [];
    var bw = bestWorst(t, 'hour', METS[0]);
    if (bw) say.push([h('b', null, 'Quando si muove: '), 'il range è massimo alle ' + hlab(bw.hi[0]) + ' (' + nf(bw.hi[4], 2) + ' pb, ×' + nf(bw.hi[4] / (t.prof.hour.all[3] || 1), 2) + ' la media) e minimo alle ' + hlab(bw.lo[0]) + ' (×' + nf(bw.lo[4] / (t.prof.hour.all[3] || 1), 2) + ').']);
    var bi = bestWorst(t, 'hour', METS[1]);
    if (bi && bi.hi[6] > 0) say.push([h('b', null, 'Impulsi: '), 'sono lo ' + nf(t.impP, 2) + '% delle candele; il ' + nf(bi.hi[6], 2) + '% cade alle ' + hlab(bi.hi[0]) + '.']);
    var dw = bestWorst(t, 'dow', METS[0]);
    if (dw) say.push([h('b', null, 'Giorno: '), 'più mosso ' + dw.hi[0] + ' (' + nf(dw.hi[4], 2) + ' pb), meno mosso ' + dw.lo[0] + '.']);
    var mw = bestWorst(t, 'mon', METS[0]);
    if (mw) say.push([h('b', null, 'Mese: '), 'più mosso ' + mw.hi[0] + ', meno mosso ' + mw.lo[0] + (t.span < 3 ? ' (meno di 3 anni di dati: solo descrizione)' : '') + '.']);
    if (t.freq && t.freq.length) say.push([h('b', null, 'Evento più frequente: '), ent(t.freq[0][0]) + ' (' + nf(t.freq[0][3], 1) + '% delle candele, ' + nf(t.freq[0][4], 1) + ' ' + fuTxt(t) + ').']);
    if (t.rob && t.rob.length) say.push([h('b', null, 'Confronto più solido: '), ent(t.rob[0][0]) + ' (z ' + sg(t.rob[0][1], 1) + ').']);
    var pu = topPre(t, 'up'), pd = topPre(t, 'dn');
    if (pu) say.push([h('b', null, 'Prima di un impulso rialzista: '), preTxt(pu) + '.']);
    if (pd) say.push([h('b', null, 'Prima di un impulso ribassista: '), preTxt(pd) + '.']);
    var ul = h('ul');
    say.forEach(function (s) { ul.appendChild(h('li', null, s)); });
    box.appendChild(h('div', 'say', [h('b', null, 'In poche parole – ' + t.id), ul]));
    var g = h('div', 'grid2');
    if (t.prof && t.prof.hour) g.appendChild(quandoPanel(t, 'hour', METS[0], true));
    else if (t.prof && t.prof.dow) g.appendChild(quandoPanel(t, 'dow', METS[0], true));
    if (t.freq && t.freq.length) g.appendChild(eventiPanel(t, 10, 'n', true));
    box.appendChild(g);
    if (t.top && t.top.length) {
      box.appendChild(h('div', 'say', [h('b', null, 'I 5 movimenti maggiori'), table(['Quando', 'Direzione', 'Range % del prezzo', 'Range in ATR'],
        t.top.map(function (r) { return [r[0], r[1] ? 'rialzista' : 'ribassista', nf(r[2], 3) + '%', nf(r[3], 1)]; }))]));
    }
  }
  // stato piu' frequente del normale prima degli impulsi: {r, lv}; lv 2 = robusto, 1 = solo |z| >= 2 (indizio, non robusto)
  function topPre(t, d) {
    var P = t.pre && t.pre[d]; if (!P || !P.r) return null;
    var byz = function (x, y) { return y[4] - x[4]; };
    var a = P.r.filter(function (r) { return r[4] != null && r[4] > 0 && r[5] === 2; }).sort(byz);
    if (a.length) return { r: a[0], lv: 2 };
    a = P.r.filter(function (r) { return r[4] != null && r[4] >= 2; }).sort(byz);
    return a.length ? { r: a[0], lv: 1 } : null;
  }
  function preTxt(b) {
    return ent(b.r[0]) + ' (' + nf(b.r[2], 0) + ' volte contro ' + nf(b.r[3], 1) + ' attese, ' + zt(b.r[4], b.r[5]) + (b.lv === 2 ? ', robusto' : ', indizio non robusto: con molti confronti capita per caso') + ')';
  }

  function quandoPanel(t, dim, met, compact) {
    var R = profRows(t, dim);
    var all = t.prof[dim].all;
    var refV = all[met.all];
    var ranked = R.filter(function (r) { return r[met.i] != null; }).slice().sort(function (a, b) { return b[met.i] - a[met.i]; });
    var top = {}; ranked.slice(0, 3).forEach(function (r) { top[r[0]] = 1; });
    var pol = met.kind === 'pol';
    var rows = R.map(function (r) {
      var v = r[met.i], z = r[met.z], mk = r[met.m], hi;
      if (!pol) hi = top[r[0]] ? 'top' : 'dim';
      else hi = z == null || Math.abs(z) < 2 ? (v >= refV ? 'dim' : 'negdim') : (v >= refV ? 'pos' : 'neg');
      var lab = dim === 'hour' ? hlab(r[0]) : r[0];
      return { l: shortLab(dim, r[0]), v: pol ? v - refV : v, hi: hi, mk: mk, tip: nfm(met, v) + '\n' + lab + ' · ' + nf(r[1], 0) + ' candele' + (z != null ? '\n' + zt(z, mk) : '') + '\nMedia del timeframe ' + nfm(met, refV) };
    });
    var dn = DIMS.filter(function (d) { return d[0] === dim; })[0][1];
    return panel(met.n + ' per ' + dn.toLowerCase() + (pol ? ': scostamento dalla media (' + nfm(met, refV) + ')' : ''), pol ? 'Barre = differenza dalla media del timeframe; blu sopra, rosso sotto, colore pieno se |z| ≥ 2. † = robusto. Il valore vero è nel suggerimento.' : 'Barre evidenziate: le 3 più alte. † = robusto. Riga = media del timeframe.', function () {
      var pd = met.k === 'ret' ? 3 : 1;
      return pol ? bars(rows, { w: compact ? halfWidth() : undefined, lw: 18, vf: function (v) { return sg(v, pd); }, yf: function (v) { return sg(v, pd); }, aria: met.n }) :
        bars(rows, { w: compact ? halfWidth() : undefined, lw: 18, ref: refV, refl: 'media ' + nfm(met, refV), vf: function (v) { return nf(v, met.d); }, yf: function (v) { return nf(v, met.d > 1 ? 1 : 0); }, aria: met.n });
    }, function () {
      return table([dn, 'Candele', met.n, 'z', 'Segno'], R.map(function (r) { return [dim === 'hour' ? hlab(r[0]) : r[0], nf(r[1], 0), nfm(met, r[met.i]), r[met.z] == null ? '–' : sg(r[met.z], 1), MK[r[met.m] || 0] || '']; }));
    });
  }
  function secQuando(box, t) {
    var dims = DIMS.filter(function (d) { return t.prof && t.prof[d[0]] && t.prof[d[0]].r.length > 1; });
    if (!dims.length) { box.appendChild(h('p', 'cmuted', 'Questo file non contiene i profili di tempo per questo timeframe (livello del file troppo basso).')); return; }
    if (!dims.some(function (d) { return d[0] === ST.dim; })) ST.dim = dims[0][0];
    var met = METS.filter(function (m) { return m.k === ST.met; })[0] || METS[0];
    var top = h('div', 'bar', [
      select('dim', 'Dimensione del tempo', dims, ST.dim, function (v) { ST.dim = v; render(); }),
      select('met', 'Misura', METS.map(function (m) { return [m.k, m.n]; }), met.k, function (v) { ST.met = v; render(); })]);
    box.appendChild(top);
    var bw = bestWorst(t, ST.dim, met), dn = dims.filter(function (d) { return d[0] === ST.dim; })[0][1];
    if (bw) {
      var refV = t.prof[ST.dim].all[met.all], nsig = bw.all.filter(function (r) { return r[met.z] != null && Math.abs(r[met.z]) >= 2; }).length, nrob = bw.all.filter(function (r) { return r[met.m] === 2; }).length;
      var L = function (r) { return (ST.dim === 'hour' ? hlab(r[0]) : r[0]) + ' (' + nfm(met, r[met.i]) + ')'; };
      var s = met.kind === 'mag' ?
        'Massimo: ' + L(bw.hi) + ', ×' + nf(bw.hi[met.i] / (refV || 1), 2) + ' la media del timeframe (' + nfm(met, refV) + '). Minimo: ' + L(bw.lo) + ', ×' + nf(bw.lo[met.i] / (refV || 1), 2) + '. Seconda e terza: ' + bw.all.slice(1, 3).map(L).join(', ') + '.' :
        'Più alto: ' + L(bw.hi) + '; più basso: ' + L(bw.lo) + '; media ' + nfm(met, refV) + '. ' + nsig + ' categorie su ' + bw.all.length + ' si scostano dal caso di oltre 2 z' + (nrob ? ' (' + nrob + ' robuste †)' : '') + '.';
      box.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), s]));
    }
    box.appendChild(quandoPanel(t, ST.dim, met, false));
  }

  function eventiPanel(t, n, sort, compact) {
    var F = t.freq.slice();
    if (sort === 'day') F.sort(function (a, b) { return b[4] - a[4]; }); else F.sort(function (a, b) { return b[3] - a[3]; });
    F = F.slice(0, n);
    var rows = F.map(function (r) { return { l: ent(r[0]), sub: r[1], v: r[3], txt: nf(r[3], 1) + '%', cls: '', tip: nf(r[3], 2) + '% delle candele\n' + ent(r[0]) + ' · ' + nf(r[2], 0) + ' casi\nUna volta ogni ' + nf(100 / r[3], 1) + ' candele · ' + nf(r[4], 2) + ' ' + fuTxt(t) }; });
    return panel('Gli eventi più frequenti (' + n + ')', 'Quota delle candele del timeframe in cui l’evento capita.', function () { return hbars(rows); }, function () {
      return table(['Evento', 'Gruppo', 'Casi', '% delle candele', 'Una volta ogni (candele)', t.fu === 'anno' ? 'All’anno' : 'Al giorno di mercato'], F.map(function (r) { return [ent(r[0]), r[1], nf(r[2], 0), nf(r[3], 2) + '%', nf(100 / r[3], 1), nf(r[4], 2)]; }));
    });
  }
  function secEventi(box, t) {
    if (!t.freq || !t.freq.length) { box.appendChild(h('p', 'cmuted', 'Nessun evento con almeno 30 casi in questo timeframe.')); return; }
    box.appendChild(h('div', 'bar', [
      select('en', 'Quanti eventi', [[5, 'Primi 5'], [10, 'Primi 10'], [15, 'Primi 15']], String(ST.en || 10), function (v) { ST.en = +v; render(); }),
      select('es', 'Ordina per', [['n', 'Quota delle candele'], ['day', 'Frequenza al giorno']], ST.es || 'n', function (v) { ST.es = v; render(); })]));
    var F = t.freq[0];
    box.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), 'su ' + t.id + ' capita più spesso “' + ent(F[0]) + '” (' + nf(F[3], 1) + '% delle candele, ' + nf(F[4], 1) + ' ' + fuTxt(t) + '). ' +
      'I primi ' + Math.min(5, t.freq.length) + ' eventi coprono ' + nf(t.freq.slice(0, 5).reduce(function (a, r) { return a + r[3]; }, 0), 0) + '% delle candele (gli eventi si sovrappongono).']));
    box.appendChild(eventiPanel(t, ST.en || 10, ST.es || 'n', false));
  }

  /* pattern, forme e stati */
  var CAND_G = ['Forme di candela', 'Pattern con nome', 'Serie nella stessa direzione', 'Posizione rispetto alla candela precedente', 'Coppie e terne di candele'];
  function clsGroups(t) {
    var g = t.cls || {}, out = [];
    Object.keys(g).forEach(function (k) { if (k !== '__all') out.push(k); });
    return out;
  }
  function grpOpts(gs) {
    var a = gs.filter(function (g) { return CAND_G.indexOf(g) >= 0; }), b = gs.filter(function (g) { return CAND_G.indexOf(g) < 0; }), o = [];
    if (a.length) o.push({ g: 'Candele', o: a.map(function (g) { return [g, g]; }) });
    if (b.length) o.push({ g: 'Stati della candela', o: b.map(function (g) { return [g, g]; }) });
    return o;
  }
  // riga classe: [etichetta, n, quota%, sale%, r1, r3, zSu, zR1, zR3, mSu, mR1, mR3, rng1, brkH, brkL, amp, corsa, (gruppo)]
  function secPattern(box, t) {
    var gs = clsGroups(t);
    if (!gs.length) { box.appendChild(h('p', 'cmuted', 'Questo file non contiene le classi di candele per questo timeframe.')); return; }
    if (gs.indexOf(ST.grp) < 0) ST.grp = gs[0];
    var meas = ST.pm || 'up', sort = ST.ps || 'z', N = ST.pn || 15;
    box.appendChild(h('div', 'bar', [
      select('grp', 'Gruppo', grpOpts(gs), ST.grp, function (v) { ST.grp = v; render(); }),
      select('pm', 'Misura del grafico', [['up', 'Sale dopo (punti % sopra/sotto la media)'], ['r1', 'Rendimento della candela dopo (ATR)'], ['r3', 'Rendimento delle 3 candele dopo (ATR)']], meas, function (v) { ST.pm = v; render(); }),
      select('ps', 'Ordina per', [['z', 'Distanza dal caso (|z|)'], ['n', 'Frequenza'], ['hi', 'Valore più alto'], ['lo', 'Valore più basso']], sort, function (v) { ST.ps = v; render(); }),
      select('pn', 'Quante righe', [[10, 'Prime 10'], [15, 'Prime 15'], [30, 'Prime 30'], [999, 'Tutte']], String(N), function (v) { ST.pn = +v; render(); })]));
    var all = t.clsAll || t.cls.__all || [null, 0, 100, 50, 0, 0];
    var rows = t.cls[ST.grp].slice();
    var ix = { up: [3, 6, 9], r1: [4, 7, 10], r3: [5, 8, 11] }[meas], ref = meas === 'up' ? all[3] : (meas === 'r1' ? all[4] : all[5]);
    var maxz = function (r) { var m = 0; [6, 7, 8].forEach(function (i) { if (r[i] != null && Math.abs(r[i]) > m) m = Math.abs(r[i]); }); return m; };
    var val = function (r) { return r[ix[0]]; };
    if (sort === 'z') rows.sort(function (a, b) { return maxz(b) - maxz(a); });
    else if (sort === 'n') rows.sort(function (a, b) { return b[1] - a[1]; });
    else if (sort === 'hi') rows.sort(function (a, b) { return val(b) - val(a); });
    else rows.sort(function (a, b) { return val(a) - val(b); });
    rows = rows.slice(0, N);
    var lead = rows.filter(function (r) { return r[ix[1]] != null && Math.abs(r[ix[1]]) >= 2; });
    box.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), rows.length + ' righe del gruppo “' + ST.grp + '” su ' + t.id + '. ' +
      (lead.length ? lead.length + (lead.length === 1 ? ' si scosta' : ' si scostano') + ' dal caso di oltre 2 z; la più lontana è “' + ent(lead.sort(function (a, b) { return Math.abs(b[ix[1]]) - Math.abs(a[ix[1]]); })[0][0]) + '” (' + (meas === 'up' ? nf(lead[0][3], 1) + '% sale dopo' : nf(lead[0][ix[0]], 3) + ' ATR') + ', ' + zt(lead[0][ix[1]], lead[0][ix[2]]) + ').' : 'nessuna si scosta dal caso in modo netto.') +
      ' Riferimento: tutte le candele ' + (meas === 'up' ? nf(ref, 1) + '% sale dopo' : nf(ref, 3) + ' ATR') + '.']));
    var drows = rows.map(function (r) {
      var v = r[ix[0]] - ref, z = r[ix[1]], sig = z != null && Math.abs(z) >= 2;
      var cls = v >= 0 ? (sig ? '' : 'dim') : (sig ? 'neg' : 'negdim');
      return { l: ent(r[0]), sub: nf(r[1], 0) + ' casi · ' + nf(r[2], 2) + '% delle candele', v: v, cls: cls, txt: (meas === 'up' ? sg(v, 1) + ' pt' : sg(v, 3)) + (z != null ? ' · ' + zt(z, r[ix[2]]) : ''),
        tip: (meas === 'up' ? nf(r[3], 1) + '% sale dopo' : nf(r[ix[0]], 3) + ' ATR') + '\n' + ent(r[0]) + ' · ' + nf(r[1], 0) + ' casi\n' + zt(z, r[ix[2]]) + '\nRiferimento ' + (meas === 'up' ? nf(ref, 1) + '%' : nf(ref, 3) + ' ATR') };
    });
    box.appendChild(panel(ST.grp + ': ' + { up: 'quanto sale dopo, rispetto alla media', r1: 'rendimento a 1 candela, rispetto alla media', r3: 'rendimento a 3 candele, rispetto alla media' }[meas], 'Blu = sopra la media, rosso = sotto; colore pieno se |z| ≥ 2, tenue se compatibile con il caso. † robusto, § solo FDR.',
      function () { return hbars(drows, { div: true }); },
      function () {
        return table(['Classe', 'Casi', '% candele', 'Sale dopo %', 'Rend. 1 (ATR)', 'Rend. 3 (ATR)', 'z sale', 'z r1', 'z r3', 'Range dopo', 'Rompe max %', 'Rompe min %'],
          rows.map(function (r) { return [ent(r[0]) + (r[17] ? ' [' + r[17] + ']' : ''), nf(r[1], 0), nf(r[2], 2), nf(r[3], 1), nf(r[4], 3), nf(r[5], 3), r[6] == null ? '–' : sg(r[6], 1) + (MK[r[9] || 0] || ''), r[7] == null ? '–' : sg(r[7], 1) + (MK[r[10] || 0] || ''), r[8] == null ? '–' : sg(r[8], 1) + (MK[r[11] || 0] || ''), nf(r[12], 2), nf(r[13], 1), nf(r[14], 1)]; }));
      }));
  }

  function secPre(box, t) {
    if (!t.pre || (!t.pre.up && !t.pre.dn)) { box.appendChild(h('p', 'cmuted', 'Questo file non contiene i precursori degli impulsi per questo timeframe.')); return; }
    var d = ST.pd || 'up';
    if (!t.pre[d]) d = d === 'up' ? 'dn' : 'up';
    box.appendChild(h('div', 'bar', [
      select('pd', 'Impulso', [['up', 'Rialzista'], ['dn', 'Ribassista']], d, function (v) { ST.pd = v; render(); }),
      select('po', 'Mostra', [['all', 'Tutti gli stati'], ['sig', 'Solo quelli lontani dal caso (|z| ≥ 2)']], ST.po || 'all', function (v) { ST.po = v; render(); })]));
    var P = t.pre[d], only = (ST.po || 'all') === 'sig';
    var rows = [], lastg = -1, best = topPre(t, d);
    P.r.forEach(function (r) {
      if (only && !(r[4] != null && Math.abs(r[4]) >= 2)) return;
      if (r[1] !== lastg) { lastg = r[1]; rows.push({ g: (DATA.pg && DATA.pg[r[1]]) || 'Stato' }); }
      var sig = r[4] != null && Math.abs(r[4]) >= 2;
      rows.push({ l: ent(r[0]), v: r[2], tick: r[3], cls: sig ? (r[4] > 0 ? '' : 'neg') : 'dim', txt: nf(r[2], 0) + ' vs ' + nf(r[3], 1) + ' · ' + (r[4] == null ? 'n/d' : zt(r[4], r[5])),
        tip: nf(r[2], 0) + ' volte prima di un impulso\n' + ent(r[0]) + '\nAttese ' + nf(r[3], 1) + ' nelle stesse ore\n' + (r[4] == null ? 'campione insufficiente' : zt(r[4], r[5])) });
    });
    box.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), 'su ' + t.id + ' ci sono ' + nf(P.n, 0) + ' impulsi ' + (d === 'up' ? 'rialzisti' : 'ribassisti') + '. ' +
      (best ? 'Lo stato più sopra il normale è ' + preTxt(best) + '.' : 'nessuno stato è più frequente del normale in modo netto (|z| < 2).') +
      ' Confronto con le candele non impulso della stessa ora e dello stesso regime di volatilità.']));
    box.appendChild(panel('Stato della candela prima dell’impulso ' + (d === 'up' ? 'rialzista' : 'ribassista'), 'Barra = quante volte prima dell’impulso; tacca = quante ne aspetteremmo. Blu = più del normale, rosso = meno, tenue = compatibile con il caso.', function () {
      // ogni gruppo ha la sua scala
      var blocks = h('div', 'chb'), grp = [], all = [];
      rows.forEach(function (r) { if (r.g) { grp = []; all.push({ g: r.g, rows: grp }); } else grp.push(r); });
      all.forEach(function (b) {
        var mx = 0; b.rows.forEach(function (r) { mx = Math.max(mx, r.v, r.tick || 0); });
        var part = hbars([{ g: b.g }].concat(b.rows), { max: mx * 1.1 });
        Array.prototype.slice.call(part.childNodes).forEach(function (c) { blocks.appendChild(c); });
      });
      return blocks;
    }, function () {
      return table(['Stato', 'Osservati', 'Attesi', 'Rapporto', 'z', 'Segno'], P.r.filter(function (r) { return !only || (r[4] != null && Math.abs(r[4]) >= 2); }).map(function (r) { return [ent(r[0]), nf(r[2], 0), nf(r[3], 1), r[3] > 0 ? nf(r[2] / r[3], 2) : '–', r[4] == null ? '–' : sg(r[4], 1), MK[r[5] || 0] || '']; }));
    }));
    if (t.comp && t.comp.length === 3) {
      var fam = ['Doji', 'Pin', 'Trottola', 'Corpo medio', 'Corpo lungo', 'Marubozu'];
      var rowsC = fam.map(function (f, k) { return [f, nf(t.comp[0][k], 1) + '%', nf(t.comp[1][k], 1) + '%', nf(t.comp[2][k], 1) + '%']; });
      rowsC.push(['Ampiezza media (ATR)', nf(t.comp[0][6], 2), nf(t.comp[1][6], 2), nf(t.comp[2][6], 2)]);
      box.appendChild(h('figure', null, [h('figcaption', null, [h('span', 't', 'Come sono fatti gli impulsi'), h('span', 's', 'Forma della candela: quota tra tutte le candele e tra gli impulsi rialzisti e ribassisti.')]), table(['Forma', 'Tutte le candele', 'Impulsi rialzisti', 'Impulsi ribassisti'], rowsC)]));
    }
  }

    function secRob(box, t) {
    var R = (t.rob || []).slice();
    if (!R.length) { box.appendChild(h('p', 'cmuted', 'Nessun confronto robusto in questo timeframe (o non incluso nel file).')); return; }
    var fam = ST.rf || 'all', N = ST.rn || 15;
    box.appendChild(h('div', 'bar', [
      select('rf', 'Famiglia', [['all', 'Tutte'], ['dir', 'Direzione (dopo la candela, per fascia di tempo)'], ['rit', 'Ritmo dell’attività (range, candele grandi, impulsi)'], ['pre', 'Precursori degli impulsi']], fam, function (v) { ST.rf = v; render(); }),
      select('rn', 'Quanti', [[5, 'Primi 5'], [10, 'Primi 10'], [15, 'Primi 15'], [25, 'Primi 25']], String(N), function (v) { ST.rn = +v; render(); })]));
    var map = { dir: [0, 1, 2], rit: [3, 4], pre: [5] };
    if (fam !== 'all') R = R.filter(function (r) { return map[fam].indexOf(r[2]) >= 0; });
    R = R.slice(0, N);
    var fc = [0, 0, 0];
    (t.rob || []).forEach(function (r) { fc[r[2] <= 2 ? 0 : (r[2] <= 4 ? 1 : 2)]++; });
    box.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), 'su ' + t.id + ' i confronti che superano il controllo dei falsi positivi e hanno lo stesso verso nelle due metà dello storico sono ' + nf(t.nrob, 0) + '. ' +
      'Tra i ' + nf((t.rob || []).length, 0) + ' più forti del file: direzione ' + nf(fc[0], 0) + ', ritmo dell’attività ' + nf(fc[1], 0) + ', precursori degli impulsi ' + nf(fc[2], 0) + '. I confronti di ritmo sono in gran parte la stagionalità della volatilità (nota); quelli di direzione sono i più rari.']));
    var rows = R.map(function (r) { return { l: ent(r[0]), v: Math.abs(r[1]), txt: 'z ' + sg(r[1], 1), cls: r[1] >= 0 ? '' : 'neg', tip: 'z ' + sg(r[1], 1) + '\n' + ent(r[0]) }; });
    box.appendChild(panel('Confronti robusti di ' + t.id, 'Lunghezza della barra = |z|; blu = sopra il riferimento, rosso = sotto. Descrivono l’andamento del prezzo, non un guadagno: nessun costo è considerato.', function () { return hbars(rows); },
      function () { return table(['Confronto', 'z', 'Famiglia'], R.map(function (r) { return [ent(r[0]), sg(r[1], 1), ['classi', 'direzione ora/minuto', 'direzione calendario', 'ritmo ora/minuto', 'ritmo calendario', 'precursori'][r[2]] || '']; })); }));
  }

  function secConf(box) {
    var tfs = DATA.tfs.filter(function (t) { return t.prof && t.prof.hour && t.prof.hour.r.length > 3; });
    if (!tfs.length) { box.appendChild(h('p', 'cmuted', 'Nessun timeframe con profilo orario nel file.')); return; }
    var mk = ST.cm || 'rng';
    box.appendChild(h('div', 'bar', [select('cm', 'Misura', [['rng', 'Range rispetto alla media del timeframe'], ['imp', '% di impulsi'], ['bull', '% di candele rialziste']], mk, function (v) { ST.cm = v; render(); })]));
    var vals = {}, mx = 0, mn = 1e9;
    tfs.forEach(function (t) {
      var all = t.prof.hour.all;
      t.prof.hour.r.forEach(function (r) {
        var v = mk === 'rng' ? (all[3] ? r[4] / all[3] : null) : (mk === 'imp' ? r[6] : r[2]);
        if (v == null) return;
        var m = /^(\d\d)-(\d\d)h$/.exec(r[0]), a, b;
        if (m) { a = +m[1]; b = +m[2]; } else { m = /^(\d\d)h$/.exec(r[0]); if (!m) return; a = +m[1]; b = a + 1; }
        for (var k = a; k < b && k < 24; k++) vals[t.id + '|' + ('0' + k).slice(-2) + 'h'] = v;
        mx = Math.max(mx, v); mn = Math.min(mn, v);
      });
    });
    var lines = tfs.map(function (t) {
      var b = bestWorst(t, 'hour', mk === 'rng' ? METS[0] : (mk === 'imp' ? METS[1] : METS[3]));
      return b ? t.id + ': ' + hlab(b.hi[0]) : null;
    }).filter(Boolean);
    box.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), (mk === 'rng' ? 'ora con il range maggiore' : mk === 'imp' ? 'ora con più impulsi' : 'ora più rialzista') + ' per timeframe – ' + lines.join('; ') + '.']));
    var hours = []; for (var i = 0; i < 24; i++) hours.push(('0' + i).slice(-2) + 'h');
    panelHeat(box, tfs, hours, vals, mk, mn, mx);
  }
  function panelHeat(box, tfs, hours, vals, mk, mn, mx) {
    var pol = mk === 'bull', fm = function (v) { return mk === 'rng' ? '×' + nf(v, 2) : nf(v, mk === 'imp' ? 2 : 1) + '%'; };
    box.appendChild(panel('Ora del giorno × timeframe (ora dei dati)', 'Ogni casella è una fascia oraria di un timeframe; più scuro/intenso = valore più alto' + (pol ? '; blu sopra il 50%, rosso sotto' : '') + '. Passa il puntatore per il valore.', function () {
      var t = h('table', 'hm'), th = h('thead'), tr = h('tr', null, [h('th')]);
      hours.forEach(function (x) { tr.appendChild(h('th', null, x.slice(0, 2))); });
      th.appendChild(tr); t.appendChild(th);
      var tb = h('tbody');
      tfs.forEach(function (tf) {
        var row = h('tr', null, [h('td', null, tf.id)]);
        hours.forEach(function (hx) {
          var v = vals[tf.id + '|' + hx], td = h('td');
          if (v != null) {
            var a;
            if (pol) { var dv = (v - 50) / Math.max(1, Math.max(mx - 50, 50 - mn)); a = Math.min(1, Math.abs(dv)) * 100; td.style.background = 'color-mix(in srgb,' + (dv >= 0 ? 'var(--c-s1,#3987e5)' : 'var(--c-neg,#e66767)') + ' ' + px(Math.max(4, a)) + '%,var(--c-heat0,#1c2230))'; }
            else { a = (v - 0) / (mx || 1) * 100; td.style.background = 'color-mix(in srgb,var(--c-s1,#3987e5) ' + px(Math.max(4, a)) + '%,var(--c-heat0,#1c2230))'; }
            td.setAttribute('data-tip', fm(v) + '\n' + tf.id + ' · ' + hlab(hx)); td.setAttribute('tabindex', '0');
          }
          row.appendChild(td);
        });
        tb.appendChild(row);
      });
      t.appendChild(tb);
      return h('div', 'plot', [t, h('div', 'lgd', [pol ? 'sotto il 50%' : 'meno', h('i', pol ? 'dv' : null), pol ? 'sopra il 50%' : 'più (max ' + fm(mx) + ')'])]);
    }, function () {
      return table(['Timeframe'].concat(hours), tfs.map(function (tf) { return [tf.id].concat(hours.map(function (hx) { var v = vals[tf.id + '|' + hx]; return v == null ? '–' : fm(v); })); }));
    }));
  }

  function secEdge(box) {
    var e = DATA.edge;
    if (!e) { box.appendChild(h('p', 'cmuted', 'Il file non contiene la sintesi edge.')); return; }
    if (e.warn) box.appendChild(h('div', 'box bad', [h('b', null, '⚠ Costi del broker non disponibili. '), ent(e.warn)]));
    box.appendChild(h('div', 'box ' + (e.col || 'info'), [h('b', null, 'Verdetto. '), ent(e.head), h('div', 'cmuted', ent(e.stat))]));
    box.appendChild(h('div', 'ckpis', [kpi('Robuste', nf(e.cnt[3], 0), 'superano tutti i controlli'), kpi('Promettenti', nf(e.cnt[2], 0), 'tutto tranne i test multipli'), kpi('Indizi', nf(e.cnt[1], 0), 'positive e stabili'),
      kpi('Scartate', nf(e.cnt[0], 0), 'senza vantaggio'), kpi('Costo del broker', e.cost || 'n/d', e.costsrc || ''),
      e.tests != null ? kpi('Confronti in tutte le schede', nf(e.tests, 0), 'oltre z 3: ' + nf(e.n3, 0) + ' (attesi per caso ' + nf(e.exp3, 0) + ')') : null]));
    if (DATA.cxr) box.appendChild(h('div', 'say', [h('b', null, 'Scheda Candele, 21 timeframe: '), nf(DATA.cxr.all, 0) + ' confronti; robusti (controllo dei falsi positivi e stesso verso nelle due metà) – direzione ' + nf(DATA.cxr.r[0], 0) + ' su ' + nf(DATA.cxr.t[0], 0) +
      ', ritmo dell’attività ' + nf(DATA.cxr.r[1], 0) + ' su ' + nf(DATA.cxr.t[1], 0) + ' (in gran parte stagionalità della volatilità), precursori degli impulsi ' + nf(DATA.cxr.r[2], 0) + ' su ' + nf(DATA.cxr.t[2], 0) + '. Sono misure descrittive, senza costi.']));
    if (e.bs) box.appendChild(h('div', 'say', [h('b', null, 'Bias del calendario e degli impulsi: '), ent(e.bs)]));
    if (e.top && e.top.length) box.appendChild(h('figure', null, [h('figcaption', null, [h('span', 't', 'Le strategie candidate migliori'), h('span', 's', 'Scelte tra R/R e ORB; livello dopo i controlli (su quelli applicabili). Il dettaglio dei 7 controlli è nella scheda Sintesi edge.')]),
      table(['Livello', 'Fonte', 'Timeframe', 'Operazione', 'Contesto', 'Trade', 'Netta peggiore (R)', 'z netto', 'Controlli'], e.top.map(function (r) { return [r[0], ent(r[1]), r[2], ent(r[3]), ent(r[4]), nf(r[5], 0), sg(r[6], 3), sg(r[7], 1), r[8] + '/' + r[9]]; }), [0, 1, 2, 3, 4])]));
    (e.bias || []).forEach(function (b) {
      if (!b[2] || !b[2].length) return;
      box.appendChild(h('figure', null, [h('figcaption', null, [h('span', 't', ent(b[0])), h('span', 's', nf(b[1], 0) + ' robusti; qui i primi ' + b[2].length)]),
        hbars(b[2].map(function (r) { return { l: ent(r[1]), v: Math.abs(r[0]), txt: 'z ' + sg(r[0], 1), cls: r[0] >= 0 ? '' : 'neg', tip: 'z ' + sg(r[0], 1) + '\n' + ent(r[1]) }; }))]));
    });
  }

  /* ---------- file compatto per l'analisi ---------- */
  var LV = { min: 'Minimo (qualche riga per timeframe)', ess: 'Essenziale (profili e classi migliori)', full: 'Completo (tutto)' };
  function trimTf(t, lv) {
    if (lv === 'full') return t;
    var o = {}, keep = ['id', 'sec', 'n', 't0', 't1', 'span', 'bull', 'medR', 'body', 'thr', 'nimp', 'impP', 'nrob', 'tst', 'fu'];
    keep.forEach(function (k) { if (t[k] != null) o[k] = t[k]; });
    var dims = lv === 'min' ? ['hour', 'dow', 'mon'] : ['hour', 'min', 'dow', 'wom', 'mon', 'qtr', 'yr'], cols = lv === 'min' ? 7 : 17;
    o.prof = {};
    dims.forEach(function (d) { if (t.prof && t.prof[d]) o.prof[d] = { all: t.prof[d].all.slice(0, cols - 1), r: t.prof[d].r.filter(function (r) { return r[1] > 0; }).map(function (r) { return r.slice(0, cols); }) }; });
    o.freq = (t.freq || []).slice(0, lv === 'min' ? 10 : 15);
    o.clsAll = t.clsAll || (t.cls && t.cls.__all);
    var groups = t.cls || {}, cand = [];
    var mz = function (r) { var m = 0; [6, 7, 8].forEach(function (i) { if (r[i] != null && Math.abs(r[i]) > m) m = Math.abs(r[i]); }); return m; };
    if (lv === 'min') {
      Object.keys(groups).forEach(function (g) { if (g !== '__all') groups[g].forEach(function (r) { if (r[1] >= 100) cand.push(r.slice(0, 12).concat([null, null, null, null, null, g])); }); });
      cand.sort(function (a, b) { return mz(b) - mz(a); });
      o.cls = { 'Le più lontane dal caso': cand.slice(0, 12) };
    } else {
      o.cls = {};
      Object.keys(groups).forEach(function (g) {
        if (g === '__all') return;
        var rows = groups[g].slice().sort(function (a, b) { return mz(b) - mz(a); }).filter(function (r) { return mz(r) >= 1.5; }).slice(0, 5).map(function (r) { return r.slice(0, 12); });
        if (rows.length) o.cls[g] = rows;
      });
    }
    o.pre = {};
    ['up', 'dn'].forEach(function (d) {
      var P = t.pre && t.pre[d]; if (!P) return;
      var r = P.r.filter(function (q) { return q[4] != null; }).sort(function (a, b) { return Math.abs(b[4]) - Math.abs(a[4]); }).slice(0, lv === 'min' ? 6 : 12).sort(function (a, b) { return a[1] - b[1]; });
      o.pre[d] = { n: P.n, r: r };
    });
    o.top = t.top; o.rob = (t.rob || []).slice(0, lv === 'min' ? 8 : 20);
    if (lv !== 'min' && t.comp) o.comp = t.comp;
    return o;
  }
  function trimEdge(e) {
    if (!e) return e;
    var o = {};
    Object.keys(e).forEach(function (k) { o[k] = e[k]; });
    o.top = (e.top || []).slice(0, 4);
    o.bias = (e.bias || []).map(function (b) { return [b[0], b[1], b[2].slice(0, 4)]; });
    return o;
  }
  function makeDigest(ids, lv) {
    var o = { v: 1, app: 'MarketProfiler-cruscotto', level: lv, sym: DATA.sym, gen: DATA.gen, tz: DATA.tz, roll: DATA.roll, ref: DATA.ref, pg: DATA.pg, cxr: DATA.cxr, skip: DATA.skip, tfs: [], edge: lv === 'min' ? trimEdge(DATA.edge) : DATA.edge };
    ids.forEach(function (id) { var t = byId(id); if (t) o.tfs.push(trimTf(t, lv)); });
    return o;
  }
  function secFile(box) {
    var ids = DATA.tfs.map(function (t) { return t.id; });
    var presets = { main: ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1', 'W1'], all: ids, low: ids.filter(function (i) { return ['D1', 'W1', 'MN1'].indexOf(i) < 0; }), one: [ST.tf] };
    if (!ST.fp) { ST.fp = 'main'; ST.fl = 'min'; ST.sel = presets.main.filter(function (i) { return ids.indexOf(i) >= 0; }); }
    box.appendChild(h('div', 'say', [h('b', null, 'Come si usa: '), 'scegli i timeframe e il livello di dettaglio, controlla la dimensione, premi “Copia” e incolla il testo in chat: lo metto in un cruscotto come questo, con grafici e riassunti. ' +
      'Il livello “Minimo” tiene per ogni timeframe i profili di ora, giorno e mese, gli eventi più frequenti, le classi e i precursori più lontani dal caso e i confronti robusti.']));
    var ta = h('textarea', 'dg', null, { readonly: 'readonly', spellcheck: 'false', 'aria-label': 'File per l’analisi' });
    var info = h('span', 'cst'), stt = h('span', 'cst');
    var chk = h('div', 'chk');
    function refresh() {
      var sel = ids.filter(function (i) { return ST.sel.indexOf(i) >= 0; });
      var txt = JSON.stringify(makeDigest(sel, ST.fl));
      ta.value = txt;
      var kb = txt.length / 1024;
      info.textContent = nf(sel.length, 0) + ' timeframe · ' + nf(txt.length, 0) + ' caratteri (' + nf(kb, 0) + ' KB) · circa ' + nf(Math.round(txt.length / 3 / 100) * 100, 0) + ' token';
      stt.textContent = '';
    }
    function boxes() {
      while (chk.firstChild) chk.removeChild(chk.firstChild);
      ids.forEach(function (i) {
        var c = h('input', null, null, { type: 'checkbox', id: 'cxd-c-' + i }); c.checked = ST.sel.indexOf(i) >= 0;
        c.addEventListener('change', function () { ST.sel = c.checked ? ST.sel.concat([i]) : ST.sel.filter(function (x) { return x !== i; }); ST.fp = 'custom'; refresh(); });
        chk.appendChild(h('label', null, [c, i]));
      });
    }
    box.appendChild(h('div', 'bar', [
      select('fp', 'Timeframe', [['main', 'Principali (M1 M5 M15 M30 H1 H4 D1 W1)'], ['low', 'Tutti sotto il D1'], ['all', 'Tutti'], ['one', 'Solo quello scelto in alto'], ['custom', 'Scelta libera']], ST.fp, function (v) {
        ST.fp = v; if (v !== 'custom') ST.sel = presets[v].filter(function (i) { return ids.indexOf(i) >= 0; }); render();
      }),
      select('fl', 'Dettaglio', Object.keys(LV).map(function (k) { return [k, LV[k]]; }), ST.fl, function (v) { ST.fl = v; refresh(); })]));
    box.appendChild(chk); boxes();
    var cp = h('button', 'main', 'Copia', { type: 'button' });
    cp.addEventListener('click', function () {
      function done() { stt.className = 'cst ok'; stt.textContent = 'Copiato (' + nf(ta.value.length, 0) + ' caratteri). Incollalo in chat.'; }
      function fb() { ta.focus(); ta.select(); var ok = false; try { ok = document.execCommand('copy'); } catch (e) { } if (ok) done(); else { stt.className = 'cst'; stt.textContent = 'Testo selezionato: premi Ctrl+C.'; } }
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(ta.value).then(done, fb); else fb();
    });
    box.appendChild(h('div', 'bar', [cp, info, stt]));
    box.appendChild(ta);
    refresh();
  }

  /* ---------- struttura della pagina ---------- */
  function render() {
    if (!DATA) return;
    LASTW = root.clientWidth;
    while (root.firstChild) root.removeChild(root.firstChild);
    TIP = null;
    var tfOpts = TFORD.filter(function (i) { return byId(i); }).map(function (i) { var t = byId(i); return [i, i + ' · ' + nf(t.n, 0) + ' candele']; });
    if (!byId(ST.tf)) ST.tf = byId('H1') ? 'H1' : (tfOpts.length ? tfOpts[0][0] : null);
    var t = ST.tf ? byId(ST.tf) : null;
    var head = h('div', 'bar', [
      select('tf', 'Timeframe', tfOpts, ST.tf, function (v) { ST.tf = v; render(); }),
      select('sec', 'Cosa vedere', SECS, ST.sec, function (v) { ST.sec = v; render(); })]);
    root.appendChild(head);
    root.appendChild(h('p', 'cst', [h('b', null, DATA.sym || ''), ' · ' + (DATA.gen || '') + (DATA.roll ? ' · rollover ' + DATA.roll : '') + ' · ' + ent(DATA.tz || '') + '. † = robusto (controllo dei falsi positivi e stesso verso nelle due metà), § = solo controllo dei falsi positivi. Misure descrittive, senza costi.']));
    var sk = DATA.skip ? Object.keys(DATA.skip) : [];
    if (sk.length) root.appendChild(h('p', 'cst', 'Non calcolati: ' + sk.map(function (k) { return k + (DATA.skip[k] === 1 ? ' (servono dati M1)' : ' (dati insufficienti)'); }).join(', ') + '.'));
    var box = h('div');
    root.appendChild(box);
    if (ST.sec === 'edge') secEdge(box);
    else if (ST.sec === 'conf') secConf(box);
    else if (!t) box.appendChild(h('p', 'cmuted', 'Nessun timeframe nei dati.'));
    else if (ST.sec === 'sintesi') secSintesi(box, t);
    else if (ST.sec === 'quando') secQuando(box, t);
    else if (ST.sec === 'eventi') secEventi(box, t);
    else if (ST.sec === 'pattern') secPattern(box, t);
    else if (ST.sec === 'pre') secPre(box, t);
    else if (ST.sec === 'rob') secRob(box, t);
    else if (ST.sec === 'file') secFile(box);
  }

  function load(obj) {
    DATA = obj;
    DATA.tfs = (DATA.tfs || []);
    DATA.tfs.forEach(function (t) { if (t.cls && t.cls.__all) { t.clsAll = t.cls.__all; delete t.cls.__all; } });
    var keep = { tf: ST.tf, sec: ST.sec };
    ST = { tf: keep.tf, sec: keep.sec || 'sintesi' };
    render();
  }
  window.CXD = { load: load, digest: function (ids, lv) { return makeDigest(ids, lv); } };
  var el = document.getElementById('cxd-data');
  if (el && el.textContent.trim()) { try { load(JSON.parse(el.textContent)); } catch (e) { root.appendChild(h('p', 'cst', 'Dati non leggibili: ' + e.message)); } }
  if (window.ResizeObserver) { var to = null; new ResizeObserver(function () { if (Math.abs(root.clientWidth - LASTW) > 24 && root.clientWidth > 0) { clearTimeout(to); to = setTimeout(render, 120); } }).observe(root); }
})();
