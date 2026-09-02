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

### Vincoli operativi

- **Mettere il grafico sul TF più piccolo che si vuole osservare.** Tutti i TF delle
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
