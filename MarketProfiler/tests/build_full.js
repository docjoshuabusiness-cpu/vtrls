// Costruisce il MarketProfiler.mq5 completo: il file originale (../originale/MarketProfiler.mq5) + modulo Edge + modulo Candele + punti di aggancio
const fs = require('fs');
const path = require('path');
const { mpApply } = require('./patches.js');
const dir = __dirname;
const src = fs.readFileSync(process.argv[2] || path.join(dir, '..', 'originale', 'MarketProfiler.mq5'), 'utf8');
const mod = fs.readFileSync(path.join(dir, '..', 'MarketProfilerEdge.mqh'), 'utf8') + '\n\n' + fs.readFileSync(path.join(dir, '..', 'MarketProfilerCandle.mqh'), 'utf8') + '\n\n' + fs.readFileSync(path.join(dir, '..', 'MarketProfilerDash.mqh'), 'utf8');
const r = mpApply(src, mod);
if (!r.ok) {
  r.results.forEach(x => console.log(x.id, x.status, x.count, x.name));
  process.exit(1);
}
const out = process.argv[3] || path.join(dir, '..', 'MarketProfiler.mq5');
fs.writeFileSync(out, r.text);
console.log('scritto', out, r.text.split('\n').length, 'righe', r.text.length, 'caratteri');
