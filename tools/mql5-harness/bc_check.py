#!/usr/bin/env python3
"""Verifica indipendente della variante "a chiusura" della Parte B (conferma a candela chiusa, <base>_conferma.csv).
Ricalcola da m1.csv (dump M1: t,o,h,l,c,spread; MDRB_DUMP_M1=1), in Python e dalla specifica, tutto cio' che il CSV dichiara.

USO (dalla cartella build/, dopo una run con MDRB_DUMP_M1=1 che abbia calcolato la variante a chiusura del TF scelto):
  python3 bc_check.py TF_SEC OFFSET WE_MIN EXTRA WS_MIN [SPREAD_PTS] [opzioni]

ARGOMENTI POSIZIONALI
  TF_SEC      time frame della variante: 60 (M1), 300 (M5), 900 (M15), 1800 (M30), 3600 (H1), 7200 (H2), 10800 (H3);
              si controllano solo le righe con variant == nome del TF (le altre varianti sono ignorate, salvo coerenza variant/tf_sec/ordine)
  OFFSET      PendingOrderOffsetPoints della definizione, in punti (livelli hi+offset*point / lo-offset*point)
  WE_MIN      fine della finestra di ingresso in minuti dalla mezzanotte (1440 = mezzanotte): finestra = [WS_MIN, WE_MIN) del giorno D
  EXTRA       ExpireExtraMinutes: scadenza pX = D + (WE_MIN + EXTRA) minuti
  WS_MIN      inizio della finestra di ingresso in minuti dalla mezzanotte
  SPREAD_PTS  spread in punti (InpSpreadPoints, default 2): S per le uscite, colonna spread_pts, ask=open+spread al piazzamento

OPZIONI
  --hold-hours H     InpMaxHoldHours (default 72): orizzonte L = H*60 barre M1; con meno barre fino a fine dati l'orizzonte e' troncato
  --ref-sl P         SL di riferimento in punti per R_ref (RefSLPoints()); se omesso lo legge dal commento di riga "ref_sl_pts=..." del CSV
                     (anche "# ref_sl_pts: ..." o una colonna ref_sl_pts); se dato e diverso dal commento, e' una differenza
  --ref-rr X         InpRefRR (default 2.0): TP di riferimento = X * SL
  --comm-pts C       InpCommissionPoints (default 0): R = (u_uscita - C*point)/SL
  --point P          SYMBOL_POINT (default 1e-5);  --tick T  tick size (default = point): level_px e' normalizzato a T
  --m1 FILE          dump M1 (default m1.csv);  --base PATH  base dei CSV (default out/MQL5/Files/MDRB_Study_EURUSD -> PATH_conferma.csv)
  --min-events N     numero minimo di righe attese per la variante (default 1; 0 per ammettere zero eventi)
  --max-print N      dettagli stampati per controllo (default 8)
  Completezza (solo definizioni a range ORARIO, caso semplice; senza --rhs/--rhe NON viene eseguita):
  --rhs M --rhe M    inizio/fine del range orario in minuti dalla mezzanotte (es. 0 e 480 = 00:00-08:00); rhe <= rhs: range a cavallo
                     della mezzanotte [D-1+rhs, D+rhe)
  --days-back N      RangeDaysBack: il range inizia N giorni di calendario prima (default 0)
  --min-width P / --max-width P   filtri sulla larghezza del range in punti (default 0 = disattivati)
  --min-bars N       barre M1 minime nel range (default 1)
  --place-spread P   spread in punti per ask=open+spread al piazzamento (default = SPREAD_PTS)
  --skip-last-day    esclude l'ultimo giorno del dump dall'universo della completezza

COSA CONTROLLA
  Su OGNI riga presente della variante (anche in assenza di completezza):
   - formato: intestazione esatta, colonne, variant/tf_sec, ordine (per variante e giorno, un evento per giorno), part IS/OOS monotona,
     dir, executed in {0,1}, sl0..sl5 uguali in tutte le righe, place_time = barra M1 esistente dentro la finestra;
   - candela di conferma: ricostruita dalle barre M1 (allineata alla mezzanotte; high=max, low=min, close=ultima barra M1) e confermata
     come PRIMA candela con tc > place_time e tc <= pX che chiude fuori da hi+offset / lo-offset di piu' di g_tol (0.001*point);
     dir, entry_time, ingresso eseguibile (esiste una barra M1 con time >= tc, entro 900 s);
   - campi: entry_px (= close della candela), level_px (hi+offset o lo-offset, normalizzato al tick), slip_pts, delay_min, spread_pts, range_pts;
   - R_ref e i 18 R_s{i}_m{m}: regola SimFixed sulle barre M1 da jn (compresa) in poi, senza correzione della barra d'ingresso;
   - mfe_pts, pullback_pts, fakeout: su tutto l'orizzonte L, dalla stessa barra jn.
  Con --rhs/--rhe (COMPLETEZZA, su ogni giorno del dump): ricostruisce l'evento atteso (range hi/lo dal CSV nei giorni con evento, altrimenti
  ricalcolato dall'intervallo orario; piazzamento = prima barra M1 della finestra, a range pronto, con ask=open+spread < hi+offset e bid=open > lo-offset;
  poi candela di conferma) e lo confronta col CSV: nessun evento mancante, nessun evento in piu', place_time uguale; inoltre hi/lo del CSV ==
  ricalcolo orario. Valida SOLO con: range orario semplice, nessun ChaseIfBroken, nessun filtro oltre a quelli indicati, un solo piazzamento al giorno.
  NON verificati: atr_pts (solo finito), executed (informativo), R_ea, la regola del giorno occupato; part IS/OOS solo come coerenza monotona.

Tolleranze: R 1e-3 (piu' la meta' dell'ultima cifra scritta), prezzi 1e-6, punti = meta' dell'ultima cifra scritta + 2e-3.
Uscita: 1 se ci sono differenze, se mancano colonne attese, se i file non esistono; 2 per argomenti errati; 0 altrimenti."""
import argparse, bisect, calendar, collections, csv, math, os, re, sys, time

