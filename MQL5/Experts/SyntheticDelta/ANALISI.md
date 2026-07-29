# SyntheticDelta EA — Analisi di correttezza e diagnosi backtest

Progetto isolato. Non condivide file con `VolumeProfile` (Magic Number 11111 dedicato).

## 1. Perché Dukascopy (10 anni) dà molti meno trade del test broker (2 anni)

Riferimento report broker allegato: `EURUSD.r`, M30, 2024–2025, **100% tick reali**,
51.837.696 tick / 24.865 barre ≈ **~2.084 tick per barra M30**, **1.118 trade** (~559/anno).
Al medesimo ritmo, 10 anni ≈ 5.500 trade attesi. Osservati ~750 → **crollo ~7×**, sistematico.

### Causa n°1 (dominante, specifica di questo EA): collasso del `tick_volume`
Il segnale dipende linearmente da `volWeight = tick_volume / media(tick_volume)` (cap 3.0):

```
bullsStrength = fracBuy  * (1 + bullsNorm) * volWeight
synDelta      = bullsStrength - bearsStrength
normalizedDelta = synDelta / 6.0
segnale se |normalizedDelta| > SignalThreshold   (report: 0.30)
```

- Tick reali broker: `tick_volume` ~2.000/barra, **oscilla molto** → `volWeight` spazia 0.x–3.
  Sono le barre ad alto volWeight a spingere il delta oltre soglia.
- Dukascopy importato come **barre M1** senza conteggio tick reale: il `tick_volume` M30
  ricostruito ≈ numero di sotto-barre (~30), **quasi costante** → `volWeight ≈ 1` → ampiezza
  del delta compressa → **quasi nessuna barra supera 0.30**. Da qui il fattore ~7×.
- Aggravanti: `if(tickVol<=0) return` e `if(range<=0) return` scartano più barre piatte
  (weekend/festivi/liquidità bassa), più frequenti su serie ricostruite.

### Causa n°2: modello di generazione tick diverso
"100% tick reali" li possiede solo il broker. Un simbolo custom Dukascopy senza *tick* gira in
"1 minuto OHLC" o "Solo prezzi apertura" → `tick_volume` e comportamento intrabar diversi.
Non confrontabile col test a tick reali.

### Causa n°3: Spread filter sul simbolo custom (`Inp_MaxSpreadPoints=30`)
Se lo spread del custom symbol è flottante e prende gli spike di rollover (00:00) o è fisso ≥30,
il filtro scarta entrate su tutto il periodo.

### Diagnosi rapida (conferma in 3 passi)
1. Report Dukascopy → campo **"Qualità dello Storico"**: se ≠ "100% tick reali" → causa n°2.
2. `Inp_DebugMode=true` su un mese Dukascopy → osserva `delta=` e `volWeight`:
   se `volWeight≈1` e `normalizedDelta` schiacciato sotto soglia → causa n°1 (import volume).
3. Run con `Inp_UseSpreadFilter=false`: se i trade risalgono → causa n°3.

Nella maggioranza dei casi è **n°1 + n°2**: l'import a barre M1 impoverisce il `tick_volume`
su cui si regge l'intera formula.

## 2. Verifica correttezza

### 🔴 BUG CRITICO — `OnTester()` legge statistiche errate (corrompe le ottimizzazioni)
Le `#define` in testa al file NON coincidono con l'enum reale `ENUM_STATISTICS` di MQL5:

| Serve            | Valore usato | Cosa legge davvero  | Valore corretto            |
|------------------|:------------:|---------------------|----------------------------|
| STAT_PROFIT      | 1            | STAT_WITHDRAWAL     | **2**                      |
| max DD balance   | 7            | STAT_CONPROFITMAX   | **16** (STAT_BALANCE_DD)   |
| STAT_TRADES      | 20           | STAT_EQUITYMIN      | **31**                     |
| trade vincenti   | 21           | STAT_EQUITY_DD      | **32** (STAT_PROFIT_TRADES)|

Conseguenza: la fitness custom è calcolata su numeri scorrelati → l'optimizer classifica i set
di parametri con una metrica priva di significato. **Da correggere prima di fidarsi di qualsiasi
ottimizzazione.** Fix: rimuovere le `#define` e usare i nomi nativi dell'enum.

### 🟠 Live FP Markets — `ORDER_FILLING_FOK` hardcoded
FP Markets (ECN/Raw) spesso rifiuta FOK su alcuni simboli → ordini scartati (retcode 10030) in
live. Nel tester non emerge. Fix: interrogare `SYMBOL_FILLING_MODE` e scegliere IOC/FOK.

### 🟡 `CalcLotSize()` — rischio calcolato su SL fisso anche con SL ATR
Con `Inp_UseATR_SLTP=true` il position sizing usa comunque `Inp_StopLoss` fisso →
rischio reale ≠ rischio target. (Già annotato nei commenti; reale.)

### Corretto (nessun difetto)
- Calcoli su barra chiusa idx=1: **no repaint / no look-ahead** (motore delta, vol filter,
  expansion filter).
- Gestione stato pending expansion con annullamento in sicurezza su gap/riavvio.
- Filtri ADX/S/R applicati in modo identico alle due sorgenti di segnale.

## Struttura progetto
```
MQL5/Experts/SyntheticDelta/
├── SyntheticDelta_EA_v1.11.mq5   # baseline verbatim (come fornito)
└── ANALISI.md                    # questo documento
```
Fix (STAT enum, filling mode, risk sizing) disponibili come v1.12 su conferma.
