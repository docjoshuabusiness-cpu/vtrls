//+------------------------------------------------------------------+
//|                Enhanced Multi-Day Range Breakout EA - MQL5       |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"

input double LotSize = 0.01;

// Range tramite barre
input bool UseBarRange = true;
input int RangeBarsLookback = 25;

// Range tramite orario
input bool UseTimeRange = false;
input int RangeHourStart = 16;
input int RangeMinuteStart = 0;
input int RangeHourEnd = 0;      // mezzanotte
input int RangeMinuteEnd = 0;
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;

// === NUOVE OPZIONI MULTI-DAY ENHANCED ===
input string sep1 = "=== MULTI-DAY TRADING OPTIONS ===";
input bool EnableMultiDayTrading = true;  // Abilita/disabilita completamente
input bool UsePreviousDayRange = true;    // Usa range del giorno precedente
input int RangeDaysBack = 1;              // Quanti giorni indietro per il range (1=ieri)
input bool RequireRangeConfirmation = true; // Richiede che il range sia "valido"
input double MinRangePoints = 50;         // Range minimo in punti per essere valido
input double MaxRangePoints = 500;        // Range massimo in punti per essere valido

// === GESTIONE RANGE UTILIZZATI ===
input string sep1b = "=== RANGE MANAGEMENT ===";
input bool OneTradePerRange = true;       // Solo un trade per ogni range
input bool ResetOnNewDay = true;          // Reset automatico a nuovo giorno
input bool AllowNewTradeIfPositionHeld = true; // Permetti nuovo trade se posizione aperta dal giorno precedente
input int MaxTradesPerDay = 1;            // Massimo numero di trade per giorno

// Finestra oraria per apertura ordini
input string sep2 = "=== TRADING WINDOW ===";
input int TradeHourStart = 10;
input int TradeMinuteStart = 0;
input int TradeHourEnd = 11;
input int TradeMinuteEnd = 0;
input bool TradeSameDayOnly = false;      // Se true, trade solo nello stesso giorno del range
input bool AvoidMidnightHours = true;    // Evita piazzamento ordini a mezzanotte

// Stop Loss e Take Profit
input string sep3 = "=== RISK MANAGEMENT ===";
input double StopLossPoints = 100;
input double TakeProfitPoints = 200;
input bool UseTakeProfit = true;

// Offset (distanza in punti dal range per pending orders)
input int PendingOrderOffsetPoints = 20;

// BreakEven & Trailing Stop
input string sep4 = "=== ADVANCED MANAGEMENT ===";
input bool UsaBreakEven = true;
input int BreakEvenAttivazione = 100;
input int BreakEvenOffset = 10;

input bool UsaTrailingStop = true;
input int TrailingStartProfit = 150;
input int TrailingStep = 20;
input int TrailingOffset = 30;

// Slippage e Magic Number
input string sep5 = "=== SYSTEM SETTINGS ===";
input int Slippage = 10;
input int MagicNumber = 123456;
input string OrderComment = "MultiDayRangeV2";

// === VARIABILI GLOBALI ENHANCED ===
double upperRange = 0.0;
double lowerRange = 0.0;
datetime rangeCalculationDate = 0;   // Quando è stato calcolato il range
datetime rangeValidDate = 0;         // Per quale giorno è valido il range
bool isRangeValid = false;
bool pendingOrdersPlaced = false;
string rangeInfo = "";

// === NUOVE VARIABILI PER CONTROLLO RANGE UTILIZZATI ===
bool rangeAlreadyTraded = false;     // Se questo range è già stato tradato
datetime lastTradeDate = 0;          // Data dell'ultimo trade
datetime lastPositionOpenDate = 0;   // Data di apertura dell'ultima posizione
int tradesCountToday = 0;            // Numero di trade oggi
datetime currentTradingDay = 0;      // Giorno di trading corrente
datetime lastAttemptTime = 0;        // Ultimo tentativo di piazzare ordini
int failedAttemptsCount = 0;         // Contatore tentativi falliti

