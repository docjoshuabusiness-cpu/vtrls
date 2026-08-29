#!/usr/bin/env python3
"""
Meta-labeling per Order Flow Engine v2.

PIPELINE
    Pine (feature vector, colonne x_*)  ->  Esporta dati del grafico (CSV)
    ->  questo script  ->  coefficienti  ->  Pine / MQL5

IDEA
    Il segnale primario NON si stringe. Resta generoso. Un secondo modello
    impara soltanto PRENDERE / SALTARE, addestrato sull'esito a barriere dei
    segnali primari. Separa "dove guardare" da "quando vale la pena", che e'
    esattamente il punto in cui i filtri a soglia falliscono: una soglia si
    muove lungo la stessa distribuzione, un meta-modello usa la combinazione
    di assi che la soglia non vede.

DISCIPLINA STATISTICA (non e' decorazione, senza questo i numeri mentono)
    - Etichette a triple barrier: SL, TP, uscita a tempo. Stessa definizione
      del Pine, ricostruita qui dalle OHLC cosi' vive in un posto solo.
    - I trade si SOVRAPPONGONO nel tempo. Una k-fold normale mette in train
      campioni che condividono barre col test: leakage garantito e AUC gonfiata.
      Qui: purged k-fold con embargo (Lopez de Prado, AFML cap. 7).
    - Pesi di unicita': un trade che condivide 19 barre su 20 con un altro non
      vale come un'osservazione indipendente.
    - Si valuta in EXPECTANCY (R per trade), non in accuracy. Un modello al
      75% di accuracy che scarta i pochi vincitori grossi e' inutile.

USO
    python3 meta_label.py export.csv --mintick 0.25 --cost-ticks 2 \\
        --sl-atr 1.5 --tp-atr 2.5 --max-bars 20
"""

import argparse
import sys

import numpy as np
import pandas as pd

FAMILY = {1: "BuyAbs", -1: "SellAbs", 2: "BearExh", -2: "BullExh",
          3: "BullIni", -3: "BearIni", 4: "BullDiv", -4: "BearDiv"}

FEATURES = ["x_vz", "x_dz", "x_imb", "x_ortho", "x_res", "x_clv", "x_er",
            "x_ext", "x_vwz", "x_cvdz", "x_htf", "x_cusumage", "x_hour",
            "x_score"]


# --------------------------------------------------------------------------
# 1. CARICAMENTO
# --------------------------------------------------------------------------
def load(path):
    df = pd.read_csv(path)
    df.columns = [c.strip() for c in df.columns]
    ren = {}
    for c in df.columns:
        lc = c.lower()
        if lc in ("time", "date", "datetime"):
            ren[c] = "time"
        elif lc in ("open", "high", "low", "close"):
            ren[c] = lc
        elif lc.startswith("volume"):
            ren[c] = "volume"
    df = df.rename(columns=ren)

    missing = {"open", "high", "low", "close"} - set(df.columns)
    if missing:
        sys.exit(f"Colonne OHLC mancanti nel CSV: {sorted(missing)}")
    if "x_sig" not in df.columns:
        sys.exit("Colonna x_sig assente. Attiva 'Modalita' export' nello script "
                 "Pine prima di esportare i dati del grafico.")

    for c in FEATURES:
        if c not in df.columns:
            df[c] = 0.0
    if "x_atr" not in df.columns:
        sys.exit("Colonna x_atr assente: serve per dimensionare le barriere.")

    df = df.reset_index(drop=True)
    return df


