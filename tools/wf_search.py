#!/usr/bin/env python3
"""
Cercatore walk-forward sui file _orb_breakout.csv prodotti da VTRLS_MoveResearch.

Perche' esiste, e perche' NON e' scritto in MQL5
-----------------------------------------------
Provare tutte le combinazioni e tenere la migliore non e' apprendimento: e' il
modo piu' rapido di trovare rumore. Questo strumento fa l'unica cosa che
trasforma una ricerca in una misura: sceglie la regola guardando SOLO il
passato e la valuta su un blocco che non ha mai visto.

Con quel giudice montato, allargare la ricerca diventa sicuro. Senza, ogni
feature aggiunta peggiora il risultato invece di migliorarlo.

Tre discipline, tutte imparate a spese di questo dataset:

  * PERCENTILE CAUSALE. Una soglia assoluta smette di scattare quando la scala
    della feature si sposta: la prima versione sceglieva "forza > 140" e dopo
    il 2018 non apriva piu' nessuna operazione. Ogni valore diventa il proprio
    rango fra le sole N rotture PRECEDENTI.
  * SELEZIONE CONGIUNTA. La regola viene scelta sui simboli messi insieme, non
    per simbolo. "EURUSD preferisce l'RSI e GBPUSD il breakout" e'
    indistinguibile dal rumore finche' non c'e' una ragione per cui debba
    essere cosi'.
  * LA RICERCA VIENE CONTATA. Il massimo di N estrazioni da una distribuzione
    nulla cresce come sqrt(2 ln N): con 500 candidati serve gia' z 3.5 perche'
    una cella significhi qualcosa. Il numero viene stampato accanto al
    risultato, non lasciato al lettore.

Uso:
    python3 wf_search.py EURUSD=file.csv:0.078 GBPUSD=file2.csv:0.060
"""
import csv, sys, math, bisect

WIN      = 250     # rotture precedenti su cui calcolare il percentile
BLOCK    = 2       # ampiezza in anni del blocco fuori campione
WARM     = 4       # anni iniziali riservati alla sola selezione
PCTS     = (60, 70, 75, 80, 85, 90)
MINSHARE = 0.08    # una regola deve aprire almeno l'8% delle rotture
TOPK     = 6       # quante singole entrano nelle coppie

# Colonne che NON sono note al momento dell'ingresso. mfe_atr e mae_atr sono
# escursioni misurate DOPO: sono l'esito travestito da feature. Alla prima
# esecuzione il cercatore le ha scelte e ha prodotto t = 21.77 - ed e'
# esattamente cosi' che si riconosce un look-ahead: non dal fatto che sia
# positivo, dal fatto che sia impossibile.
SKIP = {"finestra","giorno","ora","direzione","esito","anno","vp_stato",
        "mfe_atr","mae_atr"}

def carica(path, cost):
    """Righe in ordine cronologico -> (anno, payoff in R, percentili causali)."""
    with open(path, newline="", encoding="latin-1") as f:
        rd = csv.reader(f, delimiter=";")
        hdr = next(rd)
        ix  = {n: i for i, n in enumerate(hdr)}
        feats, hist, out = [], {}, []
        for r in rd:
            if not r or r[0] == "finestra" or len(r) < len(hdr):
                continue
            if not feats:                       # feature dedotte dall'intestazione:
                for n in hdr:                   # le colonne nuove entrano da sole
                    if n in SKIP or n.startswith("vp_stato"):
                        continue
                    try:
                        float(r[ix[n]]); feats.append(n); hist[n] = []
                    except (ValueError, IndexError):
                        pass
            e = r[ix["esito"]]
            p = 2.0 - cost if e == "TARGET" else (-1.0 - cost if e == "STOP" else -cost)
            pc = {}
            for n in feats:
                try:
                    v = float(r[ix[n]])
                except ValueError:
                    continue
                h = hist[n]
                if len(h) >= 100:
                    w = sorted(h[-WIN:])
                    pc[n] = 100.0 * bisect.bisect_left(w, v) / len(w)
                h.append(v)
            out.append((int(r[ix["anno"]]), p, pc))
    return out, feats

