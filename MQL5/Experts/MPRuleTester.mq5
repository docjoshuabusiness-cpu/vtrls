//+------------------------------------------------------------------+
//|                                                MPRuleTester.mq5  |
//| Verifica nello Strategy Tester delle regole esportate dallo      |
//| script MarketProfiler (scheda Strategie):                        |
//|  - entrata all'apertura della candela del timeframe della regola |
//|    quando il contesto e' vero, una posizione alla volta          |
//|  - stop K x ATR(14) (o range della candela precedente, o % del   |
//|    prezzo) dal prezzo bid di apertura, obiettivo R x stop        |
//|  - chiusura a mercato dopo L candele                             |
//| Regole ORB (scheda ORB): range dall'orario locale della piazza   |
//| (convertito con il fuso del server), entrata alla chiusura della |
//| prima candela M1 fuori dal range, stop all'altro lato o a meta', |
//| obiettivo in multipli del rischio, chiusura a fine finestra.     |
//| Contesti calcolati con le stesse definizioni dello script.       |
//| Risultati in R (profitto netto / rischio del trade) nel diario e |
//| in Common\Files\MarketProfiler_tester_<strumento>.csv            |
//+------------------------------------------------------------------+
#property version     "1.00"
#property description "Verifica con tick reali delle regole di MarketProfiler (Common\\Files\\MarketProfiler_regole_<strumento>.csv)"

#include <Trade\Trade.mqh>

enum ENUM_MP_STOP
  {
   MP_STOP_ATR = 0,  // K x ATR(14) del timeframe
   MP_STOP_PREV = 1, // K x range della candela precedente
   MP_STOP_PCT = 2   // K % del prezzo
  };
enum ENUM_MP_SRV
  {
   SRV_NY7 = 0,    // New York + 7: GMT+2/+3 con ora legale USA (FP Markets, IC Markets)
   SRV_UTC = 1,    // UTC
   SRV_EUROPE = 2, // Europa centrale: CET/CEST
   SRV_FIXED = 3   // Fisso: GMT + ore indicate sotto
  };
enum ENUM_MP_MKT
  {
   MKT_NY = 0,  // New York
   MKT_LON = 1, // Londra
   MKT_FRA = 2, // Francoforte
   MKT_TKY = 3  // Tokyo
  };

input int    InpRule      = 1;      // Regola (numero nel file; 0 = regola manuale qui sotto)
input string InpRulesFile = "";     // File delle regole in Common\Files (vuoto = MarketProfiler_regole_<strumento>.csv)
input double InpRiskMoney = 100.0;  // Rischio per trade in valuta del conto (il lotto si calcola dallo stop)
input int    InpHourShift = 0;      // Ore da aggiungere all'ora del server per l'orologio dei dati (0 se entrambi New York + 7)
input long   InpMagic     = 770077; // Magic number
input group  "Regola manuale (Regola = 0)"
input ENUM_TIMEFRAMES InpTF = PERIOD_H1; // Timeframe
input int    InpSide      = 0;      // Lato: 0 = buy, 1 = sell
input int    InpR         = 2;      // Obiettivo in multipli dello stop
input ENUM_MP_STOP InpStop = MP_STOP_ATR; // Tipo di stop
input double InpK         = 1.0;    // K dello stop
input int    InpL         = 24;     // Candele massime in posizione
input int    InpDimA      = 0;      // Contesto A (numero come nello script; 0 = tutte le candele)
input int    InpValA      = 0;      // Valore del contesto A
input int    InpDimB      = -1;     // Contesto B (-1 = nessuno)
input int    InpValB      = -1;     // Valore del contesto B
input double InpP20       = -0.001; // Candela precedente: rendimento sotto cui e' 'forte ribasso' (dal file delle regole)
input double InpP80       = 0.001;  // Candela precedente: rendimento sopra cui e' 'forte rialzo'
input group  "ORB (regole della scheda ORB)"
input ENUM_MP_SRV InpSrvTZ = SRV_NY7; // Fuso orario del server del broker
input int    InpSrvGMT    = 2;      // Solo per fuso 'Fisso': ore da GMT
input bool   InpOrbManual = false;  // Regola manuale ORB (con Regola = 0): usa i parametri qui sotto
input ENUM_MP_MKT InpOrbMkt = MKT_NY; // Piazza dell'orario di inizio
input string InpOrbStart  = "09:30"; // Inizio del range, ora locale della piazza (HH:MM)
input int    InpOrbRange  = 15;     // Durata del range in minuti
input int    InpOrbWindow = 120;    // Finestra dopo il range in minuti (poi chiusura a mercato)
input bool   InpOrbMid    = false;  // Stop a meta' range (false = all'altro lato del range)
input int    InpOrbTarget = 1;      // Obiettivo in multipli del rischio (0 = nessuno, chiude a fine finestra)
input bool   InpOrbFade   = false;  // Fade: contro la rottura (false = segui la rottura)
input int    InpOrbSides  = 2;      // Lati: 2 = entrambi, 0 = solo rotture al rialzo, 1 = solo al ribasso
input int    InpOrbDay    = -1;     // Giorno: 0 = lunedi' ... 4 = venerdi' (orologio dei dati), -1 = tutti

