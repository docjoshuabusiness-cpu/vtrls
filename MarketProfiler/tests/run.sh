#!/bin/sh
# Banco di prova: traduce il modulo MQL5 in C++, lo compila con controllo dei limiti degli array e lo esegue su serie sintetiche.
# Casi: pure (solo rumore: deve dare 0 falsi positivi robusti), plant (effetti piantati), gaps, sunday, novol, short, small, tiny.
set -e
cd "$(dirname "$0")"
python3 translate.py gen.cpp orig.mq5 ../MarketProfilerEdge.mqh
g++ -std=c++17 -O2 -Wall -Wextra -Wshadow -Wno-unused-parameter -Wno-sign-compare -o t driver.cpp 2>&1 | grep -E "gen.cpp.*(warning|error)" || true
for c in pure plant gaps sunday novol short small tiny; do ./t $c | grep -E "CASO|^test|FUORI"; done
node testpatch.js | head -3
