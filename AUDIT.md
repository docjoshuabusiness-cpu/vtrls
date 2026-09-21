# Audit tecnico — VolumeProfile ULTIMATE ML (indicatore v9.2 + EA v1.0)

Revisione statica dei due sorgenti presenti nel repo. Ordinati per impatto reale
sul P&L, non per gravità formale. Nessuno di questi punti è stato ancora corretto:
questo documento è la lista di lavoro.

---

## A — Errori che falsano i profili (colpiscono indicatore ED EA)

### A1. `UpdateStandardProfiles()` costruisce il profilo sbagliato
`Indicators/…v9.2…mq5:1817` · `Experts/…v1.0…mq5:757`

```mql5
profile.start = iTime(_Symbol, tf, i + 1);
profile.end   = iTime(_Symbol, tf, i);
if(i == 0) profile.end = TimeCurrent();
```

Due difetti in tre righe:

1. **Sfasamento di un periodo.** Il profilo indicizzato `i` va dall'apertura della
   candela `i+1` all'apertura della candela `i`, cioè contiene i dati del periodo
   `i+1`. Tutti i profili storici sono etichettati con un giorno/settimana/mese di
   ritardo.
2. **Il profilo 0 è largo il doppio.** Con `i == 0`, l'intervallo diventa
   *apertura di ieri → adesso*: POC, VAH e VAL del "profilo corrente" sono calcolati
   su due sedute fuse insieme. È il profilo su cui l'EA decide di entrare.

Corretto: `start = iTime(tf, i)`, `end = (i == 0) ? TimeCurrent() : iTime(tf, i-1)`.

### A2. `GetSessionTime()` cammina sui giorni di calendario
`Indicators:1841` · `Experts:768`

```mql5
datetime base = TimeCurrent() - (days_back * 86400);
```

Sabato e domenica vengono contati come giorni di sessione. Con
`InpHistoryPeriods = 20` i profili di sessione effettivamente costruiti sono
~14, non 20, e il numero varia col giorno della settimana in cui gira l'EA.
Serve un'iterazione sulle barre reali (o uno skip esplicito di `day_of_week` 0 e 6).

### A3. Overflow latente dello shift DST
`Indicators:1852` · `Experts:779`

```mql5
dt.hour = (int)StringToInteger(parts[0]) + dst_shift;
```

Con un orario di sessione a `23:00` e ora legale attiva si ottiene `dt.hour = 24`.
`StructToTime()` non garantisce la normalizzazione dei campi fuori range. Oggi non
esplode solo perché il valore più alto negli input di default è `19:00`. Va
normalizzato: `if(h >= 24) { h -= 24; giorno++; }`.

### A4. Il "pip" è definito solo per il forex
`Indicators:846,1153` · `Experts:928,1131`

```mql5
double pip = g_Adaptive.pip_value * 10;   // pip_value == SYMBOL_POINT
```

`point * 10` è un pip solo sui simboli FX a 5 o 3 decimali. Su XAUUSD, sugli indici
e sulle cripto è un numero arbitrario: `InpVADistance = 15` significa distanze
completamente diverse da strumento a strumento, e l'ottimizzatore lo compensa
adattando altri parametri — che è il modo classico per ottenere un backtest che non
si replica. Va sostituito con una distanza in unità di ATR (già disponibile) o in
tick reali.

---

## B — Logica di trading dell'EA

### B1. Le sessioni sovrapposte non vengono mai valutate (impatto alto)
`Experts:914`

```mql5
for(int p = 0; p < g_TotalProfiles; p++) {
    if(bar_time >= g_Profiles[p].start && bar_time <= g_Profiles[p].end) {
        EvaluateSignal(shift, g_Profiles[p]);
        return;                                 // ← esce al PRIMO profilo
    }
}
```

Le sessioni di default si sovrappongono per costruzione:
Sydney `00–09` vs Asian `02–11`, London `10–19` vs New York `15–00`.
I profili sono inseriti in `g_Profiles` nell'ordine Sydney → Asian → London → NY,
quindi il `return` fa sì che:

