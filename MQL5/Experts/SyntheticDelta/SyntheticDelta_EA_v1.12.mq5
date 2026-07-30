//+------------------------------------------------------------------+
//|                                    SyntheticDelta_EA_v1.12.mq5   |
//+------------------------------------------------------------------+
//| STRATEGIA                                                        |
//| ---------                                                        |
//| "Synthetic Delta": stima uno pseudo order-flow delta usando solo |
//| dati OHLC + tick volume (nessun vero volume/DOM), combinando:    |
//|   - posizione della chiusura nel range della barra (pressione    |
//|     buy/sell intrabarra)                                         |
//|   - distanza high/low da una EMA (forza bulls/bears alla Elder)  |
//|   - peso volumetrico (tick volume vs media)                      |
//| Il segnale è filtrato da ADX (evita mercati laterali), S/R       |
//| (evita entrate nel mezzo del range), e opzionalmente da un       |
//| regime di volatilità calcolato internamente (ATR% + volatilità   |
//| di Parkinson, percentile rank su finestra mobile).               |
//|                                                                   |
//| NOVITA' v1.11: Expansion Candle Filter                          |
//| ---------------------------------------                          |
//| Modalità di segnale ALTERNATIVA al Synthetic Delta: quando una    |
//| candela chiusa mostra un True Range anomalo rispetto al suo ATR   |
//| (espansione), la direzione del trade viene decisa dal COLORE      |
//| della candela di conferma (bull=BUY, bear=SELL), con un offset    |
//| configurabile di quante barre attendere dopo il trigger prima di  |
//| leggere la direzione. Passa comunque per gli stessi filtri ADX e  |
//| S/R del motore core, e per il filtro di regime volatilità se      |
//| attivo: nessuna duplicazione di logica, solo una sorgente di      |
//| direzione diversa.                                                 |
//|                                                                   |
//| NOTE METODOLOGICHE (lette prima di ottimizzare)                  |
//| ------------------------------------------------------------     |
//| 1. Tutti i calcoli usano la barra CHIUSA idx=1 -> no repaint/     |
//|    look-ahead. Verificato nel motore delta, nel filtro            |
//|    volatilità e nel filtro expansion candle.                      |
//| 2. Il tick_volume su forex/CFD NON è volume reale: è conteggio   |
//|    tick. Il "peso volumetrico" è quindi una proxy debole, non    |
//|    order flow vero. Trattalo come rumore attenuato, non come     |
//|    segnale primario.                                              |
//| 3. Il fitness in OnTester() (sharpe*0.4 + winrate*0.6) è         |
//|    un proxy grezzo: non penalizza il numero di trade (rischio    |
//|    overfitting su pochi trade fortunati) e non usa un vero       |
//|    Sharpe (profit/maxDD non è volatility-adjusted). Da rivedere  |
//|    prima di un walk-forward serio.                                |
//| 4. Expansion Candle Filter con offset>0: se il grafico perde una  |
//|    barra (es. riavvio EA, gap di connessione) durante l'attesa    |
//|    della conferma, lo stato pending viene scartato in sicurezza   |
//|    (nessuna entrata "fantasma" su barra sbagliata). Lo stato      |
//|    pending NON persiste tra riavvii dell'EA (variabile in RAM).   |
//+------------------------------------------------------------------+
#property copyright "SyntheticDelta EA"
#property version   "1.12"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| STATISTICHE TESTER                                               |
//| FIX v1.12: rimosse le #define custom di v1.11, i cui valori       |
//| numerici NON coincidevano con l'enum reale ENUM_STATISTICS di     |
//| MQL5 (STAT_PROFIT=1 leggeva STAT_WITHDRAWAL, ecc.) -> la fitness   |
//| di OnTester era calcolata su statistiche errate. Ora si usano     |
//| direttamente i nomi nativi dell'enum (vedi OnTester in fondo).    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| ENUM GLOBALI                                                      |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
{
   LOT_FIXED       = 0,  // Lotto fisso, ignora capitale ed equity
   LOT_BALANCE_PCT = 1,  // Rischio % calcolato sul Balance (stabile, non risente di floating P/L)
   LOT_EQUITY_PCT  = 2   // Rischio % calcolato sull'Equity (più aggressivo, si adatta in tempo reale)
};

