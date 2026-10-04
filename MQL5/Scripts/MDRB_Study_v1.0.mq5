//+------------------------------------------------------------------+
//|  MDRB_Study_v1.0.mq5  (versione 1.10: analisi AUTOMATICA)         |
//|  SCRIPT di studio statistico per MultiDayRangeBreakout (v3.00)    |
//|  Si trascina su un grafico e basta: gira UNA volta sulla storia   |
//|  disponibile, prova DA SOLO tutte le modalita' di range, finestre |
//|  orarie, offset e uscite per orizzonte GIORNALIERO, SETTIMANALE e |
//|  MENSILE, e scrive un unico report. Non apre ordini.              |
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
#property copyright "Advanced Quant Systems - MDRB Study v1.1"
#property version   "1.10"
#property strict
#property script_show_inputs

//=== PARAMETRI DELL'EA (stessi nomi e significato) ===
// NON serve toccare nulla: lo script analizza DA SOLO tutte le modalita' di range, le finestre orarie, le
// distanze/offset e le uscite, per orizzonte giornaliero, settimanale e mensile, su tutta la storia disponibile.
// I valori qui sotto servono solo alla riga di confronto "EA con i tuoi input" (cosa fa l'EA oggi).
input group "=== EA: RANGE (solo per la riga di confronto) ==="
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
input bool RequireRangeConfirmation = false;       // EA: true. Qui false = studia TUTTE le larghezze (le tabelle dicono dove mettere Min/Max)
input double MinRangePoints = 50;
input double MaxRangePoints = 500;

input group "=== EA: FINESTRA DI ENTRATA (ora server) ==="
input int TradeHourStart = 10;
input int TradeMinuteStart = 0;
input int TradeHourEnd = 11;
input int TradeMinuteEnd = 0;
input int ExpireExtraMinutes = 0;
input int PendingOrderOffsetPoints = 20;
input bool ChaseIfBroken = false;

input group "=== EA: USCITE (riga 'EA' del report) ==="
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

input group "=== COSTI ==="
input int    InpSpreadPoints = -1;                  // Spread in punti (-1 = usa lo spread registrato nella barra)
input double InpCommissionPoints = 0.0;             // Commissione round-turn in punti

input group "=== OUTPUT ==="
input bool   InpWriteHTML = true;
input bool   InpWriteCSV = true;
input string InpFilePrefix = "MDRB_Study";

//=== PARAMETRI INTERNI (NON sono input: l'analisi e' automatica e non richiede scelte) ===
enum ENUM_RANK_BY { RANK_TSTAT, RANK_EXPECTANCY, RANK_PF };
bool   InpAuto = true;                      // true = esplora tutto (giornaliero/settimanale/mensile); false = analizza solo la configurazione degli input dell'EA (usato dai test)
int    InpMonthsBack = 0;                   // 0 = tutta la storia disponibile (alla risoluzione piu' fine che copra almeno 3 anni)
ENUM_TIMEFRAMES InpSimTF = PERIOD_M1;       // TF di simulazione; se la storia e' troppo corta ripiega su M5, M15, M30, H1
ENUM_TIMEFRAMES InpATRTimeframe = PERIOD_H1;// TF dell'ATR usato per SL/TP in ATR (l'EA non usa ATR)
int    InpATRPeriod = 14;
int    InpMaxHoldHours = 72;                // Orizzonte massimo di una posizione; poi uscita a mercato (l'EA non ha time-stop)
int    InpISPercent = 70;                   // % di TEMPO In-Sample (taglio per data comune a tutte le definizioni); il resto e' Out-Of-Sample
ENUM_RANK_BY InpRankBy = RANK_TSTAT;        // Metrica per scegliere la cella/definizione migliore (sull'IS)
bool   InpSmoothRank = true;                // Punteggio = media della cella e dei vicini (penalizza i picchi isolati)
int    InpMinTrades = 30;                   // Minimo trade IS per candidare una cella
bool   InpOptimistic = false;               // Ordine intrabarra OTTIMISTA (TP prima di SL). Default: pessimista
bool   InpFastPath = true;                  // Orizzonte adattivo negli sweep (risultati identici, piu' veloce)
string InpSLMultList = "0.5,0.75,1,1.5,2,3";    // SL in multipli di ATR
string InpSLPointsList = "";                // SL in punti; vuoto = automatico (multipli x ATR mediano)
string InpSLRangeList = "0.25,0.5,0.75,1,1.5";  // SL in multipli della larghezza del range (1 = bordo opposto)
double InpRRMin = 1.0;
double InpRRMax = 6.0;
double InpRRStep = 1.0;
double InpTrailSLATR = 1.0;                 // SL iniziale in ATR (trailing)
int    InpTrailSLPoints = 0;                // SL iniziale in punti (0 = ATR mediano x InpTrailSLATR)
string InpTrailActList = "0.5,1,1.5,2,3";   // Attivazione in multipli di ATR
string InpTrailDistList = "0.5,0.75,1,1.5,2";   // Distanza trailing in multipli di ATR
string InpTrailActPoints = "";              // Attivazione in punti; vuoto = automatico
string InpTrailDistPoints = "";             // Distanza in punti; vuoto = automatico
double InpTrailStepRatio = 0.15;            // Step minimo = ratio x distanza
double InpTrailTPRR = 0.0;                  // TP in multipli dello SL durante il trailing (0 = nessun TP)
double InpRefSLATR = 1.0;                   // configurazione di riferimento (mappa, sweep)
double InpRefRR = 2.0;

//--- Costanti
#define EPSILON  0.0000001
#define MAXDIM   16
#define MAXFAM   6
#define NHOR     8
#define NFP      5
#define NFR      3
#define NCLS     3        // classi di orizzonte: giornaliero, settimanale, mensile
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
SDef     g_cur;                    // definizione analizzata a fondo (vincitore di classe, o input dell'EA in modo classico)
string   g_pre = "";               // prefisso della numerazione delle sezioni (una parte per classe)
datetime g_cut = 0;                // taglio IS/OOS per DATA, comune a tutte le definizioni

//--- Esplorazione automatica: universo di definizioni di range x finestre di ingresso
int      g_nR = 0, g_nW = 0;
SDef     g_rDef[];                 // definizione di range (finestra di ingresso da impostare per combinazione)
string   g_rLbl[];
int      g_rCls[];                 // classe: 0 giornaliero, 1 settimanale, 2 mensile
int      g_rChain[];               // righe adiacenti della stessa catena = vicini (per lo smoothing)
int      g_wS[], g_wE[], g_wLen[]; // finestre di ingresso (minuti del giorno)
SStat    g_mIS[], g_mOOS[], g_mAll[];   // [(r*nW+w)*2 + c]: c0 = SL ATR di riferimento, c1 = uscite dell'EA
int      g_mN[];                   // trade per combinazione
double   g_mScore[];               // punteggio IS (eventualmente mediato sui vicini)
bool     g_mValid[];
int      g_win[NCLS];              // combinazione vincente per classe (-1 = nessuna)
int      g_eaN = 0;                // riga di confronto: gli input dell'EA
SStat    g_eaIS[], g_eaOOS[], g_eaAll[];
string   g_clsName[NCLS] = {"Giornaliero", "Settimanale", "Mensile"};
string   g_clsTag[NCLS] = {"giornaliero", "settimanale", "mensile"};

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

//--- Sweep offset / chase / scadenza sul vincitore
string   g_s1Lbl[];
int      g_s1N[];
SStat    g_s1IS[], g_s1OOS[], g_s1All[];
SFunnel  g_s1Fn[];

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
      if(frac >= 0.6 || (InpMonthsBack == 0 && cov >= 3.0 * 365.0 * 86400.0))
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
   Warn(StringFormat("Nessun TF di simulazione copre il periodo richiesto: uso %s (copertura %.0f%%). Alza 'Max barre nel grafico' (Strumenti > Opzioni > Grafici) e rilancia per avere piu' storia a risoluzione fine.", EnumToString(bestTF), 100.0 * bestCov));
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
   if(!LoadSim(from, now)) { Print("Errore: nessun dato per la simulazione"); return false; }
   if(ArraySize(g_rs) > 0 && g_rs[0].time > from) fromPad = g_rs[0].time - 90 * 86400;     // il periodo analizzato parte dove esiste la simulazione
   if(!LoadRates(g_rangeTF, fromPad, now, g_rr)) { Print("Errore: nessun dato sul TF del range"); return false; }
   if(!LoadRates(g_atrTF, fromPad, now, g_ra)) { Print("Errore: nessun dato sul TF dell'ATR"); return false; }
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

   if(autoSL) Print("Nota: SL in punti generati da ATR mediano (", F(med, 0), " punti) x multipli.");
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

