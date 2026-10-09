//+------------------------------------------------------------------+
//|                                       MultiDayRangeBreakout.mq5 |
//|  v3.00                                                           |
//|                                                                  |
//|  COSA FA                                                         |
//|  Calcola un RANGE (massimo e minimo di un periodo) e, dentro la |
//|  FINESTRA DI ENTRATA, entra in breakout: long se il prezzo esce  |
//|  sopra il massimo, short se esce sotto il minimo. Livelli di     |
//|  breakout: massimo + offset (alto) e minimo - offset (basso).    |
//|                                                                  |
//|  Convenzioni: tutti gli orari sono ORA SERVER del broker (quella |
//|  di TimeCurrent), non GMT e non ora locale. Tutte le distanze    |
//|  (range, offset, SL, TP, break even, trailing, spread) sono in   |
//|  PUNTI del simbolo: su un cambio a 5 cifre 10 punti = 1 pip.     |
//|                                                                  |
//|  ORDINE DEGLI INPUT (gli stessi gruppi della finestra Parametri) |
//|   0  modo (reale / analisi virtuale) e volume                    |
//|   1A quale range usare (interruttori true/false)                 |
//|   1B time frame osservato e giorno di riferimento                |
//|   1C range per ORARIO    1D range a BARRE    1E range D1         |
//|   1F filtro di larghezza del range                               |
//|   2  finestra di entrata e massimo di trade al giorno            |
//|   3  modalita' di entrata (interruttori true/false)              |
//|   4  uscite: stop loss, take profit, break even, trailing        |
//|   5  filtro di spread                                            |
//|   6  parametri dell'analisi virtuale                             |
//|   7  sistema                                                     |
//|                                                                  |
//|  1. RANGE (gruppi 1A-1F)                                         |
//|   Per orario  massimo/minimo di una fascia oraria (es. 00-08)    |
//|               del giorno di riferimento, calcolato sulle barre   |
//|               di Timeframe.                                      |
//|   A barre     massimo/minimo delle ultime N barre di Timeframe.  |
//|   D1 prec.    massimo/minimo degli ultimi N giorni D1 completi.  |
//|   Giorno di riferimento (RangeDaysBack) = N-esimo giorno di      |
//|   mercato prima di oggi, contato con le barre D1: il lunedi'     |
//|   1 = venerdi'. 0 = oggi. Il range e' calcolato una volta per    |
//|   giorno di calendario server, al primo tick utile della         |
//|   finestra di entrata (mai fuori finestra). A mezzanotte tutto   |
//|   si azzera: se la finestra passa la mezzanotte il range viene   |
//|   ricalcolato col nuovo giorno di riferimento.                   |
//|   Il filtro di larghezza (1F) scarta il range fuori da Min/Max.  |
//|                                                                  |
//|  2. FINESTRA DI ENTRATA (gruppo 2)                               |
//|   Gli ordini stop si piazzano solo dentro la finestra (fine      |
//|   esclusa) e vivono fino a fine finestra + ExpireExtraMinutes.   |
//|   Retest e chiusura di candela valgono fino a fine finestra +    |
//|   ExpireExtraMinutes (la candela che chiude esattamente a fine   |
//|   finestra vale e l'ingresso scatta al primo tick dopo; una      |
//|   candela che chiude a mezzanotte no). MaxTradesPerDay limita le |
//|   posizioni aperte in un giorno server (riparte a mezzanotte):   |
//|   EA reale = un solo conteggio per tutte le modalita' (vince la  |
//|   prima che scatta, una posizione per volta); analisi virtuale = |
//|   un conteggio per concorrente.                                  |
//|                                                                  |
//|  3. MODALITA' DI ENTRATA (gruppo 3), anche piu' di una insieme:  |
//|   vince la prima che scatta e ne parte una sola per volta.       |
//|   EntryStop         coppia di ordini stop: BuyStop sul livello   |
//|                     alto, SellStop sul basso. Quando uno scatta  |
//|                     l'altro e' cancellato (OCO); gli ordini non  |
//|                     eseguiti scadono a fine finestra +           |
//|                     ExpireExtraMinutes.                          |
//|   EntryCandleClose  a mercato quando una candela CHIUSA di       |
//|                     Timeframe chiude oltre il livello alto       |
//|                     (long) o sotto il basso (short).             |
//|   EntryRetest       a mercato quando, dopo una rottura, il       |
//|                     prezzo TORNA al bordo del range (retest),    |
//|                     nella direzione della rottura.               |
//|  Se accesi, prima di piazzare gli ordini stop o di entrare a     |
//|  mercato valgono il filtro di spread (gruppo 5: non controlla    |
//|  gli stop gia' piazzati) e quello di larghezza del range (1F).   |
//|                                                                  |
//|  4. USCITE (gruppo 4): stop loss e take profit in punti dal      |
//|   prezzo dell'ordine (stop) o dalla quotazione all'invio         |
//|   (ingressi a mercato); break even e trailing stop opzionali.    |
//|                                                                  |
//|  ANALISI VIRTUALE (SlotScan = true, gruppi 0 e 6)                |
//|   L'EA NON apre ordini. Simula in parallelo e in modo            |
//|   indipendente tanti "concorrenti" = un range x una modalita' di |
//|   entrata, con le stesse regole dell'EA reale (finestra, filtri, |
//|   SL/TP, break even, trailing). Range in gara: le fasce orarie   |
//|   Slot1..Slot12 (se UseRangeTime), il range a barre (se          |
//|   UseRangeBars), il range D1 (se UseRangePrevD1). A fine test    |
//|   scrive la classifica nel log degli Esperti e due file CSV in   |
//|   Terminal\Common\Files (sovrascritti a ogni esecuzione; nelle   |
//|   ottimizzazioni non scrive nulla: conta solo il valore dato a   |
//|   OnTester). Il risultato di ogni trade e' in R (multipli dello  |
//|   stop loss). La classifica usa TUTTI i trade del periodo;       |
//|   SlotSplitDate mostra solo prima/dopo. Con tanti concorrenti il |
//|   migliore e' in parte fortuna: confermalo rifacendo il test su  |
//|   un altro periodo.                                              |
//+------------------------------------------------------------------+
#property copyright "MultiDayRangeBreakout"
#property version   "3.00"
#property description "Breakout di un range: ordini stop OCO, chiusura di candela o retest. Analisi virtuale delle fasce orarie."

#include <Trade\Trade.mqh>

enum ENUM_SLOT_RANK
  {
   SLOT_RANK_TSTAT       = 0,   // t-stat dell'E[R] (tiene conto di quanti trade)
   SLOT_RANK_EXPECTANCY  = 1,   // E[R] medio per trade
   SLOT_RANK_PF          = 2,   // profit factor
   SLOT_RANK_TOTAL       = 3    // R totale
  };

//==================================================================
// 0. MODO DI FUNZIONAMENTO E VOLUME
//==================================================================
input group "=== 0. MODO E VOLUME ==="
input bool SlotScan = false;                       // MODO. false = EA REALE: apre ordini veri sul conto. true = ANALISI VIRTUALE: NESSUN ordine, simula in parallelo tutti i range e le modalita' di entrata accesi e scrive la classifica (parametri nel gruppo 6)
input double LotSize = 0.01;                       // VOLUME di ogni operazione reale, in lotti (> 0; arrotondato per DIFETTO al passo del simbolo e limitato al massimo; se e' sotto il minimo del simbolo l'EA non parte). Nell'analisi virtuale non viene usato (il risultato e' in multipli dello stop loss) ma deve comunque essere valido

//==================================================================
// 1. RANGE
//==================================================================
input group "=== 1A. QUALE RANGE USARE (interruttori true/false) ==="
// EA REALE (SlotScan = false): accendine ESATTAMENTE UNO, l'EA rifiuta 0 o piu' di uno.
// ANALISI VIRTUALE (SlotScan = true): puoi accenderne piu' di uno, entrano tutti in classifica.
input bool UseRangeTime = false;                   // RANGE PER ORARIO. true = usa il massimo/minimo di una fascia oraria. EA reale: la fascia RangeHourStart-RangeHourEnd (gruppo 1C). Analisi virtuale: le fasce Slot1..Slot12 (gruppo 1C). Usa anche i parametri 1B
input bool UseRangeBars = true;                    // RANGE A BARRE. true = usa il massimo/minimo delle ultime RangeBarsLookback barre di Timeframe (gruppo 1D). Usa anche i parametri 1B
input bool UseRangePrevD1 = false;                 // RANGE D1 PRECEDENTI. true = usa il massimo/minimo degli ultimi RangeDaySpan giorni D1 completi (gruppo 1E). Richiede RangeDaysBack >= 1 (gruppo 1B)

input group "=== 1B. TIME FRAME E GIORNO DI RIFERIMENTO (comuni ai range) ==="
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;  // TIME FRAME OSSERVATO. Le sue barre formano il range per orario e il range a barre; le sue candele chiuse servono a EntryCandleClose. Nel range per orario conta ogni barra che APRE dentro la fascia (inizio incluso, fine esclusa) ed e' presa intera con il suo massimo/minimo: la fascia e' esatta solo se inizio e fine coincidono con aperture di barra (M1 sempre; con H1 solo a minuto 00), altrimenti il range perde prezzi dentro la fascia o include prezzi fuori. Il range D1 non lo usa. PERIOD_CURRENT = il time frame del grafico
input int RangeDaysBack = 1;                       // GIORNO DI RIFERIMENTO del range, in giorni di mercato (barre D1) prima di oggi: 1 = ultimo giorno di mercato (il lunedi' guarda il venerdi'), 2 = il giorno di mercato prima ancora. Per orario e' il giorno in cui INIZIA la fascia; a barre il range finisce con l'ultima barra di quel giorno; D1 e' il giorno piu' recente incluso. 0 = oggi: NON ammesso con il range D1; a barre sono le ultime barre chiuse al primo tick della finestra di entrata (possono includere ieri); per orario la fascia deve finire prima della fine della finestra di entrata (se finisce durante, l'EA aspetta), altrimenti quel giorno non si entra

input group "=== 1C. RANGE PER ORARIO (usato se UseRangeTime = true) ==="
input int RangeHourStart = 16;                     // EA REALE - ORA di inizio della fascia, 0-23 (ora server)
input int RangeMinuteStart = 0;                    // EA REALE - MINUTO di inizio della fascia, 0-59
input int RangeHourEnd = 0;                        // EA REALE - ORA di fine della fascia, 0-24. Se la fine e' uguale o precedente all'inizio la fascia passa la mezzanotte (0 con minuto 0 = mezzanotte)
input int RangeMinuteEnd = 0;                      // EA REALE - MINUTO di fine della fascia, 0-59
input int SlotFirstHour = 0;                       // ANALISI VIRTUALE - ORA di inizio della fascia 1, 0-23 (ora server). Ogni fascia successiva parte dove finisce la precedente
input int SlotLenHours = 2;                        // ANALISI VIRTUALE - DURATA di ogni fascia in ore, 1-12. Con 2 e inizio 0: 00-02, 02-04 ... 22-24. Se una fascia coincide con una precedente (succede con durata 3, 4, 6, 8, 9 o 12) viene spenta anche se quella precedente e' disattivata: quell'orario resta analizzato solo dalla prima
input bool Slot1 = true;                           // ANALISI VIRTUALE - fascia 1 attiva (con i valori di default 00-02; in generale parte a SlotFirstHour e dura SlotLenHours ore)
input bool Slot2 = true;                           // ANALISI VIRTUALE - fascia 2 attiva (con i valori di default 02-04; in generale parte dove finisce la fascia 1 e dura SlotLenHours ore)
input bool Slot3 = true;                           // ANALISI VIRTUALE - fascia 3 attiva (con i valori di default 04-06; in generale parte dove finisce la fascia 2 e dura SlotLenHours ore)
input bool Slot4 = true;                           // ANALISI VIRTUALE - fascia 4 attiva (con i valori di default 06-08; in generale parte dove finisce la fascia 3 e dura SlotLenHours ore)
input bool Slot5 = true;                           // ANALISI VIRTUALE - fascia 5 attiva (con i valori di default 08-10; in generale parte dove finisce la fascia 4 e dura SlotLenHours ore)
input bool Slot6 = true;                           // ANALISI VIRTUALE - fascia 6 attiva (con i valori di default 10-12; in generale parte dove finisce la fascia 5 e dura SlotLenHours ore)
input bool Slot7 = true;                           // ANALISI VIRTUALE - fascia 7 attiva (con i valori di default 12-14; in generale parte dove finisce la fascia 6 e dura SlotLenHours ore)
input bool Slot8 = true;                           // ANALISI VIRTUALE - fascia 8 attiva (con i valori di default 14-16; in generale parte dove finisce la fascia 7 e dura SlotLenHours ore)
input bool Slot9 = true;                           // ANALISI VIRTUALE - fascia 9 attiva (con i valori di default 16-18; in generale parte dove finisce la fascia 8 e dura SlotLenHours ore)
input bool Slot10 = true;                          // ANALISI VIRTUALE - fascia 10 attiva (con i valori di default 18-20; in generale parte dove finisce la fascia 9 e dura SlotLenHours ore)
input bool Slot11 = true;                          // ANALISI VIRTUALE - fascia 11 attiva (con i valori di default 20-22; in generale parte dove finisce la fascia 10 e dura SlotLenHours ore)
input bool Slot12 = true;                          // ANALISI VIRTUALE - fascia 12 attiva (con i valori di default 22-24; in generale parte dove finisce la fascia 11 e dura SlotLenHours ore)

