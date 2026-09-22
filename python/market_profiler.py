#!/usr/bin/env python3
"""
market_profiler.py - Analisi quantitativa approfondita di uno strumento -> report HTML interattivo.

Cosa misura
  1. Movimenti su 4h, 6h, 8h, 12h, 24h, 1w, 2w, 1m, 3m, 6m, 12m: distribuzione dei rendimenti,
     range, MFE/MAE (escursione massima favorevole/avversa), mossa tipica tradotta in prezzo.
  2. Regime per orizzonte: momentum vs mean reversion (Variance Ratio Lo-MacKinlay robusto,
     time-series momentum con t-stat corretto per l'overlap delle finestre).
  3. Matrice lookback x forward: quale movimento passato predice quale movimento futuro.
  4. Quando continua / quando inverte: probabilita' di continuazione condizionata a forza della
     mossa (z in sigma), efficienza del trend (Kaufman ER), regime di volatilita', volume relativo,
     ora del giorno.
  5. Mean reversion verso la media mobile: probabilita' di rientro e di toccare la media entro l'orizzonte.
  6. Forza del trend: in quali condizioni il movimento successivo e' piu' direzionale (ER forward).
  7. Volume: Volume Profile (POC, Value Area 70%), VWAP ancorati, volume corrente vs storico
     (giornaliero e per ora del giorno), sequenze (streak), stagionalita'.

Uso
  python market_profiler.py --mt5 XAUUSD EURUSD US500      # terminale MT5 FP Markets aperto (Windows)
  python market_profiler.py --csv-h1 XAUUSD_H1.csv [--csv-d1 XAUUSD_D1.csv] --name XAUUSD
  python market_profiler.py --yf GC=F                        # Yahoo Finance, solo per test (H1 ~730 giorni)

Note
  - Orari = ora del server MT5 (FP Markets: EET/EEST, GMT+2/+3).
  - Sui CFD il volume e' tick volume: misura l'attivita', non il controvalore scambiato.
  - Le finestre si sovrappongono: le significativita' usano N_eff = durata campione / orizzonte.
"""
import argparse
import html
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import plotly.graph_objects as go
from plotly.offline import get_plotlyjs, get_plotlyjs_version
from plotly.subplots import make_subplots

HOUR = pd.Timedelta(hours=1).value
DAY = pd.Timedelta(days=1).value
SLACK = 5 * DAY  # tolleranza su buchi dati / weekend / festivi
HORIZONS = [("4h", 4 * HOUR), ("6h", 6 * HOUR), ("8h", 8 * HOUR), ("12h", 12 * HOUR), ("24h", DAY),
            ("1w", 7 * DAY), ("2w", 14 * DAY), ("1m", 30 * DAY), ("3m", 91 * DAY), ("6m", 182 * DAY),
            ("12m", 365 * DAY)]
MIN_NEFF = 10
SIG_Z = 2.5  # soglia di significativita' usata nel verdetto (piu' severa di 2 per i test multipli)
Z_EDGES = [0.5, 1, 1.5, 2, 3]
Z_LAB = ["0-0.5σ", "0.5-1σ", "1-1.5σ", "1.5-2σ", "2-3σ", ">3σ"]
DEV_LAB = ["0-0.5σ", "0.5-1σ", "1-1.5σ", "1.5-2σ", "2-3σ", ">3σ"]
Q5 = ["Q1", "Q2", "Q3", "Q4", "Q5"]
FAMILIES = [("z", "Forza mossa passata |z|", Z_LAB),
            ("er", "Efficienza trend passato (ER)", ["Q1 choppy", "Q2", "Q3", "Q4", "Q5 pulito"]),
            ("vol", "Regime volatilità", ["Bassa", "Media", "Alta"]),
            ("rv", "Volume relativo", ["Q1 basso", "Q2", "Q3", "Q4", "Q5 alto"])]
TEMPLATE = "plotly_dark"
BLUE, RED, GREY, AMBER = "#3b82f6", "#ef4444", "#6b7280", "#f59e0b"
DIVERGING = [[0, RED], [0.5, "#1f2937"], [1, BLUE]]


# ----------------------------------------------------------------------------- caricamento dati
def _finish(df):
    df = df.rename(columns=lambda c: str(c).strip("<>").strip().lower())
    kind = None
    for k, lab in (("real_volume", "reale"), ("volume", "reale"), ("vol", "reale"),
                   ("tick_volume", "tick"), ("tickvol", "tick")):
        if k in df and pd.to_numeric(df[k], errors="coerce").fillna(0).sum() > 0:
            df["volume"], kind = df[k], lab
            break
    cols = ["open", "high", "low", "close"] + (["volume"] if kind else [])
    df = df[cols].apply(pd.to_numeric, errors="coerce").dropna(subset=cols[:4])
    df = df[~df.index.duplicated(keep="last")].sort_index()
    return df[(df.close > 0) & (df.high >= df.low)], kind


def load_mt5(symbol, n_h1, n_d1):
    try:
        import MetaTrader5 as mt5
    except ImportError:
        sys.exit("Serve 'pip install MetaTrader5' (solo Windows) con il terminale MT5 aperto e loggato.")
    if not mt5.initialize():
        sys.exit(f"MT5 initialize() fallita: {mt5.last_error()}")
    try:
        if not mt5.symbol_select(symbol, True):
            raise RuntimeError(f"Simbolo '{symbol}' non trovato nel Market Watch (controlla il suffisso del broker).")

        def get(tf, n):
            while n >= 500:
                r = mt5.copy_rates_from_pos(symbol, tf, 0, n)
                if r is not None and len(r) > 0:
                    df = pd.DataFrame(r)
                    df.index = pd.to_datetime(df["time"], unit="s")
                    return df.iloc[:-1]  # scarta la barra in formazione
                n //= 2  # 'Max bars in chart' del terminale puo' limitare la richiesta
            raise RuntimeError(f"Nessun dato per {symbol}: {mt5.last_error()}")

        h1, kind = _finish(get(mt5.TIMEFRAME_H1, n_h1))
        d1, _ = _finish(get(mt5.TIMEFRAME_D1, n_d1))
        info = mt5.symbol_info(symbol)
        return h1, d1, dict(source="MetaTrader 5", digits=info.digits, vol_kind=kind)
    finally:
        mt5.shutdown()


def load_csv(path):
    df = pd.read_csv(path, sep=None, engine="python")
    df = df.rename(columns=lambda c: str(c).strip("<>").strip().lower())

    def parse(s):
        s = s.astype(str).str.replace(r"^(\d{4})\.(\d{2})\.(\d{2})", r"\1-\2-\3", regex=True)
        return pd.to_datetime(s)

    if "date" in df and "time" in df:
        idx = parse(df["date"].astype(str) + " " + df["time"].astype(str))
    else:
        k = next((c for c in ("datetime", "date", "time", "timestamp") if c in df), None)
        if k is None:
            sys.exit(f"{path}: nessuna colonna data/ora riconosciuta")
        idx = pd.to_datetime(df[k], unit="s") if pd.api.types.is_numeric_dtype(df[k]) else parse(df[k])
    idx = pd.DatetimeIndex(idx)
    df.index = idx.tz_convert("UTC").tz_localize(None) if idx.tz is not None else idx
    return _finish(df)


def load_yf(ticker):
    import yfinance as yf

    def dl(**kw):
        df = yf.download(ticker, auto_adjust=False, progress=False, multi_level_index=False, **kw)
        if df.empty:
            raise RuntimeError(f"Yahoo: nessun dato per {ticker} {kw}")
        idx = df.index
        df.index = idx.tz_convert("UTC").tz_localize(None) if idx.tz is not None else idx
        return _finish(df)

    h1, kind = dl(period="730d", interval="1h")
    d1, _ = dl(period="max", interval="1d")
    return h1, d1, dict(source="Yahoo Finance (UTC)", digits=None, vol_kind=kind)


def daily_from_intraday(h1):
    agg = {"open": "first", "high": "max", "low": "min", "close": "last"}
    if "volume" in h1:
        agg["volume"] = "sum"
    return h1.resample("1D").agg(agg).dropna(subset=["close"])


# ----------------------------------------------------------------------------- strutture numeriche
class RMQ:
    """Sparse table: max/min sull'intervallo [l, r] in O(1) per query, vettoriale."""

    def __init__(self, a, fn):
        self.fn, self.tab = fn, [np.asarray(a, float)]
        k = 1
        while (1 << k) <= len(a):
            prev, half = self.tab[-1], 1 << (k - 1)
            self.tab.append(fn(prev[:-half], prev[half:]))
            k += 1

    def __call__(self, l, r):
        k = np.log2(r - l + 1).astype(int)
        out = np.empty(len(l))
        for kk in np.unique(k):
            m = k == kk
            t = self.tab[kk]
            out[m] = self.fn(t[l[m]], t[r[m] - (1 << kk) + 1])
        return out


