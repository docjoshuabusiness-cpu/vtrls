#!/usr/bin/env python3
"""Verifica indipendente dell'anatomia del range della Parte B ("range-days", SPEC sezione 2).

Ricalcola da zero, in Python, dai dati M1 esportati (MDRB_DUMP_M1=1 -> m1.csv, come cb_check.py) tutte le colonne di
<base>_range_days.csv e le confronta riga per riga con quanto scritto dallo script. Implementato dalla SPECIFICA, non dal codice MQL5.

USO (dalla cartella build/, dopo una run classica InpAuto=0 con MDRB_DUMP_M1=1)
  python3 rd_check.py --mode time --rhs H --rhe H --days-back N --ws-min M --we-min M [--spread 2] [altre opzioni]
  python3 rd_check.py --mode d1 --days-back N --span K --ws-min M --we-min M [...]     (RANGE_PREV_D1, N >= 1)
  (RANGE_BARS non e' supportato: --mode bars termina con errore.)

ARGOMENTI
  --mode time|d1     definizione del range (default time)
  --rhs H --rhe H    RANGE_TIME: ora di inizio e di fine del range (RangeHourStart/End, 0..24); --rms/--rme minuti (default 0).
                     Se fine <= inizio il range passa la mezzanotte (fine += 24 h).
  --days-back N      RangeDaysBack: giorno di riferimento = N-esimo GIORNO DI MERCATO prima di D (si contano i giorni con barre M1,
                     cioe' le barre D1: il lunedi' 1 = venerdi', come l'EA). Per d1 N >= 1.
  --span K           RANGE_PREV_D1: numero di giorni D1 (default 1)
  --ws-min M         inizio finestra di ingresso in minuti dalla mezzanotte server (TradeHourStart*60+TradeMinuteStart)
  --we-min M         fine finestra in minuti (fino a 1440 = mezzanotte)
  --spread P         InpSpreadPoints in punti (default 2). Serve solo a riconoscere i range degenerati (< 2 spread), vedi AMBIGUITA'.
  --point X          SYMBOL_POINT (default 1e-5); tol = 0.001*point come g_tol
  --atr-tf TF        time frame dell'ATR: M1,M5,M15,M30,H1,H2,H3,H4,H6,H8,H12,D1 o secondi (default H1); --atr-period (default 14)
  --atr-first-hl     ATR: la prima barra della serie usa TR = high-low (disponibile da 14 barre); default: servono 14 TR con chiusura precedente
  --hold-hours H     InpMaxHoldHours (default 72): L = H*60 barre, riduce gli orizzonti h4 e h24
  --wdays LISTA      giorni della settimana ammessi (0=dom..6=sab; es. 1-5 o 1,2,3,4,5); default tutti quelli presenti nel dump
  --from-day / --to-day yyyy.mm.dd   periodo analizzato (D >= from, D < to); default tutto il dump
  --cut yyyy.mm.dd   taglio IS/OOS (IS se day < taglio): se manca si verifica solo che la serie sia IS...IS OOS...OOS
  --min-width / --max-width P   filtro di larghezza del range in punti (RequireRangeConfirmation): i giorni fuori NON devono comparire
  --m1 FILE          dump M1 (default m1.csv);  --base PERCORSO  base dei CSV (default out/MQL5/Files/MDRB_Study_EURUSD)
  --conferma FILE    <base>_conferma.csv per il controllo incrociato di event/R_ref (default: <base>_conferma.csv se esiste); --no-conferma
  --dump-expected F  scrive il CSV ricalcolato da Python e termina (debug / diff manuale; nessun confronto, event=0)
  --max-print N      differenze di dettaglio stampate per controllo (default 6)

USCITA: una riga per controllo con "differenze N"; codice 1 se ci sono differenze, se manca un CSV o se mancano colonne attese;
codice 2 per argomenti non validi. Poi, per il confronto MANUALE con il report, le statistiche aggregate ricalcolate dal CSV.

CHE COSA E' VERIFICATO IN MODO COMPLETO (ogni riga, ogni campo, anche con dati con buchi)
  - intestazione esatta e formato delle righe (giorni ordinati e non duplicati, part IS/OOS, valori numerici);
  - completezza: ogni giorno del dump che soddisfa la definizione ha una riga e viceversa (con le sole eccezioni "ambigue" sotto);
  - day/wday, hi, lo, width_pts, t0, t1, n_bars; pos, age, last_side; ctx (D1 del giorno prima ricostruito dalle M1);
  - comp (mediana dei <= 20 range-days precedenti, >= 10 richiesti), atr_pts e width_atr (SMA del TR, periodo 14);
  - w_*, h4_*, h24_* (n, up, dn, side, extup, extdn, close), compresi gli orizzonti non disponibili (n=0, campi -1);
  - part: con --cut esatta; senza --cut solo la monotonia IS->OOS.
VERIFICATO IN MODO PARZIALE O NON VERIFICATO
  - event/R_ref: NON ricalcolati (richiedono la logica del tocco); controllati solo il formato e, se c'e' il conferma.csv, la
    coerenza con le righe "touch" (stessa direzione, R_ref entro 1e-3, giorno presente tra i range-days);
  - RANGE_BARS non supportato; RANGE_PREV_D1 implementato dalla specifica ma senza scenario di prova previsto;
  - le statistiche aggregate NON sono confrontate: sono stampate dal CSV per il confronto manuale con il report.

AMBIGUITA' DELLA SPECIFICA e interpretazione scelta (nei casi dubbi si accettano ENTRAMBE le letture)
  1. RangeDaysBack in RANGE_TIME non e' definito nella SPEC: come l'EA (giorno di mercato N prima di D, indice D1). Il range e' [rif+rhs, rif+rhe).
  2. "valido": hi > lo e lo > 0. Un filtro di larghezza (Min/MaxRangePoints) si impone solo con --min-width/--max-width.
     Range con larghezza < 2 spread, range chiusi dopo la fine della finestra o troncati dalla fine dei dati: presenza non imposta
     (riga assente o presente accettate); se presente la riga e' verificata comunque.
  3. ATR: "ultima barra ATR chiusa prima di tComp" = ultima barra con apertura+TF <= tComp; ATR = media dei 14 TR (TR con chiusura
     precedente); ATR assente (poche barre) o <= 0 -> atr_pts = width_atr = -1.
  4. Orizzonte w: barre da j0 con time < D + we*60. Se la finestra scavalca la mezzanotte (we <= ws) si accettano sia we+24 h sia
     "non disponibile". Se i dati finiscono prima della fine finestra si accettano sia le barre disponibili sia "non disponibile".
     w non e' ridotto a L (la SPEC cita L solo per h4/h24).
  5. Orizzonti h4/h24: n = min(240|1440, L) barre da j0; disponibili se j0+n <= numero barre; se j0+n == numero barre (esattamente al
     bordo) si accetta anche "non disponibile" (cb_check richiede una barra in piu').
  6. n_bars = 0 (non accade in RANGE_TIME: senza barre il range non esiste): non gestito oltre la SPEC.
  7. Orizzonte non disponibile: n=0 e up=dn=side=extup=extdn=close=-1 (anche side, che ha -1 come valore valido altrimenti).
  8. ctx: confronti stretti senza tolleranza, ma se mid cade entro 1e-9 da high_prev/low_prev si accettano entrambi i lati (rumore float).
  9. comp: la mediana dei precedenti (pari -> media dei due centrali) e' calcolata sui range-days PRESENTI nel CSV e ricalcolabili
     in Python, per non propagare un'eventuale differenza di completezza.
 10. event/R_ref: tolleranza R 1e-3; il conferma.csv deve avere al piu' una riga "touch" per giorno.
 11. Statistiche: "sopra/sotto/entrambi" non e' definito in modo univoco: si stampano sia sopra/sotto in assoluto (up=1 / dn=1)
     sia solo-sopra, solo-sotto, entrambi, nessuna e la prima uscita; i quantili sono stampati con interpolazione lineare (come
     cb_check) e, per la larghezza in punti, anche con indice floor e round di p*(n-1).
Tolleranze: prezzi 1e-6, punti 0.011 (due decimali), rapporti 1e-5 + 1e-6 relativo, R 1e-3."""
import argparse, bisect, calendar, csv, math, os, sys, time

