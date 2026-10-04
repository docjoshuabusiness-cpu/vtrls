#!/usr/bin/env python3
"""Modalita' PERSONALIZZATA: i filtri scelti dall'utente (giorni della settimana, periodo, larghezza del range, range orario,
finestra di ingresso, time frame) devono essere rispettati davvero, sia nella parte A sia nella parte B."""
import csv, os, subprocess, sys, calendar, time
F = "out/MQL5/Files/"
def run(ov, days="300", seed="0"):
    env = dict(os.environ, VPINP=ov, VPTF="M15", MDRB_QUIET="1", GEN_ROUND="1e7")
    subprocess.run(["./mdrb_study_fast", days, "0.002", seed], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
def wday(s): return time.gmtime(calendar.timegm(time.strptime(s, "%Y.%m.%d"))).tm_wday      # 0 = lunedi
bad = 0
def check(cond, msg):
    global bad
    if not cond: bad += 1; print("FALLITO:", msg)
# 1. giorni della settimana (classico, parte B)
run("InpAuto=0,AnalysisMode=1,ChWeekdays=1 3")
rows = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_trades.csv")))
check(len(rows) > 20 and all(wday(r["day"]) in (0, 2) for r in rows), f"giorni: trade fuori da lunedi/mercoledi ({len(rows)} trade)")
# 2. periodo
f0, t0 = calendar.timegm((2023, 3, 1, 0, 0, 0)), calendar.timegm((2023, 6, 1, 0, 0, 0))
run(f"InpAuto=0,AnalysisMode=1,ChFrom={f0},ChTo={t0}")
rows = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_trades.csv")))
ds = [calendar.timegm(time.strptime(r["day"], "%Y.%m.%d")) for r in rows]
check(len(rows) > 10 and min(ds) >= f0 - 86400 and max(ds) <= t0, f"periodo: trade fuori da marzo-maggio ({len(rows)} trade)")
# 3. larghezza del range
run("InpAuto=0,AnalysisMode=1,ChMinRangePts=60,ChMaxRangePts=140")
rows = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_trades.csv")))
check(len(rows) > 10 and all(60 - 1 <= float(r["range_pts"]) <= 140 + 1 for r in rows), f"larghezza: range fuori da 60-140 punti ({len(rows)} trade)")
# 4. parte A: range orario, time frame, giorni
run("AnalysisMode=1,ChRangeHourStart=8,ChRangeHours=4,ChTFMin=15,ChTFMax=60,ChWeekdays=2 3 4,g_cbDbgW=0,g_cbDbgT=2")
ev = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_cb_events_debug.csv")))
check(len(ev) > 20 and all(wday(r["day"]) in (1, 2, 3) for r in ev) and all(r["tf"] == "M15" and r["win_start"] == "8" and r["win_hours"] == "4" for r in ev), "parte A: filtri di giorni/range/TF non rispettati")
html = open(F + "MDRB_Study_EURUSD.html", encoding="utf-8", errors="ignore").read()
check(">M1<" not in html.split("A1b.")[0].split("Solo M1")[0] or "Solo M1" not in html, "parte A: il TF M1 non doveva comparire (minimo 15 minuti)")
# 5. parte B: universo personalizzato = solo le definizioni e la finestra richieste
run("AnalysisMode=1,ChRangeHourStart=8,ChRangeHours=4,ChEntryHourStart=14,ChEntryHourEnd=15")
m = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_map.csv")))
check(len(m) > 0 and all(r["ws_min"] == "840" and r["we_min"] == "900" for r in m) and all(r["range"].startswith("Sessione 08:00-12:00") for r in m), "parte B: universo non ristretto alla sessione 08-12 con ingresso 14-15")
print(f"modalita' personalizzata: filtri verificati, problemi {bad}")
sys.exit(1 if bad else 0)