input group "=== 1D. RANGE A BARRE (usato se UseRangeBars = true) ==="
input int RangeBarsLookback = 25;                  // NUMERO DI BARRE di Timeframe che formano il range (>= 1). Con RangeDaysBack >= 1 sono le ultime barre fino alla fine del giorno di riferimento (RangeDaysBack = 1: fino alla mezzanotte di oggi); con RangeDaysBack = 0 sono le ultime barre chiuse al primo tick della finestra di entrata

input group "=== 1E. RANGE D1 PRECEDENTI (usato se UseRangePrevD1 = true) ==="
input int RangeDaySpan = 1;                        // QUANTI GIORNI D1 completi (>= 1) formano il range, dal giorno di riferimento andando indietro. Con RangeDaysBack = 1: 1 = solo ieri, 3 = gli ultimi 3 giorni di mercato

input group "=== 1F. FILTRO DI LARGHEZZA DEL RANGE (vale per tutti i range) ==="
input bool RequireRangeConfirmation = true;        // true = scarta il range (niente trade quel giorno) se la sua larghezza e' fuori da Min/Max. false = nessun filtro di larghezza
input double MinRangePoints = 50;                  // LARGHEZZA MINIMA del range in punti (solo con il filtro acceso)
input double MaxRangePoints = 500;                 // LARGHEZZA MASSIMA del range in punti, misurata tra massimo e minimo del range (offset escluso); un range piu' largo viene scartato (solo con il filtro acceso; deve essere >= alla minima; 0 NON vuol dire nessun limite: scarta tutti i range)

//==================================================================
// 2. FINESTRA DI ENTRATA
//==================================================================
input group "=== 2. FINESTRA DI ENTRATA (ora server) E LIMITI GIORNALIERI ==="
input int TradeHourStart = 10;                     // ORA di inizio della finestra di entrata, 0-23
input int TradeMinuteStart = 0;                    // MINUTO di inizio della finestra di entrata, 0-59
input int TradeHourEnd = 11;                       // ORA di fine della finestra, 0-24 (la fine e' esclusa). Fine uguale all'inizio, o 00:00-24:00, NON e' ammesso (la finestra deve durare meno di 24 ore). Se la fine e' prima dell'inizio la finestra passa la mezzanotte; a mezzanotte il giorno riparte: il range si ricalcola, MaxTradesPerDay riparte da zero e con EntryCandleClose la candela che chiude alle 00:00 non vale
input int TradeMinuteEnd = 0;                      // MINUTO di fine della finestra, 0-59
input int ExpireExtraMinutes = 0;                  // MINUTI EXTRA dopo la fine della finestra (>= 0; finestra + extra sotto le 24 ore). Gli ordini stop gia' piazzati restano vivi fino a fine finestra + extra; retest e chiusura di candela restano validi (conta la candela che chiude entro quel limite, estremo compreso). NON si piazzano nuovi ordini stop dopo la fine della finestra. Vale anche nell'analisi virtuale
input int MaxTradesPerDay = 1;                     // MASSIMO DI APERTURE di posizioni in un giorno server (>= 1): conta anche le posizioni gia' chiuse e riparte da 0 a mezzanotte. EA reale: un solo conteggio per tutte le modalita' di entrata insieme e una sola posizione alla volta; analisi virtuale: il limite vale separatamente per ogni concorrente

//==================================================================
// 3. MODALITA' DI ENTRATA
//==================================================================
input group "=== 3. MODALITA' DI ENTRATA (interruttori true/false) ==="
input int PendingOrderOffsetPoints = 20;           // OFFSET in punti dal range, comune alle tre modalita': livello alto = massimo + offset, livello basso = minimo - offset. Stop: prezzo degli ordini. Chiusura di candela: la candela deve chiudere oltre il livello. Retest: la rottura scatta quando il prezzo supera il livello
input bool EntryStop = true;                       // A) ORDINI STOP. true = piazza BuyStop sul livello alto e SellStop sul basso, una sola volta e solo dentro la finestra (OCO: quando uno scatta l'altro e' cancellato); gli ordini non eseguiti scadono a fine finestra + ExpireExtraMinutes (con 0 extra: a fine finestra)
input bool ChaseIfBroken = false;                  // A) solo con EntryStop: PREZZO GIA' OLTRE UN LIVELLO (o piu' vicino della distanza minima degli stop del broker) nel momento in cui si piazza la coppia, di norma all'apertura della finestra. false = aspetta che il prezzo rientri; se non rientra prima della fine della finestra non piazza nulla. true = piazza subito lo stop del lato rotto vicino al mercato (BuyStop a ask + distanza minima + 10 punti, SellStop a bid - distanza minima - 10 punti, SL/TP dal nuovo prezzo); l'altro lato resta al suo livello se e' piazzabile. Rincorre il movimento gia' partito: NON e' un retest
input bool EntryCandleClose = false;               // B) CHIUSURA DI CANDELA. true = entra a mercato, al primo tick dopo la chiusura, quando una candela chiusa di Timeframe chiude oltre il livello alto (long) o sotto il basso (short). Conta solo la candela che chiude dopo l'inizio e al piu' alla fine della finestra (+ ExpireExtraMinutes); una candela che chiude a mezzanotte (00:00) non conta mai, quindi con fine finestra 24:00 l'ultima candela e' esclusa
input bool EntryRetest = false;                    // C) RETEST. true = dopo che il prezzo (bid) supera il livello, entra a mercato quando TORNA al bordo del range, nella direzione della rottura
input int RetestTolerancePoints = 0;               // C) TOLLERANZA del ritorno in punti: il retest scatta quando il bid scende fino a questa distanza SOPRA il bordo (long; simmetrico per lo short). 0 = deve toccarlo. Deve essere minore dell'offset
input int RetestMaxDepthPoints = 50;               // C) PROFONDITA' MASSIMA in punti, misurata dal BORDO del range verso l'interno (dal massimo per il long, dal minimo per lo short): se il bid scende sotto massimo - profondita' (simmetrico per lo short) la rottura e' fallita e il retest armato si annulla. Se poi il prezzo supera di nuovo il livello (offset) il retest si riarma e puo' ancora entrare nella stessa finestra. 0 NON vuol dire nessun limite: il prezzo non deve mai oltrepassare il bordo

//==================================================================
// 4. USCITE
//==================================================================
input group "=== 4A. STOP LOSS E TAKE PROFIT (in punti) ==="
input double StopLossPoints = 100;                 // STOP LOSS iniziale in punti (> 0). Con gli ordini stop e' misurato dal prezzo dell'ordine; con gli ingressi a mercato (candela, retest) dall'ask/bid al momento dell'invio. Il livello e' fisso: con gap o slippage la perdita reale puo' superare questa distanza. Misura anche l'unita' R dell'analisi virtuale
input bool UseTakeProfit = true;                   // true = imposta il take profit; false = nessun TP (restano lo stop loss, il break even e il trailing)
input double TakeProfitPoints = 200;               // TAKE PROFIT in punti, misurato dalla stessa base dello stop loss (non dal prezzo realmente eseguito); ignorato se UseTakeProfit = false, altrimenti deve essere > 0

input group "=== 4B. BREAK EVEN ==="
input bool UsaBreakEven = true;                    // true = quando il profitto raggiunge BreakEvenAttivazione sposta lo stop loss sull'entrata piu' BreakEvenOffset
input int BreakEvenAttivazione = 100;              // PROFITTO in punti che attiva il break even
input int BreakEvenOffset = 10;                    // PUNTI oltre il prezzo di entrata a cui viene portato lo stop loss (copre spread e costi)

input group "=== 4C. TRAILING STOP ==="
input bool UsaTrailingStop = true;                 // true = quando il profitto raggiunge TrailingStartProfit lo stop loss segue il prezzo
input int TrailingStartProfit = 150;               // PROFITTO in punti da cui parte il trailing
input int TrailingStep = 20;                       // PASSO MINIMO in punti: lo stop loss si sposta solo se migliora di almeno questo valore
input int TrailingOffset = 30;                     // DISTANZA in punti a cui viene portato lo stop loss rispetto al prezzo corrente (bid per i long, ask per gli short) quando si sposta. Lo SL si muove solo ogni TrailingStep punti, quindi tra due spostamenti la distanza reale sale fino a circa offset + passo. Se e' minore della distanza minima del broker vale quella. Con il break even acceso vale lo stop piu' favorevole dei due

//==================================================================
// 5. FILTRO DI SPREAD
//==================================================================
input group "=== 5. FILTRO DI SPREAD (controllo prima di aprire) ==="
input double MaxSpreadPoints = 0;                  // SPREAD MASSIMO in punti, controllato solo nel momento in cui l'EA piazza la coppia di ordini stop o invia un ingresso a mercato (chiusura di candela, retest): se e' piu' alto aspetta e riprova a ogni tick finche' puo'. Gli stop gia' piazzati NON sono piu' controllati e scattano anche con spread alto. 0 = filtro spento
input double MaxSpreadPctOfSL = 15;                // SPREAD MASSIMO in % dello stop loss (stesso controllo di MaxSpreadPoints): limite = StopLossPoints x % / 100, es. 15 con SL 100 = 15 punti. 0 = filtro spento. Se sono accesi entrambi vale il limite piu' stretto

//==================================================================
// 6. ANALISI VIRTUALE (usati solo con SlotScan = true)
//==================================================================
input group "=== 6. ANALISI VIRTUALE: classifica e file (solo con SlotScan = true) ==="
input int SlotMinTrades = 30;                      // TRADE MINIMI (>= 1) perche' un concorrente entri in classifica; gli altri sono elencati in coda come "fuori classifica"
input ENUM_SLOT_RANK SlotRankBy = SLOT_RANK_TSTAT; // CRITERIO della classifica, sui trade virtuali (R = multipli dello stop loss): t-stat = E[R] medio diviso la sua incertezza statistica, premia risultato buono E molti trade (consigliato; vale 0 con meno di 2 trade o se tutti i trade hanno lo stesso R); E[R] medio per trade; profit factor (nel punteggio al massimo 10: sopra si pareggia); R totale. Il punteggio del primo in classifica e' anche il valore dato al tester per l'ottimizzazione "Custom max" (-1e9 se nessuno raggiunge SlotMinTrades)
input datetime SlotSplitDate = 0;                  // DATA DI SEPARAZIONE (ora server). Se > 0 il log e i CSV mostrano per ogni concorrente anche numero di trade ed E[R] di quelli aperti prima e da questa data in poi, per confrontare i due periodi. Classifica, SlotMinTrades e punteggio del tester usano SEMPRE tutti i trade: non e' un vero fuori campione, per quello rifai il test su un altro periodo. 0 = nessuna separazione
input double SlotCommissionPoints = 0.0;           // COMMISSIONE round-turn in punti sottratta a ogni trade virtuale. 0 = commissioni escluse (lo spread e' sempre incluso)
input bool SlotWriteFiles = true;                  // true = a fine test scrive in Terminal\Common\Files, sovrascrivendoli a ogni esecuzione, la classifica di tutti i concorrenti (MDRB_SlotScan_<simbolo>.csv, colonna eligible: 0 = fuori classifica) e tutti i trade virtuali (MDRB_SlotScan_<simbolo>_trades.csv). false = nessun file, resta la classifica nel log degli Esperti. In ottimizzazione non viene scritto nulla (ne' file ne' log): conta solo il valore dato al tester

