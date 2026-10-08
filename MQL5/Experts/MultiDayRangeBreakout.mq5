//+------------------------------------------------------------------+
//|                                       MultiDayRangeBreakout.mq5 |
//|  v3.00: riscrittura di v2.00 (stessa idea, meccanica corretta).  |
//|                                                                  |
//|  Idea: nella finestra di entrata si entra in breakout di un      |
//|  range. Modalita' di entrata (interruttori, anche piu' di una;   |
//|  vince la prima che scatta e ne parte una sola per volta):       |
//|   EntryStop         coppia di ordini stop: BuyStop sopra il      |
//|                     massimo, SellStop sotto il minimo (+ offset).|
//|                     Quando uno scatta l'altro viene cancellato   |
//|                     (OCO); gli ordini non eseguiti scadono a     |
//|                     fine finestra.                               |
//|   EntryCandleClose  a mercato quando una candela CHIUSA di       |
//|                     Timeframe chiude oltre massimo+offset (long) |
//|                     o sotto minimo-offset (short).               |
//|   EntryRetest       a mercato dopo una rottura (il prezzo supera |
//|                     il livello+offset) quando il prezzo TORNA al |
//|                     bordo del range (retest), nella direzione    |
//|                     della rottura.                               |
//|  Prima di aprire valgono sempre i filtri di spread e, se attivo, |
//|  quello di larghezza del range (Min/MaxRangePoints).             |
//|                                                                  |
//|  Tutti gli orari sono ORA SERVER del broker (quella di           |
//|  TimeCurrent), non GMT e non ora locale.                         |
//|                                                                  |
//|  Range (RangeMode):                                              |
//|   RANGE_BARS    ultime RangeBarsLookback barre completate di     |
//|                 Timeframe che finiscono alla fine del giorno di  |
//|                 riferimento. RangeDaysBack=1: fino alla          |
//|                 mezzanotte di oggi (cioe' ieri); 0: le ultime    |
//|                 barre chiuse al momento del piazzamento.         |
//|   RANGE_TIME    finestra oraria RangeHourStart:Min - RangeHourEnd|
//|                 :Min (se la fine e' prima dell'inizio passa la   |
//|                 mezzanotte) nel giorno di riferimento. 0 = oggi  |
//|                 (range asiatico), 1 = ultimo giorno di mercato.  |
//|   RANGE_PREV_D1 massimo e minimo di RangeDaySpan barre D1        |
//|                 complete, a partire dal giorno di riferimento    |
//|                 (RangeDaysBack >= 1) e andando indietro.         |
//|  "Giorno di riferimento" = N-esimo giorno di mercato prima di    |
//|  oggi (contato con le barre D1): il lunedi' 1 = venerdi'.        |
//|                                                                  |
//|  Le distanze (SL, TP, BE, trailing, offset, range) sono in PUNTI |
//|  del simbolo: su un cambio a 5 cifre 10 punti = 1 pip.           |
//|                                                                  |
//|  SlotScan = true: l'EA NON apre ordini ma analizza in modo       |
//|  virtuale 12 fasce orarie (+ range a barre e D1 precedenti) per  |
//|  ogni modalita' accesa e scrive la classifica (vedi sotto).      |
//+------------------------------------------------------------------+
#property copyright "MultiDayRangeBreakout"
#property version   "3.00"
#property description "Breakout di un range: ordini stop OCO, chiusura di candela o retest. Analisi virtuale delle fasce orarie."

#include <Trade\Trade.mqh>

enum ENUM_RANGE_MODE
  {
   RANGE_BARS    = 0,   // ultime N barre del timeframe
   RANGE_TIME    = 1,   // finestra oraria (ora server)
   RANGE_PREV_D1 = 2    // massimo/minimo di giorni D1 completi
  };

enum ENUM_SLOT_RANK
  {
   SLOT_RANK_TSTAT       = 0,   // t-stat dell'E[R] (tiene conto di quanti trade)
   SLOT_RANK_EXPECTANCY  = 1,   // E[R] medio per trade
   SLOT_RANK_PF          = 2,   // profit factor
   SLOT_RANK_TOTAL       = 3    // R totale
  };

input group "=== POSIZIONE ==="
input double LotSize = 0.01;

input group "=== RANGE ==="
input ENUM_RANGE_MODE RangeMode = RANGE_BARS;
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;  // TIME FRAME OSSERVATO: barre del range (RANGE_BARS, RANGE_TIME) e candele di EntryCandleClose
input int RangeDaysBack = 1;                       // giorno di riferimento (vedi intestazione)
input int RangeBarsLookback = 25;                  // RANGE_BARS: numero di barre
input int RangeHourStart = 16;                     // RANGE_TIME: inizio
input int RangeMinuteStart = 0;
input int RangeHourEnd = 0;                        // RANGE_TIME: fine (0:00 = mezzanotte)
input int RangeMinuteEnd = 0;
input int RangeDaySpan = 1;                        // RANGE_PREV_D1: quanti giorni D1
input bool RequireRangeConfirmation = true;       // scarta i range fuori da Min/Max
input double MinRangePoints = 50;
input double MaxRangePoints = 500;

