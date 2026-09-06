#!/usr/bin/env python3
"""
gex_full_string.py — genera la stringa dati completa per GEX_Confluence_v2_NQ.pine
partendo dalla options chain reale. Sostituisce la dipendenza da un provider
terzo e aggiunge gli strati che i provider retail tengono nel tier a pagamento.

OUTPUT
------
    S:<basis NQ-NDX>|R:<NDX/QQQ>|L:<livelli>|P:<profilo>

FAMIGLIE DI LIVELLO EMESSE
--------------------------
    ZG  zero gamma (attraversamento zero del GEX cumulato)
    MP  max pain
    EH  EL  expected move +/-1 sigma
    VH  VL  vol band (ZG +/- 25% EM)
    CW  PW  muri di net GEX
    AG  picco di ABS GEX  --- gamma call + put in valore assoluto.
        Uno strike con gamma call e put enormi che si cancellano ha net GEX ~0
        e per un modello net-only non esiste, ma e' dove l'hedging e' piu'
        intenso. E' il punto cieco di qualunque mappa basata solo sul netto.
    DP  DN  estremi di net delta exposure
    OC  OP  OA  picchi di open interest (call, put, totale)
    VC  VP  picchi di volume di sessione

FORMULE
-------
    d1     = [ln(S/K) + (r - q + s^2/2)T] / (s sqrt(T))
    gamma  = e^{-qT} phi(d1) / (S s sqrt(T))
    delta_c= e^{-qT} N(d1)          delta_p = e^{-qT} (N(d1) - 1)

    netGEX_K = (gamma_c OI_c - gamma_p OI_p) * 100 * S^2 * 0.01
    absGEX_K = (gamma_c OI_c + gamma_p OI_p) * 100 * S^2 * 0.01
    DEX_K    = (delta_c OI_c + delta_p OI_p) * 100 * S
    maxpain  = argmin_K [ sum_c OI_c max(K - K_c, 0) + sum_p OI_p max(K_p - K, 0) ]
    EM       = S * s_atm * sqrt(T)      (front expiry, 1 sigma)

CONVENZIONI, DETTE ESPLICITAMENTE
---------------------------------
1. netGEX usa la convenzione dealer long call / short put. E' un'assunzione
   statistica sul flusso retail, non un dato di posizionamento.
2. DEX qui e' il delta netto del BBRO APERTO (call positive, put negative), non
   il delta del dealer. Ricondurlo all'inventario dei dealer richiede la stessa
   ipotesi non verificabile del punto 1, quindi lo lascio esplicito invece di
   nasconderlo dietro un segno.
3. absGEX non ha convenzione di segno: e' gamma lorda, l'unica delle tre che
   non dipende da un'ipotesi di posizionamento. E' anche la piu' robusta.
4. L'OI e' T+1. Il volume di sessione (VC/VP) e' l'unico strato che guarda a
   oggi invece che a ieri.

USO
    pip install yfinance numpy pandas scipy
    python tools/gex_full_string.py --days 21 > oggi.txt
"""

from __future__ import annotations

import argparse
import datetime as dt
import sys

import numpy as np
import pandas as pd

try:
    from scipy.stats import norm
    _pdf, _cdf = norm.pdf, norm.cdf
except ImportError:
    def _pdf(x):
        return np.exp(-0.5 * np.asarray(x, float) ** 2) / np.sqrt(2 * np.pi)

    def _cdf(x):                                    # Abramowitz-Stegun 7.1.26
        x = np.asarray(x, float)
        t = 1.0 / (1.0 + 0.2316419 * np.abs(x))
        poly = t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 +
               t * (-1.821255978 + t * 1.330274429))))
        n = 1.0 - _pdf(x) * poly
        return np.where(x >= 0, n, 1.0 - n)

MULT = 100.0


def _d1(S, K, T, r, q, s):
    return (np.log(S / K) + (r - q + 0.5 * s ** 2) * T) / (s * np.sqrt(T))


def greeks(S, K, T, r, q, s):
    """Gamma e delta BSM, vettoriali. Zero dove gli input sono degeneri."""
    K, T, s = map(lambda a: np.asarray(a, float), (K, T, s))
    ok = (T > 0) & (s > 0) & (K > 0) & np.isfinite(s)
    g = np.zeros_like(K)
    d = np.zeros_like(K)
    if ok.any():
        dd = _d1(S, K[ok], T[ok], r, q, s[ok])
        disc = np.exp(-q * T[ok])
        g[ok] = disc * _pdf(dd) / (S * s[ok] * np.sqrt(T[ok]))
        d[ok] = disc * _cdf(dd)                     # delta call; put = d - disc
    return g, d