//==================================================================
// 7. SISTEMA
//==================================================================
input group "=== 7. SISTEMA ==="
input int Slippage = 10;                           // SLIPPAGE massimo in punti accettato negli ordini a mercato (chiusura di candela, retest)
input int MagicNumber = 123456;                    // NUMERO MAGICO: identifica gli ordini e le posizioni di questo EA (cambialo se ne usi piu' di uno sullo stesso simbolo)
input string OrderComment = "MDRB3";               // COMMENTO (prefisso) scritto su ordini e posizioni reali: l'EA vi aggiunge " B"/" S" (ordini stop) o " chiusura"/" retest" (ingressi a mercato); il broker puo' troncarlo. E' solo un'etichetta: le operazioni sono riconosciute dal MagicNumber, non dal commento. Ignorato nell'analisi virtuale
input bool ShowPanel = true;                       // true = mostra il pannello di stato sul grafico (non nel tester senza modo visuale)
input bool ShowRangeLines = true;                  // true = disegna due linee orizzontali tratteggiate: massimo (blu) e minimo (rosso) del range di oggi, SENZA offset (non sono i livelli di entrata, che distano PendingOrderOffsetPoints). Compaiono quando il range viene calcolato, spariscono a mezzanotte o se il range e' scartato. Solo EA reale: nell'analisi virtuale non disegna nulla

//--- stato
CTrade   g_trade;
datetime g_day = 0;           // giorno server corrente (mezzanotte)
bool     g_rangeDone = false; // il range di oggi e' stato calcolato (valido o no)
bool     g_rangeOK = false;
double   g_upper = 0.0;
double   g_lower = 0.0;
string   g_rangeInfo = "";
int      g_pairsToday = 0;    // coppie di ordini piazzate oggi
int      g_tradesToday = 0;   // posizioni aperte oggi
int      g_nPos = -1;         // nostre posizioni (-1 = da leggere)
int      g_nOrd = -1;         // nostri ordini pendenti
datetime g_nextTry = 0;
datetime g_nextMod = 0;
datetime g_nextTryM = 0;       // pausa dopo un errore su un ingresso a mercato
datetime g_barTime = 0;        // apertura della barra corrente di Timeframe (serve a riconoscere la chiusura di una candela)
bool     g_armL = false;       // retest: il prezzo ha superato il livello superiore
bool     g_armS = false;       // retest: il prezzo ha superato il livello inferiore
bool     g_candlePend = false; // chiusura di candela: la candela appena chiusa va ancora valutata/ritentata (fino a fine barra)
int      g_failToday = 0;
bool     g_logOutside = false;
bool     g_logSpread = false;
bool     g_logWait = false;
datetime g_lastPanel = 0;
string   g_status = "";

//+------------------------------------------------------------------+
//| Utilita'                                                         |
//+------------------------------------------------------------------+
datetime DayStart(datetime t) { return t - (t % 86400); }

int MinuteOfDay(datetime t) { return (int)((t % 86400) / 60); }

double TickSize()
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0)
      ts = _Point;
   return ts;
  }

double NormPrice(double p)
  {
   double ts = TickSize();
   return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
  }

int VolumeDigits(double step)
  {
   int d = 0;
   double s = step;
   while(d < 8 && MathAbs(s - MathRound(s)) > 1e-9)
     {
      s *= 10.0;
      d++;
     }
   return d;
  }

double NormVol(double v)
  {
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(st <= 0.0)
      st = (mn > 0.0 ? mn : 0.01);
   v = MathFloor(v / st + 1e-9) * st;
   if(mx > 0.0 && v > mx)
      v = mx;
   if(v < mn)
      return 0.0;
   return NormalizeDouble(v, VolumeDigits(st));
  }

bool TradeOK()
  {
   uint rc = g_trade.ResultRetcode();
   return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED);
  }

bool TradingAllowed()
  {
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return false;
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Finestra di entrata (minuti del giorno server)                   |
//+------------------------------------------------------------------+
int WinStartMin() { return TradeHourStart * 60 + TradeMinuteStart; }
int WinEndMin() { return TradeHourEnd * 60 + TradeMinuteEnd; }
int WinLen() { return (WinEndMin() - WinStartMin() + 1440) % 1440; }
int WinOffset(datetime t) { return (MinuteOfDay(t) - WinStartMin() + 1440) % 1440; }

bool InEntryWindow(datetime t) { return WinOffset(t) < WinLen(); }

bool OrdersMayLive(datetime t) { return WinOffset(t) < WinLen() + ExpireExtraMinutes; }

datetime OrdersExpiry(datetime t)
  {
   int remain = WinLen() + ExpireExtraMinutes - WinOffset(t);
   return (t - (t % 60)) + (datetime)remain * 60;
  }

//+------------------------------------------------------------------+
//| I nostri ordini e le nostre posizioni (simbolo + magic)          |
//+------------------------------------------------------------------+
int CountOurPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;
      n++;
     }
   return n;
  }

void ScanOurOrders(int &buys, int &sells)
  {
   buys = 0;
   sells = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)MagicNumber)
         continue;
      long ty = OrderGetInteger(ORDER_TYPE);
      if(ty == ORDER_TYPE_BUY_STOP)
         buys++;
      else
         if(ty == ORDER_TYPE_SELL_STOP)
            sells++;
     }
  }

int CountOurPendings()
  {
   int b = 0, s = 0;
   ScanOurOrders(b, s);
   return b + s;
  }

void DeleteOurPendings(const string why)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != (long)MagicNumber)
         continue;
      long ty = OrderGetInteger(ORDER_TYPE);
      if(ty != ORDER_TYPE_BUY_STOP && ty != ORDER_TYPE_SELL_STOP)
         continue;
      if(g_trade.OrderDelete(tk) && TradeOK())
         Print("Ordine ", tk, " cancellato (", why, ")");
      else
         Print("Errore cancellazione ordine ", tk, ": ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
     }
   g_nOrd = CountOurPendings();
  }

//+------------------------------------------------------------------+
//| Contatori del giorno: si rileggono dalla storia quando cambia il |
//| numero di ordini o di posizioni (regge al riavvio dell'EA)       |
//+------------------------------------------------------------------+
void RefreshFromHistory(datetime now)
  {
   int entries = 0, hb = 0, hs = 0;
   if(HistorySelect(g_day, now + 86400))
     {
      int nd = HistoryDealsTotal();
      for(int i = 0; i < nd; i++)
        {
         ulong dk = HistoryDealGetTicket(i);
         if(dk == 0)
            continue;
         if(HistoryDealGetString(dk, DEAL_SYMBOL) != _Symbol)
            continue;
         if(HistoryDealGetInteger(dk, DEAL_MAGIC) != (long)MagicNumber)
            continue;
         if(HistoryDealGetInteger(dk, DEAL_ENTRY) == DEAL_ENTRY_IN)
            entries++;
        }
      int no = HistoryOrdersTotal();
      for(int i = 0; i < no; i++)
        {
         ulong ok = HistoryOrderGetTicket(i);
         if(ok == 0)
            continue;
         if(HistoryOrderGetString(ok, ORDER_SYMBOL) != _Symbol)
            continue;
         if(HistoryOrderGetInteger(ok, ORDER_MAGIC) != (long)MagicNumber)
            continue;
         long ty = HistoryOrderGetInteger(ok, ORDER_TYPE);
         if(ty == ORDER_TYPE_BUY_STOP)
            hb++;
         else
            if(ty == ORDER_TYPE_SELL_STOP)
               hs++;
        }
     }
   int cb = 0, cs = 0;
   ScanOurOrders(cb, cs);
   g_tradesToday = MathMax(g_tradesToday, entries);
   g_pairsToday = MathMax(g_pairsToday, MathMax(MathMax(hb, hs), MathMax(cb, cs)));
   if(g_pairsToday < g_tradesToday)
      g_pairsToday = g_tradesToday;
  }

void SyncCounters(datetime now)
  {
   int np = CountOurPositions();
   int no = CountOurPendings();
   bool changed = (np != g_nPos || no != g_nOrd);
   if(g_nPos >= 0 && np > g_nPos)
      g_tradesToday += np - g_nPos;
   g_nPos = np;
   g_nOrd = no;
   if(changed)
      RefreshFromHistory(now);
  }

//+------------------------------------------------------------------+
//| Range                                                            |
//| ritorna 1 = valido, 0 = scartato per oggi, -1 = dati non pronti  |
//+------------------------------------------------------------------+
// finestra oraria (hS:mS - hE:mE) nel giorno di riferimento RangeDaysBack.
// ritorna 1 = massimo/minimo calcolati, 0 = nessuna barra nella finestra, -1 = non pronto
int RangeTimeWindow(datetime now, int hS, int mS, int hE, int mE, double &hi, double &lo, string &info)
  {
   hi = -DBL_MAX;
   lo = DBL_MAX;
   info = "";
   datetime dayStart = iTime(_Symbol, PERIOD_D1, RangeDaysBack);
   if(dayStart == 0)
      return -1;
   datetime ws = dayStart + hS * 3600 + mS * 60;
   datetime we = dayStart + hE * 3600 + mE * 60;
   if(we <= ws)
      we += 86400;
   if(we > now)
      return -1;   // il range non e' ancora chiuso
   int s = iBarShift(_Symbol, Timeframe, we - 1, false);
   if(s < 0)
      return -1;
   int n = 0;
   for(int i = s; i < s + 100000; i++)
     {
      datetime bt = iTime(_Symbol, Timeframe, i);
      if(bt == 0 || bt < ws)
         break;
      if(bt >= we)
         continue;
      double h = iHigh(_Symbol, Timeframe, i);
      double l = iLow(_Symbol, Timeframe, i);
      if(h <= 0.0 || l <= 0.0)
         return -1;
      hi = MathMax(hi, h);
      lo = MathMin(lo, l);
      n++;
     }
   if(n == 0)
     {
      info = "nessuna barra nella finestra " + TimeToString(ws, TIME_DATE | TIME_MINUTES) + " - " + TimeToString(we, TIME_DATE | TIME_MINUTES);
      return 0;
     }
   info = IntegerToString(n) + " barre " + TimeToString(ws, TIME_DATE | TIME_MINUTES) + " - " + TimeToString(we, TIME_DATE | TIME_MINUTES);
   return 1;
  }

// controlli comuni a tutti i modi: range nullo e limiti Min/Max. ritorna 1 = valido, 0 = scartato
int FinishRange(double hi, double lo, string &info)
  {
   if(!(hi > lo) || lo <= 0.0)
     {
      info += " | range nullo";
      return 0;
     }
   double pts = (hi - lo) / _Point;
   if(RequireRangeConfirmation)
     {
      if(pts < MinRangePoints)
        {
         info += StringFormat(" | scartato: %.0f punti, minimo %.0f", pts, MinRangePoints);
         return 0;
        }
      if(pts > MaxRangePoints)
        {
         info += StringFormat(" | scartato: %.0f punti, massimo %.0f", pts, MaxRangePoints);
         return 0;
        }
     }
   return 1;
  }

// range = massimo/minimo di RangeDaySpan barre D1 complete a partire dal giorno di riferimento. ritorna 1 = calcolato, -1 = dati non pronti
int RangeByD1(double &hi, double &lo, string &info)
  {
   hi = -DBL_MAX;
   lo = DBL_MAX;
   info = "";
   for(int k = 0; k < RangeDaySpan; k++)
     {
      double h = iHigh(_Symbol, PERIOD_D1, RangeDaysBack + k);
      double l = iLow(_Symbol, PERIOD_D1, RangeDaysBack + k);
      if(h <= 0.0 || l <= 0.0)
         return -1;
      hi = MathMax(hi, h);
      lo = MathMin(lo, l);
     }
   datetime t0 = iTime(_Symbol, PERIOD_D1, RangeDaysBack + RangeDaySpan - 1);
   datetime t1 = iTime(_Symbol, PERIOD_D1, RangeDaysBack);
   info = "D1 " + TimeToString(t0, TIME_DATE) + " .. " + TimeToString(t1, TIME_DATE);
   return 1;
  }

