//+------------------------------------------------------------------+
//|                        CCI_MultiMode_EA_v3.mq5                   |
//|  Expert Advisor: segnali CCI + filtro AMA, SL/TP Points|ATR|Candela|
//|  Trailing selezionabile (Points/ATR/Smart), Break-Even,          |
//|  controlli rischio giornalieri, sizing su tick value reale.      |
//|                                                                  |
//|  v3.00 - Revisione strutturale completa:                         |
//|   - ManageOpenPositions() eseguita su OGNI tick, prima dei gate   |
//|   - contatori giornalieri ricostruiti da storico (reset a nuovo gg)|
//|   - HistorySelect() prima di leggere lo storico                   |
//|   - crossover CCI letto da 2 barre chiuse (niente stato globale)   |
//|   - filtri orari in OR + supporto finestre a cavallo di mezzanotte |
//|   - un solo modulo di trailing attivo (enum) -> 1 modify per tick  |
//|   - sizing su SYMBOL_TRADE_TICK_VALUE/TICK_SIZE + normalizzazione  |
//|   - validazione STOPS_LEVEL/FREEZE_LEVEL e NormalizeDouble         |
//|   - tutti i loop filtrati per simbolo + magic                      |
//|   - handle indicatori creati in OnInit e rilasciati in OnDeinit    |
//|                                                                  |
//|  Author: Joshua                                                  |
//+------------------------------------------------------------------+
#property version   "3.00"
#property description "CCI EA - versione corretta con filtro AMA e risk management"
#property copyright "2025"

#include <Trade\Trade.mqh>
CTrade trade;

//======================== ENUM MODALITA' =============================
enum ENUM_LOT_MODE
  {
   LOT_FIXED         = 0,  // Lotto fisso
   LOT_RISK_PERCENT  = 1   // % di rischio sul balance
  };

enum ENUM_SL_MODE
  {
   SL_MODE_POINTS      = 0, // SL in punti
   SL_MODE_ATR         = 1, // SL da ATR
   SL_MODE_PREVCANDLE  = 2  // SL su estremo candele precedenti
  };

enum ENUM_TP_MODE
  {
   TP_MODE_NONE    = 0, // Nessun TP
   TP_MODE_POINTS  = 1, // TP in punti
   TP_MODE_ATR     = 2, // TP da ATR
   TP_MODE_RR      = 3  // TP come multiplo del rischio (R:R)
  };

enum ENUM_TRAIL_MODE
  {
   TRAIL_NONE    = 0, // Trailing disattivato
   TRAIL_POINTS  = 1, // Trailing in punti
   TRAIL_ATR     = 2, // Trailing da ATR
   TRAIL_SMART   = 3  // Smart trailing a scaglioni
  };

enum ENUM_BE_MODE
  {
   BE_MODE_OFF     = 0, // Break-even disattivato
   BE_MODE_POINTS  = 1, // Break-even in punti
   BE_MODE_ATR     = 2  // Break-even da ATR
  };

//======================== INPUTS =====================================
input group "=== Generale ==="
input bool   EnableEA                 = true;    // Abilita EA
input bool   OnlyOnNewBar             = true;    // Segnali solo a candela chiusa
input bool   PrintLogs                = true;    // Stampa log
input ulong  MagicNumber              = 880011;  // Magic number
input int    SlippagePoints           = 5;       // Deviazione massima (punti)

input group "=== Filtro spread ==="
input bool   UseSpreadFilter          = true;    // Abilita filtro spread
input double MaxSpreadPoints          = 40.0;    // Spread massimo (punti)

input group "=== Money management ==="
input ENUM_LOT_MODE LotMode           = LOT_FIXED; // Modalita' calcolo lotto
input double LotFixed                 = 0.01;    // Lotto fisso
input double RiskPercent              = 1.0;     // Rischio % per trade
input double MinLot                   = 0.01;    // Lotto minimo (clamp utente)
input double MaxLot                   = 100.0;   // Lotto massimo (clamp utente)
input double MaxMarginUsagePercent    = 30.0;    // Max margine impegnabile (% equity, 0=off)

input group "=== Segnale CCI ==="
input ENUM_TIMEFRAMES CCI_Timeframe   = PERIOD_CURRENT;   // Timeframe CCI (= TF di lavoro)
input int    CCI_Period               = 20;      // Periodo CCI
input ENUM_APPLIED_PRICE CCI_Price    = PRICE_TYPICAL;    // Prezzo CCI
input double CCI_BuyThreshold         = 50.0;    // Soglia crossover Buy
input double CCI_SellThreshold        = -50.0;   // Soglia crossover Sell

