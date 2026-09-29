// Sottoinsieme fedele di MarketProfiler.mq5 (solo cio' che serve al modulo nuovo, per il banco di prova)
#define NTF     13
#define NX_ROWS 28
#define VP_BINS 60
#define C_BLUE  "#3b82f6"
#define C_RED   "#ef4444"
#define C_GREY  "#6b7280"
#define C_AMBER "#f59e0b"
#define C_GREEN "#34d399"
#define NPRF 3
#define HI_NMOD 21
#define OB_NT 7

enum ENUM_DATA_TZ { TZ_BROKER_NY7 = 0, TZ_UTC = 1, TZ_EUROPE = 2, TZ_FIXED = 3 };
input ENUM_DATA_TZ InpDataTZ = TZ_BROKER_NY7;
input int    InpDataGMT = 2;
input bool   InpRollSkip = true;
input int    InpRollPre = 15;
input int    InpRollPost = 60;
input double InpImpulsePct = 99.5;
input bool   InpCommonDir = false;

string TF_KEY[NTF]   = {"min", "h1", "h4", "h6", "h8", "h12", "d", "w", "w2", "mo", "q", "s", "y"};
string TF_LABEL[NTF] = {"Minuto", "Ora", "4 ore", "6 ore", "8 ore", "12 ore", "Giorno", "Settimana",
                        "2 settimane", "Mese", "Trimestre", "Semestre", "Anno"};
int    TF_K[NTF]     = {0, 0, 4, 6, 8, 12, 0, 0, 0, 0, 0, 0, 0};
int    TF_SRC1[NTF]  = {0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2};
int    TF_SRC2[NTF]  = {-1, 1, 0, 0, 0, 0, 0, 2, -1, -1, -1, -1, -1};
string DOW[7]  = {"Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"};
string DOWS[7] = {"Dom", "Lun", "Mar", "Mer", "Gio", "Ven", "Sab"};  // settimana che parte la domenica
string MON[12] = {"Gen", "Feb", "Mar", "Apr", "Mag", "Giu", "Lug", "Ago", "Set", "Ott", "Nov", "Dic"};
string CLS_NAME[3] = {"Trend", "Parziale", "Mean reversion"};
string CLS_COL[3]  = {C_BLUE, C_GREY, C_RED};

int    g_fh = INVALID_HANDLE;
bool   g_buf = false;   // se true W() scrive in g_bufS invece che nel file
string g_bufS = "";
string g_out = "";
int    g_digits = 5;
double g_last = 0;

struct NxAcc
  {
   int               n, same, up, bh, bl, ins, fb, br, mid;
   double            ret, rr;
  };