def load(ticker, max_days, min_oi, r, q):
    import yfinance as yf

    tk = yf.Ticker(ticker)
    h = tk.history(period="5d")
    if h.empty:
        raise RuntimeError(f"nessun prezzo per {ticker}")
    spot = float(h["Close"].iloc[-1])
    today = dt.date.today()
    exps = [e for e in tk.options if 0 <= (dt.date.fromisoformat(e) - today).days <= max_days]
    if not exps:
        raise RuntimeError(f"nessuna scadenza entro {max_days}g per {ticker}")

    rows, atm_iv, atm_T = [], None, None
    for exp in exps:
        try:
            ch = tk.option_chain(exp)
        except Exception as exc:
            print(f"[warn] {ticker} {exp}: {exc}", file=sys.stderr)
            continue
        T = max((dt.date.fromisoformat(exp) - today).days, 0) / 365.0
        for side, df in (("C", ch.calls), ("P", ch.puts)):
            if df is None or df.empty:
                continue
            cols = {"strike": "strike", "openInterest": "oi",
                    "impliedVolatility": "iv", "volume": "vol"}
            d = df[[c for c in cols if c in df.columns]].rename(columns=cols).copy()
            for c in ("oi", "iv", "vol"):
                d[c] = pd.to_numeric(d.get(c), errors="coerce").fillna(0.0)
            d = d[(d["oi"] >= min_oi) & (d["iv"] > 0)]
            if d.empty:
                continue
            d["T"], d["side"] = T, side
            rows.append(d)
            # IV ATM della prima scadenza: base dell'expected move
            if atm_iv is None and side == "C" and T > 0:
                near = d.iloc[(d["strike"] - spot).abs().argsort()[:1]]
                if not near.empty:
                    atm_iv, atm_T = float(near["iv"].iloc[0]), T

    if not rows:
        raise RuntimeError("catena vuota dopo i filtri")

    ch = pd.concat(rows, ignore_index=True)
    g, dc = greeks(spot, ch["strike"].to_numpy(), ch["T"].to_numpy(), r, q, ch["iv"].to_numpy())
    is_c = (ch["side"] == "C").to_numpy()
    disc = np.exp(-q * ch["T"].to_numpy())
    delta = np.where(is_c, dc, dc - disc)           # put delta = N(d1) - 1, scontato

    dollar_gamma = g * ch["oi"].to_numpy() * MULT * spot ** 2 * 0.01
    ch["net_gex"] = np.where(is_c, dollar_gamma, -dollar_gamma)
    ch["abs_gex"] = dollar_gamma                    # gamma lorda: nessuna ipotesi di segno
    ch["dex"] = delta * ch["oi"].to_numpy() * MULT * spot
    ch["oi_c"] = np.where(is_c, ch["oi"], 0.0)
    ch["oi_p"] = np.where(~is_c, ch["oi"], 0.0)
    ch["vol_c"] = np.where(is_c, ch["vol"], 0.0)
    ch["vol_p"] = np.where(~is_c, ch["vol"], 0.0)
    return spot, ch, len(exps), atm_iv, atm_T


def zero_gamma(k, cum, spot):
    """Attraversamento dello zero del GEX cumulato piu' vicino allo spot."""
    best = None
    for i in range(1, len(k)):
        if cum[i - 1] * cum[i] < 0:
            w = cum[i - 1] / (cum[i - 1] - cum[i])
            x = k[i - 1] + w * (k[i] - k[i - 1])
            if best is None or abs(x - spot) < abs(best - spot):
                best = float(x)
    return best


def max_pain(prof):
    """Strike che minimizza il valore intrinseco totale alla scadenza."""
    k = prof["strike"].to_numpy()
    oc, op = prof["oi_c"].to_numpy(), prof["oi_p"].to_numpy()
    pain = [(oc * np.maximum(x - k, 0)).sum() + (op * np.maximum(k - x, 0)).sum() for x in k]
    return float(k[int(np.argmin(pain))])