//+------------------------------------------------------------------+
//| Funzioni di utilità enhanced                                     |
//+------------------------------------------------------------------+
datetime DateOfDay(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t,dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   return StructToTime(dt);
}

datetime GetDateNDaysBack(datetime currentDate, int daysBack)
{
   return currentDate - (daysBack * 24 * 3600);
}

bool IsMarketOpen()
{
   // Verifica se il mercato è aperto per il trading
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   
   // Controlla se è weekend
   if(dt.day_of_week == 0 || dt.day_of_week == 6) // Domenica o Sabato
   {
      Print("📅 Weekend - Mercato chiuso");
      return false;
   }
      
   // Controlla orari di trading Forex (più precisi)
   // Domenica 22:00 GMT - Venerdì 22:00 GMT
   if(dt.day_of_week == 1) // Lunedì
   {
      if(dt.hour < 1) // Prima dell'1:00 GMT lunedì
      {
         Print("🕐 Lunedì prima 01:00 GMT - Mercato chiuso");
         return false;
      }
   }
      
   if(dt.day_of_week == 5) // Venerdì  
   {
      if(dt.hour >= 22) // Dopo le 22:00 GMT venerdì
      {
         Print("🕐 Venerdì dopo 22:00 GMT - Mercato chiuso");
         return false;
      }
   }

   // Controlla tra domenica 22:00 e lunedì 01:00
   if(dt.day_of_week == 0 && dt.hour < 22) // Domenica prima delle 22:00
   {
      Print("🕐 Domenica prima 22:00 GMT - Mercato chiuso");
      return false;
   }
      
   return true;
}

bool IsWithinTime(datetime t,int sh,int sm,int eh,int em)
{
   MqlDateTime dt;
   TimeToStruct(t,dt);
   int mins=dt.hour*60+dt.min;
   int startM=sh*60+sm;
   int endM=eh*60+em;
   if(startM<=endM) return (mins>=startM && mins<=endM);
   return (mins>=startM || mins<=endM);
}

//+------------------------------------------------------------------+
//| Funzioni MQL5 per conteggio ordini                               |
//+------------------------------------------------------------------+
int OrdersTotalByMagic(int magic)
{
   int total = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if((int)OrderGetInteger(ORDER_MAGIC) == magic)
            total++;
      }
   }
   return total;
}

int PositionsTotalByMagic(int magic)
{
   int total = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      string symbol = PositionGetSymbol(i);
      if(PositionSelect(symbol))
      {
         if((int)PositionGetInteger(POSITION_MAGIC) == magic)
            total++;
      }
   }
   return total;
}

//+------------------------------------------------------------------+
//| Calcolo range enhanced con validazione                           |
//+------------------------------------------------------------------+
void CalculateRange()
{
   // NUOVO: Controlla se deve calcolare un nuovo range
   if(!ShouldCalculateNewRange())
      return;
      
   datetime now = TimeCurrent();
   datetime today = DateOfDay(now);
   
   // Se non è multi-day trading, usa logica originale
   if(!EnableMultiDayTrading)
   {
      CalculateRangeOriginal();
      return;
   }
   
   // Calcola per quale giorno dovremmo avere il range
   datetime targetRangeDate = GetDateNDaysBack(today, RangeDaysBack);
   
   // Reset delle variabili
   isRangeValid = false;
   upperRange = 0.0;
   lowerRange = 0.0;
   
   if(UsePreviousDayRange && UseTimeRange)
   {
      // Calcola range basato su orario del giorno target
      CalculateTimeRangeForDate(targetRangeDate);
   }
   else if(UsePreviousDayRange && UseBarRange)
   {
      // Calcola range basato su barre del giorno target  
      CalculateBarRangeForDate(targetRangeDate);
   }
   
   // Validazione del range
   ValidateRange();
   
   if(isRangeValid)
   {
      rangeValidDate = today;  // Range valido per oggi
      rangeCalculationDate = now;
      pendingOrdersPlaced = false; // Reset per permettere nuovi ordini
      
      // NUOVO: Reset stato range utilizzato solo se è un nuovo range
      if(rangeValidDate != today || ResetOnNewDay)
      {
         rangeAlreadyTraded = false;
      }
      
      rangeInfo = StringFormat("Range: %.5f-%.5f (%.1f pts) from %s", 
                              lowerRange, upperRange, 
                              (upperRange-lowerRange)/_Point,
                              TimeToString(targetRangeDate, TIME_DATE));
      Print("✓ ", rangeInfo);
   }
}