input group "=== Filtro di trend AMA ==="
input bool   UseAMAFilter             = true;    // Usa AMA come filtro direzionale
input ENUM_TIMEFRAMES AMA_Timeframe   = PERIOD_CURRENT;   // Timeframe AMA
input int    AMA_Period               = 10;      // Periodo AMA (Efficiency Ratio)
input int    AMA_FastEMA              = 2;       // Fast EMA
input int    AMA_SlowEMA              = 30;      // Slow EMA
input int    AMA_Shift                = 0;       // Shift orizzontale AMA (NON e' smoothing)
input ENUM_APPLIED_PRICE AMA_Price    = PRICE_CLOSE;      // Prezzo AMA
input bool   AMA_UseSlope             = false;   // Richiedi anche pendenza AMA concorde

input group "=== Comportamento ingressi ==="
input bool   UseCloseOnOppositeSignal = true;    // Chiudi posizione su segnale opposto
input int    MaxPositionsPerSymbol    = 1;       // Max posizioni totali sul simbolo

input group "=== Stop Loss ==="
input ENUM_SL_MODE SL_Mode            = SL_MODE_POINTS;   // Modalita' SL
input int    SL_Points                = 500;     // SL in punti
input int    SL_ATR_Period            = 14;      // Periodo ATR per SL
input double SL_ATR_Mult              = 1.5;     // Moltiplicatore ATR per SL
input int    PrevCandlesBack          = 1;       // Candele indietro per SL su estremo
input int    PrevCandle_BufferPoints  = 20;      // Buffer oltre l'estremo (punti)

input group "=== Take Profit ==="
input ENUM_TP_MODE TP_Mode            = TP_MODE_POINTS;   // Modalita' TP
input int    TP_Points                = 500;     // TP in punti
input int    TP_ATR_Period            = 14;      // Periodo ATR per TP
input double TP_ATR_Mult              = 1.5;     // Moltiplicatore ATR per TP
input double TP_RR_Ratio              = 2.0;     // R:R quando TP_Mode = RR

input group "=== Trailing stop ==="
input ENUM_TRAIL_MODE TrailMode       = TRAIL_ATR;        // Modalita' trailing (una sola)
input int    Trailing_MinStepPoints   = 10;      // Movimento minimo per inviare modify
input int    Trailing_Points_Start    = 300;     // [POINTS] attivazione (punti di profitto)
input int    Trailing_Points_Step     = 100;     // [POINTS] distanza SL dal prezzo
input int    Trailing_ATR_Period      = 14;      // [ATR] periodo ATR
input double Trailing_ATR_StartMult   = 1.0;     // [ATR] attivazione: profitto >= mult*ATR
input double Trailing_ATR_Mult        = 1.5;     // [ATR] distanza SL = mult*ATR
input int    Smart_Start_Points       = 200;     // [SMART] attivazione
input int    Smart_Rpoints            = 100;     // [SMART] ampiezza scaglione
input int    Smart_Step1              = 150;     // [SMART] distanza SL scaglione 1
input int    Smart_Step2              = 100;     // [SMART] distanza SL scaglione 2
input int    Smart_Step3              = 60;      // [SMART] distanza SL scaglione 3

input group "=== Break-even ==="
input ENUM_BE_MODE BE_Mode            = BE_MODE_ATR;      // Modalita' break-even
input int    BE_Trigger_Points        = 250;     // [POINTS] trigger
input int    BE_Offset_Points         = 10;      // [POINTS] offset oltre l'apertura
input int    BE_ATR_Period            = 14;      // [ATR] periodo
input double BE_ATR_TriggerMult       = 1.0;     // [ATR] moltiplicatore trigger
input double BE_ATR_OffsetMult        = 0.2;     // [ATR] moltiplicatore offset

input group "=== Filtri orari (server time, in OR) ==="
input bool   TF1_Enable               = false;   // Finestra 1
input int    TF1_StartHour            = 8;
input int    TF1_StartMin             = 0;
input int    TF1_EndHour              = 11;
input int    TF1_EndMin               = 59;
input bool   TF2_Enable               = false;   // Finestra 2
input int    TF2_StartHour            = 14;
input int    TF2_StartMin             = 0;
input int    TF2_EndHour              = 17;
input int    TF2_EndMin               = 59;
input bool   TF3_Enable               = false;   // Finestra 3
input int    TF3_StartHour            = 19;
input int    TF3_StartMin             = 0;
input int    TF3_EndHour              = 22;
input int    TF3_EndMin               = 59;

input group "=== Controlli rischio giornalieri ==="
input bool   EnableMaxDailyTrades     = true;    // Abilita limite trade/giorno
input int    MaxDailyTrades           = 10;      // Numero massimo trade al giorno
input bool   EnableDailyLossCut       = true;    // Abilita stop perdite giornaliero
input double DailyLossCutAmount       = 100.0;   // Perdita massima giornaliera (valuta conto)
input bool   DailyLossCut_IncludeFloating = true;// Includi P/L flottante nel calcolo
input bool   DailyLossCut_CloseOpen   = false;   // Chiudi le posizioni quando scatta