// Negli sweep (study = false) la simulazione parte con un orizzonte corto (4 h, poi 24 h, poi quello pieno): se
// TUTTE le configurazioni escono prima della fine del livello, il risultato e' identico a quello con orizzonte
// pieno (l'esito fino all'uscita non dipende dalle barre successive); altrimenti si riesegue al livello superiore.
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
   const int Lfull = g_L;
   int lv[3];
   lv[0] = Lfull; lv[1] = Lfull; lv[2] = Lfull;
   if(!study && InpFastPath)
   {
      lv[0] = MathMin(Lfull, MathMax(2, (int)(4 * 3600 / g_perSim)));
      lv[1] = MathMin(Lfull, MathMax(lv[0], (int)(24 * 3600 / g_perSim)));
   }
   double r0[];
   int f0[], j0[];
   ArrayResize(r0, C);
   ArrayResize(f0, C);
   ArrayResize(j0, C);
   for(int e = 0; e < E; e++)
   {
      if(IsStopped()) { g_L = Lfull; return; }
      if(study && (e & 31) == 0) Comment(StringFormat("MDRB Study: simulazione %d/%d trade x %d configurazioni", e, E, C));
      if(study)
      {
         g_L = Lfull;
         BuildPath(ev[e]);
         EventStudy(ev[e]);
         for(int c = 0; c < C; c++) SimCfgOnEvent(ev[e], cfg[c], r0[c], f0[c], j0[c]);
      }
      else
      {
         for(int k = 0; k < 3; k++)
         {
            if(k > 0 && lv[k] == lv[k - 1]) continue;
            g_L = lv[k];
            BuildPath(ev[e]);
            bool open = false;
            for(int c = 0; c < C; c++)
            {
               SimCfgOnEvent(ev[e], cfg[c], r0[c], f0[c], j0[c]);
               if((f0[c] & 1) != 0 && lv[k] < Lfull) open = true;
            }
            if(!open) break;
         }
         g_L = Lfull;
      }
      int off = e * C;
      for(int c = 0; c < C; c++)
      {
         R[off + c] = (float)r0[c];
         F2[off + c] = (uchar)f0[c];
         XJ[off + c] = j0[c];
      }
   }
   g_L = Lfull;
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
   if(s.n < 2) return 0.0;
   if(sd < EPSILON)      // tutti i trade con lo stesso R (es. tutti stoppati): non e' "t = 0", e' il caso estremo
   {
      double m0 = StatMean(s);
      return (m0 > EPSILON) ? 99.0 : ((m0 < -EPSILON) ? -99.0 : 0.0);
   }
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

// Taglio IS/OOS per DATA, lo stesso per tutte le definizioni: se ogni definizione avesse il proprio taglio (70% dei
// SUOI trade) scegliere la migliore sull'IS userebbe giorni che per un'altra definizione sono gia' OOS.
int SplitFor(const SEvent &ev[])
{
   int E = ArraySize(ev);
   int sp = E;
   for(int i = 0; i < E; i++)
      if(ev[i].day >= g_cut) { sp = i; break; }
   if(sp < 1) sp = 1;
   if(sp > E) sp = E;
   return sp;
}