//--- nomi con cui i broker chiamano lo stesso strumento (come nello script)
string ALIAS_GRP[11] = {"US100,USTEC,NAS100,NDX100,USTECH,NQ100,NASDAQ100,NASDAQ",
                        "US500,SPX500,SP500,USA500,SPX",
                        "US30,DJ30,WS30,DJI30,USA30,DOW30",
                        "DE40,GER40,DE30,GER30,DAX40,DAX",
                        "UK100,FTSE100,GB100",
                        "F40,FRA40,FR40,CAC40",
                        "EU50,EUSTX50,STOXX50,EURO50,ESTX50",
                        "JP225,JPN225,NIKKEI225,N225",
                        "AUS200,AU200,ASX200",
                        "US2000,RUSSELL2000,RTY",
                        "XAUUSD,GOLD"};

string MKT_SHORT[4] = {"NY", "LDN", "FRA", "TKY"};

//--- regola
ENUM_TIMEFRAMES g_tf = PERIOD_H1;
int    g_tfSec = 3600, g_side = 0, g_R = 2, g_stop = 0, g_L = 24, g_dA = 0, g_vA = 0, g_dB = -1, g_vB = -1;
double g_K = 1, g_p20 = -0.001, g_p80 = 0.001;
string g_desc = "", g_key = "";
bool   g_ok = false;

//--- stato degli indicatori sulle candele chiuse (stesse formule dello script)
bool     g_ready = false;
int      g_k = 0;              // candele elaborate = indice della candela che si apre
datetime g_lastFed = 0;
double   g_pc = 0, g_atr = 0, g_atrSum = 0, g_e20 = 0, g_e50 = 0, g_ag = 0, g_al = 0, g_rsi = 0, g_rv = 0;
bool     g_rsiOk = false, g_rvOk = false;
double   g_tr[100];
int      g_dir = 0, g_stk = 0;
double   g_lo = 0, g_lh = 0, g_ll = 0, g_lc = 0;
int      g_ns = 1;
double   g_vBuf[], g_vSum[];
int      g_vCnt[], g_vPos[];

//--- ORB: regola e stato della giornata
bool     g_isOrb = false;
int      g_oMkt = 0, g_oStart = 570, g_oRange = 15, g_oWin = 120, g_oMid = 0, g_oK = 1, g_oMode = 1, g_oSides = 2, g_oDay = -1;
datetime g_oS0 = 0, g_oE = 0, g_oX = 0, g_oBar = 0;  // inizio del range, fine del range, fine della finestra (orario del server)
int      g_oPh = 3;                                   // 0 range in corso, 1 attesa della chiusura fuori dal range, 2 in posizione, 3 finita
double   g_oHi = 0, g_oLo = 0;

//--- posizione
datetime g_lastT = 0, g_entryT = 0;
int      g_skip = 0;
CTrade   g_trade;

//--- descrizioni delle regole (per il file dei risultati in ottimizzazione)
int      g_fh = INVALID_HANDLE;
string   g_rdesc[];