TFNAME = {60: "M1", 300: "M5", 900: "M15", 1800: "M30", 3600: "H1", 7200: "H2", 10800: "H3"}
BASE_COLS = ["variant", "tf_sec", "day", "dir", "part", "place_time", "entry_time", "entry_px", "level_px", "slip_pts", "delay_min",
             "range_hi", "range_lo", "range_pts", "atr_pts", "spread_pts", "mfe_pts", "pullback_pts", "fakeout", "executed", "R_ref", "R_ea"]
SL_COLS = [f"sl{i}" for i in range(6)]
R_COLS = [f"R_s{i}_m{m}" for i in range(6) for m in (1, 2, 3)]
EXPECTED = BASE_COLS + SL_COLS + R_COLS
NUM_COLS = ["tf_sec", "dir", "delay_min", "entry_px", "level_px", "slip_pts", "range_hi", "range_lo", "range_pts", "atr_pts", "spread_pts",
            "mfe_pts", "pullback_pts", "fakeout", "executed"] + SL_COLS
RE_REF = re.compile(r"ref_sl_pts\s*[=:,;]?\s*\"?\s*([-+]?\d+(?:\.\d+)?)", re.I)

ap = argparse.ArgumentParser(description="Verifica indipendente della variante a chiusura della Parte B (vedi la docstring del file).")
ap.add_argument("tf_sec", type=int)
ap.add_argument("offset", type=float)
ap.add_argument("we_min", type=int)
ap.add_argument("extra", type=int)
ap.add_argument("ws_min", type=int)
ap.add_argument("spread", type=float, nargs="?", default=2.0)
ap.add_argument("--hold-hours", type=float, default=72.0)
ap.add_argument("--ref-sl", type=float, default=None)
ap.add_argument("--ref-rr", type=float, default=2.0)
ap.add_argument("--comm-pts", type=float, default=0.0)
ap.add_argument("--point", type=float, default=1e-5)
ap.add_argument("--tick", type=float, default=None)
ap.add_argument("--m1", default="m1.csv")
ap.add_argument("--base", default="out/MQL5/Files/MDRB_Study_EURUSD")
ap.add_argument("--min-events", type=int, default=1)
ap.add_argument("--max-print", type=int, default=8)
ap.add_argument("--rhs", type=int, default=None)
ap.add_argument("--rhe", type=int, default=None)
ap.add_argument("--days-back", type=int, default=0)
ap.add_argument("--min-width", type=float, default=0.0)
ap.add_argument("--max-width", type=float, default=0.0)
ap.add_argument("--min-bars", type=int, default=1)
ap.add_argument("--place-spread", type=float, default=None)
ap.add_argument("--skip-last-day", action="store_true")
args = ap.parse_args()
if args.tf_sec not in TFNAME: ap.error("tf_sec deve essere uno di " + ",".join(str(k) for k in TFNAME))
if not (0 <= args.ws_min < args.we_min <= 1440): ap.error("serve 0 <= ws_min < we_min <= 1440 (finestra nello stesso giorno)")
if args.extra < 0: ap.error("extra deve essere >= 0")
if (args.rhs is None) != (args.rhe is None): ap.error("--rhs e --rhe vanno dati insieme")
if args.rhs is not None and not (0 <= args.rhs <= 1440 and 0 <= args.rhe <= 1440): ap.error("--rhs/--rhe in minuti 0..1440")

