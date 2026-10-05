#!/usr/bin/env python3
"""Test nullo / di potenza della modalita' AUTO. Sotto il nullo (random walk, costi zero) i vincitori scelti sull'IS devono
avere OOS ~ rumore: la t OOS media (vincitori con >=20 trade OOS) deve restare vicina a 0 (soglia 0.30: un leak IS/OOS grossolano la
porta a ~+0.7, uno lieve a ~+0.4) e le conferme OOS devono essere poche (il simulatore ha un drift lievemente negativo: attese ~1/36)."""
import csv, math, os, subprocess, sys
days, kappa, seeds, spread = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
max_conf = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] != "-" else None     # nullo: massimo di vincitori confermati OOS
min_daily = int(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] != "-" else None    # potenza: minimo di vincitori giornalieri confermati
tf = os.environ.get("VPTF", "M15")
F = "out/MQL5/Files/"
def pnorm_up(z): return 0.5 * math.erfc(z / math.sqrt(2))
n = conf = isflag = 0
tclip = []
oos_pos = 0
per_cls = {}
for sd in range(seeds):
    env = dict(os.environ, VPINP=f"InpSpreadPoints={spread}", VPTF=tf, MDRB_QUIET="1", GEN_ROUND="1e7")
    subprocess.run(["./mdrb_study_fast", days, kappa, str(sd)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    rows = list(csv.DictReader(open(F + "MDRB_Study_EURUSD_map.csv")))
    valid = {}
    for r in rows:
        if r["cfg"] == "PT_ref" and r["valid"] == "1": valid[r["class"]] = valid.get(r["class"], 0) + 1
    for r in rows:
        if r["cfg"] != "PT_ref" or r["winner"] != "1": continue
        t_oos, n_oos, er_oos, t_is = float(r["t_oos"]), int(r["n_oos"]), float(r["er_oos"]), float(r["t_is"])
        p = pnorm_up(t_oos)
        K = valid[r["class"]]
        # soglia di Bonferroni: z tale che P(Z>z)=0.05/K
        lo, hi = 0.0, 10.0
        for _ in range(60):
            mid = (lo + hi) / 2
            if pnorm_up(mid) > 0.05 / K: lo = mid
            else: hi = mid
        tcrit = lo
        n += 1
        if n_oos >= 20: tclip.append(max(-5.0, min(5.0, t_oos)))
        c = (er_oos > 0 and p < 0.05 and n_oos >= 30)
        conf += c
        isflag += (t_is >= tcrit)
        oos_pos += (er_oos > 0)
        d = per_cls.setdefault(r["class"], [0, 0])
        d[0] += 1; d[1] += c
        print(f"seed {sd} {r['class']:12s} K={K:4d} IS t={t_is:5.2f} (crit {tcrit:4.2f}) | OOS N={n_oos:3d} E[R]={er_oos:+.3f} t={t_oos:+.2f} p={p:.3f} {'CONFERMATO' if c else ''}")
mt = sum(tclip) / len(tclip) if tclip else 0.0
print(f"\nvincitori valutati {n}; confermati OOS (p<5%): {conf} ({100*conf/max(1,n):.1f}%, sotto il nullo atteso ~3%); IS sopra Bonferroni: {isflag}; OOS E[R]>0: {oos_pos} ({100*oos_pos/max(1,n):.0f}%); t OOS media (N>=20): {mt:+.2f}")
for k, v in per_cls.items(): print(f"  {k}: {v[1]}/{v[0]}")

rc = 0
if max_conf is not None and mt > 0.30:
    print(f"FALLITO: t OOS media dei vincitori {mt:+.2f} > +0.30 (possibile leak IS/OOS nella scelta)"); rc = 1
if max_conf is not None and isflag > max(2, int(0.1 * n)):
    print(f"FALLITO: troppi vincitori sopra la soglia di Bonferroni sull'IS sotto il nullo ({isflag})"); rc = 1
if max_conf is not None and conf > max_conf:
    print(f"FALLITO: troppi vincitori confermati sotto il nullo ({conf} > {max_conf})"); rc = 1
if min_daily is not None and per_cls.get("giornaliero", [0, 0])[1] < min_daily:
    print(f"FALLITO: potenza insufficiente (giornalieri confermati {per_cls.get('giornaliero', [0, 0])[1]} < {min_daily})"); rc = 1
sys.exit(rc)
