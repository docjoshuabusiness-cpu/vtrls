#!/bin/bash
# Verifiche della modalita' AUTO di MDRB_Study (richiede run_mdrb.sh gia' eseguito: usa build/).
set -e
set -o pipefail
cd "$(dirname "$0")/build"
H=..
python3 $H/prep_mdrb.py >/dev/null
CXX="g++ -std=c++17 -w -I. -I$H"
$CXX -O2 -o mdrb_study_fast $H/main_mdrb_study.cpp
$CXX -O1 -g -fsanitize=address,undefined,float-divide-by-zero -fno-sanitize-recover=undefined,float-divide-by-zero -o mdrb_study_san $H/main_mdrb_study.cpp
cp $H/auto_consistency.py .
export GEN_ROUND=1e7 VPTF=M15 MDRB_QUIET=1
F=out/MQL5/Files
fail=0
echo "== A1. orizzonte adattivo (fast path) identico all'orizzonte pieno =="
VPINP="InpFastPath=1" ./mdrb_study_fast 260 0.002 0 >/dev/null 2>&1; cp $F/MDRB_Study_EURUSD_map.csv map_fast.csv
VPINP="InpFastPath=0" ./mdrb_study_fast 260 0.002 0 >/dev/null 2>&1; cp $F/MDRB_Study_EURUSD_map.csv map_full.csv
if cmp -s map_fast.csv map_full.csv; then echo "OK: mappa identica byte per byte ($(wc -l < map_full.csv) righe)"; else echo "DIFF fast/full"; fail=1; fi
echo "== A2. riga della mappa == analisi completa della stessa definizione (+ taglio IS/OOS per data) =="
VPINP="" ./mdrb_study_fast 260 0.002 0 >/dev/null 2>&1
python3 auto_consistency.py 260 0.002 M15 14 || fail=1
echo "== A3. AddressSanitizer + UBSan + divisioni per zero in virgola mobile (fatali in MQL5, silenziose in C++): modalita' AUTO =="
for a in "90 0.002 0" "70 0.03 1" "400 0.002 0"; do
  VPINP="" ./mdrb_study_san $a >/dev/null 2>err_auto.txt || { echo "ERRORE ASan $a"; head -8 err_auto.txt; fail=1; }
done
for g in "GEN_GAPS=0.01" "GEN_BREAK=1 GEN_GAPS=0.003"; do
  env $g VPINP="" ./mdrb_study_san 90 0.002 0 >/dev/null 2>err_auto.txt || { echo "ERRORE ASan dati con buchi ($g)"; head -8 err_auto.txt; fail=1; }
done
cp $H/auto_null.py $H/cb_check.py $H/event_check.py $H/custom_check.py .
echo "== A4. test nullo: random walk a costi zero, 12 storie (36 vincitori): confermati OOS ~5% atteso, massimo 5 =="
python3 auto_null.py 900 0.0 12 0 5 - | tail -6 || fail=1
echo "== A5. test di potenza: salto giornaliero del livello medio (effetto reale nei dati): i vincitori giornalieri devono confermarsi =="
python3 auto_null.py 900 0.002 6 -1 - 4 | tail -6 || fail=1
echo "== A6. Parte A (rotture a candela chiusa): eventi, k, 21 esiti SL x RR, MFE, rientro e sopravvivenza contro il ricalcolo indipendente in Python; statistiche su eventi distinti; dati con buchi =="
export MDRB_DUMP_M1=1
for gaps in "" "GEN_GAPS=0.004" "GEN_BREAK=1 GEN_GAPS=0.002"; do
  echo "-- dati: ${gaps:-completi}"
  for combo in "43 2" "54 4" "14 0" "54 5" "100 4" "-2 2" "-2 4" "-2 0"; do
    set -- $combo
    env $gaps VPINP="g_cbDbgW=$1,g_cbDbgT=$2,InpSpreadPoints=2" ./mdrb_study_fast 150 0.002 1 >/dev/null 2>&1
    python3 cb_check.py $1 $2 2 || fail=1
  done
done
echo "== A7. Parte B: ritest, meta' range, zona del giorno prima, falsi breakout, MFE e rientro contro il ricalcolo indipendente =="
for ov in "InpAuto=0" "InpAuto=0,RangeMode=1,RangeHourStart=0,RangeHourEnd=8,RangeDaysBack=0,TradeHourStart=9,TradeHourEnd=12,PendingOrderOffsetPoints=10" "InpAuto=0,ChaseIfBroken=1,TradeHourStart=20,TradeHourEnd=23"; do
  off=$(echo "$ov" | grep -o "PendingOrderOffsetPoints=[0-9]*" | cut -d= -f2 || true); off=${off:-20}
  VPINP="$ov" ./mdrb_study_fast 300 0.002 1 >/dev/null 2>&1
  python3 event_check.py $off || fail=1
done
unset MDRB_DUMP_M1
echo "== A8. modalita' PERSONALIZZATA: giorni, periodo, larghezza, range orario, finestra, time frame =="
python3 custom_check.py || fail=1
echo "== A9. metro di misura: PUNTI / ATR / ENTRAMBI producono il report atteso =="
for u in 0 1 2; do
  VPINP="UnitMode=$u" ./mdrb_study_fast 200 0.002 0 >/dev/null 2>&1
  python3 - $u <<'PYU' || fail=1
import re, sys
u = int(sys.argv[1]); h = open("out/MQL5/Files/MDRB_Study_EURUSD.html", encoding="utf-8", errors="ignore").read()
has_atr_tab = "Stessa distanza espressa in ATR" in h
appx = "GA. Appendice" in h
appx_pt = "A. Appendice: rischio/rendimento in PUNTI" in h
ok = (u == 0 and appx and not has_atr_tab and not appx_pt) or (u == 1 and has_atr_tab and appx_pt and not appx) or (u == 2 and has_atr_tab and not appx and not appx_pt)
print("unita'", u, "OK" if ok else "FALLITO")
sys.exit(0 if ok else 1)
PYU
done
[ $fail -eq 0 ] && echo "AUTO: TUTTO OK" || { echo "AUTO: verifiche fallite"; exit 1; }
