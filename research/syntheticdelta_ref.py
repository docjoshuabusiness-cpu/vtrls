#!/usr/bin/env python3
"""
syntheticdelta_ref.py - riferimento Python di MQL5/Indicators/SyntheticDelta_v3.0.mq5

Replica la STESSA macchina a stati dell'indicatore MQL5:
  - la storia stagionale del volume riceve solo barre CHIUSE, in ordine;
  - ogni chiamata ricalcola da prev_calculated-1;
  - la barra in formazione e' lasciata vuota (closed_only).
Serve a due cose: (1) verificare il DISEGNO (causalita', incrementale == completo)
senza compilare MQL5; (2) fare da oracolo numerico: esporta le barre da MT5,
lancia --csv e confronta i valori con quelli dell'indicatore.

NON verifica la sintassi MQL5: quella va controllata compilando in MetaEditor.

Uso:
  python3 -I syntheticdelta_ref.py --selftest
  python3 -I syntheticdelta_ref.py --csv barre.csv --out valori.csv [--psec 300] [--mode clv|bvc]
"""
import argparse
import calendar
import csv
import io
import math
import statistics
import sys
from datetime import datetime

import numpy as np

SQRT2 = 1.4142135623730951
NAN = float("nan")


def erf_as(x):
    """Abramowitz-Stegun 7.1.26, errore max 1.5e-7. Identica alla versione MQL5."""
    p, a1, a2, a3, a4, a5 = 0.3275911, 0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429
    s = -1.0 if x < 0.0 else 1.0
    ax = abs(x)
    t = 1.0 / (1.0 + p * ax)
    y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-ax * ax)
    return s * y


def norm_cdf(z):
    return 0.5 * (1.0 + erf_as(z / SQRT2))


