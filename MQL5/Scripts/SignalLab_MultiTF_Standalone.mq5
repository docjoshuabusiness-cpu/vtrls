//+------------------------------------------------------------------+
//| FILE GENERATO da tools/build_standalone.py: non modificarlo a mano.|
//| Contiene SignalLab_MultiTF.mq5 + SD_Core.mqh in un solo file.     |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                          SignalLab_MultiTF.mq5   |
//|  Studio statistico del Synthetic Delta / Expansion dell'EA su    |
//|  TUTTI i timeframe MT5 contemporaneamente, misurato in PUNTI.    |
//|                                                                  |
//|  Cosa fa                                                          |
//|   1. Calcola i segnali a candela chiusa su ogni timeframe con la |
//|      stessa logica dell'EA (SD_Core.mqh).                         |
//|   2. Entra all'open della prima barra M1 dopo la chiusura (+     |
//|      spread reale). M1 e' l'orologio comune: tutti i TF sono     |
//|      misurati sugli stessi istanti e con la stessa risoluzione.  |
//|   3. Per ogni segnale e per ogni orizzonte (minuti) registra     |
//|      MFE, MAE e rendimento a fine orizzonte, in punti.           |
//|   4. Confronta con una BASE abbinata: entrate in direzione       |
//|      casuale, stesso TF, stessa fascia oraria. Cosi' la          |
//|      stagionalita' della volatilita' non passa per edge.         |
//|   5. Tabelle: per TF x orizzonte, superamento di livelli (spunte |
//|      sui target in punti), fascia oraria, candela nel TF         |
//|      superiore, posizione nella raffica, direzione, giorno,      |
//|      classifica delle run piu' lunghe.                           |
//|   6. CLASSIFICA: ipotetica posizione una per volta, tenuta N     |
//|      minuti con target opzionale e senza stop, per TF x fascia   |
//|      oraria x tenuta x target x verso (SEGUI/INVERTI). Si        |
//|      classifica sul primo 70% del periodo e si verifica sul      |
//|      resto. Con segnali senza informazione il netto medio e'     |
//|      -costo per qualunque tenuta e target.                       |
//|                                                                  |
//|  Metrica principale: NETTO MEDIO = rendimento a fine orizzonte   |
//|  nella direzione del segnale meno il costo. MFE/MAE crescono con |
//|  la volatilita': da soli non dimostrano nulla.                   |
//|  Errore standard raggruppato per giorno (cluster) perche' i      |
//|  segnali sono sovrapposti.                                       |
//|                                                                  |
//|  InpMode = DELTA_E_EXP_ADDED (default): in UN SOLO LANCIO calcola |
//|  la serie Delta e la serie EXP_ADDED (segnali che l'Expansion    |
//|  aggiunge), ciascuna con il proprio gruppo di tabelle, piu' una  |
//|  tabella di confronto in cima.                                   |
//|  Esegui su un simbolo alla volta (quello del grafico).           |
//|  Output: MQL5/Files/SignalLab_MultiTF_<simbolo>_<modo>.html e    |
//|          SignalLab_MultiTF_digest_<simbolo>_<modo>.txt           |
//+------------------------------------------------------------------+
#property copyright "SignalLab"
#property version   "1.00"
#property script_show_inputs
#property strict

//--- ============================================================
//--- INIZIO SD_Core.mqh (incorporato: questo file non richiede MQL5/Include)
//--- ============================================================
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
//--- ============================================================
//--- FINE SD_Core.mqh
//--- ============================================================

//--- ================================================================
enum ENUM_SD_MODE
  {
   SDM_DELTA = 0,  // Solo Synthetic Delta
   SDM_EXP   = 1,  // Solo Expansion Candle
   SDM_AND   = 2,  // Entrambi concordi sulla stessa barra (AND)
   SDM_OR    = 3,  // Delta + Expansion: basta uno dei due (OR)
   SDM_ADDED = 4,  // Solo i segnali che l'Expansion AGGIUNGE a Delta (Expansion accesa, Delta spento)
   SDM_DELTA_ADDED = 5  // IN UN SOLO LANCIO: serie DELTA e serie EXP_ADDED, in tabelle distinte + confronto
  };

enum ENUM_NOISE_SORT
  {
   NS_TOTAL = 0,  // Profitto totale in punti sull'intero storico
   NS_MEAN  = 1,  // Netto medio per posizione
   NS_T     = 2   // t-statistic
  };

input group "=== SEGNALE (stessi parametri dell'EA) ==="
input ENUM_SD_MODE InpMode          = SDM_DELTA_ADDED;
input int      InpEmaPeriod         = 13;     // EmaPeriod
input int      InpVolAvgPeriod      = 20;     // VolAvgPeriod
input double   InpThreshold         = 0.15;   // SignalThreshold
input int      InpAtrPeriod         = 14;     // ATR_Period (solo validita' dato)
input int      InpExpAtrPeriod      = 14;     // Inp_ExpATRPeriod
input double   InpExpThreshold      = 1.8;    // Inp_ExpThreshold (TR/ATR)
input int      InpExpConfirmOffset  = 0;      // Inp_ExpConfirmOffset
input int      InpRunGapBars        = 0;      // Inp_RunGapBars (0 = raffica chiusa solo da segnale opposto)

input group "=== STATO DI VOLATILITA' (indicatore Ferro: TR/ATR e percentile) ==="
input bool     InpUseVolState       = true;   // classifica ogni segnale per intensita' e regime di volatilita' (non filtra)
input int      InpVsAtrLen          = 14;     // ATR Length
input int      InpVsLookback        = 100;    // Percentile Lookback (barre)
input int      InpVsEmaSmooth       = 3;      // Smoothing EMA
input double   InpVsExpTh           = 1.8;    // Soglia Espansione (TR/ATR)
input double   InpVsCompTh          = 0.5;    // Soglia Compressione (TR/ATR)
input int      InpVsLowTh           = 30;     // Soglia LOW percentile
input int      InpVsHighTh          = 70;     // Soglia HIGH percentile
input int      InpVsExtremeTh       = 90;     // Soglia EXTREME percentile

input group "=== DATI ==="
input datetime InpFrom              = D'2015.01.01 00:00';
input datetime InpTo                = D'2030.01.01 00:00';
input string   InpTFs               = "ALL";  // ALL oppure lista, es. M1,M5,M15,H1
input int      InpTimeOffsetH       = 0;      // ore da sommare al server time per fasce e giorni
input int      InpMaxGapMin         = 90;     // scarta finestre che contengono un buco di dati > N minuti (weekend, festivi)
input int      InpMaxEntryGapMin    = 5;      // scarta segnali se l'ingresso e' oltre N minuti dopo la chiusura (pausa di sessione)

input group "=== MISURA (tutto in PUNTI) ==="
input string   InpHorizons          = "1,2,3,5,10,15,30,45,60,120,240,1440"; // orizzonti = tempo di tenuta in minuti, uguali per tutti i TF
input int      InpRefHorizon        = 60;     // orizzonte di riferimento per le tabelle di dettaglio
input string   InpLevels            = "50,100,150,200,250,300,350,400,450,500,550,600"; // livelli/target in punti (le spunte e i take profit della classifica)
input double   InpCostPoints        = 0;      // 0 = spread reale della barra M1 d'ingresso
input double   InpExtraCostPts      = 0;      // commissione/slippage extra in punti

input group "=== TABELLE ==="
input int      InpBucketMin         = 15;     // fasce orarie: 1,2,3,4,5,6,10,12,15,20,30,60
input ENUM_TIMEFRAMES InpParentTF   = PERIOD_H1; // TF "contenitore" per la posizione della candela (es. 5a M1 dentro l'H1)
input double   InpMatrixLevel       = 200;    // livello (pt) della matrice giorno x ora: probabilita' di raggiungerlo
input int      InpTopRuns           = 100;    // quante run piu' lunghe elencare
input int      InpMinPerBucket      = 30;     // sotto questa soglia la riga e' grigia (rumore)
input bool     InpDigestTOD         = false;  // include le fasce orarie nel digest (lungo)

input group "=== CLASSIFICA (ipotetica posizione, in-sample / out-of-sample) ==="
input int      InpSplitPct          = 70;     // % iniziale del periodo usata per CLASSIFICARE; il resto serve solo a verificare
input int      InpRankMinN          = 100;    // posizioni minime in-sample perche' una combinazione entri in classifica
input int      InpRankTop           = 30;     // quante righe mostrare nella classifica
input ENUM_NOISE_SORT InpNoiseSort  = NS_TOTAL; // ordinamento della tabella B (con rumore, senza protezione: intero storico)
input ENUM_TIMEFRAMES InpEventTF    = PERIOD_M5; // TF dell'elenco segnali con le spunte
input int      InpEventRows         = 120;    // quanti segnali elencare (campione uniforme su tutto il periodo)

input group "=== CANDELE SUCCESSIVE AL SEGNALE (quanto si muove il prezzo dopo) ==="
input string   InpNextCandles       = "1,2,3,5,10"; // quante candele DOPO il segnale misurare (dello stesso TF del segnale): massimo 8 valori, ciascuno da 1 a 100
input int      InpNextRef           = 1;      // numero di candele di riferimento per le tabelle per orario, intensita' e giorno

//--- ================================================================
#define ACCN 8       // campi per accumulatore: n, mfe, mae, retNet, retNet^2, costo, win, lose
#define BCAP 8       // posizione raffica: 1..7, 8+
#define RKN  5       // campi classifica: n, somma pnl, somma pnl^2, hit, somma MAE
#define NCAT 9       // categorie di stato di volatilita': 3 intensita' + 4 regimi + 2 direzioni del percentile
#define NXF    7     // candele successive, campi: n, favorevole, avverso, range, |chiusura|, chiusura con segno, chiusura con segno^2
#define NXB    64    // classi dell'istogramma logaritmico (favorevole e range) per mediana e 90 percentile
#define NXSTEP 0.2   // ampiezza di una classe dell'istogramma: log(1 + punti)
#define NMEM1  20    // categorie fisse: 0 tutti | 1..7 giorno | 8..13 intensita' | 14..17 regime | 18..19 volatilita' in calo/in salita; poi le fasce orarie

const ENUM_TIMEFRAMES g_allTF[21] =
  {PERIOD_M1, PERIOD_M2, PERIOD_M3, PERIOD_M4, PERIOD_M5, PERIOD_M6, PERIOD_M10, PERIOD_M12,
   PERIOD_M15, PERIOD_M20, PERIOD_M30, PERIOD_H1, PERIOD_H2, PERIOD_H3, PERIOD_H4, PERIOD_H6,
   PERIOD_H8, PERIOD_H12, PERIOD_D1, PERIOD_W1, PERIOD_MN1};
const string g_allName[21] =
  {"M1","M2","M3","M4","M5","M6","M10","M12","M15","M20","M30","H1","H2","H3","H4","H6",
   "H8","H12","D1","W1","MN1"};

//--- parametri derivati
SDParams g_par;
SDVolParams g_vpar;
int      g_volWarm = 0;
int      g_nT = 0;
ENUM_TIMEFRAMES g_tf[];
string   g_tfName[];
long     g_tfSec[];
bool     g_slotOK[];
int      g_slotCnt[];
int      g_maxSlots = 1;
int      g_nH = 0;
int      g_hor[];
int      g_refH = 0;
int      g_nL = 0;
double   g_lev[];
int      g_bMin = 15;
int      g_nB = 96;
long     g_parentSec = 3600;
long     g_off = 0;
double   g_pt = 0.0;
double   g_zB = 3.0;
double   g_minN = 100.0;                // minimo posizioni (>= 1)

//--- serie di segnali analizzate in un solo lancio (0 = Delta, 1 = EXP_ADDED)
int      g_nSets = 1;
int      g_curSet = 0;
int      g_setMode[2];
string   g_setName[2];     // titolo HTML
string   g_setTag[2];      // etichetta semplice (digest)
string   g_setNote[2];
char     g_dirAlt[];       // direzioni della seconda serie, parallele a g_dir
uchar    g_burAlt[];
int      g_tfEvAlt[];
string   g_dgSets = "";
//--- sintesi di ogni serie per la tabella di confronto: indice = serie * g_nT + t
int      g_cmpEv[];
double   g_cmpN[], g_cmpMfe[], g_cmpMae[], g_cmpRet[], g_cmpTcl[];
string   g_cmpDesc[];
double   g_cmpBoN[], g_cmpBoM[], g_cmpBoT[];

//--- candele successive al segnale
int      g_nM = 0, g_nxRef = 0, g_nMem = 0;
int      g_nxM[];                  // numero di candele misurate (crescente)
double   g_ibEdge[5];              // soglie TR/ATR delle 6 classi di intensita'
double   g_nx[];                   // [serie][t][categoria][m][NXF]
int      g_nxh[];                  // [serie][t][categoria][m][2][NXB]: 0 = favorevole, 1 = range
double   g_nxb[];                  // base: [t][categoria][m][NXF] = tutte le barre con ingresso valido, direzione casuale

//--- giorno della settimana x fascia x livello (orizzonte di riferimento)
int      g_dbLev[];        // [t][dow][b][nL+1] segnali: istogramma del n. di livelli <= MFE
int      g_dbBN[];         // [t][dow][b]       barre base
int      g_dbBHist[];      // [t][dow][b][nL+1] base (direzione casuale)

//--- riepilogo scritto: righe (serie, tema, testo) e valori raccolti dalle tabelle di classifica
int      g_cSet[];
string   g_cTopic[], g_cText[];
bool     g_cAok = false, g_cBok = false;
long     g_cAm = 0, g_cBm = 0;
double   g_cAbestT = 0.0, g_cAchance = 0.0;
int      g_cApn = 0, g_cAusable = 0, g_cApos = 0, g_cAstrong = 0, g_cAns = 0;
string   g_cAsurv = "", g_cBdesc = "";
double   g_cBtotal = 0.0, g_cBmean = 0.0, g_cBt = 0.0, g_cBn = 0.0, g_cBshareN = 0.0, g_cBshareLate = 0.0;
int      g_cBboth = 0, g_cBincoh = 0, g_cBusable = 0, g_cBpn = 0;
//--- aggregati per serie, usati dal confronto
double   g_agN[2], g_agNet[2], g_agGross[2];
int      g_agGpos[2], g_agGneg[2], g_agNsig[2], g_agA1ok[2], g_agAns[2], g_agNtf[2];
datetime g_tStart = 0;                  // primo istante M1 effettivamente disponibile nel periodo
bool     g_histWarn = false;            // lo storico M1 inizia molto dopo InpFrom
int      g_rbMin = 15, g_nRB = 96;   // fasce della classifica
int      g_splitDay = 0;             // primo giorno out-of-sample
int      g_evT = -1;                 // indice TF dell'elenco segnali

//--- orologio M1
MqlRates g_r1[];
int      g_n1 = 0;
datetime g_m1Time[];
double   g_m1Open[], g_m1High[], g_m1Low[], g_m1Close[];
int      g_m1Spr[];
ushort   g_m1Bkt[];
int      g_m1Day[];
uchar    g_m1Dow[];
int      g_nextBrk[];
int      g_nDays = 1;
long     g_day0 = 0;
double   g_medRange = 0.0, g_medSpr = 0.0, g_zeroSprPct = 0.0;

//--- finestre forward per l'orizzonte corrente
double   g_fHi[], g_fLo[], g_fCl[];
uchar    g_ok[];
int      g_dqH[], g_dqL[];

//--- barre di ogni TF con ingresso valido (appese in sequenza)
int      g_tfOff[], g_tfCnt[], g_tfBars[], g_tfEv[], g_tfRejGap[], g_tfRejM1[];
int      g_ent[];
uchar    g_vs[];            // codice stato di volatilita' per barra (vedi SD_VolState)
char     g_dir[];
uchar    g_bur[];
ushort   g_slot[];
int      g_used = 0;

//--- accumulatori
double   g_accTH[];       // [t][h][ACCN]
int      g_exFav[], g_exAdv[];   // [t][h][nL+1] istogramma: n. di livelli <= valore
int      g_evBN[];        // [t][h][b] eventi per fascia
int      g_bsN[];         // [t][h][b] barre base per fascia
double   g_bsSum[];       // [t][h][b] somma MFE medio (buy+sell)/2
int      g_bsHist[];      // [t][h][b][nL+1]
double   g_dayS[], g_dayN[];     // [t][h][giorno] cluster del netto
double   g_accBkt[];      // [t][b][ACCN]   (orizzonte di riferimento)
double   g_accSlot[];     // [t][slot][ACCN]
double   g_accBur[];      // [t][BCAP][ACCN]
double   g_accDir[];      // [t][2][ACCN]
double   g_accDow[];      // [t][7][ACCN]
double   g_accCnd[];      // [t][NCAT][ACCN]   stato di volatilita' dei segnali (orizzonte di riferimento)
int      g_cbN[], g_ceN[];       // [t][NCAT][b] barre base / segnali per fascia
double   g_cbSum[];              // [t][NCAT][b] somma MFE medio (buy+sell)/2

//--- classifica ipotetica posizione: [t][fascia][h][kk][dd][smp][RKN]
//    kk: 0 = uscita a solo tempo, 1..nL = target; dd: 0 = segui, 1 = inverti; smp: 0 = IS, 1 = OOS
double   g_rk[];          // una posizione per volta PER FASCIA
double   g_rg[];          // una posizione per volta per TF, tutto il giorno: [t][h][kk][dd][smp][RKN]
long     g_lockB[], g_lockG[];

//--- elenco segnali con spunte
int      g_evCap = 0, g_evCount = 0, g_evSeen = 0, g_evStride = 1;
datetime g_evTime[];
int      g_evDir[], g_evSlot[], g_evBur[], g_evJ[];
double   g_evMfe[], g_evMae[], g_evRet[];
int      g_evMin[];       // [evento][livello] minuti al raggiungimento, -1 = non raggiunto

//--- classifica run piu' lunghe
int      g_topCap = 0, g_topN = 0, g_topMinIdx = 0;
datetime g_tpTime[];
int      g_tpTF[], g_tpDir[], g_tpBur[], g_tpSlot[];
double   g_tpMfe[], g_tpMae[], g_tpRet[], g_tpCost[];

//--- output
int      g_fh = INVALID_HANDLE;
string   g_dg = "";

struct CellStat
  {
   double n, mfe, mae, ret, sd, tNaive, tCl, cost, win, lose, zSign, baseMfe, se, gross, tGross;
  };

//+------------------------------------------------------------------+
//| Utilita'                                                          |
//+------------------------------------------------------------------+
string F0(const double v) { return DoubleToString(v, 0); }
string F1(const double v) { return DoubleToString(v, 1); }
string F2(const double v) { return DoubleToString(v, 2); }
string IS(const long v)   { return IntegerToString(v); }
string Sg(const double v, const int dg = 1) { return string(v > 0.0 ? "+" : "") + DoubleToString(v, dg); }

string HtmlEsc(const string src)
  {
   string o = src;
   StringReplace(o, "&", "&amp;");
   StringReplace(o, "<", "&lt;");
   StringReplace(o, ">", "&gt;");
   return o;
  }

double MedianOf(double &a[], const int n)
  {
   if(n <= 0) return 0.0;
   ArrayResize(a, n);
   ArraySort(a);
   return (n % 2 == 1) ? a[n / 2] : 0.5 * (a[n / 2 - 1] + a[n / 2]);
  }

void W(const string s) { if(g_fh != INVALID_HANDLE) FileWriteString(g_fh, s); }

string Td(const string txt, const string col = "")
  {
   if(col == "") return "<td>" + txt + "</td>";
   return "<td style='color:" + col + "'>" + txt + "</td>";
  }

string ColSign(const double v)
  {
   if(v > 0.0) return "#a3be8c";
   if(v < 0.0) return "#bf616a";
   return "#7b8794";
  }

string ColT(const double t)
  {
   double a = MathAbs(t);
   if(a >= g_zB) return (t > 0.0) ? "#a3be8c" : "#bf616a";
   if(a >= 2.0)  return "#ebcb8b";
   return "#7b8794";
  }

//--- t naive (campioni sovrapposti, nessuna correzione per test multipli): al massimo giallo
string ColTNaive(const double t)
  {
   return (MathAbs(t) >= 2.0) ? "#ebcb8b" : "#7b8794";
  }

double NormSf(const double z)
  {
   double t = 1.0 / (1.0 + 0.2316419 * MathAbs(z));
   double d = 0.3989422804 * MathExp(-z * z / 2.0);
   double p = d * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
   return (z >= 0.0) ? p : 1.0 - p;
  }

//--- soglia |z| bilaterale al 5% con correzione di Bonferroni su m test
double ZCrit(const int m)
  {
   double alpha = 0.05 / (double)MathMax(1, m);
   double lo = 0.0, hi = 10.0;
   for(int k = 0; k < 60; k++)
     {
      double mid = 0.5 * (lo + hi);
      if(2.0 * NormSf(mid) > alpha) lo = mid; else hi = mid;
     }
   return 0.5 * (lo + hi);
  }

int SnapBucket(const int req)
  {
   int valid[] = {1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60};
   int best = 60, bd = 100000;
   for(int i = 0; i < ArraySize(valid); i++)
     {
      int d = MathAbs(valid[i] - req);
      if(d < bd) { bd = d; best = valid[i]; }
     }
   return best;
  }

string SafeTag(const string src)
  {
   string out = src;
   for(int i = 0; i < StringLen(out); i++)
     {
      ushort c = StringGetCharacter(out, i);
      bool ok = ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '.' || c == '-' || c == '_');
      if(!ok) StringSetCharacter(out, i, '_');
     }
   return out;
  }

string ParentName()
  {
   for(int i = 0; i < 21; i++) if(g_allTF[i] == InpParentTF) return g_allName[i];
   return EnumToString(InpParentTF);
  }

string ModeName()
  {
   switch(InpMode)
     {
      case SDM_DELTA: return "DELTA";
      case SDM_EXP:   return "EXPANSION";
      case SDM_AND:   return "AND";
      case SDM_OR:    return "OR";
      case SDM_ADDED: return "EXP_ADDED";
      case SDM_DELTA_ADDED: return "DELTA_E_EXP_ADDED";
     }
   return "?";
  }

string BktLabel(const int b)
  {
   int s = b * g_bMin, e = s + g_bMin;
   return StringFormat("%02d:%02d-%02d:%02d", s / 60, s % 60, e / 60, e % 60);
  }

string DowName(const int d)
  {
   string n[7] = {"Dom", "Lun", "Mar", "Mer", "Gio", "Ven", "Sab"};
   return (d >= 0 && d < 7) ? n[d] : "?";
  }

//+------------------------------------------------------------------+
//| Parsing input                                                     |
//+------------------------------------------------------------------+
void AddTF(const int idx)
  {
   for(int q = 0; q < ArraySize(g_tf); q++)
      if(g_tf[q] == g_allTF[idx]) return;
   int k = ArraySize(g_tf);
   ArrayResize(g_tf, k + 1);
   ArrayResize(g_tfName, k + 1);
   g_tf[k]     = g_allTF[idx];
   g_tfName[k] = g_allName[idx];
  }

bool ParseTFs()
  {
   string s = InpTFs;
   StringTrimLeft(s); StringTrimRight(s); StringToUpper(s);
   ArrayResize(g_tf, 0);
   ArrayResize(g_tfName, 0);
   if(s == "ALL" || s == "")
     { for(int i = 0; i < 21; i++) AddTF(i); }
   else
     {
      string parts[];
      int np = StringSplit(s, ',', parts);
      for(int q = 0; q < np; q++)
        {
         string pp = parts[q];
         StringTrimLeft(pp); StringTrimRight(pp);
         bool known = false;
         for(int i = 0; i < 21; i++)
            if(g_allName[i] == pp) { AddTF(i); known = true; break; }
         if(!known && pp != "") Print("Timeframe sconosciuto in InpTFs: '", pp, "' (ignorato).");
        }
     }
   g_nT = ArraySize(g_tf);
   return (g_nT > 0);
  }

int ParseIntList(const string src, int &out[])
  {
   string parts[];
   int np = StringSplit(src, ',', parts);
   ArrayResize(out, 0);
   for(int i = 0; i < np; i++)
     {
      string pp = parts[i];
      StringTrimLeft(pp); StringTrimRight(pp);
      int v = (int)StringToInteger(pp);
      if(v < 1) continue;
      int k = ArraySize(out);
      bool dup = false;
      for(int q = 0; q < k; q++) if(out[q] == v) { dup = true; break; }
      if(dup) continue;
      ArrayResize(out, k + 1);
      out[k] = v;
     }
   if(ArraySize(out) > 1) ArraySort(out);
   return ArraySize(out);
  }

int ParseDoubleList(const string src, double &out[])
  {
   string parts[];
   int np = StringSplit(src, ',', parts);
   ArrayResize(out, 0);
   for(int i = 0; i < np; i++)
     {
      string pp = parts[i];
      StringTrimLeft(pp); StringTrimRight(pp);
      double v = StringToDouble(pp);
      if(v <= 0.0) continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k] = v;
     }
   if(ArraySize(out) > 1) ArraySort(out);
   return ArraySize(out);
  }

bool SetupInputs()
  {
   if(InpFrom >= InpTo) { Print("InpFrom deve precedere InpTo."); return false; }
   g_minN = MathMax(1.0, (double)InpRankMinN);
   if(!ParseTFs()) { Print("Nessun timeframe valido in InpTFs"); return false; }
   g_nH = ParseIntList(InpHorizons, g_hor);
   if(g_nH < 1) { Print("Nessun orizzonte valido in InpHorizons"); return false; }
   g_refH = 0;
   int bd = 1000000000;
   for(int i = 0; i < g_nH; i++)
     {
      int d = MathAbs(g_hor[i] - InpRefHorizon);
      if(d < bd) { bd = d; g_refH = i; }
     }
   if(g_hor[g_refH] != InpRefHorizon)
      Print("InpRefHorizon ", InpRefHorizon, " non e' fra gli orizzonti: uso ", g_hor[g_refH], " min.");
   g_nL = ParseDoubleList(InpLevels, g_lev);
   if(g_nL < 1)
     {
      Print("InpLevels non valido: uso 100, 500, 1000.");
      ArrayResize(g_lev, 3);
      g_lev[0] = 100; g_lev[1] = 500; g_lev[2] = 1000;
      g_nL = 3;
     }
   g_bMin = SnapBucket(InpBucketMin);
   g_nB   = 1440 / g_bMin;
   g_rbMin = SnapBucket(MathMax(g_bMin, 5));
   g_nRB   = 1440 / g_rbMin;
   g_evT = -1;
   for(int t = 0; t < g_nT; t++) if(g_tf[t] == InpEventTF) g_evT = t;
   if(g_evT < 0) Print("InpEventTF non e' fra i TF analizzati: elenco spunte disattivato.");
   g_parentSec = (long)PeriodSeconds(InpParentTF);
   ArrayResize(g_tfSec, g_nT);
   ArrayResize(g_slotOK, g_nT);
   ArrayResize(g_slotCnt, g_nT);
   g_maxSlots = 1;
   for(int t = 0; t < g_nT; t++)
     {
      g_tfSec[t] = (long)PeriodSeconds(g_tf[t]);
      bool ok = (g_tfSec[t] > 0 && g_tfSec[t] < g_parentSec && g_parentSec <= 86400L &&
                 (g_parentSec % g_tfSec[t]) == 0 && (g_parentSec / g_tfSec[t]) <= 1440);
      g_slotOK[t]  = ok;
      g_slotCnt[t] = ok ? (int)(g_parentSec / g_tfSec[t]) : 0;
      if(g_slotCnt[t] > g_maxSlots) g_maxSlots = g_slotCnt[t];
     }
   {
    bool anySlot = false;
    for(int t = 0; t < g_nT; t++) if(g_slotOK[t]) anySlot = true;
    if(!anySlot)
       Print("InpParentTF ", EnumToString(InpParentTF), " non utilizzabile come contenitore (al massimo D1 e deve contenere almeno un TF analizzato): tabelle 'candela nel TF superiore' disattivate.");
   }

   {
    int tmp[];
    const int nn = ParseIntList(InpNextCandles, tmp);
    ArrayResize(g_nxM, 0);
    for(int i = 0; i < nn && ArraySize(g_nxM) < 8; i++)
       if(tmp[i] <= 100)
         {
          const int k = ArraySize(g_nxM);
          ArrayResize(g_nxM, k + 1);
          g_nxM[k] = tmp[i];
         }
    if(ArraySize(g_nxM) < 1)
      {
       Print("InpNextCandles non valido: uso 1,2,3,5,10.");
       ArrayResize(g_nxM, 5);
       g_nxM[0] = 1; g_nxM[1] = 2; g_nxM[2] = 3; g_nxM[3] = 5; g_nxM[4] = 10;
      }
    g_nM = ArraySize(g_nxM);
    g_nxRef = 0;
    int bdx = 1000000000;
    for(int i = 0; i < g_nM; i++)
      {
       const int dx = MathAbs(g_nxM[i] - InpNextRef);
       if(dx < bdx) { bdx = dx; g_nxRef = i; }
      }
    g_nMem = NMEM1 + g_nB;
    g_ibEdge[0] = InpVsCompTh;
    g_ibEdge[1] = 1.0;
    g_ibEdge[2] = 0.5 * (1.0 + InpVsExpTh);
    g_ibEdge[3] = InpVsExpTh;
    g_ibEdge[4] = 1.4 * InpVsExpTh;
    ArraySort(g_ibEdge);
   }

   g_vpar.atrLen    = MathMax(2, InpVsAtrLen);
   g_vpar.lookback  = MathMax(10, InpVsLookback);
   g_vpar.emaSmooth = MathMax(1, InpVsEmaSmooth);
   g_vpar.expTh     = InpVsExpTh;
   g_vpar.compTh    = InpVsCompTh;
   g_vpar.lowTh     = InpVsLowTh;
   g_vpar.highTh    = InpVsHighTh;
   g_vpar.extremeTh = InpVsExtremeTh;
   g_volWarm        = g_vpar.atrLen + g_vpar.lookback + g_vpar.emaSmooth + 10;

   if(InpMode == SDM_DELTA_ADDED)
     {
      g_nSets = 2;
      g_setMode[0] = SD_MODE_DELTA;  g_setTag[0] = "DELTA";
      g_setName[0] = "DELTA &mdash; solo Synthetic Delta";
      g_setNote[0] = "Segnali emessi dal solo Synthetic Delta, con i parametri dell'EA.";
      g_setMode[1] = SD_MODE_ADDED;  g_setTag[1] = "EXP_ADDED";
      g_setName[1] = "EXP_ADDED &mdash; segnali che l'Expansion aggiunge al Delta";
      g_setNote[1] = "Segnali dell'Expansion Candle (TR/ATR sopra soglia, direzione = colore della candela) sulle barre in cui il Delta <b>non</b> d&agrave; segnale. "
                     "Le due serie non si sovrappongono: nessun segnale della serie Delta compare qui. La posizione nella raffica segue il flusso Delta + Expansion dell'EA.";
     }
   else
     {
      g_nSets = 1;
      g_setMode[0] = (int)InpMode;
      g_setTag[0]  = ModeName();
      g_setName[0] = ModeName();
      g_setNote[0] = "Serie unica scelta con InpMode.";
     }
   g_par.mode             = g_setMode[0];
   g_par.emaPeriod        = MathMax(1, InpEmaPeriod);
   g_par.volAvgPeriod     = MathMax(1, InpVolAvgPeriod);
   g_par.threshold        = InpThreshold;
   g_par.atrPeriod        = MathMax(1, InpAtrPeriod);
   g_par.expAtrPeriod     = MathMax(1, InpExpAtrPeriod);
   g_par.expThreshold     = InpExpThreshold;
   g_par.expConfirmOffset = MathMax(0, InpExpConfirmOffset);
   g_par.runGapBars       = MathMax(0, InpRunGapBars);
   return true;
  }

