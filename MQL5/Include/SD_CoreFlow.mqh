//+------------------------------------------------------------------+
//|                                                SD_CoreFlow.mqh   |
//|  Flow Z di SyntheticDelta v3.x come COSTRUTTORE DI SEGNALI per    |
//|  SignalLab_MultiTF, nella stessa convenzione di SD_Core.mqh:      |
//|  array ordinati dal piu' vecchio al piu' recente (non-series),    |
//|  dir[i] = +1/-1/0 e burst[i] = posizione nella raffica.           |
//|                                                                  |
//|  Segnale = PRIMO ATTRAVERSAMENTO di +-soglia di Z:                |
//|     BUY  se Z[i] >= +soglia e Z[i-1] non lo era                   |
//|     SELL se Z[i] <= -soglia e Z[i-1] non lo era                   |
//|  (SignalLab prova gia' SEGUI e INVERTI: l'interpretazione        |
//|  momentum o inversione la decidono i dati, non questo file).      |
//|                                                                  |
//|  Matematica identica a SyntheticDelta_v3.x.mq5 e a               |
//|  research/syntheticdelta_ref.py (riferimento barra per barra);    |
//|  research/test_coreflow_shadow.py ne controlla la trascrizione.   |
//|  QUESTO FILE NON E' STATO COMPILATO in ambiente di sviluppo:      |
//|  compilalo in MetaEditor e controlla gli Errors.                  |
//|                                                                  |
//|  INTEGRAZIONE in SignalLab_MultiTF (6 modifiche; il file          |
//|  standalone e' generato da tools/build_standalone.py: aggiungi    |
//|  questo include ai sorgenti che il tool concatena e rigenera):    |
//|   1. dopo SD_Core.mqh:   #include "SD_CoreFlow.mqh"               |
//|   2. enum ENUM_SD_MODE:  aggiungi   SDM_FLOW = 6,  // Flow Z v3   |
//|      e in ModeName():    case SDM_FLOW: return "FLOW";            |
//|   3. input (nuovo gruppo): InpFlowN=12, InpFlowM=500,             |
//|      InpFlowThr=1.5, InpFlowDays=20, InpFlowMinSess=5,            |
//|      InpFlowBvc=false (false=CLV), InpFlowWeights=true            |
//|   4. variabile globale   SDFlowParams g_fpar;  riempita in        |
//|      SetupInputs() dagli input del punto 3 (atrPeriod 14,         |
//|      bvcBars 50, weightCap 3.0, runGapBars = InpRunGapBars)       |
//|   5. SetupInputs(): con InpMode == SDM_FLOW usa il ramo a serie   |
//|      singola (g_nSets = 1, g_setMode[0] = SD_MODE_FLOW)           |
//|   6. ProcessTF(): sostituisci                                     |
//|         int warm = SD_BuildSignals(r, n, g_par, dir, bur);        |
//|      con                                                          |
//|         int warm = (g_par.mode == SD_MODE_FLOW)                   |
//|            ? SD_BuildSignalsFlow(r, n, g_fpar, (int)g_tfSec[t],   |
//|                                  dir, bur)                       |
//|            : SD_BuildSignals(r, n, g_par, dir, bur);             |
//|  ADX, regime di volatilita', gestione simulata, scansioni e      |
//|  tabelle del lab lavorano poi sui segnali Flow senza altre        |
//|  modifiche.                                                      |
//+------------------------------------------------------------------+
#ifndef SD_COREFLOW_MQH
#define SD_COREFLOW_MQH

#define SD_MODE_FLOW 6

struct SDFlowParams
  {
   int    flowMode;      // 0 = CLV, 1 = BVC
   int    flowBars;      // N: barre di aggregazione
   int    zWindow;       // M: finestra dello z-score
   double threshold;     // soglia |Z| dell'evento
   int    seasonDays;    // D: sedute di storia per fascia oraria
   int    minSessions;   // campioni minimi per fascia
   double weightCap;     // tetto del peso
   int    atrPeriod;     // ATR (media del TR)
   int    bvcBars;       // BVC: barre per la sigma dei rendimenti
   bool   useWeights;    // false = ogni barra pesa uguale
   int    runGapBars;    // come SDParams.runGapBars (raffica)
  };

//--- erf di Abramowitz-Stegun 7.1.26 (errore max 1.5e-7)
double SD_ErfAS(const double x)
  {
   const double p  = 0.3275911;
   const double a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741;
   const double a4 = -1.453152027, a5 = 1.061405429;
   double s  = (x < 0.0) ? -1.0 : 1.0;
   double ax = MathAbs(x);
   double t  = 1.0 / (1.0 + p * ax);
   return s * (1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * MathExp(-ax * ax));
  }