class SyntheticDelta:
    BUFS = ("Z", "Zc", "Ab", "Leg", "Ev", "W", "Fb", "cF", "cF2", "cFn", "cA", "cA2", "cAn", "ema")

    def __init__(self, psec, flow_mode="clv", N=12, M=500, thr=1.5, D=20, min_sess=5, cap=3.0,
                 atr_p=14, bvc_bars=50, closed_only=True, show_legacy=True,
                 legacy_ema=13, legacy_vol=20, legacy_scale=10.0, use_weights=True):
        self.use_weights = use_weights
        self.psec, self.flow_mode, self.N, self.M, self.thr = psec, flow_mode, N, M, thr
        self.D, self.min_sess, self.cap, self.atr_p, self.bvc_bars = D, min_sess, cap, atr_p, bvc_bars
        self.closed_only, self.show_legacy = closed_only, show_legacy
        self.legacy_ema, self.legacy_vol, self.legacy_scale = legacy_ema, legacy_vol, legacy_scale
        self.slots = max(1, 86400 // psec)
        self.first = max(atr_p, bvc_bars, N) + 2
        self.b = {k: [] for k in self.BUFS}      # i buffer persistono fra le chiamate, come in MT5
        self.reset()

    # ---- stato stagionale -------------------------------------------------
    def reset(self):
        self.ring = {}
        self.pushed = -1

    def slot_of(self, t):
        s = (int(t) % 86400) // self.psec
        return min(s, self.slots - 1)

    def push(self, slot, v):
        r = self.ring.setdefault(slot, [])
        r.append(v)
        if len(r) > self.D:
            r.pop(0)

    def _alloc(self, total):
        for k, arr in self.b.items():
            fill = -1.0 if k == "W" else (NAN if k in ("Z", "Ab", "Leg") else 0.0)
            while len(arr) < total:
                arr.append(fill)

    # ---- z-score su finestra [i-M, i-1] via somme cumulate --------------------
    def roll_z(self, cs, cs2, cn, i, x):
        hi = i - 1
        if hi < 0:
            return False, 0.0
        lo = hi - self.M
        s = cs[hi] - (cs[lo] if lo >= 0 else 0.0)
        s2 = cs2[hi] - (cs2[lo] if lo >= 0 else 0.0)
        n = cn[hi] - (cn[lo] if lo >= 0 else 0.0)
        if n < 0.5 * self.M:
            return False, 0.0
        mu = s / n
        var = s2 / n - mu * mu
        if var <= 1e-12:
            return False, 0.0
        return True, (x - mu) / math.sqrt(var)

    def legacy_delta(self, i, h, l, c, v):
        if i < self.legacy_vol:
            return NAN
        rng = h[i] - l[i]
        if rng <= 0.0 or v[i] <= 0:
            return NAN
        ema = self.b["ema"][i]
        fb, fs = (c[i] - l[i]) / rng, (h[i] - c[i]) / rng
        bn, br = (h[i] - ema) / rng, (ema - l[i]) / rng
        sv = sum(float(v[j]) for j in range(i, i - self.legacy_vol, -1) if j >= 0)
        cnt = sum(1 for j in range(i, i - self.legacy_vol, -1) if j >= 0)
        avg = sv / cnt if cnt > 0 else float(v[i])
        vw = min(v[i] / avg, 3.0) if avg > 0.0 else 1.0
        return (fb * (1.0 + bn) - fs * (1.0 + br)) * vw / 6.0

    # ---- una barra ----------------------------------------------------------
    def compute_bar(self, i, total, t, h, l, c, v):
        b = self.b
        if self.show_legacy:
            a = 2.0 / (self.legacy_ema + 1.0)
            b["ema"][i] = c[i] if i == 0 else a * c[i] + (1.0 - a) * b["ema"][i - 1]
        for k in ("cF", "cF2", "cFn", "cA", "cA2", "cAn"):
            b[k][i] = b[k][i - 1] if i > 0 else 0.0
        b["Z"][i] = NAN
        b["Zc"][i] = 0.0
        b["Ab"][i] = NAN
        b["Leg"][i] = NAN
        b["Ev"][i] = 0.0
        b["W"][i] = -1.0
        b["Fb"][i] = 0.0

        if self.show_legacy:
            x = self.legacy_delta(i, h, l, c, v)
            b["Leg"][i] = NAN if math.isnan(x) else x * self.legacy_scale

        if i < self.first:
            return
        if self.closed_only and i == total - 1:
            return

        rng = h[i] - l[i]
        V = float(v[i])
        s_tr = 0.0
        for j in range(i - self.atr_p + 1, i + 1):
            s_tr += max(h[j], c[j - 1]) - min(l[j], c[j - 1])
        atr = s_tr / self.atr_p

        slot = self.slot_of(t[i])
        w = -1.0
        r = self.ring.get(slot, [])
        if len(r) >= self.min_sess:
            med = statistics.median(r)
            if med > 0.0:
                w = min(V / med, self.cap)
        if w < 0.0:
            return
        if not self.use_weights:
            w = 1.0              # A/B: stessa finestra di warm-up, ma ogni barra pesa uguale

        if self.flow_mode == "clv":
            d = ((c[i] - l[i]) - (h[i] - c[i])) / rng if rng > 0.0 else 0.0
        else:
            s2 = 0.0
            for j in range(i - self.bvc_bars + 1, i + 1):
                dd = c[j] - c[j - 1]
                s2 += dd * dd
            sg = math.sqrt(s2 / self.bvc_bars)
            d = 2.0 * norm_cdf((c[i] - c[i - 1]) / sg) - 1.0 if sg > 0.0 else 0.0
        b["W"][i] = w
        b["Fb"][i] = w * d

        sf = sw = 0.0
        for k in range(self.N):
            j = i - k
            if b["W"][j] < 0.0:
                return
            sf += b["Fb"][j]
            sw += b["W"][j]
        if sw <= 0.0:
            return
        F = sf / sw
        effort = sw / self.N

        ok, z = self.roll_z(b["cF"], b["cF2"], b["cFn"], i, F)
        b["cF"][i] += F
        b["cF2"][i] += F * F
        b["cFn"][i] += 1.0

        if atr > 0.0:
            res = abs(c[i] - c[i - self.N]) / (atr * math.sqrt(self.N))
            A = math.log(max(effort, 0.05)) - math.log(res + 0.1)
            okA, za = self.roll_z(b["cA"], b["cA2"], b["cAn"], i, A)
            b["cA"][i] += A
            b["cA2"][i] += A * A
            b["cAn"][i] += 1.0
            if okA:
                b["Ab"][i] = za
        if ok:
            b["Z"][i] = z
            b["Zc"][i] = 1.0 if z >= self.thr else (2.0 if z <= -self.thr else 0.0)
            # evento = primo attraversamento di +-soglia (barra precedente non valida o sotto soglia): +1 BUY, -1 SELL
            pz = b["Z"][i - 1] if i > 0 else NAN
            if z >= self.thr and not (pz >= self.thr):
                b["Ev"][i] = 1.0
            elif z <= -self.thr and not (pz <= -self.thr):
                b["Ev"][i] = -1.0

    # ---- OnCalculate --------------------------------------------------------
    def on_calculate(self, t, h, l, c, v, prev_calculated):
        total = len(t)
        if total < self.first + 2:
            return 0
        self._alloc(total)
        start = 0 if prev_calculated <= 0 else prev_calculated - 1
        if start == 0 or start <= self.pushed:
            self.reset()
            start = 0
        elif start > self.pushed + 1:
            start = self.pushed + 1
        for i in range(start, total):
            self.compute_bar(i, total, t, h, l, c, v)
            if i < total - 1 and i > self.pushed:
                self.push(self.slot_of(t[i]), float(v[i]))
                self.pushed = i
        return total


# ============================================================ dati sintetici ==
def gen_bars(days=60, psec=300, seed=7):
    """Barre OHLC + tick volume con profilo orario forte (apertura Londra/NY)."""
    rng = np.random.default_rng(seed)
    t0 = calendar.timegm((2026, 1, 5, 0, 0, 0))  # lunedi'
    T, O, H, L, C, V = [], [], [], [], [], []
    px, act = 1.1000, 0.0
    for d in range(days):
        if d % 7 >= 5:
            continue
        for s in range(86400 // psec):
            hr = s * psec / 3600.0
            base = 100.0 * (0.35 + 1.1 * math.exp(-((hr - 8) / 1.8) ** 2)
                            + 1.6 * math.exp(-((hr - 14.5) / 1.5) ** 2) + 0.25 * math.exp(-((hr - 2) / 2) ** 2))
            act = 0.97 * act + 0.10 * rng.standard_normal()
            vol = base * math.exp(act + 0.3 * rng.standard_normal())
            sig = 4e-5 * math.sqrt(vol / 100.0)
            path = px + np.cumsum(rng.standard_normal(8) * sig)
            T.append(t0 + d * 86400 + s * psec)
            O.append(px)
            H.append(max(px, path.max()))
            L.append(min(px, path.min()))
            C.append(path[-1])
            V.append(max(1.0, round(vol)))
            px = path[-1]
    return T, O, H, L, C, V


def partial(o, h, l, c, v, f):
    cc = o + (c - o) * f
    return (o, max(o, cc, o + (h - o) * f), min(o, cc, o - (o - l) * f), cc, max(1.0, round(v * f)))


def same(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    return a.shape == b.shape and np.allclose(a, b, rtol=0, atol=1e-12, equal_nan=True)


def selftest():
    psec = 300
    T, O, H, L, C, V = gen_bars(60, psec)
    n = len(T)
    ok_all = True

    def check(name, cond, extra=""):
        nonlocal ok_all
        ok_all &= bool(cond)
        print(f"[{'OK' if cond else 'FAIL'}] {name} {extra}")

    for mode in ("clv", "bvc"):
        print(f"\n=== modo {mode}  ({n} barre M5 sintetiche) ===")
        full = SyntheticDelta(psec, flow_mode=mode)
        full.on_calculate(T, H, L, C, V, 0)

        # 1) incrementale == completo, con barra in formazione aggiornata piu' volte
        T0 = n - 400
        inc = SyntheticDelta(psec, flow_mode=mode)
        prev = inc.on_calculate(T[:T0], H[:T0], L[:T0], C[:T0], V[:T0], 0)
        for t in range(T0, n):
            for f in (0.3, 0.6, 1.0):
                o, h_, l_, c_, v_ = partial(O[t], H[t], L[t], C[t], V[t], f)
                th = T[:t + 1]
                hh, ll, cc, vv = H[:t] + [h_], L[:t] + [l_], C[:t] + [c_], V[:t] + [v_]
                prev = inc.on_calculate(th, hh, ll, cc, vv, prev)
        for k in ("Z", "Ab", "Leg", "W", "Fb"):
            check(f"incrementale == completo [{k}]", same(inc.b[k][:n], full.b[k][:n]))

        # 2) nessun look-ahead: sporco il futuro, il passato non deve cambiare
        t_cut = n - 1500
        rng = np.random.default_rng(3)
        H2, L2, C2, V2 = list(H), list(L), list(C), list(V)
        for i in range(t_cut + 1, n):
            C2[i] = C[i] * (1 + 0.01 * rng.standard_normal())
            H2[i] = max(H2[i], C2[i]) * 1.001
            L2[i] = min(L2[i], C2[i]) * 0.999
            V2[i] = V[i] * (1 + 5 * rng.random())
        pert = SyntheticDelta(psec, flow_mode=mode)
        pert.on_calculate(T, H2, L2, C2, V2, 0)
        for k in ("Z", "Ab", "Leg"):
            check(f"causale [{k}]", same(pert.b[k][:t_cut + 1], full.b[k][:t_cut + 1]))

        # 3) barra in formazione vuota
        check("ultima barra vuota (closed_only)", math.isnan(full.b["Z"][n - 1]) and math.isnan(full.b["Ab"][n - 1]))

        # 4) pesi nel range e stazionarieta' delle soglie
        W = np.array(full.b["W"]); Wv = W[W >= 0]
        check("pesi w in [0, cap]", Wv.min() >= 0.0 and Wv.max() <= 3.0, f"(min {Wv.min():.2f} max {Wv.max():.2f})")
        Z = np.array(full.b["Z"]); Zv = Z[~np.isnan(Z)]
        h1, h2 = Zv[:len(Zv) // 2], Zv[len(Zv) // 2:]
        print(f"     Z validi {len(Zv)} | P(Z>1.5) {np.mean(Zv > 1.5):.3f}  P(Z<-1.5) {np.mean(Zv < -1.5):.3f} "
              f"| 1a meta {np.mean(np.abs(h1) > 1.5):.3f}  2a meta {np.mean(np.abs(h2) > 1.5):.3f}")

    # 5) normalizzazione stagionale vs media a 20 barre (come nel vecchio codice)
    print("\n=== volume relativo: stagionale vs media 20 barre (profilo orario sintetico) ===")
    full = SyntheticDelta(psec)
    full.on_calculate(T, H, L, C, V, 0)
    Vn = np.array(V, float)
    cs = np.cumsum(np.insert(Vn, 0, 0.0))
    avg20 = np.full(n, np.nan)
    avg20[19:] = (cs[20:] - cs[:-20]) / 20.0
    naive = np.minimum(Vn / avg20, 3.0)
    W = np.array(full.b["W"])
    hours = np.array([(t % 86400) // 3600 for t in T])
    ok = (W >= 0) & ~np.isnan(naive)
    ms = np.array([W[ok & (hours == h)].mean() for h in range(24)])
    mn = np.array([naive[ok & (hours == h)].mean() for h in range(24)])
    print(f"     stagionale : media per ora min {ms.min():.2f} max {ms.max():.2f}  (dev.std fra ore {ms.std():.3f})")
    print(f"     media 20bar: media per ora min {mn.min():.2f} max {mn.max():.2f}  (dev.std fra ore {mn.std():.3f})")
    check("stagionale piu' piatto della media a 20 barre", ms.std() < mn.std())

    # 6) soglia vecchia vs nuova: quota di barre oltre soglia (stessa scala grazie a legacy_scale=10)
    Leg = np.array(full.b["Leg"]); Lv = Leg[~np.isnan(Leg)]
    Z = np.array(full.b["Z"]); Zv = Z[~np.isnan(Z)]
    print(f"\n     quota barre oltre soglia 1.5: vecchio delta {np.mean(np.abs(Lv) > 1.5):.3f} | nuovo Z {np.mean(np.abs(Zv) > 1.5):.3f}")

    print("\nRISULTATO:", "TUTTI I TEST OK" if ok_all else "ALCUNI TEST FALLITI")
    return 0 if ok_all else 1


# ================================================================== CSV / CLI ==
def _read_text(path):
    """Legge un CSV di MT5 qualunque sia la codifica (UTF-16 con BOM, UTF-8, ANSI)."""
    raw = open(path, "rb").read()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16")
    if raw[:3] == b"\xef\xbb\xbf":
        return raw.decode("utf-8-sig")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("cp1252")


def load_csv(path):
    text = _read_text(path)
    head = text.splitlines()[0]
    delim = "\t" if "\t" in head else (";" if ";" in head and "," not in head else ",")
    rd = csv.reader(io.StringIO(text), delimiter=delim)
    hdr = [x.strip().strip("<>").lower() for x in next(rd)]
    rows = [r for r in rd if r]

    def col(*names):
        for nme in names:
            if nme in hdr:
                return hdr.index(nme)
        raise SystemExit(f"colonna mancante: {names} (trovate: {hdr})")

    def to_epoch(s):
        s = s.strip()
        if s.replace(".", "", 1).isdigit() and len(s) >= 9 and ":" not in s and s.count(".") <= 1:
            return int(float(s))
        for fmt in ("%Y.%m.%d %H:%M:%S", "%Y.%m.%d %H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
            try:
                return calendar.timegm(datetime.strptime(s, fmt).timetuple())
            except ValueError:
                pass
        raise SystemExit(f"formato data non riconosciuto: {s}")

    if "date" in hdr and "time" in hdr:     # export barre di MT5
        i_d, i_t = col("date"), col("time")
        T = [to_epoch(r[i_d] + " " + r[i_t]) for r in rows]
    else:
        # colonna dei tempi: per nome, oppure la prima colonna senza nome (CSV in stile pandas)
        i_t = next((hdr.index(nm) for nm in ("time", "datetime", "timestamp", "date") if nm in hdr),
                   0 if hdr and hdr[0] == "" else None)
        if i_t is None:
            raise SystemExit(f"colonna dei tempi mancante (trovate: {hdr})")
        T = [to_epoch(r[i_t]) for r in rows]
    cols = [col("high"), col("low"), col("close"), col("tickvol", "tick_volume", "tickvolume", "volume")]
    H, L, C, V = ([float(r[k]) for r in rows] for k in cols)
    # colonne dei valori calcolati da MT5 (presenti se il CSV viene dallo script di export)
    extra = {}
    for name in ("flow_z", "absorption_z", "legacy_x10"):
        if name in hdr:
            k = hdr.index(name)
            extra[name] = [float(r[k]) if r[k].strip() != "" else NAN for r in rows]
    if "event" in hdr:                      # eventi esportati dallo script (v3.1): vuoto = non esportato
        k = hdr.index("event")
        extra["event"] = [float(r[k]) if r[k].strip() != "" else NAN for r in rows]
    for name in ("open", "spread"):         # servono al banco di prova (costi e ingresso all'open)
        if name in hdr:
            k = hdr.index(name)
            extra[name] = [float(r[k]) for r in rows]
    return T, H, L, C, V, extra


def compare(ind, extra, n, psec, a):
    """Confronta i valori di MT5 con il riferimento, ignorando il warm-up.
    L'indicatore MT5 gira sulla storia completa del grafico, il riferimento solo sulle barre
    esportate: i due stati coincidono dopo (D sedute * barre/giorno) + M barre."""
    if not extra:
        print("il CSV non ha colonne flow_z/absorption_z/legacy_x10: usa lo script ExportSyntheticDelta.mq5")
        return 2
    skip = a.skip if a.skip is not None else int(a.days * (86400 // psec)) + a.M + 200
    if skip >= n - 50:
        print(f"troppo poche barre ({n}) per il warm-up richiesto ({skip}): esporta di piu' o abbassa --skip")
        return 2
    print(f"barre {n} | warm-up ignorato {skip} | confronto su {n - skip} barre")
    ok_all = True
    for name, key in (("flow_z", "Z"), ("absorption_z", "Ab"), ("legacy_x10", "Leg")):
        if name not in extra:
            continue
        mt5 = np.array(extra[name][skip:], float)
        ref = np.array(ind.b[key][skip:n], float)
        nan_mis = int(np.sum(np.isnan(mt5) != np.isnan(ref)))
        both = ~np.isnan(mt5) & ~np.isnan(ref)
        d = np.abs(mt5[both] - ref[both])
        maxd = float(d.max()) if d.size else float("nan")
        # i valori di MT5 hanno 8 decimali; 5e-5 lascia margine per l'erf approssimata e gli arrotondamenti
        ok = nan_mis == 0 and d.size > 0 and maxd < 5e-5
        ok_all &= ok
        if name == "legacy_x10" and not both.any():
            print(f"[--] {name}: tutta vuota in MT5 (ShowLegacy spento?)")
            continue
        print(f"[{'OK' if ok else 'FAIL'}] {name}: valori confrontati {int(both.sum())} | "
              f"diff max {maxd:.2e} | vuoti discordanti {nan_mis}")
    if "event" in extra and not np.all(np.isnan(extra["event"])):
        mt5 = np.array(extra["event"][skip:], float)
        ref = np.array(ind.b["Ev"][skip:n], float)
        mism = int(np.sum(mt5 != ref))
        ok = mism == 0
        ok_all &= ok
        print(f"[{'OK' if ok else 'FAIL'}] event: eventi MT5 {int(np.sum(mt5 != 0))} | riferimento {int(np.sum(ref != 0))} | barre discordanti {mism} (soglia {a.thr})")
    print("RISULTATO:", "L'IMPLEMENTAZIONE MQL5 COINCIDE CON IL RIFERIMENTO" if ok_all else "DIFFERENZE: mandami il CSV")
    return 0 if ok_all else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--csv")
    ap.add_argument("--out")
    ap.add_argument("--psec", type=int)
    ap.add_argument("--mode", default="clv", choices=["clv", "bvc"])
    ap.add_argument("--N", type=int, default=12)
    ap.add_argument("--M", type=int, default=500)
    ap.add_argument("--days", type=int, default=20)
    ap.add_argument("--thr", type=float, default=1.5, help="soglia degli eventi (deve coincidere con quella dell'indicatore)")
    ap.add_argument("--compare", action="store_true",
                    help="confronta con le colonne flow_z/absorption_z/legacy_x10 del CSV (script di export)")
    ap.add_argument("--skip", type=int, help="barre iniziali da ignorare nel confronto (warm-up)")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(selftest())
    if not a.csv:
        ap.error("serve --selftest oppure --csv")
    T, H, L, C, V, extra = load_csv(a.csv)
    psec = a.psec or int(statistics.median(np.diff(T)))
    ind = SyntheticDelta(psec, flow_mode=a.mode, N=a.N, M=a.M, D=a.days, thr=a.thr)
    ind.on_calculate(T, H, L, C, V, 0)
    if a.compare:
        sys.exit(compare(ind, extra, len(T), psec, a))
    out = a.out or "syntheticdelta_out.csv"
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time", "flowZ", "absorptionZ", "legacy_x10"])
        for i in range(len(T)):
            w.writerow([T[i]] + ["" if math.isnan(ind.b[k][i]) else f"{ind.b[k][i]:.6f}" for k in ("Z", "Ab", "Leg")])
    print(f"scritto {out}  (psec={psec}, barre={len(T)})")


if __name__ == "__main__":
    main()
