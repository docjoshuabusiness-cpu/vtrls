# MarketProfiler: moduli Edge e Candele

Moduli aggiuntivi per `MarketProfiler.mq5` (script MT5 che scrive un report HTML per simbolo).

## File
- `MarketProfiler.mq5`: **il file completo, pronto da usare**: il tuo MarketProfiler.mq5 con i moduli Edge 1.2 e Candele gia' integrati (20 punti di aggancio applicati). Si sostituisce per intero il contenuto del file in MetaEditor, poi F7.
- `MarketProfilerEdge.mqh`: modulo **Sintesi edge** e **Bias e impulsi**.
- `MarketProfilerCandle.mqh`: modulo **Candele** (tutti i 21 timeframe).
- `MarketProfilerEdge_patch.html`: pagina che unisce i due moduli al tuo `MarketProfiler.mq5` (incolla, applica, copia il file completo).
- `originale/MarketProfiler.mq5`: il file originale prima dei moduli (serve a ricostruire il completo).
- `tests/`: banco di prova (vedi sotto).

## Scheda Candele (modulo Candele)
Rapporto descrittivo su **tutti i 21 timeframe di MT5** (M1 M2 M3 M4 M5 M6 M10 M12 M15 M20 M30 H1 H2 H3 H4 H6 H8 H12 D1 W1 MN1), costruiti dai dati M1 (o M5) sull'orologio dei dati, con la settimana da domenica. Per ogni timeframe:
- **Quando**: ora, minuto, giorno della settimana, settimana del mese, mese, trimestre, anno: range in punti base, quota di candele grandi (oltre 1,5 ATR), quota di impulsi, quota di rialziste, rendimento in ATR. Tabella "dove si muove di piu' e di meno" e tabella incrociata dei 21 timeframe.
- **Eventi piu' frequenti** (con frequenza per giorno di mercato) e cinque movimenti maggiori.
- **Come sono fatte le candele**: 10 forme (doji e varianti, pin, trottola, corpo medio e lungo, marubozu) per direzione; 22 pattern con nome (engulfing, harami, tweezer, morning/evening star, tre soldati/corvi, pin al massimo/minimo di 10 candele, NR4, NR7, chiusura oltre il massimo/minimo di 20 candele, inside/outside bar); tutte le 36 coppie e 216 terne di candele (rialzista/ribassista x piccola/normale/grande); serie nella stessa direzione fino a 6 o piu'.
- **Rispetto ad alti e bassi precedenti**: candela prima (inside, outside, rotture, false rotture, gap), ultime 20 candele, ora, 4 ore, giorno, settimana e mese prima.
- **Stati**: ADX(14) di Wilder, VWAP ancorato (giorno; D1 settimana; W1 mese; MN1 anno) in sigma, z-score del prezzo su 20 candele, volume all'ora (RVOL su 20 occorrenze dello stesso orario), volatilita' ATR14/ATR100, ampiezza.
- **Impulsi**: soglia (percentile `InpImpulsePct` dell'ampiezza, almeno 2 ATR), forma degli impulsi, e **cosa c'e' prima** (volume, ADX, VWAP, z-score, range e movimento delle 3 candele prima, forma della candela prima) contro le candele non impulso della stessa ora e dello stesso regime di volatilita'.
- Ogni classe e' misurata su cosa succede **dopo**: probabilita' che la candela dopo salga, rendimento a 1 e 3 candele in ATR14, rottura del massimo e del minimo, escursioni, corsa a +1 ATR contro -1 ATR entro 12 candele.
- File CSV (punto e virgola, virgola decimale): `MarketProfiler_<simbolo>_candele.csv` (tutte le classi) e `MarketProfiler_<simbolo>_orari_candele.csv` (tutte le fasce di tempo).
- Parametri nuovi: `Candele` (attiva/disattiva) e `Candele: anni` (anni di storico per i timeframe fino a H1; 0 = tutto; M1 con molti anni e' lento).

### Statistica
- z contro tutte le candele del timeframe, con errore **robusto ai cluster (settimane)** e correzione di **Newey-West** a 8 settimane (la volatilita' persiste); per le metriche 0/1 (candele grandi, impulsi) varianza binomiale per l'effetto di disegno misurato su tutte le candele, con correzione di continuita'.
- Controllo **FDR 5% (Benjamini-Hochberg) per famiglia** di confronti: classi di candele; direzione per ora/minuto; direzione per giorno/mese/anno; ritmo dell'attivita' per ora/minuto; ritmo per giorno/mese/anno; precursori degli impulsi. Le stagionalita' della volatilita' sono vere e numerose: nello stesso gruppo abbasserebbero la soglia delle ipotesi di direzione. **†** = supera FDR e ha lo stesso verso nelle due meta' dello storico.
- Mese e trimestre sono testati solo con almeno 3 anni di storico; l'anno e' solo descrittivo.
- Rollover: fino a H1 le candele che toccano la finestra sono escluse; da H2 a H12 le barre nella finestra sono tolte e il range e' riportato alla durata nominale; da D1 le barre nella finestra sono tolte.
- Sono misure **descrittive dell'andamento del prezzo, senza spread, commissioni e slittamento**.

## Sintesi edge e Bias e impulsi (modulo Edge)
1. **Sintesi edge**: verdetto; candidati strategia (R/R e ORB) con 7 controlli (z netto, stabilita' nelle due meta', oltre la stessa ora, placebo, costo di pareggio contro costo broker, una posizione alla volta, soglia di Bonferroni); cosa sopravvive ai test multipli (FDR) area per area; bias del momento; profilo di ore e giorni; bias robusti per tipo; numeri di base per timeframe; blocco con i confronti robusti della scheda Candele.
2. **Bias e impulsi**: per ora, blocchi 4/6/8/12 ore, giorno, mese, trimestre, semestre; ora x giorno; giorno del massimo e minimo della settimana; ora dell'impulso piu' forte e del massimo/minimo del giorno contro un atteso da bootstrap; cosa precede un impulso forte.

### Costi del broker (Edge 1.1+)
Il controllo V (costo di pareggio contro costo del broker) richiede i costi misurati. Se mancano (nessun profilo caricato, oppure spread nullo come nei simboli personalizzati esportati da QuantDataManager) il verdetto lo dice in alto in rosso, i risultati sono **al lordo dei costi** e il livello massimo di un candidato e' `INDIZIO LORDO`. Per avere il controllo: `InpCostsOnly = true` nel terminale del broker (il profilo viene salvato) oppure un costo in punti base in `InpEdRefCostBp`.

## Banco di prova (`tests/`)
`tests/run.sh` traduce i moduli MQL5 in C++ (`translate.py`, `mql_rt.h` con array a controllo dei limiti), li compila con `-Wall -Wextra -Wshadow` e li esegue su serie sintetiche.
- Edge: rumore puro, effetti piantati, buchi, domenica, senza volume, storico corto.
- Candele (`driver2.cpp`): effetti piantati (pin, mercoledi', volume prima degli impulsi), rumore iid e rumore con volatilita' persistente (zero falsi positivi di direzione e di precursori), domenica, buchi, senza volume, base M5, storico minimo, rollover acceso e spento.
- Indicatori (`driver3.cpp`): candele, ATR, ADX, z-score, RVOL, VWAP, finestre di 20 candele ed esiti a 1 e 3 candele contro calcoli indipendenti (errori al limite della precisione a 32 bit).
- Pattern e forme (`driver4.cpp`): candele costruite a mano.
- `build_full.js` ricostruisce il file completo; `make_patch_page.py` e `make_copy_page.py` rigenerano le pagine.

## Punti aperti
- Non e' stato compilato con MetaEditor (non disponibile nell'ambiente di sviluppo): compilare con F7 e segnalare gli errori con il numero di riga.
- Tempo di esecuzione: M1 con molti anni aggiunge minuti; si puo' ridurre con `Candele: anni`.
