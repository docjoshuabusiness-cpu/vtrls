# SyntheticDelta EA v2.0 — guida operativa

File: `MQL5/Experts/SyntheticDelta_EA_v2.0.mq5`

> **Stato:** scritto e revisionato, ma **mai compilato** (nell'ambiente di sviluppo non c'è MetaEditor).
> Compila in MetaEditor (F7) e, se compaiono errori, incollali così come sono.
>
> **Cosa è stato verificato senza compilatore**
> - sintassi: il file è stato tradotto in C++ con uno stub dell'API MQL5 e compilato con `g++ -Wall -Wextra -Wshadow`, zero messaggi;
> - logica del segnale: port Python riga per riga dell'EA confrontato con il port di `SD_BuildSignals` di SignalLab su circa 15 milioni di barre sintetiche
>   (offset di conferma 0–3, raffica con e senza `RunGapBars`, barre piatte, volume zero, conflitti Delta/Expansion): **0 differenze** nella terna (sorgente, verso, raffica);
>   12 bug iniettati di proposito nel port sono stati tutti rilevati, quindi lo zero è significativo;
> - nessun uso dei dati della barra in formazione nel segnale;
> - codifica delle classi: biiettiva per tutte le ampiezze di fascia ammesse, e il filtro accetta esattamente i segnali della classe.
>
> **Non verificabile qui:** il comportamento reale dell'API MetaTrader (ordini, storico deal, tester). Vedi il Passo 0.

## 1. Cosa fa e cosa cambia rispetto alla v1.13

| | v1.13 | v2.0 |
|---|---|---|
| Lotto | fisso / % rischio | **fisso** |
| SL / TP / trailing | punti oppure ATR | **solo ATR**, distanze congelate all'ingresso |
| Stop a tempo | no | sì (`Inp_D_MaxBars`, `Inp_E_MaxBars`), terza barriera |
| Posizioni | fino a N per direzione | **una alla volta**; in netting non entra se sul simbolo c'è una posizione di qualunque magic |
| Filtri ADX, S/R | filtri rigidi | **etichette** misurabili; filtro opzionale (`PASS`/`FAIL`) |
| Sequence filter / 1 trade per ora / orari | sì | sostituiti dalle **classi di segnale** |
| Impostazioni per sorgente | no | profilo SL/TP/trailing **separato** per DELTA e EXP_ADDED |
| Metrica di ottimizzazione | winrate/RF/PF | **t-statistic di R** (media del rendimento in multipli del rischio) |
| Input sbagliati | passata silenziosa | `OnInit` fallisce: nessuna passata "vuota" |

La logica del segnale (Synthetic Delta, Expansion, raffica, intensità TR/ATR) è la stessa di v1.13 e di SignalLab, così
una classe misurata nello script è la stessa classe che l'EA opera.

## 2. Attenzione: il tuo conto è NETTING

La barra del titolo del terminale riporta *Netting*. In netting esiste **una sola posizione per simbolo**: nella v1.13 un
SELL con un BUY aperto non apriva uno short, **chiudeva il long** (o lo riduceva), e l'EA contava comunque "un trade
aperto". I backtest della v1.13 su questo conto mischiano quindi ingressi e uscite da inversione che non erano nel disegno.
La v2.0 non invia mai un ordine se esiste già una posizione sul simbolo.

## 3. La classe del segnale

Ogni segnale ha quattro etichette che definiscono la classe:

| Dimensione | Valori |
|---|---|
| Sorgente | `DELTA` (Synthetic Delta) · `EXP_ADDED` (Expansion sulle barre dove il Delta tace) |
| Verso del segnale | `BUY` · `SELL` |
| Raffica | 1 · 2 · 3 · 4+ (posizione nella serie di segnali consecutivi nello stesso verso, sul flusso grezzo) |
| Fascia oraria | `nB = 1440 / Inp_BucketMin` fasce (server + `Inp_TimeOffsetH`) |

Più le etichette non filtranti: ADX passato/fallito, S/R passato/fallito, relazione con l'Expansion (solo Delta: nessuna / concorde / discorde), intensità TR/ATR 0–5.

**`Inp_ClassID`**: `-1` = nessuna classe (valgono solo i filtri manuali). `>= 0` = opera solo quella classe.

```
ID = ((src*3 + dir)*5 + burst) * (nB+1) + hour
src: 0 ANY, 1 DELTA, 2 EXP_ADDED   dir: 0 ANY, 1 BUY, 2 SELL
burst: 0 ANY, 1, 2, 3, 4 (=4+)     hour: 0 ANY, 1..nB
```

| `Inp_BucketMin` | fasce | classi totali | classi con ora = ANY |
|---|---|---|---|
| 1440 | 1 | 90 | 45 |
| 480 | 3 | 180 | 45 |
| 360 | 4 | 225 | 45 |
| **240 (default)** | 6 | **315** | 45 |
| 120 | 12 | 585 | 45 |
| 60 | 24 | 1125 | 45 |

