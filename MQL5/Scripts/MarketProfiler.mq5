//+------------------------------------------------------------------+
//|                                              MarketProfiler.mq5  |
//|  Analisi descrittiva di uno strumento, timeframe per timeframe.   |
//|  Output: report HTML a schede in MQL5\Files (o Common\Files).     |
//|                                                                  |
//|  Schede: Panoramica, Minuto, Ora, 4/6/8/12 ore, Giorno,           |
//|  Settimana, 2 settimane, Mese, Trimestre, Semestre, Anno,        |
//|  Sessioni, Swing, Rotture, Impulsi, Notizie, Gap, Volume,         |
//|  Rapporto. Orari chiave di New York, Londra, Francoforte e Tokyo  |
//|  convertiti giorno per giorno: vale per indici USA ed europei,    |
//|  forex e materie prime (imposta il fuso orario dei dati).         |
//|                                                                  |
//|  Ogni periodo (la candela del timeframe) e' scomposto in:         |
//|    apertura -> primo estremo        movimento iniziale            |
//|    primo -> secondo estremo         SPOSTAMENTO PIU' AMPIO        |
//|    secondo estremo -> chiusura      MEAN REVERSION (restituito)   |
//|  e per ogni tratto misura QUANTO (% e prezzo) e QUANDO avviene.   |
//|                                                                  |
//|  Usa in automatico tutto lo storico del simbolo, dalla prima       |
//|  all'ultima barra (anche simboli personalizzati, es. Dukascopy).  |
//|  Orari = ora delle barre (parametro 'Fuso orario dei dati').      |
//|  Sui CFD il volume e' tick volume (attivita', non controvalore).  |
//+------------------------------------------------------------------+
#property copyright   "vtrls"
#property version     "1.00"
#property description "Analisi descrittiva per timeframe: spostamento piu' ampio, mean reversion, quando avvengono."
#property script_show_inputs

enum ENUM_DATA_TZ
  {
   TZ_BROKER_NY7 = 0, // Broker New York+7: GMT+2/+3 con ora legale USA (FP Markets)
   TZ_UTC = 1,        // UTC
   TZ_EUROPE = 2,     // Europa centrale: CET/CEST
   TZ_FIXED = 3       // Fisso: GMT + ore indicate sotto
  };
enum ENUM_REF_MKT
  {
   REF_AUTO = 0,  // Automatica dalla valuta dello strumento
   REF_NY = 1,    // New York
   REF_LON = 2,   // Londra
   REF_FRA = 3,   // Francoforte
   REF_TKY = 4,   // Tokyo
   REF_NONE = 5   // Nessuna
  };

input string InpSymbols     = "";    // Simboli (vuoto = simbolo del grafico, altrimenti separati da virgola)
input int    InpMinuteYears = 3;     // Scheda Minuto: ultimi N anni di M1 (0 = tutto lo storico)
input bool   InpUseM1       = true;  // Usa M1 (scheda Minuto e 'quando' dentro l'ora)
input int    InpMaxBarsM1   = 0;     // Limite barre M1 (0 = tutto lo storico disponibile)
input int    InpMaxBarsH1   = 0;     // Limite barre H1 (0 = tutto lo storico disponibile)
input int    InpMaxBarsD1   = 0;     // Limite barre D1 (0 = tutto lo storico disponibile)
input bool   InpCommonDir   = false; // Salva in Common\Files invece di MQL5\Files
input double InpSwingATR     = 3.0;   // Swing: inversione minima in multipli di ATR(14)
input int    InpPivotBars    = 3;     // Rotture: barre a sinistra e a destra per un massimo/minimo
input int    InpFalseBars    = 3;     // Rotture: falsa se richiude dentro entro N barre
input int    InpLookBars     = 20;    // Rotture: barre osservate dopo la rottura
input double InpImpulsePct   = 99.5;  // Impulsi: percentile di soglia (99.5 = lo 0.5% piu' forte)
input bool   InpNews         = true;  // Notizie dal calendario economico di MT5
input string InpNewsCurrency = "";    // Valute delle notizie (vuoto = automatico dallo strumento, es. EUR,USD)
input int    InpNewsMinImp   = 2;     // Importanza minima notizie (3 = alta, 2 = media e alta)
input ENUM_DATA_TZ InpDataTZ = TZ_BROKER_NY7; // Fuso orario dei dati
input int    InpDataGMT      = 2;     // Solo per fuso 'Fisso': ore da GMT
input ENUM_REF_MKT InpRefMarket = REF_AUTO; // Piazza di riferimento per le etichette orarie
input int    InpSessionHours = 4;     // Sessioni: ore osservate dopo ogni orario chiave
input int    InpORMinutes    = 30;    // Sessioni: minuti del range iniziale
input bool   InpSkipIncomplete = true; // Escludi dalle analisi intraday i primi anni con copertura oraria incompleta

#define NTF     13
#define NX_ROWS 28
#define VP_BINS 60
#define C_BLUE  "#3b82f6"
#define C_RED   "#ef4444"
#define C_GREY  "#6b7280"
#define C_AMBER "#f59e0b"
#define C_GREEN "#34d399"

string TF_KEY[NTF]   = {"min", "h1", "h4", "h6", "h8", "h12", "d", "w", "w2", "mo", "q", "s", "y"};
string TF_LABEL[NTF] = {"Minuto", "Ora", "4 ore", "6 ore", "8 ore", "12 ore", "Giorno", "Settimana",
                        "2 settimane", "Mese", "Trimestre", "Semestre", "Anno"};
int    TF_K[NTF]     = {0, 0, 4, 6, 8, 12, 0, 0, 0, 0, 0, 0, 0};
// sorgente dati preferita per misurare il "quando" dentro il periodo: 0=M1 1=H1 2=D1 -1=nessuna
int    TF_SRC1[NTF]  = {0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2};
int    TF_SRC2[NTF]  = {-1, 1, 0, 0, 0, 0, 0, 2, -1, -1, -1, -1, -1};
string DOW[7]  = {"Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"};
string DOWS[7] = {"Dom", "Lun", "Mar", "Mer", "Gio", "Ven", "Sab"};  // settimana che parte la domenica
string MON[12] = {"Gen", "Feb", "Mar", "Apr", "Mag", "Giu", "Lug", "Ago", "Set", "Ott", "Nov", "Dic"};
string CLS_NAME[3] = {"Trend", "Parziale", "Mean reversion"};
string CLS_COL[3]  = {C_BLUE, C_GREY, C_RED};
string NX_LABEL[NX_ROWS] = {"Tutti i periodi",
                            "Trend rialzista", "Trend ribassista", "Parziale rialzista", "Parziale ribassista",
                            "Mean reversion rialzista", "Mean reversion ribassista",
                            "Q1 forte ribasso", "Q2", "Q3", "Q4", "Q5 forte rialzo",
                            "Q1 stretto", "Q2", "Q3", "Q4", "Q5 ampio",
                            "Q1 basso", "Q2", "Q3", "Q4", "Q5 alto",
                            "1 di fila", "2 di fila", "3 di fila", "4 di fila", "5 di fila", "6+ di fila"};

int    g_fh = INVALID_HANDLE;
bool   g_buf = false;   // se true W() scrive in g_bufS invece che nel file
string g_bufS = "";
int    g_digits = 5;
double g_last = 0;
string g_curRows = "";
string g_sumRows = "";
string g_warn = "";
string g_minNote = "";
string g_rep = "";      // rapporto testuale: sezioni per timeframe
string g_repCur = "";   // rapporto testuale: periodo in corso
string g_repHead = "";  // rapporto testuale: dati e stato attuale
string g_repVol = "";   // rapporto testuale: volume

struct NxAcc
  {
   int               n, same, up, bh, bl, ins, fb, br, mid;
   double            ret, rr;
  };

struct VPr
  {
   bool              ok;
   double            lo, w, poc, val, vah, vwap, mx;
   int               pocI, vaL, vaH;
   double            p[VP_BINS];
  };

//+------------------------------------------------------------------+
//| Serie OHLCV                                                       |
//+------------------------------------------------------------------+
class CSeries
  {
public:
   datetime          t[];
   double            o[], h[], l[], c[], v[];
   int               n;
   bool              hasVol, truncated;
                     CSeries(void) { n = 0; hasVol = false; truncated = false; }
   void              Free(void)
     {
      ArrayFree(t); ArrayFree(o); ArrayFree(h); ArrayFree(l); ArrayFree(c); ArrayFree(v);
      n = 0; hasVol = false; truncated = false;
     }
   // carica dalla prima all'ultima barra disponibile (o le ultime maxBars), a blocchi di chunkDays giorni
   bool              Load(const string sym, const ENUM_TIMEFRAMES tf, const int maxBars, const int chunkDays)
     {
      Free();
      int avail = 0;
      for(int k = 0; k < 50 && !IsStopped(); k++)
        {
         avail = Bars(sym, tf);
         if(avail > 0 && SeriesInfoInteger(sym, tf, SERIES_SYNCHRONIZED) != 0)
            break;
         Sleep(200);
        }
      if(avail < 3)
         return false;
      truncated = (long)avail >= TerminalInfoInteger(TERMINAL_MAXBARS);  // storico tagliato da 'Barre massime nel grafico'
      datetime first = (datetime)SeriesInfoInteger(sym, tf, SERIES_FIRSTDATE);
      datetime last = (datetime)SeriesInfoInteger(sym, tf, SERIES_LASTBAR_DATE);
      if(maxBars > 0 && maxBars < avail)
        {
         datetime tt[];
         if(CopyTime(sym, tf, maxBars - 1, 1, tt) == 1)
            first = tt[0];
        }
      if(first <= 0 || last < first)
         return false;
      int reserve = avail + 16;
      double vr[];
      int withReal = 0;
      long span = (long)chunkDays * 86400;
      MqlRates r[];
      for(long cs = (long)first; cs <= (long)last && !IsStopped(); cs += span)
        {
         int got = -1;
         for(int k = 0; k < 3 && got < 0; k++)
           {
            got = CopyRates(sym, tf, (datetime)cs, (datetime)(cs + span - 1), r);
            if(got < 0)
               Sleep(200);
           }
         if(got <= 0)
            continue;
         int base = n;
         n += got;
         ArrayResize(t, n, reserve); ArrayResize(o, n, reserve); ArrayResize(h, n, reserve); ArrayResize(l, n, reserve);
         ArrayResize(c, n, reserve); ArrayResize(v, n, reserve); ArrayResize(vr, n, reserve);
         for(int i = 0; i < got; i++)
           {
            int k = base + i;
            t[k] = r[i].time; o[k] = r[i].open; h[k] = r[i].high; l[k] = r[i].low; c[k] = r[i].close;
            v[k] = (double)r[i].tick_volume;
            vr[k] = (double)r[i].real_volume;
            if(r[i].real_volume > 0)
               withReal++;
           }
        }
      ArrayFree(r);
      if(n < 3)
         return false;
      // volume reale solo se c'e' su quasi tutte le barre, altrimenti tick volume
      if(withReal >= 0.95 * n)
         ArrayCopy(v, vr, 0, 0, n);
      for(int i = 0; i < n && !hasVol; i++)
         if(v[i] > 0)
            hasVol = true;
      return true;
     }
  };

//+------------------------------------------------------------------+
//| Periodi di un timeframe                                           |
//+------------------------------------------------------------------+
class CBlocks
  {
public:
   int               tf, src, N, curCnt;
   bool              ok, intra, hasVol;
   double            medCnt, curO, curH, curL, curC;
   datetime          curT0;
   datetime          t0[], tH[], tL[];
   double            O[], H[], L[], C[], V[], rng[], ret[], rf[], pH[], pL[], rv[];
   int               cnt[], offH[], offL[], cls[], cat[], bH[], bL[], yr[];
   bool              lf[];
                     CBlocks(void) { N = 0; ok = false; tf = 0; src = 0; }
   void              Size(const int n)
     {
      ArrayResize(t0, n); ArrayResize(tH, n); ArrayResize(tL, n);
      ArrayResize(O, n); ArrayResize(H, n); ArrayResize(L, n); ArrayResize(C, n); ArrayResize(V, n);
      ArrayResize(rng, n); ArrayResize(ret, n); ArrayResize(rf, n); ArrayResize(pH, n); ArrayResize(pL, n);
      ArrayResize(rv, n);
      ArrayResize(cnt, n); ArrayResize(offH, n); ArrayResize(offL, n); ArrayResize(cls, n); ArrayResize(cat, n);
      ArrayResize(bH, n); ArrayResize(bL, n); ArrayResize(yr, n); ArrayResize(lf, n);
     }
   void              Free(void) { Size(0); N = 0; ok = false; }
  };

//+------------------------------------------------------------------+
//| Utilita'                                                          |
//+------------------------------------------------------------------+
double Nan(void) { return MathArcsin(2.0); }
double Dv(const double a, const double b) { return b != 0 ? a / b : Nan(); }  // in MQL5 dividere per 0 blocca lo script
void   W(const string s) { if(g_buf) g_bufS += s; else FileWriteString(g_fh, s); }
string F(const double x, const int d) { if(!MathIsValidNumber(x)) return "&ndash;"; return DoubleToString(x, d); }
string FP(const double x, const int d) { return F(x * 100.0, d); }
string PX(const double x) { if(!MathIsValidNumber(x)) return "&ndash;"; return DoubleToString(x, g_digits); }
string I2S(const long x) { return IntegerToString(x); }
void   R(string &dst, const string s) { dst += s + "\n"; }
double ArcF(const double x) { return 2.0 / M_PI * MathArcsin(MathSqrt(MathMax(0.0, MathMin(1.0, x)))); }  // legge dell'arcoseno
string TD(const string s) { return "<td>" + s + "</td>"; }
string TDc(const string s, const string bg) { if(bg == "") return TD(s); return "<td style='background:" + bg + "'>" + s + "</td>"; }

string PCol(const double p, const double center, const double span)
  {
   if(!MathIsValidNumber(p) || span <= 0)
      return "";
   double v = p - center;
   double a = MathMin(MathAbs(v) / span, 1.0) * 0.55;
   if(a < 0.04)
      return "";
   return v > 0 ? "rgba(59,130,246," + DoubleToString(a, 2) + ")" : "rgba(239,68,68," + DoubleToString(a, 2) + ")";
  }

double Mean(const double &a[], const int n)
  {
   if(n <= 0)
      return Nan();
   double s = 0;
   for(int i = 0; i < n; i++)
      s += a[i];
   return s / n;
  }

void Sorted(const double &a[], const int n, double &out[])
  {
   ArrayResize(out, n);
   if(n > 0)
     {
      ArrayCopy(out, a, 0, 0, n);
      ArraySort(out);
     }
  }

// percentile con interpolazione lineare (s ordinato crescente)
double Pct(const double &s[], const int n, const double p)
  {
   if(n <= 0)
      return Nan();
   double pos = p / 100.0 * (n - 1);
   int i = (int)MathFloor(pos);
   if(i >= n - 1)
      return s[n - 1];
   return s[i] + (s[i + 1] - s[i]) * (pos - i);
  }

// quintile di ogni elemento (-1 se non valido o campione troppo piccolo)
void Quint(const double &a[], const bool &valid[], const int n, int &q[])
  {
   ArrayResize(q, n);
   double tmp[];
   ArrayResize(tmp, n);
   int m = 0;
   for(int i = 0; i < n; i++)
      if(valid[i])
         tmp[m++] = a[i];
   if(m < 25)
     {
      for(int i = 0; i < n; i++)
         q[i] = -1;
      return;
     }
   ArrayResize(tmp, m);
   ArraySort(tmp);
   double th[4];
   for(int k = 0; k < 4; k++)
      th[k] = Pct(tmp, m, 20.0 * (k + 1));
   for(int i = 0; i < n; i++)
     {
      if(!valid[i])
        {
         q[i] = -1;
         continue;
        }
      int k = 0;
      while(k < 4 && a[i] > th[k])
         k++;
      q[i] = k;
     }
  }

//+------------------------------------------------------------------+
//| Periodi: chiave, categorie, "quando"                              |
//+------------------------------------------------------------------+
long BlockKey(const int tfi, const datetime t)
  {
   long s = (long)t;
   long day = s / 86400;
   int hour = (int)((s % 86400) / 3600);
   if(tfi == 0)
      return s / 60;
   if(tfi == 1)
      return s / 3600;
   if(tfi >= 2 && tfi <= 5)
      return day * 100 + hour / TF_K[tfi];
   if(tfi == 6)
      return day;
   // settimana da domenica a sabato: con dati UTC la domenica sera apre la settimana nuova,
   // con l'orario del broker (EET) la domenica non ha barre
   long ws = day - (day + 4) % 7;  // 1970-01-01 era giovedi'
   if(tfi == 7)
      return ws;
   if(tfi == 8)
      return (ws - 3) / 14;        // 1970-01-04 era domenica
   MqlDateTime d;
   TimeToStruct(t, d);
   long m = (long)d.year * 12 + d.mon - 1;
   if(tfi == 9)
      return m;
   if(tfi == 10)
      return m / 3;
   if(tfi == 11)
      return m / 6;
   return m / 12;
  }

int CatCount(const int tfi)
  {
   if(tfi <= 1)
      return 24;
   if(tfi <= 5)
      return 24 / TF_K[tfi];
   if(tfi == 6)
      return 7;
   if(tfi <= 9)
      return 12;
   if(tfi == 10)
      return 4;
   if(tfi == 11)
      return 2;
   return 0;
  }

int CatIndex(const int tfi, const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   if(tfi <= 1)
      return d.hour;
   if(tfi <= 5)
      return d.hour / TF_K[tfi];
   if(tfi == 6)
      return (d.day_of_week + 6) % 7;
   if(tfi <= 9)
      return d.mon - 1;
   if(tfi == 10)
      return (d.mon - 1) / 3;
   if(tfi == 11)
      return (d.mon - 1) / 6;
   return 0;
  }

string CatLabel(const int tfi, const int i)
  {
   if(tfi <= 1)
      return StringFormat("%02dh", i);
   if(tfi <= 5)
      return StringFormat("%02d-%02dh", i * TF_K[tfi], (i + 1) * TF_K[tfi]);
   if(tfi == 6)
      return DOW[i];
   if(tfi <= 9)
      return MON[i];
   if(tfi == 10)
      return "Q" + I2S(i + 1);
   return I2S(i + 1) + "&deg; semestre";
  }

string CatName(const int tfi)
  {
   if(tfi <= 1)
      return "ora del giorno";
   if(tfi <= 5)
      return "blocco orario";
   if(tfi == 6)
      return "giorno della settimana";
   if(tfi <= 9)
      return "mese";
   if(tfi == 10)
      return "trimestre";
   return "semestre";
  }

int TimCount(const int tfi)
  {
   switch(tfi)
     {
      case 1:  return 12;
      case 2:  return 4;
      case 3:  return 6;
      case 4:  return 8;
      case 5:  return 12;
      case 6:  return 24;
      case 7:  return 7;
      case 8:  return 14;
      case 9:  return 31;
      case 10: return 14;
      case 11: return 6;
      case 12: return 12;
     }
   return 0;
  }

int TimIndex(const int tfi, const datetime te, const datetime t0, const int off)
  {
   MqlDateTime d;
   TimeToStruct(te, d);
   int n = TimCount(tfi);
   int r = 0;
   switch(tfi)
     {
      case 1:  r = d.min / 5; break;
      case 2:
      case 3:
      case 4:
      case 5:  r = d.hour % TF_K[tfi]; break;
      case 6:  r = d.hour; break;
      case 7:  r = d.day_of_week; break;
      case 8:
      case 9:  r = off; break;
      case 10: r = (int)(((long)te / 86400 - (long)t0 / 86400) / 7); break;
      case 11: r = (d.mon - 1) % 6; break;
      case 12: r = d.mon - 1; break;
     }
   if(r < 0)
      r = 0;
   if(r > n - 1)
      r = n - 1;
   return r;
  }

string TimLabel(const int tfi, const int i)
  {
   switch(tfi)
     {
      case 1:  return StringFormat(":%02d", i * 5);
      case 2:
      case 3:
      case 4:
      case 5:  return "+" + I2S(i) + "h";
      case 6:  return StringFormat("%02dh", i);
      case 7:  return DOWS[i];
      case 8:
      case 9:  return "G" + I2S(i + 1);
      case 10: return "S" + I2S(i + 1);
      case 11: return "M" + I2S(i + 1);
      case 12: return MON[i];
     }
   return "";
  }

string TimUnit(const int tfi)
  {
   if(tfi == 1)
      return "minuto dell'ora, fasce di 5 minuti";
   if(tfi <= 5)
      return "ora dentro il blocco";
   if(tfi == 6)
      return "ora del giorno";
   if(tfi == 7)
      return "giorno della settimana";
   if(tfi == 8)
      return "giorno di borsa del periodo";
   if(tfi == 9)
      return "giorno di borsa del mese";
   if(tfi == 10)
      return "settimana del trimestre";
   if(tfi == 11)
      return "mese del semestre";
   return "mese dell'anno";
  }

string PeriodLabel(const int tfi, const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   if(tfi <= 5)
      return TimeToString(t, TIME_DATE | TIME_MINUTES);
   if(tfi == 6)
      return TimeToString(t, TIME_DATE) + " " + DOW[(d.day_of_week + 6) % 7];
   if(tfi <= 8)
      return "sett. " + TimeToString(t, TIME_DATE);
   if(tfi == 9)
      return MON[d.mon - 1] + " " + I2S(d.year);
   if(tfi == 10)
      return "Q" + I2S((d.mon - 1) / 3 + 1) + " " + I2S(d.year);
   if(tfi == 11)
      return I2S((d.mon - 1) / 6 + 1) + "&deg; sem " + I2S(d.year);
   return I2S(d.year);
  }

//+------------------------------------------------------------------+
//| Scompone la serie nei periodi del timeframe e misura ogni periodo |
//+------------------------------------------------------------------+
bool Build(const int tfi, const int srcIdx, CSeries &s, CBlocks &b, const int i0)
  {
   b.Free();
   b.tf = tfi;
   b.src = srcIdx;
   b.hasVol = s.hasVol;
   int n = s.n;
   if(n - i0 < 50)
      return false;
   int st[];
   ArrayResize(st, n - i0);
   int nb = 0;
   long prev = 0;
   for(int i = i0; i < n; i++)
     {
      long k = BlockKey(tfi, s.t[i]);
      if(i == i0 || k != prev)
        {
         st[nb++] = i;
         prev = k;
        }
     }
   int cn[];
   ArrayResize(cn, nb);
   double tmp[];
   ArrayResize(tmp, nb);
   for(int j = 0; j < nb; j++)
     {
      cn[j] = (j < nb - 1 ? st[j + 1] : n) - st[j];
      tmp[j] = cn[j];
     }
   ArraySort(tmp);
   b.medCnt = Pct(tmp, nb, 50);
   b.intra = (b.medCnt > 1.0);
   b.Size(nb);
   int m = 0;
   for(int j = 0; j < nb; j++)
     {
      int a = st[j], e = st[j] + cn[j] - 1;
      double hh = s.h[a], ll = s.l[a], vv = 0;
      int ih = a, il = a;
      for(int i = a; i <= e; i++)
        {
         if(s.h[i] > hh) { hh = s.h[i]; ih = i; }
         if(s.l[i] < ll) { ll = s.l[i]; il = i; }
         vv += s.v[i];
        }
      if(j == nb - 1)  // periodo in corso
        {
         b.curT0 = s.t[a]; b.curO = s.o[a]; b.curH = hh; b.curL = ll; b.curC = s.c[e]; b.curCnt = cn[j];
         continue;
        }
      if(cn[j] < 0.5 * b.medCnt || (j == 0 && cn[j] < 0.9 * b.medCnt) || s.o[a] <= 0)
         continue;  // periodo monco (festivo, inizio dati) o prezzo non valido
      b.t0[m] = s.t[a]; b.O[m] = s.o[a]; b.H[m] = hh; b.L[m] = ll; b.C[m] = s.c[e]; b.V[m] = vv; b.cnt[m] = cn[j];
      b.tH[m] = s.t[ih]; b.tL[m] = s.t[il]; b.offH[m] = ih - a; b.offL[m] = il - a;
      // ordine degli estremi; se cadono nella stessa barra decide la direzione di quella barra
      b.lf[m] = (il < ih) ? true : ((il > ih) ? false : (s.c[ih] >= s.o[ih]));
      m++;
     }
   b.Size(m);
   b.N = m;
   for(int i = 0; i < m; i++)
     {
      double R = b.H[i] - b.L[i];
      double second = b.lf[i] ? b.H[i] : b.L[i];
      b.rng[i]  = R / b.O[i];
      b.ret[i]  = b.C[i] / b.O[i] - 1.0;
      b.rf[i]   = R > 0 ? MathAbs(b.C[i] - second) / R : 0.0;
      b.cls[i]  = b.rf[i] <= 0.25 ? 0 : (b.rf[i] >= 0.75 ? 2 : 1);
      MqlDateTime d;
      TimeToStruct(b.t0[i], d);
      b.yr[i]  = d.year;
      b.pH[i]  = (b.offH[i] + 1.0) / b.cnt[i];
      b.pL[i]  = (b.offL[i] + 1.0) / b.cnt[i];
      b.cat[i] = CatIndex(tfi, b.t0[i]);
      if(b.intra)
        {
         b.bH[i] = TimIndex(tfi, b.tH[i], b.t0[i], b.offH[i]);
         b.bL[i] = TimIndex(tfi, b.tL[i], b.t0[i], b.offL[i]);
        }
      else
        {
         b.bH[i] = -1;
         b.bL[i] = -1;
        }
     }
   // volume relativo: vs media degli ultimi 20 periodi della stessa fascia (es. stessa ora)
   double buf[24][20];
   int bn[24], bp[24];
   ArrayInitialize(bn, 0);
   ArrayInitialize(bp, 0);
   for(int i = 0; i < m; i++)
     {
      int c = CatCount(tfi) > 0 ? b.cat[i] : 0;
      b.rv[i] = -1;
      if(b.hasVol && bn[c] >= 5)
        {
         double sm = 0;
         for(int k = 0; k < bn[c]; k++)
            sm += buf[c][k];
         if(sm > 0)
            b.rv[i] = b.V[i] / (sm / bn[c]);
        }
      buf[c][bp[c]] = b.V[i];
      bp[c] = (bp[c] + 1) % 20;
      if(bn[c] < 20)
         bn[c]++;
     }
   b.ok = (m >= 3);
   return b.ok;
  }

