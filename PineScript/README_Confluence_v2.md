# Confluence Engine v2 — livelli pesati e indipendenti

## Il problema di v1

Il motore originale conta: N livelli entro una banda → `Nx`. Tre difetti strutturali.

**1. Nessun peso.** Un call wall da 190M e la VWAP asiatica valgono uguale.

**2. Nessuna nozione di indipendenza.** A metà mattina Asia-VWAP, EU-VWAP e US-VWAP
sono quasi lo stesso numero. v1 le conta come **tre prove**. Non lo sono: è una
prova sola, misurata tre volte.

**3. Rumore di griglia contato come segnale.** Nel data string convivono due libri:

| Famiglia | Griglia | Conversione a NQ |
|---|---|---|
| strike **NDX** | 25 punti | `+ S` |
| strike **QQQ** | ~41 punti, **arrotondati a 10 punti NDX** | `× R`, arrotondato, `+ S` |

Due griglie diverse sovrapposte producono quasi-coincidenze **per aritmetica**.
Con la banda v1 da 5 punti, l'errore di arrotondamento QQQ (fino a ±5) è dello
stesso ordine della banda: molte "UBER zone" erano artefatti.

## Il modello v2

```
score(zona) = Σ_famiglie  Σ_k  w_k · decay^(rank_k)
```

Quattro famiglie: **G**EX · **P**rice Action · **B**OS · a**V**WAP.

- **Fra famiglie** i pesi si sommano pieni — sono fonti indipendenti.
- **Dentro una famiglia** decadono (`0.4`): il 2° livello vale il 40%, il 3° il 16%.
  È l'espressione diretta del fatto che livelli della stessa fonte sono correlati.

### Pesi di default

| Livello | Peso | Perché |
|---|---|---|
| Zero Gamma | 3.00 | è il pivot di regime, non un livello qualunque |
| BOS M / W / D | 3.00 / 2.50 / 2.00 | struttura di ordine superiore |
| PWH / PWL | 2.00 | riferimento settimanale, poche occorrenze |
| EM edge (±1σ) | 1.75 | frontiera statistica, non un prezzo arbitrario |
| Charm / Delta Flip | 1.60 | |
| Max Pain, PDH/PDL, VWAP US e PD | 1.50 | |
| **Call / Put Wall** | **1.00 × [0.5 … 2.0]** | **scalato sulla magnitudine** |
| VWAP EU / Asia | 0.90 | |
| Vol Band, BOS H1/H4 | 0.75 | derivati o rumorosi |

I muri sono l'unica classe con peso variabile: `0.5 + 1.5·min(mag/magMax, 1)`.
Un wall da 190M pesa ~2.0, uno da 12M ~0.6. In v1 pesavano identico.

### Tre filtri che tolgono il grosso del rumore

**De-duplica intra-famiglia** (`confQuantum`, 12 pt): due livelli della *stessa*
famiglia più vicini del quanto vengono collassati nel più pesante. Neutralizza
l'arrotondamento QQQ e le VWAP sovrapposte. Le coppie **cross-family non vengono
mai collassate** — sono precisamente il segnale.

**Requisito cross-family** (default ON): una zona esiste solo se **almeno due
famiglie diverse** convergono. È il filtro con il rapporto qualità/prezzo più
alto di tutto il modulo: elimina in un colpo ogni cluster puramente aritmetico.

**Clustering per densità + non-max suppression**: ogni livello è un centro
candidato, si calcola lo score della sua banda, si ordina per score e si accettano
le zone non sovrapposte. v1 usava un walk greedy: l'appartenenza a un cluster
dipendeva da dove iniziava la scansione, e un livello di confine finiva nel
cluster sbagliato.

## La correzione di basis — non è opzionale

Gli strike arrivano in spazio NQ con il basis **congelato** al momento dello
snapshot (campo `S:`). Il carry NQ−NDX decade di ~15-20 punti a settimana e salta
al roll trimestrale.

