//+------------------------------------------------------------------+
//|                                          SyntheticDeltaLab.mq5   |
//|   Laboratorio di analisi segnali SyntheticDelta v2.1             |
//|   - Replica esatta della logica dell'indicatore                  |
//|   - Analisi MFE/MAE post-segnale (first-touch barrier)           |
//|   - Griglia SL x TP completa in un solo passaggio                |
//|   - Report HTML: ora, minuto, giorno, heatmap SL/TP              |
//+------------------------------------------------------------------+
#property copyright "SyntheticDelta Lab"
#property version   "1.00"
#property script_show_inputs
#property strict

//--- ================================================================
input group "=== PERIODO DI ANALISI ==="
input datetime InpFrom            = D'2015.01.01 00:00';
input datetime InpTo              = D'2026.07.15 00:00';
input int      InpTimeOffsetHours = 0;      // shift ore server -> fuso desiderato

input group "=== PARAMETRI INDICATORE (identici a SyntheticDelta) ==="
input int    EmaPeriod        = 13;
input int    VolAvgPeriod     = 20;
input double SignalThreshold  = 0.15;
input bool   UseADXFilter     = true;
input int    ADX_Period       = 14;
input double ADX_MinLevel     = 20.0;
input bool   UseSRFilter      = true;
input int    SR_Lookback      = 15;
input double SR_Proximity     = 0.5;
input int    ATR_Period       = 14;

input group "=== SIMULAZIONE TRADE ==="
input int    InpEntryDelayBars = 1;      // 1 = entra all'open della barra successiva (no look-ahead)
input int    InpMaxHoldBars    = 1440;   // orizzonte massimo (M1: 1440 = 24h)
input double InpCostPoints     = 0;      // 0 = usa lo spread reale della barra; >0 = costo fisso in punti
input double InpExtraCostPts   = 0;      // commissione/slippage extra in punti (round turn)
input bool   InpOnePosAtTime   = false;  // true = scarta segnali sovrapposti al trade aperto
input int    InpCooldownBars   = 0;      // scarta un segnale se ne e' gia' uscito uno da meno di N barre (stessa direzione)

input group "=== MODALITA GRIGLIA ==="
input bool   InpGridFromATR = true;   // true = griglia in multipli di ATR mediano (auto-scala su ogni simbolo)
input double InpSLatrMin    = 0.5;    // SL minimo in multipli di ATR
input double InpSLatrMax    = 6.0;    // SL massimo in multipli di ATR
input int    InpSLatrSteps  = 10;
input double InpTPatrMin    = 0.5;    // TP minimo in multipli di ATR
input double InpTPatrMax    = 10.0;   // TP massimo in multipli di ATR
input int    InpTPatrSteps  = 10;

input group "=== GRIGLIA STOP LOSS (punti, solo se InpGridFromATR=false) ==="
input int    InpSLMin  = 200;
input int    InpSLMax  = 2000;
input int    InpSLStep = 200;

input group "=== GRIGLIA TAKE PROFIT (punti, solo se InpGridFromATR=false) ==="
input int    InpTPMin  = 250;
input int    InpTPMax  = 2500;
input int    InpTPStep = 250;

input group "=== REPORT ==="
input int    InpMinTradesPerBucket = 30;   // sotto questa soglia il bucket e' rumore
input bool   InpExportCSV          = true; // esporta anche il dettaglio segnali
input string InpReportName         = "SyntheticDeltaLab";

//--- ================================================================
#define BIG_INT 2147483647

struct SignalRec
  {
   datetime t;          // ora del segnale (barra di calcolo)
   datetime tEntry;     // ora di ingresso
   int      dir;        // +1 buy, -1 sell
   double   entry;      // prezzo effettivo di ingresso (costi inclusi)
   double   mfe;        // max favorable excursion (punti)
   double   mae;        // max adverse excursion (punti)
   double   timeoutPts; // P/L in punti alla scadenza dell'orizzonte
   int      barsToMFE;
   double   delta;      // normalizedDelta al segnale
  };

SignalRec g_sig[];
int       g_tFav[];   // [s*nTP + j] barra di primo tocco livello TP j
int       g_tAdv[];   // [s*nSL + i] barra di primo tocco livello SL i
int       g_slLev[];
int       g_tpLev[];
int       g_nSL = 0, g_nTP = 0, g_nSig = 0;

MqlRates  g_r[];
double    g_ema[], g_atr[], g_adx[];
int       g_bars = 0;
double    g_pt;
double    g_atrMedPts = 0;   // ATR mediano in punti sul periodo analizzato
double    g_ptValue   = 0;   // valore di 1 punto per 1 lotto, in valuta conto