La tabella ID → etichetta viene scritta in `Common\Files\SDv2_classmap_<bucket>m.csv` ad ogni test singolo.
`Inp_BucketMin` dovrebbe essere un multiplo del timeframe (su M15: 15, 30, 60, ...); l'EA avvisa se non lo è.

## 4. Procedura consigliata

**Perché partire grossolani.** Con classi fini il campione è troppo piccolo: per vedere un edge di 0.10R con soglia
Bonferroni su 315 classi servono circa **1700 trade per classe**; per 0.05R circa 6900. Una classe "SELL, raffica 1, 08:00–12:00"
in 16 anni di M15 ne ha poche centinaia. Con poche centinaia di trade si vedono solo edge ≥ 0.3R, cioè quasi mai reali.

| N classi provate | soglia t unilaterale 5% (la stampa l'EA) | soglia bilaterale (per la lettura INVERTI) | t massimo atteso dal solo caso |
|---|---|---|---|
| 45 | 3.06 | 3.26 | 2.76 |
| 315 | 3.60 | 3.78 | 3.39 |
| 585 | 3.76 | 3.93 | 3.57 |
| 1125 | 3.92 | 4.08 | 3.75 |

Il **t è una misura di evidenza, non di effetto**: cresce con √n. Una classe larga con n = 20000 e media 0.02R può avere un t più alto di una
stretta con n = 300 e media 0.15R. Guarda sempre anche la media di R e, per un uso reale, pretendi una media netta di costi chiaramente positiva
(ordine di grandezza: ≥ 0.05R). Le classi sono anche **annidate** (ogni ANY è un'unione di classi più strette), quindi i test non sono indipendenti
e il numero di prove vere è diverso dal numero di ID.

**Fase 0 — verifica del banco di prova** (test singolo, `Inp_ClassID = -1`, `Inp_LogSignals = true`). Non saltarla: sono le cose che nessuno ha potuto verificare per te.
1. **Compila** e incolla gli eventuali errori.
2. **Tick volume.** A fine test nel Journal compare `DIAGNOSTICA tick_volume`. Se la media è costante (dev.std ≈ 0), il tester sta usando volume *generato*
   e non quello storico del simbolo: i segnali DELTA non sono quelli di SignalLab e nessuna classe si trasferisce. Se la dev.std è ampia, il volume è quello storico.
3. **Riconciliazione con SignalLab.** Il numero di segnali nel CSV (`SDv2_signals_..._c-1_b240.csv`) deve essere dello stesso ordine di quello di SignalLab per lo stesso
   simbolo e TF (SignalLab ignora ADX/S-R, qui sono etichette; ripeti un breve periodo e confronta le prime righe per data/verso/raffica).
4. **Costi.** Il report stampa spread medio all'ingresso e un avviso se spread = 0 e costo extra = 0. Se lo spread QDM è 0 o fisso il risultato è ottimista:
   imposta `Inp_ExtraCostPts` con commissione + slippage in **punti** (su una coppia JPY a 3 cifre 1 pip = 10 punti).
5. **Accoppiamento deal.** Il report stampa `Ordini aperti / chiusi e abbinati / rifiutati`. La differenza aperti − chiusi deve essere al massimo 1 (posizione ancora aperta a fine test).
   Se è grande, l'accoppiamento tra deal di ingresso e uscita non funziona su questo simbolo e **tutte** le passate darebbero lo stesso risultato: fermati e incollami il Journal.
6. Nel Journal controlla che il conto sia riconosciuto come NETTING e che la classe stampata sia quella attesa.

**Fase 1 — scansione grossolana (45 classi)**
- Tester: modello *OHLC 1 minuto* va bene per l'esplorazione; **ottimizzazione: algoritmo completo lento**; **criterio: Max personalizzato**
  (non *Balance max*: premia i set fortunati).
- Parametro ottimizzato: solo `Inp_ClassID`, **start 0, step `nB+1` (7 con il default), stop 314**. Così scorri solo le classi con ora = ANY.
- *Avanti*: **Personalizzato, data 2022.01.01** (in-sample 2010–2021, fuori campione 2022–2026). Nella scheda *Risultati dell'ottimizzazione*
  leggi sia *Backtest* sia *Forward*.
- Le classi senza nessun trade restituiscono −1000 e finiscono in fondo; una classe che perde ha un t negativo.
- Sotto `Inp_FitMinTrades` (default **100**) la parte positiva del t viene ridotta quadraticamente: con poche decine di trade la soglia vera di significatività è più alta di quella stampata.
- Usa `SDE_FIT_T_R` (default). `SDE_FIT_RECOVERY_PF` è in denaro e con *profitto in pips* su un simbolo custom non è affidabile: non classificare classi con quella.
- Se in uno stesso run i filtri manuali (`Inp_SrcSel`, `Inp_DirSel`, `Inp_BurstMin/Max`, `Inp_Hours`) contraddicono la classe, l'EA rifiuta la passata invece di restituire zero.

**Fase 2 — scansione fine** solo se la fase 1 ha lasciato qualcosa: start 0, step 1, stop 314, stesso periodo.

**Fase 3 — selezione**
Tieni una classe solo se **tutte** queste condizioni sono vere:
1. t in-sample ≥ soglia unilaterale di Bonferroni per il numero di classi provate (tabella sopra);
2. almeno 300 trade in-sample e media di R netta di costi chiaramente positiva;
3. nel forward: stesso segno e t ≥ 2 (una sola classe, non ne scegli una tra tante);
4. la stessa classe con `Inp_Invert = true` non è altrettanto positiva (altrimenti è deriva, non informazione);
5. stabilità per anno nel CSV dei trade (non deve dipendere da 2–3 trade o da un solo anno).

Se nessuna classe passa, la conclusione corretta è che **il segnale non ha un vantaggio operabile in questa forma**: non è un fallimento della procedura.

**Fase 4 — profilo di esecuzione della classe sopravvissuta**
Ottimizza SL, TP e trailing (in ATR) del solo profilo della sorgente interessata, con griglia grossolana e scegliendo un **altopiano**, non il picco.
Ogni combinazione provata va sommata alle classi nel conteggio dei test multipli.

**Fase 5 — walk-forward e demo**: finestre rolling con tick reali (non OHLC 1 minuto), poi demo sullo stesso broker.

## 5. Impostazioni del tester viste nei tuoi screenshot

| Impostazione | Valore | Commento |
|---|---|---|
| Modello *OHLC 1 minuto* | ok per scansione | per la validazione finale usa *ogni tick basato su tick reali* (il simbolo custom deve avere i tick) |
| *Profitto in pips* | attivo | l'R della v2.0 è in prezzo, quindi non ne risente; il *Balance max* sì |
| Criterio *Balance max* | da cambiare | usa *Max personalizzato* (`OnTester`) |
| Ritardo 5 ms | ok | per stress prova 200–500 ms |
| Deposito 1000 EUR, 1:30 | ok per lotto 0.01 | con lotto fisso non cambia R |
| Simbolo `AUDJPY.r_QDM` | custom QDM | verifica spread, commissione, fuso orario e volume dei dati (Passo 0) |

## 6. File prodotti (cartella Common)

| File | Quando | Contenuto |
|---|---|---|
| `SDv2_classmap_<bucket>m.csv` | test singolo | ID → sorgente, verso, raffica, fascia |
| `SDv2_trades_<simbolo>_<TF>_c<ID>_b<bucket>.csv` | test singolo, `Inp_LogTrades` | ogni trade con R, ATR, SL, spread, etichette |
| `SDv2_signals_<simbolo>_<TF>_c<ID>_b<bucket>.csv` | test singolo, `Inp_LogSignals` | ogni segnale con etichette e motivo del blocco (0 = operato) |

Codici `reason`: 0 operato · 1 classe/sorgente/verso/raffica · 2 ore o giorni · 3 filtri · 4 posizione già aperta · 5 spread · 6 ordine rifiutato · 7 ATR non valido.

## 7. Formato di `Inp_Hours` e `Inp_Days`

Solo cifre, virgole e trattini: `7-11,13,15-17`. Vuoto = tutto. Un intervallo con estremi invertiti è a cavallo di mezzanotte (`22-3`).
Giorni: 0 = domenica … 6 = sabato. Qualunque altro carattere (`Mon-Fri`, `7;9`, `8-24`) fa fallire `OnInit` con un messaggio nel Journal.

## 8. Limiti noti e passo successivo

- Le classi misurano **un trade alla volta**: un segnale che arriva con posizione aperta non viene operato (reason 4). Per misurare **ogni** segnale
  indipendentemente dalle sovrapposizioni serve un motore di "trade ombra" che simuli SL/TP/trailing su ogni segnale e scriva l'esito: è il passo
  successivo, da fare dopo che questa versione compila e i suoi numeri sono riconciliati con SignalLab.
- Il regime di volatilità (percentile ATR%+Parkinson) non è ancora un'etichetta; l'intensità TR/ATR sì.
- Il t usa una dispersione minima di 0.25R: una classe i cui trade chiudono tutti esattamente a TP o a SL non può avere un t enorme per pura mancanza di varianza.
- R usa la distanza SL nominale (dal prezzo richiesto): lo slippage reale di riempimento è un costo, non entra nel denominatore.
- Il report per verso (`sig-BUY` / `sig-SELL`) è per verso del **segnale**: con `Inp_Invert = true` i trade eseguiti sono l'opposto (l'EA lo ricorda nel Journal).
- Se un ordine risulta eseguito ma segnalato come fallito (timeout, solo live), la posizione viene riallineata e gestita, ma non entra nelle statistiche di R.
- Il valore `moneyProfit` nel CSV dei trade include la commissione d'ingresso; R non dipende dal denaro.
- Dopo un riavvio live lo stato della raffica si ricostruisce rielaborando le ultime 1000 barre; una raffica più lunga di 1000 barre non è riproducibile.
- In live, se il terminale salta delle barre, l'EA le rielabora solo per lo stato (non opera su barre passate); oltre 900 barre perse ricostruisce lo stato da capo.
