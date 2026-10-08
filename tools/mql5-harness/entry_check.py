#!/usr/bin/env python3
"""Controllo indipendente del PRIMO ingresso giornaliero dei concorrenti "chiusura" e "retest" dell'analisi virtuale
(SlotScan: sorgente del range x modalita' di entrata). Ricostruisce da zero, dai soli M1 grezzi, l'ingresso atteso di ogni
giorno e lo confronta col primo trade del CSV dei trade virtuali (la modalita' "stop" non viene controllata).

uso: entry_check.py <cartella> [--tf M5|M15|H1] [--offset PUNTI] [--tol PUNTI] [--win HH:MM-HH:MM] [--extra MIN]
                    [--first-hour H] [--slot-len ORE] [--slots N] [--days-back N] [--bars N] [--span N] [--no-bars-d1]
                    [--m1 FILE] [--trades FILE] [--max-diff N] [--full]
  <cartella>  contiene m1_dump.csv (time,open,high,low,close,spread; time = epoch "ora server" trattato come UTC naive)
              e trades.csv (source,mode,label,dir,part,topen,tclose,entry,exit,R,pts,range_pts)
  --offset    offset dei livelli di breakout in punti (default 20)      --tol    tolleranza del retest in punti (default 0)
  --win       finestra di entrata, ora server (default 10:00-11:00, anche a cavallo di mezzanotte)
  --extra     ExpireExtraMinutes: minuti oltre la fine finestra in cui l'ingresso e' ancora valutato (default 0)
  --first-hour/--slot-len  fasce 1..12: ore di partenza e durata in ore (default 0 e 2)
  --slots     quante fasce controllare (default min(12, 24/slot-len))
  --days-back RangeDaysBack (default 1)   --bars RangeBarsLookback (default 25)   --span RangeDaySpan (default 1)
  --no-bars-d1  non controlla le sorgenti 13 (range a barre) e 14 (D1 precedenti)
  --full      niente scorciatoia per saltare i minuti inerti: simula ogni tick (lento, per verificare lo script)

Modello: spread costante dalla colonna M1 (ask = bid + spread*0.00001), tick su percorso fisso e denso (passo mezzo punto,
open -> estremo piu' vicino -> estremo opposto -> close), un nuovo stato del giorno a mezzanotte, cancelli comuni (finestra
attiva, 1 trade al giorno, posizione aperta ricavata dal CSV, range pronto e valido), chiusura valutata solo al primo tick
di ogni barra del grafico, retest con armamento e ingresso su tick distinti. Vale il primo ingresso del giorno.
Confronto: stesso minuto di apertura, stessa direzione, prezzo entro 0.000015. I giorni in cui l'esito dipende
dall'istante (entro il minuto) di chiusura di una posizione del giorno prima sono "saltati" e contati a parte; di ciascuno
si stampa l'esito col minuto di chiusura tutto libero e tutto occupato e a quale ipotesi corrisponde il CSV.
Il CSV contiene solo trade chiusi: un ingresso atteso nell'ULTIMO giorno dei dati senza trade nel CSV puo' essere una posizione ancora
aperta a fine dati e viene contato a parte ("aperti a fine dati"), non come differenza.
Esce con 1 se ci sono differenze.
"""
import argparse, bisect, calendar, csv, math, sys, time
from collections import defaultdict

PT = 0.00001
STEP = 0.000005
STEP_LIM = STEP * 1.0000001
PRICE_TOL = 0.000015
TF_SEC = {"M1": 60, "M5": 300, "M15": 900, "M30": 1800, "H1": 3600, "H4": 14400}
MODES = ("chiusura", "retest")

