//+------------------------------------------------------------------+
//|  MDRB_Study_v1.0.mq5                                             |
//|  SCRIPT di studio statistico per MultiDayRangeBreakout (v3.00)    |
//|  (si trascina su un grafico, gira UNA volta sulla storia e         |
//|  termina; non apre ordini).                                       |
//|                                                                    |
//|  L'EA piazza ogni giorno, nella finestra di entrata, un BuyStop    |
//|  sopra e un SellStop sotto un range (OCO). Questo script           |
//|  ricostruisce sulla storia ESATTAMENTE quel meccanismo (calcolo    |
//|  del range, finestra oraria, attesa se il prezzo e' fuori livello, |
//|  scadenza degli ordini, riempimento con gap, un solo trade al      |
//|  giorno, nessun nuovo ordine se una posizione e' aperta) e misura: |
//|  1. come si comporta il prezzo DOPO lo sfondamento (lordo di       |
//|     costi): rendimento per orizzonte, MFE/MAE, +X/-X ATR, falsi    |
//|     breakout (ritorno sul bordo opposto del range);                |
//|  2. quali range funzionano meglio: per larghezza (ATR e punti),    |
//|     giorno della settimana, direzione; e uno sweep delle           |
//|     DEFINIZIONI di range e delle FINESTRE ORARIE di ingresso;      |
//|  3. tabelle RR 1:1..1:N con SL in PUNTI fissi, in ATR e in         |
//|     multipli del range; griglie di TRAILING (attivazione x         |
//|     distanza) in punti e in ATR; e la configurazione di uscita     |
//|     ESATTA dell'EA (SL/TP + break-even + trailing dai suoi input). |
//|  Con disciplina anti data-mining: split IS/OOS cronologico, la     |
//|  cella migliore si sceglie solo sull'IS, p-value sull'OOS,         |
//|  soglia di Bonferroni, stabilita' annuale, equity.                 |
//|  Output: report HTML + CSV in MQL5/Files, riepilogo nel log.       |
//+------------------------------------------------------------------+
#property copyright "Advanced Quant Systems - MDRB Study v1.0"
#property version   "1.00"
#property strict
#property script_show_inputs

//=== RANGE (stessi nomi e significato dell'EA) ===
input group "=== RANGE (come EA) ==="
enum ENUM_RANGE_MODE
  {
   RANGE_BARS    = 0,
   RANGE_TIME    = 1,
   RANGE_PREV_D1 = 2
  };
input ENUM_RANGE_MODE RangeMode = RANGE_BARS;
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;  // TF delle barre del range (PERIOD_CURRENT = TF del grafico)
input int RangeDaysBack = 1;
input int RangeBarsLookback = 25;
input int RangeHourStart = 16;
input int RangeMinuteStart = 0;
input int RangeHourEnd = 0;
input int RangeMinuteEnd = 0;
input int RangeDaySpan = 1;
input bool RequireRangeConfirmation = false;       // EA: true. Qui false = studia TUTTE le larghezze, poi scegli Min/Max dalle tabelle
input double MinRangePoints = 50;
input double MaxRangePoints = 500;

//=== FINESTRA DI ENTRATA (come EA) ===
input group "=== FINESTRA DI ENTRATA (come EA, ora server) ==="
input int TradeHourStart = 10;
input int TradeMinuteStart = 0;
input int TradeHourEnd = 11;
input int TradeMinuteEnd = 0;
input int ExpireExtraMinutes = 0;
input int PendingOrderOffsetPoints = 20;
input bool ChaseIfBroken = false;

//=== USCITE DELL'EA (configurazione di riferimento) ===
input group "=== USCITE DELL'EA (riga 'EA' del report) ==="
input double StopLossPoints = 100;
input double TakeProfitPoints = 200;
input bool UseTakeProfit = true;
input bool UsaBreakEven = true;
input int BreakEvenAttivazione = 100;
input int BreakEvenOffset = 10;
input bool UsaTrailingStop = true;
input int TrailingStartProfit = 150;
input int TrailingStep = 20;
input int TrailingOffset = 30;

//=== STUDIO ===
input group "=== STUDIO ==="
input int    InpMonthsBack = 60;                    // Mesi di storia da analizzare (0 = tutta quella disponibile)
input ENUM_TIMEFRAMES InpSimTF = PERIOD_M1;         // TF di simulazione; se la storia non copre >=60% ripiega su M5, M15, M30, H1
input ENUM_TIMEFRAMES InpATRTimeframe = PERIOD_H1;  // TF dell'ATR usato per SL/TP in ATR (l'EA non usa ATR)
input int    InpATRPeriod = 14;
input int    InpMaxHoldHours = 72;                  // Orizzonte massimo di una posizione; poi uscita a mercato (l'EA non ha time-stop)
input int    InpISPercent = 70;                     // % di trade (cronologici) In-Sample; il resto e' Out-Of-Sample
enum ENUM_RANK_BY { RANK_TSTAT, RANK_EXPECTANCY, RANK_PF };
input ENUM_RANK_BY InpRankBy = RANK_TSTAT;          // Metrica per scegliere la cella migliore (sull'IS)
input bool   InpSmoothRank = true;                  // Punteggio = media della cella e dei vicini 3x3 (penalizza i picchi isolati)
input int    InpMinTrades = 30;                     // Minimo trade IS per candidare una cella
input bool   InpOptimistic = false;                 // Ordine intrabarra OTTIMISTA (TP prima di SL). Default: pessimista

//=== COSTI ===
input group "=== COSTI ==="
input int    InpSpreadPoints = -1;                  // Spread in punti (-1 = usa lo spread registrato nella barra)
input double InpCommissionPoints = 0.0;             // Commissione round-turn in punti

//=== GRIGLIA RR ===
input group "=== GRIGLIA SL x RR ==="
input string InpSLMultList = "0.5,0.75,1,1.5,2,3";   // SL in multipli di ATR (max 16 valori)
input string InpSLPointsList = "";                  // SL in punti separati da virgola; vuoto = automatico (multipli x ATR mediano)
input string InpSLRangeList = "0.25,0.5,0.75,1,1.5"; // SL in multipli della larghezza del range (1 = bordo opposto)
input double InpRRMin = 1.0;
input double InpRRMax = 6.0;
input double InpRRStep = 1.0;

//=== GRIGLIA TRAILING ===
input group "=== GRIGLIA TRAILING ==="
input double InpTrailSLATR = 1.0;                   // SL iniziale in ATR (modalita' ATR)
input int    InpTrailSLPoints = 0;                  // SL iniziale in punti (0 = ATR mediano x InpTrailSLATR)
input string InpTrailActList = "0.5,1,1.5,2,3";     // Attivazione in multipli di ATR
input string InpTrailDistList = "0.5,0.75,1,1.5,2"; // Distanza trailing in multipli di ATR
input string InpTrailActPoints = "";                // Attivazione in punti; vuoto = automatico
input string InpTrailDistPoints = "";               // Distanza in punti; vuoto = automatico
input double InpTrailStepRatio = 0.15;              // Step minimo = ratio x distanza
input double InpTrailTPRR = 0.0;                    // TP in multipli dello SL durante il trailing (0 = nessun TP)

//=== RIFERIMENTO PER LE TABELLE PER RANGE E GLI SWEEP ===
input group "=== CONFIGURAZIONE DI RIFERIMENTO (tabelle per range, sweep) ==="
input double InpRefSLATR = 1.0;
input double InpRefRR = 2.0;

//=== SWEEP ===
input group "=== SWEEP delle definizioni (ogni riga e' un'ipotesi in piu': leggi la soglia di Bonferroni) ==="
input bool   InpSweepRange = true;                  // Sweep delle definizioni di range (per il RangeMode scelto)
input string InpSweepBarsLookback = "10,15,25,40,60,96"; // RANGE_BARS: numero di barre
input string InpSweepTimeWindows = "00:00-08:00,02:00-10:00,08:00-16:00,16:00-00:00"; // RANGE_TIME: finestre HH:MM-HH:MM
input string InpSweepDaySpans = "1,2,3,5";          // RANGE_PREV_D1: giorni
input string InpSweepDaysBackList = "0,1";          // RangeDaysBack da provare (RANGE_PREV_D1 usa solo valori >=1)
input bool   InpSweepEntryHours = true;             // Sweep della finestra oraria di ingresso (stesso range dell'EA)
input int    InpSweepEntryLenMin = 60;              // durata delle finestre di ingresso provate
input int    InpSweepEntryStepMin = 60;             // passo di partenza delle finestre (>= 30)

//=== OUTPUT ===
input group "=== OUTPUT ==="
input bool   InpWriteHTML = true;
input bool   InpWriteCSV = true;
input string InpFilePrefix = "MDRB_Study";

//--- Costanti
#define EPSILON  0.0000001
#define MAXDIM   16
#define MAXFAM   6
#define NHOR     8
#define NFP      5
#define NFR      3
#define MAXSWEEP 64
#define XR_SKIP  9999.0f      // marcatore: trade non eseguito (posizione ancora aperta)

const double g_fpX[NFP] = {0.5, 1.0, 1.5, 2.0, 3.0};     // soglie first-passage in ATR
const double g_frX[NFR] = {0.25, 0.5, 1.0};              // soglie first-passage in multipli del range
const int    g_horAllH[NHOR] = {1, 2, 4, 8, 12, 24, 48, 72};

//--- Strutture
struct SDef
{
   int  mode;
   int  daysBack;
   int  lookback;
   int  rhs, rms, rhe, rme;   // RANGE_TIME
   int  span;                 // RANGE_PREV_D1
   int  wsMin, weMin;         // finestra di entrata (minuti del giorno)
   int  extra;
   int  offsetPts;
   bool chase;
};

struct SFunnel
{
   int days;       // giorni analizzati (con dati di simulazione)
   int noRange;    // range non calcolabile
   int tooSmall;
   int tooBig;
   int invalid;    // range nullo / nessuna barra
   int noPlace;    // prezzo sempre fuori dai livelli: coppia mai piazzata
   int noFill;     // coppia piazzata ma scaduta senza riempimento
   int noATR;
   int noData;     // orizzonte non disponibile (fine dati)
   int filled;
   int longs;
   int shorts;
   int ambTrig;    // barra di innesco che toccava entrambi i livelli
   int blocked;    // coppia del giorno precedente ancora viva (finestre a cavallo)
};

struct SEvent
{
   int      di;         // indice del giorno D1
   datetime day;
   datetime tPlace;
   datetime tFill;
   int      dir;        // +1 long, -1 short
   int      jp;         // barra di piazzamento (TF simulazione)
   int      jt;         // barra di innesco
   double   E0;         // riferimento bid: ingresso long = E0 + spread, ingresso short = E0
   double   delta;      // slippage di gap sul riempimento (prezzo)
   double   spread;     // prezzo
   double   hi, lo, width;
   double   buyPx, sellPx;
   double   atr;
   int      wday;
   double   widthAtr;
   double   delayMin;
   int      ambTrig;
   double   mfe, mae;   // in ATR, lordi
   int      fakeout;    // 1 se raggiunge il bordo opposto del range
   double   fakeHrs;    // ore al falso breakout (-1 = mai)
   int      fp[NFP];    // first-passage in ATR
   int      fr[NFR];    // first-passage in multipli del range
   double   ret[NHOR];  // rendimento direzionale in ATR a fine orizzonte (ore)
   int      bw, bd;
};

struct SCfg
{
   int    fam;     // 0 fisso punti, 1 fisso ATR, 2 fisso range, 3 trailing punti, 4 trailing ATR, 5 uscita EA
   int    kind;    // 0 SL/TP fissi, 1 trailing, 2 EA esatto
   int    row, col;
   int    unit;    // 0 prezzo, 1 multiplo ATR, 2 multiplo range
   double sl;
   double rr;
   double act;
   double dist;
};

struct SStat
{
   int    n;
   int    wins;
   int    tmo;
   int    amb;
   double sum, sum2;
   double gp, gl;
   double eq, peak, dd;
};

//--- Dati
MqlRates g_d1[];           // D1
MqlRates g_rr[];           // barre del range (Timeframe)
MqlRates g_ra[];           // barre per l'ATR
MqlRates g_rs[];           // TF simulazione
double   g_atrA[];
ENUM_TIMEFRAMES g_chartTF, g_simTF, g_rangeTF, g_atrTF;
int      g_perSim = 60, g_L = 0;
double   g_point = 0.0, g_ts = 0.0, g_stopLvl = 0.0, g_tol = 0.0;   // g_tol: tolleranza sui confronti con soglie su griglia di punti
datetime g_dataFirst = 0, g_dataLast = 0;
int      g_wsMin = 0, g_weMin = 0;

//--- Eventi principali
SDef     g_def;
SEvent   g_ev[];
SFunnel  g_fn;
int      g_nH = 0;
int      g_hor[NHOR];
double   g_wEdge[4];
double   g_dEdge[2];
double   g_medATRpts = 0.0;
int      g_split = 0;

//--- Configurazioni e risultati
SCfg     g_cfg[];
int      g_dimR[MAXFAM], g_dimC[MAXFAM], g_base[MAXFAM];
string   g_rowLbl[MAXFAM][MAXDIM];
string   g_colLbl[MAXFAM][MAXDIM];
float    g_R[];
uchar    g_F[];
int      g_XJ[];
SStat    g_stIS[], g_stOOS[], g_stAll[];
int      g_skip[];
int      g_repl[];
float    g_xR[];
datetime g_xT[];
int      g_xD[];
double   g_score[];
bool     g_valid[];
int      g_best[MAXFAM];
int      g_refIdx = -1;

//--- Sweep
string   g_s1Lbl[], g_s2Lbl[];
int      g_s1N[], g_s2N[];
SStat    g_s1IS[], g_s1OOS[], g_s1All[];
SStat    g_s2IS[], g_s2OOS[], g_s2All[];
SFunnel  g_s1Fn[], g_s2Fn[];

//--- Buffer di percorso
double   g_wO[], g_wF[], g_wA[], g_wC[];
double   g_a0raw = 0.0;      // estremo avverso REALE della barra di innesco (g_wA[0] ne e' una stima dalla chiusura)

//--- Output
int      g_fh = INVALID_HANDLE;
string   g_warn[];

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

// lista di interi >= 0 (ammette 0)
int ParseIntList(const string s, int &out[])
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
      int v = (int)StringToInteger(t);
      if(v < 0) continue;
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