string NormU(const string s)
  {
   string u = s;
   StringToUpper(u);
   string r = "";
   int n = StringLen(u);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(u, i);
      if((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z'))
         r += ShortToString(c);
     }
   return r;
  }

string SymBase(const string sym)
  {
   string u = sym;
   StringToUpper(u);
   int n = StringLen(u), a = 0;
   while(a < n && NormU(StringSubstr(u, a, 1)) == "")
      a++;
   int b = a;
   while(b < n && NormU(StringSubstr(u, b, 1)) != "")
      b++;
   return StringSubstr(u, a, b - a);
  }

string InstrKey(const string sym)
  {
   string base = SymBase(sym);
   for(int g = 0; g < ArraySize(ALIAS_GRP); g++)
     {
      string p[];
      int k = StringSplit(ALIAS_GRP[g], ',', p);
      for(int i = 0; i < k; i++)
         if(StringFind(base, p[i]) == 0 && StringLen(base) - StringLen(p[i]) <= 4)
            return p[0];
     }
   return base;
  }

ENUM_TIMEFRAMES TfOf(const int mins)
  {
   switch(mins)
     {
      case 1:
         return PERIOD_M1;
      case 5:
         return PERIOD_M5;
      case 15:
         return PERIOD_M15;
      case 30:
         return PERIOD_M30;
      case 60:
         return PERIOD_H1;
      case 240:
         return PERIOD_H4;
      case 1440:
         return PERIOD_D1;
     }
   return PERIOD_CURRENT;
  }

string RulesFile(void) { return InpRulesFile != "" ? InpRulesFile : "MarketProfiler_regole_" + g_key + ".csv"; }

// legge la regola 'id' (e, se richiesto, le descrizioni di tutte)
bool LoadRule(const int id, const bool allDesc)
  {
   string fn = RulesFile();
   int fh = FileOpen(fn, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
     {
      PrintFormat("[MPRuleTester] file delle regole %s non trovato in Common\\Files (lancia prima lo script MarketProfiler)", fn);
      return false;
     }
   bool found = false;
   bool head = true;
   while(!FileIsEnding(fh))
     {
      string ln = FileReadString(fh);
      if(head)
        {
         head = false;
         continue;
        }
      string f[];
      if(StringSplit(ln, ';', f) < 14)
         continue;
      int rid = (int)StringToInteger(f[0]);
      if(allDesc && rid > 0)
        {
         if(ArraySize(g_rdesc) <= rid)
            ArrayResize(g_rdesc, rid + 1);
         g_rdesc[rid] = f[13];
        }
      if(rid != id)
         continue;
      g_tf = TfOf((int)StringToInteger(f[1]));
      g_side = (int)StringToInteger(f[2]);
      g_R = (int)StringToInteger(f[3]);
      g_stop = (int)StringToInteger(f[4]);
      g_K = StringToDouble(f[5]);
      g_L = (int)StringToInteger(f[6]);
      g_dA = (int)StringToInteger(f[7]);
      g_vA = (int)StringToInteger(f[8]);
      g_dB = (int)StringToInteger(f[9]);
      g_vB = (int)StringToInteger(f[10]);
      g_p20 = StringToDouble(f[11]);
      g_p80 = StringToDouble(f[12]);
      g_desc = f[13];
      g_isOrb = ArraySize(f) >= 29 && StringToInteger(f[19]) == 1;
      if(g_isOrb)
        {
         g_oMkt = (int)StringToInteger(f[20]);
         g_oStart = (int)StringToInteger(f[21]);
         g_oRange = (int)StringToInteger(f[22]);
         g_oWin = (int)StringToInteger(f[23]);
         g_oMid = (int)StringToInteger(f[24]);
         g_oK = (int)StringToInteger(f[25]);
         g_oMode = (int)StringToInteger(f[26]);
         g_oSides = (int)StringToInteger(f[27]);
         g_oDay = (int)StringToInteger(f[28]);
        }
      found = true;
     }
   FileClose(fh);
   if(!found && id > 0)
      PrintFormat("[MPRuleTester] regola %d non presente in %s", id, fn);
   return found;
  }

int OnInit(void)
  {
   g_key = InstrKey(_Symbol);
   if(InpRule > 0)
      g_ok = LoadRule(InpRule, false);
   else
      if(InpOrbManual)
        {
         string hm[];
         int k = StringSplit(InpOrbStart, ':', hm);
         g_isOrb = true;
         g_oMkt = (int)InpOrbMkt;
         g_oStart = k >= 2 ? (int)StringToInteger(hm[0]) * 60 + (int)StringToInteger(hm[1]) : -1;
         g_oRange = InpOrbRange;
         g_oWin = InpOrbWindow;
         g_oMid = InpOrbMid ? 1 : 0;
         g_oK = InpOrbTarget;
         g_oMode = InpOrbFade ? -1 : 1;
         g_oSides = InpOrbSides;
         g_oDay = InpOrbDay;
         g_desc = "regola ORB manuale";
         g_ok = true;
        }
      else
        {
         g_tf = InpTF;
         g_side = InpSide;
         g_R = InpR;
         g_stop = (int)InpStop;
         g_K = InpK;
         g_L = InpL;
         g_dA = InpDimA;
         g_vA = InpValA;
         g_dB = InpDimB;
         g_vB = InpValB;
         g_p20 = InpP20;
         g_p80 = InpP80;
         g_desc = "regola manuale";
         g_ok = true;
        }
   if(!g_ok)
      return INIT_PARAMETERS_INCORRECT;
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   if(g_isOrb)
     {
      if(g_oMkt < 0 || g_oMkt > 3 || g_oStart < 0 || g_oStart >= 1440 || g_oRange < 1 || g_oWin < 1 || g_oK < 0 ||
         (g_oMode != 1 && g_oMode != -1) || (g_oMode == -1 && g_oK < 1) || g_oSides < 0 || g_oSides > 2 || g_oDay > 6)
        {
         Print("[MPRuleTester] regola ORB non valida");
         return INIT_PARAMETERS_INCORRECT;
        }
      PrintFormat("[MPRuleTester] regola %d: %s (ORB %s %02d:%02d, range %d min, finestra %d min, stop %s, obiettivo %s, %s, lati %d, giorno %d, " +
                  "fuso del server %s)", InpRule, g_desc, MKT_SHORT[g_oMkt], g_oStart / 60, g_oStart % 60, g_oRange, g_oWin,
                  g_oMid == 1 ? "a meta' range" : "all'altro lato", g_oK > 0 ? IntegerToString(g_oK) + " volte il rischio" : "nessuno (fine finestra)",
                  g_oMode > 0 ? "segui la rottura" : "fade", g_oSides, g_oDay, EnumToString(InpSrvTZ));
      return INIT_SUCCEEDED;
     }
   g_tfSec = PeriodSeconds(g_tf);
   if(g_tfSec <= 0 || g_R < 1 || g_L < 1 || g_K <= 0 || g_dA < 0 || g_dA > 19)
     {
      Print("[MPRuleTester] regola non valida");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_ns = g_tfSec >= 86400 ? 1 : 86400 / g_tfSec;
   ArrayResize(g_vBuf, g_ns * 20);
   ArrayResize(g_vSum, g_ns);
   ArrayResize(g_vCnt, g_ns);
   ArrayResize(g_vPos, g_ns);
   ArrayInitialize(g_vSum, 0.0);
   ArrayInitialize(g_vCnt, 0);
   ArrayInitialize(g_vPos, 0);
   PrintFormat("[MPRuleTester] regola %d: %s (timeframe %s, %s 1:%d, stop %d K %.2f, max %d candele, contesto %d=%d, %d=%d)", InpRule, g_desc,
               EnumToString(g_tf), g_side == 0 ? "buy" : "sell", g_R, g_stop, g_K, g_L, g_dA, g_vA, g_dB, g_vB);
   return INIT_SUCCEEDED;
  }

//--- una candela chiusa nello stato degli indicatori (CalcATR, EMA, RSI di Wilder, serie, RVOL come nello script)
void Feed(const MqlRates &b)
  {
   double tr = g_k == 0 ? b.high - b.low : MathMax(b.high, g_pc) - MathMin(b.low, g_pc);
   if(g_k < 14)
     {
      g_atrSum += tr;
      g_atr = g_atrSum / (g_k + 1);
     }
   else
      g_atr = (g_atr * 13 + tr) / 14;
   g_tr[g_k % 100] = tr;
   double a20 = 2.0 / 21.0, a50 = 2.0 / 51.0;
   g_e20 = g_k == 0 ? b.close : a20 * b.close + (1 - a20) * g_e20;
   g_e50 = g_k == 0 ? b.close : a50 * b.close + (1 - a50) * g_e50;
   if(g_k > 0)
     {
      double ch = b.close - g_pc, g = ch > 0 ? ch : 0, lo = ch < 0 ? -ch : 0;
      if(g_k <= 14)
        {
         g_ag += g / 14.0;
         g_al += lo / 14.0;
        }
      else
        {
         g_ag = (g_ag * 13 + g) / 14.0;
         g_al = (g_al * 13 + lo) / 14.0;
        }
      if(g_k >= 14)
        {
         g_rsi = g_al > 0 ? 100 - 100 / (1 + g_ag / g_al) : 100;
         g_rsiOk = true;
        }
     }
   int d = b.close > b.open ? 1 : (b.close < b.open ? -1 : 0);
   g_stk = d == 0 ? 0 : ((g_k > 0 && g_dir == d) ? g_stk + 1 : 1);
   g_dir = d;
   //--- RVOL: volume della candela diviso la media delle 20 candele precedenti alla stessa ora
   long td = (long)b.time + (long)InpHourShift * 3600;
   int sl = g_ns == 1 ? 0 : (int)((td % 86400) / g_tfSec);
   if(sl >= g_ns)
      sl = g_ns - 1;
   double v = (double)b.tick_volume;
   g_rvOk = g_vCnt[sl] >= 20 && g_vSum[sl] > 0;
   g_rv = g_rvOk ? v / (g_vSum[sl] / 20.0) : 0;
   int x = sl * 20 + g_vPos[sl];
   if(g_vCnt[sl] >= 20)
      g_vSum[sl] -= g_vBuf[x];
   else
      g_vCnt[sl]++;
   g_vBuf[x] = v;
   g_vSum[sl] += v;
   g_vPos[sl] = (g_vPos[sl] + 1) % 20;
   g_lo = b.open;
   g_lh = b.high;
   g_ll = b.low;
   g_lc = b.close;
   g_pc = b.close;
   g_lastFed = b.time;
   g_k++;
  }

bool Warm(void)
  {
   int need = MathMax(600, 21 * g_ns + 200);
   if(need > 20000)
      need = 20000;
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int got = CopyRates(_Symbol, g_tf, 1, need, r);
   if(got < 120)
      return false;
   for(int i = 0; i < got; i++)
      Feed(r[i]);
   g_ready = true;
   PrintFormat("[MPRuleTester] %d candele %s di riscaldamento, ultima %s", got, EnumToString(g_tf), TimeToString(g_lastFed));
   return true;
  }

void FeedNew(void)
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int got = CopyRates(_Symbol, g_tf, 1, 10, r);
   for(int i = 0; i < got; i++)
      if(r[i].time > g_lastFed)
         Feed(r[i]);
  }

double MedianOf(double &a[], const int n)
  {
   if(n <= 0)
      return 0;
   double s[];
   ArrayResize(s, n);
   ArrayCopy(s, a, 0, 0, n);
   ArraySort(s);
   return n % 2 == 1 ? s[n / 2] : 0.5 * (s[n / 2 - 1] + s[n / 2]);
  }

// classe di un contesto per la candela che si apre a t0 al prezzo O con stop S (-1 = non definito), come nello script
int Ctx(const int dim, const datetime t0, const double O, const double S)
  {
   long td = (long)t0 + (long)InpHourShift * 3600;
   bool intra = g_tfSec < 86400;
   switch(dim)
     {
      case 0:
         return 0;
      case 1:
        {
         if(!intra)
            return -1;
         int h = (int)((td % 86400) / 3600);
         return g_tfSec >= 3600 ? (h / (g_tfSec / 3600)) * (g_tfSec / 3600) : h;
        }
      case 2:
         return (int)((td / 86400 + 3) % 7);
      case 3:
        {
         double rp = g_lo > 0 ? g_lc / g_lo - 1 : 0;
         return rp >= g_p80 ? 0 : (rp <= g_p20 ? 3 : (rp > 0 ? 1 : 2));
        }
      case 4:
        {
         if(!(g_atr > 0))
            return -1;
         double ra = (g_lh - g_ll) / g_atr;
         return ra < 0.75 ? 0 : (ra > 1.33 ? 2 : 1);
        }
      case 5:
        {
         double rg = g_lh - g_ll;
         if(!(rg > 0))
            return -1;
         return (int)MathMin(2.0, MathFloor(3.0 * (g_lc - g_ll) / rg));
        }
      case 6:
         return g_dir > 0 ? (g_stk >= 3 ? 0 : (g_stk == 2 ? 1 : 4)) : (g_dir < 0 ? (g_stk >= 3 ? 2 : (g_stk == 2 ? 3 : 4)) : 4);
      case 7:
        {
         if(g_k < 101)
            return -1;
         double s14 = 0, s100 = 0;
         for(int j = 1; j <= 100; j++)
           {
            double tr = g_tr[(g_k - j) % 100];
            s100 += tr;
            if(j <= 14)
               s14 += tr;
           }
         if(!(s100 > 0))
            return -1;
         double vr = (s14 / 14.0) / (s100 / 100.0);
         return vr < 0.8 ? 0 : (vr > 1.2 ? 2 : 1);
        }
      case 8:
         if(!g_rvOk)
            return -1;
         return g_rv < 0.8 ? 0 : (g_rv < 1.5 ? 1 : 2);
      case 9:
      case 10:
        {
         double ph = iHigh(_Symbol, PERIOD_D1, 1), pl = iLow(_Symbol, PERIOD_D1, 1);
         if(!(ph > 0) || !(pl > 0))
            return -1;
         int c9 = O > ph ? 0 : (O < pl ? 2 : 1);
         if(dim == 9)
            return c9;
         if(c9 != 1)
            return -1;
         double dh = (ph - O) / S, dl = (O - pl) / S;
         return (dh <= 1 && dh <= dl) ? 0 : (dl <= 1 ? 1 : 2);
        }
      case 11:
        {
         double wh = iHigh(_Symbol, PERIOD_W1, 1), wl = iLow(_Symbol, PERIOD_W1, 1);
         if(!(wh > 0) || !(wl > 0))
            return -1;
         return O > wh ? 0 : (O < wl ? 2 : 1);
        }
      case 12:
      case 13:
      case 14:
      case 15:
        {
         if(!intra)
            return -1;
         datetime d0 = (datetime)(td - td % 86400 - (long)InpHourShift * 3600);
         MqlRates m[];
         int n = CopyRates(_Symbol, PERIOD_M1, d0, (datetime)((long)t0 - 1), m);
         if(n <= 0)
            return dim == 12 ? 2 : -1;  // prima candela del giorno
         double dO = m[0].open, dH = m[0].high, dL = m[0].low, pv = 0, vv = 0;
         for(int j = 0; j < n; j++)
           {
            if(m[j].high > dH)
               dH = m[j].high;
            if(m[j].low < dL)
               dL = m[j].low;
            double w = (double)m[j].tick_volume;
            pv += (m[j].high + m[j].low + m[j].close) / 3.0 * w;
            vv += w;
           }
         if(dim == 12)
            return O >= dO ? 0 : 1;
         if(dim == 13)
            return vv > 0 ? (O >= pv / vv ? 0 : 1) : -1;
         if(dim == 14)
            return dH > dL ? (int)MathMax(0.0, MathMin(2.0, MathFloor(3.0 * (O - dL) / (dH - dL)))) : -1;
         MqlRates dd[];
         int nd = CopyRates(_Symbol, PERIOD_D1, 1, 20, dd);
         if(nd < 5)
            return -1;
         double rr[];
         ArrayResize(rr, nd);
         for(int j = 0; j < nd; j++)
            rr[j] = dd[j].high - dd[j].low;
         double med = MedianOf(rr, nd);
         if(!(med > 0))
            return -1;
         double rd = (dH - dL) / med;
         return rd < 0.5 ? 0 : (rd <= 1.0 ? 1 : 2);
        }
      case 16:
         return g_k - 1 >= 50 ? (O > g_e50 ? 0 : 1) : -1;
      case 17:
         return g_k - 1 >= 50 ? (g_e20 > g_e50 ? 0 : 1) : -1;
      case 18:
         if(!g_rsiOk)
            return -1;
         return g_rsi < 30 ? 0 : (g_rsi < 50 ? 1 : (g_rsi < 70 ? 2 : 3));
     }
   return -1;
  }

bool MyPosition(ulong &ticket)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
        {
         ticket = t;
         return true;
        }
     }
   return false;
  }