//+------------------------------------------------------------------+
//| Cosa succede nel periodo successivo                               |
//+------------------------------------------------------------------+
void NextStats(CBlocks &b, NxAcc &acc[])
  {
   ArrayResize(acc, NX_ROWS);
   for(int k = 0; k < NX_ROWS; k++)
      ZeroMemory(acc[k]);
   int m = b.N;
   if(m < 3)
      return;
   int nc = m - 1;
   bool all[], vv[];
   ArrayResize(all, nc);
   ArrayResize(vv, nc);
   for(int i = 0; i < nc; i++)
     {
      all[i] = true;
      vv[i] = b.rv[i] > 0;
     }
   int qr[], qg[], qv[];
   Quint(b.ret, all, nc, qr);
   Quint(b.rng, all, nc, qg);
   Quint(b.rv, vv, nc, qv);
   double sr[];
   Sorted(b.rng, m, sr);
   double medR = Pct(sr, m, 50);
   int run = 0, prevSign = 0;
   int rows[6];
   for(int i = 0; i < nc; i++)
     {
      int s0 = b.ret[i] > 0 ? 1 : (b.ret[i] < 0 ? -1 : 0);
      int s1 = b.ret[i + 1] > 0 ? 1 : (b.ret[i + 1] < 0 ? -1 : 0);
      if(i > 0 && s0 == prevSign)
         run++;
      else
         run = 1;
      prevSign = s0;
      bool same = (s0 != 0 && s0 == s1);
      bool bh = b.H[i + 1] > b.H[i];
      bool bl = b.L[i + 1] < b.L[i];
      bool fb = (bh && b.C[i + 1] <= b.H[i]) || (bl && b.C[i + 1] >= b.L[i]);
      double mid = (b.H[i] + b.L[i]) / 2.0;
      bool tm = (b.L[i + 1] <= mid && b.H[i + 1] >= mid);
      double rr = medR > 0 ? b.rng[i + 1] / medR : 0;
      int nr = 0;
      rows[nr++] = 0;
      rows[nr++] = 1 + b.cls[i] * 2 + (b.ret[i] > 0 ? 0 : 1);
      if(qr[i] >= 0)
         rows[nr++] = 7 + qr[i];
      if(qg[i] >= 0)
         rows[nr++] = 12 + qg[i];
      if(qv[i] >= 0)
         rows[nr++] = 17 + qv[i];
      if(s0 != 0)
         rows[nr++] = 22 + (run < 6 ? run : 6) - 1;
      for(int k = 0; k < nr; k++)
        {
         int r = rows[k];
         acc[r].n++;
         if(same)
            acc[r].same++;
         if(b.ret[i + 1] > 0)
            acc[r].up++;
         acc[r].ret += b.ret[i + 1];
         acc[r].rr += rr;
         if(bh)
            acc[r].bh++;
         if(bl)
            acc[r].bl++;
         if(!bh && !bl)
            acc[r].ins++;
         if(bh || bl)
            acc[r].br++;
         if(fb)
            acc[r].fb++;
         if(tm)
            acc[r].mid++;
        }
     }
  }

//+------------------------------------------------------------------+
//| HTML: blocchi base                                                |
//+------------------------------------------------------------------+
void SecStart(const string title, const string desc)
  {
   W("<section><h2>" + title + "</h2>");
   if(desc != "")
      W("<p class='desc'>" + desc + "</p>");
  }
void SecEnd(void) { W("</section>"); }

void THead(const string heads)
  {
   string p[];
   int k = StringSplit(heads, '|', p);
   W("<div class='tw'><table><thead><tr>");
   for(int i = 0; i < k; i++)
      W("<th>" + p[i] + "</th>");
   W("</tr></thead><tbody>");
  }
void TEnd(void) { W("</tbody></table></div>"); }
void Grp(const string s, const int cols) { W("<tr class='grp'><td colspan='" + I2S(cols) + "'>" + s + "</td></tr>"); }

void Kpi(const string a, const string b, const string c)
  {
   W("<div><span>" + a + "</span><b>" + b + "</b>" + (c != "" ? "<small>" + c + "</small>" : "") + "</div>");
  }

string Stack(const double t, const double p, const double r)
  {
   return "<div class='st'><i style='width:" + DoubleToString(t * 100, 1) + "%;background:" + C_BLUE + "'></i><i style='width:" +
          DoubleToString(p * 100, 1) + "%;background:" + C_GREY + "'></i><i style='width:" + DoubleToString(r * 100, 1) +
          "%;background:" + C_RED + "'></i></div>";
  }

string HBar(const double v, const double vmax, const string txt)
  {
   double w = vmax > 0 ? v / vmax * 100.0 : 0;
   return "<div class='hb'><i style='width:" + DoubleToString(w, 1) + "%'></i><span>" + txt + "</span></div>";
  }

// istogramma / barre verticali a una serie
void VBars(const string title, string &lab[], double &val[], string &col[], const int n, const string foot, const bool showLab)
  {
   double mx = 0;
   for(int i = 0; i < n; i++)
      if(val[i] > mx)
         mx = val[i];
   if(mx <= 0)
      mx = 1;
   W("<div class='ch'><div class='ct'>" + title + "</div><div class='vb'>");
   for(int i = 0; i < n; i++)
      W("<div class='c'><div class='bs'><i style='height:" + DoubleToString(val[i] / mx * 100, 1) + "%;background:" + col[i] +
        "' title='" + lab[i] + ": " + DoubleToString(val[i], 1) + "%'></i></div><span>" + (showLab ? lab[i] : "") + "</span></div>");
   W("</div>" + (foot != "" ? "<div class='cf'>" + foot + "</div>" : "") + "</div>");
  }

// barre verticali a due serie affiancate
void VBars2(const string title, string &lab[], double &a[], double &c2[], const int from, const int n,
            const string colA, const string colB, const string nameA, const string nameB)
  {
   double mx = 0;
   for(int i = from; i < n; i++)
     {
      if(a[i] > mx)
         mx = a[i];
      if(c2[i] > mx)
         mx = c2[i];
     }
   if(mx <= 0)
      mx = 1;
   W("<div class='ch'><div class='ct'>" + title + "</div><div class='vb'>");
   for(int i = from; i < n; i++)
      W("<div class='c'><div class='bs'><i style='height:" + DoubleToString(a[i] / mx * 100, 1) + "%;background:" + colA +
        "' title='" + lab[i] + " &middot; " + nameA + ": " + DoubleToString(a[i], 1) + "%'></i><i style='height:" +
        DoubleToString(c2[i] / mx * 100, 1) + "%;background:" + colB + "' title='" + lab[i] + " &middot; " + nameB + ": " +
        DoubleToString(c2[i], 1) + "%'></i></div><span>" + lab[i] + "</span></div>");
   W("</div><div class='lg'><b style='background:" + colA + "'></b>" + nameA + " <b style='background:" + colB + "'></b>" +
     nameB + "</div></div>");
  }

// istogramma: mode 0 blu, 1 blu/rosso per segno, 2 colori classe (0-100)
void Hist(const string title, const double &x[], const int n, const double lo, const double hi, const int bins, const int mode)
  {
   double cv[];
   string lab[], col[];
   ArrayResize(cv, bins);
   ArrayResize(lab, bins);
   ArrayResize(col, bins);
   ArrayInitialize(cv, 0.0);
   double w = (hi - lo) / bins;
   if(w <= 0)
      w = 1e-12;
   for(int i = 0; i < n; i++)
     {
      int k = (int)MathFloor((x[i] - lo) / w);
      if(k < 0)
         k = 0;
      if(k >= bins)
         k = bins - 1;
      cv[k] += 1;
     }
   for(int k = 0; k < bins; k++)
     {
      cv[k] = n > 0 ? cv[k] / n * 100.0 : 0;
      double ctr = lo + (k + 0.5) * w;
      lab[k] = DoubleToString(ctr, 3);
      if(mode == 0)
         col[k] = C_BLUE;
      else
         if(mode == 1)
            col[k] = ctr >= 0 ? C_BLUE : C_RED;
         else
            col[k] = ctr <= 25 ? C_BLUE : (ctr >= 75 ? C_RED : C_GREY);
     }
   VBars(title, lab, cv, col, bins, DoubleToString(lo, 3) + " &hellip; " + DoubleToString(hi, 3) + " &middot; altezza = % dei periodi", false);
  }

//+------------------------------------------------------------------+
//| Scheda di un timeframe                                            |
//+------------------------------------------------------------------+
void PctRow(const string name, const double &x[], const int n, const bool hasPx)
  {
   if(n <= 0)
      return;
   double s[];
   Sorted(x, n, s);
   W("<tr>" + TD(name) + TD(I2S(n)) + TD(FP(Mean(x, n), 3)) + TD(FP(Pct(s, n, 10), 3)) + TD(FP(Pct(s, n, 25), 3)) +
     TD(FP(Pct(s, n, 50), 3)) + TD(FP(Pct(s, n, 75), 3)) + TD(FP(Pct(s, n, 90), 3)) + TD(FP(Pct(s, n, 95), 3)) +
     TD(FP(s[n - 1], 3)) + TD(hasPx ? PX(Pct(s, n, 50) * g_last) : "&ndash;") + TD(hasPx ? PX(Pct(s, n, 90) * g_last) : "&ndash;") + "</tr>");
   R(g_rep, "- " + name + ": media " + FP(Mean(x, n), 3) + "%, P10 " + FP(Pct(s, n, 10), 3) + "%, P25 " + FP(Pct(s, n, 25), 3) +
     "%, mediana " + FP(Pct(s, n, 50), 3) + "%, P75 " + FP(Pct(s, n, 75), 3) + "%, P90 " + FP(Pct(s, n, 90), 3) + "%, P95 " +
     FP(Pct(s, n, 95), 3) + "%, max " + FP(s[n - 1], 3) + "%" +
     (hasPx ? " (in prezzo: mediana " + PX(Pct(s, n, 50) * g_last) + ", P90 " + PX(Pct(s, n, 90) * g_last) + ")" : ""));
  }

string ModeLabel(const int tfi, const int &cnts[], const int tc, const int tot)
  {
   if(tot <= 0 || tc <= 0)
      return "&ndash;";
   int bi = 0;
   for(int k = 1; k < tc; k++)
      if(cnts[k] > cnts[bi])
         bi = k;
   return TimLabel(tfi, bi) + " (" + DoubleToString(100.0 * cnts[bi] / tot, 0) + "%)";
  }

string ModeOf(CBlocks &b, const bool useH)
  {
   int tc = TimCount(b.tf);
   int cn[];
   ArrayResize(cn, tc);
   ArrayInitialize(cn, 0);
   for(int i = 0; i < b.N; i++)
      cn[useH ? b.bH[i] : b.bL[i]]++;
   return ModeLabel(b.tf, cn, tc, b.N);
  }

// tabella per gruppi (fascia oraria, giorno, mese, anno...)
void GroupTable(CBlocks &b, const int &g[], const int ng, string &glab[], const string gname)
  {
   int m = b.N, tc = b.intra ? TimCount(b.tf) : 0;
   int gn[], gu[], gc[], rvn[], hc[], lc[];
   double sR[], sRet[], sRf[], sRv[];
   ArrayResize(gn, ng); ArrayResize(gu, ng); ArrayResize(gc, ng * 3); ArrayResize(rvn, ng);
   ArrayResize(sR, ng); ArrayResize(sRet, ng); ArrayResize(sRf, ng); ArrayResize(sRv, ng);
   ArrayResize(hc, MathMax(ng * tc, 1)); ArrayResize(lc, MathMax(ng * tc, 1));
   ArrayInitialize(gn, 0); ArrayInitialize(gu, 0); ArrayInitialize(gc, 0); ArrayInitialize(rvn, 0);
   ArrayInitialize(sR, 0.0); ArrayInitialize(sRet, 0.0); ArrayInitialize(sRf, 0.0); ArrayInitialize(sRv, 0.0);
   ArrayInitialize(hc, 0); ArrayInitialize(lc, 0);
   for(int i = 0; i < m; i++)
     {
      int k = g[i];
      if(k < 0 || k >= ng)
         continue;
      gn[k]++;
      sR[k] += b.rng[i];
      sRet[k] += b.ret[i];
      sRf[k] += b.rf[i];
      if(b.ret[i] > 0)
         gu[k]++;
      gc[k * 3 + b.cls[i]]++;
      if(b.rv[i] > 0)
        {
         sRv[k] += b.rv[i];
         rvn[k]++;
        }
      if(tc > 0)
        {
         hc[k * tc + b.bH[i]]++;
         lc[k * tc + b.bL[i]]++;
        }
     }
   double mx = 0;
   for(int k = 0; k < ng; k++)
      if(gn[k] > 0 && sR[k] / gn[k] > mx)
         mx = sR[k] / gn[k];
   string hd = gname + "|N|Spostamento medio %|Spost. mediano %|&asymp; prezzo|% rialzisti|Rend. medio %|Trend &middot; Parziale &middot; Mean rev.|% Trend|% Mean rev.|Restituito medio %|Volume rel.";
   if(tc > 0)
      hd += "|Massimo pi&ugrave; spesso|Minimo pi&ugrave; spesso";
   THead(hd);
   R(g_rep, "Per " + gname + ":");
   double tmp[];
   ArrayResize(tmp, m);
   int hsub[], lsub[];
   ArrayResize(hsub, MathMax(tc, 1));
   ArrayResize(lsub, MathMax(tc, 1));
   for(int k = 0; k < ng; k++)
     {
      if(gn[k] == 0)
         continue;
      int q = 0;
      for(int i = 0; i < m; i++)
         if(g[i] == k)
            tmp[q++] = b.rng[i];
      double s[];
      Sorted(tmp, q, s);
      double med = Pct(s, q, 50);
      double up = (double)gu[k] / gn[k];
      string row = "<tr>" + TD(glab[k]) + TD(I2S(gn[k])) + TD(HBar(sR[k] / gn[k], mx, FP(sR[k] / gn[k], 3))) + TD(FP(med, 3)) +
                   TD(PX(med * g_last)) + TDc(FP(up, 1), PCol(up, 0.5, 0.15)) + TD(FP(sRet[k] / gn[k], 3)) +
                   TD(Stack((double)gc[k * 3] / gn[k], (double)gc[k * 3 + 1] / gn[k], (double)gc[k * 3 + 2] / gn[k])) +
                   TD(FP((double)gc[k * 3] / gn[k], 1)) + TD(FP((double)gc[k * 3 + 2] / gn[k], 1)) + TD(F(sRf[k] / gn[k] * 100, 0)) +
                   TD(rvn[k] > 0 ? F(sRv[k] / rvn[k], 2) : "&ndash;");
      if(tc > 0)
        {
         for(int z = 0; z < tc; z++)
           {
            hsub[z] = hc[k * tc + z];
            lsub[z] = lc[k * tc + z];
           }
         row += TD(ModeLabel(b.tf, hsub, tc, gn[k])) + TD(ModeLabel(b.tf, lsub, tc, gn[k]));
        }
      W(row + "</tr>");
      R(g_rep, "  " + glab[k] + ": N " + I2S(gn[k]) + ", spostamento medio " + FP(sR[k] / gn[k], 3) + "%, mediano " + FP(med, 3) +
        "%, rialzisti " + FP(up, 1) + "%, rend. medio " + FP(sRet[k] / gn[k], 3) + "%, Trend " + FP((double)gc[k * 3] / gn[k], 1) +
        "%, Mean rev. " + FP((double)gc[k * 3 + 2] / gn[k], 1) + "%, restituito medio " + F(sRf[k] / gn[k] * 100, 0) + "%" +
        (rvn[k] > 0 ? ", volume rel. " + F(sRv[k] / rvn[k], 2) : "") +
        (tc > 0 ? ", massimo pi&ugrave; spesso " + ModeLabel(b.tf, hsub, tc, gn[k]) + ", minimo pi&ugrave; spesso " +
         ModeLabel(b.tf, lsub, tc, gn[k]) : ""));
     }
   TEnd();
  }

void NextTable(NxAcc &acc[])
  {
   THead("Condizione|N|% stessa direzione|% rialzista|Rend. medio %|Ampiezza vs mediano|% rompe massimo prec.|% rompe minimo prec.|% inside|% false rotture|% torna a met&agrave; prec.");
   string grp[NX_ROWS];
   for(int k = 0; k < NX_ROWS; k++)
      grp[k] = "";
   grp[1] = "Tipo del periodo appena chiuso";
   grp[7] = "Rendimento del periodo appena chiuso";
   grp[12] = "Ampiezza del periodo appena chiuso";
   grp[17] = "Volume del periodo appena chiuso (vs ultimi 20 della stessa fascia)";
   grp[22] = "Sequenza: periodi consecutivi nella stessa direzione";
   int gs[5] = {1, 7, 12, 17, 22};
   int ge[5] = {6, 11, 16, 21, 27};
   R(g_rep, "Cosa fa il periodo successivo:");
   for(int k = 0; k < NX_ROWS; k++)
     {
      if(grp[k] != "")
        {
         bool has = false;
         for(int z = 0; z < 5; z++)
            if(gs[z] == k)
               for(int r = gs[z]; r <= ge[z]; r++)
                  if(acc[r].n >= 5)
                     has = true;
         if(has)
           {
            Grp(grp[k], 11);
            R(g_rep, "  [" + grp[k] + "]");
           }
        }
      NxAcc a = acc[k];
      if(a.n < 5)
         continue;
      double same = (double)a.same / a.n, up = (double)a.up / a.n, rr = a.rr / a.n;
      W("<tr>" + TD(NX_LABEL[k]) + TD(I2S(a.n)) + TDc(FP(same, 1), PCol(same, 0.5, 0.15)) + TDc(FP(up, 1), PCol(up, 0.5, 0.15)) +
        TD(FP(a.ret / a.n, 3)) + TDc(F(rr, 2), PCol(rr, 1.0, 0.5)) + TD(FP((double)a.bh / a.n, 1)) + TD(FP((double)a.bl / a.n, 1)) +
        TD(FP((double)a.ins / a.n, 1)) + TD(a.br > 0 ? FP((double)a.fb / a.br, 1) : "&ndash;") + TD(FP((double)a.mid / a.n, 1)) + "</tr>");
      R(g_rep, "  " + NX_LABEL[k] + " (N " + I2S(a.n) + "): stessa direzione " + FP(same, 1) + "%, rialzista " + FP(up, 1) +
        "%, rend. medio " + FP(a.ret / a.n, 3) + "%, ampiezza " + F(rr, 2) + "x il mediano, rompe il massimo prec. " +
        FP((double)a.bh / a.n, 1) + "%, rompe il minimo prec. " + FP((double)a.bl / a.n, 1) + "%, inside " + FP((double)a.ins / a.n, 1) +
        "%, false rotture " + (a.br > 0 ? FP((double)a.fb / a.br, 1) : "-") + "%, torna a met&agrave; prec. " + FP((double)a.mid / a.n, 1) + "%");
     }
   TEnd();
  }

void PeriodList(CBlocks &b, const int &idx[], const int k, const double medR)
  {
   THead("Periodo|Apertura|Massimo|Minimo|Chiusura|Spostamento %|Rendimento %|Spostamento|Tipo|Restituito %|Quando il massimo|Quando il minimo|Volume rel.");
   int fmtT = b.src == 2 ? TIME_DATE : (TIME_DATE | TIME_MINUTES);
   for(int j = 0; j < k; j++)
     {
      int i = idx[j];
      W("<tr>" + TD(PeriodLabel(b.tf, b.t0[i])) + TD(PX(b.O[i])) + TD(PX(b.H[i])) + TD(PX(b.L[i])) + TD(PX(b.C[i])) +
        TD(FP(b.rng[i], 3)) + TDc(FP(b.ret[i], 3), PCol(b.ret[i], 0, medR)) + TD(b.lf[i] ? "rialzista" : "ribassista") +
        TD(CLS_NAME[b.cls[i]]) + TD(F(b.rf[i] * 100, 0)) + TD(b.intra ? TimeToString(b.tH[i], fmtT) : "&ndash;") +
        TD(b.intra ? TimeToString(b.tL[i], fmtT) : "&ndash;") + TD(b.rv[i] > 0 ? F(b.rv[i], 2) : "&ndash;") + "</tr>");
     }
   TEnd();
  }

