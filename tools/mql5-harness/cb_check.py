#!/usr/bin/env python3
"""Verifica indipendente della Parte A (rotture a candela chiusa): ricalcola da m1.csv, in Python, range, candele del TF,
prima chiusura fuori, k (candele trascorse), ingresso, gli R di tutte le combinazioni SL x RR, MFE/rientro a 4 ore e la sopravvivenza
(escursione avversa massima prima del bersaglio), e li confronta con gli eventi esportati dallo script.
Con window = -2 verifica tutte le finestre del time frame e le statistiche aggregate su eventi distinti (un evento per candela d'ingresso)."""
import csv, math, sys, collections, bisect, calendar, time
w_idx, t_idx = int(sys.argv[1]), int(sys.argv[2])
spread_pts = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
pt = 1e-5; S = spread_pts * pt; tol = pt * 0.001
TFS = [60, 300, 900, 1800, 3600, 7200, 10800]; sec = TFS[t_idx]
durs = [1, 2, 3, 4, 6, 8, 12]
wins = [(s, d) for d in durs for s in range(0, 24) if s + d <= 23]
wlist = wins if w_idx < 0 else [wins[w_idx]]
T, O, H, L, C = [], [], [], [], []
for ln in open("m1.csv"):
    t, o, h, l, c, sp = ln.strip().split(",")
    T.append(int(t)); O.append(float(o)); H.append(float(h)); L.append(float(l)); C.append(float(c))
n = len(T)
def lower(t): return bisect.bisect_left(T, t)
rows = list(csv.DictReader(open("out/MQL5/Files/MDRB_Study_EURUSD_cb_events_debug.csv")))
if rows:
    med = float(rows[0]["med_pts"]); slf = [float(rows[0][f"sl{i}"]) for i in range(6)]
else:
    med = 100.0; slf = [25.0, 50.0, 75.0, 100.0, 150.0, 200.0]     # nessun evento atteso: i valori non servono
buf = max(1.0, round(0.05 * med))
tgs = (max(1.0, round(1.0 * med)), max(2.0, round(2.0 * med)))
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
def kbucket(k): return 0 if k <= 1 else 1 if k == 2 else 2 if k == 3 else 3 if k <= 5 else 4 if k <= 10 else 5
exp = {}
obs = []                                    # range osservati (con almeno una candela dopo la fine): (giorno, ws, wd, larghezza, rotto)
order = []                                  # ordine di generazione degli eventi (giorno, finestra) come nello script
last = T[-1]
days = sorted(set(t - t % 86400 for t in T))
for D in days[:-1]:               # lo script esclude l'ultimo giorno D1 (potrebbe essere incompleto)
    if D > last: break
    for (ws, wd) in wlist:
        rs0 = D + ws * 3600; re0 = rs0 + wd * 3600
        ja, jb = lower(rs0), lower(re0)
        if jb - ja < max(1, int(0.6 * wd * 3600 / 60)): continue
        hi = max(H[ja:jb]); lo = min(L[ja:jb])
        if not (hi > lo) or lo <= 0: continue
        if (hi - lo) < 2.0 * S: continue
        endDay = D + 86400
        ci = bisect.bisect_left(ctimes, re0)
        hit = None
        seen = False
        for q in range(ci, len(ctimes)):
            ct = ctimes[q]
            if ct + sec > endDay: break
            if ct < re0: continue
            seen = True
            cc = cand[ct][2]
            if cc > hi: hit = (ct, 1); break
            if cc < lo: hit = (ct, -1); break
        if not seen: continue
        obs.append((D, ws, wd, (hi - lo) / pt, hit is not None))
        if hit is None: continue
        ct, d = hit
        k = (ct - re0) // sec + 1
        tc = ct + sec; j0 = lower(tc)
        if j0 + L4 >= n: continue
        if T[j0] - tc > 900: continue
        E0 = cand[ct][2]; edge = hi if d > 0 else lo
        edgeDist = d * (E0 - edge) / pt
        slEdge = max(edgeDist + buf + S / pt, max(5.0, 4.0 * S / pt))
        # post-rottura a 4 ore: MFE (>= 0), rientro e escursione avversa massima prima di +T (convenzione dello spread di SimFixed)
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
        key = (D, ws, wd, k, d)
        exp[key] = (hi, lo, E0, tc, res, mfe4 / pt, ret4, mbk)
        order.append(key)
