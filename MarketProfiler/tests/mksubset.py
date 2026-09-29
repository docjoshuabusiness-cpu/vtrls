#!/usr/bin/env python3
# Estrae dal MarketProfiler.mq5 completo le funzioni originali usate dal modulo Candele (per il banco di prova)
import re, sys
src = open(sys.argv[1], encoding='utf-8').read().split('\n')
names = ['NthSunday', 'LastSunday', 'IsUSDST', 'IsEUDST', 'DataOffset', 'DataToNY7', 'RollPre', 'RollPost', 'RollWin', 'RollIn', 'RollHit7',
         'HM', 'RollTxt', 'RollInC', 'LowerBound', 'CN', 'MktOffset', 'TZName']
out = []
for nm in names:
    pat = re.compile(r'^(?:[A-Za-z_][\w<>&\*]*[ \t]+)+' + nm + r'[ \t]*\(')
    idx = [i for i, l in enumerate(src) if pat.match(l)]
    if len(idx) != 1:
        raise SystemExit('funzione %s trovata %d volte' % (nm, len(idx)))
    i = idx[0]
    depth = 0
    started = False
    j = i
    buf = []
    while True:
        line = src[j]
        buf.append(line)
        # ignora stringhe e commenti di riga
        t = re.sub(r'"(\\.|[^"\\])*"', '""', line)
        t = re.sub(r'//.*$', '', t)
        depth += t.count('{') - t.count('}')
        if '{' in t:
            started = True
        if started and depth == 0:
            break
        if not started and t.rstrip().endswith(';'):
            break
        j += 1
    out.append('\n'.join(buf))
open(sys.argv[2], 'w').write('\n\n'.join(out) + '\n')
print('estratte', len(names), 'funzioni')
