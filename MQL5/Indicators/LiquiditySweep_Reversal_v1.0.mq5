//+------------------------------------------------------------------+
//|                              LiquiditySweep_Reversal_v1.0.mq5    |
//|  Pattern: sweep del minimo/massimo precedente + chiusura di       |
//|  rientro (stop-hunt / liquidity grab reversal).                   |
//|                                                                   |
//|  BUY : la candela segnale rompe il MINIMO della finestra di N     |
//|        candele precedenti e CHIUDE sopra un riferimento della      |
//|        candela precedente (open / close / high della finestra).    |
//|  SELL: speculare (rompe il MASSIMO, chiude sotto open/close/low).  |
//|                                                                   |
//|  Ogni condizione di chiusura e' attivabile singolarmente e le      |
//|  condizioni attive si combinano in ANY (almeno una) o ALL (tutte). |
//|                                                                   |
//|  MULTI-TIMEFRAME: il pattern viene cercato su InpPatternTF (>= TF  |
//|  del grafico) e la freccia viene disegnata sul grafico corrente    |
//|  in corrispondenza della candela che chiude la barra HTF.          |
//|  NON RIPINGE: un segnale nasce solo quando la barra HTF e' chiusa. |
//|                                                                   |
//|  Buffer esposti per uso da EA via iCustom():                       |
//|    0 = freccia BUY (prezzo)   1 = freccia SELL (prezzo)            |
//|    2 = segnale (+1 buy / -1 sell / 0)                              |
//|    3 = livello spazzato (min/max della finestra) -> utile per SL   |
//+------------------------------------------------------------------+
#property copyright "Advanced Quant Systems"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "SweepBuy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

#property indicator_label2  "SweepSell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

#property indicator_label3  "Signal"
#property indicator_type3   DRAW_NONE

#property indicator_label4  "SweptLevel"
#property indicator_type4   DRAW_NONE

//--- logica di combinazione delle condizioni di chiusura
enum ENUM_COND_LOGIC
  {
   COND_ANY = 0,   // ANY - basta una delle condizioni attive
   COND_ALL = 1    // ALL - servono tutte le condizioni attive
  };

//--- dove ancorare la freccia sul grafico quando il TF pattern e' superiore
enum ENUM_SIG_ANCHOR
  {
   ANCHOR_TF_CLOSE = 0,   // Ultima candela del grafico dentro la barra HTF
   ANCHOR_NEXT_BAR = 1    // Prima candela del grafico dopo la chiusura HTF
  };

//==================== INPUT: struttura del pattern ==================
input group                "=== PATTERN ==="
input ENUM_TIMEFRAMES      InpPatternTF            = PERIOD_CURRENT; // TF su cui cercare il pattern (>= TF grafico)
input int                  InpSweepLookback        = 1;              // N candele della finestra spazzata (1 = candela precedente)
input bool                 InpRequireCloseBackIn   = true;           // Chiusura deve rientrare oltre il livello spazzato

input group                "=== CONDIZIONI DI CHIUSURA (attivabili) ==="
input bool                 InpUsePrevOpen          = true;           // BUY: close > OPEN prec.  | SELL: close < OPEN prec.
input bool                 InpUsePrevClose         = false;          // BUY: close > CLOSE prec. | SELL: close < CLOSE prec.
input bool                 InpUsePrevExtreme       = false;          // BUY: close > HIGH fin.   | SELL: close < LOW fin.
input ENUM_COND_LOGIC      InpCondLogic            = COND_ANY;       // Combinazione condizioni attive

input group                "=== FILTRI OPZIONALI ==="
input bool                 InpRequireBodyDir       = true;           // Candela segnale rialzista (buy) / ribassista (sell)
input double               InpMinSweepATR          = 0.0;            // Penetrazione minima oltre il livello, in ATR (0 = off)
input double               InpMinClosePosPct       = 0.0;            // Chiusura nel top/bottom X% del range candela (0 = off)
input int                  InpATRPeriod            = 14;             // Periodo ATR (filtri + offset frecce)

