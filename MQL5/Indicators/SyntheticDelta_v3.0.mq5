//+------------------------------------------------------------------+
//|                                        SyntheticDelta_v3.0.mq5   |
//|        Flusso sintetico da OHLC + tick volume, sub-finestra      |
//+------------------------------------------------------------------+
//  Aggiornamento di SyntheticDelta v2.1. COSA CAMBIA E PERCHE':
//
//  1) Il termine EMA/Bulls-Bears e' RIMOSSO dal flusso. In v2.1
//     bullsNorm + bearsNorm = (H-EMA)/R + (EMA-L)/R = 1 identicamente, quindi
//     synDelta = volWeight * [ CLV + (Close-EMA)/R ]: due termini, non tre
//     fattori indipendenti, e il secondo e' normalizzato per il range della
//     barra (esplode sulle barre piccole). Qui il flusso e' solo CLV (oppure
//     BVC); il trend va letto a parte, non nascosto dentro il delta.
//  2) Volume relativo STAGIONALE: tick volume della barra / MEDIANA del volume
//     nella stessa fascia oraria dei D giorni precedenti. La media a 20 barre
//     di v2.1 e' al massimo peso (3) a ogni apertura di sessione.
//  3) Aggregazione su N barre (media del CLV pesata per attivita') e z-score
//     su finestra mobile: le soglie diventano quantili stazionari. In v2.1 la
//     soglia 0.15 (normalizedDelta) faceva passare circa il 60% delle barre
//     in simulazione; qui |Z|>1.5 e' circa il 13% per costruzione.
//  4) Assorbimento (effort vs result): attivita' relativa alta con spostamento
//     di prezzo piccolo. Ipotesi da TESTARE, non un segnale.
//  5) Calcolo SOLO su barre chiuse (ClosedBarsOnly): niente repaint intrabar.
//  6) I filtri ADX e S/R di v2.1 sono tolti dall'indicatore. Il filtro S/R era
//     simmetrico rispetto al segno e mescolava continuazione e inversione:
//     appartiene allo strato di strategia, da testare con IC per contesto.
//
//  Riferimenti (verificati su SSRN/NBER/riviste): Easley-Lopez de Prado-O'Hara,
//  RFS 2012 (BVC); Campbell-Grossman-Wang, QJE 1993; Llorente et al., RFS 2002;
//  Osler, J. Finance 2003. Il CLV e' la formula di Chaikin/Williams.
//
//  AVVERTENZE ONESTE
//  - Il tick volume NON ha segno: la direzione viene solo dal CLV (o dal BVC).
//    E' un proxy rumoroso, dipendente dal broker.
//  - Nessuna evidenza di edge: e' uno strumento di misura per ricerca.
//  - La logica e' verificata con il riferimento Python
//    research/syntheticdelta_ref.py (incrementale == completo, causalita').
//    Questo file NON e' stato compilato in ambiente di sviluppo: compila in
//    MetaEditor e controlla la sezione Errors prima di usarlo.
//+------------------------------------------------------------------+
#property copyright "SyntheticDelta"
#property version   "3.00"
#property indicator_separate_window
#property indicator_buffers 13
#property indicator_plots   3

#property indicator_label1  "Flow Z"
#property indicator_type1   DRAW_COLOR_HISTOGRAM
#property indicator_color1  clrSilver,clrLimeGreen,clrTomato
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Absorption Z"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGold
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Legacy v2.1 (scalato)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

//--- ================================================================
enum ENUM_FLOW_MODE
  {
   FLOW_CLV = 0,   // CLV (Close Location Value)
   FLOW_BVC = 1    // BVC (Bulk Volume Classification)
  };

input group "=== FLUSSO ==="
input ENUM_FLOW_MODE FlowMode   = FLOW_CLV;  // Direzione per barra
input int            FlowBars   = 12;        // N: barre di aggregazione
input int            BvcBars    = 50;        // BVC: barre per la sigma dei rendimenti
input int            ZWindow    = 500;       // M: finestra dello z-score
input double         Threshold  = 1.5;       // Soglia |Z| per la colorazione

input group "=== VOLUME RELATIVO STAGIONALE ==="
input int            SeasonDays  = 20;       // D: giorni di storia per fascia oraria
input int            MinSessions = 5;        // Campioni minimi per fascia
input double         WeightCap   = 3.0;      // Tetto del peso w

