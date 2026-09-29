#!/usr/bin/env python3
# Genera la pagina da cui copiare il MarketProfiler.mq5 completo (textarea con il codice, pulsante Copia tutto, controllo del numero di caratteri)
import sys, os, re
d = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(d, '..', 'MarketProfiler.mq5'), encoding='utf-8').read()
out = sys.argv[1]
tpl = open(sys.argv[2], encoding='utf-8').read()   # pagina precedente come modello
n_lines = src.count('\n')
n_chars = len(src)
esc = src.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
a = tpl.index('<textarea id="src"')
a = tpl.index('>', a) + 1
b = tpl.index('</textarea>')
page = tpl[:a] + esc + tpl[b:]
page = re.sub(r'MarketProfiler\.mq5 con il modulo Edge [\d.]+ gi&agrave; integrato &middot; \d+ righe &middot; solo ASCII',
              'MarketProfiler.mq5 con i moduli Edge 1.2 e Candele gi&agrave; integrati &middot; %d righe &middot; solo ASCII' % n_lines, page)
page = re.sub(r'Il codice ha \d+ righe\.', 'Il codice ha %d righe.' % n_lines, page)
page = re.sub(r'var EXP_LINES=\d+, EXP_CHARS=\d+;', 'var EXP_LINES=%d, EXP_CHARS=%d;' % (n_lines, n_chars), page)
page = re.sub(r'<p class="note">.*?</p>',
              '<p class="note">Novit&agrave;: scheda <b>Candele</b> su tutti i 21 timeframe (M1-MN1): forme, pattern con nome, coppie e terne di candele, serie, stati ADX/VWAP/z-score/volume all\'ora/volatilit&agrave;, '
              'posizione rispetto ad alti e bassi precedenti (candela prima, 20 candele, ora, 4 ore, giorno, settimana, mese), orari, giorni, mesi, impulsi e cosa li precede; due file CSV. '
              'Nuovi parametri: <b>Candele</b> e <b>Candele: anni</b>.</p>', page, count=1, flags=re.S)
open(out, 'w', encoding='utf-8').write(page)
print('scritto', out, len(page), 'caratteri;', n_lines, 'righe;', n_chars, 'caratteri di codice')