//--- prototipi
void   BuildGrids();
void   ComputeMedianATR();
void   ComputePointValue();
void   WriteReport(int bi, int bj);
void   WriteCSV();
void   ComboStats(int iSL, int jTP, double &net, double &pf, double &wr, double &expc, double &maxDD);
double Outcome(int s, int iSL, int jTP);

//+------------------------------------------------------------------+
bool WaitHandle(int h, string name)
  {
   if(h == INVALID_HANDLE) { Print("Handle non valido: ", name); return false; }
   for(int k = 0; k < 200; k++)
     {
      if(BarsCalculated(h) >= g_bars) return true;
      Sleep(50);
     }
   Print("Timeout calcolo indicatore: ", name, " (", BarsCalculated(h), "/", g_bars, ")");
   return false;
  }

//+------------------------------------------------------------------+
bool CopyChunked(int h, int buf, int total, double &dst[])
  {
   ArrayResize(dst, total);
   ArraySetAsSeries(dst, false);
   int chunk = 100000, done = 0;
   double tmp[];
   ArraySetAsSeries(tmp, false);
   while(done < total)
     {
      int n = MathMin(chunk, total - done);
      // start_pos conta dalla barra corrente all'indietro
      int startPos = total - done - n;
      int got = CopyBuffer(h, buf, startPos, n, tmp);
      if(got <= 0) { Print("CopyBuffer fallita: ", GetLastError()); return false; }
      for(int k = 0; k < got; k++) dst[done + k] = tmp[k];
      done += got;
     }
   return true;
  }

//+------------------------------------------------------------------+
void AddLevel(int &arr[], int &n, int v)
  {
   if(v < 1) v = 1;
   if(n > 0 && arr[n-1] >= v) return;   // scarta duplicati/non crescenti
   ArrayResize(arr, n + 1);
   arr[n++] = v;
  }

//+------------------------------------------------------------------+
void BuildGrids()
  {
   if(InpGridFromATR && g_atrMedPts > 0)
     {
      int nS = MathMax(InpSLatrSteps, 2), nT = MathMax(InpTPatrSteps, 2);
      for(int k = 0; k < nS; k++)
        {
         double mult = InpSLatrMin + (InpSLatrMax - InpSLatrMin) * k / (nS - 1.0);
         AddLevel(g_slLev, g_nSL, (int)MathRound(mult * g_atrMedPts));
        }
      for(int k = 0; k < nT; k++)
        {
         double mult = InpTPatrMin + (InpTPatrMax - InpTPatrMin) * k / (nT - 1.0);
         AddLevel(g_tpLev, g_nTP, (int)MathRound(mult * g_atrMedPts));
        }
     }
   else
     {
      for(int v = InpSLMin; v <= InpSLMax; v += InpSLStep) AddLevel(g_slLev, g_nSL, v);
      for(int v = InpTPMin; v <= InpTPMax; v += InpTPStep) AddLevel(g_tpLev, g_nTP, v);
     }
  }

//+------------------------------------------------------------------+
//| ATR mediano in punti sulla finestra di analisi                   |
//+------------------------------------------------------------------+
void ComputeMedianATR()
  {
   double tmp[]; int n = 0;
   ArrayResize(tmp, g_bars);
   for(int i = 0; i < g_bars; i++)
     {
      if(g_r[i].time < InpFrom || g_r[i].time > InpTo) continue;
      if(g_atr[i] <= 0) continue;
      tmp[n++] = g_atr[i] / g_pt;
     }
   if(n == 0) { g_atrMedPts = 0; return; }
   ArrayResize(tmp, n);
   ArraySort(tmp);
   g_atrMedPts = (n % 2) ? tmp[n/2] : 0.5 * (tmp[n/2 - 1] + tmp[n/2]);
  }

//+------------------------------------------------------------------+
//| Valore in valuta conto di 1 punto per 1 lotto                    |
//+------------------------------------------------------------------+
void ComputePointValue()
  {
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_ptValue = (tickSize > 0) ? tickVal * (g_pt / tickSize) : 0.0;
  }

