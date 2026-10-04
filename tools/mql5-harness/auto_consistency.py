#!/usr/bin/env python3
"""Coerenza della modalita' AUTO: una riga della mappa (MDRB_Study_*_map.csv) deve dare gli STESSI numeri dell'analisi
completa della stessa definizione lanciata come configurazione singola (InpAuto=0). Verifica anche il taglio IS/OOS per data."""
import csv, os, subprocess, sys, random, re
days, kappa, tf = sys.argv[1], sys.argv[2], sys.argv[3]
nsel = int(sys.argv[4]) if len(sys.argv) > 4 else 14
F = "out/MQL5/Files/"
rows = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_map.csv")))
combos = {}
for r in rows:
    key = (r["range"], r["ws_min"], r["we_min"])
    combos.setdefault(key, {})[r["cfg"]] = r
keys = [k for k in combos if int(combos[k]["PT_ref"]["n_is"]) >= 10]
random.seed(7)
win = [k for k in combos if combos[k]["PT_ref"]["winner"] == "1"]
pick = list(dict.fromkeys(win + random.sample(keys, min(nsel, len(keys)))))
bad = 0
for k in pick:
    r = combos[k]["PT_ref"]
    ws, we = int(r["ws_min"]), int(r["we_min"])
    ov = [f"InpAuto=0", f"RangeMode={r['mode']}", f"RangeDaysBack={r['days_back']}", f"RangeBarsLookback={r['lookback_bars']}",
          f"RangeHourStart={r['rhs']}", f"RangeMinuteStart={r['rms']}", f"RangeHourEnd={r['rhe']}", f"RangeMinuteEnd={r['rme']}",
          f"RangeDaySpan={r['span']}", f"TradeHourStart={ws//60}", f"TradeMinuteStart={ws%60}", f"TradeHourEnd={(we%1440)//60}", f"TradeMinuteEnd={we%60}"]
    env = dict(os.environ, VPINP=",".join(ov), VPTF=tf, MDRB_QUIET="1", GEN_ROUND="1e7")
    subprocess.run(["./mdrb_study_fast", days, kappa, "0"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    grid = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_grid.csv")))
    refpts = float(combos[k]["PT_ref"]["ref_sl_pts"])
    ref = [g for g in grid if g["family"] == "0" and abs(float(g["sl"]) - refpts * 1e-5) < 2e-7 and abs(float(g["rr_or_tp"]) - 2.0) < 1e-9][0]
    ea = [g for g in grid if g["family"] == "5"][0]
    for name, g, m in (("PT_ref", ref, combos[k]["PT_ref"]), ("EA_exit", ea, combos[k]["EA_exit"])):
        ok = (int(g["n_is"]) == int(m["n_is"]) and int(g["n_oos"]) == int(m["n_oos"])
              and abs(float(g["er_is"]) - float(m["er_is"])) < 2e-4 and abs(float(g["er_oos"]) - float(m["er_oos"])) < 2e-4
              and abs(float(g["t_is"]) - float(m["t_is"])) < 2e-2 and abs(float(g["t_oos"]) - float(m["t_oos"])) < 2e-2)
        if not ok:
            bad += 1
            print("DIFF", k, name, {x: g[x] for x in ("n_is", "er_is", "t_is", "n_oos", "er_oos", "t_oos")}, {x: m[x] for x in ("n_is", "er_is", "t_is", "n_oos", "er_oos", "t_oos")})
print(f"coerenza mappa == analisi singola: {len(pick)} combinazioni x 2 uscite, differenze {bad}")
sys.exit(1 if bad else 0)