sec = args.tf_sec; vname = TFNAME[sec]
pt = args.point; tick = args.tick if args.tick else pt
S = args.spread * pt; tol = pt * 0.001
pS = (args.place_spread if args.place_spread is not None else args.spread) * pt
off = args.offset
WS, WE, EXTRA = args.ws_min, args.we_min, args.extra
L = int(round(args.hold_hours * 3600 / 60))
comm = args.comm_pts * pt


def fmt_t(t): return time.strftime("%Y.%m.%d %H:%M", time.gmtime(t))
def parse_t(s): return calendar.timegm(time.strptime(s, "%Y.%m.%d %H:%M"))
def parse_d(s): return calendar.timegm(time.strptime(s, "%Y.%m.%d"))
def norm_tick(x): return round(x / tick) * tick
def ndec(s):
    s = s.strip()
    if "e" in s.lower(): return 12
    return len(s.split(".")[1]) if "." in s else 0
def tol_px(s): return max(1e-6, 0.5 * 10 ** (-ndec(s)) + 1e-9)
def tol_pts(s): return 0.5 * 10 ** (-ndec(s)) + 2e-3
def tol_R(s, Rexp, slstr, slv):
    t = max(1e-3, 0.5 * 10 ** (-ndec(s)) + 1e-6)
    if slv > 0 and ndec(slstr) >= 1: t += abs(Rexp) * 0.5 * 10 ** (-ndec(slstr)) / slv       # SL scritto arrotondato: R = u/SL cambia in proporzione
    return t


class Check:
    def __init__(self, name): self.name = name; self.n = 0; self.detail = []; self.note = ""; self.skipped = False
    def bad(self, msg):
        self.n += 1
        if len(self.detail) < args.max_print: self.detail.append(msg)
    def show(self):
        if self.skipped: print(f"{self.name}: {self.note}"); return              # controllo non eseguito: nessun 'differenze N'
        print(f"{self.name}: {self.note + ', ' if self.note else ''}differenze {self.n}")
        for d in self.detail: print("   - " + d)
        if self.n > len(self.detail): print(f"   - ... altre {self.n - len(self.detail)}")


c_fmt = Check("formato/coerenza"); c_cand = Check("candela di conferma (prima valida)"); c_fld = Check("campi evento")
c_R = Check("R_ref + R_s*_m*"); c_mfe = Check("mfe/pullback/fakeout"); c_rng = Check("range orario (CSV vs ricalcolo)"); c_cmp = Check("completezza")
checks = [c_fmt, c_cand, c_fld, c_R, c_mfe, c_rng, c_cmp]


def finish(code_msg=None):
    if code_msg: print(code_msg)
    tot = sum(c.n for c in checks)
    print(f"bc_check {vname}: TOTALE differenze {tot}")
    sys.exit(1 if tot else 0)


# ---- dump M1
if not os.path.exists(args.m1):
    print(f"manca il dump M1 '{args.m1}' (lanciare lo studio con MDRB_DUMP_M1=1): differenze 1"); sys.exit(1)
T, O, H, L_, C = [], [], [], [], []
for ln in open(args.m1):
    p = ln.strip().split(",")
    if len(p) < 5: continue
    T.append(int(p[0])); O.append(float(p[1])); H.append(float(p[2])); L_.append(float(p[3])); C.append(float(p[4]))
n = len(T)
if n == 0:
    print(f"dump M1 '{args.m1}' vuoto: differenze 1"); sys.exit(1)
