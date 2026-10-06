#!/usr/bin/env python3
"""Verifica indipendente della parte A2 (range = ultime N candele di un time frame che finiscono a ogni ora piena): ricalcola da m1.csv, in Python,
candele, range, prima chiusura fuori, k, ingresso, R di tutte le combinazioni SL x RR, MFE/rientro e sopravvivenza, range osservati, e le statistiche
su eventi distinti (una volta per candela d'ingresso e direzione), e li confronta con quanto esportato dallo script (g_cbDbg2 = t*6 + ni)."""
import csv, math, sys, collections, bisect, calendar, time
t_idx, ni_idx = int(sys.argv[1]), int(sys.argv[2])
spread_pts = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
pt = 1e-5; S = spread_pts * pt; tol = pt * 0.001
TFS = [60, 300, 900, 1800, 3600, 7200, 10800]; sec = TFS[t_idx]
NLIST = [3, 5, 8, 12, 20, 25]; N = NLIST[ni_idx]
T, O, H, L, C = [], [], [], [], []
for ln in open("m1.csv"):
    t, o, h, l, c, sp = ln.strip().split(",")
    T.append(int(t)); O.append(float(o)); H.append(float(h)); L.append(float(l)); C.append(float(c))
n = len(T)
def lower(t): return bisect.bisect_left(T, t)
rows = list(csv.DictReader(open("out/MQL5/Files/MDRB_Study_EURUSD_cb2_events_debug.csv")))
med = float(rows[0]["med_pts"]) if rows else 100.0
slf = [float(rows[0][f"sl{i}"]) for i in range(6)] if rows else [25.0, 50.0, 75.0, 100.0, 150.0, 200.0]
buf = max(1.0, round(0.05 * med))
tgs = (max(1.0, round(1.0 * med)), max(2.0, round(2.0 * med)))
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
        if hs: return slu / SLd
        if ht: return TPd / SLd
    return ((d * (C[j0 + Lh - 1] - E0) - S)) / SLd
L4 = 240; L24 = 1440
def kbucket(k): return 0 if k <= 1 else 1 if k == 2 else 2 if k == 3 else 3 if k <= 5 else 4 if k <= 10 else 5
exp = {}; order = []
rng = collections.Counter(); brk = collections.Counter()
cutv = None
got = {}
for r in rows:
    D = calendar.timegm(time.strptime(r["day"], "%Y.%m.%d"))
    R = [float(r[f"R_s{i}_m{m}"]) for i in range(7) for m in (1, 2, 3)]
    got[(D, int(r["end_hour"]), int(r["k"]), int(r["dir"]))] = (float(r["range_hi"]), float(r["range_lo"]), float(r["close"]), R, float(r["mfe4_pts"]), float(r["ret4_pts"]), [float(r["mbk_t0"]), float(r["mbk_t1"])], int(r["part"]))
# la parte (IS/OOS) di ogni giorno e' nota dal dedup/eventi: la ricaviamo dagli eventi esportati (stesso giorno -> stessa parte)
part_of_day = {}
for key, v in got.items(): part_of_day[key[0]] = v[7]
dd = list(csv.DictReader(open("out/MQL5/Files/MDRB_Study_EURUSD_cb_dedup_debug.csv")))
wd_rows = list(csv.DictReader(open("out/MQL5/Files/MDRB_Study_EURUSD_cb_width_debug.csv")))
cutv = int([r for r in wd_rows if r["kind"] == "meta"][0]["w"])
last = T[-1]
days = sorted(set(t - t % 86400 for t in T))
tn = t_idx * 6 + ni_idx
for D in days[:-1]:
    if D > last: break
    part = 1 if D >= cutv else 0
    endDay = D + 86400
    for e in range(1, 24):
        if (e * 3600) % sec != 0: continue
        E = D + e * 3600
        c0 = bisect.bisect_left(ctimes, E)
        if c0 - N < 0 or c0 >= len(ctimes): continue
        if E - (ctimes[c0 - 1] + sec) > sec: continue
        span = E - ctimes[c0 - N]
        if span > int(1.5 * N * sec) + 2 * sec: continue
        hi = max(cand[ctimes[q]][0] for q in range(c0 - N, c0)); lo = min(cand[ctimes[q]][1] for q in range(c0 - N, c0))
        if not (hi > lo) or lo <= 0: continue
        jb = lower(E)
        if jb >= n: continue
        if (hi - lo) < 2.0 * S: continue
        hit = None; seen = False
        for q in range(c0, len(ctimes)):
            ct = ctimes[q]
            if ct + sec > endDay: break
            seen = True
            cc = cand[ct][2]
            if cc > hi: hit = (ct, 1); break
            if cc < lo: hit = (ct, -1); break
        if not seen: continue
        rng[part] += 1
        if hit is None: continue
        brk[part] += 1
        ct, d = hit
        k = (ct - E) // sec + 1
        tc = ct + sec; j0 = lower(tc)
        if j0 + L4 >= n: continue
        if T[j0] - tc > 900: continue
        E0 = cand[ct][2]; edge = hi if d > 0 else lo
        edgeDist = d * (E0 - edge) / pt
        slEdge = max(edgeDist + buf + S / pt, max(5.0, 4.0 * S / pt))
        mfe4 = 0.0; mbk = []
        for ti, Tg in enumerate(tgs):
            mb = 0.0; got_t = None
            for j in range(L4):
                h, l, c = H[j0 + j], L[j0 + j], C[j0 + j]
                Fv, Av = (h - E0, l - E0) if d > 0 else (E0 - l, E0 - h)
                if ti == 0: mfe4 = max(mfe4, Fv)
                if -Av > mb: mb = -Av
                if got_t is None and Fv - S >= Tg * pt - tol: got_t = mb
            mbk.append(-1.0 if got_t is None else got_t / pt)
        ret4 = d * (C[j0 + L4 - 1] - E0) / pt
        Lh = min(L24, n - j0 - 1)
        res = []
        for i in range(7):
            slp = slf[i] if i < 6 else slEdge
            for m in range(3):
                res.append(sim(j0, d, E0, slp * pt, (m + 1) * slp * pt, Lh))
        key = (D, e, k, d)
        exp[key] = (hi, lo, E0, tc, res, mfe4 / pt, ret4, mbk, part)
        order.append(key)
