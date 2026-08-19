# rangelab — event study su rotture di range a orario fisso

Laboratorio per rispondere a una domanda sola: **fra le N rotture che lo stesso
range genera in una giornata, ce n'e' una selezionabile in anticipo che abbia
expectancy positiva?**

Non e' un backtester. E' uno strumento di misura: estrae gli eventi, li etichetta
in modo coerente col trade reale, e prova a smontare qualunque edge apparente.

## Installazione

```bash
pip install pandas numpy scipy
```

## Uso

**Collaudo su rumore puro** — la pipeline deve NON trovare edge:

```bash
python run_study.py --synthetic --edge 0.0
```

**Collaudo con edge iniettato** — la pipeline deve ritrovarlo:

```bash
python run_study.py --synthetic --edge 0.40
```

**Dati reali** (export MT5 a 1 minuto, ora server del broker):

```bash
python run_study.py --csv NQ_M1.csv --data-tz "+03:00" \
    --range-start 08:00 --range-end 10:00 --session-end 22:00 \
    --timeframe 5min --tp-mult 1.0 --sl-mult 0.5 --cost-ticks 3
```

## Fusi orari

`--data-tz` e' il fuso **dei dati**, `--analysis-tz` quello in cui si esprimono
le finestre orarie (default `Europe/Rome`). Le finestre `--range-start/end` e
`--session-end` sono SEMPRE nel fuso di analisi.

Gli export MT5 portano l'ora del server senza informazione di fuso: FP Markets
sta su GMT+2 d'inverno e GMT+3 d'estate. Un offset fisso (`"+03:00"`) e' corretto
solo se l'export copre un periodo omogeneo; per storici lunghi serve un nome IANA
con le stesse regole di ora legale del server, altrimenti la finestra oraria
scivola di un'ora per meta' dell'anno e i risultati sono spazzatura.

**Verifica sempre** che la sezione 2 riporti un numero di giorni con range valido
vicino al numero di giorni di borsa attesi. Se e' molto piu' basso, il fuso e'
sbagliato.

## Le otto sezioni del report

| # | Sezione | Cosa guardare |
|---|---------|---------------|
| 1 | Dati | intervallo coperto, numero barre |
| 2 | Range di accumulazione | giorni validi, distribuzione delle ampiezze |
| 3 | Eventi di rottura | eventi per giorno, quota di rientri nel range |
| 4 | Triple barrier | expectancy grezza su TUTTI gli eventi |
| 5 | Expectancy condizionata | `rho_raw` e `p_bh`: quali feature contano |
| 6 | Selezione | `first_ok` e' l'unica colonna operabile |
| 7 | Test di permutazione | batte una scelta casuale a parita' di giorni? |
| 8 | Walk-forward su BQS | soglia dal train, score a pesi uguali |
| 9 | Walk-forward con score ristimato | **il numero che conta** |

Si legge dal fondo. La sezione 9 e' l'unica in cui selezione delle feature,
normalizzazione e soglia sono tutte stimate dentro il train: se l'edge non
sopravvive li', non esiste.

## Difese contro l'autoinganno

Ogni scelta di progetto qui serve a rendere piu' difficile trovare un edge falso.

**Causalita'.** Ogni normalizzazione usa `shift(1)` prima di ogni rolling. Il
volume e' z-scorato contro lo stesso minuto del giorno nei giorni precedenti:
senza quella normalizzazione si misura l'ora, non l'evento.

**Un trade al giorno.** Gli eventi dello stesso giorno sono fortemente correlati.
Contarli come osservazioni indipendenti gonfia lo Sharpe e i test di
significativita' diventano finzione.

**Look-ahead esplicito.** La policy `best_bqs` sceglie la rottura migliore della
giornata: non e' operabile, perche' per saperlo bisognerebbe aspettare sera e
tornare indietro a entrare. E' riportata solo come limite superiore teorico, e
lo dichiara nell'intestazione della colonna. Sul rumore puro produce Sharpe 3.4:
serve proprio a mostrare quanto e' facile fabbricare un backtest bellissimo.

**Etichette asimmetriche.** Il triple barrier riproduce TP, SL e scadenza. Quando
una barra tocca entrambe le barriere si assume che sia stato colpito prima lo SL:
e' l'ipotesi conservativa, l'unica difendibile senza dati tick.

**Costi dentro l'etichetta.** `--cost-ticks` (spread + commissione) e' gia'
sottratto: ogni R riportato e' netto.

**Test multipli.** Testando 11 feature, una "significativa al 5%" e' attesa per
puro caso. `p_bh` applica la correzione Benjamini-Hochberg. La colonna `rho_q`
(Spearman sui 5 punti dei quintili) e' volutamente affiancata a `rho_raw` per
mostrare quanto e' debole: su rumore puro produce regolarmente rho di 0.9 con
p sotto 0.05.

**Null corretto nel test di permutazione.** Il confronto e' contro "k giorni a
caso, un evento a caso per giorno". Pescare k eventi dal calderone sarebbe un
null sbagliato: sovrappeserebbe le giornate confuse, quelle con molte rotture,
e il confronto risulterebbe favorevole per pura contabilita'.

**Pesi uguali.** Il BQS non ottimizza i pesi. Su poche migliaia di osservazioni
l'1/N batte quasi sempre i pesi stimati fuori campione. I pesi si toccano solo
dopo che l'equipesato ha dimostrato un edge.

## Validazione della pipeline

Il generatore sintetico e' il banco di prova, e va rieseguito dopo ogni modifica
al codice:

| Comando | Esito atteso |
|---------|--------------|
| `--edge 0.0` | sezione 9: nessun edge stabile |
| `--edge 0.40` | sezione 9: edge positivo in tutti gli anni di test |

Stato attuale: rumore 1/3 anni positivi (edge medio **-0.045 R**), edge iniettato
3/3 anni positivi (edge medio **+0.041 R**).

## Struttura

```
rangelab/
  data.py       loader CSV/MT5, fusi orari, generatore sintetico
  features.py   CCI, AMA, ATR, ER, profilo di volume, estrazione eventi
  labeling.py   triple barrier con costi
  study.py      score, expectancy condizionata, permutazione, walk-forward
run_study.py    riga di comando
```

## Feature estratte per ogni evento

| Feature | Definizione |
|---------|-------------|
| `compression` | `-log(W / mediana_20(W))` — range stretto rispetto al solito |
| `poc_centrality` | `1 - 2|POC - mid| / W` — l'accumulazione e' bilanciata? |
| `entropy` | entropia del profilo di volume, normalizzata |
| `er` | efficiency ratio di Kaufman sulla rottura |
| `expansion` | range della barra di rottura / range medio in accumulazione |
| `body_ratio` | corpo / range della barra di rottura |
| `vol_z` | z-score del log-volume vs stesso minuto nei 20 giorni precedenti |
| `attempt` | numero del tentativo nella giornata |
| `minutes_after_range` | minuti trascorsi dalla fine dell'accumulazione |
| `cci`, `cci_agree` | CCI(20) e concordanza col verso della rottura |
| `ama_agree` | concordanza col filtro AMA di Kaufman |
| `reentered` | il prezzo e' rientrato nel range entro N barre |