ap = argparse.ArgumentParser()
ap.add_argument("folder")
ap.add_argument("--tf", default="M15")
ap.add_argument("--offset", type=float, default=20)
ap.add_argument("--tol", type=float, default=0)
ap.add_argument("--win", default="10:00-11:00")
ap.add_argument("--extra", type=int, default=0)
ap.add_argument("--first-hour", type=int, default=0)
ap.add_argument("--slot-len", type=int, default=2)
ap.add_argument("--slots", type=int, default=None)
ap.add_argument("--days-back", type=int, default=1)
ap.add_argument("--bars", type=int, default=25)
ap.add_argument("--span", type=int, default=1)
ap.add_argument("--no-bars-d1", action="store_true")
ap.add_argument("--m1", default=None)
ap.add_argument("--trades", default=None)
ap.add_argument("--max-diff", type=int, default=10)
ap.add_argument("--full", action="store_true")
ns = ap.parse_args()

P = TF_SEC[ns.tf.upper()]
OFFS = ns.offset * PT
TOLP = ns.tol * PT
NSLOT = ns.slots if ns.slots is not None else min(12, 24 // ns.slot_len)
m1_path = ns.m1 or ns.folder.rstrip("/") + "/m1_dump.csv"
tr_path = ns.trades or ns.folder.rstrip("/") + "/trades.csv"
w0, w1 = ns.win.split("-")
START_MIN = int(w0[:2]) * 60 + int(w0[3:5])
END_MIN = int(w1[:2]) * 60 + int(w1[3:5])
WIN_LEN = (END_MIN - START_MIN + 1440) % 1440
ACT_LEN = WIN_LEN + ns.extra


def norm(p):
    return math.floor(p / PT + 0.5) * PT


def fmt(t):
    return time.strftime("%Y.%m.%d %H:%M", time.gmtime(t))


def ts(x):
    return calendar.timegm(time.strptime(x, "%Y.%m.%d %H:%M"))


# ---------------------------------------------------------------- dati M1, barre del grafico, barre D1
T, O, H, L, C, S = [], [], [], [], [], []
with open(m1_path) as f:
    rd = csv.reader(f)
    next(rd)
    for r in rd:
        T.append(int(r[0])); O.append(float(r[1])); H.append(float(r[2])); L.append(float(r[3])); C.append(float(r[4])); S.append(int(r[5]))
N = len(T)
if any(T[i] <= T[i - 1] for i in range(1, N)):
    sys.exit("m1_dump.csv non e' in ordine temporale stretto")

bt, bh, bl, bc = [], [], [], []      # barre del grafico: apertura, high, low, close (close dell'ultimo M1)
bar_of = [0] * N
first_of_bar = [False] * N
cur_b = None
for i in range(N):
    b = T[i] // P * P
    if b != cur_b:
        cur_b = b
        bt.append(b); bh.append(H[i]); bl.append(L[i]); bc.append(C[i])
        first_of_bar[i] = True
    else:
        if H[i] > bh[-1]:
            bh[-1] = H[i]
        if L[i] < bl[-1]:
            bl[-1] = L[i]
        bc[-1] = C[i]
    bar_of[i] = len(bt) - 1

days, dh, dl, drow = [], [], [], []  # giorni D1 con dati: inizio, high, low, (primo indice M1, fine)
for i in range(N):
    d = T[i] // 86400 * 86400
    if not days or days[-1] != d:
        days.append(d); dh.append(H[i]); dl.append(L[i]); drow.append([i, i + 1])
    else:
        dh[-1] = max(dh[-1], H[i]); dl[-1] = min(dl[-1], L[i]); drow[-1][1] = i + 1
day_idx = {d: k for k, d in enumerate(days)}

win_off = [((T[i] // 60) % 1440 - START_MIN + 1440) % 1440 for i in range(N)]
act_rows, nb_rows = [], []           # per giorno: righe M1 con finestra attiva; quelle che aprono una barra del grafico
for k in range(len(days)):
    a, b = drow[k]
    rows = [i for i in range(a, b) if win_off[i] < ACT_LEN]
    act_rows.append(rows)
    nb_rows.append([i for i in rows if first_of_bar[i]])


# ---------------------------------------------------------------- sorgenti di range
def slot_start(src):
    return (ns.first_hour * 60 + (src - 1) * ns.slot_len * 60) % 1440


def slot_label(src):
    s = slot_start(src)
    e = s + ns.slot_len * 60
    return "%02d:%02d-%02d:%02d" % (s // 60, s % 60, e // 60, e % 60)


def range_for(src, di):
    """(hi, lo, istante dal quale il range e' pronto) oppure None se non disponibile/non valido."""
    ri = di - ns.days_back
    if ri < 0:
        return None
    rif = days[ri]
    if src <= 12:
        ws = rif + slot_start(src) * 60
        we = ws + ns.slot_len * 3600
        a, b = bisect.bisect_left(bt, ws), bisect.bisect_left(bt, we)
        if b <= a:
            return None
        hi, lo, rdy = max(bh[a:b]), min(bl[a:b]), we
    elif src == 13:
        if ns.days_back < 1:
            return None
        e = di - (ns.days_back - 1)
        jb = bisect.bisect_right(bt, days[e] - 1) - 1
        a = jb - ns.bars + 1
        if a < 0:
            return None
        hi, lo, rdy = max(bh[a:jb + 1]), min(bl[a:jb + 1]), 0
    else:
        if ns.days_back < 1:
            return None
        idx = [di - ns.days_back - j for j in range(ns.span)]
        if min(idx) < 0:
            return None
        hi, lo, rdy = max(dh[j] for j in idx), min(dl[j] for j in idx), 0
    return (hi, lo, rdy) if hi > lo else None


sources = list(range(1, NSLOT + 1))
if not ns.no_bars_d1 and ns.days_back >= 1:
    sources += [13, 14]


def src_label(src):
    if src <= 12:
        return slot_label(src)
    return "barre%d" % ns.bars if src == 13 else "D1x%d" % ns.span


# ---------------------------------------------------------------- trade del CSV
csv_rows = defaultdict(list)             # (sorgente, modalita') -> [(topen, tclose, dir, entry)]
csv_label = {}
with open(tr_path) as f:
    for r in csv.DictReader(f):
        if r["mode"] in MODES:
            k = (int(r["source"]), r["mode"])
            csv_rows[k].append((ts(r["topen"]), ts(r["tclose"]), int(r["dir"]), float(r["entry"])))
            csv_label[int(r["source"])] = r["label"]
for k in csv_rows:
    csv_rows[k].sort()

# posizioni aperte da giorni precedenti: per (concorrente, giorno) elenco di (apertura, chiusura) in minuti
carry = {}
for k, lst in csv_rows.items():
    dct = defaultdict(list)
    for a, b, _, _ in lst:
        da = a // 86400 * 86400
        for dd in range(da + 86400, b // 86400 * 86400 + 1, 86400):
            dct[dd].append((a, b))
    carry[k] = dct


def pos_state(rel, m):
    """0 libera, 1 posizione aperta (topen <= m < tclose), 2 ambiguo (il minuto m e' quello di chiusura)."""
    st = 0
    for a, b in rel:
        if a <= m < b:
            return 1
        if m == b:
            st = 2
    return st


def tick_prices(o, h, l, c):
    out = [o]
    keys = (h, l, c) if (h - o) <= (o - l) else (l, h, c)
    cur = o
    for tg in keys:
        while True:
            d = tg - cur
            if abs(d) <= STEP_LIM:
                out.append(tg); cur = tg
                break
            cur = cur + STEP if d > 0 else cur - STEP
            out.append(cur)
    return out


# ---------------------------------------------------------------- ricostruzione degli ingressi attesi
# Ogni run_* restituisce None (nessun ingresso), (minuto, dir, prezzo) oppure "ambiguo" se l'esito del giorno dipende
# dall'istante di chiusura (dentro il minuto) di una posizione del giorno prima. Con amb=0/1 il minuto ambiguo viene
# invece considerato libero/occupato per intero (usato solo per dire a quale ipotesi corrisponde il CSV).
def run_chiusura(di, rel, up, dn, rdy, amb):
    for i in nb_rows[di]:
        m = T[i]
        if m < rdy:
            continue
        st = pos_state(rel, m) if rel else 0
        if st == 2 and amb is not None:
            st = amb
        if st == 1:
            continue
        k = bar_of[i]
        if k == 0:
            continue
        if bt[k - 1] + P <= m - win_off[i] * 60:
            continue
        c = bc[k - 1]
        if c - up > 0.00000001:
            d, px = 1, O[i] + S[i] * PT
        elif dn - c > 0.00000001:
            d, px = -1, O[i]
        else:
            continue
        return "ambiguo" if st == 2 else (m, d, px)
    return None


def run_retest(di, rel, hi, lo, up, dn, rdy, amb):
    armL = armS = False
    prev = -2
    for i in act_rows[di]:
        if i != prev + 1:               # tra le due righe c'e' stato almeno un minuto fuori finestra
            armL = armS = False
        prev = i
        m = T[i]
        st = pos_state(rel, m) if rel else 0
        if st == 2 and amb is not None:
            st = amb
        if st == 1:
            armL = armS = False
            continue
        if m < rdy:
            continue
        o, h, l, c = O[i], H[i], L[i], C[i]
        sp = S[i] * PT
        if not ns.full:
            mx, mn = max(o, h, l, c), min(o, h, l, c)
            if not ((not armL and mx + sp >= up - 1e-8) or (not armS and mn <= dn + 1e-8)
                    or (armL and mn <= hi + TOLP + 1e-8) or (armS and mx + sp >= lo - TOLP - 1e-8)):
                continue
        L0, S0 = armL, armS
        res = None
        for bid in tick_prices(o, h, l, c):
            ask = bid + sp
            if armL and bid <= hi + TOLP + 1e-9:
                res = (m, 1, ask)
                break
            if armS and ask >= lo - TOLP - 1e-9:
                res = (m, -1, bid)
                break
            if ask >= up - 1e-9:
                armL = True
            if bid <= dn + 1e-9:
                armS = True
        if st == 2:                     # ambiguo: se nel minuto cambia qualcosa l'esito non e' determinabile
            if res is not None or armL != L0 or armS != S0:
                return "ambiguo"
            continue
        if res is not None:
            return res
    return None


exp = defaultdict(dict)                  # (src, modo) -> {giorno: (minuto, dir, prezzo)}
skipped = defaultdict(dict)              # (src, modo) -> {giorno: (esito se il minuto ambiguo e' libero, esito se occupato)}
for di in range(len(days)):
    if not act_rows[di]:
        continue
    for src in sources:
        r = range_for(src, di)
        if r is None:
            continue
        hi, lo, rdy = r
        up, dn = norm(hi + OFFS), norm(lo - OFFS)
        for mode in MODES:
            key = (src, mode)
            rel = carry.get(key, {}).get(days[di])
            if mode == "chiusura":
                run = lambda amb: run_chiusura(di, rel, up, dn, rdy, amb)
            else:
                run = lambda amb: run_retest(di, rel, hi, lo, up, dn, rdy, amb)
            res = run(None)
            if res == "ambiguo":
                skipped[key][days[di]] = (run(0), run(1))
            elif res is not None:
                exp[key][days[di]] = res

# ---------------------------------------------------------------- confronto
print("controllo ingressi: %s | tf %s offset %g tol %g finestra %s extra %d fasce %dh dalle %d (n=%d) days_back %d bars %d span %d%s" % (
    ns.folder, ns.tf.upper(), ns.offset, ns.tol, ns.win, ns.extra, ns.slot_len, ns.first_hour, NSLOT, ns.days_back,
    ns.bars, ns.span, "" if (not ns.no_bars_d1 and ns.days_back >= 1) else " (senza 13/14)"))
print("M1 %d, barre %s %d, giorni D1 %d" % (N, ns.tf.upper(), len(bt), len(days)))
def same(e, c):
    return e is not None and c is not None and e[0] == c[0] and e[1] == c[1] and abs(e[2] - c[2]) <= PRICE_TOL


def show(e):
    return "nessun ingresso" if e is None else "%s %+d %.5f" % (fmt(e[0])[11:], e[1], e[2])


diffs, skip_list = [], []
tot = defaultdict(int)
zero = []
maxdp = 0.0
for src in sources:
    for mode in MODES:
        key = (src, mode)
        rows = csv_rows.get(key, [])
        by_day = defaultdict(list)
        for a, b, d, e in rows:
            by_day[a // 86400 * 86400].append((a, d, e))
        ex, sk = exp.get(key, {}), skipped.get(key, {})
        ok = nd = ns_ = nopen = 0
        for day in sorted(set(ex) | set(by_day) | set(sk)):
            tag = "%s %d %s %s" % (mode, src, src_label(src), fmt(day)[:10])
            if day in sk:
                ns_ += 1
                fr, oc = sk[day]
                cc = min(by_day[day])[:3] if day in by_day else None
                cc = None if cc is None else (cc[0], cc[1], cc[2])
                comp = [n for n, x in (("libero", fr), ("occupato", oc)) if (x is None and cc is None) or same(x, cc)]
                skip_list.append("%s: CSV %s ; minuto di chiusura libero -> %s ; occupato -> %s ; compatibile con: %s" % (
                    tag, show(cc), show(fr), show(oc), "/".join(comp) if comp else "nessuna delle due (esito intermedio?)"))
                continue
            e, c = ex.get(day), by_day.get(day)
            if e and c:
                a, d, px = min(c)[0], min(c)[1], min(c)[2]
                if e[0] == a and e[1] == d and abs(e[2] - px) <= PRICE_TOL:
                    ok += 1
                    maxdp = max(maxdp, abs(e[2] - px))
                else:
                    nd += 1
                    diffs.append("%s: atteso %s dir %+d prezzo %.5f ; CSV %s dir %+d prezzo %.5f" % (
                        tag, fmt(e[0])[11:], e[1], e[2], fmt(a)[11:], d, px))
                if len(c) > 1:
                    nd += 1
                    diffs.append("%s: %d trade aperti lo stesso giorno nel CSV (MaxTradesPerDay=1)" % (tag, len(c)))
            elif e and day == days[-1]:
                nopen += 1   # ultimo giorno dei dati: il CSV contiene solo trade chiusi, la posizione puo' essere ancora aperta
            elif e:
                nd += 1
                diffs.append("%s: atteso %s dir %+d prezzo %.5f ; CSV nessun trade" % (tag, fmt(e[0])[11:], e[1], e[2]))
            else:
                nd += 1
                diffs.append("%s: nessun ingresso atteso ; CSV %s dir %+d prezzo %.5f" % (
                    tag, fmt(min(c)[0])[11:], min(c)[1], min(c)[2]))
        csv_days = len([1 for d in by_day if d not in sk])
        print("%-8s %2d %-11s atteso %3d | CSV giorni %3d (righe %3d) | ok %3d | differenze %d | saltati %d | aperti a fine dati %d" % (
            mode, src, csv_label.get(src, src_label(src)), len(ex), csv_days, len(rows), ok, nd, ns_, nopen))
        tot["atteso"] += len(ex); tot["csv"] += csv_days; tot["ok"] += ok; tot["diff"] += nd; tot["saltati"] += ns_; tot["fine"] += nopen
        if len(ex) == 0 and csv_days == 0:
            zero.append("%s %d" % (mode, src))
print("TOTALE: atteso %d, CSV giorni %d, ok %d, differenze %d, saltati %d, aperti a fine dati %d (max|dprezzo| sugli ok %.6f)" % (
    tot["atteso"], tot["csv"], tot["ok"], tot["diff"], tot["saltati"], tot["fine"], maxdp))
if zero:
    print("concorrenti con 0 giorni confrontati (ne' atteso ne' CSV): " + ", ".join(zero))
for d in diffs[:ns.max_diff]:
    print("   -", d)
if len(diffs) > ns.max_diff:
    print("   ... altre %d differenze" % (len(diffs) - ns.max_diff))
for s_ in skip_list[:ns.max_diff]:
    print("   saltato:", s_)
if len(skip_list) > ns.max_diff:
    print("   ... altri %d giorni saltati" % (len(skip_list) - ns.max_diff))
sys.exit(1 if diffs else 0)