input group                "=== VISUALIZZAZIONE ==="
input ENUM_SIG_ANCHOR      InpAnchor               = ANCHOR_TF_CLOSE;// Ancoraggio freccia in modalita' MTF
input int                  InpArrowBuyCode         = 233;            // Codice freccia BUY (Wingdings)
input int                  InpArrowSellCode        = 234;            // Codice freccia SELL (Wingdings)
input color                InpBuyColor             = clrDodgerBlue;  // Colore BUY
input color                InpSellColor            = clrRed;         // Colore SELL
input double               InpArrowOffsetATR       = 0.40;           // Distanza freccia dalla candela (in ATR)
input int                  InpMaxBars              = 3000;           // Max barre del grafico da elaborare

input group                "=== ALERT ==="
input bool                 InpAlertPopup           = false;          // Alert popup
input bool                 InpAlertPush            = false;          // Notifica push
input bool                 InpAlertEmail           = false;          // Email

//==================== BUFFER =======================================
double BufBuy[];
double BufSell[];
double BufSignal[];
double BufLevel[];

//==================== STATO GLOBALE ================================
ENUM_TIMEFRAMES g_tf       = PERIOD_CURRENT;
int             g_tfSec    = 0;
int             g_lookback = 1;
datetime        g_lastAlertBar = 0;   // time di apertura della barra HTF gia' allertata

