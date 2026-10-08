#!/bin/bash
# Analisi delle fasce orarie dell'EA (SlotScan): ogni fascia virtuale contro l'EA REALE fatto girare sul broker simulato
# con RANGE_TIME sulle ore di quella fascia, sugli stessi tick (PATHMODE=fixed: il percorso dei tick non dipende dallo stato dell'EA).
# Richiede g++ e python3; non lanciare insieme alla batteria (usano la stessa cartella build/).
set -e
set -o pipefail
cd "$(dirname "$0")"
mkdir -p build && cd build
H=..
python3 $H/prep_mdrb.py >/dev/null
CXX="g++ -std=c++17 -w -I. -I$H"
$CXX -O2 -o mdrb_ea $H/main_mdrb_ea.cpp
$CXX -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -o mdrb_ea_san $H/main_mdrb_ea.cpp
cp $H/slot_check.py $H/slot_rank_check.py .
export GEN_ROUND=1e7 TICKSTEP_PTS=0.5 PATHMODE=fixed VPTF=M15
fail=0
n_ok=0
sc() {   # nome giorni override [kappa] [binario]
  local name="$1" days="$2" ov="$3" kappa="${4:-0.002}" bin="${5:-./mdrb_ea}"
  local first=0 len=2
  [[ "$ov" =~ SlotFirstHour=([0-9]+) ]] && first=${BASH_REMATCH[1]}
  [[ "$ov" =~ SlotLenHours=([0-9]+) ]] && len=${BASH_REMATCH[1]}
  rm -f out/MQL5/Files/MDRB_SlotScan_*
  VPINP="$ov,SlotScan=1" MDRB_QUIET=1 $bin $days $kappa 0 >/dev/null 2>err_slot.txt || { echo "ERRORE scansione ($name)"; head -5 err_slot.txt; fail=1; return; }
  [ -f out/MQL5/Files/MDRB_SlotScan_EURUSD_trades.csv ] || { echo "ERRORE: nessun file di trade virtuali ($name)"; fail=1; return; }
  cp out/MQL5/Files/MDRB_SlotScan_EURUSD_trades.csv scan_trades.csv
  cp out/MQL5/Files/MDRB_SlotScan_EURUSD.csv scan_rank.csv
  local tot=0 bad=0
  for k in 0 1 2 3 4 5 6 7 8 9 10 11; do
    local hs=$(( (first + k * len) % 24 )) he=$(( (first + k * len + len) % 24 ))
    VPINP="$ov,RangeMode=1,RangeHourStart=$hs,RangeMinuteStart=0,RangeHourEnd=$he,RangeMinuteEnd=0" $bin $days $kappa 0 >/dev/null 2>err_slot.txt || { echo "ERRORE EA reale fascia $((k+1)) ($name)"; head -5 err_slot.txt; fail=1; return; }
    o=$(python3 slot_check.py $((k+1)) 0.02 --scan scan_trades.csv --ea mdrb_ea_trades.csv 2>&1) || { echo "$o" | head -8; bad=$((bad+1)); }
    tot=$((tot + $(echo "$o" | sed -n 's/.*comuni \([0-9]*\),.*/\1/p')))
  done
  python3 slot_rank_check.py scan_trades.csv scan_rank.csv --min-trades $(echo "$ov" | sed -n 's/.*SlotMinTrades=\([0-9]*\).*/\1/p' | grep . || echo 30) --split $(echo "$ov" | sed -n 's/.*SlotSplitDate=\([0-9]*\).*/\1/p' | grep . || echo 0) || bad=$((bad+1))
  if [ $bad -eq 0 ]; then n_ok=$((n_ok+1)); echo "OK   $name | 12 fasce, $tot trade confrontati con l'EA reale, 0 differenze"; else fail=1; echo "DIFF $name | fasce con differenze: $bad"; fi
}
R="RequireRangeConfirmation=0"
sc "default (range di ieri, finestra 10-11)" 300 "$R"
sc "range di oggi, finestra 14-16" 300 "$R,RangeDaysBack=0,TradeHourStart=14,TradeHourEnd=16"
sc "filtro di larghezza 60-300" 300 "RequireRangeConfirmation=1,MinRangePoints=60,MaxRangePoints=300"
sc "ChaseIfBroken + stops level 25" 300 "$R,ChaseIfBroken=1,StopsLevel=25"
sc "trailing aggressivo, SL 60" 300 "$R,StopLossPoints=60,TakeProfitPoints=300,BreakEvenAttivazione=30,BreakEvenOffset=5,TrailingStartProfit=50,TrailingStep=10,TrailingOffset=20"
sc "3 trade al giorno, TP corto" 300 "$R,MaxTradesPerDay=3,StopLossPoints=50,TakeProfitPoints=60,TradeHourStart=9,TradeHourEnd=17"
sc "fasce da 1 ora dalle 06, finestra 20-23" 300 "$R,SlotFirstHour=6,SlotLenHours=1,RangeDaysBack=0,TradeHourStart=20,TradeHourEnd=23"
sc "fasce da 3 ore, finestra a cavallo 22-02" 300 "$R,SlotFirstHour=0,SlotLenHours=3,TradeHourStart=22,TradeHourEnd=2,RangeDaysBack=0"
sc "offset 80, solo SL/TP" 300 "$R,PendingOrderOffsetPoints=80,UsaBreakEven=0,UsaTrailingStop=0"
sc "kappa 0.03" 300 "$R" 0.03
echo "== scansione sotto AddressSanitizer + UBSan (dati sintetici, tutte le fasce) =="
for ov in "$R" "$R,ChaseIfBroken=1,StopsLevel=25,MaxTradesPerDay=3"; do
  rm -f out/MQL5/Files/MDRB_SlotScan_*
  VPINP="$ov,SlotScan=1,SlotSplitDate=1676000000" MDRB_QUIET=1 ./mdrb_ea_san 120 0.002 0 >/dev/null 2>err_slot.txt || { echo "ERRORE ASan ($ov)"; head -8 err_slot.txt; fail=1; }
done
echo "== input non validi: la scansione deve fermarsi con un messaggio, senza ordini =="
for bad in "SlotLenHours=0" "SlotLenHours=13" "SlotFirstHour=24" "Slot1=0,Slot2=0,Slot3=0,Slot4=0,Slot5=0,Slot6=0,Slot7=0,Slot8=0,Slot9=0,Slot10=0,Slot11=0,Slot12=0" "SlotMinTrades=0"; do
  if VPINP="$R,SlotScan=1,$bad" MDRB_QUIET=1 ./mdrb_ea 30 0.002 0 >/dev/null 2>err_slot.txt; then echo "ERRORE: l'input non valido ($bad) e' stato accettato"; fail=1; else echo "rifiutato: $bad"; fi
done
[ $fail -eq 0 ] && echo "FASCE: TUTTO OK ($n_ok scenari)" || { echo "FASCE: verifiche fallite"; exit 1; }
