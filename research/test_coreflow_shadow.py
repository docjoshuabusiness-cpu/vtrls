#!/usr/bin/env python3
"""
test_coreflow_shadow.py - trascrizione RIGA PER RIGA di MQL5/Include/SD_CoreFlow.mqh in Python (stessi cicli, stesse
variabili, stessa aritmetica) confrontata con il riferimento vettorializzato (flow_fast.py / flow_lab.events_dir).

Cosa dimostra: che la LOGICA scritta nell'include (ring per fascia, mediana, finestre, somme cumulate, eventi,
raffica) coincide con quella gia' verificata. Cosa NON dimostra: che il file MQL5 compili o che io abbia trascritto
fedelmente ogni carattere: quello lo dice solo MetaEditor. Se modifichi l'include, aggiorna questa copia.

  python3 -I test_coreflow_shadow.py
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_fast as ff
import flow_lab as fl

EMPTY = 1.7976931348623157e308      # EMPTY_VALUE (DBL_MAX)


def sd_erf_as(x):
    p, a1, a2, a3, a4, a5 = 0.3275911, 0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429
    s = -1.0 if x < 0.0 else 1.0
    ax = abs(x)
    t = 1.0 / (1.0 + p * ax)
    return s * (1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-ax * ax))


def sd_norm_cdf(z):
    return 0.5 * (1.0 + sd_erf_as(z / 1.4142135623730951))


def sd_flow_median(hist, base, n, tmp):
    for k in range(n):
        v = hist[base + k]
        m = k - 1
        while m >= 0 and tmp[m] > v:
            tmp[m + 1] = tmp[m]
            m -= 1
        tmp[m + 1] = v
    if (n & 1) == 1:
        return tmp[n // 2]
    return 0.5 * (tmp[n // 2 - 1] + tmp[n // 2])


def sd_flow_series(t, h_, l_, c_, v_, n, p, period_sec):
    z = [EMPTY] * n
    ab = [EMPTY] * n
    N, M, D = max(2, p["flowBars"]), max(50, p["zWindow"]), max(3, p["seasonDays"])
    atrP, bvcB = max(2, p["atrPeriod"]), max(5, p["bvcBars"])
    first = max(max(atrP, bvcB), N) + 2
    slots = max(1, 86400 // max(1, period_sec))
    if n < first + 2:
        return z, ab
    hist = [0.0] * (slots * D)
    tmp = [0.0] * D
    cnt = [0] * slots
    head = [0] * slots
    wv, fb = [0.0] * n, [0.0] * n
    cF, cF2, cFn, cA, cA2, cAn = ([0.0] * n for _ in range(6))
    for i in range(n):
        for arr in (cF, cF2, cFn, cA, cA2, cAn):
            arr[i] = arr[i - 1] if i > 0 else 0.0
        wv[i] = -1.0
        fb[i] = 0.0
        slot = int((int(t[i]) % 86400) // period_sec)
        if slot >= slots:
            slot = slots - 1
        if slot < 0:
            slot = 0
        vol = float(v_[i])
        if i >= first and i < n - 1:
            w = -1.0
            if cnt[slot] >= p["minSessions"]:
                med = sd_flow_median(hist, slot * D, cnt[slot], tmp)
                if med > 0.0:
                    w = min(vol / med, p["weightCap"])
            if w >= 0.0:
                if not p["useWeights"]:
                    w = 1.0
                rng = h_[i] - l_[i]
                if p["flowMode"] == 0:
                    d = ((c_[i] - l_[i]) - (h_[i] - c_[i])) / rng if rng > 0.0 else 0.0
                else:
                    s2 = 0.0
                    for j in range(i - bvcB + 1, i + 1):
                        dd = c_[j] - c_[j - 1]
                        s2 += dd * dd
                    sg = math.sqrt(s2 / bvcB)
                    d = 2.0 * sd_norm_cdf((c_[i] - c_[i - 1]) / sg) - 1.0 if sg > 0.0 else 0.0
                wv[i] = w
                fb[i] = w * d
                sf = sw = 0.0
                full = True
                for k in range(N):
                    j = i - k
                    if wv[j] < 0.0:
                        full = False
                        break
                    sf += fb[j]
                    sw += wv[j]
                if full and sw > 0.0:
                    F = sf / sw
                    effort = sw / N
                    hi = i - 1
                    lo = hi - M
                    s1 = cF[hi] - (cF[lo] if lo >= 0 else 0.0)
                    s2_ = cF2[hi] - (cF2[lo] if lo >= 0 else 0.0)
                    nn = cFn[hi] - (cFn[lo] if lo >= 0 else 0.0)
                    if nn >= 0.5 * M:
                        mu = s1 / nn
                        vr = s2_ / nn - mu * mu
                        if vr > 1e-12:
                            z[i] = (F - mu) / math.sqrt(vr)
                    cF[i] += F
                    cF2[i] += F * F
                    cFn[i] += 1.0
                    sTR = 0.0
                    for j in range(i - atrP + 1, i + 1):
                        sTR += max(h_[j], c_[j - 1]) - min(l_[j], c_[j - 1])
                    atr = sTR / atrP
                    if atr > 0.0:
                        res = abs(c_[i] - c_[i - N]) / (atr * math.sqrt(N))
                        A = math.log(max(effort, 0.05)) - math.log(res + 0.1)
                        a1 = cA[hi] - (cA[lo] if lo >= 0 else 0.0)
                        a2 = cA2[hi] - (cA2[lo] if lo >= 0 else 0.0)
                        an = cAn[hi] - (cAn[lo] if lo >= 0 else 0.0)
                        if an >= 0.5 * M:
                            mu = a1 / an
                            vr = a2 / an - mu * mu
                            if vr > 1e-12:
                                ab[i] = (A - mu) / math.sqrt(vr)
                        cA[i] += A
                        cA2[i] += A * A
                        cAn[i] += 1.0
        if i < n - 1:
            hh = head[slot]
            hist[slot * D + hh] = vol
            head[slot] = (hh + 1) % D
            if cnt[slot] < D:
                cnt[slot] += 1
    return z, ab


def sd_build_signals_flow(t, h_, l_, c_, v_, n, p, period_sec):
    d_arr, b_arr = [0] * n, [0] * n
    N = max(2, p["flowBars"])
    first = max(max(max(2, p["atrPeriod"]), max(5, p["bvcBars"])), N) + 2
    warm = first + N
    if n < warm + 3:
        return d_arr, b_arr, warm, [], []
    z, ab = sd_flow_series(t, h_, l_, c_, v_, n, p, period_sec)
    run_dir = run_count = gap = 0
    for i in range(1, n - 1):
        d = 0
        if z[i] != EMPTY:
            prev_up = z[i - 1] != EMPTY and z[i - 1] >= p["threshold"]
            prev_dn = z[i - 1] != EMPTY and z[i - 1] <= -p["threshold"]
            if z[i] >= p["threshold"] and not prev_up:
                d = 1
            elif z[i] <= -p["threshold"] and not prev_dn:
                d = -1
        if d == 0:
            gap += 1
            if p["runGapBars"] > 0 and gap >= p["runGapBars"]:
                run_dir = run_count = 0
        else:
            gap = 0
            if d == run_dir:
                run_count += 1
            else:
                run_dir, run_count = d, 1
        if d != 0:
            d_arr[i] = d
            b_arr[i] = min(run_count, 255)
    return d_arr, b_arr, warm, z, ab


def burst_reference(dirs, run_gap=0):
    """raffica calcolata in modo indipendente dalle direzioni (stessa regola di SD_BuildSignals)"""
    b = np.zeros(len(dirs), int)
    rd = rc = gap = 0
    for i, d in enumerate(dirs):
        if d == 0:
            gap += 1
            if run_gap > 0 and gap >= run_gap:
                rd = rc = 0
        else:
            gap = 0
            if d == rd:
                rc += 1
            else:
                rd, rc = d, 1
            b[i] = min(rc, 255)
    return b


def main():
    ok_all = True
    for psec, days, seed, mode, uw, thr in ((3600, 150, 3, 0, True, 1.5), (900, 45, 4, 0, False, 1.0),
                                             (3600, 150, 5, 1, True, 1.5), (300, 25, 6, 1, False, 2.0), (86400, 900, 7, 0, True, 1.5)):
        b = fl.gen_dgp(days=days, seed=seed, psec=psec) if psec < 86400 else fl.gen_dgp(days=days, seed=seed, psec=3600)
        t, o, h, l, c, v = (b[k] for k in ("t", "o", "h", "l", "c", "v"))
        if psec == 86400:           # D1: aggrego le H1 per provare il caso con una sola fascia oraria
            bk = t // 86400
            st = np.concatenate(([0], np.flatnonzero(np.diff(bk)) + 1))
            en = np.concatenate((st[1:] - 1, [len(t) - 1]))
            t, o, h, l, c, v = bk[st] * 86400, o[st], np.maximum.reduceat(h, st), np.minimum.reduceat(l, st), c[en], np.add.reduceat(v, st)
        n = len(t)
        p = dict(flowMode=mode, flowBars=12, zWindow=500 if psec < 86400 else 80, threshold=thr, seasonDays=20, minSessions=5,
                 weightCap=3.0, atrPeriod=14, bvcBars=50, useWeights=uw, runGapBars=0)
        d_arr, b_arr, warm, z, ab = sd_build_signals_flow(t.tolist(), h.tolist(), l.tolist(), c.tolist(), v.tolist(), n, p, psec)
        f = ff.flow_features(t, o, h, l, c, v, psec, N=12, M=p["zWindow"], D=20, mode="clv" if mode == 0 else "bvc", use_weights=uw)
        zs = np.array([np.nan if x == EMPTY else x for x in z])
        abs_ = np.array([np.nan if x == EMPTY else x for x in ab])
        z_ok = np.array_equal(np.isnan(zs), np.isnan(f["Z"])) and (np.nanmax(np.abs(zs - f["Z"])) < 1e-9 if (~np.isnan(zs)).any() else True)
        a_ok = np.array_equal(np.isnan(abs_), np.isnan(f["Ab"])) and (np.nanmax(np.abs(abs_ - f["Ab"])) < 1e-9 if (~np.isnan(abs_)).any() else True)
        ev = fl.events_dir(f["Z"], thr)
        ev[n - 1] = 0                                   # il lab non emette segnali sull'ultima barra
        e_ok = np.array_equal(np.array(d_arr), ev)
        br_ok = np.array_equal(np.array(b_arr), burst_reference(ev))
        ok = z_ok and a_ok and e_ok and br_ok
        ok_all &= ok
        print("psec %5d modo %d peso %-5s soglia %.1f | Z %s | Ab %s | eventi %s (%d) | raffica %s | %s" % (
            psec, mode, uw, thr, z_ok, a_ok, e_ok, int((ev != 0).sum()), br_ok, "OK" if ok else "FAIL"))
    print("TRASCRIZIONE DI SD_CoreFlow.mqh:", "COERENTE CON IL RIFERIMENTO" if ok_all else "DIFFERENZE")
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