void TfPage(CBlocks &b)
  {
   int tfi = b.tf, m = b.N;
   string src = b.src == 0 ? "M1" : (b.src == 1 ? "H1" : "D1");
   double sr[];
   Sorted(b.rng, m, sr);
   double medR = Pct(sr, m, 50), p90 = Pct(sr, m, 90);
   int ib = 0, nUp = 0;
   int nc[3] = {0, 0, 0};
   double sRet = 0;
   for(int i = 0; i < m; i++)
     {
      if(b.rng[i] > b.rng[ib])
         ib = i;
      if(b.ret[i] > 0)
         nUp++;
      nc[b.cls[i]]++;
      sRet += b.ret[i];
     }
   NxAcc acc[];
   NextStats(b, acc);
   double sameAll = acc[0].n > 0 ? (double)acc[0].same / acc[0].n : Nan();
   double retr[];  // mean reversion: dal secondo estremo alla chiusura, in % dell'apertura
   ArrayResize(retr, m);
   for(int i = 0; i < m; i++)
      retr[i] = MathAbs(b.C[i] - (b.lf[i] ? b.H[i] : b.L[i])) / b.O[i];
   double meanRetr = Mean(retr, m);

   //--- sintesi
   string note = b.intra ? "Misurato su barre " + src + ": il 'quando' dentro il periodo ha la risoluzione di una barra " + src + "."
                 : "Ogni periodo &egrave; una singola barra " + src + ": si misurano ampiezza e direzione; l'ordine massimo/minimo " +
                 "&egrave; dedotto dalla candela (chiusura sopra l'apertura = prima il minimo).";
   if(tfi == 0)
      note += g_minNote;
   SecStart(TF_LABEL[tfi] + ": sintesi", note);
   W("<div class='kpi'>");
   Kpi("Periodi analizzati", I2S(m), TimeToString(b.t0[0], TIME_DATE) + " &rarr; " + TimeToString(b.t0[m - 1], TIME_DATE));
   Kpi("Spostamento pi&ugrave; ampio mediano", FP(medR, 3) + "%", "&asymp; " + PX(medR * g_last) + " in prezzo");
   Kpi("Spostamento medio", FP(Mean(b.rng, m), 3) + "%", "&asymp; " + PX(Mean(b.rng, m) * g_last));
   Kpi("1 periodo su 10 supera", FP(p90, 3) + "%", "&asymp; " + PX(p90 * g_last));
   Kpi("Spostamento massimo storico", FP(b.rng[ib], 2) + "%", PeriodLabel(tfi, b.t0[ib]));
   Kpi("Periodi rialzisti", FP((double)nUp / m, 1) + "%", "rendimento medio " + FP(sRet / m, 3) + "%");
   Kpi("Trend (restituisce &le; 25%)", FP((double)nc[0] / m, 1) + "%", "chiude vicino all'estremo");
   Kpi("Mean reversion (restituisce &ge; 75%)", FP((double)nc[2] / m, 1) + "%", "torna indietro quasi tutto");
   Kpi("Parziale", FP((double)nc[1] / m, 1) + "%", "restituisce tra 25% e 75%");
   Kpi("Mean reversion media", FP(meanRetr, 3) + "%", F(Mean(b.rf, m) * 100, 0) + "% dello spostamento");
   Kpi("Periodo dopo nella stessa direzione", FP(sameAll, 1) + "%", "");
   if(b.intra)
     {
      Kpi("Massimo pi&ugrave; spesso in", ModeOf(b, true), TimUnit(tfi));
      Kpi("Minimo pi&ugrave; spesso in", ModeOf(b, false), TimUnit(tfi));
     }
   W("</div>");
   SecEnd();
   R(g_rep, "");
   R(g_rep, "=== " + TF_LABEL[tfi] + " ===");
   R(g_rep, I2S(m) + " periodi completi dal " + TimeToString(b.t0[0], TIME_DATE) + " al " + TimeToString(b.t0[m - 1], TIME_DATE) +
     ", misurati su barre " + src + (b.intra ? "." : " (ogni periodo &egrave; una sola barra: ordine massimo/minimo dedotto dalla candela).") +
     (tfi == 0 ? g_minNote : ""));
   R(g_rep, "Spostamento pi&ugrave; ampio (massimo - minimo): mediana " + FP(medR, 3) + "% (circa " + PX(medR * g_last) +
     " in prezzo), media " + FP(Mean(b.rng, m), 3) + "%, 1 periodo su 10 supera " + FP(p90, 3) + "%, massimo storico " +
     FP(b.rng[ib], 2) + "% (" + PeriodLabel(tfi, b.t0[ib]) + ").");
   R(g_rep, "Direzione: " + FP((double)nUp / m, 1) + "% dei periodi chiude sopra l'apertura, rendimento medio " + FP(sRet / m, 3) + "%.");
   R(g_rep, "Tipo: Trend (restituisce al massimo il 25% dello spostamento) " + FP((double)nc[0] / m, 1) + "%, Parziale " +
     FP((double)nc[1] / m, 1) + "%, Mean reversion (restituisce almeno il 75%) " + FP((double)nc[2] / m, 1) +
     "%. In media viene restituito il " + F(Mean(b.rf, m) * 100, 0) + "% dello spostamento (mean reversion media " + FP(meanRetr, 3) + "%).");
   R(g_rep, "Il periodo successivo va nella stessa direzione nel " + FP(sameAll, 1) + "% dei casi.");
   R(g_rep, "Distribuzioni (in % del prezzo di apertura del periodo):");

   //--- quanto
   SecStart("Spostamento pi&ugrave; ampio e mean reversion: quanto",
            "Ogni riga &egrave; una misura calcolata su tutti i periodi, in % del prezzo di apertura del periodo. " +
            "P90 = superato solo nel 10% dei periodi. Le ultime due colonne traducono mediana e P90 in prezzo al livello attuale.");
   THead("Misura|N|Media %|P10 %|P25 %|Mediana %|P75 %|P90 %|P95 %|Max %|Mediana &asymp; prezzo|P90 &asymp; prezzo");
   double up[], dn[], ab[];
   ArrayResize(up, m);
   ArrayResize(dn, m);
   ArrayResize(ab, m);
   int nu = 0, nd = 0;
   for(int i = 0; i < m; i++)
     {
      if(b.lf[i])
         up[nu++] = b.rng[i];
      else
         dn[nd++] = b.rng[i];
      ab[i] = MathAbs(b.ret[i]);
     }
   PctRow("Spostamento pi&ugrave; ampio (massimo &minus; minimo)", b.rng, m, true);
   PctRow("&nbsp;&nbsp;&hellip; dal minimo al massimo (rialzista)", up, nu, true);
   PctRow("&nbsp;&nbsp;&hellip; dal massimo al minimo (ribassista)", dn, nd, true);
   double tx[];
   ArrayResize(tx, m);
   for(int i = 0; i < m; i++)
      tx[i] = b.H[i] / b.O[i] - 1.0;
   PctRow("Escursione sopra l'apertura", tx, m, true);
   for(int i = 0; i < m; i++)
      tx[i] = 1.0 - b.L[i] / b.O[i];
   PctRow("Escursione sotto l'apertura", tx, m, true);
   for(int i = 0; i < m; i++)
      tx[i] = MathAbs((b.lf[i] ? b.L[i] : b.H[i]) - b.O[i]) / b.O[i];
   PctRow("Movimento iniziale (apertura &rarr; primo estremo)", tx, m, true);
   PctRow("Mean reversion (secondo estremo &rarr; chiusura)", retr, m, true);
   PctRow("Mean reversion in % dello spostamento", b.rf, m, false);
   PctRow("Rendimento apertura &rarr; chiusura", b.ret, m, true);
   PctRow("|Rendimento| apertura &rarr; chiusura", ab, m, true);
   TEnd();
   double x[], s2[];
   ArrayResize(x, m);
   W("<div class='g3'>");
   for(int i = 0; i < m; i++)
      x[i] = b.rng[i] * 100;
   Sorted(x, m, s2);
   Hist("Spostamento pi&ugrave; ampio %", x, m, 0, Pct(s2, m, 99.5), 40, 0);
   for(int i = 0; i < m; i++)
      x[i] = b.ret[i] * 100;
   Sorted(x, m, s2);
   Hist("Rendimento apertura &rarr; chiusura %", x, m, Pct(s2, m, 0.5), Pct(s2, m, 99.5), 40, 1);
   for(int i = 0; i < m; i++)
      x[i] = b.rf[i] * 100;
   Hist("Mean reversion: % dello spostamento restituita", x, m, 0, 100, 20, 2);
   W("</div>");
   SecEnd();

   //--- quando
   if(b.intra)
     {
      int tc = TimCount(tfi);
      double h[], l[], ru[], rd[];
      string lab[];
      ArrayResize(h, tc); ArrayResize(l, tc); ArrayResize(ru, tc); ArrayResize(rd, tc); ArrayResize(lab, tc);
      ArrayInitialize(h, 0.0); ArrayInitialize(l, 0.0); ArrayInitialize(ru, 0.0); ArrayInitialize(rd, 0.0);
      int cu = 0, cd = 0;
      for(int i = 0; i < m; i++)
        {
         h[b.bH[i]] += 1;
         l[b.bL[i]] += 1;
         if(b.lf[i])
           {
            ru[b.bH[i]] += 1;
            cu++;
           }
         else
           {
            rd[b.bL[i]] += 1;
            cd++;
           }
        }
      int ts = -1, te = 1;  // taglia le fasce vuote in testa e in coda (es. domenica, giorni 24-31)
      for(int k = 0; k < tc; k++)
        {
         if(h[k] > 0 || l[k] > 0)
           {
            te = k + 1;
            if(ts < 0)
               ts = k;
           }
         h[k] = h[k] / m * 100;
         l[k] = l[k] / m * 100;
         ru[k] = cu > 0 ? ru[k] / cu * 100 : 0;
         rd[k] = cd > 0 ? rd[k] / cd * 100 : 0;
         lab[k] = TimLabel(tfi, k);
        }
      SecStart("Quando avvengono", "Sinistra: in quale " + TimUnit(tfi) + " si forma il massimo e il minimo del periodo (% dei periodi). " +
               "Destra: dove finisce lo spostamento pi&ugrave; ampio, cio&egrave; il punto da cui parte il rientro (mean reversion).");
      W("<div class='g2'>");
      if(ts < 0)
         ts = 0;
      VBars2("Quando si forma il massimo e il minimo", lab, h, l, ts, te, C_BLUE, C_AMBER, "Massimo del periodo", "Minimo del periodo");
      VBars2("Dove parte il rientro", lab, ru, rd, ts, te, "#93c5fd", "#fcd34d", "Swing rialzista: rientro dal massimo",
             "Swing ribassista: rientro dal minimo");
      W("</div>");
      SecEnd();
      string sh = "", sl = "", su = "", sd = "";
      for(int k = ts; k < te; k++)
        {
         sh += lab[k] + " " + F(h[k], 1) + "%; ";
         sl += lab[k] + " " + F(l[k], 1) + "%; ";
         su += lab[k] + " " + F(ru[k], 1) + "%; ";
         sd += lab[k] + " " + F(rd[k], 1) + "%; ";
        }
      R(g_rep, "Quando si forma il massimo (" + TimUnit(tfi) + ", % dei periodi): " + sh);
      R(g_rep, "Quando si forma il minimo: " + sl);
      R(g_rep, "Dove parte il rientro dopo uno swing rialzista (al massimo): " + su);
      R(g_rep, "Dove parte il rientro dopo uno swing ribassista (al minimo): " + sd);

      //--- posizione degli estremi nel periodo contro quella di un prezzo casuale (legge dell'arcoseno)
      int nq = b.medCnt >= 10 ? 10 : (int)MathRound(b.medCnt);
      if(nq >= 2)
        {
         double oh[], ol[], ex[];
         ArrayResize(oh, nq); ArrayResize(ol, nq); ArrayResize(ex, nq);
         ArrayInitialize(oh, 0.0); ArrayInitialize(ol, 0.0); ArrayInitialize(ex, 0.0);
         for(int i = 0; i < m; i++)
           {
            int cc = b.cnt[i];
            int kh = (int)MathFloor((double)b.offH[i] / cc * nq), kl = (int)MathFloor((double)b.offL[i] / cc * nq);
            oh[kh < nq ? kh : nq - 1] += 1;
            ol[kl < nq ? kl : nq - 1] += 1;
            for(int j = 0; j < cc; j++)  // atteso: probabilita' di ogni barra per un prezzo casuale, sommata nella sua fascia
              {
               int kk = (int)MathFloor((double)j / cc * nq);
               ex[kk < nq ? kk : nq - 1] += ArcF((j + 1.0) / cc) - ArcF((double)j / cc);
              }
           }
         SecStart("Quando: confronto con un prezzo casuale",
                  "Anche un prezzo che si muove del tutto a caso fa pi&ugrave; spesso massimo e minimo all'inizio o alla fine del " +
                  "periodo (legge dell'arcoseno). Per questo &egrave; normale che le fasce estreme risultino le 'pi&ugrave; frequenti'. " +
                  "Qui il periodo &egrave; diviso in " + I2S(nq) + " parti di tempo: il rapporto osservato/atteso dice dove lo strumento " +
                  "si comporta davvero in modo diverso dal caso (sopra 1.20 pi&ugrave; spesso del caso, sotto 0.80 meno spesso).");
         THead("Parte del periodo trascorsa|% massimi|% minimi|Atteso se casuale|Massimi / atteso|Minimi / atteso");
         string sx = "";
         for(int k = 0; k < nq; k++)
           {
            oh[k] = oh[k] / m * 100;
            ol[k] = ol[k] / m * 100;
            ex[k] = ex[k] / m * 100;
            double rh = Dv(oh[k], ex[k]), rl = Dv(ol[k], ex[k]);
            string ql = F(100.0 * k / nq, 0) + "-" + F(100.0 * (k + 1) / nq, 0) + "%";
            W("<tr>" + TD(ql) + TD(F(oh[k], 1)) + TD(F(ol[k], 1)) + TD(F(ex[k], 1)) + TDc(F(rh, 2), PCol(rh, 1.0, 0.5)) +
              TDc(F(rl, 2), PCol(rl, 1.0, 0.5)) + "</tr>");
            sx += ql + ": massimi " + F(oh[k], 1) + "%, minimi " + F(ol[k], 1) + "%, atteso " + F(ex[k], 1) + "% (x" + F(rh, 2) +
                  " / x" + F(rl, 2) + "); ";
           }
         TEnd();
         SecEnd();
         R(g_rep, "Posizione di massimo e minimo nel tempo del periodo contro un prezzo casuale: " + sx);
        }
     }

   //--- per categoria
   int ncat = CatCount(tfi);
   if(ncat > 0)
     {
      string glab[];
      ArrayResize(glab, ncat);
      for(int k = 0; k < ncat; k++)
         glab[k] = CatLabel(tfi, k);
      SecStart("Quando: per " + CatName(tfi), "Come cambiano ampiezza, direzione e tipo di periodo in base a " + CatName(tfi) +
               ". Barra tricolore: blu Trend, grigio Parziale, rosso Mean reversion.");
      GroupTable(b, b.cat, ncat, glab, CatName(tfi));
      SecEnd();
     }

   //--- per anno
   int y0 = b.yr[0], y1 = b.yr[m - 1];
   if(tfi != 12 && y1 > y0)
     {
      int ny = y1 - y0 + 1;
      int g[];
      string glab[];
      ArrayResize(g, m);
      ArrayResize(glab, ny);
      for(int i = 0; i < m; i++)
         g[i] = b.yr[i] - y0;
      for(int k = 0; k < ny; k++)
         glab[k] = I2S(y0 + k);
      SecStart("Come cambia nel tempo", "Stesse misure, anno per anno.");
      GroupTable(b, g, ny, glab, "Anno");
      SecEnd();
     }

   //--- periodo successivo
   SecStart("Cosa succede nel periodo successivo (momentum o mean reversion fra periodi)",
            "Per ogni condizione del periodo appena chiuso: quante volte il successivo va nella stessa direzione (blu = prosegue, " +
            "momentum; rosso = inverte, mean reversion), quanto &egrave; ampio rispetto al mediano, quante volte rompe il massimo " +
            "o il minimo precedente, quante volte resta dentro (inside), quante rotture sono false (rompe ma chiude di nuovo " +
            "dentro il range precedente) e quante volte torna a met&agrave; del periodo precedente.");
   NextTable(acc);
   SecEnd();

   //--- elenchi
   int idx[];
   if(tfi == 12)
     {
      ArrayResize(idx, m);
      for(int j = 0; j < m; j++)
         idx[j] = m - 1 - j;
      SecStart("Anno per anno", "");
      PeriodList(b, idx, m, medR);
      SecEnd();
      string sy = "";
      for(int j = 0; j < m; j++)
        {
         int i = idx[j];
         sy += PeriodLabel(tfi, b.t0[i]) + ": rendimento " + FP(b.ret[i], 2) + "%, spostamento " + FP(b.rng[i], 2) + "% " +
               (b.lf[i] ? "rialzista" : "ribassista") + ", " + CLS_NAME[b.cls[i]] + ", massimo " + TimeToString(b.tH[i], TIME_DATE) +
               ", minimo " + TimeToString(b.tL[i], TIME_DATE) + "; ";
        }
      R(g_rep, "Anno per anno: " + sy);
     }
   else
     {
      int k = m < 15 ? m : 15;
      bool used[];
      ArrayResize(used, m);
      for(int i = 0; i < m; i++)
         used[i] = false;
      ArrayResize(idx, k);
      for(int j = 0; j < k; j++)
        {
         int bi = -1;
         for(int i = 0; i < m; i++)
            if(!used[i] && (bi < 0 || b.rng[i] > b.rng[bi]))
               bi = i;
         used[bi] = true;
         idx[j] = bi;
        }
      SecStart("Periodi pi&ugrave; ampi della storia", "I 15 periodi con lo spostamento pi&ugrave; ampio.");
      PeriodList(b, idx, k, medR);
      SecEnd();
      string sb = "";
      int fmtT = b.src == 2 ? TIME_DATE : (TIME_DATE | TIME_MINUTES);
      for(int j = 0; j < k; j++)
        {
         int i = idx[j];
         sb += PeriodLabel(tfi, b.t0[i]) + " " + FP(b.rng[i], 2) + "% " + (b.lf[i] ? "rialzista" : "ribassista") + " (" +
               CLS_NAME[b.cls[i]] + (b.intra ? ", massimo " + TimeToString(b.tH[i], fmtT) + ", minimo " + TimeToString(b.tL[i], fmtT) : "") + "); ";
        }
      R(g_rep, "I 15 periodi pi&ugrave; ampi: " + sb);
      for(int j = 0; j < k; j++)
         idx[j] = m - 1 - j;
      SecStart("Ultimi periodi chiusi", "");
      PeriodList(b, idx, k, medR);
      SecEnd();
     }

   //--- righe per la Panoramica
   if(b.intra && b.curO > 0)
     {
      double el = MathMin(b.curCnt / b.medCnt, 1.0);
      double ch = MathMax(b.curH, g_last), cl = MathMin(b.curL, g_last);
      double rs = (ch - cl) / b.curO;
      double pos = ch > cl ? (g_last - cl) / (ch - cl) : Nan();
      int le = 0, ph = 0, pl = 0;
      for(int i = 0; i < m; i++)
        {
         if(b.rng[i] <= rs)
            le++;
         if(b.pH[i] <= el)
            ph++;
         if(b.pL[i] <= el)
            pl++;
        }
      double fromO = g_last / b.curO - 1;
      R(g_repCur, TF_LABEL[tfi] + " (" + PeriodLabel(tfi, b.curT0) + "): trascorso " + F(el * 100, 0) + "%, dall'apertura " + FP(fromO, 3) +
        "%, spostamento finora " + FP(rs, 3) + "% = " + F(Dv(rs, medR) * 100, 0) + "% del mediano (percentile " + F(100.0 * le / m, 0) +
        "), prezzo al " + F(pos * 100, 0) + "% del range, a questo punto il massimo era gi&agrave; fatto nel " + F(100.0 * ph / m, 0) +
        "% dei periodi e il minimo nel " + F(100.0 * pl / m, 0) + "%.");
      g_curRows += "<tr>" + TD(TF_LABEL[tfi]) + TD(PeriodLabel(tfi, b.curT0)) + TD(F(el * 100, 0) + "%") + TD(PX(b.curO)) +
                   TD(PX(ch)) + TD(PX(cl)) + TDc(FP(fromO, 3) + "%", PCol(fromO, 0, medR)) + TD(FP(rs, 3) + "%") +
                   TDc(F(Dv(rs, medR) * 100, 0) + "%", PCol(Dv(rs, medR), 1.0, 0.6)) + TD(F(100.0 * le / m, 0)) +
                   TD(F(pos * 100, 0) + "%") + TD(F(100.0 * ph / m, 0) + "%") + TD(F(100.0 * pl / m, 0) + "%") + "</tr>";
     }
   double upr = (double)nUp / m;
   g_sumRows += "<tr>" + TD(TF_LABEL[tfi]) + TD(I2S(m)) + TD(FP(medR, 3)) + TD(PX(medR * g_last)) + TD(FP(p90, 3)) +
                TDc(FP(upr, 1), PCol(upr, 0.5, 0.15)) + TD(FP((double)nc[0] / m, 1)) + TD(FP((double)nc[2] / m, 1)) +
                TD(FP(meanRetr, 3)) + TD(F(Mean(b.rf, m) * 100, 0)) + TD(b.intra ? ModeOf(b, true) : "&ndash;") +
                TD(b.intra ? ModeOf(b, false) : "&ndash;") + TDc(FP(sameAll, 1), PCol(sameAll, 0.5, 0.15)) + "</tr>";
  }

//+------------------------------------------------------------------+
//| Panoramica                                                        |
//+------------------------------------------------------------------+
void PriceSvg(CSeries &d)
  {
   int n = d.n;
   if(n < 10)
      return;
   double lmin = 1e300, lmax = -1e300;
   for(int i = 0; i < n; i++)
     {
      double v = MathLog(d.c[i]);
      if(v < lmin)
         lmin = v;
      if(v > lmax)
         lmax = v;
     }
   if(lmax <= lmin)
      lmax = lmin + 1e-9;
   int step = (int)MathCeil(n / 1200.0);
   if(step < 1)
      step = 1;
   string pc = "", ps = "";
   double sum = 0;
   for(int i = 0; i < n; i++)
     {
      sum += d.c[i];
      if(i >= 200)
         sum -= d.c[i - 200];
      if(i % step != 0 && i != n - 1)
         continue;
      double x = 50 + (double)i / (n - 1) * 1140;
      pc += DoubleToString(x, 1) + "," + DoubleToString(15 + (lmax - MathLog(d.c[i])) / (lmax - lmin) * 280, 1) + " ";
      if(i >= 199)
         ps += DoubleToString(x, 1) + "," + DoubleToString(15 + (lmax - MathLog(sum / 200)) / (lmax - lmin) * 280, 1) + " ";
     }
   W("<svg viewBox='0 0 1200 330' width='100%' class='svg'>");
   int lastY = 0;
   for(int i = 0; i < n; i++)
     {
      MqlDateTime t;
      TimeToStruct(d.t[i], t);
      if(t.year != lastY)
        {
         if(lastY != 0)
           {
            double x = 50 + (double)i / (n - 1) * 1140;
            W("<line x1='" + DoubleToString(x, 1) + "' y1='15' x2='" + DoubleToString(x, 1) + "' y2='295' stroke='#1f2937'/>" +
              "<text x='" + DoubleToString(x + 3, 1) + "' y='318' fill='#9ca3af' font-size='11'>" + I2S(t.year) + "</text>");
           }
         lastY = t.year;
        }
     }
   W("<text x='2' y='22' fill='#9ca3af' font-size='11'>" + PX(MathExp(lmax)) + "</text>");
   W("<text x='2' y='295' fill='#9ca3af' font-size='11'>" + PX(MathExp(lmin)) + "</text>");
   W("<polyline fill='none' stroke='" + C_BLUE + "' stroke-width='1.2' points='" + ps + "'/>");
   W("<polyline fill='none' stroke='#e5e7eb' stroke-width='1.2' points='" + pc + "'/>");
   W("</svg><div class='lg'><b style='background:#e5e7eb'></b>Chiusura giornaliera (scala log) <b style='background:" + C_BLUE +
     "'></b>SMA200</div>");
  }

void Overview(CSeries &d, const datetime lastT)
  {
   int n = d.n;
   if(n < 10)
     {
      SecStart("Stato attuale", "");
      W("<p class='muted'>Servono barre D1 per lo stato attuale.</p>");
      SecEnd();
      return;
     }
   double s50 = 0, s200 = 0;
   for(int i = MathMax(0, n - 50); i < n; i++)
      s50 += d.c[i];
   s50 /= MathMin(n, 50);
   for(int i = MathMax(0, n - 200); i < n; i++)
      s200 += d.c[i];
   s200 /= MathMin(n, 200);
   double hi52 = -1e300, lo52 = 1e300, pk = 0, dd = 0, mdd = 0;
   for(int i = 0; i < n; i++)
     {
      if(d.t[i] >= d.t[n - 1] - 365 * 86400)
        {
         hi52 = MathMax(hi52, d.c[i]);
         lo52 = MathMin(lo52, d.c[i]);
        }
      pk = MathMax(pk, d.c[i]);
      dd = Dv(d.c[i], pk) - 1;
      mdd = MathMin(mdd, dd);
     }
   SecStart("Stato attuale", "");
   W("<div class='kpi'>");
   Kpi("Ultimo prezzo", PX(g_last), TimeToString(lastT, TIME_DATE | TIME_MINUTES));
   Kpi("vs SMA50 giornaliera", FP(Dv(g_last, s50) - 1, 2) + "%", PX(s50));
   Kpi("vs SMA200 giornaliera", FP(Dv(g_last, s200) - 1, 2) + "%", PX(s200));
   Kpi("Massimo 52 settimane", PX(hi52), FP(Dv(g_last, hi52) - 1, 2) + "% dal massimo");
   Kpi("Minimo 52 settimane", PX(lo52), FP(Dv(g_last, lo52) - 1, 2) + "% dal minimo");
   Kpi("Drawdown attuale", FP(dd, 1) + "%", "massimo storico " + FP(mdd, 1) + "%");
   R(g_repHead, "Stato attuale: prezzo " + PX(g_last) + " (" + TimeToString(lastT, TIME_DATE | TIME_MINUTES) + "), " +
     FP(Dv(g_last, s50) - 1, 2) + "% dalla SMA50 giornaliera, " + FP(Dv(g_last, s200) - 1, 2) + "% dalla SMA200, " +
     FP(Dv(g_last, hi52) - 1, 2) + "% dal massimo a 52 settimane (" + PX(hi52) + "), " + FP(Dv(g_last, lo52) - 1, 2) +
     "% dal minimo a 52 settimane (" + PX(lo52) + "), drawdown attuale " + FP(dd, 1) + "%, massimo drawdown storico " + FP(mdd, 1) + "%.");
   string srt = "";
   int days[5] = {7, 30, 91, 182, 365};
   string dl[5] = {"1 settimana", "1 mese", "3 mesi", "6 mesi", "12 mesi"};
   for(int k = 0; k < 5; k++)
     {
      int j = -1;
      for(int i = n - 1; i >= 0; i--)
         if(d.t[i] <= d.t[n - 1] - days[k] * 86400)
           {
            j = i;
            break;
           }
      if(j >= 0)
        {
         Kpi("Rendimento " + dl[k], FP(Dv(g_last, d.c[j]) - 1, 2) + "%", "");
         srt += dl[k] + " " + FP(Dv(g_last, d.c[j]) - 1, 2) + "%; ";
        }
     }
   W("</div>");
   SecEnd();
   R(g_repHead, "Rendimenti: " + srt);
   SecStart("Periodo in corso, per timeframe",
            "Il periodo non ancora chiuso di ogni timeframe confrontato con la storia: quanto spostamento ha gi&agrave; fatto rispetto " +
            "al mediano (100% = ha gi&agrave; fatto uno spostamento tipico), in quale percentile storico cade, dove si trova il prezzo " +
            "nel range del periodo (0% = sul minimo, 100% = sul massimo) e in quale percentuale dei periodi passati il massimo e " +
            "il minimo erano gi&agrave; stati fatti a questo punto del periodo.");
   THead("Timeframe|Periodo|Trascorso|Apertura|Massimo finora|Minimo finora|Dall'apertura|Spostamento finora|vs mediano|Percentile|Posizione nel range|Massimo gi&agrave; fatto (storico)|Minimo gi&agrave; fatto (storico)");
   W(g_curRows);
   TEnd();
   SecEnd();
   SecStart("Sintesi di tutti i timeframe", "Valori su tutta la storia disponibile. Dettagli nelle schede.");
   THead("Timeframe|N periodi|Spost. mediano %|&asymp; prezzo|Spost. P90 %|% rialzisti|% Trend|% Mean rev.|Mean rev. media %|Restituito medio %|Massimo pi&ugrave; spesso|Minimo pi&ugrave; spesso|% successivo stessa direzione");
   W(g_sumRows);
   TEnd();
   SecEnd();
   SecStart("Come cambia il prezzo nel tempo", "");
   PriceSvg(d);
   SecEnd();
  }

//+------------------------------------------------------------------+
//| Volume                                                            |
//+------------------------------------------------------------------+
bool VolProfile(CSeries &s, const datetime from, VPr &r)
  {
   r.ok = false;
   int a = 0;
   while(a < s.n && s.t[a] < from)
      a++;
   if(s.n - a < 5)
      return false;
   double lo = 1e300, hi = -1e300, vs = 0, pv = 0;
   for(int i = a; i < s.n; i++)
     {
      lo = MathMin(lo, s.l[i]);
      hi = MathMax(hi, s.h[i]);
      vs += s.v[i];
      pv += (s.h[i] + s.l[i] + s.c[i]) / 3.0 * s.v[i];
     }
   if(hi <= lo || vs <= 0)
      return false;
   double w = (hi - lo) / VP_BINS;
   for(int k = 0; k < VP_BINS; k++)
      r.p[k] = 0;
   for(int i = a; i < s.n; i++)
     {
      int x = (int)((s.l[i] - lo) / w), y = (int)((s.h[i] - lo) / w);
      if(x > VP_BINS - 1)
         x = VP_BINS - 1;
      if(y > VP_BINS - 1)
         y = VP_BINS - 1;
      double per = s.v[i] / (y - x + 1);  // volume distribuito uniformemente sul range della barra
      for(int k = x; k <= y; k++)
         r.p[k] += per;
     }
   int poc = 0;
   double tot = 0;
   for(int k = 0; k < VP_BINS; k++)
     {
      tot += r.p[k];
      if(r.p[k] > r.p[poc])
         poc = k;
     }
   int vl = poc, vh = poc;
   double acc = r.p[poc];
   while(acc < 0.7 * tot && (vl > 0 || vh < VP_BINS - 1))
     {
      double upv = vh < VP_BINS - 1 ? r.p[vh + 1] : -1;
      double dnv = vl > 0 ? r.p[vl - 1] : -1;
      if(upv >= dnv)
        {
         vh++;
         acc += upv;
        }
      else
        {
         vl--;
         acc += dnv;
        }
     }
   r.lo = lo; r.w = w; r.pocI = poc; r.vaL = vl; r.vaH = vh; r.mx = r.p[poc];
   r.poc = lo + (poc + 0.5) * w;
   r.val = lo + vl * w;
   r.vah = lo + (vh + 1) * w;
   r.vwap = pv / vs;
   r.ok = true;
   return true;
  }