Lw = L_                                     # low delle barre M1 (L e' l'orizzonte)
cand = {}                                   # candele del TF: bk -> [high, low, close]
for i in range(n):
    day = T[i] - T[i] % 86400
    bk = day + ((T[i] - day) // sec) * sec
    c = cand.get(bk)
    if c is None: cand[bk] = [H[i], Lw[i], C[i]]
    else:
        if H[i] > c[0]: c[0] = H[i]
        if Lw[i] < c[1]: c[1] = Lw[i]
        c[2] = C[i]
ctimes = sorted(cand)
days_all = sorted(set(t - t % 86400 for t in T))


def first_confirm(place_t, hi, lo, pX):
    """prima candela con tc > place_t e tc <= pX che chiude fuori: (bk, dir, close) oppure None"""
    up = norm_tick(hi + off * pt); dn = norm_tick(lo - off * pt)
    q = bisect.bisect_left(ctimes, place_t - sec + 1)                   # bk > place_t - sec  <=>  tc > place_t
    while q < len(ctimes):
        bk = ctimes[q]
        if bk + sec > pX: break
        cl = cand[bk][2]
        if cl - up > tol: return bk, 1, cl
        if dn - cl > tol: return bk, -1, cl
        q += 1
    return None


def entry_bar(tc):
    """jn = prima barra M1 con time >= tc; None se non esiste o se time(jn) - tc > 900 s (ingresso non eseguibile)"""
    jn = bisect.bisect_left(T, tc)
    if jn >= n or T[jn] - tc > 900: return None
    return jn


def path(jn, d, E0):
    Lh = min(L, n - jn)
    if d > 0:
        oo = [O[j] - E0 for j in range(jn, jn + Lh)]; ff = [H[j] - E0 for j in range(jn, jn + Lh)]
        aa = [Lw[j] - E0 for j in range(jn, jn + Lh)]; cc = [C[j] - E0 for j in range(jn, jn + Lh)]
    else:
        oo = [E0 - O[j] for j in range(jn, jn + Lh)]; ff = [E0 - Lw[j] for j in range(jn, jn + Lh)]
        aa = [E0 - H[j] for j in range(jn, jn + Lh)]; cc = [E0 - C[j] for j in range(jn, jn + Lh)]
    return oo, ff, aa, cc, Lh


def sim_fixed(oo, ff, aa, cc, SLd, TPd):
    """SimFixed: u(x) = x - S; gap all'apertura, poi stop prima del TP nella stessa barra; a fine orizzonte u(C_ultima)"""
    m = -SLd + tol; t = TPd - tol
    for j in range(len(oo)):
        uO = oo[j] - S
        if uO <= m or uO >= t: return uO
        if aa[j] - S <= m: return -SLd
        if ff[j] - S >= t: return TPd
    return cc[-1] - S


# ---- CSV
fn = args.base + "_conferma.csv"
if not os.path.exists(fn):
    print(f"manca {fn}: differenze 1"); sys.exit(1)
header = None; rows = []; malformed = []; refs = []
with open(fn, encoding="utf-8-sig", errors="replace", newline="") as f:
    for ln, raw in enumerate(f, 1):
        s = raw.strip()
        if not s: continue
        first = s.split(",")[0].strip().lower()
        if s[0] in "#;" or s.startswith("//") or first.startswith("ref_sl_pts"):          # riga di commento (ref_sl_pts)
            m = RE_REF.search(s)
            if m: refs.append(m.group(1))
            continue
        fields = [x.strip() for x in next(csv.reader([s]))]
        if header is None: header = fields; continue
        if len(fields) > len(header):                                                     # commento in coda alla riga
            m = RE_REF.search(",".join(fields[len(header):]))
            if m: refs.append(m.group(1)); fields = fields[:len(header)]
        if len(fields) != len(header): malformed.append((ln, len(fields))); continue
        rows.append((ln, dict(zip(header, fields))))
if header is None:
    print(f"{fn} senza intestazione: differenze 1"); sys.exit(1)
missing = [c for c in EXPECTED if c not in header]
if missing:
    print(f"colonne attese mancanti in {os.path.basename(fn)}: {','.join(missing)}; differenze {len(missing)}"); sys.exit(1)
core = [c for c in header if c in EXPECTED]
extra_cols = [c for c in header if c not in EXPECTED and c != "ref_sl_pts"]
if core != EXPECTED: c_fmt.bad("l'ordine delle colonne non e' quello della specifica")
if extra_cols: c_fmt.bad("colonne non previste dalla specifica: " + ",".join(extra_cols))
for ln, k in malformed: c_fmt.bad(f"riga {ln}: {k} campi invece di {len(header)}")
if rows and "ref_sl_pts" in header:
    refs += [r["ref_sl_pts"] for _, r in rows if r.get("ref_sl_pts", "") != ""]

# ---- coerenza generale (tutte le varianti): variant/tf_sec, ordine, part
expected_tf = {"touch": 0, **{v: k for k, v in TFNAME.items()}}
seen_var = []; last_day = {}; is_days = []; oos_days = []
for ln, r in rows:
    v = r["variant"]
    if v not in expected_tf: c_fmt.bad(f"riga {ln}: variant '{v}' sconosciuta"); continue
    try:
        if int(float(r["tf_sec"])) != expected_tf[v]: c_fmt.bad(f"riga {ln}: variant {v} con tf_sec {r['tf_sec']} (atteso {expected_tf[v]})")
    except ValueError: c_fmt.bad(f"riga {ln}: tf_sec '{r['tf_sec']}' non numerico")
    if not seen_var or seen_var[-1] != v:
        if v in seen_var: c_fmt.bad(f"riga {ln}: la variante {v} riappare dopo altre (righe non ordinate per variante)")
        seen_var.append(v)
    try: dd = parse_d(r["day"])
    except ValueError: c_fmt.bad(f"riga {ln}: day '{r['day']}' non valido"); continue
    if v in last_day and dd <= last_day[v]: c_fmt.bad(f"riga {ln}: {v} giorno {r['day']} non crescente (o duplicato)")
    last_day[v] = dd
    if r["part"] == "IS": is_days.append(dd)
    elif r["part"] == "OOS": oos_days.append(dd)
    else: c_fmt.bad(f"riga {ln}: part '{r['part']}' (atteso IS/OOS)")
if is_days and oos_days and max(is_days) >= min(oos_days):
    c_fmt.bad(f"part non monotona: un giorno IS ({fmt_t(max(is_days))[:10]}) non precede tutti gli OOS ({fmt_t(min(oos_days))[:10]})")

mine = [(ln, r) for ln, r in rows if r["variant"] == vname]
if len(mine) < args.min_events: c_fmt.bad(f"righe della variante {vname}: {len(mine)} (attese almeno {args.min_events})")

# ---- SL di riferimento
ref_sl = None
if refs:
    if len(set(float(x) for x in refs)) > 1: c_fmt.bad("ref_sl_pts discordi nel CSV: " + ",".join(sorted(set(refs))))
    ref_sl_csv = float(refs[0]); ref_sl_str = refs[0]
else:
    ref_sl_csv = None; ref_sl_str = ""
if args.ref_sl is not None:
    ref_sl = args.ref_sl
    if ref_sl_csv is not None and abs(ref_sl_csv - ref_sl) > 0.5 * 10 ** (-ndec(ref_sl_str)) + 1e-9:
        c_fmt.bad(f"ref_sl_pts del CSV ({ref_sl_str}) diverso dall'argomento --ref-sl ({args.ref_sl:g})")
else: ref_sl = ref_sl_csv
if ref_sl is None and mine:
    c_fmt.bad("SL di riferimento ignoto: nessun commento ref_sl_pts nel CSV e nessun --ref-sl (R_ref non verificabile)")

# ---- righe della variante
parsed = {}                                  # giorno -> (ln, r, v)
sl_ref_row = None
n_candle_skip = 0; n_trunc = 0; n_rows_full = 0; n_cells = 0
for ln, r in mine:
    v = {}; ok = True
    for col in NUM_COLS:
        try:
            x = float(r[col])
            if math.isnan(x) or math.isinf(x): raise ValueError
            v[col] = x
        except ValueError:
            c_fmt.bad(f"riga {ln}: {col}='{r[col]}' non numerico"); ok = False
    try:
        D = parse_d(r["day"]); place_t = parse_t(r["place_time"]); entry_t = parse_t(r["entry_time"])
    except ValueError:
        c_fmt.bad(f"riga {ln}: day/place_time/entry_time non nel formato yyyy.mm.dd [hh:mm]"); continue
    if not ok: continue
    d = int(v["dir"])
    if d not in (1, -1): c_fmt.bad(f"riga {ln}: dir {r['dir']} (atteso +1/-1)"); continue
    if v["executed"] not in (0.0, 1.0): c_fmt.bad(f"riga {ln}: executed {r['executed']} (atteso 0/1)")
    if v["atr_pts"] < 0 and v["atr_pts"] != -1: c_fmt.bad(f"riga {ln}: atr_pts {r['atr_pts']}")
    slv = [v[c] for c in SL_COLS]
    if sl_ref_row is None: sl_ref_row = (ln, slv)
    elif any(abs(a - b) > 1e-9 for a, b in zip(slv, sl_ref_row[1])): c_fmt.bad(f"riga {ln}: sl0..sl5 diversi da quelli della riga {sl_ref_row[0]}")
    hi, lo = v["range_hi"], v["range_lo"]
    if not hi > lo: c_fmt.bad(f"riga {ln}: range_hi {r['range_hi']} <= range_lo {r['range_lo']}"); continue
    # place_time: barra M1 esistente, dentro la finestra del giorno D
    jp = bisect.bisect_left(T, place_t)
    if jp >= n or T[jp] != place_t: c_fmt.bad(f"riga {ln}: place_time {r['place_time']} non e' l'apertura di una barra M1 del dump"); continue
    if not (D + WS * 60 <= place_t < D + WE * 60): c_fmt.bad(f"riga {ln}: place_time {r['place_time']} fuori dalla finestra [{WS // 60:02d}:{WS % 60:02d}, {WE // 60:02d}:{WE % 60:02d}) del giorno {r['day']}")
    parsed[D] = (ln, r, v)
    pX = D + (WE + EXTRA) * 60
    # candela di conferma
    ex = first_confirm(place_t, hi, lo, pX)
    if ex is None:
        c_cand.bad(f"{r['day']}: nessuna candela {vname} valida in ({fmt_t(place_t)}, {fmt_t(pX)}] ma il CSV ha un evento (dir {d:+d}, entry {r['entry_time']})")
        n_candle_skip += 1; continue
    bk, dexp, E0 = ex; tc = bk + sec
    if dexp != d or tc != entry_t:
        up = norm_tick(hi + off * pt); dn = norm_tick(lo - off * pt)
        cb = cand.get(entry_t - sec)
        if cb is None: why = "nel dump non c'e' la candela che chiude a quell'ora"
        else:
            vd = 1 if cb[2] - up > tol else (-1 if dn - cb[2] > tol else 0)
            if entry_t <= place_t: why = "la candela del CSV si chiude prima del piazzamento"
            elif vd == 0: why = "la candela del CSV NON chiude fuori dal range"
            elif tc != entry_t and entry_t > tc: why = "la candela del CSV non e' la prima valida"
            elif tc != entry_t: why = "la prima valida e' piu' tarda di quella del CSV"
            else: why = "direzione diversa"
        c_cand.bad(f"{r['day']}: CSV dir {d:+d} entry {r['entry_time']}, python dir {dexp:+d} entry {fmt_t(tc)} ({why})")
        n_candle_skip += 1; continue
    jn = entry_bar(tc)
    if jn is None:
        c_cand.bad(f"{r['day']}: ingresso {fmt_t(tc)} NON eseguibile (nessuna barra M1 entro 900 s) ma presente nel CSV")
        n_candle_skip += 1; continue
    n_rows_full += 1
    # campi evento
    if abs(v["entry_px"] - E0) > tol_px(r["entry_px"]): c_fld.bad(f"{r['day']}: entry_px {r['entry_px']} != close candela {E0:.8f}")
    raw = hi + off * pt if d > 0 else lo - off * pt
    lv = v["level_px"]
    if abs(lv - raw) > tick / 2 + 1e-8 or abs(lv - norm_tick(lv)) > 5e-8:
        c_fld.bad(f"{r['day']}: level_px {r['level_px']} != {'hi' if d > 0 else 'lo'}{'+' if d > 0 else '-'}offset normalizzato a tick {tick:g} ({raw:.8f})")
    slip = (d * (E0 - lv) + (args.spread * pt if d > 0 else 0.0)) / pt      # prezzo pagato oltre il livello: il long entra all'ask (bid + spread)
    if abs(v["slip_pts"] - slip) > tol_pts(r["slip_pts"]): c_fld.bad(f"{r['day']}: slip_pts {r['slip_pts']} != {slip:.3f}")
    dly = (tc - place_t) / 60.0
    if abs(v["delay_min"] - dly) > max(1e-6, 0.5 * 10 ** (-ndec(r["delay_min"])) + 1e-9): c_fld.bad(f"{r['day']}: delay_min {r['delay_min']} != {dly:g}")
    if abs(v["spread_pts"] - args.spread) > tol_pts(r["spread_pts"]): c_fld.bad(f"{r['day']}: spread_pts {r['spread_pts']} != {args.spread:g}")
    if abs(v["range_pts"] - (hi - lo) / pt) > tol_pts(r["range_pts"]): c_fld.bad(f"{r['day']}: range_pts {r['range_pts']} != (hi-lo)/point {(hi - lo) / pt:.3f}")
    # percorso
    oo, ff, aa, cc, Lh = path(jn, d, E0)
    if Lh < L: n_trunc += 1
    cfgs = [("R_ref", ref_sl, args.ref_rr, "")] if ref_sl is not None else []
    for i in range(6):
        for m in (1, 2, 3): cfgs.append((f"R_s{i}_m{m}", slv[i], float(m), r[f"sl{i}"]))
    for col, slp, mult, slstr in cfgs:
        if slp <= 0: continue
        SLd = slp * pt
        Rexp = (sim_fixed(oo, ff, aa, cc, SLd, mult * SLd) - comm) / SLd
        n_cells += 1
        try: Rg = float(r[col])
        except ValueError: c_R.bad(f"{r['day']}: {col}='{r[col]}' non numerico (atteso {Rexp:.4f})"); continue
        if math.isnan(Rg) or abs(Rg - Rexp) > tol_R(r[col], Rexp, slstr, slp):
            c_R.bad(f"{r['day']} {d:+d} entry {r['entry_time']}: {col} script {r[col]} python {Rexp:.4f}")
    # mfe / pullback / fakeout (tutto l'orizzonte, nessuna correzione della barra d'ingresso)
    edge = hi if d > 0 else lo; opp = lo if d > 0 else hi
    Lrel = d * (edge - E0)
    mfe = (max(ff) - Lrel) / pt; pul = (Lrel - min(aa)) / pt
    fk = 1 if min(aa) <= d * (opp - E0) + tol else 0
    if abs(v["mfe_pts"] - mfe) > tol_pts(r["mfe_pts"]): c_mfe.bad(f"{r['day']}: mfe_pts script {r['mfe_pts']} python {mfe:.3f}")
    if abs(v["pullback_pts"] - pul) > tol_pts(r["pullback_pts"]): c_mfe.bad(f"{r['day']}: pullback_pts script {r['pullback_pts']} python {pul:.3f}")
    if int(v["fakeout"]) != fk: c_mfe.bad(f"{r['day']}: fakeout script {r['fakeout']} python {fk}")

c_fmt.note = f"{len(rows)} righe nel CSV ({len(mine)} della variante {vname}), ref_sl_pts {ref_sl if ref_sl is not None else 'ignoto'}"
c_cand.note = f"{len(mine)} eventi {vname} confrontati con le candele ricalcolate dal dump ({len(cand)} candele), {n_candle_skip} saltati nei controlli successivi"
c_fld.note = f"{n_rows_full} eventi"
c_R.note = f"{n_cells} celle su {n_rows_full} eventi, orizzonte {L} barre ({n_trunc} eventi con orizzonte troncato a fine dati)"
c_mfe.note = f"{n_rows_full} eventi"

# ---- completezza (range orario semplice)
n_unverif = 0
if args.rhs is not None:
    rhs, rhe, wrap = args.rhs, args.rhe, args.rhe <= args.rhs

    def hourly_range(D):
        t0 = D - (args.days_back + (1 if wrap else 0)) * 86400 + rhs * 60; t1 = D + rhe * 60
        if t0 < T[0]: return "incompleto", t0, t1, 0.0, 0.0
        ja = bisect.bisect_left(T, t0); jb = bisect.bisect_left(T, t1)
        if jb - ja < max(1, args.min_bars): return "invalido", t0, t1, 0.0, 0.0
        hi = max(H[ja:jb]); lo = min(Lw[ja:jb])
        w = (hi - lo) / pt
        if not hi > lo or lo <= 0 or (args.min_width > 0 and w < args.min_width) or (args.max_width > 0 and w > args.max_width): return "invalido", t0, t1, hi, lo
        return "ok", t0, t1, hi, lo

    # piazzamento: il piazzamento della coppia non dipende dalla variante (e' la logica dell'EA, verificata dalla batteria contro l'EA reale):
    # si usa il place_time delle righe 'touch' dello stesso CSV. Una chiusura oltre il livello implica un tocco dopo il piazzamento (stessa
    # barra o precedente), quindi i giorni con un evento a chiusura sono un sottoinsieme dei giorni con un evento al tocco.
    touch_place = {}
    for _ln0, r0 in rows:
        if r0.get("variant") == "touch":
            try: touch_place[parse_d(r0["day"])] = parse_t(r0["place_time"])
            except Exception: pass

    def placement(D, hi, lo, t1):
        tp0 = touch_place.get(D)
        if tp0 is None: return -1
        j = bisect.bisect_left(T, tp0)
        return j if j < n and T[j] == tp0 else -1

    st = collections.Counter(); exp_days = {}; trunc_days = set()
    dl = days_all[:-1] if args.skip_last_day else days_all
    for D in dl:
        status, t0, t1, hi, lo = hourly_range(D)
        if status == "incompleto":
            n_unverif += 1; st["range non completo nei dati"] += 1; continue
        pr = parsed.get(D)
        if pr is not None:
            chi, clo = pr[2]["range_hi"], pr[2]["range_lo"]
            if status == "ok":
                if abs(chi - hi) > 1e-6 or abs(clo - lo) > 1e-6:
                    c_rng.bad(f"{pr[1]['day']}: CSV hi/lo {pr[1]['range_hi']}/{pr[1]['range_lo']} vs ricalcolo [{fmt_t(t0)}, {fmt_t(t1)}) {hi:.8f}/{lo:.8f}")
            else: c_rng.bad(f"{pr[1]['day']}: il ricalcolo orario non da' un range valido ma il CSV ha un evento")
            hi, lo = chi, clo; st["giorni con range (CSV)"] += 1
        elif status != "ok": st["senza range valido"] += 1; continue
        else: st["giorni con range (ricalcolato)"] += 1
        if not hi > lo: continue
        jp = placement(D, hi, lo, t1)
        if jp < 0: st["senza piazzamento"] += 1; continue
        st["piazzati"] += 1
        pX = D + (WE + EXTRA) * 60
        ex = first_confirm(T[jp], hi, lo, pX)
        if ex is None: st["senza candela di conferma"] += 1; continue
        bk, dexp, E0 = ex; tc = bk + sec
        jn = entry_bar(tc)
        if jn is None: st["ingresso non eseguibile"] += 1; continue
        st["con evento atteso"] += 1
        if n - jn < L: trunc_days.add(D)
        exp_days[D] = (T[jp], dexp, tc)
    csv_days = set(parsed)
    verified = set(dl)
    missing_d = sorted(d for d in exp_days if d not in csv_days)
    extra_d = sorted(d for d in csv_days if d not in exp_days and d in verified and hourly_range(d)[0] != "incompleto")
    days_set = set(days_all)
    outside = sorted(d for d in csv_days if d not in days_set)
    n_mis_trunc = 0
    for D in missing_d:
        if D in trunc_days: n_mis_trunc += 1; continue
        pt_, dd_, tc_ = exp_days[D]
        c_cmp.bad(f"evento MANCANTE {fmt_t(D)[:10]}: atteso dir {dd_:+d}, piazzamento {fmt_t(pt_)}, entry {fmt_t(tc_)}")
    for D in extra_d:
        c_cmp.bad(f"evento IN PIU' {fmt_t(D)[:10]}: nel CSV (place {parsed[D][1]['place_time']}, entry {parsed[D][1]['entry_time']}) ma il ricalcolo non prevede piazzamento/conferma/ingresso eseguibile")
    for D in outside: c_cmp.bad(f"evento in un giorno senza dati nel dump: {fmt_t(D)[:10]}")
    n_pl = 0
    for D in sorted(csv_days & set(exp_days)):
        n_pl += 1
        if parse_t(parsed[D][1]["place_time"]) != exp_days[D][0]:
            c_cmp.bad(f"{fmt_t(D)[:10]}: place_time CSV {parsed[D][1]['place_time']} python {fmt_t(exp_days[D][0])}")
    c_cmp.note = (f"{len(dl)} giorni del dump, range {rhs // 60:02d}:{rhs % 60:02d}-{rhe // 60:02d}:{rhe % 60:02d}"
                  f"{' (giorno prima)' if wrap else ''} giorni_indietro {args.days_back}; range validi {st['giorni con range (CSV)'] + st['giorni con range (ricalcolato)']}, piazzati {st['piazzati']}, eventi attesi {len(exp_days)}, nel CSV {len(csv_days)}, "
                  f"mancanti {len(missing_d) - n_mis_trunc}, in piu' {len(extra_d)}, place_time confrontati {n_pl}; non verificabili {n_unverif} (range non completo nei dati); "
                  f"assenti con orizzonte troncato (non contati) {n_mis_trunc}")
    c_rng.note = f"{sum(1 for D in csv_days if D in verified)} giorni con evento"
else:
    c_cmp.note = "NON ESEGUITA: manca --rhs/--rhe (solo le righe presenti sono verificate; nessun controllo su eventi mancanti o in piu')"
    c_rng.note = "NON ESEGUITO (manca --rhs/--rhe)"
    c_cmp.skipped = c_rng.skipped = True

for c in checks: c.show()
print("COPERTURA: completa (ogni giorno del dump) = presenza/assenza dell'evento, place_time, hi/lo orari" + (" [eseguita]" if args.rhs is not None else " [NON eseguita]") +
      "; solo sugli eventi presenti = candela di conferma, campi, R, mfe/pullback/fakeout; non verificati = atr_pts, executed, R_ea, giorno occupato")
finish()
