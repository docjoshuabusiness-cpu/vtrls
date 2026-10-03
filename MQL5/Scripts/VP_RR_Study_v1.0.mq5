//+------------------------------------------------------------------+
//|  VP_RR_Study_v1.0.mq5                                            |
//|  SCRIPT di studio statistico per VolumeProfile_v1.0_EA            |
//|  (si trascina su un grafico, gira UNA volta sulla storia e         |
//|  termina; non apre ordini).                                       |
//|                                                                    |
//|  Cosa fa                                                           |
//|  1. Ricostruisce sulla storia i segnali TECNICI dell'EA: profilo   |
//|     volumi sviluppato barra per barra (sessioni FP Markets con     |
//|     auto-DST, o Daily/Weekly/Monthly), tocco VAL/VAH, POC strict,  |
//|     filtro Hull, tocchi minimi, candela di rigetto. Il filtro ML   |
//|     NON e' incluso di proposito: i suoi pesi sono addestrati sugli |
//|     stessi esiti che qui vogliamo misurare (circolarita').         |
//|  2. Misura come si comporta il prezzo DOPO ogni segnale: curva di  |
//|     rendimento medio per orizzonte, MFE/MAE, probabilita' di       |
//|     raggiungere prima +X ATR o -X ATR, tocco di POC e bordo        |
//|     opposto della Value Area (lordo di costi).                     |
//|  3. Griglie SL x RR (1:1, 1:2 ... 1:N) in PUNTI FISSI e in ATR,    |
//|     e griglie di TRAILING (attivazione x distanza) in punti e ATR. |
//|     Netto di spread e commissioni.                                 |
//|  4. Per non farsi ingannare dal data-mining: split cronologico     |
//|     IN-SAMPLE / OUT-OF-SAMPLE, la cella migliore si sceglie solo   |
//|     sull'IS (opzionale media dei vicini) e si giudica sull'OOS;    |
//|     t-stat, correzione di Bonferroni, correlazione di Spearman     |
//|     IS-OOS tra le celle, stabilita' annuale, curve di equity.      |
//|  Output: report HTML + CSV in MQL5/Files, riepilogo nel log.       |
//|                                                                    |
//|  Simulazione: ingresso a mercato all'apertura della barra          |
//|  successiva al segnale (come l'EA), SL/TP/trailing valutati su     |
//|  barre del TF di simulazione (default M1, con ripiego automatico   |
//|  al TF del grafico se la storia M1 non basta).                     |
//+------------------------------------------------------------------+
#property copyright "Advanced Quant Systems - VP RR Study v1.0"
#property version   "1.00"
#property strict
#property script_show_inputs

//=== PROFILE (identico all'EA) ===
input group "=== PROFILO / SEGNALE (stessi valori dell'EA) ==="
enum ENUM_PROFILE_MODE { MODE_DAILY, MODE_WEEKLY, MODE_MONTHLY, MODE_SESSIONS };
input ENUM_PROFILE_MODE InpProfileMode = MODE_SESSIONS;  // Daily/Weekly/Monthly/Sessions
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT;     // TF per costruire il profilo (non oltre il TF del grafico)
input int    InpPriceLevels = 100;
input int    InpHistoryPeriods = 20;
input double InpValueAreaPercent = 70.0;
input bool   InpUseRealVolume = true;
input bool   InpAutoDST = true;
input string InpSydneyStart  = "00:00";
input string InpSydneyEnd    = "09:00";
input string InpAsianStart   = "02:00";
input string InpAsianEnd     = "11:00";
input string InpLondonStart  = "10:00";
input string InpLondonEnd    = "19:00";
input string InpNewYorkStart = "15:00";
input string InpNewYorkEnd   = "00:00";
input bool   InpStrictMode = true;
input double InpVADistance = 15.0;
input int    InpMinTouchBars = 3;
input bool   InpRequireRejection = true;
input double InpMinWickRatio = 0.3;
input bool   InpOneSignalPerSession = true;  // 1 evento long + 1 short per sessione/profilo (riduce la dipendenza tra eventi)
input bool   InpUseHullFilter = true;
input int    InpHullPeriod = 20;
input bool   InpAutoAdaptDistance = true;
input int    InpATRPeriod = 14;              // periodo ATR (stesso dell'EA)
input bool   InpIncludeOpenTick = true;      // Replica l'EA: il profilo include la barra appena aperta (solo tick di apertura, volume 1)

//=== STUDIO ===
input group "=== STUDIO ==="
input int    InpMonthsBack = 24;                    // Mesi di storia da analizzare (0 = tutta quella disponibile)
input ENUM_TIMEFRAMES InpSimTF = PERIOD_M1;         // TF per simulare SL/TP/trailing (se la storia non copre >=60% usa il TF del grafico)
input int    InpMaxHoldBars = 100;                  // Orizzonte massimo in BARRE DEL GRAFICO; poi uscita a mercato (l'EA non ha time-stop)
input int    InpISPercent = 70;                     // % di eventi (cronologici) usati come In-Sample; il resto e' Out-Of-Sample
enum ENUM_RANK_BY { RANK_TSTAT, RANK_EXPECTANCY, RANK_PF };
input ENUM_RANK_BY InpRankBy = RANK_TSTAT;          // Metrica per scegliere la cella migliore (sull'IS)
input bool   InpSmoothRank = true;                  // Punteggio = media della cella e dei vicini 3x3 (penalizza i picchi isolati)
input int    InpMinTrades = 30;                     // Minimo trade IS per candidare una cella
input bool   InpOptimistic = false;                 // Ordine intrabarra OTTIMISTA (TP prima di SL). Default: pessimista

//=== COSTI ===
input group "=== COSTI ==="
input int    InpSpreadPoints = -1;                  // Spread in punti (-1 = usa lo spread registrato nella barra di ingresso)
input double InpCommissionPoints = 0.0;             // Commissione round-turn convertita in punti (es. Raw: ~7 punti su EURUSD a 5 cifre)

//=== GRIGLIA RR ===
input group "=== GRIGLIA SL x RR ==="
input string InpSLMultList = "0.5,0.75,1,1.25,1.5,2,2.5,3";  // SL in multipli di ATR (max 16 valori)
input string InpSLPointsList = "";                  // SL in punti separati da virgola; vuoto = automatico (multipli x ATR mediano)
input double InpRRMin = 1.0;                        // RR minimo (TP = RR x SL)
input double InpRRMax = 8.0;                        // RR massimo
input double InpRRStep = 1.0;                       // passo RR

//=== GRIGLIA TRAILING ===
input group "=== GRIGLIA TRAILING ==="
input double InpTrailSLATR = 1.0;                   // SL iniziale del trailing in ATR (modalita' ATR)
input int    InpTrailSLPoints = 0;                  // SL iniziale in punti (0 = ATR mediano x InpTrailSLATR)
input string InpTrailActList = "0.5,1,1.5,2,3";     // Attivazione in multipli di ATR
input string InpTrailDistList = "0.5,0.75,1,1.5,2"; // Distanza trailing in multipli di ATR
input string InpTrailActPoints = "";                // Attivazione in punti; vuoto = automatico (multipli x ATR mediano)
input string InpTrailDistPoints = "";               // Distanza in punti; vuoto = automatico
input double InpTrailStepRatio = 0.15;              // Step minimo di aggiornamento = ratio x distanza (EA: ~0.17)
input double InpTrailTPRR = 0.0;                    // TP in multipli dell'SL durante il trailing (0 = nessun TP)

//=== RIFERIMENTO ===
input group "=== CONFIGURAZIONE DI RIFERIMENTO (tabelle per range) ==="
input double InpRefSLATR = 1.0;                     // SL di riferimento in ATR (EA default 1.0)
input double InpRefRR = 2.0;                        // RR di riferimento (EA default: TP 2 ATR => 1:2)

//=== OUTPUT ===
input group "=== OUTPUT ==="
input bool   InpWriteHTML = true;
input bool   InpWriteCSV = true;
input string InpFilePrefix = "VP_RR_Study";

//--- Costanti
#define EPSILON  0.0000001
#define MIN_BARS_REQUIRED 100   // come l'EA: sotto questa soglia di barre non valuta segnali
#define MAXDIM   16
#define MAXFAM   5
#define NHOR     8
#define NFP      5
#define NSESS    5      // 4 sessioni + "altro" (Daily/Weekly/Monthly)

const double g_fpX[NFP] = {0.5, 1.0, 1.5, 2.0, 3.0};   // soglie first-passage in ATR
const int    g_horAll[NHOR] = {1, 2, 3, 5, 10, 20, 50, 100};

//--- Strutture
struct SProfile
{
   datetime start;
   datetime end;
   double   high;
   double   low;
   double   poc;
   double   vah;
   double   val;
   double   totvol;
   int      sess;
};

struct SEvent
{
   datetime time;       // apertura della barra segnale (TF grafico)
   int      dir;        // +1 long, -1 short
   int      sess;       // 0 Sydney 1 Asian 2 London 3 NY 4 altro
   datetime pstart;
   int      k;          // indice barra segnale (TF grafico)
   int      e0;         // indice barra di ingresso (TF simulazione)
   double   entry;      // prezzo bid di apertura della barra di ingresso
   double   atr;
   double   spread;     // in prezzo
   double   poc, vah, val;
   double   vaw_atr;    // ampiezza Value Area in ATR
   double   hrs;        // ore dall'inizio del profilo
   double   dist_atr;   // distanza dal livello (VAL/VAH) in ATR
   int      touches;
   double   rej;
   double   mfe, mae;   // in ATR (lordi), massima escursione favorevole/avversa sull'orizzonte
   int      bpoc, bopp; // barre (TF grafico) al primo tocco di POC / bordo opposto, -1 = mai
   double   dpoc, dopp; // distanza in ATR da POC / bordo opposto
   int      fp[NFP];    // first-passage: +1 TP prima, -1 SL prima, 0 nessuno
   double   ret[NHOR];  // rendimento direzionale in ATR a fine orizzonte h
   int      bw, bh;     // bucket ampiezza VA / maturita'
};

struct SCfg
{
   int    fam;     // 0 fisso punti, 1 fisso ATR, 2 trailing punti, 3 trailing ATR, 4 riferimento
   int    row, col;
   bool   atr;     // true: i parametri sono multipli di ATR; false: distanze in prezzo
   double sl;      // SL (prezzo o multiplo ATR)
   double rr;      // fisso: RR; trailing: RR del TP (0 = nessun TP)
   double act;     // trailing: attivazione
   double dist;    // trailing: distanza
};

struct SStat
{
   int    n;
   int    wins;
   int    tmo;     // uscite a fine orizzonte
   int    amb;     // esiti dipendenti dall'ordine intrabarra
   double sum, sum2;
   double gp, gl;
   double eq, peak, dd;
};

//--- Dati
MqlRates g_rc[];           // TF grafico
MqlRates g_rs[];           // TF simulazione
MqlRates g_rp[];           // TF profilo (solo se diverso dal TF grafico)
datetime g_pt[];           // aperture dei periodi D1/W1/MN1 (solo modalita' non-sessioni)
double   g_atr[];
double   g_hull[];
double   g_node[];
double   g_pseudoPrice = 0.0;   // prezzo di apertura della barra successiva al segnale (tick di apertura visto dall'EA)
ENUM_TIMEFRAMES g_chartTF, g_simTF, g_profTF;
bool     g_profSame = true;
bool     g_simSame = true;
bool     g_useReal = false;
int      g_perChart = 0, g_perSim = 0, g_ratio = 1, g_L = 0;
double   g_point = 0.0;
int      g_ssH[4], g_ssM[4], g_seH[4], g_seM[4];

//--- Eventi
SEvent   g_ev[];
datetime g_sessKey[];
uchar    g_sessFlag[];
int      g_dropData = 0;       // eventi scartati per mancanza di dati di simulazione
int      g_candidates = 0;
int      g_nH = 0;
int      g_hor[NHOR];
double   g_wEdge[4];
double   g_hEdge[2];
double   g_medATRpts = 0.0;
int      g_split = 0;

//--- Configurazioni e risultati
SCfg     g_cfg[];
int      g_dimR[MAXFAM], g_dimC[MAXFAM], g_base[MAXFAM];
string   g_rowLbl[MAXFAM][MAXDIM];
string   g_colLbl[MAXFAM][MAXDIM];
float    g_R[];
uchar    g_F[];
SStat    g_stIS[], g_stOOS[], g_stAll[];
double   g_score[];
bool     g_valid[];
int      g_best[MAXFAM];
int      g_refIdx = -1;

//--- Buffer di percorso (per evento)
double   g_wO[], g_wF[], g_wA[], g_wC[];

//--- Output
int      g_fh = INVALID_HANDLE;
string   g_warn[];
datetime g_dataFirst = 0, g_dataLast = 0;

//+------------------------------------------------------------------+
//| Utility                                                            |
//+------------------------------------------------------------------+
void Warn(const string msg)
{
   int n = ArraySize(g_warn);
   ArrayResize(g_warn, n + 1);
   g_warn[n] = msg;
   Print("ATTENZIONE: ", msg);
}

