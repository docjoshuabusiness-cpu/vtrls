# GEX Map — Dealer Gamma Exposure per Nasdaq CME (NQ / MNQ)

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

## 2. Perché il gamma su NQ non nasce dalle opzioni su NQ

Il CME quota opzioni sul future E-mini Nasdaq, ma il loro open interest è una
frazione di quello di **NDX** e **QQQ**. Il gamma che i dealer devono realmente
coprire — e che quindi muove il prezzo — sta sulle opzioni **cash e ETF**.

Lo script aggrega quindi **NDX + QQQ**, riporta tutto in **punti NDX** (unica scala
in cui i due si sommano) e aggrega su una griglia regolare (default 25 punti,
perché gli strike QQQ riscalati cadono su valori non tondi e senza binning non si
sommerebbero mai a quelli NDX).

## 3. Il basis NDX → NQ, e la trappola del roll

Gli strike sono in punti **NDX cash**; il grafico è il future **NQ**. Il
differenziale è il cost of carry:

```
F ≈ S · e^{(r − q)·T}
```

Vale tipicamente **decine di punti** e decade a zero a scadenza. L'indicatore lo
calcola live:

```
livello_grafico = strike × moltiplicatore + basis
basis = MEDIANA( close(NQ) − close(NDX) × moltiplicatore , N )
```

**Mediana, non media, ed è deliberato.** `NQ1!` è un contratto continuo: al roll
trimestrale il basis salta di decine di punti in un tick. Una media impiega N barre
a recuperare, e per tutte quelle barre ogni livello sul grafico è fuori posto.
La mediana assorbe il salto quasi subito.

In più il pannello mostra **Stato basis**: se il basis grezzo devia dal filtrato
oltre la soglia, segnala `ROLL / DESYNC` e c'è un alert dedicato. In quella
finestra i livelli non sono affidabili — non tradarli.

Impostazioni: sottostante `NASDAQ:NDX`, moltiplicatore `1.0`, basis `Auto`.

## 4. Il modulo di sizing: perché sta dentro un indicatore di gamma

Su conto prop (TopStep, Apex e simili) ciò che ti elimina non è la perdita
realizzata, è la **trailing drawdown** — che nella maggior parte dei firm conta
anche l'**unrealized**. Il vincolo binding è quindi l'**escursione avversa
intraday (MAE)**, non il P&L di chiusura.

E la MAE è esattamente la variabile che il regime di gamma predice: in gamma
negativo la sua distribuzione ha code molto più grasse. Conseguenza operativa
diretta: **size costante fra i due regimi = rischio di breach non costante**.

Da qui il moltiplicatore di regime (default 0.5 in gamma negativo) e lo stop
ancorato al livello GEX più vicino invece che a un multiplo di ATR — perché è lì
che l'hedging reale ha una probabilità decente di fermare il prezzo.

Il pannello riporta: stop long/short in punti (arrotondati al tick, con buffer
oltre il livello), size massima in contratti, e **quanti stop consecutivi ti
concede il daily limit** a quella size. Se quel numero scende sotto 3, la size è
troppo alta per sopravvivere a una giornata storta.

> I numeri di daily loss limit, trailing drawdown e profit target **cambiano fra
> firm, fra taglie di conto e nel tempo**. Sono input: mettici i tuoi, letti dal
> contratto. Non fidarti di valori sentiti dire.

Valore punto: **NQ $20/pt**, **MNQ $2/pt**, tick 0.25 (quindi $5 e $0.50 a tick).
Su conti prop piccoli il MNQ è quasi sempre l'unico strumento che permette una
size ≥ 1 contratto con stop ancorati a livelli veri.

## 5. Cash session

Il gamma hedging avviene sul mercato **cash**. Fuori dalla RTH (09:30–16:00 ET) i
livelli restano riferimenti strutturali, ma il regime non è operativo: nessun
dealer sta ribilanciando. Con `rthOnly` attivo la tinta di sfondo si spegne fuori
sessione, così non ti convince di un contesto di hedging che in quel momento non
esiste.

## 6. Uso operativo

```bash
pip install yfinance numpy pandas scipy

# default: aggrega NDX + QQQ, output in punti NDX su griglia da 25
python tools/gex_from_chain.py --days 21 --top 24
```

Copia le righe sotto `# ---- incolla da qui in giù ----` nel campo
**"Profilo GEX per strike"** dell'indicatore. Rifallo **una volta al giorno**:
l'open interest si aggiorna a fine sessione, un profilo di tre giorni fa descrive
un mercato che non esiste più.

## 7. Come si legge

| Elemento | Significato | Uso |
|---|---|---|
| **Gamma Flip** (linea gialla) | dove il gamma cumulato dei dealer cambia segno | è la linea di demarcazione del regime, non un livello di prezzo |
| **Sopra il flip** — long gamma | l'hedging dei dealer è contro-trend: vendono forza, comprano debolezza | vol compressa, range, mean reversion. Fade degli estremi, non breakout |
| **Sotto il flip** — short gamma | l'hedging è pro-trend: vendono debolezza, comprano forza | vol espansa, code grasse. Momentum, stop più larghi, size ridotta |
| **Call Wall** | massimo gamma positivo | tetto magnetico. Sopra, il muro cade e spesso parte l'accelerazione |
| **Put Wall** | massimo gamma negativo | pavimento. Sotto, si entra nella zona di gamma negativo |
| **Istogramma** | intensità per strike | dove il prezzo tende a incollarsi (pinning), soprattutto in scadenza |
| **RV 5/20** | vol realizzata breve / lunga | conferma empirica: long gamma + RV<0.8 = regime coerente; long gamma + RV>1.2 = il profilo è stantio o l'ipotesi di posizionamento è sbagliata |

## 8. Cosa questo modello NON è

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

## 9. Uso corretto nel workflow

Il GEX va a monte, non a valle:

- **Long gamma** → abilita i sistemi mean-reversion, disabilita i breakout.
- **Short gamma** → abilita i momentum/breakout, allarga gli stop, taglia la size
  (la vol realizzata sarà più alta della tua stima storica).
- **Prezzo entro ~0.3 ATR dal flip** → zona di indecisione: è dove i falsi segnali
  si concentrano. Il default sensato è stare fuori.
- **`ROLL / DESYNC` nel pannello** → flat. I livelli sono geometricamente sbagliati.
- **Fuori cash session** → i livelli non hanno un hedger dietro. Nessun edge da GEX.

## 10. File

| File | Contenuto |
|---|---|
| `PineScript/GEX_Map.pine` | indicatore TradingView (Pine v6) |
| `tools/gex_from_chain.py` | calcolo GEX dalla catena opzioni |
| `PineScript/README_GEX.md` | questo documento |
