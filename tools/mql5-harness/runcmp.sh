#!/bin/bash
# Confronta i segnali tecnici dell'EA reale con gli eventi dello script sugli STESSI dati sintetici.
# uso: runcmp.sh <TF: M5|M15|H1> "<override: InpX=v,...>" <giorni> <kappa>
export VPTF="$1" VPINP="$2"
D=${3:-120}; K=${4:-0.002}
rm -f ea_signals.csv out/MQL5/Files/*events.csv
./ea_run $D $K 3 2>/dev/null
./study_nosan 3 $D $K >/dev/null 2>&1
python3 - "$1" <<'PY'
import csv, glob, sys
tf = sys.argv[1]
eas = set((r['time'], int(r['dir'])) for r in csv.DictReader(open('ea_signals.csv')))
f = glob.glob('out/MQL5/Files/*events.csv')[0]
scs = set((r['time'], int(r['dir'])) for r in csv.DictReader(open(f)))
hi = max(t for t, _ in scs)
lo2 = sorted(scs)[0][0][:8] + '05'          # salta i primi giorni (l'EA richiede 100 barre di storia)
ine = [x for x in eas if lo2 <= x[0] <= hi]; ins = [x for x in scs if lo2 <= x[0] <= hi]
oe = sorted(set(ine) - set(ins)); os_ = sorted(set(ins) - set(ine))
status = "OK " if not oe and not os_ else "DIFF"
print(f"{status} {tf:4s} da {lo2} | EA {len(ine):5d}  script {len(ins):5d} | solo-EA {len(oe)}  solo-script {len(os_)}", oe[:3], os_[:3])
sys.exit(0 if not oe and not os_ else 1)
PY