int ParseList(const string s, double &out[])
{
   ArrayResize(out, 0);
   string parts[];
   int n = StringSplit(s, ',', parts);
   for(int i = 0; i < n; i++)
   {
      if(ArraySize(out) >= MAXDIM) break;
      string t = parts[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      if(StringLen(t) == 0) continue;
      double v = StringToDouble(t);
      if(v <= 0.0) continue;
      int sz = ArraySize(out);
      ArrayResize(out, sz + 1);
      out[sz] = v;
   }
   return ArraySize(out);
}

bool ParseHM(const string s, int &h, int &m)
{
   string p[];
   if(StringSplit(s, ':', p) != 2) return false;
   h = (int)StringToInteger(p[0]);
   m = (int)StringToInteger(p[1]);
   return (h >= 0 && h <= 24 && m >= 0 && m < 60);
}

// Complemento della funzione errore (Numerical Recipes, errore relativo < 1.2e-7)
double ErfcApprox(const double x)
{
   double z = MathAbs(x);
   double t = 1.0 / (1.0 + 0.5 * z);
   double ans = t * MathExp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 +
                t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 +
                t * (-0.82215223 + t * 0.17087277)))))))));
   return (x >= 0.0) ? ans : 2.0 - ans;
}

// P(Z > z) per Z normale standard
double NormUpper(const double z)
{
   return 0.5 * ErfcApprox(z / MathSqrt(2.0));
}

// z tale che P(Z > z) = p (bisezione)
double NormInvUpper(const double p)
{
   double lo = -10.0, hi = 10.0;
   for(int i = 0; i < 80; i++)
   {
      double mid = 0.5 * (lo + hi);
      if(NormUpper(mid) > p) lo = mid; else hi = mid;
   }
   return 0.5 * (lo + hi);
}

double Quantile(const double &sorted[], const int n, const double p)
{
   if(n <= 0) return 0.0;
   if(n == 1) return sorted[0];
   double pos = p * (n - 1);
   int i0 = (int)MathFloor(pos);
   int i1 = MathMin(i0 + 1, n - 1);
   double fr = pos - i0;
   return sorted[i0] * (1.0 - fr) + sorted[i1] * fr;
}

// rango medio (gestisce i pari merito); n piccolo => O(n^2) accettabile
void RankArray(const double &v[], const int n, double &rk[])
{
   ArrayResize(rk, n);
   for(int i = 0; i < n; i++)
   {
      int less = 0, eq = 0;
      for(int j = 0; j < n; j++)
      {
         if(v[j] < v[i]) less++;
         else if(v[j] == v[i]) eq++;
      }
      rk[i] = less + 0.5 * (eq + 1.0);
   }
}

double Spearman(const double &a[], const double &b[], const int n)
{
   if(n < 4) return 0.0;
   double ra[], rb[];
   RankArray(a, n, ra);
   RankArray(b, n, rb);
   double ma = 0, mb = 0;
   for(int i = 0; i < n; i++) { ma += ra[i]; mb += rb[i]; }
   ma /= n; mb /= n;
   double sab = 0, saa = 0, sbb = 0;
   for(int i = 0; i < n; i++)
   {
      sab += (ra[i] - ma) * (rb[i] - mb);
      saa += (ra[i] - ma) * (ra[i] - ma);
      sbb += (rb[i] - mb) * (rb[i] - mb);
   }
   if(saa < EPSILON || sbb < EPSILON) return 0.0;
   return sab / MathSqrt(saa * sbb);
}

string F(const double v, const int d)
{
   return DoubleToString(v, d);
}

string Pick(const bool c, const string a, const string b)
{
   if(c) return a;
   return b;
}

//+------------------------------------------------------------------+
//| DST (identico all'EA)                                              |
//+------------------------------------------------------------------+
datetime LastSundayOfMonth(int year, int month)
{
   MqlDateTime dt;
   ZeroMemory(dt);
   dt.year = year; dt.mon = month; dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;

   int days_in_month;
   if(month == 12) days_in_month = 31;
   else
   {
      MqlDateTime next;
      ZeroMemory(next);
      next.year = year; next.mon = month + 1; next.day = 1;
      datetime next_month = StructToTime(next);
      days_in_month = (int)((next_month - StructToTime(dt)) / 86400);
   }

   dt.day = days_in_month;
   datetime last_day = StructToTime(dt);
   TimeToStruct(last_day, dt);
   int offset = dt.day_of_week;
   return last_day - (offset * 86400);
}

bool IsEEST_DST(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   datetime dst_start = LastSundayOfMonth(dt.year, 3);
   datetime dst_end   = LastSundayOfMonth(dt.year, 10);
   return (t >= dst_start && t < dst_end);
}

//+------------------------------------------------------------------+
//| Ricerca binaria sui tempi                                          |
//+------------------------------------------------------------------+
// indice dell'ultima barra con time <= t (come iBarShift exact=false), -1 se t precede la prima
int BarAtOrBefore(const MqlRates &r[], const datetime t)
{
   int lo = 0, hi = ArraySize(r) - 1, ans = -1;
   while(lo <= hi)
   {
      int mid = (lo + hi) / 2;
      if(r[mid].time <= t) { ans = mid; lo = mid + 1; }
      else hi = mid - 1;
   }
   return ans;
}

// primo indice con time >= t (n se nessuno)
int LowerBound(const MqlRates &r[], const datetime t)
{
   int lo = 0, hi = ArraySize(r);
   while(lo < hi)
   {
      int mid = (lo + hi) / 2;
      if(r[mid].time < t) lo = mid + 1; else hi = mid;
   }
   return lo;
}

//+------------------------------------------------------------------+
//| Caricamento dati                                                   |
//+------------------------------------------------------------------+
bool LoadRates(ENUM_TIMEFRAMES tf, datetime from, datetime to, MqlRates &out[])
{
   int last = -1, stable = 0;
   uint t0 = GetTickCount();
   for(int attempt = 0; attempt < 80; attempt++)
   {
      if(IsStopped()) return false;
      ResetLastError();
      int got = CopyRates(_Symbol, tf, from, to, out);
      if(got > 0)
      {
         if(got == last) stable++; else stable = 0;
         last = got;
         if(stable >= 2 && (long)SeriesInfoInteger(_Symbol, tf, SERIES_SYNCHRONIZED) != 0) break;
      }
      Sleep(300);
      if(GetTickCount() - t0 > 45000) break;
   }
   ArraySetAsSeries(out, false);
   return (ArraySize(out) > 0);
}

bool LoadTimes(ENUM_TIMEFRAMES tf, datetime from, datetime to, datetime &out[])
{
   for(int attempt = 0; attempt < 20; attempt++)
   {
      int got = CopyTime(_Symbol, tf, from, to, out);
      if(got > 0) { ArraySetAsSeries(out, false); return true; }
      Sleep(300);
   }
   return false;
}

bool Setup()
{
   g_chartTF = (ENUM_TIMEFRAMES)_Period;
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_perChart = PeriodSeconds(g_chartTF);
   if(g_point <= 0.0 || g_perChart <= 0) { Print("Errore: point/periodo non validi"); return false; }

   g_simTF = (InpSimTF == PERIOD_CURRENT) ? g_chartTF : InpSimTF;
   if(PeriodSeconds(g_simTF) > g_perChart)
   {
      Warn("InpSimTF e' piu' grossolano del TF del grafico: uso il TF del grafico.");
      g_simTF = g_chartTF;
   }
   g_profTF = (InpTimeframe == PERIOD_CURRENT) ? g_chartTF : InpTimeframe;
   if(PeriodSeconds(g_profTF) > g_perChart)
   {
      Warn("InpTimeframe (profilo) e' piu' grossolano del TF del grafico: uso il TF del grafico (evita look-ahead).");
      g_profTF = g_chartTF;
   }
   g_profSame = (g_profTF == g_chartTF);

   string ss[4], se[4];
   ss[0] = InpSydneyStart; ss[1] = InpAsianStart; ss[2] = InpLondonStart; ss[3] = InpNewYorkStart;
   se[0] = InpSydneyEnd;   se[1] = InpAsianEnd;   se[2] = InpLondonEnd;   se[3] = InpNewYorkEnd;
   for(int i = 0; i < 4; i++)
   {
      if(!ParseHM(ss[i], g_ssH[i], g_ssM[i]) || !ParseHM(se[i], g_seH[i], g_seM[i]))
      {
         Print("Errore: orario di sessione non valido (usa HH:MM)");
         return false;
      }
   }

   if(InpPriceLevels < 10 || InpPriceLevels > 500) { Print("Errore: InpPriceLevels fuori range"); return false; }
   if(InpMaxHoldBars < 2) { Print("Errore: InpMaxHoldBars minimo 2"); return false; }
   if(InpISPercent < 10 || InpISPercent > 95) { Print("Errore: InpISPercent 10-95"); return false; }
   if(InpRRMin <= 0.0 || InpRRMax < InpRRMin || InpRRStep <= 0.0) { Print("Errore: parametri RR non validi"); return false; }
   if(InpValueAreaPercent <= 0.0 || InpValueAreaPercent > 100.0) { Print("Errore: Value Area % non valida"); return false; }
   if(InpHullPeriod < 2) { Print("Errore: Hull minimo 2"); return false; }
   if(InpATRPeriod < 1) { Print("Errore: ATR period minimo 1"); return false; }
   return true;
}

bool LoadAllData()
{
   datetime now = TimeCurrent();
   datetime from;
   if(InpMonthsBack > 0) from = now - (datetime)InpMonthsBack * 30 * 86400;
   else from = (datetime)SeriesInfoInteger(_Symbol, g_chartTF, SERIES_SERVER_FIRSTDATE);

   PrintFormat("Dati: %s %s | max barre terminale: %d", _Symbol, EnumToString(g_chartTF), (int)TerminalInfoInteger(TERMINAL_MAXBARS));
   Comment("VP RR Study: caricamento storico...");

   if(!LoadRates(g_chartTF, from, now, g_rc)) { Print("Errore: nessun dato sul TF del grafico"); return false; }
   int n = ArraySize(g_rc);
   if(n < 300) { Print("Errore: storico insufficiente (", n, " barre)"); return false; }
   g_dataFirst = g_rc[0].time;
   g_dataLast  = g_rc[n - 1].time;

   // TF di simulazione
   g_simSame = (g_simTF == g_chartTF);
   if(!g_simSame)
   {
      bool ok = LoadRates(g_simTF, from, now, g_rs);
      bool good = false;
      if(ok)
      {
         double span = (double)(g_dataLast - g_dataFirst);
         double cov  = (double)(g_dataLast - g_rs[0].time);
         good = (span > 0.0 && cov >= 0.6 * span);
         if(!good)
            Warn(StringFormat("Storia %s copre solo %.0f%% del periodo (max barre terminale: %d). Uso il TF del grafico per la simulazione "
                              "(ordine intrabarra pessimista). Per usare M1: Strumenti > Opzioni > Grafici > 'Max barre nel grafico' = Illimitato, riavvia, rilancia.",
                              EnumToString(g_simTF), 100.0 * MathMax(0.0, cov) / MathMax(1.0, span), (int)TerminalInfoInteger(TERMINAL_MAXBARS)));
      }
      else Warn("Impossibile caricare il TF di simulazione: uso il TF del grafico.");
      if(!good)
      {
         g_simTF = g_chartTF;
         g_simSame = true;
         ArrayFree(g_rs);
      }
   }
   if(g_simSame)
   {
      ArrayResize(g_rs, n);
      ArrayCopy(g_rs, g_rc);
   }
   g_perSim = PeriodSeconds(g_simTF);
   g_ratio = MathMax(1, g_perChart / g_perSim);
   g_L = InpMaxHoldBars * g_ratio;

   // TF profilo
   if(!g_profSame)
   {
      if(!LoadRates(g_profTF, from, now, g_rp))
      {
         Warn("Impossibile caricare il TF del profilo: uso il TF del grafico.");
         g_profTF = g_chartTF;
         g_profSame = true;
      }
   }

   // aperture dei periodi per le modalita' Daily/Weekly/Monthly
   if(InpProfileMode != MODE_SESSIONS)
   {
      ENUM_TIMEFRAMES ptf = (InpProfileMode == MODE_DAILY) ? PERIOD_D1 : ((InpProfileMode == MODE_WEEKLY) ? PERIOD_W1 : PERIOD_MN1);
      if(!LoadTimes(ptf, from - 40 * 86400, now, g_pt)) { Print("Errore: periodi non disponibili"); return false; }
   }

   // volume reale o tick volume (come l'EA)
   g_useReal = false;
   if(InpUseRealVolume)
   {
      int m = g_profSame ? ArraySize(g_rc) : ArraySize(g_rp);
      int from_i = MathMax(0, m - 2000);
      for(int i = from_i; i < m; i++)
      {
         long rv = g_profSame ? g_rc[i].real_volume : g_rp[i].real_volume;
         long tv = g_profSame ? g_rc[i].tick_volume : g_rp[i].tick_volume;
         if(rv > 0 && rv != tv) { g_useReal = true; break; }
      }
   }

   PrintFormat("Barre grafico: %d (%s -> %s) | sim: %s %d barre | rapporto %d | orizzonte %d barre sim | volume: %s",
               n, TimeToString(g_dataFirst, TIME_DATE), TimeToString(g_dataLast, TIME_DATE),
               EnumToString(g_simTF), ArraySize(g_rs), g_ratio, g_L, g_useReal ? "reale" : "tick");
   return true;
}

//+------------------------------------------------------------------+
//| Indicatori: ATR (SMA del True Range, come iATR) e Hull MA          |
//+------------------------------------------------------------------+
void BuildATR()
{
   int n = ArraySize(g_rc);
   ArrayResize(g_atr, n);
   ArrayInitialize(g_atr, 0.0);
   double tr[];
   ArrayResize(tr, n);
   tr[0] = 0.0;
   for(int i = 1; i < n; i++)
   {
      double hh = MathMax(g_rc[i].high, g_rc[i - 1].close);
      double ll = MathMin(g_rc[i].low,  g_rc[i - 1].close);
      tr[i] = hh - ll;
   }
   int p = InpATRPeriod;
   double sum = 0.0;
   for(int i = 1; i < n; i++)
   {
      sum += tr[i];
      if(i > p) sum -= tr[i - p];
      if(i >= p) g_atr[i] = sum / p;
   }
}

