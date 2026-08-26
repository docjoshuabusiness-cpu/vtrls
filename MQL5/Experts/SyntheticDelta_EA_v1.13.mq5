//+------------------------------------------------------------------+
//|                                    SyntheticDelta_EA_v1.13.mq5   |
//+------------------------------------------------------------------+
//| STRATEGIA                                                        |
//| ---------                                                        |
//| "Synthetic Delta": stima uno pseudo order-flow delta usando solo |
//| dati OHLC + tick volume (nessun vero volume/DOM), combinando:    |
//|   - posizione della chiusura nel range della barra                |
//|   - distanza high/low da una EMA (forza bulls/bears alla Elder)  |
//|   - peso volumetrico (tick volume vs media)                      |
//| In alternativa (o in combinazione) la direzione puo' arrivare    |
//| dall'Expansion Candle Filter: colore della candela di conferma   |
//| dopo una barra con True Range anomalo rispetto all'ATR.          |
//|                                                                   |
//| NOVITA' v1.13                                                     |
//| -------------                                                     |
//| A) SIGNAL MODE: Delta / Expansion / ENTRAMBI in AND (confluenza) |
//|    / ENTRAMBI in OR (prima che arriva). Sostituisce il vecchio   |
//|    bool Inp_UseExpansionFilter.                                   |
//| B) STATISTICHE A BUCKET DI MINUTI: il report non e' piu' solo    |
//|    orario, ma su fasce configurabili (1/5/10/15/20/30/60 min)    |
//|    con etichetta "HH:MM-HH:MM", piu' rollup orario.               |
//| C) SEQUENCE FILTER: scelta di QUALE segnale della raffica        |
//|    prendere (N-esimo, con finestra opzionale) + RESET su segnale |
//|    opposto (dopo un BUY serve un segnale SELL prima di un altro  |
//|    BUY, e viceversa). Il segnale opposto NON deve essere         |
//|    necessariamente tradato: serve solo a sbloccare.               |
//| D) ARCHITETTURA: dati di mercato copiati UNA volta per barra e   |
//|    condivisi dai due motori; filtri ADX/S/R applicati una volta  |
//|    sola a valle (niente logica duplicata).                        |
//| E) PERFORMANCE OPTIMIZER: log disattivati in optimization,       |
//|    regime volatilita' calcolato in modo INCREMENTALE (era O(n*m) |
//|    ricalcolato da zero ad ogni barra), tracking PnL una volta    |
//|    per barra invece che ad ogni tick, ricostruzione statistiche  |
//|    da storico in O(n log n) invece che O(n^2).                    |
//| F) ROBUSTEZZA BROKER: rispetto di SYMBOL_TRADE_STOPS_LEVEL su    |
//|    apertura e trailing, normalizzazione lotto sullo step reale,  |
//|    fitness function selezionabile e sensata.                      |
//|                                                                   |
//| NOTE METODOLOGICHE                                                |
//| ------------------                                                |
//| 1. Tutti i calcoli usano la barra CHIUSA idx=1 -> no repaint.     |
//| 2. Il tick_volume su forex/CFD NON e' volume reale: proxy debole. |
//| 3. Lo stato del sequence filter e dell'expansion pending NON      |
//|    persiste tra riavvii dell'EA (variabili in RAM).               |
//+------------------------------------------------------------------+
#property copyright "SyntheticDelta EA"
#property version   "1.13"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| ENUM GLOBALI                                                      |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
{
   LOT_FIXED       = 0,  // Lotto fisso, ignora capitale ed equity
   LOT_BALANCE_PCT = 1,  // Rischio % sul Balance (stabile)
   LOT_EQUITY_PCT  = 2   // Rischio % sull'Equity (piu' aggressivo)
};

enum ENUM_VOL_REGIME
{
   VOL_LOW      = 0,  // Percentile < LowTh   -> mercato quieto
   VOL_NORMAL   = 1,  // LowTh <= P < HighTh  -> condizioni tipiche
   VOL_HIGH     = 2,  // HighTh <= P < ExtTh  -> volatilita' elevata
   VOL_EXTREME  = 3   // P >= ExtremeTh       -> coda di distribuzione
};

enum ENUM_SIGNAL_MODE
{
   SIG_DELTA_ONLY     = 0, // Solo Synthetic Delta
   SIG_EXPANSION_ONLY = 1, // Solo Expansion Candle
   SIG_BOTH_AND       = 2, // ENTRAMBI concordi sulla stessa barra (confluenza, piu' selettivo)
   SIG_BOTH_OR        = 3  // Basta uno dei due; se sono discordi nella stessa barra il segnale viene annullato
};

