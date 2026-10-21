//+------------------------------------------------------------------+
//|                      SyntheticDelta_EA.mq5                       |
//|  EA basato sull'indicatore SyntheticDelta v2.1                   |
//|  Segnale sulla barra chiusa [1], ingresso all'apertura barra [0] |
//|  SL / TP / Trailing in multipli di ATR, lotto fisso              |
//+------------------------------------------------------------------+
#property copyright "SyntheticDelta EA"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>

//--- ================================================================
input group "=== TRADE ==="
input double InpLots            = 0.10;    // Lotto fisso
input ulong  InpMagic           = 21062026;// Magic number
input int    InpDeviation       = 20;      // Slippage max (punti)
input int    InpMaxSpreadPts    = 0;       // Spread max in punti (0 = disattivo)
input int    InpMaxPositions    = 0;       // Max posizioni contemporanee (0 = illimitate)
input bool   InpCloseOnOpp      = false;   // Segnale opposto: chiudi prima le posizioni contrarie
input string InpComment         = "SynDelta";

input group "=== INDICATORE: CORE ==="
input int    EmaPeriod          = 13;
input int    VolAvgPeriod       = 20;
input double SignalThreshold    = 0.15;

input group "=== INDICATORE: ATR ==="
input int    ATR_Period         = 14;      // Usato per SL/TP/trailing e prossimita' S/R

input group "=== INDICATORE: ADX ==="
input bool   UseADXFilter       = true;
input int    ADX_Period         = 14;
input double ADX_MinLevel       = 20.0;

input group "=== INDICATORE: SUPPORTO/RESISTENZA ==="
input bool   UseSRFilter        = true;
input int    SR_Lookback        = 15;
input double SR_Proximity       = 0.5;

input group "=== RISCHIO (multipli ATR) ==="
input double SL_ATR_Mult        = 1.5;     // Stop Loss
input double TP_ATR_Mult        = 3.0;     // Take Profit (0 = nessun TP)
input bool   UseTrailing        = true;
input double TrailStart_ATR     = 1.0;     // Profitto (in ATR) per attivare il trailing
input double TrailDist_ATR      = 1.0;     // Distanza trailing (in ATR)
input double TrailStep_ATR      = 0.1;     // Avanzamento minimo SL (in ATR)

input group "=== FILTRO ORARIO (ora SERVER del broker, ora di apertura della barra d'ingresso) ==="
input bool   InpH00 = true;  input bool InpH01 = true;  input bool InpH02 = true;  input bool InpH03 = true;
input bool   InpH04 = true;  input bool InpH05 = true;  input bool InpH06 = true;  input bool InpH07 = true;
input bool   InpH08 = true;  input bool InpH09 = true;  input bool InpH10 = true;  input bool InpH11 = true;
input bool   InpH12 = true;  input bool InpH13 = true;  input bool InpH14 = true;  input bool InpH15 = true;
input bool   InpH16 = true;  input bool InpH17 = true;  input bool InpH18 = true;  input bool InpH19 = true;
input bool   InpH20 = true;  input bool InpH21 = true;  input bool InpH22 = true;  input bool InpH23 = true;

