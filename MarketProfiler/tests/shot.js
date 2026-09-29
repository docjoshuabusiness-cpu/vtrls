const { chromium } = require('/opt/node22/lib/node_modules/playwright');
(async () => {
  const file = process.argv[2], out = process.argv[3];
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 1500, height: 1000 } });
  const errs = [];
  p.on('pageerror', e => errs.push(String(e)));
  p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  await p.goto('file://' + file);
  const nDet = await p.evaluate(() => document.querySelectorAll('details').length);
  const nTab = await p.evaluate(() => document.querySelectorAll('table').length);
  const nTr = await p.evaluate(() => document.querySelectorAll('tr').length);
  const bad = await p.evaluate(() => {
    // celle per riga diverse dall'intestazione
    let bad = 0, samples = [];
    document.querySelectorAll('table').forEach(t => {
      const hc = t.querySelector('thead tr') ? t.querySelector('thead tr').children.length : 0;
      t.querySelectorAll('tbody tr').forEach(r => {
        if (r.classList.contains('grp')) return;
        let cells = 0; for (const c of r.children) cells += (c.colSpan || 1);
        if (hc && cells !== hc) { bad++; if (samples.length < 5) samples.push(hc + ' vs ' + cells + ': ' + r.innerText.slice(0, 80)); }
      });
    });
    return { bad, samples };
  });
  console.log('details', nDet, 'tabelle', nTab, 'righe', nTr, 'righe con colonne sfalsate', bad.bad, JSON.stringify(bad.samples));
  console.log('errori pagina', JSON.stringify(errs));
  await p.evaluate(() => { document.querySelectorAll('details').forEach((d, i) => { if (i < 1) d.open = true; }); });
  await p.screenshot({ path: out, fullPage: false });
  const h = await p.evaluate(() => document.body.scrollHeight);
  console.log('altezza', h);
  await b.close();
})();
