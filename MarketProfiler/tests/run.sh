#!/bin/sh
# Banco di prova: traduce i moduli MQL5 in C++, li compila con controllo dei limiti degli array e li esegue su serie sintetiche.
# Modulo Edge (driver.cpp), casi: pure (solo rumore: deve dare 0 falsi positivi robusti), plant (effetti piantati), gaps, sunday, novol, short, small, tiny.
# Modulo Candele (driver2.cpp), casi: cplant (effetti piantati), cnull e cnullv (rumore: 0 falsi positivi di direzione), csun, cgap, cnovol, cm5, ctiny.
# Indicatori e pattern (driver3.cpp, driver4.cpp): confronto con calcoli indipendenti e con candele costruite a mano.
set -e
cd "$(dirname "$0")"
python3 ../dash/build_dash_mqh.py > /dev/null
python3 mksubset.py ../MarketProfiler.mq5 orig2.mq5 > /dev/null
python3 translate.py gen.cpp orig.mq5 orig2.mq5 ../MarketProfilerEdge.mqh ../MarketProfilerCandle.mqh ../MarketProfilerDash.mqh
FL="-std=c++17 -O2 -Wall -Wextra -Wshadow -Wno-unused-parameter -Wno-sign-compare"
g++ $FL -o t driver.cpp 2>&1 | grep -E "gen.cpp.*(warning|error)" || true
g++ $FL -o tc driver2.cpp 2>&1 | grep -E "gen.cpp.*(warning|error)" || true
g++ $FL -o t3 driver3.cpp 2>&1 | grep -E "gen.cpp.*(warning|error)" || true
g++ $FL -o t4 driver4.cpp 2>&1 | grep -E "gen.cpp.*(warning|error)" || true
echo "##### Modulo Edge"
for c in pure plant gaps sunday novol short small tiny; do ./t $c | grep -E "CASO|^test|FUORI"; done
echo "##### Modulo Candele"
for c in cplant cnull cnullv csun cgap cnovol cm5 ctiny; do ./tc $c | grep -E "CASO|^oltre|^  famiglia|^z delle|FUORI"; done
echo "##### Indicatori"
./t3 | grep -E "differenze|errore massimo|esiti"
echo "##### Pattern e forme (errori: $(./t4 | grep -c ERRORE))"
node testpatch.js | head -3
