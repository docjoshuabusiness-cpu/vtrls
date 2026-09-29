// Punti di aggancio sul file originale vero: ognuno deve comparire una sola volta; seconda applicazione rifiutata; fine riga CRLF accettata
const fs = require('fs');
const path = require('path');
const { mpApply } = require('./patches.js');
const src = fs.readFileSync(path.join(__dirname, '..', 'originale', 'MarketProfiler.mq5'), 'utf8');
const mod = fs.readFileSync(path.join(__dirname, '..', 'MarketProfilerEdge.mqh'), 'utf8') + '\n\n' + fs.readFileSync(path.join(__dirname, '..', 'MarketProfilerCandle.mqh'), 'utf8');
const r = mpApply(src, mod);
console.log('ok', r.ok, r.already || '');
r.results.forEach(x => console.log(x.id, x.status, x.count, x.name));
if (r.ok) {
  const full = fs.readFileSync(path.join(__dirname, '..', 'MarketProfiler.mq5'), 'utf8');
  console.log('uguale al file completo del repository:', r.text === full);
  const r2 = mpApply(r.text, mod);
  console.log('seconda applicazione rifiutata:', r2.already === true);
  const r3 = mpApply(src.replace(/\n/g, '\r\n'), mod);
  console.log('CRLF ok:', r3.ok);
}