// "HH:MM-HH:MM,HH:MM-HH:MM"
int ParseWindows(const string s, int &hs[], int &ms[], int &he[], int &me[])
{
   ArrayResize(hs, 0); ArrayResize(ms, 0); ArrayResize(he, 0); ArrayResize(me, 0);
   string parts[];
   int n = StringSplit(s, ',', parts);
   for(int i = 0; i < n; i++)
   {
      if(ArraySize(hs) >= MAXDIM) break;
      string t = parts[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      string ab[];
      if(StringSplit(t, '-', ab) != 2) continue;
      int h1, m1, h2, m2;
      if(!ParseHM(ab[0], h1, m1) || !ParseHM(ab[1], h2, m2)) continue;
      int sz = ArraySize(hs);
      ArrayResize(hs, sz + 1); ArrayResize(ms, sz + 1); ArrayResize(he, sz + 1); ArrayResize(me, sz + 1);
      hs[sz] = h1; ms[sz] = m1; he[sz] = h2; me[sz] = m2;
   }
   return ArraySize(hs);
}

double ErfcApprox(const double x)
{
   double z = MathAbs(x);
   double t = 1.0 / (1.0 + 0.5 * z);
   double ans = t * MathExp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 +
                t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 +
                t * (-0.82215223 + t * 0.17087277)))))))));
   return (x >= 0.0) ? ans : 2.0 - ans;
}

double NormUpper(const double z)
{
   return 0.5 * ErfcApprox(z / MathSqrt(2.0));
}

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

string HHMM(const int minutes)
{
   int m = minutes % 1440;
   return StringFormat("%02d:%02d", m / 60, m % 60);
}

double NormPrice(const double p)
{
   return NormalizeDouble(MathRound(p / g_ts) * g_ts, _Digits);
}

//+------------------------------------------------------------------+
//| Ricerca binaria sui tempi                                          |
//+------------------------------------------------------------------+
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

int SimSpreadPts(const int j)
{
   int s = g_rs[j].spread;
   if(s <= 0) s = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return MathMax(0, s);
}

double SpreadAt(const int j)
{
   if(InpSpreadPoints >= 0) return InpSpreadPoints * g_point;
   return SimSpreadPts(j) * g_point;
}

void MakeMainDef()
{
   g_def.mode = (int)RangeMode;
   g_def.daysBack = RangeDaysBack;
   g_def.lookback = RangeBarsLookback;
   g_def.rhs = RangeHourStart; g_def.rms = RangeMinuteStart;
   g_def.rhe = RangeHourEnd;   g_def.rme = RangeMinuteEnd;
   g_def.span = RangeDaySpan;
   g_def.wsMin = g_wsMin;
   g_def.weMin = g_weMin;
   g_def.extra = ExpireExtraMinutes;
   g_def.offsetPts = PendingOrderOffsetPoints;
   g_def.chase = ChaseIfBroken;
}

bool Setup()
{
   g_chartTF = (ENUM_TIMEFRAMES)_Period;
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_ts <= 0.0) g_ts = g_point;
   g_stopLvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   g_tol = g_point * 0.001;
   if(g_point <= 0.0) { Print("Errore: point non valido"); return false; }

   g_rangeTF = (Timeframe == PERIOD_CURRENT) ? g_chartTF : Timeframe;
   g_atrTF = (InpATRTimeframe == PERIOD_CURRENT) ? g_chartTF : InpATRTimeframe;
   g_simTF = (InpSimTF == PERIOD_CURRENT) ? g_chartTF : InpSimTF;

   if(TradeHourStart < 0 || TradeHourStart > 23 || TradeHourEnd < 0 || TradeHourEnd > 24 || TradeMinuteStart < 0 || TradeMinuteStart > 59 || TradeMinuteEnd < 0 || TradeMinuteEnd > 59)
   { Print("Errore: orario della finestra di entrata non valido"); return false; }
   g_wsMin = TradeHourStart * 60 + TradeMinuteStart;
   g_weMin = TradeHourEnd * 60 + TradeMinuteEnd;
   if(g_wsMin == g_weMin || (g_wsMin == 0 && g_weMin == 0)) { Print("Errore: finestra di entrata vuota"); return false; }
   if(g_weMin == 0) g_weMin = 1440;
   if(ExpireExtraMinutes < 0) { Print("Errore: ExpireExtraMinutes negativo"); return false; }

   if(StopLossPoints <= 0.0) { Print("Errore: StopLossPoints deve essere > 0"); return false; }
   if(InpMaxHoldHours < 1) { Print("Errore: InpMaxHoldHours minimo 1"); return false; }
   if(InpISPercent < 10 || InpISPercent > 95) { Print("Errore: InpISPercent 10-95"); return false; }
   if(InpRRMin <= 0.0 || InpRRMax < InpRRMin || InpRRStep <= 0.0) { Print("Errore: parametri RR non validi"); return false; }
   if(InpATRPeriod < 1) { Print("Errore: ATR period minimo 1"); return false; }
   if(InpSweepEntryStepMin < 30 || InpSweepEntryLenMin < 15) { Print("Errore: sweep ingresso: passo >= 30 e durata >= 15 minuti"); return false; }
   if(RangeMode == RANGE_BARS && RangeBarsLookback < 1) { Print("Errore: RangeBarsLookback minimo 1"); return false; }
   if(RangeMode == RANGE_PREV_D1 && (RangeDaysBack < 1 || RangeDaySpan < 1)) { Print("Errore: RANGE_PREV_D1 richiede RangeDaysBack>=1 e RangeDaySpan>=1"); return false; }
   if(RangeMode == RANGE_TIME && (RangeHourStart < 0 || RangeHourStart > 23 || RangeHourEnd < 0 || RangeHourEnd > 24 || RangeMinuteStart < 0 || RangeMinuteStart > 59 || RangeMinuteEnd < 0 || RangeMinuteEnd > 59))
   { Print("Errore: orario del range non valido"); return false; }
   MakeMainDef();
   return true;
}

// carica il TF di simulazione provando in ordine InpSimTF, M5, M15, M30, H1
bool LoadSim(datetime from, datetime now)
{
   ENUM_TIMEFRAMES cand[5];
   cand[0] = g_simTF; cand[1] = PERIOD_M5; cand[2] = PERIOD_M15; cand[3] = PERIOD_M30; cand[4] = PERIOD_H1;
   double span = (double)(now - from);
   double bestCov = -1.0;
   ENUM_TIMEFRAMES bestTF = PERIOD_H1;
   for(int c = 0; c < 5; c++)
   {
      if(c > 0 && PeriodSeconds(cand[c]) <= PeriodSeconds(g_simTF)) continue;
      MqlRates tmp[];
      if(!LoadRates(cand[c], from, now, tmp)) continue;
      double cov = (double)(tmp[ArraySize(tmp) - 1].time - tmp[0].time);
      double frac = (span > 0.0) ? cov / span : 1.0;
      if(frac > bestCov)
      {
         bestCov = frac;
         bestTF = cand[c];
         ArrayResize(g_rs, ArraySize(tmp));
         ArrayCopy(g_rs, tmp);
      }
      if(frac >= 0.6)
      {
         if(c > 0)
            Warn(StringFormat("Storia %s insufficiente (max barre terminale: %d): simulo su %s con ordine intrabarra pessimista. Per M1: Strumenti > Opzioni > Grafici > 'Max barre nel grafico' = Illimitato, riavvia, rilancia.",
                              EnumToString(cand[0]), (int)TerminalInfoInteger(TERMINAL_MAXBARS), EnumToString(cand[c])));
         g_simTF = cand[c];
         return true;
      }
   }
   if(bestCov < 0.0) return false;
   g_simTF = bestTF;
   Warn(StringFormat("Nessun TF di simulazione copre il periodo richiesto: uso %s (copertura %.0f%%). Riduci InpMonthsBack o alza 'Max barre nel grafico'.", EnumToString(bestTF), 100.0 * bestCov));
   return true;
}

void BuildATRFor(const MqlRates &r[], const int period, double &atr[])
{
   int n = ArraySize(r);
   ArrayResize(atr, n);
   ArrayInitialize(atr, 0.0);
   if(n < 2) return;
   double tr[];
   ArrayResize(tr, n);
   tr[0] = 0.0;
   for(int i = 1; i < n; i++)
   {
      double hh = MathMax(r[i].high, r[i - 1].close);
      double ll = MathMin(r[i].low,  r[i - 1].close);
      tr[i] = hh - ll;
   }
   double sum = 0.0;
   for(int i = 1; i < n; i++)
   {
      sum += tr[i];
      if(i > period) sum -= tr[i - period];
      if(i >= period) atr[i] = sum / period;
   }
}

bool LoadAllData()
{
   datetime now = TimeCurrent();
   datetime from;
   if(InpMonthsBack > 0) from = now - (datetime)InpMonthsBack * 30 * 86400;
   else from = (datetime)SeriesInfoInteger(_Symbol, PERIOD_D1, SERIES_SERVER_FIRSTDATE);
   datetime fromPad = from - 90 * 86400;     // storico extra per i look-back del range e dell'ATR

   PrintFormat("Dati: %s | max barre terminale: %d", _Symbol, (int)TerminalInfoInteger(TERMINAL_MAXBARS));
   Comment("MDRB Study: caricamento storico...");

   if(!LoadRates(PERIOD_D1, fromPad, now, g_d1)) { Print("Errore: nessun dato D1"); return false; }
   if(!LoadRates(g_rangeTF, fromPad, now, g_rr)) { Print("Errore: nessun dato sul TF del range"); return false; }
   if(!LoadRates(g_atrTF, fromPad, now, g_ra)) { Print("Errore: nessun dato sul TF dell'ATR"); return false; }
   if(!LoadSim(from, now)) { Print("Errore: nessun dato per la simulazione"); return false; }
   if(ArraySize(g_d1) < 60 || ArraySize(g_rs) < 1000) { Print("Errore: storico insufficiente"); return false; }

   g_perSim = PeriodSeconds(g_simTF);
   g_L = MathMax(2, (int)((long)InpMaxHoldHours * 3600 / g_perSim));
   g_dataFirst = g_rs[0].time;
   g_dataLast = g_rs[ArraySize(g_rs) - 1].time;
   BuildATRFor(g_ra, InpATRPeriod, g_atrA);

   PrintFormat("D1: %d giorni | range TF %s: %d barre | ATR TF %s | sim %s: %d barre (%s -> %s) | orizzonte %d barre",
               ArraySize(g_d1), EnumToString(g_rangeTF), ArraySize(g_rr), EnumToString(g_atrTF), EnumToString(g_simTF), ArraySize(g_rs),
               TimeToString(g_dataFirst, TIME_DATE), TimeToString(g_dataLast, TIME_DATE), g_L);
   return true;
}

//+------------------------------------------------------------------+
//| Range (replica di ComputeRange dell'EA)                            |
//| ritorna 1 = valido, 0 = scartato (reason: 1 piccolo, 2 grande,     |
//| 3 nullo/senza barre), -1 = non calcolabile                          |
//+------------------------------------------------------------------+
datetime RangeReadyTime(const SDef &d, const int di)
{
   if(d.mode != (int)RANGE_TIME) return 0;
   int dj = di - d.daysBack;
   if(dj < 0) return 0;
   datetime dayStart = g_d1[dj].time;
   datetime ws = dayStart + d.rhs * 3600 + d.rms * 60;
   datetime we = dayStart + d.rhe * 3600 + d.rme * 60;
   if(we <= ws) we += 86400;
   return we;
}

int ComputeRangeDef(const SDef &d, const int di, const datetime tNow, double &hi, double &lo, int &reason)
{
   hi = -DBL_MAX;
   lo = DBL_MAX;
   reason = 0;
   int nD = ArraySize(g_d1);
   if(d.mode == (int)RANGE_PREV_D1)
   {
      for(int k = 0; k < d.span; k++)
      {
         int idx = di - d.daysBack - k;
         if(idx < 0 || idx >= nD) return -1;
         double h = g_d1[idx].high, l = g_d1[idx].low;
         if(h <= 0.0 || l <= 0.0) return -1;
         hi = MathMax(hi, h);
         lo = MathMin(lo, l);
      }
   }
   else if(d.mode == (int)RANGE_BARS)
   {
      int sIdx;
      if(d.daysBack > 0)
      {
         int dj = di - (d.daysBack - 1);
         if(dj < 0 || dj >= nD) return -1;
         sIdx = BarAtOrBefore(g_rr, g_d1[dj].time - 1);
      }
      else sIdx = BarAtOrBefore(g_rr, tNow) - 1;     // ultime barre chiuse al momento del piazzamento
      if(sIdx < 0 || sIdx - d.lookback + 1 < 0) return -1;
      for(int i = sIdx; i > sIdx - d.lookback; i--)
      {
         double h = g_rr[i].high, l = g_rr[i].low;
         if(h <= 0.0 || l <= 0.0) return -1;
         hi = MathMax(hi, h);
         lo = MathMin(lo, l);
      }
   }
   else
   {
      int dj = di - d.daysBack;
      if(dj < 0 || dj >= nD) return -1;
      datetime dayStart = g_d1[dj].time;
      datetime ws = dayStart + d.rhs * 3600 + d.rms * 60;
      datetime we = dayStart + d.rhe * 3600 + d.rme * 60;
      if(we <= ws) we += 86400;
      if(we > tNow) return -1;
      int s = BarAtOrBefore(g_rr, we - 1);
      if(s < 0) return -1;
      int n = 0;
      for(int i = s; i >= 0; i--)
      {
         datetime bt = g_rr[i].time;
         if(bt < ws) break;
         if(bt >= we) continue;
         double h = g_rr[i].high, l = g_rr[i].low;
         if(h <= 0.0 || l <= 0.0) return -1;
         hi = MathMax(hi, h);
         lo = MathMin(lo, l);
         n++;
      }
      if(n == 0) { reason = 3; return 0; }
   }
   if(!(hi > lo) || lo <= 0.0) { reason = 3; return 0; }
   double pts = (hi - lo) / g_point;
   if(RequireRangeConfirmation)
   {
      if(pts < MinRangePoints) { reason = 1; return 0; }
      if(pts > MaxRangePoints) { reason = 2; return 0; }
   }
   return 1;
}