void CalculateTimeRangeForDate(datetime targetDate)
{
   MqlDateTime dtStart, dtEnd;
   TimeToStruct(targetDate, dtStart); 
   dtEnd = dtStart;
   
   dtStart.hour = RangeHourStart; 
   dtStart.min = RangeMinuteStart; 
   dtStart.sec = 0;
   dtEnd.hour = RangeHourEnd; 
   dtEnd.min = RangeMinuteEnd; 
   dtEnd.sec = 0;
   
   // Se range attraversa mezzanotte, aggiusta la data di fine
   if(RangeHourEnd < RangeHourStart)
   {
      dtEnd.day += 1;
   }
   
   datetime startTime = StructToTime(dtStart);
   datetime endTime = StructToTime(dtEnd);
   
   int startIndex = iBarShift(_Symbol, Timeframe, startTime, false);
   int endIndex = iBarShift(_Symbol, Timeframe, endTime, false);
   
   if(startIndex == -1 || endIndex == -1)
   {
      Print("⚠ Impossibile trovare barre per il range temporale richiesto");
      return;
   }
   
   double maxH = -DBL_MAX, minL = DBL_MAX;
   int barsProcessed = 0;
   
   for(int i = endIndex; i <= startIndex; i++)
   {
      double h = iHigh(_Symbol, Timeframe, i);
      double l = iLow(_Symbol, Timeframe, i);
      
      if(h > 0 && l > 0) // Verifica validità dati
      {
         maxH = MathMax(maxH, h);
         minL = MathMin(minL, l);
         barsProcessed++;
      }
   }
   
   if(barsProcessed > 0)
   {
      upperRange = maxH;
      lowerRange = minL;
   }
   else
   {
      Print("⚠ Nessuna barra valida trovata per il range");
   }
}

void CalculateBarRangeForDate(datetime targetDate)
{
   // Trova l'indice della barra più vicina alla data target
   int targetIndex = iBarShift(_Symbol, Timeframe, targetDate, false);
   
   if(targetIndex == -1)
   {
      Print("⚠ Impossibile trovare barre per la data target");
      return;
   }
   
   double maxH = -DBL_MAX, minL = DBL_MAX;
   int barsProcessed = 0;
   
   // Calcola range dalle barre successive alla data target
   for(int i = targetIndex + 1; i <= targetIndex + RangeBarsLookback; i++)
   {
      double h = iHigh(_Symbol, Timeframe, i);
      double l = iLow(_Symbol, Timeframe, i);
      
      if(h > 0 && l > 0)
      {
         maxH = MathMax(maxH, h);
         minL = MathMin(minL, l);
         barsProcessed++;
      }
   }
   
   if(barsProcessed > 0)
   {
      upperRange = maxH;
      lowerRange = minL;
   }
}

void CalculateRangeOriginal()
{
   // Logica originale per compatibilità
   datetime now = TimeCurrent();
   datetime today = DateOfDay(now);

   if(UseBarRange)
   {
      double maxH = -DBL_MAX, minL = DBL_MAX;
      for(int i = 1; i <= RangeBarsLookback; i++)
      {
         maxH = MathMax(maxH, iHigh(_Symbol, Timeframe, i));
         minL = MathMin(minL, iLow(_Symbol, Timeframe, i));
      }
      upperRange = maxH;
      lowerRange = minL;
      rangeValidDate = today;
      isRangeValid = true;
   }

   if(UseTimeRange)
   {
      MqlDateTime dtStart, dtEnd;
      TimeToStruct(now, dtStart); 
      dtEnd = dtStart;

      dtStart.hour = RangeHourStart; 
      dtStart.min = RangeMinuteStart; 
      dtStart.sec = 0;
      dtEnd.hour = RangeHourEnd; 
      dtEnd.min = RangeMinuteEnd; 
      dtEnd.sec = 0;

      datetime startTime = StructToTime(dtStart);
      datetime endTime = StructToTime(dtEnd);

      int startIndex = iBarShift(_Symbol, Timeframe, endTime, false);
      int barsCount = iBarShift(_Symbol, Timeframe, startTime, false) - startIndex;

      double maxH = -DBL_MAX, minL = DBL_MAX;
      for(int i = 0; i < barsCount; i++)
      {
         double h = iHigh(_Symbol, Timeframe, startIndex + i);
         double l = iLow(_Symbol, Timeframe, startIndex + i);
         maxH = MathMax(maxH, h);
         minL = MathMin(minL, l);
      }
      upperRange = maxH;
      lowerRange = minL;
      rangeValidDate = today;
      isRangeValid = true;
   }
}