input group "=== ANALISI VIRTUALE: classifica di range x modalita' di entrata, NESSUN ordine reale ==="
input bool SlotScan = false;                       // true: analizza e scrivi la classifica (non apre ordini; RangeMode e' ignorato: le sorgenti sono le fasce e i due interruttori sotto)
input int SlotFirstHour = 0;                       // fascia 1: ora di inizio (ora server)
input int SlotLenHours = 2;                        // durata di ogni fascia in ore (le fasce sono contigue: fascia 2 inizia dove finisce la 1)
input bool Slot1 = true;                           // fascia 1 attiva (di default 00-02)
input bool Slot2 = true;                           // fascia 2 attiva (02-04)
input bool Slot3 = true;                           // fascia 3 attiva (04-06)
input bool Slot4 = true;                           // fascia 4 attiva (06-08)
input bool Slot5 = true;                           // fascia 5 attiva (08-10)
input bool Slot6 = true;                           // fascia 6 attiva (10-12)
input bool Slot7 = true;                           // fascia 7 attiva (12-14)
input bool Slot8 = true;                           // fascia 8 attiva (14-16)
input bool Slot9 = true;                           // fascia 9 attiva (16-18)
input bool Slot10 = true;                          // fascia 10 attiva (18-20)
input bool Slot11 = true;                          // fascia 11 attiva (20-22)
input bool Slot12 = true;                          // fascia 12 attiva (22-24)
input bool ScanRangeBars = false;                  // analizza anche il range a barre (RangeBarsLookback barre di Timeframe)
input bool ScanRangePrevD1 = false;                // analizza anche il range dei D1 precedenti (RangeDaySpan giorni; richiede RangeDaysBack >= 1)
input int SlotMinTrades = 30;                      // trade minimi per entrare in classifica
input ENUM_SLOT_RANK SlotRankBy = SLOT_RANK_TSTAT; // criterio della classifica
input datetime SlotSplitDate = 0;                  // se > 0: i risultati sono separati prima/dopo questa data (per controllare fuori campione)
input double SlotCommissionPoints = 0.0;           // commissione round-turn in punti, sottratta a ogni trade virtuale
input bool SlotWriteFiles = true;                  // scrivi la classifica e i trade virtuali in Terminal\Common\Files (solo nei test singoli)

input group "=== FINESTRA DI ENTRATA (ora server) ==="
input int TradeHourStart = 10;
input int TradeMinuteStart = 0;
input int TradeHourEnd = 11;
input int TradeMinuteEnd = 0;
input int ExpireExtraMinutes = 0;                  // minuti di vita degli ordini oltre la fine finestra
input int MaxTradesPerDay = 1;                     // posizioni aperte al massimo in un giorno
input int PendingOrderOffsetPoints = 20;           // distanza degli ordini dal range
input bool ChaseIfBroken = false;                  // solo EntryStop. false: se il prezzo e' gia' oltre il livello aspetta che rientri nel range e poi piazza la coppia; true: piazza subito lo stop del lato rotto vicino al mercato (come v2)

input group "=== MODALITA' DI ENTRATA (interruttori) ==="
input bool EntryStop = true;                       // A) coppia di ordini stop sul massimo/minimo +/- offset (OCO)
input bool EntryCandleClose = false;               // B) a mercato quando una candela chiusa di Timeframe chiude oltre massimo+offset / sotto minimo-offset
input bool EntryRetest = false;                    // C) retest: dopo che il prezzo supera il livello+offset, entra a mercato quando TORNA al bordo del range
input int RetestTolerancePoints = 0;               // C) il ritorno conta quando il prezzo e' entro questi punti dal bordo del range (0 = lo tocca)

input group "=== STOP LOSS E TAKE PROFIT ==="
input double StopLossPoints = 100;
input double TakeProfitPoints = 200;
input bool UseTakeProfit = true;

input group "=== FILTRI DI COSTO ==="
input double MaxSpreadPoints = 0;                  // 0 = spento
input double MaxSpreadPctOfSL = 15;                // spread massimo in % dello stop loss; 0 = spento

input group "=== BREAK EVEN E TRAILING ==="
input bool UsaBreakEven = true;
input int BreakEvenAttivazione = 100;
input int BreakEvenOffset = 10;
input bool UsaTrailingStop = true;
input int TrailingStartProfit = 150;
input int TrailingStep = 20;
input int TrailingOffset = 30;