double WmaAt(const int idx, const int period)
{
   double sum = 0.0;
   int wsum = 0;
   for(int i = 0; i < period; i++)
   {
      int w = period - i;
      sum += g_rc[idx - i].close * w;
      wsum += w;
   }
   return (wsum == 0) ? 0.0 : sum / wsum;
}

void BuildHull()
{
   int n = ArraySize(g_rc);
   ArrayResize(g_hull, n);
   for(int k = 0; k < n; k++) g_hull[k] = EMPTY_VALUE;
   if(!InpUseHullFilter) return;

   int P = InpHullPeriod;
   int half = P / 2;
   int sq = (int)MathSqrt(P);
   for(int k = 0; k < n; k++)
   {
      if(k + 2 < P + sq + 5) continue;            // come l'EA: Bars() < period+sqrt+5 => nessun valore
      if(k - (sq - 1) - (P - 1) < 0) continue;
      double sum = 0.0;
      int wsum = 0;
      for(int j = 0; j < sq; j++)
      {
         int idx = k - j;
         double d = 2.0 * WmaAt(idx, half) - WmaAt(idx, P);
         int w = sq - j;
         sum += d * w;
         wsum += w;
      }
      g_hull[k] = (wsum == 0) ? EMPTY_VALUE : sum / wsum;
   }
}

//+------------------------------------------------------------------+
//| Profilo volumi sviluppato                                          |
//+------------------------------------------------------------------+
bool BuildProfile(const MqlRates &r[], const int i0, const int i1, const bool pseudo, SProfile &P)
{
   double hi = 0.0, lo = DBL_MAX;
   for(int i = i0; i <= i1; i++)
   {
      double h = r[i].high, l = r[i].low;
      if(h <= 0 || l <= 0) continue;
      if(h > hi) hi = h;
      if(l < lo) lo = l;
   }
   if(pseudo && g_pseudoPrice > 0.0)
   {
      if(g_pseudoPrice > hi) hi = g_pseudoPrice;
      if(g_pseudoPrice < lo) lo = g_pseudoPrice;
   }
   if(hi <= lo + EPSILON) return false;

   int L = InpPriceLevels;
   double step = (hi - lo) / L;
   for(int i = 0; i < L; i++) g_node[i] = 0.0;

   double tot = 0.0;
   for(int i = i0; i <= i1; i++)
   {
      double h = r[i].high, l = r[i].low;
      double vol = g_useReal ? (double)r[i].real_volume : (double)r[i].tick_volume;
      if(vol <= EPSILON) continue;
      int s_lv = (int)((l - lo) / step);
      int e_lv = (int)((h - lo) / step);
      s_lv = MathMax(0, MathMin(s_lv, L - 1));
      e_lv = MathMax(0, MathMin(e_lv, L - 1));
      int nl = e_lv - s_lv + 1;
      if(nl <= 0) nl = 1;
      double vpl = vol / nl;
      for(int j = s_lv; j <= e_lv; j++) g_node[j] += vpl;
      tot += vol;
   }
   if(pseudo && g_pseudoPrice > 0.0 && !g_useReal)
   {
      // barra appena aperta come la vede l'EA al primo tick: H=L=C=open, tick volume = 1
      int lv = (int)((g_pseudoPrice - lo) / step);
      lv = MathMax(0, MathMin(lv, L - 1));
      g_node[lv] += 1.0;
      tot += 1.0;
   }
   if(tot <= EPSILON) return false;

   double mx = 0.0;
   int poc_i = 0;
   for(int i = 0; i < L; i++)
      if(g_node[i] > mx) { mx = g_node[i]; poc_i = i; }

   double target = tot * (InpValueAreaPercent / 100.0);
   double acc = g_node[poc_i];
   int hiI = poc_i, loI = poc_i;
   while(acc < target && (hiI < L - 1 || loI > 0))
   {
      double va = (hiI < L - 1) ? g_node[hiI + 1] : 0.0;
      double vb = (loI > 0) ? g_node[loI - 1] : 0.0;
      if(va >= vb && hiI < L - 1) { hiI++; acc += g_node[hiI]; }
      else if(loI > 0) { loI--; acc += g_node[loI]; }
      else break;
   }

   P.high = hi;
   P.low = lo;
   P.totvol = tot;
   P.poc = lo + poc_i * step + step * 0.5;
   P.vah = lo + hiI * step + step * 0.5;
   P.val = lo + loI * step + step * 0.5;
   return true;
}

// Profilo per la finestra [st,en] come lo vedrebbe l'EA al momento t_eval
// (apertura della barra successiva al segnale): barre con open < t_eval, piu' (opzione)
// la barra appena aperta con il solo tick di apertura, se la sessione e' ancora in corso.
bool ProfileForWindow(const MqlRates &r[], const datetime st, const datetime en, const datetime t_eval, SProfile &P)
{
   int i0 = BarAtOrBefore(r, st);                 // come iBarShift(start)
   int lim = BarAtOrBefore(r, t_eval - 1);        // ultima barra gia' aperta prima di t_eval
   int ie = BarAtOrBefore(r, en);
   int i1 = MathMin(lim, ie);
   if(i0 < 0 || i1 < i0) return false;
   bool pseudo = (InpIncludeOpenTick && en >= t_eval);
   if(!BuildProfile(r, i0, i1, pseudo, P)) return false;
   P.start = st;
   P.end = en;
   return true;
}

bool ResolveSessionProfile(const int k, const datetime t_eval, SProfile &P)
{
   datetime Tk = g_rc[k].time;
   for(int d = 0; d < InpHistoryPeriods; d++)
   {
      datetime base = t_eval - (datetime)d * 86400;
      int dst = (InpAutoDST && IsEEST_DST(base)) ? 1 : 0;
      datetime day0 = base - (datetime)((long)base % 86400);
      for(int s = 0; s < 4; s++)
      {
         datetime st = day0 + (datetime)((g_ssH[s] + dst) * 3600 + g_ssM[s] * 60);
         datetime en = day0 + (datetime)((g_seH[s] + dst) * 3600 + g_seM[s] * 60);
         if(en <= st) en += 86400;
         if(Tk < st || Tk > en) continue;
         bool ok = g_profSame ? ProfileForWindow(g_rc, st, en, t_eval, P)
                              : ProfileForWindow(g_rp, st, en, t_eval, P);
         if(ok) { P.sess = s; return true; }
      }
   }
   return false;
}

// Modalita' Daily/Weekly/Monthly come l'EA: il profilo 0 va dall'apertura del periodo
// PRECEDENTE fino ad ora (quindi copre due periodi).
bool ResolveStdProfile(const int k, const datetime t_eval, SProfile &P)
{
   int m = ArraySize(g_pt);
   int lo = 0, hi = m - 1, idx = -1;
   while(lo <= hi)
   {
      int mid = (lo + hi) / 2;
      if(g_pt[mid] <= t_eval) { idx = mid; lo = mid + 1; }
      else hi = mid - 1;
   }
   if(idx < 1) return false;
   datetime st = g_pt[idx - 1];
   datetime en = t_eval;
   bool ok = g_profSame ? ProfileForWindow(g_rc, st, en, t_eval, P)
                        : ProfileForWindow(g_rp, st, en, t_eval, P);
   if(ok) P.sess = 4;
   return ok;
}

//+------------------------------------------------------------------+
//| Rilevamento eventi (logica tecnica dell'EA)                        |
//+------------------------------------------------------------------+
int CountTouches(const int k, const double level, const double thr)
{
   int touches = 0;
   int lookback = MathMax(InpMinTouchBars * 4, 12);
   for(int i = 1; i <= lookback; i++)
   {
      int idx = k - i;
      if(idx < 0) break;
      if(MathAbs(g_rc[idx].close - level) <= thr * 1.5) touches++;
   }
   return touches;
}

bool FiredAlready(const datetime pstart, const int dir)
{
   int n = ArraySize(g_sessKey);
   int lim = MathMax(0, n - 64);
   for(int i = n - 1; i >= lim; i--)
   {
      if(g_sessKey[i] == pstart)
         return ((g_sessFlag[i] & (dir > 0 ? 1 : 2)) != 0);
   }
   return false;
}

void MarkFired(const datetime pstart, const int dir)
{
   int n = ArraySize(g_sessKey);
   int lim = MathMax(0, n - 64);
   for(int i = n - 1; i >= lim; i--)
   {
      if(g_sessKey[i] == pstart) { g_sessFlag[i] |= (uchar)(dir > 0 ? 1 : 2); return; }
   }
   ArrayResize(g_sessKey, n + 1, 4096);
   ArrayResize(g_sessFlag, n + 1, 4096);
   g_sessKey[n] = pstart;
   g_sessFlag[n] = (uchar)(dir > 0 ? 1 : 2);
}

bool SimEntryIndex(const int k, int &e0)
{
   int nS = ArraySize(g_rs);
   if(g_simSame) e0 = k + 1;
   else
   {
      datetime te = g_rc[k + 1].time;
      e0 = LowerBound(g_rs, te);
      if(e0 >= nS) return false;
      if(g_rs[e0].time - te >= g_perChart) return false;     // buco nei dati di simulazione
   }
   if(e0 + g_L - 1 > nS - 2) return false;                   // orizzonte non completamente disponibile
   return true;
}

void TryAddEvent(const int k, const int dir, const SProfile &P, const double atr,
                 const double dist, const int touches, const double rej)
{
   g_candidates++;
   if(InpOneSignalPerSession && FiredAlready(P.start, dir)) return;

   int e0;
   if(!SimEntryIndex(k, e0)) { g_dropData++; return; }
   if(InpOneSignalPerSession) MarkFired(P.start, dir);

   SEvent ev;
   ZeroMemory(ev);
   ev.time = g_rc[k].time;
   ev.dir = dir;
   ev.sess = P.sess;
   ev.pstart = P.start;
   ev.k = k;
   ev.e0 = e0;
   ev.entry = g_rs[e0].open;
   ev.atr = atr;
   double sp;
   if(InpSpreadPoints >= 0) sp = InpSpreadPoints * g_point;
   else
   {
      int spr = g_rs[e0].spread;
      if(spr <= 0) spr = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      sp = MathMax(0, spr) * g_point;
   }
   ev.spread = sp;
   ev.poc = P.poc; ev.vah = P.vah; ev.val = P.val;
   ev.vaw_atr = (P.vah - P.val) / atr;
   ev.hrs = (double)(g_rc[k].time - P.start) / 3600.0;
   ev.dist_atr = dist / atr;
   ev.touches = touches;
   ev.rej = rej;
   ev.bpoc = -1; ev.bopp = -1;

   int sz = ArraySize(g_ev);
   ArrayResize(g_ev, sz + 1, 4096);
   g_ev[sz] = ev;
}

void DetectEvents()
{
   int n = ArraySize(g_rc);
   int warm = MathMax(InpATRPeriod + 2, InpHullPeriod + (int)MathSqrt(InpHullPeriod) + 6);
   warm = MathMax(warm, MathMax(InpMinTouchBars * 4, 12) + 2);
   warm = MathMax(warm, MIN_BARS_REQUIRED - 2);
   ArrayResize(g_node, InpPriceLevels);
   ArrayResize(g_ev, 0);
   ArrayResize(g_sessKey, 0);
   ArrayResize(g_sessFlag, 0);

   uint t0 = GetTickCount();
   int last_pct = -1;
   for(int k = warm; k < n - 2; k++)
   {
      if(IsStopped()) return;
      int pct = (int)(100.0 * (k - warm) / MathMax(1, n - 2 - warm));
      if(pct != last_pct && pct % 5 == 0)
      {
         last_pct = pct;
         Comment(StringFormat("VP RR Study: ricerca segnali %d%%  (eventi: %d)", pct, ArraySize(g_ev)));
      }

      double atr = g_atr[k];
      if(atr < EPSILON) continue;
      double o = g_rc[k].open, h = g_rc[k].high, l = g_rc[k].low, c = g_rc[k].close;

      bool hullL = true, hullS = true;
      if(InpUseHullFilter)
      {
         double hv = g_hull[k];
         if(hv == EMPTY_VALUE) { hullL = false; hullS = false; }
         else { hullL = (c > hv); hullS = (c < hv); }
      }

      double rng = h - l;
      double bullRej = (rng > EPSILON) ? (MathMin(o, c) - l) / rng : 0.0;
      double bearRej = (rng > EPSILON) ? (h - MathMax(o, c)) / rng : 0.0;
      bool candL = hullL && (!InpRequireRejection || bullRej >= InpMinWickRatio);
      bool candS = hullS && (!InpRequireRejection || bearRej >= InpMinWickRatio);
      if(!candL && !candS) continue;       // pre-filtro economico: nessuna delle due direzioni puo' scattare

      datetime t_eval = g_rc[k + 1].time;      // l'EA valuta al primo tick della barra successiva (dopo il weekend e' il lunedi')
      g_pseudoPrice = g_rc[k + 1].open;
      SProfile P;
      ZeroMemory(P);
      bool okp = (InpProfileMode == MODE_SESSIONS) ? ResolveSessionProfile(k, t_eval, P)
                                                   : ResolveStdProfile(k, t_eval, P);
      if(!okp) continue;

      double pip = g_point * 10.0;
      double dmult = 1.0;
      if(InpAutoAdaptDistance && atr > EPSILON)
      {
         dmult = NormalizeDouble(atr / (g_point * 10.0), 2);
         dmult = MathMax(0.5, MathMin(dmult, 3.0));
      }
      double thr = InpVADistance * dmult * pip;

      if(candL)
      {
         double dv = MathAbs(c - P.val);
         bool near_v = (dv <= thr);
         bool below = (!InpStrictMode || c < P.poc);
         if(near_v && below)
         {
            int touches = CountTouches(k, P.val, thr);
            if(touches >= InpMinTouchBars) TryAddEvent(k, 1, P, atr, dv, touches, bullRej);
         }
      }
      if(candS)
      {
         double dh = MathAbs(c - P.vah);
         bool near_h = (dh <= thr);
         bool above = (!InpStrictMode || c > P.poc);
         if(near_h && above)
         {
            int touches = CountTouches(k, P.vah, thr);
            if(touches >= InpMinTouchBars) TryAddEvent(k, -1, P, atr, dh, touches, bearRej);
         }
      }
   }
   PrintFormat("Eventi: %d (candidati %d, scartati per dati sim: %d) in %.1f s",
               ArraySize(g_ev), g_candidates, g_dropData, (GetTickCount() - t0) / 1000.0);
}

