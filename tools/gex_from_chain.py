#!/usr/bin/env python3
"""
gex_from_chain.py — calcolo del Gamma Exposure (GEX) dei dealer per strike
e generazione del blocco di testo da incollare in PineScript/GEX_Map.pine.

FORMULA
-------
Gamma Black-Scholes per contratto:

    d1    = [ ln(S/K) + (r - q + sigma^2/2) * T ] / (sigma * sqrt(T))
    Gamma = exp(-q*T) * phi(d1) / (S * sigma * sqrt(T))

GEX per strike, in dollari di delta da ricoprire per +1% di spot:

    GEX_call = + Gamma * OI * M * S^2 * 0.01
    GEX_put  = - Gamma * OI * M * S^2 * 0.01
    NetGEX_K = GEX_call(K) + GEX_put(K)

M = moltiplicatore del contratto (100 per QQQ/NDX).
Il fattore S^2 * 0.01 converte gamma (d delta / d S) in "delta per 1% di S".

IPOTESI (esplicite, perche' sono la parte fragile del modello)
-------------------------------------------------------------
1. Convenzione SqueezeMetrics: i dealer sono LONG call e SHORT put.
   E' un'approssimazione statistica del flusso retail, non un dato di posizione.
   Su indici come NDX il flusso istituzionale di put protettive puo' invertirla.
2. L'open interest e' EOD (T+1). Intraday il profilo e' gia' vecchio: usalo come
   mappa strutturale, non come segnale tick-by-tick.
3. La IV usata e' quella della catena (mid-market implied). Strike illiquidi
   hanno IV rumorose: il filtro --min-oi serve a questo.
4. Gamma e' calcolata sullo spot corrente, non ripricata per ogni livello: il
   "gamma flip" che ne esce e' l'attraversamento dello zero del cumulato, non
   la vera superficie di zero-gamma. Differenza tipica: pochi decimi di %.

USO
---
    pip install yfinance numpy pandas scipy
    python tools/gex_from_chain.py --ticker QQQ --days 21 --top 24
    python tools/gex_from_chain.py --ticker QQQ --scale-to-ndx --days 30

L'output va incollato nel campo "Profilo GEX per strike" dell'indicatore.
"""

from __future__ import annotations

import argparse
import datetime as dt
import sys

import numpy as np
import pandas as pd

try:
    from scipy.stats import norm
    _pdf = norm.pdf
except ImportError:  # evita una dipendenza per una sola funzione
    def _pdf(x):
        return np.exp(-0.5 * np.asarray(x, dtype=float) ** 2) / np.sqrt(2.0 * np.pi)


CONTRACT_MULT = 100.0


def bs_gamma(S: float, K: np.ndarray, T: np.ndarray, r: float, q: float,
             sigma: np.ndarray) -> np.ndarray:
    """Gamma Black-Scholes-Merton, vettoriale. Zero dove gli input sono degeneri."""
    K = np.asarray(K, dtype=float)
    T = np.asarray(T, dtype=float)
    sigma = np.asarray(sigma, dtype=float)
    ok = (T > 0) & (sigma > 0) & (K > 0) & np.isfinite(sigma)
    out = np.zeros_like(K, dtype=float)
    if not ok.any():
        return out
    st = sigma[ok] * np.sqrt(T[ok])
    d1 = (np.log(S / K[ok]) + (r - q + 0.5 * sigma[ok] ** 2) * T[ok]) / st
    out[ok] = np.exp(-q * T[ok]) * _pdf(d1) / (S * st)
    return out


def load_chain(ticker: str, max_days: int, min_oi: int, r: float, q: float):
    import yfinance as yf

    tk = yf.Ticker(ticker)
    hist = tk.history(period="5d")
    if hist.empty:
        sys.exit(f"[errore] nessun prezzo per {ticker}")
    spot = float(hist["Close"].iloc[-1])

    today = dt.date.today()
    expiries = [e for e in tk.options
                if 0 <= (dt.date.fromisoformat(e) - today).days <= max_days]
    if not expiries:
        sys.exit(f"[errore] nessuna scadenza entro {max_days} giorni per {ticker}")

    frames = []
    for exp in expiries:
        try:
            ch = tk.option_chain(exp)
        except Exception as exc:                      # scadenza sporca -> salta
            print(f"[warn] scadenza {exp} scartata: {exc}", file=sys.stderr)
            continue
        # 365 giorni di calendario: coerente con la IV quotata dai vendor
        T = max((dt.date.fromisoformat(exp) - today).days, 0) / 365.0
        for side, df in (("C", ch.calls), ("P", ch.puts)):
            if df is None or df.empty:
                continue
            d = df[["strike", "openInterest", "impliedVolatility"]].copy()
            d.columns = ["strike", "oi", "iv"]
            d["oi"] = pd.to_numeric(d["oi"], errors="coerce").fillna(0.0)
            d["iv"] = pd.to_numeric(d["iv"], errors="coerce")
            d = d[(d["oi"] >= min_oi) & d["iv"].notna() & (d["iv"] > 0.0)]
            if d.empty:
                continue
            d["T"] = T
            d["side"] = side
            frames.append(d)

    if not frames:
        sys.exit("[errore] catena vuota dopo i filtri (alza --days o abbassa --min-oi)")

    chain = pd.concat(frames, ignore_index=True)
    gamma = bs_gamma(spot, chain["strike"].to_numpy(), chain["T"].to_numpy(), r, q,
                     chain["iv"].to_numpy())
    sign = np.where(chain["side"].to_numpy() == "C", 1.0, -1.0)
    chain["gex"] = sign * gamma * chain["oi"].to_numpy() * CONTRACT_MULT * spot ** 2 * 0.01

    prof = chain.groupby("strike", as_index=False)["gex"].sum().sort_values("strike")
    return spot, prof, len(expiries)