double NormPrice(const double p)
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts > 0)
      return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
   return NormalizeDouble(p, _Digits);
  }

// lotti per rischiare InpRiskMoney con lo stop a 'dist' di prezzo; risk = perdita allo stop con i lotti arrotondati
bool LotsFor(const double dist, double &lots, double &risk)
  {
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vst = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(!(tv > 0) || !(ts > 0) || !(vst > 0) || !(dist > 0))
      return false;
   double lossPerLot = dist / ts * tv;
   lots = MathFloor(InpRiskMoney / lossPerLot / vst) * vst;
   if(lots < vmin)
      lots = vmin;
   if(lots > vmax)
      lots = vmax;
   lots = NormalizeDouble(lots, (int)MathMax(0.0, MathCeil(-MathLog10(vst) - 1e-9)));
   risk = lots * lossPerLot;
   return true;
  }

//--- ORB: orari locali delle piazze convertiti giorno per giorno nell'orologio del server (come nello script)
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

// ore di differenza da UTC dell'orologio del server
int SrvOffset(const datetime t)
  {
   if(InpSrvTZ == SRV_NY7)
      return IsUSDST(t) ? 3 : 2;
   if(InpSrvTZ == SRV_UTC)
      return 0;
   if(InpSrvTZ == SRV_EUROPE)
      return IsEUDST(t) ? 2 : 1;
   return InpSrvGMT;
  }