enum ENUM_VOL_REGIME
{
   VOL_LOW      = 0,  // Percentile volatilità < LowTh   -> mercato "quieto"
   VOL_NORMAL   = 1,  // LowTh <= Percentile < HighTh     -> condizioni tipiche
   VOL_HIGH     = 2,  // HighTh <= Percentile < ExtremeTh -> volatilità elevata
   VOL_EXTREME  = 3   // Percentile >= ExtremeTh          -> coda di distribuzione, evento anomalo
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "=== SYNTHETIC DELTA CORE ==="
input int    EmaPeriod        = 13;    // Periodo EMA di riferimento per bulls/bears power. Più basso = più reattivo ma più rumoroso.
input int    VolAvgPeriod     = 20;    // Finestra media tick_volume per il peso volumetrico. Attenzione: tick volume, non volume reale.
input double SignalThreshold  = 0.15;  // Soglia minima del delta normalizzato (range teorico ~[-1,1]) per generare un segnale. Aumentarla riduce frequenza ma aumenta selettività.

input group "=== ATR ==="
input bool   UseATRFilter     = true;  // Se true, ATR viene usato anche come soglia di prossimità nel filtro S/R (vedi sotto). L'ATR come VALIDITA' del segnale (currentATR>0) resta invece sempre obbligatorio, non disattivabile da qui.
input int    ATR_Period       = 14;    // Periodo ATR usato dal motore core (validità dati + prossimità S/R). Timeframe = quello del grafico (PERIOD_CURRENT).

input group "=== ADX TREND FILTER ==="
input bool   UseADXFilter     = true;  // Filtra i segnali in mercati laterali. Consigliato attivo: il delta sintetico produce falsi segnali frequenti in range stretto.
input int    ADX_Period       = 14;    // Periodo ADX standard.
input double ADX_MinLevel     = 20.0;  // Soglia minima ADX per considerare il mercato "in trend". Sotto questa soglia il segnale viene scartato.

input group "=== SUPPORT/RESISTANCE FILTER ==="
input bool   UseSRFilter      = true;  // Richiede che il prezzo sia vicino a un livello S/R (o in breakout) per validare l'entrata. Riduce i trade "nel vuoto" a metà range.
input int    SR_Lookback      = 15;    // Numero di barre (precedenti a quella corrente) su cui calcolare massimo/minimo come S/R.
input double SR_Proximity     = 0.5;   // Moltiplicatore di ATR che definisce "vicino" al livello S/R. Ignorato se UseATRFilter=false (in quel caso S/R valido solo su breakout puro).

input group "=== VOLATILITY REGIME FILTER (integrato) ==="
input bool   Inp_UseVolFilter    = false; // Master switch del filtro. Se false, tutto il resto del gruppo è ignorato (nessun costo computazionale extra).
input int    Inp_VolAtrLen       = 14;    // Lunghezza ATR usata SOLO per calcolare la componente ATR% del regime volatilità (handle indipendente da ATR_Period del core).
input int    Inp_VolLookback     = 100;   // Ampiezza finestra su cui viene calcolato il percentile rank della volatilità composita. Finestra più ampia = regime più stabile ma meno reattivo ai cambi di regime recenti.
input int    Inp_VolEmaSmooth    = 3;     // Periodo EMA di smoothing sulla volatilità composita (ATR% + Parkinson vol), riduce il rumore prima del ranking percentile.
input int    Inp_VolLowTh        = 30;    // Percentile sotto il quale il regime è classificato LOW.
input int    Inp_VolHighTh       = 70;    // Percentile sopra il quale il regime è classificato HIGH (fino a ExtremeTh).
input int    Inp_VolExtremeTh    = 90;    // Percentile sopra il quale il regime è classificato EXTREME (coda della distribuzione).
input bool   Inp_AllowTradeLOW      = true;  // Consenti apertura trade quando il regime rilevato è LOW.
input bool   Inp_AllowTradeNORMAL   = true;  // Consenti apertura trade quando il regime rilevato è NORMAL.
input bool   Inp_AllowTradeHIGH     = false; // Consenti apertura trade quando il regime rilevato è HIGH. Di default disattivo: alta volatilità spesso significa slippage e stop hunting più aggressivi.
input bool   Inp_AllowTradeEXTREME  = false; // Consenti apertura trade quando il regime rilevato è EXTREME. Di default disattivo: eventi di coda, execution risk elevato specie su FP Markets in news window.
input bool   Inp_RequireVolIncreasing = false; // Se true, scarta il segnale quando la volatilità sta CALANDO rispetto alla barra chiusa precedente (percentile attuale <= percentile precedente). Utile per evitare entrate mentre un regime alto sta esaurendosi.

input group "=== EXPANSION CANDLE FILTER (sorgente segnale alternativa) ==="
input bool   Inp_UseExpansionFilter = false; // Master switch. Se true, la DIREZIONE del trade viene decisa dal colore della candela di conferma dopo un'espansione TR/ATR, ANZICHE' dal Synthetic Delta. Passa comunque per i filtri ADX/S/R/Volatilità.
input int    Inp_ExpATRPeriod       = 14;    // Periodo ATR dedicato al calcolo TR/ATR, handle indipendente da ATR_Period del core e da Inp_VolAtrLen.
input double Inp_ExpThreshold       = 1.8;   // Soglia TR/ATR sopra la quale la barra chiusa è considerata "in espansione" (stesso default dell'indicatore VolatilityStateIndicator_Ferro).
input int    Inp_ExpConfirmOffset   = 0;     // Quante barre chiuse attendere DOPO quella di espansione prima di leggere la direzione. 0 = direzione letta sulla candela di espansione stessa. 1 = sulla barra successiva. 2 = due barre dopo. Ecc.

input group "=== MONEY MANAGEMENT ==="
input int    Inp_LotMode      = 0;     // Vedi ENUM_LOT_MODE: 0=Fisso, 1=%Balance, 2=%Equity.
input double Inp_LotSize      = 0.01;  // Lotto fisso, usato se Inp_LotMode=0, oppure come fallback se il calcolo dinamico fallisce (tickValue/tickSize non disponibili).
input double Inp_RiskPct      = 1.0;   // % di capitale (Balance o Equity a seconda del modo) rischiata per trade se Inp_LotMode != 0. Il rischio è calcolato sullo Stop Loss in PUNTI FISSI (Inp_StopLoss), NON sull'SL dinamico ATR anche se Inp_UseATR_SLTP=true -> possibile disallineamento tra rischio reale e rischio target, vedi nota sotto CalcLotSize.
input int    Inp_StopLoss     = 50;    // SL in punti. Usato per l'esecuzione se Inp_UseATR_SLTP=false, ed è SEMPRE la base del calcolo lotto in CalcLotSize() indipendentemente da Inp_UseATR_SLTP.
input int    Inp_TakeProfit   = 100;   // TP in punti. Usato solo se Inp_UseATR_SLTP=false e Inp_UseTP=true.
input bool   Inp_UseTP        = true;  // Se false, il trade viene aperto senza Take Profit (uscita solo via SL/trailing).
input int    Inp_MagicNumber  = 11111; // Identificativo univoco per distinguere le posizioni di questo EA da altri EA/trade manuali sullo stesso conto.

input group "=== SL/TP DINAMICI SU ATR ==="
input bool   Inp_UseATR_SLTP  = false; // Se true, SL/TP in esecuzione sono multipli di ATR invece che punti fissi. ATTENZIONE: non influenza il position sizing (vedi Inp_RiskPct sopra).
input double Inp_ATR_SL_Mult  = 1.5;   // Moltiplicatore ATR per lo Stop Loss.
input double Inp_ATR_TP_Mult  = 3.0;   // Moltiplicatore ATR per il Take Profit. Rapporto TP/SL = 2:1 con i default -> coerente con winrate atteso <50%.
input ENUM_TIMEFRAMES Inp_ATR_SLTP_TF     = PERIOD_CURRENT; // Timeframe su cui calcolare l'ATR per SL/TP, indipendente dal TF operativo del grafico.
input int              Inp_ATR_SLTP_Period = 14;             // Periodo ATR per SL/TP. Se il TF scelto è inferiore a quello operativo, in backtest servono dati storici di quel TF già disponibili nel tester, altrimenti l'ATR resta 0 e scatta il fallback a punti fissi (vedi OpenTrade).

input group "=== TRAILING STOP ==="
input bool   Inp_UseTrailing      = true; // Attiva/disattiva il trailing stop lineare a step.
input int    Inp_TrailingStart    = 30;   // Profitto minimo in punti prima che il trailing inizi a muovere lo SL.
input int    Inp_TrailingStop     = 20;   // Distanza (in punti) mantenuta tra prezzo corrente e nuovo SL.
input int    Inp_TrailingStep     = 5;    // Incremento minimo (in punti) richiesto prima di aggiornare nuovamente lo SL, evita modifiche eccessive/spam di richieste al broker.

input group "=== FILTRO 1 TRADE PER ORA ==="
input bool   Inp_OneTradePerHour  = true; // Se true, blocca nuove entrate nella stessa ora solare in cui è già stato aperto un trade (chiave anno/mese/giorno/ora).

input group "=== FILTRI ORARI (INCLUSIVI) ==="
input bool   Inp_UseTimeFilter1   = false; // Attiva la prima fascia oraria di trading consentita.
input int    Inp_StartHour1       = 8;     // Ora inizio fascia 1 (server time del broker, non il tuo fuso).
input int    Inp_StartMin1        = 0;     // Minuto inizio fascia 1.
input int    Inp_EndHour1         = 12;    // Ora fine fascia 1.
input int    Inp_EndMin1          = 0;     // Minuto fine fascia 1.
input bool   Inp_UseTimeFilter2   = false; // Attiva la seconda fascia oraria di trading consentita.
input int    Inp_StartHour2       = 14;    // Ora inizio fascia 2.
input int    Inp_StartMin2        = 30;    // Minuto inizio fascia 2.
input int    Inp_EndHour2         = 18;    // Ora fine fascia 2.
input int    Inp_EndMin2          = 0;     // Minuto fine fascia 2. Se entrambe le fasce sono attive, il trade è permesso se rientra in ALMENO UNA delle due (OR logico, vedi IsTimeFilterOK).

input group "=== RISK MANAGEMENT ==="
input bool   Inp_UseMaxTrades     = true; // Se true, limita il numero di posizioni simultanee per direzione (vedi sotto). Consigliato sempre attivo.
input int    Inp_MaxBuyTrades     = 1;    // Numero massimo di posizioni BUY aperte contemporaneamente da questo EA (stesso Magic Number).
input int    Inp_MaxSellTrades    = 1;    // Numero massimo di posizioni SELL aperte contemporaneamente.
input int    Inp_Slippage         = 30;   // Deviazione massima in punti tollerata tra prezzo richiesto ed eseguito.

input group "=== SPREAD FILTER ==="
input bool   Inp_UseSpreadFilter  = true; // Blocca nuove entrate se lo spread corrente è eccessivo (tipico durante news o bassa liquidità).
input int    Inp_MaxSpreadPoints  = 30;   // Spread massimo tollerato, in punti. Da calibrare in base allo strumento: 30 punti su un major FX è ampio, su un indice/CFD può essere stretto.

input group "=== DEBUG ==="
input bool   Inp_DebugMode        = true;  // Stampa log dettagliati in Print() ad ogni barra/evento. Disattivare in produzione live per non intasare il log del terminale.
input bool   Inp_EnableAlerts     = false; // Genera un Alert() popup/sonoro all'apertura di ogni trade.

//+------------------------------------------------------------------+
//| HANDLES INDICATORI                                                |
//+------------------------------------------------------------------+
int EmaHandle      = INVALID_HANDLE;  // EMA core per bulls/bears power
int ATRHandle      = INVALID_HANDLE;  // ATR core (validità segnale + prossimità S/R)
int ADXHandle      = INVALID_HANDLE;  // ADX filtro trend
int VolATRHandle   = INVALID_HANDLE;  // ATR dedicato al filtro di regime volatilità (handle separato, periodo indipendente)
int SLTP_ATRHandle = INVALID_HANDLE;  // ATR dedicato a SL/TP dinamici (handle separato, TF/periodo indipendenti)
int ExpATRHandle   = INVALID_HANDLE;  // ATR dedicato al filtro Expansion Candle (handle separato, periodo indipendente)

//+------------------------------------------------------------------+
//| VARIABILI GLOBALI DI STATO                                        |
//+------------------------------------------------------------------+
datetime lastBarTime      = 0;   // Timestamp ultima barra processata, evita ricalcoli multipli sullo stesso tick
int      totalTrades      = 0;   // Contatore totale trade aperti dalla sessione EA
int      lastTradeHour    = -1;  // Ultima ora in cui è stato aperto un trade
datetime lastTradeDayTime = 0;   // Chiave anno/mese/giorno/ora dell'ultimo trade, per il filtro OneTradePerHour

// Statistiche di performance aggregate per ora del giorno (0-23), usate per il report a fine test
double   hourPnL    [24];
int      hourTrades [24];
int      hourWins   [24];

#define MAX_TRACK 200            // Capacità massima del buffer di tracking trade->ora apertura
ulong    trackedTicket[MAX_TRACK]; // Ticket (position id) monitorati per l'attribuzione PnL orario
int      trackedHour  [MAX_TRACK]; // Ora di apertura corrispondente al ticket
int      trackedCount = 0;         // Numero di slot attualmente in uso

// Stato del filtro Expansion Candle: gestisce l'attesa della barra di conferma
// quando Inp_ExpConfirmOffset > 0. Non persiste tra riavvii dell'EA (in RAM).
bool     g_expPending     = false; // true = espansione rilevata, in attesa della barra di conferma
datetime g_expPendingTime = 0;     // Timestamp della barra chiusa in cui è stata rilevata l'espansione (ancora di riferimento per iBarShift)

//+------------------------------------------------------------------+
//| STRUTTURE                                                         |
//+------------------------------------------------------------------+
struct DeltaSignal
{
   int    direction;        // 1=BUY, -1=SELL, 0=nessun segnale
   double normalizedDelta;  // Valore del delta sintetico normalizzato, range teorico ~[-1,1]. Non usato dal ramo Expansion Candle (resta 0).
   string info;             // Stringa diagnostica per il log (motivo accept/reject)
};

//+------------------------------------------------------------------+
//| PickFilling (FIX v1.12)                                            |
//| Restituisce la modalita' di riempimento supportata dal simbolo    |
//| corrente, leggendo la bitmask SYMBOL_FILLING_MODE. Preferenza:     |
//| FOK -> IOC -> RETURN. Evita il rifiuto ordini (retcode 10030) su   |
//| broker ECN come FP Markets che non espongono FOK su ogni simbolo.  |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING PickFilling()
{
   long modes = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((modes & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((modes & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("============================================================");
   Print("SyntheticDelta EA v1.12 - Standalone + Volatility Regime + Expansion Candle Filter");
   Print("============================================================");

   trade.SetExpertMagicNumber(Inp_MagicNumber);
   trade.SetDeviationInPoints(Inp_Slippage);
   // FIX v1.12: filling mode rilevato dal simbolo invece di FOK hardcoded.
   // FP Markets (ECN/Raw) non sempre accetta FOK -> in live ordini rifiutati
   // (retcode 10030 "Unsupported filling mode"). PickFilling() sceglie la
   // modalita' effettivamente supportata dal simbolo corrente.
   trade.SetTypeFilling(PickFilling());
   trade.SetAsyncMode(false);

   EmaHandle = iMA(_Symbol, PERIOD_CURRENT, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(EmaHandle == INVALID_HANDLE)
   { Print("Errore EMA handle: ", GetLastError()); return INIT_FAILED; }

   ATRHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   if(ATRHandle == INVALID_HANDLE)
   { Print("Errore ATR handle: ", GetLastError()); return INIT_FAILED; }

   if(UseADXFilter)
   {
      ADXHandle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);
      if(ADXHandle == INVALID_HANDLE)
      { Print("Errore ADX handle: ", GetLastError()); return INIT_FAILED; }
   }

   if(Inp_UseVolFilter)
   {
      VolATRHandle = iATR(_Symbol, PERIOD_CURRENT, Inp_VolAtrLen);
      if(VolATRHandle == INVALID_HANDLE)
      { Print("Errore Vol-ATR handle: ", GetLastError()); return INIT_FAILED; }
   }

   if(Inp_UseExpansionFilter)
   {
      ExpATRHandle = iATR(_Symbol, PERIOD_CURRENT, Inp_ExpATRPeriod);
      if(ExpATRHandle == INVALID_HANDLE)
      { Print("Errore Exp-ATR handle: ", GetLastError()); return INIT_FAILED; }
      Print("Expansion Candle Filter: ON | Threshold TR/ATR=", DoubleToString(Inp_ExpThreshold,2),
            " | ConfirmOffset=", Inp_ExpConfirmOffset,
            " | Direzione trade decisa dal colore candela, NON dal Synthetic Delta");
   }

   if(Inp_UseATR_SLTP)
   {
      SLTP_ATRHandle = iATR(_Symbol, Inp_ATR_SLTP_TF, Inp_ATR_SLTP_Period);
      if(SLTP_ATRHandle == INVALID_HANDLE)
      { Print("Errore SLTP-ATR handle: ", GetLastError()); return INIT_FAILED; }
      Print("SL/TP ATR: TF=", EnumToString(Inp_ATR_SLTP_TF), " Period=", Inp_ATR_SLTP_Period,
            " | ATTENZIONE: se il TF e' piu' basso di quello operativo, in backtest servono");
      Print("            i dati storici di quel TF caricati/disponibili nel tester, altrimenti");
      Print("            l'ATR ritornera' 0 finche' non sono disponibili -> fallback a punti fissi.");
   }

   ArrayInitialize(hourPnL,    0.0);
   ArrayInitialize(hourTrades, 0);
   ArrayInitialize(hourWins,   0);
   ArrayInitialize(trackedTicket, 0);
   ArrayInitialize(trackedHour,  -1);
   g_expPending     = false;
   g_expPendingTime = 0;

   Print("Indicatori inizializzati | Symbol=", _Symbol, " TF=", EnumToString(PERIOD_CURRENT));
   Print("Vol Filter: ", Inp_UseVolFilter ? "ON" : "OFF",
         " | Allow LOW=", Inp_AllowTradeLOW,
         " NORMAL=", Inp_AllowTradeNORMAL,
         " HIGH=", Inp_AllowTradeHIGH,
         " EXTREME=", Inp_AllowTradeEXTREME);
   Print("============================================================\n");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(EmaHandle      != INVALID_HANDLE) IndicatorRelease(EmaHandle);
   if(ATRHandle      != INVALID_HANDLE) IndicatorRelease(ATRHandle);
   if(ADXHandle      != INVALID_HANDLE) IndicatorRelease(ADXHandle);
   if(VolATRHandle   != INVALID_HANDLE) IndicatorRelease(VolATRHandle);
   if(SLTP_ATRHandle != INVALID_HANDLE) IndicatorRelease(SLTP_ATRHandle);
   if(ExpATRHandle   != INVALID_HANDLE) IndicatorRelease(ExpATRHandle);
   Print("EA chiuso | Trades totali: ", totalTrades);
   PrintHourlyStats();
}

//+------------------------------------------------------------------+
//| OnTick - loop principale, eseguito su barra chiusa (one-shot)    |
//+------------------------------------------------------------------+
void OnTick()
{
   if(Inp_UseTrailing) ManageTrailingStop();
   UpdateClosedTradePnL();

   // Guardia "una volta per barra": tutta la logica sotto opera solo al cambio barra
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   //--- Filtro spread
   if(Inp_UseSpreadFilter)
   {
      double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID))
                      / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      if(spread > Inp_MaxSpreadPoints)
      { if(Inp_DebugMode) Print("Spread alto: ", spread, " pts - skip"); return; }
   }

   if(!IsTimeFilterOK()) return;

   //--- Filtro 1 trade per ora
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   int currentHour = dtNow.hour;

   if(Inp_OneTradePerHour)
   {
      datetime hourKey = (datetime)(dtNow.year * 1000000L
                                  + dtNow.mon  * 10000L
                                  + dtNow.day  * 100L
                                  + dtNow.hour);
      if(lastTradeDayTime == hourKey)
      {
         if(Inp_DebugMode) Print("Trade gia' aperto ora [", currentHour, ":xx] - skip");
         return;
      }
   }

   //--- Sorgente del segnale: Synthetic Delta (default) OPPURE Expansion Candle
   //    (Inp_UseExpansionFilter sostituisce la sorgente della DIREZIONE, non i filtri
   //    ADX/S/R/Volatilità che restano applicati identicamente in entrambi i casi)
   DeltaSignal sig;
   sig.direction       = 0;
   sig.normalizedDelta = 0.0;
   sig.info            = "";

   if(Inp_UseExpansionFilter)
      ProcessExpansionSignal(sig);
   else
      sig = CalculateDeltaSignal();

   if(Inp_DebugMode)
      Print("Ora=", currentHour,
            " | dir=",   sig.direction,
            " | delta=", DoubleToString(sig.normalizedDelta, 4),
            " | ", sig.info);

   //--- Filtro regime di volatilità (integrato nativamente, no iCustom)
   bool volOK = true;
   if(Inp_UseVolFilter)
   {
      ENUM_VOL_REGIME regime;
      double pct, pctPrev;
      if(!GetVolatilityRegime(regime, pct, pctPrev))
      {
         if(Inp_DebugMode) Print("VolFilter: dati insufficienti - skip");
         return;
      }
      volOK = (regime == VOL_LOW     && Inp_AllowTradeLOW)     ||
              (regime == VOL_NORMAL  && Inp_AllowTradeNORMAL)  ||
              (regime == VOL_HIGH    && Inp_AllowTradeHIGH)    ||
              (regime == VOL_EXTREME && Inp_AllowTradeEXTREME);

      //--- Richiede volatilità in AUMENTO rispetto alla barra chiusa precedente
      //    (scarta il segnale se la volatilità sta calando, es. alta->bassa)
      bool volTrendOK = true;
      if(Inp_RequireVolIncreasing)
         volTrendOK = (pct > pctPrev);

      volOK = volOK && volTrendOK;

      if(Inp_DebugMode)
         Print("VolRegime=", EnumToString(regime),
               " pct=", DoubleToString(pct, 1),
               " pctPrev=", DoubleToString(pctPrev, 1),
               " trendOK=", volTrendOK,
               " allowed=", volOK);
   }
   if(!volOK) return;

   //--- Esecuzione entrata
   if(sig.direction == 1)
   {
      if(!Inp_UseMaxTrades || CountOpenTrades(ORDER_TYPE_BUY) < Inp_MaxBuyTrades)
      {
         ulong ticket = 0;
         if(OpenTrade(ORDER_TYPE_BUY, ticket))
         { RegisterTradeHour(ticket, currentHour); SetHourLock(dtNow); }
      }
      else if(Inp_DebugMode) Print("MaxBuyTrades raggiunto - BUY bloccato");
   }
   else if(sig.direction == -1)
   {
      if(!Inp_UseMaxTrades || CountOpenTrades(ORDER_TYPE_SELL) < Inp_MaxSellTrades)
      {
         ulong ticket = 0;
         if(OpenTrade(ORDER_TYPE_SELL, ticket))
         { RegisterTradeHour(ticket, currentHour); SetHourLock(dtNow); }
      }
      else if(Inp_DebugMode) Print("MaxSellTrades raggiunto - SELL bloccato");
   }
}

//+------------------------------------------------------------------+
//| CalculateDeltaSignal                                              |
//| Calcola il delta sintetico sulla barra chiusa idx=1 e applica     |
//| in cascata i filtri ADX e S/R. Ritorna direction=0 se uno         |
//| qualsiasi dei controlli fallisce (dati insufficienti, ADX basso,  |
//| S/R non valido, |delta| < soglia).                                |
//+------------------------------------------------------------------+
DeltaSignal CalculateDeltaSignal()
{
   DeltaSignal sig;
   sig.direction       = 0;
   sig.normalizedDelta = 0.0;
   sig.info            = "";

   int minBars = MathMax(MathMax(EmaPeriod, VolAvgPeriod),
                         MathMax(ATR_Period, SR_Lookback)) + 5;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, minBars + 20, rates);
   if(copied < minBars) return sig;

   double emaArr[];
   ArraySetAsSeries(emaArr, true);
   if(CopyBuffer(EmaHandle, 0, 0, minBars + 5, emaArr) <= 0) return sig;

   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(ATRHandle, 0, 0, minBars + 5, atrArr) <= 0) return sig;

   double adxArr[];
   if(UseADXFilter)
   {
      ArraySetAsSeries(adxArr, true);
      if(CopyBuffer(ADXHandle, 0, 0, minBars + 5, adxArr) <= 0) return sig;
   }

   int idx = 1; // barra chiusa, no look-ahead

   double high_i  = rates[idx].high;
   double low_i   = rates[idx].low;
   double close_i = rates[idx].close;
   double range   = high_i - low_i;
   if(range <= 0.0) return sig;

   double ema     = emaArr[idx];
   double tickVol = (double)rates[idx].tick_volume;
   if(tickVol <= 0.0) return sig;

   // Validità ATR: SEMPRE obbligatoria (fedele all'indicatore originale,
   // che non prevede alcun modo di disattivare questo controllo dati)
   double currentATR = atrArr[idx];
   if(currentATR <= 0.0) return sig;

   // Pressione buy/sell = dove chiude il prezzo dentro il range della barra
   double fracBuy  = (close_i - low_i)  / range;
   double fracSell = (high_i  - close_i) / range;

   // Forza bulls/bears alla Elder, normalizzata sul range della barra
   double bullsPower = high_i - ema;
   double bearsPower = ema - low_i;
   double bullsNorm  = bullsPower / range;
   double bearsNorm  = bearsPower / range;

   // Peso volumetrico: tick_volume corrente vs media mobile, cappato a 3x
   // per evitare che un singolo outlier domini il delta
   double volSum = 0.0;
   int    volCount = 0;
   for(int j = idx; j < idx + VolAvgPeriod && j < copied; j++)
   {
      volSum += (double)rates[j].tick_volume;
      volCount++;
   }
   double volAvg    = (volCount > 0) ? volSum / volCount : tickVol;
   double volWeight = (volAvg > 0.0) ? tickVol / volAvg : 1.0;
   volWeight = MathMin(volWeight, 3.0);

   double bullsStrength   = fracBuy  * (1.0 + bullsNorm) * volWeight;
   double bearsStrength   = fracSell * (1.0 + bearsNorm) * volWeight;
   double synDelta        = bullsStrength - bearsStrength;
   double normalizedDelta = synDelta / 6.0;  // 6.0 = fattore di scala empirico per riportare il range a ~[-1,1]

   sig.normalizedDelta = normalizedDelta;

   //--- Filtro ADX: scarta se il mercato non è in trend
   if(UseADXFilter)
   {
      double adxVal = adxArr[idx];
      if(adxVal < ADX_MinLevel)
      { sig.info = StringFormat("ADX=%.1f < %.1f (ranging, skip)", adxVal, ADX_MinLevel); return sig; }
      sig.info += StringFormat("ADX=%.1f ", adxVal);
   }

   //--- Filtro Supporto/Resistenza: richiede prossimità a un livello o breakout
   if(UseSRFilter && idx + SR_Lookback < copied)
   {
      double resistance = rates[idx + 1].high;
      double support    = rates[idx + 1].low;

      for(int k = idx + 1; k < idx + 1 + SR_Lookback && k < copied; k++)
      {
         if(rates[k].high > resistance) resistance = rates[k].high;
         if(rates[k].low  < support)    support    = rates[k].low;
      }

      bool nearResistance = false;
      bool nearSupport    = false;
      double proximityThreshold = 0.0;
      if(UseATRFilter)
      {
         proximityThreshold = currentATR * SR_Proximity;
         nearResistance = MathAbs(close_i - resistance) <= proximityThreshold;
         nearSupport    = MathAbs(close_i - support)    <= proximityThreshold;
      }
      bool aboveR = close_i > resistance;
      bool belowS = close_i < support;

      // Senza ATR: S/R valido solo su breakout (nessun concetto di "vicinanza")
      bool srValid = nearResistance || nearSupport || aboveR || belowS;
      if(!srValid)
      {
         sig.info += StringFormat("S/R skip (R=%.5f S=%.5f prox=%.5f)", resistance, support, proximityThreshold);
         return sig;
      }
      sig.info += StringFormat("S/R OK (R=%.5f S=%.5f) ", resistance, support);
   }

   //--- Decisione finale sulla soglia del delta
   if(normalizedDelta > SignalThreshold)
   {
      sig.direction = 1;
      sig.info += StringFormat("BUY delta=%.4f > %.4f", normalizedDelta, SignalThreshold);
   }
   else if(normalizedDelta < -SignalThreshold)
   {
      sig.direction = -1;
      sig.info += StringFormat("SELL delta=%.4f < -%.4f", normalizedDelta, SignalThreshold);
   }
   else
   {
      sig.info += StringFormat("No signal delta=%.4f (|d|<%.4f)", normalizedDelta, SignalThreshold);
   }

   return sig;
}

//+------------------------------------------------------------------+
//| ProcessExpansionSignal                                             |
//| Sorgente di segnale alternativa al Synthetic Delta.                |
//| 1) Rileva l'espansione (TR/ATR > soglia) sulla barra chiusa idx=1. |
//| 2) Se Inp_ExpConfirmOffset=0, legge subito la direzione dal colore |
//|    di QUELLA stessa candela.                                       |
//| 3) Se Inp_ExpConfirmOffset>0, memorizza lo stato "pending" e        |
//|    attende che si chiudano esattamente Inp_ExpConfirmOffset barre  |
//|    aggiuntive, poi legge la direzione dal colore della barra di    |
//|    conferma raggiunta. Se una barra viene persa (gap/riavvio),     |
//|    lo stato pending viene scartato per sicurezza (no look-ahead,   |
//|    no entrate su barra sbagliata).                                 |
//| Applica gli STESSI filtri ADX/S/R del motore core (EvaluateCandle- |
//| Direction), quindi nessuna duplicazione di logica.                 |
//+------------------------------------------------------------------+
void ProcessExpansionSignal(DeltaSignal &sig)
{
   sig.direction       = 0;
   sig.normalizedDelta = 0.0;
   sig.info            = "";

   int minBars = MathMax(SR_Lookback, 5) + 10;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, minBars, r) < 5)
   { sig.info = "ExpFilter: dati insufficienti"; return; }

   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(ExpATRHandle, 0, 0, 5, atrArr) <= 0)
   { sig.info = "ExpFilter: Exp-ATR non disponibile"; return; }

   double adxArr[];
   if(UseADXFilter)
   {
      ArraySetAsSeries(adxArr, true);
      if(CopyBuffer(ADXHandle, 0, 0, 5, adxArr) <= 0)
      { sig.info = "ExpFilter: ADX non disponibile"; return; }
   }

   //--- CASO A: siamo in attesa della barra di conferma da un'espansione precedente
   if(g_expPending)
   {
      int shift = iBarShift(_Symbol, PERIOD_CURRENT, g_expPendingTime, true);
      if(shift < 0)
      {
         // Barra di riferimento non trovata (storico insufficiente/gap) -> annulla in sicurezza
         g_expPending = false;
         sig.info = "ExpFilter: barra di riferimento persa - pending annullato";
         return;
      }
      if(shift > Inp_ExpConfirmOffset + 1)
      {
         // Abbiamo superato la barra attesa (es. EA fermo per più barre) -> annulla, non recuperare a posteriori
         g_expPending = false;
         sig.info = "ExpFilter: offset saltato (gap) - pending annullato";
         return;
      }
      if(shift < Inp_ExpConfirmOffset + 1)
      {
         // Ancora non è la barra giusta, continuiamo ad attendere
         sig.info = StringFormat("ExpFilter: in attesa conferma (shift=%d/%d)", shift, Inp_ExpConfirmOffset + 1);
         return;
      }

      // shift == Inp_ExpConfirmOffset + 1: siamo esattamente sulla barra di conferma
      g_expPending = false;
      EvaluateCandleDirection(r, atrArr, adxArr, sig,
                               StringFormat("Expansion confermata (offset=%d)", Inp_ExpConfirmOffset));
      return;
   }

   //--- CASO B: nessuna attesa in corso, controlla se la barra chiusa è in espansione
   double currentATR = atrArr[1];
   if(currentATR <= 0.0)
   { sig.info = "ExpFilter: ATR non valido"; return; }

   double trueRange = MathMax(r[1].high - r[1].low,
                       MathMax(MathAbs(r[1].high - r[2].close),
                               MathAbs(r[1].low  - r[2].close)));
   double trAtr = trueRange / currentATR;

   if(trAtr <= Inp_ExpThreshold)
   {
      sig.info = StringFormat("ExpFilter: nessuna espansione TR/ATR=%.2f (soglia %.2f)", trAtr, Inp_ExpThreshold);
      return;
   }

   //--- Espansione rilevata
   if(Inp_ExpConfirmOffset == 0)
   {
      // Direzione letta subito sulla candela di espansione stessa
      EvaluateCandleDirection(r, atrArr, adxArr, sig,
                               StringFormat("Espansione TR/ATR=%.2f (soglia %.2f)", trAtr, Inp_ExpThreshold));
      return;
   }

   // Offset>0: arma lo stato pending, la direzione verrà letta tra Inp_ExpConfirmOffset barre
   g_expPending     = true;
   g_expPendingTime = r[1].time;
   sig.info = StringFormat("Espansione TR/ATR=%.2f rilevata - attendo %d barra/e di conferma",
                            trAtr, Inp_ExpConfirmOffset);
}

