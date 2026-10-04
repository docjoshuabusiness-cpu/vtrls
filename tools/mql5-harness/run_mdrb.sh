#!/bin/bash
# Batteria differenziale MDRB: l'EA MultiDayRangeBreakout reale (broker simulato, tick per tick) contro MDRB_AutoStudy.
# Richiede g++ e python3. Dati sintetici, griglia prezzi fine (GEN_ROUND) per evitare il rumore float dell'EA ai soglie esatte.
set -e
cd "$(dirname "$0")"
mkdir -p build && cd build
H=..
cp $H/mdrb_cmp.py $H/mdrb_run.sh $H/mdrb_battery.sh . && chmod +x mdrb_run.sh mdrb_battery.sh
python3 $H/prep_mdrb.py
CXX="g++ -std=c++17 -w -I. -I$H"
$CXX -O2 -o mdrb_ea $H/main_mdrb_ea.cpp
$CXX -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -o mdrb_study_san $H/main_mdrb_study.cpp
./mdrb_battery.sh | tee mdrb_battery.log
tail -1 mdrb_battery.log | grep -q "DIFF 0"