# --------------------------------------------------------------------------
# 2. ETICHETTE A TRIPLE BARRIER
# --------------------------------------------------------------------------
def label(df, sl_atr, tp_atr, max_bars, cost_ticks, mintick, use_raw):
    """Per ogni segnale: percorre le barre successive e registra quale barriera
    viene toccata per prima. Se SL e TP cadono nella stessa barra vince lo SL
    (pessimistico: senza dati intrabar non sai l'ordine)."""
    col = "x_sigraw" if use_raw else "x_sig"
    if col not in df.columns:
        col = "x_sig"

    sig = df[col].fillna(0).to_numpy()
    hi, lo, cl = (df[c].to_numpy(float) for c in ("high", "low", "close"))
    atr = df["x_atr"].to_numpy(float)
    n = len(df)

    rows = []
    for i in np.flatnonzero(sig != 0):
        code = int(sig[i])
        d = 1 if code > 0 else -1
        risk = sl_atr * atr[i]
        if not np.isfinite(risk) or risk <= 0:
            continue
        entry = cl[i]
        sl = entry - d * risk
        tp = entry + d * tp_atr * atr[i]
        cost = cost_ticks * mintick / risk

        r, t1 = None, min(i + max_bars, n - 1)
        for j in range(i + 1, t1 + 1):
            hit_sl = lo[j] <= sl if d > 0 else hi[j] >= sl
            hit_tp = hi[j] >= tp if d > 0 else lo[j] <= tp
            if hit_sl:
                r, t1 = -1.0, j
                break
            if hit_tp:
                r, t1 = tp_atr / sl_atr, j
                break
        if r is None:
            r = d * (cl[t1] - entry) / risk
        if t1 <= i:
            continue

        rows.append({"t0": i, "t1": t1, "code": code, "dir": d,
                     "R": r - cost,
                     **{f: float(df[f].iloc[i]) for f in FEATURES}})

    if not rows:
        sys.exit("Nessun segnale trovato nel CSV. Controlla che la finestra "
                 "esportata contenga barre dopo il warm-up.")
    return pd.DataFrame(rows)


def uniqueness(ev, n_bars):
    """Peso = unicita' media. Conta quanti trade sono aperti su ogni barra e
    penalizza chi vive dentro una folla."""
    conc = np.zeros(n_bars + 1)
    for t0, t1 in zip(ev.t0, ev.t1):
        conc[t0:t1 + 1] += 1
    w = np.array([np.mean(1.0 / np.maximum(conc[t0:t1 + 1], 1))
                  for t0, t1 in zip(ev.t0, ev.t1)])
    return w / w.mean()


# --------------------------------------------------------------------------
# 3. REGRESSIONE LOGISTICA (IRLS + ridge, senza dipendenze esterne)
# --------------------------------------------------------------------------
def fit_logit(X, y, w, lam=1.0, iters=40):
    Xb = np.hstack([np.ones((len(X), 1)), X])
    b = np.zeros(Xb.shape[1])
    reg = lam * np.eye(Xb.shape[1])
    reg[0, 0] = 0.0                       # nessuna penalita' sull'intercetta
    for _ in range(iters):
        p = 1.0 / (1.0 + np.exp(-np.clip(Xb @ b, -30, 30)))
        s = w * p * (1 - p)
        H = Xb.T @ (Xb * s[:, None]) + reg
        g = Xb.T @ (w * (y - p)) - reg @ b
        try:
            step = np.linalg.solve(H, g)
        except np.linalg.LinAlgError:
            break
        b += step
        if np.max(np.abs(step)) < 1e-8:
            break
    return b


def predict(b, X):
    Xb = np.hstack([np.ones((len(X), 1)), X])
    return 1.0 / (1.0 + np.exp(-np.clip(Xb @ b, -30, 30)))


def purged_cv(ev, X, y, w, k=5, embargo=0.02, lam=1.0):
    """Per ogni fold: elimina dal train ogni campione il cui intervallo
    [t0,t1] tocca il test, piu' un embargo temporale dopo. Senza questo i
    trade sovrapposti passano informazione dal test al train."""
    n = len(ev)
    idx = np.arange(n)
    folds = np.array_split(idx, k)
    emb = int(n * embargo)
    oof = np.full(n, np.nan)
    for f in folds:
        lo_t, hi_t = ev.t0.iloc[f[0]], ev.t1.iloc[f[-1]]
        overlap = (ev.t1 >= lo_t) & (ev.t0 <= hi_t)
        tr = idx[~overlap.to_numpy()]
        tr = tr[(tr < f[0] - emb) | (tr > f[-1] + emb)]
        if len(tr) < 40 or len(np.unique(y[tr])) < 2:
            continue
        b = fit_logit(X[tr], y[tr], w[tr], lam)
        oof[f] = predict(b, X[f])
    return oof