//+------------------------------------------------------------------+
//| Costruzione del setup di UN giorno (replica di TryPlaceSetup).     |
//| tMin > 0: l'EA non puo' piazzare prima di tMin (la posizione del   |
//| giorno prima si chiude a meta' finestra): range e piazzamento      |
//| ripartono da li'. Ritorna true se il giorno produce uno            |
//| sfondamento (e); altrimenti classifica il motivo in fn.            |
//+------------------------------------------------------------------+
bool BuildDay(const SDef &d, const int di, const datetime tMin, SEvent &e, SFunnel &fn, datetime &prevExpiry)
{
   int nS = ArraySize(g_rs);
   datetime D = g_d1[di].time;

   int np = 0;
   int pS[2], pE[2];
   datetime pX[2];
   int we = d.weMin;
   if(d.wsMin < we)
   {
      np = 1;
      pS[0] = d.wsMin; pE[0] = we; pX[0] = D + (datetime)(we + d.extra) * 60;
   }
   else
   {
      np = 2;
      pS[0] = 0;       pE[0] = we;   pX[0] = D + (datetime)(we + d.extra) * 60;
      pS[1] = d.wsMin; pE[1] = 1440; pX[1] = D + 86400 + (datetime)(we + d.extra) * 60;
   }

   bool rangeDone = false, rangeOK = false;
   double hi = 0.0, lo = 0.0;
   bool placed = false;
   bool counted = false;      // il giorno e' gia' stato classificato nell'imbuto
   bool blockedAny = false;
   bool made = false;
   for(int p = 0; p < np && !placed; p++)
   {
      datetime tS = D + (datetime)pS[p] * 60;
      datetime tE = D + (datetime)pE[p] * 60;
      if(tE <= tS) continue;
      if(tMin > tS) tS = tMin;
      if(tS >= tE) continue;
      if(prevExpiry > tS) { blockedAny = true; continue; }      // coppia del giorno prima ancora viva
      int j0 = LowerBound(g_rs, tS);
      if(j0 >= nS) break;
      if(g_rs[j0].time >= tE) continue;

      if(!rangeDone)
      {
         datetime tRdy = RangeReadyTime(d, di);
         datetime tComp = g_rs[j0].time;
         if(tRdy > tComp)
         {
            int jr = LowerBound(g_rs, tRdy);
            if(jr >= nS || g_rs[jr].time >= tE) continue;     // il range chiude oltre questa porzione di finestra
            j0 = jr;
            tComp = g_rs[jr].time;
         }
         int reason;
         int r = ComputeRangeDef(d, di, tComp, hi, lo, reason);
         if(r < 0) continue;
         rangeDone = true;
         rangeOK = (r == 1);
         if(!rangeOK)
         {
            if(reason == 1) fn.tooSmall++;
            else if(reason == 2) fn.tooBig++;
            else fn.invalid++;
            counted = true;
            break;
         }
      }
      if(!rangeOK) break;

      double buyPx = NormPrice(hi + d.offsetPts * g_point);
      double sellPx = NormPrice(lo - d.offsetPts * g_point);
      int jp = -1;
      bool noBuy = false, noSell = false;      // nella barra di piazzamento: l'estremo gia' avvenuto prima non puo' innescare
      for(int j = j0; j < nS && g_rs[j].time < tE; j++)
      {
         double o = g_rs[j].open, hb = g_rs[j].high, lb = g_rs[j].low;
         double S = SpreadAt(j);
         double ask = o + S, bid = o;
         bool bOK = ((buyPx - ask) > g_stopLvl + g_ts * 0.5);
         bool sOK = ((bid - sellPx) > g_stopLvl + g_ts * 0.5);
         if(bOK && sOK) { jp = j; break; }
         if(d.chase)
         {
            if(!bOK) buyPx = NormPrice(ask + g_stopLvl + 10 * g_point);
            if(!sOK) sellPx = NormPrice(bid - g_stopLvl - 10 * g_point);
            jp = j;
            break;
         }
         // L'EA controlla a ogni tick: la coppia parte appena il prezzo rientra nella zona consentita,
         // anche a meta' barra. Zona (in bid): (sellPx + stopLvl + ts/2, buyPx - S - stopLvl - ts/2).
         double upperBid = buyPx - S - g_stopLvl - g_ts * 0.5;
         double lowerBid = sellPx + g_stopLvl + g_ts * 0.5;
         if(!bOK && sOK && lb < upperBid) { jp = j; noBuy = true; break; }       // prezzo sopra il livello d'acquisto che rientra scendendo
         if(!sOK && bOK && hb > lowerBid) { jp = j; noSell = true; break; }      // prezzo sotto il livello di vendita che rientra salendo
      }
      if(jp < 0) continue;       // prezzo fuori dai livelli per tutta la porzione

      placed = true;
      prevExpiry = pX[p];
      counted = true;

      // riempimento
      int jt = -1, dir = 0, amb = 0;
      double fillDelta = 0.0, E0 = 0.0, Sf = 0.0;
      for(int j = jp; j < nS && g_rs[j].time < pX[p]; j++)
      {
         double o = g_rs[j].open, h = g_rs[j].high, l = g_rs[j].low;
         double S = SpreadAt(j);
         bool bGap = (j > jp && (o + S) + g_tol >= buyPx);
         bool sGap = (j > jp && o <= sellPx + g_tol);
         double c = g_rs[j].close;
         bool bT, sT;
         if(j == jp && noBuy)
         {
            // il massimo e' avvenuto PRIMA del piazzamento: dopo, il percorso e' minimo -> chiusura
            bT = ((c + S) + g_tol >= buyPx);
            sT = (l <= sellPx + g_tol);
         }
         else if(j == jp && noSell)
         {
            sT = (c <= sellPx + g_tol);
            bT = ((h + S) + g_tol >= buyPx);
         }
         else
         {
            bT = bGap || ((h + S) + g_tol >= buyPx);
            sT = sGap || (l <= sellPx + g_tol);
         }
         if(!bT && !sT) continue;
         bool buy;
         if(bT && sT)
         {
            amb = 1;
            if(j == jp && noBuy) buy = false;                     // percorso: minimo prima della chiusura
            else if(j == jp && noSell) buy = true;                // percorso: massimo prima della chiusura
            else if(bGap && !sGap) buy = true;
            else if(sGap && !bGap) buy = false;
            else buy = ((buyPx - (o + S)) < (o - sellPx));      // vince il livello piu' vicino all'apertura
         }
         else buy = bT;
         jt = j;
         Sf = S;
         if(buy)
         {
            double fa = bGap ? (o + S) : buyPx;
            dir = 1;
            fillDelta = fa - buyPx;
            E0 = fa - S;
         }
         else
         {
            double fb = sGap ? o : sellPx;
            dir = -1;
            fillDelta = sellPx - fb;
            E0 = fb;
         }
         break;
      }
      if(jt < 0) { fn.noFill++; break; }
      if(jt + g_L - 1 > nS - 2) { fn.noData++; break; }

      datetime tPlace = g_rs[jp].time;
      int ia = BarAtOrBefore(g_ra, tPlace) - 1;       // ultima barra ATR chiusa prima del piazzamento
      if(ia < 0 || g_atrA[ia] <= EPSILON) { fn.noATR++; break; }
      double atr = g_atrA[ia];

      ZeroMemory(e);
      e.di = di;
      e.day = D;
      e.tPlace = tPlace;
      e.tFill = g_rs[jt].time;
      e.dir = dir;
      e.jp = jp;
      e.jt = jt;
      e.E0 = E0;
      e.delta = fillDelta;
      e.spread = Sf;
      e.hi = hi; e.lo = lo; e.width = hi - lo;
      e.buyPx = buyPx; e.sellPx = sellPx;
      e.atr = atr;
      MqlDateTime dt;
      TimeToStruct(D, dt);
      e.wday = dt.day_of_week;
      e.widthAtr = (hi - lo) / atr;
      e.delayMin = (double)(e.tFill - tPlace) / 60.0;
      e.ambTrig = amb;
      e.fakeHrs = -1.0;
      fn.filled++;
      if(dir > 0) fn.longs++; else fn.shorts++;
      if(amb != 0) fn.ambTrig++;
      made = true;
   }
   if(!made)
   {
      if(!counted && !rangeDone)
      {
         if(blockedAny) fn.blocked++;
         else fn.noRange++;
      }
      else if(!counted && rangeOK && !placed) fn.noPlace++;
   }
   return made;
}

void BuildSetups(const SDef &d, SEvent &ev[], SFunnel &fn)
{
   ZeroMemory(fn);
   ArrayResize(ev, 0);
   int nD1 = ArraySize(g_d1);
   int nS = ArraySize(g_rs);
   datetime lastOK = g_rs[nS - 1].time;
   datetime prevExpiry = 0;
   for(int di = 0; di < nD1 - 1; di++)
   {
      if(IsStopped()) return;
      datetime D = g_d1[di].time;
      if(D + 86400 <= g_dataFirst) continue;     // prima dei dati di simulazione
      if(D > lastOK) break;
      fn.days++;
      SEvent e;
      if(BuildDay(d, di, 0, e, fn, prevExpiry))
      {
         int sz = ArraySize(ev);
         ArrayResize(ev, sz + 1, 1024);
         ev[sz] = e;
      }
   }
}

//+------------------------------------------------------------------+
//| Simulazione di un trade sul percorso gia' caricato in g_w*         |
//|                                                                    |
//| "u" = profitto direzionale rispetto all'ingresso effettivo, al     |
//| netto dello spread: u = dir*(prezzo-E0) - S. Long: entra all'ask   |
//| (= bid + S), esce al bid. Short: entra al bid, esce all'ask.       |
//| SL/TP dell'EA sono relativi al prezzo dell'ORDINE: se il          |
//| riempimento e' peggiorato dal gap di delta, lo SL effettivo e'     |
//| SL+delta e il TP effettivo TP-delta; R e' normalizzato sullo SL    |
//| nominale (Rden). Prima barra = barra di innesco: l'estremo avverso |
//| e' stimato dalla chiusura (non si sa se il minimo e' prima o dopo  |
//| il riempimento).                                                   |
//| Ordine intrabarra PESSIMISTA (default): tick di apertura, minimo   |
//| (SL), massimo (TP, poi salita a gradini di BE/trailing), minimo    |
//| di nuovo contro lo stop aggiornato. Ottimista: TP prima.           |
//| Ritorna 1 = TP, -1 = stop (anche in profitto), 0 = fine orizzonte. |
//| fl: bit0 = fine orizzonte, bit1 = esito dipendente dall'ordine.    |
//| jx = indice della barra di uscita (0 = barra di innesco).          |
//+------------------------------------------------------------------+
int SimFixed(const double S, const double comm, const double SLd, const double TPd, const double Rden,
             double &R, int &fl, int &jx)
{
   fl = 0;
   const double slu = -SLd;
   const bool hasTP = (TPd > 0.0);
   const double tpu = hasTP ? TPd : 0.0;
   if((g_a0raw - S) <= slu + g_tol) fl |= 2;      // il minimo della barra di innesco potrebbe aver toccato lo stop dopo il riempimento
   for(int j = 0; j < g_L; j++)
   {
      double uO = g_wO[j] - S;
      if(uO <= slu + g_tol) { R = (uO - comm) / Rden; jx = j; return -1; }
      if(hasTP && uO >= tpu - g_tol) { R = (uO - comm) / Rden; jx = j; return 1; }
      bool hs = ((g_wA[j] - S) <= slu + g_tol);
      bool ht = hasTP && ((g_wF[j] - S) >= tpu - g_tol);
      if(hs && ht)
      {
         fl |= 2;
         jx = j;
         if(InpOptimistic) { R = (tpu - comm) / Rden; return 1; }
         R = (slu - comm) / Rden;
         return -1;
      }
      if(hs) { R = (slu - comm) / Rden; jx = j; return -1; }
      if(ht) { R = (tpu - comm) / Rden; jx = j; return 1; }
   }
   fl |= 1;
   jx = g_L - 1;
   R = ((g_wC[g_L - 1] - S) - comm) / Rden;
   return 0;
}

// Trailing e break-even dell'EA (ManagePositions) valutati su un percorso di prezzo CONTINUO dentro la barra.
// L'EA controlla a ogni tick: lo stop si sposta SOLO quando "prezzo - distanza" supera lo stop di almeno lo
// step, quindi sale a gradini e resta indietro rispetto al massimo di al piu' uno step; la vicinanza del TP e la
// distanza minima del broker si valutano sul prezzo CORRENTE, non sul massimo. Non e' "massimo - distanza".
// PointUpdate = una valutazione al prezzo p (u: profitto); ritorna il nuovo stop (u) o lo stop invariato.
double PointUpdate(const double sl, const double p, const bool hasTP, const double tpu,
                   const bool beOn, const double beAct, const double beOff,
                   const bool trOn, const double trAct, const double trDist, const double trStep,
                   const double minDist)
{
   double halfPt = 0.5 * g_point;
   if(hasTP && (tpu - p) < minDist - g_tol) return sl;      // TP troppo vicino: l'EA non modifica
   bool have = false;
   double target = 0.0;
   if(beOn && p + g_tol >= beAct)
   {
      if((beOff - sl) >= g_ts - halfPt - g_tol) { target = beOff; have = true; }
   }
   if(trOn && p + g_tol >= trAct)
   {
      double tr = p - trDist;
      if((tr - sl) >= MathMax(g_ts, trStep) - halfPt - g_tol)
      {
         if(!have || tr > target) { target = tr; have = true; }
      }
   }
   if(!have) return sl;
   target = MathMin(target, p - minDist);
   target = MathRound(target / g_ts) * g_ts;               // l'EA arrotonda lo stop al tick (NormPrice)
   if((target - sl) >= g_ts - halfPt - g_tol) return target;
   return sl;
}

// salita continua del prezzo fino a hMax: applica in sequenza gli innesci (BE, poi i gradini del trailing)
double ClimbUpdate(const double sl0, const double hMax, const bool hasTP, const double tpu,
                   const bool beOn, const double beAct, const double beOff,
                   const bool trOn, const double trAct, const double trDist, const double trStep,
                   const double minDist)
{
   double halfPt = 0.5 * g_point;
   double stepEff = MathMax(g_ts, trStep) - halfPt;
   double sl = sl0;
   bool beDone = false;
   for(int guard = 0; guard < 20000; guard++)
   {
      double pBE = DBL_MAX, pTR = DBL_MAX;
      if(beOn && !beDone && (beOff - sl) >= g_ts - halfPt - g_tol) pBE = beAct;
      if(trOn) pTR = MathMax(trAct, sl + trDist + stepEff);
      double p = MathMin(pBE, pTR);
      if(p > hMax + g_tol) break;
      double nsl = PointUpdate(sl, p, hasTP, tpu, beOn, beAct, beOff, trOn, trAct, trDist, trStep, minDist);
      if(nsl <= sl)
      {
         if(p == pBE) { beDone = true; continue; }       // il BE non produce modifiche (es. gia' applicato): passa al trailing
         break;
      }
      sl = nsl;
   }
   return sl;
}