void VolumeTab(CSeries &h1, CSeries &d1)
  {
   bool useH = h1.n > 50 && h1.hasVol;
   if(!useH && !d1.hasVol)
     {
      SecStart("Volume", "");
      W("<p class='muted'>Nessun dato di volume disponibile.</p>");
      SecEnd();
      return;
     }
   datetime end = useH ? h1.t[h1.n - 1] : d1.t[d1.n - 1];
   int wd[5] = {365, 182, 91, 30, 7};
   string wl[5] = {"12 mesi", "6 mesi", "3 mesi", "1 mese", "1 settimana"};
   VPr pr[5];
   SecStart("Dove si &egrave; scambiato di pi&ugrave; (Volume Profile)",
            "Profilo da barre " + (useH ? "H1" : "D1") + ": il volume di ogni barra &egrave; distribuito sul suo range. " +
            "<b style='color:#f59e0b'>Arancio</b> = POC (prezzo con pi&ugrave; volume), blu = Value Area (70% del volume), " +
            "riga bianca = prezzo attuale. Sui CFD &egrave; tick volume: misura l'attivit&agrave;, non il controvalore.");
   THead("Finestra|POC (prezzo con pi&ugrave; volume)|Value Area bassa|Value Area alta|VWAP|Prezzo vs POC|Prezzo vs VWAP|Posizione");
   for(int k = 0; k < 5; k++)
     {
      bool okp = useH ? VolProfile(h1, end - wd[k] * 86400, pr[k]) : VolProfile(d1, end - wd[k] * 86400, pr[k]);
      if(!okp)
         continue;
      double vp = Dv(g_last, pr[k].poc) - 1, vw = Dv(g_last, pr[k].vwap) - 1;
      string pos = g_last > pr[k].vah ? "sopra la Value Area" : (g_last < pr[k].val ? "sotto la Value Area" : "dentro la Value Area");
      W("<tr>" + TD(wl[k]) + TD(PX(pr[k].poc)) + TD(PX(pr[k].val)) + TD(PX(pr[k].vah)) + TD(PX(pr[k].vwap)) +
        TDc(FP(vp, 2) + "%", PCol(vp, 0, 0.05)) + TDc(FP(vw, 2) + "%", PCol(vw, 0, 0.05)) + TD(pos) + "</tr>");
      R(g_repVol, "Volume Profile " + wl[k] + ": POC " + PX(pr[k].poc) + " (prezzo " + FP(vp, 2) + "% dal POC), Value Area " +
        PX(pr[k].val) + " - " + PX(pr[k].vah) + ", VWAP " + PX(pr[k].vwap) + " (prezzo " + FP(vw, 2) + "%), prezzo " + pos + ".");
     }
   TEnd();
   W("<div class='vps'>");
   for(int k = 0; k < 5; k++)
     {
      if(!pr[k].ok)
         continue;
      int cb = (int)((g_last - pr[k].lo) / pr[k].w);
      W("<div class='vp'><div class='ct'>" + wl[k] + "</div><div class='cf'>" + PX(pr[k].lo + VP_BINS * pr[k].w) + "</div>");
      for(int z = VP_BINS - 1; z >= 0; z--)
        {
         string col = z == pr[k].pocI ? C_AMBER : ((z >= pr[k].vaL && z <= pr[k].vaH) ? "#1d4ed8" : "#374151");
         W("<div class='r" + (z == cb ? " cur" : "") + "' title='" + PX(pr[k].lo + (z + 0.5) * pr[k].w) + "'><i style='width:" +
           F(Dv(pr[k].p[z], pr[k].mx) * 100, 1) + "%;background:" + col + "'></i></div>");
        }
      W("<div class='cf'>" + PX(pr[k].lo) + "</div></div>");
     }
   W("</div>");
   SecEnd();

   SecStart("Volume attuale rispetto allo storico", "");
   W("<div class='kpi'>");
   if(d1.hasVol && d1.n > 30)
     {
      int n = d1.n, j = n - 2;  // ultima sessione chiusa
      double m20 = 0, m252 = 0, r20 = 0, r252 = 0;
      int c20 = 0, c252 = 0, below = 0;
      for(int i = MathMax(0, j - 20); i < j; i++)
        {
         m20 += d1.v[i];
         c20++;
        }
      for(int i = MathMax(0, j - 252); i < j; i++)
        {
         m252 += d1.v[i];
         c252++;
         if(d1.v[i] < d1.v[j])
            below++;
        }
      for(int i = MathMax(0, j - 19); i <= j; i++)
         r20 += d1.v[i];
      for(int i = MathMax(0, j - 251); i <= j; i++)
         r252 += d1.v[i];
      m20 /= MathMax(c20, 1);
      m252 /= MathMax(c252, 1);
      r20 /= MathMin(20, j + 1);
      r252 /= MathMin(252, j + 1);
      Kpi("Volume ultima sessione chiusa", DoubleToString(d1.v[j], 0), TimeToString(d1.t[j], TIME_DATE));
      Kpi("vs media 20 sessioni", F(Dv(d1.v[j], m20), 2) + "&times;", "");
      Kpi("vs media 252 sessioni", F(Dv(d1.v[j], m252), 2) + "&times;", "");
      Kpi("Percentile sull'ultimo anno", F(100.0 * below / MathMax(c252, 1), 0), "");
      Kpi("Media 20 / media 252", F(Dv(r20, r252), 2) + "&times;", "partecipazione recente vs anno");
      Kpi("Sessione in corso finora", DoubleToString(d1.v[n - 1], 0), TimeToString(d1.t[n - 1], TIME_DATE));
      R(g_repVol, "Volume ultima sessione chiusa (" + TimeToString(d1.t[j], TIME_DATE) + "): " + F(Dv(d1.v[j], m20), 2) +
        "x la media di 20 sessioni, " + F(Dv(d1.v[j], m252), 2) + "x la media di 252, percentile " + F(100.0 * below / MathMax(c252, 1), 0) +
        " sull'ultimo anno; media 20 sessioni / media 252 = " + F(Dv(r20, r252), 2) + ".");
     }
   double a12[24], a4w[24], al[24];
   int n12[24], n4w[24], nl[24];
   bool hasH = h1.n > 50 && h1.hasVol;
   if(hasH)
     {
      ArrayInitialize(a12, 0.0); ArrayInitialize(a4w, 0.0); ArrayInitialize(al, 0.0);
      ArrayInitialize(n12, 0); ArrayInitialize(n4w, 0); ArrayInitialize(nl, 0);
      int n = h1.n, j = n - 2;  // ultima ora chiusa
      datetime te = h1.t[n - 1];
      long lastDay = (long)te / 86400;
      MqlDateTime tj;
      TimeToStruct(h1.t[j], tj);
      double sameSum = 0;
      int sameN = 0;
      for(int i = j - 1; i >= 0 && sameN < 20; i--)
        {
         MqlDateTime t;
         TimeToStruct(h1.t[i], t);
         if(t.hour == tj.hour)
           {
            sameSum += h1.v[i];
            sameN++;
           }
        }
      for(int i = 0; i < n; i++)
        {
         MqlDateTime t;
         TimeToStruct(h1.t[i], t);
         if(h1.t[i] >= te - 365 * 86400)
           {
            a12[t.hour] += h1.v[i];
            n12[t.hour]++;
           }
         if(h1.t[i] >= te - 28 * 86400)
           {
            a4w[t.hour] += h1.v[i];
            n4w[t.hour]++;
           }
         if((long)h1.t[i] / 86400 == lastDay)
           {
            al[t.hour] += h1.v[i];
            nl[t.hour]++;
           }
        }
      if(sameN > 0 && sameSum > 0)
        {
         Kpi("Ultima ora chiusa vs stessa ora (20 gg)", F(h1.v[j] / (sameSum / sameN), 2) + "&times;", TimeToString(h1.t[j], TIME_DATE | TIME_MINUTES));
         R(g_repVol, "Ultima ora chiusa (" + TimeToString(h1.t[j], TIME_DATE | TIME_MINUTES) + "): " + F(h1.v[j] / (sameSum / sameN), 2) +
           "x la media della stessa ora negli ultimi 20 giorni.");
        }
     }
   W("</div>");
   if(hasH)
     {
      double mx = 0;
      for(int k = 0; k < 24; k++)
        {
         a12[k] = n12[k] > 0 ? a12[k] / n12[k] : 0;
         a4w[k] = n4w[k] > 0 ? a4w[k] / n4w[k] : 0;
         al[k] = nl[k] > 0 ? al[k] / nl[k] : 0;
         mx = MathMax(mx, MathMax(a12[k], MathMax(a4w[k], al[k])));
        }
      W("<h3>Volume medio per ora (orario dei dati)</h3>");
      THead("Ora|Media 12 mesi|Media ultime 4 settimane|Ultima sessione|Ultime 4 sett. vs 12 mesi|Ultima sessione vs 12 mesi");
      R(g_repVol, "Volume medio per ora:");
      for(int k = 0; k < 24; k++)
        {
         if(n12[k] == 0)
            continue;
         double r1 = a12[k] > 0 ? a4w[k] / a12[k] : Nan(), r2 = (a12[k] > 0 && nl[k] > 0) ? al[k] / a12[k] : Nan();
         W("<tr>" + TD(StringFormat("%02dh", k)) + TD(HBar(a12[k], mx, DoubleToString(a12[k], 0))) +
           TD(HBar(a4w[k], mx, DoubleToString(a4w[k], 0))) + TD(nl[k] > 0 ? HBar(al[k], mx, DoubleToString(al[k], 0)) : "&ndash;") +
           TDc(F(r1, 2) + "&times;", PCol(r1, 1.0, 0.6)) + TDc(F(r2, 2) + "&times;", PCol(r2, 1.0, 0.6)) + "</tr>");
         R(g_repVol, "  " + StringFormat("%02dh", k) + ": volume medio 12 mesi " + DoubleToString(a12[k], 0) + ", ultime 4 settimane " +
           DoubleToString(a4w[k], 0) + " (" + F(r1, 2) + "x), ultima sessione " + (nl[k] > 0 ? DoubleToString(al[k], 0) : "-") + ".");
        }
      TEnd();
     }
   SecEnd();
  }

//+------------------------------------------------------------------+
//| EVENTI: swing, rotture, impulsi, notizie, gap                     |
//| Ogni movimento del prezzo, come lo esegue e a che ora.            |
//+------------------------------------------------------------------+
#define NEV 5
string   EV_NAME[NEV] = {"M5", "M15", "H1", "H4", "D1"};
int      EV_SEC[NEV]  = {300, 900, 3600, 14400, 86400};
string   g_repEv = "";
string   MKT_NAME[4]  = {"New York", "Londra", "Francoforte", "Tokyo"};
string   MKT_SHORT[4] = {"NY", "LDN", "FRA", "TKY"};
int      g_ref = 0, g_refOffA = 0, g_refOffB = 0;  // piazza di riferimento e sua differenza dai dati (gennaio / luglio)
string   g_newsCur[];
int      g_nCurN = 0;
string   g_covInfo = "";
// notizie (orari gia' allineati ai dati)
datetime g_nT[];
int      g_nImp[];
string   g_nName[];
double   g_nAct[], g_nFc[];
int      g_nN = 0;
string   g_nInfo = "";
int      g_offW = 0, g_offS = 0;
string   g_alignRows = "";
// swing
bool     g_swOk[NEV];
double   g_swH[NEV][24], g_swL[NEV][24], g_swBig[NEV][24];
double   g_swDH[7], g_swDL[7];
string   g_swRows = "";
// rotture del timeframe in analisi
string   g_boRows = "";
int      g_boN = 0, g_boLook = 20;
double   g_boBase = 0;
bool     g_boHi[], g_boCl[], g_boF[], g_boNw[];
int      g_boRc[];
int      g_boHold[], g_boAge[], g_boHr[], g_boDw[];
double   g_boExc[], g_boAdx[], g_boVr[], g_boRv[];
// impulsi della finestra in analisi
int      g_imN = 0;
double   g_imSz[], g_imC15[], g_imC60[], g_imRt[];
int      g_imNw[], g_imHr[], g_imMd[], g_imDw[], g_imYr[];
bool     g_imUp[];
double   g_imRv[], g_rvM[];
// gap
int      g_gpN = 0;
double   g_gpS[], g_gpFt[];

int HourOf(const datetime t) { return (int)(((long)t % 86400) / 3600); }
int MinOfDay(const datetime t) { return (int)(((long)t % 86400) / 60); }
int DowMon(const datetime t) { return (int)(((long)t / 86400 + 3) % 7); }  // 0 = lunedi'

string HourLab(const int h)
  {
   if(g_ref < 0)
      return StringFormat("%02dh", h);
   int a = ((h + g_refOffA) % 24 + 24) % 24, b = ((h + g_refOffB) % 24 + 24) % 24;
   return StringFormat("%02dh (%s %02dh", h, MKT_SHORT[g_ref], a) + (a != b ? StringFormat("/%02dh", b) : "") + ")";
  }

string SlotLab(const int mod)
  {
   int h = mod / 60, mi = mod % 60;
   if(g_ref < 0)
      return StringFormat("%02d:%02d", h, mi);
   int a = ((h + g_refOffA) % 24 + 24) % 24, b = ((h + g_refOffB) % 24 + 24) % 24;
   return StringFormat("%02d:%02d (%s %02d:%02d", h, mi, MKT_SHORT[g_ref], a, mi) + (a != b ? StringFormat("/%02d:%02d", b, mi) : "") + ")";
  }

string DurLab(const double hrs)
  {
   if(!MathIsValidNumber(hrs))
      return "-";
   if(hrs < 1)
      return F(hrs * 60, 0) + " min";
   if(hrs < 48)
      return F(hrs, 1) + " ore";
   return F(hrs / 24, 1) + " giorni";
  }

double MedianOf(const double &a[], const int n)
  {
   double s[];
   Sorted(a, n, s);
   return Pct(s, n, 50);
  }

int LowerBound(const datetime &t[], const int n, const datetime x)
  {
   int lo = 0, hi = n;
   while(lo < hi)
     {
      int mid = (lo + hi) / 2;
      if(t[mid] < x)
         lo = mid + 1;
      else
         hi = mid;
     }
   return lo;
  }

//--- ora legale USA (per allineare dati e calendario)
datetime NthSunday(const int y, const int mon, const int nth)
  {
   MqlDateTime d;
   ZeroMemory(d);
   d.year = y;
   d.mon = mon;
   d.day = 1;
   datetime t = StructToTime(d);
   TimeToStruct(t, d);
   int add = (7 - d.day_of_week) % 7;
   return t + (add + 7 * (nth - 1)) * 86400;
  }

datetime LastSunday(const int y, const int mon)
  {
   MqlDateTime d;
   ZeroMemory(d);
   d.year = mon == 12 ? y + 1 : y;
   d.mon = mon == 12 ? 1 : mon + 1;
   d.day = 1;
   datetime t = StructToTime(d) - 86400;
   TimeToStruct(t, d);
   return t - d.day_of_week * 86400;
  }

bool IsUSDST(const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   datetime a, b;
   if(d.year >= 2007)
     {
      a = NthSunday(d.year, 3, 2);
      b = NthSunday(d.year, 11, 1);
     }
   else
     {
      a = NthSunday(d.year, 4, 1);
      b = LastSunday(d.year, 10);
     }
   return t >= a && t < b;
  }

bool IsEUDST(const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   return t >= LastSunday(d.year, 3) && t < LastSunday(d.year, 10);
  }

// ore di differenza da UTC di una piazza (0 New York, 1 Londra, 2 Francoforte, 3 Tokyo)
int MktOffset(const int mkt, const datetime t)
  {
   if(mkt == 0)
      return IsUSDST(t) ? -4 : -5;
   if(mkt == 1)
      return IsEUDST(t) ? 1 : 0;
   if(mkt == 2)
      return IsEUDST(t) ? 2 : 1;
   return 9;
  }

// ore di differenza da UTC dell'orologio dei dati
int DataOffset(const datetime t)
  {
   if(InpDataTZ == TZ_BROKER_NY7)
      return IsUSDST(t) ? 3 : 2;
   if(InpDataTZ == TZ_UTC)
      return 0;
   if(InpDataTZ == TZ_EUROPE)
      return IsEUDST(t) ? 2 : 1;
   return InpDataGMT;
  }

string TZName(void)
  {
   if(InpDataTZ == TZ_BROKER_NY7)
      return "ora del broker GMT+2/+3 con ora legale USA (New York + 7)";
   if(InpDataTZ == TZ_UTC)
      return "UTC";
   if(InpDataTZ == TZ_EUROPE)
      return "ora dell'Europa centrale (CET/CEST)";
   return "GMT" + (InpDataGMT >= 0 ? "+" : "") + I2S(InpDataGMT) + " fisso";
  }

// orario locale di una piazza (minuti dalla mezzanotte del giorno 'day') espresso nell'orologio dei dati
datetime LocalToData(const long day, const int mkt, const int mins)
  {
   datetime t = (datetime)(day * 86400 + (long)mins * 60);
   return t + (DataOffset(t) - MktOffset(mkt, t)) * 3600;
  }

void RefSetup(const string sym, const datetime ref)
  {
   g_ref = -1;
   g_refOffA = 0;
   g_refOffB = 0;
   if(InpRefMarket == REF_NONE)
      return;
   if(InpRefMarket != REF_AUTO)
      g_ref = (int)InpRefMarket - 1;
   else
     {
      string b = SymbolInfoString(sym, SYMBOL_CURRENCY_BASE), p = SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT);
      bool fx = StringLen(b) == 3 && StringLen(p) == 3 && b != p && StringFind("XAUXAGXPTXPD", b) < 0;
      if(fx)
         g_ref = 1;   // forex: Londra e' il centro del mercato
      else
         if(p == "EUR" || p == "CHF")
            g_ref = 2;
         else
            if(p == "GBP")
               g_ref = 1;
            else
               if(p == "JPY")
                  g_ref = 3;
               else
                  g_ref = 0;
     }
   MqlDateTime d;
   TimeToStruct(ref, d);
   MqlDateTime a;
   ZeroMemory(a);
   a.year = d.year;
   a.mon = 1;
   a.day = 15;
   a.hour = 12;
   datetime ta = StructToTime(a);
   a.mon = 7;
   datetime tb = StructToTime(a);
   g_refOffA = MktOffset(g_ref, ta) - DataOffset(ta);
   g_refOffB = MktOffset(g_ref, tb) - DataOffset(tb);
  }

string NewsCurStr(void)
  {
   string r = "";
   for(int i = 0; i < g_nCurN; i++)
      r += (i > 0 ? "+" : "") + g_newsCur[i];
   return r == "" ? "-" : r;
  }

// valute delle notizie: dal parametro o, se vuoto, dalla valuta base e di profitto dello strumento
void ResolveNewsCur(const string sym)
  {
   g_nCurN = 0;
   ArrayResize(g_newsCur, 0);
   string list = InpNewsCurrency;
   if(list == "")
     {
      string b = SymbolInfoString(sym, SYMBOL_CURRENCY_BASE), p = SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT);
      list = p;
      if(b != "" && b != p)
         list = b + "," + p;
     }
   string parts[];
   int k = StringSplit(list, ',', parts);
   for(int i = 0; i < k; i++)
     {
      string c = parts[i];
      StringTrimLeft(c);
      StringTrimRight(c);
      StringToUpper(c);
      if(StringLen(c) != 3 || StringFind("XAUXAGXPTXPD", c) >= 0)
         continue;
      bool dup = false;
      for(int z = 0; z < g_nCurN; z++)
         if(g_newsCur[z] == c)
            dup = true;
      if(dup)
         continue;
      g_nCurN++;
      ArrayResize(g_newsCur, g_nCurN);
      g_newsCur[g_nCurN - 1] = c;
     }
   if(g_nCurN == 0)
     {
      g_nCurN = 1;
      ArrayResize(g_newsCur, 1);
      g_newsCur[0] = "USD";
     }
  }

// primo anno con copertura oraria completa: in alcuni storici i primi anni coprono solo parte della giornata
datetime CoverageStart(CSeries &h)
  {
   g_covInfo = "";
   if(h.n < 2000)
      return 0;
   MqlDateTime d;
   TimeToStruct(h.t[0], d);
   int y0 = d.year;
   TimeToStruct(h.t[h.n - 1], d);
   int y1 = d.year;
   int ny = y1 - y0 + 1;
   double hrs[], days[];
   ArrayResize(hrs, ny);
   ArrayResize(days, ny);
   ArrayInitialize(hrs, 0.0);
   ArrayInitialize(days, 0.0);
   long cur = -1;
   int yc = y0;
   for(int i = 0; i < h.n; i++)
     {
      long dd = (long)h.t[i] / 86400;
      if(dd != cur)
        {
         TimeToStruct(h.t[i], d);
         yc = d.year;
         days[yc - y0] += 1;
         cur = dd;
        }
      hrs[yc - y0] += 1;
     }
   double ref = 0;
   int nr = 0;
   for(int y = y1; y >= y0 && nr < 3; y--)
      if(days[y - y0] >= 50)
        {
         ref += hrs[y - y0] / days[y - y0];
         nr++;
        }
   if(nr == 0)
      return 0;
   ref /= nr;
   int ys = y0;
   while(ys <= y1 && days[ys - y0] > 0 && hrs[ys - y0] / days[ys - y0] < 0.85 * ref)
      ys++;
   if(ys <= y0 || ys > y1)
      return 0;
   g_covInfo = "Anni " + I2S(y0) + (ys - 1 > y0 ? "-" + I2S(ys - 1) : "") + " esclusi dall'analisi: coprono in media " +
               F(hrs[0] / MathMax(days[0], 1.0), 1) + " ore al giorno contro " + F(ref, 1) + " degli anni recenti.";
   MqlDateTime a;
   ZeroMemory(a);
   a.year = ys;
   a.mon = 1;
   a.day = 1;
   return StructToTime(a);
  }

void TrimFrom(CSeries &s, const datetime from)
  {
   if(from <= 0 || s.n == 0)
      return;
   int k = LowerBound(s.t, s.n, from);
   if(k <= 0)
      return;
   int m = s.n - k;
   datetime t2[];
   double o2[], h2[], l2[], c2[], v2[];
   ArrayCopy(t2, s.t, 0, k, m);
   ArrayCopy(o2, s.o, 0, k, m);
   ArrayCopy(h2, s.h, 0, k, m);
   ArrayCopy(l2, s.l, 0, k, m);
   ArrayCopy(c2, s.c, 0, k, m);
   ArrayCopy(v2, s.v, 0, k, m);
   ArrayFree(s.t); ArrayFree(s.o); ArrayFree(s.h); ArrayFree(s.l); ArrayFree(s.c); ArrayFree(s.v);
   ArrayCopy(s.t, t2);
   ArrayCopy(s.o, o2);
   ArrayCopy(s.h, h2);
   ArrayCopy(s.l, l2);
   ArrayCopy(s.c, c2);
   ArrayCopy(s.v, v2);
   s.n = m;
  }

//--- indicatori
void CalcATR(CSeries &s, const int p, double &a[])
  {
   ArrayResize(a, s.n);
   double sum = 0;
   for(int i = 0; i < s.n; i++)
     {
      double tr = i == 0 ? s.h[i] - s.l[i] : MathMax(s.h[i], s.c[i - 1]) - MathMin(s.l[i], s.c[i - 1]);
      if(i < p)
        {
         sum += tr;
         a[i] = sum / (i + 1);
        }
      else
         a[i] = (a[i - 1] * (p - 1) + tr) / p;
     }
  }

void CalcADX(CSeries &s, const int p, double &adx[])
  {
   int n = s.n;
   ArrayResize(adx, n);
   if(n == 0)
      return;
   adx[0] = 0;
   double trS = 0, pS = 0, mS = 0, dxS = 0;
   for(int i = 1; i < n; i++)
     {
      double up = s.h[i] - s.h[i - 1], dn = s.l[i - 1] - s.l[i];
      double pdm = (up > dn && up > 0) ? up : 0, mdm = (dn > up && dn > 0) ? dn : 0;
      double tr = MathMax(s.h[i], s.c[i - 1]) - MathMin(s.l[i], s.c[i - 1]);
      if(i <= p)
        {
         trS += tr;
         pS += pdm;
         mS += mdm;
        }
      else
        {
         trS = trS - trS / p + tr;
         pS = pS - pS / p + pdm;
         mS = mS - mS / p + mdm;
        }
      double pdi = trS > 0 ? 100 * pS / trS : 0, mdi = trS > 0 ? 100 * mS / trS : 0;
      double dx = (pdi + mdi) > 0 ? 100 * MathAbs(pdi - mdi) / (pdi + mdi) : 0;
      if(i < 2 * p)
        {
         dxS += dx;
         adx[i] = dxS / i;
        }
      else
         adx[i] = (adx[i - 1] * (p - 1) + dx) / p;
     }
  }

// ZigZag: nuovo swing quando il prezzo inverte di almeno k x ATR. pty: +1 massimo, -1 minimo
// volume relativo alla stessa fascia oraria: volume della barra / media delle stesse barre dei 'nd' giorni precedenti
void CalcRVOL(CSeries &s, const int barSec, const int nd, double &rv[])
  {
   ArrayResize(rv, s.n);
   double nv = Nan();
   for(int i = 0; i < s.n; i++)
      rv[i] = nv;
   if(!s.hasVol || nd < 1 || barSec <= 0)
      return;
   int ns = barSec >= 86400 ? 1 : 86400 / barSec;
   double buf[], sum[];
   int cnt[], pos[];
   ArrayResize(buf, ns * nd);
   ArrayResize(sum, ns);
   ArrayResize(cnt, ns);
   ArrayResize(pos, ns);
   ArrayInitialize(sum, 0.0);
   ArrayInitialize(cnt, 0);
   ArrayInitialize(pos, 0);
   for(int i = 0; i < s.n; i++)
     {
      int sl = ns == 1 ? 0 : (int)(((long)s.t[i] % 86400) / barSec);
      if(sl >= ns)
         sl = ns - 1;
      if(cnt[sl] >= nd)
         rv[i] = Dv(s.v[i], sum[sl] / nd);
      int b = sl * nd + pos[sl];
      if(cnt[sl] >= nd)
         sum[sl] -= buf[b];
      else
         cnt[sl]++;
      buf[b] = s.v[i];
      sum[sl] += s.v[i];
      pos[sl] = (pos[sl] + 1) % nd;
     }
  }

int ZigZag(CSeries &s, const double &atr[], const double k, int &pv[], int &pty[])
  {
   int np = 0, dir = 0, ei = 0, ih = 0, il = 0;
   double ext = 0, eh = s.h[0], el = s.l[0];
   ArrayResize(pv, 0, s.n / 8 + 16);
   ArrayResize(pty, 0, s.n / 8 + 16);
   for(int i = 1; i < s.n; i++)
     {
      double th = k * atr[i];
      int add = -1, typ = 0;
      if(dir == 0)
        {
         if(s.h[i] > eh) { eh = s.h[i]; ih = i; }
         if(s.l[i] < el) { el = s.l[i]; il = i; }
         if(eh - el >= th && th > 0)
           {
            if(ih < il) { add = ih; typ = 1; dir = -1; ext = el; ei = il; }
            else { add = il; typ = -1; dir = 1; ext = eh; ei = ih; }
           }
        }
      else
         if(dir == 1)
           {
            if(s.h[i] > ext) { ext = s.h[i]; ei = i; }
            else
               if(ext - s.l[i] >= th) { add = ei; typ = 1; dir = -1; ext = s.l[i]; ei = i; }
           }
         else
           {
            if(s.l[i] < ext) { ext = s.l[i]; ei = i; }
            else
               if(s.h[i] - ext >= th) { add = ei; typ = -1; dir = 1; ext = s.h[i]; ei = i; }
           }
      if(add >= 0)
        {
         np++;
         ArrayResize(pv, np, s.n / 8 + 16);
         ArrayResize(pty, np, s.n / 8 + 16);
         pv[np - 1] = add;
         pty[np - 1] = typ;
        }
     }
   return np;
  }

//+------------------------------------------------------------------+
//| Notizie dal calendario economico di MT5                           |
//+------------------------------------------------------------------+
int NewsNear(const datetime a, const datetime b)
  {
   if(g_nN == 0)
      return -1;
   int k = LowerBound(g_nT, g_nN, a);
   return (k < g_nN && g_nT[k] <= b) ? k : -1;
  }

void LoadNews(const datetime from, const datetime to)
  {
   g_nN = 0;
   ArrayResize(g_nT, 0); ArrayResize(g_nImp, 0); ArrayResize(g_nName, 0); ArrayResize(g_nAct, 0); ArrayResize(g_nFc, 0);
   if(!InpNews)
     {
      g_nInfo = "Notizie disattivate nei parametri.";
      return;
     }
   ulong cid[];
   int cimp[], cmode[];
   string cname[];
   int nc = 0;
   datetime tT[];
   int tImp[];
   string tName[];
   double tAct[], tFc[];
   int tn = 0;
   MqlDateTime d;
   TimeToStruct(from, d);
   int y0 = d.year;
   TimeToStruct(to, d);
   int y1 = d.year;
   for(int cu = 0; cu < g_nCurN; cu++)
      for(int y = y0; y <= y1 && !IsStopped(); y++)
        {
         MqlDateTime a;
         ZeroMemory(a);
         a.year = y;
         a.mon = 1;
         a.day = 1;
         datetime ya = StructToTime(a);
         a.year = y + 1;
         datetime yb = StructToTime(a) - 1;
         MqlCalendarValue vals[];
         int n = CalendarValueHistory(vals, ya, yb, NULL, g_newsCur[cu]);
         for(int i = 0; i < n; i++)
           {
            ulong id = vals[i].event_id;
            int k = -1;
            for(int z = 0; z < nc; z++)
               if(cid[z] == id)
                 {
                  k = z;
                  break;
                 }
            if(k < 0)
              {
               MqlCalendarEvent ev;
               if(!CalendarEventById(id, ev))
                  continue;
               nc++;
               ArrayResize(cid, nc); ArrayResize(cimp, nc); ArrayResize(cmode, nc); ArrayResize(cname, nc);
               k = nc - 1;
               cid[k] = id;
               cimp[k] = (int)ev.importance;
               cmode[k] = (int)ev.time_mode;
               cname[k] = (g_nCurN > 1 ? g_newsCur[cu] + " " : "") + ev.name;
              }
            if(cimp[k] < InpNewsMinImp || cmode[k] != (int)CALENDAR_TIMEMODE_DATETIME)
               continue;
            if(vals[i].time < from || vals[i].time > to)
               continue;
            int m = tn;
            tn++;
            ArrayResize(tT, tn, 8192); ArrayResize(tImp, tn, 8192); ArrayResize(tName, tn, 8192);
            ArrayResize(tAct, tn, 8192); ArrayResize(tFc, tn, 8192);
            tT[m] = vals[i].time;
            tImp[m] = cimp[k];
            tName[m] = cname[k];
            tAct[m] = vals[i].actual_value != LONG_MIN ? vals[i].actual_value / 1000000.0 : Nan();
            tFc[m] = vals[i].forecast_value != LONG_MIN ? vals[i].forecast_value / 1000000.0 : Nan();
           }
        }
   //--- ordina per orario (con piu' valute le liste arrivano separate): chiave = orario * 2^20 + indice
   long key[];
   ArrayResize(key, tn);
   for(int i = 0; i < tn; i++)
      key[i] = (long)tT[i] * 1048576 + i;
   if(tn > 1)
      ArraySort(key);
   g_nN = tn;
   ArrayResize(g_nT, tn); ArrayResize(g_nImp, tn); ArrayResize(g_nName, tn); ArrayResize(g_nAct, tn); ArrayResize(g_nFc, tn);
   for(int r = 0; r < tn; r++)
     {
      int i = (int)(key[r] % 1048576);
      g_nT[r] = tT[i];
      g_nImp[r] = tImp[i];
      g_nName[r] = tName[i];
      g_nAct[r] = tAct[i];
      g_nFc[r] = tFc[i];
     }
   g_nInfo = g_nN > 0 ? I2S(g_nN) + " notizie " + NewsCurStr() + " con importanza &ge; " + I2S(InpNewsMinImp) + " dal " +
             TimeToString(g_nT[0], TIME_DATE) + " al " + TimeToString(g_nT[g_nN - 1], TIME_DATE) + "."
             : "Nessuna notizia dal calendario: MT5 deve essere collegato al conto del broker quando lanci lo script.";
  }

