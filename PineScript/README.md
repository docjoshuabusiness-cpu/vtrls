# PineScript

## `mtf_zscore_confluence.pine` — MTF Z-Score Confluence (Pine v6)

Indicatore di confluenza multi-timeframe su z-score, con 5 sezioni e 4 soglie tutte
attivabili/disattivabili indipendentemente.

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
