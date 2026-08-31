# SessionOpen Probe v1.0 — primi minuti dopo l'apertura H4

## Perché non usa `iTime(PERIOD_H4, 0)`

L'operatività reale è su **futures MT5** (feed CME): lì la griglia H4 è ancorata
all'apertura sessione CME, quindi i confini utili cadono alle **09:00 e 13:00 ET**
(= 15:00 e 19:00 Roma).

Il banco di prova è **FP Markets**, dove quegli stessi istanti cadono alle **17:00
e 21:00 ora server** — ma lì **non sono confini di candela H4**: MT5 taglia le H4 da
mezzanotte server (00/04/08/12/16/20). Un rilevamento basato su `iTime(PERIOD_H4,0)`
sparerebbe alle 16:00 e 20:00, **un'ora prima** dell'evento che interessa, e l'intero
backtest misurerebbe un'altra cosa.

Per questo l'ancoraggio è su **orario esplicito configurabile**, in due modalità.

## Le due modalità di ancoraggio

| `InpAnchorTZ` | `InpAnchorTimes` | Quando usarla |
|---|---|---|
| `TZ_SERVER` | `"17:00,21:00"` | Test su FP Markets. Gli orari sono letti così come sono, in ora server. |
| `TZ_NEWYORK` | `"09:00,13:00"` | **Su qualsiasi piattaforma.** Gli orari sono in ET e vengono convertiti in ora server a runtime. |

`TZ_NEWYORK` gestisce **separatamente** il DST USA (2ª domenica di marzo → 1ª di
novembre) e quello del broker (ultima domenica di marzo → ultima di ottobre). I due
cambi d'ora non coincidono: per ~3 settimane a marzo e ~1 a novembre lo scarto è
diverso. È la modalità che rende confrontabili il test su FP e l'operatività su
futures **senza ritoccare gli orari a mano** — basta impostare
`InpServerGMTOffsetWinter` e `InpServerUsesEUDST` per la piattaforma in uso.

FP Markets: `InpServerGMTOffsetWinter = 2`, `InpServerUsesEUDST = true`.

## Perché il sizing è a rischio %

Su FP il NAS100 è un **CFD** (1 pt = 1 unità indice). Su CME il **NQ** ha tick 0.25
a $5 (MNQ $0.50). Con lotti fissi le due curve equity sono semplicemente
incomparabili. Il volume è calcolato da `SYMBOL_TRADE_TICK_VALUE`/`TICK_SIZE` a
partire da `InpRiskPercent`: la curva **in percentuale** diventa confrontabile tra
i due strumenti.

Se il rischio richiesto non copre il lotto minimo, il trade viene **saltato**, non
arrotondato in su — arrotondare significherebbe rischiare più del dichiarato.

## Flusso di lavoro consigliato

### Fase 1 — misurare (`MODE_PROBE`)

Nessun ordine. Scrive un CSV in `<Common>\Files\` con una riga per evento:
spostamento a +1/+2/+3/+5/+10/+15/+30/+60 min (in **punti base**, così NQ a 7.000
e a 25.000 sono confrontabili), MFE/MAE a ogni checkpoint, opening range, spread
all'apertura, volume, ATR e OHLC della H4 precedente.

I checkpoint non raggiunti restano **celle vuote**, non zero: uno zero verrebbe
letto in analisi come "nessun movimento" e sporcherebbe le medie.

### Fase 2 — il gruppo di controllo (non saltarlo)

`InpControlTimes` (default `"18:00,22:00"`) registra eventi *placebo* a orari non
speciali. Non vengono mai tradati, solo loggati.

Servono a rispondere alla sola domanda che conta: **le 17:00 spiccano davvero, o
stai misurando la normale volatilità di quella fascia oraria?** Un confine di
candela è un artefatto del grafico — nessun flusso istituzionale parte perché si è
aperta una candela su MT5. Se l'effetto c'è, è perché coincide con le 09:00 ET (il
ramp pre-apertura). Senza controlli si trova "qualcosa" ogni singola volta, ed è
così che nascono gli EA che muoiono in live.

### Fase 3 — eseguire (`MODE_TRADE`)

Quattro ipotesi selezionabili con `InpEntryMode`:

- `ENTRY_OR_BREAKOUT` — rottura dell'opening range dei primi K minuti
- `ENTRY_OR_FADE` — il contrario
- `ENTRY_FIRSTBAR_CONT` — continuazione della prima barra M1
- `ENTRY_FIRSTBAR_FADE` — il contrario

Testarle **tutte e quattro** sugli stessi dati: se breakout e fade risultano
entrambe redditizie, il backtest è rotto o i costi sono sottostimati.

## Impostazioni del Tester

Attaccare a un grafico **M1** e testare in **"Ogni tick basato su tick reali"** —
è l'unica modalità che usa lo spread storico reale, e nei primi minuti dopo
l'apertura lo spread **è** il costo dominante. Con "1 minuto OHLC" si ottengono
statistiche OHLC valide ma percorso intrabar e spread non realistici. Con modalità
più grezze i primi minuti non esistono proprio e il test è privo di significato.

## Numeri da tenere a mente

2 eventi/giorno × ~252 giorni = **~500 eventi/anno**, cioè ~250 per ciascuna delle
due ore. Con 5-6 anni si arriva a ~1.300 per ora.

Basta per stimare una media marginale. **Non basta** per affettare per
giorno-della-settimana × regime × direzione precedente (20 celle → ~60 campioni
ciascuna = rumore puro). La lista delle ipotesi va decisa **prima** di guardare i
dati, poi corretta per multiple testing.

## Costi che decidono tutto

Sul CFD NAS100 di FP lo spread tipico in RTH è ~1.0–1.8 pt, ma **tra le 09:00 e le
09:35 ET si allarga a 3–8 pt** — esattamente la finestra che si vuole tradare.
Round trip realistico: **2–4 punti**. Se lo spostamento medio nei primi 5 minuti è
8 punti, metà del lordo è già del broker.

`InpMaxSpreadPts` filtra gli eventi con spread eccessivo. Lasciarlo a 0 (default)
disattiva il filtro e l'EA lo segnala in init: senza filtro il backtest sarà
ottimista.