//+------------------------------------------------------------------+
//| Simulazione di un trade sul percorso gia' caricato in g_w*         |
//|                                                                    |
//| Convenzione: tutto e' espresso in "u" = profitto direzionale al    |
//| netto dello spread d'ingresso (u = dir*(prezzo-ingresso) - S).     |
//| Long: entra all'ask (= bid + S), esce al bid. Short: entra al bid, |
//| esce all'ask. In u il long e lo short sono identici.               |
//| R = (u_uscita - commissione) / SL iniziale.                        |
//| Ordine intrabarra PESSIMISTA (default): SL prima del TP; per il    |
//| trailing, prima si alza lo stop con l'estremo favorevole e poi si  |
//| testa l'estremo avverso. Ottimista: TP prima; ratchet effettivo    |
//| dalla barra successiva.                                            |
//| Ritorna 1 = TP, -1 = stop (anche trailing in profitto),            |
//| 0 = fine orizzonte (uscita a mercato).                             |
//| fl: bit0 = fine orizzonte, bit1 = esito dipendente dall'ordine.    |
//+------------------------------------------------------------------+
int SimFixed(const double S, const double comm, const double SLd, const double TPd, double &R, int &fl)
{
   fl = 0;
   const double slu = -SLd;
   const bool hasTP = (TPd > 0.0);
   const double tpu = hasTP ? TPd : 0.0;
   for(int j = 0; j < g_L; j++)
   {
      double uO = g_wO[j] - S;
      if(uO <= slu) { R = (uO - comm) / SLd; return -1; }
      if(hasTP && uO >= tpu) { R = (uO - comm) / SLd; return 1; }
      bool hs = ((g_wA[j] - S) <= slu);
      bool ht = hasTP && ((g_wF[j] - S) >= tpu);
      if(hs && ht)
      {
         fl |= 2;
         if(InpOptimistic) { R = (tpu - comm) / SLd; return 1; }
         R = (slu - comm) / SLd;
         return -1;
      }
      if(hs) { R = (slu - comm) / SLd; return -1; }
      if(ht) { R = (tpu - comm) / SLd; return 1; }
   }
   fl |= 1;
   R = ((g_wC[g_L - 1] - S) - comm) / SLd;
   return 0;
}

int SimTrail(const double S, const double comm, const double SLd, const double TPd,
             const double act, const double dist, const double step, double &R, int &fl)
{
   fl = 0;
   double sl = -SLd;
   const bool hasTP = (TPd > 0.0);
   const double tpu = hasTP ? TPd : 0.0;
   double peak = -DBL_MAX;
   for(int j = 0; j < g_L; j++)
   {
      double uO = g_wO[j] - S;
      double uF = g_wF[j] - S;
      double uA = g_wA[j] - S;
      if(uO <= sl) { R = (uO - comm) / SLd; return -1; }
      if(hasTP && uO >= tpu) { R = (uO - comm) / SLd; return 1; }

      if(!InpOptimistic)
      {
         if(uA <= sl)
         {
            if(hasTP && uF >= tpu) fl |= 2;
            R = (sl - comm) / SLd;
            return -1;
         }
         if(hasTP && uF >= tpu) { R = (tpu - comm) / SLd; return 1; }
         if(uF > peak) peak = uF;
         if(peak >= act)
         {
            double ns = peak - dist;
            if(ns > sl + step) sl = ns;
         }
         if(uA <= sl) { fl |= 2; R = (sl - comm) / SLd; return -1; }
      }
      else
      {
         if(hasTP && uF >= tpu)
         {
            if(uA <= sl) fl |= 2;
            R = (tpu - comm) / SLd;
            return 1;
         }
         if(uA <= sl) { R = (sl - comm) / SLd; return -1; }
         if(uF > peak) peak = uF;
         if(peak >= act)
         {
            double ns = peak - dist;
            if(ns > sl + step) sl = ns;
         }
      }
   }
   fl |= 1;
   R = ((g_wC[g_L - 1] - S) - comm) / SLd;
   return 0;
}

//+------------------------------------------------------------------+
//| Configurazioni (celle delle griglie)                               |
//+------------------------------------------------------------------+
void AddCfg(const int fam, const int row, const int col, const bool isAtr,
            const double sl, const double rr, const double act, const double dist)
{
   int n = ArraySize(g_cfg);
   ArrayResize(g_cfg, n + 1);
   g_cfg[n].fam = fam; g_cfg[n].row = row; g_cfg[n].col = col; g_cfg[n].atr = isAtr;
   g_cfg[n].sl = sl; g_cfg[n].rr = rr; g_cfg[n].act = act; g_cfg[n].dist = dist;
}

string MultStr(const double m)
{
   return DoubleToString(m, 2);
}

void BuildConfigs()
{
   double slm[], slp[], actm[], distm[], actp[], distp[];
   double rrl[];
   if(ParseList(InpSLMultList, slm) < 1) { ArrayResize(slm, 3); slm[0] = 0.75; slm[1] = 1.0; slm[2] = 1.5; }
   if(ParseList(InpTrailActList, actm) < 1) { ArrayResize(actm, 3); actm[0] = 0.5; actm[1] = 1.0; actm[2] = 2.0; }
   if(ParseList(InpTrailDistList, distm) < 1) { ArrayResize(distm, 3); distm[0] = 0.5; distm[1] = 1.0; distm[2] = 1.5; }

   ArrayResize(rrl, 0);
   for(double x = InpRRMin; x <= InpRRMax + 1e-9 && ArraySize(rrl) < MAXDIM; x += InpRRStep)
   {
      int sz = ArraySize(rrl);
      ArrayResize(rrl, sz + 1);
      rrl[sz] = x;
   }

   double med = MathMax(1.0, g_medATRpts);

   // SL in punti
   bool autoSL = (ParseList(InpSLPointsList, slp) < 1);
   if(autoSL)
   {
      int m = ArraySize(slm);
      ArrayResize(slp, m);
      for(int i = 0; i < m; i++) slp[i] = MathMax(1.0, MathRound(slm[i] * med));
   }
   // trailing in punti
   bool autoAct = (ParseList(InpTrailActPoints, actp) < 1);
   if(autoAct)
   {
      int m = ArraySize(actm);
      ArrayResize(actp, m);
      for(int i = 0; i < m; i++) actp[i] = MathMax(1.0, MathRound(actm[i] * med));
   }
   bool autoDist = (ParseList(InpTrailDistPoints, distp) < 1);
   if(autoDist)
   {
      int m = ArraySize(distm);
      ArrayResize(distp, m);
      for(int i = 0; i < m; i++) distp[i] = MathMax(1.0, MathRound(distm[i] * med));
   }
   double trailSLp = (InpTrailSLPoints > 0) ? (double)InpTrailSLPoints : MathMax(1.0, MathRound(InpTrailSLATR * med));

   ArrayResize(g_cfg, 0);
   int nrr = ArraySize(rrl);

   // famiglia 0: fisso, punti
   g_base[0] = ArraySize(g_cfg);
   g_dimR[0] = ArraySize(slp);
   g_dimC[0] = nrr;
   for(int r = 0; r < g_dimR[0]; r++)
   {
      g_rowLbl[0][r] = StringFormat("SL %d pt (~%.2f ATR)", (int)slp[r], slp[r] / med);
      for(int c = 0; c < nrr; c++)
      {
         if(r == 0) g_colLbl[0][c] = "1:" + F(rrl[c], (rrl[c] == MathFloor(rrl[c])) ? 0 : 2);
         AddCfg(0, r, c, false, slp[r] * g_point, rrl[c], 0, 0);
      }
   }
   // famiglia 1: fisso, ATR
   g_base[1] = ArraySize(g_cfg);
   g_dimR[1] = ArraySize(slm);
   g_dimC[1] = nrr;
   for(int r = 0; r < g_dimR[1]; r++)
   {
      g_rowLbl[1][r] = "SL " + MultStr(slm[r]) + " ATR";
      for(int c = 0; c < nrr; c++)
      {
         if(r == 0) g_colLbl[1][c] = g_colLbl[0][c];
         AddCfg(1, r, c, true, slm[r], rrl[c], 0, 0);
      }
   }
   // famiglia 2: trailing, punti (righe = attivazione, colonne = distanza)
   g_base[2] = ArraySize(g_cfg);
   g_dimR[2] = ArraySize(actp);
   g_dimC[2] = ArraySize(distp);
   for(int r = 0; r < g_dimR[2]; r++)
   {
      g_rowLbl[2][r] = StringFormat("Att. %d pt (~%.2f ATR)", (int)actp[r], actp[r] / med);
      for(int c = 0; c < g_dimC[2]; c++)
      {
         if(r == 0) g_colLbl[2][c] = StringFormat("Dist %d pt (~%.2f)", (int)distp[c], distp[c] / med);
         AddCfg(2, r, c, false, trailSLp * g_point, InpTrailTPRR, actp[r] * g_point, distp[c] * g_point);
      }
   }
   // famiglia 3: trailing, ATR
   g_base[3] = ArraySize(g_cfg);
   g_dimR[3] = ArraySize(actm);
   g_dimC[3] = ArraySize(distm);
   for(int r = 0; r < g_dimR[3]; r++)
   {
      g_rowLbl[3][r] = "Att. " + MultStr(actm[r]) + " ATR";
      for(int c = 0; c < g_dimC[3]; c++)
      {
         if(r == 0) g_colLbl[3][c] = "Dist " + MultStr(distm[c]) + " ATR";
         AddCfg(3, r, c, true, InpTrailSLATR, InpTrailTPRR, actm[r], distm[c]);
      }
   }
   // famiglia 4: riferimento (una sola cella)
   g_base[4] = ArraySize(g_cfg);
   g_dimR[4] = 1;
   g_dimC[4] = 1;
   g_rowLbl[4][0] = "SL " + MultStr(InpRefSLATR) + " ATR";
   g_colLbl[4][0] = "1:" + F(InpRefRR, 2);
   AddCfg(4, 0, 0, true, InpRefSLATR, InpRefRR, 0, 0);
   g_refIdx = g_base[4];

   if(autoSL) Print("Nota: SL in punti generati da ATR mediano (", F(med, 0), " punti) x multipli. Per fissare i tuoi valori usa InpSLPointsList.");
}

//+------------------------------------------------------------------+
//| Simulazione di tutti gli eventi su tutte le configurazioni         |
//+------------------------------------------------------------------+
void BuildPath(const int e)
{
   int dir = g_ev[e].dir;
   double E0 = g_ev[e].entry;
   int e0 = g_ev[e].e0;
   for(int j = 0; j < g_L; j++)
   {
      double o = g_rs[e0 + j].open, h = g_rs[e0 + j].high, l = g_rs[e0 + j].low, c = g_rs[e0 + j].close;
      g_wO[j] = dir * (o - E0);
      g_wC[j] = dir * (c - E0);
      if(dir > 0) { g_wF[j] = h - E0; g_wA[j] = l - E0; }
      else        { g_wF[j] = E0 - l; g_wA[j] = E0 - h; }
   }
}

void EventStudy(const int e)
{
   double atr = g_ev[e].atr;
   int dir = g_ev[e].dir;

   double mfe = 0.0, mae = 0.0;
   for(int j = 0; j < g_L; j++)
   {
      if(g_wF[j] > mfe) mfe = g_wF[j];
      if(-g_wA[j] > mae) mae = -g_wA[j];
   }
   g_ev[e].mfe = mfe / atr;
   g_ev[e].mae = mae / atr;

   for(int h = 0; h < g_nH; h++)
   {
      int idx = MathMin(g_L - 1, g_hor[h] * g_ratio - 1);
      g_ev[e].ret[h] = g_wC[idx] / atr;
   }

   for(int i = 0; i < NFP; i++)
   {
      double R; int fl;
      double d = g_fpX[i] * atr;
      g_ev[e].fp[i] = SimFixed(0.0, 0.0, d, d, R, fl);
   }

   double gPoc = dir * (g_ev[e].poc - g_ev[e].entry);
   double gOpp = dir * (((dir > 0) ? g_ev[e].vah : g_ev[e].val) - g_ev[e].entry);
   g_ev[e].dpoc = gPoc / atr;
   g_ev[e].dopp = gOpp / atr;
   int bp = -1, bo = -1;
   for(int j = 0; j < g_L; j++)
   {
      if(bp < 0 && g_wF[j] >= gPoc) bp = j;
      if(bo < 0 && g_wF[j] >= gOpp) bo = j;
      if(bp >= 0 && bo >= 0) break;
   }
   g_ev[e].bpoc = (bp < 0) ? -1 : bp / g_ratio;
   g_ev[e].bopp = (bo < 0) ? -1 : bo / g_ratio;
}

