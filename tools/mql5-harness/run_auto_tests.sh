#!/bin/bash
# Verifiche della modalita' AUTO di MDRB_Study (richiede run_mdrb.sh gia' eseguito: usa build/).
set -e
set -o pipefail
cd "$(dirname "$0")/build"
H=..
python3 $H/prep_mdrb.py >/dev/null
CXX="g++ -std=c++17 -w -I. -I$H"
$CXX -O2 -o mdrb_study_fast $H/main_mdrb_study.cpp
$CXX -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -o mdrb_study_san $H/main_mdrb_study.cpp
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
echo "== A3. AddressSanitizer: modalita' AUTO su storia corta e su kappa estremo =="
for a in "90 0.002 0" "70 0.03 1"; do
  VPINP="" ./mdrb_study_san $a >/dev/null 2>err_auto.txt || { echo "ERRORE ASan $a"; head -8 err_auto.txt; fail=1; }
done
cp $H/auto_null.py .
echo "== A4. test nullo: random walk a costi zero, 12 storie (36 vincitori): confermati OOS ~5% atteso, massimo 5 =="
python3 auto_null.py 900 0.0 12 0 5 - | tail -6 || fail=1
echo "== A5. test di potenza: salto giornaliero del livello medio (effetto reale nei dati): i vincitori giornalieri devono confermarsi =="
python3 auto_null.py 900 0.002 6 -1 - 4 | tail -6 || fail=1
[ $fail -eq 0 ] && echo "AUTO: TUTTO OK" || { echo "AUTO: verifiche fallite"; exit 1; }