int SimFull(const double S, const double comm, const double SLd, const double TPd, const double Rden,
            const bool beOn, const double beAct, const double beOff,
            const bool trOn, const double trAct, const double trDist, const double trStep,
            const double minDist, double &R, int &fl, int &jx)
{
   fl = 0;
   double sl = -SLd;
   const bool hasTP = (TPd > 0.0);
   const double tpu = hasTP ? TPd : 0.0;
   if((g_a0raw - S) <= sl + g_tol) fl |= 2;       // il minimo della barra di innesco potrebbe aver toccato lo stop dopo il riempimento
   for(int j = 0; j < g_L; j++)
   {
      double uO = g_wO[j] - S;
      double uF = g_wF[j] - S;
      double uA = g_wA[j] - S;
      if(uO <= sl + g_tol) { R = (uO - comm) / Rden; jx = j; return -1; }
      if(hasTP && uO >= tpu - g_tol) { R = (uO - comm) / Rden; jx = j; return 1; }
      // tick di apertura (non nella barra di innesco, dove l'ingresso e' a meta' barra)
      if(j > 0) sl = PointUpdate(sl, uO, hasTP, tpu, beOn, beAct, beOff, trOn, trAct, trDist, trStep, minDist);

      if(!InpOptimistic)
      {
         if(uA <= sl + g_tol)
         {
            if(hasTP && uF >= tpu - g_tol) fl |= 2;
            R = (sl - comm) / Rden; jx = j;
            return -1;
         }
         if(hasTP && uF >= tpu - g_tol) { R = (tpu - comm) / Rden; jx = j; return 1; }
         sl = ClimbUpdate(sl, uF, hasTP, tpu, beOn, beAct, beOff, trOn, trAct, trDist, trStep, minDist);
         if(uA <= sl + g_tol) { fl |= 2; R = (sl - comm) / Rden; jx = j; return -1; }
      }
      else
      {
         if(hasTP && uF >= tpu - g_tol)
         {
            if(uA <= sl + g_tol) fl |= 2;
            R = (tpu - comm) / Rden; jx = j;
            return 1;
         }
         if(uA <= sl + g_tol) { R = (sl - comm) / Rden; jx = j; return -1; }
         sl = ClimbUpdate(sl, uF, hasTP, tpu, beOn, beAct, beOff, trOn, trAct, trDist, trStep, minDist);
      }
   }
   fl |= 1;
   jx = g_L - 1;
   R = ((g_wC[g_L - 1] - S) - comm) / Rden;
   return 0;
}

//+------------------------------------------------------------------+
//| Configurazioni (celle delle griglie)                               |
//+------------------------------------------------------------------+
void AddCfg(const int fam, const int kind, const int row, const int col, const int unit,
            const double sl, const double rr, const double act, const double dist)
{
   int n = ArraySize(g_cfg);
   ArrayResize(g_cfg, n + 1);
   g_cfg[n].fam = fam; g_cfg[n].kind = kind; g_cfg[n].row = row; g_cfg[n].col = col; g_cfg[n].unit = unit;
   g_cfg[n].sl = sl; g_cfg[n].rr = rr; g_cfg[n].act = act; g_cfg[n].dist = dist;
}

string MultStr(const double m)
{
   return DoubleToString(m, 2);
}

void BuildConfigs()
{
   double slm[], slp[], slr[], actm[], distm[], actp[], distp[];
   double rrl[];
   if(ParseList(InpSLMultList, slm) < 1) { ArrayResize(slm, 3); slm[0] = 0.75; slm[1] = 1.0; slm[2] = 1.5; }
   if(ParseList(InpSLRangeList, slr) < 1) { ArrayResize(slr, 3); slr[0] = 0.5; slr[1] = 1.0; slr[2] = 1.5; }
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

   bool autoSL = (ParseList(InpSLPointsList, slp) < 1);
   if(autoSL)
   {
      int m = ArraySize(slm);
      ArrayResize(slp, m);
      for(int i = 0; i < m; i++) slp[i] = MathMax(1.0, MathRound(slm[i] * med));
   }
   if(ParseList(InpTrailActPoints, actp) < 1)
   {
      int m = ArraySize(actm);
      ArrayResize(actp, m);
      for(int i = 0; i < m; i++) actp[i] = MathMax(1.0, MathRound(actm[i] * med));
   }
   if(ParseList(InpTrailDistPoints, distp) < 1)
   {
      int m = ArraySize(distm);
      ArrayResize(distp, m);
      for(int i = 0; i < m; i++) distp[i] = MathMax(1.0, MathRound(distm[i] * med));
   }
   double trailSLp = (InpTrailSLPoints > 0) ? (double)InpTrailSLPoints : MathMax(1.0, MathRound(InpTrailSLATR * med));

   ArrayResize(g_cfg, 0);
   int nrr = ArraySize(rrl);

   // 0: fisso, punti
   g_base[0] = ArraySize(g_cfg);
   g_dimR[0] = ArraySize(slp);
   g_dimC[0] = nrr;
   for(int r = 0; r < g_dimR[0]; r++)
   {
      g_rowLbl[0][r] = StringFormat("SL %d pt (~%.2f ATR)", (int)slp[r], slp[r] / med);
      for(int c = 0; c < nrr; c++)
      {
         if(r == 0) g_colLbl[0][c] = "1:" + F(rrl[c], (rrl[c] == MathFloor(rrl[c])) ? 0 : 2);
         AddCfg(0, 0, r, c, 0, slp[r] * g_point, rrl[c], 0, 0);
      }
   }
   // 1: fisso, ATR
   g_base[1] = ArraySize(g_cfg);
   g_dimR[1] = ArraySize(slm);
   g_dimC[1] = nrr;
   for(int r = 0; r < g_dimR[1]; r++)
   {
      g_rowLbl[1][r] = "SL " + MultStr(slm[r]) + " ATR";
      for(int c = 0; c < nrr; c++)
      {
         if(r == 0) g_colLbl[1][c] = g_colLbl[0][c];
         AddCfg(1, 0, r, c, 1, slm[r], rrl[c], 0, 0);
      }
   }
   // 2: fisso, multipli del range
   g_base[2] = ArraySize(g_cfg);
   g_dimR[2] = ArraySize(slr);
   g_dimC[2] = nrr;
   for(int r = 0; r < g_dimR[2]; r++)
   {
      g_rowLbl[2][r] = "SL " + MultStr(slr[r]) + " x range";
      for(int c = 0; c < nrr; c++)
      {
         if(r == 0) g_colLbl[2][c] = g_colLbl[0][c];
         AddCfg(2, 0, r, c, 2, slr[r], rrl[c], 0, 0);
      }
   }
   // 3: trailing, punti (righe = attivazione, colonne = distanza)
   g_base[3] = ArraySize(g_cfg);
   g_dimR[3] = ArraySize(actp);
   g_dimC[3] = ArraySize(distp);
   for(int r = 0; r < g_dimR[3]; r++)
   {
      g_rowLbl[3][r] = StringFormat("Att. %d pt (~%.2f ATR)", (int)actp[r], actp[r] / med);
      for(int c = 0; c < g_dimC[3]; c++)
      {
         if(r == 0) g_colLbl[3][c] = StringFormat("Dist %d pt (~%.2f)", (int)distp[c], distp[c] / med);
         AddCfg(3, 1, r, c, 0, trailSLp * g_point, InpTrailTPRR, actp[r] * g_point, distp[c] * g_point);
      }
   }
   // 4: trailing, ATR
   g_base[4] = ArraySize(g_cfg);
   g_dimR[4] = ArraySize(actm);
   g_dimC[4] = ArraySize(distm);
   for(int r = 0; r < g_dimR[4]; r++)
   {
      g_rowLbl[4][r] = "Att. " + MultStr(actm[r]) + " ATR";
      for(int c = 0; c < g_dimC[4]; c++)
      {
         if(r == 0) g_colLbl[4][c] = "Dist " + MultStr(distm[c]) + " ATR";
         AddCfg(4, 1, r, c, 1, InpTrailSLATR, InpTrailTPRR, actm[r], distm[c]);
      }
   }
   // 5: uscita dell'EA, esatta
   g_base[5] = ArraySize(g_cfg);
   g_dimR[5] = 1;
   g_dimC[5] = 1;
   g_rowLbl[5][0] = StringFormat("EA: SL %d TP %s", (int)StopLossPoints, UseTakeProfit ? IntegerToString((int)TakeProfitPoints) : "-");
   g_colLbl[5][0] = StringFormat("BE %s trail %s", UsaBreakEven ? IntegerToString(BreakEvenAttivazione) : "off", UsaTrailingStop ? IntegerToString(TrailingStartProfit) : "off");
   AddCfg(5, 2, 0, 0, 0, StopLossPoints * g_point, UseTakeProfit ? TakeProfitPoints / StopLossPoints : 0.0, 0, 0);
   g_refIdx = g_base[5];

   if(autoSL) Print("Nota: SL in punti generati da ATR mediano (", F(med, 0), " punti) x multipli. Per fissare i tuoi valori usa InpSLPointsList.");
}

// configurazioni ridotte per gli sweep: [0] = ATR di riferimento, [1] = uscita dell'EA
void BuildSweepCfgs(SCfg &c[])
{
   ArrayResize(c, 2);
   ZeroMemory(c[0]);
   c[0].fam = 1; c[0].kind = 0; c[0].unit = 1; c[0].sl = InpRefSLATR; c[0].rr = InpRefRR;
   ZeroMemory(c[1]);
   c[1].fam = 5; c[1].kind = 2; c[1].unit = 0; c[1].sl = StopLossPoints * g_point;
   c[1].rr = UseTakeProfit ? TakeProfitPoints / StopLossPoints : 0.0;
}

//+------------------------------------------------------------------+
//| Percorso e simulazione                                             |
//+------------------------------------------------------------------+
void BuildPath(const SEvent &e)
{
   int dir = e.dir;
   double E0 = e.E0;
   int jt = e.jt;
   for(int j = 0; j < g_L; j++)
   {
      double h = g_rs[jt + j].high, l = g_rs[jt + j].low, c = g_rs[jt + j].close;
      g_wC[j] = dir * (c - E0);
      if(dir > 0) { g_wF[j] = h - E0; g_wA[j] = l - E0; }
      else        { g_wF[j] = E0 - l; g_wA[j] = E0 - h; }
      g_wO[j] = dir * (g_rs[jt + j].open - E0);
   }
   // barra di innesco: ingresso a E0, estremo avverso stimato dalla chiusura
   g_wO[0] = 0.0;
   g_a0raw = g_wA[0];
   g_wA[0] = MathMin(0.0, g_wC[0]);
   if(g_wF[0] < 0.0) g_wF[0] = 0.0;
}

void EventStudy(SEvent &e)
{
   double atr = e.atr;
   int dir = e.dir;
   double mfe = 0.0, mae = 0.0;
   for(int j = 0; j < g_L; j++)
   {
      if(g_wF[j] > mfe) mfe = g_wF[j];
      if(-g_wA[j] > mae) mae = -g_wA[j];
   }
   e.mfe = mfe / atr;
   e.mae = mae / atr;
   for(int h = 0; h < g_nH; h++)
   {
      int idx = MathMin(g_L - 1, (int)((long)g_hor[h] * 3600 / g_perSim) - 1);
      if(idx < 0) idx = 0;
      e.ret[h] = g_wC[idx] / atr;
   }
   for(int i = 0; i < NFP; i++)
   {
      double R; int fl, jx;
      double dd = g_fpX[i] * atr;
      e.fp[i] = SimFixed(0.0, 0.0, dd, dd, dd, R, fl, jx);
   }
   for(int i = 0; i < NFR; i++)
   {
      double R; int fl, jx;
      double dd = g_frX[i] * e.width;
      e.fr[i] = (dd > EPSILON) ? SimFixed(0.0, 0.0, dd, dd, dd, R, fl, jx) : 0;
   }
   // falso breakout: raggiunge il bordo opposto del range
   double opp = (dir > 0) ? e.lo : e.hi;
   double thr = dir * (opp - e.E0);     // negativo
   e.fakeout = 0;
   e.fakeHrs = -1.0;
   for(int j = 0; j < g_L; j++)
   {
      if(g_wA[j] <= thr)
      {
         e.fakeout = 1;
         e.fakeHrs = (double)(j + 1) * g_perSim / 3600.0;
         break;
      }
   }
}

// Simula UNA configurazione sull'evento il cui percorso e' gia' in g_w* (BuildPath).
void SimCfgOnEvent(const SEvent &ev, const SCfg &cf, double &R0, int &fl, int &jx)
{
   double comm = InpCommissionPoints * g_point;
   double minDist = g_stopLvl + g_ts;
   double atr = ev.atr, width = ev.width, S = ev.spread, dl = ev.delta;
   R0 = 0.0; fl = 0; jx = 0;
   if(cf.kind == 2)
   {
      double sl = StopLossPoints * g_point;
      double tp = UseTakeProfit ? TakeProfitPoints * g_point : 0.0;
      double tpe = (tp > 0.0) ? MathMax(tp - dl, g_ts) : 0.0;
      SimFull(S, comm, sl + dl, tpe, sl, UsaBreakEven, BreakEvenAttivazione * g_point, BreakEvenOffset * g_point,
              UsaTrailingStop, TrailingStartProfit * g_point, TrailingOffset * g_point, TrailingStep * g_point, minDist, R0, fl, jx);
      return;
   }
   double slb = cf.sl;
   if(cf.unit == 1) slb *= atr;
   else if(cf.unit == 2) slb *= width;
   if(slb <= EPSILON) return;
   if(cf.kind == 0)
   {
      double tp = cf.rr * slb;
      double tpe = MathMax(tp - dl, g_ts);
      SimFixed(S, comm, slb + dl, tpe, slb, R0, fl, jx);
   }
   else
   {
      double act  = (cf.unit == 1) ? cf.act * atr  : cf.act;
      double dist = (cf.unit == 1) ? cf.dist * atr : cf.dist;
      double tp   = (cf.rr > 0.0) ? cf.rr * slb : 0.0;
      double tpe  = (tp > 0.0) ? MathMax(tp - dl, g_ts) : 0.0;
      SimFull(S, comm, slb + dl, tpe, slb, false, 0.0, 0.0, true, act, dist, InpTrailStepRatio * dist, minDist, R0, fl, jx);
   }
}

void SimulateOne(const SEvent &ev, const SCfg &cf, double &R0, int &fl, int &jx)
{
   BuildPath(ev);
   SimCfgOnEvent(ev, cf, R0, fl, jx);
}