double SD_NormCdf(const double z)
  {
   return 0.5 * (1.0 + SD_ErfAS(z / 1.4142135623730951));
  }

//--- mediana di n valori di hist[base..base+n-1] (ordinamento per inserimento in tmp)
double SD_FlowMedian(const double &hist[], const int base, const int n, double &tmp[])
  {
   for(int k = 0; k < n; k++)
     {
      double v = hist[base + k];
      int m = k - 1;
      while(m >= 0 && tmp[m] > v)
        {
         tmp[m + 1] = tmp[m];
         m--;
        }
      tmp[m + 1] = v;
     }
   if((n & 1) == 1)
      return tmp[n / 2];
   return 0.5 * (tmp[n / 2 - 1] + tmp[n / 2]);
  }

//+------------------------------------------------------------------+
//| Flow Z (z) e assorbimento (ab) per tutte le barre. EMPTY_VALUE dove |
//| non calcolabile. L'ultima barra (n-1) non viene calcolata: nel lab |
//| e' la barra in formazione. periodSec = durata del TF in secondi.    |
//+------------------------------------------------------------------+
void SD_FlowSeries(const MqlRates &r[], const int n, const SDFlowParams &p, const int periodSec,
                   double &z[], double &ab[])
  {
   ArrayResize(z, n);
   ArrayInitialize(z, EMPTY_VALUE);
   ArrayResize(ab, n);
   ArrayInitialize(ab, EMPTY_VALUE);
   const int N     = MathMax(2, p.flowBars);
   const int M     = MathMax(50, p.zWindow);
   const int D     = MathMax(3, p.seasonDays);
   const int atrP  = MathMax(2, p.atrPeriod);
   const int bvcB  = MathMax(5, p.bvcBars);
   const int first = MathMax(MathMax(atrP, bvcB), N) + 2;
   const int slots = MathMax(1, 86400 / MathMax(1, periodSec));
   if(n < first + 2)
      return;

   double hist[], tmp[], wv[], fb[], cF[], cF2[], cFn[], cA[], cA2[], cAn[];
   int    cnt[], head[];
   ArrayResize(hist, slots * D);
   ArrayResize(tmp, D);
   ArrayResize(cnt, slots);
   ArrayResize(head, slots);
   ArrayInitialize(cnt, 0);
   ArrayInitialize(head, 0);
   ArrayResize(wv, n);
   ArrayResize(fb, n);
   ArrayResize(cF, n);
   ArrayResize(cF2, n);
   ArrayResize(cFn, n);
   ArrayResize(cA, n);
   ArrayResize(cA2, n);
   ArrayResize(cAn, n);

   for(int i = 0; i < n; i++)
     {
      cF[i]  = (i > 0) ? cF[i - 1]  : 0.0;
      cF2[i] = (i > 0) ? cF2[i - 1] : 0.0;
      cFn[i] = (i > 0) ? cFn[i - 1] : 0.0;
      cA[i]  = (i > 0) ? cA[i - 1]  : 0.0;
      cA2[i] = (i > 0) ? cA2[i - 1] : 0.0;
      cAn[i] = (i > 0) ? cAn[i - 1] : 0.0;
      wv[i]  = -1.0;
      fb[i]  = 0.0;

      int slot = (int)(((long)r[i].time % 86400) / periodSec);
      if(slot >= slots) slot = slots - 1;
      if(slot < 0)      slot = 0;
      const double vol = (double)r[i].tick_volume;

      if(i >= first && i < n - 1)
        {
         //--- peso: volume / mediana della stessa fascia oraria nelle D sedute precedenti
         double w = -1.0;
         if(cnt[slot] >= p.minSessions)
           {
            double med = SD_FlowMedian(hist, slot * D, cnt[slot], tmp);
            if(med > 0.0)
               w = MathMin(vol / med, p.weightCap);
           }
         if(w >= 0.0)
           {
            if(!p.useWeights)
               w = 1.0;
            //--- direzione per barra in [-1, 1]
            const double range = r[i].high - r[i].low;
            double dir = 0.0;
            if(p.flowMode == 0)
               dir = (range > 0.0) ? ((r[i].close - r[i].low) - (r[i].high - r[i].close)) / range : 0.0;
            else
              {
               double s2 = 0.0;
               for(int j = i - bvcB + 1; j <= i; j++)
                 {
                  double dd = r[j].close - r[j - 1].close;
                  s2 += dd * dd;
                 }
               double sg = MathSqrt(s2 / bvcB);
               dir = (sg > 0.0) ? 2.0 * SD_NormCdf((r[i].close - r[i - 1].close) / sg) - 1.0 : 0.0;
              }
            wv[i] = w;
            fb[i] = w * dir;
            //--- aggregazione su N barre: media del flusso pesata per attivita'
            double sf = 0.0, sw = 0.0;
            bool   full = true;
            for(int k = 0; k < N; k++)
              {
               int j = i - k;
               if(wv[j] < 0.0)
                 {
                  full = false;
                  break;
                 }
               sf += fb[j];
               sw += wv[j];
              }
            if(full && sw > 0.0)
              {
               const double F      = sf / sw;
               const double effort = sw / N;
               //--- z di F rispetto alle M barre precedenti (barra corrente esclusa)
               const int hi = i - 1;
               const int lo = hi - M;
               double s1 = cF[hi]  - ((lo >= 0) ? cF[lo]  : 0.0);
               double s2 = cF2[hi] - ((lo >= 0) ? cF2[lo] : 0.0);
               double nn = cFn[hi] - ((lo >= 0) ? cFn[lo] : 0.0);
               if(nn >= 0.5 * M)
                 {
                  double mu = s1 / nn;
                  double vr = s2 / nn - mu * mu;
                  if(vr > 1e-12)
                     z[i] = (F - mu) / MathSqrt(vr);
                 }
               cF[i]  += F;
               cF2[i] += F * F;
               cFn[i] += 1.0;
               //--- assorbimento: attivita' alta, spostamento di prezzo piccolo
               double sTR = 0.0;
               for(int j = i - atrP + 1; j <= i; j++)
                  sTR += MathMax(r[j].high, r[j - 1].close) - MathMin(r[j].low, r[j - 1].close);
               double atr = sTR / atrP;
               if(atr > 0.0)
                 {
                  double res = MathAbs(r[i].close - r[i - N].close) / (atr * MathSqrt((double)N));
                  double A   = MathLog(MathMax(effort, 0.05)) - MathLog(res + 0.1);
                  double a1  = cA[hi]  - ((lo >= 0) ? cA[lo]  : 0.0);
                  double a2  = cA2[hi] - ((lo >= 0) ? cA2[lo] : 0.0);
                  double an  = cAn[hi] - ((lo >= 0) ? cAn[lo] : 0.0);
                  if(an >= 0.5 * M)
                    {
                     double mu = a1 / an;
                     double vr = a2 / an - mu * mu;
                     if(vr > 1e-12)
                        ab[i] = (A - mu) / MathSqrt(vr);
                    }
                  cA[i]  += A;
                  cA2[i] += A * A;
                  cAn[i] += 1.0;
                 }
              }
           }
        }

      //--- nella storia stagionale entrano le barre chiuse, DOPO averne calcolato il peso
      if(i < n - 1)
        {
         int h = head[slot];
         hist[slot * D + h] = vol;
         head[slot] = (h + 1) % D;
         if(cnt[slot] < D)
            cnt[slot]++;
        }
     }
  }