datetime LocalToServer(const long day, const int mkt, const int mins)
  {
   datetime t = (datetime)(day * 86400 + (long)mins * 60);
   return t + (SrvOffset(t) - MktOffset(mkt, t)) * 3600;
  }

int DowMon(const datetime t) { return (int)(((long)t / 86400 + 3) % 7); }  // 0 = lunedi'

// prossima giornata ORB: la prima la cui finestra finisce dopo 'now', diversa dall'ultima
void OrbNext(const datetime now)
  {
   long dl = ((long)now - (long)(SrvOffset(now) - MktOffset(g_oMkt, now)) * 3600) / 86400;
   for(long d = dl - 1; d <= dl + 1; d++)
     {
      datetime s0 = LocalToServer(d, g_oMkt, g_oStart);
      if(s0 <= g_oS0 || (long)s0 + (long)(g_oRange + g_oWin) * 60 <= (long)now)
         continue;
      g_oS0 = s0;
      g_oE = (datetime)((long)s0 + g_oRange * 60);
      g_oX = (datetime)((long)g_oE + g_oWin * 60);
      g_oPh = now < g_oE ? 0 : 3;  // EA avviato a range gia' finito: la giornata si salta
      return;
     }
  }

// ORB: range dall'inizio, entrata all'apertura della candela M1 dopo la prima chiusura fuori dal range, chiusura a fine finestra
void OrbTick(void)
  {
   datetime now = TimeCurrent();
   ulong tk = 0;
   if(g_oPh == 2)
     {
      if(!MyPosition(tk))
         g_oPh = 3;  // chiusa da stop o obiettivo
      else
        {
         if(now >= g_oX)
           {
            g_trade.PositionClose(tk);
            g_oPh = 3;
           }
         return;
        }
     }
   if(g_oPh == 3)
      OrbNext(now);
   if(g_oPh == 0)
     {
      if(now < g_oE)
         return;
      //--- range: candele M1 dall'inizio alla fine del range (almeno meta', la prima entro 2 minuti dall'inizio), come nello script
      g_oPh = 3;
      if(g_oDay >= 0 && DowMon((datetime)((long)g_oS0 + (long)InpHourShift * 3600)) != g_oDay)
         return;
      MqlRates r[];
      int n = CopyRates(_Symbol, PERIOD_M1, g_oS0, (datetime)((long)g_oE - 1), r);
      if(n < MathMax(1, g_oRange / 2) || (long)r[0].time - (long)g_oS0 >= 120)
         return;
      g_oHi = r[0].high;
      g_oLo = r[0].low;
      for(int i = 1; i < n; i++)
        {
         if(r[i].high > g_oHi)
            g_oHi = r[i].high;
         if(r[i].low < g_oLo)
            g_oLo = r[i].low;
        }
      if(!(g_oHi > g_oLo))
         return;
      g_oBar = iTime(_Symbol, PERIOD_M1, 0);
      g_oPh = 1;
      return;
     }
   if(g_oPh != 1)
      return;
   //--- a ogni nuova candela M1: la precedente ha chiuso fuori dal range?
   datetime b0 = iTime(_Symbol, PERIOD_M1, 0);
   if(b0 == 0 || b0 == g_oBar)
      return;
   g_oBar = b0;
   if(b0 >= g_oX)
     {
      g_oPh = 3;  // finestra finita senza chiusure fuori dal range
      return;
     }
   double c1 = iClose(_Symbol, PERIOD_M1, 1);
   if(iTime(_Symbol, PERIOD_M1, 1) < g_oE || !(c1 > g_oHi || c1 < g_oLo))
      return;
   int d = c1 > g_oHi ? 1 : -1;
   g_oPh = 3;
   if((g_oSides == 0 && d != 1) || (g_oSides == 1 && d != -1))
      return;
   //--- stop all'altro lato o a meta' range; obiettivo K volte il rischio dal bid di entrata (fade: stop e obiettivo scambiati)
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sp = g_oMid == 1 ? 0.5 * (g_oHi + g_oLo) : (d > 0 ? g_oLo : g_oHi);
   double rr = d * (bid - sp);
   if(!(rr > 0))
      return;
   int dir = d * g_oMode;
   double sl = g_oMode > 0 ? sp : bid + d * g_oK * rr;
   double tp = g_oMode > 0 ? (g_oK > 0 ? bid + d * g_oK * rr : 0) : sp;
   double lots = 0, risk = 0;
   if(!LotsFor(g_oMode > 0 ? rr : g_oK * rr, lots, risk))
      return;
   sl = NormPrice(sl);
   if(tp > 0)
      tp = NormPrice(tp);
   double lvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double ref = dir > 0 ? bid : ask;
   if(MathAbs(ref - sl) < lvl || (tp > 0 && MathAbs(ref - tp) < lvl))
     {
      g_skip++;
      return;
     }
   string cm = "MP r=" + DoubleToString(risk, 2);
   bool ok = dir > 0 ? g_trade.Buy(lots, _Symbol, 0, sl, tp, cm) : g_trade.Sell(lots, _Symbol, 0, sl, tp, cm);
   if(ok)
      g_oPh = 2;
  }