input group "=== Sicurezza ordini ==="
input int    StopsSafetyPoints        = 5;       // Margine extra sopra lo stops level

//======================== GLOBALS ====================================
datetime        g_lastBarTime   = 0;
ENUM_TIMEFRAMES g_tf            = PERIOD_CURRENT;   // TF di lavoro risolto
ENUM_TIMEFRAMES g_amaTF         = PERIOD_CURRENT;   // TF AMA risolto

int    g_cciHandle = INVALID_HANDLE;
int    g_amaHandle = INVALID_HANDLE;

#define MAX_ATR_SLOTS 8
int    g_atrPeriods[MAX_ATR_SLOTS];
int    g_atrHandles[MAX_ATR_SLOTS];
int    g_atrCount = 0;

double g_dailyRealized = 0.0;   // P/L realizzato oggi (profit+swap+commission)
int    g_dailyTrades   = 0;     // ingressi eseguiti oggi (da storico)
datetime g_statsDay    = 0;     // giorno a cui si riferiscono le statistiche
datetime g_lastSignalBar = 0;   // barra su cui e' gia' stato processato un segnale
bool   g_statsReady    = false;
bool   g_initOK        = false;

//======================== UTILITY ====================================
void Log(string msg)
  {
   if(PrintLogs)
      Print(TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+" | "+msg);
  }

ENUM_TIMEFRAMES ResolveTF(ENUM_TIMEFRAMES tf)
  {
   return (tf==PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : tf;
  }

double BidPrice() { return SymbolInfoDouble(_Symbol, SYMBOL_BID); }
double AskPrice() { return SymbolInfoDouble(_Symbol, SYMBOL_ASK); }

double NormPrice(double p)
  {
   return NormalizeDouble(p, _Digits);
  }

//--- distanza minima ammessa per SL/TP dal prezzo corrente
double MinStopDistance()
  {
   long   stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double lvl       = (double)MathMax(stopsLvl, freezeLvl) * _Point;
   double spread    = AskPrice() - BidPrice();
   return MathMax(lvl, spread) + StopsSafetyPoints * _Point;
  }

double CurrentSpreadPoints()
  {
   double s = (AskPrice() - BidPrice()) / _Point;
   return (s > 0.0) ? s : 0.0;
  }

bool SpreadOK()
  {
   if(!UseSpreadFilter || MaxSpreadPoints <= 0.0)
      return true;
   return (CurrentSpreadPoints() <= MaxSpreadPoints);
  }

//======================== ATR HANDLE REGISTRY ========================
int RegisterATR(int period)
  {
   if(period <= 0)
      return INVALID_HANDLE;
   for(int i=0; i<g_atrCount; i++)
      if(g_atrPeriods[i] == period)
         return g_atrHandles[i];

   if(g_atrCount >= MAX_ATR_SLOTS)
     {
      Print("ATR: slot handle esauriti.");
      return INVALID_HANDLE;
     }
   int h = iATR(_Symbol, g_tf, period);
   if(h == INVALID_HANDLE)
      return INVALID_HANDLE;

   g_atrPeriods[g_atrCount] = period;
   g_atrHandles[g_atrCount] = h;
   g_atrCount++;
   return h;
  }

//--- ritorna ATR della barra chiusa; 0.0 = dato non disponibile (chiamante deve abortire)
double GetATR(int period, int shift=1)
  {
   int h = RegisterATR(period);
   if(h == INVALID_HANDLE)
      return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(h, 0, shift, 1, buf) < 1)
      return 0.0;
   if(buf[0] <= 0.0 || !MathIsValidNumber(buf[0]))
      return 0.0;
   return buf[0];
  }

//======================== FILTRI ORARI ===============================
//--- gestisce anche finestre a cavallo di mezzanotte (start > end)
bool InWindow(int sh, int sm, int eh, int em, datetime t)
  {
   MqlDateTime tm;
   TimeToStruct(t, tm);
   int now   = tm.hour*60 + tm.min;
   int start = sh*60 + sm;
   int end   = eh*60 + em;

   if(start <= end)
      return (now >= start && now <= end);
   return (now >= start || now <= end);   // wrap-around
  }

//--- OR sulle finestre abilitate; nessuna abilitata = sempre aperto
bool TimeFiltersPassed(datetime t)
  {
   bool anyEnabled = (TF1_Enable || TF2_Enable || TF3_Enable);
   if(!anyEnabled)
      return true;

   if(TF1_Enable && InWindow(TF1_StartHour,TF1_StartMin,TF1_EndHour,TF1_EndMin,t)) return true;
   if(TF2_Enable && InWindow(TF2_StartHour,TF2_StartMin,TF2_EndHour,TF2_EndMin,t)) return true;
   if(TF3_Enable && InWindow(TF3_StartHour,TF3_StartMin,TF3_EndHour,TF3_EndMin,t)) return true;
   return false;
  }

