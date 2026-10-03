#!/bin/bash
# Ricompila lo script e l'EA nell'harness e rilancia tutte le verifiche. Richiede g++ e python3.
set -e
cd "$(dirname "$0")"
mkdir -p build && cd build
H=..
cp $H/runcmp.sh $H/ref_check.py . 2>/dev/null || true
python3 $H/prep.py $H/../../MQL5/Scripts/VP_RR_Study_v1.0.mq5 study_pp.cpp
python3 $H/prep_ea.py
python3 $H/extract_trailing.py $H/../../MQL5/Experts/VolumeProfile_v1.0_EA_ULTIMATE_ML_Sydney.mq5 ea_trailing_fn.inc
CXX="g++ -std=c++17 -w -I. -I$H"
$CXX -O2 -o study_nosan $H/main_study.cpp
$CXX -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -o study_san $H/main_study.cpp
$CXX -O2 -o ea_run $H/main_ea.cpp
$CXX -O2 -fsanitize=address,undefined -o sim $H/main_sim.cpp
$CXX -O2 -o trail_ref $H/main_trail_ref.cpp
fail=0
echo "== 1. simulatore SL/TP/trailing contro riferimento Python indipendente =="
./sim && python3 ref_check.py
echo "== 1b. trailing: ProcessTrailing() REALE dell'EA su tick fitti contro SimTrail =="
./trail_ref 300 2e-6 || fail=1
echo "== 2. segnali dello script contro l'EA reale (stessi dati) =="
for t in "M15||260|0.002" "M5||60|0.002" "H1||260|0.002" \
         "M15|InpStrictMode=0,InpUseHullFilter=0,InpRequireRejection=0,InpMinTouchBars=1|90|0.002" \
         "M15|InpAutoDST=0|90|0.002" "M15|InpVADistance=4,InpMinWickRatio=0.5|120|0.002" \
         "M15|InpProfileMode=0|120|0.002" "M15|InpProfileMode=1|200|0.002" "M15|InpProfileMode=2|260|0.002" \
         "M15|InpTimeframe=5|60|0.002" "M15|InpTimeframe=1|40|0.002"; do
  IFS='|' read tf ov d k <<< "$t"
  ./runcmp.sh "$tf" "$ov" $d $k || fail=1
done
echo "== 3. sanitizer su scenari limite =="
export VPTF=M15 VPINP=""
for a in "1 200 0.002" "5 150 0.002" "0 12 0.002" "4 300 0.03" "0 260 0.002"; do
  ./study_san $a >/dev/null 2>err.txt || { echo "ERRORE scenario $a"; head -5 err.txt; fail=1; }
done
echo "== 4. test nullo (random walk, costi zero): nessuna cella deve validare OOS =="
./study_nosan 4 1500 0.0 2>&1 | grep -A6 RIEPILOGO | cut -c1-200
echo "== 5. test di potenza (mean-reversion forte): il fade ai bordi deve risultare significativo =="
./study_nosan 4 400 0.03 2>&1 | grep -A6 RIEPILOGO | cut -c1-200
echo "== 6. MDRB: EA MultiDayRangeBreakout reale contro MDRB_Study (batteria differenziale) =="
(cd .. && ./run_mdrb.sh | tail -1) || fail=1
[ $fail -eq 0 ] && echo "TUTTO OK" || { echo "ATTENZIONE: verifiche fallite"; exit 1; }