void SimulateEvents(SEvent &ev[], const SCfg &cfg[], float &R[], uchar &F2[], int &XJ[], const bool study)
{
   int E = ArraySize(ev);
   int C = ArraySize(cfg);
   ArrayResize(R, E * C);
   ArrayResize(F2, E * C);
   ArrayResize(XJ, E * C);
   ArrayResize(g_wO, g_L);
   ArrayResize(g_wF, g_L);
   ArrayResize(g_wA, g_L);
   ArrayResize(g_wC, g_L);
   for(int e = 0; e < E; e++)
   {
      if(IsStopped()) return;
      if(study && (e & 31) == 0) Comment(StringFormat("MDRB Study: simulazione %d/%d trade x %d configurazioni", e, E, C));
      BuildPath(ev[e]);
      if(study) EventStudy(ev[e]);
      int off = e * C;
      for(int c = 0; c < C; c++)
      {
         double R0;
         int fl, jx;
         SimCfgOnEvent(ev[e], cfg[c], R0, fl, jx);
         R[off + c] = (float)R0;
         F2[off + c] = (uchar)fl;
         XJ[off + c] = jx;
      }
   }
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

// Aggrega per configurazione rispettando la regola dell'EA: nessuna nuova coppia se una posizione e' ancora
// aperta. Se alla finestra la posizione della stessa configurazione e' aperta, il trade e' SALTATO; ma se la
// posizione si chiude DENTRO la finestra l'EA ripiazza la coppia da quel momento (range e riempimento ripartono
// da li', e il nuovo trade viene simulato per quella sola configurazione).
// XR: R del trade eseguito (XR_SKIP se saltato); XT/XD: istante di riempimento e direzione del trade eseguito.
void AggregateBusy(const SEvent &ev[], const SDef &d, const SCfg &cfg[], const int C, const float &R[], const uchar &F2[], const int &XJ[],
                   const int split, SStat &sIS[], SStat &sOOS[], SStat &sAll[], int &skip[], int &repl[],
                   float &XR[], datetime &XT[], int &XD[])
{
   int E = ArraySize(ev);
   int nS = ArraySize(g_rs);
   datetime busy[];
   ArrayResize(busy, C);
   ArrayResize(XR, E * C);
   ArrayResize(XT, E * C);
   ArrayResize(XD, E * C);
   for(int c = 0; c < C; c++)
   {
      busy[c] = 0;
      ZeroMemory(sIS[c]); ZeroMemory(sOOS[c]); ZeroMemory(sAll[c]);
      skip[c] = 0;
      repl[c] = 0;
   }
   for(int e = 0; e < E; e++)
   {
      int off = e * C;
      for(int c = 0; c < C; c++)
      {
         double r;
         uchar fl;
         int jx, jt;
         datetime tf;
         int dr;
         XR[off + c] = XR_SKIP;
         if(ev[e].tPlace >= busy[c])
         {
            r = (double)R[off + c]; fl = F2[off + c]; jx = XJ[off + c]; jt = ev[e].jt; tf = ev[e].tFill; dr = ev[e].dir;
         }
         else
         {
            // posizione ancora aperta alla finestra: ripiazzamento solo se si chiude prima della fine della finestra
            SEvent e2;
            SFunnel f2;
            ZeroMemory(f2);
            datetime pe = 0;
            if(!BuildDay(d, ev[e].di, busy[c], e2, f2, pe)) { skip[c]++; continue; }
            double r2;
            int fl2;
            SimulateOne(e2, cfg[c], r2, fl2, jx);
            r = r2; fl = (uchar)fl2; jt = e2.jt; tf = e2.tFill; dr = e2.dir;
            repl[c]++;
         }
         StatAdd(sAll[c], r, fl);
         if(e < split) StatAdd(sIS[c], r, fl);
         else StatAdd(sOOS[c], r, fl);
         XR[off + c] = (float)r;
         XT[off + c] = tf;
         XD[off + c] = dr;
         int jb = MathMin(jt + jx, nS - 1);
         busy[c] = g_rs[jb].time + g_perSim;
      }
   }
}

void AggregateMain()
{
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);
   ArrayResize(g_stIS, C);
   ArrayResize(g_stOOS, C);
   ArrayResize(g_stAll, C);
   ArrayResize(g_skip, C);
   ArrayResize(g_repl, C);
   g_split = (int)(E * InpISPercent / 100.0);
   if(g_split < 1) g_split = 1;
   if(g_split > E) g_split = E;
   AggregateBusy(g_ev, g_def, g_cfg, C, g_R, g_F, g_XJ, g_split, g_stIS, g_stOOS, g_stAll, g_skip, g_repl, g_xR, g_xT, g_xD);
}

double RankMetric(const SStat &s)
{
   if(InpRankBy == RANK_EXPECTANCY) return StatMean(s);
   if(InpRankBy == RANK_PF) return MathMin(StatPF(s), 10.0) - 1.0;
   return StatT(s);
}

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
   for(int f = 0; f < 5; f++) g_best[f] = -1;
   g_best[5] = g_refIdx;

   for(int f = 0; f < 5; f++)
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

void AssignBuckets()
{
   int E = ArraySize(g_ev);
   double w[], dl[];
   ArrayResize(w, E);
   ArrayResize(dl, E);
   for(int e = 0; e < E; e++) { w[e] = g_ev[e].widthAtr; dl[e] = g_ev[e].delayMin; }
   ArraySort(w);
   ArraySort(dl);
   for(int i = 0; i < 4; i++) g_wEdge[i] = Quantile(w, E, (i + 1) / 5.0);
   for(int i = 0; i < 2; i++) g_dEdge[i] = Quantile(dl, E, (i + 1) / 3.0);
   for(int e = 0; e < E; e++)
   {
      int bw = 0;
      for(int i = 0; i < 4; i++) if(g_ev[e].widthAtr > g_wEdge[i]) bw++;
      int bd = 0;
      for(int i = 0; i < 2; i++) if(g_ev[e].delayMin > g_dEdge[i]) bd++;
      g_ev[e].bw = bw;
      g_ev[e].bd = bd;
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
//| Sweep: una definizione = un insieme di trade; 2 configurazioni     |
//+------------------------------------------------------------------+
void RunDefStats(const SDef &d, const SCfg &cfg[], SStat &sIS[], SStat &sOOS[], SStat &sAll[], const int row, int &nEv, SFunnel &fnOut)
{
   SEvent ev[];
   SFunnel fn;
   BuildSetups(d, ev, fn);
   fnOut = fn;
   int E = ArraySize(ev);
   nEv = E;
   int C = ArraySize(cfg);
   for(int c = 0; c < C; c++) { ZeroMemory(sIS[row * C + c]); ZeroMemory(sOOS[row * C + c]); ZeroMemory(sAll[row * C + c]); }
   if(E == 0) return;
   float R[];
   uchar F2[];
   int XJ[];
   SimulateEvents(ev, cfg, R, F2, XJ, false);
   int split = (int)(E * InpISPercent / 100.0);
   if(split < 1) split = 1;
   SStat tIS[], tOOS[], tAll[];
   ArrayResize(tIS, C); ArrayResize(tOOS, C); ArrayResize(tAll, C);
   int skip[], repl[];
   ArrayResize(skip, C);
   ArrayResize(repl, C);
   float XR[];
   datetime XT[];
   int XD[];
   AggregateBusy(ev, d, cfg, C, R, F2, XJ, split, tIS, tOOS, tAll, skip, repl, XR, XT, XD);
   for(int c = 0; c < C; c++) { sIS[row * C + c] = tIS[c]; sOOS[row * C + c] = tOOS[c]; sAll[row * C + c] = tAll[c]; }
}

void RunSweep1()
{
   ArrayResize(g_s1Lbl, 0);
   SDef defs[];
   ArrayResize(defs, 0);
   int dbk[];
   if(ParseIntList(InpSweepDaysBackList, dbk) < 1) { ArrayResize(dbk, 1); dbk[0] = RangeDaysBack; }

   if(RangeMode == RANGE_BARS)
   {
      double lb[];
      if(ParseList(InpSweepBarsLookback, lb) < 1) return;
      for(int a = 0; a < ArraySize(lb); a++)
         for(int b = 0; b < ArraySize(dbk); b++)
         {
            if(ArraySize(defs) >= MAXSWEEP) break;
            int n = ArraySize(defs);
            ArrayResize(defs, n + 1);
            defs[n] = g_def;
            defs[n].lookback = (int)lb[a];
            defs[n].daysBack = dbk[b];
            ArrayResize(g_s1Lbl, n + 1);
            g_s1Lbl[n] = StringFormat("%d barre %s, giorno -%d", (int)lb[a], EnumToString(g_rangeTF), dbk[b]);
         }
   }
   else if(RangeMode == RANGE_TIME)
   {
      int hs[], ms[], he[], me[];
      if(ParseWindows(InpSweepTimeWindows, hs, ms, he, me) < 1) return;
      for(int a = 0; a < ArraySize(hs); a++)
         for(int b = 0; b < ArraySize(dbk); b++)
         {
            if(ArraySize(defs) >= MAXSWEEP) break;
            int n = ArraySize(defs);
            ArrayResize(defs, n + 1);
            defs[n] = g_def;
            defs[n].rhs = hs[a]; defs[n].rms = ms[a]; defs[n].rhe = he[a]; defs[n].rme = me[a];
            defs[n].daysBack = dbk[b];
            ArrayResize(g_s1Lbl, n + 1);
            g_s1Lbl[n] = StringFormat("%02d:%02d-%02d:%02d, giorno -%d", hs[a], ms[a], he[a], me[a], dbk[b]);
         }
   }
   else
   {
      double sp[];
      if(ParseList(InpSweepDaySpans, sp) < 1) return;
      for(int a = 0; a < ArraySize(sp); a++)
         for(int b = 0; b < ArraySize(dbk); b++)
         {
            if(dbk[b] < 1) continue;
            if(ArraySize(defs) >= MAXSWEEP) break;
            int n = ArraySize(defs);
            ArrayResize(defs, n + 1);
            defs[n] = g_def;
            defs[n].span = (int)sp[a];
            defs[n].daysBack = dbk[b];
            ArrayResize(g_s1Lbl, n + 1);
            g_s1Lbl[n] = StringFormat("%d giorni D1, da -%d", (int)sp[a], dbk[b]);
         }
   }
   int K = ArraySize(defs);
   if(K == 0) return;
   SCfg cfg[];
   BuildSweepCfgs(cfg);
   ArrayResize(g_s1N, K);
   ArrayResize(g_s1Fn, K);
   ArrayResize(g_s1IS, K * 2);
   ArrayResize(g_s1OOS, K * 2);
   ArrayResize(g_s1All, K * 2);
   for(int k = 0; k < K; k++)
   {
      if(IsStopped()) return;
      Comment(StringFormat("MDRB Study: sweep range %d/%d", k + 1, K));
      RunDefStats(defs[k], cfg, g_s1IS, g_s1OOS, g_s1All, k, g_s1N[k], g_s1Fn[k]);
   }
}

void RunSweep2()
{
   ArrayResize(g_s2Lbl, 0);
   SDef defs[];
   ArrayResize(defs, 0);
   int len = InpSweepEntryLenMin;
   for(int s = 0; s + len <= 1440; s += InpSweepEntryStepMin)
   {
      if(ArraySize(defs) >= MAXSWEEP) break;
      int n = ArraySize(defs);
      ArrayResize(defs, n + 1);
      defs[n] = g_def;
      defs[n].wsMin = s;
      defs[n].weMin = s + len;
      ArrayResize(g_s2Lbl, n + 1);
      g_s2Lbl[n] = HHMM(s) + "-" + HHMM(s + len);
   }
   int K = ArraySize(defs);
   if(K == 0) return;
   SCfg cfg[];
   BuildSweepCfgs(cfg);
   ArrayResize(g_s2N, K);
   ArrayResize(g_s2Fn, K);
   ArrayResize(g_s2IS, K * 2);
   ArrayResize(g_s2OOS, K * 2);
   ArrayResize(g_s2All, K * 2);
   for(int k = 0; k < K; k++)
   {
      if(IsStopped()) return;
      Comment(StringFormat("MDRB Study: sweep finestra di ingresso %d/%d", k + 1, K));
      RunDefStats(defs[k], cfg, g_s2IS, g_s2OOS, g_s2All, k, g_s2N[k], g_s2Fn[k]);
   }
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

string WdayName(const int w)
{
   if(w == 1) return "Luned&igrave;";
   if(w == 2) return "Marted&igrave;";
   if(w == 3) return "Mercoled&igrave;";
   if(w == 4) return "Gioved&igrave;";
   if(w == 5) return "Venerd&igrave;";
   return "Weekend";
}

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

double HeatValue(const int metric, const int fam, const int c, const SStat &s)
{
   if(s.n == 0) return 0.0;
   double v = 0.0;
   if(metric == 0) v = StatMean(s);
   else if(metric == 1)
   {
      if(fam <= 2 || fam == 5) v = StatWR(s) - 100.0 / (1.0 + g_cfg[c].rr);
   }
   else if(metric == 2) v = StatPF(s) - 1.0;
   else if(metric == 3) v = StatT(s);
   return v;
}

void HtmlMatrix(const string title, const int fam, const int metric, const int part)
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
         if(g_best[fam] == c && fam < 5 && metric == 0 && part < 2) cls = " class='best'";
         HW("<td" + cls + bg + ">" + MetricStr(metric, s) + "</td>");
      }
      HW("</tr>\n");
   }
   HW("</table>");
}

void HtmlStart()
{
   HW("<!DOCTYPE html><html><head><meta charset='utf-8'><title>MDRB Study</title><style>");
   HW("body{font-family:Segoe UI,Arial,sans-serif;margin:24px auto;max-width:1180px;padding:0 14px;color:#1b1f24;background:#fafbfc;font-size:14px}");
   HW("h1{font-size:22px;margin-bottom:4px}h2{font-size:17px;margin-top:34px;border-bottom:1px solid #d0d7de;padding-bottom:4px}h3{font-size:14px;margin:20px 0 4px}");
   HW("table{border-collapse:collapse;margin:6px 0 4px;font-size:12.5px}th,td{border:1px solid #d0d7de;padding:3px 8px;text-align:right}");
   HW("th{background:#eef1f4;font-weight:600}th.rl{text-align:left;white-space:nowrap}td.lo{color:#9aa3ad}td.best{outline:2px solid #1f6feb;outline-offset:-2px;font-weight:700}");
   HW(".note{color:#59636e;font-size:12px;margin:2px 0 4px}.warn{background:#fff4d6;border:1px solid #e0c36a;padding:6px 10px;margin:6px 0;font-size:13px}");
   HW(".bad{color:#b42318;font-weight:600}.ok{color:#1a7f37;font-weight:600}.mid{color:#9a6700;font-weight:600}.mono{font-family:Consolas,monospace}");
   HW(".legend span{display:inline-block;margin-right:14px}svg{background:#fff;border:1px solid #d0d7de}ul{margin:6px 0 6px 18px;padding:0}li{margin:3px 0}tr.bestrow td,tr.bestrow th{background:#e8f1ff}");
   HW("</style></head><body>\n");
}

string FamName(const int f)
{
   if(f == 0) return "RR fisso - punti";
   if(f == 1) return "RR fisso - ATR";
   if(f == 2) return "RR fisso - range";
   if(f == 3) return "Trailing - punti";
   if(f == 4) return "Trailing - ATR";
   return "Uscita EA";
}

