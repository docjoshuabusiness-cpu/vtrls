//+------------------------------------------------------------------+
//|                                                    SD_Core.mqh   |
//|  Logica di segnale di SyntheticDelta_EA_v1.13 riscritta su array |
//|  ordinati dal piu' vecchio al piu' recente (non-series), cosi'   |
//|  puo' essere riusata da script di ricerca su storico completo.   |
//|                                                                  |
//|  Replica fedelmente (senza filtri ADX / S/R / regime vol):       |
//|   - Synthetic Delta  (GetDeltaDirection)                          |
//|   - Expansion Candle (GetExpansionDirection, con stato pending)   |
//|   - CombineDirections (DELTA / EXP / AND / OR)                    |
//|   - conteggio della raffica del Sequence Filter (g_runCount)      |
//|                                                                  |
//|  NOTA: l'EA di produzione NON include questo file. Se si cambia  |
//|  la logica nell'EA va cambiata anche qui, altrimenti lo studio   |
//|  misura un segnale diverso da quello operato.                    |
//+------------------------------------------------------------------+
#property copyright "SignalLab"

#ifndef SD_CORE_MQH
#define SD_CORE_MQH

#define SD_MODE_DELTA 0
#define SD_MODE_EXP   1
#define SD_MODE_AND   2
#define SD_MODE_OR    3
#define SD_MODE_ADDED 4   // solo i segnali che l'Expansion AGGIUNGE a Delta (Expansion accesa, Delta spento)

struct SDParams
  {
   int    mode;              // SD_MODE_*
   int    emaPeriod;         // EmaPeriod dell'EA
   int    volAvgPeriod;      // VolAvgPeriod dell'EA
   double threshold;         // SignalThreshold dell'EA
   int    atrPeriod;         // ATR_Period dell'EA (solo validita' dato, come nell'EA)
   int    expAtrPeriod;      // Inp_ExpATRPeriod
   double expThreshold;      // Inp_ExpThreshold (TR/ATR)
   int    expConfirmOffset;  // Inp_ExpConfirmOffset
   int    runGapBars;        // Inp_RunGapBars (0 = la raffica si chiude solo con segnale opposto)
  };

//+------------------------------------------------------------------+
//| EMA sulla chiusura, seed = prima chiusura (come iMA MODE_EMA)    |
//+------------------------------------------------------------------+
void SD_Ema(const MqlRates &r[], const int n, const int period, double &ema[])
  {
   ArrayResize(ema, n);
   if(n <= 0) return;
   double a = 2.0 / (period + 1.0);
   ema[0] = r[0].close;
   for(int i = 1; i < n; i++)
      ema[i] = ema[i-1] + a * (r[i].close - ema[i-1]);
  }

//+------------------------------------------------------------------+
//| ATR come l'indicatore standard di MT5: media semplice del TR     |
//| su 'period' barre che includono la barra stessa. Zero prima di   |
//| avere 'period' valori.                                           |
//+------------------------------------------------------------------+
void SD_Atr(const MqlRates &r[], const int n, const int period, double &atr[])
  {
   ArrayResize(atr, n);
   ArrayInitialize(atr, 0.0);
   if(period < 1 || n <= period + 1) return;
   double trv[];
   ArrayResize(trv, n);
   trv[0] = 0.0;
   for(int i = 1; i < n; i++)
      trv[i] = MathMax(r[i].high, r[i-1].close) - MathMin(r[i].low, r[i-1].close);
   double s = 0.0;
   for(int i = 1; i <= period; i++) s += trv[i];
   atr[period] = s / period;
   for(int i = period + 1; i < n; i++)
      atr[i] = atr[i-1] + (trv[i] - trv[i-period]) / period;
  }

//+------------------------------------------------------------------+
//| STATO DI VOLATILITA' - stessa logica dell'indicatore              |
//| VolatilityStateIndicator_Ferro (verificata barra per barra):      |
//|   TR/ATR della barra (ATR = SMA del TR, include la barra)         |
//|   volatilita' composita = (ATR% + Parkinson)/2, EMA di smoothing  |
//|   percentile della composita sulle ultime 'lookback' barre        |
//| code = (cls << 3) | (regime << 1) | rising                        |
//|   cls   : 0 compressione (TR/ATR < compTh), 1 normale,            |
//|           2 espansione (TR/ATR > expTh)                           |
//|   regime: 0 LOW, 1 NORMAL, 2 HIGH, 3 EXTREME                      |
//|   rising: 1 se il percentile e' salito rispetto alla barra prima  |
//+------------------------------------------------------------------+
struct SDVolParams
  {
   int    atrLen;
   int    lookback;
   int    emaSmooth;
   double expTh;
   double compTh;
   int    lowTh;
   int    highTh;
   int    extremeTh;
  };

