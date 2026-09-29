// Prova del cruscotto nel browser: apre la pagina di prova (out_<caso>_dash.html), percorre timeframe, sezioni e menu, cerca errori e testo sospetto.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
(async () => {
  const file = process.argv[2] || __dirname + '/out_cplant_dash.html';
  const shots = process.argv[3] || '';
  const width = +(process.argv[4] || 1300);
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: width, height: 900 } });
  const errs = [];
  p.on('pageerror', e => errs.push(String(e)));
  p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  await p.goto('file://' + file);
  await p.waitForSelector('#cxd select');
  const sizes = await p.evaluate(() => {
    const all = Array.from(document.querySelectorAll('#cxd-tf option')).map(o => o.value);
    const main = ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1', 'W1'].filter(x => all.indexOf(x) >= 0);
    const out = {};
    ['min', 'ess', 'full'].forEach(lv => { out[lv] = { main: JSON.stringify(CXD.digest(main, lv)).length, one: JSON.stringify(CXD.digest(['M15'], lv)).length, all: JSON.stringify(CXD.digest(all, lv)).length }; });
    return out;
  });
  console.log('dimensioni del file (caratteri):', JSON.stringify(sizes));
  if (process.env.DIGEST) {
    const lv = process.env.DIGEST;
    const txt = await p.evaluate((lv) => {
      const all = Array.from(document.querySelectorAll('#cxd-tf option')).map(o => o.value);
      return JSON.stringify(CXD.digest(all, lv));
    }, lv);
    fs.writeFileSync(__dirname + '/digest_' + lv + '.json', txt);
    await p.evaluate((t) => { CXD.load(JSON.parse(t)); }, txt);
    console.log('ricaricato dal file di livello', lv, txt.length);
  }
  const bad = [];
  async function check(tag) {
    const r = await p.evaluate(() => {
      const t = document.getElementById('cxd').innerText;
      const found = [];
      ['NaN', 'undefined', 'null', '[object', 'Infinity'].forEach(w => { if (t.indexOf(w) >= 0) found.push(w); });
      const svgs = document.querySelectorAll('#cxd svg').length, hb = document.querySelectorAll('#cxd .hb').length, tb = document.querySelectorAll('#cxd table').length;
      const w = document.getElementById('cxd').scrollWidth, cw = document.getElementById('cxd').clientWidth;
      return { found, len: t.length, svgs, hb, tb, over: w - cw, sw: document.documentElement.scrollWidth - document.documentElement.clientWidth };
    });
    if (r.found.length || r.len < 80 || r.over > 4 || r.sw > 4) bad.push(tag + ' ' + JSON.stringify(r));
    return r;
  }
  const opts = async (id) => p.evaluate((id) => Array.from(document.querySelectorAll('#cxd-' + id + ' option')).map(o => o.value), id);
  const setv = async (id, v) => { await p.selectOption('#cxd-' + id, v); };
  const tfs = await opts('tf');
  const secs = await opts('sec');
  console.log('timeframe', tfs.length, 'sezioni', secs.join(','));
  // sotto-menu di ogni sezione
  const subs = { quando: ['dim', 'met'], eventi: ['en', 'es'], pattern: ['grp', 'pm', 'ps', 'pn'], pre: ['pd', 'po'], rob: ['rf', 'rn'], conf: ['cm'], file: ['fp', 'fl'] };
  let n = 0;
  for (const sec of secs) {
    await setv('sec', sec);
    for (const tf of (sec === 'edge' || sec === 'conf' ? [tfs[0]] : tfs)) {
      await setv('tf', tf);
      await check(sec + '/' + tf); n++;
      for (const sid of (subs[sec] || [])) {
        const ov = await opts(sid);
        for (const v of ov) {
          await setv(sid, v);
          await check(sec + '/' + tf + '/' + sid + '=' + v); n++;
        }
        if (ov.length) await setv(sid, ov[0]);
      }
    }
  }
  console.log('controlli', n, 'anomalie', bad.length);
  bad.slice(0, 15).forEach(x => console.log('  ', x));
  console.log('errori pagina', JSON.stringify(errs.slice(0, 5)));
  if (shots) {
    fs.mkdirSync(shots, { recursive: true });
    const snap = async (name, sec, tf, extra) => {
      await setv('sec', sec); if (tf) await setv('tf', tf);
      if (extra) for (const k in extra) { try { await p.selectOption('#cxd-' + k, extra[k], { timeout: 1500 }); } catch (e) { } }
      await p.waitForTimeout(150);
      const el = await p.$('#cxd');
      await el.screenshot({ path: shots + '/' + name + '.png' });
    };
    await snap('1_sintesi', 'sintesi', 'M15');
    await snap('2_quando', 'quando', 'M15', { dim: 'hour', met: 'rng' });
    await snap('3_quando_dow', 'quando', 'H1', { dim: 'dow', met: 'bull' });
    await snap('4_eventi', 'eventi', 'M15', { en: '10' });
    await snap('5_pattern', 'pattern', 'M15', { grp: 'Pattern con nome' });
    await snap('6_pre', 'pre', 'M15', { pd: 'up' });
    await snap('7_rob', 'rob', 'M15');
    await snap('8_conf', 'conf', 'M15', { cm: 'rng' });
    await snap('9_edge', 'edge', 'M15');
    await snap('10_file', 'file', 'M15');
  }
  await b.close();
})();