void SimulateAll()
{
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);
   ArrayResize(g_R, E * C);
   ArrayResize(g_F, E * C);
   ArrayResize(g_wO, g_L);
   ArrayResize(g_wF, g_L);
   ArrayResize(g_wA, g_L);
   ArrayResize(g_wC, g_L);

   uint t0 = GetTickCount();
   for(int e = 0; e < E; e++)
   {
      if(IsStopped()) { Print("Interrotto dall'utente"); break; }
      if((e & 63) == 0) Comment(StringFormat("VP RR Study: simulazione %d/%d eventi x %d configurazioni", e, E, C));

      BuildPath(e);
      EventStudy(e);

      double atr = g_ev[e].atr;
      double S = g_ev[e].spread;
      double comm = InpCommissionPoints * g_point;
      int off = e * C;
      for(int c = 0; c < C; c++)
      {
         double sl = g_cfg[c].atr ? g_cfg[c].sl * atr : g_cfg[c].sl;
         double R = 0.0;
         int fl = 0;
         if(sl <= EPSILON) { g_R[off + c] = 0.0f; g_F[off + c] = 0; continue; }
         if(g_cfg[c].fam == 0 || g_cfg[c].fam == 1 || g_cfg[c].fam == 4)
         {
            SimFixed(S, comm, sl, g_cfg[c].rr * sl, R, fl);
         }
         else
         {
            double act  = g_cfg[c].atr ? g_cfg[c].act * atr  : g_cfg[c].act;
            double dist = g_cfg[c].atr ? g_cfg[c].dist * atr : g_cfg[c].dist;
            double tp   = (g_cfg[c].rr > 0.0) ? g_cfg[c].rr * sl : 0.0;
            SimTrail(S, comm, sl, tp, act, dist, InpTrailStepRatio * dist, R, fl);
         }
         g_R[off + c] = (float)R;
         g_F[off + c] = (uchar)fl;
      }
   }
   PrintFormat("Simulazione: %d eventi x %d configurazioni in %.1f s", E, C, (GetTickCount() - t0) / 1000.0);
}

//+------------------------------------------------------------------+
//| Statistiche                                                        |
//+------------------------------------------------------------------+
void StatAdd(SStat &s, const double r, const uchar fl)
{
   s.n++;
   if(r > 0.0) { s.wins++; s.gp += r; }
   else s.gl += -r;
   s.sum += r;
   s.sum2 += r * r;
   if((fl & 1) != 0) s.tmo++;
   if((fl & 2) != 0) s.amb++;
   s.eq += r;
   if(s.eq > s.peak) s.peak = s.eq;
   double d = s.peak - s.eq;
   if(d > s.dd) s.dd = d;
}

double StatMean(const SStat &s) { return (s.n > 0) ? s.sum / s.n : 0.0; }
double StatSD(const SStat &s)
{
   if(s.n < 2) return 0.0;
   double v = (s.sum2 - s.sum * s.sum / s.n) / (s.n - 1);
   return (v > 0.0) ? MathSqrt(v) : 0.0;
}
double StatT(const SStat &s)
{
   double sd = StatSD(s);
   if(s.n < 2 || sd < EPSILON) return 0.0;
   return StatMean(s) / (sd / MathSqrt((double)s.n));
}
double StatPF(const SStat &s)
{
   if(s.gl < EPSILON) return (s.gp > EPSILON) ? 99.0 : 0.0;
   return s.gp / s.gl;
}
double StatWR(const SStat &s) { return (s.n > 0) ? 100.0 * s.wins / s.n : 0.0; }

void GetStat(const int c, const int part, SStat &s)
{
   if(part == 0) s = g_stIS[c];
   else if(part == 1) s = g_stOOS[c];
   else s = g_stAll[c];
}

void AggregateAll()
{
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);
   ArrayResize(g_stIS, C);
   ArrayResize(g_stOOS, C);
   ArrayResize(g_stAll, C);
   for(int c = 0; c < C; c++) { ZeroMemory(g_stIS[c]); ZeroMemory(g_stOOS[c]); ZeroMemory(g_stAll[c]); }

   g_split = (int)(E * InpISPercent / 100.0);
   if(g_split < 1) g_split = 1;
   if(g_split > E) g_split = E;
   for(int e = 0; e < E; e++)
   {
      int off = e * C;
      for(int c = 0; c < C; c++)
      {
         double r = (double)g_R[off + c];
         uchar fl = g_F[off + c];
         StatAdd(g_stAll[c], r, fl);
         if(e < g_split) StatAdd(g_stIS[c], r, fl);
         else StatAdd(g_stOOS[c], r, fl);
      }
   }
}

double RankMetric(const SStat &s)
{
   if(InpRankBy == RANK_EXPECTANCY) return StatMean(s);
   if(InpRankBy == RANK_PF) return MathMin(StatPF(s), 10.0) - 1.0;
   return StatT(s);
}

// Punteggio (sull'IS) di ogni cella; con InpSmoothRank media della cella e dei vicini validi.
void ScoreCells()
{
   int C = ArraySize(g_cfg);
   ArrayResize(g_score, C);
   ArrayResize(g_valid, C);
   double raw[];
   ArrayResize(raw, C);
   for(int c = 0; c < C; c++)
   {
      g_valid[c] = (g_stIS[c].n >= InpMinTrades);
      raw[c] = g_valid[c] ? RankMetric(g_stIS[c]) : 0.0;
      g_score[c] = raw[c];
   }
   for(int f = 0; f < 4; f++) g_best[f] = -1;
   g_best[4] = g_refIdx;

   for(int f = 0; f < 4; f++)
   {
      int R = g_dimR[f], Cn = g_dimC[f];
      for(int r = 0; r < R; r++)
         for(int cc = 0; cc < Cn; cc++)
         {
            int idx = g_base[f] + r * Cn + cc;
            if(!g_valid[idx]) continue;
            double sc = raw[idx];
            if(InpSmoothRank)
            {
               double sum = 0.0; int cnt = 0;
               for(int dr = -1; dr <= 1; dr++)
                  for(int dc = -1; dc <= 1; dc++)
                  {
                     int rr2 = r + dr, cc2 = cc + dc;
                     if(rr2 < 0 || rr2 >= R || cc2 < 0 || cc2 >= Cn) continue;
                     int id2 = g_base[f] + rr2 * Cn + cc2;
                     if(!g_valid[id2]) continue;
                     sum += raw[id2];
                     cnt++;
                  }
               sc = (cnt > 0) ? sum / cnt : raw[idx];
            }
            g_score[idx] = sc;
            if(g_best[f] < 0 || sc > g_score[g_best[f]]) g_best[f] = idx;
         }
   }
}

//+------------------------------------------------------------------+
//| Quantili per i bucket (ampiezza VA, maturita' del profilo)         |
//+------------------------------------------------------------------+
void AssignBuckets()
{
   int E = ArraySize(g_ev);
   double w[], h[];
   ArrayResize(w, E);
   ArrayResize(h, E);
   for(int e = 0; e < E; e++) { w[e] = g_ev[e].vaw_atr; h[e] = g_ev[e].hrs; }
   ArraySort(w);
   ArraySort(h);
   for(int i = 0; i < 4; i++) g_wEdge[i] = Quantile(w, E, (i + 1) / 5.0);
   for(int i = 0; i < 2; i++) g_hEdge[i] = Quantile(h, E, (i + 1) / 3.0);
   for(int e = 0; e < E; e++)
   {
      int bw = 0;
      for(int i = 0; i < 4; i++) if(g_ev[e].vaw_atr > g_wEdge[i]) bw++;
      int bh = 0;
      for(int i = 0; i < 2; i++) if(g_ev[e].hrs > g_hEdge[i]) bh++;
      g_ev[e].bw = bw;
      g_ev[e].bh = bh;
   }
}

double MedianATRPoints()
{
   int E = ArraySize(g_ev);
   double a[];
   ArrayResize(a, E);
   for(int e = 0; e < E; e++) a[e] = g_ev[e].atr / g_point;
   ArraySort(a);
   return Quantile(a, E, 0.5);
}

//+------------------------------------------------------------------+
//| REPORT                                                             |
//+------------------------------------------------------------------+
void HW(const string s)
{
   if(g_fh != INVALID_HANDLE) FileWriteString(g_fh, s);
}

string Heat(const double v, const double scale)
{
   double t = (scale > EPSILON) ? v / scale : 0.0;
   if(t > 1.0) t = 1.0;
   if(t < -1.0) t = -1.0;
   int r, g, b;
   if(t >= 0.0) { r = (int)(255 - (255 - 70) * t); g = (int)(255 - (255 - 175) * t); b = (int)(255 - (255 - 100) * t); }
   else { double a = -t; r = (int)(255 - (255 - 215) * a); g = (int)(255 - (255 - 80) * a); b = (int)(255 - (255 - 80) * a); }
   return StringFormat("rgb(%d,%d,%d)", r, g, b);
}

string PfStr(const double pf)
{
   if(pf >= 99.0) return "inf";
   return F(pf, 2);
}

string SessName(const int s)
{
   if(s == 0) return "Sydney";
   if(s == 1) return "Asian";
   if(s == 2) return "London";
   if(s == 3) return "New York";
   return "Daily/Weekly/Monthly";
}

// metric: 0 E[R], 1 WinRate, 2 PF, 3 t-stat, 4 MaxDD(R), 5 N
double MetricValue(const int metric, const SStat &s)
{
   double v = (double)s.n;
   if(metric == 0) v = StatMean(s);
   else if(metric == 1) v = StatWR(s);
   else if(metric == 2) v = StatPF(s);
   else if(metric == 3) v = StatT(s);
   else if(metric == 4) v = s.dd;
   return v;
}

string MetricStr(const int metric, const SStat &s)
{
   if(s.n == 0) return "-";
   string out = IntegerToString(s.n);
   if(metric == 0) out = F(StatMean(s), 3);
   else if(metric == 1) out = F(StatWR(s), 1) + "%";
   else if(metric == 2) out = PfStr(StatPF(s));
   else if(metric == 3) out = F(StatT(s), 2);
   else if(metric == 4) out = F(s.dd, 1);
   return out;
}

// valore usato per la colorazione (0 = nessuna)
double HeatValue(const int metric, const int fam, const int c, const SStat &s)
{
   if(s.n == 0) return 0.0;
   double v = 0.0;
   if(metric == 0) v = StatMean(s);
   else if(metric == 1)
   {
      if(fam == 0 || fam == 1 || fam == 4) v = StatWR(s) - 100.0 / (1.0 + g_cfg[c].rr);   // vantaggio rispetto al breakeven
   }
   else if(metric == 2) v = StatPF(s) - 1.0;
   else if(metric == 3) v = StatT(s);
   return v;
}

void HtmlMatrix(const string title, const string note, const int fam, const int metric, const int part)
{
   int R = g_dimR[fam], Cn = g_dimC[fam];
   double sc = 0.0;
   for(int r = 0; r < R; r++)
      for(int cc = 0; cc < Cn; cc++)
      {
         int c = g_base[fam] + r * Cn + cc;
         SStat s;
         GetStat(c, part, s);
         sc = MathMax(sc, MathAbs(HeatValue(metric, fam, c, s)));
      }
   double floorSc = (metric == 0) ? 0.05 : ((metric == 1) ? 3.0 : ((metric == 2) ? 0.1 : 1.5));
   sc = MathMax(sc, floorSc);

   HW("<h3>" + title + "</h3>");
   if(StringLen(note) > 0) HW("<div class='note'>" + note + "</div>");
   HW("<table class='m'><tr><th></th>");
   for(int cc = 0; cc < Cn; cc++) HW("<th>" + g_colLbl[fam][cc] + "</th>");
   HW("</tr>\n");
   for(int r = 0; r < R; r++)
   {
      HW("<tr><th class='rl'>" + g_rowLbl[fam][r] + "</th>");
      for(int cc = 0; cc < Cn; cc++)
      {
         int c = g_base[fam] + r * Cn + cc;
         SStat s;
         GetStat(c, part, s);
         string bg = "";
         double hv = HeatValue(metric, fam, c, s);
         if(s.n > 0 && hv != 0.0) bg = " style='background:" + Heat(hv, sc) + "'";
         string cls = (s.n < InpMinTrades) ? " class='lo'" : "";
         if(g_best[fam] == c && fam < 4 && metric == 0 && part < 2) cls = " class='best'";
         HW("<td" + cls + bg + ">" + MetricStr(metric, s) + "</td>");
      }
      HW("</tr>\n");
   }
   HW("</table>");
}

