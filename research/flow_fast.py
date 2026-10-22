#!/usr/bin/env python3
"""
flow_fast.py - SyntheticDelta v3.x vettorializzato (numpy) per ricerca su anni di barre M1.

Stessa matematica di syntheticdelta_ref.py / SyntheticDelta_v3.0.mq5 (che restano il riferimento barra per
barra): il test di parita' e' in flow_lab.py --parity. Serve perche' un ciclo Python su milioni di barre M1
per ogni timeframe sarebbe troppo lento.
"""
import math

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

SQRT2 = 1.4142135623730951


def phi(x):
    """CDF normale con l'erf di Abramowitz-Stegun 7.1.26, identica a quella dell'indicatore"""
    p, a1, a2, a3, a4, a5 = 0.3275911, 0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429
    s = np.where(x < 0, -1.0, 1.0)
    ax = np.abs(x / SQRT2)
    t = 1.0 / (1.0 + p * ax)
    erf = s * (1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * np.exp(-ax * ax))
    return 0.5 * (1.0 + erf)


def rolling_sum(x, n):
    """somma delle n barre che finiscono in i (NaN dove la finestra non e' completa)"""
    cs = np.concatenate(([0.0], np.cumsum(x)))
    out = np.full(len(x), np.nan)
    out[n - 1:] = cs[n:] - cs[:len(x) - n + 1]
    return out


def roll_z_series(x, M, minfrac=0.5):
    """z-score di x rispetto alle M barre precedenti (corrente esclusa): stessa regola di RollZ"""
    x = np.where(np.isfinite(x), x, np.nan)         # un inf (es. divisione per ATR = 0) avvelenerebbe le somme cumulate
    n = len(x)
    ok = ~np.isnan(x)
    x0 = np.where(ok, x, 0.0)
    cs = np.concatenate(([0.0], np.cumsum(x0)))
    cs2 = np.concatenate(([0.0], np.cumsum(x0 * x0)))
    cn = np.concatenate(([0.0], np.cumsum(ok.astype(float))))
    out = np.full(n, np.nan)
    i = np.arange(1, n)
    lo = np.maximum(0, i - M)
    s, s2, c = cs[i] - cs[lo], cs2[i] - cs2[lo], cn[i] - cn[lo]
    with np.errstate(divide="ignore", invalid="ignore"):
        mu = s / c
        vr = s2 / c - mu * mu
        z = (x[i] - mu) / np.sqrt(vr)
    good = (c >= minfrac * M) & (vr > 1e-12) & ok[i]
    out[i[good]] = z[good]
    return out


def atr_series(h, l, c, p=14):
    """ATR come media semplice del true range (come l'indicatore)"""
    n = len(c)
    tr = np.zeros(n)
    tr[1:] = np.maximum(h[1:], c[:-1]) - np.minimum(l[1:], c[:-1])
    cs = np.concatenate(([0.0], np.cumsum(tr)))
    out = np.full(n, np.nan)
    out[p:] = (cs[p + 1:] - cs[1:n - p + 1]) / p
    return out


def ema_series(c, period):
    """EMA con seme = prima chiusura (come iMA MODE_EMA)"""
    a = 2.0 / (period + 1.0)
    try:
        from scipy.signal import lfilter
        out, _ = lfilter([a], [1.0, -(1.0 - a)], c, zi=[(1.0 - a) * c[0]])
        return out
    except ImportError:
        out = np.empty(len(c))
        e = c[0]
        for i in range(len(c)):
            e = e + a * (c[i] - e) if i else c[0]
            out[i] = e
        return out


