#!/usr/bin/env python3
"""Verifica indipendente dello studio post-rottura della Parte B (ritest del livello, meta' range, zona del giorno precedente,
falso breakout, MFE e rientro in punti): ricalcola da m1.csv per ogni trade del file trades.csv e confronta con le colonne dello script.
Uso: dopo una run classica (InpAuto=0) con MDRB_DUMP_M1=1."""
import csv, re, sys, calendar, time, bisect
pt = 1e-5
gt = pt * 0.001
F = "out/MQL5/Files/"
rows = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_trades.csv")))
html = open(F + "MDRB_Study_EURUSD.html", encoding="utf-8", errors="ignore").read()
tol = float(re.search(r"a meno di (\d+) punti dal livello", html).group(1))
m = re.search(r"sale di (\d+) punti oltre il livello prima di scendere di (\d+) sotto", html)
cont, fail = float(m.group(1)), float(m.group(2))
offset = float(sys.argv[1]) if len(sys.argv) > 1 else 20.0
T, O, H, L, C = [], [], [], [], []
for ln in open("m1.csv"):
    t, o, h, l, c, sp = ln.strip().split(",")
    T.append(int(t)); O.append(float(o)); H.append(float(h)); L.append(float(l)); C.append(float(c))
n = len(T)
dayhl = {}
for i in range(n):
    d = T[i] - T[i] % 86400
    if d not in dayhl: dayhl[d] = [H[i], L[i]]
    else: dayhl[d][0] = max(dayhl[d][0], H[i]); dayhl[d][1] = min(dayhl[d][1], L[i])
days = sorted(dayhl)
g_L = 4320
def ts(s): return calendar.timegm(time.strptime(s, "%Y.%m.%d %H:%M"))
bad = 0; cnt = 0
for r in rows:
    d = int(r["dir"]); jt = bisect.bisect_left(T, ts(r["fill_time"]))
    hi = float(r["range_hi"]); lo = float(r["range_lo"])
    S = float(r["spread_pts"]) * pt; delta = float(r["gap_delta_pts"]) * pt
    E0 = (float(r["buy_px"]) + delta - S) if d > 0 else (float(r["sell_px"]) - delta)
    Lh = min(g_L, n - jt)
    wF, wA, wC = [], [], []
    for j in range(Lh):
        h, l, c = H[jt + j], L[jt + j], C[jt + j]
        wC.append(d * (c - E0))
        if d > 0: wF.append(h - E0); wA.append(l - E0)
        else: wF.append(E0 - l); wA.append(E0 - h)
    wA[0] = min(0.0, wC[0])
    if wF[0] < 0.0: wF[0] = 0.0
    edge = hi if d > 0 else lo
    Lrel = d * (edge - E0)
    band = Lrel + tol * pt + gt
    departed = band < 0.0
    jr = -1
    for j in range(Lh):
        if not departed:
            if wF[j] > band: departed = True
            continue
        if wA[j] <= band: jr = j; break
    rt4 = rt24 = 0; rth = -1.0; res = 0
    if jr >= 0:
        rth = (jr + 1) * 60 / 3600.0
        rt4 = int(rth <= 4.0); rt24 = int(rth <= 24.0)
        for j in range(jr, Lh):
            if wA[j] <= Lrel - fail * pt + gt: res = -1; break
            if j > jr and wF[j] >= Lrel + cont * pt - gt: res = 1; break
    mrel = d * ((hi + lo) * 0.5 - E0)
    jm = next((j for j in range(Lh) if wA[j] <= mrel + gt), -1)
    mid = int(jm >= 0 and (jm + 1) * 60 / 3600.0 <= 24.0)
    opp = lo if d > 0 else hi
    fake = int(any(wA[j] <= d * (opp - E0) + gt for j in range(Lh)))
    dd = T[jt] - T[jt] % 86400
    k = bisect.bisect_left(days, dd)
    pdA = pdH = pdR = 0
    if k >= 1:
        zp = dayhl[days[k - 1]][0] if d > 0 else dayhl[days[k - 1]][1]
        zrel = d * (zp - E0)
        if zrel > tol * pt + gt:
            pdA = 1
            jz = next((j for j in range(Lh) if wF[j] >= zrel - gt), -1)
            if jz >= 0 and (jz + 1) * 60 / 3600.0 <= 24.0:
                pdH = 1
                for j in range(jz, Lh):
                    if j > jz and wA[j] <= zrel - fail * pt + gt: pdR = -1; break
                    if wF[j] >= zrel + fail * pt - gt: pdR = 1; break
    mfe = (max(wF) - Lrel) / pt; mae = (Lrel - min(wA)) / pt
    got = (int(r["retest4"]), int(r["retest24"]), float(r["retest_hours"]), int(r["retest_result"]), int(r["mid_hit"]), int(r["pd_ahead"]), int(r["pd_hit"]), int(r["pd_result"]), int(r["fakeout"]))
    exp = (rt4, rt24, rth, res, mid, pdA, pdH, pdR, fake)
    ok = all((abs(a - b) < 0.011 if isinstance(a, float) else a == b) for a, b in zip(got, exp)) and abs(float(r["mfe_pts"]) - mfe) < 0.6 and abs(float(r["pullback_pts"]) - mae) < 0.6
    cnt += 1
    if not ok:
        bad += 1
        if bad <= 6: print("DIFF", r["day"], r["fill_time"], "script", got, round(float(r["mfe_pts"]), 1), round(float(r["pullback_pts"]), 1), "python", exp, round(mfe, 1), round(mae, 1))
print(f"studio post-rottura: {cnt} trade confrontati con il ricalcolo indipendente, differenze {bad}")
sys.exit(1 if bad else 0)