HEADER = ("day,wday,part,hi,lo,width_pts,atr_pts,width_atr,t0,t1,n_bars,pos,age,last_side,ctx,comp,"
          "w_n,w_up,w_dn,w_side,w_extup,w_extdn,w_close,h4_n,h4_up,h4_dn,h4_side,h4_extup,h4_extdn,h4_close,"
          "h24_n,h24_up,h24_dn,h24_side,h24_extup,h24_extdn,h24_close,event,R_ref").split(",")
HZ = ("w", "h4", "h24")
HF = ("n", "up", "dn", "side", "extup", "extdn", "close")
UNAVAIL = (0, -1, -1, -1, -1, -1, -1)
TOL_PRICE, TOL_PTS, TOL_RATIO, TOL_RATIO_REL, TOL_R = 1e-6, 0.011, 1e-5, 1e-6, 1e-3
TFNAMES = {"M1": 60, "M5": 300, "M15": 900, "M30": 1800, "H1": 3600, "H2": 7200, "H3": 10800, "H4": 14400, "H6": 21600,
           "H8": 28800, "H12": 43200, "D1": 86400}


def usage_error(msg):
    print("ERRORE argomenti:", msg)
    sys.exit(2)


def fatal(msg):
    print("ERRORE:", msg)
    print("rd_check: FALLITO")
    sys.exit(1)


def parse_wdays(s):
    out = set()
    for part in s.split(","):
        part = part.strip()
        if not part: continue
        if "-" in part:
            a, b = part.split("-"); out.update(range(int(a), int(b) + 1))
        else: out.add(int(part))
    if any(x < 0 or x > 6 for x in out): usage_error("--wdays: valori ammessi 0..6")
    return out


