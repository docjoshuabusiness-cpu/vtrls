#!/usr/bin/env python3
# Rigenera MarketProfilerEdge_patch.html: modulo (Edge + Candele) e punti di aggancio (patches.js) dentro la pagina esistente
import re, os
d = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(d, '..')
page_p = os.path.join(root, 'MarketProfilerEdge_patch.html')
page = open(page_p, encoding='utf-8').read()
mod = open(os.path.join(root, 'MarketProfilerEdge.mqh'), encoding='utf-8').read() + '\n\n' + open(os.path.join(root, 'MarketProfilerCandle.mqh'), encoding='utf-8').read()
patches = open(os.path.join(d, 'patches.js'), encoding='utf-8').read()
assert '</script' not in mod
a = page.index('<script type="text/plain" id="modsrc">') + len('<script type="text/plain" id="modsrc">')
b = page.index('</script>', a)
page = page[:a] + mod + page[b:]
# blocco dei punti di aggancio: dal commento 'Patch di MarketProfiler.mq5' alla riga module.exports
a = page.index('// Patch di MarketProfiler.mq5')
b = page.index("if (typeof module !== 'undefined')", a)
b = page.index('\n', b) + 1
pa = patches.index('// Patch di MarketProfiler.mq5')
pb = patches.index("if (typeof module !== 'undefined')", pa)
pb = patches.index('\n', pb) + 1
page = page[:a] + patches[pa:pb] + page[b:]
page = page.replace('<h1>MarketProfiler Edge</h1>', '<h1>MarketProfiler Edge e Candele</h1>')
page = page.replace('Incolla il file, applica, copia il risultato.</p>',
    'In pi&ugrave; la scheda <b>Candele</b>: tutti i 21 timeframe da M1 a MN1 (forme, pattern con nome, coppie e terne di candele, stati ADX, VWAP, z-score, volume all\'ora, volatilit&agrave;, posizione rispetto ad alti e bassi precedenti, orari, giorni, mesi, impulsi e cosa li precede). Incolla il file, applica, copia il risultato.</p>')
page = page.replace('<li><b>Nuove schede</b> nel report HTML: <i>Sintesi edge</i> (si apre per prima), <i>Bias e impulsi</i>, e i testi da copiare corrispondenti. Nessun nuovo parametro.</li>',
    '<li><b>Nuove schede</b> nel report HTML: <i>Sintesi edge</i> (si apre per prima), <i>Bias e impulsi</i>, <i>Candele</i>, e i testi da copiare corrispondenti. Nuovi parametri: <b>Candele</b>, <b>Candele: anni</b> e <b>InpEdRefCostBp</b>. Nuovi file: <code>MarketProfiler_&lt;simbolo&gt;_candele.csv</code> e <code>_orari_candele.csv</code>.</li>')
open(page_p, 'w', encoding='utf-8').write(page)
print('pagina rigenerata', len(page), 'caratteri')