//+------------------------------------------------------------------+
//| Replica esatta della logica dell'indicatore su barra i           |
//| ritorna 0 = nessun segnale, +1 = buy, -1 = sell                  |
//+------------------------------------------------------------------+
int EvalSignal(int i, double &outDelta)
  {
   outDelta = 0.0;
   double currentATR = g_atr[i];
   if(currentATR <= 0.0) return 0;

   double range = g_r[i].high - g_r[i].low;
   if(range <= 0.0) return 0;

   double tickVol = (double)g_r[i].tick_volume;
   if(tickVol <= 0.0) return 0;

   double ema = g_ema[i];

   double fracBuy  = (g_r[i].close - g_r[i].low)  / range;
   double fracSell = (g_r[i].high  - g_r[i].close) / range;

   double bullsNorm = (g_r[i].high - ema) / range;
   double bearsNorm = (ema - g_r[i].low)  / range;

   double volSum = 0.0; int volCount = 0;
   for(int j = i; j > i - VolAvgPeriod && j >= 0; j--)
     { volSum += (double)g_r[j].tick_volume; volCount++; }
   double volAvg    = (volCount > 0) ? volSum / volCount : tickVol;
   double volWeight = (volAvg > 0.0) ? tickVol / volAvg : 1.0;
   volWeight = MathMin(volWeight, 3.0);

   double bullsStrength = fracBuy  * (1.0 + bullsNorm) * volWeight;
   double bearsStrength = fracSell * (1.0 + bearsNorm) * volWeight;
   double normalizedDelta = (bullsStrength - bearsStrength) / 6.0;
   outDelta = normalizedDelta;

   if(UseADXFilter && g_adx[i] < ADX_MinLevel) return 0;

   if(UseSRFilter && i >= SR_Lookback)
     {
      double resistance = -DBL_MAX, support = DBL_MAX;
      for(int j = i - SR_Lookback; j < i; j++)
        {
         if(g_r[j].high > resistance) resistance = g_r[j].high;
         if(g_r[j].low  < support)    support    = g_r[j].low;
        }
      double prox = currentATR * SR_Proximity;
      bool nearR  = (MathAbs(g_r[i].close - resistance) <= prox);
      bool nearS  = (MathAbs(g_r[i].close - support)    <= prox);
      bool aboveR = (g_r[i].close > resistance);
      bool belowS = (g_r[i].close < support);
      if(!(nearR || nearS || aboveR || belowS)) return 0;
     }

   if(normalizedDelta >  SignalThreshold) return  1;
   if(normalizedDelta < -SignalThreshold) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Percorso forward: first-touch di tutti i livelli SL e TP         |
//+------------------------------------------------------------------+
void WalkForward(int sIdx, int entryBar, int dir, double entryEff)
  {
   int base_f = sIdx * g_nTP;
   int base_a = sIdx * g_nSL;
   for(int j = 0; j < g_nTP; j++) g_tFav[base_f + j] = BIG_INT;
   for(int j = 0; j < g_nSL; j++) g_tAdv[base_a + j] = BIG_INT;

   double mfe = 0.0, mae = 0.0;
   int pf = 0, pa = 0, lastBar = entryBar, barsToMFE = 0;

   int endBar = MathMin(entryBar + InpMaxHoldBars, g_bars - 1);
   for(int k = entryBar; k <= endBar; k++)
     {
      double fav, adv;
      if(dir > 0)
        { fav = (g_r[k].high - entryEff) / g_pt; adv = (entryEff - g_r[k].low)  / g_pt; }
      else
        { fav = (entryEff - g_r[k].low)  / g_pt; adv = (g_r[k].high - entryEff) / g_pt; }

      if(fav > mfe) { mfe = fav; barsToMFE = k - entryBar; }
      if(adv > mae) mae = adv;

      while(pf < g_nTP && mfe >= (double)g_tpLev[pf]) { g_tFav[base_f + pf] = k - entryBar; pf++; }
      while(pa < g_nSL && mae >= (double)g_slLev[pa]) { g_tAdv[base_a + pa] = k - entryBar; pa++; }

      lastBar = k;
      if(pf >= g_nTP && pa >= g_nSL) break;
     }

   g_sig[sIdx].mfe        = mfe;
   g_sig[sIdx].mae        = mae;
   g_sig[sIdx].barsToMFE  = barsToMFE;
   g_sig[sIdx].timeoutPts = (dir > 0) ? (g_r[lastBar].close - entryEff) / g_pt
                                      : (entryEff - g_r[lastBar].close) / g_pt;
  }

//+------------------------------------------------------------------+
//| Esito di un segnale per una combinazione (SL i, TP j)            |
//| Tie-break pessimista: se SL e TP toccati nella stessa barra -> SL|
//+------------------------------------------------------------------+
double Outcome(int s, int iSL, int jTP)
  {
   int tf = g_tFav[s * g_nTP + jTP];
   int ta = g_tAdv[s * g_nSL + iSL];
   if(tf == BIG_INT && ta == BIG_INT) return g_sig[s].timeoutPts;
   if(ta <= tf) return -(double)g_slLev[iSL];
   return (double)g_tpLev[jTP];
  }

//+------------------------------------------------------------------+
void ComboStats(int iSL, int jTP, double &net, double &pf, double &wr, double &expc, double &maxDD)
  {
   double gp = 0, gl = 0, eq = 0, peak = 0;
   int wins = 0;
   net = 0; maxDD = 0;
   for(int s = 0; s < g_nSig; s++)
     {
      double p = Outcome(s, iSL, jTP);
      net += p;
      if(p > 0) { gp += p; wins++; } else gl += -p;
      eq += p;
      if(eq > peak) peak = eq;
      if(peak - eq > maxDD) maxDD = peak - eq;
     }
   pf   = (gl > 0) ? gp / gl : (gp > 0 ? 999.0 : 0.0);
   wr   = (g_nSig > 0) ? 100.0 * wins / g_nSig : 0.0;
   expc = (g_nSig > 0) ? net / g_nSig : 0.0;
  }

//+------------------------------------------------------------------+
string HeatColor(double v, double vmin, double vmax)
  {
   if(vmax - vmin < 1e-9) return "#2b2b2b";
   int r, g, b;
   if(v >= 0) { double u = (vmax > 0) ? v / vmax : 0; r = (int)(20 + 20*u); g = (int)(60 + 150*u); b = (int)(40 + 30*u); }
   else       { double u = (vmin < 0) ? v / vmin : 0; r = (int)(60 + 150*u); g = (int)(20 + 20*u); b = (int)(30 + 20*u); }
   return StringFormat("#%02x%02x%02x", r, g, b);
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   g_pt = _Point;
   if(_Period != PERIOD_M1)
      Print("ATTENZIONE: timeframe corrente ", EnumToString((ENUM_TIMEFRAMES)_Period),
            " - lo studio e' pensato per M1.");

//--- dati
   ArraySetAsSeries(g_r, false);
   g_bars = CopyRates(_Symbol, _Period, 0, TerminalInfoInteger(TERMINAL_MAXBARS), g_r);
   if(g_bars <= 0) { Print("CopyRates fallita: ", GetLastError()); return; }
   Print("Barre caricate: ", g_bars, " da ", g_r[0].time, " a ", g_r[g_bars-1].time);

   int hEma = iMA(_Symbol, _Period, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   int hAtr = iATR(_Symbol, _Period, ATR_Period);
   int hAdx = UseADXFilter ? iADX(_Symbol, _Period, ADX_Period) : INVALID_HANDLE;

   if(!WaitHandle(hEma, "EMA")) return;
   if(!WaitHandle(hAtr, "ATR")) return;
   if(UseADXFilter && !WaitHandle(hAdx, "ADX")) return;

   if(!CopyChunked(hEma, 0, g_bars, g_ema)) return;
   if(!CopyChunked(hAtr, 0, g_bars, g_atr)) return;
   if(UseADXFilter) { if(!CopyChunked(hAdx, 0, g_bars, g_adx)) return; }
   else { ArrayResize(g_adx, g_bars); ArrayInitialize(g_adx, 100.0); }

//--- griglia auto-scalante sulla volatilita' dello strumento
   ComputeMedianATR();
   ComputePointValue();
   BuildGrids();
   Print("--- ", _Symbol, " | Digits=", _Digits, " | Point=", DoubleToString(g_pt, 8),
         " | 1 pt x 1 lotto = ", DoubleToString(g_ptValue, 4), " ", AccountInfoString(ACCOUNT_CURRENCY));
   Print("ATR(", ATR_Period, ") M1 mediano = ", DoubleToString(g_atrMedPts, 1), " punti = ",
         DoubleToString(g_atrMedPts * g_pt, _Digits), " in prezzo");
   string sSL = "", sTP = "";
   for(int k = 0; k < g_nSL; k++) sSL += IntegerToString(g_slLev[k]) + " ";
   for(int k = 0; k < g_nTP; k++) sTP += IntegerToString(g_tpLev[k]) + " ";
   Print("Griglia SL (pt): ", sSL);
   Print("Griglia TP (pt): ", sTP);
   Print("Combinazioni: ", g_nSL * g_nTP);

//--- scansione segnali
   int minBars = MathMax(MathMax(EmaPeriod, VolAvgPeriod), MathMax(ATR_Period, SR_Lookback)) + 2;
   int reserve = g_bars / 4 + 16;
   ArrayResize(g_sig, reserve);
   ArrayResize(g_tFav, reserve * g_nTP);
   ArrayResize(g_tAdv, reserve * g_nSL);

   datetime busyUntil = 0;
   int lastBarBuy = -1000000, lastBarSell = -1000000;
   uint t0 = GetTickCount();

   for(int i = minBars; i < g_bars - InpEntryDelayBars - 1; i++)
     {
      if(g_r[i].time < InpFrom || g_r[i].time > InpTo) continue;

      double d;
      int dir = EvalSignal(i, d);
      if(dir == 0) continue;

      int entryBar = i + InpEntryDelayBars;
      if(entryBar >= g_bars) break;
      if(InpOnePosAtTime && g_r[entryBar].time < busyUntil) continue;
      if(InpCooldownBars > 0)
        {
         if(dir > 0 && i - lastBarBuy  < InpCooldownBars) continue;
         if(dir < 0 && i - lastBarSell < InpCooldownBars) continue;
        }
      if(dir > 0) lastBarBuy = i; else lastBarSell = i;

      double costPts = (InpCostPoints > 0 ? InpCostPoints : (double)g_r[entryBar].spread) + InpExtraCostPts;
      double entryEff = (dir > 0) ? g_r[entryBar].open + costPts * g_pt
                                  : g_r[entryBar].open - costPts * g_pt;

      if(g_nSig >= reserve)
        {
         reserve = g_nSig + 4096;
         ArrayResize(g_sig, reserve);
         ArrayResize(g_tFav, reserve * g_nTP);
         ArrayResize(g_tAdv, reserve * g_nSL);
        }

      g_sig[g_nSig].t      = g_r[i].time + InpTimeOffsetHours * 3600;
      g_sig[g_nSig].tEntry = g_r[entryBar].time;
      g_sig[g_nSig].dir    = dir;
      g_sig[g_nSig].entry  = entryEff;
      g_sig[g_nSig].delta  = d;

      WalkForward(g_nSig, entryBar, dir, entryEff);
      busyUntil = g_r[MathMin(entryBar + InpMaxHoldBars, g_bars-1)].time;
      g_nSig++;
     }

   Print("Segnali trovati: ", g_nSig, " in ", (GetTickCount()-t0)/1000.0, " s");
   if(g_nSig == 0) { Print("Nessun segnale nel periodo indicato."); return; }

   ArrayResize(g_sig, g_nSig);

//--- migliore combinazione per expectancy
   int bestI = 0, bestJ = 0; double bestExp = -DBL_MAX;
   double gNet, gPF, gWR, gEXP, gDD;
   for(int a = 0; a < g_nSL; a++)
      for(int b = 0; b < g_nTP; b++)
        {
         ComboStats(a, b, gNet, gPF, gWR, gEXP, gDD);
         if(gEXP > bestExp) { bestExp = gEXP; bestI = a; bestJ = b; }
        }
   ComboStats(bestI, bestJ, gNet, gPF, gWR, gEXP, gDD);
   Print("Best combo: SL=", g_slLev[bestI], " TP=", g_tpLev[bestJ],
         " | exp=", DoubleToString(gEXP,2), " pt/trade | PF=", DoubleToString(gPF,2),
         " | WR=", DoubleToString(gWR,1), "%");

   WriteReport(bestI, bestJ);
   if(InpExportCSV) WriteCSV();

   IndicatorRelease(hEma); IndicatorRelease(hAtr);
   if(hAdx != INVALID_HANDLE) IndicatorRelease(hAdx);
  }

//+------------------------------------------------------------------+
void WriteCSV()
  {
   string fn = InpReportName + "_" + _Symbol + "_signals.csv";
   int f = FileOpen(fn, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f == INVALID_HANDLE) { Print("CSV non scrivibile: ", GetLastError()); return; }
   FileWriteString(f, "time;entry_time;dir;hour;minute;dow;delta;entry;mfe_pts;mae_pts;bars_to_mfe;timeout_pts\n");
   for(int s = 0; s < g_nSig; s++)
     {
      MqlDateTime dt; TimeToStruct(g_sig[s].t, dt);
      FileWriteString(f, StringFormat("%s;%s;%d;%d;%d;%d;%.5f;%.5f;%.1f;%.1f;%d;%.1f\n",
        TimeToString(g_sig[s].t, TIME_DATE|TIME_MINUTES),
        TimeToString(g_sig[s].tEntry, TIME_DATE|TIME_MINUTES),
        g_sig[s].dir, dt.hour, dt.min, dt.day_of_week, g_sig[s].delta,
        g_sig[s].entry, g_sig[s].mfe, g_sig[s].mae, g_sig[s].barsToMFE, g_sig[s].timeoutPts));
     }
   FileClose(f);
   Print("CSV: MQL5/Files/", fn);
  }

//+------------------------------------------------------------------+
void BucketRow(string &html, string label, int n, double sum, double sum2, double wins, double gp, double gl)
  {
   double mean = (n > 0) ? sum / n : 0;
   double var  = (n > 1) ? (sum2 - n*mean*mean) / (n-1) : 0;
   double sd   = (var > 0) ? MathSqrt(var) : 0;
   double tst  = (sd > 0 && n > 1) ? mean / (sd / MathSqrt((double)n)) : 0;
   double pf   = (gl > 0) ? gp/gl : (gp > 0 ? 999 : 0);
   double wr   = (n > 0) ? 100.0*wins/n : 0;
   string cls  = (n < InpMinTradesPerBucket) ? " class='thin'" : (mean > 0 ? " class='pos'" : " class='neg'");
   html += StringFormat("<tr%s><td>%s</td><td>%d</td><td>%.1f</td><td>%.0f</td><td>%.1f</td><td>%.2f</td><td>%.2f</td></tr>\n",
                        cls, label, n, mean, sum, wr, pf, tst);
  }

//+------------------------------------------------------------------+
void WriteReport(int bi, int bj)
  {
   int SL = g_slLev[bi], TP = g_tpLev[bj];

//--- aggregati temporali sulla combo scelta
   int    hN[24];  double hS[24],  hS2[24],  hW[24],  hGP[24],  hGL[24];
   int    mN[60];  double mS[60],  mS2[60],  mW[60],  mGP[60],  mGL[60];
   int    dN[7];   double dS[7],   dS2[7],   dW[7],   dGP[7],   dGL[7];
   ArrayInitialize(hN,0); ArrayInitialize(hS,0); ArrayInitialize(hS2,0); ArrayInitialize(hW,0); ArrayInitialize(hGP,0); ArrayInitialize(hGL,0);
   ArrayInitialize(mN,0); ArrayInitialize(mS,0); ArrayInitialize(mS2,0); ArrayInitialize(mW,0); ArrayInitialize(mGP,0); ArrayInitialize(mGL,0);
   ArrayInitialize(dN,0); ArrayInitialize(dS,0); ArrayInitialize(dS2,0); ArrayInitialize(dW,0); ArrayInitialize(dGP,0); ArrayInitialize(dGL,0);

   int nBuy = 0, nSell = 0; double sBuy = 0, sSell = 0;
   double thr[8];
   if(InpGridFromATR && g_atrMedPts > 0)
     { double mm[8] = {0.5,1,2,3,5,8,12,20};
       for(int k=0;k<8;k++) thr[k] = MathRound(mm[k]*g_atrMedPts); }
   else
     { double ff[8] = {250,500,750,1000,1500,2000,2500,3000};
       for(int k=0;k<8;k++) thr[k] = ff[k]; }
   int    reach[8]; ArrayInitialize(reach, 0);
   double barsToReach[8]; ArrayInitialize(barsToReach, 0);

   for(int s = 0; s < g_nSig; s++)
     {
      double p = Outcome(s, bi, bj);
      MqlDateTime dt; TimeToStruct(g_sig[s].t, dt);
      int h = dt.hour, m = dt.min, d = dt.day_of_week;

      hN[h]++; hS[h]+=p; hS2[h]+=p*p; if(p>0){hW[h]++; hGP[h]+=p;} else hGL[h]+=-p;
      mN[m]++; mS[m]+=p; mS2[m]+=p*p; if(p>0){mW[m]++; mGP[m]+=p;} else mGL[m]+=-p;
      dN[d]++; dS[d]+=p; dS2[d]+=p*p; if(p>0){dW[d]++; dGP[d]+=p;} else dGL[d]+=-p;

      if(g_sig[s].dir > 0) { nBuy++;  sBuy  += p; }
      else                 { nSell++; sSell += p; }

      for(int k = 0; k < 8; k++)
         if(g_sig[s].mfe >= thr[k]) { reach[k]++; barsToReach[k] += g_sig[s].barsToMFE; }
     }

   double gNet,gPF,gWR,gEXP,gDD;
   ComboStats(bi, bj, gNet, gPF, gWR, gEXP, gDD);

   string dowName[7] = {"Domenica","Lunedi","Martedi","Mercoledi","Giovedi","Venerdi","Sabato"};

   string html = "";
   html += "<!doctype html><html><head><meta charset='utf-8'><title>SyntheticDelta Lab</title><style>";
   html += "body{background:#14161a;color:#d8dee9;font:13px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;margin:24px}";
   html += "h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;margin:28px 0 8px;color:#88c0d0;border-bottom:1px solid #2e3440;padding-bottom:4px}";
   html += "table{border-collapse:collapse;margin:8px 0;font-size:12px}td,th{border:1px solid #2e3440;padding:3px 8px;text-align:right}";
   html += "th{background:#1e222a;color:#8fbcbb;font-weight:600}td:first-child,th:first-child{text-align:left}";
   html += ".pos td{color:#a3be8c}.neg td{color:#bf616a}.thin td{color:#4c566a;font-style:italic}";
   html += ".kpi{display:inline-block;background:#1e222a;border:1px solid #2e3440;border-radius:6px;padding:10px 16px;margin:4px 8px 4px 0;min-width:110px}";
   html += ".kpi b{display:block;font-size:19px;color:#eceff4}.kpi{font-size:11px;color:#7b8794}.kpi span{font-size:11px;color:#7b8794;text-transform:uppercase;letter-spacing:.5px}";
   html += ".note{background:#1e222a;border-left:3px solid #ebcb8b;padding:10px 14px;margin:12px 0;color:#c8ccd4}";
   html += "</style></head><body>";

   html += "<h1>SyntheticDelta Lab &mdash; " + _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period) + "</h1>";
   html += "<div style='color:#7b8794'>Generato " + TimeToString(TimeCurrent()) + " | Periodo "
         + TimeToString(g_sig[0].t, TIME_DATE) + " &rarr; " + TimeToString(g_sig[g_nSig-1].t, TIME_DATE)
         + " | offset ore " + IntegerToString(InpTimeOffsetHours) + "</div>";

   html += "<h2>Strumento</h2><table>";
   html += StringFormat("<tr><th>Digits</th><td>%d</td><th>Point</th><td>%s</td></tr>", _Digits, DoubleToString(g_pt,8));
   html += StringFormat("<tr><th>1 punto x 1 lotto</th><td>%.4f %s</td><th>ATR(%d) M1 mediano</th><td>%.0f pt (%s in prezzo)</td></tr>",
                        g_ptValue, AccountInfoString(ACCOUNT_CURRENCY), ATR_Period, g_atrMedPts,
                        DoubleToString(g_atrMedPts*g_pt, _Digits));
   html += StringFormat("<tr><th>Griglia</th><td colspan='3'>%s</td></tr>",
                        InpGridFromATR ? "multipli di ATR mediano (auto-scalante)" : "punti fissi");
   html += "</table>";

   html += "<h2>Combinazione migliore per expectancy</h2>";
   html += StringFormat("<div class='kpi'><span>Stop Loss</span><b>%d pt</b>%s | %.1f ATR</div>",
                        SL, DoubleToString(SL*g_pt,_Digits), g_atrMedPts>0 ? SL/g_atrMedPts : 0);
   html += StringFormat("<div class='kpi'><span>Take Profit</span><b>%d pt</b>%s | %.1f ATR</div>",
                        TP, DoubleToString(TP*g_pt,_Digits), g_atrMedPts>0 ? TP/g_atrMedPts : 0);
   html += StringFormat("<div class='kpi'><span>R multiplo</span><b>%.2f</b>TP/SL</div>", SL>0 ? (double)TP/SL : 0);
   html += StringFormat("<div class='kpi'><span>Segnali</span><b>%d</b></div>", g_nSig);
   html += StringFormat("<div class='kpi'><span>Expectancy</span><b>%.1f pt</b></div>", gEXP);
   html += StringFormat("<div class='kpi'><span>Net</span><b>%.0f pt</b>%.0f %s / lotto</div>",
                        gNet, gNet*g_ptValue, AccountInfoString(ACCOUNT_CURRENCY));
   html += StringFormat("<div class='kpi'><span>Profit Factor</span><b>%.2f</b></div>", gPF);
   html += StringFormat("<div class='kpi'><span>Win Rate</span><b>%.1f%%</b></div>", gWR);
   html += StringFormat("<div class='kpi'><span>Max DD</span><b>%.0f pt</b></div>", gDD);
   html += StringFormat("<div class='kpi'><span>Buy / Sell</span><b>%d / %d</b></div>", nBuy, nSell);

   html += "<div class='note'><b>Come leggere:</b> tutti i valori sono in <b>punti</b> (non pip, non valuta). "
           "Ingresso all'open della barra +" + IntegerToString(InpEntryDelayBars) + " dopo il segnale, costi gia' dedotti. "
           "Tie-break pessimista: se SL e TP cadono nella stessa barra M1 viene contato lo <b>stop</b>. "
           "Bucket con meno di " + IntegerToString(InpMinTradesPerBucket) + " trade sono in grigio: <b>rumore, non usarli</b>.</div>";

//--- MFE
   html += "<h2>Il prezzo arriva davvero a target? (MFE post-segnale, orizzonte "
         + IntegerToString(InpMaxHoldBars) + " barre)</h2><table><tr><th>Target (punti | prezzo | ATR)</th><th>Segnali che lo toccano</th><th>%</th><th>Barre medie al tocco</th></tr>";
   for(int k = 0; k < 8; k++)
     {
      double pct = 100.0 * reach[k] / g_nSig;
      double avb = (reach[k] > 0) ? barsToReach[k] / reach[k] : 0;
      html += StringFormat("<tr><td>%.0f pt (%s | %.1f ATR)</td><td>%d</td><td>%.1f%%</td><td>%.0f</td></tr>",
                           thr[k], DoubleToString(thr[k]*g_pt,_Digits), g_atrMedPts>0?thr[k]/g_atrMedPts:0, reach[k], pct, avb);
     }
   html += "</table>";

//--- heatmap SL x TP
   double vmin = DBL_MAX, vmax = -DBL_MAX;
   double grid[]; ArrayResize(grid, g_nSL*g_nTP);
   for(int a = 0; a < g_nSL; a++)
      for(int b = 0; b < g_nTP; b++)
        {
         double n2,p2,w2,e2,d2; ComboStats(a,b,n2,p2,w2,e2,d2);
         grid[a*g_nTP+b] = e2;
         if(e2 < vmin) vmin = e2;
         if(e2 > vmax) vmax = e2;
        }
   html += "<h2>Heatmap expectancy (punti per trade) &mdash; righe SL, colonne TP</h2><table><tr><th>SL \\ TP</th>";
   for(int b = 0; b < g_nTP; b++) html += StringFormat("<th>%d</th>", g_tpLev[b]);
   html += "</tr>";
   for(int a = 0; a < g_nSL; a++)
     {
      html += StringFormat("<tr><th>%d</th>", g_slLev[a]);
      for(int b = 0; b < g_nTP; b++)
        {
         double v = grid[a*g_nTP+b];
         string mark = (a==bi && b==bj) ? ";outline:2px solid #ebcb8b" : "";
         html += StringFormat("<td style='background:%s;color:#e5e9f0%s'>%.1f</td>", HeatColor(v,vmin,vmax), mark, v);
        }
      html += "</tr>";
     }
   html += "</table>";

//--- ore
   html += "<h2>Performance per ORA del segnale (SL " + IntegerToString(SL) + " / TP " + IntegerToString(TP) + ")</h2>";
   html += "<table><tr><th>Ora</th><th>N</th><th>Media pt</th><th>Totale pt</th><th>Win %</th><th>PF</th><th>t-stat</th></tr>";
   for(int h = 0; h < 24; h++)
      BucketRow(html, StringFormat("%02d:00", h), hN[h], hS[h], hS2[h], hW[h], hGP[h], hGL[h]);
   html += "</table>";

//--- giorni
   html += "<h2>Performance per GIORNO</h2>";
   html += "<table><tr><th>Giorno</th><th>N</th><th>Media pt</th><th>Totale pt</th><th>Win %</th><th>PF</th><th>t-stat</th></tr>";
   for(int d = 0; d < 7; d++)
      if(dN[d] > 0) BucketRow(html, dowName[d], dN[d], dS[d], dS2[d], dW[d], dGP[d], dGL[d]);
   html += "</table>";

//--- minuti
   html += "<h2>Performance per MINUTO dell'ora</h2>";
   html += "<div class='note'>60 bucket su un solo campione: con |t| &lt; 2.5 il risultato e' quasi certamente rumore. "
           "Usa questa tabella solo per cercare anomalie strutturali (rollover, apertura sessioni, news schedulate), mai per filtrare i trade.</div>";
   html += "<table><tr><th>Minuto</th><th>N</th><th>Media pt</th><th>Totale pt</th><th>Win %</th><th>PF</th><th>t-stat</th></tr>";
   for(int m = 0; m < 60; m++)
      BucketRow(html, StringFormat(":%02d", m), mN[m], mS[m], mS2[m], mW[m], mGP[m], mGL[m]);
   html += "</table>";

   html += "<h2>Direzione</h2><table><tr><th>Lato</th><th>N</th><th>Totale pt</th><th>Media pt</th></tr>";
   html += StringFormat("<tr><td>BUY</td><td>%d</td><td>%.0f</td><td>%.1f</td></tr>",  nBuy,  sBuy,  nBuy>0?sBuy/nBuy:0);
   html += StringFormat("<tr><td>SELL</td><td>%d</td><td>%.0f</td><td>%.1f</td></tr>", nSell, sSell, nSell>0?sSell/nSell:0);
   html += "</table>";

   html += "</body></html>";

   string fn = InpReportName + "_" + _Symbol + ".html";
   int f = FileOpen(fn, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f == INVALID_HANDLE) { Print("HTML non scrivibile: ", GetLastError()); return; }
   FileWriteString(f, html);
   FileClose(f);
   Print("Report HTML: MQL5/Files/", fn);
  }
//+------------------------------------------------------------------+