//+------------------------------------------------------------------+
//| Caricamento storico                                               |
//+------------------------------------------------------------------+
int LoadRates(const ENUM_TIMEFRAMES tf, const datetime from, const datetime to, MqlRates &out[])
  {
   ArraySetAsSeries(out, false);
   int got = -1;
   bool synced = false;
   for(int a = 0; a < 20; a++)
     {
      got = CopyRates(_Symbol, tf, from, to, out);
      if(got > 0 && (bool)SeriesInfoInteger(_Symbol, tf, SERIES_SYNCHRONIZED)) { synced = true; break; }
      if(IsStopped()) break;
      Sleep(250);
     }
   if(!synced) Print("Attenzione: serie ", EnumToString(tf), " non sincronizzata dopo i tentativi (barre ", got, "): lo storico potrebbe essere parziale.");
   return got;
  }

int LoadTF(const int t, MqlRates &r[])
  {
   long f = (long)InpFrom - 300L * g_tfSec[t];
   if(f < 86400L) f = 86400L;
   return LoadRates(g_tf[t], (datetime)f, InpTo, r);
  }

bool LoadM1()
  {
   datetime from = (datetime)((long)InpFrom - 300L * 60L);
   int got = LoadRates(PERIOD_M1, from, InpTo, g_r1);
   int  maxb = (int)TerminalInfoInteger(TERMINAL_MAXBARS);
   long sb   = SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_BARS_COUNT);
   Print("Storico M1: server ", sb, " barre | caricate ", got, " | MAXBARS ", maxb);
   if(sb > maxb)
      Print("!!! Il terminale espone solo ", maxb, " barre su ", sb,
            ". Opzioni > Grafici > Max barre = Illimitato, poi riavvia il terminale.");
   if(got < 1000) { Print("Storico M1 insufficiente (", got, ")."); return false; }

   g_n1 = got;
   ArrayResize(g_m1Time, g_n1);
   ArrayResize(g_m1Open, g_n1);
   ArrayResize(g_m1High, g_n1);
   ArrayResize(g_m1Low,  g_n1);
   ArrayResize(g_m1Close, g_n1);
   ArrayResize(g_m1Spr,  g_n1);
   ArrayResize(g_m1Bkt,  g_n1);
   ArrayResize(g_m1Day,  g_n1);
   ArrayResize(g_m1Dow,  g_n1);
   ArrayResize(g_nextBrk, g_n1);

   g_day0 = (((long)g_r1[0].time) + g_off) / 86400L;
   const long bsec = (long)g_bMin * 60L;
   for(int i = 0; i < g_n1; i++)
     {
      g_m1Time[i]  = g_r1[i].time;
      g_m1Open[i]  = g_r1[i].open;
      g_m1High[i]  = g_r1[i].high;
      g_m1Low[i]   = g_r1[i].low;
      g_m1Close[i] = g_r1[i].close;
      g_m1Spr[i]   = g_r1[i].spread;
      long ts = (long)g_r1[i].time + g_off;
      long dd = ts / 86400L;
      g_m1Bkt[i] = (ushort)((ts % 86400L) / bsec);
      g_m1Day[i] = (int)(dd - g_day0);
      g_m1Dow[i] = (uchar)((dd + 4L) % 7L);
     }
   g_nDays = g_m1Day[g_n1 - 1] + 1;
   if(g_nDays < 1) g_nDays = 1;

   //--- primo istante realmente disponibile nel periodo richiesto
   g_tStart = g_m1Time[g_n1 - 1];
   for(int i = 0; i < g_n1; i++)
      if(g_m1Time[i] >= InpFrom) { g_tStart = g_m1Time[i]; break; }
   g_histWarn = ((long)g_tStart > (long)InpFrom + 7L * 86400L);
   Print("Storico M1 dal ", TimeToString(g_m1Time[0], TIME_DATE | TIME_MINUTES), " al ",
         TimeToString(g_m1Time[g_n1 - 1], TIME_DATE | TIME_MINUTES), " | inizio effettivo del periodo ",
         TimeToString(g_tStart, TIME_DATE));
   if(g_histWarn)
      Print("!!! Lo storico M1 disponibile inizia dopo InpFrom: il periodo analizzato e' piu' corto di quello richiesto.",
            " Scarica piu' storico (F2 History Center) o accorcia InpFrom.");

   //--- buchi di dati: nextBrk[j] = primo k >= j con buco dopo k (altrimenti ultimo indice)
   const long gmax = (long)InpMaxGapMin * 60L;
   int nb = g_n1 - 1;
   g_nextBrk[g_n1 - 1] = g_n1 - 1;
   for(int j = g_n1 - 2; j >= 0; j--)
     {
      if((long)(g_m1Time[j+1] - g_m1Time[j]) > gmax) nb = j;
      g_nextBrk[j] = nb;
     }

   //--- contesto descrittivo (non entra nella logica): range M1 e spread mediani nel periodo
   int stride = MathMax(1, g_n1 / 200000);
   double rg[], sp[];
   ArrayResize(rg, g_n1 / stride + 1);
   ArrayResize(sp, g_n1 / stride + 1);
   int cnt = 0, zero = 0;
   for(int i = 0; i < g_n1; i += stride)
     {
      if(g_m1Time[i] < InpFrom || g_m1Time[i] > InpTo) continue;
      rg[cnt] = (g_m1High[i] - g_m1Low[i]) / g_pt;
      sp[cnt] = (double)g_m1Spr[i];
      if(g_m1Spr[i] == 0) zero++;
      cnt++;
     }
   if(cnt > 0)
     {
      ArrayResize(rg, cnt); ArrayResize(sp, cnt);
      ArraySort(rg); ArraySort(sp);
      g_medRange   = rg[cnt / 2];
      g_medSpr     = sp[cnt / 2];
      g_zeroSprPct = 100.0 * zero / cnt;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| CANDELE SUCCESSIVE AL SEGNALE                                     |
//| Per ogni barra con ingresso valido (segnale o no) misura, dal     |
//| prezzo d'ingresso (open della candela successiva), cosa fanno le  |
//| prossime m candele DELLO STESSO TF: massimo e minimo raggiunti    |
//| (cumulati) e chiusura dell'm-esima. In punti, lordo di spread.    |
//| Le barre senza segnale alimentano la BASE (direzione casuale).    |
//+------------------------------------------------------------------+
int NxBin(const double v)
  {
   if(v <= 0.0) return 0;
   const int b = (int)(MathLog(1.0 + v) / NXSTEP);
   return (b >= NXB) ? NXB - 1 : b;
  }

void NxBar(const int t, const MqlRates &r[], const int n, const int i, const int mp,
           const long xs, const bool chk, const long gapSec, const int ib, const uchar vs,
           const int d0, const int d1)
  {
   const double o       = r[i + 1].open;
   const int    maxM    = g_nxM[g_nM - 1];
   const long   lastEnd = (long)g_m1Time[g_n1 - 1] + 60L;
   double hi = r[i + 1].high, lo = r[i + 1].low;
   double up[8], dn[8], mv[8];
   int mi = 0;
   for(int kk = 1; kk <= maxM; kk++)
     {
      const int x = i + kk;
      if(x >= n) break;                                                       // storico finito
      if(chk && ((long)(r[x].time - r[x - 1].time) - xs) > gapSec) break;     // buco di dati fra due candele (intraday)
      if(x == n - 1 && ((long)r[x].time + xs) > lastEnd) break;               // ultima candela ancora in formazione
      if(r[x].high > hi) hi = r[x].high;
      if(r[x].low  < lo) lo = r[x].low;
      if(g_nxM[mi] == kk)
        {
         up[mi] = (hi - o) / g_pt;
         dn[mi] = (o - lo) / g_pt;
         mv[mi] = (r[x].close - o) / g_pt;
         mi++;
         if(mi >= g_nM) break;
        }
     }
   if(mi < 1) return;

   //--- categorie a cui appartiene la barra
   int mem[6];
   int nm = 0;
   mem[nm] = 0;                              nm++;
   mem[nm] = 1 + (int)g_m1Dow[mp];           nm++;
   if(ib >= 0 && ib < 6) { mem[nm] = 8 + ib; nm++; }
   if(InpUseVolState && vs != 255)
     {
      mem[nm] = 14 + ((vs >> 1) & 3);        nm++;
      mem[nm] = 18 + (vs & 1);               nm++;
     }
   mem[nm] = NMEM1 + (int)g_m1Bkt[mp];       nm++;

   //--- base: ogni barra, direzione casuale (favorevole = avverso = meta' del range)
   double rg[8];
   for(int k = 0; k < mi; k++) rg[k] = up[k] + dn[k];
   for(int q = 0; q < nm; q++)
      for(int k = 0; k < mi; k++)
        {
         const int p = ((t * g_nMem + mem[q]) * g_nM + k) * NXF;
         g_nxb[p]     += 1.0;
         g_nxb[p + 1] += 0.5 * rg[k];
         g_nxb[p + 2] += 0.5 * rg[k];
         g_nxb[p + 3] += rg[k];
         g_nxb[p + 4] += MathAbs(mv[k]);
        }

   //--- segnali di ciascuna serie
   int ds[2];
   ds[0] = d0; ds[1] = d1;
   int bR[8], bF[8];
   for(int s = 0; s < g_nSets; s++)
     {
      const int d = ds[s];
      if(d == 0) continue;
      for(int k = 0; k < mi; k++)
        {
         bR[k] = NxBin(rg[k]);
         bF[k] = NxBin((d > 0) ? up[k] : dn[k]);
        }
      for(int q = 0; q < nm; q++)
         for(int k = 0; k < mi; k++)
           {
            const int    cellI = (((s * g_nT + t) * g_nMem + mem[q]) * g_nM + k);
            const int    p     = cellI * NXF;
            const double fav   = (d > 0) ? up[k] : dn[k];
            const double adv   = (d > 0) ? dn[k] : up[k];
            const double sm    = (d > 0) ? mv[k] : -mv[k];
            g_nx[p]     += 1.0;
            g_nx[p + 1] += fav;
            g_nx[p + 2] += adv;
            g_nx[p + 3] += rg[k];
            g_nx[p + 4] += MathAbs(mv[k]);
            g_nx[p + 5] += sm;
            g_nx[p + 6] += sm * sm;
            g_nxh[cellI * 2 * NXB + bF[k]]++;
            g_nxh[cellI * 2 * NXB + NXB + bR[k]]++;
           }
     }
  }

//+------------------------------------------------------------------+
//| Per un TF: segnali + mappa verso l'ingresso M1                    |
//+------------------------------------------------------------------+
void ProcessTF(const int t, const MqlRates &r[], const int n)
  {
   g_tfOff[t] = g_used;
   g_tfCnt[t] = 0;
   if(n < 60) { Print("TF ", g_tfName[t], ": storico insufficiente (", n, " barre)"); return; }

   char  dir[];
   uchar bur[];
   int   warm = SD_BuildSignals(r, n, g_par, dir, bur);
   char  dir2[];
   uchar bur2[];
   if(g_nSets > 1)
     {
      SDParams p2 = g_par;
      p2.mode = g_setMode[1];
      SD_BuildSignals(r, n, p2, dir2, bur2);
     }
   uchar vsc[];
   if(InpUseVolState)
     {
      SD_VolState(r, n, g_vpar, g_pt, vsc);       // il warm-up dei segnali resta quello del segnale: lo stato ha il suo (g_volWarm)
     }
   uchar ibn[];
   SD_IntensityBins(r, n, g_vpar.atrLen, g_ibEdge, ibn);      // intensita' della candela del segnale (TR/ATR), anche senza stato di volatilita'

   const long   xs      = g_tfSec[t];
   const long   maxGap  = (long)InpMaxEntryGapMin * 60L;
   const bool   slotOK  = g_slotOK[t];
   const bool   isMN    = (g_tf[t] == PERIOD_MN1);

   int need = g_used + n;
   ArrayResize(g_ent,  need, 2000000);
   ArrayResize(g_dir,  need, 2000000);
   ArrayResize(g_bur,  need, 2000000);
   ArrayResize(g_slot, need, 2000000);
   ArrayResize(g_vs,   need, 2000000);
   if(g_nSets > 1) { ArrayResize(g_dirAlt, need, 2000000); ArrayResize(g_burAlt, need, 2000000); }

   int u = g_used, p = 0;
   int bars = 0, rejGap = 0, rejM1 = 0, ev = 0, ev2 = 0;
   for(int i = warm; i < n - 1; i++)
     {
      datetime tNext = r[i+1].time;
      if(tNext < InpFrom || tNext > InpTo) continue;
      bars++;
      long spacing = (long)(tNext - r[i].time);
      if(!isMN && (spacing - xs) > maxGap) { rejGap++; continue; }
      while(p < g_n1 && g_m1Time[p] < tNext) p++;
      if(p >= g_n1) break;
      if((long)(g_m1Time[p] - tNext) > maxGap) { rejM1++; continue; }
      g_ent[u]  = p;
      g_dir[u]  = dir[i];
      g_bur[u]  = bur[i];
      if(g_nSets > 1) { g_dirAlt[u] = dir2[i]; g_burAlt[u] = bur2[i]; if(dir2[i] != 0) ev2++; }
      g_vs[u]   = InpUseVolState ? ((i >= g_volWarm) ? vsc[i] : (uchar)255) : (uchar)10;   // 255 = finestra del percentile incompleta
      g_slot[u] = (ushort)(slotOK ? (int)(((long)r[i].time % g_parentSec) / xs) : 0);
      if(dir[i] != 0) ev++;
      NxBar(t, r, n, i, p, xs, (xs < 86400L), (long)InpMaxGapMin * 60L, (int)ibn[i], g_vs[u], (int)dir[i],
            (g_nSets > 1) ? (int)dir2[i] : 0);
      u++;
     }
   g_tfCnt[t]    = u - g_used;
   g_used        = u;
   g_tfBars[t]   = bars;
   g_tfEv[t]     = ev;
   g_tfEvAlt[t]  = ev2;
   g_tfRejGap[t] = rejGap;
   g_tfRejM1[t]  = rejM1;
   ArrayResize(g_ent,  g_used);
   ArrayResize(g_dir,  g_used);
   ArrayResize(g_bur,  g_used);
   ArrayResize(g_slot, g_used);
   ArrayResize(g_vs,   g_used);
   if(g_nSets > 1) { ArrayResize(g_dirAlt, g_used); ArrayResize(g_burAlt, g_used); }
   Print("TF ", g_tfName[t], ": barre ", n, " | in periodo ", bars, " | segnali ", ev, (g_nSets > 1 ? (" / " + IntegerToString(ev2) + " (EXP_ADDED)") : ""),
         " | scartate gap sessione ", rejGap, " | senza M1 ", rejM1);
  }

//+------------------------------------------------------------------+
//| Accumulatori                                                      |
//+------------------------------------------------------------------+
bool AllocAcc()
  {
   int cTH = g_nT * g_nH;
   ArrayResize(g_accTH, cTH * ACCN);               ArrayInitialize(g_accTH, 0.0);
   ArrayResize(g_exFav, cTH * (g_nL + 1));         ArrayInitialize(g_exFav, 0);
   ArrayResize(g_exAdv, cTH * (g_nL + 1));         ArrayInitialize(g_exAdv, 0);
   ArrayResize(g_evBN,  cTH * g_nB);               ArrayInitialize(g_evBN, 0);
   ArrayResize(g_bsN,   cTH * g_nB);               ArrayInitialize(g_bsN, 0);
   ArrayResize(g_bsSum, cTH * g_nB);               ArrayInitialize(g_bsSum, 0.0);
   ArrayResize(g_bsHist, cTH * g_nB * (g_nL + 1)); ArrayInitialize(g_bsHist, 0);
   ArrayResize(g_dayS,  cTH * g_nDays);            ArrayInitialize(g_dayS, 0.0);
   ArrayResize(g_dayN,  cTH * g_nDays);            ArrayInitialize(g_dayN, 0.0);
   ArrayResize(g_accBkt,  g_nT * g_nB * ACCN);        ArrayInitialize(g_accBkt, 0.0);
   ArrayResize(g_accSlot, g_nT * g_maxSlots * ACCN);  ArrayInitialize(g_accSlot, 0.0);
   ArrayResize(g_accBur,  g_nT * BCAP * ACCN);        ArrayInitialize(g_accBur, 0.0);
   ArrayResize(g_accDir,  g_nT * 2 * ACCN);           ArrayInitialize(g_accDir, 0.0);
   ArrayResize(g_accDow,  g_nT * 7 * ACCN);           ArrayInitialize(g_accDow, 0.0);

   g_topCap = MathMin(1000, MathMax(0, InpTopRuns));
   g_topN = 0; g_topMinIdx = 0;
   int c = MathMax(1, g_topCap);
   ArrayResize(g_tpTime, c); ArrayResize(g_tpTF, c); ArrayResize(g_tpDir, c);
   ArrayResize(g_tpBur, c);  ArrayResize(g_tpSlot, c);
   ArrayResize(g_tpMfe, c);  ArrayResize(g_tpMae, c); ArrayResize(g_tpRet, c); ArrayResize(g_tpCost, c);

   //--- giorno x fascia x livello
   ArrayResize(g_dbLev,   g_nT * 7 * g_nB * (g_nL + 1)); ArrayInitialize(g_dbLev, 0);
   ArrayResize(g_dbBN,    g_nT * 7 * g_nB);              ArrayInitialize(g_dbBN, 0);
   ArrayResize(g_dbBHist, g_nT * 7 * g_nB * (g_nL + 1)); ArrayInitialize(g_dbBHist, 0);

   //--- stato di volatilita'
   ArrayResize(g_accCnd, g_nT * NCAT * ACCN);      ArrayInitialize(g_accCnd, 0.0);
   ArrayResize(g_cbN,  g_nT * NCAT * g_nB);        ArrayInitialize(g_cbN, 0);
   ArrayResize(g_ceN,  g_nT * NCAT * g_nB);        ArrayInitialize(g_ceN, 0);
   ArrayResize(g_cbSum, g_nT * NCAT * g_nB);       ArrayInitialize(g_cbSum, 0.0);

   //--- classifica ipotetica posizione
   int blk = (g_nL + 1) * 4 * RKN;
   long szK = (long)g_nT * g_nRB * g_nH * blk;
   Print("Classifica: ", szK, " celle (", DoubleToString(szK * 8.0 / 1048576.0, 0), " MB)");
   if(szK > 400000000L || ArrayResize(g_rk, (int)szK) != (int)szK)
     {
      Print("Memoria insufficiente per la classifica (", szK, " celle): riduci orizzonti, livelli o TF, oppure allarga le fasce.");
      return false;
     }
   ArrayInitialize(g_rk, 0.0);
   ArrayResize(g_rg, g_nT * g_nH * blk);        ArrayInitialize(g_rg, 0.0);
   ArrayResize(g_lockB, g_nT * g_nH * g_nRB);   ArrayInitialize(g_lockB, 0);
   ArrayResize(g_lockG, g_nT * g_nH);           ArrayInitialize(g_lockG, 0);

   //--- elenco segnali con spunte
   g_evCap = (g_evT >= 0) ? MathMax(0, InpEventRows) : 0;
   g_evCount = 0; g_evSeen = 0;
   g_evStride = (g_evCap > 0) ? MathMax(1, (g_tfEv[g_evT] + g_evCap - 1) / g_evCap) : 1;
   int ce = MathMax(1, g_evCap);
   ArrayResize(g_evTime, ce); ArrayResize(g_evDir, ce); ArrayResize(g_evSlot, ce);
   ArrayResize(g_evBur, ce);  ArrayResize(g_evJ, ce);
   ArrayResize(g_evMfe, ce);  ArrayResize(g_evMae, ce); ArrayResize(g_evRet, ce);
   ArrayResize(g_evMin, ce * g_nL);
   return true;
  }

void AddAcc(double &a[], const int cell, const double fav, const double adv,
            const double retN, const double cost)
  {
   int p = cell * ACCN;
   a[p]     += 1.0;
   a[p + 1] += fav;
   a[p + 2] += adv;
   a[p + 3] += retN;
   a[p + 4] += retN * retN;
   a[p + 5] += cost;
   if(fav > adv)      a[p + 6] += 1.0;
   else if(adv > fav) a[p + 7] += 1.0;
  }

void TopInsert(const datetime tm, const int t, const int d, const double fav, const double adv,
               const double ret, const double cost, const int bur, const int slot)
  {
   if(g_topCap <= 0) return;
   int pos;
   if(g_topN < g_topCap) pos = g_topN++;
   else
     {
      if(fav <= g_tpMfe[g_topMinIdx]) return;
      pos = g_topMinIdx;
     }
   g_tpTime[pos] = tm;  g_tpTF[pos] = t;   g_tpDir[pos] = d;
   g_tpMfe[pos]  = fav; g_tpMae[pos] = adv; g_tpRet[pos] = ret;
   g_tpCost[pos] = cost; g_tpBur[pos] = bur; g_tpSlot[pos] = slot;
   if(g_topN == g_topCap)
     {
      int mi = 0;
      for(int q = 1; q < g_topN; q++) if(g_tpMfe[q] < g_tpMfe[mi]) mi = q;
      g_topMinIdx = mi;
     }
  }

//+------------------------------------------------------------------+
//| Finestre forward sull'orologio M1, basate sul TEMPO (non sul      |
//| numero di barre): max high, min low e close finale entro H minuti |
//| dall'open della barra d'ingresso. Deque monotone: O(N) per H.     |
//+------------------------------------------------------------------+
void ComputeForward(const int hMin)
  {
   const long Hs = (long)hMin * 60L;
   int hd = 0, ht = 0, ld = 0, lt = 0, e = 0;
   for(int j = 0; j < g_n1; j++)
     {
      long tEnd = (long)g_m1Time[j] + Hs;
      while(e < g_n1 && (long)g_m1Time[e] < tEnd)
        {
         while(ht > hd && g_m1High[g_dqH[ht-1]] <= g_m1High[e]) ht--;
         g_dqH[ht++] = e;
         while(lt > ld && g_m1Low[g_dqL[lt-1]] >= g_m1Low[e]) lt--;
         g_dqL[lt++] = e;
         e++;
        }
      while(ht > hd && g_dqH[hd] < j) hd++;
      while(lt > ld && g_dqL[ld] < j) ld++;
      //--- finestra completa: nessun buco dati fra le barre j..e-1 e, se un buco segue la barra e-1,
      //    quella barra deve comunque coprire tEnd (altrimenti l'orizzonte risulterebbe troncato)
      bool ok = (e < g_n1 && e > j && ht > hd && lt > ld &&
                 (g_nextBrk[j] >= e || (g_nextBrk[j] == e - 1 && (long)g_m1Time[e - 1] + 60L >= tEnd)));
      g_ok[j] = ok ? 1 : 0;
      if(ok)
        {
         g_fHi[j] = g_m1High[g_dqH[hd]];
         g_fLo[j] = g_m1Low[g_dqL[ld]];
         g_fCl[j] = g_m1Close[e - 1];
        }
     }
  }

//+------------------------------------------------------------------+
//| Ipotetica posizione: per ogni target (kk) e verso (dd) il risultato|
//| netto e': +target se il movimento favorevole NETTO raggiunge il   |
//| target entro la tenuta, altrimenti il rendimento netto a fine     |
//| tenuta. Nessuno stop. Valori gia' al netto del costo d'ingresso.  |
//+------------------------------------------------------------------+
void AddRank(double &a[], const int base, const int smp,
             const double mfeF, const double maeF, const double retF,
             const double mfeI, const double maeI, const double retI)
  {
   for(int kk = 0; kk <= g_nL; kk++)
     {
      const double lv = (kk == 0) ? 0.0 : g_lev[kk - 1];
      for(int dd = 0; dd < 2; dd++)
        {
         const double mfe = (dd == 0) ? mfeF : mfeI;
         const double mae = (dd == 0) ? maeF : maeI;
         const double ret = (dd == 0) ? retF : retI;
         const bool   hit = (kk > 0 && mfe >= lv);
         const double pnl = hit ? lv : ret;
         const int p = base + (((kk * 2 + dd) * 2 + smp) * RKN);
         a[p]     += 1.0;
         a[p + 1] += pnl;
         a[p + 2] += pnl * pnl;
         if(hit) a[p + 3] += 1.0;
         a[p + 4] += mae;
        }
     }
  }

struct RkStat
  {
   double n, mean, t, hit, mae, sum;
  };

void RkRead(const double &a[], const int base, const int kk, const int dd, const int smp, RkStat &s)
  {
   const int p = base + (((kk * 2 + dd) * 2 + smp) * RKN);
   double n = a[p];
   s.n = n; s.mean = 0.0; s.t = 0.0; s.hit = 0.0; s.mae = 0.0; s.sum = 0.0;
   if(n < 1.0) return;
   s.sum  = a[p + 1];
   s.mean = a[p + 1] / n;
   double var = (n > 1.0) ? (a[p + 2] - n * s.mean * s.mean) / (n - 1.0) : 0.0;
   double sd  = (var > 0.0) ? MathSqrt(var) : 0.0;
   s.t   = (sd > 0.0) ? s.mean / (sd / MathSqrt(n)) : 0.0;
   s.hit = 100.0 * a[p + 3] / n;
   s.mae = a[p + 4] / n;
  }

//--- statistiche sull'INTERO storico (in-sample + out-of-sample sommati)
void RkReadAll(const double &a[], const int base, const int kk, const int dd, RkStat &s)
  {
   const int p0 = base + (((kk * 2 + dd) * 2 + 0) * RKN);
   const int p1 = base + (((kk * 2 + dd) * 2 + 1) * RKN);
   double n = a[p0] + a[p1];
   s.n = n; s.mean = 0.0; s.t = 0.0; s.hit = 0.0; s.mae = 0.0; s.sum = 0.0;
   if(n < 1.0) return;
   double sm = a[p0 + 1] + a[p1 + 1];
   double s2 = a[p0 + 2] + a[p1 + 2];
   s.sum  = sm;
   s.mean = sm / n;
   double var = (n > 1.0) ? (s2 - n * s.mean * s.mean) / (n - 1.0) : 0.0;
   double sd  = (var > 0.0) ? MathSqrt(var) : 0.0;
   s.t   = (sd > 0.0) ? s.mean / (sd / MathSqrt(n)) : 0.0;
   s.hit = 100.0 * (a[p0 + 3] + a[p1 + 3]) / n;
   s.mae = (a[p0 + 4] + a[p1 + 4]) / n;
  }

//+------------------------------------------------------------------+
//| Misura di tutti i segnali e di tutte le barre-base per un         |
//| orizzonte. Convenzione dei costi come SignalLab: l'ingresso paga  |
//| lo spread, MFE/MAE/rendimento lordi sono dall'open d'ingresso.    |
//+------------------------------------------------------------------+
void AccumulateHorizon(const int hi)
  {
   const double pt  = g_pt;
   const bool isRef = (hi == g_refH);
   const int  nL1   = g_nL + 1;
   const int  rkBlk = (g_nL + 1) * 4 * RKN;
   const long Hs    = (long)g_hor[hi] * 60L;
   for(int t = 0; t < g_nT; t++)
     {
      const int cell = t * g_nH + hi;
      const int k0 = g_tfOff[t];
      const int k1 = k0 + g_tfCnt[t];
      for(int k = k0; k < k1; k++)
        {
         const int j = g_ent[k];
         if(g_ok[j] == 0) continue;
         const double o  = g_m1Open[j];
         const double mB = (g_fHi[j] - o) / pt;     // MFE se compro
         const double mS = (o - g_fLo[j]) / pt;     // MFE se vendo
         const int    b  = (int)g_m1Bkt[j];
         const int    bi = cell * g_nB + b;

         //--- base: tutte le barre, direzione casuale
         g_bsN[bi]++;
         g_bsSum[bi] += 0.5 * (mB + mS);
         int cb = 0; while(cb < g_nL && mB >= g_lev[cb]) cb++;
         int cs = 0; while(cs < g_nL && mS >= g_lev[cs]) cs++;
         g_bsHist[bi * nL1 + cb]++;
         g_bsHist[bi * nL1 + cs]++;
         if(isRef)
           {
            const int dbi = (t * 7 + (int)g_m1Dow[j]) * g_nB + b;
            g_dbBN[dbi]++;
            g_dbBHist[dbi * nL1 + cb]++;
            g_dbBHist[dbi * nL1 + cs]++;
           }
         if(isRef && InpUseVolState && g_vs[k] != 255)
           {
            const int    vc = (int)g_vs[k];
            const double bm = 0.5 * (mB + mS);
            int ib = (t * NCAT + ((vc >> 3) & 3)) * g_nB + b;       g_cbN[ib]++; g_cbSum[ib] += bm;
            ib     = (t * NCAT + 3 + ((vc >> 1) & 3)) * g_nB + b;   g_cbN[ib]++; g_cbSum[ib] += bm;
            ib     = (t * NCAT + 7 + (vc & 1)) * g_nB + b;          g_cbN[ib]++; g_cbSum[ib] += bm;
           }

         //--- segnali
         const int d = (int)g_dir[k];
         if(d == 0) continue;
         const double fav  = (d > 0) ? mB : mS;
         const double adv  = (d > 0) ? mS : mB;
         const double retG = (d > 0) ? (g_fCl[j] - o) / pt : (o - g_fCl[j]) / pt;
         const double cost = ((InpCostPoints > 0.0) ? InpCostPoints : (double)g_m1Spr[j]) + InpExtraCostPts;
         const double retN = retG - cost;

         AddAcc(g_accTH, cell, fav, adv, retN, cost);
         g_evBN[bi]++;
         int cf = 0; while(cf < g_nL && fav >= g_lev[cf]) cf++;
         int ca = 0; while(ca < g_nL && adv >= g_lev[ca]) ca++;
         g_exFav[cell * nL1 + cf]++;
         g_exAdv[cell * nL1 + ca]++;
         int di = cell * g_nDays + g_m1Day[j];
         g_dayS[di] += retN;
         g_dayN[di] += 1.0;

         //--- ipotetica posizione tenuta H minuti, una per volta (per TF e per fascia)
         {
          const long   tj  = (long)g_m1Time[j];
          const int    smp = (g_m1Day[j] >= g_splitDay) ? 1 : 0;
          const double mfeF = fav - cost, maeF = adv + cost;
          const double mfeI = adv - cost, maeI = fav + cost, retI = -retG - cost;
          if(g_lockG[cell] == 0 || (tj - g_lockG[cell]) >= Hs)
            {
             g_lockG[cell] = tj;
             AddRank(g_rg, cell * rkBlk, smp, mfeF, maeF, retN, mfeI, maeI, retI);
            }
          const int rb = (int)((((long)g_m1Time[j] + g_off) % 86400L) / ((long)g_rbMin * 60L));
          const int lb = cell * g_nRB + rb;
          if(g_lockB[lb] == 0 || (tj - g_lockB[lb]) >= Hs)
            {
             g_lockB[lb] = tj;
             AddRank(g_rk, ((t * g_nRB + rb) * g_nH + hi) * rkBlk, smp, mfeF, maeF, retN, mfeI, maeI, retI);
            }
         }

         if(isRef)
           {
            if(t == g_evT && g_evCap > 0)
              {
               g_evSeen++;
               if(g_evCount < g_evCap && ((g_evSeen - 1) % g_evStride) == 0)
                 {
                  int q = g_evCount++;
                  g_evTime[q] = g_m1Time[j]; g_evDir[q] = d; g_evSlot[q] = (int)g_slot[k];
                  g_evBur[q]  = (int)g_bur[k]; g_evJ[q] = j;
                  g_evMfe[q]  = fav; g_evMae[q] = adv; g_evRet[q] = retN;
                 }
              }
            g_dbLev[((t * 7 + (int)g_m1Dow[j]) * g_nB + b) * nL1 + cf]++;
            if(InpUseVolState && g_vs[k] != 255)
              {
               const int vc2 = (int)g_vs[k];
               const int cA = (vc2 >> 3) & 3, cB = 3 + ((vc2 >> 1) & 3), cC = 7 + (vc2 & 1);
               AddAcc(g_accCnd, t * NCAT + cA, fav, adv, retN, cost);
               AddAcc(g_accCnd, t * NCAT + cB, fav, adv, retN, cost);
               AddAcc(g_accCnd, t * NCAT + cC, fav, adv, retN, cost);
               g_ceN[(t * NCAT + cA) * g_nB + b]++;
               g_ceN[(t * NCAT + cB) * g_nB + b]++;
               g_ceN[(t * NCAT + cC) * g_nB + b]++;
              }
            AddAcc(g_accBkt, t * g_nB + b, fav, adv, retN, cost);
            if(g_slotOK[t]) AddAcc(g_accSlot, t * g_maxSlots + (int)g_slot[k], fav, adv, retN, cost);
            int bc = MathMin((int)g_bur[k], BCAP) - 1;
            if(bc < 0) bc = 0;
            AddAcc(g_accBur, t * BCAP + bc, fav, adv, retN, cost);
            AddAcc(g_accDir, t * 2 + ((d > 0) ? 0 : 1), fav, adv, retN, cost);
            AddAcc(g_accDow, t * 7 + (int)g_m1Dow[j], fav, adv, retN, cost);
            TopInsert(g_m1Time[j], t, d, fav, adv, retN, cost, (int)g_bur[k], (int)g_slot[k]);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Statistiche di una cella (TF, orizzonte)                          |
//+------------------------------------------------------------------+
double SuffixCount(const int &arr[], const int base, const int l)
  {
   double s = 0.0;
   for(int c = l + 1; c <= g_nL; c++) s += (double)arr[base + c];
   return s;
  }

double BaseExcMatched(const int t, const int h, const int l)
  {
   const int cell = t * g_nH + h;
   double num = 0.0, den = 0.0;
   for(int b = 0; b < g_nB; b++)
     {
      int bi = cell * g_nB + b;
      int en = g_evBN[bi];
      if(en <= 0 || g_bsN[bi] <= 0) continue;
      double pr = SuffixCount(g_bsHist, bi * (g_nL + 1), l) / (2.0 * (double)g_bsN[bi]);
      num += (double)en * pr;
      den += (double)en;
     }
   return (den > 0.0) ? num / den : 0.0;
  }

bool GetCell(const int t, const int h, CellStat &s)
  {
   const int cell = t * g_nH + h;
   const int p = cell * ACCN;
   double n = g_accTH[p];
   if(n < 1.0) return false;
   s.n    = n;
   s.mfe  = g_accTH[p + 1] / n;
   s.mae  = g_accTH[p + 2] / n;
   s.ret  = g_accTH[p + 3] / n;
   s.cost = g_accTH[p + 5] / n;
   double var = (n > 1.0) ? (g_accTH[p + 4] - n * s.ret * s.ret) / (n - 1.0) : 0.0;
   s.sd     = (var > 0.0) ? MathSqrt(var) : 0.0;
   s.tNaive = (s.sd > 0.0) ? s.ret / (s.sd / MathSqrt(n)) : 0.0;

   //--- errore standard raggruppato per giorno
   double ss = 0.0;
   const int base = cell * g_nDays;
   for(int d = 0; d < g_nDays; d++)
     {
      double nn = g_dayN[base + d];
      if(nn <= 0.0) continue;
      double dev = g_dayS[base + d] - nn * s.ret;
      ss += dev * dev;
     }
   double se = MathSqrt(ss) / n;
   s.tCl = (se > 0.0) ? s.ret / se : 0.0;
   s.se     = se;
   s.gross  = s.ret + s.cost;                 // rendimento medio prima dei costi
   s.tGross = (se > 0.0) ? s.gross / se : 0.0;

   s.win  = g_accTH[p + 6];
   s.lose = g_accTH[p + 7];
   s.zSign = (s.win + s.lose > 0.0) ? (s.win - s.lose) / MathSqrt(s.win + s.lose) : 0.0;

   //--- MFE della base, pesata sulla distribuzione oraria degli eventi
   double num = 0.0, den = 0.0;
   for(int b = 0; b < g_nB; b++)
     {
      int bi = cell * g_nB + b;
      int en = g_evBN[bi];
      if(en <= 0 || g_bsN[bi] <= 0) continue;
      num += (double)en * (g_bsSum[bi] / (double)g_bsN[bi]);
      den += (double)en;
     }
   s.baseMfe = (den > 0.0) ? num / den : 0.0;
   return true;
  }

string AccCell(const double &a[], const int p)
  {
   double n = a[p];
   if(n < 1.0) return "<td>-</td>";
   double ret = a[p + 3] / n;
   double var = (n > 1.0) ? (a[p + 4] - n * ret * ret) / (n - 1.0) : 0.0;
   double tn  = (var > 0.0) ? ret / (MathSqrt(var) / MathSqrt(n)) : 0.0;
   string col = (n < InpMinPerBucket) ? "#4c566a" : ColTNaive(tn);
   return Td(F1(ret) + " <span style='color:#4c566a'>(" + F0(n) + ")</span>", col);
  }

//+------------------------------------------------------------------+
//| REPORT                                                            |
//+------------------------------------------------------------------+
void RepHead()
  {
   W("<!doctype html><html><head><meta charset='utf-8'><title>SignalLab MultiTF</title><style>");
   W("body{background:#14161a;color:#d8dee9;font:13px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;margin:24px}");
   W("h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;margin:26px 0 8px;color:#88c0d0;border-bottom:1px solid #2e3440;padding-bottom:4px}");
   W("h3{font-size:13px;margin:16px 0 4px;color:#8fbcbb}");
   W("table{border-collapse:collapse;margin:8px 0;font-size:12px}td,th{border:1px solid #2e3440;padding:3px 9px;text-align:right}");
   W("th{background:#1e222a;color:#8fbcbb}td:first-child,th:first-child{text-align:left}");
   W(".thin td,td.thin{color:#4c566a;font-style:italic}");
   W(".kpi{display:inline-block;background:#1e222a;border:1px solid #2e3440;border-radius:6px;padding:10px 16px;margin:4px 8px 4px 0;min-width:120px;font-size:11px;color:#7b8794}");
   W(".kpi b{display:block;font-size:18px;color:#eceff4}");
   W(".note{background:#1e222a;border-left:3px solid #ebcb8b;padding:10px 14px;margin:12px 0;color:#c8ccd4}");
   W(".ko{border-left-color:#bf616a}.ok{border-left-color:#a3be8c}");
   W("details{margin:6px 0}summary{cursor:pointer;color:#88c0d0;padding:3px 0}");
   W("pre{background:#0f1114;border:1px solid #2e3440;border-radius:6px;padding:14px;overflow-x:auto;font:11px/1.45 ui-monospace,Consolas,monospace;color:#d8dee9;white-space:pre}");
   W(".wrap{display:flex;flex-direction:column}.sec{width:100%}.setH{font-size:18px;margin:34px 0 4px;padding:8px 12px;background:#1e222a;border-left:4px solid #88c0d0}");
   W("h4{font-size:12px;margin:12px 0 4px;color:#a3be8c}button{background:#2e3440;color:#d8dee9;border:1px solid #4c566a;border-radius:4px;padding:6px 14px;cursor:pointer}");
   W(".sum td{text-align:left;vertical-align:top;line-height:1.5}.sum td:first-child{white-space:nowrap;font-weight:bold;color:#88c0d0}.sum td:nth-child(2){white-space:nowrap;color:#8fbcbb}");
   W("</style></head><body>");
  }

void RepIntro()
  {
   W("<h1>SignalLab MultiTF &mdash; " + ModeName() + " &mdash; " + _Symbol + "</h1>");
   datetime tEnd = (datetime)MathMin((long)InpTo, (long)g_m1Time[g_n1 - 1]);
   W("<div style='color:#7b8794'>Tutto in punti (point = " + DoubleToString(g_pt, _Digits) + "). Periodo " +
     TimeToString(g_tStart, TIME_DATE) + " &rarr; " + TimeToString(tEnd, TIME_DATE) +
     " | orologio comune M1 | orizzonte di riferimento " + IS(g_hor[g_refH]) + " min</div>");

   if(g_histWarn)
      W("<div class='note ko'><b>Storico M1 incompleto.</b> Richiesto da " + TimeToString(InpFrom, TIME_DATE) + ", disponibile da " +
        TimeToString(g_tStart, TIME_DATE) + ". Il periodo analizzato &egrave; pi&ugrave; corto: scarica altro storico (F2, Centro cronologia) o accorcia InpFrom.</div>");
   W("<h2>Configurazione e contesto dati</h2>");
   W("<table>");
   W("<tr><th>Segnale</th><td>" + ModeName() + " | EMA " + IS(InpEmaPeriod) + " | volume " + IS(InpVolAvgPeriod) +
     " | soglia " + F2(InpThreshold) + " | Exp TR/ATR &gt; " + F2(InpExpThreshold) + " (ATR " + IS(InpExpAtrPeriod) +
     ", conferma +" + IS(InpExpConfirmOffset) + ") | RunGapBars " + IS(InpRunGapBars) + "</td></tr>");
   if(InpUseVolState)
      W("<tr><th>Stato di volatilit&agrave;</th><td>ATR " + IS(g_vpar.atrLen) + " | percentile su " + IS(g_vpar.lookback) + " barre | EMA " + IS(g_vpar.emaSmooth) +
        " | espansione TR/ATR &gt; " + F2(InpVsExpTh) + " | compressione &lt; " + F2(InpVsCompTh) + " | LOW &lt; " + IS(InpVsLowTh) +
        ", HIGH &ge; " + IS(InpVsHighTh) + ", EXTREME &ge; " + IS(InpVsExtremeTh) + "</td></tr>");
   W("<tr><th>Costo</th><td>" + (InpCostPoints > 0.0 ? ("fisso " + F1(InpCostPoints) + " pt") : "spread reale M1") +
     " + extra " + F1(InpExtraCostPts) + " pt</td></tr>");
   W("<tr><th>Finestre</th><td>buco dati massimo " + IS(InpMaxGapMin) + " min | gap massimo all'ingresso " +
     IS(InpMaxEntryGapMin) + " min | fasce da " + IS(g_bMin) + " min | offset orario " + IS(InpTimeOffsetH) + " h</td></tr>");
   string hs = "";
   for(int i = 0; i < g_nH; i++) hs += (i > 0 ? ", " : "") + IS(g_hor[i]);
   W("<tr><th>Tenute / orizzonti (min)</th><td>" + hs + "</td></tr>");
   datetime tSplit = (datetime)((g_day0 + (long)g_splitDay) * 86400L);   // giorno sull'orologio server + offset, lo stesso di g_m1Day
   W("<tr><th>Classifica</th><td>in-sample prima del " + TimeToString(tSplit, TIME_DATE) + " (server + offset), out-of-sample dal " +
     TimeToString(tSplit, TIME_DATE) + " | fasce da " + IS(g_rbMin) + " min | minimo " + IS((long)g_minN) +
     " posizioni (in-sample per le tabelle A, intero storico per le B) | una posizione per volta, senza stop</td></tr>");
   string ls = "";
   for(int i = 0; i < g_nL; i++) ls += (i > 0 ? ", " : "") + F0(g_lev[i]);
   W("<tr><th>Livelli (pt)</th><td>" + ls + "</td></tr>");
   W("<tr><th>Barre M1</th><td>" + IS(g_n1) + " | giorni " + IS(g_nDays) + " | range M1 mediano " + F0(g_medRange) +
     " pt | spread M1 mediano " + F0(g_medSpr) + " pt | spread = 0 sul " + F1(g_zeroSprPct) + "% delle barre</td></tr>");
   W("</table>");
   if(InpCostPoints <= 0.0 && g_zeroSprPct > 20.0)
      W("<div class='note ko'><b>Spread storico spesso pari a 0.</b> Il costo &egrave; sottostimato e il netto medio &egrave; "
        "ottimista. Imposta <b>InpCostPoints</b> con lo spread tipico del simbolo o <b>InpExtraCostPts</b> con la commissione.</div>");
   if(InpCostPoints <= 0.0 && InpExtraCostPts <= 0.0)
      W("<div class='note'>Nessuna commissione inclusa. Su conti Raw (FP Markets, IC Markets) aggiungila in "
        "<b>InpExtraCostPts</b>, convertita in punti.</div>");

   W("<h2>Come leggere</h2>");
   W("<div class='note'><b>Netto medio</b> = rendimento a fine orizzonte nella direzione del segnale meno il costo, in punti. "
     "&Egrave; la metrica principale: senza informazione vale circa <b>&minus;costo</b> e non dipende dalla volatilit&agrave; (in media). "
     "<b>MFE</b> e <b>MAE</b> sono ampiezze massime: crescono con la volatilit&agrave; e con la radice dell'orizzonte, quindi un MFE grande da solo non &egrave; edge. "
     "Contano <b>MFE/MAE</b> (asimmetria dentro lo stesso evento) e il confronto con la <b>base</b> = entrate in direzione casuale, stesso TF, stessa fascia oraria.</div>");
   W("<div class='note'><b>t cluster</b> usa l'errore standard raggruppato per giorno: i segnali di barre vicine si sovrappongono, "
     "il t naive &egrave; gonfiato. Giallo = |t| &ge; 2 (debole, atteso per caso su 1 cella su 20). Verde/rosso = oltre la soglia di Bonferroni "
     "sul numero di celle TF x orizzonte di ciascuna serie (la soglia &egrave; scritta in testa alla serie). Non cercare la cella migliore: cerca coerenza fra TF vicini e orizzonti vicini. "
     "Il t cluster &egrave; ottimista per orizzonti di un giorno o pi&ugrave;, perch&eacute; giorni adiacenti condividono parte del percorso del prezzo.</div>");
   W("<div class='note'>Tutte le tabelle con <b>t naive</b> o z del segno (fasce orarie, candela nel TF superiore, raffica, direzione, giorno, classifiche) "
     "non sono corrette per i test multipli (e quelle non a posizione singola nemmeno per la sovrapposizione): nelle colonne t e z il giallo significa solo |t| &ge; 2, mai verde o rosso; "
     "il verde/rosso dei netti indica solo il segno, e la colonna Esito (verdetto sull'out-of-sample) &egrave; l'unica eccezione. "
     "Nelle classifiche la posizione occupa il suo slot per tutta la tenuta anche se il target esce prima (scelta prudente).</div>");
   W("<div class='note'>Le misure sono <b>in punti</b>: i simboli non sono confrontabili fra loro e le ore con volatilit&agrave; alta dominano i totali. "
     "Per questo le tabelle orarie sono affiancate dalla base della stessa fascia.</div>");
  }

void RepCoverage()
  {
   W("<h2>Copertura per timeframe</h2>");
   W("<div class='note'>Un segnale viene scartato se tra la chiusura della barra e la barra successiva c'&egrave; una pausa di sessione "
     "oltre <b>" + IS(InpMaxEntryGapMin) + "</b> min (weekend, chiusura giornaliera): l'ingresso non sarebbe quello del segnale. "
     "Per D1, W1 e MN1 la pausa di sessione o il weekend pu&ograve; scartare una quota alta dei segnali (vedi le colonne sopra): aumenta <b>InpMaxEntryGapMin</b> se vuoi entrare comunque all'apertura successiva.</div>");
   W("<table><tr><th>TF</th><th>Barre in periodo</th><th>Scartate gap sessione</th><th>Senza M1</th><th>Barre base</th>"
     "<th>Segnali</th><th>Misurati @" + IS(g_hor[g_refH]) + "m</th><th>% misurati</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      double nref = g_accTH[(t * g_nH + g_refH) * ACCN];
      double pc = (g_tfEv[t] > 0) ? 100.0 * nref / g_tfEv[t] : 0.0;
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(IS(g_tfBars[t])) + Td(IS(g_tfRejGap[t])) + Td(IS(g_tfRejM1[t])) +
        Td(IS(g_tfCnt[t])) + Td(IS(g_tfEv[t])) + Td(F0(nref)) + Td(F1(pc)) + "</tr>");
     }
   W("</table>");
  }

void RepVerdict()
  {
   W("<h2>Verdetto per timeframe &mdash; orizzonte " + IS(g_hor[g_refH]) + " min</h2>");
   W("<table><tr><th>TF</th><th>Segnali misurati</th><th>MFE medio</th><th>MAE medio</th><th>MFE/MAE</th>"
     "<th>MFE base</th><th>MFE/base</th><th>Netto medio</th><th>t naive</th><th>t cluster</th><th>Costo medio</th>"
     "<th>MFE&gt;MAE %</th><th>z segno</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      CellStat s;
      if(!GetCell(t, g_refH, s))
        { W("<tr class='thin'><td>" + g_tfName[t] + "</td><td colspan='12'>nessun segnale misurato</td></tr>"); continue; }
      double ratio = (s.mae > 0.0) ? s.mfe / s.mae : 0.0;
      double rb    = (s.baseMfe > 0.0) ? s.mfe / s.baseMfe : 0.0;
      double wp    = (s.win + s.lose > 0.0) ? 100.0 * s.win / (s.win + s.lose) : 0.0;
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(F0(s.n)) + Td(F0(s.mfe)) + Td(F0(s.mae)) +
        Td(F2(ratio), ratio > 1.0 ? "#a3be8c" : "#bf616a") + Td(F0(s.baseMfe)) + Td(F2(rb)) +
        Td("<b>" + F1(s.ret) + "</b>", ColSign(s.ret)) + Td(F2(s.tNaive)) +
        Td("<b>" + F2(s.tCl) + "</b>", ColT(s.tCl)) + Td(F1(s.cost)) + Td(F1(wp)) +
        Td(F2(s.zSign), ColTNaive(s.zSign)) + "</tr>");
     }
   W("</table>");
  }

void RepMatrices()
  {
   W("<h2>Netto medio (punti) per TF e orizzonte &mdash; (t cluster)</h2>");
   W("<table><tr><th>TF</th>");
   for(int h = 0; h < g_nH; h++) W("<th>" + IS(g_hor[h]) + "m</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int h = 0; h < g_nH; h++)
        {
         CellStat s;
         if(!GetCell(t, h, s)) { W("<td>-</td>"); continue; }
         W(Td(F1(s.ret) + " (" + F1(s.tCl) + ")", ColT(s.tCl)));
        }
      W("</tr>");
     }
   W("</table>");

   W("<h2>MFE medio (punti) per TF e orizzonte &mdash; [MFE/MAE]</h2>");
   W("<div class='note'>Descrive per quanti punti il prezzo prosegue nella direzione del segnale, ma &egrave; confuso dalla volatilit&agrave;. "
     "Verde = MFE/MAE &gt; 1 (il movimento favorevole supera quello avverso nello stesso evento).</div>");
   W("<table><tr><th>TF</th>");
   for(int h = 0; h < g_nH; h++) W("<th>" + IS(g_hor[h]) + "m</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int h = 0; h < g_nH; h++)
        {
         CellStat s;
         if(!GetCell(t, h, s)) { W("<td>-</td>"); continue; }
         double ratio = (s.mae > 0.0) ? s.mfe / s.mae : 0.0;
         W(Td(F0(s.mfe) + " [" + F2(ratio) + "]", ratio > 1.0 ? "#a3be8c" : "#bf616a"));
        }
      W("</tr>");
     }
   W("</table>");
  }

void RepExceed()
  {
   W("<h2>Probabilit&agrave; di raggiungere un livello &mdash; orizzonte " + IS(g_hor[g_refH]) + " min</h2>");
   W("<div class='note'>Ogni cella: <b>favorevole % / avverso % / base %</b>. Favorevole = MFE &ge; livello nella direzione del segnale; "
     "avverso = MAE &ge; livello; base = stessa probabilit&agrave; con direzione casuale, stesso TF e stessa distribuzione oraria. "
     "Verde se favorevole supera sia l'avverso sia la base, rosso se &egrave; sotto entrambi.</div>");
   W("<table><tr><th>TF</th><th>n</th>");
   for(int l = 0; l < g_nL; l++) W("<th>&ge; " + F0(g_lev[l]) + " pt</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      CellStat s;
      if(!GetCell(t, g_refH, s)) continue;
      const int cell = t * g_nH + g_refH;
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(F0(s.n)));
      for(int l = 0; l < g_nL; l++)
        {
         double pf = 100.0 * SuffixCount(g_exFav, cell * (g_nL + 1), l) / s.n;
         double pa = 100.0 * SuffixCount(g_exAdv, cell * (g_nL + 1), l) / s.n;
         double pb = 100.0 * BaseExcMatched(t, g_refH, l);
         string col = "#7b8794";
         if(pf > pa && pf > pb) col = "#a3be8c";
         else if(pf < pa && pf < pb) col = "#bf616a";
         W(Td(F1(pf) + " / " + F1(pa) + " / " + F1(pb), col));
        }
      W("</tr>");
     }
   W("</table>");
  }

//+------------------------------------------------------------------+
//| SPUNTE: minuti al raggiungimento dei livelli per il campione      |
//+------------------------------------------------------------------+
void ComputeEventReach()
  {
   if(g_evCount < 1) return;
   const long Hs = (long)g_hor[g_refH] * 60L;
   for(int q = 0; q < g_evCount; q++)
     {
      for(int l = 0; l < g_nL; l++) g_evMin[q * g_nL + l] = -1;
      const int    j = g_evJ[q];
      const double o = g_m1Open[j];
      const long   tEnd = (long)g_m1Time[j] + Hs;
      int nxt = 0;
      for(int x = j; x < g_n1 && (long)g_m1Time[x] < tEnd && nxt < g_nL; x++)
        {
         double fv = (g_evDir[q] > 0) ? (g_m1High[x] - o) / g_pt : (o - g_m1Low[x]) / g_pt;
         while(nxt < g_nL && fv >= g_lev[nxt])
           {
            g_evMin[q * g_nL + nxt] = (int)(((long)g_m1Time[x] - (long)g_m1Time[j]) / 60L) + 1;
            nxt++;
           }
        }
     }
  }

void RepEvents()
  {
   if(g_evCount < 1) return;
   W("<h2>Spunte: i punti raggiunti dopo ogni segnale &mdash; " + g_tfName[g_evT] + ", entro " + IS(g_hor[g_refH]) + " min</h2>");
   W("<div class='note'>Campione uniforme di <b>" + IS(g_evCount) + "</b> segnali del TF " + g_tfName[g_evT] +
     " (uno ogni " + IS(g_evStride) + ") su tutto il periodo. <b>&#10003; N m</b> = livello raggiunto entro N minuti dall'ingresso, "
     "nella direzione del segnale, come movimento lordo dal prezzo d'ingresso (open M1, spread escluso). "
     "&laquo;-&raquo; = non raggiunto entro l'orizzonte. L'elenco &egrave; illustrativo: le percentuali da usare sono nelle tabelle aggregate.</div>");
   W("<table><tr><th>#</th><th>Entrata (server + offset)</th><th>Giorno</th><th>Verso</th><th>Candela TF sup.</th><th>Raffica</th><th>MFE</th><th>MAE</th><th>Netto</th>");
   for(int l = 0; l < g_nL; l++) W("<th>" + F0(g_lev[l]) + "</th>");
   W("</tr>");
   for(int q = 0; q < g_evCount; q++)
     {
      datetime tm = (datetime)((long)g_evTime[q] + g_off);
      int dow = (int)((((long)tm / 86400L) + 4L) % 7L);
      string sl = g_slotOK[g_evT] ? (IS(g_evSlot[q] + 1) + "/" + IS(g_slotCnt[g_evT])) : "-";
      W("<tr>" + Td(IS(q + 1)) + "<td>" + TimeToString(tm, TIME_DATE | TIME_MINUTES) + "</td>" + Td(DowName(dow)) +
        Td(g_evDir[q] > 0 ? "BUY" : "SELL", g_evDir[q] > 0 ? "#a3be8c" : "#bf616a") + Td(sl) + Td(IS(g_evBur[q])) +
        Td(F0(g_evMfe[q])) + Td(F0(g_evMae[q])) + Td(F0(g_evRet[q]), ColSign(g_evRet[q])));
      for(int l = 0; l < g_nL; l++)
        {
         int mm = g_evMin[q * g_nL + l];
         if(mm >= 0) W(Td("&#10003; " + IS(mm) + "m", "#a3be8c"));
         else        W(Td("-", "#4c566a"));
        }
      W("</tr>");
     }
   W("</table>");
  }

//+------------------------------------------------------------------+
//| Probabilita' di raggiungere il target entro la tenuta (per TF)    |
//+------------------------------------------------------------------+
void RepReach(const int t)
  {
   W("<table><tr><th>Target (pt) \\ Tieni (min)</th>");
   for(int h = 0; h < g_nH; h++) W("<th>" + IS(g_hor[h]) + "</th>");
   W("</tr>");
   for(int l = 0; l < g_nL; l++)
     {
      W("<tr><td>" + F0(g_lev[l]) + "</td>");
      for(int h = 0; h < g_nH; h++)
        {
         const int cell = t * g_nH + h;
         double n = g_accTH[cell * ACCN];
         if(n < 1.0) { W("<td>-</td>"); continue; }
         double pf = 100.0 * SuffixCount(g_exFav, cell * (g_nL + 1), l) / n;
         double pb = 100.0 * BaseExcMatched(t, h, l);
         string col = "#7b8794";
         if(pf > pb * 1.1 && pf >= 1.0) col = "#a3be8c";
         else if(pf < pb * 0.9 && pb >= 1.0) col = "#bf616a";
         W(Td(F1(pf) + " (" + F1(pb) + ")", col));
        }
      W("</tr>");
     }
   W("</table>");
  }

//+------------------------------------------------------------------+
//| Mappa tenuta x target (per TF): netto medio per posizione IS/OOS  |
//+------------------------------------------------------------------+
void RepHeat(const int t)
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   for(int dd = 0; dd < 2; dd++)
     {
      W("<h3>" + string(dd == 0 ? "SEGUI il segnale" : "INVERTI il segnale") +
        " &mdash; netto medio per posizione (punti), in-sample / out-of-sample</h3>");
      W("<table><tr><th>Target \\ Tieni (min)</th>");
      for(int h = 0; h < g_nH; h++) W("<th>" + IS(g_hor[h]) + "</th>");
      W("</tr>");
      for(int kk = 0; kk <= g_nL; kk++)
        {
         W("<tr><td>" + (kk == 0 ? string("nessuno (solo tempo)") : F0(g_lev[kk - 1]) + " pt") + "</td>");
         for(int h = 0; h < g_nH; h++)
           {
            RkStat a, b;
            const int base = (t * g_nH + h) * blk;
            RkRead(g_rg, base, kk, dd, 0, a);
            RkRead(g_rg, base, kk, dd, 1, b);
            string tip = " title='posizioni IS " + F0(a.n) + " / OOS " + F0(b.n) + "'";
            if(a.n < g_minN)
              { W("<td class='thin'" + tip + ">" + F1(a.mean) + " / " + F1(b.mean) + "</td>"); continue; }
            string col = "#ebcb8b";
            if(a.mean > 0.0 && b.mean > 0.0) col = "#a3be8c";
            else if(a.mean < 0.0 && b.mean < 0.0) col = "#bf616a";
            W("<td style='color:" + col + "'" + tip + ">" + F1(a.mean) + " / " + F1(b.mean) + "</td>");
           }
         W("</tr>");
        }
      W("</table>");
     }
  }

//+------------------------------------------------------------------+
//| CLASSIFICA                                                        |
//+------------------------------------------------------------------+
string RBktLabel(const int b)
  {
   int s0 = b * g_rbMin, e0 = s0 + g_rbMin;
   return StringFormat("%02d:%02d-%02d:%02d", s0 / 60, s0 % 60, e0 / 60, e0 % 60);
  }

string KLabel(const int kk) { return (kk == 0) ? string("nessuno") : F0(g_lev[kk - 1]); }

string EsitoCell(const RkStat &a, const RkStat &b)
  {
   if(b.n < MathMax(10.0, g_minN / 3.0)) return Td("OOS scarso", "#4c566a");
   if(b.mean > 0.0 && b.t >= 2.0)             return Td("<b>TIENE</b>", "#a3be8c");
   if(b.mean > 0.0)                           return Td("debole", "#ebcb8b");
   return Td("NO", "#bf616a");
  }

string RankHead()
  {
   return "<table><tr><th>#</th><th>TF</th><th>Fascia (entrata, server + offset)</th><th>Verso</th><th>Tieni (min)</th><th>Target (pt)</th>"
          "<th>IS pos.</th><th>IS netto</th><th>IS t</th><th>Target raggiunto % (netto)</th>"
          "<th>OOS pos.</th><th>OOS netto</th><th>OOS t</th><th>Esito</th></tr>";
  }

string RankRow(const int rank, const int t, const int rb, const int h, const int kk, const int dd)
  {
   const int base = ((t * g_nRB + rb) * g_nH + h) * ((g_nL + 1) * 4 * RKN);
   RkStat a, b;
   RkRead(g_rk, base, kk, dd, 0, a);
   RkRead(g_rk, base, kk, dd, 1, b);
   string hs = (kk == 0) ? "-" : F1(a.hit);
   return "<tr>" + Td(IS(rank)) + "<td>" + g_tfName[t] + "</td><td>" + RBktLabel(rb) + "</td>" +
          Td(dd == 0 ? "SEGUI" : "INVERTI") + Td(IS(g_hor[h])) + Td(KLabel(kk)) +
          Td(F0(a.n)) + Td("<b>" + F1(a.mean) + "</b>", ColSign(a.mean)) + Td(F2(a.t)) + Td(hs) +
          Td(F0(b.n)) + Td("<b>" + F1(b.mean) + "</b>", ColSign(b.mean)) + Td(F2(b.t), ColTNaive(b.t)) +
          EsitoCell(a, b) + "</tr>";
  }

void RankDigest(const string tag, const int rank, const int t, const int rb, const int h, const int kk, const int dd)
  {
   const int base = ((t * g_nRB + rb) * g_nH + h) * ((g_nL + 1) * 4 * RKN);
   RkStat a, b;
   RkRead(g_rk, base, kk, dd, 0, a);
   RkRead(g_rk, base, kk, dd, 1, b);
   g_dg += tag + "|" + IS(rank) + "|" + g_tfName[t] + "|" + RBktLabel(rb) + "|" + (dd == 0 ? "SEGUI" : "INVERTI") +
           "|hold|" + IS(g_hor[h]) + "|tp|" + KLabel(kk) + "|isn|" + F0(a.n) + "|ismean|" + F1(a.mean) + "|ist|" + F2(a.t) +
           "|hit|" + (kk == 0 ? "-" : F1(a.hit)) + "|oosn|" + F0(b.n) + "|oosmean|" + F1(b.mean) + "|oost|" + F2(b.t) + "\n";
  }

//--- migliore combinazione (tenuta, target, verso) per ogni TF, su tutto il giorno
void RepBestTF()
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   W("<h2>A1 &mdash; Quanto tenere e per quanti punti: miglior combinazione per timeframe (scelta in-sample)</h2>");
   W("<div class='note'><b>Come &egrave; costruita.</b> Per ogni TF si simula una posizione per volta (tutto il giorno): si entra sul segnale, "
     "si esce al target (se indicato) oppure dopo <b>Tieni</b> minuti, senza stop. Il risultato &egrave; netto del costo. "
     "La combinazione migliore &egrave; scelta sul <b>primo " + IS(MathMin(95, MathMax(5, InpSplitPct))) + "%</b> del periodo (in-sample, IS) per t-statistic; "
     "le colonne OOS sono il restante periodo, mai usato per scegliere. <b>Solo l'OOS conta.</b> "
     "&laquo;INVERTI&raquo; = fare l'opposto del segnale: &egrave; incluso perch&eacute; un trigger pu&ograve; contenere informazione dal lato sbagliato.</div>");
   W("<table><tr><th>TF</th><th>Verso</th><th>Tieni (min)</th><th>Target (pt)</th><th>IS pos.</th><th>IS netto</th><th>IS t</th>"
     "<th>Target raggiunto % (netto)</th><th>OOS pos.</th><th>OOS netto</th><th>OOS t</th><th>Esito</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      double bt = -1.0e9; int bh = -1, bk = -1, bd = -1;
      for(int h = 0; h < g_nH; h++)
         for(int kk = 0; kk <= g_nL; kk++)
            for(int dd = 0; dd < 2; dd++)
              {
               RkStat a;
               RkRead(g_rg, (t * g_nH + h) * blk, kk, dd, 0, a);
               if(a.n < g_minN) continue;
               if(a.t > bt) { bt = a.t; bh = h; bk = kk; bd = dd; }
              }
      const int ci = g_curSet * g_nT + t;
      g_cmpBoN[ci] = 0.0; g_cmpBoM[ci] = 0.0; g_cmpBoT[ci] = 0.0; g_cmpDesc[ci] = "-";
      if(bh < 0)
        { W("<tr class='thin'><td>" + g_tfName[t] + "</td><td colspan='11'>campione in-sample insufficiente</td></tr>"); continue; }
      RkStat a, b;
      RkRead(g_rg, (t * g_nH + bh) * blk, bk, bd, 0, a);
      RkRead(g_rg, (t * g_nH + bh) * blk, bk, bd, 1, b);
      g_cmpBoN[ci] = b.n; g_cmpBoM[ci] = b.mean; g_cmpBoT[ci] = b.t;
      g_cmpDesc[ci] = string(bd == 0 ? "SEGUI" : "INVERTI") + " " + IS(g_hor[bh]) + "m, TP " + KLabel(bk);
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(bd == 0 ? "SEGUI" : "INVERTI") + Td(IS(g_hor[bh])) + Td(KLabel(bk)) +
        Td(F0(a.n)) + Td("<b>" + F1(a.mean) + "</b>", ColSign(a.mean)) + Td(F2(a.t)) + Td(bk == 0 ? "-" : F1(a.hit)) +
        Td(F0(b.n)) + Td("<b>" + F1(b.mean) + "</b>", ColSign(b.mean)) + Td(F2(b.t), ColTNaive(b.t)) + EsitoCell(a, b) + "</tr>");
      g_dg += "BESTTF|" + g_tfName[t] + "|" + (bd == 0 ? "SEGUI" : "INVERTI") + "|hold|" + IS(g_hor[bh]) + "|tp|" + KLabel(bk) +
              "|isn|" + F0(a.n) + "|ismean|" + F1(a.mean) + "|ist|" + F2(a.t) + "|hit|" + (bk == 0 ? "-" : F1(a.hit)) +
              "|oosn|" + F0(b.n) + "|oosmean|" + F1(b.mean) + "|oost|" + F2(b.t) + "\n";
     }
   W("</table>");
  }