ap = argparse.ArgumentParser(description="Verifica indipendente di <base>_range_days.csv (vedi la docstring del file)")
ap.add_argument("--mode", default="time"); ap.add_argument("--rhs", type=int); ap.add_argument("--rhe", type=int)
ap.add_argument("--rms", type=int, default=0); ap.add_argument("--rme", type=int, default=0)
ap.add_argument("--days-back", type=int, required=True); ap.add_argument("--span", type=int, default=1)
ap.add_argument("--ws-min", type=int, required=True); ap.add_argument("--we-min", type=int, required=True)
ap.add_argument("--spread", type=float, default=2.0); ap.add_argument("--point", type=float, default=1e-5)
ap.add_argument("--atr-tf", default="H1"); ap.add_argument("--atr-period", type=int, default=14)
ap.add_argument("--atr-first-hl", action="store_true"); ap.add_argument("--hold-hours", type=float, default=72.0)
ap.add_argument("--wdays", default=""); ap.add_argument("--from-day"); ap.add_argument("--to-day"); ap.add_argument("--cut")
ap.add_argument("--min-width", type=float); ap.add_argument("--max-width", type=float)
ap.add_argument("--m1", default="m1.csv"); ap.add_argument("--base", default="out/MQL5/Files/MDRB_Study_EURUSD")
ap.add_argument("--conferma"); ap.add_argument("--no-conferma", action="store_true")
ap.add_argument("--dump-expected"); ap.add_argument("--max-print", type=int, default=6)
args = ap.parse_args()

if args.mode == "bars": usage_error("RANGE_BARS non e' supportato da rd_check.py")
if args.mode not in ("time", "d1"): usage_error("--mode deve essere time o d1")
if args.mode == "time":
    if args.rhs is None or args.rhe is None: usage_error("--mode time richiede --rhs e --rhe")
    if not (0 <= args.rhs <= 23 and 0 <= args.rhe <= 24 and 0 <= args.rms <= 59 and 0 <= args.rme <= 59): usage_error("orario del range non valido")
    if args.days_back < 0: usage_error("--days-back deve essere >= 0")
else:
    if args.days_back < 1 or args.span < 1: usage_error("--mode d1 richiede --days-back >= 1 e --span >= 1")
if not (0 <= args.ws_min <= 1439 and 1 <= args.we_min <= 1440): usage_error("finestra non valida: ws-min 0..1439, we-min 1..1440")
if args.we_min == args.ws_min: usage_error("finestra vuota (we-min == ws-min)")
try:
    ATR_SEC = TFNAMES[args.atr_tf.upper()] if args.atr_tf.upper() in TFNAMES else int(args.atr_tf)
except ValueError:
    usage_error("--atr-tf non riconosciuto: " + args.atr_tf)
if ATR_SEC < 60 or ATR_SEC > 86400: usage_error("--atr-tf fuori intervallo")
if args.atr_period < 1: usage_error("--atr-period deve essere >= 1")
WDAYS = parse_wdays(args.wdays) if args.wdays.strip() else None
try:
    FROM_DAY = calendar.timegm(time.strptime(args.from_day, "%Y.%m.%d")) if args.from_day else None
    TO_DAY = calendar.timegm(time.strptime(args.to_day, "%Y.%m.%d")) if args.to_day else None
    CUT = calendar.timegm(time.strptime(args.cut, "%Y.%m.%d")) if args.cut else None
except ValueError:
    usage_error("data non valida (formato yyyy.mm.dd)")

pt = args.point; S = args.spread * pt; tol = 0.001 * pt
LMAX = int(round(args.hold_hours * 3600 / 60))
NBARS = {"h4": 240, "h24": 1440}
MAXP = args.max_print


