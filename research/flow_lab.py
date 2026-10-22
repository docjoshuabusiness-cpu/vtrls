#!/usr/bin/env python3
"""
flow_lab.py - banco di prova per SyntheticDelta v3.x su QUALUNQUE simbolo e timeframe, nello spirito di
SignalLab_MultiTF. Si parte da un file di barre (di norma M1: Dukascopy, export di MT5, QDM, script di export)
e si ricampiona in ogni TF richiesto.

Dal tuo lab: ingresso all'open della barra dopo il segnale, costo = spread + commissione sempre inclusi,
orizzonti in minuti uguali per tutti i TF, split in-sample / out-of-sample per giorni, errore standard
raggruppato per giorno, Bonferroni su TUTTI i test (TF x feature x orizzonte), scomposizione pnl = M + s*D.
In piu': regressione continua su tutte le barre (piu' potenza degli eventi), placebo a traslazione di giorni
interi (conserva autocorrelazione e orario), calcolo della potenza (quale IC si riesce a vedere).

  python3 -I flow_lab.py --csv AUDJPY_M1.csv --tfs M5,M15,M30,H1,H4 --cost-pts 12 --comm-pts 9
  python3 -I flow_lab.py --selftest      # calibrazione su dati con verita' nota
  python3 -I flow_lab.py --parity        # versione veloce contro il riferimento barra per barra
"""
import argparse
import calendar
import itertools
import math
import os
import sys
import time as _time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_fast as ff

NAN = float("nan")
TFS = [("M1", 60), ("M2", 120), ("M3", 180), ("M4", 240), ("M5", 300), ("M6", 360), ("M10", 600), ("M12", 720),
       ("M15", 900), ("M20", 1200), ("M30", 1800), ("H1", 3600), ("H2", 7200), ("H3", 10800), ("H4", 14400),
       ("H6", 21600), ("H8", 28800), ("H12", 43200), ("D1", 86400)]
HORIZONS_MIN = [1, 2, 3, 5, 10, 15, 30, 45, 60, 120, 240, 1440]      # come InpHorizons del lab