//--- classifica congiunta: TF x fascia x tenuta x target x verso
void RepRank()
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   const int rankTop = MathMin(200, MathMax(1, InpRankTop));
   const int P = MathMax(300, rankTop * 5);
   double pT[]; int pTf[], pB[], pH[], pK[], pD[];
   ArrayResize(pT, P); ArrayResize(pTf, P); ArrayResize(pB, P);
   ArrayResize(pH, P); ArrayResize(pK, P);  ArrayResize(pD, P);
   int pn = 0;
   long m = 0;
   for(int t = 0; t < g_nT; t++)
      for(int rb = 0; rb < g_nRB; rb++)
         for(int h = 0; h < g_nH; h++)
           {
            const int base = ((t * g_nRB + rb) * g_nH + h) * blk;
            if(g_rk[base] < g_minN) continue;
            for(int kk = 0; kk <= g_nL; kk++)
               for(int dd = 0; dd < 2; dd++)
                 {
                  RkStat a;
                  RkRead(g_rk, base, kk, dd, 0, a);
                  m++;
                  int pos;
                  if(pn < P) { pos = pn; pn++; }
                  else
                    {
                     if(a.t <= pT[P - 1]) continue;
                     pos = P - 1;
                    }
                  while(pos > 0 && pT[pos - 1] < a.t)
                    {
                     pT[pos] = pT[pos - 1]; pTf[pos] = pTf[pos - 1]; pB[pos] = pB[pos - 1];
                     pH[pos] = pH[pos - 1]; pK[pos] = pK[pos - 1];   pD[pos] = pD[pos - 1];
                     pos--;
                    }
                  pT[pos] = a.t; pTf[pos] = t; pB[pos] = rb; pH[pos] = h; pK[pos] = kk; pD[pos] = dd;
                 }
           }

   W("<h2>A2 &mdash; Classifica: quando osservare il segnale e come gestire la posizione (scelta in-sample)</h2>");
   if(pn < 1 || m < 1)
     { W("<div class='note ko'>Nessuna combinazione con almeno " + IS((long)g_minN) + " posizioni in-sample. Riduci <b>InpRankMinN</b> o allarga il periodo.</div>"); return; }

   //--- diagnostica sull'insieme dei migliori in-sample
   int posOOS = 0, strong = 0, usable = 0;
   for(int i = 0; i < pn; i++)
     {
      RkStat b;
      RkRead(g_rk, ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk, pK[i], pD[i], 1, b);
      if(b.n < MathMax(10.0, g_minN / 3.0)) continue;
      usable++;
      if(b.mean > 0.0) posOOS++;
      if(b.mean > 0.0 && b.t >= 2.0) strong++;
     }
   double chanceT = (m > 1) ? MathSqrt(2.0 * MathLog((double)m)) : 0.0;
   double bestT = pT[0];
   bool noisy = (bestT < chanceT + 1.0 || usable == 0 || posOOS * 2 < usable);
   g_cAok = true; g_cAm = m; g_cAbestT = bestT; g_cAchance = chanceT; g_cApn = pn;
   g_cAusable = usable; g_cApos = posOOS; g_cAstrong = strong;
   W("<div class='note " + string(noisy ? "ko" : "ok") + "'><b>Diagnostica della classifica.</b> Combinazioni valutate in-sample: <b>" + IS(m) +
     "</b>. Il miglior t in-sample trovato &egrave; <b>" + F2(bestT) + "</b>; per puro caso, su " + IS(m) +
     " tentativi indipendenti, ci si aspetta un massimo intorno a <b>" + F2(chanceT) + "</b> (stima per eccesso: le combinazioni vicine sono correlate, quindi i test davvero indipendenti sono meno). "
     "Fra le prime <b>" + IS(pn) + "</b> in-sample, <b>" + IS(posOOS) + "</b> su " + IS(usable) + " con campione OOS sufficiente restano positive fuori campione, <b>" +
     IS(strong) + "</b> con OOS t &ge; 2. " +
     string(noisy ? "Se questi numeri sono vicini a zero la classifica &egrave; rumore di selezione: non operare nessuna di queste righe."
                  : "Il risultato regge la prima verifica, ma resta da confermare su dati mai visti (forward o altro simbolo).") + "</div>");

   const int K = MathMin(rankTop, pn);
   W("<h3>Prime " + IS(K) + " in-sample (ordinate per t in-sample)</h3>");
   W(RankHead());
   for(int i = 0; i < K; i++)
     {
      W(RankRow(i + 1, pTf[i], pB[i], pH[i], pK[i], pD[i]));
      RankDigest("RANK", i + 1, pTf[i], pB[i], pH[i], pK[i], pD[i]);
     }
   W("</table>");
   g_dg += "DIAG|combos|" + IS(m) + "|bestt|" + F2(bestT) + "|chance|" + F2(chanceT) + "|pool|" + IS(pn) +
           "|poosn|" + IS(usable) + "|pos|" + IS(posOOS) + "|strong|" + IS(strong) + "\n";

   //--- candidati che reggono fuori campione (seconda selezione: usa l'OOS)
   int sv[]; ArrayResize(sv, pn);
   double svT[]; ArrayResize(svT, pn);
   int ns = 0;
   for(int i = 0; i < pn; i++)
     {
      if(pT[i] < 2.0) continue;
      RkStat b;
      RkRead(g_rk, ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk, pK[i], pD[i], 1, b);
      if(b.n < MathMax(10.0, g_minN / 3.0)) continue;
      if(b.mean > 0.0 && b.t >= 2.0) { sv[ns] = i; svT[ns] = b.t; ns++; }
     }
   for(int i = 0; i < ns - 1; i++)
      for(int j2 = i + 1; j2 < ns; j2++)
         if(svT[j2] > svT[i]) { double tt = svT[i]; svT[i] = svT[j2]; svT[j2] = tt; int ti = sv[i]; sv[i] = sv[j2]; sv[j2] = ti; }
   g_cAns = ns;
   g_cAsurv = "";
   if(ns > 0)
     {
      const int i0 = sv[0];
      const int bs0 = ((pTf[i0] * g_nRB + pB[i0]) * g_nH + pH[i0]) * blk;
      RkStat sa, sb;
      RkRead(g_rk, bs0, pK[i0], pD[i0], 0, sa);
      RkRead(g_rk, bs0, pK[i0], pD[i0], 1, sb);
      g_cAsurv = g_tfName[pTf[i0]] + " " + RBktLabel(pB[i0]) + " " + (pD[i0] == 0 ? "SEGUI" : "INVERTI") + ", tieni " + IS(g_hor[pH[i0]]) +
                 " min, target " + KLabel(pK[i0]) + " pt: netto in-sample " + Sg(sa.mean) + " (t " + F2(sa.t) + "), fuori campione " +
                 Sg(sb.mean) + " (t " + F2(sb.t) + ", " + F0(sb.n) + " posizioni)";
     }
   W("<h3>Fra le prime " + IS(pn) + " in-sample: quelle con IS t &ge; 2 che reggono anche fuori campione (OOS netto &gt; 0 e OOS t &ge; 2)</h3>");
   if(ns == 0)
      W("<div class='note ko'>Nessuna combinazione fra le migliori in-sample ha OOS positivo e significativo. &Egrave; il risultato atteso se il segnale non ha edge netto dei costi.</div>");
   else
     {
      W("<div class='note'>Attenzione: questa lista usa l'OOS per selezionare, quindi l'OOS non &egrave; pi&ugrave; incontaminato. "
        "Sono candidati da confermare in forward test o su un altro periodo/simbolo, non risultati.</div>");
      W(RankHead());
      int shown = MathMin(ns, 20);
      for(int i = 0; i < shown; i++)
        {
         W(RankRow(i + 1, pTf[sv[i]], pB[sv[i]], pH[sv[i]], pK[sv[i]], pD[sv[i]]));
         RankDigest("SURV", i + 1, pTf[sv[i]], pB[sv[i]], pH[sv[i]], pK[sv[i]], pD[sv[i]]);
        }
      W("</table>");
     }
  }

