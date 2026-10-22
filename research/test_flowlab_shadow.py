#!/usr/bin/env python3
"""
test_flowlab_shadow.py - trascrizione riga per riga della parte STATISTICA di MQL5/Scripts/FlowLab_MultiTF.mq5
(FL_Entries, FL_FwdClose, FL_BuildY, FL_Reg a due passate, FL_IcShift, Clu*, e i cicli degli eventi di ProcessTF)
confrontata con calcoli indipendenti: numpy/pandas diretti e le funzioni gia' calibrate di flow_lab.py.

Cosa dimostra: che l'algebra in streaming (somme per giorno A,B,C; regressione a due passate; abilita' cov(verso,r))
da' gli stessi numeri del calcolo diretto, e che la mappa barra->M1 e il rendimento a H minuti seguono la regola
scritta. Cosa NON dimostra: che il file MQL5 compili o che la trascrizione sia fedele a ogni carattere (lo dice solo
MetaEditor). SD_FlowSeries e' identico al testo di SD_CoreFlow.mqh (verificato con un diff) e quello e' coperto da
test_coreflow_shadow.py.

  python3 -I test_flowlab_shadow.py
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_lab as fl

EMPTY = 1.7976931348623157e308


# ---------------------------------------------------------------- trascrizione ---------------------------
def fl_entries(tfsec, tf_time, m1_time, n, ent_gap_min, t_from, t_to):
    ent = [-1] * n
    max_gap = ent_gap_min * 60
    p = 0
    n1 = len(m1_time)
    for i in range(n - 1):
        t_next = tf_time[i + 1]
        if t_next < t_from or t_next > t_to:
            continue
        spacing = t_next - tf_time[i]
        if spacing - tfsec > max_gap:
            continue
        while p < n1 and m1_time[p] < t_next:
            p += 1
        if p >= n1:
            break
        if m1_time[p] - t_next > max_gap:
            continue
        ent[i] = p
    return ent


def next_brk(m1_time, gmax):
    n1 = len(m1_time)
    nb = [0] * n1
    cur = n1 - 1
    nb[n1 - 1] = n1 - 1
    for j in range(n1 - 2, -1, -1):
        if m1_time[j + 1] - m1_time[j] > gmax:
            cur = j
        nb[j] = cur
    return nb


def fl_fwd_close(m1_time, m1_close, nbrk, hmin):
    n1 = len(m1_time)
    hs = hmin * 60
    okf = [0] * n1
    fcl = [0.0] * n1
    e = 0
    for j in range(n1):
        t_end = m1_time[j] + hs
        while e < n1 and m1_time[e] < t_end:
            e += 1
        ok = e < n1 and e > j and (nbrk[j] >= e or (nbrk[j] == e - 1 and m1_time[e - 1] + 60 >= t_end))
        okf[j] = 1 if ok else 0
        if ok:
            fcl[j] = m1_close[e - 1]
    return okf, fcl


def fl_build_y(n, ent, lag, m1_time, m1_open, m1_spr, m1_day, okf, fcl, pt, cost_fixed, extra, split_day):
    yv = [EMPTY] * n
    cv = [0.0] * n
    dv = [0] * n
    sm = [0] * n
    for i in range(n):
        p0 = ent[i]
        if p0 < 0:
            continue
        j = p0
        if lag > 0:
            j = p0 + lag
            if j >= len(m1_time) or m1_time[j] - m1_time[p0] != lag * 60:
                continue
        if okf[j] == 0:
            continue
        yv[i] = (fcl[j] - m1_open[j]) / pt
        cv[i] = (cost_fixed if cost_fixed > 0 else float(m1_spr[j])) + extra
        dv[i] = m1_day[j]
        sm[i] = 1 if m1_day[j] >= split_day else 0
    return yv, cv, dv, sm


def fl_reg(F, off, n, yv, dv, sm):
    sn, sx, sy, sxx, sxy, syy = ([0.0] * 3 for _ in range(6))
    for i in range(n):
        x = F[off + i]
        y = yv[i]
        if x == EMPTY or y == EMPTY:
            continue
        s = 1 + sm[i]
        for k in (0, s):
            sn[k] += 1.0
            sx[k] += x
            sy[k] += y
            sxx[k] += x * x
            sxy[k] += x * y
            syy[k] += y * y
    xb, yb, sxxc, sxyc, syyc, beta = ([0.0] * 3 for _ in range(6))
    ok = [False] * 3
    for k in range(3):
        ok[k] = sn[k] >= 20.0
        if not ok[k]:
            continue
        xb[k] = sx[k] / sn[k]
        yb[k] = sy[k] / sn[k]
        sxxc[k] = sxx[k] - sn[k] * xb[k] * xb[k]
        sxyc[k] = sxy[k] - sn[k] * xb[k] * yb[k]
        syyc[k] = syy[k] - sn[k] * yb[k] * yb[k]
        if sxxc[k] <= 1e-18 or syyc[k] <= 1e-18:
            ok[k] = False
            continue
        beta[k] = sxyc[k] / sxxc[k]
    curS, ssq = [0.0] * 3, [0.0] * 3
    curD = [-1] * 3
    for i in range(n):
        x = F[off + i]
        y = yv[i]
        if x == EMPTY or y == EMPTY:
            continue
        s = 1 + sm[i]
        for q in range(2):
            k = 0 if q == 0 else s
            if not ok[k]:
                continue
            xc = x - xb[k]
            yc = y - yb[k]
            if dv[i] != curD[k]:
                ssq[k] += curS[k] * curS[k]
                curS[k] = 0.0
                curD[k] = dv[i]
            curS[k] += xc * (yc - beta[k] * xc)
    for k in range(3):
        ssq[k] += curS[k] * curS[k]
    out = []
    for k in range(3):
        if not ok[k]:
            out.append(dict(n=0.0, beta=0.0, t=0.0, ic=0.0, icse=0.0))
            continue
        se = math.sqrt(ssq[k]) / sxxc[k]
        out.append(dict(n=sn[k], beta=beta[k] * math.sqrt(sxxc[k] / sn[k]), t=(beta[k] / se if se > 0 else 0.0),
                        ic=sxyc[k] / math.sqrt(sxxc[k] * syyc[k]), icse=se * math.sqrt(sxxc[k] / syyc[k])))
    return out


def fl_ic_shift(F, off, n, yv, k):
    sn = sx = sy = sxx = sxy = syy = 0.0
    for i in range(n):
        j = i - k
        if j < 0:
            j += n
        x = F[off + j]
        y = yv[i]
        if x == EMPTY or y == EMPTY:
            continue
        sn += 1.0
        sx += x
        sy += y
        sxx += x * x
        sxy += x * y
        syy += y * y
    if sn < 20.0:
        return 0.0
    cxx, cyy, cxy = sxx - sx * sx / sn, syy - sy * sy / sn, sxy - sx * sy / sn
    if cxx <= 1e-18 or cyy <= 1e-18:
        return 0.0
    return cxy / math.sqrt(cxx * cyy)


class Clu:
    def __init__(self):
        self.n = self.sum = self.A = self.B = self.C = self.cs = self.cn = 0.0
        self.day = -1

    def add(self, day, v):
        if day != self.day:
            if self.cn > 0.0:
                self.A += self.cs * self.cs
                self.B += self.cs * self.cn
                self.C += self.cn * self.cn
            self.cs = self.cn = 0.0
            self.day = day
        self.cs += v
        self.cn += 1.0
        self.n += 1.0
        self.sum += v

    def end(self):
        if self.cn > 0.0:
            self.A += self.cs * self.cs
            self.B += self.cs * self.cn
            self.C += self.cn * self.cn
        self.cs = self.cn = 0.0

    def t(self):
        if self.n < 3.0:
            return 0.0
        mu = self.sum / self.n
        v = self.A - 2.0 * mu * self.B + mu * mu * self.C
        if v <= 0.0:
            return 0.0
        se = math.sqrt(v) / self.n
        return mu / se if se > 0 else 0.0


def event_cells(n, evd_row, yv, cv, dv, sm):
    """un solo (soglia, orizzonte): [SEGUI-IS, SEGUI-OOS, INVERTI-IS, INVERTI-OOS] e abilita' [IS, OOS]"""
    cnet = [Clu() for _ in range(4)]
    csk = [Clu() for _ in range(2)]
    gsum = [0.0] * 4
    nb = [0.0] * 2
    ns = [0.0] * 2
    for i in range(n):
        if yv[i] == EMPTY:
            continue
        d = evd_row[i]
        if d == 0:
            continue
        q = sm[i]
        if d > 0:
            nb[q] += 1.0
        else:
            ns[q] += 1.0
    for i in range(n):
        if yv[i] == EMPTY:
            continue
        d = evd_row[i]
        if d == 0:
            continue
        smp = sm[i]
        gF = d * yv[i]
        kf, ki = smp, 2 + smp
        cnet[kf].add(dv[i], gF - cv[i])
        gsum[kf] += gF
        cnet[ki].add(dv[i], -gF - cv[i])
        gsum[ki] += -gF
        nbb, nss = nb[smp], ns[smp]
        sbar = (nbb - nss) / (nbb + nss)
        csk[smp].add(dv[i], (d - sbar) * yv[i])
    res = []
    for kk in range(4):
        cnet[kk].end()
        res.append(dict(n=cnet[kk].n, g=gsum[kk] / cnet[kk].n if cnet[kk].n > 0 else 0.0,
                        net=cnet[kk].sum / cnet[kk].n if cnet[kk].n > 0 else 0.0, t=cnet[kk].t()))
    sk = []
    for smp in range(2):
        csk[smp].end()
        sk.append(csk[smp].t())
    return res, sk