string CellDesc(const int c)
{
   int f = g_cfg[c].fam;
   int r = g_cfg[c].row, cc = g_cfg[c].col;
   if(f == 5) return g_rowLbl[5][0] + " " + g_colLbl[5][0];
   if(f <= 2) return g_rowLbl[f][r] + " / RR " + g_colLbl[f][cc];
   return g_rowLbl[f][r] + " / " + g_colLbl[f][cc];
}

string Verdict(const SStat &o, double &pOut)
{
   pOut = 1.0;
   if(o.n < 20) return "campione OOS insufficiente";
   double t = StatT(o);
   pOut = NormUpper(t);
   if(StatMean(o) <= 0.0) return "<span class='bad'>NON confermato OOS</span>";
   if(pOut < 0.05) return "<span class='ok'>confermato OOS (p&lt;5%)</span>";
   return "<span class='mid'>OOS positivo ma non significativo</span>";
}

void HtmlVerdict()
{
   HW("<h2>1. Verdetto</h2>");
   HW("<div class='note'>Per ogni famiglia la cella migliore &egrave; scelta SOLO sull'In-Sample (metrica: " +
      Pick(InpRankBy == RANK_TSTAT, "t-stat", Pick(InpRankBy == RANK_EXPECTANCY, "expectancy", "profit factor")) +
      Pick(InpSmoothRank, ", mediata sui vicini 3x3", "") + "). L'unico numero onesto &egrave; la colonna OOS: un solo test, fatto su dati mai usati per scegliere. "
      "Un trade = un giorno: il campione &egrave; piccolo, quindi anche un buon risultato vale poco senza conferma OOS. "
      "Attenzione: tutte le famiglie usano gli stessi giorni e lo stesso OOS, quindi un OOS fortunato le conferma TUTTE insieme: leggi \"quante famiglie confermano\" come un solo test, non come sei test indipendenti, e guarda la stabilit&agrave; per anno.</div>");
   HW("<table><tr><th class='rl'>Famiglia</th><th class='rl'>Cella scelta (IS)</th><th>N IS</th><th>E[R] IS</th><th>t IS</th><th>t critico*</th><th>N OOS</th><th>E[R] OOS</th><th>t OOS</th><th>p OOS</th><th>PF OOS</th><th>MaxDD (R) tutto</th><th class='rl'>Esito</th></tr>");
   for(int f = 0; f < 6; f++)
   {
      int c = g_best[f];
      if(c < 0) { HW("<tr><th class='rl'>" + FamName(f) + "</th><td colspan='12' class='rl'>nessuna cella con almeno " + IntegerToString(InpMinTrades) + " trade IS</td></tr>"); continue; }
      int K = (f < 5) ? g_dimR[f] * g_dimC[f] : 1;
      double tcrit = (f < 5) ? NormInvUpper(0.05 / K) : 1.645;
      double p;
      string v = Verdict(g_stOOS[c], p);
      if(f < 5 && StatT(g_stIS[c]) < tcrit) v += " <span class='note'>(t IS sotto la soglia di correzione multipla)</span>";
      HW("<tr><th class='rl'>" + FamName(f) + "</th><td class='mono' style='text-align:left'>" + CellDesc(c) + "</td><td>" + IntegerToString(g_stIS[c].n) + "</td><td>" +
         F(StatMean(g_stIS[c]), 3) + "</td><td>" + F(StatT(g_stIS[c]), 2) + "</td><td>" + F(tcrit, 2) + "</td><td>" + IntegerToString(g_stOOS[c].n) + "</td><td>" +
         F(StatMean(g_stOOS[c]), 3) + "</td><td>" + F(StatT(g_stOOS[c]), 2) + "</td><td>" + F(p, 3) + "</td><td>" + PfStr(StatPF(g_stOOS[c])) + "</td><td>" +
         F(g_stAll[c].dd, 1) + "</td><td class='rl' style='text-align:left'>" + v + "</td></tr>\n");
   }
   HW("</table><div class='note'>* soglia t (one-sided 5%) con correzione di Bonferroni sul numero di celle della famiglia: conservativa perch&eacute; le celle sono correlate, ma &egrave; l'ordine di grandezza giusto per il data-mining. "
      "La riga &laquo;Uscita EA&raquo; non &egrave; stata scelta: &egrave; la configurazione di uscita dei tuoi input (SL/TP + break-even + trailing), quindi vale come test a posteriori unico.</div>");

   HW("<h3>La mappa delle celle si ripete fuori campione?</h3><table><tr><th class='rl'>Famiglia</th><th>Celle confrontate</th><th>Spearman IS-OOS (E[R])</th><th class='rl'>Lettura</th></tr>");
   for(int f = 0; f < 5; f++)
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

void HtmlFunnel()
{
   HW("<h2>2. Cosa succede ogni giorno</h2>");
   HW("<table><tr><th class='rl'>Passo</th><th>Giorni</th><th>%</th></tr>");
   int d = MathMax(1, g_fn.days);
   HW("<tr><th class='rl'>Giorni di mercato analizzati</th><td>" + IntegerToString(g_fn.days) + "</td><td>100.0</td></tr>");
   HW("<tr><th class='rl'>Range non calcolabile (dati o fine del range oltre la finestra)</th><td>" + IntegerToString(g_fn.noRange) + "</td><td>" + F(100.0 * g_fn.noRange / d, 1) + "</td></tr>");
   if(RequireRangeConfirmation)
   {
      HW("<tr><th class='rl'>Range scartato: pi&ugrave; stretto di " + F(MinRangePoints, 0) + " punti</th><td>" + IntegerToString(g_fn.tooSmall) + "</td><td>" + F(100.0 * g_fn.tooSmall / d, 1) + "</td></tr>");
      HW("<tr><th class='rl'>Range scartato: pi&ugrave; largo di " + F(MaxRangePoints, 0) + " punti</th><td>" + IntegerToString(g_fn.tooBig) + "</td><td>" + F(100.0 * g_fn.tooBig / d, 1) + "</td></tr>");
   }
   HW("<tr><th class='rl'>Range nullo o senza barre</th><td>" + IntegerToString(g_fn.invalid) + "</td><td>" + F(100.0 * g_fn.invalid / d, 1) + "</td></tr>");
   HW("<tr><th class='rl'>Prezzo sempre fuori dai livelli: coppia mai piazzata</th><td>" + IntegerToString(g_fn.noPlace) + "</td><td>" + F(100.0 * g_fn.noPlace / d, 1) + "</td></tr>");
   HW("<tr><th class='rl'>Coppia piazzata ma scaduta senza sfondamento</th><td>" + IntegerToString(g_fn.noFill) + "</td><td>" + F(100.0 * g_fn.noFill / d, 1) + "</td></tr>");
   HW("<tr><th class='rl'>Orizzonte non disponibile (fine dei dati) o ATR assente</th><td>" + IntegerToString(g_fn.noData + g_fn.noATR) + "</td><td>" + F(100.0 * (g_fn.noData + g_fn.noATR) / d, 1) + "</td></tr>");
   HW("<tr><th class='rl'>Sfondamenti (trade simulati)</th><td>" + IntegerToString(g_fn.filled) + "</td><td>" + F(100.0 * g_fn.filled / d, 1) + "</td></tr>");
   HW("<tr><th class='rl'>&nbsp;&nbsp;long / short</th><td>" + IntegerToString(g_fn.longs) + " / " + IntegerToString(g_fn.shorts) + "</td><td></td></tr>");
   HW("<tr><th class='rl'>&nbsp;&nbsp;barra di innesco che toccava entrambi i livelli</th><td>" + IntegerToString(g_fn.ambTrig) + "</td><td></td></tr>");
   if(g_refIdx >= 0)
   {
      HW("<tr><th class='rl'>Con le uscite dell'EA: giorni saltati (posizione ancora aperta per tutta la finestra)</th><td>" + IntegerToString(g_skip[g_refIdx]) + "</td><td>" + F(100.0 * g_skip[g_refIdx] / MathMax(1, g_fn.filled), 1) + "</td></tr>");
      HW("<tr><th class='rl'>Con le uscite dell'EA: coppia ripiazzata a met&agrave; finestra (la posizione si &egrave; chiusa durante la finestra)</th><td>" + IntegerToString(g_repl[g_refIdx]) + "</td><td>" + F(100.0 * g_repl[g_refIdx] / MathMax(1, g_fn.filled), 1) + "</td></tr>");
   }
   HW("</table><div class='note'>L'EA piazza al massimo una coppia al giorno e non ne piazza se c'&egrave; una posizione aperta: i giorni saltati o ripiazzati dipendono dalla configurazione di uscita (SL/TP larghi = posizioni pi&ugrave; lunghe = pi&ugrave; giorni saltati). Lo studio lo replica per ogni cella: se la posizione si chiude durante la finestra, ripiazza la coppia come l'EA.</div>");
}

void HtmlEventStudy()
{
   int E = ArraySize(g_ev);
   HW("<h2>3. Come si comporta il prezzo dopo lo sfondamento (lordo di costi)</h2>");
   HW("<div class='note'>Misurato dall'ingresso. Direzionale: positivo = il prezzo prosegue nel verso dello sfondamento. Unit&agrave;: ATR (" + EnumToString(g_atrTF) + ", " + IntegerToString(InpATRPeriod) +
      ") al momento del piazzamento; in punti con l'ATR mediano (" + F(g_medATRpts, 0) + " punti). Orizzonte: ore dopo l'ingresso. Tutti i " + IntegerToString(E) + " sfondamenti, senza saltare nulla.</div>");

   HW("<h3>Rendimento direzionale medio a fine orizzonte</h3><table><tr><th>Ore</th><th>Medio (ATR)</th><th>Medio (punti)</th><th>Errore std.</th><th>t</th><th>% positivi</th></tr>");
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

   double mf[], ma[];
   ArrayResize(mf, E);
   ArrayResize(ma, E);
   double smf = 0.0, sma = 0.0;
   int fake = 0;
   double fh[];
   ArrayResize(fh, 0);
   for(int e = 0; e < E; e++)
   {
      mf[e] = g_ev[e].mfe; ma[e] = g_ev[e].mae; smf += mf[e]; sma += ma[e];
      if(g_ev[e].fakeout != 0)
      {
         fake++;
         int sz = ArraySize(fh);
         ArrayResize(fh, sz + 1);
         fh[sz] = g_ev[e].fakeHrs;
      }
   }
   ArraySort(mf);
   ArraySort(ma);
   ArraySort(fh);
   HW("<h3>Escursione massima sull'orizzonte (ATR)</h3><table><tr><th></th><th>Media</th><th>P25</th><th>Mediana</th><th>P75</th><th>P90</th></tr>");
   HW("<tr><th class='rl'>MFE (favorevole)</th><td>" + F(smf / E, 2) + "</td><td>" + F(Quantile(mf, E, 0.25), 2) + "</td><td>" + F(Quantile(mf, E, 0.5), 2) +
      "</td><td>" + F(Quantile(mf, E, 0.75), 2) + "</td><td>" + F(Quantile(mf, E, 0.9), 2) + "</td></tr>");
   HW("<tr><th class='rl'>MAE (avversa)</th><td>" + F(sma / E, 2) + "</td><td>" + F(Quantile(ma, E, 0.25), 2) + "</td><td>" + F(Quantile(ma, E, 0.5), 2) +
      "</td><td>" + F(Quantile(ma, E, 0.75), 2) + "</td><td>" + F(Quantile(ma, E, 0.9), 2) + "</td></tr></table>");
   HW("<div class='note'>Falsi breakout: <b>" + F(100.0 * fake / E, 1) + "%</b> degli sfondamenti torna a toccare il bordo OPPOSTO del range entro l'orizzonte" +
      (fake > 0 ? " (dopo " + F(Quantile(fh, ArraySize(fh), 0.5), 1) + " ore, mediana)" : "") + ". MFE e MAE sono misurate su tutto l'orizzonte senza fermarsi allo SL: servono a dimensionare stop e target, non sono un risultato di trading.</div>");

   HW("<h3>Quale soglia viene toccata per prima dopo l'ingresso?</h3><table><tr><th>Soglia</th><th>Favorevole prima</th><th>Avversa prima</th><th>Nessuna</th><th>P(fav | decisi)</th><th>z vs 50%</th></tr>");
   for(int i = 0; i < NFP + NFR; i++)
   {
      int up = 0, dn = 0, nn = 0;
      for(int e = 0; e < E; e++)
      {
         int v = (i < NFP) ? g_ev[e].fp[i] : g_ev[e].fr[i - NFP];
         if(v > 0) up++; else if(v < 0) dn++; else nn++;
      }
      double p = (up + dn > 0) ? (double)up / (up + dn) : 0.5;
      double z = (up + dn > 0) ? (p - 0.5) / MathSqrt(0.25 / (up + dn)) : 0.0;
      string cls = (MathAbs(z) >= 2.0) ? ((z > 0) ? " class='ok'" : " class='bad'") : "";
      string lbl = (i < NFP) ? "&plusmn;" + F(g_fpX[i], 1) + " ATR" : "&plusmn;" + F(g_frX[i - NFP], 2) + " x range";
      HW("<tr><th class='rl'>" + lbl + "</th><td>" + F(100.0 * up / E, 1) + "%</td><td>" + F(100.0 * dn / E, 1) + "%</td><td>" + F(100.0 * nn / E, 1) +
         "%</td><td>" + F(100.0 * p, 1) + "%</td><td" + cls + ">" + F(z, 2) + "</td></tr>\n");
   }
   HW("</table><div class='note'>Con prezzo senza direzione P(fav | decisi) = 50%. Scarto significativo = lo sfondamento ha un contenuto direzionale prima dei costi. Se i due livelli cadono nella stessa barra si assume quello avverso.</div>");
}

void BreakRow(const string label, const int dimType, const int val)
{
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);
   SStat s;
   ZeroMemory(s);
   double smfe = 0.0, smae = 0.0;
   double wp[];
   ArrayResize(wp, 0);
   for(int e = 0; e < E; e++)
   {
      bool m = false;
      if(dimType == 0) m = (g_ev[e].dir == val);
      else if(dimType == 1) m = (g_ev[e].wday == val);
      else if(dimType == 2) m = (g_ev[e].bw == val);
      else if(dimType == 3) m = (g_ev[e].bd == val);
      else
      {
         double wpts = g_ev[e].width / g_point;
         bool inl = (wpts >= MinRangePoints && wpts <= MaxRangePoints);
         m = (val == 1) ? inl : !inl;
      }
      if(!m) continue;
      StatAdd(s, (double)g_R[e * C + g_refIdx], g_F[e * C + g_refIdx]);
      smfe += g_ev[e].mfe;
      smae += g_ev[e].mae;
      int sz = ArraySize(wp);
      ArrayResize(wp, sz + 1);
      wp[sz] = g_ev[e].width / g_point;
   }
   if(s.n == 0) return;
   ArraySort(wp);
   double t = StatT(s);
   string cls = (s.n >= InpMinTrades && t >= 2.0) ? " class='ok'" : ((s.n >= InpMinTrades && t <= -2.0) ? " class='bad'" : "");
   HW("<tr><th class='rl'>" + label + "</th><td>" + IntegerToString(s.n) + "</td><td>" + F(StatWR(s), 1) + "%</td><td>" + F(StatMean(s), 3) +
      "</td><td" + cls + ">" + F(t, 2) + "</td><td>" + PfStr(StatPF(s)) + "</td><td>" + F(smfe / s.n, 2) + "</td><td>" + F(smae / s.n, 2) +
      "</td><td>" + F(Quantile(wp, ArraySize(wp), 0.5), 0) + "</td></tr>\n");
}

