#!/bin/sh
# Banco di prova di MultiDayRangeBreakout: traduce l'EA in C++ (traduttore di MarketProfiler), lo compila contro il finto MT5 (ea_rt.h) e lo esegue su serie sintetiche.
# Uso: ./run.sh            esegue tutte le prove della v3 e il confronto con la v2
#      ./run.sh v3 range   una sola prova
set -e
cd "$(dirname "$0")"
T=../../../MarketProfiler/tests/translate.py
python3 $T gen_v3.cpp ../MultiDayRangeBreakout.mq5
python3 $T gen_v2.cpp v2_originale.mq5
FL="-std=c++17 -O2 -Wall -Wextra -Wshadow -Wno-unused-parameter -Wno-sign-compare"
g++ $FL -o t_v3 driver.cpp 2>&1 | grep -E "(gen_v3|driver|ea_rt)\.(cpp|h).*(warning|error)" || true
g++ $FL -DEA_V2 -o t_v2 driver.cpp 2>&1 | grep -E "(gen_v2|driver|ea_rt)\.(cpp|h).*(warning|error)" || true
if [ -n "$2" ]; then ./t_$1 "$2"; exit 0; fi
for s in range life held stops spam manage restart spread chase expiry random pnl; do ./t_v3 $s; done
echo "##### v2.00 (originale), stesse prove"
for s in range life held stops spam logs; do ./t_v2 $s; done
