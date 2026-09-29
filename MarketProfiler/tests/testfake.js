const { chromium } = require('/opt/node22/lib/node_modules/playwright');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 1400, height: 900 } });
  const errs = []; p.on('pageerror', e => errs.push(String(e))); p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); });
  await p.goto('file://' + __dirname + '/out_fake_report.html');
  await p.waitForTimeout(500);
  const info = async () => p.evaluate(() => { const r = document.getElementById('cxd'); const s = r.querySelector('svg'); return { vis: !r.closest('.tab').hidden, w: r.clientWidth, svgw: s ? s.getBoundingClientRect().width : null, hash: location.hash }; });
  console.log('avvio', JSON.stringify(await info()));
  await p.click("nav button[data-tab='edge']"); console.log('edge', JSON.stringify(await info()));
  await p.click("nav button[data-tab='dash']"); await p.waitForTimeout(400); console.log('dash', JSON.stringify(await info()));
  await p.screenshot({ path: process.argv[2] || '/tmp/fake.png' });
  console.log('errori', JSON.stringify(errs));
  await b.close();
})();