//+------------------------------------------------------------------+
//| Segnali di eventi + posizione nella raffica (stessa logica di     |
//| SD_BuildSignals). Restituisce l'indice di warm-up.                |
//+------------------------------------------------------------------+
int SD_BuildSignalsFlow(const MqlRates &r[], const int n, const SDFlowParams &p, const int periodSec,
                        char &dir[], uchar &burst[])
  {
   ArrayResize(dir, n);
   ArrayInitialize(dir, 0);
   ArrayResize(burst, n);
   ArrayInitialize(burst, 0);
   const int N     = MathMax(2, p.flowBars);
   const int first = MathMax(MathMax(MathMax(2, p.atrPeriod), MathMax(5, p.bvcBars)), N) + 2;
   const int warm  = first + N;
   if(n < warm + 3)
      return warm;

   double z[], ab[];
   SD_FlowSeries(r, n, p, periodSec, z, ab);

   int runDir = 0, runCount = 0, gapBars = 0;
   for(int i = 1; i < n - 1; i++)
     {
      int d = 0;
      if(z[i] != EMPTY_VALUE)
        {
         const bool prevUp = (z[i - 1] != EMPTY_VALUE && z[i - 1] >=  p.threshold);
         const bool prevDn = (z[i - 1] != EMPTY_VALUE && z[i - 1] <= -p.threshold);
         if(z[i] >= p.threshold && !prevUp)
            d = 1;
         else if(z[i] <= -p.threshold && !prevDn)
            d = -1;
        }
      //--- raffica (identico a SD_BuildSignals)
      if(d == 0)
        {
         gapBars++;
         if(p.runGapBars > 0 && gapBars >= p.runGapBars)
           {
            runDir = 0;
            runCount = 0;
           }
        }
      else
        {
         gapBars = 0;
         if(d == runDir)
            runCount++;
         else
           {
            runDir = d;
            runCount = 1;
           }
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
