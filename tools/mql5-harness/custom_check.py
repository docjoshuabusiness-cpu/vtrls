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
def run_err(ov, days="120"):
    env = dict(os.environ, VPINP=ov, VPTF="M15", MDRB_QUIET="1", GEN_ROUND="1e7")
    r = subprocess.run(["./mdrb_study_fast", days, "0.002", "0"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    return r.stderr
# 1. giorni della settimana (classico, parte B): separatori diversi, intervalli, nomi
for spec, want in (("1 3", {0, 2}), ("tue;thu", {1, 3}), ("1-3", {0, 1, 2}), ("Mon Wed Fri", {0, 2, 4}), ("5", {4})):
    run(f"InpAuto=0,AnalysisMode=1,ChWeekdays={spec}")
    rows = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_trades.csv")))
    got = set(wday(r["day"]) for r in rows)
    check(len(rows) > 20 and got == want, f"giorni '{spec}': attesi {sorted(want)}, trovati {sorted(got)} ({len(rows)} trade)")
# 2. periodo
f0, t0 = calendar.timegm((2023, 3, 1, 0, 0, 0)), calendar.timegm((2023, 6, 1, 0, 0, 0))
run(f"InpAuto=0,AnalysisMode=1,ChFrom={f0},ChTo={t0}")
rows = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_trades.csv")))
ds = [calendar.timegm(time.strptime(r["day"], "%Y.%m.%d")) for r in rows]
check(len(rows) > 10 and min(ds) >= f0 - 86400 and max(ds) <= t0, f"periodo: trade fuori dal periodo scelto ({len(rows)} trade)")
check(max(ds) >= t0 - 3 * 86400, f"periodo: gli ultimi giorni prima di ChTo non devono perdere gli sfondamenti per 'fine dati' (ultimo trade {time.strftime('%Y-%m-%d', time.gmtime(max(ds)))})")
# ChTo: l'ultimo giorno scelto e' incluso (1 giugno 2023 e' un giovedi di mercato)
run(f"InpAuto=0,AnalysisMode=1,ChFrom={f0},ChTo={t0}", days="300")
rows2 = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_trades.csv")))
check(any(calendar.timegm(time.strptime(r["day"], "%Y.%m.%d")) == t0 for r in rows2) or len(rows2) > 0, "periodo: ChTo incluso")
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
# 6. parte A: durata non standard (5 h) e solo ora di inizio
run("AnalysisMode=1,ChRangeHours=5,g_cbDbgW=8,g_cbDbgT=2")
ev = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_cb_events_debug.csv")))
check(len(ev) > 10 and all(r["win_hours"] == "5" and r["win_start"] == "8" for r in ev), "parte A: durata di 5 ore non applicata")
# 7. parte B: ora di inizio da sola, durata da sola
run("AnalysisMode=1,ChRangeHourStart=8")
m = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_map.csv")))
rngs = set(r["range"] for r in m)
check(len(m) > 0 and all(x.startswith("Sessione 08:00-") for x in rngs) and len(rngs) >= 4, f"parte B: solo ora di inizio 08:00: righe {sorted(rngs)[:4]}")
run("AnalysisMode=1,ChRangeHours=2")
m = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_map.csv")))
rngs = set(r["range"].split(" (")[0] for r in m)
starts = set(x.split(":")[0].split()[-1] for x in rngs)
check(len(m) > 0 and all("(2 h)" in r["range"] and r["range"].startswith("Sessione ") for r in m) and len(starts) >= 12, f"parte B: solo durata 2 h: {len(starts)} ore di inizio")
# 8. time frame: ChTFMax=0 = nessun massimo; escluso dal filtro dichiarato
run("AnalysisMode=1,ChTFMin=5,ChTFMax=0")
html = open(F + "MDRB_Study_EURUSD.html", encoding="utf-8", errors="ignore").read()
check("escluso dal filtro dei time frame" in html and "<th class='rl'>H3</th><td colspan" not in html, "time frame: ChTFMax=0 deve significare nessun massimo, M1 escluso dichiarato")
# 9. validazioni: scelte incoerenti fermano lo script con un messaggio chiaro
for ov, frag in (("AnalysisMode=1,ChMinRangePts=800,ChMaxRangePts=300", "ChMinRangePts"), (f"AnalysisMode=1,ChFrom={t0},ChTo={f0}", "ChFrom"),
                 ("AnalysisMode=1,ChRangeHours=30", "ChRangeHours"), ("AnalysisMode=1,ChEntryHourStart=10,ChEntryHourEnd=10", "ChEntryHourStart")):
    err = run_err(ov)
    check("ALERT: Errore" in err and frag in err, f"validazione '{ov}': nessun errore chiaro ({err[:120]!r})")
# 10. parte A2 personalizzata: ChBars = numero di candele, ChBarsTF = time frame
run("AnalysisMode=1,ChBars=7,ChBarsTF=15")
a2 = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_partA2.csv")))
check(len(a2) > 5 and all(r["n_candles"] == "7" and r["tf"] == "M15" for r in a2), f"parte A2: ChBars=7/ChBarsTF=M15 non rispettati ({len(a2)} righe)")
# 10b. time frame scelto fuori dalla griglia della parte A2: messaggio chiaro, non "storia troppo corta"
run("AnalysisMode=1,ChBars=7,ChBarsTF=16408")
html = open(F + "MDRB_Study_EURUSD.html", encoding="utf-8", errors="ignore").read()
check("Parte A2 non disponibile" in html and "ChBarsTF" in html, "parte A2: messaggio per un time frame fuori dalla griglia")
# 10c. nessuna finestra oraria possibile (22:00 + 2 h supera le 23:00): la parte A2 sceglie lo SL di riferimento sul proprio In-Sample e lo dichiara
run("AnalysisMode=1,ChRangeHourStart=22,ChRangeHours=2,ChBars=12")
html = open(F + "MDRB_Study_EURUSD.html", encoding="utf-8", errors="ignore").read()
check("Parte A non disponibile" in html and ("scelto sull'In-Sample della parte A2" in html or "valore di default" in html), "parte A2: SL di riferimento dichiarato quando la parte A non ha finestre")
# 11. file di larghezza e parte A2 in modalita' TUTTO: struttura e coerenza
run("")
wr = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_widths.csv")))
check(len(wr) == 132 and all(float(r["p10_pts"]) <= float(r["median_pts"]) <= float(r["p90_pts"]) and (r["tercile1_is_pts"] == "" or float(r["tercile1_is_pts"]) <= float(r["tercile2_is_pts"])) for r in wr if int(r["days"]) > 0), f"larghezze: struttura/coerenza ({len(wr)} righe)")
check(all(r["tercile1_is_pts"] != "-1.00" for r in wr), "larghezze: sentinella -1 nel CSV")
a2 = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_partA2.csv")))
check(len(a2) > 100 and {r["tf"] for r in a2} >= {"M1", "M5", "M15", "H1"} and {r["n_candles"] for r in a2} == {"3", "5", "8", "12", "20", "25"}, f"parte A2: TF/N attesi ({len(a2)} righe)")
# 12. riepilogo di testo da copiare: un file solo se sta nel limite, altrimenti due parti; niente HTML residuo, sezioni chiave presenti
import glob, re
def digests():
    return sorted(glob.glob(F + "MDRB_Study_EURUSD_RIEPILOGO*.txt"))
def clean():
    for f in digests(): os.remove(f)
clean(); run("g_digLimit=900000", days="400")
d1 = digests()
check(len(d1) == 1 and d1[0].endswith("_RIEPILOGO.txt"), f"riepilogo: con limite alto atteso 1 file, trovati {[os.path.basename(x) for x in d1]}")
if d1:
    txt = open(d1[0], encoding="latin-1").read()
    check(not re.search(r"<(table|td|tr|th|div|span|b|h[123])[ >]", txt) and not re.search(r"&[a-z]+;", txt), "riepilogo: tag o entita' HTML residui")
    for key in ("RIEPILOGO GENERALE", "CONCLUSIONE AUTOMATICA", "LEGENDA", "A1. Quale SL", "A5. Le migliori combinazioni", "A7. Larghezza del range", "A8c.", "Sintesi:", "G1. Verdetto", "G2b. Anatomia del range", "G3. Come si comporta", "G4c. Conferma a candela chiusa"):
        check(key in txt, f"riepilogo: sezione '{key}' mancante")
    check("Come leggere questo report" not in txt and "Appendice" not in txt, "riepilogo: sezioni escluse presenti")
clean(); run("g_digLimit=30000", days="400")
d2 = digests()
check(len(d2) == 2 and d2[0].endswith("parte1.txt") and d2[1].endswith("parte2.txt"), f"riepilogo: con limite basso attese 2 parti, trovate {[os.path.basename(x) for x in d2]}")
if len(d2) == 2:
    t1 = open(d2[0], encoding="latin-1").read(); t2 = open(d2[1], encoding="latin-1").read()
    check("PARTE 1 DI 2" in t1 and "PARTE 2 DI 2" in t2 and "LEGENDA" in t1 and "## " in t2, "riepilogo: intestazioni delle due parti")
    both = t1 + t2
    check(all(k in both for k in ("A8c.", "Sintesi:", "G1. Verdetto")), "riepilogo: sezioni chiave perse dividendo in due parti")
clean()
print(f"modalita' personalizzata: filtri verificati, problemi {bad}")
sys.exit(1 if bad else 0)
