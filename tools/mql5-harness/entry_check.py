#!/usr/bin/env python3
"""Controllo indipendente del PRIMO ingresso giornaliero dei concorrenti "chiusura" e "retest" dell'analisi virtuale
(SlotScan: sorgente del range x modalita' di entrata). Ricostruisce da zero, dai soli M1 grezzi, l'ingresso atteso di ogni
giorno e lo confronta col primo trade del CSV dei trade virtuali (la modalita' "stop" non viene controllata).

uso: entry_check.py <cartella> [--tf M5|M15|H1] [--offset PUNTI] [--tol PUNTI] [--depth PUNTI] [--win HH:MM-HH:MM]
                    [--extra MIN] [--first-hour H] [--slot-len ORE] [--slots N] [--days-back N] [--bars N] [--span N]
                    [--no-bars] [--no-d1] [--no-bars-d1] [--retry SEC] [--m1 FILE] [--trades FILE] [--max-diff N] [--full]
  <cartella>  contiene m1_dump.csv (time,open,high,low,close,spread; time = epoch "ora server" trattato come UTC naive)
              e trades.csv (source,mode,label,dir,part,topen,tclose,entry,exit,R,pts,range_pts)
  --offset    offset dei livelli di breakout in punti (default 20)      --tol    tolleranza del retest in punti (default 0)
  --depth     RetestMaxDepthPoints: oltre questa profondita' dentro il range la rottura e' fallita (default 50)
  --win       finestra di entrata, ora server (default 10:00-11:00, anche a cavallo di mezzanotte)
  --extra     ExpireExtraMinutes: minuti oltre la fine finestra ancora considerati "dentro" (default 0)
  --first-hour/--slot-len  fasce 1..12: ore di partenza e durata in ore (default 0 e 2)
  --slots     quante fasce controllare (default min(12, 24/slot-len))
  --days-back RangeDaysBack (default 1)   --bars RangeBarsLookback (default 25)   --span RangeDaySpan (default 1)
  --no-bars   non controlla la sorgente 13 (range a barre)    --no-d1   non controlla la sorgente 14 (D1 precedenti;
              con days_back = 0 non esiste comunque)           --no-bars-d1  scorciatoia per entrambe
  --retry     secondi tra i tentativi di calcolo del range quando non e' pronto (default 10; serve alle prove di sensibilita')
  --full      niente scorciatoia per i minuti inerti del retest e verifica del conteggio dei tick: lento, serve a collaudare

Modello: spread dalla colonna M1 (ask = bid + spread*0.00001); tick su percorso fisso e denso (passo mezzo punto, open ->
estremo piu' vicino -> estremo opposto -> close; il k-esimo tick del minuto ha tempo t0 + min(k,59); l'open puo' differire dal
close precedente); stato del giorno azzerato a mezzanotte (trade, armamenti, pend, nextTry, range calcolato). Per concorrente,
a ogni tick, nell'ordine:
 (a) chiusura: primo tick di una nuova barra del grafico (il primissimo tick conta) -> pend; (b) inWin = WinOffset(now) <
 WinLen + extra; retest fuori finestra: armamenti spenti; (c) niente se non inWin e non pend; (d) 1 trade al giorno;
 (e) posizione aperta (dal CSV: trade di giorni precedenti con topen <= minuto < tclose): armamenti e pend spenti;
 (f) niente se now < nextTry; (g1) range non ancora calcolato e fuori finestra: pend spento, niente (il range non si calcola
 mai fuori finestra); (g2) range non ancora calcolato e in finestra: si calcola a questo tick, se non e' pronto (we > now,
 solo con days_back = 0) nextTry = now + 10 s e niente; (h) range non valido: niente; (i) retest in finestra: logica retest;
 se non scatta e pend: si valuta la candela; (j) ingresso al prezzo del tick (long ask, short bid).
 Retest (tutto sul bid): se armL: bid < hi - depth -> armL spento, altrimenti bid <= hi + tol -> ingresso long (ask); poi
 se armS: bid > lo + depth -> armS spento, altrimenti bid >= lo - tol -> ingresso short (bid); se nessun ingresso: bid >= up
 arma il long, bid <= dn arma lo short (armamento e ingresso mai nello stesso tick; gli armamenti si accendono soltanto).
 Chiusura: la candela e' quella precedente la barra corrente e vale solo se contigua (apertura + periodo = apertura della barra
 corrente), non chiude a mezzanotte (tc % 86400 != 0) e il suo ultimo secondo tl = tc - 1 cade nella finestra piu' extra
 (WinOffset(tl) < WinLen + extra); long se close - up > 1e-8, short se dn - close > 1e-8; senza segnale pend si spegne.
Sorgenti: fasce 1..12 (barre TF della fascia del giorno di riferimento), 13 (ultime `bars` barre: con days_back >= 1 fino
alla fine del giorno di riferimento; con days_back = 0 le `bars` barre che precedono nella serie quella del tick di calcolo),
14 (D1, solo days_back >= 1).
Vale il primo ingresso del giorno. Confronto: stesso minuto di apertura, stessa direzione, prezzo entro 0.000015.
I giorni in cui l'esito dipende dall'istante (dentro il minuto) di chiusura di una posizione del giorno prima (esito diverso
tra minuto tutto libero e tutto occupato) sono "saltati" e contati a parte; di ciascuno si stampano i due esiti e a quale
corrisponde il CSV. Se i due esiti coincidono il giorno e' confrontato normalmente (e contato tra gli "ambigui determinati").
Il CSV contiene solo trade chiusi: un ingresso atteso nell'ULTIMO giorno dei dati senza trade nel CSV puo' essere una
posizione ancora aperta a fine dati e viene contato a parte ("aperti a fine dati"), non come differenza.
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
ap.add_argument("--depth", type=float, default=50)
ap.add_argument("--win", default="10:00-11:00")
ap.add_argument("--extra", type=int, default=0)
ap.add_argument("--first-hour", type=int, default=0)
ap.add_argument("--slot-len", type=int, default=2)
ap.add_argument("--slots", type=int, default=None)
ap.add_argument("--days-back", type=int, default=1)
ap.add_argument("--bars", type=int, default=25)
ap.add_argument("--span", type=int, default=1)
ap.add_argument("--no-bars", action="store_true")
ap.add_argument("--no-d1", action="store_true")
ap.add_argument("--no-bars-d1", action="store_true")
ap.add_argument("--retry", type=int, default=10)
ap.add_argument("--m1", default=None)
ap.add_argument("--trades", default=None)
ap.add_argument("--max-diff", type=int, default=10)
ap.add_argument("--full", action="store_true")
ns = ap.parse_args()
if ns.no_bars_d1:
    ns.no_bars = ns.no_d1 = True

P = TF_SEC[ns.tf.upper()]
OFFS = ns.offset * PT
TOLP = ns.tol * PT
DEPTH = ns.depth * PT
NSLOT = ns.slots if ns.slots is not None else min(12, 24 // ns.slot_len)
m1_path = ns.m1 or ns.folder.rstrip("/") + "/m1_dump.csv"
tr_path = ns.trades or ns.folder.rstrip("/") + "/trades.csv"
w0, w1 = ns.win.split("-")
START_MIN = int(w0[:2]) * 60 + int(w0[3:5])
END_MIN = int(w1[:2]) * 60 + int(w1[3:5])
WIN_LEN = (END_MIN - START_MIN + 1440) % 1440
ACT_LEN = WIN_LEN + ns.extra
if ns.offset <= ns.tol:
    print("attenzione: la specifica richiede offset > tol")


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

inwin_a = [((T[i] // 60) % 1440 - START_MIN + 1440) % 1440 < ACT_LEN for i in range(N)]
next_nb = [N] * (N + 1)              # prossimo M1 che apre una barra del grafico
next_in = [N] * (N + 1)              # prossimo M1 dentro la finestra
for i in range(N - 1, -1, -1):
    next_nb[i] = i + 1 if (i + 1 < N and first_of_bar[i + 1]) else next_nb[i + 1]
    next_in[i] = i + 1 if (i + 1 < N and inwin_a[i + 1]) else next_in[i + 1]


def candle_close(i):
    """close della candela precedente la barra del tick, se vale: contigua, non chiusa a mezzanotte, ultimo secondo in finestra."""
    kb = bar_of[i]
    if kb == 0:
        return None
    tc = bt[kb - 1] + P
    if tc != bt[kb] or tc % 86400 == 0 or ((tc - 1) // 60 % 1440 - START_MIN) % 1440 >= ACT_LEN:
        return None
    return bc[kb - 1]


cclose = [None] * N                  # candela valida all'apertura di ogni barra
NONCONT = 0                          # candele valide per finestra e mezzanotte ma non contigue (solo statistica)
for i in range(N):
    if first_of_bar[i] and bar_of[i] > 0:
        cclose[i] = candle_close(i)
        if cclose[i] is None:
            kb = bar_of[i]
            tc = bt[kb - 1] + P
            if tc != bt[kb] and tc % 86400 != 0 and ((tc - 1) // 60 % 1440 - START_MIN) % 1440 < ACT_LEN:
                NONCONT += 1

days, dh, dl, drow = [], [], [], []  # giorni D1 con dati: inizio, high, low, (primo indice M1, fine)
for i in range(N):
    d = T[i] // 86400 * 86400
    if not days or days[-1] != d:
        days.append(d); dh.append(H[i]); dl.append(L[i]); drow.append([i, i + 1])
    else:
        dh[-1] = max(dh[-1], H[i]); dl[-1] = min(dl[-1], L[i]); drow[-1][1] = i + 1

act_rows = []                        # per giorno: righe M1 con finestra attiva
for k in range(len(days)):
    a, b = drow[k]
    act_rows.append([i for i in range(a, b) if inwin_a[i]])

DYN = ("dinamico",)                  # sorgente 13 con days_back = 0: il range si calcola al tick di calcolo


# ---------------------------------------------------------------- sorgenti di range
def slot_start(src):
    return (ns.first_hour * 60 + (src - 1) * ns.slot_len * 60) % 1440


def slot_label(src):
    s = slot_start(src)
    e = s + ns.slot_len * 60
    return "%02d:%02d-%02d:%02d" % (s // 60, s % 60, e // 60, e % 60)


def range_for(src, di):
    """(hi, lo, we, up, dn), DYN oppure None se non disponibile/non valido; we = istante dal quale il range e' pronto."""
    if src == 13 and ns.days_back == 0:
        return DYN
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
        hi, lo = max(bh[a:b]), min(bl[a:b])
    elif src == 13:
        e = di - (ns.days_back - 1)
        jb = bisect.bisect_right(bt, days[e] - 1) - 1
        a = jb - ns.bars + 1
        if a < 0:
            return None
        hi, lo, we = max(bh[a:jb + 1]), min(bl[a:jb + 1]), 0
    else:
        if ns.days_back < 1:
            return None
        idx = [di - ns.days_back - j for j in range(ns.span)]
        if min(idx) < 0:
            return None
        hi, lo, we = max(dh[j] for j in idx), min(dl[j] for j in idx), 0
    if not hi > lo:
        return None
    return (hi, lo, we, norm(hi + OFFS), norm(lo - OFFS))