// range = massimo/minimo delle ultime RangeBarsLookback barre di Timeframe. ritorna 1 = calcolato, -1 = dati non pronti
int RangeByBars(double &hi, double &lo, string &info)
  {
   hi = -DBL_MAX;
   lo = DBL_MAX;
   info = "";
   int s0 = 1;
   if(RangeDaysBack > 0)
     {
      datetime nextDay = iTime(_Symbol, PERIOD_D1, RangeDaysBack - 1);
      if(nextDay == 0)
         return -1;
      s0 = iBarShift(_Symbol, Timeframe, nextDay - 1, false);
      if(s0 < 0)
         return -1;
     }
   for(int i = s0; i < s0 + RangeBarsLookback; i++)
     {
      double h = iHigh(_Symbol, Timeframe, i);
      double l = iLow(_Symbol, Timeframe, i);
      if(h <= 0.0 || l <= 0.0)
         return -1;
      hi = MathMax(hi, h);
      lo = MathMin(lo, l);
     }
   info = IntegerToString(RangeBarsLookback) + " barre " + TimeToString(iTime(_Symbol, Timeframe, s0 + RangeBarsLookback - 1), TIME_DATE | TIME_MINUTES) +
          " .. " + TimeToString(iTime(_Symbol, Timeframe, s0), TIME_DATE | TIME_MINUTES);
   return 1;
  }

int ComputeRange(datetime now, double &hi, double &lo, string &info)
  {
   int rt = 1;
   if(UseRangePrevD1)
      rt = RangeByD1(hi, lo, info);
   else
      if(UseRangeBars)
         rt = RangeByBars(hi, lo, info);
      else
         rt = RangeTimeWindow(now, RangeHourStart, RangeMinuteStart, RangeHourEnd, RangeMinuteEnd, hi, lo, info);
   if(rt <= 0)
      return rt;
   return FinishRange(hi, lo, info);
  }

void SetHLine(const string name, double price, color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
  }

string LineName(const string part) { return "MDRB_" + IntegerToString(MagicNumber) + "_" + part; }

void UpdateRangeLines()
  {
   if(!ShowRangeLines)
      return;
   if(g_rangeOK)
     {
      SetHLine(LineName("hi"), g_upper, clrDodgerBlue);
      SetHLine(LineName("lo"), g_lower, clrTomato);
     }
   else
     {
      ObjectDelete(0, LineName("hi"));
      ObjectDelete(0, LineName("lo"));
     }
  }

//+------------------------------------------------------------------+
//| Filtro di spread e modalita' di entrata a mercato                |
//| (le stesse funzioni servono all'EA reale e all'analisi virtuale) |
//+------------------------------------------------------------------+
// spread massimo ammesso in punti (0 = nessun limite)
double SpreadLimitPoints()
  {
   double lim = 0.0;
   if(MaxSpreadPoints > 0.0)
      lim = MaxSpreadPoints;
   if(MaxSpreadPctOfSL > 0.0)
     {
      double l2 = StopLossPoints * MaxSpreadPctOfSL / 100.0;
      if(lim <= 0.0 || l2 < lim)
         lim = l2;
     }
   return lim;
  }

// SL e TP di un ingresso a mercato al prezzo entry (tp = 0 se UseTakeProfit e' spento)
void MarketStops(const bool isBuy, const double entry, double &sl, double &tp)
  {
   double slD = StopLossPoints * _Point;
   double tpD = TakeProfitPoints * _Point;
   sl = NormPrice(isBuy ? entry - slD : entry + slD);
   tp = (UseTakeProfit ? NormPrice(isBuy ? entry + tpD : entry - tpD) : 0.0);
  }

// B) la candela di Timeframe appena chiusa ha chiuso oltre il livello? +1 sopra massimo+offset, -1 sotto minimo-offset, 0 no.
// La candela vale se FINISCE dentro la finestra di entrata (piu' ExpireExtraMinutes): cioe' anche quella che chiude esattamente a fine finestra, come nello
// Studio; l'ingresso avviene al primo tick utile dopo la chiusura. Vale solo la candela appena chiusa (contigua alla barra corrente); una candela che
// chiude a mezzanotte e' esclusa (per l'EA e' gia' un altro giorno).
int CandleSignal(double hi, double lo)
  {
   datetime t1 = iTime(_Symbol, Timeframe, 1);
   if(t1 == 0)
      return 0;
   datetime tc = t1 + (datetime)PeriodSeconds(Timeframe);
   if(tc != iTime(_Symbol, Timeframe, 0))
      return 0;   // c'e' un buco di barre (weekend, pausa, avvio): quella non e' la candela appena chiusa
   if(tc % 86400 == 0)
      return 0;
   if(WinOffset(tc - 1) >= WinLen() + ExpireExtraMinutes)
      return 0;
   double c = iClose(_Symbol, Timeframe, 1);
   if(c <= 0.0)
      return 0;
   double tol = 0.001 * _Point;
   double up = NormPrice(hi + PendingOrderOffsetPoints * _Point);
   double dn = NormPrice(lo - PendingOrderOffsetPoints * _Point);
   if(c - up > tol)
      return 1;
   if(dn - c > tol)
      return -1;
   return 0;
  }

// C) retest, tutto sul prezzo bid del grafico. Armamento: il prezzo supera il livello (bid >= massimo+offset per il long, bid <= minimo-offset per lo short).
// Ingresso: dopo l'armamento (mai nello stesso tick) il prezzo torna al bordo del range: bid <= massimo + tolleranza (long), bid >= minimo - tolleranza (short).
// Se pero' il prezzo si spinge oltre RetestMaxDepthPoints dentro il range la rottura e' fallita: l'armamento si annulla. Ritorna +1 / -1 / 0.
int RetestSignal(bool &armL, bool &armS, double hi, double lo, double bid, double ask)
  {
   double tol = RetestTolerancePoints * _Point;
   double depth = RetestMaxDepthPoints * _Point;
   if(armL)
     {
      if(bid < hi - depth - 1e-9)
         armL = false;
      else
         if(bid <= hi + tol + 1e-9)
            return 1;
     }
   if(armS)
     {
      if(bid > lo + depth + 1e-9)
         armS = false;
      else
         if(bid >= lo - tol - 1e-9)
            return -1;
     }
   double up = NormPrice(hi + PendingOrderOffsetPoints * _Point);
   double dn = NormPrice(lo - PendingOrderOffsetPoints * _Point);
   if(bid >= up - 1e-9)
      armL = true;
   if(bid <= dn + 1e-9)
      armS = true;
   return 0;
  }

// calcola il range di oggi quando serve (una volta al giorno). true se e' valido e pronto
bool EnsureRange(datetime now)
  {
   if(g_rangeDone)
      return g_rangeOK;
   if(now < g_nextTry)
      return false;
   double hi = 0.0, lo = 0.0;
   string info = "";
   int r = ComputeRange(now, hi, lo, info);
   if(r < 0)
     {
      if(!g_logWait)
        {
         Print("Range non ancora calcolabile (dati o fine del range): riprovo. ", info);
         g_logWait = true;
        }
      g_nextTry = now + 10;
      return false;
     }
   g_rangeDone = true;
   g_rangeInfo = info;
   if(r == 1)
     {
      g_rangeOK = true;
      g_upper = hi;
      g_lower = lo;
      g_rangeInfo = StringFormat("Range %s - %s (%.0f punti) %s", DoubleToString(lo, _Digits), DoubleToString(hi, _Digits), (hi - lo) / _Point, info);
     }
   Print(g_rangeOK ? "Range valido: " : "Range scartato: ", g_rangeInfo);
   UpdateRangeLines();
   return g_rangeOK;
  }

// ordine a mercato (modalita' B e C). ritorna true se accettato
bool OpenMarket(const bool isBuy, const string tag)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = (isBuy ? ask : bid);
   double sl = 0.0, tp = 0.0;
   MarketStops(isBuy, entry, sl, tp);
   double vol = NormVol(LotSize);
   if(vol <= 0.0)
     {
      Print("Volume non valido: LotSize ", DoubleToString(LotSize, 3));
      return false;
     }
   bool ok = (isBuy ? g_trade.Buy(vol, _Symbol, 0.0, sl, tp, OrderComment + " " + tag) : g_trade.Sell(vol, _Symbol, 0.0, sl, tp, OrderComment + " " + tag));
   if(!(ok && TradeOK()))
     {
      Print("Errore ordine a mercato ", (isBuy ? "Buy" : "Sell"), " (", tag, "): ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
      return false;
     }
   Print("Ingresso a mercato ", (isBuy ? "Buy" : "Sell"), " (", tag, ") a ", DoubleToString(entry, _Digits), " SL ", DoubleToString(sl, _Digits), " TP ", DoubleToString(tp, _Digits), " | ", g_rangeInfo);
   return true;
  }

void TryMarketEntry(datetime now, bool newBar)
  {
   if(!EntryCandleClose && !EntryRetest)
      return;
   if(newBar && EntryCandleClose)
      g_candlePend = true;   // una nuova candela e' appena chiusa: va valutata (e ritentata nella stessa barra se un filtro o un errore la blocca)
   bool inWin = OrdersMayLive(now);
   if(EntryRetest && !inWin)
     {
      g_armL = false;
      g_armS = false;
     }
   if(!inWin && !g_candlePend)
      return;   // fuori dalla finestra puo' ancora agire solo la candela appena chiusa
   if(g_tradesToday >= MaxTradesPerDay)
     {
      g_candlePend = false;
      return;
     }
   if(g_nPos > 0)
     {
      g_armL = false;
      g_armS = false;
      g_candlePend = false;
      return;
     }
   if(now < g_nextTryM)
      return;
   if(!TradingAllowed())
     {
      g_status = "trading non consentito";
      return;
     }
   if(!g_rangeDone && !inWin)
     {
      g_candlePend = false;   // il range si calcola solo dentro la finestra (come per gli ordini stop): fuori non si calcola e la candela non si puo' valutare
      return;
     }
   if(!EnsureRange(now))
      return;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0 || ask < bid)
      return;
   int dir = 0;
   string tag = "";
   bool retestWin = (EntryRetest && inWin);
   if(retestWin)
     {
      dir = RetestSignal(g_armL, g_armS, g_upper, g_lower, bid, ask);
      tag = "retest";
     }
   if(dir == 0 && g_candlePend)
     {
      dir = CandleSignal(g_upper, g_lower);
      tag = "chiusura";
      if(dir == 0)
         g_candlePend = false;   // candela valutata, nessun segnale: non si riprova
     }
   if(dir == 0)
      return;
   double spr = (ask - bid) / _Point;
   double lim = SpreadLimitPoints();
   if(lim > 0.0 && spr > lim)
     {
      if(!g_logSpread)
        {
         Print("Spread ", DoubleToString(spr, 1), " punti sopra il limite ", DoubleToString(lim, 1), ": segnale ", tag, " in attesa");
         g_logSpread = true;
        }
      return;
     }
   if(OpenMarket(dir > 0, tag))
     {
      g_armL = false;
      g_armS = false;
      g_candlePend = false;
      g_failToday = 0;
      g_tradesToday++;   // contato subito: se la posizione si chiude prima del prossimo tick SyncCounters non la vedrebbe mai
      g_nPos++;
      if(g_nOrd != 0)
         DeleteOurPendings("OCO: ingresso a mercato");
     }
   else
     {
      g_failToday++;
      g_nextTryM = now + (g_failToday >= 5 ? 600 : 15);
     }
  }

