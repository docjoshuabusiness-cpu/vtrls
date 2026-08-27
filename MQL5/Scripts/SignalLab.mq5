//+------------------------------------------------------------------+
//|                                                   SignalLab.mq5  |
//|  Motore generico di test statistico per segnali intraday.        |
//|                                                                  |
//|  Separa la FUNZIONE-SEGNALE dal MOTORE DI MISURA: ogni nuova     |
//|  ipotesi si aggiunge come una funzione e si misura con lo stesso |
//|  barrier test, lo stesso report e lo stesso digest.              |
//|                                                                  |
//|  Misure prodotte:                                                |
//|   - test di simmetria first-touch (edge direzionale pulito)      |
//|   - sweep stop loss completo                                     |
//|   - profilo orario con costo reale per ora                       |
//|   - decili di forza del segnale (la forza informa?)              |
//|   - split in-sample / out-of-sample sulla stessa serie           |
//+------------------------------------------------------------------+
#property copyright "SignalLab"
#property version   "1.00"
#property script_show_inputs
#property strict

//--- ================================================================
enum ENUM_SIGNAL
  {
   SIG_SWEEP      = 0,  // Sweep di liquidita' con rientro (reversal)
   SIG_VWAP_DEV   = 1,  // Deviazione dal VWAP di sessione (reversal)
   SIG_EXPANSION  = 2,  // Espansione di range con volume (continuazione)
   SIG_SYNTHDELTA = 3,  // SyntheticDelta - controllo negativo noto
   SIG_RANDOM     = 4   // Casuale - controllo nullo, deve dare z ~ 0
  };

input group "=== SEGNALE ==="
input ENUM_SIGNAL InpSignal = SIG_SWEEP;
input bool     InpInvert         = false;  // inverte la direzione del segnale

input group "=== DATI ==="
input ENUM_TIMEFRAMES InpTF = PERIOD_M1;
input datetime InpFrom           = D'2015.01.01 00:00';
input datetime InpTo             = D'2026.07.15 00:00';
input int      InpTimeOffsetH    = 0;

input group "=== FINESTRA OPERATIVA ==="
input int      InpHourFrom       = 0;      // ora di inizio (inclusa), 0-23
input int      InpHourTo         = 23;     // ora di fine (inclusa)

input group "=== BARRIER TEST ==="
input int      InpTPpoints       = 1000;   // target in punti
input int      InpMaxBars        = 60;     // orizzonte in barre
input int      InpEntryDelay     = 1;      // 1 = open della barra successiva
input double   InpCostPoints     = 0;      // 0 = spread reale della barra
input double   InpExtraCostPts   = 0;      // commissione/slippage extra
input int      InpCooldownBars   = 0;      // scarta segnali ravvicinati (stessa direzione)

input group "=== SWEEP STOP LOSS ==="
input int      InpSLfrom         = 100;
input int      InpSLto           = 3000;
input int      InpSLstep         = 100;

input group "=== VALIDAZIONE ==="
input int      InpSplitPct       = 70;     // % iniziale usata come in-sample
input int      InpMinPerBucket   = 100;    // soglia minima per considerare un bucket

input group "=== SIG_SWEEP ==="
input int      InpSwLookback     = 30;     // barre di riferimento per l'estremo
input double   InpSwMinPenATR    = 0.10;   // penetrazione minima oltre l'estremo, in ATR
input double   InpSwMinRejFrac   = 0.50;   // frazione minima della penetrazione riassorbita

input group "=== SIG_VWAP_DEV ==="
input int      InpVwSessStartH   = 15;     // ora di reset del VWAP (server time)
input int      InpVwSessStartM   = 30;
input double   InpVwMinDevATR    = 2.0;    // deviazione minima dal VWAP, in ATR

input group "=== SIG_EXPANSION ==="
input double   InpExpMinRangeATR = 2.0;    // range minimo della barra, in ATR
input double   InpExpMinVolMult  = 2.0;    // volume minimo, in multipli della media
input double   InpExpMinBodyFrac = 0.60;   // corpo minimo come frazione del range

input group "=== SIG_SYNTHDELTA (controllo) ==="
input int      InpSdEmaPeriod    = 13;
input int      InpSdVolAvg       = 20;
input double   InpSdThreshold    = 0.15;

input group "=== COMUNE ==="
input int      InpATRPeriod      = 14;
input int      InpVolAvgPeriod   = 20;
input int      InpRandomSeed     = 12345;

#define BIG 2147483647

//--- dati
MqlRates g_r[];
double   g_atr[], g_ema[], g_vwap[], g_volAvg[];
int      g_bars = 0;
double   g_pt, g_atrMed = 0, g_ptValue = 0;

//--- livelli SL
int      g_sl[]; int g_nSL = 0;

//--- record segnali
datetime s_time[];
int      s_dir[];
int      s_tTP[];
double   s_maeAtTP[], s_maeFull[], s_mfe[], s_endPts[], s_cost[], s_score[];
int      s_tSL[];
int      g_n = 0;

//--- prototipi
string SignalName();
string BuildDigest();
void   WriteReport();

//+------------------------------------------------------------------+
int LoadRates()
  {
   int maxb = (int)TerminalInfoInteger(TERMINAL_MAXBARS);
   int got = 0;
   for(int a = 0; a < 60; a++)
     {
      got = CopyRates(_Symbol, InpTF, 0, maxb, g_r);
      if(got > 0 && SeriesInfoInteger(_Symbol, InpTF, SERIES_SYNCHRONIZED)) break;
      Sleep(500);
     }
   long sb = SeriesInfoInteger(_Symbol, InpTF, SERIES_BARS_COUNT);
   Print("Storico ", EnumToString(InpTF), ": server ", sb, " barre | caricate ", got, " | MAXBARS ", maxb);
   if(sb > maxb)
      Print("!!! Il terminale espone solo ", maxb, " barre su ", sb,
            ". Opzioni > Grafici > Max barre = Illimitato, poi riavvia.");
   return got;
  }

