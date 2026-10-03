//+------------------------------------------------------------------+
//|                                       MultiDayRangeBreakout.mq5 |
//|  v3.00: riscrittura di v2.00 (stessa idea, meccanica corretta).  |
//|                                                                  |
//|  Idea: nella finestra di entrata si piazza una coppia di ordini  |
//|  stop sul range scelto: BuyStop sopra il massimo, SellStop sotto |
//|  il minimo. Quando uno scatta l'altro viene cancellato (OCO).    |
//|  Gli ordini non eseguiti scadono a fine finestra.                |
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
//+------------------------------------------------------------------+
#property copyright "MultiDayRangeBreakout"
#property version   "3.00"
#property description "BuyStop sopra e SellStop sotto un range, OCO, scadenza a fine finestra."

#include <Trade\Trade.mqh>

enum ENUM_RANGE_MODE
  {
   RANGE_BARS    = 0,   // ultime N barre del timeframe
   RANGE_TIME    = 1,   // finestra oraria (ora server)
   RANGE_PREV_D1 = 2    // massimo/minimo di giorni D1 completi
  };

input group "=== POSIZIONE ==="
input double LotSize = 0.01;

input group "=== RANGE ==="
input ENUM_RANGE_MODE RangeMode = RANGE_BARS;
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;  // timeframe delle barre (RANGE_BARS e RANGE_TIME)
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

input group "=== FINESTRA DI ENTRATA (ora server) ==="
input int TradeHourStart = 10;
input int TradeMinuteStart = 0;
input int TradeHourEnd = 11;
input int TradeMinuteEnd = 0;
input int ExpireExtraMinutes = 0;                  // minuti di vita degli ordini oltre la fine finestra
input int MaxTradesPerDay = 1;                     // posizioni aperte al massimo in un giorno
input int PendingOrderOffsetPoints = 20;           // distanza degli ordini dal range
input bool ChaseIfBroken = false;                  // true: se il prezzo e' gia' oltre il livello, ordine stop vicino al mercato (come v2)

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
int ComputeRange(datetime now, double &hi, double &lo, string &info)
  {
   hi = -DBL_MAX;
   lo = DBL_MAX;
   info = "";
   if(RangeMode == RANGE_PREV_D1)
     {
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
     }
   else
      if(RangeMode == RANGE_BARS)
        {
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
        }
      else
        {
         datetime dayStart = iTime(_Symbol, PERIOD_D1, RangeDaysBack);
         if(dayStart == 0)
            return -1;
         datetime ws = dayStart + RangeHourStart * 3600 + RangeMinuteStart * 60;
         datetime we = dayStart + RangeHourEnd * 3600 + RangeMinuteEnd * 60;
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
        }
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
   if(!g_rangeDone)
     {
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
         return;
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
     }
   if(!g_rangeOK)
      return;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0 || ask < bid)
      return;
   double spr = (ask - bid) / _Point;
   double lim = 0.0;
   if(MaxSpreadPoints > 0.0)
      lim = MaxSpreadPoints;
   if(MaxSpreadPctOfSL > 0.0)
     {
      double l2 = StopLossPoints * MaxSpreadPctOfSL / 100.0;
      if(lim <= 0.0 || l2 < lim)
         lim = l2;
     }
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

void ManagePositions(datetime now)
  {
   if(!UsaBreakEven && !UsaTrailingStop)
      return;
   if(g_nPos <= 0 || now < g_nextMod)
      return;
   double ts = TickSize();
   double stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double frzLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
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
      double price = (isBuy ? bid : ask);
      double profitPts = (isBuy ? (price - entry) : (entry - price)) / _Point;
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
         continue;
      // distanza minima dal prezzo imposta dal broker
      if(isBuy)
         target = MathMin(target, price - stopLvl - ts);
      else
         target = MathMax(target, price + stopLvl + ts);
      target = NormPrice(target);
      if(!IsBetterSL(isBuy, target, sl, ts))
         continue;
      if(frzLvl > 0.0 && ((tp > 0.0 && MathAbs(tp - price) <= frzLvl) || (sl > 0.0 && MathAbs(price - sl) <= frzLvl)))
         continue;
      if(tp > 0.0 && MathAbs(tp - price) < stopLvl + ts)
         continue;   // il target e' dentro la distanza minima: il broker potrebbe rifiutare la modifica, e la chiusura e' imminente
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
//| Pannello                                                         |
//+------------------------------------------------------------------+
void UpdatePanel(datetime now)
  {
   if(!ShowPanel || now == g_lastPanel)
      return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   g_lastPanel = now;
   string s = "MultiDayRangeBreakout 3.00  magic " + IntegerToString(MagicNumber) + "\n";
   s += "Ora server " + TimeToString(now, TIME_DATE | TIME_MINUTES) + "  finestra " + StringFormat("%02d:%02d-%02d:%02d", TradeHourStart, TradeMinuteStart, TradeHourEnd, TradeMinuteEnd) +
        (InEntryWindow(now) ? "  (aperta)" : "  (chiusa)") + "\n";
   if(g_rangeDone)
      s += (g_rangeOK ? "Range: " : "Range scartato: ") + g_rangeInfo + "\n";
   else
      s += "Range: non ancora calcolato\n";
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
   g_logOutside = false;
   g_logSpread = false;
   g_logWait = false;
   g_status = "";
   g_nPos = -1;   // forza la rilettura dei contatori dalla storia
   g_nOrd = -1;
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
   if(RangeDaysBack < 0 || (RangeMode == RANGE_PREV_D1 && RangeDaysBack < 1))
      return "RangeDaysBack non valido per il modo scelto";
   if(RangeMode == RANGE_BARS && RangeBarsLookback < 1)
      return "RangeBarsLookback deve essere >= 1";
   if(RangeMode == RANGE_PREV_D1 && RangeDaySpan < 1)
      return "RangeDaySpan deve essere >= 1";
   if(RangeMode == RANGE_TIME && (RangeHourStart < 0 || RangeHourStart > 23 || RangeHourEnd < 0 || RangeHourEnd > 24 || RangeMinuteStart < 0 || RangeMinuteStart > 59 || RangeMinuteEnd < 0 || RangeMinuteEnd > 59))
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
   Print("MultiDayRangeBreakout 3.00 su ", _Symbol, ": range ", EnumToString(RangeMode), ", finestra ", StringFormat("%02d:%02d-%02d:%02d", TradeHourStart, TradeMinuteStart, TradeHourEnd, TradeMinuteEnd),
         " ora server, SL ", DoubleToString(StopLossPoints, 0), " TP ", (UseTakeProfit ? DoubleToString(TakeProfitPoints, 0) : "nessuno"), " punti");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
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
   SyncCounters(now);
   ManageOrders(now);
   ManagePositions(now);
   TryPlaceSetup(now);
   UpdatePanel(now);
  }
//+------------------------------------------------------------------+