//+------------------------------------------------------------------+
//| Piazzamento della coppia di ordini                               |
//| ritorna 1 = piazzata, 0 = rinviata, -1 = errore                  |
//+------------------------------------------------------------------+
int PlaceSetup(datetime now)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ts = TickSize();
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double buyPx = NormPrice(g_upper + PendingOrderOffsetPoints * _Point);
   double sellPx = NormPrice(g_lower - PendingOrderOffsetPoints * _Point);
   bool buyOK = ((buyPx - ask) > stopLvl + ts * 0.5);
   bool sellOK = ((bid - sellPx) > stopLvl + ts * 0.5);
   if(!buyOK || !sellOK)
     {
      if(!ChaseIfBroken)
        {
         if(!g_logOutside)
           {
            Print("Prezzo fuori dai livelli (ask ", DoubleToString(ask, _Digits), " bid ", DoubleToString(bid, _Digits),
                  " BuyStop ", DoubleToString(buyPx, _Digits), " SellStop ", DoubleToString(sellPx, _Digits), "): attendo il rientro nel range");
            g_logOutside = true;
           }
         return 0;
        }
      if(!buyOK)
         buyPx = NormPrice(ask + stopLvl + 10 * _Point);
      if(!sellOK)
         sellPx = NormPrice(bid - stopLvl - 10 * _Point);
     }
   double slD = StopLossPoints * _Point;
   double tpD = TakeProfitPoints * _Point;
   double slB = NormPrice(buyPx - slD);
   double slS = NormPrice(sellPx + slD);
   double tpB = (UseTakeProfit ? NormPrice(buyPx + tpD) : 0.0);
   double tpS = (UseTakeProfit ? NormPrice(sellPx - tpD) : 0.0);
   double vol = NormVol(LotSize);
   if(vol <= 0.0)
     {
      Print("Volume non valido: LotSize ", DoubleToString(LotSize, 3));
      return -1;
     }
   ENUM_ORDER_TYPE_TIME ttype = ORDER_TIME_GTC;
   datetime expiry = 0;
   if((SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_SPECIFIED) != 0)
     {
      ttype = ORDER_TIME_SPECIFIED;
      expiry = OrdersExpiry(now);
     }
   ulong tBuy = 0;
   if(g_trade.BuyStop(vol, buyPx, _Symbol, slB, tpB, ttype, expiry, OrderComment + " B") && TradeOK())
      tBuy = g_trade.ResultOrder();
   else
     {
      Print("Errore BuyStop @ ", DoubleToString(buyPx, _Digits), ": ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
      return -1;
     }
   if(!(g_trade.SellStop(vol, sellPx, _Symbol, slS, tpS, ttype, expiry, OrderComment + " S") && TradeOK()))
     {
      Print("Errore SellStop @ ", DoubleToString(sellPx, _Digits), ": ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
      if(g_trade.OrderDelete(tBuy))
         Print("BuyStop ", tBuy, " cancellato: la coppia non e' completa");
      return -1;
     }
   Print("Coppia piazzata: BuyStop ", DoubleToString(buyPx, _Digits), " SL ", DoubleToString(slB, _Digits), " TP ", DoubleToString(tpB, _Digits),
         " | SellStop ", DoubleToString(sellPx, _Digits), " SL ", DoubleToString(slS, _Digits), " TP ", DoubleToString(tpS, _Digits),
         " | scadenza ", TimeToString(OrdersExpiry(now), TIME_DATE | TIME_MINUTES), " | ", g_rangeInfo);
   return 1;
  }

void TryPlaceSetup(datetime now)
  {
   if(!EntryStop)
      return;
   if(!InEntryWindow(now))
      return;
   if(g_tradesToday >= MaxTradesPerDay)
      return;
   if(g_pairsToday > g_tradesToday)
      return;   // c'e' una coppia in attesa di esito
   if(g_nPos > 0 || g_nOrd > 0)
      return;
   if(now < g_nextTry)
      return;
   if(!TradingAllowed())
     {
      g_status = "trading non consentito";
      return;
     }
   if(!EnsureRange(now))
      return;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0 || ask < bid)
      return;
   double spr = (ask - bid) / _Point;
   double lim = SpreadLimitPoints();
   if(lim > 0.0 && spr > lim)
     {
      if(!g_logSpread)
        {
         Print("Spread ", DoubleToString(spr, 1), " punti sopra il limite ", DoubleToString(lim, 1), ": attendo");
         g_logSpread = true;
        }
      return;
     }
   int r = PlaceSetup(now);
   if(r == 1)
     {
      g_pairsToday++;
      g_failToday = 0;
      g_nOrd = CountOurPendings();
     }
   else
      if(r < 0)
        {
         g_failToday++;
         g_nextTry = now + (g_failToday >= 5 ? 600 : 15);
        }
  }

//+------------------------------------------------------------------+
//| OCO e scadenza degli ordini                                      |
//+------------------------------------------------------------------+
void ManageOrders(datetime now)
  {
   if(g_nOrd <= 0)
      return;
   if(g_nPos > 0)
     {
      DeleteOurPendings("OCO: una posizione e' aperta");
      return;
     }
   if(!OrdersMayLive(now))
      DeleteOurPendings("fuori dalla finestra");
  }

//+------------------------------------------------------------------+
//| Break even e trailing                                            |
//+------------------------------------------------------------------+
bool IsBetterSL(bool isBuy, double newSL, double curSL, double minGain)
  {
   if(curSL <= 0.0)
      return true;
   if(isBuy)
      return ((newSL - curSL) >= minGain - _Point * 0.5);
   return ((curSL - newSL) >= minGain - _Point * 0.5);
  }

// nuovo SL di una posizione (reale o virtuale) per break even e trailing.
// ritorna true se lo SL va modificato a newSL; profitPts = profitto corrente in punti
bool NextStop(bool isBuy, double entry, double sl, double tp, double bid, double ask, double &newSL, double &profitPts)
  {
   double ts = TickSize();
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double frzLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double price = (isBuy ? bid : ask);
   profitPts = (isBuy ? (price - entry) : (entry - price)) / _Point;
   double target = 0.0;
   bool have = false;
   if(UsaBreakEven && profitPts >= BreakEvenAttivazione)
     {
      double be = (isBuy ? entry + BreakEvenOffset * _Point : entry - BreakEvenOffset * _Point);
      if(IsBetterSL(isBuy, be, sl, ts))
        {
         target = be;
         have = true;
        }
     }
   if(UsaTrailingStop && profitPts >= TrailingStartProfit)
     {
      double tr = (isBuy ? price - TrailingOffset * _Point : price + TrailingOffset * _Point);
      if(IsBetterSL(isBuy, tr, sl, MathMax(ts, TrailingStep * _Point)))
        {
         if(!have || (isBuy ? tr > target : tr < target))
           {
            target = tr;
            have = true;
           }
        }
     }
   if(!have)
      return false;
   // distanza minima dal prezzo imposta dal broker
   if(isBuy)
      target = MathMin(target, price - stopLvl - ts);
   else
      target = MathMax(target, price + stopLvl + ts);
   target = NormPrice(target);
   if(!IsBetterSL(isBuy, target, sl, ts))
      return false;
   if(frzLvl > 0.0 && ((tp > 0.0 && MathAbs(tp - price) <= frzLvl) || (sl > 0.0 && MathAbs(price - sl) <= frzLvl)))
      return false;
   if(tp > 0.0 && MathAbs(tp - price) < stopLvl + ts)
      return false;   // il target e' dentro la distanza minima: il broker potrebbe rifiutare la modifica, e la chiusura e' imminente
   newSL = target;
   return true;
  }