//+------------------------------------------------------------------+
//| TABELLA B - CON RUMORE                                            |
//| Ordinata sull'INTERO storico, senza separare in-sample e          |
//| out-of-sample: e' quello che vedrebbe chi ottimizza senza         |
//| protezione. Le due parti del periodo sono affiancate solo per     |
//| mostrare se il risultato e' stabile; la riga pero' e' stata       |
//| scelta guardando entrambe, quindi non sono indipendenti.          |
//+------------------------------------------------------------------+
string NoiseSortName()
  {
   switch(InpNoiseSort)
     {
      case NS_TOTAL: return "profitto totale in punti";
      case NS_MEAN:  return "netto medio per posizione";
      case NS_T:     return "t-statistic";
     }
   return "profitto totale in punti";
  }

double NoiseKey(const RkStat &s)
  {
   switch(InpNoiseSort)
     {
      case NS_TOTAL: return s.sum;
      case NS_MEAN:  return s.mean;
      case NS_T:     return s.t;
     }
   return s.sum;
  }

//--- campione minimo della parte recente per la tabella B: proporzionale alla quota di periodo fuori campione
double MinLate()
  {
   int pct = MathMin(95, MathMax(5, InpSplitPct));
   return MathMax(10.0, 0.5 * g_minN * (100.0 - pct) / 100.0);
  }

string CoerenzaCell(const RkStat &a, const RkStat &b)
  {
   if(a.n < 1.0 || b.n < MinLate()) return Td("2a parte scarsa", "#4c566a");
   if(a.mean > 0.0 && b.mean > 0.0) return Td("coerente +", "#a3be8c");
   if(a.mean < 0.0 && b.mean < 0.0) return Td("coerente -", "#7b8794");
   return Td("INCOERENTE", "#bf616a");
  }

string NoiseHead(const bool withBucket)
  {
   return "<table><tr><th>#</th><th>TF</th>" + string(withBucket ? "<th>Fascia (entrata, server + offset)</th>" : "") +
          "<th>Verso</th><th>Tieni (min)</th><th>Target (pt)</th><th>Posizioni</th><th>Profitto totale (pt)</th>"
          "<th>Netto medio</th><th>t</th><th>Target raggiunto % (netto)</th>"
          "<th>Netto 1a parte</th><th>Netto 2a parte</th><th>Fra le due parti</th></tr>";
  }

string NoiseCells(const RkStat &all, const RkStat &a, const RkStat &b, const int kk)
  {
   return Td(F0(all.n)) + Td("<b>" + F0(all.sum) + "</b>", ColSign(all.sum)) + Td(F1(all.mean), ColSign(all.mean)) +
          Td(F2(all.t), ColTNaive(all.t)) + Td(kk == 0 ? "-" : F1(all.hit)) +
          Td(F1(a.mean), ColSign(a.mean)) + Td(F1(b.mean), ColSign(b.mean)) + CoerenzaCell(a, b);
  }

void RepNoiseIntro()
  {
   int pct = MathMin(95, MathMax(5, InpSplitPct));
   W("<h2>Due letture della stessa classifica</h2>");
   W("<div class='note'><b>Tabelle A</b> (A1 e A2, qui di seguito): le combinazioni sono scelte guardando solo il primo " + IS(pct) +
     "% del periodo e poi verificate sul resto, che non ha mai partecipato alla scelta. "
     "<b>Tabelle B</b> (B1 e B2, dopo le A): le combinazioni sono scelte guardando <b>tutto</b> lo storico, ordinate per <b>" + NoiseSortName() +
     "</b>, senza alcuna protezione: &egrave; quello che vedrebbe chi ottimizza sull'intero storico. "
     "Con migliaia di combinazioni la prima riga di B tende a essere positiva anche se il segnale non ha informazione (a meno che il costo domini ovunque). "
     "Serve per confrontare quanto B promette rispetto a quanto A conferma, non per scegliere cosa operare.</div>");
  }

//--- B1: miglior combinazione per TF sull'intero storico
void RepBestTFNoise()
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   W("<h2>B1 &mdash; Quanto tenere e per quanti punti: miglior combinazione per timeframe (CON RUMORE, intero storico)</h2>");
   W("<div class='note ko'>Per ogni TF si prende la combinazione con il valore pi&ugrave; alto di <b>" + NoiseSortName() +
     "</b> su tutto il periodo. Le colonne <b>1a parte</b> (primo " + IS(MathMin(95, MathMax(5, InpSplitPct))) +
     "%) e <b>2a parte</b> (resto) mostrano se il risultato &egrave; stabile nel tempo, ma non sono indipendenti: la riga &egrave; stata scelta guardandole entrambe. "
     "&laquo;INCOERENTE&raquo; = le due parti hanno segno opposto: tipico del rumore.</div>");
   W(NoiseHead(false));
   for(int t = 0; t < g_nT; t++)
     {
      double bk0 = -1.0e18; int bh = -1, bk = -1, bd = -1;
      for(int h = 0; h < g_nH; h++)
         for(int kk = 0; kk <= g_nL; kk++)
            for(int dd = 0; dd < 2; dd++)
              {
               RkStat all;
               RkReadAll(g_rg, (t * g_nH + h) * blk, kk, dd, all);
               if(all.n < g_minN) continue;
               double key = NoiseKey(all);
               if(key > bk0) { bk0 = key; bh = h; bk = kk; bd = dd; }
              }
      if(bh < 0)
        { W("<tr class='thin'><td>-</td><td>" + g_tfName[t] + "</td><td colspan='11'>campione insufficiente</td></tr>"); continue; }
      RkStat all, a, b;
      RkReadAll(g_rg, (t * g_nH + bh) * blk, bk, bd, all);
      RkRead(g_rg, (t * g_nH + bh) * blk, bk, bd, 0, a);
      RkRead(g_rg, (t * g_nH + bh) * blk, bk, bd, 1, b);
      W("<tr>" + Td("-") + "<td>" + g_tfName[t] + "</td>" + Td(bd == 0 ? "SEGUI" : "INVERTI") + Td(IS(g_hor[bh])) + Td(KLabel(bk)) +
        NoiseCells(all, a, b, bk) + "</tr>");
      g_dg += "BESTNOISE|" + g_tfName[t] + "|" + (bd == 0 ? "SEGUI" : "INVERTI") + "|hold|" + IS(g_hor[bh]) + "|tp|" + KLabel(bk) +
              "|n|" + F0(all.n) + "|total|" + F0(all.sum) + "|mean|" + F1(all.mean) + "|t|" + F2(all.t) + "|hit|" + (bk == 0 ? "-" : F1(all.hit)) +
              "|part1|" + F1(a.mean) + "|part2|" + F1(b.mean) + "\n";
     }
   W("</table>");
  }

//--- B2: classifica congiunta TF x fascia x tenuta x target x verso sull'intero storico
void RepRankNoise()
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   const int rankTop = MathMin(200, MathMax(1, InpRankTop));
   const int P = MathMax(300, rankTop * 5);
   double pK2[]; int pTf[], pB[], pH[], pK[], pD[];
   ArrayResize(pK2, P); ArrayResize(pTf, P); ArrayResize(pB, P);
   ArrayResize(pH, P);  ArrayResize(pK, P);  ArrayResize(pD, P);
   int pn = 0;
   long m = 0;
   for(int t = 0; t < g_nT; t++)
      for(int rb = 0; rb < g_nRB; rb++)
         for(int h = 0; h < g_nH; h++)
           {
            const int base = ((t * g_nRB + rb) * g_nH + h) * blk;
            if(g_rk[base] + g_rk[base + RKN] < g_minN) continue;
            for(int kk = 0; kk <= g_nL; kk++)
               for(int dd = 0; dd < 2; dd++)
                 {
                  RkStat all;
                  RkReadAll(g_rk, base, kk, dd, all);
                  m++;
                  double key = NoiseKey(all);
                  int pos;
                  if(pn < P) { pos = pn; pn++; }
                  else
                    {
                     if(key <= pK2[P - 1]) continue;
                     pos = P - 1;
                    }
                  while(pos > 0 && pK2[pos - 1] < key)
                    {
                     pK2[pos] = pK2[pos - 1]; pTf[pos] = pTf[pos - 1]; pB[pos] = pB[pos - 1];
                     pH[pos] = pH[pos - 1];   pK[pos]  = pK[pos - 1];  pD[pos] = pD[pos - 1];
                     pos--;
                    }
                  pK2[pos] = key; pTf[pos] = t; pB[pos] = rb; pH[pos] = h; pK[pos] = kk; pD[pos] = dd;
                 }
           }

   W("<h2>B2 &mdash; Classifica (CON RUMORE): ordinata per " + NoiseSortName() + " sull'intero storico</h2>");
   if(pn < 1 || m < 1)
     { W("<div class='note ko'>Nessuna combinazione con almeno " + IS((long)g_minN) + " posizioni.</div>"); return; }

   //--- diagnostica: quanto del profitto "trovato" sopravvive nella parte piu' recente
   double sumAll = 0.0, sumLate = 0.0, nAll = 0.0, nLate = 0.0;
   int incoh = 0, bothPos = 0, usable = 0;
   const int K = MathMin(rankTop, pn);
   for(int i = 0; i < K; i++)
     {
      const int base = ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk;
      RkStat all, a, b;
      RkReadAll(g_rk, base, pK[i], pD[i], all);
      RkRead(g_rk, base, pK[i], pD[i], 0, a);
      RkRead(g_rk, base, pK[i], pD[i], 1, b);
      sumAll += all.sum; sumLate += b.sum; nAll += all.n; nLate += b.n;
     }
   for(int i = 0; i < pn; i++)
     {
      const int base = ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk;
      RkStat a, b;
      RkRead(g_rk, base, pK[i], pD[i], 0, a);
      RkRead(g_rk, base, pK[i], pD[i], 1, b);
      if(b.n < MinLate()) continue;
      usable++;
      if(a.mean > 0.0 && b.mean > 0.0) bothPos++;
      else if((a.mean > 0.0) != (b.mean > 0.0)) incoh++;
     }
   double chanceT = (m > 1) ? MathSqrt(2.0 * MathLog((double)m)) : 0.0;
   double shareLate = (sumAll > 0.0) ? 100.0 * sumLate / sumAll : 0.0;
   double shareN    = (nAll > 0.0) ? 100.0 * nLate / nAll : 0.0;
   RkStat top;
   RkReadAll(g_rk, ((pTf[0] * g_nRB + pB[0]) * g_nH + pH[0]) * blk, pK[0], pD[0], top);
   bool good = (sumAll > 0.0 && usable > 0 && bothPos * 2 >= usable && shareLate >= 0.5 * shareN);
   g_cBok = true; g_cBm = m; g_cBtotal = top.sum; g_cBmean = top.mean; g_cBt = top.t; g_cBn = top.n;
   g_cBshareN = shareN; g_cBshareLate = shareLate; g_cBboth = bothPos; g_cBincoh = incoh; g_cBusable = usable; g_cBpn = pn;
   g_cBdesc = g_tfName[pTf[0]] + " " + RBktLabel(pB[0]) + " " + (pD[0] == 0 ? "SEGUI" : "INVERTI") + ", tieni " + IS(g_hor[pH[0]]) +
              " min, target " + KLabel(pK[0]) + " pt";
   string shareTxt = (sumAll > 0.0)
      ? ("la parte pi&ugrave; recente del periodo contiene il <b>" + F1(shareN) + "%</b> delle posizioni ma il <b>" + F1(shareLate) +
         "%</b> del profitto: se l'edge fosse stabile le due quote sarebbero simili. ")
      : "le prime righe non hanno profitto totale positivo: non c'&egrave; profitto da ripartire fra le due parti. ";
   W("<div class='note " + string(good ? "ok" : "ko") + "'><b>Cosa promette questa tabella.</b> Combinazioni valutate: <b>" + IS(m) +
     "</b>. La prima ha profitto totale <b>" + F0(top.sum) + " pt</b> su " + F0(top.n) + " posizioni (netto medio " + F1(top.mean) +
     ", t " + F2(top.t) + "); il t massimo atteso per puro caso su " + IS(m) + " tentativi &egrave; intorno a <b>" + F2(chanceT) + "</b>. "
     "Nelle prime " + IS(K) + " righe " + shareTxt +
     "Fra le prime " + IS(pn) + " con campione sufficiente, <b>" + IS(bothPos) + "</b> su " + IS(usable) + " sono positive in entrambe le parti e <b>" +
     IS(incoh) + "</b> cambiano segno. " +
     string(good ? "Il profitto sembra stabile nel tempo: confrontalo con la tabella A prima di fidarti."
                 : "La distanza fra il profitto promesso e quello della parte recente &egrave; la misura del rumore di selezione.") + "</div>");

   W("<h3>Prime " + IS(K) + " per " + NoiseSortName() + " (intero storico)</h3>");
   W(NoiseHead(true));
   for(int i = 0; i < K; i++)
     {
      const int base = ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk;
      RkStat all, a, b;
      RkReadAll(g_rk, base, pK[i], pD[i], all);
      RkRead(g_rk, base, pK[i], pD[i], 0, a);
      RkRead(g_rk, base, pK[i], pD[i], 1, b);
      W("<tr>" + Td(IS(i + 1)) + "<td>" + g_tfName[pTf[i]] + "</td><td>" + RBktLabel(pB[i]) + "</td>" +
        Td(pD[i] == 0 ? "SEGUI" : "INVERTI") + Td(IS(g_hor[pH[i]])) + Td(KLabel(pK[i])) + NoiseCells(all, a, b, pK[i]) + "</tr>");
      g_dg += "NOISE|" + IS(i + 1) + "|" + g_tfName[pTf[i]] + "|" + RBktLabel(pB[i]) + "|" + (pD[i] == 0 ? "SEGUI" : "INVERTI") +
              "|hold|" + IS(g_hor[pH[i]]) + "|tp|" + KLabel(pK[i]) + "|n|" + F0(all.n) + "|total|" + F0(all.sum) +
              "|mean|" + F1(all.mean) + "|t|" + F2(all.t) + "|hit|" + (pK[i] == 0 ? "-" : F1(all.hit)) + "|part1|" + F1(a.mean) + "|part2|" + F1(b.mean) + "\n";
     }
   W("</table>");
   g_dg += "DIAGNOISE|combos|" + IS(m) + "|sort|" + NoiseSortName() + "|top_total|" + F0(top.sum) + "|top_t|" + F2(top.t) +
           "|chance_t|" + F2(chanceT) + "|late_share_n|" + F1(shareN) + "|late_share_profit|" + F1(shareLate) +
           "|pool|" + IS(pn) + "|usable|" + IS(usable) + "|both_pos|" + IS(bothPos) + "|incoherent|" + IS(incoh) + "\n";
  }

