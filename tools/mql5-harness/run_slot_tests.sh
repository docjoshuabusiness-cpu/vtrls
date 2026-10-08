#!/bin/bash
# Analisi virtuale dell'EA (SlotScan): ogni concorrente (sorgente del range x modalita' di entrata) contro l'EA REALE fatto girare sul
# broker simulato con lo stesso range e UNA sola modalita' accesa, sugli stessi tick (PATHMODE=fixed: il percorso dei tick non dipende
# dallo stato dell'EA; EXEC_AT_TICK=1: stop e SL/TP si eseguono al prezzo del tick, come nell'analisi virtuale).
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
export GEN_ROUND=1e7 TICKSTEP_PTS=0.5 PATHMODE=fixed EXEC_AT_TICK=1
export VPTF=M15
BUILD=$PWD
JOBS=${JOBS:-4}
fail=0
n_ok=0
scn=0
MODES=(stop chiusura retest)
MODEOV=("EntryStop=1,EntryCandleClose=0,EntryRetest=0" "EntryStop=0,EntryCandleClose=1,EntryRetest=0" "EntryStop=0,EntryCandleClose=0,EntryRetest=1")

# un'esecuzione dell'EA reale in una cartella propria (cosi' girano in parallelo)
job() {   # indice override giorni kappa
  local idx="$1" ov="$2" days="$3" kappa="$4"
  local d="$BUILD/par/j$idx"
  rm -rf "$d"; mkdir -p "$d"
  ( cd "$d" && VPINP="$ov" MDRB_QUIET=1 "$BUILD/mdrb_ea" "$days" "$kappa" 0 >/dev/null 2>err.txt ) || { echo "ERRORE EA reale job $idx ($ov)"; head -3 "$d/err.txt"; return 1; }
}

