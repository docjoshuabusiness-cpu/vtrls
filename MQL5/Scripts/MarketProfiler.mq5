//+------------------------------------------------------------------+
//|                                              MarketProfiler.mq5  |
//|  Analisi descrittiva di uno strumento, timeframe per timeframe.   |
//|  Output: report HTML a schede in MQL5\Files (o Common\Files).     |
//|                                                                  |
//|  Schede: Panoramica, Minuto, Ora, 4/6/8/12 ore, Giorno,           |
//|  Settimana, 2 settimane, Mese, Trimestre, Semestre, Anno, Volume. |
//|                                                                  |
//|  Ogni periodo (la candela del timeframe) e' scomposto in:         |
//|    apertura -> primo estremo        movimento iniziale            |
//|    primo -> secondo estremo         SPOSTAMENTO PIU' AMPIO        |
//|    secondo estremo -> chiusura      MEAN REVERSION (restituito)   |
//|  e per ogni tratto misura QUANTO (% e prezzo) e QUANDO avviene.   |
//|                                                                  |
//|  Usa in automatico tutto lo storico del simbolo, dalla prima       |
//|  all'ultima barra (anche simboli personalizzati, es. Dukascopy).  |
//|  Orari = ora delle barre (server, o fuso dei dati importati).     |
//|  Sui CFD il volume e' tick volume (attivita', non controvalore).  |
//+------------------------------------------------------------------+
#property copyright   "vtrls"
#property version     "1.00"
#property description "Analisi descrittiva per timeframe: spostamento piu' ampio, mean reversion, quando avvengono."
#property script_show_inputs

input string InpSymbols     = "";    // Simboli (vuoto = simbolo del grafico, altrimenti separati da virgola)
input int    InpMinuteYears = 3;     // Scheda Minuto: ultimi N anni di M1 (0 = tutto lo storico)
input bool   InpUseM1       = true;  // Usa M1 (scheda Minuto e 'quando' dentro l'ora)
input int    InpMaxBarsM1   = 0;     // Limite barre M1 (0 = tutto lo storico disponibile)
input int    InpMaxBarsH1   = 0;     // Limite barre H1 (0 = tutto lo storico disponibile)
input int    InpMaxBarsD1   = 0;     // Limite barre D1 (0 = tutto lo storico disponibile)
input bool   InpCommonDir   = false; // Salva in Common\Files invece di MQL5\Files

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
int    g_digits = 5;
double g_last = 0;
string g_curRows = "";
string g_sumRows = "";
string g_warn = "";
string g_minNote = "";

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
void   W(const string s) { FileWriteString(g_fh, s); }
string F(const double x, const int d) { if(!MathIsValidNumber(x)) return "&ndash;"; return DoubleToString(x, d); }
string FP(const double x, const int d) { return F(x * 100.0, d); }
string PX(const double x) { if(!MathIsValidNumber(x)) return "&ndash;"; return DoubleToString(x, g_digits); }
string I2S(const long x) { return IntegerToString(x); }
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
            Grp(grp[k], 11);
        }
      NxAcc a = acc[k];
      if(a.n < 5)
         continue;
      double same = (double)a.same / a.n, up = (double)a.up / a.n, rr = a.rr / a.n;
      W("<tr>" + TD(NX_LABEL[k]) + TD(I2S(a.n)) + TDc(FP(same, 1), PCol(same, 0.5, 0.15)) + TDc(FP(up, 1), PCol(up, 0.5, 0.15)) +
        TD(FP(a.ret / a.n, 3)) + TDc(F(rr, 2), PCol(rr, 1.0, 0.5)) + TD(FP((double)a.bh / a.n, 1)) + TD(FP((double)a.bl / a.n, 1)) +
        TD(FP((double)a.ins / a.n, 1)) + TD(a.br > 0 ? FP((double)a.fb / a.br, 1) : "&ndash;") + TD(FP((double)a.mid / a.n, 1)) + "</tr>");
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
         Kpi("Rendimento " + dl[k], FP(Dv(g_last, d.c[j]) - 1, 2) + "%", "");
     }
   W("</div>");
   SecEnd();
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
         Kpi("Ultima ora chiusa vs stessa ora (20 gg)", F(h1.v[j] / (sameSum / sameN), 2) + "&times;", TimeToString(h1.t[j], TIME_DATE | TIME_MINUTES));
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
      W("<h3>Volume medio per ora (server)</h3>");
      THead("Ora|Media 12 mesi|Media ultime 4 settimane|Ultima sessione|Ultime 4 sett. vs 12 mesi|Ultima sessione vs 12 mesi");
      for(int k = 0; k < 24; k++)
        {
         if(n12[k] == 0)
            continue;
         double r1 = a12[k] > 0 ? a4w[k] / a12[k] : Nan(), r2 = (a12[k] > 0 && nl[k] > 0) ? al[k] / a12[k] : Nan();
         W("<tr>" + TD(StringFormat("%02dh", k)) + TD(HBar(a12[k], mx, DoubleToString(a12[k], 0))) +
           TD(HBar(a4w[k], mx, DoubleToString(a4w[k], 0))) + TD(nl[k] > 0 ? HBar(al[k], mx, DoubleToString(al[k], 0)) : "&ndash;") +
           TDc(F(r1, 2) + "&times;", PCol(r1, 1.0, 0.6)) + TDc(F(r2, 2) + "&times;", PCol(r2, 1.0, 0.6)) + "</tr>");
        }
      TEnd();
     }
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
          ".svg{display:block;max-width:100%}";
  }

string Js(void)
  {
   return "function show(id){if(!document.getElementById('tab-'+id))id='overview';" +
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
   CSeries m1, h1, d1;
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
   g_curRows = "";
   g_sumRows = "";
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
   bool custom = SymbolInfoInteger(sym, SYMBOL_CUSTOM) != 0;
   string tz = custom ? "simbolo personalizzato: orari = fuso dei dati importati (Dukascopy / Quant Data Manager: di solito UTC)"
               : "orari = ora del server " + AccountInfoString(ACCOUNT_COMPANY);
   W("<header><h1>" + sym + " &mdash; analisi descrittiva</h1><p>" + info + tz + " &middot; generato " +
     TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES) + "</p>" + (g_warn != "" ? "<p style='color:#f59e0b'>" + g_warn + "</p>" : "") + "<nav>");
   W("<button data-tab='overview'>Panoramica</button>");
   for(int k = 0; k < NTF; k++)
      W("<button data-tab='" + TF_KEY[k] + "'>" + TF_LABEL[k] + "</button>");
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
   W("<div class='tab' id='tab-overview' hidden>");
   Overview(d1, lastT);
   W("</div><div class='tab' id='tab-volume' hidden>");
   VolumeTab(h1, d1);
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
