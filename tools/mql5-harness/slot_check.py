#!/usr/bin/env python3
"""Confronta i trade virtuali di UN concorrente dell'analisi virtuale (SlotScan: sorgente del range x modalita' di entrata)
con i trade dell'EA reale (stesso range, una sola modalita' accesa, broker simulato) fatto girare sugli stessi tick.

uso: slot_check.py <sorgente 1..14> <modalita' stop|chiusura|retest> [tolleranza R, default 0.02] [--scan FILE] [--ea FILE]
  sorgente 1..12 = fasce, 13 = range a barre, 14 = D1 precedenti
  --scan  CSV dei trade virtuali (default out/MQL5/Files/MDRB_SlotScan_EURUSD_trades.csv)
  --ea    CSV dei trade dell'EA reale (default mdrb_ea_trades.csv)
Controlla: stesso numero di trade, stessa direzione, stesso minuto di apertura, chiusura entro 2 minuti, R entro la tolleranza.
Esce con 1 se ci sono differenze.
"""
import calendar, csv, sys, time

import argparse
ap = argparse.ArgumentParser()
ap.add_argument("slot", type=int)
ap.add_argument("mode")
ap.add_argument("tol", type=float, nargs="?", default=0.02)
ap.add_argument("--scan", default="out/MQL5/Files/MDRB_SlotScan_EURUSD_trades.csv")
ap.add_argument("--ea", default="mdrb_ea_trades.csv")
ns = ap.parse_args()
slot, mode, tol, scan_f, ea_f = ns.slot, ns.mode, ns.tol, ns.scan, ns.ea


def ts(x):
    return calendar.timegm(time.strptime(x, "%Y.%m.%d %H:%M"))


scan = [r for r in csv.DictReader(open(scan_f)) if int(r["source"]) == slot and r["mode"] == mode]
ea = list(csv.DictReader(open(ea_f)))
scan.sort(key=lambda r: ts(r["topen"]))
ea.sort(key=lambda r: ts(r["topen"]))
diffs = []
if len(scan) != len(ea):
    diffs.append(f"numero di trade: scansione {len(scan)}, EA {len(ea)}")
sa = {(ts(r["topen"]), int(r["dir"])): r for r in scan}
se = {(ts(r["topen"]), int(r["dir"])): r for r in ea}
only_s = sorted(set(sa) - set(se))
only_e = sorted(set(se) - set(sa))
for k in only_s[:5]:
    diffs.append(f"solo scansione: {sa[k]['topen']} dir {k[1]}")
for k in only_e[:5]:
    diffs.append(f"solo EA: {se[k]['topen']} dir {k[1]}")
maxd = 0.0
for k in sorted(set(sa) & set(se)):
    a, e = sa[k], se[k]
    d = abs(float(a["R"]) - float(e["R"]))
    maxd = max(maxd, d)
    if d > tol:
        diffs.append(f"{a['topen']} dir {k[1]}: R scansione {a['R']} EA {e['R']}")
    if abs(ts(a["tclose"]) - ts(e["tclose"])) > 120:
        diffs.append(f"{a['topen']} dir {k[1]}: chiusura scansione {a['tclose']} EA {e['tclose']}")
name = scan[0]["label"] if scan else "?"
print(f"sorgente {slot} {name} {mode}: trade scansione {len(scan)}, EA {len(ea)}, comuni {len(set(sa) & set(se))}, max|dR| {maxd:.4f}, differenze {len(diffs)}")
for d in diffs[:8]:
    print("   -", d)
sys.exit(1 if diffs else 0)