# --------------------------------------------------------------------------
# 4. REPORT
# --------------------------------------------------------------------------
def breakdown(ev, key, label_fn=str):
    print(f"\n  {'gruppo':<12} {'N':>6} {'muR':>8} {'hit%':>7}")
    for g, sub in ev.groupby(key):
        if len(sub) < 5:
            continue
        print(f"  {label_fn(g):<12} {len(sub):>6} {sub.R.mean():>8.3f} "
              f"{100 * (sub.R > 0).mean():>7.1f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--mintick", type=float, default=0.25, help="NQ/ES: 0.25")
    ap.add_argument("--cost-ticks", type=float, default=2.0)
    ap.add_argument("--sl-atr", type=float, default=1.5)
    ap.add_argument("--tp-atr", type=float, default=2.5)
    ap.add_argument("--max-bars", type=int, default=20)
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--ridge", type=float, default=1.0)
    ap.add_argument("--raw", action="store_true",
                    help="usa i segnali PRIMA del gate di qualita' (consigliato: "
                         "piu' campione, e il modello impara da solo cosa scartare)")
    a = ap.parse_args()

    df = load(a.csv)
    ev = label(df, a.sl_atr, a.tp_atr, a.max_bars, a.cost_ticks, a.mintick, a.raw)

    print("=" * 66)
    print(f"BASE   barre={len(df)}  segnali={len(ev)}  "
          f"muR={ev.R.mean():+.3f}  hit={100 * (ev.R > 0).mean():.1f}%")
    print("=" * 66)
    print("\nPER FAMIGLIA")
    breakdown(ev, "code", lambda c: FAMILY.get(int(c), str(c)))
    print("\nPER FASCIA ORARIA (ora del broker sul grafico)")
    ev = ev.assign(hh=ev.x_hour.astype(int))
    breakdown(ev, "hh", lambda h: f"{int(h):02d}:00")

    X = ev[FEATURES].to_numpy(float)
    X = np.nan_to_num(X, nan=0.0, posinf=0.0, neginf=0.0)
    mu, sd = X.mean(0), np.where(X.std(0) > 1e-9, X.std(0), 1.0)
    Xs = (X - mu) / sd
    y = (ev.R.to_numpy() > 0).astype(float)
    w = uniqueness(ev, len(df))

    if len(ev) < 150:
        print(f"\n!! ATTENZIONE: {len(ev)} segnali. Sotto ~300 il meta-modello "
              "si adatta al rumore. Esporta una finestra piu' lunga.")

    oof = purged_cv(ev, Xs, y, w, a.folds, lam=a.ridge)
    ok = np.isfinite(oof)
    if ok.sum() < 50:
        sys.exit("Campione out-of-sample troppo piccolo dopo il purging.")

    print("\n" + "=" * 66)
    print("META-MODELLO  ·  out-of-sample (purged k-fold + embargo)")
    print("=" * 66)
    print(f"\n  {'soglia':>7} {'N':>6} {'% tenuti':>9} {'muR':>8} {'vs base':>9}")
    base = ev.R[ok].mean()
    best = None
    for th in np.arange(0.30, 0.75, 0.05):
        m = ok & (oof >= th)
        if m.sum() < 20:
            continue
        r = ev.R[m].mean()
        print(f"  {th:>7.2f} {m.sum():>6} {100 * m.sum() / ok.sum():>8.0f}% "
              f"{r:>8.3f} {r - base:>+9.3f}")
        if best is None or r > best[1]:
            best = (th, r, m.sum())

    print(f"\n  base (tutti i segnali): muR={base:+.3f} su N={ok.sum()}")
    if best:
        print(f"  migliore: soglia {best[0]:.2f} -> muR={best[1]:+.3f} su N={best[2]}")
        print("\n  NB: la soglia scelta guardando questa tabella e' essa stessa una\n"
              "  decisione in-sample. Verificala su un periodo che non hai usato qui.")

    b = fit_logit(Xs, y, w, a.ridge)
    print("\n" + "=" * 66)
    print("COEFFICIENTI (su feature standardizzate: |coef| = importanza)")
    print("=" * 66)
    order = np.argsort(-np.abs(b[1:]))
    for i in order:
        print(f"  {FEATURES[i]:<12} {b[i + 1]:+8.4f}   (mu={mu[i]:+.4f} sd={sd[i]:.4f})")
    print(f"  {'intercetta':<12} {b[0]:+8.4f}")

    print("\n" + "-" * 66)
    print("PORTING IN PINE  ·  incolla nello script e usa come gate:")
    print("-" * 66)
    print(f"metaZ = {b[0]:+.4f}")
    for i in order:
        print(f"     + {b[i + 1]:+.4f} * (({FEATURES[i][2:]} - {mu[i]:.6f}) / {sd[i]:.6f})")
    print("metaP = 1.0 / (1.0 + math.exp(-metaZ))")
    print(f"metaOk = metaP >= {best[0] if best else 0.5:.2f}")


if __name__ == "__main__":
    main()