//+------------------------------------------------------------------+
//| STATO DI VOLATILITA' DEI SEGNALI (logica dell'indicatore Ferro)   |
//| Non filtra: divide gli stessi segnali per intensita' della        |
//| candela (TR/ATR), regime (percentile) e direzione del percentile. |
//+------------------------------------------------------------------+
string CndLabel(const int cat)
  {
   switch(cat)
     {
      case 0: return "Compressione (TR/ATR &lt; " + F2(InpVsCompTh) + ")";
      case 1: return "Normale";
      case 2: return "Espansione (TR/ATR &gt; " + F2(InpVsExpTh) + ")";
      case 3: return "LOW (percentile &lt; " + IS(InpVsLowTh) + ")";
      case 4: return "NORMAL";
      case 5: return "HIGH (&ge; " + IS(InpVsHighTh) + ")";
      case 6: return "EXTREME (&ge; " + IS(InpVsExtremeTh) + ")";
      case 7: return "Volatilit&agrave; in calo o ferma";
      case 8: return "Volatilit&agrave; in aumento";
     }
   return "?";
  }

string CndTag(const int cat)
  {
   string tg[9] = {"COMPRESSIONE", "NORMALE", "ESPANSIONE", "LOW", "NORMAL", "HIGH", "EXTREME", "VOL_CALO", "VOL_AUMENTO"};
   return (cat >= 0 && cat < 9) ? tg[cat] : "?";
  }

//--- MFE medio della base (direzione casuale) nella stessa categoria e con la stessa distribuzione oraria dei segnali
double CndBase(const int t, const int cat)
  {
   double num = 0.0, den = 0.0;
   for(int b = 0; b < g_nB; b++)
     {
      const int ib = (t * NCAT + cat) * g_nB + b;
      const int en = g_ceN[ib];
      if(en <= 0 || g_cbN[ib] <= 0) continue;
      num += (double)en * (g_cbSum[ib] / (double)g_cbN[ib]);
      den += (double)en;
     }
   return (den > 0.0) ? num / den : 0.0;
  }

void RepVolState()
  {
   if(!InpUseVolState) return;
   W("<h2>Stato di volatilit&agrave; dei segnali (indicatore Ferro) &mdash; orizzonte " + IS(g_hor[g_refH]) + " min</h2>");
   W("<div class='note'>Ogni segnale &egrave; classificato con la stessa logica dell'indicatore <b>Volatility State [Ferro]</b>, calcolata sulla <b>barra del segnale</b> "
     "(la candela che ha appena chiuso): <b>intensit&agrave;</b> = TR/ATR (compressione sotto " + F2(InpVsCompTh) + ", espansione sopra " + F2(InpVsExpTh) +
     "), <b>regime</b> = percentile della volatilit&agrave; composita (ATR% + Parkinson, EMA " + IS(g_vpar.emaSmooth) + ") sulle ultime " + IS(g_vpar.lookback) +
     " barre, <b>direzione</b> = il percentile &egrave; salito o no rispetto alla barra prima. &Egrave; una misura, non un filtro: i segnali restano gli stessi, "
     "divisi in gruppi. Verifica se i segnali emessi con volatilit&agrave; in aumento o in espansione hanno un netto diverso. "
     "La tabella <b>MFE / base</b> confronta il movimento dopo il segnale con quello di entrate in direzione casuale nello stesso stato di volatilit&agrave; e nelle stesse fasce orarie: "
     "in espansione tutti si muovono di pi&ugrave;, quindi conta il rapporto con la base e il netto, non l'MFE assoluto. "
     "t naive: nessuna correzione per sovrapposizione e test multipli.</div>");
   int first[3] = {0, 3, 7};
   int cnt[3]   = {3, 4, 2};
   string title[3] = {"1. Intensit&agrave; della candela del segnale (TR/ATR)", "2. Regime di volatilit&agrave; (percentile)", "3. La volatilit&agrave; sta salendo?"};
   for(int g = 0; g < 3; g++)
     {
      W("<h3>" + title[g] + " &mdash; netto medio per posizione, punti (segnali)</h3>");
      W("<table><tr><th>TF</th>");
      for(int c = 0; c < cnt[g]; c++) W("<th>" + CndLabel(first[g] + c) + "</th>");
      W("</tr>");
      for(int t = 0; t < g_nT; t++)
        {
         if(g_accTH[(t * g_nH + g_refH) * ACCN] < 1.0) continue;
         W("<tr><td>" + g_tfName[t] + "</td>");
         for(int c = 0; c < cnt[g]; c++) W(AccCell(g_accCnd, (t * NCAT + first[g] + c) * ACCN));
         W("</tr>");
        }
      W("</table>");
      W("<h3>" + title[g] + " &mdash; MFE medio / base della stessa categoria [MFE/MAE]</h3>");
      W("<table><tr><th>TF</th>");
      for(int c = 0; c < cnt[g]; c++) W("<th>" + CndLabel(first[g] + c) + "</th>");
      W("</tr>");
      for(int t = 0; t < g_nT; t++)
        {
         if(g_accTH[(t * g_nH + g_refH) * ACCN] < 1.0) continue;
         W("<tr><td>" + g_tfName[t] + "</td>");
         for(int c = 0; c < cnt[g]; c++)
           {
            const int cat = first[g] + c;
            const int p = (t * NCAT + cat) * ACCN;
            double n = g_accCnd[p];
            if(n < 1.0) { W("<td>-</td>"); continue; }
            double mfe = g_accCnd[p + 1] / n, mae = g_accCnd[p + 2] / n;
            double bs  = CndBase(t, cat);
            double rb  = (bs > 0.0) ? mfe / bs : 0.0;
            double ra  = (mae > 0.0) ? mfe / mae : 0.0;
            string col = (n < InpMinPerBucket) ? "#4c566a" : (ra > 1.0 ? "#a3be8c" : "#bf616a");
            W(Td(F2(rb) + " [" + F2(ra) + "]", col));
            double ret = g_accCnd[p + 3] / n;
            double var = (n > 1.0) ? (g_accCnd[p + 4] - n * ret * ret) / (n - 1.0) : 0.0;
            double tn  = (var > 0.0) ? ret / (MathSqrt(var) / MathSqrt(n)) : 0.0;
            g_dg += "VST|" + g_tfName[t] + "|" + CndTag(cat) + "|n|" + F0(n) + "|mfe|" + F0(mfe) + "|mae|" + F0(mae) +
                    "|base|" + F0(bs) + "|ret|" + F1(ret) + "|t|" + F2(tn) + "|cost|" + F1(g_accCnd[p + 5] / n) + "\n";
           }
         W("</tr>");
        }
      W("</table>");
     }
  }

//+------------------------------------------------------------------+
//| GIORNI DELLA SETTIMANA E ORARI CHE RAGGIUNGONO I PUNTI            |
//| P = % di segnali il cui movimento favorevole (lordo, dal prezzo   |
//| d'ingresso) raggiunge il livello entro la tenuta di riferimento.  |
//| Base = stessa probabilita' con entrata in direzione casuale nello |
//| STESSO giorno e nella STESSA fascia: toglie l'effetto della       |
//| volatilita' di quel momento.                                      |
//+------------------------------------------------------------------+
int DbIdx(const int t, const int d, const int b) { return (t * 7 + d) * g_nB + b; }

double DbEvN(const int t, const int d, const int b)
  {
   const int base = DbIdx(t, d, b) * (g_nL + 1);
   double sm = 0.0;
   for(int c = 0; c <= g_nL; c++) sm += (double)g_dbLev[base + c];
   return sm;
  }

double DbEvReach(const int t, const int d, const int b, const int l)
  {
   return SuffixCount(g_dbLev, DbIdx(t, d, b) * (g_nL + 1), l);
  }

double DbBase(const int t, const int d, const int b, const int l)
  {
   const int i = DbIdx(t, d, b);
   if(g_dbBN[i] <= 0) return 0.0;
   return SuffixCount(g_dbBHist, i * (g_nL + 1), l) / (2.0 * (double)g_dbBN[i]);
  }

//--- probabilita' osservata e di base su un insieme di celle (giorni dLo..dHi, fasce bLo..bHi); la base e' pesata sui segnali
void DbAgg(const int t, const int dLo, const int dHi, const int bLo, const int bHi, const int l,
           double &n, double &pObs, double &pBase)
  {
   double sn = 0.0, sr = 0.0, sb = 0.0;
   for(int d = dLo; d <= dHi; d++)
      for(int b = bLo; b <= bHi; b++)
        {
         const double en = DbEvN(t, d, b);
         if(en <= 0.0) continue;
         sn += en;
         sr += DbEvReach(t, d, b, l);
         sb += en * DbBase(t, d, b, l);
        }
   n = sn;
   pObs  = (sn > 0.0) ? 100.0 * sr / sn : 0.0;
   pBase = (sn > 0.0) ? 100.0 * sb / sn : 0.0;
  }

//--- fino a 4 livelli "chiave" per le tabelle compatte
int KeyLevels(int &idx[])
  {
   ArrayResize(idx, 0);
   if(g_nL <= 4)
     {
      ArrayResize(idx, g_nL);
      for(int i = 0; i < g_nL; i++) idx[i] = i;
      return g_nL;
     }
   int cand[4];
   cand[0] = 0; cand[1] = g_nL / 3; cand[2] = (2 * g_nL) / 3; cand[3] = g_nL - 1;
   for(int i = 0; i < 4; i++)
     {
      bool dup = false;
      for(int q = 0; q < ArraySize(idx); q++) if(idx[q] == cand[i]) dup = true;
      if(dup) continue;
      const int k = ArraySize(idx);
      ArrayResize(idx, k + 1);
      idx[k] = cand[i];
     }
   return ArraySize(idx);
  }

int MatrixLevelIdx()
  {
   int best = 0;
   double bd = 1.0e18;
   for(int l = 0; l < g_nL; l++)
     {
      double d = MathAbs(g_lev[l] - InpMatrixLevel);
      if(d < bd) { bd = d; best = l; }
     }
   return best;
  }

//--- TF di riferimento per le sintesi: quello dell'elenco spunte se ha campione, altrimenti il TF con piu' segnali misurati
int RefTFIndex()
  {
   if(g_evT >= 0 && g_accTH[(g_evT * g_nH + g_refH) * ACCN] >= g_minN) return g_evT;
   int best = -1;
   double bn = 0.0;
   for(int t = 0; t < g_nT; t++)
     {
      double n = g_accTH[(t * g_nH + g_refH) * ACCN];
      if(n > bn) { bn = n; best = t; }
     }
   return best;
  }

//--- le k fasce con la P piu' alta (mode 0) o il maggior vantaggio sulla base P/base (mode 1) per il livello l
int BestBuckets(const int t, const int l, const int mode, const int k, int &out[])
  {
   ArrayResize(out, 0);
   double sc[];
   bool   used[];
   ArrayResize(sc, g_nB);
   ArrayResize(used, g_nB);
   for(int b = 0; b < g_nB; b++)
     {
      used[b] = false;
      sc[b]   = -1.0e18;
      double n, po, pb;
      DbAgg(t, 0, 6, b, b, l, n, po, pb);
      if(n < InpMinPerBucket) continue;
      if(mode == 0) sc[b] = po;
      else if(pb >= 1.0) sc[b] = po / pb;
     }
   for(int r = 0; r < k; r++)
     {
      int bi = -1;
      double bs = -1.0e17;
      for(int b = 0; b < g_nB; b++)
         if(!used[b] && sc[b] > bs) { bs = sc[b]; bi = b; }
      if(bi < 0) break;
      used[bi] = true;
      const int m = ArraySize(out);
      ArrayResize(out, m + 1);
      out[m] = bi;
     }
   return ArraySize(out);
  }

string BktInfo(const int t, const int b, const int l)
  {
   double n, po, pb;
   DbAgg(t, 0, 6, b, b, l, n, po, pb);
   return BktLabel(b) + " " + F0(po) + "% (base " + F0(pb) + "%, " + F0(n) + " segnali)";
  }

string ReachCol(const double po, const double pb)
  {
   if(po > pb * 1.1 && po >= 1.0) return "#a3be8c";
   if(po < pb * 0.9 && pb >= 1.0) return "#bf616a";
   return "#7b8794";
  }

//--- giorno della settimana: segnali, MFE/MAE, netto, costo e probabilita' di raggiungere ogni livello (base fra parentesi)
void RepDowTable(const int t)
  {
   W("<table><tr><th>Giorno</th><th>Segnali</th><th>MFE medio</th><th>MAE medio</th><th>Netto medio</th><th>Costo medio</th>");
   for(int l = 0; l < g_nL; l++) W("<th>&ge; " + F0(g_lev[l]) + " pt</th>");
   W("</tr>");
   int ord[7] = {1, 2, 3, 4, 5, 6, 0};
   for(int q = 0; q < 7; q++)
     {
      const int d = ord[q];
      const int p = (t * 7 + d) * ACCN;
      const double n = g_accDow[p];
      if(n < 1.0) continue;
      const string cls = (n < InpMinPerBucket) ? " class='thin'" : "";
      W("<tr" + cls + "><td>" + DowName(d) + "</td>" + Td(F0(n)) + Td(F0(g_accDow[p + 1] / n)) + Td(F0(g_accDow[p + 2] / n)) +
        Td("<b>" + F1(g_accDow[p + 3] / n) + "</b>", ColSign(g_accDow[p + 3] / n)) + Td(F1(g_accDow[p + 5] / n)));
      for(int l = 0; l < g_nL; l++)
        {
         double nn, po, pb;
         DbAgg(t, d, d, 0, g_nB - 1, l, nn, po, pb);
         W(Td(F0(po) + " (" + F0(pb) + ")", ReachCol(po, pb)));
        }
      W("</tr>");
     }
   W("</table>");
  }

//--- fasce orarie: probabilita' di raggiungere i livelli chiave
void RepHoursReach(const int t)
  {
   int key[];
   const int nk = KeyLevels(key);
   if(nk < 1) return;
   W("<table><tr><th>Fascia (entrata, server + offset)</th><th>Segnali</th>");
   for(int q = 0; q < nk; q++) W("<th>&ge; " + F0(g_lev[key[q]]) + " pt: % (base)</th>");
   W("</tr>");
   for(int b = 0; b < g_nB; b++)
     {
      double n, po, pb;
      DbAgg(t, 0, 6, b, b, key[0], n, po, pb);
      if(n < 1.0) continue;
      const string cls = (n < InpMinPerBucket) ? " class='thin'" : "";
      W("<tr" + cls + "><td>" + BktLabel(b) + "</td>" + Td(F0(n)));
      for(int q = 0; q < nk; q++)
        {
         double n2, po2, pb2;
         DbAgg(t, 0, 6, b, b, key[q], n2, po2, pb2);
         W(Td(F0(po2) + " (" + F0(pb2) + ")", ReachCol(po2, pb2)));
        }
      W("</tr>");
     }
   W("</table>");
  }

//--- classifica: per ogni livello le fasce che lo raggiungono piu' spesso
void RepHoursRanking(const int t)
  {
   W("<table><tr><th>Livello</th><th>Fasce con la probabilit&agrave; pi&ugrave; alta (P %, base %, segnali)</th>"
     "<th>Fasce con il maggior vantaggio sulla base (P / base)</th></tr>");
   for(int l = 0; l < g_nL; l++)
     {
      int top0[], top1[];
      const int n0 = BestBuckets(t, l, 0, 3, top0);
      const int n1 = BestBuckets(t, l, 1, 3, top1);
      if(n0 < 1) continue;
      string c0 = "", c1 = "";
      for(int r = 0; r < n0; r++) c0 += (r > 0 ? "<br>" : "") + BktInfo(t, top0[r], l);
      for(int r = 0; r < n1; r++)
        {
         double n, po, pb;
         DbAgg(t, 0, 6, top1[r], top1[r], l, n, po, pb);
         c1 += (r > 0 ? "<br>" : "") + BktLabel(top1[r]) + " x" + F2(pb > 0.0 ? po / pb : 0.0) + " (" + F0(po) + "% contro " + F0(pb) + "%)";
        }
      W("<tr><td>&ge; " + F0(g_lev[l]) + " pt</td><td style='text-align:left'>" + c0 + "</td><td style='text-align:left'>" + c1 + "</td></tr>");
     }
   W("</table>");
  }

//--- matrice giorno x ora: probabilita' di raggiungere il livello InpMatrixLevel
void RepDowHourMatrix(const int t)
  {
   const int lm  = MatrixLevelIdx();
   const int per = MathMax(1, 60 / g_bMin);
   W("<div class='note'>Probabilit&agrave; (%) di raggiungere <b>+" + F0(g_lev[lm]) + " pt</b> entro " + IS(g_hor[g_refH]) +
     " min, per giorno e ora d'ingresso (server + offset). Verde = sopra la base dello stesso giorno e fascia, rosso = sotto. "
     "Passa il mouse su una cella per vedere base e numero di segnali. Celle grigie = meno di " + IS(InpMinPerBucket) + " segnali.</div>");
   W("<table><tr><th>Giorno \\ ora</th>");
   for(int h = 0; h < 24; h++) W("<th>" + IntegerToString(h) + "</th>");
   W("</tr>");
   int ord[7] = {1, 2, 3, 4, 5, 6, 0};
   for(int q = 0; q < 7; q++)
     {
      const int d = ord[q];
      if(g_accDow[(t * 7 + d) * ACCN] < 1.0) continue;
      W("<tr><td>" + DowName(d) + "</td>");
      for(int h = 0; h < 24; h++)
        {
         const int bLo = h * per;
         if(bLo >= g_nB) { W("<td>-</td>"); continue; }
         const int bHi = MathMin(g_nB - 1, bLo + per - 1);
         double n, po, pb;
         DbAgg(t, d, d, bLo, bHi, lm, n, po, pb);
         if(n < 1.0) { W("<td>-</td>"); continue; }
         const string tip = " title='base " + F0(pb) + "% | segnali " + F0(n) + "'";
         if(n < InpMinPerBucket) { W("<td class='thin'" + tip + ">" + F0(po) + "</td>"); continue; }
         W("<td style='color:" + ReachCol(po, pb) + "'" + tip + ">" + F0(po) + "</td>");
        }
      W("</tr>");
     }
   W("</table>");
  }

void RepDowHours(const int t)
  {
   W("<h3>Per giorno della settimana: segnali, MFE/MAE, netto e probabilit&agrave; di raggiungere i livelli: P % (base %)</h3>");
   RepDowTable(t);
   W("<h3>Per fascia oraria: probabilit&agrave; di raggiungere i livelli chiave: P % (base %)</h3>");
   RepHoursReach(t);
   W("<h3>Quali orari raggiungono pi&ugrave; spesso ciascun livello</h3>");
   RepHoursRanking(t);
   W("<h3>Matrice giorno x ora</h3>");
   RepDowHourMatrix(t);
  }

void RepDowHoursMain()
  {
   const int rt = RefTFIndex();
   if(rt < 0) return;
   W("<h2>Giorni della settimana e orari che raggiungono i punti &mdash; " + g_tfName[rt] + ", entro " + IS(g_hor[g_refH]) + " min</h2>");
   W("<div class='note'><b>P</b> = percentuale di segnali il cui movimento favorevole (lordo, dal prezzo d'ingresso) raggiunge il livello entro la tenuta. "
     "<b>Base</b> = la stessa probabilit&agrave; con entrata in direzione casuale nello <b>stesso giorno e nella stessa fascia</b>: "
     "i momenti con pi&ugrave; volatilit&agrave; raggiungono i livelli pi&ugrave; spesso anche senza segnale, quindi conta il vantaggio sulla base (verde), non la P assoluta. "
     "Con molte fasce e giorni testati qualcuno supera la base per caso: cerca regolarit&agrave; fra TF vicini, non la singola cella. "
     "Le stesse tabelle per ogni timeframe sono nel dettaglio per TF.</div>");
   RepDowHours(rt);
  }

//+------------------------------------------------------------------+
//| CANDELE SUCCESSIVE AL SEGNALE - REPORT                            |
//| Dopo ogni segnale: quanti punti fanno le prossime m candele dello |
//| stesso TF, dal prezzo d'ingresso (open della candela successiva). |
//| Favorevole = massimo nella direzione del segnale, avverso = nella |
//| direzione opposta, range = massimo - minimo, chiusura = close     |
//| dell'm-esima candela. La BASE e' la stessa misura su tutte le     |
//| barre dello stesso TF e della stessa categoria (direzione         |
//| casuale): senza di essa un movimento ampio sembra merito del      |
//| segnale mentre e' solo la volatilita' di quel momento.            |
//+------------------------------------------------------------------+
struct NxStat
  {
   double n, fav, adv, rng, absMv, sMv, tMv;
  };

int NxCell(const int s, const int t, const int mem, const int mi)
  {
   return (((s * g_nT + t) * g_nMem + mem) * g_nM + mi);
  }

bool NxGet(const int s, const int t, const int mem, const int mi, NxStat &o)
  {
   const int p = NxCell(s, t, mem, mi) * NXF;
   const double n = g_nx[p];
   if(n < 1.0) return false;
   o.n     = n;
   o.fav   = g_nx[p + 1] / n;
   o.adv   = g_nx[p + 2] / n;
   o.rng   = g_nx[p + 3] / n;
   o.absMv = g_nx[p + 4] / n;
   o.sMv   = g_nx[p + 5] / n;
   const double var = (n > 1.0) ? (g_nx[p + 6] - n * o.sMv * o.sMv) / (n - 1.0) : 0.0;
   o.tMv   = (var > 0.0) ? o.sMv / (MathSqrt(var) / MathSqrt(n)) : 0.0;
   return true;
  }

//--- base della categoria; per "tutti" (mem 0) e' la media delle basi di ciascuna fascia oraria pesata sui segnali della serie
bool NxBase(const int s, const int t, const int mem, const int mi, NxStat &o)
  {
   o.n = 0.0; o.fav = 0.0; o.adv = 0.0; o.rng = 0.0; o.absMv = 0.0; o.sMv = 0.0; o.tMv = 0.0;
   if(mem != 0)
     {
      const int p = ((t * g_nMem + mem) * g_nM + mi) * NXF;
      const double n = g_nxb[p];
      if(n < 1.0) return false;
      o.n = n; o.fav = g_nxb[p + 1] / n; o.adv = g_nxb[p + 2] / n; o.rng = g_nxb[p + 3] / n; o.absMv = g_nxb[p + 4] / n;
      return true;
     }
   double w = 0.0, f = 0.0, r = 0.0, a = 0.0;
   for(int b = 0; b < g_nB; b++)
     {
      const int    mm = NMEM1 + b;
      const double ns = g_nx[NxCell(s, t, mm, mi) * NXF];
      const int    pb = ((t * g_nMem + mm) * g_nM + mi) * NXF;
      const double nb = g_nxb[pb];
      if(ns < 1.0 || nb < 1.0) continue;
      w += ns;
      f += ns * g_nxb[pb + 1] / nb;
      r += ns * g_nxb[pb + 3] / nb;
      a += ns * g_nxb[pb + 4] / nb;
     }
   if(w <= 0.0) return false;
   o.n = w; o.fav = f / w; o.adv = o.fav; o.rng = r / w; o.absMv = a / w;
   return true;
  }

//--- percentile q (0..1) dall'istogramma logaritmico; which: 0 = favorevole, 1 = range
double NxPct(const int s, const int t, const int mem, const int mi, const int which, const double n, const double q)
  {
   const int    h      = (NxCell(s, t, mem, mi) * 2 + which) * NXB;
   const double target = q * n;
   double cum = 0.0;
   for(int b = 0; b < NXB; b++)
     {
      const double c = (double)g_nxh[h + b];
      if(c <= 0.0) continue;
      if(cum + c >= target)
        {
         const double lo = MathExp(b * NXSTEP) - 1.0;
         const double hi = MathExp((b + 1) * NXSTEP) - 1.0;
         const double fr = MathMin(1.0, MathMax(0.0, (target - cum) / c));
         return lo + (hi - lo) * fr;
        }
      cum += c;
     }
   return MathExp(NXB * NXSTEP) - 1.0;
  }

string NxIntLabel(const int b)
  {
   if(b <= 0) return "TR/ATR &lt; " + F2(g_ibEdge[0]);
   if(b >= 5) return "TR/ATR &ge; " + F2(g_ibEdge[4]);
   return "TR/ATR " + F2(g_ibEdge[b - 1]) + " &ndash; " + F2(g_ibEdge[b]);
  }

string NxIntPlain(const int b)
  {
   if(b <= 0) return "TR/ATR < " + F2(g_ibEdge[0]);
   if(b >= 5) return "TR/ATR >= " + F2(g_ibEdge[4]);
   return "TR/ATR " + F2(g_ibEdge[b - 1]) + "-" + F2(g_ibEdge[b]);
  }

string NxMemLabel(const int mem)
  {
   if(mem == 0)  return "Tutti i segnali";
   if(mem <= 7)  return DowName(mem - 1);
   if(mem <= 13) return NxIntLabel(mem - 8);
   switch(mem)
     {
      case 14: return "Regime LOW";
      case 15: return "Regime NORMAL";
      case 16: return "Regime HIGH";
      case 17: return "Regime EXTREME";
      case 18: return "Volatilit&agrave; in calo o ferma";
      case 19: return "Volatilit&agrave; in aumento";
     }
   return BktLabel(mem - NMEM1);
  }

//--- verde se il valore supera la base di oltre il 10%, rosso se e' sotto di oltre il 10%, grigio scuro se il campione e' piccolo
string NxCol(const double v, const double base, const double n)
  {
   if(n < InpMinPerBucket) return "#4c566a";
   if(base <= 0.0) return "#7b8794";
   if(v > base * 1.1) return "#a3be8c";
   if(v < base * 0.9) return "#bf616a";
   return "#7b8794";
  }

string NxSub(const string txt)
  {
   return "<br><span style='color:#7b8794;font-size:11px'>" + txt + "</span>";
  }

string NxDuration(const int t, const int m)
  {
   const long mins = (long)m * g_tfSec[t] / 60L;
   if(mins >= 1440L) return F1((double)mins / 1440.0) + " g";
   if(mins >= 120L)  return F1((double)mins / 60.0) + " h";
   return IS(mins) + " min";
  }

