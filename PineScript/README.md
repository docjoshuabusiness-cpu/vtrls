# PineScript

## `mtf_zscore_confluence.pine` — MTF Z-Score Confluence (Pine v6)

Indicatore di confluenza multi-timeframe su z-score, con 5 sezioni e 4 soglie tutte
attivabili/disattivabili indipendentemente.

**Doppia vista da un solo script.** L'indicatore vive in un pannello separato, dove
disegna le cinque curve z, la curva del timeframe più veloce e i livelli di soglia e
di trigger degli stream attivi. I **marker dei segnali** vengono però spinti sul
grafico dei prezzi tramite `force_overlay`, così le frecce/pallini stanno sulle
candele e il quadro statistico resta leggibile sotto. Curve e livelli si spengono
indipendentemente dal gruppo "Grafica".

> **Installazione**: nel Pine Editor premi `Ctrl+A` per selezionare *tutto* il template
> di default (`//@version=6`, `indicator("My script")`, `plot(close)`) e poi incolla.
> Incollare in coda produce l'errore `CE10243`: un file Pine ammette una sola
> dichiarazione `indicator()`.

### Logica in due stadi

1. **ARMAMENTO** — per una data soglia `T`, *tutti* i timeframe attivi devono aver
   raggiunto `z >= T` (setup SELL) o `z <= T` (setup BUY) almeno una volta entro
   `lookback` barre del grafico.
2. **TRIGGER** — il segnale viene stampato sulla prima barra in cui il **timeframe
   più veloce fra quelli attivi** attraversa il *livello di trigger*:
   - `Rientro (reversione)`: crossunder del livello di trigger (SELL) / crossover (BUY).
     Esempio: armamento a `+2`, trigger a `+1` → SELL quando il TF veloce rientra sotto +1.
   - `Primo tocco della soglia`: crossover della soglia stessa (setup di continuazione).

Un **latch** garantisce un solo segnale per episodio di armamento, più un `cooldown`
in barre configurabile.

### Le 4 soglie sono stream indipendenti

`A (+2)`, `B (+1)`, `C (−1)`, `D (−2)` — ciascuna con proprio ON/OFF, proprio livello e
proprio livello di trigger. Attivandone più di una si ottengono serie di segnali
distinte e confrontabili sullo stesso grafico (marker etichettati A/B/C/D).

### Base di calcolo dello z-score (`zBasis`) — la scelta che conta

| Modo | Cosa calcola | Finestra | n effettivo |
|---|---|---|---|
| **A · TF nativo** (default) | z dentro il TF di riferimento, su `len` barre **di quel TF** | `len × tf` — diversa per ogni sezione | `len` |
| **B · Barre grafico (serie HTF)** | serie del TF mappata sul grafico, media/stdev su `len` **barre del grafico** | uguale per tutte le sezioni | `len / k` ⚠ |
| **C · Barre grafico (orizzonte equivalente)** | z sul prezzo **del grafico**, finestra `len × k` barre | stessa di A, a piena risoluzione | `len × k` |

con `k = tf_sezione / tf_grafico`.

**Il tetto algebrico dello z-score.** Con deviazione standard di popolazione (quella
usata da `ta.stdev` per default) il massimo |z| ottenibile da `n` osservazioni è

    max|z| = sqrt(n - 1)

Nel **modo B** la serie HTF mappata sul grafico è a gradini: il close a 5m resta
costante per `k` barre, quindi il campione effettivo è `len/k`, non `len`. Con
grafico 15S, sezione 5m e `len = 100` si ottiene `n_eff = 5` e quindi `max|z| = 2.00`:
quella sezione **non può superare la soglia +2** e la confluenza non si arma mai.
Non è un bug ed è impossibile aggirarlo con la taratura. La colonna `n · cap` della
dashboard mostra campione e tetto per ogni sezione, e colora la riga di **rosso**
quando il tetto è sotto la soglia attiva più ambiziosa.

Il **modo C** è la versione corretta di "z-score dei TF superiori calcolato con le
candele del timeframe corrente": stesso orizzonte temporale del modo A, ma calcolato
sul prezzo del grafico a piena risoluzione — nessun gradino, nessun repaint, nessuna
barra di conferma da perdere, campione effettivo `len × k`. In questo modo il TF della
sezione smette di essere una richiesta di dati e diventa un puro **moltiplicatore di
orizzonte**: due sezioni con lo stesso `k` producono z identici, quindi vanno
differenziate via `len`.

### Serie dedicata per il trigger

Armamento e trigger sono due cose distinte e possono usare serie diverse.
L'armamento chiede che *tutte* le sezioni attive siano state in soglia entro la
finestra; il trigger è il momento in cui **una sola curva** riattraversa il
livello. Legare quest'ultima alla sezione più veloce la costringeva a ereditarne
il modo e la `len`, che è una dipendenza inutile: in modo C, per esempio, la
sezione 15S non è affatto lo z-score a 15S, è lo z del prezzo del grafico su un
orizzonte equivalente.

Con `Serie dedicata per il trigger` (default ON) il trigger usa una serie propria,
definita da `timeframe del trigger` e `len del trigger` e calcolata **sempre in modo
nativo**. Le 5 sezioni restano libere di usare qualunque `zBasis`, e il marker cade
sulla barra in cui la curva che stai davvero guardando attraversa il livello.

Per replicare un indicatore esterno basta ricopiarne timeframe e Length in questi
due campi: con `15S` e `17` la curva di trigger è identica a un riferimento
configurato `Length 17 · Close · Timeframe 15 seconds`. La riga `trigger` della
dashboard mostra in azzurro il timeframe e la durata reale della finestra in uso.

