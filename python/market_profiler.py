#!/usr/bin/env python3
"""
market_profiler.py - Analisi descrittiva di uno strumento, timeframe per timeframe -> report HTML a schede.

Schede: Panoramica | Minuto | Ora | 4 ore | 6 ore | 8 ore | 12 ore | Giorno | Settimana | 2 settimane |
        Mese | Trimestre | Semestre | Anno | Volume

Ogni periodo (la candela del timeframe) viene scomposto in tre tratti:
    apertura -> primo estremo             movimento iniziale
    primo estremo -> secondo estremo      SPOSTAMENTO PIU' AMPIO (= massimo - minimo, con la sua direzione)
    secondo estremo -> chiusura           SPOSTAMENTO DI MEAN REVERSION (quanto viene restituito)
Per ciascun tratto misura QUANTO (in % e in prezzo) e QUANDO (ora / giorno / settimana / mese dentro il periodo).
Poi: come cambia per ora, giorno, mese e anno; cosa succede nel periodo successivo (continuazione, rottura del
massimo/minimo precedente, false rotture, sequenze); volume profile e volume attuale rispetto allo storico.

Uso
  python market_profiler.py --mt5 XAUUSD EURUSD US500        # terminale MT5 FP Markets aperto (Windows)
  python market_profiler.py --csv-m1 X_M1.csv --csv-h1 X_H1.csv --csv-d1 X_D1.csv --name XAUUSD
  python market_profiler.py --yf GC=F                          # Yahoo Finance, solo per prova

Note: orari = ora del server MT5 (FP Markets EET/EEST: la giornata chiude alle 17:00 di New York).
Sui CFD il volume e' tick volume: misura l'attivita', non il controvalore.
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
DOW = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]
MON = ["Gen", "Feb", "Mar", "Apr", "Mag", "Giu", "Lug", "Ago", "Set", "Ott", "Nov", "Dic"]
# key, etichetta, dati usati per misurare il "quando" dentro il periodo (in ordine di preferenza)
TFS = [dict(key="min", label="Minuto", src=["m1"]),
       dict(key="h1", label="Ora", src=["m1", "h1"]),
       dict(key="h4", label="4 ore", src=["h1", "m1"], k=4),
       dict(key="h6", label="6 ore", src=["h1", "m1"], k=6),
       dict(key="h8", label="8 ore", src=["h1", "m1"], k=8),
       dict(key="h12", label="12 ore", src=["h1", "m1"], k=12),
       dict(key="d", label="Giorno", src=["h1", "m1"]),
       dict(key="w", label="Settimana", src=["h1", "d1"]),
       dict(key="w2", label="2 settimane", src=["d1"]),
       dict(key="mo", label="Mese", src=["d1"]),
       dict(key="q", label="Trimestre", src=["d1"]),
       dict(key="s", label="Semestre", src=["d1"]),
       dict(key="y", label="Anno", src=["d1"])]
TIMING_UNIT = {"h1": "minuto dell'ora (fasce di 5')", "h4": "ora dentro il blocco", "h6": "ora dentro il blocco",
               "h8": "ora dentro il blocco", "h12": "ora dentro il blocco", "d": "ora del giorno",
               "w": "giorno della settimana", "w2": "giorno di borsa del periodo", "mo": "giorno di borsa del mese",
               "q": "settimana del trimestre", "s": "mese del semestre", "y": "mese dell'anno"}
CLASSES = ["Trend", "Parziale", "Mean reversion"]
TEMPLATE = "plotly_dark"
BLUE, RED, GREY, AMBER, GREEN = "#3b82f6", "#ef4444", "#6b7280", "#f59e0b", "#34d399"
CLS_COL = {"Trend": BLUE, "Parziale": GREY, "Mean reversion": RED}


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


def load_mt5(symbol, bars):
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
                n //= 2  # 'Barre massime nel grafico' del terminale puo' limitare la richiesta
            return None

        data, kind = {}, None
        for key, tf in (("m1", mt5.TIMEFRAME_M1), ("h1", mt5.TIMEFRAME_H1), ("d1", mt5.TIMEFRAME_D1)):
            raw = get(tf, bars[key]) if bars[key] > 0 else None
            if raw is not None:
                data[key], k = _finish(raw)
                kind = kind or k
        if "d1" not in data and "h1" not in data:
            raise RuntimeError(f"Nessun dato per {symbol}: {mt5.last_error()}")
        info = mt5.symbol_info(symbol)
        return data, dict(source="MetaTrader 5", digits=info.digits, vol_kind=kind)
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
    data, kind = {}, None
    for key, kw in (("m1", dict(period="7d", interval="1m")), ("h1", dict(period="730d", interval="1h")),
                    ("d1", dict(period="max", interval="1d"))):
        df = yf.download(ticker, auto_adjust=False, progress=False, multi_level_index=False, **kw)
        if df.empty:
            continue
        idx = df.index
        df.index = idx.tz_convert("UTC").tz_localize(None) if idx.tz is not None else idx
        data[key], k = _finish(df)
        kind = kind or k
    if not data:
        raise RuntimeError(f"Yahoo: nessun dato per {ticker}")
    return data, dict(source="Yahoo Finance (UTC)", digits=None, vol_kind=kind)


def resample(df, rule):
    agg = {"open": "first", "high": "max", "low": "min", "close": "last"}
    if "volume" in df:
        agg["volume"] = "sum"
    return df.resample(rule).agg(agg).dropna(subset=["close"])


def ns(idx):
    return pd.DatetimeIndex(idx).values.astype("datetime64[ns]").astype(np.int64)


# ----------------------------------------------------------------------------- periodi
def block_key(spec, idx):
    key, k = spec["key"], spec.get("k")
    if key == "min":
        return ns(idx.floor("min"))
    if key == "h1":
        return ns(idx.floor("h"))
    if k:
        return ns(idx.normalize()) + (idx.hour.to_numpy().astype(np.int64) // k * k) * HOUR
    if key == "d":
        return ns(idx.normalize())
    ws = ns(idx.normalize() - pd.to_timedelta(idx.dayofweek, unit="D"))
    if key == "w":
        return ws
    if key == "w2":
        return (ws - pd.Timestamp("1970-01-05").value) // (14 * DAY)
    m = idx.year.to_numpy().astype(np.int64) * 12 + idx.month.to_numpy() - 1
    return {"mo": m, "q": m // 3, "s": m // 6, "y": m // 12}[key]


def _cat(v, order):
    order = list(order)
    return pd.Categorical(np.array(order, dtype=object)[np.asarray(v, int)], categories=order, ordered=True)


def timing(spec, t_ext, t0, off):
    """In quale parte del periodo cade l'estremo."""
    key, k = spec["key"], spec.get("k")
    t = pd.DatetimeIndex(t_ext)
    if key == "h1":
        return _cat(t.minute // 5, [f"{m:02d}-{m + 4:02d}'" for m in range(0, 60, 5)])
    if k:
        return _cat(t.hour % k, [f"+{i}h" for i in range(k)])
    if key == "d":
        return _cat(t.hour, [f"{h:02d}h" for h in range(24)])
    if key == "w":
        return _cat(t.dayofweek, DOW)
    if key in ("w2", "mo"):
        off = np.asarray(off, int)
        return _cat(off, [f"G{i + 1}" for i in range(off.max() + 1)])
    if key == "q":
        w = np.minimum((t.normalize() - pd.DatetimeIndex(t0).normalize()).days.to_numpy() // 7, 13)
        return _cat(w, [f"S{i + 1}" for i in range(14)])
    if key == "s":
        return _cat((t.month - 1) % 6, [f"M{i + 1}" for i in range(6)])
    return _cat(t.month - 1, MON)


def category(spec, t0):
    """Sotto-categoria del periodo per vedere come cambia il comportamento (ora, giorno, mese...)."""
    key, k = spec["key"], spec.get("k")
    t = pd.DatetimeIndex(t0)
    if key in ("min", "h1"):
        return _cat(t.hour, [f"{h:02d}h" for h in range(24)])
    if k:
        return _cat(t.hour // k, [f"{i * k:02d}-{(i + 1) * k:02d}h" for i in range(24 // k)])
    if key == "d":
        return _cat(t.dayofweek, DOW)
    if key in ("w", "w2", "mo"):
        return _cat(t.month - 1, MON)
    if key == "q":
        return _cat((t.month - 1) // 3, ["Q1", "Q2", "Q3", "Q4"])
    if key == "s":
        return _cat((t.month - 1) // 6, ["1° semestre", "2° semestre"])
    return None


def period_label(key, t):
    t = pd.DatetimeIndex(t)
    if key in ("min", "h1", "h4", "h6", "h8", "h12"):
        return list(t.strftime("%Y-%m-%d %H:%M"))
    if key == "d":
        return [f"{x:%Y-%m-%d} {DOW[x.dayofweek]}" for x in t]
    if key in ("w", "w2"):
        return list(t.strftime("sett. %Y-%m-%d"))
    if key == "mo":
        return [f"{MON[x.month - 1]} {x.year}" for x in t]
    if key == "q":
        return [f"Q{(x.month - 1) // 3 + 1} {x.year}" for x in t]
    if key == "s":
        return [f"{(x.month - 1) // 6 + 1}° sem {x.year}" for x in t]
    return list(t.strftime("%Y"))


class Blocks:
    """Scompone la serie nei periodi del timeframe e misura ogni periodo."""

    def __init__(self, spec, df, src):
        self.spec, self.src = spec, src
        idx = pd.DatetimeIndex(df.index)
        kv = block_key(spec, idx)
        n = len(df)
        starts = np.r_[0, np.flatnonzero(np.diff(kv) != 0) + 1]
        cnt = np.diff(np.r_[starts, n])
        o, h, l, c = (df[x].to_numpy(float) for x in ("open", "high", "low", "close"))
        H, L = np.maximum.reduceat(h, starts), np.minimum.reduceat(l, starts)
        ar = np.arange(n)
        iH = np.minimum.reduceat(np.where(h == np.repeat(H, cnt), ar, n), starts)
        iL = np.minimum.reduceat(np.where(l == np.repeat(L, cnt), ar, n), starts)
        self.intra = np.median(cnt) > 1  # False = il periodo e' una sola barra: niente "quando" interno
        # ordine degli estremi; se cadono nella stessa barra decide la direzione di quella barra
        lfirst = np.where(iL < iH, True, np.where(iL > iH, False, c[iH] >= o[iH]))
        b = pd.DataFrame(dict(t0=idx[starts], O=o[starts], H=H, L=L, C=c[starts + cnt - 1], cnt=cnt,
                              tH=idx[iH], tL=idx[iL], offH=iH - starts, offL=iL - starts, lfirst=lfirst))
        if "volume" in df:
            b["V"] = np.add.reduceat(df["volume"].fillna(0).to_numpy(float), starts)
        self.med_cnt = float(np.median(cnt))
        self.cur = b.iloc[-1]  # periodo in corso
        keep = cnt >= 0.5 * self.med_cnt  # scarta periodi monchi (festivi, inizio dati)
        keep[0] &= cnt[0] >= 0.9 * self.med_cnt
        keep[-1] = False
        b = b[keep].reset_index(drop=True)
        R = (b.H - b.L).to_numpy()
        first = np.where(b.lfirst, b.L, b.H)
        second = np.where(b.lfirst, b.H, b.L)
        b["rng"] = R / b.O
        b["ret"] = b.C / b.O - 1
        b["mfe"], b["mae"] = b.H / b.O - 1, 1 - b.L / b.O
        b["init"] = np.abs(first - b.O) / b.O
        b["retr"] = np.abs(b.C - second) / b.O
        b["rf"] = np.where(R > 0, np.abs(b.C - second) / np.where(R > 0, R, 1), 0.0)
        b["cls"] = pd.Categorical(np.select([b.rf <= 0.25, b.rf >= 0.75], ["Trend", "Mean reversion"], "Parziale"),
                                  categories=CLASSES)
        b["dir"] = np.where(b.lfirst, "rialzista", "ribassista")
        b["year"] = pd.DatetimeIndex(b.t0).year
        b["pH"], b["pL"] = (b.offH + 1) / b.cnt, (b.offL + 1) / b.cnt  # frazione del periodo trascorsa all'estremo
        cat = category(spec, b.t0)
        b["cat"] = cat if cat is not None else "—"
        if self.intra:
            b["bH"] = timing(spec, b.tH, b.t0, b.offH)
            b["bL"] = timing(spec, b.tL, b.t0, b.offL)
        if "V" in b:
            if cat is not None:
                base = b.V.groupby(b.cat, observed=True).transform(lambda s: s.shift(1).rolling(20, min_periods=5).mean())
            else:
                base = b.V.shift(1).rolling(20, min_periods=5).mean()
            b["rv"] = b.V / base.where(base > 0)
        self.b = b


def pick_source(spec, data):
    for s in spec["src"]:
        if s in data and data[s] is not None and len(data[s]) > 50:
            return s
    return None


# ----------------------------------------------------------------------------- statistiche descrittive
def next_period(b):
    """Cosa succede nel periodo successivo, per condizione del periodo appena chiuso."""
    cur, nx = b.iloc[:-1].reset_index(drop=True), b.iloc[1:].reset_index(drop=True)
    s0, s1 = np.sign(cur.ret.to_numpy()), np.sign(nx.ret.to_numpy())
    same = (s0 == s1) & (s0 != 0)
    bh, bl = (nx.H > cur.H).to_numpy(), (nx.L < cur.L).to_numpy()
    fb = (bh & (nx.C <= cur.H).to_numpy()) | (bl & (nx.C >= cur.L).to_numpy())
    mid = ((cur.H + cur.L) / 2).to_numpy()
    tmid = (nx.L.to_numpy() <= mid) & (nx.H.to_numpy() >= mid)
    rr = (nx.rng / b.rng.median()).to_numpy()
    nret = nx.ret.to_numpy()
    rows = []

    def add(group, label, m):
        m = np.asarray(m, bool)
        n = int(m.sum())
        if n < 5:
            return
        br = (bh | bl)[m]
        rows.append(dict(group=group, label=label, N=n, same=same[m].mean(), up=(nret[m] > 0).mean(),
                         ret=nret[m].mean(), rr=rr[m].mean(), bh=bh[m].mean(), bl=bl[m].mean(),
                         inside=(~bh & ~bl)[m].mean(), fb=fb[m].sum() / br.sum() if br.sum() else np.nan,
                         mid=tmid[m].mean()))

    add("", "Tutti i periodi", np.ones(len(cur), bool))
    up = cur.ret.to_numpy() > 0
    for cl in CLASSES:
        m = (cur.cls == cl).to_numpy()
        add("Tipo del periodo appena chiuso", f"{cl} rialzista", m & up)
        add("Tipo del periodo appena chiuso", f"{cl} ribassista", m & ~up)
    for name, x, labs in (("Rendimento del periodo appena chiuso", cur.ret,
                           ["Q1 forte ribasso", "Q2", "Q3", "Q4", "Q5 forte rialzo"]),
                          ("Ampiezza del periodo appena chiuso", cur.rng, ["Q1 stretto", "Q2", "Q3", "Q4", "Q5 ampio"]),
                          ("Volume del periodo appena chiuso (vs ultimi 20)", cur.get("rv"),
                           ["Q1 basso", "Q2", "Q3", "Q4", "Q5 alto"])):
        if x is None or x.notna().sum() < 25:
            continue
        q = pd.qcut(x.rank(method="first"), 5, labels=False).to_numpy()
        for i, lb in enumerate(labs):
            add(name, lb, q == i)
    s = pd.Series(s0)
    run = s.groupby((s != s.shift()).cumsum()).cumcount().to_numpy() + 1
    for k in range(1, 7):
        add("Sequenza: periodi consecutivi nella stessa direzione", f"{k}{'+' if k == 6 else ''} di fila",
            ((run >= k) if k == 6 else (run == k)) & (s0 != 0))
    return rows


def fmt(x, d=2, suf=""):
    try:
        if x is None or not np.isfinite(x):
            return "–"
    except TypeError:
        return str(x)
    return f"{x:.{d}f}{suf}"


def pcol(p, center=0.5, span=0.15):
    """Blu sopra il centro, rosso sotto."""
    if p is None or not np.isfinite(p):
        return ""
    v = p - center
    a = min(abs(v) / span, 1) * 0.55
    return "" if a < 0.04 else (f"rgba(59,130,246,{a:.2f})" if v > 0 else f"rgba(239,68,68,{a:.2f})")


def pct_rows(b, px, last):
    """Percentili delle misure di ogni periodo."""
    up = b.lfirst.to_numpy()
    spec = [("Spostamento più ampio (massimo − minimo)", b.rng, True),
            ("  … dal minimo al massimo (rialzista)", b.rng[up], True),
            ("  … dal massimo al minimo (ribassista)", b.rng[~up], True),
            ("Escursione sopra l'apertura", b.mfe, True),
            ("Escursione sotto l'apertura", b.mae, True),
            ("Movimento iniziale (apertura → primo estremo)", b.init, True),
            ("Mean reversion (secondo estremo → chiusura)", b.retr, True),
            ("Mean reversion in % dello spostamento", b.rf, False),
            ("Rendimento apertura → chiusura", b.ret, True),
            ("|Rendimento| apertura → chiusura", b.ret.abs(), True)]
    rows = []
    for name, x, has_px in spec:
        x = x.dropna().to_numpy()
        if len(x) == 0:
            continue
        q = np.percentile(x, [10, 25, 50, 75, 90, 95])
        rows.append([name, len(x), *[fmt(v * 100, 3) for v in (x.mean(), *q, x.max())],
                     px(q[2] * last) if has_px else "–", px(q[4] * last) if has_px else "–"])
    return rows


def table(headers, rows):
    th = "".join(f"<th>{h}</th>" for h in headers)
    body = []
    for r in rows:
        if isinstance(r, str):  # riga di intestazione di gruppo
            body.append(f'<tr class="grp"><td colspan="{len(headers)}">{r}</td></tr>')
            continue
        tds = []
        for c in r:
            if isinstance(c, tuple):
                tds.append(f'<td style="background:{c[1]}">{c[0]}</td>' if c[1] else f"<td>{c[0]}</td>")
            else:
                tds.append(f"<td>{c}</td>")
        body.append("<tr>" + "".join(tds) + "</tr>")
    return f'<div class="tw"><table><thead><tr>{th}</tr></thead><tbody>{"".join(body)}</tbody></table></div>'


def kpis(items):
    return "<div class='kpi'>" + "".join(
        f"<div><span>{a}</span><b>{b}</b>{f'<small>{c}</small>' if c else ''}</div>" for a, b, c in items) + "</div>"


def most(cat_series):
    vc = cat_series.value_counts(normalize=True)
    return f"{vc.index[0]} ({vc.iloc[0] * 100:.0f}%)" if len(vc) else "–"


# ----------------------------------------------------------------------------- grafici
def _layout(fig, h, **kw):
    lay = dict(template=TEMPLATE, height=h, margin=dict(l=50, r=20, t=60, b=40), paper_bgcolor="rgba(0,0,0,0)",
               plot_bgcolor="rgba(0,0,0,0)", legend=dict(orientation="h", y=-0.18, x=0))
    lay.update(kw)
    fig.update_layout(**lay)
    return fig


def _hist(x, lo, hi, bins=60):
    x = x[np.isfinite(x)]
    if hi <= lo:
        hi = lo + 1e-9
    cnt, ed = np.histogram(np.clip(x, lo, hi), bins=bins, range=(lo, hi))
    return (ed[:-1] + ed[1:]) / 2, cnt / max(cnt.sum(), 1) * 100


def fig_dist(b):
    fig = make_subplots(1, 3, subplot_titles=["Spostamento più ampio (massimo − minimo) %",
                                              "Rendimento apertura → chiusura %",
                                              "Mean reversion: % dello spostamento restituita"])
    r = b.rng.to_numpy() * 100
    x, y = _hist(r, 0, np.percentile(r, 99.5))
    fig.add_bar(x=x, y=y, marker_color=BLUE, row=1, col=1, hovertemplate="%{x:.3f}%: %{y:.1f}% dei periodi<extra></extra>")
    t = b.ret.to_numpy() * 100
    x, y = _hist(t, *np.percentile(t, [0.5, 99.5]))
    fig.add_bar(x=x, y=y, marker_color=[BLUE if v >= 0 else RED for v in x], row=1, col=2,
                hovertemplate="%{x:.3f}%: %{y:.1f}% dei periodi<extra></extra>")
    x, y = _hist(b.rf.to_numpy() * 100, 0, 100, 20)
    fig.add_bar(x=x, y=y, marker_color=[BLUE if v <= 25 else RED if v >= 75 else GREY for v in x], row=1, col=3,
                hovertemplate="%{x:.0f}%: %{y:.1f}% dei periodi<extra></extra>")
    fig.update_yaxes(title="% dei periodi", col=1)
    return _layout(fig, 340, showlegend=False, bargap=0.02)


def fig_timing(b, unit):
    h = b.bH.value_counts(normalize=True, sort=False) * 100
    l = b.bL.value_counts(normalize=True, sort=False) * 100
    up, dn = b[b.lfirst], b[~b.lfirst]
    rev_up = up.bH.value_counts(normalize=True, sort=False) * 100  # fine swing rialzista = inizio del rientro
    rev_dn = dn.bL.value_counts(normalize=True, sort=False) * 100
    fig = make_subplots(1, 2, subplot_titles=[f"Quando si forma il massimo e il minimo ({unit})",
                                              f"Dove finisce lo spostamento più ampio e parte il rientro ({unit})"])
    x = [str(c) for c in h.index]
    fig.add_bar(x=x, y=h.values, name="Massimo del periodo", marker_color=BLUE, row=1, col=1)
    fig.add_bar(x=x, y=l.values, name="Minimo del periodo", marker_color=AMBER, row=1, col=1)
    fig.add_bar(x=x, y=rev_up.reindex(h.index).values, name="Swing rialzista: rientro dal massimo",
                marker_color="#93c5fd", row=1, col=2)
    fig.add_bar(x=x, y=rev_dn.reindex(h.index).values, name="Swing ribassista: rientro dal minimo",
                marker_color="#fcd34d", row=1, col=2)
    fig.update_yaxes(title="% dei periodi", col=1)
    return _layout(fig, 400, barmode="group", bargap=0.15)


def fig_category(b, title):
    g = b.groupby("cat", observed=True)
    rng = g.rng.mean() * 100
    up = g.ret.apply(lambda x: (x > 0).mean() * 100)
    cls = pd.crosstab(b.cat, b.cls, normalize="index").reindex(columns=CLASSES, fill_value=0) * 100
    x = [str(c) for c in rng.index]
    fig = make_subplots(1, 2, specs=[[{"secondary_y": True}, {}]],
                        subplot_titles=[f"Spostamento medio e % rialzisti per {title}", f"Tipo di periodo per {title}"])
    fig.add_bar(x=x, y=rng.values, name="Spostamento medio %", marker_color=GREY, row=1, col=1)
    fig.add_scatter(x=x, y=up.values, name="% rialzisti", mode="lines+markers", line=dict(color=GREEN),
                    row=1, col=1, secondary_y=True)
    for c in CLASSES:
        fig.add_bar(x=[str(i) for i in cls.index], y=cls[c].values, name=c, marker_color=CLS_COL[c], row=1, col=2)
    fig.update_yaxes(title="% del prezzo", row=1, col=1, secondary_y=False)
    fig.update_yaxes(title="% rialzisti", range=[0, 100], row=1, col=1, secondary_y=True, showgrid=False)
    return _layout(fig, 400, barmode="stack")


def fig_years(b):
    g = b.groupby("year")
    rng, up = g.rng.mean() * 100, g.ret.apply(lambda x: (x > 0).mean() * 100)
    cls = pd.crosstab(b.year, b.cls, normalize="index").reindex(columns=CLASSES, fill_value=0) * 100
    x = [str(i) for i in rng.index]
    fig = make_subplots(1, 2, specs=[[{"secondary_y": True}, {}]],
                        subplot_titles=["Spostamento medio e % rialzisti per anno", "Tipo di periodo per anno"])
    fig.add_bar(x=x, y=rng.values, name="Spostamento medio %", marker_color=GREY, row=1, col=1)
    fig.add_scatter(x=x, y=up.values, name="% rialzisti", mode="lines+markers", line=dict(color=GREEN),
                    row=1, col=1, secondary_y=True)
    for c in CLASSES:
        fig.add_bar(x=x, y=cls[c].values, name=c, marker_color=CLS_COL[c], row=1, col=2)
    fig.update_yaxes(title="% rialzisti", range=[0, 100], row=1, col=1, secondary_y=True, showgrid=False)
    return _layout(fig, 400, barmode="stack")


def fig_history(d1):
    c = d1["close"]
    has_v = "volume" in d1
    titles = ["Prezzo giornaliero (scala log) con SMA50 / SMA200", "Drawdown dal massimo %"]
    if has_v:
        titles.append("Volume giornaliero con media 20 / 252")
    fig = make_subplots(len(titles), 1, shared_xaxes=True, vertical_spacing=0.05, subplot_titles=titles,
                        row_heights=[0.55, 0.2, 0.25][: len(titles)])
    fig.add_scatter(x=c.index, y=c, name="Chiusura", line=dict(width=1.3, color="#e5e7eb"), row=1, col=1)
    fig.add_scatter(x=c.index, y=c.rolling(50).mean(), name="SMA50", line=dict(width=1, color=AMBER), row=1, col=1)
    fig.add_scatter(x=c.index, y=c.rolling(200).mean(), name="SMA200", line=dict(width=1, color=BLUE), row=1, col=1)
    fig.update_yaxes(type="log", row=1, col=1)
    dd = (c / c.cummax() - 1) * 100
    fig.add_scatter(x=dd.index, y=dd, fill="tozeroy", line=dict(width=0.8, color=RED), showlegend=False, row=2, col=1)
    if has_v:
        v = d1["volume"]
        fig.add_bar(x=v.index, y=v, marker_color="#374151", showlegend=False, row=3, col=1)
        fig.add_scatter(x=v.index, y=v.rolling(20).mean(), name="Vol MA20", line=dict(width=1, color=AMBER), row=3, col=1)
        fig.add_scatter(x=v.index, y=v.rolling(252).mean(), name="Vol MA252", line=dict(width=1.2, color=BLUE), row=3, col=1)
    return _layout(fig, 820 if has_v else 620, hovermode="x unified", legend=dict(orientation="h", y=1.06, x=0))


# ----------------------------------------------------------------------------- volume
def volume_profile(df, start, nbins=120):
    d = df[df.index >= start]
    if len(d) < 5:
        return None
    h, l, c, v = (d[k].to_numpy(float) for k in ("high", "low", "close", "volume"))
    lo, hi = l.min(), h.max()
    if hi <= lo or v.sum() <= 0:
        return None
    w = (hi - lo) / nbins
    a = np.clip(((l - lo) / w).astype(int), 0, nbins - 1)
    z = np.clip(((h - lo) / w).astype(int), 0, nbins - 1)
    per = v / (z - a + 1)  # volume della barra distribuito uniformemente sul suo range
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
    return dict(ctr=ctr, prof=prof, poc=ctr[poc], val=lo + lo_i * w, vah=lo + (hi_i + 1) * w,
                vwap=((h + l + c) / 3 * v).sum() / v.sum(), va=(lo_i, hi_i), poc_i=poc)


def fig_profiles(prof, last):
    fig = make_subplots(1, len(prof), subplot_titles=list(prof), horizontal_spacing=0.035)
    for k, (lab, pf) in enumerate(prof.items()):
        lo_i, hi_i = pf["va"]
        i = np.arange(len(pf["prof"]))
        col = np.where((i >= lo_i) & (i <= hi_i), "#1d4ed8", "#374151").astype(object)
        col[pf["poc_i"]] = AMBER
        fig.add_bar(y=pf["ctr"], x=pf["prof"], orientation="h", marker_color=list(col), showlegend=False,
                    hovertemplate="prezzo %{y}<br>volume %{x:.0f}<extra></extra>", row=1, col=k + 1)
        fig.add_hline(y=last, line=dict(color="#f9fafb", dash="dash", width=1), row=1, col=k + 1)
        fig.add_hline(y=pf["vwap"], line=dict(color=GREEN, dash="dot", width=1), row=1, col=k + 1)
    fig.update_xaxes(showticklabels=False)
    return _layout(fig, 620, bargap=0)


# ----------------------------------------------------------------------------- report
CSS = """
:root{--bg:#0b0f17;--card:#111827;--fg:#e5e7eb;--mut:#9ca3af;--line:#1f2937;--acc:#3b82f6}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
header{position:sticky;top:0;z-index:10;background:var(--bg);border-bottom:1px solid var(--line);padding:10px 16px 0}
header h1{font-size:20px;margin:0 0 2px}header p{margin:0 0 8px;color:var(--mut);font-size:12px}
nav{display:flex;gap:4px;overflow-x:auto;padding-bottom:8px}
nav button{background:#0f172a;color:var(--mut);border:1px solid var(--line);border-radius:6px;padding:6px 11px;
cursor:pointer;white-space:nowrap;font:inherit;font-size:13px}nav button.on{background:var(--acc);color:#fff;border-color:var(--acc)}
main{max-width:1500px;margin:0 auto;padding:12px 16px}h2{font-size:18px;margin:0 0 6px}
section{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin:12px 0}
.muted{color:var(--mut)}.desc{color:var(--mut);margin:0 0 10px;max-width:1100px}
.tw{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:12.5px;font-variant-numeric:tabular-nums}
th,td{padding:5px 8px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap}
th:first-child,td:first-child{text-align:left}th{color:var(--mut);font-weight:600}
tr.grp td{color:var(--acc);font-weight:600;padding-top:12px;text-align:left}
.kpi{display:grid;grid-template-columns:repeat(auto-fill,minmax(175px,1fr));gap:10px}
.kpi div{background:#0f172a;border:1px solid var(--line);border-radius:8px;padding:10px}.kpi b{display:block;font-size:18px}
.kpi span{color:var(--mut);font-size:12px}.kpi small{display:block;color:var(--mut);font-size:11px}
.plot{min-height:60px}
"""

JS = """
function show(id){
  if(!document.getElementById('tab-'+id)) id='overview';
  document.querySelectorAll('.tab').forEach(t=>t.hidden=(t.id!=='tab-'+id));
  document.querySelectorAll('nav button').forEach(b=>b.classList.toggle('on',b.dataset.tab===id));
  document.querySelectorAll('#tab-'+id+' .plot:not(.done)').forEach(d=>{
    const f=FIGS[d.dataset.fig]; Plotly.newPlot(d,f.data,f.layout,{displaylogo:false,responsive:true}); d.classList.add('done');});
  if(location.hash!=='#'+id) history.replaceState(null,'','#'+id);
  window.scrollTo(0,0);
}
document.querySelectorAll('nav button').forEach(b=>b.onclick=()=>show(b.dataset.tab));
show(location.hash.slice(1)||'overview');
"""


class Page:
    """Raccoglie i grafici: vengono disegnati solo quando si apre la loro scheda."""

    def __init__(self):
        self.figs, self.n = {}, 0

    def fig(self, fig):
        if fig is None:
            return ""
        self.n += 1
        fid = f"f{self.n}"
        self.figs[fid] = fig.to_json()
        return f'<div class="plot" data-fig="{fid}"></div>'


def sec(title, desc, body):
    return f"<section><h2>{title}</h2>" + (f"<p class='desc'>{desc}</p>" if desc else "") + f"{body}</section>"


def tf_page(pg, bl, px, last):
    spec, b = bl.spec, bl.b
    key, label, src = spec["key"], spec["label"], bl.src.upper()
    if len(b) < 3:
        return sec(label, "", "<p class='muted'>Meno di 3 periodi completi: servono più dati storici.</p>")
    big = b.loc[b.rng.idxmax()]
    cls_share = b.cls.value_counts(normalize=True).reindex(CLASSES).fillna(0)
    nxt = next_period(b)
    items = [("Periodi analizzati", f"{len(b):,}".replace(",", "."), f"{b.t0.iloc[0]:%Y-%m-%d} → {b.t0.iloc[-1]:%Y-%m-%d}"),
             ("Spostamento più ampio mediano", fmt(b.rng.median() * 100, 3, "%"), f"≈ {px(b.rng.median() * last)} in prezzo"),
             ("Spostamento medio", fmt(b.rng.mean() * 100, 3, "%"), f"≈ {px(b.rng.mean() * last)}"),
             ("1 periodo su 10 supera", fmt(b.rng.quantile(0.9) * 100, 3, "%"), f"≈ {px(b.rng.quantile(0.9) * last)}"),
             ("Spostamento massimo storico", fmt(big.rng * 100, 2, "%"), period_label(key, [big.t0])[0]),
             ("Periodi rialzisti", fmt((b.ret > 0).mean() * 100, 1, "%"), f"rendimento medio {fmt(b.ret.mean() * 100, 3, '%')}"),
             ("Trend (restituisce ≤ 25%)", fmt(cls_share["Trend"] * 100, 1, "%"), "chiude vicino all'estremo"),
             ("Mean reversion (restituisce ≥ 75%)", fmt(cls_share["Mean reversion"] * 100, 1, "%"), "torna indietro quasi tutto"),
             ("Parziale", fmt(cls_share["Parziale"] * 100, 1, "%"), "restituisce tra 25% e 75%"),
             ("Mean reversion media", fmt(b.retr.mean() * 100, 3, "%"), f"{fmt(b.rf.mean() * 100, 0)}% dello spostamento"),
             ("Periodo dopo nella stessa direzione", fmt(nxt[0]["same"] * 100, 1, "%") if nxt else "–", "")]
    if bl.intra:
        items += [("Massimo più spesso in", most(b.bH), TIMING_UNIT.get(key, "")),
                  ("Minimo più spesso in", most(b.bL), TIMING_UNIT.get(key, ""))]
    note = (f"Misurato su barre {src}: il 'quando' dentro il periodo ha la risoluzione di una barra {src}."
            if bl.intra else f"Ogni periodo è una singola barra {src}: si misurano ampiezza e direzione; l'ordine "
            "massimo/minimo è dedotto dalla candela (chiusura sopra l'apertura = prima il minimo).")
    out = [sec(f"{label}: sintesi", note, kpis(items))]
    out.append(sec("Spostamento più ampio e mean reversion: quanto",
                   "Ogni riga è una misura calcolata su tutti i periodi, in % del prezzo di apertura del periodo. "
                   "P90 = superato solo nel 10% dei periodi. Le ultime due colonne traducono mediana e P90 in prezzo "
                   "al livello attuale.",
                   table(["Misura", "N", "Media %", "P10 %", "P25 %", "Mediana %", "P75 %", "P90 %", "P95 %", "Max %",
                          "Mediana ≈ prezzo", "P90 ≈ prezzo"], pct_rows(b, px, last)) + pg.fig(fig_dist(b))))
    if bl.intra:
        out.append(sec("Quando avvengono",
                       f"Sinistra: in quale {TIMING_UNIT.get(key)} si forma il massimo e il minimo del periodo. Destra: dove "
                       "finisce lo spostamento più ampio, cioè il punto da cui parte il rientro (mean reversion).",
                       pg.fig(fig_timing(b, TIMING_UNIT.get(key)))))
    if category(spec, b.t0.iloc[:1]) is not None:
        cname = {"min": "ora del giorno", "h1": "ora del giorno", "d": "giorno della settimana", "q": "trimestre",
                 "s": "semestre"}.get(key, "blocco orario" if spec.get("k") else "mese")
        crow = []
        for cv, x in b.groupby("cat", observed=True):
            crow.append([str(cv), len(x), fmt(x.rng.mean() * 100, 3), fmt(x.rng.median() * 100, 3),
                         px(x.rng.median() * last), (fmt((x.ret > 0).mean() * 100, 1), pcol((x.ret > 0).mean())),
                         fmt(x.ret.mean() * 100, 3), fmt((x.cls == "Trend").mean() * 100, 1),
                         fmt((x.cls == "Mean reversion").mean() * 100, 1), fmt(x.rf.mean() * 100, 0),
                         fmt(x.rv.mean(), 2) if "rv" in x else "–"] + ([most(x.bH), most(x.bL)] if bl.intra else []))
        out.append(sec(f"Quando: per {cname}", f"Come cambiano ampiezza, direzione e tipo di periodo in base a {cname}.",
                       pg.fig(fig_category(b, cname)) + table(
                           [cname.capitalize(), "N", "Spost. medio %", "Spost. mediano %", "≈ prezzo", "% rialzisti",
                            "Rend. medio %", "% Trend", "% Mean rev.", "Restituito medio %", "Volume rel."]
                           + (["Massimo più spesso", "Minimo più spesso"] if bl.intra else []), crow)))
    if key != "y" and b.year.nunique() > 1:
        out.append(sec("Come cambia nel tempo", "Stesse misure, anno per anno.", pg.fig(fig_years(b))))

    nrows, last_g = [], None
    for r in nxt:
        if r["group"] and r["group"] != last_g:
            nrows.append(r["group"])
        last_g = r["group"]
        nrows.append([r["label"], r["N"], (fmt(r["same"] * 100, 1), pcol(r["same"])), (fmt(r["up"] * 100, 1), pcol(r["up"])),
                      fmt(r["ret"] * 100, 3), (fmt(r["rr"], 2), pcol(r["rr"], 1, 0.5)), fmt(r["bh"] * 100, 1),
                      fmt(r["bl"] * 100, 1), fmt(r["inside"] * 100, 1), fmt(r["fb"] * 100, 1), fmt(r["mid"] * 100, 1)])
    out.append(sec("Cosa succede nel periodo successivo (momentum o mean reversion fra periodi)",
                   "Per ogni condizione del periodo appena chiuso: quante volte il successivo va nella stessa direzione "
                   "(blu = prosegue, momentum; rosso = inverte, mean reversion), quanto è ampio rispetto al mediano, quante "
                   "volte rompe il massimo o il minimo precedente, quante volte resta dentro (inside), quante rotture sono "
                   "false (rompe ma chiude di nuovo dentro il range precedente) e quante volte torna a metà del periodo "
                   "precedente.",
                   table(["Condizione", "N", "% stessa direzione", "% rialzista", "Rend. medio %", "Ampiezza vs mediano",
                          "% rompe massimo prec.", "% rompe minimo prec.", "% inside", "% false rotture",
                          "% torna a metà prec."], nrows)))

    tf = "%Y-%m-%d %H:%M" if bl.src != "d1" else "%Y-%m-%d"

    def plist(x):
        return [[period_label(key, [r.t0])[0], px(r.O), px(r.H), px(r.L), px(r.C), fmt(r.rng * 100, 3),
                 (fmt(r.ret * 100, 3), pcol(r.ret, 0, max(b.rng.median(), 1e-9))), r.dir, str(r.cls), fmt(r.rf * 100, 0),
                 f"{r.tH:{tf}}" if bl.intra else "–", f"{r.tL:{tf}}" if bl.intra else "–",
                 fmt(getattr(r, "rv", np.nan), 2)] for r in x.itertuples()]

    hdr = ["Periodo", "Apertura", "Massimo", "Minimo", "Chiusura", "Spostamento %", "Rendimento %", "Spostamento",
           "Tipo", "Restituito %", "Quando il massimo", "Quando il minimo", "Volume rel."]
    if key == "y":
        out.append(sec("Anno per anno", "", table(hdr, plist(b.iloc[::-1]))))
    else:
        out.append(sec("Periodi più ampi della storia", "I 15 periodi con lo spostamento più ampio.",
                       table(hdr, plist(b.nlargest(15, "rng")))))
        out.append(sec("Ultimi periodi chiusi", "", table(hdr, plist(b.iloc[-15:][::-1]))))
    return "".join(out)


def overview(pg, data, blocks, px, last, last_time):
    d1 = data["d1"]
    c = d1["close"]
    s50, s200 = c.rolling(50).mean().iloc[-1], c.rolling(200).mean().iloc[-1]
    y = c[c.index >= c.index[-1] - pd.Timedelta(days=365)]
    dd = c / c.cummax() - 1
    items = [("Ultimo prezzo", px(last), f"{last_time:%Y-%m-%d %H:%M}"),
             ("vs SMA50 giornaliera", fmt((last / s50 - 1) * 100, 2, "%"), px(s50)),
             ("vs SMA200 giornaliera", fmt((last / s200 - 1) * 100, 2, "%"), px(s200)),
             ("Massimo 52 settimane", px(y.max()), fmt((last / y.max() - 1) * 100, 2, "% dal massimo")),
             ("Minimo 52 settimane", px(y.min()), fmt((last / y.min() - 1) * 100, 2, "% dal minimo")),
             ("Drawdown attuale", fmt(dd.iloc[-1] * 100, 1, "%"), f"massimo storico {fmt(dd.min() * 100, 1, '%')}")]
    for lab, days in (("1 settimana", 7), ("1 mese", 30), ("3 mesi", 91), ("6 mesi", 182), ("12 mesi", 365)):
        p = c[c.index <= c.index[-1] - pd.Timedelta(days=days)]
        if len(p):
            items.append((f"Rendimento {lab}", fmt((last / p.iloc[-1] - 1) * 100, 2, "%"), ""))

    crow, srow = [], []
    for spec in TFS:
        bl = blocks.get(spec["key"])
        if bl is None or len(bl.b) < 3:
            continue
        b, cu = bl.b, bl.cur
        med = b.rng.median()
        if bl.intra:
            el = min(cu.cnt / bl.med_cnt, 1)
            rs = (cu.H - cu.L) / cu.O
            pos = (last - cu.L) / (cu.H - cu.L) if cu.H > cu.L else np.nan
            crow.append([spec["label"], period_label(spec["key"], [cu.t0])[0], fmt(el * 100, 0, "%"), px(cu.O), px(cu.H),
                         px(cu.L), (fmt((last / cu.O - 1) * 100, 3, "%"), pcol(last / cu.O - 1, 0, max(med, 1e-9))),
                         fmt(rs * 100, 3, "%"), (fmt(rs / med * 100, 0, "%"), pcol(rs / med, 1, 0.6)),
                         fmt((b.rng <= rs).mean() * 100, 0), fmt(pos * 100, 0, "%"),
                         fmt((b.pH <= el).mean() * 100, 0, "%"), fmt((b.pL <= el).mean() * 100, 0, "%")])
        nx = next_period(b)
        srow.append([spec["label"], len(b), fmt(med * 100, 3), px(med * last), fmt(b.rng.quantile(0.9) * 100, 3),
                     (fmt((b.ret > 0).mean() * 100, 1), pcol((b.ret > 0).mean())),
                     fmt((b.cls == "Trend").mean() * 100, 1), fmt((b.cls == "Mean reversion").mean() * 100, 1),
                     fmt(b.retr.mean() * 100, 3), fmt(b.rf.mean() * 100, 0),
                     most(b.bH) if bl.intra else "–", most(b.bL) if bl.intra else "–",
                     (fmt(nx[0]["same"] * 100, 1), pcol(nx[0]["same"])) if nx else "–"])
    return "".join([
        sec("Stato attuale", "", kpis(items)),
        sec("Periodo in corso, per timeframe",
            "Il periodo non ancora chiuso di ogni timeframe confrontato con la storia: quanto spostamento ha già fatto "
            "rispetto al mediano (100% = ha già fatto uno spostamento tipico), in quale percentile storico cade, dove si "
            "trova il prezzo nel range del periodo (0% = sul minimo, 100% = sul massimo) e in quale percentuale dei periodi "
            "passati il massimo e il minimo erano già stati fatti a questo punto del periodo.",
            table(["Timeframe", "Periodo", "Trascorso", "Apertura", "Massimo finora", "Minimo finora", "Dall'apertura",
                   "Spostamento finora", "vs mediano", "Percentile", "Posizione nel range",
                   "Massimo già fatto (storico)", "Minimo già fatto (storico)"], crow)),
        sec("Sintesi di tutti i timeframe", "Valori su tutta la storia disponibile. Dettagli nelle schede.",
            table(["Timeframe", "N periodi", "Spost. mediano %", "≈ prezzo", "Spost. P90 %", "% rialzisti", "% Trend",
                   "% Mean rev.", "Mean rev. media %", "Restituito medio %", "Massimo più spesso", "Minimo più spesso",
                   "% successivo stessa direzione"], srow)),
        sec("Come cambia il prezzo nel tempo", "", pg.fig(fig_history(d1)))])


def volume_tab(pg, data, meta, px, last):
    base = data.get("h1") if data.get("h1") is not None else data["d1"]
    d1 = data["d1"]
    if "volume" not in base or base["volume"].sum() <= 0:
        return sec("Volume", "", "<p class='muted'>Nessun dato di volume disponibile.</p>")
    end = base.index[-1]
    prof = {}
    for lab, days in (("12 mesi", 365), ("6 mesi", 182), ("3 mesi", 91), ("1 mese", 30), ("1 settimana", 7)):
        pf = volume_profile(base, end - pd.Timedelta(days=days))
        if pf:
            prof[lab] = pf
    tv = table(["Finestra", "POC (prezzo con più volume)", "Value Area bassa", "Value Area alta", "VWAP",
                "Prezzo vs POC", "Prezzo vs VWAP", "Posizione"],
               [[lab, px(pf["poc"]), px(pf["val"]), px(pf["vah"]), px(pf["vwap"]),
                 (fmt((last / pf["poc"] - 1) * 100, 2, "%"), pcol(last / pf["poc"] - 1, 0, 0.05)),
                 (fmt((last / pf["vwap"] - 1) * 100, 2, "%"), pcol(last / pf["vwap"] - 1, 0, 0.05)),
                 "sopra la Value Area" if last > pf["vah"] else "sotto la Value Area" if last < pf["val"]
                 else "dentro la Value Area"] for lab, pf in prof.items()])
    vk = []
    if "volume" in d1:
        v = d1["volume"]
        vk += [("Volume ultima sessione", f"{v.iloc[-1]:,.0f}".replace(",", "."), f"{v.index[-1]:%Y-%m-%d}"),
               ("vs media 20 sessioni", fmt(v.iloc[-1] / v.iloc[-21:-1].mean(), 2, "×"), ""),
               ("vs media 252 sessioni", fmt(v.iloc[-1] / v.iloc[-253:-1].mean(), 2, "×"), ""),
               ("Percentile sull'ultimo anno", fmt((v.iloc[-253:-1] < v.iloc[-1]).mean() * 100, 0), ""),
               ("Media 20 / media 252", fmt(v.iloc[-20:].mean() / v.iloc[-252:].mean(), 2, "×"),
                "partecipazione recente vs anno")]
    hv = ""
    h1 = data.get("h1")
    if h1 is not None and "volume" in h1:
        v = h1["volume"]
        te = v.index[-1]
        same = v[(v.index.hour == te.hour) & (v.index < te)].iloc[-20:].mean()
        vk.append(("Ultima ora vs stessa ora (20 gg)", fmt(v.iloc[-1] / same, 2, "×"), f"{te:%Y-%m-%d %H:00}"))
        fig = go.Figure()
        for s, lab, col in ((v[v.index >= te - pd.Timedelta(days=365)], "Media 12 mesi", GREY),
                            (v[v.index >= te - pd.Timedelta(days=28)], "Media ultime 4 settimane", BLUE),
                            (v[v.index.normalize() == te.normalize()], "Ultima sessione", AMBER)):
            g = s.groupby(s.index.hour).mean()
            if len(g):
                fig.add_scatter(x=[f"{h:02d}h" for h in g.index], y=g.values, name=lab, mode="lines+markers",
                                line=dict(color=col))
        hv = pg.fig(_layout(fig, 380, xaxis_title="Ora (server)", yaxis_title="Volume medio per barra H1"))
    return (sec("Dove si è scambiato di più (Volume Profile)",
                f"Profilo da barre {'H1' if base is h1 else 'D1'}: il volume di ogni barra è distribuito sul suo range. "
                "<b style='color:#f59e0b'>Arancio</b> = POC, blu = Value Area (70% del volume), tratteggio bianco = prezzo "
                "attuale, punteggiato verde = VWAP."
                + (" Volume = tick volume (attività, non controvalore)." if meta.get("vol_kind") == "tick" else ""),
                tv + (pg.fig(fig_profiles(prof, last)) if prof else ""))
            + sec("Volume attuale rispetto allo storico", "", kpis(vk) + hv))


def build_report(name, data, meta, offline=False):
    last_src = max((k for k in ("m1", "h1", "d1") if data.get(k) is not None), key=lambda k: data[k].index[-1])
    last, last_time = float(data[last_src]["close"].iloc[-1]), data[last_src].index[-1]
    dg = meta.get("digits")
    digits = int(dg) if dg is not None else int(np.clip(5 - np.floor(np.log10(last)), 0, 5))

    def px(x):
        return fmt(x, digits)

    pg = Page()
    blocks, tabs = {}, []
    for spec in TFS:
        s = pick_source(spec, data)
        if s is None:
            need = spec["src"][0].upper()
            tabs.append((spec["key"], spec["label"], sec(spec["label"], "", f"<p class='muted'>Servono dati {need} "
                                                                              f"(MT5 o --csv-{need.lower()}).</p>")))
            continue
        bl = Blocks(spec, data[s], s)
        blocks[spec["key"]] = bl
        tabs.append((spec["key"], spec["label"], tf_page(pg, bl, px, last)))
    tabs = ([("overview", "Panoramica", overview(pg, data, blocks, px, last, last_time))] + tabs
            + [("volume", "Volume", volume_tab(pg, data, meta, px, last))])

    nav = "".join(f'<button data-tab="{k}">{html.escape(lb)}</button>' for k, lb, _ in tabs)
    body = "".join(f'<div class="tab" id="tab-{k}" hidden>{h}</div>' for k, _, h in tabs)
    info = " · ".join(f"{k.upper()}: {len(data[k])} barre ({data[k].index[0]:%Y-%m-%d} → {data[k].index[-1]:%Y-%m-%d})"
                      for k in ("m1", "h1", "d1") if data.get(k) is not None)
    figs = ("const FIGS={" + ",".join(f'"{k}":{v}' for k, v in pg.figs.items()) + "};").replace("</", "<\\/")
    js = (f"<script>{get_plotlyjs()}</script>" if offline
          else f'<script src="https://cdn.plot.ly/plotly-{get_plotlyjs_version()}.min.js" charset="utf-8"></script>')
    return (f"<!doctype html><html lang='it'><head><meta charset='utf-8'><meta name='viewport' "
            f"content='width=device-width,initial-scale=1'><title>{html.escape(name)} — Market Profiler</title>"
            f"<style>{CSS}</style>{js}</head><body><header><h1>{html.escape(name)} — analisi descrittiva</h1>"
            f"<p>Fonte: {html.escape(meta['source'])} · {info} · orari = ora del server/fonte</p><nav>{nav}</nav></header>"
            f"<main>{body}</main><script>{figs}{JS}</script></body></html>")


def prepare(data):
    data = {k: v for k, v in data.items() if v is not None and len(v)}
    if "h1" not in data and "m1" in data:
        data["h1"] = resample(data["m1"], "1h")
    if "d1" not in data:
        data["d1"] = resample(data.get("h1", data.get("m1")), "1D")
    return data


def main():
    ap = argparse.ArgumentParser(description="Analisi descrittiva di uno strumento per timeframe -> report HTML a schede")
    ap.add_argument("--mt5", nargs="+", metavar="SYMBOL", help="simboli dal terminale MT5 aperto")
    ap.add_argument("--yf", nargs="+", metavar="TICKER", help="ticker Yahoo Finance (prova)")
    ap.add_argument("--csv-m1", help="CSV M1 (export MT5 o generico OHLCV)")
    ap.add_argument("--csv-h1", help="CSV H1")
    ap.add_argument("--csv-d1", help="CSV D1")
    ap.add_argument("--name", help="nome dello strumento per i CSV")
    ap.add_argument("--bars-m1", type=int, default=500_000, help="barre M1 da MT5 (0 = non scaricare)")
    ap.add_argument("--bars-h1", type=int, default=100_000)
    ap.add_argument("--bars-d1", type=int, default=20_000)
    ap.add_argument("--out", default=".", help="cartella di output")
    ap.add_argument("--offline", action="store_true", help="incorpora plotly.js nel file (funziona senza internet)")
    a = ap.parse_args()

    if a.mt5:
        bars = dict(m1=a.bars_m1, h1=a.bars_h1, d1=a.bars_d1)
        jobs = [(s, lambda s=s: load_mt5(s, bars)) for s in a.mt5]
    elif a.yf:
        jobs = [(t, lambda t=t: load_yf(t)) for t in a.yf]
    elif a.csv_m1 or a.csv_h1 or a.csv_d1:
        def from_csv():
            data, kind = {}, None
            for k, p in (("m1", a.csv_m1), ("h1", a.csv_h1), ("d1", a.csv_d1)):
                if p:
                    data[k], kd = load_csv(p)
                    kind = kind or kd
            return data, dict(source="CSV", digits=None, vol_kind=kind)
        jobs = [(a.name or Path(a.csv_h1 or a.csv_m1 or a.csv_d1).stem, from_csv)]
    else:
        ap.error("indica una sorgente: --mt5, --csv-m1/--csv-h1/--csv-d1 oppure --yf")

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for name, loader in jobs:
        try:
            data, meta = loader()
            path = out / f"report_{''.join(ch if ch.isalnum() else '_' for ch in name)}.html"
            path.write_text(build_report(name, prepare(data), meta, a.offline), encoding="utf-8")
            print(f"[ok] {name}: {path}")
        except Exception as e:  # un simbolo fallito non blocca gli altri
            print(f"[errore] {name}: {e}", file=sys.stderr)
            if len(jobs) == 1:
                raise


if __name__ == "__main__":
    main()
