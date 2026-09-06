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

**`PineScript/GEX_Confluence_v2_NQ.pine` è lo script completo.** Pine Editor →
nuovo indicatore → seleziona tutto → incolla → Save → Add to chart. Non serve
altro: `//@version=6` è già in testa.

Il file contiene l'indicatore originale con tre modifiche integrate:

| Modifica | Effetto |
|---|---|
| Motore confluenze v2 | sostituisce il conteggio con lo scoring pesato |
| `f_convertPrice` drift-aware | linee, profilo e zone condividono la stessa correzione di basis |
| `f_addBOS` non riconverte più | correzione del bug che spostava i BOS di 178 punti su chart NDX/QQQ |

Il resto — parser, BOS, wall-flip, session box, AVWAP, alert — è invariato.

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

## Ponte verso provider esterni (TanukiTrade, TLADe, altri)

`input.source()` aggancia il **plot di un altro indicatore presente sullo stesso
grafico**. E' l'unico modo legittimo di far parlare due script in Pine: nessun
reverse engineering, nessun dato estratto, funziona anche con script invite-only
purche' espongano i livelli come plot.

Gruppo **"Livelli esterni"**: 6 slot, ognuno con nome, sorgente e peso.
**Peso 0 = slot spento** — necessario perche' `input.source()` non ha un valore
"nessuno": lasciato al default punta a `close`, e un livello sempre esattamente
sul prezzo avvelenerebbe ogni zona.

### La scelta della famiglia è la decisione importante

Default: **famiglia GEX**. Se la fonte esterna è anch'essa options-derived
(HVL, call/put wall), metterla in una famiglia separata significherebbe contare
**due volte la stessa informazione**: due vendor che calcolano il gamma dalla
stessa options chain non sono due prove indipendenti. Con `confCrossOnly` attivo
verrebbero fuori zone "UBER" costruite sul nulla.

Scegli **"Famiglia indipendente"** solo per fonti di natura diversa da quella
opzionaria — un volume profile, un modello di order flow, livelli istituzionali.

## Pannello di stato e guardia sulla staleness

Tre fatti che invalidano tutto il resto quando vanno storti, raccolti in un
riquadro solo in alto a destra:

| Riga | Cosa dice |
|---|---|
| **Regime** | sopra o sotto lo Zero Gamma. **È un regime di volatilità, non una direzione**: long gamma = vol compressa e mean reversion; short gamma = vol espansa, e il movimento accelera in *entrambe* le direzioni |
| **Zero Gamma** | livello e distanza in punti |
| **Età dati** | ore/minuti dal campo *Data/ora del paste*. Oltre la soglia (default 9h) diventa rosso e scrive `RIGENERA` |
| **Basis / zone** | drift applicato (o `ROLL!`) e numero di zone disegnate |

Il campo **Data/ora del paste** (`YYYY-MM-DD HH:MM`, ora exchange) va compilato a
mano quando incolli la stringa. È l'unico modo: Pine non sa quando un input è
stato modificato. Lasciato vuoto, il controllo è disattivato — e resti senza rete
sul rischio operativo numero uno.

## Timeframe e tipi di candela

Non usare questo indicatore su **Renko, Kagi, Point&Figure o altre candele
esotiche**, né su timeframe superiori a 1D. Su quelle il tempo non avanza in modo
lineare, e session box, AVWAP e tracking wall-flip a 5m assumono tutti tempo
lineare. Vale per noi esattamente come per qualunque altro tool basato su dati
esterni con marca temporale.

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
   (Il bug di conversione dei BOS su chart NDX/QQQ è invece corretto in questo
   file: `f_addBOS` non applica più `f_convertPrice` a livelli già in scala
   grafico.)