void HtmlStart()
{
   HW("<!DOCTYPE html><html><head><meta charset='utf-8'><title>VP RR Study</title><style>");
   HW("body{font-family:Segoe UI,Arial,sans-serif;margin:24px auto;max-width:1180px;padding:0 14px;color:#1b1f24;background:#fafbfc;font-size:14px}");
   HW("h1{font-size:22px;margin-bottom:4px}h2{font-size:17px;margin-top:34px;border-bottom:1px solid #d0d7de;padding-bottom:4px}h3{font-size:14px;margin:20px 0 4px}");
   HW("table{border-collapse:collapse;margin:6px 0 4px;font-size:12.5px}th,td{border:1px solid #d0d7de;padding:3px 8px;text-align:right}");
   HW("th{background:#eef1f4;font-weight:600}th.rl{text-align:left;white-space:nowrap}td.lo{color:#9aa3ad}td.best{outline:2px solid #1f6feb;outline-offset:-2px;font-weight:700}");
   HW(".note{color:#59636e;font-size:12px;margin:2px 0 4px}.warn{background:#fff4d6;border:1px solid #e0c36a;padding:6px 10px;margin:6px 0;font-size:13px}");
   HW(".bad{color:#b42318;font-weight:600}.ok{color:#1a7f37;font-weight:600}.mid{color:#9a6700;font-weight:600}.mono{font-family:Consolas,monospace}");
   HW(".legend span{display:inline-block;margin-right:14px}svg{background:#fff;border:1px solid #d0d7de}ul{margin:6px 0 6px 18px;padding:0}li{margin:3px 0}");
   HW("</style></head><body>\n");
}

void HtmlEventStudy()
{
   int E = ArraySize(g_ev);
   HW("<h2>2. Come si comporta il prezzo dopo il segnale (lordo di costi)</h2>");
   HW("<div class='note'>Tutto direzionale: positivo = il prezzo si muove nel verso del segnale. Unit&agrave;: ATR del grafico al momento del segnale; in punti &egrave; la conversione con l'ATR mediano (" +
      F(g_medATRpts, 0) + " punti). Orizzonte: barre del grafico dopo l'ingresso.</div>");

   HW("<h3>Rendimento direzionale medio a fine orizzonte</h3><table><tr><th>Barre</th><th>Medio (ATR)</th><th>Medio (punti)</th><th>Errore std.</th><th>t</th><th>% positivi</th></tr>");
   for(int h = 0; h < g_nH; h++)
   {
      double sum = 0.0, sum2 = 0.0;
      int pos = 0;
      for(int e = 0; e < E; e++)
      {
         double v = g_ev[e].ret[h];
         sum += v; sum2 += v * v;
         if(v > 0.0) pos++;
      }
      double mean = sum / E;
      double var = (E > 1) ? (sum2 - sum * sum / E) / (E - 1) : 0.0;
      double se = (var > 0.0) ? MathSqrt(var / E) : 0.0;
      double t = (se > EPSILON) ? mean / se : 0.0;
      string cls = (MathAbs(t) >= 2.0) ? ((t > 0) ? " class='ok'" : " class='bad'") : "";
      HW("<tr><th>" + IntegerToString(g_hor[h]) + "</th><td>" + F(mean, 3) + "</td><td>" + F(mean * g_medATRpts, 1) + "</td><td>" + F(se, 3) +
         "</td><td" + cls + ">" + F(t, 2) + "</td><td>" + F(100.0 * pos / E, 1) + "%</td></tr>\n");
   }
   HW("</table>");

   // MFE / MAE
   double mf[], ma[];
   ArrayResize(mf, E);
   ArrayResize(ma, E);
   double smf = 0.0, sma = 0.0;
   for(int e = 0; e < E; e++) { mf[e] = g_ev[e].mfe; ma[e] = g_ev[e].mae; smf += mf[e]; sma += ma[e]; }
   ArraySort(mf);
   ArraySort(ma);
   HW("<h3>Escursione massima sull'orizzonte (ATR)</h3><table><tr><th></th><th>Media</th><th>P25</th><th>Mediana</th><th>P75</th><th>P90</th></tr>");
   HW("<tr><th class='rl'>MFE (favorevole)</th><td>" + F(smf / E, 2) + "</td><td>" + F(Quantile(mf, E, 0.25), 2) + "</td><td>" + F(Quantile(mf, E, 0.5), 2) +
      "</td><td>" + F(Quantile(mf, E, 0.75), 2) + "</td><td>" + F(Quantile(mf, E, 0.9), 2) + "</td></tr>");
   HW("<tr><th class='rl'>MAE (avversa)</th><td>" + F(sma / E, 2) + "</td><td>" + F(Quantile(ma, E, 0.25), 2) + "</td><td>" + F(Quantile(ma, E, 0.5), 2) +
      "</td><td>" + F(Quantile(ma, E, 0.75), 2) + "</td><td>" + F(Quantile(ma, E, 0.9), 2) + "</td></tr></table>");
   HW("<div class='note'>MFE e MAE sono misurate su tutto l'orizzonte senza fermarsi allo SL: servono a dimensionare stop e target, non sono un risultato di trading.</div>");

   // first passage
   HW("<h3>Quale soglia viene toccata per prima: +X ATR o -X ATR?</h3><table><tr><th>X (ATR)</th><th>+X prima</th><th>-X prima</th><th>Nessuna</th><th>P(+X | decisi)</th><th>z vs 50%</th></tr>");
   for(int i = 0; i < NFP; i++)
   {
      int up = 0, dn = 0, nn = 0;
      for(int e = 0; e < E; e++)
      {
         if(g_ev[e].fp[i] > 0) up++; else if(g_ev[e].fp[i] < 0) dn++; else nn++;
      }
      double p = (up + dn > 0) ? (double)up / (up + dn) : 0.5;
      double z = (up + dn > 0) ? (p - 0.5) / MathSqrt(0.25 / (up + dn)) : 0.0;
      string cls = (MathAbs(z) >= 2.0) ? ((z > 0) ? " class='ok'" : " class='bad'") : "";
      HW("<tr><th>" + F(g_fpX[i], 1) + "</th><td>" + F(100.0 * up / E, 1) + "%</td><td>" + F(100.0 * dn / E, 1) + "%</td><td>" + F(100.0 * nn / E, 1) +
         "%</td><td>" + F(100.0 * p, 1) + "%</td><td" + cls + ">" + F(z, 2) + "</td></tr>\n");
   }
   HW("</table><div class='note'>Con prezzo senza direzione (random walk) P(+X | decisi) = 50%. Scarto significativo = il segnale ha un contenuto direzionale prima dei costi. Se SL e TP cadono nella stessa barra si assume lo SL.</div>");

   // livelli
   HW("<h3>Rispetto ai livelli del profilo</h3><table><tr><th></th><th>Distanza mediana (ATR)</th><th>Toccato entro l'orizzonte</th><th>Barre al tocco (mediana)</th></tr>");
   for(int lv = 0; lv < 2; lv++)
   {
      double d[], bt[];
      ArrayResize(d, E);
      ArrayResize(bt, 0);
      int hit = 0;
      for(int e = 0; e < E; e++)
      {
         d[e] = (lv == 0) ? g_ev[e].dpoc : g_ev[e].dopp;
         int b = (lv == 0) ? g_ev[e].bpoc : g_ev[e].bopp;
         if(b >= 0)
         {
            hit++;
            int sz = ArraySize(bt);
            ArrayResize(bt, sz + 1);
            bt[sz] = b;
         }
      }
      ArraySort(d);
      ArraySort(bt);
      HW("<tr><th class='rl'>" + Pick(lv == 0, "POC", "Bordo opposto Value Area (VAH per i long, VAL per gli short)") + "</th><td>" + F(Quantile(d, E, 0.5), 2) +
         "</td><td>" + F(100.0 * hit / E, 1) + "%</td><td>" + F(Quantile(bt, ArraySize(bt), 0.5), 1) + "</td></tr>");
   }
   HW("</table><div class='note'>Se la distanza mediana del POC &egrave; 0.4 ATR, anche prendendolo sempre ottieni solo 0.4R con SL = 1 ATR: il bersaglio naturale del profilo spesso non paga abbastanza.</div>");
}

void BreakRow(const string label, const int dimType, const int val)
{
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);
   SStat s;
   ZeroMemory(s);
   double smfe = 0.0, smae = 0.0;
   for(int e = 0; e < E; e++)
   {
      bool m = false;
      if(dimType == 0) m = (g_ev[e].dir == val);
      else if(dimType == 1) m = (g_ev[e].sess == val);
      else if(dimType == 2) m = (g_ev[e].bw == val);
      else m = (g_ev[e].bh == val);
      if(!m) continue;
      StatAdd(s, (double)g_R[e * C + g_refIdx], g_F[e * C + g_refIdx]);
      smfe += g_ev[e].mfe;
      smae += g_ev[e].mae;
   }
   if(s.n == 0) return;
   double t = StatT(s);
   string cls = (s.n >= InpMinTrades && t >= 2.0) ? " class='ok'" : ((s.n >= InpMinTrades && t <= -2.0) ? " class='bad'" : "");
   HW("<tr><th class='rl'>" + label + "</th><td>" + IntegerToString(s.n) + "</td><td>" + F(StatWR(s), 1) + "%</td><td>" + F(StatMean(s), 3) +
      "</td><td" + cls + ">" + F(t, 2) + "</td><td>" + PfStr(StatPF(s)) + "</td><td>" + F(smfe / s.n, 2) + "</td><td>" + F(smae / s.n, 2) + "</td></tr>\n");
}

void HtmlBreakdown()
{
   HW("<h2>3. Quali range funzionano meglio</h2>");
   HW("<div class='note'>Configurazione di riferimento: SL " + F(InpRefSLATR, 2) + " ATR, TP " + F(InpRefRR * InpRefSLATR, 2) + " ATR (RR 1:" + F(InpRefRR, 1) +
      "), netto di costi, su tutti gli eventi. Una dimensione alla volta (nessun incrocio) per non frammentare il campione. Evidenziati solo scostamenti con |t| &ge; 2 e almeno " +
      IntegerToString(InpMinTrades) + " trade: con ~15 celle guardate, un paio escono per puro caso.</div>");
   HW("<table><tr><th></th><th>N</th><th>Win %</th><th>E[R]</th><th>t</th><th>PF</th><th>MFE media (ATR)</th><th>MAE media (ATR)</th></tr>");
   HW("<tr><th class='rl' colspan='8' style='background:#f6f8fa'>Direzione</th></tr>");
   BreakRow("Long (VAL)", 0, 1);
   BreakRow("Short (VAH)", 0, -1);
   HW("<tr><th class='rl' colspan='8' style='background:#f6f8fa'>Sessione del profilo</th></tr>");
   for(int s = 0; s < NSESS; s++) BreakRow(SessName(s), 1, s);
   HW("<tr><th class='rl' colspan='8' style='background:#f6f8fa'>Ampiezza della Value Area (quintili, in ATR)</th></tr>");
   for(int b = 0; b < 5; b++)
   {
      string lo = (b == 0) ? "0" : F(g_wEdge[b - 1], 1);
      string hi = (b == 4) ? "inf" : F(g_wEdge[b], 1);
      BreakRow("VA " + lo + " - " + hi + " ATR", 2, b);
   }
   HW("<tr><th class='rl' colspan='8' style='background:#f6f8fa'>Ore dall'inizio del profilo (terzili)</th></tr>");
   for(int b = 0; b < 3; b++)
   {
      string lo = (b == 0) ? "0" : F(g_hEdge[b - 1], 1);
      string hi = (b == 2) ? "inf" : F(g_hEdge[b], 1);
      BreakRow(lo + " - " + hi + " h", 3, b);
   }
   HW("</table>");
}

string Verdict(const int c, double &pOut)
{
   SStat o = g_stOOS[c];
   pOut = 1.0;
   if(o.n < 20) return "campione OOS insufficiente";
   double t = StatT(o);
   pOut = NormUpper(t);
   if(StatMean(o) <= 0.0) return "<span class='bad'>NON confermato OOS</span>";
   if(pOut < 0.05) return "<span class='ok'>confermato OOS (p&lt;5%)</span>";
   return "<span class='mid'>OOS positivo ma non significativo</span>";
}

string FamName(const int f)
{
   if(f == 0) return "RR fisso - punti";
   if(f == 1) return "RR fisso - ATR";
   if(f == 2) return "Trailing - punti";
   if(f == 3) return "Trailing - ATR";
   return "Riferimento";
}

string CellDesc(const int c)
{
   int f = g_cfg[c].fam;
   int r = g_cfg[c].row, cc = g_cfg[c].col;
   if(f == 4) return g_rowLbl[4][0] + " / " + g_colLbl[4][0];
   if(f <= 1) return g_rowLbl[f][r] + " / RR " + g_colLbl[f][cc];
   return g_rowLbl[f][r] + " / " + g_colLbl[f][cc];
}