//+------------------------------------------------------------------+
//| EvaluateCandleDirection                                            |
//| Legge la direzione dal colore della barra chiusa idx=1 (bull=BUY,  |
//| bear=SELL, doji=nessun segnale) e applica gli stessi filtri ADX e  |
//| S/R usati da CalculateDeltaSignal, per coerenza tra le due         |
//| sorgenti di segnale.                                                |
//+------------------------------------------------------------------+
void EvaluateCandleDirection(MqlRates &r[], double &atrArr[], double &adxArr[], DeltaSignal &sig, string tag)
{
   double currentATR = atrArr[1];
   if(currentATR <= 0.0)
   { sig.info = tag + " - ATR non valido"; return; }

   double o = r[1].open;
   double c = r[1].close;

   if(c > o)      sig.direction = 1;
   else if(c < o) sig.direction = -1;
   else
   { sig.info = tag + " - doji, nessuna direzione"; return; }

   sig.info = tag + StringFormat(" | open=%.5f close=%.5f dir=%d", o, c, sig.direction);

   //--- Filtro ADX (identico al motore core)
   if(UseADXFilter)
   {
      double adxVal = adxArr[1];
      if(adxVal < ADX_MinLevel)
      {
         sig.direction = 0;
         sig.info += StringFormat(" | ADX=%.1f < %.1f (ranging, skip)", adxVal, ADX_MinLevel);
         return;
      }
      sig.info += StringFormat(" | ADX=%.1f", adxVal);
   }

   //--- Filtro Supporto/Resistenza (identico al motore core)
   if(UseSRFilter)
   {
      int n = ArraySize(r);
      if(2 + SR_Lookback <= n)
      {
         double resistance = r[2].high;
         double support    = r[2].low;
         for(int k = 2; k < 2 + SR_Lookback && k < n; k++)
         {
            if(r[k].high > resistance) resistance = r[k].high;
            if(r[k].low  < support)    support    = r[k].low;
         }

         bool nearResistance = false;
         bool nearSupport    = false;
         double proximityThreshold = 0.0;
         if(UseATRFilter)
         {
            proximityThreshold = currentATR * SR_Proximity;
            nearResistance = MathAbs(c - resistance) <= proximityThreshold;
            nearSupport    = MathAbs(c - support)    <= proximityThreshold;
         }
         bool aboveR = c > resistance;
         bool belowS = c < support;

         bool srValid = nearResistance || nearSupport || aboveR || belowS;
         if(!srValid)
         {
            sig.direction = 0;
            sig.info += StringFormat(" | S/R skip (R=%.5f S=%.5f prox=%.5f)", resistance, support, proximityThreshold);
            return;
         }
         sig.info += StringFormat(" | S/R OK (R=%.5f S=%.5f)", resistance, support);
      }
   }
}