void AggregateMain()
{
   int C = ArraySize(g_cfg);
   ArrayResize(g_stIS, C);
   ArrayResize(g_stOOS, C);
   ArrayResize(g_stAll, C);
   ArrayResize(g_skip, C);
   ArrayResize(g_repl, C);
   g_split = SplitFor(g_ev);
   AggregateBusy(g_ev, g_cur, g_cfg, C, g_R, g_F, g_XJ, g_split, g_stIS, g_stOOS, g_stAll, g_skip, g_repl, g_xR, g_xT, g_xD);
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
   int split = SplitFor(ev);
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

string RangeText(const SDef &d)
{
   if(d.mode == (int)RANGE_BARS) return IntegerToString(d.lookback) + " barre " + EnumToString(g_rangeTF) + ", giorno -" + IntegerToString(d.daysBack);
   if(d.mode == (int)RANGE_TIME) return StringFormat("finestra %02d:%02d-%02d:%02d, giorno -%d", d.rhs, d.rms, d.rhe, d.rme, d.daysBack);
   return IntegerToString(d.span) + " giorni D1 da -" + IntegerToString(d.daysBack);
}

string ModeName(const SDef &d)
{
   if(d.mode == (int)RANGE_BARS) return "RANGE_BARS";
   if(d.mode == (int)RANGE_TIME) return "RANGE_TIME";
   return "RANGE_PREV_D1";
}

void AddUniqueInt(int &a[], const int v)
{
   for(int i = 0; i < ArraySize(a); i++)
      if(a[i] == v) return;
   int n = ArraySize(a);
   ArrayResize(a, n + 1);
   a[n] = v;
}

//+------------------------------------------------------------------+
//| ESPLORAZIONE AUTOMATICA                                            |
//| Universo = definizioni di range (tutte le modalita' dell'EA) x     |
//| finestre di ingresso. Le definizioni sono raggruppate per          |
//| ORIZZONTE: giornaliero (range fino a 1 giorno: ultime N ore,       |
//| sessioni, giorno precedente), settimanale (D1 2-5 giorni), mensile |
//| (D1 10-21 giorni). Per ogni combinazione: 2 uscite (SL ATR di      |
//| riferimento e uscite dell'EA), eventi e regola "EA occupato"       |
//| identici all'analisi completa.                                     |
//+------------------------------------------------------------------+
void AddRangeRow(const int cls, const int chain, const SDef &d, const string lbl)
{
   int n = ArraySize(g_rDef);
   ArrayResize(g_rDef, n + 1);
   ArrayResize(g_rLbl, n + 1);
   ArrayResize(g_rCls, n + 1);
   ArrayResize(g_rChain, n + 1);
   g_rDef[n] = d;
   g_rLbl[n] = lbl;
   g_rCls[n] = cls;
   g_rChain[n] = chain;
}

void BuildUniverse()
{
   ArrayResize(g_rDef, 0);
   ArrayResize(g_rLbl, 0);
   ArrayResize(g_rCls, 0);
   ArrayResize(g_rChain, 0);
   ArrayResize(g_wS, 0);
   ArrayResize(g_wE, 0);
   ArrayResize(g_wLen, 0);
   int chain = 0;
   SDef d;
   d = g_def;                       // eredita offset / chase / scadenza degli input dell'EA
   int per = MathMax(60, PeriodSeconds(g_rangeTF));

   // --- giornaliero: ultime N ore (barre del TF del range), al piazzamento (giorno -0) o fino all'apertura di oggi (giorno -1)
   double hrs[8] = {1, 2, 3, 4, 6, 8, 12, 24};
   for(int b = 0; b < 2; b++)
   {
      chain++;
      int last = -1;
      for(int i = 0; i < 8; i++)
      {
         int bars = (int)MathMax(1.0, MathRound(hrs[i] * 3600.0 / per));
         if(bars == last) continue;
         last = bars;
         d.mode = (int)RANGE_BARS; d.lookback = bars; d.daysBack = b;
         AddRangeRow(0, chain, d, StringFormat("Ultime %d barre %s (%.1f h), %s", bars, EnumToString(g_rangeTF), bars * per / 3600.0,
                                                Pick(b == 0, "al piazzamento", "fino all'apertura di oggi")));
      }
   }
   // --- giornaliero: sessioni orarie (4 h e 8 h), di oggi (finita prima della finestra di ingresso) o di ieri
   int starts[6] = {0, 4, 8, 12, 16, 20};
   int lens[2] = {4, 8};
   for(int b = 0; b < 2; b++)
      for(int l = 0; l < 2; l++)
      {
         chain++;
         for(int k = 0; k < 6; k++)
         {
            int hs = starts[k];
            if(b == 0 && hs + lens[l] >= 24) continue;     // di oggi: deve chiudersi prima della mezzanotte
            int he = (hs + lens[l]) % 24;
            d.mode = (int)RANGE_TIME; d.rhs = hs; d.rms = 0; d.rhe = he; d.rme = 0; d.daysBack = b;
            AddRangeRow(0, chain, d, StringFormat("Sessione %02d:00-%02d:00 (%d h), %s", hs, he, lens[l], Pick(b == 0, "di oggi", "di ieri")));
         }
      }
   // --- giornaliero: giorno precedente
   chain++;
   d.mode = (int)RANGE_PREV_D1; d.span = 1; d.daysBack = 1;
   AddRangeRow(0, chain, d, "Giorno precedente (D1)");
   // --- settimanale: ultimi 2, 3, 5 giorni D1
   chain++;
   int spW[3] = {2, 3, 5};
   for(int i = 0; i < 3; i++)
   {
      d.mode = (int)RANGE_PREV_D1; d.span = spW[i]; d.daysBack = 1;
      AddRangeRow(1, chain, d, StringFormat("Ultimi %d giorni D1%s", spW[i], Pick(spW[i] == 5, " (settimana)", "")));
   }
   // --- mensile: ultimi 10, 15, 21 giorni D1
   chain++;
   int spM[3] = {10, 15, 21};
   for(int i = 0; i < 3; i++)
   {
      d.mode = (int)RANGE_PREV_D1; d.span = spM[i]; d.daysBack = 1;
      AddRangeRow(2, chain, d, StringFormat("Ultimi %d giorni D1%s", spM[i], Pick(spM[i] == 10, " (2 settimane)", Pick(spM[i] == 15, " (3 settimane)", " (mese)"))));
   }
   g_nR = ArraySize(g_rDef);

   // --- finestre di ingresso: 60, 120 e 240 minuti, senza scavalcare la mezzanotte
   int wl[3] = {60, 120, 240};
   for(int l = 0; l < 3; l++)
      for(int st = 0; st + wl[l] <= 1440; st += wl[l])
      {
         int n = ArraySize(g_wS);
         ArrayResize(g_wS, n + 1);
         ArrayResize(g_wE, n + 1);
         ArrayResize(g_wLen, n + 1);
         g_wS[n] = st;
         g_wE[n] = st + wl[l];
         g_wLen[n] = wl[l];
      }
   g_nW = ArraySize(g_wS);
}

bool RunAutoMap()
{
   BuildUniverse();
   int K = g_nR * g_nW;
   SCfg cfg[];
   BuildSweepCfgs(cfg);
   ArrayResize(g_mN, K);
   ArrayResize(g_mIS, K * 2);
   ArrayResize(g_mOOS, K * 2);
   ArrayResize(g_mAll, K * 2);
   PrintFormat("Esplorazione automatica: %d definizioni di range x %d finestre di ingresso = %d combinazioni", g_nR, g_nW, K);
   uint t0 = GetTickCount();
   for(int r = 0; r < g_nR; r++)
      for(int w = 0; w < g_nW; w++)
      {
         if(IsStopped()) return false;
         int k = r * g_nW + w;
         SDef d;
         d = g_rDef[r];
         d.wsMin = g_wS[w];
         d.weMin = g_wE[w];
         SFunnel fn;
         RunDefStats(d, cfg, g_mIS, g_mOOS, g_mAll, k, g_mN[k], fn);
         if((k % 6) == 0)
         {
            double el = (GetTickCount() - t0) / 1000.0;
            Comment(StringFormat("MDRB Study: esplorazione %d/%d combinazioni (%.0f s, restano ~%.0f s)", k + 1, K, el, el * (K - k - 1) / (k + 1)));
         }
      }
   return true;
}

// punteggio IS di ogni combinazione (SL ATR di riferimento), eventualmente mediato sui vicini (finestre adiacenti
// della stessa durata, definizioni adiacenti della stessa catena); vincitore per classe
void ScoreMap()
{
   int K = g_nR * g_nW;
   ArrayResize(g_mScore, K);
   ArrayResize(g_mValid, K);
   for(int k = 0; k < K; k++) g_mValid[k] = (g_mIS[k * 2].n >= InpMinTrades);
   for(int r = 0; r < g_nR; r++)
      for(int w = 0; w < g_nW; w++)
      {
         int k = r * g_nW + w;
         if(!g_mValid[k]) { g_mScore[k] = -1e9; continue; }
         double raw = RankMetric(g_mIS[k * 2]);
         if(!InpSmoothRank) { g_mScore[k] = raw; continue; }
         double sum = 0.0;
         int cnt = 0;
         for(int dr = -1; dr <= 1; dr++)
         {
            int r2 = r + dr;
            if(r2 < 0 || r2 >= g_nR || g_rChain[r2] != g_rChain[r]) continue;
            for(int dw = -1; dw <= 1; dw++)
            {
               int w2 = w + dw;
               if(w2 < 0 || w2 >= g_nW || g_wLen[w2] != g_wLen[w]) continue;
               int k2 = r2 * g_nW + w2;
               if(!g_mValid[k2]) continue;
               sum += RankMetric(g_mIS[k2 * 2]);
               cnt++;
            }
         }
         g_mScore[k] = (cnt > 0) ? sum / cnt : raw;
      }
   for(int cl = 0; cl < NCLS; cl++)
   {
      g_win[cl] = -1;
      for(int r = 0; r < g_nR; r++)
      {
         if(g_rCls[r] != cl) continue;
         for(int w = 0; w < g_nW; w++)
         {
            int k = r * g_nW + w;
            if(!g_mValid[k]) continue;
            if(g_win[cl] < 0 || g_mScore[k] > g_mScore[g_win[cl]]) g_win[cl] = k;
         }
      }
   }
}

// definizione (range + finestra di ingresso) di una combinazione della mappa
void ComboDef(const int k, SDef &d)
{
   d = g_rDef[k / g_nW];
   d.wsMin = g_wS[k % g_nW];
   d.weMin = g_wE[k % g_nW];
}

void RunEaRow()
{
   SCfg cfg[];
   BuildSweepCfgs(cfg);
   ArrayResize(g_eaIS, 2);
   ArrayResize(g_eaOOS, 2);
   ArrayResize(g_eaAll, 2);
   SFunnel fn;
   RunDefStats(g_def, cfg, g_eaIS, g_eaOOS, g_eaAll, 0, g_eaN, fn);
}

// Offset del livello, ChaseIfBroken e scadenza extra sul vincitore: stessi eventi del vincitore, cambia solo come si piazza la coppia.
void RunOffsetSweep()
{
   ArrayResize(g_s1Lbl, 0);
   SDef defs[];
   ArrayResize(defs, 0);
   double med = MathMax(1.0, g_medATRpts);
   double fo[4] = {0.0, 0.05, 0.1, 0.25};
   int offs[];
   ArrayResize(offs, 0);
   for(int i = 0; i < 4; i++) AddUniqueInt(offs, (int)MathRound(fo[i] * med));
   AddUniqueInt(offs, g_cur.offsetPts);
   AddUniqueInt(offs, g_def.offsetPts);
   ArraySort(offs);
   for(int o = 0; o < ArraySize(offs); o++)
      for(int ch = 0; ch < 2; ch++)
      {
         int n = ArraySize(defs);
         ArrayResize(defs, n + 1);
         defs[n] = g_cur;
         defs[n].offsetPts = offs[o];
         defs[n].chase = (ch == 1);
         ArrayResize(g_s1Lbl, n + 1);
         bool isBase = (offs[o] == g_cur.offsetPts && defs[n].chase == g_cur.chase);
         g_s1Lbl[n] = StringFormat("offset %d pt (%.2f ATR), %s, scadenza +%d min%s", offs[o], offs[o] / med, Pick(ch == 1, "chase", "attesa del rientro"), g_cur.extra, Pick(isBase, "  [= definizione analizzata]", ""));
      }
   int ex[2] = {60, 180};
   for(int x = 0; x < 2; x++)
   {
      int n = ArraySize(defs);
      ArrayResize(defs, n + 1);
      defs[n] = g_cur;
      defs[n].extra = g_cur.extra + ex[x];
      ArrayResize(g_s1Lbl, n + 1);
      g_s1Lbl[n] = StringFormat("offset %d pt (%.2f ATR), %s, scadenza +%d min", g_cur.offsetPts, g_cur.offsetPts / med, Pick(g_cur.chase, "chase", "attesa del rientro"), defs[n].extra);
   }
   int K = ArraySize(defs);
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
      Comment(StringFormat("MDRB Study: offset / chase / scadenza %d/%d", k + 1, K));
      RunDefStats(defs[k], cfg, g_s1IS, g_s1OOS, g_s1All, k, g_s1N[k], g_s1Fn[k]);
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
   HW(".m2 td,.m2 th{font-size:10.5px;padding:2px 4px}.sc{overflow-x:auto}");
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
   HW("<h2>" + g_pre + "1. Verdetto</h2>");
   HW("<div class='note'>Per ogni famiglia la cella migliore &egrave; scelta SOLO sull'In-Sample (metrica: " +
      Pick(InpRankBy == RANK_TSTAT, "t-stat", Pick(InpRankBy == RANK_EXPECTANCY, "expectancy", "profit factor")) +
      Pick(InpSmoothRank, ", mediata sui vicini 3x3", "") + "). L'unico numero onesto &egrave; la colonna OOS: un solo test, fatto su dati mai usati per scegliere. "
      "Un trade = un giorno: il campione &egrave; piccolo, quindi anche un buon risultato vale poco senza conferma OOS. " +
      Pick(InpAuto, "Anche la DEFINIZIONE analizzata qui (range + finestra di ingresso) &egrave; stata scelta sull'IS tra le combinazioni della mappa: l'OOS di questa tabella &egrave; quindi il test unico dell'intera catena di scelte (definizione + cella). ", "") +
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
   HW("<h2>" + g_pre + "2. Cosa succede ogni giorno</h2>");
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
   HW("<h2>" + g_pre + "3. Come si comporta il prezzo dopo lo sfondamento (lordo di costi)</h2>");
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
   HW("<h2>" + g_pre + "4. Quali range funzionano meglio</h2>");
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
   HW("<div class='sc'><table><tr><th class='rl'>Definizione</th><th>Trade</th><th>Giorni senza range valido</th>"
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
   HW("</table></div><div class='note'>Riga evidenziata = migliore sull'IS (SL ATR). t IS verde = supera la soglia di Bonferroni su " + IntegerToString(K) + " righe (t &ge; " + F(tcrit, 2) +
      "). Se nessuna &egrave; verde, la differenza tra le righe &egrave; compatibile con il caso. Ogni riga ha eventi in parte diversi, quindi N cambia.</div>");
}

void HtmlOffsetSweep()
{
   HW("<h2>" + g_pre + "5. Come si piazza la coppia: offset, chase, scadenza</h2>");
   HW("<div class='note'>Stessa definizione di range e stessa finestra del vincitore; cambiano solo la distanza dei livelli dal range (offset, anche in frazioni di ATR), ChaseIfBroken e quanto dura l'ordine oltre la finestra. Due uscite uguali per tutte le righe (SL ATR di riferimento e uscite dell'EA).</div>");
   HtmlSweepTable("Offset / chase / scadenza", "Righe = ipotesi in pi&ugrave;: guarda l'OOS, non l'IS.", g_s1Lbl, g_s1N, g_s1IS, g_s1OOS, g_s1All, g_s1Fn, ArraySize(g_s1Lbl));
}

void HtmlTop10()
{
   HW("<h2>" + g_pre + "7. Prime 10 celle per famiglia (ordinate sul punteggio IS)</h2>");
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
   HW("<h2>" + g_pre + "8. Stabilit&agrave; nel tempo e curve di equity</h2>");
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
   HW("<h2 id='note'>Come leggere questo report e cosa NON dimostra</h2><ul>");
   HW("<li><b>Analisi automatica.</b> Lo script non chiede nulla: prova tutte le modalit&agrave; di range dell'EA (ultime N barre, sessioni orarie, giorni D1), tutte le finestre di ingresso (60, 120 e 240 minuti), raggruppate per orizzonte del range (giornaliero fino a 1 giorno, settimanale 2-5 giorni, mensile 10-21 giorni), su tutta la storia disponibile. Per ogni orizzonte sceglie la combinazione migliore SOLO sull'In-Sample (taglio per data uguale per tutte), poi analizza a fondo quella: uscite, trailing, giorno/settimana/mese. Il numero onesto &egrave; l'Out-Of-Sample della combinazione scelta: un solo test fatto su dati mai usati per scegliere.</li>");
   HW("<li>Il meccanismo replica l'EA: range calcolato con le stesse regole (barre/orario/D1), finestra in ora server, coppia stop piazzata solo se il prezzo &egrave; dentro i livelli (altrimenti si aspetta il rientro), scadenza a fine finestra, riempimento con gap, SL/TP relativi al prezzo dell'ordine, un solo trade al giorno e nessuna nuova coppia con una posizione aperta (se la posizione si chiude a met&agrave; finestra la coppia viene ripiazzata da quel momento, per ogni configurazione).</li>");
   HW("<li>Non modellati: filtro spread (MaxSpreadPoints, MaxSpreadPctOfSL), MaxTradesPerDay &gt; 1 (lo studio misura il primo trade del giorno), slippage oltre il gap, allargamenti di spread nei momenti critici. I risultati reali saranno peggiori. Le finestre di ingresso della mappa non scavalcano la mezzanotte.</li>");
   HW("<li>Se SL/TP/trailing si toccano dentro la stessa barra l'ordine &egrave; " + Pick(InpOptimistic, "OTTIMISTA (TP prima di SL)", "PESSIMISTA (SL prima di TP; con trailing/BE prima si alza lo stop e poi si testa l'estremo avverso)") +
      ". TF di simulazione: " + EnumToString(g_simTF) + ". Con M1 l'ambiguit&agrave; &egrave; trascurabile; a TF grossolano le colonne &laquo;Ambig. %&raquo; ti dicono quanto pesa. Nella barra di innesco l'estremo avverso &egrave; stimato dalla chiusura.</li>");
   HW("<li>Periodo: tutta la storia disponibile, alla risoluzione pi&ugrave; fine che copra almeno 3 anni (M1, poi M5, M15, M30, H1). Se il terminale limita le barre ('Max barre nel grafico') la storia analizzata &egrave; pi&ugrave; corta: la data di inizio &egrave; scritta in cima.</li>");
   HW("<li>Orizzonte " + IntegerToString(InpMaxHoldHours) + " ore, poi uscita a mercato. L'EA non ha time-stop: una posizione che si trascina oltre blocca anche i giorni successivi, ed &egrave; ci&ograve; che lo studio replica con i trade saltati.</li>");
   HW("<li>Un trade al giorno al massimo: con qualche anno di storia sono poche centinaia di trade per combinazione. La differenza tra due celle vicine &egrave; quasi sempre rumore: conta la struttura (zone intere della mappa che funzionano, anche fuori campione), non il singolo massimo.</li>");
   HW("<li>ATR: SMA del true range come iATR, sul TF " + EnumToString(g_atrTF) + ", valutato sull'ultima barra chiusa prima del piazzamento. L'EA non usa ATR: le griglie ATR e range servono a capire se distanze adattive battono quelle fisse. In automatico i punti derivano dall'ATR mediano, cos&igrave; le griglie sono confrontabili.</li>");
   HW("<li>R-multipli: confrontabili tra famiglie solo con sizing a rischio fisso per trade. L'EA usa lotti fissi (LotSize): con lotti fissi uno SL largo pesa di pi&ugrave; in denaro.</li>");
   HW("<li>La mappa contiene centinaia di combinazioni sullo stesso campione: la soglia di Bonferroni indica quanto deve essere forte l'IS per non essere data-mining. Le tre classi (giornaliero, settimanale, mensile) usano gli stessi giorni e lo stesso OOS: un OOS fortunato pu&ograve; confermarle tutte insieme, non sono test indipendenti.</li>");
   HW("</ul>");
}

int CountDir(const int dir)
{
   int n = 0;
   for(int e = 0; e < ArraySize(g_ev); e++) if(g_ev[e].dir == dir) n++;
   return n;
}

//+------------------------------------------------------------------+
//| Report: struttura                                                  |
//+------------------------------------------------------------------+
bool HtmlOpen()
{
   string fn = InpFilePrefix + "_" + _Symbol + ".html";
   g_fh = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(g_fh == INVALID_HANDLE) { Print("Errore: impossibile creare ", fn, " (", GetLastError(), ")"); return false; }
   HtmlStart();
   HW("<h1>MDRB Study - " + _Symbol + "</h1>");
   return true;
}

void HtmlClose()
{
   if(g_fh == INVALID_HANDLE) return;
   HtmlNotes();
   HW("</body></html>");
   FileClose(g_fh);
   g_fh = INVALID_HANDLE;
   Print("Report HTML: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", InpFilePrefix + "_" + _Symbol + ".html");
}

void HtmlGlobalInfo()
{
   HW("<div class='note'>Storia analizzata: <b>" + TimeToString(g_dataFirst, TIME_DATE) + " &rarr; " + TimeToString(g_dataLast, TIME_DATE) + "</b> (tutta quella disponibile, simulazione " + EnumToString(g_simTF) +
      ") | taglio In-Sample / Out-Of-Sample: <b>" + TimeToString(g_cut, TIME_DATE) + "</b> (" + IntegerToString(InpISPercent) + "% del tempo, uguale per tutte le definizioni) | orizzonte massimo " + IntegerToString(InpMaxHoldHours) +
      " h | spread " + Pick(InpSpreadPoints >= 0, IntegerToString(InpSpreadPoints) + " pt fissi", "da barra") + " + comm. " + F(InpCommissionPoints, 1) + " pt | ATR " + EnumToString(g_atrTF) + "(" + IntegerToString(InpATRPeriod) +
      ") | limiti Min/Max range dell'EA " + Pick(RequireRangeConfirmation, "APPLICATI", "non applicati (le tabelle dicono dove metterli)") + "</div>");
   for(int i = 0; i < ArraySize(g_warn); i++) HW("<div class='warn'>" + g_warn[i] + "</div>");
}

// parametri dell'EA che riproducono la definizione analizzata
string EaInputsText(const SDef &d)
{
   string s = "RangeMode=" + ModeName(d) + ", ";
   if(d.mode == (int)RANGE_BARS) s += "RangeBarsLookback=" + IntegerToString(d.lookback) + " (Timeframe=" + EnumToString(g_rangeTF) + "), RangeDaysBack=" + IntegerToString(d.daysBack);
   else if(d.mode == (int)RANGE_TIME) s += StringFormat("RangeHourStart=%d, RangeMinuteStart=%d, RangeHourEnd=%d, RangeMinuteEnd=%d, RangeDaysBack=%d", d.rhs, d.rms, d.rhe, d.rme, d.daysBack);
   else s += "RangeDaySpan=" + IntegerToString(d.span) + ", RangeDaysBack=" + IntegerToString(d.daysBack);
   int we = d.weMin % 1440;
   s += StringFormat(", TradeHourStart=%d, TradeMinuteStart=%d, TradeHourEnd=%d, TradeMinuteEnd=%d, ExpireExtraMinutes=%d, PendingOrderOffsetPoints=%d, ChaseIfBroken=%s",
                     d.wsMin / 60, d.wsMin % 60, we / 60, we % 60, d.extra, d.offsetPts, Pick(d.chase, "true", "false"));
   return s;
}

void HtmlClassIntro()
{
   int E = ArraySize(g_ev);
   HW("<div class='note'>range: <b>" + RangeText(g_cur) + "</b> (" + ModeName(g_cur) + ") | finestra di entrata <b>" + HHMM(g_cur.wsMin) + "-" + HHMM(g_cur.weMin) +
      "</b> ora server | offset " + IntegerToString(g_cur.offsetPts) + " pt | sfondamenti: <b>" + IntegerToString(E) + "</b> (long " + IntegerToString(CountDir(1)) + ", short " + IntegerToString(CountDir(-1)) +
      ") | IS: " + IntegerToString(g_split) + " trade fino al " + TimeToString(g_ev[MathMax(0, g_split - 1)].day, TIME_DATE) + ", OOS: " + IntegerToString(E - g_split) +
      " | ATR mediano " + F(g_medATRpts, 0) + " punti</div>");
   HW("<div class='note'>Per riprodurre questa definizione nell'EA: <span class='mono'>" + EaInputsText(g_cur) + "</span></div>");
   if(E < 150) HW("<div class='warn'>Meno di 150 trade: le griglie sono rumore. La storia disponibile &egrave; corta o la finestra &egrave; stretta.</div>");
   if(E - g_split < 30) HW("<div class='warn'>Meno di 30 trade in OOS: il verdetto OOS non &egrave; affidabile.</div>");
}

//+------------------------------------------------------------------+
//| Calendario: giorno, settimana, mese                                |
//+------------------------------------------------------------------+
void CalRow(const string label, const double &v[], const int n)
{
   if(n < 2) { HW("<tr><th class='rl'>" + label + "</th><td colspan='7'>dati insufficienti</td></tr>"); return; }
   double sum = 0.0, sum2 = 0.0, mn = 1e18, mx = -1e18;
   int pos = 0;
   for(int i = 0; i < n; i++)
   {
      sum += v[i]; sum2 += v[i] * v[i];
      if(v[i] < mn) mn = v[i];
      if(v[i] > mx) mx = v[i];
      if(v[i] > 0.0) pos++;
   }
   double mean = sum / n;
   double var = (sum2 - sum * sum / n) / (n - 1);
   double sd = (var > 0.0) ? MathSqrt(var) : 0.0;
   double t = (sd > EPSILON) ? mean / (sd / MathSqrt((double)n)) : 0.0;
   string cls = (MathAbs(t) >= 2.0) ? ((t > 0.0) ? " class='ok'" : " class='bad'") : "";
   HW("<tr><th class='rl'>" + label + "</th><td>" + IntegerToString(n) + "</td><td>" + F(100.0 * pos / n, 1) + "%</td><td>" + F(mean, 3) + "</td><td>" + F(sd, 3) +
      "</td><td" + cls + ">" + F(t, 2) + "</td><td>" + F(mn, 2) + "</td><td>" + F(mx, 2) + "</td></tr>\n");
}

void HtmlCalendar()
{
   int E = ArraySize(g_ev);
   int C = ArraySize(g_cfg);
   int fin[2];
   string nm[2];
   string nmS[2];
   int nf = 0;
   if(g_best[1] >= 0) { fin[nf] = g_best[1]; nm[nf] = "SL in ATR scelto sull'IS: " + CellDesc(g_best[1]); nmS[nf] = "SL ATR scelto"; nf++; }
   if(g_refIdx >= 0) { fin[nf] = g_refIdx; nm[nf] = "Uscite dell'EA (SL/TP + BE + trailing dei tuoi input)"; nmS[nf] = "Uscite EA"; nf++; }
   if(nf == 0 || E < 2) return;
   HW("<h2>" + g_pre + "8b. Calendario: giorno, settimana, mese</h2>");
   HW("<div class='note'>Trade eseguiti secondo la regola dell'EA, in R. Giorno = un trade; settimana = luned&igrave;-domenica; mese = mese solare (giorno di piazzamento). Un edge reale non dipende da pochi mesi fortunati: guarda la quota di periodi positivi e la t. Le righe settimana e mese sommano le R dei trade del periodo.</div>");

   MqlDateTime a0, a1;
   TimeToStruct(g_ev[0].day, a0);
   TimeToStruct(g_ev[E - 1].day, a1);
   int m0 = a0.year * 12 + a0.mon - 1;
   int nMon = (a1.year * 12 + a1.mon - 1) - m0 + 1;
   long w0 = ((long)g_ev[0].day / 86400 + 3) / 7;
   int nWk = (int)(((long)g_ev[E - 1].day / 86400 + 3) / 7 - w0) + 1;
   if(nMon < 1 || nWk < 1) return;
   double monS[], wkS[];
   int monC[], wkC[];
   ArrayResize(monS, nf * nMon);
   ArrayResize(monC, nf * nMon);
   ArrayResize(wkS, nf * nWk);
   ArrayResize(wkC, nf * nWk);
   ArrayInitialize(monS, 0.0);
   ArrayInitialize(wkS, 0.0);
   ArrayInitialize(monC, 0);
   ArrayInitialize(wkC, 0);

   HW("<h3>Riepilogo per periodo</h3><table><tr><th class='rl'>Uscita / periodo</th><th>Periodi con trade</th><th>% periodi positivi</th><th>R medio per periodo</th><th>Dev. std.</th><th>t</th><th>Peggiore (R)</th><th>Migliore (R)</th></tr>");
   for(int i = 0; i < nf; i++)
   {
      double dd[];
      ArrayResize(dd, 0);
      int streak = 0, maxStreak = 0;
      for(int e = 0; e < E; e++)
      {
         float xr = g_xR[e * C + fin[i]];
         if(xr == XR_SKIP) continue;
         double r = (double)xr;
         int sz = ArraySize(dd);
         ArrayResize(dd, sz + 1);
         dd[sz] = r;
         if(r < 0.0) { streak++; if(streak > maxStreak) maxStreak = streak; }
         else streak = 0;
         MqlDateTime dt;
         TimeToStruct(g_ev[e].day, dt);
         int mi = dt.year * 12 + dt.mon - 1 - m0;
         int wi = (int)(((long)g_ev[e].day / 86400 + 3) / 7 - w0);
         if(mi >= 0 && mi < nMon) { monS[i * nMon + mi] += r; monC[i * nMon + mi]++; }
         if(wi >= 0 && wi < nWk) { wkS[i * nWk + wi] += r; wkC[i * nWk + wi]++; }
      }
      HW("<tr><th class='rl' colspan='8' style='background:#f6f8fa'>" + nm[i] + " &mdash; serie perdente pi&ugrave; lunga: " + IntegerToString(maxStreak) + " trade consecutivi</th></tr>");
      CalRow("Giorno (1 trade)", dd, ArraySize(dd));
      double wk[], mo[];
      ArrayResize(wk, 0);
      ArrayResize(mo, 0);
      for(int k = 0; k < nWk; k++)
         if(wkC[i * nWk + k] > 0) { int sz = ArraySize(wk); ArrayResize(wk, sz + 1); wk[sz] = wkS[i * nWk + k]; }
      for(int k = 0; k < nMon; k++)
         if(monC[i * nMon + k] > 0) { int sz = ArraySize(mo); ArrayResize(mo, sz + 1); mo[sz] = monS[i * nMon + k]; }
      CalRow("Settimana", wk, ArraySize(wk));
      CalRow("Mese", mo, ArraySize(mo));
   }
   HW("</table>");

   HW("<h3>Mese per mese (somma R / N trade)</h3><table class='m'><tr><th>Mese</th>");
   for(int i = 0; i < nf; i++) HW("<th>" + nmS[i] + "</th>");
   HW("</tr>\n");
   for(int k = 0; k < nMon; k++)
   {
      int mm = m0 + k;
      HW("<tr><th>" + IntegerToString(mm / 12) + "-" + StringFormat("%02d", mm % 12 + 1) + "</th>");
      for(int i = 0; i < nf; i++)
      {
         int n = monC[i * nMon + k];
         double sm = monS[i * nMon + k];
         string bg = (n > 0) ? " style='background:" + Heat(sm, 3.0) + "'" : "";
         HW("<td" + bg + ">" + Pick(n > 0, F(sm, 2) + " (" + IntegerToString(n) + ")", "-") + "</td>");
      }
      HW("</tr>\n");
   }
   HW("</table>");
}

//+------------------------------------------------------------------+
//| Sintesi e mappa dell'esplorazione automatica                       |
//+------------------------------------------------------------------+
int ValidInClass(const int cl)
{
   int n = 0;
   for(int r = 0; r < g_nR; r++)
   {
      if(g_rCls[r] != cl) continue;
      for(int w = 0; w < g_nW; w++)
         if(g_mValid[r * g_nW + w]) n++;
   }
   return n;
}

void SumRow(const string label, const string defTxt, const string winTxt, const int K, const SStat &isA, const SStat &oosA, const SStat &oosB, const bool chosen)
{
   double tcrit = chosen ? NormInvUpper(0.05 / MathMax(1, K)) : 1.645;
   double p;
   string v = Verdict(oosA, p);
   if(chosen && StatMean(isA) <= 0.0) v += " <span class='note'>(nessuna combinazione con E[R] IS positivo)</span>";
   else if(chosen && StatT(isA) < tcrit) v += " <span class='note'>(t IS sotto la soglia di correzione multipla)</span>";
   HW("<tr><th class='rl'>" + label + "</th><td class='mono' style='text-align:left'>" + defTxt + "</td><td>" + winTxt + "</td><td>" + Pick(chosen, IntegerToString(K), "-") + "</td><td>" + F(tcrit, 2) + "</td><td>" +
      IntegerToString(isA.n) + "</td><td>" + F(StatMean(isA), 3) + "</td><td>" + F(StatT(isA), 2) + "</td><td>" + IntegerToString(oosA.n) + "</td><td>" + F(StatMean(oosA), 3) + "</td><td>" +
      F(StatT(oosA), 2) + "</td><td>" + F(p, 3) + "</td><td>" + F(StatMean(oosB), 3) + "</td><td class='rl' style='text-align:left'>" + v + "</td></tr>\n");
}

void HtmlAutoSummary()
{
   int K = g_nR * g_nW;
   HW("<h2 id='sintesi'>Sintesi: giornaliero, settimanale, mensile</h2>");
   HW("<div class='note'>Lo script ha provato da solo <b>" + IntegerToString(K) + "</b> combinazioni di (definizione di range &times; finestra di ingresso) su tutta la storia disponibile. Per ogni orizzonte del range la combinazione migliore &egrave; scelta SOLO sull'In-Sample " +
      "(SL " + F(InpRefSLATR, 2) + " ATR / RR 1:" + F(InpRefRR, 1) + ", metrica " + Pick(InpRankBy == RANK_TSTAT, "t-stat", Pick(InpRankBy == RANK_EXPECTANCY, "expectancy", "profit factor")) + Pick(InpSmoothRank, ", mediata sui vicini", "") +
      "). L'unico numero onesto &egrave; l'Out-Of-Sample di quella scelta (un solo test). Dopo la sintesi trovi la mappa completa di ogni orizzonte e, per ognuno, l'analisi a fondo (uscite, trailing, giorno/settimana/mese). " +
      "I tre orizzonti usano gli stessi giorni: un OOS fortunato pu&ograve; confermarli tutti insieme.</div>");
   HW("<table><tr><th class='rl'>Orizzonte del range</th><th class='rl'>Definizione scelta (IS)</th><th>Finestra di ingresso</th><th>Combinazioni valide</th><th>t critico*</th><th>N IS</th><th>E[R] IS</th><th>t IS</th><th>N OOS</th>");
   HW("<th>E[R] OOS</th><th>t OOS</th><th>p OOS</th><th>E[R] OOS con le uscite dell'EA</th><th class='rl'>Esito</th></tr>");
   for(int cl = 0; cl < NCLS; cl++)
   {
      int k = g_win[cl];
      if(k < 0) { HW("<tr><th class='rl'>" + g_clsName[cl] + "</th><td colspan='13' class='rl'>nessuna combinazione con almeno " + IntegerToString(InpMinTrades) + " trade IS</td></tr>"); continue; }
      SumRow(g_clsName[cl], g_rLbl[k / g_nW], HHMM(g_wS[k % g_nW]) + "-" + HHMM(g_wE[k % g_nW]), ValidInClass(cl), g_mIS[k * 2], g_mOOS[k * 2], g_mOOS[k * 2 + 1], true);
   }
   SumRow("EA con i tuoi input (non scelta)", RangeText(g_def), HHMM(g_def.wsMin) + "-" + HHMM(g_def.weMin), 1, g_eaIS[0], g_eaOOS[0], g_eaOOS[1], false);
   HW("</table><div class='note'>* soglia t (one-sided 5%) con correzione di Bonferroni sul numero di combinazioni valide dell'orizzonte: conservativa perch&eacute; le combinazioni sono correlate, ma &egrave; l'ordine di grandezza giusto per il data-mining. ");
   HW("L'ultima riga non &egrave; stata scelta: sono i parametri dell'EA nei suoi input, quindi vale come test unico a posteriori. Se la scelta per un orizzonte ha OOS negativo o non significativo, per quell'orizzonte non c'&egrave; un edge dimostrato.</div>");
}

void MapCell(const int k, const int part, const double sc)
{
   SStat s;
   if(part == 0) s = g_mIS[k * 2]; else s = g_mOOS[k * 2];
   bool win = false;
   for(int cl = 0; cl < NCLS; cl++) if(g_win[cl] == k) win = true;
   string cls = "";
   if(!g_mValid[k]) cls = " class='lo'";
   else if(win) cls = " class='best'";
   if(s.n == 0) { HW("<td" + cls + ">-</td>"); return; }
   double m = StatMean(s);
   string bg = (g_mValid[k] && m != 0.0) ? " style='background:" + Heat(m, sc) + "'" : "";
   HW("<td" + cls + bg + " title='N " + IntegerToString(s.n) + " | E[R] " + F(m, 3) + " | t " + F(StatT(s), 2) + " | win " + F(StatWR(s), 1) + "%'>" + F(m, 2) + "</td>");
}

void HtmlAutoMap(const int cl)
{
   int rows[];
   ArrayResize(rows, 0);
   for(int r = 0; r < g_nR; r++)
      if(g_rCls[r] == cl) { int sz = ArraySize(rows); ArrayResize(rows, sz + 1); rows[sz] = r; }
   int nr = ArraySize(rows);
   if(nr == 0) return;
   int nValid = ValidInClass(cl);
   double sc = 0.0;
   for(int i = 0; i < nr; i++)
      for(int w = 0; w < g_nW; w++)
      {
         int k = rows[i] * g_nW + w;
         if(!g_mValid[k]) continue;
         sc = MathMax(sc, MathAbs(StatMean(g_mIS[k * 2])));
         if(g_mOOS[k * 2].n >= 10) sc = MathMax(sc, MathAbs(StatMean(g_mOOS[k * 2])));
      }
   sc = MathMin(0.4, MathMax(0.05, sc));
   double tcrit = NormInvUpper(0.05 / MathMax(1, nValid));

   HW("<h2 id='mappa" + IntegerToString(cl) + "'>Mappa &mdash; orizzonte " + g_clsName[cl] + ": " + IntegerToString(nr) + " definizioni di range &times; " + IntegerToString(g_nW) + " finestre di ingresso</h2>");
   HW("<div class='note'>Ogni cella &egrave; una combinazione (range + finestra di ingresso) con SL " + F(InpRefSLATR, 2) + " ATR / RR 1:" + F(InpRefRR, 1) + ", netto di costi, regola dell'EA applicata. Colonna = ora di inizio della finestra (ora server) per durata. " +
      "Celle tenui = meno di " + IntegerToString(InpMinTrades) + " trade IS. Contorno blu = combinazione scelta. Passa il mouse su una cella per N, t e win rate. " +
      "L'ultima riga e l'ultima colonna sono la media delle celle valide: una zona che funziona dovrebbe vedersi in entrambe le mappe (IS e OOS) e non in una sola cella.</div>");
   for(int part = 0; part < 2; part++)
   {
      HW("<h3>E[R] " + Pick(part == 0, "In-Sample", "Out-Of-Sample") + "</h3><div class='sc'><table class='m m2'><tr><th rowspan='2' class='rl'>Definizione di range</th>");
      int w = 0;
      while(w < g_nW)
      {
         int len = g_wLen[w];
         int c = 0;
         while(w + c < g_nW && g_wLen[w + c] == len) c++;
         HW("<th colspan='" + IntegerToString(c) + "'>finestra " + IntegerToString(len) + " min</th>");
         w += c;
      }
      HW("<th rowspan='2'>Media (60 min)</th></tr><tr>");
      for(int w2 = 0; w2 < g_nW; w2++) HW("<th>" + StringFormat("%02d", g_wS[w2] / 60) + "</th>");
      HW("</tr>\n");
      double colSum[], colCnt[];
      ArrayResize(colSum, g_nW);
      ArrayResize(colCnt, g_nW);
      ArrayInitialize(colSum, 0.0);
      ArrayInitialize(colCnt, 0.0);
      for(int i = 0; i < nr; i++)
      {
         HW("<tr><th class='rl'>" + g_rLbl[rows[i]] + "</th>");
         double rs = 0.0, rc = 0.0;
         for(int w3 = 0; w3 < g_nW; w3++)
         {
            int k = rows[i] * g_nW + w3;
            MapCell(k, part, sc);
            if(g_mValid[k])
            {
               SStat sc3;
               if(part == 0) sc3 = g_mIS[k * 2]; else sc3 = g_mOOS[k * 2];
               double m = StatMean(sc3);
               colSum[w3] += m; colCnt[w3] += 1.0;
               if(g_wLen[w3] == 60) { rs += m; rc += 1.0; }
            }
         }
         HW(Pick(rc > 0.0, "<td style='background:" + Heat(rs / MathMax(1.0, rc), sc) + "'>" + F(rs / MathMax(1.0, rc), 3) + "</td>", "<td>-</td>") + "</tr>\n");
      }
      HW("<tr><th class='rl'>Media (celle valide)</th>");
      for(int w4 = 0; w4 < g_nW; w4++)
         HW(Pick(colCnt[w4] > 0.0, "<td style='background:" + Heat(colSum[w4] / colCnt[w4], sc) + "'>" + F(colSum[w4] / colCnt[w4], 3) + "</td>", "<td>-</td>"));
      HW("<td></td></tr></table></div>");
   }

   // prime 12 combinazioni per punteggio IS
   int top[12];
   int nt = 0;
   for(int q = 0; q < 12; q++)
   {
      int bk = -1;
      for(int i = 0; i < nr; i++)
         for(int w = 0; w < g_nW; w++)
         {
            int k = rows[i] * g_nW + w;
            if(!g_mValid[k]) continue;
            bool used = false;
            for(int j = 0; j < nt; j++) if(top[j] == k) used = true;
            if(used) continue;
            if(bk < 0 || g_mScore[k] > g_mScore[bk]) bk = k;
         }
      if(bk < 0) break;
      top[nt] = bk;
      nt++;
   }
   HW("<h3>Prime " + IntegerToString(nt) + " combinazioni per punteggio IS</h3><table><tr><th class='rl'>Definizione di range</th><th>Finestra</th><th>Punteggio</th><th>N IS</th><th>E[R] IS</th><th>t IS</th><th>N OOS</th><th>E[R] OOS</th><th>t OOS</th><th>p OOS</th><th>E[R] OOS uscite EA</th></tr>");
   int oosPos = 0;
   for(int i = 0; i < nt; i++)
   {
      int k = top[i];
      SStat a, b;
      a = g_mIS[k * 2];
      b = g_mOOS[k * 2];
      double p = NormUpper(StatT(b));
      if(StatMean(b) > 0.0) oosPos++;
      string tcl = (StatT(a) >= tcrit) ? " class='ok'" : "";
      string rcl = (i == 0) ? " class='bestrow'" : "";
      HW("<tr" + rcl + "><th class='rl'>" + g_rLbl[k / g_nW] + "</th><td>" + HHMM(g_wS[k % g_nW]) + "-" + HHMM(g_wE[k % g_nW]) + "</td><td>" + F(g_mScore[k], 2) + "</td><td>" + IntegerToString(a.n) + "</td><td>" + F(StatMean(a), 3) +
         "</td><td" + tcl + ">" + F(StatT(a), 2) + "</td><td>" + IntegerToString(b.n) + "</td><td>" + F(StatMean(b), 3) + "</td><td>" + F(StatT(b), 2) + "</td><td>" + Pick(b.n >= 20, F(p, 3), "-") + "</td><td>" +
         F(StatMean(g_mOOS[k * 2 + 1]), 3) + "</td></tr>\n");
   }
   HW("</table><div class='note'>t IS verde = supera la soglia di Bonferroni su " + IntegerToString(nValid) + " combinazioni (t &ge; " + F(tcrit, 2) + "). Delle prime " + IntegerToString(nt) + ", " + IntegerToString(oosPos) +
      " hanno E[R] OOS positivo: senza edge ci si aspetta circa la met&agrave;.</div>");

   // la mappa IS predice la mappa OOS?
   double ia[], ib[];
   ArrayResize(ia, 0);
   ArrayResize(ib, 0);
   for(int i = 0; i < nr; i++)
      for(int w = 0; w < g_nW; w++)
      {
         int k = rows[i] * g_nW + w;
         if(!g_mValid[k] || g_mOOS[k * 2].n < 10) continue;
         int sz = ArraySize(ia);
         ArrayResize(ia, sz + 1);
         ArrayResize(ib, sz + 1);
         ia[sz] = StatMean(g_mIS[k * 2]);
         ib[sz] = StatMean(g_mOOS[k * 2]);
      }
   int nn = ArraySize(ia);
   double rho = Spearman(ia, ib, nn);
   string lec = "dati insufficienti";
   if(nn >= 8) lec = (rho >= 0.5) ? "<span class='ok'>mappa stabile</span>" : ((rho >= 0.2) ? "<span class='mid'>mappa debole</span>" : "<span class='bad'>mappa instabile: scegliere la cella migliore insegue rumore</span>");
   HW("<div class='note'>La mappa si ripete fuori campione? Spearman IS-OOS su " + IntegerToString(nn) + " combinazioni: <b>" + F(rho, 2) + "</b> &mdash; " + lec + ". Correlazione ~0 = la scelta sull'IS non ha valore predittivo. " +
      "Una correlazione alta non prova un edge (anche i costi creano struttura: finestre in ore di spread alto perdono sempre di pi&ugrave;); conta il segno di E[R] OOS.</div>");
}

//+------------------------------------------------------------------+
//| Corpo dell'analisi a fondo (una definizione)                       |
//+------------------------------------------------------------------+
void WriteClassBody()
{
   HtmlClassIntro();
   HtmlVerdict();
   HtmlFunnel();
   HtmlEventStudy();
   HtmlBreakdown();
   if(InpAuto && ArraySize(g_s1Lbl) > 0) HtmlOffsetSweep();

   HW("<h2>" + g_pre + "6. Rischio/rendimento: SL e TP in PUNTI FISSI, in ATR, in multipli del RANGE</h2>");
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

   HW("<h2>" + g_pre + "6b. Trailing stop</h2>");
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
   HtmlCalendar();
}

//+------------------------------------------------------------------+
//| CSV                                                                |
//+------------------------------------------------------------------+
void WriteCSV(const string suffix)
{
   string base = InpFilePrefix + "_" + _Symbol + Pick(suffix == "", "", "_" + suffix);
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

   int K = ArraySize(g_s1Lbl);
   if(K > 0)
   {
      h = FileOpen(base + "_offsets.csv", FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h != INVALID_HANDLE)
      {
         FileWriteString(h, "definition,trades,cfg,n_is,er_is,t_is,n_oos,er_oos,t_oos\n");
         for(int k = 0; k < K; k++)
            for(int c = 0; c < 2; c++)
            {
               SStat a, b;
               a = g_s1IS[k * 2 + c];
               b = g_s1OOS[k * 2 + c];
               FileWriteString(h, "\"" + g_s1Lbl[k] + "\"," + IntegerToString(g_s1N[k]) + "," + Pick(c == 0, "ATR_ref", "EA_exit") + "," + IntegerToString(a.n) + "," + F(StatMean(a), 4) + "," + F(StatT(a), 3) + "," +
                               IntegerToString(b.n) + "," + F(StatMean(b), 4) + "," + F(StatT(b), 3) + "\n");
            }
         FileClose(h);
      }
   }
}

// tutta la mappa: una riga per combinazione x uscita; include i parametri per riprodurre la combinazione
void WriteMapCSV()
{
   string base = InpFilePrefix + "_" + _Symbol;
   int h = FileOpen(base + "_map.csv", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, "class,range,mode,days_back,lookback_bars,rhs,rms,rhe,rme,span,ws_min,we_min,valid,winner,trades,cfg,n_is,er_is,t_is,wr_is,n_oos,er_oos,t_oos,wr_oos,score_is\n");
   for(int r = 0; r < g_nR; r++)
      for(int w = 0; w < g_nW; w++)
      {
         int k = r * g_nW + w;
         bool win = false;
         for(int cl = 0; cl < NCLS; cl++) if(g_win[cl] == k) win = true;
         for(int c = 0; c < 2; c++)
         {
            SStat a, b;
            a = g_mIS[k * 2 + c];
            b = g_mOOS[k * 2 + c];
            string ln = g_clsTag[g_rCls[r]] + ",\"" + g_rLbl[r] + "\"," + IntegerToString(g_rDef[r].mode) + "," + IntegerToString(g_rDef[r].daysBack) + "," + IntegerToString(g_rDef[r].lookback) + "," +
                        IntegerToString(g_rDef[r].rhs) + "," + IntegerToString(g_rDef[r].rms) + "," + IntegerToString(g_rDef[r].rhe) + "," + IntegerToString(g_rDef[r].rme) + "," + IntegerToString(g_rDef[r].span) + "," +
                        IntegerToString(g_wS[w]) + "," + IntegerToString(g_wE[w]) + "," + Pick(g_mValid[k], "1", "0") + "," + Pick(win, "1", "0") + "," + IntegerToString(g_mN[k]) + "," + Pick(c == 0, "ATR_ref", "EA_exit") + "," +
                        IntegerToString(a.n) + "," + F(StatMean(a), 5) + "," + F(StatT(a), 4) + "," + F(StatWR(a), 2) + "," + IntegerToString(b.n) + "," + F(StatMean(b), 5) + "," + F(StatT(b), 4) + "," + F(StatWR(b), 2) + "," + F(g_mScore[k], 4);
            FileWriteString(h, ln + "\n");
         }
      }
   FileClose(h);
   Print("CSV mappa: ", TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", base, "_map.csv");
}

void PrintSummary(const string label)
{
   int E = ArraySize(g_ev);
   Print("=============== MDRB STUDY - RIEPILOGO: ", label, " ===============");
   PrintFormat("%s | range %s, finestra %s-%s | sfondamenti %d (IS %d / OOS %d) | sim %s | ATR mediano %.0f punti", _Symbol, RangeText(g_cur), HHMM(g_cur.wsMin), HHMM(g_cur.weMin), E, g_split, E - g_split, EnumToString(g_simTF), g_medATRpts);
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
//| Analisi a fondo della definizione g_cur                            |
//+------------------------------------------------------------------+
bool AnalyzeCur()
{
   BuildSetups(g_cur, g_ev, g_fn);
   if(IsStopped()) return false;
   int E = ArraySize(g_ev);
   PrintFormat("Sfondamenti: %d su %d giorni (range non calcolabile %d, piccolo %d, grande %d, nullo %d, mai piazzata %d, senza sfondamento %d, fine dati %d)",
               E, g_fn.days, g_fn.noRange, g_fn.tooSmall, g_fn.tooBig, g_fn.invalid, g_fn.noPlace, g_fn.noFill, g_fn.noData + g_fn.noATR);
   if(E < 20)
   {
      Comment("");
      PrintFormat("Solo %d sfondamenti: troppo pochi per qualunque statistica (storia corta o finestra/range da controllare: ora SERVER).", E);
      return false;
   }
   g_medATRpts = MedianATRPoints();
   AssignBuckets();
   BuildConfigs();
   SimulateEvents(g_ev, g_cfg, g_R, g_F, g_XJ, true);
   if(IsStopped()) return false;
   AggregateMain();
   ScoreCells();
   return true;
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
   g_cut = g_dataFirst + (datetime)((double)(g_dataLast - g_dataFirst) * InpISPercent / 100.0);
   for(int i = 0; i < NCLS; i++) g_win[i] = -1;
   ArrayResize(g_s1Lbl, 0);

   g_nH = 0;
   for(int i = 0; i < NHOR; i++)
      if(g_horAllH[i] <= InpMaxHoldHours) { g_hor[g_nH] = g_horAllH[i]; g_nH++; }
   if(g_nH == 0) { g_hor[0] = 1; g_nH = 1; }

   if(!InpAuto)
   {
      // modo classico: analizza solo la configurazione degli input dell'EA
      g_cur = g_def;
      g_pre = "";
      Comment("MDRB Study: ricostruzione dei setup giornalieri...");
      if(!AnalyzeCur()) { Comment(""); return; }
      if(InpWriteHTML && HtmlOpen())
      {
         HtmlGlobalInfo();
         WriteClassBody();
         HtmlClose();
      }
      if(InpWriteCSV) WriteCSV("");
      PrintSummary("configurazione degli input dell'EA");
   }
   else
   {
      if(!RunAutoMap()) { Comment(""); return; }
      ScoreMap();
      RunEaRow();
      if(InpWriteCSV) WriteMapCSV();
      bool html = (InpWriteHTML && HtmlOpen());
      if(html)
      {
         HtmlGlobalInfo();
         HW("<div class='note'>Indice: <a href='#sintesi'>Sintesi</a> &middot; Mappe: <a href='#mappa0'>giornaliero</a>, <a href='#mappa1'>settimanale</a>, <a href='#mappa2'>mensile</a> &middot; Analisi a fondo: <a href='#analisi0'>giornaliero</a>, <a href='#analisi1'>settimanale</a>, <a href='#analisi2'>mensile</a> &middot; <a href='#note'>Come leggere il report</a></div>");
         HtmlAutoSummary();
         for(int cl = 0; cl < NCLS; cl++) HtmlAutoMap(cl);
      }
      for(int cl = 0; cl < NCLS; cl++)
      {
         if(IsStopped()) break;
         if(g_win[cl] < 0)
         {
            PrintFormat("Orizzonte %s: nessuna combinazione con almeno %d trade IS.", g_clsName[cl], InpMinTrades);
            continue;
         }
         ComboDef(g_win[cl], g_cur);
         g_pre = Pick(cl == 0, "G", Pick(cl == 1, "S", "M"));
         Comment("MDRB Study: analisi a fondo, orizzonte " + g_clsName[cl] + "...");
         if(!AnalyzeCur()) continue;
         RunOffsetSweep();
         if(html)
         {
            HW("<h1 id='analisi" + IntegerToString(cl) + "' style='margin-top:46px;border-top:3px solid #1f6feb;padding-top:10px'>Analisi a fondo &mdash; orizzonte " + g_clsName[cl] + "</h1>");
            WriteClassBody();
         }
         if(InpWriteCSV) WriteCSV(g_clsTag[cl]);
         PrintSummary(g_clsName[cl]);
      }
      if(html) HtmlClose();
   }
   Comment("");
   PrintFormat("Completato in %.1f s", (GetTickCount() - t0) / 1000.0);
}
//+------------------------------------------------------------------+
