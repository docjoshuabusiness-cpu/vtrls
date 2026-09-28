const fs=require('fs'); const {mpApply}=require('./patches.js');
const src=fs.readFileSync('mini_orig.mq5','utf8'); const mod=fs.readFileSync('../MarketProfilerEdge.mqh','utf8');
const r=mpApply(src,mod);
console.log('ok',r.ok, r.already||''); r.results.forEach(x=>console.log(x.id,x.status,x.count,x.name));
if(r.ok){ fs.writeFileSync('/tmp/mini_out.mq5',r.text);
  const lines=r.text.split('\n'); const i0=lines.findIndex(l=>l.includes('bool Analyze')); console.log(lines.slice(i0-2).join('\n').replace(/\n{3,}/g,'\n'));
  console.log('--- righe', src.split('\n').length,'->',lines.length);
  // seconda applicazione deve essere rifiutata
  const r2=mpApply(r.text,mod); console.log('seconda applicazione rifiutata:', r2.already===true);
  // CRLF
  const r3=mpApply(src.replace(/\n/g,'\r\n'),mod); console.log('CRLF ok:', r3.ok);
}