void ValidateRange()
{
   if(upperRange <= 0 || lowerRange <= 0 || upperRange <= lowerRange)
   {
      Print("⚠ Range non valido: upperRange=", upperRange, " lowerRange=", lowerRange);
      return;
   }
   
   double rangePoints = (upperRange - lowerRange) / _Point;
   
   if(RequireRangeConfirmation)
   {
      if(rangePoints < MinRangePoints)
      {
         Print("⚠ Range troppo piccolo: ", rangePoints, " punti (minimo: ", MinRangePoints, ")");
         return;
      }
      
      if(rangePoints > MaxRangePoints)
      {
         Print("⚠ Range troppo grande: ", rangePoints, " punti (massimo: ", MaxRangePoints, ")");
         return;
      }
   }
   
   isRangeValid = true;
}

//+------------------------------------------------------------------+
//| Controllo opportunità di trade enhanced                          |
//+------------------------------------------------------------------+
void CheckForTradeOpportunities()
{
   if(!isRangeValid)
      return;
   
   datetime now = TimeCurrent();
   datetime today = DateOfDay(now);
   
   // NUOVO: Evita spam di tentativi - max 1 tentativo ogni 5 minuti
   if(lastAttemptTime > 0 && (now - lastAttemptTime) < 300) // 5 minuti
   {
      return;
   }
   
   // NUOVO: Se troppi tentativi falliti, aspetta più tempo
   if(failedAttemptsCount >= 3 && (now - lastAttemptTime) < 1800) // 30 minuti dopo 3 fallimenti
   {
      return;
   }
   
   // NUOVO: Gestione posizioni aperte dai giorni precedenti
   bool hasOpenPosition = (PositionsTotalByMagic(MagicNumber) > 0);
   
   if(hasOpenPosition)
   {
      // Cancella pending orders se c'è una posizione aperta
      CancelPendingOrders();
      
      // Se AllowNewTradeIfPositionHeld è attivo, controlla se posizione è di ieri
      if(AllowNewTradeIfPositionHeld && lastPositionOpenDate > 0)
      {
         datetime positionDay = DateOfDay(lastPositionOpenDate);
         
         if(positionDay < today)
         {
            // La posizione è di un giorno precedente, permetti nuovo setup
            Print("📅 Posizione aperta dal giorno precedente - Permetto nuovo setup");
            Print("   Pos aperta: ", TimeToString(positionDay, TIME_DATE), " Oggi: ", TimeToString(today, TIME_DATE));
            
            // Reset del flag per permettere nuovo trade
            if(OneTradePerRange)
            {
               rangeAlreadyTraded = false;
               Print("🔄 Flag rangeAlreadyTraded resettato per nuovo giorno");
            }
         }
         else
         {
            // Posizione aperta oggi, non fare nuovi trade
            return;
         }
      }
      else
      {
         // Logica originale - se c'è posizione, stop
         return;
      }
   }
   
   // NUOVO: Controllo se il range è già stato utilizzato
   if(OneTradePerRange && rangeAlreadyTraded)
   {
      return; // Non fare più trade su questo range
   }
   
   // NUOVO: Controllo limite trade giornalieri
   if(currentTradingDay != today)
   {
      // Nuovo giorno, reset contatori
      currentTradingDay = today;
      tradesCountToday = 0;
      failedAttemptsCount = 0; // Reset anche i tentativi falliti
      
      if(ResetOnNewDay)
      {
         rangeAlreadyTraded = false; // Reset per nuovo giorno
         Print("🆕 Nuovo giorno di trading - Reset contatori");
      }
   }
   
   if(tradesCountToday >= MaxTradesPerDay)
   {
      return; // Limite raggiunto, non logare ogni tick
   }
      
   // Se ci sono già ordini, non piazzarne altri
   if(OrdersTotalByMagic(MagicNumber) > 0)
      return;
      
   if(pendingOrdersPlaced)
      return;
   
   // NUOVO: Verifica se il mercato è aperto
   if(!IsMarketOpen())
   {
      // Non stampare ogni tick, solo al primo check
      if((now - lastAttemptTime) > 3600) // Log solo ogni ora
      {
         Print("⏸ Mercato chiuso - Attendo apertura");
      }
      return;
   }
   
   // Verifica se siamo nella finestra temporale di trading
   if(!IsWithinTime(now, TradeHourStart, TradeMinuteStart, TradeHourEnd, TradeMinuteEnd))
      return;
   
   // NUOVO: Evita orari rischiosi (mezzanotte)
   if(AvoidMidnightHours)
   {
      MqlDateTime dt;
      TimeToStruct(now, dt);
      if(dt.hour >= 23 || dt.hour <= 1) // Evita 23:00-01:00
      {
         return;
      }
   }
   
   // Se TradeSameDayOnly è attivo, verifica che stiamo tradando nello stesso giorno del range
   if(TradeSameDayOnly && EnableMultiDayTrading)
   {
      if(today != rangeValidDate)
         return;
   }
   
   // Aggiorna il tempo dell'ultimo tentativo
   lastAttemptTime = now;
   
   PlacePendingOrders();
}