// Allinea gli orari del calendario a quelli dei dati. MT5 salva lo storico del calendario con il fuso ATTUALE del
// server, quindi lo spostamento atteso e' (fuso dei dati alla data della notizia) - (fuso attuale del server).
// Attorno a quello si cerca lo spostamento (-2..+2 ore) per cui il minuto delle notizie importanti ha il range
// piu' ampio, separatamente per ora legale USA e ora solare.
void AlignNews(CSeries &s)
  {
   g_offW = 0;
   g_offS = 0;
   g_alignRows = "";
   if(g_nN == 0)
      return;
   int srv = (int)MathRound((double)((long)TimeTradeServer() - (long)TimeGMT()) / 3600.0);
   if(srv < -12 || srv > 14)
      srv = 0;
   int ex[];
   ArrayResize(ex, g_nN);
   int exS[2] = {0, 0};
   bool exF[2] = {false, false};
   for(int i = 0; i < g_nN; i++)
     {
      ex[i] = DataOffset(g_nT[i]) - srv;
      int se = IsUSDST(g_nT[i]) ? 1 : 0;
      if(!exF[se])
        {
         exS[se] = ex[i];
         exF[se] = true;
        }
     }
   double sc[10];
   for(int z = 0; z < 10; z++)
      sc[z] = Nan();
   if(s.n >= 1000)
     {
      int step = s.n / 200000 + 1;
      double tmp[];
      ArrayResize(tmp, s.n / step + 1);
      int q = 0;
      for(int i = 0; i < s.n; i += step)
         tmp[q++] = (s.h[i] - s.l[i]) / s.o[i];
      double medAll = MedianOf(tmp, q);
      double vv[];
      ArrayResize(vv, g_nN);
      for(int season = 0; season < 2; season++)
         for(int o = -2; o <= 2; o++)
           {
            int nv = 0;
            for(int i = 0; i < g_nN; i++)
              {
               if(g_nImp[i] < 3 || (IsUSDST(g_nT[i]) ? 1 : 0) != season)
                  continue;
               datetime tt = g_nT[i] + (ex[i] + o) * 3600;
               int k = LowerBound(s.t, s.n, tt);
               if(k >= s.n || s.t[k] != tt)
                  continue;
               vv[nv++] = (s.h[k] - s.l[k]) / s.o[k];
              }
            sc[season * 5 + o + 2] = nv >= 10 ? Dv(MedianOf(vv, nv), medAll) : Nan();
           }
     }
   for(int season = 0; season < 2; season++)
     {
      int bi = 2;
      for(int z = 0; z < 5; z++)
         if(MathIsValidNumber(sc[season * 5 + z]) && (!MathIsValidNumber(sc[season * 5 + bi]) || sc[season * 5 + z] > sc[season * 5 + bi]))
            bi = z;
      int off = (MathIsValidNumber(sc[season * 5 + bi]) && sc[season * 5 + bi] >= 1.5) ? bi - 2 : 0;
      if(season == 0)
         g_offW = off;
      else
         g_offS = off;
      int tot = exS[season] + off;
      string row = "<tr>" + TD(season == 0 ? "Ora solare USA (inverno)" : "Ora legale USA (estate)") +
                   TD((exS[season] >= 0 ? "+" : "") + I2S(exS[season]) + " ore");
      for(int z = 0; z < 5; z++)
         row += TDc(F(sc[season * 5 + z], 2) + "&times;", z == bi && MathIsValidNumber(sc[season * 5 + z]) ? "rgba(59,130,246,.45)" : "");
      g_alignRows += row + TD((tot >= 0 ? "+" : "") + I2S(tot) + " ore") + "</tr>";
      R(g_repEv, "Allineamento calendario/dati, " + (season == 0 ? "inverno" : "estate") + ": spostamento atteso " + I2S(exS[season]) +
        " ore (fuso dei dati meno fuso attuale del server, " + (srv >= 0 ? "GMT+" : "GMT") + I2S(srv) + "); range del minuto della notizia " +
        "(volte il normale) con correzione -2/-1/0/+1/+2 ore = " + F(sc[season * 5], 2) + " / " + F(sc[season * 5 + 1], 2) + " / " +
        F(sc[season * 5 + 2], 2) + " / " + F(sc[season * 5 + 3], 2) + " / " + F(sc[season * 5 + 4], 2) + "; applicato " + I2S(tot) + " ore.");
     }
   for(int i = 0; i < g_nN; i++)
      g_nT[i] = g_nT[i] + (ex[i] + (IsUSDST(g_nT[i]) ? g_offS : g_offW)) * 3600;
  }

//+------------------------------------------------------------------+
//| Swing: ogni movimento del prezzo, per timeframe (ZigZag ATR)      |
//+------------------------------------------------------------------+
string TopHours(const int k, const int typ)
  {
   double v[24];
   bool used[24];
   for(int h = 0; h < 24; h++)
     {
      v[h] = typ == 0 ? g_swH[k][h] : (typ == 1 ? g_swL[k][h] : g_swBig[k][h]);
      used[h] = false;
     }
   string out = "";
   for(int r = 0; r < 5; r++)
     {
      int bi = -1;
      for(int h = 0; h < 24; h++)
         if(!used[h] && MathIsValidNumber(v[h]) && (bi < 0 || v[h] > v[bi]))
            bi = h;
      if(bi < 0)
         break;
      used[bi] = true;
      out += (r > 0 ? ", " : "") + HourLab(bi) + " x" + F(v[bi], 2);
     }
   return out;
  }

void SwingTF(const int k, CSeries &s)
  {
   g_swOk[k] = false;
   for(int h = 0; h < 24; h++)
     {
      g_swH[k][h] = Nan();
      g_swL[k][h] = Nan();
      g_swBig[k][h] = Nan();
     }
   if(s.n < 200)
      return;
   double atr[];
   CalcATR(s, 14, atr);
   int pv[], pty[];
   int np = ZigZag(s, atr, InpSwingATR, pv, pty);
   if(np < 6)
      return;
   int nl = np - 1, nUp = 0;
   double ab[], sz[], su[], du[];
   ArrayResize(ab, nl); ArrayResize(sz, nl); ArrayResize(su, nl); ArrayResize(du, nl);
   for(int p = 0; p < nl; p++)
     {
      double p1 = pty[p] > 0 ? s.h[pv[p]] : s.l[pv[p]];
      double p2 = pty[p + 1] > 0 ? s.h[pv[p + 1]] : s.l[pv[p + 1]];
      ab[p] = MathAbs(p2 - p1);
      sz[p] = ab[p] / p1;
      su[p] = atr[pv[p]] > 0 ? ab[p] / atr[pv[p]] : 0;
      du[p] = (double)((long)s.t[pv[p + 1]] - (long)s.t[pv[p]]) / 3600.0;
      if(p2 > p1)
         nUp++;
     }
   int rb[4] = {0, 0, 0, 0};
   for(int p = 1; p < nl; p++)
     {
      if(ab[p - 1] <= 0)
         continue;
      double r = ab[p] / ab[p - 1];
      rb[r < 0.382 ? 0 : (r < 0.618 ? 1 : (r < 1.0 ? 2 : 3))]++;
     }
   int nr = rb[0] + rb[1] + rb[2] + rb[3];
   if(nr < 1)
      nr = 1;
   double ss[], sa[], sd[], ap[];
   Sorted(sz, nl, ss);
   Sorted(su, nl, sa);
   Sorted(du, nl, sd);
   ArrayResize(ap, s.n);
   for(int i = 0; i < s.n; i++)
      ap[i] = atr[i] / s.c[i];
   double atrMed = MedianOf(ap, s.n);
   ArrayFree(ap);
   //--- quando si formano le svolte: per ora, normalizzate per il numero di barre di quell'ora
   double bars[24], ph[24], pl[24], big[24], all[24];
   ArrayInitialize(bars, 0.0); ArrayInitialize(ph, 0.0); ArrayInitialize(pl, 0.0);
   ArrayInitialize(big, 0.0); ArrayInitialize(all, 0.0);
   for(int i = 0; i < s.n; i++)
      bars[HourOf(s.t[i])] += 1;
   int nH = 0;
   for(int p = 0; p < np; p++)
     {
      int hh = HourOf(s.t[pv[p]]);
      if(pty[p] > 0)
        {
         ph[hh] += 1;
         nH++;
        }
      else
         pl[hh] += 1;
     }
   int nLo = np - nH, nBig = 0;
   double thBig = Pct(sa, nl, 90);
   for(int p = 0; p < nl; p++)
     {
      int hh = HourOf(s.t[pv[p]]);
      all[hh] += 1;
      if(su[p] >= thBig)
        {
         big[hh] += 1;
         nBig++;
        }
     }
   for(int h = 0; h < 24; h++)
     {
      if(bars[h] >= 20 && nH > 0 && nLo > 0)
        {
         g_swH[k][h] = Dv(ph[h] / bars[h], (double)nH / s.n);
         g_swL[k][h] = Dv(pl[h] / bars[h], (double)nLo / s.n);
        }
      if(all[h] >= 10 && nBig > 0)
         g_swBig[k][h] = Dv(big[h] / all[h], (double)nBig / nl);
     }
   if(k == 4)
     {
      double db[7], dh[7], dl[7];
      ArrayInitialize(db, 0.0); ArrayInitialize(dh, 0.0); ArrayInitialize(dl, 0.0);
      for(int i = 0; i < s.n; i++)
         db[DowMon(s.t[i])] += 1;
      for(int p = 0; p < np; p++)
        {
         if(pty[p] > 0)
            dh[DowMon(s.t[pv[p]])] += 1;
         else
            dl[DowMon(s.t[pv[p]])] += 1;
        }
      for(int d = 0; d < 7; d++)
        {
         g_swDH[d] = db[d] >= 20 && nH > 0 ? Dv(dh[d] / db[d], (double)nH / s.n) : Nan();
         g_swDL[d] = db[d] >= 20 && nLo > 0 ? Dv(dl[d] / db[d], (double)nLo / s.n) : Nan();
        }
     }
   g_swOk[k] = true;
   int lp = pv[np - 1];
   double lastP = pty[np - 1] > 0 ? s.h[lp] : s.l[lp];
   double cur = s.c[s.n - 1];
   string curS = (pty[np - 1] > 0 ? "in discesa dal massimo " : "in salita dal minimo ") + PX(lastP) + " del " +
                 TimeToString(s.t[lp], TIME_DATE | TIME_MINUTES) + ": " + FP(MathAbs(cur - lastP) / lastP, 2) + "% (" +
                 F(Dv(MathAbs(cur - lastP), atr[s.n - 1]), 1) + " ATR)";
   double m50 = Pct(ss, nl, 50);
   g_swRows += "<tr>" + TD(EV_NAME[k]) + TD(FP(atrMed, 3) + "%") + TD(I2S(nl)) + TD(FP(m50, 3)) + TD(PX(m50 * g_last)) +
               TD(F(Pct(sa, nl, 50), 1)) + TD(FP(Pct(ss, nl, 90), 3)) + TD(DurLab(Pct(sd, nl, 50))) + TD(DurLab(Pct(sd, nl, 90))) +
               TD(FP((double)nUp / nl, 1)) + TD(FP((double)rb[0] / nr, 1)) + TD(FP((double)rb[1] / nr, 1)) +
               TD(FP((double)rb[2] / nr, 1)) + TD(FP((double)rb[3] / nr, 1)) + TD(curS) + "</tr>";
   R(g_repEv, "Swing " + EV_NAME[k] + " (ATR14 mediano " + FP(atrMed, 3) + "%): " + I2S(nl) + " swing, mediano " + FP(m50, 3) +
     "% (circa " + PX(m50 * g_last) + ", " + F(Pct(sa, nl, 50), 1) + " ATR), P90 " + FP(Pct(ss, nl, 90), 3) + "%, durata mediana " +
     DurLab(Pct(sd, nl, 50)) + " (P90 " + DurLab(Pct(sd, nl, 90)) + "). Lo swing successivo ritraccia: meno del 38.2% nel " +
     FP((double)rb[0] / nr, 1) + "%, 38.2-61.8% nel " + FP((double)rb[1] / nr, 1) + "%, 61.8-100% nel " + FP((double)rb[2] / nr, 1) +
     "%, oltre il 100% (supera l'origine: inversione) nel " + FP((double)rb[3] / nr, 1) + "%. Swing in corso: " + curS + ".");
   if(k < 4)
      R(g_repEv, "  Ore con pi&ugrave; massimi di swing del normale: " + TopHours(k, 0) + ". Minimi: " + TopHours(k, 1) +
        ". Partenze dei grandi swing (top 10%): " + TopHours(k, 2) + ".");
  }

void SwingTab(CSeries &a5, CSeries &a15, CSeries &a60, CSeries &a240, CSeries &aD)
  {
   g_swRows = "";
   R(g_repEv, "");
   R(g_repEv, "=== SWING: ogni movimento del prezzo (ZigZag: nuovo swing quando il prezzo inverte di almeno " + F(InpSwingATR, 1) +
     " x ATR14 del timeframe) ===");
   SwingTF(0, a5);
   SwingTF(1, a15);
   SwingTF(2, a60);
   SwingTF(3, a240);
   SwingTF(4, aD);
   SecStart("Swing: ogni movimento del prezzo, visto da ogni timeframe",
            "Uno swing finisce quando il prezzo inverte di almeno " + F(InpSwingATR, 1) + " volte l'ATR(14) di quel timeframe: " +
            "su M5 sono i movimenti intraday, su D1 quelli di settimane. Ritracciamento = quanto lo swing successivo torna indietro " +
            "rispetto al precedente; oltre il 100% supera il punto di partenza (inversione di tendenza).");
   THead("Timeframe|ATR14 mediano|N swing|Swing mediano %|&asymp; prezzo|In ATR|Swing P90 %|Durata mediana|Durata P90|% al rialzo|Ritraccia &lt;38.2%|38.2-61.8%|61.8-100%|&gt;100% (inversione)|Swing in corso");
   W(g_swRows);
   TEnd();
   SecEnd();
   SecStart("Quando si formano massimi e minimi di swing",
            "Per ogni ora del server: quante svolte si formano rispetto alla media (1.00 = normale, 1.50 = il 50% in pi&ugrave;), " +
            "gi&agrave; normalizzato per il numero di barre di quell'ora. 'Grandi swing' = quanto spesso gli swing pi&ugrave; ampi " +
            "(top 10%) partono a quell'ora rispetto alla media.");
   THead("Ora (orario dei dati)|M5 massimi|M5 minimi|M15 massimi|M15 minimi|H1 massimi|H1 minimi|H4 massimi|H4 minimi|Grandi swing M5|Grandi swing M15|Grandi swing H1");
   for(int h = 0; h < 24; h++)
     {
      bool any = false;
      for(int k = 0; k < 4; k++)
         if(MathIsValidNumber(g_swH[k][h]))
            any = true;
      if(!any)
         continue;
      string row = "<tr>" + TD(HourLab(h));
      for(int k = 0; k < 4; k++)
         row += TDc(F(g_swH[k][h], 2), PCol(g_swH[k][h], 1.0, 0.6)) + TDc(F(g_swL[k][h], 2), PCol(g_swL[k][h], 1.0, 0.6));
      for(int k = 0; k < 3; k++)
         row += TDc(F(g_swBig[k][h], 2), PCol(g_swBig[k][h], 1.0, 0.6));
      W(row + "</tr>");
     }
   TEnd();
   if(g_swOk[4])
     {
      W("<h3>D1: in quale giorno si formano massimi e minimi di swing</h3>");
      THead("Giorno|Massimi (x il normale)|Minimi (x il normale)");
      string sd = "";
      for(int d = 0; d < 7; d++)
        {
         if(!MathIsValidNumber(g_swDH[d]))
            continue;
         W("<tr>" + TD(DOW[d]) + TDc(F(g_swDH[d], 2), PCol(g_swDH[d], 1.0, 0.6)) + TDc(F(g_swDL[d], 2), PCol(g_swDL[d], 1.0, 0.6)) + "</tr>");
         sd += DOW[d] + " massimi x" + F(g_swDH[d], 2) + " minimi x" + F(g_swDL[d], 2) + "; ";
        }
      TEnd();
      R(g_repEv, "  D1 per giorno della settimana: " + sd);
     }
   SecEnd();
  }

//+------------------------------------------------------------------+
//| Rotture di massimi e minimi (ogni livello, ogni timeframe)        |
//+------------------------------------------------------------------+
void AddBo(int &bj[], int &bp[], double &bl[], bool &bh[], int &nb, const int j, const int p, const double lv, const bool hi)
  {
   nb++;
   ArrayResize(bj, nb, 65536);
   ArrayResize(bp, nb, 65536);
   ArrayResize(bl, nb, 65536);
   ArrayResize(bh, nb, 65536);
   bj[nb - 1] = j;
   bp[nb - 1] = p;
   bl[nb - 1] = lv;
   bh[nb - 1] = hi;
  }

// dalla chiusura della barra j: +1 se arriva prima a 'a' nella direzione dir, -1 se prima a 'a' contro, 0 nessuno o entrambi
int Race(CSeries &s, const int j, const int dir, const double a, const int L)
  {
   if(!(a > 0))
      return 0;
   double tgt = s.c[j] + dir * a, stp = s.c[j] - dir * a;
   int end = j + L < s.n - 1 ? j + L : s.n - 1;
   for(int q = j + 1; q <= end; q++)
     {
      bool hs = dir > 0 ? s.l[q] <= stp : s.h[q] >= stp;
      bool ht = dir > 0 ? s.h[q] >= tgt : s.l[q] <= tgt;
      if(hs && ht)
         return 0;
      if(hs)
         return -1;
      if(ht)
         return 1;
     }
   return 0;
  }

string BoCells(const bool &m[], string &txt)
  {
   int n = 0, cl = 0, f = 0, cu = 0, rv = 0, still = 0, ne = 0;
   double ex[], ho[];
   ArrayResize(ex, g_boN);
   ArrayResize(ho, g_boN);
   for(int e = 0; e < g_boN; e++)
     {
      if(!m[e])
         continue;
      ho[n] = g_boHold[e];
      n++;
      if(g_boCl[e])
         cl++;
      if(g_boF[e])
         f++;
      if(g_boRc[e] > 0)
         cu++;
      if(g_boRc[e] < 0)
         rv++;
      if(g_boHold[e] > g_boLook)
         still++;
      if(MathIsValidNumber(g_boExc[e]))
         ex[ne++] = g_boExc[e];
     }
   txt = "";
   if(n < 5)
      return "";
   double fp = (double)f / n, cp = (double)cu / n, rp = (double)rv / n, mEx = MedianOf(ex, ne), mHo = MedianOf(ho, n);
   string hoS = mHo > g_boLook ? "&gt;" + I2S(g_boLook) : F(mHo, 0);
   txt = " (N " + I2S(n) + "): chiude oltre il livello " + FP((double)cl / n, 1) + "%, false " + FP(fp, 1) + "%, prosegue di 1 ATR per prima " +
         FP(cp, 1) + "%, torna indietro di 1 ATR per prima " + FP(rp, 1) + "%, escursione mediana " + F(mEx, 2) + " ATR, tenuta mediana " + hoS +
         " barre, ancora oltre dopo " + I2S(g_boLook) + " barre " + FP((double)still / n, 1) + "%";
   return TD(I2S(n)) + TD(FP((double)cl / n, 1)) + TDc(FP(fp, 1), PCol(-fp, -g_boBase, 0.15)) + TDc(FP(cp, 1), PCol(cp, rp, 0.15)) +
          TD(FP(rp, 1)) + TD(F(mEx, 2)) + TD(hoS) + TD(FP((double)still / n, 1));
  }

void BoLine(const string label, const bool &m[])
  {
   string tx;
   string c = BoCells(m, tx);
   if(c == "")
      return;
   W("<tr>" + TD(label) + c + "</tr>");
   R(g_repEv, "    " + label + tx);
  }

void BoGrp(const string title)
  {
   Grp(title, 9);
   R(g_repEv, "  [" + title + "]");
  }

void BreakTF(const int k, CSeries &s)
  {
   g_boN = 0;
   int n = s.n, N = InpPivotBars, L = InpLookBars;
   g_boLook = L;
   if(n < 200 || N < 1)
      return;
   double atr[], atrL[], adx[];
   CalcATR(s, 14, atr);
   CalcATR(s, 100, atrL);
   CalcADX(s, 14, adx);
   double rvb[];
   CalcRVOL(s, EV_SEC[k], 20, rvb);
   //--- livelli ancora intatti: pila ordinata (in cima il massimo piu' basso / il minimo piu' alto)
   double hsL[], lsL[];
   int hsI[], lsI[];
   ArrayResize(hsL, n); ArrayResize(hsI, n); ArrayResize(lsL, n); ArrayResize(lsI, n);
   int th = 0, tl = 0, nb = 0;
   int bj[], bp[];
   double bl[];
   bool bh[];
   for(int j = 0; j < n; j++)
     {
      while(th > 0 && hsL[th - 1] < s.h[j])
        {
         th--;
         AddBo(bj, bp, bl, bh, nb, j, hsI[th], hsL[th], true);
        }
      while(tl > 0 && lsL[tl - 1] > s.l[j])
        {
         tl--;
         AddBo(bj, bp, bl, bh, nb, j, lsI[tl], lsL[tl], false);
        }
      int p = j - N;
      if(p < N)
         continue;
      bool fh = true, fl = true;
      for(int q = 1; q <= N; q++)
        {
         if(!(s.h[p] > s.h[p - q] && s.h[p] >= s.h[p + q]))
            fh = false;
         if(!(s.l[p] < s.l[p - q] && s.l[p] <= s.l[p + q]))
            fl = false;
        }
      if(fh)
        {
         hsL[th] = s.h[p];
         hsI[th] = p;
         th++;
        }
      if(fl)
        {
         lsL[tl] = s.l[p];
         lsI[tl] = p;
         tl++;
        }
     }
   g_boN = nb;
   ArrayResize(g_boHi, nb); ArrayResize(g_boCl, nb); ArrayResize(g_boF, nb); ArrayResize(g_boRc, nb); ArrayResize(g_boRv, nb);
   ArrayResize(g_boNw, nb); ArrayResize(g_boHold, nb); ArrayResize(g_boAge, nb); ArrayResize(g_boHr, nb); ArrayResize(g_boDw, nb);
   ArrayResize(g_boExc, nb); ArrayResize(g_boAdx, nb); ArrayResize(g_boVr, nb);
   int fAll = 0;
   for(int e = 0; e < nb; e++)
     {
      int j = bj[e];
      double lv = bl[e];
      bool hi = bh[e];
      int end = j + L < n - 1 ? j + L : n - 1;
      int back = -1;
      double ex = 0;
      for(int q = j; q <= end && back < 0; q++)
        {
         double x = hi ? s.h[q] - lv : lv - s.l[q];
         if(x > ex)
            ex = x;
         if(hi ? s.c[q] <= lv : s.c[q] >= lv)
            back = q;  // richiude dentro il livello
        }
      g_boHi[e] = hi;
      g_boCl[e] = hi ? s.c[j] > lv : s.c[j] < lv;
      g_boHold[e] = back < 0 ? L + 1 : back - j;
      g_boExc[e] = Dv(ex, atr[j]);
      g_boF[e] = back >= 0 && back - j <= InpFalseBars && g_boExc[e] < 1.0;
      g_boRc[e] = Race(s, j, hi ? 1 : -1, atr[j], L);
      g_boRv[e] = rvb[j];
      g_boAge[e] = j - bp[e];
      g_boHr[e] = HourOf(s.t[j]);
      g_boDw[e] = DowMon(s.t[j]);
      g_boAdx[e] = adx[j];
      g_boVr[e] = Dv(atr[j], atrL[j]);
      g_boNw[e] = k <= 2 && NewsNear(s.t[j] - 900, s.t[j] + EV_SEC[k]) >= 0;
      if(g_boF[e])
         fAll++;
     }
   if(nb < 20)
      return;
   g_boBase = (double)fAll / nb;
   bool m[];
   ArrayResize(m, nb);
   string tx;
   for(int e = 0; e < nb; e++)
      m[e] = true;
   string sum = BoCells(m, tx);
   g_boRows += "<tr>" + TD(EV_NAME[k]) + sum + "</tr>";
   SecStart("Rotture su " + EV_NAME[k], "Ogni massimo e minimo " + EV_NAME[k] + " (" + I2S(N) + " barre a sinistra e a destra) seguito fino a quando " +
            "il prezzo lo supera. Colore di '% false': rosso = pi&ugrave; false della media di questo timeframe (" + FP(g_boBase, 1) + "%), blu = meno. " +
            "Colore di '% prosegue': blu = prosegue pi&ugrave; spesso di quanto torni indietro.");
   THead("Condizione|N|% chiude oltre|% false|% prosegue 1 ATR per prima|% torna indietro 1 ATR per prima|Escursione mediana (ATR)|Tenuta mediana (barre)|% ancora oltre dopo " + I2S(L) + " barre");
   R(g_repEv, "Rotture " + EV_NAME[k] + " (media false " + FP(g_boBase, 1) + "%):");
   BoLine("Tutte le rotture", m);
   BoGrp("Barra che rompe il livello");
   for(int e = 0; e < nb; e++)
      m[e] = g_boCl[e];
   BoLine("chiude oltre il livello", m);
   for(int e = 0; e < nb; e++)
      m[e] = !g_boCl[e];
   BoLine("rompe solo con l'ombra e richiude dentro", m);
   BoGrp("Tipo di livello");
   for(int e = 0; e < nb; e++)
      m[e] = g_boHi[e];
   BoLine("rottura di un massimo (al rialzo)", m);
   for(int e = 0; e < nb; e++)
      m[e] = !g_boHi[e];
   BoLine("rottura di un minimo (al ribasso)", m);
   BoGrp("Et&agrave; del livello (barre " + EV_NAME[k] + " tra il massimo/minimo e la rottura)");
   int ag[5] = {0, 10, 50, 200, 2000000000};
   string al[4] = {"meno di 10 barre", "10-49 barre", "50-199 barre", "200 barre e oltre"};
   for(int z = 0; z < 4; z++)
     {
      for(int e = 0; e < nb; e++)
         m[e] = g_boAge[e] >= ag[z] && g_boAge[e] < ag[z + 1];
      BoLine(al[z], m);
     }
   BoGrp("Forza del trend al momento della rottura: ADX(14)");
   for(int e = 0; e < nb; e++)
      m[e] = g_boAdx[e] < 20;
   BoLine("ADX sotto 20 (laterale)", m);
   for(int e = 0; e < nb; e++)
      m[e] = g_boAdx[e] >= 20 && g_boAdx[e] <= 30;
   BoLine("ADX 20-30", m);
   for(int e = 0; e < nb; e++)
      m[e] = g_boAdx[e] > 30;
   BoLine("ADX sopra 30 (trend forte)", m);
   BoGrp("Volatilit&agrave; al momento della rottura: ATR14 / ATR100");
   for(int e = 0; e < nb; e++)
      m[e] = g_boVr[e] < 0.8;
   BoLine("sotto 0.8 (compressione)", m);
   for(int e = 0; e < nb; e++)
      m[e] = g_boVr[e] >= 0.8 && g_boVr[e] <= 1.2;
   BoLine("0.8-1.2 (normale)", m);
   for(int e = 0; e < nb; e++)
      m[e] = g_boVr[e] > 1.2;
   BoLine("sopra 1.2 (espansione)", m);
   if(s.hasVol)
     {
      BoGrp("Volume della barra di rottura rispetto alla stessa fascia oraria dei 20 giorni precedenti (RVOL)");
      double rl[5] = {0, 0.8, 1.5, 2.5, 1e18};
      string rn[4] = {"RVOL sotto 0.8 (volume basso)", "RVOL 0.8-1.5 (normale)", "RVOL 1.5-2.5 (alto)", "RVOL oltre 2.5 (molto alto)"};
      for(int z = 0; z < 4; z++)
        {
         for(int e = 0; e < nb; e++)
            m[e] = MathIsValidNumber(g_boRv[e]) && g_boRv[e] >= rl[z] && g_boRv[e] < rl[z + 1];
         BoLine(rn[z], m);
        }
     }
   if(k <= 2 && g_nN > 0)
     {
      BoGrp("Notizie (" + NewsCurStr() + " nei 15 minuti prima o durante la barra di rottura)");
      for(int e = 0; e < nb; e++)
         m[e] = g_boNw[e];
      BoLine("con notizia", m);
      for(int e = 0; e < nb; e++)
         m[e] = !g_boNw[e];
      BoLine("senza notizia", m);
     }
   if(k <= 3)
     {
      BoGrp("Ora della rottura (orario dei dati)");
      for(int h = 0; h < 24; h++)
        {
         for(int e = 0; e < nb; e++)
            m[e] = g_boHr[e] == h;
         BoLine(HourLab(h), m);
        }
     }
   else
     {
      BoGrp("Giorno della rottura");
      for(int d = 0; d < 7; d++)
        {
         for(int e = 0; e < nb; e++)
            m[e] = g_boDw[e] == d;
         BoLine(DOW[d], m);
        }
     }
   TEnd();
   SecEnd();
  }