//+------------------------------------------------------------------+
//| GetVolatilityRegime                                                |
//| Ricalcola il regime di volatilità su ogni barra chiusa, composito |
//| di ATR% e volatilità di Parkinson (stima da high/low, più         |
//| efficiente statisticamente del solo close-to-close), smoothato    |
//| con EMA e classificato via percentile rank su finestra mobile.    |
//| Usa esclusivamente barre CHIUSE (start_pos=1) -> no repaint.      |
//+------------------------------------------------------------------+
bool GetVolatilityRegime(ENUM_VOL_REGIME &regime, double &pctRankOut, double &pctRankPrevOut)
{
   int need = Inp_VolAtrLen + Inp_VolLookback + Inp_VolEmaSmooth + 10;

   MqlRates r[];
   ArraySetAsSeries(r, false); // cronologico: r[0]=piu' vecchia, r[n-1]=barra chiusa piu' recente
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 1, need, r);
   if(copied < need) return false;

   double atrArr[];
   ArraySetAsSeries(atrArr, false);
   if(CopyBuffer(VolATRHandle, 0, 1, need, atrArr) <= 0) return false;

   int n = copied;
   double volSmooth[];
   ArrayResize(volSmooth, n);

   double emaAlpha   = 2.0 / (Inp_VolEmaSmooth + 1.0);
   double parkFactor = 1.0 / (4.0 * MathLog(2.0));  // costante dello stimatore Parkinson (1962)

   for(int i = 0; i < n; i++)
   {
      double atrVal = atrArr[i];
      if(atrVal <= 0.0) atrVal = _Point;
      double atrPct = (atrVal / r[i].close) * 100.0;

      // Stimatore di Parkinson: usa solo high/low, più efficiente del close-to-close
      // ma NON cattura i gap overnight (irrilevante su forex 24/5, da considerare su altri asset)
      double parkVarSum = 0.0;
      int    cnt = 0;
      for(int k = i; k > i - Inp_VolAtrLen && k >= 0; k--)
      {
         double pv = (r[k].low > 0) ? parkFactor * MathPow(MathLog(r[k].high / r[k].low), 2) : 0.0;
         parkVarSum += pv;
         cnt++;
      }
      double parkVol = (cnt > 0) ? MathSqrt(parkVarSum / cnt) * 100.0 : 0.0;
      double volComposite = (atrPct + parkVol) / 2.0;

      if(i == 0) volSmooth[i] = volComposite;
      else       volSmooth[i] = volSmooth[i-1] + emaAlpha * (volComposite - volSmooth[i-1]);
   }

   int last    = n - 1;
   int prevIdx = last - 1;
   // servono Lookback barre valide sia per l'ultima barra chiusa sia per quella precedente
   if(prevIdx < Inp_VolLookback) return false;

   double curVol = volSmooth[last];
   int    lowerCount = 0;
   for(int k = last - Inp_VolLookback; k < last; k++)
      if(volSmooth[k] <= curVol) lowerCount++;
   double pctRank = ((double)lowerCount / Inp_VolLookback) * 100.0;

   double prevVol = volSmooth[prevIdx];
   int    lowerCountPrev = 0;
   for(int k = prevIdx - Inp_VolLookback; k < prevIdx; k++)
      if(volSmooth[k] <= prevVol) lowerCountPrev++;
   double pctRankPrev = ((double)lowerCountPrev / Inp_VolLookback) * 100.0;

   pctRankOut     = pctRank;
   pctRankPrevOut = pctRankPrev;

   if(pctRank >= Inp_VolExtremeTh)      regime = VOL_EXTREME;
   else if(pctRank >= Inp_VolHighTh)    regime = VOL_HIGH;
   else if(pctRank >= Inp_VolLowTh)     regime = VOL_NORMAL;
   else                                 regime = VOL_LOW;

   return true;
}