Il punto sottile: un drift comune **non** degrada le confluenze GEX-GEX — quei
livelli si muovono tutti insieme. Degrada le **cross-family**, perché AVWAP, BOS e
PDH/PDL non si muovono affatto. Cioè: il drift corrompe esattamente le zone che
questo motore è costruito per trovare.

```
basisLive  = mediana( close(NQ1!) − close(NDX), N )
drift      = basisLive − S
livelloGEX = strike + drift
```

Mediana e non media: al roll il basis salta in un tick e una media resta sbagliata
per tutta la sua finestra. Se `|drift| > 120 pt` la correzione viene sospesa e
compare un'etichetta rossa: significa dato molto vecchio, roll in corso o campo
`S:` assente. In quel caso i livelli non sono utilizzabili.

## Installazione

Tre blocchi in `confluence_v2_patch.pine`:

1. **BLOCCO 1** → nella sezione input, dopo il gruppo `Confluence Zones`.
2. **BLOCCO 2** → a livello globale, subito dopo `[close5m, time5m] = request.security(...)`.
3. **BLOCCO 3** → sostituisce integralmente il vecchio blocco `CONFLUENCE ZONES`,
   da `for b in confluenceBoxes` fino a `i := j` incluso. Resta dentro
   `if needsRedraw` e mantiene l'indentazione a 4 spazi.

Gli input v1 (`confluenceMinSize`, `confluenceBandPoints`) restano innocui.

## Come leggere l'output

Etichetta: `4.8 GPV` → score 4.8, convergono GEX + PriceAction + VWAP.
Tooltip: distanza dal prezzo in punti e ogni livello membro con il suo peso.

Il **badge conta più dello score**. `2.6 GP` (wall + massimo di ieri) è un livello
migliore di `3.1 G` — che è solo il libro opzioni che si ripete.

| Score | Lettura |
|---|---|
| < 2.5 | non disegnato |
| 2.5 – 4.0 | zona da osservare |
| 4.0 – 6.0 | zona forte |
| > 6.0 | UBER: convergenza multi-fonte rara |

## Taratura

- **Banda troppo stretta** (< 10 pt su NQ) → non intercetti mai una vera
  coincidenza cross-family: le griglie strike sono a 10 e 25 punti. Default 12.
- **`confDecay` a 1.0** → torni al conteggio di v1. **A 0** → conta solo il livello
  più pesante per famiglia: massimo scetticismo.
- **`confCrossOnly` OFF** → riappaiono i cluster puramente GEX. Fallo solo per
  capire quanto rumore stava passando prima.

## Cosa questo motore NON risolve

Onestà su cosa resta aperto:

1. **I pesi sono priors, non stime.** Li ho scelti per plausibilità strutturale,
   non misurandoli. Il modo corretto di tararli è una regressione della reazione
   del prezzo (reversal rate, MFE/MAE alla prima interazione) sulla classe del
   livello. Finché non lo fai, `wZG = 3.0` è un'opinione informata.
2. **Il decadimento 0.4 è arbitrario.** La correlazione vera fra due AVWAP dipende
   dall'ora del giorno: a fine sessione US sono molto meno correlate che alle 10:00.
   Un decay fisso è un'approssimazione grezza di una correlazione variabile.
3. **Confluenza ≠ edge.** Misura *quante fonti indipendenti* indicano un prezzo,
   non la probabilità che il prezzo reagisca. Le due cose coincidono solo se ogni
   fonte ha potere predittivo — ipotesi mai verificata su NQ, per nessuna di esse.
4. **Restano i difetti 3, 4, 5 e 9** della revisione: BOS che valuta una sola volta
   per periodo, invalidazione sul timeframe del grafico, wall-flip corretto solo
   sul grafico a 5 minuti, alert assenti sui livelli GEX. Il punto 3 in
   particolare **inquina questo motore**: i livelli BOS che entrano nel calcolo
   sono prodotti da una logica che non fa quello che il nome dichiara.