# ================================================================= lettura dati ==
def _enc(path):
    with open(path, "rb") as f:
        b = f.read(4)
    if b[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return "utf-16"
    return "utf-8-sig" if b[:3] == b"\xef\xbb\xbf" else "utf-8"


def _epoch(strs):
    """epoch in secondi da: epoch, dd.mm.yyyy HH:MM[:SS[.fff]] (Dukascopy), yyyy.mm.dd / yyyy-mm-dd / yyyy/mm/dd"""
    s0 = strs[0]
    if s0.isdigit():
        a = np.array(strs, dtype=np.int64)
        return a // 1000 if a[0] >= 10 ** 11 else a
    out = []
    dukas = len(s0) >= 10 and s0[2] == "." and s0[5] == "."
    for s in strs:
        tm = s[11:19] if len(s) > 10 else "00:00:00"
        if len(tm) == 5:
            tm += ":00"
        if dukas:
            out.append(s[6:10] + "-" + s[3:5] + "-" + s[0:2] + "T" + tm)
        else:
            out.append(s[0:4] + "-" + s[5:7] + "-" + s[8:10] + "T" + tm)
    return np.array(out, dtype="datetime64[s]").astype(np.int64)


def load_bars(path, chunk=250000):
    """-> dict t,o,h,l,c,v (+ sp se c'e' lo spread) e digits. Streaming a blocchi: regge anni di M1."""
    with open(path, encoding=_enc(path), newline="") as f:
        head = f.readline().rstrip("\r\n")
        delim = "\t" if "\t" in head else (";" if ";" in head and "," not in head else ",")
        hdr = [x.strip().strip('<>"').lower() for x in head.split(delim)]

        def ix(*names):
            for nm in names:
                if nm in hdr:
                    return hdr.index(nm)
            return None

        i_d, i_tm = ix("date"), ix("time", "gmt time", "local time", "datetime", "timestamp")
        two = i_d is not None and "time" in hdr
        if i_tm is None and hdr and hdr[0] == "":
            i_tm = 0
        i_o, i_h, i_l, i_c = ix("open"), ix("high"), ix("low"), ix("close")
        i_v = ix("tickvol", "tick_volume", "tickvolume", "volume", "vol")
        i_s = ix("spread")
        if None in (i_tm, i_o, i_h, i_l, i_c, i_v):
            raise SystemExit("colonne non riconosciute: %s (servono tempo, open, high, low, close, volume)" % hdr)
        T, A, digits = [], [[], [], [], [], []], 0
        S = []
        while True:
            lines = list(itertools.islice(f, chunk))
            if not lines:
                break
            cols = list(zip(*[ln.rstrip("\r\n").split(delim) for ln in lines if ln.strip()]))
            if two:
                ts = [d.strip('"') + " " + tt.strip('"') for d, tt in zip(cols[i_d], cols[i_tm])]
            else:
                ts = [x.strip('"') for x in cols[i_tm]]
            T.append(_epoch(ts))
            for k, ci in enumerate((i_o, i_h, i_l, i_c, i_v)):
                A[k].append(np.array(cols[ci], dtype=float))
            if i_s is not None:
                S.append(np.array(cols[i_s], dtype=float))
            if digits == 0:
                digits = max((len(x.split(".")[1]) if "." in x else 0) for x in cols[i_o][:2000])
    t = np.concatenate(T)
    d = {k: np.concatenate(a) for k, a in zip(("o", "h", "l", "c", "v"), A)}
    d["t"] = t
    if S:
        d["sp"] = np.concatenate(S)
    if not np.all(np.diff(t) > 0):                      # ordina e toglie i duplicati
        order = np.argsort(t, kind="stable")
        keep = np.concatenate(([True], np.diff(t[order]) > 0))
        idx = order[keep]
        d = {k: a[idx] for k, a in d.items()}
    d["digits"] = digits
    return d


def resample(b, psec_base, psec, off):
    """barre di durata psec dalle barre di base; il bucket parte da off secondi (allineamento a ora server)"""
    if psec == psec_base:
        return b
    bk = (b["t"] + off) // psec
    st = np.concatenate(([0], np.flatnonzero(np.diff(bk)) + 1))
    en = np.concatenate((st[1:] - 1, [len(bk) - 1]))
    out = {"t": bk[st] * psec - off, "o": b["o"][st], "h": np.maximum.reduceat(b["h"], st),
           "l": np.minimum.reduceat(b["l"], st), "c": b["c"][en], "v": np.add.reduceat(b["v"], st)}
    if "sp" in b:
        out["sp"] = b["sp"][st]                         # spread della prima barra M1 del bucket = quello d'ingresso
    return out


# ================================================================= statistiche ==
def norm_sf(z):
    return 0.5 * math.erfc(abs(z) / math.sqrt(2.0))


def zcrit(m, alpha=0.05):
    lo, hi = 0.0, 10.0
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        if 2.0 * norm_sf(mid) > alpha / max(1, m):
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def day_starts(day):
    return np.concatenate(([0], np.flatnonzero(np.diff(day) != 0) + 1))


def cluster_t(x, day):
    n = len(x)
    if n < 3:
        return NAN, 0.0
    mu = x.mean()
    S = np.add.reduceat(x - mu, day_starts(day))
    se = math.sqrt(float((S * S).sum())) / n
    return mu, (mu / se if se > 0 else 0.0)


def slope_t(f, r, day):
    """pendenza di r su f (in dev.std), t con errore standard raggruppato per giorno, IC di Pearson"""
    n = len(f)
    if n < 20:
        return NAN, 0.0, NAN
    sf = f.std()
    if sf <= 0:
        return NAN, 0.0, NAN
    z = (f - f.mean()) / sf
    rc = r - r.mean()
    sxx = float((z * z).sum())
    beta = float((z * rc).sum()) / sxx
    S = np.add.reduceat(z * (rc - beta * z), day_starts(day))
    se = math.sqrt(float((S * S).sum())) / sxx
    sr = r.std()
    return beta, (beta / se if se > 0 else 0.0), (beta / sr if sr > 0 else NAN)


def n_eff_regress(z, H):
    zc = z[~np.isnan(z)]
    zc = zc - zc.mean()
    var = float((zc * zc).mean())
    infl = 1.0
    for k in range(1, min(H, len(zc) - 1)):
        infl += 2.0 * float((zc[:-k] * zc[k:]).mean()) / var * (1.0 - k / H)
    return len(zc) / max(infl, 1e-9)


def min_ic(n_eff):
    return (1.959964 + 0.841621) / math.sqrt(max(n_eff, 1.0))


def fwd_returns(o, c, t, psec, H, lag):
    """r[i] = c[x] - o[e], e = i+1+lag (open), x = e+H-1 (chiusura); scartati i casi con un buco di dati"""
    n = len(c)
    r = np.full(n, np.nan)
    en = np.full(n, -1)
    i = np.arange(n)
    e = i + 1 + lag
    x = e + H - 1
    ok = x < n
    ie, ee, xx = i[ok], e[ok], x[ok]
    good = ((t[xx] - t[ee]) == (H - 1) * psec) & ((t[ee] - t[ie]) == (1 + lag) * psec)
    r[ie[good]] = c[xx[good]] - o[ee[good]]
    en[ie[good]] = ee[good]
    return r, en


def split_masks(day, pct):
    ud = np.unique(day)
    sday = ud[min(len(ud) - 1, int(len(ud) * pct / 100.0))]
    return day < sday, day >= sday


def events_dir(Z, thr):
    ok = ~np.isnan(Z)
    prev = np.concatenate(([np.nan], Z[:-1]))
    up = ok & (Z >= thr) & ~(prev >= thr)
    dn = ok & (Z <= -thr) & ~(prev <= -thr)
    return up.astype(int) - dn.astype(int)


def event_stats(dirs, side, r, en, cost, point, day, mask):
    """n, lordo medio, netto medio, t del netto, t dell'abilita' cov(s, D): tutto in punti"""
    k = mask & (dirs != 0) & ~np.isnan(r)
    n = int(k.sum())
    if n < 5:
        return n, NAN, NAN, 0.0, 0.0
    s = side * dirs[k].astype(float)
    d = day[k]
    g = s * r[k] / point
    net = g - cost[en[k]]
    _, tn = cluster_t(net, d)
    _, tsk = cluster_t((s - s.mean()) * r[k] / point, d)
    return n, g.mean(), net.mean(), tn, tsk


def shift_null(Z, stat_fn, bars_per_day, B, seed=7):
    """statistica con Z traslato di giorni interi: conserva orario e autocorrelazione, rompe il legame col futuro"""
    rng = np.random.default_rng(seed)
    maxk = max(3, len(Z) // bars_per_day - 2)
    return np.array([stat_fn(np.roll(Z, int(rng.integers(2, maxk)) * bars_per_day)) for _ in range(B)])


def pval(obs, null):
    null = null[~np.isnan(null)]
    return (1.0 + float((np.abs(null) >= abs(obs)).sum())) / (len(null) + 1.0)


# ================================================================= feature ======
def tf_features(b, psec, N, M, D):
    t, o, h, l, c, v = (b[k] for k in ("t", "o", "h", "l", "c", "v"))
    f = {}
    for name, mode, uw in (("Z_clv_pesato", "clv", True), ("Z_clv_piatto", "clv", False),
                           ("Z_bvc_pesato", "bvc", True), ("Z_bvc_piatto", "bvc", False)):
        r = ff.flow_features(t, o, h, l, c, v, psec, N=N, M=M, D=D, mode=mode, use_weights=uw)
        f[name] = r["Z"]
        if name == "Z_clv_pesato":
            f["assorbimento"] = r["Ab"]
    f["vecchio_delta"] = ff.legacy_nd(h, l, c, v)
    atr = ff.atr_series(h, l, c, 14)
    atr = np.where(atr > 0, atr, np.nan)            # barre piatte: ATR nullo = feature non definita, non infinito
    mom = np.full(len(c), np.nan)
    mom[N:] = (c[N:] - c[:-N]) / (atr[N:] * math.sqrt(N))
    f["momentum"] = ff.roll_z_series(mom, M)
    f["trend_EMA13"] = ff.roll_z_series((c - ff.ema_series(c, 13)) / atr, M)
    return f


# ================================================================= runner ========
def run(base, psec_base, args):
    off = int(args.offset_h * 3600)
    point = args.point or 10.0 ** (-base["digits"])
    has_sp = "sp" in base
    names = [x.strip().upper() for x in args.tfs.split(",")]
    tfmap = dict(TFS)
    allrows, evrows, tfinfo, cache = [], [], [], {}
    t0 = _time.time()
    print("=" * 110)
    print("DATI: %d barre base (%d s) | %s -> %s | punto %g | costo: %s + commissione %.1f pt | split %d%% | offset %+.1f h" % (
        len(base["t"]), psec_base, np.datetime_as_string(np.datetime64(int(base["t"][0]), "s")),
        np.datetime_as_string(np.datetime64(int(base["t"][-1]), "s")), point,
        "spread del file" if has_sp else "FISSO %.1f pt (il file non ha lo spread: valore di esempio, mettilo tu con --cost-pts)" % args.cost_pts,
        args.comm_pts, args.split, args.offset_h))
    if args.comm_pts <= 0:
        print("ATTENZIONE: commissione = 0 (--comm-pts): su un conto Raw i risultati lordi/netti sono ottimisti. Usa il valore in punti che stampa il tuo lab.")
    for nm in names:
        if nm not in tfmap or tfmap[nm] < psec_base or tfmap[nm] % psec_base:
            print("TF %s ignorato (non supportato o piu' fine dei dati di base)." % nm)
            continue
        psec = tfmap[nm]
        b = resample(base, psec_base, psec, off)
        n = len(b["c"])
        if n < 2000:
            print("TF %s: solo %d barre, saltato." % (nm, n))
            continue
        t = b["t"]
        day = ((t + off) // 86400).astype(int)
        is_m, oos_m = split_masks(day, args.split)
        cost = (b["sp"] + args.comm_pts) if has_sp else np.full(n, args.cost_pts + args.comm_pts)
        feats = tf_features(b, psec, args.N, args.M, args.days)
        hs = [(m, m * 60 // psec) for m in (args.horizons or HORIZONS_MIN) if (m * 60) % psec == 0 and m * 60 >= psec and m * 60 // psec <= n // 50]
        rets = {H: fwd_returns(b["o"], b["c"], t, psec, H, args.lag) for _, H in hs}
        z0 = feats["Z_clv_pesato"]
        ac1 = float(np.corrcoef(z0[~np.isnan(z0)][:-1], z0[~np.isnan(z0)][1:])[0, 1])
        ne = {H: n_eff_regress(z0, H) for _, H in hs}
        tfinfo.append((nm, n, int((~np.isnan(z0)).sum()), ac1, {m: min_ic(ne[H]) for m, H in hs}))
        cache[nm] = (b, psec, day, is_m, oos_m, cost, feats, rets, hs)
        for fn, fz in feats.items():
            for m, H in hs:
                r = rets[H][0]
                res = {}
                for lab, mk in (("all", is_m | oos_m), ("is", is_m), ("oos", oos_m)):
                    k = mk & ~np.isnan(fz) & ~np.isnan(r)
                    res[lab] = slope_t(fz[k], r[k], day[k]) if k.sum() >= 200 else (NAN, 0.0, NAN)
                    res[lab + "_n"] = int(k.sum())
                allrows.append(dict(tf=nm, feat=fn, m=m, H=H, n=res["all_n"], beta=res["all"][0], t=res["all"][1], ic=res["all"][2],
                                    t_is=res["is"][1], t_oos=res["oos"][1], ic_oos=res["oos"][2], n_oos=res["oos_n"]))
        # eventi del Z principale: scelta in-sample, verifica fuori campione
        cells = []
        for thr in (1.0, 1.5, 2.0):
            dirs = events_dir(z0, thr)
            for m, H in hs:
                r, en = rets[H]
                for side, sn in ((1, "SEGUI"), (-1, "INVERTI")):
                    cells.append((thr, m, H, sn, side, event_stats(dirs, side, r, en, cost, point, day, is_m),
                                  event_stats(dirs, side, r, en, cost, point, day, oos_m)))
        okc = [x for x in cells if x[5][0] >= 30 and not math.isnan(x[5][2])]
        okc.sort(key=lambda x: -x[5][3])
        if okc:
            thr, m, H, sn, side, a, bb = okc[0]
            evrows.append(dict(tf=nm, thr=thr, m=m, H=H, side=sn, is_n=a[0], is_net=a[2], is_t=a[3], oos_n=bb[0], oos_gross=bb[1],
                               oos_net=bb[2], oos_t=bb[3], oos_skill_t=bb[4], ncells=len(cells)))
        print("  TF %-3s pronto: %d barre, %d feature x %d orizzonti (%.0f s)" % (nm, n, len(feats), len(hs), _time.time() - t0))
        sys.stdout.flush()
    if not allrows:
        print("Nessun TF analizzabile.")
        return
    # ---- potenza
    print("\n[1] POTENZA: IC minimo che il campione riesce a vedere (80% potenza, 5%) per Z_clv_pesato, sull'INTERO periodo")
    print("    Z e' molto autocorrelato: il campione efficace e' una frazione delle barre. Sul solo periodo di verifica l'IC minimo e' ~1.7 volte piu' alto.")
    ms = sorted({m for tf in tfinfo for m in tf[4]})
    print("    %-4s %8s %8s %6s | " % ("TF", "barre", "Z valid", "ac(1)") + " ".join("%6s" % ("%dm" % m) for m in ms))
    for nm, n, nz, ac1, mi in tfinfo:
        print("    %-4s %8d %8d %6.2f | " % (nm, n, nz, ac1) + " ".join("%6.3f" % mi[m] if m in mi else "%6s" % "-" for m in ms))
    # ---- regressioni
    nt = len(allrows)
    zb = zcrit(nt)
    print("\n[2] REGRESSIONE DEL RENDIMENTO FUTURO SU OGNI FEATURE: %d test (TF x feature x orizzonte). Bonferroni 5%%: |t| >= %.2f" % (nt, zb))
    top = sorted(allrows, key=lambda r: -abs(r["t"]))[:args.topk]
    print("    Prime %d per |t| sull'intero periodo (t con errore standard raggruppato per giorno). IS/OOS = metta' iniziale/finale (70/30)." % len(top))
    # placebo sulle celle migliori
    for r in top:
        b, psec, day, is_m, oos_m, cost, feats, rets, hs = cache[r["tf"]]
        fz, rr = feats[r["feat"]], rets[r["H"]][0]

        def tall(zz, rr=rr, day=day):
            k = ~np.isnan(zz) & ~np.isnan(rr)
            return slope_t(zz[k], rr[k], day[k])[1] if k.sum() >= 200 else 0.0

        B = args.B if len(fz) < 400000 else max(40, args.B // 4)
        r["p"] = pval(r["t"], shift_null(fz, tall, 86400 // psec, B))
    print("    %-4s %-14s %5s | %9s %6s %7s | %6s %6s %8s | %8s | %s" % ("TF", "feature", "orizz", "n", "t", "IC", "t IS", "t OOS", "IC OOS", "placebo p", "giudizio"))
    ncand = 0
    for r in top:
        same = (r["t_is"] * r["t_oos"] > 0) and abs(r["t_oos"]) >= 1.96
        cand = abs(r["t"]) >= zb and r["p"] < 0.05 and same
        ncand += cand
        j = "CANDIDATO" if cand else ("supera Bonferroni ma non regge" if abs(r["t"]) >= zb else ("*" if abs(r["t"]) >= 1.96 else ""))
        print("    %-4s %-14s %4dm | %9d %6.2f %7.3f | %6.2f %6.2f %8.3f | %8.3f | %s" % (r["tf"], r["feat"], r["m"], r["n"], r["t"], r["ic"], r["t_is"], r["t_oos"], r["ic_oos"], r["p"], j))
    npass = sum(abs(r["t"]) >= zb for r in allrows)
    # ---- Z contro riferimenti banali, a parita' di orizzonte
    print("\n    Z_clv_pesato contro i riferimenti, t medio assoluto sull'intero periodo (se Z non batte momentum/trend/piatto non aggiunge nulla):")
    for fn in ("Z_clv_pesato", "Z_clv_piatto", "Z_bvc_pesato", "Z_bvc_piatto", "assorbimento", "vecchio_delta", "momentum", "trend_EMA13"):
        ts = [abs(r["t"]) for r in allrows if r["feat"] == fn]
        print("      %-14s |t| medio %.2f  max %.2f  (%d test)" % (fn, np.mean(ts), np.max(ts), len(ts)))
    # ---- eventi
    print("\n[3] EVENTI (primo attraversamento di +-soglia di Z_clv_pesato; ingresso all'open dopo; costo incluso): miglior cella in-sample per TF, risultato fuori campione")
    print("    %-4s %5s %5s %-8s | %6s %8s %6s | %6s %8s %8s %6s %7s" % ("TF", "soglia", "tenuta", "verso", "IS n", "IS netto", "IS t", "OOS n", "OOS lordo", "OOS netto", "t", "t abil."))
    for e in evrows:
        print("    %-4s %5.1f %4dm %-8s | %6d %8.1f %6.2f | %6d %9.1f %8.1f %6.2f %7.2f" % (e["tf"], e["thr"], e["m"], e["side"], e["is_n"], e["is_net"], e["is_t"], e["oos_n"], e["oos_gross"], e["oos_net"], e["oos_t"], e["oos_skill_t"]))
    npos = sum(1 for e in evrows if e["oos_n"] >= 30 and e["oos_net"] > 0 and e["oos_t"] >= 2.0)
    # ---- verdetto
    print("\n[4] LETTURA")
    print("    Test di regressione: %d, superano Bonferroni %d; candidati (Bonferroni + placebo p<0.05 + stesso segno e |t|>=1.96 in entrambe le meta'): %d." % (nt, npass, ncand))
    print("    Eventi: su %d TF, la cella scelta in-sample e' positiva al netto fuori campione con t>=2 in %d (per caso se ne attendono circa %.1f)." % (len(evrows), npos, 0.0228 * len(evrows)))
    if ncand == 0 and npos == 0:
        print("    Nessuna evidenza di un vantaggio. NON e' una prova che non esista: guarda nella tabella [1] l'IC minimo rilevabile.")
    else:
        print("    Candidati da confermare su altri simboli e su un periodo successivo: la scelta fra tante celle gonfia il migliore.")
    if args.out:
        import csv
        with open(args.out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(allrows[0].keys()))
            w.writeheader()
            w.writerows(allrows)
        print("    Tutte le celle in %s" % args.out)


# ================================================================= selftest ======
def gen_dgp(days=260, beta=0.0, gamma=0.30, phi=0.9, seed=1, psec=3600):
    """Flusso nascosto AR(1) persistente. Il prezzo reagisce all'INNOVAZIONE del flusso (il CLV la rivela) e,
    con beta > 0, anche al LIVELLO ritardato del flusso (informazione che Z puo' prevedere)."""
    rng = np.random.default_rng(seed)
    t0 = calendar.timegm((2026, 1, 5, 0, 0, 0))
    bpd, m = 86400 // psec, 12
    T, O, H, L, C, V = [], [], [], [], [], []
    px, act, f_prev = 1.1, 0.0, 0.0
    s_eta = math.sqrt(1.0 - phi * phi)
    for d in range(days):
        if d % 7 >= 5:
            continue
        for s in range(bpd):
            hr = s * psec / 3600.0
            base = 100.0 * (0.35 + 1.1 * math.exp(-((hr - 8) / 1.8) ** 2) + 1.6 * math.exp(-((hr - 14.5) / 1.5) ** 2) + 0.25 * math.exp(-((hr - 2) / 2) ** 2))
            act = 0.97 * act + 0.10 * rng.standard_normal()
            eta = s_eta * rng.standard_normal()
            f = phi * f_prev + eta
            sig = 4e-5 * math.exp(0.5 * act)
            path = px + np.cumsum(sig * (rng.standard_normal(m) + gamma * eta / s_eta + beta * f_prev))
            T.append(t0 + d * 86400 + s * psec)
            O.append(px)
            H.append(max(px, path.max()))
            L.append(min(px, path.min()))
            C.append(path[-1])
            V.append(max(1.0, round(base * math.exp(0.8 * act + 0.3 * rng.standard_normal()) * (1.0 + 0.3 * abs(eta / s_eta)))))
            f_prev, px = f, path[-1]
    r5 = lambda a: np.round(np.array(a), 5)
    return {"t": np.array(T, dtype=np.int64), "o": r5(O), "h": r5(H), "l": r5(L), "c": r5(C), "v": np.array(V, float), "digits": 5}


def gen_fast(days=700, psec=60, seed=3):
    """generatore vettorializzato di barre sintetiche (per prove di velocita' e di tubazione)"""
    rng = np.random.default_rng(seed)
    bpd = 86400 // psec
    d = np.arange(days)
    d = d[d % 7 < 5]
    t = (calendar.timegm((2026, 1, 5, 0, 0, 0)) + d[:, None] * 86400 + np.arange(bpd)[None, :] * psec).ravel().astype(np.int64)
    n = len(t)
    hr = (t % 86400) / 3600.0
    base = 100.0 * (0.35 + 1.1 * np.exp(-((hr - 8) / 1.8) ** 2) + 1.6 * np.exp(-((hr - 14.5) / 1.5) ** 2) + 0.25 * np.exp(-((hr - 2) / 2) ** 2))
    act = np.zeros(n)
    e = 0.1 * rng.standard_normal(n)
    for i in range(1, n):
        act[i] = 0.9995 * act[i - 1] + e[i]
    sig = 2e-5 * np.exp(0.5 * act)
    st = rng.standard_normal((n, 4)) * sig[:, None]
    cum = np.cumsum(st.sum(1))
    o = 1.1 + np.concatenate(([0.0], cum[:-1]))
    path = o[:, None] + np.cumsum(st, axis=1)
    return {"t": t, "o": np.round(o, 5), "h": np.round(np.maximum(o, path.max(1)), 5), "l": np.round(np.minimum(o, path.min(1)), 5),
            "c": np.round(path[:, -1], 5), "v": np.maximum(1.0, np.round(base * np.exp(0.8 * act + 0.3 * rng.standard_normal(n)))), "digits": 5}


def parity():
    import syntheticdelta_ref as sd
    ok_all = True
    for psec, days in ((3600, 90), (900, 40)):
        b = gen_dgp(days=days, seed=5, psec=psec)
        T, H, L, C, V = (b[k].tolist() for k in ("t", "h", "l", "c", "v"))
        for mode, uw in (("clv", True), ("clv", False), ("bvc", True), ("bvc", False)):
            ind = sd.SyntheticDelta(psec, flow_mode=mode, use_weights=uw)
            ind.on_calculate(T, H, L, C, V, 0)
            f = ff.flow_features(b["t"], b["o"], b["h"], b["l"], b["c"], b["v"], psec, mode=mode, use_weights=uw)
            for ref_k, k in (("Z", "Z"), ("Ab", "Ab")):
                a, x = np.array(ind.b[ref_k], float), f[k]
                same = np.array_equal(np.isnan(a), np.isnan(x))
                md = float(np.nanmax(np.abs(a - x))) if (~np.isnan(a) & ~np.isnan(x)).any() else 0.0
                ok = same and md < 1e-9
                ok_all &= ok
                print("psec %5d %-3s peso=%-5s %-2s: NaN uguali %-5s diff max %.1e  %s" % (psec, mode, uw, ref_k, same, md, "OK" if ok else "FAIL"))
    print("PARITA' VELOCE/RIFERIMENTO:", "OK" if ok_all else "FALLITA")
    return 0 if ok_all else 1


def selftest(reps, B):
    psec = 3600
    hs = (1, 6, 12)
    print("CALIBRAZIONE SU DATI SINTETICI CON VERITA' NOTA (H1, ~%d barre, flusso persistente phi=0.9, %d repliche)\n" % (260 * 5 // 7 * 24, reps))
    print("Con beta=0 (nessun effetto) il tasso di rifiuto deve essere ~5%%. 't' = |t| raggruppato per giorno >= 1.96; 'placebo' = p < 0.05 con traslazione di giorni interi (%d estrazioni, H=6)." % B)
    print("\n%5s %8s | %-24s %-24s | %-14s" % ("beta", "IC vero", "Z_clv_pesato  t (H=1,6,12)", "Z_clv_piatto  t (H=1,6,12)", "placebo H=6"))
    for beta in (0.0, 0.01, 0.02, 0.04):
        hit = {nm: np.zeros(len(hs)) for nm in ("Z_clv_pesato", "Z_clv_piatto")}
        pl, ics = 0, []
        for rep in range(reps):
            b = gen_dgp(beta=beta, seed=2000 + rep, psec=psec)
            t, o = b["t"], b["o"]
            day = (t // 86400).astype(int)
            is_m, oos_m = split_masks(day, 70)
            f = tf_features(b, psec, 12, 500, 20)
            for j, Hn in enumerate(hs):
                r, _ = fwd_returns(o, b["c"], t, psec, Hn, 0)
                for nm in hit:
                    k = oos_m & ~np.isnan(f[nm]) & ~np.isnan(r)
                    if k.sum() >= 200:
                        _, tt, ic = slope_t(f[nm][k], r[k], day[k])
                        hit[nm][j] += abs(tt) >= 1.96
                        if nm == "Z_clv_pesato" and Hn == 6:
                            ics.append(ic)
            r6, _ = fwd_returns(o, b["c"], t, psec, 6, 0)

            def tt6(zz, r6=r6, day=day, oos_m=oos_m):
                k = oos_m & ~np.isnan(zz) & ~np.isnan(r6)
                return slope_t(zz[k], r6[k], day[k])[1] if k.sum() >= 200 else 0.0

            pl += pval(tt6(f["Z_clv_pesato"]), shift_null(f["Z_clv_pesato"], tt6, 24, B, seed=rep)) < 0.05
        print("%5.2f %8.3f | %-24s %-24s | %.2f" % (beta, float(np.mean(ics)), "  ".join("%.2f" % x for x in hit["Z_clv_pesato"] / reps),
                                                     "  ".join("%.2f" % x for x in hit["Z_clv_piatto"] / reps), pl / reps))
        sys.stdout.flush()
    print("\n'IC vero' = IC medio di Z_clv_pesato a H=6 sul periodo di verifica (30%% dei dati).")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--parity", action="store_true")
    ap.add_argument("--perf", action="store_true", help="prova di velocita' su ~1M barre M1 sintetiche")
    ap.add_argument("--reps", type=int, default=60)
    ap.add_argument("--csv")
    ap.add_argument("--tfs", default="M5,M15,M30,H1,H4", help="elenco di TF oppure ALL")
    ap.add_argument("--point", type=float, default=0.0, help="valore di 1 punto in prezzo (0 = dalle cifre decimali del file)")
    ap.add_argument("--cost-pts", type=float, default=10.0, help="spread fisso in punti se il file non ha la colonna spread")
    ap.add_argument("--comm-pts", type=float, default=0.0, help="commissione andata e ritorno in punti (quella che stampa il lab)")
    ap.add_argument("--offset-h", type=float, default=0.0, help="ore da sommare all'orologio del file per allineare barre e giorni al server")
    ap.add_argument("--horizons", type=lambda s: [int(x) for x in s.split(",")], default=None, help="orizzonti in minuti")
    ap.add_argument("--N", type=int, default=12)
    ap.add_argument("--M", type=int, default=500)
    ap.add_argument("--days", type=int, default=20)
    ap.add_argument("--split", type=int, default=70)
    ap.add_argument("--B", type=int, default=200)
    ap.add_argument("--lag", type=int, default=0, help="ritardo d'ingresso in barre del TF")
    ap.add_argument("--topk", type=int, default=15)
    ap.add_argument("--out")
    a = ap.parse_args()
    if a.parity:
        sys.exit(parity())
    if a.selftest:
        selftest(a.reps, a.B)
        return
    if a.perf:
        t0 = _time.time()
        b = gen_fast()
        print("generate %d barre M1 in %.1f s" % (len(b["t"]), _time.time() - t0))
        a.tfs, a.B, a.topk = "M5,M15,H1,H4", 40, 6
        run(b, 60, a)
        print("totale %.1f s" % (_time.time() - t0))
        return
    if not a.csv:
        ap.error("serve --csv oppure --selftest/--parity/--perf")
    t0 = _time.time()
    base = load_bars(a.csv)
    psec_base = int(np.median(np.diff(base["t"][:200000])))
    print("letti %d record in %.1f s (passo di base %d s)" % (len(base["t"]), _time.time() - t0, psec_base))
    if a.tfs.upper() == "ALL":
        a.tfs = ",".join(n for n, s in TFS if s >= psec_base)
    run(base, psec_base, a)


if __name__ == "__main__":
    main()