- fra le 02 e le 09 venga valutata **solo** Sydney, mai Asian;
- fra le 15 e le 19 venga valutata **solo** London, mai New York.

La finestra 15–19 è l'overlap London/NY, cioè il momento di massima volatilità e
massimo volume della giornata: il profilo NY è calcolato, disegnato e poi ignorato.

### B2. `InpOneSignalPerSession` smette di funzionare dopo ~160 sessioni
`Experts:1020` + `Experts:411`

`g_Signals` è dimensionato a `g_TotalProfiles * 2` (160 in modalità sessioni) e non
viene mai riciclato né azzerato in runtime. `UpdateSignalTracker()` cerca uno slot
libero (`session_start == 0`); esaurito l'array, esce senza registrare nulla e senza
errori. Da quel momento il limite "un segnale per sessione" è disattivato.
In backtest su un anno l'array satura dopo ~40 giorni.

### B3. Nessun controllo dello stops level
`Experts:1419` (ordini) e `Experts:1688` (trailing)

Né `ExecuteMarketOrder()` né `ProcessTrailing()` verificano
`SYMBOL_TRADE_STOPS_LEVEL` / `SYMBOL_TRADE_FREEZE_LEVEL`. Con SL a `1 × ATR` su
timeframe bassi la distanza può finire sotto il minimo del broker: l'ordine viene
rifiutato con retcode 10016 e il segnale è perso in silenzio (`InpDebugMode` è
`false` di default). Su FP Markets succede regolarmente sugli indici.

### B4. Dimensionamento posizione
`Experts:1392`

- `NormalizeDouble(lots, 2)` è cablato a 2 decimali: rompe ogni simbolo con
  `lot_step = 0.001`.
- Quando il lotto calcolato è sotto il minimo viene alzato a `min_lot`, superando il
  rischio richiesto senza alcun avviso. Con `RiskPercent = 1%` su un conto piccolo il
  rischio effettivo può essere il 3–4%.
- `SSymbolCache.tick_value` è letto una sola volta in `OnInit()`. Sui cross non
  denominati nella valuta del conto cambia col tasso di cambio: il sizing deriva nel
  tempo.

---

## C — Il modulo "ML". È qui che si trova il problema principale

### C1. Le etichette di training sono gonfiate (bias ottimistico)
`Experts:1587`

```mql5
if(tp_distance > 0 && h >= entry + tp_distance) { is_winner = true;  break; }
if(sl_distance > 0 && l <= entry - sl_distance) { is_winner = false; break; }
```

Il TP è controllato prima dello SL **sulla stessa barra**. Se una barra tocca
entrambi i livelli — situazione frequente su H1 con SL a 1×ATR e TP a 2×ATR — il
segnale viene etichettato come vincente. Non è un dettaglio: è una forma di
look-ahead che sposta sistematicamente verso l'alto il win-rate di training, e
quindi la probabilità stimata dal modello. Serve una risoluzione su M1 o, come
minimo, l'assunzione pessimistica (SL prima).

### C2. L'ensemble non è un ensemble
`Experts:505` · `Indicators:546`

I tre "modelli" sono tre regressioni logistiche con **le stesse identiche feature**,
allenate **sullo stesso dataset**, con **la stessa loss**, **lo stesso learning rate**
e **lo stesso ordine di presentazione dei campioni**. L'unica differenza sono i pesi
iniziali. La discesa del gradiente li fa convergere allo stesso ottimo: dopo qualche
retrain "Conservative", "Balanced" e "Aggressive" emettono probabilità quasi
identiche.

Conseguenza: il `consensus 3/3` non contiene informazione — i tre voti non sono
indipendenti — e la media pesata `0.35 / 0.30 / 0.35` è puramente decorativa.
Un ensemble reale richiede diversità: feature diverse, bagging sui campioni,
o famiglie di modelli diverse.

### C3. L'accuracy mostrata in dashboard non misura nulla
`Experts:1244`

