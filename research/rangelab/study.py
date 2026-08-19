"""
Analisi: score composito, expectancy condizionata, selezione e validazione.

Tre principi non negoziabili implementati qui:
  1. Normalizzazioni causali (expanding shiftato): nessuna feature conosce
     la propria distribuzione futura.
  2. Un trade al giorno: gli eventi dello stesso giorno sono correlati, e
     contarli come osservazioni indipendenti gonfia lo Sharpe.
  3. Ogni risultato passa da un test di permutazione: se la selezione non
     batte una selezione casuale della stessa numerosita', non e' un edge.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from scipy import stats

# componenti dello score di qualita' della rottura (pesi uguali)
BQS_FEATURES = ["compression", "poc_centrality", "er", "expansion", "vol_z"]

# tutte le feature su cui misurare l'expectancy condizionata
STUDY_FEATURES = BQS_FEATURES + [
    "entropy", "body_ratio", "width_atr", "attempt",
    "minutes_after_range", "cci", "cci_agree", "ama_agree",
]


# --------------------------------------------------------------------------
# Score composito
# --------------------------------------------------------------------------
def causal_z(s: pd.Series, min_periods: int = 100) -> pd.Series:
    """Z-score che usa solo le osservazioni PRECEDENTI (expanding + shift)."""
    prev = s.shift(1)
    mu = prev.expanding(min_periods=min_periods).mean()
    sd = prev.expanding(min_periods=min_periods).std()
    return (s - mu) / sd.replace(0.0, np.nan)


def add_bqs(ev: pd.DataFrame, features=BQS_FEATURES,
            min_periods: int = 100) -> pd.DataFrame:
    """Breakout Quality Score: media dei componenti z-scorati, pesi UGUALI.

    Pesi uguali e non ottimizzati: su poche migliaia di osservazioni l'1/N
    batte quasi sempre i pesi stimati fuori campione. I pesi si ottimizzano
    solo dopo aver dimostrato che l'equipesato ha gia' un edge.
    """
    ev = ev.copy()
    cols = []
    for f in features:
        if f not in ev.columns:
            continue
        z = causal_z(ev[f], min_periods)
        ev[f"z_{f}"] = z
        cols.append(f"z_{f}")
    ev["bqs"] = ev[cols].mean(axis=1, skipna=True) if cols else np.nan
    ev["bqs_n"] = ev[cols].notna().sum(axis=1) if cols else 0
    return ev


# --------------------------------------------------------------------------
# Expectancy condizionata
# --------------------------------------------------------------------------
def quantile_table(ev: pd.DataFrame, feature: str, target: str = "r_net",
                   q: int = 5) -> pd.DataFrame | None:
    """Media del target per quantile della feature, con test di monotonicita'.

    Si cerca MONOTONICITA', non il quantile migliore: una feature che 'funziona'
    solo in un bucket e altrove e' piatta e' quasi sempre rumore mascherato.
    """
    d = ev[[feature, target]].dropna()
    if len(d) < q * 20 or d[feature].nunique() < q:
        return None
    try:
        d = d.assign(bucket=pd.qcut(d[feature], q, labels=False, duplicates="drop"))
    except ValueError:
        return None

    g = d.groupby("bucket")[target]
    tab = pd.DataFrame({
        "n": g.size(),
        "mean_r": g.mean(),
        "median_r": g.median(),
        "hit": d.groupby("bucket")[target].apply(lambda s: (s > 0).mean()),
        "lo": d.groupby("bucket")[feature].min(),
        "hi": d.groupby("bucket")[feature].max(),
    })
    # Spearman sui soli q punti dei quantili: indicativo ma DEBOLE.
    # Con q=5 un rho di 0.9 da' gia' p<0.05 per puro caso: non basta.
    rho, p = stats.spearmanr(tab.index.to_numpy(), tab["mean_r"].to_numpy())
    # Spearman sulle osservazioni grezze: e' questo il test con potenza reale.
    rho_raw, p_raw = stats.spearmanr(d[feature].to_numpy(), d[target].to_numpy())
    tab.attrs.update(spearman_rho=float(rho), spearman_p=float(p),
                     rho_raw=float(rho_raw), p_raw=float(p_raw), feature=feature)
    return tab


def scan_features(ev: pd.DataFrame, features=STUDY_FEATURES,
                  target: str = "r_net", q: int = 5) -> pd.DataFrame:
    """Classifica le feature per monotonicita' dell'expectancy condizionata."""
    rows = []
    for f in features:
        t = quantile_table(ev, f, target, q)
        if t is None:
            continue
        rows.append({
            "feature": f,
            "rho_q": t.attrs["spearman_rho"],
            "rho_raw": t.attrs["rho_raw"],
            "p_raw": t.attrs["p_raw"],
            "r_top": t["mean_r"].iloc[-1],
            "r_bot": t["mean_r"].iloc[0],
            "spread": t["mean_r"].iloc[-1] - t["mean_r"].iloc[0],
            "n": int(t["n"].sum()),
        })
    if not rows:
        return pd.DataFrame()
    out = pd.DataFrame(rows).sort_values("p_raw")

    # Benjamini-Hochberg: testando 11 feature, una "significativa al 5%" e'
    # attesa per puro caso. Senza correzione si promuove rumore.
    m = len(out)
    ranks = np.arange(1, m + 1)
    out["p_bh"] = np.minimum.accumulate(
        (out["p_raw"].to_numpy() * m / ranks)[::-1])[::-1].clip(0, 1)
    out["significativa"] = np.where(out["p_bh"] < 0.05, "si", "-")
    return out.sort_values("rho_raw", key=abs, ascending=False)


# --------------------------------------------------------------------------
# Selezione: un solo trade al giorno
# --------------------------------------------------------------------------
def select_one_per_day(ev: pd.DataFrame, policy: str = "first_ok",
                       bqs_quantile: float = 0.67,
                       min_history: int = 200) -> pd.DataFrame:
    """Riduce gli eventi a al massimo uno per giornata.

    policy:
      first     - la prima rottura del giorno. Baseline senza selezione.

      first_ok  - la prima rottura che supera una soglia BQS CAUSALE: il
                  quantile calcolato sui soli BQS gia' osservati prima di
                  quell'evento. E' l'unica policy eseguibile in tempo reale,
                  ed e' quella su cui vanno letti i risultati.

      best_bqs  - la rottura con lo score piu' alto della giornata.
                  *** NON OPERABILE: guarda avanti. ***
                  Per sapere quale sia la migliore del giorno bisogna
                  attendere la fine della giornata e poi tornare indietro a
                  entrare. Serve solo come limite superiore teorico: se
                  nemmeno questa batte il caso, l'idea e' morta in partenza.
    """
    d = ev.dropna(subset=["r_net"]).sort_values("dt").copy()
    if d.empty:
        return d

    if policy == "first":
        idx = d.groupby("date")["dt"].idxmin()
        return d.loc[idx].sort_values("dt")

    if policy == "first_ok":
        thr = d["bqs"].shift(1).expanding(min_periods=min_history).quantile(bqs_quantile)
        d["bqs_threshold"] = thr
        ok = d[d["bqs"] >= thr]
        if ok.empty:
            return ok
        idx = ok.groupby("date")["dt"].idxmin()
        return ok.loc[idx].sort_values("dt")

    if policy == "best_bqs":
        scored = d.dropna(subset=["bqs"])
        idx = list(scored.groupby("date")["bqs"].idxmax())
        rest = d[~d["date"].isin(scored["date"].unique())]
        if not rest.empty:
            idx += list(rest.groupby("date")["dt"].idxmin())
        return d.loc[idx].sort_values("dt")

    raise ValueError(f"policy sconosciuta: {policy}")


# --------------------------------------------------------------------------
# Metriche
# --------------------------------------------------------------------------
def summary(ev: pd.DataFrame, target: str = "r_net") -> dict:
    r = ev[target].dropna()
    if len(r) < 2:
        return {"n": len(r)}

    daily = ev.groupby("date")[target].sum()
    equity = daily.cumsum()
    dd = (equity.cummax() - equity).max()

    wins, losses = r[r > 0], r[r < 0]
    pf = wins.sum() / abs(losses.sum()) if len(losses) and losses.sum() != 0 else np.inf
    t = r.mean() / (r.std(ddof=1) / np.sqrt(len(r))) if r.std(ddof=1) > 0 else np.nan
    sharpe = (daily.mean() / daily.std(ddof=1) * np.sqrt(252)
              if daily.std(ddof=1) > 0 else np.nan)

    return {
        "n": int(len(r)),
        "hit_rate": float((r > 0).mean()),
        "mean_r": float(r.mean()),
        "median_r": float(r.median()),
        "total_r": float(r.sum()),
        "t_stat": float(t),
        "profit_factor": float(pf),
        "sharpe_daily_ann": float(sharpe),
        "max_dd_r": float(dd),
        "tp_rate": float((ev["label"] == 1).mean()),
        "sl_rate": float((ev["label"] == -1).mean()),
        "timeout_rate": float((ev["label"] == 0).mean()),
    }


# --------------------------------------------------------------------------
# Validazione
# --------------------------------------------------------------------------
def permutation_test(pool: pd.DataFrame, selected: pd.DataFrame,
                     target: str = "r_net", n_iter: int = 2000,
                     seed: int = 0) -> dict:
    """La selezione batte una scelta CASUALE della stessa numerosita'?

    Test diretto sulla domanda che conta. Se il p-value non e' piccolo, il
    filtro non sta selezionando: sta solo riducendo il campione.
    """
    d = pool.dropna(subset=[target])
    k = len(selected[target].dropna())
    if k < 5 or d["date"].nunique() <= k:
        return {"p_value": np.nan, "n_iter": 0}

    # Null CORRETTO: k giorni a caso, un evento a caso dentro ciascuno.
    # Pescare k eventi a caso dal calderone sarebbe un null SBAGLIATO: la regola
    # reale pesa ugualmente ogni giornata, mentre il calderone sovrappesa i
    # giorni con molte rotture (le giornate confuse, quelle che perdono). Il
    # confronto risulterebbe favorevole per pura contabilita', non per merito.
    rng = np.random.default_rng(seed)
    by_day = [g[target].to_numpy() for _, g in d.groupby("date")]
    n_days = len(by_day)
    obs = float(selected[target].dropna().mean())

    draws = np.empty(n_iter)
    for i in range(n_iter):
        days = rng.choice(n_days, size=k, replace=False)
        draws[i] = np.mean([by_day[j][rng.integers(len(by_day[j]))] for j in days])
    return {
        "observed_mean_r": obs,
        "random_mean_r": float(draws.mean()),
        "random_std": float(draws.std(ddof=1)),
        "p_value": float((draws >= obs).mean()),
        "z_vs_random": float((obs - draws.mean()) / draws.std(ddof=1)) if draws.std(ddof=1) > 0 else np.nan,
        "n_iter": n_iter,
    }


def walk_forward(ev: pd.DataFrame, train_years: int = 3, quantile: float = 0.67,
                 target: str = "r_net") -> pd.DataFrame:
    """Walk-forward annuale sulla regola OPERABILE (prima rottura sopra soglia).

    La soglia BQS si stima solo sugli anni di train; l'anno di test la subisce.
    Il confronto e' contro la baseline 'prima rottura del giorno, sempre',
    misurata sullo stesso anno: e' l'unico paragone che risponda alla domanda
    "il filtro aggiunge qualcosa?".

    Un backtest unico sui 6 anni non direbbe nulla: la soglia sarebbe scelta
    conoscendo gia' tutto il campione.
    """
    d = ev.dropna(subset=[target, "bqs"]).sort_values("dt").copy()
    if d.empty:
        return pd.DataFrame()
    d["year"] = pd.DatetimeIndex(d["dt"]).year
    years = sorted(d["year"].unique())

    rows = []
    for i in range(train_years, len(years)):
        tr = d[d["year"].isin(years[max(0, i - train_years):i])]
        te = d[d["year"] == years[i]]
        if len(tr) < 100 or te.empty:
            continue
        thr = float(tr["bqs"].quantile(quantile))

        ok = te[te["bqs"] >= thr]
        sel = ok.loc[ok.groupby("date")["dt"].idxmin()] if not ok.empty else ok
        base = te.loc[te.groupby("date")["dt"].idxmin()]

        rows.append({
            "test_year": years[i], "threshold": thr,
            "n_selected": len(sel), "n_days_base": len(base),
            "mean_r_selected": float(sel[target].mean()) if len(sel) else np.nan,
            "mean_r_baseline": float(base[target].mean()),
            "edge": float(sel[target].mean() - base[target].mean()) if len(sel) else np.nan,
        })
    return pd.DataFrame(rows)


# --------------------------------------------------------------------------
# Score stimato sul train (l'unico modo onesto di combinare le feature)
# --------------------------------------------------------------------------
def fit_score(train: pd.DataFrame, candidates=STUDY_FEATURES,
              target: str = "r_net", p_max: float = 0.05,
              rho_min: float = 0.03) -> dict:
    """Seleziona le feature sopravvissute sul TRAIN e ne fissa media/dev.std.

    Sopravvive una feature solo se la correlazione di rango con l'esito e'
    significativa DOPO la correzione per test multipli e supera una soglia
    minima di ampiezza: la significativita' da sola, su migliaia di eventi,
    promuove anche relazioni irrilevanti.

    Il segno del peso viene dal segno di rho: e' il dato a decidere se una
    feature vada letta in positivo o in negativo, non l'intuizione.
    """
    scan = scan_features(train, candidates, target)
    if scan.empty:
        return {"weights": {}, "mu": {}, "sd": {}}

    keep = scan[(scan["p_bh"] < p_max) & (scan["rho_raw"].abs() >= rho_min)]
    weights = {r.feature: float(np.sign(r.rho_raw)) for r in keep.itertuples()}
    mu = {f: float(train[f].mean()) for f in weights}
    sd = {f: float(train[f].std(ddof=1)) for f in weights}
    return {"weights": weights, "mu": mu, "sd": sd,
            "scan": scan[["feature", "rho_raw", "p_bh"]]}


def apply_score(ev: pd.DataFrame, model: dict) -> pd.Series:
    """Applica al test uno score stimato sul train. Media dei z-score orientati."""
    w = model.get("weights", {})
    if not w:
        return pd.Series(np.nan, index=ev.index)
    parts = []
    for f, sign in w.items():
        s = model["sd"].get(f, 0.0)
        if not s or not np.isfinite(s):
            continue
        parts.append(sign * (ev[f] - model["mu"][f]) / s)
    if not parts:
        return pd.Series(np.nan, index=ev.index)
    return pd.concat(parts, axis=1).mean(axis=1, skipna=True)


def walk_forward_fitted(ev: pd.DataFrame, train_years: int = 3,
                        quantile: float = 0.67, target: str = "r_net",
                        p_max: float = 0.05, rho_min: float = 0.03) -> pd.DataFrame:
    """Walk-forward con lo score RICOSTRUITO a ogni fold sui soli anni di train.

    E' la versione onesta della pipeline completa: selezione delle feature,
    stima di media/dev.std e taratura della soglia avvengono tutte dentro il
    train. L'anno di test non contribuisce a nessuna scelta.

    Se qui l'edge sparisce mentre nell'analisi su tutto il campione c'era,
    la risposta e' semplice: quell'edge era il campione, non il mercato.
    """
    d = ev.dropna(subset=[target]).sort_values("dt").copy()
    if d.empty:
        return pd.DataFrame()
    d["year"] = pd.DatetimeIndex(d["dt"]).year
    years = sorted(d["year"].unique())

    rows = []
    for i in range(train_years, len(years)):
        tr = d[d["year"].isin(years[max(0, i - train_years):i])]
        te = d[d["year"] == years[i]].copy()
        if len(tr) < 200 or te.empty:
            continue

        model = fit_score(tr, target=target, p_max=p_max, rho_min=rho_min)
        if not model["weights"]:
            rows.append({"test_year": years[i], "n_features": 0, "features": "-",
                         "n_selected": 0, "mean_r_selected": np.nan,
                         "mean_r_baseline": float(te.loc[te.groupby("date")["dt"].idxmin(), target].mean()),
                         "edge": np.nan})
            continue

        thr = float(apply_score(tr, model).quantile(quantile))
        te["score"] = apply_score(te, model)
        ok = te[te["score"] >= thr]
        sel = ok.loc[ok.groupby("date")["dt"].idxmin()] if not ok.empty else ok
        base = te.loc[te.groupby("date")["dt"].idxmin()]

        rows.append({
            "test_year": years[i],
            "n_features": len(model["weights"]),
            "features": ",".join(sorted(model["weights"])),
            "n_selected": len(sel), "n_days_base": len(base),
            "mean_r_selected": float(sel[target].mean()) if len(sel) else np.nan,
            "mean_r_baseline": float(base[target].mean()),
            "edge": float(sel[target].mean() - base[target].mean()) if len(sel) else np.nan,
        })
    return pd.DataFrame(rows)
