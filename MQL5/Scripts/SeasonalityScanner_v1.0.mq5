//+------------------------------------------------------------------+
//|                                   SeasonalityScanner_v1.0.mq5     |
//|                                                                   |
//|  SCOPO                                                            |
//|  Misurare il comportamento ricorrente di uno strumento su quattro  |
//|  scale temporali — intraday (ora del giorno), settimanale (giorno  |
//|  della settimana), mensile (giorno di trading del mese) e annuale  |
//|  (mese dell'anno) — e stampare un report HTML autoconsistente.     |
//|                                                                   |
//|  FILOSOFIA                                                        |
//|  Una media non e' un edge. Ogni cella del report riporta quindi:   |
//|    n          = numerosita' campionaria (sotto InpMinSample e'     |
//|                 rumore e viene marcata come tale)                  |
//|    media      = rendimento medio in basis point (1 bp = 0.01%)     |
//|    mediana    = robusta alle code grasse; se ha segno opposto      |
//|                 alla media, l'effetto e' guidato da outlier        |
//|    t-stat     = media / (sd/sqrt(n))                               |
//|    p-value    = bilaterale, approssimazione normale                |
//|    IS / OOS   = stesso effetto misurato su prima e seconda meta'   |
//|                 dello storico. Se il segno non concorda, l'effetto |
//|                 NON e' stabile e va scartato.                      |
//|                                                                   |
//|  CORREZIONE PER TEST MULTIPLI                                      |
//|  24 ore + 5 giorni + 12 mesi + ... sono decine di test simultanei. |
//|  Con 24 test al 5%, ~1.2 "scoperte" sono false per costruzione.    |
//|  Il report applica la soglia di Bonferroni per famiglia di test e  |
//|  promuove a SFRUTTABILE solo cio' che la supera E concorda IS/OOS  |
//|  E ha un edge lordo superiore al costo di transazione stimato.     |
//|                                                                   |
//|  OUTPUT: MQL5\Files\Seasonality_<SYMBOL>_<data>.html               |
//|  (MetaTrader non ha un browser interno: il percorso completo viene |
//|  stampato nel tab Esperti, si apre con doppio click.)              |
//+------------------------------------------------------------------+
#property copyright "Quant Research"
#property version   "1.00"
#property script_show_inputs

//--- INPUT --------------------------------------------------------------
input group "═══ 📅 PERIODO DI ANALISI ═══"
input int    InpYearsBack          = 10;      // Anni di storico da analizzare (piu' anni = piu' regimi diversi)
input int    InpMinSample          = 30;      // n minimo perche' una cella sia considerata statisticamente leggibile
input bool   InpSplitIS_OOS        = true;    // Divide lo storico a meta' e verifica che l'effetto esista in entrambe

input group "═══ 🕐 STRUTTURA INTRADAY (ora server) ═══"
input int    InpRangeStartHour     = 0;       // Ora di inizio del range di riferimento (default: apertura Sydney)
input int    InpRangeEndHour       = 8;       // Ora di fine del range (esclusa). Default 0-8 = Sydney+Asia
input int    InpMinBarsPerDay      = 12;      // Giorni con meno barre H1 di questo valore sono scartati (festivi/mezze sedute)

input group "═══ 💰 COSTI (per calcolare l'edge NETTO) ═══"
input double InpSpreadPoints       = 0.0;     // Spread medio in punti (0 = usa lo spread corrente del simbolo)
input double InpCommissionRT_Points= 0.0;     // Commissione round-turn convertita in punti (conto Raw: ~ 6-8 USD/lotto)

input group "═══ 📄 OUTPUT ═══"
input string InpOutputFile         = "";      // Nome file HTML (vuoto = automatico)
input bool   InpUseCommonFolder    = false;   // Salva nella cartella comune di tutti i terminali
input bool   InpVerboseLog         = true;    // Stampa anche un riassunto testuale nel tab Esperti

//--- COSTANTI -----------------------------------------------------------
#define BP           10000.0   // 1 unita' di log-return = 10000 bp
#define MAX_TDOM_S   10        // giorni di trading dall'inizio del mese tracciati
#define MAX_TDOM_E   5         // giorni di trading dalla fine del mese tracciati
#define EPS          1e-12

//+------------------------------------------------------------------+
//| Accumulatore statistico. Conserva i valori grezzi perche' servono |
//| mediana e quantili, non solo somma e somma dei quadrati.          |
//+------------------------------------------------------------------+
struct SAcc
{
   double v[];
   int    up;
   double abs_sum;
   double aux_sum;   // metrica secondaria (es. volume medio, range medio)
   int    aux_n;

   void Reset()          { ArrayFree(v); up=0; abs_sum=0; aux_sum=0; aux_n=0; }
   void Add(double x)    { int n=ArraySize(v); ArrayResize(v,n+1,1024); v[n]=x; if(x>0.0) up++; abs_sum+=MathAbs(x); }
   void AddAux(double x) { aux_sum+=x; aux_n++; }
   int  N()              { return ArraySize(v); }

   double Mean()
   {
      int n=ArraySize(v); if(n==0) return 0.0;
      double s=0.0; for(int i=0;i<n;i++) s+=v[i];
      return s/n;
   }
   double SD()
   {
      int n=ArraySize(v); if(n<2) return 0.0;
      double m=Mean(), s=0.0;
      for(int i=0;i<n;i++) { double d=v[i]-m; s+=d*d; }
      return MathSqrt(s/(n-1));
   }
   double TStat()
   {
      int n=ArraySize(v); if(n<2) return 0.0;
      double sd=SD(); if(sd<EPS) return 0.0;
      return Mean()/(sd/MathSqrt((double)n));
   }
   double Median()
   {
      int n=ArraySize(v); if(n==0) return 0.0;
      double t[]; ArrayCopy(t,v); ArraySort(t);
      if((n%2)==1) return t[n/2];
      return 0.5*(t[n/2-1]+t[n/2]);
   }
   double WinRate()   { int n=ArraySize(v); return (n==0)?0.0:100.0*up/n; }
   double MeanAbs()   { int n=ArraySize(v); return (n==0)?0.0:abs_sum/n; }
   double AuxMean()   { return (aux_n==0)?0.0:aux_sum/aux_n; }
};

//+------------------------------------------------------------------+
//| Una "scoperta" candidata, per il ranking finale                   |
//+------------------------------------------------------------------+
struct SFinding
{
   string family;     // famiglia di test (per la correzione di Bonferroni)
   string bucket;     // etichetta del bucket (es. "Martedi'", "15:00")
   double mean_bp;    // edge lordo medio in bp
   double t;
   double p;
   int    n;
   double winrate;
   int    oos_agree;  // 1 = segno concorde IS/OOS, 0 = discorde, -1 = non valutato
   double bonf_t;     // soglia |t| di Bonferroni per questa famiglia
   double net_bp;     // edge al netto dei costi stimati
   string note;
};

SFinding g_Find[];
int      g_FindCount = 0;

//--- STATO GLOBALE ------------------------------------------------------
int      g_H = INVALID_HANDLE;
double   g_CostBp = 0.0;          // costo round-turn stimato in bp
datetime g_SplitTime = 0;         // confine IS / OOS
string   g_Sym;
double   g_Point;
int      g_Digits;

MqlRates g_H1[];
MqlRates g_D1[];
int      g_nH1 = 0, g_nD1 = 0;

//--- ACCUMULATORI -------------------------------------------------------
SAcc g_Hour[24],  g_HourIS[24],  g_HourOOS[24];
SAcc g_Dow[7],    g_DowIS[7],    g_DowOOS[7];
SAcc g_Mon[13],   g_MonIS[13],   g_MonOOS[13];   // 1..12
SAcc g_TdomS[MAX_TDOM_S+1];                      // 1..MAX_TDOM_S
SAcc g_TdomE[MAX_TDOM_E+1];                      // 1..MAX_TDOM_E (1 = ultimo giorno)
SAcc g_TomIn, g_TomOut;                          // turn-of-month dentro/fuori finestra
SAcc g_Heat[7][24];                              // giorno settimana x ora
SAcc g_DowRange[7];                              // range giornaliero medio per giorno settimana

