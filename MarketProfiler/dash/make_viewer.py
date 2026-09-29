#!/usr/bin/env python3
# Costruisce la pagina "Cruscotto candele" (viewer.html + dash.css + dash.js + dati) da pubblicare come Artifact.
# Uso: python3 dash/make_viewer.py file_compatto.json pagina.html
#   file_compatto.json = il testo copiato dal pulsante Copia del cruscotto (o un JSON di prova con "demo": true per mostrare l'avviso dei dati di esempio)
import json, os, sys

here = os.path.dirname(os.path.abspath(__file__))
src, out = sys.argv[1], sys.argv[2]
data = json.load(open(src, encoding='utf-8'))
if data.get('app') != 'MarketProfiler-cruscotto' or not isinstance(data.get('tfs'), list):
    sys.exit('il file non e\' un file del cruscotto MarketProfiler')
txt = json.dumps(data, ensure_ascii=True, separators=(',', ':')).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
tpl = open(os.path.join(here, 'viewer.html'), encoding='utf-8').read()
css = open(os.path.join(here, 'dash.css'), encoding='utf-8').read()
js = open(os.path.join(here, 'dash.js'), encoding='utf-8').read()
for nm, t in (('css', css), ('js', js)):
    if '</' + 'script' in t.lower() or '</' + 'style' in t.lower():
        sys.exit(nm + ' contiene una chiusura di tag')
page = tpl.replace('/*DATA*/', txt).replace('/*CSS*/', css).replace('/*JS*/', js)
open(out, 'w', encoding='utf-8').write(page)
print('scritto', out, len(page), 'caratteri; dati', len(txt), 'timeframe', ','.join(t['id'] for t in data['tfs']))
