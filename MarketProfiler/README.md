# MarketProfiler Edge

Modulo aggiuntivo per `MarketProfiler.mq5` (script MT5).

- `MarketProfilerEdge.mqh`: il modulo (schede **Sintesi edge** e **Bias e impulsi**).
- `MarketProfilerEdge_patch.html`: pagina che unisce il modulo al tuo `MarketProfiler.mq5` (incolla, applica, copia il file completo).
- `tests/`: banco di prova. Traduce il modulo MQL5 in C++ con le funzioni originali che usa, lo compila con controllo dei limiti degli array e lo esegue su serie sintetiche. `tests/run.sh` lo lancia.

## Cosa aggiunge
1. **Sintesi edge**: verdetto; candidati strategia (R/R e ORB) con 7 controlli (z netto, stabilita' nelle due meta', oltre la stessa ora, placebo, costo di pareggio contro costo broker, una posizione alla volta, soglia di Bonferroni); cosa sopravvive ai test multipli (FDR Benjamini-Hochberg) area per area; bias del momento; profilo di ore e giorni; bias robusti per tipo; numeri di base per timeframe.
2. **Bias e impulsi**: per ora, blocchi 4/6/8/12 ore, giorno, mese, trimestre, semestre: % rialzista, rendimento, range, massimo/minimo nel primo terzo, trend e mean reversion, contro tutti i periodi, con stabilita' nelle due meta'; ora x giorno; giorno del massimo e minimo della settimana; ora dell'impulso piu' forte e del massimo/minimo del giorno contro un atteso da bootstrap delle barre; cosa precede un impulso forte contro le stesse ore degli altri giorni.

## Punti aperti
- Non e' stato compilato con MetaEditor (non disponibile nell'ambiente di sviluppo): compilare con F7 e segnalare gli errori.
- Verifiche fatte nel banco di prova: nessun avviso del compilatore C++ (-Wall -Wextra -Wshadow), nessun indice fuori limite su 8 scenari (rumore puro, effetti piantati, buchi, domenica, senza volume, storico corto), nessuna divisione per zero, calibrazione dei falsi positivi su 20 serie di puro rumore.