int  g_HighHour[24], g_LowHour[24];              // in quale ora si forma high/low del giorno
int  g_DaysScanned = 0;

// range breakout
int    g_BrkUpFirst=0, g_BrkDnFirst=0, g_BrkNone=0;
int    g_BrkUpCont=0,  g_BrkDnCont=0;            // rotture proseguite fino a chiusura oltre il livello
SAcc   g_BrkUpExt, g_BrkDnExt;                   // estensione max in unita' di range
SAcc   g_RangeSizeBp;

// gap di inizio settimana
SAcc   g_WeekGap;
int    g_GapFilled=0, g_GapTotal=0;

// rendimenti annui
int    g_Years[];
double g_YearRet[];

//+------------------------------------------------------------------+
//| Utility statistiche                                              |
//+------------------------------------------------------------------+
double NormCDF(double x)
{
   // Abramowitz & Stegun 26.2.17 — errore assoluto < 7.5e-8
   double s = (x < 0.0) ? -1.0 : 1.0;
   double ax = MathAbs(x) / MathSqrt(2.0);
   double t = 1.0 / (1.0 + 0.3275911 * ax);
   double y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * MathExp(-ax * ax);
   return 0.5 * (1.0 + s * y);
}

double PValueTwoSided(double t)
{
   if(t == 0.0) return 1.0;
   return 2.0 * (1.0 - NormCDF(MathAbs(t)));
}

// Soglia |t| di Bonferroni per k test simultanei al livello alpha (normale)
double BonferroniT(int k, double alpha = 0.05)
{
   if(k < 1) k = 1;
   double target = 1.0 - (alpha / (2.0 * k));   // quantile richiesto
   // ricerca binaria sul quantile normale
   double lo = 0.0, hi = 6.0;
   for(int i = 0; i < 80; i++) {
      double mid = 0.5 * (lo + hi);
      if(NormCDF(mid) < target) lo = mid; else hi = mid;
   }
   return 0.5 * (lo + hi);
}

double LogRet(double a, double b) { return (a > EPS && b > EPS) ? MathLog(b / a) : 0.0; }

//+------------------------------------------------------------------+
//| Scrittura HTML in UTF-8 reale (FileWrite su handle TXT scrive     |
//| UTF-16 e rompe la codifica delle pagine)                          |
//+------------------------------------------------------------------+
void W(string s)
{
   if(g_H == INVALID_HANDLE) return;
   uchar b[];
   int len = StringToCharArray(s, b, 0, -1, CP_UTF8) - 1;
   if(len > 0) FileWriteArray(g_H, b, 0, len);
}

string F(double x, int d = 2) { return DoubleToString(x, d); }

//+------------------------------------------------------------------+
//| Caricamento storico con attesa della sincronizzazione             |
//+------------------------------------------------------------------+
int LoadRates(ENUM_TIMEFRAMES tf, MqlRates &dst[], datetime from, datetime to)
{
   ArraySetAsSeries(dst, false);
   int got = -1;
   for(int attempt = 0; attempt < 20; attempt++) {
      got = CopyRates(g_Sym, tf, from, to, dst);
      if(got > 0) break;
      Sleep(300);
   }
   return got;
}

//+------------------------------------------------------------------+
//| Registra una scoperta candidata                                   |
//+------------------------------------------------------------------+
void PushFinding(string family, string bucket, SAcc &a, SAcc &is, SAcc &oos, int family_size, string note = "")
{
   int n = a.N();
   if(n < InpMinSample) return;

   double mean_bp = a.Mean() * BP;
   double t = a.TStat();

   int agree = -1;
   if(InpSplitIS_OOS && is.N() >= 10 && oos.N() >= 10) {
      double mi = is.Mean(), mo = oos.Mean();
      agree = ((mi > 0 && mo > 0) || (mi < 0 && mo < 0)) ? 1 : 0;
   }

   ArrayResize(g_Find, g_FindCount + 1, 64);
   g_Find[g_FindCount].family    = family;
   g_Find[g_FindCount].bucket    = bucket;
   g_Find[g_FindCount].mean_bp   = mean_bp;
   g_Find[g_FindCount].t         = t;
   g_Find[g_FindCount].p         = PValueTwoSided(t);
   g_Find[g_FindCount].n         = n;
   g_Find[g_FindCount].winrate   = a.WinRate();
   g_Find[g_FindCount].oos_agree = agree;
   g_Find[g_FindCount].bonf_t    = BonferroniT(family_size);
   g_Find[g_FindCount].net_bp    = MathAbs(mean_bp) - g_CostBp;
   g_Find[g_FindCount].note      = note;
   g_FindCount++;
}

//+------------------------------------------------------------------+
//| 1) ORA DEL GIORNO + heatmap giorno x ora                          |
//+------------------------------------------------------------------+
void BuildIntraday()
{
   MqlDateTime dt;
   for(int i = 1; i < g_nH1; i++) {
      // Salta i buchi (weekend, festivi, gap di quotazione): il rendimento
      // sarebbe attribuito a un'ora che non lo ha prodotto.
      if(g_H1[i].time - g_H1[i-1].time > 2 * 3600) continue;
      double r = LogRet(g_H1[i-1].close, g_H1[i].close);
      if(r == 0.0 && g_H1[i].tick_volume == 0) continue;

      TimeToStruct(g_H1[i].time, dt);
      int h = dt.hour;
      int d = dt.day_of_week;
      if(h < 0 || h > 23 || d < 0 || d > 6) continue;

      g_Hour[h].Add(r);
      g_Hour[h].AddAux((double)g_H1[i].tick_volume);
      g_Heat[d][h].Add(r);

      if(g_H1[i].time < g_SplitTime) g_HourIS[h].Add(r); else g_HourOOS[h].Add(r);
   }
}

