#!/bin/bash
# Batteria differenziale: EA reale (broker simulato) contro MDRB_Study.
export GEN_ROUND=1e7 TICKSTEP_PTS=0.1
pass=0; fail=0
t() {  # nome giorni override [TF] [kappa]
  out=$(KAPPA=${5:-0.002} ./mdrb_run.sh "$2" "${5:-0.002}" "$3" "${4:-M15}" 2>&1)
  if echo "$out" | grep -q "ESITO: OK"; then pass=$((pass+1)); st="OK  "; else fail=$((fail+1)); st="DIFF"; fi
  tr=$(echo "$out" | grep "^TRADE" | sed 's/  */ /g')
  echo "$st $1 | $tr"
  [ "$st" = "DIFF" ] && echo "$out" | head -12 | sed 's/^/        /'
}
R="RequireRangeConfirmation=0"
t "default EA 700g"                    700 "$R"
t "BARS daysBack=0 lookback 12"        400 "$R,RangeDaysBack=0,RangeBarsLookback=12"
t "TIME 00-08 oggi"                    400 "$R,RangeMode=1,RangeHourStart=0,RangeHourEnd=8,RangeDaysBack=0"
t "TIME 16-00 ieri"                    400 "$R,RangeMode=1,RangeHourStart=16,RangeHourEnd=0,RangeDaysBack=1"
t "PREV_D1 span 2"                     400 "$R,RangeMode=2,RangeDaySpan=2,RangeDaysBack=1"
t "PREV_D1 span 1"                     400 "$R,RangeMode=2,RangeDaySpan=1,RangeDaysBack=1"
t "limiti range 100-400"               400 "RequireRangeConfirmation=1,MinRangePoints=100,MaxRangePoints=400"
t "finestra 22-02 (cavallo)"           300 "$R,TradeHourStart=22,TradeHourEnd=2"
t "finestra 20-24"                     300 "$R,TradeHourStart=20,TradeHourEnd=24"
t "finestra 08:30-09:45 +90"           300 "$R,TradeHourStart=8,TradeMinuteStart=30,TradeHourEnd=9,TradeMinuteEnd=45,ExpireExtraMinutes=90"
t "ChaseIfBroken"                      300 "$R,ChaseIfBroken=1"
t "Chase + stops level 25"             300 "$R,ChaseIfBroken=1,StopsLevel=25"
t "stops level 15"                     300 "$R,StopsLevel=15"
t "offset 0"                           300 "$R,PendingOrderOffsetPoints=0"
t "offset 80"                          300 "$R,PendingOrderOffsetPoints=80"
t "TP spento (600h)"                   300 "$R,UseTakeProfit=0,InpMaxHoldHours=600"
t "BE spento"                          300 "$R,UsaBreakEven=0"
t "trailing spento"                    300 "$R,UsaTrailingStop=0"
t "SL/TP puri"                         300 "$R,UsaBreakEven=0,UsaTrailingStop=0"
t "trailing aggressivo SL40"           300 "$R,StopLossPoints=40,TakeProfitPoints=300,BreakEvenAttivazione=30,BreakEvenOffset=5,TrailingStartProfit=50,TrailingStep=10,TrailingOffset=20"
t "trailing stretto step grande"       300 "$R,StopLossPoints=150,TakeProfitPoints=500,UsaBreakEven=0,TrailingStartProfit=100,TrailingStep=60,TrailingOffset=15"
t "SL 250 TP 250 (600h)"               300 "$R,StopLossPoints=250,TakeProfitPoints=250,BreakEvenAttivazione=200,TrailingStartProfit=220,InpMaxHoldHours=600"
t "BARS d0 + SL largo (600h)"          300 "$R,RangeDaysBack=0,RangeBarsLookback=12,StopLossPoints=200,TakeProfitPoints=200,InpMaxHoldHours=600"
t "cavallo + SL largo (600h)"          300 "$R,TradeHourStart=22,TradeHourEnd=2,StopLossPoints=200,TakeProfitPoints=300,InpMaxHoldHours=600"
t "TIME 00-08 + SL largo (600h)"       300 "$R,RangeMode=1,RangeHourStart=0,RangeHourEnd=8,RangeDaysBack=0,StopLossPoints=200,TakeProfitPoints=300,InpMaxHoldHours=600"
t "M5"                                 100 "$R" M5
t "H1 lookback 8"                      400 "$R,RangeBarsLookback=8" H1
t "Timeframe esplicito H1"             300 "$R,Timeframe=16385,RangeBarsLookback=10"
t "kappa 0.03"                         300 "$R" M15 0.03
echo "---- OK $pass  DIFF $fail"
