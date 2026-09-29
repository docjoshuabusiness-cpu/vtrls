const { chromium } = require('/opt/node22/lib/node_modules/playwright');
(async () => {
  const file = process.argv[2], tf = process.argv[3], prefix = process.argv[4];
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 1500, height: 1000 } });
  await p.goto('file://' + file);
  await p.evaluate((tf) => { const d = document.getElementById('cx-' + tf); d.open = true; d.scrollIntoView(); }, tf);
  const boxes = await p.evaluate((tf) => {
    const d = document.getElementById('cx-' + tf);
    const hs = [...d.querySelectorAll('h3')].map(h => [h.innerText, h.getBoundingClientRect().top + window.scrollY]);
    return hs;
  }, tf);
  console.log(JSON.stringify(boxes.map(x => x[0])));
  const want = process.argv.slice(5);
  let k = 0;
  for (const w of want) {
    const y = boxes.find(x => x[0].startsWith(w));
    if (!y) { console.log('manca', w); continue; }
    await p.evaluate((y) => window.scrollTo(0, y - 10), y[1]);
    await p.screenshot({ path: prefix + (k++) + '.png' });
  }
  await b.close();
})();