//--- matrice TF x numero di candele; kind 0 = favorevole, 1 = avverso, 2 = range, 3 = chiusura
void RepNextMatrix(const int kind)
  {
   const int s = g_curSet;
   W("<table><tr><th>TF</th>");
   for(int k = 0; k < g_nM; k++) W("<th>dopo " + IS(g_nxM[k]) + " cand.</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      bool any = false;
      for(int k = 0; k < g_nM; k++) if(g_nx[NxCell(s, t, 0, k) * NXF] >= 1.0) any = true;
      if(!any) continue;
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int k = 0; k < g_nM; k++)
        {
         NxStat a, b;
         if(!NxGet(s, t, 0, k, a)) { W("<td>-</td>"); continue; }
         const bool hb = NxBase(s, t, 0, k, b);
         const string tip = " title='segnali " + F0(a.n) + " | durata " + NxDuration(t, g_nxM[k]) + "'";
         if(kind == 0)
           {
            W("<td style='color:" + NxCol(a.fav, b.fav, a.n) + "'" + tip + ">" + F0(a.fav) + (hb ? " (base " + F0(b.fav) + ")" : "") +
              NxSub("mediana " + F0(NxPct(s, t, 0, k, 0, a.n, 0.5)) + " &middot; p90 " + F0(NxPct(s, t, 0, k, 0, a.n, 0.9))) + "</td>");
           }
         else if(kind == 1)
           {
            const double ra = (a.adv > 0.0) ? a.fav / a.adv : 0.0;
            const string col = (a.n < InpMinPerBucket) ? "#4c566a" : (ra > 1.05 ? "#a3be8c" : (ra < 0.95 ? "#bf616a" : "#7b8794"));
            W("<td style='color:" + col + "'" + tip + ">" + F0(a.adv) + (hb ? " (base " + F0(b.adv) + ")" : "") +
              NxSub("favorevole / avverso " + F2(ra)) + "</td>");
           }
         else if(kind == 2)
           {
            const double ratio = (hb && b.rng > 0.0) ? a.rng / b.rng : 0.0;
            W("<td style='color:" + NxCol(a.rng, b.rng, a.n) + "'" + tip + ">" + F0(a.rng) + (hb ? " &times;" + F2(ratio) : "") +
              NxSub("mediana " + F0(NxPct(s, t, 0, k, 1, a.n, 0.5)) + " &middot; p90 " + F0(NxPct(s, t, 0, k, 1, a.n, 0.9))) + "</td>");
           }
         else
           {
            const string col = (a.n < InpMinPerBucket) ? "#4c566a" : ColTNaive(a.tMv);
            W("<td style='color:" + col + "'" + tip + ">" + Sg(a.sMv, 0) + " / " + F0(a.absMv) + NxSub("t naive " + F2(a.tMv)) + "</td>");
           }
        }
      W("</tr>");
     }
   W("</table>");
  }

//--- TF x intensita' della candela del segnale, alla distanza di riferimento
void RepNextIntensity()
  {
   const int s = g_curSet, k = g_nxRef;
   W("<table><tr><th>TF</th>");
   for(int b = 0; b < 6; b++) W("<th>" + NxIntLabel(b) + "</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      bool any = false;
      for(int b = 0; b < 6; b++) if(g_nx[NxCell(s, t, 8 + b, k) * NXF] >= 1.0) any = true;
      if(!any) continue;
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int b = 0; b < 6; b++)
        {
         NxStat a, bs;
         if(!NxGet(s, t, 8 + b, k, a)) { W("<td>-</td>"); continue; }
         const bool hb = NxBase(s, t, 8 + b, k, bs);
         W("<td style='color:" + NxCol(a.fav, bs.fav, a.n) + "'>" + F0(a.fav) + (hb ? " (base " + F0(bs.fav) + ")" : "") +
           NxSub("range " + F0(a.rng) + (hb && bs.rng > 0.0 ? " &times;" + F2(a.rng / bs.rng) : "") + " &middot; n " + F0(a.n)) + "</td>");
        }
      W("</tr>");
     }
   W("</table>");
  }

//--- fasce orarie x TF, alla distanza di riferimento; kind 0 = favorevole, 1 = range
void RepNextHours(const int kind)
  {
   const int s = g_curSet, k = g_nxRef;
   int cols[];
   ArrayResize(cols, 0);
   for(int t = 0; t < g_nT; t++)
     {
      if(g_nx[NxCell(s, t, 0, k) * NXF] < 1.0) continue;
      const int c = ArraySize(cols);
      ArrayResize(cols, c + 1);
      cols[c] = t;
     }
   const int nc = ArraySize(cols);
   if(nc < 1) return;
   W("<table><tr><th>Fascia (entrata, server + offset)</th>");
   for(int c = 0; c < nc; c++) W("<th>" + g_tfName[cols[c]] + "</th>");
   W("</tr>");
   for(int b = 0; b < g_nB; b++)
     {
      bool any = false;
      for(int c = 0; c < nc; c++) if(g_nx[NxCell(s, cols[c], NMEM1 + b, k) * NXF] >= 1.0) any = true;
      if(!any) continue;
      W("<tr><td>" + BktLabel(b) + "</td>");
      for(int c = 0; c < nc; c++)
        {
         NxStat a, bs;
         if(!NxGet(s, cols[c], NMEM1 + b, k, a)) { W("<td>-</td>"); continue; }
         const bool hb = NxBase(s, cols[c], NMEM1 + b, k, bs);
         const double v  = (kind == 0) ? a.fav : a.rng;
         const double vb = hb ? ((kind == 0) ? bs.fav : bs.rng) : 0.0;
         W("<td style='color:" + NxCol(v, vb, a.n) + "' title='segnali " + F0(a.n) + " | base " + F0(vb) + "'>" + F0(v) + "</td>");
        }
      W("</tr>");
     }
   W("</table>");
  }

//--- TF x giorno della settimana, alla distanza di riferimento
void RepNextDow()
  {
   const int s = g_curSet, k = g_nxRef;
   int ord[7] = {1, 2, 3, 4, 5, 6, 0};
   W("<table><tr><th>TF</th>");
   for(int q = 0; q < 7; q++) W("<th>" + DowName(ord[q]) + "</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      if(g_nx[NxCell(s, t, 0, k) * NXF] < 1.0) continue;
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int q = 0; q < 7; q++)
        {
         NxStat a, bs;
         if(!NxGet(s, t, 1 + ord[q], k, a)) { W("<td>-</td>"); continue; }
         const bool hb = NxBase(s, t, 1 + ord[q], k, bs);
         W("<td style='color:" + NxCol(a.fav, bs.fav, a.n) + "'>" + F0(a.fav) + (hb ? " (base " + F0(bs.fav) + ")" : "") +
           NxSub("range " + F0(a.rng) + (hb && bs.rng > 0.0 ? " &times;" + F2(a.rng / bs.rng) : "") + " &middot; n " + F0(a.n)) + "</td>");
        }
      W("</tr>");
     }
   W("</table>");
  }

//--- righe per categoria (un TF): segnali, favorevole/avverso per ogni m, e a distanza di riferimento range, base, percentili, chiusura
void RepNextCat(const int t, const int &mems[], const int cnt, const string head)
  {
   const int s = g_curSet, k = g_nxRef;
   W("<table><tr><th>" + head + "</th><th>Segnali</th>");
   for(int q = 0; q < g_nM; q++) W("<th>dopo " + IS(g_nxM[q]) + ": favorevole / avverso</th>");
   W("<th>Range dopo " + IS(g_nxM[k]) + "</th><th>Range base</th><th>&times; base</th><th>Favorevole mediana</th><th>Favorevole p90</th>"
     "<th>Range mediana</th><th>Range p90</th><th>Chiusura con segno</th></tr>");
   for(int r = 0; r < cnt; r++)
     {
      const int mem = mems[r];
      NxStat a, b;
      if(!NxGet(s, t, mem, k, a)) continue;
      const bool hb = NxBase(s, t, mem, k, b);
      const string cls = (a.n < InpMinPerBucket) ? " class='thin'" : "";
      W("<tr" + cls + "><td>" + NxMemLabel(mem) + "</td>" + Td(F0(a.n)));
      for(int q = 0; q < g_nM; q++)
        {
         NxStat c;
         if(NxGet(s, t, mem, q, c)) W(Td(F0(c.fav) + " / " + F0(c.adv)));
         else W("<td>-</td>");
        }
      const double ratio = (hb && b.rng > 0.0) ? a.rng / b.rng : 0.0;
      W(Td("<b>" + F0(a.rng) + "</b>") + Td(hb ? F0(b.rng) : "-") + (hb ? Td(F2(ratio), NxCol(a.rng, b.rng, a.n)) : Td("-")) +
        Td(F0(NxPct(s, t, mem, k, 0, a.n, 0.5))) + Td(F0(NxPct(s, t, mem, k, 0, a.n, 0.9))) +
        Td(F0(NxPct(s, t, mem, k, 1, a.n, 0.5))) + Td(F0(NxPct(s, t, mem, k, 1, a.n, 0.9))) +
        Td(Sg(a.sMv, 0) + " (t " + F2(a.tMv) + ")", ColTNaive(a.tMv)) + "</tr>");
     }
   W("</table>");
  }

//--- dettaglio di un TF: intensita', giorno, regime, fascia oraria
void RepNextTF(const int t)
  {
   int ms[];
   W("<p style='color:#7b8794'>Candele successive del TF " + g_tfName[t] + ": ogni candela dura " + NxDuration(t, 1) +
     ". Punti dal prezzo d'ingresso (open della candela dopo il segnale), media su tutti i segnali della categoria.</p>");
   ArrayResize(ms, 7);
   ms[0] = 0;
   for(int i = 0; i < 6; i++) ms[i + 1] = 8 + i;
   W("<h4>Per intensit&agrave; della candela del segnale</h4>");
   RepNextCat(t, ms, 7, "Intensit&agrave;");
   int ord[7] = {1, 2, 3, 4, 5, 6, 0};
   ArrayResize(ms, 7);
   for(int i = 0; i < 7; i++) ms[i] = 1 + ord[i];
   W("<h4>Per giorno della settimana</h4>");
   RepNextCat(t, ms, 7, "Giorno");
   if(InpUseVolState)
     {
      ArrayResize(ms, 6);
      for(int i = 0; i < 6; i++) ms[i] = 14 + i;
      W("<h4>Per regime di volatilit&agrave; e direzione del percentile</h4>");
      RepNextCat(t, ms, 6, "Stato");
     }
   ArrayResize(ms, g_nB);
   for(int b = 0; b < g_nB; b++) ms[b] = NMEM1 + b;
   W("<h4>Per fascia oraria</h4>");
   RepNextCat(t, ms, g_nB, "Fascia");
  }

void RepNext()
  {
   const int s = g_curSet;
   W("<h2>Quanto si muove il prezzo dopo il segnale: le candele successive (punti)</h2>");
   W("<div class='note'>Per ogni segnale si misurano le <b>prossime m candele dello stesso timeframe</b> (m = " + InpNextCandles +
     "), in punti dal prezzo d'ingresso (open della candela che segue il segnale, spread escluso). "
     "<b>Favorevole</b> = massimo raggiunto nella direzione del segnale; <b>avverso</b> = nella direzione opposta; "
     "<b>range</b> = massimo meno minimo, senza direzione: &egrave; la risposta a &laquo;quanto pu&ograve; spostarsi la candela dopo il segnale&raquo;; "
     "<b>chiusura</b> = spostamento fino alla chiusura dell'm-esima candela, con segno positivo se nella direzione del segnale / valore assoluto. "
     "<b>Mediana</b> e <b>p90</b> mostrano la dispersione: la media &egrave; trascinata dai giorni eccezionali. "
     "La <b>base</b> (fra parentesi, &times;) &egrave; la stessa misura su tutte le barre dello stesso TF e della stessa categoria, direzione casuale: "
     "verde = oltre la base di pi&ugrave; del 10%, rosso = sotto di pi&ugrave; del 10%. Per la riga &laquo;tutti&raquo; la base &egrave; pesata sulle stesse fasce orarie dei segnali. "
     "Una candela ampia prima del segnale rende pi&ugrave; ampia anche la successiva (la volatilit&agrave; si raggruppa), per questo le tabelle per intensit&agrave; hanno la propria base. "
     "Intensit&agrave; = TR/ATR della candela del segnale (soglie " + F2(g_ibEdge[0]) + ", " + F2(g_ibEdge[1]) + ", " + F2(g_ibEdge[2]) + ", " + F2(g_ibEdge[3]) + ", " + F2(g_ibEdge[4]) +
     "). Le finestre intraday che attraversano un buco di dati oltre " + IS(InpMaxGapMin) + " min (weekend, festivi) non sono contate. "
     "Celle grigie scure = meno di " + IS(InpMinPerBucket) + " segnali; passa il mouse su una cella per numero di segnali e durata.</div>");

   W("<h3>1. Escursione favorevole media (punti nella direzione del segnale) &mdash; base fra parentesi</h3>");
   RepNextMatrix(0);
   W("<h3>2. Escursione avversa media (punti contro la direzione del segnale)</h3>");
   RepNextMatrix(1);
   W("<h3>3. Range medio (massimo &minus; minimo, senza direzione) &mdash; &times; base</h3>");
   RepNextMatrix(2);
   W("<h3>4. Chiusura dell'm-esima candela: spostamento con segno nella direzione del segnale / valore assoluto</h3>");
   RepNextMatrix(3);
   W("<h3>5. Per intensit&agrave; della candela del segnale &mdash; dopo " + IS(g_nxM[g_nxRef]) + " candela/e: favorevole (base), range &times; base, segnali</h3>");
   RepNextIntensity();
   W("<h3>6. Per giorno della settimana &mdash; dopo " + IS(g_nxM[g_nxRef]) + " candela/e: favorevole (base), range &times; base, segnali</h3>");
   RepNextDow();
   W("<h3>7. Per fascia oraria e TF &mdash; escursione favorevole media dopo " + IS(g_nxM[g_nxRef]) + " candela/e</h3>");
   RepNextHours(0);
   W("<h3>8. Per fascia oraria e TF &mdash; range medio dopo " + IS(g_nxM[g_nxRef]) + " candela/e</h3>");
   RepNextHours(1);
   W("<div class='note'>Il dettaglio per categoria (intensit&agrave;, giorno, regime, fascia) con mediana, p90 e base di ciascun TF &egrave; nel riquadro di ogni TF, pi&ugrave; in basso.</div>");

   //--- digest
   for(int t = 0; t < g_nT; t++)
     {
      for(int q = 0; q < g_nM; q++)
        {
         NxStat a, b;
         if(!NxGet(s, t, 0, q, a)) continue;
         const bool hb = NxBase(s, t, 0, q, b);
         g_dg += "NXT|" + g_tfName[t] + "|m|" + IS(g_nxM[q]) + "|n|" + F0(a.n) + "|fav|" + F0(a.fav) + "|adv|" + F0(a.adv) +
                 "|rng|" + F0(a.rng) + "|basefav|" + (hb ? F0(b.fav) : "-") + "|baserng|" + (hb ? F0(b.rng) : "-") +
                 "|abs|" + F0(a.absMv) + "|smv|" + F1(a.sMv) + "|tmv|" + F2(a.tMv) +
                 "|favp50|" + F0(NxPct(s, t, 0, q, 0, a.n, 0.5)) + "|favp90|" + F0(NxPct(s, t, 0, q, 0, a.n, 0.9)) +
                 "|rngp50|" + F0(NxPct(s, t, 0, q, 1, a.n, 0.5)) + "|rngp90|" + F0(NxPct(s, t, 0, q, 1, a.n, 0.9)) + "\n";
        }
      for(int b2 = 0; b2 < 6; b2++)
        {
         NxStat a, b;
         if(!NxGet(s, t, 8 + b2, g_nxRef, a)) continue;
         const bool hb = NxBase(s, t, 8 + b2, g_nxRef, b);
         g_dg += "NXI|" + g_tfName[t] + "|" + NxIntPlain(b2) + "|m|" + IS(g_nxM[g_nxRef]) + "|n|" + F0(a.n) + "|fav|" + F0(a.fav) +
                 "|adv|" + F0(a.adv) + "|rng|" + F0(a.rng) + "|basefav|" + (hb ? F0(b.fav) : "-") + "|baserng|" + (hb ? F0(b.rng) : "-") + "\n";
        }
      for(int d2 = 0; d2 < 7; d2++)
        {
         NxStat a, b;
         if(!NxGet(s, t, 1 + d2, g_nxRef, a)) continue;
         const bool hb = NxBase(s, t, 1 + d2, g_nxRef, b);
         g_dg += "NXD|" + g_tfName[t] + "|" + DowName(d2) + "|m|" + IS(g_nxM[g_nxRef]) + "|n|" + F0(a.n) + "|fav|" + F0(a.fav) +
                 "|rng|" + F0(a.rng) + "|basefav|" + (hb ? F0(b.fav) : "-") + "|baserng|" + (hb ? F0(b.rng) : "-") + "\n";
        }
      if(InpDigestTOD)
         for(int bk = 0; bk < g_nB; bk++)
           {
            NxStat a, b;
            if(!NxGet(s, t, NMEM1 + bk, g_nxRef, a)) continue;
            const bool hb = NxBase(s, t, NMEM1 + bk, g_nxRef, b);
            g_dg += "NXH|" + g_tfName[t] + "|" + BktLabel(bk) + "|m|" + IS(g_nxM[g_nxRef]) + "|n|" + F0(a.n) + "|fav|" + F0(a.fav) +
                    "|rng|" + F0(a.rng) + "|basefav|" + (hb ? F0(b.fav) : "-") + "|baserng|" + (hb ? F0(b.rng) : "-") + "\n";
           }
     }
  }

void RepStruct()
  {
   W("<h2>Posizione nella raffica (come il Sequence Filter dell'EA) &mdash; netto medio (n)</h2>");
   W("<div class='note'>1 = primo segnale dopo un segnale opposto, 2 = secondo consecutivo nella stessa direzione, ecc. "
     "&Egrave; la domanda che il Sequence Filter dell'EA tenta di sfruttare: qui la misuri senza filtrare. "
     "Celle grigie = meno di " + IS(InpMinPerBucket) + " eventi.</div>");
   W("<table><tr><th>TF</th>");
   for(int c = 1; c <= BCAP; c++) W("<th>" + IS(c) + (c == BCAP ? "+" : "") + "</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int c = 0; c < BCAP; c++) W(AccCell(g_accBur, (t * BCAP + c) * ACCN));
      W("</tr>");
     }
   W("</table>");

   W("<h2>Direzione: buy contro sell &mdash; netto medio (n)</h2>");
   W("<table><tr><th>TF</th><th>BUY</th><th>BUY MFE</th><th>BUY MAE</th><th>SELL</th><th>SELL MFE</th><th>SELL MAE</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int d = 0; d < 2; d++)
        {
         int p = (t * 2 + d) * ACCN;
         W(AccCell(g_accDir, p));
         double n = g_accDir[p];
         W(Td(n > 0.0 ? F0(g_accDir[p + 1] / n) : "-"));
         W(Td(n > 0.0 ? F0(g_accDir[p + 2] / n) : "-"));
        }
      W("</tr>");
     }
   W("</table>");

   W("<h2>Giorno della settimana (server + offset) &mdash; netto medio (n)</h2>");
   W("<table><tr><th>TF</th>");
   for(int d = 0; d < 7; d++) W("<th>" + DowName(d) + "</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int d = 0; d < 7; d++) W(AccCell(g_accDow, (t * 7 + d) * ACCN));
      W("</tr>");
     }
   W("</table>");
  }

void RepTOD(const int t)
  {
   W("<table><tr><th>Fascia (ora di entrata)</th><th>Segnali</th><th>MFE medio</th><th>MAE medio</th><th>MFE base</th>"
     "<th>MFE/base</th><th>Netto medio</th><th>t naive</th><th>Costo medio</th></tr>");
   for(int b = 0; b < g_nB; b++)
     {
      int p = (t * g_nB + b) * ACCN;
      double n = g_accBkt[p];
      if(n < 1.0) continue;
      double mfe = g_accBkt[p + 1] / n, mae = g_accBkt[p + 2] / n;
      double ret = g_accBkt[p + 3] / n, cost = g_accBkt[p + 5] / n;
      double var = (n > 1.0) ? (g_accBkt[p + 4] - n * ret * ret) / (n - 1.0) : 0.0;
      double tn  = (var > 0.0) ? ret / (MathSqrt(var) / MathSqrt(n)) : 0.0;
      int bi = (t * g_nH + g_refH) * g_nB + b;
      double bm = (g_bsN[bi] > 0) ? g_bsSum[bi] / (double)g_bsN[bi] : 0.0;
      string cls = (n < InpMinPerBucket) ? " class='thin'" : "";
      W("<tr" + cls + "><td>" + BktLabel(b) + "</td>" + Td(F0(n)) + Td(F0(mfe)) + Td(F0(mae)) + Td(F0(bm)) +
        Td(bm > 0.0 ? F2(mfe / bm) : "-") + Td("<b>" + F1(ret) + "</b>", ColSign(ret)) +
        Td(F2(tn), ColTNaive(tn)) + Td(F1(cost)) + "</tr>");
      if(InpDigestTOD)
         g_dg += "TOD|" + g_tfName[t] + "|" + BktLabel(b) + "|n|" + F0(n) + "|mfe|" + F0(mfe) + "|mae|" + F0(mae) +
                 "|base|" + F0(bm) + "|ret|" + F1(ret) + "|t|" + F2(tn) + "|cost|" + F1(cost) + "\n";
     }
   W("</table>");
  }

void RepSlot(const int t)
  {
   W("<table><tr><th>Candela nel " + ParentName() + "</th><th>Segnali</th><th>MFE medio</th><th>MAE medio</th>"
     "<th>Netto medio</th><th>t naive</th><th>Costo medio</th></tr>");
   for(int s = 0; s < g_slotCnt[t]; s++)
     {
      int p = (t * g_maxSlots + s) * ACCN;
      double n = g_accSlot[p];
      if(n < 1.0) continue;
      double mfe = g_accSlot[p + 1] / n, mae = g_accSlot[p + 2] / n;
      double ret = g_accSlot[p + 3] / n, cost = g_accSlot[p + 5] / n;
      double var = (n > 1.0) ? (g_accSlot[p + 4] - n * ret * ret) / (n - 1.0) : 0.0;
      double tn  = (var > 0.0) ? ret / (MathSqrt(var) / MathSqrt(n)) : 0.0;
      string cls = (n < InpMinPerBucket) ? " class='thin'" : "";
      W("<tr" + cls + "><td>" + IS(s + 1) + " di " + IS(g_slotCnt[t]) + "</td>" + Td(F0(n)) + Td(F0(mfe)) + Td(F0(mae)) +
        Td("<b>" + F1(ret) + "</b>", ColSign(ret)) + Td(F2(tn), ColTNaive(tn)) + Td(F1(cost)) + "</tr>");
     }
   W("</table>");
  }

void RepDetails()
  {
   W("<h2>Dettaglio per timeframe &mdash; orizzonte " + IS(g_hor[g_refH]) + " min</h2>");
   W("<div class='note'><b>Fascia oraria</b>: ora del server (+ offset) della barra M1 d'ingresso, cio&egrave; della chiusura del segnale. "
     "<b>Candela nel TF superiore</b>: posizione della barra del segnale dentro il " + ParentName() +
     " (es. 8 di 15 = ottava candela di un contenitore da 15). Con fasce strette il campione per riga &egrave; piccolo: "
     "le righe grigie sono rumore, non fasce operative.</div>");
   for(int t = 0; t < g_nT; t++)
     {
      if(g_accTH[(t * g_nH + g_refH) * ACCN] < 1.0) continue;
      W("<details><summary><b>" + g_tfName[t] + "</b> &mdash; fasce orarie, " + string(g_slotOK[t] ? "candela nel contenitore, " : "") + "target, tenuta e candele successive</summary>");
      W("<h3>Fasce orarie</h3>");
      RepTOD(t);
      if(g_slotOK[t])
        {
         W("<h3>Candela nel " + ParentName() + "</h3>");
         RepSlot(t);
        }
      W("<h3>Probabilit&agrave; di raggiungere il target entro la tenuta: segnale % (base %) &mdash; movimento lordo dal prezzo d'ingresso, spread escluso</h3>");
      RepReach(t);
      W("<h3>Quanto tenere e per quanti punti (una posizione per volta, tutto il giorno)</h3>");
      RepHeat(t);
      W("<h3>Giorni della settimana e orari che raggiungono i punti</h3>");
      RepDowHours(t);
      W("<h3>Candele successive al segnale: quanti punti si muove il prezzo</h3>");
      RepNextTF(t);
      W("</details>");
     }
  }

void RepTop()
  {
   if(g_topN < 1) return;
   //--- ordinamento per MFE decrescente
   int idx[];
   ArrayResize(idx, g_topN);
   for(int i = 0; i < g_topN; i++) idx[i] = i;
   for(int i = 0; i < g_topN - 1; i++)
      for(int j = i + 1; j < g_topN; j++)
         if(g_tpMfe[idx[j]] > g_tpMfe[idx[i]]) { int tmp = idx[i]; idx[i] = idx[j]; idx[j] = tmp; }

   W("<h2>Run pi&ugrave; lunghe &mdash; orizzonte " + IS(g_hor[g_refH]) + " min</h2>");
   W("<div class='note'>Classifica globale di tutti i TF per MFE lordo (punti dall'open d'ingresso nella direzione del segnale). "
     "Orologio comune M1, quindi confrontabili. Sono gli estremi della distribuzione: indicano <b>quando</b> si sono verificati, non dove c'&egrave; edge. "
     "Se si concentrano in poche giornate sono eventi di mercato, non una propriet&agrave; del segnale.</div>");
   W("<table><tr><th>#</th><th>Entrata (server + offset)</th><th>Giorno</th><th>TF</th><th>Dir</th><th>Candela TF sup.</th><th>Raffica</th>"
     "<th>MFE</th><th>MAE</th><th>Netto</th><th>Costo</th></tr>");
   for(int r = 0; r < g_topN; r++)
     {
      int q = idx[r];
      int t = g_tpTF[q];
      datetime tm = (datetime)((long)g_tpTime[q] + g_off);
      long dd = (long)tm / 86400L;
      int dow = (int)((dd + 4L) % 7L);
      string sl = g_slotOK[t] ? (IS(g_tpSlot[q] + 1) + "/" + IS(g_slotCnt[t])) : "-";
      W("<tr>" + Td(IS(r + 1)) + "<td>" + TimeToString(tm, TIME_DATE | TIME_MINUTES) + "</td>" + Td(DowName(dow)) +
        Td(g_tfName[t]) + Td(g_tpDir[q] > 0 ? "BUY" : "SELL", g_tpDir[q] > 0 ? "#a3be8c" : "#bf616a") + Td(sl) +
        Td(IS(g_tpBur[q])) + Td("<b>" + F0(g_tpMfe[q]) + "</b>") + Td(F0(g_tpMae[q])) +
        Td(F0(g_tpRet[q]), ColSign(g_tpRet[q])) + Td(F1(g_tpCost[q])) + "</tr>");
      if(r < 25)
         g_dg += "TOP|" + IS(r + 1) + "|" + TimeToString(tm, TIME_DATE | TIME_MINUTES) + "|" + g_tfName[t] + "|" +
                 IS(g_tpDir[q]) + "|slot|" + sl + "|burst|" + IS(g_tpBur[q]) + "|mfe|" + F0(g_tpMfe[q]) +
                 "|mae|" + F0(g_tpMae[q]) + "|ret|" + F0(g_tpRet[q]) + "|cost|" + F1(g_tpCost[q]) + "\n";
     }
   W("</table>");
  }

//+------------------------------------------------------------------+
//| RIEPILOGO SCRITTO E CONCLUSIONI                                   |
//| Testo generato con regole fisse dai numeri di questa corsa: non e' |
//| un giudizio, e' la lettura prudente delle tabelle. Solo ASCII e   |
//| nessun carattere '|' (il testo finisce anche nel digest).         |
//+------------------------------------------------------------------+
void AddConc(const int s, const string topic, const string text)
  {
   const int k = ArraySize(g_cSet);
   ArrayResize(g_cSet, k + 1);
   ArrayResize(g_cTopic, k + 1);
   ArrayResize(g_cText, k + 1);
   g_cSet[k]   = s;
   g_cTopic[k] = topic;
   g_cText[k]  = text;
  }

bool CndStat(const int t, const int cat, double &n, double &mean, double &var)
  {
   const int p = (t * NCAT + cat) * ACCN;
   n = g_accCnd[p];
   mean = 0.0;
   var  = 0.0;
   if(n < 1.0) return false;
   mean = g_accCnd[p + 3] / n;
   var  = (n > 1.0) ? (g_accCnd[p + 4] - n * mean * mean) / (n - 1.0) : 0.0;
   return true;
  }