//+------------------------------------------------------------------+
//| Serie OHLCV                                                       |
//+------------------------------------------------------------------+
class CSeries
  {
public:
   datetime          t[];
   double            o[], h[], l[], c[], v[];
   int               sp[];  // spread della barra in punti (0 se non registrato)
   int               n;
   bool              hasVol, truncated;
                     CSeries(void) { n = 0; hasVol = false; truncated = false; }
   void              Free(void)
     {
      ArrayFree(t); ArrayFree(o); ArrayFree(h); ArrayFree(l); ArrayFree(c); ArrayFree(v); ArrayFree(sp);
      n = 0; hasVol = false; truncated = false;
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
void   W(const string s) { if(g_buf) g_bufS += s; else g_out += s; }
string F(const double x, const int d) { if(!MathIsValidNumber(x)) return "&ndash;"; return DoubleToString(x, d); }
string FP(const double x, const int d) { return F(x * 100.0, d); }
string PX(const double x) { if(!MathIsValidNumber(x)) return "&ndash;"; return DoubleToString(x, g_digits); }
string I2S(const long x) { return IntegerToString(x); }
void   R(string &dst, const string s) { dst += s + "\n"; }

string ZS(const double z) { if(!MathIsValidNumber(z)) return "-"; return (z >= 0 ? "+" : "") + DoubleToString(z, 1); }
double ZProp(const double p, const double p0, const double n)  // proporzione p su n casi contro l'atteso p0
  {
   if(!MathIsValidNumber(p) || !MathIsValidNumber(p0) || n <= 0 || p0 <= 0 || p0 >= 1)
      return MathArcsin(2.0);
   return (p - p0) / MathSqrt(p0 * (1 - p0) / n);
  }
double ArcF(const double x) { return 2.0 / M_PI * MathArcsin(MathSqrt(MathMax(0.0, MathMin(1.0, x)))); }  // legge dell'arcoseno

string HI_NAME[HI_NMOD] = {"Sessioni e orari chiave (reale contro atteso con direzione casuale)",
                           "Livelli: effetto del livello (reale contro livello finto)",
                           "Vita dei livelli (reale contro livello finto)",
                           "Livelli letti sui timeframe inferiori (reale contro livello finto)",
                           "Direzione (condizione contro tutti i periodi)",
                           "Rischio/rendimento lordo (aspettativa contro zero)", "", "",
                           "Coppie di contesti (aspettativa netta del broker peggiore contro zero)",
                           "ORB a tutti gli orari e con ogni candela di conferma",
                           "Rischio/rendimento lordo: il contesto contro la stessa ora",
                           "Rischio/rendimento lordo: la direzione conta",
                           "ORB: dopo la chiusura di conferma il prezzo va piu' a favore che contro",
                           "ORB: eventi dopo il range per candela di conferma",
                           "Persistenza per timeframe",
                           "Persistenza per ora del giorno",
                           "Timeframe alto -> basso: stati singoli della candela alta",
                           "Timeframe alto -> basso: coppie di stati della candela alta", "", "", ""};
int    g_hiCnt[HI_NMOD];
int    g_hiN = 0;
int    g_hiM[];
double g_hiZ[];
string g_hiT[];
string g_hiA = "", g_hiB = "";  // contesto corrente (analisi e gruppo) per il testo del riepilogo

bool HiKeep(const int m, const double z)  // conta il confronto; true se entra nel riepilogo
  {
   if(!MathIsValidNumber(z) || m < 0 || m >= HI_NMOD)
      return false;
   g_hiCnt[m]++;
   return MathAbs(z) >= 2.0;
  }

void HiAdd(const int m, const double z, const string txt)
  {
   if(g_hiN >= ArraySize(g_hiM))
     {
      int ns = g_hiN + 1024;
      ArrayResize(g_hiM, ns);
      ArrayResize(g_hiZ, ns);
      ArrayResize(g_hiT, ns);
     }
   g_hiM[g_hiN] = m;
   g_hiZ[g_hiN] = z;
   g_hiT[g_hiN] = txt;
   g_hiN++;
  }

void Hi(const int m, const double z, const string txt)
  {
   if(HiKeep(m, z))
      HiAdd(m, z, txt);
  }
string TD(const string s) { return "<td>" + s + "</td>"; }
string TDc(const string s, const string bg) { if(bg == "") return TD(s); return "<td style='background:" + bg + "'>" + s + "</td>"; }

string PCol(const double p, const double center, const double span)
  {
   if(!MathIsValidNumber(p) || !MathIsValidNumber(center) || span <= 0)
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
   double buf[480];
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
            sm += buf[c * 20 + k];
         if(sm > 0)
            b.rv[i] = b.V[i] / (sm / bn[c]);
        }
      buf[c * 20 + bp[c]] = b.V[i];
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

//+------------------------------------------------------------------+
//| Eventi                                                            |
//+------------------------------------------------------------------+
string   MKT_NAME[4]  = {"New York", "Londra", "Francoforte", "Tokyo"};
string   MKT_SHORT[4] = {"NY", "LDN", "FRA", "TKY"};
int      g_ref = 0, g_refOffA = 0, g_refOffB = 0;  // piazza di riferimento e sua differenza dai dati (gennaio / luglio)

int HourOf(const datetime t) { return (int)(((long)t % 86400) / 3600); }
int DowMon(const datetime t) { return (int)(((long)t / 86400 + 3) % 7); }  // 0 = lunedi'

string HourLab(const int h)
  {
   if(g_ref < 0)
      return StringFormat("%02dh", h);
   int a = ((h + g_refOffA) % 24 + 24) % 24, b = ((h + g_refOffB) % 24 + 24) % 24;
   return StringFormat("%02dh (%s %02dh", h, MKT_SHORT[g_ref], a) + (a != b ? StringFormat("/%02dh", b) : "") + ")";
  }

double MedianOf(const double &a[], const int n)
  {
   double s[];
   Sorted(a, n, s);
   return Pct(s, n, 50);
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

string SgnF(const double x, const int d) { if(!MathIsValidNumber(x)) return "-"; return (x >= 0 ? "+" : "") + DoubleToString(x, d); }

string Plain(const string s)  // testo senza entita' HTML (CSV e file delle regole)
  {
   string t = s;
   StringReplace(t, "&agrave;", "a'");
   StringReplace(t, "&egrave;", "e'");
   StringReplace(t, "&eacute;", "e'");
   StringReplace(t, "&igrave;", "i'");
   StringReplace(t, "&ograve;", "o'");
   StringReplace(t, "&ugrave;", "u'");
   StringReplace(t, "&ge;", ">=");
   StringReplace(t, "&le;", "<=");
   StringReplace(t, "&middot;", "-");
   StringReplace(t, "&rarr;", "->");
   StringReplace(t, "&nbsp;", " ");
   StringReplace(t, "&times;", "x");
   StringReplace(t, "&amp;", "&");
   StringReplace(t, ";", ",");
   return t;
  }

//+------------------------------------------------------------------+
//| Costi                                                             |
//+------------------------------------------------------------------+
struct CostP
  {
   string            name, sym;
   bool              on;
   double            sp[24];          // spread medio per ora dell'orologio del broker (New York + 7), in prezzo
   bool              spOk[24];        // ora misurata
   double            comm, slip;
  };
CostP  g_cp[NPRF];

double CostSpMed(const int p)
  {
   double a[];
   int n = 0;
   ArrayResize(a, 24);
   for(int h = 0; h < 24; h++)
      if(g_cp[p].spOk[h] || g_cp[p].sp[h] > 0)
         a[n++] = g_cp[p].sp[h];
   return n > 0 ? MedianOf(a, n) : 0;
  }

double CostBp(const int p)  // costo tipico del broker per trade in punti base: spread mediano + commissione + slittamento al prezzo attuale
  {
   return g_last > 0 ? (CostSpMed(p) + g_cp[p].comm + g_cp[p].slip) / g_last * 1e4 : Nan();
  }

string BpTxt(const double be) { return MathIsValidNumber(be) ? (be > 0 ? F(be, 1) + " pb" : "nessuno") : "-"; }

//+------------------------------------------------------------------+
//| Rischio/rendimento: strutture usate dagli hook                    |
//+------------------------------------------------------------------+
string RROpLab(const int i) { return (i < 5 ? "Buy" : "Sell") + " 1:" + I2S(i % 5 + 1); }

struct SqR
  {
   int               n, nY, posY, ls;
   double            yrs, win, e, tot, pf, dd, ddDays, lsMed, ls95, ddMed, dd95;
   double            be, cb;  // costo di pareggio dei trade eseguiti (punti base, dal lordo) e costo medio del profilo (punti base)
  };

int    g_ckN = 0;
int    g_ckKind[], g_ckDA[], g_ckVA[], g_ckDB[], g_ckVB[], g_ckI[], g_ckNn[];
double g_ckZ[], g_ckE[];
double g_ckZh[], g_ckZp[], g_ckBe[];  // controlli del broker peggiore: z rispetto alla stessa ora, z contro il placebo, pareggio (pb)
bool   g_ckSt[];
string g_ckLab[];

//+------------------------------------------------------------------+
//| ORB: variabili globali usate dal candidato ORB                    |
//+------------------------------------------------------------------+
bool   InpOrb = true;
string OB_OP[OB_NT] = {"Segui 1:1 (stop all'altro lato)", "Segui 1:2 (stop all'altro lato)", "Segui 1:2 (stop a meta' range)",
                       "Segui a tempo (stop all'altro lato, chiude a fine finestra)", "Fade 1:1 (obiettivo l'altro lato)",
                       "Fade 1:0,5 (obiettivo l'altro lato, stop a 2 volte)", "Fade 1:0,5 (obiettivo meta' range, stop a 2 volte)"
                      };
string OB_SIDE[3] = {"entrambi i lati", "solo rotture al rialzo", "solo rotture al ribasso"};
int    g_obNF = 1, g_obMinDay = 30;
int    g_osDay[];
int    g_otN[];
double g_otEw[], g_otZw[], g_otZp[], g_otBe[];
bool   g_otSt[];
int    g_orN = 0;
int    g_orX[];
string ObTf(const int f) { return f == 0 ? "M1" : "M5"; }
string ObCfLab(const int cf) { return "NY 09:30 (dati 16:30 / 17:30), range 30 min, finestra 120 min, conferma " + ObTf(cf % g_obNF); }
