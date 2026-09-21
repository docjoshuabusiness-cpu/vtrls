# Audit — VTRLS_MoveResearch_v1.mq5

Revisione statica. Non compilato (niente MetaEditor in questo ambiente): i punti
qui sotto vengono dalla lettura del sorgente, non da un run.

Ordinati per impatto sui numeri, non per gravità formale. Le sezioni A sono
errori che **cambiano le conclusioni**; B è memoria e tempo; C sono incoerenze
che non sbagliano un conto ma fanno sbagliare la lettura.

Verificato e **corretto** (nessuna azione necessaria): conteggio colonne di tutti
i 24 CSV contro le rispettive intestazioni, bilanciamento `<section>` contro gli
indici `tab(i)` del JavaScript, bound di tutti gli array indicizzati da bin
(`SW_NB`, `VP_MAXVA`, `ORB_MAXRR`, `THR_MAX`, `SH_SLOTS`), reset dello stato
globale fra simboli, ordine `basePt` → `CellAdd`, aritmetica del leave-one-out
sul segno della valuta.

---

## A — Errori che falsano i risultati

### A1. Il costo medio è diviso per il denominatore sbagliato

`sCost` viene sommato **solo sulle rotture che diventano operazioni**:

```mql5
g_orb[w].nBrk++;                          // conta TUTTE le rotture
if(dir==0){ g_orb[w].nAmb++; continue; }  // ambigue: non operabili
...
if(stopAtr<InpOrbMinStopAtr) continue;    // stop sotto il minimo: non operabili
...
g_orb[w].sCost+=costAtr;                  // solo qui
```

`OrbScore()` lo divide correttamente per `win+loss+flat`. Ma quattro file di
output lo dividono per `nBrk`:

```mql5
double meanCost  = g_orb[wi].sCost/g_orb[wi].nBrk;   // _orb_stop.csv
double meanCost2 = g_orb[wj].sCost/g_orb[wj].nBrk;   // _orb_orizzonte.csv
double mc        = g_orb[wg].sCost/g_orb[wg].nBrk;   // _orb_gestione.csv
double mcS       = g_orb[g_orbSel].sCost/g_orb[g_orbSel].nBrk;  // _orb_stop_orizzonte.csv
```

Il costo esce **sottostimato del rapporto operabili/rotture**. Su una finestra al
60% di operabilità le colonne `E_netto_in_R` sono ottimiste del 40%. Sono
esattamente le quattro tabelle su cui si decide se la famiglia paga.

Correzione: `int tot=g_orb[i].win+g_orb[i].loss+g_orb[i].flat;` e dividere per
quello, come già fa `OrbScore()`.

### A2. Con `InpOrbCostPt = 0` tutte le colonne di costo alternative vanno a zero

```mql5
double invAtr = (InpOrbCostPt>0.0 ? meanCost/InpOrbCostPt : 0.0);
```

`invAtr` è la media di `1/ATR` ricavata *dividendo* per il costo base. A costo
base zero diventa zero, e `CostCells()` restituisce `eR - 0` per **ogni** valore
di `InpCostPtList`. L'utente vede dieci colonne di costo diverse tutte identiche
al lordo e non ha modo di accorgersene. Stesso schema in `WgCostCells()`.

L'input dichiara che a zero "la colonna netta è una copia della lorda" — vero per
quella singola colonna, ma la documentazione non copre il collasso silenzioso
delle altre dieci.

Correzione: ricavare `invAtr` dall'ATR, non dal costo — accumulare direttamente
`sInvAtr += 1.0/atrPt` accanto a `sCost`.

### A3. `WgCostCells` riscala anche il finanziamento

```mql5
double cR = (InpOrbCostPt - InpSwapPtDay*held)*pointSz/sd;   // in WgTrade
double c  = cR * g_costPt[i]/base;                            // in WgCostCells
```

`cR` contiene spread **e** swap. Riscalarlo per il rapporto fra spread
alternativi moltiplica anche lo swap: a 55 punti invece di 7, un finanziamento di
10 punti/giorno diventa 78. Sullo swing multi-giorno lo swap è la voce dominante,
quindi la colonna a costo alto è completamente sbagliata.

Correzione: accumulare spread e swap separati, riscalare solo il primo.

