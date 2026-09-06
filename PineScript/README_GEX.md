# GEX Map — Dealer Gamma Exposure per NAS100

## 1. Il vincolo da cui parte tutto

TradingView **non espone la options chain**. Nessun open interest, nessuna implied
volatility, nessuna greca per strike. Il Gamma Exposure **non è calcolabile dentro
Pine Script**: qualunque script che dichiari di farlo sta plottando un proxy di
price action con un nome altisonante.

Architettura corretta, in due stadi:

```
opzioni NDX/QQQ  ──►  tools/gex_from_chain.py  ──►  testo "strike : gex"
                                                         │
                                                         ▼
                            PineScript/GEX_Map.pine  ──►  livelli sul NAS100
```

## 2. Il problema del basis (specifico per chi tradisce NAS100 CFD)

Gli strike vivono su **NDX cash** (o QQQ). Il tuo grafico è un **CFD sul future NQ**
di FP Markets. Fra i due c'è un differenziale che vale tipicamente **30–90 punti** e
si muove con tassi, dividendi e giorni a scadenza del future.

Plottare gli strike grezzi significa sbagliare i livelli di quell'ordine di
grandezza — su NAS100 è la differenza fra un rimbalzo preso e uno stop.

L'indicatore corregge automaticamente:

```
livello_grafico = strike × moltiplicatore + basis
basis = SMA( close(chart) − close(sottostante) × moltiplicatore , N )
```

| Fonte strike | Moltiplicatore | Sottostante da impostare |
|---|---|---|
| Opzioni NDX / NQ | `1.0` | `NASDAQ:NDX` |
| Opzioni QQQ | `~41` (o usa `--scale-to-ndx` nello script) | `NASDAQ:QQQ` |

Lo smoothing serve perché i due feed non tickano sincronizzati: senza media il
basis salta e i livelli tremano.

## 3. Uso operativo

```bash
pip install yfinance numpy pandas scipy

# strike già convertiti in punti NDX -> moltiplicatore 1.0 nell'indicatore
python tools/gex_from_chain.py --ticker QQQ --scale-to-ndx --days 21 --top 24
```

Copia le righe sotto `# ---- incolla da qui in giù ----` nel campo
**"Profilo GEX per strike"** dell'indicatore. Rifallo **una volta al giorno**:
l'open interest si aggiorna a fine sessione, un profilo di tre giorni fa descrive
un mercato che non esiste più.

## 4. Come si legge

| Elemento | Significato | Uso |
|---|---|---|
| **Gamma Flip** (linea gialla) | dove il gamma cumulato dei dealer cambia segno | è la linea di demarcazione del regime, non un livello di prezzo |
| **Sopra il flip** — long gamma | l'hedging dei dealer è contro-trend: vendono forza, comprano debolezza | vol compressa, range, mean reversion. Fade degli estremi, non breakout |
| **Sotto il flip** — short gamma | l'hedging è pro-trend: vendono debolezza, comprano forza | vol espansa, code grasse. Momentum, stop più larghi, size ridotta |
| **Call Wall** | massimo gamma positivo | tetto magnetico. Sopra, il muro cade e spesso parte l'accelerazione |
| **Put Wall** | massimo gamma negativo | pavimento. Sotto, si entra nella zona di gamma negativo |
| **Istogramma** | intensità per strike | dove il prezzo tende a incollarsi (pinning), soprattutto in scadenza |
| **RV 5/20** | vol realizzata breve / lunga | conferma empirica: long gamma + RV<0.8 = regime coerente; long gamma + RV>1.2 = il profilo è stantio o l'ipotesi di posizionamento è sbagliata |

## 5. Cosa questo modello NON è

Onestà intellettuale, perché queste ipotesi sono la parte fragile:

1. **La convenzione dealer long-call / short-put è un'assunzione statistica**, non un
   dato di posizionamento. Su indici con molto flusso istituzionale di put protettive
   può essere semplicemente falsa.
2. **L'OI è T+1.** Intraday il profilo è già vecchio. È una mappa strutturale, non un
   trigger.
3. **Il gamma flip qui è l'attraversamento dello zero del cumulato**, non la vera
   superficie di zero-gamma ripricata a ogni spot. Scostamento tipico: qualche
   decimo di punto percentuale — irrilevante per il livello, rilevante se ci metti
   uno stop a 5 punti.
4. **Il GEX non è un segnale di ingresso.** È un filtro di regime che dice quale
   famiglia di strategie ha aspettativa positiva oggi. Usarlo come indicatore di
   entrata secco è il modo più rapido per perdere soldi con dati corretti.

## 6. Uso corretto nel workflow

Il GEX va a monte, non a valle:

- **Long gamma** → abilita i sistemi mean-reversion, disabilita i breakout.
- **Short gamma** → abilita i momentum/breakout, allarga gli stop, taglia la size
  (la vol realizzata sarà più alta della tua stima storica).
- **Prezzo entro ~0.3 ATR dal flip** → zona di indecisione: è dove i falsi segnali
  si concentrano. Il default sensato è stare fuori.

## 7. File

| File | Contenuto |
|---|---|
| `PineScript/GEX_Map.pine` | indicatore TradingView (Pine v6) |
| `tools/gex_from_chain.py` | calcolo GEX dalla catena opzioni |
| `PineScript/README_GEX.md` | questo documento |