//+------------------------------------------------------------------+
//| Piazza pending orders MQL5 VERSION                               |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
   if(!isRangeValid) return;

   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentMid = (currentAsk + currentBid) / 2;
   
   double priceBuy  = upperRange + PendingOrderOffsetPoints * _Point;
   double priceSell = lowerRange - PendingOrderOffsetPoints * _Point;

   // NUOVO: Controllo distanze minime più intelligente
   double minStopDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freezeDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   
   // Se i prezzi sono troppo vicini, aggiusta le distanze
   if(priceBuy - currentMid < minStopDistance)
   {
      priceBuy = currentMid + minStopDistance + 10 * _Point; // +10 punti di sicurezza
      Print("📏 BuyStop aggiustato per distanza minima: ", priceBuy);
   }
   
   if(currentMid - priceSell < minStopDistance)
   {
      priceSell = currentMid - minStopDistance - 10 * _Point; // -10 punti di sicurezza  
      Print("📏 SellStop aggiustato per distanza minima: ", priceSell);
   }
   
   // Verifica che i prezzi siano ancora logici dopo gli aggiustamenti
   if(priceBuy <= currentMid || priceSell >= currentMid)
   {
      Print("⚠ Prezzi non validi dopo aggiustamento - Skip setup");
      Print("   Current: ", currentMid, " BuyStop: ", priceBuy, " SellStop: ", priceSell);
      return;
   }

   double slBuy  = priceBuy - StopLossPoints * _Point;
   double slSell = priceSell + StopLossPoints * _Point;

   double tpBuy = UseTakeProfit ? priceBuy + TakeProfitPoints * _Point : 0;
   double tpSell = UseTakeProfit ? priceSell - TakeProfitPoints * _Point : 0;

   MqlTradeRequest req;
   MqlTradeResult res;
   bool buySuccess = false, sellSuccess = false;

   // Piazza BuyStop solo se il prezzo è sopra il mercato
   if(priceBuy > currentAsk + minStopDistance)
   {
      ZeroMemory(req); ZeroMemory(res);
      req.action    = TRADE_ACTION_PENDING;
      req.symbol    = _Symbol;
      req.volume    = LotSize;
      req.type      = ORDER_TYPE_BUY_STOP;
      req.price     = NormalizeDouble(priceBuy, _Digits);
      req.sl        = NormalizeDouble(slBuy, _Digits);
      req.tp        = NormalizeDouble(tpBuy, _Digits);
      req.deviation = Slippage;
      req.magic     = MagicNumber;
      req.comment   = OrderComment + " Buy";

      if(OrderSend(req, res))
      {
         buySuccess = true;
         Print("✓ BuyStop piazzato: ", res.order, " @ ", priceBuy, " (Current: ", currentAsk, ")");
      }
      else
      {
         Print("⚠ Errore BuyStop: ", res.retcode, " - ", res.comment);
         Print("   Prezzo: ", priceBuy, " vs Current: ", currentAsk, " Distanza: ", (priceBuy-currentAsk)/_Point, " pts");
      }
   }
   else
   {
      Print("⚠ BuyStop skip - Troppo vicino al mercato");
   }

   // Piazza SellStop solo se il prezzo è sotto il mercato
   if(priceSell < currentBid - minStopDistance)
   {
      ZeroMemory(req); ZeroMemory(res);
      req.action    = TRADE_ACTION_PENDING;
      req.symbol    = _Symbol;
      req.volume    = LotSize;
      req.type      = ORDER_TYPE_SELL_STOP;
      req.price     = NormalizeDouble(priceSell, _Digits);
      req.sl        = NormalizeDouble(slSell, _Digits);
      req.tp        = NormalizeDouble(tpSell, _Digits);
      req.deviation = Slippage;
      req.magic     = MagicNumber;
      req.comment   = OrderComment + " Sell";

      if(OrderSend(req, res))
      {
         sellSuccess = true;
         Print("✓ SellStop piazzato: ", res.order, " @ ", priceSell, " (Current: ", currentBid, ")");
      }
      else
      {
         Print("⚠ Errore SellStop: ", res.retcode, " - ", res.comment);
         Print("   Prezzo: ", priceSell, " vs Current: ", currentBid, " Distanza: ", (currentBid-priceSell)/_Point, " pts");
      }
   }
   else
   {
      Print("⚠ SellStop skip - Troppo vicino al mercato");
   }

   if(buySuccess || sellSuccess)
   {
      pendingOrdersPlaced = true;
      lastPositionOpenDate = TimeCurrent(); // NUOVO: Traccia quando è stata aperta la posizione
      failedAttemptsCount = 0; // Reset tentativi falliti dopo successo
      Print("📊 ", rangeInfo);
      Print("💰 Setup completato con ", (buySuccess ? "BuyStop" : ""), (buySuccess && sellSuccess ? " + " : ""), (sellSuccess ? "SellStop" : ""));
      Print("📅 Posizione aperta il: ", TimeToString(lastPositionOpenDate, TIME_DATE|TIME_MINUTES));
   }
   else
   {
      failedAttemptsCount++; // Incrementa tentativi falliti
      Print("⚠ Nessun ordine piazzato (tentativo ", failedAttemptsCount, "/3) - Range troppo vicino al prezzo corrente");
      Print("   Range: ", lowerRange, "-", upperRange, " vs Current: ", currentMid);
      
      if(failedAttemptsCount >= 3)
      {
         Print("⏸ Troppi tentativi falliti - Pausa 30 minuti");
      }
   }
}