//+------------------------------------------------------------------+
//| CalcLotSize (FIX v1.12)                                            |
//| Il rischio monetario è ora calcolato sulla DISTANZA SL EFFETTIVA   |
//| (in prezzo) passata da OpenTrade, quindi coincide con lo SL        |
//| realmente piazzato sia in modalità punti fissi sia in modalità     |
//| ATR (Inp_UseATR_SLTP=true). Elimina il disallineamento di v1.11,   |
//| dove il sizing usava sempre Inp_StopLoss fisso a prescindere.      |
//| slDistancePrice: distanza SL in unità di prezzo (es. 0.00050).     |
//+------------------------------------------------------------------+
double CalcLotSize(double slDistancePrice)
{
   int mode = (int)Inp_LotMode;
   if(mode == 0) return Inp_LotSize;

   double capital = (mode == 1)
                    ? AccountInfoDouble(ACCOUNT_BALANCE)
                    : AccountInfoDouble(ACCOUNT_EQUITY);
   if(capital <= 0.0) return Inp_LotSize;

   double riskMoney = capital * Inp_RiskPct / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0.0 || tickSize <= 0.0 || slDistancePrice <= 0.0) return Inp_LotSize;

   double slTicks = slDistancePrice / tickSize;
   double slMoney = slTicks * tickValue;
   if(slMoney <= 0.0) return Inp_LotSize;

   double lots = riskMoney / slMoney;
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathMax(lotMin, MathMin(lotMax, lots));
   lots = MathFloor(lots / lotStep) * lotStep;
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| GetCurrentATR                                                     |
//| Legge l'ATR sulla barra chiusa più recente del timeframe          |
//| Inp_ATR_SLTP_TF (indipendente dal TF operativo). Usato SOLO per   |
//| SL/TP dinamici, non tocca il motore core né il filtro S/R.        |
//+------------------------------------------------------------------+
double GetCurrentATR()
{
   if(SLTP_ATRHandle == INVALID_HANDLE) return 0.0;
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(SLTP_ATRHandle, 0, 1, 1, arr) <= 0) return 0.0;
   return arr[0];
}

