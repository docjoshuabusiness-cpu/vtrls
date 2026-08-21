# VTRLS_MoveResearch_v1 — motore di ricerca condizioni operative

Script MQL5 (non EA, non fa trading). Legge lo storico di uno o piu' simboli e
produce 6 CSV in `MQL5/Files/<InpOutDir>/`. Separatore `;`, decimale `.`.

## Installazione
Copiare `VTRLS_MoveResearch_v1.mq5` in `MQL5/Scripts/`, compilare (F7),
trascinare sul grafico, impostare gli input, eseguire.
Prima di lanciarlo scaricare lo storico del TF base (Strumenti > Opzioni >
Grafici > barre massime = illimitato; poi aprire il grafico M1 e premere Home
finche' la storia non e' completa).

## Regola anti-bias (fondamentale)
Il **Largest Move** e' noto solo a posteriori: descrive, non predice. Non e'
un'etichetta valida per costruire una strategia, perche' quando parte non sai
che sara' il piu' grande della giornata.

Percio':
- le colonne `pre_*` del file `_daily.csv` usano **solo** le barre che
  precedono la barra di inizio del Largest Move;
- le tabelle delle condizioni **non** usano il Largest Move come target, ma
  la domanda operativa reale, calcolata sulla griglia point-in-time:

  > date queste condizioni all'istante *t*, qual e' la probabilita' che nelle
  > prossime N ore il prezzo faccia +X **prima** di fare -X*AdverseRatio?

  Entrata all'open della barra *t*, esito per **first touch** target/stop.
  Se target e stop cadono nella stessa barra si conta **stop** (ipotesi
  conservativa: senza tick non si conosce l'ordine intrabar).

## Due formati di output
`InpWriteHtml` (default true) produce **`<SYM>_report.html`**: un file autonomo,
doppio clic e si apre nel browser. Nessuna libreria esterna, nessuna
connessione, funziona offline. Contiene sette schede (Riepilogo, Giornaliero,
Largest Move, Orari, Aggregati, Condizioni incrociate, Condizioni marginali) con
ordinamento cliccando sulle intestazioni, filtro testuale e colorazione
automatica delle celle rilevanti.

`InpWriteCsv` (default true) produce i CSV con tutte le colonne, inclusa la
griglia point-in-time grezza, per Excel e Python. L'HTML omette qualche colonna
per restare leggibile: per l'analisi seria usa i CSV.

Puoi disattivare l'uno o l'altro.

## File prodotti

| File | Contenuto |
|---|---|
| `<SYM>_daily.csv` | 1 riga/giorno: blocco D-1, blocco D pre-evento, Largest Move, news |
| `<SYM>_largest.csv` | solo il movimento maggiore: ora inizio/fine, direzione, punti, durata, ATR, sessione, news |
| `<SYM>_timedist.csv` | distribuzione dei Largest Move per bucket H1 e M15 |
| `<SYM>_scan.csv` | griglia point-in-time grezza (feature a *t* + esito forward) |
| `<SYM>_conditions.csv` | condizioni incrociate (range D-1 x dir D-1 x punti pre x net x sessione x news) |
| `<SYM>_conditions_marg.csv` | stesse metriche, una dimensione per volta (piu' campioni, piu' robusto) |
| `<SYM>_aggregate.csv` | giornate raggruppate per giorno della settimana, anno, mese e sessione |
| `<SYM>_dow_hour.csv` | matrici giorno x ora, giorno x 15 minuti e anno x ora |
| `<SYM>_indicatori_tf.csv` | stessi stati RSI/CCI/Z-Score calcolati sui tre timeframe, con delta sul riferimento |
| `<SYM>_orb_finestre.csv` | tutte le finestre di osservazione testate, con % di rottura, win rate, Wilson, valore atteso e le due meta' del periodo |
| `<SYM>_orb_setup.csv` | setup completo: esito per numero di conferme (0-3) con il placebo appaiato, e per combinazione di indicatori |
| `<SYM>_orb_regime.csv` | regime di volatilita' e livelli vergini: esito per regime col placebo appaiato, e curva rischio/rendimento spezzata per regime |
| `<SYM>_cci_trade.csv` | uscita dalla banda CCI come ingresso: per periodo e per rapporto rischio/rendimento, con placebo appaiato; piu' la ripartizione per ora |
| `<SYM>_orb_rr.csv` | curva rischio/rendimento della finestra selezionata: per ogni RR, win rate misurato contro il placebo (ingresso a caso, stesso rischio e stesso orizzonte), delta e z |
| `<SYM>_orb_stop.csv` | calibrazione dello stop sulla finestra DICHIARATA da input: moltiplicatore dello stop x scala RR x fascia di larghezza Value Area, con l'aspettativa lorda, il costo espresso in R e il netto |
| `<SYM>_orb_tempi.csv` | quando arriva la rottura: per ora, per giorno x ora (griglia intera), per giorno, e la finestra migliore di ogni giorno della settimana su tutta la griglia. Stesse colonne di controllo del file condizioni |
| `<SYM>_prev_range.csv` | range di IERI rotto OGGI: tre riferimenti fissi (giornata intera, notte 00:00-08:00, pomeriggio 16:00-24:00), scala RR, ampiezza del range D-1, ora della rottura, giorno, e la quota di giornate che si aprono gia' fuori dal range |
| `<SYM>_orb_condizioni.csv` | effetto di ogni filtro sulla rottura, con `perc_risolte`, `target_medio_atr` e il win rate nei due estremi (irrisolto contato come perdita / come vincita): serve a distinguere un gradiente vero da un effetto di troncamento dell'orizzonte |
| `<SYM>_orb_breakout.csv` | una riga per ogni rottura della finestra selezionata: direzione, esito, range, intensita', volatilita', RSI/CCI/Z al momento della rottura, MFE/MAE |
| `<SYM>_report.html` | tutto quanto sopra (tranne lo scan grezzo) in un report navigabile |

## Indicatori: tre timeframe nella stessa passata
`InpIndTF1` / `InpIndTF2` / `InpIndTF3` (default M15, M5, M1) sono i timeframe su
cui vengono calcolati RSI, CCI e Z-Score. Gli istanti osservati e l'esito forward
sono **gli stessi** per tutti e tre: cambia solo la barra su cui l'indicatore
viene letto, sempre l'ultima **chiusa** prima dell'istante.

`InpIndTfMain` (1/2/3) sceglie quale dei tre alimenta condizioni, setup e
classifiche. Gli altri due servono solo al confronto, nella scheda *Indicatori*:
questo evita di mescolare timeframe dentro lo stesso segnale, che a mercato non
sarebbe replicabile.

Come si legge: **non** prendere il timeframe col delta migliore. Scendendo di
timeframe il numero di eventi esplode, ma gli istanti restano gli stessi e
diventano solo piu' correlati: un `n` piu' grande su M1 non e' piu' informazione.
Conta se il **segno del delta** e' lo stesso sui tre, e se le ore buone sono le
stesse. Se cambia segno, non hai tre conferme: hai tre rumori.

`InpIndTfCompare = false` calcola solo il timeframe principale: il confronto su
M1 su periodi storici lunghi allunga sensibilmente il run.

## Range di osservazione e breakout

Due schede del report (`Range e breakout`, `Breakout operativo`) rispondono a una
domanda in due tempi: **dove** si forma l'accumulazione dentro la giornata, e
**cosa** succede quando quel range viene rotto.

**Primo tempo.** Lo script non decide a priori quale sia la fascia buona: prova
ogni combinazione di ora di inizio (`InpOrbFirstHour` -> `InpOrbLastHour`, passo
`InpOrbStartStep`) e durata (`InpOrbDur`, default `1,5,15,30,60,90,120`),
tipicamente qualche centinaio di finestre. Per ognuna costruisce massimo e minimo
**solo con le barre dentro la finestra**, poi aspetta la rottura di un estremo
entro `InpOrbDeadlineMin` minuti.

Le durate sono **minuti di orologio**, non timeframe: non hanno niente a che
vedere con `InpIndTF1/2/3`, che riguardano solo su quale barra vengono letti RSI,
CCI e Z-Score. Massimo e minimo si costruiscono sempre con le barre di
`InpBaseTF`, quindi una durata inferiore alla barra base viene scartata da sola
(su M5 la durata 1 sparisce, su M1 restano tutte).

Occhio a cosa vuol dire una finestra da 1 minuto su base M1: il "range" e' una
singola candela, viene rotta quasi subito e quasi sempre. Non e' accumulazione.
Sta nella lista come termine di paragone - guarda la colonna `range medio ATR`:
se e' una frazione minima di ATR, quella riga descrive rumore, non compressione.
Ogni durata in piu' allunga il run in proporzione: togli quelle che non ti
servono.

**Secondo tempo.** Entrata sul livello rotto, esito a primo tocco entro
`InpScanHorizonMin`.

**L'ancora e' il rischio, non il rendimento.** Lo stop si misura sulla
volatilita' via `InpOrbStopMode`:

- `0` (default): stop = `InpOrbStopMult` x l'ampiezza del range rotto
- `1`: stop = `InpOrbStopAtr` x ATR(D-1)
- `2`: stop al lato opposto del range (l'ORB classico)

Il target sta a `RR` volte quella distanza, e `InpOrbRR` elenca **tutti i
rapporti testati nella stessa passata** (default `0.5,1,2,3,4,5`).
`InpOrbRRMain` sceglie quale alimenta classifica e filtri.

### La curva rischio/rendimento: il test che decide

E' la tabella piu' importante delle due schede. Stessa rottura, stesso stop,
target diversi. In una passeggiata casuale senza deriva la probabilita' di
raggiungere un target grande RR volte lo stop **prima** dello stop vale
esattamente **1/(1+RR)**. Non e' un'approssimazione: e' un teorema.

Quindi un win rate del 33% con target 1:2 non e' una strategia mediocre da
migliorare — e' **esattamente il nulla**. E il 17% con target 1:5 e' lo stesso
identico nulla travestito da numero diverso.

**La formula 1/(1+RR) non e' il riferimento giusto, e sbaglia di parecchio.** La curva
nulla 1/(1+RR) vale per orizzonte **infinito**. Con un orizzonte finito un
target lontano ha bisogno di piu' tempo di uno vicino, quindi ai rapporti alti
le operazioni che avrebbero vinto scadono irrisolte mentre quelle che perdono -
lo stop e' vicino - fanno in tempo a perdere. Il win rate calcolato sulle sole
risolte finisce sotto la curva nulla ai rapporti alti e sopra a quelli bassi:
**una curva decrescente e monotona compare anche in un mercato perfettamente
casuale**. E' un artefatto dell'orologio, non un risultato.

Quanto sbaglia? Simulando una passeggiata casuale con la stessa volatilita' e
lo stesso orizzonte di 240 minuti, il win rate a RR 1:5 scende a **3,9%** contro
il 16,67% della formula. Un mercato del tutto casuale, misurato cosi', sembra
crollare del 12,8% sotto il "nulla teorico". Su questo dataset il valore
osservato a 1:5 e' 9,21%: sotto la formula, ma **sopra** la passeggiata casuale
con lo stesso orologio. Il segno della conclusione si ribalta a seconda del
riferimento che usi.

**Per questo la colonna che conta e' `placebo misurato`** (`InpOrbPlacebo`).
E' la stessa cosa - stessa giornata, stessa finestra, stesso stop, stessi
target, stesso orizzonte - ma con ingresso alla **chiusura della finestra** e
direzione tirata a sorte con una moneta deterministica. Subisce esattamente lo
stesso troncamento, la stessa volatilita' intraday e le stesse code grasse dei
dati veri: nessuna simulazione, nessuna assunzione gaussiana. E' quanto vale
**non avere segnale** in quel momento della giornata.

`delta vs placebo` e' quindi il valore aggiunto della rottura, e il suo `z`
tiene conto dell'incertezza di entrambe le misure.

`InpOrbHorizonMin` resta disponibile (orizzonte del solo breakout, indipendente
da quello della griglia) per verificare che le conclusioni non dipendano dalla
lunghezza della finestra temporale.

Fatto quel controllo, si legge il **segno di delta lungo tutta la colonna**,
mai la riga migliore:

- delta positivo ai rapporti **alti** -> **momentum**: quando parte continua,
  conviene un target lontano
- delta positivo ai rapporti **bassi** (RR < 1) -> **ritorno alla media**:
  il prezzo rientra, conviene incassare subito
- delta che oscilla intorno a zero senza andamento -> il mercato e' una
  **martingala** su questa struttura, e nessun rapporto la salva. Spostare stop
  e target a quel punto e' riarredare, non fare ricerca.

Testare solo rapporti con target maggiore dello stop (1:2, 1:3, 1:4, 1:5)
guarda un lato solo della curva: senza almeno un rapporto sotto 1 non si
distingue "nessuna struttura" da "ritorno alla media". Per questo il default
parte da 0,5.

Un target fisso troppo grande e' l'errore piu' facile e il piu' costoso. Su
EURUSD la massima escursione media nelle quattro ore dopo una rottura vale circa
0,2 ATR: chiedendone 0,5, l'80% delle operazioni resta appeso senza toccare ne'
target ne' stop, il win rate scende sotto il breakeven **per costruzione**, e la
classifica finisce per premiare le finestre in cui non succede mai niente,
perche' contando gli irrisolti a zero chi non risolve mai batte chi perde. Per
questo esiste `InpOrbMinResolved` (default 60%): una finestra che non risolve
almeno quella quota di rotture esce dalla classifica invece di vincerla.

`InpOrbCostPt` sottrae spread e commissioni dal valore atteso, e
`InpOrbMinStopAtr` scarta le finestre il cui stop sarebbe piu' piccolo del costo
di transazione. **Mettici i tuoi numeri reali prima di trarre conclusioni**: su
EURUSD un round trip da 0,7 pip vale circa 0,08 ATR, e su questo dataset il
valore atteso lordo del breakout e' +0,0016 ATR. Il costo e' cinquanta volte il
vantaggio lordo, e nessuna scelta di rapporto cambia quell'ordine di grandezza.
La barra in cui avviene la rottura viene valutata **solo per lo stop, mai per il
target**: dentro una barra l'ordine dei prezzi non e' noto, e assumere che il
target sia arrivato prima gonfierebbe il win rate a gratis. I numeri veri sono
uguali o migliori, mai peggiori.

Le rotture che toccano **entrambi** i livelli nella stessa barra sono contate a
parte come *ambigue* e non entrano nel win rate: non sono operabili.

### Come si legge senza prendere fischi per fiaschi

La classifica **non** e' ordinata sul win rate. E' ordinata su `score` = ATR
attesi ogni 100 giornate, calcolato sul **limite inferiore di Wilson** invece che
sulla percentuale grezza: cosi' un 70% con dodici operazioni finisce sotto un 56%
con duecento, che e' l'ordine giusto.

Tre controlli, in ordine di importanza:

1. **1a meta' / 2a meta'.** Il win rate nelle due meta' del periodo. Se divergono,
   la finestra non e' un edge: e' rumore finito in cima alla lista.
2. **La matrice inizio x durata.** Un effetto vero forma un *altopiano* di celle
   vicine tutte decenti. Un picco isolato circondato da celle mediocri e' fortuna.
3. **% operabili.** La percentuale di rottura e la percentuale di giornate
   realmente operabili sono due cose diverse, e conta la seconda. Il livello
   puo' essere toccato quasi ogni giorno e l'operazione essere impossibile lo
   stesso: i due estremi cadono nella stessa barra e non si sa in che ordine,
   oppure lo stop sarebbe sotto il costo di transazione. Una finestra di cinque
   minuti alle 03:00 ha un range cosi' stretto che lo stop supera il minimo solo
   nelle giornate in cui quella fascia si e' mossa in modo anomalo: misurarla
   li' significa misurare le eccezioni. `InpOrbMinTradePct` (default 80%) la
   tiene fuori dalla classifica.
4. **wlow contro il breakeven richiesto.** Con stop meta' del target servono il
   33,3% per non perdere. Se il limite inferiore di Wilson resta sotto, quel
   segnale non ha dimostrato nulla, per quanto bello sia il win rate grezzo.

### Compressione

La colonna `compress` e' l'ampiezza del range diviso quella attesa da una
passeggiata casuale della stessa durata (ATR x radice del tempo). **Sotto 1 = la
finestra e' stata piu' ferma del normale**, ed e' l'unica definizione di
accumulazione che regge il confronto fra durate diverse: un range di 0,15 ATR
vuol dire cose opposte se si e' formato in 15 minuti o in due ore.

Nella scheda operativa due filtri usano questa misura (`compressione sotto 1` e
`sotto 0,70`). Se il vantaggio compare solo li', il meccanismo e' reale: si opera
la rottura di una compressione, non una rottura qualsiasi.

### Il setup completo: rottura + conferma degli indicatori

E' l'idea per intero, e le tabelle sono **aggiuntive**: nessuna delle altre
sparisce, si leggono tutte insieme.

Range nella finestra -> rottura di un estremo -> conferma dai tre indicatori,
letti sull'ultima barra chiusa **prima** della barra di rottura:

- `InpOrbCciConf` (default 40): CCI oltre soglia nel verso della rottura
- `InpOrbRsiConf` (default 50): RSI oltre soglia nel verso
- `InpOrbZsConf` (default 0): Z-Score oltre soglia nel verso

**Tabella `conferme`**: quanti dei tre erano d'accordo, da 0 a 3. L'idea regge
solo se il win rate **cresce in modo ordinato** da 0 a 3. Un singolo valore alto
in mezzo a valori bassi e' rumore, e con quattro righe capita spesso.

**Le colonne placebo accanto sono la ragione per cui la tabella si puo'
credere.** Contengono lo stesso conteggio di conferme applicato a un ingresso a
caso alla chiusura della finestra, negli stessi giorni. Separano due cose che
altrimenti restano confuse:

- il win rate cresce con le conferme **anche nel placebo** -> il merito e' degli
  indicatori, dicono qualcosa sul mercato in generale e la rottura non c'entra
- cresce **solo** nella colonna reale -> e' la combinazione rottura + conferma a
  valere qualcosa

**Tabella `combinazione`**: quale dei tre ha votato, non solo quanti. Serve a
scoprire se due fanno tutto il lavoro e il terzo e' decorativo - succede spesso,
perche' RSI e Z-Score misurano quasi la stessa cosa e si confermano a vicenda
senza aggiungere informazione. Con otto combinazioni una supera il breakeven per
caso quasi sempre: guarda `wlow`, non `win%`, e diffida di righe sotto le
duecento operazioni.

### Sui filtri, e sul "100% di sicurezza"

Non esiste, e nessun indicatore lo produce. Ogni filtro che alza il win rate lo fa
**riducendo il numero di operazioni**, e oltre un certo punto sta solo selezionando
il rumore che gli e' piaciuto in questo campione. Nella scheda `Breakout operativo`
la colonna che conta e' **delta E** letta insieme a **n**: un filtro serve se
migliora il valore atteso senza ridurre il campione a poche decine di operazioni
in dieci anni. Un segnale filtrato fino al 90% con venti occorrenze non e' forte:
e' morto.

I filtri di intensita' e volatilita' leggono le `InpOrbMomBars` barre **che
precedono** la rottura, mai quella in cui avviene.

### In-sample, dichiarato

Se `InpOrbFixStartMin` resta a -1, la finestra della scheda operativa e' quella
che ha vinto la classifica **sullo stesso campione** su cui viene poi misurata.
E' selezione in-sample e una parte del vantaggio e' fortuna per costruzione: le
colonne sulle due meta' servono a quantificarla. Per un numero onesto, fissa la
finestra con `InpOrbFixStartMin` / `InpOrbFixDurMin` e rilancia su un altro
periodo o un altro simbolo.

`InpDoOrb = false` salta entrambe le schede.

## Regime di volatilita' e livelli vergini

Scheda dedicata, **aggiuntiva**, e nasce da un punto cieco strutturale.

Tutto il resto del report normalizza **per ATR**: range, target, stop,
compressione, escursioni. E' la scelta giusta per confrontare giornate e
simboli diversi, ma ha un prezzo: **cancella il regime**. Dividendo ogni misura
per l'ATR del giorno, una giornata addormentata e una tempesta diventano della
stessa dimensione, e la domanda *"conviene operare quando il mercato e' fermo o
quando corre?"* diventa impossibile da porre.

Qui il regime torna esplicito: l'ATR di ieri messo in percentile sui suoi ultimi
`InpVolLookback` valori (default 100 giornate). Sotto `InpVolLow` = basso, sopra
`InpVolHigh` = alto, sopra `InpVolExtreme` = estremo. Il controllo e' il placebo
**nello stesso regime**, negli stessi giorni.

La terza tabella spezza la **curva rischio/rendimento per regime**: se un target
lontano paga solo con volatilita' alta e uno vicino solo con volatilita' bassa,
non esiste un rapporto giusto - ne esiste uno per regime, e il regime si conosce
in anticipo perche' e' l'ATR di ieri.

**Livello vergine** e' l'altra idea, presa dalla mitigazione del volume profile:
un livello che il prezzo non ha ancora toccato oggi e' intatto, uno gia'
visitato e' consumato. La domanda e' se rompere un estremo mai toccato prima
nella giornata valga piu' che rompere un livello gia' attraversato.

## CCI: l'uscita dalla banda come ingresso

Scheda dedicata, **aggiuntiva**. Fino a qui l'uscita dalla banda `+/-InpCciCross`
era misurata solo come *"dopo, il prezzo si muove di 0,5 ATR?"* - una domanda
sulla volatilita', non su un'operazione. Qui diventa un ingresso vero:

- si aspetta che la barra che esce dalla banda **chiuda**
- si entra all'apertura della prima barra base successiva
- stop `InpCxStopAtr` ATR, target sulla stessa scala `InpOrbRR` (1:0,5 ... 1:5)
- richiesta un'accumulazione di almeno `InpAccMinBars` barre dentro la banda
- tutto ripetuto su **tre timeframe** (`InpIndTF1/2/3`, default M15/M5/M1) e
  **tre periodi** CCI - nove combinazioni, ognuna col proprio controllo

Nessun dato della barra del segnale entra nella decisione, e la barra
d'ingresso conta solo per lo stop, mai per il target.

**Il controllo e' la direzione opposta, non un sorteggio.** Stesso istante,
stesso stop, stessi target, stessa identica finestra di prezzo: cambia solo il
segno. E' il controllo piu' stretto possibile per un'affermazione direzionale,
perche' tutto cio' che non e' la direzione resta costante per costruzione. Una
moneta avrebbe indovinato meta' delle volte e avrebbe dimezzato il vantaggio
misurato; cosi' il `delta` e' il vantaggio direzionale per intero.

Separa due cose che altrimenti restano confuse per sempre: *il CCI sa dove
andra' il prezzo*, oppure *il CCI esce dalla banda quando il mercato si sta
muovendo comunque*? Nel secondo caso il win rate e' alto e il delta e' zero -
l'indicatore dice che sta succedendo qualcosa, cosa che il grafico diceva gia'.

Come per i periodi: **non prendere la riga migliore fra nove combinazioni**.
Guarda se il segno del delta regge scendendo di timeframe e cambiando periodo.
Se cambia, sono nove rumori.

La seconda tabella spezza per ora del segnale sui tre timeframe, col controllo
alla stessa ora: risponde a *"si riesce a capire quando andare a cercare il
setup?"* senza che l'effetto dell'ora si confonda con quello dell'indicatore -
se un'ora e' buona per chiunque, li' non compare.

## Le due letture opposte di RSI e Z-Score

Nella scheda `Breakout operativo` la conferma degli indicatori viene misurata
in **due modi opposti**, in due tabelle affiancate:

- **momentum**: RSI sopra 50 e Z sopra 0 confermano un BUY. Si compra la forza.
- **esaurimento**: RSI sotto `InpRsiLow` e Z sotto `InpZsLow` confermano un BUY.
  Si compra la debolezza. E' la lettura classica di questi due indicatori, che
  misurano estremi.

Il CCI resta direzionale in entrambe, perche' e' il trigger e non il filtro.

Non sono sfumature della stessa idea: su un dato campione al massimo una delle
due puo' avere ragione, e molto probabilmente nessuna. Il placebo appaiato per
numero di conferme dice se la differenza viene dal segnale o dal momento della
giornata.

## Volume Profile

Scheda dedicata, **aggiuntiva**: POC, VAH e VAL del **giorno precedente**
(`InpVpLevels` livelli). Il profilo di ieri e' noto per intero prima che oggi
cominci, quindi e' point-in-time pulito per qualunque istante della giornata.

**Cinque Value Area, non una.** `InpVpVaList` (default `40,50,60,70,80`) misura
ogni condizione a piu' percentuali di volume; `InpVpVaMain` sceglie quale
alimenta le colonne principali e il CSV (default 4 = 70%). L'istogramma si
costruisce una volta sola e poi si espande dal POC cinque volte: il costo
aggiuntivo e' trascurabile.

Non serve a scegliere la percentuale migliore - quello sarebbe overfitting su
una soglia. Serve a vedere **come si muove il risultato mentre la soglia si
muove**. Il ventaglio e' largo apposta: al 40% la Value Area e' il nocciolo
stretto attorno al POC, all'80% copre quasi tutta la giornata. Se una condizione
ha senso, il suo effetto deve variare in modo ordinato - crescere, calare o
restare stabile. Un valore che spicca a una sola percentuale e sparisce alle due
vicine e' rumore che ha trovato la sua soglia, e fuori campione non la
ritrovera'.

**Perche' merita una scheda a se.** Ogni altra cosa misurata in questo report -
range, ATR, RSI, CCI, Z-Score, momentum, compressione - e' una trasformazione
della **stessa serie OHLC**. Sono modi diversi di guardare gli stessi numeri, ed
e' una ragione plausibile per cui tendono a dare tutti la stessa risposta. Il
volume per livello di prezzo e' informazione **diversa**: dice dove si e'
scambiato, non che forma avevano le candele.

Tre tabelle, tutte misurate contro il **placebo** come il resto:

1. **Condizione di Volume Profile** all'ingresso: fuori/dentro la Value Area di
   ieri, livello rotto coincidente con VAH/VAL, rottura in allontanamento dal
   POC, volume della finestra dal lato della rottura. Il placebo si trova nella
   stessa condizione negli stessi giorni: se il win rate e' alto anche li',
   quella condizione descrive un buon momento della giornata e non ha niente a
   che vedere con la rottura.

2. **Larghezza della Value Area** in ATR - la compressione **volumetrica**.
   `compress` misura quanto si e' mosso il prezzo, questa quanto stretto e'
   l'intervallo in cui si e' davvero scambiato. Le due possono divergere: una
   giornata che spazia molto ma scambia tutto in mezzo ha range largo e Value
   Area stretta. **Quando divergono, l'informazione in piu' e' reale** - e' la
   parte che il prezzo da solo non conteneva.

3. **Distanza dal POC di ieri**, col segno della rottura: positivo = ci si
   allontana, negativo = ci si va incontro. E' la domanda operativa vera del
   Volume Profile - il prezzo torna verso il volume o scappa da esso? Se il
   ritorno verso il POC pagasse in modo sistematico, la rottura andrebbe operata
   al contrario di come la si opera d'istinto.

Le stesse misure finiscono per riga in `<SYM>_orb_breakout.csv`.

`InpDoVp = false` salta la scheda e non calcola i profili.

## Normalizzazione cross-simbolo
Le soglie in punti non sono confrontabili tra XAUUSD, US30 ed EURUSD. Ogni
metrica esiste in **punti** e in **multipli di ATR(D-1)**; i bin delle tabelle
condizioni sono in ATR, quindi la stessa condizione ha senso su ogni simbolo.
L'ATR usato per la giornata D e' quello calcolato **fino a D-1** (point-in-time).

## Come leggere le tabelle condizioni
Ogni cella riporta, per ogni soglia:
- `n_<soglia>` numero di successi, `p_<soglia>` probabilita' %,
- `wlow_<soglia>` **limite inferiore di Wilson al 95%**,
- `lift_<soglia>` rapporto con la baseline incondizionata (ultima riga del file).

Nel report HTML questo criterio e' gia' applicato: una cella e' **verde** solo
se `lift > 1.20` **e** Wilson-low sopra la baseline, **rossa** se sotto
baseline, **grigia** in tutti gli altri casi, cioe' quando non e'
distinguibile dal caso. Guarda solo il verde, e verificalo comunque.

Una cella con `p=40%`, baseline 38% e `wlow=31%` non e' un edge: e' rumore.
Si guardano **wlow** e **lift**, mai la probabilita' nuda. Con centinaia di
celle testate il multiple testing e' garantito: alza `InpMinSamples`, pretendi
`lift > 1.20` **e** `wlow > baseline`, e verifica che la stessa cella regga
su un secondo periodo e su un secondo simbolo prima di considerarla reale.

## Input principali
- `InpBaseTF` — TF del percorso intraday, da M1 a H1. M1 = massima precisione
  sull'ora di inizio del movimento; H1 = molto piu' veloce, ora approssimata.
- `InpSymbols` — vuoto = simbolo del grafico, `*` = tutto il Market Watch,
  oppure lista separata da virgola.
- `InpCleanLeg` / `InpMaxRetracePct` — se true il Largest Move e' la gamba
  "pulita" (chiusa quando ritraccia oltre X% del run), invece della massima
  escursione assoluta che al suo interno puo' contenere ore di chop.
- `InpScanStepMin` / `InpScanHorizonMin` / `InpAdverseRatio` — griglia,
  orizzonte forward e rapporto stop/target del first touch.
- `InpThrPoints` / `InpThrATR` — soglie di movimento (max 8 ciascuna).
- `InpUseCalendar` — calendario economico MQL5, filtrato sulle valute del
  simbolo. Se il terminale non lo espone, le colonne news restano a 0.

## Limiti noti
- L'ora di inizio del movimento ha la risoluzione del TF base (M1 -> +/-1 min).
- La decomposizione punti UP/DOWN e' ricostruita dall'OHLC di ogni barra
  (rialzista: open->low->high->close; ribassista: open->high->low->close):
  per costruzione `up - down == close - open`. Su M1 l'errore e' trascurabile,
  su H1 no.
- Il calendario MQL5 copre in genere solo gli anni recenti e non e' identico
  tra broker: le colonne news vanno considerate indicative.
- La giornata e' quella del broker (barra D1 del server), quindi FP Markets =
  GMT+2/+3 con DST. Confrontando simboli o periodi lunghi, tienine conto:
  i bucket M15 slittano di un'ora tra ora solare e ora legale.

## Come si esegue (procedura)
1. Copia lo `.mq5` in `MQL5/Scripts/`, compila con F7 in MetaEditor.
2. Nel terminale, Strumenti > Opzioni > Grafici > **Barre massime nel grafico =
   illimitato**. Apri il grafico del simbolo sul TF base (es. M1) e tieni premuto
   Home finche' la storia non arriva alla data che ti serve.
3. Trascina lo script sul grafico: si apre la finestra **Input** (il TF del
   grafico e' irrilevante, conta solo `InpBaseTF`; il simbolo del grafico conta
   solo se `InpSymbols` e' vuoto).
4. Imposta `InpFrom` / `InpTo` / `InpBaseTF` / `InpSymbols` e conferma.
5. Lo script gira una volta e termina da solo. Segui l'avanzamento nella scheda
   **Esperti**: stampa prima barra disponibile, barre nel periodo, giornate
   analizzate e giornate scartate.
6. Output: File > Apri cartella dati > `MQL5\\Files\\VTRLS_Research\\`.

**Primo run consigliato**: 3 mesi, `InpDoScan=false`. Verifichi che i CSV
abbiano senso, poi rilanci sul periodo pieno con lo scan attivo.

Se la riga "giornate scartate" e' alta, lo storico non e' completo: ripeti il
punto 2 e rilancia (al secondo run i dati sono gia' in cache locale).


## Range di ieri rotto oggi (`InpDoPrev`)

Il modulo ORB costruisce il range e ne opera la rottura nella **stessa**
giornata. Questo modulo fa una cosa diversa: il livello nasce ieri e viene
rotto oggi. Tre riferimenti fissi, nessuno da ottimizzare — giornata intera
D-1, notte D-1 (00:00-08:00), pomeriggio D-1 (16:00-24:00) — e una finestra
operativa di oggi (`InpPrevTradeStart` / `InpPrevTradeEnd`, default 07:00-18:00).

Regola di costruzione, imparata a spese di questo dataset: **lo stop e' una
frazione fissa di ATR(D-1) e il target e' RR volte lo stop**. L'ampiezza del
range di ieri decide *se* operare, mai *quanto e' lontano il bersaglio*.
Legare il target all'ampiezza del range produce un gradiente di win rate che
sembra un edge ed e' solo troncamento dell'orizzonte: i target vicini si
toccano dentro l'orizzonte, quelli lontani no, e la differenza finisce tutta
nella colonna degli irrisolti.

Tre garanzie sul campione:

- si scarta la giornata se la finestra operativa si **apre gia' fuori** dal
  range di ieri (la rottura e' avvenuta altrove, non e' osservabile qui);
  la quota di giornate cosi' scartate e' riportata nella riga `copertura`
- si scarta la barra che tocca **entrambi** gli estremi: e' ambigua
- si scarta la giornata se l'orizzonte non entra nei dati disponibili
- su un gap l'ingresso e' al **peggiore** fra livello e apertura della barra

Il controllo e' la **direzione opposta**: stesso istante, stesso stop, stessi
target, solo il segno cambia. `delta` e `z` confrontano le due.


## L'estremo RECENTE, non simultaneo (`InpOrbExtBars`)

Il test di esaurimento sulla rottura era uscito vuoto: pretendere RSI<30 e
Z<-2 **nello stesso istante** in cui il massimo di un'accumulazione viene
rotto al rialzo e' una contraddizione, e infatti su 4078 rotture solo 7
soddisfacevano due condizioni su tre.

La versione corretta guarda **indietro**: c'e' stato un estremo RSI/Z nelle
ultime `InpOrbExtBars` barre dell'indicatore, prima della rottura? Un mercato
sceso in ipervenduto e poi risalito fino a rompere il massimo del range e'
un evento comune, e non ha niente a che vedere con quello impossibile di
prima. Tre righe nella tabella dei filtri: estremo opposto alla rottura
(esaurimento recente), estremo concorde (spinta recente), nessun estremo.

Insieme arrivano due misure sulla barra chiusa prima della rottura:
l'**ombra** dal lato in cui si romperà (il mercato aveva gia' provato ad
andare li' ed era stato respinto) e il **volume relativo** alla media delle
barre precedenti.


## Forza relativa cross-sectional (`InpDoStrength`)

Tutto il resto dello script guarda **un solo strumento**. Questa e' la prima
misura che porta informazione da fuori: la forza di EUR e quella di USD
ricavate dalle altre coppie del complesso, differenza fra le due, girata nel
verso della rottura.

Tre scelte che la distinguono dagli indicatori di currency strength in
circolazione, e sono la ragione per cui vale la pena misurarla:

1. **Rendimenti, non differenze di prezzo.** Sommare `close-open` di EURUSD,
   EURGBP e EURJPY produce una media pesata i cui pesi sono la convenzione di
   quotazione: EURJPY pesa cento volte EURUSD. Dividere le coppie JPY per 100
   e' una toppa; il rendimento elimina il problema alla radice.
2. **Leave-one-out.** La coppia che si opera e' esclusa da entrambe le gambe.
   Senza, circa il 29% del differenziale EUR-USD e' il rendimento di EURUSD
   stesso, e si finirebbe a rimisurare il momentum del simbolo - la cosa che
   in questo dataset ha gia' fallito trenta volte.
3. **Segno dedotto dal nome della coppia**, non da tabelle scritte a mano: la
   valuta base prende +1, quella quotata -1.

Letta all'ultima barra **chiusa** di `InpStrTF` prima della rottura. Sui
metalli non esiste una gamba XAU: si usa la forza del dollaro col segno
girato. Quattro righe nella tabella dei filtri (concorde forte, concorde,
contraria, contraria forte) e una colonna in `_orb_breakout.csv`.