//+------------------------------------------------------------------+
//| 2) GIORNO DELLA SETTIMANA + 3) GIORNO DI TRADING DEL MESE         |
//|    + 4) MESE DELL'ANNO + rendimenti annui                         |
//+------------------------------------------------------------------+
void BuildDailyAndAbove()
{
   MqlDateTime dt, dtn, dtp;

   //--- giorno della settimana (close-to-close) + range
   for(int i = 1; i < g_nD1; i++) {
      double r = LogRet(g_D1[i-1].close, g_D1[i].close);
      TimeToStruct(g_D1[i].time, dt);
      int d = dt.day_of_week;
      if(d < 0 || d > 6) continue;
      g_Dow[d].Add(r);
      if(g_D1[i].low > EPS)
         g_DowRange[d].Add(LogRet(g_D1[i].low, g_D1[i].high));
      if(g_D1[i].time < g_SplitTime) g_DowIS[d].Add(r); else g_DowOOS[d].Add(r);
   }

   //--- indicizzazione del giorno di trading all'interno del mese
   int tdom_start[];  ArrayResize(tdom_start, g_nD1);
   int tdom_end[];    ArrayResize(tdom_end,   g_nD1);
   ArrayInitialize(tdom_start, 0);
   ArrayInitialize(tdom_end,   0);

   int run = 0;
   for(int i = 0; i < g_nD1; i++) {
      TimeToStruct(g_D1[i].time, dt);
      bool new_month = true;
      if(i > 0) { TimeToStruct(g_D1[i-1].time, dtp); new_month = (dtp.mon != dt.mon || dtp.year != dt.year); }
      if(new_month) run = 0;
      run++;
      tdom_start[i] = run;
   }
   run = 0;
   for(int i = g_nD1 - 1; i >= 0; i--) {
      TimeToStruct(g_D1[i].time, dt);
      bool new_month = true;
      if(i < g_nD1 - 1) { TimeToStruct(g_D1[i+1].time, dtn); new_month = (dtn.mon != dt.mon || dtn.year != dt.year); }
      if(new_month) run = 0;
      run++;
      tdom_end[i] = run;
   }

   for(int i = 1; i < g_nD1; i++) {
      double r = LogRet(g_D1[i-1].close, g_D1[i].close);
      if(tdom_start[i] >= 1 && tdom_start[i] <= MAX_TDOM_S) g_TdomS[tdom_start[i]].Add(r);
      if(tdom_end[i]   >= 1 && tdom_end[i]   <= MAX_TDOM_E) g_TdomE[tdom_end[i]].Add(r);

      // Turn of month: ultimi 2 giorni del mese + primi 3 del successivo
      bool in_tom = (tdom_end[i] <= 2) || (tdom_start[i] <= 3);
      if(in_tom) g_TomIn.Add(r); else g_TomOut.Add(r);
   }

   //--- mese dell'anno: rendimento da ultima chiusura del mese precedente
   //    all'ultima chiusura del mese corrente
   double prev_close = 0.0;

   for(int i = 0; i < g_nD1; i++) {
      TimeToStruct(g_D1[i].time, dt);
      bool last_of_month = (i == g_nD1 - 1);
      if(!last_of_month) { TimeToStruct(g_D1[i+1].time, dtn); last_of_month = (dtn.mon != dt.mon || dtn.year != dt.year); }
      if(!last_of_month) continue;

      if(prev_close > EPS) {
         double r = LogRet(prev_close, g_D1[i].close);
         if(dt.mon >= 1 && dt.mon <= 12) {
            g_Mon[dt.mon].Add(r);
            if(g_D1[i].time < g_SplitTime) g_MonIS[dt.mon].Add(r); else g_MonOOS[dt.mon].Add(r);
         }
      }
      prev_close = g_D1[i].close;
   }

   //--- rendimenti per anno solare (serve a vedere i cambi di regime)
   double year_first = 0.0, year_last = 0.0;
   int    cur_year = -1;
   for(int i = 0; i < g_nD1; i++) {
      TimeToStruct(g_D1[i].time, dt);
      if(dt.year != cur_year) {
         if(cur_year != -1 && year_first > EPS) {
            int k = ArraySize(g_Years);
            ArrayResize(g_Years, k+1); ArrayResize(g_YearRet, k+1);
            g_Years[k] = cur_year;
            g_YearRet[k] = LogRet(year_first, year_last) * 100.0;
         }
         cur_year = dt.year;
         year_first = g_D1[i].open;
      }
      year_last = g_D1[i].close;
   }
   if(cur_year != -1 && year_first > EPS) {
      int k = ArraySize(g_Years);
      ArrayResize(g_Years, k+1); ArrayResize(g_YearRet, k+1);
      g_Years[k] = cur_year;
      g_YearRet[k] = LogRet(year_first, year_last) * 100.0;
   }
}

//+------------------------------------------------------------------+
//| 5) In quale ora si forma il massimo / minimo di giornata          |
//| 6) Rottura del range asiatico e sua prosecuzione                  |
//| 7) Gap di apertura settimanale                                    |
//+------------------------------------------------------------------+
void BuildDayStructure()
{
   ArrayInitialize(g_HighHour, 0);
   ArrayInitialize(g_LowHour, 0);

   MqlDateTime dt, dtp;
   int i = 0;
   double last_week_close = 0.0;
   int    last_week_num = -1;

   while(i < g_nH1) {
      // individua l'intervallo di barre appartenenti allo stesso giorno server
      TimeToStruct(g_H1[i].time, dt);
      int day = dt.day, mon = dt.mon, year = dt.year;
      int j = i;
      while(j < g_nH1) {
         TimeToStruct(g_H1[j].time, dtp);
         if(dtp.day != day || dtp.mon != mon || dtp.year != year) break;
         j++;
      }
      int cnt = j - i;

      if(cnt >= InpMinBarsPerDay) {
         g_DaysScanned++;

         //--- ora del massimo e del minimo
         int hi_idx = i, lo_idx = i;
         for(int k = i; k < j; k++) {
            if(g_H1[k].high > g_H1[hi_idx].high) hi_idx = k;
            if(g_H1[k].low  < g_H1[lo_idx].low)  lo_idx = k;
         }
         TimeToStruct(g_H1[hi_idx].time, dtp); if(dtp.hour >= 0 && dtp.hour < 24) g_HighHour[dtp.hour]++;
         TimeToStruct(g_H1[lo_idx].time, dtp); if(dtp.hour >= 0 && dtp.hour < 24) g_LowHour[dtp.hour]++;

         //--- range di riferimento e sua rottura
         double rh = -DBL_MAX, rl = DBL_MAX;
         int    range_end_idx = -1;
         for(int k = i; k < j; k++) {
            TimeToStruct(g_H1[k].time, dtp);
            if(dtp.hour >= InpRangeStartHour && dtp.hour < InpRangeEndHour) {
               if(g_H1[k].high > rh) rh = g_H1[k].high;
               if(g_H1[k].low  < rl) rl = g_H1[k].low;
               range_end_idx = k;
            }
         }

         if(range_end_idx >= 0 && rh > rl + EPS && range_end_idx < j - 1) {
            double range = rh - rl;
            g_RangeSizeBp.Add(LogRet(rl, rh));

            int  side = 0;           // +1 rottura al rialzo, -1 al ribasso
            double ext = 0.0;
            for(int k = range_end_idx + 1; k < j; k++) {
               if(side == 0) {
                  bool up = (g_H1[k].high > rh);
                  bool dn = (g_H1[k].low  < rl);
                  // Se una barra oraria rompe entrambi i lati non si puo' sapere
                  // quale sia arrivato prima: si scarta invece di indovinare.
                  if(up && dn) { side = 0; break; }
                  if(up) side = 1;
                  else if(dn) side = -1;
               }
               if(side == 1)       ext = MathMax(ext, (g_H1[k].high - rh) / range);
               else if(side == -1) ext = MathMax(ext, (rl - g_H1[k].low)  / range);
            }

            double day_close = g_H1[j-1].close;
            if(side == 1) {
               g_BrkUpFirst++;
               g_BrkUpExt.Add(ext);
               if(day_close > rh) g_BrkUpCont++;
            } else if(side == -1) {
               g_BrkDnFirst++;
               g_BrkDnExt.Add(ext);
               if(day_close < rl) g_BrkDnCont++;
            } else {
               g_BrkNone++;
            }
         }

         //--- gap di inizio settimana
         TimeToStruct(g_H1[i].time, dtp);
         if(dtp.day_of_week == 1 || (last_week_num != -1 && dtp.day_of_week < last_week_num)) {
            if(last_week_close > EPS) {
               double gap = LogRet(last_week_close, g_H1[i].open);
               g_WeekGap.Add(gap);
               g_GapTotal++;
               // Il gap si considera colmato se nel corso della prima giornata
               // il prezzo torna a toccare la chiusura di venerdi'.
               bool filled = false;
               for(int k = i; k < j; k++)
                  if(g_H1[k].low <= last_week_close && g_H1[k].high >= last_week_close) { filled = true; break; }
               if(filled) g_GapFilled++;
            }
         }
         TimeToStruct(g_H1[j-1].time, dtp);
         if(dtp.day_of_week == 5) last_week_close = g_H1[j-1].close;
         last_week_num = dtp.day_of_week;
      }

      i = j;
   }
}

//+------------------------------------------------------------------+
//| Raccolta delle scoperte candidate                                 |
//+------------------------------------------------------------------+
string DowName(int d)
{
   switch(d) { case 0: return "Domenica"; case 1: return "Lunedì"; case 2: return "Martedì";
               case 3: return "Mercoledì"; case 4: return "Giovedì"; case 5: return "Venerdì";
               case 6: return "Sabato"; }
   return "?";
}
string MonName(int m)
{
   string n[13] = {"", "Gennaio","Febbraio","Marzo","Aprile","Maggio","Giugno",
                   "Luglio","Agosto","Settembre","Ottobre","Novembre","Dicembre"};
   return (m >= 1 && m <= 12) ? n[m] : "?";
}