void BreakTab(CSeries &a5, CSeries &a15, CSeries &a60, CSeries &a240, CSeries &aD)
  {
   g_boRows = "";
   R(g_repEv, "");
   R(g_repEv, "=== ROTTURE di ogni massimo e minimo (massimo/minimo = barra pi&ugrave; alta/bassa delle " + I2S(InpPivotBars) +
     " barre a sinistra e a destra; falsa = richiude dentro entro " + I2S(InpFalseBars) + " barre senza allontanarsi di 1 ATR; " +
     "prosegue / torna indietro = dalla chiusura della barra di rottura arriva prima +1 ATR nella direzione della rottura oppure -1 ATR " +
     "contro (misura simmetrica: senza tendenza sarebbe circa 50 e 50; il resto = nessuno dei due entro " + I2S(InpLookBars) + " barre); " +
     "tenuta = barre prima di richiudere dentro) ===");
   g_buf = true;
   g_bufS = "";
   BreakTF(0, a5);
   BreakTF(1, a15);
   BreakTF(2, a60);
   BreakTF(3, a240);
   BreakTF(4, aD);
   g_buf = false;
   SecStart("Rotture di massimi e minimi: confronto fra timeframe",
            "Ogni massimo e minimo che si forma, a qualsiasi ora, viene seguito finch&eacute; il prezzo lo rompe. <b>Falsa</b> = richiude " +
            "dentro il livello entro " + I2S(InpFalseBars) + " barre senza essersi allontanata di 1 ATR. <b>Prosegue / torna indietro</b> = " +
            "dalla chiusura della barra di rottura, cosa arriva prima: +1 ATR nella direzione della rottura o -1 ATR contro. &Egrave; una " +
            "misura simmetrica (senza tendenza sarebbe circa 50 e 50); il resto sono i casi in cui nessuno dei due arriva entro " +
            I2S(InpLookBars) + " barre. <b>Tenuta</b> = barre in cui resta oltre il livello prima di richiudere dentro. " +
            "<b>RVOL</b> = volume della barra diviso la media delle barre alla stessa ora dei 20 giorni precedenti.");
   THead("Timeframe|N|% chiude oltre|% false|% prosegue 1 ATR per prima|% torna indietro 1 ATR per prima|Escursione mediana (ATR)|Tenuta mediana (barre)|% ancora oltre dopo " + I2S(InpLookBars) + " barre");
   W(g_boRows);
   TEnd();
   SecEnd();
   W(g_bufS);
   g_bufS = "";
  }

//+------------------------------------------------------------------+
//| Impulsi: i movimenti piu' violenti, quando e perche'              |
//+------------------------------------------------------------------+
double Follow(CSeries &s, const int i, const int hb, const int barSec, const double r)
  {
   int e = i + hb;
   if(e >= s.n || (long)s.t[e] - (long)s.t[i] > (long)(hb + 5) * barSec || r == 0)
      return Nan();
   return (r > 0 ? 1.0 : -1.0) * (s.c[e] / s.c[i] - 1) / MathAbs(r);
  }

string MostNews(const bool &m[])
  {
   string best = "";
   int bc = 0;
   for(int e = 0; e < g_imN; e++)
     {
      if(!m[e] || g_imNw[e] < 0)
         continue;
      string nm = g_nName[g_imNw[e]];
      if(nm == best)
         continue;
      int c = 0;
      for(int e2 = 0; e2 < g_imN; e2++)
         if(m[e2] && g_imNw[e2] >= 0 && g_nName[g_imNw[e2]] == nm)
            c++;
      if(c > bc)
        {
         bc = c;
         best = nm;
        }
     }
   return best == "" ? "-" : best + " (" + I2S(bc) + ")";
  }

void ImpLine(const string label, const bool &m[], const bool withNews)
  {
   int n = 0, nn = 0, k15 = 0, n15 = 0, k60 = 0, n60 = 0, nr = 0;
   double a[], b[];
   ArrayResize(a, g_imN);
   ArrayResize(b, g_imN);
   for(int e = 0; e < g_imN; e++)
     {
      if(!m[e])
         continue;
      a[n++] = g_imSz[e];
      if(g_imNw[e] >= 0)
         nn++;
      if(MathIsValidNumber(g_imC15[e]))
        {
         n15++;
         if(g_imC15[e] > 0)
            k15++;
        }
      if(MathIsValidNumber(g_imC60[e]))
        {
         n60++;
         if(g_imC60[e] > 0)
            k60++;
        }
      if(MathIsValidNumber(g_imRt[e]))
         b[nr++] = g_imRt[e];
     }
   if(n < 3)
      return;
   double med = MedianOf(a, n);
   double p15 = n15 > 0 ? (double)k15 / n15 : Nan(), p60 = n60 > 0 ? (double)k60 / n60 : Nan();
   double rtm = nr > 0 ? MedianOf(b, nr) : Nan();
   string mn = withNews ? MostNews(m) : "";
   W("<tr>" + TD(label) + TD(I2S(n)) + TD(FP((double)n / g_imN, 1)) + TD(FP(med, 3)) + TD(PX(med * g_last)) +
     TD(FP((double)nn / n, 1)) + TDc(FP(p15, 1), PCol(p15, 0.5, 0.15)) + TDc(FP(p60, 1), PCol(p60, 0.5, 0.15)) +
     TDc(F(rtm, 2), PCol(-rtm, -0.5, 0.4)) + (withNews ? TD(mn) : "") + "</tr>");
   R(g_repEv, "    " + label + ": N " + I2S(n) + " (" + FP((double)n / g_imN, 1) + "% degli impulsi), dimensione mediana " + FP(med, 3) +
     "% (circa " + PX(med * g_last) + "), con notizia " + FP((double)nn / n, 1) + "%, continua dopo 15 min " + FP(p15, 1) +
     "%, dopo 60 min " + FP(p60, 1) + "%, rientro mediano entro 60 min " + F(rtm, 2) + (withNews ? ", notizia pi&ugrave; frequente " + mn : ""));
  }

void ImpulseWindow(CSeries &s, const int w, const int barSec, const int mins)
  {
   int n = s.n;
   double z[];
   ArrayResize(z, n);
   double ew = 0, al = 2.0 / 10001.0;
   bool init = false;
   int nz = 0;
   for(int i = 0; i < n; i++)
     {
      z[i] = -1;
      if(i < w || (long)s.t[i] - (long)s.t[i - w] > (long)(w + 2) * barSec)
         continue;
      double a = MathAbs(s.c[i] / s.c[i - w] - 1);
      if(init && ew > 0)
        {
         z[i] = a / ew;
         nz++;
        }
      ew = init ? al * a + (1 - al) * ew : a;
      init = true;
     }
   if(nz < 1000)
      return;
   double tmp[];
   ArrayResize(tmp, nz);
   int q = 0;
   for(int i = 0; i < n; i++)
      if(z[i] >= 0)
         tmp[q++] = z[i];
   ArraySort(tmp);
   double Q = Pct(tmp, q, InpImpulsePct);
   ArrayFree(tmp);
   int ev[];
   int ne = 0, last = -1000000;
   for(int i = 0; i < n; i++)  // l'impulso parte dalla PRIMA barra oltre la soglia: le successive vicine sono lo stesso impulso
     {
      if(z[i] < Q)
         continue;
      if(i - last <= w)
        {
         last = i;
         continue;
        }
      last = i;
      ne++;
      ArrayResize(ev, ne, 8192);
      ev[ne - 1] = i;
     }
   ArrayFree(z);
   if(ne < 20)
      return;
   g_imN = ne;
   ArrayResize(g_imSz, ne); ArrayResize(g_imC15, ne); ArrayResize(g_imC60, ne); ArrayResize(g_imRt, ne);
   ArrayResize(g_imNw, ne); ArrayResize(g_imHr, ne); ArrayResize(g_imMd, ne); ArrayResize(g_imDw, ne); ArrayResize(g_imYr, ne);
   ArrayResize(g_imUp, ne); ArrayResize(g_imRv, ne);
   bool rvOk = ArraySize(g_rvM) == n;
   int h15 = 15 * 60 / barSec, h60 = 60 * 60 / barSec;
   for(int e = 0; e < ne; e++)
     {
      int i = ev[e], st = i - w + 1;
      double r = s.c[i] / s.c[i - w] - 1;
      g_imSz[e] = MathAbs(r);
      g_imUp[e] = r > 0;
      g_imHr[e] = HourOf(s.t[st]);
      g_imMd[e] = MinOfDay(s.t[st]);
      g_imDw[e] = DowMon(s.t[st]);
      MqlDateTime d;
      TimeToStruct(s.t[st], d);
      g_imYr[e] = d.year;
      g_imNw[e] = NewsNear(s.t[i - w] - 300, s.t[i] + barSec);
      g_imC15[e] = Follow(s, i, h15, barSec, r);
      g_imC60[e] = Follow(s, i, h60, barSec, r);
      double base = MathAbs(s.c[i] - s.c[i - w]);
      double mn = s.c[i], mx = s.c[i];
      for(int kk = i + 1; kk <= i + h60 && kk < n; kk++)
        {
         if((long)s.t[kk] - (long)s.t[i] > (long)(h60 + 5) * barSec)
            break;
         if(s.l[kk] < mn)
            mn = s.l[kk];
         if(s.h[kk] > mx)
            mx = s.h[kk];
        }
      g_imRt[e] = base > 0 ? (g_imUp[e] ? s.c[i] - mn : mx - s.c[i]) / base : Nan();
      double rs = 0;
      int rc = 0;
      for(int kk = st; kk <= i && rvOk; kk++)
         if(MathIsValidNumber(g_rvM[kk]))
           {
            rs += g_rvM[kk];
            rc++;
           }
      g_imRv[e] = rc > 0 ? rs / rc : Nan();
     }
   string wl = I2S(mins) + (mins == 1 ? " minuto" : " minuti");
   SecStart("Impulsi di " + wl,
            "Impulso = movimento in " + wl + " almeno " + F(Q, 1) + " volte il movimento normale del momento (media degli ultimi ~10.000 " +
            "periodi): &egrave; lo " + F(100 - InpImpulsePct, 1) + "% dei movimenti pi&ugrave; forti. " + I2S(ne) + " impulsi. " +
            "Ogni impulso &egrave; misurato dalla <b>prima</b> barra che supera la soglia (le barre oltre soglia subito dopo fanno parte " +
            "dello stesso impulso): nessuna scelta a posteriori del punto migliore. " +
            "<b>Continua</b> = dopo 15/60 minuti il prezzo &egrave; oltre la chiusura dell'impulso nella sua direzione. <b>Rientro</b> = " +
            "quanto dell'impulso viene restituito entro 60 minuti (1.00 = tutto).");
   THead("Condizione|N|% degli impulsi|Dimensione mediana %|&asymp; prezzo|% con notizia|% continua dopo 15 min|% continua dopo 60 min|Rientro mediano entro 60 min");
   R(g_repEv, "Impulsi di " + wl + ": soglia " + F(Q, 1) + " volte il movimento normale, " + I2S(ne) + " impulsi.");
   bool m[];
   ArrayResize(m, ne);
   for(int e = 0; e < ne; e++)
      m[e] = true;
   ImpLine("Tutti", m, false);
   if(g_nN > 0)
     {
      Grp("Notizie", 9);
      R(g_repEv, "  [Notizie]");
      for(int e = 0; e < ne; e++)
         m[e] = g_imNw[e] >= 0;
      ImpLine("con notizia " + NewsCurStr() + " (da 5 min prima)", m, false);
      for(int e = 0; e < ne; e++)
         m[e] = g_imNw[e] < 0;
      ImpLine("senza notizia", m, false);
     }
   Grp("Direzione", 9);
   R(g_repEv, "  [Direzione]");
   for(int e = 0; e < ne; e++)
      m[e] = g_imUp[e];
   ImpLine("al rialzo", m, false);
   for(int e = 0; e < ne; e++)
      m[e] = !g_imUp[e];
   ImpLine("al ribasso", m, false);
   if(rvOk)
     {
      Grp("Volume delle barre dell'impulso rispetto alla stessa ora dei 20 giorni precedenti (RVOL)", 9);
      R(g_repEv, "  [RVOL]");
      double rl[4] = {0, 1.5, 3.0, 1e18};
      string rn[3] = {"RVOL sotto 1.5", "RVOL 1.5-3", "RVOL oltre 3"};
      for(int zz = 0; zz < 3; zz++)
        {
         for(int e = 0; e < ne; e++)
            m[e] = MathIsValidNumber(g_imRv[e]) && g_imRv[e] >= rl[zz] && g_imRv[e] < rl[zz + 1];
         ImpLine(rn[zz], m, false);
        }
     }
   Grp("Ora di inizio (orario dei dati)", 9);
   R(g_repEv, "  [Ora di inizio]");
   for(int h = 0; h < 24; h++)
     {
      for(int e = 0; e < ne; e++)
         m[e] = g_imHr[e] == h;
      ImpLine(HourLab(h), m, false);
     }
   Grp("Giorno", 9);
   R(g_repEv, "  [Giorno]");
   for(int d = 0; d < 7; d++)
     {
      for(int e = 0; e < ne; e++)
         m[e] = g_imDw[e] == d;
      ImpLine(DOW[d], m, false);
     }
   Grp("Anno", 9);
   R(g_repEv, "  [Anno]");
   for(int y = g_imYr[0]; y <= g_imYr[ne - 1]; y++)
     {
      for(int e = 0; e < ne; e++)
         m[e] = g_imYr[e] == y;
      ImpLine(I2S(y), m, false);
     }
   TEnd();
   //--- orari esatti
   int cnt[1440];
   bool used[1440];
   for(int z2 = 0; z2 < 1440; z2++)
     {
      cnt[z2] = 0;
      used[z2] = false;
     }
   for(int e = 0; e < ne; e++)
      cnt[g_imMd[e]]++;
   W("<h3>Gli orari esatti in cui partono pi&ugrave; impulsi</h3>");
   THead("Orario (orario dei dati)|N|% degli impulsi|Dimensione mediana %|&asymp; prezzo|% con notizia|% continua dopo 15 min|% continua dopo 60 min|Rientro mediano entro 60 min|Notizia pi&ugrave; frequente");
   R(g_repEv, "  [Orari esatti pi&ugrave; frequenti]");
   for(int r = 0; r < 20; r++)
     {
      int bi = -1;
      for(int z2 = 0; z2 < 1440; z2++)
         if(!used[z2] && (bi < 0 || cnt[z2] > cnt[bi]))
            bi = z2;
      if(bi < 0 || cnt[bi] < 3)
         break;
      used[bi] = true;
      for(int e = 0; e < ne; e++)
         m[e] = g_imMd[e] == bi;
      ImpLine(SlotLab(bi), m, g_nN > 0);
     }
   TEnd();
   SecEnd();
  }

void ImpulseTab(CSeries &s, const int barSec)
  {
   R(g_repEv, "");
   R(g_repEv, "=== IMPULSI: i movimenti pi&ugrave; violenti (lo " + F(100 - InpImpulsePct, 1) + "% pi&ugrave; forte rispetto al movimento normale del momento) ===");
   if(s.n < 5000)
     {
      SecStart("Impulsi", "");
      W("<p class='muted'>Servono dati M1 o M5.</p>");
      SecEnd();
      return;
     }
   CalcRVOL(s, barSec, 20, g_rvM);
   if(!s.hasVol)
      ArrayResize(g_rvM, 0);
   int mins[3] = {1, 5, 15};
   for(int z = 0; z < 3; z++)
     {
      int w = mins[z] * 60 / barSec;
      if(w >= 1)
         ImpulseWindow(s, w, barSec, mins[z]);
     }
   ArrayFree(g_rvM);
  }

//+------------------------------------------------------------------+
//| Notizie: come reagisce il prezzo a ogni tipo di notizia           |
//+------------------------------------------------------------------+
void NewsTab(CSeries &s)
  {
   R(g_repEv, "");
   R(g_repEv, "=== NOTIZIE (calendario economico MT5, valuta " + NewsCurStr() + ", importanza minima " + I2S(InpNewsMinImp) + ") ===");
   R(g_repEv, g_nInfo);
   SecStart("Notizie: allineamento tra orari dei dati e calendario",
            "MT5 salva lo storico del calendario con il fuso <b>attuale</b> del server: nei mesi con l'altro orario (legale o solare) " +
            "le notizie risultano spostate di un'ora. Lo spostamento atteso si calcola dal fuso dei dati (" + TZName() + ") e dal fuso " +
            "attuale del server. Attorno a quello si misura quanto &egrave; ampio il minuto delle notizie importanti con una correzione " +
            "di -2&hellip;+2 ore: se una colonna supera 1.5 volte il normale ed &egrave; la pi&ugrave; alta, quella correzione viene " +
            "applicata a tutte le analisi con notizie.");
   if(g_alignRows != "")
     {
      THead("Periodo|Spostamento atteso|Correzione -2 ore|-1 ora|0|+1 ora|+2 ore|Spostamento applicato");
      W(g_alignRows);
      TEnd();
     }
   W("<p class='muted'>" + g_nInfo + "</p>");
   SecEnd();
   if(g_nN == 0 || s.n < 5000)
      return;
   int nN = g_nN;
   double r1[], r5[], r15[], r60[], r560[], rg[];
   bool ok[];
   int sl[];
   ArrayResize(r1, nN); ArrayResize(r5, nN); ArrayResize(r15, nN); ArrayResize(r60, nN); ArrayResize(r560, nN); ArrayResize(rg, nN);
   ArrayResize(ok, nN); ArrayResize(sl, nN);
   for(int i = 0; i < nN; i++)
     {
      ok[i] = false;
      datetime T = g_nT[i];
      int k = LowerBound(s.t, s.n, T);
      if(k <= 0 || k + 59 >= s.n)
         continue;
      if((long)s.t[k] - (long)T >= 120 || (long)s.t[k + 59] - (long)s.t[k] > 65 * 60)
         continue;
      double pre = s.c[k - 1];
      r1[i] = s.c[k] / pre - 1;
      r5[i] = s.c[k + 4] / pre - 1;
      r15[i] = s.c[k + 14] / pre - 1;
      r60[i] = s.c[k + 59] / pre - 1;
      r560[i] = s.c[k + 59] / s.c[k + 4] - 1;  // tratto 5-60 min, separato dai primi 5
      double hh = s.h[k], ll = s.l[k];
      for(int j = k; j <= k + 59; j++)
        {
         if(s.h[j] > hh)
            hh = s.h[j];
         if(s.l[j] < ll)
            ll = s.l[j];
        }
      rg[i] = (hh - ll) / pre;
      sl[i] = MinOfDay(T);
      ok[i] = true;
     }
   //--- riferimento: stesso orario nei giorni senza notizie
   int slots[];
   int ns = 0;
   for(int i = 0; i < nN; i++)
     {
      if(!ok[i])
         continue;
      bool f = false;
      for(int z = 0; z < ns; z++)
         if(slots[z] == sl[i])
           {
            f = true;
            break;
           }
      if(!f)
        {
         ns++;
         ArrayResize(slots, ns);
         slots[ns - 1] = sl[i];
        }
     }
   for(int a = 1; a < ns; a++)  // ordina gli orari
     {
      int v = slots[a], b = a - 1;
      while(b >= 0 && slots[b] > v)
        {
         slots[b + 1] = slots[b];
         b--;
        }
      slots[b + 1] = v;
     }
   double base[];
   ArrayResize(base, ns);
   long d0 = (long)s.t[0] / 86400, d1 = (long)s.t[s.n - 1] / 86400;
   double tmp[];
   ArrayResize(tmp, (int)(d1 - d0 + 2));
   for(int z = 0; z < ns; z++)
     {
      int q = 0;
      for(long d = d0; d <= d1; d++)
        {
         datetime Ts = (datetime)(d * 86400 + (long)slots[z] * 60);
         if(NewsNear(Ts - 5400, Ts + 5400) >= 0)
            continue;
         int k = LowerBound(s.t, s.n, Ts);
         if(k <= 0 || k + 59 >= s.n || s.t[k] != Ts || (long)s.t[k + 59] - (long)s.t[k] > 65 * 60)
            continue;
         double hh = s.h[k], ll = s.l[k];
         for(int j = k; j <= k + 59; j++)
           {
            if(s.h[j] > hh)
               hh = s.h[j];
            if(s.l[j] < ll)
               ll = s.l[j];
           }
         tmp[q++] = (hh - ll) / s.c[k - 1];
        }
      base[z] = q >= 20 ? MedianOf(tmp, q) : Nan();
     }
   //--- per notizia
   string nm[];
   int nc[];
   int nn = 0;
   for(int i = 0; i < nN; i++)
     {
      if(!ok[i])
         continue;
      int f = -1;
      for(int z = 0; z < nn; z++)
         if(nm[z] == g_nName[i])
           {
            f = z;
            break;
           }
      if(f < 0)
        {
         nn++;
         ArrayResize(nm, nn);
         ArrayResize(nc, nn);
         nm[nn - 1] = g_nName[i];
         nc[nn - 1] = 0;
         f = nn - 1;
        }
      nc[f]++;
     }
   SecStart("Reazione del prezzo per notizia",
            "Notizie con almeno 5 uscite, ordinate per impatto (range dei 60 minuti rispetto allo stesso orario nei giorni senza " +
            "notizie). Movimento mediano (in valore assoluto) dopo 1, 5, 15 e 60 minuti dall'uscita; quante volte i minuti 5-60 " +
            "proseguono la direzione dei primi 5 minuti (tratti separati: senza legame sarebbe circa 50%); direzione a 60 minuti " +
            "quando il dato esce sopra o sotto le attese.");
   THead("Notizia|N|Mossa 1 min %|5 min %|15 min %|60 min %|Range 60 min %|&asymp; prezzo|vs stessa ora senza notizie|% i minuti 5-60 proseguono i primi 5|Sopra le attese: % rialzo a 60 min|Sotto le attese: % rialzo a 60 min");
   R(g_repEv, "  [Per notizia, ordinate per impatto]");
   string rowS[], repS[];
   double scr[];
   int nr = 0;
   for(int bi = 0; bi < nn; bi++)
     {
      if(nc[bi] < 5)
         continue;
      double a1[], a5[], a15[], a60[], ag[], ar[];
      ArrayResize(a1, nc[bi]); ArrayResize(a5, nc[bi]); ArrayResize(a15, nc[bi]); ArrayResize(a60, nc[bi]);
      ArrayResize(ag, nc[bi]); ArrayResize(ar, nc[bi]);
      int q = 0, qr = 0, hold = 0, holdN = 0, abN = 0, abU = 0, beN = 0, beU = 0;
      for(int i = 0; i < nN; i++)
        {
         if(!ok[i] || g_nName[i] != nm[bi])
            continue;
         a1[q] = MathAbs(r1[i]);
         a5[q] = MathAbs(r5[i]);
         a15[q] = MathAbs(r15[i]);
         a60[q] = MathAbs(r60[i]);
         ag[q] = rg[i];
         q++;
         for(int z = 0; z < ns; z++)
            if(slots[z] == sl[i])
              {
               if(MathIsValidNumber(base[z]) && base[z] > 0)
                  ar[qr++] = rg[i] / base[z];
               break;
              }
         if(r5[i] != 0 && r560[i] != 0)
           {
            holdN++;
            if((r5[i] > 0) == (r560[i] > 0))
               hold++;
           }
         if(MathIsValidNumber(g_nAct[i]) && MathIsValidNumber(g_nFc[i]) && g_nAct[i] != g_nFc[i])
           {
            if(g_nAct[i] > g_nFc[i])
              {
               abN++;
               if(r60[i] > 0)
                  abU++;
              }
            else
              {
               beN++;
               if(r60[i] > 0)
                  beU++;
              }
           }
        }
      if(q < 5)
         continue;
      double mg = MedianOf(ag, q), mr = qr >= 3 ? MedianOf(ar, qr) : Nan();
      double ph = holdN > 0 ? (double)hold / holdN : Nan();
      string sa = abN >= 3 ? FP((double)abU / abN, 0) + "% (" + I2S(abN) + ")" : "-";
      string sb = beN >= 3 ? FP((double)beU / beN, 0) + "% (" + I2S(beN) + ")" : "-";
      nr++;
      ArrayResize(rowS, nr);
      ArrayResize(repS, nr);
      ArrayResize(scr, nr);
      rowS[nr - 1] = "<tr>" + TD(nm[bi]) + TD(I2S(q)) + TD(FP(MedianOf(a1, q), 3)) + TD(FP(MedianOf(a5, q), 3)) + TD(FP(MedianOf(a15, q), 3)) +
                     TD(FP(MedianOf(a60, q), 3)) + TD(FP(mg, 3)) + TD(PX(mg * g_last)) + TDc(F(mr, 2) + "&times;", PCol(mr, 1.0, 1.0)) +
                     TDc(FP(ph, 0), PCol(ph, 0.5, 0.15)) + TD(sa) + TD(sb) + "</tr>";
      repS[nr - 1] = "  " + nm[bi] + " (N " + I2S(q) + "): range 60 min " + FP(mg, 3) + "% (circa " + PX(mg * g_last) + ") = " + F(mr, 2) +
                     " volte lo stesso orario senza notizie; mossa mediana 1 min " + FP(MedianOf(a1, q), 3) + "%, 5 min " + FP(MedianOf(a5, q), 3) +
                     "%, 15 min " + FP(MedianOf(a15, q), 3) + "%, 60 min " + FP(MedianOf(a60, q), 3) + "%; i minuti 5-60 proseguono la " +
                     "direzione dei primi 5 nel " + FP(ph, 0) + "%; dato sopra le attese: rialzo a 60 min " + sa + "; sotto le attese: " + sb + ".";
      scr[nr - 1] = MathIsValidNumber(mr) ? mr : -1;
     }
   bool usedR[];
   ArrayResize(usedR, nr);
   for(int z = 0; z < nr; z++)
      usedR[z] = false;
   for(int r = 0; r < 40 && r < nr; r++)
     {
      int bi = -1;
      for(int z = 0; z < nr; z++)
         if(!usedR[z] && (bi < 0 || scr[z] > scr[bi]))
            bi = z;
      usedR[bi] = true;
      W(rowS[bi]);
      R(g_repEv, repS[bi]);
     }
   TEnd();
   SecEnd();
   //--- per orario di uscita
   SecStart("Reazione per orario di uscita", "Tutte le notizie che escono allo stesso orario, confrontate con lo stesso orario nei giorni senza notizie.");
   THead("Orario (orario dei dati)|N notizie|Notizia pi&ugrave; frequente|Mossa 5 min %|Range 60 min %|Stesso orario senza notizie %|Rapporto");
   R(g_repEv, "  [Per orario di uscita]");
   for(int z = 0; z < ns; z++)
     {
      double a5[], ag[];
      ArrayResize(a5, nN);
      ArrayResize(ag, nN);
      int q = 0;
      string bestN = "";
      int bestC = 0;
      for(int i = 0; i < nN; i++)
        {
         if(!ok[i] || sl[i] != slots[z])
            continue;
         a5[q] = MathAbs(r5[i]);
         ag[q] = rg[i];
         q++;
         if(g_nName[i] != bestN)
           {
            int c = 0;
            for(int i2 = 0; i2 < nN; i2++)
               if(ok[i2] && sl[i2] == slots[z] && g_nName[i2] == g_nName[i])
                  c++;
            if(c > bestC)
              {
               bestC = c;
               bestN = g_nName[i];
              }
           }
        }
      if(q < 5)
         continue;
      double mg = MedianOf(ag, q), rt = Dv(mg, base[z]);
      W("<tr>" + TD(SlotLab(slots[z])) + TD(I2S(q)) + TD(bestN + " (" + I2S(bestC) + ")") + TD(FP(MedianOf(a5, q), 3)) + TD(FP(mg, 3)) +
        TD(FP(base[z], 3)) + TDc(F(rt, 2) + "&times;", PCol(rt, 1.0, 1.0)) + "</tr>");
      R(g_repEv, "    " + SlotLab(slots[z]) + ": " + I2S(q) + " notizie (pi&ugrave; frequente " + bestN + "), mossa mediana 5 min " +
        FP(MedianOf(a5, q), 3) + "%, range 60 min " + FP(mg, 3) + "% contro " + FP(base[z], 3) + "% senza notizie (" + F(rt, 2) + " volte).");
     }
   TEnd();
   SecEnd();
  }