### A4. La calibrazione dello stop è misurata su un campione già selezionato

```mql5
if(stopAtr < InpOrbMinStopAtr) continue;   // stopAtr = lo stop di DEFAULT
...
if(doSw)  for(int m=0;m<g_nSw;m++) { ... }   // tutta la spazzata sta dentro
```

La spazzata su 40 stop, gli orizzonti e la gestione girano **solo** sulle rotture
che hanno superato il filtro calcolato sullo stop di default. È lo stesso trucco
che il codice denuncia a proposito di `OrbTradePct`: su una finestra stretta lo
stop di default supera il minimo solo nei giorni in cui quella fascia si è mossa
in modo anomalo, e tutta la curva dello stop viene tarata su quelle eccezioni.

Peggio: agli stop **in punti** il filtro non si applica affatto (sono fissi in
punti, non in ATR), quindi vengono misurati su un campione selezionato da un
criterio che non li riguarda.

Correzione: spostare il filtro `InpOrbMinStopAtr` dentro il ciclo per-stop,
scartando la singola combinazione e non l'intera rottura.

### A5. Le tabelle per giorno della settimana non sono confrontabili con la classifica

```mql5
int fl = g_orb[i].dBrk[d] - rs;              // "irrisolte"
double v = 100.0*pb*OrbExpLow(wn,ls,fl,OrbTgt(i));   // costo omesso → default 0
```

Due problemi nella stessa riga:

1. `dBrk[d]` conta tutte le rotture, `dRes[d]` solo quelle risolte. La differenza
   include le **ambigue** e quelle scartate per stop minimo, che non sono
   operazioni irrisolte: sono operazioni mai aperte. Il denominatore di
   `OrbExpLow` è gonfiato e E/score escono deflazionati.
2. `OrbExpLow` è chiamato **senza** l'argomento costo (default 0), mentre
   `OrbScore()` lo passa. Gli score per giorno sono lordi, quello generale è
   netto: la nota che dice "lo score resta sulla scala comune" è falsa.

Vale sia per la tabella HTML `tO3` sia per la riga `finestra_per_giorno` di
`_orb_tempi.csv`.

### A6. `news_flag` ha due significati diversi nello stesso progetto

```mql5
// _daily.csv, _largest.csv
int ni = NearestNews(lmStart,nDist);                       // passato O futuro
int nFlag = (ni>=0 && MathAbs(nDist)<=InpNewsWindowMin);   // |dist|

// _scan.csv
int nextNews = MinutesToNextNews(s.t);                     // solo futuro
s.newsFlag = (nextNews>=0 && nextNews<=InpNewsWindowMin);
```

Nei primi due file la colonna è **contaminata da look-ahead**: un evento uscito
dopo l'inizio del Largest Move accende il flag. È innocuo finché la colonna resta
descrittiva, ma è nominata come quella point-in-time dello scan, e il cercatore
che gira sui CSV non ha modo di distinguerle. È il tipo di colonna che produce un
edge che sparisce a mercato.

Correzione: rinominarla `news_flag_lookahead` nei due file descrittivi, oppure
aggiungere accanto la versione point-in-time.

### A7. Lo scan misura l'orizzonte in barre, l'ORB in minuti

```mql5
int horBars = MathMax(1, InpScanHorizonMin/g_tfMin);
if(g+horBars >= nScanEnd) break;
int endIdx = g+horBars;                       // conteggio di BARRE
...
datetime hEnd = r[kb].time + (datetime)(OrbHorizon()*60);   // minuti REALI
```

Su un simbolo con barre mancanti — sessione asiatica su un cross minore, festivi
americani, qualunque cosa sotto M5 — `horBars` barre coprono **più** di
`InpScanHorizonMin` minuti di calendario. Il che significa che la griglia
point-in-time usa un orizzonte più lungo di quello dichiarato proprio nelle ore
illiquide, cioè dove le probabilità di base sono più basse e dove il confronto
conta di più. E `g_overlap`, che corregge gli intervalli di confidenza, è
calcolato sull'orizzonte dichiarato.

I due moduli devono usare la stessa convenzione. Quella giusta è il tempo reale.

### A8. L'ATR non è quello di MetaTrader, e il warm-up è troppo corto

