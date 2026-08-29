# Order Flow Engine v2 (OFE2)

Riscrittura di `Delta Volume + Exhaustion Signals` (DVB-EX v1).

## Perche' la v1 andava rifatta

| # | Problema v1 | Effetto | Fix v2 |
|---|---|---|---|
| 1 | `overlay=true` con CVD e istogramma delta (unita' prezzo x volume, ordine 1e6-1e9) sulla scala del prezzo | grafico inutilizzabile | pannello separato + `force_overlay` sui soli marker |
| 2 | `isDeltaPositive = currentDelta > deltaMA` | in downtrend la MA e' molto negativa, quindi un delta **ancora venditore** viene letto come acquisto: falsi Buy Absorption dove il trend e' piu' forte | segno contro **zero**, magnitudine contro la distribuzione |
| 3 | `bearExhaustion` = `buyAbsorption` con `1.2 < abs(z) <= 1.5` | il modulo "Exhaustion" non aggiungeva informazione: era l'Absorption debole con un colore diverso | eventi ridefiniti con predicati disgiunti |
| 4 | Se `sensitivityExhaustion > sensitivityAbsorption` il `not buyAbsorption` azzera il modulo | alzare la sensibilita' **spegne** il segnale | soglie su assi distinti, nessuna esclusione reciproca |
| 5 | `deltaMA`/`deltaStdDev` includono la barra corrente | l'outlier gonfia il proprio denominatore; con n=20 lo z massimo ottenibile e' `(n-1)/sqrt(n) = 4.25`, quindi le soglie 1.2/1.5/2.0 non significano quello che sembra | mediana/MAD su finestra **laggata**, robuste alle code grasse |
| 6 | `volume > volumeMA * k` come "conferma" mentre `delta ∝ volume` | i due test sono collineari: stessa cosa contata due volte, campione ridotto senza guadagno informativo | assi ortogonali: partecipazione `z(volume)`, sbilanciamento `delta/volume ∈ [-1,1]`, risultato `(close-open)/ATR` |
| 7 | `buyPressure = c>o ? (c-o)+lw*0.5 : lw*0.7` | discontinuita' a `close == open`, coefficienti arbitrari, wick superiore mai contributiva agli acquisti | forma continua e adimensionale, vedi identita' sotto |
| 8 | `math.max(bodyRange, 0.0001)` | epsilon dipendente dallo strumento (rompe su indici e JPY) | `syminfo.mintick` |
| 9 | `(1 + velocityFactor)` | doppio conteggio del corpo, gia' presente in `buyPressure` | rimosso |
| 10 | Nessun contesto di regime | lo stesso assorbimento e' mean-reverting in range e rumore in trend | Efficiency Ratio che **routa** il tipo di evento |
| 11 | Nessuna misura di edge, 8 segnali x 8 parametri | superficie di multiple testing enorme, zero evidenza | tabella forward return netto costi |
| 12 | `barstate.isconfirmed` come anti-repaint | no-op: Pine fa gia' rollback delle `var` a ogni tick | rimosso |
| 13 | CVD non ancorato, cresce dalla prima barra caricata | valore dipendente dallo storico caricato | reset giornaliero opzionale + z-score |
| 14 | Nessun filtro sessione | il tick volume esplode al rollover broker e collassa in Asia: falsi z-spike sistematici | filtro sessione + esclusione rollover |

## Identita' che governa la modalita' geometrica

Per ogni barra vale **esattamente**:

```
CLV = bodyRatio + wickImbalance

bodyRatio     = (close - open) / range
wickImbalance = (lowerWick - upperWick) / range
CLV           = ((close - low) - (high - close)) / range
```

Conseguenza operativa: senza dati intrabar, **l'unica informazione non gia' contenuta nella direzione della barra e' lo sbilanciamento delle ombre**. Per questo i test di assorbimento usano

```
imbOrtho = imb - bodyRatio
```

e non `imb`. Un test tipo "delta positivo mentre il prezzo scende" costruito sul corpo della candela e' quasi tautologicamente vuoto: i due termini hanno lo stesso segno per costruzione. Usare la modalita' LTF (`request.security_lower_tf`) quando il timeframe lo consente.

## I quattro eventi

| Evento | Regime | Condizione | Logica |
|---|---|---|---|
| **Absorption** | RANGE (`ER < 0.30`) | partecipazione alta, `imbOrtho` **contro** la direzione della barra, risultato significativo | sforzo contro-direzionale senza risultato: qualcuno assorbe |
| **Exhaustion** | TREND (`ER > 0.50`) | volume climatico, nuovo estremo, chiusura respinta (`clvPos < 0.40`), flusso nascosto contrario | upthrust di Wyckoff: massimo sforzo, nessun progresso |
| **Initiative** | TREND | flusso, prezzo e chiusura tutti allineati | continuazione |
| **Divergence** | qualsiasi | pivot prezzo vs CVD z-scored | distribuzione/accumulo su swing (conferma `pivR` barre dopo l'estremo: lag dichiarato, non repaint) |

Absorption ed Exhaustion sono ora **mutuamente esclusivi per costruzione**: il filtro di regime li separa prima ancora delle soglie.

## Protocollo di calibrazione (non saltarlo)

1. Imposta `costPts` sullo strumento reale. FP Markets Raw EURUSD: ~0.1 pip spread + 3.5 USD/lot/side = circa **0.7 pip = 7 punti** su 5 decimali. Su US30 e XAUUSD i valori sono molto diversi. Con `costPts = 0` la tabella mente.
2. Leggi la tabella EDGE, **non i colori sul grafico**. Un evento e' utilizzabile solo se `N >= 100` (sotto 30 la colonna N diventa arancione) e `mu net > 0` con `|mu net| > 0.15R`.
3. Un `mu net` positivo con `MAE` peggiore di `-1.5R` significa che l'edge esiste ma non e' tradeable con lo SL che stai usando: allarga lo SL o scarta il segnale.
4. Non ottimizzare le soglie sullo stesso periodo su cui leggi la tabella. Calibra su un periodo, verifica su un altro. Con 8 eventi e ~12 parametri liberi, trovare un `mu net` positivo in-sample e' garantito anche su rumore puro.
5. Disattiva gli eventi che non passano il test. Quattro famiglie sono un menu, non un obbligo.

## Bridge MT5

Gli alert emettono JSON, non testo:

```json
{"sym":"EURUSD","tf":"15","evt":"BUY_ABSORPTION","dir":1,"px":1.08432,
 "sl":1.08210,"tp":1.08802,"atr":0.00148,"vz":2.31,"imb":0.44,"er":0.21,
 "score":0.38,"t":1724956200000}
```

Il campo `score` e' continuo in `[-1,1]` e puo' essere usato come input di sizing invece di un ingresso binario.

---

# Meta-labeling

## Cosa il DOM non e', in Pine

Pine Script **non ha accesso al book**. Nessuna profondita', nessun bid/ask, nessun
lato aggressore per trade. Non dipende dall'abbonamento: non esiste nel linguaggio.
Il DOM del widget TradingView arriva dall'integrazione broker e non e' raggiungibile
da uno script.

Cosa l'abbonamento CME da' davvero, ed e' comunque molto:

- **volume reale in contratti**, non tick count (su FX il volume e' il numero di tick)
- **dati al secondo**, quindi la modalita' LTF funziona su grafici a 15s

Il massimo ottenibile in Pine resta: spezzare la barra in sotto-barre da 1 secondo e
classificarle per close vs open. Buona approssimazione del lato aggressore, ma
approssimazione. Il DOM vero richiede un feed futures diretto (Rithmic, CQG,
Tradovate, IQFeed) con MQL5 o C++. **Non i CFD di FP Markets**: li' il book e' del
broker e non ha relazione con la liquidita' reale del CME.

## La pipeline

```
Pine (useExport = true)  ->  Esporta dati del grafico (CSV)
   ->  research/meta_label.py  ->  coefficienti  ->  Pine / MQL5
```

Il segnale primario **non si stringe**. Resta generoso. Un secondo modello impara
soltanto PRENDERE / SALTARE, addestrato sull'esito a barriere dei segnali primari.
Separa "dove guardare" da "quando vale la pena" - il punto esatto in cui i filtri a
soglia falliscono, perche' una soglia si muove lungo la stessa distribuzione mentre
un meta-modello usa la combinazione di assi che la soglia non vede.

## Comando

```bash
python3 research/meta_label.py export.csv \
    --mintick 0.25 --cost-ticks 2 --sl-atr 1.5 --tp-atr 2.5 --max-bars 20 --raw
```

`--raw` usa i segnali **prima** del gate di qualita': piu' campione, e il modello
impara da solo cosa scartare invece di ereditare le mie soglie.

Requisiti: solo `numpy` e `pandas`.

## Cosa esce

1. **muR e hit rate per famiglia** - quali dei quattro eventi sopravvivono
2. **muR per fascia oraria** - spesso tutto l'edge sta in due ore e il resto lo divora
3. **Curva soglia -> expectanza out-of-sample**, con la colonna `vs base`
4. **Coefficienti** ordinati per importanza, gia' pronti da incollare in Pine

## Perche' la disciplina statistica qui non e' decorazione

I trade **si sovrappongono nel tempo**. Una k-fold normale mette in train campioni
che condividono barre col test: leakage garantito e AUC gonfiata. Lo script usa
**purged k-fold con embargo** (Lopez de Prado, AFML cap. 7) e **pesi di unicita'**:
un trade che condivide 19 barre su 20 con un altro non vale un'osservazione
indipendente.

E si valuta in **expectancy (R per trade)**, mai in accuracy. Un modello al 75% di
accuracy che scarta i pochi vincitori grossi e' peggio di niente.

## Avvertenza sul campione

Sotto ~300 segnali il meta-modello si adatta al rumore, e lo script lo dice.
La soglia scelta guardando la curva e' essa stessa una decisione in-sample:
va verificata su un periodo non usato per addestrare.