//--- ================================================================
CTrade   Trade;
int      hEma = INVALID_HANDLE;
int      hAtr = INVALID_HANDLE;
int      hAdx = INVALID_HANDLE;
datetime g_lastBar = 0;
bool     g_hourOn[24];
double   g_atr     = 0.0;   // ATR dell'ultima barra chiusa (per il trailing)

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLots <= 0.0 || EmaPeriod < 1 || VolAvgPeriod < 1 || ATR_Period < 1 || SR_Lookback < 1)
     {
      Print("Parametri non validi");
      return INIT_PARAMETERS_INCORRECT;
     }

   hEma = iMA(_Symbol, _Period, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hAtr = iATR(_Symbol, _Period, ATR_Period);
   if(UseADXFilter)
      hAdx = iADX(_Symbol, _Period, ADX_Period);

   if(hEma == INVALID_HANDLE || hAtr == INVALID_HANDLE || (UseADXFilter && hAdx == INVALID_HANDLE))
     {
      Print("Errore creazione handle: ", GetLastError());
      return INIT_FAILED;
     }

   Trade.SetExpertMagicNumber(InpMagic);
   Trade.SetDeviationInPoints(InpDeviation);
   Trade.SetTypeFillingBySymbol(_Symbol);

   g_hourOn[0]  = InpH00; g_hourOn[1]  = InpH01; g_hourOn[2]  = InpH02; g_hourOn[3]  = InpH03;
   g_hourOn[4]  = InpH04; g_hourOn[5]  = InpH05; g_hourOn[6]  = InpH06; g_hourOn[7]  = InpH07;
   g_hourOn[8]  = InpH08; g_hourOn[9]  = InpH09; g_hourOn[10] = InpH10; g_hourOn[11] = InpH11;
   g_hourOn[12] = InpH12; g_hourOn[13] = InpH13; g_hourOn[14] = InpH14; g_hourOn[15] = InpH15;
   g_hourOn[16] = InpH16; g_hourOn[17] = InpH17; g_hourOn[18] = InpH18; g_hourOn[19] = InpH19;
   g_hourOn[20] = InpH20; g_hourOn[21] = InpH21; g_hourOn[22] = InpH22; g_hourOn[23] = InpH23;

   if(InpMaxPositions != 1 &&
      AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("ATTENZIONE: conto NON hedging, le posizioni nella stessa direzione vengono fuse in una sola.");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hEma != INVALID_HANDLE) IndicatorRelease(hEma);
   if(hAtr != INVALID_HANDLE) IndicatorRelease(hAtr);
   if(hAdx != INVALID_HANDLE) IndicatorRelease(hAdx);
  }

//+------------------------------------------------------------------+
//| Segnale sulla barra [1] (ultima chiusa). Ritorna +1 / -1 / 0.    |
//| Replica fedelmente la logica di SyntheticDelta v2.1.             |
//| Costo: 1 CopyRates + 3 CopyBuffer da 1 elemento, una volta/barra.|
//+------------------------------------------------------------------+
int GetSignal(double &atrOut)
  {
   double ema[1], atr[1];
   if(CopyBuffer(hEma, 0, 1, 1, ema) != 1) return 0;
   if(CopyBuffer(hAtr, 0, 1, 1, atr) != 1) return 0;
   atrOut = atr[0];
   if(atrOut <= 0.0) return 0;

   if(UseADXFilter)
     {
      double adx[1];
      if(CopyBuffer(hAdx, 0, 1, 1, adx) != 1) return 0;
      if(adx[0] < ADX_MinLevel) return 0;
     }

   // r[0] = barra segnale (shift 1); r[1..SR_Lookback] = barre precedenti
   int n = MathMax(VolAvgPeriod, SR_Lookback + 1);
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, _Period, 1, n, r) != n) return 0;

   double range = r[0].high - r[0].low;
   if(range <= 0.0) return 0;
   double tickVol = (double)r[0].tick_volume;
   if(tickVol <= 0.0) return 0;

   // Volume relativo (include la barra corrente, come l'indicatore)
   double volSum = 0.0;
   for(int j = 0; j < VolAvgPeriod; j++)
      volSum += (double)r[j].tick_volume;
   double volAvg    = volSum / VolAvgPeriod;
   double volWeight = (volAvg > 0.0) ? MathMin(tickVol / volAvg, 3.0) : 1.0;

   // Synthetic delta
   double fracBuy   = (r[0].close - r[0].low)  / range;
   double fracSell  = (r[0].high  - r[0].close) / range;
   double bullsNorm = (r[0].high - ema[0]) / range;
   double bearsNorm = (ema[0] - r[0].low)  / range;
   double delta     = (fracBuy * (1.0 + bullsNorm) - fracSell * (1.0 + bearsNorm)) * volWeight / 6.0;

   int sig = 0;
   if(delta >  SignalThreshold) sig =  1;
   else if(delta < -SignalThreshold) sig = -1;
   if(sig == 0) return 0;

   // Filtro S/R (livelli calcolati sulle SR_Lookback barre PRECEDENTI)
   if(UseSRFilter)
     {
      double res = r[1].high, sup = r[1].low;
      for(int k = 2; k <= SR_Lookback; k++)
        {
         if(r[k].high > res) res = r[k].high;
         if(r[k].low  < sup) sup = r[k].low;
        }
      double prox = atrOut * SR_Proximity;
      double c    = r[0].close;
      bool ok = (MathAbs(c - res) <= prox) || (MathAbs(c - sup) <= prox) || (c > res) || (c < sup);
      if(!ok) return 0;
     }
   return sig;
  }