```mql5
for(int i=InpATRPeriod;i<nd;i++)
{
   double s=0;
   for(int j=i-InpATRPeriod+1;j<=i;j++) s+=tr[j];
   atr[i]=s/InpATRPeriod;                     // media SEMPLICE
}
```

`iATR` usa lo smoothing di Wilder. Questa è una SMA. I due divergono in modo
sistematico dopo un salto di volatilità, e ogni soglia in ATR di questo script —
stop, target, bin, compressione — è quindi tarata su una grandezza che non
coincide con quella che leggerà l'EA che userà `iATR`. Non è sbagliato in sé, ma
va dichiarato, altrimenti la ricerca e l'implementazione misurano due cose
diverse.

Separatamente:

```mql5
datetime warm = InpFrom - (datetime)((InpATRPeriod+5)*86400);
```

19 giorni **di calendario** per riempire un ATR(14) su barre **giornaliere**: con
i weekend fanno ~13 sedute, una meno del necessario. Le prime giornate del
periodo richiesto finiscono in `skNoAtr` e spariscono dal campione. Serve
`*86400*7/5`.

### A9. La validazione di `InpBaseTF` non copre più i valori che `TFMinutes` accetta

```mql5
g_tfMin = TFMinutes(InpBaseTF);
if(g_tfMin < 0) { Print("ERRORE: InpBaseTF deve essere compreso tra M1 e H1."); return; }
```

`TFMinutes` è stata estesa a H2…W1 per servire `InpExtraTfList`. Ora
`InpBaseTF = PERIOD_D1` supera il controllo, `g_tfMin` vale 1440, `stepMin`
diventa 1440, `horBars` diventa 1 e lo script gira producendo zero righe di scan
senza dire perché. Il messaggio d'errore descrive un vincolo che il codice non
applica più.

Correzione: `if(g_tfMin < 1 || g_tfMin > 60)`.

### A10. Lo swing conta giorni di trading e li chiama giorni di calendario

```mql5
input string InpSwgDays = "2,3,5,8,13,21";  // Orizzonti in GIORNI di calendario
...
int hEnd = (int)MathMin(n-1, i0 + g_wgDay[hz] - 1);   // indici D1 = sedute
double cR = (InpOrbCostPt - InpSwapPtDay*held)*pointSz/sd;   // held = sedute
```

`n` indicizza barre D1, quindi 5 "giorni" sono 5 **sedute** = 7 giorni di
calendario. Due conseguenze: la colonna `giorni` del CSV mente, e lo swap è
sottostimato del 40% perché i weekend non vengono contati (e sul forex il venerdì
notte è swap triplo, che qui non esiste affatto).

### A11. Leave-one-out dello swing: sottrazione su barre in cui la coppia non ha contribuito

```mql5
for(int i=0;i<n;i++)
   if(po[i][p]>0.0){ sc[i][c]+=sg*pr[i][p]; cc[i][c]++; }   // solo se la barra esiste
...
int nb = cc[i][ib]-1;                                        // sempre -1
f1[i] = (nb>0 ? (sc[i][ib]-pr[i][p])/nb : 0.0);              // sempre sottratto
```

Nelle barre in cui la coppia operata non ha dati, il suo contributo non è dentro
`sc` e `cc` non la conta — ma il leave-one-out lo sottrae lo stesso e decrementa
il denominatore. Il TSI è ricorsivo, quindi l'errore non resta locale: si propaga
in avanti per tutta la lunghezza dello smoothing.

Il ciclo dei segnali richiede `po[i][p]>0.0`, quindi il segnale non nasce mai su
una barra sporca — ma nasce su una barra il cui TSI è stato contaminato da quelle
precedenti.

### A12. La scala principale della forza non ha maschera di validità

Le scale aggiuntive ce l'hanno, ed è la cosa giusta:

```mql5
bool good = (ok2[q]!=0 && run*2>=span);
g_sOk[tot+q] = (uchar)(good?1:0);
```

La scala principale no: `CsAxis` riempie `oOk[]` ma `CsBuild` lo ignora per
`InpStrTF` e `CsAt()` restituisce sempre un valore. Su H1 il danno è contenuto,
ma il codice stesso spiega perché la maschera serve — "il TSI decade verso zero,
cioè verso forza neutra, che è l'unica lettura che un lettore non può
distinguere da un dato vero" — e poi non la applica dove la forza viene
effettivamente usata dai filtri 31–34 e da `StrBin()`.