```mql5
double predicted = PredictProbability(g_MLHistory[i].features, m) / 100.0;
…
g_MLModels[m].feature_weights[k] += learning_rate * error * …;   // aggiorna i pesi
…
if(predicted_win == actual_win) correct++;                        // e misura
```

La predizione è calcolata **con i pesi che vengono modificati nello stesso ciclo**, e
su **tutto il dataset di training**. Il numero risultante è insieme in-sample e
misurato su un modello che cambia a metà misurazione. Non ha relazione con la
performance fuori campione. Serve una separazione train/validation temporale
(walk-forward) e la valutazione a pesi congelati.

### C4. Nessuna regolarizzazione, campioni duplicati, campione minimo irrisorio

- Nessun termine L1/L2 e nessun clipping: i pesi possono divergere, e con `lr = 0.01`
  su record riusati ad ogni retrain si ottengono di fatto epoche multiple su un
  campione minuscolo.
- `TrainEnsembleModels()` parte con **20 segnali chiusi**. Con 12 feature, 20
  osservazioni sono meno di due campioni per parametro: il modello memorizza, non
  generalizza.
- `RecordMLSignal()` è invocato in `TryFireSignal()` a **ogni barra** che soddisfa le
  condizioni tecniche. Lo stesso setup persistente entra nel training 5–10 volte:
  osservazioni fortemente correlate trattate come indipendenti, con sovrappeso
  proprio sui setup che restano aperti a lungo senza risolversi.

### C5. Stessa feature, due definizioni diverse fra EA e indicatore
`Experts:1145` vs `Indicators:1135`

```mql5
// EA
f.volume_quality = MathMin(profile.total_vol / 1000000.0, 1.0);
// Indicatore
double CalculateVolumeQuality(double v) { … v / GetAverageProfileVolume() … }
```

L'EA usa una costante cablata a 1.000.000, l'indicatore una media adattiva. Sul
tick volume di una sessione, `total_vol / 1e6` vale tipicamente 0.001–0.02: la
feature è praticamente costante e non porta informazione. Ma soprattutto **lo stesso
setup produce score ML diversi nell'indicatore e nell'EA**: le frecce sul grafico non
corrispondono ai trade.

### C6. La correzione multi-simbolo rompe la calibrazione
`Experts:1211`

```mql5
double adj = 0.85 + 0.30 * sym_weight;
vote.ensemble_prob = MathMin(vote.ensemble_prob * adj, 100.0);
```

Una probabilità stimata viene moltiplicata per un fattore arbitrario fra 0.85 e 1.15
**dopo** la sigmoide. Un segnale al 60% diventa 69% e supera la soglia di 65% senza
che nulla sia cambiato nel setup. Se il peso per simbolo deve contare, va inserito
come feature prima dell'addestramento, non come moltiplicatore a valle.

---

## D — Cosa manca del tutto

Non esiste alcuna analisi del comportamento ricorrente dello strumento su base
oraria, settimanale, mensile o annuale. È la lacuna colmata da
`MQL5/Scripts/SeasonalityScanner_v1.0.mq5`.

---

## Ordine di intervento consigliato

| # | Intervento | Perché prima |
|---|---|---|
| 1 | B1 — valutare tutti i profili che contengono la barra | Metà dei segnali potenziali oggi non viene nemmeno testata |
| 2 | A1 — correggere l'indicizzazione dei profili standard | L'EA decide su un profilo che fonde due sedute |
| 3 | C1 — risolvere l'ambiguità TP/SL intrabar | Finché le etichette sono gonfiate, ogni metrica ML è finzione |
| 4 | C3 — walk-forward con pesi congelati | Senza questo non si sa se il ML aggiunga o tolga valore |
| 5 | B3 — controllo stops level | Segnali persi in silenzio in produzione |
| 6 | C2 — diversificare l'ensemble o ridurlo a un modello | Meglio un modello onesto che tre copie |

**Test di controllo prima di qualunque ottimizzazione:** girare l'EA con
`InpEnableML = false` sullo stesso periodo. Se il risultato non peggiora in modo
netto, il modulo ML sta aggiungendo solo gradi di libertà, e va rimosso o rifatto.