def top(prof, col, n, ascending=False):
    d = prof[prof[col] != 0]
    if d.empty:
        return []
    d = d.nsmallest(n, col) if ascending else d.nlargest(n, col)
    return list(zip(d["strike"].tolist(), d[col].tolist()))


def main() -> None:
    ap = argparse.ArgumentParser(description="stringa dati completa per GEX_Confluence_v2_NQ.pine")
    ap.add_argument("--tickers", default="^NDX,QQQ")
    ap.add_argument("--days", type=int, default=21)
    ap.add_argument("--min-oi", type=int, default=50)
    ap.add_argument("--bin", type=float, default=25.0, help="griglia strike in punti NDX")
    ap.add_argument("--range-pct", type=float, default=6.0)
    ap.add_argument("--walls", type=int, default=8, help="muri CW/PW per lato")
    ap.add_argument("--secondary", type=int, default=3, help="livelli per famiglia secondaria")
    ap.add_argument("--rate", type=float, default=0.04)
    ap.add_argument("--div", type=float, default=0.006)
    args = ap.parse_args()

    import yfinance as yf

    # yfinance solleva invece di restituire vuoto quando la rete e' bloccata:
    # senza questo si esce con uno stack trace invece che con un messaggio.
    def _hist(sym):
        try:
            return yf.Ticker(sym).history(period="5d")
        except Exception as exc:
            print(f"[warn] {sym}: {exc}", file=sys.stderr)
            return pd.DataFrame()

    ndx = _hist("^NDX")
    nq = _hist("NQ=F")
    if ndx.empty:
        sys.exit("[errore] impossibile leggere ^NDX (rete, proxy o rate limit di Yahoo)")
    ndx_spot = float(ndx["Close"].iloc[-1])
    # basis NQ-NDX al momento dello snapshot: l'indicatore lo ricalcola live e
    # corregge il drift, ma serve un punto di partenza onesto.
    basis = float(nq["Close"].iloc[-1]) - ndx_spot if not nq.empty else 0.0

    agg, atm_iv, atm_T, n_exp = [], None, None, 0
    qqq_spot = None
    for t in [x.strip() for x in args.tickers.split(",") if x.strip()]:
        try:
            sp, ch, ne, iv, tt = load(t, args.days, args.min_oi, args.rate, args.div)
        except Exception as exc:
            print(f"[warn] {t} scartato: {exc}", file=sys.stderr)
            continue
        ratio = ndx_spot / sp                       # tutto in punti NDX
        if t.upper() == "QQQ":
            qqq_spot = sp
        ch = ch.copy()
        ch["strike"] = ch["strike"] * ratio
        agg.append(ch)
        n_exp += ne
        if atm_iv is None and iv is not None:
            atm_iv, atm_T = iv, tt

    if not agg:
        sys.exit("[errore] nessuna catena utilizzabile")

    ch = pd.concat(agg, ignore_index=True)
    ch["strike"] = (ch["strike"] / args.bin).round() * args.bin
    prof = ch.groupby("strike", as_index=False)[
        ["net_gex", "abs_gex", "dex", "oi_c", "oi_p", "vol_c", "vol_p"]].sum().sort_values("strike")
    prof["oi_tot"] = prof["oi_c"] + prof["oi_p"]

    spot = ndx_spot
    k = prof["strike"].to_numpy()
    zg = zero_gamma(k, np.cumsum(prof["net_gex"].to_numpy()), spot)
    mp = max_pain(prof)
    em = spot * atm_iv * np.sqrt(atm_T) if atm_iv and atm_T else None

    def nq_(x):                                      # punti NDX -> spazio NQ
        return x + basis

    lo, hi = spot * (1 - args.range_pct / 100), spot * (1 + args.range_pct / 100)
    view = prof[(prof["strike"] >= lo) & (prof["strike"] <= hi)]

    L = []

    def add(strike, code, label, tip, mag=0.0):
        L.append(f"{nq_(strike):.0f},{code},{label},{tip},{mag:.1f}")

    if zg:
        add(zg, "ZG", "ZERO GAMMA", "Zero Gamma~Pivot di regime~Sopra: vol compressa. Sotto: vol espansa")
    add(mp, "MP", "MAX PAIN", "Max Pain~Strike che minimizza il valore intrinseco totale")
    if em and zg:
        add(spot + em, "EH", "EM HIGH", f"Expected Move +1s~{em:.0f} pt")
        add(spot - em, "EL", "EM LOW", f"Expected Move -1s~{em:.0f} pt")
        add(zg + 0.25 * em, "VH", "VOL HIGH", "Vol Band~ZG + 25% EM")
        add(zg - 0.25 * em, "VL", "VOL LOW", "Vol Band~ZG - 25% EM")

    for s, v in top(view, "net_gex", args.walls):
        if v > 0:
            add(s, "CW", "Call Wall", f"Net GEX +{v/1e6:.1f}M~Da spot: {(s-spot)/spot*100:+.2f}%", v / 1e6)
    for s, v in top(view, "net_gex", args.walls, ascending=True):
        if v < 0:
            add(s, "PW", "Put Wall", f"Net GEX {v/1e6:.1f}M~Da spot: {(s-spot)/spot*100:+.2f}%", abs(v) / 1e6)

    # Abs GEX: gamma lorda call+put. Cattura gli strike dove il netto si cancella
    # ma l'hedging e' massimo -- invisibili a qualunque mappa net-only.
    for i, (s, v) in enumerate(top(view, "abs_gex", args.secondary), 1):
        add(s, "AG", f"AbsGEX {i}", f"Gamma lorda call+put {v/1e6:.1f}M~Nessuna ipotesi di segno~Hedging intenso anche se il netto si cancella", v / 1e6)
    for i, (s, v) in enumerate(top(view, "dex", args.secondary), 1):
        add(s, "DP", f"DEX+ {i}", f"Net delta exposure +{v/1e9:.2f}B~Delta del book aperto, non del dealer", abs(v) / 1e9)
    for i, (s, v) in enumerate(top(view, "dex", args.secondary, ascending=True), 1):
        add(s, "DN", f"DEX- {i}", f"Net delta exposure {v/1e9:.2f}B~Delta del book aperto, non del dealer", abs(v) / 1e9)
    for i, (s, v) in enumerate(top(view, "oi_c", args.secondary), 1):
        add(s, "OC", f"OI call {i}", f"Open interest call {v:,.0f}~Capitale immobilizzato, non pressione di hedging", v / 1e3)
    for i, (s, v) in enumerate(top(view, "oi_p", args.secondary), 1):
        add(s, "OP", f"OI put {i}", f"Open interest put {v:,.0f}~Capitale immobilizzato, non pressione di hedging", v / 1e3)
    for s, v in top(view, "oi_tot", 1):
        add(s, "OA", "OI peak", f"Open interest totale {v:,.0f}", v / 1e3)
    # Volume: unico strato che guarda a oggi invece che all'OI di ieri.
    for i, (s, v) in enumerate(top(view, "vol_c", args.secondary), 1):
        add(s, "VC", f"Vol call {i}", f"Volume di sessione {v:,.0f}~Flusso di oggi, non inventario di ieri", v / 1e3)
    for i, (s, v) in enumerate(top(view, "vol_p", args.secondary), 1):
        add(s, "VP", f"Vol put {i}", f"Volume di sessione {v:,.0f}~Flusso di oggi, non inventario di ieri", v / 1e3)

    mx = prof["net_gex"].abs().max()
    P = [f"{nq_(r.strike):.0f},{r.net_gex/mx*10:.1f},{1 if r.net_gex >= 0 else -1}"
         for r in prof.itertuples() if mx > 0 and abs(r.net_gex) / mx * 10 >= 0.05]

    ratio_txt = f"{ndx_spot/qqq_spot:.3f}" if qqq_spot else "41.000"
    print(f"# generato {dt.datetime.now():%Y-%m-%d %H:%M}  |  spot NDX {spot:,.0f}  |  basis {basis:+.1f}"
          f"  |  {n_exp} scadenze <= {args.days}g  |  ZG {nq_(zg):,.0f}" if zg else "# (zero gamma non trovato)",
          file=sys.stderr)
    print(f"# incolla la riga sotto in 'Live GEX Override'; imposta Data/ora del paste a "
          f"{dt.datetime.now():%Y-%m-%d %H:%M}", file=sys.stderr)
    print(f"S:{basis:.2f}|R:{ratio_txt}|L:" + ";".join(L) + "|P:" + ";".join(P))


if __name__ == "__main__":
    main()