//+------------------------------------------------------------------+
//| OpenTrade                                                          |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE orderType, ulong &outTicket)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double price = (orderType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double slDistance, tpDistance;
   if(Inp_UseATR_SLTP)
   {
      double atrVal = GetCurrentATR();
      if(atrVal <= 0.0)
      {
         // fallback di sicurezza: se ATR non disponibile, usa i punti fissi
         atrVal = Inp_StopLoss * point / MathMax(Inp_ATR_SL_Mult, 0.01);
      }
      slDistance = atrVal * Inp_ATR_SL_Mult;
      tpDistance = atrVal * Inp_ATR_TP_Mult;
   }
   else
   {
      slDistance = Inp_StopLoss   * point;
      tpDistance = Inp_TakeProfit * point;
   }

   double sl = (orderType == ORDER_TYPE_BUY)
               ? NormalizeDouble(price - slDistance, digits)
               : NormalizeDouble(price + slDistance, digits);

   double tp = 0.0;
   if(Inp_UseTP)
      tp = (orderType == ORDER_TYPE_BUY)
           ? NormalizeDouble(price + tpDistance, digits)
           : NormalizeDouble(price - tpDistance, digits);

   // FIX v1.12: passa la distanza SL effettiva (in prezzo) al sizing,
   // così il rischio reale coincide con Inp_RiskPct anche con SL su ATR.
   double lots    = CalcLotSize(slDistance);
   string comment = StringFormat("SD_EA_%s", orderType == ORDER_TYPE_BUY ? "L" : "S");

   if(Inp_DebugMode)
   {
      Print("============================================================");
      Print("APERTURA ", orderType == ORDER_TYPE_BUY ? "LONG" : "SHORT");
      Print("   Price=", DoubleToString(price, digits),
            " | SL=",   DoubleToString(sl, digits),
            " | TP=",   tp > 0 ? DoubleToString(tp, digits) : "OFF",
            " | Lots=", DoubleToString(lots, 2));
   }

   bool result = (orderType == ORDER_TYPE_BUY)
                 ? trade.Buy (lots, _Symbol, price, sl, tp, comment)
                 : trade.Sell(lots, _Symbol, price, sl, tp, comment);

   if(result)
   {
      outTicket = trade.ResultOrder();
      totalTrades++;
      if(Inp_DebugMode) Print("Trade aperto! Ticket: ", outTicket);
      if(Inp_EnableAlerts)
         Alert(StringFormat("SD EA: %s @ %.5f | SL %.5f | TP %.5f",
               orderType == ORDER_TYPE_BUY ? "LONG" : "SHORT", price, sl, tp));
   }
   else
   {
      outTicket = 0;
      Print("Errore apertura: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
   }
   if(Inp_DebugMode) Print("============================================================\n");
   return result;
}

