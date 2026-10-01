#!/usr/bin/env python3
# Prova di sensibilita': introduce un guasto alla volta nell'EA e controlla che almeno una prova fallisca.
import subprocess, sys, os, re, shutil
here = os.path.dirname(os.path.abspath(__file__))
os.chdir(here)
src = open('../MultiDayRangeBreakout.mq5', encoding='utf-8').read()
T = '../../../MarketProfiler/tests/translate.py'
FL = ['-std=c++17', '-O2', '-Wno-unused-parameter', '-Wno-sign-compare']
M = [
 ('niente OCO (l\'ordine gemello resta)', 'life', 'if(g_nPos > 0)\n     {\n      DeleteOurPendings("OCO: una posizione e\' aperta");\n      return;\n     }', ''),
 ('niente cancellazione degli ordini scaduti da parte dell\'EA', 'expiry', 'if(!OrdersMayLive(now))\n      DeleteOurPendings("fuori dalla finestra");', 'now = now;'),
 ('range sbagliato di un giorno (come la v2)', 'range', 'iTime(_Symbol, PERIOD_D1, RangeDaysBack - 1);\n            if(nextDay == 0)', 'iTime(_Symbol, PERIOD_D1, RangeDaysBack);\n            if(nextDay == 0)'),
 ('contatori non riletti dalla storia dopo il riavvio', 'restart', '   if(changed)\n      RefreshFromHistory(now);', '   if(false)\n      RefreshFromHistory(now);'),
 ('filtro di spread spento', 'spread', 'if(lim > 0.0 && spr > lim)', 'if(false)'),
 ('prezzo gia\' oltre il livello: piazza comunque', 'chase', 'if(!ChaseIfBroken)\n        {', 'if(false)\n        {'),
 ('trailing senza passo minimo', 'manage', 'MathMax(ts, TrailingStep * _Point)', 'ts'),
 ('break even dal prezzo sbagliato (ingresso -10 invece di +10)', 'manage', 'entry + BreakEvenOffset * _Point : entry - BreakEvenOffset * _Point', 'entry - BreakEvenOffset * _Point : entry + BreakEvenOffset * _Point'),
 ('massimo di posizioni al giorno ignorato', 'random', 'if(g_tradesToday >= MaxTradesPerDay)\n      return;', ''),
]
bad = 0
for name, test, old, new in M:
    if old not in src:
        print('MANCA IL PUNTO DA GUASTARE:', name); bad += 1; continue
    open('mut.mq5', 'w', encoding='utf-8').write(src.replace(old, new, 1))
    subprocess.run(['python3', T, 'gen_v3.cpp', 'mut.mq5'], check=True)
    r = subprocess.run(['g++'] + FL + ['-o', 't_mut', 'driver.cpp'], capture_output=True, text=True)
    if r.returncode:
        print('NON COMPILA:', name, r.stderr[:300]); bad += 1; continue
    p = subprocess.run(['./t_mut', test], capture_output=True, text=True)
    caught = p.returncode != 0
    print(('RILEVATO   ' if caught else 'NON RILEVATO'), '|', name, '| prova', test)
    if not caught: bad += 1
# ripristina i file generati dall'EA vero
subprocess.run(['python3', T, 'gen_v3.cpp', '../MultiDayRangeBreakout.mq5'], check=True)
for f in ('mut.mq5', 't_mut'):
    if os.path.exists(f): os.remove(f)
print('guasti non rilevati:', bad)
sys.exit(1 if bad else 0)