void ManagePositions(datetime now)
  {
   if(!UsaBreakEven && !UsaTrailingStop)
      return;
   if(g_nPos <= 0 || now < g_nextMod)
      return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber)
         continue;
      bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double target = 0.0, profitPts = 0.0;
      if(!NextStop(isBuy, entry, sl, tp, bid, ask, target, profitPts))
         continue;
      if(g_trade.PositionModify(tk, target, tp) && TradeOK())
         Print("Posizione ", tk, ": SL ", DoubleToString(sl, _Digits), " -> ", DoubleToString(target, _Digits), " (profitto ", DoubleToString(profitPts, 0), " punti)");
      else
        {
         Print("Errore modifica SL posizione ", tk, " a ", DoubleToString(target, _Digits), ": ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
         g_nextMod = now + 5;
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| ANALISI VIRTUALE (SlotScan): NESSUN ordine reale                  |
//| Ogni "concorrente" e' un EA virtuale indipendente, formato da:    |
//|   una SORGENTE di range                                           |
//|     - le fasce orarie Slot1..Slot12 (se UseRangeTime: massimo/    |
//|       minimo della fascia nel giorno di riferimento RangeDaysBack)|
//|     - il range a barre (se UseRangeBars: RangeBarsLookback barre  |
//|       di Timeframe)                                               |
//|     - il range dei D1 precedenti (se UseRangePrevD1: RangeDaySpan |
//|       giorni)                                                     |
//|   una MODALITA' di entrata                                        |
//|     - EntryStop         coppia di ordini stop (OCO)               |
//|     - EntryCandleClose  chiusura di candela oltre il livello      |
//|     - EntryRetest       rottura e ritorno al bordo del range      |
//| Poi segue le stesse regole dell'EA reale: finestra di entrata,     |
//| filtri di larghezza e di spread, SL/TP, break even e trailing, un  |
//| numero massimo di trade al giorno. Ordini e posizioni sono         |
//| simulati qui dentro sui tick (ask/bid del tester): non si apre     |
//| nulla nel conto. I concorrenti non si influenzano a vicenda        |
//| (nemmeno quelli della stessa fascia con modalita' diverse). A fine |
//| test si scrive la classifica (log degli Esperti + file CSV).       |
//+------------------------------------------------------------------+
#define NSLOT 12
#define NSRC 14
#define NMODE 3
#define NCON 42

struct SSlot
  {
   bool     on;
   int      src, mode;               // sorgente (0..11 fasce, 12 barre, 13 D1 precedenti) e modalita' (0 stop, 1 chiusura, 2 retest)
   int      hS, mS, hE, mE;          // fascia (ora server); hE = 0 significa mezzanotte
   // stato del giorno
   bool     rangeDone, rangeOK;
   double   hi, lo;
   int      pairs, trades;           // coppie piazzate / posizioni aperte oggi
   datetime nextTry;
   bool     armL, armS;              // retest: il prezzo ha superato il livello, si attende il ritorno
   bool     candlePend;              // chiusura di candela: la candela appena chiusa va ancora valutata/ritentata (fino a fine barra)
   // ordini e posizione virtuali
   int      state;                   // 0 niente, 1 coppia pendente (solo stop), 2 posizione aperta
   double   buyPx, sellPx, slB, slS, tpB, tpS;
   datetime expiry;
   bool     isBuy;
   double   entry, sl, tp, slNom, width;
   datetime tOpen;
   // statistiche
   int      daysSeen, daysValid, nPairs;
   double   sumWidth;
   int      n[2], wins[2];           // [0] = prima della data di separazione (o tutto), [1] = dopo
   double   sumR[2], sumR2[2], gW[2], gL[2], sumPts[2];
   double   eq, peak, dd;
  };

struct SVTrade
  {
   int      con, dir, part;
   datetime tOpen, tClose;
   double   entry, exitPx, R, pts, width;
  };

SSlot    g_sl[NCON];
SVTrade  g_vt[];
int      g_nVt = 0;

bool SlotOn(const int k)
  {
   switch(k)
     {
      case 0:
         return Slot1;
      case 1:
         return Slot2;
      case 2:
         return Slot3;
      case 3:
         return Slot4;
      case 4:
         return Slot5;
      case 5:
         return Slot6;
      case 6:
         return Slot7;
      case 7:
         return Slot8;
      case 8:
         return Slot9;
      case 9:
         return Slot10;
      case 10:
         return Slot11;
      case 11:
         return Slot12;
     }
   return false;
  }

bool SrcOn(const int src)
  {
   if(src < NSLOT)
      return (UseRangeTime && SlotOn(src));
   if(src == NSLOT)
      return UseRangeBars;
   return UseRangePrevD1;
  }

bool ModeOn(const int m)
  {
   if(m == 0)
      return EntryStop;
   if(m == 1)
      return EntryCandleClose;
   return EntryRetest;
  }

string ModeName(const int m)
  {
   if(m == 0)
      return "stop";
   if(m == 1)
      return "chiusura";
   return "retest";
  }

string SrcLabel(const int c)
  {
   int src = g_sl[c].src;
   if(src < NSLOT)
      return StringFormat("%02d:%02d-%02d:%02d", g_sl[c].hS, g_sl[c].mS, (g_sl[c].hE == 0 ? 24 : g_sl[c].hE), g_sl[c].mE);
   if(src == NSLOT)
      return "barre" + IntegerToString(RangeBarsLookback);
   return "D1x" + IntegerToString(RangeDaySpan);
  }

string ConName(const int c)
  {
   return SrcLabel(c) + " " + ModeName(g_sl[c].mode);
  }

void ScanInit()
  {
   g_nVt = 0;
   ArrayResize(g_vt, 0);
   for(int c = 0; c < NCON; c++)
     {
      ZeroMemory(g_sl[c]);
      int src = c / NMODE;
      g_sl[c].src = src;
      g_sl[c].mode = c % NMODE;
      g_sl[c].on = (SrcOn(src) && ModeOn(c % NMODE));
      if(src < NSLOT)
        {
         int startMin = (SlotFirstHour * 60 + src * SlotLenHours * 60) % 1440;
         int endMin = startMin + SlotLenHours * 60;
         g_sl[c].hS = startMin / 60;
         g_sl[c].mS = 0;
         g_sl[c].hE = (endMin % 1440) / 60;
         g_sl[c].mE = 0;
         // una fascia identica a una precedente (succede se SlotLenHours non e' 1, 2 o un divisore di 24 che dia meno di 12 fasce distinte) e' un doppione: si spegne
         for(int q = 0; q < src; q++)
            if(g_sl[q * NMODE].hS == g_sl[c].hS && g_sl[q * NMODE].hE == g_sl[c].hE)
               g_sl[c].on = false;
        }
     }
  }

int ScanActive()
  {
   int n = 0;
   for(int c = 0; c < NCON; c++)
      if(g_sl[c].on)
         n++;
   return n;
  }

void ScanNewDay(const datetime now)
  {
   for(int c = 0; c < NCON; c++)
     {
      // una coppia scaduta (per esempio nel fine settimana) non c'e' piu' quando comincia il nuovo giorno: il broker l'ha gia' tolta
      if(g_sl[c].state == 1 && (now >= g_sl[c].expiry || !OrdersMayLive(now)))
         g_sl[c].state = 0;
      g_sl[c].rangeDone = false;
      g_sl[c].rangeOK = false;
      g_sl[c].hi = 0.0;
      g_sl[c].lo = 0.0;
      g_sl[c].pairs = (g_sl[c].state == 1 ? 1 : 0);   // una coppia ancora viva (finestra a cavallo di mezzanotte) conta come piazzata
      g_sl[c].trades = 0;
      g_sl[c].nextTry = 0;
      g_sl[c].armL = false;
      g_sl[c].armS = false;
      g_sl[c].candlePend = false;
     }
  }

// chiude la posizione virtuale del concorrente c al prezzo exitPx e aggiorna le statistiche
void ScanClose(const int c, const double exitPx, const datetime now)
  {
   double diff = (g_sl[c].isBuy ? (exitPx - g_sl[c].entry) : (g_sl[c].entry - exitPx));
   double R = diff / g_sl[c].slNom;
   double pts = diff / _Point;
   if(SlotCommissionPoints > 0.0)
     {
      R -= SlotCommissionPoints * _Point / g_sl[c].slNom;
      pts -= SlotCommissionPoints;
     }
   int p = ((SlotSplitDate > 0 && g_sl[c].tOpen >= SlotSplitDate) ? 1 : 0);
   g_sl[c].n[p]++;
   if(R > 0.0)
     {
      g_sl[c].wins[p]++;
      g_sl[c].gW[p] += R;
     }
   else
      g_sl[c].gL[p] += -R;
   g_sl[c].sumR[p] += R;
   g_sl[c].sumR2[p] += R * R;
   g_sl[c].sumPts[p] += pts;
   g_sl[c].eq += R;
   if(g_sl[c].eq > g_sl[c].peak)
      g_sl[c].peak = g_sl[c].eq;
   if(g_sl[c].peak - g_sl[c].eq > g_sl[c].dd)
      g_sl[c].dd = g_sl[c].peak - g_sl[c].eq;
   ArrayResize(g_vt, g_nVt + 1, 4096);
   g_vt[g_nVt].con = c;
   g_vt[g_nVt].dir = (g_sl[c].isBuy ? 1 : -1);
   g_vt[g_nVt].part = p;
   g_vt[g_nVt].tOpen = g_sl[c].tOpen;
   g_vt[g_nVt].tClose = now;
   g_vt[g_nVt].entry = g_sl[c].entry;
   g_vt[g_nVt].exitPx = exitPx;
   g_vt[g_nVt].R = R;
   g_vt[g_nVt].pts = pts;
   g_vt[g_nVt].width = g_sl[c].width;
   g_nVt++;
   g_sl[c].state = 0;
  }

// range del concorrente c al tick corrente: 1 valido, 0 scartato, -1 non pronto
int ScanRange(const int c, const datetime now, double &hi, double &lo, string &info)
  {
   int src = g_sl[c].src;
   int r = 1;
   if(src < NSLOT)
      r = RangeTimeWindow(now, g_sl[c].hS, g_sl[c].mS, g_sl[c].hE, g_sl[c].mE, hi, lo, info);
   else
      if(src == NSLOT)
         r = RangeByBars(hi, lo, info);
      else
         r = RangeByD1(hi, lo, info);
   if(r > 0)
      r = FinishRange(hi, lo, info);
   return r;
  }

// calcola (una volta al giorno) il range del concorrente; true se e' valido e pronto
bool ScanEnsureRange(const int c, const datetime now)
  {
   if(!g_sl[c].rangeDone)
     {
      double hi = 0.0, lo = 0.0;
      string info = "";
      int r = ScanRange(c, now, hi, lo, info);
      if(r < 0)
        {
         g_sl[c].nextTry = now + 10;
         return false;
        }
      g_sl[c].rangeDone = true;
      g_sl[c].daysSeen++;
      if(r == 1)
        {
         g_sl[c].rangeOK = true;
         g_sl[c].hi = hi;
         g_sl[c].lo = lo;
         g_sl[c].daysValid++;
         g_sl[c].sumWidth += (hi - lo) / _Point;
        }
     }
   return g_sl[c].rangeOK;
  }

// modalita' stop: piazzamento della coppia virtuale (stesse condizioni di TryPlaceSetup)
void ScanPlacePair(const int c, const datetime now, const double bid, const double ask)
  {
   if(!InEntryWindow(now))
      return;
   if(g_sl[c].trades >= MaxTradesPerDay)
      return;
   if(g_sl[c].pairs > g_sl[c].trades)
      return;
   if(now < g_sl[c].nextTry)
      return;
   if(!ScanEnsureRange(c, now))
      return;
   if(ask <= 0.0 || bid <= 0.0 || ask < bid)
      return;
   double spr = (ask - bid) / _Point;
   double lim = SpreadLimitPoints();
   if(lim > 0.0 && spr > lim)
      return;
   double ts = TickSize();
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double buyPx = NormPrice(g_sl[c].hi + PendingOrderOffsetPoints * _Point);
   double sellPx = NormPrice(g_sl[c].lo - PendingOrderOffsetPoints * _Point);
   bool buyOK = ((buyPx - ask) > stopLvl + ts * 0.5);
   bool sellOK = ((bid - sellPx) > stopLvl + ts * 0.5);
   if(!buyOK || !sellOK)
     {
      if(!ChaseIfBroken)
         return;
      if(!buyOK)
         buyPx = NormPrice(ask + stopLvl + 10 * _Point);
      if(!sellOK)
         sellPx = NormPrice(bid - stopLvl - 10 * _Point);
     }
   double slD = StopLossPoints * _Point;
   double tpD = TakeProfitPoints * _Point;
   g_sl[c].buyPx = buyPx;
   g_sl[c].sellPx = sellPx;
   g_sl[c].slB = NormPrice(buyPx - slD);
   g_sl[c].slS = NormPrice(sellPx + slD);
   g_sl[c].tpB = (UseTakeProfit ? NormPrice(buyPx + tpD) : 0.0);
   g_sl[c].tpS = (UseTakeProfit ? NormPrice(sellPx - tpD) : 0.0);
   g_sl[c].expiry = OrdersExpiry(now);
   g_sl[c].state = 1;
   g_sl[c].pairs++;
   g_sl[c].nPairs++;
  }

// modalita' chiusura di candela (1) e retest (2): ingresso virtuale a mercato (stesse condizioni di TryMarketEntry)
void ScanMarketEntry(const int c, const datetime now, const double bid, const double ask, const bool newBar)
  {
   if(newBar && g_sl[c].mode == 1)
      g_sl[c].candlePend = true;
   bool inWin = OrdersMayLive(now);
   if(g_sl[c].mode == 2 && !inWin)
     {
      g_sl[c].armL = false;
      g_sl[c].armS = false;
     }
   if(!inWin && !g_sl[c].candlePend)
      return;
   if(g_sl[c].trades >= MaxTradesPerDay)
     {
      g_sl[c].candlePend = false;
      return;
     }
   if(!g_sl[c].rangeDone && !inWin)
     {
      g_sl[c].candlePend = false;
      return;
     }
   if(now < g_sl[c].nextTry)
      return;
   if(!ScanEnsureRange(c, now))
      return;
   if(ask <= 0.0 || bid <= 0.0 || ask < bid)
      return;
   int dir = 0;
   bool retestWin = (g_sl[c].mode == 2 && inWin);
   if(retestWin)
      dir = RetestSignal(g_sl[c].armL, g_sl[c].armS, g_sl[c].hi, g_sl[c].lo, bid, ask);
   if(dir == 0 && g_sl[c].candlePend)
     {
      dir = CandleSignal(g_sl[c].hi, g_sl[c].lo);
      if(dir == 0)
         g_sl[c].candlePend = false;
     }
   if(dir == 0)
      return;
   double spr = (ask - bid) / _Point;
   double lim = SpreadLimitPoints();
   if(lim > 0.0 && spr > lim)
      return;
   bool isBuy = (dir > 0);
   double entry = (isBuy ? ask : bid);
   double sl = 0.0, tp = 0.0;
   MarketStops(isBuy, entry, sl, tp);
   g_sl[c].isBuy = isBuy;
   g_sl[c].entry = entry;
   g_sl[c].sl = sl;
   g_sl[c].tp = tp;
   g_sl[c].slNom = MathAbs(entry - sl);
   g_sl[c].tOpen = now;
   g_sl[c].width = (g_sl[c].hi - g_sl[c].lo) / _Point;
   g_sl[c].trades++;
   g_sl[c].nPairs++;
   g_sl[c].state = 2;
   g_sl[c].armL = false;
   g_sl[c].armS = false;
   g_sl[c].candlePend = false;
  }

// un tick per un concorrente: prima il "broker" virtuale (scadenza, SL/TP, riempimenti), poi le azioni dell'EA (break even/trailing, ingresso)
void ScanSlot(const int c, const datetime now, const double bid, const double ask, const bool newBar)
  {
   if(g_sl[c].state == 1 && (now >= g_sl[c].expiry || !OrdersMayLive(now)))
      g_sl[c].state = 0;
   if(g_sl[c].state == 2)
     {
      bool hit = false;
      double ex = 0.0;
      if(g_sl[c].isBuy)
        {
         if(g_sl[c].sl > 0.0 && bid <= g_sl[c].sl + 1e-9)
           {
            hit = true;
            ex = bid;
           }
         else
            if(g_sl[c].tp > 0.0 && bid >= g_sl[c].tp - 1e-9)
              {
               hit = true;
               ex = bid;
              }
        }
      else
        {
         if(g_sl[c].sl > 0.0 && ask >= g_sl[c].sl - 1e-9)
           {
            hit = true;
            ex = ask;
           }
         else
            if(g_sl[c].tp > 0.0 && ask <= g_sl[c].tp + 1e-9)
              {
               hit = true;
               ex = ask;
              }
        }
      if(hit)
         ScanClose(c, ex, now);
     }
   if(g_sl[c].state == 1)
     {
      bool fillB = (ask >= g_sl[c].buyPx - 1e-9);
      bool fillS = (!fillB && bid <= g_sl[c].sellPx + 1e-9);
      if(fillB || fillS)
        {
         g_sl[c].isBuy = fillB;
         g_sl[c].entry = (fillB ? MathMax(g_sl[c].buyPx, ask) : MathMin(g_sl[c].sellPx, bid));   // un gap si riempie al prezzo del tick
         g_sl[c].sl = (fillB ? g_sl[c].slB : g_sl[c].slS);
         g_sl[c].tp = (fillB ? g_sl[c].tpB : g_sl[c].tpS);
         g_sl[c].slNom = (fillB ? MathAbs(g_sl[c].buyPx - g_sl[c].slB) : MathAbs(g_sl[c].sellPx - g_sl[c].slS));
         g_sl[c].tOpen = now;
         g_sl[c].width = (g_sl[c].hi - g_sl[c].lo) / _Point;
         g_sl[c].trades++;
         g_sl[c].state = 2;
        }
     }
   if(g_sl[c].state == 2 && (UsaBreakEven || UsaTrailingStop))
     {
      double tg = 0.0, pp = 0.0;
      if(NextStop(g_sl[c].isBuy, g_sl[c].entry, g_sl[c].sl, g_sl[c].tp, bid, ask, tg, pp))
         g_sl[c].sl = tg;
     }
   if(g_sl[c].state != 0)
     {
      g_sl[c].armL = false;      // come TryMarketEntry con una posizione aperta
      g_sl[c].armS = false;
      g_sl[c].candlePend = false;
      return;
     }
   if(g_sl[c].mode == 0)
      ScanPlacePair(c, now, bid, ask);
   else
      ScanMarketEntry(c, now, bid, ask, newBar);
  }

void ScanTick(const datetime now, const bool newBar)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;
   for(int c = 0; c < NCON; c++)
      if(g_sl[c].on)
         ScanSlot(c, now, bid, ask, newBar);
  }

//--- metriche e classifica
int SlotTrades(const int k) { return g_sl[k].n[0] + g_sl[k].n[1]; }

double SlotSumR(const int k) { return g_sl[k].sumR[0] + g_sl[k].sumR[1]; }

double SlotMean(const int k)
  {
   int n = SlotTrades(k);
   return (n > 0 ? SlotSumR(k) / n : 0.0);
  }

double SlotT(const int k)
  {
   int n = SlotTrades(k);
   if(n < 2)
      return 0.0;
   double s = SlotSumR(k);
   double s2 = g_sl[k].sumR2[0] + g_sl[k].sumR2[1];
   double var = (s2 - s * s / n) / (n - 1);
   if(var <= 1e-12)
      return 0.0;
   return (s / n) / MathSqrt(var / n);
  }

double SlotPF(const int k)
  {
   double gw = g_sl[k].gW[0] + g_sl[k].gW[1];
   double gl = g_sl[k].gL[0] + g_sl[k].gL[1];
   if(gl <= 1e-12)
      return (gw > 0.0 ? 99.0 : 0.0);
   return gw / gl;
  }

double SlotScore(const int k)
  {
   if(SlotRankBy == SLOT_RANK_EXPECTANCY)
      return SlotMean(k);
   if(SlotRankBy == SLOT_RANK_PF)
      return MathMin(SlotPF(k), 10.0);
   if(SlotRankBy == SLOT_RANK_TOTAL)
      return SlotSumR(k);
   return SlotT(k);
  }

// a prima di b nella classifica? (prima chi ha almeno SlotMinTrades trade, per punteggio; poi gli altri, per numero di trade)
bool SlotBefore(const int a, const int b)
  {
   bool ea = (SlotTrades(a) >= SlotMinTrades);
   bool eb = (SlotTrades(b) >= SlotMinTrades);
   if(ea != eb)
      return ea;
   if(ea)
     {
      double sa = SlotScore(a), sb = SlotScore(b);
      if(MathAbs(sa - sb) > 1e-12)
         return sa > sb;
     }
   else
     {
      if(SlotTrades(a) != SlotTrades(b))
         return SlotTrades(a) > SlotTrades(b);
     }
   return a < b;
  }

int ScanOrder(int &order[])
  {
   int cnt = 0;
   for(int k = 0; k < NCON; k++)
      if(g_sl[k].on)
        {
         order[cnt] = k;
         cnt++;
        }
   for(int i = 0; i < cnt - 1; i++)
      for(int j = i + 1; j < cnt; j++)
         if(SlotBefore(order[j], order[i]))
           {
            int tmp = order[i];
            order[i] = order[j];
            order[j] = tmp;
           }
   return cnt;
  }

string SlotRankName()
  {
   if(SlotRankBy == SLOT_RANK_EXPECTANCY)
      return "E[R] medio per trade";
   if(SlotRankBy == SLOT_RANK_PF)
      return "profit factor";
   if(SlotRankBy == SLOT_RANK_TOTAL)
      return "R totale";
   return "t-stat dell'E[R]";
  }

// valore per il tester (OnTester): punteggio del concorrente migliore tra quelli con abbastanza trade, -1e9 se nessuno
double ScanBestScore()
  {
   int order[];
   ArrayResize(order, NCON);
   int cnt = ScanOrder(order);
   if(cnt < 1 || SlotTrades(order[0]) < SlotMinTrades)
      return -1.0e9;   // nessun concorrente ha abbastanza trade: peggio di qualunque punteggio reale (anche negativo)
   return SlotScore(order[0]);
  }

string SlotLine(const int rank, const int k)
  {
   int n = SlotTrades(k);
   double wr = (n > 0 ? 100.0 * (g_sl[k].wins[0] + g_sl[k].wins[1]) / n : 0.0);
   double aw = (g_sl[k].daysValid > 0 ? g_sl[k].sumWidth / g_sl[k].daysValid : 0.0);
   double pts = g_sl[k].sumPts[0] + g_sl[k].sumPts[1];
   string s = StringFormat("%2d) %s | giorni %d (range validi %d, largh. media %.0f pt) | setup %d | trade %d | win %.1f%% | E[R] %.3f | PF %.2f | R tot %.1f | punti %.0f | maxDD %.1f R | t %.2f",
                           rank, ConName(k), g_sl[k].daysSeen, g_sl[k].daysValid, aw, g_sl[k].nPairs, n, wr, SlotMean(k), SlotPF(k), SlotSumR(k), pts, g_sl[k].dd, SlotT(k));
   if(SlotSplitDate > 0)
     {
      s += StringFormat(" | prima: %d trade E[R] %.3f | dopo: %d trade E[R] %.3f",
                        g_sl[k].n[0], (g_sl[k].n[0] > 0 ? g_sl[k].sumR[0] / g_sl[k].n[0] : 0.0), g_sl[k].n[1], (g_sl[k].n[1] > 0 ? g_sl[k].sumR[1] / g_sl[k].n[1] : 0.0));
     }
   if(n < SlotMinTrades)
      s += "  [pochi trade: fuori classifica]";
   return s;
  }

void ScanWriteFiles(const int &order[], const int cnt)
  {
   string base = "MDRB_SlotScan_" + _Symbol;
   int h = FileOpen(base + ".csv", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      Print("SlotScan: impossibile scrivere ", base, ".csv (errore ", GetLastError(), ")");
   else
     {
      FileWriteString(h, "rank,source,mode,label,days_seen,days_valid,avg_width_pts,setups,trades,win_pct,expectancy_r,profit_factor,total_r,total_pts,max_dd_r,t_stat,eligible,trades_before,er_before,trades_after,er_after\n");
      for(int i = 0; i < cnt; i++)
        {
         int k = order[i];
         int n = SlotTrades(k);
         double wr = (n > 0 ? 100.0 * (g_sl[k].wins[0] + g_sl[k].wins[1]) / n : 0.0);
         double aw = (g_sl[k].daysValid > 0 ? g_sl[k].sumWidth / g_sl[k].daysValid : 0.0);
         string ln = IntegerToString(i + 1) + "," + IntegerToString(g_sl[k].src + 1) + "," + ModeName(g_sl[k].mode) + "," + SrcLabel(k) + "," +
                     IntegerToString(g_sl[k].daysSeen) + "," + IntegerToString(g_sl[k].daysValid) + "," + DoubleToString(aw, 1) + "," + IntegerToString(g_sl[k].nPairs) + "," + IntegerToString(n) + "," +
                     DoubleToString(wr, 2) + "," + DoubleToString(SlotMean(k), 4) + "," + DoubleToString(SlotPF(k), 3) + "," + DoubleToString(SlotSumR(k), 3) + "," + DoubleToString(g_sl[k].sumPts[0] + g_sl[k].sumPts[1], 1) + "," +
                     DoubleToString(g_sl[k].dd, 3) + "," + DoubleToString(SlotT(k), 3) + "," + (n >= SlotMinTrades ? "1" : "0") + "," + IntegerToString(g_sl[k].n[0]) + "," + DoubleToString(g_sl[k].n[0] > 0 ? g_sl[k].sumR[0] / g_sl[k].n[0] : 0.0, 4) + "," +
                     IntegerToString(g_sl[k].n[1]) + "," + DoubleToString(g_sl[k].n[1] > 0 ? g_sl[k].sumR[1] / g_sl[k].n[1] : 0.0, 4);
         FileWriteString(h, ln + "\n");
        }
      FileClose(h);
     }
   h = FileOpen(base + "_trades.csv", FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE)
      Print("SlotScan: impossibile scrivere ", base, "_trades.csv (errore ", GetLastError(), ")");
   else
     {
      FileWriteString(h, "source,mode,label,dir,part,topen,tclose,entry,exit,R,pts,range_pts\n");
      for(int i = 0; i < g_nVt; i++)
        {
         int k = g_vt[i].con;
         string ln = IntegerToString(g_sl[k].src + 1) + "," + ModeName(g_sl[k].mode) + "," + SrcLabel(k) + "," +
                     IntegerToString(g_vt[i].dir) + "," + (g_vt[i].part == 1 ? "dopo" : "prima") + "," + TimeToString(g_vt[i].tOpen, TIME_DATE | TIME_MINUTES) + "," + TimeToString(g_vt[i].tClose, TIME_DATE | TIME_MINUTES) + "," +
                     DoubleToString(g_vt[i].entry, _Digits) + "," + DoubleToString(g_vt[i].exitPx, _Digits) + "," + DoubleToString(g_vt[i].R, 4) + "," + DoubleToString(g_vt[i].pts, 1) + "," + DoubleToString(g_vt[i].width, 1);
         FileWriteString(h, ln + "\n");
        }
      FileClose(h);
     }
  }

void ScanReport()
  {
   int order[];
   ArrayResize(order, NCON);
   int cnt = ScanOrder(order);
   if(cnt < 1)
      return;
   int nOpen = 0;
   for(int k = 0; k < NCON; k++)
      if(g_sl[k].on && g_sl[k].state == 2)
         nOpen++;
   Print("=== CLASSIFICA DEI CONCORRENTI: range x modalita' di entrata (analisi virtuale: nessun ordine e nessuna posizione reale) ===");
   Print("Criterio: ", SlotRankName(), " | in classifica i concorrenti con almeno ", SlotMinTrades, " trade | giorno di riferimento del range RangeDaysBack ", RangeDaysBack,
         " (barre ", EnumToString(Timeframe), ") | finestra di entrata ", StringFormat("%02d:%02d-%02d:%02d", TradeHourStart, TradeMinuteStart, TradeHourEnd, TradeMinuteEnd),
         " | offset ", PendingOrderOffsetPoints, " | SL ", DoubleToString(StopLossPoints, 0), " TP ", (UseTakeProfit ? DoubleToString(TakeProfitPoints, 0) : "nessuno"), " punti");
   for(int i = 0; i < cnt; i++)
      Print(SlotLine(i + 1, order[i]));
   Print("R = profitto in multipli dello SL (costi di spread inclusi", (SlotCommissionPoints > 0.0 ? " e commissione" : ", commissione NON inclusa: usa SlotCommissionPoints"), "). Posizioni virtuali ancora aperte a fine test (non contate): ", nOpen,
         ". Con ", cnt, " concorrenti provati il migliore e' in parte fortuna: confermalo rifacendo il test su un altro periodo (SlotSplitDate mostra solo prima/dopo, ma la classifica usa tutti i trade) prima di fidarti.");
   if(SlotWriteFiles)
     {
      ScanWriteFiles(order, cnt);
      Print("SlotScan: file scritti in Terminal\\Common\\Files: MDRB_SlotScan_", _Symbol, ".csv (classifica) e MDRB_SlotScan_", _Symbol, "_trades.csv (tutti i trade virtuali)");
     }
  }

//+------------------------------------------------------------------+
//| Pannello                                                         |
//+------------------------------------------------------------------+
void UpdatePanel(datetime now)
  {
   if(!ShowPanel || now == g_lastPanel)
      return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   g_lastPanel = now;
   if(SlotScan)
     {
      string sp = "MultiDayRangeBreakout 3.00 - ANALISI VIRTUALE (nessun ordine reale)\nOra server " + TimeToString(now, TIME_DATE | TIME_MINUTES) + "  finestra di entrata " +
                  StringFormat("%02d:%02d-%02d:%02d", TradeHourStart, TradeMinuteStart, TradeHourEnd, TradeMinuteEnd) + (InEntryWindow(now) ? " (aperta)" : " (chiusa)") + "\n";
      int ord[];
      ArrayResize(ord, NCON);
      int cn = ScanOrder(ord);
      for(int i = 0; i < cn && i < 8; i++)
        {
         int k = ord[i];
         sp += IntegerToString(i + 1) + ") " + ConName(k) + "  trade " + IntegerToString(SlotTrades(k)) + "  E[R] " + DoubleToString(SlotMean(k), 3) + "  t " + DoubleToString(SlotT(k), 2) +
               (g_sl[k].state == 2 ? "  [posizione virtuale aperta]" : (g_sl[k].state == 1 ? "  [coppia virtuale in attesa]" : "")) + "\n";
        }
      if(cn > 8)
         sp += "... altri " + IntegerToString(cn - 8) + " concorrenti (classifica completa a fine test)\n";
      Comment(sp);
      return;
     }
   string s = "MultiDayRangeBreakout 3.00  magic " + IntegerToString(MagicNumber) + "\n";
   s += "Ora server " + TimeToString(now, TIME_DATE | TIME_MINUTES) + "  finestra " + StringFormat("%02d:%02d-%02d:%02d", TradeHourStart, TradeMinuteStart, TradeHourEnd, TradeMinuteEnd) +
        (InEntryWindow(now) ? "  (aperta)" : "  (chiusa)") + "\n";
   if(g_rangeDone)
      s += (g_rangeOK ? "Range: " : "Range scartato: ") + g_rangeInfo + "\n";
   else
      s += "Range: non ancora calcolato\n";
   string em = "";
   if(EntryStop)
      em += "stop ";
   if(EntryCandleClose)
      em += "chiusura ";
   if(EntryRetest)
      em += "retest";
   if(EntryRetest && g_armL)
      em += " [armato long]";
   if(EntryRetest && g_armS)
      em += " [armato short]";
   s += "Entrata: " + em + "\n";
   s += "Ordini " + IntegerToString(g_nOrd) + "  posizioni " + IntegerToString(g_nPos) + "  coppie oggi " + IntegerToString(g_pairsToday) +
        "  trade oggi " + IntegerToString(g_tradesToday) + "/" + IntegerToString(MaxTradesPerDay) + "\n";
   s += "Spread " + DoubleToString((SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point, 1) + " punti\n";
   if(g_status != "")
      s += g_status + "\n";
   Comment(s);
  }

//+------------------------------------------------------------------+
//| Nuovo giorno                                                     |
//+------------------------------------------------------------------+
void NewDay(datetime day)
  {
   g_day = day;
   g_rangeDone = false;
   g_rangeOK = false;
   g_upper = 0.0;
   g_lower = 0.0;
   g_rangeInfo = "";
   g_pairsToday = 0;
   g_tradesToday = 0;
   g_failToday = 0;
   g_nextTry = 0;
   g_nextTryM = 0;
   g_armL = false;
   g_armS = false;
   g_candlePend = false;
   g_logOutside = false;
   g_logSpread = false;
   g_logWait = false;
   g_status = "";
   g_nPos = -1;   // forza la rilettura dei contatori dalla storia
   g_nOrd = -1;
   if(SlotScan)
      ScanNewDay(TimeCurrent());
   UpdateRangeLines();
  }

//+------------------------------------------------------------------+
string CheckInputs()
  {
   if(LotSize <= 0.0)
      return "LotSize deve essere > 0";
   if(StopLossPoints <= 0.0)
      return "StopLossPoints deve essere > 0";
   if(UseTakeProfit && TakeProfitPoints <= 0.0)
      return "TakeProfitPoints deve essere > 0";
   if(TradeHourStart < 0 || TradeHourStart > 23 || TradeHourEnd < 0 || TradeHourEnd > 24 || TradeMinuteStart < 0 || TradeMinuteStart > 59 || TradeMinuteEnd < 0 || TradeMinuteEnd > 59)
      return "orario della finestra di entrata non valido";
   if(WinLen() == 0)
      return "la finestra di entrata e' vuota (inizio = fine)";
   if(ExpireExtraMinutes < 0 || WinLen() + ExpireExtraMinutes >= 1440)
      return "ExpireExtraMinutes non valido";
   if(MaxTradesPerDay < 1)
      return "MaxTradesPerDay deve essere >= 1";
   if(!EntryStop && !EntryCandleClose && !EntryRetest)
      return "accendi almeno una modalita' di entrata (EntryStop, EntryCandleClose, EntryRetest)";
   if(RetestTolerancePoints < 0 || RetestMaxDepthPoints < 0)
      return "RetestTolerancePoints e RetestMaxDepthPoints non possono essere negativi";
   if(EntryRetest && PendingOrderOffsetPoints <= RetestTolerancePoints)
      return "con EntryRetest l'offset (PendingOrderOffsetPoints) deve essere maggiore di RetestTolerancePoints: altrimenti il ritorno e' gia' vero alla rottura";
   // --- range: quali sorgenti sono accese
   int nSrc = (UseRangeTime ? 1 : 0) + (UseRangeBars ? 1 : 0) + (UseRangePrevD1 ? 1 : 0);
   bool anySlot = (Slot1 || Slot2 || Slot3 || Slot4 || Slot5 || Slot6 || Slot7 || Slot8 || Slot9 || Slot10 || Slot11 || Slot12);
   if(!SlotScan && nSrc != 1)
      return "EA reale: accendi ESATTAMENTE un range tra UseRangeTime, UseRangeBars e UseRangePrevD1 (ora ne sono accesi " + IntegerToString(nSrc) + "); per confrontarne piu' di uno usa SlotScan";
   if(SlotScan && !((UseRangeTime && anySlot) || UseRangeBars || UseRangePrevD1))
      return "analisi virtuale: accendi almeno un range (UseRangeTime con almeno una fascia Slot1..Slot12, UseRangeBars oppure UseRangePrevD1)";
   if(RangeDaysBack < 0)
      return "RangeDaysBack non puo' essere negativo";
   if(UseRangeBars && RangeBarsLookback < 1)
      return "RangeBarsLookback deve essere >= 1";
   if(UseRangePrevD1 && (RangeDaySpan < 1 || RangeDaysBack < 1))
      return "UseRangePrevD1 richiede RangeDaySpan >= 1 e RangeDaysBack >= 1";
   if(UseRangeTime && !SlotScan && (RangeHourStart < 0 || RangeHourStart > 23 || RangeHourEnd < 0 || RangeHourEnd > 24 || RangeMinuteStart < 0 || RangeMinuteStart > 59 || RangeMinuteEnd < 0 || RangeMinuteEnd > 59))
      return "orario del range per orario (RangeHourStart/Minute..., RangeHourEnd/Minute...) non valido";
   if(UseRangeTime && SlotScan)
     {
      if(SlotFirstHour < 0 || SlotFirstHour > 23)
         return "SlotFirstHour deve essere tra 0 e 23";
      if(SlotLenHours < 1 || SlotLenHours > 12)
         return "SlotLenHours deve essere tra 1 e 12";
     }
   if(SlotScan && SlotMinTrades < 1)
      return "SlotMinTrades deve essere >= 1";
   if(RequireRangeConfirmation && MinRangePoints > MaxRangePoints)
      return "MinRangePoints > MaxRangePoints";
   if(NormVol(LotSize) <= 0.0)
      return "LotSize sotto il volume minimo del simbolo";
   return "";
  }

int OnInit()
  {
   string err = CheckInputs();
   if(err != "")
     {
      Print("Parametri non validi: ", err);
      return INIT_PARAMETERS_INCORRECT;
     }
   g_trade.SetExpertMagicNumber((ulong)MagicNumber);
   g_trade.SetDeviationInPoints((ulong)Slippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_day = 0;
   g_nPos = -1;
   g_nOrd = -1;
   g_pairsToday = 0;
   g_tradesToday = 0;
   g_nextTry = 0;
   g_nextMod = 0;
   g_lastPanel = 0;
   g_barTime = iTime(_Symbol, Timeframe, 0);   // la barra in corso all'avvio non e' una "nuova barra": la prima candela da valutare e' la prossima a chiudere
   g_candlePend = false;
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(StopLossPoints * _Point < stopLvl)
      Print("Attenzione: StopLossPoints e' sotto il livello minimo dei stop del broker (", DoubleToString(stopLvl / _Point, 0), " punti)");
   if(EntryCandleClose && PeriodSeconds(Timeframe) > (WinLen() + ExpireExtraMinutes) * 60)
      Print("Attenzione: la finestra di entrata (", WinLen() + ExpireExtraMinutes, " minuti) e' piu' corta di una candela di ", EnumToString(Timeframe), ": potrebbe non contenere nessuna chiusura di candela e EntryCandleClose non scattare mai");
   string rs = "";   // range accesi
   if(UseRangeTime)
     {
      if(SlotScan)
         rs += "orario (fasce da " + IntegerToString(SlotLenHours) + " ore dalle " + StringFormat("%02d:00", SlotFirstHour) + ") ";
      else
         rs += "orario " + StringFormat("%02d:%02d-%02d:%02d", RangeHourStart, RangeMinuteStart, RangeHourEnd, RangeMinuteEnd) + " ";
     }
   if(UseRangeBars)
      rs += "barre (" + IntegerToString(RangeBarsLookback) + " x " + EnumToString(Timeframe) + ") ";
   if(UseRangePrevD1)
      rs += "D1 precedenti (" + IntegerToString(RangeDaySpan) + " giorni) ";
   if(SlotScan)
     {
      ScanInit();
      Print("MultiDayRangeBreakout 3.00 su ", _Symbol, ": ANALISI VIRTUALE, ", ScanActive(), " concorrenti (range x modalita' di entrata). Range: ", rs, "| entrata: ", (EntryStop ? "stop " : ""), (EntryCandleClose ? "chiusura " : ""), (EntryRetest ? "retest" : ""),
            " | giorno di riferimento del range RangeDaysBack ", RangeDaysBack, ". NESSUN ordine reale verra' aperto: la classifica si scrive a fine test.");
      return INIT_SUCCEEDED;
     }
   Print("MultiDayRangeBreakout 3.00 su ", _Symbol, ": entrata ", (EntryStop ? "stop " : ""), (EntryCandleClose ? "chiusura " : ""), (EntryRetest ? "retest " : ""), "| range ", rs, "| finestra ", StringFormat("%02d:%02d-%02d:%02d", TradeHourStart, TradeMinuteStart, TradeHourEnd, TradeMinuteEnd),
         " ora server, SL ", DoubleToString(StopLossPoints, 0), " TP ", (UseTakeProfit ? DoubleToString(TakeProfitPoints, 0) : "nessuno"), " punti");
   return INIT_SUCCEEDED;
  }

// valore del tester: nell'analisi virtuale e' il punteggio del concorrente migliore (per ottimizzare gli altri parametri su di esso); altrimenti 0
double OnTester()
  {
   if(SlotScan)
      return ScanBestScore();
   return 0.0;
  }

void OnDeinit(const int reason)
  {
   if(SlotScan && !MQLInfoInteger(MQL_OPTIMIZATION))
      ScanReport();
   Comment("");
   ObjectDelete(0, LineName("hi"));
   ObjectDelete(0, LineName("lo"));
  }

void OnTick()
  {
   datetime now = TimeCurrent();
   datetime day = DayStart(now);
   if(day != g_day)
      NewDay(day);
   bool newBar = false;
   if(SlotScan || EntryCandleClose)
     {
      datetime bt = iTime(_Symbol, Timeframe, 0);
      if(bt != 0 && bt != g_barTime)
        {
         newBar = true;
         g_barTime = bt;
        }
     }
   if(SlotScan)
     {
      ScanTick(now, newBar);
      UpdatePanel(now);
      return;
     }
   SyncCounters(now);
   ManageOrders(now);
   ManagePositions(now);
   TryPlaceSetup(now);
   TryMarketEntry(now, newBar);
   UpdatePanel(now);
  }
//+------------------------------------------------------------------+