def dyn_range(i):
    """sorgente 13 con days_back = 0: le `bars` barre che precedono nella serie quella del tick di calcolo (riga i)."""
    kb = bar_of[i]
    a = kb - ns.bars
    if a < 0:
        return None
    hi, lo = max(bh[a:kb]), min(bl[a:kb])
    return (hi, lo, 0, norm(hi + OFFS), norm(lo - OFFS)) if hi > lo else None


sources = list(range(1, NSLOT + 1))
if not ns.no_bars:
    sources.append(13)
if not ns.no_d1 and ns.days_back >= 1:
    sources.append(14)


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


# ---------------------------------------------------------------- tick
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


NT = [0] * N


def ntick(i):
    """numero di tick del minuto, in forma chiusa (verificato contro tick_prices con --full)."""
    n = NT[i]
    if n:
        return n
    o, h, l, c = O[i], H[i], L[i], C[i]
    keys = (h, l, c) if (h - o) <= (o - l) else (l, h, c)
    n, cur = 1, o
    for tg in keys:
        s = math.ceil(abs(tg - cur) / STEP - 1.0000001)
        n += (s if s > 0 else 0) + 1
        cur = tg
    if ns.full and n != len(tick_prices(o, h, l, c)):
        sys.exit("conteggio dei tick incoerente alla riga %d" % i)
    NT[i] = n
    return n