void HtmlBreakdown()
{
   HW("<h2>4. Quali range funzionano meglio</h2>");
   HW("<div class='note'>Configurazione di riferimento: SL " + F(InpRefSLATR, 2) + " ATR, TP " + F(InpRefRR * InpRefSLATR, 2) + " ATR (RR 1:" + F(InpRefRR, 1) +
      "), netto di costi, su tutti gli sfondamenti (senza saltare giorni). Una dimensione alla volta. Evidenziati solo scostamenti con |t| &ge; 2 e almeno " +
      IntegerToString(InpMinTrades) + " trade: con una ventina di celle guardate, un paio escono per puro caso. " +
      Pick(RequireRangeConfirmation, "Il filtro Min/Max range dell'EA &egrave; ATTIVO: le larghezze fuori limite non compaiono.", "Il filtro Min/Max range non &egrave; applicato: le righe &laquo;nei limiti / fuori limiti&raquo; ti dicono dove mettere MinRangePoints e MaxRangePoints.") + "</div>");
   HW("<table><tr><th></th><th>N</th><th>Win %</th><th>E[R]</th><th>t</th><th>PF</th><th>MFE media (ATR)</th><th>MAE media (ATR)</th><th>Range mediano (pt)</th></tr>");
   HW("<tr><th class='rl' colspan='9' style='background:#f6f8fa'>Direzione dello sfondamento</th></tr>");
   BreakRow("Long (sopra il massimo)", 0, 1);
   BreakRow("Short (sotto il minimo)", 0, -1);
   HW("<tr><th class='rl' colspan='9' style='background:#f6f8fa'>Giorno della settimana</th></tr>");
   for(int w = 1; w <= 5; w++) BreakRow(WdayName(w), 1, w);
   HW("<tr><th class='rl' colspan='9' style='background:#f6f8fa'>Larghezza del range (quintili, in ATR)</th></tr>");
   for(int b = 0; b < 5; b++)
   {
      string lo = (b == 0) ? "0" : F(g_wEdge[b - 1], 1);
      string hi = (b == 4) ? "inf" : F(g_wEdge[b], 1);
      BreakRow("Range " + lo + " - " + hi + " ATR", 2, b);
   }
   HW("<tr><th class='rl' colspan='9' style='background:#f6f8fa'>Limiti dell'EA (" + F(MinRangePoints, 0) + " - " + F(MaxRangePoints, 0) + " punti)</th></tr>");
   BreakRow("Range nei limiti", 4, 1);
   BreakRow("Range fuori limiti", 4, 0);
   HW("<tr><th class='rl' colspan='9' style='background:#f6f8fa'>Minuti dal piazzamento allo sfondamento (terzili)</th></tr>");
   for(int b = 0; b < 3; b++)
   {
      string lo = (b == 0) ? "0" : F(g_dEdge[b - 1], 0);
      string hi = (b == 2) ? "inf" : F(g_dEdge[b], 0);
      BreakRow(lo + " - " + hi + " min", 3, b);
   }
   HW("</table>");
}

void HtmlSweepTable(const string title, const string note, const string &lbl[], const int &nEv[],
                    const SStat &sIS[], const SStat &sOOS[], const SStat &sAll[], const SFunnel &fn[], const int K)
{
   HW("<h3>" + title + "</h3><div class='note'>" + note + "</div>");
   if(K <= 0) { HW("<div class='note'>nessuna definizione da provare</div>"); return; }
   // migliore sull'IS (cfg 0), con almeno InpMinTrades
   int best = -1;
   double bs = -1e9;
   for(int k = 0; k < K; k++)
   {
      if(sIS[k * 2].n < InpMinTrades) continue;
      double sc = RankMetric(sIS[k * 2]);
      if(sc > bs) { bs = sc; best = k; }
   }
   double tcrit = NormInvUpper(0.05 / K);
   if(best >= 0 && StatMean(sIS[best * 2]) <= 0.0)
      HW("<div class='warn'>Nessuna definizione ha E[R] positivo in-sample con la configurazione SL ATR di riferimento: la riga evidenziata &egrave; solo la meno negativa.</div>");
   HW("<table><tr><th class='rl'>Definizione</th><th>Trade</th><th>Giorni senza range valido</th>"
      "<th>N IS</th><th>E[R] IS</th><th>t IS</th><th>N OOS</th><th>E[R] OOS</th><th>t OOS</th><th>p OOS</th>"
      "<th>N IS</th><th>E[R] IS</th><th>t IS</th><th>N OOS</th><th>E[R] OOS</th><th>t OOS</th><th>p OOS</th></tr>");
   HW("<tr><th class='rl' style='background:#f6f8fa'></th><th style='background:#f6f8fa'></th><th style='background:#f6f8fa'></th><th colspan='7' style='background:#f6f8fa'>SL " + F(InpRefSLATR, 2) + " ATR / RR 1:" + F(InpRefRR, 1) +
      "</th><th colspan='7' style='background:#f6f8fa'>Uscite dell'EA</th></tr>");
   for(int k = 0; k < K; k++)
   {
      string cls = (k == best) ? " class='bestrow'" : "";
      HW("<tr" + cls + "><th class='rl'>" + lbl[k] + "</th><td>" + IntegerToString(nEv[k]) + "</td><td>" + IntegerToString(fn[k].noRange + fn[k].tooSmall + fn[k].tooBig + fn[k].invalid) + "</td>");
      for(int c = 0; c < 2; c++)
      {
         int i = k * 2 + c;
         double p = NormUpper(StatT(sOOS[i]));
         string tcl = (sIS[i].n >= InpMinTrades && StatT(sIS[i]) >= tcrit) ? " class='ok'" : "";
         HW("<td>" + IntegerToString(sIS[i].n) + "</td><td>" + F(StatMean(sIS[i]), 3) + "</td><td" + tcl + ">" + F(StatT(sIS[i]), 2) + "</td><td>" + IntegerToString(sOOS[i].n) + "</td><td>" +
            F(StatMean(sOOS[i]), 3) + "</td><td>" + F(StatT(sOOS[i]), 2) + "</td><td>" + Pick(sOOS[i].n >= 20, F(p, 3), "-") + "</td>");
      }
      HW("</tr>\n");
   }
   HW("</table><div class='note'>Riga evidenziata = migliore sull'IS (SL ATR). t IS verde = supera la soglia di Bonferroni su " + IntegerToString(K) + " definizioni (t &ge; " + F(tcrit, 2) +
      "). Se nessuna &egrave; verde, la differenza tra definizioni &egrave; compatibile con il caso. Ogni definizione ha eventi diversi, quindi N cambia.</div>");
}

void HtmlSweeps()
{
   HW("<h2>5. Sweep: quale definizione di range, quale finestra di ingresso</h2>");
   HW("<div class='note'>Qui ogni riga &egrave; una variante degli input dell'EA. Le due configurazioni di uscita sono le stesse per tutte le righe (SL ATR di riferimento e uscite dell'EA), cos&igrave; le differenze vengono dalla definizione e non dall'uscita. Le righe sono molte ipotesi: guarda l'OOS, non l'IS.</div>");
   if(InpSweepRange)
      HtmlSweepTable("5a. Definizione del range (" + Pick(RangeMode == RANGE_BARS, "ultime N barre", Pick(RangeMode == RANGE_TIME, "finestra oraria", "giorni D1")) + ")",
                     "Tutto il resto come nei tuoi input.", g_s1Lbl, g_s1N, g_s1IS, g_s1OOS, g_s1All, g_s1Fn, ArraySize(g_s1Lbl));
   if(InpSweepEntryHours)
      HtmlSweepTable("5b. Finestra oraria di ingresso (durata " + IntegerToString(InpSweepEntryLenMin) + " minuti, ora server)",
                     "Stesso range dei tuoi input; cambia solo quando piazzi la coppia.", g_s2Lbl, g_s2N, g_s2IS, g_s2OOS, g_s2All, g_s2Fn, ArraySize(g_s2Lbl));
}

void HtmlTop10()
{
   HW("<h2>7. Prime 10 celle per famiglia (ordinate sul punteggio IS)</h2>");
   for(int f = 0; f < 5; f++)
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
      HW("<h3>" + FamName(f) + "</h3><table><tr><th class='rl'>Cella</th><th>Punteggio</th><th>N IS</th><th>Win IS</th><th>E[R] IS</th><th>t IS</th><th>N OOS</th><th>Win OOS</th><th>E[R] OOS</th><th>t OOS</th><th>PF OOS</th><th>Ambig. %</th><th>Fine orizz. %</th><th>Saltati</th></tr>");
      for(int i = 0; i < MathMin(10, n); i++)
      {
         int c = ids[i];
         double amb = (g_stAll[c].n > 0) ? 100.0 * g_stAll[c].amb / g_stAll[c].n : 0.0;
         double tmo = (g_stAll[c].n > 0) ? 100.0 * g_stAll[c].tmo / g_stAll[c].n : 0.0;
         HW("<tr><th class='rl'>" + CellDesc(c) + "</th><td>" + F(g_score[c], 2) + "</td><td>" + IntegerToString(g_stIS[c].n) + "</td><td>" + F(StatWR(g_stIS[c]), 1) + "%</td><td>" +
            F(StatMean(g_stIS[c]), 3) + "</td><td>" + F(StatT(g_stIS[c]), 2) + "</td><td>" + IntegerToString(g_stOOS[c].n) + "</td><td>" + F(StatWR(g_stOOS[c]), 1) + "%</td><td>" +
            F(StatMean(g_stOOS[c]), 3) + "</td><td>" + F(StatT(g_stOOS[c]), 2) + "</td><td>" + PfStr(StatPF(g_stOOS[c])) + "</td><td>" + F(amb, 1) + "</td><td>" + F(tmo, 1) + "</td><td>" +
            IntegerToString(g_skip[c]) + "</td></tr>\n");
      }
      HW("</table>");
   }
   HW("<div class='note'>Ambig. % = quota di trade il cui esito dipende dall'ordine con cui SL/TP (o lo stop trascinato) sono stati toccati dentro la stessa barra. Saltati = giorni in cui l'EA avrebbe avuto ancora una posizione aperta e non avrebbe piazzato la coppia.</div>");
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
         if(g_xR[e * C + fin[i]] != XR_SKIP) eq += (double)g_xR[e * C + fin[i]];
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
   HW("</div><div class='note'>Equity cumulata in R (un trade = 1R di rischio, nessun compounding), trade eseguiti secondo la regola dell'EA (nessuna coppia con posizione aperta), in ordine cronologico. A sinistra della linea tratteggiata il campione con cui le celle sono state scelte.</div>");
}

void HtmlStability()
{
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);
   HW("<h2>8. Stabilit&agrave; nel tempo e curve di equity</h2>");
   int fin[6];
   string names[6];
   int nf = 0;
   for(int f = 0; f < 6; f++)
   {
      if(g_best[f] < 0) continue;
      fin[nf] = g_best[f];
      names[nf] = FamName(f) + ": " + CellDesc(g_best[f]);
      nf++;
   }
   if(nf == 0) return;
   HtmlEquity(fin, names, nf);

   MqlDateTime d0, d1;
   TimeToStruct(g_ev[0].day, d0);
   TimeToStruct(g_ev[E - 1].day, d1);
   HW("<h3>E[R] per anno solare (N trade eseguiti)</h3><table><tr><th>Anno</th>");
   for(int i = 0; i < nf; i++) HW("<th>" + FamName(g_cfg[fin[i]].fam) + "</th>");
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
            if(g_xR[e * C + fin[i]] == XR_SKIP) continue;
            MqlDateTime dt;
            TimeToStruct(g_ev[e].day, dt);
            if(dt.year != y) continue;
            sum += (double)g_xR[e * C + fin[i]];
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
   HW("<h2>9. Come leggere questo report e cosa NON dimostra</h2><ul>");
   HW("<li>Il meccanismo replica l'EA: range calcolato con le stesse regole (barre/orario/D1), finestra in ora server, coppia stop piazzata solo se il prezzo &egrave; dentro i livelli (altrimenti si aspetta il rientro), scadenza a fine finestra, riempimento con gap, SL/TP relativi al prezzo dell'ordine, un solo trade al giorno e nessuna nuova coppia con una posizione aperta (se la posizione si chiude a met&agrave; finestra la coppia viene ripiazzata da quel momento, per ogni configurazione).</li>");
   HW("<li>Non modellati: filtro spread (MaxSpreadPoints, MaxSpreadPctOfSL), MaxTradesPerDay &gt; 1 (lo studio misura il primo trade del giorno), slippage oltre il gap, allargamenti di spread nei momenti critici. I risultati reali saranno peggiori.</li>");
   HW("<li>Se SL/TP/trailing si toccano dentro la stessa barra l'ordine &egrave; " + Pick(InpOptimistic, "OTTIMISTA (TP prima di SL)", "PESSIMISTA (SL prima di TP; con trailing/BE prima si alza lo stop e poi si testa l'estremo avverso)") +
      ". TF di simulazione: " + EnumToString(g_simTF) + ". Con M1 l'ambiguit&agrave; &egrave; trascurabile; a TF grossolano le colonne &laquo;Ambig. %&raquo; ti dicono quanto pesa. Nella barra di innesco l'estremo avverso &egrave; stimato dalla chiusura.</li>");
   HW("<li>Orizzonte " + IntegerToString(InpMaxHoldHours) + " ore, poi uscita a mercato. L'EA non ha time-stop: una posizione che si trascina oltre blocca anche i giorni successivi, ed &egrave; ci&ograve; che lo studio replica con i trade saltati.</li>");
   HW("<li>Un trade al giorno: in 5 anni sono circa 1000 trade al massimo. Con un campione cos&igrave; la differenza tra due celle vicine &egrave; quasi sempre rumore: conta la struttura (zone intere che funzionano), non il singolo massimo.</li>");
   HW("<li>ATR: SMA del true range come iATR, sul TF " + EnumToString(g_atrTF) + ", valutato sull'ultima barra chiusa prima del piazzamento. L'EA non usa ATR: le griglie ATR e range servono a capire se distanze adattive battono quelle fisse. In automatico i punti derivano dall'ATR mediano, cos&igrave; le griglie sono confrontabili.</li>");
   HW("<li>R-multipli: confrontabili tra famiglie solo con sizing a rischio fisso per trade. L'EA usa lotti fissi (LotSize): con lotti fissi uno SL largo pesa di pi&ugrave; in denaro.</li>");
   HW("<li>Gli sweep di definizione e di orario sono molte ipotesi sullo stesso campione: la soglia di Bonferroni nelle tabelle indica quanto deve essere forte l'IS per non essere data-mining; la conferma vera &egrave; l'OOS.</li>");
   HW("</ul>");
}