void HtmlVerdict()
{
   int C = ArraySize(g_cfg);
   HW("<h2>1. Verdetto</h2>");
   HW("<div class='note'>Per ogni famiglia la cella migliore &egrave; scelta SOLO sull'In-Sample (metrica: " +
      Pick(InpRankBy == RANK_TSTAT, "t-stat", Pick(InpRankBy == RANK_EXPECTANCY, "expectancy", "profit factor")) +
      Pick(InpSmoothRank, ", mediata sui vicini 3x3", "") + "). L'unico numero onesto &egrave; la colonna OOS: un solo test, fatto su dati mai usati per scegliere.</div>");
   HW("<table><tr><th class='rl'>Famiglia</th><th class='rl'>Cella scelta (IS)</th><th>N IS</th><th>E[R] IS</th><th>t IS</th><th>t critico*</th><th>N OOS</th><th>E[R] OOS</th><th>t OOS</th><th>p OOS</th><th>PF OOS</th><th>MaxDD (R) tutto</th><th class='rl'>Esito</th></tr>");
   for(int f = 0; f < 5; f++)
   {
      int c = g_best[f];
      if(c < 0) { HW("<tr><th class='rl'>" + FamName(f) + "</th><td colspan='12' class='rl'>nessuna cella con almeno " + IntegerToString(InpMinTrades) + " trade IS</td></tr>"); continue; }
      int K = (f < 4) ? g_dimR[f] * g_dimC[f] : 1;
      double tcrit = (f < 4) ? NormInvUpper(0.05 / K) : 1.645;
      double p;
      string v = Verdict(c, p);
      if(f < 4 && StatT(g_stIS[c]) < tcrit) v += " <span class='note'>(t IS sotto la soglia di correzione multipla)</span>";
      HW("<tr><th class='rl'>" + FamName(f) + "</th><td class='mono' style='text-align:left'>" + CellDesc(c) + "</td><td>" + IntegerToString(g_stIS[c].n) + "</td><td>" +
         F(StatMean(g_stIS[c]), 3) + "</td><td>" + F(StatT(g_stIS[c]), 2) + "</td><td>" + F(tcrit, 2) + "</td><td>" + IntegerToString(g_stOOS[c].n) + "</td><td>" +
         F(StatMean(g_stOOS[c]), 3) + "</td><td>" + F(StatT(g_stOOS[c]), 2) + "</td><td>" + F(p, 3) + "</td><td>" + PfStr(StatPF(g_stOOS[c])) + "</td><td>" +
         F(g_stAll[c].dd, 1) + "</td><td class='rl' style='text-align:left'>" + v + "</td></tr>\n");
   }
   HW("</table><div class='note'>* soglia t (one-sided 5%) con correzione di Bonferroni sul numero di celle della famiglia: conservativa perch&eacute; le celle sono correlate, ma &egrave; l'ordine di grandezza giusto per il data-mining. "
      "La riga &laquo;Riferimento&raquo; non &egrave; stata scelta: &egrave; la configurazione di default dell'EA, quindi vale come test a posteriori unico.</div>");

   // correlazione IS-OOS
   HW("<h3>La mappa delle celle si ripete fuori campione?</h3><table><tr><th class='rl'>Famiglia</th><th>Celle confrontate</th><th>Spearman IS-OOS (E[R])</th><th class='rl'>Lettura</th></tr>");
   for(int f = 0; f < 4; f++)
   {
      double a[], b[];
      ArrayResize(a, 0);
      ArrayResize(b, 0);
      int R = g_dimR[f], Cn = g_dimC[f];
      for(int i = 0; i < R * Cn; i++)
      {
         int c = g_base[f] + i;
         if(g_stIS[c].n < InpMinTrades || g_stOOS[c].n < 10) continue;
         int sz = ArraySize(a);
         ArrayResize(a, sz + 1);
         ArrayResize(b, sz + 1);
         a[sz] = StatMean(g_stIS[c]);
         b[sz] = StatMean(g_stOOS[c]);
      }
      int n = ArraySize(a);
      double rho = Spearman(a, b, n);
      string lec = "dati insufficienti";
      if(n >= 8) lec = (rho >= 0.5) ? "<span class='ok'>mappa stabile</span>" : ((rho >= 0.2) ? "<span class='mid'>mappa debole</span>" : "<span class='bad'>mappa instabile: ottimizzare qui insegue rumore</span>");
      HW("<tr><th class='rl'>" + FamName(f) + "</th><td>" + IntegerToString(n) + "</td><td>" + F(rho, 2) + "</td><td class='rl' style='text-align:left'>" + lec + "</td></tr>");
   }
   HW("</table><div class='note'>Correlazione ~0 = la &laquo;cella migliore&raquo; non ha alcun valore predittivo. Attenzione: una correlazione alta NON prova un edge, perch&eacute; la mappa ha anche una struttura sistematica dovuta ai costi (SL stretti e RR alti perdono sempre di pi&ugrave;). Conta il segno di E[R] OOS nella tabella sopra.</div>");
}

void HtmlTop10()
{
   int C = ArraySize(g_cfg);
   HW("<h2>6. Prime 10 celle per famiglia (ordinate sul punteggio IS)</h2>");
   for(int f = 0; f < 4; f++)
   {
      int R = g_dimR[f], Cn = g_dimC[f];
      int ids[];
      ArrayResize(ids, 0);
      for(int i = 0; i < R * Cn; i++)
         if(g_valid[g_base[f] + i])
         {
            int sz = ArraySize(ids);
            ArrayResize(ids, sz + 1);
            ids[sz] = g_base[f] + i;
         }
      int n = ArraySize(ids);
      for(int i = 0; i < n - 1; i++)
         for(int j = i + 1; j < n; j++)
            if(g_score[ids[j]] > g_score[ids[i]]) { int t = ids[i]; ids[i] = ids[j]; ids[j] = t; }
      HW("<h3>" + FamName(f) + "</h3><table><tr><th class='rl'>Cella</th><th>Punteggio</th><th>N IS</th><th>Win IS</th><th>E[R] IS</th><th>t IS</th><th>N OOS</th><th>Win OOS</th><th>E[R] OOS</th><th>t OOS</th><th>PF OOS</th><th>Ambig. %</th><th>Fine orizz. %</th></tr>");
      for(int i = 0; i < MathMin(10, n); i++)
      {
         int c = ids[i];
         double amb = (g_stAll[c].n > 0) ? 100.0 * g_stAll[c].amb / g_stAll[c].n : 0.0;
         double tmo = (g_stAll[c].n > 0) ? 100.0 * g_stAll[c].tmo / g_stAll[c].n : 0.0;
         HW("<tr><th class='rl'>" + CellDesc(c) + "</th><td>" + F(g_score[c], 2) + "</td><td>" + IntegerToString(g_stIS[c].n) + "</td><td>" + F(StatWR(g_stIS[c]), 1) + "%</td><td>" +
            F(StatMean(g_stIS[c]), 3) + "</td><td>" + F(StatT(g_stIS[c]), 2) + "</td><td>" + IntegerToString(g_stOOS[c].n) + "</td><td>" + F(StatWR(g_stOOS[c]), 1) + "%</td><td>" +
            F(StatMean(g_stOOS[c]), 3) + "</td><td>" + F(StatT(g_stOOS[c]), 2) + "</td><td>" + PfStr(StatPF(g_stOOS[c])) + "</td><td>" + F(amb, 1) + "</td><td>" + F(tmo, 1) + "</td></tr>\n");
      }
      HW("</table>");
   }
   HW("<div class='note'>Ambig. % = quota di trade il cui esito dipende dall'ordine con cui SL/TP (o il trailing) sono stati toccati dentro la stessa barra. Se &egrave; alta, rilancia con TF di simulazione pi&ugrave; fine.</div>");
}

void HtmlEquity(const int &fin[], const string &names[], const int nf)
{
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);
   if(E < 2 || nf < 1) return;
   string cols[6] = {"#1f6feb", "#d1242f", "#1a7f37", "#9a6700", "#8250df", "#57606a"};
   double mn = 0.0, mx = 0.0;
   double cum[];
   ArrayResize(cum, E * nf);
   for(int i = 0; i < nf; i++)
   {
      double eq = 0.0;
      for(int e = 0; e < E; e++)
      {
         eq += (double)g_R[e * C + fin[i]];
         cum[i * E + e] = eq;
         if(eq < mn) mn = eq;
         if(eq > mx) mx = eq;
      }
   }
   if(mx - mn < 1e-9) mx = mn + 1.0;
   int W = 1000, H = 300, pad = 10;
   HW("<svg width='" + IntegerToString(W) + "' height='" + IntegerToString(H) + "' viewBox='0 0 " + IntegerToString(W) + " " + IntegerToString(H) + "'>");
   double y0 = pad + (H - 2 * pad) * (mx - 0.0) / (mx - mn);
   HW("<line x1='0' x2='" + IntegerToString(W) + "' y1='" + F(y0, 1) + "' y2='" + F(y0, 1) + "' stroke='#d0d7de'/>");
   double xs = (double)W * g_split / E;
   HW("<line x1='" + F(xs, 1) + "' x2='" + F(xs, 1) + "' y1='0' y2='" + IntegerToString(H) + "' stroke='#8c959f' stroke-dasharray='4 4'/>");
   HW("<text x='" + F(xs + 6, 1) + "' y='14' font-size='11' fill='#59636e'>OOS &rarr;</text>");
   for(int i = 0; i < nf; i++)
   {
      string pts = "";
      int step = MathMax(1, E / 800);
      for(int e = 0; e < E; e += step)
      {
         double x = (double)W * e / (E - 1);
         double y = pad + (H - 2 * pad) * (mx - cum[i * E + e]) / (mx - mn);
         pts += F(x, 1) + "," + F(y, 1) + " ";
      }
      HW("<polyline fill='none' stroke='" + cols[i % 6] + "' stroke-width='1.6' points='" + pts + "'/>");
   }
   HW("</svg><div class='legend note'>");
   for(int i = 0; i < nf; i++) HW("<span><b style='color:" + cols[i % 6] + "'>&mdash;</b> " + names[i] + "</span>");
   HW("</div><div class='note'>Equity cumulata in R (un trade = 1R di rischio, nessun compounding), eventi in ordine cronologico. A sinistra della linea tratteggiata il campione con cui le celle sono state scelte.</div>");
}

void HtmlStability()
{
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);
   HW("<h2>7. Stabilit&agrave; nel tempo e curve di equity</h2>");

   int fin[6];
   string names[6];
   int nf = 0;
   for(int f = 0; f < 5; f++)
   {
      if(g_best[f] < 0) continue;
      fin[nf] = g_best[f];
      names[nf] = FamName(f) + ": " + CellDesc(g_best[f]);
      nf++;
   }
   if(nf == 0) return;
   HtmlEquity(fin, names, nf);

   MqlDateTime d0, d1;
   TimeToStruct(g_ev[0].time, d0);
   TimeToStruct(g_ev[E - 1].time, d1);
   HW("<h3>E[R] per anno solare (N trade)</h3><table><tr><th>Anno</th>");
   for(int i = 0; i < nf; i++) HW("<th>" + FamName((g_cfg[fin[i]].fam)) + "</th>");
   HW("</tr>\n");
   for(int y = d0.year; y <= d1.year; y++)
   {
      HW("<tr><th>" + IntegerToString(y) + "</th>");
      for(int i = 0; i < nf; i++)
      {
         double sum = 0.0;
         int n = 0;
         for(int e = 0; e < E; e++)
         {
            MqlDateTime dt;
            TimeToStruct(g_ev[e].time, dt);
            if(dt.year != y) continue;
            sum += (double)g_R[e * C + fin[i]];
            n++;
         }
         string bg = (n >= 10) ? " style='background:" + Heat(sum / n, 0.3) + "'" : "";
         HW("<td" + bg + ">" + (n > 0 ? F(sum / n, 3) + " (" + IntegerToString(n) + ")" : "-") + "</td>");
      }
      HW("</tr>\n");
   }
   HW("</table><div class='note'>Un edge reale non deve vivere in un solo anno. Anni con meno di 10 trade non sono colorati.</div>");
}

void HtmlNotes()
{
   HW("<h2>8. Come leggere questo report e cosa NON dimostra</h2><ul>");
   HW("<li>Il segnale replica la parte <b>tecnica</b> dell'EA (profilo sviluppato, VAL/VAH, POC strict, Hull, tocchi, rigetto). Il filtro ML &egrave; escluso: i suoi pesi sono addestrati sugli stessi esiti, misurarlo qui sarebbe circolare.</li>");
   HW("<li>Ingresso a mercato all'apertura della barra successiva, spread costante per trade (da barra o fisso) + commissione. Slippage e allargamenti di spread nei momenti critici non sono modellati: i risultati reali saranno peggiori.</li>");
   HW("<li>Ordine intrabarra: " + Pick(InpOptimistic, "OTTIMISTA (TP prima di SL)", "PESSIMISTA (SL prima di TP; nel trailing prima si alza lo stop e poi si testa l'estremo avverso)") +
      ". TF di simulazione usato: " + EnumToString(g_simTF) + ". Con M1 l'ambiguit&agrave; &egrave; trascurabile; a TF grossolano le colonne &laquo;Ambig. %&raquo; ti dicono quanto pesa.</li>");
   HW("<li>Orizzonte " + IntegerToString(InpMaxHoldBars) + " barre del grafico, poi uscita a mercato. L'EA non ha time-stop: le posizioni lunghe dell'EA reale non sono qui.</li>");
   HW("<li>Gli eventi non sono indipendenti (stesse sessioni, stessa volatilit&agrave;). " + Pick(InpOneSignalPerSession, "Un evento per direzione e sessione (come intende l'EA) riduce il problema", "Con pi&ugrave; eventi per sessione il problema &egrave; grave") +
      " ma non lo elimina: i t-stat restano ottimistici.</li>");
   HW("<li>R-multipli: confrontabili tra famiglie solo se il sizing &egrave; a rischio fisso per trade (UseFixedRisk = true nell'EA). Con lotti fissi un SL pi&ugrave; largo pesa di pi&ugrave; in denaro.</li>");
   HW("<li>ATR: qui &egrave; l'ATR della barra segnale gi&agrave; chiusa (SMA del true range, come iATR). L'EA lo legge alla barra appena aperta (shift 0), che contiene un true range quasi nullo, quindi il suo ATR &egrave; circa 1/" + IntegerToString(InpATRPeriod) + " pi&ugrave; piccolo: con lo stesso moltiplicatore l'EA user&agrave; distanze lievemente pi&ugrave; corte.</li>");
   HW("<li>La griglia in punti usa SL/trailing fissi in prezzo; quella ATR li adatta alla volatilit&agrave; di ogni evento. In automatico i punti derivano dall'ATR mediano, cos&igrave; le due griglie sono confrontabili e la differenza isola &laquo;fisso contro adattivo&raquo;.</li>");
   HW("<li>La logica &laquo;un segnale per sessione&raquo; qui segue l'intento dell'EA. Nell'EA l'array g_Signals ha 160 posti e non viene mai ripulito: dopo 160 sessioni tradate il filtro smette di funzionare nei backtest lunghi.</li>");
   HW("</ul>");
}

