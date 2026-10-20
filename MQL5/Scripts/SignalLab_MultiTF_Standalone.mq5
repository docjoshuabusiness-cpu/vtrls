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
//|   7. GESTIONE SIMULATA: su ogni TF simula stop, trailing e take  |
//|      profit con durata massima, in multipli dell'ATR del momento |
//|      E in punti fissi (ATR mediano del TF), provando tutte le    |
//|      griglie e tutti i ritardi d'ingresso insieme; misura i      |
//|      punti presi per segnale, consiglia la durata, confronta i   |
//|      TF, sceglie orari e giorni sul primo periodo e li verifica  |
//|      sul resto (con la curva cumulata).                          |
//|   8. SCANSIONE AUTOMATICA DEI FILTRI: su ogni TF prova da sola   |
//|      livelli di ADX x sottoinsiemi di regimi di volatilita' x    |
//|      volatilita' in salita, scelta in-sample e verifica sul      |
//|      resto (i filtri manuali InpAdxMin e InpRegimeAllow restano  |
//|      per replicare un EA preciso).                               |
//|   9. SCANSIONE DEI PARAMETRI: tutte le combinazioni di           |
//|      EmaPeriod x VolAvgPeriod x SignalThreshold del Delta con    |
//|      una gestione fissa, su ogni TF, scelta in-sample e verifica |
//|      fuori campione, effetto di ogni parametro e mappe soglia x  |
//|      EMA.                                                        |
//|  10. PICCHI, STOP E RISCHIO: per ogni segnale, su ogni TF, misura |
//|      il picco del movimento (prima di un ritiro di 1..9 ATR dal   |
//|      massimo) in punti e in ATR, dopo quanti minuti e candele si  |
//|      forma, quanto il prezzo va contro prima, e anche nelle       |
//|      sequenze di segnali nello stesso verso; la griglia stop x    |
//|      target (stop 0.5-9 ATR, target fino a 4 ATR, in ATR e in     |
//|      punti fissi) con scelta in-sample e verifica fuori campione; |
//|      lo stop che serve per ora, TF, posizione nella sequenza,     |
//|      intensita', volume tick, regime e ADX; gli orari migliori e  |
//|      le classi che filtrano; il rischio % (passi di 0.5) con lotti|
//|      per saldo e patrimonio; grafici SVG (percorso medio per      |
//|      regime di volatilita', istogramma dei picchi, sequenze reali).|
//|  COSTI: spread M1 reale + commissione (InpCommissionPerLotSide,  |
//|  default 3 per lotto e per lato) sempre inclusi; il valore del   |
//|  punto e' ricavato da solo, anche per i simboli QDM.             |
//|  TUTTO e' eseguito con i valori predefiniti, senza impostare     |
//|  nulla (gli input servono solo ad accorciare o ad ampliare).     |
//|  Il riepilogo copiabile contiene, per ogni serie e TF, una scheda|
//|  con l'esito di ogni test, piu' l'elenco dei test eseguiti; lo   |
//|  stesso testo e' nel digest.                                     |
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
//|  Replica fedelmente (i filtri ADX e regime vol sono applicati    |
//|  dallo script a valle; SD_Adx / SD_VolState li calcolano):       |
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
//| ADX come l'esempio ADX.mq5 di MetaQuotes (iADX): +DM e -DM in     |
//| percentuale del TR, lisciati con una EMA di periodo 'period'      |
//| (alpha = 2/(period+1)), DX = 100*|+DI-(-DI)|/(+DI+(-DI)), ADX =   |
//| EMA del DX. Ricostruzione dall'esempio: piccole differenze dal    |
//| valore dell'indicatore del terminale sono possibili, quindi il    |
//| numero di segnali filtrati puo' non coincidere al 100% con l'EA.  |
//| Le EMA partono dalla barra 'period' con seme zero (l'esempio le    |
//| fa partire prima): la differenza svanisce in circa 10 periodi e   |
//| lo script precarica 300 barre prima del periodo analizzato.       |
//+------------------------------------------------------------------+
void SD_Adx(const MqlRates &r[], const int n, const int period, double &adx[])
  {
   ArrayResize(adx, n);
   ArrayInitialize(adx, 0.0);
   if(period < 1 || n <= period + 1) return;
   const double a = 2.0 / (period + 1.0);
   double pdi = 0.0, ndi = 0.0, ax = 0.0;
   for(int i = 1; i < n; i++)
     {
      double pos = r[i].high - r[i-1].high;
      double neg = r[i-1].low - r[i].low;
      if(pos < 0.0) pos = 0.0;
      if(neg < 0.0) neg = 0.0;
      if(pos > neg) neg = 0.0;
      else if(pos < neg) pos = 0.0;
      else { pos = 0.0; neg = 0.0; }
      const double tr = MathMax(MathMax(MathAbs(r[i].high - r[i].low), MathAbs(r[i].high - r[i-1].close)), MathAbs(r[i].low - r[i-1].close));
      const double pd = (tr != 0.0) ? 100.0 * pos / tr : 0.0;
      const double nd = (tr != 0.0) ? 100.0 * neg / tr : 0.0;
      if(i < period) continue;                       // come l'esempio: le prime 'period' barre restano a zero
      pdi = pd * a + pdi * (1.0 - a);
      ndi = nd * a + ndi * (1.0 - a);
      const double s  = pdi + ndi;
      const double dx = (s != 0.0) ? 100.0 * MathAbs((pdi - ndi) / s) : 0.0;
      ax = dx * a + ax * (1.0 - a);
      adx[i] = ax;
     }
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

enum ENUM_RANK_SIDE
  {
   RS_FOLLOW = 0,  // Solo SEGUI il segnale (apri nel suo verso)
   RS_BOTH   = 1,  // SEGUI e INVERTI
   RS_FADE   = 2   // Solo INVERTI
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
input bool     InpUseVolState       = true;   // classifica ogni segnale per intensita' e regime di volatilita' (da solo non toglie segnali: il filtro dei regimi e' InpRegimeAllow e usa lo stesso calcolo anche se questo e' spento)
input int      InpVsAtrLen          = 14;     // ATR Length
input int      InpVsLookback        = 100;    // Percentile Lookback (barre)
input int      InpVsEmaSmooth       = 3;      // Smoothing EMA
input double   InpVsExpTh           = 1.8;    // Soglia Espansione (TR/ATR)
input double   InpVsCompTh          = 0.5;    // Soglia Compressione (TR/ATR)
input int      InpVsLowTh           = 30;     // Soglia LOW percentile
input int      InpVsHighTh          = 70;     // Soglia HIGH percentile
input int      InpVsExtremeTh       = 90;     // Soglia EXTREME percentile

input group "=== FILTRI DELL'EA (replica di ADX e regime di volatilita': tolgono i segnali da TUTTE le tabelle) ==="
input int      InpAdxPeriod         = 14;     // ADX_Period
input double   InpAdxMin            = 0;      // ADX_MinLevel: scarta i segnali con ADX sotto questo livello (0 = filtro spento; l'EA del backtest EURUSD M30 usava 17). ADX ricostruito dall'esempio ADX.mq5: piccole differenze dall'iADX del terminale sono possibili
input string   InpRegimeAllow       = "ALL";  // regimi di volatilita' ammessi, come Inp_AllowTrade*: ALL oppure elenco di LOW,NORMAL,HIGH,EXTREME (l'EA del backtest escludeva HIGH: LOW,NORMAL,EXTREME); usa lo stato di volatilita' qui sopra
input bool     InpRequireVolRising  = false;  // Inp_RequireVolIncreasing: ammette solo i segnali con percentile di volatilita' in salita

input group "=== DATI ==="
input datetime InpFrom              = D'2015.01.01 00:00';
input datetime InpTo                = D'2030.01.01 00:00';
input string   InpTFs               = "ALL";  // ALL oppure lista, es. M1,M5,M15,H1
input int      InpTimeOffsetH       = 0;      // ore da sommare al server time per fasce e giorni
input int      InpMaxGapMin         = 90;     // scarta finestre che contengono un buco di dati > N minuti (weekend, festivi)
input int      InpMaxEntryGapMin    = 5;      // scarta segnali se l'ingresso e' oltre N minuti dopo la chiusura (pausa di sessione)
input string   InpSkipEntryWin      = "";     // finestre d'ingresso da escludere da TUTTE le tabelle (ora server + offset), es. 22:00-00:30,06:00-06:15 (vuoto = nessuna): prova per il rollover

input group "=== MISURA (tutto in PUNTI) ==="
input string   InpHorizons          = "1,2,3,5,10,15,30,45,60,120,240,1440"; // orizzonti = tempo di tenuta in minuti, uguali per tutti i TF
input int      InpRefHorizon        = 60;     // orizzonte di riferimento per le tabelle di dettaglio
input string   InpLevels            = "50,100,150,200,250,300,350,400,450,500,550,600"; // livelli/target in punti (le spunte e i take profit della classifica)
input double   InpCostPoints        = 0;      // 0 = spread reale della barra M1 d'ingresso
input double   InpExtraCostPts      = 0;      // commissione/slippage extra in punti
input int      InpEntryLagMin       = 0;      // ritardo d'ingresso in minuti dopo la chiusura del segnale (0 = open della prima barra M1): prova di stress, se un risultato sparisce con 5 era una dislocazione del prezzo d'ingresso

input group "=== DENARO (posizione ipotetica) ==="
input double   InpLotSize           = 0.01;   // lotto ipotetico di ogni posizione
input double   InpCommissionPerLotSide = 3.0; // commissione per 1.00 lotto e per lato, in valuta del conto (conti Raw IC Markets / FP Markets: circa 3-3.5): e' SEMPRE inclusa nel costo di ogni risultato (due lati, convertita in punti); metti 0 solo se il tuo conto non la applica o se l'hai gia' messa in InpExtraCostPts
input double   InpPointValuePerLot  = 0;      // valore di 1 punto per 1.00 lotto in valuta del conto; 0 = automatico (consigliato): dal simbolo reale del broker, dai cambi o dal prezzo del simbolo stesso
input string   InpPointValueSymbol  = "";     // facoltativo: simbolo REALE del broker da cui leggere il valore del tick (es. AUDJPY.r); vuoto = lo cerca da solo (anche per i simboli personalizzati QDM)
input ENUM_RANK_SIDE InpRankSide    = RS_FOLLOW; // verso studiato nelle classifiche A/B: solo il verso del segnale (come un EA che apre dove dice il segnale), oppure anche l'inverso

input group "=== GESTIONE SIMULATA (stop, trailing, take profit, durata massima, ritardo d'ingresso) ==="
input bool     InpMgmt              = true;   // simula la gestione di un EA su ogni segnale: stop iniziale, trailing e take profit, uscita alla durata massima; misura i punti presi per segnale e la durata consigliata
input string   InpMgmtTFs           = "ALL";  // TF da simulare: ALL oppure elenco (es. M5,M15,H1); i TF con molti segnali sono campionati
input int      InpMgmtAtrLen        = 14;     // periodo dell'ATR del TF del segnale
input bool     InpMgmtPoints        = false;  // false = stop, trailing e take profit in multipli dell'ATR; true = in PUNTI fissi (per replicare un EA a SL/TP fissi, es. SL 120, TP 210)
input string   InpMgmtSlAtr         = "1,1.5,2,3"; // stop iniziale (multipli dell'ATR o punti, vedi InpMgmtPoints): fino a 8 valori, provati tutti insieme
input string   InpMgmtTrailAtr      = "0,1,2";     // trailing: distanza (lo zero = nessun trailing e' sempre incluso e conta nel limite di 6 valori); con distanza D parte quando il profitto raggiunge D e porta lo stop a (massimo favorevole - D)
input string   InpMgmtTpAtr         = "0,2";       // take profit (lo zero = nessuno e' sempre incluso e conta nel limite di 4 valori): 0,2 prova senza target e con target a 2 ATR; per esempio 0,1.5,3 ne prova di piu'
input bool     InpMgmtFixedVar      = true;        // prova OGNI gestione anche con stop, trailing e target in PUNTI FISSI (= gli stessi multipli per l'ATR mediano del TF sul primo periodo), oltre che in multipli dell'ATR del momento: e' la gestione di un EA a SL/TP fissi; ignorato con InpMgmtPoints
input string   InpMgmtLags          = "0,2,5,15";  // ritardi d'ingresso in minuti provati TUTTI insieme (fino a 8 valori compreso lo zero, sempre incluso come riferimento; aggiungi almeno un valore fra 1 e 5 per il giudizio "regge fino a 5 min"): mostrano se il risultato regge entrando piu' tardi
input int      InpMgmtMaxSignals    = 20000;  // massimo di segnali simulati per TF (campionamento uniforme; 0 o meno = tutti, molto lento): il tempo cresce con segnali x gestioni x ritardi
input bool     InpMgmtHighFirst     = false;  // ordine dentro la barra M1: false = prima il minimo (neutro su un percorso casuale), true = prima il massimo (limite pessimistico per il trailing; con il take profit favorisce il target)
input bool     InpMgmtSelect        = true;   // seleziona gli orari (ora x giorno della settimana) migliori sul primo periodo e li verifica sul resto, con la curva cumulata
input int      InpSelMinCell        = 15;     // segnali minimi in-sample perche' una cella ora x giorno possa essere scelta
input double   InpSelMinT           = 1.0;    // t in-sample minimo (non raggruppato) perche' una cella sia scelta, oltre al netto positivo

input group "=== SCANSIONE DEI PARAMETRI DEL SEGNALE (EmaPeriod x VolAvgPeriod x SignalThreshold, solo Synthetic Delta) ==="
input bool     InpSweep             = true;   // prova tutte le combinazioni dei tre parametri del Delta con una gestione fissa, scelta in-sample e verifica fuori campione
input string   InpSweepTFs          = "ALL";  // TF della scansione: ALL = tutti i TF analizzati tranne M1 (default), oppure un elenco (es. M15,M30,H1,H4) per accorciare il tempo
input string   InpSweepEma          = "5,8,10,13,14,18,21,34";  // livelli di EmaPeriod (massimo 16)
input string   InpSweepVol          = "10,14,20,30,50";          // livelli di VolAvgPeriod (massimo 12)
input string   InpSweepThr          = "0.05,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.50"; // livelli di SignalThreshold (massimo 16; in tutto al massimo 1500 combinazioni)
input double   InpSweepSl           = 1.5;    // stop iniziale della gestione che valuta ogni combinazione (multipli dell'ATR o punti, come InpMgmtPoints)
input double   InpSweepTrail        = 1.0;    // trailing della stessa gestione (0 = nessuno)
input double   InpSweepTp           = 0;      // take profit della stessa gestione (0 = nessuno)
input int      InpSweepHold         = 240;    // durata massima in minuti della stessa gestione
input int      InpSweepMaxSignals   = 8000;   // massimo di segnali valutati per combinazione e TF (campionamento uniforme; 0 o meno = tutti)

input group "=== SCANSIONE AUTOMATICA DEI FILTRI (ADX, regime di volatilita', volatilita' in salita) ==="
input bool     InpFilterScan        = true;   // prova da sola, su ogni TF, tutti i filtri dell'EA insieme (livelli di ADX x tutti i sottoinsiemi di regimi x volatilita' in salita), con la miglior gestione del TF: scelta in-sample, verifica fuori campione; non serve impostare InpAdxMin e InpRegimeAllow
input string   InpFilterAdx          = "10,15,17,20,25,30"; // livelli minimi di ADX provati (lo zero = nessun filtro e' sempre incluso; massimo 8 valori)

input group "=== PICCHI, STOP E RISCHIO (quanto si muovono i segnali, quando si forma il picco, quale stop e target, quali orari, quanto rischiare) ==="
input bool     InpPeak              = true;   // per ogni segnale misura il picco del movimento (punti, ATR, minuti, candele), la griglia stop x target, gli orari migliori verificati fuori campione e la scala del rischio % in passi di 0.5
input string   InpPeakTFs           = "ALL";  // TF analizzati: ALL (M1 compresa) oppure elenco, es. M5,M15,H1
input string   InpPeakPullbacks     = "1,2,3,4,5,6,7,8,9"; // ritiro dal massimo, in multipli dell'ATR, che chiude un picco (un picco per ogni valore, massimo 9 valori)
input double   InpPeakRefK          = 2;      // ritiro di riferimento (ATR) per le tabelle per sequenza e per i grafici: il piu' vicino fra quelli provati
input int      InpPeakMaxMin        = 1440;   // finestra massima di osservazione di ogni segnale in minuti
input int      InpPeakMaxCandles    = 12;     // oppure questo numero di candele del TF, se la finestra e' piu' lunga
input bool     InpPeakCross         = false;  // false = la finestra di un segnale finisce quando compare il segnale opposto della stessa serie; true = continua oltre
input int      InpPeakMaxSignals    = 30000;  // massimo di segnali misurati per TF (campionamento uniforme; 0 o meno = tutti, piu' lento)
input string   InpPeakTpAtr         = "0.5,1,1.5,2,3,4"; // target provati, in multipli dell'ATR (massimo 8 valori; gli stop provati vanno da 0.5 a 9 ATR in passi di 0.5)
input double   InpPeakGoodTp        = 2.0;    // segnale "buono" = raggiunge questo target (ATR) ...
input double   InpPeakGoodSl        = 1.5;    // ... senza toccare questo stop (ATR, multiplo di 0.5)
input int      InpPeakMinN          = 30;     // segnali minimi in una cella (ora, sequenza, classe) perche' sia valutata
input double   InpRiskMaxPct        = 2.0;    // rischio massimo per posizione in % del capitale
input double   InpRiskStepPct       = 0.5;    // passo della scala del rischio in punti percentuali (0.5, 1, 1.5, 2 ...)
input double   InpRiskKelly         = 0.25;   // frazione del Kelly usata per proporre il rischio (0.25 = un quarto)
input bool     InpPeakCharts        = true;   // grafici: percorso medio per regime di volatilita', istogramma dei picchi, esempi di sequenze reali
input int      InpPeakExamples      = 10;     // esempi di sequenze reali da disegnare (sul TF InpPeakExampleTF)
input ENUM_TIMEFRAMES InpPeakExampleTF = PERIOD_H1; // TF degli esempi disegnati

input group "=== PROVE DI STRESS ==="
input bool     InpStress            = true;   // tabella di stress: rifa' le regole migliori della tabella A con ingresso ritardato e costi piu' alti
input string   InpStressLags        = "0,1,2,3,5,10,15,30"; // ritardi d'ingresso in minuti dopo la chiusura del segnale (massimo 10 valori, lo zero e' sempre il riferimento)
input string   InpStressExtra       = "0,5,10,20";          // costo extra in punti da sommare allo spread e alla commissione (massimo 6 valori)
input string   InpFixedRule         = "";     // regola fissa da mettere sempre in testa alle prove di stress e alla scheda: TF,inizio fascia,SEGUI o INVERTI,tenuta in minuti,target in punti (0 = nessuno); es. M15,21:00,SEGUI,1440,300. Serve a verificare una regola gia' trovata su un altro simbolo o periodo senza selezione (per i dati nuovi usa InpSplitPct = 5)
input int      InpStressRules       = 6;      // quante regole mettere sotto stress (1-12): prima quelle che reggono fuori campione, poi le migliori in-sample

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
input bool     InpPlacebo           = true;   // controllo placebo: ricalcola le classifiche A con direzione casuale sugli stessi istanti (raddoppia la memoria della classifica)
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
#define RKN  10      // campi classifica: n, somma pnl, somma pnl^2, hit, somma MAE, somma verso s (+1 lungo/-1 corto), somma D, somma s*D, somma D^2, somma s*D^2 (D = (pnl se lungo - pnl se corto)/2)
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
int      g_nxsb[];                 // [serie][t][categoria 1..19][fascia][m]: segnali per fascia (pesi della base di categoria)
double   g_nxbb[];                 // [t][categoria 1..19][fascia][m][4]: barre, favorevole, range, |chiusura| di tutte le barre
double   g_cmpGross[];             // lordo medio per serie e TF (confronto)

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
int      g_cApn = 0, g_cAusable = 0, g_cApos = 0, g_cAstrong = 0, g_cAstrongN = 0, g_cAone = 0, g_cAns = 0;
string   g_cAsurv = "", g_cBdesc = "";
double   g_cAsurvMean = 0.0, g_cAsurvN = 0.0;       // prima sopravvissuta della tabella A: netto medio OOS (pt) e posizioni OOS
double   g_cBsumAll = 0.0, g_cBtotal = 0.0, g_cBmean = 0.0, g_cBt = 0.0, g_cBn = 0.0, g_cBshareN = 0.0, g_cBshareLate = 0.0;
int      g_cBboth = 0, g_cBincoh = 0, g_cBusable = 0, g_cBpn = 0;
//--- aggregati per serie, usati dal confronto
int      g_agGpos[2], g_agGneg[2], g_agNsig[2], g_agA1ok[2], g_agAns[2], g_agNtf[2], g_agAedge[2], g_agAok[2];
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

//--- prove di stress: ritardi (minuti) e costi extra (punti) provati, testo per il riepilogo
int      g_slag[];
double   g_sext[];
int      g_nSlag = 0, g_nSext = 0;
string   g_cStress = "";
string   g_cMgmt = "", g_cMgmt3 = "", g_cMgmt4 = "", g_cMgmt5 = "";
//--- schede per time frame del riepilogo: una stringa per serie e TF (indice = serie * g_nT + t); la scansione dei parametri e' per TF (solo Delta)
string   g_cdPts[], g_cdMg[], g_cdLag[], g_cdSel[], g_cdFilt[], g_cdSw[], g_cdPk[];
int      g_cdPos[];            // test positivi e significativi fuori campione per serie e TF
string   g_cdWin = "";         // elenco dei test positivi (serie, TF, test) per la riga finale del riepilogo
int      g_cdEval[];           // test valutabili per serie e TF
int      g_mgPosTf = 0, g_mgEvalTf = 0, g_mgRobTf = 0, g_mgRobTested = 0, g_mgSelPosTf = 0, g_mgSelEvalTf = 0;   // esiti della gestione simulata per il paragrafo di fattibilita'
bool     g_mgOn = false, g_mgHasShort = false;
double   g_atr[];            // ATR (punti) del TF del segnale, sulla barra del segnale, parallelo a g_ent
bool     g_atrOn = false;    // l'ATR del segnale serve (gestione simulata o picchi)
bool     g_xfOn = false;     // ADX e regime di volatilita' della barra del segnale servono (scansione dei filtri o picchi)
uchar    g_ib[];             // classe di intensita' (TR/ATR) della candela del segnale, parallelo a g_ent (solo con InpPeak)
double   g_m1Vcum[], g_m1Rcum[];   // volume tick e range M1 (punti) cumulati: elemento i = somma delle barre M1 prima di i (solo con InpPeak)
double   g_hrVol[24];        // indice del volume tick per ora del giorno (ora server + offset): media per barra M1 dell'ora / media generale
double   g_acctBal = 0.0, g_acctEq = 0.0;   // saldo e patrimonio netto del conto al lancio (0 = non disponibili)
string   g_fixedNote = "";   // problema nella regola fissa (vuoto se va bene)

//--- denaro: valore di 1 punto per 1.00 lotto nella valuta del conto, commissione in punti, costo extra totale in punti
double   g_pv = 0.0, g_commPts = 0.0, g_extraPts = 0.0;
bool     g_money = false;
string   g_ccy = "EUR";
string   g_pvInfo = "";      // da dove viene il valore del punto e cambio implicito
bool     g_pvWarn = false;   // valore del punto stimato o non verificato (la commissione e' inclusa lo stesso)

//--- spread M1 per fascia d'entrata (stesse fasce della classifica, ora server + offset)
#define SPRBIN 400
double   g_sprN[], g_sprMean[], g_sprMed[], g_sprP90[];

//--- finestre forward per l'orizzonte corrente
double   g_fHi[], g_fLo[], g_fCl[];
uchar    g_ok[];
int      g_dqH[], g_dqL[];

//--- barre di ogni TF con ingresso valido (appese in sequenza)
int      g_tfOff[], g_tfCnt[], g_tfBars[], g_tfEv[], g_tfRejGap[], g_tfRejM1[], g_tfRejWin[];
int      g_tfRejAdx[], g_tfRejReg[];       // segnali tolti dai filtri dell'EA (ADX, regime di volatilita')
int      g_regMask = 15;                   // regimi ammessi: bit 0 LOW, 1 NORMAL, 2 HIGH, 3 EXTREME
bool     g_regFilt = false, g_adxFilt = false;
string   g_filtTxt = "";                   // descrizione dei filtri dell'EA per il report e il riepilogo
int      g_skN = 0;                 // finestre d'ingresso escluse (InpSkipEntryWin)
int      g_skA[], g_skB[];          // minuto di inizio e fine (del giorno, ora server + offset)
int      g_ent[];
uchar    g_vs[];            // codice stato di volatilita' per barra (vedi SD_VolState)
uchar    g_adxq[];          // ADX della barra del segnale in mezzi punti (0-200), parallelo a g_ent: per la scansione dei filtri (vuoto se spenta)
uchar    g_reg[];           // codice stato di volatilita' della barra del segnale anche con InpUseVolState spento, 255 = finestra incompleta (come g_adxq)
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
double   g_plcQ[];           // placebo: quota di acquisti dei segnali per [t][fascia][IS/OOS]
void     BuildPlcQ();
void     MgmtSetup();
void     FsSetup();
void     PkSetup();
void     AddConc(const int s, const string topic, const string text);
double   g_rkP[], g_rgP[];   // placebo: stesse regole e stessi istanti, direzione di ogni segnale sostituita da una casuale
bool     g_plc = false;
bool     g_cPok = false;
double   g_cPbest = 0.0;
int      g_cPstrong = 0, g_cPstrongN = 0;
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
string   g_reportTag = "", g_reportFile = "", g_reportTmp = "";

struct CellStat
  {
   double n, mfe, mae, ret, tNaive, tCl, cost, win, lose, zSign, baseMfe, gross, tGross;
  };

//+------------------------------------------------------------------+
//| Utilita'                                                          |
//+------------------------------------------------------------------+
string F0(const double v) { return DoubleToString(v, 0); }
string F1(const double v) { return DoubleToString(v, 1); }
string F2(const double v) { return DoubleToString(v, 2); }
string IS(const long v)   { return IntegerToString(v); }
string Sg(const double v, const int dg = 1) { return string(v > 0.0 ? "+" : "") + DoubleToString(v, dg); }
string Pc(const double v) { return (v < 10.0) ? F1(v) : F0(v); }      // percentuale: un decimale sotto il 10%, cosi' 1.4% non diventa 1%

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

string RBktLabel(const int b)
  {
   int s0 = b * g_rbMin, e0 = s0 + g_rbMin;
   return StringFormat("%02d:%02d-%02d:%02d", s0 / 60, s0 % 60, e0 / 60, e0 % 60);
  }

//--- spread medio della fascia in rapporto alla mediana generale (1 = nella norma)
double SprRatio(const int rb)
  {
   if(rb < 0 || rb >= ArraySize(g_sprMean)) return 0.0;
   return g_sprMean[rb] / MathMax(1.0, g_medSpr);
  }

string SprColor(const int rb)
  {
   const double r = SprRatio(rb);
   if(r >= 2.5) return "#bf616a";
   if(r >= 1.5) return "#d08770";
   return "";
  }

//--- frase per il riepilogo: le fasce piu' care (spread medio >= 1.5 volte la mediana generale), massimo tre
string SprTopText()
  {
   if(InpCostPoints > 0.0 || g_nRB < 1 || ArraySize(g_sprMean) < g_nRB) return "";
   bool used[];
   ArrayResize(used, g_nRB);
   ArrayInitialize(used, false);
   string out = "";
   int shown = 0;
   for(int k = 0; k < 3; k++)
     {
      int bi = -1;
      double bv = 0.0;
      for(int rb = 0; rb < g_nRB; rb++)
         if(!used[rb] && g_sprN[rb] >= 100.0 && g_sprMean[rb] > bv) { bv = g_sprMean[rb]; bi = rb; }
      if(bi < 0 || SprRatio(bi) < 1.5) break;
      used[bi] = true;
      out += (shown > 0 ? ", " : "") + RBktLabel(bi) + " " + F1(g_sprMean[bi]) + " pt";
      shown++;
     }
   if(shown == 0) return "";
   return " Spread M1 medio piu' alto nelle fasce (ora server + offset): " + out + ", contro una mediana generale di " + F0(g_medSpr) +
          " pt: dove lo spread e' largo il netto e' piu' fragile, controlla la colonna Spread fascia nelle classifiche.";
  }

//--- denaro della posizione ipotetica (InpLotSize) per una quantita' in punti; 3 decimali per posizione, 2 per i totali
double MnyV(const double pts) { return pts * g_pv * InpLotSize; }
string Mny(const double pts)  { return g_money ? DoubleToString(MnyV(pts), 3) : string("n.d."); }
string MnyT(const double pts) { return g_money ? DoubleToString(MnyV(pts), 2) : string("n.d."); }
string MnyU(const double pts) { return g_money ? (DoubleToString(MnyV(pts), 3) + " " + g_ccy) : string("n.d."); }
string MnyTU(const double pts) { return g_money ? (DoubleToString(MnyV(pts), 2) + " " + g_ccy) : string("n.d."); }

//--- lotto ipotetico senza zeri finali (0.01, 0.005, 1.00)
string LotTxt()
  {
   string t = DoubleToString(InpLotSize, 3);
   while(StringLen(t) > 4 && StringSubstr(t, StringLen(t) - 1, 1) == "0") t = StringSubstr(t, 0, StringLen(t) - 1);
   if(StringSubstr(t, StringLen(t) - 1, 1) == ".") t = StringSubstr(t, 0, StringLen(t) - 1);
   return t;
  }

//--- verso studiato nelle classifiche
bool SideOK(const int dd)
  {
   if(InpRankSide == RS_BOTH) return true;
   return (InpRankSide == RS_FOLLOW) ? (dd == 0) : (dd == 1);
  }

//--- valore del tick di un simbolo: dopo SymbolSelect il terminale puo' impiegare qualche istante a fornirlo (0 nel frattempo)
double PvTickValue(const string name)
  {
   for(int w = 0; w < 10; w++)
     {
      double tv = SymbolInfoDouble(name, SYMBOL_TRADE_TICK_VALUE_PROFIT);
      if(tv <= 0.0) tv = SymbolInfoDouble(name, SYMBOL_TRADE_TICK_VALUE);
      if(tv > 0.0) return tv;
      Sleep(100);
     }
   return 0.0;
  }

//--- simboli del terminale che contengono i primi 6 caratteri del simbolo analizzato (senza il suffisso _QDM): per suggerire il nome reale del broker
string PvCandidates()
  {
   const string base = StringSubstr(_Symbol, 0, 6);
   string out = "";
   int found = 0;
   const int n = SymbolsTotal(false);
   for(int i = 0; i < n && found < 8; i++)
     {
      const string nm = SymbolName(i, false);
      if(StringFind(nm, base) < 0 || nm == _Symbol) continue;
      out += string(found > 0 ? ", " : "") + nm;
      found++;
     }
   return out;
  }

//--- aggiunge un nome a un elenco senza doppioni
void PvAdd(string &arr[], const string v)
  {
   if(v == "") return;
   for(int i = 0; i < ArraySize(arr); i++) if(arr[i] == v) return;
   const int k = ArraySize(arr);
   ArrayResize(arr, k + 1);
   arr[k] = v;
  }

//--- nome senza il suffisso _QDM (il simbolo reale del broker ha lo stesso nome, es. EURUSD.r)
string PvCleanName(const string name)
  {
   string clean = name;
   if(StringLen(clean) > 4 && StringSubstr(clean, StringLen(clean) - 4) == "_QDM") clean = StringSubstr(clean, 0, StringLen(clean) - 4);
   return clean;
  }

//--- simboli REALI (non personalizzati) del terminale i cui primi 6 caratteri sono 'key'; ritorna quanti (al massimo 8)
int PvReal(const string key, string &out[])
  {
   ArrayResize(out, 0);
   if(StringLen(key) < 6) return 0;
   const int n = SymbolsTotal(false);
   for(int i = 0; i < n && ArraySize(out) < 8; i++)
     {
      const string nm = SymbolName(i, false);
      if(StringLen(nm) < 6 || StringSubstr(nm, 0, 6) != key || nm == _Symbol) continue;
      if(SymbolInfoInteger(nm, SYMBOL_CUSTOM) != 0) continue;
      PvAdd(out, nm);
     }
   return ArraySize(out);
  }

//--- ultimo bid di un simbolo, con una breve attesa della sincronizzazione; 0 se non disponibile
double PvBid(const string name)
  {
   if(!SymbolSelect(name, true)) return 0.0;
   for(int w = 0; w < 10; w++)
     {
      const double b = SymbolInfoDouble(name, SYMBOL_BID);
      if(b > 0.0) return b;
      Sleep(100);
     }
   return 0.0;
  }

//--- cambio fra due valute: unita' di 'b' per 1 'a', da un simbolo diretto a+b o inverso b+a (suffisso del broker, nome nudo, simboli reali del terminale); 0 se non disponibile
double PvPairRate(const string a, const string b, const string sfx, string &src)
  {
   src = "";
   if(a == b) return 1.0;
   for(int dr = 0; dr < 2; dr++)
     {
      const string k = (dr == 0) ? (a + b) : (b + a);
      string cand[];
      ArrayResize(cand, 0);
      PvAdd(cand, k + sfx);
      PvAdd(cand, k);
      string real[];
      const int nr = PvReal(k, real);
      for(int q = 0; q < nr; q++) PvAdd(cand, real[q]);
      for(int c = 0; c < ArraySize(cand); c++)
        {
         const double bid = PvBid(cand[c]);
         if(bid <= 0.0) continue;
         src = cand[c] + " = " + DoubleToString(bid, 5);
         return (dr == 0) ? bid : 1.0 / bid;
        }
     }
   return 0.0;
  }

//--- cambio acc -> pc diretto oppure passando dal dollaro; 0 se non disponibile
double PvRate(const string acc, const string pc, const string sfx, string &src)
  {
   double r = PvPairRate(acc, pc, sfx, src);
   if(r > 0.0) return r;
   if(acc != "USD" && pc != "USD")
     {
      string s1, s2;
      const double r1 = PvPairRate(acc, "USD", sfx, s1);
      const double r2 = PvPairRate("USD", pc, sfx, s2);
      if(r1 > 0.0 && r2 > 0.0)
        {
         src = s1 + " e " + s2;
         return r1 * r2;
        }
     }
   src = "";
   return 0.0;
  }

//--- vero se il nome di sei lettere e' una coppia forex (3 + 3 lettere, entrambe valute note)
bool PvIsFxKey(const string key)
  {
   const string cur = "USD,EUR,GBP,JPY,CHF,CAD,AUD,NZD,SEK,NOK,DKK,PLN,CZK,HUF,TRY,ZAR,MXN,SGD,HKD,CNH";
   if(StringLen(key) != 6) return false;
   return (StringFind(cur, StringSubstr(key, 0, 3)) >= 0 && StringFind(cur, StringSubstr(key, 3, 3)) >= 0);
  }

//--- valore del punto, commissione in punti e costo extra totale. Senza input manuali: cerca da solo il valore del tick di un simbolo reale
//--- (anche per i simboli personalizzati QDM), altrimenti lo calcola dal cambio, altrimenti dal prezzo del simbolo stesso, altrimenti lo stima 1:1.
//--- La commissione e' quindi sempre inclusa nel costo; l'origine del valore e' scritta nel report e nel riepilogo.
void SetupMoney()
  {
   g_ccy = AccountInfoString(ACCOUNT_CURRENCY);
   if(g_ccy == "") g_ccy = "EUR";
   g_pv = 0.0;
   g_commPts = 0.0;
   g_pvInfo = "";
   g_pvWarn = false;
   const bool custom = (SymbolInfoInteger(_Symbol, SYMBOL_CUSTOM) != 0);
   const string clean = PvCleanName(_Symbol);
   const string key = (StringLen(clean) >= 6) ? StringSubstr(clean, 0, 6) : clean;
   const string sfx = (StringLen(clean) > 6) ? StringSubstr(clean, 6) : "";
   string pcOwn = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   StringToUpper(pcOwn);
   if(InpPointValuePerLot > 0.0)
     {
      g_pv = InpPointValuePerLot;
      g_pvInfo = "valore del punto impostato a mano";
     }
   else
     {
      //--- 1) valore del tick letto da un simbolo reale: quello indicato, il simbolo stesso (se non personalizzato o gia' nella valuta del conto), il nome senza _QDM, i simboli reali con gli stessi 6 caratteri
      string cand[];
      ArrayResize(cand, 0);
      if(InpPointValueSymbol != "") PvAdd(cand, InpPointValueSymbol);
      if(!custom || (pcOwn != "" && pcOwn == g_ccy)) PvAdd(cand, _Symbol);
      PvAdd(cand, clean);
      string real[];
      const int nr = PvReal(key, real);
      for(int q = 0; q < nr; q++) PvAdd(cand, real[q]);
      double csReal = 0.0;
      string pcReal = "";
      for(int c = 0; c < ArraySize(cand) && g_pv <= 0.0; c++)
        {
         const string src = cand[c];
         if(!SymbolSelect(src, true))
           {
            if(src == InpPointValueSymbol) g_pvInfo = "il simbolo '" + src + "' non esiste nel terminale (controlla il nome con Ctrl+U); ";
            continue;
           }
         //--- un simbolo personalizzato ha spesso un valore del tick di default: lo si usa solo se indicato a mano o se non richiede conversione di valuta
         if(SymbolInfoInteger(src, SYMBOL_CUSTOM) != 0 && src != InpPointValueSymbol && !(src == _Symbol && pcOwn != "" && pcOwn == g_ccy)) continue;
         const double cs0 = SymbolInfoDouble(src, SYMBOL_TRADE_CONTRACT_SIZE);
         string pc0 = SymbolInfoString(src, SYMBOL_CURRENCY_PROFIT);
         StringToUpper(pc0);
         if(csReal <= 0.0 && cs0 > 0.0) csReal = cs0;
         if(pcReal == "" && pc0 != "") pcReal = pc0;
         const double tv = PvTickValue(src);
         const double ts = SymbolInfoDouble(src, SYMBOL_TRADE_TICK_SIZE);
         if(tv > 0.0 && ts > 0.0)
           {
            g_pv = tv / ts * g_pt;
            g_pvInfo += string(src == _Symbol ? "valore letto dal simbolo " : "valore letto dal simbolo reale ") + src + ": valore del tick " + DoubleToString(tv, 5) + " " + g_ccy;
            if(cs0 > 0.0 && pc0 != "")
               g_pvInfo += " (contratto " + F0(cs0) + " x " + DoubleToString(g_pt, _Digits) + " " + pc0 + " = " + F2(cs0 * g_pt) + " " + pc0 + " per punto e per lotto, cambio implicito 1 " + g_ccy + " = " + F2(cs0 * g_pt / g_pv) + " " + pc0 + ")";
           }
        }
      //--- 2) dal cambio: contratto x punto nella valuta di profitto, convertito nella valuta del conto
      if(g_pv <= 0.0)
        {
         double cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         if(cs <= 0.0) cs = csReal;
         bool csGuess = false;
         if(cs <= 0.0 && PvIsFxKey(key)) { cs = 100000.0; csGuess = true; }
         string pc = (pcOwn != "") ? pcOwn : pcReal;
         if(pc == "" && PvIsFxKey(key)) pc = StringSubstr(key, 3, 3);
         if(cs > 0.0 && pc != "")
           {
            string rsrc = "";
            double rate = PvRate(g_ccy, pc, sfx, rsrc);
            if(rate <= 0.0 && g_n1 > 0 && g_m1Close[g_n1 - 1] > 0.0 && StringLen(key) == 6)
              {
               //--- il simbolo analizzato e' esso stesso il cambio fra la valuta del conto e quella di profitto
               if(key == g_ccy + pc) { rate = g_m1Close[g_n1 - 1]; rsrc = "ultimo prezzo di " + key + " nello storico = " + DoubleToString(rate, 5); }
              }
            if(rate > 0.0)
              {
               g_pv = cs * g_pt / rate;
               g_pvInfo += "valore calcolato: contratto " + F0(cs) + string(csGuess ? " (ipotizzato)" : "") + " x " + DoubleToString(g_pt, _Digits) + " " + pc + " = " + F2(cs * g_pt) + " " + pc + " per punto e per lotto" +
                           string(pc == g_ccy ? "" : (", convertito in " + g_ccy + " con il cambio " + rsrc));
               if(csGuess) g_pvWarn = true;
              }
           }
        }
      //--- 3) valore del tick del simbolo analizzato anche se personalizzato (non verificabile)
      if(g_pv <= 0.0)
        {
         const double tv = PvTickValue(_Symbol);
         const double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tv > 0.0 && ts > 0.0)
           {
            g_pv = tv / ts * g_pt;
            g_pvWarn = true;
            g_pvInfo += "ATTENZIONE: valore del tick del simbolo personalizzato " + _Symbol + " (" + DoubleToString(tv, 5) + " " + g_ccy + ") non verificabile con un simbolo reale";
           }
        }
      //--- 4) ultima ipotesi: valuta di profitto uguale a quella del conto
      if(g_pv <= 0.0)
        {
         double cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         if(cs <= 0.0) cs = csReal;
         if(cs <= 0.0) cs = PvIsFxKey(key) ? 100000.0 : 1.0;
         g_pv = cs * g_pt;
         g_pvWarn = true;
         g_pvInfo += "ATTENZIONE: valore stimato con contratto " + F0(cs) + " x punto " + DoubleToString(g_pt, _Digits) + " ipotizzando che la valuta di profitto sia " + g_ccy + " (nessun simbolo reale ne' cambio trovato)";
        }
      if(g_pvWarn)
        {
         const string cd = PvCandidates();
         if(cd != "") g_pvInfo += ". Simboli simili nel terminale: " + cd + " (puoi indicarne uno in InpPointValueSymbol, ma non e' necessario)";
        }
     }
   g_money = (g_pv > 0.0 && InpLotSize > 0.0);
   if(g_pv > 0.0 && InpCommissionPerLotSide > 0.0) g_commPts = 2.0 * InpCommissionPerLotSide / g_pv;
   g_extraPts = InpExtraCostPts + g_commPts;
   if(g_money)
      Print("Denaro: lotto ", LotTxt(), " | 1 punto per 1.00 lotto = ", DoubleToString(g_pv, 4), " ", g_ccy, " (", g_pvInfo, ")",
            " | commissione ", DoubleToString(InpCommissionPerLotSide, 2), " per lato e per lotto = ", DoubleToString(g_commPts, 2), " pt a/r (sempre inclusa nel costo)");
   else
      Print("Colonne in denaro non calcolate (InpLotSize = 0); commissione ", g_commPts > 0.0 ? "inclusa" : "NON inclusa", " (valore del punto: ", g_pvInfo, ").");
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
      bool dup = false;
      for(int q = 0; q < k; q++) if(MathAbs(out[q] - v) < 1.0e-9) { dup = true; break; }
      if(dup) continue;
      ArrayResize(out, k + 1);
      out[k] = v;
     }
   if(ArraySize(out) > 1) ArraySort(out);
   return ArraySize(out);
  }

//--- lista di numeri positivi (ritardi, costi extra) con lo zero sempre in testa come riferimento, senza doppioni, ordinata
int ParseNonNegList(const string src, double &out[], const int maxN, const double maxV)
  {
   string parts[];
   const int np = StringSplit(src, ',', parts);
   ArrayResize(out, 1);
   out[0] = 0.0;
   for(int i = 0; i < np; i++)
     {
      string pp = parts[i];
      StringTrimLeft(pp); StringTrimRight(pp);
      if(pp == "") continue;
      const double v = StringToDouble(pp);
      if(v <= 0.0 || v > maxV) continue;
      const int k = ArraySize(out);
      if(k >= maxN) { Print("Lista '", src, "' troncata a ", maxN, " valori (lo zero e' sempre incluso e conta nel limite)."); break; }
      bool dup = false;
      for(int q = 0; q < k; q++) if(MathAbs(out[q] - v) < 1.0e-9) { dup = true; break; }
      if(dup) continue;
      ArrayResize(out, k + 1);
      out[k] = v;
     }
   if(ArraySize(out) > 1) ArraySort(out);
   return ArraySize(out);
  }

//--- ritardi in minuti da un elenco (lo zero e' sempre il primo): numeri interi, senza doppioni
int ParseLagList(const string src, const int maxN, int &out[])
  {
   double tmp[];
   const int nn = ParseNonNegList(src, tmp, maxN, 240.0);
   ArrayResize(out, 0);
   for(int q = 0; q < nn; q++)
     {
      const int v = (int)MathRound(tmp[q]);
      bool dup = false;
      for(int w = 0; w < ArraySize(out); w++) if(out[w] == v) dup = true;
      if(dup) continue;
      const int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k] = v;
     }
   return ArraySize(out);
  }

//+------------------------------------------------------------------+
//| Finestre d'ingresso escluse (InpSkipEntryWin)                     |
//+------------------------------------------------------------------+
int ClockToMin(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   string hm[];
   if(StringSplit(s, ':', hm) != 2) return -1;
   const int h = (int)StringToInteger(hm[0]);
   const int m = (int)StringToInteger(hm[1]);
   if(h < 0 || h > 24 || m < 0 || m > 59) return -1;
   return (h * 60 + m) % 1440;
  }

void ParseSkipWin()
  {
   g_skN = 0;
   ArrayResize(g_skA, 0);
   ArrayResize(g_skB, 0);
   string src = InpSkipEntryWin;
   StringTrimLeft(src);
   StringTrimRight(src);
   if(src == "") return;
   string parts[];
   const int np = StringSplit(src, ',', parts);
   for(int i = 0; i < np; i++)
     {
      string w = parts[i];
      StringTrimLeft(w);
      StringTrimRight(w);
      if(w == "") continue;
      string ab[];
      if(StringSplit(w, '-', ab) != 2) { Print("InpSkipEntryWin: finestra non valida '", w, "' (ignorata)."); continue; }
      const int mA = ClockToMin(ab[0]);
      const int mB = ClockToMin(ab[1]);
      if(mA < 0 || mB < 0 || mA == mB) { Print("InpSkipEntryWin: finestra non valida '", w, "' (ignorata)."); continue; }
      const int k = ArraySize(g_skA);
      ArrayResize(g_skA, k + 1);
      ArrayResize(g_skB, k + 1);
      g_skA[k] = mA;
      g_skB[k] = mB;
     }
   g_skN = ArraySize(g_skA);
  }

//--- true se l'istante (tempo server in secondi) cade in una finestra esclusa; le finestre possono attraversare la mezzanotte
bool InSkipWin(const long tsec)
  {
   if(g_skN == 0) return false;
   const int mn = (int)(((((tsec + g_off) % 86400L) + 86400L) % 86400L) / 60L);
   for(int i = 0; i < g_skN; i++)
     {
      if(g_skA[i] < g_skB[i]) { if(mn >= g_skA[i] && mn < g_skB[i]) return true; }
      else if(mn >= g_skA[i] || mn < g_skB[i]) return true;
     }
   return false;
  }

bool SetupInputs()
  {
   if(InpFrom >= InpTo) { Print("InpFrom deve precedere InpTo."); return false; }
   if(InpEntryLagMin < 0) { Print("InpEntryLagMin deve essere >= 0."); return false; }
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

   ParseSkipWin();
   g_vpar.atrLen    = MathMax(2, InpVsAtrLen);
   g_vpar.lookback  = MathMax(10, InpVsLookback);
   g_vpar.emaSmooth = MathMax(1, InpVsEmaSmooth);
   g_vpar.expTh     = InpVsExpTh;
   g_vpar.compTh    = InpVsCompTh;
   g_vpar.lowTh     = InpVsLowTh;
   g_vpar.highTh    = InpVsHighTh;
   g_vpar.extremeTh = InpVsExtremeTh;
   g_volWarm        = g_vpar.atrLen + g_vpar.lookback + g_vpar.emaSmooth + 10;

   //--- filtri dell'EA
   g_adxFilt = (InpAdxMin > 0.0);
   g_regMask = 15;
   g_regFilt = false;
   {
    string rg = InpRegimeAllow;
    StringTrimLeft(rg); StringTrimRight(rg); StringToUpper(rg);
    if(rg != "" && rg != "ALL")
      {
       string parts[];
       const int np = StringSplit(rg, ',', parts);
       int mk = 0;
       for(int q = 0; q < np; q++)
         {
          string pp = parts[q];
          StringTrimLeft(pp); StringTrimRight(pp);
          if(pp == "LOW" || pp == "L") mk |= 1;
          else if(pp == "NORMAL" || pp == "N") mk |= 2;
          else if(pp == "HIGH" || pp == "H") mk |= 4;
          else if(pp == "EXTREME" || pp == "X" || pp == "E") mk |= 8;
          else if(pp != "") Print("InpRegimeAllow: regime sconosciuto '", pp, "' (ignorato).");
         }
       if(mk == 0) { Print("InpRegimeAllow non contiene regimi validi: filtro dei regimi spento."); mk = 15; }
       g_regMask = mk;
      }
    g_regFilt = (g_regMask != 15 || InpRequireVolRising);
    if(g_regFilt && !InpUseVolState)
      {
       Print("Filtro dei regimi richiesto ma InpUseVolState e' spento: lo stato di volatilita' viene calcolato lo stesso per il filtro.");
      }
    g_filtTxt = "";
    if(g_adxFilt) g_filtTxt += "ADX(" + IntegerToString(MathMax(1, InpAdxPeriod)) + ") >= " + DoubleToString(InpAdxMin, 1);
    if(g_regFilt)
      {
       string ra = "";
       if((g_regMask & 1) != 0) ra += string(ra == "" ? "" : ",") + "LOW";
       if((g_regMask & 2) != 0) ra += string(ra == "" ? "" : ",") + "NORMAL";
       if((g_regMask & 4) != 0) ra += string(ra == "" ? "" : ",") + "HIGH";
       if((g_regMask & 8) != 0) ra += string(ra == "" ? "" : ",") + "EXTREME";
       g_filtTxt += string(g_filtTxt != "" ? "; " : "") + "regimi ammessi " + ra + string(InpRequireVolRising ? " con volatilita' in salita" : "");
      }
   }

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
   {
    g_nSlag = ParseLagList(InpStressLags, 10, g_slag);
    g_nSext = ParseNonNegList(InpStressExtra, g_sext, 6, 1000.0);
   }
   g_atrOn = (InpMgmt || InpPeak);
   g_xfOn  = (InpFilterScan || InpPeak);
   MgmtSetup();
   FsSetup();
   PkSetup();
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

//--- spread M1 per fascia: media, mediana e p90 (istogramma a passo 1 punto, ultimo bin = SPRBIN-1 o piu'), solo barre nel periodo richiesto
void BuildSpreadStats()
  {
   double hist[], sSum[];
   ArrayResize(hist, g_nRB * SPRBIN);
   ArrayInitialize(hist, 0.0);
   ArrayResize(sSum, g_nRB);
   ArrayInitialize(sSum, 0.0);
   ArrayResize(g_sprN, g_nRB);
   ArrayInitialize(g_sprN, 0.0);
   ArrayResize(g_sprMean, g_nRB);
   ArrayResize(g_sprMed, g_nRB);
   ArrayResize(g_sprP90, g_nRB);
   const long rbSec = (long)g_rbMin * 60L;
   for(int i = 0; i < g_n1; i++)
     {
      if(g_m1Time[i] < InpFrom || g_m1Time[i] > InpTo) continue;
      const long tsr = ((((long)g_m1Time[i] + g_off) % 86400L) + 86400L) % 86400L;
      const int rb = (int)(tsr / rbSec);
      if(rb < 0 || rb >= g_nRB) continue;
      const int sv = (g_m1Spr[i] < 0) ? 0 : g_m1Spr[i];
      hist[rb * SPRBIN + ((sv >= SPRBIN) ? SPRBIN - 1 : sv)] += 1.0;
      g_sprN[rb] += 1.0;
      sSum[rb] += (double)sv;
     }
   for(int rb = 0; rb < g_nRB; rb++)
     {
      g_sprMean[rb] = 0.0; g_sprMed[rb] = 0.0; g_sprP90[rb] = 0.0;
      if(g_sprN[rb] <= 0.0) continue;
      g_sprMean[rb] = sSum[rb] / g_sprN[rb];
      double cum = 0.0;
      bool gotMed = false, gotP90 = false;
      for(int b = 0; b < SPRBIN; b++)
        {
         cum += hist[rb * SPRBIN + b];
         if(!gotMed && cum >= 0.5 * g_sprN[rb]) { g_sprMed[rb] = (double)b; gotMed = true; }
         if(!gotP90 && cum >= 0.9 * g_sprN[rb]) { g_sprP90[rb] = (double)b; gotP90 = true; break; }
        }
     }
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
   if(InpPeak)
     {
      ArrayResize(g_m1Vcum, g_n1 + 1);
      ArrayResize(g_m1Rcum, g_n1 + 1);
      g_m1Vcum[0] = 0.0;
      g_m1Rcum[0] = 0.0;
     }

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
      if(InpPeak)
        {
         g_m1Vcum[i + 1] = g_m1Vcum[i] + (double)g_r1[i].tick_volume;
         g_m1Rcum[i + 1] = g_m1Rcum[i] + (g_r1[i].high - g_r1[i].low) / g_pt;
        }
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
   BuildSpreadStats();
   if(InpPeak)
     {
      //--- indice del volume tick per ora del giorno: media per barra M1 dell'ora in rapporto alla media generale (1 = nella norma)
      double hs[24], hn[24], ts = 0.0, tn = 0.0;
      for(int h = 0; h < 24; h++) { hs[h] = 0.0; hn[h] = 0.0; g_hrVol[h] = 1.0; }
      for(int i = 0; i < g_n1; i++)
        {
         if(g_m1Time[i] < InpFrom || g_m1Time[i] > InpTo) continue;
         const int h = (int)(((((long)g_m1Time[i] + g_off) % 86400L) + 86400L) % 86400L / 3600L);
         const double v = g_m1Vcum[i + 1] - g_m1Vcum[i];
         hs[h] += v; hn[h] += 1.0; ts += v; tn += 1.0;
        }
      if(tn > 0.0 && ts > 0.0)
         for(int h = 0; h < 24; h++) g_hrVol[h] = (hn[h] > 0.0) ? (hs[h] / hn[h]) / (ts / tn) : 0.0;
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
   const int bkt = (int)g_m1Bkt[mp];
   for(int q = 0; q < nm; q++)
      for(int k = 0; k < mi; k++)
        {
         const int p = ((t * g_nMem + mem[q]) * g_nM + k) * NXF;
         g_nxb[p]     += 1.0;
         g_nxb[p + 1] += 0.5 * rg[k];
         g_nxb[p + 2] += 0.5 * rg[k];
         g_nxb[p + 3] += rg[k];
         g_nxb[p + 4] += MathAbs(mv[k]);
         if(mem[q] >= 1 && mem[q] < NMEM1)          // categorie non orarie: base anche per fascia, per abbinarla ai segnali
           {
            const int pb = ((((t * 19 + (mem[q] - 1)) * g_nB + bkt) * g_nM) + k) * 4;
            g_nxbb[pb]     += 1.0;
            g_nxbb[pb + 1] += 0.5 * rg[k];
            g_nxbb[pb + 2] += rg[k];
            g_nxbb[pb + 3] += MathAbs(mv[k]);
           }
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
            if(mem[q] >= 1 && mem[q] < NMEM1)
               g_nxsb[((((s * g_nT + t) * 19 + (mem[q] - 1)) * g_nB + bkt) * g_nM) + k]++;
           }
     }
  }

//+------------------------------------------------------------------+
//| Filtri dell'EA sulla barra i: 0 = superati, 1 = tolto dall'ADX,   |
//| 2 = tolto dal regime di volatilita' (adxv e vsc servono solo se   |
//| il rispettivo filtro e' attivo)                                   |
//+------------------------------------------------------------------+
int FiltCode(const double &adxv[], const uchar &vsc[], const int i)
  {
   if(g_adxFilt && !(adxv[i] >= InpAdxMin)) return 1;
   if(g_regFilt)
     {
      const int vcf = (i >= g_volWarm) ? (int)vsc[i] : 255;
      if(vcf == 255) return 2;
      if(((g_regMask >> ((vcf >> 1) & 3)) & 1) == 0) return 2;
      if(InpRequireVolRising && (vcf & 1) == 0) return 2;
     }
   return 0;
  }

//--- ritardo massimo fra l'apertura della barra successiva e la prima barra M1 disponibile: gli input per i TF normali; per W1 e MN1 l'apertura nominale
//--- cade nel weekend (W1 = domenica 00:00, un mese puo' iniziare di sabato) e il mercato riapre fino a un giorno dopo, quindi si accettano fino a 4 giorni
long EntryGapLimit(const int t)
  {
   if(g_tf[t] == PERIOD_MN1 || g_tfSec[t] >= 604800L) return 345600L;
   return (long)InpMaxEntryGapMin * 60L;
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
   if(InpUseVolState || g_regFilt || g_xfOn)
     {
      SD_VolState(r, n, g_vpar, g_pt, vsc);       // il warm-up dei segnali resta quello del segnale: lo stato ha il suo (g_volWarm)
     }
   uchar ibn[];
   SD_IntensityBins(r, n, g_vpar.atrLen, g_ibEdge, ibn);      // intensita' della candela del segnale (TR/ATR), anche senza stato di volatilita'
   double atrM[];
   if(g_atrOn) SD_Atr(r, n, MathMax(2, InpMgmtAtrLen), atrM);
   double adxv[];
   if(g_adxFilt || g_xfOn) SD_Adx(r, n, MathMax(1, InpAdxPeriod), adxv);
   int rejAdx = 0, rejReg = 0;

   const long   xs      = g_tfSec[t];
   const long   maxGap  = (long)InpMaxEntryGapMin * 60L;
   const long   maxEnt  = EntryGapLimit(t);
   const bool   slotOK  = g_slotOK[t];
   const bool   isMN    = (g_tf[t] == PERIOD_MN1);

   int need = g_used + n;
   ArrayResize(g_ent,  need, 2000000);
   ArrayResize(g_dir,  need, 2000000);
   ArrayResize(g_bur,  need, 2000000);
   ArrayResize(g_slot, need, 2000000);
   ArrayResize(g_vs,   need, 2000000);
   if(g_atrOn) ArrayResize(g_atr, need, 2000000);
   if(g_xfOn) { ArrayResize(g_adxq, need, 2000000); ArrayResize(g_reg, need, 2000000); }
   if(InpPeak) ArrayResize(g_ib, need, 2000000);
   if(g_nSets > 1) { ArrayResize(g_dirAlt, need, 2000000); ArrayResize(g_burAlt, need, 2000000); }

   int u = g_used, p = 0;
   int bars = 0, rejGap = 0, rejM1 = 0, rejWin = 0, ev = 0, ev2 = 0;
   for(int i = warm; i < n - 1; i++)
     {
      datetime tNext = r[i+1].time;
      if(tNext < InpFrom || tNext > InpTo) continue;
      bars++;
      long spacing = (long)(tNext - r[i].time);
      if(!isMN && (spacing - xs) > maxGap) { rejGap++; continue; }
      while(p < g_n1 && g_m1Time[p] < tNext) p++;
      if(p >= g_n1) break;
      if((long)(g_m1Time[p] - tNext) > maxEnt) { rejM1++; continue; }
      if(InSkipWin((long)g_m1Time[p])) { rejWin++; continue; }
      //--- filtri dell'EA: un segnale che non li supera e' come se l'EA non lo avesse visto (vale per tutte le tabelle)
      if((g_adxFilt || g_regFilt) && (dir[i] != 0 || (g_nSets > 1 && dir2[i] != 0)))
        {
         const int fc = FiltCode(adxv, vsc, i);
         if(fc != 0)
           {
            if(fc == 1) rejAdx++; else rejReg++;
            dir[i] = 0;
            if(g_nSets > 1) dir2[i] = 0;
           }
        }
      g_ent[u]  = p;
      g_dir[u]  = dir[i];
      g_bur[u]  = bur[i];
      if(g_nSets > 1) { g_dirAlt[u] = dir2[i]; g_burAlt[u] = bur2[i]; if(dir2[i] != 0) ev2++; }
      g_vs[u]   = InpUseVolState ? ((i >= g_volWarm) ? vsc[i] : (uchar)255) : (uchar)10;   // 255 = finestra del percentile incompleta
      g_slot[u] = (ushort)(slotOK ? (int)(((long)r[i].time % g_parentSec) / xs) : 0);
      if(g_atrOn) g_atr[u] = (i < ArraySize(atrM)) ? atrM[i] / g_pt : 0.0;
      if(InpPeak) g_ib[u] = ibn[i];
      if(g_xfOn)
        {
         g_adxq[u] = (uchar)MathMin(200.0, MathMax(0.0, MathFloor(((i < ArraySize(adxv)) ? adxv[i] : 0.0) * 2.0)));
         g_reg[u]  = (i >= g_volWarm) ? vsc[i] : (uchar)255;
        }
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
   g_tfRejWin[t] = rejWin;
   g_tfRejAdx[t] = rejAdx;
   g_tfRejReg[t] = rejReg;
   ArrayResize(g_ent,  g_used);
   ArrayResize(g_dir,  g_used);
   ArrayResize(g_bur,  g_used);
   ArrayResize(g_slot, g_used);
   ArrayResize(g_vs,   g_used);
   if(g_atrOn) ArrayResize(g_atr, g_used);
   if(g_xfOn) { ArrayResize(g_adxq, g_used); ArrayResize(g_reg, g_used); }
   if(InpPeak) ArrayResize(g_ib, g_used);
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
   g_plc = false;
   if(InpPlacebo)
     {
      const int szG = g_nT * g_nH * blk;
      if(ArrayResize(g_rkP, (int)szK) == (int)szK && ArrayResize(g_rgP, szG) == szG)
        {
         ArrayInitialize(g_rkP, 0.0);
         ArrayInitialize(g_rgP, 0.0);
         BuildPlcQ();
         g_plc = true;
        }
      else
        {
         Print("Memoria insufficiente per il placebo: disattivato.");
         ArrayFree(g_rkP);
         ArrayFree(g_rgP);
        }
     }
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

//--- il placebo mantiene la quota di acquisti dei segnali veri in ogni [TF][fascia][IS/OOS]: solo cosi' condivide con il segnale l'esposizione alla deriva
void BuildPlcQ()
  {
   const int nQ = g_nT * g_nRB * 2;
   double nb[], nt[];
   ArrayResize(g_plcQ, nQ); ArrayResize(nb, nQ); ArrayResize(nt, nQ);
   ArrayInitialize(nb, 0.0); ArrayInitialize(nt, 0.0);
   for(int t = 0; t < g_nT; t++)
      for(int k = g_tfOff[t]; k < g_tfOff[t] + g_tfCnt[t]; k++)
        {
         const int d = (int)g_dir[k];
         if(d == 0) continue;
         const int j  = g_ent[k] + InpEntryLagMin;
         if(j >= g_n1) continue;
         const int rb = (int)((((long)g_m1Time[j] + g_off) % 86400L) / ((long)g_rbMin * 60L));
         const int ix = (t * g_nRB + rb) * 2 + ((g_m1Day[j] >= g_splitDay) ? 1 : 0);
         nt[ix] += 1.0;
         if(d > 0) nb[ix] += 1.0;
        }
   for(int i = 0; i < nQ; i++) g_plcQ[i] = (nt[i] > 0.0) ? nb[i] / nt[i] : 0.5;
  }

//--- prodotto modulo 2^32 senza overflow (h e m < 2^32 : ogni addendo resta sotto 2^49)
long Mul32(const long h, const long m)
  {
   const long lo = h * (m & 65535);
   const long hi = (h * (m >> 16)) & 65535;
   return (lo + (hi << 16)) & 4294967295;
  }

//--- verso casuale deterministico (rimescolamento a 32 bit dell'indice M1 d'ingresso, solo aritmetica long mascherata) con probabilita' q di acquisto
int PlaceboDir(const int j, const double q)
  {
   long h = ((long)j + 1) & 4294967295;
   h = h ^ (h >> 16);
   h = Mul32(h, 2246822507);
   h = h ^ (h >> 13);
   h = Mul32(h, 3266489909);
   h = h ^ (h >> 16);
   const double u = (double)(h & 16777215) / 16777216.0;
   return (u < q) ? 1 : -1;
  }

//+------------------------------------------------------------------+
//| Ipotetica posizione: per ogni target (kk) e verso (dd) il risultato|
//| netto e': +target se il movimento favorevole NETTO raggiunge il   |
//| target entro la tenuta, altrimenti il rendimento netto a fine     |
//| tenuta. Nessuno stop. Valori gia' al netto del costo d'ingresso.  |
//+------------------------------------------------------------------+
//--- somme per separare TRE cose: pnl = M + s*D, dove s = verso della POSIZIONE (+1 lunga, -1 corta), D = (pnl se lungo - pnl se corto)/2 nello
//--- stesso istante e M = (pnl se lungo + pnl se corto)/2 = valore dell'ISTANTE per chi sceglie il verso a caso (rollover, spread, code di prezzo...).
//--- Media di D = deriva/dislocazione (il verso la sfrutta solo se i segnali sono sbilanciati); ABILITA' = covarianza fra s e D:
//--- un segnale senza informazione ha abilita' nulla (t attorno a 0) anche con M molto positivo e segnali sbilanciati.
void AddRank(double &a[], const int base, const int smp, const int d,
             const double mfeF, const double maeF, const double retF,
             const double mfeI, const double maeI, const double retI)
  {
   for(int kk = 0; kk <= g_nL; kk++)
     {
      const double lv = (kk == 0) ? 0.0 : g_lev[kk - 1];
      const double pF = (kk > 0 && mfeF >= lv) ? lv : retF;
      const double pI = (kk > 0 && mfeI >= lv) ? lv : retI;
      const double dl = 0.5 * ((d > 0) ? (pF - pI) : (pI - pF));
      for(int dd = 0; dd < 2; dd++)
        {
         const double mfe = (dd == 0) ? mfeF : mfeI;
         const double mae = (dd == 0) ? maeF : maeI;
         const double ret = (dd == 0) ? retF : retI;
         const bool   hit = (kk > 0 && mfe >= lv);
         const double pnl = hit ? lv : ret;
         const double sd  = (dd == 0) ? (double)d : -(double)d;
         const int p = base + (((kk * 2 + dd) * 2 + smp) * RKN);
         a[p]     += 1.0;
         a[p + 1] += pnl;
         a[p + 2] += pnl * pnl;
         if(hit) a[p + 3] += 1.0;
         a[p + 4] += mae;
         a[p + 5] += sd;
         a[p + 6] += dl;
         a[p + 7] += sd * dl;
         a[p + 8] += dl * dl;
         a[p + 9] += sd * dl * dl;
        }
     }
  }

struct RkStat
  {
   double n, mean, t, hit, mae, sum;
   double fl, dlt, mc, nm, nt;      // quota di posizioni lunghe, D medio, valore medio dell'istante M, abilita' della direzione (cov(s,D)) e suo t
  };

//--- t semplice della media da n, somma e somma dei quadrati (0 se n < 2 o varianza nulla)
double NaiveT(const double n, const double sum, const double sum2)
  {
   if(n < 2.0) return 0.0;
   const double mean = sum / n;
   const double var  = (sum2 - n * mean * mean) / (n - 1.0);
   return (var > 0.0) ? mean / (MathSqrt(var) / MathSqrt(n)) : 0.0;
  }

//--- t con errore standard raggruppato per giorno: n, media e le tre somme dei cluster (somma dei totali giornalieri al quadrato, somma totale x numero, somma dei numeri al quadrato)
double ClusterT(const double n, const double mean, const double a, const double b, const double c)
  {
   if(n < 2.0) return 0.0;
   const double v = a - 2.0 * mean * b + mean * mean * c;
   return (v > 0.0) ? mean / (MathSqrt(v) / n) : 0.0;
  }

void RkRead(const double &a[], const int base, const int kk, const int dd, const int smp, RkStat &s)
  {
   const int p = base + (((kk * 2 + dd) * 2 + smp) * RKN);
   double n = a[p];
   s.n = n; s.mean = 0.0; s.t = 0.0; s.hit = 0.0; s.mae = 0.0; s.sum = 0.0;
   s.fl = 0.5; s.dlt = 0.0; s.mc = 0.0; s.nm = 0.0; s.nt = 0.0;
   if(n < 1.0) return;
   s.sum  = a[p + 1];
   s.mean = a[p + 1] / n;
   s.t   = NaiveT(n, a[p + 1], a[p + 2]);
   s.hit = 100.0 * a[p + 3] / n;
   s.mae = a[p + 4] / n;
   //--- valore dell'istante e abilita' della direzione (vedi AddRank)
   const double sbar = a[p + 5] / n;
   const double msd  = a[p + 7] / n;                       // media di s*D
   s.fl  = 0.5 * (1.0 + sbar);
   s.dlt = a[p + 6] / n;
   s.mc  = s.mean - msd;                                   // M medio: cosa guadagna chi sceglie il verso a caso in quegli istanti
   s.nm  = msd - sbar * s.dlt;                             // abilita': covarianza fra il verso della posizione e D
   const double suu = (1.0 + sbar * sbar) * a[p + 8] - 2.0 * sbar * a[p + 9];     // somma di ((s - sbar)*D)^2
   const double vr  = (n > 1.0) ? (suu - n * s.nm * s.nm) / (n - 1.0) : 0.0;
   s.nt  = (vr > 0.0) ? s.nm / (MathSqrt(vr) / MathSqrt(n)) : 0.0;
  }

//--- statistiche sull'INTERO storico (in-sample + out-of-sample sommati)
void RkReadAll(const double &a[], const int base, const int kk, const int dd, RkStat &s)
  {
   const int p0 = base + (((kk * 2 + dd) * 2 + 0) * RKN);
   const int p1 = base + (((kk * 2 + dd) * 2 + 1) * RKN);
   double n = a[p0] + a[p1];
   s.n = n; s.mean = 0.0; s.t = 0.0; s.hit = 0.0; s.mae = 0.0; s.sum = 0.0;
   s.fl = 0.5; s.dlt = 0.0; s.mc = 0.0; s.nm = 0.0; s.nt = 0.0;
   if(n < 1.0) return;
   double sm = a[p0 + 1] + a[p1 + 1];
   double s2 = a[p0 + 2] + a[p1 + 2];
   s.sum  = sm;
   s.mean = sm / n;
   s.t   = NaiveT(n, sm, s2);
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
         const int j0 = g_ent[k];
         const int j  = j0 + InpEntryLagMin;
         if(InpEntryLagMin > 0 && (j >= g_n1 || (long)(g_m1Time[j] - g_m1Time[j0]) != (long)InpEntryLagMin * 60L)) continue;   // il ritardo non deve attraversare un buco di dati
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
         const double cost = ((InpCostPoints > 0.0) ? InpCostPoints : (double)g_m1Spr[j]) + g_extraPts;
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
          //--- placebo: stesso istante e stessa barra, verso casuale (se coincide con quello del segnale i valori sono gli stessi, altrimenti si scambiano)
          const int rb = (int)((((long)g_m1Time[j] + g_off) % 86400L) / ((long)g_rbMin * 60L));
          const int pd = g_plc ? PlaceboDir(j, g_plcQ[(t * g_nRB + rb) * 2 + smp]) : d;
          double pF = fav, pA = adv, pR = retG;
          if(g_plc && pd != d) { pF = adv; pA = fav; pR = -retG; }
          const double pmfeF = pF - cost, pmaeF = pA + cost, pretN = pR - cost;
          const double pmfeI = pA - cost, pmaeI = pF + cost, pretI = -pR - cost;
          if(g_lockG[cell] == 0 || (tj - g_lockG[cell]) >= Hs)
            {
             g_lockG[cell] = tj;
             AddRank(g_rg, cell * rkBlk, smp, d, mfeF, maeF, retN, mfeI, maeI, retI);
             if(g_plc) AddRank(g_rgP, cell * rkBlk, smp, pd, pmfeF, pmaeF, pretN, pmfeI, pmaeI, pretI);
            }
          const int lb = cell * g_nRB + rb;
          if(g_lockB[lb] == 0 || (tj - g_lockB[lb]) >= Hs)
            {
             g_lockB[lb] = tj;
             AddRank(g_rk, ((t * g_nRB + rb) * g_nH + hi) * rkBlk, smp, d, mfeF, maeF, retN, mfeI, maeI, retI);
             if(g_plc) AddRank(g_rkP, ((t * g_nRB + rb) * g_nH + hi) * rkBlk, smp, pd, pmfeF, pmaeF, pretN, pmfeI, pmaeI, pretI);
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
   s.tNaive = NaiveT(n, g_accTH[p + 3], g_accTH[p + 4]);

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
   double tn  = NaiveT(n, a[p + 3], a[p + 4]);
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

void RepSpread()
  {
   W("<h2>Spread M1 per fascia d'entrata</h2>");
   W("<div class='note'>Spread della barra M1 (punti) per fascia oraria (ora server + offset), su tutto il periodo. "
     "Il costo di ogni posizione &egrave; lo spread della barra M1 d'ingresso" + string(InpCostPoints > 0.0 ? " (qui sostituito dal costo fisso impostato)" : "") +
     ": una fascia con spread molto sopra la mediana generale (" + F0(g_medSpr) + " pt) rende fragile ogni guadagno netto trovato l&igrave;. "
     "Arancio = spread medio almeno 1.5 volte la mediana generale; rosso = almeno 2.5 volte. Se i dati storici hanno uno spread fisso o modellato, "
     "la tabella non mostra l'allargamento reale del broker: confrontala con lo spread che vedi sul conto.</div>");
   W("<table><tr><th>Fascia</th><th>Barre M1</th><th>Spread medio</th><th>Mediano</th><th>p90</th><th>Medio / mediana generale</th></tr>");
   for(int rb = 0; rb < g_nRB; rb++)
     {
      if(g_sprN[rb] <= 0.0) continue;
      const string col = SprColor(rb);
      W("<tr><td>" + RBktLabel(rb) + "</td>" + Td(F0(g_sprN[rb])) + Td("<b>" + F1(g_sprMean[rb]) + "</b>", col) + Td(F0(g_sprMed[rb])) +
        Td(F0(g_sprP90[rb])) + Td(F2(SprRatio(rb)), col) + "</tr>");
     }
   W("</table>");
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
   W("<tr><th>Costo</th><td>" + (InpCostPoints > 0.0 ? ("spread fisso " + F1(InpCostPoints) + " pt") : "spread reale M1") +
     " + extra " + F1(InpExtraCostPts) + " pt + commissione " + F1(g_commPts) + " pt (" + F2(InpCommissionPerLotSide) + " " + g_ccy + " per lato e per lotto, due lati)</td></tr>");
   W("<tr><th>Denaro</th><td>lotto ipotetico " + LotTxt() + " | 1 punto per 1.00 lotto = " + (g_pv > 0.0 ? (DoubleToString(g_pv, 4) + " " + g_ccy) : string("non disponibile")) +
     " | valuta del conto " + g_ccy + string(g_pvInfo != "" ? (" | " + g_pvInfo) : "") + " | verso nelle classifiche: " + string(InpRankSide == RS_FOLLOW ? "solo SEGUI" : (InpRankSide == RS_FADE ? "solo INVERTI" : "SEGUI e INVERTI")) +
     "</td></tr>");
   W("<tr><th>Finestre</th><td>buco dati massimo " + IS(InpMaxGapMin) + " min | gap massimo all'ingresso " +
     IS(InpMaxEntryGapMin) + " min | fasce da " + IS(g_bMin) + " min | offset orario " + IS(InpTimeOffsetH) + " h | ritardo d'ingresso " + IS(InpEntryLagMin) + " min | finestre d'ingresso escluse: " + (g_skN > 0 ? InpSkipEntryWin : string("nessuna")) + "</td></tr>");
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
   if(!g_money)
      W("<div class='note ko'><b>Colonne in denaro non disponibili.</b> " + g_pvInfo + ". La commissione " + string(g_commPts > 0.0 ? "&egrave; inclusa lo stesso nel costo." : "non &egrave; inclusa (lotto o commissione a zero).") + "</div>");
   else if(g_pvWarn)
      W("<div class='note ko'><b>Valore del punto stimato.</b> " + g_pvInfo + ". La commissione &egrave; inclusa nel costo con questa stima (" + F1(g_commPts) + " pt a/r): se il suo valore reale per il tuo conto &egrave; diverso, indica il simbolo reale in <b>InpPointValueSymbol</b> o il valore in <b>InpPointValuePerLot</b>.</div>");
   else if(g_commPts > 0.0)
      W("<div class='note'><b>Commissione inclusa automaticamente:</b> " + F2(InpCommissionPerLotSide) + " " + g_ccy + " per lato e per lotto = " + F1(g_commPts) + " pt andata e ritorno, sommati allo spread M1 reale in ogni risultato di questo report (valore del punto: " + g_pvInfo + ").</div>");
   if(g_commPts <= 0.0 && g_money)
      W("<div class='note ko'><b>Nessuna commissione inclusa</b> (InpCommissionPerLotSide = 0): su un conto Raw (FP Markets, IC Markets) i risultati sono ottimisti.</div>");

   if(g_filtTxt != "")
     {
      int tAdx = 0, tReg = 0;
      for(int t = 0; t < g_nT; t++) { tAdx += g_tfRejAdx[t]; tReg += g_tfRejReg[t]; }
      W("<div class='note'><b>Filtri dell'EA attivi:</b> " + g_filtTxt + ". I segnali che non li superano sono tolti da <b>tutte</b> le tabelle (come se l'EA non li avesse visti): " +
        "tolti dall'ADX " + IS(tAdx) + " e dal regime di volatilit&agrave; " + IS(tReg) + " (somma dei TF, barre con segnale in almeno una serie; l'ADX ha la precedenza sul regime). L'ADX &egrave; ricostruito dall'esempio ADX.mq5: il numero di segnali filtrati pu&ograve; non coincidere al 100% con quello dell'iADX dell'EA. La posizione nella raffica (Sequence Filter) &egrave; calcolata prima dei filtri.</div>");
     }
   W("<h2>Come leggere</h2>");
   W("<div class='note'><b>Netto medio</b> = rendimento a fine orizzonte nella direzione del segnale meno il costo, in punti. "
     "&Egrave; la metrica principale: senza informazione vale circa <b>&minus;costo</b> e non dipende dalla volatilit&agrave; (in media). "
     "<b>MFE</b> e <b>MAE</b> sono ampiezze massime: crescono con la volatilit&agrave; e con la radice dell'orizzonte, quindi un MFE grande da solo non &egrave; edge. "
     "Contano <b>MFE/MAE</b> (asimmetria dentro lo stesso evento) e il confronto con la <b>base</b> = entrate in direzione casuale, stesso TF, stessa fascia oraria.</div>");
   W("<div class='note'><b>t cluster</b> usa l'errore standard raggruppato per giorno: i segnali di barre vicine si sovrappongono, "
     "il t naive &egrave; gonfiato. Giallo = |t| &ge; 2 (debole, atteso per caso su 1 cella su 20). Verde/rosso = oltre la soglia di Bonferroni "
     "sul numero di celle TF x orizzonte di ciascuna serie (la soglia &egrave; scritta in testa alla serie). Non cercare la cella migliore: cerca coerenza fra orizzonti vicini e verifica su un periodo successivo; i TF vicini condividono gran parte dei segnali e non sono conferme indipendenti. "
     "Il t cluster &egrave; ottimista per orizzonti di un giorno o pi&ugrave;, perch&eacute; giorni adiacenti condividono parte del percorso del prezzo.</div>");
   W("<div class='note'>Tutte le tabelle con <b>t naive</b> o z del segno (fasce orarie, candela nel TF superiore, raffica, direzione, giorno, classifiche) "
     "non sono corrette per i test multipli (e quelle non a posizione singola nemmeno per la sovrapposizione): nelle colonne t e z il giallo significa solo |t| &ge; 2, mai verde o rosso; "
     "il verde/rosso dei netti indica solo il segno, e la colonna Esito (verdetto sull'out-of-sample) &egrave; l'unica eccezione. "
     "Nelle classifiche la posizione occupa il suo slot per tutta la tenuta anche se il target esce prima (scelta prudente).</div>");
   W("<div class='note'>Le misure sono <b>in punti</b>: i simboli non sono confrontabili fra loro e le ore con volatilit&agrave; alta dominano i totali. "
     "Per questo le tabelle orarie sono affiancate dalla base della stessa fascia.</div>");
   RepSpread();
  }

void RepCoverage()
  {
   W("<h2>Copertura per timeframe</h2>");
   W("<div class='note'>Un segnale viene scartato se tra la chiusura della barra e la barra successiva c'&egrave; una pausa di sessione "
     "oltre <b>" + IS(InpMaxEntryGapMin) + "</b> min (weekend, chiusura giornaliera): l'ingresso non sarebbe quello del segnale. "
     "Per D1, W1 e MN1 la pausa di sessione o il weekend pu&ograve; scartare una quota alta dei segnali (vedi le colonne sopra): aumenta <b>InpMaxEntryGapMin</b> se vuoi entrare comunque all'apertura successiva.</div>");
   W("<table><tr><th>TF</th><th>Barre in periodo</th><th>Scartate gap sessione</th><th>Senza M1</th><th>Escluse (finestre)</th><th>Tolti da ADX</th><th>Tolti da regime</th><th>Barre base</th>"
     "<th>Segnali</th><th>Misurati @" + IS(g_hor[g_refH]) + "m</th><th>% misurati</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      double nref = g_accTH[(t * g_nH + g_refH) * ACCN];
      double pc = (g_tfEv[t] > 0) ? 100.0 * nref / g_tfEv[t] : 0.0;
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(IS(g_tfBars[t])) + Td(IS(g_tfRejGap[t])) + Td(IS(g_tfRejM1[t])) + Td(IS(g_tfRejWin[t])) + Td(IS(g_tfRejAdx[t])) + Td(IS(g_tfRejReg[t])) +
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

   if(g_money)
     {
      W("<h2>Netto medio in " + g_ccy + " per posizione (lotto " + LotTxt() + ") per TF e orizzonte</h2>");
      W("<div class='note'>Entrando a ogni segnale nel suo verso e uscendo dopo l'orizzonte indicato (tempo fisso, senza stop), al netto di spread e commissione. "
        "Passando il mouse su una cella si vede dopo quante candele del TF si esce. Le posizioni si sovrappongono: &egrave; il risultato medio di un singolo segnale, non di un conto che apre una posizione alla volta.</div>");
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
            const string tip = " title='uscita dopo " + F1((double)g_hor[h] / MathMax(1.0, (double)g_tfSec[t] / 60.0)) + " candele; posizioni " + F0(s.n) + "'";
            W("<td style='color:" + ColT(s.tCl) + "'" + tip + ">" + Mny(s.ret) + "</td>");
           }
         W("</tr>");
        }
      W("</table>");
     }

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
        if(!SideOK(dd)) continue;
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
string KLabel(const int kk) { return (kk == 0) ? string("nessuno") : F0(g_lev[kk - 1]); }

string EsitoCell(const RkStat &a, const RkStat &b)
  {
   if(b.n < MathMax(10.0, g_minN / 3.0)) return Td("OOS scarso", "#4c566a");
   if(b.mean > 0.0 && b.t >= 2.0)             return (b.nm > 0.0 && b.nt >= 2.0) ? Td("<b>TIENE</b>", "#a3be8c") : Td("istante/deriva", "#d08770");
   if(b.mean > 0.0)                           return Td("debole", "#ebcb8b");
   return Td("NO", "#bf616a");
  }

string RankHead()
  {
   return "<table><tr><th>#</th><th>TF</th><th>Fascia (entrata, server + offset)</th><th>Verso</th><th>Tieni (min)</th><th>Candele TF</th><th>Target (pt)</th>"
          "<th>IS pos.</th><th>IS netto</th><th>IS t</th><th>Target raggiunto % (netto)</th>"
          "<th>OOS pos.</th><th>OOS netto</th><th>OOS netto (" + g_ccy + "/pos.)</th><th>OOS totale (" + g_ccy + ")</th><th>OOS t</th><th>OOS % lunghe</th><th>OOS valore istante (M)</th><th>OOS abilit&agrave; direzione</th><th>OOS t abilit&agrave;</th><th>Spread fascia (pt)</th><th>Esito</th></tr>";
  }

string RankRow(const int rank, const int t, const int rb, const int h, const int kk, const int dd)
  {
   const int base = ((t * g_nRB + rb) * g_nH + h) * ((g_nL + 1) * 4 * RKN);
   RkStat a, b;
   RkRead(g_rk, base, kk, dd, 0, a);
   RkRead(g_rk, base, kk, dd, 1, b);
   string hs = (kk == 0) ? "-" : F1(a.hit);
   return "<tr>" + Td(IS(rank)) + "<td>" + g_tfName[t] + "</td><td>" + RBktLabel(rb) + "</td>" +
          Td(dd == 0 ? "SEGUI" : "INVERTI") + Td(IS(g_hor[h])) + Td(F1((double)g_hor[h] / MathMax(1.0, (double)g_tfSec[t] / 60.0))) + Td(KLabel(kk)) +
          Td(F0(a.n)) + Td("<b>" + F1(a.mean) + "</b>", ColSign(a.mean)) + Td(F2(a.t)) + Td(hs) +
          Td(F0(b.n)) + Td("<b>" + F1(b.mean) + "</b>", ColSign(b.mean)) + Td(Mny(b.mean), ColSign(b.mean)) + Td(MnyT(b.mean * b.n), ColSign(b.mean)) + Td(F2(b.t), ColTNaive(b.t)) +
          Td(F0(100.0 * b.fl) + "%") + Td(F1(b.mc), ColSign(b.mc)) + Td(F1(b.nm), ColSign(b.nm)) + Td(F2(b.nt), ColTNaive(b.nt)) +
          Td(F1(g_sprMean[rb]), SprColor(rb)) + EsitoCell(a, b) + "</tr>";
  }

void RankDigest(const string tag, const int rank, const int t, const int rb, const int h, const int kk, const int dd)
  {
   const int base = ((t * g_nRB + rb) * g_nH + h) * ((g_nL + 1) * 4 * RKN);
   RkStat a, b;
   RkRead(g_rk, base, kk, dd, 0, a);
   RkRead(g_rk, base, kk, dd, 1, b);
   g_dg += tag + "|" + IS(rank) + "|" + g_tfName[t] + "|" + RBktLabel(rb) + "|" + (dd == 0 ? "SEGUI" : "INVERTI") +
           "|hold|" + IS(g_hor[h]) + "|tp|" + KLabel(kk) + "|isn|" + F0(a.n) + "|ismean|" + F1(a.mean) + "|ist|" + F2(a.t) +
           "|hit|" + (kk == 0 ? "-" : F1(a.hit)) + "|oosn|" + F0(b.n) + "|oosmean|" + F1(b.mean) + "|oost|" + F2(b.t) +
           "|ooslong|" + F0(100.0 * b.fl) + "|oosdelta|" + F1(b.dlt) + "|oosm|" + F1(b.mc) + "|oosskill|" + F1(b.nm) + "|oosskt|" + F2(b.nt) + "|candles|" + F1((double)g_hor[h] / MathMax(1.0, (double)g_tfSec[t] / 60.0)) +
           "|oosmny|" + Mny(b.mean) + "|oosmnytot|" + MnyT(b.mean * b.n) + "|spr|" + F1(g_sprMean[rb]) + "\n";
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
     + string(InpRankSide == RS_FOLLOW ? "Il verso studiato &egrave; solo SEGUI il segnale (InpRankSide)."
                                       : "&laquo;INVERTI&raquo; = fare l'opposto del segnale: &egrave; incluso perch&eacute; un trigger pu&ograve; contenere informazione dal lato sbagliato.") + "</div>");
   W("<table><tr><th>TF</th><th>Verso</th><th>Tieni (min)</th><th>Target (pt)</th><th>IS pos.</th><th>IS netto</th><th>IS t</th>"
     "<th>Target raggiunto % (netto)</th><th>OOS pos.</th><th>OOS netto</th><th>OOS netto (" + g_ccy + "/pos.)</th><th>OOS t</th><th>Esito</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      double bt = -1.0e9; int bh = -1, bk = -1, bd = -1;
      for(int h = 0; h < g_nH; h++)
         for(int kk = 0; kk <= g_nL; kk++)
            for(int dd = 0; dd < 2; dd++)
              {
                 if(!SideOK(dd)) continue;
               RkStat a;
               RkRead(g_rg, (t * g_nH + h) * blk, kk, dd, 0, a);
               if(a.n < g_minN) continue;
               if(a.t > bt) { bt = a.t; bh = h; bk = kk; bd = dd; }
              }
      const int ci = g_curSet * g_nT + t;
      g_cmpBoN[ci] = 0.0; g_cmpBoM[ci] = 0.0; g_cmpBoT[ci] = 0.0; g_cmpDesc[ci] = "-";
      if(bh < 0)
        { W("<tr class='thin'><td>" + g_tfName[t] + "</td><td colspan='12'>campione in-sample insufficiente</td></tr>"); continue; }
      RkStat a, b;
      RkRead(g_rg, (t * g_nH + bh) * blk, bk, bd, 0, a);
      RkRead(g_rg, (t * g_nH + bh) * blk, bk, bd, 1, b);
      g_cmpBoN[ci] = b.n; g_cmpBoM[ci] = b.mean; g_cmpBoT[ci] = b.t;
      g_cmpDesc[ci] = string(bd == 0 ? "SEGUI" : "INVERTI") + " " + IS(g_hor[bh]) + "m, TP " + KLabel(bk);
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(bd == 0 ? "SEGUI" : "INVERTI") + Td(IS(g_hor[bh])) + Td(KLabel(bk)) +
        Td(F0(a.n)) + Td("<b>" + F1(a.mean) + "</b>", ColSign(a.mean)) + Td(F2(a.t)) + Td(bk == 0 ? "-" : F1(a.hit)) +
        Td(F0(b.n)) + Td("<b>" + F1(b.mean) + "</b>", ColSign(b.mean)) + Td(Mny(b.mean), ColSign(b.mean)) + Td(F2(b.t), ColTNaive(b.t)) + EsitoCell(a, b) + "</tr>");
      g_dg += "BESTTF|" + g_tfName[t] + "|" + (bd == 0 ? "SEGUI" : "INVERTI") + "|hold|" + IS(g_hor[bh]) + "|tp|" + KLabel(bk) +
              "|isn|" + F0(a.n) + "|ismean|" + F1(a.mean) + "|ist|" + F2(a.t) + "|hit|" + (bk == 0 ? "-" : F1(a.hit)) +
              "|oosn|" + F0(b.n) + "|oosmean|" + F1(b.mean) + "|oost|" + F2(b.t) + "\n";
     }
   W("</table>");
  }

//--- statistiche della classifica A2 su un array di accumulatori (segnale reale o placebo): miglior t in-sample, e fra le prime
//--- le migliori combinazioni per t in-sample (pool ordinato) e quante restano positive o hanno t OOS >= 2 fuori campione: vale per il segnale reale e per il placebo
void RankPool(const double &arr[], double &pT[], int &pTf[], int &pB[], int &pH[], int &pK[], int &pD[], int &pn,
              double &bestT, int &usable, int &pos, int &strong, int &strongN, int &strongOne, long &m)
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   const int rankTop = MathMin(200, MathMax(1, InpRankTop));
   const int P = MathMax(300, rankTop * 5);
   ArrayResize(pT, P); ArrayResize(pTf, P); ArrayResize(pB, P);
   ArrayResize(pH, P); ArrayResize(pK, P);  ArrayResize(pD, P);
   pn = 0;
   m = 0; usable = 0; pos = 0; strong = 0; strongN = 0; strongOne = 0; bestT = 0.0;
   for(int t = 0; t < g_nT; t++)
      for(int rb = 0; rb < g_nRB; rb++)
         for(int h = 0; h < g_nH; h++)
           {
            const int base = ((t * g_nRB + rb) * g_nH + h) * blk;
            if(arr[base] < g_minN) continue;
            for(int kk = 0; kk <= g_nL; kk++)
               for(int dd = 0; dd < 2; dd++)
                 {
                  if(!SideOK(dd)) continue;
                  RkStat a;
                  RkRead(arr, base, kk, dd, 0, a);
                  m++;
                  int ps;
                  if(pn < P) { ps = pn; pn++; }
                  else
                    {
                     if(a.t <= pT[P - 1]) continue;
                     ps = P - 1;
                    }
                  while(ps > 0 && pT[ps - 1] < a.t)
                    {
                     pT[ps] = pT[ps - 1]; pTf[ps] = pTf[ps - 1]; pB[ps] = pB[ps - 1];
                     pH[ps] = pH[ps - 1]; pK[ps] = pK[ps - 1];   pD[ps] = pD[ps - 1];
                     ps--;
                    }
                  pT[ps] = a.t; pTf[ps] = t; pB[ps] = rb; pH[ps] = h; pK[ps] = kk; pD[ps] = dd;
                 }
           }
   if(pn < 1) return;
   bestT = pT[0];
   for(int i = 0; i < pn; i++)
     {
      RkStat b;
      RkRead(arr, ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk, pK[i], pD[i], 1, b);
      if(b.n < MathMax(10.0, g_minN / 3.0)) continue;
      usable++;
      if(b.mean > 0.0) pos++;
      if(b.mean > 0.0 && b.t >= 2.0) { strong++; if(b.fl <= 0.1 || b.fl >= 0.9) strongOne++; }     // strongOne: fasce in cui il segnale va quasi sempre nello stesso verso (abilita' non misurabile)
      if(b.mean > 0.0 && b.t >= 2.0 && b.nm > 0.0 && b.nt >= 2.0) strongN++;      // anche al netto di deriva e composizione BUY/SELL
     }
  }

//--- tabella A1: in quanti TF la miglior combinazione in-sample (su tutto il giorno) resta positiva fuori campione con t >= 2
int A1Count(const double &arr[])
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   int cnt = 0;
   for(int t = 0; t < g_nT; t++)
     {
      double bt = -1.0e9;
      int bh = -1, bk = -1, bd = -1;
      for(int h = 0; h < g_nH; h++)
         for(int kk = 0; kk <= g_nL; kk++)
            for(int dd = 0; dd < 2; dd++)
              {
                 if(!SideOK(dd)) continue;
               RkStat a;
               RkRead(arr, (t * g_nH + h) * blk, kk, dd, 0, a);
               if(a.n < g_minN) continue;
               if(a.t > bt) { bt = a.t; bh = h; bk = kk; bd = dd; }
              }
      if(bh < 0) continue;
      RkStat b;
      RkRead(arr, (t * g_nH + bh) * blk, bk, bd, 1, b);
      if(b.n >= MathMax(10.0, g_minN / 3.0) && b.mean > 0.0 && b.t >= 2.0 && b.nm > 0.0 && b.nt >= 2.0) cnt++;
     }
   return cnt;
  }

//+------------------------------------------------------------------+
//| PROVE DI STRESS                                                   |
//| Rifanno la stessa posizione ipotetica della classifica (entrata   |
//| sul segnale, uscita al target netto o dopo la tenuta, nessuno     |
//| stop, una per volta) ma con ingresso ritardato di N minuti e/o    |
//| costo maggiorato. Il ritardo non cambia l'insieme dei segnali: la |
//| fascia e' quella dell'ingresso senza ritardo. Richiedono che      |
//| ComputeForward(tenuta) sia stato eseguito.                        |
//+------------------------------------------------------------------+

//--- indice M1 d'ingresso con il ritardo globale InpEntryLagMin, come la classifica (-1 se attraversa un buco di dati)
int StressBase(const int k)
  {
   const int j0 = g_ent[k];
   const int jb = j0 + InpEntryLagMin;
   if(InpEntryLagMin > 0 && (jb >= g_n1 || (long)(g_m1Time[jb] - g_m1Time[j0]) != (long)InpEntryLagMin * 60L)) return -1;
   return jb;
  }

//--- indici dei segnali del TF la cui fascia d'ingresso (con il ritardo globale, senza quello di stress) e' rb
int StressCollect(const int t, const int rb, int &idx[])
  {
   const long rbSec = (long)g_rbMin * 60L;
   int cnt = 0;
   ArrayResize(idx, 0, 4096);
   const int k0 = g_tfOff[t];
   const int k1 = k0 + g_tfCnt[t];
   for(int k = k0; k < k1; k++)
     {
      if(g_dir[k] == 0) continue;
      const int j0 = StressBase(k);
      if(j0 < 0) continue;
      if((int)(((((long)g_m1Time[j0] + g_off) % 86400L) + 86400L) % 86400L / rbSec) != rb) continue;
      cnt++;
      ArrayResize(idx, cnt, 4096);
      idx[cnt - 1] = k;
     }
   return cnt;
  }

//--- st: [0..2] in-sample posizioni, somma, somma dei quadrati; [3..5] lo stesso fuori campione
void StressSim(const int &idx[], const int nIdx, const int h, const int kk, const int dd,
               const int lag, const double extra, const double sprMult, double &st[],
               const bool store, double &pnlOut[], int &dayOut[])
  {
   for(int q = 0; q < 6; q++) st[q] = 0.0;
   const long   Hs = (long)g_hor[h] * 60L;
   const double lv = (kk == 0) ? 0.0 : g_lev[kk - 1];
   long lockT = 0;
   for(int a = 0; a < nIdx; a++)
     {
      const int k  = idx[a];
      const int d  = (int)g_dir[k];
      const int j0 = StressBase(k);
      if(j0 < 0) continue;
      const int j  = j0 + lag;
      if(lag > 0 && (j >= g_n1 || (long)(g_m1Time[j] - g_m1Time[j0]) != (long)lag * 60L)) continue;
      if(g_ok[j] == 0) continue;
      const double o    = g_m1Open[j];
      const double mB   = (g_fHi[j] - o) / g_pt;
      const double mS   = (o - g_fLo[j]) / g_pt;
      const double fav  = (d > 0) ? mB : mS;
      const double adv  = (d > 0) ? mS : mB;
      const double retG = (d > 0) ? (g_fCl[j] - o) / g_pt : (o - g_fCl[j]) / g_pt;
      const double spr  = (InpCostPoints > 0.0) ? InpCostPoints : (double)g_m1Spr[j];
      const double cost = spr * sprMult + g_extraPts + extra;
      const long   tj   = (long)g_m1Time[j];
      if(lockT != 0 && (tj - lockT) < Hs) continue;
      lockT = tj;
      const double mfe = (dd == 0) ? (fav - cost) : (adv - cost);
      const double ret = (dd == 0) ? (retG - cost) : (-retG - cost);
      const double pnl = (kk > 0 && mfe >= lv) ? lv : ret;
      const int smp = (g_m1Day[j] >= g_splitDay) ? 1 : 0;
      st[smp * 3]     += 1.0;
      st[smp * 3 + 1] += pnl;
      st[smp * 3 + 2] += pnl * pnl;
      if(store)
        {
         const int c = ArraySize(pnlOut);
         ArrayResize(pnlOut, c + 1, 4096);
         ArrayResize(dayOut, c + 1, 4096);
         pnlOut[c] = pnl;
         dayOut[c] = g_m1Day[j];
        }
     }
  }

//--- tutti i segnali di un TF alla tenuta di riferimento, senza target e senza blocco: netto medio con ingresso ritardato e t raggruppato per giorno
void StressPop(const int t, const int lag, double &dayS[], double &dayN[], double &nOut, double &meanOut, double &tclOut)
  {
   ArrayInitialize(dayS, 0.0);
   ArrayInitialize(dayN, 0.0);
   double n = 0.0, sum = 0.0;
   const int k0 = g_tfOff[t];
   const int k1 = k0 + g_tfCnt[t];
   for(int k = k0; k < k1; k++)
     {
      const int d = (int)g_dir[k];
      if(d == 0) continue;
      const int j0 = StressBase(k);
      if(j0 < 0) continue;
      const int j  = j0 + lag;
      if(lag > 0 && (j >= g_n1 || (long)(g_m1Time[j] - g_m1Time[j0]) != (long)lag * 60L)) continue;
      if(g_ok[j] == 0) continue;
      const double o    = g_m1Open[j];
      const double retG = (d > 0) ? (g_fCl[j] - o) / g_pt : (o - g_fCl[j]) / g_pt;
      const double spr  = (InpCostPoints > 0.0) ? InpCostPoints : (double)g_m1Spr[j];
      const double retN = retG - spr - g_extraPts;
      const int day = g_m1Day[j];
      dayS[day] += retN;
      dayN[day] += 1.0;
      n += 1.0;
      sum += retN;
     }
   nOut = n;
   meanOut = (n > 0.0) ? sum / n : 0.0;
   double ss = 0.0;
   for(int dI = 0; dI < g_nDays; dI++)
      if(dayN[dI] > 0.0) { const double e = dayS[dI] - meanOut * dayN[dI]; ss += e * e; }
   tclOut = (n > 1.0 && ss > 0.0) ? meanOut / (MathSqrt(ss) / n) : 0.0;
  }

//--- punti senza decimali se interi (5), con un decimale altrimenti (2.5)
string PtLbl(const double v) { return (v == MathFloor(v)) ? F0(v) : F1(v); }

//--- anno di un giorno (giorni dal 1970.01.01)
int YearOfDay(const long z0)
  {
   const long z   = z0 + 719468L;
   const long era = ((z >= 0) ? z : z - 146096L) / 146097L;
   const long doe = z - era * 146097L;
   const long yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L;
   const long doy = doe - (365L * yoe + yoe / 4L - yoe / 100L);
   const long mp  = (5L * doy + 2L) / 153L;
   const long mo  = mp + ((mp < 10L) ? 3L : -9L);
   return (int)(yoe + era * 400L + ((mo <= 2L) ? 1L : 0L));
  }

//--- scheda di una regola: posizioni, vincenti, perdite, drawdown e risultato per anno (intero periodo, ingresso subito); restituisce il testo per il riepilogo
string RepCard(const int rank, const int t, const int rb, const int h, const int kk, const int dd)
  {
   int idx[];
   ComputeForward(g_hor[h]);
   const int nIdx = StressCollect(t, rb, idx);
   double st[6];
   double pnl[];
   int dayv[];
   ArrayResize(pnl, 0, 4096);
   ArrayResize(dayv, 0, 4096);
   StressSim(idx, nIdx, h, kk, dd, 0, 0.0, 1.0, st, true, pnl, dayv);
   const int n = ArraySize(pnl);
   if(n < 5) return "";
   double sum = 0.0, sumW = 0.0, sumL = 0.0, worst = 1.0e18, eq = 0.0, peak = 0.0, mdd = 0.0;
   int nW = 0, nL = 0, streak = 0, maxStreak = 0;
   int yMin = 100000, yMax = -100000;
   int yr[];
   ArrayResize(yr, n);
   for(int i = 0; i < n; i++)
     {
      const double x = pnl[i];
      sum += x;
      if(x > 0.0) { sumW += x; nW++; streak = 0; }
      else { sumL += x; nL++; streak++; if(streak > maxStreak) maxStreak = streak; }
      if(x < worst) worst = x;
      eq += x;
      if(eq > peak) peak = eq;
      if(peak - eq > mdd) mdd = peak - eq;
      yr[i] = YearOfDay(g_day0 + (long)dayv[i]);
      if(yr[i] < yMin) yMin = yr[i];
      if(yr[i] > yMax) yMax = yr[i];
     }
   const double avgW = (nW > 0) ? sumW / nW : 0.0;
   const double avgL = (nL > 0) ? sumL / nL : 0.0;
   const int ny = yMax - yMin + 1;
   double yN[], yW[], yS[], yWorst[];
   ArrayResize(yN, ny); ArrayResize(yW, ny); ArrayResize(yS, ny); ArrayResize(yWorst, ny);
   ArrayInitialize(yN, 0.0); ArrayInitialize(yW, 0.0); ArrayInitialize(yS, 0.0); ArrayInitialize(yWorst, 1.0e18);
   for(int i = 0; i < n; i++)
     {
      const int q = yr[i] - yMin;
      yN[q] += 1.0;
      if(pnl[i] > 0.0) yW[q] += 1.0;
      yS[q] += pnl[i];
      if(pnl[i] < yWorst[q]) yWorst[q] = pnl[i];
     }
   int yPos = 0, yUsed = 0;
   for(int q = 0; q < ny; q++) if(yN[q] > 0.0) { yUsed++; if(yS[q] > 0.0) yPos++; }
   const string desc = g_tfName[t] + " " + RBktLabel(rb) + " " + string(dd == 0 ? "SEGUI" : "INVERTI") + ", tieni " + IS(g_hor[h]) + " min, target " + KLabel(kk);
   W("<h3>4. Scheda della regola " + IS(rank) + ": " + desc + " (intero periodo, ingresso subito)</h3>");
   W("<div class='note'>Tutte le posizioni della regola, senza stop, in ordine di tempo: il drawdown &egrave; la massima perdita dal picco del profitto cumulato. "
     "Se il guadagno medio dipende da pochi anni o da una perdita rara molto grande, un EA con questa entrata e senza stop non &egrave; sostenibile. Swap e slippage non sono inclusi.</div>");
   W("<table><tr><th>Posizioni</th><th>Vincenti</th><th>Media (pt)</th><th>Media (" + g_ccy + ")</th><th>Vincita media (pt)</th><th>Perdita media (pt)</th><th>Rapporto vincita/perdita</th>"
     "<th>Peggiore posizione (pt)</th><th>Peggiore (" + g_ccy + ")</th><th>Drawdown massimo (pt)</th><th>Drawdown massimo (" + g_ccy + ")</th><th>Serie perdente massima</th><th>Totale (" + g_ccy + ")</th><th>Anni positivi</th></tr>");
   W("<tr>" + Td(IS(n)) + Td(F1(100.0 * nW / n) + "%") + Td(F1(sum / n), ColSign(sum)) + Td(Mny(sum / n), ColSign(sum)) + Td(F1(avgW)) + Td(F1(avgL)) +
     Td(avgL < 0.0 ? F2(avgW / -avgL) : string("-")) + Td(F1(worst), "#bf616a") + Td(Mny(worst), "#bf616a") + Td(F0(mdd)) + Td(MnyT(mdd)) + Td(IS(maxStreak)) +
     Td(MnyT(sum), ColSign(sum)) + Td(IS(yPos) + " su " + IS(yUsed)) + "</tr></table>");
   W("<table><tr><th>Anno</th><th>Posizioni</th><th>Vincenti</th><th>Netto (pt)</th><th>Netto (" + g_ccy + ")</th><th>Media (pt)</th><th>Peggiore posizione (pt)</th></tr>");
   for(int q = 0; q < ny; q++)
     {
      if(yN[q] < 1.0) continue;
      W("<tr>" + Td(IS(yMin + q)) + Td(F0(yN[q])) + Td(F1(100.0 * yW[q] / yN[q]) + "%") + Td(F0(yS[q]), ColSign(yS[q])) + Td(MnyT(yS[q]), ColSign(yS[q])) +
        Td(F1(yS[q] / yN[q]), ColSign(yS[q])) + Td(F0(yWorst[q]), "#bf616a") + "</tr>");
      g_dg += "CARDYEAR|" + IS(rank) + "|year|" + IS(yMin + q) + "|n|" + F0(yN[q]) + "|win|" + F1(100.0 * yW[q] / yN[q]) + "|sum|" + F0(yS[q]) + "|worst|" + F0(yWorst[q]) + "\n";
     }
   W("</table>");
   g_dg += "CARD|" + IS(rank) + "|" + desc + "|n|" + IS(n) + "|win|" + F1(100.0 * nW / n) + "|mean|" + F1(sum / n) + "|avgwin|" + F1(avgW) + "|avgloss|" + F1(avgL) +
           "|worst|" + F0(worst) + "|maxdd|" + F0(mdd) + "|maxstreak|" + IS(maxStreak) + "|yearspos|" + IS(yPos) + "|years|" + IS(yUsed) + "\n";
   return "Scheda della regola " + IS(rank) + " (intero periodo): " + IS(n) + " posizioni, " + F1(100.0 * nW / n) + "% vincenti, media " + Sg(sum / n) + " pt" +
          string(g_money ? (" (" + MnyU(sum / n) + ")") : "") + ", vincita media " + F1(avgW) + " pt contro perdita media " + F1(avgL) + " pt, peggiore posizione " + F0(worst) + " pt" +
          string(g_money ? (" (" + MnyU(worst) + ")") : "") + ", drawdown massimo " + F0(mdd) + " pt" + string(g_money ? (" (" + MnyTU(mdd) + ")") : "") + ", serie perdente massima " + IS(maxStreak) +
          ", anni positivi " + IS(yPos) + " su " + IS(yUsed) + ". ";
  }

string StressCell(const double mean, const double n, const double t)
  {
   if(n < 1.0) return "<td>-</td>";
   const string tip = (t > 1.0e8) ? (" title='posizioni " + F0(n) + "'") : (" title='posizioni " + F0(n) + ", t " + F2(t) + "'");
   return "<td style='color:" + ColSign(mean) + "'" + tip + ">" + F1(mean) + string(g_money ? (" (" + Mny(mean) + ")") : "") + "</td>";
  }

void RepStress(const int nr, int &rTf[], int &rB[], int &rH[], int &rK[], int &rD[], int &rS[])
  {
   g_cStress = "";
   if(!InpStress || g_nSlag < 1) return;
   const int OKLAG = 5;
   const int nLag = g_nSlag, nExt = g_nSext;
   const int blk  = (g_nL + 1) * 4 * RKN;
   const double minOos = MathMax(10.0, g_minN / 3.0);

   W("<h2>Prove di stress: entrare pi&ugrave; tardi e costi pi&ugrave; alti</h2>");
   W("<div class='note'>Le stesse posizioni ipotetiche della classifica, rifatte con <b>ingresso ritardato</b> di N minuti dopo la chiusura del segnale e con un <b>costo extra</b> in punti "
     "(sommato a spread e commissione). Se un risultato positivo sparisce con pochi minuti di ritardo o con pochi punti di costo era una dislocazione del prezzo d'ingresso o un'illusione di costo: non regge in un conto reale. "
     "Il ritardo non cambia l'insieme dei segnali (la fascia resta quella dell'ingresso senza ritardo). Valori in punti" + string(g_money ? (" e, fra parentesi, in " + g_ccy + " per posizione con " + LotTxt() + " lotti") : "") + ".</div>");
   if(g_fixedNote != "") W("<div class='note ko'>" + g_fixedNote + "</div>");

   //--- 1. tutti i segnali di ogni TF, alla tenuta di riferimento
   ComputeForward(g_hor[g_refH]);
   double dayS[], dayN[];
   ArrayResize(dayS, g_nDays);
   ArrayResize(dayN, g_nDays);
   double wN[], wS[], rowN[], rowM[], rowT[];
   ArrayResize(wN, nLag); ArrayResize(wS, nLag); ArrayInitialize(wN, 0.0); ArrayInitialize(wS, 0.0);
   ArrayResize(rowN, nLag); ArrayResize(rowM, nLag); ArrayResize(rowT, nLag);
   W("<h3>1. Seguire ogni segnale, uscita dopo " + IS(g_hor[g_refH]) + " min, con ingresso ritardato</h3>");
   W("<table><tr><th>TF</th><th>Segnali</th>");
   for(int li = 0; li < nLag; li++) W("<th>" + string(g_slag[li] == 0 ? "subito" : ("+" + IS(g_slag[li]) + " min")) + "</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      if(g_tfCnt[t] < 1) continue;
      for(int li = 0; li < nLag; li++) StressPop(t, g_slag[li], dayS, dayN, rowN[li], rowM[li], rowT[li]);
      if(rowN[0] < g_minN) continue;
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(F0(rowN[0])));
      for(int li = 0; li < nLag; li++)
        {
         W(StressCell(rowM[li], rowN[li], rowT[li]));
         wN[li] += rowN[li];
         wS[li] += rowN[li] * rowM[li];
         g_dg += "STRESSPOP|" + g_tfName[t] + "|lag|" + IS(g_slag[li]) + "|n|" + F0(rowN[li]) + "|mean|" + F1(rowM[li]) + "|tcl|" + F2(rowT[li]) + "\n";
        }
      W("</tr>");
     }
   W("<tr><td><b>Media pesata</b></td>" + Td(F0(wN[0])));
   for(int li = 0; li < nLag; li++)
     {
      const double wm = (wN[li] > 0.0) ? wS[li] / wN[li] : 0.0;
      W(StressCell(wm, wN[li], 1.0e9));
     }
   W("</tr></table>");
   if(nr < 1) return;
   //--- media pesata al ritardo di riferimento (il massimo ritardo non oltre OKLAG minuti)
   int liRef = 0;
   for(int li = 0; li < nLag; li++) if(g_slag[li] <= OKLAG) liRef = li;
   const double popM0   = (wN[0] > 0.0) ? wS[0] / wN[0] : 0.0;
   const double popMRef = (wN[liRef] > 0.0) ? wS[liRef] / wN[liRef] : 0.0;

   //--- 2. regole della classifica: ritardo e costi
   const int nCost = nExt + 1;                       // l'ultima colonna e' lo spread raddoppiato
   double lagM[], lagN[], lagT[], cM[], cN[], cT[];
   ArrayResize(lagM, nr * nLag); ArrayResize(lagN, nr * nLag); ArrayResize(lagT, nr * nLag);
   ArrayResize(cM, nr * nCost);  ArrayResize(cN, nr * nCost);  ArrayResize(cT, nr * nCost);
   bool done[];
   ArrayResize(done, nr);
   ArrayInitialize(done, false);
   double st[6];
   int idx[];
   double noP[];
   int noD[];
   for(int a = 0; a < nr; a++)
     {
      if(done[a]) continue;
      const int h = rH[a];
      ComputeForward(g_hor[h]);
      for(int b = a; b < nr; b++)
        {
         if(done[b] || rH[b] != h) continue;
         done[b] = true;
         const int nIdx = StressCollect(rTf[b], rB[b], idx);
         for(int li = 0; li < nLag; li++)
           {
            StressSim(idx, nIdx, h, rK[b], rD[b], g_slag[li], 0.0, 1.0, st, false, noP, noD);
            lagN[b * nLag + li] = st[3];
            lagM[b * nLag + li] = (st[3] > 0.0) ? st[4] / st[3] : 0.0;
            lagT[b * nLag + li] = NaiveT(st[3], st[4], st[5]);
           }
         for(int ci = 0; ci < nCost; ci++)
           {
            StressSim(idx, nIdx, h, rK[b], rD[b], 0, (ci < nExt) ? g_sext[ci] : 0.0, (ci < nExt) ? 1.0 : 2.0, st, false, noP, noD);
            cN[b * nCost + ci] = st[3];
            cM[b * nCost + ci] = (st[3] > 0.0) ? st[4] / st[3] : 0.0;
            cT[b * nCost + ci] = NaiveT(st[3], st[4], st[5]);
           }
         //--- controllo di coerenza: senza ritardo e senza extra la simulazione deve riprodurre la classifica
         StressSim(idx, nIdx, h, rK[b], rD[b], 0, 0.0, 1.0, st, false, noP, noD);
         RkStat chk;
         RkRead(g_rk, ((rTf[b] * g_nRB + rB[b]) * g_nH + h) * blk, rK[b], rD[b], 1, chk);
         if(MathAbs(chk.n - st[3]) > 0.5 || MathAbs(chk.sum - st[4]) > 1.0e-6 * MathMax(1.0, MathAbs(chk.sum)))
            Print("!!! Stress: la regola ", g_tfName[rTf[b]], " ", RBktLabel(rB[b]), " non coincide con la classifica (OOS ", F0(chk.n), " contro ", F0(st[3]), " posizioni)");
        }
     }

   //--- esiti
   int ciRef = nExt - 1;                              // costo extra di riferimento: il primo >= 10 punti, altrimenti l'ultimo
   for(int ci = 0; ci < nExt; ci++) if(g_sext[ci] >= 10.0) { ciRef = ci; break; }
   int nLagOk = 0, nCostOk = 0, nBoth = 0, nSurv = 0, nUse = 0;
   int vLag[], vCost[];
   ArrayResize(vLag, nr);
   ArrayResize(vCost, nr);
   bool hasShortS = false;                            // la prova del ritardo e' valutabile solo se fra i ritardi c'e' almeno un valore da 1 a OKLAG minuti
   for(int li = 0; li < nLag; li++) if(g_slag[li] >= 1 && g_slag[li] <= OKLAG) hasShortS = true;
   for(int b = 0; b < nr; b++)
     {
      if(rS[b] == 1) nSurv++;
      vLag[b] = 0; vCost[b] = 0;
      if(lagN[b * nLag] < minOos) { vLag[b] = -1; vCost[b] = -1; continue; }
      nUse++;
      bool lagPos = (lagM[b * nLag] > 0.0);
      for(int li = 0; li < nLag; li++) if(g_slag[li] > 0 && g_slag[li] <= OKLAG && lagM[b * nLag + li] <= 0.0) lagPos = false;
      const bool costPos = (cM[b * nCost] > 0.0 && cM[b * nCost + ciRef] > 0.0);
      const bool sig0 = (lagT[b * nLag] >= 2.0);        // senza ritardo il netto fuori campione deve essere gia' significativo (t >= 2): altrimenti positivo per caso
      vLag[b]  = !hasShortS ? -2 : (lagPos ? (sig0 ? 1 : 2) : 0);
      vCost[b] = costPos ? (sig0 ? 1 : 2) : 0;
      if(vLag[b] == 1) nLagOk++;
      if(vCost[b] == 1) nCostOk++;
      if(vLag[b] == 1 && vCost[b] == 1) nBoth++;
     }

   //--- tabella ritardo
   W("<h3>2. Le regole della classifica con ingresso ritardato (fuori campione, netto per posizione)</h3>");
   W("<table><tr><th>#</th><th>TF</th><th>Fascia</th><th>Verso</th><th>Tieni (min)</th><th>Target (pt)</th><th>Origine</th><th>OOS pos.</th>");
   for(int li = 0; li < nLag; li++) W("<th>" + string(g_slag[li] == 0 ? "subito" : ("+" + IS(g_slag[li]) + " min")) + "</th>");
   W("<th>Esito (REGGE = netto positivo con ritardo fino a " + IS(OKLAG) + " min e t &ge; 2 senza ritardo)</th></tr>");
   for(int b = 0; b < nr; b++)
     {
      W("<tr>" + Td(IS(b + 1)) + "<td>" + g_tfName[rTf[b]] + "</td><td>" + RBktLabel(rB[b]) + "</td>" + Td(rD[b] == 0 ? "SEGUI" : "INVERTI") +
        Td(IS(g_hor[rH[b]])) + Td(KLabel(rK[b])) + Td(rS[b] == 2 ? "regola fissa (nessuna selezione)" : (rS[b] == 1 ? "regge fuori campione" : "migliore in-sample")) + Td(F0(lagN[b * nLag])));
      for(int li = 0; li < nLag; li++)
        {
         W(StressCell(lagM[b * nLag + li], lagN[b * nLag + li], lagT[b * nLag + li]));
         g_dg += "STRESSLAG|" + IS(b + 1) + "|" + g_tfName[rTf[b]] + "|" + RBktLabel(rB[b]) + "|" + string(rD[b] == 0 ? "SEGUI" : "INVERTI") + "|hold|" + IS(g_hor[rH[b]]) +
                 "|tp|" + KLabel(rK[b]) + "|lag|" + IS(g_slag[li]) + "|oosn|" + F0(lagN[b * nLag + li]) + "|oosmean|" + F1(lagM[b * nLag + li]) + "|oost|" + F2(lagT[b * nLag + li]) + "\n";
        }
      W(vLag[b] == -2 ? Td("n.d. (nessun ritardo da 1 a " + IS(OKLAG) + " min provato)", "#4c566a") : (vLag[b] < 0 ? Td("OOS scarso", "#4c566a") : (vLag[b] == 1 ? Td("<b>REGGE</b>", "#a3be8c") : (vLag[b] == 2 ? Td("positiva, non significativa", "#ebcb8b") : Td("CADE", "#bf616a")))));
      W("</tr>");
     }
   W("</table>");

   //--- tabella costi
   W("<h3>3. Le stesse regole con costi pi&ugrave; alti, senza ritardo (fuori campione, netto per posizione)</h3>");
   W("<table><tr><th>#</th><th>TF</th><th>Fascia</th><th>Verso</th><th>Tieni (min)</th><th>Target (pt)</th>");
   for(int ci = 0; ci < nExt; ci++) W("<th>" + string(g_sext[ci] == 0.0 ? "costo attuale" : ("+" + PtLbl(g_sext[ci]) + " pt")) + "</th>");
   W("<th>Spread x2</th><th>Extra che azzera il netto</th><th>Esito (REGGE = netto positivo con +" + PtLbl(g_sext[ciRef]) + " pt e t &ge; 2 senza extra)</th></tr>");
   for(int b = 0; b < nr; b++)
     {
      W("<tr>" + Td(IS(b + 1)) + "<td>" + g_tfName[rTf[b]] + "</td><td>" + RBktLabel(rB[b]) + "</td>" + Td(rD[b] == 0 ? "SEGUI" : "INVERTI") +
        Td(IS(g_hor[rH[b]])) + Td(KLabel(rK[b])));
      for(int ci = 0; ci < nCost; ci++)
        {
         W(StressCell(cM[b * nCost + ci], cN[b * nCost + ci], cT[b * nCost + ci]));
         g_dg += "STRESSCOST|" + IS(b + 1) + "|" + g_tfName[rTf[b]] + "|" + RBktLabel(rB[b]) + "|" + string(rD[b] == 0 ? "SEGUI" : "INVERTI") + "|hold|" + IS(g_hor[rH[b]]) +
                 "|tp|" + KLabel(rK[b]) + "|extra|" + string(ci < nExt ? PtLbl(g_sext[ci]) : "spreadx2") + "|oosn|" + F0(cN[b * nCost + ci]) + "|oosmean|" + F1(cM[b * nCost + ci]) + "|oost|" + F2(cT[b * nCost + ci]) + "\n";
        }
      //--- extra che azzera il netto: interpolazione lineare fra i costi provati
      string be = "-";
      if(cN[b * nCost] >= minOos)
        {
         if(cM[b * nCost] <= 0.0) be = "nessuno";
         else
           {
            be = "oltre " + PtLbl(g_sext[nExt - 1]) + " pt";
            for(int ci = 1; ci < nExt; ci++)
               if(cM[b * nCost + ci] <= 0.0)
                 {
                  const double m0 = cM[b * nCost + ci - 1], m1 = cM[b * nCost + ci];
                  be = "circa " + F1(g_sext[ci - 1] + m0 / (m0 - m1) * (g_sext[ci] - g_sext[ci - 1])) + " pt";
                  break;
                 }
           }
        }
      W(Td(be));
      W(vCost[b] < 0 ? Td("OOS scarso", "#4c566a") : (vCost[b] == 1 ? Td("<b>REGGE</b>", "#a3be8c") : (vCost[b] == 2 ? Td("positiva, non significativa", "#ebcb8b") : Td("CADE", "#bf616a"))));
      W("</tr>");
     }
   W("</table>");

   //--- schede delle prime regole
   string cardTxt = "";
   const int nCard = MathMin(3, nr);
   for(int b = 0; b < nCard; b++)
     {
      const string ct = RepCard(b + 1, rTf[b], rB[b], rH[b], rK[b], rD[b]);
      if(b == 0) cardTxt = ct;
     }

   //--- testo per il riepilogo
   string bothTx = "";                                // regole che superano sia la prova del ritardo sia quella del costo
   for(int b = 0; b < nr; b++)
      if(vLag[b] == 1 && vCost[b] == 1)
         bothTx += string(bothTx != "" ? "; " : "") + g_tfName[rTf[b]] + " " + RBktLabel(rB[b]) + " " + string(rD[b] == 0 ? "SEGUI" : "INVERTI") + ", tieni " + IS(g_hor[rH[b]]) + " min, target " + KLabel(rK[b]);
   string sOrig;
   if(nSurv == 0)       sOrig = (rS[0] == 2 && nr == 1) ? string("solo la regola fissa, nessuna selezione") :
                                (string(rS[0] == 2 ? "oltre alla regola fissa " : "") + "nessuna regge fuori campione, sono le migliori in-sample");
   else if(nSurv >= nr) sOrig = (nr == 1) ? "la regola regge fuori campione" : "tutte reggono fuori campione";
   else                 sOrig = string(nSurv == 1 ? "una regge" : (IS(nSurv) + " reggono")) + " fuori campione, le altre sono fra le migliori in-sample";
   string tx = string(rS[0] == 2 ? "La prima e' la regola fissa impostata (nessuna selezione sui dati: un solo test). " : "") +
               "Regole in prova: " + IS(nr) + " (fuori campione): " + sOrig + ". ";
   if(nUse == 0)
      tx += "Campione fuori campione troppo scarso per valutarle. ";
   else if(!hasShortS)
      tx += "La prova del ritardo non e' valutabile: InpStressLags non contiene ritardi da 1 a " + IS(OKLAG) + " min; con " + PtLbl(g_sext[ciRef]) + " pt di costo in piu' il netto fuori campione resta positivo e significativo (t >= 2 senza ritardo) in " + IS(nCostOk) + " su " + IS(nUse) + string(nUse == 1 ? " regola" : " regole") + ". ";
   else
      tx += "Con ingresso ritardato fino a " + IS(OKLAG) + " min il netto fuori campione resta positivo e significativo (t >= 2 senza ritardo) in " + IS(nLagOk) + " su " + IS(nUse) + string(nUse == 1 ? " regola" : " regole") + "; con " + PtLbl(g_sext[ciRef]) +
            " pt di costo in piu' in " + IS(nCostOk) + "; superano entrambe le prove: " + IS(nBoth) + string(nBoth > 0 ? (" (" + bothTx + "; candidate da confermare, non conferme: la regola e' stata scelta guardando i dati)") : "") + ". ";
   {
    string ds = g_tfName[rTf[0]] + " " + RBktLabel(rB[0]) + " " + string(rD[0] == 0 ? "SEGUI" : "INVERTI") + ", tieni " + IS(g_hor[rH[0]]) + " min, target " + KLabel(rK[0]);
    tx += "La prima (" + ds + "): netto fuori campione";
    for(int li = 0; li < nLag; li++)
       if(g_slag[li] == 0 || g_slag[li] == OKLAG || li == nLag - 1)
          tx += string(g_slag[li] == 0 ? " subito " : (" con " + IS(g_slag[li]) + " min di ritardo ")) + Sg(lagM[li]) + " pt" + string(g_money ? (" (" + MnyU(lagM[li]) + ")") : "") + ",";
    tx += " con " + PtLbl(g_sext[ciRef]) + " pt di costo in piu' " + Sg(cM[ciRef]) + " pt. ";
   }
   tx += "Seguendo ogni segnale (media pesata dei TF, uscita dopo " + IS(g_hor[g_refH]) + " min) il netto medio e' " + Sg(popM0) + " pt subito" +
         string(g_slag[liRef] > 0 ? (" e " + Sg(popMRef) + " pt con " + IS(g_slag[liRef]) + " min di ritardo" + string(g_money ? (" (" + MnyU(popMRef) + " a posizione con " + LotTxt() + " lotti)") : "")) : "") + ". ";
   tx += "Una regola che non regge a pochi minuti di ritardo o a pochi punti di costo non e' operabile in un conto reale. " + cardTxt;
   g_cStress = tx;
  }

//+------------------------------------------------------------------+
//| GESTIONE SIMULATA                                                 |
//| Per ogni segnale simula una posizione aperta all'open d'ingresso  |
//| con stop iniziale, trailing e take profit (in multipli dell'ATR   |
//| del TF del segnale oppure in punti fissi) e con una durata        |
//| massima (tutti gli orizzonti insieme), rifatta anche entrando N   |
//| minuti piu' tardi (tutti i ritardi insieme): misura i punti presi |
//| in media per segnale, lordi e netti dei costi. Percorso sulle     |
//| barre M1; dentro la barra, se non e' scelto altro, lo stop usa il |
//| minimo prima del massimo (ordine intrabarra sconosciuto: neutro;  |
//| con InpMgmtHighFirst il limite pessimistico per il trailing).     |
//+------------------------------------------------------------------+
#define MGF 5            // campi per cella: n, netto, netto^2, lordo, uscite prima della durata (stop o target)
int     g_mgTf[];        // TF simulati (indici in g_tfName)
double  g_mgSl[], g_mgTr[], g_mgTp[];
int     g_mgLag[];       // ritardi d'ingresso in minuti (il primo e' sempre 0)
int     g_mgNtf = 0, g_mgNsl = 0, g_mgNtr = 0, g_mgNtp = 0, g_mgR = 0, g_mgNlag = 0;
int     g_mgNv = 1;      // varianti di unita': 1 = solo la principale; 2 = anche punti fissi pari ai multipli dell'ATR mediano del TF (InpMgmtFixedVar)
int     g_mgRv = 0;      // gestioni per variante (stop x trailing x take profit); le regole sono variante * g_mgRv + indice nella variante
double  g_mgMed[];       // ATR mediano (punti) sul primo periodo per TF simulato: unita' della variante a punti fissi
int     g_mgAct[];       // appoggio di MgSim: regole ancora aperte
double  g_mgAcc[];       // [TF simulato][fascia][regola][orizzonte][IS/OOS][MGF], solo ritardo 0
double  g_mgLg[];        // [ritardo][TF simulato][regola][orizzonte][IS/OOS][MGF], senza fascia
double  g_mgCl[];        // somme per il t raggruppato per giorno: [ritardo][TF simulato][regola][orizzonte][IS/OOS][3]
int     g_mgUsed[];      // segnali simulati per TF (ritardo 0)
int     g_mgSeen[];      // segnali del TF prima del campionamento
string  g_mgSvg[];       // curva cumulata per TF simulato (SVG), vuota se non calcolata
string  g_mgSelTab[];    // tabella HTML delle celle scelte per TF simulato
string  g_mgSelTop[];    // le prime celle scelte per TF simulato, in testo per il riepilogo

struct MgSelRes
  {
   bool   ok;
   int    nElig, nSel;
   double isN, isMean;             // in-sample, celle scelte (il netto e' gonfiato dalla scelta)
   double allN, allMean, allT;     // fuori campione, tutti i segnali
   double selN, selMean, selT;     // fuori campione, celle scelte
   int    selDays;                 // giorni distinti fuori campione con almeno un segnale nelle celle scelte
   double pct;                     // % delle scelte casuali (stesso numero di celle) battute dalla scelta; -1 se non calcolabile
  };

//--- elenco di TF (ALL = tutti, M1 compresa solo con allowM1, oppure nomi separati da virgola) come indici in g_tfName; in ignored i nomi non validi
int ParseTfSel(const string src0, int &out[], string &ignored, const bool allowM1 = false)
  {
   ArrayResize(out, 0);
   ignored = "";
   string src = src0;
   StringTrimLeft(src); StringTrimRight(src); StringToUpper(src);
   if(src == "ALL" || src == "")
     {
      for(int t = 0; t < g_nT; t++)
        {
         if(g_tf[t] == PERIOD_M1 && !allowM1) continue;
         const int k = ArraySize(out);
         ArrayResize(out, k + 1);
         out[k] = t;
        }
      return ArraySize(out);
     }
   string parts[];
   const int np = StringSplit(src, ',', parts);
   for(int q = 0; q < np; q++)
     {
      string pp = parts[q];
      StringTrimLeft(pp); StringTrimRight(pp);
      if(pp == "") continue;
      bool found = false;
      for(int t = 0; t < g_nT; t++) if(g_tfName[t] == pp) found = true;
      if(!found) ignored += string(ignored != "" ? ", " : "") + pp;
      for(int t = 0; t < g_nT; t++)
         if(g_tfName[t] == pp)
           {
            if(g_tf[t] == PERIOD_M1 && !allowM1) { ignored += string(ignored != "" ? ", " : "") + "M1 (non supportato)"; continue; }
            bool dup = false;
            for(int w = 0; w < ArraySize(out); w++) if(out[w] == t) dup = true;
            if(dup) continue;
            const int k = ArraySize(out);
            ArrayResize(out, k + 1);
            out[k] = t;
           }
     }
   return ArraySize(out);
  }

//--- TF da simulare (InpMgmtTFs: ALL oppure elenco), griglie di stop, trailing e take profit, ritardi
void MgmtSetup()
  {
   string ign;
   ParseTfSel(InpMgmtTFs, g_mgTf, ign, true);
   if(ign != "") Print("InpMgmtTFs: TF ignorati perche' non analizzati in InpTFs: ", ign);
   g_mgNtf = ArraySize(g_mgTf);
   const double mx = InpMgmtPoints ? 100000.0 : 50.0;
   g_mgNsl = ParseDoubleList(InpMgmtSlAtr, g_mgSl);
   if(g_mgNsl > 8) { Print("InpMgmtSlAtr: usati solo i primi 8 valori (i piu' piccoli)."); ArrayResize(g_mgSl, 8); g_mgNsl = 8; }
   g_mgNtr = ParseNonNegList(InpMgmtTrailAtr, g_mgTr, 6, mx);
   g_mgNtp = ParseNonNegList(InpMgmtTpAtr, g_mgTp, 4, mx);
   g_mgRv  = g_mgNsl * g_mgNtr * g_mgNtp;
   g_mgNv  = (InpMgmtFixedVar && !InpMgmtPoints) ? 2 : 1;
   g_mgR   = g_mgRv * g_mgNv;
   g_mgNlag = ParseLagList(InpMgmtLags, 8, g_mgLag);
  }

//--- regola r = variante * g_mgRv + (stop, trailing, take profit): indici delle tre griglie e variante (0 = unita' principale, 1 = punti fissi)
void MgRuleParts(const int r, int &isl, int &itr, int &itp, int &v)
  {
   v = r / g_mgRv;
   const int r0 = r % g_mgRv;
   itp = r0 % g_mgNtp;
   itr = (r0 / g_mgNtp) % g_mgNtr;
   isl = r0 / (g_mgNtp * g_mgNtr);
  }

//--- unita' di una regola per un segnale con ATR 'atr' (punti) sul TF simulato m: ATR del momento, punti (1), oppure ATR mediano del TF (punti fissi)
double MgRuleUnit(const int v, const double atr, const int m)
  {
   if(InpMgmtPoints) return 1.0;
   return (v == 0) ? atr : g_mgMed[m];
  }

//--- primo indice >= from con tempo >= tEnd (g_n1 se non esiste)
int MgLower(const long tEnd, const int from)
  {
   int lo = from, hi = g_n1;
   while(lo < hi)
     {
      const int mid = (lo + hi) / 2;
      if((long)g_m1Time[mid] < tEnd) lo = mid + 1; else hi = mid;
     }
   return lo;
  }

//--- indici nelle somme per ritardo e per il t raggruppato
int MgLgIx(const int l, const int m, const int r, const int c, const int s)
  {
   return ((((l * g_mgNtf + m) * g_mgR + r) * g_nH + c) * 2 + s) * MGF;
  }

int MgClIx(const int l, const int m, const int r, const int c, const int s)
  {
   return ((((l * g_mgNtf + m) * g_mgR + r) * g_nH + c) * 2 + s) * 3;
  }

//--- svuota la somma giornaliera di una cella nelle somme per il t raggruppato
void MgFlush(const int l, const int m, const int r, const int c, const int cx, const int &curSmp[], double &curS[], double &curN[])
  {
   if(curN[cx] <= 0.0) return;
   const int p = MgClIx(l, m, r, c, curSmp[cx]);
   g_mgCl[p]     += curS[cx] * curS[cx];
   g_mgCl[p + 1] += curS[cx] * curN[cx];
   g_mgCl[p + 2] += curN[cx] * curN[cx];
   curS[cx] = 0.0;
   curN[cx] = 0.0;
  }

//+------------------------------------------------------------------+
//| Percorso di una posizione per ognuna delle nR regole, dalla barra |
//| M1 j nel verso d. ur[r] = unita' della regola r in punti (ATR del |
//| segnale, 1 in modo punti, ATR mediano del TF per i punti fissi).  |
//| Riempie gr[r*nC+c] = punti lordi alla durata c e ex[r*nC+c] = 1   |
//| se la posizione e' uscita prima della durata (solo per le durate  |
//| valide okc[c]). Ordine dentro la barra M1: vedi InpMgmtHighFirst; |
//| se stop e target cadono nella stessa barra vale l'ordine scelto   |
//| (di default prima il minimo, cioe' lo stop). Si scorrono solo le  |
//| regole ancora aperte (risultato identico, piu' veloce).           |
//+------------------------------------------------------------------+
void MgSim(const int j, const int d, const double &ur[], const int eLast, const int nR, const int nC,
           const bool &okc[], const int &recBar[], const double &slp[], const double &trd[], const double &tpd[],
           double &S[], double &HW[], double &exitP[], bool &opn[], double &gr[], uchar &ex[])
  {
   const double pt = g_pt;
   const double o = g_m1Open[j];
   if(ArraySize(g_mgAct) < nR) ArrayResize(g_mgAct, nR);
   int na = nR;
   for(int r = 0; r < nR; r++) { S[r] = -slp[r] * ur[r]; HW[r] = 0.0; opn[r] = true; exitP[r] = 0.0; g_mgAct[r] = r; }
   int nc = 0;
   double fc = 0.0;
   for(int b = j; b < eLast; b++)
     {
      const double hi = g_m1High[b], lo = g_m1Low[b], op = g_m1Open[b], cl = g_m1Close[b];
      double fh, fl, fo;
      if(d > 0) { fh = (hi - o) / pt; fl = (lo - o) / pt; fo = (op - o) / pt; fc = (cl - o) / pt; }
      else      { fh = (o - lo) / pt; fl = (o - hi) / pt; fo = (o - op) / pt; fc = (o - cl) / pt; }
      int a = 0;
      while(a < na)
        {
         const int r = g_mgAct[a];
         const double tr = trd[r] * ur[r];
         const double tp = tpd[r] * ur[r];
         const double sOpen = S[r];                       // stop in vigore all'apertura della barra
         bool closed = false;
         if(fo <= sOpen) { exitP[r] = fo; closed = true; }                       // apertura gia' oltre lo stop o il target in vigore: si esce all'open, qualunque sia l'ordine intrabarra
         else if(tp > 0.0 && fo >= tp) { exitP[r] = fo; closed = true; }
         else if(InpMgmtHighFirst)
           {
            //--- prima il massimo: il target e il trailing vedono il massimo, poi lo stop (eventualmente alzato) vede il minimo
            if(tp > 0.0 && fh >= tp) { exitP[r] = tp; closed = true; }
            else
              {
               if(fh > HW[r]) HW[r] = fh;
               if(tr > 0.0 && HW[r] >= tr && HW[r] - tr > S[r]) S[r] = HW[r] - tr;
               if(fl <= S[r]) { exitP[r] = S[r]; closed = true; }                // colpito scendendo dal massimo: eseguito allo stop, non all'open
              }
           }
         else
           {
            //--- prima il minimo: lo stop in vigore all'apertura e' testato per primo
            if(fl <= sOpen) { exitP[r] = sOpen; closed = true; }
            else
              {
               if(fh > HW[r]) HW[r] = fh;
               if(tr > 0.0 && HW[r] >= tr && HW[r] - tr > S[r]) S[r] = HW[r] - tr;
               if(tp > 0.0 && fh >= tp) { exitP[r] = tp; closed = true; }
              }
           }
         if(closed)
           {
            opn[r] = false;
            na--;
            g_mgAct[a] = g_mgAct[na];                     // l'ordine di scorrimento non conta: le regole sono indipendenti
           }
         else
            a++;
        }
      while(nc < nC)
        {
         if(!okc[nc]) { nc++; continue; }
         if(recBar[nc] > b) break;
         for(int r = 0; r < nR; r++)
           {
            gr[r * nC + nc] = opn[r] ? fc : exitP[r];
            ex[r * nC + nc] = opn[r] ? (uchar)0 : (uchar)1;
           }
         nc++;
        }
      if(na == 0) break;
     }
   //--- tutte le posizioni chiuse prima della fine: gli orizzonti restanti hanno il risultato dell'uscita
   while(nc < nC)
     {
      if(okc[nc])
         for(int r = 0; r < nR; r++)
           {
            gr[r * nC + nc] = exitP[r];
            ex[r * nC + nc] = (uchar)1;
           }
      nc++;
     }
  }

//--- orizzonti validi (okc), barra di registrazione (recBar) e ultima barra da percorrere per un ingresso alla barra M1 j; -1 se nessuno e' valido
int MgHorizons(const int j, const int nC, bool &okc[], int &recBar[])
  {
   const long t0 = (long)g_m1Time[j];
   int eLast = -1;
   for(int c = 0; c < nC; c++)
     {
      const long tEnd = t0 + (long)g_hor[c] * 60L;
      const int e = MgLower(tEnd, j);
      okc[c] = (e < g_n1 && e > j && (g_nextBrk[j] >= e || (g_nextBrk[j] == e - 1 && (long)g_m1Time[e - 1] + 60L >= tEnd)));
      recBar[c] = e - 1;
      if(okc[c] && e > eLast) eLast = e;
     }
   return eLast;
  }

//--- ingresso ritardato di 'lg' minuti rispetto alla barra jb; -1 se attraversa un buco di dati o la fine dello storico
int MgLagBar(const int jb, const int lg)
  {
   if(lg <= 0) return jb;
   const int j = jb + lg;
   if(j >= g_n1 || (long)(g_m1Time[j] - g_m1Time[jb]) != (long)lg * 60L) return -1;
   return j;
  }

bool MgmtCompute()
  {
   const int nM = g_mgNtf, nC = g_nH, R = g_mgR, nLag = g_mgNlag;
   const long szAccL = (long)nM * g_nRB * R * nC * 2 * MGF;
   const long szLgL  = (long)nLag * nM * R * nC * 2 * MGF;
   const long szClL  = (long)nLag * nM * R * nC * 2 * 3;
   bool okMem = (szAccL + szLgL + szClL < 300000000L);          // 300 milioni di double = 2.4 GB al massimo (predefiniti: circa 12 milioni)
   if(okMem) okMem = (ArrayResize(g_mgAcc, (int)szAccL) == (int)szAccL && ArrayResize(g_mgLg, (int)szLgL) == (int)szLgL && ArrayResize(g_mgCl, (int)szClL) == (int)szClL);
   if(!okMem)
     {
      ArrayFree(g_mgAcc); ArrayFree(g_mgLg); ArrayFree(g_mgCl);
      Print("!!! Gestione simulata: memoria insufficiente per ", szAccL, " + ", szLgL, " celle. Riduci i TF (InpMgmtTFs), le griglie (InpMgmtSlAtr, InpMgmtTrailAtr, InpMgmtTpAtr), gli orizzonti o i ritardi (InpMgmtLags).");
      return false;
     }
   ArrayInitialize(g_mgAcc, 0.0);
   ArrayInitialize(g_mgLg, 0.0);
   ArrayInitialize(g_mgCl, 0.0);
   ArrayResize(g_mgUsed, nM);
   ArrayInitialize(g_mgUsed, 0);
   ArrayResize(g_mgSeen, nM);
   ArrayInitialize(g_mgSeen, 0);
   ArrayResize(g_mgSvg, nM);
   ArrayResize(g_mgSelTab, nM);
   ArrayResize(g_mgSelTop, nM);
   for(int q = 0; q < nM; q++) { g_mgSvg[q] = ""; g_mgSelTab[q] = ""; g_mgSelTop[q] = ""; }
   double slp[], trd[], tpd[], ur[], S[], HW[], exitP[], gr[];
   bool opn[], okc[];
   int recBar[];
   uchar ex[];
   ArrayResize(slp, R); ArrayResize(trd, R); ArrayResize(tpd, R); ArrayResize(ur, R); ArrayResize(S, R); ArrayResize(HW, R); ArrayResize(exitP, R);
   ArrayResize(opn, R); ArrayResize(okc, nC); ArrayResize(recBar, nC);
   ArrayResize(gr, R * nC); ArrayResize(ex, R * nC);
   for(int rr = 0; rr < R; rr++)
     {
      int isl, itr, itp, vv;
      MgRuleParts(rr, isl, itr, itp, vv);
      slp[rr] = g_mgSl[isl];
      trd[rr] = g_mgTr[itr];
      tpd[rr] = g_mgTp[itp];
     }
   //--- unita' dei punti fissi: ATR mediano di ogni TF sui segnali del primo periodo (se sono pochi, su tutti)
   ArrayResize(g_mgMed, nM);
   for(int m = 0; m < nM; m++)
     {
      g_mgMed[m] = 0.0;
      if(g_mgNv < 2) continue;
      const int t = g_mgTf[m];
      double av[];
      ArrayResize(av, 0, 4096);
      for(int pass = 0; pass < 2 && ArraySize(av) < 20; pass++)
        {
         ArrayResize(av, 0, 4096);
         for(int k = g_tfOff[t]; k < g_tfOff[t] + g_tfCnt[t]; k++)
           {
            if(g_dir[k] == 0 || g_atr[k] <= 0.0) continue;
            if(pass == 0)
              {
               const int jb0 = StressBase(k);
               if(jb0 < 0 || g_m1Day[jb0] >= g_splitDay) continue;
              }
            const int na = ArraySize(av);
            ArrayResize(av, na + 1, 4096);
            av[na] = g_atr[k];
           }
        }
      if(ArraySize(av) >= 1) g_mgMed[m] = MedianOf(av, ArraySize(av));
     }
   int curSmp[];
   double curS[], curN[];
   int curDay[];
   const int nCur = nLag * R * nC;
   ArrayResize(curSmp, nCur); ArrayResize(curS, nCur); ArrayResize(curN, nCur); ArrayResize(curDay, nCur);
   const long rbSec = (long)g_rbMin * 60L;
   for(int m = 0; m < nM; m++)
     {
      const int t = g_mgTf[m];
      if(IsStopped()) return false;
      Comment("SignalLab MultiTF: gestione simulata ", g_tfName[t], " (", m + 1, "/", nM, ")");
      ArrayInitialize(curS, 0.0); ArrayInitialize(curN, 0.0); ArrayInitialize(curDay, -1); ArrayInitialize(curSmp, 0);
      int nSig = 0;
      for(int k = g_tfOff[t]; k < g_tfOff[t] + g_tfCnt[t]; k++) if(g_dir[k] != 0) nSig++;
      const long capSig = (InpMgmtMaxSignals > 0) ? (long)InpMgmtMaxSignals : 2147483647L;
      const int stride = MathMax(1, (int)(((long)nSig + capSig - 1L) / capSig));
      int seen = 0, used = 0;
      for(int k = g_tfOff[t]; k < g_tfOff[t] + g_tfCnt[t]; k++)
        {
         const int d = (int)g_dir[k];
         if(d == 0) continue;
         seen++;
         if(((seen - 1) % stride) != 0) continue;
         const double atr = g_atr[k];
         if(atr <= 0.0) continue;
         const int jb = StressBase(k);
         if(jb < 0) continue;
         for(int rr = 0; rr < R; rr++) ur[rr] = MgRuleUnit(rr / g_mgRv, atr, m);
         const int smp = (g_m1Day[jb] >= g_splitDay) ? 1 : 0;
         const int day = g_m1Day[jb];
         const int rb = (int)(((((long)g_m1Time[jb] + g_off) % 86400L) + 86400L) % 86400L / rbSec);
         const int base = ((m * g_nRB + rb) * R);
         for(int l = 0; l < nLag; l++)
           {
            const int j = MgLagBar(jb, g_mgLag[l]);
            if(j < 0) continue;
            const int eLast = MgHorizons(j, nC, okc, recBar);
            if(eLast < 0) continue;
            if(l == 0) used++;
            const double cost = ((InpCostPoints > 0.0) ? InpCostPoints : (double)g_m1Spr[j]) + g_extraPts;
            MgSim(j, d, ur, eLast, R, nC, okc, recBar, slp, trd, tpd, S, HW, exitP, opn, gr, ex);
            for(int nc = 0; nc < nC; nc++)
              {
               if(!okc[nc]) continue;
               for(int r = 0; r < R; r++)
                 {
                  const int ix = r * nC + nc;
                  const double gv = gr[ix];
                  const double nt = gv - cost;
                  const int pl = MgLgIx(l, m, r, nc, smp);
                  g_mgLg[pl]     += 1.0;
                  g_mgLg[pl + 1] += nt;
                  g_mgLg[pl + 2] += nt * nt;
                  g_mgLg[pl + 3] += gv;
                  if(ex[ix] != 0) g_mgLg[pl + 4] += 1.0;
                  if(l == 0)
                    {
                     const int p = (((base + r) * nC + nc) * 2 + smp) * MGF;
                     g_mgAcc[p]     += 1.0;
                     g_mgAcc[p + 1] += nt;
                     g_mgAcc[p + 2] += nt * nt;
                     g_mgAcc[p + 3] += gv;
                     if(ex[ix] != 0) g_mgAcc[p + 4] += 1.0;
                    }
                  const int cx = (l * R + r) * nC + nc;
                  if(curDay[cx] != day) { MgFlush(l, m, r, nc, cx, curSmp, curS, curN); curDay[cx] = day; curSmp[cx] = smp; }
                  curS[cx] += nt;
                  curN[cx] += 1.0;
                 }
              }
           }
        }
      for(int l = 0; l < nLag; l++)
         for(int r = 0; r < R; r++)
            for(int c = 0; c < nC; c++) MgFlush(l, m, r, c, (l * R + r) * nC + c, curSmp, curS, curN);
      g_mgUsed[m] = used;
      g_mgSeen[m] = nSig;
     }
   Comment("");
   return true;
  }

//--- somme di una cella (ritardo, TF simulato, regola, orizzonte); smpSel -1 = tutto, 0 = in-sample, 1 = fuori campione
void MgSum(const int l, const int m, const int r, const int c, const int smpSel, double &n, double &sn, double &sn2, double &sg, double &ss)
  {
   n = 0.0; sn = 0.0; sn2 = 0.0; sg = 0.0; ss = 0.0;
   for(int s = 0; s < 2; s++)
     {
      if(smpSel >= 0 && s != smpSel) continue;
      const int p = MgLgIx(l, m, r, c, s);
      n += g_mgLg[p]; sn += g_mgLg[p + 1]; sn2 += g_mgLg[p + 2]; sg += g_mgLg[p + 3]; ss += g_mgLg[p + 4];
     }
  }

//--- t del netto medio con errore standard raggruppato per giorno (i segnali dello stesso giorno condividono il percorso del prezzo)
double MgClT(const int l, const int m, const int r, const int c, const int smpSel)
  {
   double n, sn, sn2, sg, ss;
   MgSum(l, m, r, c, smpSel, n, sn, sn2, sg, ss);
   if(n < 2.0) return 0.0;
   const double mu = sn / n;
   double a = 0.0, b = 0.0, cc = 0.0;
   for(int s = 0; s < 2; s++)
     {
      if(smpSel >= 0 && s != smpSel) continue;
      const int p = MgClIx(l, m, r, c, s);
      a += g_mgCl[p]; b += g_mgCl[p + 1]; cc += g_mgCl[p + 2];
     }
   return ClusterT(n, mu, a, b, cc);
  }

//--- numero di una griglia con al massimo due decimali, senza zeri finali (0.25, 1.5, 120)
string GridLbl(const double v)
  {
   if(v == MathFloor(v)) return F0(v);
   string tx = DoubleToString(v, 2);
   if(StringSubstr(tx, StringLen(tx) - 1, 1) == "0") tx = StringSubstr(tx, 0, StringLen(tx) - 1);
   return tx;
  }

//--- "1 cella" / "3 celle"
string Pl(const long n, const string one, const string many)
  {
   return IS(n) + " " + string(n == 1 ? one : many);
  }

//--- etichette delle regole (la scomposizione e l'unita' sono sopra MgLower)
string MgRuleLbl(const int r, const int m = -1)
  {
   int isl, itr, itp, v;
   MgRuleParts(r, isl, itr, itp, v);
   const bool fx = (!InpMgmtPoints && v == 1);
   const string u = InpMgmtPoints ? " pt" : (fx ? " ATR mediano" : " ATR");
   const bool pn = (fx && m >= 0 && m < ArraySize(g_mgMed) && g_mgMed[m] > 0.0);
   string tx = "SL " + GridLbl(g_mgSl[isl]) + u + string(pn ? (" (" + F0(g_mgSl[isl] * g_mgMed[m]) + " pt)") : "") + ", ";
   tx += (g_mgTr[itr] > 0.0) ? ("trailing " + GridLbl(g_mgTr[itr]) + u + string(pn ? (" (" + F0(g_mgTr[itr] * g_mgMed[m]) + " pt)") : "")) : string("senza trailing");
   tx += (g_mgTp[itp] > 0.0) ? (", TP " + GridLbl(g_mgTp[itp]) + u + string(pn ? (" (" + F0(g_mgTp[itp] * g_mgMed[m]) + " pt)") : "")) : string(", senza target");
   return tx;
  }

string MgRuleDg(const int r, const int m = -1)
  {
   int isl, itr, itp, v;
   MgRuleParts(r, isl, itr, itp, v);
   return "sl|" + GridLbl(g_mgSl[isl]) + "|trail|" + GridLbl(g_mgTr[itr]) + "|tp|" + GridLbl(g_mgTp[itp]) + "|unit|" + string(InpMgmtPoints ? "pt" : (v == 0 ? "atr" : "atrmed")) +
          string((!InpMgmtPoints && v == 1 && m >= 0 && m < ArraySize(g_mgMed)) ? ("|medpt|" + DoubleToString(g_mgMed[m], 4)) : "");
  }

string MgCapLbl(const int c, const int t)
  {
   const double cn = (double)g_hor[c] / MathMax(1.0, (double)g_tfSec[t] / 60.0);
   return IS(g_hor[c]) + " min (" + string(cn < 1.0 ? "meno di 1 candela" : (F1(cn) + " candele")) + ")";
  }

//--- soglia con 2-3 decimali senza zeri finali inutili (0.15, 0.125)
string ThrLbl(const double v)
  {
   string tx = DoubleToString(v, 3);
   if(StringSubstr(tx, StringLen(tx) - 1, 1) == "0") tx = StringSubstr(tx, 0, StringLen(tx) - 1);
   return tx;
  }

//--- elenco di interi separati da virgola, con un valore da sommare a ciascuno
string MgIntList(const int &a[], const int n, const int add = 0)
  {
   string tx = "";
   for(int i = 0; i < n; i++) tx += string(i > 0 ? ", " : "") + IS(a[i] + add);
   return tx;
  }

string MgDblList(const double &a[], const int n)
  {
   string tx = "";
   for(int i = 0; i < n; i++) tx += string(i > 0 ? ", " : "") + ThrLbl(a[i]);
   return tx;
  }

//--- ritardi d'ingresso provati, in minuti dalla chiusura del segnale (con il ritardo di base)
string MgLagTotList() { return MgIntList(g_mgLag, g_mgNlag, InpEntryLagMin); }

//--- giorno della settimana (0 = domenica) e ora (0-23) di un istante, in ora server + offset
int MgDow(const long tsec)
  {
   return (int)((((tsec + g_off) / 86400L) + 4L) % 7L);
  }

int MgHour(const long tsec)
  {
   return (int)(((((tsec + g_off) % 86400L) + 86400L) % 86400L) / 3600L);
  }

string MgCellLbl(const int cell)
  {
   const int dw = cell / 24, hr = cell % 24;
   return StringSubstr("DomLunMarMerGioVenSab", dw * 3, 3) + " " + string(hr < 10 ? "0" : "") + IS(hr) + ":00";
  }

//--- curva cumulata (SVG): tutti i segnali contro le celle scelte in-sample; la linea tratteggiata separa in-sample e fuori campione
string MgSvgCurve(const double &ya[], const double &ys[], const int np, const int splitPt)
  {
   if(np < 2) return "";
   double lo = 0.0, hi = 0.0;
   for(int i = 0; i < np; i++)
     {
      lo = MathMin(lo, MathMin(ya[i], ys[i]));
      hi = MathMax(hi, MathMax(ya[i], ys[i]));
     }
   if(hi - lo < 1.0e-9) hi = lo + 1.0;
   const double pl = 56.0, pr = 8.0, pt0 = 8.0, pb = 22.0;
   const double pw = 640.0 - pl - pr, ph = 220.0 - pt0 - pb;
   string pa = "", ps = "";
   for(int i = 0; i < np; i++)
     {
      const double x = pl + pw * (double)i / (double)(np - 1);
      pa += DoubleToString(x, 1) + "," + DoubleToString(pt0 + ph * (hi - ya[i]) / (hi - lo), 1) + " ";
      ps += DoubleToString(x, 1) + "," + DoubleToString(pt0 + ph * (hi - ys[i]) / (hi - lo), 1) + " ";
     }
   const double y0 = pt0 + ph * hi / (hi - lo);
   string sv = "<svg viewBox='0 0 640 220' width='100%' style='max-width:700px;background:#2e3440;border-radius:6px'>";
   sv += "<line x1='" + DoubleToString(pl, 0) + "' y1='" + DoubleToString(y0, 1) + "' x2='" + DoubleToString(pl + pw, 0) + "' y2='" + DoubleToString(y0, 1) + "' stroke='#4c566a'/>";
   if(splitPt > 0 && splitPt < np - 1)
     {
      const double xs = pl + pw * (double)splitPt / (double)(np - 1);
      sv += "<line x1='" + DoubleToString(xs, 1) + "' y1='" + DoubleToString(pt0, 0) + "' x2='" + DoubleToString(xs, 1) + "' y2='" + DoubleToString(pt0 + ph, 0) + "' stroke='#ebcb8b' stroke-dasharray='4 3'/>";
      sv += "<text x='" + DoubleToString(xs + 4.0, 1) + "' y='" + DoubleToString(pt0 + 10.0, 0) + "' fill='#ebcb8b' font-size='10'>fuori campione</text>";
     }
   sv += "<polyline fill='none' stroke='#88c0d0' stroke-width='1.5' points='" + pa + "'/>";
   sv += "<polyline fill='none' stroke='#a3be8c' stroke-width='1.5' points='" + ps + "'/>";
   sv += "<text x='2' y='" + DoubleToString(pt0 + 8.0, 0) + "' fill='#d8dee9' font-size='10'>" + F0(hi) + " pt</text>";
   sv += "<text x='2' y='" + DoubleToString(pt0 + ph, 0) + "' fill='#d8dee9' font-size='10'>" + F0(lo) + " pt</text>";
   sv += "<text x='60' y='216' fill='#88c0d0' font-size='10'>tutti i segnali</text><text x='170' y='216' fill='#a3be8c' font-size='10'>solo le celle scelte in-sample</text>";
   sv += "</svg>";
   return sv;
  }

//+------------------------------------------------------------------+
//| Risultato per segnale della gestione 'bRule' con durata 'bCap' su  |
//| un TF simulato (ritardo 0, stesso campione della passata           |
//| principale): netto in punti, giorno, cella ora x giorno della      |
//| settimana, periodo (0 = in-sample, 1 = fuori campione), ADX (mezzi |
//| punti) e stato di volatilita' della barra del segnale. Serve alla  |
//| selezione di orari e giorni e alla scansione dei filtri.           |
//+------------------------------------------------------------------+
int MgCollect(const int m, const int bRule, const int bCap, double &rNet[], int &rDay[], uchar &rCell[], uchar &rSmp[], uchar &rAdx[], uchar &rReg[])
  {
   const int t = g_mgTf[m];
   int isl, itr, itp, bv;
   MgRuleParts(bRule, isl, itr, itp, bv);
   double slp[], trd[], tpd[], ur[], S[], HW[], exitP[], gr[];
   bool opn[], okc[];
   int recBar[];
   uchar ex[];
   ArrayResize(slp, 1); ArrayResize(trd, 1); ArrayResize(tpd, 1); ArrayResize(ur, 1); ArrayResize(S, 1); ArrayResize(HW, 1); ArrayResize(exitP, 1);
   ArrayResize(opn, 1); ArrayResize(okc, 1); ArrayResize(recBar, 1); ArrayResize(gr, 1); ArrayResize(ex, 1);
   slp[0] = g_mgSl[isl]; trd[0] = g_mgTr[itr]; tpd[0] = g_mgTp[itp];
   ArrayResize(rNet, 0, 4096); ArrayResize(rDay, 0, 4096); ArrayResize(rCell, 0, 4096); ArrayResize(rSmp, 0, 4096); ArrayResize(rAdx, 0, 4096); ArrayResize(rReg, 0, 4096);
   //--- stesso campione della passata principale
   int nSig = 0;
   for(int k = g_tfOff[t]; k < g_tfOff[t] + g_tfCnt[t]; k++) if(g_dir[k] != 0) nSig++;
   const long capSig = (InpMgmtMaxSignals > 0) ? (long)InpMgmtMaxSignals : 2147483647L;
   const int stride = MathMax(1, (int)(((long)nSig + capSig - 1L) / capSig));
   int seen = 0;
   int nRec = 0;
   const bool haveFs = (InpFilterScan && ArraySize(g_adxq) >= g_tfOff[t] + g_tfCnt[t]);
   for(int k = g_tfOff[t]; k < g_tfOff[t] + g_tfCnt[t]; k++)
     {
      const int d = (int)g_dir[k];
      if(d == 0) continue;
      seen++;
      if(((seen - 1) % stride) != 0) continue;
      const double atr = g_atr[k];
      if(atr <= 0.0) continue;
      const int j = StressBase(k);
      if(j < 0) continue;
      const long tEnd = (long)g_m1Time[j] + (long)g_hor[bCap] * 60L;
      const int e = MgLower(tEnd, j);
      okc[0] = (e < g_n1 && e > j && (g_nextBrk[j] >= e || (g_nextBrk[j] == e - 1 && (long)g_m1Time[e - 1] + 60L >= tEnd)));
      recBar[0] = e - 1;
      if(!okc[0]) continue;
      const double cost = ((InpCostPoints > 0.0) ? InpCostPoints : (double)g_m1Spr[j]) + g_extraPts;
      ur[0] = MgRuleUnit(bv, atr, m);
      MgSim(j, d, ur, e, 1, 1, okc, recBar, slp, trd, tpd, S, HW, exitP, opn, gr, ex);
      ArrayResize(rNet, nRec + 1, 4096); ArrayResize(rDay, nRec + 1, 4096); ArrayResize(rCell, nRec + 1, 4096); ArrayResize(rSmp, nRec + 1, 4096);
      ArrayResize(rAdx, nRec + 1, 4096); ArrayResize(rReg, nRec + 1, 4096);
      rNet[nRec]  = gr[0] - cost;
      rDay[nRec]  = g_m1Day[j];
      rCell[nRec] = (uchar)(MgDow((long)g_m1Time[j]) * 24 + MgHour((long)g_m1Time[j]));
      rSmp[nRec]  = (uchar)((g_m1Day[j] >= g_splitDay) ? 1 : 0);
      rAdx[nRec]  = haveFs ? g_adxq[k] : (uchar)0;
      rReg[nRec]  = haveFs ? g_reg[k] : (uchar)255;
      nRec++;
     }
   return nRec;
  }

//+------------------------------------------------------------------+
//| SELEZIONE DI ORARI E GIORNI                                       |
//| Per la gestione e la durata scelte per un TF rifa' il percorso di  |
//| ogni segnale (ritardo 0), divide i risultati in celle ora x giorno |
//| della settimana (ora server + offset dell'ingresso), sceglie sul   |
//| primo periodo le celle con netto positivo e t sufficiente e misura |
//| sul resto il risultato della sola selezione. Confronto: tutti i    |
//| segnali e scelte casuali dello stesso numero di celle.             |
//+------------------------------------------------------------------+
bool MgSelect(const int m, const int bRule, const int bCap, MgSelRes &res)
  {
   res.ok = false; res.nElig = 0; res.nSel = 0; res.isN = 0.0; res.isMean = 0.0;
   res.allN = 0.0; res.allMean = 0.0; res.allT = 0.0; res.selN = 0.0; res.selMean = 0.0; res.selT = 0.0; res.pct = -1.0; res.selDays = 0;
   const int t = g_mgTf[m];
   double rNet[];
   int rDay[];
   uchar rCell[], rSmp[], rAdx[], rReg[];
   const int nRec = MgCollect(m, bRule, bCap, rNet, rDay, rCell, rSmp, rAdx, rReg);
   if(nRec < 60) return false;
   //--- statistiche per cella
   double cN[168], cS[168], cS2[168], cNo[168], cSo[168];
   bool selc[168];
   for(int q = 0; q < 168; q++) { cN[q] = 0.0; cS[q] = 0.0; cS2[q] = 0.0; cNo[q] = 0.0; cSo[q] = 0.0; selc[q] = false; }
   for(int i = 0; i < nRec; i++)
     {
      const int ci = (int)rCell[i];
      if(rSmp[i] == 0) { cN[ci] += 1.0; cS[ci] += rNet[i]; cS2[ci] += rNet[i] * rNet[i]; }
      else             { cNo[ci] += 1.0; cSo[ci] += rNet[i]; }
     }
   int nElig = 0, nSel = 0;
   double isN = 0.0, isS = 0.0;
   for(int q = 0; q < 168; q++)
     {
      if(cN[q] < (double)MathMax(3, InpSelMinCell)) continue;
      nElig++;
      const double mu = cS[q] / cN[q];
      const double ti = NaiveT(cN[q], cS[q], cS2[q]);
      if(mu > 0.0 && ti >= InpSelMinT) { selc[q] = true; nSel++; isN += cN[q]; isS += cS[q]; }
     }
   //--- fuori campione: tutti i segnali e solo le celle scelte, con il t raggruppato per giorno; curve cumulate
   double allN = 0.0, allS = 0.0, selN = 0.0, selS = 0.0;
   double aA = 0.0, bA = 0.0, cA = 0.0, aS = 0.0, bS = 0.0, cSs = 0.0;
   int dayA = -1, dayS = -1, selDays = 0;
   double dsA = 0.0, dnA = 0.0, dsS = 0.0, dnS = 0.0;
   const int step = MathMax(1, nRec / 300);
   double ya[], ys[];
   ArrayResize(ya, 0, 400); ArrayResize(ys, 0, 400);
   double cumA = 0.0, cumS = 0.0;
   int firstOos = -1;
   for(int i = 0; i < nRec; i++)
     {
      const bool isSel = selc[(int)rCell[i]];
      cumA += rNet[i];
      if(isSel) cumS += rNet[i];
      if((i % step) == 0)
        {
         const int np = ArraySize(ya);
         ArrayResize(ya, np + 1, 400); ArrayResize(ys, np + 1, 400);
         ya[np] = cumA; ys[np] = cumS;
        }
      if(rSmp[i] == 0) continue;
      if(firstOos < 0) firstOos = i;
      allN += 1.0; allS += rNet[i];
      if(rDay[i] != dayA) { aA += dsA * dsA; bA += dsA * dnA; cA += dnA * dnA; dsA = 0.0; dnA = 0.0; dayA = rDay[i]; }
      dsA += rNet[i]; dnA += 1.0;
      if(isSel)
        {
         selN += 1.0; selS += rNet[i];
         if(rDay[i] != dayS) { aS += dsS * dsS; bS += dsS * dnS; cSs += dnS * dnS; dsS = 0.0; dnS = 0.0; dayS = rDay[i]; selDays++; }
         dsS += rNet[i]; dnS += 1.0;
        }
     }
   aA += dsA * dsA; bA += dsA * dnA; cA += dnA * dnA;
   aS += dsS * dsS; bS += dsS * dnS; cSs += dnS * dnS;
   res.nElig = nElig; res.nSel = nSel; res.selDays = selDays;
   res.isN = isN; res.isMean = (isN > 0.0) ? isS / isN : 0.0;
   res.allN = allN; res.allMean = (allN > 0.0) ? allS / allN : 0.0;
   res.selN = selN; res.selMean = (selN > 0.0) ? selS / selN : 0.0;
   res.allT = ClusterT(allN, res.allMean, aA, bA, cA);
   res.selT = ClusterT(selN, res.selMean, aS, bS, cSs);
   //--- scelte casuali dello stesso numero di celle fra quelle ammissibili (generatore xorshift fisso, riproducibile)
   if(nSel >= 1 && nElig > nSel && selN > 0.0)
     {
      int pool[];
      ArrayResize(pool, nElig);
      int pk = 0;
      for(int q = 0; q < 168; q++) if(cN[q] >= (double)MathMax(3, InpSelMinCell)) { pool[pk] = q; pk++; }
      ulong x = 88172645463325252;
      int below = 0, ties = 0, draws = 0;
      for(int dr = 0; dr < 500; dr++)
        {
         double so = 0.0, no = 0.0;
         for(int z = 0; z < nSel; z++)
           {
            x ^= (x << 13); x ^= (x >> 7); x ^= (x << 17);
            const int jx = z + (int)(x % (ulong)(nElig - z));
            const int tmp = pool[z]; pool[z] = pool[jx]; pool[jx] = tmp;
            so += cSo[pool[z]]; no += cNo[pool[z]];
           }
         if(no <= 0.0) continue;
         draws++;
         const double mr = so / no;
         if(mr < res.selMean) below++;
         else if(mr == res.selMean) ties++;
        }
      if(draws >= 50) res.pct = 100.0 * ((double)below + 0.5 * (double)ties) / (double)draws;
     }
   //--- curva
   g_mgSvg[m] = MgSvgCurve(ya, ys, ArraySize(ya), (firstOos >= 0) ? (firstOos / step) : -1);
   //--- celle scelte con le loro misure (le prime 14 per netto in-sample)
   string tb = "", top = "";
   bool used[168];
   for(int q = 0; q < 168; q++) used[q] = false;
   //--- digest: tutte le celle scelte (giorno, ora, segnali e netto in-sample e fuori campione)
   for(int q = 0; q < 168; q++)
     {
      if(!selc[q]) continue;
      g_dg += "MGMTSELCELL|" + g_tfName[t] + "|" + MgCellLbl(q) + "|isn|" + F0(cN[q]) + "|isnet|" + F1(cS[q] / cN[q]) + "|oosn|" + F0(cNo[q]) + "|oosnet|" + string(cNo[q] > 0.0 ? F1(cSo[q] / cNo[q]) : string("-")) + "\n";
     }
   for(int z = 0; z < 14; z++)
     {
      int bq = -1;
      double bv = -1.0e18;
      for(int q = 0; q < 168; q++)
        {
         if(!selc[q] || used[q]) continue;
         const double mu = cS[q] / cN[q];
         if(mu > bv) { bv = mu; bq = q; }
        }
      if(bq < 0) break;
      used[bq] = true;
      const double mo = (cNo[bq] > 0.0) ? cSo[bq] / cNo[bq] : 0.0;
      if(z < 5) top += string(z > 0 ? ", " : "") + MgCellLbl(bq) + " (in-sample " + Sg(cS[bq] / cN[bq]) + " su " + F0(cN[bq]) + ", fuori campione " + string(cNo[bq] > 0.0 ? (Sg(mo) + " su " + F0(cNo[bq])) : string("n.d.")) + ")";
      tb += "<tr><td>" + MgCellLbl(bq) + "</td>" + Td(F0(cN[bq])) + Td(F1(cS[bq] / cN[bq]), ColSign(cS[bq])) + Td(F0(cNo[bq])) +
            Td(cNo[bq] > 0.0 ? F1(mo) : string("-"), ColSign(mo)) + "</tr>";
     }
   g_mgSelTop[m] = top;
   if(tb != "")
      g_mgSelTab[m] = "<table><tr><th>Cella (giorno e ora d'ingresso)</th><th>Segnali in-sample</th><th>Netto in-sample (pt)</th><th>Segnali fuori campione</th><th>Netto fuori campione (pt)</th></tr>" + tb + "</table>";
   res.ok = true;
   return true;
  }

//--- verdetto di un risultato fuori campione: 0 campione scarso, 1 positivo con t >= 2 (da confermare), 2 positivo ma debole, 3 non positivo
int OosVerdict(const bool scarso, const double mean, const bool strong)
  {
   if(scarso) return 0;
   if(mean > 0.0 && strong) return 1;
   return (mean > 0.0) ? 2 : 3;
  }

string VerdCell(const int v)
  {
   if(v == 0) return Td("OOS scarso", "#4c566a");
   if(v == 1) return Td("<b>t &ge; 2 (da confermare)</b>", "#a3be8c");
   return (v == 2) ? Td("debole", "#ebcb8b") : Td("NO", "#bf616a");
  }

string VerdText(const int v)
  {
   if(v == 0) return "fuori campione scarso";
   if(v == 1) return "t >= 2 da confermare";
   return (v == 2) ? "debole" : "no";
  }

//--- registra un test positivo e significativo fuori campione per la scheda (ix = serie * g_nT + TF) e per l'elenco finale
void CdPos(const int ix, const string test)
  {
   g_cdPos[ix]++;
   g_cdWin += string(g_cdWin != "" ? "; " : "") + g_setTag[ix / g_nT] + " " + g_tfName[ix % g_nT] + " (" + test + ")";
  }

//+------------------------------------------------------------------+
//| SCANSIONE AUTOMATICA DEI FILTRI                                   |
//| Per ogni TF prende la gestione e la durata scelte in-sample (ritardo|
//| 0) e rifa' il risultato di ogni segnale; poi prova da sola tutte le|
//| combinazioni dei filtri dell'EA: livello minimo di ADX (InpFilterAdx|
//| piu' lo zero) x i 15 sottoinsiemi non vuoti dei 4 regimi di        |
//| volatilita' (LOW, NORMAL, HIGH, EXTREME) x volatilita' in salita   |
//| no/si. La variante migliore e' scelta sul primo periodo (t         |
//| raggruppato per giorno piu' alto fra quelle che lasciano almeno il |
//| 10% dei segnali) e misurata sul resto. Confronti: nessun filtro, la|
//| configurazione del backtest EURUSD (ADX 17, senza HIGH) e il       |
//| massimo atteso per caso fra le varianti provate (sqrt(2 ln m)).    |
//+------------------------------------------------------------------+
#define FSF 6            // campi per variante e periodo: n, somma, somma^2, somme del t raggruppato per giorno (3)
double  g_fsAdx[];       // livelli minimi di ADX provati (il primo e' sempre 0 = nessun filtro)
int     g_fsAdxQ[];      // gli stessi in mezzi punti (soglia sul valore intero g_adxq)
int     g_fsNa = 0, g_fsNv = 0;
double  g_fsPool[];      // [variante][n, somma]: fuori campione, sommato sui TF valutabili della serie corrente
string  g_cFilt = "";    // testo per il riepilogo
int     g_fsEvalTf = 0, g_fsPosTf = 0, g_fsBetterTf = 0;   // TF valutabili, con variante scelta positiva e t >= 2 fuori campione, con variante scelta migliore di nessun filtro

struct FsRes
  {
   bool   ok;
   int    nElig;                                   // varianti con abbastanza segnali in-sample
   int    bestV;                                   // scelta sul primo periodo
   double bIsN, bIsMean, bIsT, bOosN, bOosMean, bOosT;
   double aIsN, aOosN, aOosMean, aOosT;                   // nessun filtro
   bool   eOk;                                     // configurazione di riferimento (ADX 17, senza HIGH) presente nella griglia
   int    eV;
   double eOosN, eOosMean, eOosT;
   double chance;
   int    nBoth, nStrong;                          // varianti con netto positivo in-sample e fuori campione / e t fuori campione >= 2
  };

int FsIx(const int ia, const int mask, const int rise)
  {
   return (ia * 15 + (mask - 1)) * 2 + rise;
  }

void FsSetup()
  {
   double lv[];
   ParseNonNegList(InpFilterAdx, lv, 9, 100.0);
   g_fsNa = ArraySize(lv);
   ArrayResize(g_fsAdx, g_fsNa);
   ArrayResize(g_fsAdxQ, g_fsNa);
   //--- l'ADX della scansione e' memorizzato a mezzi punti: i livelli sono portati al mezzo punto superiore (17.3 diventa 17.5) e l'etichetta riporta il livello effettivo
   int nu = 0;
   for(int i = 0; i < g_fsNa; i++)
     {
      const double eff = MathCeil(lv[i] * 2.0 - 1.0e-9) / 2.0;
      if(nu > 0 && MathAbs(g_fsAdx[nu - 1] - eff) < 1.0e-9) continue;
      g_fsAdx[nu] = eff;
      g_fsAdxQ[nu] = (int)MathRound(eff * 2.0);
      nu++;
     }
   g_fsNa = nu;
   ArrayResize(g_fsAdx, g_fsNa);
   ArrayResize(g_fsAdxQ, g_fsNa);
   g_fsNv = g_fsNa * 15 * 2;
  }

string FsRegNames(const int mask)
  {
   if(mask == 15) return "tutti i regimi";
   string tx = "";
   if((mask & 1) != 0) tx += string(tx == "" ? "" : "+") + "LOW";
   if((mask & 2) != 0) tx += string(tx == "" ? "" : "+") + "NORMAL";
   if((mask & 4) != 0) tx += string(tx == "" ? "" : "+") + "HIGH";
   if((mask & 8) != 0) tx += string(tx == "" ? "" : "+") + "EXTREME";
   return "regimi " + tx;
  }

string FsLbl(const int v)
  {
   const int rise = v % 2, mask = ((v / 2) % 15) + 1, ia = v / 30;
   return string(ia == 0 ? "senza filtro ADX" : ("ADX >= " + GridLbl(g_fsAdx[ia]))) + ", " + FsRegNames(mask) + string(rise == 1 ? ", volatilita' in salita" : "");
  }

//--- risultato di ogni segnale, poi somme di ogni variante per periodo; false se il campione e' insufficiente
bool FsScan(const int m, const int bRule, const int bCap, double &fa[])
  {
   double rNet[];
   int rDay[];
   uchar rCell[], rSmp[], rAdx[], rReg[];
   const int nRec = MgCollect(m, bRule, bCap, rNet, rDay, rCell, rSmp, rAdx, rReg);
   if(nRec < 60) return false;
   const int V = g_fsNv;
   ArrayResize(fa, V * 2 * FSF);
   ArrayInitialize(fa, 0.0);
   int curDay[], curSmp[];
   double curS[], curN[];
   ArrayResize(curDay, V); ArrayResize(curSmp, V); ArrayResize(curS, V); ArrayResize(curN, V);
   ArrayInitialize(curDay, -1); ArrayInitialize(curSmp, 0); ArrayInitialize(curS, 0.0); ArrayInitialize(curN, 0.0);
   for(int i = 0; i < nRec; i++)
     {
      const double x = rNet[i];
      const int smp = (int)rSmp[i];
      const int day = rDay[i];
      const int adx = (int)rAdx[i];
      const int rg = (int)rReg[i];
      const bool known = (rg != 255);
      const int rbit = known ? ((rg >> 1) & 3) : 0;
      const bool rising = (known && (rg & 1) == 1);
      for(int ia = 0; ia < g_fsNa; ia++)
        {
         if(adx < g_fsAdxQ[ia]) break;                        // livelli crescenti: se non passa questo non passa i successivi
         for(int mk = 1; mk <= 15; mk++)
           {
            if(mk != 15 && (!known || ((mk >> rbit) & 1) == 0)) continue;
            for(int rs = 0; rs < 2; rs++)
              {
               if(rs == 1 && !rising) continue;
               const int v = FsIx(ia, mk, rs);
               if(curDay[v] != day)
                 {
                  if(curN[v] > 0.0)
                    {
                     const int pc = (v * 2 + curSmp[v]) * FSF;
                     fa[pc + 3] += curS[v] * curS[v];
                     fa[pc + 4] += curS[v] * curN[v];
                     fa[pc + 5] += curN[v] * curN[v];
                     curS[v] = 0.0;
                     curN[v] = 0.0;
                    }
                  curDay[v] = day;
                  curSmp[v] = smp;
                 }
               curS[v] += x;
               curN[v] += 1.0;
               const int p = (v * 2 + smp) * FSF;
               fa[p] += 1.0;
               fa[p + 1] += x;
               fa[p + 2] += x * x;
              }
           }
        }
     }
   for(int v = 0; v < V; v++)
     {
      if(curN[v] <= 0.0) continue;
      const int pc = (v * 2 + curSmp[v]) * FSF;
      fa[pc + 3] += curS[v] * curS[v];
      fa[pc + 4] += curS[v] * curN[v];
      fa[pc + 5] += curN[v] * curN[v];
     }
   return true;
  }

//--- n, media e t raggruppato per giorno di una variante; smp 0 = in-sample, 1 = fuori campione, -1 = tutto
void FsStat(const double &fa[], const int v, const int smp, double &n, double &mean, double &tt)
  {
   n = 0.0;
   double sx = 0.0, a = 0.0, b = 0.0, c = 0.0;
   for(int s = 0; s < 2; s++)
     {
      if(smp >= 0 && s != smp) continue;
      const int p = (v * 2 + s) * FSF;
      n += fa[p]; sx += fa[p + 1]; a += fa[p + 3]; b += fa[p + 4]; c += fa[p + 5];
     }
   mean = (n > 0.0) ? sx / n : 0.0;
   tt = ClusterT(n, mean, a, b, c);
  }

//--- scelta in-sample della variante e confronti
void FsEvaluate(const double &fa[], const double minIs, const double minOos, FsRes &r)
  {
   r.ok = false; r.nElig = 0; r.bestV = -1;
   r.bIsN = 0.0; r.bIsMean = 0.0; r.bIsT = 0.0; r.bOosN = 0.0; r.bOosMean = 0.0; r.bOosT = 0.0;
   r.aIsN = 0.0; r.aOosN = 0.0; r.aOosMean = 0.0; r.aOosT = 0.0;
   r.eOk = false; r.eV = -1; r.eOosN = 0.0; r.eOosMean = 0.0; r.eOosT = 0.0;
   r.chance = 0.0; r.nBoth = 0; r.nStrong = 0;
   const int v0 = FsIx(0, 15, 0);
   double mIs, tIs;
   FsStat(fa, v0, 0, r.aIsN, mIs, tIs);
   FsStat(fa, v0, 1, r.aOosN, r.aOosMean, r.aOosT);
   if(r.aIsN < minIs) return;
   const double thrN = MathMax(minIs, 0.10 * r.aIsN);
   double bt = -1.0e18;
   for(int v = 0; v < g_fsNv; v++)
     {
      double n0, m0, t0, n1, m1, t1;
      FsStat(fa, v, 0, n0, m0, t0);
      if(n0 < thrN) continue;
      r.nElig++;
      FsStat(fa, v, 1, n1, m1, t1);
      if(n1 >= minOos && m0 > 0.0 && m1 > 0.0) { r.nBoth++; if(t1 >= 2.0) r.nStrong++; }
      if(t0 > bt) { bt = t0; r.bestV = v; }
     }
   if(r.bestV < 0) return;
   FsStat(fa, r.bestV, 0, r.bIsN, r.bIsMean, r.bIsT);
   FsStat(fa, r.bestV, 1, r.bOosN, r.bOosMean, r.bOosT);
   r.chance = (r.nElig > 1) ? MathSqrt(2.0 * MathLog((double)r.nElig)) : 0.0;
   for(int ia = 0; ia < g_fsNa; ia++)
      if(MathAbs(g_fsAdx[ia] - 17.0) < 1.0e-9)
        {
         r.eV = FsIx(ia, 1 + 2 + 8, 0);
         r.eOk = true;
        }
   if(r.eOk)
     {
      FsStat(fa, r.eV, 1, r.eOosN, r.eOosMean, r.eOosT);
     }
   r.ok = true;
  }

string FsVerdict(const FsRes &r, const double minOos)
  {
   if(r.bOosN < minOos) return "fuori campione scarso";
   if(r.bOosMean > 0.0 && r.bOosT >= 2.0 && r.bOosMean > r.aOosMean) return "positivo, t >= 2, meglio di nessun filtro (da confermare)";
   if(r.bOosMean > 0.0 && r.bOosT >= 2.0) return "positivo, t >= 2, ma non meglio di nessun filtro";
   if(r.bOosMean > 0.0) return "debole";
   return "no";
  }

string FsRow(const double &fa[], const int v, const bool withLabel)
  {
   double n0, m0, t0, n1, m1, t1;
   FsStat(fa, v, 0, n0, m0, t0);
   FsStat(fa, v, 1, n1, m1, t1);
   return "<tr>" + string(withLabel ? Td(FsLbl(v)) : "") + Td(F0(n0)) + Td(F1(m0), ColSign(m0)) + Td(F2(t0)) + Td(F0(n1)) + Td(n1 > 0.0 ? F1(m1) : string("-"), ColSign(m1)) + Td(n1 > 1.0 ? F2(t1) : string("-"), ColT(t1)) + "</tr>";
  }

void FsDg(const string tfn, const double &fa[], const int v, const string kind)
  {
   double n0, m0, t0, n1, m1, t1;
   FsStat(fa, v, 0, n0, m0, t0);
   FsStat(fa, v, 1, n1, m1, t1);
   const string lb = FsLbl(v);
   g_dg += "FSVAR|" + tfn + "|" + kind + "|" + lb + "|isn|" + F0(n0) + "|isnet|" + F1(m0) + "|ist|" + F2(t0) + "|oosn|" + F0(n1) + "|oosnet|" + string(n1 > 0.0 ? F1(m1) : string("-")) + "|oost|" + string(n1 > 1.0 ? F2(t1) : string("-")) + "\n";
  }

//+------------------------------------------------------------------+
//| Tabelle e testo della scansione dei filtri su tutti i TF simulati  |
//+------------------------------------------------------------------+
void RepFilters(const int sIdx, const int &bR[], const int &pC[], const double minIs, const double minOos)
  {
   g_cFilt = "";
   g_fsEvalTf = 0; g_fsPosTf = 0; g_fsBetterTf = 0;
   if(!InpFilterScan) return;
   const int nM = g_mgNtf;
   ArrayResize(g_fsPool, g_fsNv * 2);
   ArrayInitialize(g_fsPool, 0.0);
   string adxList = "";
   for(int i = 1; i < g_fsNa; i++) adxList += string(i > 1 ? ", " : "") + GridLbl(g_fsAdx[i]);
   W("<h3>Scansione automatica dei filtri dell'EA: ADX x regime di volatilit&agrave; x volatilit&agrave; in salita</h3>");
   W("<div class='note'>Per ogni TF, con la miglior gestione e durata scelte in-sample (ritardo 0), ogni segnale &egrave; rifatto e poi si prova <b>da soli</b> tutti i filtri dell'EA: ADX minimo " +
     string(adxList != "" ? ("(livelli " + adxList + " e nessun filtro)") : "(nessun livello)") + " x i 15 sottoinsiemi non vuoti dei regimi LOW, NORMAL, HIGH, EXTREME x volatilit&agrave; in salita no/s&igrave; = <b>" + IS(g_fsNv) + " varianti</b> per TF. "
     "La variante migliore &egrave; scelta <b>sul primo periodo</b> (t raggruppato per giorno pi&ugrave; alto fra quelle che lasciano almeno il 10% dei segnali) e il suo risultato sul resto &egrave; l'unico che conta: "
     "con tante varianti provate il massimo in-sample cresce per puro caso (circa &radic;(2 ln m), colonna <i>Atteso per caso</i>). Confronti: nessun filtro e la configurazione dell'EA del backtest EURUSD (ADX 17, senza il regime HIGH). "
     "Un filtro che migliora solo in-sample ha ridotto i segnali tenendo quelli fortunati; un filtro vero migliora anche dopo. Il campione &egrave; lo stesso della gestione simulata (" + string(InpMgmtMaxSignals > 0 ? ("fino a " + IS(InpMgmtMaxSignals) + " segnali per TF") : "tutti i segnali") + ").</div>");
   W("<table><tr><th>TF</th><th>Nessun filtro: fuori campione (n, netto pt)</th><th>Variante scelta in-sample</th><th>In-sample (n, netto, t)</th><th>Fuori campione (n, netto, t)</th><th>Atteso per caso (t max)</th>"
     "<th>Config. EA backtest: fuori campione (n, netto)</th><th>Esito</th></tr>");
   FsRes rs[];
   ArrayResize(rs, nM);
   double fa[];
   string allDet = "";                  // dettagli per TF, scritti dopo la tabella di sintesi
   string txTf = "";
   int nScan = 0;
   for(int m = 0; m < nM; m++)
     {
      rs[m].ok = false;
      const int t = g_mgTf[m];
      if(bR[m] < 0) continue;
      if(IsStopped()) break;
      if(!FsScan(m, bR[m], pC[m], fa))
        {
         W("<tr class='thin'><td>" + g_tfName[t] + "</td><td colspan='7'>campione insufficiente</td></tr>");
         txTf += g_tfName[t] + ": campione insufficiente; ";
         g_cdFilt[sIdx * g_nT + t] = "campione insufficiente";
         continue;
        }
      FsEvaluate(fa, minIs, minOos, rs[m]);
      nScan++;
      if(!rs[m].ok)
        {
         W("<tr class='thin'><td>" + g_tfName[t] + "</td><td colspan='7'>campione in-sample insufficiente per scegliere (" + F0(rs[m].aIsN) + " segnali, minimo " + F0(minIs) + ")</td></tr>");
         txTf += g_tfName[t] + ": campione in-sample insufficiente; ";
         g_cdFilt[sIdx * g_nT + t] = "campione in-sample insufficiente";
         continue;
        }
      const FsRes q = rs[m];
      const bool evalOk = (q.bOosN >= minOos && q.aOosN >= minOos);
      if(evalOk)
        {
         g_fsEvalTf++;
         g_cdEval[sIdx * g_nT + t]++;
         if(q.bOosMean > 0.0 && q.bOosT >= 2.0 && q.bOosMean > q.aOosMean) { CdPos(sIdx * g_nT + t, "filtri"); g_fsPosTf++; }
         if(q.bOosMean > q.aOosMean) g_fsBetterTf++;
         //--- effetto medio di ogni variante su tutti i TF valutabili (fuori campione)
         for(int v = 0; v < g_fsNv; v++)
           {
            double n1, m1, t1;
            FsStat(fa, v, 1, n1, m1, t1);
            g_fsPool[v * 2] += n1;
            g_fsPool[v * 2 + 1] += n1 * m1;
           }
        }
      const string vd = FsVerdict(q, minOos);
      const string es = VerdCell(OosVerdict(q.bOosN < minOos, q.bOosMean, q.bOosT >= 2.0 && q.bOosMean > q.aOosMean));
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(F0(q.aOosN) + ", " + F1(q.aOosMean), ColSign(q.aOosMean)) + Td(FsLbl(q.bestV)) + Td(F0(q.bIsN) + ", " + F1(q.bIsMean) + ", " + F2(q.bIsT)) +
        Td(F0(q.bOosN) + ", <b>" + F1(q.bOosMean) + "</b>, " + F2(q.bOosT), ColSign(q.bOosMean)) + Td(F2(q.chance)) +
        Td(q.eOk ? (F0(q.eOosN) + ", " + F1(q.eOosMean)) : string("fuori griglia"), ColSign(q.eOosMean)) + es + "</tr>");
      g_dg += "FSCAN|" + g_tfName[t] + "|" + MgRuleDg(bR[m], m) + "|hold|" + IS(g_hor[pC[m]]) + "|variants|" + IS(g_fsNv) + "|elig|" + IS(q.nElig) + "|best|" + FsLbl(q.bestV) +
              "|isn|" + F0(q.bIsN) + "|isnet|" + F1(q.bIsMean) + "|ist|" + F2(q.bIsT) + "|oosn|" + F0(q.bOosN) + "|oosnet|" + F1(q.bOosMean) + "|oost|" + F2(q.bOosT) + "|chance|" + F2(q.chance) +
              "|nofilt_oosn|" + F0(q.aOosN) + "|nofilt_oosnet|" + F1(q.aOosMean) + "|nofilt_oost|" + F2(q.aOosT) +
              "|ea_oosn|" + string(q.eOk ? F0(q.eOosN) : string("na")) + "|ea_oosnet|" + string(q.eOk ? F1(q.eOosMean) : string("na")) + "|both|" + IS(q.nBoth) + "|strong|" + IS(q.nStrong) + "|eval|" + IS(evalOk ? 1 : 0) + "\n";
      //--- digest: nessun filtro, riferimento EA, prime 10 per t in-sample, effetto di ogni filtro da solo
      FsDg(g_tfName[t], fa, FsIx(0, 15, 0), "nofilter");
      if(q.eOk) FsDg(g_tfName[t], fa, q.eV, "ea");
      string cd = string(q.bIsMean > 0.0 ? "" : "nessuna variante ha netto in-sample positivo, la meno negativa e' ") + FsLbl(q.bestV) + ": in-sample " + Sg(q.bIsMean) + " pt su " + F0(q.bIsN) + " segnali (t " + F2(q.bIsT) + "), fuori campione " + Sg(q.bOosMean) + " pt su " + F0(q.bOosN) +
                  " (t " + F2(q.bOosT) + ", " + vd + ") contro " + Sg(q.aOosMean) + " pt senza filtri su " + F0(q.aOosN) + string(q.eOk ? (" e " + Sg(q.eOosMean) + " pt con la configurazione dell'EA (" + F0(q.eOosN) + " segnali)") : "");
      g_cdFilt[sIdx * g_nT + t] = cd + "; massimo in-sample atteso per caso su " + IS(q.nElig) + " varianti: t " + F2(q.chance) + ", ottenuto " + F2(q.bIsT);
      txTf += g_tfName[t] + ": " + cd + "; ";
      //--- dettaglio del TF
      bool usedV[];
      ArrayResize(usedV, g_fsNv);
      ArrayInitialize(usedV, false);
      string det = "<details><summary><b>" + g_tfName[t] + "</b> &mdash; filtri: prime 10 varianti in-sample, effetto di ogni filtro da solo</summary>";
      det += "<h3>" + g_tfName[t] + ": le 10 varianti con il t in-sample pi&ugrave; alto (con gestione " + MgRuleLbl(bR[m], m) + ", durata " + MgCapLbl(pC[m], t) + ")</h3>";
      det += "<table><tr><th>Variante</th><th>Segnali in-sample</th><th>Netto in-sample</th><th>t in-sample</th><th>Segnali fuori campione</th><th>Netto fuori campione</th><th>t fuori campione</th></tr>";
      double thrN = MathMax(minIs, 0.10 * q.aIsN);
      for(int z = 0; z < 10; z++)
        {
         int bv = -1;
         double btv = -1.0e18;
         for(int v = 0; v < g_fsNv; v++)
           {
            if(usedV[v]) continue;
            double n0, m0, t0;
            FsStat(fa, v, 0, n0, m0, t0);
            if(n0 < thrN) continue;
            if(t0 > btv) { btv = t0; bv = v; }
           }
         if(bv < 0) break;
         usedV[bv] = true;
         det += FsRow(fa, bv, true);
         FsDg(g_tfName[t], fa, bv, "top");
        }
      det += "</table>";
      det += "<h3>" + g_tfName[t] + ": effetto di ogni filtro da solo</h3>";
      det += "<table><tr><th>Filtro</th><th>Segnali in-sample</th><th>Netto in-sample</th><th>t in-sample</th><th>Segnali fuori campione</th><th>Netto fuori campione</th><th>t fuori campione</th></tr>";
      for(int ia = 0; ia < g_fsNa; ia++)
        {
         const int v = FsIx(ia, 15, 0);
         det += FsRow(fa, v, true);
         if(ia > 0) FsDg(g_tfName[t], fa, v, "adx");
        }
      for(int bit = 0; bit < 4; bit++)
        {
         const int vOnly = FsIx(0, 1 << bit, 0), vWithout = FsIx(0, 15 - (1 << bit), 0);
         det += FsRow(fa, vOnly, true);
         det += FsRow(fa, vWithout, true);
         FsDg(g_tfName[t], fa, vOnly, "regonly");
         FsDg(g_tfName[t], fa, vWithout, "regwithout");
        }
      det += FsRow(fa, FsIx(0, 15, 1), true);
      FsDg(g_tfName[t], fa, FsIx(0, 15, 1), "rising");
      det += "</table></details>";
      allDet += det;
     }
   W("</table>");
   W(allDet);
   if(nScan == 0)
     {
      g_cFilt = "Scansione dei filtri richiesta ma non valutabile: " + string(txTf != "" ? txTf : "nessun TF con gestione scelta e campione sufficiente.");
      return;
     }
   //--- effetto medio di ogni filtro da solo, sommando tutti i TF valutabili (fuori campione)
   string poolTx = "";
   double bn = g_fsPool[FsIx(0, 15, 0) * 2], bs = g_fsPool[FsIx(0, 15, 0) * 2 + 1];
   if(g_fsEvalTf > 0 && bn > 0.0)
     {
      poolTx = "Effetto medio di ogni filtro da solo, fuori campione, sommando " + Pl(g_fsEvalTf, "TF valutabile", "TF valutabili") + " (media pesata sui segnali, non indipendenti fra TF; nessun filtro: " + Sg(bs / bn) + " pt su " + F0(bn) + " segnali): ";
      for(int ia = 1; ia < g_fsNa; ia++)
        {
         const int v = FsIx(ia, 15, 0);
         poolTx += "ADX >= " + GridLbl(g_fsAdx[ia]) + " " + (g_fsPool[v * 2] > 0.0 ? (Sg(g_fsPool[v * 2 + 1] / g_fsPool[v * 2]) + " pt su " + F0(g_fsPool[v * 2])) : string("n.d.")) + "; ";
        }
      string nm[4] = {"LOW", "NORMAL", "HIGH", "EXTREME"};
      for(int bit = 0; bit < 4; bit++)
        {
         const int vW = FsIx(0, 15 - (1 << bit), 0), vO = FsIx(0, 1 << bit, 0);
         poolTx += "senza " + nm[bit] + " " + (g_fsPool[vW * 2] > 0.0 ? (Sg(g_fsPool[vW * 2 + 1] / g_fsPool[vW * 2]) + " pt su " + F0(g_fsPool[vW * 2])) : string("n.d.")) +
                   ", solo " + nm[bit] + " " + (g_fsPool[vO * 2] > 0.0 ? (Sg(g_fsPool[vO * 2 + 1] / g_fsPool[vO * 2]) + " pt su " + F0(g_fsPool[vO * 2])) : string("n.d.")) + "; ";
        }
      const int vR = FsIx(0, 15, 1);
      poolTx += "solo volatilita' in salita " + (g_fsPool[vR * 2] > 0.0 ? (Sg(g_fsPool[vR * 2 + 1] / g_fsPool[vR * 2]) + " pt su " + F0(g_fsPool[vR * 2])) : string("n.d.")) + ". ";
      W("<div class='note'>" + HtmlEsc(poolTx) + "</div>");
      g_dg += "FSPOOL|nofilter|oosn|" + F0(bn) + "|oosnet|" + F1(bs / bn);
      for(int ia = 1; ia < g_fsNa; ia++)
        {
         const int v = FsIx(ia, 15, 0);
         g_dg += "|adx" + GridLbl(g_fsAdx[ia]) + "|" + (g_fsPool[v * 2] > 0.0 ? (F1(g_fsPool[v * 2 + 1] / g_fsPool[v * 2]) + "/" + F0(g_fsPool[v * 2])) : string("na"));
        }
      g_dg += "\n";
     }
   const double expPos = 0.0228 * (double)g_fsEvalTf;
   string verd;
   if(g_fsEvalTf == 0) verd = "Nessun TF e' valutabile fuori campione: non emerge evidenza ne' a favore ne' contro i filtri.";
   else if(g_fsPosTf == 0) verd = "Nessuna variante scelta in-sample resta positiva, significativa e migliore di nessun filtro fuori campione: non emerge evidenza che ADX, regime di volatilita' o volatilita' in salita rendano operabili questi segnali. " +
                                  string(g_fsBetterTf * 2 > g_fsEvalTf ? "Migliorano il netto medio rispetto a nessun filtro in piu' della meta' dei TF, ma restano non significativi." : "Non migliorano in modo coerente il netto medio rispetto a nessun filtro.");
   else verd = "Le varianti positive sono candidati da confermare su altri simboli e periodi: la scelta fra " + IS(g_fsNv) + " varianti per TF e' ottimizzata sul primo periodo e con tante prove qualche risultato significativo e' atteso per caso.";
   g_cFilt = "Filtri dell'EA provati in automatico su ogni TF con la miglior gestione del TF: " + string(g_fsNa > 1 ? (Pl(g_fsNa - 1, "livello", "livelli") + " di ADX (" + adxList + ")") : string("nessun livello di ADX")) + " x 15 sottoinsiemi di regimi x volatilita' in salita no/si = " + IS(g_fsNv) +
             " varianti per TF, scelta sul primo periodo (t piu' alto fra quelle con almeno il 10% dei segnali), verifica sul resto. TF valutabili: " + IS(g_fsEvalTf) + "; variante scelta positiva fuori campione con t >= 2 e migliore di nessun filtro: " + IS(g_fsPosTf) +
             " (per puro caso circa " + F1(expPos) + "); migliore di nessun filtro fuori campione: " + IS(g_fsBetterTf) + ". " + verd + " " + poolTx + "Il dettaglio di ogni TF e' nella sua scheda. " +
             "Le tabelle con le prime 10 varianti e l'effetto di ogni filtro da solo sono nel report HTML (dettaglio di ogni TF) e nel digest (FSCAN, FSVAR, FSPOOL).";
  }

void RepMgmt()
  {
   g_cMgmt = ""; g_cMgmt3 = ""; g_cMgmt4 = ""; g_cMgmt5 = ""; g_cFilt = "";
   g_fsEvalTf = 0; g_fsPosTf = 0; g_fsBetterTf = 0; g_mgOn = false; g_mgHasShort = false; g_mgPosTf = 0; g_mgEvalTf = 0; g_mgRobTf = 0; g_mgRobTested = 0; g_mgSelPosTf = 0; g_mgSelEvalTf = 0;
   if(!InpMgmt)
     {
      if(InpFilterScan) g_cFilt = "Scansione dei filtri richiesta ma non eseguita: usa la gestione di ogni TF e quindi richiede InpMgmt = true.";
      return;
     }
   if(g_mgNtf < 1 || g_mgR < 1 || g_mgNlag < 1)
     {
      Print("Gestione simulata non eseguita: InpMgmtTFs o InpMgmtSlAtr non validi (nessun TF o nessuna gestione).");
      W("<div class='note ko'><b>Gestione simulata non eseguita</b>: InpMgmtTFs, InpMgmtSlAtr o InpMgmtLags non contengono valori validi (nessun TF o nessuna gestione).</div>");
      g_cMgmt = "Gestione simulata richiesta ma non eseguita: InpMgmtTFs, InpMgmtSlAtr o InpMgmtLags non contengono valori validi (nessun TF o nessuna gestione).";
      return;
     }
   if(!MgmtCompute())
     {
      W("<div class='note ko'><b>Gestione simulata non eseguita</b> (memoria insufficiente o interruzione). Riduci i TF, le griglie, gli orizzonti o i ritardi.</div>");
      g_cMgmt = "Gestione simulata richiesta ma non eseguita (memoria insufficiente o interruzione): riduci i TF, le griglie, gli orizzonti o i ritardi.";
      return;
     }
   const int nM = g_mgNtf, nC = g_nH, R = g_mgR, nLag = g_mgNlag;
   const double minIs = MathMax(30.0, g_minN / 2.0);
   const double minOos = MathMax(10.0, minIs / 3.0);
   const string uTxt = InpMgmtPoints ? string("punti fissi") : ("multipli dell'ATR(" + IS(InpMgmtAtrLen) + ") del TF del segnale, calcolato sulla barra del segnale (lo stop si adatta alla volatilita' del momento)" +
                       string(g_mgNv > 1 ? ", e in alternativa in PUNTI FISSI pari agli stessi multipli per l'ATR mediano del TF sul primo periodo (stop fisso come in un EA a SL/TP fissi: il valore in punti e' scritto accanto a ogni regola)" : ""));
   const string uTxtS = InpMgmtPoints ? string("in punti fissi") : string(g_mgNv > 1 ? "in multipli dell'ATR del momento o in punti fissi (ATR mediano)" : "in multipli dell'ATR");
   W("<h2>Gestione simulata: punti presi in media per segnale con stop, trailing, take profit, durata massima e ritardo d'ingresso</h2>");
   W("<div class='note'>Ogni segnale apre una posizione nel suo verso all'open della barra M1 d'ingresso. <b>Stop iniziale</b>, <b>trailing</b> e <b>take profit</b> sono in " + uTxt +
     " (griglie provate tutte insieme: " + IS(g_mgNsl) + " stop x " + IS(g_mgNtr) + " trailing x " + IS(g_mgNtp) + " target" + string(g_mgNv > 1 ? " x 2 unita'" : "") + " = " + IS(R) + " gestioni); il trailing parte quando il profitto raggiunge la sua distanza e porta lo stop a (massimo favorevole &minus; distanza), senza mai allontanarlo. "
     "La posizione esce allo stop, al target oppure alla <b>durata massima</b> (colonne = orizzonti). Dentro la barra M1 l'ordine fra minimo e massimo e' sconosciuto: " +
     string(InpMgmtHighFirst ? "si assume prima il massimo (limite pessimistico per il trailing; se la stessa barra tocca stop e target vince il target)" : "si assume prima il minimo (neutro su un percorso casuale; se la stessa barra tocca stop e target vince lo stop)") + ". "
     "<b>Ritardo</b>: ogni segnale e' rifatto anche aprendo N minuti piu' tardi (" + MgIntList(g_mgLag, g_mgNlag) + " min, tutti insieme); fascia oraria e periodo in-sample/fuori campione restano quelli dell'ingresso senza ritardo, la durata si conta dall'ingresso ritardato. "
     "<b>Lordo</b> = punti presi prima dei costi; <b>netto</b> = dopo spread, commissione e costo extra. Per i TF con molti segnali si simula un campione uniforme (" + string(InpMgmtMaxSignals > 0 ? ("massimo " + IS(InpMgmtMaxSignals) + " per TF") : "nessun limite") + "). "
     "Le posizioni non sono una per volta: si sovrappongono, e con la durata di un giorno attraversano piu' giorni (il t raggruppato per giorno e' allora ottimista). "
     "La miglior combinazione per TF e' scelta sul primo periodo (in-sample, a ritardo 0) e verificata sul resto: <b>solo il fuori campione conta</b>. Il t e' raggruppato per giorno.</div>");

   //--- scelta per TF (ritardo 0)
   int bR[], bC[], pC[];
   double bIs[], bOos[], bOosT[], bGross[], bOosN[], bStop[];
   ArrayResize(bR, nM); ArrayResize(bC, nM); ArrayResize(pC, nM);
   ArrayResize(bIs, nM); ArrayResize(bOos, nM); ArrayResize(bOosT, nM); ArrayResize(bGross, nM); ArrayResize(bOosN, nM); ArrayResize(bStop, nM);
   int nPos = 0, nEval = 0;
   for(int m = 0; m < nM; m++)
     {
      bR[m] = -1; bC[m] = -1; pC[m] = -1;
      bIs[m] = 0.0; bOos[m] = 0.0; bOosT[m] = 0.0; bGross[m] = 0.0; bOosN[m] = 0.0; bStop[m] = 0.0;
      double best = -1.0e18;
      for(int r = 0; r < R; r++)
         for(int c = 0; c < nC; c++)
           {
            double n, sn, sn2, sg, ss;
            MgSum(0, m, r, c, 0, n, sn, sn2, sg, ss);
            if(n < minIs) continue;
            if(sn / n > best) { best = sn / n; bR[m] = r; bC[m] = c; }
           }
      if(bR[m] < 0) continue;
      //--- durata consigliata: la piu' breve che raggiunge almeno il 90% del miglior netto in-sample (se positivo)
      pC[m] = bC[m];
      if(best > 0.0)
         for(int c = 0; c < nC; c++)
           {
            double n, sn, sn2, sg, ss;
            MgSum(0, m, bR[m], c, 0, n, sn, sn2, sg, ss);
            if(n >= minIs && sn / n >= 0.9 * best) { pC[m] = c; break; }
           }
      double n0, a0, b0, g0, s0;
      MgSum(0, m, bR[m], pC[m], 0, n0, a0, b0, g0, s0);
      bIs[m] = (n0 > 0.0) ? a0 / n0 : 0.0;
      double n1, a1, b1, g1, s1;
      MgSum(0, m, bR[m], pC[m], 1, n1, a1, b1, g1, s1);
      bOosN[m] = n1;
      bOos[m] = (n1 > 0.0) ? a1 / n1 : 0.0;
      bOosT[m] = MgClT(0, m, bR[m], pC[m], 1);
      bGross[m] = (n1 > 0.0) ? g1 / n1 : 0.0;
      bStop[m] = (n1 > 0.0) ? 100.0 * s1 / n1 : 0.0;
      if(bOosN[m] >= minOos) nEval++;
      if(bOosN[m] >= minOos && bOos[m] > 0.0 && bOosT[m] >= 2.0) nPos++;
      g_cdEval[g_curSet * g_nT + g_mgTf[m]] += (bOosN[m] >= minOos) ? 1 : 0;
      if(bOosN[m] >= minOos && bOos[m] > 0.0 && bOosT[m] >= 2.0) CdPos(g_curSet * g_nT + g_mgTf[m], "gestione");
     }

   //--- confronto fra time frame
   W("<h3>Confronto fra time frame (miglior gestione scelta in-sample, risultato fuori campione)</h3>");
   W("<table><tr><th>TF</th><th>Segnali simulati</th><th>Miglior gestione in-sample</th><th>Durata consigliata</th><th>Lordo fuori campione (pt)</th><th>Netto in-sample (pt)</th>"
     "<th>Netto fuori campione (pt)</th><th>Netto fuori campione (" + g_ccy + ")</th><th>t fuori campione</th><th>Uscite per stop o target (fuori campione)</th><th>Esito</th></tr>");
   for(int m = 0; m < nM; m++)
     {
      const int t = g_mgTf[m];
      if(bR[m] < 0)
        { W("<tr class='thin'><td>" + g_tfName[t] + "</td><td colspan='10'>campione insufficiente (" + IS(g_mgUsed[m]) + " segnali simulati)</td></tr>"); continue; }
      const string es = VerdCell(OosVerdict(bOosN[m] < minOos, bOos[m], bOosT[m] >= 2.0));
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(F0(g_mgUsed[m]) + " su " + F0(g_mgSeen[m])) + Td(MgRuleLbl(bR[m], m)) + Td(bIs[m] > 0.0 ? MgCapLbl(pC[m], t) : string("nessuna (netto non positivo)")) +
        Td(F1(bGross[m]), ColSign(bGross[m])) + Td(F1(bIs[m]), ColSign(bIs[m])) + Td("<b>" + F1(bOos[m]) + "</b>", ColSign(bOos[m])) +
        Td(Mny(bOos[m]), ColSign(bOos[m])) + Td(F2(bOosT[m]), ColT(bOosT[m])) + Td(F0(bStop[m]) + "%") + es + "</tr>");
      g_dg += "MGMTBEST|" + g_tfName[t] + "|" + MgRuleDg(bR[m], m) + "|hold|" + IS(g_hor[pC[m]]) +
              "|signals|" + F0(g_mgUsed[m]) + "|gross|" + F1(bGross[m]) + "|netis|" + F1(bIs[m]) + "|netoos|" + F1(bOos[m]) + "|oosn|" + F0(bOosN[m]) + "|oost|" + F2(bOosT[m]) +
              "|stoppct|" + F0(bStop[m]) + "\n";
     }
   W("</table>");
   const double expPos = 0.0228 * (double)nEval;
   W("<div class='note'>TF con netto fuori campione positivo e t &ge; 2: <b>" + IS(nPos) + "</b> su " + IS(nEval) + " valutabili (per puro caso, con una scelta per TF, se ne attendono circa " + F1(expPos) +
     "). Il lordo &egrave; ci&ograve; che la sola direzione del segnale porta con quella gestione, senza costi: se &egrave; vicino a zero in tutte le combinazioni la gestione non crea un vantaggio, ridistribuisce soltanto vincite e perdite.</div>");

   //--- ritardo d'ingresso: la gestione scelta a ritardo 0 rifatta con tutti i ritardi
   int nRob = 0, nRobTested = 0, nLag0Pos = 0, nLag0Eval = 0;
   bool hasShort = false;
   for(int l = 0; l < nLag; l++) if(g_mgLag[l] >= 1 && g_mgLag[l] <= 5) hasShort = true;
   g_mgHasShort = hasShort;
   int nLag0PosNo = 0, nLag0PosUnk = 0;
   if(nLag > 1)
     {
      W("<h3>Ritardo d'ingresso: gestione e durata scelte in-sample a ritardo 0, rifatte entrando piu' tardi (netto medio fuori campione per segnale, pt)</h3>");
      W("<div class='note'>Se il netto crolla con pochi minuti di ritardo il vantaggio era una dislocazione del prezzo d'ingresso (lo scatto che segue la chiusura del segnale), non operabile da un EA che entra qualche secondo o minuto dopo. "
        "Colonna finale: <b>SI</b> se il netto fuori campione e' positivo a ritardo 0 e a tutti i ritardi provati da 1 a 5 min (serve almeno un ritardo fra 1 e 5 in InpMgmtLags: " + string(hasShort ? "presente" : "<b>assente, la colonna non e' valutabile</b>") + "), <b>NO</b> se almeno uno di questi e' negativo, n.d. se manca il campione. " +
        string(InpEntryLagMin > 0 ? ("Il ritardo di base InpEntryLagMin = " + IS(InpEntryLagMin) + " min e' gia' compreso: le colonne mostrano il ritardo totale dalla chiusura del segnale. ") : "") +
        "I segnali senza barre M1 contigue fino all'ingresso ritardato sono esclusi da quel ritardo: il numero di segnali per ritardo e' nel suggerimento della cella e nel digest (oosn).</div>");
      W("<table><tr><th>TF</th><th>Gestione</th><th>Durata</th>");
      for(int l = 0; l < nLag; l++) W("<th>+" + IS(InpEntryLagMin + g_mgLag[l]) + " min</th>");
      W("<th>" + string(InpEntryLagMin > 0 ? "Regge fino a +5 min oltre il ritardo di base?" : "Regge fino a 5 min?") + "</th></tr>");
      for(int m = 0; m < nM; m++)
        {
         if(bR[m] < 0) continue;
         const int t = g_mgTf[m];
         string cells = "";
         bool anyNeg = false, anyUnk = false;
         string lt = g_tfName[t] + ": ";
         for(int l = 0; l < nLag; l++)
           {
            double n0, a0, b0, g0, s0, n1, a1, b1, g1, s1;
            MgSum(l, m, bR[m], pC[m], 0, n0, a0, b0, g0, s0);
            MgSum(l, m, bR[m], pC[m], 1, n1, a1, b1, g1, s1);
            const double mo = (n1 > 0.0) ? a1 / n1 : 0.0;
            const double tt = MgClT(l, m, bR[m], pC[m], 1);
            if(n1 < minOos) { cells += Td("OOS scarso", "#4c566a"); if(g_mgLag[l] <= 5) anyUnk = true; }
            else
              {
               cells += "<td style='color:" + ColSign(mo) + "' title='segnali fuori campione " + F0(n1) + ", lordo " + F1(g1 / n1) + ", netto in-sample " + F1(n0 > 0.0 ? a0 / n0 : 0.0) + ", t " + F2(tt) + "'>" + F1(mo) + "</td>";
               if(g_mgLag[l] <= 5 && mo <= 0.0) anyNeg = true;
               if(l == 0) { nLag0Eval++; if(mo > 0.0) nLag0Pos++; }
              }
            lt += string(l > 0 ? ", " : "") + "+" + IS(InpEntryLagMin + g_mgLag[l]) + " min " + string(n1 >= minOos ? Sg(mo) : string("n.d."));
            g_dg += "MGMTLAG|" + g_tfName[t] + "|lag|" + IS(g_mgLag[l]) + "|total|" + IS(InpEntryLagMin + g_mgLag[l]) + "|" + MgRuleDg(bR[m], m) + "|hold|" + IS(g_hor[pC[m]]) + "|oosn|" + F0(n1) + "|gross|" + string(n1 > 0.0 ? F1(g1 / n1) : string("-")) +
                    "|netis|" + string(n0 > 0.0 ? F1(a0 / n0) : string("-")) + "|netoos|" + string(n1 > 0.0 ? F1(mo) : string("-")) + "|oost|" + F2(tt) + "\n";
           }
         string rbTxt;
         double l0n, l0a, l0b, l0g, l0s;
         MgSum(0, m, bR[m], pC[m], 1, l0n, l0a, l0b, l0g, l0s);
         const bool lag0Pos = (l0n >= minOos && l0a > 0.0);
         const bool negLag = (hasShort && anyNeg);          // senza ritardi da 1 a 5 min nel gruppo il giudizio non e' valutabile: il solo ritardo 0 negativo non basta per dire NO
         if(negLag) { rbTxt = Td("NO", "#bf616a"); nRobTested++; if(lag0Pos) nLag0PosNo++; }
         else if(anyUnk || !hasShort) { rbTxt = Td("n.d.", "#4c566a"); if(lag0Pos) nLag0PosUnk++; }
         else { rbTxt = Td("<b>SI</b>", "#a3be8c"); nRob++; nRobTested++; }
         g_cdLag[g_curSet * g_nT + t] = "netto medio fuori campione per segnale con la gestione scelta a ritardo 0, per ritardo d'ingresso dalla chiusura del segnale: " + StringSubstr(lt, StringLen(g_tfName[t]) + 2) + "; regge fino a 5 min (positivo a tutti i ritardi da 1 a 5): " +
                                        string(negLag ? "NO" : ((anyUnk || !hasShort) ? "non valutabile" : "SI"));
         W("<tr><td>" + g_tfName[t] + "</td>" + Td(MgRuleLbl(bR[m], m)) + Td(MgCapLbl(pC[m], t)) + cells + rbTxt + "</tr>");
        }
      W("</table>");
      string verd;
      if(!hasShort) verd = "InpMgmtLags non contiene ritardi fra 1 e 5 min: la tenuta dell'ingresso ritardato non e' valutabile.";
      else if(nLag0Eval == 0) verd = "Nessun TF ha un campione fuori campione sufficiente: ritardo non valutabile.";
      else if(nLag0Pos == 0) verd = "Nessun TF ha un netto fuori campione positivo gia' a ritardo 0 (" + IS(nLag0Eval) + " valutabili): il ritardo non e' la causa, manca il vantaggio da perdere.";
      else if(nRob == 0)
         verd = string(nLag0Pos == 1 ? "L'unico TF con netto positivo a ritardo 0 non risulta positivo" : ("Dei " + IS(nLag0Pos) + " TF con netto positivo a ritardo 0 nessuno risulta positivo")) + " a tutti i ritardi fino a 5 min (" + IS(nLag0PosNo) + " con almeno un ritardo negativo, " + IS(nLag0PosUnk) + " non valutabili per campione scarso): " +
                "puo' essere rumore o una dislocazione del prezzo d'ingresso, e con questi dati non sono distinguibili; in nessun caso il risultato e' operabile.";
      else verd = "I TF che reggono sono candidati, non conferme: la gestione e' scelta sul primo periodo e il criterio e' il solo segno del netto medio (senza t).";
      g_cMgmt4 = "Ritardo d'ingresso (minuti dalla chiusura del segnale" + string(InpEntryLagMin > 0 ? (", compreso il ritardo di base " + IS(InpEntryLagMin)) : "") + ", tutti provati insieme: " + MgLagTotList() + "), con la gestione e la durata scelte in-sample a ritardo 0 (netto medio fuori campione per segnale in punti, per TF nella scheda di ogni time frame). " +
                 "TF con netto fuori campione positivo a ritardo 0: " + IS(nLag0Pos) + " su " + IS(nLag0Eval) + " valutabili" +
                 string(hasShort ? ("; positivo anche a tutti i " + string(InpEntryLagMin > 0 ? "ritardi aggiuntivi" : "ritardi") + " da 1 a 5 min: " + IS(nRob)) : "") + ". " + verd;
     }

   //--- selezione di orari e giorni
   MgSelRes sres[];
   ArrayResize(sres, nM);
   for(int m = 0; m < nM; m++) sres[m].ok = false;
   int nSelTf = 0, nSelEval = 0, nBetter = 0, nSelPos = 0;
   const double selPct = 90.0;                 // un indizio solo se la selezione batte almeno questa quota di scelte casuali
   if(InpMgmtSelect)
     {
      W("<h3>Selezione di orari e giorni: scelti sul primo periodo, verificati sul resto</h3>");
      W("<div class='note'>Per la gestione e la durata scelte di ogni TF i risultati dei segnali sono divisi in celle <b>ora x giorno della settimana</b> (ora d'ingresso server + offset, ritardo 0). "
        "Sul primo periodo si scelgono le celle con almeno " + IS(InpSelMinCell) + " segnali, netto positivo e t &ge; " + F1(InpSelMinT) + "; la colonna <b>fuori campione</b> misura la sola selezione sul resto del periodo. "
        "Sul periodo di scelta la curva migliora per costruzione (la selezione e' fatta guardando quei dati): conta solo se migliora anche dopo. "
        "<b>Batte</b> = quota di scelte casuali dello stesso numero di celle (500 estrazioni fra le celle ammissibili) che fanno peggio della selezione sul fuori campione: senza alcuna informazione questa quota e' sparsa fra 0% e 100% e supera il " + F0(selPct) + "% in circa 1 TF su 10 per puro caso. "
        "Una selezione e' valutabile solo con almeno una cella scelta, 30 segnali e 15 giorni distinti fuori campione. "
        "La curva cumulata (tutti i segnali contro le sole celle scelte) e' nel dettaglio di ogni TF.</div>");
      W("<table><tr><th>TF</th><th>Celle scelte / ammissibili</th><th>Fuori campione: tutti i segnali (n, netto pt)</th><th>Fuori campione: solo celle scelte (n, giorni, netto pt)</th><th>t</th><th>Batte le scelte casuali</th><th>Esito</th></tr>");
      string selTx = "";
      for(int m = 0; m < nM; m++)
        {
         sres[m].ok = false;
         if(bR[m] < 0) continue;
         const int t = g_mgTf[m];
         if(IsStopped()) break;
         if(!MgSelect(m, bR[m], pC[m], sres[m]))
           {
            W("<tr class='thin'><td>" + g_tfName[t] + "</td><td colspan='6'>campione insufficiente</td></tr>");
            selTx += g_tfName[t] + ": campione insufficiente; ";
            g_cdSel[g_curSet * g_nT + t] = "campione insufficiente";
            continue;
           }
         nSelTf++;
         const MgSelRes q = sres[m];
         const bool evalOk = (q.nSel >= 1 && q.selN >= MathMax(30.0, minOos) && q.selDays >= 15);
         if(evalOk) nSelEval++;
         string es;
         if(q.nSel < 1) es = Td("nessuna cella scelta", "#4c566a");
         else if(!evalOk) es = Td("OOS scarso", "#4c566a");
         else if(q.selMean > 0.0 && q.selT >= 2.0 && q.pct >= selPct) { es = Td("<b>positivo, t &ge; 2 (da confermare)</b>", "#a3be8c"); nSelPos++; }
         else if(q.selMean > q.allMean) es = Td("migliora ma non basta", "#ebcb8b");
         else es = Td("NO", "#bf616a");
         if(evalOk && q.selMean > q.allMean) nBetter++;
         W("<tr><td>" + g_tfName[t] + "</td>" + Td(IS(q.nSel) + " / " + IS(q.nElig)) + Td(F0(q.allN) + ", " + F1(q.allMean), ColSign(q.allMean)) +
           Td(q.nSel > 0 ? (F0(q.selN) + ", " + IS(q.selDays) + " gg, <b>" + F1(q.selMean) + "</b>") : string("-"), ColSign(q.selMean)) + Td(q.nSel > 0 ? F2(q.selT) : string("-"), ColT(q.selT)) +
           Td(q.pct >= 0.0 ? (F0(q.pct) + "%") : string("-")) + es + "</tr>");
         g_dg += "MGMTSEL|" + g_tfName[t] + "|" + MgRuleDg(bR[m], m) + "|hold|" + IS(g_hor[pC[m]]) + "|cells|" + IS(q.nSel) + "|elig|" + IS(q.nElig) + "|isn|" + F0(q.isN) + "|isnet|" + F1(q.isMean) +
                 "|alln|" + F0(q.allN) + "|allnet|" + F1(q.allMean) + "|allt|" + F2(q.allT) + "|seln|" + F0(q.selN) + "|seldays|" + IS(q.selDays) + "|selnet|" + F1(q.selMean) + "|selt|" + F2(q.selT) +
                 "|beats|" + string(q.pct >= 0.0 ? F0(q.pct) : string("na")) + "|eval|" + IS(evalOk ? 1 : 0) + "\n";
         string one;
         if(q.nSel < 1) one = "nessuna cella scelta su " + IS(q.nElig);
         else
           {
            one = Pl(q.nSel, "cella scelta", "celle scelte") + " su " + IS(q.nElig) + " (" + g_mgSelTop[m] + "); ";
            if(q.selN < 1.0) one += "nessun segnale fuori campione nelle celle scelte";
            else
               one += "fuori campione " + Sg(q.selMean) + " pt su " + F0(q.selN) + " segnali e " + IS(q.selDays) + " giorni (t " + F2(q.selT) + ", " +
                      string(q.pct >= 0.0 ? ("batte il " + F0(q.pct) + "% delle scelte casuali") : string("confronto con le scelte casuali non calcolabile")) + ") contro " + Sg(q.allMean) + " pt di tutti i " + F0(q.allN) + " segnali" +
                      string(evalOk ? "" : " (campione scarso: non valutabile)");
           }
         selTx += g_tfName[t] + ": " + one + "; ";
         g_cdSel[g_curSet * g_nT + t] = one;
         if(evalOk) g_cdEval[g_curSet * g_nT + t]++;
         if(evalOk && q.selMean > 0.0 && q.selT >= 2.0 && q.pct >= selPct) CdPos(g_curSet * g_nT + t, "orari e giorni");
        }
      W("</table>");
      if(nSelTf == 0 && selTx != "")
         g_cMgmt5 = "Selezione di orari e giorni richiesta ma non valutabile: " + selTx;
      if(nSelTf > 0)
        {
         g_cMgmt5 = "Selezione di orari e giorni: celle ora x giorno della settimana scelte sul primo periodo (almeno " + IS(InpSelMinCell) + " segnali, netto positivo, t >= " + F1(InpSelMinT) + ") con la gestione scelta per ogni TF, poi misurate sul resto (il dettaglio di ogni TF e' nella sua scheda). " +
                    string(nSelEval == 0 ?
                    "Nessun TF e' valutabile (serve almeno una cella scelta, 30 segnali e 15 giorni fuori campione): non emerge evidenza ne' a favore ne' contro la selezione. " :
                    ("Su " + IS(nSelEval) + " TF valutabili la selezione ha battuto tutti i segnali fuori campione in " + IS(nBetter) + " (senza informazione ci si attende circa la meta', e i TF condividono gran parte dei segnali: non sono prove indipendenti) e ha dato un netto positivo con t >= 2 e sopra il " + F0(selPct) + "% delle scelte casuali in " + IS(nSelPos) + ". " +
                     string(nSelPos == 0 ? "Nessun TF mostra un miglioramento significativo sul periodo di verifica: non emerge evidenza che scegliere orari e giorni guardando lo storico aiuti. " :
                            "I TF positivi sono candidati da confermare su altri simboli e periodi (con 168 celle per TF qualche risultato positivo e' atteso per caso). "))) +
                    "La curva cumulata e' nel report HTML, nel dettaglio di ogni TF; tutte le celle scelte sono nel digest (MGMTSELCELL).";
        }
     }

   //--- scansione automatica dei filtri dell'EA
   RepFilters(g_curSet, bR, pC, minIs, minOos);

   //--- dettaglio per TF
   for(int m = 0; m < nM; m++)
     {
      const int t = g_mgTf[m];
      if(bR[m] < 0) continue;
      W("<details><summary><b>" + g_tfName[t] + "</b> &mdash; dettaglio per gestione e durata, per orario e per cella ora x giorno</summary>");
      W("<h3>" + g_tfName[t] + ": netto medio per segnale (pt) per gestione e durata massima &mdash; lordo fra parentesi</h3>");
      W("<table><tr><th>Gestione</th>");
      for(int c = 0; c < nC; c++) W("<th>" + IS(g_hor[c]) + " min</th>");
      W("</tr>");
      for(int r = 0; r < R; r++)
        {
         W("<tr><td>" + MgRuleLbl(r, m) + "</td>");
         for(int c = 0; c < nC; c++)
           {
            double n, sn, sn2, sg, ss, n0, a0, b0, g0, s0, n1, a1, b1, g1, s1;
            MgSum(0, m, r, c, -1, n, sn, sn2, sg, ss);
            MgSum(0, m, r, c, 0, n0, a0, b0, g0, s0);
            MgSum(0, m, r, c, 1, n1, a1, b1, g1, s1);
            if(n < 1.0) { W("<td>-</td>"); continue; }
            const string tip = " title='segnali " + F0(n) + ", in-sample " + F1(n0 > 0.0 ? a0 / n0 : 0.0) + ", fuori campione " + F1(n1 > 0.0 ? a1 / n1 : 0.0) + ", uscite per stop o target " + F0(100.0 * ss / n) + "%'";
            const bool isBest = (r == bR[m] && c == pC[m]);
            W("<td style='color:" + ColSign(sn / n) + string(isBest ? ";font-weight:bold;border:1px solid #88c0d0" : "") + "'" + tip + ">" + F1(sn / n) + " (" + F1(sg / n) + ")</td>");
            g_dg += "MGMT|" + g_tfName[t] + "|" + MgRuleDg(r, m) + "|hold|" + IS(g_hor[c]) + "|n|" + F0(n) + "|gross|" + F1(sg / n) +
                    "|net|" + F1(sn / n) + "|netis|" + F1(n0 > 0.0 ? a0 / n0 : 0.0) + "|netoos|" + F1(n1 > 0.0 ? a1 / n1 : 0.0) + "|stoppct|" + F0(100.0 * ss / n) + "\n";
           }
         W("</tr>");
        }
      W("</table>");
      //--- per orario, con la gestione scelta
      W("<h3>" + g_tfName[t] + ": per orario d'ingresso con " + MgRuleLbl(bR[m], m) + ", durata massima " + MgCapLbl(pC[m], t) + "</h3>");
      W("<table><tr><th>Fascia (server + offset)</th><th>Segnali</th><th>Lordo medio (pt)</th><th>Netto medio (pt)</th><th>Netto in-sample</th><th>Netto fuori campione</th><th>Fra le due parti</th></tr>");
      for(int rb = 0; rb < g_nRB; rb++)
        {
         double n[2], sn[2], sg[2];
         for(int s = 0; s < 2; s++)
           {
            const int p = ((((m * g_nRB + rb) * R + bR[m]) * nC + pC[m]) * 2 + s) * MGF;
            n[s] = g_mgAcc[p]; sn[s] = g_mgAcc[p + 1]; sg[s] = g_mgAcc[p + 3];
           }
         const double nt = n[0] + n[1];
         if(nt < 1.0) continue;
         const bool thin = (nt < (double)InpMinPerBucket);
         string cons;
         if(n[0] < 10.0 || n[1] < 5.0) cons = "campione scarso";
         else if(sn[0] / n[0] > 0.0 && sn[1] / n[1] > 0.0) cons = "coerente +";
         else if(sn[0] / n[0] < 0.0 && sn[1] / n[1] < 0.0) cons = "coerente -";
         else cons = "INCOERENTE";
         W("<tr" + string(thin ? " class='thin'" : "") + "><td>" + RBktLabel(rb) + "</td>" + Td(F0(nt)) + Td(F1((sg[0] + sg[1]) / nt)) + Td(F1((sn[0] + sn[1]) / nt), ColSign(sn[0] + sn[1])) +
           Td(n[0] > 0.0 ? F1(sn[0] / n[0]) : "-") + Td(n[1] > 0.0 ? F1(sn[1] / n[1]) : "-") + Td(cons) + "</tr>");
         g_dg += "MGMTH|" + g_tfName[t] + "|" + RBktLabel(rb) + "|n|" + F0(nt) + "|gross|" + F1((sg[0] + sg[1]) / nt) + "|net|" + F1((sn[0] + sn[1]) / nt) +
                 "|netis|" + (n[0] > 0.0 ? F1(sn[0] / n[0]) : string("-")) + "|netoos|" + (n[1] > 0.0 ? F1(sn[1] / n[1]) : string("-")) + "\n";
        }
      W("</table>");
      if(InpMgmtSelect && sres[m].ok)
        {
         W("<h3>" + g_tfName[t] + ": curva cumulata del netto per segnale (pt) &mdash; tutti i segnali contro le sole celle ora x giorno scelte in-sample</h3>");
         if(g_mgSvg[m] != "") W(g_mgSvg[m]);
         W("<div class='note'>Somma dei netti dei segnali in ordine di tempo (una posizione per segnale, lotto fisso, senza reinvestire e senza limiti di margine: le posizioni si sovrappongono). A sinistra della linea tratteggiata e' il periodo in cui le celle sono state scelte, a destra il periodo di verifica.</div>");
         if(g_mgSelTab[m] != "") { W("<h3>" + g_tfName[t] + ": celle scelte (le prime 14 per netto in-sample)</h3>"); W(g_mgSelTab[m]); }
        }
      W("</details>");
     }

   //--- elenco completo per TF (per il riepilogo copiabile)
   {
    for(int m = 0; m < nM; m++)
      {
       const int t = g_mgTf[m];
       if(bR[m] < 0) { g_cdMg[g_curSet * g_nT + t] = "campione insufficiente (" + IS(g_mgUsed[m]) + " segnali simulati)"; continue; }
       const string es2 = VerdText(OosVerdict(bOosN[m] < minOos, bOos[m], bOosT[m] >= 2.0));
       const string one2 = MgRuleLbl(bR[m], m) + ", " +
              string(bIs[m] > 0.0 ? ("durata massima consigliata " + MgCapLbl(pC[m], t)) : ("nessuna durata ha netto in-sample positivo (la meno negativa: " + IS(g_hor[bC[m]]) + " min)")) +
              ", lordo fuori campione " + Sg(bGross[m]) + " pt, netto in-sample " + Sg(bIs[m]) + " pt, netto fuori campione " + Sg(bOos[m]) + " pt" +
              string(g_money ? (" (" + MnyU(bOos[m]) + ")") : "") + " su " + F0(bOosN[m]) + " segnali, t " + F2(bOosT[m]) + ", uscite per stop o target " + F0(bStop[m]) + "%, esito " + es2;
       g_cdMg[g_curSet * g_nT + t] = one2;
      }
    //--- orari migliori (in-sample) dei cinque TF con il miglior netto fuori campione
    bool usedM[];
    ArrayResize(usedM, nM);
    ArrayInitialize(usedM, false);
    string hrs = "";
    for(int q = 0; q < 5; q++)
      {
       int mm = -1;
       for(int m = 0; m < nM; m++)
          if(!usedM[m] && bR[m] >= 0 && bOosN[m] >= minOos && (mm < 0 || bOos[m] > bOos[mm])) mm = m;
       if(mm < 0) break;
       usedM[mm] = true;
       bool usedB[];
       ArrayResize(usedB, g_nRB);
       ArrayInitialize(usedB, false);
       string h3 = "";
       for(int z = 0; z < 3; z++)
         {
          int bb = -1;
          double bv = -1.0e18;
          for(int rb = 0; rb < g_nRB; rb++)
            {
             if(usedB[rb]) continue;
             const int pa = ((((mm * g_nRB + rb) * R + bR[mm]) * nC + pC[mm]) * 2) * MGF;
             if(g_mgAcc[pa] < 20.0 || g_mgAcc[pa + MGF] < 8.0) continue;
             const double v = g_mgAcc[pa + 1] / g_mgAcc[pa];
             if(v > bv) { bv = v; bb = rb; }
            }
          if(bb < 0) break;
          usedB[bb] = true;
          const int pb = ((((mm * g_nRB + bb) * R + bR[mm]) * nC + pC[mm]) * 2) * MGF;
          h3 += string(z > 0 ? ", " : "") + RBktLabel(bb) + " (in-sample " + Sg(g_mgAcc[pb + 1] / g_mgAcc[pb]) + ", fuori campione " + Sg(g_mgAcc[pb + MGF + 1] / g_mgAcc[pb + MGF]) + ")";
         }
       if(h3 != "") hrs += g_tfName[g_mgTf[mm]] + ": " + h3 + "; ";
      }
    if(hrs != "")
       g_cMgmt3 = "Orari d'ingresso (server + offset) con il miglior netto in-sample per segnale, con la gestione scelta, per i cinque TF migliori fuori campione, con il netto fuori campione dello stesso orario (tre orari scelti fra " + IS(g_nRB) +
                  ", una parte e' rumore: conta solo se il fuori campione e' coerente e positivo; la tabella completa per orario e' nel report HTML e nel digest MGMTH): " + hrs;
   }

   //--- testo per il riepilogo
   string tx = string(g_mgNtp > 1 ? "Stop, trailing e take profit " : "Stop e trailing ") + uTxtS + " con durata massima, su " + IS(nM) + " TF, " + IS(R) + " gestioni x " + IS(nC) + " durate" + string(InpMgmtMaxSignals > 0 ? (" (campione fino a " + IS(InpMgmtMaxSignals) + " segnali per TF)") : "") + ": ";
   int bestM = -1;
   for(int m = 0; m < nM; m++)
      if(bR[m] >= 0 && bOosN[m] >= minOos && (bestM < 0 || bOos[m] > bOos[bestM])) bestM = m;
   if(bestM < 0)
      tx += "campione insufficiente per valutare i TF. ";
   else
     {
      tx += "TF con netto fuori campione positivo e t >= 2: " + IS(nPos) + " su " + IS(nEval) + " valutabili (per caso se ne attendono circa " + F1(expPos) + "). ";
      const int tb = g_mgTf[bestM];
      tx += "Il migliore fuori campione (" + string(nEval > 1 ? ("massimo fra " + IS(nEval) + " TF, quindi sovrastimato") : string("unico TF valutabile")) + ") e' " + g_tfName[tb] + " con " + MgRuleLbl(bR[bestM], bestM) + " e durata massima " + MgCapLbl(pC[bestM], tb) + ": lordo medio fuori campione " + Sg(bGross[bestM]) + " pt per segnale, netto in-sample " + Sg(bIs[bestM]) +
            " pt, netto fuori campione " + Sg(bOos[bestM]) + " pt" + string(g_money ? (" (" + MnyU(bOos[bestM]) + " a segnale con " + LotTxt() + " lotti)") : "") + " (t " + F2(bOosT[bestM]) + "). ";
      double sumG = 0.0, sumN = 0.0;
      int cnt = 0;
      for(int m = 0; m < nM; m++) if(bR[m] >= 0 && bOosN[m] >= minOos) { sumG += bGross[m]; sumN += bOos[m]; cnt++; }
      if(cnt > 0)
         tx += "Sulla media dei " + IS(cnt) + " TF valutabili la miglior gestione di ciascuno prende " + Sg(sumG / cnt) + " pt lordi e " + Sg(sumN / cnt) + " pt netti per segnale, entrambi fuori campione. ";
      if(nPos == 0)
         tx += "Nessuno dei " + IS(nEval) + " TF valutabili mostra un netto positivo e significativo fuori campione" + string(bOos[bestM] <= 0.0 ? ": anche il migliore ha netto non positivo, con queste gestioni i segnali non portano punti oltre i costi." : ": il migliore e' positivo ma senza t >= 2, non distinguibile dal caso.");
      else
         tx += "I TF positivi sono candidati da confermare su altri simboli e periodi, non conferme: la scelta della miglior gestione per TF e' ottimizzata sul primo periodo.";
     }
   g_cMgmt = tx;
   g_mgOn = true;
   g_mgPosTf = nPos; g_mgEvalTf = nEval; g_mgRobTf = nRob; g_mgRobTested = nRobTested; g_mgSelPosTf = nSelPos; g_mgSelEvalTf = nSelEval;
  }

//--- componenti della gestione simulata effettivamente provati in questa corsa, per i testi del riepilogo
string MgComps()
  {
   string tx = "stop, trailing";
   if(g_mgNtp > 1) tx += ", take profit";
   if(g_mgNlag > 1 && g_mgHasShort) tx += ", ritardo d'ingresso";
   if(InpMgmtSelect && g_mgSelEvalTf > 0) tx += ", selezione di orari e giorni";
   if(InpFilterScan && g_fsEvalTf > 0) tx += ", filtri ADX e regime di volatilita'";
   return tx;
  }

//--- frase sulla gestione simulata per il paragrafo di fattibilita' dell'EA; 'closing' aggiunge la conclusione (solo dove non contraddice il resto del paragrafo)
string MgFeasTxt(const bool closing)
  {
   if(!g_mgOn) return "";
   if(g_mgEvalTf < 1) return " Gestione simulata: campione fuori campione insufficiente in tutti i TF, non valutabile.";
   string tx = " Gestione simulata (" + MgComps() + " e durata massima, tutte le griglie provate): TF con netto fuori campione positivo e t >= 2: " + IS(g_mgPosTf) + " su " + IS(g_mgEvalTf) + " valutabili; ";
   if(g_mgNlag > 1 && g_mgHasShort && g_mgRobTested > 0)
      tx += "fra quelli con ritardo valutabile, positivi per segno (senza t) a tutti i " + string(InpEntryLagMin > 0 ? "ritardi aggiuntivi" : "ritardi") + " da 1 a 5 min: " + IS(g_mgRobTf) + " su " + IS(g_mgRobTested) + "; ";
   if(InpMgmtSelect && g_mgSelEvalTf > 0) tx += "TF con la selezione di orari e giorni positiva e significativa fuori campione: " + IS(g_mgSelPosTf) + " su " + IS(g_mgSelEvalTf) + " valutabili; ";
   if(InpFilterScan && g_fsEvalTf > 0) tx += "TF con la variante di filtri (ADX, regime) scelta in-sample positiva, significativa e migliore di nessun filtro fuori campione: " + IS(g_fsPosTf) + " su " + IS(g_fsEvalTf) + " valutabili; ";
   if(closing)
      tx += string((g_mgPosTf == 0 && g_mgSelPosTf == 0 && g_fsPosTf == 0) ?
                   "dai dati non emerge evidenza significativa di fattibilita' con la gestione provata." :
                   "i TF positivi sono candidati da confermare su altri simboli e periodi, non conferme.");
   return tx;
  }

//+------------------------------------------------------------------+
//| SCANSIONE DEI PARAMETRI DEL SEGNALE DELTA                         |
//| Prova tutte le combinazioni di EmaPeriod, VolAvgPeriod e          |
//| SignalThreshold (liste InpSweepEma, InpSweepVol, InpSweepThr) su  |
//| ogni TF scelto: ricalcola i segnali Delta per ogni combinazione e |
//| li valuta con UNA gestione fissa (InpSweepSl/Trail/Tp/Hold, nelle |
//| stesse unita' della gestione simulata), con gli stessi costi,     |
//| ritardo, filtri dell'EA e divisione in-sample / fuori campione    |
//| del resto dello script. La combinazione migliore e' scelta sul    |
//| primo periodo e verificata sul resto; il massimo atteso per caso  |
//| cresce con il numero di combinazioni provate (sqrt(2 ln m)).      |
//+------------------------------------------------------------------+
int     g_swQ = 0, g_swTfN = 0;      // combinazioni e TF della scansione dei parametri eseguita (0 = non eseguita)
string  g_swNote = "";               // perche' la scansione non e' stata eseguita
#define SWF 8   // campi per combinazione: 0 n in-sample, 1 netto medio IS, 2 t IS, 3 n fuori campione, 4 netto medio OOS, 5 t OOS, 6 lordo medio OOS, 7 segnali validi (prima del campionamento)

//--- indice M1 d'ingresso di ogni barra del TF (-1 se scartata): stesse regole di ProcessTF
void SweepEntries(const int t, const MqlRates &r[], const int n, int &ent[])
  {
   ArrayResize(ent, n);
   ArrayInitialize(ent, -1);
   const long xs = g_tfSec[t];
   const long maxGap = (long)InpMaxEntryGapMin * 60L;
   const long maxEnt = EntryGapLimit(t);
   const bool isMN = (g_tf[t] == PERIOD_MN1);
   int p = 0;
   for(int i = 0; i < n - 1; i++)
     {
      const datetime tNext = r[i+1].time;
      if(tNext < InpFrom || tNext > InpTo) continue;
      const long spacing = (long)(tNext - r[i].time);
      if(!isMN && (spacing - xs) > maxGap) continue;
      while(p < g_n1 && g_m1Time[p] < tNext) p++;
      if(p >= g_n1) break;
      if((long)(g_m1Time[p] - tNext) > maxEnt) continue;
      if(InSkipWin((long)g_m1Time[p])) continue;
      ent[i] = p;
     }
  }

//--- una combinazione di parametri su un TF: segnali Delta ricalcolati e valutati con la gestione fissa; scrive SWF campi in out[ob..]
void SweepEval(const MqlRates &r[], const int n, const SDParams &p, const double &atrP[], const int &entM[], const bool &passF[], double &out[], const int ob)
  {
   char dir[];
   uchar bur[];
   const int warm = SD_BuildSignals(r, n, p, dir, bur);
   for(int f = 0; f < SWF; f++) out[ob + f] = 0.0;
   int nSig = 0;
   for(int i = warm; i < n - 1; i++) if(dir[i] != 0 && entM[i] >= 0 && passF[i]) nSig++;
   out[ob + 7] = (double)nSig;
   if(nSig < 1) return;
   const long capSig = (InpSweepMaxSignals > 0) ? (long)InpSweepMaxSignals : 2147483647L;
   const int stride = MathMax(1, (int)(((long)nSig + capSig - 1L) / capSig));
   double slp[], trd[], tpd[], ur[], S[], HW[], exitP[], gr[];
   bool opn[], okc[];
   int recBar[];
   uchar ex[];
   ArrayResize(slp, 1); ArrayResize(trd, 1); ArrayResize(tpd, 1); ArrayResize(ur, 1); ArrayResize(S, 1); ArrayResize(HW, 1); ArrayResize(exitP, 1);
   ArrayResize(opn, 1); ArrayResize(okc, 1); ArrayResize(recBar, 1); ArrayResize(gr, 1); ArrayResize(ex, 1);
   slp[0] = InpSweepSl; trd[0] = InpSweepTrail; tpd[0] = InpSweepTp;
   double cn[2], cs[2], cg[2], ca[2], cb[2], cc[2];
   for(int q = 0; q < 2; q++) { cn[q] = 0.0; cs[q] = 0.0; cg[q] = 0.0; ca[q] = 0.0; cb[q] = 0.0; cc[q] = 0.0; }
   int curDay = -1, curSmp = 0, seen = 0;
   double dS = 0.0, dN = 0.0;
   for(int i = warm; i < n - 1; i++)
     {
      if(dir[i] == 0 || entM[i] < 0 || !passF[i]) continue;
      seen++;
      if(((seen - 1) % stride) != 0) continue;
      const double atr = atrP[i];
      if(atr <= 0.0) continue;
      int jb = entM[i];
      if(InpEntryLagMin > 0)
        {
         const int jl = jb + InpEntryLagMin;
         if(jl >= g_n1 || (long)(g_m1Time[jl] - g_m1Time[jb]) != (long)InpEntryLagMin * 60L) continue;
         jb = jl;
        }
      const long tEnd = (long)g_m1Time[jb] + (long)InpSweepHold * 60L;
      const int e = MgLower(tEnd, jb);
      okc[0] = (e < g_n1 && e > jb && (g_nextBrk[jb] >= e || (g_nextBrk[jb] == e - 1 && (long)g_m1Time[e - 1] + 60L >= tEnd)));
      if(!okc[0]) continue;
      recBar[0] = e - 1;
      const double cost = ((InpCostPoints > 0.0) ? InpCostPoints : (double)g_m1Spr[jb]) + g_extraPts;
      ur[0] = InpMgmtPoints ? 1.0 : atr;
      MgSim(jb, (int)dir[i], ur, e, 1, 1, okc, recBar, slp, trd, tpd, S, HW, exitP, opn, gr, ex);
      const double nt = gr[0] - cost;
      const int smp = (g_m1Day[jb] >= g_splitDay) ? 1 : 0;
      const int day = g_m1Day[jb];
      if(day != curDay)
        {
         if(dN > 0.0) { ca[curSmp] += dS * dS; cb[curSmp] += dS * dN; cc[curSmp] += dN * dN; }
         dS = 0.0; dN = 0.0; curDay = day; curSmp = smp;
        }
      dS += nt; dN += 1.0;
      cn[smp] += 1.0; cs[smp] += nt; cg[smp] += gr[0];
     }
   if(dN > 0.0) { ca[curSmp] += dS * dS; cb[curSmp] += dS * dN; cc[curSmp] += dN * dN; }
   for(int s = 0; s < 2; s++)
     {
      if(cn[s] < 1.0) continue;
      const double mu = cs[s] / cn[s];
      const double tt = ClusterT(cn[s], mu, ca[s], cb[s], cc[s]);
      if(s == 0) { out[ob] = cn[0]; out[ob + 1] = mu; out[ob + 2] = tt; }
      else       { out[ob + 3] = cn[1]; out[ob + 4] = mu; out[ob + 5] = tt; out[ob + 6] = cg[1] / cn[1]; }
     }
  }

string SweepCombLbl(const int e, const int v, const double th)
  {
   return "EMA " + IS(e) + ", volume medio " + IS(v) + ", soglia " + ThrLbl(th);
  }

//--- scansione richiesta ma non eseguita: traccia nel log, nel report e nel riepilogo
void SweepSkip(const string why)
  {
   g_swNote = why;
   Print("Scansione dei parametri non eseguita: ", why);
   W("<div class='sec' style='order:7'><h1 class='setH'>Scansione dei parametri del segnale Delta</h1><div class='note ko'><b>Scansione non eseguita</b>: " + HtmlEsc(why) + "</div></div>");
   AddConc(-2, "Scansione dei parametri del segnale (EMA, volume medio, soglia)", "Scansione richiesta ma non eseguita: " + why);
  }

void RepSweep()
  {
   if(!InpSweep) return;
   int ema[], vol[], sTf[];
   double thr[];
   int nE = ParseIntList(InpSweepEma, ema);
   int nV = ParseIntList(InpSweepVol, vol);
   int nH = ParseDoubleList(InpSweepThr, thr);
   if(nE < 1 || nV < 1 || nH < 1)
     {
      SweepSkip("InpSweepEma, InpSweepVol o InpSweepThr non contengono valori validi.");
      return;
     }
   if(nE > 16) { nE = 16; Print("Scansione: InpSweepEma limitato ai primi 16 valori."); }
   if(nV > 12) { nV = 12; Print("Scansione: InpSweepVol limitato ai primi 12 valori."); }
   if(nH > 16) { nH = 16; Print("Scansione: InpSweepThr limitato ai primi 16 valori."); }
   const int nQ = nE * nV * nH;
   if(nQ > 1500)
     {
      SweepSkip(IS(nQ) + " combinazioni sono troppe (massimo 1500): riduci le liste InpSweepEma, InpSweepVol, InpSweepThr.");
      return;
     }
   string ignTf = "";
   const int nS = ParseTfSel(InpSweepTFs, sTf, ignTf);
   if(nS < 1)
     {
      SweepSkip("nessun TF valido in InpSweepTFs (devono essere fra quelli analizzati in InpTFs, M1 escluso)" + string(ignTf != "" ? (": ignorati " + ignTf) : "") + ".");
      return;
     }
   if(ignTf != "") Print("Scansione: TF ignorati in InpSweepTFs: ", ignTf);
   if(InpSweepSl <= 0.0 || InpSweepTrail < 0.0 || InpSweepTp < 0.0 || InpSweepHold < 1)
     {
      SweepSkip("InpSweepSl deve essere positivo, InpSweepTrail e InpSweepTp non negativi, InpSweepHold almeno 1 minuto.");
      return;
     }
   const double minIs = MathMax(30.0, g_minN / 2.0);
   const double minOos = MathMax(10.0, minIs / 3.0);
   double res[];
   ArrayResize(res, nS * nQ * SWF);
   ArrayInitialize(res, 0.0);
   bool okS[];
   ArrayResize(okS, nS);
   string skipTx = "";
   for(int s = 0; s < nS; s++)
     {
      okS[s] = false;
      if(IsStopped()) return;
      const int t = sTf[s];
      MqlRates r[];
      const int n = LoadTF(t, r);
      if(n < 120) { Print("Scansione: TF ", g_tfName[t], " senza storico sufficiente (", n, ")."); skipTx += string(skipTx != "" ? ", " : "") + g_tfName[t]; g_cdSw[t] = "storico insufficiente per la scansione (" + IS(n) + " barre)"; continue; }
      int entM[];
      SweepEntries(t, r, n, entM);
      double adxv[];
      if(g_adxFilt) SD_Adx(r, n, MathMax(1, InpAdxPeriod), adxv);
      uchar vsc[];
      if(g_regFilt) SD_VolState(r, n, g_vpar, g_pt, vsc);
      double atrM[], atrP[];
      SD_Atr(r, n, MathMax(2, InpMgmtAtrLen), atrM);
      ArrayResize(atrP, n);
      for(int i = 0; i < n; i++) atrP[i] = (i < ArraySize(atrM)) ? atrM[i] / g_pt : 0.0;
      bool passF[];
      ArrayResize(passF, n);
      for(int i = 0; i < n; i++) passF[i] = (g_adxFilt || g_regFilt) ? (FiltCode(adxv, vsc, i) == 0) : true;
      SDParams pr = g_par;
      pr.mode = SD_MODE_DELTA;
      for(int ie = 0; ie < nE; ie++)
         for(int iv = 0; iv < nV; iv++)
            for(int ih = 0; ih < nH; ih++)
              {
               if(IsStopped()) { ArrayFree(r); return; }
               const int q = (ie * nV + iv) * nH + ih;
               pr.emaPeriod = MathMax(1, ema[ie]);
               pr.volAvgPeriod = MathMax(1, vol[iv]);
               pr.threshold = thr[ih];
               SweepEval(r, n, pr, atrP, entM, passF, res, (s * nQ + q) * SWF);
              }
      ArrayFree(r);
      okS[s] = true;
      Comment("SignalLab MultiTF: scansione dei parametri ", g_tfName[t], " completata (", s + 1, "/", nS, ")");
      Print("Scansione dei parametri: TF ", g_tfName[t], " completato, ", nQ, " combinazioni.");
     }
   Comment("");

   //--- riepilogo e report
   const string uTxt = InpMgmtPoints ? string(" punti") : string(" ATR");
   const string ruleTxt = "stop " + GridLbl(InpSweepSl) + uTxt + ", " + string(InpSweepTrail > 0.0 ? ("trailing " + GridLbl(InpSweepTrail) + uTxt) : string("senza trailing")) + ", " +
                          string(InpSweepTp > 0.0 ? ("target " + GridLbl(InpSweepTp) + uTxt) : string("senza target")) + ", durata massima " + IS(InpSweepHold) + " min";
   g_dgSets += "### SWEEP\n";
   g_dgSets += "SWEEPCFG|serie|DELTA|ema|" + MgIntList(ema, nE) + "|vol|" + MgIntList(vol, nV) + "|thr|" + MgDblList(thr, nH) + "|unit|" + string(InpMgmtPoints ? "pt" : "atr") + "|sl|" + GridLbl(InpSweepSl) + "|trail|" + GridLbl(InpSweepTrail) +
               "|tp|" + GridLbl(InpSweepTp) + "|hold|" + IS(InpSweepHold) + "|atrlen|" + IS(InpMgmtAtrLen) + "|highfirst|" + IS(InpMgmtHighFirst ? 1 : 0) + "|maxsignals|" + IS(InpSweepMaxSignals) + "|minis|" + F0(minIs) + "|minoos|" + F0(minOos) +
               "|entrylag|" + IS(InpEntryLagMin) + "|filters|" + string(g_filtTxt != "" ? g_filtTxt : string("none")) + "\n";
   W("<div class='sec' style='order:7'>");
   W("<h1 class='setH'>Scansione dei parametri del segnale Delta: EmaPeriod x VolAvgPeriod x SignalThreshold</h1>");
   W("<div class='note'>Per ogni TF e per ognuna delle <b>" + IS(nQ) + "</b> combinazioni (" + IS(nE) + " livelli di EmaPeriod x " + IS(nV) + " di VolAvgPeriod x " + IS(nH) + " di SignalThreshold) i segnali del solo Synthetic Delta sono ricalcolati e valutati con la <b>stessa gestione fissa</b>: " + ruleTxt +
     " (unit&agrave; come la gestione simulata), con costi, ritardo d'ingresso, filtri dell'EA e divisione in-sample / fuori campione del resto del report. "
     "La combinazione migliore e' scelta <b>sul primo periodo</b> e il suo risultato sul resto &egrave; l'unico che conta. Provando " + IS(nQ) + " combinazioni il miglior t in-sample cresce per puro caso (circa &radic;(2 ln m)): "
     "ci&ograve; che interessa &egrave; se le combinazioni vicine fanno lo stesso (un altopiano) o se il migliore &egrave; un picco isolato. " + string(InpSweepMaxSignals > 0 ? ("Si valuta un campione uniforme fino a " + IS(InpSweepMaxSignals) + " segnali per combinazione e TF. ") : "Nessun limite al campione di segnali per combinazione. ") +
     "Livelli: EmaPeriod " + MgIntList(ema, nE) + "; VolAvgPeriod " + MgIntList(vol, nV) + "; SignalThreshold " + MgDblList(thr, nH) + ".</div>");
   int tfLoaded = 0, tfEval = 0, tfOos = 0, tfStrong = 0, tfPosOos = 0;
   for(int s = 0; s < nS; s++)
     {
      if(!okS[s]) continue;
      const int t = sTf[s];
      tfLoaded++;
      const int ob0 = s * nQ * SWF;
      //--- combinazioni valide e conteggi
      int m = 0, nBoth = 0, nStrong = 0, nOosPos = 0, nIsPos = 0;
      for(int q = 0; q < nQ; q++)
        {
         const int ob = ob0 + q * SWF;
         if(res[ob] < minIs) continue;
         m++;
         const bool isPos = (res[ob + 1] > 0.0);
         if(isPos) nIsPos++;
         if(res[ob + 3] < minOos) continue;
         if(res[ob + 4] > 0.0) nOosPos++;
         if(isPos && res[ob + 4] > 0.0) nBoth++;
         if(isPos && res[ob + 4] > 0.0 && res[ob + 5] >= 2.0) nStrong++;
        }
      W("<h2>" + g_tfName[t] + ": " + IS(m) + " combinazioni con almeno " + F0(minIs) + " segnali in-sample</h2>");
      if(m < 1)
        {
         W("<div class='note ko'>Nessuna combinazione con campione sufficiente su questo TF.</div>");
         g_cdSw[t] = "campione insufficiente (nessuna combinazione con almeno " + F0(minIs) + " segnali in-sample)";
         continue;
        }
      tfEval++;
      //--- migliori in-sample
      bool usedQ[];
      ArrayResize(usedQ, nQ);
      ArrayInitialize(usedQ, false);
      int bestQ = -1;
      W("<h3>Le 12 combinazioni migliori scelte sul primo periodo (netto medio per segnale, pt)</h3>");
      W("<table><tr><th>Combinazione</th><th>Segnali in-sample</th><th>Netto in-sample</th><th>t in-sample</th><th>Segnali fuori campione</th><th>Lordo fuori campione</th><th>Netto fuori campione</th><th>t fuori campione</th><th>Esito</th></tr>");
      for(int z = 0; z < 12; z++)
        {
         int bq = -1;
         double bv = -1.0e18;
         for(int q = 0; q < nQ; q++)
           {
            if(usedQ[q] || res[ob0 + q * SWF] < minIs) continue;
            if(res[ob0 + q * SWF + 1] > bv) { bv = res[ob0 + q * SWF + 1]; bq = q; }
           }
         if(bq < 0) break;
         usedQ[bq] = true;
         if(z == 0) bestQ = bq;
         const int ob = ob0 + bq * SWF;
         const int ih = bq % nH, iv = (bq / nH) % nV, ie = bq / (nH * nV);
         const string es = VerdCell(OosVerdict(res[ob + 3] < minOos, res[ob + 4], res[ob + 5] >= 2.0));
         W("<tr><td>" + SweepCombLbl(ema[ie], vol[iv], thr[ih]) + "</td>" + Td(F0(res[ob])) + Td(F1(res[ob + 1]), ColSign(res[ob + 1])) + Td(F2(res[ob + 2])) + Td(F0(res[ob + 3])) +
           Td(F1(res[ob + 6]), ColSign(res[ob + 6])) + Td("<b>" + F1(res[ob + 4]) + "</b>", ColSign(res[ob + 4])) + Td(F2(res[ob + 5]), ColT(res[ob + 5])) + es + "</tr>");
        }
      W("</table>");
      const int bo = ob0 + bestQ * SWF;
      const int bih = bestQ % nH, biv = (bestQ / nH) % nV, bie = bestQ / (nH * nV);
      const double chanceT = (m > 1) ? MathSqrt(2.0 * MathLog((double)m)) : 0.0;
      //--- vicini del migliore (un livello in piu' o in meno su ogni parametro): altopiano o picco
      double nbS = 0.0, nbN = 0.0, nbPos = 0.0;
      for(int de = -1; de <= 1; de++)
         for(int dv = -1; dv <= 1; dv++)
            for(int dh = -1; dh <= 1; dh++)
              {
               if(de == 0 && dv == 0 && dh == 0) continue;
               const int ne = bie + de, nv = biv + dv, nh = bih + dh;
               if(ne < 0 || ne >= nE || nv < 0 || nv >= nV || nh < 0 || nh >= nH) continue;
               const int nq = (ne * nV + nv) * nH + nh;
               const int nb = ob0 + nq * SWF;
               if(res[nb + 3] < minOos) continue;
               nbS += res[nb + 4]; nbN += 1.0;
               if(res[nb + 4] > 0.0) nbPos += 1.0;
              }
      const double nbMean = (nbN > 0.0) ? nbS / nbN : 0.0;
      string nbTx;
      if(nbN < 1.0) nbTx = "Nessuna combinazione vicina valutabile (un livello in piu' o in meno su ogni parametro)";
      else
        {
         string vd;
         const bool zonaPos = (nbMean > 0.0 && nbPos >= 0.6 * nbN);
         if(res[bo + 3] < minOos) vd = "migliore non valutabile fuori campione";
         else if(res[bo + 4] <= 0.0) vd = string(nbMean <= 0.0 ? "nessun vantaggio fuori campione ne' nel migliore ne' nella zona" : "il migliore e' negativo fuori campione ma la zona e' in media positiva: nessun picco da confermare");
         else if(zonaPos && res[bo + 5] >= 2.0) vd = "altopiano: il migliore e' significativo e la zona lo conferma";
         else if(zonaPos) vd = "zona in media positiva ma il migliore non e' significativo: altopiano debole";
         else vd = "picco isolato: il vicinato non conferma il migliore";
         nbTx = "Le " + Pl((long)nbN, "combinazione vicina valutabile", "combinazioni vicine valutabili") + " (un livello in piu' o in meno) fanno in media " + Sg(nbMean) + " pt fuori campione, positive " + F0(nbPos) + ": " + vd;
        }
      const string bestEs = VerdText(OosVerdict(res[bo + 3] < minOos, res[bo + 4], res[bo + 5] >= 2.0));
      if(res[bo + 3] >= minOos) tfOos++;
      if(res[bo + 3] >= minOos && res[bo + 4] > 0.0) tfPosOos++;
      if(res[bo + 3] >= minOos && res[bo + 4] > 0.0 && res[bo + 5] >= 2.0) tfStrong++;
      //--- combinazione attuale (parametri dell'EA impostati sopra)
      int curQ = -1;
      for(int ie = 0; ie < nE; ie++)
         for(int iv = 0; iv < nV; iv++)
            for(int ih = 0; ih < nH; ih++)
               if(ema[ie] == InpEmaPeriod && vol[iv] == InpVolAvgPeriod && MathAbs(thr[ih] - InpThreshold) < 1.0e-9) curQ = (ie * nV + iv) * nH + ih;
      string curTx;
      if(curQ < 0) curTx = "la combinazione impostata (EMA " + IS(InpEmaPeriod) + ", volume medio " + IS(InpVolAvgPeriod) + ", soglia " + ThrLbl(InpThreshold) + ") non e' nella griglia";
      else
        {
         const int co = ob0 + curQ * SWF;
         if(res[co] < minIs || res[co + 3] < minOos)
            curTx = "la combinazione impostata (EMA " + IS(InpEmaPeriod) + ", volume medio " + IS(InpVolAvgPeriod) + ", soglia " + ThrLbl(InpThreshold) + ") non e' valutabile (" + F0(res[co]) + " segnali in-sample, " + F0(res[co + 3]) + " fuori campione)";
         else
            curTx = "la combinazione impostata (EMA " + IS(InpEmaPeriod) + ", volume medio " + IS(InpVolAvgPeriod) + ", soglia " + ThrLbl(InpThreshold) + ") ha netto in-sample " + Sg(res[co + 1]) +
                    " pt e fuori campione " + Sg(res[co + 4]) + " pt (t " + F2(res[co + 5]) + ", " + F0(res[co + 3]) + " segnali)";
        }
      W("<div class='note'>Provate <b>" + Pl(m, "combinazione", "combinazioni") + "</b>: in-sample il netto &egrave; positivo in " + IS(nIsPos) + ", fuori campione in " + IS(nOosPos) + ", positivo in entrambi i periodi in <b>" + IS(nBoth) + "</b>, con t fuori campione &ge; 2 in <b>" + IS(nStrong) + "</b> (per puro caso, fra quelle con netto in-sample positivo, circa il 2.3%). "
        "La migliore in-sample (" + SweepCombLbl(ema[bie], vol[biv], thr[bih]) + ") ha t in-sample <b>" + F2(res[bo + 2]) + "</b>" + string(m > 1 ? (" contro un massimo atteso per caso di circa " + F2(chanceT)) : "") + ", e fuori campione " + Sg(res[bo + 4]) + " pt (t " + F2(res[bo + 5]) + "). " +
        nbTx + ". Inoltre " + curTx + ".</div>");
      //--- effetto di ogni parametro, media sulle altre combinazioni
      W("<details><summary>Effetto di ciascun parametro (media sulle altre combinazioni) e mappe soglia x EMA</summary>");
      string effTx = "";
      for(int pi = 0; pi < 3; pi++)
        {
         string effP = "";
         const int nL = (pi == 0) ? nE : ((pi == 1) ? nV : nH);
         W("<h3>" + g_tfName[t] + ": " + string(pi == 0 ? "EmaPeriod" : (pi == 1 ? "VolAvgPeriod" : "SignalThreshold")) + "</h3>");
         W("<table><tr><th>Livello</th><th>Combinazioni valide</th><th>Segnali medi in-sample</th><th>Netto in-sample medio</th><th>Netto fuori campione medio</th><th>Positive in entrambi</th></tr>");
         for(int lv = 0; lv < nL; lv++)
           {
            double cnt = 0.0, sIs = 0.0, sOo = 0.0, nIsS = 0.0, cOo = 0.0, both = 0.0;
            for(int q = 0; q < nQ; q++)
              {
               const int ih = q % nH, iv = (q / nH) % nV, ie = q / (nH * nV);
               const int idx = (pi == 0) ? ie : ((pi == 1) ? iv : ih);
               if(idx != lv) continue;
               const int ob = ob0 + q * SWF;
               if(res[ob] < minIs) continue;
               cnt += 1.0; sIs += res[ob + 1]; nIsS += res[ob];
               if(res[ob + 3] >= minOos) { sOo += res[ob + 4]; cOo += 1.0; if(res[ob + 1] > 0.0 && res[ob + 4] > 0.0) both += 1.0; }
              }
            const string lvl = (pi == 0) ? IS(ema[lv]) : ((pi == 1) ? IS(vol[lv]) : ThrLbl(thr[lv]));
            effP += string(lv > 0 ? ", " : "") + lvl + " " + string(cOo > 0.0 ? Sg(sOo / cOo) : string("n.d."));
            if(cnt < 1.0) { W("<tr class='thin'><td>" + lvl + "</td><td colspan='5'>campione insufficiente</td></tr>"); continue; }
            W("<tr><td>" + lvl + "</td>" + Td(F0(cnt)) + Td(F0(nIsS / cnt)) + Td(F1(sIs / cnt), ColSign(sIs / cnt)) + Td(cOo > 0.0 ? F1(sOo / cOo) : string("-"), ColSign(cOo > 0.0 ? sOo / cOo : 0.0)) + Td(F0(both)) + "</tr>");
            g_dgSets += "SWEEPLV|" + g_tfName[t] + "|param|" + string(pi == 0 ? "ema" : (pi == 1 ? "vol" : "thr")) + "|level|" + lvl + "|combos|" + F0(cnt) + "|netis|" + F1(sIs / cnt) + "|netoos|" + string(cOo > 0.0 ? F1(sOo / cOo) : string("-")) + "|both|" + F0(both) + "\n";
           }
         W("</table>");
         effTx += string(pi == 0 ? "EmaPeriod" : (pi == 1 ? "VolAvgPeriod" : "SignalThreshold")) + " (" + effP + ")" + string(pi < 2 ? ", " : "");
        }
      for(int smpSel = 0; smpSel < 2; smpSel++)
        {
         W("<h3>" + g_tfName[t] + ": netto medio " + string(smpSel == 0 ? "in-sample" : "fuori campione") + " (pt), righe = soglia, colonne = EmaPeriod, media sui livelli di VolAvgPeriod</h3>");
         W("<table><tr><th>Soglia \\ EMA</th>");
         for(int ie = 0; ie < nE; ie++) W("<th>" + IS(ema[ie]) + "</th>");
         W("</tr>");
         for(int ih = 0; ih < nH; ih++)
           {
            W("<tr><td>" + ThrLbl(thr[ih]) + "</td>");
            for(int ie = 0; ie < nE; ie++)
              {
               double cnt = 0.0, sm = 0.0;
               for(int iv = 0; iv < nV; iv++)
                 {
                  const int ob = ob0 + ((ie * nV + iv) * nH + ih) * SWF;
                  if(smpSel == 0) { if(res[ob] < minIs) continue; sm += res[ob + 1]; cnt += 1.0; }
                  else { if(res[ob] < minIs || res[ob + 3] < minOos) continue; sm += res[ob + 4]; cnt += 1.0; }
                 }
               if(cnt < 1.0) W("<td>-</td>");
               else W("<td style='color:" + ColSign(sm / cnt) + "'>" + F1(sm / cnt) + "</td>");
              }
            W("</tr>");
           }
         W("</table>");
        }
      W("</details>");
      //--- digest
      for(int q = 0; q < nQ; q++)
        {
         const int ob = ob0 + q * SWF;
         if(res[ob + 7] < 1.0) continue;
         const int ih = q % nH, iv = (q / nH) % nV, ie = q / (nH * nV);
         g_dgSets += "SWEEP|" + g_tfName[t] + "|ema|" + IS(ema[ie]) + "|vol|" + IS(vol[iv]) + "|thr|" + ThrLbl(thr[ih]) + "|sig|" + F0(res[ob + 7]) + "|nis|" + F0(res[ob]) + "|netis|" + F1(res[ob + 1]) +
                     "|tis|" + F2(res[ob + 2]) + "|noos|" + F0(res[ob + 3]) + "|netoos|" + F1(res[ob + 4]) + "|toos|" + F2(res[ob + 5]) + "|grossoos|" + F1(res[ob + 6]) + "\n";
        }
      g_dgSets += "SWEEPBEST|" + g_tfName[t] + "|ema|" + IS(ema[bie]) + "|vol|" + IS(vol[biv]) + "|thr|" + ThrLbl(thr[bih]) + "|combos|" + IS(m) + "|netis|" + F1(res[bo + 1]) + "|tis|" + F2(res[bo + 2]) +
                  "|chance|" + F2(chanceT) + "|noos|" + F0(res[bo + 3]) + "|netoos|" + F1(res[bo + 4]) + "|toos|" + F2(res[bo + 5]) + "|neighbors|" + F0(nbN) + "|nbmean|" + F1(nbMean) + "|nbpos|" + F0(nbPos) +
                  "|both|" + IS(nBoth) + "|strong|" + IS(nStrong) + "\n";
      const string swTx = "su " + Pl(m, "combinazione valutabile", "combinazioni valutabili") + " la migliore in-sample e' " + SweepCombLbl(ema[bie], vol[biv], thr[bih]) + " (netto in-sample " + Sg(res[bo + 1]) + " pt, t " + F2(res[bo + 2]) +
               string(m > 1 ? (" contro un massimo atteso per caso di " + F2(chanceT)) : "") + "), fuori campione " + Sg(res[bo + 4]) + " pt su " + F0(res[bo + 3]) + " segnali (t " + F2(res[bo + 5]) + ", " + bestEs + "). " + nbTx +
               ". Positive in entrambi i periodi: " + IS(nBoth) + " su " + IS(m) + "; con t fuori campione >= 2: " + IS(nStrong) + " (per puro caso, fra le " + IS(nIsPos) + " con netto in-sample positivo, circa " + F1(0.0228 * (double)nIsPos) + "). " +
               "Netto fuori campione medio per livello, sulle altre combinazioni: " + effTx + ". Inoltre " + curTx;
      g_cdSw[t] = swTx;
      if(g_setMode[0] == SD_MODE_DELTA)               // la scheda del TF conta la scansione solo se la serie 0 e' il Delta
        {
         if(res[bo + 3] >= minOos) g_cdEval[t]++;
         if(res[bo + 3] >= minOos && res[bo + 4] > 0.0 && res[bo + 5] >= 2.0) CdPos(t, "scansione dei parametri");
        }
     }
   if(skipTx != "")
      W("<div class='note ko'>TF saltati per storico insufficiente: " + skipTx + ".</div>");
   if(ignTf != "")
      W("<div class='note ko'>TF di InpSweepTFs ignorati perche' non analizzati in InpTFs o non supportati: " + HtmlEsc(ignTf) + ".</div>");
   W("</div>");
   if(tfLoaded == 0)
      AddConc(-2, "Scansione dei parametri del segnale (EMA, volume medio, soglia)", "Scansione richiesta ma non eseguita: nessun TF con storico sufficiente" + string(skipTx != "" ? (" (" + skipTx + ")") : "") + ".");
   if(tfLoaded > 0)
     {
      g_swQ = nQ;
      g_swTfN = tfLoaded;
      string verd;
      if(tfEval == 0) verd = "Nessun TF ha un campione sufficiente per la scansione (nessuna combinazione con abbastanza segnali in-sample): non valutabile.";
      else if(tfOos == 0) verd = "Nessun TF ha un campione fuori campione sufficiente per la migliore combinazione: non valutabile.";
      else if(tfStrong == 0) verd = "Nessuna combinazione scelta in-sample dei tre parametri porta un netto positivo e significativo fuori campione: non emerge un vantaggio oltre i costi cambiando EMA, volume medio o soglia.";
      else verd = "I TF positivi sono candidati da confermare su altri simboli e periodi: con tante combinazioni provate il massimo in-sample e' gonfiato, conta l'altopiano delle combinazioni vicine e il fuori campione.";
      AddConc(-2, "Scansione dei parametri del segnale (EMA, volume medio, soglia)", "Provate " + Pl(nQ, "combinazione", "combinazioni") + " di EmaPeriod (" + MgIntList(ema, nE) + "), VolAvgPeriod (" + MgIntList(vol, nV) + ") e SignalThreshold (" + MgDblList(thr, nH) + ") del solo Synthetic Delta su " + Pl(tfLoaded, "TF", "TF") +
              ", ognuna valutata con la stessa gestione fissa (" + ruleTxt + ", costi e filtri come il resto della corsa), scelta della migliore sul primo periodo e verifica sul resto (il dettaglio di ogni TF e' nella sua scheda). " +
              string(skipTx != "" ? ("TF saltati per storico insufficiente: " + skipTx + ". ") : "") + string(ignTf != "" ? ("TF ignorati in InpSweepTFs: " + ignTf + ". ") : "") +
              "TF valutabili: " + IS(tfEval) + "; con un campione fuori campione sufficiente per la migliore: " + IS(tfOos) + "; migliore in-sample con netto fuori campione positivo: " + IS(tfPosOos) + "; con t >= 2: " + IS(tfStrong) + ". " + verd +
              " Le mappe soglia x EMA sono nel report HTML; tutte le combinazioni e i livelli sono nel digest (SWEEP, SWEEPBEST, SWEEPLV).");
     }
  }

//--- regola fissa dell'utente (InpFixedRule): TF, inizio fascia, verso, tenuta, target; false (con nota) se non valida o non presente nelle griglie
bool ParseFixedRule(int &t, int &rb, int &h, int &kk, int &dd)
  {
   g_fixedNote = "";
   string src = InpFixedRule;
   StringTrimLeft(src); StringTrimRight(src);
   if(src == "") return false;
   string pr[];
   if(StringSplit(src, ',', pr) != 5)
     { g_fixedNote = "InpFixedRule non valida: servono 5 campi TF,inizio fascia,SEGUI o INVERTI,tenuta,target (es. M15,21:00,SEGUI,1440,300)."; return false; }
   for(int i = 0; i < 5; i++) { StringTrimLeft(pr[i]); StringTrimRight(pr[i]); }
   string tfn = pr[0];
   StringToUpper(tfn);
   t = -1;
   for(int q = 0; q < g_nT; q++) if(g_tfName[q] == tfn) t = q;
   if(t < 0) { g_fixedNote = "Regola fissa: il TF " + pr[0] + " non e' fra quelli analizzati (InpTFs)."; return false; }
   const int mn = ClockToMin(pr[1]);
   if(mn < 0) { g_fixedNote = "Regola fissa: orario " + pr[1] + " non valido (HH:MM)."; return false; }
   rb = mn / g_rbMin;
   if(rb >= g_nRB) rb = g_nRB - 1;
   string sd = pr[2];
   StringToUpper(sd);
   if(sd == "SEGUI") dd = 0;
   else if(sd == "INVERTI") dd = 1;
   else { g_fixedNote = "Regola fissa: il verso deve essere SEGUI o INVERTI."; return false; }
   const int hold = (int)StringToInteger(pr[3]);
   h = -1;
   for(int q = 0; q < g_nH; q++) if(g_hor[q] == hold) h = q;
   if(h < 0) { g_fixedNote = "Regola fissa: la tenuta " + pr[3] + " min non e' fra gli orizzonti (InpHorizons)."; return false; }
   const double tp = StringToDouble(pr[4]);
   kk = -1;
   if(tp <= 0.0) kk = 0;
   else for(int q = 0; q < g_nL; q++) if(MathAbs(g_lev[q] - tp) < 1.0e-9) kk = q + 1;
   if(kk < 0) { g_fixedNote = "Regola fissa: il target " + pr[4] + " pt non e' fra i livelli (InpLevels)."; return false; }
   return true;
  }

//--- prepara le regole da mettere sotto stress: la regola fissa (se c'e'), poi quelle che reggono fuori campione, poi le migliori in-sample (senza doppioni di TF, fascia, verso e tenuta)
void StressRun(const int &pTf[], const int &pB[], const int &pH[], const int &pK[], const int &pD[], const int pn, const int &sv[], const int ns)
  {
   if(!InpStress) return;
   const int maxR = MathMin(12, MathMax(1, InpStressRules));
   int rTf[12], rB[12], rH[12], rK[12], rD[12], rO[12];
   int nr = 0;
   int fT = 0, fB = 0, fH = 0, fK = 0, fD = 0;
   if(ParseFixedRule(fT, fB, fH, fK, fD))
     {
      rTf[0] = fT; rB[0] = fB; rH[0] = fH; rK[0] = fK; rD[0] = fD; rO[0] = 2;
      nr = 1;
     }
   for(int pass = 0; pass < 2 && nr < maxR; pass++)
     {
      const int lim = (pass == 0) ? ns : pn;
      for(int ii = 0; ii < lim && nr < maxR; ii++)
        {
         const int ix = (pass == 0) ? sv[ii] : ii;
         bool dupR = false;
         for(int q2 = 0; q2 < nr; q2++)
            if(rTf[q2] == pTf[ix] && rB[q2] == pB[ix] && rD[q2] == pD[ix] && rH[q2] == pH[ix]) { dupR = true; break; }
         if(dupR) continue;
         rTf[nr] = pTf[ix]; rB[nr] = pB[ix]; rH[nr] = pH[ix]; rK[nr] = pK[ix]; rD[nr] = pD[ix]; rO[nr] = (pass == 0) ? 1 : 0;
         nr++;
        }
     }
   RepStress(nr, rTf, rB, rH, rK, rD, rO);
  }

//--- classifica congiunta: TF x fascia x tenuta x target x verso
void RepRank()
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   const int rankTop = MathMin(200, MathMax(1, InpRankTop));
   double pT[]; int pTf[], pB[], pH[], pK[], pD[];
   int pn = 0;
   int posOOS = 0, strong = 0, usable = 0, strongN = 0, strongOne = 0;
   double bestT = 0.0;
   long m = 0;
   RankPool(g_rk, pT, pTf, pB, pH, pK, pD, pn, bestT, usable, posOOS, strong, strongN, strongOne, m);

   W("<h2>A2 &mdash; Classifica: quando osservare il segnale e come gestire la posizione (scelta in-sample)</h2>");
   if(pn < 1 || m < 1)
     {
      W("<div class='note ko'>Nessuna combinazione con almeno " + IS((long)g_minN) + " posizioni in-sample. Riduci <b>InpRankMinN</b> o allarga il periodo.</div>");
      int svNone[];
      StressRun(pTf, pB, pH, pK, pD, 0, svNone, 0);
      return;
     }

   //--- diagnostica sull'insieme dei migliori in-sample (RankPool ha gia' contato le sopravvissute fuori campione)
   double chanceT = (m > 1) ? MathSqrt(2.0 * MathLog((double)m)) : 0.0;
   bool noisy = (bestT < chanceT + 1.0 || usable == 0 || posOOS * 2 < usable);
   g_cAok = true; g_cAm = m; g_cAbestT = bestT; g_cAchance = chanceT; g_cApn = pn;
   g_cAusable = usable; g_cApos = posOOS; g_cAstrong = strong; g_cAstrongN = strongN; g_cAone = strongOne;
   W("<div class='note " + string(noisy ? "ko" : "ok") + "'><b>Diagnostica della classifica.</b> Combinazioni valutate in-sample: <b>" + IS(m) +
     "</b>. Il miglior t in-sample trovato &egrave; <b>" + F2(bestT) + "</b>; per puro caso, su " + IS(m) +
     " tentativi indipendenti, ci si aspetta un massimo intorno a <b>" + F2(chanceT) + "</b> (stima per eccesso: le combinazioni vicine sono correlate, quindi i test davvero indipendenti sono meno). "
     "Fra le prime <b>" + IS(pn) + "</b> in-sample, <b>" + IS(posOOS) + "</b> su " + IS(usable) + " con campione OOS sufficiente restano positive fuori campione, <b>" +
     IS(strong) + "</b> con OOS t &ge; 2, di cui <b>" + IS(strongN) + "</b> con <b>abilit&agrave; della direzione</b> significativa (t &ge; 2). "
     "Il netto grezzo mescola tre cose: il <b>valore dell'istante M</b> (cosa guadagna in media chi sceglie il verso a caso in quegli istanti: rollover, spread, code di prezzo), la deriva del prezzo sfruttata da chi ha pi&ugrave; acquisti che vendite, "
     "e l'<b>abilit&agrave;</b>, cio&egrave; quanto la scelta del verso del segnale guadagna in pi&ugrave; di un verso casuale. Un segnale senza informazione ha abilit&agrave; nulla (t attorno a 0) anche con netto grezzo molto positivo. "
     "Dove il segnale va quasi sempre nello stesso verso (colonna % lunghe vicina a 0 o 100) l'abilit&agrave; non &egrave; misurabile: <b>" + IS(strongOne) + "</b> delle " + IS(strong) + " righe con OOS t &ge; 2 sono di questo tipo. " +
     string(noisy ? "Se questi numeri sono vicini a zero la classifica &egrave; rumore di selezione: non operare nessuna di queste righe."
                  : "Il risultato regge la prima verifica, ma resta da confermare su dati mai visti (forward o altro simbolo).") + "</div>");

   g_cPok = false;
   if(g_plc)
     {
      double pbT;
      double ptmp[];
      int pus, ppos, pstr, pstrN, pone, pn2;
      int qTf[], qB[], qH[], qK[], qD[];
      long pm;
      RankPool(g_rkP, ptmp, qTf, qB, qH, qK, qD, pn2, pbT, pus, ppos, pstr, pstrN, pone, pm);
      g_cPok = true; g_cPbest = pbT; g_cPstrong = pstr; g_cPstrongN = pstrN;
      W("<div class='note'><b>Controllo placebo.</b> Stessa classifica ricalcolata con una direzione casuale al posto di quella del segnale: stessi istanti, stesse regole di tenuta e di target, "
        "e la <b>stessa quota di acquisti e vendite</b> del segnale in ogni TF, fascia e periodo (cos&igrave; condivide con il segnale l'esposizione alla deriva del prezzo). Una sola estrazione: &egrave; molto variabile. "
        "Miglior t in-sample <b>" + F2(pbT) + "</b> contro " + F2(bestT) + " del segnale reale; fra le prime con campione OOS sufficiente <b>" + IS(pstr) + "</b> hanno OOS positivo e t &ge; 2 contro <b>" + IS(strong) +
        "</b> del segnale reale; con abilit&agrave; significativa <b>" + IS(pstrN) + "</b> contro <b>" + IS(strongN) + "</b>. "
        "Se il placebo ne trova quanto il segnale la classifica misura rumore di selezione, combinazioni quasi duplicate, oppure deriva o dislocazione del prezzo d'ingresso per sbilanciamento acquisti/vendite: non la direzione del segnale.</div>");
      g_dg += "PLACEBO|combos|" + IS(pm) + "|bestt|" + F2(pbT) + "|poosn|" + IS(pus) + "|pos|" + IS(ppos) + "|strong|" + IS(pstr) + "|strongneutral|" + IS(pstrN) + "\n";
     }

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
           "|poosn|" + IS(usable) + "|pos|" + IS(posOOS) + "|strong|" + IS(strong) + "|strongneutral|" + IS(strongN) + "\n";

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
      if(b.mean > 0.0 && b.t >= 2.0 && b.nm > 0.0 && b.nt >= 2.0) { sv[ns] = i; svT[ns] = b.t; ns++; }
     }
   for(int i = 0; i < ns - 1; i++)
      for(int j2 = i + 1; j2 < ns; j2++)
         if(svT[j2] > svT[i]) { double tt = svT[i]; svT[i] = svT[j2]; svT[j2] = tt; int ti = sv[i]; sv[i] = sv[j2]; sv[j2] = ti; }
   g_cAns = ns;
   g_cAsurv = "";
   g_cAsurvMean = 0.0; g_cAsurvN = 0.0;
   if(ns > 0)
     {
      const int i0 = sv[0];
      const int bs0 = ((pTf[i0] * g_nRB + pB[i0]) * g_nH + pH[i0]) * blk;
      RkStat sa, sb;
      RkRead(g_rk, bs0, pK[i0], pD[i0], 0, sa);
      RkRead(g_rk, bs0, pK[i0], pD[i0], 1, sb);
      g_cAsurvMean = sb.mean; g_cAsurvN = sb.n;
      g_cAsurv = g_tfName[pTf[i0]] + " " + RBktLabel(pB[i0]) + " " + (pD[i0] == 0 ? "SEGUI" : "INVERTI") + ", tieni " + IS(g_hor[pH[i0]]) +
                 " min, target " + KLabel(pK[i0]) + " pt: netto in-sample " + Sg(sa.mean) + " (t " + F2(sa.t) + "), fuori campione " +
                 Sg(sb.mean) + " (t " + F2(sb.t) + ", " + F0(sb.n) + " posizioni" + (g_money ? ("; = " + MnyU(sb.mean) + " a posizione con " + LotTxt() + " lotti, " + MnyTU(sb.mean * sb.n) + " in totale fuori campione") : "") +
                 "), spread medio della fascia " + F1(g_sprMean[pB[i0]]) +
                 " pt contro una mediana generale di " + F0(g_medSpr) + " pt";
     }
   W("<h3>Fra le prime " + IS(pn) + " in-sample: quelle con IS t &ge; 2 che reggono anche fuori campione (OOS netto &gt; 0 e OOS t &ge; 2, con abilit&agrave; della direzione significativa)</h3>");
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

   StressRun(pTf, pB, pH, pK, pD, pn, sv, ns);
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
          "<th>Verso</th><th>Tieni (min)</th><th>Target (pt)</th><th>Posizioni</th><th>Profitto totale (pt)</th><th>Totale (" + g_ccy + ")</th>"
          "<th>Netto medio</th><th>Netto medio (" + g_ccy + "/pos.)</th><th>t</th><th>Target raggiunto % (netto)</th>"
          "<th>Netto 1a parte</th><th>Netto 2a parte</th><th>Fra le due parti</th></tr>";
  }

string NoiseCells(const RkStat &all, const RkStat &a, const RkStat &b, const int kk)
  {
   return Td(F0(all.n)) + Td("<b>" + F0(all.sum) + "</b>", ColSign(all.sum)) + Td(MnyT(all.sum), ColSign(all.sum)) + Td(F1(all.mean), ColSign(all.mean)) +
          Td(Mny(all.mean), ColSign(all.mean)) + Td(F2(all.t), ColTNaive(all.t)) + Td(kk == 0 ? "-" : F1(all.hit)) +
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
                 if(!SideOK(dd)) continue;
               RkStat all;
               RkReadAll(g_rg, (t * g_nH + h) * blk, kk, dd, all);
               if(all.n < g_minN) continue;
               double key = NoiseKey(all);
               if(key > bk0) { bk0 = key; bh = h; bk = kk; bd = dd; }
              }
      if(bh < 0)
        { W("<tr class='thin'><td>-</td><td>" + g_tfName[t] + "</td><td colspan='13'>campione insufficiente</td></tr>"); continue; }
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
                    if(!SideOK(dd)) continue;
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
   g_cBok = true; g_cBm = m; g_cBsumAll = sumAll; g_cBtotal = top.sum; g_cBmean = top.mean; g_cBt = top.t; g_cBn = top.n;
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
            double tn  = NaiveT(n, g_accCnd[p + 3], g_accCnd[p + 4]);
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
      else if(pb >= 1.0 && pb < 100.0) sc[b] = (po - pb) / MathSqrt(pb * (100.0 - pb) / n);     // z naive: penalizza i campioni piccoli (un rapporto su 50 segnali e' solo rumore)
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
   return BktLabel(b) + " " + Pc(po) + "% (base " + Pc(pb) + "%, " + F0(n) + " segnali)";
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
     "<th>Fasce con il maggior vantaggio sulla base (ordinate per z naive, che penalizza i campioni piccoli)</th></tr>");
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
         c1 += (r > 0 ? "<br>" : "") + BktLabel(top1[r]) + " x" + F2(pb > 0.0 ? po / pb : 0.0) + " (" + Pc(po) + "% contro " + Pc(pb) + "%)";
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
     "Con molte fasce e giorni testati qualcuno supera la base per caso: cerca regolarit&agrave; che regga su un periodo successivo e su altri simboli, non la singola cella (i TF vicini condividono gran parte dei segnali). "
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
   o.tMv   = NaiveT(n, g_nx[p + 5], g_nx[p + 6]);
   return true;
  }

//--- base della categoria, sempre abbinata alla distribuzione oraria dei segnali di quella categoria (tutti, giorno, intensita', regime: media delle basi di fascia pesata sui segnali)
bool NxBase(const int s, const int t, const int mem, const int mi, NxStat &o)
  {
   o.n = 0.0; o.fav = 0.0; o.adv = 0.0; o.rng = 0.0; o.absMv = 0.0; o.sMv = 0.0; o.tMv = 0.0;
   if(mem >= NMEM1)                      // fascia oraria: la categoria coincide con la fascia, base diretta
     {
      const int p = ((t * g_nMem + mem) * g_nM + mi) * NXF;
      const double n = g_nxb[p];
      if(n < 1.0) return false;
      o.n = n; o.fav = g_nxb[p + 1] / n; o.adv = g_nxb[p + 2] / n; o.rng = g_nxb[p + 3] / n; o.absMv = g_nxb[p + 4] / n;
      return true;
     }
   if(mem != 0)                          // giorno, intensita', regime, direzione: media delle basi di fascia pesata sulle fasce dei segnali della categoria
     {
      double w1 = 0.0, f1 = 0.0, r1 = 0.0, a1 = 0.0;
      for(int b = 0; b < g_nB; b++)
        {
         const double ns = (double)g_nxsb[((((s * g_nT + t) * 19 + (mem - 1)) * g_nB + b) * g_nM) + mi];
         if(ns <= 0.0) continue;
         const int pb = ((((t * 19 + (mem - 1)) * g_nB + b) * g_nM) + mi) * 4;
         const double nb = g_nxbb[pb];
         if(nb < 1.0) continue;
         w1 += ns;
         f1 += ns * g_nxbb[pb + 1] / nb;
         r1 += ns * g_nxbb[pb + 2] / nb;
         a1 += ns * g_nxbb[pb + 3] / nb;
        }
      if(w1 <= 0.0) return false;
      o.n = w1; o.fav = f1 / w1; o.adv = o.fav; o.rng = r1 / w1; o.absMv = a1 / w1;
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

//--- range dopo m candele rispetto alla base a pari intensita' della candela del segnale (e stessa distribuzione oraria):
//--- media dei rapporti delle 6 classi di intensita' pesata sui segnali. 0 = non calcolabile
double NxRatioInt(const int s, const int t, const int mi)
  {
   double num = 0.0, den = 0.0;
   for(int b = 0; b < 6; b++)
     {
      NxStat a, bs;
      if(!NxGet(s, t, 8 + b, mi, a)) continue;
      if(!NxBase(s, t, 8 + b, mi, bs) || bs.rng <= 0.0) continue;
      num += a.n * a.rng;
      den += a.n * bs.rng;
     }
   return (den > 0.0) ? num / den : 0.0;
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
            const double ri    = NxRatioInt(s, t, k);
            const string colr  = (ri > 0.0) ? NxCol(ri, 1.0, a.n) : NxCol(a.rng, b.rng, a.n);        // il colore usa il rapporto a pari intensita'
            W("<td style='color:" + colr + "'" + tip + ">" + F0(a.rng) + (hb ? " &times;" + F2(ratio) : "") +
              NxSub("mediana " + F0(NxPct(s, t, 0, k, 1, a.n, 0.5)) + " &middot; p90 " + F0(NxPct(s, t, 0, k, 1, a.n, 0.9)) +
                    (ri > 0.0 ? " &middot; a pari intensit&agrave; &times;" + F2(ri) : "")) + "</td>");
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

string NxMList()
  {
   string ml = "";
   for(int q = 0; q < g_nM; q++) ml += string(q > 0 ? ", " : "") + IS(g_nxM[q]);
   return ml;
  }

void RepNext()
  {
   const int s = g_curSet;
   W("<h2>Quanto si muove il prezzo dopo il segnale: le candele successive (punti)</h2>");
   W("<div class='note'>Per ogni segnale si misurano le <b>prossime m candele dello stesso timeframe</b> (m = " + NxMList() +
     "), in punti dal prezzo d'ingresso (open della candela che segue il segnale, spread escluso). "
     "<b>Favorevole</b> = massimo raggiunto nella direzione del segnale; <b>avverso</b> = nella direzione opposta; "
     "<b>range</b> = massimo meno minimo, senza direzione: &egrave; la risposta a &laquo;quanto pu&ograve; spostarsi la candela dopo il segnale&raquo;; "
     "<b>chiusura</b> = spostamento fino alla chiusura dell'm-esima candela, con segno positivo se nella direzione del segnale / valore assoluto. "
     "<b>Mediana</b> e <b>p90</b> mostrano la dispersione: la media &egrave; trascinata dai giorni eccezionali. "
     "La <b>base</b> (fra parentesi, &times;) &egrave; la stessa misura su tutte le barre dello stesso TF e della stessa categoria, direzione casuale: "
     "verde = oltre la base di pi&ugrave; del 10%, rosso = sotto di pi&ugrave; del 10% (tabelle 1, 3, 5, 6, 7 e 8; nella 2 il colore confronta avverso e favorevole, nella 4 il giallo indica |t naive| &ge; 2). "
     "In ogni riga la base &egrave; pesata sulle stesse fasce orarie dei segnali di quella riga, cos&igrave; l'orario non passa per merito del segnale. "
     "Una candela ampia prima del segnale rende pi&ugrave; ampia anche la successiva (la volatilit&agrave; si raggruppa), per questo le tabelle per intensit&agrave; hanno la propria base. "
     "Intensit&agrave; = TR/ATR della candela del segnale (soglie " + F2(g_ibEdge[0]) + ", " + F2(g_ibEdge[1]) + ", " + F2(g_ibEdge[2]) + ", " + F2(g_ibEdge[3]) + ", " + F2(g_ibEdge[4]) +
     "). Le finestre intraday che attraversano un buco di dati oltre " + IS(InpMaxGapMin) + " min (weekend, festivi) non sono contate. "
     "Celle grigie scure = meno di " + IS(InpMinPerBucket) + " segnali; passa il mouse su una cella per numero di segnali e durata.</div>");

   W("<h3>1. Escursione favorevole media (punti nella direzione del segnale) &mdash; base fra parentesi</h3>");
   RepNextMatrix(0);
   W("<h3>2. Escursione avversa media (punti contro la direzione del segnale) &mdash; verde = avverso minore del favorevole, rosso = maggiore</h3>");
   RepNextMatrix(1);
   W("<h3>3. Range medio (massimo &minus; minimo, senza direzione) &mdash; &times; base (il colore usa il rapporto a pari intensit&agrave; della candela del segnale)</h3>");
   RepNextMatrix(2);
   W("<h3>4. Chiusura dell'm-esima candela: spostamento con segno nella direzione del segnale / valore assoluto &mdash; giallo se |t naive| &ge; 2</h3>");
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
                 "|ratioint|" + F2(NxRatioInt(s, t, q)) + "|abs|" + F0(a.absMv) + "|smv|" + F1(a.sMv) + "|tmv|" + F2(a.tMv) +
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
      double tn  = NaiveT(n, g_accBkt[p + 3], g_accBkt[p + 4]);
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
      double tn  = NaiveT(n, g_accSlot[p + 3], g_accSlot[p + 4]);
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
   string tp = topic, tx = text;
   StringReplace(tp, "|", "/");               // il testo finisce nel digest separato da '|'
   StringReplace(tx, "|", "/");
   g_cSet[k]   = s;
   g_cTopic[k] = tp;
   g_cText[k]  = tx;
  }

//--- tabella A: quante combinazioni con t OOS >= 2 si attendono per puro caso (P(t >= 2) circa 2.3%); l'evidenza c'e' solo se ne passano molte di piu'
bool AEdge(double &expected)
  {
   expected = g_cAok ? 0.0228 * (double)g_cAusable : 0.0;
   if(g_cPok && (double)g_cPstrongN > expected) expected = (double)g_cPstrongN;      // il placebo (stessa composizione BUY/SELL) e' il riferimento empirico: include correlazione fra combinazioni e struttura del payoff
   return (g_cAok && g_cAusable > 0 && g_cAstrongN >= 3 && (double)g_cAstrongN > 2.0 * expected + 2.0);          // si conta il risultato neutro, senza deriva e composizione
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

//+------------------------------------------------------------------+
//| PICCHI, STOP E RISCHIO                                            |
//| Per ogni segnale (campione uniforme per TF) si percorrono le barre |
//| M1 dall'ingresso alla fine della finestra (segnale opposto, durata |
//| massima o buco di dati) e si registrano: il picco del movimento    |
//| per ogni ritiro provato (massimo favorevole prima che il prezzo    |
//| ritiri di k ATR dal massimo), quando si forma e quanto il prezzo e'|
//| andato contro prima, il primo passaggio su ogni target e la massima|
//| escursione avversa prima di raggiungerlo (da cui si ricava ogni    |
//| stop). Dentro la barra M1 il minimo conta prima del massimo (come lo|
//| stop nella gestione simulata). Il picco e' un massimo calcolato a  |
//| posteriori: misura l'ampiezza dei movimenti, non un profitto; i    |
//| profitti ottenibili sono nella griglia stop x target, scelta sul   |
//| primo periodo e verificata sul resto.                              |
//+------------------------------------------------------------------+
#define PK_NSL    18         // stop provati: da 0.5 a 9 ATR in passi di 0.5
#define PK_SLMAX  9.0
#define PK_NCLS   55         // classi: 0 tutti | 1..24 ora | 25..32 posizione nella sequenza | 33..38 intensita' | 39..42 volume | 43..46 regime | 47..50 ADX | 51..54 percorso gia' fatto
double  g_pkK[], g_pkTp[];                       // ritiri (ATR) e target (ATR) provati
int     g_pkNk = 0, g_pkNj = 0, g_pkRefK = 0, g_pkGoodJ = 0, g_pkGoodS = 0;
int     g_pkTf[];
int     g_pkNtf = 0;
double  g_pkMed = 0.0;                           // ATR mediano (punti) del TF in corso, sui segnali del primo periodo: unita' dei punti fissi
int     g_pkNsig = 0, g_pkNruns = 0, g_pkStride = 1;   // segnali del TF, sequenze, passo del campionamento
//--- un record per segnale misurato (TF in corso)
int     g_prN = 0;
int     g_prK[], g_prJ[], g_prDay[], g_prPb[], g_prFt[];
uchar   g_prSmp[], g_prHr[], g_prBur[], g_prIb[], g_prVr[], g_prRg[], g_prAx[], g_prPc[];
char    g_prDir[];
double  g_prAtr[], g_prCost[], g_prProg[], g_prMa[], g_prRe[], g_prPv[], g_prPm[], g_prFm[];
//--- esiti per TF raccolti da PkAnalyze
string  g_pkSumRow = "", g_pkDet = "", g_pkCard = "";
double  g_pkRef[8];                              // ritiro di riferimento: picco mediano e 90% (pt), mediano e 90% (ATR), minuti al picco mediano, contro prima del picco (pt e ATR), candele mediane
int     g_pkP0v = -1, g_pkP0j = 0, g_pkP0s = 0;  // gestione scelta in-sample: variante (0 ATR del momento, 1 punti fissi), target, stop
double  g_pkP0[10];                              // n IS, media IS, t IS, n OOS, media OOS, t OOS, % target, % stop, % tempo, minuti medi al target (fuori campione)
double  g_pkNet[];                               // netto in punti di ogni record con la gestione scelta
double  g_pkHr[5];                               // test orari: ore scelte, segnali fuori campione delle ore scelte, loro media e t, media fuori campione di tutte le ore
double  g_pkFl[7];                               // test filtro: classe, n OOS, media OOS, t, media OOS tutte, n IS, media IS
double  g_pkSl[5];                               // tutti i segnali: % che raggiunge il target del segnale buono, stop (ATR e punti) che ne lascia passare il 75% e il 90%
double  g_pkRk[3];                               // rischio proposto %, crescita fuori campione e drawdown massimo a quel rischio
int     g_pkTest[3];                             // esito dei 3 test (OosVerdict) per il TF: gestione, orari, filtro; -1 non valutato

void PkSetup()
  {
   g_pkNtf = 0; g_pkNk = 0; g_pkNj = 0;
   if(!InpPeak) return;
   string ign;
   ParseTfSel(InpPeakTFs, g_pkTf, ign, true);
   if(ign != "") Print("InpPeakTFs: TF ignorati perche' non analizzati in InpTFs: ", ign);
   g_pkNtf = ArraySize(g_pkTf);
   g_pkNk = ParseDoubleList(InpPeakPullbacks, g_pkK);
   if(g_pkNk > 9) { Print("InpPeakPullbacks: usati solo i primi 9 valori (i piu' piccoli)."); ArrayResize(g_pkK, 9); g_pkNk = 9; }
   if(g_pkNk < 1) { ArrayResize(g_pkK, 1); g_pkK[0] = 2.0; g_pkNk = 1; Print("InpPeakPullbacks: nessun valore valido, uso 2 ATR."); }
   //--- target: positivi fino a 20 ATR, massimo 8, con quello del segnale buono sempre presente
   double tp[];
   const int nt = ParseDoubleList(InpPeakTpAtr, tp);
   ArrayResize(g_pkTp, 0);
   const double gTp = (InpPeakGoodTp > 0.0 && InpPeakGoodTp <= 20.0) ? InpPeakGoodTp : 2.0;
   bool haveGood = false;
   for(int q = 0; q < nt; q++)
     {
      if(tp[q] > 20.0) continue;
      const int k = ArraySize(g_pkTp);
      ArrayResize(g_pkTp, k + 1);
      g_pkTp[k] = tp[q];
      if(MathAbs(tp[q] - gTp) < 1.0e-9) haveGood = true;
     }
   if(!haveGood)
     {
      const int k = ArraySize(g_pkTp);
      ArrayResize(g_pkTp, k + 1);
      g_pkTp[k] = gTp;
      ArraySort(g_pkTp);
     }
   while(ArraySize(g_pkTp) > 8)
     {
      //--- troppi: si toglie il piu' grande che non sia quello del segnale buono
      int rm = ArraySize(g_pkTp) - 1;
      if(MathAbs(g_pkTp[rm] - gTp) < 1.0e-9) rm--;
      for(int q = rm; q < ArraySize(g_pkTp) - 1; q++) g_pkTp[q] = g_pkTp[q + 1];
      ArrayResize(g_pkTp, ArraySize(g_pkTp) - 1);
     }
   g_pkNj = ArraySize(g_pkTp);
   g_pkGoodJ = 0;
   for(int q = 0; q < g_pkNj; q++) if(MathAbs(g_pkTp[q] - gTp) < 1.0e-9) g_pkGoodJ = q;
   g_pkGoodS = (int)MathMin((double)(PK_NSL - 1), MathMax(0.0, MathRound(InpPeakGoodSl / 0.5) - 1.0));
   g_pkRefK = 0;
   for(int q = 1; q < g_pkNk; q++) if(MathAbs(g_pkK[q] - InpPeakRefK) < MathAbs(g_pkK[g_pkRefK] - InpPeakRefK)) g_pkRefK = q;
  }

//--- ATR mediano del TF sui segnali del primo periodo (se sono pochi, su tutti): unita' della variante a punti fissi
double PkMedianAtr(const int t)
  {
   double av[];
   for(int pass = 0; pass < 2 && ArraySize(av) < 20; pass++)
     {
      ArrayResize(av, 0, 4096);
      for(int k = g_tfOff[t]; k < g_tfOff[t] + g_tfCnt[t]; k++)
        {
         if(g_dir[k] == 0 || g_atr[k] <= 0.0) continue;
         if(pass == 0)
           {
            const int jb0 = StressBase(k);
            if(jb0 < 0 || g_m1Day[jb0] >= g_splitDay) continue;
           }
         const int na = ArraySize(av);
         ArrayResize(av, na + 1, 4096);
         av[na] = g_atr[k];
        }
     }
   return (ArraySize(av) >= 1) ? MedianOf(av, ArraySize(av)) : 0.0;
  }

//--- classe del volume tick recente (ultime 30 barre M1 prima dell'ingresso) rispetto al normale di quell'ora: 0 < 0.7, 1 fino a 1, 2 fino a 1.5, 3 oltre
int PkVolClass(const int j, const int hr)
  {
   const int L = 30;
   if(j < L || g_hrVol[hr] <= 0.0 || g_n1 < 1) return 1;
   const double ex = (g_m1Vcum[g_n1] / (double)g_n1) * g_hrVol[hr] * (double)L;
   if(ex <= 0.0) return 1;
   const double r = (g_m1Vcum[j] - g_m1Vcum[j - L]) / ex;
   return (r < 0.7) ? 0 : ((r < 1.0) ? 1 : ((r < 1.5) ? 2 : 3));
  }

//+------------------------------------------------------------------+
//| Percorso di un segnale: barre M1 da j (ingresso, all'open) a eEnd  |
//| escluso. Riempie il record i: un picco per ritiro (valore, barra e |
//| motivo di chiusura: 0 ritiro, 1 segnale opposto, 2 durata massima, |
//| 3 buco di dati o fine dello storico, escursione avversa prima del  |
//| picco) e, per le due unita' (0 ATR del segnale, 1 punti fissi pari |
//| all'ATR mediano) e per ogni target, la massima escursione avversa  |
//| prima del primo passaggio e i minuti impiegati (-1 se non raggiunto).|
//| ma = massima escursione avversa di tutta la finestra, re = risultato|
//| lordo a fine finestra (valido se la camminata non e' stata fermata  |
//| prima: cioe' solo quando serve).                                    |
//+------------------------------------------------------------------+
void PkWalk(const int i, const int j, const int d, const double atr, const int eEnd, const int endCause, const double pEnd)
  {
   const double pt = g_pt, o = g_m1Open[j];
   const int nK = g_pkNk, nJ = g_pkNj;
   double u[2];
   u[0] = atr; u[1] = g_pkMed;
   int nxt[2];
   nxt[0] = 0; nxt[1] = (g_pkMed > 0.0) ? 0 : nJ;
   for(int v = 0; v < 2; v++)
      for(int q = 0; q < nJ; q++) { g_prFm[(i * 2 + v) * nJ + q] = -1.0; g_prFt[(i * 2 + v) * nJ + q] = -1; }
   double mx = 0.0, aeNow = 0.0, aeMx = 0.0;
   int tm = j, nk = 0;
   bool early = false;
   for(int b = j; b < eEnd; b++)
     {
      double fh, fl;
      if(d > 0) { fh = (g_m1High[b] - o) / pt; fl = (g_m1Low[b] - o) / pt; }
      else      { fh = (o - g_m1Low[b]) / pt;  fl = (o - g_m1High[b]) / pt; }
      const double dd = mx - fl;                       // ritiro dal massimo precedente: il minimo della barra conta prima del suo massimo
      while(nk < nK && dd >= g_pkK[nk] * atr)
        {
         g_prPv[i * nK + nk] = mx; g_prPb[i * nK + nk] = tm; g_prPm[i * nK + nk] = aeMx; g_prPc[i * nK + nk] = 0;
         nk++;
        }
      if(-fl > aeNow) aeNow = -fl;
      if(fh > mx) { mx = fh; tm = b; aeMx = aeNow; }
      for(int v = 0; v < 2; v++)
         while(nxt[v] < nJ && fh >= g_pkTp[nxt[v]] * u[v])
           {
            g_prFm[(i * 2 + v) * nJ + nxt[v]] = aeNow;
            g_prFt[(i * 2 + v) * nJ + nxt[v]] = (int)(((long)g_m1Time[b] - (long)g_m1Time[j]) / 60L);
            nxt[v]++;
           }
      if(nk >= nK && (nxt[0] >= nJ || aeNow >= PK_SLMAX * u[0]) && (nxt[1] >= nJ || aeNow >= PK_SLMAX * u[1])) { early = true; break; }
     }
   for(int q = nk; q < nK; q++)
     { g_prPv[i * nK + q] = mx; g_prPb[i * nK + q] = tm; g_prPm[i * nK + q] = aeMx; g_prPc[i * nK + q] = (uchar)endCause; }
   g_prMa[i] = aeNow;
   g_prRe[i] = early ? 0.0 : ((d > 0) ? (pEnd - o) / pt : (o - pEnd) / pt);
  }

//--- raccoglie i record del TF t (serie corrente); restituisce il numero di record
int PkCollect(const int t)
  {
   const int k0 = g_tfOff[t], k1 = k0 + g_tfCnt[t];
   const int nK = g_pkNk, nJ = g_pkNj;
   int nSig = 0;
   for(int k = k0; k < k1; k++) if(g_dir[k] != 0) nSig++;
   const long capSig = (InpPeakMaxSignals > 0) ? (long)InpPeakMaxSignals : 2147483647L;
   const int stride = MathMax(1, (int)(((long)nSig + capSig - 1L) / capSig));
   const int cap = nSig / stride + 2;
   g_pkNsig = nSig; g_pkStride = stride; g_pkNruns = 0;
   ArrayResize(g_prK, cap); ArrayResize(g_prJ, cap); ArrayResize(g_prDay, cap); ArrayResize(g_prSmp, cap); ArrayResize(g_prHr, cap);
   ArrayResize(g_prBur, cap); ArrayResize(g_prIb, cap); ArrayResize(g_prVr, cap); ArrayResize(g_prRg, cap); ArrayResize(g_prAx, cap);
   ArrayResize(g_prDir, cap); ArrayResize(g_prAtr, cap); ArrayResize(g_prCost, cap); ArrayResize(g_prProg, cap); ArrayResize(g_prMa, cap); ArrayResize(g_prRe, cap);
   ArrayResize(g_prPv, cap * nK); ArrayResize(g_prPm, cap * nK); ArrayResize(g_prPb, cap * nK); ArrayResize(g_prPc, cap * nK);
   ArrayResize(g_prFm, cap * 2 * nJ); ArrayResize(g_prFt, cap * 2 * nJ);
   //--- all'indietro: ingresso M1 del segnale opposto piu' vicino dopo ciascun segnale
   int oppEnt[];
   ArrayResize(oppEnt, k1 - k0);
   int lastBuy = -1, lastSell = -1;
   for(int k = k1 - 1; k >= k0; k--)
     {
      const int d = (int)g_dir[k];
      oppEnt[k - k0] = -1;
      if(d == 0) continue;
      const int jb = StressBase(k);
      const int je = (jb >= 0) ? jb : g_ent[k];
      oppEnt[k - k0] = (d > 0) ? lastSell : lastBuy;
      if(d > 0) lastBuy = je; else lastSell = je;
     }
   const long tfMin = MathMax(1L, g_tfSec[t] / 60L);
   const long capMin = MathMax((long)MathMax(1, InpPeakMaxMin), (long)MathMax(1, InpPeakMaxCandles) * tfMin);
   int seen = 0, n = 0;
   double runOpen = 0.0;
   for(int k = k0; k < k1; k++)
     {
      const int d = (int)g_dir[k];
      if(d == 0) continue;
      const int jb = StressBase(k);
      if(g_bur[k] == 1) { g_pkNruns++; if(jb >= 0) runOpen = g_m1Open[jb]; }
      seen++;
      if(((seen - 1) % stride) != 0) continue;
      if(jb < 0) continue;
      const double atr = g_atr[k];
      if(atr <= 0.0) continue;
      //--- fine della finestra: durata massima, buco di dati o fine dello storico, segnale opposto
      int e = MgLower((long)g_m1Time[jb] + capMin * 60L, jb);
      int cause = 2;
      const int eb = g_nextBrk[jb] + 1;
      if(eb <= e) { e = eb; cause = 3; }
      if(!InpPeakCross)
        {
         const int jo = oppEnt[k - k0];
         if(jo > jb && jo < e) { e = jo; cause = 1; }
        }
      if(e <= jb) continue;
      const double pEnd = (cause == 1) ? g_m1Open[e] : g_m1Close[e - 1];
      const long ts = (long)g_m1Time[jb];
      const int hr = (int)(((((ts + g_off) % 86400L) + 86400L) % 86400L) / 3600L);
      g_prK[n] = k; g_prJ[n] = jb; g_prDir[n] = (char)d; g_prDay[n] = g_m1Day[jb];
      g_prSmp[n] = (g_m1Day[jb] >= g_splitDay) ? (uchar)1 : (uchar)0;
      g_prHr[n] = (uchar)hr;
      g_prBur[n] = g_bur[k];
      g_prIb[n] = (g_ib[k] < 6) ? g_ib[k] : (uchar)255;
      g_prVr[n] = (uchar)PkVolClass(jb, hr);
      const bool haveX = (ArraySize(g_adxq) > k && ArraySize(g_reg) > k);
      g_prRg[n] = (haveX && g_reg[k] != 255) ? (uchar)((g_reg[k] >> 1) & 3) : (uchar)255;
      const int a2 = haveX ? (int)g_adxq[k] / 2 : -1;
      g_prAx[n] = (a2 < 0) ? (uchar)255 : ((a2 < 15) ? (uchar)0 : ((a2 < 20) ? (uchar)1 : ((a2 < 30) ? (uchar)2 : (uchar)3)));
      g_prAtr[n] = atr;
      g_prCost[n] = ((InpCostPoints > 0.0) ? InpCostPoints : (double)g_m1Spr[jb]) + g_extraPts;
      g_prProg[n] = (g_bur[k] > 1) ? (double)d * (g_m1Open[jb] - runOpen) / g_pt : 0.0;
      PkWalk(n, jb, d, atr, e, cause, pEnd);
      n++;
     }
   g_prN = n;
   return n;
  }

//--- classi a cui appartiene il record i (c: almeno 8 posti)
int PkCls(const int i, int &c[])
  {
   int nc = 0;
   c[nc] = 0; nc++;
   c[nc] = 1 + (int)g_prHr[i]; nc++;
   const int b = (int)g_prBur[i];
   c[nc] = 25 + MathMin(8, MathMax(1, b)) - 1; nc++;
   if(g_prIb[i] < 6) { c[nc] = 33 + (int)g_prIb[i]; nc++; }
   c[nc] = 39 + (int)g_prVr[i]; nc++;
   if(g_prRg[i] < 4) { c[nc] = 43 + (int)g_prRg[i]; nc++; }
   if(g_prAx[i] < 4) { c[nc] = 47 + (int)g_prAx[i]; nc++; }
   if(b > 1)
     {
      const double pg = g_prProg[i] / g_prAtr[i];
      c[nc] = 51 + ((pg < 0.0) ? 0 : ((pg < 1.0) ? 1 : ((pg < 2.0) ? 2 : 3))); nc++;
     }
   return nc;
  }

string PkClsLbl(const int c)
  {
   if(c == 0) return "tutti i segnali";
   if(c <= 24) return "ora " + string(c - 1 < 10 ? "0" : "") + IS(c - 1) + ":00";
   if(c <= 32) return (c == 32) ? string("segnale n. 8 o oltre della sequenza") : ("segnale n. " + IS(c - 24) + " della sequenza");
   if(c <= 38) return NxIntPlain(c - 33);
   if(c <= 42) { const string vs[4] = {"volume sotto la norma (< 0.7)", "volume 0.7-1.0 della norma", "volume 1.0-1.5 della norma", "volume sopra 1.5 volte la norma"}; return vs[c - 39]; }
   if(c <= 46) { const string rn[4] = {"regime LOW", "regime NORMAL", "regime HIGH", "regime EXTREME"}; return rn[c - 43]; }
   if(c <= 50) { const string ax[4] = {"ADX sotto 15", "ADX 15-20", "ADX 20-30", "ADX 30 o piu'"}; return ax[c - 47]; }
   const string pg[4] = {"prezzo gia' tornato indietro dall'inizio della sequenza", "gia' percorso 0-1 ATR", "gia' percorso 1-2 ATR", "gia' percorso oltre 2 ATR"};
   return pg[c - 51];
  }

//--- quantile (0..1) di un vettore ordinato
double PkAt(const double &a[], const int n, const double q)
  {
   if(n <= 0) return 0.0;
   const double p = q * (double)(n - 1);
   const int lo = (int)MathFloor(p);
   const int hi = MathMin(n - 1, lo + 1);
   return a[lo] + (p - (double)lo) * (a[hi] - a[lo]);
  }

//--- mediana, 75% e 90% (il vettore viene ordinato)
void PkQ(double &a[], const int n, double &q50, double &q75, double &q90)
  {
   q50 = 0.0; q75 = 0.0; q90 = 0.0;
   if(n <= 0) return;
   ArrayResize(a, n);
   ArraySort(a);
   q50 = PkAt(a, n, 0.5); q75 = PkAt(a, n, 0.75); q90 = PkAt(a, n, 0.9);
  }

//--- netto in punti del record i con la gestione (variante v, target j, stop s): stop e target eseguiti al loro livello, stop prima del target nella stessa barra
double PkNet(const int i, const int v, const int j, const int s)
  {
   const double u = (v == 0) ? g_prAtr[i] : g_pkMed;
   const double slp = (double)(s + 1) * 0.5 * u;
   const double fm = g_prFm[(i * 2 + v) * g_pkNj + j];
   double gross;
   if(fm >= 0.0) gross = (fm < slp) ? g_pkTp[j] * u : -slp;
   else          gross = (g_prMa[i] >= slp) ? -slp : g_prRe[i];
   return gross - g_prCost[i];
  }

//--- statistiche di una selezione di record: res = n e media in-sample, t semplice in-sample, n e media fuori campione, t raggruppato per giorno fuori campione
void PkStat(const bool &mask[], const double &x[], const int n, double &res[])
  {
   double n0 = 0.0, s0 = 0.0, q0 = 0.0, n1 = 0.0, s1 = 0.0, A = 0.0, B = 0.0, C = 0.0, ds = 0.0, dn = 0.0;
   int dayc = -1;
   for(int i = 0; i < n; i++)
     {
      if(!mask[i]) continue;
      const double v = x[i];
      if(g_prSmp[i] == 0) { n0 += 1.0; s0 += v; q0 += v * v; continue; }
      if(g_prDay[i] != dayc) { A += ds * ds; B += ds * dn; C += dn * dn; ds = 0.0; dn = 0.0; dayc = g_prDay[i]; }
      ds += v; dn += 1.0; n1 += 1.0; s1 += v;
     }
   A += ds * ds; B += ds * dn; C += dn * dn;
   ArrayResize(res, 6);
   res[0] = n0; res[1] = (n0 > 0.0) ? s0 / n0 : 0.0; res[2] = NaiveT(n0, s0, q0);
   res[3] = n1; res[4] = (n1 > 0.0) ? s1 / n1 : 0.0; res[5] = ClusterT(n1, res[4], A, B, C);
  }

//--- minuti dall'ingresso alla barra del picco del record i, ritiro kk
double PkPeakMin(const int i, const int kk)
  {
   return (double)(((long)g_m1Time[g_prPb[i * g_pkNk + kk]] - (long)g_m1Time[g_prJ[i]]) / 60L);
  }

//--- 0 = il target del segnale buono non e' raggiunto, 1 = raggiunto, 2 = raggiunto senza toccare lo stop del segnale buono (ATR del momento)
int PkGoodCode(const int i)
  {
   const double fm = g_prFm[(i * 2 + 0) * g_pkNj + g_pkGoodJ];
   if(fm < 0.0) return 0;
   return (fm < (double)(g_pkGoodS + 1) * 0.5 * g_prAtr[i]) ? 2 : 1;
  }

string PkMin(const double m, const double tfMin)
  {
   const double c = m / MathMax(1.0, tfMin);
   return F0(m) + " min (" + string(c < 1.0 ? "meno di 1 candela" : (F1(c) + " candele")) + ")";
  }

//+------------------------------------------------------------------+
//| Tabella dei picchi: per ogni ritiro, quanti punti e quanti ATR     |
//| percorre il prezzo prima del picco, dopo quanto tempo, quanto va   |
//| contro prima. I picchi non chiusi dal ritiro (finestra finita prima|
//| per segnale opposto, durata massima o buco di dati) sono limiti    |
//| inferiori e sono contati nella colonna dei picchi confermati.      |
//+------------------------------------------------------------------+
string PkPeaks(const int t, const int n)
  {
   const double tfMin = (double)g_tfSec[t] / 60.0;
   const int nK = g_pkNk;
   double a1[], a2[], a3[], a4[], a5[], a6[];
   ArrayResize(a1, n); ArrayResize(a2, n); ArrayResize(a3, n); ArrayResize(a4, n); ArrayResize(a5, n); ArrayResize(a6, n);
   string tb = "";
   for(int kk = 0; kk < nK; kk++)
     {
      int conf = 0;
      double sPts = 0.0;
      for(int i = 0; i < n; i++)
        {
         const int p = i * nK + kk;
         a1[i] = g_prPv[p]; a2[i] = g_prPv[p] / g_prAtr[i]; a3[i] = PkPeakMin(i, kk);
         a4[i] = g_prPm[p]; a5[i] = g_prPm[p] / g_prAtr[i];
         if(g_prPc[p] == 0) conf++;
         sPts += g_prPv[p];
        }
      double p50, p75, p90, r50, r75, r90, m50, m75, m90, e50, e75, e90, f50, f75, f90;
      PkQ(a1, n, p50, p75, p90); PkQ(a2, n, r50, r75, r90); PkQ(a3, n, m50, m75, m90);
      PkQ(a4, n, e50, e75, e90); PkQ(a5, n, f50, f75, f90);
      const double cp = 100.0 * (double)conf / (double)n;
      if(kk == g_pkRefK)
        {
         g_pkRef[0] = p50; g_pkRef[1] = p90; g_pkRef[2] = r50; g_pkRef[3] = r90; g_pkRef[4] = m50; g_pkRef[5] = e50; g_pkRef[6] = f50; g_pkRef[7] = m50 / MathMax(1.0, tfMin);
        }
      tb += "<tr" + string(kk == g_pkRefK ? " style='background:#222733'" : "") + "><td>" + ThrLbl(g_pkK[kk]) + " ATR</td>" + Td(F0(cp) + "%") + Td(F0(sPts / (double)n)) + Td("<b>" + F0(p50) + "</b>") + Td(F0(p75)) + Td(F0(p90)) +
            Td(F2(r50)) + Td(F2(r90)) + Td(F0(m50)) + Td(F0(m75)) + Td(F1(m50 / MathMax(1.0, tfMin))) + Td(F0(e50)) + Td(F2(f50)) + "</tr>";
      g_dg += "PK|" + g_tfName[t] + "|ret|" + ThrLbl(g_pkK[kk]) + "|n|" + IS(n) + "|conf|" + F0(cp) + "|mean|" + F0(sPts / (double)n) + "|p50|" + F0(p50) + "|p75|" + F0(p75) + "|p90|" + F0(p90) +
              "|atr50|" + F2(r50) + "|atr90|" + F2(r90) + "|min50|" + F0(m50) + "|min75|" + F0(m75) + "|candles50|" + F1(m50 / MathMax(1.0, tfMin)) + "|mae50|" + F0(e50) + "|mae50atr|" + F2(f50) + "\n";
     }
   return "<table><tr><th>Ritiro che chiude il picco</th><th>Picchi chiusi dal ritiro</th><th>Picco medio (pt)</th><th>Picco mediano (pt)</th><th>75% (pt)</th><th>90% (pt)</th><th>Mediano (ATR)</th><th>90% (ATR)</th>"
          "<th>Tempo mediano al picco (min)</th><th>75% (min)</th><th>Candele mediane</th><th>Contro prima del picco, mediana (pt)</th><th>(ATR)</th></tr>" + tb + "</table>";
  }

//+------------------------------------------------------------------+
//| Sequenze: per la posizione del segnale nella sequenza di segnali   |
//| nello stesso verso, picco (ritiro di riferimento), tempo, percorso |
//| che il prezzo ha gia' fatto dall'inizio della sequenza, quota di   |
//| segnali buoni.                                                     |
//+------------------------------------------------------------------+
string PkSeq(const int t, const int n)
  {
   const double tfMin = (double)g_tfSec[t] / 60.0;
   const int nK = g_pkNk, kr = g_pkRefK;
   string tb = "";
   double a1[], a2[], a3[];
   for(int b = 1; b <= 8; b++)
     {
      ArrayResize(a1, n); ArrayResize(a2, n); ArrayResize(a3, n);     // PkQ accorcia i vettori
      int m = 0, good = 0, reach = 0;
      double sp = 0.0, sa = 0.0;
      for(int i = 0; i < n; i++)
        {
         if(MathMin(8, (int)g_prBur[i]) != b) continue;
         a1[m] = g_prPv[i * nK + kr]; a2[m] = g_prPv[i * nK + kr] / g_prAtr[i]; a3[m] = PkPeakMin(i, kr);
         sp += g_prProg[i]; sa += g_prProg[i] / g_prAtr[i];
         const int gc = PkGoodCode(i);
         if(gc >= 1) reach++;
         if(gc == 2) good++;
         m++;
        }
      if(m < 1) continue;
      double p50, p75, p90, r50, r75, r90, m50, m75, m90;
      PkQ(a1, m, p50, p75, p90); PkQ(a2, m, r50, r75, r90); PkQ(a3, m, m50, m75, m90);
      tb += "<tr" + string(m < InpPeakMinN ? " class='thin'" : "") + "><td>" + string(b == 8 ? "8 o oltre" : IS(b)) + "</td>" + Td(IS(m)) + Td("<b>" + F0(p50) + "</b>") + Td(F0(p90)) + Td(F2(r50)) + Td(F2(r90)) + Td(F0(m50)) + Td(F1(m50 / MathMax(1.0, tfMin))) +
            Td(b > 1 ? F0(sp / (double)m) : string("-")) + Td(b > 1 ? F2(sa / (double)m) : string("-")) + Td(F0(100.0 * (double)reach / (double)m) + "%") + Td(F0(100.0 * (double)good / (double)m) + "%") + "</tr>";
      g_dg += "PKSEQ|" + g_tfName[t] + "|pos|" + IS(b) + "|n|" + IS(m) + "|p50|" + F0(p50) + "|p90|" + F0(p90) + "|atr50|" + F2(r50) + "|min50|" + F0(m50) + "|done|" + F0(b > 1 ? sp / (double)m : 0.0) +
              "|reach|" + F0(100.0 * (double)reach / (double)m) + "|good|" + F0(100.0 * (double)good / (double)m) + "\n";
     }
   string runs = "";
   if(g_pkNruns > 0)
      runs = "Su " + IS(g_pkNsig) + " segnali del TF ci sono " + IS(g_pkNruns) + " sequenze di segnali nello stesso verso (in media " + F1((double)g_pkNsig / (double)g_pkNruns) + " segnali per sequenza). ";
   //--- dall'inizio di una sequenza: quanti segnali sono gia' entrati quando si forma il picco (il primo c'e' sempre)
   {
    double nb[];
    ArrayResize(nb, 0, 1024);
    double sLen = 0.0;
    int early = 0;
    const int kEnd = g_tfOff[t] + g_tfCnt[t];
    for(int i = 0; i < n; i++)
      {
       if(g_prBur[i] != 1) continue;
       const int jPk = g_prPb[i * nK + kr];
       int c = 1, pb = 1, len = 1;
       for(int k = g_prK[i] + 1; k < kEnd; k++)
         {
          if(g_dir[k] == 0) continue;
          if(g_dir[k] != g_prDir[i] || (int)g_bur[k] != pb + 1) break;
          pb++; len++;
          const int jb = StressBase(k);
          if(jb >= 0 && jb <= jPk) c++;
         }
       const int q = ArraySize(nb);
       ArrayResize(nb, q + 1, 1024);
       nb[q] = (double)c;
       sLen += (double)len;
       if(c == 1) early++;
      }
    const int nr = ArraySize(nb);
    if(nr >= 5)
      {
       double sc = 0.0;
       for(int q = 0; q < nr; q++) sc += nb[q];
       const double md = MedianOf(nb, nr);
       runs += "Contando dall'inizio di una sequenza: quando si forma il picco sono gia' entrati in media " + F1(sc / (double)nr) + " segnali (mediana " + F0(md) + ") su " + F1(sLen / (double)nr) + " della sequenza intera; nel " +
               F0(100.0 * (double)early / (double)nr) + "% dei casi il picco si forma prima del secondo segnale. ";
       g_dg += "PKRUN|" + g_tfName[t] + "|runs|" + IS(nr) + "|sigatpeak|" + F2(sc / (double)nr) + "|median|" + F0(md) + "|runlen|" + F2(sLen / (double)nr) + "|beforesecond|" + F0(100.0 * (double)early / (double)nr) + "\n";
      }
   }
   return "<div class='note'>" + runs + "Picco con ritiro di " + ThrLbl(g_pkK[kr]) + " ATR. <b>Percorso gi&agrave; fatto</b> = quanto il prezzo si &egrave; mosso nel verso del segnale fra l'ingresso del primo segnale della sequenza e quello di questo (negativo = &egrave; tornato indietro). "
          "<b>Raggiunge</b> = tocca il target di " + ThrLbl(g_pkTp[g_pkGoodJ]) + " ATR entro la finestra, qualunque sia lo stop; <b>buoni</b> = lo raggiunge senza toccare lo stop di " + ThrLbl((double)(g_pkGoodS + 1) * 0.5) + " ATR.</div>"
          "<table><tr><th>Posizione nella sequenza</th><th>Segnali</th><th>Picco mediano (pt)</th><th>90% (pt)</th><th>Mediano (ATR)</th><th>90% (ATR)</th><th>Tempo mediano (min)</th><th>(candele)</th>"
          "<th>Gi&agrave; percorso, medio (pt)</th><th>(ATR)</th><th>Raggiunge il target</th><th>Buoni</th></tr>" + tb + "</table>";
  }

//--- etichetta della gestione scelta: variante, stop e target in ATR e in punti
string PkP0Lbl(const double medAtr)
  {
   if(g_pkP0v < 0) return "nessuna";
   const double sl = (double)(g_pkP0s + 1) * 0.5, tp = g_pkTp[g_pkP0j];
   const double un = (g_pkP0v == 0) ? medAtr : g_pkMed;
   return "stop " + ThrLbl(sl) + " ATR" + string(g_pkP0v == 0 ? " del segnale" : " mediano (punti fissi)") + " (circa " + F0(sl * un) + " pt), target " + ThrLbl(tp) + " ATR (circa " + F0(tp * un) + " pt)";
  }

//+------------------------------------------------------------------+
//| Griglia stop x target. Per ogni segnale, stop s e target tp (in    |
//| multipli dell'ATR del segnale oppure dell'ATR mediano del TF in    |
//| punti fissi): se il prezzo raggiunge il target prima di andare     |
//| contro di s, guadagna tp; se va contro di s prima, perde s; se non |
//| succede nulla entro la finestra esce al prezzo di fine finestra.   |
//| Si sceglie sul primo periodo la cella con il t semplice piu' alto  |
//| (con almeno minIs segnali) e la si misura sul resto.               |
//+------------------------------------------------------------------+
string PkGrid(const int t, const int n, const double medAtr)
  {
   const int nV = (g_pkMed > 0.0) ? 2 : 1, nJ = g_pkNj;
   const int nCell = nV * nJ * PK_NSL;
   const double minIs = MathMax(30.0, g_minN / 2.0);
   double gN[], gS[], gQ[], gA[], gB[], gC[], cs[], cn[];
   int cd[];
   ArrayResize(gN, nCell * 2); ArrayResize(gS, nCell * 2); ArrayResize(gQ, nCell * 2);
   ArrayResize(gA, nCell); ArrayResize(gB, nCell); ArrayResize(gC, nCell); ArrayResize(cs, nCell); ArrayResize(cn, nCell); ArrayResize(cd, nCell);
   ArrayInitialize(gN, 0.0); ArrayInitialize(gS, 0.0); ArrayInitialize(gQ, 0.0);
   ArrayInitialize(gA, 0.0); ArrayInitialize(gB, 0.0); ArrayInitialize(gC, 0.0); ArrayInitialize(cs, 0.0); ArrayInitialize(cn, 0.0); ArrayInitialize(cd, -1);
   for(int i = 0; i < n; i++)
     {
      const int sm = (int)g_prSmp[i];
      for(int v = 0; v < nV; v++)
         for(int j = 0; j < nJ; j++)
            for(int s = 0; s < PK_NSL; s++)
              {
               const int c = (v * nJ + j) * PK_NSL + s;
               const double x = PkNet(i, v, j, s);
               gN[c * 2 + sm] += 1.0; gS[c * 2 + sm] += x; gQ[c * 2 + sm] += x * x;
               if(sm == 1)
                 {
                  if(g_prDay[i] != cd[c]) { gA[c] += cs[c] * cs[c]; gB[c] += cs[c] * cn[c]; gC[c] += cn[c] * cn[c]; cs[c] = 0.0; cn[c] = 0.0; cd[c] = g_prDay[i]; }
                  cs[c] += x; cn[c] += 1.0;
                 }
              }
     }
   for(int c = 0; c < nCell; c++) { gA[c] += cs[c] * cs[c]; gB[c] += cs[c] * cn[c]; gC[c] += cn[c] * cn[c]; }
   //--- scelta in-sample
   int best = -1;
   double bt = -1.0e18;
   for(int pass = 0; pass < 2 && best < 0; pass++)
      for(int c = 0; c < nCell; c++)
        {
         if(gN[c * 2] < minIs) continue;
         if(pass == 0 && gS[c * 2] <= 0.0) continue;
         const double ti = NaiveT(gN[c * 2], gS[c * 2], gQ[c * 2]);
         if(best < 0 || ti > bt) { best = c; bt = ti; }
        }
   g_pkP0v = -1;
   for(int q = 0; q < 10; q++) g_pkP0[q] = 0.0;
   ArrayResize(g_pkNet, n);
   if(best >= 0)
     {
      g_pkP0v = best / (nJ * PK_NSL); g_pkP0j = (best / PK_NSL) % nJ; g_pkP0s = best % PK_NSL;
      g_pkP0[0] = gN[best * 2]; g_pkP0[1] = gS[best * 2] / gN[best * 2]; g_pkP0[2] = bt;
      g_pkP0[3] = gN[best * 2 + 1];
      g_pkP0[4] = (gN[best * 2 + 1] > 0.0) ? gS[best * 2 + 1] / gN[best * 2 + 1] : 0.0;
      g_pkP0[5] = ClusterT(gN[best * 2 + 1], g_pkP0[4], gA[best], gB[best], gC[best]);
      //--- come finiscono le posizioni fuori campione: target, stop, tempo
      double nt = 0.0, ns = 0.0, nw = 0.0, sMin = 0.0;
      for(int i = 0; i < n; i++)
        {
         g_pkNet[i] = PkNet(i, g_pkP0v, g_pkP0j, g_pkP0s);
         if(g_prSmp[i] == 0) continue;
         const double u = (g_pkP0v == 0) ? g_prAtr[i] : g_pkMed;
         const double slp = (double)(g_pkP0s + 1) * 0.5 * u;
         const int p = (i * 2 + g_pkP0v) * nJ + g_pkP0j;
         const double fm = g_prFm[p];
         if(fm >= 0.0 && fm < slp) { nt += 1.0; sMin += (double)g_prFt[p]; }
         else if(fm >= 0.0 || g_prMa[i] >= slp) ns += 1.0;
         else nw += 1.0;
        }
      const double no = MathMax(1.0, nt + ns + nw);
      g_pkP0[6] = 100.0 * nt / no; g_pkP0[7] = 100.0 * ns / no; g_pkP0[8] = 100.0 * nw / no; g_pkP0[9] = (nt > 0.0) ? sMin / nt : 0.0;
     }
   else
      for(int i = 0; i < n; i++) g_pkNet[i] = 0.0;
   //--- tabelle (media su tutto il periodo: descrittiva, la scelta e' sopra)
   string hs = "";
   for(int v = 0; v < nV; v++)
     {
      const double un = (v == 0) ? medAtr : g_pkMed;
      hs += "<h4>" + string(v == 0 ? "Stop e target in multipli dell'ATR del segnale (punti = multiplo x ATR del momento; in punti al mediano di " + F0(medAtr) + " pt)"
                                   : "Stop e target in PUNTI FISSI (multipli dell'ATR mediano del TF, " + F0(g_pkMed) + " pt)") + " &mdash; netto medio per segnale su tutto il periodo, in punti</h4>";
      hs += "<table><tr><th>Stop \\ Target</th>";
      for(int j = 0; j < nJ; j++) hs += "<th>" + ThrLbl(g_pkTp[j]) + " ATR<br>" + F0(g_pkTp[j] * un) + " pt</th>";
      hs += "</tr>";
      for(int s = 0; s < PK_NSL; s++)
        {
         hs += "<tr><td>" + ThrLbl((double)(s + 1) * 0.5) + " ATR (" + F0((double)(s + 1) * 0.5 * un) + " pt)</td>";
         for(int j = 0; j < nJ; j++)
           {
            const int c = (v * nJ + j) * PK_NSL + s;
            const double nn = gN[c * 2] + gN[c * 2 + 1];
            const double mu = (nn > 0.0) ? (gS[c * 2] + gS[c * 2 + 1]) / nn : 0.0;
            const bool isB = (c == best);
            hs += Td(string(isB ? "<b>[" : "") + F1(mu) + string(isB ? "]</b>" : ""), ColSign(mu));
           }
         hs += "</tr>";
        }
      hs += "</table>";
     }
   //--- digest: la cella scelta e la media di ogni cella
   if(best >= 0)
      g_dg += "PKBEST|" + g_tfName[t] + "|unit|" + string(g_pkP0v == 0 ? "atr" : "atrmed") + "|sl|" + ThrLbl((double)(g_pkP0s + 1) * 0.5) + "|tp|" + ThrLbl(g_pkTp[g_pkP0j]) + "|medpt|" + F0(g_pkP0v == 0 ? medAtr : g_pkMed) +
              "|isn|" + F0(g_pkP0[0]) + "|isnet|" + F1(g_pkP0[1]) + "|ist|" + F2(g_pkP0[2]) + "|oosn|" + F0(g_pkP0[3]) + "|oosnet|" + F1(g_pkP0[4]) + "|oost|" + F2(g_pkP0[5]) +
              "|hit|" + F0(g_pkP0[6]) + "|stop|" + F0(g_pkP0[7]) + "|time|" + F0(g_pkP0[8]) + "|minhit|" + F0(g_pkP0[9]) + "\n";
   //--- digest: una riga per unita' e stop con il netto medio (tutto il periodo) di ogni target, "target:netto"
   for(int v = 0; v < nV; v++)
      for(int s = 0; s < PK_NSL; s++)
        {
         string ln = "";
         for(int j = 0; j < nJ; j++)
           {
            const int c = (v * nJ + j) * PK_NSL + s;
            const double nn = gN[c * 2] + gN[c * 2 + 1];
            ln += string(j > 0 ? "," : "") + ThrLbl(g_pkTp[j]) + ":" + string(nn > 0.0 ? F1((gS[c * 2] + gS[c * 2 + 1]) / nn) : string("-"));
           }
         g_dg += "PKGRID|" + g_tfName[t] + "|" + string(v == 0 ? "atr" : "atrmed") + "|sl|" + ThrLbl((double)(s + 1) * 0.5) + "|" + ln + "\n";
        }
   return hs;
  }

bool    g_pkRiskMask[];                  // record su cui si calcola il rischio: orari scelti in-sample se il test degli orari ne ha scelti, altrimenti tutti
bool    g_pkRiskSel = false;
double  g_pkCls[PK_NCLS * 8];            // per classe: n, n IS, media IS, t IS, n OOS, media OOS, t OOS, rischio proposto %

//--- lotti arrotondati per difetto al passo del simbolo
string PkLots(const double raw)
  {
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(st <= 0.0) st = 0.01;
   if(mn <= 0.0) mn = st;
   if(mx <= 0.0) mx = 1000.0;
   double l = MathFloor(raw / st + 1.0e-9) * st;
   if(l > mx) l = mx;
   if(l < mn) return "sotto il minimo (" + DoubleToString(raw, 3) + ")";
   return DoubleToString(l, 2);
  }

//--- rischio proposto in % del capitale: frazione del Kelly (media / media dei quadrati dei risultati in multipli del rischio) arrotondata per difetto al passo, 0 se il risultato non e' positivo
double PkRiskPct(const double sumR, const double sumR2)
  {
   if(sumR <= 0.0 || sumR2 <= 0.0) return 0.0;
   const double step = MathMax(0.05, InpRiskStepPct);
   double f = 100.0 * InpRiskKelly * (sumR / sumR2);
   if(f > InpRiskMaxPct) f = InpRiskMaxPct;
   return MathFloor(f / step + 1.0e-9) * step;
  }

//+------------------------------------------------------------------+
//| Classi (ora, posizione nella sequenza, intensita', volume, regime,  |
//| ADX, percorso gia' fatto): quanti segnali raggiungono il target,    |
//| quanto va contro prima (da cui lo stop che li lascia passare),      |
//| risultato della gestione scelta in-sample e fuori campione. Poi i   |
//| due test: scelta degli orari e scelta della miglior classe (filtro).|
//+------------------------------------------------------------------+
string PkClasses(const int t, const int n, const double medAtr)
  {
   const double minIs = MathMax(30.0, g_minN / 2.0);
   const double minOos = MathMax(10.0, minIs / 3.0);
   const bool havePol = (g_pkP0v >= 0);
   const int nJ = g_pkNj;
   bool mk[];
   int cl[], ncl[];
   double rr[];
   ArrayResize(mk, n); ArrayResize(cl, n * 8); ArrayResize(ncl, n); ArrayResize(rr, n);
   int tmp[8];
   for(int i = 0; i < n; i++)
     {
      ncl[i] = PkCls(i, tmp);
      for(int q = 0; q < ncl[i]; q++) cl[i * 8 + q] = tmp[q];
      double sl = 1.0;
      if(havePol) sl = (double)(g_pkP0s + 1) * 0.5 * ((g_pkP0v == 0) ? g_prAtr[i] : g_pkMed);
      rr[i] = havePol ? g_pkNet[i] / sl : 0.0;
     }
   ArrayInitialize(g_pkCls, 0.0);
   ArrayInitialize(g_pkSl, 0.0);
   string tb = "";
   double qa[], qp[];
   ArrayResize(qa, n); ArrayResize(qp, n);
   double st[];
   const int grpEnd[8] = {0, 24, 32, 38, 42, 46, 50, 54};
   const string grpName[8] = {"Tutti", "Ora d'ingresso (server + offset), volume tick medio dell'ora in rapporto alla media", "Posizione nella sequenza di segnali nello stesso verso", "Intensit&agrave; della candela del segnale (TR/ATR)",
                              "Volume tick delle ultime 30 barre M1 rispetto al normale dell'ora", "Regime di volatilit&agrave;", "ADX", "Percorso gi&agrave; fatto dall'inizio della sequenza (solo dal 2&deg; segnale)"};
   int grp = 0, shownGrp = -1;
   for(int c = 0; c < PK_NCLS; c++)
     {
      ArrayResize(qa, n); ArrayResize(qp, n);                         // PkQ accorcia i vettori
      int m = 0, nr = 0, ng = 0, nq = 0;
      double sIs = 0.0, sIs2 = 0.0, nIs = 0.0;
      for(int i = 0; i < n; i++)
        {
         bool inCl = false;
         for(int q = 0; q < ncl[i]; q++) if(cl[i * 8 + q] == c) { inCl = true; break; }
         mk[i] = inCl;
         if(!inCl) continue;
         m++;
         const int gc = PkGoodCode(i);
         if(gc >= 1)
           {
            nr++;
            if(gc == 2) ng++;
            qa[nq] = g_prFm[(i * 2) * nJ + g_pkGoodJ] / g_prAtr[i];
            qp[nq] = g_prFm[(i * 2) * nJ + g_pkGoodJ];
            nq++;
           }
         if(havePol && g_prSmp[i] == 0) { sIs += rr[i]; sIs2 += rr[i] * rr[i]; nIs += 1.0; }
        }
      if(m < 1) continue;
      PkStat(mk, g_pkNet, n, st);
      const int o = c * 8;
      g_pkCls[o] = (double)m; g_pkCls[o + 1] = st[0]; g_pkCls[o + 2] = st[1]; g_pkCls[o + 3] = st[2]; g_pkCls[o + 4] = st[3]; g_pkCls[o + 5] = st[4]; g_pkCls[o + 6] = st[5];
      const double fr = (havePol && st[0] >= 5.0 && st[3] >= minOos / 2.0 && st[1] > 0.0 && st[4] > 0.0) ? PkRiskPct(sIs, sIs2) : 0.0;
      g_pkCls[o + 7] = fr;
      double a50 = 0.0, a75 = 0.0, a90 = 0.0, p50 = 0.0, p75 = 0.0, p90 = 0.0;
      if(nq > 0) { PkQ(qa, nq, a50, a75, a90); PkQ(qp, nq, p50, p75, p90); }
      if(c == 0) { g_pkSl[0] = 100.0 * (double)nr / (double)m; g_pkSl[1] = a75; g_pkSl[2] = p75; g_pkSl[3] = a90; g_pkSl[4] = p90; }
      while(grp < 7 && c > grpEnd[grp]) grp++;
      if(grp != shownGrp)
        {
         tb += "<tr><th colspan='14' style='text-align:left'>" + grpName[grp] + "</th></tr>";
         shownGrp = grp;
        }
      const string vol = (c >= 1 && c <= 24) ? F2(g_hrVol[c - 1]) : string("-");
      tb += "<tr" + string((double)m < (double)InpPeakMinN ? " class='thin'" : "") + "><td>" + HtmlEsc(PkClsLbl(c)) + "</td>" + Td(IS(m)) + Td(vol) + Td(F0(100.0 * (double)nr / (double)m) + "%") + Td(F0(100.0 * (double)ng / (double)m) + "%") +
            Td(nq > 0 ? F2(a50) : string("-")) + Td(nq > 0 ? (F2(a75) + " / " + F0(p75) + " pt") : string("-")) + Td(nq > 0 ? (F2(a90) + " / " + F0(p90) + " pt") : string("-")) +
            Td(havePol ? F0(st[0]) : string("-")) + Td(havePol ? F1(st[1]) : string("-"), ColSign(st[1])) + Td(havePol ? F0(st[3]) : string("-")) +
            Td(havePol ? F1(st[4]) : string("-"), ColSign(st[4])) + Td(havePol ? F2(st[5]) : string("-"), ColT(st[5])) + Td(havePol ? F1(fr) : string("-")) + "</tr>";
      g_dg += "PKCLS|" + g_tfName[t] + "|" + IS(c) + "|n|" + IS(m) + "|reach|" + F0(100.0 * (double)nr / (double)m) + "|good|" + F0(100.0 * (double)ng / (double)m) + "|mae75atr|" + F2(a75) + "|mae75pt|" + F0(p75) + "|mae90atr|" + F2(a90) +
              "|isn|" + F0(st[0]) + "|isnet|" + F1(st[1]) + "|oosn|" + F0(st[3]) + "|oosnet|" + F1(st[4]) + "|oost|" + F2(st[5]) + "|risk|" + F1(fr) + "\n";
     }
   //--- test degli orari: ore scelte sul primo periodo (netto positivo, t semplice sufficiente), misurate sul resto
   ArrayInitialize(g_pkHr, 0.0);
   ArrayInitialize(g_pkFl, 0.0);
   g_pkFl[0] = -1.0;
   int nSelH = 0;
   ArrayResize(g_pkRiskMask, n);
   for(int i = 0; i < n; i++) { mk[i] = false; g_pkRiskMask[i] = true; }
   g_pkRiskSel = false;
   string hv = "";
   if(havePol)
     {
      bool selH[24];
      for(int h = 0; h < 24; h++)
        {
         const int o = (1 + h) * 8;
         selH[h] = (g_pkCls[o + 1] >= (double)InpPeakMinN && g_pkCls[o + 2] > 0.0 && g_pkCls[o + 3] >= InpSelMinT);
         if(selH[h]) nSelH++;
        }
      for(int i = 0; i < n; i++) mk[i] = selH[(int)g_prHr[i]];
      if(nSelH > 0)
        {
         PkStat(mk, g_pkNet, n, st);
         g_pkHr[0] = (double)nSelH; g_pkHr[1] = st[3]; g_pkHr[2] = st[4]; g_pkHr[3] = st[5];
         for(int i = 0; i < n; i++) mk[i] = true;
         PkStat(mk, g_pkNet, n, st);
         g_pkHr[4] = st[4];
         if(g_pkHr[1] >= minOos) { g_pkRiskSel = true; for(int i = 0; i < n; i++) g_pkRiskMask[i] = selH[(int)g_prHr[i]]; }
        }
      //--- volume alto contro volume basso (ore con volume tick medio sopra o sotto la media), stessa gestione
      for(int g = 0; g < 2; g++)
        {
         for(int i = 0; i < n; i++) mk[i] = ((g_hrVol[(int)g_prHr[i]] >= 1.0) == (g == 0));
         PkStat(mk, g_pkNet, n, st);
         hv += string(g == 0 ? "ore con volume tick sopra la media: " : "; ore con volume sotto la media: ") + "in-sample " + F0(st[0]) + " segnali netto " + Sg(st[1]) + " pt, fuori campione " + F0(st[3]) + " segnali netto " + Sg(st[4]) + " pt (t " + F2(st[5]) + ")";
         g_dg += "PKVOL|" + g_tfName[t] + "|" + string(g == 0 ? "high" : "low") + "|isn|" + F0(st[0]) + "|isnet|" + F1(st[1]) + "|oosn|" + F0(st[3]) + "|oosnet|" + F1(st[4]) + "|oost|" + F2(st[5]) + "\n";
        }
      //--- test del filtro: la miglior classe (sequenza, intensita', volume, regime, ADX, percorso) in-sample, misurata sul resto
      int bc = -1;
      double bt = -1.0e18;
      for(int c = 25; c < PK_NCLS; c++)
        {
         const int o = c * 8;
         if(g_pkCls[o + 1] < (double)InpPeakMinN || g_pkCls[o + 2] <= 0.0) continue;
         if(bc < 0 || g_pkCls[o + 3] > bt) { bc = c; bt = g_pkCls[o + 3]; }
        }
      if(bc >= 0)
        {
         const int o = bc * 8;
         g_pkFl[0] = (double)bc; g_pkFl[1] = g_pkCls[o + 4]; g_pkFl[2] = g_pkCls[o + 5]; g_pkFl[3] = g_pkCls[o + 6]; g_pkFl[4] = g_pkP0[4]; g_pkFl[5] = g_pkCls[o + 1]; g_pkFl[6] = g_pkCls[o + 2];
        }
     }
   string hs = "<div class='note'>Ogni riga &egrave; un modo di raggruppare i segnali. <b>Raggiunge</b> = tocca il target di " + ThrLbl(g_pkTp[g_pkGoodJ]) + " ATR entro la finestra, qualunque sia lo stop; <b>buoni</b> = lo raggiunge senza toccare " + ThrLbl((double)(g_pkGoodS + 1) * 0.5) + " ATR. "
               "<b>Contro prima del target</b> = quanto il prezzo va contro (ATR del segnale e punti) prima di arrivare al target, fra i segnali che lo raggiungono: uno stop pari al 75% o al 90% li lascia passare il 75% o il 90% delle volte. "
               "Il netto &egrave; quello della gestione scelta in-sample (" + PkP0Lbl(medAtr) + "), in punti per segnale. <b>Rischio %</b> = un quarto del Kelly calcolato sul solo primo periodo, solo se anche fuori campione la classe &egrave; positiva, arrotondato per difetto a passi di " + ThrLbl(InpRiskStepPct) + " e limitato a " + ThrLbl(InpRiskMaxPct) + "%: &egrave; un'indicazione, non una conferma. "
               "Le classi con meno di " + IS(InpPeakMinN) + " segnali sono grigie.</div>";
   hs += "<table><tr><th>Classe</th><th>Segnali</th><th>Volume ora</th><th>Raggiunge</th><th>Buoni</th><th>Contro prima del target, mediana (ATR)</th><th>75% (ATR / pt)</th><th>90% (ATR / pt)</th>"
         "<th>In-sample: segnali</th><th>netto (pt)</th><th>Fuori campione: segnali</th><th>netto (pt)</th><th>t</th><th>Rischio %</th></tr>" + tb + "</table>";
   if(hv != "") hs += "<div class='note'>Volume tick: " + hv + ".</div>";
   return hs;
  }

//+------------------------------------------------------------------+
//| Scala del rischio: sui record della gestione scelta (orari scelti  |
//| se il test degli orari ne ha scelti) il risultato di ogni posizione|
//| in multipli del rischio (netto diviso la distanza dello stop). Per |
//| ogni rischio % della scala, crescita e drawdown fuori campione    |
//| componendo le posizioni nell'ordine del tempo (le posizioni sono   |
//| trattate come indipendenti e una dopo l'altra), lotti per saldo e  |
//| patrimonio al lancio.                                             |
//+------------------------------------------------------------------+
string PkRisk(const int t, const int n, const double medAtr)
  {
   g_pkRk[0] = 0.0; g_pkRk[1] = 0.0; g_pkRk[2] = 0.0;
   if(g_pkP0v < 0) return "";
   const double minIs = MathMax(30.0, g_minN / 2.0);
   const double minOos = MathMax(10.0, minIs / 3.0);
   double sr = 0.0, sr2 = 0.0, nIs = 0.0;
   for(int i = 0; i < n; i++)
     {
      if(!g_pkRiskMask[i] || g_prSmp[i] != 0) continue;
      const double sl = (double)(g_pkP0s + 1) * 0.5 * ((g_pkP0v == 0) ? g_prAtr[i] : g_pkMed);
      const double r = g_pkNet[i] / sl;
      sr += r; sr2 += r * r; nIs += 1.0;
     }
   //--- il rischio si propone solo se la gestione (o gli orari scelti) regge fuori campione
   double oosMean = g_pkRiskSel ? g_pkHr[2] : g_pkP0[4];
   double oosT = g_pkRiskSel ? g_pkHr[3] : g_pkP0[5];
   double oosN = g_pkRiskSel ? g_pkHr[1] : g_pkP0[3];
   const bool proven = (oosN >= minOos && oosMean > 0.0 && oosT >= 2.0 && nIs >= 10.0);
   const double rec = proven ? PkRiskPct(sr, sr2) : 0.0;
   g_pkRk[0] = rec;
   const double slMed = (double)(g_pkP0s + 1) * 0.5 * ((g_pkP0v == 0) ? medAtr : g_pkMed);
   const double step = MathMax(0.05, InpRiskStepPct);
   string tb = "";
   for(double pct = step; pct <= InpRiskMaxPct + 1.0e-9; pct += step)
     {
      double eq = 1.0, pk = 1.0, dd = 0.0;
      bool ruin = false;
      for(int i = 0; i < n && !ruin; i++)
        {
         if(!g_pkRiskMask[i] || g_prSmp[i] == 0) continue;
         const double sl = (double)(g_pkP0s + 1) * 0.5 * ((g_pkP0v == 0) ? g_prAtr[i] : g_pkMed);
         eq *= 1.0 + (pct / 100.0) * g_pkNet[i] / sl;
         if(eq <= 0.0) { ruin = true; eq = 0.0; }
         if(eq > pk) pk = eq;
         if((pk - eq) / pk > dd) dd = (pk - eq) / pk;
        }
      if(MathAbs(pct - rec) < 1.0e-9) { g_pkRk[1] = 100.0 * (eq - 1.0); g_pkRk[2] = 100.0 * dd; }
      string lots = "n.d.", lotsE = "n.d.", lotsK = "n.d.", mon = "n.d.";
      if(g_money && g_pv > 0.0 && slMed > 0.0)
        {
         const double per = slMed * g_pv;                       // perdita in valuta del conto per 1.00 lotto allo stop
         lotsK = PkLots(pct / 100.0 * 1000.0 / per);
         if(g_acctBal > 0.0) { lots = PkLots(pct / 100.0 * g_acctBal / per); mon = DoubleToString(pct / 100.0 * g_acctBal, 2) + " " + g_ccy; }
         if(g_acctEq > 0.0) lotsE = PkLots(pct / 100.0 * g_acctEq / per);
        }
      tb += "<tr" + string(MathAbs(pct - rec) < 1.0e-9 ? " style='background:#222733'" : "") + "><td>" + ThrLbl(pct) + "%</td>" + Td(mon) + Td(lots) + Td(lotsE) + Td(lotsK) +
            Td(ruin ? string("rovina") : (Sg(100.0 * (eq - 1.0), 1) + "%"), ColSign(eq - 1.0)) + Td(F1(100.0 * dd) + "%") + "</tr>";
      g_dg += "PKRISK|" + g_tfName[t] + "|pct|" + ThrLbl(pct) + "|growth|" + F1(100.0 * (eq - 1.0)) + "|dd|" + F1(100.0 * dd) + "|lotsbal|" + lots + "|lotseq|" + lotsE + "|lots1000|" + lotsK + "\n";
     }
   const string base = g_pkRiskSel ? "sugli orari scelti in-sample" : "su tutti i segnali";
   string hs = "<div class='note'>Gestione: " + PkP0Lbl(medAtr) + ", " + base + ". Stop medio circa <b>" + F0(slMed) + " pt</b>" + string(g_money ? (" (perdita di circa " + MnyU(slMed) + " per posizione con " + LotTxt() + " lotti allo stop)") : "") + ". "
               "Saldo " + string(g_acctBal > 0.0 ? DoubleToString(g_acctBal, 2) + " " + g_ccy : "n.d.") + ", patrimonio " + string(g_acctEq > 0.0 ? DoubleToString(g_acctEq, 2) + " " + g_ccy : "n.d.") + " al lancio dello script. "
               "<b>Rischio proposto: " + ThrLbl(rec) + "%</b>" + string(proven ? "" : " &mdash; nessun rischio giustificato: la gestione non &egrave; positiva con t &ge; 2 fuori campione, quindi non c'&egrave; un vantaggio verificato da dimensionare") +
               ". La scala sotto &egrave; indicativa: posizioni trattate come indipendenti e consecutive, senza sovrapposizioni, slittamenti e variazioni dello spread.</div>";
   hs += "<table><tr><th>Rischio per posizione</th><th>Importo a rischio (saldo)</th><th>Lotti (saldo)</th><th>Lotti (patrimonio)</th><th>Lotti ogni 1000 " + g_ccy + "</th><th>Crescita fuori campione</th><th>Drawdown massimo fuori campione</th></tr>" + tb + "</table>";
   return hs;
  }

//--- grafico a linee, y[serie * nX + x] (1.0e300 = mancante); etichette dell'asse x in xl
string PkSvgLines(const double &y[], const int nS, const int nX, const string &nm[], const string &xl[], const string &unit)
  {
   if(nX < 2) return "";
   double lo = 1.0e300, hi = -1.0e300;
   for(int q = 0; q < nS * nX; q++)
     {
      if(y[q] > 1.0e299) continue;
      lo = MathMin(lo, y[q]); hi = MathMax(hi, y[q]);
     }
   if(lo > hi) return "";
   lo = MathMin(lo, 0.0); hi = MathMax(hi, 0.0);
   if(hi - lo < 1.0e-9) hi = lo + 1.0;
   const string cols[6] = {"#5e81ac", "#a3be8c", "#ebcb8b", "#bf616a", "#d8dee9", "#b48ead"};
   const double pl = 46.0, pr = 22.0, pt0 = 8.0, pb = 50.0;
   const double pw = 640.0 - pl - pr, ph = 246.0 - pt0 - pb;
   string sv = "<svg viewBox='0 0 640 246' width='100%' style='max-width:700px;background:#2e3440;border-radius:6px'>";
   const double y0 = pt0 + ph * hi / (hi - lo);
   sv += "<line x1='" + DoubleToString(pl, 0) + "' y1='" + DoubleToString(y0, 1) + "' x2='" + DoubleToString(pl + pw, 0) + "' y2='" + DoubleToString(y0, 1) + "' stroke='#4c566a'/>";
   for(int s = 0; s < nS; s++)
     {
      string pts = "";
      int np = 0;
      for(int x = 0; x < nX; x++)
        {
         const double v = y[s * nX + x];
         if(v > 1.0e299) continue;
         pts += DoubleToString(pl + pw * (double)x / (double)(nX - 1), 1) + "," + DoubleToString(pt0 + ph * (hi - v) / (hi - lo), 1) + " ";
         np++;
        }
      if(np >= 2) sv += "<polyline fill='none' stroke='" + cols[s % 6] + "' stroke-width='" + string(s == nS - 1 ? "2" : "1.5") + "' points='" + pts + "'/>";
     }
   for(int x = 0; x < nX; x++)
      sv += "<text x='" + DoubleToString(pl + pw * (double)x / (double)(nX - 1), 1) + "' y='" + DoubleToString(pt0 + ph + 12.0, 0) + "' fill='#d8dee9' font-size='9' text-anchor='middle'>" + xl[x] + "</text>";
   sv += "<text x='2' y='" + DoubleToString(pt0 + 8.0, 0) + "' fill='#d8dee9' font-size='10'>" + F2(hi) + "</text>";
   sv += "<text x='2' y='" + DoubleToString(pt0 + ph, 0) + "' fill='#d8dee9' font-size='10'>" + F2(lo) + "</text>";
   sv += "<text x='" + DoubleToString(pl + pw, 0) + "' y='" + DoubleToString(pt0 + ph + 42.0, 0) + "' fill='#d8dee9' font-size='9' text-anchor='end'>minuti dall'ingresso &middot; " + unit + "</text>";
   double lx = pl;
   for(int s = 0; s < nS; s++)
     {
      sv += "<rect x='" + DoubleToString(lx, 0) + "' y='" + DoubleToString(pt0 + ph + 19.0, 0) + "' width='10' height='4' fill='" + cols[s % 6] + "'/><text x='" + DoubleToString(lx + 13.0, 0) + "' y='" + DoubleToString(pt0 + ph + 25.0, 0) + "' fill='#d8dee9' font-size='9'>" + nm[s] + "</text>";
      lx += 14.0 + 6.0 * (double)StringLen(nm[s]);
     }
   return sv + "</svg>";
  }

//--- percorso medio dei segnali per regime di volatilita' (rendimento in ATR e ampiezza media delle barre M1 in ATR per barra) a ogni orizzonte
void PkPaths(const int n, string &svgRet, string &svgRng)
  {
   svgRet = ""; svgRng = "";
   const int nH = g_nH;
   if(nH < 2 || ArraySize(g_m1Rcum) < g_n1 + 1) return;
   double sR[], sG[], cN[];
   ArrayResize(sR, 5 * nH); ArrayResize(sG, 5 * nH); ArrayResize(cN, 5 * nH);
   ArrayInitialize(sR, 0.0); ArrayInitialize(sG, 0.0); ArrayInitialize(cN, 0.0);
   bool okc[];
   int recBar[];
   ArrayResize(okc, nH); ArrayResize(recBar, nH);
   for(int i = 0; i < n; i++)
     {
      const int j = g_prJ[i];
      if(MgHorizons(j, nH, okc, recBar) < 0) continue;
      const double o = g_m1Open[j], atr = g_prAtr[i];
      const int d = (int)g_prDir[i];
      const int rg = (int)g_prRg[i];
      int prev = j - 1;
      for(int c = 0; c < nH; c++)
        {
         if(!okc[c]) continue;
         const int rb = recBar[c];
         const double ret = (double)d * (g_m1Close[rb] - o) / g_pt / atr;
         const double rng = (rb > prev) ? (g_m1Rcum[rb + 1] - g_m1Rcum[prev + 1]) / (double)(rb - prev) / atr : 0.0;
         prev = rb;
         for(int z = 0; z < 2; z++)
           {
            const int sl = (z == 0) ? rg : 4;
            if(sl > 4) continue;
            sR[sl * nH + c] += ret; sG[sl * nH + c] += rng; cN[sl * nH + c] += 1.0;
           }
        }
     }
   double yR[], yG[];
   ArrayResize(yR, 5 * nH); ArrayResize(yG, 5 * nH);
   for(int q = 0; q < 5 * nH; q++)
     {
      yR[q] = (cN[q] >= 10.0) ? sR[q] / cN[q] : 1.0e300;
      yG[q] = (cN[q] >= 10.0) ? sG[q] / cN[q] : 1.0e300;
     }
   string nm[5];
   string xl[];
   nm[0] = "LOW"; nm[1] = "NORMAL"; nm[2] = "HIGH"; nm[3] = "EXTREME"; nm[4] = "tutti";
   ArrayResize(xl, nH);
   for(int c = 0; c < nH; c++) xl[c] = IS(g_hor[c]);
   svgRet = PkSvgLines(yR, 5, nH, nm, xl, "movimento medio nel verso del segnale, in ATR");
   svgRng = PkSvgLines(yG, 5, nH, nm, xl, "ampiezza media di una barra M1, in ATR");
  }

//--- istogramma dei picchi (ritiro di riferimento) in ATR, classi di 0.5 ATR fino a 12, l'ultima raccoglie il resto
string PkSvgHist(const int n)
  {
   const int NB = 25, nK = g_pkNk, kr = g_pkRefK;
   int h[25];
   for(int b = 0; b < NB; b++) h[b] = 0;
   for(int i = 0; i < n; i++)
     {
      const int b = (int)(g_prPv[i * nK + kr] / g_prAtr[i] / 0.5);
      h[(b >= NB) ? NB - 1 : b]++;
     }
   int mx = 1;
   for(int b = 0; b < NB; b++) mx = MathMax(mx, h[b]);
   const double pl = 30.0, pt0 = 14.0, pw = 600.0, ph = 150.0;
   string sv = "<svg viewBox='0 0 640 200' width='100%' style='max-width:700px;background:#2e3440;border-radius:6px'>";
   const double bw = pw / (double)NB;
   for(int b = 0; b < NB; b++)
     {
      const double hh = ph * (double)h[b] / (double)mx;
      sv += "<rect x='" + DoubleToString(pl + bw * (double)b + 1.0, 1) + "' y='" + DoubleToString(pt0 + ph - hh, 1) + "' width='" + DoubleToString(bw - 2.0, 1) + "' height='" + DoubleToString(hh, 1) + "' fill='#5e81ac'/>";
      if(b % 2 == 0) sv += "<text x='" + DoubleToString(pl + bw * (double)b, 1) + "' y='" + DoubleToString(pt0 + ph + 12.0, 0) + "' fill='#d8dee9' font-size='9'>" + string(b == NB - 1 ? ">" : "") + F1(0.5 * (double)b) + "</text>";
     }
   const double xm = pl + pw * g_pkRef[2] / 12.5, x9 = pl + pw * g_pkRef[3] / 12.5;
   if(xm < pl + pw) sv += "<line x1='" + DoubleToString(xm, 1) + "' y1='" + DoubleToString(pt0, 0) + "' x2='" + DoubleToString(xm, 1) + "' y2='" + DoubleToString(pt0 + ph, 0) + "' stroke='#a3be8c' stroke-dasharray='4 3'/><text x='" + DoubleToString(xm + 3.0, 1) + "' y='" + DoubleToString(pt0 + 9.0, 0) + "' fill='#a3be8c' font-size='10'>mediana " + F2(g_pkRef[2]) + "</text>";
   if(x9 < pl + pw) sv += "<line x1='" + DoubleToString(x9, 1) + "' y1='" + DoubleToString(pt0, 0) + "' x2='" + DoubleToString(x9, 1) + "' y2='" + DoubleToString(pt0 + ph, 0) + "' stroke='#ebcb8b' stroke-dasharray='4 3'/><text x='" + DoubleToString(x9 + 3.0, 1) + "' y='" + DoubleToString(pt0 + 20.0, 0) + "' fill='#ebcb8b' font-size='10'>90% " + F2(g_pkRef[3]) + "</text>";
   sv += "<text x='" + DoubleToString(pl + pw, 0) + "' y='196' fill='#d8dee9' font-size='9' text-anchor='end'>picco in ATR, ritiro " + ThrLbl(g_pkK[kr]) + " ATR &middot; altezza = numero di segnali</text></svg>";
   return sv;
  }

//--- una sequenza reale: prezzo M1 (chiusure), ingressi dei segnali (triangoli), prezzo del primo ingresso, target e stop del segnale buono, picco
string PkSvgRun(const int t, const int i0)
  {
   const int nK = g_pkNk, kr = g_pkRefK;
   const int k0 = g_prK[i0], d = (int)g_prDir[i0];
   const double atr = g_prAtr[i0], o = g_m1Open[g_prJ[i0]];
   int sb[40];
   int ns = 0, prevBur = (int)g_bur[k0];
   sb[ns] = g_prJ[i0]; ns++;
   const int kEnd = g_tfOff[t] + g_tfCnt[t];
   for(int k = k0 + 1; k < kEnd && ns < 40; k++)
     {
      if(g_dir[k] == 0) continue;
      if((int)g_dir[k] != d || (int)g_bur[k] != prevBur + 1) break;
      const int jb = StressBase(k);
      if(jb < 0) break;
      sb[ns] = jb; ns++; prevBur++;
     }
   const int jPk = g_prPb[i0 * nK + kr];
   const double vPk = g_prPv[i0 * nK + kr];
   const int jA = MathMax(0, g_prJ[i0] - 40);
   const int jB = MathMin(g_n1 - 1, MathMax(jPk, sb[ns - 1]) + 40);
   if(jB - jA < 5) return "";
   const int stp = MathMax(1, (jB - jA) / 200);
   const double tpP = o + (double)d * g_pkTp[g_pkGoodJ] * atr * g_pt, slP = o - (double)d * (double)(g_pkGoodS + 1) * 0.5 * atr * g_pt, pkP = o + (double)d * vPk * g_pt;
   double lo = MathMin(MathMin(tpP, slP), MathMin(o, pkP)), hi = MathMax(MathMax(tpP, slP), MathMax(o, pkP));
   for(int b = jA; b <= jB; b += stp) { lo = MathMin(lo, g_m1Close[b]); hi = MathMax(hi, g_m1Close[b]); }
   if(hi - lo < g_pt) hi = lo + g_pt;
   const double pl = 6.0, pt0 = 14.0, pw = 348.0, ph = 128.0;
   string sv = "<svg viewBox='0 0 360 170' width='360' style='background:#2e3440;border-radius:6px;margin:4px'>";
   string line = "";
   for(int b = jA; b <= jB; b += stp)
      line += DoubleToString(pl + pw * (double)(b - jA) / (double)(jB - jA), 1) + "," + DoubleToString(pt0 + ph * (hi - g_m1Close[b]) / (hi - lo), 1) + " ";
   const double yo = pt0 + ph * (hi - o) / (hi - lo), yt = pt0 + ph * (hi - tpP) / (hi - lo), ys = pt0 + ph * (hi - slP) / (hi - lo), yp = pt0 + ph * (hi - pkP) / (hi - lo);
   sv += "<line x1='" + DoubleToString(pl, 0) + "' y1='" + DoubleToString(yo, 1) + "' x2='" + DoubleToString(pl + pw, 0) + "' y2='" + DoubleToString(yo, 1) + "' stroke='#5e81ac' stroke-dasharray='3 3'/>";
   sv += "<line x1='" + DoubleToString(pl, 0) + "' y1='" + DoubleToString(yt, 1) + "' x2='" + DoubleToString(pl + pw, 0) + "' y2='" + DoubleToString(yt, 1) + "' stroke='#a3be8c' stroke-dasharray='2 4'/>";
   sv += "<line x1='" + DoubleToString(pl, 0) + "' y1='" + DoubleToString(ys, 1) + "' x2='" + DoubleToString(pl + pw, 0) + "' y2='" + DoubleToString(ys, 1) + "' stroke='#bf616a' stroke-dasharray='2 4'/>";
   sv += "<polyline fill='none' stroke='#d8dee9' stroke-width='1.2' points='" + line + "'/>";
   for(int q = 0; q < ns; q++)
     {
      const double x = pl + pw * (double)(sb[q] - jA) / (double)(jB - jA);
      const double y = pt0 + ph * (hi - g_m1Open[sb[q]]) / (hi - lo);
      sv += "<path d='M" + DoubleToString(x - 4.0, 1) + "," + DoubleToString(y + (d > 0 ? 8.0 : -8.0), 1) + " L" + DoubleToString(x + 4.0, 1) + "," + DoubleToString(y + (d > 0 ? 8.0 : -8.0), 1) + " L" + DoubleToString(x, 1) + "," + DoubleToString(y, 1) + " Z' fill='" + string(d > 0 ? "#a3be8c" : "#bf616a") + "'/>";
     }
   const double xp = pl + pw * (double)(jPk - jA) / (double)(jB - jA);
   sv += "<circle cx='" + DoubleToString(xp, 1) + "' cy='" + DoubleToString(yp, 1) + "' r='4' fill='none' stroke='#ebcb8b' stroke-width='2'/>";
   sv += "<text x='6' y='10' fill='#d8dee9' font-size='10'>" + TimeToString(g_m1Time[g_prJ[i0]], TIME_DATE | TIME_MINUTES) + " &middot; " + string(d > 0 ? "BUY" : "SELL") + " x" + IS(ns) + "</text>";
   sv += "<text x='6' y='164' fill='#ebcb8b' font-size='10'>picco +" + F0(vPk) + " pt (" + F1(vPk / atr) + " ATR) dopo " + F0(PkPeakMin(i0, kr)) + " min (" + F1(PkPeakMin(i0, kr) / MathMax(1.0, (double)g_tfSec[t] / 60.0)) + " candele)</text></svg>";
   return sv;
  }

bool   g_pkOk = false;
double g_pkMedAtr = 0.0;
string g_cPkA = "", g_cPkB = "", g_cPkC = "", g_cPkD = "";       // testi per il riepilogo della serie: picchi, stop e target, orari e filtri, rischio
int    g_pkEvalTf = 0, g_pkPosTf = 0;

//+------------------------------------------------------------------+
//| Analisi di un TF: raccoglie i record, costruisce le tabelle e i    |
//| grafici, esegue i tre test fuori campione (gestione scelta, orari, |
//| filtro per classe) e scrive riga di sintesi, dettaglio e scheda.   |
//+------------------------------------------------------------------+
void PkAnalyze(const int t, const int ix)
  {
   g_pkSumRow = ""; g_pkDet = ""; g_pkCard = "";
   g_pkTest[0] = -1; g_pkTest[1] = -1; g_pkTest[2] = -1;
   g_pkP0v = -1;
   g_pkOk = false;
   g_pkMed = PkMedianAtr(t);
   const int n = PkCollect(t);
   if(n < 30)
     {
      g_pkSumRow = "<tr class='thin'><td>" + g_tfName[t] + "</td><td colspan='13'>campione insufficiente (" + IS(n) + " segnali misurabili su " + IS(g_pkNsig) + ")</td></tr>";
      g_pkCard = "campione insufficiente (" + IS(n) + " segnali misurabili)";
      return;
     }
   const double minIs = MathMax(30.0, g_minN / 2.0);
   const double minOos = MathMax(10.0, minIs / 3.0);
   const double tfMin = (double)g_tfSec[t] / 60.0;
   double am[];
   ArrayResize(am, n);
   for(int i = 0; i < n; i++) am[i] = g_prAtr[i];
   const double medAtr = MedianOf(am, n);
   g_pkOk = true;
   g_pkMedAtr = medAtr;
   const string tPk = PkPeaks(t, n);
   const string tSq = PkSeq(t, n);
   const string tGr = PkGrid(t, n, medAtr);
   const string tCl = PkClasses(t, n, medAtr);
   const string tRk = PkRisk(t, n, medAtr);
   string svRet = "", svRng = "", svHist = "", svRuns = "";
   if(InpPeakCharts)
     {
      PkPaths(n, svRet, svRng);
      svHist = PkSvgHist(n);
      if(g_tf[t] == InpPeakExampleTF && InpPeakExamples > 0)
        {
         int cand[];
         ArrayResize(cand, 0, 1024);
         for(int i = 0; i < n; i++)
           {
            if(g_prBur[i] != 1) continue;
            int run = 1;
            const int kEnd = g_tfOff[t] + g_tfCnt[t];
            int pb = 1;
            for(int k = g_prK[i] + 1; k < kEnd && run < 3; k++)
              {
               if(g_dir[k] == 0) continue;
               if(g_dir[k] != g_prDir[i] || (int)g_bur[k] != pb + 1) break;
               run++; pb++;
              }
            if(run < 3) continue;
            const int nc = ArraySize(cand);
            ArrayResize(cand, nc + 1, 1024);
            cand[nc] = i;
           }
         const int nc = ArraySize(cand);
         const int ne = MathMin(nc, InpPeakExamples);
         for(int q = 0; q < ne; q++)
           {
            const int ci = cand[(ne > 1) ? (int)((double)q * (double)(nc - 1) / (double)(ne - 1)) : 0];
            svRuns += PkSvgRun(t, ci);
           }
        }
     }
   //--- esiti dei tre test
   if(g_pkP0v >= 0)
     {
      g_pkTest[0] = OosVerdict(g_pkP0[3] < minOos, g_pkP0[4], g_pkP0[5] >= 2.0);
      if(g_pkP0[3] >= minOos) g_cdEval[ix]++;
      if(g_pkTest[0] == 1) CdPos(ix, "picchi: stop e target");
     }
   if(g_pkHr[0] > 0.0)
     {
      g_pkTest[1] = OosVerdict(g_pkHr[1] < minOos, g_pkHr[2], g_pkHr[3] >= 2.0 && g_pkHr[2] > g_pkHr[4]);
      if(g_pkHr[1] >= minOos) g_cdEval[ix]++;
      if(g_pkTest[1] == 1) CdPos(ix, "picchi: orari");
     }
   if(g_pkFl[0] >= 0.0)
     {
      g_pkTest[2] = OosVerdict(g_pkFl[1] < minOos, g_pkFl[2], g_pkFl[3] >= 2.0 && g_pkFl[2] > g_pkFl[4]);
      if(g_pkFl[1] >= minOos) g_cdEval[ix]++;
      if(g_pkTest[2] == 1) CdPos(ix, "picchi: filtro per classe");
     }
   for(int q = 0; q < 3; q++)
     {
      if(g_pkTest[q] < 0) continue;
      if(g_pkTest[q] != 0) g_pkEvalTf++;
      if(g_pkTest[q] == 1) g_pkPosTf++;
     }
   //--- scheda del TF per il riepilogo (corta: il dettaglio e' nel report)
   string cd = "ritiro " + ThrLbl(g_pkK[g_pkRefK]) + " ATR, " + IS(n) + " segnali su " + IS(g_pkNsig) + ": picco mediano " + F0(g_pkRef[0]) + " pt (" + F2(g_pkRef[2]) + " ATR), 90% sotto " + F0(g_pkRef[1]) + " pt (" + F2(g_pkRef[3]) + " ATR), dopo " + PkMin(g_pkRef[4], tfMin) +
               "; prima del picco il prezzo va contro di " + F0(g_pkRef[5]) + " pt (" + F2(g_pkRef[6]) + " ATR) alla mediana. ";
   string st = "";
   if(g_pkP0v >= 0)
      st = "migliore in-sample su " + IS(g_pkNj * PK_NSL * ((g_pkMed > 0.0) ? 2 : 1)) + " celle = " + PkP0Lbl(medAtr) + "; in-sample " + Sg(g_pkP0[1]) + " pt su " + F0(g_pkP0[0]) + ", fuori campione " + Sg(g_pkP0[4]) + " pt su " + F0(g_pkP0[3]) + " (t " + F2(g_pkP0[5]) + ", " + VerdText(g_pkTest[0]) + "); " +
           F0(g_pkP0[6]) + "% a target, " + F0(g_pkP0[7]) + "% a stop, " + F0(g_pkP0[8]) + "% a fine finestra";
   else
      st = "nessuna cella valutabile in-sample (segnali insufficienti)";
   string hr = "";
   if(g_pkHr[0] > 0.0)
      hr = IS((long)g_pkHr[0]) + " ore scelte in-sample: fuori campione " + Sg(g_pkHr[2]) + " pt su " + F0(g_pkHr[1]) + " (t " + F2(g_pkHr[3]) + ", " + VerdText(g_pkTest[1]) + ") contro " + Sg(g_pkHr[4]) + " pt di tutte le ore";
   else
      hr = g_pkP0v >= 0 ? "nessuna ora con netto positivo in-sample" : "non valutate";
   string fl = "";
   if(g_pkFl[0] >= 0.0)
      fl = "'" + PkClsLbl((int)g_pkFl[0]) + "' (in-sample " + Sg(g_pkFl[6]) + " pt su " + F0(g_pkFl[5]) + "): fuori campione " + Sg(g_pkFl[2]) + " pt su " + F0(g_pkFl[1]) + " (t " + F2(g_pkFl[3]) + ", " + VerdText(g_pkTest[2]) + ") contro " + Sg(g_pkFl[4]) + " pt senza filtro";
   else
      fl = g_pkP0v >= 0 ? "nessuna classe con netto positivo in-sample" : "non valutato";
   if(g_pkSl[0] > 0.0)
      cd += "Stop che lascia passare i segnali: il " + F0(g_pkSl[0]) + "% raggiunge " + ThrLbl(g_pkTp[g_pkGoodJ]) + " ATR e, fra questi, uno stop di " + F2(g_pkSl[1]) + " ATR (" + F0(g_pkSl[2]) + " pt) ne lascia passare il 75% e uno di " + F2(g_pkSl[3]) + " ATR (" + F0(g_pkSl[4]) + " pt) il 90%. ";
   g_pkCard = cd + "GRIGLIA STOP x TARGET: " + st + ". ORARI: " + hr + ". CLASSE FILTRO: " + fl + ". RISCHIO: " +
              (g_pkRk[0] > 0.0 ? ("proposto " + ThrLbl(g_pkRk[0]) + "% (crescita fuori campione " + Sg(g_pkRk[1], 1) + "%, drawdown " + F1(g_pkRk[2]) + "%)") : string("0%, nessun vantaggio verificato fuori campione da dimensionare")) + ".";
   //--- riga di sintesi
   const string v0 = (g_pkTest[0] >= 0) ? VerdCell(g_pkTest[0]) : Td("-");
   g_pkSumRow = "<tr><td>" + g_tfName[t] + "</td>" + Td(IS(n) + " su " + IS(g_pkNsig)) + Td("<b>" + F0(g_pkRef[0]) + "</b>") + Td(F2(g_pkRef[2])) + Td(F0(g_pkRef[4])) + Td(F1(g_pkRef[7])) + Td(F0(g_pkRef[5])) +
                Td(g_pkP0v >= 0 ? PkP0Lbl(medAtr) : string("-")) + Td(g_pkP0v >= 0 ? F1(g_pkP0[1]) : string("-"), ColSign(g_pkP0[1])) + Td(g_pkP0v >= 0 ? ("<b>" + F1(g_pkP0[4]) + "</b>") : string("-"), ColSign(g_pkP0[4])) +
                Td(g_pkP0v >= 0 ? F2(g_pkP0[5]) : string("-"), ColT(g_pkP0[5])) + v0 +
                Td(g_pkHr[0] > 0.0 ? (IS((long)g_pkHr[0]) + " ore: " + Sg(g_pkHr[2]) + " pt, t " + F2(g_pkHr[3])) : string("-")) +
                Td(g_pkFl[0] >= 0.0 ? (HtmlEsc(PkClsLbl((int)g_pkFl[0])) + ": " + Sg(g_pkFl[2]) + " pt, t " + F2(g_pkFl[3])) : string("-")) + Td(g_pkP0v >= 0 ? (F1(g_pkRk[0]) + "%") : string("-")) + "</tr>";
   //--- dettaglio
   g_pkDet = "<details><summary><b>" + g_tfName[t] + "</b> &mdash; " + IS(n) + " segnali misurati su " + IS(g_pkNsig) + (g_pkStride > 1 ? (" (uno ogni " + IS(g_pkStride) + ")") : "") + "</summary>";
   g_pkDet += "<h3>Picchi: quanto si muove il prezzo, quando e quanto va contro</h3>" + tPk;
   if(svHist != "") g_pkDet += "<h4>Distribuzione dei picchi (ritiro di riferimento)</h4>" + svHist;
   if(svRet != "") g_pkDet += "<h4>Percorso medio dopo il segnale per regime di volatilit&agrave; (nel verso del segnale, in ATR)</h4>" + svRet;
   if(svRng != "") g_pkDet += "<h4>Volatilit&agrave; lungo il percorso (ampiezza media di una barra M1, in ATR)</h4>" + svRng;
   g_pkDet += "<h3>Sequenze di segnali nello stesso verso</h3>" + tSq;
   g_pkDet += "<h3>Stop e target (griglia): scelta sul primo periodo, verifica sul resto</h3>";
   if(g_pkP0v >= 0)
      g_pkDet += "<div class='note'>Scelta in-sample (t semplice pi&ugrave; alto fra " + IS(g_pkNj * PK_NSL * ((g_pkMed > 0.0) ? 2 : 1)) + " celle; per puro caso il massimo atteso &egrave; circa " + F1(MathSqrt(2.0 * MathLog((double)(g_pkNj * PK_NSL * ((g_pkMed > 0.0) ? 2 : 1))))) + "): <b>" + PkP0Lbl(medAtr) + "</b>. "
                 "In-sample netto " + Sg(g_pkP0[1]) + " pt su " + F0(g_pkP0[0]) + " segnali (t " + F2(g_pkP0[2]) + "). <b>Fuori campione netto " + Sg(g_pkP0[4]) + " pt</b> su " + F0(g_pkP0[3]) + " segnali (t raggruppato per giorno " + F2(g_pkP0[5]) + "). "
                 "Fuori campione: " + F0(g_pkP0[6]) + "% chiuse a target (in media dopo " + F0(g_pkP0[9]) + " min), " + F0(g_pkP0[7]) + "% a stop, " + F0(g_pkP0[8]) + "% a fine finestra. Stop e target sono eseguiti al loro livello (nessuno slittamento); se nella stessa barra M1 toccano entrambi vale lo stop.</div>";
   g_pkDet += tGr;
   g_pkDet += "<h3>Orari, volume, sequenza, intensit&agrave;, regime, ADX: stop che serve e risultato</h3>" + tCl;
   if(tRk != "") g_pkDet += "<h3>Rischio per posizione, lotti e verifica fuori campione</h3>" + tRk;
   if(svRuns != "") g_pkDet += "<h3>Esempi di sequenze reali (" + g_tfName[t] + ", " + IS(InpPeakExamples) + " scelte a distanza regolare nel periodo)</h3><div class='note'>Linea = chiusure M1; triangoli = ingressi dei segnali della sequenza; cerchio = picco (ritiro di riferimento); linea blu = prezzo del primo ingresso, verde e rossa = target e stop del segnale buono.</div><div style='display:flex;flex-wrap:wrap'>" + svRuns + "</div>";
   g_pkDet += "</details>";
   g_dg += "PKTEST|" + g_tfName[t] + "|n|" + IS(n) + "|grid|" + IS(g_pkTest[0]) + "|hours|" + IS(g_pkTest[1]) + "|filter|" + IS(g_pkTest[2]) + "|risk|" + F1(g_pkRk[0]) + "|sigtot|" + IS(g_pkNsig) + "|runs|" + IS(g_pkNruns) + "\n";
  }

void RepPeaks()
  {
   g_cPkA = ""; g_cPkB = ""; g_cPkC = ""; g_cPkD = "";
   g_pkEvalTf = 0; g_pkPosTf = 0;
   if(!InpPeak) return;
   if(g_pkNtf < 1 || g_pkNk < 1 || g_pkNj < 1 || !g_atrOn)
     {
      W("<div class='note ko'><b>Picchi, stop e rischio non eseguiti</b>: nessun TF valido in InpPeakTFs o liste vuote.</div>");
      return;
     }
   W("<h2>Picchi, stop e rischio</h2>");
   W("<div class='note'>Per ogni segnale si percorrono le barre M1 dall'ingresso (open dopo la chiusura del segnale) fino al segnale opposto" + string(InpPeakCross ? "" : " della stessa serie") + ", alla durata massima (" + IS(InpPeakMaxMin) + " min o " + IS(InpPeakMaxCandles) + " candele del TF) o a un buco di dati. "
     "<b>Picco</b> = massimo spostamento nel verso del segnale prima che il prezzo ritiri dal massimo di un certo multiplo dell'ATR (" + MgDblList(g_pkK, g_pkNk) + " ATR): un picco per ogni ritiro; &egrave; calcolato a posteriori, misura l'ampiezza del movimento e <b>non</b> &egrave; un profitto ottenibile. "
     "Il tempo al picco e il percorso contro sono dalla barra M1 d'ingresso. I profitti ottenibili sono nella griglia stop x target (" + IS(PK_NSL) + " stop da 0.5 a 9 ATR, target " + MgDblList(g_pkTp, g_pkNj) + " ATR, ognuno in multipli dell'ATR del segnale e in punti fissi): "
     "la cella migliore &egrave; scelta sul primo periodo e misurata sul resto; costi inclusi (spread M1 d'ingresso e commissione). "
     "Ordine dentro la barra M1: il minimo prima del massimo. Orari e classi sono scelti sul primo periodo e verificati sul resto; con tanti raggruppamenti alcuni risultano buoni per puro caso in-sample, per questo conta solo la colonna fuori campione. "
     "ATR = ATR a " + IS(MathMax(2, InpMgmtAtrLen)) + " periodi del TF del segnale, sulla candela del segnale. Volume = tick volume M1 (il volume reale non c'&egrave; nei dati forex). "
     "Con pi&ugrave; di " + IS(InpPeakMaxSignals) + " segnali per TF se ne misura uno ogni tanti, a distanza regolare (InpPeakMaxSignals).</div>");
   //--- volume tick per ora
   {
    string vt = "<table><tr><th>Ora (server + offset)</th>";
    for(int h = 0; h < 24; h++) vt += "<th>" + string(h < 10 ? "0" : "") + IS(h) + "</th>";
    vt += "</tr><tr><td>Volume tick M1, indice (1 = media)</td>";
    string dgv = "";
    for(int h = 0; h < 24; h++)
      {
       vt += Td(F2(g_hrVol[h]), g_hrVol[h] >= 1.0 ? "#a3be8c" : "#7b8794");
       dgv += string(h > 0 ? "," : "") + F2(g_hrVol[h]);
      }
    W("<h3>Volume tick per ora del giorno</h3>" + vt + "</tr></table>");
    g_dg += "PKVOLH|" + dgv + "\n";
   }
   string rows = "", dets = "";
   for(int m = 0; m < g_pkNtf; m++)
     {
      const int t = g_pkTf[m];
      if(IsStopped()) return;
      if(g_tfCnt[t] < 1) continue;
      Comment("SignalLab MultiTF: picchi e stop ", g_tfName[t], " (", m + 1, "/", g_pkNtf, ")");
      PkAnalyze(t, g_curSet * g_nT + t);
      g_cdPk[g_curSet * g_nT + t] = g_pkCard;
      rows += g_pkSumRow;
      dets += g_pkDet;
      if(g_pkOk)
        {
         const string tn = g_tfName[t];
         if(g_pkP0v >= 0)
            g_cPkB += tn + " " + Sg(g_pkP0[4]) + " pt (t " + F2(g_pkP0[5]) + ", " + VerdText(g_pkTest[0]) + "; " + PkP0Lbl(g_pkMedAtr) + "; stop che lascia passare il 75% / 90% dei segnali che raggiungono " + ThrLbl(g_pkTp[g_pkGoodJ]) + " ATR: " +
                      F2(g_pkSl[1]) + " ATR (" + F0(g_pkSl[2]) + " pt) / " + F2(g_pkSl[3]) + " ATR (" + F0(g_pkSl[4]) + " pt)); ";
         g_cPkA += tn + " " + F0(g_pkRef[0]) + " pt (" + F2(g_pkRef[2]) + " ATR) in " + F0(g_pkRef[4]) + " min; ";
         if(g_pkRk[0] > 0.0) g_cPkD += tn + " " + ThrLbl(g_pkRk[0]) + "%; ";
         string oc = "";
         if(g_pkHr[0] > 0.0) oc += IS((long)g_pkHr[0]) + " ore scelte (fuori campione " + Sg(g_pkHr[2]) + " pt su " + F0(g_pkHr[1]) + ", t " + F2(g_pkHr[3]) + ", " + VerdText(g_pkTest[1]) + ")";
         if(g_pkFl[0] >= 0.0) oc += string(oc != "" ? " e " : "") + "miglior classe '" + PkClsLbl((int)g_pkFl[0]) + "' (fuori campione " + Sg(g_pkFl[2]) + " pt su " + F0(g_pkFl[1]) + ", t " + F2(g_pkFl[3]) + ", " + VerdText(g_pkTest[2]) + ")";
         if(oc != "") g_cPkC += tn + " " + oc + "; ";
        }
     }
   Comment("");
   W("<h3>Sintesi per time frame</h3>");
   W("<table><tr><th>TF</th><th>Segnali misurati</th><th>Picco mediano (pt)</th><th>(ATR)</th><th>Tempo al picco (min)</th><th>(candele)</th><th>Contro prima del picco (pt)</th><th>Gestione scelta in-sample</th><th>Netto in-sample (pt)</th><th>Netto fuori campione (pt)</th>"
     "<th>t fuori campione</th><th>Esito</th><th>Orari scelti: fuori campione</th><th>Miglior classe: fuori campione</th><th>Rischio proposto</th></tr>" + rows + "</table>");
   W(dets);
  }

//--- righe del riepilogo della serie (testi raccolti da RepPeaks)
void BuildPeaksConc(const int sIdx)
  {
   if(!InpPeak || g_cPkA == "") return;
   AddConc(sIdx, "Picchi dei segnali: quanto si muovono, quando e per quanto tempo",
           "Picco = massimo spostamento nel verso del segnale prima di un ritiro di " + ThrLbl(g_pkK[g_pkRefK]) + " ATR dal massimo (calcolato a posteriori: misura l'ampiezza del movimento, non un profitto). Picco mediano e tempo mediano al picco per TF: " + g_cPkA +
           "Le tabelle per ogni ritiro provato (" + MgDblList(g_pkK, g_pkNk) + " ATR), per posizione nella sequenza di segnali, i percorsi medi per regime di volatilita' e le sequenze reali disegnate sono nel report HTML (sezione Picchi, stop e rischio) e nel digest (PK, PKSEQ).");
   if(g_cPkB != "")
      AddConc(sIdx, "Stop e target dalla griglia (scelta in-sample, risultato fuori campione)",
              "Per ogni TF la cella stop x target con il t piu' alto sul primo periodo (stop da 0.5 a 9 ATR, target " + MgDblList(g_pkTp, g_pkNj) + " ATR, in multipli dell'ATR del segnale o in punti fissi) e il suo netto fuori campione per segnale, costi inclusi: " + g_cPkB +
              "Orari, volume, intensita', regime, ADX e posizione nella sequenza con lo stop che lascia passare il 75% e il 90% dei segnali che raggiungono il target sono nelle tabelle per classe del report.");
   {
    //--- ore con il maggior volume tick e risultato degli orari e delle classi
    int top[3];
    top[0] = -1; top[1] = -1; top[2] = -1;
    for(int z = 0; z < 3; z++)
      {
       double bv = 0.0;
       for(int h = 0; h < 24; h++)
         {
          if((z > 0 && h == top[0]) || (z > 1 && h == top[1])) continue;
          if(g_hrVol[h] > bv) { bv = g_hrVol[h]; top[z] = h; }
         }
      }
    string vt = "";
    for(int z = 0; z < 3; z++) if(top[z] >= 0) vt += string(vt != "" ? ", " : "") + string(top[z] < 10 ? "0" : "") + IS(top[z]) + ":00 (" + F2(g_hrVol[top[z]]) + ")";
    AddConc(sIdx, "Orari, volume e classi di segnali (scelta in-sample, verifica fuori campione)",
            "Ore con piu' volume tick M1 (indice rispetto alla media, ora server + offset): " + vt + ". Per ogni TF le ore con netto positivo in-sample (almeno " + IS(InpPeakMinN) + " segnali) sono misurate sul resto con la gestione scelta, e la miglior classe (posizione nella sequenza, intensita', volume recente, regime, ADX, percorso gia' fatto) allo stesso modo: " +
            string(g_cPkC != "" ? g_cPkC : "nessuna ora o classe con netto positivo in-sample, quindi niente da verificare. ") + "La tabella per ora e per classe con lo stop che lascia passare il 75% e il 90% dei segnali che raggiungono il target (in ATR e in punti) e' nel report.");
   }
   if(g_cPkD != "")
      AddConc(sIdx, "Rischio per posizione proposto (scala di " + ThrLbl(InpRiskStepPct) + " in " + ThrLbl(InpRiskStepPct) + ")",
              "Solo dove la gestione regge fuori campione (netto positivo, t >= 2), un quarto del Kelly in-sample arrotondato per difetto, massimo " + ThrLbl(InpRiskMaxPct) + "%: " + g_cPkD + "Lotti per saldo e patrimonio, crescita e drawdown fuori campione di ogni passo della scala sono nel report.");
   else
      AddConc(sIdx, "Rischio per posizione proposto",
              "0% su ogni TF: nessuna gestione della griglia (e nessuna selezione di orari) e' positiva con t >= 2 fuori campione, quindi non c'e' un vantaggio verificato da dimensionare; aumentare il rischio non ha giustificazione statistica. La scala di " + ThrLbl(InpRiskStepPct) + " in " + ThrLbl(InpRiskStepPct) +
              " con lotti, crescita e drawdown fuori campione e' comunque nel report, per vedere cosa succederebbe.");
  }

//--- una frase per la conclusione: esito dei test della sezione picchi
string PkFeasTxt()
  {
   if(!InpPeak || g_pkEvalTf < 1) return "";
   return " Picchi, stop e orari (griglia stop x target, orari e classi): " + IS(g_pkPosTf) + " test su " + IS(g_pkEvalTf) + " positivi con t >= 2 fuori campione" + string(g_pkPosTf == 0 ? ": nessun risultato supera il caso." : " (candidati da confermare).");
  }

//--- punti medi per segnale all'orizzonte di riferimento, per TF e per fascia oraria d'ingresso (tutto il periodo, senza divisione in-sample / fuori campione):
//--- una riga di sintesi con tutti i TF e, per la scheda di ogni TF, il lordo, il netto e le fasce con il netto migliore e peggiore
void BuildPoints(const int sIdx)
  {
   string all = "";
   const string hs = IS(g_hor[g_refH]);
   bool usedB[];
   ArrayResize(usedB, g_nB);
   for(int t = 0; t < g_nT; t++)
     {
      g_cdPts[sIdx * g_nT + t] = "";
      CellStat c;
      if(!GetCell(t, g_refH, c) || c.n < 1.0) continue;
      const string one = "lordo " + Sg(c.gross) + " pt, netto " + Sg(c.ret) + " pt" + string(g_money ? (" (" + MnyU(c.ret) + " a posizione con " + LotTxt() + " lotti)") : "") +
                         " su " + F0(c.n) + " segnali (t del netto " + F2(c.tCl) + ")";
      int nOk = 0;
      for(int b = 0; b < g_nB; b++) if(g_accBkt[(t * g_nB + b) * ACCN] >= (double)InpMinPerBucket) nOk++;
      string bestTx = "", worstTx = "";
      for(int side = 0; side < 2; side++)
        {
         ArrayInitialize(usedB, false);
         for(int z = 0; z < 3; z++)
           {
            int bb = -1;
            double bv = 0.0;
            for(int b = 0; b < g_nB; b++)
              {
               const int p = (t * g_nB + b) * ACCN;
               const double nn = g_accBkt[p];
               if(nn < (double)InpMinPerBucket || usedB[b]) continue;
               const double v = g_accBkt[p + 3] / nn;
               if(bb < 0 || (side == 0 ? v > bv : v < bv)) { bv = v; bb = b; }
              }
            if(bb < 0) break;
            usedB[bb] = true;
            const int pb = (t * g_nB + bb) * ACCN;
            const string it = BktLabel(bb) + " netto " + Sg(bv) + " pt (lordo " + Sg(bv + g_accBkt[pb + 5] / g_accBkt[pb]) + ", " + F0(g_accBkt[pb]) + " segnali)";
            if(side == 0) bestTx += string(z > 0 ? "; " : "") + it;
            else          worstTx += string(z > 0 ? "; " : "") + it;
           }
        }
      string tx = "orizzonte " + hs + " min: " + one + ".";
      if(bestTx != "")
         tx += " Fasce d'ingresso (server + offset) con il netto migliore: " + bestTx + "; con il peggiore: " + worstTx + ". Sono il massimo e il minimo di " + IS(nOk) +
               " fasce misurate sull'intero periodo, senza verifica fuori campione: una parte e' rumore (le celle ora x giorno scelte sul primo periodo e verificate sul resto sono in ORARI E GIORNI)";
      g_cdPts[sIdx * g_nT + t] = tx;
      all += g_tfName[t] + " lordo " + Sg(c.gross) + " netto " + Sg(c.ret) + " (" + F0(c.n) + " segnali); ";
     }
   if(all != "")
      AddConc(sIdx, "Punti medi per segnale per time frame", "Orizzonte di riferimento " + hs + " min (uscita a tempo, ingresso all'open dopo la chiusura del segnale, costi inclusi: spread M1 e commissione), intero periodo, in punti per segnale: " + all +
              "Il lordo e' cio' che la sola direzione del segnale porta prima dei costi, il netto cio' che resta. Il dettaglio per fascia oraria e' nella scheda di ogni time frame; le altre tenute (da 1 a 1440 min) sono nelle tabelle TF x tenuta del report HTML e nel digest (TFH).");
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
    string fzTxt = "";
    if(g_filtTxt != "")
      {
       int fAdx = 0, fReg = 0;
       for(int t = 0; t < g_nT; t++) { fAdx += g_tfRejAdx[t]; fReg += g_tfRejReg[t]; }
       string tolte = "";
       if(g_adxFilt) tolte += IS(fAdx) + " dall'ADX";
       if(g_regFilt) tolte += string(tolte != "" ? ", " : "") + IS(fReg) + " dal regime di volatilita'";
       fzTxt = " Filtri dell'EA attivi su tutti i segnali: " + g_filtTxt + " (barre con segnale tolte, somma dei TF e delle serie, in ordine ADX poi regime: " + tolte + ")." +
               string(g_adxFilt ? " L'ADX e' ricostruito dall'esempio ADX.mq5, quindi il conteggio puo' differire un poco da quello dell'EA." : "") +
               " La posizione nella raffica (Sequence Filter) e' calcolata prima dei filtri.";
      }
    AddConc(sIdx, "Dati", "Simbolo " + _Symbol + ", periodo " + TimeToString(g_tStart, TIME_DATE) + " - " + TimeToString(tEnd, TIME_DATE) +
            ", " + IS(g_nT) + " TF analizzati. Segnali misurati a " + hs + " min: " + F0(tot) + " in totale (somma dei TF: non sono indipendenti)" +
            (top != "" ? " (TF con piu' segnali: " + top + ")" : "") + ". Costo: " +
            (InpCostPoints > 0.0 ? ("fisso " + F1(InpCostPoints) + " pt") : ("spread M1 mediano " + F0(g_medSpr) + " pt")) +
            (InpExtraCostPts > 0.0 ? (" + extra " + F1(InpExtraCostPts) + " pt") : "") +
            (g_commPts > 0.0 ? (" + commissione " + F1(g_commPts) + " pt (" + F2(InpCommissionPerLotSide) + " " + g_ccy + " per lato e per lotto)") : "") +
            (g_commPts <= 0.0 ? ". ATTENZIONE: nessuna commissione inclusa (InpCommissionPerLotSide = 0): i risultati sono ottimisti su un conto Raw" : "") +
            (!g_money ? (". Valori in denaro non disponibili (" + g_pvInfo + ")") : "") +
            (g_money ? (". Posizione ipotetica " + LotTxt() + " lotti: 1 punto = " + DoubleToString(MnyV(1.0), 4) + " " + g_ccy + string(g_pvInfo != "" ? (" (" + g_pvInfo + ")") : "")) : "") +
            (g_pvWarn ? ". ATTENZIONE: il valore del punto e' una stima (vedi sopra), quindi lo e' anche la commissione in punti e il netto in denaro" : "") +
            ". Tutti i valori sono in punti (1 punto = " + DoubleToString(g_pt, _Digits) + ")." +
            fzTxt +
            (g_histWarn ? " ATTENZIONE: lo storico M1 e' piu' corto del periodo richiesto." : "") + SprTopText() +
            (g_skN > 0 ? (" ATTENZIONE: escluse le finestre d'ingresso " + InpSkipEntryWin + " (ora server + offset): i risultati non sono quelli dell'EA su quelle fasce.") : "") +
            (InpEntryLagMin > 0 ? (" ATTENZIONE: corsa con ingresso ritardato di " + IS(InpEntryLagMin) + " min dopo la chiusura del segnale (prova di stress): i risultati non sono quelli dell'EA.") : ""));
   }

   BuildPoints(sIdx);
   BuildPeaksConc(sIdx);

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
   g_agGpos[sIdx] = posS; g_agGneg[sIdx] = negS; g_agNsig[sIdx] = netSig; g_agNtf[sIdx] = K;
   g_agAns[sIdx] = g_cAns;
   double expA = 0.0;
   const bool aEdge = AEdge(expA);
   const int a1 = A1Count(g_rg);
   const int a1P = g_plc ? A1Count(g_rgP) : 0;
   g_agA1ok[sIdx] = a1;
   const double expA1 = MathMax(0.0228 * (double)K, (double)a1P);
   const bool a1Edge = (a1 >= 2 && (double)a1 > 2.0 * expA1);                     // una scelta A1 per TF: ne passa per caso circa il 2.3%, o quanto il placebo
   g_agAedge[sIdx] = (aEdge || a1Edge) ? 1 : 0;
   g_agAok[sIdx]   = (g_cAok && g_cAusable > 0) ? 1 : 0;
   bool ampKnown = false, ampUp = false, ampDown = false, ptsAbove = false;

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
         v1 = "In almeno un TF il segnale anticipa la direzione gia' prima dei costi: i TF vicini condividono gran parte dei segnali e non sono conferme indipendenti, serve una verifica su un periodo successivo e su altri simboli (il t cluster resta ottimista sulle tenute lunghe).";
      else if(posS == 0)
         v1 = "Il segnale e' contrario alla direzione del prezzo in almeno un TF: " +
              string(InpRankSide == RS_FOLLOW ? "seguirlo perde gia' prima dei costi; per vedere la lettura INVERTI rilancia con InpRankSide = SEGUI e INVERTI." : "guarda la lettura INVERTI nelle tabelle A.");
      else
         v1 = "Segni opposti in TF diversi: nessuna direzione coerente.";
      AddConc(sIdx, "Direzione prima dei costi", "Orizzonte " + hs + " min, " + IS(K) + " TF con almeno " + IS(minN) +
              " segnali. Rendimento lordo medio (prima dei costi) positivo in " + IS(posN) + " TF; significativamente positivo in " + IS(posS) +
              " e significativamente negativo in " + IS(negS) + " (soglia di Bonferroni: valore assoluto di t cluster >= " + F2(g_zB) + "). Migliore: " + g_tfName[bi] +
              " lordo " + Sg(cb.gross) + " pt (t " + F2(cb.tGross) + "); peggiore: " + g_tfName[wi] + " lordo " + Sg(cw.gross) + " pt (t " + F2(cw.tGross) + "). " + v1);
      if(netSig == 0)
         v2 = "Nessun TF resta significativamente positivo dopo i costi: come entrata autonoma, con uscita a tempo, il segnale non ha un vantaggio operabile. "
              "Con segnali senza informazione il netto atteso e' circa meno il costo, qualunque sia la tenuta.";
      else
         v2 = "TF con netto positivo significativo: " + sigList + ". Sono candidati, non conferme: guarda se reggono fuori campione nelle tabelle A e poi su un periodo successivo e su altri simboli (i TF vicini condividono gran parte dei segnali).";
      AddConc(sIdx, "Dopo i costi", "Costo medio pesato " + F1(wCost / wN) + " pt, lordo medio pesato " + Sg(wG / wN) + " pt, netto medio pesato " + Sg(wNet / wN) +
              " pt (pesi = segnali di ciascun TF). Netto positivo in " + IS(netPos) + " TF su " + IS(K) + ", positivo e significativo (t cluster >= " + F2(g_zB) +
              ") in " + IS(netSig) + ". Miglior netto: " + g_tfName[bni] + " " + Sg(cn.ret) + " pt (t cluster " + F2(cn.tCl) + "). " +
              (g_money ? ("Con " + LotTxt() + " lotti il netto medio di una posizione che segue il segnale e' " + MnyU(wNet / wN) + " (costo medio " + MnyU(wCost / wN) +
                         ", commissione inclusa nel costo extra). ") : "") +
              (wG < 0.0 ? ("Se si invertisse il segnale: lordo " + Sg(-wG / wN) + " pt, meno il costo medio " + F1(wCost / wN) + " pt = netto " + Sg(-wG / wN - wCost / wN) + " pt (media pesata). ") : "") + v2);
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
       sh += (sh == "" ? "" : "; ") + IS(g_hor[h]) + "m " + Sg(wg / wn, 1) + "/" + Sg(wr / wn, 1);
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
      if(GetCell(rt, g_refH, c) && c.n >= g_minN)
        {
         //--- punti raggiunti
         const int cell = rt * g_nH + g_refH;
         int key[];
         const int nk = KeyLevels(key);
         string sl = "";
         int above = 0, below = 0, volOnly = 0;
         for(int q = 0; q < nk; q++)
           {
            const int    l  = key[q];
            const double pf = 100.0 * SuffixCount(g_exFav, cell * (g_nL + 1), l) / c.n;
            const double pa = 100.0 * SuffixCount(g_exAdv, cell * (g_nL + 1), l) / c.n;
            const double pb = 100.0 * BaseExcMatched(rt, g_refH, l);
            sl += "+" + F0(g_lev[l]) + " pt: " + Pc(pf) + "% (avverso " + Pc(pa) + "%, base " + Pc(pb) + "%); ";
            if(pf > pb * 1.1 && pf >= 1.0)
              {
               if(pf > pa * 1.05) above++;       // supera la base e il movimento contrario
               else volOnly++;                   // supera la base ma anche il contrario: volatilita', non direzione
              }
            else if(pf < pb * 0.9 && pb >= 1.0) below++;
           }
         double l50 = 0.0, l25 = 0.0;
         for(int l = 0; l < g_nL; l++)
           {
            const double pf = 100.0 * SuffixCount(g_exFav, cell * (g_nL + 1), l) / c.n;
            if(pf >= 50.0) l50 = g_lev[l];
            if(pf >= 25.0) l25 = g_lev[l];
           }
         ptsAbove = (above * 2 > nk);
         string v3;
         if(above * 2 > nk)      v3 = "La probabilita' supera sia quella di un'entrata casuale nelle stesse ore sia quella del movimento contrario nella maggior parte dei livelli: il segnale tocca i punti piu' spesso del caso e nel verso giusto (da confermare fuori campione).";
         else if((above + volOnly) * 2 > nk) v3 = "La probabilita' supera quella di un'entrata casuale, ma il movimento contrario la supera nella stessa misura: e' volatilita' (le candele ampie sono seguite da altre candele ampie), non direzione.";
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
         double bestR = -1.0, worstR = 1.0e9, bestZ = 0.0, worstZ = 0.0, totDow = 0.0;
         int bd = -1, wd = -1, nDowTested = 0;
         for(int q = 0; q < 7; q++) totDow += g_accDow[(rt * 7 + ord[q]) * ACCN];
         for(int q = 0; q < 7; q++)
           {
            double nn, po, pb;
            DbAgg(rt, ord[q], ord[q], 0, g_nB - 1, lm, nn, po, pb);
            if(nn < InpMinPerBucket || nn < 0.02 * totDow || pb <= 0.0 || pb >= 100.0) continue;      // esclude i giorni quasi vuoti (sessione della domenica)
            nDowTested++;
            sd += DowName(ord[q]) + " " + Pc(po) + "% (base " + Pc(pb) + "%, " + F0(nn) + " segnali); ";
            const double ratio = po / pb;
            const double z = (po - pb) / MathSqrt(pb * (100.0 - pb) / nn);
            if(ratio > bestR)  { bestR = ratio;  bd = ord[q]; bestZ = z; }
            if(ratio < worstR) { worstR = ratio; wd = ord[q]; worstZ = z; }
           }
         if(bd >= 0)
            AddConc(sIdx, "Giorni della settimana", "TF " + g_tfName[rt] + ", probabilita' di toccare +" + F0(g_lev[lm]) + " pt entro " + hs +
                    " min per giorno d'ingresso (server + offset): " + sd + "Giorno migliore rispetto alla base: " + DowName(bd) + " x" + F2(bestR) +
                    " (z naive " + F2(bestZ) + "); peggiore: " + DowName(wd) + " x" + F2(worstR) + " (z naive " + F2(worstZ) + "). "
                    "Il z e' calcolato come se i segnali fossero indipendenti, ma segnali vicini condividono lo stesso percorso di prezzo: e' gonfiato e non e' una prova. Con " + IS(nDowTested) + " giorni testati una differenza conta solo se si ripete su un periodo successivo. "
                    "Usala solo se regge su un periodo successivo e su altri simboli (i TF vicini condividono gran parte dei segnali). Le tabelle per ogni TF sono nel dettaglio.");

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
               c1 += (q > 0 ? "; " : "") + BktLabel(top1[q]) + " x" + F2(pb > 0.0 ? po / pb : 0.0) + " (" + Pc(po) + "% contro " + Pc(pb) + "%, " + F0(nn) + " segnali)";
              }
            double maxR = 0.0;
            for(int q = 0; q < n0; q++)
              {
               double nn0, po0, pb0;
               DbAgg(rt, 0, 6, top0[q], top0[q], lm, nn0, po0, pb0);
               if(pb0 > 0.0 && po0 / pb0 > maxR) maxR = po0 / pb0;
              }
            const string vh = (maxR <= 1.1)
               ? "Le fasce con la probabilita' assoluta piu' alta sono di norma le ore piu' volatili: la base le tocca altrettanto spesso, quindi non sono ore in cui il segnale funziona meglio. "
               : "Alcune delle fasce con la probabilita' piu' alta superano la base di oltre il 10%: controlla nella tabella dei livelli se anche il movimento contrario la supera (candele ampie, volatilita' che si raggruppa) prima di leggerlo come merito del segnale. ";
            AddConc(sIdx, "Orari che raggiungono piu' spesso i punti", "TF " + g_tfName[rt] + ", +" + F0(g_lev[lm]) + " pt entro " + hs + " min, orario d'ingresso (server + offset). "
                    "Fasce con la probabilita' piu' alta: " + c0 + ". Fasce con il maggior vantaggio sulla base (ordinate per z naive, che penalizza i campioni piccoli): " + (n1 > 0 ? c1 : "nessuna con campione sufficiente") + ". " + vh +
                    "Il vantaggio sulla base e' l'unico indizio, ma con " + IS(g_nB) + " fasce testate qualcuna supera la base per caso: serve una verifica su un periodo successivo e su altri simboli (i TF vicini condividono gran parte dei segnali).");
           }

         //--- raffica e verso
         {
          string sb = "";
          for(int q = 0; q < 4; q++)
            {
             double nq = 0.0, sq = 0.0;
             for(int q2 = q; q2 < ((q == 3) ? BCAP : q + 1); q2++)      // la quarta riga raccoglie 4a e oltre
               {
                const int pq = (rt * BCAP + q2) * ACCN;
                nq += g_accBur[pq];
                sq += g_accBur[pq + 3];
               }
             if(nq < 1.0) continue;
             sb += "posizione " + IS(q + 1) + string(q == 3 ? " e oltre" : "") + " " + Sg(sq / nq) + " pt (" + F0(nq) + "); ";
            }
          if(sb != "")
             AddConc(sIdx, "Raffica", "TF " + g_tfName[rt] + ", netto medio per posizione nella raffica (posizione 1 = primo segnale dopo uno opposto): " + sb +
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
            NxStat ar;
            if(sn != "" && NxGet(sIdx, rt, 0, g_nxRef, ar))
              {
               //--- range contro base: si prende la distanza (fra quelle misurate, con campione sufficiente) dove lo scarto dalla base e' maggiore;
               //--- due basi: una barra qualunque nelle stesse ore (rr) e una barra con la stessa intensita' della candela del segnale (rI)
               double rr = 1.0, rI = 1.0;
               int    rrM = g_nxM[g_nxRef], rIM = g_nxM[g_nxRef], rrQ = g_nxRef;
               bool   hasI = false;
               for(int q = 0; q < g_nM; q++)
                 {
                  NxStat aq, bq;
                  if(!NxGet(sIdx, rt, 0, q, aq) || aq.n < g_minN) continue;
                  if(NxBase(sIdx, rt, 0, q, bq) && bq.rng > 0.0)
                    {
                     const double rq = aq.rng / bq.rng;
                     if(!ampKnown || MathAbs(rq - 1.0) > MathAbs(rr - 1.0)) { rr = rq; rrM = g_nxM[q]; rrQ = q; ampKnown = true; }
                    }
                  const double riq = NxRatioInt(sIdx, rt, q);
                  if(riq > 0.0 && (!hasI || MathAbs(riq - 1.0) > MathAbs(rI - 1.0))) { rI = riq; rIM = g_nxM[q]; hasI = true; }
                 }
               const double riAtRr = hasI ? NxRatioInt(sIdx, rt, rrQ) : 0.0;           // rapporto a pari intensita' alla STESSA distanza di rr
               ampUp   = hasI ? (rI >= 1.1) : (ampKnown && rr >= 1.1);
               ampDown = hasI ? (rI <= 0.9) : (ampKnown && rr <= 0.9);
               string v4;
               if(!ampKnown)
                  v4 = "";
               else if(hasI && rI >= 1.1)
                  v4 = "Dopo " + IS(rIM) + " cand. il range supera di " + F0(100.0 * (rI - 1.0)) + "% quello di una barra con la stessa intensita' (TR/ATR) e le stesse ore: il segnale porta qualcosa oltre la sola ampiezza della candela. Puo' servire a dimensionare target e stop, non a scegliere il verso. ";
               else if(hasI && rI <= 0.9)
                  v4 = "Dopo " + IS(rIM) + " cand. il range e' inferiore di " + F0(100.0 * (1.0 - rI)) + "% a quello di una barra con la stessa intensita' (TR/ATR) e le stesse ore. ";
               else if(rr >= 1.1)
                  v4 = "Dopo " + IS(rrM) + " cand. il range supera di " + F0(100.0 * (rr - 1.0)) + "% quello di una barra qualunque nelle stesse ore" +
                       (hasI ? (", ma a pari intensita' della candela (TR/ATR) e alla stessa distanza lo scarto e' x" + F2(riAtRr) + ": il segnale dice solo che la candela era ampia, cosa che si vede senza segnale e dopo la quale la volatilita' si raggruppa. ")
                             : ": il segnale arriva quando il mercato si sta gia' muovendo (la volatilita' si raggruppa). ");
               else if(rr <= 0.9)
                  v4 = "Dopo " + IS(rrM) + " cand. il range e' inferiore di " + F0(100.0 * (1.0 - rr)) + "% a quello di una barra qualunque nelle stesse ore. ";
               else
                  v4 = "Il range dopo il segnale e' in linea con quello di una barra qualunque nelle stesse ore a tutte le distanze misurate (scarto massimo " + F0(100.0 * MathAbs(rr - 1.0)) + "% dopo " + IS(rrM) + " cand.): il segnale non anticipa ne' una volatilita' maggiore ne' minore. ";
               string v5;
               if(MathAbs(ar.tMv) < 3.0)        // t naive: la sovrapposizione dei segnali lo gonfia, soglia piu' alta di 2
                  v5 = ampUp   ? "La direzione di chiusura non e' distinguibile dal caso: l'informazione e' sull'ampiezza, non sul verso."
                     : (ampDown ? "La direzione di chiusura non e' distinguibile dal caso e il range e' inferiore alla base: nessuna informazione utile sul verso."
                                : "La direzione di chiusura non e' distinguibile dal caso e l'ampiezza e' quella di una barra qualunque: il segnale non porta informazione ne' sul verso ne' sull'ampiezza.");
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
                  AddConc(sIdx, "Candele successive per intensita'", "TF " + g_tfName[rt] + ", dopo " + IS(g_nxM[g_nxRef]) + " cand., per intensita' della candela del segnale (TR/ATR): " + si +
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
                  AddConc(sIdx, "Candele successive per orario", "TF " + g_tfName[rt] + ", range medio dopo " + IS(g_nxM[g_nxRef]) + " cand., per orario d'ingresso (server + offset). "
                          "Fasce con il range piu' alto: " + hiTxt + ". Fasce piu' quiete: " + (loTxt != "" ? loTxt : "-") + ". "
                          "Il range segue la volatilita' oraria del mercato, con o senza segnale: la tabella per orario e TF mostra anche il confronto con la base di ogni fascia.");
              }
           }
        }
      else
         AddConc(sIdx, "Punti raggiunti", "Il TF con piu' segnali (" + g_tfName[rt] + ") ha meno di " + IS(minN) + " segnali misurati a " + hs +
                 " min: le sintesi per punti raggiunti, giorni, orari e candele successive non sono calcolate perche' non affidabili.");
     }

   //--- tabella A (scelta in-sample, verifica fuori campione)
   if(!g_cAok)
      AddConc(sIdx, "Tabella A (scelta in-sample)", "Non calcolabile: nessuna combinazione con almeno " + IS(minN) + " posizioni in-sample.");
   else if(g_cAusable == 0)
      AddConc(sIdx, "Tabella A (scelta in-sample)", "Valutate " + IS(g_cAm) + " combinazioni sul primo periodo (miglior t in-sample " + F2(g_cAbestT) + " contro un massimo atteso per caso di circa " + F2(g_cAchance) +
              "), ma nessuna delle prime ha un campione fuori campione sufficiente: la verifica non e' possibile e la tabella A non e' valutabile. Allarga il periodo o riduci InpRankMinN.");
   else
     {
      const double expAn = 0.0228 * (double)g_cAusable;
      string ta = "Valutate " + IS(g_cAm) + " combinazioni TF x fascia x tenuta x target x verso sul primo periodo. Miglior t in-sample " + F2(g_cAbestT) +
                  " contro un massimo atteso per puro caso di circa " + F2(g_cAchance) + ". Fra le prime " + IS(g_cApn) + " in-sample, " + IS(g_cApos) + " su " + IS(g_cAusable) +
                  " restano positive fuori campione, " + IS(g_cAstrong) + " con t OOS >= 2 e " + IS(g_cAstrongN) + " con t OOS >= 2 e abilita' della direzione significativa; " +
                  "per puro caso, con combinazioni indipendenti, se ne attendono circa " + F1(expAn) + " (probabilita' di un t >= 2 positivo circa il 2.3%). ";
      if(g_cPok)
         ta += "Controllo placebo (direzione casuale con la stessa quota di acquisti e vendite, stessi istanti e stesse regole; una sola estrazione, molto variabile): miglior t in-sample " + F2(g_cPbest) +
               ", t OOS >= 2 fra le prime: " + IS(g_cPstrong) + " (con abilita' " + IS(g_cPstrongN) + ") contro " + IS(g_cAstrong) + " (con abilita' " + IS(g_cAstrongN) + ") del segnale reale; TF con A1 positiva fuori campione: " +
               IS(a1P) + " contro " + IS(a1) + ". ";
      if(aEdge)
         ta += "Il conteggio con abilita' significativa del segnale reale supera nettamente quello atteso dal caso" + string(g_cPok ? " e dal placebo" : "") + ": la direzione del segnale sembra portare informazione oltre il valore dell'istante e la deriva" +
               string(g_cAsurv != "" ? ("; la prima: " + g_cAsurv) : "") + ". Sono candidate da confermare su dati mai visti (l'OOS e' stato usato per sceglierle), non risultati. ";
      else if(g_cAstrong >= 3 && 2 * g_cAstrongN < g_cAstrong && 2 * g_cAone > g_cAstrong)
         ta += "Molte combinazioni sembrano reggere fuori campione, ma per la maggior parte (" + IS(g_cAone) + " su " + IS(g_cAstrong) + ") sono fasce in cui il segnale va quasi sempre nello stesso verso: li' l'abilita' della direzione "
               "non e' misurabile e il guadagno puo' essere deriva oppure direzione. Servono un altro simbolo, un altro periodo o la prova con InpEntryLagMin = 5. ";
      else if(g_cAstrong >= 3 && 2 * g_cAstrongN < g_cAstrong)
         ta += "Molte combinazioni (" + IS(g_cAstrong) + ") sembrano reggere fuori campione, ma solo " + IS(g_cAstrongN) + " hanno abilita' della direzione significativa (circa " + F1(expAn) + " se ne attendono per caso): per le altre il guadagno e' dell'istante (chi sceglie il verso a caso negli stessi istanti guadagna lo stesso, valore M) "
               "o della deriva sfruttata da una quota sbilanciata di acquisti o vendite, non della direzione del segnale. Un valore M positivo in una fascia e' tipicamente un artefatto dei dati (rollover, spread, code di prezzo). "
               "Prova di stress: ripeti con InpEntryLagMin = 5 oppure escludi la fascia con InpSkipEntryWin. ";
      else
         ta += "Il conteggio con abilita' significativa del segnale reale non si distingue da quello atteso dal caso" + string(g_cPok ? " e dal placebo" : "") + ": la tabella A non prova che la direzione del segnale porti informazione" +
               string(g_cAns > 0 && g_cAsurv != "" ? ("; fra quelle che passano il filtro (" + IS(g_cAns) + ") la prima e': " + g_cAsurv) : "") + ". ";
      ta += "Le combinazioni vicine (TF contigui, fasce e target adiacenti) sono quasi duplicati: il numero di sopravvissute non conta conferme indipendenti.";
      AddConc(sIdx, "Tabella A (scelta in-sample)", ta);
     }

   //--- tabella B (con rumore)
   if(!g_cBok)
      AddConc(sIdx, "Tabella B (con rumore)", "Non calcolabile: nessuna combinazione con almeno " + IS(minN) + " posizioni.");
   else
     {
      const double chB = (g_cBm > 1) ? MathSqrt(2.0 * MathLog((double)g_cBm)) : 0.0;
      AddConc(sIdx, "Tabella B (con rumore)", "Ordinata per " + NoiseSortName() + " sull'intero storico, senza protezione. La prima riga (" + g_cBdesc + ") promette " + F0(g_cBtotal) +
              " pt su " + F0(g_cBn) + " posizioni (netto medio " + F1(g_cBmean) + ", t " + F2(g_cBt) + "); il t massimo atteso per puro caso su " + IS(g_cBm) + " tentativi e' circa " + F2(chB) + ". " +
              (g_cBsumAll > 0.0 ? ("Nelle prime righe la parte piu' recente del periodo contiene il " + F1(g_cBshareN) + "% delle posizioni e il " + F1(g_cBshareLate) + "% del profitto. ")
                                : "Le prime righe non hanno profitto totale positivo: non c'e' profitto da ripartire fra le due parti. ") +
              "Fra le prime " + IS(g_cBpn) + " con campione sufficiente, " + IS(g_cBboth) + " su " + IS(g_cBusable) + " sono positive in entrambe le parti del periodo e " + IS(g_cBincoh) +
              " cambiano segno. La distanza fra il profitto promesso qui e quello della tabella A e' la misura del rumore di selezione.");
     }

   if(g_cMgmt != "") AddConc(sIdx, "Gestione simulata", g_cMgmt);
   if(g_cMgmt3 != "") AddConc(sIdx, "Gestione simulata per orario", g_cMgmt3);
   if(g_cMgmt4 != "") AddConc(sIdx, "Gestione simulata e ritardo d'ingresso", g_cMgmt4);
   if(g_cMgmt5 != "") AddConc(sIdx, "Gestione simulata: selezione di orari e giorni", g_cMgmt5);
   if(g_cFilt != "") AddConc(sIdx, "Scansione automatica dei filtri (ADX, regime di volatilita')", g_cFilt);
   if(g_cStress != "") AddConc(sIdx, "Prove di stress", g_cStress);

   //--- fattibilita' di un EA che apre nel verso del segnale (lotto ipotetico, costi inclusi)
   if(K >= 1 && wN > 0.0)
     {
      const bool oosOk = (aEdge || a1Edge);
      const double years = MathMax(0.1, (double)((long)g_m1Time[g_n1 - 1] - (long)g_tStart) / 86400.0 / 365.25);
      const double oosYears = MathMax(0.05, (double)(g_nDays - g_splitDay) / 365.25);
      string fz = "";
      CellStat cr;
      const bool haveRef = (rt >= 0 && GetCell(rt, g_refH, cr) && cr.n >= g_minN);
      if(netSig == 0 && !oosOk)
        {
         const double gapPts = (wCost - wG) / wN;
         fz = "Statisticamente non fattibile come EA che apre nel verso del segnale: nessun TF ha netto positivo e significativo dopo la correzione per test multipli e la tabella A non mostra evidenza oltre il caso. "
              "Lordo medio pesato " + Sg(wG / wN) + " pt contro un costo medio (spread e commissione) di " + F1(wCost / wN) + " pt";
         if(gapPts > 0.0)
           {
            fz += ": mancano " + F1(gapPts) + " pt a posizione per pareggiare";
            if(g_money) fz += " (" + MnyU(gapPts) + " con " + LotTxt() + " lotti)";
           }
         else
            fz += ": il netto medio pesato e' " + Sg(wNet / wN) + " pt ma nessun TF e' significativo, quindi non e' distinguibile dal caso";
         fz += ". ";
         if(haveRef && g_money)
            fz += "Esempio sul TF " + g_tfName[rt] + " con uscita dopo " + hs + " min: " + F0(cr.n) + " segnali in " + F1(years) + " anni (circa " + F0(cr.n / years) + " all'anno), netto medio " + MnyU(cr.ret) +
                  " a posizione, circa " + MnyTU(cr.ret * cr.n / years) + " all'anno se si aprisse ogni segnale (le posizioni si sovrappongono: e' un ordine di grandezza, non il risultato di un conto). ";
         if(gapPts > 0.0)
            fz += "Un EA con questa entrata non puo' guadagnare dalla sola direzione: potrebbe farlo solo con una gestione (uscite, trailing, target) che crea un profilo diverso" +
                  string(g_mgOn ? ", ed e' quello che misura la gestione simulata (paragrafi dedicati)." : ", che questo studio non misura (gestione simulata spenta o non eseguita).") + MgFeasTxt(true);
         else
            fz += "Un netto positivo ma non significativo non basta: serve una conferma su dati mai visti e su altri simboli prima di scrivere un EA." + MgFeasTxt(true);
        }
      else
        {
         fz = "Da verificare, non ancora fattibile: ";
         if(netSig > 0) fz += "netto positivo e significativo in " + sigList + "; ";
         if(aEdge)      fz += "la tabella A ha " + IS(g_cAstrongN) + " combinazioni con abilita' della direzione significativa fuori campione contro circa " + F1(expA) + " attese; ";
         if(a1Edge)     fz += "in " + IS(a1) + " TF la miglior combinazione A1 resta positiva fuori campione; ";
         if(g_money && g_cAsurvN > 0.0)
            fz += "la prima candidata vale " + MnyU(g_cAsurvMean) + " a posizione con " + LotTxt() + " lotti, " + F0(g_cAsurvN) + " posizioni fuori campione in " + F1(oosYears) + " anni, cioe' circa " +
                  MnyTU(g_cAsurvMean * g_cAsurvN / oosYears) + " all'anno al lordo di slippage e swap; ";
         fz += "prima di scrivere un EA servono tutte queste conferme: netto OOS positivo con spread e commissione reali; risultato che regge con InpEntryLagMin = 5 e con spread doppio nelle ore di news; "
               "non concentrato in pochi giorni di eventi (tabella dei giorni piu' lunghi); ripetuto su un periodo successivo e su un altro simbolo." + MgFeasTxt(false);
        }
      AddConc(sIdx, "Fattibilita' EA", fz);
     }

   //--- conclusione
   {
    string c;
    const bool oosEdge = (aEdge || a1Edge);
    if(K < 1)
       c = "Campione insufficiente: nessuna conclusione.";
    else if(netSig == 0 && !oosEdge)
      {
       c = "Nessuna evidenza di vantaggio operabile al netto dei costi in questa serie con l'entrata nel verso del segnale e l'uscita a tempo (tabelle A e B). ";
       if(posS > 0)
          c += "Il segnale ha contenuto direzionale lordo in " + IS(posS) + " TF, ma i costi lo assorbono. ";
       else if(negS > 0)
          c += "Il segnale e' significativamente contrario alla direzione del prezzo in " + IS(negS) + " TF: " +
               string(InpRankSide == RS_FOLLOW ? "seguirlo perde gia' prima dei costi; per la lettura INVERTI rilancia con InpRankSide = SEGUI e INVERTI. "
                                               : "la lettura INVERTI va verificata nelle tabelle A (il netto dell'inverso e' meno il lordo, meno il costo). ");
       else
          c += "Il segnale non anticipa la direzione del prezzo oltre il caso. ";
       if(g_cAok && g_cAstrong >= 3 && !aEdge && 2 * g_cAstrongN < g_cAstrong && 2 * g_cAone > g_cAstrong)
          c += "Nella tabella A " + IS(g_cAstrong) + " combinazioni sembrano reggere fuori campione ma per la maggior parte (" + IS(g_cAone) + ") il segnale va quasi sempre nello stesso verso: l'abilita' della direzione non e' misurabile "
               "li' e il guadagno puo' essere deriva oppure direzione; servono un altro simbolo o periodo, o la prova con InpEntryLagMin = 5. ";
       else if(g_cAok && g_cAstrong >= 3 && !aEdge && 2 * g_cAstrongN < g_cAstrong)
          c += "Nella tabella A " + IS(g_cAstrong) + " combinazioni sembrano reggere fuori campione ma solo " + IS(g_cAstrongN) + " hanno abilita' della direzione: il guadagno e' dell'istante (valore M, tipicamente rollover, spread o code di prezzo) "
               "o della deriva per una quota sbilanciata di acquisti e vendite, non e' prova che il segnale abbia informazione direzionale; verifica con InpEntryLagMin = 5 o escludendo la fascia con InpSkipEntryWin. ";
       if(ptsAbove)
          c += "I punti toccati nel verso del segnale superano la base e il movimento contrario (vedi 'Punti raggiunti'): da confermare fuori campione. ";
       else
          c += "I punti toccati dopo il segnale descrivono la volatilita' del momento, non un vantaggio direzionale. ";
       if(ampUp)
          c += "Il range delle candele successive supera quello di una barra con la stessa intensita' e le stesse ore (vedi 'Candele successive'): il segnale puo' servire come indicazione di ampiezza, non come trigger di direzione. ";
       else if(ampDown)
          c += "Il range delle candele successive e' inferiore a quello di una barra con la stessa intensita' e le stesse ore (vedi 'Candele successive'): nessun uso operativo dimostrato. ";
       else if(ampKnown)
          c += "A pari intensita' della candela e stesse ore l'ampiezza delle candele successive non si discosta da quella di una barra qualunque: sapere che la candela era ampia basta, il segnale non aggiunge nulla e non c'e' un uso operativo dimostrato. ";
       if(g_mgOn && g_mgEvalTf > 0)
          c += string((g_mgPosTf > 0 || g_mgSelPosTf > 0) ?
                ("La gestione simulata (" + MgComps() + ") mostra pero' dei candidati: TF con netto fuori campione positivo e t >= 2 in " + IS(g_mgPosTf) + " su " + IS(g_mgEvalTf) + " valutabili" + string(InpMgmtSelect && g_mgSelEvalTf > 0 ? (", con la selezione di orari e giorni positiva e significativa in " + IS(g_mgSelPosTf) + " su " + IS(g_mgSelEvalTf)) : "") + " (vedi i paragrafi 'Gestione simulata'), da confermare. ") :
                ("Anche la gestione simulata (" + MgComps() + ") non mostra TF positivi e significativi fuori campione. "));
       c += "Prima di qualunque uso operativo: ripeti lo studio su altri simboli e su un periodo successivo.";
      }
    else
      {
       c = "Ci sono indizi da verificare: ";
       if(netSig > 0) c += "netto positivo e significativo in " + sigList + "; ";
       if(negS > 0 && wN > 0.0) c += "il lordo e' significativamente contrario al segnale in " + IS(negS) + " TF (media pesata di tutti i TF " + Sg(wG / wN) + " pt contro un costo medio di " + F1(wCost / wN) + " pt); ";
       if(aEdge)      c += IS(g_cAstrongN) + " combinazioni della tabella A hanno abilita' della direzione significativa fuori campione, contro circa " + F1(expA) + " attese " + string(g_cPok ? "tra caso e placebo" : "per caso") + "; ";
       if(a1Edge)     c += "in " + IS(a1) + " TF la miglior combinazione A1 resta positiva fuori campione con t >= 2; ";
       c += "non sono conferme. Servono un test su dati mai visti (forward) e su altri simboli, e la verifica che l'esecuzione reale (spread, slippage, commissioni) non cancelli il margine.";
      }
    AddConc(sIdx, "Conclusione", c + PkFeasTxt());
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

   //--- solo i TF con campione sufficiente in entrambe le serie, con gli stessi TF e i pesi di ciascuna serie
   int both = 0, better = 0, bdT = -1;
   double bestDiff = -1.0e18, w0 = 0.0, w1 = 0.0, n0s = 0.0, n1s = 0.0, g0s = 0.0, g1s = 0.0;
   for(int t = 0; t < g_nT; t++)
     {
      if(g_cmpN[t] < g_minN || g_cmpN[g_nT + t] < g_minN) continue;
      both++;
      const double diff = g_cmpRet[g_nT + t] - g_cmpRet[t];
      if(diff > 0.0) better++;
      if(diff > bestDiff) { bestDiff = diff; bdT = t; }
      w0 += g_cmpN[t];          n0s += g_cmpN[t] * g_cmpRet[t];                 g0s += g_cmpN[t] * g_cmpGross[t];
      w1 += g_cmpN[g_nT + t];   n1s += g_cmpN[g_nT + t] * g_cmpRet[g_nT + t];   g1s += g_cmpN[g_nT + t] * g_cmpGross[g_nT + t];
     }
   string tx = "All'orizzonte di " + IS(g_hor[g_refH]) + " min. ";
   if(both > 0)
      tx += "Sui " + IS(both) + " TF con campione sufficiente in entrambe le serie (stessi TF, pesi = segnali di ciascuna serie): netto medio " + a0 + " " + Sg(n0s / w0) + " pt, " +
            a1 + " " + Sg(n1s / w1) + " pt; lordo medio " + a0 + " " + Sg(g0s / w0) + " pt, " + a1 + " " + Sg(g1s / w1) + " pt. " + a1 + " ha netto migliore in " + IS(better) +
            " di questi TF; la differenza maggiore e' su " + g_tfName[bdT] + " (" + Sg(bestDiff) + " pt). ";
   else
      tx += "Nessun TF ha campione sufficiente in entrambe le serie: il netto non e' confrontabile. ";
   tx += "TF con netto positivo significativo (ciascuna serie sui propri TF): " + a0 + " " + IS(g_agNsig[0]) + ", " + a1 + " " + IS(g_agNsig[1]) +
         ". TF con lordo significativo positivo: " + a0 + " " + IS(g_agGpos[0]) + ", " + a1 + " " + IS(g_agGpos[1]) +
         "; negativo: " + a0 + " " + IS(g_agGneg[0]) + ", " + a1 + " " + IS(g_agGneg[1]) + ".";
   AddConc(-1, "Netto a confronto", tx);
   AddConc(-1, "Tabelle A a confronto", "Combinazioni della tabella A scelte in-sample con t >= 2 che restano positive fuori campione con t >= 2 e abilita' della direzione significativa: " + a0 + " " + (g_agAok[0] > 0 ? IS(g_agAns[0]) : string("non valutabile")) + ", " +
           a1 + " " + (g_agAok[1] > 0 ? IS(g_agAns[1]) : string("non valutabile")) +
           " (una piccola quota e' attesa per puro caso, circa il 2.3% di quelle valutate). TF in cui la miglior combinazione A1 resta positiva fuori campione con t >= 2: " +
           a0 + " " + IS(g_agA1ok[0]) + ", " + a1 + " " + IS(g_agA1ok[1]) + ". Evidenza oltre il caso" + string(g_plc ? " e oltre il placebo" : "") + " nelle tabelle A (conteggio con abilita'): " + a0 + " " +
           (g_agAok[0] > 0 ? string(g_agAedge[0] > 0 ? "si" : "no") : string("non valutabile")) + ", " + a1 + " " + (g_agAok[1] > 0 ? string(g_agAedge[1] > 0 ? "si" : "no") : string("non valutabile")) + ".");
   string c;
   const bool enough = (g_agNtf[0] >= 1 && g_agNtf[1] >= 1);
   if(g_agNtf[1] < 1)
      c = "Campione insufficiente: nessun TF ha almeno " + IS((long)g_minN) + " segnali " + a1 + " misurati, gli aggiunti non sono valutabili. ";
   else if(g_agNtf[0] < 1)
      c = "Campione insufficiente nella serie " + a0 + ": il confronto non e' possibile. ";
   else if(g_agNsig[1] == 0 && g_agAedge[1] == 0)
      c = "I segnali che l'Expansion aggiunge non mostrano un vantaggio netto dimostrabile" + string(g_agAok[1] > 0 ? "" : " (tabella A non valutabile: campione insufficiente)") +
          ": allargano il numero di operazioni (e dei costi) senza una prova che valgano il costo. ";
   else
      c = "I segnali aggiunti mostrano qualche indizio di vantaggio: va confermato fuori campione prima di aggiungerli alla strategia. ";
   if(enough && both > 0)
      c += (n1s / w1 > n0s / w0) ? ("Sui TF in comune il netto medio degli aggiunti e' migliore di quello del Delta di " + F1(n1s / w1 - n0s / w0) + " pt, ma conta la significativita', non la differenza puntuale.")
                                 : ("Sui TF in comune il netto medio degli aggiunti non e' migliore di quello del Delta (differenza " + Sg(n1s / w1 - n0s / w0) + " pt).");
   AddConc(-1, "Conclusione del confronto", c);
  }

//+------------------------------------------------------------------+
//| SCHEDE PER TIME FRAME                                             |
//| Una riga del riepilogo per ogni serie e TF con tutti i test       |
//| eseguiti (gestione, ritardo, orari e giorni, filtri, scansione     |
//| dei parametri) e il numero di test positivi e significativi fuori  |
//| campione. In testa una riga con l'elenco dei test eseguiti e di    |
//| quelli non eseguiti. Solo ASCII e nessun '|'.                      |
//+------------------------------------------------------------------+
//--- come AddConc ma in testa all'elenco
void AddConcFront(const int s, const string topic, const string text)
  {
   AddConc(s, topic, text);
   const int k = ArraySize(g_cSet) - 1;
   const int s0 = g_cSet[k];
   const string t0 = g_cTopic[k], x0 = g_cText[k];
   for(int i = k; i > 0; i--)
     {
      g_cSet[i] = g_cSet[i - 1];
      g_cTopic[i] = g_cTopic[i - 1];
      g_cText[i] = g_cText[i - 1];
     }
   g_cSet[0] = s0;
   g_cTopic[0] = t0;
   g_cText[0] = x0;
  }

void BuildCards()
  {
   //--- elenco dei test eseguiti
   string run = "", skip = "";
   run += "Costi in ogni risultato: " + string(InpCostPoints > 0.0 ? ("spread fisso " + F1(InpCostPoints) + " pt") : "spread M1 reale della barra d'ingresso") +
          string(InpExtraCostPts > 0.0 ? (" + extra " + F1(InpExtraCostPts) + " pt") : "") + " + commissione " + F2(InpCommissionPerLotSide) + " " + g_ccy + " per lato e per lotto" +
          string(g_commPts > 0.0 ? (" = " + F1(g_commPts) + " pt andata e ritorno, inclusa automaticamente") : " (zero: nessuna commissione inclusa)") +
          string(g_pvWarn ? " [valore del punto stimato]" : "") + ". ";
   run += "Divisione dei dati: primo " + IS(MathMin(95, MathMax(5, InpSplitPct))) + "% del periodo per scegliere, il resto per verificare; le scelte di gestione, filtri, orari e parametri sono valutate solo sul resto (le tabelle B con rumore sono scelte sull'intero storico e indicate come tali). ";
   run += "Tabelle di base su " + IS(g_nT) + " TF (direzione, costi, orari, classifiche, prove di stress). ";
   if(g_mgOn)
     {
      run += "Gestione simulata su " + IS(g_mgNtf) + " TF: " + IS(g_mgNsl) + " stop x " + IS(g_mgNtr) + " trailing x " + IS(g_mgNtp) + " target" + string(g_mgNv > 1 ? " x 2 unita' (ATR del momento e punti fissi)" : "") + " = " + IS(g_mgR) + " gestioni x " + IS(g_nH) + " durate, " +
             IS(g_mgNlag) + " ritardi d'ingresso (" + MgLagTotList() + " min)" + string(InpMgmtSelect ? ", selezione di orari e giorni (168 celle ora x giorno)" : "") + ". ";
     }
   else
      skip += "gestione simulata (spenta o non eseguita); ";
   if(InpPeak && g_pkNtf > 0) run += "Picchi, stop e rischio su " + IS(g_pkNtf) + " TF: " + IS(g_pkNk) + " ritiri (" + MgDblList(g_pkK, g_pkNk) + " ATR), griglia di " + IS(PK_NSL) + " stop x " + IS(g_pkNj) + " target in due unita', orari, classi (sequenza, intensita', volume tick, regime, ADX) e scala del rischio. ";
   else skip += string(InpPeak ? "picchi, stop e rischio (nessun TF valido); " : "picchi, stop e rischio (spento in InpPeak); ");
   if(g_mgOn && g_mgNtf < g_nT) skip += "gestione simulata, filtri e orari solo su " + IS(g_mgNtf) + " TF su " + IS(g_nT) + " (InpMgmtTFs); ";
   if(g_mgOn && !InpMgmtSelect) skip += "selezione di orari e giorni (spenta in InpMgmtSelect); ";
   if(InpFilterScan && g_mgOn) run += "Scansione dei filtri: " + IS(g_fsNv) + " varianti per TF (ADX x regimi x volatilita' in salita). ";
   else skip += string(InpFilterScan ? "scansione dei filtri (richiede la gestione simulata); " : "scansione dei filtri (spenta in InpFilterScan); ");
   if(g_swQ > 0)
     {
      run += "Scansione dei parametri del segnale Delta: " + IS(g_swQ) + " combinazioni di EmaPeriod x VolAvgPeriod x SignalThreshold su " + IS(g_swTfN) + " TF. ";
      int nNoM1 = 0;
      for(int t = 0; t < g_nT; t++) if(g_tf[t] != PERIOD_M1) nNoM1++;
      if(g_swTfN < nNoM1) skip += "scansione dei parametri solo su " + IS(g_swTfN) + " TF su " + IS(nNoM1) + " (M1 esclusa; gli altri fuori da InpSweepTFs o con storico insufficiente); ";
     }
   else skip += "scansione dei parametri (" + string(g_swNote != "" ? g_swNote : (InpSweep ? "nessun TF con storico sufficiente" : "spenta in InpSweep")) + "); ";
   if(StringLen(skip) > 2) skip = StringSubstr(skip, 0, StringLen(skip) - 2);
   const string runTx = run + string(skip != "" ? ("NON eseguiti o parziali: " + skip + ".") : "Tutti i test sono stati eseguiti su ogni TF disponibile (M1 esclusa dalla scansione dei parametri): nessun input da impostare.") +
                        " Ogni TF ha in fondo la sua scheda, per serie, con l'esito di ciascun test misurato sul periodo di verifica (i numeri in-sample sono indicati come tali).";
   //--- esito complessivo
   {
    long evAll = 0, psAll = 0;
    for(int q = 0; q < g_nSets * g_nT; q++) { evAll += g_cdEval[q]; psAll += g_cdPos[q]; }
    string ov;
    if(evAll == 0)
       ov = "Nessun test e' valutabile fuori campione (campione insufficiente o test non eseguiti): non emerge evidenza ne' a favore ne' contro un vantaggio operabile.";
    else
       ov = "Su " + IS(evAll) + " test valutabili (gestione, orari e giorni, filtri" + string(InpPeak ? ", griglia stop x target, orari e classe dei picchi" : "") + " e, per il Delta, scansione dei parametri; tutti i TF e tutte le serie) " + IS(psAll) + " sono positivi con t >= 2 fuori campione; " +
            "per puro caso se ne attendono circa " + F1(0.0228 * (double)evAll) + " (i test condividono gli stessi segnali: non sono indipendenti, e ogni test sceglie la sua variante migliore sul primo periodo). " +
            string(psAll == 0 ? "Nessun test supera il caso: con questi dati non emerge un vantaggio operabile in nessun time frame, con le gestioni, i filtri e i parametri provati." :
                   ("Test positivi (candidati da confermare su altri simboli e periodi, non conferme): " + g_cdWin + "."));
    AddConcFront(-3, "Esito complessivo di tutti i test", ov);
   }
   AddConcFront(-3, "Test eseguiti in automatico", runTx);
   //--- schede
   for(int s = 0; s < g_nSets; s++)
      for(int t = 0; t < g_nT; t++)
        {
         const int ix = s * g_nT + t;
         const bool anyMg = (g_cdPts[ix] != "" || g_cdMg[ix] != "" || g_cdLag[ix] != "" || g_cdSel[ix] != "" || g_cdFilt[ix] != "" || g_cdPk[ix] != "");
         const bool anySw = (s == 0 && g_setMode[0] == SD_MODE_DELTA && g_cdSw[t] != "");
         if(!anyMg && !anySw) continue;
         string pts0 = g_cdPts[ix];
         if(StringLen(pts0) > 0 && StringSubstr(pts0, StringLen(pts0) - 1, 1) == ".") pts0 = StringSubstr(pts0, 0, StringLen(pts0) - 1);
         string tx = "PUNTI MEDI PER SEGNALE (uscita a tempo, tutto il periodo): " + string(pts0 != "" ? pts0 : "non disponibili") + ". ";
         tx += "GESTIONE: " + string(g_cdMg[ix] != "" ? g_cdMg[ix] : (g_mgOn ? "non eseguita su questo TF" : "spenta o non eseguita")) + ". ";
         tx += "RITARDO: " + string(g_cdLag[ix] != "" ? g_cdLag[ix] : "non valutato") + ". ";
         tx += "ORARI E GIORNI: " + string(g_cdSel[ix] != "" ? g_cdSel[ix] : "non valutati") + ". ";
         tx += "FILTRI: " + string(g_cdFilt[ix] != "" ? g_cdFilt[ix] : "non valutati") + ". ";
         if(InpPeak) tx += "PICCHI E STOP: " + string(g_cdPk[ix] != "" ? g_cdPk[ix] : "non valutati") + " ";
         if(s == 0 && g_setMode[0] == SD_MODE_DELTA) tx += "SCANSIONE PARAMETRI DELTA: " + string(g_cdSw[t] != "" ? g_cdSw[t] : (g_swQ > 0 ? (g_tf[t] == PERIOD_M1 ? "M1 non supportata dalla scansione" : "TF non incluso nella scansione (InpSweepTFs)") : "non eseguita")) + ". ";
         const int ev = g_cdEval[ix], ps = g_cdPos[ix];
         tx += "ESITO DEL TF: test positivi con t >= 2 fuori campione: " + IS(ps) + " su " + IS(ev) + " valutabili (gestione, orari e giorni, filtri" + string(InpPeak ? ", griglia stop x target, orari e classe dei picchi" : "") + string(s == 0 && g_setMode[0] == SD_MODE_DELTA ? ", scansione dei parametri" : "") + "; circa " +
               F1(0.0228 * (double)ev) + " attesi per puro caso, e i test condividono gli stessi segnali). " +
               string(ev == 0 ? "Non valutabile: campione fuori campione insufficiente." : (ps == 0 ? "Nessuna evidenza di un vantaggio operabile su questo TF." : "Candidato da confermare su altri simboli e periodi, non una conferma."));
         AddConc(s, "Scheda " + g_tfName[t], tx);
        }
   //--- la scansione e' sempre sul Delta: se la serie 0 non e' il Delta (InpMode diverso) il dettaglio per TF non entra nelle schede e va qui
   if(g_swQ > 0 && g_setMode[0] != SD_MODE_DELTA)
     {
      string sw = "";
      for(int t = 0; t < g_nT; t++) if(g_cdSw[t] != "") sw += g_tfName[t] + ": " + g_cdSw[t] + "; ";
      AddConc(-2, "Scansione dei parametri del segnale Delta, dettaglio per time frame", sw);
     }
  }

string SetLbl(const int s)
  {
   if(s == -3) return "TEST";
   if(s == -2) return "SCANSIONE";
   if(s < 0) return "CONFRONTO";
   return g_setTag[s];
  }

string SummaryPlain()
  {
   string out = "SignalLab MultiTF - riepilogo e conclusioni - " + _Symbol + " - " + ModeName() + "\n";
   for(int k = 0; k < ArraySize(g_cSet); k++)
      out += "\n[" + SetLbl(g_cSet[k]) + "] " + g_cTopic[k] + ": " + g_cText[k] + "\n";
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
      W("<tr><td>" + HtmlEsc(SetLbl(g_cSet[k])) + "</td><td>" + HtmlEsc(g_cTopic[k]) + "</td><td>" + HtmlEsc(g_cText[k]) + "</td></tr>");
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
   d += "RUN|costfix|" + F1(InpCostPoints) + "|extra|" + F1(InpExtraCostPts) + "|commpts|" + F1(g_commPts) + "|lot|" + LotTxt() + "|pv|" + DoubleToString(g_pv, 4) + "|ccy|" + g_ccy + "|commlot|" + F2(InpCommissionPerLotSide) + "|pvwarn|" + IS(g_pvWarn ? 1 : 0) + "|pvinfo|" + g_pvInfo +
        "|side|" + string(InpRankSide == RS_FOLLOW ? "follow" : (InpRankSide == RS_FADE ? "fade" : "both")) + "|maxgap|" + IS(InpMaxGapMin) +
        "|entrygap|" + IS(InpMaxEntryGapMin) + "|entrylag|" + IS(InpEntryLagMin) + "|skipwin|" + InpSkipEntryWin + "|fixedrule|" + InpFixedRule + "|bucket|" + IS(g_bMin) + "|parent|" + ParentName() +
        "|ref|" + IS(g_hor[g_refH]) + "|sets|" + IS(g_nSets) + "\n";
   d += "FILTCFG|adx|" + string(g_adxFilt ? ("on|period|" + IS(MathMax(1, InpAdxPeriod)) + "|min|" + DoubleToString(InpAdxMin, 1)) : string("off")) + "|regime|" + string(g_regFilt ? ("on|mask|" + IS(g_regMask) + "|rising|" + IS(InpRequireVolRising ? 1 : 0)) : string("off")) + "\n";
   d += "# MGMT/MGMTBEST/MGMTLAG/MGMTSEL/MGMTH: gestione simulata; sl/trail/tp in unita' 'unit' (atr = multipli dell'ATR del TF del segnale, pt = punti), hold = durata massima in minuti, tutto in punti per segnale; la gestione e la durata di MGMTBEST/MGMTLAG/MGMTSEL sono scelte in-sample a ritardo 0\n";
   d += "MGMTCFG|on|" + IS(InpMgmt ? 1 : 0) + "|unit|" + string(InpMgmtPoints ? "pt" : "atr") + "|atrlen|" + IS(InpMgmtAtrLen) + "|highfirst|" + IS(InpMgmtHighFirst ? 1 : 0) + "|maxsignals|" + IS(InpMgmtMaxSignals) + "|sl|" + InpMgmtSlAtr + "|trail|" + InpMgmtTrailAtr + "|tp|" + InpMgmtTpAtr +
        "|lags|" + InpMgmtLags + "|entrylagbase|" + IS(InpEntryLagMin) + "|select|" + IS(InpMgmtSelect ? 1 : 0) + "|selmincell|" + IS(InpSelMinCell) + "|selmint|" + F1(InpSelMinT) + "|fixedvar|" + IS(g_mgNv > 1 ? 1 : 0) + "|rules|" + IS(g_mgR) + "\n";
   d += "# PKCFG/PK/PKSEQ/PKBEST/PKGRID/PKCLS/PKVOL/PKVOLH/PKRISK/PKTEST: picchi (ritiro in ATR che chiude il picco; conf = % chiusi dal ritiro; p50/p75/p90 in punti; atr50/atr90 in ATR; min50 minuti al picco; mae50 = contro prima del picco), sequenze (pos = posizione nella sequenza; done = percorso gia' fatto), gestione stop x target scelta in-sample (sl, tp in ATR; netto in punti), classi (c: 0 tutti, 1-24 ora, 25-32 posizione, 33-38 intensita', 39-42 volume, 43-46 regime, 47-50 ADX, 51-54 percorso), rischio\n";
   d += "PKCFG|on|" + IS(InpPeak ? 1 : 0) + "|ret|" + InpPeakPullbacks + "|tp|" + InpPeakTpAtr + "|goodtp|" + ThrLbl(InpPeakGoodTp) + "|goodsl|" + ThrLbl(InpPeakGoodSl) + "|window|" + IS(InpPeakMaxMin) + "|candles|" + IS(InpPeakMaxCandles) + "|cross|" + IS(InpPeakCross ? 1 : 0) +
        "|maxsignals|" + IS(InpPeakMaxSignals) + "|minn|" + IS(InpPeakMinN) + "|riskmax|" + ThrLbl(InpRiskMaxPct) + "|riskstep|" + ThrLbl(InpRiskStepPct) + "|kelly|" + ThrLbl(InpRiskKelly) + "|balance|" + F2(g_acctBal) + "|equity|" + F2(g_acctEq) + "\n";
   d += "# FSCAN/FSVAR/FSPOOL: scansione automatica dei filtri con la gestione scelta di ogni TF; FSVAR kind = nofilter, ea (ADX 17 senza HIGH), top (prime 10 in-sample), adx, regonly, regwithout, rising\n";
   d += "FSCFG|on|" + IS(InpFilterScan ? 1 : 0) + "|adx|" + InpFilterAdx + "|variants|" + IS(g_fsNv) + "\n";
   d += "DATA|m1bars|" + IS(g_n1) + "|days|" + IS(g_nDays) + "|medrange|" + F0(g_medRange) + "|medspr|" + F0(g_medSpr) +
        "|zerospr|" + F1(g_zeroSprPct) + "\n";
   d += "# CARD/CARDYEAR: scheda delle prime regole (posizioni, vincenti, peggiore, drawdown, anni). # STRESSPOP/STRESSLAG/STRESSCOST: prove di stress (ritardo d'ingresso in minuti, costo extra in punti), netto medio in punti; POP = ogni segnale del TF, LAG/COST = regole della tabella A fuori campione\n";
   d += "# SPRH: spread M1 (punti) per fascia d'entrata (ora server + offset): barre, medio, mediano, p90\n";
   for(int rb = 0; rb < g_nRB; rb++)
      if(g_sprN[rb] > 0.0)
         d += "SPRH|" + RBktLabel(rb) + "|n|" + F0(g_sprN[rb]) + "|mean|" + F1(g_sprMean[rb]) + "|med|" + F0(g_sprMed[rb]) + "|p90|" + F0(g_sprP90[rb]) + "\n";
   return d;
  }

//--- righe della singola serie (le righe RANK, NOISE, VST, TOP... le aggiungono le funzioni Rep*)
string BuildDigestSet()
  {
   string d = "SETINFO|name|" + g_setTag[g_curSet] + "|zbonf|" + F2(g_zB) + "\n";
   for(int t = 0; t < g_nT; t++)
      d += "TF|" + g_tfName[t] + "|bars|" + IS(g_tfBars[t]) + "|base|" + IS(g_tfCnt[t]) + "|signals|" + IS(g_tfEv[t]) +
           "|rejgap|" + IS(g_tfRejGap[t]) + "|rejm1|" + IS(g_tfRejM1[t]) + "|rejwin|" + IS(g_tfRejWin[t]) + "|rejadx|" + IS(g_tfRejAdx[t]) + "|rejreg|" + IS(g_tfRejReg[t]) + "\n";
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
        { g_cmpN[ci] = cs.n; g_cmpMfe[ci] = cs.mfe; g_cmpMae[ci] = cs.mae; g_cmpRet[ci] = cs.ret; g_cmpTcl[ci] = cs.tCl; g_cmpGross[ci] = cs.gross; }
      else
        { g_cmpN[ci] = 0.0; g_cmpMfe[ci] = 0.0; g_cmpMae[ci] = 0.0; g_cmpRet[ci] = 0.0; g_cmpTcl[ci] = 0.0; g_cmpGross[ci] = 0.0; }
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
   g_cAok = false; g_cBok = false; g_cPok = false; g_cPstrong = 0; g_cPstrongN = 0; g_cAstrongN = 0; g_cAone = 0; g_cPbest = 0.0; g_cAns = 0; g_cAsurv = ""; g_cAsurvMean = 0.0; g_cAsurvN = 0.0; g_cBdesc = ""; g_cBsumAll = 0.0; g_cStress = "";
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
   RepMgmt();
   RepPeaks();
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
     "Il netto OOS &egrave; la sola colonna che conta; un netto OOS positivo con t &ge; 2 su una sola riga non basta, serve una verifica su un periodo successivo o su un altro simbolo.</div>");
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
   BuildCards();
   RepCompare();
   RepSummary();
   if(ArraySize(g_cSet) > 0)
     {
      g_dgSets += "### CONCL\n";
      for(int k = 0; k < ArraySize(g_cSet); k++)
         g_dgSets += "CONCL|" + SetLbl(g_cSet[k]) + "|" + g_cTopic[k] + "|" + g_cText[k] + "\n";
     }
   g_dg = BuildDigestHeader() + g_dgSets;
   string esc = g_dg;
   StringReplace(esc, "&", "&amp;");
   StringReplace(esc, "<", "&lt;");
   W("<div class='sec' style='order:9'>");
   W("<h2>Digest da copiare</h2>");
   if(StringLen(esc) <= 1500000)
     {
      W("<div class='note'>Seleziona e incolla in chat. Stesso testo in <b>MQL5/Files/SignalLab_MultiTF_digest_" + g_reportTag + ".txt</b>.</div>");
      W("<pre>" + esc + "### END\n</pre>");
     }
   else
      W("<div class='note'>Il digest completo (" + F1((double)StringLen(esc) / 1048576.0) + " MB: tutte le gestioni, le combinazioni e le varianti) non e' incorporato nella pagina; &egrave; nel file <b>MQL5/Files/SignalLab_MultiTF_digest_" + g_reportTag + ".txt</b>. "
        "Il testo da incollare in chat &egrave; il <b>riepilogo</b> in cima alla pagina (stesso testo in <b>MQL5/Files/SignalLab_MultiTF_riepilogo_" + g_reportTag + ".txt</b>).</div>");
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
   SetupMoney();                       // dopo il caricamento: puo' usare l'ultimo prezzo dello storico come cambio
   g_acctBal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_acctEq  = AccountInfoDouble(ACCOUNT_EQUITY);

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
    ArrayResize(g_cmpGross, nc); ArrayInitialize(g_cmpGross, 0.0);
    ArrayResize(g_cmpBoN, nc); ArrayInitialize(g_cmpBoN, 0.0);
    ArrayResize(g_cmpBoM, nc); ArrayInitialize(g_cmpBoM, 0.0);
    ArrayResize(g_cmpBoT, nc); ArrayInitialize(g_cmpBoT, 0.0);
    ArrayResize(g_cmpDesc, nc);
    for(int q = 0; q < nc; q++) g_cmpDesc[q] = "-";
   }
   {
    const int nCd = g_nSets * g_nT;
    ArrayResize(g_cdPts, nCd); ArrayResize(g_cdMg, nCd); ArrayResize(g_cdLag, nCd); ArrayResize(g_cdSel, nCd); ArrayResize(g_cdFilt, nCd); ArrayResize(g_cdSw, g_nT); ArrayResize(g_cdPk, nCd);
    ArrayResize(g_cdPos, nCd); ArrayInitialize(g_cdPos, 0);
    ArrayResize(g_cdEval, nCd); ArrayInitialize(g_cdEval, 0);
    for(int q = 0; q < nCd; q++) { g_cdPts[q] = ""; g_cdMg[q] = ""; g_cdLag[q] = ""; g_cdSel[q] = ""; g_cdFilt[q] = ""; g_cdPk[q] = ""; }
    for(int q = 0; q < g_nT; q++) g_cdSw[q] = "";
   }
   ArrayResize(g_tfRejGap, g_nT); ArrayInitialize(g_tfRejGap, 0);
   ArrayResize(g_tfRejM1, g_nT);  ArrayInitialize(g_tfRejM1, 0);
   ArrayResize(g_tfRejWin, g_nT); ArrayInitialize(g_tfRejWin, 0);
   ArrayResize(g_tfRejAdx, g_nT); ArrayInitialize(g_tfRejAdx, 0);
   ArrayResize(g_tfRejReg, g_nT); ArrayInitialize(g_tfRejReg, 0);
   {
    //--- candele successive: accumulatori di entrambe le serie (riempiti durante il calcolo dei segnali)
    const long cells = (long)g_nSets * g_nT * g_nMem * g_nM;
    const long nxbN = (long)g_nT * g_nMem * g_nM * NXF;
    const long nsbN = (long)g_nSets * g_nT * 19 * g_nB * g_nM;
    const long nbbN = (long)g_nT * 19 * g_nB * g_nM * 4;
    if(cells * NXF + cells * 2 * NXB + nxbN + nsbN + nbbN > 300000000L ||
       ArrayResize(g_nx, (int)(cells * NXF)) != (int)(cells * NXF) ||
       ArrayResize(g_nxh, (int)(cells * 2 * NXB)) != (int)(cells * 2 * NXB) ||
       ArrayResize(g_nxb, (int)nxbN) != (int)nxbN ||
       ArrayResize(g_nxsb, (int)nsbN) != (int)nsbN ||
       ArrayResize(g_nxbb, (int)nbbN) != (int)nbbN)
      {
       Print("Memoria insufficiente per le candele successive: riduci InpNextCandles, i TF o allarga le fasce (InpBucketMin).");
       return;
      }
    ArrayInitialize(g_nx, 0.0);
    ArrayInitialize(g_nxh, 0);
    ArrayInitialize(g_nxb, 0.0);
    ArrayInitialize(g_nxsb, 0);
    ArrayInitialize(g_nxbb, 0.0);
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
   RepSweep();
   if(IsStopped()) { Print("Interrotto dall'utente."); Comment(""); ReportAbort(); return; }
   ReportEnd();
   Comment("");
   Print("Fatto in ", (GetTickCount() - t0) / 1000.0, " s");
  }
//+------------------------------------------------------------------+