void SD_VolState(const MqlRates &r[], const int n, const SDVolParams &p, const double pt, uchar &code[])
  {
   ArrayResize(code, n);
   ArrayInitialize(code, 0);
   if(n < p.atrLen + p.lookback + p.emaSmooth + 5) return;

   double atr[];
   SD_Atr(r, n, p.atrLen, atr);

   double pv[], sm[], pct[];
   ArrayResize(pv, n);
   ArrayResize(sm, n);  ArrayInitialize(sm, 0.0);
   ArrayResize(pct, n); ArrayInitialize(pct, 50.0);
   const double parkF = 1.0 / (4.0 * MathLog(2.0));
   const double a     = 2.0 / (p.emaSmooth + 1.0);
   double win = 0.0;      // somma mobile della varianza di Parkinson su atrLen barre
   for(int i = 0; i < n; i++)
     {
      pv[i] = (r[i].low > 0.0 && r[i].high > 0.0) ? parkF * MathPow(MathLog(r[i].high / r[i].low), 2) : 0.0;
      win += pv[i];
      if(i >= p.atrLen) win -= pv[i - p.atrLen];
      if(win < 0.0) win = 0.0;     // l'arrotondamento della somma mobile non deve dare radici negative
      if(i < p.atrLen) continue;
      int    cnt     = MathMin(i + 1, p.atrLen);
      double parkVol = MathSqrt(win / cnt) * 100.0;
      double av      = (atr[i] > 0.0) ? atr[i] : pt;
      double comp    = ((av / r[i].close) * 100.0 + parkVol) / 2.0;
      sm[i] = (i == p.atrLen) ? comp : sm[i-1] + a * (comp - sm[i-1]);
     }
   for(int i = p.lookback; i < n; i++)
     {
      if(i < p.atrLen) continue;
      double cur = sm[i];
      int lower = 0;
      for(int k = i - p.lookback; k < i; k++) if(sm[k] <= cur) lower++;
      pct[i] = 100.0 * lower / p.lookback;
     }
   for(int i = 0; i < n; i++)
     {
      if(i < p.lookback || i < p.atrLen || i < 1) { code[i] = (uchar)((1 << 3) | (1 << 1)); continue; }
      double tr    = MathMax(r[i].high, r[i-1].close) - MathMin(r[i].low, r[i-1].close);
      double av    = (atr[i] > 0.0) ? atr[i] : pt;
      double ratio = tr / av;
      int cls  = (ratio > p.expTh) ? 2 : ((ratio < p.compTh) ? 0 : 1);
      int reg  = (pct[i] >= p.extremeTh) ? 3 : ((pct[i] >= p.highTh) ? 2 : ((pct[i] >= p.lowTh) ? 1 : 0));
      int rise = (i > p.lookback && pct[i] > pct[i-1]) ? 1 : 0;
      code[i] = (uchar)((cls << 3) | (reg << 1) | rise);
     }
  }

//+------------------------------------------------------------------+
//| INTENSITA' DELLA CANDELA: classe del rapporto TR/ATR (ATR = SMA   |
//| del TR su 'atrLen' barre, barra inclusa) rispetto a 5 soglie      |
//| crescenti 'edge': 0 = sotto la prima soglia ... 5 = sopra         |
//| l'ultima. 255 = ATR non ancora disponibile.                       |
//+------------------------------------------------------------------+
void SD_IntensityBins(const MqlRates &r[], const int n, const int atrLen, const double &edge[], uchar &bin[])
  {
   ArrayResize(bin, n);
   ArrayInitialize(bin, 255);
   if(atrLen < 1 || n < atrLen + 2) return;
   double atr[];
   SD_Atr(r, n, atrLen, atr);
   for(int i = MathMax(1, atrLen); i < n; i++)
     {
      if(atr[i] <= 0.0) continue;
      double tr    = MathMax(r[i].high, r[i-1].close) - MathMin(r[i].low, r[i-1].close);
      double ratio = tr / atr[i];
      int    b     = 0;
      while(b < 5 && ratio >= edge[b]) b++;
      bin[i] = (uchar)b;
     }
  }