//+------------------------------------------------------------------+
//| Gestione BreakEven e Trailing Stop (MQL5)                        |
//+------------------------------------------------------------------+
void ManageTrade()
{
   if(!PositionSelect(_Symbol)) return;

   ulong ticket = PositionGetInteger(POSITION_TICKET);
   int type = (int)PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitPoints = (type == POSITION_TYPE_BUY) ? (price - entry) / _Point : (entry - price) / _Point;

   MqlTradeRequest req; 
   MqlTradeResult res;
   ZeroMemory(req); 
   ZeroMemory(res);

   // BreakEven
   if(UsaBreakEven && profitPoints >= BreakEvenAttivazione)
   {
      double newSL = (type == POSITION_TYPE_BUY) ? entry + BreakEvenOffset * _Point : entry - BreakEvenOffset * _Point;
      if((type == POSITION_TYPE_BUY && sl < newSL) || (type == POSITION_TYPE_SELL && sl > newSL))
      {
         req.action = TRADE_ACTION_SLTP;
         req.position = ticket;
         req.sl = NormalizeDouble(newSL, _Digits);
         req.tp = PositionGetDouble(POSITION_TP);
         req.magic = MagicNumber;
         req.symbol = _Symbol;
         if(OrderSend(req, res))
            Print("✓ BreakEven applicato @ ", newSL);
         else
            Print("⚠ Errore BreakEven: ", res.retcode);
      }
   }

   // Trailing
   if(UsaTrailingStop && profitPoints >= TrailingStartProfit)
   {
      double newSL = (type == POSITION_TYPE_BUY) ? price - TrailingOffset * _Point : price + TrailingOffset * _Point;
      if((type == POSITION_TYPE_BUY && newSL > sl + TrailingStep * _Point) ||
         (type == POSITION_TYPE_SELL && newSL < sl - TrailingStep * _Point))
      {
         ZeroMemory(req); ZeroMemory(res);
         req.action = TRADE_ACTION_SLTP;
         req.position = ticket;
         req.sl = NormalizeDouble(newSL, _Digits);
         req.tp = PositionGetDouble(POSITION_TP);
         req.magic = MagicNumber;
         req.symbol = _Symbol;
         if(OrderSend(req, res))
            Print("✓ Trailing aggiornato @ ", newSL);
         else
            Print("⚠ Errore Trailing: ", res.retcode);
      }
   }
}