//+------------------------------------------------------------------+
//| Seleziona la posizione i-esima solo se e' di questo EA/simbolo.  |
bool SelectMine(const int i)
  {
   ulong t = PositionGetTicket(i);
   if(t == 0) return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   return ((ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

int CountMyPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(SelectMine(i)) n++;
   return n;
  }

//--- Chiude le posizioni contrarie al segnale sig (+1 buy / -1 sell)
void CloseOpposite(const int sig)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!SelectMine(i)) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      bool opposite = (sig > 0 && type == POSITION_TYPE_SELL) || (sig < 0 && type == POSITION_TYPE_BUY);
      if(opposite && !Trade.PositionClose((ulong)PositionGetInteger(POSITION_TICKET)))
         PrintFormat("Chiusura fallita: %s", Trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
void OpenTrade(const int sig, const double atr)
  {
   if(InpMaxSpreadPts > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts)
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   double slDist = MathMax(atr * SL_ATR_Mult, minDist);
   double tpDist = (TP_ATR_Mult > 0.0) ? MathMax(atr * TP_ATR_Mult, minDist) : 0.0;

   double lots = NormalizeLots(InpLots);
   bool   ok;
   if(sig > 0)
     {
      double sl = NormalizeDouble(ask - slDist, _Digits);
      double tp = (tpDist > 0.0) ? NormalizeDouble(ask + tpDist, _Digits) : 0.0;
      ok = Trade.Buy(lots, _Symbol, 0.0, sl, tp, InpComment);
     }
   else
     {
      double sl = NormalizeDouble(bid + slDist, _Digits);
      double tp = (tpDist > 0.0) ? NormalizeDouble(bid - tpDist, _Digits) : 0.0;
      ok = Trade.Sell(lots, _Symbol, 0.0, sl, tp, InpComment);
     }
   if(!ok)
      PrintFormat("Ordine fallito: retcode=%u (%s)", Trade.ResultRetcode(), Trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step > 0.0) lots = MathFloor(lots / step + 1e-9) * step;
   return MathMin(MathMax(lots, vmin), vmax);
  }

//+------------------------------------------------------------------+
//| Trailing ATR: eseguito a ogni tick ma con ATR cache (O(1))       |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   if(!UseTrailing || g_atr <= 0.0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLvl   = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freezeLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double guard = MathMax(stopLvl, freezeLvl);
   double step  = g_atr * TrailStep_ATR;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!SelectMine(i)) continue;

      ulong  ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      long   type   = PositionGetInteger(POSITION_TYPE);
      double open   = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
        {
         if(bid - open < g_atr * TrailStart_ATR) continue;
         double newSL = NormalizeDouble(bid - g_atr * TrailDist_ATR, _Digits);
         if((curSL == 0.0 || newSL > curSL + step) && newSL < bid - guard)
            Trade.PositionModify(ticket, newSL, tp);
        }
      else
        {
         if(open - ask < g_atr * TrailStart_ATR) continue;
         double newSL = NormalizeDouble(ask + g_atr * TrailDist_ATR, _Digits);
         if((curSL == 0.0 || newSL < curSL - step) && newSL > ask + guard)
            Trade.PositionModify(ticket, newSL, tp);
        }
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   ManageTrailing();

   // Logica di segnale solo alla prima tick di una nuova barra
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBar) return;

   // Attendi che gli indicatori siano pronti (riprova al tick successivo)
   if(BarsCalculated(hEma) < 2 || BarsCalculated(hAtr) < 2) return;
   if(UseADXFilter && BarsCalculated(hAdx) < 2) return;
   if(Bars(_Symbol, _Period) < MathMax(MathMax(VolAvgPeriod, SR_Lookback + 1), MathMax(EmaPeriod, ATR_Period)) + 3) return;

   double atr = 0.0;
   int sig = GetSignal(atr);
   if(atr > 0.0) g_atr = atr;
   g_lastBar = barTime;
   if(sig == 0) return;

   // Filtro orario (ora server della barra d'ingresso)
   MqlDateTime dt;
   TimeToStruct(barTime, dt);
   if(!g_hourOn[dt.hour]) return;

   if(InpCloseOnOpp) CloseOpposite(sig);
   if(InpMaxPositions > 0 && CountMyPositions() >= InpMaxPositions) return;

   OpenTrade(sig, atr);
  }
//+------------------------------------------------------------------+