void CollectFindings()
{
   SAcc empty; empty.Reset();

   for(int h = 0; h < 24; h++)
      PushFinding("Ora del giorno", StringFormat("%02d:00", h), g_Hour[h], g_HourIS[h], g_HourOOS[h], 24);

   for(int d = 0; d < 7; d++)
      if(g_Dow[d].N() > 0)
         PushFinding("Giorno settimana", DowName(d), g_Dow[d], g_DowIS[d], g_DowOOS[d], 5);

   for(int m = 1; m <= 12; m++)
      PushFinding("Mese dell'anno", MonName(m), g_Mon[m], g_MonIS[m], g_MonOOS[m], 12);

   for(int k = 1; k <= MAX_TDOM_S; k++)
      PushFinding("Giorno del mese", StringFormat("TD +%d (dall'inizio)", k), g_TdomS[k], empty, empty, MAX_TDOM_S + MAX_TDOM_E);
   for(int k = 1; k <= MAX_TDOM_E; k++)
      PushFinding("Giorno del mese", StringFormat("TD -%d (dalla fine)", k), g_TdomE[k], empty, empty, MAX_TDOM_S + MAX_TDOM_E);

   // ordinamento per |t| decrescente
   for(int a = 0; a < g_FindCount - 1; a++)
      for(int b = 0; b < g_FindCount - a - 1; b++)
         if(MathAbs(g_Find[b].t) < MathAbs(g_Find[b+1].t)) {
            SFinding tmp = g_Find[b]; g_Find[b] = g_Find[b+1]; g_Find[b+1] = tmp;
         }
}

bool IsExploitable(SFinding &f)
{
   return (f.n >= InpMinSample && MathAbs(f.t) >= f.bonf_t && f.oos_agree != 0 && f.net_bp > 0.0);
}

