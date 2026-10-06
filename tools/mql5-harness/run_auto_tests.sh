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
for g in "GEN_GAPS=0.01" "GEN_BREAK=1 GEN_GAPS=0.003"; do      # modalita' classica: conferma a chiusura e anatomia del range
  env $g VPINP="InpAuto=0,RangeMode=1,RangeHourStart=0,RangeHourEnd=8,RangeDaysBack=0,TradeHourStart=9,TradeHourEnd=12" ./mdrb_study_san 90 0.002 0 >/dev/null 2>err_auto.txt || { echo "ERRORE ASan classica ($g)"; head -8 err_auto.txt; fail=1; }
done
cp $H/auto_null.py $H/cb_check.py $H/cb2_check.py $H/event_check.py $H/custom_check.py $H/bc_check.py $H/rd_check.py .
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
  echo "-- parte A2 (range = ultime N candele): dati: ${gaps:-completi}"
  for combo in "2 3" "0 0" "4 5" "1 1" "5 2"; do
    set -- $combo
    env $gaps VPINP="g_cbDbg2=$(( $1 * 6 + $2 )),InpSpreadPoints=2" ./mdrb_study_fast 150 0.002 1 >/dev/null 2>&1
    python3 cb2_check.py $1 $2 2 || fail=1
  done
done
echo "== A7. Parte B: ritest, meta' range, zona del giorno prima, falsi breakout, MFE e rientro contro il ricalcolo indipendente =="
for ov in "InpAuto=0" "InpAuto=0,RangeMode=1,RangeHourStart=0,RangeHourEnd=8,RangeDaysBack=0,TradeHourStart=9,TradeHourEnd=12,PendingOrderOffsetPoints=10" "InpAuto=0,ChaseIfBroken=1,TradeHourStart=20,TradeHourEnd=23"; do
  off=$(echo "$ov" | grep -o "PendingOrderOffsetPoints=[0-9]*" | cut -d= -f2 || true); off=${off:-20}
  VPINP="$ov" ./mdrb_study_fast 300 0.002 1 >/dev/null 2>&1
  python3 event_check.py $off || fail=1
done
echo "== A7b. Parte B, variante a chiusura su 7 time frame: candela di conferma, ingresso, R, MFE/rientro e completezza contro il ricalcolo indipendente; dati con buchi =="
for gaps in "" "GEN_GAPS=0.004" "GEN_BREAK=1 GEN_GAPS=0.002"; do
  echo "-- dati: ${gaps:-completi}"
  for def in "10 9 12 30 0 8" "20 20 23 0 0 8" "0 9 11 0 6 8"; do      # offset, ora inizio e fine finestra, scadenza extra (min), ora inizio e fine range
    set -- $def; off=$1; wsh=$2; weh=$3; ex=$4; rhs=$5; rhe=$6
    ov="InpAuto=0,RangeMode=1,RangeHourStart=$rhs,RangeHourEnd=$rhe,RangeDaysBack=0,TradeHourStart=$wsh,TradeHourEnd=$weh,ExpireExtraMinutes=$ex,PendingOrderOffsetPoints=$off,InpSpreadPoints=2"
    env $gaps VPINP="$ov" ./mdrb_study_fast 300 0.002 1 >/dev/null 2>&1
    rs=$(python3 -c "import re;h=open('out/MQL5/Files/MDRB_Study_EURUSD.html',encoding='utf-8',errors='ignore').read();print(re.search(r'ATR mediano (\d+) punti',h).group(1))")
    for tf in 60 300 900 1800 3600 7200 10800; do
      o=$(python3 bc_check.py $tf $off $((weh*60)) $ex $((wsh*60)) 2 --rhs $((rhs*60)) --rhe $((rhe*60)) --days-back 0 --ref-sl $rs --min-events 0 2>&1) || { echo "$o" | head -12; fail=1; }
      echo "def $off/$wsh-$weh/+$ex/$rhs-$rhe: $(echo "$o" | tail -1)"
    done
  done
done
echo "== A10. Parte B, anatomia del range: giorni, caratteristiche, contesto D1, ATR, esiti w/h4/h24 contro il ricalcolo indipendente; dati con buchi =="
rd_run() {  # $1 = override del VPINP, poi gli argomenti di rd_check.py
  local ov="$1"; shift
  env $gaps VPINP="InpAuto=0,RequireRangeConfirmation=0,$ov,InpSpreadPoints=2" ./mdrb_study_fast 300 0.002 1 >/dev/null 2>&1
  local cut lastd o
  cut=$(awk -F, '$3=="OOS"{print $1; exit}' out/MQL5/Files/MDRB_Study_EURUSD_range_days.csv)
  lastd=$(python3 -c "import time;l=open('m1.csv').read().strip().split('\n')[-1].split(',')[0];print(time.strftime('%Y.%m.%d',time.gmtime(int(l))))")
  o=$(python3 rd_check.py --spread 2 --atr-tf H1 --cut "$cut" --to-day "$lastd" "$@" 2>&1) || { echo "$o" | head -14; fail=1; }
  echo "$(echo "$o" | grep -c 'differenze 0') controlli senza differenze, $(echo "$o" | grep -E '^[a-zA-Z].*differenze [1-9]' | wc -l) con differenze"
}
for gaps in "" "GEN_GAPS=0.004" "GEN_BREAK=1 GEN_GAPS=0.002"; do
  echo "-- dati: ${gaps:-completi}"
  rd_run "RangeMode=1,RangeHourStart=0,RangeHourEnd=8,RangeDaysBack=0,TradeHourStart=9,TradeHourEnd=12" --mode time --rhs 0 --rhe 8 --days-back 0 --ws-min 540 --we-min 720
  rd_run "RangeMode=1,RangeHourStart=8,RangeHourEnd=10,RangeDaysBack=0,TradeHourStart=9,TradeHourEnd=12" --mode time --rhs 8 --rhe 10 --days-back 0 --ws-min 540 --we-min 720
  rd_run "RangeMode=1,RangeHourStart=0,RangeHourEnd=8,RangeDaysBack=0,TradeHourStart=20,TradeHourEnd=23" --mode time --rhs 0 --rhe 8 --days-back 0 --ws-min 1200 --we-min 1380
  rd_run "RangeMode=2,RangeDaysBack=1,RangeDaySpan=2,TradeHourStart=10,TradeHourEnd=11" --mode d1 --days-back 1 --span 2 --ws-min 600 --we-min 660
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
appx = "A. Appendice: distanze in ATR" in h          # appendice con le griglie ATR (metro PUNTI)
appx_pt = "A. Appendice: rischio/rendimento in PUNTI" in h     # appendice con le griglie in punti (metro ATR)
new_sections = all(x in h for x in ("A6. Larghezza dei range orari", "A7. Larghezza del range e time frame", "Parte A2", "A8. Per time frame e numero di candele", "A8c."))
ok = new_sections and ((u == 0 and appx and not has_atr_tab and not appx_pt) or (u == 1 and has_atr_tab and appx_pt and not appx) or (u == 2 and has_atr_tab and not appx and not appx_pt))
print("unita'", u, "OK" if ok else "FALLITO")
sys.exit(0 if ok else 1)
PYU
done
[ $fail -eq 0 ] && echo "AUTO: TUTTO OK" || { echo "AUTO: verifiche fallite"; exit 1; }