void OnTick(void)
  {
   if(!g_ok)
      return;
   if(g_isOrb)
     {
      OrbTick();
      return;
     }
   datetime t0 = iTime(_Symbol, g_tf, 0);
   if(t0 == 0 || t0 == g_lastT)
      return;
   if(!g_ready && !Warm())
      return;
   g_lastT = t0;
   FeedNew();
   //--- chiusura a tempo: dopo L candele dalla candela di entrata
   ulong tk = 0;
   if(MyPosition(tk))
     {
      int sh = iBarShift(_Symbol, g_tf, g_entryT, false);
      if(sh >= g_L)
         g_trade.PositionClose(tk);
      else
         return;
     }
   if(g_k < 20 || MyPosition(tk))
      return;
   //--- entrata: prezzo bid all'apertura della candela, stop e obiettivo misurati da li' (come nello script)
   double O = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double S = g_stop == MP_STOP_ATR ? g_K * g_atr : (g_stop == MP_STOP_PREV ? g_K * (g_lh - g_ll) : g_K / 100.0 * O);
   if(!(S > 0) || !(O > 0))
      return;
   if(Ctx(g_dA, t0, O, S) != g_vA)
      return;
   if(g_dB >= 0 && Ctx(g_dB, t0, O, S) != g_vB)
      return;
   double lots = 0, risk = 0;
   if(!LotsFor(S, lots, risk))
      return;
   double sl = NormPrice(g_side == 0 ? O - S : O + S), tp = NormPrice(g_side == 0 ? O + g_R * S : O - g_R * S);
   double lvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double ref = g_side == 0 ? O : ask;
   if(MathAbs(ref - sl) < lvl || MathAbs(ref - tp) < lvl)
     {
      g_skip++;
      return;
     }
   string cm = "MP r=" + DoubleToString(risk, 2);
   bool ok = g_side == 0 ? g_trade.Buy(lots, _Symbol, 0, sl, tp, cm) : g_trade.Sell(lots, _Symbol, 0, sl, tp, cm);
   if(ok)
      g_entryT = t0;
  }