def tick_k(t0, nt, next_try):
    """indice del primo tick del minuto con tempo >= next_try (None se non ce n'e')."""
    o = next_try - t0
    if o <= 0:
        k = 0
    elif o <= 59:
        k = o
    else:
        return None
    return k if k < nt else None


ATTEMPTS = [0]                       # tentativi di calcolo del range non riusciti (solo statistica)
DYNSTAT = [0, 0]                     # calcoli del range a barre (days_back = 0): totali, e spostati oltre il primo tick in finestra


def chain(t0, nt, next_try):
    """nextTry dopo un minuto in cui il range non e' pronto: tentativi ogni RETRY s sui tick esistenti (secondi 0..min(nt,60)-1)."""
    c = nt if nt < 60 else 60
    o = next_try - t0
    if o < 0:
        o = 0
    if o >= c:
        return next_try
    n = (c - 1 - o) // ns.retry
    ATTEMPTS[0] += n + 1
    return t0 + o + ns.retry * n + ns.retry


# ---------------------------------------------------------------- ricostruzione degli ingressi attesi
# Ogni run_* restituisce (ingresso o None, toccato): ingresso = (minuto, dir, prezzo, indice tick, differito);
# "toccato" dice che un minuto ambiguo (chiusura di una posizione del giorno prima) e' stato attraversato da un tick attivo.
# amb = None: minuto ambiguo tutto libero; amb = 0/1: tutto libero / tutto occupato.
def entry_at(i, k, d, carried):
    bid = O[i] if k == 0 else tick_prices(O[i], H[i], L[i], C[i])[k]
    return (T[i], d, bid + S[i] * PT if d > 0 else bid, k, carried)