bad = 0
for key in set(exp) | set(got):
    if key not in exp or key not in got:
        bad += 1
        if bad <= 8: print("EVENTO diverso", key, "py" if key in exp else "-", "script" if key in got else "-")
        continue
    e_, g_ = exp[key], got[key]
    if abs(e_[0] - g_[0]) > 2e-6 or abs(e_[1] - g_[1]) > 2e-6 or abs(e_[2] - g_[2]) > 2e-6: bad += 1; print("range/close diverso", key); continue
    if max(abs(a - b) for a, b in zip(e_[4], g_[3])) > 2e-3: bad += 1; print("R diverso", key); continue
    if abs(e_[5] - g_[4]) > 0.06 or abs(e_[6] - g_[5]) > 0.06: bad += 1; print("MFE/rientro diverso", key); continue
    if any(abs(a - b) > 0.02 for a, b in zip(e_[7], g_[6])): bad += 1; print("sopravvivenza diversa", key); continue
    if e_[8] != g_[7]: bad += 1; print("parte IS/OOS diversa", key); continue
# statistiche su eventi distinti (candela d'ingresso, direzione) su tutte le ore di fine, e conteggi dei range osservati
U = {}; seen_u = set()
for key in order:
    if key not in got: continue
    tc = exp[key][3]; d = key[3]; part = exp[key][8]
    if (tc, d) in seen_u: continue
    seen_u.add((tc, d))
    for idx, Rv in enumerate(exp[key][4]):
        i, m = divmod(idx, 3)
        a = U.setdefault((i, m + 1, part), [0, 0.0, 0.0]); a[0] += 1; a[1] += Rv; a[2] += Rv * Rv
nbad = 0; ncmp = 0
for r in dd:
    if r["kind"] == "u":
        ncmp += 1
        ref = U.get((int(r["sl"]), int(r["m"]), int(r["part"])), [0, 0.0, 0.0]); nn = int(r["n"])
        if nn != ref[0] or abs(float(r["sum"]) - ref[1]) > 5e-4 * max(1, nn) or abs(float(r["sum2"]) - ref[2]) > 5e-4 * max(1, nn):
            nbad += 1
            if nbad <= 6: print("aggregato distinto diverso", r["sl"], r["m"], r["part"], "script", nn, round(float(r["sum"]), 4), "python", ref[0], round(ref[1], 4))
    elif r["kind"] == "c2r":
        ncmp += 1
        p = int(r["part"])
        if int(r["n"]) != rng[p] or int(float(r["sum"])) != brk[p]:
            nbad += 1; print("range osservati diversi", p, "script", r["n"], r["sum"], "python", rng[p], brk[p])
bad += nbad
print(f"A2: TF {sec}s N={N}: eventi python {len(exp)}, script {len(got)}, differenze {bad} | {ncmp} aggregati confrontati (eventi totali {len(order)} -> distinti {len(seen_u)}, range osservati {sum(rng.values())})")
sys.exit(1 if bad else 0)