//======================== POSIZIONI: HELPER ==========================
//--- true se la posizione selezionata appartiene a questo EA e a questo simbolo
bool IsOurPosition()
  {
   if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber) return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)            return false;
   return true;
  }

int CountOurPositions(int dir=0)
  {
   int total = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!IsOurPosition()) continue;

      if(dir == 0) { total++; continue; }

      long type = PositionGetInteger(POSITION_TYPE);
      if((dir > 0 && type == POSITION_TYPE_BUY) || (dir < 0 && type == POSITION_TYPE_SELL))
         total++;
     }
   return total;
  }

double FloatingPnL()
  {
   double pnl = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!IsOurPosition()) continue;
      pnl += PositionGetDouble(POSITION_PROFIT)
           + PositionGetDouble(POSITION_SWAP);
     }
   return pnl;
  }

void CloseAllOurPositions(string reason)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!IsOurPosition()) continue;

      if(!trade.PositionClose(ticket))
         Log("Chiusura fallita ticket="+(string)ticket+" retcode="+(string)trade.ResultRetcode());
      else
         Log("Chiusa ("+reason+") ticket="+(string)ticket);
     }
  }

void CloseOppositePositions(int dir)
  {
   long oppType = (dir > 0) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!IsOurPosition()) continue;
      if(PositionGetInteger(POSITION_TYPE) != oppType) continue;

      if(trade.PositionClose(ticket))
         Log("Chiuso opposto ticket="+(string)ticket);
      else
         Log("Chiusura opposto fallita ticket="+(string)ticket+" retcode="+(string)trade.ResultRetcode());
     }
  }

//======================== STATISTICHE GIORNALIERE ====================
datetime TodayStart()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   t.hour = 0; t.min = 0; t.sec = 0;
   return StructToTime(t);
  }

//--- ricostruisce trade e P/L realizzato del giorno dallo storico
//--- (niente contatori persistenti: reset automatico a cambio giornata)
void UpdateDailyStats()
  {
   datetime dayStart = TodayStart();
   g_statsDay      = dayStart;
   g_dailyRealized = 0.0;
   g_dailyTrades   = 0;

   if(!HistorySelect(dayStart, TimeCurrent() + 60))
     {
      Log("HistorySelect fallita: statistiche giornaliere non aggiornate.");
      return;
     }

   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN)
         g_dailyTrades++;

      g_dailyRealized += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                       + HistoryDealGetDouble(ticket, DEAL_SWAP)
                       + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
     }
   g_statsReady = true;
  }

double DailyPnL()
  {
   double pnl = g_dailyRealized;
   if(DailyLossCut_IncludeFloating)
      pnl += FloatingPnL();
   return pnl;
  }

//======================== SIZING =====================================
double NormalizeLot(double lot)
  {
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;

   double loBound = MathMax(vmin, MinLot);
   double hiBound = MathMin(vmax, MaxLot);
   if(hiBound < loBound) hiBound = loBound;

   lot = MathFloor(lot/step) * step;   // arrotonda per difetto: mai sovra-rischiare
   lot = MathMax(lot, loBound);
   lot = MathMin(lot, hiBound);

   int volDigits = 0;
   double s = step;
   while(s < 1.0 && volDigits < 8) { s *= 10.0; volDigits++; }
   return NormalizeDouble(lot, volDigits);
  }

//--- lotto da distanza di stop espressa in PREZZO (non in punti)
double CalcLot(double slDistancePrice)
  {
   double lot = LotFixed;

   if(LotMode == LOT_RISK_PERCENT)
     {
      if(slDistancePrice <= 0.0)
        {
         Log("Rischio %: distanza SL nulla, fallback su LotFixed.");
        }
      else
        {
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickValue > 0.0 && tickSize > 0.0)
           {
            double lossPerLot = (slDistancePrice / tickSize) * tickValue;
            if(lossPerLot > 0.0)
              {
               double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (RiskPercent / 100.0);
               lot = riskMoney / lossPerLot;
              }
           }
         else
            Log("TICK_VALUE/TICK_SIZE non disponibili, fallback su LotFixed.");
        }
     }
   return NormalizeLot(lot);
  }

//--- riduce il lotto se il margine richiesto supera il tetto impostato
double ApplyMarginCap(int dir, double lot)
  {
   if(MaxMarginUsagePercent <= 0.0)
      return lot;

   ENUM_ORDER_TYPE ot = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (dir > 0) ? AskPrice() : BidPrice();
   double margin = 0.0;
   if(!OrderCalcMargin(ot, _Symbol, lot, price, margin) || margin <= 0.0)
      return lot;

   double cap = AccountInfoDouble(ACCOUNT_EQUITY) * (MaxMarginUsagePercent / 100.0);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   cap = MathMin(cap, freeMargin);
   if(margin <= cap)
      return lot;

   double scaled = lot * (cap / margin);
   scaled = NormalizeLot(scaled);
   Log("Lotto ridotto per limite margine: "+DoubleToString(lot,2)+" -> "+DoubleToString(scaled,2));
   return scaled;
  }