void BuildConclusions(const int sIdx)
  {
   const int    rt   = RefTFIndex();
   const int    minN = (int)g_minN;
   const string hs   = IS(g_hor[g_refH]);

   //--- Dati
   {
    double tot = 0.0;
    for(int t = 0; t < g_nT; t++) tot += g_accTH[(t * g_nH + g_refH) * ACCN];
    bool used[];
    ArrayResize(used, g_nT);
    for(int t = 0; t < g_nT; t++) used[t] = false;
    string top = "";
    for(int q = 0; q < 3; q++)
      {
       int bi0 = -1;
       double bn = 0.0;
       for(int t = 0; t < g_nT; t++)
         {
          const double nn = g_accTH[(t * g_nH + g_refH) * ACCN];
          if(!used[t] && nn > bn) { bn = nn; bi0 = t; }
         }
       if(bi0 < 0) break;
       used[bi0] = true;
       top += (top == "" ? "" : ", ") + g_tfName[bi0] + " " + F0(bn);
      }
    datetime tEnd = (datetime)MathMin((long)InpTo, (long)g_m1Time[g_n1 - 1]);
    AddConc(sIdx, "Dati", "Simbolo " + _Symbol + ", periodo " + TimeToString(g_tStart, TIME_DATE) + " - " + TimeToString(tEnd, TIME_DATE) +
            ", " + IS(g_nT) + " TF analizzati. Segnali misurati a " + hs + " min: " + F0(tot) + " in totale" +
            (top != "" ? " (TF con piu' segnali: " + top + ")" : "") + ". Costo: " +
            (InpCostPoints > 0.0 ? ("fisso " + F1(InpCostPoints) + " pt") : ("spread M1 mediano " + F0(g_medSpr) + " pt")) +
            (InpExtraCostPts > 0.0 ? (" + extra " + F1(InpExtraCostPts) + " pt") : "") +
            ". Tutti i valori sono in punti (1 punto = " + DoubleToString(g_pt, _Digits) + ")." +
            (g_histWarn ? " ATTENZIONE: lo storico M1 e' piu' corto del periodo richiesto." : ""));
   }

   //--- direzione prima dei costi e netto dopo i costi, per TF all'orizzonte di riferimento
   int    K = 0, posN = 0, posS = 0, negS = 0, netPos = 0, netSig = 0;
   double wN = 0.0, wG = 0.0, wNet = 0.0, wCost = 0.0;
   double bestT = -1.0e9, worstT = 1.0e9, bestNet = -1.0e18;
   int    bi = -1, wi = -1, bni = -1;
   string sigList = "";
   for(int t = 0; t < g_nT; t++)
     {
      CellStat c;
      if(!GetCell(t, g_refH, c) || c.n < g_minN) continue;
      K++;
      if(c.gross > 0.0) posN++;
      if(c.tGross >= g_zB)  posS++;
      if(c.tGross <= -g_zB) negS++;
      if(c.ret > 0.0) netPos++;
      if(c.ret > 0.0 && c.tCl >= g_zB) { netSig++; sigList += (sigList == "" ? "" : ", ") + g_tfName[t]; }
      if(c.tGross > bestT)  { bestT = c.tGross;  bi = t; }
      if(c.tGross < worstT) { worstT = c.tGross; wi = t; }
      if(c.ret > bestNet)   { bestNet = c.ret;   bni = t; }
      wN += c.n; wG += c.n * c.gross; wNet += c.n * c.ret; wCost += c.n * c.cost;
     }
   g_agN[sIdx] = wN; g_agNet[sIdx] = wNet; g_agGross[sIdx] = wG;
   g_agGpos[sIdx] = posS; g_agGneg[sIdx] = negS; g_agNsig[sIdx] = netSig; g_agNtf[sIdx] = K;
   g_agAns[sIdx] = g_cAns;
   {
    int a1 = 0;
    for(int t = 0; t < g_nT; t++)
      {
       const int ci = sIdx * g_nT + t;
       if(g_cmpBoN[ci] >= MathMax(10.0, g_minN / 3.0) && g_cmpBoM[ci] > 0.0 && g_cmpBoT[ci] >= 2.0) a1++;
      }
    g_agA1ok[sIdx] = a1;
   }

   if(K < 1)
     {
      AddConc(sIdx, "Direzione prima dei costi", "Nessun TF ha almeno " + IS(minN) + " segnali misurati a " + hs + " min: campione insufficiente per qualunque conclusione.");
      AddConc(sIdx, "Dopo i costi", "Non valutabile: campione insufficiente.");
     }
   else
     {
      CellStat cb, cw, cn;
      GetCell(bi, g_refH, cb);
      GetCell(wi, g_refH, cw);
      GetCell(bni, g_refH, cn);
      string v1, v2;
      if(posS + negS == 0)
         v1 = "Nessun TF mostra una direzione distinguibile dal caso: da solo il segnale non anticipa la direzione del prezzo.";
      else if(negS == 0)
         v1 = "In almeno un TF il segnale anticipa la direzione gia' prima dei costi: controlla che lo stesso segno compaia nei TF vicini (il t cluster resta ottimista sulle tenute lunghe).";
      else if(posS == 0)
         v1 = "Il segnale e' contrario alla direzione del prezzo in almeno un TF: guarda la lettura INVERTI nelle tabelle A.";
      else
         v1 = "Segni opposti in TF diversi: nessuna direzione coerente.";
      AddConc(sIdx, "Direzione prima dei costi", "Orizzonte " + hs + " min, " + IS(K) + " TF con almeno " + IS(minN) +
              " segnali. Rendimento lordo medio (prima dei costi) positivo in " + IS(posN) + " TF; significativamente positivo in " + IS(posS) +
              " e significativamente negativo in " + IS(negS) + " (soglia di Bonferroni |t cluster| >= " + F2(g_zB) + "). Migliore: " + g_tfName[bi] +
              " lordo " + Sg(cb.gross) + " pt (t " + F2(cb.tGross) + "); peggiore: " + g_tfName[wi] + " lordo " + Sg(cw.gross) + " pt (t " + F2(cw.tGross) + "). " + v1);
      if(netSig == 0)
         v2 = "Nessun TF resta significativamente positivo dopo i costi: come entrata autonoma, con uscita a tempo, il segnale non ha un vantaggio operabile. "
              "Con segnali senza informazione il netto atteso e' circa meno il costo, qualunque sia la tenuta.";
      else
         v2 = "TF con netto positivo significativo: " + sigList + ". Sono candidati, non conferme: guarda se reggono fuori campione nelle tabelle A e se il segno e' lo stesso nei TF vicini.";
      AddConc(sIdx, "Dopo i costi", "Costo medio pesato " + F1(wCost / wN) + " pt, lordo medio pesato " + Sg(wG / wN) + " pt, netto medio pesato " + Sg(wNet / wN) +
              " pt (pesi = segnali di ciascun TF). Netto positivo in " + IS(netPos) + " TF su " + IS(K) + ", positivo e significativo (t cluster >= " + F2(g_zB) +
              ") in " + IS(netSig) + ". Miglior netto: " + g_tfName[bni] + " " + Sg(cn.ret) + " pt (t cluster " + F2(cn.tCl) + "). " + v2);
     }

   //--- tenuta: lordo e netto medi pesati per ogni orizzonte
   {
    string sh = "";
    double bestG = -1.0e18;
    int bh = -1;
    for(int h = 0; h < g_nH; h++)
      {
       double wn = 0.0, wg = 0.0, wr = 0.0;
       for(int t = 0; t < g_nT; t++)
         {
          CellStat c;
          if(!GetCell(t, h, c) || c.n < g_minN) continue;
          wn += c.n; wg += c.n * c.gross; wr += c.n * c.ret;
         }
       if(wn <= 0.0) continue;
       sh += (sh == "" ? "" : "; ") + IS(g_hor[h]) + "m " + Sg(wg / wn, 0) + "/" + Sg(wr / wn, 0);
       if(wg / wn > bestG) { bestG = wg / wn; bh = h; }
      }
    if(bh >= 0)
       AddConc(sIdx, "Tenuta", "Lordo/netto medio pesato per tenuta in minuti (pt, media dei TF con campione sufficiente, pesata sui segnali): " + sh +
               ". Se il lordo resta intorno a zero a ogni tenuta il segnale non ha informazione direzionale e il netto e' circa meno il costo qualunque sia la tenuta: "
               "allungare la tenuta non lo cambia. Tenuta con il lordo migliore: " + IS(g_hor[bh]) + " min (" + Sg(bestG) + " pt). "
               "La media pesata e' dominata dai TF con piu' segnali; il dettaglio per TF e' nelle tabelle A1 e B1.");
   }

   if(rt >= 0)
     {
      CellStat c;
      if(GetCell(rt, g_refH, c))
        {
         //--- punti raggiunti
         const int cell = rt * g_nH + g_refH;
         int key[];
         const int nk = KeyLevels(key);
         string sl = "";
         int above = 0, below = 0;
         for(int q = 0; q < nk; q++)
           {
            const int    l  = key[q];
            const double pf = 100.0 * SuffixCount(g_exFav, cell * (g_nL + 1), l) / c.n;
            const double pa = 100.0 * SuffixCount(g_exAdv, cell * (g_nL + 1), l) / c.n;
            const double pb = 100.0 * BaseExcMatched(rt, g_refH, l);
            sl += "+" + F0(g_lev[l]) + " pt: " + F0(pf) + "% (avverso " + F0(pa) + "%, base " + F0(pb) + "%); ";
            if(pf > pb * 1.1 && pf >= 1.0) above++;
            else if(pf < pb * 0.9 && pb >= 1.0) below++;
           }
         double l50 = 0.0, l25 = 0.0;
         for(int l = 0; l < g_nL; l++)
           {
            const double pf = 100.0 * SuffixCount(g_exFav, cell * (g_nL + 1), l) / c.n;
            if(pf >= 50.0) l50 = g_lev[l];
            if(pf >= 25.0) l25 = g_lev[l];
           }
         string v3;
         if(above * 2 > nk)      v3 = "La probabilita' supera quella di un'entrata casuale nelle stesse ore nella maggior parte dei livelli: il segnale raggiunge i punti piu' spesso del caso.";
         else if(below * 2 > nk) v3 = "La probabilita' e' inferiore a quella di un'entrata casuale nelle stesse ore: nessun vantaggio sulla base.";
         else v3 = "La probabilita' e' praticamente quella di un'entrata casuale nelle stesse ore e vicina a quella del movimento contrario: i punti si raggiungono perche' "
                   "il mercato si muove in quell'orario, non perche' c'e' il segnale.";
         AddConc(sIdx, "Punti raggiunti", "TF " + g_tfName[rt] + " (quello dell'elenco spunte se ha campione, altrimenti il piu' popolato), entro " + hs +
                 " min dal segnale: MFE medio " + F0(c.mfe) + " pt, MAE medio " + F0(c.mae) + " pt. Probabilita' di toccare il livello nella direzione del segnale: " + sl +
                 "Livello toccato da almeno meta' dei segnali: " + (l50 > 0.0 ? (F0(l50) + " pt") : ("meno di " + F0(g_lev[0]) + " pt")) +
                 "; da almeno un quarto: " + (l25 > 0.0 ? (F0(l25) + " pt") : ("meno di " + F0(g_lev[0]) + " pt")) + ". " + v3 +
                 " Le stesse probabilita' per ogni TF sono nella tabella dei livelli.");

         //--- giorni della settimana al livello della matrice
         const int lm = MatrixLevelIdx();
         int ord[7] = {1, 2, 3, 4, 5, 6, 0};
         string sd = "";
         double bestR = -1.0, worstR = 1.0e9, bestZ = 0.0, worstZ = 0.0;
         int bd = -1, wd = -1;
         for(int q = 0; q < 7; q++)
           {
            double nn, po, pb;
            DbAgg(rt, ord[q], ord[q], 0, g_nB - 1, lm, nn, po, pb);
            if(nn < InpMinPerBucket || pb <= 0.0 || pb >= 100.0) continue;
            sd += DowName(ord[q]) + " " + F0(po) + "% (base " + F0(pb) + "%, " + F0(nn) + " segnali); ";
            const double ratio = po / pb;
            const double z = (po - pb) / MathSqrt(pb * (100.0 - pb) / nn);
            if(ratio > bestR)  { bestR = ratio;  bd = ord[q]; bestZ = z; }
            if(ratio < worstR) { worstR = ratio; wd = ord[q]; worstZ = z; }
           }
         if(bd >= 0)
            AddConc(sIdx, "Giorni della settimana", "TF " + g_tfName[rt] + ", probabilita' di toccare +" + F0(g_lev[lm]) + " pt entro " + hs +
                    " min per giorno d'ingresso (server + offset): " + sd + "Giorno migliore rispetto alla base: " + DowName(bd) + " x" + F2(bestR) +
                    " (z naive " + F2(bestZ) + "); peggiore: " + DowName(wd) + " x" + F2(worstR) + " (z naive " + F2(worstZ) + "). "
                    "Il z non corregge la sovrapposizione dei segnali: una differenza con |z| sotto 3 non e' distinguibile dal caso. "
                    "Usala solo se compare con lo stesso segno nei TF vicini. Le tabelle per ogni TF sono nel dettaglio.");

         //--- orari che raggiungono piu' spesso i punti
         int top0[], top1[];
         const int n0 = BestBuckets(rt, lm, 0, 3, top0);
         const int n1 = BestBuckets(rt, lm, 1, 3, top1);
         if(n0 > 0)
           {
            string c0 = "", c1 = "";
            for(int q = 0; q < n0; q++) c0 += (q > 0 ? "; " : "") + BktInfo(rt, top0[q], lm);
            for(int q = 0; q < n1; q++)
              {
               double nn, po, pb;
               DbAgg(rt, 0, 6, top1[q], top1[q], lm, nn, po, pb);
               c1 += (q > 0 ? "; " : "") + BktLabel(top1[q]) + " x" + F2(pb > 0.0 ? po / pb : 0.0) + " (" + F0(po) + "% contro " + F0(pb) + "%, " + F0(nn) + " segnali)";
              }
            AddConc(sIdx, "Orari che raggiungono piu' spesso i punti", "TF " + g_tfName[rt] + ", +" + F0(g_lev[lm]) + " pt entro " + hs + " min, orario d'ingresso (server + offset). "
                    "Fasce con la probabilita' piu' alta: " + c0 + ". Fasce con il maggior vantaggio sulla base: " + (n1 > 0 ? c1 : "nessuna con campione sufficiente") + ". "
                    "Le fasce con la probabilita' assoluta piu' alta sono di norma le ore piu' volatili: la base le tocca altrettanto spesso, quindi non sono ore in cui il segnale funziona meglio. "
                    "Il vantaggio sulla base e' l'unico indizio, ma con " + IS(g_nB) + " fasce testate qualcuna supera la base per caso: serve coerenza fra TF vicini.");
           }

         //--- raffica e verso
         {
          string sb = "";
          for(int q = 0; q < 4; q++)
            {
             const int pq = (rt * BCAP + q) * ACCN;
             const double nq = g_accBur[pq];
             if(nq < 1.0) continue;
             sb += IS(q + 1) + (q == 3 ? "a+" : "a") + " posizione " + Sg(g_accBur[pq + 3] / nq) + " pt (" + F0(nq) + "); ";
            }
          if(sb != "")
             AddConc(sIdx, "Raffica", "TF " + g_tfName[rt] + ", netto medio per posizione nella raffica (1a = primo segnale dopo uno opposto): " + sb +
                     "Se il netto non cambia in modo sistematico con la posizione, il Sequence Filter non trova qui un fondamento; una differenza va comunque verificata fuori campione, cosa che questa tabella non fa.");
          string sdr = "";
          for(int k2 = 0; k2 < 2; k2++)
            {
             const int pq = (rt * 2 + k2) * ACCN;
             const double nq = g_accDir[pq];
             if(nq < 1.0) continue;
             sdr += string(k2 == 0 ? "BUY" : "SELL") + " " + Sg(g_accDir[pq + 3] / nq) + " pt su " + F0(nq) + " segnali (MFE " + F0(g_accDir[pq + 1] / nq) + ", MAE " + F0(g_accDir[pq + 2] / nq) + "); ";
            }
          if(sdr != "")
             AddConc(sIdx, "Direzione BUY e SELL", "TF " + g_tfName[rt] + ", netto medio per verso: " + sdr +
                     "Una differenza marcata riflette di norma la deriva del simbolo nel periodo (trend), non il segnale: confrontala con la base prima di dedurne un'asimmetria.");
         }

         //--- stato di volatilita'
         if(InpUseVolState)
           {
            double n0v, m0v, v0v, n1v, m1v, v1v, n2v, m2v, v2v, nrv, mrv, vrv, nfv, mfv, vfv;
            const bool h0 = CndStat(rt, 0, n0v, m0v, v0v);
            const bool h1 = CndStat(rt, 1, n1v, m1v, v1v);
            const bool h2 = CndStat(rt, 2, n2v, m2v, v2v);
            const bool hr = CndStat(rt, 8, nrv, mrv, vrv);
            const bool hf = CndStat(rt, 7, nfv, mfv, vfv);
            if(h0 || h1 || h2)
              {
               string sv = "TF " + g_tfName[rt] + ", netto medio per intensita' della candela del segnale: ";
               sv += "compressione (TR/ATR < " + F2(InpVsCompTh) + ") " + (h0 ? (Sg(m0v) + " pt (" + F0(n0v) + ")") : string("-")) +
                     ", normale " + (h1 ? (Sg(m1v) + " pt (" + F0(n1v) + ")") : string("-")) +
                     ", espansione (> " + F2(InpVsExpTh) + ") " + (h2 ? (Sg(m2v) + " pt (" + F0(n2v) + ")") : string("-")) + ". ";
               if(h0 && h2 && n0v >= 30.0 && n2v >= 30.0)
                 {
                  const double se = MathSqrt(v0v / n0v + v2v / n2v);
                  const double zw = (se > 0.0) ? (m2v - m0v) / se : 0.0;
                  sv += "Differenza espansione meno compressione " + Sg(m2v - m0v) + " pt (z naive " + F2(zw) + "). ";
                 }
               if(h2)
                 {
                  const double bs2 = CndBase(rt, 2);
                  if(bs2 > 0.0) sv += "MFE in espansione / base della stessa categoria: " + F2((g_accCnd[(rt * NCAT + 2) * ACCN + 1] / n2v) / bs2) + ". ";
                 }
               if(hr && hf) sv += "Volatilita' in aumento " + Sg(mrv) + " pt (" + F0(nrv) + ") contro in calo o ferma " + Sg(mfv) + " pt (" + F0(nfv) + "). ";
               sv += "Con segnali senza informazione ogni categoria ha netto circa meno il costo: una categoria migliore e' un'ipotesi da verificare fuori campione, non un filtro pronto.";
               AddConc(sIdx, "Stato di volatilita'", sv);
              }
           }

         //--- candele successive al segnale
         if(g_nM > 0)
           {
            string sn = "";
            for(int q = 0; q < g_nM; q++)
              {
               NxStat a, b;
               if(!NxGet(sIdx, rt, 0, q, a)) continue;
               const bool hb = NxBase(sIdx, rt, 0, q, b);
               sn += "dopo " + IS(g_nxM[q]) + " cand. (" + NxDuration(rt, g_nxM[q]) + "): favorevole " + F0(a.fav) + " (mediana " + F0(NxPct(sIdx, rt, 0, q, 0, a.n, 0.5)) +
                     ", p90 " + F0(NxPct(sIdx, rt, 0, q, 0, a.n, 0.9)) + "), avverso " + F0(a.adv) + ", range " + F0(a.rng) +
                     ((hb && b.rng > 0.0) ? (" (x" + F2(a.rng / b.rng) + " la base)") : "") + "; ";
              }
            NxStat ar, br;
            if(sn != "" && NxGet(sIdx, rt, 0, g_nxRef, ar))
              {
               const bool hbr = NxBase(sIdx, rt, 0, g_nxRef, br);
               string v4;
               const double rr = (hbr && br.rng > 0.0) ? ar.rng / br.rng : 0.0;
               if(!hbr)          v4 = "";
               else if(rr >= 1.1) v4 = "Il range dopo il segnale supera di oltre il 10% quello di una barra qualunque nelle stesse ore: il segnale arriva quando il mercato si sta gia' muovendo (la volatilita' si raggruppa). Puo' servire a dimensionare target e stop, non a scegliere il verso. ";
               else if(rr <= 0.9) v4 = "Il range dopo il segnale e' inferiore di oltre il 10% a quello di una barra qualunque nelle stesse ore. ";
               else               v4 = "Il range dopo il segnale e' in linea con quello di una barra qualunque nelle stesse ore: il segnale non anticipa ne' una volatilita' maggiore ne' minore. ";
               string v5;
               if(MathAbs(ar.tMv) < 2.0)
                  v5 = "La direzione di chiusura non e' distinguibile dal caso: l'informazione e' sull'ampiezza, non sul verso.";
               else
                  v5 = "La chiusura ha una tendenza nel verso " + string(ar.sMv > 0.0 ? "del segnale" : "opposto al segnale") + " (t naive gonfiato dalla sovrapposizione: verifica fuori campione).";
               AddConc(sIdx, "Candele successive", "TF " + g_tfName[rt] + " (ogni candela dura " + NxDuration(rt, 1) + "), punti dal prezzo d'ingresso: " + sn +
                       "Chiusura dopo " + IS(g_nxM[g_nxRef]) + " cand.: spostamento medio con segno nella direzione del segnale " + Sg(ar.sMv) + " pt (t naive " + F2(ar.tMv) +
                       "), valore assoluto medio " + F0(ar.absMv) + " pt. " + v4 + v5);

               //--- per intensita' della candela del segnale
               string si = "";
               for(int bb = 0; bb < 6; bb++)
                 {
                  NxStat ai, bi2;
                  if(!NxGet(sIdx, rt, 8 + bb, g_nxRef, ai) || ai.n < InpMinPerBucket) continue;
                  const bool hbi = NxBase(sIdx, rt, 8 + bb, g_nxRef, bi2);
                  si += NxIntPlain(bb) + ": range " + F0(ai.rng) + ((hbi && bi2.rng > 0.0) ? (" (x" + F2(ai.rng / bi2.rng) + " la base)") : "") +
                        ", favorevole " + F0(ai.fav) + ", avverso " + F0(ai.adv) + " su " + F0(ai.n) + " segnali; ";
                 }
               if(si != "")
                  AddConc(sIdx, "Candele successive per intensita'", "TF " + g_tfName[rt] + ", dopo " + IS(g_nxM[g_nxRef]) + " candela/e, per intensita' della candela del segnale (TR/ATR): " + si +
                          "L'intensita' conta perche' la volatilita' si raggruppa anche senza segnale: la base di ogni categoria ne tiene conto, il confronto utile e' il rapporto con la base.");

               //--- per orario
               double hr2[], hn2[];
               bool usedH[];
               ArrayResize(hr2, g_nB); ArrayResize(hn2, g_nB); ArrayResize(usedH, g_nB);
               for(int bb = 0; bb < g_nB; bb++)
                 {
                  hr2[bb] = -1.0; hn2[bb] = 0.0; usedH[bb] = false;
                  NxStat ah;
                  if(NxGet(sIdx, rt, NMEM1 + bb, g_nxRef, ah) && ah.n >= InpMinPerBucket) { hr2[bb] = ah.rng; hn2[bb] = ah.n; }
                 }
               string hiTxt = "", loTxt = "";
               for(int q = 0; q < 3; q++)
                 {
                  int bsel = -1;
                  double bv = -1.0;
                  for(int bb = 0; bb < g_nB; bb++) if(!usedH[bb] && hr2[bb] > bv) { bv = hr2[bb]; bsel = bb; }
                  if(bsel < 0) break;
                  usedH[bsel] = true;
                  hiTxt += (hiTxt == "" ? "" : "; ") + BktLabel(bsel) + " " + F0(bv) + " pt (" + F0(hn2[bsel]) + " segnali)";
                 }
               for(int bb = 0; bb < g_nB; bb++) usedH[bb] = false;
               for(int q = 0; q < 2; q++)
                 {
                  int bsel = -1;
                  double bv = 1.0e18;
                  for(int bb = 0; bb < g_nB; bb++) if(!usedH[bb] && hr2[bb] >= 0.0 && hr2[bb] < bv) { bv = hr2[bb]; bsel = bb; }
                  if(bsel < 0) break;
                  usedH[bsel] = true;
                  loTxt += (loTxt == "" ? "" : "; ") + BktLabel(bsel) + " " + F0(bv) + " pt (" + F0(hn2[bsel]) + " segnali)";
                 }
               if(hiTxt != "")
                  AddConc(sIdx, "Candele successive per orario", "TF " + g_tfName[rt] + ", range medio dopo " + IS(g_nxM[g_nxRef]) + " candela/e, per orario d'ingresso (server + offset). "
                          "Fasce con il range piu' alto: " + hiTxt + ". Fasce piu' quiete: " + (loTxt != "" ? loTxt : "-") + ". "
                          "Il range segue la volatilita' oraria del mercato, con o senza segnale: la tabella per orario e TF mostra anche il confronto con la base di ogni fascia.");
              }
           }
        }
     }

   //--- tabella A (scelta in-sample, verifica fuori campione)
   if(!g_cAok)
      AddConc(sIdx, "Tabella A (scelta in-sample)", "Non calcolabile: nessuna combinazione con almeno " + IS(minN) + " posizioni in-sample.");
   else
      AddConc(sIdx, "Tabella A (scelta in-sample)", "Valutate " + IS(g_cAm) + " combinazioni TF x fascia x tenuta x target x verso sul primo periodo. Miglior t in-sample " + F2(g_cAbestT) +
              " contro un massimo atteso per puro caso di circa " + F2(g_cAchance) + ". Fra le prime " + IS(g_cApn) + " in-sample, " + IS(g_cApos) + " su " + IS(g_cAusable) +
              " restano positive fuori campione e " + IS(g_cAstrong) + " con t OOS >= 2. " +
              (g_cAns > 0 ? ("Combinazioni che reggono (OOS positivo e t >= 2): " + IS(g_cAns) + "; la prima: " + g_cAsurv +
                             ". Sono candidate da confermare su dati mai visti, non risultati: l'OOS e' stato usato per sceglierle.")
                          : "Nessuna combinazione regge fuori campione: la classifica in-sample e' rumore di selezione, nessuna riga va operata."));

   //--- tabella B (con rumore)
   if(!g_cBok)
      AddConc(sIdx, "Tabella B (con rumore)", "Non calcolabile: nessuna combinazione con almeno " + IS(minN) + " posizioni.");
   else
     {
      const double chB = (g_cBm > 1) ? MathSqrt(2.0 * MathLog((double)g_cBm)) : 0.0;
      AddConc(sIdx, "Tabella B (con rumore)", "Ordinata per " + NoiseSortName() + " sull'intero storico, senza protezione. La prima riga (" + g_cBdesc + ") promette " + F0(g_cBtotal) +
              " pt su " + F0(g_cBn) + " posizioni (netto medio " + F1(g_cBmean) + ", t " + F2(g_cBt) + "); il t massimo atteso per puro caso su " + IS(g_cBm) + " tentativi e' circa " + F2(chB) + ". " +
              "Nelle prime righe la parte piu' recente del periodo contiene il " + F1(g_cBshareN) + "% delle posizioni e il " + F1(g_cBshareLate) + "% del profitto. "
              "Fra le prime " + IS(g_cBpn) + " con campione sufficiente, " + IS(g_cBboth) + " su " + IS(g_cBusable) + " sono positive in entrambe le parti del periodo e " + IS(g_cBincoh) +
              " cambiano segno. La distanza fra il profitto promesso qui e quello della tabella A e' la misura del rumore di selezione.");
     }

   //--- conclusione
   {
    string c;
    const bool oosEdge = (g_cAok && g_cAns > 0);
    if(K < 1)
       c = "Campione insufficiente: nessuna conclusione.";
    else if(netSig == 0 && !oosEdge)
      {
       c = "Nessuna evidenza di vantaggio operabile al netto dei costi in questa serie. ";
       if(posS > 0)
          c += "Il segnale ha contenuto direzionale lordo in " + IS(posS) + " TF, ma i costi lo assorbono. ";
       else
          c += "Il segnale non anticipa la direzione del prezzo oltre il caso. ";
       c += "I punti toccati dopo il segnale descrivono la volatilita' del momento, non un vantaggio direzionale. "
            "Uso ragionevole: indicazione di ampiezza (quanto puo' muoversi la candela successiva, vedi 'Candele successive'), non trigger di direzione. "
            "Prima di qualunque uso operativo: ripeti lo studio su altri simboli e su un periodo successivo.";
      }
    else
      {
       c = "Ci sono indizi da verificare: ";
       if(netSig > 0) c += "netto positivo e significativo in " + sigList + "; ";
       if(oosEdge)    c += IS(g_cAns) + " combinazioni della tabella A reggono fuori campione; ";
       c += "non sono conferme. Servono un test su dati mai visti (forward) e su altri simboli, e la verifica che l'esecuzione reale (spread, slippage, commissioni) non cancelli il margine.";
      }
    AddConc(sIdx, "Conclusione", c);
   }
  }

