#!/bin/bash
# uso: mdrb_run.sh <giorni> <kappa> "<override>" [TF]
export VPTF=${4:-M15} VPINP="$3,InpAuto=0" MDRB_NEW=0
D=$1; K=$2
rm -f mdrb_ea_*.csv mdrb_sc_*.csv
MDRB_QUIET=1 ./mdrb_study_san $D $K 0 >/dev/null 2>err_study.txt || { echo "ERRORE studio: $(head -3 err_study.txt)"; exit 2; }
./mdrb_ea $D $K 0 >/dev/null 2>err_ea.txt || { echo "ERRORE EA: $(head -3 err_ea.txt)"; exit 2; }
python3 mdrb_cmp.py 0.025 | grep -E "PIAZZAMENTI|TRADE|ESITO|dR|solo" | head -12