//======================== SEGNALI ====================================
//--- crossover letto da due barre CHIUSE: nessuno stato globale
int GetCCISignal()
  {
   if(g_cciHandle == INVALID_HANDLE)
      return 0;

   double cci[];
   ArraySetAsSeries(cci, true);
   if(CopyBuffer(g_cciHandle, 0, 1, 2, cci) < 2)
      return 0;
   if(!MathIsValidNumber(cci[0]) || !MathIsValidNumber(cci[1]))
      return 0;

   double last = cci[0];   // ultima barra chiusa
   double prev = cci[1];   // barra precedente

   if(prev <= CCI_BuyThreshold  && last > CCI_BuyThreshold)  return  1;
   if(prev >= CCI_SellThreshold && last < CCI_SellThreshold) return -1;
   return 0;
  }

//--- 1 = rialzista, -1 = ribassista, 0 = neutro/dato assente
int GetAMATrend()
  {
   if(g_amaHandle == INVALID_HANDLE)
      return 0;

   double ama[], cl[];
   ArraySetAsSeries(ama, true);
   ArraySetAsSeries(cl,  true);

   // barre CHIUSE su entrambe le serie: nessun mix con la barra in formazione
   if(CopyBuffer(g_amaHandle, 0, 1, 2, ama) < 2) return 0;
   if(CopyClose(_Symbol, g_amaTF, 1, 1, cl)  < 1) return 0;
   if(!MathIsValidNumber(ama[0]) || !MathIsValidNumber(ama[1])) return 0;

   int dir = 0;
   if(cl[0] > ama[0])      dir =  1;
   else if(cl[0] < ama[0]) dir = -1;

   if(AMA_UseSlope && dir != 0)
     {
      if(dir > 0 && ama[0] <= ama[1]) dir = 0;
      if(dir < 0 && ama[0] >= ama[1]) dir = 0;
     }
   return dir;
  }

//======================== SL / TP ====================================
//--- calcola SL e TP ancorati al prezzo di ingresso reale (Ask per buy, Bid per sell)
bool ComputeSLTP(int dir, double entry, double &sl, double &tp)
  {
   sl = 0.0;
   tp = 0.0;

   //--- STOP LOSS -----------------------------------------------------
   switch(SL_Mode)
     {
      case SL_MODE_POINTS:
        {
         if(SL_Points <= 0) { Log("SL_Points non valido."); return false; }
         sl = (dir > 0) ? entry - SL_Points*_Point : entry + SL_Points*_Point;
         break;
        }
      case SL_MODE_ATR:
        {
         double atr = GetATR(SL_ATR_Period);
         if(atr <= 0.0) { Log("ATR SL non disponibile: ingresso annullato."); return false; }
         sl = (dir > 0) ? entry - SL_ATR_Mult*atr : entry + SL_ATR_Mult*atr;
         break;
        }
      case SL_MODE_PREVCANDLE:
        {
         int bars = MathMax(1, PrevCandlesBack);
         double buf = PrevCandle_BufferPoints * _Point;
         if(dir > 0)
           {
            double lows[];
            ArraySetAsSeries(lows, true);
            if(CopyLow(_Symbol, g_tf, 1, bars, lows) < bars)
              { Log("CopyLow insufficiente: ingresso annullato."); return false; }
            double lo = lows[0];
            for(int i=1; i<bars; i++) if(lows[i] < lo) lo = lows[i];
            sl = lo - buf;
           }
         else
           {
            double highs[];
            ArraySetAsSeries(highs, true);
            if(CopyHigh(_Symbol, g_tf, 1, bars, highs) < bars)
              { Log("CopyHigh insufficiente: ingresso annullato."); return false; }
            double hi = highs[0];
            for(int i=1; i<bars; i++) if(highs[i] > hi) hi = highs[i];
            sl = hi + buf;
           }
         break;
        }
     }

   //--- lo SL deve stare dalla parte giusta del prezzo
   if((dir > 0 && sl >= entry) || (dir < 0 && sl <= entry))
     {
      Log("SL calcolato dal lato sbagliato del prezzo: ingresso annullato.");
      return false;
     }

   double riskDist = MathAbs(entry - sl);

   //--- TAKE PROFIT ---------------------------------------------------
   switch(TP_Mode)
     {
      case TP_MODE_NONE:
         tp = 0.0;
         break;
      case TP_MODE_POINTS:
        {
         if(TP_Points <= 0) { tp = 0.0; break; }
         tp = (dir > 0) ? entry + TP_Points*_Point : entry - TP_Points*_Point;
         break;
        }
      case TP_MODE_ATR:
        {
         double atr = GetATR(TP_ATR_Period);
         if(atr <= 0.0) { Log("ATR TP non disponibile: TP non impostato."); tp = 0.0; break; }
         tp = (dir > 0) ? entry + TP_ATR_Mult*atr : entry - TP_ATR_Mult*atr;
         break;
        }
      case TP_MODE_RR:
        {
         if(TP_RR_Ratio <= 0.0) { tp = 0.0; break; }
         tp = (dir > 0) ? entry + TP_RR_Ratio*riskDist : entry - TP_RR_Ratio*riskDist;
         break;
        }
     }

   //--- validazione distanza minima dal mercato ------------------------
   double minDist = MinStopDistance();
   double refSL   = (dir > 0) ? BidPrice() : AskPrice();   // prezzo con cui il server valuta lo stop

   if(dir > 0)
     {
      if(refSL - sl < minDist)
        {
         Log("SL troppo vicino al mercato (min "+DoubleToString(minDist/_Point,0)+" pt): ingresso annullato.");
         return false;
        }
      if(tp > 0.0 && tp - refSL < minDist)
        {
         Log("TP troppo vicino al mercato: TP rimosso.");
         tp = 0.0;
        }
     }
   else
     {
      if(sl - refSL < minDist)
        {
         Log("SL troppo vicino al mercato (min "+DoubleToString(minDist/_Point,0)+" pt): ingresso annullato.");
         return false;
        }
      if(tp > 0.0 && refSL - tp < minDist)
        {
         Log("TP troppo vicino al mercato: TP rimosso.");
         tp = 0.0;
        }
     }

   sl = NormPrice(sl);
   tp = (tp > 0.0) ? NormPrice(tp) : 0.0;
   return true;
  }