//+------------------------------------------------------------------+
//| Sessioni: cosa succede dopo gli orari chiave delle piazze         |
//| Orari locali convertiti giorno per giorno nell'orologio dei dati  |
//| (ora legale USA ed europea gestite separatamente).                |
//+------------------------------------------------------------------+
#define NSE 11
string SE_NAME[NSE] = {"Apertura Tokyo", "Pre-apertura Europa", "Apertura Europa (Xetra 09:00, Londra 08:00)", "Dati macro USA delle 8:30",
                       "Apertura cash USA", "Dati USA delle 10:00", "Fix WM/Reuters di Londra", "FOMC / pomeriggio USA",
                       "Chiusura Europa (Xetra 17:30, Londra 16:30)", "Chiusura cash USA", "Fine giornata forex / rollover"
                      };
int    SE_MKT[NSE]  = {3, 2, 2, 0, 0, 0, 1, 0, 2, 0, 0};
int    SE_MIN[NSE]  = {540, 480, 540, 510, 570, 600, 960, 840, 1050, 960, 1020};

double g_seAct[], g_seOr[], g_seAbs[], g_seRng[], g_seDist[], g_seRv[];
int    g_seCont[], g_seInv[], g_seBrk[], g_seVwS[], g_seX[], g_seTch[];
bool   g_seF[], g_seHold[], g_seExt[], g_seNw[];
int    g_seN = 0;

struct SeSt
  {
   int               n, nw, bu, bd, fl, hd, ext, cN, cY, iN, iY, vN, vY, tN, tY;
   double            act, orr, absm, rng, xs, dist;
  };

string Share(const int k, const int n) { return n > 0 ? FP((double)k / n, 1) : "-"; }
double Frac(const int k, const int n) { return n > 0 ? (double)k / n : Nan(); }

void SeCalc(const bool &m[], SeSt &r)
  {
   ZeroMemory(r);
   double a[], o[], b[], g[], x[], d[];
   ArrayResize(a, g_seN); ArrayResize(o, g_seN); ArrayResize(b, g_seN);
   ArrayResize(g, g_seN); ArrayResize(x, g_seN); ArrayResize(d, g_seN);
   int na = 0, nx = 0;
   for(int i = 0; i < g_seN; i++)
     {
      if(!m[i])
         continue;
      o[r.n] = g_seOr[i];
      b[r.n] = g_seAbs[i];
      g[r.n] = g_seRng[i];
      r.n++;
      if(MathIsValidNumber(g_seAct[i]))
         a[na++] = g_seAct[i];
      if(g_seNw[i])
         r.nw++;
      if(g_seBrk[i] > 0)
         r.bu++;
      if(g_seBrk[i] < 0)
         r.bd++;
      if(g_seF[i])
         r.fl++;
      if(g_seHold[i])
         r.hd++;
      if(g_seExt[i])
         r.ext++;
      if(g_seCont[i] >= 0)
        {
         r.cN++;
         if(g_seCont[i] == 1)
            r.cY++;
        }
      if(g_seInv[i] >= 0)
        {
         r.iN++;
         if(g_seInv[i] == 1)
            r.iY++;
        }
      if(g_seVwS[i] >= 0)
        {
         r.vN++;
         if(g_seVwS[i] == 1)
            r.vY++;
        }
      if(g_seTch[i] >= 0)
        {
         r.tN++;
         if(g_seTch[i] == 1)
            r.tY++;
        }
      x[nx] = g_seX[i];
      d[nx] = g_seDist[i];
      nx++;
     }
   r.act = na > 0 ? MedianOf(a, na) : Nan();
   r.orr = r.n > 0 ? MedianOf(o, r.n) : Nan();
   r.absm = r.n > 0 ? MedianOf(b, r.n) : Nan();
   r.rng = r.n > 0 ? MedianOf(g, r.n) : Nan();
   r.xs = nx > 0 ? MedianOf(x, nx) : Nan();
   r.dist = nx > 0 ? MedianOf(d, nx) : Nan();
  }

string HM(const int mins) { int m = ((mins % 1440) + 1440) % 1440; return StringFormat("%02d:%02d", m / 60, m % 60); }

// minuti in cui il prezzo si muove di piu', nell'ora locale della piazza di riferimento
void HotMinutes(CSeries &s, const int barSec)
  {
   int st = barSec / 60 < 1 ? 1 : barSec / 60;
   double sum[1440];
   int cnt[1440], big[1440], nw[1440];
   bool used[1440];
   for(int z = 0; z < 1440; z++)
     {
      sum[z] = 0;
      cnt[z] = 0;
      big[z] = 0;
      nw[z] = 0;
      used[z] = false;
     }
   double ew = 0, al = 2.0 / (1440.0 / st + 1.0);
   bool init = false;
   long cur = -1;
   int off = 0;
   for(int i = 0; i < s.n; i++)
     {
      long dd = (long)s.t[i] / 86400;
      if(dd != cur)
        {
         cur = dd;
         off = g_ref >= 0 ? MktOffset(g_ref, s.t[i]) - DataOffset(s.t[i]) : 0;
        }
      int ml = ((MinOfDay(s.t[i]) + off * 60) % 1440 + 1440) % 1440;
      double r = s.h[i] - s.l[i];
      if(init && ew > 0)
        {
         double x = r / ew;
         sum[ml] += x;
         cnt[ml]++;
         if(x >= 3.0)
            big[ml]++;
         if(g_nN > 0 && NewsNear(s.t[i] - 60, s.t[i] + barSec - 1) >= 0)
            nw[ml]++;
        }
      ew = init ? al * r + (1 - al) * ew : r;
      init = true;
     }
   int mx = 0;
   for(int z = 0; z < 1440; z++)
      if(cnt[z] > mx)
         mx = cnt[z];
   string where = g_ref >= 0 ? "ora di " + MKT_NAME[g_ref] : "orario dei dati";
   SecStart("Minuti caldi (" + where + ")",
            "I minuti della giornata in cui il prezzo si muove di pi&ugrave;, trovati automaticamente su tutto lo storico. " +
            "Attivit&agrave; = range della barra diviso il range medio delle ultime 24 ore (1.00 = normale). Gli orari sono " +
            (g_ref >= 0 ? "convertiti giorno per giorno nell'ora locale di " + MKT_NAME[g_ref] + ", cos&igrave; il cambio dell'ora legale non li sposta. " : "") +
            "% esplosioni = barre almeno 3 volte il normale.");
   THead("Minuto|Orario dei dati (inverno / estate)|Barre|Attivit&agrave; media|% esplosioni (&ge; 3&times;)|% con notizia");
   R(g_repEv, "  [Minuti caldi, " + where + ": attivita' media della barra rispetto alle ultime 24 ore]");
   for(int r = 0; r < 20; r++)
     {
      int bi = -1;
      double bv = 0;
      for(int z = 0; z < 1440; z++)
        {
         if(used[z] || cnt[z] < 50 || cnt[z] < mx / 5)
            continue;
         double v = sum[z] / cnt[z];
         if(bi < 0 || v > bv)
           {
            bi = z;
            bv = v;
           }
        }
      if(bi < 0)
         break;
      used[bi] = true;
      string lab = g_ref >= 0 ? MKT_SHORT[g_ref] + " " + HM(bi) : HM(bi);
      int da = bi - g_refOffA * 60, db = bi - g_refOffB * 60;
      string dl = HM(da) + (HM(da) != HM(db) ? " / " + HM(db) : "");
      W("<tr>" + TD(lab) + TD(dl) + TD(I2S(cnt[bi])) + TDc(F(bv, 2) + "&times;", PCol(bv, 1.0, 2.0)) + TD(Share(big[bi], cnt[bi])) +
        TD(g_nN > 0 ? Share(nw[bi], cnt[bi]) : "-") + "</tr>");
      R(g_repEv, "    " + lab + " (dati " + dl + "): attivita' " + F(bv, 2) + " volte il normale, esplosioni " + Share(big[bi], cnt[bi]) +
        "%, con notizia " + (g_nN > 0 ? Share(nw[bi], cnt[bi]) : "-") + "%");
     }
   TEnd();
   SecEnd();
  }

void SessionTab(CSeries &s, const int barSec)
  {
   int H = InpSessionHours < 1 ? 1 : InpSessionHours;
   int ORm = InpORMinutes < barSec / 60 ? barSec / 60 : InpORMinutes;
   R(g_repEv, "");
   R(g_repEv, "=== SESSIONI: cosa succede dopo gli orari chiave delle piazze (orari locali convertiti giorno per giorno; OR = range dei " +
     "primi " + I2S(ORm) + " minuti; finestra = " + I2S(H) + " ore dall'orario chiave; solo giorni feriali della piazza) ===");
   if(s.n < 5000)
     {
      SecStart("Sessioni", "");
      W("<p class='muted'>Servono dati M1 o M5.</p>");
      SecEnd();
      return;
     }
   long d0 = (long)s.t[0] / 86400 + 1, d1 = (long)s.t[s.n - 1] / 86400;
   int nd = (int)(d1 - d0 + 1);
   if(nd < 60)
      return;
   ArrayResize(g_seAct, nd); ArrayResize(g_seOr, nd); ArrayResize(g_seAbs, nd); ArrayResize(g_seRng, nd); ArrayResize(g_seDist, nd);
   ArrayResize(g_seRv, nd); ArrayResize(g_seCont, nd); ArrayResize(g_seInv, nd); ArrayResize(g_seBrk, nd); ArrayResize(g_seVwS, nd);
   ArrayResize(g_seX, nd); ArrayResize(g_seTch, nd); ArrayResize(g_seF, nd); ArrayResize(g_seHold, nd); ArrayResize(g_seExt, nd);
   ArrayResize(g_seNw, nd);
   bool m[];
   ArrayResize(m, nd);
   //--- giorni di riferimento per l'orario dei dati: 15 gennaio e 15 luglio dell'ultimo anno completo
   MqlDateTime dl;
   TimeToStruct(s.t[s.n - 1], dl);
   MqlDateTime a;
   ZeroMemory(a);
   a.year = dl.year - 1;
   a.mon = 1;
   a.day = 15;
   long dayA = (long)StructToTime(a) / 86400;
   a.mon = 7;
   long dayB = (long)StructToTime(a) / 86400;
   int ord[NSE], tmA[NSE];
   for(int e = 0; e < NSE; e++)
     {
      ord[e] = e;
      tmA[e] = MinOfDay(LocalToData(dayA, SE_MKT[e], SE_MIN[e]));
     }
   for(int x = 1; x < NSE; x++)
     {
      int v = ord[x], y = x - 1;
      while(y >= 0 && tmA[ord[y]] > tmA[v])
        {
         ord[y + 1] = ord[y];
         y--;
        }
      ord[y + 1] = v;
     }
   int minPre = MathMax(1, 3600 / barSec / 2), minOR = MathMax(1, ORm * 60 / barSec / 2), minH = MathMax(2, H * 3600 / barSec / 2);
   string rowsA = "", rowsB = "", rowsC = "";
   double hist[20];
   for(int oi = 0; oi < NSE && !IsStopped(); oi++)
     {
      int e = ord[oi], mk = SE_MKT[e], mn = SE_MIN[e];
      g_seN = 0;
      int hN = 0, hP = 0;
      for(long day = d0; day <= d1; day++)
        {
         if(DowMon((datetime)(day * 86400)) >= 5)
            continue;
         datetime T = LocalToData(day, mk, mn);
         int k = LowerBound(s.t, s.n, T);
         if(k <= 0 || k >= s.n || (long)s.t[k] - (long)T >= 120)
            continue;
         int kp = LowerBound(s.t, s.n, T - 3600);
         int kor = LowerBound(s.t, s.n, T + ORm * 60);
         int k60 = LowerBound(s.t, s.n, T + 3600);
         int kh = LowerBound(s.t, s.n, T + H * 3600);
         if(k - kp < minPre || kor - k < minOR || kh - k < minH || kh <= kor || k60 <= k)
            continue;
         int i = g_seN;
         double op = s.o[k];
         if(!(op > 0))
            continue;
         //--- ora prima / ora dopo
         double pH = s.h[kp], pL = s.l[kp], aH = s.h[k], aL = s.l[k];
         for(int q = kp; q < k; q++)
           {
            if(s.h[q] > pH)
               pH = s.h[q];
            if(s.l[q] < pL)
               pL = s.l[q];
           }
         for(int q = k; q < k60; q++)
           {
            if(s.h[q] > aH)
               aH = s.h[q];
            if(s.l[q] < aL)
               aL = s.l[q];
           }
         g_seAct[i] = pH > pL ? (aH - aL) / (pH - pL) : Nan();
         double pre = s.c[k - 1] - s.o[kp], post = s.c[k60 - 1] - op;
         g_seInv[i] = (pre != 0 && post != 0) ? ((pre > 0) != (post > 0) ? 1 : 0) : -1;
         //--- range iniziale (OR)
         double oH = s.h[k], oL = s.l[k], vOr = 0;
         for(int q = k; q < kor; q++)
           {
            if(s.h[q] > oH)
               oH = s.h[q];
            if(s.l[q] < oL)
               oL = s.l[q];
            vOr += s.v[q];
           }
         g_seOr[i] = (oH - oL) / op;
         double orMv = s.c[kor - 1] - op, rest = s.c[kh - 1] - s.c[kor - 1];
         g_seCont[i] = (orMv != 0 && rest != 0) ? ((orMv > 0) == (rest > 0) ? 1 : 0) : -1;
         //--- rottura dell'OR, rottura falsa (tocca poi anche l'altro lato), estremi della finestra
         int br = 0;
         bool fl = false;
         double wH = oH, wL = oL;
         for(int q = kor; q < kh; q++)
           {
            bool u = s.h[q] > oH, dn = s.l[q] < oL;
            if(br == 0)
              {
               if(u && dn)
                 {
                  br = s.c[q] >= s.o[q] ? 1 : -1;
                  fl = true;
                 }
               else
                  if(u)
                     br = 1;
                  else
                     if(dn)
                        br = -1;
              }
            else
               if(!fl && ((br == 1 && dn) || (br == -1 && u)))
                  fl = true;
            if(s.h[q] > wH)
               wH = s.h[q];
            if(s.l[q] < wL)
               wL = s.l[q];
           }
         g_seBrk[i] = br;
         g_seF[i] = fl;
         g_seHold[i] = (br == 1 && s.c[kh - 1] > oH) || (br == -1 && s.c[kh - 1] < oL);
         g_seExt[i] = oH >= wH || oL <= wL;
         g_seAbs[i] = MathAbs(s.c[kh - 1] - op) / op;
         g_seRng[i] = (wH - wL) / op;
         g_seNw[i] = g_nN > 0 && NewsNear(T - 900, T + 900) >= 0;
         //--- VWAP ancorato all'orario chiave (senza volume: media semplice dei prezzi tipici)
         double cpv = 0, cv = 0, dmax = 0;
         int side = 0, sOr = 0, sLast = 0, xs = 0;
         bool tch = false;
         for(int q = k; q < kh; q++)
           {
            double tp = (s.h[q] + s.l[q] + s.c[q]) / 3.0;
            double w = s.hasVol ? s.v[q] : 1.0;
            cpv += tp * w;
            cv += w;
            double vw = cv > 0 ? cpv / cv : tp;
            double dd = MathAbs(s.c[q] - vw) / op;
            if(dd > dmax)
               dmax = dd;
            int sd = s.c[q] > vw ? 1 : (s.c[q] < vw ? -1 : 0);
            if(q == kor - 1)
               sOr = sd;
            if(q >= kor)
              {
               if(s.l[q] <= vw && s.h[q] >= vw)
                  tch = true;
               if(sd != 0 && side != 0 && sd != side)
                  xs++;
              }
            if(sd != 0)
               side = sd;
            sLast = sd;
           }
         g_seVwS[i] = (sOr != 0 && sLast != 0) ? (sOr == sLast ? 1 : 0) : -1;
         g_seTch[i] = sOr != 0 ? (tch ? 1 : 0) : -1;
         g_seX[i] = xs;
         g_seDist[i] = dmax;
         //--- volume relativo dei primi minuti rispetto agli ultimi 20 giorni validi
         g_seRv[i] = Nan();
         if(s.hasVol)
           {
            if(hN >= 10)
              {
               double mv = 0;
               for(int z = 0; z < hN; z++)
                  mv += hist[z];
               g_seRv[i] = Dv(vOr, mv / hN);
              }
            hist[hP] = vOr;
            hP = (hP + 1) % 20;
            if(hN < 20)
               hN++;
           }
         g_seN++;
        }
      if(g_seN < 30)
         continue;
      for(int z = 0; z < g_seN; z++)
         m[z] = true;
      SeSt r;
      SeCalc(m, r);
      string loc = MKT_SHORT[mk] + " " + HM(mn);
      int ta = MinOfDay(LocalToData(dayA, mk, mn)), tb = MinOfDay(LocalToData(dayB, mk, mn));
      string dt = HM(ta) + (ta != tb ? " / " + HM(tb) : "");
      int nb = r.bu + r.bd;
      rowsA += "<tr>" + TD(SE_NAME[e]) + TD(loc) + TD(dt) + TD(I2S(r.n)) + TDc(F(r.act, 2) + "&times;", PCol(r.act, 1.0, 1.0)) +
               TD(FP(r.orr, 3)) + TD(Share(r.bu, r.n) + " / " + Share(r.bd, r.n)) + TD(Share(r.fl, nb)) + TD(Share(r.hd, nb)) +
               TDc(Share(r.cY, r.cN), PCol(Frac(r.cY, r.cN), 0.5, 0.15)) + TDc(Share(r.iY, r.iN), PCol(Frac(r.iY, r.iN), 0.5, 0.15)) +
               TD(Share(r.ext, r.n)) + TD(FP(r.absm, 3)) + TD(FP(r.rng, 3)) + TD(PX(r.rng * g_last)) + TD(g_nN > 0 ? Share(r.nw, r.n) : "-") + "</tr>";
      R(g_repEv, "  " + SE_NAME[e] + " (" + loc + ", orario dei dati " + dt + "), " + I2S(r.n) + " giorni: range dell'ora dopo = " + F(r.act, 2) +
        " volte l'ora prima; range iniziale " + FP(r.orr, 3) + "%; rompe l'OR al rialzo " + Share(r.bu, r.n) + "%, al ribasso " + Share(r.bd, r.n) +
        "%; rotture false (poi tocca anche l'altro lato) " + Share(r.fl, nb) + "%; chiude la finestra oltre il lato rotto " + Share(r.hd, nb) +
        "%; il resto della finestra prosegue la direzione dei primi " + I2S(ORm) + " min " + Share(r.cY, r.cN) + "%; l'ora dopo va contro " +
        "l'ora prima " + Share(r.iY, r.iN) + "%; l'OR contiene il massimo o il minimo della finestra " + Share(r.ext, r.n) +
        "%; movimento mediano in " + I2S(H) + " ore " + FP(r.absm, 3) + "%, range mediano " + FP(r.rng, 3) + "% (circa " + PX(r.rng * g_last) +
        "); con notizia " + (g_nN > 0 ? Share(r.nw, r.n) : "-") + "%.");
      rowsB += "<tr>" + TD(SE_NAME[e]) + TD(loc) + TD(I2S(r.vN)) + TDc(Share(r.vY, r.vN), PCol(Frac(r.vY, r.vN), 0.5, 0.15)) +
               TD(Share(r.tY, r.tN)) + TD(F(r.xs, 0)) + TD(FP(r.dist, 3)) + TD(PX(r.dist * g_last)) + "</tr>";
      R(g_repEv, "    VWAP da " + loc + ": a fine finestra dallo stesso lato del VWAP di fine OR " + Share(r.vY, r.vN) + "%, torna a toccare il " +
        "VWAP dopo l'OR " + Share(r.tY, r.tN) + "%, incroci mediani " + F(r.xs, 0) + ", distanza massima mediana " + FP(r.dist, 3) + "% (circa " +
        PX(r.dist * g_last) + ").");
      if(s.hasVol)
        {
         double rl[4] = {0, 0.8, 1.5, 1e18};
         string rn[3] = {"RVOL sotto 0.8", "RVOL 0.8-1.5", "RVOL oltre 1.5"};
         rowsC += "<tr class='grp'><td colspan='9'>" + SE_NAME[e] + " (" + loc + ")</td></tr>";
         for(int c = 0; c < 3; c++)
           {
            for(int z = 0; z < g_seN; z++)
               m[z] = MathIsValidNumber(g_seRv[z]) && g_seRv[z] >= rl[c] && g_seRv[z] < rl[c + 1];
            SeSt q;
            SeCalc(m, q);
            if(q.n < 10)
               continue;
            int qb = q.bu + q.bd;
            rowsC += "<tr>" + TD(rn[c]) + TD(I2S(q.n)) + TD(FP(q.orr, 3)) + TD(Share(qb, q.n)) + TD(Share(q.fl, qb)) +
                     TDc(Share(q.cY, q.cN), PCol(Frac(q.cY, q.cN), 0.5, 0.15)) + TD(FP(q.absm, 3)) + TD(FP(q.rng, 3)) +
                     TDc(Share(q.vY, q.vN), PCol(Frac(q.vY, q.vN), 0.5, 0.15)) + "</tr>";
            R(g_repEv, "    " + rn[c] + " (N " + I2S(q.n) + "): range iniziale " + FP(q.orr, 3) + "%, rompe l'OR " + Share(qb, q.n) +
              "%, false " + Share(q.fl, qb) + "%, prosegue la direzione dei primi " + I2S(ORm) + " min " + Share(q.cY, q.cN) +
              "%, movimento mediano " + FP(q.absm, 3) + "%, range mediano " + FP(q.rng, 3) + "%, stesso lato del VWAP " + Share(q.vY, q.vN) + "%");
           }
        }
     }
   string wl = I2S(ORm) + " min";
   SecStart("Orari chiave delle piazze: cosa succede dopo",
            "Per ogni orario chiave (ora locale della piazza, convertita giorno per giorno nell'orologio dei dati) si osservano i " +
            I2S(H) + " ore successive. <b>Attivit&agrave;</b> = range dei 60 minuti dopo diviso il range dei 60 minuti prima. " +
            "<b>OR</b> = range dei primi " + wl + ". <b>Rottura falsa</b> = dopo aver rotto un lato dell'OR il prezzo tocca anche l'altro. " +
            "<b>Prosegue</b> = il resto della finestra va nella stessa direzione dei primi " + wl + " (tratti separati: senza legame " +
            "sarebbe circa 50%). <b>L'ora dopo va contro l'ora prima</b>: circa 50% senza legame. Le righe sono in ordine di orario " +
            "dei dati (inverno). Orari che per lo strumento non contano mostrano attivit&agrave; vicina a 1.");
   THead("Evento|Ora locale|Orario dei dati (inverno / estate)|Giorni|Attivit&agrave; ora dopo / ora prima|Range iniziale %|Rompe l'OR: % su / % gi&ugrave;|% rottura falsa|% chiude oltre il lato rotto|% prosegue la direzione dei primi " + wl + "|% l'ora dopo va contro l'ora prima|% OR contiene max o min della finestra|Movimento mediano " + I2S(H) + " ore %|Range mediano " + I2S(H) + " ore %|&asymp; prezzo|% con notizia");
   W(rowsA);
   TEnd();
   SecEnd();
   SecStart("VWAP ancorato a ogni orario chiave",
            "VWAP calcolato dall'orario chiave in avanti (" + (s.hasVol ? "pesato con il tick volume: sui CFD &egrave; il numero di " +
            "variazioni di prezzo, non il controvalore, ma segue bene l'attivit&agrave;" : "senza volume: media semplice dei prezzi") +
            "). <b>Stesso lato</b> = a fine finestra il prezzo &egrave; dalla stessa parte del VWAP in cui era alla fine dell'OR. " +
            "<b>Torna al VWAP</b> = dopo l'OR il prezzo tocca di nuovo il VWAP. <b>Incroci</b> = quante volte la chiusura passa da un " +
            "lato all'altro (pochi = giornata direzionale, tanti = giornata in rotazione).");
   THead("Evento|Ora locale|Giorni|% stesso lato del VWAP a fine finestra|% torna a toccare il VWAP dopo l'OR|Incroci mediani|Distanza massima mediana dal VWAP %|&asymp; prezzo");
   W(rowsB);
   TEnd();
   SecEnd();
   if(s.hasVol && rowsC != "")
     {
      SecStart("Volume relativo all'orario (RVOL) dei primi " + wl,
               "RVOL = volume dei primi " + wl + " diviso la media degli stessi minuti nei 20 giorni precedenti (1 = normale). " +
               "Le stesse misure della tabella sopra, divise per volume basso, normale e alto all'apertura della finestra.");
      THead("RVOL|Giorni|Range iniziale %|% rompe l'OR|% rottura falsa|% prosegue la direzione dei primi " + wl + "|Movimento mediano %|Range mediano %|% stesso lato del VWAP");
      W(rowsC);
      TEnd();
      SecEnd();
     }
   HotMinutes(s, barSec);
  }