//+------------------------------------------------------------------+
//| Cancella tutti i pending orders del Magic Number                 |
//+------------------------------------------------------------------+
void CancelPendingOrders()
{
   MqlTradeRequest req;
   MqlTradeResult res;
   
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if((int)OrderGetInteger(ORDER_MAGIC) == MagicNumber && 
            StringCompare(OrderGetString(ORDER_SYMBOL), _Symbol) == 0)
         {
            ZeroMemory(req); 
            ZeroMemory(res);
            
            req.action = TRADE_ACTION_REMOVE;
            req.order = ticket;
            
            if(OrderSend(req, res))
            {
               Print("✓ Pending order cancellato: ", ticket);
            }
            else
            {
               Print("⚠ Errore cancellazione ordine ", ticket, ": ", res.retcode);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Reset sistema dopo chiusura posizione                            |
//+------------------------------------------------------------------+
void CheckForReset()
{
   // Se non ci sono posizioni né ordini pending, gestiamo il reset
   if(PositionsTotalByMagic(MagicNumber) == 0 && OrdersTotalByMagic(MagicNumber) == 0)
   {
      if(pendingOrdersPlaced)
      {
         // NUOVO: Segna il range come utilizzato quando una posizione è stata aperta e poi chiusa
         if(OneTradePerRange)
         {
            rangeAlreadyTraded = true;
            lastTradeDate = TimeCurrent();
            tradesCountToday++;
            
            Print("🔒 Range marcato come utilizzato - Trade completato");
            Print("📊 Trade oggi: ", tradesCountToday, "/", MaxTradesPerDay);
         }
         
         pendingOrdersPlaced = false;
         Print("🔄 Trade cycle completato");
         
         // NON invalidare il range se OneTradePerRange è attivo
         if(!OneTradePerRange && EnableMultiDayTrading)
         {
            isRangeValid = false;
            rangeValidDate = 0;
            Print("🔄 Range invalidato per ricalcolo");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Controlla se deve calcolare un nuovo range                       |
//+------------------------------------------------------------------+
bool ShouldCalculateNewRange()
{
   datetime now = TimeCurrent();
   datetime today = DateOfDay(now);
   
   // Se non è multi-day, sempre calcola
   if(!EnableMultiDayTrading)
      return true;
   
   // Se è un nuovo giorno e ResetOnNewDay è attivo
   if(ResetOnNewDay && currentTradingDay != today)
      return true;
   
   // NUOVO: Se c'è una posizione aperta dal giorno precedente e AllowNewTradeIfPositionHeld è attivo
   if(AllowNewTradeIfPositionHeld && PositionsTotalByMagic(MagicNumber) > 0 && lastPositionOpenDate > 0)
   {
      datetime positionDay = DateOfDay(lastPositionOpenDate);
      if(positionDay < today)
      {
         Print("🔄 Forzo ricalcolo range - Posizione aperta dal giorno precedente");
         return true;
      }
   }
   
   // Se non abbiamo un range valido
   if(!isRangeValid)
      return true;
   
   // Se abbiamo un range ma non è per oggi
   if(rangeValidDate != today)
      return true;
   
   // Se OneTradePerRange è disabilitato, permetti ricalcolo
   if(!OneTradePerRange)
      return true;
   
   // Altrimenti, non ricalcolare se range già utilizzato
   return false;
}

//+------------------------------------------------------------------+
//| Funzione per display info su chart                               |
//+------------------------------------------------------------------+
void DisplayInfo()
{
   string info = "\n=== MULTI-DAY RANGE BREAKOUT ===\n";
   info += "Status: " + (isRangeValid ? "RANGE VALIDO ✓" : "IN ATTESA RANGE ⏳") + "\n";
   
   if(isRangeValid)
   {
      info += rangeInfo + "\n";
      double currentPrice = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2;
      info += "Prezzo Corrente: " + DoubleToString(currentPrice, _Digits) + "\n";
      info += "Range Status: " + (rangeAlreadyTraded ? "UTILIZZATO ❌" : "DISPONIBILE ✅") + "\n";
      info += "Ordini: " + (pendingOrdersPlaced ? "PIAZZATI ✓" : "DA PIAZZARE ⏳") + "\n";
   }
   
   info += "Multi-day: " + (EnableMultiDayTrading ? "ON" : "OFF") + "\n";
   info += "One Trade/Range: " + (OneTradePerRange ? "ON" : "OFF") + "\n";
   info += "Allow New if Held: " + (AllowNewTradeIfPositionHeld ? "ON" : "OFF") + "\n";
   info += "Trade oggi: " + IntegerToString(tradesCountToday) + "/" + IntegerToString(MaxTradesPerDay) + "\n";
   info += "Giorni indietro: " + IntegerToString(RangeDaysBack) + "\n";
   info += "Mercato: " + (IsMarketOpen() ? "APERTO ✓" : "CHIUSO ⚠") + "\n";
   info += "Pending Orders: " + IntegerToString(OrdersTotalByMagic(MagicNumber)) + "\n";
   info += "Posizioni Aperte: " + IntegerToString(PositionsTotalByMagic(MagicNumber)) + "\n";
   
   // NUOVO: Mostra info su posizioni aperte dal giorno precedente
   if(PositionsTotalByMagic(MagicNumber) > 0 && lastPositionOpenDate > 0)
   {
      datetime today = DateOfDay(TimeCurrent());
      datetime posDay = DateOfDay(lastPositionOpenDate);
      if(posDay < today)
      {
         info += "⚠ Posizione da: " + TimeToString(posDay, TIME_DATE) + "\n";
      }
   }
   
   Comment(info);
}

//+------------------------------------------------------------------+
//| Main Functions                                                   |
//+------------------------------------------------------------------+
int OnInit()
{ 
   Print("🚀 Enhanced Multi-Day Range Breakout EA Started");
   Print("📋 Multi-Day Trading: ", (EnableMultiDayTrading ? "ENABLED" : "DISABLED"));
   Print("📋 Range Days Back: ", RangeDaysBack);
   return(INIT_SUCCEEDED); 
}

void OnTick()
{
   CalculateRange();
   CheckForTradeOpportunities();
   ManageTrade();
   CheckForReset();  // NUOVO: Controlla se resettare il sistema
   DisplayInfo();
}

void OnDeinit(const int reason)
{
   Comment("");
   Print("🛑 EA Terminato - Motivo: ", reason);
}