//======================== APERTURA ORDINE ============================
bool OpenMarketOrder(int dir)
  {
   double entry = (dir > 0) ? AskPrice() : BidPrice();
   if(entry <= 0.0) return false;

   double sl = 0.0, tp = 0.0;
   if(!ComputeSLTP(dir, entry, sl, tp))
      return false;

   double lot = CalcLot(MathAbs(entry - sl));
   lot = ApplyMarginCap(dir, lot);
   if(lot <= 0.0)
     {
      Log("Lotto calcolato nullo: ingresso annullato.");
      return false;
     }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool res = (dir > 0)
              ? trade.Buy (lot, _Symbol, 0.0, sl, tp, "CCI_EA_BUY")
              : trade.Sell(lot, _Symbol, 0.0, sl, tp, "CCI_EA_SELL");

   if(res)
     {
      g_dailyTrades++;   // aggiornamento immediato; riconciliato da storico a nuova barra
      Log((dir>0 ? "BUY" : "SELL")+" aperto | lot="+DoubleToString(lot,2)
          +" SL="+DoubleToString(sl,_Digits)
          +" TP="+DoubleToString(tp,_Digits)
          +" spread="+DoubleToString(CurrentSpreadPoints(),0)+"pt");
     }
   else
     {
      Log("Apertura fallita retcode="+(string)trade.ResultRetcode()+" ("+trade.ResultRetcodeDescription()+")");
     }
   return res;
  }

//======================== GESTIONE POSIZIONI =========================
//--- candidato SL dal modulo di trailing attivo; 0.0 = nessuna proposta
double TrailingCandidate(long type, double openPrice, double curPrice, double atrTrail)
  {
   if(TrailMode == TRAIL_NONE)
      return 0.0;

   bool isBuy = (type == POSITION_TYPE_BUY);
   double moveP = (isBuy ? curPrice - openPrice : openPrice - curPrice) / _Point;
   if(moveP <= 0.0)
      return 0.0;

   switch(TrailMode)
     {
      case TRAIL_POINTS:
        {
         if(Trailing_Points_Start <= 0 || moveP < Trailing_Points_Start) return 0.0;
         double d = Trailing_Points_Step * _Point;
         return isBuy ? curPrice - d : curPrice + d;
        }
      case TRAIL_ATR:
        {
         if(atrTrail <= 0.0) return 0.0;
         double startP = (Trailing_ATR_StartMult * atrTrail) / _Point;
         if(moveP < startP) return 0.0;            // attivazione: manca nella v2
         double d = Trailing_ATR_Mult * atrTrail;
         return isBuy ? curPrice - d : curPrice + d;
        }
      case TRAIL_SMART:
        {
         if(moveP < Smart_Start_Points) return 0.0;
         double step = Smart_Step1;
         if(moveP >= Smart_Start_Points + Smart_Rpoints)     step = Smart_Step2;
         if(moveP >= Smart_Start_Points + 2*Smart_Rpoints)   step = Smart_Step3;
         if(step <= 0.0) return 0.0;
         double d = step * _Point;
         return isBuy ? curPrice - d : curPrice + d;
        }
     }
   return 0.0;
  }