//--- risultati in R dalla storia delle operazioni
struct MpStat
  {
   int               n, wins, ls;
   double            e, tot, pf, dd, yrs, costR;
  };

void Stats(MpStat &st)
  {
   ZeroMemory(st);
   if(!HistorySelect(0, TimeCurrent() + 86400))
      return;
   int nd = HistoryDealsTotal();
   long pid[];
   double prof[], risk[], cost[];
   datetime tin[];
   int np = 0;
   for(int i = 0; i < nd; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic || HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol)
         continue;
      long id = HistoryDealGetInteger(d, DEAL_POSITION_ID);
      int x = -1;
      for(int j = np - 1; j >= 0 && j >= np - 5; j--)
         if(pid[j] == id)
           {
            x = j;
            break;
           }
      if(x < 0)
        {
         x = np++;
         ArrayResize(pid, np, 1024);
         ArrayResize(prof, np, 1024);
         ArrayResize(risk, np, 1024);
         ArrayResize(cost, np, 1024);
         ArrayResize(tin, np, 1024);
         pid[x] = id;
         prof[x] = 0;
         risk[x] = 0;
         cost[x] = 0;
         tin[x] = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
        }
      double c = HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_FEE);
      prof[x] += HistoryDealGetDouble(d, DEAL_PROFIT) + c;
      cost[x] += c;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
        {
         string cm = HistoryDealGetString(d, DEAL_COMMENT);
         int k = StringFind(cm, "r=");
         if(k >= 0)
            risk[x] = StringToDouble(StringSubstr(cm, k + 2));
        }
     }
   double gp = 0, gl = 0, eq = 0, pk = 0, cs = 0;
   int cur = 0;
   for(int j = 0; j < np; j++)
     {
      double rk = risk[j] > 0 ? risk[j] : InpRiskMoney;
      double r = prof[j] / rk;
      st.n++;
      st.tot += r;
      cs += cost[j] / rk;
      if(r > 0)
        {
         st.wins++;
         gp += r;
         cur = 0;
        }
      else
        {
         gl -= r;
         cur++;
         if(cur > st.ls)
            st.ls = cur;
        }
      eq += r;
      if(eq > pk)
         pk = eq;
      else
         if(pk - eq > st.dd)
            st.dd = pk - eq;
     }
   if(st.n > 0)
     {
      st.e = st.tot / st.n;
      st.costR = cs / st.n;
      st.yrs = MathMax(((double)tin[np - 1] - (double)tin[0]) / (365.25 * 86400.0), 1.0 / 12);
     }
   st.pf = gl > 0 ? gp / gl : 0;
  }