def run_chiusura(di, rel, rg, amb):
    a, b = drow[di]
    pend = False
    next_try = 0
    computed = False
    touched = False
    hi = lo = up = dn = None
    we = 0
    if rg is not DYN:
        hi, lo, we, up, dn = rg
    i = a
    while i < b:
        carried = pend
        fb = first_of_bar[i]
        if fb:                              # (a)
            pend = True
        inwin = inwin_a[i]
        if not pend and (computed or not inwin):        # (c) e righe che non servono piu'
            i = next_nb[i] if computed else min(next_nb[i], next_in[i])
            continue
        m = T[i]
        st = pos_state(rel, m) if rel else 0
        if st == 2:
            touched = True
            st = 0 if amb is None else amb
        if st == 1:                         # (e)
            pend = False
            i += 1
            continue
        if computed:                        # pend e' vero: la candela si valuta al primo tick della barra
            c = cclose[i] if fb else candle_close(i)
            if c is not None:
                if c - up > 0.00000001:
                    return entry_at(i, 0, 1, carried), touched
                if dn - c > 0.00000001:
                    return entry_at(i, 0, -1, carried), touched
            pend = False
            i += 1
            continue
        nt = ntick(i)                       # range non ancora calcolato
        if not inwin:                       # (g1) (con (f): i tick prima di nextTry non fanno niente)
            if tick_k(m, nt, next_try) is not None:
                pend = False
            i += 1
            continue
        if rg is not DYN and m < we:        # (g2) range non pronto in tutto il minuto
            next_try = chain(m, nt, next_try)
            i += 1
            continue
        k = tick_k(m, nt, next_try)
        if k is not None:                   # (g2) il range si calcola a questo tick
            if rg is DYN:
                r = dyn_range(i)
                if amb is None:
                    DYNSTAT[0] += 1
                    DYNSTAT[1] += i != act_rows[di][0]
                if r is None:
                    return None, touched
                hi, lo, we, up, dn = r
            computed = True
            if pend:
                c = cclose[i] if (fb and k == 0) else candle_close(i)
                if c is not None:
                    if c - up > 0.00000001:
                        return entry_at(i, k, 1, carried), touched
                    if dn - c > 0.00000001:
                        return entry_at(i, k, -1, carried), touched
                pend = False
        i += 1
    return None, touched