//+------------------------------------------------------------------+
bool CopyAll(int h, string nm, double &dst[])
  {
   if(h == INVALID_HANDLE) { Print("Handle nullo: ", nm); return false; }
   for(int k = 0; k < 300; k++) { if(BarsCalculated(h) >= g_bars) break; Sleep(50); }
   ArrayResize(dst, g_bars); ArraySetAsSeries(dst, false);
   double tmp[]; ArraySetAsSeries(tmp, false);
   int done = 0;
   while(done < g_bars)
     {
      int n = MathMin(100000, g_bars - done);
      int got = CopyBuffer(h, 0, g_bars - done - n, n, tmp);
      if(got <= 0) { Print("CopyBuffer ", nm, " err ", GetLastError()); return false; }
      for(int k = 0; k < got; k++) dst[done + k] = tmp[k];
      done += got;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| VWAP di sessione, reset all'ora indicata                         |
//+------------------------------------------------------------------+
void BuildVWAP()
  {
   ArrayResize(g_vwap, g_bars);
   double pv = 0, vv = 0;
   int lastDay = -1;
   for(int i = 0; i < g_bars; i++)
     {
      MqlDateTime dt; TimeToStruct(g_r[i].time, dt);
      int day = dt.day_of_year;
      bool reset = (day != lastDay) ||
                   (dt.hour == InpVwSessStartH && dt.min == InpVwSessStartM);
      if(reset && !(day == lastDay && pv == 0)) { pv = 0; vv = 0; }
      lastDay = day;

      double tp = (g_r[i].high + g_r[i].low + g_r[i].close) / 3.0;
      double v  = (double)g_r[i].tick_volume;
      pv += tp * v; vv += v;
      g_vwap[i] = (vv > 0) ? pv / vv : g_r[i].close;
     }
  }

//+------------------------------------------------------------------+
void BuildVolAvg()
  {
   ArrayResize(g_volAvg, g_bars);
   double run = 0;
   for(int i = 0; i < g_bars; i++)
     {
      run += (double)g_r[i].tick_volume;
      if(i >= InpVolAvgPeriod) run -= (double)g_r[i - InpVolAvgPeriod].tick_volume;
      int n = MathMin(i + 1, InpVolAvgPeriod);
      g_volAvg[i] = (n > 0) ? run / n : (double)g_r[i].tick_volume;
     }
  }

//+------------------------------------------------------------------+
//| SEGNALE 1 - Sweep di liquidita' con rientro                      |
//| Meccanismo: il prezzo buca l'estremo recente (dove siedono gli   |
//| stop), non trova continuazione e rientra dentro il range entro   |
//| la stessa barra. Si opera CONTRO la penetrazione.                |
//| Forza = penetrazione oltre l'estremo, in ATR.                    |
//+------------------------------------------------------------------+
int Sig_Sweep(int i, double &score)
  {
   score = 0;
   if(i < InpSwLookback + 1) return 0;
   double atr = g_atr[i];
   if(atr <= 0) return 0;

   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int j = i - InpSwLookback; j < i; j++)
     { if(g_r[j].high > hi) hi = g_r[j].high; if(g_r[j].low < lo) lo = g_r[j].low; }

   double minPen = InpSwMinPenATR * atr;

   // sweep dei massimi -> SELL
   if(g_r[i].high > hi + minPen)
     {
      double pen = g_r[i].high - hi;
      double rej = g_r[i].high - g_r[i].close;      // quanto e' stato riassorbito
      if(pen > 0 && rej / pen >= InpSwMinRejFrac && g_r[i].close < hi)
        { score = pen / atr; return -1; }
     }
   // sweep dei minimi -> BUY
   if(g_r[i].low < lo - minPen)
     {
      double pen = lo - g_r[i].low;
      double rej = g_r[i].close - g_r[i].low;
      if(pen > 0 && rej / pen >= InpSwMinRejFrac && g_r[i].close > lo)
        { score = pen / atr; return 1; }
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| SEGNALE 2 - Deviazione dal VWAP di sessione                      |
//| Meccanismo: i market maker rientrano in inventario verso il      |
//| prezzo medio ponderato per volume.                               |
//| Forza = deviazione in ATR.                                       |
//+------------------------------------------------------------------+
int Sig_VwapDev(int i, double &score)
  {
   score = 0;
   double atr = g_atr[i];
   if(atr <= 0) return 0;
   double dev = (g_r[i].close - g_vwap[i]) / atr;
   score = MathAbs(dev);
   if(dev >=  InpVwMinDevATR) return -1;   // troppo sopra -> vendi
   if(dev <= -InpVwMinDevATR) return  1;   // troppo sotto -> compra
   return 0;
  }

//+------------------------------------------------------------------+
//| SEGNALE 3 - Espansione di range con volume                       |
//| Meccanismo: informazione che entra nel book; la barra ampia con  |
//| corpo pieno e volume anomalo segnala flusso direzionale.         |
//| Forza = range in ATR.                                            |
//+------------------------------------------------------------------+
int Sig_Expansion(int i, double &score)
  {
   score = 0;
   double atr = g_atr[i];
   if(atr <= 0) return 0;
   double range = g_r[i].high - g_r[i].low;
   if(range <= 0) return 0;
   if(range < InpExpMinRangeATR * atr) return 0;
   if(g_volAvg[i] <= 0) return 0;
   if((double)g_r[i].tick_volume < InpExpMinVolMult * g_volAvg[i]) return 0;

   double body = g_r[i].close - g_r[i].open;
   if(MathAbs(body) / range < InpExpMinBodyFrac) return 0;

   score = range / atr;
   return (body > 0) ? 1 : -1;
  }

//+------------------------------------------------------------------+
//| SEGNALE 4 - SyntheticDelta (controllo negativo noto: z ~ -63)    |
//+------------------------------------------------------------------+
int Sig_SynthDelta(int i, double &score)
  {
   score = 0;
   double range = g_r[i].high - g_r[i].low;
   if(range <= 0) return 0;
   double tv = (double)g_r[i].tick_volume;
   if(tv <= 0) return 0;
   double ema = g_ema[i];

   double fracBuy  = (g_r[i].close - g_r[i].low)   / range;
   double fracSell = (g_r[i].high  - g_r[i].close) / range;
   double bullsN   = (g_r[i].high - ema) / range;
   double bearsN   = (ema - g_r[i].low)  / range;
   double volW     = (g_volAvg[i] > 0) ? MathMin(tv / g_volAvg[i], 3.0) : 1.0;

   double d = (fracBuy * (1.0 + bullsN) * volW - fracSell * (1.0 + bearsN) * volW) / 6.0;
   score = MathAbs(d);
   if(d >  InpSdThreshold) return  1;
   if(d < -InpSdThreshold) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| SEGNALE 5 - Casuale (controllo nullo: deve dare z ~ 0)           |
//| Serve a validare il motore: se il random produce edge, il bug e' |
//| nel motore, non nella strategia.                                 |
//+------------------------------------------------------------------+
int Sig_Random(int i, double &score)
  {
   uint x = (uint)(i * 2654435761u + InpRandomSeed);
   x ^= x >> 13; x *= 2246822519u; x ^= x >> 16;
   score = (double)(x % 1000) / 1000.0;
   if((x % 97) != 0) return 0;                // ~1% delle barre
   return ((x >> 8) % 2 == 0) ? 1 : -1;
  }

//+------------------------------------------------------------------+
int Dispatch(int i, double &score)
  {
   switch(InpSignal)
     {
      case SIG_SWEEP:      return Sig_Sweep(i, score);
      case SIG_VWAP_DEV:   return Sig_VwapDev(i, score);
      case SIG_EXPANSION:  return Sig_Expansion(i, score);
      case SIG_SYNTHDELTA: return Sig_SynthDelta(i, score);
      case SIG_RANDOM:     return Sig_Random(i, score);
     }
   return 0;
  }

//+------------------------------------------------------------------+
string SignalName()
  {
   switch(InpSignal)
     {
      case SIG_SWEEP:      return "SWEEP";
      case SIG_VWAP_DEV:   return "VWAP_DEV";
      case SIG_EXPANSION:  return "EXPANSION";
      case SIG_SYNTHDELTA: return "SYNTHDELTA";
      case SIG_RANDOM:     return "RANDOM";
     }
   return "?";
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   g_pt = _Point;
   for(int v = InpSLfrom; v <= InpSLto; v += InpSLstep)
     { ArrayResize(g_sl, g_nSL + 1); g_sl[g_nSL++] = v; }

   ArraySetAsSeries(g_r, false);
   g_bars = LoadRates();
   if(g_bars <= 0) { Print("Nessun dato."); return; }

   int hA = iATR(_Symbol, InpTF, InpATRPeriod);
   if(!CopyAll(hA, "ATR", g_atr)) return;
   if(InpSignal == SIG_SYNTHDELTA)
     {
      int hE = iMA(_Symbol, InpTF, InpSdEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(!CopyAll(hE, "EMA", g_ema)) return;
      IndicatorRelease(hE);
     }
   else ArrayResize(g_ema, g_bars);

   BuildVolAvg();
   if(InpSignal == SIG_VWAP_DEV) BuildVWAP(); else ArrayResize(g_vwap, g_bars);

//--- diagnostica strumento
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_ptValue = (ts > 0) ? tv * (g_pt / ts) : 0.0;
     {
      double t2[]; int n = 0; ArrayResize(t2, g_bars);
      for(int i = 0; i < g_bars; i++)
         if(g_r[i].time >= InpFrom && g_r[i].time <= InpTo && g_atr[i] > 0) t2[n++] = g_atr[i] / g_pt;
      if(n > 0) { ArrayResize(t2, n); ArraySort(t2); g_atrMed = t2[n/2]; }
     }
   Print("=== ", _Symbol, " ", EnumToString(InpTF), " | segnale ", SignalName(),
         " | Digits ", _Digits, " | ATR mediano ", DoubleToString(g_atrMed, 0), " pt");
   Print("TP ", InpTPpoints, " pt = ", DoubleToString(InpTPpoints*g_pt, _Digits),
         " = ", DoubleToString(g_atrMed > 0 ? InpTPpoints/g_atrMed : 0, 2), " x ATR");

//--- scansione
   int warm = MathMax(MathMax(InpATRPeriod, InpVolAvgPeriod),
                      MathMax(InpSwLookback, InpSdEmaPeriod)) + 2;
   int cap = 8192;
   ArrayResize(s_time, cap); ArrayResize(s_dir, cap); ArrayResize(s_tTP, cap);
   ArrayResize(s_maeAtTP, cap); ArrayResize(s_maeFull, cap); ArrayResize(s_mfe, cap);
   ArrayResize(s_endPts, cap); ArrayResize(s_cost, cap); ArrayResize(s_score, cap);
   ArrayResize(s_tSL, cap * g_nSL);

   int lastB = -1000000, lastS = -1000000;
   uint t0 = GetTickCount();

   for(int i = warm; i < g_bars - InpEntryDelay - 1; i++)
     {
      if(g_r[i].time < InpFrom || g_r[i].time > InpTo) continue;

      datetime tShift = g_r[i].time + InpTimeOffsetH * 3600;
      MqlDateTime dt; TimeToStruct(tShift, dt);
      if(InpHourFrom <= InpHourTo)
        { if(dt.hour < InpHourFrom || dt.hour > InpHourTo) continue; }
      else
        { if(dt.hour < InpHourFrom && dt.hour > InpHourTo) continue; }   // finestra a cavallo di mezzanotte

      double sc;
      int dir = Dispatch(i, sc);
      if(dir == 0) continue;
      if(InpInvert) dir = -dir;
      if(InpCooldownBars > 0)
        {
         if(dir > 0 && i - lastB < InpCooldownBars) continue;
         if(dir < 0 && i - lastS < InpCooldownBars) continue;
        }
      if(dir > 0) lastB = i; else lastS = i;

      int eb = i + InpEntryDelay;
      if(eb >= g_bars) break;

      double cost = (InpCostPoints > 0 ? InpCostPoints : (double)g_r[eb].spread) + InpExtraCostPts;
      double E = (dir > 0) ? g_r[eb].open + cost * g_pt : g_r[eb].open - cost * g_pt;

      if(g_n >= cap)
        {
         cap = g_n + 16384;
         ArrayResize(s_time, cap); ArrayResize(s_dir, cap); ArrayResize(s_tTP, cap);
         ArrayResize(s_maeAtTP, cap); ArrayResize(s_maeFull, cap); ArrayResize(s_mfe, cap);
         ArrayResize(s_endPts, cap); ArrayResize(s_cost, cap); ArrayResize(s_score, cap);
         ArrayResize(s_tSL, cap * g_nSL);
        }

      int base = g_n * g_nSL;
      for(int k = 0; k < g_nSL; k++) s_tSL[base + k] = BIG;
      double mfe = 0, mae = 0, maeAtTP = -1;
      int tTP = BIG, pa = 0, last = eb;
      int endB = MathMin(eb + InpMaxBars, g_bars - 1);

      for(int k = eb; k <= endB; k++)
        {
         double fav, adv;
         if(dir > 0) { fav = (g_r[k].high - E) / g_pt; adv = (E - g_r[k].low)  / g_pt; }
         else        { fav = (E - g_r[k].low)  / g_pt; adv = (g_r[k].high - E) / g_pt; }
         if(fav > mfe) mfe = fav;
         if(adv > mae) mae = adv;
         while(pa < g_nSL && mae >= (double)g_sl[pa]) { s_tSL[base + pa] = k - eb; pa++; }
         if(tTP == BIG && mfe >= (double)InpTPpoints) { tTP = k - eb; maeAtTP = mae; }
         last = k;
         if(tTP != BIG && pa >= g_nSL) break;
        }

      s_time[g_n]    = tShift;
      s_dir[g_n]     = dir;
      s_tTP[g_n]     = tTP;
      s_maeAtTP[g_n] = maeAtTP;
      s_maeFull[g_n] = mae;
      s_mfe[g_n]     = mfe;
      s_cost[g_n]    = cost;
      s_score[g_n]   = sc;
      s_endPts[g_n]  = (dir > 0) ? (g_r[last].close - E) / g_pt : (E - g_r[last].close) / g_pt;
      g_n++;
     }

   Print("Segnali: ", g_n, " | scansione ", (GetTickCount()-t0)/1000.0, " s");
   if(g_n == 0) { Print("Nessun segnale: allenta i filtri del segnale scelto."); return; }

   WriteReport();
   IndicatorRelease(hA);
  }

//+------------------------------------------------------------------+
//| Esito di un segnale per un dato livello di SL                    |
//+------------------------------------------------------------------+
double Outcome(int s, int k)
  {
   int ta = s_tSL[s * g_nSL + k], tf = s_tTP[s];
   if(tf == BIG && ta == BIG) return s_endPts[s];
   if(ta <= tf)               return -(double)g_sl[k];
   return (double)InpTPpoints;
  }

//+------------------------------------------------------------------+
//| Statistiche di edge sui segnali con indice da lo a hi escluso    |
//+------------------------------------------------------------------+
void EdgeStats(int lo, int hi, int refK, int &n, double &foPct, double &aoPct,
               double &z, double &expc, double &t)
  {
   n = 0; int fo = 0, ao = 0; double sum = 0, sum2 = 0;
   for(int s = lo; s < hi; s++)
     {
      n++;
      bool f = (s_tTP[s] != BIG);
      bool a = (s_maeFull[s] >= (double)InpTPpoints);
      if(f && !a) fo++;
      if(a && !f) ao++;
      double p = Outcome(s, refK);
      sum += p; sum2 += p*p;
     }
   if(n == 0) { foPct = aoPct = z = expc = t = 0; return; }
   foPct = 100.0*fo/n; aoPct = 100.0*ao/n;
   z = (fo + ao > 0) ? (fo - ao)/MathSqrt((double)(fo + ao)) : 0;
   expc = sum/n;
   double v = (n > 1) ? (sum2 - n*expc*expc)/(n-1) : 0;
   double sd = (v > 0) ? MathSqrt(v) : 0;
   t = (sd > 0) ? expc/(sd/MathSqrt((double)n)) : 0;
  }

//+------------------------------------------------------------------+
int BestSL()
  {
   int best = 0; double bm = -DBL_MAX;
   for(int k = 0; k < g_nSL; k++)
     {
      double sum = 0;
      for(int s = 0; s < g_n; s++) sum += Outcome(s, k);
      if(sum/g_n > bm) { bm = sum/g_n; best = k; }
     }
   return best;
  }

//+------------------------------------------------------------------+
string BuildDigest()
  {
   string d = "### SIGNALLAB DIGEST v1\n";
   d += StringFormat("SIG|%s|invert|%d|tp|%d|maxbars|%d|delay|%d|cooldown|%d|hours|%d-%d\n",
                     SignalName(), InpInvert ? 1 : 0, InpTPpoints, InpMaxBars,
                     InpEntryDelay, InpCooldownBars, InpHourFrom, InpHourTo);
   d += StringFormat("SYM|%s|digits|%d|point|%s|ptval|%.5f|ccy|%s|atrmed|%.0f\n",
                     _Symbol, _Digits, DoubleToString(g_pt,8), g_ptValue,
                     AccountInfoString(ACCOUNT_CURRENCY), g_atrMed);
   d += StringFormat("TF|%s|bars|%d|from|%s|to|%s\n", EnumToString(InpTF), g_bars,
                     TimeToString(g_r[0].time, TIME_DATE|TIME_MINUTES),
                     TimeToString(g_r[g_bars-1].time, TIME_DATE|TIME_MINUTES));
   d += StringFormat("PARSW|lb|%d|pen|%.2f|rej|%.2f\nPARVW|h|%d|m|%d|dev|%.2f\nPAREX|rng|%.2f|vol|%.2f|body|%.2f\n",
                     InpSwLookback, InpSwMinPenATR, InpSwMinRejFrac,
                     InpVwSessStartH, InpVwSessStartM, InpVwMinDevATR,
                     InpExpMinRangeATR, InpExpMinVolMult, InpExpMinBodyFrac);

   int nDays = 0; long prev = -1; double totCost = 0; int hits = 0;
   for(int s = 0; s < g_n; s++)
     {
      long day = (long)s_time[s] / 86400;
      if(day != prev) { nDays++; prev = day; }
      totCost += s_cost[s];
      if(s_tTP[s] != BIG) hits++;
     }
   if(nDays < 1) nDays = 1;
   d += StringFormat("GLOB|n|%d|days|%d|perday|%.2f|hit|%.2f|cost|%.0f|cost_pct_tp|%.1f\n",
                     g_n, nDays, (double)g_n/nDays, 100.0*hits/g_n, totCost/g_n,
                     InpTPpoints > 0 ? 100.0*(totCost/g_n)/InpTPpoints : 0);

   int fo = 0, ao = 0, both = 0, neither = 0;
   for(int s = 0; s < g_n; s++)
     {
      bool f = (s_tTP[s] != BIG), a = (s_maeFull[s] >= (double)InpTPpoints);
      if(f && a) both++; else if(f) fo++; else if(a) ao++; else neither++;
     }
   d += StringFormat("SYMM|fo|%d|ao|%d|both|%d|neither|%d|edge_pp|%.2f|z|%.2f\n",
                     fo, ao, both, neither, 100.0*(fo-ao)/g_n,
                     (fo+ao > 0) ? (fo-ao)/MathSqrt((double)(fo+ao)) : 0);

   int refK = BestSL();
   d += StringFormat("REFSL|%d\n", g_sl[refK]);

   for(int k = 0; k < g_nSL; k++)
     {
      int wT = 0, wS = 0, wO = 0; double sum = 0, sum2 = 0;
      for(int s = 0; s < g_n; s++)
        {
         int ta = s_tSL[s*g_nSL+k], tf = s_tTP[s];
         double p;
         if(tf == BIG && ta == BIG) { wO++; p = s_endPts[s]; }
         else if(ta <= tf)          { wS++; p = -(double)g_sl[k]; }
         else                       { wT++; p = (double)InpTPpoints; }
         sum += p; sum2 += p*p;
        }
      double m = sum/g_n;
      double v = (g_n > 1) ? (sum2 - g_n*m*m)/(g_n-1) : 0;
      double sd = (v > 0) ? MathSqrt(v) : 0;
      d += StringFormat("SL|%d|tp|%.1f|sl|%.1f|to|%.1f|exp|%.1f|t|%.2f\n",
                        g_sl[k], 100.0*wT/g_n, 100.0*wS/g_n, 100.0*wO/g_n, m,
                        (sd > 0) ? m/(sd/MathSqrt((double)g_n)) : 0);
     }

//--- split in-sample / out-of-sample
   int cut = (int)(g_n * InpSplitPct / 100.0);
   if(cut < 1) cut = 1; if(cut > g_n - 1) cut = g_n - 1;
   int n1, n2; double f1, a1, z1, e1, t1, f2, a2, z2, e2, t2;
   EdgeStats(0, cut, refK, n1, f1, a1, z1, e1, t1);
   EdgeStats(cut, g_n, refK, n2, f2, a2, z2, e2, t2);
   d += StringFormat("IS|n|%d|to|%s|fo|%.1f|ao|%.1f|z|%.2f|exp|%.1f|t|%.2f\n",
                     n1, TimeToString(s_time[cut-1], TIME_DATE), f1, a1, z1, e1, t1);
   d += StringFormat("OOS|n|%d|from|%s|fo|%.1f|ao|%.1f|z|%.2f|exp|%.1f|t|%.2f\n",
                     n2, TimeToString(s_time[cut], TIME_DATE), f2, a2, z2, e2, t2);

//--- profilo orario
   for(int hh = 0; hh < 24; hh++)
     {
      int n = 0, f3 = 0, a3 = 0, hi2 = 0; double sum = 0, sum2 = 0, cst = 0;
      for(int s = 0; s < g_n; s++)
        {
         MqlDateTime dt; TimeToStruct(s_time[s], dt);
         if(dt.hour != hh) continue;
         n++; cst += s_cost[s];
         bool f = (s_tTP[s] != BIG), a = (s_maeFull[s] >= (double)InpTPpoints);
         if(f) hi2++;
         if(f && !a) f3++;
         if(a && !f) a3++;
         double p = Outcome(s, refK);
         sum += p; sum2 += p*p;
        }
      if(n == 0) continue;
      double m = sum/n;
      double v = (n > 1) ? (sum2 - n*m*m)/(n-1) : 0;
      double sd = (v > 0) ? MathSqrt(v) : 0;
      d += StringFormat("HOUR|%d|n|%d|hit|%.1f|fo|%.1f|ao|%.1f|z|%.2f|exp|%.1f|t|%.2f|cost|%.0f\n",
                        hh, n, 100.0*hi2/n, 100.0*f3/n, 100.0*a3/n,
                        (f3+a3 > 0) ? (f3-a3)/MathSqrt((double)(f3+a3)) : 0, m,
                        (sd > 0) ? m/(sd/MathSqrt((double)n)) : 0, cst/n);
     }

//--- decili di forza del segnale
     {
      double srt[]; ArrayResize(srt, g_n);
      for(int s = 0; s < g_n; s++) srt[s] = s_score[s];
      ArraySort(srt);
      for(int q = 0; q < 10; q++)
        {
         double lo = srt[(int)((q/10.0)*(g_n-1))];
         double hi2 = srt[(int)(((q+1)/10.0)*(g_n-1))];
         int n = 0, f3 = 0, a3 = 0; double sum = 0;
         for(int s = 0; s < g_n; s++)
           {
            double v = s_score[s];
            if(v < lo || (q < 9 && v >= hi2)) continue;
            n++;
            bool f = (s_tTP[s] != BIG), a = (s_maeFull[s] >= (double)InpTPpoints);
            if(f && !a) f3++;
            if(a && !f) a3++;
            sum += Outcome(s, refK);
           }
         if(n == 0) continue;
         d += StringFormat("DEC|%d|lo|%.4f|hi|%.4f|n|%d|fo|%.1f|ao|%.1f|edge|%.1f|z|%.2f|exp|%.1f\n",
                           q+1, lo, hi2, n, 100.0*f3/n, 100.0*a3/n, 100.0*(f3-a3)/n,
                           (f3+a3 > 0) ? (f3-a3)/MathSqrt((double)(f3+a3)) : 0, sum/n);
        }
     }

   d += "### END\n";
   return d;
  }

//+------------------------------------------------------------------+
void WriteReport()
  {
   int refK = BestSL();
   int nA, nI, nO; double fA, aA, zA, eA, tA, fI, aI, zI, eI, tI, fO, aO, zO, eO, tO;
   EdgeStats(0, g_n, refK, nA, fA, aA, zA, eA, tA);
   int cut = (int)(g_n * InpSplitPct / 100.0);
   if(cut < 1) cut = 1; if(cut > g_n - 1) cut = g_n - 1;
   EdgeStats(0, cut, refK, nI, fI, aI, zI, eI, tI);
   EdgeStats(cut, g_n, refK, nO, fO, aO, zO, eO, tO);

   double totCost = 0;
   for(int s = 0; s < g_n; s++) totCost += s_cost[s];
   double avgCost = totCost / g_n;
   double edgeGross = (aA - fA) / 100.0 * InpTPpoints;   // edge lordo se il segno fosse corretto

   string h = "";
   h += "<!doctype html><html><head><meta charset='utf-8'><title>SignalLab</title><style>";
   h += "body{background:#14161a;color:#d8dee9;font:13px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;margin:24px}";
   h += "h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;margin:26px 0 8px;color:#88c0d0;border-bottom:1px solid #2e3440;padding-bottom:4px}";
   h += "table{border-collapse:collapse;margin:8px 0;font-size:12px}td,th{border:1px solid #2e3440;padding:3px 9px;text-align:right}";
   h += "th{background:#1e222a;color:#8fbcbb}td:first-child,th:first-child{text-align:left}";
   h += ".thin td{color:#4c566a;font-style:italic}";
   h += ".kpi{display:inline-block;background:#1e222a;border:1px solid #2e3440;border-radius:6px;padding:10px 16px;margin:4px 8px 4px 0;min-width:120px;font-size:11px;color:#7b8794}";
   h += ".kpi b{display:block;font-size:20px;color:#eceff4}";
   h += ".note{background:#1e222a;border-left:3px solid #ebcb8b;padding:10px 14px;margin:12px 0;color:#c8ccd4}";
   h += ".ko{border-left-color:#bf616a}.ok{border-left-color:#a3be8c}";
   h += "pre{background:#0f1114;border:1px solid #2e3440;border-radius:6px;padding:14px;overflow-x:auto;";
   h += "font:11px/1.45 ui-monospace,Consolas,monospace;color:#d8dee9;white-space:pre}";
   h += "</style></head><body>";

   h += "<h1>SignalLab &mdash; " + SignalName() + (InpInvert ? " (INVERTITO)" : "") + "</h1>";
   h += "<div style='color:#7b8794'>" + _Symbol + " " + EnumToString(InpTF)
      + " | TP " + IntegerToString(InpTPpoints) + " pt | orizzonte " + IntegerToString(InpMaxBars)
      + " barre | ore " + IntegerToString(InpHourFrom) + "-" + IntegerToString(InpHourTo)
      + " | " + TimeToString(s_time[0], TIME_DATE) + " &rarr; " + TimeToString(s_time[g_n-1], TIME_DATE) + "</div>";

//--- verdetto in cima
   h += "<h2>Verdetto</h2>";
   h += StringFormat("<div class='kpi'><span>Segnali</span><b>%d</b></div>", g_n);
   h += StringFormat("<div class='kpi'><span>Edge direzionale</span><b>%+.2f pp</b>fav %.1f%% / avv %.1f%%</div>",
                     fA - aA, fA, aA);
   h += StringFormat("<div class='kpi'><span>z</span><b>%+.2f</b>%s</div>", zA,
                     MathAbs(zA) < 2.0 ? "non distinguibile da zero" : (zA > 0 ? "a favore" : "CONTRO"));
   h += StringFormat("<div class='kpi'><span>Edge lordo</span><b>%.0f pt</b>se il segno e' corretto</div>",
                     MathAbs(fA - aA)/100.0*InpTPpoints);
   h += StringFormat("<div class='kpi'><span>Costo medio</span><b>%.0f pt</b>%.1f%% del TP</div>",
                     avgCost, 100.0*avgCost/InpTPpoints);
   h += StringFormat("<div class='kpi'><span>Expectancy (SL %d)</span><b>%.1f pt</b>t = %.2f</div>",
                     g_sl[refK], eA, tA);

   double netto = MathAbs(fA - aA)/100.0*InpTPpoints - avgCost;
   if(MathAbs(zA) < 2.0)
      h += "<div class='note ko'><b>NESSUN EDGE.</b> La differenza fra tocchi favorevoli e avversi non e' "
           "distinguibile dal caso. Nessuna soglia, nessun orario e nessuno stop possono creare un edge "
           "che nei dati non esiste.</div>";
   else if(netto <= 0)
      h += StringFormat("<div class='note ko'><b>EDGE REALE MA NON MONETIZZABILE.</b> z = %.2f su %d segnali: "
           "l'asimmetria esiste. Ma vale %.0f punti lordi contro %.0f punti di costo medio: netto <b>%+.0f</b>. "
           "%s</div>", zA, g_n, MathAbs(fA-aA)/100.0*InpTPpoints, avgCost, netto,
           zA < 0 ? "Il segno e' invertito: rilancia con InpInvert=true prima di scartarlo." : "");
   else
      h += StringFormat("<div class='note ok'><b>EDGE POTENZIALMENTE MONETIZZABILE.</b> %.0f punti lordi contro "
           "%.0f di costo: netto <b>%+.0f</b> per segnale. Ora conta solo una cosa: <b>tiene fuori campione?</b> "
           "Guarda la sezione sotto.</div>", MathAbs(fA-aA)/100.0*InpTPpoints, avgCost, netto);

//--- IS/OOS
   h += "<h2>In-sample vs out-of-sample</h2>";
   h += "<div class='note'>Lo split e' <b>temporale</b>: primo " + IntegerToString(InpSplitPct)
      + "% dei segnali contro il resto. Un edge che esiste nell'in-sample e sparisce nell'out-of-sample "
        "e' overfitting, anche quando l'in-sample ha z enormi. I due z devono avere <b>lo stesso segno</b> "
        "e magnitudine confrontabile.</div>";
   h += "<table><tr><th>Campione</th><th>Segnali</th><th>fav%</th><th>avv%</th><th>edge pp</th><th>z</th><th>Exp pt</th><th>t</th></tr>";
   h += StringFormat("<tr><td>In-sample (fino a %s)</td><td>%d</td><td>%.1f</td><td>%.1f</td>"
                     "<td style='color:%s'><b>%+.2f</b></td><td>%+.2f</td><td>%.1f</td><td>%.2f</td></tr>",
                     TimeToString(s_time[cut-1], TIME_DATE), nI, fI, aI,
                     fI-aI > 0 ? "#a3be8c" : "#bf616a", fI-aI, zI, eI, tI);
   h += StringFormat("<tr><td>Out-of-sample (da %s)</td><td>%d</td><td>%.1f</td><td>%.1f</td>"
                     "<td style='color:%s'><b>%+.2f</b></td><td>%+.2f</td><td>%.1f</td><td>%.2f</td></tr>",
                     TimeToString(s_time[cut], TIME_DATE), nO, fO, aO,
                     fO-aO > 0 ? "#a3be8c" : "#bf616a", fO-aO, zO, eO, tO);
   h += "</table>";
   if((zI > 0) != (zO > 0) && MathAbs(zI) > 2 && MathAbs(zO) > 2)
      h += "<div class='note ko'><b>SEGNO OPPOSTO fra i due campioni.</b> Qualunque cosa il segnale misuri, "
           "non e' stabile nel tempo. Non costruirci sopra.</div>";

//--- sweep SL
   h += "<h2>Sweep stop loss</h2><table><tr><th>SL</th><th>x ATR</th><th>R</th><th>%TP</th><th>%SL</th>"
        "<th>%scaduti</th><th>Exp pt</th><th>Net pt</th><th>Net " + AccountInfoString(ACCOUNT_CURRENCY) + "</th></tr>";
   for(int k = 0; k < g_nSL; k++)
     {
      int wT = 0, wS = 0, wO = 0; double sum = 0;
      for(int s = 0; s < g_n; s++)
        {
         int ta = s_tSL[s*g_nSL+k], tf = s_tTP[s];
         if(tf == BIG && ta == BIG) { wO++; sum += s_endPts[s]; }
         else if(ta <= tf)          { wS++; sum -= (double)g_sl[k]; }
         else                       { wT++; sum += (double)InpTPpoints; }
        }
      double m = sum/g_n;
      h += StringFormat("<tr%s><td>%d</td><td>%.1f</td><td>%.2f</td><td>%.1f</td><td>%.1f</td><td>%.1f</td>"
                        "<td style='color:%s'><b>%.1f</b></td><td>%.0f</td><td>%.0f</td></tr>",
                        k == refK ? " style='outline:2px solid #ebcb8b'" : "",
                        g_sl[k], g_atrMed > 0 ? g_sl[k]/g_atrMed : 0, (double)InpTPpoints/g_sl[k],
                        100.0*wT/g_n, 100.0*wS/g_n, 100.0*wO/g_n,
                        m > 0 ? "#a3be8c" : "#bf616a", m, sum, sum*g_ptValue);
     }
   h += "</table>";

//--- profilo orario
   h += "<h2>Profilo orario</h2>";
   h += "<div class='note'>La colonna <b>netto</b> e' l'edge lordo dell'ora meno il costo reale pagato in "
        "quell'ora. E' l'unico numero che dice se in quell'ora si guadagna. Un edge grande in un'ora con "
        "spread largo vale zero.</div>";
   h += "<table><tr><th>Ora</th><th>Segnali</th><th>fav%</th><th>avv%</th><th>edge pp</th><th>z</th>"
        "<th>edge pt</th><th>costo pt</th><th>netto pt</th><th>Exp pt</th></tr>";
   for(int hh = 0; hh < 24; hh++)
     {
      int n = 0, f3 = 0, a3 = 0; double sum = 0, cst = 0;
      for(int s = 0; s < g_n; s++)
        {
         MqlDateTime dt; TimeToStruct(s_time[s], dt);
         if(dt.hour != hh) continue;
         n++; cst += s_cost[s];
         bool f = (s_tTP[s] != BIG), a = (s_maeFull[s] >= (double)InpTPpoints);
         if(f && !a) f3++;
         if(a && !f) a3++;
         sum += Outcome(s, refK);
        }
      if(n == 0) continue;
      double edgePP = 100.0*(f3-a3)/n;
      double zz = (f3+a3 > 0) ? (f3-a3)/MathSqrt((double)(f3+a3)) : 0;
      double edgePt = MathAbs(edgePP)/100.0*InpTPpoints;
      double net = edgePt - cst/n;
      string cls = (n < InpMinPerBucket) ? " class='thin'" : "";
      h += StringFormat("<tr%s><td>%02d:00</td><td>%d</td><td>%.1f</td><td>%.1f</td>"
                        "<td style='color:%s'>%+.1f</td><td style='color:%s'>%+.2f</td>"
                        "<td>%.0f</td><td>%.0f</td><td style='color:%s'><b>%+.0f</b></td><td>%.1f</td></tr>",
                        cls, hh, n, 100.0*f3/n, 100.0*a3/n,
                        edgePP > 0 ? "#a3be8c" : "#bf616a", edgePP,
                        MathAbs(zz) > 2.0 ? "#ebcb8b" : "#7b8794", zz,
                        edgePt, cst/n, net > 0 ? "#a3be8c" : "#bf616a", net, sum/n);
     }
   h += "</table>";

//--- decili
   h += "<h2>Decili di forza del segnale</h2>";
   h += "<div class='note'>Gruppi disgiunti di pari numerosita'. Se la forza del segnale informa, l'edge deve "
        "crescere dal decile 1 al 10. Se resta piatto, il filtro sulla forza e' inutile qualunque soglia "
        "si scelga.</div>";
   h += "<table><tr><th>Decile</th><th>Intervallo</th><th>Segnali</th><th>fav%</th><th>avv%</th><th>edge pp</th><th>z</th><th>Exp pt</th></tr>";
     {
      double srt[]; ArrayResize(srt, g_n);
      for(int s = 0; s < g_n; s++) srt[s] = s_score[s];
      ArraySort(srt);
      for(int q = 0; q < 10; q++)
        {
         double lo = srt[(int)((q/10.0)*(g_n-1))];
         double hi2 = srt[(int)(((q+1)/10.0)*(g_n-1))];
         int n = 0, f3 = 0, a3 = 0; double sum = 0;
         for(int s = 0; s < g_n; s++)
           {
            double v = s_score[s];
            if(v < lo || (q < 9 && v >= hi2)) continue;
            n++;
            bool f = (s_tTP[s] != BIG), a = (s_maeFull[s] >= (double)InpTPpoints);
            if(f && !a) f3++;
            if(a && !f) a3++;
            sum += Outcome(s, refK);
           }
         if(n == 0) continue;
         double e = 100.0*(f3-a3)/n;
         double zz = (f3+a3 > 0) ? (f3-a3)/MathSqrt((double)(f3+a3)) : 0;
         h += StringFormat("<tr><td>%d</td><td>%.3f &ndash; %.3f</td><td>%d</td><td>%.1f</td><td>%.1f</td>"
                           "<td style='color:%s'><b>%+.1f</b></td><td style='color:%s'>%+.2f</td><td>%.1f</td></tr>",
                           q+1, lo, hi2, n, 100.0*f3/n, 100.0*a3/n,
                           e > 0 ? "#a3be8c" : "#bf616a", e,
                           MathAbs(zz) > 2.0 ? "#ebcb8b" : "#7b8794", zz, sum/n);
        }
     }
   h += "</table>";

//--- digest
   string dg = BuildDigest();
   h += "<h2>Digest da copiare</h2>";
   h += "<div class='note'>Seleziona e incolla in chat. Stesso testo in <b>MQL5/Files/SignalLab_digest.txt</b>.</div>";
   string esc = dg;
   StringReplace(esc, "&", "&amp;");
   StringReplace(esc, "<", "&lt;");
   h += "<pre>" + esc + "</pre>";
   h += "</body></html>";

   string fn = "SignalLab_" + _Symbol + "_" + SignalName() + (InpInvert ? "_INV" : "") + ".html";
   int f = FileOpen(fn, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f == INVALID_HANDLE) { Print("HTML non scrivibile: ", GetLastError()); return; }
   FileWriteString(f, h);
   FileClose(f);
   Print("Report: MQL5/Files/", fn);

   int df = FileOpen("SignalLab_digest.txt", FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(df != INVALID_HANDLE) { FileWriteString(df, dg); FileClose(df); Print("Digest: MQL5/Files/SignalLab_digest.txt"); }

   Print("VERDETTO ", SignalName(), ": edge ", DoubleToString(fA-aA,2), " pp | z ", DoubleToString(zA,2),
         " | lordo ", DoubleToString(MathAbs(fA-aA)/100.0*InpTPpoints,0), " pt | costo ",
         DoubleToString(avgCost,0), " pt | netto ", DoubleToString(netto,0), " pt");
  }
//+------------------------------------------------------------------+