enum ENUM_FITNESS_MODE
{
   FIT_LEGACY      = 0, // (profit/maxDD)*0.4 + winrate*0.6  (compatibilita' v1.12, sconsigliata)
   FIT_RECOVERY_PF = 1, // RecoveryFactor * min(ProfitFactor,3) * penalita' su numero trade
   FIT_SHARPE_N    = 2  // Sharpe nativo MT5 * penalita' su numero trade
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "=== SORGENTE SEGNALE ==="
input ENUM_SIGNAL_MODE Inp_SignalMode = SIG_DELTA_ONLY; // Quale motore decide la direzione. BOTH_AND = servono entrambi concordi sulla STESSA barra chiusa (attenzione: con ExpConfirmOffset>0 l'expansion spara solo sulla barra di conferma, quindi la confluenza e' rara). BOTH_OR = entra col primo dei due che si accende.

input group "=== SYNTHETIC DELTA CORE ==="
input int    EmaPeriod        = 13;    // Periodo EMA per bulls/bears power. Piu' basso = piu' reattivo ma piu' rumoroso.
input int    VolAvgPeriod     = 20;    // Finestra media tick_volume per il peso volumetrico.
input double SignalThreshold  = 0.15;  // Soglia minima del delta normalizzato (~[-1,1]). Piu' alta = meno trade, piu' selettivi.

input group "=== ATR ==="
input bool   UseATRFilter     = true;  // Se true l'ATR e' usato come soglia di prossimita' nel filtro S/R. La VALIDITA' del dato ATR (>0) resta sempre obbligatoria.
input int    ATR_Period       = 14;    // Periodo ATR del motore core (validita' dati + prossimita' S/R).

input group "=== ADX TREND FILTER ==="
input bool   UseADXFilter     = true;  // Filtra i segnali in mercati laterali.
input int    ADX_Period       = 14;    // Periodo ADX standard.
input double ADX_MinLevel     = 20.0;  // Soglia minima ADX per considerare il mercato in trend.

input group "=== SUPPORT/RESISTANCE FILTER ==="
input bool   UseSRFilter      = true;  // Richiede prossimita' a un livello S/R o breakout.
input int    SR_Lookback      = 15;    // Barre precedenti su cui calcolare massimo/minimo come S/R.
input double SR_Proximity     = 0.5;   // Moltiplicatore ATR che definisce "vicino". Ignorato se UseATRFilter=false (resta solo il breakout puro).
input bool   Inp_SR_DirAware  = false; // NOVITA' v1.13: se true il filtro diventa direzionale (BUY valido solo vicino al supporto o in breakout sopra la resistenza; SELL solo vicino alla resistenza o sotto il supporto). Se false replica il comportamento simmetrico della v1.12.

input group "=== VOLATILITY REGIME FILTER ==="
input bool   Inp_UseVolFilter    = false; // Master switch del filtro regime.
input int    Inp_VolAtrLen       = 14;    // ATR usato SOLO per la componente ATR% del regime.
input int    Inp_VolLookback     = 100;   // Finestra del percentile rank. Piu' ampia = regime piu' stabile ma meno reattivo.
input int    Inp_VolEmaSmooth    = 3;     // EMA di smoothing sulla volatilita' composita.
input int    Inp_VolLowTh        = 30;    // Percentile sotto il quale il regime e' LOW.
input int    Inp_VolHighTh       = 70;    // Percentile sopra il quale il regime e' HIGH.
input int    Inp_VolExtremeTh    = 90;    // Percentile sopra il quale il regime e' EXTREME.
input bool   Inp_AllowTradeLOW      = true;  // Consenti trade in regime LOW.
input bool   Inp_AllowTradeNORMAL   = true;  // Consenti trade in regime NORMAL.
input bool   Inp_AllowTradeHIGH     = false; // Consenti trade in regime HIGH.
input bool   Inp_AllowTradeEXTREME  = false; // Consenti trade in regime EXTREME.
input bool   Inp_RequireVolIncreasing = false; // Scarta il segnale se la volatilita' sta calando rispetto alla barra precedente.

input group "=== EXPANSION CANDLE FILTER ==="
input int    Inp_ExpATRPeriod       = 14;  // Periodo ATR dedicato al rapporto TR/ATR (handle indipendente).
input double Inp_ExpThreshold       = 1.8; // Soglia TR/ATR sopra la quale la barra chiusa e' "in espansione".
input int    Inp_ExpConfirmOffset   = 0;   // Barre chiuse da attendere DOPO l'espansione prima di leggere il colore. 0 = colore della candela di espansione stessa.

input group "=== SEQUENCE FILTER (quale segnale della raffica prendere) ==="
input bool   Inp_UseSequenceFilter  = false; // Master switch. Se false il comportamento e' quello classico: si entra sul primo segnale utile.
input int    Inp_EnterOnSignalNo    = 1;     // N-esimo segnale della raffica su cui entrare. 1 = il primo (comportamento classico), 2 = ignora il primo ed entra sul secondo, ecc.
input int    Inp_SignalWindow       = 1;     // Quanti segnali consecutivi accettare a partire dall'N-esimo. 1 = solo l'N-esimo. 3 con EnterOnSignalNo=2 = accetta il 2o, 3o e 4o. 0 = da N in poi senza limite.
input int    Inp_RunGapBars         = 0;     // Barre consecutive SENZA segnale che chiudono la raffica e azzerano il contatore. 0 = la raffica si chiude solo con un segnale di direzione opposta.
input bool   Inp_RequireOppositeReset = false; // NOVITA': dopo un'entrata BUY, nessun altro BUY finche' non compare un segnale SELL (e viceversa). Il segnale opposto NON viene necessariamente tradato: serve solo da reset.
input bool   Inp_ResetOnRawSignal   = false; // Se true il reset scatta anche su un segnale opposto BOCCIATO dai filtri ADX/S/R/Volatilita' (piu' reattivo, sblocca prima). Se false serve un segnale opposto pienamente valido.

input group "=== MONEY MANAGEMENT ==="
input int    Inp_LotMode      = 0;     // 0=Fisso, 1=%Balance, 2=%Equity.
input double Inp_LotSize      = 0.01;  // Lotto fisso, o fallback se il calcolo dinamico fallisce.
input double Inp_RiskPct      = 1.0;   // % di capitale rischiata per trade se Inp_LotMode != 0. Dalla v1.12 il rischio e' calcolato sulla distanza SL EFFETTIVA (anche in modalita' ATR).
input int    Inp_StopLoss     = 50;    // SL in punti (usato se Inp_UseATR_SLTP=false).
input int    Inp_TakeProfit   = 100;   // TP in punti (usato se Inp_UseATR_SLTP=false e Inp_UseTP=true).
input bool   Inp_UseTP        = true;  // Se false il trade e' aperto senza Take Profit.
input int    Inp_MagicNumber  = 11111; // Identificativo posizioni di questo EA.

input group "=== SL/TP DINAMICI SU ATR ==="
input bool   Inp_UseATR_SLTP  = false; // SL/TP come multipli di ATR invece che punti fissi.
input double Inp_ATR_SL_Mult  = 1.5;   // Moltiplicatore ATR per lo Stop Loss.
input double Inp_ATR_TP_Mult  = 3.0;   // Moltiplicatore ATR per il Take Profit.
input ENUM_TIMEFRAMES Inp_ATR_SLTP_TF     = PERIOD_CURRENT; // Timeframe dell'ATR per SL/TP.
input int              Inp_ATR_SLTP_Period = 14;            // Periodo ATR per SL/TP.

input group "=== TRAILING STOP ==="
input bool   Inp_UseTrailing      = true; // Trailing stop lineare a step.
input int    Inp_TrailingStart    = 30;   // Profitto minimo in punti prima di attivare il trailing.
input int    Inp_TrailingStop     = 20;   // Distanza mantenuta tra prezzo e nuovo SL.
input int    Inp_TrailingStep     = 5;    // Incremento minimo per aggiornare lo SL (anti-spam richieste).

input group "=== FILTRO 1 TRADE PER ORA ==="
input bool   Inp_OneTradePerHour  = true; // Blocca nuove entrate nella stessa ora solare di un trade gia' aperto.

input group "=== FILTRI ORARI (INCLUSIVI) ==="
input bool   Inp_UseTimeFilter1   = false; // Attiva la prima fascia oraria.
input int    Inp_StartHour1       = 8;     // Ora inizio fascia 1 (server time broker).
input int    Inp_StartMin1        = 0;     // Minuto inizio fascia 1.
input int    Inp_EndHour1         = 12;    // Ora fine fascia 1.
input int    Inp_EndMin1          = 0;     // Minuto fine fascia 1.
input bool   Inp_UseTimeFilter2   = false; // Attiva la seconda fascia oraria.
input int    Inp_StartHour2       = 14;    // Ora inizio fascia 2.
input int    Inp_StartMin2        = 30;    // Minuto inizio fascia 2.
input int    Inp_EndHour2         = 18;    // Ora fine fascia 2.
input int    Inp_EndMin2          = 0;     // Minuto fine fascia 2. Con entrambe attive vale l'OR logico.

input group "=== RISK MANAGEMENT ==="
input bool   Inp_UseMaxTrades     = true; // Limita le posizioni simultanee per direzione.
input int    Inp_MaxBuyTrades     = 1;    // Max posizioni BUY contemporanee.
input int    Inp_MaxSellTrades    = 1;    // Max posizioni SELL contemporanee.
input int    Inp_Slippage         = 30;   // Deviazione massima in punti.

input group "=== SPREAD FILTER ==="
input bool   Inp_UseSpreadFilter  = true; // Blocca entrate con spread eccessivo.
input int    Inp_MaxSpreadPoints  = 30;   // Spread massimo tollerato in punti.

input group "=== STATISTICHE / REPORT ==="
input int    Inp_StatsBucketMinutes = 15; // NOVITA' v1.13: ampiezza in minuti delle fasce del report (valori validi: 1,2,3,4,5,6,10,12,15,20,30,60 - un valore diverso viene arrotondato al divisore di 60 piu' vicino). 60 = report orario classico.
input int    Inp_StatsTopN          = 15; // Quante fasce migliori e peggiori stampare. 0 = stampa tutte le fasce con almeno un trade.
input int    Inp_StatsMinTrades     = 1;  // Numero minimo di trade perche' una fascia compaia nel report (alza a 5-10 per evitare di leggere rumore statistico).

input group "=== OTTIMIZZAZIONE ==="
input ENUM_FITNESS_MODE Inp_FitnessMode = FIT_RECOVERY_PF; // Metrica restituita da OnTester all'Optimizer.
input int    Inp_Fit_MinTrades     = 50;  // Sotto questo numero di trade la fitness viene penalizzata quadraticamente (anti-overfitting su pochi trade fortunati).

input group "=== DEBUG ==="
input bool   Inp_DebugMode        = true;  // Log dettagliati. Forzato OFF automaticamente durante l'ottimizzazione (le Print sono il collo di bottiglia n.1 del tester).
input bool   Inp_EnableAlerts     = false; // Alert popup all'apertura di ogni trade.

//+------------------------------------------------------------------+
//| HANDLES INDICATORI                                                |
//+------------------------------------------------------------------+
int EmaHandle      = INVALID_HANDLE;  // EMA core per bulls/bears power
int ATRHandle      = INVALID_HANDLE;  // ATR core (validita' segnale + prossimita' S/R)
int ADXHandle      = INVALID_HANDLE;  // ADX filtro trend
int VolATRHandle   = INVALID_HANDLE;  // ATR del filtro di regime volatilita'
int SLTP_ATRHandle = INVALID_HANDLE;  // ATR per SL/TP dinamici
int ExpATRHandle   = INVALID_HANDLE;  // ATR del filtro Expansion Candle

//+------------------------------------------------------------------+
//| COSTANTI DI SIMBOLO CACHATE (lette una volta in OnInit)           |
//| SymbolInfoDouble/Integer nel tester costa: in v1.12 veniva        |
//| chiamata decine di volte per tick.                                |
//+------------------------------------------------------------------+
double g_point      = 0.0;
int    g_digits     = 5;
long   g_stopsLevel = 0;
double g_lotMin     = 0.01;
double g_lotMax     = 100.0;
double g_lotStep    = 0.01;
int    g_lotDigits  = 2;

bool   g_debug      = false; // Inp_DebugMode AND non-optimization
bool   g_isOptim    = false; // true durante l'ottimizzazione: niente log, niente statistiche in-memory
bool   g_useDelta   = false; // motore delta attivo secondo Inp_SignalMode
bool   g_useExp     = false; // motore expansion attivo secondo Inp_SignalMode

//+------------------------------------------------------------------+
//| VARIABILI GLOBALI DI STATO                                        |
//+------------------------------------------------------------------+
datetime lastBarTime      = 0;   // Timestamp ultima barra processata
int      totalTrades      = 0;   // Contatore trade aperti nella sessione
datetime lastTradeHourKey = 0;   // Chiave anno/mese/giorno/ora dell'ultimo trade (OneTradePerHour)

//--- Buffer condivisi dai due motori: copiati UNA sola volta per barra
MqlRates g_rates[];
double   g_ema[];
double   g_atr[];
double   g_adx[];
double   g_expAtr[];
int      g_barsCopied = 0;

//--- Stato Expansion Candle
bool     g_expPending     = false; // espansione rilevata, attesa barra di conferma
datetime g_expPendingTime = 0;     // timestamp della barra di espansione

//--- Stato Sequence Filter
int      g_runDir       = 0;  // direzione della raffica corrente (1/-1/0)
int      g_runCount     = 0;  // quanti segnali validi consecutivi in quella direzione
int      g_gapBars      = 0;  // barre consecutive senza segnale
int      g_lockedDir    = 0;  // direzione bloccata in attesa del segnale opposto di reset (0 = nessun blocco)

//--- Statistiche a bucket di minuti
#define MAX_BUCKETS 1440
double   g_bucketPnL   [MAX_BUCKETS];
int      g_bucketTrades[MAX_BUCKETS];
int      g_bucketWins  [MAX_BUCKETS];
int      g_bucketMin   = 60;  // ampiezza bucket in minuti (validata in OnInit)
int      g_bucketCount = 24;  // 1440 / g_bucketMin

#define MAX_TRACK 512
ulong    trackedTicket[MAX_TRACK]; // position id monitorati per l'attribuzione PnL
int      trackedBucket[MAX_TRACK]; // bucket di apertura corrispondente
int      trackedCount = 0;

//+------------------------------------------------------------------+
//| PickFilling                                                        |
//| Modalita' di riempimento supportata dal simbolo (bitmask           |
//| SYMBOL_FILLING_MODE): FOK -> IOC -> RETURN. Evita il retcode 10030 |
//| su broker ECN come FP Markets che non espongono FOK ovunque.       |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING PickFilling()
{
   long modes = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((modes & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((modes & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| ValidateBucketMinutes - snap al divisore di 60 piu' vicino        |
//+------------------------------------------------------------------+
int ValidateBucketMinutes(int req)
{
   int valid[] = {1,2,3,4,5,6,10,12,15,20,30,60};
   int best = 60, bestDiff = 1000;
   for(int i = 0; i < ArraySize(valid); i++)
   {
      int d = MathAbs(valid[i] - req);
      if(d < bestDiff) { bestDiff = d; best = valid[i]; }
   }
   return best;
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_isOptim = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_debug   = Inp_DebugMode && !g_isOptim;

   g_useDelta = (Inp_SignalMode == SIG_DELTA_ONLY || Inp_SignalMode == SIG_BOTH_AND || Inp_SignalMode == SIG_BOTH_OR);
   g_useExp   = (Inp_SignalMode == SIG_EXPANSION_ONLY || Inp_SignalMode == SIG_BOTH_AND || Inp_SignalMode == SIG_BOTH_OR);

   g_bucketMin   = ValidateBucketMinutes(Inp_StatsBucketMinutes);
   g_bucketCount = 1440 / g_bucketMin;

   //--- costanti di simbolo (lette una volta sola)
   g_point      = SymbolInfoDouble (_Symbol, SYMBOL_POINT);
   g_digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_lotMin     = SymbolInfoDouble (_Symbol, SYMBOL_VOLUME_MIN);
   g_lotMax     = SymbolInfoDouble (_Symbol, SYMBOL_VOLUME_MAX);
   g_lotStep    = SymbolInfoDouble (_Symbol, SYMBOL_VOLUME_STEP);
   if(g_lotStep <= 0.0) g_lotStep = 0.01;
   g_lotDigits  = (int)MathRound(-MathLog10(g_lotStep));
   if(g_lotDigits < 0) g_lotDigits = 0;
   if(g_point <= 0.0)
   { Print("Errore: SYMBOL_POINT non valido"); return INIT_FAILED; }

   trade.SetExpertMagicNumber(Inp_MagicNumber);
   trade.SetDeviationInPoints(Inp_Slippage);
   trade.SetTypeFilling(PickFilling());
   trade.SetAsyncMode(false);
   trade.LogLevel(g_debug ? LOG_LEVEL_ERRORS : LOG_LEVEL_NO);

   if(g_useDelta)
   {
      EmaHandle = iMA(_Symbol, PERIOD_CURRENT, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(EmaHandle == INVALID_HANDLE)
      { Print("Errore EMA handle: ", GetLastError()); return INIT_FAILED; }
   }

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

   if(g_useExp)
   {
      ExpATRHandle = iATR(_Symbol, PERIOD_CURRENT, Inp_ExpATRPeriod);
      if(ExpATRHandle == INVALID_HANDLE)
      { Print("Errore Exp-ATR handle: ", GetLastError()); return INIT_FAILED; }
   }

   if(Inp_UseATR_SLTP)
   {
      SLTP_ATRHandle = iATR(_Symbol, Inp_ATR_SLTP_TF, Inp_ATR_SLTP_Period);
      if(SLTP_ATRHandle == INVALID_HANDLE)
      { Print("Errore SLTP-ATR handle: ", GetLastError()); return INIT_FAILED; }
   }

   ArraySetAsSeries(g_rates,  true);
   ArraySetAsSeries(g_ema,    true);
   ArraySetAsSeries(g_atr,    true);
   ArraySetAsSeries(g_adx,    true);
   ArraySetAsSeries(g_expAtr, true);

   ResetStats();
   ArrayInitialize(trackedTicket, 0);
   ArrayInitialize(trackedBucket, -1);
   trackedCount     = 0;
   g_expPending     = false;
   g_expPendingTime = 0;
   g_runDir = 0; g_runCount = 0; g_gapBars = 0; g_lockedDir = 0;
   VolRegimeReset();

   if(!g_isOptim)
   {
      Print("============================================================");
      Print("SyntheticDelta EA v1.13 | Symbol=", _Symbol, " TF=", EnumToString((ENUM_TIMEFRAMES)Period()));
      Print("SignalMode = ", EnumToString(Inp_SignalMode),
            " | Delta=", g_useDelta ? "ON" : "OFF",
            " Expansion=", g_useExp ? "ON" : "OFF");
      if(g_useExp)
         Print("Expansion: TR/ATR>", DoubleToString(Inp_ExpThreshold,2),
               " ConfirmOffset=", Inp_ExpConfirmOffset, " AtrPeriod=", Inp_ExpATRPeriod);
      Print("Sequence Filter: ", Inp_UseSequenceFilter ? "ON" : "OFF",
            " | EnterOnSignalNo=", Inp_EnterOnSignalNo,
            " Window=", Inp_SignalWindow,
            " GapBars=", Inp_RunGapBars,
            " OppositeReset=", Inp_RequireOppositeReset ? "ON" : "OFF",
            " ResetOnRaw=", Inp_ResetOnRawSignal ? "ON" : "OFF");
      Print("Vol Filter: ", Inp_UseVolFilter ? "ON" : "OFF",
            " | Allow LOW=", Inp_AllowTradeLOW, " NORMAL=", Inp_AllowTradeNORMAL,
            " HIGH=", Inp_AllowTradeHIGH, " EXTREME=", Inp_AllowTradeEXTREME);
      Print("Report bucket = ", g_bucketMin, " min (", g_bucketCount, " fasce/giorno)");
      Print("StopsLevel broker = ", g_stopsLevel, " punti | LotStep=", DoubleToString(g_lotStep, g_lotDigits));
      Print("============================================================");
   }
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

   if(g_isOptim) return;           // niente I/O durante l'ottimizzazione
   if(MQLInfoInteger(MQL_TESTER)) return; // in single-test il report lo stampa OnTester (dati completi)
   Print("EA chiuso | Trades totali: ", totalTrades);
   PrintBucketStats();
}

//+------------------------------------------------------------------+
//| OnTick - loop principale                                          |
//| ARCHITETTURA v1.13: separazione netta tra                         |
//|   (1) FILTRI DI SEGNALE  -> decidono se esiste un segnale valido  |
//|   (2) GATE DI ESECUZIONE -> decidono se quel segnale e' tradabile |
//| In v1.12 spread/orario/1-trade-per-ora facevano return PRIMA del  |
//| calcolo del segnale: la macchina a stati dell'Expansion perdeva   |
//| barre e qualunque contatore di sequenza sarebbe stato falsato.    |
//+------------------------------------------------------------------+
void OnTick()
{
   if(Inp_UseTrailing && PositionsTotal() > 0) ManageTrailingStop();

   //--- Guardia "una volta per barra"
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   //--- Statistiche in-memory: solo fuori ottimizzazione, una volta per barra
   if(!g_isOptim) UpdateClosedTradePnL();

   //--- (0) Dati di mercato: una sola copia per barra, condivisa dai due motori
   if(!PrepareBarData()) return;

   //--- (1) SEGNALE GREZZO -----------------------------------------------
   string info    = "";
   double ndelta  = 0.0;
   int    dirDelta = 0, dirExp = 0;

   if(g_useDelta) dirDelta = GetDeltaDirection(ndelta);
   if(g_useExp)   dirExp   = GetExpansionDirection(info); // va chiamata sempre: mantiene lo stato pending

   int rawDir = CombineDirections(dirDelta, dirExp);

   //--- (2) FILTRI DI SEGNALE (ADX / S/R / regime volatilita') ------------
   int filteredDir = rawDir;
   if(filteredDir != 0)
   {
      if(!PassesADXFilter(info))                  filteredDir = 0;
      else if(!PassesSRFilter(filteredDir, info)) filteredDir = 0;
   }
   if(filteredDir != 0 && Inp_UseVolFilter && !PassesVolFilter(info)) filteredDir = 0;

   //--- (3) SEQUENCE FILTER + RESET SU SEGNALE OPPOSTO --------------------
   //    Lo stato va aggiornato SEMPRE, anche quando il trade verra' poi
   //    bloccato dai gate di esecuzione, altrimenti il conteggio salta.
   int resetDir = Inp_ResetOnRawSignal ? rawDir : filteredDir;
   int tradeDir = ApplySequenceFilter(filteredDir, resetDir, info);

   if(g_debug && (rawDir != 0 || filteredDir != 0))
      Print("bar=", TimeToString(currentBarTime, TIME_DATE|TIME_MINUTES),
            " dDelta=", dirDelta, " dExp=", dirExp,
            " raw=", rawDir, " filt=", filteredDir, " trade=", tradeDir,
            " nd=", DoubleToString(ndelta, 4),
            " run(", g_runDir, ",", g_runCount, ") lock=", g_lockedDir,
            " | ", info);

   if(tradeDir == 0) return;

   //--- (4) GATE DI ESECUZIONE -------------------------------------------
   if(Inp_UseSpreadFilter)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > Inp_MaxSpreadPoints)
      { if(g_debug) Print("Spread alto: ", spread, " pts - skip"); return; }
   }

   if(!IsTimeFilterOK()) return;

   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);

   if(Inp_OneTradePerHour && lastTradeHourKey == HourKey(dtNow))
   { if(g_debug) Print("Trade gia' aperto in questa ora - skip"); return; }

   ENUM_ORDER_TYPE ot  = (tradeDir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   int             cap = (tradeDir == 1) ? Inp_MaxBuyTrades : Inp_MaxSellTrades;
   if(Inp_UseMaxTrades && CountOpenTrades(ot) >= cap)
   { if(g_debug) Print("Max trades raggiunto per direzione ", tradeDir, " - skip"); return; }

   //--- (5) ESECUZIONE ----------------------------------------------------
   ulong ticket = 0;
   if(OpenTrade(ot, ticket))
   {
      RegisterTradeBucket(ticket, BucketIndex(dtNow));
      lastTradeHourKey = HourKey(dtNow);
      OnEntryExecuted(tradeDir);
   }
}

//+------------------------------------------------------------------+
//| PrepareBarData                                                    |
//| Copia UNA volta per barra tutti i dati serviti dai due motori.    |
//| In v1.12 ogni motore ricopiava rates+buffer per conto proprio:    |
//| in modalita' combinata sarebbe stato il doppio del lavoro.        |
//+------------------------------------------------------------------+
bool PrepareBarData()
{
   int need = MathMax(MathMax(EmaPeriod, VolAvgPeriod),
                      MathMax(ATR_Period, SR_Lookback + 2));
   need = MathMax(need, ADX_Period);
   need = MathMax(need, Inp_ExpATRPeriod);
   if(Inp_UseVolFilter) need = MathMax(need, Inp_VolAtrLen + 2);
   need += 25;

   g_barsCopied = CopyRates(_Symbol, PERIOD_CURRENT, 0, need, g_rates);
   if(g_barsCopied < 5) return false;

   if(CopyBuffer(ATRHandle, 0, 0, 5, g_atr) <= 0) return false;

   if(g_useDelta && CopyBuffer(EmaHandle, 0, 0, 5, g_ema) <= 0) return false;
   if(UseADXFilter && CopyBuffer(ADXHandle, 0, 0, 5, g_adx) <= 0) return false;
   if(g_useExp && CopyBuffer(ExpATRHandle, 0, 0, 5, g_expAtr) <= 0) return false;

   return true;
}

//+------------------------------------------------------------------+
//| GetDeltaDirection                                                 |
//| Motore Synthetic Delta PURO: nessun filtro ADX/S/R (applicati a   |
//| valle una sola volta, condivisi con l'altro motore).              |
//+------------------------------------------------------------------+
int GetDeltaDirection(double &normalizedDeltaOut)
{
   normalizedDeltaOut = 0.0;
   const int idx = 1; // barra chiusa, no look-ahead
   if(g_barsCopied < VolAvgPeriod + 2) return 0;

   double high_i  = g_rates[idx].high;
   double low_i   = g_rates[idx].low;
   double close_i = g_rates[idx].close;
   double range   = high_i - low_i;
   if(range <= 0.0) return 0;

   double tickVol = (double)g_rates[idx].tick_volume;
   if(tickVol <= 0.0) return 0;
   if(g_atr[idx] <= 0.0) return 0;   // validita' dato ATR: sempre obbligatoria

   double ema = g_ema[idx];

   // Pressione buy/sell = posizione della chiusura nel range
   double fracBuy  = (close_i - low_i)  / range;
   double fracSell = (high_i  - close_i) / range;

   // Forza bulls/bears alla Elder, normalizzata sul range
   double bullsNorm = (high_i - ema) / range;
   double bearsNorm = (ema - low_i)  / range;

   // Peso volumetrico: tick_volume vs media, cappato a 3x
   double volSum = 0.0; int volCount = 0;
   for(int j = idx; j < idx + VolAvgPeriod && j < g_barsCopied; j++)
   { volSum += (double)g_rates[j].tick_volume; volCount++; }
   double volAvg    = (volCount > 0) ? volSum / volCount : tickVol;
   double volWeight = (volAvg > 0.0) ? MathMin(tickVol / volAvg, 3.0) : 1.0;

   double synDelta = fracBuy  * (1.0 + bullsNorm) * volWeight
                   - fracSell * (1.0 + bearsNorm) * volWeight;
   double nd = synDelta / 6.0;  // fattore di scala empirico -> range ~[-1,1]
   normalizedDeltaOut = nd;

   if(nd >  SignalThreshold) return  1;
   if(nd < -SignalThreshold) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| GetExpansionDirection                                             |
//| Motore Expansion Candle PURO (nessun filtro ADX/S/R qui).         |
//| Va chiamato ad OGNI barra chiusa perche' mantiene la macchina a   |
//| stati dell'attesa di conferma (Inp_ExpConfirmOffset > 0).         |
//+------------------------------------------------------------------+
int GetExpansionDirection(string &info)
{
   if(g_barsCopied < 4) return 0;

   //--- CASO A: attesa della barra di conferma
   if(g_expPending)
   {
      int shift = iBarShift(_Symbol, PERIOD_CURRENT, g_expPendingTime, true);
      if(shift < 0)
      { g_expPending = false; if(g_debug) info += "Exp: barra rif. persa;"; return 0; }
      if(shift > Inp_ExpConfirmOffset + 1)
      { g_expPending = false; if(g_debug) info += "Exp: offset saltato (gap);"; return 0; }
      if(shift < Inp_ExpConfirmOffset + 1)
      { if(g_debug) info += StringFormat("Exp: attesa conferma %d/%d;", shift, Inp_ExpConfirmOffset + 1); return 0; }

      g_expPending = false;
      return CandleColorDirection(info, "Exp confermata");
   }

   //--- CASO B: rilevamento espansione sulla barra chiusa
   double atrVal = g_expAtr[1];
   if(atrVal <= 0.0) return 0;

   double trueRange = MathMax(g_rates[1].high - g_rates[1].low,
                       MathMax(MathAbs(g_rates[1].high - g_rates[2].close),
                               MathAbs(g_rates[1].low  - g_rates[2].close)));
   double trAtr = trueRange / atrVal;
   if(trAtr <= Inp_ExpThreshold) return 0;

   if(Inp_ExpConfirmOffset == 0)
      return CandleColorDirection(info, StringFormat("Exp TR/ATR=%.2f", trAtr));

   g_expPending     = true;
   g_expPendingTime = g_rates[1].time;
   if(g_debug) info += StringFormat("Exp TR/ATR=%.2f -> pending %d barre;", trAtr, Inp_ExpConfirmOffset);
   return 0;
}

//+------------------------------------------------------------------+
//| CandleColorDirection - bull=BUY, bear=SELL, doji=nessun segnale   |
//+------------------------------------------------------------------+
int CandleColorDirection(string &info, string tag)
{
   double o = g_rates[1].open;
   double c = g_rates[1].close;
   if(g_debug) info += tag + ";";
   if(c > o) return  1;
   if(c < o) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| CombineDirections - applica Inp_SignalMode                        |
//+------------------------------------------------------------------+
int CombineDirections(int dDelta, int dExp)
{
   switch(Inp_SignalMode)
   {
      case SIG_DELTA_ONLY:     return dDelta;
      case SIG_EXPANSION_ONLY: return dExp;
      case SIG_BOTH_AND:
         // confluenza stretta: entrambi accesi e concordi sulla stessa barra
         return (dDelta != 0 && dDelta == dExp) ? dDelta : 0;
      case SIG_BOTH_OR:
         // basta uno dei due; se sono discordi il segnale e' ambiguo -> annullato
         if(dDelta != 0 && dExp != 0 && dDelta != dExp) return 0;
         return (dDelta != 0) ? dDelta : dExp;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| PassesADXFilter - identico per entrambi i motori                  |
//+------------------------------------------------------------------+
bool PassesADXFilter(string &info)
{
   if(!UseADXFilter) return true;
   double adxVal = g_adx[1];
   if(adxVal < ADX_MinLevel)
   { if(g_debug) info += StringFormat("ADX=%.1f<%.1f skip;", adxVal, ADX_MinLevel); return false; }
   if(g_debug) info += StringFormat("ADX=%.1f;", adxVal);
   return true;
}

//+------------------------------------------------------------------+
//| PassesSRFilter                                                     |
//| Con Inp_SR_DirAware=false replica la v1.12 (simmetrico).          |
//| Con true diventa direzionale: BUY solo su supporto o breakout     |
//| rialzista, SELL solo su resistenza o breakdown ribassista. Nella  |
//| v1.12 un BUY poteva essere validato dal fatto di essere INCOLLATO |
//| alla resistenza senza averla rotta, che e' il contesto peggiore.  |
//+------------------------------------------------------------------+
bool PassesSRFilter(int dir, string &info)
{
   if(!UseSRFilter) return true;
   if(2 + SR_Lookback > g_barsCopied) return true; // dati insufficienti: non blocca (come v1.12)

   double c   = g_rates[1].close;
   double atr = g_atr[1];

   double resistance = g_rates[2].high;
   double support    = g_rates[2].low;
   for(int k = 2; k < 2 + SR_Lookback && k < g_barsCopied; k++)
   {
      if(g_rates[k].high > resistance) resistance = g_rates[k].high;
      if(g_rates[k].low  < support)    support    = g_rates[k].low;
   }

   bool nearResistance = false, nearSupport = false;
   double prox = 0.0;
   if(UseATRFilter)
   {
      prox = atr * SR_Proximity;
      nearResistance = MathAbs(c - resistance) <= prox;
      nearSupport    = MathAbs(c - support)    <= prox;
   }
   bool aboveR = (c > resistance);
   bool belowS = (c < support);

   bool srValid;
   if(Inp_SR_DirAware)
      srValid = (dir > 0) ? (nearSupport || aboveR) : (nearResistance || belowS);
   else
      srValid = nearResistance || nearSupport || aboveR || belowS;

   if(!srValid)
   { if(g_debug) info += StringFormat("S/R skip(R=%.5f S=%.5f);", resistance, support); return false; }
   if(g_debug) info += "S/R OK;";
   return true;
}

//+------------------------------------------------------------------+
//| PassesVolFilter                                                    |
//+------------------------------------------------------------------+
bool PassesVolFilter(string &info)
{
   ENUM_VOL_REGIME regime;
   double pct, pctPrev;
   if(!GetVolatilityRegime(regime, pct, pctPrev))
   { if(g_debug) info += "Vol: dati insuff.;"; return false; }

   bool allowed = (regime == VOL_LOW     && Inp_AllowTradeLOW)    ||
                  (regime == VOL_NORMAL  && Inp_AllowTradeNORMAL) ||
                  (regime == VOL_HIGH    && Inp_AllowTradeHIGH)   ||
                  (regime == VOL_EXTREME && Inp_AllowTradeEXTREME);

   if(Inp_RequireVolIncreasing && pct <= pctPrev) allowed = false;

   if(g_debug) info += StringFormat("Vol=%s pct=%.0f/%.0f %s;",
                                    EnumToString(regime), pct, pctPrev, allowed ? "OK" : "BLOCK");
   return allowed;
}

//+------------------------------------------------------------------+
//| SEQUENCE FILTER                                                    |
//| ------------------------------------------------------------------|
//| Due meccanismi indipendenti, entrambi opzionali:                  |
//|                                                                    |
//| 1) SELEZIONE NELLA RAFFICA                                         |
//|    Una "raffica" e' una serie di segnali validi consecutivi nella  |
//|    stessa direzione. g_runCount e' la posizione del segnale nella  |
//|    raffica. Si entra solo se:                                      |
//|       g_runCount >= Inp_EnterOnSignalNo   e                        |
//|       g_runCount <  Inp_EnterOnSignalNo + Inp_SignalWindow         |
//|    (con Inp_SignalWindow=0 la finestra e' illimitata).             |
//|    La raffica si chiude su segnale opposto, oppure dopo            |
//|    Inp_RunGapBars barre senza segnale (0 = mai).                   |
//|                                                                    |
//| 2) RESET SU SEGNALE OPPOSTO                                        |
//|    Dopo un'entrata in direzione D, D resta BLOCCATA finche' non    |
//|    compare un segnale di direzione -D. Quel segnale opposto non    |
//|    viene necessariamente tradato (puo' essere bloccato a sua volta |
//|    da max trades, orario, ecc.): serve solo a sbloccare D.         |
//|    Con Inp_ResetOnRawSignal=true sblocca anche un segnale opposto  |
//|    bocciato dai filtri ADX/S/R/Vol.                                |
//+------------------------------------------------------------------+
int ApplySequenceFilter(int filteredDir, int resetDir, string &info)
{
   //--- Reset del blocco: un segnale opposto sblocca la direzione lockata
   if(g_lockedDir != 0 && resetDir != 0 && resetDir == -g_lockedDir)
   {
      g_lockedDir = 0;
      if(g_debug) info += "RESET sblocco;";
   }

   if(!Inp_UseSequenceFilter)
   {
      // Solo il meccanismo di reset resta attivo (e' indipendente dal master switch
      // della selezione nella raffica, cosi' si puo' usare da solo).
      if(Inp_RequireOppositeReset && filteredDir != 0 && filteredDir == g_lockedDir)
      { if(g_debug) info += "BLOCCO: attendo segnale opposto;"; return 0; }
      return filteredDir;
   }

   //--- Aggiornamento della raffica
   if(filteredDir == 0)
   {
      g_gapBars++;
      if(Inp_RunGapBars > 0 && g_gapBars >= Inp_RunGapBars)
      { g_runDir = 0; g_runCount = 0; }
      return 0;
   }

   g_gapBars = 0;
   if(filteredDir == g_runDir) g_runCount++;
   else { g_runDir = filteredDir; g_runCount = 1; }

   //--- Blocco in attesa del segnale opposto
   if(Inp_RequireOppositeReset && filteredDir == g_lockedDir)
   { if(g_debug) info += "BLOCCO: attendo segnale opposto;"; return 0; }

   //--- Selezione posizionale nella raffica
   int startNo = MathMax(1, Inp_EnterOnSignalNo);
   if(g_runCount < startNo)
   { if(g_debug) info += StringFormat("SEQ: segnale %d < %d, skip;", g_runCount, startNo); return 0; }
   if(Inp_SignalWindow > 0 && g_runCount >= startNo + Inp_SignalWindow)
   { if(g_debug) info += StringFormat("SEQ: segnale %d fuori finestra;", g_runCount); return 0; }

   if(g_debug) info += StringFormat("SEQ: segnale %d ACCETTATO;", g_runCount);
   return filteredDir;
}

//+------------------------------------------------------------------+
//| OnEntryExecuted - aggiorna il lock dopo un'entrata effettiva      |
//+------------------------------------------------------------------+
void OnEntryExecuted(int dir)
{
   if(Inp_RequireOppositeReset) g_lockedDir = dir;
}

//+------------------------------------------------------------------+
//| VOLATILITY REGIME - versione INCREMENTALE (v1.13)                 |
//| ------------------------------------------------------------------|
//| La v1.12 ricostruiva l'INTERA serie (ATR% + Parkinson + EMA) da   |
//| zero ad ogni barra: ~(Lookback+AtrLen)*AtrLen operazioni per barra|
//| moltiplicate per ogni passata dell'optimizer.                     |
//| Qui la serie smussata vive in un ring buffer: ad ogni nuova barra |
//| si calcola UN solo valore composito e si aggiorna l'EMA in O(1).  |
//| Il ricalcolo completo scatta solo alla prima barra o dopo un gap  |
//| (barra mancante), rilevato confrontando g_rates[2].time con       |
//| l'ultima barra processata. Risultati numericamente identici.      |
//+------------------------------------------------------------------+
double   g_volRing[];
int      g_volCap   = 0;
int      g_volHead  = 0;
int      g_volCount = 0;
double   g_volEma   = 0.0;
bool     g_volInit  = false;
datetime g_volLastBar = 0;

void VolRegimeReset()
{
   g_volCap = Inp_VolLookback + 2;
   if(g_volCap < 4) g_volCap = 4;
   ArrayResize(g_volRing, g_volCap);
   ArrayInitialize(g_volRing, 0.0);
   g_volHead = 0; g_volCount = 0; g_volEma = 0.0;
   g_volInit = false; g_volLastBar = 0;
}

void VolRingPush(double v)
{
   g_volRing[g_volHead] = v;
   g_volHead = (g_volHead + 1) % g_volCap;
   if(g_volCount < g_volCap) g_volCount++;
}

// k=0 -> valore piu' recente, k=1 -> precedente, ...
double VolRingGet(int k)
{
   int idx = (g_volHead - 1 - k) % g_volCap;
   if(idx < 0) idx += g_volCap;
   return g_volRing[idx];
}

// Volatilita' composita (ATR% + Parkinson) della barra a shift 'shift' su serie temporale
double VolCompositeAt(const MqlRates &r[], int nCopied, int shift, double atrVal)
{
   double closeV = r[shift].close;
   if(closeV <= 0.0) return 0.0;
   if(atrVal <= 0.0) atrVal = g_point;
   double atrPct = (atrVal / closeV) * 100.0;

   double parkFactor = 1.0 / (4.0 * MathLog(2.0)); // stimatore Parkinson (1962)
   double sum = 0.0; int cnt = 0;
   for(int k = shift; k < shift + Inp_VolAtrLen && k < nCopied; k++)
   {
      if(r[k].low > 0.0 && r[k].high > 0.0)
         sum += parkFactor * MathPow(MathLog(r[k].high / r[k].low), 2);
      cnt++;
   }
   double parkVol = (cnt > 0) ? MathSqrt(sum / cnt) * 100.0 : 0.0;
   return (atrPct + parkVol) / 2.0;
}

// Ricostruzione completa della serie (prima barra o dopo un gap)
bool VolRegimeRebuild()
{
   int need = Inp_VolAtrLen + Inp_VolLookback + Inp_VolEmaSmooth + 10;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 1, need, r);
   if(copied < Inp_VolLookback + Inp_VolAtrLen + 2) return false;

   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(VolATRHandle, 0, 1, copied, atrArr) <= 0) return false;

   double emaAlpha = 2.0 / (Inp_VolEmaSmooth + 1.0);
   g_volHead = 0; g_volCount = 0;

   // dalla piu' vecchia (shift alto) alla piu' recente (shift 0)
   int startShift = copied - 1;
   bool seeded = false;
   for(int s = startShift; s >= 0; s--)
   {
      double comp = VolCompositeAt(r, copied, s, atrArr[s]);
      if(!seeded) { g_volEma = comp; seeded = true; }
      else        g_volEma += emaAlpha * (comp - g_volEma);
      VolRingPush(g_volEma);
   }

   g_volLastBar = r[0].time;
   g_volInit    = true;
   return true;
}

// Aggiornamento incrementale: un solo valore composito + EMA in O(1)
bool VolRegimePushCurrent()
{
   double atrArr[];
   ArraySetAsSeries(atrArr, true);
   if(CopyBuffer(VolATRHandle, 0, 1, 1, atrArr) <= 0) return false;

   double comp     = VolCompositeAt(g_rates, g_barsCopied, 1, atrArr[0]);
   double emaAlpha = 2.0 / (Inp_VolEmaSmooth + 1.0);
   g_volEma += emaAlpha * (comp - g_volEma);
   VolRingPush(g_volEma);
   g_volLastBar = g_rates[1].time;
   return true;
}

bool GetVolatilityRegime(ENUM_VOL_REGIME &regime, double &pctRankOut, double &pctRankPrevOut)
{
   bool contiguous = (g_volInit && g_barsCopied > 2 && g_rates[2].time == g_volLastBar);

   if(contiguous)
   { if(!VolRegimePushCurrent()) return false; }
   else
   { if(!VolRegimeRebuild()) return false; }

   if(g_volCount < Inp_VolLookback + 2) return false;

   //--- percentile rank della barra corrente sulle Lookback barre precedenti
   double curVol = VolRingGet(0);
   int lower = 0;
   for(int k = 1; k <= Inp_VolLookback; k++)
      if(VolRingGet(k) <= curVol) lower++;
   double pctRank = ((double)lower / Inp_VolLookback) * 100.0;

   double prevVol = VolRingGet(1);
   int lowerPrev = 0;
   for(int k = 2; k <= Inp_VolLookback + 1; k++)
      if(VolRingGet(k) <= prevVol) lowerPrev++;
   double pctRankPrev = ((double)lowerPrev / Inp_VolLookback) * 100.0;

   pctRankOut     = pctRank;
   pctRankPrevOut = pctRankPrev;

   if(pctRank      >= Inp_VolExtremeTh) regime = VOL_EXTREME;
   else if(pctRank >= Inp_VolHighTh)    regime = VOL_HIGH;
   else if(pctRank >= Inp_VolLowTh)     regime = VOL_NORMAL;
   else                                 regime = VOL_LOW;
   return true;
}

//+------------------------------------------------------------------+
//| CalcLotSize                                                        |
//| Rischio calcolato sulla distanza SL EFFETTIVA (in prezzo) passata  |
//| da OpenTrade: coincide con lo SL realmente piazzato sia a punti    |
//| fissi sia in modalita' ATR.                                        |
//+------------------------------------------------------------------+
double CalcLotSize(double slDistancePrice)
{
   if(Inp_LotMode == 0) return NormalizeLots(Inp_LotSize);

   double capital = (Inp_LotMode == 1)
                    ? AccountInfoDouble(ACCOUNT_BALANCE)
                    : AccountInfoDouble(ACCOUNT_EQUITY);
   if(capital <= 0.0) return NormalizeLots(Inp_LotSize);

   double riskMoney = capital * Inp_RiskPct / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0 || slDistancePrice <= 0.0)
      return NormalizeLots(Inp_LotSize);

   double slMoney = (slDistancePrice / tickSize) * tickValue; // perdita per 1 lotto
   if(slMoney <= 0.0) return NormalizeLots(Inp_LotSize);

   return NormalizeLots(riskMoney / slMoney);
}

double NormalizeLots(double lots)
{
   lots = MathFloor(lots / g_lotStep) * g_lotStep;
   lots = MathMax(g_lotMin, MathMin(g_lotMax, lots));
   return NormalizeDouble(lots, g_lotDigits);
}

//+------------------------------------------------------------------+
//| GetCurrentATR - ATR per SL/TP dinamici (TF indipendente)          |
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
//| v1.13: rispetta SYMBOL_TRADE_STOPS_LEVEL (distanza minima imposta  |
//| dal broker). Senza questo controllo, su simboli con stops level    |
//| non nullo, gli ordini con SL/TP troppo stretti vengono rifiutati    |
//| con retcode 10016 "Invalid stops".                                 |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_ORDER_TYPE orderType, ulong &outTicket)
{
   outTicket = 0;
   bool isBuy = (orderType == ORDER_TYPE_BUY);

   double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price <= 0.0) return false;

   double slDistance, tpDistance;
   if(Inp_UseATR_SLTP)
   {
      double atrVal = GetCurrentATR();
      if(atrVal <= 0.0)  // fallback: se l'ATR non e' disponibile usa i punti fissi
         atrVal = Inp_StopLoss * g_point / MathMax(Inp_ATR_SL_Mult, 0.01);
      slDistance = atrVal * Inp_ATR_SL_Mult;
      tpDistance = atrVal * Inp_ATR_TP_Mult;
   }
   else
   {
      slDistance = Inp_StopLoss   * g_point;
      tpDistance = Inp_TakeProfit * g_point;
   }

   double minStop = (double)g_stopsLevel * g_point;
   if(minStop > 0.0)
   {
      if(slDistance < minStop) slDistance = minStop;
      if(tpDistance < minStop) tpDistance = minStop;
   }

   double sl = isBuy ? NormalizeDouble(price - slDistance, g_digits)
                     : NormalizeDouble(price + slDistance, g_digits);
   double tp = 0.0;
   if(Inp_UseTP)
      tp = isBuy ? NormalizeDouble(price + tpDistance, g_digits)
                 : NormalizeDouble(price - tpDistance, g_digits);

   double lots = CalcLotSize(slDistance);
   if(lots <= 0.0) return false;

   string comment = isBuy ? "SD_EA_L" : "SD_EA_S";

   bool ok = isBuy ? trade.Buy (lots, _Symbol, price, sl, tp, comment)
                   : trade.Sell(lots, _Symbol, price, sl, tp, comment);

   if(!ok)
   {
      if(!g_isOptim)
         Print("Errore apertura: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
      return false;
   }

   //--- Position ID robusto: dal deal di apertura, non dal ticket ordine
   ulong posId = 0;
   ulong dealTicket = trade.ResultDeal();
   if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      posId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   if(posId == 0) posId = trade.ResultOrder();
   outTicket = posId;
   totalTrades++;

   if(g_debug)
      Print("APERTURA ", isBuy ? "LONG" : "SHORT",
            " @", DoubleToString(price, g_digits),
            " SL=", DoubleToString(sl, g_digits),
            " TP=", tp > 0 ? DoubleToString(tp, g_digits) : "OFF",
            " Lots=", DoubleToString(lots, g_lotDigits),
            " pos=", posId);

   if(Inp_EnableAlerts && !g_isOptim)
      Alert(StringFormat("SD EA: %s @ %s", isBuy ? "LONG" : "SHORT", DoubleToString(price, g_digits)));

   return true;
}

//+------------------------------------------------------------------+
//| ManageTrailingStop - trailing lineare a step, con rispetto del    |
//| livello di stop minimo del broker                                  |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double minStop = (double)g_stopsLevel * g_point;
   double trailDist = Inp_TrailingStop * g_point;
   if(trailDist < minStop) trailDist = minStop;
   double stepDist = Inp_TrailingStep * g_point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double oldSL     = PositionGetDouble(POSITION_SL);
      double posTP     = PositionGetDouble(POSITION_TP);

      if(posType == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if((bid - openPrice) / g_point < Inp_TrailingStart) continue;
         double newSL = NormalizeDouble(bid - trailDist, g_digits);
         if(newSL <= 0.0) continue;
         if(oldSL == 0.0 || newSL > oldSL + stepDist)
            trade.PositionModify(ticket, newSL, posTP);
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if((openPrice - ask) / g_point < Inp_TrailingStart) continue;
         double newSL = NormalizeDouble(ask + trailDist, g_digits);
         if(oldSL == 0.0 || newSL < oldSL - stepDist)
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
   ENUM_POSITION_TYPE want = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == want) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| IsTimeFilterOK - fasce inclusive, supporta fasce overnight        |
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
   if(Inp_UseTimeFilter1 && Inp_UseTimeFilter2) return (f1 || f2);
   return (Inp_UseTimeFilter1 ? f1 : f2);
}

datetime HourKey(const MqlDateTime &dt)
{
   return (datetime)(dt.year * 1000000L + dt.mon * 10000L + dt.day * 100L + dt.hour);
}

//+------------------------------------------------------------------+
//| STATISTICHE A BUCKET DI MINUTI (v1.13)                            |
//| ------------------------------------------------------------------|
//| La v1.12 aggregava solo per ora (24 secchi). Qui il giorno e'     |
//| diviso in 1440/g_bucketMin fasce, cosi' il report dice non solo   |
//| "l'ora 09 e' la migliore" ma "09:15-09:30 e' la migliore".        |
//| ATTENZIONE STATISTICA: piu' stretto e' il bucket, meno trade      |
//| cadono in ciascuno e piu' il risultato e' rumore. Con 200 trade   |
//| e bucket da 5 minuti hai in media 0.7 trade per fascia: quello    |
//| che leggi NON e' un edge orario, e' campionamento casuale. Usa    |
//| Inp_StatsMinTrades (>=10-20) per non prendere per buono il caso.  |
//+------------------------------------------------------------------+
int BucketIndex(const MqlDateTime &dt)
{
   int idx = (dt.hour * 60 + dt.min) / g_bucketMin;
   if(idx < 0) idx = 0;
   if(idx >= g_bucketCount) idx = g_bucketCount - 1;
   return idx;
}

string BucketLabel(int idx)
{
   int s = idx * g_bucketMin;
   int e = s + g_bucketMin;
   return StringFormat("%02d:%02d-%02d:%02d", s / 60, s % 60, (e / 60) % 25, e % 60);
}

void ResetStats()
{
   ArrayInitialize(g_bucketPnL,    0.0);
   ArrayInitialize(g_bucketTrades, 0);
   ArrayInitialize(g_bucketWins,   0);
}

void RegisterTradeBucket(ulong posId, int bucketIdx)
{
   if(g_isOptim) return;              // in ottimizzazione le stats si ricostruiscono da storico
   if(trackedCount >= MAX_TRACK) UpdateClosedTradePnL(); // compatta prima di arrendersi
   if(trackedCount >= MAX_TRACK) return;
   trackedTicket[trackedCount] = posId;
   trackedBucket[trackedCount] = bucketIdx;
   trackedCount++;
}

//+------------------------------------------------------------------+
//| UpdateClosedTradePnL                                               |
//| v1.13: (a) chiamata una volta per barra e non ad ogni tick;       |
//|        (b) compattazione dello slot (swap-remove) -> il buffer    |
//|            non si satura piu' silenziosamente dopo N trade;       |
//|        (c) somma TUTTI i deal della posizione (chiusure parziali) |
//|            inclusa la COMMISSIONE DEL DEAL DI APERTURA, che la    |
//|            v1.12 ignorava: su conto raw FP Markets la commissione |
//|            e' addebitata all'ingresso, quindi il PnL per fascia   |
//|            oraria era sistematicamente ottimista.                 |
//+------------------------------------------------------------------+
void UpdateClosedTradePnL()
{
   for(int t = trackedCount - 1; t >= 0; t--)
   {
      ulong posId = trackedTicket[t];
      if(PositionSelectByTicket(posId)) continue;      // ancora aperta
      if(!HistorySelectByPosition(posId)) continue;

      int    deals  = (int)HistoryDealsTotal();
      double profit = 0.0;
      bool   hasOut = false;
      for(int d = 0; d < deals; d++)
      {
         ulong dt = HistoryDealGetTicket(d);
         if(dt == 0) continue;
         profit += HistoryDealGetDouble(dt, DEAL_PROFIT)
                 + HistoryDealGetDouble(dt, DEAL_SWAP)
                 + HistoryDealGetDouble(dt, DEAL_COMMISSION);
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt, DEAL_ENTRY) == DEAL_ENTRY_OUT) hasOut = true;
      }
      if(!hasOut) continue;

      int b = trackedBucket[t];
      if(b >= 0 && b < g_bucketCount)
      {
         g_bucketPnL[b] += profit;
         g_bucketTrades[b]++;
         if(profit > 0.0) g_bucketWins[b]++;
      }
      //--- swap-remove
      trackedCount--;
      trackedTicket[t] = trackedTicket[trackedCount];
      trackedBucket[t] = trackedBucket[trackedCount];
   }
}

//+------------------------------------------------------------------+
//| BuildStatsFromHistory                                              |
//| Ricostruzione completa dallo storico deal, singola passata O(n*k) |
//| con k = posizioni contemporaneamente aperte (tipicamente 1-2).    |
//| La v1.12 usava un doppio ciclo annidato O(n^2): su un backtest    |
//| con qualche migliaio di operazioni erano milioni di iterazioni    |
//| ripetute ad OGNI passata dell'optimizer.                          |
//+------------------------------------------------------------------+
#define MAX_OPEN_TRACK 256
void BuildStatsFromHistory()
{
   ResetStats();
   if(!HistorySelect(0, TimeCurrent())) return;

   ulong  openPos   [MAX_OPEN_TRACK];
   int    openBucket[MAX_OPEN_TRACK];
   double openProfit[MAX_OPEN_TRACK];
   double openVol   [MAX_OPEN_TRACK];
   int    openCount = 0;

   int total = (int)HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong dt = HistoryDealGetTicket(i);
      if(dt == 0) continue;
      if(HistoryDealGetInteger(dt, DEAL_MAGIC) != Inp_MagicNumber) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt, DEAL_ENTRY);
      ulong  posId  = (ulong)HistoryDealGetInteger(dt, DEAL_POSITION_ID);
      double vol    = HistoryDealGetDouble(dt, DEAL_VOLUME);
      double money  = HistoryDealGetDouble(dt, DEAL_PROFIT)
                    + HistoryDealGetDouble(dt, DEAL_SWAP)
                    + HistoryDealGetDouble(dt, DEAL_COMMISSION);

      if(entry == DEAL_ENTRY_IN)
      {
         if(openCount >= MAX_OPEN_TRACK) continue;
         MqlDateTime d; TimeToStruct((datetime)HistoryDealGetInteger(dt, DEAL_TIME), d);
         openPos   [openCount] = posId;
         openBucket[openCount] = BucketIndex(d);
         openProfit[openCount] = money;   // include la commissione di ingresso
         openVol   [openCount] = vol;
         openCount++;
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         for(int k = 0; k < openCount; k++)
         {
            if(openPos[k] != posId) continue;
            openProfit[k] += money;
            openVol   [k] -= vol;
            if(openVol[k] <= 0.0000001)   // posizione completamente chiusa
            {
               int b = openBucket[k];
               if(b >= 0 && b < g_bucketCount)
               {
                  g_bucketPnL[b] += openProfit[k];
                  g_bucketTrades[b]++;
                  if(openProfit[k] > 0.0) g_bucketWins[b]++;
               }
               openCount--;
               openPos   [k] = openPos   [openCount];
               openBucket[k] = openBucket[openCount];
               openProfit[k] = openProfit[openCount];
               openVol   [k] = openVol   [openCount];
            }
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PrintBucketStats - report fasce migliori/peggiori + rollup orario |
//+------------------------------------------------------------------+
void PrintBucketStats()
{
   int idxs[]; ArrayResize(idxs, g_bucketCount);
   int n = 0;
   double totPnL = 0.0; int totTrades = 0, totWins = 0;

   for(int i = 0; i < g_bucketCount; i++)
   {
      totPnL    += g_bucketPnL[i];
      totTrades += g_bucketTrades[i];
      totWins   += g_bucketWins[i];
      if(g_bucketTrades[i] >= MathMax(1, Inp_StatsMinTrades)) idxs[n++] = i;
   }
   ArrayResize(idxs, n);

   Print("============================================================");
   Print("STATISTICHE PER FASCIA - SyntheticDelta EA v1.13 | bucket=", g_bucketMin, " min");
   Print("Totale: ", totTrades, " trade | PnL ", DoubleToString(totPnL, 2),
         " | winrate ", totTrades > 0 ? DoubleToString((double)totWins / totTrades * 100.0, 1) : "0.0", "%");
   if(n == 0)
   { Print("Nessuna fascia con almeno ", Inp_StatsMinTrades, " trade."); Print("============================================================"); return; }

   //--- ordinamento decrescente per PnL (selection sort: n piccolo)
   for(int i = 0; i < n - 1; i++)
      for(int j = i + 1; j < n; j++)
         if(g_bucketPnL[idxs[j]] > g_bucketPnL[idxs[i]])
         { int tmp = idxs[i]; idxs[i] = idxs[j]; idxs[j] = tmp; }

   int show = (Inp_StatsTopN > 0) ? MathMin(Inp_StatsTopN, n) : n;

   Print("------------------------------------------------------------");
   Print(StringFormat("%-14s %-7s %-11s %-9s %-9s", "FASCIA", "TRADES", "PnL TOT", "WIN%", "AVG PnL"));
   Print("--- MIGLIORI -----------------------------------------------");
   for(int i = 0; i < show; i++) PrintBucketRow(idxs[i]);

   if(Inp_StatsTopN > 0 && n > 2 * show)
   {
      Print("--- PEGGIORI -----------------------------------------------");
      for(int i = n - show; i < n; i++) PrintBucketRow(idxs[i]);
   }

   //--- rollup orario (utile per impostare Inp_StartHour/EndHour)
   if(g_bucketMin < 60)
   {
      Print("--- ROLLUP ORARIO ------------------------------------------");
      for(int h = 0; h < 24; h++)
      {
         double p = 0.0; int tr = 0, w = 0;
         int perHour = 60 / g_bucketMin;
         for(int b = h * perHour; b < (h + 1) * perHour; b++)
         { p += g_bucketPnL[b]; tr += g_bucketTrades[b]; w += g_bucketWins[b]; }
         if(tr == 0) continue;
         Print(StringFormat("%02d:00-%02d:00   %-7d %-11.2f %-9.1f %-9.2f",
               h, h + 1, tr, p, (double)w / tr * 100.0, p / tr));
      }
   }
   Print("============================================================");
}

void PrintBucketRow(int b)
{
   int tr = g_bucketTrades[b];
   if(tr == 0) return;
   Print(StringFormat("%-14s %-7d %-11.2f %-9.1f %-9.2f",
         BucketLabel(b), tr, g_bucketPnL[b],
         (double)g_bucketWins[b] / tr * 100.0, g_bucketPnL[b] / tr));
}

//+------------------------------------------------------------------+
//| OnTester                                                           |
//| ------------------------------------------------------------------|
//| FIT_LEGACY replica la v1.12 solo per confronto: pesa il winrate    |
//| al 60% e non penalizza il numero di trade, quindi in ottimizzazione|
//| premia set con 12 trade e 75% di winrate che non sopravvivono a un |
//| walk-forward. Non usarla per decidere dove mettere capitale.       |
//| FIT_RECOVERY_PF (default) = RecoveryFactor * min(PF,3) * penalita' |
//| quadratica sotto Inp_Fit_MinTrades. Cerca robustezza, non bellezza.|
//| FIT_SHARPE_N usa lo Sharpe nativo del tester con la stessa         |
//| penalita' sul campione.                                            |
//+------------------------------------------------------------------+
double OnTester()
{
   if(!g_isOptim)
   {
      BuildStatsFromHistory();
      PrintBucketStats();
   }

   double profit      = TesterStatistics(STAT_PROFIT);
   double maxDD       = TesterStatistics(STAT_BALANCE_DD);
   double winTrades   = TesterStatistics(STAT_PROFIT_TRADES);
   double totalTrd    = TesterStatistics(STAT_TRADES);
   double profitFact  = TesterStatistics(STAT_PROFIT_FACTOR);
   double sharpe      = TesterStatistics(STAT_SHARPE_RATIO);

   if(totalTrd <= 0.0) return 0.0;
   if(maxDD <= 0.0) maxDD = 1.0;   // nessun drawdown registrato: evita divisione per zero

   //--- penalita' sul campione: sotto Inp_Fit_MinTrades la fitness crolla
   double minT    = MathMax(1, Inp_Fit_MinTrades);
   double penalty = (totalTrd >= minT) ? 1.0 : MathPow(totalTrd / minT, 2.0);

   switch(Inp_FitnessMode)
   {
      case FIT_LEGACY:
      {
         double rf = profit / maxDD;
         double wr = (winTrades / totalTrd) * 100.0;
         return (rf * 0.4) + (wr * 0.6);
      }
      case FIT_SHARPE_N:
         if(profit <= 0.0) return profit / 1.0e9;
         return sharpe * penalty;

      case FIT_RECOVERY_PF:
      default:
      {
         if(profit <= 0.0) return profit / 1.0e9; // le perdite restano ordinate tra loro, sotto ogni set profittevole
         double rf = profit / maxDD;
         double pf = (profitFact > 0.0) ? MathMin(profitFact, 3.0) : 1.0;
         return rf * pf * penalty;
      }
   }
   return 0.0;
}
//+------------------------------------------------------------------+