class Bars:
    def __init__(self, df, name):
        self.name, self.df, self.idx = name, df, df.index
        self.t = df.index.values.astype("datetime64[ns]").astype(np.int64)
        self.tf = int(np.median(np.diff(self.t))) if len(df) > 1 else DAY
        self.intraday = self.tf < DAY
        if not self.intraday:
            self.tf = DAY
        self.tc = self.t + self.tf  # orario di chiusura barra = istante decisionale
        self.o, self.h, self.l, self.c = (df[k].to_numpy(float) for k in ("open", "high", "low", "close"))
        self.n = len(df)
        self.lr = np.r_[np.nan, np.diff(np.log(self.c))]
        self.S = np.r_[0.0, np.cumsum(np.abs(np.diff(self.c)))]  # lunghezza del percorso, per l'ER
        self.CS = np.cumsum(self.c)
        self.bpd = DAY / self.tf
        span = int(20 * self.bpd) if self.intraday else 60
        self.sig = np.sqrt(pd.Series(self.lr ** 2).ewm(span=span, min_periods=span // 2).mean().to_numpy())
        self.hi, self.lo = RMQ(self.h, np.maximum), RMQ(self.l, np.minimum)
        self.v = None
        if "volume" in df and df["volume"].fillna(0).sum() > 0:
            v = df["volume"].fillna(0).astype(float)
            if self.intraday:  # atteso per la stessa ora del giorno: elimina la stagionalita' intraday
                exp = v.groupby(df.index.hour).transform(lambda s: s.ewm(span=20, min_periods=5).mean().shift(1))
            else:
                exp = v.ewm(span=20, min_periods=5).mean().shift(1)
            self.v, self.vexp = v.to_numpy(), exp.to_numpy()
            bad = ~np.isfinite(self.vexp) | (self.vexp <= 0)
            self.rvol = np.where(bad, np.nan, self.v / np.where(bad, 1, self.vexp))
            self.CV, self.CE = np.cumsum(self.v), np.cumsum(np.where(bad, 0, self.vexp))
            self.CB = np.cumsum(bad)

    def fwd(self, h):
        """j = prima barra che chiude almeno h dopo la chiusura di i (uscita realistica dopo gap/weekend)."""
        target = self.tc + h
        j = np.searchsorted(self.tc, target, side="left")
        jj = np.minimum(j, self.n - 1)
        ok = (j < self.n) & (self.tc[jj] - target <= SLACK) & (jj > np.arange(self.n))
        return jj, dense(jj - np.arange(self.n), ok)

    def back(self, h):
        """p = ultima barra chiusa almeno h prima della chiusura di i."""
        target = self.tc - h
        p = np.searchsorted(self.tc, target, side="right") - 1
        pp = np.maximum(p, 0)
        ok = (p >= 0) & (target - self.tc[pp] <= SLACK) & (pp < np.arange(self.n))
        return pp, dense(np.arange(self.n) - pp, ok)

    def window_rvol(self, p, i):
        if self.v is None:
            return np.full(len(i), np.nan)
        ev = self.CE[i] - self.CE[p]
        ok = (self.CB[i] - self.CB[p] == 0) & (ev > 0)
        return np.where(ok, (self.CV[i] - self.CV[p]) / np.where(ok, ev, 1), np.nan)


class Ctx:
    def __init__(self, name, h1, d1, meta):
        self.name, self.meta = name, meta
        self.h1 = Bars(h1, "H1") if h1 is not None and len(h1) > 500 else None
        if self.h1 is not None and not self.h1.intraday:
            self.h1 = None
        self.d1 = Bars(d1, "D1")
        self.bpw = max(1.0, (self.d1.t >= self.d1.t[-1] - 364 * DAY).sum() / 52)
        self.base = self.h1 or self.d1
        self.last = self.base.c[-1]
        d = meta.get("digits")
        self.digits = int(d) if d is not None else int(np.clip(5 - np.floor(np.log10(self.last)), 0, 5))
        self.horizons = [(n, h) for n, h in HORIZONS if self.bars_for(h) is not None]

    def bars_for(self, h):
        return self.h1 if h <= DAY else self.d1

    def q_for(self, b, h):
        return max(1, round(h / b.tf)) if b.intraday else max(1, round(h / DAY * self.bpw / 7))

    def px(self, x):
        return fmt(x, self.digits)


# ----------------------------------------------------------------------------- statistica
def nw_t(x, lag):
    """t-stat della media con errore standard Newey-West (autocovarianze via FFT)."""
    x = np.asarray(x, float)
    n = len(x)
    if n < 20:
        return np.nan
    d = x - x.mean()
    lag = int(min(max(lag, 0), n - 1))
    f = np.fft.rfft(d, 2 * n)
    ac = np.fft.irfft(f * np.conj(f))[: lag + 1] / n
    w = 1 - np.arange(lag + 1) / (lag + 1)
    s = ac[0] + 2 * (w[1:] * ac[1:]).sum()
    return x.mean() / np.sqrt(s / n) if s > 0 else np.nan


def variance_ratio(logp, q):
    """VR(q) di Lo-MacKinlay con z robusto all'eteroschedasticita'. VR>1 persistenza, VR<1 mean reversion."""
    logp = logp[np.isfinite(logp)]
    r = np.diff(logp)
    n = len(r)
    if q < 2 or n < 5 * q:
        return np.nan, np.nan
    mu = r.mean()
    d = r - mu
    var1 = d @ d / (n - 1)
    rq = logp[q:] - logp[:-q]
    varq = ((rq - q * mu) ** 2).sum() / (q * (n - q + 1) * (1 - q / n))
    vr = varq / var1
    e2 = d ** 2
    den = e2.sum() ** 2
    theta = sum((2 * (q - k) / q) ** 2 * n * (e2[k:] @ e2[:-k]) / den for k in range(1, q))
    return vr, np.sqrt(n) * (vr - 1) / np.sqrt(theta)


def dense(cnt, ok):
    """Scarta le finestre con meno della meta' delle barre tipiche: cadono per lo piu' a mercato chiuso."""
    if ok.any():
        ok &= cnt >= max(1, 0.5 * np.median(cnt[ok]))
    return ok


def bucketize(x, inner):
    k = np.digitize(x, inner)
    return np.where(np.isfinite(x), k, -1)


def qedges(x, k):
    x = x[np.isfinite(x)]
    return np.percentile(x, np.linspace(0, 100, k + 1)[1:-1]) if len(x) else np.array([])


def fmt(x, d=2, suf=""):
    try:
        if x is None or not np.isfinite(x):
            return "–"
    except TypeError:
        return str(x)
    return f"{x:.{d}f}{suf}"


# ----------------------------------------------------------------------------- analisi
def horizon_stats(ctx):
    rows, hists = [], {}
    for name, h in ctx.horizons:
        b = ctx.bars_for(h)
        j, ok = b.fwd(h)
        i, j = np.flatnonzero(ok), j[ok]
        if len(i) < 30:
            continue
        e = b.c[i]
        r = b.c[j] / e - 1
        hi, lo = b.hi(i + 1, j), b.lo(i + 1, j)
        mfe, mae, rng = hi / e - 1, 1 - lo / e, (hi - lo) / e
        lr = pd.Series(np.log1p(r))
        lg = np.log(rng[rng > 0])
        cnt, ed = np.histogram(lg, bins=60)
        k = cnt.argmax()
        q = ctx.q_for(b, h)
        vr, vz = variance_ratio(np.log(b.c), q)
        rows.append(dict(
            name=name, h=h, tf=b.name, N=len(i), neff=(b.tc[i[-1]] - b.tc[i[0]]) / h,
            mean=r.mean(), t=nw_t(r, np.ceil(np.mean(j - i))), med=np.median(r), std=r.std(), up=(r > 0).mean(),
            skew=lr.skew(), kurt=lr.kurt(), qs=np.percentile(r, [5, 25, 75, 95]),
            absmed=np.median(np.abs(r)), rng_med=np.median(rng), rng_mode=np.exp((ed[k] + ed[k + 1]) / 2),
            mfe=np.percentile(mfe, [50, 75, 90]), mae=np.percentile(mae, [50, 75, 90]), vq=q, vr=vr, vz=vz))
        lo_, hi_ = np.percentile(r, [0.5, 99.5])
        cnt, ed = np.histogram(r, bins=80, range=(lo_, hi_))
        hists[name] = (ed, cnt / max(cnt.sum(), 1))
    return rows, hists


def combined_close(ctx):
    d = ctx.d1
    if ctx.h1 is None:
        return d.tc, d.c
    m = d.tc <= ctx.h1.tc[0]
    return np.r_[d.tc[m], ctx.h1.tc], np.r_[d.c[m], ctx.h1.c]


def tsmom_matrix(ctx):
    """Payoff sign(rendimento passato su lookback) * rendimento futuro su forward, per ogni coppia."""
    ctc, cc = combined_close(ctx)
    hz = ctx.horizons
    T, P, NE = (np.full((len(hz), len(hz)), np.nan) for _ in range(3))
    for a, (_, lb) in enumerate(hz):
        for bb, (_, fw) in enumerate(hz):
            anc = ctx.h1 if min(lb, fw) <= DAY else ctx.d1
            ta, ca = anc.tc, anc.c
            tp, tf_ = ta - lb, ta + fw
            p = np.searchsorted(ctc, tp, "right") - 1
            f = np.searchsorted(ctc, tf_, "left")
            ok = (p >= 0) & (f < len(ctc))
            p, f = np.clip(p, 0, len(ctc) - 1), np.clip(f, 0, len(ctc) - 1)
            ok &= (tp - ctc[p] <= SLACK) & (ctc[f] - tf_ <= SLACK) & (ctc[f] > ta)
            pos = np.searchsorted(ctc, ta, "left")
            if fw <= DAY:
                ok = dense(f - pos, ok)
            if lb <= DAY:
                ok = dense(pos - p, ok)
            if ok.sum() < 30:
                continue
            s = np.sign(np.log(ca[ok] / cc[p[ok]])) * (cc[f[ok]] / ca[ok] - 1)
            neff = (ta[ok][-1] - ta[ok][0]) / fw
            if neff < MIN_NEFF or s.std() == 0:
                continue
            T[a, bb], P[a, bb], NE[a, bb] = s.mean() / (s.std() / np.sqrt(neff)), (s > 0).mean(), neff
    return dict(names=[n for n, _ in hz], T=T, P=P, NE=NE)


def _cell(n, ne, hit, pay, erf=None, base_erf=None):
    return dict(n=n, ne=ne, P=hit.mean(), zP=(hit.mean() - 0.5) / np.sqrt(0.25 / ne),
                mean=pay.mean(), t=pay.mean() / (pay.std() / np.sqrt(ne)) if pay.std() > 0 else np.nan,
                ERr=np.nanmean(erf) / base_erf if erf is not None else np.nan)


def conditional(ctx):
    """Continuazione (lookback = forward = orizzonte) condizionata a forza, efficienza, volatilita', volume, ora."""
    cond = {k: dict(title=t, labels=lab, data={}, edges={}) for k, t, lab in FAMILIES}
    hours = dict(P={}, zP={}, ERr={}, N={})
    overall = {}
    for name, h in ctx.horizons:
        b = ctx.bars_for(h)
        j, okf = b.fwd(h)
        p, okb = b.back(h)
        ok = okf & okb & np.isfinite(b.sig) & (b.sig > 0)
        i, j, p = np.flatnonzero(ok), j[ok], p[ok]
        if len(i) < 100:
            continue
        ci, cj, cp = b.c[i], b.c[j], b.c[p]
        past = np.log(ci / cp)
        s = np.sign(past) * (cj / ci - 1)
        hit = s > 0
        pl, plf = b.S[i] - b.S[p], b.S[j] - b.S[i]
        feats = dict(z=np.abs(past) / (b.sig[i] * np.sqrt(i - p)),
                     er=np.where(pl > 0, np.abs(ci - cp) / np.where(pl > 0, pl, 1), np.nan),
                     vol=b.sig[i], rv=b.window_rvol(p, i))
        erf = np.where(plf > 0, np.abs(cj - ci) / np.where(plf > 0, plf, 1), np.nan)
        base_erf = np.nanmean(erf)
        w = (b.tc[i[-1]] - b.tc[i[0]]) / h / len(i)  # N_eff per osservazione
        overall[name] = _cell(len(i), len(i) * w, hit, s)
        for key, _, lab in FAMILIES:
            x = feats[key]
            if not np.isfinite(x).any():
                continue
            inner = np.array(Z_EDGES) if key == "z" else qedges(x, len(lab))
            cond[key]["edges"][name] = inner
            k = bucketize(x, inner)
            cell = {}
            for bi, lb in enumerate(lab):
                m = k == bi
                if m.sum() >= 30:
                    cell[lb] = _cell(m.sum(), m.sum() * w, hit[m], s[m], erf[m], base_erf)
            cond[key]["data"][name] = cell
        if b.intraday:
            hrs = pd.DatetimeIndex(b.tc[i]).hour.to_numpy()
            arr = {k: np.full(24, np.nan) for k in hours}
            for hh in range(24):
                m = hrs == hh
                if m.sum() >= 30:
                    c = _cell(m.sum(), m.sum() * w, hit[m], s[m], erf[m], base_erf)
                    arr["P"][hh], arr["zP"][hh], arr["ERr"][hh], arr["N"][hh] = c["P"], c["zP"], c["ERr"], c["ne"]
            for k in hours:
                hours[k][name] = arr[k]
    return cond, hours, overall


def mean_reversion(ctx):
    """Distanza dalla media mobile (finestra 2x orizzonte) -> rientro verso la media entro l'orizzonte."""
    out = dict(labels=DEV_LAB, data={})
    for name, h in ctx.horizons:
        b = ctx.bars_for(h)
        j, okf = b.fwd(h)
        p, okb = b.back(2 * h)
        ok = okf & okb & np.isfinite(b.sig) & (b.sig > 0)
        i, j, p = np.flatnonzero(ok), j[ok], p[ok]
        if len(i) < 100:
            continue
        ci = b.c[i]
        ma = (b.CS[i] - b.CS[p]) / (i - p)
        dev = np.log(ci / ma) / (b.sig[i] * np.sqrt(np.maximum((i - p) / 2, 1)))
        rev = -np.sign(dev) * (b.c[j] / ci - 1)
        touch = np.where(dev > 0, b.lo(i + 1, j) <= ma, b.hi(i + 1, j) >= ma)
        w = (b.tc[i[-1]] - b.tc[i[0]]) / h / len(i)
        k = bucketize(np.abs(dev), np.array(Z_EDGES))
        cell = {}
        for bi, lb in enumerate(DEV_LAB):
            m = k == bi
            if m.sum() >= 30:
                c = _cell(m.sum(), m.sum() * w, rev[m] > 0, rev[m])
                c["touch"] = touch[m].mean()
                cell[lb] = c
        out["data"][name] = cell
    return out


def current_state(ctx, cond, mr):
    rows = []
    for name, h in ctx.horizons:
        b = ctx.bars_for(h)
        n = b.n - 1
        p, ok = b.back(h)
        if not ok[n] or not np.isfinite(b.sig[n]):
            continue
        p = p[n]
        past = np.log(b.c[n] / b.c[p])
        pl = b.S[n] - b.S[p]
        feats = dict(z=abs(past) / (b.sig[n] * np.sqrt(n - p)), er=abs(b.c[n] - b.c[p]) / pl if pl > 0 else np.nan,
                     vol=b.sig[n], rv=b.window_rvol(np.array([p]), np.array([n]))[0])
        r = dict(name=name, past=np.expm1(past), z=feats["z"], fam={})
        for key, _, lab in FAMILIES:
            inner = cond[key]["edges"].get(name)
            if inner is None or not np.isfinite(feats[key]):
                continue
            lb = lab[int(np.digitize(feats[key], inner))]
            r["fam"][key] = (lb, cond[key]["data"].get(name, {}).get(lb))
        p2, ok2 = b.back(2 * h)
        if ok2[n]:
            p2 = p2[n]
            ma = (b.CS[n] - b.CS[p2]) / (n - p2)
            dev = np.log(b.c[n] / ma) / (b.sig[n] * np.sqrt(max((n - p2) / 2, 1)))
            lb = DEV_LAB[int(np.digitize(abs(dev), Z_EDGES))]
            r.update(ma=ma, dev=dev, mr=(lb, mr["data"].get(name, {}).get(lb)))
        rows.append(r)
    return rows


def streaks(ctx):
    """P(la barra successiva ha lo stesso segno | k barre consecutive nello stesso verso)."""
    series = {"D1": pd.Series(ctx.d1.c, ctx.d1.idx)}
    if ctx.h1 is not None:
        series = {"H1": pd.Series(ctx.h1.c, ctx.h1.idx), **series}
    series["W1"] = series["D1"].resample("W-FRI").last().dropna()
    out = {}
    for tf, c in series.items():
        s = np.sign(np.diff(c.to_numpy()))
        s = s[s != 0]
        if len(s) < 50:
            continue
        starts = np.r_[0, np.flatnonzero(np.diff(s)) + 1]
        lens, sg = np.diff(np.r_[starts, len(s)])[:-1], s[starts][:-1]  # l'ultima sequenza e' incompleta
        res = {}
        for sign, lab in ((1, "up"), (-1, "down")):
            L = lens[sg == sign]
            pr, nn = [], []
            for k in range(1, 7):
                ge = (L >= k).sum()
                pr.append((L > k).sum() / ge if ge >= 20 else np.nan)
                nn.append(ge)
            res[lab] = dict(P=pr, N=nn, base=(s == sign).mean())
        out[tf] = res
    return out


def seasonality(ctx):
    out = {}
    if ctx.h1 is not None:
        b = ctx.h1
        df = pd.DataFrame({"r": b.lr * 1e4, "a": np.abs(b.lr) * 1e4}, index=b.idx).dropna()
        g = df.groupby(df.index.hour)
        out["hour"] = pd.DataFrame({"mean": g.r.mean(), "se": g.r.std() / np.sqrt(g.r.count()), "abs": g.a.mean()})
    d = ctx.d1
    df = pd.DataFrame({"r": d.lr * 1e4, "a": np.abs(d.lr) * 1e4}, index=d.idx).dropna()
    df = df[df.index.dayofweek < 7]
    g = df.groupby(df.index.dayofweek)
    out["dow"] = pd.DataFrame({"mean": g.r.mean(), "se": g.r.std() / np.sqrt(g.r.count()), "abs": g.a.mean(),
                               "up": g.r.apply(lambda x: (x > 0).mean())})
    m = pd.Series(d.c, d.idx).resample("ME").last().pct_change().dropna() * 100
    g = m.groupby(m.index.month)
    out["month"] = pd.DataFrame({"mean": g.mean(), "se": g.std() / np.sqrt(g.count()),
                                 "up": g.apply(lambda x: (x > 0).mean()), "n": g.count()})
    return out


def volume_profile(b, start, nbins=120):
    m = b.t >= start
    if m.sum() < 5:
        return None
    h, l, c, v = b.h[m], b.l[m], b.c[m], b.v[m]
    lo, hi = l.min(), h.max()
    if hi <= lo:
        return None
    w = (hi - lo) / nbins
    a = np.clip(((l - lo) / w).astype(int), 0, nbins - 1)
    z = np.clip(((h - lo) / w).astype(int), 0, nbins - 1)
    per = v / (z - a + 1)  # volume di ogni barra distribuito uniformemente sul suo range
    diff = np.zeros(nbins + 1)
    np.add.at(diff, a, per)
    np.add.at(diff, z + 1, -per)
    prof = np.cumsum(diff)[:nbins]
    poc = int(prof.argmax())
    lo_i = hi_i = poc
    acc, tot = prof[poc], prof.sum()
    while acc < 0.7 * tot and (lo_i > 0 or hi_i < nbins - 1):
        up = prof[hi_i + 1] if hi_i < nbins - 1 else -1
        dn = prof[lo_i - 1] if lo_i > 0 else -1
        if up >= dn:
            hi_i += 1
            acc += up
        else:
            lo_i -= 1
            acc += dn
    ctr = lo + (np.arange(nbins) + 0.5) * w
    return dict(ctr=ctr, prof=prof, poc=ctr[poc], val=lo + lo_i * w, vah=lo + (hi_i + 1) * w, w=w,
                vwap=((h + l + c) / 3 * v).sum() / v.sum(), va=(lo_i, hi_i), poc_i=poc)


def volume_analysis(ctx):
    b = ctx.base
    if b.v is None:
        return None
    end = b.t[-1]
    prof = {}
    for lab, days in (("12 mesi", 365), ("6 mesi", 182), ("3 mesi", 91), ("1 mese", 30), ("1 settimana", 7)):
        pf = volume_profile(b, end - days * DAY)
        if pf:
            prof[lab] = pf
    out = dict(profiles=prof)
    d = ctx.d1
    if d.v is not None:
        v = pd.Series(d.v, d.idx)
        out["daily"] = dict(last=v.iloc[-1], ma20=v.iloc[-21:-1].mean(), ma252=v.iloc[-253:-1].mean(),
                            pct=(v.iloc[-253:-1] < v.iloc[-1]).mean(), last5=v.iloc[-5:].mean(),
                            date=v.index[-1])
    if ctx.h1 is not None and ctx.h1.v is not None:
        h = ctx.h1
        v = pd.Series(h.v, h.idx)
        t_end = h.idx[-1]
        out["hourly"] = dict(
            y12=v[v.index >= t_end - pd.Timedelta(days=365)].groupby(lambda x: x.hour).mean(),
            d20=v[v.index >= t_end - pd.Timedelta(days=28)].groupby(lambda x: x.hour).mean(),
            last=v[v.index.normalize() == t_end.normalize()].groupby(lambda x: x.hour).mean(),
            rvol_last=h.rvol[-1], last_time=t_end)
    return out


def trend_summary(ctx):
    d = ctx.d1
    c = pd.Series(d.c, d.idx)
    days = max((d.idx[-1] - d.idx[0]).days, 1)
    ann = np.sqrt(ctx.bpw * 52)
    dd = c / c.cummax() - 1
    s50, s200 = c.rolling(50).mean(), c.rolling(200).mean()
    rv20 = pd.Series(d.lr, d.idx).rolling(20).std() * ann
    rets = {}
    for name, h in HORIZONS[5:]:
        p, ok = d.back(h)
        if ok[-1]:
            rets[name] = d.c[-1] / d.c[p[-1]] - 1
    y = c[c.index >= c.index[-1] - pd.Timedelta(days=365)]
    rvh = rv20.dropna()
    return dict(start=d.idx[0], end=ctx.base.idx[-1], last=ctx.last, cagr=(c.iloc[-1] / c.iloc[0]) ** (365.25 / days) - 1,
                vol=np.nanstd(d.lr) * ann, mdd=dd.min(), cur_dd=dd.iloc[-1],
                above200=(c > s200)[s200.notna()].mean(), s50=s50.iloc[-1], s200=s200.iloc[-1], rets=rets,
                hi52=y.max(), lo52=y.min(), rv20=rv20.iloc[-1],
                rv_pct=(rvh < rvh.iloc[-1]).mean() if len(rvh) else np.nan)


# ----------------------------------------------------------------------------- grafici
def _layout(fig, h, **kw):
    lay = dict(template=TEMPLATE, height=h, margin=dict(l=50, r=20, t=50, b=40), paper_bgcolor="rgba(0,0,0,0)",
               plot_bgcolor="rgba(0,0,0,0)", legend=dict(orientation="h", y=1.08, x=0))
    lay.update(kw)
    fig.update_layout(**lay)
    return fig


def fig_history(ctx):
    d = ctx.d1
    c = pd.Series(d.c, d.idx)
    lp = np.log(c)
    has_v = d.v is not None
    titles = ["Prezzo (scala log) con SMA50 / SMA200", "Drawdown %",
              "Variance Ratio mobile (1 anno): >1 fasi di trend, <1 fasi di mean reversion"]
    if has_v:
        titles.append("Volume giornaliero con media 20 / 252 barre")
    fig = make_subplots(len(titles), 1, shared_xaxes=True, vertical_spacing=0.04, subplot_titles=titles,
                        row_heights=[0.42, 0.14, 0.22, 0.22][: len(titles)])
    fig.add_scatter(x=c.index, y=c, name="Close", line=dict(width=1.3, color="#e5e7eb"), row=1, col=1)
    fig.add_scatter(x=c.index, y=c.rolling(50).mean(), name="SMA50", line=dict(width=1, color=AMBER), row=1, col=1)
    fig.add_scatter(x=c.index, y=c.rolling(200).mean(), name="SMA200", line=dict(width=1, color=BLUE), row=1, col=1)
    fig.update_yaxes(type="log", row=1, col=1)
    dd = (c / c.cummax() - 1) * 100
    fig.add_scatter(x=dd.index, y=dd, name="Drawdown", fill="tozeroy", line=dict(width=0.8, color=RED),
                    showlegend=False, row=2, col=1)
    r1 = lp.diff()
    wk, mo = max(2, round(ctx.bpw)), max(2, round(ctx.bpw * 52 / 12))
    for q, col in ((wk, "#a78bfa"), (mo, "#34d399")):
        vr = lp.diff(q).rolling(252).var() / (q * r1.rolling(252).var())
        fig.add_scatter(x=vr.index, y=vr, name=f"VR({q} barre)", line=dict(width=1.1, color=col), row=3, col=1)
    fig.add_hline(y=1, line=dict(color=GREY, dash="dash"), row=3, col=1)
    if has_v:
        v = pd.Series(d.v, d.idx)
        fig.add_bar(x=v.index, y=v, name="Volume", marker_color="#374151", showlegend=False, row=4, col=1)
        fig.add_scatter(x=v.index, y=v.rolling(20).mean(), name="Vol MA20", line=dict(width=1, color=AMBER), row=4, col=1)
        fig.add_scatter(x=v.index, y=v.rolling(252).mean(), name="Vol MA252", line=dict(width=1.2, color=BLUE), row=4, col=1)
    return _layout(fig, 950 if has_v else 780, hovermode="x unified")


def fig_hists(hists):
    names = list(hists)
    nc = 4
    nr = int(np.ceil(len(names) / nc))
    fig = make_subplots(nr, nc, subplot_titles=[f"Rendimento {n} (%)" for n in names],
                        vertical_spacing=0.09, horizontal_spacing=0.05)
    for k, nm in enumerate(names):
        ed, pr = hists[nm]
        ctr = (ed[:-1] + ed[1:]) / 2 * 100
        fig.add_bar(x=ctr, y=pr * 100, marker_color=[BLUE if x >= 0 else RED for x in ctr], showlegend=False,
                    hovertemplate="%{x:.2f}%: %{y:.2f}% dei casi<extra></extra>", row=k // nc + 1, col=k % nc + 1)
    return _layout(fig, 220 * nr + 60, bargap=0)


def fig_vr(rows):
    rows = [r for r in rows if np.isfinite(r["vr"])]
    col = [BLUE if r["vz"] > 2 else RED if r["vz"] < -2 else GREY for r in rows]
    fig = go.Figure(go.Bar(x=[r["name"] for r in rows], y=[r["vr"] - 1 for r in rows], marker_color=col,
                           text=[f"z {r['vz']:.1f}" for r in rows], textposition="outside",
                           hovertemplate="%{x}: VR-1 = %{y:.3f}<extra></extra>"))
    fig.add_hline(y=0, line=dict(color=GREY))
    return _layout(fig, 360, yaxis_title="VR − 1  (>0 trend · <0 mean reversion)")


def _heat(z, text, x, y, custom=None, hover="", zmax=None):
    zmax = zmax or np.nanmax(np.abs(z)) if np.isfinite(z).any() else 1
    return go.Heatmap(z=z, x=x, y=y, text=text, texttemplate="%{text}", textfont=dict(size=10),
                      colorscale=DIVERGING, zmid=0, zmin=-zmax, zmax=zmax, customdata=custom,
                      hovertemplate=hover + "<extra></extra>", xgap=1, ygap=1, showscale=False)


def fig_tsmom(tm):
    T, P = np.clip(tm["T"], -4, 4), tm["P"]
    text = np.where(np.isfinite(T), np.vectorize(lambda p: f"{p * 100:.0f}%")(np.nan_to_num(P)), "")
    fig = go.Figure(_heat(T, text, tm["names"], tm["names"], np.dstack([tm["NE"], tm["P"] * 100]),
                          "lookback %{y} → forward %{x}<br>t = %{z:.2f}<br>hit %{customdata[1]:.1f}%"
                          "<br>N_eff %{customdata[0]:.0f}", zmax=4))
    fig.data[0].showscale = True
    fig.data[0].colorbar = dict(title="t")
    return _layout(fig, 520, xaxis_title="Orizzonte futuro (forward)", yaxis_title="Mossa passata (lookback)",
                   yaxis_autorange="reversed")


def fig_conditional(cond, names, metric):
    fams = [k for k, _, _ in FAMILIES if cond[k]["data"]]
    fig = make_subplots(1, len(fams), shared_yaxes=True, horizontal_spacing=0.02,
                        subplot_titles=[cond[k]["title"] for k in fams],
                        column_widths=[len(cond[k]["labels"]) for k in fams])
    for c, k in enumerate(fams):
        lab = cond[k]["labels"]
        z = np.full((len(names), len(lab)), np.nan)
        text = np.full(z.shape, "", dtype=object)
        cust = np.full(z.shape + (3,), np.nan)
        for a, nm in enumerate(names):
            for bb, lb in enumerate(lab):
                cell = cond[k]["data"].get(nm, {}).get(lb)
                if not cell:
                    continue
                star = "*" if abs(cell["zP"]) > SIG_Z else ""
                if metric == "P":
                    z[a, bb] = (cell["P"] - 0.5) * 100
                    text[a, bb] = f"{cell['P'] * 100:.0f}%{star}"
                else:
                    z[a, bb] = (cell["ERr"] - 1) * 100
                    text[a, bb] = f"{cell['ERr']:.2f}"
                cust[a, bb] = (cell["ne"], cell["mean"] * 100, cell["t"])
        hover = ("%{y} · %{x}<br>" + ("P(continua) − 50 = %{z:.1f} pt" if metric == "P" else "ER forward vs media: %{z:+.1f}%")
                 + "<br>payoff medio %{customdata[1]:.3f}%  t=%{customdata[2]:.2f}<br>N_eff %{customdata[0]:.0f}")
        fig.add_trace(_heat(z, text, lab, names, cust, hover, zmax=15 if metric == "P" else 30), 1, c + 1)
    fig.update_yaxes(autorange="reversed")
    return _layout(fig, 90 + 36 * len(names))


def fig_hours(hours):
    names = list(hours["P"])
    if not names:
        return None
    fig = make_subplots(1, 2, shared_yaxes=True, horizontal_spacing=0.04,
                        subplot_titles=["P(continuazione) per ora di ingresso", "Forza del trend successivo (ER forward / media)"])
    P = np.array([hours["P"][n] for n in names]).T
    Z = np.array([hours["zP"][n] for n in names]).T
    E = np.array([hours["ERr"][n] for n in names]).T
    N = np.array([hours["N"][n] for n in names]).T
    hrs = [f"{h:02d}:00" for h in range(24)]
    tp = np.where(np.isfinite(P), np.vectorize(lambda p, z: f"{p * 100:.0f}{'*' if abs(z) > SIG_Z else ''}")(
        np.nan_to_num(P), np.nan_to_num(Z)), "")
    te = np.where(np.isfinite(E), np.vectorize(lambda e: f"{e:.2f}")(np.nan_to_num(E)), "")
    fig.add_trace(_heat((P - 0.5) * 100, tp, names, hrs, N, "ore %{y} · %{x}: P−50 = %{z:.1f} pt<br>N_eff %{customdata:.0f}",
                        zmax=10), 1, 1)
    fig.add_trace(_heat((E - 1) * 100, te, names, hrs, N, "ore %{y} · %{x}: ER vs media %{z:+.1f}%", zmax=25), 1, 2)
    fig.update_yaxes(autorange="reversed")
    return _layout(fig, 720)


def fig_mr(mr, names):
    lab = mr["labels"]
    z = np.full((len(names), len(lab)), np.nan)
    text = np.full(z.shape, "", dtype=object)
    cust = np.full(z.shape + (3,), np.nan)
    for a, nm in enumerate(names):
        for bb, lb in enumerate(lab):
            c = mr["data"].get(nm, {}).get(lb)
            if c:
                z[a, bb] = (c["P"] - 0.5) * 100
                text[a, bb] = f"{c['P'] * 100:.0f}% · {c['touch'] * 100:.0f}%{'*' if abs(c['zP']) > SIG_Z else ''}"
                cust[a, bb] = (c["ne"], c["mean"] * 100, c["touch"] * 100)
    fig = go.Figure(_heat(z, text, lab, names, cust,
                          "%{y} · distanza %{x}<br>P(rientro) − 50 = %{z:.1f} pt<br>P(tocca la media) %{customdata[2]:.0f}%"
                          "<br>rientro medio %{customdata[1]:.3f}%<br>N_eff %{customdata[0]:.0f}", zmax=15))
    return _layout(fig, 90 + 36 * len(names), xaxis_title="Distanza dalla media mobile (in σ dell'orizzonte)",
                   yaxis_autorange="reversed")


def fig_streaks(st):
    fig = make_subplots(1, 2, subplot_titles=["Dopo k barre rialziste consecutive", "Dopo k barre ribassiste consecutive"])
    cols = {"H1": "#a78bfa", "D1": AMBER, "W1": "#34d399"}
    for c, lab in enumerate(("up", "down")):
        for tf, res in st.items():
            r = res[lab]
            fig.add_scatter(x=list(range(1, 7)), y=np.array(r["P"]) * 100, mode="lines+markers", name=tf,
                            line=dict(color=cols[tf]), showlegend=c == 0, customdata=r["N"],
                            hovertemplate=f"{tf}: k=%{{x}} → P(continua) %{{y:.1f}}%  (N=%{{customdata}})<extra></extra>",
                            row=1, col=c + 1)
            fig.add_hline(y=r["base"] * 100, line=dict(color=cols[tf], dash="dot", width=1), row=1, col=c + 1)
    fig.update_xaxes(title="k barre consecutive")
    fig.update_yaxes(title="P(barra successiva stesso verso) %", col=1)
    return _layout(fig, 430, legend=dict(orientation="h", y=-0.22, x=0))


def fig_season(se):
    dow_n = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
    mon_n = ["Gen", "Feb", "Mar", "Apr", "Mag", "Giu", "Lug", "Ago", "Set", "Ott", "Nov", "Dic"]
    has_h = "hour" in se
    specs = [("hour", "Rendimento medio per ora (bps)", "mean"), ("dow", "Rendimento medio per giorno (bps)", "mean"),
             ("month", "Rendimento medio per mese (%)", "mean"), ("hour", "Movimento assoluto medio per ora (bps)", "abs"),
             ("dow", "Movimento assoluto medio per giorno (bps)", "abs"), ("month", "% mesi positivi", "up")]
    fig = make_subplots(2, 3, subplot_titles=[s[1] for s in specs], vertical_spacing=0.15)
    for k, (key, _, col) in enumerate(specs):
        if key not in se:
            continue
        df = se[key]
        x = ([f"{h:02d}" for h in df.index] if key == "hour" else [dow_n[i] for i in df.index] if key == "dow"
             else [mon_n[i - 1] for i in df.index])
        y = df[col] * (100 if col == "up" else 1)
        err = dict(type="data", array=2 * df["se"], color=GREY) if col == "mean" else None
        color = ([BLUE if v >= 0 else RED for v in y] if col == "mean"
                 else [BLUE if v >= 50 else RED for v in y] if col == "up" else "#9ca3af")
        fig.add_bar(x=x, y=y, error_y=err, marker_color=color, showlegend=False, row=k // 3 + 1, col=k % 3 + 1)
    if not has_h:
        fig.layout.annotations[0].text = fig.layout.annotations[3].text = "(servono dati H1)"
    return _layout(fig, 620)


def fig_profiles(ctx, vp):
    prof = vp["profiles"]
    fig = make_subplots(1, len(prof), subplot_titles=list(prof), horizontal_spacing=0.035)
    for k, (lab, pf) in enumerate(prof.items()):
        lo_i, hi_i = pf["va"]
        col = np.where((np.arange(len(pf["prof"])) >= lo_i) & (np.arange(len(pf["prof"])) <= hi_i), "#1d4ed8", "#374151")
        col[pf["poc_i"]] = AMBER
        fig.add_bar(y=pf["ctr"], x=pf["prof"], orientation="h", marker_color=list(col), showlegend=False,
                    hovertemplate="prezzo %{y}<br>volume %{x:.0f}<extra></extra>", row=1, col=k + 1)
        fig.add_hline(y=ctx.last, line=dict(color="#f9fafb", dash="dash", width=1), row=1, col=k + 1)
        fig.add_hline(y=pf["vwap"], line=dict(color="#34d399", dash="dot", width=1), row=1, col=k + 1)
    fig.update_layout(bargap=0)
    fig.update_xaxes(showticklabels=False)
    return _layout(fig, 620)


def fig_hour_volume(hv):
    fig = go.Figure()
    for key, lab, col in (("y12", "Media 12 mesi", GREY), ("d20", "Media ultime 4 settimane", BLUE),
                          ("last", "Ultima sessione", AMBER)):
        s = hv[key]
        if len(s):
            fig.add_scatter(x=[f"{h:02d}" for h in s.index], y=s.values, name=lab, mode="lines+markers",
                            line=dict(color=col, width=2 if key == "last" else 1.4))
    return _layout(fig, 360, xaxis_title="Ora (server)", yaxis_title="Volume medio per barra H1")


# ----------------------------------------------------------------------------- HTML
def dcol(v, vmax):
    if v is None or not np.isfinite(v) or v == 0:
        return ""
    a = min(abs(v) / vmax, 1) * 0.55
    return f"rgba(59,130,246,{a:.2f})" if v > 0 else f"rgba(239,68,68,{a:.2f})"


def table(headers, rows):
    th = "".join(f"<th>{h}</th>" for h in headers)
    body = []
    for r in rows:
        tds = []
        for c in r:
            if isinstance(c, tuple):
                tds.append(f'<td style="background:{c[1]}">{c[0]}</td>' if c[1] else f"<td>{c[0]}</td>")
            else:
                tds.append(f"<td>{c}</td>")
        body.append("<tr>" + "".join(tds) + "</tr>")
    return f'<div class="tw"><table><thead><tr>{th}</tr></thead><tbody>{"".join(body)}</tbody></table></div>'


def regime_label(vz, t):
    """VR misura la persistenza dentro la finestra, TSMOM quella fra finestre consecutive."""
    a = 0 if not np.isfinite(vz) else (1 if vz > 2 else -1 if vz < -2 else 0)
    b = 0 if not np.isfinite(t) else (1 if t > SIG_Z else -1 if t < -SIG_Z else 0)
    if a * b < 0:
        return ("Misto: " + ("rumore che rientra, direzione che persiste" if a < 0 else "trend interno, inversione fra finestre"),
                "rgba(245,158,11,.35)")
    if a + b > 0:
        return ("Momentum / trend", dcol(1, 1))
    if a + b < 0:
        return ("Mean reversion", dcol(-1, 1))
    return ("Random walk", "")


def verdict(ctx, ts, rows, tm, cond, hours, overall, mr, vp):
    out = []
    lp = ts["last"]
    above = lp > ts["s200"] if np.isfinite(ts["s200"]) else None
    if above is not None:
        out.append(f"<b>Trend di fondo:</b> prezzo {'sopra' if above else 'sotto'} la SMA200 "
                   f"({(lp / ts['s200'] - 1) * 100:+.1f}%), SMA50 {'>' if ts['s50'] > ts['s200'] else '<'} SMA200. "
                   f"Storicamente sopra la SMA200 il {ts['above200'] * 100:.0f}% del tempo. "
                   f"Rendimento 12m: {fmt(ts['rets'].get('12m', np.nan) * 100, 1, '%')}, 3m: {fmt(ts['rets'].get('3m', np.nan) * 100, 1, '%')}.")
    names = tm["names"]
    diag = {n: tm["T"][k, k] for k, n in enumerate(names)}
    mom = [r["name"] for r in rows if regime_label(r["vz"], diag.get(r["name"], np.nan))[0].startswith("Momentum")]
    rev = [r["name"] for r in rows if regime_label(r["vz"], diag.get(r["name"], np.nan))[0].startswith("Mean")]
    mix = [r["name"] for r in rows if regime_label(r["vz"], diag.get(r["name"], np.nan))[0].startswith("Misto")]
    rnd = [r["name"] for r in rows if r["name"] not in mom + rev + mix]
    out.append(f"<b>Regime per orizzonte:</b> momentum su <b>{', '.join(mom) or 'nessuno'}</b>; mean reversion su "
               f"<b>{', '.join(rev) or 'nessuno'}</b>; misto (VR e momentum in disaccordo) su {', '.join(mix) or 'nessuno'}; "
               f"indistinguibile dal random walk su {', '.join(rnd) or 'nessuno'}.")
    cells = []
    for k, _, _ in FAMILIES:
        for nm, d in cond[k]["data"].items():
            for lb, c in d.items():
                if c["ne"] >= 30:
                    cells.append((c["zP"], c["P"], nm, cond[k]["title"], lb, c))
    best = sorted([c for c in cells if c[0] > SIG_Z], key=lambda c: -c[1])[:4]
    worst = sorted([c for c in cells if c[0] < -SIG_Z], key=lambda c: c[1])[:4]
    if best:
        out.append("<b>Quando continua (momentum):</b> " + "; ".join(
            f"{nm} con {t.lower()} = {lb}: continua nel {P * 100:.0f}% (z {z:.1f}, N_eff {c['ne']:.0f})"
            for z, P, nm, t, lb, c in best) + ".")
    else:
        out.append("<b>Quando continua:</b> nessuna condizione con continuazione statisticamente robusta (z > 2.5).")
    if worst:
        out.append("<b>Quando inverte (mean reversion della mossa):</b> " + "; ".join(
            f"{nm} con {t.lower()} = {lb}: continua solo nel {P * 100:.0f}% (z {z:.1f})"
            for z, P, nm, t, lb, c in worst) + ".")
    mrc = [(c["zP"], c["P"], nm, lb, c) for nm, d in mr["data"].items() for lb, c in d.items() if c["ne"] >= 30]
    mrb = sorted([c for c in mrc if c[0] > SIG_Z], key=lambda c: -c[1])[:4]
    if mrb:
        out.append("<b>Rientro verso la media:</b> " + "; ".join(
            f"{nm} a {lb} dalla media: rientra nel {P * 100:.0f}%, tocca la media nel {c['touch'] * 100:.0f}%"
            for z, P, nm, lb, c in mrb) + ".")
    er = sorted([c for c in cells if c[5]["ne"] >= 30 and np.isfinite(c[5]["ERr"])], key=lambda c: -c[5]["ERr"])[:3]
    if er:
        out.append("<b>Trend più puliti quando:</b> " + "; ".join(
            f"{nm} con {t.lower()} = {lb} (ER forward {c['ERr']:.2f}× la media)" for z, P, nm, t, lb, c in er) + ".")
    if hours["P"]:
        nm = next(iter(hours["P"]))
        P, Z = hours["P"][nm], hours["zP"][nm]
        hc = [f"{h:02d}h ({P[h] * 100:.0f}%)" for h in np.argsort(-np.nan_to_num(P)) if np.isfinite(Z[h]) and Z[h] > SIG_Z][:4]
        hr = [f"{h:02d}h ({P[h] * 100:.0f}%)" for h in np.argsort(np.nan_to_num(P, nan=1)) if np.isfinite(Z[h]) and Z[h] < -SIG_Z][:4]
        out.append(f"<b>Ore (server), orizzonte {nm}:</b> continuazione in {', '.join(hc) or 'nessuna ora significativa'}; "
                   f"inversione in {', '.join(hr) or 'nessuna ora significativa'}.")
    if vp and vp["profiles"]:
        parts = []
        for lab, pf in vp["profiles"].items():
            pos = "sopra la VA" if lp > pf["vah"] else "sotto la VA" if lp < pf["val"] else "dentro la VA"
            parts.append(f"{lab}: POC {ctx.px(pf['poc'])} ({(lp / pf['poc'] - 1) * 100:+.2f}%), {pos}")
        out.append("<b>Dove si è scambiato di più:</b> " + "; ".join(parts) + ".")
        if "daily" in vp:
            dv = vp["daily"]
            out.append(f"<b>Volume:</b> ultima sessione {dv['last'] / dv['ma20']:.2f}× la media 20g e "
                       f"{dv['last'] / dv['ma252']:.2f}× la media annua (percentile {dv['pct'] * 100:.0f}); "
                       f"media 20g / media annua = {dv['ma20'] / dv['ma252']:.2f}.")
    out.append(f"<span class='muted'>Sono stati testati centinaia di condizioni: per il puro caso circa l'1% supera "
               f"|z| > {SIG_Z}. Considera un edge credibile solo se è coerente fra orizzonti vicini e sopravvive "
               f"a spread + commissioni.</span>")
    return "<ul>" + "".join(f"<li>{x}</li>" for x in out) + "</ul>"


CSS = """
:root{--bg:#0b0f17;--card:#111827;--fg:#e5e7eb;--mut:#9ca3af;--line:#1f2937;--acc:#3b82f6}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:1500px;margin:0 auto;padding:16px}h1{font-size:26px;margin:8px 0 4px}h2{font-size:19px;margin:0 0 6px}
section{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin:14px 0}
.muted{color:var(--mut)}.desc{color:var(--mut);margin:0 0 10px;max-width:1100px}
.tw{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:12.5px;font-variant-numeric:tabular-nums}
th,td{padding:5px 8px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap}
th:first-child,td:first-child{text-align:left}th{color:var(--mut);font-weight:600;position:sticky;top:0;background:var(--card)}
ul{margin:0;padding-left:20px}li{margin:6px 0}.kpi{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:10px}
.kpi div{background:#0f172a;border:1px solid var(--line);border-radius:8px;padding:10px}.kpi b{display:block;font-size:18px}
.kpi span{color:var(--mut);font-size:12px}
"""


def build_report(ctx, offline=False):
    rows, hists = horizon_stats(ctx)
    tm = tsmom_matrix(ctx)
    cond, hours, overall = conditional(ctx)
    mr = mean_reversion(ctx)
    cur = current_state(ctx, cond, mr)
    ts = trend_summary(ctx)
    vp = volume_analysis(ctx)
    names = [n for n, _ in ctx.horizons]
    diag = {n: tm["T"][k, k] for k, n in enumerate(tm["names"])}
    first = [True]

    def F(fig):
        if fig is None:
            return ""
        s = fig.to_html(full_html=False, include_plotlyjs=False, config={"displaylogo": False, "responsive": True})
        first[0] = False
        return s

    def sec(title, desc, body):
        return f"<section><h2>{title}</h2><p class='desc'>{desc}</p>{body}</section>"

    last_px = ctx.last
    kp = ([("Ultimo prezzo", ctx.px(last_px)), ("Dati D1 dal", ts["start"].strftime("%Y-%m-%d")),
          ("CAGR", fmt(ts["cagr"] * 100, 1, "%")), ("Volatilità annua", fmt(ts["vol"] * 100, 1, "%")),
          ("Max drawdown", fmt(ts["mdd"] * 100, 1, "%")), ("Drawdown attuale", fmt(ts["cur_dd"] * 100, 1, "%")),
          ("vs SMA50", fmt((last_px / ts["s50"] - 1) * 100, 2, "%")), ("vs SMA200", fmt((last_px / ts["s200"] - 1) * 100, 2, "%")),
          ("Dist. max 52w", fmt((last_px / ts["hi52"] - 1) * 100, 1, "%")), ("Dist. min 52w", fmt((last_px / ts["lo52"] - 1) * 100, 1, "%")),
          ("Vol 20g annualizz.", fmt(ts["rv20"] * 100, 1, "%")), ("Percentile vol 20g", fmt(ts["rv_pct"] * 100, 0))]
          + [(f"Rend. {k}", fmt(v * 100, 2, "%")) for k, v in ts["rets"].items()])
    kpi = "<div class='kpi'>" + "".join(f"<div><span>{a}</span><b>{b}</b></div>" for a, b in kp) + "</div>"

    # tabella movimenti
    tA = table(["Orizzonte", "Dati", "N eff", "Media %", "t", "Mediana %", "Dev.std %", "% rialzo",
                "P5 %", "P25 %", "P75 %", "P95 %", "Skew", "Kurt"],
               [[r["name"], r["tf"], (fmt(r["neff"], 0), "" if r["neff"] >= 30 else "rgba(245,158,11,.35)"),
                 fmt(r["mean"] * 100, 3), (fmt(r["t"], 2), dcol(r["t"], 4)), fmt(r["med"] * 100, 3), fmt(r["std"] * 100, 2),
                 (fmt(r["up"] * 100, 1), dcol(r["up"] - 0.5, 0.1)), *[fmt(x * 100, 2) for x in r["qs"]],
                 fmt(r["skew"], 2), fmt(r["kurt"], 1)] for r in rows])
    tB = table(["Orizzonte", "|mossa| mediana %", "≈ prezzo", "Range mediano %", "≈ prezzo", "Range più frequente %",
                "MFE P50 %", "MFE P75 %", "MFE P90 %", "MAE P50 %", "MAE P75 %", "MAE P90 %", "MFE P50 prezzo", "MAE P50 prezzo"],
               [[r["name"], fmt(r["absmed"] * 100, 2), ctx.px(r["absmed"] * last_px), fmt(r["rng_med"] * 100, 2),
                 ctx.px(r["rng_med"] * last_px), fmt(r["rng_mode"] * 100, 2), *[fmt(x * 100, 2) for x in r["mfe"]],
                 *[fmt(x * 100, 2) for x in r["mae"]], ctx.px(r["mfe"][0] * last_px), ctx.px(r["mae"][0] * last_px)]
                for r in rows])
    tC = table(["Orizzonte", "Barre q", "VR(q)", "z VR", "TSMOM t", "P(continua)", "Payoff medio %", "Regime"],
               [[r["name"], f"{r['vq']} {r['tf']}", fmt(r["vr"], 3), (fmt(r["vz"], 2), dcol(r["vz"], 4)),
                 (fmt(diag.get(r["name"]), 2), dcol(diag.get(r["name"], np.nan), 4)),
                 (fmt(overall.get(r["name"], {}).get("P", np.nan) * 100, 1),
                  dcol(overall.get(r["name"], {}).get("P", np.nan) - 0.5, 0.08)),
                 fmt(overall.get(r["name"], {}).get("mean", np.nan) * 100, 3),
                 regime_label(r["vz"], diag.get(r["name"], np.nan))] for r in rows])

    def pc(c, key="P"):
        return ("–", "") if not c else (f"{c[key] * 100:.0f}%" + ("*" if abs(c["zP"]) > SIG_Z else ""), dcol(c[key] - 0.5, 0.12))

    tCur = table(["Orizzonte", "Mossa ultima finestra", "|z|", "P(cont) per |z|", "ER → P(cont)", "Vol → P(cont)",
                  "Volume → P(cont)", "Dist. media (σ)", "P(rientro)", "P(tocca media)", "Media mobile"],
                 [[r["name"], (fmt(r["past"] * 100, 2, "%"), dcol(r["past"], 0.05)), fmt(r["z"], 2),
                   pc(r["fam"].get("z", (None, None))[1]),
                   *[(f"{r['fam'][k][0]}: " + pc(r["fam"][k][1])[0], pc(r["fam"][k][1])[1]) if k in r["fam"] else "–"
                     for k in ("er", "vol", "rv")],
                   fmt(r.get("dev"), 2), pc(r.get("mr", (None, None))[1]),
                   (fmt(r["mr"][1]["touch"] * 100, 0, "%") if r.get("mr") and r["mr"][1] else "–"),
                   ctx.px(r.get("ma", np.nan))] for r in cur])

    vol_html = ""
    if vp:
        tV = table(["Finestra", "POC", "VAL", "VAH", "VWAP", "Prezzo vs POC", "Posizione"],
                   [[lab, ctx.px(pf["poc"]), ctx.px(pf["val"]), ctx.px(pf["vah"]), ctx.px(pf["vwap"]),
                     (fmt((last_px / pf["poc"] - 1) * 100, 2, "%"), dcol(last_px / pf["poc"] - 1, 0.05)),
                     "sopra VA" if last_px > pf["vah"] else "sotto VA" if last_px < pf["val"] else "dentro VA"]
                    for lab, pf in vp["profiles"].items()])
        vk = []
        if "daily" in vp:
            dv = vp["daily"]
            vk += [("Volume ultima sessione", f"{dv['last']:,.0f}"), ("vs media 20g", f"{dv['last'] / dv['ma20']:.2f}×"),
                   ("vs media 252g", f"{dv['last'] / dv['ma252']:.2f}×"), ("Percentile 1 anno", f"{dv['pct'] * 100:.0f}"),
                   ("Media 5g / 252g", f"{dv['last5'] / dv['ma252']:.2f}×"), ("Media 20g / 252g", f"{dv['ma20'] / dv['ma252']:.2f}×")]
        if "hourly" in vp:
            vk.append(("RVOL ultima H1 (stessa ora)", fmt(vp["hourly"]["rvol_last"], 2, "×")))
        vk_html = "<div class='kpi'>" + "".join(f"<div><span>{a}</span><b>{b}</b></div>" for a, b in vk) + "</div>"
        vol_html = sec("Volume: dove si concentra e come si confronta con lo storico",
                       f"Volume Profile da barre {ctx.base.name} (volume di ogni barra distribuito sul suo range). "
                       "<b style='color:#f59e0b'>Arancio</b> = POC (prezzo con più volume), blu = Value Area 70%, "
                       "linea tratteggiata = prezzo attuale, linea verde punteggiata = VWAP della finestra. "
                       f"Volume: {ctx.meta.get('vol_kind') or 'n/d'}"
                       + (" — sui CFD è tick volume: misura l'attività, non il controvalore." if ctx.meta.get("vol_kind") == "tick" else "."),
                       tV + F(fig_profiles(ctx, vp)) + "<h2 style='margin-top:16px'>Volume corrente vs storico</h2>" + vk_html
                       + (F(fig_hour_volume(vp["hourly"])) if "hourly" in vp else ""))

    body = [
        f"<h1>{html.escape(ctx.name)} — analisi quantitativa</h1><p class='muted'>Fonte: {ctx.meta['source']} · "
        f"H1: {len(ctx.h1.df) if ctx.h1 else 0} barre"
        + (f" ({ctx.h1.idx[0]:%Y-%m-%d} → {ctx.h1.idx[-1]:%Y-%m-%d %H:%M})" if ctx.h1 else "")
        + f" · D1: {len(ctx.d1.df)} barre ({ctx.d1.idx[0]:%Y-%m-%d} → {ctx.d1.idx[-1]:%Y-%m-%d}) · orari = ora del server/fonte</p>",
        sec("Verdetto", "Sintesi automatica. * = |z| > 2.5 sulla N effettiva (finestre sovrapposte già corrette).",
            verdict(ctx, ts, rows, tm, cond, hours, overall, mr, vp)),
        sec("Stato attuale", "Dove si trova oggi lo strumento rispetto alla sua storia.", kpi),
        sec("Cruscotto: cosa dice la storia sulla situazione di adesso",
            "Per ogni orizzonte: la mossa dell'ultima finestra, in quale fascia storica cade e con che frequenza, "
            "in passato, da quella fascia il movimento è continuato (blu) o si è invertito (rosso); a destra la "
            "distanza dalla media mobile (2× orizzonte) e la probabilità storica di rientro.", tCur),
        sec("Come cambia il prezzo nel tempo", "Prezzo, drawdown, regimi di trend/mean reversion nel tempo (Variance Ratio "
            "mobile a 1 anno) e volume.", F(fig_history(ctx))),
        sec("Movimenti per orizzonte: rendimenti",
            "Rendimento da chiusura a chiusura dopo l'orizzonte (le uscite che cadono nel weekend slittano alla prima barra "
            "disponibile). t = t-stat Newey-West della media. N eff = finestre indipendenti; in arancio se < 30 "
            "(campione insufficiente per conclusioni).", tA + F(fig_hists(hists))),
        sec("Movimenti per orizzonte: escursioni (per SL/TP)",
            "MFE = massimo movimento favorevole a un long entro l'orizzonte (high massimo), MAE = massimo movimento avverso "
            "(low minimo). Per uno short scambia le colonne. P75 = soglia superata nel 25% dei casi. Prezzi = percentuali "
            "applicate al prezzo attuale. 'Range più frequente' = moda della distribuzione high−low.", tB),
        sec("Regime: momentum o mean reversion per orizzonte",
            "Variance Ratio: VR>1 significa che i movimenti tendono a proseguire, VR<1 che tendono a rientrare (z robusto, "
            "|z|>2 significativo). TSMOM t = t-stat della strategia 'segui il segno dell'ultima finestra' sullo stesso "
            "orizzonte.", tC + F(fig_vr(rows))),
        sec("Matrice momentum: mossa passata → mossa futura",
            "Colore = t-stat del payoff sign(mossa passata) × rendimento futuro. Blu = la direzione passata prosegue "
            "(momentum), rosso = si inverte (mean reversion). Numero = % di volte in cui la direzione è proseguita. "
            "Celle vuote = meno di 10 finestre indipendenti.", F(fig_tsmom(tm))),
        sec("Quando prosegue e quando si inverte",
            "P(continuazione) dopo una mossa sull'orizzonte, per la stessa durata futura, divisa per condizione al momento "
            "dell'ingresso. |z| = mossa in σ (volatilità recente); ER = efficienza di Kaufman (1 = linea retta, 0 = laterale); "
            "volume relativo = volume della finestra vs atteso per quelle ore. Blu > 50%, rosso < 50%, * significativo.",
            F(fig_conditional(cond, names, "P"))),
        sec("Quando il trend è più forte",
            "Efficienza (ER) del movimento successivo rispetto alla media dell'orizzonte: 1.20 = trend del 20% più "
            "direzionale del normale. Indica in quali condizioni i movimenti successivi sono puliti e in quali sono choppy.",
            F(fig_conditional(cond, names, "ER"))),
        sec("Quando: ora del giorno (server)",
            "Per gli orizzonti intraday: continuazione della mossa appena conclusa e forza del trend successivo, per ora di "
            "ingresso. Qui si vedono le sessioni con breakout/momentum e quelle da range/mean reversion.",
            F(fig_hours(hours)) if hours["P"] else "<p class='muted'>Servono dati H1.</p>"),
        sec("Mean reversion verso la media mobile",
            "Distanza del prezzo dalla media mobile (finestra = 2× orizzonte) in σ dell'orizzonte. Primo numero = "
            "P(il prezzo si muove verso la media entro l'orizzonte), secondo = P(tocca la media entro l'orizzonte). "
            "Blu = tende a rientrare, rosso = tende ad allontanarsi ancora (trend).", F(fig_mr(mr, names))),
        sec("Sequenze (streak)", "Probabilità che la barra successiva prosegua nello stesso verso dopo k barre consecutive. "
            "Linee punteggiate = probabilità base. Sopra la base = persistenza, sotto = esaurimento.", F(fig_streaks(streaks(ctx)))),
        sec("Stagionalità", "Barre di errore = ±2 errori standard: se attraversano lo zero, l'effetto non è distinguibile "
            "dal rumore.", F(fig_season(seasonality(ctx)))),
        vol_html,
        sec("Metodologia e limiti",
            "", "<ul><li>Orizzonti ≤ 24h calcolati su barre H1, oltre su D1. Tempo di calendario: '24h' = 24 ore reali, "
            "weekend inclusi se attraversati.</li><li>Le finestre sovrapposte gonfiano il campione: tutte le "
            "significatività usano N_eff = durata del campione / orizzonte. Con meno di 30 N_eff (tipico per 6m–12m) "
            "i numeri sono descrittivi, non inferenziali.</li><li>σ = volatilità EWMA causale (nessun dato futuro); "
            "fasce di ER/volatilità/volume sono quintili/terzili dell'intero campione (descrittivo, non un segnale "
            "eseguibile così com'è).</li><li>Escluse le finestre con meno della metà delle barre tipiche (cadono per lo più "
            "nel weekend/chiusura): altrimenti falsano ER e continuazione del venerdì sera.</li><li>Nessun costo di transazione incluso: un edge del 52% su 4h raramente "
            "sopravvive allo spread.</li><li>Test multipli: con centinaia di celle, qualche 'significatività' è "
            "rumore. Cerca coerenza fra orizzonti vicini e stabilità nel tempo (VR mobile).</li></ul>"),
    ]
    js = (f"<script>{get_plotlyjs()}</script>" if offline
          else f'<script src="https://cdn.plot.ly/plotly-{get_plotlyjs_version()}.min.js" charset="utf-8"></script>')
    return (f"<!doctype html><html lang='it'><head><meta charset='utf-8'><meta name='viewport' "
            f"content='width=device-width,initial-scale=1'><title>{html.escape(ctx.name)} — Market Profiler</title>"
            f"<style>{CSS}</style>{js}</head><body><main>{''.join(body)}</main></body></html>")


# ----------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description="Analisi quantitativa di uno strumento -> report HTML")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--mt5", nargs="+", metavar="SYMBOL", help="simboli dal terminale MT5 aperto")
    src.add_argument("--csv-h1", help="CSV H1 (export MT5 o generico OHLCV)")
    src.add_argument("--csv-d1-only", help="solo CSV D1 (niente orizzonti intraday)")
    src.add_argument("--yf", nargs="+", metavar="TICKER", help="ticker Yahoo Finance (test)")
    ap.add_argument("--csv-d1", help="CSV D1 opzionale da affiancare a --csv-h1 (storico più lungo)")
    ap.add_argument("--name", help="nome dello strumento per i CSV")
    ap.add_argument("--bars-h1", type=int, default=100_000)
    ap.add_argument("--bars-d1", type=int, default=20_000)
    ap.add_argument("--out", default=".", help="cartella di output")
    ap.add_argument("--offline", action="store_true", help="incorpora plotly.js nel file (funziona senza internet)")
    a = ap.parse_args()

    jobs = []
    if a.mt5:
        jobs = [(s, lambda s=s: load_mt5(s, a.bars_h1, a.bars_d1)) for s in a.mt5]
    elif a.yf:
        jobs = [(t, lambda t=t: load_yf(t)) for t in a.yf]
    else:
        def from_csv():
            h1 = load_csv(a.csv_h1) if a.csv_h1 else (None, None)
            d1 = load_csv(a.csv_d1 or a.csv_d1_only) if (a.csv_d1 or a.csv_d1_only) else (daily_from_intraday(h1[0]), None)
            return h1[0], d1[0], dict(source="CSV", digits=None, vol_kind=h1[1] or d1[1])
        jobs = [(a.name or Path(a.csv_h1 or a.csv_d1_only).stem, from_csv)]

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for name, loader in jobs:
        try:
            h1, d1, meta = loader()
            ctx = Ctx(name, h1, d1, meta)
            path = out / f"report_{''.join(ch if ch.isalnum() else '_' for ch in name)}.html"
            path.write_text(build_report(ctx, a.offline), encoding="utf-8")
            print(f"[ok] {name}: {path}")
        except Exception as e:  # un simbolo fallito non blocca gli altri
            print(f"[errore] {name}: {e}", file=sys.stderr)
            if len(jobs) == 1:
                raise


if __name__ == "__main__":
    main()