input group "=== ASSORBIMENTO (effort vs result) ==="
input bool           ShowAbsorption = true;  // Mostra la linea di assorbimento
input int            AtrPeriod      = 14;    // Periodo ATR (media del TR)

input group "=== OPZIONI ==="
input bool           ClosedBarsOnly = true;  // Barra in formazione vuota (no repaint)

input group "=== CONFRONTO CON v2.1 ==="
input bool           ShowLegacy   = false;   // Linea del vecchio normalizedDelta
input int            LegacyEma    = 13;
input int            LegacyVolAvg = 20;
input double         LegacyScale  = 10.0;    // 0.15 (vecchia soglia) -> 1.5

//--- buffer di disegno
double bZ[], bZc[], bAb[], bLeg[];
//--- buffer di calcolo (persistono fra le chiamate, come in MT5)
double bW[], bFb[], bcF[], bcF2[], bcFn[], bcA[], bcA2[], bcAn[], bEma[];

//--- stato della storia stagionale
int    g_psec   = 0;
int    g_slots  = 1;
int    g_first  = 0;
int    g_pushed = -1;
double g_hist[];
double g_tmp[];
int    g_cnt[];
int    g_head[];

void ResetState();

//+------------------------------------------------------------------+
int OnInit()
  {
   if(FlowBars < 2 || BvcBars < 5 || ZWindow < 50 || SeasonDays < 3 ||
      MinSessions < 1 || MinSessions > SeasonDays || AtrPeriod < 2 ||
      LegacyEma < 1 || LegacyVolAvg < 2)
     {
      Print("SyntheticDelta v3.0: parametri non validi");
      return INIT_PARAMETERS_INCORRECT;
     }

   SetIndexBuffer(0,  bZ,   INDICATOR_DATA);
   SetIndexBuffer(1,  bZc,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,  bAb,  INDICATOR_DATA);
   SetIndexBuffer(3,  bLeg, INDICATOR_DATA);
   SetIndexBuffer(4,  bW,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,  bFb,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,  bcF,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,  bcF2, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8,  bcFn, INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,  bcA,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, bcA2, INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, bcAn, INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, bEma, INDICATOR_CALCULATIONS);

   for(int p = 0; p < 3; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, ShowAbsorption ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, ShowLegacy     ? DRAW_LINE : DRAW_NONE);

   g_psec  = PeriodSeconds();
   g_slots = MathMax(1, 86400 / MathMax(1, g_psec));
   g_first = MathMax(MathMax(AtrPeriod, BvcBars), FlowBars) + 2;
   ArrayResize(g_hist, g_slots * SeasonDays);
   ArrayResize(g_tmp,  SeasonDays);
   ArrayResize(g_cnt,  g_slots);
   ArrayResize(g_head, g_slots);
   ResetState();

   IndicatorSetInteger(INDICATOR_LEVELS, 3);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0,  Threshold);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, -Threshold);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 2,  0.0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrDimGray);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 1, clrDimGray);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 2, clrDimGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 1, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 2, STYLE_SOLID);
   IndicatorSetInteger(INDICATOR_DIGITS, 2);
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("SyntheticDelta v3.0 (%s, N=%d, M=%d)",
                                   FlowMode == FLOW_CLV ? "CLV" : "BVC", FlowBars, ZWindow));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void ResetState()
  {
   ArrayInitialize(g_cnt, 0);
   ArrayInitialize(g_head, 0);
   g_pushed = -1;
  }

//+------------------------------------------------------------------+
//  Fascia oraria della barra (ora del SERVER, come time[]).
//+------------------------------------------------------------------+
int SlotOf(const datetime t)
  {
   int s = (int)(((long)t % 86400) / g_psec);
   if(s >= g_slots) s = g_slots - 1;
   if(s < 0)        s = 0;
   return s;
  }

//--- buffer circolare per fascia: contiene sempre gli ultimi SeasonDays valori
void PushVol(const int slot, const double v)
  {
   int h = g_head[slot];
   g_hist[slot * SeasonDays + h] = v;
   g_head[slot] = (h + 1) % SeasonDays;
   if(g_cnt[slot] < SeasonDays)
      g_cnt[slot]++;
  }