def applica(riga, regola):
    for f, op, t in regola:
        x = riga[2].get(f)
        if x is None: return False
        if op == ">" and not x > t: return False
        if op == "<" and not x < t: return False
    return True

def valuta(dati, regola):
    s = n = 0
    for d in dati:
        if applica(d, regola):
            s += d[1]; n += 1
    return (s / n if n else 0.0), n

def cerca(train, feats):
    """Migliore regola a una o due condizioni sul solo periodo di training."""
    need = max(80, int(len(train) * MINSHARE))
    singole, ncand = [], 0
    for f in feats:
        for t in PCTS:
            for op in (">", "<"):
                ncand += 1
                e, n = valuta(train, [(f, op, t)])
                if n >= need:
                    singole.append((e, [(f, op, t)]))
    if not singole:
        return None, ncand
    singole.sort(key=lambda x: -x[0])
    best = singole[0]
    for i in range(min(TOPK, len(singole))):          # coppie fra le migliori
        for j in range(i + 1, min(TOPK, len(singole))):
            if singole[i][1][0][0] == singole[j][1][0][0]:
                continue
            reg = singole[i][1] + singole[j][1]
            ncand += 1
            e, n = valuta(train, reg)
            if n >= need and e > best[0]:
                best = (e, reg)
    return best, ncand

def etichetta(regola):
    return " & ".join(f"{f}{op}{t}" for f, op, t in regola)

def main(argv):
    simboli = {}
    for a in argv:
        nome, resto = a.split("=", 1)
        path, cost  = resto.rsplit(":", 1)
        dati, feats = carica(path, float(cost))
        simboli[nome] = dati
        campi = feats
    anni = sorted({y for d in simboli.values() for y, _, _ in d})
    print(f"simboli: {', '.join(simboli)} | feature: {len(campi)} | "
          f"percentile causale su {WIN} rotture\n")
    print(f"{'blocco':<11}{'regola scelta sul solo passato':<46}{'E train':>9}"
          f"{'E test':>9}{'n':>6}{'baseline':>10}")
    somma = conta = 0.0
    quad  = 0.0
    basesum = basen = 0.0
    ncand = 0
    b = anni[0] + WARM
    while b <= anni[-1]:
        train = [d for s in simboli.values() for d in s if d[0] < b]
        test  = [d for s in simboli.values() for d in s if b <= d[0] < b + BLOCK]
        if len(train) < 800 or len(test) < 120:
            b += BLOCK; continue
        best, ncand = cerca(train, campi)
        if best is None:
            b += BLOCK; continue
        etr, regola = best
        ete, nte = valuta(test, regola)
        base = sum(d[1] for d in test) / len(test)
        print(f"{b}-{b+BLOCK-1:<6}{etichetta(regola):<46}{etr:>9.4f}{ete:>9.4f}"
              f"{nte:>6d}{base:>10.4f}")
        for d in test:
            if applica(d, regola):
                somma += d[1]; conta += 1; quad += d[1] * d[1]
        basesum += base * len(test); basen += len(test)
        b += BLOCK
    if conta > 1:
        media = somma / conta
        sd    = math.sqrt(max(0.0, quad / conta - media * media))
        t     = media / (sd / math.sqrt(conta)) if sd > 0 else 0.0
        print("-" * 91)
        print(f"{'FUORI CAMPIONE, tutti i blocchi':<57}{media:>9.4f}"
              f"{int(conta):>6d}{basesum/basen:>10.4f}")
        print(f"   t = {t:.2f}  (deviazione {sd:.2f} R)   "
              f"vantaggio sulla baseline: {media - basesum/basen:+.4f} R")
        print(f"   {ncand} candidati per selezione -> una cella dentro la ricerca "
              f"ha bisogno di z ~{math.sqrt(2*math.log(ncand)):.2f} per contare")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    main(sys.argv[1:])
