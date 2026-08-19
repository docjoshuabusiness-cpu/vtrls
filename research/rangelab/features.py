"""
Indicatori, costruzione del range di accumulazione ed estrazione degli eventi
di rottura con le feature di qualita'.

Tutte le feature sono CAUSALI: ogni normalizzazione usa solo dati dei giorni
precedenti (shift(1) prima di ogni rolling). Nessuna feature guarda avanti.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

# --------------------------------------------------------------------------
# Indicatori
# --------------------------------------------------------------------------
def cci(df: pd.DataFrame, period: int = 20) -> pd.Series:
    """CCI su prezzo tipico, identico all'implementazione MT5."""
    tp = (df["high"] + df["low"] + df["close"]) / 3.0
    sma = tp.rolling(period, min_periods=period).mean()
    mad = (tp - sma).abs().rolling(period, min_periods=period).mean()
    return (tp - sma) / (0.015 * mad.replace(0.0, np.nan))


def efficiency_ratio(series: pd.Series, period: int) -> pd.Series:
    """ER di Kaufman: |P_t - P_{t-n}| / somma dei |passi|. In [0, 1]."""
    direction = (series - series.shift(period)).abs()
    volatility = series.diff().abs().rolling(period, min_periods=period).sum()
    return direction / volatility.replace(0.0, np.nan)


def ama(df: pd.DataFrame, period: int = 10, fast: int = 2, slow: int = 30,
        price: str = "close") -> pd.Series:
    """AMA di Kaufman. Ricorsiva, quindi va calcolata in loop."""
    p = df[price]
    er = efficiency_ratio(p, period).fillna(0.0)
    fsc, ssc = 2.0 / (fast + 1), 2.0 / (slow + 1)
    sc = (er * (fsc - ssc) + ssc) ** 2

    vals = np.empty(len(p))
    vals[:] = np.nan
    pv, scv = p.to_numpy(), sc.to_numpy()
    prev = pv[0]
    for i in range(len(pv)):
        prev = prev + scv[i] * (pv[i] - prev)
        vals[i] = prev
    out = pd.Series(vals, index=p.index)
    out.iloc[:period] = np.nan
    return out


def atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    """ATR di Wilder."""
    pc = df["close"].shift(1)
    tr = pd.concat([df["high"] - df["low"],
                    (df["high"] - pc).abs(),
                    (df["low"] - pc).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1.0 / period, adjust=False, min_periods=period).mean()


def resample(df: pd.DataFrame, rule: str) -> pd.DataFrame:
    """Riaggrega barre 1-min al timeframe di analisi (es. '5min')."""
    if rule in (None, "1min", "1T"):
        return df
    out = df.resample(rule, label="left", closed="left").agg(
        {"open": "first", "high": "max", "low": "min",
         "close": "last", "volume": "sum"})
    return out.dropna(subset=["open", "close"])


# --------------------------------------------------------------------------
# Volume z-score normalizzato per ora del giorno
# --------------------------------------------------------------------------
def volume_zscore_tod(df: pd.DataFrame, lookback_days: int = 20,
                      min_days: int = 5) -> pd.Series:
    """Z-score del volume rispetto allo STESSO minuto del giorno nei giorni
    precedenti. Il volume grezzo misura l'ora, non l'evento: senza questa
    normalizzazione un breakout alle 15:30 sembra sempre 'ad alto volume'.

    shift(1) dentro il gruppo esclude la barra corrente: nessun look-ahead.
    """
    tod = df.index.hour * 60 + df.index.minute
    # scala logaritmica: il volume e' approssimativamente lognormale e ha code
    # pesanti. Standardizzarlo in scala lineare produce z-score da migliaia
    # su un singolo spike, che poi dominano qualunque score composito.
    lv = np.log1p(df["volume"])
    g = lv.groupby(tod)
    mu = g.transform(lambda s: s.shift(1).rolling(lookback_days, min_periods=min_days).mean())
    sd = g.transform(lambda s: s.shift(1).rolling(lookback_days, min_periods=min_days).std())
    z = (lv - mu) / sd.where(sd > 1e-9)
    return z.clip(-6.0, 6.0)


# --------------------------------------------------------------------------
# Range di accumulazione
# --------------------------------------------------------------------------
def _minutes(hhmm: str) -> int:
    h, m = map(int, hhmm.split(":"))
    return h * 60 + m


def build_ranges(df: pd.DataFrame, start: str, end: str,
                 profile_bins: int = 20, median_days: int = 20) -> pd.DataFrame:
    """Costruisce un range di accumulazione per giorno di calendario.

    Ritorna un DataFrame indicizzato per data con:
      hi, lo, width, mid, poc, poc_centrality, entropy, bar_range_mean,
      compression (calcolata sui SOLI giorni precedenti)
    """
    tod = df.index.hour * 60 + df.index.minute
    m0, m1 = _minutes(start), _minutes(end)
    if m1 <= m0:
        raise ValueError("La finestra di accumulazione non puo' scavalcare la mezzanotte")

    win = df[(tod >= m0) & (tod < m1)]
    if win.empty:
        raise ValueError(f"Nessuna barra nella finestra {start}-{end}: controlla il fuso orario")

    day = win.index.normalize()
    rows = []
    for d, g in win.groupby(day):
        hi, lo = g["high"].max(), g["low"].min()
        w = hi - lo
        if w <= 0 or len(g) < 3:
            continue

        # profilo di volume sul range: POC e entropia del tempo-a-prezzo
        edges = np.linspace(lo, hi, profile_bins + 1)
        centers = (edges[:-1] + edges[1:]) / 2.0
        typ = ((g["high"] + g["low"] + g["close"]) / 3.0).to_numpy()
        hist, _ = np.histogram(typ, bins=edges, weights=g["volume"].to_numpy())
        tot = hist.sum()
        if tot <= 0:
            continue
        p = hist / tot
        poc = float(centers[int(np.argmax(hist))])
        nz = p[p > 0]
        entropy = float(-(nz * np.log(nz)).sum() / np.log(profile_bins))

        rows.append({
            "date": d, "hi": float(hi), "lo": float(lo), "width": float(w),
            "mid": float((hi + lo) / 2.0), "poc": poc,
            "poc_centrality": float(1.0 - 2.0 * abs(poc - (hi + lo) / 2.0) / w),
            "entropy": entropy,
            "bar_range_mean": float((g["high"] - g["low"]).mean()),
            "range_vol": float(g["volume"].sum()),
            "n_bars": len(g),
        })

    r = pd.DataFrame(rows).set_index("date").sort_index()
    # compressione: mediana delle ampiezze dei giorni PRECEDENTI (causale)
    med = r["width"].shift(1).rolling(median_days, min_periods=5).median()
    r["width_median"] = med
    r["compression"] = -np.log(r["width"] / med)
    return r


# --------------------------------------------------------------------------
# Estrazione eventi di rottura
# --------------------------------------------------------------------------
def extract_breakouts(df: pd.DataFrame, ranges: pd.DataFrame,
                      range_end: str, session_end: str,
                      buffer_frac: float = 0.05,
                      er_period: int = 10,
                      reentry_bars: int = 3,
                      cci_period: int = 20,
                      ama_period: int = 10, ama_fast: int = 2, ama_slow: int = 30,
                      atr_period: int = 14) -> pd.DataFrame:
    """Enumera OGNI rottura del range, con le feature di qualita'.

    Nessun filtro applicato: filtrare qui significherebbe decidere prima di
    misurare. La selezione avviene a valle, sui dati.

    Macchina a stati sul CLOSE: inside -> above / below genera un evento.
    Il rientro dentro il range riarma la macchina (tentativo successivo).
    """
    ind = pd.DataFrame(index=df.index)
    ind["cci"] = cci(df, cci_period)
    ind["ama"] = ama(df, ama_period, ama_fast, ama_slow)
    ind["er"] = efficiency_ratio(df["close"], er_period)
    ind["atr"] = atr(df, atr_period)
    ind["vz"] = volume_zscore_tod(df)

    tod = df.index.hour * 60 + df.index.minute
    m_end, m_close = _minutes(range_end), _minutes(session_end)
    post = df[(tod >= m_end) & (tod < m_close)]
    post_ind = ind.reindex(post.index)

    events = []
    for d, g in post.groupby(post.index.normalize()):
        if d not in ranges.index:
            continue
        r = ranges.loc[d]
        hi, lo, w = r["hi"], r["lo"], r["width"]
        buf = buffer_frac * w
        gi = post_ind.loc[g.index]

        c = g["close"].to_numpy()
        state, attempt = 0, 0          # 0 = dentro, +1 = sopra, -1 = sotto
        for i in range(len(g)):
            if c[i] > hi + buf:
                new = 1
            elif c[i] < lo - buf:
                new = -1
            else:
                new = 0

            if new != 0 and state == 0:
                attempt += 1
                ts = g.index[i]
                bar = g.iloc[i]
                row = gi.iloc[i]
                bar_rng = bar["high"] - bar["low"]

                # rientro nel range entro k barre: metrica di "fakeout"
                k = min(i + 1 + reentry_bars, len(g))
                fut = c[i + 1:k]
                if new > 0:
                    reentered = bool((fut <= hi).any()) if len(fut) else False
                else:
                    reentered = bool((fut >= lo).any()) if len(fut) else False

                events.append({
                    "date": d, "dt": ts, "dir": new, "attempt": attempt,
                    "entry": float(bar["close"]),
                    "minutes_after_range": int((ts - (d + pd.Timedelta(minutes=m_end))).total_seconds() // 60),
                    "bar_index": i,
                    # --- feature di qualita' ---
                    "width": float(w),
                    "width_atr": float(w / row["atr"]) if row["atr"] and row["atr"] > 0 else np.nan,
                    "compression": float(r["compression"]),
                    "poc_centrality": float(r["poc_centrality"]),
                    "entropy": float(r["entropy"]),
                    "expansion": float(bar_rng / r["bar_range_mean"]) if r["bar_range_mean"] > 0 else np.nan,
                    "body_ratio": float(abs(bar["close"] - bar["open"]) / bar_rng) if bar_rng > 0 else np.nan,
                    "er": float(row["er"]) if pd.notna(row["er"]) else np.nan,
                    "vol_z": float(row["vz"]) if pd.notna(row["vz"]) else np.nan,
                    # --- segnale CCI / AMA, come nell'EA ---
                    "cci": float(row["cci"]) if pd.notna(row["cci"]) else np.nan,
                    "cci_agree": _agree(row["cci"], new, 50.0),
                    "ama_agree": _agree_ama(bar["close"], row["ama"], new),
                    # --- confermatore ---
                    "reentered": reentered,
                })
                state = new
            elif new == 0:
                state = 0

    if not events:
        return pd.DataFrame()
    ev = pd.DataFrame(events).sort_values("dt").reset_index(drop=True)
    ev["first_attempt"] = (ev["attempt"] == 1).astype(int)
    return ev


def _agree(cci_val, direction, threshold) -> float:
    if pd.isna(cci_val):
        return np.nan
    if direction > 0:
        return float(cci_val > threshold)
    return float(cci_val < -threshold)


def _agree_ama(close, ama_val, direction) -> float:
    if pd.isna(ama_val):
        return np.nan
    if direction > 0:
        return float(close > ama_val)
    return float(close < ama_val)