string I2S(const long x) { return IntegerToString(x); }
string D2(const double x, const int d) { string t = DoubleToString(x, d); StringReplace(t, ".", ","); return t; }  // virgola decimale (Excel)

string ResLine(const int rule, const string desc, MpStat &st)
  {
   return I2S(rule) + ";" + desc + ";" + _Symbol + ";" + I2S(st.n) + ";" + D2(st.n > 0 ? 100.0 * st.wins / st.n : 0, 1) + ";" + D2(st.e, 4) + ";" +
          D2(st.tot, 2) + ";" + D2(st.yrs > 0 ? st.tot / st.yrs : 0, 2) + ";" + D2(st.pf, 2) + ";" + I2S(st.ls) + ";" + D2(st.dd, 2) + ";" +
          D2(st.costR, 4);
  }

int OpenRes(void)
  {
   string fn = "MarketProfiler_tester_" + g_key + ".csv";
   int fh = FileOpen(fn, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return fh;
   if(FileSize(fh) == 0)
      FileWriteString(fh, "Regola;Descrizione;Simbolo;Trade;% vinti;R per trade;R totali;R all'anno;Profit factor;Serie di perdite max;" +
                      "Drawdown max R;Costi medi R (commissioni e swap)\n");
   FileSeek(fh, 0, SEEK_END);
   return fh;
  }

double OnTester(void)
  {
   MpStat st;
   Stats(st);
   PrintFormat("[MPRuleTester] regola %d (%s): %d trade, vinti %.1f%%, %.3f R per trade, totale %.1f R, profit factor %.2f, serie di perdite %d, " +
               "drawdown %.1f R, costi medi %.3f R, saltati per distanza minima degli stop %d", InpRule, g_desc, st.n,
               st.n > 0 ? 100.0 * st.wins / st.n : 0, st.e, st.tot, st.pf, st.ls, st.dd, st.costR, g_skip);
   if(MQLInfoInteger(MQL_OPTIMIZATION))
     {
      double data[10];
      data[0] = InpRule;
      data[1] = st.n;
      data[2] = st.wins;
      data[3] = st.e;
      data[4] = st.tot;
      data[5] = st.pf;
      data[6] = st.ls;
      data[7] = st.dd;
      data[8] = st.yrs;
      data[9] = st.costR;
      FrameAdd("mp", InpRule, st.e, data);
     }
   else
     {
      int fh = OpenRes();
      if(fh != INVALID_HANDLE)
        {
         FileWriteString(fh, ResLine(InpRule, g_desc, st) + "\n");
         FileClose(fh);
        }
     }
   return st.n >= 10 ? st.e : -1;
  }

//--- ottimizzazione su 'Regola': i risultati di ogni passaggio arrivano al terminale come frame
void OnTesterInit(void)
  {
   g_key = InstrKey(_Symbol);
   ArrayResize(g_rdesc, 0);
   LoadRule(-1, true);
   g_fh = OpenRes();
  }

void OnTesterPass(void)
  {
   ulong pass;
   string name;
   long id;
   double value;
   double data[];
   while(FrameNext(pass, name, id, value, data))
     {
      if(ArraySize(data) < 10 || g_fh == INVALID_HANDLE)
         continue;
      MpStat st;
      st.n = (int)data[1];
      st.wins = (int)data[2];
      st.e = data[3];
      st.tot = data[4];
      st.pf = data[5];
      st.ls = (int)data[6];
      st.dd = data[7];
      st.yrs = data[8];
      st.costR = data[9];
      int rule = (int)data[0];
      string desc = rule > 0 && rule < ArraySize(g_rdesc) ? g_rdesc[rule] : "";
      FileWriteString(g_fh, ResLine(rule, desc, st) + "\n");
     }
  }

void OnTesterDeinit(void)
  {
   if(g_fh != INVALID_HANDLE)
     {
      FileClose(g_fh);
      g_fh = INVALID_HANDLE;
      Print("[MPRuleTester] risultati in Common\\Files\\MarketProfiler_tester_", g_key, ".csv");
     }
  }
//+------------------------------------------------------------------+
