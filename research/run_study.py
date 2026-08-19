#!/usr/bin/env python3
"""
Event study su rotture di un range di accumulazione a orario fisso.

Esempi
------
Collaudo su rumore puro (l'edge DEVE risultare assente):
    python run_study.py --synthetic --edge 0.0

Collaudo con edge iniettato (lo studio DEVE ritrovarlo):
    python run_study.py --synthetic --edge 0.35

Dati reali (export MT5 a 1 minuto, ora server del broker):
    python run_study.py --csv NQ_M1.csv --data-tz "+03:00" \
        --range-start 08:00 --range-end 10:00 --session-end 22:00
"""
from __future__ import annotations

import argparse
import sys

import numpy as np
import pandas as pd

from rangelab import data as D
from rangelab import features as F
from rangelab import labeling as L
from rangelab import study as S

pd.set_option("display.width", 130)
pd.set_option("display.max_columns", 30)
pd.set_option("display.float_format", lambda v: f"{v:>9.4f}")


def header(t: str) -> None:
    print(f"\n{'=' * 78}\n{t}\n{'=' * 78}")


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    src = p.add_argument_group("sorgente dati")
    src.add_argument("--csv", help="CSV OHLCV a 1 minuto")
    src.add_argument("--synthetic", action="store_true", help="usa dati sintetici")
    src.add_argument("--years", type=int, default=6)
    src.add_argument("--edge", type=float, default=0.0,
                     help="ampiezza edge iniettato nei dati sintetici (0 = rumore puro)")
    src.add_argument("--seed", type=int, default=7)
    src.add_argument("--data-tz", default="UTC",
                     help="fuso dei dati: nome IANA o offset fisso, es. '+03:00'")
    src.add_argument("--analysis-tz", default="Europe/Rome")

    win = p.add_argument_group("finestra")
    win.add_argument("--range-start", default="08:00", help="inizio accumulazione (fuso di analisi)")
    win.add_argument("--range-end", default="10:00", help="fine accumulazione = inizio caccia alle rotture")
    win.add_argument("--session-end", default="22:00", help="orario di chiusura forzata")
    win.add_argument("--timeframe", default="5min", help="timeframe di analisi (1min, 5min, 15min)")

    ev = p.add_argument_group("eventi")
    ev.add_argument("--buffer-frac", type=float, default=0.05,
                    help="soglia di rottura come frazione dell'ampiezza del range")
    ev.add_argument("--reentry-bars", type=int, default=3)
    ev.add_argument("--cci-period", type=int, default=20)

    bar = p.add_argument_group("barriere e costi")
    bar.add_argument("--tp-mult", type=float, default=1.0, help="TP in multipli di W")
    bar.add_argument("--sl-mult", type=float, default=0.5, help="SL in multipli di W")
    bar.add_argument("--max-minutes", type=int, default=None)
    bar.add_argument("--tick", type=float, default=0.25)
    bar.add_argument("--cost-ticks", type=float, default=3.0,
                     help="costo round-trip in tick (spread + commissione)")

    sel = p.add_argument_group("selezione")
    sel.add_argument("--bqs-quantile", type=float, default=0.67,
                     help="quantile BQS sopra il quale si opera")
    sel.add_argument("--train-years", type=int, default=3)
    sel.add_argument("--n-iter", type=int, default=2000)
    sel.add_argument("--out", default=None, help="salva gli eventi etichettati in CSV")

    a = p.parse_args(argv)
    if not a.csv and not a.synthetic:
        p.error("serve --csv oppure --synthetic")

    # ---------------- dati ----------------
    header("1. DATI")
    if a.synthetic:
        cfg = D.SynthConfig(years=a.years, tz=a.analysis_tz, edge=a.edge,
                            edge_window=a.range_end, seed=a.seed)
        df = D.synthetic(cfg)
        print(f"Sintetici | edge iniettato = {a.edge}"
              + ("  (RUMORE PURO: l'edge deve risultare assente)" if a.edge == 0 else ""))
    else:
        df = D.load_csv(a.csv, a.data_tz, a.analysis_tz)
        print(f"CSV: {a.csv} | fuso dati {a.data_tz} -> analisi {a.analysis_tz}")

    print(f"Barre 1-min : {len(df):,}   da {df.index[0]}  a {df.index[-1]}")
    df = F.resample(df, a.timeframe)
    print(f"Timeframe   : {a.timeframe} -> {len(df):,} barre")

    # ---------------- range ----------------
    header(f"2. RANGE DI ACCUMULAZIONE  {a.range_start}-{a.range_end} ({a.analysis_tz})")
    ranges = F.build_ranges(df, a.range_start, a.range_end)
    print(f"Giorni con range valido: {len(ranges):,}")
    print(ranges[["width", "compression", "poc_centrality", "entropy"]].describe().T)

    # ---------------- eventi ----------------
    header("3. EVENTI DI ROTTURA (nessun filtro applicato)")
    events = F.extract_breakouts(df, ranges, a.range_end, a.session_end,
                                 buffer_frac=a.buffer_frac,
                                 reentry_bars=a.reentry_bars,
                                 cci_period=a.cci_period)
    if events.empty:
        print("Nessun evento estratto: controlla finestra oraria e fuso.")
        return 1

    per_day = events.groupby("date").size()
    print(f"Eventi totali            : {len(events):,}")
    print(f"Giorni con almeno 1 evento: {len(per_day):,}")
    print(f"Eventi per giorno         : media {per_day.mean():.2f}  "
          f"mediana {per_day.median():.0f}  max {per_day.max()}")
    print("\nDistribuzione tentativi per giornata:")
    print(per_day.value_counts().sort_index().rename("giorni").to_frame().T)
    print(f"\nQuota di rotture che rientrano nel range entro {a.reentry_bars} barre: "
          f"{events['reentered'].mean():.1%}")

    # ---------------- barriere ----------------
    header(f"4. TRIPLE BARRIER  TP={a.tp_mult}W  SL={a.sl_mult}W  costi={a.cost_ticks} tick")
    events = L.triple_barrier(df, events, a.session_end, a.tp_mult, a.sl_mult,
                              a.max_minutes, a.tick, a.cost_ticks)
    events = S.add_bqs(events)
    labelled = events.dropna(subset=["r_net"])
    print(f"Eventi etichettati: {len(labelled):,}")
    print(pd.Series(S.summary(labelled)).to_frame("tutti gli eventi"))

    # ---------------- expectancy condizionata ----------------
    header("5. EXPECTANCY CONDIZIONATA  (si cerca MONOTONICITA', non il bucket migliore)")
    scan = S.scan_features(labelled)
    if scan.empty:
        print("Campione insufficiente per l'analisi a quantili.")
    else:
        print(scan.to_string(index=False))
        print("\nrho_q   = Spearman sui 5 punti dei quintili. Indicativo ma DEBOLE:")
        print("          con 5 punti un rho di 0.9 esce per caso piu' spesso di quanto sembri.")
        print("rho_raw = Spearman su tutte le osservazioni. E' questo il test che conta.")
        print("p_bh    = p-value corretto Benjamini-Hochberg per i test multipli.")
        print("          Senza correzione, testando 11 feature una 'significativa' e' attesa per caso.")
        best = scan.iloc[0]["feature"]
        print(f"\nDettaglio quintili della feature piu' monotona ({best}):")
        print(S.quantile_table(labelled, best).to_string())

    # ---------------- selezione ----------------
    header("6. SELEZIONE  (un solo trade al giorno)")
    baseline = S.select_one_per_day(labelled, "first")
    tradeable = S.select_one_per_day(labelled, "first_ok", a.bqs_quantile)
    upper = S.select_one_per_day(labelled, "best_bqs")

    comp = pd.DataFrame({
        "first (baseline)": pd.Series(S.summary(baseline)),
        f"first_ok BQS>q{a.bqs_quantile:g}": pd.Series(S.summary(tradeable)),
        "best_bqs (NON OPERABILE)": pd.Series(S.summary(upper)),
    })
    print(comp)
    print("\n'first_ok' e' l'unica colonna operabile: la soglia BQS e' calcolata")
    print("sui soli eventi passati e si entra alla PRIMA rottura che la supera.")
    print("'best_bqs' sceglie la rottura migliore del giorno: per saperlo servirebbe")
    print("attendere sera e tornare indietro. E' un limite superiore, non una strategia.")

    # ---------------- validazione ----------------
    header("7. TEST DI PERMUTAZIONE  (batte una scelta casuale, a parita' di giorni?)")
    perm = S.permutation_test(labelled, tradeable, n_iter=a.n_iter, seed=a.seed)
    print(pd.Series(perm).to_frame("first_ok vs casuale"))
    pv = perm.get("p_value", np.nan)
    if np.isnan(pv):
        print("\n=> Campione insufficiente per il test.")
    elif pv < 0.05:
        print(f"\n=> p={pv:.4f}: la selezione batte il caso. Ora deve reggere il walk-forward.")
    else:
        print(f"\n=> p={pv:.4f}: NESSUN edge di selezione.")
        print("   Il filtro riduce il campione, non lo migliora.")

    header(f"8. WALK-FORWARD  (soglia stimata solo sul train, {a.train_years} anni)")
    wf = S.walk_forward(labelled, a.train_years, a.bqs_quantile)
    if wf.empty:
        print("Storico insufficiente per il walk-forward.")
    else:
        print(wf.to_string(index=False))
        pos = int((wf["edge"] > 0).sum())
        print(f"\nAnni con edge positivo fuori campione: {pos}/{len(wf)}  "
              f"| edge medio {wf['edge'].mean():+.4f} R")
        if pos <= len(wf) / 2:
            print("=> Instabile fuori campione: NON promuovere questa configurazione.")

    header(f"9. WALK-FORWARD CON SCORE RISTIMATO  (selezione feature dentro il train)")
    wff = S.walk_forward_fitted(labelled, a.train_years, a.bqs_quantile)
    if wff.empty:
        print("Storico insufficiente.")
    else:
        print(wff.to_string(index=False))
        ok = wff.dropna(subset=["edge"])
        if len(ok):
            pos = int((ok["edge"] > 0).sum())
            print(f"\nAnni con edge positivo: {pos}/{len(ok)}  "
                  f"| edge medio {ok['edge'].mean():+.4f} R")
            print("\nQuesto e' il numero che conta: selezione delle feature, normalizzazione")
            print("e soglia sono tutte stimate dentro il train. Se qui l'edge non c'e',")
            print("non c'e' e basta - qualunque cosa dica l'analisi su tutto il campione.")

    if a.out:
        events.to_csv(a.out, index=False)
        print(f"\nEventi salvati in {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