//+------------------------------------------------------------------+
//| SD_BuildSignals                                                   |
//| Per ogni barra CHIUSA i (0..n-2) calcola la direzione del        |
//| segnale (+1/-1/0) e la posizione nella raffica (burst >= 1).      |
//| Restituisce l'indice di warm-up: le barre sotto non sono valide.  |
//+------------------------------------------------------------------+
int SD_BuildSignals(const MqlRates &r[], const int n, const SDParams &p,
                    char &dir[], uchar &burst[])
  {
   ArrayResize(dir, n);
   ArrayInitialize(dir, 0);
   ArrayResize(burst, n);
   ArrayInitialize(burst, 0);

   int warm = MathMax(MathMax(p.emaPeriod, p.volAvgPeriod),
                      MathMax(p.atrPeriod, p.expAtrPeriod)) + 3;
   if(n < warm + 3) return warm;

   const bool useD = (p.mode != SD_MODE_EXP);
   const bool useE = (p.mode != SD_MODE_DELTA);

   double ema[], atrE[];
   if(useD) SD_Ema(r, n, p.emaPeriod, ema);
   if(useE) SD_Atr(r, n, p.expAtrPeriod, atrE);

   double vsum    = 0.0;
   bool   pending = false;
   int    pIdx    = -1;
   int    runDir  = 0, runCount = 0, gapBars = 0;

   for(int i = 0; i < n - 1; i++)
     {
      //--- somma mobile del tick_volume sulle ultime volAvgPeriod barre (inclusa i)
      vsum += (double)r[i].tick_volume;
      if(i >= p.volAvgPeriod) vsum -= (double)r[i - p.volAvgPeriod].tick_volume;
      if(i < warm) continue;

      //--- motore Synthetic Delta
      int dD = 0;
      if(useD)
        {
         double range = r[i].high - r[i].low;
         double tv    = (double)r[i].tick_volume;
         if(range > 0.0 && tv > 0.0 && i >= p.atrPeriod)
           {
            double fracBuy  = (r[i].close - r[i].low)   / range;
            double fracSell = (r[i].high  - r[i].close) / range;
            double bulls    = (r[i].high - ema[i]) / range;
            double bears    = (ema[i] - r[i].low)  / range;
            int    cnt      = MathMin(i + 1, p.volAvgPeriod);
            double volAvg   = (cnt > 0) ? vsum / cnt : tv;
            double volW     = (volAvg > 0.0) ? MathMin(tv / volAvg, 3.0) : 1.0;
            double nd = (fracBuy  * (1.0 + bulls) * volW
                       - fracSell * (1.0 + bears) * volW) / 6.0;
            if(nd >  p.threshold)      dD =  1;
            else if(nd < -p.threshold) dD = -1;
           }
        }

      //--- motore Expansion Candle (macchina a stati identica all'EA)
      int dE = 0;
      if(useE)
        {
         bool handled = false;
         if(pending)
           {
            // shift dell'espansione visto dalla barra in formazione (i+1), come iBarShift nell'EA
            int shift = (i + 1) - pIdx;
            handled = true;
            if(shift > p.expConfirmOffset + 1)
               pending = false;                       // gap: annulla
            else if(shift < p.expConfirmOffset + 1)
              { /* attesa conferma */ }
            else
              {
               pending = false;
               if(r[i].close > r[i].open)      dE =  1;
               else if(r[i].close < r[i].open) dE = -1;
              }
           }
         if(!handled)
           {
            double a = atrE[i];
            if(a > 0.0)
              {
               double tr = MathMax(r[i].high, r[i-1].close) - MathMin(r[i].low, r[i-1].close);
               if(tr / a > p.expThreshold)
                 {
                  if(p.expConfirmOffset == 0)
                    {
                     if(r[i].close > r[i].open)      dE =  1;
                     else if(r[i].close < r[i].open) dE = -1;
                    }
                  else
                    { pending = true; pIdx = i; }
                 }
              }
           }
        }

      //--- combinazione
      int d = 0;
      int dRun = -99;      // direzione che alimenta la raffica (coincide con d tranne che nel modo ADDED)
      switch(p.mode)
        {
         case SD_MODE_DELTA: d = dD; break;
         case SD_MODE_EXP:   d = dE; break;
         case SD_MODE_AND:   d = (dD != 0 && dD == dE) ? dD : 0; break;
         case SD_MODE_ADDED:
            d    = (dD == 0) ? dE : 0;     // segnale emesso: solo quelli che l'Expansion aggiunge
            dRun = (dD != 0 && dE != 0 && dD != dE) ? 0 : ((dD != 0) ? dD : dE);   // la raffica segue il flusso OR dell'EA
            break;
         case SD_MODE_OR:
            if(dD != 0 && dE != 0 && dD != dE) d = 0;
            else d = (dD != 0) ? dD : dE;
            break;
        }

      //--- raffica (identico a ApplySequenceFilter, senza filtri a monte)
      if(dRun == -99) dRun = d;
      if(dRun == 0)
        {
         gapBars++;
         if(p.runGapBars > 0 && gapBars >= p.runGapBars) { runDir = 0; runCount = 0; }
        }
      else
        {
         gapBars = 0;
         if(dRun == runDir) runCount++;
         else { runDir = dRun; runCount = 1; }
        }
      if(d != 0)
        {
         dir[i]   = (char)d;
         burst[i] = (uchar)MathMin(runCount, 255);
        }
     }
   return warm;
  }

#endif
