import csv, sys
tol = float(sys.argv[1]) if len(sys.argv) > 1 else 0.025
def rd(f): return list(csv.DictReader(open(f)))
eo = rd('mdrb_ea_orders.csv'); so = rd('mdrb_sc_orders.csv')
# EA: due ordini (buy stop + sell stop) per coppia, alla stessa ora
ea_pairs = {}
for r in eo:
    d = ea_pairs.setdefault(r['t'], {})
    d['buy' if r['type'] == '4' else 'sell'] = float(r['price'])
sc_pairs = {r['t']: (float(r['buy']), float(r['sell'])) for r in so}
import os
_cut = open('mdrb_meta.txt').read().strip() if os.path.exists('mdrb_meta.txt') else '9999'
sc_pairs = {t:v for t,v in sc_pairs.items() if t <= _cut}
import os
cut = open('mdrb_meta.txt').read().strip() if os.path.exists('mdrb_meta.txt') else '9999'
lastp = min(max(sc_pairs) if sc_pairs else '', cut)
ea_pairs = {t:v for t,v in ea_pairs.items() if t <= lastp}
import time as _t, calendar as _c
first2 = _t.strftime('%Y.%m.%d %H:%M', _t.gmtime(_c.timegm(_t.strptime(min(sc_pairs), '%Y.%m.%d %H:%M')) + 2*86400)) if sc_pairs else ''
ea_pairs = {t:v for t,v in ea_pairs.items() if t >= first2}
sc_pairs = {t:v for t,v in sc_pairs.items() if t >= first2}
common = set(ea_pairs) & set(sc_pairs)
import time as _tt, calendar as _cc
def _ts(x): return _cc.timegm(_tt.strptime(x, '%Y.%m.%d %H:%M'))
_et = list(csv.DictReader(open('mdrb_ea_trades.csv')))
_iv = [(_ts(r['topen']), _ts(r['tclose'])) for r in _et]
_eap = sorted(_ts(t) for t in ea_pairs)
def busy_explained(t):
    tt = _ts(t)
    if any(a <= tt < b for a, b in _iv): return True
    return any(0 < tt - p <= 8*3600 for p in _eap)      # coppia dell'EA ancora viva (finestra a cavallo)
def replace_explained(t):
    tt = _ts(t)
    return any(0 <= tt - b <= 24*3600 for a, b in _iv)
only_ea_all = sorted(set(ea_pairs) - set(sc_pairs)); only_ea = [t for t in only_ea_all if not replace_explained(t)]
n_repl = len(only_ea_all) - len(only_ea)
only_sc_all = sorted(set(sc_pairs) - set(ea_pairs))
only_sc = [t for t in only_sc_all if not busy_explained(t)]
n_busy = len(only_sc_all) - len(only_sc)
bad = [t for t in common if abs(ea_pairs[t]['buy'] - sc_pairs[t][0]) > 1e-9 or abs(ea_pairs[t]['sell'] - sc_pairs[t][1]) > 1e-9]
print(f"PIAZZAMENTI  EA {len(ea_pairs)}  studio {len(sc_pairs)}  comuni {len(common)}  solo-EA {len(only_ea)}  solo-studio {len(only_sc)} (+{n_busy} con posizione EA aperta: regola) solo-EA spiegati da ripiazzamento: {n_repl}  prezzi diversi {len(bad)}")
for t in only_ea[:4]: print("  solo-EA", t)
for t in only_sc[:4]: print("  solo-studio", t)
for t in bad[:4]: print("  prezzi", t, ea_pairs[t], sc_pairs[t])
et = rd('mdrb_ea_trades.csv'); st = rd('mdrb_sc_trades.csv')
ea_t = {r['topen']: (int(r['dir']), float(r['R'])) for r in et if first2 <= r['topen'] <= _cut}
sc_t = {r['tfill']: (int(r['dir']), float(r['R'])) for r in st if first2 <= r['tfill'] <= _cut}
def _near(k, dct):
    t0 = _ts(k)
    for dm in (0, 60, -60):
        kk = _tt.strftime('%Y.%m.%d %H:%M', _tt.gmtime(t0 + dm))
        if kk in dct: return kk
    return None
_map = {}
for k in list(ea_t):
    n = _near(k, sc_t)
    if n is not None: _map[k] = n
_used = set(_map.values())
com = set(_map)
dd = [t for t in com if ea_t[t][0] != sc_t[_map[t]][0]]
dr = sorted([(abs(ea_t[t][1] - sc_t[_map[t]][1]), t) for t in com if ea_t[t][0] == sc_t[_map[t]][0]], reverse=True)
big = [x for x in dr if x[0] > tol]
print(f"TRADE        EA {len(ea_t)}  studio {len(sc_t)}  comuni {len(com)}  solo-EA {len(set(ea_t)-set(_map))}  solo-studio {len(set(sc_t)-_used)}  direzione diversa {len(dd)}  |dR|>{tol}: {len(big)}  max|dR| {dr[0][0] if dr else 0:.4f}")
for t in sorted(set(ea_t) - set(_map))[:4]: print("  solo-EA", t, ea_t[t])
for t in sorted(set(sc_t) - _used)[:4]: print("  solo-studio", t, sc_t[t])
for d_, t in big[:6]: print(f"  dR {d_:.4f}  {t}  EA {ea_t[t]}  studio {sc_t[_map[t]]}")
ok = (not only_ea and not only_sc and not bad and not dd and not big and set(ea_t) == set(_map) and set(sc_t) == _used)
print("ESITO:", "OK" if ok else "DIFFERENZE")
sys.exit(0 if ok else 1)