//--- candidato SL dal break-even; 0.0 = nessuna proposta
double BreakEvenCandidate(long type, double openPrice, double curPrice, double atrBE)
  {
   if(BE_Mode == BE_MODE_OFF)
      return 0.0;

   bool isBuy = (type == POSITION_TYPE_BUY);
   double moveP = (isBuy ? curPrice - openPrice : openPrice - curPrice) / _Point;

   double triggerP = 0.0, offset = 0.0;
   if(BE_Mode == BE_MODE_POINTS)
     {
      triggerP = (double)BE_Trigger_Points;
      offset   = BE_Offset_Points * _Point;
     }
   else
     {
      if(atrBE <= 0.0) return 0.0;
      triggerP = (atrBE * BE_ATR_TriggerMult) / _Point;
      offset   = atrBE * BE_ATR_OffsetMult;
     }

   if(triggerP <= 0.0 || moveP < triggerP)
      return 0.0;

   return isBuy ? openPrice + offset : openPrice - offset;
  }

//--- eseguita a OGNI tick, prima di qualsiasi gate: un solo modify per posizione
void ManageOpenPositions()
  {
   if(TrailMode == TRAIL_NONE && BE_Mode == BE_MODE_OFF)
      return;

   double atrTrail = (TrailMode == TRAIL_ATR)  ? GetATR(Trailing_ATR_Period) : 0.0;
   double atrBE    = (BE_Mode   == BE_MODE_ATR)? GetATR(BE_ATR_Period)       : 0.0;

   double minDist  = MinStopDistance();
   double minStep  = Trailing_MinStepPoints * _Point;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!IsOurPosition()) continue;

      long   type       = PositionGetInteger(POSITION_TYPE);
      bool   isBuy      = (type == POSITION_TYPE_BUY);
      double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL      = PositionGetDouble(POSITION_SL);
      double curTP      = PositionGetDouble(POSITION_TP);
      double curPrice   = isBuy ? BidPrice() : AskPrice();

      //--- raccoglie i candidati e tiene il piu' protettivo
      double cTrail = TrailingCandidate(type, openPrice, curPrice, atrTrail);
      double cBE    = BreakEvenCandidate(type, openPrice, curPrice, atrBE);

      double newSL = 0.0;
      if(cTrail > 0.0) newSL = cTrail;
      if(cBE > 0.0)
         newSL = (newSL <= 0.0) ? cBE
                                : (isBuy ? MathMax(newSL, cBE) : MathMin(newSL, cBE));

      if(newSL <= 0.0) continue;

      //--- non superare il prezzo corrente e rispettare lo stops level
      if(isBuy  && curPrice - newSL < minDist) continue;
      if(!isBuy && newSL - curPrice < minDist) continue;

      //--- solo miglioramenti, e solo se il salto supera lo step minimo
      bool improved = isBuy ? (curSL <= 0.0 || newSL > curSL + minStep)
                            : (curSL <= 0.0 || newSL < curSL - minStep);
      if(!improved) continue;

      newSL = NormPrice(newSL);
      if(!trade.PositionModify(ticket, newSL, curTP))
         Log("PositionModify fallita ticket="+(string)ticket
             +" SL="+DoubleToString(newSL,_Digits)
             +" retcode="+(string)trade.ResultRetcode());
     }
  }

//======================== INIT / DEINIT ==============================
int OnInit()
  {
   g_tf    = ResolveTF(CCI_Timeframe);
   g_amaTF = ResolveTF(AMA_Timeframe);

   //--- validazione input
   if(CCI_Period < 1)                       { Print("CCI_Period non valido.");        return INIT_PARAMETERS_INCORRECT; }
   if(CCI_BuyThreshold <= CCI_SellThreshold){ Print("Soglie CCI incoerenti.");        return INIT_PARAMETERS_INCORRECT; }
   if(LotMode == LOT_FIXED && LotFixed <= 0){ Print("LotFixed non valido.");          return INIT_PARAMETERS_INCORRECT; }
   if(LotMode == LOT_RISK_PERCENT && RiskPercent <= 0.0)
                                            { Print("RiskPercent non valido.");       return INIT_PARAMETERS_INCORRECT; }
   if(MaxPositionsPerSymbol < 1)            { Print("MaxPositionsPerSymbol < 1.");    return INIT_PARAMETERS_INCORRECT; }

   //--- handle indicatori: creati UNA volta
   g_cciHandle = iCCI(_Symbol, g_tf, CCI_Period, CCI_Price);
   if(g_cciHandle == INVALID_HANDLE)
     { Print("Errore creazione handle CCI."); return INIT_FAILED; }

   if(UseAMAFilter)
     {
      g_amaHandle = iAMA(_Symbol, g_amaTF, AMA_Period, AMA_FastEMA, AMA_SlowEMA, AMA_Shift, AMA_Price);
      if(g_amaHandle == INVALID_HANDLE)
        { Print("Errore creazione handle AMA."); return INIT_FAILED; }
     }

   //--- pre-registra gli handle ATR effettivamente usati
   ArrayInitialize(g_atrPeriods, 0);
   ArrayInitialize(g_atrHandles, INVALID_HANDLE);
   g_atrCount = 0;
   if(SL_Mode    == SL_MODE_ATR)  RegisterATR(SL_ATR_Period);
   if(TP_Mode    == TP_MODE_ATR)  RegisterATR(TP_ATR_Period);
   if(TrailMode  == TRAIL_ATR)    RegisterATR(Trailing_ATR_Period);
   if(BE_Mode    == BE_MODE_ATR)  RegisterATR(BE_ATR_Period);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_lastBarTime    = 0;
   g_lastSignalBar  = 0;
   g_statsReady     = false;
   g_initOK         = true;

   Log("Init OK | TF="+EnumToString(g_tf)
       +" stopsLevel="+(string)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)+"pt"
       +" volStep="+DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),2));
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_cciHandle != INVALID_HANDLE) { IndicatorRelease(g_cciHandle); g_cciHandle = INVALID_HANDLE; }
   if(g_amaHandle != INVALID_HANDLE) { IndicatorRelease(g_amaHandle); g_amaHandle = INVALID_HANDLE; }
   for(int i=0; i<g_atrCount; i++)
      if(g_atrHandles[i] != INVALID_HANDLE)
         IndicatorRelease(g_atrHandles[i]);
   g_atrCount = 0;
  }