//--- confronto fra le due serie (Delta contro EXP_ADDED)
void BuildCrossConclusions()
  {
   if(g_nSets < 2) return;
   const string a0 = g_setTag[0], a1 = g_setTag[1];
   long ev0 = 0, ev1 = 0;
   for(int t = 0; t < g_nT; t++) { ev0 += (long)g_cmpEv[t]; ev1 += (long)g_cmpEv[g_nT + t]; }
   AddConc(-1, "Quanti segnali in piu'", a1 + ": " + IS(ev1) + " segnali contro " + IS(ev0) + " del " + a0 +
           (ev0 > 0 ? (" (" + F1(100.0 * (double)ev1 / (double)ev0) + "% rispetto al Delta)") : "") +
           ". Le due serie sono disgiunte: l'Expansion aggiunge segnali solo dove il Delta tace.");

   int both = 0, better = 0;
   double bestDiff = -1.0e18;
   int bdT = -1;
   for(int t = 0; t < g_nT; t++)
     {
      if(g_cmpN[t] < g_minN || g_cmpN[g_nT + t] < g_minN) continue;
      both++;
      const double diff = g_cmpRet[g_nT + t] - g_cmpRet[t];
      if(diff > 0.0) better++;
      if(diff > bestDiff) { bestDiff = diff; bdT = t; }
     }
   const double net0 = (g_agN[0] > 0.0) ? g_agNet[0] / g_agN[0] : 0.0;
   const double net1 = (g_agN[1] > 0.0) ? g_agNet[1] / g_agN[1] : 0.0;
   const double gr0  = (g_agN[0] > 0.0) ? g_agGross[0] / g_agN[0] : 0.0;
   const double gr1  = (g_agN[1] > 0.0) ? g_agGross[1] / g_agN[1] : 0.0;
   AddConc(-1, "Netto a confronto", "All'orizzonte di " + IS(g_hor[g_refH]) + " min, netto medio pesato sui segnali dei TF con campione sufficiente: " + a0 + " " + Sg(net0) + " pt, " + a1 + " " + Sg(net1) +
           " pt; lordo medio pesato: " + a0 + " " + Sg(gr0) + " pt, " + a1 + " " + Sg(gr1) + " pt. " +
           (both > 0 ? ("Su " + IS(both) + " TF con campione sufficiente in entrambe le serie, " + a1 + " ha netto migliore in " + IS(better) + "; la differenza maggiore e' su " +
                        g_tfName[bdT] + " (" + Sg(bestDiff) + " pt). ") : "Nessun TF ha campione sufficiente in entrambe le serie. ") +
           "TF con netto positivo significativo: " + a0 + " " + IS(g_agNsig[0]) + ", " + a1 + " " + IS(g_agNsig[1]) + ". TF con lordo significativo positivo: " +
           a0 + " " + IS(g_agGpos[0]) + ", " + a1 + " " + IS(g_agGpos[1]) + ", negativo: " + a0 + " " + IS(g_agGneg[0]) + ", " + a1 + " " + IS(g_agGneg[1]) + ".");
   AddConc(-1, "Tabelle A a confronto", "Combinazioni della tabella A che reggono fuori campione (OOS positivo e t >= 2): " + a0 + " " + IS(g_agAns[0]) + ", " + a1 + " " + IS(g_agAns[1]) +
           ". TF in cui la miglior combinazione A1 resta positiva fuori campione con t >= 2: " + a0 + " " + IS(g_agA1ok[0]) + ", " + a1 + " " + IS(g_agA1ok[1]) + ".");
   string c;
   if(g_agNsig[1] == 0 && g_agAns[1] == 0 && g_agA1ok[1] == 0)
      c = "I segnali che l'Expansion aggiunge non mostrano un vantaggio netto dimostrabile: allargano il numero di operazioni (e dei costi) senza una prova che valgano il costo. ";
   else
      c = "I segnali aggiunti mostrano qualche indizio di vantaggio: va confermato fuori campione prima di aggiungerli alla strategia. ";
   if(g_agN[0] > 0.0 && g_agN[1] > 0.0)
      c += (net1 > net0) ? ("Il netto medio pesato degli aggiunti e' migliore di quello del Delta di " + F1(net1 - net0) + " pt, ma conta la significativita', non la differenza puntuale.")
                         : ("Il netto medio pesato degli aggiunti non e' migliore di quello del Delta (differenza " + Sg(net1 - net0) + " pt).");
   AddConc(-1, "Conclusione del confronto", c);
  }

string SummaryPlain()
  {
   string out = "SignalLab MultiTF - riepilogo e conclusioni - " + _Symbol + " - " + ModeName() + "\n";
   for(int k = 0; k < ArraySize(g_cSet); k++)
      out += "\n[" + string(g_cSet[k] < 0 ? "CONFRONTO" : g_setTag[g_cSet[k]]) + "] " + g_cTopic[k] + ": " + g_cText[k] + "\n";
   return out;
  }

void RepSummary()
  {
   const int nc = ArraySize(g_cSet);
   if(nc < 1) return;
   W("<div class='sec' style='order:1'>");
   W("<h1 class='setH'>Riepilogo e conclusioni</h1>");
   W("<div class='note'>Riassunto scritto generato dai numeri di questa corsa con regole fisse: riporta quello che le tabelle dicono, con le cautele statistiche del caso, "
     "e non sostituisce la lettura delle tabelle. Il testo qui sotto si pu&ograve; copiare con il pulsante (stesso testo in <b>MQL5/Files/SignalLab_MultiTF_riepilogo_" + g_reportTag + ".txt</b>). "
     "I numeri di dettaglio sono nelle serie pi&ugrave; in basso.</div>");
   W("<table class='sum'><tr><th>Serie</th><th>Tema</th><th>Cosa dicono i dati</th></tr>");
   for(int k = 0; k < nc; k++)
      W("<tr><td>" + HtmlEsc(g_cSet[k] < 0 ? string("CONFRONTO") : g_setTag[g_cSet[k]]) + "</td><td>" + HtmlEsc(g_cTopic[k]) + "</td><td>" + HtmlEsc(g_cText[k]) + "</td></tr>");
   W("</table>");
   W("<h2>Testo da copiare</h2>");
   W("<button onclick=\"var t=document.getElementById('sumTxt');t.select();document.execCommand('copy');\">Copia il riepilogo</button>");
   W("<textarea id='sumTxt' readonly style='width:100%;height:320px;margin-top:8px;background:#0f1114;color:#d8dee9;border:1px solid #2e3440;border-radius:6px;padding:10px;font:12px/1.5 ui-monospace,Consolas,monospace'>" +
     HtmlEsc(SummaryPlain()) + "</textarea>");
   W("</div>");
  }

//--- digest compatto da incollare in chat
string BuildDigestHeader()
  {
   string d = "### SIGNALLAB MULTITF DIGEST v1\n";
   d += "# tutto in punti; netto = rendimento a fine orizzonte nella direzione del segnale meno costo\n";
   d += "# tcl = t con errore standard raggruppato per giorno; base = MFE di entrate casuali, stessa fascia oraria\n";
   d += "CFG|" + _Symbol + "|digits|" + IS(_Digits) + "|point|" + DoubleToString(g_pt, 8) + "|mode|" + ModeName() +
        "|ema|" + IS(InpEmaPeriod) + "|vol|" + IS(InpVolAvgPeriod) + "|thr|" + F2(InpThreshold) +
        "|expthr|" + F2(InpExpThreshold) + "|expatr|" + IS(InpExpAtrPeriod) + "|expoff|" + IS(InpExpConfirmOffset) +
        "|rungap|" + IS(InpRunGapBars) + "\n";
   datetime tSp = (datetime)((g_day0 + (long)g_splitDay) * 86400L);
   d += "# tabelle RANK/SURV/BESTTF: scelte sul primo periodo, verificate sul resto. NOISE/BESTNOISE: scelte sull'intero storico, part1/part2 NON indipendenti.\n";
   d += "CTX|offset|" + IS(InpTimeOffsetH) + "|from|" + TimeToString(g_tStart, TIME_DATE) + "|histwarn|" + IS(g_histWarn ? 1 : 0) +
        "|split|" + IS(MathMin(95, MathMax(5, InpSplitPct))) + "|splitdate|" + TimeToString(tSp, TIME_DATE) + "|minn|" + IS((long)g_minN) +
        "|noisesort|" + NoiseSortName() + "\n";
   if(!InpUseVolState) d += "VOLCFG|on|0\n";
   else d += "VOLCFG|on|1|atr|" + IS(g_vpar.atrLen) + "|lookback|" + IS(g_vpar.lookback) + "|ema|" + IS(g_vpar.emaSmooth) +
        "|exp|" + F2(InpVsExpTh) + "|comp|" + F2(InpVsCompTh) + "|low|" + IS(InpVsLowTh) + "|high|" + IS(InpVsHighTh) + "|extreme|" + IS(InpVsExtremeTh) + "\n";
   d += "RUN|costfix|" + F1(InpCostPoints) + "|extra|" + F1(InpExtraCostPts) + "|maxgap|" + IS(InpMaxGapMin) +
        "|entrygap|" + IS(InpMaxEntryGapMin) + "|bucket|" + IS(g_bMin) + "|parent|" + ParentName() +
        "|ref|" + IS(g_hor[g_refH]) + "|sets|" + IS(g_nSets) + "\n";
   d += "DATA|m1bars|" + IS(g_n1) + "|days|" + IS(g_nDays) + "|medrange|" + F0(g_medRange) + "|medspr|" + F0(g_medSpr) +
        "|zerospr|" + F1(g_zeroSprPct) + "\n";
   return d;
  }

//--- righe della singola serie (le righe RANK, NOISE, VST, TOP... le aggiungono le funzioni Rep*)
string BuildDigestSet()
  {
   string d = "SETINFO|name|" + g_setTag[g_curSet] + "|zbonf|" + F2(g_zB) + "\n";
   for(int t = 0; t < g_nT; t++)
      d += "TF|" + g_tfName[t] + "|bars|" + IS(g_tfBars[t]) + "|base|" + IS(g_tfCnt[t]) + "|signals|" + IS(g_tfEv[t]) +
           "|rejgap|" + IS(g_tfRejGap[t]) + "|rejm1|" + IS(g_tfRejM1[t]) + "\n";
   for(int t = 0; t < g_nT; t++)
      for(int h = 0; h < g_nH; h++)
        {
         CellStat s;
         if(!GetCell(t, h, s)) continue;
         d += "TFH|" + g_tfName[t] + "|" + IS(g_hor[h]) + "|n|" + F0(s.n) + "|mfe|" + F0(s.mfe) + "|mae|" + F0(s.mae) +
              "|base|" + F0(s.baseMfe) + "|ret|" + F1(s.ret) + "|tn|" + F2(s.tNaive) + "|tcl|" + F2(s.tCl) +
              "|cost|" + F1(s.cost) + "|win|" + F0(s.win) + "|lose|" + F0(s.lose) + "|zs|" + F2(s.zSign) + "\n";
        }
   for(int t = 0; t < g_nT; t++)
     {
      CellStat s;
      if(!GetCell(t, g_refH, s)) continue;
      const int cell = t * g_nH + g_refH;
      d += "LEV|" + g_tfName[t] + "|" + IS(g_hor[g_refH]);
      for(int l = 0; l < g_nL; l++)
         d += "|" + F0(g_lev[l]) + "|" + F1(100.0 * SuffixCount(g_exFav, cell * (g_nL + 1), l) / s.n) +
              "/" + F1(100.0 * SuffixCount(g_exAdv, cell * (g_nL + 1), l) / s.n) +
              "/" + F1(100.0 * BaseExcMatched(t, g_refH, l));
      d += "\n";
     }
   for(int t = 0; t < g_nT; t++)
     {
      for(int c = 0; c < BCAP; c++)
        {
         int p = (t * BCAP + c) * ACCN; double n = g_accBur[p];
         if(n < 1.0) continue;
         d += "BURST|" + g_tfName[t] + "|" + IS(c + 1) + "|n|" + F0(n) + "|mfe|" + F0(g_accBur[p+1]/n) +
              "|mae|" + F0(g_accBur[p+2]/n) + "|ret|" + F1(g_accBur[p+3]/n) + "\n";
        }
      for(int k = 0; k < 2; k++)
        {
         int p = (t * 2 + k) * ACCN; double n = g_accDir[p];
         if(n < 1.0) continue;
         d += "DIR|" + g_tfName[t] + "|" + (k == 0 ? "BUY" : "SELL") + "|n|" + F0(n) + "|mfe|" + F0(g_accDir[p+1]/n) +
              "|mae|" + F0(g_accDir[p+2]/n) + "|ret|" + F1(g_accDir[p+3]/n) + "\n";
        }
      for(int k = 0; k < 7; k++)
        {
         int p = (t * 7 + k) * ACCN; double n = g_accDow[p];
         if(n < 1.0) continue;
         d += "DOW|" + g_tfName[t] + "|" + DowName(k) + "|n|" + F0(n) + "|ret|" + F1(g_accDow[p+3]/n) + "\n";
        }
     }
   return d;
  }

//+------------------------------------------------------------------+
//| REPORT A SERIE: ogni serie ha il suo gruppo completo di tabelle,   |
//| piu' una tabella di confronto mostrata in cima (CSS order).        |
//+------------------------------------------------------------------+
string g_reportTag = "";
string g_reportFile = "";
string g_reportTmp = "";

void ReportBegin()
  {
   g_reportTag  = SafeTag(_Symbol) + "_" + ModeName();
   g_reportFile = "SignalLab_MultiTF_" + g_reportTag + ".html";
   g_reportTmp  = g_reportFile + ".tmp";      // il report precedente resta intatto finche' la corsa non e' completa
   g_fh = FileOpen(g_reportTmp, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(g_fh == INVALID_HANDLE) Print("HTML non scrivibile (errore ", GetLastError(), "): salvo solo il digest.");
   g_dgSets = "";
   RepHead();
   W("<div class='wrap'>");
   W("<div class='sec' style='order:0'>");
   RepIntro();
   W("</div>");
  }

//--- sintesi della serie corrente (orizzonte di riferimento) per il confronto
void CaptureSummary(const int sIdx)
  {
   for(int t = 0; t < g_nT; t++)
     {
      const int ci = sIdx * g_nT + t;
      g_cmpEv[ci] = g_tfEv[t];
      CellStat cs;
      if(GetCell(t, g_refH, cs))
        { g_cmpN[ci] = cs.n; g_cmpMfe[ci] = cs.mfe; g_cmpMae[ci] = cs.mae; g_cmpRet[ci] = cs.ret; g_cmpTcl[ci] = cs.tCl; }
      else
        { g_cmpN[ci] = 0.0; g_cmpMfe[ci] = 0.0; g_cmpMae[ci] = 0.0; g_cmpRet[ci] = 0.0; g_cmpTcl[ci] = 0.0; }
     }
  }

void ReportSet(const int sIdx)
  {
   g_curSet = sIdx;
   //--- soglia di Bonferroni sul numero di celle con dati di questa serie
   int m = 0;
   for(int t = 0; t < g_nT; t++)
      for(int h = 0; h < g_nH; h++)
         if(g_accTH[(t * g_nH + h) * ACCN] >= 1.0) m++;
   g_zB = ZCrit(MathMax(1, m));

   g_dg = "";
   g_cAok = false; g_cBok = false; g_cAns = 0; g_cAsurv = ""; g_cBdesc = "";
   W("<div class='sec' style='order:" + IS(3 + sIdx) + "'>");
   W("<h1 class='setH'>Serie " + IS(sIdx + 1) + " di " + IS(g_nSets) + " &mdash; " + g_setName[sIdx] + "</h1>");
   W("<div class='note'>" + g_setNote[sIdx] + " Soglia di Bonferroni su " + IS(m) + " celle TF x orizzonte: |t| &ge; <b>" + F2(g_zB) + "</b>.</div>");
   RepCoverage();
   RepVerdict();
   RepMatrices();
   RepExceed();
   RepEvents();
   RepNext();
   RepNoiseIntro();
   RepBestTF();
   RepRank();
   RepBestTFNoise();
   RepRankNoise();
   RepVolState();
   RepStruct();
   RepDowHoursMain();
   RepDetails();
   RepTop();
   W("</div>");
   CaptureSummary(sIdx);
   BuildConclusions(sIdx);
   g_dgSets += "### SET|" + g_setTag[sIdx] + "\n" + BuildDigestSet() + g_dg;
  }

//--- tabella di confronto Delta / EXP_ADDED (mostrata per prima)
void RepCompare()
  {
   if(g_nSets < 2) return;
   W("<div class='sec' style='order:2'>");
   W("<h1 class='setH'>Confronto fra le due serie &mdash; orizzonte " + IS(g_hor[g_refH]) + " min</h1>");
   W("<div class='note'><b>" + g_setTag[0] + "</b> = solo Synthetic Delta. <b>" + g_setTag[1] + "</b> = segnali che l'Expansion aggiunge dove il Delta non d&agrave; segnale. "
     "Le serie sono disgiunte e misurate con lo stesso metodo (stessi costi, stesse tenute, stessa base): ciascuna ha sotto il proprio gruppo completo di tabelle. "
     "La colonna <b>Aggiunti / Delta</b> dice di quanto l'Expansion allarga il numero di segnali. Il netto medio &egrave; per posizione, in punti, al netto del costo; "
     "t cluster = errore standard raggruppato per giorno, giallo se |t| &ge; 2 (la soglia di Bonferroni &egrave; nelle singole serie).</div>");
   W("<table><tr><th rowspan='2'>TF</th><th colspan='5'>" + g_setTag[0] + "</th><th colspan='5'>" + g_setTag[1] + "</th><th rowspan='2'>Aggiunti / Delta %</th></tr>");
   W("<tr><th>Segnali</th><th>Misurati</th><th>Netto medio</th><th>t cluster</th><th>MFE/MAE</th>"
     "<th>Segnali</th><th>Misurati</th><th>Netto medio</th><th>t cluster</th><th>MFE/MAE</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      if(g_cmpEv[t] < 1 && g_cmpEv[g_nT + t] < 1) continue;
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int s2 = 0; s2 < 2; s2++)
        {
         const int ci = s2 * g_nT + t;
         if(g_cmpN[ci] < 1.0) { W("<td>" + IS(g_cmpEv[ci]) + "</td><td>-</td><td>-</td><td>-</td><td>-</td>"); continue; }
         double ra = (g_cmpMae[ci] > 0.0) ? g_cmpMfe[ci] / g_cmpMae[ci] : 0.0;
         W(Td(IS(g_cmpEv[ci])) + Td(F0(g_cmpN[ci])) + Td("<b>" + F1(g_cmpRet[ci]) + "</b>", ColSign(g_cmpRet[ci])) +
           Td(F2(g_cmpTcl[ci]), ColTNaive(g_cmpTcl[ci])) + Td(F2(ra), ra > 1.0 ? "#a3be8c" : "#bf616a"));
        }
      double add = (g_cmpEv[t] > 0) ? 100.0 * g_cmpEv[g_nT + t] / g_cmpEv[t] : 0.0;
      W(Td(g_cmpEv[t] > 0 ? F1(add) : "-") + "</tr>");
     }
   W("</table>");

   W("<h2>Miglior combinazione per TF (tabella A1 di ciascuna serie): scelta in-sample, risultato fuori campione</h2>");
   W("<div class='note'>Per ogni serie e TF: la combinazione verso/tenuta/target scelta sul primo periodo e il suo risultato nel periodo successivo, mai usato per sceglierla. "
     "Il netto OOS &egrave; la sola colonna che conta; un netto OOS positivo con t &ge; 2 su una sola riga non basta, serve coerenza fra TF vicini.</div>");
   W("<table><tr><th rowspan='2'>TF</th><th colspan='4'>" + g_setTag[0] + "</th><th colspan='4'>" + g_setTag[1] + "</th></tr>");
   W("<tr><th>Combinazione</th><th>OOS pos.</th><th>OOS netto</th><th>OOS t</th><th>Combinazione</th><th>OOS pos.</th><th>OOS netto</th><th>OOS t</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      if(g_cmpEv[t] < 1 && g_cmpEv[g_nT + t] < 1) continue;
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int s2 = 0; s2 < 2; s2++)
        {
         const int ci = s2 * g_nT + t;
         if(g_cmpBoN[ci] < 1.0) { W("<td>" + g_cmpDesc[ci] + "</td><td>-</td><td>-</td><td>-</td>"); continue; }
         W(Td(g_cmpDesc[ci]) + Td(F0(g_cmpBoN[ci])) + Td("<b>" + F1(g_cmpBoM[ci]) + "</b>", ColSign(g_cmpBoM[ci])) +
           Td(F2(g_cmpBoT[ci]), ColTNaive(g_cmpBoT[ci])));
        }
      W("</tr>");
     }
   W("</table>");
   W("</div>");
   //--- righe per il digest (sezione separata: non appartengono all'ultima serie)
   g_dgSets += "### CMP\n";
   for(int s2 = 0; s2 < 2; s2++)
      for(int t = 0; t < g_nT; t++)
        {
         const int ci = s2 * g_nT + t;
         if(g_cmpEv[ci] < 1) continue;
         g_dgSets += "CMP|" + g_setTag[s2] + "|" + g_tfName[t] + "|signals|" + IS(g_cmpEv[ci]) + "|n|" + F0(g_cmpN[ci]) +
                     "|ret|" + F1(g_cmpRet[ci]) + "|tcl|" + F2(g_cmpTcl[ci]) + "|mfe|" + F0(g_cmpMfe[ci]) + "|mae|" + F0(g_cmpMae[ci]) +
                     "|best|" + g_cmpDesc[ci] + "|oosn|" + F0(g_cmpBoN[ci]) + "|oosmean|" + F1(g_cmpBoM[ci]) + "|oost|" + F2(g_cmpBoT[ci]) + "\n";
        }
  }

//--- corsa interrotta: chiude e scarta il file temporaneo, il report precedente non viene toccato
void ReportAbort()
  {
   if(g_fh != INVALID_HANDLE)
     {
      FileClose(g_fh);
      g_fh = INVALID_HANDLE;
      FileDelete(g_reportTmp);
     }
  }

void ReportEnd()
  {
   BuildCrossConclusions();
   RepCompare();
   RepSummary();
   if(ArraySize(g_cSet) > 0)
     {
      g_dgSets += "### CONCL\n";
      for(int k = 0; k < ArraySize(g_cSet); k++)
         g_dgSets += "CONCL|" + string(g_cSet[k] < 0 ? "CONFRONTO" : g_setTag[g_cSet[k]]) + "|" + g_cTopic[k] + "|" + g_cText[k] + "\n";
     }
   g_dg = BuildDigestHeader() + g_dgSets;
   string esc = g_dg;
   StringReplace(esc, "&", "&amp;");
   StringReplace(esc, "<", "&lt;");
   W("<div class='sec' style='order:9'>");
   W("<h2>Digest da copiare</h2>");
   W("<div class='note'>Seleziona e incolla in chat. Stesso testo in <b>MQL5/Files/SignalLab_MultiTF_digest_" + g_reportTag + ".txt</b>.</div>");
   W("<pre>" + esc + "### END\n</pre>");
   W("</div></div></body></html>");
   if(g_fh != INVALID_HANDLE)
     {
      FileClose(g_fh);
      g_fh = INVALID_HANDLE;
      if(FileIsExist(g_reportFile)) FileDelete(g_reportFile);
      if(FileMove(g_reportTmp, 0, g_reportFile, FILE_REWRITE))
         Print("Report: MQL5/Files/", g_reportFile);
      else
         Print("Report completo ma non rinominabile (errore ", GetLastError(), "): si trova in MQL5/Files/", g_reportTmp);
     }
   int sf = FileOpen("SignalLab_MultiTF_riepilogo_" + g_reportTag + ".txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(sf != INVALID_HANDLE)
     {
      FileWriteString(sf, SummaryPlain());
      FileClose(sf);
      Print("Riepilogo: MQL5/Files/SignalLab_MultiTF_riepilogo_", g_reportTag, ".txt");
     }
   int df = FileOpen("SignalLab_MultiTF_digest_" + g_reportTag + ".txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(df != INVALID_HANDLE)
     {
      FileWriteString(df, g_dg + "### END\n");
      FileClose(df);
      Print("Digest: MQL5/Files/SignalLab_MultiTF_digest_", g_reportTag, ".txt");
     }
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   uint t0 = GetTickCount();
   g_pt  = _Point;
   g_off = (long)InpTimeOffsetH * 3600L;
   if(!SetupInputs()) return;
   if(!LoadM1()) return;

   //--- primo giorno out-of-sample: la classifica si costruisce solo sul periodo precedente
   {
    int dFrom = (int)((((long)g_tStart + g_off) / 86400L) - g_day0);
    if(dFrom < 0) dFrom = 0;
    int pct = MathMin(95, MathMax(5, InpSplitPct));
    g_splitDay = dFrom + (int)((double)(g_nDays - dFrom) * pct / 100.0);
    Print("Split IS/OOS: giorni ", dFrom, "-", g_nDays - 1, " | OOS dal giorno ", g_splitDay, " (", pct, "% in-sample)");
   }

   ArrayResize(g_tfOff, g_nT);    ArrayInitialize(g_tfOff, 0);
   ArrayResize(g_tfCnt, g_nT);    ArrayInitialize(g_tfCnt, 0);
   ArrayResize(g_tfBars, g_nT);   ArrayInitialize(g_tfBars, 0);
   ArrayResize(g_tfEv, g_nT);     ArrayInitialize(g_tfEv, 0);
   ArrayResize(g_tfEvAlt, g_nT);  ArrayInitialize(g_tfEvAlt, 0);
   {
    const int nc = 2 * g_nT;
    ArrayResize(g_cmpEv, nc);  ArrayInitialize(g_cmpEv, 0);
    ArrayResize(g_cmpN, nc);   ArrayInitialize(g_cmpN, 0.0);
    ArrayResize(g_cmpMfe, nc); ArrayInitialize(g_cmpMfe, 0.0);
    ArrayResize(g_cmpMae, nc); ArrayInitialize(g_cmpMae, 0.0);
    ArrayResize(g_cmpRet, nc); ArrayInitialize(g_cmpRet, 0.0);
    ArrayResize(g_cmpTcl, nc); ArrayInitialize(g_cmpTcl, 0.0);
    ArrayResize(g_cmpBoN, nc); ArrayInitialize(g_cmpBoN, 0.0);
    ArrayResize(g_cmpBoM, nc); ArrayInitialize(g_cmpBoM, 0.0);
    ArrayResize(g_cmpBoT, nc); ArrayInitialize(g_cmpBoT, 0.0);
    ArrayResize(g_cmpDesc, nc);
    for(int q = 0; q < nc; q++) g_cmpDesc[q] = "-";
   }
   ArrayResize(g_tfRejGap, g_nT); ArrayInitialize(g_tfRejGap, 0);
   ArrayResize(g_tfRejM1, g_nT);  ArrayInitialize(g_tfRejM1, 0);
   {
    //--- candele successive: accumulatori di entrambe le serie (riempiti durante il calcolo dei segnali)
    const long cells = (long)g_nSets * g_nT * g_nMem * g_nM;
    if(ArrayResize(g_nx, (int)(cells * NXF)) != (int)(cells * NXF) ||
       ArrayResize(g_nxh, (int)(cells * 2 * NXB)) != (int)(cells * 2 * NXB) ||
       ArrayResize(g_nxb, (int)((long)g_nT * g_nMem * g_nM * NXF)) != (int)((long)g_nT * g_nMem * g_nM * NXF))
      {
       Print("Memoria insufficiente per le candele successive: riduci InpNextCandles, i TF o allarga le fasce.");
       return;
      }
    ArrayInitialize(g_nx, 0.0);
    ArrayInitialize(g_nxh, 0);
    ArrayInitialize(g_nxb, 0.0);
   }

   Print("=== SignalLab MultiTF | ", _Symbol, " | modo ", ModeName(), " | ", g_nT, " TF | ", g_nH,
         " orizzonti | riferimento ", g_hor[g_refH], " min");

   //--- segnali su ogni TF (M1 per primo se richiesto: riusa l'array gia' in memoria)
   int idxM1 = -1;
   for(int t = 0; t < g_nT; t++) if(g_tf[t] == PERIOD_M1) idxM1 = t;
   if(idxM1 >= 0) ProcessTF(idxM1, g_r1, ArraySize(g_r1));
   ArrayFree(g_r1);
   for(int t = 0; t < g_nT; t++)
     {
      if(IsStopped()) { Print("Interrotto dall'utente."); Comment(""); return; }
      if(t == idxM1) continue;
      MqlRates r[];
      int n = LoadTF(t, r);
      if(n < 60) { Print("TF ", g_tfName[t], ": storico non disponibile (", n, ")"); continue; }
      ProcessTF(t, r, n);
      ArrayFree(r);
     }
   Comment("SignalLab MultiTF: segnali pronti, misura in corso...");
   if(g_used == 0) { Print("Nessuna barra valida: controlla periodo e storico."); Comment(""); return; }

   //--- finestre forward e accumulo, un orizzonte alla volta, per ciascuna serie
   ArrayResize(g_fHi, g_n1); ArrayResize(g_fLo, g_n1); ArrayResize(g_fCl, g_n1);
   ArrayResize(g_ok, g_n1);  ArrayResize(g_dqH, g_n1); ArrayResize(g_dqL, g_n1);
   ReportBegin();
   for(int sIdx = 0; sIdx < g_nSets; sIdx++)
     {
      if(sIdx == 1)
        {
         ArrayCopy(g_dir, g_dirAlt);       // la seconda serie diventa quella attiva
         ArrayCopy(g_bur, g_burAlt);
         ArrayCopy(g_tfEv, g_tfEvAlt);
        }
      g_curSet = sIdx;
      Print("--- Serie ", sIdx + 1, "/", g_nSets, ": ", g_setTag[sIdx]);
      if(!AllocAcc()) { Comment(""); ReportAbort(); return; }
      for(int hi = 0; hi < g_nH; hi++)
        {
         if(IsStopped()) { Print("Interrotto dall'utente."); Comment(""); ReportAbort(); return; }
         ComputeForward(g_hor[hi]);
         AccumulateHorizon(hi);
         Print(g_setTag[sIdx], ": orizzonte ", g_hor[hi], " min completato (", (GetTickCount() - t0) / 1000.0, " s)");
         Comment("SignalLab MultiTF [", g_setTag[sIdx], "]: orizzonte ", g_hor[hi], " min completato (", hi + 1, "/", g_nH, ")");
        }
      ComputeEventReach();
      ReportSet(sIdx);
     }
   ReportEnd();
   Comment("");
   Print("Fatto in ", (GetTickCount() - t0) / 1000.0, " s");
  }
//+------------------------------------------------------------------+