def zero_gamma(prof: pd.DataFrame, spot: float) -> float | None:
    """Attraversamento dello zero del GEX cumulato piu' vicino allo spot."""
    k = prof["strike"].to_numpy()
    cum = np.cumsum(prof["gex"].to_numpy())
    best = None
    for i in range(1, len(k)):
        if cum[i - 1] * cum[i] < 0:
            w = cum[i - 1] / (cum[i - 1] - cum[i])
            x = k[i - 1] + w * (k[i] - k[i - 1])
            if best is None or abs(x - spot) < abs(best - spot):
                best = float(x)
    return best


def main() -> None:
    ap = argparse.ArgumentParser(description="Calcolo GEX per strike -> input per GEX_Map.pine")
    ap.add_argument("--ticker", default="QQQ", help="sottostante con opzioni liquide (QQQ, SPY, ^NDX...)")
    ap.add_argument("--days", type=int, default=21, help="orizzonte massimo delle scadenze in giorni")
    ap.add_argument("--min-oi", type=int, default=50, help="open interest minimo per contratto")
    ap.add_argument("--range-pct", type=float, default=6.0, help="mostra strike entro +/-%% dallo spot")
    ap.add_argument("--top", type=int, default=24, help="numero massimo di strike in output (per |GEX|)")
    ap.add_argument("--rate", type=float, default=0.04, help="tasso risk-free")
    ap.add_argument("--div", type=float, default=0.006, help="dividend yield del sottostante")
    ap.add_argument("--scale-to-ndx", action="store_true",
                    help="converte gli strike QQQ in punti NDX usando il rapporto NDX/QQQ corrente")
    ap.add_argument("--unit", type=float, default=1e9, help="divisore di scala (1e9 = miliardi di $)")
    args = ap.parse_args()

    spot, prof, n_exp = load_chain(args.ticker, args.days, args.min_oi, args.rate, args.div)

    ratio = 1.0
    if args.scale_to_ndx:
        import yfinance as yf
        ndx = yf.Ticker("^NDX").history(period="5d")
        if ndx.empty:
            sys.exit("[errore] impossibile leggere ^NDX per la conversione")
        ratio = float(ndx["Close"].iloc[-1]) / spot
        prof = prof.assign(strike=prof["strike"] * ratio)
        spot *= ratio

    lo, hi = spot * (1 - args.range_pct / 100), spot * (1 + args.range_pct / 100)
    view = prof[(prof["strike"] >= lo) & (prof["strike"] <= hi)].copy()
    if view.empty:
        sys.exit("[errore] nessuno strike nel range richiesto")

    flip = zero_gamma(prof, spot)
    total = prof["gex"].sum() / args.unit
    call_wall = prof.loc[prof["gex"].idxmax(), "strike"]
    put_wall = prof.loc[prof["gex"].idxmin(), "strike"]

    view["abs"] = view["gex"].abs()
    view = view.nlargest(args.top, "abs").sort_values("strike")

    dec = 0 if spot > 1000 else 1
    print(f"# GEX {args.ticker}{' -> punti NDX (x%.3f)' % ratio if args.scale_to_ndx else ''}"
          f"  |  generato {dt.datetime.now():%Y-%m-%d %H:%M}")
    print(f"# spot {spot:,.2f}  |  {n_exp} scadenze <= {args.days}g  |  unita': "
          f"{'$bn' if args.unit == 1e9 else args.unit} di delta per +1%")
    print(f"# net GEX totale {total:+.2f}  |  call wall {call_wall:,.0f}  |  put wall {put_wall:,.0f}"
          f"  |  gamma flip {flip:,.0f}" if flip else f"# net GEX totale {total:+.2f}")
    print("# ---- incolla da qui in giu' nell'indicatore ----")
    for _, row in view.iterrows():
        print(f"{row['strike']:.{dec}f} : {row['gex'] / args.unit:+.3f}")


if __name__ == "__main__":
    main()