got = {}
for r in rows:
    D = calendar.timegm(time.strptime(r["day"], "%Y.%m.%d"))
    R = [float(r[f"R_s{i}_m{m}"]) for i in range(7) for m in (1, 2, 3)]
    got[(D, int(r["win_start"]), int(r["win_hours"]), int(r["k"]), int(r["dir"]))] = (float(r["range_hi"]), float(r["range_lo"]), float(r["close"]), R, float(r["mfe4_pts"]), float(r["ret4_pts"]), [float(r["mbk_t0"]), float(r["mbk_t1"])], int(r["part"]))
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
        continue
    if abs(e[5] - g[4]) > 0.06 or abs(e[6] - g[5]) > 0.06:
        bad += 1
        if bad <= 8: print("MFE/rientro diverso", key, round(e[5], 2), g[4], round(e[6], 2), g[5])
        continue
    if any(abs(a - b) > 0.02 for a, b in zip(e[7], g[6])):
        bad += 1
        if bad <= 8: print("sopravvivenza diversa", key, e[7], g[6])
msg = f"finestre {len(wlist)}, TF {sec}s: eventi python {len(exp)}, script {len(got)}, differenze {bad}"
if w_idx < 0:
    # statistiche aggregate su eventi distinti: una volta per (candela d'ingresso, direzione) e per (candela, direzione, k)
    A, K = {}, {}
    seenA, seenK = set(), set()
    for key in order:
        if key not in got: continue
        D, ws, wd, k, d = key
        tc = exp[key][3]; part = got[key][7]; kb = kbucket(k)
        for idx, Rv in enumerate(exp[key][4]):
            i, m = divmod(idx, 3)
            if (tc, d) not in seenA:
                a = A.setdefault((i, m + 1, part), [0, 0.0, 0.0]); a[0] += 1; a[1] += Rv; a[2] += Rv * Rv
            if (tc, d, kb) not in seenK:
                a = K.setdefault((kb, i, m + 1, part), [0, 0.0, 0.0]); a[0] += 1; a[1] += Rv; a[2] += Rv * Rv
        seenA.add((tc, d)); seenK.add((tc, d, kb))
    dd = list(csv.DictReader(open("out/MQL5/Files/MDRB_Study_EURUSD_cb_dedup_debug.csv")))
    nbad = 0; ncmp = 0
    for r in dd:
        if r["kind"] not in ("a", "k"): continue
        i, m, part = int(r["sl"]), int(r["m"]), int(r["part"])
        ref = A.get((i, m, part), [0, 0.0, 0.0]) if r["kind"] == "a" else K.get((int(r["kb"]), i, m, part), [0, 0.0, 0.0])
        ncmp += 1
        nn = int(r["n"])
        if nn != ref[0] or abs(float(r["sum"]) - ref[1]) > 5e-4 * max(1, nn) or abs(float(r["sum2"]) - ref[2]) > 5e-4 * max(1, nn):
            nbad += 1
            if nbad <= 6: print("aggregato distinto diverso", r["kind"], r["kb"], i, m, part, "script", nn, round(float(r["sum"]), 4), "python", ref[0], round(ref[1], 4))
    # larghezza dei range orari: statistiche per finestra, terzili sull'IS, fasce, eventi distinti per fascia, range osservati per fascia
    wd_rows = list(csv.DictReader(open("out/MQL5/Files/MDRB_Study_EURUSD_cb_width_debug.csv")))
    cutv = int([r for r in wd_rows if r["kind"] == "meta"][0]["w"])
    def quant(a, p):
        pos = p * (len(a) - 1); i0 = int(math.floor(pos)); i1 = min(i0 + 1, len(a) - 1); fr = pos - i0
        return a[i0] * (1 - fr) + a[i1] * fr
    widths = {}
    for D in days[:-1]:
        if D > last: break
        for wi, (ws_, wd_) in enumerate(wins):
            rs0 = D + ws_ * 3600; re0 = rs0 + wd_ * 3600
            ja, jb = lower(rs0), lower(re0)
            if jb - ja < max(1, int(0.6 * wd_ * 3600 / 60)): continue
            hi = max(H[ja:jb]); lo = min(L[ja:jb])
            if not (hi > lo) or lo <= 0 or (hi - lo) < 2.0 * S: continue
            widths[(D, wi)] = (hi - lo) / pt
    cuts = {}
    wbad = 0
    for r in wd_rows:
        if r["kind"] != "win": continue
        wi = int(r["w"])
        allv = sorted(v for (D, w2), v in widths.items() if w2 == wi)
        isv = sorted(v for (D, w2), v in widths.items() if w2 == wi and D < cutv)
        c1, c2 = (quant(isv, 1 / 3.0), quant(isv, 2 / 3.0)) if len(isv) >= 30 else (-1.0, -1.0)
        cuts[wi] = (c1, c2)
        got_ = (int(r["n"]), float(r["med"]), float(r["p10"]), float(r["p90"]), float(r["c1"]), float(r["c2"]))
        exp_ = (len(allv), quant(allv, 0.5) if allv else 0.0, quant(allv, 0.1) if allv else 0.0, quant(allv, 0.9) if allv else 0.0, c1, c2)
        if got_[0] != exp_[0] or any(abs(a - b) > 2e-3 for a, b in zip(got_[1:], exp_[1:])):
            wbad += 1
            if wbad <= 5: print("larghezza finestra diversa", r["ws"], r["wd"], got_, exp_)
    def wbucket(wi, wp):
        c1, c2 = cuts[wi]
        if c1 < 0: return -1
        return 0 if wp < c1 else (1 if wp < c2 else 2)
    winidx = {w: i for i, w in enumerate(wins)}
    WS, seenW = {}, set()
    for key in order:
        if key not in got: continue
        D, ws_, wd_, k, d = key
        wi = winidx[(ws_, wd_)]
        wb = wbucket(wi, widths[(D, wi)])
        if wb < 0: continue
        tc = exp[key][3]; part = got[key][7]
        if (tc, d, wb) in seenW: continue
        seenW.add((tc, d, wb))
        for idx, Rv in enumerate(exp[key][4]):
            i, m = divmod(idx, 3)
            a = WS.setdefault((wb, i, m + 1, part), [0, 0.0, 0.0]); a[0] += 1; a[1] += Rv; a[2] += Rv * Rv
    RG = {}
    for (D, ws_, wd_, wp, brk_) in obs:
        wi = winidx[(ws_, wd_)]
        wb = wbucket(wi, widths[(D, wi)])
        if wb < 0: continue
        part = 1 if D >= cutv else 0
        a = RG.setdefault((wb, part), [0, 0.0, 0]); a[0] += 1; a[1] += wp; a[2] += 1 if brk_ else 0
    for r in dd:
        if r["kind"] == "w":
            ncmp += 1
            ref = WS.get((int(r["kb"]), int(r["sl"]), int(r["m"]), int(r["part"])), [0, 0.0, 0.0]); nn = int(r["n"])
            if nn != ref[0] or abs(float(r["sum"]) - ref[1]) > 5e-4 * max(1, nn) or abs(float(r["sum2"]) - ref[2]) > 5e-4 * max(1, nn):
                nbad += 1
                if nbad <= 6: print("fascia di larghezza diversa", r["kb"], r["sl"], r["m"], r["part"], "script", nn, round(float(r["sum"]), 4), "python", ref[0], round(ref[1], 4))
        elif r["kind"] == "wr":
            ncmp += 1
            ref = RG.get((int(r["kb"]), int(r["part"])), [0, 0.0, 0])
            if int(r["n"]) != ref[0] or abs(float(r["sum"]) - ref[1]) > 1e-3 * max(1, ref[0]) or int(float(r["sum2"])) != ref[2]:
                nbad += 1
                if nbad <= 6: print("range per fascia diversi", r["kb"], r["part"], "script", r["n"], r["sum"], r["sum2"], "python", ref)
    nbad += wbad
    tot_a = sum(v[0] for (i, m, p), v in A.items() if i == 3 and m == 2)
    msg += f" | aggregati su eventi distinti: {ncmp} celle, differenze {nbad} (eventi totali {len(order)} -> distinti {tot_a})"
    bad += nbad
print(msg)
sys.exit(1 if bad else 0)