//+------------------------------------------------------------------+
//| Gap: salti di prezzo alla riapertura                              |
//+------------------------------------------------------------------+
void GapLine(const string label, const bool &m[])
  {
   int n = 0, up = 0, f15 = 0, f60 = 0, f240 = 0, f1440 = 0, nf = 0;
   double a[], ft[];
   ArrayResize(a, g_gpN);
   ArrayResize(ft, g_gpN);
   for(int e = 0; e < g_gpN; e++)
     {
      if(!m[e])
         continue;
      a[n++] = MathAbs(g_gpS[e]);
      if(g_gpS[e] > 0)
         up++;
      double x = g_gpFt[e];
      if(x >= 0)
        {
         ft[nf++] = x;
         if(x <= 15)
            f15++;
         if(x <= 60)
            f60++;
         if(x <= 240)
            f240++;
         f1440++;
        }
     }
   if(n < 3)
      return;
   double s[];
   Sorted(a, n, s);
   double med = Pct(s, n, 50), p90 = Pct(s, n, 90), mft = nf > 0 ? MedianOf(ft, nf) : Nan();
   W("<tr>" + TD(label) + TD(I2S(n)) + TD(FP((double)up / n, 1)) + TD(FP(med, 3)) + TD(PX(med * g_last)) + TD(FP(p90, 3)) +
     TD(FP((double)f15 / n, 1)) + TD(FP((double)f60 / n, 1)) + TD(FP((double)f240 / n, 1)) + TD(FP((double)f1440 / n, 1)) +
     TD(nf > 0 ? DurLab(mft / 60.0) : "-") + "</tr>");
   R(g_repEv, "  " + label + ": N " + I2S(n) + ", al rialzo " + FP((double)up / n, 1) + "%, gap mediano " + FP(med, 3) + "% (circa " +
     PX(med * g_last) + "), P90 " + FP(p90, 3) + "%; chiuso (torna alla chiusura precedente) entro 15 min " + FP((double)f15 / n, 1) +
     "%, 1 ora " + FP((double)f60 / n, 1) + "%, 4 ore " + FP((double)f240 / n, 1) + "%, 24 ore " + FP((double)f1440 / n, 1) +
     "%; tempo mediano di chiusura " + (nf > 0 ? DurLab(mft / 60.0) : "-") + ".");
  }

void GapTab(CSeries &s, const int barSec)
  {
   R(g_repEv, "");
   R(g_repEv, "=== GAP: salti di prezzo alla riapertura dopo una pausa del mercato ===");
   SecStart("Gap: salti di prezzo alla riapertura",
            "Gap = differenza tra l'apertura dopo una pausa del mercato (almeno 30 minuti senza barre) e l'ultima chiusura prima della " +
            "pausa. 'Chiuso' = il prezzo torna alla chiusura precedente.");
   int gi[];
   int ng = 0;
   long minGap = (long)3 * barSec > 1800 ? (long)3 * barSec : 1800;
   for(int i = 1; i < s.n; i++)
      if((long)s.t[i] - (long)s.t[i - 1] >= minGap)
        {
         ng++;
         ArrayResize(gi, ng, 4096);
         gi[ng - 1] = i;
        }
   if(ng < 5)
     {
      W("<p class='muted'>Nessun gap nei dati.</p>");
      SecEnd();
      return;
     }
   g_gpN = ng;
   ArrayResize(g_gpS, ng);
   ArrayResize(g_gpFt, ng);
   bool we[];
   int gh[], gd[];
   ArrayResize(we, ng);
   ArrayResize(gh, ng);
   ArrayResize(gd, ng);
   double ab[];
   ArrayResize(ab, ng);
   for(int e = 0; e < ng; e++)
     {
      int i = gi[e];
      double pc = s.c[i - 1];
      g_gpS[e] = s.o[i] / pc - 1;
      ab[e] = MathAbs(g_gpS[e]);
      we[e] = (long)s.t[i] - (long)s.t[i - 1] > 36 * 3600;
      gh[e] = HourOf(s.t[i]);
      gd[e] = DowMon(s.t[i]);
      g_gpFt[e] = -1;
      if(g_gpS[e] == 0)
        {
         g_gpFt[e] = 0;
         continue;
        }
      for(int k = i; k < s.n; k++)
        {
         if((long)s.t[k] - (long)s.t[i] > 86400)
            break;
         if((g_gpS[e] > 0 && s.l[k] <= pc) || (g_gpS[e] < 0 && s.h[k] >= pc))
           {
            g_gpFt[e] = (double)((long)s.t[k] - (long)s.t[i]) / 60.0;
            break;
           }
        }
     }
   double sa[];
   Sorted(ab, ng, sa);
   double q50 = Pct(sa, ng, 50), q90 = Pct(sa, ng, 90);
   THead("Tipo|N|% al rialzo|Gap mediano %|&asymp; prezzo|Gap P90 %|% chiuso entro 15 min|entro 1 ora|entro 4 ore|entro 24 ore|Tempo mediano di chiusura");
   bool m[];
   ArrayResize(m, ng);
   for(int e = 0; e < ng; e++)
      m[e] = true;
   GapLine("Tutti i gap", m);
   for(int e = 0; e < ng; e++)
      m[e] = we[e];
   GapLine("dopo il weekend", m);
   for(int e = 0; e < ng; e++)
      m[e] = !we[e];
   GapLine("dopo la pausa giornaliera o un festivo", m);
   for(int e = 0; e < ng; e++)
      m[e] = g_gpS[e] > 0;
   GapLine("al rialzo", m);
   for(int e = 0; e < ng; e++)
      m[e] = g_gpS[e] < 0;
   GapLine("al ribasso", m);
   for(int e = 0; e < ng; e++)
      m[e] = ab[e] >= q90;
   GapLine("grandi (10% pi&ugrave; ampi)", m);
   for(int e = 0; e < ng; e++)
      m[e] = ab[e] < q50;
   GapLine("piccoli (sotto la mediana)", m);
   Grp("Ora di riapertura (orario dei dati)", 11);
   R(g_repEv, "  [Ora di riapertura]");
   for(int h = 0; h < 24; h++)
     {
      for(int e = 0; e < ng; e++)
         m[e] = gh[e] == h;
      GapLine(HourLab(h), m);
     }
   Grp("Giorno di riapertura", 11);
   R(g_repEv, "  [Giorno di riapertura]");
   for(int d = 0; d < 7; d++)
     {
      for(int e = 0; e < ng; e++)
         m[e] = gd[e] == d;
      GapLine(DOW[d], m);
     }
   TEnd();
   SecEnd();
  }

//+------------------------------------------------------------------+
//| Stile e script della pagina                                       |
//+------------------------------------------------------------------+
string Css(void)
  {
   return ":root{--bg:#0b0f17;--card:#111827;--fg:#e5e7eb;--mut:#9ca3af;--line:#1f2937;--acc:#3b82f6}" +
          "*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}" +
          "header{position:sticky;top:0;z-index:10;background:var(--bg);border-bottom:1px solid var(--line);padding:10px 16px 0}" +
          "header h1{font-size:20px;margin:0 0 2px}header p{margin:0 0 8px;color:var(--mut);font-size:12px}" +
          "nav{display:flex;gap:4px;overflow-x:auto;padding-bottom:8px}" +
          "nav button{background:#0f172a;color:var(--mut);border:1px solid var(--line);border-radius:6px;padding:6px 11px;cursor:pointer;white-space:nowrap;font:inherit;font-size:13px}" +
          "nav button.on{background:var(--acc);color:#fff;border-color:var(--acc)}" +
          "main{max-width:1500px;margin:0 auto;padding:12px 16px}h2{font-size:18px;margin:0 0 6px}h3{font-size:15px;margin:16px 0 6px}" +
          "section{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin:12px 0}" +
          ".muted{color:var(--mut)}.desc{color:var(--mut);margin:0 0 10px;max-width:1100px}" +
          ".tw{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:12.5px;font-variant-numeric:tabular-nums}" +
          "th,td{padding:5px 8px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap}" +
          "th:first-child,td:first-child{text-align:left}th{color:var(--mut);font-weight:600}" +
          "tr.grp td{color:var(--acc);font-weight:600;padding-top:12px;text-align:left}" +
          ".kpi{display:grid;grid-template-columns:repeat(auto-fill,minmax(175px,1fr));gap:10px}" +
          ".kpi div{background:#0f172a;border:1px solid var(--line);border-radius:8px;padding:10px}.kpi b{display:block;font-size:18px}" +
          ".kpi span{color:var(--mut);font-size:12px}.kpi small{display:block;color:var(--mut);font-size:11px}" +
          ".g2,.g3{display:grid;gap:18px;margin-top:14px}.g2{grid-template-columns:repeat(auto-fit,minmax(420px,1fr))}" +
          ".g3{grid-template-columns:repeat(auto-fit,minmax(300px,1fr))}" +
          ".ch .ct{font-size:13px;margin-bottom:6px}.cf{color:var(--mut);font-size:11px;margin-top:4px}" +
          ".vb{display:flex;align-items:flex-end;height:190px;gap:2px;border-bottom:1px solid var(--line)}" +
          ".vb .c{flex:1;min-width:0;display:flex;flex-direction:column;height:100%}" +
          ".vb .bs{flex:1;display:flex;align-items:flex-end;gap:1px}.vb .bs i{flex:1;display:block;min-height:1px;border-radius:2px 2px 0 0}" +
          ".vb .c span{font-size:10px;color:var(--mut);text-align:center;white-space:nowrap;overflow:hidden;height:15px}" +
          ".lg{font-size:12px;color:var(--mut);margin-top:6px}.lg b{display:inline-block;width:10px;height:10px;border-radius:2px;margin:0 4px 0 10px}" +
          ".hb{position:relative;min-width:110px;height:18px;background:#0f172a;border-radius:3px}" +
          ".hb i{position:absolute;left:0;top:0;bottom:0;background:#374151;border-radius:3px}" +
          ".hb span{position:relative;padding:0 6px;font-size:12px;line-height:18px}" +
          ".st{display:flex;min-width:120px;height:12px;border-radius:3px;overflow:hidden}.st i{display:block;height:100%}" +
          ".vps{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:14px;margin-top:14px}" +
          ".vp .r{height:5px}.vp .r i{display:block;height:100%}.vp .r.cur{outline:1px solid #f9fafb}" +
          ".svg{display:block;max-width:100%}" +
          "textarea{width:100%;height:70vh;background:#0f172a;color:var(--fg);border:1px solid var(--line);border-radius:8px;padding:12px;font:12px/1.5 Consolas,monospace}" +
          ".cp{background:var(--acc);color:#fff;border:0;border-radius:6px;padding:8px 14px;cursor:pointer;font:inherit;margin-bottom:10px}";
  }

string Js(void)
  {
   return "function cp(b){var t=document.getElementById('rep');t.select();try{document.execCommand('copy');}catch(e){}" +
          "if(navigator.clipboard)navigator.clipboard.writeText(t.value);b.textContent='Copiato';}" +
          "function show(id){if(!document.getElementById('tab-'+id))id='overview';" +
          "var t=document.querySelectorAll('.tab');for(var i=0;i<t.length;i++)t[i].hidden=(t[i].id!=='tab-'+id);" +
          "var b=document.querySelectorAll('nav button');for(var j=0;j<b.length;j++)b[j].className=(b[j].getAttribute('data-tab')===id)?'on':'';" +
          "if(location.hash!=='#'+id)history.replaceState(null,'','#'+id);window.scrollTo(0,0);}" +
          "var bs=document.querySelectorAll('nav button');for(var k=0;k<bs.length;k++)bs[k].onclick=function(){show(this.getAttribute('data-tab'));};" +
          "show(location.hash.slice(1)||'overview');";
  }

//+------------------------------------------------------------------+
//| Analisi di un simbolo                                             |
//+------------------------------------------------------------------+
bool Analyze(const string sym)
  {
   CSeries m1, h1, d1, m5, m15, h4;
   PrintFormat("[MarketProfiler] %s: carico lo storico...", sym);
   if(!SymbolSelect(sym, true))
     {
      PrintFormat("[MarketProfiler] simbolo %s non trovato (controlla il suffisso del broker)", sym);
      return false;
     }
   Comment("MarketProfiler: carico lo storico di ", sym, " ...");
   if(InpUseM1)
      m1.Load(sym, PERIOD_M1, InpMaxBarsM1, 60);
   h1.Load(sym, PERIOD_H1, InpMaxBarsH1, 3650);
   d1.Load(sym, PERIOD_D1, InpMaxBarsD1, 36500);
   m5.Load(sym, PERIOD_M5, 0, 365);
   m15.Load(sym, PERIOD_M15, 0, 730);
   h4.Load(sym, PERIOD_H4, 0, 36500);
   if(m1.n > 0)
      PrintFormat("[MarketProfiler] %s M1: %d barre %s -> %s", sym, m1.n, TimeToString(m1.t[0]), TimeToString(m1.t[m1.n - 1]));
   if(h1.n > 0)
      PrintFormat("[MarketProfiler] %s H1: %d barre %s -> %s", sym, h1.n, TimeToString(h1.t[0]), TimeToString(h1.t[h1.n - 1]));
   if(d1.n > 0)
      PrintFormat("[MarketProfiler] %s D1: %d barre %s -> %s", sym, d1.n, TimeToString(d1.t[0]), TimeToString(d1.t[d1.n - 1]));
   g_warn = "";
   if(m1.truncated || h1.truncated || d1.truncated)
     {
      g_warn = "Attenzione: lo storico &egrave; tagliato da 'Barre massime nel grafico' (" + I2S(TerminalInfoInteger(TERMINAL_MAXBARS)) +
               "). Strumenti &rarr; Opzioni &rarr; Grafici &rarr; Barre massime nel grafico = Illimitato, riavvia MT5 e rilancia lo script.";
      Print("[MarketProfiler] storico tagliato da 'Barre massime nel grafico': impostalo su Illimitato e riavvia MT5");
     }
   //--- nei primi anni di alcuni storici mancano ore della giornata: esclusi (parametro)
   g_covInfo = "";
   if(InpSkipIncomplete && h1.n > 0)
     {
      datetime cov = CoverageStart(h1);
      if(cov > 0)
        {
         TrimFrom(m1, cov);
         TrimFrom(m5, cov);
         TrimFrom(m15, cov);
         TrimFrom(h1, cov);
         TrimFrom(h4, cov);
         TrimFrom(d1, cov);
         PrintFormat("[MarketProfiler] %s: %s", sym, g_covInfo);
        }
     }
   if(d1.n < 50 && h1.n < 50)
     {
      PrintFormat("[MarketProfiler] %s: storico insufficiente (D1=%d, H1=%d)", sym, d1.n, h1.n);
      return false;
     }
   g_digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   datetime lastT = 0;
   if(d1.n > 0 && d1.t[d1.n - 1] >= lastT) { lastT = d1.t[d1.n - 1]; g_last = d1.c[d1.n - 1]; }
   if(h1.n > 0 && h1.t[h1.n - 1] >= lastT) { lastT = h1.t[h1.n - 1]; g_last = h1.c[h1.n - 1]; }
   if(m1.n > 0 && m1.t[m1.n - 1] >= lastT) { lastT = m1.t[m1.n - 1]; g_last = m1.c[m1.n - 1]; }
   long age = (long)TimeCurrent() - (long)lastT;
   if(age > 10 * 86400)
     {
      g_warn += (g_warn != "" ? " " : "") + "Attenzione: i dati finiscono il " + TimeToString(lastT, TIME_DATE) + " (" + I2S(age / 86400) +
                " giorni fa). Aggiorna lo storico (Quant Data Manager) se vuoi analizzare anche il periodo recente.";
      PrintFormat("[MarketProfiler] %s: i dati finiscono il %s", sym, TimeToString(lastT, TIME_DATE));
     }
   RefSetup(sym, lastT);
   ResolveNewsCur(sym);
   g_curRows = "";
   g_sumRows = "";
   g_rep = "";
   g_repCur = "";
   g_repHead = "";
   g_repVol = "";
   int i0m = 0;  // scheda Minuto: solo gli ultimi InpMinuteYears anni (milioni di barre M1 altrimenti)
   g_minNote = "";
   if(InpMinuteYears > 0 && m1.n > 0)
     {
      datetime from = (datetime)((long)m1.t[m1.n - 1] - (long)InpMinuteYears * 365 * 86400);
      int lo = 0, hi = m1.n;
      while(lo < hi)
        {
         int mid = (lo + hi) / 2;
         if(m1.t[mid] < from)
            lo = mid + 1;
         else
            hi = mid;
        }
      i0m = lo;
      if(i0m > 0)
         g_minNote = " Scheda Minuto: ultimi " + I2S(InpMinuteYears) + " anni di M1 (dal " + TimeToString(m1.t[i0m], TIME_DATE) +
                     "); le altre schede usano tutto lo storico. Per usare tutti gli anni metti 'Scheda Minuto' = 0.";
     }

   string clean = sym;
   StringReplace(clean, ".", "_");
   StringReplace(clean, "#", "_");
   StringReplace(clean, "/", "_");
   string fname = "MarketProfiler_" + clean + ".html";
   int flags = FILE_WRITE | FILE_TXT | FILE_ANSI | (InpCommonDir ? FILE_COMMON : 0);
   g_fh = FileOpen(fname, flags, '\t', CP_UTF8);
   if(g_fh == INVALID_HANDLE)
     {
      PrintFormat("[MarketProfiler] impossibile creare %s (errore %d)", fname, GetLastError());
      return false;
     }
   string info = "";
   if(m1.n > 0)
      info += "M1: " + I2S(m1.n) + " barre (" + TimeToString(m1.t[0], TIME_DATE) + " &rarr; " + TimeToString(m1.t[m1.n - 1], TIME_DATE) + ") &middot; ";
   if(h1.n > 0)
      info += "H1: " + I2S(h1.n) + " barre (" + TimeToString(h1.t[0], TIME_DATE) + " &rarr; " + TimeToString(h1.t[h1.n - 1], TIME_DATE) + ") &middot; ";
   if(d1.n > 0)
      info += "D1: " + I2S(d1.n) + " barre (" + TimeToString(d1.t[0], TIME_DATE) + " &rarr; " + TimeToString(d1.t[d1.n - 1], TIME_DATE) + ") &middot; ";
   W("<!doctype html><html lang='it'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>");
   W("<title>" + sym + " &mdash; Market Profiler</title><style>" + Css() + "</style></head><body>");
   string tz = "orari = " + TZName() + (g_ref >= 0 ? "; tra parentesi l'ora di " + MKT_NAME[g_ref] : "") +
               " (parametro 'Fuso orario dei dati': deve essere il fuso con cui sono stati scaricati i dati); notizie " + NewsCurStr();
   W("<header><h1>" + sym + " &mdash; analisi descrittiva</h1><p>" + info + tz + " &middot; generato " +
     TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES) + "</p>" + (g_warn != "" ? "<p style='color:#f59e0b'>" + g_warn + "</p>" : "") +
     (g_covInfo != "" ? "<p class='muted'>" + g_covInfo + "</p>" : "") + "<nav>");
   W("<button data-tab='overview'>Panoramica</button><button data-tab='report'>Rapporto</button>");
   R(g_repHead, "RAPPORTO DESCRITTIVO - " + sym + " (generato " + TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES) + ")");
   R(g_repHead, "Dati: " + info + tz + ".");
   if(g_warn != "")
      R(g_repHead, g_warn);
   if(g_covInfo != "")
      R(g_repHead, g_covInfo);
   R(g_repHead, "Metodo: ogni periodo (candela del timeframe) &egrave; scomposto in apertura -> primo estremo (movimento iniziale), " +
     "primo -> secondo estremo (spostamento pi&ugrave; ampio = massimo - minimo) e secondo estremo -> chiusura (mean reversion, " +
     "quanto viene restituito). Percentuali in % del prezzo di apertura del periodo. Mediana = valore tipico, P90 = superato " +
     "nel 10% dei periodi.");
   for(int k = 0; k < NTF; k++)
      W("<button data-tab='" + TF_KEY[k] + "'>" + TF_LABEL[k] + "</button>");
   W("<button data-tab='sess'>Sessioni</button><button data-tab='swing'>Swing</button><button data-tab='break'>Rotture</button><button data-tab='imp'>Impulsi</button>" +
     "<button data-tab='news'>Notizie</button><button data-tab='gap'>Gap</button>");
   W("<button data-tab='volume'>Volume</button></nav></header><main>");

   CBlocks b;
   for(int k = 0; k < NTF; k++)
     {
      Comment("MarketProfiler ", sym, ": analizzo ", TF_LABEL[k], " ...");
      W("<div class='tab' id='tab-" + TF_KEY[k] + "' hidden>");
      bool built = false;
      int pref[2];
      pref[0] = TF_SRC1[k];
      pref[1] = TF_SRC2[k];
      for(int z = 0; z < 2 && !built; z++)
        {
         if(pref[z] == 0 && m1.n > 50)
            built = Build(k, 0, m1, b, k == 0 ? i0m : 0);
         else
            if(pref[z] == 1 && h1.n > 50)
               built = Build(k, 1, h1, b, 0);
            else
               if(pref[z] == 2 && d1.n > 50)
                  built = Build(k, 2, d1, b, 0);
        }
      if(built)
         TfPage(b);
      else
        {
         SecStart(TF_LABEL[k], "");
         W("<p class='muted'>Dati insufficienti: servono barre " + (TF_SRC1[k] == 0 ? "M1" : (TF_SRC1[k] == 1 ? "H1" : "D1")) +
           " del simbolo (controlla che lo storico sia importato e che 'Barre massime nel grafico' sia Illimitato).</p>");
         SecEnd();
        }
      b.Free();
      W("</div>");
      PrintFormat("[MarketProfiler] %s: %s fatto", sym, TF_LABEL[k]);
     }
   //--- eventi: swing, rotture, impulsi, notizie, gap
   g_repEv = "";
   Comment("MarketProfiler ", sym, ": notizie dal calendario ...");
   datetime nFrom = m1.n > 0 ? m1.t[0] : (m5.n > 0 ? m5.t[0] : (h1.n > 0 ? h1.t[0] : d1.t[0]));
   LoadNews(nFrom, lastT);
   if(m1.n > 1000)
      AlignNews(m1);
   else
      AlignNews(m5);
   PrintFormat("[MarketProfiler] %s: %s", sym, g_nInfo);
   Comment("MarketProfiler ", sym, ": swing ...");
   W("<div class='tab' id='tab-swing' hidden>");
   SwingTab(m5, m15, h1, h4, d1);
   W("</div>");
   Comment("MarketProfiler ", sym, ": rotture ...");
   W("<div class='tab' id='tab-break' hidden>");
   BreakTab(m5, m15, h1, h4, d1);
   W("</div>");
   Comment("MarketProfiler ", sym, ": impulsi ...");
   W("<div class='tab' id='tab-imp' hidden>");
   if(m1.n > 5000)
      ImpulseTab(m1, 60);
   else
      ImpulseTab(m5, 300);
   W("</div>");
   Comment("MarketProfiler ", sym, ": notizie e gap ...");
   W("<div class='tab' id='tab-news' hidden>");
   NewsTab(m1);
   W("</div>");
   Comment("MarketProfiler ", sym, ": sessioni ...");
   W("<div class='tab' id='tab-sess' hidden>");
   if(m1.n > 5000)
      SessionTab(m1, 60);
   else
      SessionTab(m5, 300);
   W("</div>");
   W("<div class='tab' id='tab-gap' hidden>");
   if(m1.n > 1000)
      GapTab(m1, 60);
   else
      GapTab(h1, 3600);
   W("</div>");
   PrintFormat("[MarketProfiler] %s: eventi fatti", sym);
   W("<div class='tab' id='tab-overview' hidden>");
   Overview(d1, lastT);
   W("</div><div class='tab' id='tab-volume' hidden>");
   VolumeTab(h1, d1);
   W("</div><div class='tab' id='tab-report' hidden>");
   SecStart("Rapporto descrittivo", "Tutti i risultati in forma di testo. Premi 'Copia tutto' e incollalo in chat per l'analisi.");
   W("<button class='cp' onclick='cp(this)'>Copia tutto</button><textarea id='rep' readonly>");
   W(g_repHead);
   W("\n=== PERIODO IN CORSO ===\n");
   W(g_repCur);
   W(g_rep);
   W("\n=== EVENTI ===\n");
   W(g_repEv);
   W("\n=== VOLUME ===\n");
   W(g_repVol);
   W("</textarea>");
   SecEnd();
   W("</div></main><script>" + Js() + "</script></body></html>");
   FileClose(g_fh);
   g_fh = INVALID_HANDLE;
   Comment("");
   string path = (InpCommonDir ? TerminalInfoString(TERMINAL_COMMONDATA_PATH) : TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5") +
                 "\\Files\\" + fname;
   PrintFormat("[MarketProfiler] %s: report salvato in %s", sym, path);
   return true;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   string syms[];
   int n = 0;
   if(StringLen(InpSymbols) == 0)
     {
      ArrayResize(syms, 1);
      syms[0] = _Symbol;
      n = 1;
     }
   else
      n = StringSplit(InpSymbols, ',', syms);
   for(int i = 0; i < n; i++)
     {
      string s = syms[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s != "")
         Analyze(s);
     }
  }
//+------------------------------------------------------------------+
