// Produce il file compatto (come il pulsante Copia del cruscotto) da una pagina di prova: node mkdigest.js pagina.html livello M1,M5,... uscita.json
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
(async () => {
  const [file, lv, ids, out] = process.argv.slice(2);
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage();
  await p.goto('file://' + require('path').resolve(file));
  await p.waitForSelector('#cxd select');
  const txt = await p.evaluate(([lv, ids]) => JSON.stringify(CXD.digest(ids.split(','), lv)), [lv, ids]);
  fs.writeFileSync(out, txt);
  console.log('scritto', out, txt.length, 'caratteri');
  await b.close();
})();