//--- mediana dei valori della fascia (ordinamento per inserimento, n <= SeasonDays)
double MedianVol(const int slot)
  {
   int n = g_cnt[slot];
   int b = slot * SeasonDays;
   for(int k = 0; k < n; k++)
     {
      double v = g_hist[b + k];
      int m = k - 1;
      while(m >= 0 && g_tmp[m] > v)
        {
         g_tmp[m + 1] = g_tmp[m];
         m--;
        }
      g_tmp[m + 1] = v;
     }
   if((n & 1) == 1)
      return g_tmp[n / 2];
   return 0.5 * (g_tmp[n / 2 - 1] + g_tmp[n / 2]);
  }

//--- erf di Abramowitz-Stegun 7.1.26 (errore max 1.5e-7), come nel riferimento Python
double ErfAS(const double x)
  {
   const double p  = 0.3275911;
   const double a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741;
   const double a4 = -1.453152027, a5 = 1.061405429;
   double s  = (x < 0.0) ? -1.0 : 1.0;
   double ax = MathAbs(x);
   double t  = 1.0 / (1.0 + p * ax);
   double y  = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * MathExp(-ax * ax);
   return s * y;
  }

double NormCdf(const double z)
  {
   return 0.5 * (1.0 + ErfAS(z / 1.4142135623730951));
  }

//--- z-score di x rispetto alle ZWindow barre PRECEDENTI (barra corrente esclusa),
//    via somme cumulate: O(1) per barra
double RollZ(const double &cs[], const double &cs2[], const double &cn[],
             const int i, const double x, bool &ok)
  {
   ok = false;
   int hi = i - 1;
   if(hi < 0)
      return 0.0;
   int lo = hi - ZWindow;
   double s  = cs[hi]  - (lo >= 0 ? cs[lo]  : 0.0);
   double s2 = cs2[hi] - (lo >= 0 ? cs2[lo] : 0.0);
   double n  = cn[hi]  - (lo >= 0 ? cn[lo]  : 0.0);
   if(n < 0.5 * ZWindow)
      return 0.0;
   double mu = s / n;
   double vr = s2 / n - mu * mu;
   if(vr <= 1e-12)
      return 0.0;
   ok = true;
   return (x - mu) / MathSqrt(vr);
  }

//--- v2.1: normalizedDelta senza i filtri ADX / S/R (solo per il confronto)
double LegacyDelta(const int i, const double &high[], const double &low[],
                   const double &close[], const long &tick_volume[])
  {
   if(i < LegacyVolAvg)
      return EMPTY_VALUE;
   double range = high[i] - low[i];
   if(range <= 0.0)
      return EMPTY_VALUE;
   double tv = (double)tick_volume[i];
   if(tv <= 0.0)
      return EMPTY_VALUE;
   double ema     = bEma[i];
   double fracBuy = (close[i] - low[i]) / range;
   double fracSel = (high[i] - close[i]) / range;
   double bullsN  = (high[i] - ema) / range;
   double bearsN  = (ema - low[i]) / range;
   double sv  = 0.0;
   int    cnt = 0;
   for(int j = i; j > i - LegacyVolAvg && j >= 0; j--)
     {
      sv += (double)tick_volume[j];
      cnt++;
     }
   double avg = (cnt > 0) ? sv / cnt : tv;
   double vw  = (avg > 0.0) ? MathMin(tv / avg, 3.0) : 1.0;
   return (fracBuy * (1.0 + bullsN) - fracSel * (1.0 + bearsN)) * vw / 6.0;
  }