sc() {   # nome giorni override [kappa] [time frame del grafico]
  local name="$1" days="$2" ov="$3" kappa="${4:-0.002}" tf="${5:-M15}"
  scn=$((scn + 1))
  if [ -n "$ONLY" ] && [ "$scn" != "$ONLY" ]; then return; fi    # ONLY=n: solo lo scenario n (per il debug)
  export VPTF="$tf"
  local first=0 len=2 d1=1
  [[ "$ov" =~ SlotFirstHour=([0-9]+) ]] && first=${BASH_REMATCH[1]}
  [[ "$ov" =~ SlotLenHours=([0-9]+) ]] && len=${BASH_REMATCH[1]}
  [[ "$ov" =~ RangeDaysBack=0 ]] && d1=0       # il range dei D1 precedenti richiede RangeDaysBack >= 1
  local nsrc=14; [ $d1 -eq 0 ] && nsrc=13
  local scanov="$ov,SlotScan=1,EntryStop=1,EntryCandleClose=1,EntryRetest=1,ScanRangeBars=1,ScanRangePrevD1=$d1"
  rm -f out/MQL5/Files/MDRB_SlotScan_*
  VPINP="$scanov" MDRB_QUIET=1 ./mdrb_ea $days $kappa 0 >/dev/null 2>err_slot.txt || { echo "ERRORE scansione ($name)"; head -5 err_slot.txt; fail=1; return; }
  [ -f out/MQL5/Files/MDRB_SlotScan_EURUSD_trades.csv ] || { echo "ERRORE: nessun file di trade virtuali ($name)"; fail=1; return; }
  cp out/MQL5/Files/MDRB_SlotScan_EURUSD_trades.csv scan_trades.csv
  cp out/MQL5/Files/MDRB_SlotScan_EURUSD.csv scan_rank.csv
  rm -rf par; mkdir -p par
  local running=0 err=0
  for ((s = 1; s <= nsrc; s++)); do
    local rov
    if [ $s -le 12 ]; then
      local k=$((s - 1)) hs he
      hs=$(( (first + k * len) % 24 )); he=$(( (first + k * len + len) % 24 ))
      rov="RangeMode=1,RangeHourStart=$hs,RangeMinuteStart=0,RangeHourEnd=$he,RangeMinuteEnd=0"
    elif [ $s -eq 13 ]; then rov="RangeMode=0"
    else rov="RangeMode=2"; fi
    for m in 0 1 2; do
      job $(( (s - 1) * 3 + m )) "$ov,$rov,${MODEOV[$m]}" $days $kappa &
      running=$((running + 1))
      if [ $running -ge $JOBS ]; then wait -n || err=1; running=$((running - 1)); fi
    done
  done
  while [ $running -gt 0 ]; do wait -n || err=1; running=$((running - 1)); done
  [ $err -eq 0 ] || { fail=1; return; }
  local tot=0 bad=0 ncmp=0
  for ((s = 1; s <= nsrc; s++)); do
    for m in 0 1 2; do
      o=$(python3 slot_check.py $s ${MODES[$m]} 0.02 --scan scan_trades.csv --ea par/j$(( (s - 1) * 3 + m ))/mdrb_ea_trades.csv 2>&1) || { echo "$o" | head -8; bad=$((bad + 1)); }
      c=$(echo "$o" | sed -n 's/.*comuni \([0-9]*\),.*/\1/p'); tot=$((tot + ${c:-0}))
      ncmp=$((ncmp + 1))
    done
  done
  python3 slot_rank_check.py scan_trades.csv scan_rank.csv --min-trades $(echo "$ov" | sed -n 's/.*SlotMinTrades=\([0-9]*\).*/\1/p' | grep . || echo 30) --split $(echo "$ov" | sed -n 's/.*SlotSplitDate=\([0-9]*\).*/\1/p' | grep . || echo 0) || bad=$((bad + 1))
  if [ $bad -eq 0 ]; then n_ok=$((n_ok + 1)); echo "OK   $name | $ncmp concorrenti, $tot trade confrontati con l'EA reale, 0 differenze"; else fail=1; echo "DIFF $name | concorrenti con differenze: $bad"; fi
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
sc "grafico M5, offset 0, tolleranza retest 15, finestra 10-12" 300 "$R,PendingOrderOffsetPoints=0,RetestTolerancePoints=15,TradeHourStart=10,TradeHourEnd=12,RangeBarsLookback=40" 0.002 M5
sc "grafico H1, 3 trade al giorno, scadenza +30 min, finestra 8-18" 300 "$R,MaxTradesPerDay=3,ExpireExtraMinutes=30,TradeHourStart=8,TradeHourEnd=18,RangeDaySpan=2,RangeBarsLookback=12" 0.002 H1
sc "retest con tolleranza 40 e offset 30, range D1 su 3 giorni, 2 trade" 300 "$R,PendingOrderOffsetPoints=30,RetestTolerancePoints=40,RangeDaySpan=3,RangeDaysBack=2,MaxTradesPerDay=2,ExpireExtraMinutes=60,TradeHourStart=11,TradeHourEnd=13"
export SPREAD_WIDE=1
sc "filtro di spread: spread largo 20 minuti ogni 90, massimo 20 punti" 300 "$R,MaxSpreadPoints=20,MaxTradesPerDay=2,TradeHourStart=9,TradeHourEnd=13"
unset SPREAD_WIDE
export VPTF=M15
if [ -n "$NOTAIL" ]; then [ $fail -eq 0 ] && echo "SCENARI OK ($n_ok)" || echo "SCENARI CON DIFFERENZE"; exit $fail; fi
echo "== scansione sotto AddressSanitizer + UBSan (dati sintetici, tutti i concorrenti) =="
for ov in "$R" "$R,ChaseIfBroken=1,StopsLevel=25,MaxTradesPerDay=3,RetestTolerancePoints=10"; do
  rm -f out/MQL5/Files/MDRB_SlotScan_*
  VPINP="$ov,SlotScan=1,EntryStop=1,EntryCandleClose=1,EntryRetest=1,ScanRangeBars=1,ScanRangePrevD1=1,SlotSplitDate=1676000000" MDRB_QUIET=1 ./mdrb_ea_san 120 0.002 0 >/dev/null 2>err_slot.txt || { echo "ERRORE ASan scansione ($ov)"; head -8 err_slot.txt; fail=1; }
  for m in 0 1 2; do
    VPINP="$ov,${MODEOV[$m]}" MDRB_QUIET=1 ./mdrb_ea_san 120 0.002 0 >/dev/null 2>err_slot.txt || { echo "ERRORE ASan EA reale ($ov, ${MODES[$m]})"; head -8 err_slot.txt; fail=1; }
  done
done
echo "== input non validi: devono fermarsi con un messaggio, senza ordini =="
for bad in "SlotScan=1,SlotLenHours=0" "SlotScan=1,SlotLenHours=13" "SlotScan=1,SlotFirstHour=24" "SlotScan=1,Slot1=0,Slot2=0,Slot3=0,Slot4=0,Slot5=0,Slot6=0,Slot7=0,Slot8=0,Slot9=0,Slot10=0,Slot11=0,Slot12=0" "SlotScan=1,SlotMinTrades=0" \
           "EntryStop=0,EntryCandleClose=0,EntryRetest=0" "SlotScan=1,EntryStop=0,EntryCandleClose=0,EntryRetest=0" "EntryRetest=1,RetestTolerancePoints=-1" "SlotScan=1,ScanRangePrevD1=1,RangeDaysBack=0" "SlotScan=1,ScanRangeBars=1,RangeBarsLookback=0"; do
  if VPINP="$R,$bad" MDRB_QUIET=1 ./mdrb_ea 30 0.002 0 >/dev/null 2>err_slot.txt; then echo "ERRORE: l'input non valido ($bad) e' stato accettato"; fail=1; else echo "rifiutato: $bad"; fi
done
[ $fail -eq 0 ] && echo "FASCE: TUTTO OK ($n_ok scenari)" || { echo "FASCE: verifiche fallite"; exit 1; }