//+------------------------------------------------------------------+
//| ManageTrailingStop                                                 |
//| Trailing lineare a step: sposta lo SL solo quando il movimento     |
//| supera Inp_TrailingStep, evitando richieste di modifica continue.  |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)       != _Symbol)        continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;

      ENUM_POSITION_TYPE posType   = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double             oldSL     = PositionGetDouble(POSITION_SL);
      double             posTP     = PositionGetDouble(POSITION_TP);

      if(posType == POSITION_TYPE_BUY)
      {
         double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profitPts = (bid - openPrice) / point;
         if(profitPts < Inp_TrailingStart) continue;
         double newSL = NormalizeDouble(bid - Inp_TrailingStop * point, digits);
         if(newSL > oldSL + Inp_TrailingStep * point || oldSL == 0.0)
            trade.PositionModify(ticket, newSL, posTP);
      }
      else
      {
         double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitPts = (openPrice - ask) / point;
         if(profitPts < Inp_TrailingStart) continue;
         double newSL = NormalizeDouble(ask + Inp_TrailingStop * point, digits);
         if(newSL < oldSL - Inp_TrailingStep * point || oldSL == 0.0)
            trade.PositionModify(ticket, newSL, posTP);
      }
   }
}

//+------------------------------------------------------------------+
//| CountOpenTrades                                                    |
//+------------------------------------------------------------------+
int CountOpenTrades(ENUM_ORDER_TYPE orderType)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)       != _Symbol)        continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(orderType == ORDER_TYPE_BUY  && posType == POSITION_TYPE_BUY)  count++;
      if(orderType == ORDER_TYPE_SELL && posType == POSITION_TYPE_SELL) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| SetHourLock - registra la chiave oraria per il filtro OneTradePerHour |
//+------------------------------------------------------------------+
void SetHourLock(const MqlDateTime &dt)
{
   lastTradeDayTime = (datetime)(dt.year * 1000000L
                                + dt.mon  * 10000L
                                + dt.day  * 100L
                                + dt.hour);
   lastTradeHour    = dt.hour;
}

//+------------------------------------------------------------------+
//| RegisterTradeHour - associa un ticket appena aperto alla sua ora |
//+------------------------------------------------------------------+
void RegisterTradeHour(ulong ticket, int hour)
{
   if(trackedCount >= MAX_TRACK) return;
   trackedTicket[trackedCount] = ticket;
   trackedHour  [trackedCount] = hour;
   trackedCount++;
}