//+------------------------------------------------------------------+
//  Una barra. Le somme cumulate vengono riportate dalla barra i-1 e
//  incrementate solo se la barra e' valida: un return anticipato lascia
//  quindi lo stato coerente.
//+------------------------------------------------------------------+
void ComputeBar(const int i, const int total,
                const datetime &time[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[])
  {
   if(ShowLegacy)
     {
      double a = 2.0 / (LegacyEma + 1.0);
      bEma[i] = (i == 0) ? close[i] : a * close[i] + (1.0 - a) * bEma[i - 1];
     }

   bcF[i]  = (i > 0) ? bcF[i - 1]  : 0.0;
   bcF2[i] = (i > 0) ? bcF2[i - 1] : 0.0;
   bcFn[i] = (i > 0) ? bcFn[i - 1] : 0.0;
   bcA[i]  = (i > 0) ? bcA[i - 1]  : 0.0;
   bcA2[i] = (i > 0) ? bcA2[i - 1] : 0.0;
   bcAn[i] = (i > 0) ? bcAn[i - 1] : 0.0;
   bZ[i]   = EMPTY_VALUE;
   bZc[i]  = 0.0;
   bAb[i]  = EMPTY_VALUE;
   bLeg[i] = EMPTY_VALUE;
   bW[i]   = -1.0;
   bFb[i]  = 0.0;

   if(ShowLegacy)
     {
      double x = LegacyDelta(i, high, low, close, tick_volume);
      bLeg[i] = (x == EMPTY_VALUE) ? EMPTY_VALUE : x * LegacyScale;
     }

   if(i < g_first)
      return;
   if(ClosedBarsOnly && i == total - 1)
      return;

   double range = high[i] - low[i];
   double V     = (double)tick_volume[i];

   //--- ATR semplice: media del true range
   double sTR = 0.0;
   for(int j = i - AtrPeriod + 1; j <= i; j++)
      sTR += MathMax(high[j], close[j - 1]) - MathMin(low[j], close[j - 1]);
   double atr = sTR / AtrPeriod;

   //--- peso: volume / mediana della stessa fascia oraria nei D giorni precedenti
   int    slot = SlotOf(time[i]);
   double w    = -1.0;
   if(g_cnt[slot] >= MinSessions)
     {
      double med = MedianVol(slot);
      if(med > 0.0)
         w = MathMin(V / med, WeightCap);
     }
   if(w < 0.0)
      return;                      // warm-up: la fascia non ha ancora storia

   //--- direzione per barra, in [-1, 1]
   double dir = 0.0;
   if(FlowMode == FLOW_CLV)
      dir = (range > 0.0) ? ((close[i] - low[i]) - (high[i] - close[i])) / range : 0.0;
   else
     {
      double s2 = 0.0;
      for(int j = i - BvcBars + 1; j <= i; j++)
        {
         double d = close[j] - close[j - 1];
         s2 += d * d;
        }
      double sg = MathSqrt(s2 / BvcBars);
      dir = (sg > 0.0) ? 2.0 * NormCdf((close[i] - close[i - 1]) / sg) - 1.0 : 0.0;
     }
   bW[i]  = w;
   bFb[i] = w * dir;

   //--- aggregazione su FlowBars: media del CLV pesata per attivita', in [-1, 1]
   double sf = 0.0, sw = 0.0;
   for(int k = 0; k < FlowBars; k++)
     {
      int j = i - k;
      if(bW[j] < 0.0)
         return;                   // finestra incompleta
      sf += bFb[j];
      sw += bW[j];
     }
   if(sw <= 0.0)
      return;
   double F      = sf / sw;
   double effort = sw / FlowBars;  // attivita' relativa media (1 = normale)

   bool   ok;
   double z = RollZ(bcF, bcF2, bcFn, i, F, ok);
   bcF[i]  += F;
   bcF2[i] += F * F;
   bcFn[i] += 1.0;

   //--- assorbimento: attivita' alta, spostamento di prezzo piccolo
   if(atr > 0.0)
     {
      double res = MathAbs(close[i] - close[i - FlowBars]) / (atr * MathSqrt((double)FlowBars));
      double A   = MathLog(MathMax(effort, 0.05)) - MathLog(res + 0.1);
      bool   okA;
      double za = RollZ(bcA, bcA2, bcAn, i, A, okA);
      bcA[i]  += A;
      bcA2[i] += A * A;
      bcAn[i] += 1.0;
      if(okA)
         bAb[i] = za;
     }

   if(ok)
     {
      bZ[i]  = z;
      bZc[i] = (z >= Threshold) ? 1.0 : ((z <= -Threshold) ? 2.0 : 0.0);
     }
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
  {
   if(rates_total < g_first + 2)
      return 0;

   int start = (prev_calculated <= 0) ? 0 : prev_calculated - 1;
   //--- ricalcolo completo se serve; in uso normale start == g_pushed + 1
   if(start == 0 || start <= g_pushed)
     {
      ResetState();
      start = 0;
     }
   else
      if(start > g_pushed + 1)
         start = g_pushed + 1;

   for(int i = start; i < rates_total && !IsStopped(); i++)
     {
      ComputeBar(i, rates_total, time, high, low, close, tick_volume);
      //--- nella storia stagionale entrano SOLO barre chiuse, in ordine
      if(i < rates_total - 1 && i > g_pushed)
        {
         PushVol(SlotOf(time[i]), (double)tick_volume[i]);
         g_pushed = i;
        }
     }
   return rates_total;
  }
//+------------------------------------------------------------------+