---

## B — Memoria e tempo

### B1. `SBrk` pesa 284 byte, non 80

Il commento dell'input dice "circa 80 byte l'uno". Contando i campi:
13 float + 2 + 1 + 2 + 1 + 1 + 3×8 float (`xr/xc/xz`) + 6 (`xs`) + 6 (`xt`) +
5 (`vpVaWidthV`) float, più `resR[8]`, `vpStateV[5]`, gli interi e i char →
**~284 byte con allineamento**.

`InpOrbMaxRec = 700000` × 284 ≈ **199 MB**, non 56. Su un terminale a 32 bit non
parte; su 64 bit fa swappare. Il valore di default va abbassato o il commento
corretto — comunque va corretto, perché è il numero su cui l'utente decide.

### B2. ~25 MB di array globali sempre allocati

```
g_swW/g_swL/g_swF : 3 × 156×48×8×21 int   ≈ 15.1 MB
g_swSumAtr        : 156×48×21 double      ≈  1.3 MB
g_mgSum           : 156×12×8×21 double    ≈  2.5 MB
g_mgN/g_mgRes     : 2 × stessa forma int  ≈  2.5 MB
g_hz*             :                       ≈  3.8 MB
```

Allocati anche con `InpDoStopSweep=false` e `InpDoManage=false`, perché sono
statici. `SW_WH = SW_MAXW × SH_SLOTS = 156` moltiplica tutto per 13 anche quando
`InpSweepHorizons` è vuoto.

### B3. Gli indicatori vengono ricalcolati ~20 volte per barra

```mql5
datetime iFrom = dStart - (datetime)((need*20+300)*sec);
int cnt = CopyRates(sym, IndTF(t), iFrom, dEnd+InpScanHorizonMin*60, ri);
CalcCCI(tp,cnt,InpCciPeriod,bC);    // O(n × periodo)
CalcCCI(tp,cnt,InpCciPeriod2,bC2);
CalcCCI(tp,cnt,InpCciPeriod3,bC3);
CalcZScore(cl,cnt,InpZsPeriod,bZ);  // O(n × periodo)
```

Il warm-up è di `need*20+300` barre e viene rifatto **ogni giornata**: ogni barra
entra nel calcolo di una ventina di giornate diverse. Sopra ci sono tre CCI e uno
Z-Score implementati in O(n·periodo) invece che in forma incrementale, moltiplicati
per tre timeframe.

Con M1, `need=50`, 4000 giornate: dell'ordine di 10^10 operazioni solo per gli
indicatori. È il collo di bottiglia dominante, più dei `CopyRates`.

Due correzioni indipendenti, entrambe grandi:
- CCI e Z-Score in forma incrementale (somma e somma dei quadrati scorrevoli):
  O(n) invece di O(n·p). Per il CCI serve la deviazione **media** assoluta, che
  non è incrementale in modo esatto — ma un ricalcolo ogni N barre con
  aggiornamento incrementale in mezzo taglia comunque un ordine di grandezza.
- caricare le serie indicatore **una volta per simbolo** invece che per giornata.

### B4. ~12 `CopyRates` per giornata

3 (indicatori) + 7 (`InpExtraTfList`) + 1 (VP del giorno precedente) + 1 (base).
Su 4000 giornate sono ~48.000 chiamate. Vale la stessa correzione: caricare per
simbolo, indicizzare per giornata.

### B5. `ArrayResize(g_bk,0)` non libera memoria

In `OrbInit()`, fra un simbolo e l'altro. MQL5 conserva la capacità allocata:
serve `ArrayFree(g_bk)`. Con `InpSymbols="*"` la memoria del simbolo peggiore
resta occupata per tutto il run.

---

## C — Incoerenze che non sbagliano un conto ma fanno sbagliare la lettura

**C1.** `ResolveForward` valuta il target **anche sulla barra d'ingresso**; il
modulo ORB esplicitamente no (`if(q>kb && ...)`). Entrambe le scelte sono
difendibili, ma i due moduli non sono confrontabili fra loro e nessuna nota lo
dice.