# ---------------------------------------------------------------- dati sintetici -------------------------
def make_m1(days=120, seed=11, with_gaps=True):
    """M1 con rendimenti casuali, spread variabile, weekend (buco) e qualche buco interno"""
    rng = np.random.default_rng(seed)
    t0 = 1_600_000_000 - (1_600_000_000 % 86400)
    ts = []
    for d in range(days):
        base = t0 + d * 86400
        if ((base // 86400) + 4) % 7 in (5, 6):      # sabato/domenica: nessuna barra
            continue
        mins = np.arange(1440)
        if with_gaps:
            keep = np.ones(1440, bool)
            if d % 9 == 3:                            # buco di 2 ore
                keep[600:720] = False
            if d % 13 == 5:                           # buco di 20 minuti
                keep[300:320] = False
            drop = rng.random(1440) < 0.01            # 1% di minuti senza tick
            keep &= ~drop
            mins = mins[keep]
        ts.extend((base + mins * 60).tolist())
    t = np.array(ts, dtype=np.int64)
    n = len(t)
    ret = rng.normal(0, 0.00008, n)
    c = 0.7 * np.exp(np.cumsum(ret))
    o = np.concatenate(([c[0]], c[:-1]))
    hi = np.maximum(o, c) + np.abs(rng.normal(0, 0.00004, n))
    lo = np.minimum(o, c) - np.abs(rng.normal(0, 0.00004, n))
    spr = rng.integers(8, 40, n)
    return t, o, hi, lo, c, spr


def to_tf(t, o, h, l, c, tfsec):
    bk = t // tfsec
    st = np.concatenate(([0], np.flatnonzero(np.diff(bk)) + 1))
    en = np.concatenate((st[1:] - 1, [len(t) - 1]))
    return bk[st] * tfsec, o[st], np.maximum.reduceat(h, st), np.minimum.reduceat(l, st), c[en]


def main():
    ok_all = True

    def chk(name, cond, extra=""):
        nonlocal ok_all
        ok_all &= bool(cond)
        print("  %-62s %s %s" % (name, "OK" if cond else "FAIL", extra))

    t, o, h, l, c, spr = make_m1()
    n1 = len(t)
    pt = 0.00001
    gmax = 90 * 60
    day = (t // 86400 - t[0] // 86400).astype(int)
    split_day = int(day[-1] * 0.7)
    print("barre M1 %d, giorni %d, giorno di split %d" % (n1, day[-1] + 1, split_day))

    # --- 1. buchi e rendimento a H minuti: confronto con una ricerca diretta ---------------------------------
    nb = next_brk(t.tolist(), gmax)
    bad = 0
    for hmin in (1, 5, 30, 240, 1440):
        okf, fcl = fl_fwd_close(t.tolist(), c.tolist(), nb, hmin)
        hs = hmin * 60
        for j in range(0, n1, 7):                    # diretto: finestra [t_j, t_j+H), nessun buco > gmax
            idx = [k for k in range(j, min(n1, j + hmin + 400)) if t[k] < t[j] + hs]
            if not idx:
                exp_ok = False
            else:
                e = idx[-1] + 1
                gaps = [t[k + 1] - t[k] for k in range(j, min(e, n1 - 1))]
                inner = [g for g in gaps[:-1]] if e <= n1 - 1 else gaps
                if e >= n1:
                    exp_ok = False
                else:
                    last_gap = t[e] - t[e - 1]
                    inner_ok = all(g <= gmax for g in [t[k + 1] - t[k] for k in range(j, e - 1)])
                    exp_ok = inner_ok and (last_gap <= gmax or t[e - 1] + 60 >= t[j] + hs)
            if exp_ok != bool(okf[j]):
                bad += 1
            elif exp_ok and abs(fcl[j] - c[idx[-1]]) > 0:
                bad += 1
    chk("rendimento a H minuti sull'orologio M1 (5 orizzonti, ogni 7a barra)", bad == 0, "(%d differenze)" % bad)

    # --- 2. mappa barra TF -> M1 d'ingresso --------------------------------------------------------------
    ok_ent = True
    for tfsec in (300, 3600, 14400):
        tt, oo, hh, ll, cc = to_tf(t, o, h, l, c, tfsec)
        ent = fl_entries(tfsec, tt.tolist(), t.tolist(), len(tt), 5, 0, 2 ** 40)
        for i in range(len(tt) - 1):
            tn = tt[i + 1]
            sp = tn - tt[i]
            want = -1
            if sp - tfsec <= 300:
                k = int(np.searchsorted(t, tn, side="left"))
                if k < n1 and t[k] - tn <= 300:
                    want = k
            if ent[i] != want:
                ok_ent = False
                break
    chk("ingresso = prima barra M1 >= apertura della barra successiva", ok_ent)

    # --- 3. regressione a due passate e cluster per giorno vs calcolo diretto ---------------------------------
    tfsec = 3600
    tt, oo, hh, ll, cc = to_tf(t, o, h, l, c, tfsec)
    n = len(tt)
    ent = fl_entries(tfsec, tt.tolist(), t.tolist(), n, 5, 0, 2 ** 40)
    okf, fcl = fl_fwd_close(t.tolist(), c.tolist(), nb, 60)
    yv, cv, dv, sm = fl_build_y(n, ent, 0, t.tolist(), o.tolist(), spr.tolist(), day.tolist(), okf, fcl, pt, 0.0, 3.5, split_day)
    rng = np.random.default_rng(5)
    feat = rng.normal(size=n)
    feat[:60] = np.nan                                # warm-up
    feat[500:520] = np.nan
    # una feature con un legame reale, per avere t non banali
    yarr = np.array([np.nan if v == EMPTY else v for v in yv])
    sig = np.where(np.isnan(yarr), 0.0, yarr)
    feat2 = 0.15 * (sig - np.nanmean(yarr)) / np.nanstd(yarr) + feat
    feat2[:60] = np.nan
    F = np.concatenate([[EMPTY if np.isnan(x) else x for x in a] for a in (feat, feat2)])
    dva, sma = np.array(dv), np.array(sm)
    worst = 0.0
    for fi, fa in enumerate((feat, feat2)):
        rr = fl_reg(F.tolist(), fi * n, n, yv, dv, sm)
        for k, mask in enumerate((np.ones(n, bool), sma == 0, sma == 1)):
            use = mask & ~np.isnan(fa) & ~np.isnan(yarr)
            beta, tt_, ic = fl.slope_t(fa[use], yarr[use], dva[use])
            got = rr[k]
            diff = max(abs(got["beta"] - beta), abs(got["t"] - tt_), abs(got["ic"] - ic), abs(got["n"] - use.sum()))
            worst = max(worst, diff)
            if k == 0 and fi == 1:
                print("    esempio feature con legame: t = %.2f, IC = %.3f, IC se = %.4f (min IC 2.8 se = %.3f)" % (
                    got["t"], got["ic"], got["icse"], 2.8 * got["icse"]))
    chk("pendenza, t raggruppato per giorno e IC (tutto, IS, OOS) vs flow_lab.slope_t", worst < 1e-8, "(diff max %.2e)" % worst)

    # IC se: confronto con un calcolo diretto dell'errore standard dell'IC
    use = ~np.isnan(feat2) & ~np.isnan(yarr)
    z = (feat2[use] - feat2[use].mean()) / feat2[use].std()
    rc = yarr[use] - yarr[use].mean()
    sxx = (z * z).sum()
    b = (z * rc).sum() / sxx
    S = np.add.reduceat(z * (rc - b * z), fl.day_starts(dva[use]))
    se = math.sqrt((S * S).sum()) / sxx
    ic_se = se / yarr[use].std()
    rr = fl_reg(F.tolist(), n, n, yv, dv, sm)
    chk("errore standard dell'IC (base della tabella di potenza)", abs(rr[0]["icse"] - ic_se) < 1e-9,
        "(%.5f vs %.5f)" % (rr[0]["icse"], ic_se))

    # --- 4. placebo: spostamento circolare = np.roll ------------------------------------------------------------
    worst = 0.0
    for k in (2 * 24, 7 * 24, 31 * 24):
        got = fl_ic_shift(F.tolist(), n, n, yv, k)
        fr = np.roll(feat2, k)
        use = ~np.isnan(fr) & ~np.isnan(yarr)
        ref = float(np.corrcoef(fr[use], yarr[use])[0, 1])
        worst = max(worst, abs(got - ref))
    chk("IC con la feature traslata (3 spostamenti) vs np.roll + corrcoef", worst < 1e-10, "(%.1e)" % worst)

    # --- 5. eventi: costo, lordo, t del netto e abilita' vs flow_lab.event_stats ---------------------------------
    z2 = feat2.copy()
    worst = 0.0
    nchk = 0
    for thr in (0.8, 1.5):
        dirs = fl.events_dir(z2, thr)
        dirs[n - 1] = 0
        evd = [int(x) for x in dirs]
        cells, sk = event_cells(n, evd, yv, cv, dv, sm)
        cost = np.array(cv)
        enx = np.array(ent)
        r_pts = yarr * pt                              # event_stats lavora in prezzo e divide per point
        for smp in range(2):
            mask = sma == smp
            for side, kk in ((1, smp), (-1, 2 + smp)):
                nn, g, net, tn, tsk = fl.event_stats(dirs, side, r_pts, np.where(np.isnan(yarr), 0, np.arange(n)), cost, pt, dva, mask)
                got = cells[kk]
                if nn < 5:
                    continue
                nchk += 1
                worst = max(worst, abs(got["n"] - nn), abs(got["g"] - g), abs(got["net"] - net), abs(got["t"] - tn))
                if side == 1:
                    worst = max(worst, abs(sk[smp] - tsk))
    chk("eventi: n, lordo, netto, t del netto, t dell'abilita' vs flow_lab.event_stats (%d celle)" % nchk, worst < 1e-8,
        "(diff max %.2e)" % worst)

    print("TRASCRIZIONE DELLA PARTE STATISTICA DI FlowLab_MultiTF.mq5:", "COERENTE CON IL CALCOLO DIRETTO" if ok_all else "DIFFERENZE")
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