//+------------------------------------------------------------------+
//| GENERAZIONE HTML                                                  |
//+------------------------------------------------------------------+
void HtmlHead(string title)
{
   W("<!DOCTYPE html><html lang=\"it\"><head><meta charset=\"utf-8\">");
   W("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">");
   W("<title>" + title + "</title><style>");
   W(":root{--bg:#0e1116;--panel:#161b22;--line:#272d36;--txt:#e6edf3;--dim:#8b949e;");
   W("--pos:#2ea043;--neg:#da3633;--warn:#d29922;--acc:#388bfd;}");
   W("*{box-sizing:border-box}");
   W("body{margin:0;padding:24px 16px;background:var(--bg);color:var(--txt);");
   W("font:14px/1.5 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}");
   W(".wrap{max-width:1180px;margin:0 auto}");
   W("h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:34px 0 10px;padding-bottom:6px;border-bottom:1px solid var(--line)}");
   W(".sub{color:var(--dim);font-size:13px;margin-bottom:18px}");
   W(".card{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:14px 16px;margin:12px 0}");
   W(".grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:10px}");
   W(".kpi{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px 12px}");
   W(".kpi .l{color:var(--dim);font-size:11px;text-transform:uppercase;letter-spacing:.04em}");
   W(".kpi .v{font-size:19px;font-weight:600;margin-top:2px}");
   W("table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums;font-size:13px}");
   W("th,td{padding:6px 8px;text-align:right;border-bottom:1px solid var(--line);white-space:nowrap}");
   W("th{color:var(--dim);font-weight:600;font-size:11px;text-transform:uppercase;letter-spacing:.04em;text-align:right}");
   W("th:first-child,td:first-child{text-align:left}");
   W("tbody tr:hover{background:#1c2230}");
   W(".pos{color:var(--pos)}.neg{color:var(--neg)}.dim{color:var(--dim)}.warn{color:var(--warn)}");
   W(".tag{display:inline-block;padding:1px 7px;border-radius:99px;font-size:11px;font-weight:600}");
   W(".t-ok{background:rgba(46,160,67,.16);color:var(--pos)}");
   W(".t-no{background:rgba(139,148,158,.16);color:var(--dim)}");
   W(".t-wa{background:rgba(210,153,34,.16);color:var(--warn)}");
   W(".bar{height:9px;border-radius:2px;display:block}");
   W(".barwrap{width:130px;background:#1c2230;border-radius:2px;position:relative;height:9px}");
   W(".barwrap i{position:absolute;top:0;left:50%;width:1px;height:9px;background:var(--line)}");
   W(".heat td{text-align:center;padding:3px 0;font-size:10px;border:1px solid var(--bg)}");
   W(".heat th{text-align:center;font-size:10px}");
   W("footer{color:var(--dim);font-size:12px;margin-top:40px;border-top:1px solid var(--line);padding-top:14px}");
   W("code{background:#1c2230;padding:1px 5px;border-radius:4px;font-size:12px}");
   W("</style></head><body><div class=\"wrap\">");
}

string SignedCell(double v, int dec = 2, string suffix = "")
{
   string cls = (v > 0) ? "pos" : ((v < 0) ? "neg" : "dim");
   string sgn = (v > 0) ? "+" : "";
   return "<td class=\"" + cls + "\">" + sgn + F(v, dec) + suffix + "</td>";
}

string BarCell(double v, double maxabs)
{
   if(maxabs < EPS) maxabs = 1.0;
   double frac = MathMin(MathAbs(v) / maxabs, 1.0) * 50.0;
   string col = (v >= 0) ? "var(--pos)" : "var(--neg)";
   string left = (v >= 0) ? "50%" : F(50.0 - frac, 2) + "%";
   return "<td><div class=\"barwrap\"><i></i><span class=\"bar\" style=\"position:absolute;left:" + left +
          ";width:" + F(frac, 2) + "%;background:" + col + "\"></span></div></td>";
}

string SigTag(SFinding &f)
{
   if(f.n < InpMinSample) return "<span class=\"tag t-no\">n insufficiente</span>";
   if(IsExploitable(f))   return "<span class=\"tag t-ok\">sfruttabile</span>";
   if(MathAbs(f.t) >= 1.96) {
      if(f.oos_agree == 0)  return "<span class=\"tag t-wa\">instabile IS/OOS</span>";
      if(f.net_bp <= 0.0)   return "<span class=\"tag t-wa\">edge &lt; costi</span>";
      return "<span class=\"tag t-wa\">non supera Bonferroni</span>";
   }
   return "<span class=\"tag t-no\">rumore</span>";
}

//--- tabella generica su una famiglia di bucket
void StatTable(string title, string col1, string &labels[], SAcc &accs[], SAcc &is[], SAcc &oos[],
               int from, int to, int family_size, bool has_split, string extra_col = "", double extra_scale = 1.0)
{
   double maxabs = 0.0;
   for(int i = from; i <= to; i++) if(accs[i].N() >= InpMinSample) maxabs = MathMax(maxabs, MathAbs(accs[i].Mean() * BP));

   W("<h2>" + title + "</h2><div class=\"card\"><table><thead><tr>");
   W("<th>" + col1 + "</th><th>n</th><th>Media (bp)</th><th></th><th>Mediana (bp)</th><th>% up</th>");
   W("<th>Vol media (bp)</th><th>t-stat</th><th>p</th>");
   if(has_split) W("<th>IS (bp)</th><th>OOS (bp)</th>");
   if(extra_col != "") W("<th>" + extra_col + "</th>");
   W("<th>Giudizio</th></tr></thead><tbody>");

   double bonf = BonferroniT(family_size);

   for(int i = from; i <= to; i++) {
      int n = accs[i].N();
      if(n == 0) continue;
      double m = accs[i].Mean() * BP;
      double t = accs[i].TStat();

      SFinding f;
      f.family = ""; f.bucket = ""; f.note = "";
      f.mean_bp = m; f.p = PValueTwoSided(t); f.winrate = accs[i].WinRate();
      f.n = n; f.t = t; f.bonf_t = bonf; f.net_bp = MathAbs(m) - g_CostBp; f.oos_agree = -1;
      if(has_split && is[i].N() >= 10 && oos[i].N() >= 10) {
         double mi = is[i].Mean(), mo = oos[i].Mean();
         f.oos_agree = ((mi > 0 && mo > 0) || (mi < 0 && mo < 0)) ? 1 : 0;
      }

      W("<tr><td>" + labels[i] + "</td>");
      W("<td class=\"" + (n < InpMinSample ? "warn" : "dim") + "\">" + IntegerToString(n) + "</td>");
      W(SignedCell(m, 2));
      W(BarCell(m, maxabs));
      W(SignedCell(accs[i].Median() * BP, 2));
      W("<td>" + F(accs[i].WinRate(), 1) + "%</td>");
      W("<td class=\"dim\">" + F(accs[i].MeanAbs() * BP, 1) + "</td>");
      W("<td class=\"" + (MathAbs(t) >= bonf ? "pos" : (MathAbs(t) >= 1.96 ? "warn" : "dim")) + "\">" + F(t, 2) + "</td>");
      W("<td class=\"dim\">" + F(PValueTwoSided(t), 4) + "</td>");
      if(has_split) {
         W(SignedCell(is[i].N() > 0 ? is[i].Mean() * BP : 0.0, 2));
         W(SignedCell(oos[i].N() > 0 ? oos[i].Mean() * BP : 0.0, 2));
      }
      if(extra_col != "") W("<td class=\"dim\">" + F(accs[i].AuxMean() * extra_scale, 0) + "</td>");
      W("<td>" + SigTag(f) + "</td></tr>");
   }
   W("</tbody></table>");
   W("<p class=\"dim\" style=\"margin:10px 0 0\">Soglia Bonferroni per questa famiglia (" +
     IntegerToString(family_size) + " test, α=5%): |t| &ge; " + F(bonf, 2) +
     ". Costo round-turn stimato: " + F(g_CostBp, 2) + " bp.</p></div>");
}

//+------------------------------------------------------------------+
void HtmlVerdict()
{
   W("<h2>⚑ Verdetto — inefficienze candidate</h2>");

   int n_ok = 0;
   for(int i = 0; i < g_FindCount; i++) if(IsExploitable(g_Find[i])) n_ok++;

   W("<div class=\"card\">");
   if(n_ok == 0) {
      W("<p><b class=\"warn\">Nessun effetto supera tutti e tre i filtri</b> (significativita' corretta per test multipli, ");
      W("concordanza prima meta' / seconda meta' dello storico, edge superiore ai costi di transazione).</p>");
      W("<p class=\"dim\">Non e' un fallimento dell'analisi: e' il risultato piu' frequente su strumenti liquidi. ");
      W("Le righe marcate <span class=\"tag t-wa\">non supera Bonferroni</span> o <span class=\"tag t-wa\">instabile IS/OOS</span> ");
      W("restano spunti da combinare con un filtro di contesto (volatilita', trend, evento macro), non da tradare da soli.</p>");
   } else {
      W("<p><b class=\"pos\">" + IntegerToString(n_ok) + " effetti</b> superano contemporaneamente: significativita' corretta ");
      W("per test multipli, concordanza di segno tra prima e seconda meta' dello storico, ed edge lordo superiore ai costi.</p>");
   }
   W("</div>");

   W("<div class=\"card\"><table><thead><tr><th>Famiglia</th><th>Bucket</th><th>n</th><th>Media (bp)</th>");
   W("<th>Netto costi (bp)</th><th>% up</th><th>t-stat</th><th>|t| richiesto</th><th>p</th><th>IS/OOS</th><th>Giudizio</th></tr></thead><tbody>");

   int shown = 0;
   for(int i = 0; i < g_FindCount && shown < 25; i++) {
      if(g_Find[i].n < InpMinSample) continue;
      shown++;
      W("<tr><td class=\"dim\">" + g_Find[i].family + "</td><td><b>" + g_Find[i].bucket + "</b></td>");
      W("<td class=\"dim\">" + IntegerToString(g_Find[i].n) + "</td>");
      W(SignedCell(g_Find[i].mean_bp, 2));
      W(SignedCell(g_Find[i].net_bp, 2));
      W("<td>" + F(g_Find[i].winrate, 1) + "%</td>");
      W("<td>" + F(g_Find[i].t, 2) + "</td>");
      W("<td class=\"dim\">" + F(g_Find[i].bonf_t, 2) + "</td>");
      W("<td class=\"dim\">" + F(g_Find[i].p, 4) + "</td>");
      string oo = (g_Find[i].oos_agree == 1) ? "<span class=\"pos\">concorde</span>"
                : ((g_Find[i].oos_agree == 0) ? "<span class=\"neg\">discorde</span>" : "<span class=\"dim\">n/d</span>");
      W("<td>" + oo + "</td><td>" + SigTag(g_Find[i]) + "</td></tr>");
   }
   W("</tbody></table><p class=\"dim\" style=\"margin:10px 0 0\">Ordinamento per |t-stat| decrescente, prime 25 righe con n sufficiente.</p></div>");
}

//+------------------------------------------------------------------+
void HtmlHeatmap()
{
   W("<h2>🔥 Mappa di calore — giorno della settimana × ora (rendimento medio, bp)</h2><div class=\"card\">");

   double maxabs = 0.0;
   for(int d = 1; d <= 5; d++)
      for(int h = 0; h < 24; h++)
         if(g_Heat[d][h].N() >= 20) maxabs = MathMax(maxabs, MathAbs(g_Heat[d][h].Mean() * BP));
   if(maxabs < EPS) maxabs = 1.0;

   W("<table class=\"heat\"><thead><tr><th></th>");
   for(int h = 0; h < 24; h++) W("<th>" + StringFormat("%02d", h) + "</th>");
   W("</tr></thead><tbody>");

   for(int d = 1; d <= 5; d++) {
      W("<tr><th style=\"text-align:left;padding-right:8px\">" + DowName(d) + "</th>");
      for(int h = 0; h < 24; h++) {
         int n = g_Heat[d][h].N();
         if(n < 20) { W("<td class=\"dim\" style=\"background:#12161d\">·</td>"); continue; }
         double m = g_Heat[d][h].Mean() * BP;
         double a = MathMin(MathAbs(m) / maxabs, 1.0);
         string col = (m >= 0) ? "rgba(46,160,67," + F(a * 0.85, 2) + ")"
                               : "rgba(218,54,51,"  + F(a * 0.85, 2) + ")";
         W("<td style=\"background:" + col + "\" title=\"" + DowName(d) + " " + StringFormat("%02d:00", h) +
           " — n=" + IntegerToString(n) + ", media " + F(m, 2) + " bp\">" + F(m, 0) + "</td>");
      }
      W("</tr>");
   }
   W("</tbody></table>");
   W("<p class=\"dim\" style=\"margin:10px 0 0\">Celle con n &lt; 20 non colorate. Il valore e' il rendimento medio ");
   W("della barra oraria che <b>apre</b> a quell'ora, in bp. Cerca blocchi contigui dello stesso colore: ");
   W("una singola cella isolata e' quasi certamente rumore.</p></div>");
}

//+------------------------------------------------------------------+
void HtmlExtremeHours()
{
   W("<h2>⏱ Dove si forma il massimo e il minimo di giornata</h2><div class=\"card\">");
   if(g_DaysScanned == 0) { W("<p class=\"dim\">Dati insufficienti.</p></div>"); return; }

   int maxc = 1;
   for(int h = 0; h < 24; h++) { maxc = MathMax(maxc, g_HighHour[h]); maxc = MathMax(maxc, g_LowHour[h]); }

   W("<table><thead><tr><th>Ora (server)</th><th>Max di giornata</th><th></th><th>Min di giornata</th><th></th><th>Estremo (uno dei due)</th></tr></thead><tbody>");
   for(int h = 0; h < 24; h++) {
      double ph = 100.0 * g_HighHour[h] / g_DaysScanned;
      double pl = 100.0 * g_LowHour[h]  / g_DaysScanned;
      W("<tr><td>" + StringFormat("%02d:00", h) + "</td>");
      W("<td>" + F(ph, 1) + "%</td>");
      W("<td><div class=\"barwrap\" style=\"width:100px\"><span class=\"bar\" style=\"width:" +
        F(100.0 * g_HighHour[h] / maxc, 1) + "%;background:var(--pos)\"></span></div></td>");
      W("<td>" + F(pl, 1) + "%</td>");
      W("<td><div class=\"barwrap\" style=\"width:100px\"><span class=\"bar\" style=\"width:" +
        F(100.0 * g_LowHour[h] / maxc, 1) + "%;background:var(--neg)\"></span></div></td>");
      W("<td class=\"dim\">" + F(ph + pl, 1) + "%</td></tr>");
   }
   W("</tbody></table>");
   W("<p class=\"dim\" style=\"margin:10px 0 0\">Giorni analizzati: " + IntegerToString(g_DaysScanned) +
     ". Se una fascia oraria concentra gli estremi molto sopra il 4.2% teorico (1/24), li' si trovano ");
   W("i punti di inversione: e' la finestra naturale per un mean-reversion, e la peggiore per entrare in breakout.</p></div>");
}

//+------------------------------------------------------------------+
void HtmlBreakout()
{
   W("<h2>📐 Rottura del range " + StringFormat("%02d:00–%02d:00", InpRangeStartHour, InpRangeEndHour) + "</h2><div class=\"card\">");
   int tot = g_BrkUpFirst + g_BrkDnFirst + g_BrkNone;
   if(tot < 20) { W("<p class=\"dim\">Campione insufficiente (" + IntegerToString(tot) + " giorni).</p></div>"); return; }

   double p_up = 100.0 * g_BrkUpFirst / tot;
   double p_dn = 100.0 * g_BrkDnFirst / tot;
   double p_no = 100.0 * g_BrkNone / tot;
   double cont_up = (g_BrkUpFirst > 0) ? 100.0 * g_BrkUpCont / g_BrkUpFirst : 0.0;
   double cont_dn = (g_BrkDnFirst > 0) ? 100.0 * g_BrkDnCont / g_BrkDnFirst : 0.0;

   W("<div class=\"grid\">");
   W("<div class=\"kpi\"><div class=\"l\">Giorni validi</div><div class=\"v\">" + IntegerToString(tot) + "</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Ampiezza media range</div><div class=\"v\">" + F(g_RangeSizeBp.Mean() * BP, 1) + " bp</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Rompe prima al rialzo</div><div class=\"v\">" + F(p_up, 1) + "%</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Rompe prima al ribasso</div><div class=\"v\">" + F(p_dn, 1) + "%</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Nessuna rottura</div><div class=\"v\">" + F(p_no, 1) + "%</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Rialzo → chiude sopra</div><div class=\"v " + (cont_up >= 50 ? "pos" : "neg") + "\">" + F(cont_up, 1) + "%</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Ribasso → chiude sotto</div><div class=\"v " + (cont_dn >= 50 ? "pos" : "neg") + "\">" + F(cont_dn, 1) + "%</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Estensione media (× range)</div><div class=\"v\">" +
     F(0.5 * (g_BrkUpExt.Mean() + g_BrkDnExt.Mean()), 2) + "</div></div>");
   W("</div>");

   W("<p class=\"dim\" style=\"margin:12px 0 0\"><b>Come si legge.</b> La percentuale di continuazione e' il numero che decide ");
   W("se lo strumento e' da breakout o da fade su questo range. Sopra il 55% con campione ampio &rarr; breakout con stop ");
   W("dentro il range. Sotto il 45% &rarr; il range viene sistematicamente violato e poi rientrato: e' un setup di ");
   W("<i>false breakout</i>, si vende la rottura al rialzo e si compra quella al ribasso. Fra 45% e 55% non c'e' edge ");
   W("direzionale: resta solo l'estensione media come target di un eventuale scalping.</p>");
   W("<p class=\"dim\">Nota metodologica: i giorni in cui una singola barra oraria rompe entrambi i lati sono esclusi, ");
   W("perche' su barre H1 non e' determinabile quale lato sia stato toccato per primo. Per una misura esatta serve un ");
   W("ricalcolo su M1.</p></div>");
}

//+------------------------------------------------------------------+
//| Ampiezza media della giornata per giorno della settimana.         |
//| Serve a dimensionare stop e target in modo coerente al giorno:    |
//| usare lo stesso stop fisso il lunedi' e il giovedi' significa     |
//| rischiare due multipli di volatilita' diversi.                    |
//+------------------------------------------------------------------+
void HtmlDowRange()
{
   W("<h2>📏 Ampiezza della giornata per giorno della settimana</h2><div class=\"card\">");
   double maxr = 0.0;
   for(int d = 1; d <= 5; d++) if(g_DowRange[d].N() > 0) maxr = MathMax(maxr, g_DowRange[d].Mean() * BP);
   if(maxr < EPS) { W("<p class=\"dim\">Dati insufficienti.</p></div>"); return; }

   W("<table><thead><tr><th>Giorno</th><th>n</th><th>Range medio (bp)</th><th></th>");
   W("<th>Range mediano (bp)</th><th>vs media settimana</th></tr></thead><tbody>");

   double wk = 0.0; int wn = 0;
   for(int d = 1; d <= 5; d++) if(g_DowRange[d].N() > 0) { wk += g_DowRange[d].Mean() * BP; wn++; }
   if(wn > 0) wk /= wn;

   for(int d = 1; d <= 5; d++) {
      int n = g_DowRange[d].N();
      if(n == 0) continue;
      double r = g_DowRange[d].Mean() * BP;
      double rel = (wk > EPS) ? 100.0 * (r / wk - 1.0) : 0.0;
      W("<tr><td>" + DowName(d) + "</td><td class=\"dim\">" + IntegerToString(n) + "</td>");
      W("<td>" + F(r, 1) + "</td>");
      W("<td><div class=\"barwrap\" style=\"width:120px\"><span class=\"bar\" style=\"width:" +
        F(100.0 * r / maxr, 1) + "%;background:var(--acc)\"></span></div></td>");
      W("<td class=\"dim\">" + F(g_DowRange[d].Median() * BP, 1) + "</td>");
      W(SignedCell(rel, 1, "%"));
      W("</tr>");
   }
   W("</tbody></table>");
   W("<p class=\"dim\" style=\"margin:10px 0 0\">Il range e' misurato come <code>ln(high/low)</code> della giornata. ");
   W("Un giorno con range sistematicamente sotto media e' un giorno da mean-reversion e da stop stretti; ");
   W("uno sopra media e' il candidato naturale per i breakout e richiede stop proporzionalmente piu' larghi.</p></div>");
}

//+------------------------------------------------------------------+
void HtmlWeekGap()
{
   W("<h2>🌅 Gap di apertura settimanale</h2><div class=\"card\">");
   if(g_GapTotal < 20) { W("<p class=\"dim\">Campione insufficiente (" + IntegerToString(g_GapTotal) + " settimane).</p></div>"); return; }
   W("<div class=\"grid\">");
   W("<div class=\"kpi\"><div class=\"l\">Settimane</div><div class=\"v\">" + IntegerToString(g_GapTotal) + "</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Gap medio</div><div class=\"v\">" + F(g_WeekGap.Mean() * BP, 2) + " bp</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Gap medio assoluto</div><div class=\"v\">" + F(g_WeekGap.MeanAbs() * BP, 2) + " bp</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Colmato in giornata</div><div class=\"v " +
     (100.0 * g_GapFilled / g_GapTotal >= 60 ? "pos" : "dim") + "\">" + F(100.0 * g_GapFilled / g_GapTotal, 1) + "%</div></div>");
   W("</div>");
   W("<p class=\"dim\" style=\"margin:12px 0 0\">Una percentuale di riempimento alta con gap medio assoluto ben sopra ");
   W("lo spread e' una delle poche inefficienze meccaniche residue: si entra contro il gap all'apertura con target la ");
   W("chiusura di venerdi'. Attenzione: lo spread del lunedi' in apertura e' tipicamente 3-10 volte quello normale, ");
   W("va misurato prima di quantificare l'edge netto.</p></div>");
}

//+------------------------------------------------------------------+
void HtmlTurnOfMonth()
{
   W("<h2>📆 Effetto cambio mese (turn of month)</h2><div class=\"card\">");
   int ni = g_TomIn.N(), no = g_TomOut.N();
   if(ni < InpMinSample || no < InpMinSample) { W("<p class=\"dim\">Campione insufficiente.</p></div>"); return; }

   double mi = g_TomIn.Mean() * BP, mo = g_TomOut.Mean() * BP;
   // t-test a due campioni, varianze separate (Welch)
   double si = g_TomIn.SD() * BP, so = g_TomOut.SD() * BP;
   double se = MathSqrt(si * si / ni + so * so / no);
   double tw = (se > EPS) ? (mi - mo) / se : 0.0;

   W("<div class=\"grid\">");
   W("<div class=\"kpi\"><div class=\"l\">Finestra TOM (ultimi 2 + primi 3 gg)</div><div class=\"v " +
     (mi >= 0 ? "pos" : "neg") + "\">" + F(mi, 2) + " bp/gg</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Resto del mese</div><div class=\"v " +
     (mo >= 0 ? "pos" : "neg") + "\">" + F(mo, 2) + " bp/gg</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Differenza</div><div class=\"v\">" + F(mi - mo, 2) + " bp/gg</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">t di Welch</div><div class=\"v " +
     (MathAbs(tw) >= 1.96 ? "pos" : "dim") + "\">" + F(tw, 2) + "</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">n dentro / fuori</div><div class=\"v\">" +
     IntegerToString(ni) + " / " + IntegerToString(no) + "</div></div>");
   W("</div>");
   W("<p class=\"dim\" style=\"margin:12px 0 0\">L'effetto cambio mese e' documentato soprattutto sugli indici azionari ");
   W("(ribilanciamento dei fondi e flussi pensionistici). Su forex e materie prime e' tipicamente assente: se qui esce ");
   W("significativo su una coppia FX, sospetta un artefatto del campione prima di costruirci sopra.</p></div>");
}

//+------------------------------------------------------------------+
void HtmlYears()
{
   int n = ArraySize(g_Years);
   if(n == 0) return;
   W("<h2>📉 Rendimento per anno solare — controllo di regime</h2><div class=\"card\"><table><thead><tr>");
   for(int i = 0; i < n; i++) W("<th>" + IntegerToString(g_Years[i]) + "</th>");
   W("</tr></thead><tbody><tr>");
   for(int i = 0; i < n; i++) W(SignedCell(g_YearRet[i], 1, "%"));
   W("</tr></tbody></table>");
   W("<p class=\"dim\" style=\"margin:10px 0 0\">Se il segno cambia spesso, lo strumento non ha un drift strutturale: ");
   W("qualunque stagionalita' direzionale trovata sopra va tradata in entrambi i versi, mai solo long.</p></div>");
}

//+------------------------------------------------------------------+
void BuildHtml(string path_label)
{
   HtmlHead("Stagionalita' " + g_Sym);

   W("<h1>Analisi di stagionalita' — " + g_Sym + "</h1>");
   W("<div class=\"sub\">Storico dal " + TimeToString(g_D1[0].time, TIME_DATE) + " al " +
     TimeToString(g_D1[g_nD1-1].time, TIME_DATE) + " &nbsp;·&nbsp; " +
     IntegerToString(g_nD1) + " giorni, " + IntegerToString(g_nH1) + " barre H1 &nbsp;·&nbsp; " +
     "orari in ora del server &nbsp;·&nbsp; generato il " + TimeToString(TimeCurrent()) + "</div>");

   W("<div class=\"grid\">");
   W("<div class=\"kpi\"><div class=\"l\">Costo round-turn stimato</div><div class=\"v\">" + F(g_CostBp, 2) + " bp</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Confine IS / OOS</div><div class=\"v\">" +
     (InpSplitIS_OOS ? TimeToString(g_SplitTime, TIME_DATE) : "disattivato") + "</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">n minimo per leggere una cella</div><div class=\"v\">" + IntegerToString(InpMinSample) + "</div></div>");
   W("<div class=\"kpi\"><div class=\"l\">Volatilita' giornaliera media</div><div class=\"v\">" +
     F(g_Dow[1].MeanAbs() * BP, 0) + "–" + F(g_Dow[3].MeanAbs() * BP, 0) + " bp</div></div>");
   W("</div>");

   HtmlVerdict();

   //--- ora del giorno
   string hl[24];
   for(int h = 0; h < 24; h++) hl[h] = StringFormat("%02d:00", h);
   StatTable("🕐 Comportamento per ora del giorno", "Ora (server)", hl, g_Hour, g_HourIS, g_HourOOS,
             0, 23, 24, InpSplitIS_OOS, "Tick vol medio", 1.0);

   HtmlHeatmap();
   HtmlExtremeHours();
   HtmlBreakout();

   //--- giorno della settimana
   string dl[7];
   for(int d = 0; d < 7; d++) dl[d] = DowName(d);
   StatTable("📅 Comportamento per giorno della settimana", "Giorno", dl, g_Dow, g_DowIS, g_DowOOS,
             1, 5, 5, InpSplitIS_OOS);

   HtmlDowRange();
   HtmlWeekGap();

   //--- giorno di trading del mese
   string tl[MAX_TDOM_S+1];
   for(int k = 1; k <= MAX_TDOM_S; k++) tl[k] = StringFormat("%d° giorno di trading", k);
   SAcc dummy1[MAX_TDOM_S+1], dummy2[MAX_TDOM_S+1];
   StatTable("📈 Primi giorni di trading del mese", "Posizione", tl, g_TdomS, dummy1, dummy2,
             1, MAX_TDOM_S, MAX_TDOM_S + MAX_TDOM_E, false);

   string el[MAX_TDOM_E+1];
   for(int k = 1; k <= MAX_TDOM_E; k++) el[k] = StringFormat("%d° giorno dalla fine", k);
   SAcc dummy3[MAX_TDOM_E+1], dummy4[MAX_TDOM_E+1];
   StatTable("📉 Ultimi giorni di trading del mese", "Posizione", el, g_TdomE, dummy3, dummy4,
             1, MAX_TDOM_E, MAX_TDOM_S + MAX_TDOM_E, false);

   HtmlTurnOfMonth();

   //--- mese dell'anno
   string ml[13];
   for(int m = 0; m <= 12; m++) ml[m] = MonName(m);
   StatTable("🗓 Comportamento per mese dell'anno", "Mese", ml, g_Mon, g_MonIS, g_MonOOS,
             1, 12, 12, InpSplitIS_OOS);

   HtmlYears();

   //--- metodologia
   W("<h2>📖 Metodologia e limiti</h2><div class=\"card\">");
   W("<p><b>Rendimenti.</b> Log-return <code>ln(close_t / close_t-1)</code>, espressi in basis point ");
   W("(1 bp = 0.01%). I log-return sono additivi nel tempo, quindi le medie orarie sono confrontabili e sommabili; ");
   W("le variazioni percentuali semplici non lo sarebbero.</p>");
   W("<p><b>Buchi nella serie.</b> Le barre orarie precedute da un salto temporale superiore a 2 ore ");
   W("(weekend, festivi, sospensioni) sono escluse dalle statistiche orarie: altrimenti il rendimento del weekend ");
   W("verrebbe attribuito all'ora di riapertura, gonfiando artificialmente quel bucket.</p>");
   W("<p><b>t-stat e p-value.</b> Il t assume osservazioni indipendenti e identicamente distribuite. I rendimenti ");
   W("finanziari violano entrambe le ipotesi (autocorrelazione della volatilita', code grasse), quindi i t-stat qui ");
   W("riportati sono <i>ottimistici</i>: vanno letti come ordinamento relativo, non come probabilita' esatte.</p>");
   W("<p><b>Test multipli.</b> Testare 24 ore al 5% produce in media 1.2 falsi positivi anche su una serie ");
   W("completamente casuale. La soglia di Bonferroni mostrata in ogni tabella e' la correzione minima; e' conservativa ");
   W("ma e' esattamente il tipo di conservatorismo che evita di costruire una strategia su rumore.</p>");
   W("<p><b>IS / OOS.</b> Lo storico e' diviso a meta' in ordine cronologico. Un effetto reale sopravvive in entrambe ");
   W("le meta' con lo stesso segno. Un effetto presente solo nella prima meta' e' quasi sempre data mining.</p>");
   W("<p><b>Costi.</b> L'edge netto sottrae uno spread round-turn stimato. Non include lo slippage, ");
   W("l'allargamento dello spread in apertura e sulle news, ne' lo swap: su strategie che tengono posizioni ");
   W("overnight lo swap puo' da solo annullare una stagionalita' giornaliera.</p>");
   W("<p><b>Ora del server.</b> Tutti gli orari sono nell'ora del server del broker, che per FP Markets segue ");
   W("il DST europeo (UTC+2 / UTC+3). Un bucket orario quindi <i>si sposta</i> rispetto all'ora di New York due volte ");
   W("l'anno per le settimane in cui il DST americano ed europeo non coincidono. Per un'analisi rigorosa delle sessioni ");
   W("US conviene ripetere il calcolo con gli orari convertiti in UTC.</p>");
   W("</div>");

   W("<footer>Report generato da SeasonalityScanner v1.0 su " + g_Sym +
     ". Nessuna delle statistiche qui riportate e' una raccomandazione operativa: sono ipotesi da falsificare con un backtest completo di costi.</footer>");
   W("</div></body></html>");
}

//+------------------------------------------------------------------+
//| Riassunto testuale nel tab Esperti                                |
//+------------------------------------------------------------------+
void PrintSummary()
{
   Print("══════════════════════════════════════════════════════");
   PrintFormat("SEASONALITY SCANNER — %s | %d giorni, %d barre H1", g_Sym, g_nD1, g_nH1);
   PrintFormat("Costo round-turn stimato: %.2f bp", g_CostBp);
   Print("── Top effetti per |t-stat| (solo n >= soglia) ──");
   int shown = 0;
   for(int i = 0; i < g_FindCount && shown < 10; i++) {
      if(g_Find[i].n < InpMinSample) continue;
      shown++;
      PrintFormat("%-18s %-26s n=%4d  media=%+7.2f bp  t=%+5.2f (soglia %.2f)  %s",
                  g_Find[i].family, g_Find[i].bucket, g_Find[i].n, g_Find[i].mean_bp,
                  g_Find[i].t, g_Find[i].bonf_t,
                  IsExploitable(g_Find[i]) ? "SFRUTTABILE" : "non conclusivo");
   }
   Print("══════════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| ENTRY POINT                                                       |
//+------------------------------------------------------------------+
void OnStart()
{
   g_Sym    = _Symbol;
   g_Point  = SymbolInfoDouble(g_Sym, SYMBOL_POINT);
   g_Digits = (int)SymbolInfoInteger(g_Sym, SYMBOL_DIGITS);

   if(InpYearsBack < 1) { Print("❌ InpYearsBack deve essere >= 1"); return; }
   if(InpRangeEndHour <= InpRangeStartHour || InpRangeEndHour > 24) {
      Print("❌ Finestra di range non valida: InpRangeEndHour deve essere > InpRangeStartHour e <= 24"); return;
   }

   datetime to   = TimeCurrent();
   datetime from = to - (datetime)((double)InpYearsBack * 365.25 * 86400.0);

   Print("⏳ Caricamento storico ", g_Sym, " — attendere la sincronizzazione...");
   g_nH1 = LoadRates(PERIOD_H1, g_H1, from, to);
   g_nD1 = LoadRates(PERIOD_D1, g_D1, from, to);

   if(g_nH1 < 500 || g_nD1 < 100) {
      PrintFormat("❌ Storico insufficiente (H1=%d, D1=%d). Apri il grafico H1 e D1 del simbolo, scorri indietro per forzare il download, poi rilancia.", g_nH1, g_nD1);
      return;
   }

   //--- costo di transazione in basis point
   double spread_pts = (InpSpreadPoints > 0.0) ? InpSpreadPoints : (double)SymbolInfoInteger(g_Sym, SYMBOL_SPREAD);
   double price = g_D1[g_nD1-1].close;
   if(price < EPS) price = 1.0;
   g_CostBp = ((spread_pts + InpCommissionRT_Points) * g_Point / price) * BP;

   //--- confine in-sample / out-of-sample
   g_SplitTime = InpSplitIS_OOS ? (g_D1[0].time + (g_D1[g_nD1-1].time - g_D1[0].time) / 2)
                                : g_D1[g_nD1-1].time + 1;

   for(int h = 0; h < 24; h++) { g_Hour[h].Reset(); g_HourIS[h].Reset(); g_HourOOS[h].Reset(); }
   for(int d = 0; d < 7;  d++) { g_Dow[d].Reset();  g_DowIS[d].Reset();  g_DowOOS[d].Reset(); g_DowRange[d].Reset();
                                 for(int h = 0; h < 24; h++) g_Heat[d][h].Reset(); }
   for(int m = 0; m <= 12; m++) { g_Mon[m].Reset(); g_MonIS[m].Reset(); g_MonOOS[m].Reset(); }
   for(int k = 0; k <= MAX_TDOM_S; k++) g_TdomS[k].Reset();
   for(int k = 0; k <= MAX_TDOM_E; k++) g_TdomE[k].Reset();
   g_TomIn.Reset(); g_TomOut.Reset(); g_BrkUpExt.Reset(); g_BrkDnExt.Reset();
   g_RangeSizeBp.Reset(); g_WeekGap.Reset();

   BuildIntraday();
   BuildDailyAndAbove();
   BuildDayStructure();
   CollectFindings();

   //--- output
   string fname = InpOutputFile;
   if(fname == "") {
      MqlDateTime now; TimeToStruct(TimeCurrent(), now);
      fname = StringFormat("Seasonality_%s_%04d%02d%02d", g_Sym, now.year, now.mon, now.day);
   }
   // garantisce l'estensione .html senza manipolare i punti gia' presenti nel nome
   int flen = StringLen(fname);
   if(flen < 5 || StringSubstr(fname, flen - 5) != ".html") fname = fname + ".html";

   int flags = FILE_WRITE | FILE_BIN;
   if(InpUseCommonFolder) flags |= FILE_COMMON;

   g_H = FileOpen(fname, flags);
   if(g_H == INVALID_HANDLE) { Print("❌ Impossibile creare il file: ", fname, " (err ", GetLastError(), ")"); return; }

   BuildHtml(fname);
   FileClose(g_H);
   g_H = INVALID_HANDLE;

   string folder = InpUseCommonFolder ? TerminalInfoString(TERMINAL_COMMONDATA_PATH) : TerminalInfoString(TERMINAL_DATA_PATH);
   Print("✅ Report generato: ", folder, "\\MQL5\\Files\\", fname);
   Print("   (MetaTrader non ha un browser interno: apri il file con doppio click da Esplora Risorse,");
   Print("    oppure dal terminale con File > Apri cartella dati.)");

   if(InpVerboseLog) PrintSummary();
}
//+------------------------------------------------------------------+