**C2.** `CondCell` (HTML) colora sulla baseline **globale**, `WriteCells` (CSV)
calcola il lift su quella **di sessione**. Il commento lo ammette e dice di
credere al CSV — ma è l'HTML quello che si guarda per primo, e una cella verde
lì può essere rossa nel file.

**C3.** `ShInit()` non deduplica `g_shMin[0]` (l'orizzonte base) contro la lista:
se `InpSweepHorizons` contiene 240 e `OrbHorizon()` vale 240, escono due righe
identiche con etichette diverse.

**C4.** `LoadCalendar(sym, warm, InpTo)` usa `InpTo` invece di `effTo`. Innocuo,
ma scarica eventi che non serviranno mai quando il periodo viene ristretto.

**C5.** Le intestazioni di sezione sono `input string sec1 = "=== ... ==="` invece
di `input group`. Funzionano, ma occupano slot di input veri: compaiono
nell'ottimizzatore, finiscono nei file `.set`, e uno di loro (`s2`) ha già
causato una collisione con una variabile locale, documentata nel codice.

---

## D — Stagionalità: cosa c'è e cosa manca

Rispetto all'obiettivo dichiarato — comportamento giornaliero, settimanale,
mensile e annuale — la copertura attuale è:

| scala | presente | come |
|---|---|---|
| intraday | parziale | distribuzione oraria e a 15 min **del solo Largest Move**, più la dimensione `ora`/`m15` nelle condizioni marginali |
| settimanale | sì | `aggDow`, dimensione `giorno`, matrici giorno×ora e giorno×15min |
| mensile | parziale | solo **mese dell'anno** (`aggMon`), tutti gli anni accorpati |
| annuale | sì | `aggYear`, matrice anno×ora — ed è il controllo di regime migliore del report |

Mancano tre cose, e la prima è quella che conta:

1. **Nessuna misura del rendimento semplice per bucket.** Tutto è condizionato:
   o sul Largest Move (noto a posteriori, e lo script lo dice), o sulla griglia
   target/stop. Non esiste da nessuna parte la domanda più semplice — *qual è il
   rendimento medio della barra che apre alle 15:00, con che t-stat* — che è
   l'unica che si può confrontare fra strumenti e fra anni senza dipendere da
   stop, target, orizzonte o costi.

2. **Giorno del mese e turn-of-month.** Assenti del tutto. È l'effetto stagionale
   con la letteratura più solida (ribilanciamenti e flussi pensionistici) e
   l'unico che sugli indici sopravvive regolarmente fuori campione.

3. **Il riassunto non esiste come vista unica.** L'informazione stagionale è
   distribuita su cinque schede e va ricomposta a mano.

Il punto 1 non si risolve dentro questo file senza toccare la griglia
point-in-time, che è la parte più delicata. Sta quindi in uno script separato,
`MQL5/Scripts/SeasonalityScanner_v1.0.mq5`, che produce il suo HTML: ora del
giorno, giorno della settimana, giorno di trading del mese con turn-of-month,
mese dell'anno, tutti con n, media e mediana in basis point, win rate, t-stat,
p-value, soglia di Bonferroni per famiglia e concordanza IS/OOS — più la
distribuzione oraria di dove si forma massimo e minimo di giornata, che è il dato
più direttamente operabile di tutti.

---

## Ordine di intervento

| # | Intervento | Perché prima |
|---|---|---|
| 1 | A1 — denominatore del costo medio | Quattro tabelle di decisione sono ottimiste, e sono quelle su cui si sceglie |
| 2 | A2 + A3 — colonne di costo alternative | Oggi con costo base 0 sono tutte finte, e sullo swing lo swap viene moltiplicato |
| 3 | A4 — filtro dello stop minimo dentro il ciclo | La curva dello stop è tarata sulle eccezioni |
| 4 | A5 — denominatore e costo nelle tabelle per giorno | Dichiarano una scala comune che non hanno |
| 5 | A7 — orizzonte in minuti anche nello scan | Rende `g_overlap` e quindi ogni Wilson dello scan leggermente sbagliati |
| 6 | A9 — validazione di `InpBaseTF` | Fallimento silenzioso con zero output |
| 7 | B1 — `InpOrbMaxRec` o il suo commento | Il default chiede 200 MB dicendo che ne chiede 56 |
| 8 | B3 — indicatori per simbolo e in forma incrementale | È il motivo per cui un run dura ore |
