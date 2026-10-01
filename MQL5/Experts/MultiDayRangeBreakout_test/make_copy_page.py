#!/usr/bin/env python3
# Genera la pagina da cui copiare MultiDayRangeBreakout.mq5 (riquadro con il codice, pulsante Copia tutto, controllo del numero di caratteri).
# Uso: python3 make_copy_page.py pagina.html
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, '..', 'MultiDayRangeBreakout.mq5'), encoding='utf-8').read()
n_lines, n_chars = src.count('\n'), len(src)
esc = src.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
page = r'''<title>MultiDayRangeBreakout</title>
<style>
:root{
  --bg:#f5f6f8; --fg:#1b2230; --muted:#5a6578; --line:#d5d9e1; --panel:#ffffff;
  --code-bg:#fbfbfd; --code-fg:#1b2230; --accent:#1f5fd6; --accent-fg:#ffffff; --ok:#0f7a4a;
  --sans:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
  --mono:ui-monospace,"Cascadia Mono",Consolas,"DejaVu Sans Mono",monospace;
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --bg:#0e131b; --fg:#e6e9ef; --muted:#93a0b5; --line:#263041; --panel:#151c27;
  --code-bg:#0b1017; --code-fg:#dfe4ee; --accent:#5b93f5; --accent-fg:#08111f; --ok:#4cc38a; color-scheme:dark}}
:root[data-theme="dark"]{
  --bg:#0e131b; --fg:#e6e9ef; --muted:#93a0b5; --line:#263041; --panel:#151c27;
  --code-bg:#0b1017; --code-fg:#dfe4ee; --accent:#5b93f5; --accent-fg:#08111f; --ok:#4cc38a; color-scheme:dark}
body{background:var(--bg);color:var(--fg);font-family:var(--sans);font-size:15px;line-height:1.55;
  margin:0;padding-inline:16px;padding-block:20px}
.wrap{max-width:1100px;margin-inline:auto;display:flex;flex-direction:column;gap:16px;min-width:0}
h1{font-size:22px;line-height:1.25;margin:0;text-wrap:balance}
.meta{color:var(--muted);margin:2px 0 0;font-size:13px}
ol{margin:0;padding-left:20px;display:flex;flex-direction:column;gap:4px;max-width:70ch}
.note{color:var(--muted);font-size:13px;margin:0;max-width:70ch}
.box{background:var(--panel);border:1px solid var(--line);border-radius:10px;overflow:hidden;min-width:0}
.bar{display:flex;flex-wrap:wrap;align-items:center;gap:10px;padding:10px 12px;border-bottom:1px solid var(--line)}
button{font:inherit;font-weight:600;cursor:pointer;border-radius:8px;border:1px solid var(--line);
  background:var(--panel);color:var(--fg);padding:8px 14px}
button.main{background:var(--accent);color:var(--accent-fg);border-color:var(--accent)}
button:focus-visible,textarea:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
#st{font-size:13px;color:var(--muted)}
#st.ok{color:var(--ok);font-weight:600}
textarea{display:block;width:100%;box-sizing:border-box;height:62vh;min-height:320px;resize:vertical;border:0;
  background:var(--code-bg);color:var(--code-fg);font-family:var(--mono);font-size:12px;line-height:1.45;
  padding:12px;white-space:pre;overflow:auto;tab-size:3}
</style>
<div class="wrap">
  <div>
    <h1>MultiDayRangeBreakout 3.00</h1>
    <p class="meta">Expert Advisor MQL5 &middot; riscrittura della v2.00 &middot; @@LINES@@ righe &middot; solo ASCII</p>
  </div>
  <ol>
    <li>Premi <b>Copia tutto</b>.</li>
    <li>In MetaEditor apri (o crea) <code>MultiDayRangeBreakout.mq5</code> nella cartella <code>MQL5\Experts</code>, seleziona tutto (Ctrl+A) e incolla (Ctrl+V).</li>
    <li>Compila con F7. Se segnala errori, incollami le righe con il numero di riga.</li>
  </ol>
  <p class="note">Gli orari sono ora server del broker. Le distanze sono in punti del simbolo (su un cambio a 5 cifre 10 punti = 1 pip). Non &egrave; stato compilato con MetaEditor: la logica &egrave; stata provata in C++ contro un MT5 simulato.</p>
  <div class="box">
    <div class="bar">
      <button class="main" id="cp" type="button">Copia tutto</button>
      <button id="sel" type="button">Seleziona tutto</button>
      <span id="st" role="status">Il codice ha @@LINES@@ righe.</span>
    </div>
    <textarea id="src" readonly spellcheck="false" wrap="off" aria-label="Codice di MultiDayRangeBreakout.mq5">@@CODE@@</textarea>
  </div>
</div>
<script>
(function(){
  var ta=document.getElementById('src'), st=document.getElementById('st');
  var EXP_LINES=@@LINES@@, EXP_CHARS=@@CHARS@@;
  function lines(){var v=ta.value;return v.split('\n').length-(v.endsWith('\n')?1:0);}
  function done(){
    var okc=ta.value.length===EXP_CHARS;
    st.className='ok';
    st.textContent=okc?('Copiate '+lines()+' righe. Ora incolla in MetaEditor.'):('Copia completata, ma il testo ha '+ta.value.length+' caratteri invece di '+EXP_CHARS+': riprova.');
  }
  function fallback(){
    ta.focus();ta.select();
    var ok=false;try{ok=document.execCommand('copy');}catch(e){}
    if(ok)done();else{st.className='';st.textContent='Il browser non permette la copia automatica: il testo è selezionato, premi Ctrl+C.';}
  }
  document.getElementById('cp').onclick=function(){
    if(navigator.clipboard&&navigator.clipboard.writeText){
      navigator.clipboard.writeText(ta.value).then(done,fallback);
    }else fallback();
  };
  document.getElementById('sel').onclick=function(){ta.focus();ta.select();st.className='';st.textContent='Selezionato: premi Ctrl+C.';};
})();
</script>
'''
page = page.replace('@@LINES@@', str(n_lines)).replace('@@CHARS@@', str(n_chars)).replace('@@CODE@@', esc)
open(sys.argv[1], 'w', encoding='utf-8').write(page)
print('scritto', sys.argv[1], len(page), 'caratteri;', n_lines, 'righe;', n_chars, 'caratteri di codice')