def retest_step(i, arm_l, arm_s, next_try, computed, rg):
    hi, lo, we, up, dn = rg
    t0 = T[i]
    sp = S[i] * PT
    prices = tick_prices(O[i], H[i], L[i], C[i])
    nt = len(prices)
    k = tick_k(t0, nt, next_try)
    while k is not None and k < nt:
        ta = t0 + (k if k < 59 else 59)
        if not computed:
            if ta < we:                     # (g2) range non pronto
                next_try = ta + ns.retry
                ATTEMPTS[0] += 1
                k = tick_k(t0, nt, next_try)
                continue
            computed = True
        bid = prices[k]
        if arm_l:
            if bid < hi - DEPTH - 1e-9:
                arm_l = False
            elif bid <= hi + TOLP + 1e-9:
                return arm_l, arm_s, next_try, computed, (t0, 1, bid + sp, k, False)
        if arm_s:
            if bid > lo + DEPTH + 1e-9:
                arm_s = False
            elif bid >= lo - TOLP - 1e-9:
                return arm_l, arm_s, next_try, computed, (t0, -1, bid, k, False)
        if bid >= up - 1e-9:
            arm_l = True
        if bid <= dn + 1e-9:
            arm_s = True
        k += 1
    return arm_l, arm_s, next_try, computed, None


def run_retest(di, rel, rg, amb):
    arm_l = arm_s = False
    next_try = 0
    computed = False
    touched = False
    prev = -2
    for i in act_rows[di]:
        if i != prev + 1:                   # (b) tra le due righe c'e' stato almeno un minuto fuori finestra
            arm_l = arm_s = False
        prev = i
        m = T[i]
        st = pos_state(rel, m) if rel else 0
        if st == 2:
            touched = True
            st = 0 if amb is None else amb
        if st == 1:                         # (e)
            arm_l = arm_s = False
            continue
        if computed:
            if not ns.full:                 # minuto inerte: nessun tick puo' armare, disarmare o far entrare
                hi, lo, we, up, dn = rg
                o_, h_, l_, c_ = O[i], H[i], L[i], C[i]
                mx = max(o_, h_, l_, c_)
                mn = min(o_, h_, l_, c_)
                if arm_l:
                    inter = mn <= hi + TOLP + 1e-8
                else:
                    inter = mx >= up - 1e-8
                if not inter:
                    inter = (mx >= lo - TOLP - 1e-8) if arm_s else (mn <= dn + 1e-8)
                if not inter:
                    continue
        elif rg is DYN:                     # (g2) il range a barre si calcola al primo tick in finestra utile
            r = dyn_range(i)
            if amb is None:
                DYNSTAT[0] += 1
                DYNSTAT[1] += i != act_rows[di][0]
            if r is None:
                return None, touched
            rg = r
        elif m < rg[2]:
            next_try = chain(m, ntick(i), next_try)
            continue
        arm_l, arm_s, next_try, computed, ent = retest_step(i, arm_l, arm_s, next_try, computed, rg)
        if ent is not None:
            return ent, touched
    return None, touched