//+------------------------------------------------------------------+
int OnInit()
  {
   g_tf = (InpPatternTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpPatternTF;

   if(PeriodSeconds(g_tf) < PeriodSeconds(_Period))
     {
      Print("ERRORE: il TF del pattern (", EnumToString(g_tf),
            ") deve essere >= al TF del grafico (", EnumToString((ENUM_TIMEFRAMES)_Period), ").");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(!InpUsePrevOpen && !InpUsePrevClose && !InpUsePrevExtreme)
     {
      Print("ERRORE: attiva almeno una condizione di chiusura (open / close / extreme).");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_tfSec    = PeriodSeconds(g_tf);
   g_lookback = MathMax(1, InpSweepLookback);

   SetIndexBuffer(0, BufBuy,    INDICATOR_DATA);
   SetIndexBuffer(1, BufSell,   INDICATOR_DATA);
   SetIndexBuffer(2, BufSignal, INDICATOR_DATA);
   SetIndexBuffer(3, BufLevel,  INDICATOR_DATA);

   ArraySetAsSeries(BufBuy,    false);
   ArraySetAsSeries(BufSell,   false);
   ArraySetAsSeries(BufSignal, false);
   ArraySetAsSeries(BufLevel,  false);

   PlotIndexSetInteger(0, PLOT_ARROW, InpArrowBuyCode);
   PlotIndexSetInteger(1, PLOT_ARROW, InpArrowSellCode);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpBuyColor);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpSellColor);

   for(int p = 0; p < 4; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, (p <= 1) ? EMPTY_VALUE : 0.0);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("Sweep %s L%d %s", EnumToString(g_tf), g_lookback,
                                   (InpCondLogic == COND_ALL ? "ALL" : "ANY")));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| ATR semplice (media mobile del True Range) sull'array di rates    |
//+------------------------------------------------------------------+
void CalcATR(const MqlRates &rt[], double &atr[], const int period)
  {
   int n = ArraySize(rt);
   ArrayResize(atr, n);
   if(n <= 0)
      return;

   double tr[];
   ArrayResize(tr, n);

   for(int i = 0; i < n; i++)
     {
      if(i == 0)
         tr[i] = rt[0].high - rt[0].low;
      else
        {
         double pc = rt[i - 1].close;
         tr[i] = MathMax(rt[i].high - rt[i].low,
                         MathMax(MathAbs(rt[i].high - pc), MathAbs(rt[i].low - pc)));
        }
     }

   int    per = MathMax(1, period);
   double sum = 0.0;
   for(int i = 0; i < n; i++)
     {
      sum += tr[i];
      if(i >= per)
         sum -= tr[i - per];
      int cnt = MathMin(i + 1, per);
      atr[i] = sum / cnt;
     }
  }

//+------------------------------------------------------------------+
//| Rileva il pattern sulla barra j dell'array rates                  |
//| ritorna +1 = BUY, -1 = SELL, 0 = niente                           |
//| level = livello spazzato (min finestra per buy, max per sell)     |
//+------------------------------------------------------------------+
int DetectAt(const MqlRates &rt[], const int j, const double atr, double &level)
  {
   level = 0.0;
   if(j - g_lookback < 0)
      return(0);

   //--- finestra di riferimento: barre [j-g_lookback .. j-1]
   double loW = rt[j - 1].low;
   double hiW = rt[j - 1].high;
   for(int k = j - g_lookback; k <= j - 1; k++)
     {
      loW = MathMin(loW, rt[k].low);
      hiW = MathMax(hiW, rt[k].high);
     }

   double po = rt[j - 1].open;    // open candela immediatamente precedente
   double pc = rt[j - 1].close;   // close candela immediatamente precedente

   double o = rt[j].open, h = rt[j].high, l = rt[j].low, c = rt[j].close;
   double rng = h - l;
   if(rng <= 0.0)
      return(0);

   double minPen  = (InpMinSweepATR > 0.0 && atr > 0.0) ? InpMinSweepATR * atr : 0.0;
   double posLim  = InpMinClosePosPct / 100.0;

   //================= BUY =================
   bool okBuy = ((loW - l) > minPen);                                   // ha spazzato il minimo
   if(okBuy && InpRequireCloseBackIn) okBuy = (c > loW);                // rientro sopra il livello
   if(okBuy && InpRequireBodyDir)     okBuy = (c > o);                  // corpo rialzista
   if(okBuy && posLim > 0.0)          okBuy = ((c - l) / rng >= posLim);// chiusura in alto nel range
   if(okBuy)
     {
      int  nAct = 0, nOk = 0;
      if(InpUsePrevOpen)    { nAct++; if(c > po)  nOk++; }
      if(InpUsePrevClose)   { nAct++; if(c > pc)  nOk++; }
      if(InpUsePrevExtreme) { nAct++; if(c > hiW) nOk++; }
      okBuy = (InpCondLogic == COND_ALL) ? (nOk == nAct && nAct > 0) : (nOk > 0);
     }

   //================= SELL =================
   bool okSell = ((h - hiW) > minPen);                                    // ha spazzato il massimo
   if(okSell && InpRequireCloseBackIn) okSell = (c < hiW);
   if(okSell && InpRequireBodyDir)     okSell = (c < o);
   if(okSell && posLim > 0.0)          okSell = ((h - c) / rng >= posLim);
   if(okSell)
     {
      int  nAct = 0, nOk = 0;
      if(InpUsePrevOpen)    { nAct++; if(c < po)  nOk++; }
      if(InpUsePrevClose)   { nAct++; if(c < pc)  nOk++; }
      if(InpUsePrevExtreme) { nAct++; if(c < loW) nOk++; }
      okSell = (InpCondLogic == COND_ALL) ? (nOk == nAct && nAct > 0) : (nOk > 0);
     }

   //--- candela che spazza entrambi i lati e soddisfa entrambe le logiche: segnale ambiguo, scartato
   if(okBuy && okSell)
      return(0);

   if(okBuy)  { level = loW; return(1);  }
   if(okSell) { level = hiW; return(-1); }
   return(0);
  }

//+------------------------------------------------------------------+
//| Scansiona le barre del TF pattern a partire da tFrom e stampa i   |
//| segnali sui buffer del grafico corrente.                          |
//+------------------------------------------------------------------+
void ScanAndPlot(const datetime tFrom,
                 const int rates_total,
                 const int chartFirstIdx,
                 const datetime &time[],
                 const double &low[],
                 const double &high[],
                 const bool doAlerts)
  {
   MqlRates rt[];
   ArraySetAsSeries(rt, false);
   int copied = CopyRates(_Symbol, g_tf, tFrom, TimeCurrent(), rt);
   if(copied <= g_lookback)
      return;

   double atr[];
   CalcATR(rt, atr, InpATRPeriod);

   datetime now = TimeCurrent();

   for(int j = g_lookback; j < copied; j++)
     {
      //--- solo barre HTF gia' chiuse: nessun repaint
      datetime tClose = rt[j].time + g_tfSec;
      if(tClose > now)
         continue;

      double level = 0.0;
      int    sig   = DetectAt(rt, j, atr[j], level);
      if(sig == 0)
         continue;

      //--- mappatura sulla barra del grafico corrente
      datetime tAnchor = (InpAnchor == ANCHOR_TF_CLOSE) ? (tClose - 1) : tClose;
      if(tAnchor > now)
         continue;

      int sh = iBarShift(_Symbol, _Period, tAnchor, false);
      if(sh < 0)
         continue;

      int idx = rates_total - 1 - sh;
      if(idx < chartFirstIdx || idx >= rates_total)
         continue;

      double off = (InpArrowOffsetATR > 0.0 && atr[j] > 0.0) ? InpArrowOffsetATR * atr[j] : 0.0;

      BufSignal[idx] = (double)sig;
      BufLevel[idx]  = level;
      if(sig > 0)
         BufBuy[idx]  = low[idx]  - off;
      else
         BufSell[idx] = high[idx] + off;

      //--- alert una sola volta per barra HTF
      if(doAlerts && rt[j].time > g_lastAlertBar)
        {
         g_lastAlertBar = rt[j].time;
         string msg = StringFormat("%s %s | SWEEP %s @ %s | livello %s",
                                   _Symbol, EnumToString(g_tf),
                                   (sig > 0 ? "BUY" : "SELL"),
                                   DoubleToString(rt[j].close, _Digits),
                                   DoubleToString(level, _Digits));
         if(InpAlertPopup) Alert(msg);
         if(InpAlertPush)  SendNotification(msg);
         if(InpAlertEmail) SendMail("Sweep Reversal", msg);
        }
     }
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < g_lookback + 3)
      return(0);

   ArraySetAsSeries(time,  false);
   ArraySetAsSeries(open,  false);
   ArraySetAsSeries(high,  false);
   ArraySetAsSeries(low,   false);
   ArraySetAsSeries(close, false);

   bool full = (prev_calculated <= 0);
   int  start = full ? 0 : prev_calculated - 1;

   //--- azzera solo le barre nuove / quella ancora in formazione
   for(int i = start; i < rates_total; i++)
     {
      BufBuy[i]    = EMPTY_VALUE;
      BufSell[i]   = EMPTY_VALUE;
      BufSignal[i] = 0.0;
      BufLevel[i]  = 0.0;
     }

   int chartFirstIdx = MathMax(0, rates_total - MathMax(100, InpMaxBars));

   if(full)
     {
      //--- ricostruzione completa: nessun alert (evita il flood al primo load)
      datetime tFrom = time[chartFirstIdx] - (datetime)(g_tfSec * (g_lookback + InpATRPeriod + 5));
      ScanAndPlot(tFrom, rates_total, chartFirstIdx, time, low, high, false);

      //--- allinea il marcatore alert all'ultima barra HTF chiusa
      datetime lastHtf[];
      if(CopyTime(_Symbol, g_tf, 0, 2, lastHtf) == 2)
         g_lastAlertBar = (lastHtf[0] > lastHtf[1]) ? lastHtf[0] : lastHtf[1];
     }
   else
     {
      //--- aggiornamento incrementale: rivaluta solo le ultime barre HTF chiuse
      int      nBack = g_lookback + InpATRPeriod + 6;
      datetime tFrom = TimeCurrent() - (datetime)(g_tfSec * nBack);
      ScanAndPlot(tFrom, rates_total, chartFirstIdx, time, low, high, true);
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