//======================== NUOVA BARRA ================================
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, g_tf, 0);
   if(t == 0) return false;
   if(t == g_lastBarTime) return false;
   g_lastBarTime = t;
   return true;
  }

//======================== ONTICK =====================================
void OnTick()
  {
   if(!EnableEA || !g_initOK)
      return;

   //--- 1) GESTIONE POSIZIONI APERTE: ogni tick, prima di ogni filtro.
   //---    Trailing e break-even non devono mai dipendere da spread,
   //---    orario o limiti giornalieri.
   ManageOpenPositions();

   //--- 2) statistiche giornaliere: una volta per barra (o a cambio giorno)
   bool newBar = IsNewBar();
   if(!g_statsReady || newBar || g_statsDay != TodayStart())
      UpdateDailyStats();

   //--- 3) stop perdite giornaliero (valutato ogni tick se include il flottante)
   if(EnableDailyLossCut && DailyLossCutAmount > 0.0)
     {
      double pnl = DailyPnL();
      if(pnl <= -DailyLossCutAmount)
        {
         static datetime lastCutLog = 0;
         if(TimeCurrent() - lastCutLog > 300)
           {
            Log("Stop perdite giornaliero attivo (P/L="+DoubleToString(pnl,2)+").");
            lastCutLog = TimeCurrent();
           }
         if(DailyLossCut_CloseOpen && CountOurPositions() > 0)
            CloseAllOurPositions("daily loss cut");
         return;
        }
     }

   //--- 4) da qui in poi si lavora solo su barra chiusa (se richiesto)
   if(OnlyOnNewBar && !newBar)
      return;

   //--- 5) gate operativi
   if(EnableMaxDailyTrades && g_dailyTrades >= MaxDailyTrades)
     { Log("Limite trade giornaliero raggiunto ("+(string)g_dailyTrades+")."); return; }

   if(!SpreadOK())
     { Log("Spread troppo alto ("+DoubleToString(CurrentSpreadPoints(),0)+" pt)."); return; }

   if(!TimeFiltersPassed(TimeCurrent()))
      return;

   //--- 6) segnale: al massimo un'azione per barra, anche con OnlyOnNewBar=false
   //---    (il crossover calcolato su barre 1/2 resta vero per tutta la barra 0)
   datetime curBar = iTime(_Symbol, g_tf, 0);
   if(curBar == g_lastSignalBar)
      return;

   int signal = GetCCISignal();
   if(signal == 0)
      return;

   //--- 7) filtro AMA
   if(UseAMAFilter)
     {
      int amaTrend = GetAMATrend();
      if(amaTrend == 0)
        { Log("AMA neutrale o dato assente: segnale scartato."); return; }
      if(signal > 0 && amaTrend < 0)
        { Log("BUY scartato: AMA ribassista."); return; }
      if(signal < 0 && amaTrend > 0)
        { Log("SELL scartato: AMA rialzista."); return; }
     }

   g_lastSignalBar = curBar;   // segnale valido: consumato per questa barra

   //--- 8) chiusura opposti
   if(UseCloseOnOppositeSignal)
      CloseOppositePositions(signal);

   //--- 9) limite posizioni: conteggio TOTALE sul simbolo, non per direzione
   if(CountOurPositions(0) >= MaxPositionsPerSymbol)
     { Log("Limite posizioni sul simbolo raggiunto."); return; }

   //--- 10) ingresso
   OpenMarketOrder(signal);
  }
//+------------------------------------------------------------------+
