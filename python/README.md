# Market Profiler

Analisi quantitativa di uno strumento → report HTML interattivo (`report_<SIMBOLO>.html`).

## Installazione
```
pip install -r requirements.txt
```

## Uso
```
# Terminale MT5 FP Markets aperto e loggato (Windows)
python market_profiler.py --mt5 XAUUSD EURUSD US500 --out reports

# Export CSV di MT5 (Visualizza > Simboli > Barre > H1 > Esporta). D1 opzionale per uno storico più lungo
python market_profiler.py --csv-h1 XAUUSD_H1.csv --csv-d1 XAUUSD_D1.csv --name XAUUSD

# Report utilizzabile offline (plotly.js incorporato, circa 5 MB)
python market_profiler.py --mt5 XAUUSD --offline
```
Opzioni: `--bars-h1` (default 100000) e `--bars-d1` (default 20000). Se il terminale ne restituisce meno,
alza *Strumenti > Opzioni > Grafici > Barre massime nel grafico* e scorri il grafico indietro per scaricare lo storico.

## Contenuto del report
| Sezione | Domanda a cui risponde |
|---|---|
| Verdetto | Sintesi automatica dei risultati significativi |
| Cruscotto | Com'è la situazione attuale e cosa è successo storicamente in condizioni simili |
| Come cambia il prezzo | Trend di fondo, drawdown, fasi di trend e di mean reversion nel tempo (VR mobile), volume |
| Movimenti per orizzonte | Distribuzione dei rendimenti, range, MFE/MAE in % e in prezzo su 4h … 12m |
| Regime | Momentum, mean reversion o random walk per orizzonte (Variance Ratio + TSMOM) |
| Matrice momentum | Quale mossa passata predice quale mossa futura |
| Quando prosegue / si inverte | Continuazione condizionata a forza della mossa, efficienza, volatilità, volume |
| Quando il trend è più forte | In quali condizioni il movimento successivo è più direzionale |
| Ora del giorno | Sessioni da breakout e sessioni da range |
| Mean reversion | Probabilità di rientro verso la media mobile e di toccarla |
| Streak, stagionalità | Persistenza delle sequenze, effetti ora/giorno/mese |
| Volume | POC, Value Area, VWAP su 1w…12m; volume attuale vs storico (per giorno e per ora) |

## Limiti
- Orari = ora del server (FP Markets EET/EEST).
- CFD = tick volume (attività, non controvalore).
- Nessun costo di transazione incluso.
- Con meno di 30 finestre indipendenti (6m–12m) i numeri sono descrittivi, non statistici.
