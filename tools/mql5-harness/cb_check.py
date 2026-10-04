#!/usr/bin/env python3
"""Verifica indipendente della Parte A (rotture a candela chiusa): ricalcola da m1.csv, in Python, range, candele del TF,
prima chiusura fuori, k, ingresso e gli R di tutte le combinazioni SL x RR, e li confronta con gli eventi esportati dallo script."""
import csv, math, sys, collections
w_idx, t_idx = int(sys.argv[1]), int(sys.argv[2])
spread_pts = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
pt = 1e-5; S = spread_pts * pt; tol = pt * 0.001
TFS = [60, 300, 900, 1800, 3600, 7200, 10800]; sec = TFS[t_idx]
durs = [1, 2, 3, 4, 6, 8, 12]
wins = [(s, d) for d in durs for s in range(0, 24) if s + d <= 23]
ws, wd = wins[w_idx]
T, O, H, L, C = [], [], [], [], []
for ln in open("m1.csv"):
    t, o, h, l, c, sp = ln.strip().split(",")
    T.append(int(t)); O.append(float(o)); H.append(float(h)); L.append(float(l)); C.append(float(c))
n = len(T)
import bisect
def lower(t): return bisect.bisect_left(T, t)
rows = list(csv.DictReader(open("out/MQL5/Files/MDRB_Study_EURUSD_cb_events_debug.csv")))
if rows:
    med = float(rows[0]["med_pts"]); slf = [float(rows[0][f"sl{i}"]) for i in range(6)]
else:
    med = 100.0; slf = [25.0, 50.0, 75.0, 100.0, 150.0, 200.0]     # nessun evento atteso: i valori non servono
buf = max(1.0, round(0.05 * med))
# candele del TF
cand = collections.OrderedDict()
for i in range(n):
    day = T[i] - T[i] % 86400
    bk = day + ((T[i] - day) // sec) * sec
    if bk not in cand: cand[bk] = [H[i], L[i], C[i]]
    else:
        c = cand[bk]; c[0] = max(c[0], H[i]); c[1] = min(c[1], L[i]); c[2] = C[i]
ctimes = list(cand.keys())
def sim(j0, d, E0, SLd, TPd, Lh):
    slu = -SLd
    for j in range(Lh):
        o, h, l, c = O[j0 + j], H[j0 + j], L[j0 + j], C[j0 + j]
        uO = d * (o - E0) - S
        if uO <= slu + tol: return uO / SLd
        if uO >= TPd - tol: return uO / SLd
        F, A = (h - E0, l - E0) if d > 0 else (E0 - l, E0 - h)
        hs = (A - S) <= slu + tol; ht = (F - S) >= TPd - tol
        if hs: return slu / SLd            # stop prima (anche se entrambi: ordine pessimista)
        if ht: return TPd / SLd
    return ((d * (C[j0 + Lh - 1] - E0) - S)) / SLd
L4 = 240; L24 = 1440
exp = {}
first_day = T[0] - T[0] % 86400
last = T[-1]
nD = 0
days = sorted(set(t - t % 86400 for t in T))
for D in days[:-1]:               # lo script esclude l'ultimo giorno D1 (potrebbe essere incompleto)
    if D > last: break
    dow = (D // 86400 + 4) % 7          # 0 = domenica
    if dow in (0, 6): continue
    rs0 = D + ws * 3600; re0 = rs0 + wd * 3600
    ja, jb = lower(rs0), lower(re0)
    if jb - ja < max(1, int(0.6 * wd * 3600 / 60)): continue
    hi = max(H[ja:jb]); lo = min(L[ja:jb])
    if not (hi > lo) or lo <= 0: continue
    if (hi - lo) < 2.0 * S: continue
    endDay = D + 86400
    ci = bisect.bisect_left(ctimes, re0)
    k = 0; hit = None
    for q in range(ci, len(ctimes)):
        ct = ctimes[q]
        if ct + sec > endDay: break
        if ct < re0: continue
        k += 1
        cc = cand[ct][2]
        if cc > hi: hit = (ct, 1); break
        if cc < lo: hit = (ct, -1); break
    if hit is None: continue
    ct, d = hit
    tc = ct + sec; j0 = lower(tc)
    if j0 + L4 >= n: continue
    E0 = cand[ct][2]; edge = hi if d > 0 else lo
    edgeDist = d * (E0 - edge) / pt
    slEdge = max(max(edgeDist + buf, max(5.0, 4.0 * S / pt)), 0)
    Lh = min(L24, n - j0 - 1)
    res = []
    for i in range(7):
        slp = slf[i] if i < 6 else slEdge
        for m in range(3):
            res.append(sim(j0, d, E0, slp * pt, (m + 1) * slp * pt, Lh))
    exp[(D, k, d)] = (hi, lo, E0, tc, res)
got = {}
import time
for r in rows:
    day = time.mktime(time.strptime(r["day"], "%Y.%m.%d")) 
for r in rows:
    # giorno -> epoch UTC
    import calendar
    D = calendar.timegm(time.strptime(r["day"], "%Y.%m.%d"))
    R = [float(r[f"R_s{i}_m{m}"]) for i in range(7) for m in (1, 2, 3)]
    got[(D, int(r["k"]), int(r["dir"]))] = (float(r["range_hi"]), float(r["range_lo"]), float(r["close"]), R)
bad = 0
for key in set(exp) | set(got):
    if key not in exp or key not in got:
        bad += 1
        if bad <= 8: print("EVENTO diverso", key, "py" if key in exp else "-", "script" if key in got else "-")
        continue
    e, g = exp[key], got[key]
    if abs(e[0] - g[0]) > 2e-6 or abs(e[1] - g[1]) > 2e-6 or abs(e[2] - g[2]) > 2e-6: bad += 1; print("range/close diverso", key); continue
    mx = max(abs(a - b) for a, b in zip(e[4], g[3]))
    if mx > 2e-3:
        bad += 1
        if bad <= 8: print("R diverso", key, "max|dR|", round(mx, 4))
print(f"finestra {ws:02d}:00+{wd}h, TF {sec}s: eventi python {len(exp)}, script {len(got)}, differenze {bad}")
sys.exit(1 if bad else 0)