def same(e, c):
    return e is not None and c is not None and e[0] == c[0] and e[1] == c[1] and abs(e[2] - c[2]) <= PRICE_TOL


exp = defaultdict(dict)                  # (src, modo) -> {giorno: (minuto, dir, prezzo, k, differito)}
skipped = defaultdict(dict)              # (src, modo) -> {giorno: (esito se il minuto ambiguo e' libero, esito se occupato)}
amb_same = defaultdict(int)
for di in range(len(days)):
    for src in sources:
        rg = range_for(src, di)
        if rg is None:
            continue
        for mode in MODES:
            if mode == "retest" and not act_rows[di]:
                continue
            key = (src, mode)
            rel = carry.get(key, {}).get(days[di])
            fn = run_chiusura if mode == "chiusura" else run_retest
            r0, touched = fn(di, rel, rg, None)
            if touched:
                r1, _ = fn(di, rel, rg, 1)
                if not ((r0 is None and r1 is None) or same(r0, r1)):
                    skipped[key][days[di]] = (r0, r1)
                    continue
                amb_same[key] += 1
            if r0 is not None:
                exp[key][days[di]] = r0

# ---------------------------------------------------------------- confronto
print("controllo ingressi: %s | tf %s offset %g tol %g depth %g finestra %s extra %d fasce %dh dalle %d (n=%d) days_back %d bars %d span %d%s%s" % (
    ns.folder, ns.tf.upper(), ns.offset, ns.tol, ns.depth, ns.win, ns.extra, ns.slot_len, ns.first_hour, NSLOT, ns.days_back,
    ns.bars, ns.span, " (senza 13)" if ns.no_bars else "", " (senza 14)" if (ns.no_d1 or ns.days_back < 1) else ""))
print("M1 %d, barre %s %d, giorni D1 %d" % (N, ns.tf.upper(), len(bt), len(days)))


def show(e):
    return "nessun ingresso" if e is None else "%s %+d %.5f" % (fmt(e[0])[11:], e[1], e[2])


diffs, skip_list, open_list = [], [], []
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
                open_list.append("%s: atteso %s dir %+d prezzo %.5f ; CSV nessun trade" % (tag, fmt(e[0])[11:], e[1], e[2]))
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
        tot["ambdet"] += amb_same.get(key, 0)
        if mode == "chiusura":
            tot["differiti"] += sum(1 for e in ex.values() if e[4])
            tot["slitt"] += sum(1 for e in ex.values() if e[3] > 0)
        if len(ex) == 0 and csv_days == 0:
            zero.append("%s %d" % (mode, src))
print("TOTALE: atteso %d, CSV giorni %d, ok %d, differenze %d, saltati %d, aperti a fine dati %d (max|dprezzo| sugli ok %.6f)" % (
    tot["atteso"], tot["csv"], tot["ok"], tot["diff"], tot["saltati"], tot["fine"], maxdp))
print("ambigui con esito identico nelle due ipotesi: %d ; chiusura con attesa del range (pend riportato): %d, di cui valutate dopo il secondo 0: %d ; tentativi di calcolo del range non riusciti: %d ; candele valide per finestra ma non contigue: %d ; range a barre calcolati in finestra: %d (di cui oltre il primo minuto della finestra: %d)" % (
    tot["ambdet"], tot["differiti"], tot["slitt"], ATTEMPTS[0], NONCONT, DYNSTAT[0], DYNSTAT[1]))
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
for o_ in open_list[:ns.max_diff]:
    print("   aperto a fine dati:", o_)
sys.exit(1 if diffs else 0)