#### Il ritardo di gradino, e come si toglie

`request.security` restituisce il valore dell'ultima candela HTF **chiusa**. Una
candela 15S copre 3 barre di un grafico a 5s, quindi lo z-score arriva come una
scala a gradini che cambia una volta ogni 3 barre: il rientro sotto il livello di
trigger viene rilevato al gradino, non nell'istante in cui il prezzo lo produce.
Ritardo medio `k-1` barre, con `k = TF trigger / TF grafico`.

`trigger LIVE` (default ON) lo elimina senza introdurre look-ahead: centro e scala
della distribuzione continuano a venire dalle candele HTF **chiuse**, mentre il
numeratore usa il prezzo **corrente** della barra del grafico:

    z_live = (prezzo corrente − media HTF chiusa) / dev.std HTF chiusa

Lo z si aggiorna a ogni barra da 5s e il marker cade sulla barra in cui il rientro
avviene davvero. Nessun dato futuro: è esattamente ciò che un operatore vede in
tempo reale. Con stimatore robusto la scala usata è `MAD / 0.6745`, così la formula
resta identica allo z robusto.

Unico caso in cui va spento: sorgente `Log Return`, dove il rendimento della barra
del grafico ha una scala diversa da quello della candela HTF e la ricostruzione non
è coerente.

### Riprodurre un indicatore z-score esistente

Per confrontare una sezione con un altro indicatore z-score, i parametri devono
coincidere tutti, non solo il timeframe. Dato un riferimento con `Length 17`,
`Source Close`, `Timeframe 1 minute`:

| Impostazione | Valore |
|---|---|
| Base di calcolo | `A · TF nativo` |
| Sorgente | `Close` |
| Base (media) | `SMA` |
| Stimatore robusto | OFF |
| Solo barre HTF chiuse | OFF (se il riferimento aggiorna sulla candela in formazione) |
| `len` della sezione 1m | `17` |

La formula diventa identica: `z = (close - sma(close,17)) / stdev(close,17)` calcolata
sulle candele da 1 minuto. Con `len` diverso le due curve **non possono** coincidere:
una finestra 6 volte più lunga produce una curva molto più liscia che non raggiunge
gli stessi estremi. Se una sezione non scende sotto −2 quando il riferimento lo fa,
il primo posto da guardare è la colonna `n · cap` della dashboard, che mostra la
finestra realmente in uso.

### Diagnostica: perché non compaiono segnali

Le ultime tre righe della dashboard dicono dove si rompe la catena, senza dover
tirare a indovinare sui parametri:

- colonna **`hit`** (per sezione) — quante volte quella sezione ha *attraversato* la
  soglia attiva più alta. Una sezione a **0** (in rosso) è quella che blocca tutto:
  o la sua soglia è irraggiungibile (vedi `n · cap`), o quel timeframe non arriva
  mai a quell'estensione.
- riga **`armate`** (per stream) — su quante barre *tutte* le sezioni attive erano
  contemporaneamente in soglia. **0 in rosso con `hit` alti** significa che le
  sezioni sono estreme ma **non insieme**: la finestra di confluenza è troppo stretta.
- riga **`segnali`** (per stream) — quante volte è poi scattato il trigger. **0 in
  arancio con `armate` > 0** significa che il problema non sono le soglie ma il
  livello di trigger, che il timeframe veloce non riattraversa mai.

**Taratura della finestra di confluenza.** Deve contenere almeno 2 barre della
sezione più lenta, altrimenti quella sezione è di fatto immobile e dovrebbe trovarsi
già in soglia nell'istante esatto in cui ci arriva la più veloce:

    lookback minimo ≈ 2 × (TF più lento / TF del grafico)

Su grafico 5s con sezione più lenta a 5m: `2 × (300/5) = 120` barre. Con il default
di 10 barre la confluenza non si arma praticamente mai.

### Vincoli operativi

- Modo **C**: nessun vincolo di repaint, ma servono `len × k` barre di storico
  disponibili; la finestra è capata a 4000 barre.
- Modi **A** e **B**: **mettere il grafico sul TF più piccolo che si vuole osservare.** Tutti i TF delle
  sezioni devono essere `>=` al TF del grafico. Un TF inferiore fa restituire a
  `request.security()` l'ultimo valore intrabar → **repaint**. Il cruscotto segnala
  la sezione incriminata con `⚠ < grafico`.
- I TF a secondi (`15S`, `30S`) richiedono un piano TradingView con dati a secondi e
  hanno storico molto corto.
- `Solo barre HTF chiuse (no repaint)` applica lo shift di 1 barra **solo** ai TF
  superiori al grafico: il TF veloce non viene ritardato, quindi il trigger resta puntuale.

### Note quantitative

- Gli z-score multi-TF calcolati sullo stesso prezzo sono **fortemente collineari**:
  la "conferma di 5 TF" contiene molta meno informazione indipendente di quanto sembri
  (numero effettivo di gradi di libertà ≈ 1.5–2). Sorgente `Log Return` riduce il
  problema rendendo la serie stazionaria; finestre `len` non sovrapposte fra TF lo
  riducono ulteriormente.
- Lo stimatore **robusto (mediana/MAD)** evita che un singolo outlier gonfi la stdev e
  sopprima lo z-score proprio nel momento di massima estensione. Consigliato su
  timeframe a secondi, dove i tick anomali sono frequenti.
- La finestra di confluenza è misurata in **barre del grafico** (= unità di tempo
  uniforme), non in barre native di ciascun TF: è l'unica definizione che rende
  confrontabile "simultaneità" fra 15S e 5min.
