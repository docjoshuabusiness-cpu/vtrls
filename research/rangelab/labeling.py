"""
Etichettatura triple-barrier.

L'etichetta ha la STESSA asimmetria del trade reale: barriera di profitto,
barriera di perdita, scadenza temporale. Etichettare con "e' salito dopo N
barre" e' l'errore che rende ottimisti quasi tutti i backtest amatoriali,
perche' ignora che una discesa intermedia avrebbe chiuso la posizione.

Convenzione sui costi: espressi in tick e sottratti al P/L lordo, cosi' il
rendimento in R e' gia' netto.

Ambiguita' intrabarra: se una barra tocca sia TP sia SL, si assume che sia
stato colpito prima lo SL. E' l'ipotesi conservativa, l'unica difendibile
senza dati tick.
"""
from __future__ import annotations

import numpy as np
import pandas as pd


def triple_barrier(df: pd.DataFrame, events: pd.DataFrame,
                   session_end: str,
                   tp_mult: float = 1.0, sl_mult: float = 0.5,
                   max_minutes: int | None = None,
                   tick: float = 0.25,
                   cost_ticks: float = 3.0) -> pd.DataFrame:
    """Applica le barriere a ogni evento e ritorna le colonne di esito.

    tp_mult / sl_mult sono multipli dell'ampiezza del range (W), non valori
    assoluti: cosi' il trade si adatta alla volatilita' della giornata e i
    risultati sono confrontabili fra regimi diversi.
    """
    if events.empty:
        return events

    h, m = map(int, session_end.split(":"))
    m_close = h * 60 + m
    tod = df.index.hour * 60 + df.index.minute
    frame = df[tod < m_close]

    by_day = {d: g for d, g in frame.groupby(frame.index.normalize())}
    cost = cost_ticks * tick

    out = []
    for ev in events.itertuples(index=False):
        g = by_day.get(ev.date)
        if g is None:
            out.append(_empty())
            continue

        pos = g.index.searchsorted(ev.dt, side="right")   # si entra alla barra SUCCESSIVA
        sub = g.iloc[pos:]
        if max_minutes is not None:
            sub = sub[sub.index <= ev.dt + pd.Timedelta(minutes=max_minutes)]
        if sub.empty:
            out.append(_empty())
            continue

        risk = sl_mult * ev.width
        if risk <= 0:
            out.append(_empty())
            continue

        d = ev.dir
        tp = ev.entry + d * tp_mult * ev.width
        sl = ev.entry - d * sl_mult * ev.width

        hi = sub["high"].to_numpy()
        lo = sub["low"].to_numpy()

        if d > 0:
            hit_tp = hi >= tp
            hit_sl = lo <= sl
            fav = (hi - ev.entry)
            adv = (ev.entry - lo)
        else:
            hit_tp = lo <= tp
            hit_sl = hi >= sl
            fav = (ev.entry - lo)
            adv = (hi - ev.entry)

        i_tp = int(np.argmax(hit_tp)) if hit_tp.any() else len(sub)
        i_sl = int(np.argmax(hit_sl)) if hit_sl.any() else len(sub)

        if i_sl <= i_tp and i_sl < len(sub):        # pari merito -> SL (conservativo)
            label, k = -1, i_sl
            gross = -sl_mult * ev.width
        elif i_tp < len(sub):
            label, k = 1, i_tp
            gross = tp_mult * ev.width
        else:                                        # scadenza
            label, k = 0, len(sub) - 1
            gross = d * (sub["close"].iloc[-1] - ev.entry)

        out.append({
            "label": label,
            "r_net": (gross - cost) / risk,
            "mfe_w": float(fav[:k + 1].max() / ev.width),
            "mae_w": float(adv[:k + 1].max() / ev.width),
            "bars_held": k + 1,
            "exit_dt": sub.index[k],
        })

    res = pd.DataFrame(out, index=events.index)
    return pd.concat([events, res], axis=1)


def _empty() -> dict:
    return {"label": np.nan, "r_net": np.nan, "mfe_w": np.nan,
            "mae_w": np.nan, "bars_held": np.nan, "exit_dt": pd.NaT}
