# Market Profiler

Analisi **descrittiva** di uno strumento, timeframe per timeframe → report HTML a schede (`report_<SIMBOLO>.html`).

## Installazione
```
pip install -r requirements.txt
```

## Uso
```
# Terminale MT5 FP Markets aperto e loggato (Windows): scarica M1, H1 e D1
python market_profiler.py --mt5 XAUUSD EURUSD US500 --out reports

# Oppure export CSV di MT5 (Visualizza > Simboli > Barre > Esporta). Basta anche solo M1 o solo H1
python market_profiler.py --csv-m1 XAUUSD_M1.csv --csv-h1 XAUUSD_H1.csv --csv-d1 XAUUSD_D1.csv --name XAUUSD

# Report utilizzabile senza internet (plotly.js incorporato, ~5 MB)
python market_profiler.py --mt5 XAUUSD --offline
```
Opzioni `--bars-m1` (default 500000), `--bars-h1` (100000), `--bars-d1` (20000). Se MT5 ne restituisce meno, alza
*Strumenti > Opzioni > Grafici > Barre massime nel grafico* e scorri il grafico indietro per scaricare lo storico.

## Schede
Panoramica · Minuto · Ora · 4 ore · 6 ore · 8 ore · 12 ore · Giorno · Settimana · 2 settimane · Mese · Trimestre ·
Semestre · Anno · Volume. Ogni scheda ha un indirizzo proprio (`report.html#d` = Giorno, `#y` = Anno, …).

Ogni periodo (la candela del timeframe) è scomposto in tre tratti:

| Tratto | Cosa misura |
|---|---|
| apertura → primo estremo | movimento iniziale |
| primo → secondo estremo | **spostamento più ampio** (massimo − minimo) e sua direzione |
| secondo estremo → chiusura | **spostamento di mean reversion** (quanto viene restituito) |

Per ogni timeframe il report mostra:
- **quanto** si muove: percentili dei tratti, in % e in prezzo;
- **quando** si formano il massimo e il minimo e parte il rientro;
- come cambia per ora, giorno, mese e anno;
- cosa succede nel periodo successivo: continuazione o inversione, rottura del massimo/minimo precedente, false
  rotture, sequenze;
- i periodi più ampi della storia e gli ultimi periodi chiusi.

Classificazione di ogni periodo: **Trend** = restituisce ≤ 25% dello spostamento, **Mean reversion** = restituisce
≥ 75%, **Parziale** = in mezzo.

La Panoramica confronta il periodo in corso di ogni timeframe con la storia. La scheda Volume mostra POC, Value Area e
VWAP su 1 settimana … 12 mesi e il volume attuale rispetto alla media (per sessione e per ora).

## Note
- Orari = ora del server (FP Markets EET/EEST, giornata chiusa alle 17:00 di New York).
- Il "quando" ha la risoluzione dei dati usati: Ora da M1, da 4 ore a Settimana da H1, oltre da D1.
- Minuto: ogni periodo è una sola barra, quindi niente "quando" interno.
- CFD = tick volume (misura l'attività, non il controvalore).