int CountDir(const int dir)
{
   int n = 0;
   for(int e = 0; e < ArraySize(g_ev); e++) if(g_ev[e].dir == dir) n++;
   return n;
}

void WriteHtml()
{
   string fn = InpFilePrefix + "_" + _Symbol + ".html";
   g_fh = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(g_fh == INVALID_HANDLE) { Print("Errore: impossibile creare ", fn, " (", GetLastError(), ")"); return; }

   int E = ArraySize(g_ev);
   HtmlStart();
   HW("<h1>MDRB Study - " + _Symbol + "</h1>");
   string rdef;
   if(RangeMode == RANGE_BARS) rdef = IntegerToString(RangeBarsLookback) + " barre " + EnumToString(g_rangeTF) + ", giorno -" + IntegerToString(RangeDaysBack);
   else if(RangeMode == RANGE_TIME) rdef = StringFormat("finestra %02d:%02d-%02d:%02d, giorno -%d", RangeHourStart, RangeMinuteStart, RangeHourEnd, RangeMinuteEnd, RangeDaysBack);
   else rdef = IntegerToString(RangeDaySpan) + " giorni D1 da -" + IntegerToString(RangeDaysBack);
   HW("<div class='note'>Dati " + TimeToString(g_dataFirst, TIME_DATE) + " &rarr; " + TimeToString(g_dataLast, TIME_DATE) + " | range: <b>" + rdef + "</b> | finestra " + HHMM(g_wsMin) + "-" + HHMM(g_weMin) +
      " ora server | offset " + IntegerToString(PendingOrderOffsetPoints) + " pt | sfondamenti: <b>" + IntegerToString(E) + "</b> (long " + IntegerToString(CountDir(1)) + ", short " + IntegerToString(CountDir(-1)) +
      ") | IS: " + IntegerToString(g_split) + " fino al " + TimeToString(g_ev[MathMax(0, g_split - 1)].day, TIME_DATE) + ", OOS: " + IntegerToString(E - g_split) + " | simulazione " + EnumToString(g_simTF) +
      " | orizzonte " + IntegerToString(InpMaxHoldHours) + " h | spread " + Pick(InpSpreadPoints >= 0, IntegerToString(InpSpreadPoints) + " pt fissi", "da barra") + " + comm. " + F(InpCommissionPoints, 1) +
      " pt | ATR mediano " + F(g_medATRpts, 0) + " punti | limiti Min/Max range " + Pick(RequireRangeConfirmation, "APPLICATI", "non applicati") + "</div>");
   for(int i = 0; i < ArraySize(g_warn); i++) HW("<div class='warn'>" + g_warn[i] + "</div>");
   if(E < 150) HW("<div class='warn'>Meno di 150 trade: le griglie sono rumore. Allunga lo storico (InpMonthsBack) o allarga la finestra di ingresso.</div>");
   if(E - g_split < 30) HW("<div class='warn'>Meno di 30 trade in OOS: il verdetto OOS non &egrave; affidabile.</div>");

   HtmlVerdict();
   HtmlFunnel();
   HtmlEventStudy();
   HtmlBreakdown();
   HtmlSweeps();

   HW("<h2>6. Rischio/rendimento: SL e TP in PUNTI FISSI, in ATR, in multipli del RANGE</h2>");
   HW("<div class='note'>Righe: SL. Colonne: RR 1:x (TP = x &middot; SL). SL e TP sono relativi al prezzo dell'ordine stop, come nell'EA. Celle tenui = meno di " + IntegerToString(InpMinTrades) +
      " trade IS. Contorno blu = cella scelta (IS). Il win rate &egrave; colorato rispetto al breakeven 1/(1+RR): conta lo scarto, non il valore assoluto. SL = 1 x range &egrave; circa lo stop sul bordo opposto.</div>");
   for(int f = 0; f < 3; f++)
   {
      HW("<h3 style='font-size:15px;border-top:1px solid #d0d7de;padding-top:10px'>" + FamName(f) + "</h3>");
      HtmlMatrix("Expectancy (R) - In-Sample", f, 0, 0);
      HtmlMatrix("Expectancy (R) - Out-Of-Sample", f, 0, 1);
      HtmlMatrix("Win rate - tutto il campione", f, 1, 2);
      HtmlMatrix("Profit factor - tutto il campione", f, 2, 2);
      HtmlMatrix("t-stat dell'expectancy - tutto il campione", f, 3, 2);
      HtmlMatrix("Max drawdown (R) - tutto il campione", f, 4, 2);
   }

   HW("<h2>6b. Trailing stop</h2>");
   HW("<div class='note'>SL iniziale fisso (" + F(InpTrailSLATR, 2) + " ATR, o " + F(g_cfg[g_base[3]].sl / g_point, 0) + " punti in modalit&agrave; punti), " +
      Pick(InpTrailTPRR > 0.0, "TP a RR " + F(InpTrailTPRR, 1), "nessun TP") + ". Righe: soglia di attivazione. Colonne: distanza dello stop dal prezzo corrente (come l'EA: lo stop sale a gradini, solo se supera il precedente di almeno lo step). Step = " +
      F(InpTrailStepRatio, 2) + " x distanza. Confronta con le righe corrispondenti delle tabelle RR: il trailing aggiunge valore oppure no?</div>");
   for(int f = 3; f < 5; f++)
   {
      HW("<h3 style='font-size:15px;border-top:1px solid #d0d7de;padding-top:10px'>" + FamName(f) + "</h3>");
      HtmlMatrix("Expectancy (R) - In-Sample", f, 0, 0);
      HtmlMatrix("Expectancy (R) - Out-Of-Sample", f, 0, 1);
      HtmlMatrix("Win rate - tutto il campione", f, 1, 2);
      HtmlMatrix("Profit factor - tutto il campione", f, 2, 2);
   }

   HtmlTop10();
   HtmlStability();
   HtmlNotes();
   HW("</body></html>");
   FileClose(g_fh);
   g_fh = INVALID_HANDLE;
   Print("Report HTML: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", fn);
}

void WriteCSV()
{
   string base = InpFilePrefix + "_" + _Symbol;
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);

   int h = FileOpen(base + "_trades.csv", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      string head = "day,dir,wday,part,place_time,fill_time,delay_min,range_pts,range_atr,atr_pts,spread_pts,buy_px,sell_px,gap_delta_pts,amb_trigger,mfe_atr,mae_atr,fakeout,fakeout_hours";
      for(int i = 0; i < g_nH; i++) head += ",ret_" + IntegerToString(g_hor[i]) + "h_atr";
      for(int i = 0; i < NFP; i++) head += ",fp_" + F(g_fpX[i], 1) + "atr";
      for(int i = 0; i < NFR; i++) head += ",fp_" + F(g_frX[i], 2) + "range";
      head += ",ea_R,ea_executed";
      FileWriteString(h, head + "\n");
      for(int e = 0; e < E; e++)
      {
         string ln = TimeToString(g_ev[e].day, TIME_DATE) + "," + IntegerToString(g_ev[e].dir) + "," + IntegerToString(g_ev[e].wday) + "," + Pick(e < g_split, "IS", "OOS") + "," +
                     TimeToString(g_ev[e].tPlace, TIME_DATE | TIME_MINUTES) + "," + TimeToString(g_ev[e].tFill, TIME_DATE | TIME_MINUTES) + "," + F(g_ev[e].delayMin, 0) + "," +
                     F(g_ev[e].width / g_point, 0) + "," + F(g_ev[e].widthAtr, 3) + "," + F(g_ev[e].atr / g_point, 1) + "," + F(g_ev[e].spread / g_point, 1) + "," +
                     F(g_ev[e].buyPx, 6) + "," + F(g_ev[e].sellPx, 6) + "," + F(g_ev[e].delta / g_point, 1) + "," + IntegerToString(g_ev[e].ambTrig) + "," +
                     F(g_ev[e].mfe, 3) + "," + F(g_ev[e].mae, 3) + "," + IntegerToString(g_ev[e].fakeout) + "," + F(g_ev[e].fakeHrs, 2);
         for(int i = 0; i < g_nH; i++) ln += "," + F(g_ev[e].ret[i], 4);
         for(int i = 0; i < NFP; i++) ln += "," + IntegerToString(g_ev[e].fp[i]);
         for(int i = 0; i < NFR; i++) ln += "," + IntegerToString(g_ev[e].fr[i]);
         ln += "," + F((double)g_R[e * C + g_refIdx], 4) + "," + Pick(g_xR[e * C + g_refIdx] != XR_SKIP, "1", "0");
         FileWriteString(h, ln + "\n");
      }
      FileClose(h);
      Print("CSV trade: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", base, "_trades.csv");
   }

   h = FileOpen(base + "_grid.csv", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      FileWriteString(h, "family,row,col,cell,sl,rr_or_tp,act,dist,"
                         "n_is,er_is,wr_is,pf_is,t_is,n_oos,er_oos,wr_oos,pf_oos,t_oos,n_all,er_all,wr_all,pf_all,t_all,dd_all,tmo_pct,amb_pct,skipped,replaced,score_is\n");
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
         ln += "," + F(g_stAll[c].dd, 2) + "," + F(tmo, 2) + "," + F(amb, 2) + "," + IntegerToString(g_skip[c]) + "," + IntegerToString(g_repl[c]) + "," + F(g_score[c], 3);
         FileWriteString(h, ln + "\n");
      }
      FileClose(h);
      Print("CSV griglia: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", base, "_grid.csv");
   }

   h = FileOpen(base + "_sweeps.csv", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      FileWriteString(h, "sweep,definition,trades,cfg,n_is,er_is,t_is,n_oos,er_oos,t_oos\n");
      for(int s = 0; s < 2; s++)
      {
         int K = (s == 0) ? ArraySize(g_s1Lbl) : ArraySize(g_s2Lbl);
         for(int k = 0; k < K; k++)
            for(int c = 0; c < 2; c++)
            {
               SStat a, b;
               string lbl;
               int nTr;
               if(s == 0) { a = g_s1IS[k * 2 + c]; b = g_s1OOS[k * 2 + c]; lbl = g_s1Lbl[k]; nTr = g_s1N[k]; }
               else { a = g_s2IS[k * 2 + c]; b = g_s2OOS[k * 2 + c]; lbl = g_s2Lbl[k]; nTr = g_s2N[k]; }
               string ln = Pick(s == 0, "range", "entry_window") + ",\"" + lbl + "\"," + IntegerToString(nTr) + "," +
                           Pick(c == 0, "ATR_ref", "EA_exit") + "," + IntegerToString(a.n) + "," + F(StatMean(a), 4) + "," + F(StatT(a), 3) + "," + IntegerToString(b.n) + "," + F(StatMean(b), 4) + "," + F(StatT(b), 3);
               FileWriteString(h, ln + "\n");
            }
      }
      FileClose(h);
   }
}

void PrintSummary()
{
   int E = ArraySize(g_ev);
   Print("=============== MDRB STUDY - RIEPILOGO ===============");
   PrintFormat("%s | sfondamenti %d (IS %d / OOS %d) | sim %s | ATR mediano %.0f punti", _Symbol, E, g_split, E - g_split, EnumToString(g_simTF), g_medATRpts);
   PrintFormat("Giorni %d: range non calcolabile %d, scartati %d, mai piazzata %d, senza sfondamento %d, trade %d (L %d / S %d)",
               g_fn.days, g_fn.noRange, g_fn.tooSmall + g_fn.tooBig + g_fn.invalid, g_fn.noPlace, g_fn.noFill, g_fn.filled, g_fn.longs, g_fn.shorts);
   for(int f = 0; f < 6; f++)
   {
      int c = g_best[f];
      if(c < 0) { PrintFormat("%-18s nessuna cella con >=%d trade IS", FamName(f), InpMinTrades); continue; }
      double p;
      string v = Verdict(g_stOOS[c], p);
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

   Comment("MDRB Study: ricostruzione dei setup giornalieri...");
   BuildSetups(g_def, g_ev, g_fn);
   if(IsStopped()) { Comment(""); return; }
   int E = ArraySize(g_ev);
   PrintFormat("Sfondamenti: %d su %d giorni (range non calcolabile %d, piccolo %d, grande %d, nullo %d, mai piazzata %d, senza sfondamento %d, fine dati %d)",
               E, g_fn.days, g_fn.noRange, g_fn.tooSmall, g_fn.tooBig, g_fn.invalid, g_fn.noPlace, g_fn.noFill, g_fn.noData + g_fn.noATR);
   if(E < 20)
   {
      Comment("");
      PrintFormat("Solo %d sfondamenti: troppo pochi per qualunque statistica. Allunga InpMonthsBack, allarga la finestra di entrata o controlla range e orari (ora SERVER).", E);
      return;
   }

   g_nH = 0;
   for(int i = 0; i < NHOR; i++)
      if(g_horAllH[i] <= InpMaxHoldHours) { g_hor[g_nH] = g_horAllH[i]; g_nH++; }
   if(g_nH == 0) { g_hor[0] = 1; g_nH = 1; }

   g_medATRpts = MedianATRPoints();
   AssignBuckets();
   BuildConfigs();
   SimulateEvents(g_ev, g_cfg, g_R, g_F, g_XJ, true);
   if(IsStopped()) { Comment(""); return; }
   AggregateMain();
   ScoreCells();

   if(InpSweepRange) RunSweep1();
   if(InpSweepEntryHours) RunSweep2();
   if(IsStopped()) { Comment(""); return; }

   Comment("MDRB Study: scrittura report...");
   if(InpWriteHTML) WriteHtml();
   if(InpWriteCSV) WriteCSV();
   PrintSummary();
   Comment("");
   PrintFormat("Completato in %.1f s", (GetTickCount() - t0) / 1000.0);
}
//+------------------------------------------------------------------+
