"""
Caricamento dati e generatore sintetico.

Due sorgenti:
  - load_csv()   : export MT5 / CSV generico OHLCV a barre di 1 minuto
  - synthetic()  : serie sintetica per collaudare la pipeline SENZA dati reali

Il generatore sintetico e' il banco di prova del laboratorio: con edge=0.0
produce rumore puro con le stesse proprieta' statistiche del NQ intraday
(volatility clustering + stagionalita' a U). Se lo studio trova un "edge"
su quei dati, la pipeline e' rotta. Con edge>0 inietta una relazione nota
fra compressione del range e drift successivo: lo studio deve ritrovarla.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import timedelta
from zoneinfo import ZoneInfo

import numpy as np
import pandas as pd

OHLCV = ["open", "high", "low", "close", "volume"]


# --------------------------------------------------------------------------
# Fusi orari
# --------------------------------------------------------------------------
def resolve_tz(spec: str):
    """Accetta un nome IANA ('Europe/Rome') o un offset fisso ('+03:00', 'UTC+3').

    Gli export MT5 portano l'ora del server SENZA informazione di fuso: per
    quelli si usa l'offset fisso del broker. FP Markets sta su GMT+2 in inverno
    e GMT+3 in estate, quindi un offset fisso e' corretto solo se l'export
    copre un periodo omogeneo; altrimenti va usato un nome IANA equivalente.
    """
    m = re.fullmatch(r"(?:UTC|GMT)?\s*([+-])(\d{1,2})(?::?(\d{2}))?", spec.strip())
    if m:
        sign, hh, mm = m.group(1), int(m.group(2)), int(m.group(3) or 0)
        minutes = (hh * 60 + mm) * (1 if sign == "+" else -1)
        return pd.Timedelta(minutes=minutes)
    return ZoneInfo(spec)


def to_analysis_tz(idx: pd.DatetimeIndex, data_tz, analysis_tz) -> pd.DatetimeIndex:
    """Porta un indice naive/aware nel fuso di analisi (tz-aware)."""
    if isinstance(data_tz, pd.Timedelta):
        # offset fisso: il timestamp locale del broker meno l'offset da' UTC
        idx = (idx.tz_localize(None) - data_tz).tz_localize("UTC")
    else:
        idx = idx.tz_localize(data_tz, ambiguous="NaT", nonexistent="NaT") \
            if idx.tz is None else idx.tz_convert(data_tz)
    return idx.tz_convert(analysis_tz)


# --------------------------------------------------------------------------
# Loader CSV
# --------------------------------------------------------------------------
def load_csv(path: str, data_tz: str = "UTC", analysis_tz: str = "Europe/Rome",
             sep: str | None = None) -> pd.DataFrame:
    """Carica un CSV OHLCV a 1 minuto e lo riporta nel fuso di analisi.

    Riconosce automaticamente gli export MT5 ('<DATE>\\t<TIME>\\t<OPEN>...')
    e i CSV con una singola colonna datetime.
    """
    df = pd.read_csv(path, sep=sep, engine="python" if sep is None else "c")
    df.columns = [str(c).strip().strip("<>").lower() for c in df.columns]

    if "date" in df.columns and "time" in df.columns:
        ts = pd.to_datetime(df["date"].astype(str) + " " + df["time"].astype(str),
                            format="mixed")
    else:
        tcol = next((c for c in ("datetime", "timestamp", "date", "time") if c in df.columns), None)
        if tcol is None:
            raise ValueError(f"Nessuna colonna temporale riconosciuta in {list(df.columns)}")
        ts = pd.to_datetime(df[tcol], format="mixed")

    ren = {"tickvol": "volume", "tick_volume": "volume", "vol": "volume", "real_volume": "volume"}
    df = df.rename(columns=ren)
    missing = [c for c in OHLCV if c not in df.columns]
    if missing:
        raise ValueError(f"Colonne mancanti nel CSV: {missing}")

    out = df[OHLCV].astype(float)
    out.index = to_analysis_tz(pd.DatetimeIndex(ts), resolve_tz(data_tz), resolve_tz(analysis_tz))
    out = out[~out.index.isna()]
    out = out[~out.index.duplicated(keep="first")].sort_index()
    out.index.name = "dt"
    return out


# --------------------------------------------------------------------------
# Generatore sintetico
# --------------------------------------------------------------------------
@dataclass
class SynthConfig:
    years: int = 6
    end: str = "2025-12-31"
    tz: str = "Europe/Rome"
    day_start: str = "00:00"
    day_end: str = "23:59"
    start_price: float = 15000.0
    ann_vol: float = 0.22          # volatilita' annualizzata di base
    garch_alpha: float = 0.08      # reattivita' agli shock
    garch_beta: float = 0.90       # persistenza (clustering)
    tick: float = 0.25             # tick del NQ
    edge: float = 0.0              # ampiezza dell'edge iniettato (0 = rumore puro)
    edge_window: str = "10:00"     # da che ora agisce il drift iniettato
    compressed_quantile: float = 0.33   # quota di giorni che riceve il drift
    seed: int = 7


def synthetic(cfg: SynthConfig = SynthConfig()) -> pd.DataFrame:
    """Serie 1-min sintetica con clustering di volatilita' e stagionalita' a U.

    Se cfg.edge > 0, nei giorni con range di accumulazione COMPRESSO viene
    iniettato un drift persistente dopo cfg.edge_window, nella direzione della
    prima rottura. E' la relazione che lo studio deve saper ritrovare.
    """
    rng = np.random.default_rng(cfg.seed)
    tz = ZoneInfo(cfg.tz)

    end = pd.Timestamp(cfg.end)
    days = pd.bdate_range(end=end, periods=cfg.years * 261, freq="C")

    h0, m0 = map(int, cfg.day_start.split(":"))
    h1, m1 = map(int, cfg.day_end.split(":"))
    minutes_per_day = (h1 * 60 + m1) - (h0 * 60 + m0) + 1
    if minutes_per_day <= 0:
        raise ValueError("day_end deve seguire day_start")

    n_days = len(days)
    n = n_days * minutes_per_day

    # --- stagionalita' intraday a U (moltiplicatore di volatilita') ---
    mins = np.arange(minutes_per_day) + (h0 * 60 + m0)
    # picchi: apertura cash USA (15:30 Rome) e chiusura (22:00 Rome)
    def bump(center, width, amp):
        return amp * np.exp(-0.5 * ((mins - center) / width) ** 2)
    season = 0.35 + bump(15 * 60 + 30, 45, 1.5) + bump(22 * 60, 40, 0.9) \
             + bump(9 * 60, 60, 0.35) + bump(14 * 60 + 30, 30, 0.6)
    season = np.tile(season, n_days)

    # --- volatilita' GARCH(1,1) sul giorno ---
    base_min_vol = cfg.ann_vol / np.sqrt(252 * minutes_per_day)
    omega = base_min_vol ** 2 * (1 - cfg.garch_alpha - cfg.garch_beta)
    day_var = np.empty(n_days)
    v = base_min_vol ** 2
    for i in range(n_days):
        day_var[i] = v
        shock = rng.standard_normal() * np.sqrt(v)
        v = omega + cfg.garch_alpha * shock ** 2 + cfg.garch_beta * v
    day_vol = np.sqrt(day_var)

    sigma = np.repeat(day_vol, minutes_per_day) * season
    # code grasse: t di Student a 4 gradi di liberta', riscalata a varianza 1
    z = rng.standard_t(df=4, size=n) / np.sqrt(4 / 2)
    ret = sigma * z

    # --- edge iniettato (opzionale) ------------------------------------
    if cfg.edge > 0:
        eh, em = map(int, cfg.edge_window.split(":"))
        after = np.tile(mins >= (eh * 60 + em), n_days)
        # Compressione definita per QUANTILE della distribuzione recente, non
        # con un moltiplicatore fisso: con alpha+beta=0.98 la volatilita' e'
        # quasi integrata e si muove poco attorno alla propria mediana, quindi
        # una soglia tipo "0.85 x mediana" seleziona l'1% dei giorni e l'edge
        # iniettato diventa invisibile. Il quantile garantisce una frazione
        # nota di giorni compressi qualunque sia la dispersione del processo.
        dv = pd.Series(day_vol)
        thr = dv.shift(1).rolling(60, min_periods=20).quantile(cfg.compressed_quantile)
        compressed = np.repeat((dv < thr).fillna(False).to_numpy(), minutes_per_day)
        sign = np.repeat(rng.choice([-1.0, 1.0], size=n_days), minutes_per_day)
        ret = ret + cfg.edge * sigma * sign * (after & compressed)

    price = cfg.start_price * np.exp(np.cumsum(ret))

    # --- da prezzo tick a barre OHLC (approssimazione a 4 sotto-passi) ---
    sub = price.repeat(4) * np.exp(
        rng.standard_normal(n * 4) * np.repeat(sigma, 4) * 0.45)
    sub = sub.reshape(n, 4)
    o = np.concatenate([[cfg.start_price], price[:-1]])
    c = price
    hi = np.maximum(sub.max(axis=1), np.maximum(o, c))
    lo = np.minimum(sub.min(axis=1), np.minimum(o, c))

    # --- volume: profilo intraday + correlazione con |rendimento| -------
    vbase = 800 * season / season.mean()
    # |z| viene da una t a 4 gdl: senza clip, exp(0.6*|z|) genera volumi
    # da miliardi che distruggono ogni normalizzazione a valle.
    vol = vbase * np.exp(0.6 * np.clip(np.abs(z), 0.0, 4.0) - 0.18) \
        * rng.lognormal(0, 0.35, n)

    # --- indice temporale ------------------------------------------------
    offs = pd.to_timedelta(mins, unit="m")
    idx = pd.DatetimeIndex(
        np.concatenate([(pd.Timestamp(d) + offs).to_numpy() for d in days]))
    idx = idx.tz_localize(tz, ambiguous=True, nonexistent="shift_forward")

    q = cfg.tick
    df = pd.DataFrame(
        {"open": np.round(o / q) * q, "high": np.round(hi / q) * q,
         "low": np.round(lo / q) * q, "close": np.round(c / q) * q,
         "volume": np.round(vol)},
        index=idx)
    df.index.name = "dt"
    # coerenza OHLC dopo l'arrotondamento
    df["high"] = df[["open", "high", "close"]].max(axis=1)
    df["low"] = df[["open", "low", "close"]].min(axis=1)
    return df