input group "=== SISTEMA ==="
input int Slippage = 10;
input int MagicNumber = 123456;
input string OrderComment = "MDRB3";
input bool ShowPanel = true;
input bool ShowRangeLines = true;

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
   if(RangeMode == RANGE_PREV_D1)
      rt = RangeByD1(hi, lo, info);
   else
      if(RangeMode == RANGE_BARS)
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
// Vale solo se ora siamo nella finestra di entrata (piu' ExpireExtraMinutes) e la candela si e' chiusa dopo l'inizio della finestra corrente.
// Da chiamare solo al primo tick di una nuova barra.
int CandleSignal(datetime now, double hi, double lo)
  {
   if(!OrdersMayLive(now))
      return 0;
   datetime t1 = iTime(_Symbol, Timeframe, 1);
   if(t1 == 0)
      return 0;
   datetime tc = t1 + (datetime)PeriodSeconds(Timeframe);
   datetime winStart = now - (datetime)(WinOffset(now) * 60 + (int)(now % 60));
   if(tc <= winStart)
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

// C) retest. Armamento: il prezzo supera il livello (ask >= massimo+offset, oppure bid <= minimo-offset). Ingresso: dopo l'armamento (mai nello stesso
// tick) il prezzo torna al bordo del range: bid <= massimo + tolleranza per il long, ask >= minimo - tolleranza per lo short. Ritorna +1 / -1 / 0.
int RetestSignal(bool &armL, bool &armS, double hi, double lo, double bid, double ask)
  {
   double tol = RetestTolerancePoints * _Point;
   if(armL && bid <= hi + tol + 1e-9)
      return 1;
   if(armS && ask >= lo - tol - 1e-9)
      return -1;
   double up = NormPrice(hi + PendingOrderOffsetPoints * _Point);
   double dn = NormPrice(lo - PendingOrderOffsetPoints * _Point);
   if(ask >= up - 1e-9)
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
   if(!OrdersMayLive(now))
     {
      g_armL = false;
      g_armS = false;
      return;
     }
   if(g_tradesToday >= MaxTradesPerDay)
      return;
   if(g_nPos > 0)
     {
      g_armL = false;
      g_armS = false;
      return;
     }
   if(now < g_nextTryM)
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
   int dir = 0;
   string tag = "";
   if(EntryRetest)
     {
      dir = RetestSignal(g_armL, g_armS, g_upper, g_lower, bid, ask);
      tag = "retest";
     }
   if(dir == 0 && EntryCandleClose && newBar)
     {
      dir = CandleSignal(now, g_upper, g_lower);
      tag = "chiusura";
     }
   if(dir == 0)
      return;
   double spr = (ask - bid) / _Point;
   double lim = SpreadLimitPoints();
   if(lim > 0.0 && spr > lim)
     {
      if(!g_logSpread)
        {
         Print("Spread ", DoubleToString(spr, 1), " punti sopra il limite ", DoubleToString(lim, 1), ": segnale ", tag, " saltato");
         g_logSpread = true;
        }
      return;
     }
   if(OpenMarket(dir > 0, tag))
     {
      g_armL = false;
      g_armS = false;
      g_failToday = 0;
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
//|     - le fasce orarie Slot1..Slot12 (massimo/minimo della fascia   |
//|       nel giorno di riferimento RangeDaysBack)                    |
//|     - il range a barre (ScanRangeBars: RangeBarsLookback barre di |
//|       Timeframe)                                                  |
//|     - il range dei D1 precedenti (ScanRangePrevD1: RangeDaySpan   |
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
      return SlotOn(src);
   if(src == NSLOT)
      return ScanRangeBars;
   return ScanRangePrevD1;
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

void ScanNewDay()
  {
   for(int c = 0; c < NCON; c++)
     {
      g_sl[c].rangeDone = false;
      g_sl[c].rangeOK = false;
      g_sl[c].hi = 0.0;
      g_sl[c].lo = 0.0;
      g_sl[c].pairs = (g_sl[c].state == 1 ? 1 : 0);   // una coppia ancora viva (finestra a cavallo di mezzanotte) conta come piazzata
      g_sl[c].trades = 0;
      g_sl[c].nextTry = 0;
      g_sl[c].armL = false;
      g_sl[c].armS = false;
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
   if(!OrdersMayLive(now))
     {
      g_sl[c].armL = false;
      g_sl[c].armS = false;
      return;
     }
   if(g_sl[c].trades >= MaxTradesPerDay)
      return;
   if(now < g_sl[c].nextTry)
      return;
   if(!ScanEnsureRange(c, now))
      return;
   if(ask <= 0.0 || bid <= 0.0 || ask < bid)
      return;
   int dir = 0;
   if(g_sl[c].mode == 2)
      dir = RetestSignal(g_sl[c].armL, g_sl[c].armS, g_sl[c].hi, g_sl[c].lo, bid, ask);
   else
      if(newBar)
         dir = CandleSignal(now, g_sl[c].hi, g_sl[c].lo);
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
      return;
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

// valore per il tester (OnTester): punteggio del concorrente migliore tra quelli con abbastanza trade, 0 se nessuno
double ScanBestScore()
  {
   int order[];
   ArrayResize(order, NCON);
   int cnt = ScanOrder(order);
   if(cnt < 1 || SlotTrades(order[0]) < SlotMinTrades)
      return 0.0;
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
         ". Con ", cnt, " concorrenti provati il migliore e' in parte fortuna: confermalo su un altro periodo (SlotSplitDate) prima di fidarti.");
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
   g_logOutside = false;
   g_logSpread = false;
   g_logWait = false;
   g_status = "";
   g_nPos = -1;   // forza la rilettura dei contatori dalla storia
   g_nOrd = -1;
   if(SlotScan)
      ScanNewDay();
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
   if(RetestTolerancePoints < 0)
      return "RetestTolerancePoints non puo' essere negativo";
   if(SlotScan)
     {
      if(RangeDaysBack < 0)
         return "RangeDaysBack non valido";
      if(SlotFirstHour < 0 || SlotFirstHour > 23)
         return "SlotFirstHour deve essere tra 0 e 23";
      if(SlotLenHours < 1 || SlotLenHours > 12)
         return "SlotLenHours deve essere tra 1 e 12";
      if(!(Slot1 || Slot2 || Slot3 || Slot4 || Slot5 || Slot6 || Slot7 || Slot8 || Slot9 || Slot10 || Slot11 || Slot12 || ScanRangeBars || ScanRangePrevD1))
         return "analisi: accendi almeno una fascia o un range (ScanRangeBars, ScanRangePrevD1)";
      if(ScanRangeBars && RangeBarsLookback < 1)
         return "RangeBarsLookback deve essere >= 1";
      if(ScanRangePrevD1 && (RangeDaySpan < 1 || RangeDaysBack < 1))
         return "ScanRangePrevD1 richiede RangeDaySpan >= 1 e RangeDaysBack >= 1";
      if(SlotMinTrades < 1)
         return "SlotMinTrades deve essere >= 1";
     }
   if(RangeDaysBack < 0 || (!SlotScan && RangeMode == RANGE_PREV_D1 && RangeDaysBack < 1))
      return "RangeDaysBack non valido per il modo scelto";
   if(!SlotScan && RangeMode == RANGE_BARS && RangeBarsLookback < 1)
      return "RangeBarsLookback deve essere >= 1";
   if(!SlotScan && RangeMode == RANGE_PREV_D1 && RangeDaySpan < 1)
      return "RangeDaySpan deve essere >= 1";
   if(!SlotScan && RangeMode == RANGE_TIME && (RangeHourStart < 0 || RangeHourStart > 23 || RangeHourEnd < 0 || RangeHourEnd > 24 || RangeMinuteStart < 0 || RangeMinuteStart > 59 || RangeMinuteEnd < 0 || RangeMinuteEnd > 59))
      return "orario del range non valido";
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
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(StopLossPoints * _Point < stopLvl)
      Print("Attenzione: StopLossPoints e' sotto il livello minimo dei stop del broker (", DoubleToString(stopLvl / _Point, 0), " punti)");
   if(SlotScan)
     {
      ScanInit();
      Print("MultiDayRangeBreakout 3.00 su ", _Symbol, ": ANALISI VIRTUALE, ", ScanActive(), " concorrenti (range x modalita' di entrata: ", (EntryStop ? "stop " : ""), (EntryCandleClose ? "chiusura " : ""), (EntryRetest ? "retest" : ""),
            "); fasce da ", SlotLenHours, " ore dalle ", StringFormat("%02d:00", SlotFirstHour), " (ora server), giorno di riferimento del range RangeDaysBack ", RangeDaysBack,
            ". NESSUN ordine reale verra' aperto: la classifica si scrive a fine test.");
      return INIT_SUCCEEDED;
     }
   Print("MultiDayRangeBreakout 3.00 su ", _Symbol, ": entrata ", (EntryStop ? "stop " : ""), (EntryCandleClose ? "chiusura " : ""), (EntryRetest ? "retest " : ""), "| range ", EnumToString(RangeMode), ", finestra ", StringFormat("%02d:%02d-%02d:%02d", TradeHourStart, TradeMinuteStart, TradeHourEnd, TradeMinuteEnd),
         " ora server, SL ", DoubleToString(StopLossPoints, 0), " TP ", (UseTakeProfit ? DoubleToString(TakeProfitPoints, 0) : "nessuno"), " punti");
   return INIT_SUCCEEDED;
  }

// valore del tester: nell'analisi delle fasce e' il punteggio della fascia migliore (per ottimizzare gli altri parametri su di essa); altrimenti 0
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