def fmt_day(t): return time.strftime("%Y.%m.%d", time.gmtime(t))
def fmt_dt(t): return time.strftime("%Y.%m.%d %H:%M", time.gmtime(t))
def parse_day(s): return calendar.timegm(time.strptime(s.strip(), "%Y.%m.%d"))
def wday_of(d): return ((d // 86400) + 4) % 7          # 0 = domenica


class Chk:
    """un controllo = una riga di output; conta confronti e differenze e stampa le prime differenze di dettaglio"""
    def __init__(self, name): self.name = name; self.cmp = 0; self.bad = 0; self.shown = 0; self.note = ""
    def ok(self): self.cmp += 1
    def fail(self, msg):
        self.cmp += 1; self.bad += 1
        if self.shown < MAXP: print("  DIFF", self.name, msg); self.shown += 1
    def line(self): return f"{self.name}: {self.cmp} confronti{(' ' + self.note) if self.note else ''}, differenze {self.bad}"


# ---------------------------------------------------------------- dati M1
T, O, H, L, C = [], [], [], [], []
try:
    for ln in open(args.m1):
        ln = ln.strip()
        if not ln: continue
        t, o, h, l, c, sp = ln.split(",")
        T.append(int(t)); O.append(float(o)); H.append(float(h)); L.append(float(l)); C.append(float(c))
except (OSError, ValueError) as e:
    fatal(f"dump M1 {args.m1} illeggibile ({e})")
nb = len(T)
if nb == 0: fatal("dump M1 vuoto")
for i in range(1, nb):
    if T[i] <= T[i - 1]: fatal(f"dump M1 non ordinato alla riga {i + 1}")
days = sorted(set(t - t % 86400 for t in T))             # barre D1 ricostruite: un giorno di calendario del server per ogni giorno con barre
day_idx = {d: i for i, d in enumerate(days)}
dayhl = {}
for i in range(nb):
    d = T[i] - T[i] % 86400
    if d not in dayhl: dayhl[d] = [H[i], L[i]]
    else:
        if H[i] > dayhl[d][0]: dayhl[d][0] = H[i]
        if L[i] < dayhl[d][1]: dayhl[d][1] = L[i]


def lower(t): return bisect.bisect_left(T, t)


# ---------------------------------------------------------------- ATR sul TF indicato (barre allineate alla mezzanotte del server)
def build_atr(sec, period, first_hl):
    bks, bh, bl, bc = [], [], [], []
    cur = None
    for i in range(nb):
        d = T[i] - T[i] % 86400
        bk = d + ((T[i] - d) // sec) * sec
        if bk != cur:
            cur = bk; bks.append(bk); bh.append(H[i]); bl.append(L[i]); bc.append(C[i])
        else:
            if H[i] > bh[-1]: bh[-1] = H[i]
            if L[i] < bl[-1]: bl[-1] = L[i]
            bc[-1] = C[i]
    m = len(bks)
    tr = [None] * m
    for i in range(m):
        if i == 0:
            tr[i] = bh[i] - bl[i] if first_hl else None
        else:
            tr[i] = max(bh[i] - bl[i], abs(bh[i] - bc[i - 1]), abs(bl[i] - bc[i - 1]))
    atr = [None] * m
    for i in range(m):
        s0 = i - period + 1
        if s0 < 0 or (s0 == 0 and tr[0] is None): continue
        atr[i] = sum(tr[s0:i + 1]) / period
    return [b + sec for b in bks], atr


ATR_CLOSE, ATR_VAL = build_atr(ATR_SEC, args.atr_period, args.atr_first_hl)


def atr_at(tcomp):
    k = bisect.bisect_right(ATR_CLOSE, tcomp) - 1       # ultima barra ATR con chiusura <= tComp
    return ATR_VAL[k] if k >= 0 else None


# ---------------------------------------------------------------- ricalcolo dei range-days
class Rec(dict): pass


def range_for_day(di):
    """ritorna (hi, lo, t0, t1, a, b, motivo_esclusione); hi e' None se il range non esiste"""
    if args.mode == "time":
        ri = di - args.days_back
        if ri < 0: return (None,) * 6 + ("nessun giorno di riferimento",)
        ref = days[ri]
        t0 = ref + args.rhs * 3600 + args.rms * 60
        t1 = ref + args.rhe * 3600 + args.rme * 60
        if t1 <= t0: t1 += 86400
    else:
        last_i = di - args.days_back; first_i = last_i - args.span + 1
        if first_i < 0: return (None,) * 6 + ("giorni D1 insufficienti",)
        t0 = days[first_i]; t1 = days[last_i] + 86400
    a, b = lower(t0), lower(t1)
    if b - a < 1: return (None,) * 6 + ("nessuna barra M1 nel periodo del range",)
    hi = max(H[a:b]); lo = min(L[a:b])
    if not (hi > lo) or lo <= 0: return (None,) * 6 + ("range nullo o prezzo <= 0",)
    return hi, lo, t0, t1, a, b, ""


def horizon_tuple(j0, cnt, hi, lo):
    hs = H[j0:j0 + cnt]; ls = L[j0:j0 + cnt]
    iu = next((i for i, h in enumerate(hs) if h > hi + tol), -1)
    idn = next((i for i, l in enumerate(ls) if l < lo - tol), -1)
    if iu < 0 and idn < 0: side = 0
    elif idn < 0: side = 1
    elif iu < 0: side = -1
    else: side = 1 if iu < idn else (-1 if idn < iu else 2)
    cl = C[j0 + cnt - 1]
    return (cnt, int(iu >= 0), int(idn >= 0), side, max(0.0, max(hs) - hi) / pt, max(0.0, lo - min(ls)) / pt,
            1 if cl > hi else (-1 if cl < lo else 0))


def w_alts(D, j0, hi, lo):
    ends = [D + args.we_min * 60] if args.we_min > args.ws_min else [D + (args.we_min + 1440) * 60, D + args.we_min * 60]
    alts = []
    for wEnd in ends:
        jw = lower(wEnd); cnt = jw - j0
        if cnt <= 0: cands = [UNAVAIL]
        else:
            tup = horizon_tuple(j0, cnt, hi, lo)
            cands = [tup, UNAVAIL] if (jw >= nb and T[-1] < wEnd - 60) else [tup]       # dati finiti prima della fine finestra: ambiguo
        for c in cands:
            if c not in alts: alts.append(c)
    return alts


def h_alts(j0, nbars, hi, lo):
    Lh = min(nbars, LMAX)
    if Lh < 1 or j0 + Lh > nb: return [UNAVAIL]
    tup = horizon_tuple(j0, Lh, hi, lo)
    return [tup, UNAVAIL] if j0 + Lh == nb else [tup]                                  # esattamente al bordo dei dati: ambiguo


def make_record(di):
    D = days[di]
    hi, lo, t0, t1, a, b, why = range_for_day(di)
    if hi is None: return None, why
    width = hi - lo
    wpts = width / pt
    if args.min_width is not None and wpts < args.min_width: return None, f"larghezza {wpts:.1f} < min-width"
    if args.max_width is not None and wpts > args.max_width: return None, f"larghezza {wpts:.1f} > max-width"
    amb = []
    if width < 2.0 * S: amb.append("larghezza < 2 spread")
    if T[-1] < t1 - 60: amb.append("range troncato dalla fine dei dati")
    wEnd0 = D + args.we_min * 60 if args.we_min > args.ws_min else D + (args.we_min + 1440) * 60
    tcomp = max(D + args.ws_min * 60, t1)
    if t1 >= wEnd0: amb.append("range chiuso dopo la fine della finestra")
    # caratteristiche sulle barre M1 con t0 <= time < t1
    mh = max(H[a:b]); ml = min(L[a:b])
    jH = b - 1
    while H[jH] < mh - tol: jH -= 1
    jL = b - 1
    while L[jL] > ml + tol: jL -= 1
    tHi, tLo = T[jH], T[jL]; tLast = max(tHi, tLo)
    pos = min(1.0, max(0.0, (C[b - 1] - lo) / (hi - lo)))
    age = (t1 - tLast) / float(t1 - t0)
    last_side = 1 if tHi > tLo else (-1 if tLo > tHi else 0)
    # contesto rispetto al D1 del giorno prima (indice di giorno di-1)
    if di >= 1:
        hp, lp = dayhl[days[di - 1]]; mid = (hi + lo) / 2.0
        f = lambda m: 1 if m > hp else (-1 if m < lp else 0)
        ctx_alts = sorted(set([f(mid - 1e-9), f(mid), f(mid + 1e-9)])); ctx = f(mid)
    else:
        ctx_alts = [-2]; ctx = -2
    atr = atr_at(tcomp)
    ok_atr = atr is not None and atr > 0
    j0 = lower(tcomp)
    alts = {"w": w_alts(D, j0, hi, lo) if j0 < nb else [UNAVAIL], "h4": h_alts(j0, 240, hi, lo), "h24": h_alts(j0, 1440, hi, lo)}
    rec = Rec(day=D, wday=wday_of(D), hi=hi, lo=lo, width_pts=wpts, atr_pts=(atr / pt if ok_atr else -1.0),
              width_atr=(width / atr if ok_atr else -1.0), t0=fmt_dt(t0), t1=fmt_dt(t1), n_bars=b - a, pos=pos, age=age,
              last_side=last_side, ctx=ctx, comp=-1.0)
    rec["_ctx_alts"] = ctx_alts; rec["_alts"] = alts; rec["_amb"] = amb; rec["_width"] = width
    return rec, ""


def assign_comp(day_list, py):
    wl = [py[D]["_width"] for D in day_list]
    for k, D in enumerate(day_list):
        prev = sorted(wl[max(0, k - 20):k])
        if len(prev) >= 10:
            m = len(prev); med = prev[m // 2] if m % 2 else 0.5 * (prev[m // 2 - 1] + prev[m // 2])
            py[D]["comp"] = wl[k] / med
        else: py[D]["comp"] = -1.0


py = {}                    # day -> Rec (range-days attesi, ambigui inclusi)
excl = {}                  # day -> motivo per cui Python non lo considera un range-day
for di, D in enumerate(days):
    if FROM_DAY is not None and D < FROM_DAY: excl[D] = "fuori periodo (--from-day)"; continue
    if TO_DAY is not None and D >= TO_DAY: excl[D] = "fuori periodo (--to-day)"; continue
    if WDAYS is not None and wday_of(D) not in WDAYS: excl[D] = "giorno della settimana non ammesso"; continue
    rec, why = make_record(di)
    if rec is None: excl[D] = why; continue
    py[D] = rec

if args.dump_expected:                        # modalita' di debug: scrive il CSV ricalcolato da Python e termina (nessun confronto)
    full = sorted(py)
    assign_comp(full, py)
    cut_i = int(0.7 * len(full))
    with open(args.dump_expected, "w", newline="") as of:
        wr = csv.writer(of); wr.writerow(HEADER)
        for k, D in enumerate(full):
            rec = py[D]; part = ("IS" if D < CUT else "OOS") if CUT is not None else ("IS" if k < cut_i else "OOS")
            line = [fmt_day(D), rec["wday"], part, "%.8f" % rec["hi"], "%.8f" % rec["lo"], "%.2f" % rec["width_pts"], "%.2f" % rec["atr_pts"],
                    "%.6f" % rec["width_atr"], rec["t0"], rec["t1"], rec["n_bars"], "%.6f" % rec["pos"], "%.6f" % rec["age"], rec["last_side"],
                    rec["ctx"], "%.6f" % rec["comp"]]
            for h in HZ:
                t = rec["_alts"][h][0]
                line += [t[0], t[1], t[2], t[3], "%.2f" % t[4], "%.2f" % t[5], t[6]]
            wr.writerow(line + [0, ""])
    print("scritto", args.dump_expected, "-", len(full), "righe (event=0, R_ref vuoto; part: taglio al 70% se manca --cut)")
    sys.exit(0)

# ---------------------------------------------------------------- lettura dei CSV dello script
fn = args.base + "_range_days.csv"
try:
    fh = open(fn, newline="")
except OSError as e:
    fatal(f"{fn} non leggibile ({e})")
rd = csv.DictReader(fh)
fields = rd.fieldnames or []
missing_cols = [c for c in HEADER if c not in fields]
if missing_cols: fatal(f"{fn}: colonne mancanti {missing_cols}")
rows = list(rd); fh.close()
chk_struct = Chk("struttura"); chk_days = Chk("completezza giorni"); chk_part = Chk("part IS/OOS")
chk_ana = Chk("anatomia (wday,hi,lo,width,t0,t1,n_bars)"); chk_feat = Chk("caratteristiche (pos,age,last_side)")
chk_ctx = Chk("contesto D1 e compressione (ctx,comp)"); chk_atr = Chk("ATR (atr_pts,width_atr)")
chk_h = {h: Chk(f"esiti puri {h}") for h in HZ}; chk_ev = Chk("event/R_ref")
if list(fields) != HEADER: chk_struct.fail(f"intestazione diversa da quella attesa (colonne extra o ordine): {fields}")
else: chk_struct.ok()


def num(row, k):
    v = row.get(k)
    if v is None or not str(v).strip(): raise ValueError(k)
    try: return float(v)
    except ValueError: raise ValueError(k)


by_day = {}; parsed = []; last_d = None
for r in rows:
    try: D = parse_day(r["day"])
    except (ValueError, TypeError, KeyError):
        chk_struct.fail(f"giorno non valido {r.get('day')!r}"); continue
    if None in r.values() or None in r: chk_struct.fail(f"riga {r['day']}: numero di campi diverso dall'intestazione"); continue
    if fmt_day(D) != r["day"].strip(): chk_struct.fail(f"giorno {r['day']!r} non nel formato yyyy.mm.dd")
    if D in by_day: chk_struct.fail(f"giorno duplicato {r['day']}"); continue
    if last_d is not None and D < last_d: chk_struct.fail(f"giorni non ordinati: {r['day']} dopo {fmt_day(last_d)}")
    last_d = D; by_day[D] = r
    if r["part"].strip() not in ("IS", "OOS"): chk_struct.fail(f"{r['day']}: part {r['part']!r} non IS/OOS")
    else: chk_struct.ok()
    try:                                  # i valori numerici del CSV, per le statistiche e per il formato
        pr = {"day": D, "part": r["part"].strip()}
        for k in HEADER:
            if k in ("day", "part", "t0", "t1", "R_ref"): continue
            pr[k] = num(r, k)
        parsed.append(pr)
    except ValueError as e:
        chk_struct.fail(f"{r['day']}: valore mancante o non numerico in {e}")

# ---------------------------------------------------------------- completezza giorni
n_amb_abs = 0; amb_why = {}
for D, rec in py.items():
    if rec["_amb"] and D not in by_day:
        n_amb_abs += 1
        for w in rec["_amb"]: amb_why[w] = amb_why.get(w, 0) + 1
miss = [D for D in sorted(py) if D not in by_day and not py[D]["_amb"]]
extra = [D for D in sorted(by_day) if D not in py]
for D in miss:
    chk_days.fail(f"{fmt_day(D)}: Python lo considera un range-day (larghezza {py[D]['width_pts']:.1f} pt) ma lo script non ha la riga"
                  " (se il run ha un filtro di larghezza usare --min-width/--max-width)")
for D in extra:
    chk_days.fail(f"{fmt_day(D)}: riga dello script ma Python non lo considera un range-day ({excl.get(D, 'giorno senza barre M1 nel dump')})")
n_def = sum(1 for D in py if not py[D]["_amb"]); n_amb = len(py) - n_def
chk_days.cmp += len(py) - len(miss)       # i giorni concordi (presenti, o ambigui e assenti)
chk_days.note = (f"(python {len(py)} giorni = {n_def} certi + {n_amb} ambigui di cui {n_amb - n_amb_abs} presenti nello script; "
                 f"script {len(by_day)}; mancanti {len(miss)}, in piu' {len(extra)})")

# part IS/OOS
seen_oos = False; bounds = [None, None]
for D in sorted(by_day):
    p = by_day[D]["part"].strip()
    if CUT is not None:
        exp_p = "IS" if D < CUT else "OOS"
        if p == exp_p: chk_part.ok()
        else: chk_part.fail(f"{fmt_day(D)}: part {p} ma il taglio {args.cut} richiede {exp_p}")
    else:
        if p == "OOS":
            if not seen_oos: bounds[1] = D
            seen_oos = True; chk_part.ok()
        elif p == "IS":
            if seen_oos: chk_part.fail(f"{fmt_day(D)}: IS dopo un giorno OOS")
            else: chk_part.ok()
            bounds[0] = D if not seen_oos else bounds[0]
n_is = sum(1 for D in by_day if by_day[D]["part"].strip() == "IS"); n_oos = sum(1 for D in by_day if by_day[D]["part"].strip() == "OOS")
chk_part.note = (f"(IS {n_is}, OOS {n_oos}; " + (f"taglio {args.cut}" if CUT is not None else
                 "taglio non dato: ultimo IS " + (fmt_day(bounds[0]) if bounds[0] else "-") + ", primo OOS " + (fmt_day(bounds[1]) if bounds[1] else "-")) + ")")

# ---------------------------------------------------------------- confronto riga per riga
common = sorted(D for D in by_day if D in py)
assign_comp(common, py)                      # comp sui range-days presenti nello script e ricalcolabili in Python


def cmp_num(name, kind, g, e):
    """None se uguali, altrimenti il testo della differenza"""
    if kind == "i": bad = abs(g - e) > 1e-9
    elif kind == "p": bad = abs(g - e) > TOL_PRICE
    elif kind == "pts": bad = abs(g - e) > TOL_PTS
    else: bad = abs(g - e) > TOL_RATIO + TOL_RATIO_REL * abs(e)
    return None if not bad else f"{name} script={g:g} python={e:.8g}"


def check_fields(chk, D, row, rec, spec):
    msgs = []
    for name, kind in spec:
        try: g = num(row, name) if kind != "s" else row[name].strip()
        except ValueError: msgs.append(f"{name} non numerico {row.get(name)!r}"); continue
        if kind == "s":
            if g != rec[name]: msgs.append(f"{name} script={g!r} python={rec[name]!r}")
        elif name == "ctx":
            if int(round(g)) not in rec["_ctx_alts"] or abs(g - round(g)) > 1e-9: msgs.append(f"ctx script={g:g} python={rec['_ctx_alts']}")
        else:
            m = cmp_num(name, kind, g, rec[name])
            if m: msgs.append(m)
    if msgs: chk.fail(f"{fmt_day(D)}: " + "; ".join(msgs))
    else: chk.ok()


SPEC_ANA = [("wday", "i"), ("hi", "p"), ("lo", "p"), ("width_pts", "pts"), ("t0", "s"), ("t1", "s"), ("n_bars", "i")]
SPEC_FEAT = [("pos", "r"), ("age", "r"), ("last_side", "i")]
SPEC_CTX = [("ctx", "i"), ("comp", "r")]
SPEC_ATR = [("atr_pts", "pts"), ("width_atr", "r")]
HKIND = {"n": "i", "up": "i", "dn": "i", "side": "i", "extup": "pts", "extdn": "pts", "close": "i"}
for D in common:
    row = by_day[D]; rec = py[D]
    check_fields(chk_ana, D, row, rec, SPEC_ANA)
    check_fields(chk_feat, D, row, rec, SPEC_FEAT)
    check_fields(chk_ctx, D, row, rec, SPEC_CTX)
    check_fields(chk_atr, D, row, rec, SPEC_ATR)
    for h in HZ:
        try: got = tuple(num(row, f"{h}_{f}") for f in HF)
        except ValueError as e: chk_h[h].fail(f"{fmt_day(D)}: valore non numerico in {e}"); continue
        okk = False
        for alt in rec["_alts"][h]:
            if all(cmp_num(f, HKIND[f], g, e) is None for f, g, e in zip(HF, got, alt)): okk = True; break
        if okk: chk_h[h].ok()
        else:
            e0 = rec["_alts"][h][0]
            chk_h[h].fail(f"{fmt_day(D)}: " + "; ".join(f"{h}_{f} script={g:g} python={e:.6g}" for f, g, e in zip(HF, got, e0)
                                                       if cmp_num(f, HKIND[f], g, e) is not None) +
                          (f" (alternative accettate: {len(rec['_alts'][h])})" if len(rec["_alts"][h]) > 1 else ""))

# ---------------------------------------------------------------- event / R_ref: formato e coerenza con le righe touch del conferma.csv
conf_path = None if args.no_conferma else (args.conferma or (args.base + "_conferma.csv"))
touch = {}; conf_ok = False
if conf_path and os.path.exists(conf_path):
    with open(conf_path, newline="") as cf:
        cr = csv.DictReader(cf)
        need = ["variant", "day", "dir", "R_ref"]
        if any(c not in (cr.fieldnames or []) for c in need): fatal(f"{conf_path}: colonne mancanti {[c for c in need if c not in (cr.fieldnames or [])]}")
        for r in cr:
            if r["variant"].strip() != "touch": continue
            try: touch.setdefault(parse_day(r["day"]), []).append((int(float(r["dir"])), float(r["R_ref"])))
            except (ValueError, TypeError): chk_ev.fail(f"conferma.csv: riga touch non numerica {r['day']}")
    conf_ok = True
elif args.conferma:
    fatal(f"{args.conferma} non leggibile")
for D in common:
    row = by_day[D]
    try: ev = int(round(num(row, "event")))
    except ValueError: chk_ev.fail(f"{fmt_day(D)}: event non numerico {row.get('event')!r}"); continue
    rr = row["R_ref"].strip()
    msgs = []
    if ev not in (-1, 0, 1): msgs.append(f"event={ev} non in {{-1,0,1}}")
    if ev == 0 and rr != "": msgs.append(f"R_ref={rr!r} con event=0 (deve essere vuoto)")
    if ev != 0:
        try: rv = float(rr)
        except ValueError: rv = None; msgs.append(f"R_ref={rr!r} non numerico con event={ev}")
    if conf_ok:
        tl = touch.get(D, [])
        if len(tl) > 1: msgs.append(f"{len(tl)} righe touch nello stesso giorno nel conferma.csv")
        else:
            exp_ev = tl[0][0] if tl else 0
            if ev != exp_ev: msgs.append(f"event={ev} ma il conferma.csv ha {exp_ev}")
            elif ev != 0 and rv is not None and abs(rv - tl[0][1]) > TOL_R: msgs.append(f"R_ref={rv:g} ma il conferma.csv ha {tl[0][1]:g}")
    if msgs: chk_ev.fail(f"{fmt_day(D)}: " + "; ".join(msgs))
    else: chk_ev.ok()
if conf_ok:
    for D in sorted(touch):
        if D not in by_day: chk_ev.fail(f"{fmt_day(D)}: evento touch nel conferma.csv ma nessun range-day nello script")
    chk_ev.note = f"(coerenza con {os.path.basename(conf_path)}: {sum(len(v) for v in touch.values())} righe touch; formato verificato, valori NON ricalcolati)"
else:
    chk_ev.note = "(solo formato: conferma.csv assente, coerenza con il tocco NON verificata; valori NON ricalcolati)"

# ---------------------------------------------------------------- uscita
if args.mode == "time":
    dfn = f"RANGE_TIME {args.rhs:02d}:{args.rms:02d}-{args.rhe:02d}:{args.rme:02d} giorno-{args.days_back}"
else: dfn = f"RANGE_PREV_D1 giorno-{args.days_back} span {args.span}"
print(f"range-days: {dfn}, finestra {args.ws_min // 60:02d}:{args.ws_min % 60:02d}-{args.we_min // 60:02d}:{args.we_min % 60:02d} ({args.ws_min}-{args.we_min} min), "
      f"ATR {args.atr_tf} periodo {args.atr_period}, L={LMAX} barre, spread {args.spread:g} pt, dump M1 {nb} barre / {len(days)} giorni")
checks = [chk_struct, chk_days, chk_part, chk_ana, chk_feat, chk_ctx, chk_atr] + [chk_h[h] for h in HZ] + [chk_ev]
for c in checks: print(c.line())
if amb_why: print("  giorni ambigui assenti dallo script (accettati):", ", ".join(f"{k}: {v}" for k, v in sorted(amb_why.items())))
total = sum(c.bad for c in checks)

# ---------------------------------------------------------------- statistiche aggregate dal CSV, per il confronto manuale con il report
def quant(a, p):
    pos_ = p * (len(a) - 1); i0 = int(math.floor(pos_)); i1 = min(i0 + 1, len(a) - 1); fr = pos_ - i0
    return a[i0] * (1 - fr) + a[i1] * fr


def qline(label, vals, fmt, how):
    if not vals: return f"  {label:<22} n=0"
    a = sorted(vals); n_ = len(a)
    if how == "lin": q = [quant(a, p) for p in (0.1, 0.25, 0.5, 0.75, 0.9)]
    elif how == "floor": q = [a[int(math.floor(p * (n_ - 1)))] for p in (0.1, 0.25, 0.5, 0.75, 0.9)]
    else: q = [a[int(p * (n_ - 1) + 0.5)] for p in (0.1, 0.25, 0.5, 0.75, 0.9)]
    return f"  {label:<22} n={n_:<5} " + " ".join(f"P{int(p * 100)}=" + fmt % v for p, v in zip((0.1, 0.25, 0.5, 0.75, 0.9), q))


PARTS = (("IS", lambda r: r["part"] == "IS"), ("OOS", lambda r: r["part"] == "OOS"), ("TUTTO", lambda r: True))
print("\nSTATISTICHE AGGREGATE ricalcolate dal CSV (nessun confronto automatico: da confrontare a mano con il report)")
print("  giorni: " + ", ".join(f"{nm} {sum(1 for r in parsed if f(r))}" for nm, f in PARTS))
print("  uscita dal range per orizzonte (solo giorni con orizzonte disponibile, n>0); sopra/sotto = almeno una barra oltre il bordo;"
      " solo/entrambi = esclusivi; prima = primo bordo toccato")
for h in HZ:
    for nm, f in PARTS:
        sub = [r for r in parsed if f(r) and r[f"{h}_n"] > 0]; n_ = len(sub)
        if n_ == 0: print(f"  {h:<3} {nm:<5} n=0"); continue
        pc = lambda cond: 100.0 * sum(1 for r in sub if cond(r)) / n_
        print(f"  {h:<3} {nm:<5} n={n_:<5} sopra={pc(lambda r: r[h + '_up'] == 1):5.1f}% sotto={pc(lambda r: r[h + '_dn'] == 1):5.1f}% | "
              f"solo_sopra={pc(lambda r: r[h + '_up'] == 1 and r[h + '_dn'] == 0):5.1f}% solo_sotto={pc(lambda r: r[h + '_dn'] == 1 and r[h + '_up'] == 0):5.1f}% "
              f"entrambi={pc(lambda r: r[h + '_up'] == 1 and r[h + '_dn'] == 1):5.1f}% nessuna={pc(lambda r: r[h + '_up'] == 0 and r[h + '_dn'] == 0):5.1f}% | "
              f"prima_sopra={pc(lambda r: r[h + '_side'] == 1):5.1f}% prima_sotto={pc(lambda r: r[h + '_side'] == -1):5.1f}% stessa_barra={pc(lambda r: r[h + '_side'] == 2):5.1f}%")
print("  larghezza del range in punti (width_pts), quantili con interpolazione lineare:")
for nm, f in PARTS: print(qline(nm, [r["width_pts"] for r in parsed if f(r)], "%.2f", "lin"))
print("  larghezza in punti, variante indice floor(p*(n-1)):")
for nm, f in PARTS: print(qline(nm, [r["width_pts"] for r in parsed if f(r)], "%.2f", "floor"))
print("  larghezza in punti, variante indice round(p*(n-1)):")
for nm, f in PARTS: print(qline(nm, [r["width_pts"] for r in parsed if f(r)], "%.2f", "round"))
print("  larghezza in ATR (width_atr, solo righe con ATR disponibile), interpolazione lineare:")
for nm, f in PARTS: print(qline(nm, [r["width_atr"] for r in parsed if f(r) and r["width_atr"] >= 0], "%.4f", "lin"))

print(f"\nrd_check: {len(by_day)} righe del CSV, {len(py)} range-days attesi da Python, differenze totali {total}")
sys.exit(1 if total else 0)