void WriteHtml()
{
   string fn = InpFilePrefix + "_" + _Symbol + "_" + EnumToString(g_chartTF) + ".html";
   g_fh = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(g_fh == INVALID_HANDLE) { Print("Errore: impossibile creare ", fn, " (", GetLastError(), ")"); return; }

   int E = ArraySize(g_ev);
   HtmlStart();
   HW("<h1>VP RR Study - " + _Symbol + " " + EnumToString(g_chartTF) + "</h1>");
   HW("<div class='note'>Dati " + TimeToString(g_dataFirst, TIME_DATE) + " &rarr; " + TimeToString(g_dataLast, TIME_DATE) + " | eventi: <b>" + IntegerToString(E) + "</b> (long " +
      IntegerToString(CountDir(1)) + ", short " + IntegerToString(CountDir(-1)) + ") | IS: " + IntegerToString(g_split) + " eventi fino al " + TimeToString(g_ev[MathMax(0, g_split - 1)].time, TIME_DATE) +
      ", OOS: " + IntegerToString(E - g_split) + " | simulazione " + EnumToString(g_simTF) + " | orizzonte " + IntegerToString(InpMaxHoldBars) + " barre | spread " +
      (InpSpreadPoints >= 0 ? IntegerToString(InpSpreadPoints) + " pt fissi" : "da barra") + " + comm. " + F(InpCommissionPoints, 1) + " pt | ATR mediano " + F(g_medATRpts, 0) + " punti</div>");
   for(int i = 0; i < ArraySize(g_warn); i++) HW("<div class='warn'>" + g_warn[i] + "</div>");
   if(E < 150) HW("<div class='warn'>Meno di 150 eventi: le griglie sono rumore. Allunga lo storico (InpMonthsBack), usa un TF pi&ugrave; basso o allenta i filtri del segnale.</div>");
   if(E - g_split < 30) HW("<div class='warn'>Meno di 30 eventi in OOS: il verdetto OOS non &egrave; affidabile.</div>");

   HtmlVerdict();
   HtmlEventStudy();
   HtmlBreakdown();

   HW("<h2>4. Rischio/rendimento con SL e TP in PUNTI FISSI</h2>");
   HW("<div class='note'>Righe: SL in punti (tra parentesi il multiplo dell'ATR mediano). Colonne: RR 1:x (TP = x &middot; SL). Celle tenui = meno di " + IntegerToString(InpMinTrades) +
      " trade IS. Contorno blu = cella scelta (IS). Il win rate &egrave; colorato rispetto al breakeven 1/(1+RR): ci&ograve; che conta &egrave; lo scarto, non il valore assoluto.</div>");
   HtmlMatrix("Expectancy (R) - In-Sample", "", 0, 0, 0);
   HtmlMatrix("Expectancy (R) - Out-Of-Sample", "", 0, 0, 1);
   HtmlMatrix("Win rate - tutto il campione", "", 0, 1, 2);
   HtmlMatrix("Profit factor - tutto il campione", "", 0, 2, 2);
   HtmlMatrix("t-stat dell'expectancy - tutto il campione", "", 0, 3, 2);
   HtmlMatrix("Max drawdown (R) - tutto il campione", "", 0, 4, 2);

   HW("<h2>5. Rischio/rendimento con SL e TP in ATR (adattivi)</h2>");
   HW("<div class='note'>Come sopra, ma SL = moltiplicatore x ATR del grafico al momento del segnale.</div>");
   HtmlMatrix("Expectancy (R) - In-Sample", "", 1, 0, 0);
   HtmlMatrix("Expectancy (R) - Out-Of-Sample", "", 1, 0, 1);
   HtmlMatrix("Win rate - tutto il campione", "", 1, 1, 2);
   HtmlMatrix("Profit factor - tutto il campione", "", 1, 2, 2);
   HtmlMatrix("t-stat dell'expectancy - tutto il campione", "", 1, 3, 2);
   HtmlMatrix("Max drawdown (R) - tutto il campione", "", 1, 4, 2);

   HW("<h2>5b. Trailing stop</h2>");
   HW("<div class='note'>SL iniziale fisso (" + F(InpTrailSLATR, 2) + " ATR, o " + F(g_cfg[g_base[2]].sl / g_point, 0) + " punti in modalit&agrave; punti), " +
      (InpTrailTPRR > 0.0 ? "TP a RR " + F(InpTrailTPRR, 1) : "nessun TP") + ". Righe: soglia di attivazione. Colonne: distanza dello stop dal massimo. Step di aggiornamento = " +
      F(InpTrailStepRatio, 2) + " x distanza. Confronta con la riga SL corrispondente delle tabelle RR fisso: &egrave; il trailing che aggiunge valore oppure no?</div>");
   HW("<h3>Punti</h3>");
   HtmlMatrix("Expectancy (R) - In-Sample", "", 2, 0, 0);
   HtmlMatrix("Expectancy (R) - Out-Of-Sample", "", 2, 0, 1);
   HtmlMatrix("Win rate - tutto il campione", "", 2, 1, 2);
   HtmlMatrix("Profit factor - tutto il campione", "", 2, 2, 2);
   HW("<h3>ATR</h3>");
   HtmlMatrix("Expectancy (R) - In-Sample", "", 3, 0, 0);
   HtmlMatrix("Expectancy (R) - Out-Of-Sample", "", 3, 0, 1);
   HtmlMatrix("Win rate - tutto il campione", "", 3, 1, 2);
   HtmlMatrix("Profit factor - tutto il campione", "", 3, 2, 2);

   HtmlTop10();
   HtmlStability();
   HtmlNotes();
   HW("</body></html>");
   FileClose(g_fh);
   g_fh = INVALID_HANDLE;
   Print("Report HTML: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", fn);
}

int CountDir(const int dir)
{
   int n = 0;
   for(int e = 0; e < ArraySize(g_ev); e++) if(g_ev[e].dir == dir) n++;
   return n;
}

void WriteCSV()
{
   string base = InpFilePrefix + "_" + _Symbol + "_" + EnumToString(g_chartTF);
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);

   int h = FileOpen(base + "_events.csv", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      string head = "time,dir,session,part,entry,atr_pts,spread_pts,va_width_atr,hours_in_profile,dist_level_atr,touches,rejection,mfe_atr,mae_atr,dist_poc_atr,dist_opp_atr,bars_poc,bars_opp";
      for(int i = 0; i < g_nH; i++) head += ",ret_" + IntegerToString(g_hor[i]) + "b_atr";
      for(int i = 0; i < NFP; i++) head += ",fp_" + F(g_fpX[i], 1) + "atr";
      FileWriteString(h, head + "\n");
      for(int e = 0; e < E; e++)
      {
         string ln = TimeToString(g_ev[e].time, TIME_DATE | TIME_MINUTES) + "," + IntegerToString(g_ev[e].dir) + "," + IntegerToString(g_ev[e].sess) + "," + (e < g_split ? "IS" : "OOS") + "," +
                     F(g_ev[e].entry, 6) + "," + F(g_ev[e].atr / g_point, 1) + "," + F(g_ev[e].spread / g_point, 1) + "," + F(g_ev[e].vaw_atr, 3) + "," + F(g_ev[e].hrs, 2) + "," +
                     F(g_ev[e].dist_atr, 3) + "," + IntegerToString(g_ev[e].touches) + "," + F(g_ev[e].rej, 3) + "," + F(g_ev[e].mfe, 3) + "," + F(g_ev[e].mae, 3) + "," +
                     F(g_ev[e].dpoc, 3) + "," + F(g_ev[e].dopp, 3) + "," + IntegerToString(g_ev[e].bpoc) + "," + IntegerToString(g_ev[e].bopp);
         for(int i = 0; i < g_nH; i++) ln += "," + F(g_ev[e].ret[i], 4);
         for(int i = 0; i < NFP; i++) ln += "," + IntegerToString(g_ev[e].fp[i]);
         FileWriteString(h, ln + "\n");
      }
      FileClose(h);
      Print("CSV eventi: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", base, "_events.csv");
   }

   h = FileOpen(base + "_grid.csv", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      FileWriteString(h, "family,row,col,cell,sl,rr_or_tp,act,dist,"
                         "n_is,er_is,wr_is,pf_is,t_is,n_oos,er_oos,wr_oos,pf_oos,t_oos,n_all,er_all,wr_all,pf_all,t_all,dd_all,tmo_pct,amb_pct,score_is\n");
      for(int c = 0; c < C; c++)
      {
         string ln = IntegerToString(g_cfg[c].fam) + "," + IntegerToString(g_cfg[c].row) + "," + IntegerToString(g_cfg[c].col) + ",\"" + CellDesc(c) + "\"," +
                     F(g_cfg[c].sl, 6) + "," + F(g_cfg[c].rr, 2) + "," + F(g_cfg[c].act, 6) + "," + F(g_cfg[c].dist, 6);
         for(int p = 0; p < 3; p++)
         {
            SStat s;
            GetStat(c, p, s);
            ln += "," + IntegerToString(s.n) + "," + F(StatMean(s), 4) + "," + F(StatWR(s), 2) + "," + F(StatPF(s), 3) + "," + F(StatT(s), 3);
         }
         double amb = (g_stAll[c].n > 0) ? 100.0 * g_stAll[c].amb / g_stAll[c].n : 0.0;
         double tmo = (g_stAll[c].n > 0) ? 100.0 * g_stAll[c].tmo / g_stAll[c].n : 0.0;
         ln += "," + F(g_stAll[c].dd, 2) + "," + F(tmo, 2) + "," + F(amb, 2) + "," + F(g_score[c], 3);
         FileWriteString(h, ln + "\n");
      }
      FileClose(h);
      Print("CSV griglia: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", base, "_grid.csv");
   }
}

void PrintSummary()
{
   int E = ArraySize(g_ev);
   Print("=============== VP RR STUDY - RIEPILOGO ===============");
   PrintFormat("%s %s | eventi %d (IS %d / OOS %d) | sim %s | ATR mediano %.0f punti", _Symbol, EnumToString(g_chartTF), E, g_split, E - g_split, EnumToString(g_simTF), g_medATRpts);
   for(int f = 0; f < 5; f++)
   {
      int c = g_best[f];
      if(c < 0) { PrintFormat("%-18s nessuna cella con >=%d trade IS", FamName(f), InpMinTrades); continue; }
      double p;
      string v = Verdict(c, p);
      StringReplace(v, "<span class='bad'>", ""); StringReplace(v, "<span class='ok'>", ""); StringReplace(v, "<span class='mid'>", "");
      StringReplace(v, "</span>", ""); StringReplace(v, "&lt;", "<");
      PrintFormat("%-18s %-34s IS: N=%d E[R]=%.3f t=%.2f | OOS: N=%d E[R]=%.3f t=%.2f p=%.3f | %s",
                  FamName(f), CellDesc(c), g_stIS[c].n, StatMean(g_stIS[c]), StatT(g_stIS[c]),
                  g_stOOS[c].n, StatMean(g_stOOS[c]), StatT(g_stOOS[c]), p, v);
   }
   Print("========================================================");
}

//+------------------------------------------------------------------+
//| OnStart                                                            |
//+------------------------------------------------------------------+
void OnStart()
{
   uint t0 = GetTickCount();
   ArrayResize(g_warn, 0);
   if(!Setup()) return;
   if(!LoadAllData()) { Comment(""); return; }

   BuildATR();
   BuildHull();
   DetectEvents();
   if(IsStopped()) { Comment(""); return; }

   int E = ArraySize(g_ev);
   if(E < 20)
   {
      Comment("");
      PrintFormat("Solo %d eventi: troppo pochi per qualunque statistica. Allunga InpMonthsBack, abbassa InpMinTouchBars o disattiva filtri.", E);
      if(g_dropData > 0) PrintFormat("(%d eventi scartati per mancanza di dati di simulazione: controlla 'Max barre nel grafico' o usa InpSimTF = PERIOD_CURRENT)", g_dropData);
      return;
   }
   if(g_dropData > 0)
      Warn(StringFormat("%d segnali scartati perche' mancano dati di simulazione/orizzonte (ultime barre o buchi di storia %s).", g_dropData, EnumToString(g_simTF)));

   g_nH = 0;
   for(int i = 0; i < NHOR; i++)
      if(g_horAll[i] <= InpMaxHoldBars) { g_hor[g_nH] = g_horAll[i]; g_nH++; }

   g_medATRpts = MedianATRPoints();
   AssignBuckets();
   BuildConfigs();
   SimulateAll();
   if(IsStopped()) { Comment(""); return; }
   AggregateAll();
   ScoreCells();

   Comment("VP RR Study: scrittura report...");
   if(InpWriteHTML) WriteHtml();
   if(InpWriteCSV) WriteCSV();
   PrintSummary();
   Comment("");
   PrintFormat("Completato in %.1f s", (GetTickCount() - t0) / 1000.0);
}
//+------------------------------------------------------------------+
