#!/bin/sh
# Compila il banco di prova del modulo Candele
set -e
cd "$(dirname "$0")"
python3 ../dash/build_dash_mqh.py > /dev/null
python3 mksubset.py ../MarketProfiler.mq5 orig2.mq5 >/dev/null
python3 translate.py gen.cpp orig.mq5 orig2.mq5 ../MarketProfilerEdge.mqh ../MarketProfilerCandle.mqh ../MarketProfilerDash.mqh
g++ -std=c++17 -O1 -Wall -Wextra -Wshadow -Wno-unused-parameter -Wno-sign-compare -o tc driver2.cpp 2>&1 | grep -E "error|warning" || true
