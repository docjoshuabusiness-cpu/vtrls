#!/usr/bin/env python3
"""Ricalcolo indipendente della classifica dell'analisi delle fasce: legge i trade virtuali (CSV) e la classifica scritta
dall'EA e controlla, per ogni fascia, numero di trade, win %, E[R], profit factor, R totale, punti, drawdown (in R, in ordine di
chiusura), t-stat, trade prima/dopo la data di separazione, flag "in classifica" e ordine della classifica.

uso: slot_rank_check.py <trade.csv> <classifica.csv> [--min-trades N] [--split EPOCH] [--rank-by tstat|er|pf|total]
"""
import argparse, calendar, csv, math, sys, time

ap = argparse.ArgumentParser()
ap.add_argument("trades")
ap.add_argument("rank")
ap.add_argument("--min-trades", type=int, default=30)
ap.add_argument("--split", type=int, default=0)
ap.add_argument("--rank-by", default="tstat")
ns = ap.parse_args()


def ts(x):
    return calendar.timegm(time.strptime(x, "%Y.%m.%d %H:%M"))


rows = list(csv.DictReader(open(ns.trades)))
rank = list(csv.DictReader(open(ns.rank)))
by = {}
for r in rows:
    by.setdefault(int(r["slot"]), []).append(r)
diffs = []


def near(a, b, tol, what):
    if abs(a - b) > tol:
        diffs.append(what)


exp_score = {}
exp_elig = {}
exp_n = {}
for q in rank:
    k = int(q["slot"])
    tr = by.get(k, [])
    Rs = [float(r["R"]) for r in tr]
    n = len(Rs)
    exp_n[k] = n
    if int(q["trades"]) != n:
        diffs.append(f"fascia {k}: trade {q['trades']} atteso {n}")
        continue
    s = sum(Rs)
    mean = s / n if n else 0.0
    gw = sum(x for x in Rs if x > 0)
    gl = sum(-x for x in Rs if x <= 0)
    pf = (99.0 if gw > 0 else 0.0) if gl <= 1e-12 else gw / gl
    wins = sum(1 for x in Rs if x > 0)
    eq = peak = dd = 0.0
    for x in Rs:
        eq += x
        peak = max(peak, eq)
        dd = max(dd, peak - eq)
    if n >= 2:
        s2 = sum(x * x for x in Rs)
        var = (s2 - s * s / n) / (n - 1)
        t = 0.0 if var <= 1e-12 else mean / math.sqrt(var / n)
    else:
        t = 0.0
    near(float(q["win_pct"]), 100.0 * wins / n if n else 0.0, 0.006, f"fascia {k}: win % {q['win_pct']}")
    near(float(q["expectancy_r"]), mean, 6e-5, f"fascia {k}: E[R] {q['expectancy_r']} atteso {mean:.4f}")
    near(float(q["profit_factor"]), pf, 2e-3, f"fascia {k}: PF {q['profit_factor']} atteso {pf:.3f}")
    near(float(q["total_r"]), s, 2e-3, f"fascia {k}: R totale {q['total_r']} atteso {s:.3f}")
    near(float(q["total_pts"]), sum(float(r["pts"]) for r in tr), 0.06 + 0.05 * n, f"fascia {k}: punti {q['total_pts']}")
    near(float(q["max_dd_r"]), dd, 3e-3 + 1e-4 * n, f"fascia {k}: maxDD {q['max_dd_r']} atteso {dd:.3f}")
    near(float(q["t_stat"]), t, 3e-3 + 1e-4 * n, f"fascia {k}: t {q['t_stat']} atteso {t:.3f}")
    el = 1 if n >= ns.min_trades else 0
    if int(q["eligible"]) != el:
        diffs.append(f"fascia {k}: flag classifica {q['eligible']} atteso {el}")
    if ns.split > 0:
        nb = sum(1 for r in tr if ts(r["topen"]) < ns.split)
        na = n - nb
        if int(q["trades_before"]) != nb or int(q["trades_after"]) != na:
            diffs.append(f"fascia {k}: prima/dopo {q['trades_before']}/{q['trades_after']} atteso {nb}/{na}")
    else:
        if int(q["trades_after"]) != 0 or int(q["trades_before"]) != n:
            diffs.append(f"fascia {k}: senza data di separazione prima/dopo {q['trades_before']}/{q['trades_after']} atteso {n}/0")
    exp_score[k] = {"tstat": t, "er": mean, "pf": min(pf, 10.0), "total": s}[ns.rank_by]
    exp_elig[k] = el
# ordine: prima le fasce con abbastanza trade per punteggio decrescente, poi le altre per numero di trade; a pari merito la fascia con indice minore
order = [int(q["slot"]) for q in rank]
ks = list(order)


def key(k):
    if exp_elig[k]:
        return (0, -exp_score[k], k)
    return (1, -exp_n[k], k)


expo = sorted(ks, key=key)
# tolleranza sui punteggi quasi uguali (arrotondamento del CSV): confronta solo se la differenza supera 1e-6
if order != expo:
    bad = False
    for i in range(len(order)):
        if order[i] != expo[i]:
            a, b = order[i], expo[i]
            if exp_elig[a] == exp_elig[b] and abs(exp_score.get(a, 0) - exp_score.get(b, 0)) < 1e-6 and exp_elig[a]:
                continue
            bad = True
    if bad:
        diffs.append(f"ordine della classifica {order} atteso {expo}")
if [int(q["rank"]) for q in rank] != list(range(1, len(rank) + 1)):
    diffs.append("numerazione delle posizioni non progressiva")
print(f"classifica: {len(rank)} fasce, {sum(exp_n.values())} trade ricalcolati, differenze {len(diffs)}")
for d in diffs[:8]:
    print("   -", d)
sys.exit(1 if diffs else 0)