def seasonal_weights(t, v, psec, D=20, min_sess=5, cap=3.0):
    """w = volume / mediana del volume nella stessa fascia oraria delle D barre precedenti; -1 se non valido"""
    n = len(v)
    slots = max(1, 86400 // psec)
    slot = np.minimum(((t % 86400) // psec).astype(np.int64), slots - 1)
    w = np.full(n, -1.0)
    order = np.argsort(slot, kind="stable")          # dentro ogni fascia l'ordine resta cronologico
    ss = slot[order]
    cuts = np.flatnonzero(np.diff(ss)) + 1
    starts = np.concatenate(([0], cuts))
    ends = np.concatenate((cuts, [n]))
    for a, b in zip(starts, ends):
        idx = order[a:b]
        m = b - a
        vs = v[idx]
        win = sliding_window_view(np.concatenate((np.full(D, np.nan), vs)), D)[:m]   # win[k] = le D osservazioni prima della k-esima
        srt = np.sort(win, axis=1)                                                   # i NaN finiscono in coda
        cnt = np.minimum(np.arange(m), D)
        rows = np.arange(m)
        hi = cnt // 2
        lo = np.maximum(hi - 1, 0)
        with np.errstate(invalid="ignore"):
            med = np.where(cnt % 2 == 1, srt[rows, hi], 0.5 * (srt[rows, lo] + srt[rows, hi]))
            ok = (cnt >= min_sess) & (med > 0)
            ww = np.full(m, -1.0)
            ww[ok] = np.minimum(vs[ok] / med[ok], cap)
        w[idx] = ww
    return w


def flow_features(t, o, h, l, c, v, psec, N=12, M=500, D=20, min_sess=5, cap=3.0, atr_p=14, bvc_bars=50,
                  mode="clv", use_weights=True, closed_only=True):
    """Restituisce Z (flusso), Ab (assorbimento) e F (media pesata del flusso, in [-1, 1])"""
    n = len(c)
    first = max(atr_p, bvc_bars, N) + 2
    w = seasonal_weights(t, v, psec, D, min_sess, cap)
    valid = w >= 0
    valid[:first] = False
    if closed_only:
        valid[n - 1] = False
    rng = h - l
    if mode == "clv":
        with np.errstate(divide="ignore", invalid="ignore"):
            d = np.where(rng > 0, ((c - l) - (h - c)) / rng, 0.0)
    else:
        dc = np.zeros(n)
        dc[1:] = c[1:] - c[:-1]
        cs = np.concatenate(([0.0], np.cumsum(dc * dc)))
        s2 = np.full(n, np.nan)
        s2[bvc_bars:] = (cs[bvc_bars + 1:] - cs[1:n - bvc_bars + 1]) / bvc_bars
        sg = np.sqrt(s2)
        with np.errstate(divide="ignore", invalid="ignore"):
            d = np.where(sg > 0, 2.0 * phi(dc / sg) - 1.0, 0.0)
    wv = np.where(valid, w if use_weights else 1.0, 0.0)
    fb = wv * d
    nv, sf, sw = rolling_sum(valid.astype(float), N), rolling_sum(fb, N), rolling_sum(wv, N)
    okw = (nv == N) & (sw > 0)
    with np.errstate(divide="ignore", invalid="ignore"):
        F = np.where(okw, sf / sw, np.nan)
    effort = sw / N
    Z = roll_z_series(F, M)
    atr = atr_series(h, l, c, atr_p)
    res = np.full(n, np.nan)
    res[N:] = np.abs(c[N:] - c[:-N]) / (atr[N:] * math.sqrt(N))
    with np.errstate(divide="ignore", invalid="ignore"):
        A = np.where(okw & (atr > 0), np.log(np.maximum(effort, 0.05)) - np.log(res + 0.1), np.nan)
    return {"Z": Z, "Ab": roll_z_series(A, M), "F": F}


def legacy_nd(h, l, c, v, ema_p=13, vol_p=20):
    """normalizedDelta del vecchio indicatore / dell'EA (SD_Core.mqh), senza soglia"""
    n = len(c)
    ema = ema_series(c, ema_p)
    rng = h - l
    cs = np.concatenate(([0.0], np.cumsum(v)))
    avg = np.full(n, np.nan)
    avg[vol_p - 1:] = (cs[vol_p:] - cs[:n - vol_p + 1]) / vol_p
    with np.errstate(divide="ignore", invalid="ignore"):
        vw = np.where(avg > 0, np.minimum(v / avg, 3.0), 1.0)
        nd = ((c - l) / rng * (1.0 + (h - ema) / rng) - (h - c) / rng * (1.0 + (ema - l) / rng)) * vw / 6.0
    nd[~((rng > 0) & (v > 0))] = np.nan
    nd[:vol_p] = np.nan
    return nd