//+------------------------------------------------------------------+
//| UpdateClosedTradePnL - aggiorna le statistiche orarie quando una  |
//| posizione tracciata risulta chiusa nello storico deal             |
//+------------------------------------------------------------------+
void UpdateClosedTradePnL()
{
   if(trackedCount == 0) return;
   for(int t = 0; t < trackedCount; t++)
   {
      if(trackedHour[t] < 0) continue;
      ulong positionId = trackedTicket[t];
      if(!HistorySelectByPosition(positionId)) continue;
      uint dealsInPos = (uint)HistoryDealsTotal();
      for(uint d = 0; d < dealsInPos; d++)
      {
         ulong dealTicket = HistoryDealGetTicket(d);
         if(dealTicket == 0) continue;
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT) continue;
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                       + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                       + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
         int h = trackedHour[t];
         hourPnL   [h] += profit;
         hourTrades[h]++;
         if(profit > 0) hourWins[h]++;
         trackedHour[t] = -1;
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| IsTimeFilterOK - valuta le fasce orarie inclusive (supporta       |
//| fasce overnight, es. 22:00 -> 06:00)                              |
//+------------------------------------------------------------------+
int TimeToMinutes(int hour, int min) { return hour * 60 + min; }

bool IsTimeFilterOK()
{
   if(!Inp_UseTimeFilter1 && !Inp_UseTimeFilter2) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMin = TimeToMinutes(dt.hour, dt.min);
   bool f1 = false, f2 = false;
   if(Inp_UseTimeFilter1)
   {
      int s1 = TimeToMinutes(Inp_StartHour1, Inp_StartMin1);
      int e1 = TimeToMinutes(Inp_EndHour1,   Inp_EndMin1);
      f1 = (s1 <= e1) ? (nowMin >= s1 && nowMin < e1) : (nowMin >= s1 || nowMin < e1);
   }
   if(Inp_UseTimeFilter2)
   {
      int s2 = TimeToMinutes(Inp_StartHour2, Inp_StartMin2);
      int e2 = TimeToMinutes(Inp_EndHour2,   Inp_EndMin2);
      f2 = (s2 <= e2) ? (nowMin >= s2 && nowMin < e2) : (nowMin >= s2 || nowMin < e2);
   }
   // Se entrambe le fasce sono attive, basta rientrare in UNA delle due (OR)
   if(Inp_UseTimeFilter1 && Inp_UseTimeFilter2) return (f1 || f2);
   return (Inp_UseTimeFilter1 ? f1 : f2);
}

//+------------------------------------------------------------------+
//| PrintHourlyStats - report leggibile PnL/winrate per ora del      |
//| giorno, ordinato dal migliore al peggiore                         |
//+------------------------------------------------------------------+
void PrintHourlyStats()
{
   Print("============================================================");
   Print("STATISTICHE PER ORA - SyntheticDelta EA v1.12");
   Print("============================================================");
   Print(StringFormat("%-6s %-8s %-12s %-10s %-8s", "ORA","TRADES","PnL TOT","WINRATE%","AVG PnL"));
   Print("------------------------------------------------------------");

   int sortedIdx[24];
   for(int i = 0; i < 24; i++) sortedIdx[i] = i;
   for(int i = 0; i < 23; i++)
      for(int j = i + 1; j < 24; j++)
         if(hourPnL[sortedIdx[j]] > hourPnL[sortedIdx[i]])
         { int tmp = sortedIdx[i]; sortedIdx[i] = sortedIdx[j]; sortedIdx[j] = tmp; }

   for(int i = 0; i < 24; i++)
   {
      int h = sortedIdx[i];
      if(hourTrades[h] == 0) continue;
      double winrate = (double)hourWins[h] / hourTrades[h] * 100.0;
      double avgPnL  = hourPnL[h] / hourTrades[h];
      string marker  = (i == 0) ? " BEST" : (i <= 2) ? " +" : (hourPnL[h] < 0) ? " -" : "";
      Print(StringFormat("%02d:00  %-8d %-12.2f %-10.1f %-8.2f%s",
                         h, hourTrades[h], hourPnL[h], winrate, avgPnL, marker));
   }
   Print("============================================================\n");
}

//+------------------------------------------------------------------+
//| BuildHourlyStatsFromHistory - ricostruisce le statistiche orarie  |
//| dall'intero storico deal del conto (filtrato per Magic Number),   |
//| usata a fine backtest indipendentemente dal tracking in-memory    |
//+------------------------------------------------------------------+
void BuildHourlyStatsFromHistory()
{
   ArrayInitialize(hourPnL, 0.0);
   ArrayInitialize(hourTrades, 0);
   ArrayInitialize(hourWins,   0);

   if(!HistorySelect(0, TimeCurrent())) return;
   uint total = HistoryDealsTotal();

   for(uint i = 0; i < total; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      if((long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != Inp_MagicNumber) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN) continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      MqlDateTime dt; TimeToStruct(dealTime, dt);
      int h = dt.hour;

      ulong posId   = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      double profit = 0.0;
      bool   found  = false;

      for(uint j = i + 1; j < total; j++)
      {
         ulong exitTicket = HistoryDealGetTicket(j);
         if(exitTicket == 0) continue;
         if(HistoryDealGetInteger(exitTicket, DEAL_POSITION_ID) != (long)posId) continue;
         ENUM_DEAL_ENTRY exitEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(exitTicket, DEAL_ENTRY);
         if(exitEntry != DEAL_ENTRY_OUT) continue;
         profit = HistoryDealGetDouble(exitTicket, DEAL_PROFIT)
                + HistoryDealGetDouble(exitTicket, DEAL_SWAP)
                + HistoryDealGetDouble(exitTicket, DEAL_COMMISSION);
         found = true;
         break;
      }
      if(!found) continue;

      hourPnL   [h] += profit;
      hourTrades[h]++;
      if(profit > 0) hourWins[h]++;
   }
}

//+------------------------------------------------------------------+
//| OnTester                                                           |
//| Fitness function per l'Optimizer di MT5.                          |
//| Formula: (profit/maxDD)*0.4 + winrate%*0.6                        |
//| NOTA CRITICA: non è un vero Sharpe Ratio (manca la componente di  |
//| volatilità dei ritorni), non penalizza il numero di trade (favorisce|
//| overfitting su set con pochi trade fortunati), e pesa il winrate  |
//| più del rapporto rischio/rendimento -> in ottimizzazione tende a  |
//| premiare setup ad alta frequenza di piccole vincite anche se il   |
//| profit factor complessivo è mediocre. Da sostituire con una       |
//| metrica risk-adjusted più solida (es. Sortino, o profit/maxDD     |
//| penalizzato per numero trade insufficiente) prima di affidarsi    |
//| ai risultati dell'optimizer per decisioni di capitale reale.      |
//+------------------------------------------------------------------+
double OnTester()
{
   BuildHourlyStatsFromHistory();
   PrintHourlyStats();

   // FIX v1.12: nomi nativi ENUM_STATISTICS (prima erano #define errate).
   // STAT_BALANCE_DD = max drawdown assoluto sul balance;
   // STAT_PROFIT_TRADES = numero operazioni chiuse in profitto.
   double profit       = TesterStatistics(STAT_PROFIT);
   double max_dd        = TesterStatistics(STAT_BALANCE_DD);
   double win_trades    = TesterStatistics(STAT_PROFIT_TRADES);
   double total_trades  = TesterStatistics(STAT_TRADES);

   if(max_dd <= 0.0 || total_trades == 0.0) return 0.0;

   double sharpe  = profit / max_dd;
   double winrate = (win_trades / total_trades) * 100.0;
   return (sharpe * 0.4) + (winrate * 0.6);
}
//+------------------------------------------------------------------+
