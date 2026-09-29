//+------------------------------------------------------------------+
//|                                              MarketProfiler.mq5  |
//|  Analisi descrittiva di uno strumento, timeframe per timeframe.   |
//|  Output: report HTML a schede in MQL5\Files (o Common\Files).     |
//|                                                                  |
//|  Schede: Panoramica, Riepilogo, Minuto, Ora, 4/6/8/12 ore,        |
//|  Giorno, Settimana, 2 settimane, Mese, Trimestre, Semestre, Anno,|
//|  Sessioni, ORB a tutti gli orari, Livelli, Direzione, R/R lordo  |
//|  e netto per broker, Coppie di contesti, Strategie, Swing,        |
//|  Rotture, Impulsi, Notizie, Gap, Volume, Testi da copiare. File:  |
//|  CSV dei contesti e dell'ORB, regole per l'EA MPRuleTester.       |
//|  Controlli dei trade simulati (ORB, R/R, coppie, strategie):      |
//|  placebo con direzione a caso nello stesso istante, confronto     |
//|  con la stessa ora, costo di pareggio e livelli di costo in punti |
//|  base del prezzo (parametro 'Costi: livelli'). ORB con candela di |
//|  conferma M1, M5, M15, M30, H1: quanto continua dopo la chiusura, |
//|  in quanto tempo, forza, velocita' e volatilita' della stessa ora;|
//|  eventi sulle candele (solo tocchi, continua, rientra e resta,    |
//|  riparte, si gira) contro le stesse barre a direzione casuale,     |
//|  a che ora e su che timeframe, falsi segnali tra timeframe.        |
//|  Orari chiave di New York, Londra, Francoforte e Tokyo           |
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
enum ENUM_LV_LOW
  {
   LV_LOW_NONE = 0, // Solo 4 ore e oltre
   LV_LOW_H1 = 1,   // Anche 2 ore e 1 ora
   LV_LOW_M15 = 2   // Anche 2 ore, 1 ora, 30 e 15 minuti (scalping)
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
enum ENUM_RR_STOP
  {
   RR_STOP_ATR = 0,  // K x ATR(14) del timeframe
   RR_STOP_PREV = 1, // K x range della candela precedente
   RR_STOP_PCT = 2   // K % del prezzo
  };
enum ENUM_COST_SRC
  {
   COST_AUTO = 0,   // Automatica: misura nel terminale del broker o profilo salvato, altrimenti i valori manuali
   COST_MANUAL = 1  // Manuale: solo i valori indicati sotto
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
input bool   InpOrb          = true;  // ORB: rottura del range iniziale a tutti gli orari (quando rompe, quanto corre, segui o fade)
input int    InpOrbStep      = 15;    // ORB: passo degli orari di inizio in minuti, su tutta la giornata
input string InpOrbRanges    = "5,15,30,60";  // ORB: durate del range iniziale in minuti (separate da virgola, al massimo 6)
input string InpOrbWindows   = "60,120,240";  // ORB: finestre dopo il range in minuti, poi chiusura a mercato (al massimo 6)
input string InpOrbConfirm   = "1,5,15,30,60"; // ORB: candele di conferma in minuti (1 = prima chiusura M1 fuori dal range; 5, 15, 30, 60 = chiusura della candela M5, M15, M30, H1)
input bool   InpOrbRandom    = true;  // ORB: eventi attesi con le stesse barre a direzione casuale (placebo degli eventi; circa il doppio del tempo dell'ORB)
input bool   InpOrbAllClocks = true;  // ORB: orari locali di tre piazze (ora legale USA, europea, nessuna) invece della sola piazza di riferimento
input double InpOrbRuleZ     = 3.0;   // ORB: z minimo netto del broker peggiore per esportare una regola (le combinazioni sono decine di migliaia)
input int    InpOrbRules     = 10;    // ORB: regole esportate per lo Strategy Tester al massimo
input bool   InpSkipIncomplete = false; // Escludi i primi anni con copertura oraria incompleta (false = analizza tutto lo storico)
input bool   InpRollSkip     = true;  // Rollover (NY 17:00 = mezzanotte del broker): niente entrate nella finestra, operazioni intraday chiuse prima (R/R fino a H1, ORB)
input int    InpRollPre      = 15;    // Rollover: minuti della finestra prima di NY 17:00
input int    InpRollPost     = 60;    // Rollover: minuti della finestra dopo NY 17:00
input double InpLevelR       = 0.10;  // Livelli: distanza di reazione r (frazione del range mediano del periodo)
input ENUM_LV_LOW InpLevelLowTF = LV_LOW_NONE; // Livelli: timeframe sotto le 4 ore
input int    InpLvFollow     = 3;     // Livelli: candele osservate dopo una chiusura oltre il livello (conferma, falsa, ritest)
input int    InpBaseDraws    = 20;    // Sessioni: estrazioni casuali mediate per il valore atteso
input ENUM_RR_STOP InpRRStop = RR_STOP_ATR; // Rischio/rendimento: tipo di stop
input double InpRRStopK      = 1.0;   // Rischio/rendimento: K dello stop
input int    InpRRMaxBars    = 24;    // Rischio/rendimento: candele massime in posizione (poi chiusura a mercato)
input string InpB1Name       = "FP Markets"; // Broker 1: nome (deve comparire nel nome del server del conto per la misura automatica)
input string InpB1Sym        = "";    // Broker 1: simbolo nel suo terminale (vuoto = cerca, es. US100 / USTEC / NAS100)
input ENUM_COST_SRC InpB1Src = COST_AUTO; // Broker 1: fonte dei costi
input double InpB1Spread     = 0.0;   // Broker 1: spread manuale in prezzo (usato se non misurato)
input double InpB1Comm       = 0.0;   // Broker 1: commissione per lotto, andata e ritorno, valuta del conto
input double InpB1SwapL      = 0.0;   // Broker 1: swap buy per notte in prezzo, manuale (negativo = paghi)
input double InpB1SwapS      = 0.0;   // Broker 1: swap sell per notte in prezzo, manuale (negativo = paghi)
input double InpB1Slip       = 0.0;   // Broker 1: slittamento per trade in prezzo (entrata + uscita)
input string InpB2Name       = "IC Markets"; // Broker 2: nome
input string InpB2Sym        = "";    // Broker 2: simbolo nel suo terminale (vuoto = cerca)
input ENUM_COST_SRC InpB2Src = COST_AUTO; // Broker 2: fonte dei costi
input double InpB2Spread     = 0.0;   // Broker 2: spread manuale in prezzo
input double InpB2Comm       = 0.0;   // Broker 2: commissione per lotto, andata e ritorno, valuta del conto
input double InpB2SwapL      = 0.0;   // Broker 2: swap buy per notte in prezzo, manuale
input double InpB2SwapS      = 0.0;   // Broker 2: swap sell per notte in prezzo, manuale
input double InpB2Slip       = 0.0;   // Broker 2: slittamento per trade in prezzo
input string InpCostBp       = "0.5,1,2,4"; // Costi: livelli per trade in punti base del prezzo (1 = 0,01%; virgola tra i valori, punto per i decimali): a quale costo il vantaggio sparisce
input bool   InpRRCombo      = true;  // Rischio/rendimento: coppie di contesti (tabella, riepilogo, CSV)
input int    InpComboMinTF   = 15;    // Coppie di contesti: timeframe minimo in minuti (5 = anche M5, molto piu' lento)
input int    InpSeqTop       = 5;     // Strategie: contesti singoli e coppie migliori simulati una posizione alla volta, per timeframe
input double InpRuleMinZ     = 2.0;   // Regole per lo Strategy Tester: z minimo dell'aspettativa netta del broker peggiore
input int    InpSpreadDays   = 20;    // Costi: giorni di tick per lo spread per ora (0 = spread delle barre M1)
input bool   InpCostsOnly    = false; // Solo misura dei costi del broker di questo terminale (salva il profilo e termina)

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
   int               sp[];  // spread della barra in punti (0 se non registrato)
   int               n;
   bool              hasVol, truncated;
                     CSeries(void) { n = 0; hasVol = false; truncated = false; }
   void              Free(void)
     {
      ArrayFree(t); ArrayFree(o); ArrayFree(h); ArrayFree(l); ArrayFree(c); ArrayFree(v); ArrayFree(sp);
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
         ArrayResize(c, n, reserve); ArrayResize(v, n, reserve); ArrayResize(vr, n, reserve); ArrayResize(sp, n, reserve);
         for(int i = 0; i < got; i++)
           {
            int k = base + i;
            t[k] = r[i].time; o[k] = r[i].open; h[k] = r[i].high; l[k] = r[i].low; c[k] = r[i].close;
            v[k] = (double)r[i].tick_volume;
            vr[k] = (double)r[i].real_volume;
            sp[k] = r[i].spread;
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

//--- testo lungo a blocchi (appendici del rapporto con tutti i risultati): ogni blocco resta piccolo, quindi aggiungere righe
//--- costa poco anche con milioni di caratteri; si scrive nel file un blocco alla volta
class CText
  {
public:
   string            c[];
   int               n, len;
                     CText(void) { n = 0; len = 0; }
   void              Add(const string s)
     {
      if(n == 0 || len > 65536)
        {
         if(n >= ArraySize(c))
            ArrayResize(c, n + 64);
         c[n] = "";
         n++;
         len = 0;
        }
      c[n - 1] += s + "\n";
      len += StringLen(s) + 1;
     }
   void              Clear(void) { ArrayFree(c); n = 0; len = 0; }
  };
CText  g_txHiAll, g_txOrbAll, g_txCbAll;  // appendici: tutti i risultati oltre |z| 2, tutte le combinazioni ORB, tutte le coppie
void   WT(CText &t) { for(int i = 0; i < t.n; i++) W(t.c[i]); }
// z = di quante deviazioni standard un valore si allontana dall'atteso (|z| < 2 compatibile con il caso, |z| >= 3 difficile)
string ZS(const double z) { if(!MathIsValidNumber(z)) return "-"; return (z >= 0 ? "+" : "") + DoubleToString(z, 1); }
double ZProp(const double p, const double p0, const double n)  // proporzione p su n casi contro l'atteso p0
  {
   if(!MathIsValidNumber(p) || !MathIsValidNumber(p0) || n <= 0 || p0 <= 0 || p0 >= 1)
      return MathArcsin(2.0);
   return (p - p0) / MathSqrt(p0 * (1 - p0) / n);
  }
double Z2(const double p1, const double n1, const double p2, const double n2)  // differenza tra due proporzioni
  {
   if(!MathIsValidNumber(p1) || !MathIsValidNumber(p2) || n1 <= 0 || n2 <= 0)
      return MathArcsin(2.0);
   double pb = (p1 * n1 + p2 * n2) / (n1 + n2);
   double v = pb * (1 - pb) * (1.0 / n1 + 1.0 / n2);
   return v > 0 ? (p1 - p2) / MathSqrt(v) : MathArcsin(2.0);
  }
double ArcF(const double x) { return 2.0 / M_PI * MathArcsin(MathSqrt(MathMax(0.0, MathMin(1.0, x)))); }  // legge dell'arcoseno

//--- riepilogo: ogni z calcolato nelle schede viene contato; quelli con |z| >= 2 sono conservati con il loro testo
#define HI_NMOD 20
string HI_NAME[HI_NMOD] = {"Sessioni e orari chiave (reale contro atteso con direzione casuale)",
                           "Livelli: effetto del livello (reale contro livello finto)",
                           "Vita dei livelli (reale contro livello finto)",
                           "Livelli letti sui timeframe inferiori (reale contro livello finto)",
                           "Direzione (condizione contro tutti i periodi)",
                           "Rischio/rendimento lordo (aspettativa contro zero)", "", "",
                           "Coppie di contesti (aspettativa netta del broker peggiore contro zero)",
                           "ORB a tutti gli orari e con ogni candela di conferma (segui la rottura 1:1, aspettativa lorda contro zero, che per 1:1 e' anche il placebo; z negativo = la rottura fallisce: fade)",
                           "Rischio/rendimento lordo: il contesto contro la stessa ora (cosa aggiunge all'orario; D1: contro tutte le candele)",
                           "Rischio/rendimento lordo: la direzione conta (buy contro sell nello stesso istante, stesso stop e obiettivo: contro il placebo)",
                           "ORB: dopo la chiusura di conferma il prezzo va piu' a favore che contro (estensione a favore contro quella contraria: placebo)",
                           "ORB: eventi dopo il range per candela di conferma (reale contro atteso con le stesse barre a direzione casuale)",
                           "Persistenza per timeframe (rapporto di varianza contro 1: sopra = i movimenti continuano, sotto = tornano indietro)",
                           "Persistenza per ora del giorno (il movimento prima continua dopo? seguito medio contro zero)",
                           "Timeframe alto -> basso: stati singoli della candela alta (stato contro tutte le altre candele)",
                           "Timeframe alto -> basso: coppie di stati della candela alta (coppia contro tutte le altre candele)", "", ""};
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
   double upShare = m > 0 ? (double)nUp / m : Nan();
   double sameBase = upShare * upShare + (1 - upShare) * (1 - upShare);  // stessa direzione dovuta solo alla prevalenza dei rialzi
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
   Kpi("Periodo dopo nella stessa direzione", FP(sameAll, 1) + "%", "con la sola prevalenza dei rialzi: " + FP(sameBase, 1) + "%");
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
   R(g_rep, "Il periodo successivo va nella stessa direzione nel " + FP(sameAll, 1) + "% dei casi (con la sola prevalenza dei periodi " +
     "rialzisti, senza legame tra un periodo e il successivo, sarebbe " + FP(sameBase, 1) + "%).");
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
                TD(b.intra ? ModeOf(b, false) : "&ndash;") + TDc(FP(sameAll, 1) + " (" + FP(sameBase, 1) + ")", PCol(sameAll, sameBase, 0.1)) + "</tr>";
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
         double r1 = (a12[k] > 0 && n4w[k] > 0) ? a4w[k] / a12[k] : Nan(), r2 = (a12[k] > 0 && nl[k] > 0) ? al[k] / a12[k] : Nan();
         W("<tr>" + TD(HourLab(k)) + TD(HBar(a12[k], mx, DoubleToString(a12[k], 0))) +
           TD(n4w[k] > 0 ? HBar(a4w[k], mx, DoubleToString(a4w[k], 0)) : "&ndash;") + TD(nl[k] > 0 ? HBar(al[k], mx, DoubleToString(al[k], 0)) : "&ndash;") +
           TDc(F(r1, 2) + "&times;", PCol(r1, 1.0, 0.6)) + TDc(F(r2, 2) + "&times;", PCol(r2, 1.0, 0.6)) + "</tr>");
         R(g_repVol, "  " + HourLab(k) + ": volume medio 12 mesi " + DoubleToString(a12[k], 0) + ", ultime 4 settimane " +
           (n4w[k] > 0 ? DoubleToString(a4w[k], 0) + " (" + F(r1, 2) + "x)" : "- (nessuna barra)") + ", ultima sessione " +
           (nl[k] > 0 ? DoubleToString(al[k], 0) : "-") + ".");
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
int      g_covY0 = 0, g_covY1 = 0;   // primi anni con copertura oraria incompleta (g_covY0 = 0: nessuno)
double   g_covHrs = 0, g_covRef = 0;  // ore al giorno coperte in quegli anni e negli anni recenti
bool     g_covMiss[24];               // ore della giornata che in quegli anni mancano spesso
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

// primo anno con copertura oraria completa: in alcuni storici i primi anni coprono solo parte della giornata;
// g_covY0-g_covY1 = anni incompleti, g_covHrs / g_covRef = ore al giorno coperte, g_covMiss = ore che mancano spesso
datetime CoverageStart(CSeries &h)
  {
   g_covY0 = 0;
   g_covY1 = 0;
   ArrayInitialize(g_covMiss, false);
   if(h.n < 2000)
      return 0;
   MqlDateTime d;
   TimeToStruct(h.t[0], d);
   int y0 = d.year;
   TimeToStruct(h.t[h.n - 1], d);
   int y1 = d.year;
   int ny = y1 - y0 + 1;
   double hrs[], days[], hy[];  // hy = giorni con almeno una barra H1 in quell'ora, per anno e ora
   ArrayResize(hrs, ny);
   ArrayResize(days, ny);
   ArrayResize(hy, ny * 24);
   ArrayInitialize(hrs, 0.0);
   ArrayInitialize(days, 0.0);
   ArrayInitialize(hy, 0.0);
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
      hy[(yc - y0) * 24 + HourOf(h.t[i])] += 1;
     }
   double ref = 0, rd = 0;
   double rh[24];
   ArrayInitialize(rh, 0.0);
   int nr = 0;
   for(int y = y1; y >= y0 && nr < 3; y--)
      if(days[y - y0] >= 50)
        {
         ref += hrs[y - y0] / days[y - y0];
         rd += days[y - y0];
         for(int k = 0; k < 24; k++)
            rh[k] += hy[(y - y0) * 24 + k];
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
   double th = 0, td = 0;
   double ih[24];
   ArrayInitialize(ih, 0.0);
   for(int y = y0; y < ys; y++)
     {
      th += hrs[y - y0];
      td += days[y - y0];
      for(int k = 0; k < 24; k++)
         ih[k] += hy[(y - y0) * 24 + k];
     }
   g_covY0 = y0;
   g_covY1 = ys - 1;
   g_covHrs = th / MathMax(td, 1.0);
   g_covRef = ref;
   // manca spesso = presente in meno della meta' dei giorni rispetto agli anni recenti (solo ore di solito aperte)
   for(int k = 0; k < 24; k++)
      g_covMiss[k] = rh[k] / rd >= 0.5 && ih[k] / MathMax(td, 1.0) < 0.5 * rh[k] / rd;
   MqlDateTime a;
   ZeroMemory(a);
   a.year = ys;
   a.mon = 1;
   a.day = 1;
   return StructToTime(a);
  }

// testo sugli anni incompleti (dopo RefSetup: le ore hanno l'etichetta della piazza di riferimento)
string CoverageText(const bool excluded)
  {
   if(g_covY0 <= 0)
      return "";
   string yrs = I2S(g_covY0) + (g_covY1 > g_covY0 ? "-" + I2S(g_covY1) : "");
   string miss = "";
   for(int k = 0; k < 24; k++)
     {
      if(!g_covMiss[k] || (k > 0 && g_covMiss[k - 1]))
         continue;
      int e = k;
      while(e < 23 && g_covMiss[e + 1])
         e++;
      miss += (miss != "" ? ", " : "") + HourLab(k) + (e > k ? " - " + HourLab(e) : "");
     }
   string s = "Anni " + yrs + (excluded ? " esclusi dall'analisi" : " inclusi ma incompleti") + ": coprono in media " +
              F(g_covHrs, 1) + " ore al giorno contro " + F(g_covRef, 1) + " degli anni recenti" +
              (miss != "" ? " (mancano spesso le ore " + miss + ")" : "") + ".";
   if(excluded)
      return s + " Per includerli: parametro 'Escludi i primi anni con copertura oraria incompleta' = false.";
   return s + " Nelle ore mancanti il prezzo salta da una barra all'altra: in quegli anni impulsi, gap, statistiche per ora, sessioni " +
          "e livelli di 4 e 8 ore sono meno affidabili (per escluderli: parametro 'Escludi i primi anni con copertura oraria incompleta' = true).";
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
   int sp2[];
   bool hasSp = ArraySize(s.sp) == s.n;
   if(hasSp)
      ArrayCopy(sp2, s.sp, 0, k, m);
   ArrayFree(s.t); ArrayFree(s.o); ArrayFree(s.h); ArrayFree(s.l); ArrayFree(s.c); ArrayFree(s.v); ArrayFree(s.sp);
   ArrayCopy(s.t, t2);
   ArrayCopy(s.o, o2);
   ArrayCopy(s.h, h2);
   ArrayCopy(s.l, l2);
   ArrayCopy(s.c, c2);
   ArrayCopy(s.v, v2);
   if(hasSp)
      ArrayCopy(s.sp, sp2);
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
   int n = 0, nn = 0, k15 = 0, n15 = 0, k60 = 0, n60 = 0, nr = 0, kr = 0;
   double a[];
   ArrayResize(a, g_imN);
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
        {
         nr++;
         if(g_imRt[e] >= 1.0)
            kr++;
        }
     }
   if(n < 3)
      return;
   double med = MedianOf(a, n);
   double p15 = n15 > 0 ? (double)k15 / n15 : Nan(), p60 = n60 > 0 ? (double)k60 / n60 : Nan();
   double rtp = nr > 0 ? (double)kr / nr : Nan();
   string mn = withNews ? MostNews(m) : "";
   W("<tr>" + TD(label) + TD(I2S(n)) + TD(FP((double)n / g_imN, 1)) + TD(FP(med, 3)) + TD(PX(med * g_last)) +
     TD(FP((double)nn / n, 1)) + TDc(FP(p15, 1), PCol(p15, 0.5, 0.15)) + TDc(FP(p60, 1), PCol(p60, 0.5, 0.15)) +
     TDc(FP(rtp, 1), PCol(-rtp, -0.5, 0.2)) + (withNews ? TD(mn) : "") + "</tr>");
   R(g_repEv, "    " + label + ": N " + I2S(n) + " (" + FP((double)n / g_imN, 1) + "% degli impulsi), dimensione mediana " + FP(med, 3) +
     "% (circa " + PX(med * g_last) + "), con notizia " + FP((double)nn / n, 1) + "%, continua dopo 15 min " + FP(p15, 1) +
     "%, dopo 60 min " + FP(p60, 1) + "%, torna all'origine entro 60 min " + FP(rtp, 1) + "%" + (withNews ? ", notizia pi&ugrave; frequente " + mn : ""));
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
      g_imHr[e] = HourOf(s.t[i]);   // barra in cui l'impulso supera la soglia (es. 15:30 per un dato delle 8:30 NY)
      g_imMd[e] = MinOfDay(s.t[i]);
      g_imDw[e] = DowMon(s.t[i]);
      MqlDateTime d;
      TimeToStruct(s.t[i], d);
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
            "<b>Continua</b> = dopo 15/60 minuti il prezzo &egrave; oltre la chiusura dell'impulso nella sua direzione. <b>Torna all'origine</b> = " +
            "entro 60 minuti il prezzo ritorna al livello da cui l'impulso era partito. Orari = barra in cui l'impulso supera la soglia.");
   THead("Condizione|N|% degli impulsi|Dimensione mediana %|&asymp; prezzo|% con notizia|% continua dopo 15 min|% continua dopo 60 min|% torna all'origine entro 60 min");
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
   Grp("Ora della barra che completa l'impulso (orario dei dati)", 9);
   R(g_repEv, "  [Ora della barra che completa l'impulso]");
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
   THead("Orario (orario dei dati)|N|% degli impulsi|Dimensione mediana %|&asymp; prezzo|% con notizia|% continua dopo 15 min|% continua dopo 60 min|% torna all'origine entro 60 min|Notizia pi&ugrave; frequente");
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
            "notizie). Le notizie che escono sempre insieme sono unite in una riga (la reazione &egrave; la stessa); nelle colonne " +
            "'sopra/sotto le attese' c'&egrave; un valore per ogni notizia, nello stesso ordine dei nomi. Movimento mediano (in valore " +
            "assoluto) dopo 1, 5, 15 e 60 minuti; quante volte i minuti 5-60 proseguono la direzione dei primi 5 (tratti separati: " +
            "senza legame sarebbe circa 50%). Le attese sono il 'forecast' del calendario MT5, che pu&ograve; differire dal consenso di mercato.");
   THead("Notizia|N|Mossa 1 min %|5 min %|15 min %|60 min %|Range 60 min %|&asymp; prezzo|vs stessa ora senza notizie|% i minuti 5-60 proseguono i primi 5|Sopra le attese: % rialzo a 60 min|Sotto le attese: % rialzo a 60 min");
   R(g_repEv, "  [Per notizia, ordinate per impatto; le notizie che escono sempre insieme sono unite]");
   string rNm[], rCore[], rRep[], rSa[], rSb[];
   double scr[];
   long rSig[];
   int rQ[];
   int nr = 0;
   for(int bi = 0; bi < nn; bi++)
     {
      if(nc[bi] < 5)
         continue;
      double a1[], a5[], a15[], a60[], ag[], ar[];
      ArrayResize(a1, nc[bi]); ArrayResize(a5, nc[bi]); ArrayResize(a15, nc[bi]); ArrayResize(a60, nc[bi]);
      ArrayResize(ag, nc[bi]); ArrayResize(ar, nc[bi]);
      int q = 0, qr = 0, hold = 0, holdN = 0, abN = 0, abU = 0, beN = 0, beU = 0;
      long sig = 0;
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
         sig += (long)g_nT[i] % 1000003;
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
      nr++;
      ArrayResize(rNm, nr); ArrayResize(rCore, nr); ArrayResize(rRep, nr); ArrayResize(rSa, nr); ArrayResize(rSb, nr);
      ArrayResize(scr, nr); ArrayResize(rSig, nr); ArrayResize(rQ, nr);
      int x = nr - 1;
      rNm[x] = nm[bi];
      rQ[x] = q;
      rSig[x] = sig;
      rSa[x] = abN >= 3 ? FP((double)abU / abN, 0) + "% (" + I2S(abN) + ")" : "-";
      rSb[x] = beN >= 3 ? FP((double)beU / beN, 0) + "% (" + I2S(beN) + ")" : "-";
      rCore[x] = TD(I2S(q)) + TD(FP(MedianOf(a1, q), 3)) + TD(FP(MedianOf(a5, q), 3)) + TD(FP(MedianOf(a15, q), 3)) +
                 TD(FP(MedianOf(a60, q), 3)) + TD(FP(mg, 3)) + TD(PX(mg * g_last)) + TDc(F(mr, 2) + "&times;", PCol(mr, 1.0, 1.0)) +
                 TDc(FP(ph, 0), PCol(ph, 0.5, 0.15));
      rRep[x] = " (N " + I2S(q) + "): range 60 min " + FP(mg, 3) + "% (circa " + PX(mg * g_last) + ") = " + F(mr, 2) +
                " volte lo stesso orario senza notizie; mossa mediana 1 min " + FP(MedianOf(a1, q), 3) + "%, 5 min " + FP(MedianOf(a5, q), 3) +
                "%, 15 min " + FP(MedianOf(a15, q), 3) + "%, 60 min " + FP(MedianOf(a60, q), 3) + "%; i minuti 5-60 proseguono la " +
                "direzione dei primi 5 nel " + FP(ph, 0) + "%";
      scr[x] = MathIsValidNumber(mr) ? mr : -1;
     }
   bool usedR[];
   ArrayResize(usedR, nr);
   for(int z = 0; z < nr; z++)
      usedR[z] = false;
   for(int r = 0; r < 40; r++)
     {
      int bi = -1;
      for(int z = 0; z < nr; z++)
         if(!usedR[z] && (bi < 0 || scr[z] > scr[bi]))
            bi = z;
      if(bi < 0)
         break;
      string names = "", sas = "", sbs = "", both = "";
      int cnt = 0;
      for(int z = 0; z < nr; z++)
         if(!usedR[z] && rQ[z] == rQ[bi] && rSig[z] == rSig[bi])
           {
            usedR[z] = true;
            names += (cnt > 0 ? "<br>" : "") + rNm[z];
            sas += (cnt > 0 ? "<br>" : "") + rSa[z];
            sbs += (cnt > 0 ? "<br>" : "") + rSb[z];
            both += (cnt > 0 ? "; " : "") + rNm[z] + " " + rSa[z] + " / " + rSb[z];
            cnt++;
           }
      W("<tr>" + TD(names) + rCore[bi] + TD(sas) + TD(sbs) + "</tr>");
      string plain = names;
      StringReplace(plain, "<br>", " / ");
      R(g_repEv, "  " + plain + rRep[bi] + "; rialzo a 60 min con dato sopra / sotto le attese: " + both + ".");
     }
   TEnd();
   SecEnd();
   //--- per orario di uscita
   SecStart("Reazione per orario di uscita", "Tutte le notizie che escono allo stesso orario, confrontate con lo stesso orario nei giorni senza notizie.");
   THead("Orario (orario dei dati)|Uscite (minuti distinti)|Notizia pi&ugrave; frequente|Mossa 5 min %|Range 60 min %|Stesso orario senza notizie %|Rapporto");
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
         if(i > 0 && g_nT[i] == g_nT[i - 1])
            continue;  // piu' notizie nello stesso minuto = una sola uscita
         a5[q] = MathAbs(r5[i]);
         ag[q] = rg[i];
         q++;
        }
      if(q < 5)
         continue;
      double mg = MedianOf(ag, q), rt = Dv(mg, base[z]);
      W("<tr>" + TD(SlotLab(slots[z])) + TD(I2S(q)) + TD(bestN + " (" + I2S(bestC) + ")") + TD(FP(MedianOf(a5, q), 3)) + TD(FP(mg, 3)) +
        TD(FP(base[z], 3)) + TDc(F(rt, 2) + "&times;", PCol(rt, 1.0, 1.0)) + "</tr>");
      R(g_repEv, "    " + SlotLab(slots[z]) + ": " + I2S(q) + " uscite (pi&ugrave; frequente " + bestN + "), mossa mediana 5 min " +
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
datetime g_seTk[];  // orario chiave di ogni giorno valido (per il riferimento casuale)

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

datetime KeyTime(const long day, const int mkt, const int mins)
  {
   if(mkt < 0)
      return (datetime)(day * 86400 + (long)mins * 60);
   return LocalToData(day, mkt, mins);
  }

// Misura la finestra che parte all'orario T e scrive in g_se*[g_seN] (g_seN lo incrementa chi chiama).
bool SeWindow(CSeries &s, const datetime T, const int ORm, const int H, const int barSec, const bool useNews, double &vOr, int &kOut)
  {
   int minPre = MathMax(1, 3600 / barSec / 2), minOR = MathMax(1, ORm * 60 / barSec / 2), minH = MathMax(2, H * 3600 / barSec / 2);
   int k = LowerBound(s.t, s.n, T);
   if(k <= 0 || k >= s.n || (long)s.t[k] - (long)T >= 120)
      return false;
   int kp = LowerBound(s.t, s.n, T - 3600);
   int kor = LowerBound(s.t, s.n, T + ORm * 60);
   int k60 = LowerBound(s.t, s.n, T + 3600);
   int kh = LowerBound(s.t, s.n, T + H * 3600);
   if(k - kp < minPre || kor - k < minOR || kh - k < minH || kh <= kor || k60 <= k)
      return false;
   double op = s.o[k];
   if(!(op > 0))
      return false;
   int i = g_seN;
   kOut = k;
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
   double oH = s.h[k], oL = s.l[k];
   vOr = 0;
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
   //--- rottura dell'OR, rottura falsa (poi tocca anche l'altro lato), estremi della finestra
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
   g_seNw[i] = useNews && g_nN > 0 && NewsNear(T - 900, T + 900) >= 0;
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
   g_seRv[i] = Nan();
   return true;
  }

// Tutti i giorni feriali (della piazza) per un orario chiave; kd = barra di partenza di ogni giorno valido.
int SeCollect(CSeries &s, const int mk, const int mn, const long d0, const long d1, const int ORm, const int H, const int barSec, int &kd[])
  {
   g_seN = 0;
   int hN = 0, hP = 0;
   double hist[20];
   for(long day = d0; day <= d1; day++)
     {
      if(DowMon((datetime)(day * 86400)) >= 5)
         continue;
      double vOr = 0;
      int kk = 0;
      if(!SeWindow(s, KeyTime(day, mk, mn), ORm, H, barSec, true, vOr, kk))
         continue;
      kd[g_seN] = kk;
      g_seTk[g_seN] = KeyTime(day, mk, mn);
      if(s.hasVol)  // volume dei primi minuti rispetto agli ultimi 20 giorni validi
        {
         if(hN >= 10)
           {
            double mv = 0;
            for(int z = 0; z < hN; z++)
               mv += hist[z];
            g_seRv[g_seN] = Dv(vOr, mv / hN);
           }
         hist[hP] = vOr;
         hP = (hP + 1) % 20;
         if(hN < 20)
            hN++;
        }
      g_seN++;
     }
   return g_seN;
  }

void SeAll(SeSt &r)
  {
   bool m[];
   ArrayResize(m, g_seN);
   for(int z = 0; z < g_seN; z++)
      m[z] = true;
   SeCalc(m, r);
  }

int g_seD = 1;  // estrazioni del riferimento casuale: i conteggi di SeSurrogate sono sommati su tutte

void SeAdd(SeSt &a, SeSt &b)
  {
   a.n += b.n; a.nw += b.nw; a.bu += b.bu; a.bd += b.bd; a.fl += b.fl; a.hd += b.hd; a.ext += b.ext;
   a.cN += b.cN; a.cY += b.cY; a.iN += b.iN; a.iY += b.iY; a.vN += b.vN; a.vY += b.vY; a.tN += b.tN; a.tY += b.tY;
   a.act += b.act; a.orr += b.orr; a.absm += b.absm; a.rng += b.rng; a.xs += b.xs; a.dist += b.dist;
  }

// Riferimento: le stesse barre degli stessi giorni, con i loro orari (pause comprese), la stessa volatilita' minuto per
// minuto e lo stesso volume, ma la direzione di ogni barra e' estratta a caso (movimento invertito con probabilita' 1/2).
// Quello che resta e' l'effetto della sola volatilita'. Ripetuto InpBaseDraws volte: le percentuali usano i conteggi
// sommati di tutte le estrazioni, le mediane sono la media delle mediane.
void SeSurrogate(CSeries &s, const int &kd[], const int nk, const int ORm, const int H, const int barSec, SeSt &z)
  {
   g_seD = InpBaseDraws < 1 ? 1 : InpBaseDraws;
   ZeroMemory(z);
   long slot = (long)(H + 3) * 3600;
   CSeries sim;
   sim.hasVol = s.hasVol;
   int tot = 0;
   for(int p = 0; p < nk; p++)
     {
      int kp = LowerBound(s.t, s.n, g_seTk[p] - 3600), kh = LowerBound(s.t, s.n, g_seTk[p] + H * 3600);
      tot += kh - kp + 1;
     }
   ArrayResize(sim.t, tot); ArrayResize(sim.o, tot); ArrayResize(sim.h, tot);
   ArrayResize(sim.l, tot); ArrayResize(sim.c, tot); ArrayResize(sim.v, tot);
   datetime Tp[];
   ArrayResize(Tp, nk);
   datetime tb = D'2001.01.01';
   int done = 0;
   for(int d = 0; d < g_seD && !IsStopped(); d++)
     {
      int n = 0, np = 0;
      for(int p = 0; p < nk; p++)
        {
         datetime T = g_seTk[p];
         int kp = LowerBound(s.t, s.n, T - 3600), kh = LowerBound(s.t, s.n, T + H * 3600);
         if(kp < 1 || kh <= kp || kd[p] < kp)
            continue;
         double pc = s.c[kp - 1];
         datetime t0 = (datetime)((long)tb + (long)np * slot + 3600);
         for(int q = kp; q < kh; q++)
           {
            double ref = s.c[q - 1];
            double ro = s.o[q] / ref, rh = s.h[q] / ref, rl = s.l[q] / ref, rc = s.c[q] / ref;
            if((MathRand() & 1) == 1)
              {
               double a = 1.0 / rl;
               rl = 1.0 / rh;
               rh = a;
               ro = 1.0 / ro;
               rc = 1.0 / rc;
              }
            sim.t[n] = (datetime)((long)t0 + ((long)s.t[q] - (long)T));
            sim.o[n] = pc * ro;
            sim.h[n] = pc * rh;
            sim.l[n] = pc * rl;
            sim.c[n] = pc * rc;
            sim.v[n] = s.v[q];
            pc = sim.c[n];
            n++;
           }
         Tp[np++] = t0;
        }
      sim.n = n;
      g_seN = 0;
      for(int p = 0; p < np; p++)
        {
         double vo = 0;
         int kk = 0;
         if(SeWindow(sim, Tp[p], ORm, H, barSec, false, vo, kk))
            g_seN++;
        }
      SeSt zz;
      SeAll(zz);
      SeAdd(z, zz);
      done++;
     }
   g_seD = done > 0 ? done : 1;
   z.act /= g_seD; z.orr /= g_seD; z.absm /= g_seD; z.rng /= g_seD; z.xs /= g_seD; z.dist /= g_seD;
  }

// reale contro atteso: z dell'OR che contiene l'estremo, delle rotture false e dello stesso lato del VWAP
string SeZTxt(SeSt &r, SeSt &z, double &zE, double &zF, double &zV)
  {
   int nb = r.bu + r.bd, zb = z.bu + z.bd;
   zE = Z2(Frac(r.ext, r.n), r.n, Frac(z.ext, z.n), z.n);
   zF = Z2(Frac(r.fl, nb), nb, Frac(z.fl, zb), zb);
   zV = Z2(Frac(r.vY, r.vN), r.vN, Frac(z.vY, z.vN), z.vN);
   return "z: OR contiene " + ZS(zE) + ", false " + ZS(zF) + ", VWAP " + ZS(zV);
  }

string SeBaseTxt(SeSt &z)
  {
   int nb = z.bu + z.bd;
   return "OR contiene il massimo o il minimo " + Share(z.ext, z.n) + "%, rotture false " + Share(z.fl, nb) + "%, chiude oltre il lato rotto " +
          Share(z.hd, nb) + "%, prosegue " + Share(z.cY, z.cN) + "%, l'ora dopo contro l'ora prima " + Share(z.iY, z.iN) +
          "%, stesso lato del VWAP " + Share(z.vY, z.vN) + "%, torna al VWAP " + Share(z.tY, z.tN) + "%, incroci " + F(z.xs, 0);
  }

void SessionGrid(CSeries &s, const int barSec, const int ORm, const int H, const long d0, const long d1, const long dayA, const long dayB, int &kd[])
  {
   int mk = g_ref;
   string where = mk >= 0 ? "ora di " + MKT_NAME[mk] : "orario dei dati";
   string rows = "";
   R(g_repEv, "  [Tutta la giornata a passi di 30 minuti (" + where + "): tra parentesi il valore atteso con la stessa volatilita' e direzione casuale, " +
     "media di " + I2S(InpBaseDraws < 1 ? 1 : InpBaseDraws) + " estrazioni; z = differenza reale - atteso in deviazioni standard]");
   for(int mn = 0; mn < 1440 && !IsStopped(); mn += 30)
     {
      int nk = SeCollect(s, mk, mn, d0, d1, ORm, H, barSec, kd);
      if(nk < 30)
         continue;
      SeSt r;
      SeAll(r);
      SeSt z;
      SeSurrogate(s, kd, nk, ORm, H, barSec, z);
      string loc = mk >= 0 ? MKT_SHORT[mk] + " " + HM(mn) : HM(mn);
      int ta = MinOfDay(KeyTime(dayA, mk, mn)), tb = MinOfDay(KeyTime(dayB, mk, mn));
      string dt = HM(ta) + (ta != tb ? " / " + HM(tb) : "");
      int nb = r.bu + r.bd, zb = z.bu + z.bd;
      double fr = Frac(r.fl, nb), fz = Frac(z.fl, zb), er = Frac(r.ext, r.n), ez = Frac(z.ext, z.n), vr = Frac(r.vY, r.vN), vz = Frac(z.vY, z.vN);
      double zE = 0, zF = 0, zV = 0;
      string zt = SeZTxt(r, z, zE, zF, zV);
      string hl = "Mezz'ora " + loc + " (dati " + dt + "), " + I2S(r.n) + " giorni: ";
      Hi(0, zE, hl + "l'OR contiene il massimo o il minimo della finestra " + FP(er, 1) + "% contro atteso " + FP(ez, 1) + "%");
      Hi(0, zF, hl + "rotture false dell'OR " + FP(fr, 1) + "% contro atteso " + FP(fz, 1) + "%");
      Hi(0, zV, hl + "a fine finestra dallo stesso lato del VWAP " + FP(vr, 1) + "% contro atteso " + FP(vz, 1) + "%");
      rows += "<tr>" + TD(loc) + TD(dt) + TD(I2S(r.n)) + TDc(F(r.act, 2) + "&times;", PCol(r.act, 1.0, 1.0)) + TD(FP(r.orr, 3)) +
              TDc(FP(er, 1) + " (" + FP(ez, 1) + ")", PCol(er, ez, 0.15)) + TDc(FP(fr, 1) + " (" + FP(fz, 1) + ")", PCol(-fr, -fz, 0.15)) +
              TDc(Share(r.cY, r.cN), PCol(Frac(r.cY, r.cN), 0.5, 0.15)) + TDc(Share(r.iY, r.iN), PCol(Frac(r.iY, r.iN), 0.5, 0.15)) +
              TD(FP(r.rng, 3)) + TD(PX(r.rng * g_last)) + TDc(FP(vr, 1) + " (" + FP(vz, 1) + ")", PCol(vr, vz, 0.15)) +
              TD(g_nN > 0 ? Share(r.nw, r.n) : "-") + TD(ZS(zE) + " / " + ZS(zF) + " / " + ZS(zV)) + "</tr>";
      R(g_repEv, "    " + loc + " (dati " + dt + "), " + I2S(r.n) + " giorni: attivita' " + F(r.act, 2) + "x l'ora prima, range iniziale " +
        FP(r.orr, 3) + "%, OR contiene max o min " + FP(er, 1) + "% (" + FP(ez, 1) + "%), false " + FP(fr, 1) + "% (" + FP(fz, 1) +
        "%), prosegue " + Share(r.cY, r.cN) + "%, l'ora dopo contro l'ora prima " + Share(r.iY, r.iN) + "%, range " + I2S(H) + " ore " +
        FP(r.rng, 3) + "%, stesso lato del VWAP " + FP(vr, 1) + "% (" + FP(vz, 1) + "%), con notizia " + (g_nN > 0 ? Share(r.nw, r.n) : "-") +
        "%; " + zt);
     }
   string wl = I2S(ORm) + " min";
   SecStart("Tutta la giornata a passi di 30 minuti (" + where + ")",
            "Le stesse misure degli orari chiave, ripetute per ogni mezz'ora della giornata: si vede quali orari hanno un comportamento " +
            "proprio senza sceglierli prima. Tra parentesi il valore <b>atteso</b> ricostruendo gli stessi giorni con le stesse barre " +
            "(stessa volatilit&agrave; minuto per minuto) ma con la direzione di ogni barra estratta a caso (media di " + I2S(g_seD) +
            " estrazioni): la differenza tra reale e atteso &egrave; ci&ograve; che non si spiega con la sola volatilit&agrave;. " +
            "Blu = pi&ugrave; dell'atteso, rosso = meno (per le rotture false: blu = meno false). <b>z</b> = quanto la differenza " +
            "&egrave; grande rispetto al caso (entro &plusmn;2 compatibile con il caso, oltre &plusmn;3 difficile da ottenere per caso): " +
            "&egrave; solo un'indicazione, nessuna riga viene tolta.");
   THead("Ora locale|Orario dei dati (inverno / estate)|Giorni|Attivit&agrave; ora dopo / ora prima|Range iniziale %|% OR contiene max o min (atteso)|% rottura falsa (atteso)|% prosegue la direzione dei primi " + wl + "|% l'ora dopo va contro l'ora prima|Range mediano " + I2S(H) + " ore %|&asymp; prezzo|% stesso lato del VWAP (atteso)|% con notizia|z: OR / false / VWAP");
   W(rows);
   TEnd();
   SecEnd();
  }

void SessionTab(CSeries &s, const int barSec)
  {
   int H = InpSessionHours < 1 ? 1 : InpSessionHours;
   int ORm = InpORMinutes < barSec / 60 ? barSec / 60 : InpORMinutes;
   R(g_repEv, "");
   R(g_repEv, "=== SESSIONI: cosa succede dopo gli orari chiave delle piazze (orari locali convertiti giorno per giorno; OR = range dei " +
     "primi " + I2S(ORm) + " minuti; finestra = " + I2S(H) + " ore dall'orario chiave; solo giorni feriali della piazza; 'atteso' = " +
     "stessi giorni e stesse barre con la direzione di ogni barra estratta a caso, media di " + I2S(InpBaseDraws < 1 ? 1 : InpBaseDraws) +
     " estrazioni; z = differenza reale - atteso in deviazioni standard) ===");
   if(s.n < 5000)
     {
      SecStart("Sessioni", "");
      W("<p class='muted'>Servono dati M1 o M5.</p>");
      SecEnd();
      return;
     }
   MathSrand(20240601);
   long d0 = (long)s.t[0] / 86400 + 1, d1 = (long)s.t[s.n - 1] / 86400;
   int nd = (int)(d1 - d0 + 1);
   if(nd < 60)
      return;
   ArrayResize(g_seAct, nd); ArrayResize(g_seOr, nd); ArrayResize(g_seAbs, nd); ArrayResize(g_seRng, nd); ArrayResize(g_seDist, nd);
   ArrayResize(g_seRv, nd); ArrayResize(g_seCont, nd); ArrayResize(g_seInv, nd); ArrayResize(g_seBrk, nd); ArrayResize(g_seVwS, nd);
   ArrayResize(g_seX, nd); ArrayResize(g_seTch, nd); ArrayResize(g_seF, nd); ArrayResize(g_seHold, nd); ArrayResize(g_seExt, nd);
   ArrayResize(g_seNw, nd);
   ArrayResize(g_seTk, nd);
   int kd[];
   ArrayResize(kd, nd);
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
   string rowsA = "", rowsB = "", rowsC = "";
   string baseLab = "&nbsp;&nbsp;&#8627; atteso: stessa volatilit&agrave;, direzione casuale";
   for(int oi = 0; oi < NSE && !IsStopped(); oi++)
     {
      int e = ord[oi], mk = SE_MKT[e], mn = SE_MIN[e];
      int nk = SeCollect(s, mk, mn, d0, d1, ORm, H, barSec, kd);
      if(nk < 30)
         continue;
      SeSt r;
      SeAll(r);
      string loc = MKT_SHORT[mk] + " " + HM(mn);
      int ta = MinOfDay(LocalToData(dayA, mk, mn)), tb = MinOfDay(LocalToData(dayB, mk, mn));
      string dt = HM(ta) + (ta != tb ? " / " + HM(tb) : "");
      int nb = r.bu + r.bd;
      rowsA += "<tr>" + TD(SE_NAME[e]) + TD(loc) + TD(dt) + TD(I2S(r.n)) + TDc(F(r.act, 2) + "&times;", PCol(r.act, 1.0, 1.0)) +
               TD(FP(r.orr, 3)) + TD(Share(r.bu, r.n) + " / " + Share(r.bd, r.n)) + TD(Share(r.fl, nb)) + TD(Share(r.hd, nb)) +
               TDc(Share(r.cY, r.cN), PCol(Frac(r.cY, r.cN), 0.5, 0.15)) + TDc(Share(r.iY, r.iN), PCol(Frac(r.iY, r.iN), 0.5, 0.15)) +
               TD(Share(r.ext, r.n)) + TD(FP(r.absm, 3)) + TD(FP(r.rng, 3)) + TD(PX(r.rng * g_last)) + TD(g_nN > 0 ? Share(r.nw, r.n) : "-") + TD("") + "</tr>";
      R(g_repEv, "  " + SE_NAME[e] + " (" + loc + ", orario dei dati " + dt + "), " + I2S(r.n) + " giorni: range dell'ora dopo = " + F(r.act, 2) +
        " volte l'ora prima; range iniziale " + FP(r.orr, 3) + "%; rompe l'OR al rialzo " + Share(r.bu, r.n) + "%, al ribasso " + Share(r.bd, r.n) +
        "%; rotture false (poi tocca anche l'altro lato) " + Share(r.fl, nb) + "%; chiude la finestra oltre il lato rotto " + Share(r.hd, nb) +
        "%; il resto della finestra prosegue la direzione dei primi " + I2S(ORm) + " min " + Share(r.cY, r.cN) + "%; l'ora dopo va contro " +
        "l'ora prima " + Share(r.iY, r.iN) + "%; l'OR contiene il massimo o il minimo della finestra " + Share(r.ext, r.n) +
        "%; movimento mediano in " + I2S(H) + " ore " + FP(r.absm, 3) + "%, range mediano " + FP(r.rng, 3) + "% (circa " + PX(r.rng * g_last) +
        "); con notizia " + (g_nN > 0 ? Share(r.nw, r.n) : "-") + "%.");
      rowsB += "<tr>" + TD(SE_NAME[e]) + TD(loc) + TD(I2S(r.vN)) + TDc(Share(r.vY, r.vN), PCol(Frac(r.vY, r.vN), 0.5, 0.15)) +
               TD(Share(r.tY, r.tN)) + TD(F(r.xs, 0)) + TD(FP(r.dist, 3)) + TD(PX(r.dist * g_last)) + TD("") + "</tr>";
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
      //--- riferimento: stessi giorni, stessa volatilita', direzione casuale (sovrascrive g_se*, quindi per ultimo)
      SeSt z;
      SeSurrogate(s, kd, nk, ORm, H, barSec, z);
      int zb = z.bu + z.bd;
      double zE = 0, zF = 0, zV = 0;
      string zt = SeZTxt(r, z, zE, zF, zV);
      string hl = SE_NAME[e] + " (" + loc + "), " + I2S(r.n) + " giorni: ";
      Hi(0, zE, hl + "l'OR contiene il massimo o il minimo della finestra " + Share(r.ext, r.n) + "% contro atteso " + Share(z.ext, z.n) + "%");
      Hi(0, zF, hl + "rotture false dell'OR " + Share(r.fl, nb) + "% contro atteso " + Share(z.fl, zb) + "%");
      Hi(0, zV, hl + "a fine finestra dallo stesso lato del VWAP " + Share(r.vY, r.vN) + "% contro atteso " + Share(z.vY, z.vN) + "%");
      rowsA += "<tr class='base'>" + TD(baseLab) + TD("") + TD("") + TD(I2S(z.n / g_seD)) + TD(F(z.act, 2) + "&times;") + TD(FP(z.orr, 3)) +
               TD(Share(z.bu, z.n) + " / " + Share(z.bd, z.n)) + TD(Share(z.fl, zb)) + TD(Share(z.hd, zb)) + TD(Share(z.cY, z.cN)) +
               TD(Share(z.iY, z.iN)) + TD(Share(z.ext, z.n)) + TD(FP(z.absm, 3)) + TD(FP(z.rng, 3)) + TD(PX(z.rng * g_last)) + TD("") +
               TD("z: OR " + ZS(zE) + ", false " + ZS(zF)) + "</tr>";
      rowsB += "<tr class='base'>" + TD(baseLab) + TD("") + TD(I2S(z.vN / g_seD)) + TD(Share(z.vY, z.vN)) + TD(Share(z.tY, z.tN)) + TD(F(z.xs, 0)) +
               TD(FP(z.dist, 3)) + TD(PX(z.dist * g_last)) + TD("z " + ZS(zV)) + "</tr>";
      R(g_repEv, "    Atteso con la stessa volatilita' e direzione casuale (media di " + I2S(g_seD) + " estrazioni): " + SeBaseTxt(z) + "; " + zt + ".");
     }
   string wl = I2S(ORm) + " min";
   SecStart("Orari chiave delle piazze: cosa succede dopo",
            "Per ogni orario chiave (ora locale della piazza, convertita giorno per giorno nell'orologio dei dati) si osservano le " +
            I2S(H) + " ore successive. <b>Attivit&agrave;</b> = range dei 60 minuti dopo diviso il range dei 60 minuti prima. " +
            "<b>OR</b> = range dei primi " + wl + ". <b>Rottura falsa</b> = dopo aver rotto un lato dell'OR il prezzo tocca anche l'altro. " +
            "<b>Prosegue</b> = il resto della finestra va nella stessa direzione dei primi " + wl + ". Sotto ogni orario, in grigio, " +
            "l'<b>atteso</b>: gli stessi giorni ricostruiti con le stesse barre (stessa volatilit&agrave; minuto per minuto e stesso volume) " +
            "ma con la direzione di ogni barra estratta a caso (media di " + I2S(g_seD) + " estrazioni). Quello che differisce dall'atteso non si " +
            "spiega con la sola volatilit&agrave;; z = quanto la differenza &egrave; grande rispetto al caso (entro &plusmn;2 compatibile con il caso).");
   THead("Evento|Ora locale|Orario dei dati (inverno / estate)|Giorni|Attivit&agrave; ora dopo / ora prima|Range iniziale %|Rompe l'OR: % su / % gi&ugrave;|% rottura falsa|% chiude oltre il lato rotto|% prosegue la direzione dei primi " + wl + "|% l'ora dopo va contro l'ora prima|% OR contiene max o min della finestra|Movimento mediano " + I2S(H) + " ore %|Range mediano " + I2S(H) + " ore %|&asymp; prezzo|% con notizia|z reale - atteso");
   W(rowsA);
   TEnd();
   SecEnd();
   SecStart("VWAP ancorato a ogni orario chiave",
            "VWAP calcolato dall'orario chiave in avanti (" + (s.hasVol ? "pesato con il tick volume: sui CFD &egrave; il numero di " +
            "variazioni di prezzo, non il controvalore, ma segue bene l'attivit&agrave;" : "senza volume: media semplice dei prezzi") +
            "). <b>Stesso lato</b> = a fine finestra il prezzo &egrave; dalla stessa parte del VWAP in cui era alla fine dell'OR. " +
            "<b>Torna al VWAP</b> = dopo l'OR il prezzo tocca di nuovo il VWAP. <b>Incroci</b> = quante volte la chiusura passa da un " +
            "lato all'altro (pochi = giornata direzionale, tanti = giornata in rotazione). In grigio l'atteso con direzione casuale.");
   THead("Evento|Ora locale|Giorni|% stesso lato del VWAP a fine finestra|% torna a toccare il VWAP dopo l'OR|Incroci mediani|Distanza massima mediana dal VWAP %|&asymp; prezzo|z reale - atteso");
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
   SessionGrid(s, barSec, ORm, H, d0, d1, dayA, dayB, kd);
   HotMinutes(s, barSec);
  }

//+------------------------------------------------------------------+
//| Periodi di 4 ore, 8 ore, giorno, settimana, mese costruiti dalle  |
//| barre M1 (o M5): base delle schede Livelli e Direzione            |
//+------------------------------------------------------------------+
// 0-4: 4 ore, 8 ore, giorno, settimana, mese (sempre attivi); 5-8: 2 ore, 1 ora, 30 e 15 minuti (solo livelli, a scelta)
#define NFAM 9
string FAM_NAME[NFAM] = {"4 ore", "8 ore", "Giorno", "Settimana", "Mese", "2 ore", "1 ora", "30 minuti", "15 minuti"};
string FAM_PREV[NFAM] = {"del blocco di 4 ore precedente", "del blocco di 8 ore precedente", "del giorno precedente",
                         "della settimana precedente", "del mese precedente", "del blocco di 2 ore precedente", "dell'ora precedente",
                         "dei 30 minuti precedenti", "dei 15 minuti precedenti"
                        };
string FAM_HI[NFAM]   = {"del giorno", "del giorno", "della settimana", "del mese", "", "", "", "", ""};
string FAM_FIRST[NFAM] = {"primo blocco del giorno", "primo blocco del giorno", "primo giorno della settimana", "prima settimana del mese",
                          "", "", "", "", ""
                         };
string FAM_NEXT[NFAM]  = {"nel blocco successivo", "nel blocco successivo", "nel giorno successivo", "nella settimana successiva",
                          "nel mese successivo", "", "", "", ""
                         };
int    FAM_MIN[NFAM]   = {240, 480, 0, 0, 0, 120, 60, 30, 15};  // durata in minuti dei blocchi intraday (0 = giorno, settimana, mese)
int    FAM_ORDER[NFAM] = {8, 7, 6, 5, 0, 1, 2, 3, 4};          // ordine di presentazione: dal piu' piccolo al piu' grande

bool FamOn(const int fam)
  {
   if(fam <= 4)
      return true;
   return fam <= 6 ? InpLevelLowTF >= LV_LOW_H1 : InpLevelLowTF >= LV_LOW_M15;
  }
string g_repLv = "", g_repDir = "";

class CPer
  {
public:
   int               n;
   int               s[], e[];
   datetime          t0[], tH[], tL[], tO[];
   double            O[], H[], L[], C[];
   bool              ok[];
                     CPer(void) { n = 0; }
   void              Size(const int k)
     {
      ArrayResize(s, k, 4096); ArrayResize(e, k, 4096); ArrayResize(t0, k, 4096); ArrayResize(tH, k, 4096);
      ArrayResize(tL, k, 4096); ArrayResize(tO, k, 4096); ArrayResize(O, k, 4096); ArrayResize(H, k, 4096);
      ArrayResize(L, k, 4096); ArrayResize(C, k, 4096); ArrayResize(ok, k, 4096);
     }
   void              Free(void) { n = 0; Size(0); }
  };
CPer g_per[NFAM];

long PerKey(const datetime t, const int fam, long &cDay, long &cYM)
  {
   if(FAM_MIN[fam] > 0)
      return (long)t / ((long)FAM_MIN[fam] * 60);  // blocchi allineati alla mezzanotte dell'orologio dei dati
   long day = (long)t / 86400;
   if(fam == 2)
      return day;
   if(fam == 3)
      return (day + 4) / 7;  // settimana che parte la domenica (il forex riapre la domenica sera in UTC)
   if(day != cDay)
     {
      MqlDateTime d;
      TimeToStruct(t, d);
      cYM = (long)d.year * 12 + d.mon - 1;
      cDay = day;
     }
   return cYM;
  }

void PerBuild(CSeries &s, const int fam, CPer &p)
  {
   p.Free();
   long cDay = -1, cYM = 0, cur = LONG_MIN;
   for(int i = 0; i < s.n; i++)
     {
      long k = PerKey(s.t[i], fam, cDay, cYM);
      if(k != cur)
        {
         if(p.n > 0)
            p.e[p.n - 1] = i;
         p.n++;
         p.Size(p.n);
         int y = p.n - 1;
         p.s[y] = i;
         p.e[y] = s.n;
         p.t0[y] = s.t[i];
         p.O[y] = s.o[i];
         p.H[y] = s.h[i];
         p.L[y] = s.l[i];
         p.tH[y] = s.t[i];
         p.tL[y] = s.t[i];
         cur = k;
        }
      int x = p.n - 1;
      if(s.h[i] > p.H[x])
        {
         p.H[x] = s.h[i];
         p.tH[x] = s.t[i];
        }
      if(s.l[i] < p.L[x])
        {
         p.L[x] = s.l[i];
         p.tL[x] = s.t[i];
        }
      p.C[x] = s.c[i];
     }
   if(p.n > 1)
      p.n--;  // l'ultimo periodo e' ancora in corso
   if(p.n < 3)
      return;
   double cs[];
   ArrayResize(cs, p.n);
   for(int k = 0; k < p.n; k++)
      cs[k] = p.e[k] - p.s[k];
   double med = MedianOf(cs, p.n);
   for(int k = 0; k < p.n; k++)
     {
      p.ok[k] = k > 0 && cs[k] >= 0.25 * med;  // il primo periodo puo' essere parziale; scarta i frammenti
      int last = p.s[k];
      for(int j = p.s[k]; j < p.e[k]; j++)
         if(s.l[j] <= p.O[k] && s.h[j] >= p.O[k])
            last = j;
      p.tO[k] = s.t[last];  // ultimo passaggio sull'apertura: da qui il periodo resta da un lato
     }
  }

double PerMedRange(CPer &p, const int k, const int look)
  {
   double a[];
   ArrayResize(a, look);
   int q = 0;
   for(int j = k - 1; j >= 0 && q < look; j--)
      if(p.ok[j])
         a[q++] = p.H[j] - p.L[j];
   return q >= 5 ? MedianOf(a, q) : Nan();
  }

//+------------------------------------------------------------------+
//| Livelli chiave: massimo, minimo, chiusura del periodo precedente  |
//| e apertura del periodo in corso                                   |
//+------------------------------------------------------------------+
int    g_lvN = 0;
int    g_lvTy[], g_lvRc[], g_lvB[], g_lvPD[], g_lvCP[], g_lvOP[], g_lvOF[];
bool   g_lvT[], g_lvCB[];
double g_lvX[], g_lvFr[];

int LvBucket(const int fam, const datetime t)
  {
   if(fam != 3 && fam != 4)
      return HourOf(t);
   if(fam == 3)
      return DowMon(t);
   MqlDateTime d;
   TimeToStruct(t, d);
   return (d.day - 1) / 7;
  }

string LvBucketLab(const int fam, const int b)
  {
   if(fam != 3 && fam != 4)
      return HourLab(b);
   if(fam == 3)
      return DOW[b];
   string w[5] = {"giorni 1-7", "giorni 8-14", "giorni 15-21", "giorni 22-28", "giorni 29-31"};
   return w[b];
  }

int LvNB(const int fam) { return fam == 3 ? 7 : (fam == 4 ? 5 : 24); }

// Primo tocco del livello partendo dal lato sd (+1 prezzo sopra, -1 sotto), poi gara dalla chiusura della barra del tocco:
// +1 se va prima di r oltre il livello (prosegue), -1 se torna prima indietro di r. Partire dal livello invece che dalla
// chiusura favorirebbe 'prosegue' (la barra che tocca il livello chiude in media gia' oltre).
bool LvTouch(CSeries &s, const int j0, const int j1, const double lev, const int sd, const double r, const double closeP,
             int &jt, int &race, bool &cb, double &exc)
  {
   jt = -1;
   race = 0;
   exc = 0;
   cb = -sd * (closeP - lev) > 0;  // il periodo chiude dall'altra parte del livello
   for(int j = j0; j < j1; j++)
      if(sd > 0 ? s.l[j] <= lev : s.h[j] >= lev)
        {
         jt = j;
         break;
        }
   if(jt < 0)
      return false;
   int c = -sd;
   double ref = s.c[jt];
   double tgt = ref + c * r, bnc = ref + sd * r;
   bool done = false;
   double pen0 = c > 0 ? s.h[jt] - lev : lev - s.l[jt];
   if(pen0 > exc)
      exc = pen0;
   for(int q = jt + 1; q < j1; q++)
     {
      double pen = c > 0 ? s.h[q] - lev : lev - s.l[q];
      if(pen > exc)
         exc = pen;
      if(done)
         continue;
      bool ht = c > 0 ? s.h[q] >= tgt : s.l[q] <= tgt;
      bool hb = sd > 0 ? s.h[q] >= bnc : s.l[q] <= bnc;
      if(ht && hb)
         done = true;
      else
         if(ht)
           {
            race = 1;
            done = true;
           }
         else
            if(hb)
              {
               race = -1;
               done = true;
              }
     }
   exc = lev > 0 ? exc / lev : Nan();
   return true;
  }

void LvAdd(const int ty, const bool t, const int rc, const bool cb, const double x, const int b, const int pd, const int cp,
           const int op, const int of, const double fr)
  {
   int i = g_lvN++;
   ArrayResize(g_lvTy, g_lvN, 16384); ArrayResize(g_lvRc, g_lvN, 16384); ArrayResize(g_lvB, g_lvN, 16384);
   ArrayResize(g_lvPD, g_lvN, 16384); ArrayResize(g_lvCP, g_lvN, 16384); ArrayResize(g_lvOP, g_lvN, 16384);
   ArrayResize(g_lvOF, g_lvN, 16384); ArrayResize(g_lvT, g_lvN, 16384); ArrayResize(g_lvCB, g_lvN, 16384);
   ArrayResize(g_lvX, g_lvN, 16384); ArrayResize(g_lvFr, g_lvN, 16384);
   g_lvTy[i] = ty;
   g_lvT[i] = t;
   g_lvRc[i] = rc;
   g_lvCB[i] = cb;
   g_lvX[i] = x;
   g_lvB[i] = b;
   g_lvPD[i] = pd;
   g_lvCP[i] = cp;
   g_lvOP[i] = op;
   g_lvOF[i] = of;
   g_lvFr[i] = fr;
  }

// deviazione standard di (quota prosegue - quota respinto) su n tocchi
double LvSe(const double pc, const double pr, const int n)
  {
   if(n <= 0 || !MathIsValidNumber(pc) || !MathIsValidNumber(pr))
      return Nan();
   double v = (pc + pr - (pc - pr) * (pc - pr)) / n;
   return v > 0 ? MathSqrt(v) : Nan();
  }

// totTouch > 0: righe per orario (N = tocchi, terza colonna = quota dei tocchi)
// mf = le stesse condizioni sui livelli finti (massimo/minimo +/- 25% del range mediano): la gara dopo il tocco di un
// prezzo qualsiasi vicino al livello, per separare l'effetto del livello dal movimento generico
void LvLine(const string label, const bool &m[], const bool &mf[], const int fam, const int totTouch)
  {
   int n = 0, nt = 0, rc = 0, rr = 0, cb = 0, nx = 0, nf = 0;
   int nft = 0, rcF = 0, rrF = 0;
   for(int e = 0; e < g_lvN; e++)
     {
      if(!mf[e] || !g_lvT[e])
         continue;
      nft++;
      if(g_lvRc[e] > 0)
         rcF++;
      if(g_lvRc[e] < 0)
         rrF++;
     }
   int bc[24];
   ArrayInitialize(bc, 0);
   double xs[], fr[];
   ArrayResize(xs, g_lvN);
   ArrayResize(fr, g_lvN);
   for(int e = 0; e < g_lvN; e++)
     {
      if(!m[e])
         continue;
      n++;
      if(!g_lvT[e])
         continue;
      nt++;
      if(g_lvRc[e] > 0)
         rc++;
      if(g_lvRc[e] < 0)
         rr++;
      if(g_lvCB[e])
         cb++;
      if(MathIsValidNumber(g_lvX[e]))
         xs[nx++] = g_lvX[e];
      if(MathIsValidNumber(g_lvFr[e]))
         fr[nf++] = g_lvFr[e];
      if(g_lvB[e] >= 0 && g_lvB[e] < 24)
         bc[g_lvB[e]]++;
     }
   if(n < 10)
      return;
   int bb = 0;
   for(int z = 1; z < 24; z++)
      if(bc[z] > bc[bb])
         bb = z;
   string when = (nt > 0 && totTouch <= 0) ? LvBucketLab(fam, bb) + " (" + FP((double)bc[bb] / nt, 0) + "%)" : "-";
   double pt = totTouch > 0 ? (double)n / totTouch : (double)nt / n;
   double pc = nt > 0 ? (double)rc / nt : Nan(), pr = nt > 0 ? (double)rr / nt : Nan(), pb = nt > 0 ? (double)cb / nt : Nan();
   double mx = nx > 0 ? MedianOf(xs, nx) : Nan(), mfr = nf > 0 ? MedianOf(fr, nf) : Nan();
   double seR = LvSe(pc, pr, nt), zR = MathIsValidNumber(seR) ? (pc - pr) / seR : Nan();
   double pcF = nft > 0 ? (double)rcF / nft : Nan(), prF = nft > 0 ? (double)rrF / nft : Nan();
   double eff = (pc - pr) - (pcF - prF), seF = LvSe(pcF, prF, nft);
   double zEf = (MathIsValidNumber(seR) && MathIsValidNumber(seF)) ? eff / MathSqrt(seR * seR + seF * seF) : Nan();
   string fk = nft >= 10 ? FP(pcF, 1) + " / " + FP(prF, 1) : "-";
   if(nft >= 10)
      Hi(1, zEf, g_hiA + " / " + g_hiB + " / " + label + " (N " + I2S(n) + "): dopo il tocco prosegue di r " + FP(pc, 1) + "%, respinto " +
         FP(pr, 1) + "%; livello finto " + FP(pcF, 1) + "% / " + FP(prF, 1) + "% -> effetto del livello " + (eff >= 0 ? "+" : "") +
         FP(eff, 1) + " punti");
   W("<tr>" + TD(label) + TD(I2S(n)) + TD(FP(pt, 1)) + TD(when) + TDc(FP(pc, 1), PCol(pc, pr, 0.15)) + TD(FP(pr, 1)) + TD(ZS(zR)) +
     TD(fk) + TDc(nft >= 10 ? FP(eff, 1) : "-", nft >= 10 ? PCol(eff, 0, 0.15) : "") + TD(nft >= 10 ? ZS(zEf) : "-") +
     TD(FP(pb, 1)) + TD(FP(mx, 3)) + TD(PX(mx * g_last)) + TD(FP(mfr, 0)) + "</tr>");
   R(g_repLv, "    " + label + " (N " + I2S(n) + "): " + (totTouch > 0 ? FP(pt, 1) + "% dei tocchi" : "toccato " + FP(pt, 1) + "%" +
     (nt > 0 ? ", pi&ugrave; spesso " + when : "")) + ", dopo il tocco prosegue di r " + FP(pc, 1) + "%, respinto di r " + FP(pr, 1) +
     "% (z " + ZS(zR) + ")" + (nft >= 10 ? "; livello finto prosegue " + FP(pcF, 1) + "% / respinto " + FP(prF, 1) +
     "% -> effetto del livello " + (eff >= 0 ? "+" : "") + FP(eff, 1) + " punti (z " + ZS(zEf) + ")" : "") +
     "; il periodo chiude dall'altra parte " + FP(pb, 1) + "%, escursione mediana oltre il livello " + FP(mx, 3) + "% (circa " +
     PX(mx * g_last) + "), tocco al " + FP(mfr, 0) + "% del periodo (mediana)");
  }

void LvGrp(const string t)
  {
   g_hiB = t;
   Grp(t, 14);
   R(g_repLv, "  [" + t + "]");
  }

void LevelFam(CSeries &s, CPer &p, const int fam, const int barSec)
  {
   g_lvN = 0;
   g_hiA = "Livelli " + FAM_NAME[fam];
   g_hiB = "";
   int nIn = 0, nOH = 0, nOL = 0, nBoth = 0, nBothHF = 0, nInside = 0, cAbove = 0, cBelow = 0, nPer = 0;
   int oAway = 0, oBack = 0, oNever = 0, oNeverUp = 0;
   double rs[];
   ArrayResize(rs, p.n);
   int nr = 0;
   for(int k = 2; k < p.n; k++)
     {
      if(!p.ok[k] || !p.ok[k - 1])
         continue;
      double mr = PerMedRange(p, k, 20), r = InpLevelR * mr;
      if(!(r > 0))
         continue;
      rs[nr++] = r / p.O[k];
      double PH = p.H[k - 1], PL = p.L[k - 1], PC = p.C[k - 1], O = p.O[k], C = p.C[k];
      int j0 = p.s[k], j1 = p.e[k];
      int pd = p.C[k - 1] >= p.O[k - 1] ? 1 : -1;
      double pr = PH - PL;
      int cp = pr > 0 ? (int)MathMin(2.0, MathFloor(3.0 * (PC - PL) / pr)) : 1;
      int op = O > PH ? 1 : (O < PL ? -1 : 0);
      double per = (double)((long)s.t[j1 - 1] - (long)s.t[j0] + barSec);
      nPer++;
      int jH = -1, rH = 0, jL = -1, rL = 0;
      bool cbH = false, cbL = false;
      double xH = 0, xL = 0;
      bool tH = LvTouch(s, j0, j1, PH, O > PH ? 1 : -1, r, C, jH, rH, cbH, xH);
      bool tL = LvTouch(s, j0, j1, PL, O < PL ? -1 : 1, r, C, jL, rL, cbL, xL);
      int ofH = tH ? ((tL && jL < jH) ? 1 : 0) : -1;
      int ofL = tL ? ((tH && jH < jL) ? 1 : 0) : -1;
      LvAdd(0, tH, rH, cbH, xH, tH ? LvBucket(fam, s.t[jH]) : -1, pd, cp, op, ofH, tH ? ((long)s.t[jH] - (long)s.t[j0]) / per : Nan());
      LvAdd(1, tL, rL, cbL, xL, tL ? LvBucket(fam, s.t[jL]) : -1, pd, cp, op, ofL, tL ? ((long)s.t[jL] - (long)s.t[j0]) / per : Nan());
      //--- livelli finti: massimo e minimo spostati di +/- 25% del range mediano (tipo 4 = vicino al massimo, 5 = al minimo)
      double dF = 0.25 * mr;
      double fkL[4];
      fkL[0] = PH + dF;
      fkL[1] = PH - dF;
      fkL[2] = PL + dF;
      fkL[3] = PL - dF;
      for(int f = 0; f < 4; f++)
        {
         int jF = -1, rF = 0;
         bool cbF = false;
         double xF = 0;
         bool tF = LvTouch(s, j0, j1, fkL[f], O > fkL[f] ? 1 : -1, r, C, jF, rF, cbF, xF);
         LvAdd(f < 2 ? 4 : 5, tF, rF, cbF, xF, tF ? LvBucket(fam, s.t[jF]) : -1, pd, cp, op, -1, tF ? ((long)s.t[jF] - (long)s.t[j0]) / per : Nan());
        }
      if(op == 0)
        {
         nIn++;
         if(!tH && !tL)
            nInside++;
         else
            if(tH && !tL)
               nOH++;
            else
               if(!tH && tL)
                  nOL++;
               else
                 {
                  nBoth++;
                  if(jH < jL)
                     nBothHF++;
                 }
        }
      if(C > PH)
         cAbove++;
      else
         if(C < PL)
            cBelow++;
      //--- apertura del periodo: dopo essersi allontanato di r, ci ritorna?
      int jd = -1, sdO = 0;
      for(int j = j0; j < j1; j++)
        {
         bool up = s.h[j] >= O + r, dn = s.l[j] <= O - r;
         if(up && dn)
            break;
         if(up || dn)
           {
            sdO = up ? 1 : -1;
            jd = j;
            break;
           }
        }
      if(jd >= 0 && jd + 1 < j1)
        {
         int jO = -1, rO = 0;
         bool cbO = false;
         double xO = 0;
         bool tO = LvTouch(s, jd + 1, j1, O, sdO, r, C, jO, rO, cbO, xO);
         LvAdd(2, tO, rO, cbO, xO, tO ? LvBucket(fam, s.t[jO]) : -1, pd, cp, op, -1, tO ? ((long)s.t[jO] - (long)s.t[j0]) / per : Nan());
         oAway++;
         if(tO)
            oBack++;
         else
           {
            oNever++;
            if(sdO > 0)
               oNeverUp++;
           }
        }
      //--- chiusura precedente (giorno, settimana, mese): il gap viene riempito?
      if(fam >= 2 && fam <= 4 && MathAbs(O - PC) >= 0.05 * r)
        {
         int jC = -1, rC = 0;
         bool cbC = false;
         double xC = 0;
         bool tC = LvTouch(s, j0, j1, PC, O > PC ? 1 : -1, r, C, jC, rC, cbC, xC);
         LvAdd(3, tC, rC, cbC, xC, tC ? LvBucket(fam, s.t[jC]) : -1, pd, cp, op, -1, tC ? ((long)s.t[jC] - (long)s.t[j0]) / per : Nan());
        }
     }
   if(nPer < 20)
      return;
   double rMed = MedianOf(rs, nr);
   string pv = FAM_PREV[fam];
   string sum = I2S(nPer) + " periodi. Di quelli che aprono dentro il range " + pv + " (" + I2S(nIn) + "): restano dentro " +
                Share(nInside, nIn) + "%, toccano solo il massimo " + Share(nOH, nIn) + "%, solo il minimo " + Share(nOL, nIn) +
                "%, entrambi " + Share(nBoth, nIn) + "% (prima il massimo nel " + Share(nBothHF, nBoth) + "%). Chiude sopra il massimo " +
                pv + " nel " + Share(cAbove, nPer) + "%, sotto il minimo nel " + Share(cBelow, nPer) + "%. Apertura: dopo essersi " +
                "allontanato di r ci ritorna nel " + Share(oBack, oAway) + "%, non ci torna pi&ugrave; nel " + Share(oNever, oAway) +
                "% (di questi al rialzo il " + Share(oNeverUp, oNever) + "%). r mediano = " + FP(rMed, 3) + "% (circa " + PX(rMed * g_last) + ").";
   SecStart("Livelli: " + FAM_NAME[fam],
            "Livelli = massimo, minimo e chiusura " + pv + " e apertura del periodo in corso. <b>Toccato</b> = il prezzo lo raggiunge " +
            "durante il periodo (se il periodo apre oltre il livello conta il ritorno sul livello). Dopo il primo tocco, dalla chiusura " +
            "della barra che lo tocca: <b>prosegue</b> = va avanti di r oltre prima di tornare indietro di r; <b>respinto</b> = il " +
            "contrario (misura simmetrica: senza tendenza sarebbe circa 50 e 50); r = " +
            F(InpLevelR * 100, 0) + "% del range mediano degli ultimi 20 periodi. <b>z</b> = quanto (prosegue - respinto) si allontana " +
            "da zero rispetto al caso. <b>Livello finto</b> = la stessa misura su prezzi senza significato vicini al livello (massimo e " +
            "minimo spostati di &plusmn;25% del range mediano), negli stessi periodi e con le stesse condizioni: mostra quanto prosegue " +
            "il prezzo dopo aver toccato un prezzo qualsiasi. <b>Effetto del livello</b> = (prosegue - respinto) del livello vero meno " +
            "quello del livello finto: &egrave; la parte dovuta al livello in s&eacute;. Nessuna riga viene tolta: z e livello finto " +
            "servono solo a leggere quanto pesa il caso. <b>Chiude dall'altra parte</b> = a fine periodo il " +
            "prezzo &egrave; oltre il livello. Colonna 'a che punto del periodo' = quanta parte del periodo &egrave; passata al tocco.<br>" + sum);
   THead("Livello / condizione|N|% toccato|Quando pi&ugrave; spesso|% prosegue di r|% respinto di r|z (prosegue - respinto)|Livello finto: % prosegue / % respinto|Effetto del livello (punti)|z effetto|% chiude dall'altra parte|Escursione mediana oltre %|&asymp; prezzo|A che punto del periodo (mediana %)");
   R(g_repLv, "");
   R(g_repLv, "Livelli " + FAM_NAME[fam] + ": " + sum);
   bool m[], mf[], mz[];
   ArrayResize(m, g_lvN);
   ArrayResize(mf, g_lvN);
   ArrayResize(mz, g_lvN);
   ArrayInitialize(mz, false);
   LvGrp("Livelli");
   string nm[4] = {"Massimo ", "Minimo ", "Apertura del periodo (ritorno dopo essersi allontanato di r)", "Chiusura "};
   for(int ty = 0; ty < 4; ty++)
     {
      if(ty == 3 && (fam < 2 || fam > 4))
         continue;
      for(int e = 0; e < g_lvN; e++)
        {
         m[e] = g_lvTy[e] == ty;
         mf[e] = ty < 2 && g_lvTy[e] == ty + 4;
        }
      LvLine(ty == 2 ? nm[2] : nm[ty] + pv + (ty == 3 ? " (riempimento del gap)" : ""), m, mf, fam, 0);
     }
   for(int lt = 0; lt < 2; lt++)
     {
      string L0 = lt == 0 ? "Massimo " : "Minimo ";
      string o0 = lt == 0 ? "minimo" : "massimo";
      LvGrp(L0 + pv + ": com'era il periodo precedente");
      int pdv[2] = {1, -1};
      string pdl[2] = {"precedente rialzista", "precedente ribassista"};
      for(int z = 0; z < 2; z++)
        {
         for(int e = 0; e < g_lvN; e++)
           {
            m[e] = g_lvTy[e] == lt && g_lvPD[e] == pdv[z];
            mf[e] = g_lvTy[e] == lt + 4 && g_lvPD[e] == pdv[z];
           }
         LvLine(pdl[z], m, mf, fam, 0);
        }
      string cpl[3] = {"precedente chiuso nel terzo basso del suo range", "precedente chiuso nel terzo centrale", "precedente chiuso nel terzo alto"};
      for(int z = 2; z >= 0; z--)
        {
         for(int e = 0; e < g_lvN; e++)
           {
            m[e] = g_lvTy[e] == lt && g_lvCP[e] == z;
            mf[e] = g_lvTy[e] == lt + 4 && g_lvCP[e] == z;
           }
         LvLine(cpl[z], m, mf, fam, 0);
        }
      LvGrp(L0 + pv + ": dove apre il periodo");
      int opv[3] = {1, 0, -1};
      string opl[3] = {"apre sopra il massimo precedente", "apre dentro il range precedente", "apre sotto il minimo precedente"};
      for(int z = 0; z < 3; z++)
        {
         for(int e = 0; e < g_lvN; e++)
           {
            m[e] = g_lvTy[e] == lt && g_lvOP[e] == opv[z];
            mf[e] = g_lvTy[e] == lt + 4 && g_lvOP[e] == opv[z];
           }
         LvLine(opl[z], m, mf, fam, 0);
        }
      LvGrp(L0 + pv + ": il " + o0 + " era gi&agrave; stato toccato prima? (solo i tocchi)");
      for(int z = 1; z >= 0; z--)
        {
         for(int e = 0; e < g_lvN; e++)
            m[e] = g_lvTy[e] == lt && g_lvT[e] && g_lvOF[e] == z;
         LvLine(z == 1 ? "s&igrave;, prima il " + o0 : "no, &egrave; il primo dei due", m, mz, fam, 0);
        }
      int tt = 0;
      for(int e = 0; e < g_lvN; e++)
         if(g_lvTy[e] == lt && g_lvT[e])
            tt++;
      LvGrp(L0 + pv + ": quando viene toccato (N = tocchi)");
      for(int b = 0; b < LvNB(fam); b++)
        {
         for(int e = 0; e < g_lvN; e++)
           {
            m[e] = g_lvTy[e] == lt && g_lvT[e] && g_lvB[e] == b;
            mf[e] = g_lvTy[e] == lt + 4 && g_lvT[e] && g_lvB[e] == b;
           }
         LvLine(LvBucketLab(fam, b), m, mf, fam, tt);
        }
     }
   TEnd();
   SecEnd();
  }

//+------------------------------------------------------------------+
//| Vita del livello nel periodo: test ripetuti, attraversamenti,     |
//| ritest dopo la rottura, rimbalzi, tempo e volume vicino al        |
//| livello (accumulo)                                                |
//+------------------------------------------------------------------+
// tipi: 0 massimo, 1 minimo, 2 apertura, 3 chiusura precedente; livelli finti: 4 vicino al massimo, 5 vicino al minimo,
// 6 vicino all'apertura (livello +/- 25% del range mediano)
int    g_lfN = 0;
int    g_lfTy[], g_lfNT[], g_lfRr[], g_lfFo[], g_lfAcc[];
bool   g_lfT[], g_lfX[], g_lfRt[];
double g_lfBn[], g_lfNear[], g_lfVr[];
int    g_ltN = 0;
int    g_ltTy[], g_ltK[], g_ltRc[];  // ogni test: tipo di livello, numero del test (4 = 4 o piu'), gara dopo il test

void LtAdd(const int ty, const int k, const int rc)
  {
   int i = g_ltN++;
   ArrayResize(g_ltTy, g_ltN, 65536); ArrayResize(g_ltK, g_ltN, 65536); ArrayResize(g_ltRc, g_ltN, 65536);
   g_ltTy[i] = ty;
   g_ltK[i] = k;
   g_ltRc[i] = rc;
  }

void LfAdd(const int ty, const bool t, const int nt, const bool x, const bool rt, const int rr, const double bn, const double nr,
           const double vr, const int acc, const int fo)
  {
   int i = g_lfN++;
   ArrayResize(g_lfTy, g_lfN, 65536); ArrayResize(g_lfNT, g_lfN, 65536); ArrayResize(g_lfRr, g_lfN, 65536);
   ArrayResize(g_lfFo, g_lfN, 65536); ArrayResize(g_lfAcc, g_lfN, 65536); ArrayResize(g_lfT, g_lfN, 65536);
   ArrayResize(g_lfX, g_lfN, 65536); ArrayResize(g_lfRt, g_lfN, 65536); ArrayResize(g_lfBn, g_lfN, 65536);
   ArrayResize(g_lfNear, g_lfN, 65536); ArrayResize(g_lfVr, g_lfN, 65536);
   g_lfTy[i] = ty;
   g_lfT[i] = t;
   g_lfNT[i] = nt;
   g_lfX[i] = x;
   g_lfRt[i] = rt;
   g_lfRr[i] = rr;
   g_lfBn[i] = bn;
   g_lfNear[i] = nr;
   g_lfVr[i] = vr;
   g_lfAcc[i] = acc;
   g_lfFo[i] = fo;
  }

// Scorre le barre j0..j1-1 del periodo per il livello lev, partendo dal lato sd (+1 prezzo sopra, -1 sotto).
// Test = tocco del livello dopo che il prezzo se ne era allontanato di almeno r (il primo tocco e' il test 1); dopo ogni
// test, gara dalla chiusura della barra: attraversa di r oppure respinto di r. Attraversato = il prezzo va r oltre il
// livello dal lato opposto a quello di partenza; ritest = il primo ritorno sul livello dopo l'attraversamento; al ritest
// 'tiene' = riparte di r dal lato attraversato prima di tornare indietro di r. Rimbalzo = la massima distanza dal livello,
// dal lato di partenza, dopo il primo tocco e prima dell'attraversamento. Accumulo = barre entro +/- r dal livello tra il
// primo tocco e l'attraversamento.
void LvLife(CSeries &s, const int j0, const int j1, const double lev, const int sd, const double r, const int ty)
  {
   int c = -sd;
   int jt = -1, jx = -1, jr = -1, tests = 0, side = sd, nearN = 0, totN = 0, accN = 0;
   bool armed = true;
   double bounce = 0, vNear = 0, vTot = 0;
   for(int j = j0; j < j1; j++)
     {
      bool touch = s.l[j] <= lev && s.h[j] >= lev;
      if(!touch && j > j0 && (s.c[j - 1] - lev) * (s.o[j] - lev) < 0)
         touch = true;  // gap attraverso il livello
      if(jt < 0)
        {
         if(!touch)
            continue;
         jt = j;
        }
      totN++;
      vTot += s.v[j];
      if(s.l[j] <= lev + r && s.h[j] >= lev - r)
        {
         nearN++;
         vNear += s.v[j];
         if(jx < 0)
            accN++;
        }
      if(touch && armed)
        {
         tests++;
         LtAdd(ty, tests < 4 ? tests : 4, Race(s, j, -side, r, j1 - 1 - j));
         armed = false;
        }
      if(!armed && (s.l[j] > lev + r || s.h[j] < lev - r))
        {
         armed = true;
         side = s.l[j] > lev + r ? 1 : -1;
        }
      if(jx < 0)
        {
         double thr = c > 0 ? s.h[j] - lev : lev - s.l[j];
         if(thr >= r)
            jx = j;
         else
            if(j > jt)
              {
               double aw = sd > 0 ? s.h[j] - lev : lev - s.l[j];
               if(aw > bounce)
                  bounce = aw;
              }
        }
      else
         if(jr < 0 && j > jx && touch)
            jr = j;
     }
   if(jt < 0)
     {
      LfAdd(ty, false, 0, false, false, 0, Nan(), Nan(), Nan(), -1, 0);
      return;
     }
   //--- dopo l'attraversamento: arriva a 3r oltre il livello prima di tornarci?
   int fo = 0;
   if(jx >= 0)
     {
      double t3 = lev + c * 3 * r;
      if(c > 0 ? s.h[jx] >= t3 : s.l[jx] <= t3)
         fo = 1;
      else
         for(int q = jx + 1; q < j1; q++)
           {
            bool a3 = c > 0 ? s.h[q] >= t3 : s.l[q] <= t3;
            bool bk = c > 0 ? s.l[q] <= lev : s.h[q] >= lev;
            if(a3 && bk)
               break;  // stessa barra: ordine sconosciuto
            if(a3)
              {
               fo = 1;
               break;
              }
            if(bk)
              {
               fo = -1;
               break;
              }
           }
     }
   int rr = jr >= 0 ? Race(s, jr, c, r, j1 - 1 - jr) : 0;
   double nf = totN > 0 ? (double)nearN / totN : Nan();
   double vr = (s.hasVol && vTot > 0 && nearN > 0) ? (vNear / vTot) / nf : Nan();
   LfAdd(ty, true, tests, jx >= 0, jr >= 0, rr, bounce / r, nf, vr, jx >= 0 ? accN : -1, fo);
  }

struct LfS
  {
   int               n, nt, ts, t1, t2, t3, t4, nx, nrt, rtH, rtF, nb3, nfoU, nfoD, nnr;
   double            nrS, nrQ, bnMed, vrMed;
  };

void LfCalc(const int ty, LfS &q)
  {
   ZeroMemory(q);
   double bn[], vr[];
   ArrayResize(bn, g_lfN);
   ArrayResize(vr, g_lfN);
   int nb = 0, nv = 0;
   for(int i = 0; i < g_lfN; i++)
     {
      if(g_lfTy[i] != ty)
         continue;
      q.n++;
      if(!g_lfT[i])
         continue;
      q.nt++;
      int t = g_lfNT[i];
      q.ts += t;
      if(t == 1)
         q.t1++;
      else
         if(t == 2)
            q.t2++;
         else
            if(t == 3)
               q.t3++;
            else
               if(t >= 4)
                  q.t4++;
      if(MathIsValidNumber(g_lfBn[i]))
        {
         bn[nb++] = g_lfBn[i];
         if(g_lfBn[i] >= 3)
            q.nb3++;
        }
      if(MathIsValidNumber(g_lfNear[i]))
        {
         q.nnr++;
         q.nrS += g_lfNear[i];
         q.nrQ += g_lfNear[i] * g_lfNear[i];
        }
      if(MathIsValidNumber(g_lfVr[i]))
         vr[nv++] = g_lfVr[i];
      if(g_lfX[i])
        {
         q.nx++;
         if(g_lfFo[i] > 0)
            q.nfoU++;
         if(g_lfFo[i] < 0)
            q.nfoD++;
         if(g_lfRt[i])
           {
            q.nrt++;
            if(g_lfRr[i] > 0)
               q.rtH++;
            if(g_lfRr[i] < 0)
               q.rtF++;
           }
        }
     }
   q.bnMed = nb > 0 ? MedianOf(bn, nb) : Nan();
   q.vrMed = nv > 0 ? MedianOf(vr, nv) : Nan();
  }

// z della differenza tra le medie del tempo vicino al livello (vero contro finto)
double LfZNear(LfS &a, LfS &b)
  {
   if(a.nnr < 2 || b.nnr < 2)
      return Nan();
   double ma = a.nrS / a.nnr, mb = b.nrS / b.nnr;
   double va = a.nrQ / a.nnr - ma * ma, vb = b.nrQ / b.nnr - mb * mb;
   double se = MathSqrt(va / a.nnr + vb / b.nnr);
   return se > 0 ? (ma - mb) / se : Nan();
  }

void LfRow(const string label, LfS &q, const bool base, const double rMed, const string zTxt)
  {
   if(q.n < 10)
      return;
   double bn3 = Frac(q.nb3, q.nt), nr = q.nnr > 0 ? q.nrS / q.nnr : Nan();
   string tests = Share(q.t1, q.nt) + " / " + Share(q.t2, q.nt) + " / " + Share(q.t3, q.nt) + " / " + Share(q.t4, q.nt);
   W("<tr" + (base ? " class='base'" : "") + ">" + TD(label) + TD(I2S(q.n)) + TD(Share(q.nt, q.n)) + TD(F(Dv(q.ts, q.nt), 2)) + TD(tests) +
     TD(Share(q.nx, q.n)) + TD(Share(q.nrt, q.nx)) + TD(Share(q.rtH, q.nrt) + " / " + Share(q.rtF, q.nrt)) + TD(F(q.bnMed, 1) + " r") +
     TD(PX(q.bnMed * rMed * g_last)) + TD(FP(bn3, 1)) + TD(FP(nr, 1)) + TD(F(q.vrMed, 2)) +
     TD(Share(q.nfoU, q.nx) + " / " + Share(q.nfoD, q.nx)) + TD(zTxt) + "</tr>");
   R(g_repLv, "    " + label + " (N " + I2S(q.n) + "): toccato " + Share(q.nt, q.n) + "%, test medi " + F(Dv(q.ts, q.nt), 2) +
     " (1 / 2 / 3 / 4+ test: " + tests + "%), attraversato di r " + Share(q.nx, q.n) + "%, ritestato dopo l'attraversamento " +
     Share(q.nrt, q.nx) + "% (al ritest tiene " + Share(q.rtH, q.nrt) + "% / torna indietro " + Share(q.rtF, q.nrt) +
     "%), rimbalzo mediano al primo tocco " + F(q.bnMed, 1) + " r (circa " + PX(q.bnMed * rMed * g_last) + "), rimbalzi di almeno 3r " +
     FP(bn3, 1) + "%, tempo entro +/-r dal livello " + FP(nr, 1) + "%, volume vicino al livello " + F(q.vrMed, 2) +
     "x il normale, dopo l'attraversamento arriva a 3r " + Share(q.nfoU, q.nx) + "% / torna sul livello " + Share(q.nfoD, q.nx) + "%" +
     (zTxt != "" ? " (" + zTxt + ")" : ""));
  }

void LevelLife(CSeries &s, CPer &p, const int fam, const int barSec)
  {
   g_lfN = 0;
   g_ltN = 0;
   double rs[];
   ArrayResize(rs, p.n);
   int nr = 0;
   for(int k = 2; k < p.n && !IsStopped(); k++)
     {
      if(!p.ok[k] || !p.ok[k - 1])
         continue;
      double mr = PerMedRange(p, k, 20), r = InpLevelR * mr;
      if(!(r > 0))
         continue;
      rs[nr++] = r / p.O[k];
      double PH = p.H[k - 1], PL = p.L[k - 1], PC = p.C[k - 1], O = p.O[k], d = 0.25 * mr;
      int j0 = p.s[k], j1 = p.e[k];
      LvLife(s, j0, j1, PH, O > PH ? 1 : -1, r, 0);
      LvLife(s, j0, j1, PL, O < PL ? -1 : 1, r, 1);
      LvLife(s, j0, j1, PH + d, O > PH + d ? 1 : -1, r, 4);
      LvLife(s, j0, j1, PH - d, O > PH - d ? 1 : -1, r, 4);
      LvLife(s, j0, j1, PL + d, O < PL + d ? -1 : 1, r, 5);
      LvLife(s, j0, j1, PL - d, O < PL - d ? -1 : 1, r, 5);
      //--- apertura: dopo che il prezzo se ne e' allontanato di r (come nella tabella sopra)
      int jd = -1, sdO = 0;
      for(int j = j0; j < j1; j++)
        {
         bool up = s.h[j] >= O + r, dn = s.l[j] <= O - r;
         if(up && dn)
            break;
         if(up || dn)
           {
            sdO = up ? 1 : -1;
            jd = j;
            break;
           }
        }
      if(jd >= 0 && jd + 1 < j1)
         LvLife(s, jd + 1, j1, O, sdO, r, 2);
      LvLife(s, j0, j1, O + d, -1, r, 6);
      LvLife(s, j0, j1, O - d, 1, r, 6);
      if(fam >= 2 && fam <= 4 && MathAbs(O - PC) >= 0.05 * r)
         LvLife(s, j0, j1, PC, O > PC ? 1 : -1, r, 3);
     }
   if(nr < 20)
      return;
   double rMed = MedianOf(rs, nr);
   string pv = FAM_PREV[fam];
   SecStart("Livelli: " + FAM_NAME[fam] + " &mdash; vita del livello (test, attraversamenti, ritest, appoggi, accumulo)",
            "Tutto quello che succede su ogni livello durante il periodo, non solo al primo tocco. <b>Test</b> = tocco del livello dopo " +
            "che il prezzo se ne era allontanato di almeno r (r = " + F(InpLevelR * 100, 0) + "% del range mediano, circa " +
            PX(rMed * g_last) + "). <b>Attraversato</b> = il prezzo va r oltre il livello dal lato opposto a quello da cui arriva. " +
            "<b>Ritest</b> = il primo ritorno sul livello dopo l'attraversamento; <b>tiene</b> = da l&igrave; riparte di r nel verso " +
            "della rottura prima di tornare indietro di r (il livello rotto fa da appoggio). <b>Rimbalzo</b> = la distanza massima dal " +
            "livello, dal lato da cui arriva il prezzo, dopo il primo tocco e prima di un attraversamento (quanto il livello fa da " +
            "appoggio). <b>Tempo entro &plusmn;r</b> e <b>volume vicino al livello</b> (volume per barra vicino al livello diviso il " +
            "volume per barra del periodo) misurano l'accumulo. In grigio i <b>livelli finti</b> (livello &plusmn; 25% del range " +
            "mediano) negli stessi periodi: quello che il livello vero fa in pi&ugrave; del finto &egrave; l'effetto del livello. " +
            "z vs finto: rimbalzi di almeno 3r, ritest che tiene, tempo vicino al livello. Nota: anche su un prezzo casuale vero " +
            "e finto differiscono di 2-3 punti in % toccato, % attraversato e rimbalzi (dipendono dalla distanza dall'apertura); " +
            "i test e il ritest (gare simmetriche dalla chiusura della barra) no.");
   THead("Livello|N periodi|% toccato|Test medi (se toccato)|% con 1 / 2 / 3 / 4+ test|% attraversato di r|% ritestato dopo l'attraversamento|Al ritest: % tiene / % torna indietro|Rimbalzo mediano al primo tocco|&asymp; prezzo|% rimbalzi &ge; 3r|% tempo entro &plusmn;r dal livello|Volume vicino al livello / normale|Dopo l'attraversamento: % arriva a 3r / % torna sul livello|z vs livello finto");
   R(g_repLv, "  [Vita del livello " + FAM_NAME[fam] + ": test, attraversamenti, ritest, rimbalzi, accumulo; r mediano " + FP(rMed, 3) +
     "% (circa " + PX(rMed * g_last) + ")]");
   int tyR[4] = {0, 1, 2, 3};
   int tyF[4] = {4, 5, 6, 6};
   string lbR[4], lbF[4];
   lbR[0] = "Massimo " + pv;
   lbR[1] = "Minimo " + pv;
   lbR[2] = "Apertura del periodo (dopo essersi allontanato di r)";
   lbR[3] = "Chiusura " + pv;
   lbF[0] = "&nbsp;&nbsp;&#8627; livello finto vicino al massimo";
   lbF[1] = "&nbsp;&nbsp;&#8627; livello finto vicino al minimo";
   lbF[2] = "&nbsp;&nbsp;&#8627; livello finto vicino all'apertura";
   lbF[3] = "&nbsp;&nbsp;&#8627; livello finto vicino all'apertura";
   for(int x = 0; x < 4; x++)
     {
      LfS a, b;
      LfCalc(tyR[x], a);
      LfCalc(tyF[x], b);
      if(a.n < 10)
         continue;
      double zB = Z2(Frac(a.nb3, a.nt), a.nt, Frac(b.nb3, b.nt), b.nt);
      double zT = Z2(Frac(a.rtH, a.nrt), a.nrt, Frac(b.rtH, b.nrt), b.nrt);
      double zN = LfZNear(a, b);
      string hl = "Vita dei livelli " + FAM_NAME[fam] + " / " + lbR[x] + " (N " + I2S(a.n) + "): ";
      Hi(2, zB, hl + "rimbalzi di almeno 3r al primo tocco " + Share(a.nb3, a.nt) + "% contro finto " + Share(b.nb3, b.nt) + "%");
      Hi(2, zT, hl + "al ritest dopo l'attraversamento tiene " + Share(a.rtH, a.nrt) + "% contro finto " + Share(b.rtH, b.nrt) + "%");
      Hi(2, zN, hl + "tempo entro +/-r dal livello " + FP(Dv(a.nrS, a.nnr), 1) + "% contro finto " + FP(Dv(b.nrS, b.nnr), 1) + "%");
      LfRow(lbR[x], a, false, rMed, "z vs finto: rimbalzi " + ZS(zB) + ", ritest tiene " + ZS(zT) + ", tempo vicino " + ZS(zN));
      LfRow(lbF[x], b, true, rMed, "");
     }
   TEnd();
   //--- ogni test: il livello regge di piu' o di meno a ogni nuovo test?
   W("<h3>Ogni test del livello: attraversa o respinge?</h3><p class='desc'>Dopo ogni test, dalla chiusura della barra: " +
     "<b>attraversa</b> = va r oltre il livello prima di tornare indietro di r; <b>respinto</b> = il contrario. Test 4 = quarto " +
     "test e successivi. A destra la stessa misura sui livelli finti e l'effetto del livello (punti in pi&ugrave; di " +
     "'attraversa - respinto' rispetto al finto).</p>");
   THead("Livello e test|N test|% attraversa di r|% respinto di r|z (attraversa - respinto)|Livello finto: % attraversa / % respinto|Effetto del livello (punti)|z effetto");
   R(g_repLv, "  [Ogni test del livello " + FAM_NAME[fam] + ": attraversa di r / respinto di r dopo il test; livello finto; effetto del livello]");
   string tn[4] = {"1&deg; test (primo tocco)", "2&deg; test", "3&deg; test", "4&deg; test e oltre"};
   for(int x = 0; x < 4; x++)
     {
      for(int k = 1; k <= 4; k++)
        {
         int n = 0, a = 0, rj = 0, nf = 0, af = 0, rf = 0;
         for(int i = 0; i < g_ltN; i++)
           {
            if(g_ltK[i] != k)
               continue;
            if(g_ltTy[i] == tyR[x])
              {
               n++;
               if(g_ltRc[i] > 0)
                  a++;
               if(g_ltRc[i] < 0)
                  rj++;
              }
            else
               if(g_ltTy[i] == tyF[x])
                 {
                  nf++;
                  if(g_ltRc[i] > 0)
                     af++;
                  if(g_ltRc[i] < 0)
                     rf++;
                 }
           }
         if(n < 10)
            continue;
         double pa = (double)a / n, pr = (double)rj / n, se = LvSe(pa, pr, n), z = MathIsValidNumber(se) ? (pa - pr) / se : Nan();
         double paF = nf > 0 ? (double)af / nf : Nan(), prF = nf > 0 ? (double)rf / nf : Nan(), seF = LvSe(paF, prF, nf);
         double eff = (pa - pr) - (paF - prF);
         double zE = (MathIsValidNumber(se) && MathIsValidNumber(seF)) ? eff / MathSqrt(se * se + seF * seF) : Nan();
         string lab = lbR[x] + ": " + tn[k - 1];
         if(nf >= 10)
            Hi(2, zE, "Vita dei livelli " + FAM_NAME[fam] + " / " + lab + " (N " + I2S(n) + "): attraversa " + FP(pa, 1) + "%, respinto " +
               FP(pr, 1) + "%; livello finto " + FP(paF, 1) + "% / " + FP(prF, 1) + "% -> effetto del livello " + (eff >= 0 ? "+" : "") +
               FP(eff, 1) + " punti");
         W("<tr>" + TD(lab) + TD(I2S(n)) + TDc(FP(pa, 1), PCol(pa, pr, 0.15)) + TD(FP(pr, 1)) + TD(ZS(z)) +
           TD(nf >= 10 ? FP(paF, 1) + " / " + FP(prF, 1) : "-") + TDc(nf >= 10 ? FP(eff, 1) : "-", nf >= 10 ? PCol(eff, 0, 0.15) : "") +
           TD(nf >= 10 ? ZS(zE) : "-") + "</tr>");
         R(g_repLv, "    " + lab + " (N " + I2S(n) + "): attraversa " + FP(pa, 1) + "%, respinto " + FP(pr, 1) + "% (z " + ZS(z) + ")" +
           (nf >= 10 ? "; livello finto " + FP(paF, 1) + "% / " + FP(prF, 1) + "% -> effetto del livello " + (eff >= 0 ? "+" : "") +
            FP(eff, 1) + " punti (z " + ZS(zE) + ")" : ""));
        }
     }
   TEnd();
   //--- accumulo prima della rottura
   W("<h3>Accumulo prima della rottura</h3><p class='desc'>Solo i livelli attraversati. Tempo vicino al livello = barre entro " +
     "&plusmn;r dal livello tra il primo tocco e l'attraversamento. <b>Rottura rapida</b> = tempo sotto la mediana di quel " +
     "livello, <b>dopo accumulo</b> = sopra. Dopo la rottura: arriva a 3r oltre il livello prima di tornarci, oppure torna sul " +
     "livello prima; ritest e tenuta come sopra.</p>");
   THead("Livello|Rottura|N|Tempo mediano vicino al livello prima della rottura|% arriva a 3r prima di tornare|% torna sul livello prima|% ritestato|Al ritest % tiene");
   R(g_repLv, "  [Accumulo prima della rottura " + FAM_NAME[fam] + ": rottura rapida / dopo accumulo (tempo vicino al livello sotto / sopra la mediana)]");
   string lbA[7];
   lbA[0] = lbR[0];
   lbA[1] = lbR[1];
   lbA[2] = lbR[2];
   lbA[3] = lbR[3];
   lbA[4] = "livello finto vicino al massimo";
   lbA[5] = "livello finto vicino al minimo";
   lbA[6] = "livello finto vicino all'apertura";
   for(int ty = 0; ty < 7; ty++)
     {
      double ac[];
      ArrayResize(ac, g_lfN);
      int na = 0;
      for(int i = 0; i < g_lfN; i++)
         if(g_lfTy[i] == ty && g_lfX[i] && g_lfAcc[i] >= 0)
            ac[na++] = g_lfAcc[i];
      if(na < 20)
         continue;
      double med = MedianOf(ac, na);
      for(int g = 0; g < 2; g++)
        {
         int n = 0, fu = 0, fd = 0, rt = 0, rh = 0;
         double gs[];
         ArrayResize(gs, na);
         for(int i = 0; i < g_lfN; i++)
           {
            if(g_lfTy[i] != ty || !g_lfX[i] || g_lfAcc[i] < 0)
               continue;
            if((g == 0) != (g_lfAcc[i] <= med))
               continue;
            gs[n++] = g_lfAcc[i];
            if(g_lfFo[i] > 0)
               fu++;
            if(g_lfFo[i] < 0)
               fd++;
            if(g_lfRt[i])
              {
               rt++;
               if(g_lfRr[i] > 0)
                  rh++;
              }
           }
         if(n < 5)
            continue;
         double mt = MedianOf(gs, n) * barSec / 3600.0;
         string gl = g == 0 ? "rapida" : "dopo accumulo";
         W("<tr" + (ty >= 4 ? " class='base'" : "") + ">" + TD(lbA[ty]) + TD(gl) + TD(I2S(n)) + TD(DurLab(mt)) +
           TDc(Share(fu, n), PCol(Frac(fu, n), Frac(fd, n), 0.15)) + TD(Share(fd, n)) + TD(Share(rt, n)) + TD(Share(rh, rt)) + "</tr>");
         R(g_repLv, "    " + lbA[ty] + ", rottura " + gl + " (N " + I2S(n) + "): tempo mediano vicino al livello " + DurLab(mt) +
           ", arriva a 3r " + Share(fu, n) + "% / torna sul livello " + Share(fd, n) + "%, ritestato " + Share(rt, n) +
           "%, al ritest tiene " + Share(rh, rt) + "%");
        }
     }
   TEnd();
   SecEnd();
  }

//+------------------------------------------------------------------+
//| Livelli visti sulle candele del loro timeframe e di tutti i       |
//| timeframe inferiori (es. livelli del 4 ore su H4, H1, M30, M15,   |
//| M5, M1)                                                           |
//+------------------------------------------------------------------+
#define LO_HQ   1502  // istogramma delle candele necessarie per risolvere un test (ultima casella = oltre)
#define LO_NTF  6
#define LO_NOBS 9   // 0-5 = M1..H4, 6 = D1, 7 = W1, 8 = le candele del livello stesso
int    LO_MIN[LO_NTF]  = {1, 5, 15, 30, 60, 240};
string LO_NAME[LO_NOBS] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1", ""};
int    FAM_SPAN[NFAM]  = {240, 480, 1440, 10080, 43200, 120, 60, 30, 15};  // durata del periodo in minuti (settimana e mese circa)
string FAM_TF[NFAM]    = {"H4", "8 ore", "D1", "W1", "MN", "2 ore", "H1", "M30", "M15"};

class CCand
  {
public:
   int               n;
   int               st[];  // indice della prima barra della serie base
   double            o[], h[], l[], c[];
                     CCand(void) { n = 0; }
   void              Free(void) { n = 0; ArrayFree(st); ArrayFree(o); ArrayFree(h); ArrayFree(l); ArrayFree(c); }
  };
CCand g_lc[LO_NTF];

struct LoAcc
  {
   int               nPer, nTP, tests, brk, rej, conf, fb, rt, rtH, rUp, rDn, rNo;
   int               hq[LO_HQ];
  };
LoAcc g_lo[];

int LowerBoundInt(const int &a[], const int n, const int x)
  {
   int lo = 0, hi = n;
   while(lo < hi)
     {
      int mid = (lo + hi) / 2;
      if(a[mid] < x)
         lo = mid + 1;
      else
         hi = mid;
     }
   return lo;
  }

void CandBuild(CSeries &s, const int tfSec, CCand &q)
  {
   q.Free();
   int n = 0;
   long cur = LONG_MIN;
   for(int i = 0; i < s.n; i++)
     {
      long key = (long)s.t[i] / tfSec;
      if(key != cur)
        {
         n++;
         cur = key;
        }
     }
   ArrayResize(q.st, n); ArrayResize(q.o, n); ArrayResize(q.h, n); ArrayResize(q.l, n); ArrayResize(q.c, n);
   int x = -1;
   cur = LONG_MIN;
   for(int i = 0; i < s.n; i++)
     {
      long key = (long)s.t[i] / tfSec;
      if(key != cur)
        {
         x++;
         cur = key;
         q.st[x] = i;
         q.o[x] = s.o[i];
         q.h[x] = s.h[i];
         q.l[x] = s.l[i];
        }
      if(s.h[i] > q.h[x])
         q.h[x] = s.h[i];
      if(s.l[i] < q.l[x])
         q.l[x] = s.l[i];
      q.c[x] = s.c[i];
     }
   q.n = n;
  }

// Candele a..b-1 (quelle che si aprono nel periodo), seguito fino alla candela n-1. Test = candela che tocca il livello
// dopo che il prezzo se ne era allontanato di almeno r (il primo tocco e' il test 1). Per ogni test: la candela del test
// chiude oltre il livello o dal lato da cui arriva (rifiuto); dopo una chiusura oltre, nelle N candele successive: la
// prossima conferma, una chiude di nuovo dal lato di partenza (falsa rottura), una ritocca il livello (ritest) e chiude
// dal lato nuovo (tiene). Risoluzione = la prima chiusura a r dal livello: oltre (rotto) o dal lato di partenza (respinto);
// le candele fino alla risoluzione misurano quanto il prezzo resta sul livello.
// candele concesse per risolvere un test: la durata di un periodo del livello (almeno 20, al massimo 1500)
int LoWin(const int fam, const int tfMin)
  {
   int m = FAM_SPAN[fam] / (tfMin < 1 ? 1 : tfMin);
   return m < 20 ? 20 : (m > LO_HQ - 2 ? LO_HQ - 2 : m);
  }

void LoScan(const double &o[], const double &h[], const double &l[], const double &c[], const int n, const int a, const int b,
            const double lev, const int sd, const double r, const int N, const int ai, const int M)
  {
   g_lo[ai].nPer++;
   bool armed = true;
   int side = sd, tests = 0;
   for(int i = a; i < b; i++)
     {
      bool touch = l[i] <= lev && h[i] >= lev;
      if(!touch && i > a && (c[i - 1] - lev) * (o[i] - lev) < 0)
         touch = true;  // gap attraverso il livello
      if(armed && touch)
        {
         tests++;
         g_lo[ai].tests++;
         int sc = c[i] > lev ? 1 : (c[i] < lev ? -1 : 0);
         if(sc == -side)
           {
            g_lo[ai].brk++;
            if(i + 1 < n && (c[i + 1] - lev) * (-side) > 0)
               g_lo[ai].conf++;
            bool fb = false;
            int jr = -1;
            for(int q = i + 1; q <= i + N && q < n; q++)
              {
               if((c[q] - lev) * side > 0)
                  fb = true;
               if(jr < 0 && l[q] <= lev && h[q] >= lev)
                  jr = q;
              }
            if(fb)
               g_lo[ai].fb++;
            if(jr >= 0)
              {
               g_lo[ai].rt++;
               if((c[jr] - lev) * (-side) > 0)
                  g_lo[ai].rtH++;
              }
           }
         else
            if(sc == side)
               g_lo[ai].rej++;
         int res = 0, nq = 0;
         for(int q = i; q < n && q <= i + M; q++)
           {
            nq++;
            double dd = (c[q] - lev) * side;
            if(dd >= r)
              {
               res = -1;
               break;
              }
            if(dd <= -r)
              {
               res = 1;
               break;
              }
           }
         if(res > 0)
            g_lo[ai].rUp++;
         else
            if(res < 0)
               g_lo[ai].rDn++;
            else
               g_lo[ai].rNo++;
         if(res != 0)
            g_lo[ai].hq[nq < LO_HQ - 1 ? nq : LO_HQ - 1]++;
         armed = false;
        }
      if(!armed && (l[i] > lev + r || h[i] < lev - r))
        {
         armed = true;
         side = l[i] > lev + r ? 1 : -1;
        }
     }
   if(tests > 0)
      g_lo[ai].nTP++;
  }

// un livello su tutte le candele disponibili per la famiglia: from = prima barra della serie base da cui osservare
void LoLevel(CSeries &s, CPer &p, const int fam, const int barSec, const int k, const bool useOwn, const int from, const double lev,
             const int sd, const double r, const int ty)
  {
   int N = InpLvFollow < 1 ? 1 : InpLvFollow;
   int j1 = p.e[k];
   for(int t = 0; t < LO_NTF; t++)
     {
      if(LO_MIN[t] >= FAM_SPAN[fam] || LO_MIN[t] * 60 < barSec)
         continue;
      if(LO_MIN[t] * 60 == barSec)  // il timeframe della serie base: le sue barre
        {
         LoScan(s.o, s.h, s.l, s.c, s.n, from, j1, lev, sd, r, N, t * 7 + ty, LoWin(fam, LO_MIN[t]));
         continue;
        }
      if(g_lc[t].n == 0)
         continue;
      int a = LowerBoundInt(g_lc[t].st, g_lc[t].n, from), b = LowerBoundInt(g_lc[t].st, g_lc[t].n, j1);
      LoScan(g_lc[t].o, g_lc[t].h, g_lc[t].l, g_lc[t].c, g_lc[t].n, a, b, lev, sd, r, N, t * 7 + ty, LoWin(fam, LO_MIN[t]));
     }
   for(int f = 2; f <= 3; f++)  // D1 per settimana e mese, W1 per il mese
     {
      if((f == 2 && fam != 3 && fam != 4) || (f == 3 && fam != 4) || g_per[f].n < 2)
         continue;
      int a = LowerBoundInt(g_per[f].s, g_per[f].n, from), b = LowerBoundInt(g_per[f].s, g_per[f].n, j1);
      LoScan(g_per[f].O, g_per[f].H, g_per[f].L, g_per[f].C, g_per[f].n, a, b, lev, sd, r, N, (f == 2 ? 6 : 7) * 7 + ty,
             LoWin(fam, f == 2 ? 1440 : 10080));
     }
   if(useOwn)
      LoScan(p.O, p.H, p.L, p.C, p.n, k, k + 1, lev, sd, r, N, 8 * 7 + ty, 20);
  }

double LoMedQ(LoAcc &x)
  {
   int tot = 0;
   for(int i = 0; i < LO_HQ; i++)
      tot += x.hq[i];
   if(tot <= 0)
      return Nan();
   int acc = 0;
   for(int i = 0; i < LO_HQ; i++)
     {
      acc += x.hq[i];
      if(2 * acc >= tot)
         return i;
     }
   return Nan();
  }

string LoPair(const int a, const int na, const int b, const int nb)
  {
   return Share(a, na) + " (" + Share(b, nb) + ")";
  }

void LoRow(const string tf, LoAcc &a, LoAcc &f)
  {
   int ra = a.rUp + a.rDn, rf = f.rUp + f.rDn;
   double zB = Z2(Frac(a.brk, a.tests), a.tests, Frac(f.brk, f.tests), f.tests);
   double zR = Z2(Frac(a.rUp, ra), ra, Frac(f.rUp, rf), rf);
   double mq = LoMedQ(a), mf = LoMedQ(f);
   string hl = g_hiA + " / candele " + tf + " (" + I2S(a.tests) + " test): ";
   Hi(3, zB, hl + "la candela del test chiude oltre il livello " + Share(a.brk, a.tests) + "% contro finto " + Share(f.brk, f.tests) + "%");
   Hi(3, zR, hl + "risolto rotto " + Share(a.rUp, ra) + "% dei test risolti contro finto " + Share(f.rUp, rf) + "%");
   string res = Share(a.rUp, a.tests) + " / " + Share(a.rDn, a.tests) + " (" + Share(f.rUp, f.tests) + " / " + Share(f.rDn, f.tests) + ")";
   W("<tr>" + TD(tf) + TD(LoPair(a.nTP, a.nPer, f.nTP, f.nPer)) + TD(F(Dv(a.tests, a.nTP), 2)) +
     TDc(LoPair(a.brk, a.tests, f.brk, f.tests), PCol(Frac(a.brk, a.tests), Frac(f.brk, f.tests), 0.1)) +
     TDc(LoPair(a.rej, a.tests, f.rej, f.tests), PCol(Frac(a.rej, a.tests), Frac(f.rej, f.tests), 0.1)) +
     TD(LoPair(a.conf, a.brk, f.conf, f.brk)) + TDc(LoPair(a.fb, a.brk, f.fb, f.brk), PCol(-Frac(a.fb, a.brk), -Frac(f.fb, f.brk), 0.1)) +
     TD(LoPair(a.rt, a.brk, f.rt, f.brk)) + TDc(LoPair(a.rtH, a.rt, f.rtH, f.rt), PCol(Frac(a.rtH, a.rt), Frac(f.rtH, f.rt), 0.1)) +
     TDc(res, PCol(Frac(a.rUp, ra), Frac(f.rUp, rf), 0.1)) + TD(F(mq, 0) + " (" + F(mf, 0) + ")") + TD(ZS(zB) + " / " + ZS(zR)) + "</tr>");
   R(g_repLv, "    " + tf + ": periodi con test " + LoPair(a.nTP, a.nPer, f.nTP, f.nPer) + "%, test per periodo " + F(Dv(a.tests, a.nTP), 2) +
     ", candela del test chiude oltre " + LoPair(a.brk, a.tests, f.brk, f.tests) + "%, rifiuto " + LoPair(a.rej, a.tests, f.rej, f.tests) +
     "%; dopo chiusura oltre conferma " + LoPair(a.conf, a.brk, f.conf, f.brk) + "%, falsa " + LoPair(a.fb, a.brk, f.fb, f.brk) +
     "%, ritest " + LoPair(a.rt, a.brk, f.rt, f.brk) + "%, al ritest tiene " + LoPair(a.rtH, a.rt, f.rtH, f.rt) +
     "%; risolto rotto / respinto " + res + "%, candele sul livello " + F(mq, 0) + " (" + F(mf, 0) + "); z chiude oltre " + ZS(zB) +
     ", z rotto " + ZS(zR));
  }

void LevelLtf(CSeries &s, CPer &p, const int fam, const int barSec)
  {
   ArrayResize(g_lo, LO_NOBS * 7);
   for(int i = 0; i < LO_NOBS * 7; i++)
      ZeroMemory(g_lo[i]);
   int N = InpLvFollow < 1 ? 1 : InpLvFollow;
   for(int k = 2; k < p.n && !IsStopped(); k++)
     {
      if(!p.ok[k] || !p.ok[k - 1])
         continue;
      double mr = PerMedRange(p, k, 20), r = InpLevelR * mr;
      if(!(r > 0))
         continue;
      double PH = p.H[k - 1], PL = p.L[k - 1], PC = p.C[k - 1], O = p.O[k], d = 0.25 * mr;
      int j0 = p.s[k], j1 = p.e[k];
      LoLevel(s, p, fam, barSec, k, true, j0, PH, O > PH ? 1 : -1, r, 0);
      LoLevel(s, p, fam, barSec, k, true, j0, PL, O < PL ? -1 : 1, r, 1);
      LoLevel(s, p, fam, barSec, k, true, j0, PH + d, O > PH + d ? 1 : -1, r, 4);
      LoLevel(s, p, fam, barSec, k, true, j0, PH - d, O > PH - d ? 1 : -1, r, 4);
      LoLevel(s, p, fam, barSec, k, true, j0, PL + d, O < PL + d ? -1 : 1, r, 5);
      LoLevel(s, p, fam, barSec, k, true, j0, PL - d, O < PL - d ? -1 : 1, r, 5);
      //--- apertura (solo timeframe inferiori: sulla candela del periodo l'apertura e' il suo inizio)
      int jd = -1, sdO = 0;
      for(int j = j0; j < j1; j++)
        {
         bool up = s.h[j] >= O + r, dn = s.l[j] <= O - r;
         if(up && dn)
            break;
         if(up || dn)
           {
            sdO = up ? 1 : -1;
            jd = j;
            break;
           }
        }
      if(jd >= 0 && jd + 1 < j1)
         LoLevel(s, p, fam, barSec, k, false, jd + 1, O, sdO, r, 2);
      LoLevel(s, p, fam, barSec, k, false, j0, O + d, -1, r, 6);
      LoLevel(s, p, fam, barSec, k, false, j0, O - d, 1, r, 6);
      if(fam >= 2 && fam <= 4 && MathAbs(O - PC) >= 0.05 * r)
         LoLevel(s, p, fam, barSec, k, true, j0, PC, O > PC ? 1 : -1, r, 3);
     }
   string pv = FAM_PREV[fam];
   SecStart("Livelli: " + FAM_NAME[fam] + " &mdash; visti sulle candele " + FAM_TF[fam] + " e di tutti i timeframe inferiori",
            "Lo stesso livello letto candela per candela su ogni timeframe, dal timeframe del livello fino a M1 (tra parentesi il " +
            "<b>livello finto</b>, livello &plusmn; 25% del range mediano, negli stessi periodi). Si osservano le candele che si " +
            "aprono durante il periodo; per vedere cosa succede dopo si guardano anche le candele successive. <b>Test</b> = candela " +
            "che tocca il livello dopo che il prezzo se ne era allontanato di almeno r. <b>Chiude oltre</b> = la candela del test " +
            "chiude dall'altra parte del livello; <b>rifiuto</b> = tocca e chiude dal lato da cui arriva (stoppino sul livello). " +
            "Dopo una chiusura oltre, nelle " + I2S(N) + " candele successive: <b>conferma</b> = la candela dopo chiude ancora oltre; " +
            "<b>falsa</b> = una chiude di nuovo dal lato di partenza; <b>ritest</b> = una ritocca il livello; <b>tiene</b> = quella " +
            "candela chiude dal lato nuovo. <b>Risolto</b> = la prima chiusura a r dal livello, entro la durata di un periodo del livello (" +
            "almeno 20 e al massimo 1500 candele; sulle candele del livello stesso 20): " +
            "oltre = rotto, dal lato di partenza = respinto; <b>candele sul livello</b> = quante candele servono per risolvere " +
            "(accumulo). z = reale contro finto. Sull'apertura del periodo la candela " + FAM_TF[fam] + " non c'&egrave; (&egrave; " +
            "il suo inizio).");
   THead("Timeframe delle candele|% periodi con test (finto)|Test per periodo|Candela del test: % chiude oltre (finto)|% rifiuto (finto)|Dopo chiusura oltre: % conferma (finto)|% falsa entro " + I2S(N) + " (finto)|% ritest entro " + I2S(N) + " (finto)|Al ritest % tiene (finto)|Risolto: % rotto / % respinto (finto)|Candele sul livello, mediana (finto)|z: chiude oltre / rotto");
   R(g_repLv, "  [Livelli " + FAM_NAME[fam] + " visti sulle candele " + FAM_TF[fam] + " e dei timeframe inferiori: tra parentesi il livello finto; " +
     "conferma/falsa/ritest nelle " + I2S(N) + " candele dopo una chiusura oltre; risolto = prima chiusura a r dal livello]");
   int tyR[4] = {0, 1, 2, 3};
   int tyF[4] = {4, 5, 6, 6};
   string lbR[4];
   lbR[0] = "Massimo " + pv;
   lbR[1] = "Minimo " + pv;
   lbR[2] = "Apertura del periodo (dopo essersi allontanato di r)";
   lbR[3] = "Chiusura " + pv;
   int ord[LO_NOBS] = {8, 7, 6, 5, 4, 3, 2, 1, 0};
   for(int x = 0; x < 4; x++)
     {
      bool head = false;
      for(int oi = 0; oi < LO_NOBS; oi++)
        {
         int ob = ord[oi], ia = ob * 7 + tyR[x], ifk = ob * 7 + tyF[x];
         if(g_lo[ia].nPer < 10 || g_lo[ia].tests < 10)
            continue;
         g_hiA = "Livelli " + FAM_NAME[fam] + " sui timeframe inferiori / " + lbR[x];
         if(!head)
           {
            Grp(lbR[x], 12);
            R(g_repLv, "   " + lbR[x] + ":");
            head = true;
           }
         LoRow(ob == 8 ? FAM_TF[fam] + " (candele del livello)" : LO_NAME[ob], g_lo[ia], g_lo[ifk]);
        }
     }
   TEnd();
   SecEnd();
  }


void LoCandles(CSeries &s, const int barSec)
  {
   for(int t = 0; t < LO_NTF; t++)
     {
      g_lc[t].Free();
      if(LO_MIN[t] * 60 <= barSec)
         continue;  // la serie base stessa (M1) o sotto la sua risoluzione
      CandBuild(s, LO_MIN[t] * 60, g_lc[t]);
     }
  }

void LoFree(void)
  {
   for(int t = 0; t < LO_NTF; t++)
      g_lc[t].Free();
   ArrayFree(g_lo);
  }

void LevelTab(CSeries &s, const int barSec)
  {
   LoCandles(s, barSec);
   for(int i = 0; i < NFAM; i++)
     {
      int f = FAM_ORDER[i];
      if(FamOn(f) && g_per[f].n >= 30)
        {
         Comment("MarketProfiler: livelli ", FAM_NAME[f], " ...");
         LevelFam(s, g_per[f], f, barSec);
         LevelLife(s, g_per[f], f, barSec);
         LevelLtf(s, g_per[f], f, barSec);
        }
     }
   LoFree();
  }

//+------------------------------------------------------------------+
//| Direzione: movimenti forti, cosa li precede, quando si formano,   |
//| cosa succede dopo                                                 |
//+------------------------------------------------------------------+
int    g_drN = 0;
int    g_drK[], g_drC[], g_drA[], g_drB[], g_drCc[], g_drD[], g_drE[], g_drF[], g_drG[], g_drH[];
double g_drR[];
double g_drUp = 0.5;
double g_drV = 0.4;  // varianza per periodo di (forte rialzo - forte ribasso) se la condizione non conta nulla

// ora nominale di inizio del blocco di 4 o 8 ore (la prima barra puo' arrivare dopo, es. alle 01 dopo la pausa)
int BlockStart(const int fam, const datetime t)
  {
   int k = fam == 0 ? 4 : 8;
   return (HourOf(t) / k) * k;
  }

int DirCal(const int fam, const datetime t)
  {
   if(fam <= 1)
      return BlockStart(fam, t);
   if(fam == 2)
      return DowMon(t);
   MqlDateTime d;
   TimeToStruct(t, d);
   return (d.day - 1) / 7;
  }

string DirCalLab(const int fam, const int b)
  {
   if(fam <= 1)
      return "blocco delle " + HourLab(b);
   if(fam == 2)
      return DOW[b];
   string w[5] = {"settimana che inizia il giorno 1-7", "... 8-14", "... 15-21", "... 22-28", "... 29-31"};
   return w[b];
  }

void DirLine(const string label, const bool &m[], const int nUp, const int nDn, const int tot)
  {
   int n = 0, u = 0, d = 0, pos = 0;
   double sr = 0;
   for(int i = 0; i < g_drN; i++)
     {
      if(!m[i])
         continue;
      n++;
      if(g_drC[i] == 1)
         u++;
      if(g_drC[i] == -1)
         d++;
      if(g_drR[i] > 0)
         pos++;
      sr += g_drR[i];
     }
   if(n < 10)
      return;
   double pu = (double)u / n, pd = (double)d / n, pp = (double)pos / n;
   double zb = g_drV > 0 ? (pu - pd) / MathSqrt(g_drV / n) : Nan(), zu = ZProp(pp, g_drUp, n);
   string hl = g_hiA + " / " + g_hiB + " / " + label + " (N " + I2S(n) + "): ";
   Hi(4, zb, hl + "forte rialzo " + FP(pu, 1) + "%, forte ribasso " + FP(pd, 1) + "% (senza effetto 20% / 20%)");
   Hi(4, zu, hl + "periodo rialzista " + FP(pp, 1) + "% contro " + FP(g_drUp, 1) + "% di tutti i periodi");
   W("<tr>" + TD(label) + TD(I2S(n)) + TD(FP((double)n / tot, 1)) + TD(FP(Dv(u, nUp), 1)) + TD(FP(Dv(d, nDn), 1)) +
     TDc(FP(pu, 1), PCol(pu, 0.2, 0.1)) + TDc(FP(pd, 1), PCol(pd, 0.2, 0.1)) + TDc(FP(pu - pd, 1), PCol(pu - pd, 0, 0.1)) + TD(ZS(zb)) +
     TDc(FP(pp, 1), PCol(pp, g_drUp, 0.1)) + TD(ZS(zu)) + TD(FP(sr / n, 3)) + "</tr>");
   R(g_repDir, "    " + label + ": N " + I2S(n) + " (" + FP((double)n / tot, 1) + "% dei periodi; " + FP(Dv(u, nUp), 1) +
     "% dei forti rialzi, " + FP(Dv(d, nDn), 1) + "% dei forti ribassi): forte rialzo " + FP(pu, 1) + "%, forte ribasso " + FP(pd, 1) +
     "% (sbilanciamento " + FP(pu - pd, 1) + " punti, z " + ZS(zb) + "), rialzista " + FP(pp, 1) + "% (z " + ZS(zu) + "), rendimento medio " +
     FP(sr / n, 3) + "%");
  }

void DirGrp(const string t)
  {
   g_hiB = t;
   Grp(t, 12);
   R(g_repDir, "  [" + t + "]");
  }

void DirFam(CSeries &s, CPer &p, CPer &ph, const int fam)
  {
   g_hiA = "Direzione " + FAM_NAME[fam];
   g_hiB = "";
   int n = p.n;
   if(n < 80)
      return;
   double ret[], tr[];
   ArrayResize(ret, n);
   ArrayResize(tr, n);
   for(int k = 0; k < n; k++)
     {
      ret[k] = p.O[k] > 0 ? p.C[k] / p.O[k] - 1 : 0;
      double pc = k > 0 ? p.C[k - 1] : p.O[k];
      tr[k] = MathMax(p.H[k], pc) - MathMin(p.L[k], pc);
     }
   double tmp[];
   ArrayResize(tmp, n);
   int q = 0;
   for(int k = 2; k < n; k++)
      if(p.ok[k] && p.ok[k - 1] && p.ok[k - 2])
         tmp[q++] = ret[k];
   if(q < 60)
      return;
   double srt[];
   Sorted(tmp, q, srt);
   double p20 = Pct(srt, q, 20), p80 = Pct(srt, q, 80);
   int cls[];
   ArrayResize(cls, n);
   for(int k = 0; k < n; k++)
      cls[k] = ret[k] >= p80 ? 1 : (ret[k] <= p20 ? -1 : 0);
   g_drN = 0;
   ArrayResize(g_drK, n); ArrayResize(g_drC, n); ArrayResize(g_drA, n); ArrayResize(g_drB, n); ArrayResize(g_drCc, n);
   ArrayResize(g_drD, n); ArrayResize(g_drE, n); ArrayResize(g_drF, n); ArrayResize(g_drG, n); ArrayResize(g_drH, n);
   ArrayResize(g_drR, n);
   int nUp = 0, nDn = 0, nPos = 0;
   for(int k = 2; k < n; k++)
     {
      if(!p.ok[k] || !p.ok[k - 1] || !p.ok[k - 2])
         continue;
      int i = g_drN++;
      g_drK[i] = k;
      g_drC[i] = cls[k];
      g_drR[i] = ret[k];
      if(cls[k] == 1)
         nUp++;
      if(cls[k] == -1)
         nDn++;
      if(ret[k] > 0)
         nPos++;
      g_drA[i] = cls[k - 1] == 1 ? 0 : (cls[k - 1] == -1 ? 1 : 2);
      bool u1 = ret[k - 1] > 0, u2 = ret[k - 2] > 0;
      g_drB[i] = (u1 && u2) ? 0 : ((!u1 && !u2) ? 1 : 2);
      double pr = p.H[k - 1] - p.L[k - 1];
      g_drCc[i] = pr > 0 ? (int)MathMin(2.0, MathFloor(3.0 * (p.C[k - 1] - p.L[k - 1]) / pr)) : 1;
      double mr = PerMedRange(p, k - 1, 20);
      g_drD[i] = !MathIsValidNumber(mr) ? -1 : (pr < 0.75 * mr ? 0 : (pr > 1.33 * mr ? 2 : 1));
      g_drE[i] = p.O[k] > p.H[k - 1] ? 0 : (p.O[k] < p.L[k - 1] ? 2 : 1);
      g_drF[i] = -1;
      if(fam < 4 && ph.n > 0)
        {
         int hi = LowerBound(ph.t0, ph.n, p.t0[k] + 1) - 1;
         if(hi >= 0 && p.s[k] >= ph.s[hi] && p.s[k] < ph.e[hi])
            g_drF[i] = ph.t0[hi] == p.t0[k] ? 2 : (p.O[k] > ph.O[hi] ? 0 : 1);
        }
      g_drG[i] = -1;
      if(k >= 101)
        {
         double a14 = 0, a100 = 0;
         for(int z = 1; z <= 100; z++)
           {
            a100 += tr[k - z];
            if(z <= 14)
               a14 += tr[k - z];
           }
         double rr = Dv(a14 / 14, a100 / 100);
         g_drG[i] = !MathIsValidNumber(rr) ? -1 : (rr < 0.8 ? 0 : (rr > 1.2 ? 2 : 1));
        }
      g_drH[i] = DirCal(fam, p.t0[k]);
     }
   int tot = g_drN;
   if(tot < 60)
      return;
   g_drUp = (double)nPos / tot;
   double pu0 = (double)nUp / tot, pd0 = (double)nDn / tot;
   g_drV = pu0 * (1 - pu0) + pd0 * (1 - pd0) + 2 * pu0 * pd0;
   string fn = FAM_NAME[fam];
   SecStart("Direzione: " + fn + " &mdash; cosa precede i movimenti forti",
            "<b>Forte rialzo</b> = il 20% dei periodi con il rendimento pi&ugrave; alto (apertura &rarr; chiusura &ge; " + FP(p80, 3) +
            "%), <b>forte ribasso</b> = il 20% pi&ugrave; basso (&le; " + FP(p20, 3) + "%). Per ogni condizione conosciuta all'inizio " +
            "del periodo: quanti periodi la hanno, quanti forti rialzi e forti ribassi la avevano, e con quale frequenza un periodo con " +
            "quella condizione diventa un forte rialzo o un forte ribasso (normale = 20%; blu = pi&ugrave; spesso del normale). " +
            "Se crescono entrambi la condizione porta <b>volatilit&agrave;</b>, non direzione: la direzione &egrave; lo " +
            "<b>sbilanciamento</b> (forte rialzo meno forte ribasso). <b>z</b> = quanto il valore si allontana da quello di tutti i " +
            "periodi rispetto al caso (entro &plusmn;2 compatibile con il caso): nessuna riga viene tolta.");
   THead("Condizione all'inizio del periodo|N|% dei periodi|% dei forti rialzi|% dei forti ribassi|% diventa forte rialzo|% diventa forte ribasso|Sbilanciamento (rialzo - ribasso)|z sbilanciamento|% rialzista|z rialzista|Rendimento medio %");
   R(g_repDir, "");
   R(g_repDir, "Direzione " + fn + ": forte rialzo = rendimento >= " + FP(p80, 3) + "% (20% dei periodi), forte ribasso <= " + FP(p20, 3) +
     "%; rialzisti in generale " + FP(g_drUp, 1) + "%. Cosa c'era all'inizio del periodo:");
   bool m[];
   ArrayResize(m, tot);
   for(int i = 0; i < tot; i++)
      m[i] = true;
   DirLine("Tutti i periodi", m, nUp, nDn, tot);
   DirGrp("Periodo precedente");
   string al[3] = {"forte rialzo", "forte ribasso", "n&eacute; forte rialzo n&eacute; forte ribasso"};
   for(int z = 0; z < 3; z++)
     {
      for(int i = 0; i < tot; i++)
         m[i] = g_drA[i] == z;
      DirLine("precedente: " + al[z], m, nUp, nDn, tot);
     }
   string bl[3] = {"ultimi due entrambi rialzisti", "ultimi due entrambi ribassisti", "ultimi due in direzioni diverse"};
   for(int z = 0; z < 3; z++)
     {
      for(int i = 0; i < tot; i++)
         m[i] = g_drB[i] == z;
      DirLine(bl[z], m, nUp, nDn, tot);
     }
   string cl[3] = {"precedente chiuso nel terzo basso del suo range", "precedente chiuso nel terzo centrale", "precedente chiuso nel terzo alto"};
   for(int z = 2; z >= 0; z--)
     {
      for(int i = 0; i < tot; i++)
         m[i] = g_drCc[i] == z;
      DirLine(cl[z], m, nUp, nDn, tot);
     }
   string dl[3] = {"precedente stretto (range &lt; 0.75 volte il mediano)", "precedente di ampiezza normale", "precedente ampio (range &gt; 1.33 volte il mediano)"};
   for(int z = 0; z < 3; z++)
     {
      for(int i = 0; i < tot; i++)
         m[i] = g_drD[i] == z;
      DirLine(dl[z], m, nUp, nDn, tot);
     }
   DirGrp("Apertura");
   string el[3] = {"apre sopra il massimo precedente", "apre dentro il range precedente", "apre sotto il minimo precedente"};
   for(int z = 0; z < 3; z++)
     {
      for(int i = 0; i < tot; i++)
         m[i] = g_drE[i] == z;
      DirLine(el[z], m, nUp, nDn, tot);
     }
   if(fam < 4)
     {
      DirGrp("Rispetto all'apertura " + FAM_HI[fam]);
      string fl[3] = {"apre sopra l'apertura " + FAM_HI[fam], "apre sotto l'apertura " + FAM_HI[fam], FAM_FIRST[fam]};
      for(int z = 0; z < 3; z++)
        {
         for(int i = 0; i < tot; i++)
            m[i] = g_drF[i] == z;
         DirLine(fl[z], m, nUp, nDn, tot);
        }
     }
   DirGrp("Volatilit&agrave; dei periodi precedenti (ATR14 / ATR100)");
   string gl[3] = {"compressione (sotto 0.8)", "normale (0.8-1.2)", "espansione (sopra 1.2)"};
   for(int z = 0; z < 3; z++)
     {
      for(int i = 0; i < tot; i++)
         m[i] = g_drG[i] == z;
      DirLine(gl[z], m, nUp, nDn, tot);
     }
   DirGrp("Calendario");
   int nb = fam <= 1 ? 24 : (fam == 2 ? 7 : 5);
   for(int b = 0; b < nb; b++)
     {
      for(int i = 0; i < tot; i++)
         m[i] = g_drH[i] == b;
      DirLine(DirCalLab(fam, b), m, nUp, nDn, tot);
     }
   TEnd();
   //--- quando si forma la direzione
   int nq = fam == 0 ? 4 : (fam == 1 ? 8 : (fam == 2 ? 24 : 7));
   int uL[24], uH[24], uO[24], dH[24], dL[24], dO[24], aO[24];
   ArrayInitialize(uL, 0); ArrayInitialize(uH, 0); ArrayInitialize(uO, 0); ArrayInitialize(dH, 0);
   ArrayInitialize(dL, 0); ArrayInitialize(dO, 0); ArrayInitialize(aO, 0);
   for(int i = 0; i < tot; i++)
     {
      int k = g_drK[i];
      int h0 = fam <= 1 ? BlockStart(fam, p.t0[k]) : HourOf(p.t0[k]);
      int bL, bH, bO;
      if(fam == 2)
        {
         bL = HourOf(p.tL[k]);
         bH = HourOf(p.tH[k]);
         bO = HourOf(p.tO[k]);
        }
      else
         if(fam == 3)
           {
            bL = DowMon(p.tL[k]);
            bH = DowMon(p.tH[k]);
            bO = DowMon(p.tO[k]);
           }
         else
           {
            bL = MathMin(nq - 1, (HourOf(p.tL[k]) - h0 + 24) % 24);
            bH = MathMin(nq - 1, (HourOf(p.tH[k]) - h0 + 24) % 24);
            bO = MathMin(nq - 1, (HourOf(p.tO[k]) - h0 + 24) % 24);
           }
      aO[bO]++;
      if(g_drC[i] == 1)
        {
         uL[bL]++;
         uH[bH]++;
         uO[bO]++;
        }
      if(g_drC[i] == -1)
        {
         dH[bH]++;
         dL[bL]++;
         dO[bO]++;
        }
     }
   W("<h3>Quando si forma la direzione</h3><p class='desc'>Nei forti rialzi: quando si forma il minimo, quando il massimo e quando il " +
     "prezzo passa per l'ultima volta sull'apertura (da l&igrave; in poi resta sopra). Nei forti ribassi il contrario.</p>");
   THead("Quando|Forti rialzi: % minimo|% massimo|% ultimo passaggio sull'apertura|Forti ribassi: % massimo|% minimo|% ultimo passaggio sull'apertura|Tutti: % ultimo passaggio sull'apertura");
   R(g_repDir, "  [Quando si forma la direzione: forti rialzi minimo / massimo / ultimo passaggio sull'apertura; forti ribassi massimo / minimo / ultimo passaggio; tutti]");
   for(int b = 0; b < nq; b++)
     {
      if(fam == 3 && b >= 5 && uL[b] + dH[b] + aO[b] == 0)
         continue;
      string lb = fam == 2 ? HourLab(b) : (fam == 3 ? DOW[b] : "+" + I2S(b) + "h");
      W("<tr>" + TD(lb) + TD(FP(Dv(uL[b], nUp), 1)) + TD(FP(Dv(uH[b], nUp), 1)) + TD(FP(Dv(uO[b], nUp), 1)) + TD(FP(Dv(dH[b], nDn), 1)) +
        TD(FP(Dv(dL[b], nDn), 1)) + TD(FP(Dv(dO[b], nDn), 1)) + TD(FP(Dv(aO[b], tot), 1)) + "</tr>");
      R(g_repDir, "    " + lb + ": forti rialzi " + FP(Dv(uL[b], nUp), 1) + " / " + FP(Dv(uH[b], nUp), 1) + " / " + FP(Dv(uO[b], nUp), 1) +
        "%; forti ribassi " + FP(Dv(dH[b], nDn), 1) + " / " + FP(Dv(dL[b], nDn), 1) + " / " + FP(Dv(dO[b], nDn), 1) + "%; tutti " +
        FP(Dv(aO[b], tot), 1) + "%");
     }
   TEnd();
   //--- cosa succede dopo
   W("<h3>Cosa succede " + FAM_NEXT[fam] + "</h3>");
   THead("Dopo un|N|% rialzista|z rialzista|Rendimento medio %|% tocca il massimo del periodo prima|% tocca il minimo del periodo prima|% forte rialzo|% forte ribasso|z sbilanciamento");
   R(g_repDir, "  [Cosa succede " + FAM_NEXT[fam] + "]");
   int cv[3] = {1, -1, 0};
   string cn[3] = {"forte rialzo", "forte ribasso", "periodo normale"};
   for(int z = 0; z < 3; z++)
     {
      int nn = 0, up = 0, th = 0, tl = 0, fu = 0, fd = 0;
      double sr = 0;
      for(int i = 0; i < tot; i++)
        {
         int k = g_drK[i];
         if(g_drC[i] != cv[z] || k + 1 >= n || !p.ok[k + 1])
            continue;
         nn++;
         if(ret[k + 1] > 0)
            up++;
         sr += ret[k + 1];
         if(p.H[k + 1] >= p.H[k])
            th++;
         if(p.L[k + 1] <= p.L[k])
            tl++;
         if(cls[k + 1] == 1)
            fu++;
         if(cls[k + 1] == -1)
            fd++;
        }
      if(nn < 10)
         continue;
      double zu = ZProp(Frac(up, nn), g_drUp, nn), zb = g_drV > 0 ? (Frac(fu, nn) - Frac(fd, nn)) / MathSqrt(g_drV / nn) : Nan();
      string hl = g_hiA + " / periodo dopo un " + cn[z] + " (N " + I2S(nn) + "): ";
      Hi(4, zu, hl + "rialzista " + Share(up, nn) + "% contro " + FP(g_drUp, 1) + "% di tutti i periodi");
      Hi(4, zb, hl + "forte rialzo " + Share(fu, nn) + "%, forte ribasso " + Share(fd, nn) + "% (senza effetto 20% / 20%)");
      W("<tr>" + TD(cn[z]) + TD(I2S(nn)) + TDc(Share(up, nn), PCol(Frac(up, nn), g_drUp, 0.1)) + TD(ZS(zu)) + TD(FP(sr / nn, 3)) + TD(Share(th, nn)) +
        TD(Share(tl, nn)) + TDc(Share(fu, nn), PCol(Frac(fu, nn), 0.2, 0.1)) + TDc(Share(fd, nn), PCol(Frac(fd, nn), 0.2, 0.1)) + TD(ZS(zb)) + "</tr>");
      R(g_repDir, "    dopo un " + cn[z] + " (N " + I2S(nn) + "): rialzista " + Share(up, nn) + "% (z " + ZS(zu) + "), rendimento medio " +
        FP(sr / nn, 3) + "%, tocca il massimo " + Share(th, nn) + "%, tocca il minimo " + Share(tl, nn) + "%, forte rialzo " + Share(fu, nn) +
        "%, forte ribasso " + Share(fd, nn) + "% (sbilanciamento z " + ZS(zb) + ")");
     }
   TEnd();
   SecEnd();
  }

void DirTab(CSeries &s)
  {
   int hi[4] = {2, 2, 3, 4};
   for(int f = 0; f < 4; f++)
      DirFam(s, g_per[f], g_per[hi[f]], f);
  }

void PerAll(CSeries &s)
  {
   for(int f = 0; f < NFAM; f++)
      if(FamOn(f))
         PerBuild(s, f, g_per[f]);
  }

void PerFree(void)
  {
   for(int f = 0; f < NFAM; f++)
      g_per[f].Free();
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
//+------------------------------------------------------------------+
//| Costi per broker: spread per ora, swap, commissione, slittamento  |
//| (profilo 0 = lordo, 1 e 2 = i due broker dei parametri)           |
//+------------------------------------------------------------------+
#define NPRF 3
string SgnF(const double x, const int d) { if(!MathIsValidNumber(x)) return "-"; return (x >= 0 ? "+" : "") + DoubleToString(x, d); }
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

struct CostP
  {
   string            name, sym, spTxt, swTxt, cmTxt, warn, from;
   bool              on;
   double            sp[24];          // spread medio per ora dell'orologio del broker (New York + 7), in prezzo
   bool              spOk[24];        // ora misurata
   double            spH[24];         // ore osservate
   double            swA[2], swP[2];  // swap per notte (0 buy, 1 sell): in prezzo e in frazione del prezzo; positivo = accredito
   double            comm, slip, tv, ts;
   int               triple;          // giorno dello swap triplo (0 = domenica)
  };
CostP  g_cp[NPRF];
string g_rbHead[NPRF];  // testo: costi del profilo
string g_rrHtml[NPRF];  // HTML delle schede dei broker (costruito durante il calcolo)
int    g_srvOff = 0;
bool   g_srvNY7 = true;

string NormU(const string s)  // maiuscole, solo lettere e cifre
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

string SymBase(const string sym)  // "US100_QDM" -> "US100", "EURUSD.a" -> "EURUSD"
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

int AliasList(const string base, string &al[])  // nomi con cui i broker chiamano lo stesso strumento
  {
   for(int g = 0; g < ArraySize(ALIAS_GRP); g++)
     {
      string p[];
      int k = StringSplit(ALIAS_GRP[g], ',', p);
      for(int i = 0; i < k; i++)
         if(StringFind(base, p[i]) == 0 && StringLen(base) - StringLen(p[i]) <= 4)
           {
            ArrayResize(al, k);
            for(int j = 0; j < k; j++)
               al[j] = p[j];
            return k;
           }
     }
   ArrayResize(al, 1);
   al[0] = base;
   return 1;
  }

bool AllLetters(const string s)
  {
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(s, i);
      if(c < 'A' || c > 'Z')
         return false;
     }
   return n > 0;
  }

string FindBrokerSym(const string &al[], const int k)  // simbolo del broker (non personalizzato) con il nome piu' vicino
  {
   string best = "";
   int bsc = 1000000;
   int tot = SymbolsTotal(false);
   for(int i = 0; i < tot; i++)
     {
      string nm = SymbolName(i, false);
      if(SymbolInfoInteger(nm, SYMBOL_CUSTOM) != 0)
         continue;
      string nu = NormU(nm);
      for(int a = 0; a < k; a++)
        {
         int ex = StringLen(nu) - StringLen(al[a]);
         if(StringLen(al[a]) < 2 || ex < 0 || ex > 4 || StringFind(nu, al[a]) != 0)
            continue;
         int sc = ex * 100 + a;
         if(sc < bsc)
           {
            bsc = sc;
            best = nm;
           }
        }
     }
   return best;
  }

void SrvClock(void)
  {
   datetime g = TimeGMT();
   g_srvOff = (int)MathRound((double)((long)TimeTradeServer() - (long)g) / 3600.0);
   g_srvNY7 = g_srvOff == (IsUSDST(g) ? 3 : 2);
  }

datetime SrvToNY7(const datetime t)  // orario del server di questo terminale -> orologio New York + 7
  {
   if(g_srvNY7)
      return t;
   long u = (long)t - (long)g_srvOff * 3600;
   return (datetime)(u + (IsUSDST((datetime)u) ? 3 : 2) * 3600);
  }

datetime DataToNY7(const datetime t)  // orario dei dati -> orologio New York + 7 (mezzanotte = rollover dello swap)
  {
   if(InpDataTZ == TZ_BROKER_NY7)
      return t;
   long u = (long)t - (long)DataOffset(t) * 3600;
   return (datetime)(u + (IsUSDST((datetime)u) ? 3 : 2) * 3600);
  }

//--- rollover: NY 17:00 = mezzanotte dell'orologio New York + 7; finestra da InpRollPre minuti prima a InpRollPost minuti dopo
int RollPre(void) { return InpRollPre < 0 ? 0 : (InpRollPre > 600 ? 600 : InpRollPre); }
int RollPost(void) { return InpRollPost < 0 ? 0 : (InpRollPost > 600 ? 600 : InpRollPost); }
bool RollWin(const int m7) { return m7 >= 1440 - RollPre() || m7 < RollPost(); }  // minuto dell'orologio NY+7 dentro la finestra
bool RollIn(const datetime t) { return InpRollSkip && RollWin((int)(((long)DataToNY7(t) % 86400) / 60)); }
datetime RollNext(const datetime t)  // inizio della prossima finestra del rollover dopo t (orario dei dati)
  {
   long t7 = (long)DataToNY7(t), st = (t7 / 86400 + 1) * 86400 - (long)RollPre() * 60;
   if(st <= t7)
      st += 86400;
   return (datetime)((long)t + st - t7);
  }
bool RollHit7(const long a7, const long b7)  // l'intervallo [a7, b7] dell'orologio NY+7 tocca la finestra
  {
   if(!InpRollSkip)
      return false;
   if(RollWin((int)((a7 % 86400) / 60)))
      return true;
   long st = (a7 / 86400 + 1) * 86400 - (long)RollPre() * 60;
   if(st <= a7)
      st += 86400;
   return st <= b7;
  }
string RollTxt(void)
  {
   string w = HM(1440 - RollPre()) + "-" + HM(RollPost()) + " del broker (NY " + HM(1440 - RollPre() - 420) + "-" + HM(RollPost() - 420) + ")";
   if(!InpRollSkip)
      return "Rollover (NY 17:00, finestra " + w + "): incluso in tutte le analisi (parametro 'Rollover' = false).";
   return "Rollover (NY 17:00 = mezzanotte del broker, finestra " + w + "): lo spread si allarga e sui dati bid il prezzo scende senza " +
          "scambi veri, poi torna. Nel rischio/rendimento fino a H1 nessuna entrata nella finestra e le operazioni si chiudono a mercato " +
          "prima; nell'ORB esclusi i giorni in cui il range o la finestra la toccano. Le altre analisi la includono (vedi Ore buche e rollover).";
  }

// sequenze di fasce da 15 minuti con f[] vero, sulla giornata circolare: "23:45-01:00, 05:00-05:30"
string SlotRuns(const bool &f[])
  {
   int z0 = -1;
   for(int z = 0; z < 96 && z0 < 0; z++)
      if(!f[z])
         z0 = z;
   if(z0 < 0)
      return "tutta la giornata";
   string t = "";
   int a = -1;
   for(int k = 1; k <= 96; k++)
     {
      int z = (z0 + k) % 96;
      if(f[z] && a < 0)
         a = z;
      if(!f[z] && a >= 0)
        {
         t += (t != "" ? ", " : "") + HM(a * 15) + "-" + HM(z * 15);
         a = -1;
        }
     }
   return t == "" ? "nessuna" : t;
  }

//--- ore buche e rollover: la giornata a passi di 15 minuti sull'orologio New York + 7 (mezzanotte = NY 17:00): mercato aperto,
//    attivita', volume, spread registrato nelle barre, punte del bid (lo spread che si allarga abbassa il bid senza scambi) e movimento medio
void DeadHours(CSeries &s, const int barSec)
  {
   int dayN[96], barN[96], aN[96], spN[96], dnS[96], upS[96];
   double act[96], vol[96], spS[96], rt[96], rt2[96];
   long lastDay[96];
   for(int z = 0; z < 96; z++)
     {
      dayN[z] = 0;
      barN[z] = 0;
      aN[z] = 0;
      spN[z] = 0;
      dnS[z] = 0;
      upS[z] = 0;
      act[z] = 0;
      vol[z] = 0;
      spS[z] = 0;
      rt[z] = 0;
      rt2[z] = 0;
      lastDay[z] = -1;
     }
   bool hasSp = ArraySize(s.sp) == s.n;
   int st = barSec / 60 < 1 ? 1 : barSec / 60;
   double ew = 0, al = 2.0 / (1440.0 / st + 1.0), volAll = 0;
   bool init = false;
   long days = 0, cur7 = -1, curD = -1, off = 0;
   int nAll = 0;
   for(int i = 0; i < s.n; i++)
     {
      long dd = (long)s.t[i] / 86400;
      if(dd != curD)  // differenza dall'orologio NY+7 una volta per giorno dei dati
        {
         curD = dd;
         off = (long)DataToNY7(s.t[i]) - (long)s.t[i];
        }
      long t7 = (long)s.t[i] + off, d7 = t7 / 86400;
      if(d7 != cur7)
        {
         cur7 = d7;
         days++;
        }
      int z = (int)((t7 % 86400) / 900);
      if(lastDay[z] != d7)
        {
         lastDay[z] = d7;
         dayN[z]++;
        }
      barN[z]++;
      if(hasSp && s.sp[i] > 0)
        {
         spS[z] += s.sp[i];
         spN[z]++;
        }
      vol[z] += s.v[i];
      volAll += s.v[i];
      nAll++;
      double r = s.h[i] - s.l[i];
      if(init && ew > 0)
        {
         aN[z]++;
         act[z] += r / ew;
         if(MathMin(s.o[i], s.c[i]) - s.l[i] >= 2.0 * ew)
            dnS[z]++;
         if(s.h[i] - MathMax(s.o[i], s.c[i]) >= 2.0 * ew)
            upS[z]++;
         double x = (s.c[i] - s.o[i]) / ew;
         rt[z] += x;
         rt2[z] += x * x;
        }
      ew = init ? al * r + (1 - al) * ew : r;
      init = true;
     }
   if(days < 20)
      return;
   double volMean = nAll > 0 ? volAll / nAll : 0;
   double spv[];
   int ns = 0;
   ArrayResize(spv, 96);
   for(int z = 0; z < 96; z++)
      if(spN[z] >= 50)
         spv[ns++] = spS[z] / spN[z];
   double spRef = ns > 0 ? MedianOf(spv, ns) : 0;
   bool fC[96], fT[96], fW[96], fD[96], fR[96];
   string note[96];
   double sh[96], av[96], vv[96], sr[96], zA[96], zR[96];
   for(int z = 0; z < 96; z++)
     {
      sh[z] = (double)dayN[z] / days;
      av[z] = aN[z] > 0 ? act[z] / aN[z] : Nan();
      vv[z] = s.hasVol && volMean > 0 && barN[z] > 0 ? vol[z] / barN[z] / volMean : Nan();
      sr[z] = spN[z] >= 50 && spRef > 0 ? spS[z] / spN[z] / spRef : Nan();
      zA[z] = dnS[z] + upS[z] >= 20 ? (dnS[z] - upS[z]) / MathSqrt((double)(dnS[z] + upS[z])) : Nan();
      zR[z] = rt2[z] > 0 ? rt[z] / MathSqrt(rt2[z]) : Nan();
      fC[z] = sh[z] < 0.5;
      fT[z] = !fC[z] && MathIsValidNumber(av[z]) && av[z] < 0.6 && (!MathIsValidNumber(vv[z]) || vv[z] < 0.6);
      fW[z] = !fC[z] && MathIsValidNumber(sr[z]) && sr[z] >= 2.0;
      fD[z] = !fC[z] && MathIsValidNumber(zA[z]) && zA[z] >= 3.0;
      fR[z] = RollWin(z * 15);
      string nt = "";
      if(fR[z])
         nt += InpRollSkip ? "rollover (escluso da R/R e ORB)" : "rollover";
      if(fC[z])
         nt += (nt != "" ? ", " : "") + "mercato chiuso";
      if(fT[z])
         nt += (nt != "" ? ", " : "") + "ora buca";
      if(fW[z])
         nt += (nt != "" ? ", " : "") + "spread alto";
      if(fD[z])
         nt += (nt != "" ? ", " : "") + "punte del bid";
      note[z] = nt;
     }
   string spTxt = spRef > 0 ? "spread = media dello spread registrato nelle barre, in volte la mediana delle fasce (1 = normale; mediana " +
                  F(spRef, 1) + " punti = " + PX(spRef * MathPow(10.0, -g_digits)) + ")" :
                  "spread non registrato nelle barre di questo simbolo";
   string desc = "Ogni fascia di 15 minuti dell'orologio del broker (New York + 7: la mezzanotte &egrave; NY 17:00, il rollover). " +
                 "Aperto = % dei giorni di mercato con barre nella fascia (sotto 50% = mercato chiuso); attivit&agrave; = range della barra " +
                 "diviso il range medio delle ultime 24 ore (1 = normale); volume = volume medio della barra in volte la media; " + spTxt +
                 "; punte gi&ugrave; / su = barre con una coda di almeno 2 volte il range normale sotto o sopra il corpo, per 1000 barre: " +
                 "molte pi&ugrave; punte in basso (z &ge; 3) = lo spread che si allarga abbassa il bid (i dati sono prezzi bid) senza scambi " +
                 "veri; movimento z = direzione media delle barre della fascia (entro +/-2 compatibile con il caso). Ora buca = attivit&agrave; e " +
                 "volume sotto 0.6 del normale. Londra = New York + 5 (tranne le settimane in cui l'ora legale cambia in date diverse).";
   SecStart("Ore buche e rollover: la giornata a passi di 15 minuti", desc + " " + RollTxt());
   THead("Broker (NY+7)|New York|Londra|Aperto|Attivit&agrave;|Volume|Spread|Punte gi&ugrave; / su|z punte|Movimento z|Note");
   R(g_repEv, "");
   R(g_repEv, "=== ORE BUCHE E ROLLOVER: la giornata a passi di 15 minuti (orologio del broker New York + 7; mezzanotte = NY 17:00) ===");
   R(g_repEv, "Metodo: " + desc);
   R(g_repEv, RollTxt());
   R(g_repEv, "  Mercato chiuso: " + SlotRuns(fC) + "; ore buche: " + SlotRuns(fT) + "; spread alto: " + SlotRuns(fW) + "; punte del bid: " +
     SlotRuns(fD) + "; finestra del rollover: " + SlotRuns(fR) + " (ora del broker).");
   for(int z = 0; z < 96; z++)
     {
      string pk = barN[z] > 0 ? F(1000.0 * dnS[z] / barN[z], 1) + " / " + F(1000.0 * upS[z] / barN[z], 1) : "-";
      string spc = MathIsValidNumber(sr[z]) ? F(sr[z], 2) + "&times;" : "-";
      W("<tr>" + TD(HM(z * 15)) + TD(HM(z * 15 - 420)) + TD(HM(z * 15 - 120)) + TDc(FP(sh[z], 1) + "%", fC[z] ? "rgba(148,163,184,0.35)" : "") +
        TDc(F(av[z], 2), PCol(av[z], 1.0, 1.0)) + TD(F(vv[z], 2)) + TDc(spc, fW[z] ? "rgba(239,68,68,0.30)" : "") + TD(pk) +
        TDc(SgnF(zA[z], 1), fD[z] ? "rgba(239,68,68,0.30)" : "") + TDc(SgnF(zR[z], 1), PCol(zR[z], 0.0, 4.0)) + TD(note[z]) + "</tr>");
      R(g_repEv, "  " + HM(z * 15) + " (NY " + HM(z * 15 - 420) + ", LDN " + HM(z * 15 - 120) + "): aperto " + FP(sh[z], 1) + "%, attivita' " +
        F(av[z], 2) + ", volume " + F(vv[z], 2) + ", spread " + spc + ", punte giu'/su " + pk + " per 1000 barre (z " + SgnF(zA[z], 1) +
        "), movimento z " + SgnF(zR[z], 1) + (note[z] != "" ? " -> " + note[z] : ""));
     }
   TEnd();
   W("<p class='muted'>Orari tipici (ora del broker New York + 7), da verificare sui tuoi dati con la tabella: forex e oro fanno il " +
     "rollover a mezzanotte (NY 17:00), con lo spread largo di solito tra le 23:55 e le 00:15 e a volte fino all'01:00; le ore pi&ugrave; " +
     "sottili sono tra la chiusura di New York e l'apertura di Tokyo (circa 23:00-02:00); il weekend chiude venerd&igrave; a mezzanotte e " +
     "riapre luned&igrave; alle 00:00. Oro e indici USA hanno di solito una pausa giornaliera di circa un'ora dopo la mezzanotte " +
     "(manutenzione dei future CME, NY 17:00-18:00); gli indici europei sono molto pi&ugrave; sottili fuori dall'orario cash (DAX 09:00-17:30 " +
     "di Francoforte = 10:00-18:30 del broker). Gli orari esatti cambiano da broker a broker.</p>");
   SecEnd();
  }

// notti di swap tra due giorni dell'orologio del broker: ogni mezzanotte da lunedi' a venerdi', tripla nel giorno 'triple'
double CostNights(const long d0, const long d1, const int triple)
  {
   double n = 0;
   for(long d = d0; d < d1; d++)
     {
      int w = (int)((d + 4) % 7);  // 0 = domenica
      if(w >= 1 && w <= 5)
         n += (w == triple ? 3 : 1);
     }
   return n;
  }

void CostInit(const int p, const string nm)
  {
   g_cp[p].name = nm;
   g_cp[p].sym = "";
   g_cp[p].spTxt = "";
   g_cp[p].swTxt = "";
   g_cp[p].cmTxt = "";
   g_cp[p].warn = "";
   g_cp[p].from = "";
   g_cp[p].on = false;
   for(int h = 0; h < 24; h++)
     {
      g_cp[p].sp[h] = 0;
      g_cp[p].spOk[h] = false;
      g_cp[p].spH[h] = 0;
     }
   for(int sd = 0; sd < 2; sd++)
     {
      g_cp[p].swA[sd] = 0;
      g_cp[p].swP[sd] = 0;
     }
   g_cp[p].comm = 0;
   g_cp[p].slip = 0;
   g_cp[p].tv = 0;
   g_cp[p].ts = 0;
   g_cp[p].triple = 5;
   g_rbHead[p] = "";
   g_rrHtml[p] = "";
  }

bool CostTicks(const int p, const string bs)  // spread medio per ora dai tick, pesato per il tempo in cui resta valido
  {
   if(InpSpreadDays <= 0)
      return false;
   double sw[24], sh[24];
   ArrayInitialize(sw, 0.0);
   ArrayInitialize(sh, 0.0);
   long today = (long)TimeTradeServer() / 86400;
   int days = 0;
   long nt = 0;
   MqlTick tk[];
   for(long d = today; d > today - 3 * InpSpreadDays - 10 && days < InpSpreadDays && !IsStopped(); d--)
     {
      ulong a = (ulong)(d * 86400) * 1000, b = (ulong)((d + 1) * 86400) * 1000 - 1;
      int k = CopyTicksRange(bs, tk, COPY_TICKS_INFO, a, b);
      if(k < 100)
         continue;
      days++;
      nt += k;
      for(int i = 0; i + 1 < k; i++)
        {
         if(tk[i].bid <= 0 || tk[i].ask < tk[i].bid)
            continue;
         double dt = (double)(tk[i + 1].time_msc - tk[i].time_msc) / 1000.0;
         if(dt <= 0)
            continue;
         if(dt > 60)
            dt = 60;
         int h = HourOf(SrvToNY7(tk[i].time));
         sw[h] += (tk[i].ask - tk[i].bid) * dt;
         sh[h] += dt;
        }
     }
   ArrayFree(tk);
   bool any = false;
   for(int h = 0; h < 24; h++)
      if(sh[h] >= 600)
        {
         g_cp[p].sp[h] = sw[h] / sh[h];
         g_cp[p].spOk[h] = true;
         g_cp[p].spH[h] = sh[h] / 3600.0;
         any = true;
        }
   if(any)
      g_cp[p].spTxt = "misurato dai tick di " + bs + " degli ultimi " + I2S(days) + " giorni di borsa (" + I2S(nt) +
                      " tick, media pesata per il tempo in cui ogni spread resta in vigore)";
   return any;
  }

bool CostBars(const int p, const string bs)  // riserva: spread salvato nelle barre M1
  {
   int nd = InpSpreadDays > 0 ? InpSpreadDays : 20;
   datetime to = TimeTradeServer(), from = (datetime)((long)to - (long)(nd * 7 / 5 + 3) * 86400);
   MqlRates r[];
   int k = CopyRates(bs, PERIOD_M1, from, to, r);
   if(k < 100)
      return false;
   double pt = SymbolInfoDouble(bs, SYMBOL_POINT);
   double sw[24];
   int sc[24];
   ArrayInitialize(sw, 0.0);
   ArrayInitialize(sc, 0);
   for(int i = 0; i < k; i++)
      if(r[i].spread > 0)
        {
         int h = HourOf(SrvToNY7(r[i].time));
         sw[h] += r[i].spread * pt;
         sc[h]++;
        }
   bool any = false;
   for(int h = 0; h < 24; h++)
      if(sc[h] >= 30)
        {
         g_cp[p].sp[h] = sw[h] / sc[h];
         g_cp[p].spOk[h] = true;
         g_cp[p].spH[h] = sc[h] / 60.0;
         any = true;
        }
   if(any)
      g_cp[p].spTxt = "spread delle barre M1 di " + bs + " (circa " + I2S(nd) + " giorni; MT5 salva uno spread per minuto, di solito il " +
                      "minimo: probabile sottostima. I tick non erano disponibili)";
   return any;
  }

string SwTxt(const int p, const int sd)
  {
   if(g_cp[p].swP[sd] != 0)
      return SgnF(g_cp[p].swP[sd] * 100, 4) + "% del prezzo (circa " + SgnF(g_cp[p].swP[sd] * g_last, g_digits) + ")";
   return SgnF(g_cp[p].swA[sd], g_digits);
  }

void CostSwap(const int p, const string bs)
  {
   long md = SymbolInfoInteger(bs, SYMBOL_SWAP_MODE);
   double v[2];
   v[0] = SymbolInfoDouble(bs, SYMBOL_SWAP_LONG);
   v[1] = SymbolInfoDouble(bs, SYMBOL_SWAP_SHORT);
   double pt = SymbolInfoDouble(bs, SYMBOL_POINT), tv = g_cp[p].tv, ts = g_cp[p].ts;
   string u = "";
   if(md == SYMBOL_SWAP_MODE_DISABLED)
      u = "(swap disattivato)";
   else
      if(md == SYMBOL_SWAP_MODE_POINTS)
        {
         for(int sd = 0; sd < 2; sd++)
            g_cp[p].swA[sd] = v[sd] * pt;
         u = "punti";
        }
      else
         if(md == SYMBOL_SWAP_MODE_INTEREST_CURRENT || md == SYMBOL_SWAP_MODE_INTEREST_OPEN)
           {
            for(int sd = 0; sd < 2; sd++)
               g_cp[p].swP[sd] = v[sd] / 100.0 / 360.0;
            u = "% annuo del prezzo";
           }
         else
            if(md == SYMBOL_SWAP_MODE_REOPEN_CURRENT || md == SYMBOL_SWAP_MODE_REOPEN_BID)
               u = "(a riapertura della posizione: non convertito, swap 0)";
            else
              {
               if(tv > 0 && ts > 0)
                  for(int sd = 0; sd < 2; sd++)
                     g_cp[p].swA[sd] = v[sd] * ts / tv;
               u = tv > 0 && ts > 0 ? "in valuta per lotto" : "in valuta per lotto (non convertibile: valore del tick assente, swap 0)";
              }
   g_cp[p].triple = (int)SymbolInfoInteger(bs, SYMBOL_SWAP_ROLLOVER3DAYS);
   g_cp[p].swTxt = "letto da " + bs + ": buy " + DoubleToString(v[0], 4) + ", sell " + DoubleToString(v[1], 4) + " " + u +
                   "; triplo il " + DOWS[(g_cp[p].triple % 7 + 7) % 7];
  }

string D8(const double x) { return DoubleToString(x, 8); }

string CostFile(const int p, const string key) { return "MarketProfiler_costi_" + NormU(g_cp[p].name) + "_" + key + ".txt"; }

void CostSave(const int p, const string key)  // nella cartella comune: lo legge anche il terminale dell'altro broker
  {
   int fh = FileOpen(CostFile(p, key), FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return;
   string sp = "", sh = "";
   for(int h = 0; h < 24; h++)
     {
      sp += (h > 0 ? ";" : "") + (g_cp[p].spOk[h] ? D8(g_cp[p].sp[h]) : "-1");
      sh += (h > 0 ? ";" : "") + D8(g_cp[p].spH[h]);
     }
   FileWriteString(fh, "simbolo=" + g_cp[p].sym + "\n");
   FileWriteString(fh, "server=" + AccountInfoString(ACCOUNT_SERVER) + "\n");
   FileWriteString(fh, "data=" + TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES) + "\n");
   FileWriteString(fh, "fonte=" + g_cp[p].spTxt + "\n");
   FileWriteString(fh, "spread=" + sp + "\n");
   FileWriteString(fh, "ore=" + sh + "\n");
   FileWriteString(fh, "swap=" + D8(g_cp[p].swA[0]) + ";" + D8(g_cp[p].swA[1]) + ";" + D8(g_cp[p].swP[0]) + ";" + D8(g_cp[p].swP[1]) + "\n");
   FileWriteString(fh, "swaptesto=" + g_cp[p].swTxt + "\n");
   FileWriteString(fh, "triplo=" + I2S(g_cp[p].triple) + "\n");
   FileWriteString(fh, "tick=" + D8(g_cp[p].tv) + ";" + D8(g_cp[p].ts) + "\n");
   FileClose(fh);
   PrintFormat("[MarketProfiler] costi %s salvati in Common\\Files\\%s", g_cp[p].name, CostFile(p, key));
  }

bool CostLoad(const int p, const string key)
  {
   string fn = CostFile(p, key);
   if(!FileIsExist(fn, FILE_COMMON))
      return false;
   int fh = FileOpen(fn, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return false;
   string dt = "", srv = "", src = "";
   while(!FileIsEnding(fh))
     {
      string ln = FileReadString(fh);
      int e = StringFind(ln, "=");
      if(e < 0)
         continue;
      string k = StringSubstr(ln, 0, e), v = StringSubstr(ln, e + 1);
      string q[];
      int nq = StringSplit(v, ';', q);
      if(k == "simbolo")
         g_cp[p].sym = v;
      if(k == "server")
         srv = v;
      if(k == "data")
         dt = v;
      if(k == "fonte")
         src = v;
      if(k == "swaptesto")
         g_cp[p].swTxt = v;
      if(k == "triplo")
         g_cp[p].triple = (int)StringToInteger(v);
      if(k == "spread" && nq == 24)
         for(int h = 0; h < 24; h++)
           {
            double x = StringToDouble(q[h]);
            if(x >= 0)
              {
               g_cp[p].sp[h] = x;
               g_cp[p].spOk[h] = true;
              }
           }
      if(k == "ore" && nq == 24)
         for(int h = 0; h < 24; h++)
            g_cp[p].spH[h] = StringToDouble(q[h]);
      if(k == "swap" && nq == 4)
        {
         g_cp[p].swA[0] = StringToDouble(q[0]);
         g_cp[p].swA[1] = StringToDouble(q[1]);
         g_cp[p].swP[0] = StringToDouble(q[2]);
         g_cp[p].swP[1] = StringToDouble(q[3]);
        }
      if(k == "tick" && nq == 2)
        {
         g_cp[p].tv = StringToDouble(q[0]);
         g_cp[p].ts = StringToDouble(q[1]);
        }
     }
   FileClose(fh);
   g_cp[p].spTxt = src;
   g_cp[p].from = "profilo salvato il " + dt + " dal terminale " + srv + " (Common\\Files\\" + fn + ")";
   return true;
  }

//--- livelli di costo per trade in punti base del prezzo (1 pb = 0,01%): proporzionali al prezzo, quindi confrontabili tra
//--- strumenti e negli anni. Per ogni gruppo di trade: aspettativa e z a ogni livello e costo di pareggio (il costo che la azzera)
#define BP_MAX 6
int    g_bpN = 0;
double g_bpV[BP_MAX];

void CostBpSetup(void)
  {
   g_bpN = 0;
   string p[];
   int k = StringSplit(InpCostBp, ',', p);
   for(int i = 0; i < k && g_bpN < BP_MAX; i++)
     {
      string t = p[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      double v = StringToDouble(t);
      if(t == "" || !(v > 0) || v > 1000)
         continue;
      bool dup = false;
      for(int j = 0; j < g_bpN; j++)
         if(MathAbs(g_bpV[j] - v) < 1e-9)
            dup = true;
      if(!dup)
         g_bpV[g_bpN++] = v;
     }
   if(g_bpN == 0)  // elenco vuoto o non valido: livelli predefiniti
     {
      double dv[4] = {0.5, 1, 2, 4};
      for(int j = 0; j < 4; j++)
         g_bpV[g_bpN++] = dv[j];
     }
   for(int a = 1; a < g_bpN; a++)
      for(int b = a; b > 0 && g_bpV[b] < g_bpV[b - 1]; b--)
        {
         double x = g_bpV[b];
         g_bpV[b] = g_bpV[b - 1];
         g_bpV[b - 1] = x;
        }
  }

string BpNum(const double v) { return DoubleToString(v, v == MathFloor(v) ? 0 : (v * 10 == MathFloor(v * 10) ? 1 : 2)); }
string BpLab(void)
  {
   string t = "";
   for(int j = 0; j < g_bpN; j++)
      t += (j > 0 ? " / " : "") + BpNum(g_bpV[j]);
   return t + " pb";
  }
string BpTxt(const double be) { return MathIsValidNumber(be) ? (be > 0 ? F(be, 1) + " pb" : "nessuno") : "-"; }

// costi dei due broker per lo strumento dei dati: misura nel terminale del broker, altrimenti profilo salvato, altrimenti manuale
void CostSetup(const string dataSym)
  {
   SrvClock();
   CostBpSetup();
   string al[];
   int na = AliasList(SymBase(dataSym), al);
   string key = al[0];
   bool fx = StringLen(al[0]) == 6 && AllLetters(al[0]) && al[0] != "XAUUSD";
   string srv = NormU(AccountInfoString(ACCOUNT_SERVER) + AccountInfoString(ACCOUNT_COMPANY));
   CostInit(0, "lordo");
   for(int b = 1; b < NPRF; b++)
     {
      string nm = b == 1 ? InpB1Name : InpB2Name, us = b == 1 ? InpB1Sym : InpB2Sym;
      ENUM_COST_SRC src = b == 1 ? InpB1Src : InpB2Src;
      double mSp = b == 1 ? InpB1Spread : InpB2Spread, mCm = b == 1 ? InpB1Comm : InpB2Comm;
      double mSL = b == 1 ? InpB1SwapL : InpB2SwapL, mSS = b == 1 ? InpB1SwapS : InpB2SwapS, mSl = b == 1 ? InpB1Slip : InpB2Slip;
      StringTrimLeft(us);
      StringTrimRight(us);
      CostInit(b, nm);
      HI_NAME[5 + b] = "Rischio/rendimento netto " + nm + " (aspettativa dopo i costi contro zero)";
      g_cp[b].triple = fx ? 3 : 5;
      bool gotSw = false;
      if(src == COST_AUTO)
        {
         bool local = us != "" || (StringLen(NormU(nm)) >= 2 && StringFind(srv, NormU(nm)) >= 0);
         string bs = local ? (us != "" ? us : FindBrokerSym(al, na)) : "";
         if(bs != "" && SymbolSelect(bs, true))
           {
            g_cp[b].sym = bs;
            g_cp[b].from = "misurato in questo terminale (" + AccountInfoString(ACCOUNT_SERVER) + ") il " + TimeToString(TimeLocal(), TIME_DATE);
            g_cp[b].tv = SymbolInfoDouble(bs, SYMBOL_TRADE_TICK_VALUE);
            g_cp[b].ts = SymbolInfoDouble(bs, SYMBOL_TRADE_TICK_SIZE);
            Comment("MarketProfiler: spread di ", bs, " (", nm, ") dai tick ...");
            if(!CostTicks(b, bs))
               CostBars(b, bs);
            CostSwap(b, bs);
            gotSw = true;
            CostSave(b, key);
           }
         else
           {
            if(local)
               g_cp[b].warn += "Il server di questo terminale sembra di " + nm + " ma il simbolo " + (us != "" ? us : "dello strumento") +
                               " non c'&egrave;: indicalo nel parametro 'simbolo nel suo terminale'. ";
            if(CostLoad(b, key))
               gotSw = true;
           }
        }
      //--- spread: ore non misurate = la peggiore misurata (prudente); niente misure = valore manuale a tutte le ore
      double mx = 0;
      bool any = false;
      for(int h = 0; h < 24; h++)
         if(g_cp[b].spOk[h])
           {
            any = true;
            if(g_cp[b].sp[h] > mx)
               mx = g_cp[b].sp[h];
           }
      if(any)
        {
         for(int h = 0; h < 24; h++)
            if(!g_cp[b].spOk[h])
               g_cp[b].sp[h] = mx;
        }
      else
        {
         for(int h = 0; h < 24; h++)
            g_cp[b].sp[h] = mSp;
         g_cp[b].spTxt = mSp > 0 ? "manuale (parametro): " + PX(mSp) + " a tutte le ore" : "nessuno: non misurato e valore manuale 0";
        }
      if(!gotSw)
        {
         g_cp[b].swA[0] = mSL;
         g_cp[b].swA[1] = mSS;
         g_cp[b].swTxt = (mSL != 0 || mSS != 0) ? "manuale (parametri): buy " + SgnF(mSL, g_digits) + ", sell " + SgnF(mSS, g_digits) +
                         " per notte; triplo il " + DOWS[g_cp[b].triple] + (fx ? " (forex)" : " (indici)") :
                         "nessuno: non letto dal simbolo e valori manuali 0";
        }
      //--- commissione: MT5 non la espone, viene dai parametri e si converte in prezzo con il valore del tick
      double tv = g_cp[b].tv, ts = g_cp[b].ts;
      if(!(tv > 0 && ts > 0))
        {
         tv = SymbolInfoDouble(dataSym, SYMBOL_TRADE_TICK_VALUE);
         ts = SymbolInfoDouble(dataSym, SYMBOL_TRADE_TICK_SIZE);
        }
      if(mCm > 0 && tv > 0 && ts > 0)
        {
         g_cp[b].comm = mCm * ts / tv;
         g_cp[b].cmTxt = DoubleToString(mCm, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + " per lotto andata e ritorno (parametro) = " +
                         PX(g_cp[b].comm) + " di prezzo";
        }
      else
         if(mCm > 0)
           {
            g_cp[b].cmTxt = "non convertibile in prezzo (valore del tick assente): 0";
            g_cp[b].warn += "Commissione non applicata: manca il valore del tick. ";
           }
         else
            g_cp[b].cmTxt = "0 (parametro; sugli indici FP Markets e IC Markets di solito non c'&egrave;, sul forex dei conti Raw s&igrave;)";
      g_cp[b].slip = mSl;
      bool on = g_cp[b].comm > 0 || g_cp[b].slip > 0;
      for(int h = 0; h < 24; h++)
         if(g_cp[b].sp[h] > 0)
            on = true;
      for(int sd = 0; sd < 2; sd++)
         if(g_cp[b].swA[sd] != 0 || g_cp[b].swP[sd] != 0)
            on = true;
      g_cp[b].on = on;
      PrintFormat("[MarketProfiler] costi %s: simbolo %s; spread %s; swap %s; commissione %s; slittamento %s", nm,
                  g_cp[b].sym == "" ? "-" : g_cp[b].sym, g_cp[b].spTxt, g_cp[b].swTxt, g_cp[b].cmTxt, PX(g_cp[b].slip));
     }
   //--- nessun broker con costi: i valori "netti" coincidono con i lordi, va detto in testa al rapporto
   bool anyCost = false;
   for(int b = 1; b < NPRF; b++)
      if(g_cp[b].on)
         anyCost = true;
   HI_NAME[8] = anyCost ? "Coppie di contesti (aspettativa netta del broker peggiore contro zero)" :
                "Coppie di contesti (aspettativa LORDA contro zero: costi dei broker non disponibili)";
   if(!anyCost)
      g_warn += (g_warn != "" ? " " : "") + "Costi dei broker non impostati: ogni valore netto o 'netta peggiore' coincide con il lordo.";
  }

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
string CostBpTxt(void)  // costo tipico di ogni broker in punti base, per confronto con il costo di pareggio
  {
   string t = "";
   for(int p = 1; p < NPRF; p++)
      if(g_cp[p].on)
         t += (t != "" ? ", " : "") + g_cp[p].name + " circa " + F(CostBp(p), 2) + " pb";
   return t != "" ? t : "costi dei broker non disponibili";
  }

// sezione iniziale della scheda di un broker: da dove vengono i costi e spread per ora (tabella e testo)
void CostHtml(const int p)
  {
   string nm = g_cp[p].name, tz = InpDataTZ == TZ_BROKER_NY7 ? "" : " (ora del broker, New York + 7)";
   int tri = (g_cp[p].triple % 7 + 7) % 7;
   SecStart("Costi " + nm + ": da dove vengono e come si applicano",
            "Ogni trade della scheda R/R lordo viene ricalcolato con i costi di " + nm + ". <b>Spread</b>: i dati sono prezzi " +
            "bid, quindi il buy paga lo spread dell'ora in cui entra (compra all'ask) e il sell quello dell'ora in cui esce (ricompra " +
            "all'ask). <b>Swap</b>: per ogni mezzanotte del broker (New York + 7) tra entrata e uscita, da luned&igrave; a " +
            "venerd&igrave;, triplo il " + DOWS[tri] + ". <b>Commissione</b> e <b>slittamento</b>: fissi per trade (parametri; MT5 " +
            "non espone la commissione del conto). Lo spread misurato negli ultimi giorni &egrave; applicato a tutto lo storico: negli " +
            "anni passati poteva essere diverso. <b>Come avere i costi di entrambi i broker</b>: la misura automatica funziona nel " +
            "terminale del broker (il nome del broker deve comparire nel nome del server del conto). Lancia lo script una volta nel " +
            "terminale di ciascun broker (con 'Solo misura dei costi' = true basta un grafico qualsiasi dello strumento): il profilo " +
            "viene salvato nella cartella comune dei terminali e letto automaticamente dall'altro terminale. In alternativa inserisci " +
            "spread, swap e commissione a mano nei parametri.");
   if(!g_cp[p].on)
      W("<p style='color:#f59e0b'>Nessun costo disponibile per " + nm + ": misura i costi nel terminale di " + nm + " oppure inserisci " +
        "i valori manuali. Finch&eacute; i costi sono zero questa scheda coinciderebbe con il rischio/rendimento lordo e non viene ripetuta.</p>");
   if(g_cp[p].warn != "")
      W("<p style='color:#f59e0b'>" + g_cp[p].warn + "</p>");
   double med = CostSpMed(p), mn = 1e18, mx = 0;
   int hMn = 0, hMx = 0;
   for(int h = 0; h < 24; h++)
     {
      if(!g_cp[p].spOk[h])
         continue;
      if(g_cp[p].sp[h] < mn)
        {
         mn = g_cp[p].sp[h];
         hMn = h;
        }
      if(g_cp[p].sp[h] > mx)
        {
         mx = g_cp[p].sp[h];
         hMx = h;
        }
     }
   bool anyOk = mx > 0;
   string spv = anyOk ? "mediano " + PX(med) + ", minimo " + PX(mn) + " (" + StringFormat("%02dh", hMn) + "), massimo " + PX(mx) + " (" +
                StringFormat("%02dh", hMx) + ")" : (med > 0 ? PX(med) + " a tutte le ore" : "0");
   THead("Voce|Valore|Fonte");
   W("<tr>" + TD("Simbolo del broker") + TD(g_cp[p].sym != "" ? g_cp[p].sym : "-") + TD(g_cp[p].from != "" ? g_cp[p].from : "valori manuali") + "</tr>");
   W("<tr>" + TD("Spread") + TD(spv) + TD(g_cp[p].spTxt) + "</tr>");
   W("<tr>" + TD("Swap buy per notte (positivo = accredito)") + TD(SwTxt(p, 0)) + TD(g_cp[p].swTxt) + "</tr>");
   W("<tr>" + TD("Swap sell per notte") + TD(SwTxt(p, 1)) + TD("") + "</tr>");
   W("<tr>" + TD("Commissione per trade") + TD(PX(g_cp[p].comm)) + TD(g_cp[p].cmTxt) + "</tr>");
   W("<tr>" + TD("Slittamento per trade") + TD(PX(g_cp[p].slip)) + TD("parametro") + "</tr>");
   TEnd();
   R(g_rbHead[p], "COSTI " + nm + (g_cp[p].on ? "" : " - NESSUN COSTO DISPONIBILE (scheda non calcolata)"));
   R(g_rbHead[p], "  Simbolo del broker: " + (g_cp[p].sym != "" ? g_cp[p].sym : "-") + "; fonte: " + (g_cp[p].from != "" ? g_cp[p].from : "valori manuali"));
   R(g_rbHead[p], "  Spread: " + spv + " - " + g_cp[p].spTxt);
   R(g_rbHead[p], "  Swap per notte: buy " + SwTxt(p, 0) + ", sell " + SwTxt(p, 1) + " - " + g_cp[p].swTxt);
   R(g_rbHead[p], "  Commissione per trade: " + PX(g_cp[p].comm) + " - " + g_cp[p].cmTxt + "; slittamento per trade: " + PX(g_cp[p].slip));
   R(g_rbHead[p], "  Regole: il buy paga lo spread dell'ora di entrata, il sell quello dell'ora di uscita; swap per ogni mezzanotte del broker " +
     "da lunedi' a venerdi', triplo il " + DOWS[tri] + "; lo spread recente e' applicato a tutto lo storico.");
   if(g_cp[p].warn != "")
      R(g_rbHead[p], "  Avvisi: " + g_cp[p].warn);
   W("<h3>Spread per ora</h3><p class='desc'>Spread medio in ogni ora dell'orologio del broker. Le ore senza misura (mercato chiuso " +
     "dal broker o pochi dati) usano lo spread pi&ugrave; alto misurato, per prudenza.</p>");
   THead("Ora" + tz + "|Spread medio (prezzo)|% del prezzo attuale|Misurato|Ore osservate");
   string ln = "";
   for(int h = 0; h < 24; h++)
     {
      string hl = InpDataTZ == TZ_BROKER_NY7 ? HourLab(h) : StringFormat("%02dh", h);
      W("<tr>" + TD(hl) + TD(PX(g_cp[p].sp[h])) + TD(g_last > 0 ? FP(g_cp[p].sp[h] / g_last, 4) : "-") +
        TD(g_cp[p].spOk[h] ? "s&igrave;" : (anyOk ? "no (usato il pi&ugrave; alto)" : "no")) + TD(F(g_cp[p].spH[h], 1)) + "</tr>");
      ln += (h > 0 ? ", " : "") + StringFormat("%02dh ", h) + PX(g_cp[p].sp[h]) + (g_cp[p].spOk[h] ? "" : "*");
     }
   TEnd();
   R(g_rbHead[p], "  Spread per ora (orologio del broker, * = non misurato): " + ln);
   SecEnd();
  }

//+------------------------------------------------------------------+
//| Rischio / rendimento: a ogni apertura di candela si aprono un buy |
//| e un sell con lo stesso stop e si guarda, barra per barra, se il  |
//| prezzo arriva a 1, 2, 3, 4, 5 volte lo stop prima dello stop      |
//+------------------------------------------------------------------+
#define RR_NR     5
#define RR_NTF    6
#define RR_MAXROW 170
#define RR_NDIM   20
int    RR_MIN[RR_NTF]  = {5, 15, 30, 60, 240, 1440};
string RR_NAME[RR_NTF] = {"M5", "M15", "M30", "H1", "H4", "D1"};
string g_rrTxS[NPRF], g_rrTxT[NPRF], g_rrTxA[NPRF];  // testo per profilo: riepilogo per timeframe, contesti migliori e peggiori, tutti
int    g_rrNR = 0;
string g_rrLab[RR_MAXROW];
int    g_rrDim[RR_MAXROW];
int    g_rrDimB[RR_NDIM], g_rrDimC[RR_NDIM];
string g_rrDimN[RR_NDIM];
int    g_rrN[], g_rrNH[];                     // per riga: trade, trade per meta' del campione
double g_rrInvS[];
int    g_rrW[], g_rrT[], g_rrA[];             // per riga, lato e obiettivo: vinti, chiusi a tempo, esiti ambigui
double g_rrS[], g_rrS2[], g_rrD[];            // esiti lordi (R), quadrati, durate (candele)
double g_rrSN[], g_rrCP[], g_rrSH[];          // per profilo: esiti netti (R), costo (prezzo), esiti netti per meta' del campione
int    g_rrGap[];                             // per riga: coppie di entrate a distanza g candele (1..L), per la sovrapposizione
int    g_rrL = 1;
//--- confronto con la stessa ora: ogni trade e' confrontato con l'aspettativa di tutti i trade della sua ora (contesti singoli
//--- del timeframe; sul D1 con tutte le candele). Quello che resta e' cio' che il contesto aggiunge all'orario
#define RR_NH 24
int    g_rrHN[];                              // per riga e ora: trade
double g_rrHS[];                              // per riga, ora e operazione: somma degli esiti lordi
double g_rrBH[];                              // aspettativa della stessa ora per profilo, ora e operazione (riferimento)
bool   g_rrBOk = false, g_rrIntra = true, g_rrPair = false;
//--- placebo: buy e sell nello stesso istante con lo stesso stop e obiettivo; direzione a caso = media dei due
double g_rrX[];                               // per riga e obiettivo: somma dei prodotti esito buy x esito sell
//--- livelli di costo in punti base: costo di 1 pb in R (somma e quadrati per riga), prodotto con l'esito (per riga e operazione)
double g_rrU[], g_rrU2[], g_rrOU[];
//--- ogni trade simulato del timeframe in corso (indice q; lato e obiettivo i: q * 2 * RR_NR + i; dimensione d: q * RR_NDIM + d)
int    g_qN = 0;
int    g_qK[], g_qF[], g_qX[];                // candela di entrata, bit vinto / chiuso a tempo / ambiguo, barra di uscita
float  g_qS[], g_qO[], g_qD[];                // stop (prezzo), esito lordo (R), durata (candele)
uchar  g_qC[];                                // classe del contesto (255 = nessuna)
string g_cbHtml = "", g_sqHtml = "", g_ruHtml = "", g_cbTx = "", g_sqTx = "", g_ruTx = "";
int    g_csvH = INVALID_HANDLE, g_ruH = INVALID_HANDLE, g_ruN = 0, g_ruReal = 0;
string g_ruFile = "";

void RRDim(const int d, const string name, const string labs)
  {
   string p[];
   int k = StringSplit(labs, '|', p);
   g_rrDimB[d] = g_rrNR;
   g_rrDimN[d] = name;
   for(int i = 0; i < k && g_rrNR < RR_MAXROW; i++)
     {
      g_rrDim[g_rrNR] = d;
      g_rrLab[g_rrNR++] = p[i];
     }
   g_rrDimC[d] = g_rrNR - g_rrDimB[d];
  }

// Buy e sell aperti al prezzo O all'apertura della barra j0, stop a distanza S, chiusura a mercato alla barra jEnd.
// Esiti in R per ogni lato (0 buy, 1 sell) e obiettivo (1..5), indice sd * RR_NR + R - 1. Se nella stessa barra
// il prezzo tocca lo stop e un obiettivo non ancora raggiunto l'ordine non si conosce: conta come stop (prudente).
// Se una barra apre gia' oltre lo stop (gap del weekend o di una notizia) la perdita e' al prezzo di apertura, oltre -1 R.
// Durate in candele del timeframe (cs/ce = prima e ultima+1 barra di ogni candela, k = candela di entrata); ex = barra di uscita.
void RRWalk(CSeries &s, const int &cs[], const int &ce[], const int k, const int jEnd, const double O, const double S,
            const int tfSec, const int barSec, const int L, double &o[], bool &wn[], bool &tm[], bool &am[], double &du[], int &ex[])
  {
   double mfe[2], tS[2], tR[2 * RR_NR], ls[2];
   int qS[2], qR[2 * RR_NR];
   bool done[2], stp[2];
   for(int sd = 0; sd < 2; sd++)
     {
      mfe[sd] = 0;
      ls[sd] = 1;
      tS[sd] = 0;
      qS[sd] = jEnd;
      done[sd] = false;
      stp[sd] = false;
     }
   for(int i = 0; i < 2 * RR_NR; i++)
     {
      tR[i] = 0;
      qR[i] = jEnd;
      am[i] = false;
      wn[i] = false;
      tm[i] = false;
     }
   int kk = k;
   double tLast = L;
   for(int q = cs[k]; q <= jEnd && !(done[0] && done[1]); q++)
     {
      while(q >= ce[kk])
         kk++;
      double fr = ((double)((long)s.t[q] - (long)s.t[cs[kk]]) + barSec) / tfSec;
      double tq = (kk - k) + (fr < 1 ? fr : 1);
      tLast = tq;
      for(int sd = 0; sd < 2; sd++)
        {
         if(done[sd])
            continue;
         double fav = sd == 0 ? (s.h[q] - O) / S : (O - s.l[q]) / S;
         double adv = sd == 0 ? (O - s.l[q]) / S : (s.h[q] - O) / S;
         if(adv >= 1.0)
           {
            for(int tg = 1; tg <= RR_NR; tg++)
               if(mfe[sd] < tg && fav >= tg)
                  am[sd * RR_NR + tg - 1] = true;
            double gp = sd == 0 ? (O - s.o[q]) / S : (s.o[q] - O) / S;
            ls[sd] = (q > cs[k] && gp > 1) ? gp : 1;
            stp[sd] = true;
            done[sd] = true;
            tS[sd] = tq;
            qS[sd] = q;
           }
         else
            if(fav > mfe[sd])
              {
               for(int tg = 1; tg <= RR_NR; tg++)
                  if(mfe[sd] < tg && fav >= tg)
                    {
                     tR[sd * RR_NR + tg - 1] = tq;
                     qR[sd * RR_NR + tg - 1] = q;
                    }
               mfe[sd] = fav;
               if(mfe[sd] >= RR_NR)
                  done[sd] = true;
              }
        }
     }
   for(int sd = 0; sd < 2; sd++)
     {
      double mark = sd == 0 ? (s.c[jEnd] - O) / S : (O - s.c[jEnd]) / S;
      for(int tg = 1; tg <= RR_NR; tg++)
        {
         int i = sd * RR_NR + tg - 1;
         if(mfe[sd] >= tg)
           {
            o[i] = tg;
            wn[i] = true;
            du[i] = tR[i];
            ex[i] = qR[i];
           }
         else
            if(stp[sd])
              {
               o[i] = -ls[sd];
               du[i] = tS[sd];
               ex[i] = qS[sd];
              }
            else
              {
               o[i] = mark;
               tm[i] = true;
               du[i] = jEnd < ce[k + L - 1] - 1 ? tLast : L;  // chiusa prima delle L candele (rollover)
               ex[i] = jEnd;
              }
        }
     }
  }

// cst = costo in prezzo per profilo, lato e obiettivo (indice p * 2 * RR_NR + i); hf = meta' del campione (0 o 1);
// hs = ora della candela (0 sul D1); u = costo di 1 punto base del prezzo in R
void RRAcc(const int r, const double &o[], const bool &wn[], const bool &tm[], const bool &am[], const double &du[],
           const double invS, const double &cst[], const int hf, const int hs, const double u)
  {
   if(r < 0 || r >= g_rrNR)
      return;
   int nx = g_rrNR * 2 * RR_NR, hb = (r * RR_NH + hs) * 2 * RR_NR;
   g_rrN[r]++;
   g_rrNH[r * 2 + hf]++;
   g_rrInvS[r] += invS;
   g_rrHN[r * RR_NH + hs]++;
   g_rrU[r] += u;
   g_rrU2[r] += u * u;
   for(int tg = 0; tg < RR_NR; tg++)
      g_rrX[r * RR_NR + tg] += o[tg] * o[RR_NR + tg];
   for(int i = 0; i < 2 * RR_NR; i++)
     {
      int x = r * 2 * RR_NR + i;
      if(wn[i])
         g_rrW[x]++;
      if(tm[i])
         g_rrT[x]++;
      if(am[i])
         g_rrA[x]++;
      g_rrS[x] += o[i];
      g_rrS2[x] += o[i] * o[i];
      g_rrD[x] += du[i];
      g_rrSN[x] += o[i];
      g_rrHS[hb + i] += o[i];
      g_rrOU[x] += o[i] * u;
      g_rrSH[hf * nx + x] += o[i];
      for(int p = 1; p < NPRF; p++)
        {
         if(!g_cp[p].on)
            continue;
         double c = cst[p * 2 * RR_NR + i], on = o[i] - c * invS;
         g_rrSN[p * nx + x] += on;
         g_rrCP[p * nx + x] += c;
         g_rrSH[(p * 2 + hf) * nx + x] += on;
        }
     }
  }

// entrata alla candela k nella riga r: conta le distanze dalle entrate precedenti della stessa riga entro L candele
void RRGap(const int r, const int k, int &ring[], int &rN[], int &rP[])
  {
   int L = g_rrL, b = r * L;
   for(int j = 0; j < rN[r]; j++)
     {
      int g = k - ring[b + j];
      if(g >= 1 && g <= L)
         g_rrGap[r * (L + 1) + g]++;
     }
   ring[b + rP[r]] = k;
   rP[r] = (rP[r] + 1) % L;
   if(rN[r] < L)
      rN[r]++;
  }

// N effettivo: due trade a g candele di distanza con durata media dm hanno esiti correlati circa 1 - g/dm
// (varianza della somma = var * (n + 2 * somma delle correlazioni tra coppie)). Entrate fitte: circa n / dm; sparse: n.
double RRNeff(const int r, const int n, const double dm)
  {
   int L = g_rrL;
   double ps = 0;
   for(int g = 1; g <= L && g < dm; g++)
      ps += g_rrGap[r * (L + 1) + g] * (1.0 - g / dm);
   double den = n + 2 * ps;
   return den > 0 ? (double)n * n / den : n;
  }

struct RRSt
  {
   int               n, n1, n2;
   double            win, eg, en, z, za, cm, tmo, amb, dm, cr, cp, e1, e2;
   double            lh, lhn, zh;   // differenza dalla stessa ora (lorda, del profilo) e suo z
   double            pl, pln, zp;   // placebo (direzione a caso nello stesso istante: lordo, del profilo) e z del vantaggio sul placebo
   double            ub, cmb;       // costo di 1 punto base in R (media) e costo di pareggio in punti base
   bool              st;  // stesso segno nelle due meta' del campione
  };

// riga senza confronto con la stessa ora: 'Tutte le candele' e le righe delle ore (la differenza e' zero per costruzione)
bool RRNoLift(const int r) { return r == 0 || (!g_rrPair && g_rrIntra && r < RR_MAXROW && g_rrDim[r] == 1); }

// win = % obiettivo prima dello stop, eg/en = aspettativa lorda/netta in R, z con N effettivo (i trade aperti a candele
// vicine si sovrappongono: RRNeff), za = z della differenza dalla riga 'Tutte le candele',
// cm = costo per trade che azzera l'aspettativa lorda (prezzo), cr/cp = costo medio in R e in prezzo, e1/e2 = meta' del campione;
// lh/zh = differenza dalla stessa ora (ogni trade meno l'aspettativa della sua ora) e z; pl/zp = placebo e z del vantaggio sul
// placebo (buy meno sell nello stesso istante, diviso 2: z sulle differenze trade per trade); cmb = costo di pareggio in punti base
bool RRStat(const int p, const int r, const int i, RRSt &q)
  {
   int n = g_rrN[r];
   q.n = n;
   q.lh = Nan();
   q.lhn = Nan();
   q.zh = Nan();
   q.pl = Nan();
   q.pln = Nan();
   q.zp = Nan();
   q.ub = Nan();
   q.cmb = Nan();
   if(n <= 0)
      return false;
   int nx = g_rrNR * 2 * RR_NR, x = r * 2 * RR_NR + i;
   q.win = (double)g_rrW[x] / n;
   q.eg = g_rrS[x] / n;
   q.en = g_rrSN[p * nx + x] / n;
   q.dm = g_rrD[x] / n;
   double var = g_rrS2[x] / n - q.eg * q.eg, neff = RRNeff(r, n, q.dm);
   q.z = var > 0 ? q.en / MathSqrt(var / neff) : Nan();
   q.cm = g_rrInvS[r] > 0 ? g_rrS[x] / g_rrInvS[r] : Nan();
   q.tmo = (double)g_rrT[x] / n;
   q.amb = (double)g_rrA[x] / n;
   q.cr = q.eg - q.en;
   q.cp = g_rrCP[p * nx + x] / n;
   q.n1 = g_rrNH[r * 2];
   q.n2 = g_rrNH[r * 2 + 1];
   q.e1 = q.n1 > 0 ? g_rrSH[(p * 2) * nx + x] / q.n1 : Nan();
   q.e2 = q.n2 > 0 ? g_rrSH[(p * 2 + 1) * nx + x] / q.n2 : Nan();
   q.st = q.n1 >= 30 && q.n2 >= 30 && q.e1 * q.en > 0 && q.e2 * q.en > 0;
   q.za = Nan();
   int n0 = g_rrN[0];
   if(r > 0 && n0 > 0)
     {
      double eg0 = g_rrS[i] / n0, en0 = g_rrSN[p * nx + i] / n0, v0 = g_rrS2[i] / n0 - eg0 * eg0;
      double ne0 = RRNeff(0, n0, g_rrD[i] / n0);
      double v = (var > 0 ? var / neff : 0) + (v0 > 0 ? v0 / ne0 : 0);
      q.za = v > 0 ? (q.en - en0) / MathSqrt(v) : Nan();
     }
   //--- stessa ora: somma su ogni ora dei trade della riga per l'aspettativa di quell'ora (varianza esatta dei residui)
   if(g_rrBOk && !RRNoLift(r))
     {
      double sb = 0, sbb = 0, sbs = 0, sbn = 0;
      for(int h = 0; h < RR_NH; h++)
        {
         int nh = g_rrHN[r * RR_NH + h];
         if(nh <= 0)
            continue;
         double b0 = g_rrBH[h * 2 * RR_NR + i], bp = g_rrBH[(p * RR_NH + h) * 2 * RR_NR + i];
         sb += nh * b0;
         sbb += nh * b0 * b0;
         sbs += b0 * g_rrHS[(r * RR_NH + h) * 2 * RR_NR + i];
         sbn += nh * bp;
        }
      q.lh = (g_rrS[x] - sb) / n;
      q.lhn = (g_rrSN[p * nx + x] - sbn) / n;
      double vr = (g_rrS2[x] - 2 * sbs + sbb) / n - q.lh * q.lh;
      q.zh = vr > 1e-9 * (var + 1e-12) ? q.lhn / MathSqrt(vr / neff) : Nan();
     }
   //--- placebo: direzione a caso = media di buy e sell con lo stesso obiettivo; vantaggio = operazione - placebo
   int tg0 = i % RR_NR, xb = r * 2 * RR_NR + tg0, xs = xb + RR_NR;
   double eb = g_rrS[xb] / n, es = g_rrS[xs] / n;
   q.pl = 0.5 * (eb + es);
   q.pln = 0.5 * (g_rrSN[p * nx + xb] + g_rrSN[p * nx + xs]) / n;
   double vb = g_rrS2[xb] / n - eb * eb, vs = g_rrS2[xs] / n - es * es, cv = g_rrX[r * RR_NR + tg0] / n - eb * es;
   double vd = 0.25 * (vb + vs - 2 * cv), ne2 = RRNeff(r, n, 0.5 * (g_rrD[xb] + g_rrD[xs]) / n);
   q.zp = vd > 1e-9 * (vb + vs + 1e-12) ? (q.en - q.pln) / MathSqrt(vd / ne2) : Nan();
   //--- costo di pareggio in punti base del prezzo
   q.ub = g_rrU[r] / n;
   q.cmb = q.ub > 0 ? q.eg / q.ub : Nan();
   return true;
  }

// aspettativa lorda e z con un costo per trade di c punti base del prezzo (varianza esatta: il costo in R cambia da trade a trade)
void RRNetBp(const int r, const int i, const double c, double &e, double &z)
  {
   e = Nan();
   z = Nan();
   int n = g_rrN[r];
   if(n <= 0)
      return;
   int x = r * 2 * RR_NR + i;
   double m = g_rrS[x] / n, ub = g_rrU[r] / n;
   double vr = g_rrS2[x] / n - m * m, vu = g_rrU2[r] / n - ub * ub, cv = g_rrOU[x] / n - m * ub;
   double v = vr - 2 * c * cv + c * c * vu, ne = RRNeff(r, n, g_rrD[x] / n);
   e = m - c * ub;
   z = v > 0 ? e / MathSqrt(v / ne) : Nan();
  }

string RRLev(const int r, const int i, string &zt)  // aspettativa lorda a ogni livello di costo (" / ") e i loro z in zt
  {
   string t = "";
   zt = "";
   for(int j = 0; j < g_bpN; j++)
     {
      double e = 0, z = 0;
      RRNetBp(r, i, g_bpV[j], e, z);
      t += (j > 0 ? " / " : "") + SgnF(e, 3);
      zt += (j > 0 ? ", " : "") + BpNum(g_bpV[j]) + " pb z " + ZS(z);
     }
   return t;
  }

// riferimento della stessa ora, dai contesti singoli appena accumulati (righe delle ore; sul D1 la riga 'Tutte le candele')
void RRBase(void)
  {
   int nx = g_rrNR * 2 * RR_NR;
   ArrayResize(g_rrBH, NPRF * RR_NH * 2 * RR_NR);
   ArrayInitialize(g_rrBH, 0.0);
   for(int h = 0; h < RR_NH; h++)
     {
      int r = 0;
      if(g_rrIntra && h < g_rrDimC[1] && g_rrN[g_rrDimB[1] + h] > 0)
         r = g_rrDimB[1] + h;
      if(g_rrN[r] <= 0)
         continue;
      for(int p = 0; p < NPRF; p++)
         for(int i = 0; i < 2 * RR_NR; i++)
            g_rrBH[(p * RR_NH + h) * 2 * RR_NR + i] = g_rrSN[p * nx + r * 2 * RR_NR + i] / g_rrN[r];
     }
   g_rrBOk = true;
  }

// il contesto aggiunge qualcosa alla stessa ora: differenza netta del broker peggiore (lorda senza costi) positiva
bool RRLiftOk(const int r, const int i)
  {
   if(!g_rrBOk || RRNoLift(r))
      return true;
   bool any = false;
   for(int p = 1; p < NPRF; p++)
     {
      if(!g_cp[p].on)
         continue;
      RRSt q;
      RRStat(p, r, i, q);
      if(!(q.lhn > 0))
         return false;
      any = true;
     }
   if(!any)
     {
      RRSt q;
      RRStat(0, r, i, q);
      return q.lhn > 0;
     }
   return true;
  }

string RRVerd(RRSt &q)
  {
   if(!MathIsValidNumber(q.en) || !MathIsValidNumber(q.z))
      return "-";
   if(q.en <= 0)
      return q.z <= -2 ? "negativa" : "circa zero o negativa";
   string v = "positiva ma compatibile con il caso";
   if(q.z >= 3 && q.st)
      v = "positiva, solida, stabile nelle due met&agrave;";
   else
      if(q.z >= 2)
         v = q.st ? "positiva, stabile nelle due met&agrave;" : "positiva, ma non in entrambe le met&agrave;";
   if(q.z >= 2)
     {
      //--- i controlli: la stessa ora rende quasi lo stesso (il contesto non aggiunge nulla all'orario), oppure rende anche la
      //--- direzione opposta (conta il movimento, non la direzione)
      if(MathIsValidNumber(q.zh) && q.zh < 1)
         v += "; la spiega l'orario";
      if(MathIsValidNumber(q.zp) && q.zp < 1)
         v += "; non dipende dalla direzione";
     }
   return v;
  }

string RRCm(RRSt &q) { return q.cm > 0 ? PX(q.cm) + " (" + F(q.cmb, 1) + " pb)" : "-"; }  // costo massimo sostenibile: prezzo e punti base
string ZhLab(void) { return g_rrIntra ? "z rispetto alla stessa ora" : "z rispetto a tutte le candele"; }

string RRCellH(const int p, const int r, const int i)
  {
   RRSt q;
   if(!RRStat(p, r, i, q))
      return TD("-");
   string bg = PCol(q.z, 0, 4);
   string tip = "lorda " + SgnF(q.eg, 3) + (p > 0 ? ", costo " + F(q.cr, 3) + ", netta " + SgnF(q.en, 3) : "") + " R; z " + ZS(q.z) +
                ", vs tutte " + ZS(q.za) + (MathIsValidNumber(q.zh) ? ", vs stessa ora " + SgnF(q.lhn, 3) + " (z " + ZS(q.zh) + ")" : "") +
                "; placebo " + SgnF(q.pln, 3) + ", vs placebo z " + ZS(q.zp) + "; met&agrave; " + SgnF(q.e1, 2) + " / " + SgnF(q.e2, 2) +
                "; a tempo " + FP(q.tmo, 0) + "%; durata " + F(q.dm, 1) + "; costo max " + RRCm(q);
   return "<td title='" + tip + "'" + (bg != "" ? " style='background:" + bg + "'" : "") + ">" + FP(q.win, 1) + "% &middot; " +
          SgnF(q.en, 2) + (q.st ? "" : "*") + "</td>";
  }

string RRCellT(const int p, const int r, const int i)
  {
   RRSt q;
   if(!RRStat(p, r, i, q))
      return "-";
   return "1:" + I2S(i % RR_NR + 1) + " " + FP(q.win, 1) + "% " + SgnF(q.en, 2) + " z" + ZS(q.z) + (q.st ? "" : "*");
  }

double HistMed(const int &h[], const int off, const int nb, const double scale)
  {
   int tot = 0;
   for(int b = 0; b < nb; b++)
      tot += h[off + b];
   if(tot <= 0)
      return Nan();
   int acc = 0;
   for(int b = 0; b < nb; b++)
     {
      acc += h[off + b];
      if(2 * acc >= tot)
         return (b + 0.5) / scale;
     }
   return Nan();
  }

// tabelle e testo di un timeframe per un profilo di costo (0 = lordo); la chiamata per i broker scrive nel buffer della loro scheda
void RRRender(const int p, const int ti, const string head, const double tfH, const int &hw[], const int &hs[], const int HB)
  {
   string nm = RR_NAME[ti];
   string sn[2] = {"Buy", "Sell"};
   string pn = p == 0 ? "lordo (senza costi)" : "netto " + g_cp[p].name;
   int hm = 5 + p;  // sezione del riepilogo
   string hd = head;
   if(p > 0)
     {
      RRSt qb, qs;
      RRStat(p, 0, 0, qb);
      RRStat(p, 0, RR_NR, qs);
      hd += " Costi " + g_cp[p].name + ": costo medio per trade " + PX(qb.cp) + " (" + F(qb.cr, 3) + " R) per il buy 1:1, " + PX(qs.cp) +
            " (" + F(qs.cr, 3) + " R) per il sell 1:1; spread mediano " + PX(CostSpMed(p)) + ".";
     }
   SecStart("Rischio/rendimento " + nm + " " + pn + ": un buy e un sell a ogni apertura di candela", hd);
   if(p == 0)
      THead("Operazione|% obiettivo prima dello stop|% stop|% chiusi a tempo|Senza vantaggio sarebbe|Aspettativa (R per trade)|z|" +
            "Placebo: direzione a caso (R)|z contro il placebo|Prima / seconda met&agrave; (R)|Costo massimo sostenibile (prezzo e pb)|" +
            "Aspettativa con costo di " + BpLab() + " (R)|Tempo mediano all'obiettivo|Tempo mediano allo stop|% esiti ambigui|Lettura");
   else
      THead("Operazione|% obiettivo prima dello stop|Senza vantaggio sarebbe|Aspettativa lorda (R)|Costo medio per trade|Costo medio (R)|" +
            "Aspettativa netta (R)|z|Placebo netto (R)|z contro il placebo|Prima / seconda met&agrave; netta (R)|Costo massimo sostenibile (prezzo e pb)|Lettura");
   R(g_rrTxS[p], "");
   R(g_rrTxS[p], "Rischio/rendimento " + nm + " " + pn + ": " + hd);
   for(int sd = 0; sd < 2; sd++)
      for(int tg = 1; tg <= RR_NR; tg++)
        {
         int i = sd * RR_NR + tg - 1;
         RRSt q;
         RRStat(p, 0, i, q);
         double stp = 1 - q.win - q.tmo, be = 1.0 / (1 + tg);
         double mW = HistMed(hw, i * HB, HB, 4.0), mS = HistMed(hs, sd * HB, HB, 4.0);
         string op = sn[sd] + " 1:" + I2S(tg), hv = SgnF(q.e1, 3) + " / " + SgnF(q.e2, 3), vd = RRVerd(q);
         if(p == 0)
           {
            string lz = "", lv = RRLev(0, i, lz);
            W("<tr>" + TD(op) + TDc(FP(q.win, 1), PCol(q.win, be, 0.1)) + TD(FP(stp, 1)) + TD(FP(q.tmo, 1)) + TD(FP(be, 1)) +
              TDc(SgnF(q.en, 3), PCol(q.z, 0, 4)) + TD(ZS(q.z)) + TD(SgnF(q.pln, 3)) + TDc(ZS(q.zp), PCol(q.zp, 0, 4)) + TD(hv) + TD(RRCm(q)) +
              "<td title='" + lz + "'>" + lv + "</td>" + TD(F(mW, 2) + " candele (" + DurLab(mW * tfH) + ")") +
              TD(F(mS, 2) + " candele (" + DurLab(mS * tfH) + ")") + TD(FP(q.amb, 1)) + TD(vd) + "</tr>");
            R(g_rrTxS[p], "  " + op + ": obiettivo prima dello stop " + FP(q.win, 1) + "% (senza vantaggio " + FP(be, 1) + "%), stop " +
              FP(stp, 1) + "%, chiusi a tempo " + FP(q.tmo, 1) + "%, aspettativa " + SgnF(q.en, 3) + " R (z " + ZS(q.z) + "; prima / seconda " +
              "meta' " + hv + "), placebo " + SgnF(q.pln, 3) + " R (contro il placebo z " + ZS(q.zp) + "), costo massimo sostenibile " + RRCm(q) +
              ", con costo di " + BpLab() + ": " + lv + " R (" + lz + "), tempo mediano all'obiettivo " + F(mW, 2) + " candele (" +
              DurLab(mW * tfH) + "), allo stop " + F(mS, 2) + " candele, esiti ambigui " + FP(q.amb, 1) + "% -> " + vd);
           }
         else
           {
            W("<tr>" + TD(op) + TDc(FP(q.win, 1), PCol(q.win, be, 0.1)) + TD(FP(be, 1)) + TD(SgnF(q.eg, 3)) + TD(PX(q.cp)) + TD(F(q.cr, 3)) +
              TDc(SgnF(q.en, 3), PCol(q.z, 0, 4)) + TD(ZS(q.z)) + TD(SgnF(q.pln, 3)) + TDc(ZS(q.zp), PCol(q.zp, 0, 4)) + TD(hv) + TD(RRCm(q)) +
              TD(vd) + "</tr>");
            R(g_rrTxS[p], "  " + op + ": obiettivo prima dello stop " + FP(q.win, 1) + "% (senza vantaggio " + FP(be, 1) + "%), aspettativa " +
              "lorda " + SgnF(q.eg, 3) + " R, costo medio " + PX(q.cp) + " = " + F(q.cr, 3) + " R, netta " + SgnF(q.en, 3) + " R (z " + ZS(q.z) +
              "; prima / seconda meta' " + hv + "), placebo netto " + SgnF(q.pln, 3) + " R (contro il placebo z " + ZS(q.zp) + "), costo " +
              "massimo sostenibile " + RRCm(q) + " -> " + vd);
           }
        }
   TEnd();
   //--- contesti con z piu' alto e piu' basso
   int cr[], ci[];
   double cz[];
   int ncand = 0;
   ArrayResize(cr, g_rrNR * 2 * RR_NR);
   ArrayResize(ci, g_rrNR * 2 * RR_NR);
   ArrayResize(cz, g_rrNR * 2 * RR_NR);
   for(int r = 1; r < g_rrNR; r++)
     {
      if(g_rrN[r] < 100)
         continue;
      for(int i = 0; i < 2 * RR_NR; i++)
        {
         RRSt q;
         if(!RRStat(p, r, i, q) || !MathIsValidNumber(q.z))
            continue;
         cr[ncand] = r;
         ci[ncand] = i;
         cz[ncand] = q.z;
         ncand++;
        }
     }
   string en = p == 0 ? "l'aspettativa" : "l'aspettativa netta";
   for(int pass = 0; pass < 2; pass++)
     {
      int want = pass == 0 ? 20 : 10;
      string tt = pass == 0 ? "Contesti con " + en + " pi&ugrave; solida (z pi&ugrave; alto, N &ge; 100)" :
                  "Contesti con " + en + " pi&ugrave; negativa (z pi&ugrave; basso, N &ge; 100)";
      W("<h3>" + tt + "</h3>");
      if(p == 0)
         THead("Contesto|Operazione|N|% obiettivo prima dello stop|Senza vantaggio|Aspettativa (R)|z|" + ZhLab() + "|z contro il placebo|" +
               "Prima / seconda met&agrave; (R)|Costo massimo sostenibile (prezzo e pb)|Lettura");
      else
         THead("Contesto|Operazione|N|% obiettivo prima dello stop|Senza vantaggio|Aspettativa lorda (R)|Costo medio (R)|Aspettativa netta (R)|z|" +
               ZhLab() + "|z contro il placebo|Prima / seconda met&agrave; netta (R)|Costo massimo sostenibile (prezzo e pb)|Lettura");
      R(g_rrTxT[p], "  [" + nm + " " + pn + " - " + tt + "]");
      bool used[];
      ArrayResize(used, ncand);
      ArrayInitialize(used, false);
      for(int w = 0; w < want; w++)
        {
         int b = -1;
         for(int c = 0; c < ncand; c++)
            if(!used[c] && (b < 0 || (pass == 0 ? cz[c] > cz[b] : cz[c] < cz[b])))
               b = c;
         if(b < 0)
            break;
         used[b] = true;
         int r = cr[b], i = ci[b], tg = i % RR_NR + 1;
         RRSt q;
         RRStat(p, r, i, q);
         string lab = g_rrDimN[g_rrDim[r]] + ": " + g_rrLab[r];
         string op = sn[i / RR_NR] + " 1:" + I2S(tg), hv = SgnF(q.e1, 3) + " / " + SgnF(q.e2, 3);
         double be = 1.0 / (1 + tg);
         W("<tr>" + TD(lab) + TD(op) + TD(I2S(q.n)) + TD(FP(q.win, 1)) + TD(FP(be, 1)) + TD(SgnF(q.eg, 3)) +
           (p > 0 ? TD(F(q.cr, 3)) + TDc(SgnF(q.en, 3), PCol(q.z, 0, 4)) : "") + TD(ZS(q.z)) +
           TDc(ZS(q.zh) + (MathIsValidNumber(q.lhn) ? " (" + SgnF(q.lhn, 3) + ")" : ""), PCol(q.zh, 0, 4)) + TDc(ZS(q.zp), PCol(q.zp, 0, 4)) +
           TD(hv) + TD(RRCm(q)) + TD(RRVerd(q)) + "</tr>");
         R(g_rrTxT[p], "    " + lab + " -> " + op + " (N " + I2S(q.n) + "): obiettivo " + FP(q.win, 1) + "% (senza vantaggio " + FP(be, 1) +
           "%), aspettativa " + (p > 0 ? "lorda " + SgnF(q.eg, 3) + " R, costo " + F(q.cr, 3) + " R, netta " : "") + SgnF(q.en, 3) +
           " R, z " + ZS(q.z) + ", rispetto a tutte le candele z " + ZS(q.za) + (MathIsValidNumber(q.zh) && g_rrIntra ? ", rispetto alla stessa ora " +
           SgnF(q.lhn, 3) + " R (z " + ZS(q.zh) + ")" : "") + ", contro il placebo z " + ZS(q.zp) + ", prima / seconda meta' " + hv +
           ", costo massimo " + RRCm(q) + " -> " + RRVerd(q));
        }
      TEnd();
     }
   //--- tutti i contesti (e raccolta per il riepilogo)
   W("<h3>Tutti i contesti</h3><p class='desc'>Ogni cella: % di volte che il prezzo arriva all'obiettivo prima dello stop " +
     "&middot; aspettativa " + (p > 0 ? "netta " : "") + "in R per trade; * = segno diverso in una delle due met&agrave; del campione. " +
     "Colore: blu = aspettativa positiva, rosso = negativa; pi&ugrave; intenso = z pi&ugrave; alto (pieno da |z| = 4). Passa il mouse " +
     "su una cella per: aspettativa lorda" + (p > 0 ? ", costo e netta in R" : " in R") + "; z; z rispetto a tutte le candele (vs tutte); " +
     (g_rrIntra ? "differenza dalla stessa ora e suo z (vs stessa ora); " : "") + "placebo (direzione a caso nello stesso istante) e z " +
     "contro il placebo; prima / seconda met&agrave; del campione; % chiusi a tempo; durata media in candele; costo massimo sostenibile " +
     "(prezzo e punti base).</p>");
   string hh = "Contesto|N";
   for(int sd = 0; sd < 2; sd++)
      for(int tg = 1; tg <= RR_NR; tg++)
         hh += "|" + sn[sd] + " 1:" + I2S(tg);
   THead(hh);
   R(g_rrTxA[p], "");
   R(g_rrTxA[p], "Rischio/rendimento " + nm + " " + pn + " - tutti i contesti (ogni obiettivo: % prima dello stop, aspettativa " +
     (p > 0 ? "netta " : "") + "in R, z; * = segno diverso in una delle due meta' del campione):");
   for(int d = 0; d < RR_NDIM; d++)
     {
      bool any = false;
      for(int r = g_rrDimB[d]; r < g_rrDimB[d] + g_rrDimC[d]; r++)
         if(g_rrN[r] >= 10)
            any = true;
      if(!any)
         continue;
      if(d > 0)
        {
         Grp(g_rrDimN[d], 2 + 2 * RR_NR);
         R(g_rrTxA[p], "  [" + g_rrDimN[d] + "]");
        }
      for(int r = g_rrDimB[d]; r < g_rrDimB[d] + g_rrDimC[d]; r++)
        {
         if(g_rrN[r] < 10)
            continue;
         string row = "<tr>" + TD(g_rrLab[r]) + TD(I2S(g_rrN[r]));
         string tb = "", ts = "";
         for(int i = 0; i < 2 * RR_NR; i++)
           {
            row += RRCellH(p, r, i);
            if(i < RR_NR)
               tb += (i > 0 ? ", " : "") + RRCellT(p, r, i);
            else
               ts += (i > RR_NR ? ", " : "") + RRCellT(p, r, i);
            if(g_rrN[r] < 100)
               continue;
            RRSt q;
            RRStat(p, r, i, q);
            int tg = i % RR_NR + 1;
            string cl = "[" + nm + "] " + (d == 0 ? g_rrLab[r] : g_rrDimN[d] + ": " + g_rrLab[r]) + " (N " + I2S(q.n) + ")";
            string ctl = (MathIsValidNumber(q.zh) && g_rrIntra ? ", rispetto alla stessa ora " + SgnF(q.lhn, 3) + " R (z " + ZS(q.zh) + ")" : "") +
                         ", placebo " + SgnF(q.pln, 3) + " R (contro il placebo z " + ZS(q.zp) + ")";
            if(HiKeep(hm, q.z))
               HiAdd(hm, q.z, "[" + nm + "] " + sn[i / RR_NR] + " 1:" + I2S(tg) + " | " + (d == 0 ? g_rrLab[r] : g_rrDimN[d] + ": " + g_rrLab[r]) +
                     " (N " + I2S(q.n) + "): obiettivo " + FP(q.win, 1) + "% (senza vantaggio " + FP(1.0 / (1 + tg), 1) + "%), " +
                     (p > 0 ? "lorda " + SgnF(q.eg, 3) + " R, costo " + F(q.cr, 3) + " R, netta " : "aspettativa ") + SgnF(q.en, 3) +
                     " R, rispetto a tutte le candele z " + ZS(q.za) + ctl + ", prima / seconda meta' " + SgnF(q.e1, 3) + " / " +
                     SgnF(q.e2, 3) + (q.st ? " (stabile)" : " (non stabile)"));
            if(p > 0)
               continue;
            //--- riepilogo, solo lordo: quello che il contesto aggiunge alla stessa ora (tutte le operazioni) e dove conta la
            //--- direzione (buy contro sell con lo stesso obiettivo: una volta per obiettivo, il sell e' lo stesso confronto rovesciato)
            if(HiKeep(10, q.zh))
               HiAdd(10, q.zh, cl + " " + sn[i / RR_NR] + " 1:" + I2S(tg) + ": aspettativa " + SgnF(q.eg, 3) + " R, " +
                     (g_rrIntra ? "la stessa ora " : "tutte le candele ") + SgnF(q.eg - q.lh, 3) + " R: il contesto " +
                     (q.zh > 0 ? "aggiunge " : "toglie ") + SgnF(q.lh, 3) + " R, prima / seconda meta' " + SgnF(q.e1, 3) + " / " + SgnF(q.e2, 3));
            if(i < RR_NR && HiKeep(11, q.zp))
               HiAdd(11, q.zp, cl + " 1:" + I2S(tg) + ": buy " + SgnF(q.eg, 3) + " R, sell " + SgnF(2 * q.pl - q.eg, 3) + " R, placebo " +
                     SgnF(q.pl, 3) + " R: " + (q.zp > 0 ? "il buy" : "il sell") + " rende di piu' con lo stesso stop e obiettivo");
           }
         W(row + "</tr>");
         R(g_rrTxA[p], "    " + g_rrLab[r] + " (N " + I2S(g_rrN[r]) + "): BUY " + tb + "; SELL " + ts);
        }
     }
   TEnd();
   SecEnd();
  }

//+------------------------------------------------------------------+
//| Dopo i contesti singoli: CSV, coppie di contesti, simulazione una |
//| posizione alla volta (serie di perdite, drawdown) e regole per lo |
//| Strategy Tester                                                   |
//+------------------------------------------------------------------+
#define CB_D0 1   // dimensioni usate nelle coppie: dall'ora (1) all'RSI (18); escluse 'tutte' e l'anno
#define CB_D1 18
#define SQ_SH 200 // rimescolamenti casuali per il drawdown atteso

void RRAlloc(const int L, int &ring[], int &rN[], int &rP[])
  {
   int nx = g_rrNR * 2 * RR_NR;
   ArrayResize(g_rrN, g_rrNR); ArrayResize(g_rrNH, 2 * g_rrNR); ArrayResize(g_rrInvS, g_rrNR);
   ArrayResize(g_rrW, nx); ArrayResize(g_rrT, nx); ArrayResize(g_rrA, nx);
   ArrayResize(g_rrS, nx); ArrayResize(g_rrS2, nx); ArrayResize(g_rrD, nx);
   ArrayResize(g_rrSN, NPRF * nx); ArrayResize(g_rrCP, NPRF * nx); ArrayResize(g_rrSH, 2 * NPRF * nx);
   ArrayInitialize(g_rrN, 0); ArrayInitialize(g_rrNH, 0); ArrayInitialize(g_rrInvS, 0.0);
   ArrayInitialize(g_rrW, 0); ArrayInitialize(g_rrT, 0); ArrayInitialize(g_rrA, 0);
   ArrayInitialize(g_rrS, 0.0); ArrayInitialize(g_rrS2, 0.0); ArrayInitialize(g_rrD, 0.0);
   ArrayInitialize(g_rrSN, 0.0); ArrayInitialize(g_rrCP, 0.0); ArrayInitialize(g_rrSH, 0.0);
   ArrayResize(g_rrHN, g_rrNR * RR_NH); ArrayResize(g_rrHS, g_rrNR * RR_NH * 2 * RR_NR); ArrayResize(g_rrX, g_rrNR * RR_NR);
   ArrayResize(g_rrU, g_rrNR); ArrayResize(g_rrU2, g_rrNR); ArrayResize(g_rrOU, nx);
   ArrayInitialize(g_rrHN, 0); ArrayInitialize(g_rrHS, 0.0); ArrayInitialize(g_rrX, 0.0);
   ArrayInitialize(g_rrU, 0.0); ArrayInitialize(g_rrU2, 0.0); ArrayInitialize(g_rrOU, 0.0);
   g_rrL = L;
   ArrayResize(g_rrGap, g_rrNR * (L + 1));
   ArrayInitialize(g_rrGap, 0);
   ArrayResize(ring, g_rrNR * L);
   ArrayResize(rN, g_rrNR);
   ArrayResize(rP, g_rrNR);
   ArrayInitialize(rN, 0);
   ArrayInitialize(rP, 0);
  }

// costo in prezzo di un trade per il profilo p: entrata alla barra j0 al prezzo O, uscita alla barra jx
double RRCost1(CSeries &s, const int p, const int i, const int j0, const double O, const int jx)
  {
   int sd = i / RR_NR;
   datetime tE = DataToNY7(s.t[j0]), tX = DataToNY7(s.t[jx]);
   long dE = (long)tE / 86400, dX = (long)tX / 86400;
   double sw = dX > dE ? CostNights(dE, dX, g_cp[p].triple) * (g_cp[p].swA[sd] + g_cp[p].swP[sd] * O) : 0;
   return (sd == 0 ? g_cp[p].sp[HourOf(tE)] : g_cp[p].sp[HourOf(tX)]) + g_cp[p].comm + g_cp[p].slip - sw;
  }

// z del broker peggiore (o lordo se non ci sono costi), stabilita' nelle due meta' per tutti, aspettativa netta peggiore
double RRZr(const int r, const int i, bool &st, double &ew)
  {
   bool any = false;
   double zr = Nan();
   st = true;
   ew = Nan();
   for(int p = 1; p < NPRF; p++)
     {
      if(!g_cp[p].on)
         continue;
      RRSt q;
      if(!RRStat(p, r, i, q))
         return Nan();
      if(!any || q.z < zr)
         zr = q.z;
      if(!any || q.en < ew)
         ew = q.en;
      st = st && q.st;
      any = true;
     }
   if(!any)
     {
      RRSt q;
      if(!RRStat(0, r, i, q))
         return Nan();
      zr = q.z;
      ew = q.en;
      st = q.st;
     }
   return zr;
  }

int RRWorst(const int r, const int i)  // profilo con lo z netto piu' basso (0 se non ci sono costi)
  {
   int w = 0;
   double zw = 0;
   for(int p = 1; p < NPRF; p++)
     {
      if(!g_cp[p].on)
         continue;
      RRSt q;
      RRStat(p, r, i, q);
      if(w == 0 || q.z < zw)
        {
         w = p;
         zw = q.z;
        }
     }
   return w;
  }

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

string CN(const double x, const int d)  // numero per il CSV (virgola decimale, vuoto se non definito)
  {
   if(!MathIsValidNumber(x))
      return "";
   string t = DoubleToString(x, d);
   StringReplace(t, ".", ",");
   return t;
  }

//--- CSV: una riga per contesto (o coppia), lato e obiettivo, con lordo e netto di ogni broker
string g_csvP[RR_MAXROW], g_csvD[RR_NDIM];  // etichette senza entita' HTML del timeframe in corso

void RRCsvRow(const string tf, const string kind, const string dA, const string vA, const string dB, const string vB, const int r, const int i)
  {
   if(g_csvH == INVALID_HANDLE)
      return;
   RRSt q;
   if(!RRStat(0, r, i, q))
      return;
   int tg = i % RR_NR + 1;
   string ln = tf + ";" + kind + ";" + dA + ";" + vA + ";" + dB + ";" + vB + ";" + (i < RR_NR ? "Buy" : "Sell") + ";" + I2S(tg) + ";" +
               I2S(q.n) + ";" + CN(RRNeff(r, q.n, q.dm), 0) + ";" + CN(q.win * 100, 2) + ";" + CN(100.0 / (1 + tg), 2) + ";" +
               CN(q.tmo * 100, 2) + ";" + CN(q.dm, 2) + ";" + CN(q.eg, 4) + ";" + CN(q.z, 2) + ";" + CN(q.za, 2) + ";" + CN(q.e1, 4) + ";" +
               CN(q.e2, 4) + ";" + CN(q.cm, g_digits);
   for(int p = 1; p < NPRF; p++)
     {
      if(!g_cp[p].on)
        {
         ln += ";;;;;;";
         continue;
        }
      RRSt b;
      RRStat(p, r, i, b);
      ln += ";" + CN(b.en, 4) + ";" + CN(b.z, 2) + ";" + CN(b.za, 2) + ";" + CN(b.e1, 4) + ";" + CN(b.e2, 4) + ";" + CN(b.cr, 4);
     }
   //--- controlli (in fondo, per non spostare le colonne di prima): stessa ora, placebo, costo di pareggio e livelli di costo
   ln += ";" + CN(q.lh, 4) + ";" + CN(q.zh, 2) + ";" + CN(q.pl, 4) + ";" + CN(q.zp, 2) + ";" + CN(q.cmb, 2);
   for(int j = 0; j < g_bpN; j++)
     {
      double e = 0, z = 0;
      RRNetBp(r, i, g_bpV[j], e, z);
      ln += ";" + CN(e, 4) + ";" + CN(z, 2);
     }
   for(int p = 1; p < NPRF; p++)
     {
      if(!g_cp[p].on)
        {
         ln += ";;";
         continue;
        }
      RRSt b;
      RRStat(p, r, i, b);
      ln += ";" + CN(b.zh, 2) + ";" + CN(b.zp, 2);
     }
   FileWriteString(g_csvH, ln + "\n");
  }

//--- candidati per la simulazione una posizione alla volta
int    g_ckN = 0;
int    g_ckKind[], g_ckDA[], g_ckVA[], g_ckDB[], g_ckVB[], g_ckI[], g_ckNn[];
double g_ckZ[], g_ckE[];
double g_ckZh[], g_ckZp[], g_ckBe[];  // controlli del broker peggiore: z rispetto alla stessa ora, z contro il placebo, pareggio (pb)
bool   g_ckSt[];
string g_ckLab[];

void RRCandAdd(const int kind, const int dA, const int vA, const int dB, const int vB, const int i, const int n, const double z,
               const double e, const bool st, const string lab, const double zh, const double zp, const double be)
  {
   int c = g_ckN++;
   ArrayResize(g_ckKind, g_ckN); ArrayResize(g_ckDA, g_ckN); ArrayResize(g_ckVA, g_ckN); ArrayResize(g_ckDB, g_ckN);
   ArrayResize(g_ckVB, g_ckN); ArrayResize(g_ckI, g_ckN); ArrayResize(g_ckNn, g_ckN); ArrayResize(g_ckZ, g_ckN);
   ArrayResize(g_ckE, g_ckN); ArrayResize(g_ckSt, g_ckN); ArrayResize(g_ckLab, g_ckN);
   ArrayResize(g_ckZh, g_ckN); ArrayResize(g_ckZp, g_ckN); ArrayResize(g_ckBe, g_ckN);
   g_ckZh[c] = zh;
   g_ckZp[c] = zp;
   g_ckBe[c] = be;
   g_ckKind[c] = kind;
   g_ckDA[c] = dA;
   g_ckVA[c] = vA;
   g_ckDB[c] = dB;
   g_ckVB[c] = vB;
   g_ckI[c] = i;
   g_ckNn[c] = n;
   g_ckZ[c] = z;
   g_ckE[c] = e;
   g_ckSt[c] = st;
   g_ckLab[c] = lab;
  }

string RROpLab(const int i) { return (i < RR_NR ? "Buy" : "Sell") + " 1:" + I2S(i % RR_NR + 1); }

// sceglie i migliori per z del broker peggiore tra i contesti stabili (liste parallele: riga, lato/obiettivo, z)
void RRPickTop(const int &cr[], const int &ci[], const double &cz[], const int nc, const int want, int &pick[])
  {
   ArrayResize(pick, 0);
   bool used[];
   ArrayResize(used, nc);
   ArrayInitialize(used, false);
   for(int w = 0; w < want; w++)
     {
      int b = -1;
      for(int c = 0; c < nc; c++)
         if(!used[c] && (b < 0 || cz[c] > cz[b]))
            b = c;
      if(b < 0)
         break;
      used[b] = true;
      int m = ArraySize(pick);
      ArrayResize(pick, m + 1);
      pick[m] = b;
     }
  }

//--- coppie di contesti: stessi trade, due condizioni insieme
void RRCombo(CSeries &s, const int &cs[], CSeries &cd, const int ti, const datetime tMid, const int L)
  {
   string nm = RR_NAME[ti];
   int C[RR_NDIM], pb[RR_NDIM][RR_NDIM];
   ArrayInitialize(pb, 0);
   for(int d = 0; d < RR_NDIM; d++)
      C[d] = g_rrDimC[d];
   int nc = 0;
   for(int a = CB_D0; a <= CB_D1; a++)
      for(int b = a + 1; b <= CB_D1; b++)
        {
         pb[a][b] = nc;
         nc += C[a] * C[b];
        }
   //--- riga 0 = tutte le candele (riferimento), righe 1.. = coppie (confronto con la stessa ora: riferimento dei contesti singoli)
   g_rrPair = true;
   g_rrNR = 1 + nc;
   int ring[], rN[], rP[];
   RRAlloc(L, ring, rN, rP);
   double o[2 * RR_NR], du[2 * RR_NR], cst[NPRF * 2 * RR_NR];
   bool wn[2 * RR_NR], tm[2 * RR_NR], am[2 * RR_NR];
   int da[RR_NDIM], va[RR_NDIM];
   ArrayInitialize(da, 0);
   ArrayInitialize(va, 0);
   ArrayInitialize(cst, 0.0);
   for(int q = 0; q < g_qN && !IsStopped(); q++)
     {
      int k = g_qK[q], j0 = cs[k], fl = g_qF[q];
      double O = s.o[j0], S = g_qS[q], invS = 1.0 / S, u = 1e-4 * O * invS;
      int hf = cd.t[k] < tMid ? 0 : 1, hc = g_qC[q * RR_NDIM + 1], hSl = g_rrIntra && hc < RR_NH ? hc : 0;
      for(int i = 0; i < 2 * RR_NR; i++)
        {
         o[i] = g_qO[q * 2 * RR_NR + i];
         du[i] = g_qD[q * 2 * RR_NR + i];
         wn[i] = (fl & (1 << i)) != 0;
         tm[i] = (fl & (1 << (10 + i))) != 0;
         am[i] = (fl & (1 << (20 + i))) != 0;
        }
      for(int p = 1; p < NPRF; p++)
         if(g_cp[p].on)
            for(int i = 0; i < 2 * RR_NR; i++)
               cst[p * 2 * RR_NR + i] = RRCost1(s, p, i, j0, O, g_qX[q * 2 * RR_NR + i]);
      RRAcc(0, o, wn, tm, am, du, invS, cst, hf, hSl, u);
      RRGap(0, k, ring, rN, rP);
      int m = 0;
      for(int d = CB_D0; d <= CB_D1; d++)
        {
         int c = g_qC[q * RR_NDIM + d];
         if(c == 255)
            continue;
         da[m] = d;
         va[m] = c;
         m++;
        }
      for(int x = 0; x < m; x++)
         for(int y = x + 1; y < m; y++)
           {
            int r = 1 + pb[da[x]][da[y]] + va[x] * C[da[y]] + va[y];
            RRAcc(r, o, wn, tm, am, du, invS, cst, hf, hSl, u);
            RRGap(r, k, ring, rN, rP);
           }
     }
   //--- statistiche: CSV, riepilogo, migliori e peggiori, candidati
   int cr[], ci[], ca[], cb[], cxa[], cxb[];
   double cz[];
   int ncand = 0, ntest = 0;
   int kr[], ki[];
   double kz[];
   int nk = 0;
   bool anyC = false;
   for(int p = 1; p < NPRF; p++)
      if(g_cp[p].on)
         anyC = true;
   g_txCbAll.Add("");
   g_txCbAll.Add("[" + nm + "] coppie con almeno 30 casi: per ogni obiettivo % arrivato prima dello stop, aspettativa lorda in R e z " +
                 "(* = segno diverso nelle due meta')" + (anyC ? "; poi la netta del broker peggiore" : ""));
   for(int a = CB_D0; a <= CB_D1; a++)
      for(int b = a + 1; b <= CB_D1; b++)
         for(int x = 0; x < C[a]; x++)
            for(int y = 0; y < C[b]; y++)
              {
               int r = 1 + pb[a][b] + x * C[b] + y, n = g_rrN[r];
               if(n < 30)
                  continue;
               //--- appendice del rapporto: la coppia con tutte le operazioni
               string tbu = "", tse = "", nbu = "", nse = "";
               for(int i = 0; i < 2 * RR_NR; i++)
                 {
                  string cl = RRCellT(0, r, i), cn = anyC ? RRCellT(RRWorst(r, i), r, i) : "";
                  if(i < RR_NR)
                    {
                     tbu += (i > 0 ? ", " : "") + cl;
                     nbu += (i > 0 ? ", " : "") + cn;
                    }
                  else
                    {
                     tse += (i > RR_NR ? ", " : "") + cl;
                     nse += (i > RR_NR ? ", " : "") + cn;
                    }
                 }
               g_txCbAll.Add("    " + g_csvD[a] + ": " + g_csvP[g_rrDimB[a] + x] + " + " + g_csvD[b] + ": " + g_csvP[g_rrDimB[b] + y] + " (N " +
                             I2S(n) + "): BUY " + tbu + "; SELL " + tse + (anyC ? " | netta peggiore: BUY " + nbu + "; SELL " + nse : ""));
               for(int i = 0; i < 2 * RR_NR; i++)
                 {
                  RRCsvRow(nm, "coppia", g_csvD[a], g_csvP[g_rrDimB[a] + x], g_csvD[b], g_csvP[g_rrDimB[b] + y], r, i);
                  if(n < 100)
                     continue;
                  bool st = false;
                  double ew = 0, z = RRZr(r, i, st, ew);
                  if(!MathIsValidNumber(z))
                     continue;
                  ntest++;
                  if(ncand >= ArraySize(cr))
                    {
                     int ns = ncand + 4096;
                     ArrayResize(cr, ns); ArrayResize(ci, ns); ArrayResize(cz, ns); ArrayResize(ca, ns); ArrayResize(cb, ns);
                     ArrayResize(cxa, ns); ArrayResize(cxb, ns);
                    }
                  cr[ncand] = r;
                  ci[ncand] = i;
                  cz[ncand] = z;
                  ca[ncand] = a;
                  cb[ncand] = b;
                  cxa[ncand] = x;
                  cxb[ncand] = y;
                  ncand++;
                  if(st && z > 0 && RRLiftOk(r, i))  // candidata solo se aggiunge qualcosa alla stessa ora
                    {
                     if(nk >= ArraySize(kr))
                       {
                        ArrayResize(kr, nk + 1024);
                        ArrayResize(ki, nk + 1024);
                        ArrayResize(kz, nk + 1024);
                       }
                     kr[nk] = ncand - 1;
                     ki[nk] = i;
                     kz[nk] = z;
                     nk++;
                    }
                  if(HiKeep(8, z))
                    {
                     int pw = RRWorst(r, i);
                     RRSt w;
                     RRStat(pw, r, i, w);
                     HiAdd(8, z, "[" + nm + "] " + RROpLab(i) + " | " + g_rrDimN[a] + ": " + g_rrLab[g_rrDimB[a] + x] + " + " + g_rrDimN[b] + ": " +
                           g_rrLab[g_rrDimB[b] + y] + " (N " + I2S(n) + "): obiettivo " + FP(w.win, 1) + "% (senza vantaggio " +
                           FP(1.0 / (1 + i % RR_NR + 1), 1) + "%), lorda " + SgnF(w.eg, 3) + " R, " + (pw > 0 ? "netta " + g_cp[pw].name +
                           " " : "") + SgnF(w.en, 3) + " R, rispetto a tutte le candele z " + ZS(w.za) + (g_rrIntra ? ", rispetto alla " +
                           "stessa ora " + SgnF(w.lhn, 3) + " R (z " + ZS(w.zh) + ")" : "") + ", contro il placebo z " + ZS(w.zp) +
                           ", prima / seconda meta' " + SgnF(w.e1, 3) + " / " + SgnF(w.e2, 3) + (st ? " (stabile)" : " (non stabile)"));
                    }
                 }
              }
   //--- tabelle (scheda Coppie di contesti)
   bool anyB = false;
   for(int p = 1; p < NPRF; p++)
      if(g_cp[p].on)
         anyB = true;
   g_buf = true;
   g_bufS = "";
   SecStart("Coppie di contesti " + nm,
            I2S(nc) + " coppie possibili, " + I2S(ntest) + " confronti con almeno 100 casi (coppia x operazione): per puro caso " +
            "ci si aspettano circa " + F(0.0027 * ntest, 0) + " risultati oltre |z| 3 e " + F(0.0428 * ntest, 0) + " tra 2 e 3. " +
            "Ordinati per z " + (anyB ? "del broker peggiore (aspettativa netta)" : "lordo") + ". Il colore segue lo z, * = segno " +
            "diverso in una delle due met&agrave; del campione. " + (g_rrIntra ? "<b>Rispetto alla stessa ora</b>: la coppia contro " +
            "l'aspettativa di tutti i trade delle stesse ore (tra parentesi la differenza in R): vicino a zero = la coppia vale quanto " +
            "l'orario da solo. " : "") + "<b>Contro il placebo</b>: l'operazione contro la stessa con direzione a caso (buy e sell nello " +
            "stesso istante): vicino a zero = conta il movimento, non la direzione. Colonne del broker peggiore.");
   string hh = "Coppia di contesti|Operazione|N|% obiettivo prima dello stop|Senza vantaggio|Lorda (R) / z";
   for(int p = 1; p < NPRF; p++)
      if(g_cp[p].on)
         hh += "|Netta " + g_cp[p].name + " (R) / z";
   hh += "|" + ZhLab() + "|z contro il placebo|Prima / seconda met&agrave; (R)|Lettura";
   R(g_cbTx, "");
   R(g_cbTx, "Coppie di contesti " + nm + ": " + I2S(nc) + " coppie, " + I2S(ntest) + " confronti con N >= 100 (attesi per caso circa " +
     F(0.0027 * ntest, 0) + " oltre |z| 3 e " + F(0.0428 * ntest, 0) + " tra 2 e 3); ordinati per z " + (anyB ? "del broker peggiore" : "lordo"));
   for(int pass = 0; pass < 2; pass++)
     {
      int want = pass == 0 ? 30 : 10;
      string tt = pass == 0 ? "Le pi&ugrave; solide" : "Le pi&ugrave; negative";
      W("<h3>" + tt + "</h3>");
      THead(hh);
      R(g_cbTx, "  [" + nm + " - " + tt + "]");
      bool used[];
      ArrayResize(used, ncand);
      ArrayInitialize(used, false);
      for(int w = 0; w < want; w++)
        {
         int b = -1;
         for(int c = 0; c < ncand; c++)
            if(!used[c] && (b < 0 || (pass == 0 ? cz[c] > cz[b] : cz[c] < cz[b])))
               b = c;
         if(b < 0)
            break;
         used[b] = true;
         int r = cr[b], i = ci[b], tg = i % RR_NR + 1;
         string lab = g_rrDimN[ca[b]] + ": " + g_rrLab[g_rrDimB[ca[b]] + cxa[b]] + " + " + g_rrDimN[cb[b]] + ": " + g_rrLab[g_rrDimB[cb[b]] + cxb[b]];
         RRSt q;
         RRStat(0, r, i, q);
         int pw = RRWorst(r, i);
         RRSt w0;
         RRStat(pw, r, i, w0);
         string row = "<tr>" + TD(lab) + TD(RROpLab(i)) + TD(I2S(q.n)) + TD(FP(q.win, 1)) + TD(FP(1.0 / (1 + tg), 1)) +
                      TDc(SgnF(q.eg, 3) + " / " + ZS(q.z), PCol(q.z, 0, 4));
         string tx = "    " + lab + " -> " + RROpLab(i) + " (N " + I2S(q.n) + "): obiettivo " + FP(q.win, 1) + "% (senza vantaggio " +
                     FP(1.0 / (1 + tg), 1) + "%), lorda " + SgnF(q.eg, 3) + " R (z " + ZS(q.z) + ")";
         for(int p = 1; p < NPRF; p++)
           {
            if(!g_cp[p].on)
               continue;
            RRSt b2;
            RRStat(p, r, i, b2);
            row += TDc(SgnF(b2.en, 3) + (b2.st ? "" : "*") + " / " + ZS(b2.z), PCol(b2.z, 0, 4));
            tx += ", netta " + g_cp[p].name + " " + SgnF(b2.en, 3) + " R (z " + ZS(b2.z) + (b2.st ? "" : ", non stabile") + ")";
           }
         row += TDc(ZS(w0.zh) + (MathIsValidNumber(w0.lhn) ? " (" + SgnF(w0.lhn, 3) + ")" : ""), PCol(w0.zh, 0, 4)) +
                TDc(ZS(w0.zp), PCol(w0.zp, 0, 4)) + TD(SgnF(w0.e1, 3) + " / " + SgnF(w0.e2, 3)) + TD(RRVerd(w0)) + "</tr>";
         tx += ", rispetto a tutte le candele z " + ZS(w0.za) + (g_rrIntra ? ", rispetto alla stessa ora " + SgnF(w0.lhn, 3) + " R (z " +
               ZS(w0.zh) + ")" : "") + ", contro il placebo z " + ZS(w0.zp) + ", prima / seconda meta' " + SgnF(w0.e1, 3) + " / " +
               SgnF(w0.e2, 3) + " -> " + RRVerd(w0);
         W(row);
         R(g_cbTx, tx);
        }
      TEnd();
     }
   SecEnd();
   g_buf = false;
   g_cbHtml += g_bufS;
   g_bufS = "";
   //--- candidati: le coppie migliori stabili nelle due meta'
   int pick[];
   RRPickTop(kr, ki, kz, nk, InpSeqTop, pick);
   for(int j = 0; j < ArraySize(pick); j++)
     {
      int c = kr[pick[j]], r = cr[c], i = ci[c];
      bool st = false;
      double ew = 0, z = RRZr(r, i, st, ew);
      RRSt w;
      RRStat(RRWorst(r, i), r, i, w);
      RRCandAdd(2, ca[c], cxa[c], cb[c], cxb[c], i, g_rrN[r], z, ew, st, g_rrDimN[ca[c]] + ": " + g_rrLab[g_rrDimB[ca[c]] + cxa[c]] + " + " +
                g_rrDimN[cb[c]] + ": " + g_rrLab[g_rrDimB[cb[c]] + cxb[c]], w.zh, w.zp, w.cmb);
     }
  }

//--- simulazione una posizione alla volta di un candidato con i costi del profilo p
struct SqR
  {
   int               n, nY, posY, ls;
   double            yrs, win, e, tot, pf, dd, ddDays, lsMed, ls95, ddMed, dd95;
   double            be, cb;  // costo di pareggio dei trade eseguiti (punti base, dal lordo) e costo medio del profilo (punti base)
  };

double MaxDD(const double &x[], const int n)
  {
   double eq = 0, pk = 0, dd = 0;
   for(int j = 0; j < n; j++)
     {
      eq += x[j];
      if(eq > pk)
         pk = eq;
      else
         if(pk - eq > dd)
            dd = pk - eq;
     }
   return dd;
  }

bool RRSeq(CSeries &s, const int &cs[], CSeries &cd, const int p, const int c, SqR &r, string &svg)
  {
   int dA = g_ckDA[c], vA = g_ckVA[c], dB = g_ckDB[c], vB = g_ckVB[c], i = g_ckI[c];
   double out[];
   datetime tt[];
   ArrayResize(out, g_qN);
   ArrayResize(tt, g_qN);
   int n = 0, wins = 0, lastX = -1;
   double sg = 0, su = 0, sc = 0;
   for(int q = 0; q < g_qN; q++)
     {
      if(g_qC[q * RR_NDIM + dA] != vA || (dB >= 0 && g_qC[q * RR_NDIM + dB] != vB))
         continue;
      int k = g_qK[q], j0 = cs[k];
      if(j0 <= lastX)
         continue;  // la posizione precedente e' ancora aperta
      int jx = g_qX[q * 2 * RR_NR + i];
      double v = g_qO[q * 2 * RR_NR + i];
      sg += v;
      su += 1e-4 * s.o[j0] / g_qS[q];
      if(p > 0)
        {
         double cp = RRCost1(s, p, i, j0, s.o[j0], jx);
         v -= cp / g_qS[q];
         sc += cp / (1e-4 * s.o[j0]);
        }
      out[n] = v;
      tt[n] = cd.t[k];
      if((g_qF[q] & (1 << i)) != 0)
         wins++;
      lastX = jx;
      n++;
     }
   r.n = n;
   r.be = su > 0 ? sg / su : Nan();
   r.cb = p > 0 && n > 0 ? sc / n : Nan();
   svg = "";
   if(n < 10)
      return false;
   double tot = 0, gp = 0, gl = 0, eq = 0, pk = 0, dd = 0, ddd = 0, mn = 0, mx = 0;
   datetime tPk = tt[0];
   int ls = 0, cur = 0, nl = 0;
   MqlDateTime md;
   TimeToStruct(tt[0], md);
   int y0 = md.year;
   TimeToStruct(tt[n - 1], md);
   int ny = md.year - y0 + 1;
   double ys[];
   int yc[];
   ArrayResize(ys, ny);
   ArrayResize(yc, ny);
   ArrayInitialize(ys, 0.0);
   ArrayInitialize(yc, 0);
   for(int j = 0; j < n; j++)
     {
      double v = out[j];
      tot += v;
      if(v > 0)
         gp += v;
      else
         gl -= v;
      if(v < 0)
        {
         nl++;
         cur++;
         if(cur > ls)
            ls = cur;
        }
      else
         cur = 0;
      eq += v;
      if(eq > pk)
        {
         pk = eq;
         tPk = tt[j];
        }
      else
        {
         if(pk - eq > dd)
            dd = pk - eq;
         double dy = ((double)tt[j] - (double)tPk) / 86400.0;
         if(dy > ddd)
            ddd = dy;
        }
      if(eq < mn)
         mn = eq;
      if(eq > mx)
         mx = eq;
      TimeToStruct(tt[j], md);
      int y = md.year - y0;
      if(y >= 0 && y < ny)
        {
         ys[y] += v;
         yc[y]++;
        }
     }
   r.win = (double)wins / n;
   r.e = tot / n;
   r.tot = tot;
   r.pf = gl > 0 ? gp / gl : Nan();
   r.dd = dd;
   r.ddDays = ddd;
   r.ls = ls;
   r.yrs = MathMax(((double)tt[n - 1] - (double)tt[0]) / (365.25 * 86400.0), 1.0 / 12);
   r.nY = 0;
   r.posY = 0;
   for(int y = 0; y < ny; y++)
      if(yc[y] > 0)
        {
         r.nY++;
         if(ys[y] > 0)
            r.posY++;
        }
   //--- serie di perdite attesa se l'ordine dei trade fosse casuale: P(serie massima < k) = exp(-n p q^k)
   double qL = (double)nl / n, pW = 1 - qL;
   r.lsMed = Nan();
   r.ls95 = Nan();
   if(qL > 0 && qL < 1)
     {
      r.lsMed = MathLog(MathLog(2.0) / (n * pW)) / MathLog(qL);
      r.ls95 = MathLog(-MathLog(0.95) / (n * pW)) / MathLog(qL);
     }
   //--- drawdown atteso rimescolando l'ordine dei trade: oltre il 95% = perdite raggruppate nel tempo (fasi)
   double tmp[], dds[];
   ArrayResize(tmp, n);
   ArrayResize(dds, SQ_SH);
   ArrayCopy(tmp, out, 0, 0, n);
   MathSrand(12345);
   for(int h = 0; h < SQ_SH; h++)
     {
      for(int j = n - 1; j > 0; j--)
        {
         int x = (int)(((long)MathRand() * 32768 + MathRand()) % (j + 1));
         double t = tmp[j];
         tmp[j] = tmp[x];
         tmp[x] = t;
        }
      dds[h] = MaxDD(tmp, n);
     }
   ArraySort(dds);
   r.ddMed = dds[SQ_SH / 2];
   r.dd95 = dds[(int)(0.95 * (SQ_SH - 1))];
   //--- curva dei R cumulati (fino a 160 punti)
   int np = n < 160 ? n : 160;
   double lo = MathMin(0.0, mn), hi = MathMax(0.0, mx), sp = hi - lo > 0 ? hi - lo : 1;
   string pts = "";
   double e2 = 0;
   int jj = 0;
   for(int u = 0; u < np; u++)
     {
      int j = np > 1 ? (int)MathRound((double)(n - 1) * u / (np - 1)) : 0;
      for(; jj <= j; jj++)
         e2 += out[jj];
      pts += (u > 0 ? " " : "") + DoubleToString(200.0 * u / MathMax(1, np - 1), 1) + "," + DoubleToString(38 - 36 * (e2 - lo) / sp, 1);
     }
   double y0l = 38 - 36 * (0 - lo) / sp;
   svg = "<svg class='svg' width='200' height='40' viewBox='0 0 200 40'><line x1='0' y1='" + DoubleToString(y0l, 1) + "' x2='200' y2='" +
         DoubleToString(y0l, 1) + "' stroke='#374151'/><polyline fill='none' stroke='" + (tot > 0 ? C_BLUE : C_RED) +
         "' stroke-width='1.3' points='" + pts + "'/></svg>";
   return true;
  }

//--- regole per lo Strategy Tester (EA MPRuleTester)
void RRRuleWrite(const int id, const int ti, const int c, const double p20, const double p80, const int L, const double seqE, const int seqN)
  {
   if(g_ruH == INVALID_HANDLE)
      return;
   string ln = I2S(id) + ";" + I2S(RR_MIN[ti]) + ";" + I2S(g_ckI[c] / RR_NR) + ";" + I2S(g_ckI[c] % RR_NR + 1) + ";" + I2S((int)InpRRStop) + ";" +
               DoubleToString(InpRRStopK, 4) + ";" + I2S(L) + ";" + I2S(g_ckDA[c]) + ";" + I2S(g_ckVA[c]) + ";" + I2S(g_ckDB[c]) + ";" +
               I2S(g_ckVB[c]) + ";" + DoubleToString(p20, 8) + ";" + DoubleToString(p80, 8) + ";" +
               Plain(RR_NAME[ti] + " " + RROpLab(g_ckI[c]) + " | " + g_ckLab[c]) + ";" + I2S(g_ckNn[c]) + ";" + DoubleToString(g_ckE[c], 4) + ";" +
               DoubleToString(g_ckZ[c], 2) + ";" + I2S(seqN) + ";" + DoubleToString(seqE, 4);
   FileWriteString(g_ruH, ln + "\n");
  }

void RRSeqTf(CSeries &s, const int &cs[], CSeries &cd, const int ti, const double p20, const double p80, const int L)
  {
   if(g_ckN == 0)
      return;
   string nm = RR_NAME[ti];
   string kn[3] = {"riferimento", "contesto singolo", "coppia di contesti"};
   bool anyB = false;
   for(int p = 1; p < NPRF; p++)
      if(g_cp[p].on)
         anyB = true;
   g_buf = true;
   g_bufS = "";
   SecStart("Strategie " + nm + ": una posizione alla volta",
            "Ogni riga &egrave; una regola eseguita come farebbe un EA: si entra all'apertura della candela quando il contesto " +
            "&egrave; vero, ma solo se non c'&egrave; gi&agrave; una posizione aperta della stessa regola. Per ogni candidato: prima " +
            "senza costi, poi con i costi di ogni broker. Nel titolo di ogni candidato i controlli del broker peggiore: z rispetto " +
            (g_rrIntra ? "alla stessa ora" : "a tutte le candele") + ", z contro il placebo (direzione a caso nello stesso istante) e " +
            "costo di pareggio. Colonna 'pb': sulla riga lorda il costo per trade (punti base del prezzo) che azzera i trade eseguiti " +
            "una alla volta, sulle righe dei broker il loro costo medio per trade: se il costo supera il pareggio la regola perde.");
   THead("Costi|Trade|Trade all'anno|% obiettivo|Aspettativa (R)|R totali|R all'anno|Profit factor|Anni positivi|Serie di perdite massima (attesa: mediana / 95%)|Drawdown massimo in R (ordine casuale: mediana / 95%)|Drawdown pi&ugrave; lungo|Pareggio / costo (pb)|Curva dei R cumulati");
   R(g_sqTx, "");
   R(g_sqTx, "Strategie " + nm + " - una posizione alla volta (serie di perdite attesa e drawdown atteso = stessi trade in ordine casuale):");
   for(int c = 0; c < g_ckN && !IsStopped(); c++)
     {
      string lab = RROpLab(g_ckI[c]) + " | " + g_ckLab[c];
      SqR rs[NPRF];
      string svg[NPRF];
      bool ok[NPRF];
      double seqMin = Nan();
      int seqN = 0;
      for(int p = 0; p < NPRF; p++)
        {
         ok[p] = false;
         svg[p] = "";
         if(p > 0 && !g_cp[p].on)
            continue;
         ok[p] = RRSeq(s, cs, cd, p, c, rs[p], svg[p]);
         bool rob = anyB ? p > 0 : p == 0;
         if(ok[p] && rob && (!MathIsValidNumber(seqMin) || rs[p].e < seqMin))
           {
            seqMin = rs[p].e;
            seqN = rs[p].n;
           }
        }
      //--- regola esportata: z del broker peggiore sopra la soglia, stabile nelle due meta', positiva anche una posizione alla volta;
      //--- il riferimento 'entra sempre' e' esportato sempre, come termine di paragone nel tester
      int id = 0;
      if(g_ckKind[c] == 0 || (MathIsValidNumber(g_ckZ[c]) && g_ckZ[c] >= InpRuleMinZ && g_ckSt[c] && MathIsValidNumber(seqMin) && seqMin > 0))
        {
         id = ++g_ruN;
         if(g_ckKind[c] > 0)
            g_ruReal++;
         RRRuleWrite(id, ti, c, p20, p80, L, seqMin, seqN);
         g_ruHtml += "<tr>" + TD(I2S(id)) + TD(nm) + TD(RROpLab(g_ckI[c])) + TD(g_ckLab[c]) + TD(I2S(g_ckNn[c])) + TD(SgnF(g_ckE[c], 3)) +
                     TD(ZS(g_ckZ[c])) + TD((MathIsValidNumber(g_ckZh[c]) ? (g_rrIntra ? "stessa ora " : "tutte le candele ") +
                                            ZS(g_ckZh[c]) + "; " : "") + "placebo " + ZS(g_ckZp[c])) + TD(BpTxt(g_ckBe[c])) +
                     TD(I2S(seqN)) + TD(SgnF(seqMin, 3)) + "</tr>";
         R(g_ruTx, "  Regola " + I2S(id) + ": " + nm + " " + lab + " (analisi: N " + I2S(g_ckNn[c]) + ", netta peggiore " + SgnF(g_ckE[c], 3) +
           " R, z " + ZS(g_ckZ[c]) + (MathIsValidNumber(g_ckZh[c]) ? ", rispetto " + (g_rrIntra ? "alla stessa ora" : "a tutte le candele") +
           " z " + ZS(g_ckZh[c]) : "") + ", contro il placebo z " + ZS(g_ckZp[c]) + ", costo di pareggio " + BpTxt(g_ckBe[c]) +
           "; una posizione alla volta: " + I2S(seqN) + " trade, " + SgnF(seqMin, 3) + " R per trade)");
        }
      EdgeAddRR(nm, c, id, rs, ok);
      string ctl = (MathIsValidNumber(g_ckZh[c]) ? ", rispetto " + (g_rrIntra ? "alla stessa ora" : "a tutte le candele") + " z " +
                    ZS(g_ckZh[c]) : "") + ", contro il placebo z " + ZS(g_ckZp[c]) + ", pareggio " + BpTxt(g_ckBe[c]);
      Grp(lab + " &mdash; " + kn[g_ckKind[c]] + " (analisi: N " + I2S(g_ckNn[c]) + ", aspettativa netta peggiore " + SgnF(g_ckE[c], 3) +
          " R, z " + ZS(g_ckZ[c]) + (g_ckSt[c] ? ", stabile" : ", non stabile") + ctl + ")" + (id > 0 ? " &rarr; <b>regola " + I2S(id) + "</b>" : ""), 14);
      R(g_sqTx, "  " + lab + " [" + kn[g_ckKind[c]] + "; analisi: N " + I2S(g_ckNn[c]) + ", netta peggiore " + SgnF(g_ckE[c], 3) + " R, z " +
        ZS(g_ckZ[c]) + (g_ckSt[c] ? ", stabile" : ", non stabile") + ctl + "]" + (id > 0 ? " -> REGOLA " + I2S(id) : ""));
      for(int p = 0; p < NPRF; p++)
        {
         if(p > 0 && !g_cp[p].on)
            continue;
         string pn = p == 0 ? "lordo" : g_cp[p].name;
         if(!ok[p])
           {
            W("<tr>" + TD(pn) + TD(I2S(rs[p].n)) + "<td colspan='12' class='muted'>meno di 10 trade</td></tr>");
            R(g_sqTx, "    " + pn + ": meno di 10 trade");
            continue;
           }
         SqR q = rs[p];
         double tpy = q.n / q.yrs, rpy = q.tot / q.yrs;
         string lsT = I2S(q.ls) + " (" + F(q.lsMed, 0) + " / " + F(q.ls95, 0) + ")";
         string ddT = F(q.dd, 1) + " (" + F(q.ddMed, 1) + " / " + F(q.dd95, 1) + ")";
         W("<tr>" + TD(pn) + TD(I2S(q.n)) + TD(F(tpy, 0)) + TD(FP(q.win, 1)) + TDc(SgnF(q.e, 3), PCol(q.e, 0, 0.2)) + TD(SgnF(q.tot, 1)) +
           TD(SgnF(rpy, 1)) + TD(F(q.pf, 2)) + TD(I2S(q.posY) + " su " + I2S(q.nY)) +
           TDc(lsT, MathIsValidNumber(q.ls95) && q.ls > q.ls95 ? "rgba(239,68,68,0.35)" : "") +
           TDc(ddT, q.dd > q.dd95 ? "rgba(239,68,68,0.35)" : "") + TD(F(q.ddDays, 0) + " giorni") +
           TD(p == 0 ? "pareggio " + BpTxt(q.be) : "costo " + F(q.cb, 2) + " pb") + TD(svg[p]) + "</tr>");
         R(g_sqTx, "    " + pn + ": " + I2S(q.n) + " trade (" + F(tpy, 0) + " all'anno), obiettivo " + FP(q.win, 1) + "%, " + SgnF(q.e, 3) +
           " R per trade, totale " + SgnF(q.tot, 1) + " R (" + SgnF(rpy, 1) + " R all'anno), profit factor " + F(q.pf, 2) + ", anni positivi " +
           I2S(q.posY) + " su " + I2S(q.nY) + ", serie di perdite massima " + I2S(q.ls) + " (attesa " + F(q.lsMed, 0) + ", 95% " + F(q.ls95, 0) +
           "), drawdown massimo " + F(q.dd, 1) + " R (ordine casuale " + F(q.ddMed, 1) + ", 95% " + F(q.dd95, 1) + "), drawdown piu' lungo " +
           F(q.ddDays, 0) + " giorni, " + (p == 0 ? "costo di pareggio " + BpTxt(q.be) : "costo medio " + F(q.cb, 2) + " pb"));
        }
     }
   TEnd();
   SecEnd();
   g_buf = false;
   g_sqHtml += g_bufS;
   g_bufS = "";
  }

void RRPost(CSeries &s, const int &cs[], CSeries &cd, const int ti, const datetime tMid, const double p20, const double p80, const int L)
  {
   string nm = RR_NAME[ti];
   //--- etichette senza entita' HTML per il CSV
   for(int d = 0; d < RR_NDIM; d++)
      g_csvD[d] = Plain(g_rrDimN[d]);
   for(int r = 0; r < g_rrNR && r < RR_MAXROW; r++)
      g_csvP[r] = Plain(g_rrLab[r]);
   //--- contesti singoli: CSV e candidati (prima di riusare gli accumulatori per le coppie)
   g_ckN = 0;
   int bi = -1;
   double bz = 0;
   for(int i = 0; i < 2 * RR_NR; i++)
     {
      bool st = false;
      double ew = 0, z = RRZr(0, i, st, ew);
      if(MathIsValidNumber(z) && (bi < 0 || z > bz))
        {
         bi = i;
         bz = z;
        }
     }
   if(bi >= 0)
     {
      bool st = false;
      double ew = 0, z = RRZr(0, bi, st, ew);
      RRSt w;
      RRStat(RRWorst(0, bi), 0, bi, w);
      RRCandAdd(0, 0, 0, -1, -1, bi, g_rrN[0], z, ew, st, "Tutte le candele (entra sempre)", w.zh, w.zp, w.cmb);
     }
   int kr[], ki[];
   double kz[];
   int nk = 0;
   for(int d = 0; d < RR_NDIM; d++)
      for(int r = g_rrDimB[d]; r < g_rrDimB[d] + g_rrDimC[d]; r++)
        {
         if(g_rrN[r] < 30)
            continue;
         for(int i = 0; i < 2 * RR_NR; i++)
           {
            RRCsvRow(nm, "singolo", g_csvD[d], g_csvP[r], "", "", r, i);
            if(d < CB_D0 || d > CB_D1 || g_rrN[r] < 100)
               continue;
            bool st = false;
            double ew = 0, z = RRZr(r, i, st, ew);
            if(!st || !MathIsValidNumber(z) || z <= 0 || !RRLiftOk(r, i))  // candidato solo se aggiunge qualcosa alla stessa ora
               continue;
            ArrayResize(kr, nk + 1);
            ArrayResize(ki, nk + 1);
            ArrayResize(kz, nk + 1);
            kr[nk] = r;
            ki[nk] = i;
            kz[nk] = z;
            nk++;
           }
        }
   int pick[];
   RRPickTop(kr, ki, kz, nk, InpSeqTop, pick);
   for(int j = 0; j < ArraySize(pick); j++)
     {
      int r = kr[pick[j]], i = ki[pick[j]], d = g_rrDim[r];
      bool st = false;
      double ew = 0, z = RRZr(r, i, st, ew);
      RRSt w;
      RRStat(RRWorst(r, i), r, i, w);
      RRCandAdd(1, d, r - g_rrDimB[d], -1, -1, i, g_rrN[r], z, ew, st, g_rrDimN[d] + ": " + g_rrLab[r], w.zh, w.zp, w.cmb);
     }
   //--- coppie di contesti
   if(InpRRCombo && RR_MIN[ti] >= InpComboMinTF)
     {
      Comment("MarketProfiler: coppie di contesti ", nm, " ...");
      RRCombo(s, cs, cd, ti, tMid, L);
     }
   else
      R(g_cbTx, "Coppie di contesti " + nm + ": non calcolate (timeframe sotto il minimo impostato o coppie disattivate)");
   //--- una posizione alla volta
   Comment("MarketProfiler: strategie ", nm, " ...");
   RRSeqTf(s, cs, cd, ti, p20, p80, L);
  }

void RRTf(CSeries &s, const int barSec, const int ti)
  {
   int tfSec = RR_MIN[ti] * 60;
   bool intra = tfSec < 86400;
   int L = InpRRMaxBars < 1 ? 1 : InpRRMaxBars;
   //--- candele del timeframe costruite dalle barre di s (allineate alla mezzanotte dell'orologio dei dati)
   int nc = 0;
   long cur = LONG_MIN;
   for(int i = 0; i < s.n; i++)
     {
      long key = (long)s.t[i] / tfSec;
      if(key != cur)
        {
         nc++;
         cur = key;
        }
     }
   CSeries cd;
   int cs[], ce[];
   ArrayResize(cd.t, nc); ArrayResize(cd.o, nc); ArrayResize(cd.h, nc); ArrayResize(cd.l, nc); ArrayResize(cd.c, nc); ArrayResize(cd.v, nc);
   ArrayResize(cs, nc); ArrayResize(ce, nc);
   int x = -1;
   cur = LONG_MIN;
   for(int i = 0; i < s.n; i++)
     {
      long key = (long)s.t[i] / tfSec;
      if(key != cur)
        {
         x++;
         cur = key;
         cs[x] = i;
         cd.t[x] = s.t[i];
         cd.o[x] = s.o[i];
         cd.h[x] = s.h[i];
         cd.l[x] = s.l[i];
         cd.v[x] = 0;
        }
      if(s.h[i] > cd.h[x])
         cd.h[x] = s.h[i];
      if(s.l[i] < cd.l[x])
         cd.l[x] = s.l[i];
      cd.c[x] = s.c[i];
      cd.v[x] += s.v[i];
      ce[x] = i + 1;
     }
   nc--;  // l'ultima candela e' ancora in corso
   cd.n = nc;
   cd.hasVol = s.hasVol;
   if(nc < 200 + L)
      return;
   //--- indicatori sulle candele (all'entrata si usano solo candele chiuse: indice k - 1)
   double cnt[];
   ArrayResize(cnt, nc);
   for(int k = 0; k < nc; k++)
      cnt[k] = ce[k] - cs[k];
   double medCnt = MedianOf(cnt, nc);
   double atr[], rv[], e20[], e50[], rsi[], ret[], ps[];
   int dir[], stk[];
   CalcATR(cd, 14, atr);
   CalcRVOL(cd, tfSec, 20, rv);
   ArrayResize(e20, nc); ArrayResize(e50, nc); ArrayResize(rsi, nc); ArrayResize(ret, nc); ArrayResize(ps, nc + 1);
   ArrayResize(dir, nc); ArrayResize(stk, nc);
   double a20 = 2.0 / 21.0, a50 = 2.0 / 51.0, ag = 0, al = 0;
   ps[0] = 0;
   for(int k = 0; k < nc; k++)
     {
      e20[k] = k == 0 ? cd.c[0] : a20 * cd.c[k] + (1 - a20) * e20[k - 1];
      e50[k] = k == 0 ? cd.c[0] : a50 * cd.c[k] + (1 - a50) * e50[k - 1];
      ret[k] = cd.o[k] > 0 ? cd.c[k] / cd.o[k] - 1 : 0;
      double tr = k == 0 ? cd.h[k] - cd.l[k] : MathMax(cd.h[k], cd.c[k - 1]) - MathMin(cd.l[k], cd.c[k - 1]);
      ps[k + 1] = ps[k] + tr;
      dir[k] = cd.c[k] > cd.o[k] ? 1 : (cd.c[k] < cd.o[k] ? -1 : 0);
      stk[k] = dir[k] == 0 ? 0 : ((k > 0 && dir[k - 1] == dir[k]) ? stk[k - 1] + 1 : 1);
      rsi[k] = Nan();
      if(k > 0)
        {
         double ch = cd.c[k] - cd.c[k - 1], g = ch > 0 ? ch : 0, lo = ch < 0 ? -ch : 0;
         if(k <= 14)
           {
            ag += g / 14.0;
            al += lo / 14.0;
           }
         else
           {
            ag = (ag * 13 + g) / 14.0;
            al = (al * 13 + lo) / 14.0;
           }
         if(k >= 14)
            rsi[k] = al > 0 ? 100 - 100 / (1 + ag / al) : 100;
        }
     }
   double srt[];
   Sorted(ret, nc, srt);
   double p20 = Pct(srt, nc, 20), p80 = Pct(srt, nc, 80);
   //--- righe di contesto
   g_rrNR = 0;
   string hl = "";
   for(int h = 0; h < 24; h++)
      hl += (h > 0 ? "|" : "") + HourLab(h);
   MqlDateTime md;
   TimeToStruct(cd.t[0], md);
   int y0 = md.year;
   TimeToStruct(cd.t[nc - 1], md);
   int y1 = md.year;
   string yl = "";
   for(int y = y0; y <= y1; y++)
      yl += (y > y0 ? "|" : "") + I2S(y);
   RRDim(0, "Tutte le candele", "Tutte le candele");
   RRDim(1, "Ora di apertura della candela", hl);
   RRDim(2, "Giorno della settimana", "Lun|Mar|Mer|Gio|Ven|Sab|Dom");
   RRDim(3, "Candela precedente (forte = il 20% pi&ugrave; forte)", "forte rialzo|rialzo|ribasso|forte ribasso");
   RRDim(4, "Ampiezza della candela precedente rispetto all'ATR(14)", "stretta (sotto 0.75 ATR)|normale|ampia (oltre 1.33 ATR)");
   RRDim(5, "Chiusura della candela precedente nel suo range", "nel terzo basso|nel terzo centrale|nel terzo alto");
   RRDim(6, "Candele di fila", "3 o pi&ugrave; rialziste di fila|2 rialziste di fila|3 o pi&ugrave; ribassiste di fila|2 ribassiste di fila|ultima diversa dalla penultima");
   RRDim(7, "Volatilit&agrave; (ATR14 / ATR100)", "compressione (sotto 0.8)|normale (0.8-1.2)|espansione (sopra 1.2)");
   RRDim(8, "Volume relativo della candela precedente (RVOL, stessa ora ultimi 20 giorni)", "RVOL sotto 0.8|RVOL 0.8-1.5|RVOL oltre 1.5");
   RRDim(9, "Apertura rispetto al giorno precedente", "sopra il massimo di ieri|dentro il range di ieri|sotto il minimo di ieri");
   RRDim(10, "Vicinanza ai livelli di ieri (aperture dentro il range)", "entro 1 stop sotto il massimo di ieri|entro 1 stop sopra il minimo di ieri|lontano da entrambi");
   RRDim(11, "Apertura rispetto alla settimana precedente", "sopra il massimo della settimana scorsa|dentro il range della settimana scorsa|sotto il minimo della settimana scorsa");
   RRDim(12, "Rispetto all'apertura del giorno", "sopra l'apertura del giorno|sotto l'apertura del giorno|prima candela del giorno");
   RRDim(13, "Rispetto al VWAP del giorno", "sopra il VWAP|sotto il VWAP");
   RRDim(14, "Posizione nel range del giorno finora", "nel terzo basso|nel terzo centrale|nel terzo alto");
   RRDim(15, "Range del giorno finora rispetto al range giornaliero mediano", "meno di met&agrave;|da met&agrave; a 1 volta|oltre 1 volta");
   RRDim(16, "Trend: prezzo rispetto alla EMA50", "sopra la EMA50|sotto la EMA50");
   RRDim(17, "EMA20 rispetto alla EMA50", "EMA20 sopra la EMA50|EMA20 sotto la EMA50");
   RRDim(18, "RSI(14)", "sotto 30|30-50|50-70|oltre 70");
   RRDim(19, "Anno", yl);
   g_rrBOk = false;
   g_rrPair = false;
   g_rrIntra = intra;
   int ring[], rN[], rP[];
   RRAlloc(L, ring, rN, rP);
   //--- ogni trade simulato resta in memoria per coppie di contesti, simulazione una posizione alla volta e regole
   g_qN = 0;
   ArrayResize(g_qK, nc);
   ArrayResize(g_qF, nc);
   ArrayResize(g_qS, nc);
   ArrayResize(g_qO, nc * 2 * RR_NR);
   ArrayResize(g_qD, nc * 2 * RR_NR);
   ArrayResize(g_qX, nc * 2 * RR_NR);
   ArrayResize(g_qC, nc * RR_NDIM);
   int HB = 4 * L + 8;
   int hw[], hs[];
   ArrayResize(hw, 2 * RR_NR * HB);
   ArrayResize(hs, 2 * HB);
   ArrayInitialize(hw, 0);
   ArrayInitialize(hs, 0);
   double sv[];
   ArrayResize(sv, nc);
   int nS = 0;
   //--- le due meta' del campione (per tempo): un vantaggio vero dovrebbe esserci in entrambe
   datetime tA = cd.t[20], tB = cd.t[nc - L], tMid = (datetime)((long)tA + ((long)tB - (long)tA) / 2);
   //--- periodi giorno e settimana (schede Livelli e Direzione) e statistiche del giorno fino all'entrata
   int di = 0, wi = 0, jp = 0, cachedDi = -1;
   int cls[RR_NDIM];
   long dKey = -1, yDay = -1;
   int yCur = y0;
   double dO = 0, dH = 0, dL = 0, cpv = 0, cvv = 0, medDay = Nan();
   double o[2 * RR_NR], du[2 * RR_NR], cst[NPRF * 2 * RR_NR];
   bool wn[2 * RR_NR], tm[2 * RR_NR], am[2 * RR_NR];
   int ex[2 * RR_NR];
   ArrayInitialize(cst, 0.0);
   bool anyCost = false;
   for(int p = 1; p < NPRF; p++)
      if(g_cp[p].on)
         anyCost = true;
   bool rollTf = InpRollSkip && tfSec <= 3600;
   int rollSkip = 0, rollCut = 0;
   for(int k = 1; k + L - 1 < nc && !IsStopped(); k++)
     {
      //--- statistiche del giorno con le barre prima dell'apertura della candela
      for(; jp < cs[k]; jp++)
        {
         long dk = (long)s.t[jp] / 86400;
         if(dk != dKey)
           {
            dKey = dk;
            dO = s.o[jp];
            dH = s.h[jp];
            dL = s.l[jp];
            cpv = 0;
            cvv = 0;
           }
         if(s.h[jp] > dH)
            dH = s.h[jp];
         if(s.l[jp] < dL)
            dL = s.l[jp];
         double w = s.hasVol ? s.v[jp] : 1.0;
         cpv += (s.h[jp] + s.l[jp] + s.c[jp]) / 3.0 * w;
         cvv += w;
        }
      if(k < 20 || cnt[k] < 0.25 * medCnt)
         continue;
      double O = s.o[cs[k]];
      double S = InpRRStop == RR_STOP_ATR ? InpRRStopK * atr[k - 1] :
                 (InpRRStop == RR_STOP_PREV ? InpRRStopK * (cd.h[k - 1] - cd.l[k - 1]) : InpRRStopK / 100.0 * O);
      if(!(S > 0) || !(O > 0))
         continue;
      int jEnd = ce[k + L - 1] - 1;
      if(rollTf)  // rollover: nessuna entrata nella finestra, chiusura a mercato prima della prossima
        {
         if(RollIn(cd.t[k]))
           {
            rollSkip++;
            continue;
           }
         datetime rs = RollNext(cd.t[k]);
         if(s.t[jEnd] >= rs)
           {
            int j = LowerBound(s.t, s.n, rs) - 1;
            if(j < cs[k])
              {
               rollSkip++;
               continue;
              }
            if(j < jEnd)
              {
               jEnd = j;
               rollCut++;
              }
           }
        }
      RRWalk(s, cs, ce, k, jEnd, O, S, tfSec, barSec, L, o, wn, tm, am, du, ex);
      sv[nS++] = S;
      datetime t0 = cd.t[k];
      int hf = t0 < tMid ? 0 : 1;
      //--- costi di ogni broker: spread all'entrata (buy) o all'uscita (sell), commissione, slittamento, swap per notte
      if(anyCost)
         for(int p = 1; p < NPRF; p++)
            if(g_cp[p].on)
               for(int i = 0; i < 2 * RR_NR; i++)
                  cst[p * 2 * RR_NR + i] = RRCost1(s, p, i, cs[k], O, ex[i]);
      for(int d = 0; d < RR_NDIM; d++)
         cls[d] = -1;
      cls[0] = 0;
      if(intra)
         cls[1] = tfSec >= 3600 ? (HourOf(t0) / (tfSec / 3600)) * (tfSec / 3600) : HourOf(t0);
      cls[2] = DowMon(t0);
      double rp = ret[k - 1];
      cls[3] = rp >= p80 ? 0 : (rp <= p20 ? 3 : (rp > 0 ? 1 : 2));
      double rg = cd.h[k - 1] - cd.l[k - 1], ra = Dv(rg, atr[k - 1]);
      if(MathIsValidNumber(ra))
         cls[4] = ra < 0.75 ? 0 : (ra > 1.33 ? 2 : 1);
      if(rg > 0)
         cls[5] = (int)MathMin(2.0, MathFloor(3.0 * (cd.c[k - 1] - cd.l[k - 1]) / rg));
      int dr = dir[k - 1], sk = stk[k - 1];
      cls[6] = dr > 0 ? (sk >= 3 ? 0 : (sk == 2 ? 1 : 4)) : (dr < 0 ? (sk >= 3 ? 2 : (sk == 2 ? 3 : 4)) : 4);
      if(k >= 101)
        {
         double vr = Dv((ps[k] - ps[k - 14]) / 14.0, (ps[k] - ps[k - 100]) / 100.0);
         if(MathIsValidNumber(vr))
            cls[7] = vr < 0.8 ? 0 : (vr > 1.2 ? 2 : 1);
        }
      if(MathIsValidNumber(rv[k - 1]))
         cls[8] = rv[k - 1] < 0.8 ? 0 : (rv[k - 1] < 1.5 ? 1 : 2);
      //--- giorno e settimana precedenti
      if(g_per[2].n > 1)
        {
         while(di + 1 < g_per[2].n && g_per[2].s[di + 1] <= cs[k])
            di++;
         if(di >= 1 && g_per[2].s[di] <= cs[k] && cs[k] < g_per[2].e[di] && g_per[2].ok[di - 1])
           {
            double PH = g_per[2].H[di - 1], PL = g_per[2].L[di - 1];
            cls[9] = O > PH ? 0 : (O < PL ? 2 : 1);
            if(cls[9] == 1)
              {
               double dh = (PH - O) / S, dl = (O - PL) / S;
               cls[10] = (dh <= 1 && dh <= dl) ? 0 : (dl <= 1 ? 1 : 2);
              }
            if(di != cachedDi)
              {
               cachedDi = di;
               medDay = PerMedRange(g_per[2], di, 20);
              }
           }
        }
      if(g_per[3].n > 1)
        {
         while(wi + 1 < g_per[3].n && g_per[3].s[wi + 1] <= cs[k])
            wi++;
         if(wi >= 1 && g_per[3].s[wi] <= cs[k] && cs[k] < g_per[3].e[wi] && g_per[3].ok[wi - 1])
            cls[11] = O > g_per[3].H[wi - 1] ? 0 : (O < g_per[3].L[wi - 1] ? 2 : 1);
        }
      //--- il giorno finora (solo timeframe intraday)
      if(intra)
        {
         bool first = dKey != (long)t0 / 86400 || cvv <= 0;
         cls[12] = first ? 2 : (O >= dO ? 0 : 1);
         if(!first)
           {
            cls[13] = O >= cpv / cvv ? 0 : 1;
            if(dH > dL)
               cls[14] = (int)MathMax(0.0, MathMin(2.0, MathFloor(3.0 * (O - dL) / (dH - dL))));
            double rd = Dv(dH - dL, medDay);
            if(MathIsValidNumber(rd))
               cls[15] = rd < 0.5 ? 0 : (rd <= 1.0 ? 1 : 2);
           }
        }
      if(k - 1 >= 50)
        {
         cls[16] = O > e50[k - 1] ? 0 : 1;
         cls[17] = e20[k - 1] > e50[k - 1] ? 0 : 1;
        }
      if(MathIsValidNumber(rsi[k - 1]))
         cls[18] = rsi[k - 1] < 30 ? 0 : (rsi[k - 1] < 50 ? 1 : (rsi[k - 1] < 70 ? 2 : 3));
      long dd = (long)t0 / 86400;
      if(dd != yDay)
        {
         yDay = dd;
         TimeToStruct(t0, md);
         yCur = md.year;
        }
      cls[19] = yCur - y0;
      //--- memorizza il trade e accumula
      int qq = g_qN++, fl = 0;
      g_qK[qq] = k;
      g_qS[qq] = (float)S;
      for(int i = 0; i < 2 * RR_NR; i++)
        {
         g_qO[qq * 2 * RR_NR + i] = (float)o[i];
         g_qD[qq * 2 * RR_NR + i] = (float)du[i];
         g_qX[qq * 2 * RR_NR + i] = ex[i];
         if(wn[i])
            fl |= 1 << i;
         if(tm[i])
            fl |= 1 << (10 + i);
         if(am[i])
            fl |= 1 << (20 + i);
        }
      g_qF[qq] = fl;
      for(int d = 0; d < RR_NDIM; d++)
         g_qC[qq * RR_NDIM + d] = (uchar)((cls[d] >= 0 && cls[d] < g_rrDimC[d]) ? cls[d] : 255);
      double invS = 1.0 / S, u = 1e-4 * O * invS;
      int hSl = intra && cls[1] >= 0 && cls[1] < RR_NH ? cls[1] : 0;  // ora della candela per il confronto con la stessa ora
      for(int d = 0; d < RR_NDIM; d++)
         if(cls[d] >= 0 && cls[d] < g_rrDimC[d])
           {
            RRAcc(g_rrDimB[d] + cls[d], o, wn, tm, am, du, invS, cst, hf, hSl, u);
            RRGap(g_rrDimB[d] + cls[d], k, ring, rN, rP);
           }
      for(int sd = 0; sd < 2; sd++)
        {
         bool stopped = false;
         for(int tg = 1; tg <= RR_NR; tg++)
           {
            int i = sd * RR_NR + tg - 1;
            if(wn[i])
               hw[i * HB + (int)MathMin(HB - 1, (int)(du[i] * 4))]++;
            else
               if(!tm[i] && !stopped)
                 {
                  hs[sd * HB + (int)MathMin(HB - 1, (int)(du[i] * 4))]++;
                  stopped = true;
                 }
           }
        }
     }
   if(g_rrN[0] < 100)
      return;
   RRBase();  // aspettativa della stessa ora: riferimento per contesti singoli e coppie
   //--- tabelle: lordo nella scheda Rischio/rendimento, netto di ogni broker nel buffer della sua scheda
   double medS = MedianOf(sv, nS);
   double tfH = tfSec / 3600.0;
   string stopTxt = InpRRStop == RR_STOP_ATR ? F(InpRRStopK, 2) + " x ATR(14)" :
                    (InpRRStop == RR_STOP_PREV ? F(InpRRStopK, 2) + " x range della candela precedente" : F(InpRRStopK, 2) + "% del prezzo");
   string head = I2S(g_rrN[0]) + " candele dal " + TimeToString(tA, TIME_DATE) + " al " + TimeToString(tB, TIME_DATE) +
                 " (prima met&agrave; fino al " + TimeToString(tMid, TIME_DATE) + ": " + I2S(g_rrNH[0]) + " candele, seconda: " + I2S(g_rrNH[1]) +
                 "); stop = " + stopTxt + ", mediano " + PX(medS) + " (" + FP(medS / g_last, 3) + "% del prezzo attuale); chiusura a mercato " +
                 "dopo " + I2S(L) + " candele (" + DurLab(L * tfH) + ")" +
                 (rollTf ? "; rollover: " + I2S(rollSkip) + " entrate escluse nella finestra " + HM(1440 - RollPre()) + "-" + HM(RollPost()) +
                  " del broker, " + I2S(rollCut) + " operazioni chiuse a mercato prima della finestra" : "") + ".";
   RRRender(0, ti, head, tfH, hw, hs, HB);
   for(int p = 1; p < NPRF; p++)
     {
      if(!g_cp[p].on)
         continue;
      g_buf = true;
      g_bufS = "";
      RRRender(p, ti, head, tfH, hw, hs, HB);
      g_buf = false;
      g_rrHtml[p] += g_bufS;
      g_bufS = "";
     }
   RRPost(s, cs, cd, ti, tMid, p20, p80, L);
  }

//+------------------------------------------------------------------+
//| ORB: rottura del range iniziale a tutti gli orari                 |
//| Nessun orario scelto prima: ogni inizio a passi di InpOrbStep     |
//| minuti nell'ora locale di tre piazze (ora legale USA, europea e   |
//| nessuna, convertite giorno per giorno), ogni durata del range e   |
//| ogni finestra. Rottura = primo tocco oltre il range (quando rompe,|
//| quanto corre, rotture false); operazione = entrata alla chiusura  |
//| della prima candela che chiude fuori dal range: con i soli dati   |
//| M1 il prezzo esatto del tocco non si conosce e un ordine stop     |
//| riempito proprio sul livello darebbe un vantaggio finto. La       |
//| candela di conferma e' M1, M5, M15, M30 o H1 (parametro): dalla   |
//| sua chiusura si misura quanto continua, in quanto tempo, con che  |
//| forza e con che volatilita', con gli stessi controlli dei trade.  |
//+------------------------------------------------------------------+
#define OB_NT   7           // operazioni: 0-3 segui la rottura, 4-6 fade delle prime tre
#define OB_NB   19          // gruppi: 0 tutti, 1-2 rottura su/giu', 3-4 meta' del periodo, 5-11 giorno, 12-14 ampiezza, 15-18 lato x meta'
#define OB_FU   (3 + NPRF)  // campi: trade, somma R, somma R^2, vinti, netta di ogni broker (1..NPRF-1), poi:
#define OB_FU2  (OB_FU + 1) //   costo di 1 punto base in R (somma, quadrati, prodotto con l'esito) per netta e z a ogni livello di costo
#define OB_FRU  (OB_FU + 2)
#define OB_FD   (OB_FU + 3) //   vantaggio sul placebo (somma e quadrati): operazione meno la media tra lei e la direzione opposta
#define OB_FD2  (OB_FU + 4)
#define OB_NF   (OB_FU + 5)
#define OB_NX   101         // istogrammi: 101 caselle (estensione a caselle di 0,1 range, l'ultima = oltre 10)
#define OB_MAXL 6           // durate del range, finestre e candele di conferma al massimo
#define OB_NCA  5           // continuazione: conferme, somma e quadrati di (a favore - contro), a favore > contro, ritesta il livello
#define OB_NE   6           // eventi sulle candele di conferma: vedi OB_EV
#define OB_NEA  (OB_NE + 4) // eventi, poi: giorni, giorni con 2 o piu' candele che toccano senza chiudere fuori, somma di queste candele,
                            // rientri entro 2 candele dalla conferma
string OB_OP[OB_NT] = {"Segui 1:1 (stop all'altro lato)", "Segui 1:2 (stop all'altro lato)", "Segui 1:2 (stop a meta' range)",
                       "Segui a tempo (stop all'altro lato, chiude a fine finestra)", "Fade 1:1 (obiettivo l'altro lato)",
                       "Fade 1:0,5 (obiettivo l'altro lato, stop a 2 volte)", "Fade 1:0,5 (obiettivo meta' range, stop a 2 volte)"
                      };
string OB_SIDE[3] = {"entrambi i lati", "solo rotture al rialzo", "solo rotture al ribasso"};
string OB_EV[OB_NE] = {"nessun tocco", "solo tocchi, nessuna chiusura fuori", "chiude fuori e continua", "chiude fuori, rientra e resta dentro",
                       "chiude fuori, rientra e riparte", "chiude fuori, rientra e si gira"
                      };
string OB_EVS[OB_NE] = {"nessun tocco", "solo tocchi", "continua", "rientra e resta", "rientra e riparte", "rientra e si gira"};
string OB_OPS[OB_NT] = {"S1:1", "S1:2", "S1:2m", "St", "F1:1", "F1:0,5", "F1:0,5m"};  // sigle delle operazioni (appendice del rapporto)
string OB_EVC[OB_NE] = {"#4b5563", C_AMBER, C_BLUE, "#a78bfa", C_GREEN, C_RED};
double OB_K[4]    = {1, 2, 2, 0};  // obiettivo in multipli del rischio (0 = nessuno, chiusura a fine finestra)
bool   OB_MID[4]  = {false, false, true, false};

int    g_obNC = 0, g_obNS = 0, g_obND = 0, g_obNW = 0, g_obNF = 1, g_obStep = 15, g_obMaxW = 240, g_obBar = 60;
int    g_obClk[3];                 // piazze degli orologi
int    g_obD[], g_obW[], g_obKW[]; // durate del range, finestre (minuti), fine di ogni finestra nella giornata
int    g_obCf[], g_obCs[];         // candele di conferma: minuti e secondi (1 = prima chiusura M1 fuori dal range)
bool   g_obOk[];
double g_obA[];                    // accumulatori di un orario di inizio: durata, finestra, conferma, operazione, gruppo, campo
int    g_obE[];                    // obiettivi e stop per durata, finestra, conferma, operazione e lati
int    g_obS[];                    // per durata e finestra: giorni, rotture, al rialzo, tocca l'altro lato, chiude oltre
int    g_obHb[], g_obHx[];         // istogrammi: minuti alla rottura, estensione oltre il lato rotto
int    g_osKey[];                  // per orologio e inizio: minuto dei dati il 15 gennaio * 1440 + il 15 luglio
bool   g_osDup[];                  // stesso orario dei dati di un orologio precedente (cambia solo nelle settimane del cambio d'ora)
int    g_osDay[], g_osBrk[], g_osUp[], g_osFl[], g_osHd[];  // per combinazione (orologio, inizio, durata, finestra)
double g_osBm[], g_osEx[];
int    g_otN[], g_otU[], g_otL[];  // per combinazione, conferma, operazione e lati: trade, obiettivi, stop
double g_otE[], g_otZ[], g_otE1[], g_otE2[], g_otEw[], g_otZw[];
double g_otP[], g_otZp[], g_otBe[];  // placebo lordo, z del vantaggio sul placebo, costo di pareggio (punti base)
bool   g_otSt[];
int    g_obMinDay = 30;            // giorni minimi coperti: un orario coperto in meno della meta' dei giorni (mercato chiuso) e' escluso
//--- stato di ogni candela di conferma durante una giornata (indice f; stop e obiettivi f * 4 + j)
int    g_ofD[], g_ofQe[], g_ofQm[], g_ofVn[];
double g_ofEp[], g_ofNu[], g_ofNl[], g_ofMfe[], g_ofMae[], g_ofStr[], g_ofVp[], g_ofVb[];
bool   g_ofRe[];
double g_ofR[], g_ofRx[], g_ofMrx[];
int    g_ofRes[], g_ofRq[], g_ofMres[];  // g_ofMres/g_ofMrx = placebo: la stessa operazione nella direzione opposta
//--- eventi sulle candele di conferma: fase (0 prima della conferma, 1 confermato, 2 rientrato, 3 riparte o si gira), esito finale,
//--- tocchi nella candela in corso, candele che toccano senza chiudere fuori, candele dalla conferma, al rientro, barre di rientro ed evento
int    g_ofPh[], g_ofFin[], g_ofRj[], g_ofN1[], g_ofRc[], g_ofQr[], g_ofQv[];
bool   g_ofTu[], g_ofTd[];
//--- continuazione dopo la conferma, per durata, finestra e conferma (bf = (i * g_obNW + x) * g_obNF + f)
double g_ocA[];
int    g_ohMf[], g_ohMa[], g_ohSt[], g_ohSp[], g_ohVo[];  // a favore, contro, forza, velocita', volatilita' (OB_NX caselle)
int    g_ohTc[], g_ohTm[];                                 // minuti alla conferma e al massimo a favore (g_obMaxW + 1 caselle)
//--- eventi per durata, finestra e conferma (reali e con direzione casuale), minuti al rientro e all'evento finale, falsi segnali
double g_oeA[], g_oeB[];
int    g_ohRt[], g_ohEt[];
int    g_oxA[];                    // per durata e finestra: giorni in cui la conferma f1 c'e' e la f2 no (indice (bs * nf + f1) * nf + f2)
bool   g_obRnd = false;            // eventi attesi calcolati
CSeries g_obSim;                   // stesse barre con direzione casuale (un orario di inizio alla volta)
//--- per combinazione e conferma (cf = cfg * g_obNF + f): mediane e controlli della continuazione
int    g_ocN[];
double g_ocTc[], g_ocSt[], g_ocMf[], g_ocMa[], g_ocZc[], g_ocW[], g_ocTm[], g_ocSp[], g_ocVo[], g_ocRe[];
//--- eventi per combinazione e conferma: quote reali, attese e z (indice cf * OB_NE + evento), giorni, tocchi senza chiusura, rientri
//--- subito, minuti al rientro e all'evento finale; falsi segnali per combinazione (conferme di f1 che f2 non conferma)
double g_oeS[], g_oeX[], g_oeZ[], g_oeR2[], g_oeRj[], g_oeF[], g_oeTr[], g_oeTv[], g_oxS[];
int    g_oeN[];
//--- volatilita' della stessa ora: range delle barre allo stesso minuto dall'inizio nei 20 giorni validi precedenti
int    g_ovNO = 0, g_ovPos = 0;
double g_ovDay[], g_ovRing[], g_ovSum[];
int    g_ovCnt[];
int    g_orN = 0;                  // regole ORB da esportare
int    g_orX[];
string g_repOrb = "", g_obEvTx = "";
int    g_obCsv = INVALID_HANDLE;

struct ObSt
  {
   int               n, nU, nL;
   double            e, z, win, e1, e2, ew, zw;
   double            pl, adv, zp;  // placebo lordo (stesso istante, direzione a caso), vantaggio sul placebo e suo z
   double            ub, be;       // costo di 1 punto base in R (media), costo di pareggio in punti base
   bool              st;  // positiva (o negativa) in entrambe le meta' per tutti i broker
  };

int ObCfg(const int c, const int sI, const int i, const int x) { return ((c * g_obNS + sI) * g_obND + i) * g_obNW + x; }
int ObTr(const int cf, const int t, const int sd) { return (cf * OB_NT + t) * 3 + sd; }  // cf = combinazione * g_obNF + conferma
int ObBf(const int i, const int x, const int f) { return (i * g_obNW + x) * g_obNF + f; }
int ObA(const int i, const int x, const int f, const int t, const int b) { return ((ObBf(i, x, f) * OB_NT + t) * OB_NB + b) * OB_NF; }
int ObE(const int i, const int x, const int f, const int t, const int b) { return ((ObBf(i, x, f) * OB_NT + t) * 3 + b) * 2; }
int ObBin(const double v) { return MathIsValidNumber(v) ? (int)MathMax(0.0, MathMin(OB_NX - 1.0, MathFloor(v))) : 0; }

// elenco di minuti separati da virgola, senza doppioni, in ordine crescente
int OrbList(const string txt, int &out[], const int lo, const int hi)
  {
   string p[];
   int k = StringSplit(txt, ',', p), n = 0;
   ArrayResize(out, 0);
   for(int i = 0; i < k && n < OB_MAXL; i++)
     {
      string t = p[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      int v = (int)StringToInteger(t);
      if(t == "" || v < lo || v > hi)
         continue;
      bool dup = false;
      for(int j = 0; j < n; j++)
         if(out[j] == v)
            dup = true;
      if(dup)
         continue;
      ArrayResize(out, n + 1);
      out[n++] = v;
     }
   ArraySort(out);
   return n;
  }

string ObLoc(const int cs) { return MKT_SHORT[g_obClk[cs / g_obNS]] + " " + HM((cs % g_obNS) * g_obStep); }
string ObDat(const int cs)
  {
   int a = g_osKey[cs] / 1440, b = g_osKey[cs] % 1440;
   return HM(a) + (a != b ? " / " + HM(b) : "");
  }
string ObCfgLab(const int cfg)
  {
   int x = cfg % g_obNW, i = (cfg / g_obNW) % g_obND, cs = cfg / (g_obNW * g_obND);
   return ObLoc(cs) + " (dati " + ObDat(cs) + "), range " + I2S(g_obD[i]) + " min, finestra " + I2S(g_obW[x]) + " min";
  }
string ObTf(const int f) { int m = g_obCf[f]; return m < 60 ? "M" + I2S(m) : "H" + I2S(m / 60); }  // candela di conferma
string ObCfLab(const int cf) { return ObCfgLab(cf / g_obNF) + ", conferma " + ObTf(cf % g_obNF); }

int ObBest(const int cf)  // operazione con lo z netto del broker peggiore piu' alto (entrambi i lati)
  {
   int bt = 0;
   for(int t = 1; t < OB_NT; t++)
     {
      int a = ObTr(cf, t, 0), b = ObTr(cf, bt, 0);
      if(g_otN[a] >= 30 && MathIsValidNumber(g_otZw[a]) && (g_otN[b] < 30 || !MathIsValidNumber(g_otZw[b]) || g_otZw[a] > g_otZw[b]))
         bt = t;
     }
   return bt;
  }

// rv = esito lordo in R, nt = netto per broker, ev = obiettivo (1) o stop (-1), u = costo di 1 punto base in R, dv = vantaggio sul placebo
void OrbAdd(const int i, const int x, const int f, const int t, const int b, const double rv, const double &nt[], const int ev, const double u,
            const double dv)
  {
   int a = ObA(i, x, f, t, b);
   g_obA[a] += 1;
   g_obA[a + 1] += rv;
   g_obA[a + 2] += rv * rv;
   if(rv > 0)
      g_obA[a + 3] += 1;
   for(int p = 1; p < NPRF; p++)
      g_obA[a + 3 + p] += nt[p];
   g_obA[a + OB_FU] += u;
   g_obA[a + OB_FU2] += u * u;
   g_obA[a + OB_FRU] += rv * u;
   g_obA[a + OB_FD] += dv;
   g_obA[a + OB_FD2] += dv * dv;
   if(b < 3 && ev != 0)
      g_obE[ObE(i, x, f, t, b) + (ev > 0 ? 0 : 1)]++;
  }

// statistiche di un gruppo: lorda e z contro zero, meta' del periodo, netta e z del broker peggiore (lorda se non ci sono costi)
bool ObStat(const int i, const int x, const int f, const int t, const int b, ObSt &q)
  {
   ZeroMemory(q);
   q.e = Nan();
   q.z = Nan();
   q.win = Nan();
   q.e1 = Nan();
   q.e2 = Nan();
   q.ew = Nan();
   q.zw = Nan();
   q.pl = Nan();
   q.adv = Nan();
   q.zp = Nan();
   q.ub = Nan();
   q.be = Nan();
   int a = ObA(i, x, f, t, b);
   q.n = (int)g_obA[a];
   if(b < 3)
     {
      int ie = ObE(i, x, f, t, b);
      q.nU = g_obE[ie];
      q.nL = g_obE[ie + 1];
     }
   if(q.n < 2)
      return false;
   q.e = g_obA[a + 1] / q.n;
   double var = g_obA[a + 2] / q.n - q.e * q.e, se = var > 0 ? MathSqrt(var / q.n) : 0;
   q.z = se > 0 ? q.e / se : Nan();
   q.win = g_obA[a + 3] / q.n;
   q.ew = q.e;
   q.zw = q.z;
   //--- placebo: la stessa operazione nello stesso istante con direzione a caso (media tra lei e la direzione opposta, stesse
   //--- distanze di stop e obiettivo); vantaggio = operazione - placebo, z sulle differenze giorno per giorno
   q.adv = g_obA[a + OB_FD] / q.n;
   q.pl = q.e - q.adv;
   double vd = g_obA[a + OB_FD2] / q.n - q.adv * q.adv;
   q.zp = vd > 1e-9 * (var + 1e-12) ? q.adv / MathSqrt(vd / q.n) : Nan();
   //--- costo di pareggio: livello di costo (punti base) che porta a zero l'aspettativa lorda
   q.ub = g_obA[a + OB_FU] / q.n;
   q.be = q.ub > 0 ? q.e / q.ub : Nan();
   int h1 = b == 0 ? 3 : (b == 1 ? 15 : (b == 2 ? 17 : -1));
   if(h1 < 0)
      return true;
   int a1 = ObA(i, x, f, t, h1), a2 = ObA(i, x, f, t, h1 + 1);
   double n1 = g_obA[a1], n2 = g_obA[a2];
   q.e1 = n1 > 0 ? g_obA[a1 + 1] / n1 : Nan();
   q.e2 = n2 > 0 ? g_obA[a2 + 1] / n2 : Nan();
   bool any = false, st = n1 >= 30 && n2 >= 30;
   for(int p = 1; p < NPRF; p++)
     {
      if(!g_cp[p].on)
         continue;
      double en = g_obA[a + 3 + p] / q.n, zn = se > 0 ? en / se : Nan();
      if(!any || zn < q.zw)
         q.zw = zn;
      if(!any || en < q.ew)
         q.ew = en;
      double f1 = n1 > 0 ? g_obA[a1 + 3 + p] / n1 : Nan(), f2 = n2 > 0 ? g_obA[a2 + 3 + p] / n2 : Nan();
      st = st && f1 * en > 0 && f2 * en > 0;
      any = true;
     }
   if(!any)
      st = st && q.e1 * q.e > 0 && q.e2 * q.e > 0;
   q.st = st;
   return true;
  }

// aspettativa e z con un costo per trade di c punti base del prezzo (varianza esatta: il costo in R cambia da trade a trade)
bool ObNetBp(const int i, const int x, const int f, const int t, const int b, const double c, double &e, double &z)
  {
   e = Nan();
   z = Nan();
   int a = ObA(i, x, f, t, b);
   double n = g_obA[a];
   if(n < 2)
      return false;
   double m = g_obA[a + 1] / n, ub = g_obA[a + OB_FU] / n;
   double vr = g_obA[a + 2] / n - m * m, vu = g_obA[a + OB_FU2] / n - ub * ub, cv = g_obA[a + OB_FRU] / n - m * ub;
   double v = vr - 2 * c * cv + c * c * vu;
   e = m - c * ub;
   z = v > 0 ? e / MathSqrt(v / n) : Nan();
   return true;
  }

string ObLev(const int i, const int x, const int f, const int t, const int b)  // aspettativa a ogni livello di costo, separate da " / "
  {
   string s = "";
   for(int j = 0; j < g_bpN; j++)
     {
      double e = 0, z = 0;
      ObNetBp(i, x, f, t, b, g_bpV[j], e, z);
      s += (j > 0 ? " / " : "") + SgnF(e, 3);
     }
   return s;
  }

// conferma f alla chiusura della barra q (chiusura della sua candela fuori dal range): entrata, stop e obiettivi, prossimi livelli
void OrbEnter(const int f, const int q, const double c, const double hi, const double lo, const double mid, const double w)
  {
   int d = c > hi ? 1 : -1;
   g_ofD[f] = d;
   g_ofQe[f] = q;
   g_ofEp[f] = c;
   g_ofStr[f] = d * (c - (d > 0 ? hi : lo)) / w;
   double nu = DBL_MAX, nl = -DBL_MAX;
   for(int j = 0; j < 4; j++)
     {
      double r = d * (c - (OB_MID[j] ? mid : (d > 0 ? lo : hi)));
      g_ofR[f * 4 + j] = r;
      if(OB_K[j] > 0 && OB_K[j] * r < nu)
         nu = OB_K[j] * r;
      if(-r > nl)
         nl = -r;
      if(r < nu)
         nu = r;
      if(OB_K[j] > 0 && -OB_K[j] * r > nl)
         nl = -OB_K[j] * r;
     }
   g_ofNu[f] = nu;
   g_ofNl[f] = nl;
  }

// una barra dopo l'entrata della conferma f: stop e obiettivi lungo il percorso della barra; in parallelo il placebo, cioe' la
// stessa operazione nella direzione opposta con le stesse distanze (stop a +r, obiettivo a -K r)
void OrbWalk(const int f, const double o, const double h, const double l, const double &P[], const int q)
  {
   int d = g_ofD[f];
   double Ep = g_ofEp[f];
   double xH = d > 0 ? h - Ep : Ep - l, xL = d > 0 ? l - Ep : Ep - h;
   if(xH < g_ofNu[f] && xL > g_ofNl[f])
      return;
   double a = d * (o - Ep);
   for(int j = 0; j < 4; j++)  // apertura gia' oltre un livello: eseguito all'apertura
     {
      int fj = f * 4 + j;
      double r = g_ofR[fj];
      if(g_ofRes[fj] == 0)
        {
         if(OB_K[j] > 0 && a >= OB_K[j] * r)
           {
            g_ofRes[fj] = 1;
            g_ofRx[fj] = a;
            g_ofRq[fj] = q;
           }
         else
            if(a <= -r)
              {
               g_ofRes[fj] = -1;
               g_ofRx[fj] = a;
               g_ofRq[fj] = q;
              }
        }
      if(g_ofMres[fj] == 0)
        {
         if(a >= r)
           {
            g_ofMres[fj] = 1;
            g_ofMrx[fj] = a;
           }
         else
            if(OB_K[j] > 0 && a <= -OB_K[j] * r)
              {
               g_ofMres[fj] = -1;
               g_ofMrx[fj] = a;
              }
        }
     }
   for(int z = 1; z < 4; z++)
     {
      double b = d * (P[z] - Ep);
      for(int j = 0; j < 4; j++)
        {
         int fj = f * 4 + j;
         double r = g_ofR[fj];
         if(g_ofRes[fj] == 0)
           {
            if(b > a && OB_K[j] > 0 && b >= OB_K[j] * r)
              {
               g_ofRes[fj] = 1;
               g_ofRx[fj] = OB_K[j] * r;
               g_ofRq[fj] = q;
              }
            else
               if(b < a && b <= -r)
                 {
                  g_ofRes[fj] = -1;
                  g_ofRx[fj] = -r;
                  g_ofRq[fj] = q;
                 }
           }
         if(g_ofMres[fj] == 0)
           {
            if(b > a && b >= r)
              {
               g_ofMres[fj] = 1;
               g_ofMrx[fj] = r;
              }
            else
               if(b < a && OB_K[j] > 0 && b <= -OB_K[j] * r)
                 {
                  g_ofMres[fj] = -1;
                  g_ofMrx[fj] = -OB_K[j] * r;
                 }
           }
        }
      a = b;
     }
   double nu = DBL_MAX, nl = -DBL_MAX;
   for(int j = 0; j < 4; j++)
     {
      int fj = f * 4 + j;
      double r = g_ofR[fj];
      if(g_ofRes[fj] == 0)
        {
         if(OB_K[j] > 0 && OB_K[j] * r < nu)
            nu = OB_K[j] * r;
         if(-r > nl)
            nl = -r;
        }
      if(g_ofMres[fj] == 0)
        {
         if(r < nu)
            nu = r;
         if(OB_K[j] > 0 && -OB_K[j] * r > nl)
            nl = -OB_K[j] * r;
        }
     }
   g_ofNu[f] = nu;
   g_ofNl[f] = nl;
  }

// fine della finestra x alla barra q per la conferma f: esiti delle operazioni (lordo, netto, placebo, costo) e continuazione
void OrbSnap(CSeries &s, const int i, const int x, const int f, const int q, const double w, const int hf, const int dw, const int wc,
             const long off7, const long E0)
  {
   int d = g_ofD[f], qe = g_ofQe[f];
   double Ep = g_ofEp[f];
   double nt[NPRF];
   int sdF = d > 0 ? 0 : 1, sdB = d > 0 ? 1 : 2;
   datetime tE = (datetime)((long)s.t[qe] + g_obBar + off7);
   int hE = HourOf(tE);
   long dE = (long)tE / 86400;
   double xc = d * (s.c[q] - Ep);
   for(int j = 0; j < 4; j++)
     {
      int fj = f * 4 + j;
      bool hit = g_ofRes[fj] != 0 && g_ofRq[fj] <= q;
      double xx = hit ? g_ofRx[fj] : xc;
      double xm = g_ofMres[fj] != 0 ? g_ofMrx[fj] : xc;  // placebo: uscita della direzione opposta
      int ev = hit ? g_ofRes[fj] : 0;
      datetime tX = (datetime)((long)s.t[hit ? g_ofRq[fj] : q] + (hit ? 0 : g_obBar) + off7);
      int hX = HourOf(tX);
      long dX = (long)tX / 86400;
      for(int m = 0; m < 2; m++)
        {
         if(m == 1 && OB_K[j] <= 0)
            break;
         int t = m == 0 ? j : 4 + j, sd = m == 0 ? sdF : 1 - sdF;
         double risk = m == 0 ? g_ofR[fj] : OB_K[j] * g_ofR[fj];
         double rv = (m == 0 ? xx : -xx) / risk;
         //--- vantaggio sul placebo = meta' della differenza tra l'operazione e la direzione opposta con le stesse
         //--- distanze (per il fade la direzione opposta segue la rottura con stop a -K r e obiettivo a +r)
         double dv = (m == 0 ? xx + xm : -(xx + xm)) / (2 * risk);
         double u = 1e-4 * Ep / risk;  // costo di 1 punto base del prezzo in R
         nt[0] = rv;
         for(int p = 1; p < NPRF; p++)
           {
            if(!g_cp[p].on)
              {
               nt[p] = rv;
               continue;
              }
            double sw = dX > dE ? CostNights(dE, dX, g_cp[p].triple) * (g_cp[p].swA[sd] + g_cp[p].swP[sd] * Ep) : 0;
            nt[p] = rv - ((sd == 0 ? g_cp[p].sp[hE] : g_cp[p].sp[hX]) + g_cp[p].comm + g_cp[p].slip - sw) / risk;
           }
         int ue = m == 0 ? ev : -ev;  // per il fade l'obiettivo e' lo stop della rottura e viceversa
         OrbAdd(i, x, f, t, 0, rv, nt, ue, u, dv);
         OrbAdd(i, x, f, t, sdB, rv, nt, ue, u, dv);
         OrbAdd(i, x, f, t, 3 + hf, rv, nt, 0, u, dv);
         OrbAdd(i, x, f, t, 5 + dw, rv, nt, 0, u, dv);
         if(wc >= 0)
            OrbAdd(i, x, f, t, 12 + wc, rv, nt, 0, u, dv);
         OrbAdd(i, x, f, t, 15 + (sdB - 1) * 2 + hf, rv, nt, 0, u, dv);
        }
     }
   //--- continuazione dalla chiusura di conferma: quanto va a favore e quanto contro (con direzione a caso le due si equivalgono:
   //--- e' il placebo), in quanti minuti arriva al massimo, forza della conferma, velocita', volatilita' contro la stessa ora
   int bf = ObBf(i, x, f), ca = bf * OB_NCA, hb = bf * OB_NX, hm = bf * (g_obMaxW + 1);
   double mf = g_ofMfe[f] / w, ma = g_ofMae[f] / w, df = mf - ma;
   g_ocA[ca] += 1;
   g_ocA[ca + 1] += df;
   g_ocA[ca + 2] += df * df;
   if(mf > ma)
      g_ocA[ca + 3] += 1;
   if(g_ofRe[f])
      g_ocA[ca + 4] += 1;
   g_ohMf[hb + ObBin(mf * 10)]++;
   g_ohMa[hb + ObBin(ma * 10)]++;
   g_ohSt[hb + ObBin(g_ofStr[f] * 20)]++;
   int tc = (int)(((long)s.t[qe] + g_obBar - E0) / 60);
   g_ohTc[hm + MathMax(0, MathMin(g_obMaxW, tc))]++;
   double tm = g_ofQm[f] >= 0 ? (double)((long)s.t[g_ofQm[f]] - (long)s.t[qe]) / 60.0 : 0;
   g_ohTm[hm + MathMax(0, MathMin(g_obMaxW, (int)tm))]++;
   g_ohSp[hb + ObBin(g_ofQm[f] >= 0 ? mf / MathMax(tm, g_obBar / 60.0) * 600.0 : 0)]++;  // range all'ora, caselle da 0,1
   if(g_ofVn[f] > 0 && g_ofVb[f] > 0)
      g_ohVo[hb + ObBin(g_ofVp[f] / g_ofVb[f] * 20)]++;
  }

// fine della finestra x alla barra q: evento della giornata sulle candele della conferma f (con o senza conferma), tocchi senza
// chiusura, rientro subito, minuti al rientro e all'evento finale
void OrbEvSnap(CSeries &s, const int i, const int x, const int f, const long E0, const bool touched)
  {
   int bf = ObBf(i, x, f), ea = bf * OB_NEA, hm = bf * (g_obMaxW + 1), ph = g_ofPh[f];
   int ev = ph == 0 ? (touched ? 1 : 0) : (ph == 1 ? 2 : (ph == 2 ? 3 : g_ofFin[f]));
   g_oeA[ea + ev] += 1;
   g_oeA[ea + OB_NE] += 1;
   if(g_ofRj[f] >= 2)
      g_oeA[ea + OB_NE + 1] += 1;
   g_oeA[ea + OB_NE + 2] += g_ofRj[f];
   if(ph >= 2)
     {
      if(g_ofRc[f] <= 2)
         g_oeA[ea + OB_NE + 3] += 1;
      g_ohRt[hm + MathMax(0, MathMin(g_obMaxW, (int)(((long)s.t[g_ofQr[f]] + g_obBar - E0) / 60)))]++;
     }
   if(ph == 3)
      g_ohEt[hm + MathMax(0, MathMin(g_obMaxW, (int)(((long)s.t[g_ofQv[f]] + g_obBar - E0) / 60)))]++;
  }

// una giornata: range [T, T+D), poi le finestre dalla fine del range; ritorna l'ampiezza del range (0 = giorno non valido)
double OrbDay(CSeries &s, const int k, const datetime T, const int i, const datetime tMid, const int dw, const long off7, const double wMean)
  {
   int D = g_obD[i];
   long E0 = (long)T + D * 60;
   if(RollHit7((long)T + off7, E0 - 1 + off7))  // il range tocca la finestra del rollover
      return 0;
   int kor = LowerBound(s.t, s.n, (datetime)E0);
   if(kor >= s.n || kor - k < MathMax(1, D * 60 / g_obBar / 2) || (long)s.t[kor] - E0 >= 900)
      return 0;
   double hi = s.h[k], lo = s.l[k];
   for(int q = k + 1; q < kor; q++)
     {
      if(s.h[q] > hi)
         hi = s.h[q];
      if(s.l[q] < lo)
         lo = s.l[q];
     }
   double w = hi - lo;
   if(!(w > 0))
      return 0;
   //--- finestre coperte: nessun buco oltre 15 minuti e barre fino alla fine della finestra (venerdi' sera, festivi)
   int kEnd = kor, gap = s.n, qStop = 0;
   for(int x = 0; x < g_obNW; x++)
     {
      g_obKW[x] = LowerBound(s.t, s.n, (datetime)(E0 + g_obW[x] * 60));
      if(g_obKW[x] > kEnd)
         kEnd = g_obKW[x];
     }
   for(int q = kor + 1; q < kEnd; q++)
      if((long)s.t[q] - (long)s.t[q - 1] > 900)
        {
         gap = q;
         break;
        }
   for(int x = 0; x < g_obNW; x++)
     {
      int kx = g_obKW[x];
      g_obOk[x] = kx > kor + 1 && kx <= gap && (long)s.t[kx - 1] >= E0 + g_obW[x] * 60 - 900 &&
                  !RollHit7(E0 + off7, E0 + g_obW[x] * 60 - 1 + off7);
      if(g_obOk[x] && kx > qStop)
         qStop = kx;
     }
   if(qStop == 0)
      return w;
   int hf = T < tMid ? 0 : 1;
   int wc = wMean > 0 ? (w / wMean < 0.75 ? 0 : (w / wMean > 1.33 ? 2 : 1)) : -1;
   double mid = 0.5 * (hi + lo), LT = 0, mxT = 0;
   double P[4];
   for(int f = 0; f < g_obNF; f++)
     {
      g_ofD[f] = 0;
      g_ofQe[f] = -1;
      g_ofQm[f] = -1;
      g_ofVn[f] = 0;
      g_ofEp[f] = 0;
      g_ofNu[f] = DBL_MAX;
      g_ofNl[f] = -DBL_MAX;
      g_ofMfe[f] = 0;
      g_ofMae[f] = 0;
      g_ofStr[f] = 0;
      g_ofVp[f] = 0;
      g_ofVb[f] = 0;
      g_ofRe[f] = false;
      g_ofPh[f] = 0;
      g_ofFin[f] = 0;
      g_ofRj[f] = 0;
      g_ofN1[f] = 0;
      g_ofRc[f] = 0;
      g_ofQr[f] = -1;
      g_ofQv[f] = -1;
      g_ofTu[f] = false;
      g_ofTd[f] = false;
      for(int j = 0; j < 4; j++)
        {
         int fj = f * 4 + j;
         g_ofR[fj] = 0;
         g_ofRx[fj] = 0;
         g_ofMrx[fj] = 0;
         g_ofRes[fj] = 0;
         g_ofRq[fj] = 0;
         g_ofMres[fj] = 0;
        }
     }
   int dT = 0, qT = -1, x = 0;
   bool ft = false;
   for(int q = kor; q < qStop; q++)
     {
      double o = s.o[q], h = s.h[q], l = s.l[q], c = s.c[q];
      //--- percorso dentro la barra come il tester (1 minuto OHLC): rialzista O-L-H-C, ribassista O-H-L-C
      bool lowFirst = c > o || (c == o && o - l < h - o);
      P[0] = o;
      P[1] = lowFirst ? l : h;
      P[2] = lowFirst ? h : l;
      P[3] = c;
      //--- rottura = primo tocco oltre il range; poi estensione e tocco dell'altro lato
      if(dT == 0)
        {
         for(int z = 0; z < 4; z++)
           {
            if(dT == 0)
              {
               if(P[z] > hi)
                 {
                  dT = 1;
                  LT = hi;
                  qT = q;
                  mxT = P[z] - hi;
                 }
               else
                  if(P[z] < lo)
                    {
                     dT = -1;
                     LT = lo;
                     qT = q;
                     mxT = lo - P[z];
                    }
              }
            else
              {
               double xx = dT * (P[z] - LT);
               if(xx > mxT)
                  mxT = xx;
               if(xx <= -w)
                  ft = true;
              }
           }
        }
      else
        {
         double xH = dT > 0 ? h - LT : LT - l, xL = dT > 0 ? l - LT : LT - h;
         if(xH > mxT)
            mxT = xH;
         if(xL <= -w)
            ft = true;
        }
      //--- volatilita' normale di questa barra: range medio della barra allo stesso minuto nei 20 giorni validi precedenti
      double bv = -1;
      int of = (int)(((long)s.t[q] - (long)T) / g_obBar);
      if(of >= 0 && of < g_ovNO && g_ovCnt[of] >= 10)
         bv = g_ovSum[of] / g_ovCnt[of];
      //--- ogni candela di conferma: entrata alla chiusura della prima candela (M1, M5, ...) fuori dal range, poi stop, obiettivi,
      //--- placebo e continuazione misurati dalla chiusura di conferma
      bool lastBar = q + 1 >= s.n;
      for(int f = 0; f < g_obNF; f++)
        {
         bool cl = lastBar || (long)s.t[q + 1] / g_obCs[f] != (long)s.t[q] / g_obCs[f];  // la barra chiude la candela di conferma
         if(g_ofD[f] != 0)
           {
            OrbWalk(f, o, h, l, P, q);
            int d = g_ofD[f];
            double Ep = g_ofEp[f], fav = d > 0 ? h - Ep : Ep - l, adv = d > 0 ? Ep - l : h - Ep;
            if(fav > g_ofMfe[f])
              {
               g_ofMfe[f] = fav;
               g_ofQm[f] = q;
              }
            if(adv > g_ofMae[f])
               g_ofMae[f] = adv;
            if(d > 0 ? l < hi : h > lo)
               g_ofRe[f] = true;  // il prezzo torna al livello rotto (ritesta), anche senza chiudere dentro
            if(bv > 0)
              {
               g_ofVp[f] += h - l;
               g_ofVb[f] += bv;
               g_ofVn[f]++;
              }
           }
         else
            if((c > hi || c < lo) && cl)
               OrbEnter(f, q, c, hi, lo, mid, w);
         //--- eventi sulle candele della conferma (si osserva il prezzo, non si opera): una candela che tocca un livello e chiude dentro
         //--- non conferma; dopo la conferma una chiusura dentro il range e' un rientro, poi riparte (chiude fuori dallo stesso lato),
         //--- si gira (chiude fuori dall'altro lato) o resta dentro fino a fine finestra
         if(h > hi)
            g_ofTu[f] = true;
         if(l < lo)
            g_ofTd[f] = true;
         if(cl)
           {
            int ph = g_ofPh[f], d = g_ofD[f];
            if(ph == 0)
              {
               if(d != 0)
                 {
                  g_ofPh[f] = 1;
                  g_ofN1[f] = 0;
                 }
               else
                  if(g_ofTu[f] || g_ofTd[f])
                     g_ofRj[f]++;
              }
            else
              {
               bool ins = c >= lo && c <= hi, same = d > 0 ? c > hi : c < lo, opp = d > 0 ? c < lo : c > hi;
               if(ph == 1)
                 {
                  g_ofN1[f]++;
                  if(ins || opp)
                    {
                     g_ofPh[f] = ins ? 2 : 3;
                     g_ofRc[f] = g_ofN1[f];
                     g_ofQr[f] = q;
                     if(opp)
                       {
                        g_ofFin[f] = 5;
                        g_ofQv[f] = q;
                       }
                    }
                 }
               else
                  if(ph == 2 && (same || opp))
                    {
                     g_ofPh[f] = 3;
                     g_ofFin[f] = same ? 4 : 5;
                     g_ofQv[f] = q;
                    }
              }
            g_ofTu[f] = false;
            g_ofTd[f] = false;
           }
        }
      //--- fine di una finestra: cosa e' successo fin qui
      while(x < g_obNW && g_obKW[x] - 1 <= q)
        {
         if(g_obKW[x] - 1 == q && g_obOk[x])
           {
            int bs = i * g_obNW + x;
            g_obS[bs * 5]++;
            if(dT != 0)
              {
               g_obS[bs * 5 + 1]++;
               if(dT > 0)
                  g_obS[bs * 5 + 2]++;
               if(ft)
                  g_obS[bs * 5 + 3]++;
               if(dT * (c - LT) > 0)
                  g_obS[bs * 5 + 4]++;
               int bm = (int)(((long)s.t[qT] - E0) / 60);
               g_obHb[bs * (g_obMaxW + 1) + MathMax(0, MathMin(g_obMaxW, bm))]++;
               g_obHx[bs * OB_NX + (int)MathMax(0.0, MathMin(OB_NX - 1.0, MathFloor(mxT / w * 10.0)))]++;
              }
            for(int f = 0; f < g_obNF; f++)
              {
               if(g_ofD[f] != 0 && g_ofQe[f] < q)
                  OrbSnap(s, i, x, f, q, w, hf, dw, wc, off7, E0);
               OrbEvSnap(s, i, x, f, E0, dT != 0);
               //--- falsi segnali: conferma su questa candela ma non su un'altra (di solito piu' lunga)
               if(g_ofD[f] != 0)
                  for(int f2 = 0; f2 < g_obNF; f2++)
                     if(f2 != f && g_ofD[f2] == 0)
                        g_oxA[(bs * g_obNF + f) * g_obNF + f2]++;
              }
           }
         x++;
        }
     }
   return w;
  }

// tutte le giornate per un orario di inizio (orologio c, inizio sI): accumulatori di tutte le durate, finestre e conferme
void OrbScan(CSeries &s, const int c, const int sI, const long d0, const long d1, const datetime tMid)
  {
   ArrayInitialize(g_obA, 0.0);
   ArrayInitialize(g_obE, 0);
   ArrayInitialize(g_obS, 0);
   ArrayInitialize(g_obHb, 0);
   ArrayInitialize(g_obHx, 0);
   ArrayInitialize(g_ocA, 0.0);
   ArrayInitialize(g_ohMf, 0);
   ArrayInitialize(g_ohMa, 0);
   ArrayInitialize(g_ohSt, 0);
   ArrayInitialize(g_ohSp, 0);
   ArrayInitialize(g_ohVo, 0);
   ArrayInitialize(g_ohTc, 0);
   ArrayInitialize(g_ohTm, 0);
   ArrayInitialize(g_oeA, 0.0);
   ArrayInitialize(g_ohRt, 0);
   ArrayInitialize(g_ohEt, 0);
   ArrayInitialize(g_oxA, 0);
   ArrayInitialize(g_ovRing, -1.0);
   ArrayInitialize(g_ovSum, 0.0);
   ArrayInitialize(g_ovCnt, 0);
   g_ovPos = 0;
   int mk = g_obClk[c], mn = sI * g_obStep;
   double wBuf[], wSum[];
   int wCnt[], wPos[];
   ArrayResize(wBuf, g_obND * 20);
   ArrayResize(wSum, g_obND);
   ArrayResize(wCnt, g_obND);
   ArrayResize(wPos, g_obND);
   ArrayInitialize(wSum, 0.0);
   ArrayInitialize(wCnt, 0);
   ArrayInitialize(wPos, 0);
   for(long day = d0; day <= d1; day++)
     {
      datetime T = LocalToData(day, mk, mn);
      int k = LowerBound(s.t, s.n, T);
      if(k >= s.n || (long)s.t[k] - (long)T >= 120)
         continue;
      //--- range di ogni barra di oggi per minuto dall'inizio: entra nel riferimento della stessa ora dei giorni successivi
      int qv = k;
      for(int of = 0; of < g_ovNO; of++)
        {
         long tt = (long)T + (long)of * g_obBar;
         while(qv < s.n && (long)s.t[qv] < tt)
            qv++;
         g_ovDay[of] = qv < s.n && (long)s.t[qv] == tt ? s.h[qv] - s.l[qv] : -1.0;
        }
      int dw = DowMon(T);
      long off7 = (long)DataToNY7(T) - (long)T;
      for(int i = 0; i < g_obND; i++)
        {
         //--- ampiezza del range rispetto alla media dei 20 giorni validi precedenti (stesso orario e durata)
         double wm = wCnt[i] >= 10 ? wSum[i] / wCnt[i] : 0;
         double w = OrbDay(s, k, T, i, tMid, dw, off7, wm);
         if(!(w > 0))
            continue;
         int z = i * 20 + wPos[i];
         if(wCnt[i] >= 20)
            wSum[i] -= wBuf[z];
         else
            wCnt[i]++;
         wBuf[z] = w;
         wSum[i] += w;
         wPos[i] = (wPos[i] + 1) % 20;
        }
      //--- oggi entra nel riferimento (ultimi 20 giorni validi), dopo averlo usato: ogni giorno si confronta solo con i precedenti
      int rb = g_ovPos * g_ovNO;
      for(int of = 0; of < g_ovNO; of++)
        {
         double old = g_ovRing[rb + of], nw = g_ovDay[of];
         if(old >= 0)
           {
            g_ovSum[of] -= old;
            g_ovCnt[of]--;
           }
         g_ovRing[rb + of] = nw;
         if(nw >= 0)
           {
            g_ovSum[of] += nw;
            g_ovCnt[of]++;
           }
        }
      g_ovPos = (g_ovPos + 1) % 20;
     }
  }

// eventi attesi: le stesse barre degli stessi giorni (stessi orari, stessa ampiezza minuto per minuto) con la direzione di ogni barra
// estratta a caso, come il riferimento delle Sessioni; resta l'effetto della sola volatilita' (serie per un orario di inizio)
void OrbSim(CSeries &s, const int c, const int sI, const long d0, const long d1, CSeries &sim)
  {
   int mk = g_obClk[c], mn = sI * g_obStep;
   long span = (long)(g_obD[g_obND - 1] + g_obMaxW) * 60 + g_obBar;
   MathSrand(4321 + c * 1000 + sI);
   int n = 0;
   for(long day = d0; day <= d1; day++)
     {
      datetime T = LocalToData(day, mk, mn);
      int k = LowerBound(s.t, s.n, T);
      if(k < 1 || k >= s.n || (long)s.t[k] - (long)T >= 120 || (n > 0 && (long)s.t[k] <= (long)sim.t[n - 1]))
         continue;
      int ke = LowerBound(s.t, s.n, (datetime)((long)T + span));
      if(n + ke - k > ArraySize(sim.t))
        {
         int ns = n + ke - k + 200000;
         ArrayResize(sim.t, ns); ArrayResize(sim.o, ns); ArrayResize(sim.h, ns); ArrayResize(sim.l, ns); ArrayResize(sim.c, ns);
         ArrayResize(sim.v, ns);
        }
      double pc = s.c[k - 1];
      for(int q = k; q < ke; q++)
        {
         double ref = s.c[q - 1];
         double ro = s.o[q] / ref, rh = s.h[q] / ref, rl = s.l[q] / ref, rc = s.c[q] / ref;
         if((MathRand() & 1) == 1)
           {
            double a = 1.0 / rl;
            rl = 1.0 / rh;
            rh = a;
            ro = 1.0 / ro;
            rc = 1.0 / rc;
           }
         sim.t[n] = s.t[q];
         sim.o[n] = pc * ro;
         sim.h[n] = pc * rh;
         sim.l[n] = pc * rl;
         sim.c[n] = pc * rc;
         sim.v[n] = s.v[q];
         pc = sim.c[n];
         n++;
        }
     }
   sim.n = n;
   sim.hasVol = s.hasVol;
  }

string ObNet(const int i, const int x, const int f, const int t, const int b, const int p)  // netta del profilo p e il suo z
  {
   int a = ObA(i, x, f, t, b);
   double n = g_obA[a];
   if(n < 2 || !g_cp[p].on)
      return "-";
   double e = g_obA[a + 1] / n, var = g_obA[a + 2] / n - e * e, se = var > 0 ? MathSqrt(var / n) : 0;
   double en = g_obA[a + 3 + p] / n;
   return SgnF(en, 3) + " (z " + ZS(se > 0 ? en / se : Nan()) + ")";
  }

// continuazione dopo la conferma in breve: a favore / contro (range, mediane) e z della differenza
string ObCont(const int cf) { return g_ocN[cf] > 0 ? F(g_ocMf[cf], 2) + " / " + F(g_ocMa[cf], 2) + " (z " + ZS(g_ocZc[cf]) + ")" : "-"; }

// orario locale della piazza a 'mins' minuti dalla fine del range della combinazione (per dire a che ora avviene un evento)
string ObClk(const int cf, const double mins)
  {
   if(!MathIsValidNumber(mins))
      return "-";
   int cfg = cf / g_obNF, i = (cfg / g_obNW) % g_obND, cs = cfg / (g_obNW * g_obND);
   return HM((cs % g_obNS) * g_obStep + g_obD[i] + (int)MathRound(mins));
  }

int ObEvMax(const int cf)  // evento piu' frequente
  {
   int b = 0;
   for(int k = 1; k < OB_NE; k++)
      if(g_oeS[cf * OB_NE + k] > g_oeS[cf * OB_NE + b])
         b = k;
   return b;
  }

string ObEvTop(const int cf)  // evento piu' frequente, quota e (tra parentesi) quota attesa con direzione casuale
  {
   if(g_oeN[cf] <= 0)
      return "-";
   int b = ObEvMax(cf), a = cf * OB_NE + b;
   return OB_EVS[b] + " " + FP(g_oeS[a], 0) + "%" + (g_obRnd ? " (atteso " + FP(g_oeX[a], 0) + "%)" : "");
  }

string ObEvStack(const int cf)  // barra con le quote dei sei eventi
  {
   string t = "<div class='st'>";
   for(int k = 0; k < OB_NE; k++)
     {
      double v = g_oeS[cf * OB_NE + k];
      if(MathIsValidNumber(v) && v > 0)
         t += "<i style='width:" + DoubleToString(v * 100, 1) + "%;background:" + OB_EVC[k] + "'></i>";
     }
   return t + "</div>";
  }

string ObEvTxt(const int cf)  // tutti gli eventi: reale, atteso e z; tocchi senza chiusura, rientri subito, orari
  {
   if(g_oeN[cf] <= 0)
      return "-";
   string t = "";
   for(int k = 0; k < OB_NE; k++)
     {
      int a = cf * OB_NE + k;
      t += (k > 0 ? "; " : "") + OB_EVS[k] + " " + FP(g_oeS[a], 1) + "%" + (g_obRnd ? " (atteso " + FP(g_oeX[a], 1) + "%, z " + ZS(g_oeZ[a]) + ")" : "");
     }
   return t + "; candele che toccano senza chiudere fuori " + F(g_oeRj[cf], 2) + " al giorno (2 o piu' nel " + FP(g_oeR2[cf], 0) + "% dei giorni); " +
          "rientri entro 2 candele dalla conferma " + FP(g_oeF[cf], 0) + "%; rientro alle " + ObClk(cf, g_oeTr[cf]) + ", riparte o si gira alle " +
          ObClk(cf, g_oeTv[cf]) + " (mediane, ora locale)";
  }

string ObEvCmp(const int cf)  // eventi in breve: reale / atteso (%) nell'ordine di OB_EVS, tocchi senza chiusura, orari
  {
   if(g_oeN[cf] <= 0)
      return "-";
   string t = "";
   for(int k = 0; k < OB_NE; k++)
     {
      int a = cf * OB_NE + k;
      t += (k > 0 ? " " : "") + FP(g_oeS[a], 0) + (g_obRnd ? "/" + FP(g_oeX[a], 0) : "");
     }
   return t + ", tocchi senza chiusura " + F(g_oeRj[cf], 1) + " al giorno, rientro " + ObClk(cf, g_oeTr[cf]) + ", riparte o si gira " +
          ObClk(cf, g_oeTv[cf]);
  }

string ObEvTip(const int cf)  // lo stesso testo per l'attributo title (apostrofi protetti)
  {
   string t = ObEvTxt(cf);
   StringReplace(t, "'", "&#39;");
   return t;
  }

// riassunto di un orario di inizio: combinazioni, CSV, riepilogo, mappa e tabella degli eventi
void OrbStore(const int c, const int sI, const int iRef, const int xRef, string &heat, string &evRows, string &evM)
  {
   int cs = c * g_obNS + sI;
   heat += "<tr>" + TD(ObLoc(cs)) + TD(ObDat(cs));
   for(int i = 0; i < g_obND; i++)
      for(int x = 0; x < g_obNW; x++)
        {
         int cfg = ObCfg(c, sI, i, x), bs = i * g_obNW + x;
         g_osDay[cfg] = g_obS[bs * 5];
         g_osBrk[cfg] = g_obS[bs * 5 + 1];
         g_osUp[cfg] = g_obS[bs * 5 + 2];
         g_osFl[cfg] = g_obS[bs * 5 + 3];
         g_osHd[cfg] = g_obS[bs * 5 + 4];
         g_osBm[cfg] = HistMed(g_obHb, bs * (g_obMaxW + 1), g_obMaxW + 1, 1.0);
         g_osEx[cfg] = HistMed(g_obHx, bs * OB_NX, OB_NX, 10.0);
         bool cov = g_osDay[cfg] >= g_obMinDay;  // orario coperto nella maggior parte dei giorni (non a mercato chiuso)
         for(int f = 0; f < g_obNF; f++)
           {
            int cf = cfg * g_obNF + f, bf = ObBf(i, x, f), ca = bf * OB_NCA, hb = bf * OB_NX, hm = bf * (g_obMaxW + 1);
            //--- continuazione dopo la conferma: mediane e z di (a favore - contro), la cui media con direzione a caso e' zero
            double nc = g_ocA[ca];
            g_ocN[cf] = (int)nc;
            g_ocTc[cf] = HistMed(g_ohTc, hm, g_obMaxW + 1, 1.0);
            g_ocSt[cf] = HistMed(g_ohSt, hb, OB_NX, 20.0);
            g_ocMf[cf] = HistMed(g_ohMf, hb, OB_NX, 10.0);
            g_ocMa[cf] = HistMed(g_ohMa, hb, OB_NX, 10.0);
            g_ocTm[cf] = HistMed(g_ohTm, hm, g_obMaxW + 1, 1.0);
            g_ocSp[cf] = HistMed(g_ohSp, hb, OB_NX, 10.0);
            g_ocVo[cf] = HistMed(g_ohVo, hb, OB_NX, 20.0);
            double md = nc > 0 ? g_ocA[ca + 1] / nc : Nan(), vd = nc > 0 ? g_ocA[ca + 2] / nc - md * md : 0;
            g_ocZc[cf] = nc >= 2 && vd > 0 ? md / MathSqrt(vd / nc) : Nan();
            g_ocW[cf] = nc > 0 ? g_ocA[ca + 3] / nc : Nan();
            g_ocRe[cf] = nc > 0 ? g_ocA[ca + 4] / nc : Nan();
            //--- eventi: quote reali e attese (stesse barre con direzione casuale), z della differenza, tocchi senza chiusura, rientri
            int ea = bf * OB_NEA;
            double nd = g_oeA[ea + OB_NE], ndB = g_oeB[ea + OB_NE], nre = g_oeA[ea + 3] + g_oeA[ea + 4] + g_oeA[ea + 5];
            g_oeN[cf] = (int)nd;
            for(int k = 0; k < OB_NE; k++)
              {
               int a = cf * OB_NE + k;
               g_oeS[a] = nd > 0 ? g_oeA[ea + k] / nd : Nan();
               g_oeX[a] = g_obRnd && ndB > 0 ? g_oeB[ea + k] / ndB : Nan();
               //--- z solo con abbastanza casi attesi (almeno 5 per parte): con eventi rarissimi l'approssimazione normale non vale
               double pb = nd + ndB > 0 ? (g_oeA[ea + k] + g_oeB[ea + k]) / (nd + ndB) : 0;
               g_oeZ[a] = g_obRnd && ndB > 0 && nd > 0 && nd * pb >= 5 && nd * (1 - pb) >= 5 ? Z2(g_oeS[a], nd, g_oeX[a], ndB) : Nan();
              }
            g_oeR2[cf] = nd > 0 ? g_oeA[ea + OB_NE + 1] / nd : Nan();
            g_oeRj[cf] = nd > 0 ? g_oeA[ea + OB_NE + 2] / nd : Nan();
            g_oeF[cf] = nre > 0 ? g_oeA[ea + OB_NE + 3] / nre : Nan();
            g_oeTr[cf] = HistMed(g_ohRt, hm, g_obMaxW + 1, 1.0);
            g_oeTv[cf] = HistMed(g_ohEt, hm, g_obMaxW + 1, 1.0);
            double ncn = g_oeA[ea + 2] + nre;  // giorni con conferma a fine finestra
            for(int f2 = 0; f2 < g_obNF; f2++)
               g_oxS[(cfg * g_obNF + f) * g_obNF + f2] = f2 != f && ncn > 0 ? g_oxA[(bs * g_obNF + f) * g_obNF + f2] / ncn : Nan();
            string evc = "";
            for(int k = 0; k < OB_NE; k++)
              {
               int a = cf * OB_NE + k;
               evc += CN(100.0 * g_oeS[a], 2) + ";" + CN(100.0 * g_oeX[a], 2) + ";" + CN(g_oeZ[a], 2) + ";";
              }
            evc += CN(g_oeRj[cf], 3) + ";" + CN(100.0 * g_oeR2[cf], 2) + ";" + CN(100.0 * g_oeF[cf], 2) + ";" + CN(g_oeTr[cf], 1) + ";" +
                   CN(g_oeTv[cf], 1) + ";";
            for(int t = 0; t < OB_NT; t++)
              {
               ObSt q[3];
               for(int sd = 0; sd < 3; sd++)
                 {
                  ObStat(i, x, f, t, sd, q[sd]);
                  int tr = ObTr(cf, t, sd);
                  g_otN[tr] = q[sd].n;
                  g_otU[tr] = q[sd].nU;
                  g_otL[tr] = q[sd].nL;
                  g_otE[tr] = q[sd].e;
                  g_otZ[tr] = q[sd].z;
                  g_otE1[tr] = q[sd].e1;
                  g_otE2[tr] = q[sd].e2;
                  g_otEw[tr] = q[sd].ew;
                  g_otZw[tr] = q[sd].zw;
                  g_otSt[tr] = q[sd].st;
                  g_otP[tr] = q[sd].pl;
                  g_otZp[tr] = q[sd].zp;
                  g_otBe[tr] = q[sd].be;
                 }
               if(g_obCsv != INVALID_HANDLE && g_osDay[cfg] > 0)
                 {
                  int nr = q[0].n, tm = nr - q[0].nU - q[0].nL;
                  string ln = MKT_SHORT[g_obClk[c]] + ";" + HM(sI * g_obStep) + ";" + HM(g_osKey[cs] / 1440) + ";" + HM(g_osKey[cs] % 1440) + ";" +
                              I2S(g_obD[i]) + ";" + I2S(g_obW[x]) + ";" + ObTf(f) + ";" + I2S(g_osDay[cfg]) + ";" +
                              CN(100.0 * Frac(g_osBrk[cfg], g_osDay[cfg]), 2) + ";" + CN(100.0 * Frac(g_osUp[cfg], g_osBrk[cfg]), 2) + ";" +
                              CN(g_osBm[cfg], 1) + ";" + CN(100.0 * Frac(g_osFl[cfg], g_osBrk[cfg]), 2) + ";" +
                              CN(100.0 * Frac(g_osHd[cfg], g_osBrk[cfg]), 2) + ";" + CN(g_osEx[cfg], 2) + ";" +
                              CN(100.0 * Frac(g_ocN[cf], g_osDay[cfg]), 2) + ";" + CN(g_ocTc[cf], 1) + ";" + CN(g_ocSt[cf], 3) + ";" +
                              CN(g_ocMf[cf], 2) + ";" + CN(g_ocMa[cf], 2) + ";" + CN(100.0 * g_ocW[cf], 2) + ";" + CN(g_ocZc[cf], 2) + ";" +
                              CN(g_ocTm[cf], 1) + ";" + CN(g_ocSp[cf], 2) + ";" + CN(g_ocVo[cf], 2) + ";" + CN(100.0 * g_ocRe[cf], 2) + ";" + evc +
                              Plain(OB_OP[t]) + ";" + I2S(nr) + ";" + CN(100.0 * Frac(q[0].nU, nr), 2) + ";" + CN(100.0 * Frac(q[0].nL, nr), 2) + ";" +
                              CN(100.0 * Frac(tm, nr), 2) + ";" + CN(q[0].win * 100, 2) + ";" + CN(q[0].e, 4) + ";" + CN(q[0].z, 2) + ";" +
                              CN(q[0].e1, 4) + ";" + CN(q[0].e2, 4) + ";" + I2S(q[1].n) + ";" + CN(q[1].e, 4) + ";" + CN(q[1].z, 2) + ";" +
                              I2S(q[2].n) + ";" + CN(q[2].e, 4) + ";" + CN(q[2].z, 2);
                  for(int p = 1; p < NPRF; p++)
                    {
                     int a = ObA(i, x, f, t, 0);
                     if(!g_cp[p].on || nr < 2)
                       {
                        ln += ";;";
                        continue;
                       }
                     double e = g_obA[a + 1] / nr, var = g_obA[a + 2] / nr - e * e, se = var > 0 ? MathSqrt(var / nr) : 0,
                            en = g_obA[a + 3 + p] / nr;
                     ln += ";" + CN(en, 4) + ";" + CN(se > 0 ? en / se : Nan(), 2);
                    }
                  ln += ";" + (cov ? "si" : "no") + ";" + CN(q[0].pl, 4) + ";" + CN(q[0].adv, 4) + ";" + CN(q[0].zp, 2) + ";" + CN(q[0].be, 2);
                  for(int j = 0; j < g_bpN; j++)
                    {
                     double e = 0, z = 0;
                     ObNetBp(i, x, f, t, 0, g_bpV[j], e, z);
                     ln += ";" + CN(e, 4) + ";" + CN(z, 2);
                    }
                  FileWriteString(g_obCsv, ln + "\n");
                 }
              }
            //--- riepilogo: segui 1:1, entrambi i lati (obiettivo e stop alla stessa distanza: nessuna distorsione del percorso nella
            //--- barra), e continuazione dopo la conferma (a favore contro contro)
            int t0 = ObTr(cf, 0, 0), nr0 = g_otN[t0];
            if(g_osDup[cs] || !cov)
               continue;
            double cont = Frac(g_otU[t0], g_otU[t0] + g_otL[t0]);
            if(nr0 >= 30)
               Hi(9, g_otZ[t0], "ORB " + ObCfLab(cf) + ", " + I2S(nr0) + " trade: dopo la chiusura fuori dal range arriva prima a +1R " + FP(cont, 1) +
                  "% contro 50% (chiusi a tempo " + Share(nr0 - g_otU[t0] - g_otL[t0], nr0) + "%), aspettativa lorda " + SgnF(g_otE[t0], 3) + " R" +
                  (g_cp[1].on || g_cp[2].on ? ", netta del broker peggiore " + SgnF(g_otEw[t0], 3) + " R" : "") +
                  (g_otZ[t0] > 0 ? ", costo di pareggio " + BpTxt(g_otBe[t0]) : "") +
                  (g_otZ[t0] < 0 ? " (la rottura fallisce piu' del caso: fade)" : " (la rottura prosegue piu' del caso)"));
            if(g_ocN[cf] >= 30)
               Hi(12, g_ocZc[cf], "ORB " + ObCfLab(cf) + ", " + I2S(g_ocN[cf]) + " conferme: dalla chiusura di conferma va a favore fino a " +
                  F(g_ocMf[cf], 2) + " range e contro fino a " + F(g_ocMa[cf], 2) + " (mediane), piu' a favore che contro nel " + FP(g_ocW[cf], 1) +
                  "% dei giorni (atteso 50%); massimo dopo " + F(g_ocTm[cf], 0) + " min, velocita' " + F(g_ocSp[cf], 1) + " range all'ora, " +
                  "volatilita' " + F(g_ocVo[cf], 2) + " volte la stessa ora" + (g_ocZc[cf] < 0 ? " (dopo la conferma va piu' contro: fade)" : ""));
            if(g_obRnd && g_oeN[cf] >= 30)
               for(int k = 0; k < OB_NE; k++)
                 {
                  int a = cf * OB_NE + k;
                  Hi(13, g_oeZ[a], "ORB " + ObCfLab(cf) + ", " + I2S(g_oeN[cf]) + " giorni: " + OB_EV[k] + " nel " + FP(g_oeS[a], 1) +
                     "% dei giorni contro atteso " + FP(g_oeX[a], 1) + "% (stesse barre con direzione casuale)" +
                     (k >= 3 ? "; rientro alle " + ObClk(cf, g_oeTr[cf]) + (k >= 4 ? ", poi alle " + ObClk(cf, g_oeTv[cf]) : "") + " (mediane)" : ""));
                 }
           }
         //--- mappa (conferma di riferimento, la prima dell'elenco): % che arriva prima a +1R tra i trade chiusi, colore = z
         int f0 = cfg * g_obNF, t0 = ObTr(f0, 0, 0), nr0 = g_otN[t0];
         double cont = Frac(g_otU[t0], g_otU[t0] + g_otL[t0]);
         if(nr0 < 30)
            heat += TD("-");
         else
            if(!cov)
               heat += "<td class='muted' title='coperto in " + I2S(g_osDay[cfg]) + " giorni su circa " + I2S(2 * g_obMinDay) +
                       ": mercato chiuso o finestra oltre la chiusura nella maggior parte dei giorni (escluso)'>&middot;</td>";
            else
              {
               string tip = "N " + I2S(nr0) + ", rompe " + Share(g_osBrk[cfg], g_osDay[cfg]) + "% dopo " + F(g_osBm[cfg], 0) + " min, tocca l'altro lato " +
                            Share(g_osFl[cfg], g_osBrk[cfg]) + "%, chiude oltre " + Share(g_osHd[cfg], g_osBrk[cfg]) + "%, estensione " + F(g_osEx[cfg], 1) +
                            " range; conferma " + ObTf(0) + " 1:1 obiettivo " + Share(g_otU[t0], nr0) + "% stop " + Share(g_otL[t0], nr0) + "% a tempo " +
                            Share(nr0 - g_otU[t0] - g_otL[t0], nr0) + "%; lorda " + SgnF(g_otE[t0], 3) + " R z " + ZS(g_otZ[t0]) + "; netta peggiore " +
                            SgnF(g_otEw[t0], 3) + " R; costo di pareggio " + BpTxt(g_otBe[t0]) + "; a favore / contro " + ObCont(f0);
               StringReplace(tip, "'", "&#39;");
               string bg = PCol(g_otZ[t0], 0, 4);
               heat += "<td title='" + tip + "'" + (bg != "" ? " style='background:" + bg + "'" : "") + ">" + FP(cont, 0) + "</td>";
              }
         //--- tabella degli eventi a ogni orario (orologio principale, durata e finestra di riferimento; una colonna per conferma)
         if(c == 0 && i == iRef && x == xRef && g_osDay[cfg] >= 30 && cov)
           {
            //--- eventi per candela di conferma: barra con le sei quote, evento piu' frequente (colore = z contro l'atteso)
            string er = "<tr>" + TD(ObLoc(cs)) + TD(ObDat(cs)) + TD(I2S(g_osDay[cfg]));
            R(g_obEvTx, "    " + ObLoc(cs) + " (dati " + ObDat(cs) + ") - eventi per candela di conferma:");
            for(int f = 0; f < g_obNF; f++)
              {
               int cf = cfg * g_obNF + f, a = cf * OB_NE + ObEvMax(cf);
               string tip = ObEvTip(cf);
               string bg = g_obRnd ? PCol(g_oeZ[a], 0, 4) : "";
               er += "<td title='" + tip + "'" + (bg != "" ? " style='background:" + bg + "'" : "") + ">" + ObEvStack(cf) + ObEvTop(cf) + "</td>";
               R(g_obEvTx, "      " + ObTf(f) + ": " + ObEvTxt(cf));
              }
            evM += er + "</tr>";
            int bt = ObBest(f0), tb = ObTr(f0, bt, 0);
            double hd = Frac(g_osHd[cfg], g_osBrk[cfg]);
            string oth = "", othT = "";
            for(int f = 1; f < g_obNF; f++)
              {
               int cf = cfg * g_obNF + f, tf = ObTr(cf, 0, 0);
               oth += TDc(SgnF(g_otE[tf], 3) + " (" + ZS(g_otZ[tf]) + ") &middot; " + ObCont(cf), PCol(g_otZ[tf], 0, 4));
               othT += "; conferma " + ObTf(f) + ": lorda 1:1 " + SgnF(g_otE[tf], 3) + " R (z " + ZS(g_otZ[tf]) + "), a favore / contro " + ObCont(cf);
              }
            evRows += "<tr>" + TD(ObLoc(cs)) + TD(ObDat(cs)) + TD(I2S(g_osDay[cfg])) + TD(Share(g_osBrk[cfg], g_osDay[cfg]) + " (" +
                      Share(g_osUp[cfg], g_osBrk[cfg]) + " / " + Share(g_osBrk[cfg] - g_osUp[cfg], g_osBrk[cfg]) + ")") + TD(F(g_osBm[cfg], 0)) +
                      TD(Share(g_osFl[cfg], g_osBrk[cfg])) + TDc(FP(hd, 1), PCol(hd, 0.5, 0.15)) + TD(F(g_osEx[cfg], 2)) +
                      TD(Share(g_otU[t0], nr0) + " / " + Share(g_otL[t0], nr0) + " / " + Share(nr0 - g_otU[t0] - g_otL[t0], nr0)) +
                      TDc(SgnF(g_otE[t0], 3) + " (" + ZS(g_otZ[t0]) + ")", PCol(g_otZ[t0], 0, 4)) + TD(SgnF(g_otEw[t0], 3) + " (" + ZS(g_otZw[t0]) + ")") +
                      TD(BpTxt(g_otBe[t0])) + TDc(ObCont(f0), PCol(g_ocZc[f0], 0, 4)) + TD(OB_OP[bt] + " " + SgnF(g_otEw[tb], 3) + " (" + ZS(g_otZw[tb]) +
                            "; contro il placebo " + ZS(g_otZp[tb]) + ")") + oth + "</tr>";
            R(g_obEvTx, "    " + ObLoc(cs) + " (dati " + ObDat(cs) + "), " + I2S(g_osDay[cfg]) + " giorni: rompe " + Share(g_osBrk[cfg], g_osDay[cfg]) +
              "% (su " + Share(g_osUp[cfg], g_osBrk[cfg]) + "%) dopo " + F(g_osBm[cfg], 0) + " min, tocca l'altro lato " + Share(g_osFl[cfg], g_osBrk[cfg]) +
              "%, chiude oltre " + FP(hd, 1) + "%, estensione " + F(g_osEx[cfg], 2) + " range; conferma " + ObTf(0) + ": segui 1:1 obiettivo/stop/tempo " +
              Share(g_otU[t0], nr0) + "/" + Share(g_otL[t0], nr0) + "/" + Share(nr0 - g_otU[t0] - g_otL[t0], nr0) + "%, lorda " + SgnF(g_otE[t0], 3) +
              " R (z " + ZS(g_otZ[t0]) + "), netta peggiore " + SgnF(g_otEw[t0], 3) + ", costo di pareggio " + BpTxt(g_otBe[t0]) + ", a favore / contro " +
              ObCont(f0) + "; migliore netta: " + OB_OP[bt] + " " + SgnF(g_otEw[tb], 3) + " R (z " + ZS(g_otZw[tb]) + ", contro il placebo z " +
              ZS(g_otZp[tb]) + ")" + othT);
           }
         //--- appendice del rapporto: tutte le combinazioni (esclusi orari equivalenti e orari a mercato chiuso, che restano nel CSV)
         if(g_osDay[cfg] > 0 && cov && !g_osDup[cs])
           {
            g_txOrbAll.Add(ObCfgLab(cfg) + ", " + I2S(g_osDay[cfg]) + " giorni: rompe " + Share(g_osBrk[cfg], g_osDay[cfg]) + "% (su " +
                           Share(g_osUp[cfg], g_osBrk[cfg]) + "%) dopo " + F(g_osBm[cfg], 0) + " min, tocca l'altro lato " +
                           Share(g_osFl[cfg], g_osBrk[cfg]) + "%, chiude oltre " + Share(g_osHd[cfg], g_osBrk[cfg]) + "%, estensione " +
                           F(g_osEx[cfg], 2) + " range");
            for(int f = 0; f < g_obNF; f++)
              {
               int cf = cfg * g_obNF + f, t1 = ObTr(cf, 0, 0), bt2 = ObBest(cf), tb2 = ObTr(cf, bt2, 0);
               string ops = "";
               for(int t = 0; t < OB_NT; t++)
                 {
                  int tr = ObTr(cf, t, 0);
                  ops += (t > 0 ? " " : "") + OB_OPS[t] + " " + SgnF(g_otE[tr], 3) + " (" + ZS(g_otZ[tr]) + ")";
                 }
               g_txOrbAll.Add("    " + ObTf(f) + ": conferme " + Share(g_ocN[cf], g_osDay[cfg]) + "% dopo " + F(g_ocTc[cf], 0) + " min (forza " +
                              F(g_ocSt[cf], 2) + ") | lorde " + ops + " | S1:1 netta peggiore " + SgnF(g_otEw[t1], 3) + " (" + ZS(g_otZw[t1]) +
                              "), pareggio " + BpTxt(g_otBe[t1]) + " | migliore netta " + OB_OPS[bt2] + " " + SgnF(g_otEw[tb2], 3) + " (z " +
                              ZS(g_otZw[tb2]) + (g_otSt[tb2] ? "" : "*") + ", placebo " + ZS(g_otZp[tb2]) + ", pareggio " + BpTxt(g_otBe[tb2]) +
                              ") | a favore/contro " + ObCont(cf) + ", massimo dopo " + F(g_ocTm[cf], 0) + " min, velocita' " + F(g_ocSp[cf], 1) +
                              ", volatilita' " + F(g_ocVo[cf], 2) + " | eventi " + ObEvCmp(cf));
              }
           }
        }
   heat += "</tr>";
  }

// dettaglio di una combinazione: quando rompe, quanto corre, la stessa combinazione con ogni candela di conferma, tutte le
// operazioni della conferma scelta, giorni e ampiezza del range
void OrbDetail(CSeries &s, const int cf, const int rank, const long d0, const long d1, const datetime tMid)
  {
   int cfg = cf / g_obNF, fs = cf % g_obNF;
   int x = cfg % g_obNW, i = (cfg / g_obNW) % g_obND, cs = cfg / (g_obNW * g_obND);
   OrbScan(s, cs / g_obNS, cs % g_obNS, d0, d1, tMid);
   int bs = i * g_obNW + x, nb = g_obS[bs * 5 + 1];
   string lab = ObCfLab(cf);
   //--- quando rompe (minuti dalla fine del range) e quanto corre oltre il lato rotto (in range), dal primo tocco
   int bl[7] = {0, 5, 15, 30, 60, 120, 240};
   string bn[7] = {"entro 5 min", "5-15 min", "15-30 min", "30-60 min", "1-2 ore", "2-4 ore", "oltre 4 ore"};
   string tb = "";
   for(int z = 0; z < 7; z++)
     {
      int a = bl[z], b = z < 6 ? bl[z + 1] : g_obMaxW + 1, cnt = 0;
      if(a > g_obW[x])
         break;
      for(int m = a; m < b && m <= g_obMaxW; m++)
         cnt += g_obHb[bs * (g_obMaxW + 1) + m];
      tb += (tb != "" ? ", " : "") + bn[z] + " " + Share(cnt, nb) + "%";
     }
   double el[6] = {0, 0.5, 1, 2, 3, 1e9};
   string en[5] = {"meno di 0,5", "0,5-1", "1-2", "2-3", "oltre 3"};
   string te = "";
   for(int z = 0; z < 5; z++)
     {
      int cnt = 0;
      for(int m = 0; m < OB_NX; m++)
        {
         double v = m / 10.0;
         if(v >= el[z] && v < el[z + 1])
            cnt += g_obHx[bs * OB_NX + m];
        }
      te += (te != "" ? ", " : "") + en[z] + " " + Share(cnt, nb) + "%";
     }
   W("<h3>" + I2S(rank) + ". " + lab + "</h3><p class='muted'>Quando rompe (primo tocco, dalla fine del range): " + tb + ".<br>Quanto " +
     "corre oltre il lato rotto dal primo tocco, in multipli del range: " + te + ".</p>");
   R(g_repOrb, "  " + I2S(rank) + ". " + lab);
   R(g_repOrb, "     quando rompe: " + tb);
   R(g_repOrb, "     quanto corre dal primo tocco (range): " + te);
   //--- la stessa combinazione con ogni candela di conferma (in grassetto quella della riga in tabella)
   THead("Conferma|Giorni con conferma|Minuti alla conferma (mediana)|Forza: chiude oltre il livello (range)|A favore dalla conferma (range)|" +
         "Contro (range)|% pi&ugrave; a favore che contro (z)|Minuti al massimo a favore|Velocit&agrave; (range all'ora)|" +
         "Volatilit&agrave; (&times; stessa ora)|% ritesta il livello rotto|Segui 1:1 lorda R (z)|Netta peggiore 1:1 R (z)|Costo di pareggio 1:1|" +
         "Operazione migliore (netta peggiore; placebo; pareggio)");
   for(int f = 0; f < g_obNF; f++)
     {
      int c2 = cfg * g_obNF + f, t0 = ObTr(c2, 0, 0), bt = ObBest(c2), tb2 = ObTr(c2, bt, 0);
      W("<tr" + (f == fs ? " style='font-weight:600'" : "") + ">" + TD(ObTf(f)) + TD(I2S(g_ocN[c2]) + " (" + Share(g_ocN[c2], g_osDay[cfg]) + "%)") +
        TD(F(g_ocTc[c2], 0)) + TD(F(g_ocSt[c2], 2)) + TD(F(g_ocMf[c2], 2)) + TD(F(g_ocMa[c2], 2)) +
        TDc(FP(g_ocW[c2], 1) + " (" + ZS(g_ocZc[c2]) + ")", PCol(g_ocZc[c2], 0, 4)) + TD(F(g_ocTm[c2], 0)) + TD(F(g_ocSp[c2], 1)) +
        TDc(F(g_ocVo[c2], 2), PCol(g_ocVo[c2], 1.0, 1.0)) + TD(FP(g_ocRe[c2], 1)) +
        TDc(SgnF(g_otE[t0], 3) + " (" + ZS(g_otZ[t0]) + ")", PCol(g_otZ[t0], 0, 4)) + TD(SgnF(g_otEw[t0], 3) + " (" + ZS(g_otZw[t0]) + ")") +
        TD(BpTxt(g_otBe[t0])) + TD(OB_OP[bt] + " " + SgnF(g_otEw[tb2], 3) + " (" + ZS(g_otZw[tb2]) + "; placebo " + ZS(g_otZp[tb2]) + "; " +
                                   BpTxt(g_otBe[tb2]) + ")") + "</tr>");
      R(g_repOrb, "     conferma " + ObTf(f) + ": " + I2S(g_ocN[c2]) + " giorni con conferma (" + Share(g_ocN[c2], g_osDay[cfg]) + "%) dopo " +
        F(g_ocTc[c2], 0) + " min, forza " + F(g_ocSt[c2], 2) + " range oltre il livello; dalla conferma a favore " + F(g_ocMf[c2], 2) +
        " range, contro " + F(g_ocMa[c2], 2) + " (mediane), piu' a favore che contro " + FP(g_ocW[c2], 1) + "% (z " + ZS(g_ocZc[c2]) +
        "), massimo dopo " + F(g_ocTm[c2], 0) + " min, velocita' " + F(g_ocSp[c2], 1) + " range all'ora, volatilita' " + F(g_ocVo[c2], 2) +
        " volte la stessa ora, ritesta il livello rotto " + FP(g_ocRe[c2], 1) + "%; segui 1:1 lorda " + SgnF(g_otE[t0], 3) + " R (z " + ZS(g_otZ[t0]) +
        "), netta peggiore " + SgnF(g_otEw[t0], 3) + ", pareggio " + BpTxt(g_otBe[t0]) + "; migliore " + OB_OP[bt] + " " + SgnF(g_otEw[tb2], 3) +
        " R (z " + ZS(g_otZw[tb2]) + ", contro il placebo z " + ZS(g_otZp[tb2]) + ")");
     }
   TEnd();
   //--- eventi su ogni candela di conferma (si osserva il prezzo, non si opera): reale e atteso con direzione casuale, orari
   string eh = "";
   for(int k = 0; k < OB_NE; k++)
      eh += "|" + OB_EV[k] + " %" + (g_obRnd ? " (atteso)" : "");
   W("<p class='muted'>Cosa fa il prezzo sulle candele di ogni conferma (colore = differenza dall'atteso con le stesse barre a direzione " +
     "casuale; orari = ora locale di " + MKT_NAME[g_obClk[cs / g_obNS]] + "):</p>");
   THead("Conferma|Giorni" + eh + "|Candele che toccano senza chiudere fuori (al giorno; % giorni con 2 o pi&ugrave;)|Rientri entro 2 candele " +
         "dalla conferma|Ora del rientro (mediana)|Ora in cui riparte o si gira (mediana)");
   R(g_repOrb, "     eventi (reale e atteso con direzione casuale):");
   for(int f = 0; f < g_obNF; f++)
     {
      int c2 = cfg * g_obNF + f;
      string row = "<tr" + (f == fs ? " style='font-weight:600'" : "") + ">" + TD(ObTf(f)) + TD(I2S(g_oeN[c2]));
      for(int k = 0; k < OB_NE; k++)
        {
         int a = c2 * OB_NE + k;
         row += TDc(FP(g_oeS[a], 1) + (g_obRnd ? " (" + FP(g_oeX[a], 1) + ")" : ""), g_obRnd ? PCol(g_oeZ[a], 0, 4) : "");
        }
      W(row + TD(F(g_oeRj[c2], 2) + " (" + FP(g_oeR2[c2], 0) + "%)") + TD(FP(g_oeF[c2], 0) + "%") + TD(ObClk(c2, g_oeTr[c2])) +
        TD(ObClk(c2, g_oeTv[c2])) + "</tr>");
      R(g_repOrb, "       " + ObTf(f) + ": " + ObEvTxt(c2));
     }
   TEnd();
   //--- falsi segnali: conferme su una candela piu' corta che la candela piu' lunga non conferma (entro la finestra)
   if(g_obNF > 1)
     {
      string fh = "";
      for(int f2 = 1; f2 < g_obNF; f2++)
         fh += "|Non confermata su " + ObTf(f2);
      W("<p class='muted'>Falsi segnali: dei giorni con conferma sulla candela della riga, quota senza conferma sulla candela pi&ugrave; " +
        "lunga della colonna entro la finestra.</p>");
      THead("Conferma su" + fh);
      string ft = "";
      for(int f1 = 0; f1 < g_obNF - 1; f1++)
        {
         string row = "<tr>" + TD(ObTf(f1));
         for(int f2 = 1; f2 < g_obNF; f2++)
           {
            double v = g_oxS[(cfg * g_obNF + f1) * g_obNF + f2];
            row += f2 > f1 ? TD(FP(v, 1) + "%") : TD("-");
            if(f2 > f1)
               ft += (ft != "" ? ", " : "") + ObTf(f1) + " senza " + ObTf(f2) + " " + FP(v, 1) + "%";
           }
         W(row + "</tr>");
        }
      TEnd();
      R(g_repOrb, "     falsi segnali (conferma sulla candela corta, non su quella lunga): " + ft);
     }
   //--- tutte le operazioni della conferma scelta
   string hb = "";
   for(int p = 1; p < NPRF; p++)
      hb += "|Netta " + g_cp[p].name + " R (z)";
   W("<p class='muted'>Tutte le operazioni con la conferma " + ObTf(fs) + ":</p>");
   THead("Operazione|Trade|% obiettivo / stop / a tempo|Obiettivo tra i chiusi (atteso con prezzo casuale)|Lorda R (z)|Placebo lordo R|" +
         "Vantaggio sul placebo R (z)" + hb + "|Costo di pareggio|Lorda con costo di " + BpLab() + " (R)|Met&agrave; 1 / met&agrave; 2 lorda|" +
         "Solo rotture al rialzo lorda (z)|Solo al ribasso lorda (z)");
   R(g_repOrb, "     operazioni con la conferma " + ObTf(fs) + ":");
   for(int t = 0; t < OB_NT; t++)
     {
      ObSt q, qu, qd;
      ObStat(i, x, fs, t, 0, q);
      ObStat(i, x, fs, t, 1, qu);
      ObStat(i, x, fs, t, 2, qd);
      int j = t < 4 ? t : t - 4;
      double p0 = OB_K[j] > 0 ? (t < 4 ? 1.0 / (1 + OB_K[j]) : OB_K[j] / (1 + OB_K[j])) : Nan();
      string nets = "", netT = "";
      for(int p = 1; p < NPRF; p++)
        {
         nets += TD(ObNet(i, x, fs, t, 0, p));
         netT += ", netta " + g_cp[p].name + " " + ObNet(i, x, fs, t, 0, p);
        }
      string ev = Share(q.nU, q.n) + " / " + Share(q.nL, q.n) + " / " + Share(q.n - q.nU - q.nL, q.n);
      string ct = OB_K[j] > 0 ? Share(q.nU, q.nU + q.nL) + " (" + FP(p0, 0) + ")" : "-";
      string lv = ObLev(i, x, fs, t, 0), lz = "";
      for(int k2 = 0; k2 < g_bpN; k2++)
        {
         double e2 = 0, z2 = 0;
         ObNetBp(i, x, fs, t, 0, g_bpV[k2], e2, z2);
         lz += (k2 > 0 ? ", " : "") + BpNum(g_bpV[k2]) + " pb z " + ZS(z2);
        }
      W("<tr>" + TD(OB_OP[t]) + TD(I2S(q.n)) + TD(ev) + TD(ct) + TDc(SgnF(q.e, 3) + " (" + ZS(q.z) + ")", PCol(q.z, 0, 4)) + TD(SgnF(q.pl, 3)) +
        TDc(SgnF(q.adv, 3) + " (" + ZS(q.zp) + ")", PCol(q.zp, 0, 4)) + nets + TD(BpTxt(q.be)) + "<td title='" + lz + "'>" + lv + "</td>" +
        TD(SgnF(q.e1, 2) + " / " + SgnF(q.e2, 2)) + TD(SgnF(qu.e, 3) + " (" + ZS(qu.z) + ", N " + I2S(qu.n) + ")") +
        TD(SgnF(qd.e, 3) + " (" + ZS(qd.z) + ", N " + I2S(qd.n) + ")") + "</tr>");
      R(g_repOrb, "     " + OB_OP[t] + ": " + I2S(q.n) + " trade, obiettivo/stop/tempo " + ev + "%, obiettivo tra i chiusi " + ct + "%, lorda " +
        SgnF(q.e, 3) + " R (z " + ZS(q.z) + "), placebo " + SgnF(q.pl, 3) + " R, vantaggio sul placebo " + SgnF(q.adv, 3) + " R (z " + ZS(q.zp) + ")" +
        netT + "; costo di pareggio " + BpTxt(q.be) + ", lorda con costo di " + BpLab() + ": " + lv + " R (" + lz + "); meta' " + SgnF(q.e1, 2) +
        " / " + SgnF(q.e2, 2) + "; solo rialzo " + SgnF(qu.e, 3) + " (z " + ZS(qu.z) + "), solo ribasso " + SgnF(qd.e, 3) + " (z " + ZS(qd.z) + ")");
     }
   TEnd();
   //--- segui 1:1 per giorno della settimana e per ampiezza del range (conferma scelta)
   string wd = "", wa = "";
   for(int g = 0; g < 7; g++)
     {
      ObSt q;
      if(ObStat(i, x, fs, 0, 5 + g, q) && q.n >= 30)
         wd += (wd != "" ? ", " : "") + DOW[g] + " " + SgnF(q.e, 2) + " (z " + ZS(q.z) + ", N " + I2S(q.n) + ")";
     }
   string wn[3] = {"stretto (sotto 0,75 volte la media dei 20 giorni prima)", "normale", "ampio (oltre 1,33 volte)"};
   for(int g = 0; g < 3; g++)
     {
      ObSt q;
      if(ObStat(i, x, fs, 0, 12 + g, q) && q.n >= 30)
         wa += (wa != "" ? ", " : "") + wn[g] + " " + SgnF(q.e, 2) + " (z " + ZS(q.z) + ", N " + I2S(q.n) + ")";
     }
   W("<p class='muted'>Segui 1:1 con la conferma " + ObTf(fs) + ", lorda per giorno (orologio dei dati): " + wd + ".<br>Per ampiezza del range: " +
     wa + ".</p>");
   R(g_repOrb, "     segui 1:1 per giorno: " + wd);
   R(g_repOrb, "     segui 1:1 per ampiezza del range: " + wa);
  }

// tabella delle anomalie (segui 1:1, entrambi i lati; una riga per combinazione e conferma)
void OrbTable(const int &lst[], const int nl, const string title, const string desc)
  {
   SecStart(title, desc);
   THead("#|Ora locale|Orario dei dati (inverno / estate)|Range|Finestra|Conferma|Giorni|% rompe (su / gi&ugrave;)|% tocca l'altro lato|" +
         "% chiude oltre il lato rotto|Evento pi&ugrave; frequente sulle candele di conferma|Giorni con conferma|A favore / contro dalla conferma (range; z)|Minuti al massimo a favore|" +
         "Velocit&agrave; (range all'ora)|Volatilit&agrave; (&times; stessa ora)|Segui 1:1: % obiettivo / stop / a tempo|Lorda 1:1 R (z)|" +
         "Netta peggiore 1:1 R (z)|Costo di pareggio 1:1|Met&agrave; 1 / met&agrave; 2|Operazione migliore (netta del broker peggiore; z contro il " +
         "placebo; pareggio)");
   for(int r = 0; r < nl; r++)
     {
      int cf = lst[r], f = cf % g_obNF, cfg = cf / g_obNF, x = cfg % g_obNW, i = (cfg / g_obNW) % g_obND, cs = cfg / (g_obNW * g_obND);
      int t0 = ObTr(cf, 0, 0), n0 = g_otN[t0], bt = ObBest(cf), tb = ObTr(cf, bt, 0);
      string ev = Share(g_otU[t0], n0) + " / " + Share(g_otL[t0], n0) + " / " + Share(n0 - g_otU[t0] - g_otL[t0], n0);
      double hd = Frac(g_osHd[cfg], g_osBrk[cfg]);
      W("<tr>" + TD(I2S(r + 1)) + TD(ObLoc(cs)) + TD(ObDat(cs)) + TD(I2S(g_obD[i]) + " min") + TD(I2S(g_obW[x]) + " min") + TD(ObTf(f)) +
        TD(I2S(g_osDay[cfg])) + TD(Share(g_osBrk[cfg], g_osDay[cfg]) + " (" + Share(g_osUp[cfg], g_osBrk[cfg]) + " / " +
                                   Share(g_osBrk[cfg] - g_osUp[cfg], g_osBrk[cfg]) + ")") + TD(Share(g_osFl[cfg], g_osBrk[cfg])) +
        TDc(FP(hd, 1), PCol(hd, 0.5, 0.15)) + "<td title='" + ObEvTip(cf) + "'>" + ObEvStack(cf) + ObEvTop(cf) + "</td>" +
        TD(Share(g_ocN[cf], g_osDay[cfg])) + TDc(ObCont(cf), PCol(g_ocZc[cf], 0, 4)) +
        TD(F(g_ocTm[cf], 0)) + TD(F(g_ocSp[cf], 1)) + TD(F(g_ocVo[cf], 2)) + TD(ev) +
        TDc(SgnF(g_otE[t0], 3) + " (" + ZS(g_otZ[t0]) + ")", PCol(g_otZ[t0], 0, 4)) + TD(SgnF(g_otEw[t0], 3) + " (" + ZS(g_otZw[t0]) + ")") +
        TD(BpTxt(g_otBe[t0])) + TD(SgnF(g_otE1[t0], 2) + " / " + SgnF(g_otE2[t0], 2)) +
        TD(OB_OP[bt] + " " + SgnF(g_otEw[tb], 3) + " (" + ZS(g_otZw[tb]) + ")" + (g_otSt[tb] ? "" : "*") + "; placebo " + ZS(g_otZp[tb]) + "; " +
           BpTxt(g_otBe[tb])) + "</tr>");
      R(g_repOrb, "  " + I2S(r + 1) + ". " + ObCfLab(cf) + ", " + I2S(g_osDay[cfg]) + " giorni: rompe " + Share(g_osBrk[cfg], g_osDay[cfg]) + "% (su " +
        Share(g_osUp[cfg], g_osBrk[cfg]) + "%) dopo " + F(g_osBm[cfg], 0) + " min (mediana), tocca l'altro lato " + Share(g_osFl[cfg], g_osBrk[cfg]) +
        "%, chiude oltre il lato rotto " + FP(hd, 1) + "% (atteso 50%), estensione mediana " + F(g_osEx[cfg], 2) + " range; conferma " + ObTf(f) +
        " nel " + Share(g_ocN[cf], g_osDay[cfg]) + "% dei giorni, poi a favore / contro " + ObCont(cf) + ", massimo dopo " + F(g_ocTm[cf], 0) +
        " min, velocita' " + F(g_ocSp[cf], 1) + " range all'ora, volatilita' " + F(g_ocVo[cf], 2) + " volte la stessa ora; segui 1:1 " +
        "obiettivo/stop/tempo " + ev + "%, lorda " + SgnF(g_otE[t0], 3) + " R (z " + ZS(g_otZ[t0]) + "), netta peggiore " + SgnF(g_otEw[t0], 3) +
        " R (z " + ZS(g_otZw[t0]) + "), costo di pareggio " + BpTxt(g_otBe[t0]) + ", meta' " + SgnF(g_otE1[t0], 2) + " / " + SgnF(g_otE2[t0], 2) +
        "; migliore netta: " + OB_OP[bt] + " " + SgnF(g_otEw[tb], 3) + " R (z " + ZS(g_otZw[tb]) + (g_otSt[tb] ? ", stabile" : ", non stabile") +
        ", contro il placebo z " + ZS(g_otZp[tb]) + ", pareggio " + BpTxt(g_otBe[tb]) + ")");
      R(g_repOrb, "     eventi sulle candele " + ObTf(f) + ": " + ObEvTxt(cf));
     }
   TEnd();
   SecEnd();
  }

void OrbTab(CSeries &s, const int barSec, const string clean)
  {
   g_txOrbAll.Clear();
   g_repOrb = "";
   g_obEvTx = "";
   g_orN = 0;
   R(g_repOrb, "=== ORB: ROTTURA DEL RANGE INIZIALE A TUTTI GLI ORARI ===");
   if(!InpOrb)
     {
      SecStart("ORB", "");
      W("<p class='muted'>Disattivato dal parametro 'ORB'.</p>");
      SecEnd();
      R(g_repOrb, "  disattivato dal parametro 'ORB'");
      return;
     }
   int bm = barSec / 60 < 1 ? 1 : barSec / 60;
   g_obBar = barSec;
   g_obStep = MathMax(5, MathMin(240, InpOrbStep));
   g_obNS = 1440 / g_obStep;
   g_obND = OrbList(InpOrbRanges, g_obD, bm, 240);
   g_obNW = OrbList(InpOrbWindows, g_obW, MathMax(5, 2 * bm), 720);
   //--- candele di conferma: divisori dell'ora e multipli della barra dei dati (sul grafico e nel tester si chiudono agli stessi minuti)
   int nf = OrbList(InpOrbConfirm, g_obCf, bm, 60), mf = 0;
   for(int f = 0; f < nf; f++)
      if(g_obCf[f] % bm == 0 && 60 % g_obCf[f] == 0)
         g_obCf[mf++] = g_obCf[f];
   if(mf == 0)
     {
      ArrayResize(g_obCf, 1);
      g_obCf[0] = bm;
      mf = 1;
     }
   g_obNF = mf;
   ArrayResize(g_obCf, g_obNF);
   ArrayResize(g_obCs, g_obNF);
   for(int f = 0; f < g_obNF; f++)
      g_obCs[f] = g_obCf[f] * 60;
   if(s.n < 5000 || g_obND == 0 || g_obNW == 0)
     {
      SecStart("ORB", "");
      W("<p class='muted'>" + (s.n < 5000 ? "Servono dati M1 o M5." : "Controlla i parametri 'ORB: durate' e 'ORB: finestre' (minuti separati da virgola).") + "</p>");
      SecEnd();
      R(g_repOrb, "  non calcolato (servono dati M1 o M5 e durate e finestre valide)");
      return;
     }
   g_obMaxW = g_obW[g_obNW - 1];
   //--- orologi: la piazza di riferimento e le altre regole dell'ora legale (USA = New York, Europa = Londra, nessuna = Tokyo)
   int ref = g_ref >= 0 ? g_ref : 0;
   g_obNC = 0;
   g_obClk[g_obNC++] = ref;
   if(InpOrbAllClocks)
     {
      if(ref != 0)
         g_obClk[g_obNC++] = 0;
      if(ref != 1 && ref != 2)
         g_obClk[g_obNC++] = 1;
      if(ref != 3)
         g_obClk[g_obNC++] = 3;
     }
   int ncs = g_obNC * g_obNS, ncf = ncs * g_obND * g_obNW, ncc = ncf * g_obNF, ntr = ncc * OB_NT * 3;
   int nbf = g_obND * g_obNW * g_obNF;
   ArrayResize(g_obKW, g_obNW);
   ArrayResize(g_obOk, g_obNW);
   ArrayResize(g_obA, nbf * OB_NT * OB_NB * OB_NF);
   ArrayResize(g_obE, nbf * OB_NT * 3 * 2);
   ArrayResize(g_obS, g_obND * g_obNW * 5);
   ArrayResize(g_obHb, g_obND * g_obNW * (g_obMaxW + 1));
   ArrayResize(g_obHx, g_obND * g_obNW * OB_NX);
   ArrayResize(g_ocA, nbf * OB_NCA);
   ArrayResize(g_ohMf, nbf * OB_NX); ArrayResize(g_ohMa, nbf * OB_NX); ArrayResize(g_ohSt, nbf * OB_NX);
   ArrayResize(g_ohSp, nbf * OB_NX); ArrayResize(g_ohVo, nbf * OB_NX);
   ArrayResize(g_ohTc, nbf * (g_obMaxW + 1)); ArrayResize(g_ohTm, nbf * (g_obMaxW + 1));
   ArrayResize(g_ofD, g_obNF); ArrayResize(g_ofQe, g_obNF); ArrayResize(g_ofQm, g_obNF); ArrayResize(g_ofVn, g_obNF);
   ArrayResize(g_ofEp, g_obNF); ArrayResize(g_ofNu, g_obNF); ArrayResize(g_ofNl, g_obNF); ArrayResize(g_ofMfe, g_obNF);
   ArrayResize(g_ofMae, g_obNF); ArrayResize(g_ofStr, g_obNF); ArrayResize(g_ofVp, g_obNF); ArrayResize(g_ofVb, g_obNF);
   ArrayResize(g_ofRe, g_obNF);
   ArrayResize(g_ofR, g_obNF * 4); ArrayResize(g_ofRx, g_obNF * 4); ArrayResize(g_ofMrx, g_obNF * 4);
   ArrayResize(g_ofRes, g_obNF * 4); ArrayResize(g_ofRq, g_obNF * 4); ArrayResize(g_ofMres, g_obNF * 4);
   ArrayResize(g_ofPh, g_obNF); ArrayResize(g_ofFin, g_obNF); ArrayResize(g_ofRj, g_obNF); ArrayResize(g_ofN1, g_obNF);
   ArrayResize(g_ofRc, g_obNF); ArrayResize(g_ofQr, g_obNF); ArrayResize(g_ofQv, g_obNF); ArrayResize(g_ofTu, g_obNF); ArrayResize(g_ofTd, g_obNF);
   ArrayResize(g_oeA, nbf * OB_NEA); ArrayResize(g_oeB, nbf * OB_NEA);
   ArrayResize(g_ohRt, nbf * (g_obMaxW + 1)); ArrayResize(g_ohEt, nbf * (g_obMaxW + 1));
   ArrayResize(g_oxA, g_obND * g_obNW * g_obNF * g_obNF);
   g_ovNO = (g_obD[g_obND - 1] + g_obMaxW) * 60 / g_obBar + 1;
   ArrayResize(g_ovDay, g_ovNO); ArrayResize(g_ovRing, 20 * g_ovNO); ArrayResize(g_ovSum, g_ovNO); ArrayResize(g_ovCnt, g_ovNO);
   ArrayResize(g_osKey, ncs);
   ArrayResize(g_osDup, ncs);
   ArrayResize(g_osDay, ncf); ArrayResize(g_osBrk, ncf); ArrayResize(g_osUp, ncf); ArrayResize(g_osFl, ncf); ArrayResize(g_osHd, ncf);
   ArrayResize(g_osBm, ncf); ArrayResize(g_osEx, ncf);
   ArrayResize(g_ocN, ncc); ArrayResize(g_ocTc, ncc); ArrayResize(g_ocSt, ncc); ArrayResize(g_ocMf, ncc); ArrayResize(g_ocMa, ncc);
   ArrayResize(g_ocZc, ncc); ArrayResize(g_ocW, ncc); ArrayResize(g_ocTm, ncc); ArrayResize(g_ocSp, ncc); ArrayResize(g_ocVo, ncc);
   ArrayResize(g_ocRe, ncc);
   ArrayResize(g_oeS, ncc * OB_NE); ArrayResize(g_oeX, ncc * OB_NE); ArrayResize(g_oeZ, ncc * OB_NE); ArrayResize(g_oeN, ncc);
   ArrayResize(g_oeR2, ncc); ArrayResize(g_oeRj, ncc); ArrayResize(g_oeF, ncc); ArrayResize(g_oeTr, ncc); ArrayResize(g_oeTv, ncc);
   ArrayResize(g_oxS, ncf * g_obNF * g_obNF);
   g_obRnd = InpOrbRandom;
   ArrayResize(g_otN, ntr); ArrayResize(g_otU, ntr); ArrayResize(g_otL, ntr); ArrayResize(g_otE, ntr); ArrayResize(g_otZ, ntr);
   ArrayResize(g_otE1, ntr); ArrayResize(g_otE2, ntr); ArrayResize(g_otEw, ntr); ArrayResize(g_otZw, ntr); ArrayResize(g_otSt, ntr);
   ArrayResize(g_otP, ntr); ArrayResize(g_otZp, ntr); ArrayResize(g_otBe, ntr);
   //--- giorni con dati (almeno 4 ore di barre): un orario coperto in meno della meta' di questi giorni cade a mercato chiuso (o la
   //--- finestra supera la chiusura) quasi sempre; i pochi giorni rimasti (cambio d'ora sfasato, festivi) non lo rappresentano
   int nDay = 0, nb0 = 0;
   long dPrev = -1;
   for(int q = 0; q <= s.n; q++)
     {
      long dk = q < s.n ? (long)s.t[q] / 86400 : -2;
      if(dk != dPrev)
        {
         if(dPrev >= 0 && nb0 * barSec >= 4 * 3600)
            nDay++;
         dPrev = dk;
         nb0 = 0;
        }
      nb0++;
     }
   g_obMinDay = nDay / 2 > 30 ? nDay / 2 : 30;
   //--- orario dei dati di ogni inizio il 15 gennaio e il 15 luglio dell'ultimo anno completo (per riconoscere gli orari equivalenti)
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
   for(int cs = 0; cs < ncs; cs++)
     {
      int mk = g_obClk[cs / g_obNS], mn = (cs % g_obNS) * g_obStep;
      g_osKey[cs] = MinOfDay(LocalToData(dayA, mk, mn)) * 1440 + MinOfDay(LocalToData(dayB, mk, mn));
      g_osDup[cs] = false;
      for(int z = 0; z < (cs / g_obNS) * g_obNS && !g_osDup[cs]; z++)
         if(g_osKey[z] == g_osKey[cs])
            g_osDup[cs] = true;
     }
   //--- durata e finestra di riferimento per la tabella di tutti gli orari: la durata piu' vicina a 'Sessioni: minuti del range', la finestra di mezzo
   int iRef = 0, xRef = g_obNW / 2;
   for(int i = 1; i < g_obND; i++)
      if(MathAbs(g_obD[i] - InpORMinutes) < MathAbs(g_obD[iRef] - InpORMinutes))
         iRef = i;
   //--- CSV di tutte le combinazioni (una riga per combinazione, conferma e operazione)
   string csvName = "MarketProfiler_" + clean + "_orb.csv";
   g_obCsv = FileOpen(csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | (InpCommonDir ? FILE_COMMON : 0));
   bool csvOk = g_obCsv != INVALID_HANDLE;
   string csvPath = (InpCommonDir ? TerminalInfoString(TERMINAL_COMMONDATA_PATH) : TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5") + "\\Files\\" + csvName;
   string evh = "";
   for(int k = 0; k < OB_NE; k++)
      evh += "% " + OB_EVS[k] + ";% " + OB_EVS[k] + " atteso;z " + OB_EVS[k] + ";";
   evh += "Candele che toccano senza chiudere fuori (al giorno);% giorni con 2 o piu;% rientri entro 2 candele;Minuti al rientro (mediana);" +
          "Minuti a riparte o si gira (mediana);";
   if(g_obCsv != INVALID_HANDLE)
     {
      string hd = "Piazza;Ora locale;Orario dati inverno;Orario dati estate;Range min;Finestra min;Conferma;Giorni;% rompe;% rompe al rialzo;" +
                  "Minuti alla rottura (mediana);% tocca l'altro lato;% chiude oltre il lato rotto;Estensione mediana (range);% giorni con conferma;" +
                  "Minuti alla conferma (mediana);Forza della conferma (range oltre il livello);A favore dalla conferma (range, mediana);" +
                  "Contro dalla conferma (range, mediana);% piu a favore che contro;z a favore - contro;Minuti al massimo a favore (mediana);" +
                  "Velocita (range all'ora);Volatilita (volte la stessa ora);% ritesta il livello rotto;" + evh + "Operazione;Trade;" +
                  "% obiettivo;% stop;% a tempo;% vinti;Lorda R;z lorda;Meta 1 lorda R;Meta 2 lorda R;Solo rialzo trade;Solo rialzo lorda R;" +
                  "z solo rialzo;Solo ribasso trade;Solo ribasso lorda R;z solo ribasso";
      for(int p = 1; p < NPRF; p++)
         hd += ";Netta " + Plain(g_cp[p].name) + " R;z " + Plain(g_cp[p].name);
      hd += ";Coperto (giorni >= " + I2S(g_obMinDay) + ");Placebo lordo R;Vantaggio sul placebo R;z vs placebo;Costo di pareggio pb";
      for(int j = 0; j < g_bpN; j++)
         hd += ";Lorda a " + BpNum(g_bpV[j]) + " pb R;z a " + BpNum(g_bpV[j]) + " pb";
      FileWriteString(g_obCsv, hd + "\n");
     }
   long d0 = (long)s.t[0] / 86400 - 1, d1 = (long)s.t[s.n - 1] / 86400 + 1;
   datetime tMid = (datetime)((long)s.t[0] + ((long)s.t[s.n - 1] - (long)s.t[0]) / 2);
   string heat[3];
   string evRows = "", evM = "", clk = "";
   for(int c = 0; c < g_obNC; c++)
      clk += (c > 0 ? ", " : "") + MKT_NAME[g_obClk[c]];
   string lists = "", wl = "", cl = "";
   for(int i = 0; i < g_obND; i++)
      lists += (i > 0 ? ", " : "") + I2S(g_obD[i]);
   for(int x = 0; x < g_obNW; x++)
      wl += (x > 0 ? ", " : "") + I2S(g_obW[x]);
   for(int f = 0; f < g_obNF; f++)
      cl += (f > 0 ? ", " : "") + ObTf(f);
   R(g_repOrb, "Metodo: per ogni orario di inizio (ogni " + I2S(g_obStep) + " minuti di tutta la giornata, nell'ora locale di " + clk + ", convertita " +
     "giorno per giorno nell'orologio dei dati), range iniziale di " + lists + " minuti, finestre di " + wl + " minuti dopo la fine del range. " +
     "Rottura = primo tocco oltre il massimo o il minimo del range (su candele M1, percorso dentro la candela come il tester: rialzista " +
     "apertura-minimo-massimo-chiusura, ribassista apertura-massimo-minimo-chiusura). Conferma = chiusura della prima candela " + cl + " fuori " +
     "dal range (candele allineate all'orologio come sul grafico; la candela conta se chiude dopo la fine del range). Operazione = entrata alla " +
     "chiusura di conferma (non al tocco: con i soli dati M1 il prezzo esatto del tocco non si conosce e un ordine stop riempito sul livello " +
     "darebbe un vantaggio finto); stop all'altro lato del range o a meta'; obiettivo 1 o 2 volte il rischio o chiusura a fine finestra; fade = " +
     "la stessa operazione al contrario. Con un prezzo casuale l'aspettativa e' zero e 'arriva prima a +1R' e' il 50%: z = distanza da zero in " +
     "deviazioni standard (un trade al giorno, giorni indipendenti). Netta = con spread per ora, commissione, slittamento e swap dei broker; " +
     "netta peggiore = il broker con il risultato piu' basso. Placebo = la stessa operazione nello stesso istante e allo stesso prezzo con " +
     "direzione a caso (media tra lei e la direzione opposta con le stesse distanze di stop e obiettivo): misura cio' che rende il solo momento " +
     "(volatilita', trend in entrambi i sensi, esecuzione nella barra); vantaggio sul placebo = operazione - placebo, z sulle differenze giorno " +
     "per giorno: e' la parte che dipende dalla direzione della rottura (per segui 1:1 coincide con lo z contro zero). Continuazione dalla " +
     "chiusura di conferma fino a fine finestra: a favore = massima estensione nella direzione della rottura, contro = massima estensione " +
     "contraria, in multipli del range (con direzione a caso le due si equivalgono: z della differenza giorno per giorno = placebo); minuti al " +
     "massimo a favore; forza = quanto la candela di conferma chiude oltre il livello (range); velocita' = estensione a favore all'ora fino al " +
     "massimo; volatilita' = range delle barre dopo la conferma diviso il range delle stesse barre (stesso minuto) nei 20 giorni validi " +
     "precedenti; ritesta = il prezzo torna al livello rotto. Eventi (si osserva il prezzo, non si opera), per ogni candela di conferma: " +
     "nessun tocco; solo tocchi (candele oltre il livello che chiudono dentro: rottura non confermata); chiude fuori e continua; chiude " +
     "fuori, rientra (una candela richiude dentro il range) e resta dentro; rientra e riparte (richiude fuori dallo stesso lato); rientra e " +
     "si gira (chiude fuori dall'altro lato); atteso = stesse barre con direzione casuale" + (g_obRnd ? "" : " (disattivato)") + "; " +
     "falsi segnali = conferme sulla candela corta che la candela piu' lunga non conferma. Costo di pareggio = costo per trade in punti base del " +
     "prezzo (1 pb = 0,01%) che azzera l'aspettativa lorda; lorda a " + BpLab() + " = aspettativa con quel costo per trade (" + CostBpTxt() +
     "). Orari coperti in meno di " + I2S(g_obMinDay) + " giorni (meta' dei giorni con dati: mercato chiuso o finestra oltre la chiusura) sono " +
     "esclusi da tabelle, riepilogo e regole (restano nel CSV). Orari equivalenti (stesso orario dei dati a gennaio e a luglio, per esempio " +
     "NY 09:30 e LDN 14:30: cambiano solo nelle settimane in cui l'ora legale cambia in date diverse) sono mostrati una volta sola. " + RollTxt());
   int tot = ncs, done = 0;
   for(int c = 0; c < g_obNC && !IsStopped(); c++)
     {
      heat[c] = "";
      for(int sI = 0; sI < g_obNS && !IsStopped(); sI++)
        {
         if(done % 8 == 0)
            Comment("MarketProfiler: ORB ", MKT_SHORT[g_obClk[c]], " ", HM(sI * g_obStep), " (", I2S(done * 100 / tot), "%) ...");
         done++;
         if(g_obRnd)
           {
            //--- prima le stesse barre con direzione casuale: gli eventi attesi restano in g_oeB
            OrbSim(s, c, sI, d0, d1, g_obSim);
            OrbScan(g_obSim, c, sI, d0, d1, tMid);
            ArrayCopy(g_oeB, g_oeA);
           }
         else
            ArrayInitialize(g_oeB, 0.0);
         OrbScan(s, c, sI, d0, d1, tMid);
         OrbStore(c, sI, iRef, xRef, heat[c], evRows, evM);
        }
     }
   g_obSim.Free();
   if(g_obCsv != INVALID_HANDLE)
     {
      FileClose(g_obCsv);
      g_obCsv = INVALID_HANDLE;
      PrintFormat("[MarketProfiler] ORB: tutte le combinazioni salvate in %s", csvPath);
     }
   //--- anomalie: segui 1:1 entrambi i lati, almeno 100 trade; per orario dei dati e durata del range solo il risultato con |z| piu' alto
   //--- (tra finestre e conferme)
   double key[];
   ArrayResize(key, ncc);
   int nk = 0;
   for(int cf = 0; cf < ncc; cf++)
     {
      int t0 = ObTr(cf, 0, 0);
      if(g_otN[t0] >= 100 && g_osDay[cf / g_obNF] >= g_obMinDay && MathIsValidNumber(g_otZ[t0]))
         key[nk++] = MathFloor(MathMin(MathAbs(g_otZ[t0]), 999.0) * 1000.0) * 16777216.0 + cf;
     }
   ArrayResize(key, nk);
   ArraySort(key);
   int lp[], ln[];
   int top = 20, np = 0, nn = 0;
   ArrayResize(lp, top);
   ArrayResize(ln, top);
   for(int j = nk - 1; j >= 0 && (np < top || nn < top); j--)
     {
      int cf = (int)((long)key[j] % 16777216), cfg = cf / g_obNF, i = (cfg / g_obNW) % g_obND, cs = cfg / (g_obNW * g_obND);
      bool pos = g_otZ[ObTr(cf, 0, 0)] > 0;
      if((pos && np >= top) || (!pos && nn >= top))
         continue;
      bool seen = false;
      int m = pos ? np : nn;
      for(int z = 0; z < m && !seen; z++)
        {
         int o = (pos ? lp[z] : ln[z]) / g_obNF;
         int oi = (o / g_obNW) % g_obND, ocs = o / (g_obNW * g_obND);
         seen = oi == i && g_osKey[ocs] == g_osKey[cs];
        }
      if(seen)
         continue;
      if(pos)
         lp[np++] = cf;
      else
         ln[nn++] = cf;
     }
   //--- regole per lo Strategy Tester: netta del broker peggiore, stabile nelle due meta', una per orario dei dati e durata del range
   ArrayResize(key, ntr);
   nk = 0;
   for(int tr = 0; tr < ntr; tr++)
      if(g_otN[tr] >= 100 && g_osDay[tr / (3 * OB_NT) / g_obNF] >= g_obMinDay && g_otSt[tr] && MathIsValidNumber(g_otZw[tr]) && g_otEw[tr] > 0 &&
         g_otZw[tr] >= InpOrbRuleZ)
         key[nk++] = MathFloor(MathMin(g_otZw[tr], 999.0) * 1000.0) * 16777216.0 + tr;
   ArrayResize(key, nk);
   ArraySort(key);
   ArrayResize(g_orX, MathMax(0, InpOrbRules));
   for(int j = nk - 1; j >= 0 && g_orN < InpOrbRules; j--)
     {
      int tr = (int)((long)key[j] % 16777216), cfg = tr / (3 * OB_NT) / g_obNF, i = (cfg / g_obNW) % g_obND, cs = cfg / (g_obNW * g_obND);
      bool seen = false;
      for(int z = 0; z < g_orN && !seen; z++)
        {
         int o = g_orX[z] / (3 * OB_NT) / g_obNF;
         seen = (o / g_obNW) % g_obND == i && g_osKey[o / (g_obNW * g_obND)] == g_osKey[cs];
        }
      if(!seen)
         g_orX[g_orN++] = tr;
     }
   int nCand = nk;
   //--- pagina
   string br = "";
   for(int p = 1; p < NPRF; p++)
      br += (p > 1 ? " e " : "") + g_cp[p].name;
   SecStart("ORB a tutti gli orari: come si legge",
            "Nessun orario scelto prima: il range iniziale (ORB) &egrave; misurato a <b>ogni orario di inizio</b>, ogni " + I2S(g_obStep) +
            " minuti di tutta la giornata, nell'ora locale di " + clk + " (convertita giorno per giorno: ora legale USA, europea e nessuna), " +
            "con range di " + lists + " minuti, finestre di " + wl + " minuti dopo la fine del range e candele di conferma " + cl + ": " +
            I2S(ncf) + " combinazioni, " + I2S(ncc) + " con le conferme, " + I2S(ntr) + " con operazioni e lati. <b>Rottura</b> = primo tocco " +
            "oltre il massimo o il minimo del range. <b>Quando rompe</b> = minuti dalla fine del range. <b>Tocca l'altro lato</b> = rottura " +
            "falsa: dopo la rottura il prezzo arriva anche all'altro lato. <b>Chiude oltre</b> = a fine finestra il prezzo &egrave; oltre il lato " +
            "rotto (con un prezzo casuale il 50%). <b>Conferma</b> = la prima candela " + cl + " che <b>chiude</b> fuori dal range (candele " +
            "allineate all'orologio come sul grafico: M15 chiude ai minuti 00, 15, 30, 45; conta se chiude dopo la fine del range). " +
            "<b>Operazione</b>: entrata alla chiusura di conferma (non al tocco: con i soli dati M1 il prezzo esatto del tocco non si conosce e " +
            "un ordine stop riempito proprio sul livello darebbe un vantaggio finto, da +0,02 a +0,07 R su prezzi casuali); stop all'altro lato " +
            "del range o a met&agrave;; obiettivo 1 o 2 volte il rischio o chiusura a fine finestra; <b>fade</b> = la stessa operazione al " +
            "contrario (vende la rottura al rialzo). Con un prezzo casuale l'aspettativa &egrave; zero e 'segui 1:1' arriva prima " +
            "all'obiettivo nel 50% dei trade chiusi: <b>z</b> = distanza da zero in deviazioni standard (un trade al giorno). Netta = spread " +
            "per ora, commissione, slittamento e swap di " + br + "; netta peggiore = il broker con il risultato pi&ugrave; basso. " +
            "Stop e obiettivi sono eseguiti al prezzo esatto: lo slittamento reale degli stop &egrave; nel parametro di ogni broker. " +
            "<b>Dopo la conferma</b>: <b>a favore</b> = quanto il prezzo si spinge nella direzione della rottura dalla chiusura di conferma " +
            "fino a fine finestra, <b>contro</b> = quanto si spinge nella direzione opposta (mediane, in multipli del range): con una " +
            "direzione a caso le due si equivalgono, quindi il <b>z di a favore meno contro</b> (giorno per giorno) &egrave; il confronto " +
            "con il placebo di quanto continua. <b>Minuti al massimo</b> = quando arriva il punto pi&ugrave; lontano a favore. " +
            "<b>Intensit&agrave;</b>: <b>forza</b> = quanto la candela di conferma chiude oltre il livello (range) e <b>velocit&agrave;</b> = " +
            "estensione a favore all'ora fino al massimo. <b>Volatilit&agrave;</b> = range delle barre dopo la conferma diviso il range delle " +
            "stesse barre (stesso minuto dall'inizio) nei 20 giorni validi precedenti: oltre 1 = pi&ugrave; mosso del solito a quell'ora. " +
            "<b>Ritesta</b> = il prezzo torna al livello rotto (anche senza chiudere dentro). <b>Eventi</b>: oltre ai trade, per ogni " +
            "candela di conferma si osserva cosa fa il prezzo (solo tocchi senza chiusura fuori, chiude fuori e continua, rientra e resta, " +
            "riparte o si gira; spiegazione nella sezione degli eventi a ogni orario) contro l'atteso con le stesse barre a direzione casuale, " +
            "e quante conferme sulle candele corte non sono confermate da quelle lunghe (falsi segnali, nel dettaglio). " +
            "<b>Placebo</b> dei trade = la stessa operazione nello stesso istante e allo stesso prezzo ma con direzione a caso (media tra lei e " +
            "la direzione opposta, con le stesse distanze di stop e obiettivo): &egrave; quello che rende il solo momento, senza sapere da che " +
            "parte &egrave; uscito il prezzo (volatilit&agrave;, trend in entrambi i sensi, esecuzione dentro la barra). <b>Vantaggio sul " +
            "placebo</b> = operazione meno placebo, con z calcolato sulle differenze giorno per giorno: &egrave; la parte che dipende davvero " +
            "dalla direzione della rottura. Per 'segui 1:1' stop e obiettivo sono alla stessa distanza e il placebo &egrave; zero: il suo z " +
            "contro zero &egrave; gi&agrave; il confronto con il placebo. <b>Costo di pareggio</b> = il costo per trade (spread + commissione " +
            "+ slittamento), in punti base del prezzo (1 pb = 0,01%), che porta a zero l'aspettativa lorda; accanto, l'aspettativa con un " +
            "costo di " + BpLab() + " (" + CostBpTxt() + "). Un vantaggio con pareggio sotto il costo del broker non &egrave; operabile. " +
            "<b>Copertura</b>: gli orari coperti in meno di " + I2S(g_obMinDay) + " giorni (met&agrave; dei giorni con dati) cadono quasi " +
            "sempre a mercato chiuso o con la finestra oltre la chiusura: sono esclusi da tabelle, riepilogo e regole (&middot; nella mappa) " +
            "e restano nel CSV. " +
            "<b>Attenzione ai confronti multipli</b>: su migliaia di combinazioni correlate (ogni conferma in pi&ugrave; moltiplica i confronti) " +
            "molte superano |z| 2 per caso; conta ci&ograve; che &egrave; stabile nelle due met&agrave;, ritorna a orari, durate e conferme " +
            "vicini e resta positivo con i costi. Orari equivalenti (stesso orario dei dati a gennaio e a luglio, per esempio NY 09:30 e LDN " +
            "14:30, diversi solo nelle settimane del cambio d'ora sfasato) sono mostrati una volta. Tutte le combinazioni sono nel CSV " +
            (csvOk ? "<b>" + csvPath + "</b>" : "(non creato)") + ". Il testo &egrave; in Testi &rarr; ORB.");
   SecEnd();
   R(g_repOrb, "");
   R(g_repOrb, "[Dove la rottura prosegue piu' del caso (segui la rottura): segui 1:1 entrambi i lati, ordinati per z lordo]");
   OrbTable(lp, np, "Dove la rottura prosegue pi&ugrave; del caso (segui la rottura)",
           "Le combinazioni in cui, dopo la chiusura di conferma fuori dal range, il prezzo arriva a +1R prima dell'altro lato pi&ugrave; spesso " +
           "del 50% (segui 1:1, entrambi i lati, almeno 100 trade), ordinate per z. Un risultato per orario dei dati e durata del range (la " +
           "finestra e la conferma con lo z pi&ugrave; alto; le altre conferme sono nel dettaglio). Ultima colonna: l'operazione con lo z netto " +
           "del broker peggiore pi&ugrave; alto per quella combinazione (* = segno diverso in una delle due met&agrave;).");
   R(g_repOrb, "");
   R(g_repOrb, "[Dove la rottura fallisce piu' del caso (fade): segui 1:1 entrambi i lati, ordinati per z lordo]");
   OrbTable(ln, nn, "Dove la rottura fallisce pi&ugrave; del caso (fade)",
           "Le combinazioni in cui, dopo la chiusura di conferma fuori dal range, il prezzo torna all'altro lato prima di arrivare a +1R " +
           "pi&ugrave; spesso del 50%: qui la rottura &egrave; spesso falsa e conviene l'operazione contraria (fade). Stesse colonne della " +
           "tabella sopra.");
   SecStart("Dettaglio delle anomalie pi&ugrave; forti",
            "Per le prime 5 di ogni tabella: quando rompe, quanto corre, la stessa combinazione con ogni candela di conferma (quanto continua, " +
            "intensit&agrave;, volatilit&agrave;, trade), tutte le operazioni della conferma in tabella (lordo, placebo, netto per broker, " +
            "costi, due met&agrave;, lati) e segui 1:1 per giorno e per ampiezza del range rispetto ai 20 giorni precedenti.");
   R(g_repOrb, "");
   R(g_repOrb, "[Dettaglio delle anomalie piu' forti]");
   int rank = 0;
   for(int r = 0; r < 5 && r < np && !IsStopped(); r++)
      OrbDetail(s, lp[r], ++rank, d0, d1, tMid);
   for(int r = 0; r < 5 && r < nn && !IsStopped(); r++)
      OrbDetail(s, ln[r], ++rank, d0, d1, tMid);
   SecEnd();
   string eh = "";
   for(int f = 1; f < g_obNF; f++)
      eh += "|Conferma " + ObTf(f) + ": lorda 1:1 R (z) &middot; a favore / contro (range; z)";
   SecStart("Cosa capita a ogni orario (" + MKT_NAME[g_obClk[0]] + ", range " + I2S(g_obD[iRef]) + " min, finestra " + I2S(g_obW[xRef]) + " min)",
            "Tutti gli orari di inizio della giornata con la stessa durata del range e la stessa finestra: quale evento capita pi&ugrave; spesso " +
            "a ogni orario. Chiude oltre: blu = pi&ugrave; del 50% (la rottura tiene), rosso = meno. Lorda 1:1: colore = z. Le colonne della " +
            "conferma " + ObTf(0) + " sono complete; per le altre conferme: aspettativa lorda 'segui 1:1' e quanto va a favore e contro dopo la " +
            "conferma. Le altre durate e finestre sono nella mappa sotto e nel CSV.");
   THead("Ora locale|Orario dei dati (inverno / estate)|Giorni|% rompe (su / gi&ugrave;)|Minuti alla rottura|% tocca l'altro lato|" +
         "% chiude oltre il lato rotto|Estensione mediana (range)|Conferma " + ObTf(0) + ": segui 1:1 % obiettivo / stop / a tempo|Lorda 1:1 R (z)|" +
         "Netta peggiore 1:1 R (z)|Costo di pareggio 1:1|A favore / contro dalla conferma (range; z)|Operazione migliore (netta peggiore; z " +
         "contro il placebo)" + eh);
   W(evRows);
   TEnd();
   SecEnd();
   string lg = "<div class='lg'>";
   for(int k = 0; k < OB_NE; k++)
      lg += "<b style='background:" + OB_EVC[k] + "'></b>" + OB_EV[k];
   lg += "</div>";
   string mh = "Ora locale|Orario dei dati (inverno / estate)|Giorni";
   for(int f = 0; f < g_obNF; f++)
      mh += "|Candele " + ObTf(f);
   SecStart("Eventi sulle candele di conferma a ogni orario (" + MKT_NAME[g_obClk[0]] + ", range " + I2S(g_obD[iRef]) + " min, finestra " +
            I2S(g_obW[xRef]) + " min)",
            "Qui non si opera: si guarda cosa fa il prezzo attorno ai livelli del range, candela per candela, su ogni timeframe di conferma. " +
            "Ogni giorno finisce in uno di sei eventi: <b>nessun tocco</b> (il prezzo resta nel range); <b>solo tocchi</b> (una o pi&ugrave; " +
            "candele passano oltre il massimo o il minimo ma chiudono dentro: rottura non confermata); <b>chiude fuori e continua</b> (una " +
            "candela chiude oltre il livello e nessuna candela successiva richiude dentro il range); <b>rientra e resta dentro</b> (dopo la " +
            "chiusura fuori una candela richiude dentro e il prezzo resta nel range fino a fine finestra); <b>rientra e riparte</b> (dopo il " +
            "rientro chiude di nuovo fuori dallo stesso lato); <b>rientra e si gira</b> (dopo il rientro chiude fuori dall'altro lato: falsa " +
            "rottura e inversione). Sulle candele corte (M1) le chiusure fuori capitano spesso anche quando il prezzo solo passa oltre il " +
            "livello: il confronto con le candele pi&ugrave; lunghe mostra quali chiusure erano falsi segnali. Ogni cella: barra con le sei " +
            "quote e l'evento pi&ugrave; frequente" + (g_obRnd ? " con tra parentesi la quota attesa ricostruendo gli stessi giorni con le " +
                    "stesse barre ma con la direzione di ogni barra estratta a caso (stessa volatilit&agrave; minuto per minuto); colore = z " +
                    "della differenza (blu = pi&ugrave; dell'atteso, rosso = meno; calcolato solo se l'evento ha almeno 5 casi attesi)" : "") +
            ". Passa sopra una cella per tutte le quote, le " +
            "candele che toccano senza chiudere, i rientri subito (entro 2 candele) e l'ora del rientro e dell'evento finale. Le altre " +
            "durate e finestre sono nel CSV." + lg);
   THead(mh);
   W(evM);
   TEnd();
   SecEnd();
   string hh = "Ora locale|Orario dei dati";
   for(int i = 0; i < g_obND; i++)
      for(int x = 0; x < g_obNW; x++)
         hh += "|" + I2S(g_obD[i]) + "&rarr;" + I2S(g_obW[x]);
   for(int c = 0; c < g_obNC; c++)
     {
      SecStart("Mappa: " + MKT_NAME[g_obClk[c]] + (c == 0 ? "" : " (orologio con un'altra ora legale)"),
               "Ogni cella: range &rarr; finestra (minuti), conferma " + ObTf(0) + ". Numero = % dei trade 'segui 1:1' che arrivano prima " +
               "all'obiettivo che allo stop (atteso 50); colore = z dell'aspettativa lorda (blu = la rottura prosegue, rosso = fallisce); " +
               "&middot; = orario coperto in meno di " + I2S(g_obMinDay) + " giorni (escluso). Passa sopra una cella per i dettagli.");
      if(c > 0)
         W("<details><summary class='muted'>Mostra la mappa</summary>");
      THead(hh);
      W(heat[c]);
      TEnd();
      if(c > 0)
         W("</details>");
      SecEnd();
      heat[c] = "";
     }
   R(g_repOrb, "");
   R(g_repOrb, "[Cosa capita a ogni orario (" + MKT_NAME[g_obClk[0]] + "), range " + I2S(g_obD[iRef]) + " min, finestra " + I2S(g_obW[xRef]) +
     " min: rompe (su), minuti alla rottura, tocca l'altro lato, chiude oltre il lato rotto (atteso 50%), estensione, segui 1:1 e continuazione " +
     "per ogni conferma]");
   g_repOrb += g_obEvTx;
   g_obEvTx = "";
   R(g_repOrb, "");
   R(g_repOrb, "Combinazioni: " + I2S(ncf) + " (" + I2S(ncc) + " con le conferme " + cl + ", " + I2S(ntr) + " con operazioni e lati); candidate a " +
     "regola (netta peggiore con z >= " + F(InpOrbRuleZ, 1) + ", stabile, almeno 100 trade): " + I2S(nCand) + ", esportate " + I2S(g_orN) +
     " (una per orario e durata). CSV: " + csvPath);
   PrintFormat("[MarketProfiler] ORB: %d combinazioni (%d con le conferme), %d candidate a regola, %d esportate", ncf, ncc, nCand, g_orN);
  }

// regole ORB nel file dell'EA (chiamata da RRTab prima di chiudere il file delle regole)
void OrbRulesWrite(void)
  {
   for(int r = 0; r < g_orN; r++)
     {
      int tr = g_orX[r], sd = tr % 3, t = (tr / 3) % OB_NT, cf = tr / (3 * OB_NT), f = cf % g_obNF, cfg = cf / g_obNF;
      int x = cfg % g_obNW, i = (cfg / g_obNW) % g_obND, cs = cfg / (g_obNW * g_obND);
      int j = t < 4 ? t : t - 4, id = ++g_ruN;
      g_ruReal++;
      string ctx = ObLoc(cs) + " (dati " + ObDat(cs) + "), range " + I2S(g_obD[i]) + " min, finestra " + I2S(g_obW[x]) + " min, conferma " +
                   ObTf(f) + ", " + OB_SIDE[sd];
      if(g_ruH != INVALID_HANDLE)
         FileWriteString(g_ruH, I2S(id) + ";1;2;" + I2S((int)OB_K[j]) + ";0;0;" + I2S(g_obW[x]) + ";0;0;-1;-1;0;0;" + Plain("ORB " + OB_OP[t] + " | " + ctx) +
                         ";" + I2S(g_otN[tr]) + ";" + DoubleToString(g_otEw[tr], 4) + ";" + DoubleToString(g_otZw[tr], 2) + ";" + I2S(g_otN[tr]) + ";" +
                         DoubleToString(g_otEw[tr], 4) + ";1;" + I2S(g_obClk[cs / g_obNS]) + ";" + I2S((cs % g_obNS) * g_obStep) + ";" + I2S(g_obD[i]) + ";" +
                         I2S(g_obW[x]) + ";" + (OB_MID[j] ? "1" : "0") + ";" + I2S((int)OB_K[j]) + ";" + (t < 4 ? "1" : "-1") + ";" +
                         I2S(sd == 0 ? 2 : sd - 1) + ";-1;" + I2S(g_obCf[f]) + "\n");
      g_ruHtml += "<tr>" + TD(I2S(id)) + TD("ORB (" + ObTf(f) + ")") + TD(OB_OP[t]) + TD(ctx) + TD(I2S(g_otN[tr])) + TD(SgnF(g_otEw[tr], 3)) +
                  TD(ZS(g_otZw[tr])) + TD("placebo " + ZS(g_otZp[tr]) + "; a favore / contro " + ObCont(cf)) + TD(BpTxt(g_otBe[tr])) +
                  TD(I2S(g_otN[tr])) + TD(SgnF(g_otEw[tr], 3)) + "</tr>";
      R(g_ruTx, "  Regola " + I2S(id) + ": ORB " + OB_OP[t] + " | " + ctx + " (analisi: N " + I2S(g_otN[tr]) + ", netta peggiore " + SgnF(g_otEw[tr], 3) +
        " R, z " + ZS(g_otZw[tr]) + ", meta' lorde " + SgnF(g_otE1[tr], 2) + " / " + SgnF(g_otE2[tr], 2) + ", contro il placebo z " + ZS(g_otZp[tr]) +
        ", costo di pareggio " + BpTxt(g_otBe[tr]) + ", dopo la conferma a favore / contro " + ObCont(cf) + "; un trade al giorno)");
     }
  }

void RRTab(CSeries &s, const int barSec, const string sym, const string clean)
  {
   g_txCbAll.Clear();
   for(int p = 0; p < NPRF; p++)
     {
      g_rrTxS[p] = "";
      g_rrTxT[p] = "";
      g_rrTxA[p] = "";
     }
   int L = InpRRMaxBars < 1 ? 1 : InpRRMaxBars;
   g_cbHtml = "";
   g_sqHtml = "";
   g_ruHtml = "";
   g_cbTx = "";
   g_sqTx = "";
   g_ruTx = "";
   g_ruN = 0;
   g_ruReal = 0;
   //--- CSV di tutti i contesti singoli e delle coppie (virgola decimale, punto e virgola: si apre in Excel italiano)
   string csvName = "MarketProfiler_" + clean + "_contesti.csv";
   g_csvH = FileOpen(csvName, FILE_WRITE | FILE_TXT | FILE_ANSI | (InpCommonDir ? FILE_COMMON : 0));
   string csvPath = (InpCommonDir ? TerminalInfoString(TERMINAL_COMMONDATA_PATH) : TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5") +
                    "\\Files\\" + csvName;
   if(g_csvH != INVALID_HANDLE)
     {
      string hd = "Timeframe;Tipo;Contesto A;Valore A;Contesto B;Valore B;Operazione;Obiettivo R;N;N effettivo;% obiettivo;Senza vantaggio %;" +
                  "% chiusi a tempo;Durata media (candele);Lorda R;z lorda;z lorda vs tutte;Meta 1 lorda R;Meta 2 lorda R;Costo max sostenibile";
      for(int p = 1; p < NPRF; p++)
        {
         string b = Plain(g_cp[p].name);
         hd += ";Netta " + b + " R;z " + b + ";z " + b + " vs tutte;Meta 1 " + b + " R;Meta 2 " + b + " R;Costo medio " + b + " R";
        }
      hd += ";Lorda meno stessa ora R (D1: meno tutte);z lorda vs stessa ora;Placebo lordo R;z lorda vs placebo;Costo di pareggio pb";
      for(int j = 0; j < g_bpN; j++)
         hd += ";Lorda a " + BpNum(g_bpV[j]) + " pb R;z a " + BpNum(g_bpV[j]) + " pb";
      for(int p = 1; p < NPRF; p++)
         hd += ";z " + Plain(g_cp[p].name) + " vs stessa ora;z " + Plain(g_cp[p].name) + " vs placebo";
      FileWriteString(g_csvH, hd + "\n");
     }
   //--- regole per lo Strategy Tester nella cartella comune (le legge l'EA MPRuleTester nel terminale del broker)
   string al[];
   AliasList(SymBase(sym), al);
   g_ruFile = "MarketProfiler_regole_" + al[0] + ".csv";
   g_ruH = FileOpen(g_ruFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(g_ruH != INVALID_HANDLE)
      FileWriteString(g_ruH, "id;tf_minuti;lato;R;stop_tipo;stop_K;max_candele;dimA;valA;dimB;valB;p20;p80;descrizione;N;netta_peggiore_R;z;" +
                      "trade_una_alla_volta;R_una_alla_volta;orb;orb_piazza;orb_inizio;orb_range;orb_finestra;orb_stop;orb_obiettivo;" +
                      "orb_modo;orb_lati;orb_giorno;orb_conferma\n");
   g_buf = true;
   g_bufS = "";
   SecStart("Coppie di contesti: come si legge",
            "Gli stessi trade della scheda R/R lordo (buy e sell a ogni apertura di candela, obiettivi 1:1 - 1:5), divisi per due " +
            "condizioni vere insieme (per esempio 'ora 16' e 'sopra il VWAP'): tutte le coppie tra ora, giorno, candela precedente, " +
            "volatilit&agrave;, volume, livelli di ieri e della settimana, giorno finora, trend e RSI (escluso l'anno). Le coppie sono " +
            "migliaia: <b>alcune superano |z| 3 per puro caso</b> e l'intestazione di ogni timeframe dice quante se ne aspettano. " +
            "Fidati di quelle stabili in entrambe le met&agrave; del campione, positive con i costi di entrambi i broker e che hanno " +
            "senso di mercato. Tutte le coppie con almeno 30 casi, e tutti i contesti singoli, sono nel file CSV " +
            (g_csvH != INVALID_HANDLE ? "<b>" + csvPath + "</b>" : "(non creato)") + " (punto e virgola, virgola decimale; in Python: " +
            "pandas.read_csv(file, sep=';', decimal=',')).");
   SecEnd();
   g_cbHtml = g_bufS;
   g_bufS = "";
   SecStart("Strategie: una posizione alla volta, serie di perdite e drawdown",
            "Nelle altre schede ogni candela apre un trade, anche se il precedente &egrave; ancora aperto: va bene per misurare, ma " +
            "non &egrave; come si opera. Qui i contesti migliori di ogni timeframe (i " + I2S(InpSeqTop) + " singoli e le " +
            I2S(InpSeqTop) + " coppie con lo z " + (g_cp[1].on || g_cp[2].on ? "netto del broker peggiore" : "lordo") + " pi&ugrave; " +
            "alto, tra quelli stabili nelle due met&agrave; e che fanno meglio della stessa ora con i costi del broker peggiore, " +
            "pi&ugrave; il riferimento 'entra sempre') sono eseguiti come farebbe " +
            "un EA: <b>una posizione alla volta</b>, in ordine di tempo. <b>Serie di perdite massima</b>: tra parentesi quella attesa " +
            "se l'ordine dei trade fosse casuale (mediana e 95%): se la reale supera il 95% le perdite arrivano a gruppi (fasi di " +
            "mercato sfavorevoli). <b>Drawdown massimo</b> in R dal picco: tra parentesi lo stesso con i trade rimescolati " +
            I2S(SQ_SH) + " volte. In rosso = oltre il 95% del caso. <b>Drawdown pi&ugrave; lungo</b> = giorni per tornare al " +
            "massimo precedente. In R: con un rischio dell'1% per trade, 10 R di drawdown = circa -10% del conto. Le regole che " +
            "reggono (z netto del broker peggiore &ge; " + F(InpRuleMinZ, 1) + ", stabili nelle due met&agrave; e positive anche " +
            "una posizione alla volta) sono esportate per lo Strategy Tester, insieme al riferimento 'entra sempre' di ogni " +
            "timeframe come termine di paragone: elenco e istruzioni in fondo alla pagina.");
   SecEnd();
   g_sqHtml = g_bufS;
   g_bufS = "";
   g_buf = false;
   string br = "";
   for(int p = 1; p < NPRF; p++)
      br += (p > 1 ? " e " : "") + g_cp[p].name;
   SecStart("Rischio/rendimento: come si legge",
            "A ogni apertura di candela del timeframe si aprono <b>un buy e un sell</b> al prezzo di apertura, con lo stesso stop " +
            "(calcolato solo con le candele gi&agrave; chiuse). Per ogni obiettivo da <b>1:1 a 1:5</b> (1 a 5 volte lo stop) si " +
            "guarda, barra per barra, se il prezzo arriva all'obiettivo prima dello stop. Se entro " + I2S(L) + " candele non succede " +
            "nessuno dei due, il trade si chiude a mercato. <b>Aspettativa</b> = guadagno medio per trade in multipli del rischio (R): " +
            "+R se arriva all'obiettivo, -1 se prende lo stop, il risultato a mercato se chiuso a tempo. Con un prezzo casuale la % di " +
            "obiettivi sarebbe 1/(1+R) (50%, 33%, 25%, 20%, 17%) e l'aspettativa 0: sopra &egrave; vantaggio, sotto svantaggio. " +
            "Questa scheda &egrave; <b>lorda</b> (senza costi): i risultati con spread, commissione e swap di " + br + " sono nelle " +
            "loro schede. <b>Costo massimo sostenibile</b> = il costo per trade oltre il quale l'aspettativa diventa negativa: " +
            "confrontalo con il costo medio del broker. <b>Esiti ambigui</b> = stop e obiettivo toccati nella stessa barra (M1): " +
            "contati come stop. <b>z</b> tiene conto che trade aperti a candele vicine si sovrappongono: due trade a g candele di " +
            "distanza con durata media d contano come correlati per 1 - g/d (entrate a ogni candela: N effettivo circa N / d; " +
            "entrate sparse, per esempio una sola ora al giorno su H1: N effettivo circa N). <b>Prima / seconda met&agrave;</b> = la stessa aspettativa calcolata sulla prima e sulla seconda " +
            "met&agrave; del periodo: un vantaggio reale dovrebbe esserci in entrambe (* nelle celle = segno diverso in una delle " +
            "due). <b>z rispetto a tutte le candele</b> = se il contesto fa meglio del semplice entrare sempre: su un indice che sale " +
            "nel tempo il buy ha un vantaggio di fondo e la riga 'Tutte le candele' &egrave; il riferimento. <b>z rispetto alla stessa " +
            "ora</b> = lo stesso confronto fatto ora per ora: ogni trade del contesto &egrave; confrontato con l'aspettativa di tutti i " +
            "trade della sua ora (sul D1, con tutte le candele). Toglie l'effetto dell'orario: un contesto che capita soprattutto " +
            "nelle ore buone sembra buono anche se non aggiunge nulla; vicino a zero = vale quanto l'orario da solo. <b>Placebo</b> = " +
            "la stessa operazione con direzione a caso nello stesso istante (media di buy e sell con lo stesso stop e obiettivo): " +
            "misura quanto rende il solo movimento del prezzo e le regole di esecuzione (per esempio gli esiti ambigui contati come " +
            "stop pesano su entrambi i lati). <b>z contro il placebo</b> = buy meno sell trade per trade: quanto conta la direzione. " +
            "Un contesto che passa z ma non questi due controlli &egrave; spiegato dall'orario o dal movimento, non dalla condizione: " +
            "la colonna Lettura lo segnala e le strategie scartano i contesti che non aggiungono nulla alla stessa ora. " +
            "<b>Costo massimo sostenibile</b> anche in <b>punti base</b> del prezzo (1 pb = 0,01%, " + CostBpTxt() + ") e aspettativa " +
            "con un costo per trade di " + BpLab() + " (tabella di ogni timeframe e CSV). Nessun contesto viene tolto, anche quelli " +
            "con pochi casi: il colore e z dicono quanto fidarsi. Il testo completo &egrave; nella scheda Testi &rarr; " +
            "Rischio/rendimento lordo.");
   SecEnd();
   int bm = barSec / 60 < 1 ? 1 : barSec / 60;
   for(int ti = 0; ti < RR_NTF && !IsStopped(); ti++)
     {
      if(RR_MIN[ti] < 3 * bm)  // servono almeno 3 barre per candela per seguire il percorso del prezzo
         continue;
      Comment("MarketProfiler: rischio/rendimento ", RR_NAME[ti], " ...");
      RRTf(s, barSec, ti);
      PrintFormat("[MarketProfiler] rischio/rendimento %s fatto", RR_NAME[ti]);
     }
   if(g_csvH != INVALID_HANDLE)
     {
      FileClose(g_csvH);
      g_csvH = INVALID_HANDLE;
      PrintFormat("[MarketProfiler] contesti e coppie salvati in %s", csvPath);
     }
   OrbRulesWrite();  // regole della scheda ORB, numerate dopo quelle dei contesti
   if(g_ruH != INVALID_HANDLE)
     {
      FileClose(g_ruH);
      g_ruH = INVALID_HANDLE;
     }
   ArrayFree(g_qK); ArrayFree(g_qF); ArrayFree(g_qX); ArrayFree(g_qS); ArrayFree(g_qO); ArrayFree(g_qD); ArrayFree(g_qC);
   g_qN = 0;
   //--- elenco delle regole e istruzioni per lo Strategy Tester
   string ruPath = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + g_ruFile;
   g_buf = true;
   g_bufS = "";
   SecStart("Regole per lo Strategy Tester (" + I2S(g_ruReal) + " regole e " + I2S(g_ruN - g_ruReal) + " riferimenti 'entra sempre')",
            "Regole esportate in <b>" + ruPath + "</b>. Servono a verificarle con i <b>tick reali</b> del broker (spread vero a ogni " +
            "istante, ordine vero di stop e obiettivo nella stessa barra, swap e commissioni del conto) e, soprattutto, sul periodo " +
            "<b>dopo</b> la fine dei dati usati qui (fuori campione). Come fare:<br>1. Copia <b>MPRuleTester.mq5</b> in MQL5\\Experts " +
            "del terminale del broker e compilalo.<br>2. Strategy Tester: Expert MPRuleTester, simbolo del broker (es. US100 o USTEC), " +
            "modello <b>Ogni tick basato su tick reali</b>, date a piacere (il timeframe del grafico non conta: ogni regola usa il " +
            "suo).<br>3. Una regola: parametro 'Regola' = il suo numero. Tutte: Ottimizzazione 'Algoritmo completo lento' con " +
            "'Regola' da 1 a " + I2S(MathMax(1, g_ruN)) + " passo 1, criterio 'Personalizzato max' (= R medi per trade).<br>4. I " +
            "risultati in R di ogni regola (trade, % vinti, R per trade, profit factor, serie di perdite, drawdown) finiscono in " +
            "Common\\Files\\MarketProfiler_tester_" + al[0] + ".csv e nel diario.<br>Il file delle regole &egrave; nella cartella " +
            "comune: lo leggono gli agenti locali del tester, non quelli remoti o del cloud. L'EA riconosce i contesti con le stesse " +
            "definizioni dello script sulle candele del broker: piccole differenze (volume del broker invece di quello dei dati, " +
            "giorni del server) sono normali. Le regole <b>ORB</b> (scheda ORB) entrano alla chiusura della prima candela M1 fuori dal " +
            "range dell'orario locale della piazza (o della prima candela M5, M15, M30, H1, secondo la conferma della regola): l'EA converte " +
            "l'orario con il fuso del server (parametro 'Fuso orario del server', " +
            "New York + 7 per FP Markets e IC Markets).");
   if(g_ruReal == 0)
      W("<p style='color:#f59e0b'>Nessuna regola supera i filtri (z netto del broker peggiore &ge; " + F(InpRuleMinZ, 1) + ", stabile " +
        "nelle due met&agrave;, positiva una posizione alla volta): sono esportati solo i riferimenti. Puoi abbassare 'z minimo' nei " +
        "parametri, sapendo che aumentano i falsi positivi.</p>");
   if(g_ruN > 0)
     {
      THead("Regola|Timeframe|Operazione|Contesto|N (analisi)|Aspettativa netta peggiore (R)|z|Controlli (z)|Costo di pareggio|Trade una alla volta|" +
            "R per trade una alla volta (peggiore)");
      W(g_ruHtml);
      TEnd();
     }
   SecEnd();
   g_sqHtml += g_bufS;
   g_bufS = "";
   g_buf = false;
   g_ruTx = "REGOLE PER LO STRATEGY TESTER (" + I2S(g_ruReal) + " regole e " + I2S(g_ruN - g_ruReal) + " riferimenti 'entra sempre', file " + ruPath + "; EA MPRuleTester, parametro Regola):\n" + g_ruTx;
  }

//+------------------------------------------------------------------+
//| Riepilogo: tutti i risultati lontani dal caso, da ogni scheda      |
//+------------------------------------------------------------------+
string g_repHi = "";

//+------------------------------------------------------------------+
//| PERSISTENZA: dove il prezzo continua e dove torna indietro        |
//| TIMEFRAME ALTO -> BASSO: stato della candela alta e comportamento |
//| dei timeframe inferiori al suo interno                            |
//+------------------------------------------------------------------+
string g_repPers = "", g_repMtf = "";
CText  g_txMtfAll;  // appendice F: tutte le coppie di stati del timeframe alto

// come RollIn, con la differenza dall'orologio NY+7 calcolata una volta per giorno dei dati
bool RollInC(const datetime t, long &cD, long &cOff)
  {
   if(!InpRollSkip)
      return false;
   long d = (long)t / 86400;
   if(d != cD)
     {
      cD = d;
      cOff = (long)DataToNY7(t) - (long)t;
     }
   return RollWin((int)((((long)t + cOff) % 86400) / 60));
  }

long CdKey(const datetime t, const int sec) { return sec >= 604800 ? ((long)t / 86400 + 3) / 7 : (long)t / sec; }  // settimana da lunedi'
datetime CdStart(const long key, const int sec) { return (datetime)(sec >= 604800 ? (key * 7 - 3) * 86400 : key * sec); }
string TfNm(const int sec)
  {
   if(sec >= 604800)
      return "W1";
   if(sec >= 86400)
      return "D1";
   if(sec >= 3600)
      return "H" + I2S(sec / 3600);
   return "M" + I2S(sec / 60);
  }

// candele di un timeframe costruite dalle barre della serie base (allineate alla mezzanotte dei dati, settimana da lunedi');
// con skipRoll le barre nella finestra del rollover sono ignorate
class CCd
  {
public:
   datetime          t[];
   long              k[];
   double            o[], h[], l[], c[];
   int               s[], e[], qh[], ql[];  // prima barra, barra dopo l'ultima, barra del massimo e del minimo (serie base)
   int               n, sec;
                     CCd(void) { n = 0; sec = 0; }
   void              Free(void)
     {
      ArrayFree(t); ArrayFree(k); ArrayFree(o); ArrayFree(h); ArrayFree(l); ArrayFree(c);
      ArrayFree(s); ArrayFree(e); ArrayFree(qh); ArrayFree(ql);
      n = 0;
     }
  };

void CdBuild(CSeries &b, const int sec, CCd &q, const bool skipRoll)
  {
   q.Free();
   q.sec = sec;
   long cD = -1, cOff = 0, cur = LONG_MIN;
   int n = 0;
   for(int i = 0; i < b.n; i++)
     {
      if(skipRoll && RollInC(b.t[i], cD, cOff))
         continue;
      long key = CdKey(b.t[i], sec);
      if(key != cur)
        {
         n++;
         cur = key;
        }
     }
   ArrayResize(q.t, n); ArrayResize(q.k, n); ArrayResize(q.o, n); ArrayResize(q.h, n); ArrayResize(q.l, n); ArrayResize(q.c, n);
   ArrayResize(q.s, n); ArrayResize(q.e, n); ArrayResize(q.qh, n); ArrayResize(q.ql, n);
   int x = -1;
   cur = LONG_MIN;
   cD = -1;
   for(int i = 0; i < b.n; i++)
     {
      if(skipRoll && RollInC(b.t[i], cD, cOff))
         continue;
      long key = CdKey(b.t[i], sec);
      if(key != cur)
        {
         x++;
         cur = key;
         q.k[x] = key;
         q.t[x] = b.t[i];
         q.o[x] = b.o[i];
         q.h[x] = b.h[i];
         q.l[x] = b.l[i];
         q.s[x] = i;
         q.qh[x] = i;
         q.ql[x] = i;
        }
      if(b.h[i] > q.h[x])
        {
         q.h[x] = b.h[i];
         q.qh[x] = i;
        }
      if(b.l[i] < q.l[x])
        {
         q.l[x] = b.l[i];
         q.ql[x] = i;
        }
      q.c[x] = b.c[i];
      q.e[x] = i + 1;
     }
   q.n = n;
  }

// ATR(p) come media semplice del true range delle ultime p candele (compresa la candela k)
void CdAtr(CCd &q, const int p, double &a[])
  {
   ArrayResize(a, q.n);
   double sum = 0, tr[];
   ArrayResize(tr, q.n);
   for(int k = 0; k < q.n; k++)
     {
      tr[k] = k == 0 ? q.h[k] - q.l[k] : MathMax(q.h[k], q.c[k - 1]) - MathMin(q.l[k], q.c[k - 1]);
      sum += tr[k];
      if(k >= p)
         sum -= tr[k - p];
      a[k] = k >= p - 1 ? sum / p : Nan();
     }
  }

//--- rapporto di varianza (Lo e MacKinlay, errore robusto all'eteroschedasticita') sui rendimenti logaritmici delle chiusure
#define VR_NL 16  // ritardi 1..15
#define VR_NQ 4
int VR_Q[VR_NQ] = {2, 4, 8, 16};
struct VrAcc
  {
   double            n, s1, s2;
   double            c[VR_NL], a[VR_NL], b[VR_NL], np[VR_NL], d[VR_NL];
  };

void VrPush(VrAcc &v, const double r, const double &ring[], const int run, const int pos)
  {
   v.n++;
   v.s1 += r;
   v.s2 += r * r;
   int m = run < VR_NL - 1 ? run : VR_NL - 1;
   for(int j = 1; j <= m; j++)
     {
      double rp = ring[(pos - j + VR_NL) % VR_NL];
      v.c[j] += r * rp;
      v.a[j] += r;
      v.b[j] += rp;
      v.np[j]++;
      v.d[j] += r * r * rp * rp;
     }
  }

// VR(q) = 1 + 2 somma (1 - j/q) rho(j); z = (VR - 1) / errore robusto (somma dei (2 (1 - j/q))^2 var(rho(j)))
bool VrRes(VrAcc &v, const int q, double &vr, double &z)
  {
   vr = Nan();
   z = Nan();
   if(v.n < 30)
      return false;
   double mu = v.s1 / v.n, s0 = v.s2 - v.n * mu * mu;
   if(!(s0 > 0))
      return false;
   double sm = 0, var = 0;
   for(int j = 1; j < q && j < VR_NL; j++)
     {
      double cc = v.c[j] - mu * (v.a[j] + v.b[j]) + v.np[j] * mu * mu, w = 2.0 * (1.0 - (double)j / q);
      sm += w * cc / s0;
      var += w * w * v.d[j] / (s0 * s0);
     }
   vr = 1 + sm;
   z = var > 0 ? sm / MathSqrt(var) : Nan();
   return true;
  }

// rendimenti di chiusure consecutive del timeframe sec (candele costruite al volo dalla serie base, l'ultima in corso esclusa);
// un buco oltre 3 candele (intraday), 4 giorni (D1) o 3 settimane (W1) interrompe la catena. v[0] = tutto, v[1], v[2] = meta'
void VrTf(CSeries &b, const int sec, const datetime tMid, VrAcc &v[])
  {
   for(int x = 0; x < 3; x++)
      ZeroMemory(v[x]);
   long maxGap = sec < 86400 ? (long)3 * sec : (sec == 86400 ? (long)4 * 86400 : (long)21 * 86400);
   double ring[VR_NL];
   ArrayInitialize(ring, 0.0);
   int run = 0, pos = 0;
   long cD = -1, cOff = 0, cur = LONG_MIN;
   datetime ct = 0, pt = 0;
   double cc = 0, pc = 0;
   bool hp = false;
   for(int i = 0; i < b.n; i++)
     {
      if(InpRollSkip && RollInC(b.t[i], cD, cOff))
         continue;
      long key = CdKey(b.t[i], sec);
      if(key != cur)
        {
         if(cur != LONG_MIN)  // candela appena finita: rendimento dalla chiusura della precedente
           {
            if(hp && (long)ct - (long)pt <= maxGap && pc > 0 && cc > 0)
              {
               double r = MathLog(cc / pc);
               VrPush(v[0], r, ring, run, pos);
               VrPush(v[ct < tMid ? 1 : 2], r, ring, run, pos);
               ring[pos] = r;
               pos = (pos + 1) % VR_NL;
               run++;
              }
            else
               run = 0;
            pt = ct;
            pc = cc;
            hp = true;
           }
         cur = key;
         ct = b.t[i];
        }
      cc = b.c[i];
     }
  }

//--- continuazione per ora del giorno: il movimento dei L minuti prima di ogni mezz'ora prosegue nei F minuti dopo?
#define TD_NH 5
int TD_L[TD_NH] = {15, 30, 60, 60, 240};
int TD_F[TD_NH] = {15, 30, 60, 240, 240};

double TdPx(CSeries &b, const long x, const long tol)  // apertura della prima barra dall'istante x (0 se manca entro tol secondi)
  {
   int k = LowerBound(b.t, b.n, (datetime)x);
   return (k < b.n && (long)b.t[k] - x < tol) ? b.o[k] : 0;
  }

void PersTab(CSeries &b, const int barSec)
  {
   g_repPers = "";
   if(b.n < 5000)
     {
      SecStart("Persistenza", "");
      W("<p class='muted'>Servono dati M1 o M5.</p>");
      SecEnd();
      return;
     }
   datetime tMid = (datetime)((long)b.t[0] + ((long)b.t[b.n - 1] - (long)b.t[0]) / 2);
   //--- 1. rapporto di varianza per timeframe
   int secs[8] = {60, 300, 900, 1800, 3600, 14400, 86400, 604800};
   string d1 = "Rapporto di varianza VR(q) = varianza dei movimenti di q candele divisa per q volte la varianza dei movimenti di " +
               "una candela (rendimenti logaritmici delle chiusure). Con un prezzo casuale VR = 1; sopra 1 i movimenti tendono a " +
               "continuare nella stessa direzione (trend), sotto 1 a tornare indietro (mean reversion). z con errore robusto ai " +
               "periodi pi&ugrave; e meno volatili (Lo e MacKinlay): entro +/-2 compatibile con il caso. Tra parentesi l'orizzonte " +
               "(q candele) e le due met&agrave; dello storico (prima met&agrave; fino al " + TimeToString(tMid, TIME_DATE) + "). " +
               "Chiusure consecutive: un buco (weekend, mercato chiuso) interrompe la catena. " + RollTxt();
   SecStart("Persistenza per timeframe: i movimenti continuano o tornano indietro?", d1);
   THead("Timeframe|Rendimenti|VR(2)|VR(4)|VR(8)|VR(16)|Lettura");
   R(g_repPers, "=== PERSISTENZA PER TIMEFRAME: rapporto di varianza ===");
   R(g_repPers, "Metodo: " + d1);
   VrAcc v[3];
   for(int ti = 0; ti < 8; ti++)
     {
      int sec = secs[ti];
      if(sec < barSec)
         continue;
      VrTf(b, sec, tMid, v);
      if(v[0].n < 30)
         continue;
      string row = "<tr>" + TD(TfNm(sec)) + TD(DoubleToString(v[0].n, 0));
      string tx = "  " + TfNm(sec) + " (" + DoubleToString(v[0].n, 0) + " rendimenti):";
      double bz = 0;
      int bq = -1;
      bool bst = false;
      for(int qi = 0; qi < VR_NQ; qi++)
        {
         int q = VR_Q[qi];
         double vr, z, v1, z1, v2, z2;
         VrRes(v[0], q, vr, z);
         VrRes(v[1], q, v1, z1);
         VrRes(v[2], q, v2, z2);
         bool st = MathIsValidNumber(v1) && MathIsValidNumber(v2) && MathIsValidNumber(z) && (v1 > 1) == (z > 0) && (v2 > 1) == (z > 0);
         string hz = DurLab((double)q * sec / 3600.0);
         row += TDc(F(vr, 3) + " <small>z " + ZS(z) + "<br>" + F(v1, 3) + " / " + F(v2, 3) + "</small>", PCol(z, 0, 5));
         tx += " VR(" + I2S(q) + ", " + hz + ") " + F(vr, 3) + " (z " + ZS(z) + "; meta' " + F(v1, 3) + " / " + F(v2, 3) + (st ? ", stabile" : "") + ");";
         if(MathIsValidNumber(z) && MathAbs(z) > MathAbs(bz))
           {
            bz = z;
            bq = q;
            bst = st;
           }
         if(HiKeep(14, z))
            HiAdd(14, z, "Persistenza " + TfNm(sec) + ": VR(" + I2S(q) + ") = " + F(vr, 3) + " (movimenti di " + hz + ", " +
                  DoubleToString(v[0].n, 0) + " rendimenti): " + (vr > 1 ? "i movimenti continuano (trend)" : "i movimenti tornano indietro (mean reversion)") +
                  ", meta' " + F(v1, 3) + " / " + F(v2, 3) + (st ? " (stabile)" : " (non stabile)"));
        }
      string rd = "compatibile con il caso (passeggiata casuale)";
      if(MathAbs(bz) >= 2 && bq > 0)
         rd = (bz > 0 ? "i movimenti continuano (trend)" : "i movimenti tornano indietro (mean reversion)") + " su " +
              DurLab((double)bq * sec / 3600.0) + (MathAbs(bz) >= 3 ? ", forte" : ", indizio") + (bst ? ", stabile nelle due meta'" : ", non stabile");
      W(row + TD(rd) + "</tr>");
      R(g_repPers, tx + " -> " + rd);
     }
   TEnd();
   SecEnd();
   //--- 2. per ora del giorno
   int NS = 48, NC = 48 * TD_NH;
   double an[], sx[], sxx[], nz[], ct[], nS[], sxS[], sxxS[], nzS[], ctS[], nH[], sxH[], ctH[], nzH[], rF[], rP[];
   int rN[], rPos[];
   ArrayResize(an, NC); ArrayResize(sx, NC); ArrayResize(sxx, NC); ArrayResize(nz, NC); ArrayResize(ct, NC);
   ArrayResize(nS, NC); ArrayResize(sxS, NC); ArrayResize(sxxS, NC); ArrayResize(nzS, NC); ArrayResize(ctS, NC);
   ArrayResize(nH, 2 * NC); ArrayResize(sxH, 2 * NC); ArrayResize(ctH, 2 * NC); ArrayResize(nzH, 2 * NC);
   ArrayResize(rF, 20 * NC); ArrayResize(rP, 20 * NC); ArrayResize(rN, NC); ArrayResize(rPos, NC);
   ArrayInitialize(an, 0); ArrayInitialize(sx, 0); ArrayInitialize(sxx, 0); ArrayInitialize(nz, 0); ArrayInitialize(ct, 0);
   ArrayInitialize(nS, 0); ArrayInitialize(sxS, 0); ArrayInitialize(sxxS, 0); ArrayInitialize(nzS, 0); ArrayInitialize(ctS, 0);
   ArrayInitialize(nH, 0); ArrayInitialize(sxH, 0); ArrayInitialize(ctH, 0); ArrayInitialize(nzH, 0);
   ArrayInitialize(rF, 0); ArrayInitialize(rP, 0); ArrayInitialize(rN, 0); ArrayInitialize(rPos, 0);
   long tol = (long)barSec * 2 > 120 ? (long)barSec * 2 : 120;
   long dA = (long)DataToNY7(b.t[0]) / 86400, dB = (long)DataToNY7(b.t[b.n - 1]) / 86400;
   for(long D = dA; D <= dB && !IsStopped(); D++)
     {
      datetime mid7 = (datetime)(D * 86400 + 43200);
      if(DowMon(mid7) > 4)
         continue;
      long off = (long)DataToNY7(mid7) - (long)mid7;
      for(int z = 0; z < NS; z++)
        {
         long T7 = D * 86400 + (long)z * 1800;
         double pT = TdPx(b, T7 - off, tol);
         if(!(pT > 0))
            continue;
         int hf = (datetime)(T7 - off) < tMid ? 0 : 1;
         for(int hh = 0; hh < TD_NH; hh++)
           {
            long L = (long)TD_L[hh] * 60, Fw = (long)TD_F[hh] * 60;
            if(RollHit7(T7 - L, T7 + Fw - 1))
               continue;
            double pA = TdPx(b, T7 - off - L, tol), pC = TdPx(b, T7 - off + Fw, tol);
            if(!(pA > 0) || !(pC > 0))
               continue;
            double past = pT - pA, fut = pC - pT;
            int x = z * TD_NH + hh;
            int cnt = rN[x];
            //--- scala: movimento assoluto medio degli ultimi 20 giorni validi a quest'ora (solo giorni precedenti)
            double sF = 0, sP = 0;
            for(int q = 0; q < cnt; q++)
              {
               sF += rF[x * 20 + q];
               sP += rP[x * 20 + q];
              }
            rF[x * 20 + rPos[x]] = MathAbs(fut);
            rP[x * 20 + rPos[x]] = MathAbs(past);
            rPos[x] = (rPos[x] + 1) % 20;
            if(rN[x] < 20)
               rN[x]++;
            if(cnt < 20 || !(sF > 0) || !(sP > 0) || past == 0)
               continue;
            sF /= 20;
            sP /= 20;
            double xv = (past > 0 ? fut : -fut) / sF;
            bool strong = MathAbs(past) >= 1.5 * sP;
            an[x]++;
            sx[x] += xv;
            sxx[x] += xv * xv;
            nH[x * 2 + hf]++;
            sxH[x * 2 + hf] += xv;
            if(fut != 0)
              {
               bool same = (fut > 0) == (past > 0);
               nz[x]++;
               nzH[x * 2 + hf]++;
               if(same)
                 {
                  ct[x]++;
                  ctH[x * 2 + hf]++;
                 }
               if(strong)
                 {
                  nzS[x]++;
                  if(same)
                     ctS[x]++;
                 }
              }
            if(strong)
              {
               nS[x]++;
               sxS[x] += xv;
               sxxS[x] += xv * xv;
              }
           }
        }
     }
   string d2 = "Per ogni mezz'ora della giornata (ora del broker New York + 7, tra parentesi New York e Londra), giorno per giorno: " +
               "il prezzo si &egrave; mosso nei L minuti prima; nei F minuti dopo va nella stessa direzione? Continua = % dei giorni in cui " +
               "il movimento dopo ha lo stesso segno di quello prima (caso = 50%). Seguito medio = movimento dopo nella direzione di quello " +
               "prima, in multipli del movimento tipico dei F minuti a quell'ora (media degli ultimi 20 giorni): positivo = continua, " +
               "negativo = torna indietro, 0 = nessun legame. Forte = movimento prima di almeno 1,5 volte il suo tipico. z: giorni " +
               "indipendenti, entro +/-2 compatibile con il caso; met&agrave; = seguito medio nella prima e nella seconda met&agrave; dello storico. " +
               "Esclusi gli intervalli che toccano il rollover.";
   R(g_repPers, "");
   R(g_repPers, "=== PERSISTENZA PER ORA DEL GIORNO: il movimento prima continua dopo? ===");
   R(g_repPers, "Metodo: " + d2);
   for(int hh = 0; hh < TD_NH; hh++)
     {
      string hl = I2S(TD_L[hh]) + " min prima -> " + I2S(TD_F[hh]) + " min dopo";
      SecStart("Persistenza per ora del giorno: " + hl, hh == 0 ? d2 : "");
      THead("Broker|New York|Londra|Giorni|Continua|Seguito medio|Met&agrave; 1 / 2|Forte: giorni|Forte: continua|Forte: seguito|Lettura");
      R(g_repPers, "");
      R(g_repPers, "[" + hl + "]");
      string upL = "", dnL = "";
      for(int z = 0; z < NS; z++)
        {
         int x = z * TD_NH + hh;
         if(an[x] < 30)
            continue;
         string lab = HM(z * 30) + " (NY " + HM(z * 30 - 420) + ", LDN " + HM(z * 30 - 120) + ")";
         double m = sx[x] / an[x];
         double sd = MathSqrt(MathMax(0.0, sxx[x] / an[x] - m * m));
         double zx = sd > 0 ? m / (sd / MathSqrt(an[x])) : Nan();
         double pc = nz[x] > 0 ? ct[x] / nz[x] : Nan();
         double zc = ZProp(pc, 0.5, nz[x]);
         double m1 = nH[x * 2] > 0 ? sxH[x * 2] / nH[x * 2] : Nan(), m2 = nH[x * 2 + 1] > 0 ? sxH[x * 2 + 1] / nH[x * 2 + 1] : Nan();
         bool st = MathIsValidNumber(m1) && MathIsValidNumber(m2) && MathIsValidNumber(zx) && (m1 > 0) == (zx > 0) && (m2 > 0) == (zx > 0);
         double mS = nS[x] > 0 ? sxS[x] / nS[x] : Nan();
         double sdS = nS[x] > 1 ? MathSqrt(MathMax(0.0, sxxS[x] / nS[x] - mS * mS)) : Nan();
         double zS = nS[x] >= 30 && sdS > 0 ? mS / (sdS / MathSqrt(nS[x])) : Nan();
         double pS = nzS[x] > 0 ? ctS[x] / nzS[x] : Nan();
         double zpS = nS[x] >= 30 ? ZProp(pS, 0.5, nzS[x]) : Nan();
         string rd = "casuale";
         if(MathIsValidNumber(zx) && MathAbs(zx) >= 2)
            rd = (zx > 0 ? "continua" : "torna indietro") + (MathAbs(zx) >= 3 ? "" : " (indizio)") + (st ? ", stabile" : ", non stabile");
         W("<tr>" + TD(HM(z * 30)) + TD(HM(z * 30 - 420)) + TD(HM(z * 30 - 120)) + TD(DoubleToString(an[x], 0)) +
           TDc(FP(pc, 1) + "% <small>z " + ZS(zc) + "</small>", PCol(zc, 0, 5)) + TDc(SgnF(m, 3) + " <small>z " + ZS(zx) + "</small>", PCol(zx, 0, 5)) +
           TD(SgnF(m1, 3) + " / " + SgnF(m2, 3)) + TD(DoubleToString(nS[x], 0)) + TDc(FP(pS, 1) + "% <small>z " + ZS(zpS) + "</small>", PCol(zpS, 0, 5)) +
           TDc(SgnF(mS, 3) + " <small>z " + ZS(zS) + "</small>", PCol(zS, 0, 5)) + TD(rd) + "</tr>");
         R(g_repPers, "  " + lab + ", " + DoubleToString(an[x], 0) + " giorni: continua " + FP(pc, 1) + "% (z " + ZS(zc) + "), seguito medio " +
           SgnF(m, 3) + " (z " + ZS(zx) + "; meta' " + SgnF(m1, 3) + " / " + SgnF(m2, 3) + "); dopo un movimento forte (" +
           DoubleToString(nS[x], 0) + " giorni): continua " + FP(pS, 1) + "% (z " + ZS(zpS) + "), seguito " + SgnF(mS, 3) + " (z " + ZS(zS) + ") -> " + rd);
         string hl2 = "Persistenza alle " + HM(z * 30) + " del broker (NY " + HM(z * 30 - 420) + ", LDN " + HM(z * 30 - 120) + "), " + hl;
         if(HiKeep(15, zx))
            HiAdd(15, zx, hl2 + " (" + DoubleToString(an[x], 0) + " giorni): il movimento " + (zx > 0 ? "continua" : "torna indietro") +
                  ", continua nel " + FP(pc, 1) + "% dei giorni, seguito medio " + SgnF(m, 3) + " del movimento tipico, meta' " + SgnF(m1, 3) +
                  " / " + SgnF(m2, 3) + (st ? " (stabile)" : " (non stabile)"));
         if(HiKeep(15, zS))
            HiAdd(15, zS, hl2 + ", dopo un movimento forte (" + DoubleToString(nS[x], 0) + " giorni): " + (zS > 0 ? "continua" : "torna indietro") +
                  " nel " + FP(pS, 1) + "% dei giorni, seguito medio " + SgnF(mS, 3) + " del movimento tipico");
         if(MathIsValidNumber(zx) && zx >= 3)
            upL += (upL != "" ? ", " : "") + HM(z * 30) + " (z " + ZS(zx) + ")";
         if(MathIsValidNumber(zx) && zx <= -3)
            dnL += (dnL != "" ? ", " : "") + HM(z * 30) + " (z " + ZS(zx) + ")";
        }
      TEnd();
      string sm = "Continua (z >= 3): " + (upL != "" ? upL : "nessuna") + "; torna indietro (z <= -3): " + (dnL != "" ? dnL : "nessuna") + " (ora del broker).";
      W("<p class='muted'>" + sm + "</p>");
      SecEnd();
      R(g_repPers, "  In breve: " + sm);
     }
  }

//--- timeframe alto -> basso
#define MT_ND 9
#define MT_NSV 28
string MT_DIM[MT_ND] = {"Candela precedente (forte = il 20% piu' forte)", "Chiusura della candela precedente nel suo range",
                        "Apertura rispetto alla EMA50", "EMA20 rispetto alla EMA50", "Volatilita' (ATR14 / ATR100)",
                        "Apertura rispetto alla candela precedente", "Ampiezza della candela precedente rispetto all'ATR(14)",
                        "Candele di fila", "Apertura nel range delle ultime 20 candele"};
string MT_DS[MT_ND] = {"Precedente", "Chiusura precedente", "Apertura/EMA50", "EMA20/EMA50", "Volatilita'", "Apertura/precedente",
                       "Ampiezza precedente", "Di fila", "Range 20"};
string MT_VAL[MT_ND] = {"forte rialzo|rialzo|ribasso|forte ribasso", "nel terzo basso|nel terzo centrale|nel terzo alto",
                        "sopra la EMA50|sotto la EMA50", "EMA20 sopra la EMA50|EMA20 sotto la EMA50",
                        "compressione (sotto 0.8)|normale (0.8-1.2)|espansione (sopra 1.2)",
                        "sopra il massimo|dentro il range|sotto il minimo", "stretta (sotto 0.75 ATR)|normale|ampia (oltre 1.33 ATR)",
                        "3 o piu' rialziste|2 rialziste|3 o piu' ribassiste|2 ribassiste|ultima diversa dalla penultima",
                        "nel quinto alto|nel mezzo|nel quinto basso"};
int    MT_NV[MT_ND] = {4, 3, 2, 2, 3, 3, 3, 5, 3};
int    g_mtVO[MT_ND];
string g_mtLab[MT_NSV];
int    g_mtDimOf[MT_NSV];
double g_mtA[], g_mtB[], g_mtAA[], g_mtAB[], g_mtBB[], g_mtAH[], g_mtBH[];
int    g_mtNM = 0;

void MtSetup(void)
  {
   int u = 0;
   for(int d = 0; d < MT_ND; d++)
     {
      g_mtVO[d] = u;
      string p[];
      int k = StringSplit(MT_VAL[d], '|', p);
      for(int v = 0; v < MT_NV[d]; v++)
        {
         g_mtLab[u] = v < k ? p[v] : "?";
         g_mtDimOf[u] = d;
         u++;
        }
     }
  }

// stato della candela alta k, tutto noto alla sua apertura (u[d] = valore, -1 = non definito)
void MtState(CCd &q, const int k, const double &ret[], const double &atr[], const double &atrL[], const double &e20[], const double &e50[],
             const int &stk[], const double p20, const double p80, int &u[])
  {
   for(int d = 0; d < MT_ND; d++)
      u[d] = -1;
   if(k < 21 || k >= q.n)
      return;
   int j = k - 1;
   double rp = ret[j];
   u[0] = rp >= p80 ? 0 : (rp <= p20 ? 3 : (rp > 0 ? 1 : 2));
   double rg = q.h[j] - q.l[j];
   if(rg > 0)
      u[1] = (int)MathMin(2.0, MathFloor(3.0 * (q.c[j] - q.l[j]) / rg));
   if(j >= 50)
     {
      u[2] = q.o[k] > e50[j] ? 0 : 1;
      u[3] = e20[j] > e50[j] ? 0 : 1;
     }
   if(j >= 100 && MathIsValidNumber(atrL[j]) && atrL[j] > 0 && MathIsValidNumber(atr[j]))
     {
      double vr = atr[j] / atrL[j];
      u[4] = vr < 0.8 ? 0 : (vr > 1.2 ? 2 : 1);
     }
   u[5] = q.o[k] > q.h[j] ? 0 : (q.o[k] < q.l[j] ? 2 : 1);
   if(MathIsValidNumber(atr[j]) && atr[j] > 0)
     {
      double ra = rg / atr[j];
      u[6] = ra < 0.75 ? 0 : (ra > 1.33 ? 2 : 1);
     }
   int dr = rp > 0 ? 1 : (rp < 0 ? -1 : 0), sk = stk[j];
   u[7] = dr > 0 ? (sk >= 3 ? 0 : (sk == 2 ? 1 : 4)) : (dr < 0 ? (sk >= 3 ? 2 : (sk == 2 ? 3 : 4)) : 4);
   double hh = q.h[j], ll = q.l[j];
   for(int x = k - 20; x < k; x++)
     {
      if(q.h[x] > hh)
         hh = q.h[x];
      if(q.l[x] < ll)
         ll = q.l[x];
     }
   if(hh > ll)
     {
      double f = (q.o[k] - ll) / (hh - ll);
      u[8] = f >= 0.8 ? 0 : (f <= 0.2 ? 2 : 1);
     }
  }

void MtAdd(const int cell, const double &a[], const double &b[], const int hf)
  {
   for(int m = 0; m < g_mtNM; m++)
     {
      if(!(b[m] > 0))
         continue;
      int x = cell * g_mtNM + m;
      g_mtA[x] += a[m];
      g_mtB[x] += b[m];
      g_mtAA[x] += a[m] * a[m];
      g_mtAB[x] += a[m] * b[m];
      g_mtBB[x] += b[m] * b[m];
      g_mtAH[x * 2 + hf] += a[m];
      g_mtBH[x * 2 + hf] += b[m];
     }
  }

// cella contro tutte le altre candele (cella 0 = tutte): quota p e degli altri p2, z con errore robusto ai casi raggruppati nella
// stessa candela alta (stimatore del rapporto); ph1 / ph2 = quota della cella nelle due meta'; st = stesso verso nelle due meta'
bool MtZ(const int cell, const int m, const double minB, double &p, double &p2, double &z, double &ph1, double &ph2, bool &st)
  {
   int x = cell * g_mtNM + m, x0 = m;
   double sb = g_mtB[x], b2 = g_mtB[x0] - sb;
   p = Nan();
   p2 = Nan();
   z = Nan();
   ph1 = Nan();
   ph2 = Nan();
   st = false;
   if(sb < minB || b2 < minB)
      return false;
   p = g_mtA[x] / sb;
   p2 = (g_mtA[x0] - g_mtA[x]) / b2;
   double v1 = (g_mtAA[x] - 2 * p * g_mtAB[x] + p * p * g_mtBB[x]) / (sb * sb);
   double v2 = ((g_mtAA[x0] - g_mtAA[x]) - 2 * p2 * (g_mtAB[x0] - g_mtAB[x]) + p2 * p2 * (g_mtBB[x0] - g_mtBB[x])) / (b2 * b2);
   if(!(v1 + v2 > 0))
      return false;
   z = (p - p2) / MathSqrt(v1 + v2);
   bool ok = true;
   for(int h = 0; h < 2; h++)
     {
      double bh = g_mtBH[x * 2 + h], bo = g_mtBH[x0 * 2 + h] - bh;
      if(bh <= 0 || bo <= 0)
        {
         ok = false;
         continue;
        }
      double ph = g_mtAH[x * 2 + h] / bh, po = (g_mtAH[x0 * 2 + h] - g_mtAH[x * 2 + h]) / bo;
      if(h == 0)
         ph1 = ph;
      else
         ph2 = ph;
      if((ph > po) != (z > 0))
         ok = false;
     }
   st = ok;
   return true;
  }

string MtCell(const int cell)  // etichetta di una cella (stato singolo o coppia)
  {
   if(cell == 0)
      return "Tutte le candele";
   int u = cell - 1;
   if(u < MT_NSV)
      return MT_DIM[g_mtDimOf[u]] + ": " + g_mtLab[u];
   u -= MT_NSV;
   int u1 = u / MT_NSV, u2 = u % MT_NSV;
   return MT_DS[g_mtDimOf[u1]] + ": " + g_mtLab[u1] + " + " + MT_DS[g_mtDimOf[u2]] + ": " + g_mtLab[u2];
  }

void MtHtf(CSeries &b, const int barSec, const int hs)
  {
   int ls[3], nl = 0;
   if(hs == 14400)
     {
      ls[0] = 300;
      ls[1] = 900;
      nl = 2;
     }
   else
      if(hs == 86400)
        {
         ls[0] = 300;
         ls[1] = 900;
         ls[2] = 3600;
         nl = 3;
        }
      else
        {
         ls[0] = 3600;
         ls[1] = 14400;
         nl = 2;
        }
   int nv = 0;
   for(int x = 0; x < nl; x++)
      if(ls[x] >= barSec)
         ls[nv++] = ls[x];
   nl = nv;
   string hn = TfNm(hs);
   CCd q;
   CdBuild(b, hs, q, InpRollSkip);
   int n = q.n;
   if(n < 150)
     {
      SecStart("Timeframe alto -> basso: " + hn, "");
      W("<p class='muted'>Storico insufficiente (" + I2S(n) + " candele " + hn + ").</p>");
      SecEnd();
      return;
     }
   //--- indicatori della candela alta
   double ret[], atr[], atrL[], e20[], e50[], rg[];
   int stk[];
   ArrayResize(ret, n); ArrayResize(e20, n); ArrayResize(e50, n); ArrayResize(rg, n); ArrayResize(stk, n);
   CdAtr(q, 14, atr);
   CdAtr(q, 100, atrL);
   for(int k = 0; k < n; k++)
     {
      ret[k] = q.o[k] > 0 ? q.c[k] / q.o[k] - 1 : 0;
      rg[k] = q.h[k] - q.l[k];
      e20[k] = k == 0 ? q.c[0] : 2.0 / 21.0 * q.c[k] + (1 - 2.0 / 21.0) * e20[k - 1];
      e50[k] = k == 0 ? q.c[0] : 2.0 / 51.0 * q.c[k] + (1 - 2.0 / 51.0) * e50[k - 1];
      int dr = q.c[k] > q.o[k] ? 1 : (q.c[k] < q.o[k] ? -1 : 0), dp = k > 0 ? (q.c[k - 1] > q.o[k - 1] ? 1 : (q.c[k - 1] < q.o[k - 1] ? -1 : 0)) : 0;
      stk[k] = dr == 0 ? 0 : ((k > 0 && dp == dr) ? stk[k - 1] + 1 : 1);
     }
   double srt[];
   Sorted(ret, n - 1, srt);
   double p20 = Pct(srt, n - 1, 20), p80 = Pct(srt, n - 1, 80);
   datetime tMid = (datetime)((long)q.t[21] + ((long)q.t[n - 2] - (long)q.t[21]) / 2);
   long dur = hs >= 604800 ? (long)5 * 86400 : (long)hs;
   //--- misure: 0-3 della candela alta, poi 3 per ogni timeframe basso
   g_mtNM = 4 + 3 * nl;
   int NM = g_mtNM, NC = 1 + MT_NSV + MT_NSV * MT_NSV;
   double A[], B[];
   ArrayResize(A, n * NM);
   ArrayResize(B, n * NM);
   ArrayInitialize(A, 0.0);
   ArrayInitialize(B, 0.0);
   double w20[];
   ArrayResize(w20, 20);
   for(int k = 21; k < n - 1; k++)
     {
      int x = k * NM;
      B[x] = 1;
      A[x] = q.c[k] > q.o[k] ? 1 : 0;
      for(int j = 0; j < 20; j++)
         w20[j] = rg[k - 20 + j];
      ArraySort(w20);
      double md = 0.5 * (w20[9] + w20[10]);
      if(md > 0)
        {
         B[x + 1] = 1;
         A[x + 1] = rg[k] > 1.33 * md ? 1 : 0;
        }
      long st0 = (long)CdStart(q.k[k], hs);
      B[x + 2] = 1;
      A[x + 2] = (long)b.t[q.qh[k]] - st0 < dur / 3 ? 1 : 0;
      B[x + 3] = 1;
      A[x + 3] = (long)b.t[q.ql[k]] - st0 < dur / 3 ? 1 : 0;
     }
   for(int li = 0; li < nl; li++)
     {
      int lsec = ls[li], mi = 4 + 3 * li;
      Comment("MarketProfiler: timeframe alto -> basso ", hn, " -> ", TfNm(lsec), " ...");
      CCd L;
      CdBuild(b, lsec, L, InpRollSkip);
      double la[];
      CdAtr(L, 14, la);
      long gp = (long)3 * lsec;
      int k = 0;
      for(int j = 9; j < L.n - 1 && !IsStopped(); j++)
        {
         while(k < n && q.e[k] <= L.s[j])
            k++;
         if(k >= n - 1)
            break;
         if(k < 21 || L.s[j] < q.s[k])
            continue;
         int x = k * NM + mi;
         //--- continua: la candela bassa va nella stessa direzione della precedente
         if((long)L.t[j] - (long)L.t[j - 1] <= gp && (long)L.t[j - 1] - (long)L.t[j - 2] <= gp)
           {
            double r1 = L.c[j] - L.c[j - 1], r0 = L.c[j - 1] - L.c[j - 2];
            if(r1 != 0 && r0 != 0)
              {
               B[x] += 1;
               if((r1 > 0) == (r0 > 0))
                  A[x] += 1;
              }
           }
         //--- rottura: chiusura oltre il massimo (minimo) delle 8 candele precedenti, la precedente non oltre il suo;
         //    prosegue = arriva prima a +1 ATR(14) che a -1 ATR entro 16 candele (stessa candela o buco: non conta)
         if(!MathIsValidNumber(la[j]) || !(la[j] > 0))
            continue;
         double hh = L.h[j - 8], ll = L.l[j - 8], hp = L.h[j - 9], lp = L.l[j - 9];
         for(int y = j - 7; y < j; y++)
           {
            if(L.h[y] > hh)
               hh = L.h[y];
            if(L.l[y] < ll)
               ll = L.l[y];
           }
         for(int y = j - 8; y < j - 1; y++)
           {
            if(L.h[y] > hp)
               hp = L.h[y];
            if(L.l[y] < lp)
               lp = L.l[y];
           }
         for(int sd = 0; sd < 2; sd++)
           {
            bool brk = sd == 0 ? (L.c[j] > hh && L.c[j - 1] <= hp) : (L.c[j] < ll && L.c[j - 1] >= lp);
            if(!brk)
               continue;
            double up = L.c[j] + la[j], dn = L.c[j] - la[j];
            int res = -1;
            for(int y = j + 1; y <= j + 16 && y < L.n; y++)
              {
               if((long)L.t[y] - (long)L.t[y - 1] > gp)
                  break;
               bool hu = L.h[y] >= up, hd = L.l[y] <= dn;
               if(hu && hd)
                  break;
               if(hu)
                 {
                  res = sd == 0 ? 1 : 0;
                  break;
                 }
               if(hd)
                 {
                  res = sd == 0 ? 0 : 1;
                  break;
                 }
              }
            if(res >= 0)
              {
               B[x + 1 + sd] += 1;
               A[x + 1 + sd] += res;
              }
           }
        }
      L.Free();
     }
   //--- somme per stato singolo e per coppia di stati
   ArrayResize(g_mtA, NC * NM); ArrayResize(g_mtB, NC * NM); ArrayResize(g_mtAA, NC * NM); ArrayResize(g_mtAB, NC * NM);
   ArrayResize(g_mtBB, NC * NM); ArrayResize(g_mtAH, 2 * NC * NM); ArrayResize(g_mtBH, 2 * NC * NM);
   ArrayInitialize(g_mtA, 0.0); ArrayInitialize(g_mtB, 0.0); ArrayInitialize(g_mtAA, 0.0); ArrayInitialize(g_mtAB, 0.0);
   ArrayInitialize(g_mtBB, 0.0); ArrayInitialize(g_mtAH, 0.0); ArrayInitialize(g_mtBH, 0.0);
   int u[MT_ND];
   double a[], bb[];
   ArrayResize(a, NM);
   ArrayResize(bb, NM);
   for(int k = 21; k < n - 1; k++)
     {
      MtState(q, k, ret, atr, atrL, e20, e50, stk, p20, p80, u);
      for(int m = 0; m < NM; m++)
        {
         a[m] = A[k * NM + m];
         bb[m] = B[k * NM + m];
        }
      int hf = q.t[k] < tMid ? 0 : 1;
      MtAdd(0, a, bb, hf);
      for(int d = 0; d < MT_ND; d++)
        {
         if(u[d] < 0)
            continue;
         int u1 = g_mtVO[d] + u[d];
         MtAdd(1 + u1, a, bb, hf);
         for(int d2 = d + 1; d2 < MT_ND; d2++)
            if(u[d2] >= 0)
               MtAdd(1 + MT_NSV + u1 * MT_NSV + g_mtVO[d2] + u[d2], a, bb, hf);
        }
     }
   ArrayFree(A);
   ArrayFree(B);
   //--- nomi delle misure
   string mn[];
   ArrayResize(mn, NM);
   mn[0] = hn + " rialzista";
   mn[1] = hn + " espansione";
   mn[2] = hn + " massimo presto";
   mn[3] = hn + " minimo presto";
   for(int li = 0; li < nl; li++)
     {
      mn[4 + 3 * li] = TfNm(ls[li]) + " continua";
      mn[5 + 3 * li] = TfNm(ls[li]) + " rottura su prosegue";
      mn[6 + 3 * li] = TfNm(ls[li]) + " rottura giu' prosegue";
     }
   string lnm = "";
   for(int li = 0; li < nl; li++)
      lnm += (li > 0 ? ", " : "") + TfNm(ls[li]);
   string desc = "Ogni candela " + hn + " riceve uno stato noto alla sua apertura (" + I2S(MT_ND) + " dimensioni, come i contesti del " +
                 "rischio/rendimento: candela precedente, dove ha chiuso, trend, volatilit&agrave;, apertura, ampiezza, candele di fila, " +
                 "posizione nel range delle ultime 20). Per ogni stato: cosa fa la candela " + hn + " (rialzista = chiude sopra l'apertura; " +
                 "espansione = range oltre 1,33 volte la mediana delle 20 precedenti; massimo / minimo presto = fatto nel primo terzo della " +
                 "candela) e cosa fanno al suo interno i timeframe " + lnm + " (continua = la candela va nella stessa direzione della " +
                 "precedente; rottura su / gi&ugrave; prosegue = dopo una chiusura oltre il massimo / minimo delle 8 candele precedenti arriva " +
                 "prima a +1 ATR(14) che a -1 ATR, entro 16 candele). Ogni casella: quota dello stato e z contro tutte le altre candele " + hn +
                 " (non contro il 50%), con errore robusto ai casi raggruppati nella stessa candela; blu = pi&ugrave; degli altri, rosso = " +
                 "meno. Candele " + hn + " complete dalla 22a: " + I2S(n - 22) + "; prima met&agrave; fino al " + TimeToString(tMid, TIME_DATE) + ". " +
                 (InpRollSkip ? "Le barre nella finestra del rollover sono escluse da tutte le candele. " : "");
   SecStart("Timeframe alto -> basso: " + hn + " e dentro " + lnm, desc);
   R(g_repMtf, "");
   R(g_repMtf, "=== " + hn + " -> " + lnm + " ===");
   R(g_repMtf, "Metodo: " + desc);
   //--- stato attuale: la candela in corso
   int uc[MT_ND];
   MtState(q, n - 1, ret, atr, atrL, e20, e50, stk, p20, p80, uc);
   string cur = "Stato attuale (candela " + hn + " in corso dal " + TimeToString(q.t[n - 1], TIME_DATE | TIME_MINUTES) + "):";
   W("<p><b>" + cur + "</b></p><ul>");
   R(g_repMtf, cur);
   for(int d = 0; d < MT_ND; d++)
     {
      if(uc[d] < 0)
         continue;
      int cell = 1 + g_mtVO[d] + uc[d];
      string ln = MT_DIM[d] + " = " + g_mtLab[g_mtVO[d] + uc[d]] + " (" + DoubleToString(g_mtB[cell * NM], 0) + " candele):";
      for(int m = 0; m < NM; m++)
        {
         double p, p2, z, ph1, ph2;
         bool st;
         if(!MtZ(cell, m, m < 4 ? 30 : 100, p, p2, z, ph1, ph2, st))
            continue;
         ln += " " + mn[m] + " " + FP(p, 1) + "% (altri " + FP(p2, 1) + "%, z " + ZS(z) + ")" + (m < NM - 1 ? ";" : "");
        }
      W("<li>" + ln + "</li>");
      R(g_repMtf, "  " + ln);
     }
   W("</ul>");
   //--- stati singoli: tabella completa
   string hd = "Stato|Candele";
   for(int m = 0; m < NM; m++)
      hd += "|" + mn[m];
   THead(hd);
   R(g_repMtf, "[Stati singoli: quota dello stato, degli altri e z; meta' 1 / 2 = quota dello stato nelle due meta' (* = verso diverso)]");
   for(int cell = 0; cell <= MT_NSV; cell++)
     {
      if(cell > 0)
        {
         int uu = cell - 1, d = g_mtDimOf[uu];
         if(uu == g_mtVO[d])
           {
            Grp(MT_DIM[d], NM + 2);
            R(g_repMtf, "  " + MT_DIM[d] + ":");
           }
        }
      double nC = g_mtB[cell * NM];
      if(nC < 30)
         continue;
      string lab = cell == 0 ? "Tutte le candele" : g_mtLab[cell - 1];
      string row = "<tr>" + TD(lab) + TD(DoubleToString(nC, 0));
      string tx = "    " + lab + " (N " + DoubleToString(nC, 0) + "):";
      for(int m = 0; m < NM; m++)
        {
         double sb = g_mtB[cell * NM + m];
         if(cell == 0)
           {
            double pa = sb > 0 ? g_mtA[m] / sb : Nan();
            row += TD(FP(pa, 1) + "%");
            tx += " " + mn[m] + " " + FP(pa, 1) + "%" + (m < NM - 1 ? ";" : "");
            continue;
           }
         double p, p2, z, ph1, ph2;
         bool st;
         if(!MtZ(cell, m, m < 4 ? 30 : 100, p, p2, z, ph1, ph2, st))
           {
            row += TD("-");
            continue;
           }
         row += TDc(FP(p, 1) + "% <small>z " + ZS(z) + (st ? "" : "*") + "</small>", PCol(z, 0, 5));
         tx += " " + mn[m] + " " + FP(p, 1) + "% (altri " + FP(p2, 1) + "%, z " + ZS(z) + "; meta' " + FP(ph1, 1) + " / " + FP(ph2, 1) + (st ? "" : " *") + ")" +
               (m < NM - 1 ? ";" : "");
         if(HiKeep(16, z))
            HiAdd(16, z, "[" + hn + "] " + MtCell(cell) + " (N " + DoubleToString(nC, 0) + "): " + mn[m] + " " + FP(p, 1) + "% contro " + FP(p2, 1) +
                  "% nelle altre candele, meta' " + FP(ph1, 1) + " / " + FP(ph2, 1) + (st ? " (stabile)" : " (non stabile)"));
        }
      W(row + "</tr>");
      R(g_repMtf, tx);
     }
   TEnd();
   //--- coppie di stati: riepilogo, le piu' lontane dagli altri e appendice con tutte
   double key[];
   int nk = 0;
   ArrayResize(key, 0, 4096);
   g_txMtfAll.Add("");
   g_txMtfAll.Add("[" + hn + " -> " + lnm + ": tutte le coppie di stati con almeno 30 candele; per ogni misura quota della coppia e z contro le altre candele, * = verso diverso nelle due meta']");
   for(int cell = 1 + MT_NSV; cell < NC; cell++)
     {
      double nC = g_mtB[cell * NM];
      if(nC < 30)
         continue;
      string tx = "  " + MtCell(cell) + " (N " + DoubleToString(nC, 0) + "):";
      for(int m = 0; m < NM; m++)
        {
         double p, p2, z, ph1, ph2;
         bool st;
         if(!MtZ(cell, m, m < 4 ? 30 : 100, p, p2, z, ph1, ph2, st))
            continue;
         tx += " " + mn[m] + " " + FP(p, 1) + "% (z " + ZS(z) + (st ? "" : "*") + ");";
         if(HiKeep(17, z))
            HiAdd(17, z, "[" + hn + "] " + MtCell(cell) + " (N " + DoubleToString(nC, 0) + "): " + mn[m] + " " + FP(p, 1) + "% contro " + FP(p2, 1) +
                  "% nelle altre candele, meta' " + FP(ph1, 1) + " / " + FP(ph2, 1) + (st ? " (stabile)" : " (non stabile)"));
         if(nC >= 50 && st)
           {
            ArrayResize(key, nk + 1, 4096);
            key[nk++] = MathFloor(MathMin(MathAbs(z), 999.0) * 1000.0) * 16777216.0 + (cell * NM + m);
           }
        }
      g_txMtfAll.Add(tx);
     }
   ArraySort(key);
   W("<h3>Coppie di stati pi&ugrave; lontane dalle altre candele (almeno 50 candele, stesso verso nelle due met&agrave;; tutte nell'appendice F)</h3>");
   THead("Coppia di stati|Candele|Misura|Coppia|Altre candele|z|Met&agrave; 1 / 2");
   R(g_repMtf, "[Coppie di stati piu' lontane dalle altre candele: almeno 50 candele, stesso verso nelle due meta' (tutte nell'appendice F)]");
   int shown = 0;
   for(int j = nk - 1; j >= 0 && shown < 40; j--)
     {
      shown++;
      int id = (int)((long)key[j] % 16777216), cell = id / NM, m = id % NM;
      double p, p2, z, ph1, ph2;
      bool st;
      MtZ(cell, m, m < 4 ? 30 : 100, p, p2, z, ph1, ph2, st);
      double nC = g_mtB[cell * NM];
      W("<tr><td style='text-align:left;white-space:normal'>" + MtCell(cell) + "</td>" + TD(DoubleToString(nC, 0)) + TD(mn[m]) + TD(FP(p, 1) + "%") +
        TD(FP(p2, 1) + "%") + TDc(ZS(z), PCol(z, 0, 5)) + TD(FP(ph1, 1) + " / " + FP(ph2, 1)) + "</tr>");
      R(g_repMtf, "    z " + ZS(z) + " | " + MtCell(cell) + " (N " + DoubleToString(nC, 0) + "): " + mn[m] + " " + FP(p, 1) + "% contro " +
        FP(p2, 1) + "%, meta' " + FP(ph1, 1) + " / " + FP(ph2, 1));
     }
   TEnd();
   SecEnd();
   q.Free();
  }

void MtfTab(CSeries &b, const int barSec)
  {
   g_repMtf = "";
   g_txMtfAll.Clear();
   MtSetup();
   if(b.n < 5000)
     {
      SecStart("Timeframe alto -> basso", "");
      W("<p class='muted'>Servono dati M1 o M5.</p>");
      SecEnd();
      return;
     }
   int hs[3] = {14400, 86400, 604800};
   for(int i = 0; i < 3 && !IsStopped(); i++)
     {
      MtHtf(b, barSec, hs[i]);
      PrintFormat("[MarketProfiler] timeframe alto -> basso %s fatto", TfNm(hs[i]));
     }
   ArrayFree(g_mtA); ArrayFree(g_mtB); ArrayFree(g_mtAA); ArrayFree(g_mtAB); ArrayFree(g_mtBB); ArrayFree(g_mtAH); ArrayFree(g_mtBH);
  }

void HiTab(void)
  {
   g_repHi = "";
   g_txHiAll.Clear();
   int c3[HI_NMOD], c2[HI_NMOD];
   ArrayInitialize(c3, 0);
   ArrayInitialize(c2, 0);
   for(int i = 0; i < g_hiN; i++)
     {
      if(MathAbs(g_hiZ[i]) >= 3)
         c3[g_hiM[i]]++;
      else
         c2[g_hiM[i]]++;
     }
   SecStart("Riepilogo: cosa si discosta dal caso in tutte le analisi",
            "Ogni analisi confronta il reale con un riferimento (direzione casuale con la stessa volatilit&agrave;, livello finto, " +
            "tutti i periodi, aspettativa zero, stessa ora, placebo con direzione a caso nello stesso istante) e ne calcola z. " +
            "Qui sono raccolti tutti i risultati con <b>|z| &ge; 3</b> (difficili " +
            "da ottenere per caso) e, sotto, quelli tra <b>2 e 3</b> (indizi). <b>Attenzione ai confronti multipli</b>: su molti " +
            "confronti alcuni superano la soglia per puro caso. Con confronti indipendenti se ne aspettano lo 0,27% oltre 3 e il 4,3% " +
            "tra 2 e 3 (colonne 'attesi per caso'); molti confronti sono per&ograve; correlati (stessi giorni, stessi trade con " +
            "obiettivi diversi), quindi l'atteso &egrave; solo un ordine di grandezza. Un risultato &egrave; pi&ugrave; credibile se " +
            "ritorna in forme diverse (pi&ugrave; timeframe, entrambe le met&agrave; del campione, misure concordi) e se ha una " +
            "spiegazione di mercato. Il rischio/rendimento di ogni broker &egrave; contato a parte: gli stessi trade con costi " +
            "diversi. Nessun risultato &egrave; tolto dalle schede: qui c'&egrave; solo la selezione. Il testo &egrave; nella " +
            "scheda Testi &rarr; Riepilogo.");
   THead("Analisi|Confronti|Oltre z 3|Attesi per caso|Tra z 2 e 3|Attesi per caso");
   R(g_repHi, "RIEPILOGO - risultati lontani dal caso (|z| >= 3 difficile per caso, 2-3 indizio; attesi per caso = confronti x 0,27% e x 4,3% " +
     "se indipendenti, ma molti sono correlati)");
   for(int m = 0; m < HI_NMOD; m++)
     {
      if(HI_NAME[m] == "")
         continue;
      int n = g_hiCnt[m];
      W("<tr>" + TD(HI_NAME[m]) + TD(n > 0 ? I2S(n) : "non calcolato") + TDc(I2S(c3[m]), c3[m] > 3 * 0.0027 * n + 2 ? "rgba(59,130,246,0.35)" : "") +
        TD(F(0.0027 * n, 1)) + TD(I2S(c2[m])) + TD(F(0.0428 * n, 1)) + "</tr>");
      R(g_repHi, "  " + HI_NAME[m] + ": " + (n > 0 ? I2S(n) + " confronti, oltre |z| 3: " + I2S(c3[m]) + " (attesi per caso " + F(0.0027 * n, 1) +
        "), tra 2 e 3: " + I2S(c2[m]) + " (attesi " + F(0.0428 * n, 1) + ")" : "non calcolato"));
     }
   TEnd();
   SecEnd();
   double key[];
   for(int m = 0; m < HI_NMOD; m++)
     {
      if(HI_NAME[m] == "" || c3[m] + c2[m] == 0)
         continue;
      int nk = 0;
      ArrayResize(key, c3[m] + c2[m]);
      for(int i = 0; i < g_hiN; i++)
         if(g_hiM[i] == m)
            key[nk++] = MathFloor(MathMin(MathAbs(g_hiZ[i]), 999.0) * 1000.0) * 16777216.0 + i;
      ArraySort(key);
      SecStart(HI_NAME[m], I2S(c3[m]) + " risultati oltre |z| 3 e " + I2S(c2[m]) + " tra 2 e 3, su " + I2S(g_hiCnt[m]) +
               " confronti. Ordinati per |z|; blu = pi&ugrave; del riferimento, rosso = meno.");
      //--- appendice del rapporto: tutti i risultati della sezione, senza limiti, ordinati per |z|
      g_txHiAll.Add("");
      g_txHiAll.Add("[" + HI_NAME[m] + "] " + I2S(g_hiCnt[m]) + " confronti, oltre |z| 3: " + I2S(c3[m]) + " (attesi per caso " +
                    F(0.0027 * g_hiCnt[m], 1) + "), tra 2 e 3: " + I2S(c2[m]) + " (attesi " + F(0.0428 * g_hiCnt[m], 1) + ")");
      for(int j = nk - 1; j >= 0; j--)
        {
         int i = (int)((long)key[j] % 16777216);
         g_txHiAll.Add("    z " + ZS(g_hiZ[i]) + " | " + g_hiT[i]);
        }
      R(g_repHi, "");
      R(g_repHi, "[" + HI_NAME[m] + "] " + I2S(g_hiCnt[m]) + " confronti");
      for(int pass = 0; pass < 2; pass++)
        {
         int cap = pass == 0 ? 80 : 40, shown = 0, tot = pass == 0 ? c3[m] : c2[m];
         if(tot == 0)
            continue;
         string tt = pass == 0 ? "Oltre |z| 3" : "Tra |z| 2 e 3 (indizi)";
         W("<h3>" + tt + " (" + I2S(tot) + ")</h3>");
         THead("z|Risultato");
         R(g_repHi, "  " + tt + " (" + I2S(tot) + "):");
         for(int j = nk - 1; j >= 0 && shown < cap; j--)
           {
            int i = (int)((long)key[j] % 16777216);
            double z = g_hiZ[i];
            if((pass == 0) != (MathAbs(z) >= 3))
               continue;
            W("<tr>" + TDc(ZS(z), PCol(z, 0, 6)) + "<td style='text-align:left;white-space:normal'>" + g_hiT[i] + "</td></tr>");
            R(g_repHi, "    z " + ZS(z) + " | " + g_hiT[i]);
            shown++;
           }
         TEnd();
         if(tot > shown)
           {
            W("<p class='muted'>Altri " + I2S(tot - shown) + " con |z| pi&ugrave; basso: tutti in Tutti i risultati &rarr; Riepilogo e " +
              "nell'appendice A del rapporto completo.</p>");
            R(g_repHi, "    ... altri " + I2S(tot - shown) + " con |z| piu' basso: tutti nell'appendice A");
           }
        }
      SecEnd();
     }
  }

// scheda con un testo da copiare
void TxTab(const string id, const string title, const string desc, const string txt)
  {
   W("<div class='tab' id='tab-" + id + "' hidden>");
   SecStart(title, desc);
   W("<button class='cp' onclick=\"cp(this,'ta-" + id + "')\">Copia tutto</button><textarea id='ta-" + id + "' readonly>");
   W(txt);
   W("</textarea>");
   SecEnd();
   W("</div>");
  }

// scheda con un testo lungo (a blocchi)
void TxTabT(const string id, const string title, const string desc, const string head, CText &t)
  {
   W("<div class='tab' id='tab-" + id + "' hidden>");
   SecStart(title, desc);
   W("<button class='cp' onclick=\"cp(this,'ta-" + id + "')\">Copia tutto</button><textarea id='ta-" + id + "' readonly>");
   W(head);
   WT(t);
   W("</textarea>");
   SecEnd();
   W("</div>");
  }

// legenda dei termini usati in tutto il rapporto
string RepLegend(void)
  {
   return "LEGENDA\n" +
          "  R = multipli del rischio (1 R = distanza dello stop); aspettativa = guadagno medio per trade in R.\n" +
          "  z = di quante deviazioni standard un risultato si allontana dal suo riferimento: entro +/-2 compatibile con il caso, oltre +/-3 " +
          "difficile per caso. Su molti confronti alcuni superano la soglia per caso: il riepilogo dice quanti se ne aspettano.\n" +
          "  atteso = lo stesso calcolo sulle stesse barre con la direzione di ogni barra estratta a caso (stessa volatilita' minuto per minuto).\n" +
          "  placebo = la stessa operazione nello stesso istante con direzione a caso; vantaggio o z contro il placebo = quanto conta la direzione.\n" +
          "  stessa ora = confronto con la media di tutti i trade della stessa ora del giorno: cosa aggiunge il contesto all'orario.\n" +
          "  livello finto = lo stesso calcolo su un livello spostato (effetto del livello = vero meno finto).\n" +
          "  meta' 1 / meta' 2 = lo stesso risultato nella prima e nella seconda meta' dello storico; stabile = stesso segno in entrambe; " +
          "* = segno diverso in una delle due.\n" +
          "  lorda / netta = senza / con spread, commissione, slittamento e swap del broker; netta peggiore = il broker con il risultato piu' basso.\n" +
          "  pb = punti base del prezzo (1 pb = 0,01%); costo di pareggio = costo per trade che azzera l'aspettativa lorda.\n" +
          "  N = trade o giorni; N effettivo = corretto per i trade che si sovrappongono nel tempo.\n" +
          "  ORB: range = minuti del range iniziale dall'orario di inizio, finestra = minuti osservati dopo il range, conferma = candela " +
          "(M1, M5, M15, M30, H1) che deve chiudere fuori dal range; eventi = cosa fa il prezzo sulle candele di conferma (nessun tocco, solo " +
          "tocchi, continua, rientra e resta, rientra e riparte, rientra e si gira).\n" +
          "  rollover = NY 17:00, mezzanotte del broker: lo spread si allarga e sui dati bid compaiono punte in basso senza scambi veri; " +
          "ora buca = attivita' e volume sotto 0.6 del normale.\n" +
          "  VR = rapporto di varianza: 1 = prezzo casuale; sopra 1 i movimenti continuano (trend), sotto tornano indietro (mean " +
          "reversion); VR(q) = movimenti di q candele.\n" +
          "  seguito medio = movimento dopo, nella direzione del movimento prima, in multipli del movimento tipico di quell'orario " +
          "(0 = nessun legame, positivo = continua, negativo = torna indietro).\n" +
          "  stato (alto -> basso) = condizione della candela del timeframe alto nota alla sua apertura; z contro tutte le altre candele.\n";
  }

// indice del rapporto completo
string RepIndex(void)
  {
   string t = "\nINDICE\n  PARTE PRINCIPALE (da leggere; per l'analisi in chat basta questa)\n" +
              "    1. Riepilogo: i risultati piu' lontani dal caso di tutte le analisi\n    2. Periodo in corso\n" +
              "    3. Timeframe: dal minuto all'anno (movimento iniziale, spostamento piu' ampio, mean reversion, quando avvengono)\n" +
              "    4. Eventi e sessioni: swing, rotture, impulsi, notizie, gap, ore buche e rollover, orari chiave e sessioni\n" +
              "    5. ORB: rottura del range iniziale a tutti gli orari, candele di conferma, continuazione ed eventi\n" +
              "    6. Livelli chiave\n    7. Direzione\n    8. Rischio/rendimento lordo: riepilogo per timeframe, contesti migliori e peggiori\n";
   for(int p = 1; p < NPRF; p++)
      t += "    9." + I2S(p) + " Rischio/rendimento netto " + g_cp[p].name + ": costi, riepilogo, contesti migliori e peggiori\n";
   t += "    10. Strategie una posizione alla volta e regole per lo Strategy Tester\n    11. Coppie di contesti: le piu' solide e le piu' negative\n" +
        "    12. Volume\n    13. Persistenza: dove il prezzo continua e dove torna indietro (per timeframe e per ora del giorno)\n" +
        "    14. Dal timeframe alto al basso: stato della candela H4, D1 e settimanale e comportamento dei timeframe inferiori\n" +
        "  APPENDICI (tutti i risultati per esteso, da consultare: sono molto lunghe)\n" +
        "    A. Riepilogo: tutti i risultati oltre |z| 2\n    B. Rischio/rendimento lordo: tutti i contesti\n";
   for(int p = 1; p < NPRF; p++)
      t += "    C." + I2S(p) + " Rischio/rendimento netto " + g_cp[p].name + ": tutti i contesti\n";
   t += "    D. ORB: tutte le combinazioni\n    E. Coppie di contesti: tutte\n    F. Dal timeframe alto al basso: tutte le coppie di stati\n\n";
   return t + RepLegend();
  }

// intestazione dell'appendice ORB: come leggere una riga
string OrbAllHead(void)
  {
   return "Una riga per combinazione (orario locale della piazza, orario dei dati, range, finestra, giorni, rottura al primo tocco), poi " +
          "una riga per candela di conferma: conferme = % dei giorni con una candela chiusa fuori dal range, dopo quanti minuti, forza = " +
          "quanto chiude oltre il livello (range); lorde = aspettativa lorda in R e (z) di ogni operazione: S1:1 segui 1:1, S1:2 segui " +
          "1:2 con stop all'altro lato, S1:2m segui 1:2 con stop a meta' range, St segui a tempo (chiude a fine finestra), F1:1 fade " +
          "1:1, F1:0,5 fade 1:0,5, F1:0,5m fade 1:0,5 con obiettivo a meta' range; netta peggiore e costo di pareggio di S1:1; " +
          "migliore netta = operazione con lo z netto del broker peggiore piu' alto (placebo = z contro la stessa operazione con " +
          "direzione a caso); a favore/contro = estensione mediana dalla chiusura di conferma (range) e z della differenza; eventi = " +
          "reale/atteso % nell'ordine nessun tocco, solo tocchi, continua, rientra e resta, rientra e riparte, rientra e si gira, poi " +
          "candele che toccano senza chiudere fuori e ora del rientro e dell'evento finale (mediane). Orari equivalenti e orari a " +
          "mercato chiuso sono solo nel CSV.\n";
  }

string Css(void)
  {
   return ":root{--bg:#0b0f17;--card:#111827;--fg:#e5e7eb;--mut:#9ca3af;--line:#1f2937;--acc:#3b82f6}" +
          "*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}" +
          "header{position:sticky;top:0;z-index:10;background:var(--bg);border-bottom:1px solid var(--line);padding:10px 16px 0}" +
          "header h1{font-size:20px;margin:0 0 2px}header p{margin:0 0 8px;color:var(--mut);font-size:12px}" +
          "nav{display:flex;gap:4px;overflow-x:auto;padding-bottom:8px}" +
          "nav button{background:#0f172a;color:var(--mut);border:1px solid var(--line);border-radius:6px;padding:6px 11px;cursor:pointer;white-space:nowrap;font:inherit;font-size:13px}" +
          "nav button.on{background:var(--acc);color:#fff;border-color:var(--acc)}" +
          "nav.tx{padding-top:0}nav.tx span{color:var(--mut);font-size:12px;align-self:center;white-space:nowrap;margin-right:4px}" +
          "main{max-width:1500px;margin:0 auto;padding:12px 16px}h2{font-size:18px;margin:0 0 6px}h3{font-size:15px;margin:16px 0 6px}" +
          "section{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin:12px 0}" +
          ".muted{color:var(--mut)}.desc{color:var(--mut);margin:0 0 10px;max-width:1100px}" +
          ".tw{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:12.5px;font-variant-numeric:tabular-nums}" +
          "th,td{padding:5px 8px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap}" +
          "th:first-child,td:first-child{text-align:left}th{color:var(--mut);font-weight:600}" +
          "tr.grp td{color:var(--acc);font-weight:600;padding-top:12px;text-align:left}tr.base td{color:var(--mut);font-style:italic}" +
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
   return "function cp(b,id){var t=document.getElementById(id||'rep');t.select();try{document.execCommand('copy');}catch(e){}" +
          "if(navigator.clipboard)navigator.clipboard.writeText(t.value);b.textContent='Copiato';}" +
          "function show(id){if(!document.getElementById('tab-'+id))id='edge';" +
          "var t=document.querySelectorAll('.tab');for(var i=0;i<t.length;i++)t[i].hidden=(t[i].id!=='tab-'+id);" +
          "var b=document.querySelectorAll('nav button');for(var j=0;j<b.length;j++)b[j].className=(b[j].getAttribute('data-tab')===id)?'on':'';" +
          "if(location.hash!=='#'+id)history.replaceState(null,'','#'+id);window.scrollTo(0,0);}" +
          "var bs=document.querySelectorAll('nav button');for(var k=0;k<bs.length;k++)bs[k].onclick=function(){show(this.getAttribute('data-tab'));};" +
          "show(location.hash.slice(1)||'edge');";
  }

//+------------------------------------------------------------------+
//| MarketProfilerEdge.mqh - modulo aggiunto a MarketProfiler.mq5     |
//| Schede 'Sintesi edge' e 'Bias e impulsi'.                         |
//| Versione 1.1. Testato in un banco di prova C++ (MQL5 tradotto)    |
//| su serie sintetiche: nessun avviso del compilatore, nessun        |
//| indice fuori limite, calibrazione dei falsi positivi verificata.  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| SINTESI EDGE E BIAS (modulo aggiunto)                             |
//| - Scheda 'Sintesi edge': verdetto, scorecard delle strategie,     |
//|   controllo dei test multipli (FDR, Bonferroni), bias robusti,    |
//|   carattere dei timeframe.                                        |
//| - Scheda 'Bias e impulsi': bias di ora, blocchi di 4/6/8/12 ore,  |
//|   giorno, mese, trimestre, semestre, anno; ora x giorno; massimo  |
//|   e minimo della settimana; ora dell'impulso piu' forte e del     |
//|   massimo/minimo del giorno e cosa li precede.                    |
//+------------------------------------------------------------------+
#define ED_MB   18   // modulo del riepilogo: bias del calendario
#define ED_MT   19   // modulo del riepilogo: impulso piu' forte, massimo e minimo del giorno
#define BX_NA   14   // accumulatori per categoria e meta' del campione
#define BX_NM   8    // metriche per riga di tabella
#define TG_NT   3    // bersagli del 'quando': impulso piu' forte, massimo, minimo del giorno
#define TG_NP   2    // bersagli del 'cosa precede': impulso piu' forte del giorno (a posteriori), impulso forte tra il 2% dei movimenti piu' ampi dell'ora (causale)
#define TG_NF   5    // caratteristiche che precedono il bersaglio
#define TG_NC   4    // classi al massimo per caratteristica

input double InpEdRefCostBp = 0.0; // Sintesi edge: costo per trade in punti base da usare se i costi del broker non sono misurati (0 = nessuno)

string g_repBias = "", g_repEdge = "";
int    g_edCbSrc = 0;   // origine del costo usato nei controlli: 0 assente, 1 misurato dal broker, 2 riferimento manuale

//--- candidati strategia (R/R e ORB)
int    g_edNC = 0;
string g_edSrc[], g_edTf[], g_edOp[], g_edCx[];
int    g_edKd[], g_edRl[], g_edN[], g_edSn[], g_edYp[], g_edYn[], g_edDk[];
double g_edZ[], g_edE[], g_edZh[], g_edZp[], g_edBe[], g_edCb[], g_edSe[], g_edTy[], g_edPf[];
bool   g_edSt[];

//--- controllo dei test multipli sul riepilogo
bool   g_edFdr[];
double g_edZb[];
int    g_edNfdr[], g_edN3[];

//--- test del modulo Bias (tutti i confronti, anche quelli sotto |z| 2)
int    g_bxNT = 0;
double g_bxTz[];
bool   g_bxTst[], g_bxTfd[];
int    g_bxTm[], g_bxTk[];   // modulo del riepilogo e tipo (0 direzione, 1 volatilita', 2 timing e struttura, 3 cosa precede)
string g_bxTtx[];

//--- righe delle tabelle per timeframe
int    g_bxRN = 0;
int    g_bxRTf[], g_bxRCat[], g_bxRn[], g_bxRT[];
bool   g_bxRIn[];
string g_bxRLb[];
double g_bxRMed[], g_bxRV[], g_bxRZ[];

//--- ora x giorno della settimana (indice ora * 7 + giorno)
int    g_bxHn[168], g_bxHtu[168], g_bxHtr[168];
double g_bxHu[168], g_bxHr[168], g_bxHzu[168], g_bxHzr[168], g_bxHbu[24];
int    g_bxHbn[24];

//--- massimo e minimo della settimana (indice tipo * 7 + giorno; tipo 0 massimo, 1 minimo)
int    g_bxWn = 0;
int    g_bxWt[14];
double g_bxWo[14], g_bxWe[14], g_bxWz[14];

//--- ora dell'impulso piu' forte, del massimo e del minimo del giorno (indice tipo * 24 + ora)
int    g_tgNd = 0;
int    g_tgDays[24], g_tgT[72], g_tgUt[24], g_tgCases[TG_NP];
double g_tgO[72], g_tgE[72], g_tgZ[72], g_tgUn[24], g_tgUu[24], g_tgUz[24];
//--- caratteristiche prima del bersaglio (indice (tipo * TG_NF + caratteristica) * TG_NC + classe, tipo < TG_NP)
double g_tgFO[TG_NP * TG_NF * TG_NC], g_tgFE[TG_NP * TG_NF * TG_NC], g_tgFZ[TG_NP * TG_NF * TG_NC], g_tgFn[TG_NP * TG_NF];
int    g_tgFt[TG_NP * TG_NF * TG_NC];
double g_tgAC[];

double g_bxInfl[NTF];    // fattore di inflazione della varianza del range per timeframe (persistenza della volatilita')
datetime g_bxLast = 0;   // ora dell'ultima barra dei dati (per il bias del momento)

//--- varianza del rendimento di ogni ora del giorno (profilo intragiornaliero della volatilita')
double g_bxHv[24];

//--- tabelle costruite durante il calcolo
string g_bxDig = "", g_bxDigTx = "", g_bxYr = "", g_bxYrTx = "";

string TG_TN[TG_NT] = {"Impulso pi&ugrave; forte del giorno", "Massimo del giorno", "Minimo del giorno"};
string TG_PN[TG_NP] = {"Impulso pi&ugrave; forte del giorno (scelto a posteriori)", "Impulso forte (tra il 2% dei movimenti pi&ugrave; ampi di quell'ora)"};
string TG_FN[TG_NF] = {"Le 3 ore prima", "Compressione delle 3 ore prima", "Livelli di ieri gi&agrave; toccati oggi", "Posizione nel range di oggi",
                       "Volume dell'ora prima (RVOL)"};
int    TG_NCL[TG_NF] = {3, 3, 4, 3, 3};
string TG_CL[TG_NF * TG_NC] = {"a favore (oltre 0,5 ATR)", "laterali", "contro (oltre 0,5 ATR)", "",
                               "range basso (terzile inferiore)", "range medio", "range alto (terzile superiore)", "",
                               "solo il livello opposto (sweep)", "solo il livello nella direzione", "entrambi", "nessuno",
                               "nel terzo opposto", "nel mezzo", "nel terzo nella direzione", "",
                               "sotto 0.8", "0.8-1.5", "oltre 1.5", ""};

//+------------------------------------------------------------------+
//| Statistica: coda della normale, soglie dei test multipli, FDR     |
//+------------------------------------------------------------------+
// complemento della funzione errore (Numerical Recipes, errore relativo < 1.2e-7 anche nelle code)
double EdErfc(const double x)
  {
   double z = MathAbs(x), t = 1.0 / (1.0 + 0.5 * z);
   double r = t * MathExp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 + t * (-0.18628806 +
              t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
   return x >= 0 ? r : 2.0 - r;
  }

// probabilita' bilaterale di uno z
double EdP2(const double z)
  {
   if(!MathIsValidNumber(z))
      return 1.0;
   return EdErfc(MathAbs(z) / 1.4142135623730951);
  }

// z bilaterale la cui probabilita' vale alpha / m (soglia di Bonferroni su m confronti)
double EdZCrit(const double alpha, const double m)
  {
   double p = alpha / (m < 1 ? 1.0 : m), lo = 0.0, hi = 40.0;
   for(int it = 0; it < 80; it++)
     {
      double mid = 0.5 * (lo + hi);
      if(EdP2(mid) > p)
         lo = mid;
      else
         hi = mid;
     }
   return 0.5 * (lo + hi);
  }

// indici ordinati per valore decrescente (chiave = valore * 100 + indice: ordine esatto solo al centesimo)
void EdOrder(const double &v[], const int n, int &ord[])
  {
   ArrayResize(ord, n);
   if(n <= 0)
      return;
   double key[];
   ArrayResize(key, n);
   for(int i = 0; i < n; i++)
     {
      double x = MathIsValidNumber(v[i]) ? v[i] : -900.0;
      key[i] = MathFloor((MathMax(-900.0, MathMin(x, 9000.0)) + 1000.0) * 100.0) * 16777216.0 + i;
     }
   ArraySort(key);
   for(int j = 0; j < n; j++)
      ord[j] = (int)((long)key[n - 1 - j] % 16777216);
  }

// controllo FDR di Benjamini-Hochberg: z[] sono gli z dei confronti piu' forti, m il numero totale di confronti
void EdBhFlags(const double &z[], const int n, const double m, const double q, bool &flag[])
  {
   ArrayResize(flag, n);
   if(n > 0)
      ArrayInitialize(flag, false);
   if(n <= 0 || !(m >= 1))
      return;
   double az[];
   ArrayResize(az, n);
   for(int i = 0; i < n; i++)
      az[i] = MathIsValidNumber(z[i]) ? MathAbs(z[i]) : 0.0;
   int ord[];
   EdOrder(az, n, ord);
   int best = 0;
   for(int j = 0; j < n; j++)
      if(az[ord[j]] > 0 && EdP2(az[ord[j]]) <= (j + 1) * q / m)
         best = j + 1;
   for(int k = 0; k < best; k++)
      flag[ord[k]] = true;
  }

// FDR per ogni sezione del riepilogo (i risultati registrati sono quelli con |z| >= 2, cioe' i piu' forti della sezione)
void EdFdrAll(void)
  {
   ArrayResize(g_edFdr, g_hiN);
   if(g_hiN > 0)
      ArrayInitialize(g_edFdr, false);
   ArrayResize(g_edZb, HI_NMOD);
   ArrayResize(g_edNfdr, HI_NMOD);
   ArrayResize(g_edN3, HI_NMOD);
   for(int m = 0; m < HI_NMOD; m++)
     {
      g_edZb[m] = EdZCrit(0.05, (double)MathMax(1, g_hiCnt[m]));
      g_edNfdr[m] = 0;
      g_edN3[m] = 0;
      int idx[];
      double zz[];
      int k = 0;
      ArrayResize(idx, g_hiN);
      ArrayResize(zz, g_hiN);
      for(int i = 0; i < g_hiN; i++)
         if(g_hiM[i] == m)
           {
            idx[k] = i;
            zz[k] = MathAbs(g_hiZ[i]);
            if(zz[k] >= 3)
               g_edN3[m]++;
            k++;
           }
      if(k == 0 || g_hiCnt[m] <= 0)
         continue;
      bool fl[];
      EdBhFlags(zz, k, (double)g_hiCnt[m], 0.05, fl);
      for(int j = 0; j < k; j++)
         if(fl[j])
           {
            g_edFdr[idx[j]] = true;
            g_edNfdr[m]++;
           }
     }
  }

//+------------------------------------------------------------------+
//| Candidati strategia                                               |
//+------------------------------------------------------------------+
void EdGrow(const int k)
  {
   ArrayResize(g_edSrc, k, 64); ArrayResize(g_edTf, k, 64); ArrayResize(g_edOp, k, 64); ArrayResize(g_edCx, k, 64);
   ArrayResize(g_edKd, k, 64); ArrayResize(g_edRl, k, 64); ArrayResize(g_edN, k, 64); ArrayResize(g_edSn, k, 64);
   ArrayResize(g_edYp, k, 64); ArrayResize(g_edYn, k, 64); ArrayResize(g_edDk, k, 64);
   ArrayResize(g_edZ, k, 64); ArrayResize(g_edE, k, 64); ArrayResize(g_edZh, k, 64); ArrayResize(g_edZp, k, 64);
   ArrayResize(g_edBe, k, 64); ArrayResize(g_edCb, k, 64); ArrayResize(g_edSe, k, 64); ArrayResize(g_edTy, k, 64);
   ArrayResize(g_edPf, k, 64); ArrayResize(g_edSt, k, 64);
  }

// costo tipico per trade del broker piu' caro tra quelli con costi disponibili, in punti base.
// Un costo nullo o negativo non e' un costo misurato (simboli personalizzati senza spread): vale come assente.
// Senza costi del broker vale il riferimento manuale InpEdRefCostBp, se positivo; altrimenti Nan.
double EdCostBp(void)
  {
   double cb = Nan();
   for(int p = 1; p < NPRF; p++)
      if(g_cp[p].on)
        {
         double x = CostBp(p);
         if(MathIsValidNumber(x) && x > 0 && (!MathIsValidNumber(cb) || x > cb))
            cb = x;
        }
   g_edCbSrc = 0;
   if(MathIsValidNumber(cb))
      g_edCbSrc = 1;
   else
      if(MathIsValidNumber(InpEdRefCostBp) && InpEdRefCostBp > 0)
        {
         cb = InpEdRefCostBp;
         g_edCbSrc = 2;
        }
   return cb;
  }

void EdgeReset(void)
  {
   g_repBias = "";
   g_repEdge = "";
   g_edCbSrc = 0;
   g_edNC = 0;
   EdGrow(0);
   g_bxNT = 0;
   ArrayResize(g_bxTz, 0); ArrayResize(g_bxTst, 0); ArrayResize(g_bxTfd, 0); ArrayResize(g_bxTm, 0); ArrayResize(g_bxTk, 0); ArrayResize(g_bxTtx, 0);
   g_bxRN = 0;
   ArrayResize(g_bxRTf, 0); ArrayResize(g_bxRCat, 0); ArrayResize(g_bxRn, 0); ArrayResize(g_bxRT, 0); ArrayResize(g_bxRIn, 0);
   ArrayResize(g_bxRLb, 0); ArrayResize(g_bxRMed, 0); ArrayResize(g_bxRV, 0); ArrayResize(g_bxRZ, 0);
   ArrayInitialize(g_bxHn, 0); ArrayInitialize(g_bxHtu, -1); ArrayInitialize(g_bxHtr, -1);
   ArrayInitialize(g_bxHu, 0.0); ArrayInitialize(g_bxHr, 0.0); ArrayInitialize(g_bxHzu, 0.0); ArrayInitialize(g_bxHzr, 0.0);
   ArrayInitialize(g_bxHbu, 0.0); ArrayInitialize(g_bxHbn, 0);
   g_bxWn = 0;
   ArrayInitialize(g_bxWt, -1); ArrayInitialize(g_bxWo, 0.0); ArrayInitialize(g_bxWe, 0.0); ArrayInitialize(g_bxWz, 0.0);
   g_tgNd = 0;
   ArrayInitialize(g_tgDays, 0); ArrayInitialize(g_tgT, -1); ArrayInitialize(g_tgUt, -1); ArrayInitialize(g_tgCases, 0);
   ArrayInitialize(g_tgO, 0.0); ArrayInitialize(g_tgE, 0.0); ArrayInitialize(g_tgZ, 0.0);
   ArrayInitialize(g_tgUn, 0.0); ArrayInitialize(g_tgUu, 0.0); ArrayInitialize(g_tgUz, 0.0);
   ArrayInitialize(g_tgFO, 0.0); ArrayInitialize(g_tgFE, 0.0); ArrayInitialize(g_tgFZ, 0.0); ArrayInitialize(g_tgFn, 0.0);
   ArrayInitialize(g_tgFt, -1);
   ArrayResize(g_tgAC, 0);
   ArrayInitialize(g_bxHv, 1.0);
   g_bxLast = 0;
   ArrayInitialize(g_bxInfl, 1.0);
   g_bxDig = "";
   g_bxDigTx = "";
   g_bxYr = "";
   g_bxYrTx = "";
  }

// hook nella simulazione una posizione alla volta di un candidato R/R (rs[p] e ok[p] per profilo di costo, 0 = lordo)
void EdgeAddRR(const string nm, const int c, const int id, SqR &rs[], bool &ok[])
  {
   int pw = -1;
   for(int p = 1; p < NPRF; p++)
      if(g_cp[p].on && ok[p] && (pw < 0 || rs[p].e < rs[pw].e))
         pw = p;
   if(pw < 0 && ok[0])
      pw = 0;
   int i = g_edNC++;
   EdGrow(g_edNC);
   g_edSrc[i] = "R/R";
   g_edTf[i] = nm;
   g_edOp[i] = RROpLab(g_ckI[c]);
   g_edCx[i] = g_ckLab[c];
   g_edKd[i] = g_ckKind[c];
   g_edRl[i] = id;
   g_edN[i] = g_ckNn[c];
   g_edZ[i] = g_ckZ[c];
   g_edE[i] = g_ckE[c];
   g_edSt[i] = g_ckSt[c];
   g_edZh[i] = g_ckZh[c];
   g_edZp[i] = g_ckZp[c];
   g_edBe[i] = g_ckBe[c];
   g_edCb[i] = EdCostBp();
   g_edSn[i] = 0;
   g_edSe[i] = Nan();
   g_edTy[i] = Nan();
   g_edPf[i] = Nan();
   g_edYp[i] = 0;
   g_edYn[i] = 0;
   g_edDk[i] = -1;
   if(pw >= 0 && ok[pw])
     {
      g_edSn[i] = rs[pw].n;
      g_edSe[i] = rs[pw].e;
      g_edTy[i] = rs[pw].n / rs[pw].yrs;
      g_edPf[i] = rs[pw].pf;
      g_edYp[i] = rs[pw].posY;
      g_edYn[i] = rs[pw].nY;
      g_edDk[i] = rs[pw].dd <= rs[pw].dd95 ? 1 : 0;
     }
  }

// candidati ORB: le regole scelte (netta del broker peggiore sopra la soglia, stabile, almeno 100 trade)
void EdgeAddOrb(void)
  {
   if(!InpOrb || g_orN <= 0 || ArraySize(g_otN) <= 0)
      return;
   for(int r = 0; r < g_orN; r++)
     {
      int tr = g_orX[r], sd = tr % 3, t = (tr / 3) % OB_NT, cf = tr / (3 * OB_NT), f = cf % g_obNF;
      int i = g_edNC++;
      EdGrow(g_edNC);
      g_edSrc[i] = "ORB";
      g_edTf[i] = ObTf(f);
      g_edOp[i] = OB_OP[t];
      g_edCx[i] = ObCfLab(cf) + ", " + OB_SIDE[sd];
      g_edKd[i] = 3;
      g_edRl[i] = 0;
      g_edN[i] = g_otN[tr];
      g_edZ[i] = g_otZw[tr];
      g_edE[i] = g_otEw[tr];
      g_edSt[i] = g_otSt[tr];
      g_edZh[i] = Nan();
      g_edZp[i] = g_otZp[tr];
      g_edBe[i] = g_otBe[tr];
      g_edCb[i] = EdCostBp();
      g_edSn[i] = g_otN[tr];
      g_edSe[i] = g_otEw[tr];
      g_edTy[i] = Nan();
      g_edPf[i] = Nan();
      g_edYp[i] = 0;
      g_edYn[i] = 0;
      g_edDk[i] = -1;
     }
  }

// numero di confronti ORB con almeno 100 trade su orari coperti (universo da cui sono scelte le regole)
double EdOrbTests(void)
  {
   double n = 0;
   int ntr = ArraySize(g_otN);
   if(!InpOrb || ntr <= 0)
      return 1.0;
   for(int tr = 0; tr < ntr; tr++)
      if(g_otN[tr] >= 100 && MathIsValidNumber(g_otZw[tr]) && g_osDay[tr / (3 * OB_NT) / g_obNF] >= g_obMinDay)
         n += 1;
   return MathMax(1.0, n);
  }

// numero di confronti tra cui e' stato scelto un candidato (per la soglia di Bonferroni)
double EdTests(const int i, const double orbT)
  {
   if(g_edKd[i] == 0)
      return 1.0;
   if(g_edKd[i] == 1)
      return (double)MathMax(1, MathMax(g_hiCnt[5], MathMax(g_hiCnt[6], g_hiCnt[7])));
   if(g_edKd[i] == 2)
      return (double)MathMax(1, g_hiCnt[8]);
   return orbT;
  }

// controlli di un candidato: 1 superato, 0 no, -1 non applicabile. Ritorna il livello: 3 robusto, 2 promettente, 1 indizio, 0 scartato.
// Se il costo del broker non e' noto (V = -1) il livello massimo e' 1: al lordo dei costi nessuna strategia e' robusta o promettente.
int EdChecks(const int i, const double mTests, int &ck[])
  {
   ArrayResize(ck, 8);
   ck[0] = g_edN[i] >= 100 ? 1 : 0;
   ck[1] = MathIsValidNumber(g_edZ[i]) && g_edZ[i] >= 3 ? 1 : 0;
   ck[2] = g_edSt[i] ? 1 : 0;
   ck[3] = (g_edKd[i] == 1 || g_edKd[i] == 2) ? (MathIsValidNumber(g_edZh[i]) && g_edZh[i] >= 2 ? 1 : 0) : -1;
   ck[4] = MathIsValidNumber(g_edZp[i]) ? (g_edZp[i] >= 2 ? 1 : 0) : -1;
   if(!MathIsValidNumber(g_edCb[i]))
      ck[5] = -1;
   else
      ck[5] = (MathIsValidNumber(g_edBe[i]) && g_edBe[i] >= 1.5 * g_edCb[i]) ? 1 : 0;
   if(g_edKd[i] == 3)
      ck[6] = g_edE[i] > 0 ? 1 : 0;
   else
      ck[6] = (MathIsValidNumber(g_edSe[i]) && g_edSe[i] > 0 && (g_edYn[i] < 3 || g_edYp[i] >= 0.6 * g_edYn[i])) ? 1 : 0;
   ck[7] = (MathIsValidNumber(g_edZ[i]) && g_edZ[i] >= EdZCrit(0.05, mTests)) ? 1 : 0;
   bool all7 = true, all8 = true;
   for(int k = 0; k < 8; k++)
      if(ck[k] == 0)
        {
         all8 = false;
         if(k < 7)
            all7 = false;
        }
   bool hint = MathIsValidNumber(g_edZ[i]) && g_edZ[i] >= 2 && g_edE[i] > 0 && g_edSt[i] && ck[5] != 0 && ck[6] != 0;
   if(ck[5] < 0)
      return hint ? 1 : 0;
   if(all8)
      return 3;
   if(all7)
      return 2;
   return hint ? 1 : 0;
  }

//+------------------------------------------------------------------+
//| BIAS: test, righe per timeframe, carattere dei timeframe          |
//+------------------------------------------------------------------+
string BX_MN[BX_NM] = {"% rialzista", "rendimento medio", "range mediano", "massimo nel primo terzo", "minimo nel primo terzo",
                       "% trend (restituisce al massimo il 25%)", "% mean reversion (restituisce almeno il 75%)", "restituito medio"};

// registra un confronto; ritorna il suo id (-1 se z non e' definito)
int BxAddTest(const int mod, const int kind, const double z, const bool st, const string txt)
  {
   if(!MathIsValidNumber(z))
      return -1;
   int i = g_bxNT++;
   ArrayResize(g_bxTz, g_bxNT, 1024);
   ArrayResize(g_bxTst, g_bxNT, 1024);
   ArrayResize(g_bxTfd, g_bxNT, 1024);
   ArrayResize(g_bxTm, g_bxNT, 1024);
   ArrayResize(g_bxTk, g_bxNT, 1024);
   ArrayResize(g_bxTtx, g_bxNT, 1024);
   g_bxTz[i] = z;
   g_bxTst[i] = st;
   g_bxTfd[i] = false;
   g_bxTm[i] = mod;
   g_bxTk[i] = kind;
   g_bxTtx[i] = txt;
   return i;
  }

// stessa direzione della differenza nelle due meta' del campione
bool BxStable(const double z, const double d0, const double d1)
  {
   if(!MathIsValidNumber(z) || !MathIsValidNumber(d0) || !MathIsValidNumber(d1) || z == 0 || d0 == 0 || d1 == 0)
      return false;
   return (d0 > 0) == (z > 0) && (d1 > 0) == (z > 0);
  }

// accumulatori: riga * 2 meta' * BX_NA
double BxT(const double &a[], const int r, const int idx) { return a[(r * 2) * BX_NA + idx] + a[(r * 2 + 1) * BX_NA + idx]; }
double BxH(const double &a[], const int r, const int hf, const int idx) { return a[(r * 2 + hf) * BX_NA + idx]; }

// differenza di una metrica (categoria contro tutti i periodi) in una meta' del campione
double BxDiff(const double &a[], const int r, const int rowAll, const int hf, const int m, const bool intra)
  {
   double n = BxH(a, r, hf, 0), nA = BxH(a, rowAll, hf, 0);
   if(n < 20 || nA < 20)
      return Nan();
   switch(m)
     {
      case 0:
         return BxH(a, r, hf, 1) / n - BxH(a, rowAll, hf, 1) / nA;
      case 1:
         return BxH(a, r, hf, 2) / n - BxH(a, rowAll, hf, 2) / nA;
      case 2:
        {
         double l = BxH(a, r, hf, 4), lA = BxH(a, rowAll, hf, 4);
         if(l < 10 || lA < 10)
            return Nan();
         return BxH(a, r, hf, 5) / l - BxH(a, rowAll, hf, 5) / lA;
        }
      case 3:
         return intra ? (BxH(a, r, hf, 7) - BxH(a, r, hf, 9)) / n : Nan();
      case 4:
         return intra ? (BxH(a, r, hf, 8) - BxH(a, r, hf, 9)) / n : Nan();
      case 5:
         return BxH(a, r, hf, 11) / n - BxH(a, rowAll, hf, 11) / nA;
      case 6:
         return BxH(a, r, hf, 12) / n - BxH(a, rowAll, hf, 12) / nA;
     }
   return Nan();
  }

int BxRowAdd(const int tfi, const int cat, const string lab, const int n, const bool intra)
  {
   int r = g_bxRN++;
   ArrayResize(g_bxRTf, g_bxRN, 256);
   ArrayResize(g_bxRCat, g_bxRN, 256);
   ArrayResize(g_bxRn, g_bxRN, 256);
   ArrayResize(g_bxRIn, g_bxRN, 256);
   ArrayResize(g_bxRLb, g_bxRN, 256);
   ArrayResize(g_bxRMed, g_bxRN, 256);
   ArrayResize(g_bxRV, g_bxRN * BX_NM, 2048);
   ArrayResize(g_bxRZ, g_bxRN * BX_NM, 2048);
   ArrayResize(g_bxRT, g_bxRN * BX_NM, 2048);
   g_bxRTf[r] = tfi;
   g_bxRCat[r] = cat;
   g_bxRn[r] = n;
   g_bxRIn[r] = intra;
   g_bxRLb[r] = lab;
   g_bxRMed[r] = Nan();
   for(int m = 0; m < BX_NM; m++)
     {
      g_bxRV[r * BX_NM + m] = Nan();
      g_bxRZ[r * BX_NM + m] = Nan();
      g_bxRT[r * BX_NM + m] = -1;
     }
   return r;
  }

string BxPer(const double x, const int d) { return FP(x, d) + "%"; }

// profilo di varianza per ora del giorno dai rendimenti chiusura-chiusura orari
void BxVarProfile(CSeries &h1)
  {
   double s2[24], sn[24];
   ArrayInitialize(s2, 0.0);
   ArrayInitialize(sn, 0.0);
   for(int i = 1; i < h1.n; i++)
     {
      if((long)h1.t[i] - (long)h1.t[i - 1] > 4 * 3600 || !(h1.c[i - 1] > 0))
         continue;
      double r = h1.c[i] / h1.c[i - 1] - 1.0;
      int hr = HourOf(h1.t[i]);
      s2[hr] += r * r;
      sn[hr] += 1;
     }
   for(int h = 0; h < 24; h++)
      g_bxHv[h] = sn[h] >= 50 && s2[h] > 0 ? s2[h] / sn[h] : 1.0;
  }

// probabilita' che massimo o minimo cadano nel primo terzo di un blocco: legge dell'arcoseno nel tempo operativo (varianza cumulata),
// cosi' il ritmo giornaliero della volatilita' non crea differenze; blocchi da D1: tempo uniforme
double BxExpFirst(const int tfi, const datetime t0, const int cnt, const int q3)
  {
   if(tfi > 6)
      return ArcF((double)q3 / cnt);
   int h0 = HourOf(t0);
   double vt = 0, vq = 0;
   for(int k = 0; k < cnt; k++)
     {
      double v = g_bxHv[(h0 + k) % 24];
      vt += v;
      if(k < q3)
         vq += v;
     }
   return vt > 0 ? ArcF(vq / vt) : ArcF((double)q3 / cnt);
  }

// La volatilita' e' persistente: i range di giorni vicini non sono indipendenti e lo z sul range sarebbe troppo grande.
// Fattore di inflazione della varianza della media (Bartlett, 5 ritardi) dai log-range di ogni categoria in ordine di tempo.
double BxVarInfl(CBlocks &b, const int ncat)
  {
   double num[6];
   double den = 0;
   ArrayInitialize(num, 0.0);
   double x[];
   ArrayResize(x, b.N);
   for(int k = 0; k < ncat; k++)
     {
      int q = 0;
      double sm = 0;
      for(int i = 0; i < b.N; i++)
         if(b.cat[i] == k && b.rng[i] > 0)
           {
            x[q] = MathLog(b.rng[i]);
            sm += x[q];
            q++;
           }
      if(q < 10)
         continue;
      double mu = sm / q;
      for(int j = 0; j < q; j++)
         den += (x[j] - mu) * (x[j] - mu);
      for(int lag = 1; lag <= 5; lag++)
         for(int j = 0; j + lag < q; j++)
            num[lag] += (x[j] - mu) * (x[j + lag] - mu);
     }
   if(!(den > 0))
      return 1.0;
   double f = 1.0;
   for(int lag = 1; lag <= 5; lag++)
      f += 2.0 * (1.0 - lag / 6.0) * num[lag] / den;
   return MathMax(1.0, MathMin(f, 20.0));
  }

// una timeframe: bias di ogni categoria (ora, giorno, mese...) contro tutti i periodi
void BxTf(const int tfi, CBlocks &b, const datetime tMid)
  {
   int ncat = CatCount(tfi), m = b.N;
   if(ncat <= 0 || m < 60)
      return;
   int NA = BX_NA, rowAll = ncat;
   double acc[];
   ArrayResize(acc, (ncat + 1) * 2 * NA);
   ArrayInitialize(acc, 0.0);
   for(int i = 0; i < m; i++)
     {
      int k = b.cat[i];
      if(k < 0 || k >= ncat)
         continue;
      int hf = b.t0[i] < tMid ? 0 : 1;
      double ex = 0, vx = 0;
      bool f3 = false, f3l = false;
      if(b.intra && b.cnt[i] >= 3)
        {
         int q3 = b.cnt[i] / 3;
         ex = BxExpFirst(tfi, b.t0[i], b.cnt[i], q3);
         vx = ex * (1 - ex);
         f3 = b.offH[i] + 1 <= q3;
         f3l = b.offL[i] + 1 <= q3;
        }
      double lg = b.rng[i] > 0 ? MathLog(b.rng[i]) : 0.0;
      for(int pass = 0; pass < 2; pass++)
        {
         int o = ((pass == 0 ? k : rowAll) * 2 + hf) * NA;
         acc[o] += 1;
         if(b.ret[i] > 0)
            acc[o + 1] += 1;
         acc[o + 2] += b.ret[i];
         acc[o + 3] += b.ret[i] * b.ret[i];
         if(b.rng[i] > 0)
           {
            acc[o + 4] += 1;
            acc[o + 5] += lg;
            acc[o + 6] += lg * lg;
           }
         if(f3)
            acc[o + 7] += 1;
         if(f3l)
            acc[o + 8] += 1;
         acc[o + 9] += ex;
         acc[o + 10] += vx;
         if(b.cls[i] == 0)
            acc[o + 11] += 1;
         if(b.cls[i] == 2)
            acc[o + 12] += 1;
         acc[o + 13] += b.rf[i];
        }
     }
   //--- range mediano per categoria
   double med[], tmp[];
   ArrayResize(med, ncat + 1);
   ArrayResize(tmp, m);
   for(int k = 0; k <= ncat; k++)
     {
      int q = 0;
      for(int i = 0; i < m; i++)
         if((k == ncat || b.cat[i] == k) && b.cat[i] >= 0 && b.cat[i] < ncat && b.rng[i] > 0)
            tmp[q++] = b.rng[i];
      med[k] = q > 0 ? MedianOf(tmp, q) : Nan();
     }
   //--- riferimento: tutti i periodi
   double nA = BxT(acc, rowAll, 0);
   if(nA < 60)
      return;
   double pA = BxT(acc, rowAll, 1) / nA, mA = BxT(acc, rowAll, 2) / nA;
   double vA = BxT(acc, rowAll, 3) / nA - mA * mA, sdA = vA > 0 ? MathSqrt(vA) : Nan();
   double nlA = BxT(acc, rowAll, 4), mlA = Dv(BxT(acc, rowAll, 5), nlA);
   double vlA = Dv(BxT(acc, rowAll, 6), nlA) - mlA * mlA, sdlA = vlA > 0 ? MathSqrt(vlA) : Nan();
   double pTA = BxT(acc, rowAll, 11) / nA, pMA = BxT(acc, rowAll, 12) / nA;
   string tf = TF_LABEL[tfi];
   double infl = BxVarInfl(b, ncat);
   g_bxInfl[tfi] = infl;
   for(int k = -1; k < ncat; k++)
     {
      int r = k < 0 ? rowAll : k;
      double n = BxT(acc, r, 0);
      if(n < 10)
         continue;
      string lab = k < 0 ? "Tutti i periodi" : (tfi == 1 ? HourLab(k) : CatLabel(tfi, k));
      int row = BxRowAdd(tfi, k, lab, (int)n, b.intra);
      double v[BX_NM], z[BX_NM];
      v[0] = BxT(acc, r, 1) / n;
      v[1] = BxT(acc, r, 2) / n;
      v[2] = med[r];
      v[3] = b.intra ? BxT(acc, r, 7) / n : Nan();
      v[4] = b.intra ? BxT(acc, r, 8) / n : Nan();
      v[5] = BxT(acc, r, 11) / n;
      v[6] = BxT(acc, r, 12) / n;
      v[7] = BxT(acc, r, 13) / n;
      for(int q = 0; q < BX_NM; q++)
         z[q] = Nan();
      if(k >= 0)
        {
         double nl = BxT(acc, r, 4), ml = Dv(BxT(acc, r, 5), nl), vx = BxT(acc, r, 10);
         z[0] = ZProp(v[0], pA, n);
         z[1] = (MathIsValidNumber(sdA) && sdA > 0) ? (v[1] - mA) / (sdA / MathSqrt(n)) : Nan();
         z[2] = (nl >= 10 && MathIsValidNumber(sdlA) && sdlA > 0) ? (ml - mlA) / (sdlA / MathSqrt(nl)) / MathSqrt(infl) : Nan();
         if(b.intra && vx > 0)
           {
            z[3] = (BxT(acc, r, 7) - BxT(acc, r, 9)) / MathSqrt(vx);
            z[4] = (BxT(acc, r, 8) - BxT(acc, r, 9)) / MathSqrt(vx);
           }
         z[5] = ZProp(v[5], pTA, n);
         z[6] = ZProp(v[6], pMA, n);
        }
      g_bxRMed[row] = med[r];
      for(int q = 0; q < BX_NM; q++)
        {
         g_bxRV[row * BX_NM + q] = v[q];
         g_bxRZ[row * BX_NM + q] = z[q];
        }
      if(k < 0)
         continue;
      for(int q = 0; q < 7; q++)
        {
         if(!MathIsValidNumber(z[q]))
            continue;
         double d0 = BxDiff(acc, r, rowAll, 0, q, b.intra), d1 = BxDiff(acc, r, rowAll, 1, q, b.intra);
         bool st = BxStable(z[q], d0, d1);
         string val, bas;
         if(q == 0)
           {
            val = BxPer(v[0], 1);
            bas = BxPer(pA, 1);
           }
         else
            if(q == 1)
              {
               val = BxPer(v[1], 3);
               bas = BxPer(mA, 3);
              }
            else
               if(q == 2)
                 {
                  val = BxPer(v[2], 3);
                  bas = BxPer(med[rowAll], 3);
                 }
               else
                  if(q == 3 || q == 4)
                    {
                     val = BxPer(v[q], 1);
                     bas = BxPer(Dv(BxT(acc, r, 9), n), 1) + " atteso";
                    }
                  else
                    {
                     val = BxPer(v[q], 1);
                     bas = BxPer(q == 5 ? pTA : pMA, 1);
                    }
         string tx = "[" + tf + " per " + CatName(tfi) + "] " + lab + " (N " + I2S((int)n) + "): " + BX_MN[q] + " " + val + " contro " + bas +
                     (st ? ", stabile nelle due met&agrave;" : ", non stabile nelle due met&agrave;");
         g_bxRT[row * BX_NM + q] = BxAddTest(ED_MB, q <= 1 ? 0 : (q == 2 ? 1 : 2), z[q], st, tx);
        }
     }
  }

// carattere del timeframe: una riga per timeframe (spostamento, tipo, persistenza del periodo successivo)
void BxDigest(const int tfi, CBlocks &b)
  {
   int m = b.N;
   if(m < 30)
      return;
   double sr[];
   Sorted(b.rng, m, sr);
   double medR = Pct(sr, m, 50), sRf = 0;
   int nUp = 0, nT = 0, nM = 0;
   for(int i = 0; i < m; i++)
     {
      if(b.ret[i] > 0)
         nUp++;
      if(b.cls[i] == 0)
         nT++;
      if(b.cls[i] == 2)
         nM++;
      sRf += b.rf[i];
     }
   NxAcc acc[];
   NextStats(b, acc);
   double up = (double)nUp / m, base = up * up + (1 - up) * (1 - up);
   double same = acc[0].n > 0 ? (double)acc[0].same / acc[0].n : Nan();
   double z = ZProp(same, base, (double)acc[0].n);
   g_bxDig += "<tr>" + TD(TF_LABEL[tfi]) + TD(I2S(m)) + TD(FP(medR, 3)) + TD(PX(medR * g_last)) + TDc(FP(up, 1), PCol(up, 0.5, 0.15)) +
              TD(FP((double)nT / m, 1)) + TD(FP((double)nM / m, 1)) + TD(F(sRf / m * 100, 0)) +
              TDc(FP(same, 1) + " <small>z " + ZS(z) + "</small>", PCol(z, 0, 5)) + "</tr>";
   R(g_bxDigTx, "  " + TF_LABEL[tfi] + ": " + I2S(m) + " periodi, spostamento mediano " + FP(medR, 3) + "% (circa " + PX(medR * g_last) +
     "), rialzisti " + FP(up, 1) + "%, trend " + FP((double)nT / m, 1) + "%, mean reversion " + FP((double)nM / m, 1) + "%, restituito " +
     F(sRf / m * 100, 0) + "%, il periodo dopo va nella stessa direzione nel " + FP(same, 1) + "% (con la sola prevalenza dei rialzi " +
     FP(base, 1) + "%, z " + ZS(z) + ")");
  }

//+------------------------------------------------------------------+
//| BIAS: ora x giorno, anno per anno, massimo e minimo della         |
//| settimana                                                         |
//+------------------------------------------------------------------+
// blocchi orari (Ora): ogni ora contro le stesse ore degli altri giorni della settimana
void BxHeat(CBlocks &b, const datetime tMid)
  {
   int m = b.N;
   if(m < 500)
      return;
   double hc[], hb[];
   ArrayResize(hc, 24 * 7 * 2 * 5);
   ArrayResize(hb, 24 * 2 * 5);
   ArrayInitialize(hc, 0.0);
   ArrayInitialize(hb, 0.0);
   for(int i = 0; i < m; i++)
     {
      int h = b.cat[i];
      if(h < 0 || h > 23)
         continue;
      int d = DowMon(b.t0[i]), hf = b.t0[i] < tMid ? 0 : 1;
      double lg = b.rng[i] > 0 ? MathLog(b.rng[i]) : 0.0;
      for(int pass = 0; pass < 2; pass++)
        {
         int o = pass == 0 ? ((h * 7 + d) * 2 + hf) * 5 : (h * 2 + hf) * 5;
         if(pass == 0)
           {
            hc[o] += 1;
            if(b.ret[i] > 0)
               hc[o + 1] += 1;
            if(b.rng[i] > 0)
              {
               hc[o + 2] += 1;
               hc[o + 3] += lg;
               hc[o + 4] += lg * lg;
              }
           }
         else
           {
            hb[o] += 1;
            if(b.ret[i] > 0)
               hb[o + 1] += 1;
            if(b.rng[i] > 0)
              {
               hb[o + 2] += 1;
               hb[o + 3] += lg;
               hb[o + 4] += lg * lg;
              }
           }
        }
     }
   for(int h = 0; h < 24; h++)
     {
      double nh = hb[(h * 2) * 5] + hb[(h * 2 + 1) * 5];
      g_bxHbn[h] = (int)nh;
      if(nh < 100)
         continue;
      double uh = hb[(h * 2) * 5 + 1] + hb[(h * 2 + 1) * 5 + 1], pu = uh / nh;
      g_bxHbu[h] = pu;
      double nl = hb[(h * 2) * 5 + 2] + hb[(h * 2 + 1) * 5 + 2], sl = hb[(h * 2) * 5 + 3] + hb[(h * 2 + 1) * 5 + 3];
      double ql = hb[(h * 2) * 5 + 4] + hb[(h * 2 + 1) * 5 + 4];
      double mlh = Dv(sl, nl), vlh = Dv(ql, nl) - mlh * mlh, sdl = vlh > 0 ? MathSqrt(vlh) : Nan();
      for(int d = 0; d < 7; d++)
        {
         int c = h * 7 + d;
         double n0 = hc[((h * 7 + d) * 2) * 5], n1 = hc[((h * 7 + d) * 2 + 1) * 5], n = n0 + n1;
         g_bxHn[c] = (int)n;
         if(n < 30)
            continue;
         double u0 = hc[((h * 7 + d) * 2) * 5 + 1], u1 = hc[((h * 7 + d) * 2 + 1) * 5 + 1];
         double pc = (u0 + u1) / n;
         double zu = ZProp(pc, pu, n);
         double du0 = n0 >= 15 && hb[(h * 2) * 5] >= 15 ? u0 / n0 - hb[(h * 2) * 5 + 1] / hb[(h * 2) * 5] : Nan();
         double du1 = n1 >= 15 && hb[(h * 2 + 1) * 5] >= 15 ? u1 / n1 - hb[(h * 2 + 1) * 5 + 1] / hb[(h * 2 + 1) * 5] : Nan();
         bool su = BxStable(zu, du0, du1);
         double c0 = hc[((h * 7 + d) * 2) * 5 + 2], c1 = hc[((h * 7 + d) * 2 + 1) * 5 + 2], nlc = c0 + c1;
         double s0 = hc[((h * 7 + d) * 2) * 5 + 3], s1 = hc[((h * 7 + d) * 2 + 1) * 5 + 3];
         double mlc = Dv(s0 + s1, nlc);
         double zr = (nlc >= 20 && MathIsValidNumber(sdl) && sdl > 0) ? (mlc - mlh) / (sdl / MathSqrt(nlc)) : Nan();
         double dr0 = (c0 >= 10 && hb[(h * 2) * 5 + 2] >= 10) ? s0 / c0 - hb[(h * 2) * 5 + 3] / hb[(h * 2) * 5 + 2] : Nan();
         double dr1 = (c1 >= 10 && hb[(h * 2 + 1) * 5 + 2] >= 10) ? s1 / c1 - hb[(h * 2 + 1) * 5 + 3] / hb[(h * 2 + 1) * 5 + 2] : Nan();
         bool sr = BxStable(zr, dr0, dr1);
         g_bxHu[c] = pc;
         g_bxHzu[c] = zu;
         g_bxHr[c] = MathIsValidNumber(mlc) && MathIsValidNumber(mlh) ? MathExp(mlc - mlh) : Nan();
         g_bxHzr[c] = zr;
         string lab = "Ora " + StringFormat("%02dh", h) + " del " + DOW[d];
         g_bxHtu[c] = BxAddTest(ED_MB, 0, zu, su, "[Ora x giorno] " + lab + " (N " + I2S((int)n) + "): rialzista " + BxPer(pc, 1) + " contro " +
                                BxPer(pu, 1) + " della stessa ora negli altri giorni" + (su ? ", stabile nelle due met&agrave;" : ", non stabile nelle due met&agrave;"));
         g_bxHtr[c] = BxAddTest(ED_MB, 1, zr, sr, "[Ora x giorno] " + lab + " (N " + I2S((int)n) + "): range " + F(g_bxHr[c], 2) +
                                " volte quello della stessa ora negli altri giorni" + (sr ? ", stabile nelle due met&agrave;" : ", non stabile nelle due met&agrave;"));
        }
     }
  }

// anno per anno sui blocchi giornalieri (descrittivo)
void BxYear(CBlocks &b)
  {
   int m = b.N;
   if(m < 100)
      return;
   int y0 = b.yr[0], y1 = b.yr[m - 1];
   if(y1 < y0)
      return;
   g_buf = true;
   g_bufS = "";
   THead("Anno|Giorni|% rialzisti|Rendimento (somma dei giorni) %|Spostamento mediano %|% Trend|% Mean rev.|Giorno pi&ugrave; ampio %");
   R(g_bxYrTx, "Giorno per giorno, anno per anno:");
   double tmp[];
   ArrayResize(tmp, m);
   for(int y = y0; y <= y1; y++)
     {
      int n = 0, up = 0, nt = 0, nm = 0, q = 0;
      double sr = 0, mx = 0;
      for(int i = 0; i < m; i++)
        {
         if(b.yr[i] != y)
            continue;
         n++;
         if(b.ret[i] > 0)
            up++;
         if(b.cls[i] == 0)
            nt++;
         if(b.cls[i] == 2)
            nm++;
         sr += b.ret[i];
         if(b.rng[i] > mx)
            mx = b.rng[i];
         tmp[q++] = b.rng[i];
        }
      if(n < 20)
         continue;
      double md = MedianOf(tmp, q);
      g_bufS += "<tr>" + TD(I2S(y)) + TD(I2S(n)) + TDc(FP((double)up / n, 1), PCol((double)up / n, 0.5, 0.15)) + TDc(FP(sr, 1), PCol(sr, 0, 0.3)) +
                TD(FP(md, 3)) + TD(FP((double)nt / n, 1)) + TD(FP((double)nm / n, 1)) + TD(FP(mx, 2)) + "</tr>";
      R(g_bxYrTx, "  " + I2S(y) + ": " + I2S(n) + " giorni, rialzisti " + FP((double)up / n, 1) + "%, rendimento " + FP(sr, 1) + "%, spostamento mediano " +
        FP(md, 3) + "%, trend " + FP((double)nt / n, 1) + "%, mean reversion " + FP((double)nm / n, 1) + "%, giorno pi&ugrave; ampio " + FP(mx, 2) + "%");
     }
   TEnd();
   g_buf = false;
   g_bxYr = g_bufS;
   g_bufS = "";
  }

// il massimo e il minimo della settimana cadono in quale giorno? Contro la legge dell'arcoseno nel tempo operativo (varianza cumulata)
void BxWeek(CSeries &s, const datetime tMid)
  {
   int n = s.n;
   if(n < 2000)
      return;
   int wa[];
   int nw = 0;
   long cur = LONG_MIN;
   for(int i = 0; i < n; i++)
     {
      long key = BlockKey(7, s.t[i]);
      if(key != cur)
        {
         nw++;
         ArrayResize(wa, nw, 2048);
         wa[nw - 1] = i;
         cur = key;
        }
     }
   nw--;  // l'ultima settimana e' in corso
   if(nw < 52)
      return;
   double cnt[];
   ArrayResize(cnt, nw);
   for(int w = 0; w < nw; w++)
      cnt[w] = (w + 1 < nw ? wa[w + 1] : n) - wa[w];
   double med = MedianOf(cnt, nw);
   double ob[28], ex[28], vr[28];
   ArrayInitialize(ob, 0.0);
   ArrayInitialize(ex, 0.0);
   ArrayInitialize(vr, 0.0);
   int used = 0;
   for(int w = 0; w < nw; w++)
     {
      int a = wa[w], e = w + 1 < nw ? wa[w + 1] : n, nb = e - a;
      if(nb < 0.8 * med)
         continue;
      int hf = s.t[a] < tMid ? 0 : 1, ih = a, il = a;
      int fd[7], ld[7];
      ArrayInitialize(fd, -1);
      ArrayInitialize(ld, -1);
      for(int j = a; j < e; j++)
        {
         if(s.h[j] > s.h[ih])
            ih = j;
         if(s.l[j] < s.l[il])
            il = j;
         int d = DowMon(s.t[j]);
         if(fd[d] < 0)
            fd[d] = j - a;
         ld[d] = j - a;
        }
      used++;
      double cs[];
      ArrayResize(cs, nb + 1);
      cs[0] = 0;
      for(int j = a; j < e; j++)
         cs[j - a + 1] = cs[j - a] + g_bxHv[HourOf(s.t[j])];
      for(int d = 0; d < 7; d++)
         if(fd[d] >= 0 && cs[nb] > 0)
           {
            double p = ArcF(cs[ld[d] + 1] / cs[nb]) - ArcF(cs[fd[d]] / cs[nb]);
            for(int ty = 0; ty < 2; ty++)
              {
               ex[(ty * 7 + d) * 2 + hf] += p;
               vr[(ty * 7 + d) * 2 + hf] += p * (1 - p);
              }
           }
      ob[(0 * 7 + DowMon(s.t[ih])) * 2 + hf] += 1;
      ob[(1 * 7 + DowMon(s.t[il])) * 2 + hf] += 1;
     }
   g_bxWn = used;
   if(used < 52)
      return;
   for(int ty = 0; ty < 2; ty++)
      for(int d = 0; d < 7; d++)
        {
         int c = ty * 7 + d;
         double o0 = ob[c * 2], o1 = ob[c * 2 + 1], e0 = ex[c * 2], e1 = ex[c * 2 + 1], v = vr[c * 2] + vr[c * 2 + 1];
         g_bxWo[c] = o0 + o1;
         g_bxWe[c] = e0 + e1;
         if(e0 + e1 < 10 || !(v > 0))
            continue;
         double z = (o0 + o1 - e0 - e1) / MathSqrt(v);
         bool st = BxStable(z, o0 - e0, o1 - e1);
         g_bxWz[c] = z;
         g_bxWt[c] = BxAddTest(ED_MB, 2, z, st, "[Settimana] " + (ty == 0 ? "Il massimo" : "Il minimo") + " della settimana cade di " + DOW[d] + " nel " +
                               FP((o0 + o1) / used, 1) + "% delle settimane contro " + FP((e0 + e1) / used, 1) + "% atteso da un prezzo casuale (N " +
                               I2S(used) + ")" + (st ? ", stabile nelle due met&agrave;" : ", non stabile nelle due met&agrave;"));
        }
  }

//+------------------------------------------------------------------+
//| BIAS: impulso piu' forte, massimo e minimo del giorno: a che ora  |
//| avvengono e cosa li precede (contro la stessa ora degli altri     |
//| giorni)                                                           |
//+------------------------------------------------------------------+
#define TG_PC 98.0  // impulso forte: barra tra il 2% dei movimenti piu' ampi della sua ora
#define TG_MC 16   // estrazioni per giorno dell'atteso dell'impulso (ogni ora estratta dalla propria distribuzione)

int TgI(const int h, const int f, const int fi, const int ci) { return ((h * 2 + f) * TG_NF + fi) * TG_NC + ci; }

// caratteristiche prima della barra j (solo barre precedenti), nei due versi: cl[f * TG_NF + fi], f = 0 verso l'alto, 1 verso il basso; -1 = non definita
void TgFeat(CSeries &s, const double &atr[], const double &rvol[], const double &r3[], const double q1, const double q2, const int j,
            const int a, const bool hasPd, const double pdh, const double pdl, const double hiT, const double loT, int &cl[])
  {
   for(int x = 0; x < TG_NF * 2; x++)
      cl[x] = -1;
   bool okp = j >= 3 && MathIsValidNumber(r3[j]) && atr[j - 1] > 0;
   for(int f = 0; f < 2; f++)
     {
      double dr = f == 0 ? 1.0 : -1.0;
      int b0 = f * TG_NF;
      if(okp)
        {
         double mv = dr * (s.c[j - 1] - s.o[j - 3]) / atr[j - 1];
         cl[b0] = mv > 0.5 ? 0 : (mv < -0.5 ? 2 : 1);
         cl[b0 + 1] = r3[j] < q1 ? 0 : (r3[j] <= q2 ? 1 : 2);
        }
      if(j > a)
        {
         if(hasPd)
           {
            bool sh = hiT > pdh, sl = loT < pdl;
            bool fav = dr > 0 ? sh : sl, opp = dr > 0 ? sl : sh;
            cl[b0 + 2] = (opp && !fav) ? 0 : ((fav && !opp) ? 1 : ((fav && opp) ? 2 : 3));
           }
         if(hiT > loT)
           {
            double pos = MathMax(0.0, MathMin(1.0, (s.o[j] - loT) / (hiT - loT)));
            double pf = dr > 0 ? pos : 1.0 - pos;
            cl[b0 + 3] = pf < 1.0 / 3.0 ? 0 : (pf < 2.0 / 3.0 ? 1 : 2);
           }
        }
      if(j >= 1 && MathIsValidNumber(rvol[j - 1]))
         cl[b0 + 4] = rvol[j - 1] < 0.8 ? 0 : (rvol[j - 1] < 1.5 ? 1 : 2);
     }
  }

// registra un caso: bersaglio pt, ora, verso, meta' del campione e caratteristiche nei due versi
void TgCaseAdd(int &cT[], int &cH[], int &cD[], int &cF[], int &cCl[], int &nCs, const int pt, const int hr, const int dir, const int hf, const int &cl[])
  {
   nCs++;
   ArrayResize(cT, nCs, 8192);
   ArrayResize(cH, nCs, 8192);
   ArrayResize(cD, nCs, 8192);
   ArrayResize(cF, nCs, 8192);
   ArrayResize(cCl, nCs * 2 * TG_NF, 8192 * 2 * TG_NF);
   int r = nCs - 1;
   cT[r] = pt;
   cH[r] = hr;
   cD[r] = dir;
   cF[r] = hf;
   for(int x = 0; x < 2 * TG_NF; x++)
      cCl[r * 2 * TG_NF + x] = cl[x];
  }

void TgRun(CSeries &s, const datetime tMid)
  {
   int n = s.n;
   if(n < 5000)
      return;
   double ret[], atr[], rvol[], r3[];
   ArrayResize(ret, n);
   for(int i = 0; i < n; i++)
      ret[i] = s.o[i] > 0 ? s.c[i] / s.o[i] - 1.0 : 0.0;
   CalcATR(s, 14, atr);
   CalcRVOL(s, 3600, 20, rvol);
   if(ArraySize(rvol) != n)
     {
      ArrayResize(rvol, n);
      for(int i = 0; i < n; i++)
         rvol[i] = Nan();
     }
   //--- compressione delle 3 barre prima (range / ATR) e sue soglie (terzili sull'intero campione)
   ArrayResize(r3, n);
   double smp[];
   ArrayResize(smp, n);
   int ns = 0;
   for(int i = 0; i < n; i++)
     {
      r3[i] = Nan();
      if(i < 3 || (long)s.t[i] - (long)s.t[i - 3] > 4 * 3600 || !(atr[i - 1] > 0))
         continue;
      double hh = MathMax(s.h[i - 3], MathMax(s.h[i - 2], s.h[i - 1])), ll = MathMin(s.l[i - 3], MathMin(s.l[i - 2], s.l[i - 1]));
      r3[i] = (hh - ll) / atr[i - 1];
      smp[ns++] = r3[i];
     }
   if(ns < 1000)
      return;
   double sv[];
   Sorted(smp, ns, sv);
   double q1 = Pct(sv, ns, 100.0 / 3.0), q2 = Pct(sv, ns, 200.0 / 3.0);
   //--- rendimenti assoluti di ogni ora del giorno: per l'atteso dell'impulso ogni ora e' estratta dalla propria distribuzione
   int pcn[24], pst[24], pfl[24];
   ArrayInitialize(pcn, 0);
   ArrayInitialize(pfl, 0);
   for(int i = 0; i < n; i++)
      pcn[HourOf(s.t[i])]++;
   pst[0] = 0;
   for(int h = 1; h < 24; h++)
      pst[h] = pst[h - 1] + pcn[h - 1];
   double pool[];
   ArrayResize(pool, n);
   for(int i = 0; i < n; i++)
     {
      int hr = HourOf(s.t[i]);
      pool[pst[hr] + pfl[hr]] = MathAbs(ret[i]);
      pfl[hr]++;
     }
   //--- forme delle barre di ogni ora (apertura, massimo, minimo, chiusura relativi alla chiusura precedente): per l'atteso ogni ora
   //--- e' estratta dalla propria distribuzione, indipendente dalle altre (tiene conto di ritmo giornaliero, code pesanti e deriva)
   int scn[24], sst[24], sfl[24];
   ArrayInitialize(scn, 0);
   ArrayInitialize(sfl, 0);
   for(int i = 1; i < n; i++)
      if((long)s.t[i] - (long)s.t[i - 1] <= 4 * 3600 && s.c[i - 1] > 0)
         scn[HourOf(s.t[i])]++;
   sst[0] = 0;
   for(int h = 1; h < 24; h++)
      sst[h] = sst[h - 1] + scn[h - 1];
   double sO[], sH[], sL[], sC[];
   ArrayResize(sO, n);
   ArrayResize(sH, n);
   ArrayResize(sL, n);
   ArrayResize(sC, n);
   for(int i = 1; i < n; i++)
      if((long)s.t[i] - (long)s.t[i - 1] <= 4 * 3600 && s.c[i - 1] > 0)
        {
         int hr = HourOf(s.t[i]), q = sst[hr] + sfl[hr];
         sO[q] = s.o[i] / s.c[i - 1] - 1.0;
         sH[q] = s.h[i] / s.c[i - 1] - 1.0;
         sL[q] = s.l[i] / s.c[i - 1] - 1.0;
         sC[q] = s.c[i] / s.c[i - 1] - 1.0;
         sfl[hr]++;
        }
   //--- soglia dell'impulso forte per ora: percentile dei movimenti assoluti di quell'ora sull'intero storico
   double thr[24];
   for(int h = 0; h < 24; h++)
     {
      thr[h] = 1e300;
      if(pcn[h] < 200)
         continue;
      double seg[];
      ArrayResize(seg, pcn[h]);
      for(int q = 0; q < pcn[h]; q++)
         seg[q] = pool[pst[h] + q];
      ArraySort(seg);
      thr[h] = Pct(seg, pcn[h], TG_PC);
     }
   //--- giorni
   int ds[], de[];
   int nd = 0;
   long cur = -1;
   for(int i = 0; i < n; i++)
     {
      long dk = (long)s.t[i] / 86400;
      if(dk != cur)
        {
         nd++;
         ArrayResize(ds, nd, 8192);
         ArrayResize(de, nd, 8192);
         ds[nd - 1] = i;
         cur = dk;
        }
      de[nd - 1] = i + 1;
     }
   nd--;  // l'ultimo giorno e' in corso
   if(nd < 250)
      return;
   double nbv[];
   ArrayResize(nbv, nd);
   for(int d = 0; d < nd; d++)
      nbv[d] = de[d] - ds[d];
   double nbMed = MedianOf(nbv, nd);
   int cT[], cH[], cD[], cF[], cCl[];
   int nCs = 0;
   ArrayResize(g_tgAC, 24 * 2 * TG_NF * TG_NC);
   ArrayInitialize(g_tgAC, 0.0);
   double ob[TG_NT * 48], eM[TG_NT * 48], impN[48], impU[48], dayN[24];
   ArrayInitialize(ob, 0.0);
   ArrayInitialize(eM, 0.0);
   ArrayInitialize(impN, 0.0);
   ArrayInitialize(impU, 0.0);
   ArrayInitialize(dayN, 0.0);
   long pdDay = -1000;
   double pdH = 0, pdL = 0;
   int validDays = 0;
   int cl[TG_NF * 2];
   for(int d = 0; d < nd && !IsStopped(); d++)
     {
      int a = ds[d], e = de[d], nb = e - a;
      long dk = (long)s.t[a] / 86400;
      bool okd = nb >= 12 && nb >= 0.8 * nbMed;
      double dh = s.h[a], dl = s.l[a];
      for(int j = a; j < e; j++)
        {
         if(s.h[j] > dh)
            dh = s.h[j];
         if(s.l[j] < dl)
            dl = s.l[j];
         if(j > a && (long)s.t[j] - (long)s.t[j - 1] > 4 * 3600)
            okd = false;
        }
      bool hasPd = dk > pdDay && dk - pdDay <= 4;
      double pH = pdH, pL = pdL;
      if(okd)
        {
         pdDay = dk;
         pdH = dh;
         pdL = dl;
        }
      else
         continue;
      int ii = a, ih = a, il = a;
      double mx = -1;
      for(int j = a; j < e; j++)
        {
         double ar = MathAbs(ret[j]);
         if(ar > mx)
           {
            mx = ar;
            ii = j;
           }
         if(s.h[j] > s.h[ih])
            ih = j;
         if(s.l[j] < s.l[il])
            il = j;
        }
      int ti[TG_NT], dr[TG_NT];
      ti[0] = ii;
      ti[1] = ih;
      ti[2] = il;
      dr[0] = ret[ii] > 0 ? 1 : (ret[ii] < 0 ? -1 : 0);
      dr[1] = 1;
      dr[2] = -1;
      int hf = s.t[a] < tMid ? 0 : 1;
      validDays++;
      //--- ora del bersaglio, osservata e attesa
      for(int ty = 0; ty < TG_NT; ty++)
         if(dr[ty] != 0)
            ob[(ty * 24 + HourOf(s.t[ti[ty]])) * 2 + hf] += 1;
      if(dr[0] != 0)
        {
         int hi0 = HourOf(s.t[ii]);
         impN[hi0 * 2 + hf] += 1;
         if(dr[0] > 0)
            impU[hi0 * 2 + hf] += 1;
        }
      for(int j = a; j < e; j++)
         dayN[HourOf(s.t[j])] += 1;
      for(int k = 0; k < TG_MC; k++)
        {
         double px = 1.0, mxI = -1, hiV = -1e300, loV = 1e300;
         int bI = 0, bH = 0, bL = 0;
         for(int j = a; j < e; j++)
           {
            int hr = HourOf(s.t[j]);
            if(scn[hr] < 50)
               continue;
            int q = sst[hr] + (int)(((long)MathRand() * 32768 + MathRand()) % scn[hr]);
            double bo = px * (1.0 + sO[q]), bh = px * (1.0 + sH[q]), bl = px * (1.0 + sL[q]), bc = px * (1.0 + sC[q]);
            double imp = bo > 0 ? MathAbs(bc / bo - 1.0) : 0.0;
            if(imp > mxI)
              {
               mxI = imp;
               bI = hr;
              }
            if(bh > hiV)
              {
               hiV = bh;
               bH = hr;
              }
            if(bl < loV)
              {
               loV = bl;
               bL = hr;
              }
            px = bc;
           }
         eM[(0 * 24 + bI) * 2 + hf] += 1.0 / TG_MC;
         eM[(1 * 24 + bH) * 2 + hf] += 1.0 / TG_MC;
         eM[(2 * 24 + bL) * 2 + hf] += 1.0 / TG_MC;
        }
      //--- caratteristiche prima di ogni barra del giorno (controlli) e dei bersagli (casi)
      double hiT = -1e300, loT = 1e300;
      for(int j = a; j < e; j++)
        {
         TgFeat(s, atr, rvol, r3, q1, q2, j, a, hasPd, pH, pL, hiT, loT, cl);
         int hr = HourOf(s.t[j]);
         for(int f = 0; f < 2; f++)
            for(int fi = 0; fi < TG_NF; fi++)
               if(cl[f * TG_NF + fi] >= 0)
                  g_tgAC[TgI(hr, f, fi, cl[f * TG_NF + fi])] += 1;
         if(j == ii && dr[0] != 0)
            TgCaseAdd(cT, cH, cD, cF, cCl, nCs, 0, hr, dr[0], hf, cl);
         if(ret[j] != 0 && MathAbs(ret[j]) >= thr[hr])
            TgCaseAdd(cT, cH, cD, cF, cCl, nCs, 1, hr, ret[j] > 0 ? 1 : -1, hf, cl);
         if(s.h[j] > hiT)
            hiT = s.h[j];
         if(s.l[j] < loT)
            loT = s.l[j];
        }
     }
   g_tgNd = validDays;
   if(validDays < 250)
      return;
   for(int h = 0; h < 24; h++)
      g_tgDays[h] = (int)dayN[h];
   //--- a che ora avvengono
   double sN = 0, sU = 0;
   for(int x = 0; x < 48; x++)
     {
      sN += impN[x];
      sU += impU[x];
     }
   double pUp = sN > 0 ? sU / sN : 0.5;
   for(int h = 0; h < 24; h++)
     {
      double ndh = dayN[h];
      if(ndh < 100)
         continue;
      for(int ty = 0; ty < TG_NT; ty++)
        {
         int idx = ty * 24 + h;
         double o0 = ob[idx * 2], o1 = ob[idx * 2 + 1], e0 = eM[idx * 2], e1 = eM[idx * 2 + 1];
         double v = (e0 + e1) * (1 - (e0 + e1) / ndh);
         g_tgO[idx] = o0 + o1;
         g_tgE[idx] = e0 + e1;
         if(e0 + e1 < 5 || !(v > 0))
            continue;
         double z = (o0 + o1 - e0 - e1) / MathSqrt(v);
         bool st = BxStable(z, o0 - e0, o1 - e1);
         g_tgZ[idx] = z;
         g_tgT[idx] = BxAddTest(ED_MT, 2, z, st, "[Quando] Ora " + HourLab(h) + ": " + TG_TN[ty] + " nel " + FP((o0 + o1) / ndh, 1) +
                                "% dei giorni contro " + FP((e0 + e1) / ndh, 1) + "% atteso (ogni ora estratta dalla propria distribuzione, indipendente dalle altre, N " +
                                I2S((int)ndh) + ")" +
                                (st ? ", stabile nelle due met&agrave;" : ", non stabile nelle due met&agrave;"));
        }
      double in0 = impN[h * 2], in1 = impN[h * 2 + 1], iu0 = impU[h * 2], iu1 = impU[h * 2 + 1], inn = in0 + in1;
      g_tgUn[h] = inn;
      g_tgUu[h] = iu0 + iu1;
      if(inn >= 30)
        {
         double z = ZProp((iu0 + iu1) / inn, pUp, inn);
         double d0 = in0 >= 15 ? iu0 / in0 - pUp : Nan(), d1 = in1 >= 15 ? iu1 / in1 - pUp : Nan();
         bool st = BxStable(z, d0, d1);
         g_tgUz[h] = z;
         g_tgUt[h] = BxAddTest(ED_MT, 0, z, st, "[Direzione dell'impulso] Ora " + HourLab(h) + ": l'impulso pi&ugrave; forte del giorno &egrave; rialzista nel " +
                               FP((iu0 + iu1) / inn, 1) + "% dei casi contro " + FP(pUp, 1) + "% di tutte le ore (N " + I2S((int)inn) + ")" +
                               (st ? ", stabile nelle due met&agrave;" : ", non stabile nelle due met&agrave;"));
        }
     }
   //--- cosa precede: casi contro le altre barre della stessa ora (controlli), nello stesso verso
   for(int pt = 0; pt < TG_NP && !IsStopped(); pt++)
     {
      double CT[];
      ArrayResize(CT, ArraySize(g_tgAC));
      ArrayCopy(CT, g_tgAC);
      int nCases = 0;
      for(int r = 0; r < nCs; r++)
        {
         if(cT[r] != pt)
            continue;
         nCases++;
         for(int f = 0; f < 2; f++)
            for(int fi = 0; fi < TG_NF; fi++)
              {
               int c = cCl[r * 2 * TG_NF + f * TG_NF + fi];
               if(c >= 0)
                  CT[TgI(cH[r], f, fi, c)] -= 1;
              }
        }
      g_tgCases[pt] = nCases;
      double Oo[TG_NF * TG_NC], Ee[TG_NF * TG_NC], Vv[TG_NF * TG_NC], Oh[TG_NF * TG_NC * 2], Eh[TG_NF * TG_NC * 2], U[TG_NF], Uh[TG_NF * 2];
      ArrayInitialize(Oo, 0.0);
      ArrayInitialize(Ee, 0.0);
      ArrayInitialize(Vv, 0.0);
      ArrayInitialize(Oh, 0.0);
      ArrayInitialize(Eh, 0.0);
      ArrayInitialize(U, 0.0);
      ArrayInitialize(Uh, 0.0);
      for(int r = 0; r < nCs; r++)
        {
         if(cT[r] != pt)
            continue;
         int h = cH[r], f = cD[r] > 0 ? 0 : 1, hf = cF[r];
         for(int fi = 0; fi < TG_NF; fi++)
           {
            int c = cCl[r * 2 * TG_NF + f * TG_NF + fi];
            if(c < 0)
               continue;
            double tot = 0;
            for(int ci = 0; ci < TG_NC; ci++)
               tot += CT[TgI(h, f, fi, ci)];
            if(tot < 30)
               continue;
            U[fi] += 1;
            Uh[fi * 2 + hf] += 1;
            for(int ci = 0; ci < TG_NCL[fi]; ci++)
              {
               double p = CT[TgI(h, f, fi, ci)] / tot;
               int x = fi * TG_NC + ci;
               Ee[x] += p;
               Vv[x] += p * (1 - p);
               Eh[x * 2 + hf] += p;
               if(c == ci)
                 {
                  Oo[x] += 1;
                  Oh[x * 2 + hf] += 1;
                 }
              }
           }
        }
      for(int fi = 0; fi < TG_NF; fi++)
        {
         g_tgFn[pt * TG_NF + fi] = U[fi];
         if(U[fi] < 30)
            continue;
         for(int ci = 0; ci < TG_NCL[fi]; ci++)
           {
            int x = fi * TG_NC + ci, gx = (pt * TG_NF + fi) * TG_NC + ci;
            g_tgFO[gx] = Oo[x];
            g_tgFE[gx] = Ee[x];
            if(!(Vv[x] > 0))
               continue;
            double z = (Oo[x] - Ee[x]) / MathSqrt(Vv[x]);
            g_tgFZ[gx] = z;
            if(pt == 0)
               continue;  // scelto a posteriori: la selezione crea differenze meccaniche, niente confronto formale
            bool st = BxStable(z, Uh[fi * 2] >= 15 ? Oh[x * 2] - Eh[x * 2] : Nan(), Uh[fi * 2 + 1] >= 15 ? Oh[x * 2 + 1] - Eh[x * 2 + 1] : Nan());
            g_tgFt[gx] = BxAddTest(ED_MT, 3, z, st, "[" + TG_PN[pt] + "] " + TG_FN[fi] + ", " + TG_CL[fi * TG_NC + ci] + ": " + FP(Oo[x] / U[fi], 1) +
                                   "% dei casi contro " + FP(Ee[x] / U[fi], 1) + "% delle altre barre della stessa ora (N " + I2S((int)U[fi]) +
                                   ")" + (st ? ", stabile nelle due met&agrave;" : ", non stabile nelle due met&agrave;"));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| BIAS: tabelle e scheda                                            |
//+------------------------------------------------------------------+
// dopo lo z: dagger = sopravvive al controllo FDR e ha lo stesso verso nelle due meta'; section = solo FDR
string BxMark(const int tid)
  {
   if(tid < 0 || tid >= g_bxNT)
      return "";
   if(g_bxTfd[tid] && g_bxTst[tid])
      return "&dagger;";
   if(g_bxTfd[tid])
      return "&sect;";
   return "";
  }

string BxCell(const string val, const double z, const int tid)
  {
   return TDc(val + " <small>z " + ZS(z) + BxMark(tid) + "</small>", PCol(z, 0, 5));
  }

string BxReadRow(const int r)
  {
   string s = "";
   bool rob = false;
   for(int m = 0; m < 7; m++)
     {
      double z = g_bxRZ[r * BX_NM + m];
      if(!MathIsValidNumber(z) || MathAbs(z) < 2)
         continue;
      int tid = g_bxRT[r * BX_NM + m];
      if(tid >= 0 && g_bxTfd[tid] && g_bxTst[tid])
         rob = true;
      string t = "";
      switch(m)
        {
         case 0:
            t = z > 0 ? "sale piu' spesso" : "scende piu' spesso";
            break;
         case 1:
            t = z > 0 ? "rendimento sopra la media" : "rendimento sotto la media";
            break;
         case 2:
            t = z > 0 ? "muove di piu'" : "muove di meno";
            break;
         case 3:
            t = z > 0 ? "massimo presto" : "massimo tardi";
            break;
         case 4:
            t = z > 0 ? "minimo presto" : "minimo tardi";
            break;
         case 5:
            t = z > 0 ? "piu' trend" : "meno trend";
            break;
         case 6:
            t = z > 0 ? "piu' mean reversion" : "meno mean reversion";
            break;
        }
      s += (s != "" ? "; " : "") + t;
     }
   if(s == "")
      return "nessuno scostamento";
   return s + (rob ? " [robusto]" : " [indizio]");
  }

void BxRenderTf(const int tfi)
  {
   bool any = false, intra = false;
   for(int r = 0; r < g_bxRN; r++)
      if(g_bxRTf[r] == tfi)
        {
         any = true;
         intra = g_bxRIn[r];
        }
   if(!any)
      return;
   SecStart("Bias per " + CatName(tfi) + " (" + TF_LABEL[tfi] + ")",
            "Ogni " + CatName(tfi) + " contro tutti i periodi di questo timeframe (non contro il 50%: se il prezzo sale nel tempo, quasi ovunque " +
            "i rialzisti superano il 50%). Colore = z (blu sopra, rosso sotto); &dagger; = robusto (FDR 5% e stesso verso nelle due met&agrave;), " +
            "&sect; = solo FDR. Lo z del range &egrave; ridotto per la persistenza della volatilit&agrave; (i range di giorni vicini non sono indipendenti; correzione prudente): " +
            "fattore di inflazione della varianza " + F(g_bxInfl[tfi], 2) + "." + (intra ? " Massimo e minimo nel primo terzo: contro la quota attesa da un prezzo casuale con la volatilit&agrave; di ogni ora (legge dell'arcoseno nel tempo operativo)." : ""));
   THead("Categoria|Periodi|% rialzista|Rendimento medio %|Range mediano % (volte tutti)|Massimo nel primo terzo|Minimo nel primo terzo|% Trend|" +
         "% Mean rev.|Restituito medio %|Lettura");
   R(g_repBias, "");
   R(g_repBias, "[" + TF_LABEL[tfi] + " per " + CatName(tfi) + "]");
   double medAll = Nan();
   for(int r = 0; r < g_bxRN; r++)
      if(g_bxRTf[r] == tfi && g_bxRCat[r] < 0)
         medAll = g_bxRMed[r];
   for(int r = 0; r < g_bxRN; r++)
     {
      if(g_bxRTf[r] != tfi)
         continue;
      int b0 = r * BX_NM;
      string ratio = (g_bxRCat[r] >= 0 && MathIsValidNumber(medAll) && medAll > 0 && MathIsValidNumber(g_bxRMed[r])) ?
                     " (x" + F(g_bxRMed[r] / medAll, 2) + ")" : "";
      if(g_bxRCat[r] < 0)
        {
         W("<tr class='base'>" + TD(g_bxRLb[r]) + TD(I2S(g_bxRn[r])) + TD(FP(g_bxRV[b0], 1)) + TD(FP(g_bxRV[b0 + 1], 3)) + TD(FP(g_bxRV[b0 + 2], 3)) +
           TD(FP(g_bxRV[b0 + 3], 1)) + TD(FP(g_bxRV[b0 + 4], 1)) + TD(FP(g_bxRV[b0 + 5], 1)) + TD(FP(g_bxRV[b0 + 6], 1)) +
           TD(F(g_bxRV[b0 + 7] * 100, 0)) + TD("riferimento") + "</tr>");
         R(g_repBias, "  " + g_bxRLb[r] + " (N " + I2S(g_bxRn[r]) + "): rialzisti " + FP(g_bxRV[b0], 1) + "%, rendimento medio " + FP(g_bxRV[b0 + 1], 3) +
           "%, range mediano " + FP(g_bxRV[b0 + 2], 3) + "%, trend " + FP(g_bxRV[b0 + 5], 1) + "%, mean reversion " + FP(g_bxRV[b0 + 6], 1) + "%");
         continue;
        }
      string rd = BxReadRow(r);
      W("<tr>" + TD(g_bxRLb[r]) + TD(I2S(g_bxRn[r])) + BxCell(FP(g_bxRV[b0], 1), g_bxRZ[b0], g_bxRT[b0]) +
        BxCell(FP(g_bxRV[b0 + 1], 3), g_bxRZ[b0 + 1], g_bxRT[b0 + 1]) + BxCell(FP(g_bxRV[b0 + 2], 3) + ratio, g_bxRZ[b0 + 2], g_bxRT[b0 + 2]) +
        BxCell(FP(g_bxRV[b0 + 3], 1), g_bxRZ[b0 + 3], g_bxRT[b0 + 3]) + BxCell(FP(g_bxRV[b0 + 4], 1), g_bxRZ[b0 + 4], g_bxRT[b0 + 4]) +
        BxCell(FP(g_bxRV[b0 + 5], 1), g_bxRZ[b0 + 5], g_bxRT[b0 + 5]) + BxCell(FP(g_bxRV[b0 + 6], 1), g_bxRZ[b0 + 6], g_bxRT[b0 + 6]) +
        TD(F(g_bxRV[b0 + 7] * 100, 0)) + TD(rd) + "</tr>");
      R(g_repBias, "  " + g_bxRLb[r] + " (N " + I2S(g_bxRn[r]) + "): rialzisti " + FP(g_bxRV[b0], 1) + "% (z " + ZS(g_bxRZ[b0]) + BxMark(g_bxRT[b0]) +
        "), rendimento medio " + FP(g_bxRV[b0 + 1], 3) + "% (z " + ZS(g_bxRZ[b0 + 1]) + "), range mediano " + FP(g_bxRV[b0 + 2], 3) + "%" + ratio +
        " (z " + ZS(g_bxRZ[b0 + 2]) + BxMark(g_bxRT[b0 + 2]) + ")" +
        (intra ? ", massimo nel primo terzo " + FP(g_bxRV[b0 + 3], 1) + "% (z " + ZS(g_bxRZ[b0 + 3]) + "), minimo nel primo terzo " +
                 FP(g_bxRV[b0 + 4], 1) + "% (z " + ZS(g_bxRZ[b0 + 4]) + ")" : "") +
        ", trend " + FP(g_bxRV[b0 + 5], 1) + "% (z " + ZS(g_bxRZ[b0 + 5]) + "), mean reversion " + FP(g_bxRV[b0 + 6], 1) + "% (z " +
        ZS(g_bxRZ[b0 + 6]) + "), restituito " + F(g_bxRV[b0 + 7] * 100, 0) + "% -> " + rd);
     }
   TEnd();
   SecEnd();
  }

void BxRenderHeat(void)
  {
   int dl[7];
   int nd = 0;
   for(int d = 0; d < 7; d++)
     {
      int tot = 0;
      for(int h = 0; h < 24; h++)
         tot += g_bxHn[h * 7 + d];
      if(tot >= 100)
         dl[nd++] = d;
     }
   if(nd == 0)
      return;
   string hd = "Ora|Tutti i giorni";
   for(int k = 0; k < nd; k++)
      hd += "|" + DOW[dl[k]];
   for(int tb = 0; tb < 2; tb++)
     {
      string ttl = tb == 0 ? "Ora x giorno della settimana: % di ore rialziste" : "Ora x giorno della settimana: range";
      SecStart(ttl, "Ogni ora del giorno (orario dei dati) contro la stessa ora negli altri giorni della settimana. " +
               (tb == 0 ? "Cella = % di barre orarie rialziste; z contro la media della stessa ora." :
               "Cella = range medio (geometrico) in volte quello della stessa ora nei giorni della settimana; z sul logaritmo del range.") +
               " &dagger; = robusto (FDR 5% e stesso verso nelle due met&agrave;), &sect; = solo FDR. Almeno 30 ore per cella.");
      THead(hd);
      R(g_repBias, "");
      R(g_repBias, "[" + ttl + "]");
      for(int h = 0; h < 24; h++)
        {
         if(g_bxHbn[h] < 100)
            continue;
         string row = "<tr>" + TD(HourLab(h)) + TD(tb == 0 ? BxPer(g_bxHbu[h], 1) : "1.00");
         string tx = "  " + HourLab(h) + " (tutti i giorni " + (tb == 0 ? FP(g_bxHbu[h], 1) + "% rialziste" : "range 1.00") + "):";
         for(int k = 0; k < nd; k++)
           {
            int c = h * 7 + dl[k];
            if(g_bxHn[c] < 30)
              {
               row += TD("&ndash;");
               continue;
              }
            if(tb == 0)
              {
               row += BxCell(FP(g_bxHu[c], 0), g_bxHzu[c], g_bxHtu[c]);
               tx += " " + DOW[dl[k]] + " " + FP(g_bxHu[c], 1) + "% (z " + ZS(g_bxHzu[c]) + BxMark(g_bxHtu[c]) + ");";
              }
            else
              {
               row += BxCell(F(g_bxHr[c], 2), g_bxHzr[c], g_bxHtr[c]);
               tx += " " + DOW[dl[k]] + " x" + F(g_bxHr[c], 2) + " (z " + ZS(g_bxHzr[c]) + BxMark(g_bxHtr[c]) + ");";
              }
           }
         W(row + "</tr>");
         R(g_repBias, tx);
        }
      TEnd();
      SecEnd();
     }
  }

void BxRenderWeek(void)
  {
   if(g_bxWn < 52)
      return;
   int dl[7];
   int nd = 0;
   for(int d = 0; d < 7; d++)
      if(g_bxWe[d] + g_bxWe[7 + d] >= 10)
         dl[nd++] = d;
   if(nd == 0)
      return;
   SecStart("Massimo e minimo della settimana: in quale giorno",
            "In quale giorno cade il massimo e il minimo della settimana, in % delle " + I2S(g_bxWn) + " settimane, contro la quota attesa da un prezzo " +
            "casuale con la volatilit&agrave; di ogni ora (legge dell'arcoseno: gli estremi cadono pi&ugrave; spesso all'inizio e alla fine del periodo). &dagger; = robusto, &sect; = solo FDR.");
   string hd = "Estremo";
   for(int k = 0; k < nd; k++)
      hd += "|" + DOW[dl[k]];
   THead(hd);
   R(g_repBias, "");
   R(g_repBias, "[Massimo e minimo della settimana: giorno in cui cadono, % delle settimane (atteso da un prezzo casuale)]");
   for(int ty = 0; ty < 2; ty++)
     {
      string row = "<tr>" + TD(ty == 0 ? "Massimo della settimana" : "Minimo della settimana");
      string tx = "  " + (ty == 0 ? "Massimo" : "Minimo") + ":";
      for(int k = 0; k < nd; k++)
        {
         int c = ty * 7 + dl[k];
         row += BxCell(FP(g_bxWo[c] / g_bxWn, 1) + " (" + FP(g_bxWe[c] / g_bxWn, 1) + ")", g_bxWz[c], g_bxWt[c]);
         tx += " " + DOW[dl[k]] + " " + FP(g_bxWo[c] / g_bxWn, 1) + "% (atteso " + FP(g_bxWe[c] / g_bxWn, 1) + "%, z " + ZS(g_bxWz[c]) + BxMark(g_bxWt[c]) + ");";
        }
      W(row + "</tr>");
      R(g_repBias, tx);
     }
   TEnd();
   SecEnd();
  }

void BxRenderTg(void)
  {
   if(g_tgNd < 250)
      return;
   SecStart("Quando: l'impulso pi&ugrave; forte, il massimo e il minimo del giorno",
            "Su " + I2S(g_tgNd) + " giorni validi (barre orarie). <b>Impulso pi&ugrave; forte</b> = l'ora con il maggior movimento apertura-chiusura " +
            "del giorno. Atteso: ogni barra oraria del giorno estratta dalla distribuzione storica della propria ora (forma completa: apertura, massimo, minimo e chiusura), indipendente dalle altre (" + I2S(TG_MC) +
            " estrazioni per giorno): &egrave; quanto ci si aspetta se ogni ora avesse la sua volatilit&agrave;, le sue code e la sua deriva e le ore " +
            "fossero indipendenti, quindi un'ora di notizie ha una quota alta anche nell'atteso. Vale per l'impulso, il massimo e il minimo. Una differenza significativa indica una dipendenza dentro la giornata (un'ora forte che ne rende un'altra pi&ugrave; o meno " +
            "probabile), non che l'ora sia prevedibile in anticipo. " +
            "&dagger; = robusto (FDR 5% e stesso verso nelle due met&agrave;), &sect; = solo FDR.");
   THead("Ora|Giorni|Impulso pi&ugrave; forte: % giorni (atteso)|Impulso rialzista %|Massimo del giorno: % (atteso)|Minimo del giorno: % (atteso)");
   R(g_repBias, "");
   R(g_repBias, "[Quando: impulso piu' forte, massimo e minimo del giorno, % dei giorni con quell'ora (atteso); ora dei dati]");
   for(int h = 0; h < 24; h++)
     {
      double nd = g_tgDays[h];
      if(nd < 100)
         continue;
      string row = "<tr>" + TD(HourLab(h)) + TD(I2S((int)nd));
      string tx = "  " + HourLab(h) + " (" + I2S((int)nd) + " giorni):";
      for(int ty = 0; ty < TG_NT; ty++)
        {
         int idx = ty * 24 + h;
         string cellv = FP(g_tgO[idx] / nd, 1) + " (" + FP(g_tgE[idx] / nd, 1) + ")";
         row += BxCell(cellv, g_tgZ[idx], g_tgT[idx]);
         tx += " " + TG_TN[ty] + " " + cellv + "% z " + ZS(g_tgZ[idx]) + BxMark(g_tgT[idx]) + ";";
         if(ty == 0)
           {
            if(g_tgUn[h] >= 30)
              {
               row += BxCell(FP(g_tgUu[h] / g_tgUn[h], 0), g_tgUz[h], g_tgUt[h]);
               tx += " impulso rialzista " + FP(g_tgUu[h] / g_tgUn[h], 1) + "% (z " + ZS(g_tgUz[h]) + BxMark(g_tgUt[h]) + ");";
              }
            else
               row += TD("&ndash;");
           }
        }
      W(row + "</tr>");
      R(g_repBias, tx);
     }
   TEnd();
   SecEnd();
   for(int pt = 0; pt < TG_NP; pt++)
     {
      bool causal = pt == 1;
      SecStart("Cosa precede: " + TG_PN[pt] + " (" + I2S(g_tgCases[pt]) + " casi)",
               (causal ? "Un impulso forte &egrave; una barra oraria tra il 2% dei movimenti pi&ugrave; ampi di quell'ora (soglia fissa per ora, dall'intero " +
                "storico): si riconosce dalla barra stessa, senza guardare le altre barre del giorno, quindi le condizioni prima sono informazioni " +
                "disponibili in anticipo. " :
                "L'impulso pi&ugrave; forte del giorno &egrave; scelto a posteriori, tra tutte le barre della giornata: scegliere il massimo di una serie " +
                "crea differenze meccaniche con quello che precede (per esempio le barre prima tendono a essere pi&ugrave; piccole, altrimenti non sarebbe " +
                "il massimo). Le celle sono descrittive: nessun test n&eacute; &dagger;, non sono segnali. Per condizioni utilizzabili in anticipo guarda gli " +
                "impulsi forti sotto. ") +
               "Per ogni caso, la situazione nelle barre <b>prima</b>, confrontata con le altre barre della stessa ora negli altri giorni, nel verso " +
               "dell'impulso (a favore = nella direzione dell'impulso). ATR = ATR(14) orario; sweep = il prezzo ha gi&agrave; superato il massimo o il minimo " +
               "di ieri prima di questa barra." + (causal ? " &dagger; = robusto (FDR 5% e stesso verso nelle due met&agrave;), &sect; = solo FDR." : ""));
      THead("Caratteristica|Classe|Casi|% dei casi|% atteso (stessa ora)|z");
      R(g_repBias, "");
      R(g_repBias, "[Cosa precede: " + TG_PN[pt] + ", " + I2S(g_tgCases[pt]) + " casi" + (causal ? "" : "; descrittivo, scelto a posteriori: differenze in parte meccaniche") + "]");
      for(int fi = 0; fi < TG_NF; fi++)
        {
         double u = g_tgFn[pt * TG_NF + fi];
         if(u < 30)
            continue;
         Grp(TG_FN[fi], 6);
         R(g_repBias, "  " + TG_FN[fi] + ":");
         for(int ci = 0; ci < TG_NCL[fi]; ci++)
           {
            int gx = (pt * TG_NF + fi) * TG_NC + ci;
            W("<tr>" + TD(TG_FN[fi]) + TD(TG_CL[fi * TG_NC + ci]) + TD(I2S((int)u)) + TD(FP(g_tgFO[gx] / u, 1)) + TD(FP(g_tgFE[gx] / u, 1)) +
              (causal ? TDc("z " + ZS(g_tgFZ[gx]) + BxMark(g_tgFt[gx]), PCol(g_tgFZ[gx], 0, 5)) : TD("z " + ZS(g_tgFZ[gx]))) + "</tr>");
            R(g_repBias, "    " + TG_CL[fi * TG_NC + ci] + ": " + FP(g_tgFO[gx] / u, 1) + "% dei casi contro " + FP(g_tgFE[gx] / u, 1) + "% atteso (N " +
              I2S((int)u) + ", z " + ZS(g_tgFZ[gx]) + BxMark(g_tgFt[gx]) + ")");
           }
        }
      TEnd();
      SecEnd();
     }
  }

// i confronti del modulo Bias che sopravvivono al controllo FDR e sono stabili nelle due meta'
int BxRobustCount(void)
  {
   int n = 0;
   for(int t = 0; t < g_bxNT; t++)
      if(g_bxTfd[t] && g_bxTst[t])
         n++;
   return n;
  }

string BxKindName(const int k)
  {
   if(k == 0)
      return "Direzione: quanto spesso sale, rendimento medio, direzione dell'impulso";
   if(k == 1)
      return "Volatilit&agrave;: quanto si muove (range)";
   if(k == 2)
      return "Timing e struttura: massimo e minimo nel periodo, trend e mean reversion, giorno degli estremi della settimana, ora dell'impulso e degli estremi del giorno";
   return "Cosa precede un impulso forte (condizioni note in anticipo)";
  }

void BxRobust(void)
  {
   int n = 0, nHint = 0;
   double zz[];
   int idx[];
   ArrayResize(zz, g_bxNT);
   ArrayResize(idx, g_bxNT);
   for(int t = 0; t < g_bxNT; t++)
     {
      if(MathAbs(g_bxTz[t]) >= 2)
         nHint++;
      if(g_bxTfd[t] && g_bxTst[t])
        {
         zz[n] = MathAbs(g_bxTz[t]);
         idx[n] = t;
         n++;
        }
     }
   int ord[];
   EdOrder(zz, n, ord);
   SecStart("Bias robusti",
            "Su " + I2S(g_bxNT) + " confronti di questa scheda, " + I2S(nHint) + " superano |z| 2 e " + I2S(n) + " sopravvivono al controllo del tasso di falsi " +
            "positivi (FDR 5%, Benjamini-Hochberg) <b>e</b> hanno lo stesso verso nelle due met&agrave; dello storico. Sono i soli bias di questa scheda che " +
            "non si spiegano facilmente con il caso. Sono raggruppati per tipo: la <b>volatilit&agrave;</b> (ore e giorni pi&ugrave; o meno mossi) &egrave; quasi " +
            "sempre robusta perch&eacute; l'attivit&agrave; ha un ritmo giornaliero forte, ma non d&agrave; una direzione; la <b>direzione</b> &egrave; quella " +
            "che conta per un edge. Un bias descrittivo non &egrave; un edge: va tradotto in una regola, provato con i costi e verificato fuori campione.");
   R(g_repBias, "");
   R(g_repBias, "[Bias robusti: " + I2S(n) + " su " + I2S(g_bxNT) + " confronti (FDR 5% e stabili nelle due meta'); " + I2S(nHint) + " superano |z| 2]");
   if(n == 0)
     {
      W("<p class='muted'>Nessun confronto supera insieme il controllo FDR e il test delle due met&agrave;.</p>");
      R(g_repBias, "  nessuno");
     }
   else
     {
      int kord[4] = {0, 3, 2, 1};
      int caps[4] = {20, 15, 12, 8};
      for(int kk = 0; kk < 4; kk++)
        {
         int kind = kord[kk], cnt = 0, shown = 0;
         for(int j = 0; j < n; j++)
            if(g_bxTk[idx[ord[j]]] == kind)
               cnt++;
         R(g_repBias, "  " + BxKindName(kind) + " - " + I2S(cnt) + " robusti:");
         if(cnt == 0)
            continue;
         W("<h3>" + BxKindName(kind) + " (" + I2S(cnt) + ")</h3>");
         THead("z|Risultato");
         for(int j = 0; j < n; j++)
           {
            int t = idx[ord[j]];
            if(g_bxTk[t] != kind)
               continue;
            R(g_repBias, "    z " + ZS(g_bxTz[t]) + " | " + g_bxTtx[t]);
            if(shown < caps[kk])
              {
               W("<tr>" + TDc(ZS(g_bxTz[t]), PCol(g_bxTz[t], 0, 6)) + "<td style='text-align:left;white-space:normal'>" + g_bxTtx[t] + "</td></tr>");
               shown++;
              }
           }
         TEnd();
         if(cnt > shown)
            W("<p class='muted'>Altri " + I2S(cnt - shown) + " nel testo Bias.</p>");
        }
     }
   SecEnd();
  }

//+------------------------------------------------------------------+
//| Scheda Bias e impulsi                                             |
//+------------------------------------------------------------------+
void BiasTab(CSeries &h1, CSeries &d1)
  {
   g_repBias = "";
   HI_NAME[ED_MB] = "Bias del calendario: ogni categoria (ora, giorno, mese...) contro tutti i periodi, ora x giorno, massimo e minimo della settimana";
   HI_NAME[ED_MT] = "Impulso piu' forte, massimo e minimo del giorno: a che ora avvengono (contro l'atteso) e cosa li precede (contro la stessa ora)";
   R(g_repBias, "=== BIAS E IMPULSI ===");
   if(h1.n < 5000 && d1.n < 500)
     {
      SecStart("Bias e impulsi", "");
      W("<p class='muted'>Servono barre H1 e D1.</p>");
      SecEnd();
      R(g_repBias, "  non calcolato (servono barre H1 e D1)");
      return;
     }
   MathSrand(777);
   g_bxLast = h1.n > 0 ? h1.t[h1.n - 1] : (d1.n > 0 ? d1.t[d1.n - 1] : (datetime)0);
   if(h1.n >= 2000)
      BxVarProfile(h1);
   int tl[11] = {1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12};
   CBlocks b;
   for(int k = 0; k < 11 && !IsStopped(); k++)
     {
      int tfi = tl[k];
      bool ok = false;
      if(tfi <= 7)
         ok = h1.n > 50 && Build(tfi, 1, h1, b, 0);
      else
         ok = d1.n > 50 && Build(tfi, 2, d1, b, 0);
      if(!ok)
        {
         b.Free();
         continue;
        }
      datetime tMid = (datetime)((long)b.t0[0] + ((long)b.t0[b.N - 1] - (long)b.t0[0]) / 2);
      BxDigest(tfi, b);
      if(tfi != 7 && tfi != 12)
         BxTf(tfi, b, tMid);
      if(tfi == 1)
         BxHeat(b, tMid);
      if(tfi == 6)
         BxYear(b);
      b.Free();
     }
   if(h1.n >= 2000)
     {
      datetime tMidH = (datetime)((long)h1.t[0] + ((long)h1.t[h1.n - 1] - (long)h1.t[0]) / 2);
      BxWeek(h1, tMidH);
      TgRun(h1, tMidH);
     }
   //--- controllo FDR su tutti i confronti di ogni modulo, poi registrazione nel riepilogo generale
   for(int mod = ED_MB; mod <= ED_MT; mod++)
     {
      double zz[];
      int idx[];
      int kk = 0;
      ArrayResize(zz, g_bxNT);
      ArrayResize(idx, g_bxNT);
      for(int t = 0; t < g_bxNT; t++)
         if(g_bxTm[t] == mod)
           {
            zz[kk] = g_bxTz[t];
            idx[kk] = t;
            kk++;
           }
      bool fl[];
      EdBhFlags(zz, kk, (double)kk, 0.05, fl);
      for(int j = 0; j < kk; j++)
         g_bxTfd[idx[j]] = fl[j];
     }
   for(int t = 0; t < g_bxNT; t++)
      Hi(g_bxTm[t], g_bxTz[t], g_bxTtx[t]);
   //--- pagina
   SecStart("Bias e impulsi: come leggere",
            "Tendenze del prezzo per ora, blocchi di 4/6/8/12 ore, giorno della settimana, mese, trimestre e semestre; ora x giorno; giorno " +
            "della settimana in cui cadono il massimo e il minimo della settimana; ora dell'impulso pi&ugrave; forte del giorno e del massimo e " +
            "minimo del giorno; cosa li precede. Ogni valore &egrave; confrontato con un riferimento (tutti i periodi, la stessa ora negli altri " +
            "giorni, un prezzo casuale) e ha uno <b>z</b> (entro &plusmn;2 compatibile con il caso). Poich&eacute; i confronti sono centinaia, " +
            "molti supereranno |z| 2 per caso: per questo ogni risultato ha due controlli, il tasso di falsi positivi (FDR 5% su tutti i " +
            "confronti di questa scheda) e la <b>stabilit&agrave;</b> (stesso verso nella prima e nella seconda met&agrave; dello storico). " +
            "<b>&dagger;</b> = supera entrambi. Tutto quello che non ha il &dagger; va letto come rumore probabile. Gli orari sono quelli dei dati. " +
            "I giorni e le ore dipendono dal fuso: con i dati del broker (New York + 7) il giorno va da NY 17:00 a NY 17:00.");
   SecEnd();
   BxRobust();
   BxRenderTg();
   int tll[9] = {1, 6, 2, 3, 4, 5, 9, 10, 11};
   for(int k = 0; k < 9; k++)
      BxRenderTf(tll[k]);
   BxRenderHeat();
   BxRenderWeek();
   if(g_bxYr != "")
     {
      SecStart("Anno per anno (giorni)", "Come cambiano rialzisti, spostamento e tipo di giornata da un anno all'altro (descrittivo).");
      W(g_bxYr);
      SecEnd();
      R(g_repBias, "");
      R(g_repBias, g_bxYrTx);
     }
   if(g_bxDig != "")
     {
      SecStart("Carattere dei timeframe", "Spostamento tipico, direzione e persistenza per timeframe. L'ultima colonna dice quanto spesso il periodo successivo va " +
               "nella stessa direzione, con z contro la sola prevalenza dei periodi rialzisti (positivo = momentum, negativo = mean reversion tra periodi).");
      THead("Timeframe|Periodi|Spostamento mediano %|&asymp; prezzo|% rialzisti|% Trend|% Mean rev.|Restituito medio %|Periodo dopo nella stessa direzione");
      W(g_bxDig);
      TEnd();
      SecEnd();
      R(g_repBias, "");
      R(g_repBias, "[Carattere dei timeframe]");
      R(g_repBias, g_bxDigTx);
     }
  }

//+------------------------------------------------------------------+
//| Scheda Sintesi edge                                               |
//+------------------------------------------------------------------+
#define ED_TOP 6   // combinazioni ORB mostrate tra le migliori in assoluto

string EdMk(const int v)
  {
   if(v == 1)
      return "<span style='color:" + C_GREEN + "'>&#10003;</span>";
   if(v == 0)
      return "<span style='color:" + C_RED + "'>&#10007;</span>";
   return "<span class='muted'>&ndash;</span>";
  }

// cella di controllo: valore e simbolo; se il controllo non si applica solo il trattino
string EdCk(const string v, const int ck) { return ck < 0 ? TD(EdMk(ck)) : TD(v + " " + EdMk(ck)); }

string EdMkT(const int v) { return v == 1 ? "si" : (v == 0 ? "NO" : "n/d"); }
string EdLvName(const int lv)
  {
   if(lv == 1 && g_edCbSrc == 0)
      return "INDIZIO LORDO";
   return lv == 3 ? "ROBUSTO" : (lv == 2 ? "PROMETTENTE" : (lv == 1 ? "INDIZIO" : "SCARTATO"));
  }
string EdLvCol(const int lv) { return lv == 3 ? C_GREEN : (lv == 2 ? C_BLUE : (lv == 1 ? C_AMBER : C_GREY)); }

// nel rapporto le entita' HTML sono decodificate dalla textarea (come nel resto dello script)
string EdPlain(const string s) { return s; }

// i migliori ORB in assoluto (z netto del broker peggiore), anche se non hanno superato i filtri delle regole
void EdOrbTop(const double orbT)
  {
   int ntr = ArraySize(g_otN);
   if(!InpOrb || ntr <= 0)
      return;
   int tt[ED_TOP];
   double tz[ED_TOP];
   int nt = 0;
   for(int tr = 0; tr < ntr; tr++)
     {
      if(g_otN[tr] < 100 || !MathIsValidNumber(g_otZw[tr]) || g_osDay[tr / (3 * OB_NT) / g_obNF] < g_obMinDay)
         continue;
      double z = g_otZw[tr];
      if(nt == ED_TOP && z <= tz[ED_TOP - 1])
         continue;
      int p = nt < ED_TOP ? nt : ED_TOP - 1;
      while(p > 0 && tz[p - 1] < z)
        {
         tz[p] = tz[p - 1];
         tt[p] = tt[p - 1];
         p--;
        }
      tz[p] = z;
      tt[p] = tr;
      if(nt < ED_TOP)
         nt++;
     }
   if(nt == 0)
      return;
   double zc = EdZCrit(0.05, orbT);
   SecStart("ORB: le combinazioni migliori in assoluto",
            "Le " + I2S(nt) + " combinazioni ORB con lo z netto del broker peggiore pi&ugrave; alto tra " + F(orbT, 0) + " confronti con almeno 100 trade " +
            "(orari coperti). Per confronto: con questo numero di combinazioni la soglia di Bonferroni (5%) &egrave; z = " + F(zc, 1) +
            "; la migliore di molte combinazioni correlate supera spesso z 3 per solo effetto della selezione. Servono stabilit&agrave; nelle due " +
            "met&agrave;, vantaggio sul placebo, costo di pareggio sopra il costo del broker e, soprattutto, conferma fuori campione.");
   THead("Combinazione e operazione|Trade|Netta peggiore R|z|Stabile|Placebo z|Costo di pareggio|Nelle regole");
   R(g_repEdge, "");
   R(g_repEdge, "[ORB: migliori in assoluto su " + F(orbT, 0) + " confronti (soglia di Bonferroni z " + F(zc, 1) + ")]");
   for(int r = 0; r < nt; r++)
     {
      int tr = tt[r], t = (tr / 3) % OB_NT, sd = tr % 3, cf = tr / (3 * OB_NT);
      bool inRule = false;
      for(int q = 0; q < g_orN; q++)
         if(g_orX[q] == tr)
            inRule = true;
      string lab = OB_OP[t] + " | " + ObCfLab(cf) + ", " + OB_SIDE[sd];
      W("<tr><td style='text-align:left;white-space:normal'>" + lab + "</td>" + TD(I2S(g_otN[tr])) + TD(SgnF(g_otEw[tr], 3)) +
        TDc(ZS(g_otZw[tr]), PCol(g_otZw[tr], 0, 5)) + TD(g_otSt[tr] ? "si" : "no") + TD(ZS(g_otZp[tr])) + TD(BpTxt(g_otBe[tr])) +
        TD(inRule ? "s&igrave;" : "no") + "</tr>");
      R(g_repEdge, "  " + EdPlain(lab) + ": " + I2S(g_otN[tr]) + " trade, netta peggiore " + SgnF(g_otEw[tr], 3) + " R, z " + ZS(g_otZw[tr]) +
        (g_otSt[tr] ? ", stabile" : ", non stabile") + ", placebo z " + ZS(g_otZp[tr]) + ", costo di pareggio " + BpTxt(g_otBe[tr]) +
        (inRule ? ", esportata come regola" : ""));
     }
   TEnd();
   SecEnd();
  }

// riga della tabella per timeframe e categoria (-1 se assente)
int EdRow(const int tfi, const int cat)
  {
   for(int r = 0; r < g_bxRN; r++)
      if(g_bxRTf[r] == tfi && g_bxRCat[r] == cat)
         return r;
   return -1;
  }

// profilo compatto: 24 ore e giorni della settimana (direzione e volatilita')
void EdProfile(void)
  {
   int rAll1 = EdRow(1, -1), rAll6 = EdRow(6, -1);
   if(rAll1 < 0 && rAll6 < 0)
      return;
   SecStart("Profilo di ore e giorni",
            "Sintesi delle tendenze del prezzo per ora del giorno e giorno della settimana (orario dei dati; tra parentesi l'ora della piazza di " +
            "riferimento nelle schede complete). <b>Range</b> = movimento mediano in volte quello di tutte le ore; <b>% rialzista</b> = quota di barre " +
            "che salgono, con lo z contro tutte le ore. &dagger; = robusto (FDR 5% e stabile nelle due met&agrave;). Il range dice <i>quando</i> il prezzo si muove, " +
            "non in che direzione: solo la % rialzista e il rendimento riguardano la direzione.");
   R(g_repEdge, "");
   R(g_repEdge, "[Profilo di ore e giorni]");
   if(rAll1 >= 0)
     {
      double medAll = g_bxRMed[rAll1];
      string h1 = "<tr><th>Ora</th>", r1 = "<tr>" + TD("Range (volte la media)"), r2 = "<tr>" + TD("% rialzista"), tx1 = "  Ore, range (x media): ", tx2 = "  Ore, % rialzista (z): ";
      for(int k = 0; k < 24; k++)
        {
         int r = EdRow(1, k);
         h1 += "<th>" + StringFormat("%02d", k) + "</th>";
         if(r < 0)
           {
            r1 += TD("&ndash;");
            r2 += TD("&ndash;");
            continue;
           }
         int b0 = r * BX_NM;
         double ratio = (MathIsValidNumber(medAll) && medAll > 0) ? g_bxRMed[r] / medAll : Nan();
         r1 += TDc(F(ratio, 2) + BxMark(g_bxRT[b0 + 2]), PCol(MathIsValidNumber(ratio) ? MathLog(ratio) : Nan(), 0, 0.5));
         r2 += TDc(FP(g_bxRV[b0], 0) + " <small>" + ZS(g_bxRZ[b0]) + BxMark(g_bxRT[b0]) + "</small>", PCol(g_bxRZ[b0], 0, 5));
         tx1 += StringFormat("%02d", k) + "h " + F(ratio, 2) + BxMark(g_bxRT[b0 + 2]) + "; ";
         tx2 += StringFormat("%02d", k) + "h " + FP(g_bxRV[b0], 1) + "% (" + ZS(g_bxRZ[b0]) + BxMark(g_bxRT[b0]) + "); ";
        }
      W("<div class='tw'><table><thead>" + h1 + "</tr></thead><tbody>" + r1 + "</tr>" + r2 + "</tr></tbody></table></div>");
      R(g_repEdge, tx1);
      R(g_repEdge, tx2);
     }
   if(rAll6 >= 0)
     {
      double medAll = g_bxRMed[rAll6];
      THead("Giorno|Periodi|% rialzista|Rendimento medio %|Range (volte la media)|Massimo nel primo terzo|Minimo nel primo terzo");
      for(int k = 0; k < 7; k++)
        {
         int r = EdRow(6, k);
         if(r < 0)
            continue;
         int b0 = r * BX_NM;
         double ratio = (MathIsValidNumber(medAll) && medAll > 0) ? g_bxRMed[r] / medAll : Nan();
         W("<tr>" + TD(g_bxRLb[r]) + TD(I2S(g_bxRn[r])) + BxCell(FP(g_bxRV[b0], 1), g_bxRZ[b0], g_bxRT[b0]) +
           BxCell(FP(g_bxRV[b0 + 1], 3), g_bxRZ[b0 + 1], g_bxRT[b0 + 1]) + BxCell(F(ratio, 2), g_bxRZ[b0 + 2], g_bxRT[b0 + 2]) +
           BxCell(FP(g_bxRV[b0 + 3], 0), g_bxRZ[b0 + 3], g_bxRT[b0 + 3]) + BxCell(FP(g_bxRV[b0 + 4], 0), g_bxRZ[b0 + 4], g_bxRT[b0 + 4]) + "</tr>");
         R(g_repEdge, "  " + g_bxRLb[r] + " (" + I2S(g_bxRn[r]) + " giorni): rialzisti " + FP(g_bxRV[b0], 1) + "% (z " + ZS(g_bxRZ[b0]) + BxMark(g_bxRT[b0]) +
           "), rendimento medio " + FP(g_bxRV[b0 + 1], 3) + "% (z " + ZS(g_bxRZ[b0 + 1]) + BxMark(g_bxRT[b0 + 1]) + "), range x" + F(ratio, 2) +
           " (z " + ZS(g_bxRZ[b0 + 2]) + BxMark(g_bxRT[b0 + 2]) + "), massimo nel primo terzo " + FP(g_bxRV[b0 + 3], 0) + "%, minimo nel primo terzo " +
           FP(g_bxRV[b0 + 4], 0) + "%");
        }
      TEnd();
     }
   SecEnd();
  }

// elenco dei bias robusti di un tipo (0 direzione, 1 volatilita', 2 timing, 3 cosa precede)
void EdBiasKind(const int kind, const int cap)
  {
   int n = 0;
   double zz[];
   int idx[];
   ArrayResize(zz, g_bxNT);
   ArrayResize(idx, g_bxNT);
   for(int t = 0; t < g_bxNT; t++)
      if(g_bxTk[t] == kind && g_bxTfd[t] && g_bxTst[t])
        {
         zz[n] = MathAbs(g_bxTz[t]);
         idx[n] = t;
         n++;
        }
   int ord[];
   EdOrder(zz, n, ord);
   R(g_repEdge, "  " + BxKindName(kind) + ": " + I2S(n) + " robusti");
   if(n == 0)
     {
      W("<p class='muted'><b>" + BxKindName(kind) + "</b>: nessun bias robusto.</p>");
      return;
     }
   W("<h3>" + BxKindName(kind) + " (" + I2S(n) + " robusti)</h3>");
   THead("z|Risultato");
   for(int j = 0; j < n && j < cap; j++)
     {
      int t = idx[ord[j]];
      W("<tr>" + TDc(ZS(g_bxTz[t]), PCol(g_bxTz[t], 0, 6)) + "<td style='text-align:left;white-space:normal'>" + g_bxTtx[t] + "</td></tr>");
      R(g_repEdge, "    z " + ZS(g_bxTz[t]) + " | " + EdPlain(g_bxTtx[t]));
     }
   TEnd();
   if(n > cap)
     {
      W("<p class='muted'>Altri " + I2S(n - cap) + " nella scheda Bias e impulsi.</p>");
      R(g_repEdge, "    ... altri " + I2S(n - cap) + " nella scheda Bias e impulsi");
     }
  }

// bias del momento: le categorie dell'ultima barra dei dati (giorno, ora, mese...) lette nelle tabelle storiche
void EdNow(void)
  {
   if(g_bxLast <= 0 || g_bxRN == 0)
      return;
   MqlDateTime d;
   TimeToStruct(g_bxLast, d);
   int dw = DowMon(g_bxLast), hr = d.hour, mo = d.mon - 1;
   int tf[7] = {6, 1, 2, 4, 9, 10, 11};
   int ct[7] = {dw, hr, hr / 4, hr / 8, mo, mo / 3, mo / 6};
   string lb[7] = {"Giorno della settimana", "Ora del giorno", "Blocco di 4 ore", "Blocco di 8 ore", "Mese", "Trimestre", "Semestre"};
   bool any = false;
   for(int k = 0; k < 7; k++)
      if(EdRow(tf[k], ct[k]) >= 0)
         any = true;
   if(!any)
      return;
   SecStart("Bias del momento",
            "Le categorie a cui appartiene l'ultima barra dei dati (" + TimeToString(g_bxLast, TIME_DATE | TIME_MINUTES) + ", " + DOW[dw] + "), lette nelle tabelle " +
            "storiche: come si &egrave; comportato il prezzo in quel giorno, ora, mese, trimestre e semestre rispetto a tutti gli altri. &dagger; = robusto. " +
            "&Egrave; contesto, non un segnale: un bias di calendario piccolo o non robusto non giustifica un'operazione.");
   THead("Categoria|Valore|Periodi|% rialzista|Rendimento medio %|Range (volte la media)|Lettura");
   R(g_repEdge, "");
   R(g_repEdge, "[Bias del momento: ultima barra " + TimeToString(g_bxLast, TIME_DATE | TIME_MINUTES) + ", " + DOW[dw] + "]");
   for(int k = 0; k < 7; k++)
     {
      int r = EdRow(tf[k], ct[k]), ra = EdRow(tf[k], -1);
      if(r < 0)
         continue;
      int b0 = r * BX_NM;
      double medAll = ra >= 0 ? g_bxRMed[ra] : Nan();
      double ratio = (MathIsValidNumber(medAll) && medAll > 0) ? g_bxRMed[r] / medAll : Nan();
      string rd = BxReadRow(r);
      W("<tr>" + TD(lb[k]) + TD(g_bxRLb[r]) + TD(I2S(g_bxRn[r])) + BxCell(FP(g_bxRV[b0], 1), g_bxRZ[b0], g_bxRT[b0]) +
        BxCell(FP(g_bxRV[b0 + 1], 3), g_bxRZ[b0 + 1], g_bxRT[b0 + 1]) + BxCell(F(ratio, 2), g_bxRZ[b0 + 2], g_bxRT[b0 + 2]) + TD(rd) + "</tr>");
      R(g_repEdge, "  " + lb[k] + " " + g_bxRLb[r] + " (N " + I2S(g_bxRn[r]) + "): rialzisti " + FP(g_bxRV[b0], 1) + "% (z " + ZS(g_bxRZ[b0]) + BxMark(g_bxRT[b0]) +
        "), rendimento medio " + FP(g_bxRV[b0 + 1], 3) + "% (z " + ZS(g_bxRZ[b0 + 1]) + BxMark(g_bxRT[b0 + 1]) + "), range x" + F(ratio, 2) + " (z " +
        ZS(g_bxRZ[b0 + 2]) + BxMark(g_bxRT[b0 + 2]) + ") -> " + rd);
     }
   int c = hr * 7 + dw;
   if(g_bxHn[c] >= 30)
     {
      W("<tr>" + TD("Ora x giorno") + TD(StringFormat("%02dh", hr) + " del " + DOW[dw]) + TD(I2S(g_bxHn[c])) + BxCell(FP(g_bxHu[c], 1), g_bxHzu[c], g_bxHtu[c]) +
        TD("&ndash;") + BxCell(F(g_bxHr[c], 2), g_bxHzr[c], g_bxHtr[c]) + TD("contro la stessa ora negli altri giorni") + "</tr>");
      R(g_repEdge, "  Ora x giorno " + StringFormat("%02dh", hr) + " del " + DOW[dw] + " (N " + I2S(g_bxHn[c]) + "): rialzista " + FP(g_bxHu[c], 1) + "% (z " +
        ZS(g_bxHzu[c]) + BxMark(g_bxHtu[c]) + "), range x" + F(g_bxHr[c], 2) + " (z " + ZS(g_bxHzr[c]) + BxMark(g_bxHtr[c]) + ")");
     }
   TEnd();
   SecEnd();
  }

void EdgeTab(const string sym)
  {
   g_repEdge = "";
   EdgeAddOrb();
   EdFdrAll();
   double cbNow = EdCostBp();   // fissa anche l'origine del costo (g_edCbSrc)
   int nC = g_edNC;
   int lev[], cks[];
   double mt[], sc[];
   ArrayResize(lev, nC);
   ArrayResize(cks, nC * 8);
   ArrayResize(mt, nC);
   ArrayResize(sc, nC);
   int cnt[4];
   ArrayInitialize(cnt, 0);
   double orbT = EdOrbTests();
   for(int i = 0; i < nC; i++)
     {
      mt[i] = EdTests(i, orbT);
      int ck[];
      lev[i] = EdChecks(i, mt[i], ck);
      for(int k = 0; k < 8; k++)
         cks[i * 8 + k] = ck[k];
      sc[i] = (g_edKd[i] == 0 ? 0.0 : 1000.0) + lev[i] * 100.0 + MathMax(-50.0, MathMin(MathIsValidNumber(g_edZ[i]) ? g_edZ[i] : -50.0, 49.0));
      if(g_edKd[i] != 0)
         cnt[lev[i]]++;
     }
   // costi di pareggio dei candidati positivi (indizi o meglio): servono a leggere il verdetto quando i costi del broker mancano
   double beLo = Nan(), beHi = Nan();
   for(int i = 0; i < nC; i++)
      if(g_edKd[i] != 0 && lev[i] >= 1 && MathIsValidNumber(g_edBe[i]) && g_edBe[i] > 0)
        {
         if(!MathIsValidNumber(beLo) || g_edBe[i] < beLo)
            beLo = g_edBe[i];
         if(!MathIsValidNumber(beHi) || g_edBe[i] > beHi)
            beHi = g_edBe[i];
        }
   double tests = 0, exp3 = 0;
   int n3 = 0, nf = 0;
   for(int m = 0; m < HI_NMOD; m++)
     {
      tests += g_hiCnt[m];
      exp3 += 0.0027 * g_hiCnt[m];
      n3 += g_edN3[m];
      nf += g_edNfdr[m];
     }
   int bk[4], bt[4];
   ArrayInitialize(bk, 0);
   ArrayInitialize(bt, 0);
   for(int t = 0; t < g_bxNT; t++)
     {
      bt[g_bxTk[t]]++;
      if(g_bxTfd[t] && g_bxTst[t])
         bk[g_bxTk[t]]++;
     }
   //--- pagina: testa e verdetto
   R(g_repEdge, "SINTESI EDGE - " + sym);
   SecStart("Sintesi: dove esiste un edge e dove no",
            "Riassunto di tutte le schede. Un <b>edge</b> qui significa: una regola che con i costi del broker resta positiva, non si spiega con " +
            "l'orario o con il semplice movimento del prezzo, ha lo stesso segno nelle due met&agrave; dello storico e regge al fatto che sono " +
            "stati provati migliaia di contesti. Sotto trovi il verdetto, la tabella dei candidati con ogni controllo, cosa sopravvive ai test " +
            "multipli in ogni area, i bias del calendario e i numeri di base da cui cercare tu stesso.");
   W("<div class='kpi'>");
   Kpi("Confronti statistici", I2S((int)tests), "in tutte le schede");
   Kpi("Oltre z 3", I2S(n3), "attesi per solo caso: " + F(exp3, 0));
   Kpi("Sopravvivono al controllo FDR", I2S(nf), "falsi positivi attesi al massimo 5%");
   Kpi("Costo del broker", g_edCbSrc == 0 ? "n/d" : F(cbNow, 2) + " pb", g_edCbSrc == 0 ? "non misurato: risultati al lordo" : (g_edCbSrc == 1 ? "misurato, broker pi&ugrave; caro" : "riferimento manuale"));
   Kpi("Strategie robuste", I2S(cnt[3]), g_edCbSrc == 0 ? "impossibile senza i costi del broker" : "superano tutti i controlli");
   Kpi("Strategie promettenti", I2S(cnt[2]), g_edCbSrc == 0 ? "impossibile senza i costi del broker" : "tutto tranne i test multipli");
   Kpi(g_edCbSrc == 0 ? "Indizi lordi" : "Indizi", I2S(cnt[1]), g_edCbSrc == 0 ? "positive e stabili al lordo dei costi" : "positive e stabili, ma con un controllo non superato");
   Kpi("Bias di direzione robusti", I2S(bk[0]), "su " + I2S(bt[0]) + " confronti (FDR e stabili)");
   Kpi("Precursori di impulsi robusti", I2S(bk[3]), "su " + I2S(bt[3]) + " confronti");
   Kpi("Bias di volatilit&agrave;", I2S(bk[1]), "ritmo dell'attivit&agrave;, non direzione");
   W("</div>");
   string head, col, costWarn = "";
   if(g_edCbSrc == 0)
     {
      // senza costi il controllo V non e' eseguibile: il verdetto e' al lordo e nessun candidato puo' superare 'indizio'
      costWarn = "ATTENZIONE: i costi del broker non sono disponibili per questo simbolo (nessun profilo misurato, oppure spread nullo, come nei simboli personalizzati). " +
                 "Tutti i risultati sono AL LORDO dei costi e il controllo V (costo) non e' stato eseguito. " +
                 (MathIsValidNumber(beHi) ? "Il costo di pareggio dei candidati positivi va da " + F(beLo, 1) + " a " + F(beHi, 1) + " pb: una regola regge solo se il costo reale per trade " +
                  "(spread + commissione + slittamento) e' inferiore al suo pareggio diviso 1,5. " : "") +
                 "Per avere il controllo: misura i costi con InpCostsOnly = true nel terminale del broker (poi rilancia qui), oppure indica un costo in punti base in InpEdRefCostBp.";
      if(cnt[1] > 0)
        {
         head = "Al lordo dei costi " + I2S(cnt[1]) + " strategie sono positive e stabili, ma senza i costi del broker nessuna puo' essere dichiarata robusta o promettente. Decide il costo di pareggio contro il costo reale per trade.";
         col = C_AMBER;
        }
      else
        {
         head = "Nessuna strategia supera i filtri, nemmeno al lordo dei costi (che qui non sono disponibili): tra i contesti, le coppie e gli ORB provati non c'e' un edge.";
         col = C_RED;
        }
     }
   else
      if(cnt[3] > 0)
        {
         head = "Almeno una strategia supera tutti i controlli, compresa la soglia dei test multipli. Non e' una garanzia: e' il punto di partenza per la verifica fuori campione.";
         col = C_GREEN;
        }
      else
         if(cnt[2] > 0)
           {
            head = "Nessuna strategia supera la soglia dei test multipli. " + I2S(cnt[2]) + " passano tutti gli altri controlli (promettenti): sono le sole da verificare fuori campione, sapendo che ognuna potrebbe essere la migliore di molti tentativi.";
            col = C_BLUE;
           }
         else
            if(cnt[1] > 0)
              {
               head = "Solo indizi: " + I2S(cnt[1]) + " strategie sono positive e stabili ma falliscono almeno un controllo (stessa ora, placebo, costo o test multipli). Cosi' non sono operabili.";
               col = C_AMBER;
              }
            else
              {
               head = "Nessuna strategia supera i filtri: in questi dati, con questi costi, tra i contesti, le coppie e gli ORB provati non c'e' un edge operabile.";
               col = C_RED;
              }
   string stat = "Confronti totali " + I2S((int)tests) + ". Oltre z 3 ne trovi " + I2S(n3) + " contro circa " + F(exp3, 0) + " attesi per puro caso (se i confronti fossero indipendenti); " +
                 I2S(nf) + " sopravvivono al controllo FDR" + (bk[1] > 0 ? " (di cui " + I2S(bk[1]) + " solo volatilita', cioe' il ritmo giornaliero dell'attivita')" : "") + ". " +
                 (n3 <= 1.5 * exp3 + 3 ? "Il numero di risultati forti e' compatibile con il caso: senza un controllo serio, quasi tutto quello che vedi nelle schede e' rumore." :
                  "Ci sono piu' risultati forti di quanti ne darebbe il caso: guarda le aree con eccesso nella tabella sotto.");
   string bs = bk[0] > 0 ? I2S(bk[0]) + " bias di DIREZIONE (ora, giorno, mese, ora x giorno) superano FDR e stabilita': sono ipotesi da trasformare in regola e verificare fuori campione." :
               "Nessun bias di direzione (ora, giorno, mese, ora x giorno) supera insieme FDR e stabilita': la direzione del prezzo per calendario e' compatibile con il caso.";
   bs += " Bias di volatilita': " + I2S(bk[1]) + " robusti (il prezzo si muove di piu' o di meno a certe ore e giorni: e' il ritmo dell'attivita', non da' una direzione)." +
         " Cosa precede un impulso forte: " + I2S(bk[3]) + " condizioni robuste. Timing e struttura: " + I2S(bk[2]) + ".";
   if(costWarn != "")
      W("<div style='border-left:4px solid " + C_RED + ";padding:10px 14px;background:#2a1215;margin:12px 0'><p><b>" + costWarn + "</b></p></div>");
   W("<div style='border-left:4px solid " + col + ";padding:10px 14px;background:#0f172a;margin:12px 0'><p><b>Verdetto.</b> " + head + "</p><p>" + stat + "</p><p>" + bs +
     "</p></div>");
   if(costWarn != "")
      R(g_repEdge, costWarn);
   R(g_repEdge, "VERDETTO: " + head);
   R(g_repEdge, "  " + stat);
   R(g_repEdge, "  " + bs);
   R(g_repEdge, "  Candidati (esclusi i riferimenti 'entra sempre'): robusti " + I2S(cnt[3]) + ", promettenti " + I2S(cnt[2]) + ", indizi " + I2S(cnt[1]) +
     ", scartati " + I2S(cnt[0]));
   SecEnd();
   //--- scorecard dei candidati
   SecStart("Strategie candidate: tutti i controlli",
            "I candidati sono quelli scelti dalle altre schede: i contesti singoli e le coppie migliori di ogni timeframe simulati una posizione alla " +
            "volta (R/R), le regole ORB scelte e il riferimento 'entra sempre'. Per ognuno, dal broker peggiore: <b>z netto &ge; 3</b>; " +
            "<b>stabile</b> nelle due met&agrave;; <b>oltre la stessa ora</b> (il contesto aggiunge qualcosa all'orario, z &ge; 2); " +
            "<b>direzione</b> (contro il placebo con direzione a caso, z &ge; 2); <b>costo</b> (il costo di pareggio in punti base &egrave; almeno 1,5 " +
            "volte il costo del broker); <b>una alla volta</b> (R per trade positivo con una posizione alla volta e almeno il 60% di anni " +
            "positivi); <b>test multipli</b> (z sopra la soglia di Bonferroni 5% per il numero di confronti da cui &egrave; stato scelto). " +
            "Robusto = tutti i controlli; promettente = tutti tranne i test multipli; indizio = z &ge; 2, positivo, stabile e senza costi o " +
            "posizione alla volta negativi. Senza costi del broker (controllo <b>V</b> non eseguibile) il livello massimo &egrave; l'indizio lordo. " +
            "&ndash; = controllo non applicabile.");
   if(nC == 0)
     {
      W("<p class='muted'>Nessun candidato: le schede Rischio/rendimento e ORB non hanno prodotto regole. Controlla che i dati M1 siano disponibili.</p>");
      R(g_repEdge, "  Nessun candidato strategia.");
     }
   else
     {
      int ord[];
      EdOrder(sc, nC, ord);
      THead("Livello|Fonte|Timeframe|Operazione|Contesto|Trade|Netta peggiore R|z netto|Stabile|Oltre la stessa ora (z)|Direzione (placebo z)|" +
            "Costo di pareggio / costo broker|Una alla volta|Test multipli (z / soglia)|Controlli");
      R(g_repEdge, "");
      R(g_repEdge, "[Strategie candidate: controlli. I = z netto>=3, II = stabile, III = oltre la stessa ora, IV = direzione (placebo), V = costo, VI = una alla volta, VII = test multipli]");
      int shown = 0;
      for(int j = 0; j < nC && shown < 40; j++)
        {
         int i = ord[j];
         shown++;
         int k0 = i * 8;
         int okn = 0, apn = 0;
         for(int k = 1; k < 8; k++)
           {
            if(cks[k0 + k] >= 0)
               apn++;
            if(cks[k0 + k] == 1)
               okn++;
           }
         string lvn = g_edKd[i] == 0 ? "riferimento" : EdLvName(lev[i]);
         string lvc = g_edKd[i] == 0 ? C_GREY : EdLvCol(lev[i]);
         string seq = g_edKd[i] == 3 ? "un trade al giorno" : SgnF(g_edSe[i], 3) + " R, " + F(g_edTy[i], 0) + "/anno, anni + " + I2S(g_edYp[i]) + "/" + I2S(g_edYn[i]) +
                      (g_edDk[i] == 0 ? ", perdite raggruppate" : "");
         double zc = EdZCrit(0.05, mt[i]);
         string costc = BpTxt(g_edBe[i]) + " / " + (MathIsValidNumber(g_edCb[i]) ? F(g_edCb[i], 2) + " pb" : "n/d");
         W("<tr><td style='color:" + lvc + ";font-weight:600'>" + lvn + "</td>" + TD(g_edSrc[i]) + TD(g_edTf[i]) +
           "<td style='text-align:left;white-space:normal;min-width:150px'>" + g_edOp[i] + "</td>" +
           "<td style='text-align:left;white-space:normal;min-width:260px'>" + g_edCx[i] + "</td>" + TD(I2S(g_edN[i])) + TD(SgnF(g_edE[i], 3)) +
           TDc(ZS(g_edZ[i]) + " " + EdMk(cks[k0 + 1]), PCol(g_edZ[i], 0, 5)) + TD(EdMk(cks[k0 + 2])) +
           EdCk(ZS(g_edZh[i]), cks[k0 + 3]) + EdCk(ZS(g_edZp[i]), cks[k0 + 4]) + EdCk(costc, cks[k0 + 5]) +
           EdCk(seq, cks[k0 + 6]) + EdCk(F(g_edZ[i], 1) + " / " + F(zc, 1), cks[k0 + 7]) + TD(I2S(okn) + "/" + I2S(apn)) + "</tr>");
         R(g_repEdge, "  " + lvn + " | " + g_edSrc[i] + " " + g_edTf[i] + " " + g_edOp[i] + " | " + EdPlain(g_edCx[i]) + " | trade " + I2S(g_edN[i]) +
           ", netta peggiore " + SgnF(g_edE[i], 3) + " R, z " + ZS(g_edZ[i]) + " (I " + EdMkT(cks[k0 + 1]) + "), stabile (II) " + EdMkT(cks[k0 + 2]) +
           ", oltre la stessa ora z " + ZS(g_edZh[i]) + " (III " + EdMkT(cks[k0 + 3]) + "), placebo z " + ZS(g_edZp[i]) + " (IV " + EdMkT(cks[k0 + 4]) +
           "), costo di pareggio " + BpTxt(g_edBe[i]) + " contro costo broker " + (MathIsValidNumber(g_edCb[i]) ? F(g_edCb[i], 2) + " pb" : "n/d") +
           " (V " + EdMkT(cks[k0 + 5]) + "), una alla volta " + EdPlain(seq) + " (VI " + EdMkT(cks[k0 + 6]) + "), soglia Bonferroni z " + F(zc, 1) +
           " su " + F(mt[i], 0) + " confronti (VII " + EdMkT(cks[k0 + 7]) + ")" + (g_edRl[i] > 0 ? ", regola " + I2S(g_edRl[i]) : ""));
        }
      TEnd();
      if(nC > shown)
         W("<p class='muted'>Altri " + I2S(nC - shown) + " candidati con punteggio pi&ugrave; basso non mostrati.</p>");
     }
   SecEnd();
   EdOrbTop(orbT);
   //--- cosa sopravvive ai test multipli, per area
   SecStart("Cosa sopravvive ai test multipli, area per area",
            "Per ogni area di analisi (i bias del calendario e degli impulsi sono nella sezione dedicata): quanti confronti, quanti superano z 3 (e quanti se ne aspettano per solo caso), quanti sopravvivono al " +
            "controllo FDR (Benjamini-Hochberg 5%) e la soglia di z che serve per un test di Bonferroni 5% su quel numero di confronti. Tra i " +
            "sopravvissuti, i pi&ugrave; forti. I confronti dentro un'area sono correlati (stessi giorni, stessi trade con obiettivi diversi): il " +
            "numero di falsi positivi attesi &egrave; un ordine di grandezza.");
   THead("Area|Confronti|Oltre z 3 (attesi)|Sopravvivono FDR|Soglia Bonferroni (z)|Risultato pi&ugrave; forte");
   R(g_repEdge, "");
   R(g_repEdge, "[Aree: confronti, oltre z 3 (attesi per caso), sopravvissuti al controllo FDR, soglia di Bonferroni, risultato piu' forte]");
   for(int m = 0; m < HI_NMOD; m++)
     {
      if(HI_NAME[m] == "" || g_hiCnt[m] <= 0)
         continue;
      int bi = -1;
      for(int i = 0; i < g_hiN; i++)
         if(g_hiM[i] == m && (bi < 0 || MathAbs(g_hiZ[i]) > MathAbs(g_hiZ[bi])))
            bi = i;
      string best = bi >= 0 ? "z " + ZS(g_hiZ[bi]) + " | " + g_hiT[bi] : "nessun risultato oltre z 2";
      W("<tr><td style='text-align:left;white-space:normal'>" + HI_NAME[m] + "</td>" + TD(I2S(g_hiCnt[m])) +
        TDc(I2S(g_edN3[m]) + " (" + F(0.0027 * g_hiCnt[m], 1) + ")", g_edN3[m] > 3 * 0.0027 * g_hiCnt[m] + 2 ? "rgba(59,130,246,0.35)" : "") +
        TDc(I2S(g_edNfdr[m]), g_edNfdr[m] > 0 ? "rgba(52,211,153,0.35)" : "") + TD(F(g_edZb[m], 2)) +
        "<td style='text-align:left;white-space:normal'>" + best + "</td></tr>");
      R(g_repEdge, "  " + EdPlain(HI_NAME[m]) + ": " + I2S(g_hiCnt[m]) + " confronti, oltre z 3: " + I2S(g_edN3[m]) + " (attesi " + F(0.0027 * g_hiCnt[m], 1) +
        "), sopravvissuti FDR " + I2S(g_edNfdr[m]) + ", soglia di Bonferroni z " + F(g_edZb[m], 2) + "; piu' forte: " + EdPlain(best));
     }
   TEnd();
   bool anySurv = false;
   for(int m = 0; m < HI_NMOD; m++)
      if(g_edNfdr[m] > 0 && HI_NAME[m] != "" && m != ED_MB && m != ED_MT)
         anySurv = true;
   if(anySurv)
     {
      W("<h3>Risultati che sopravvivono al controllo FDR (fino a 5 per area)</h3>");
      THead("z|Risultato");
      R(g_repEdge, "");
      R(g_repEdge, "[Risultati che sopravvivono al controllo FDR, fino a 5 per area]");
      for(int m = 0; m < HI_NMOD; m++)
        {
         if(g_edNfdr[m] <= 0 || HI_NAME[m] == "" || m == ED_MB || m == ED_MT)
            continue;
         int idx[];
         double zz[];
         int k = 0;
         ArrayResize(idx, g_hiN);
         ArrayResize(zz, g_hiN);
         for(int i = 0; i < g_hiN; i++)
            if(g_hiM[i] == m && g_edFdr[i])
              {
               idx[k] = i;
               zz[k] = MathAbs(g_hiZ[i]);
               k++;
              }
         int ord[];
         EdOrder(zz, k, ord);
         Grp(HI_NAME[m] + " (" + I2S(k) + " sopravvissuti)", 2);
         R(g_repEdge, "  " + EdPlain(HI_NAME[m]) + " (" + I2S(k) + " sopravvissuti):");
         for(int j = 0; j < k && j < 5; j++)
           {
            int i = idx[ord[j]];
            W("<tr>" + TDc(ZS(g_hiZ[i]), PCol(g_hiZ[i], 0, 6)) + "<td style='text-align:left;white-space:normal'>" + g_hiT[i] + "</td></tr>");
            R(g_repEdge, "    z " + ZS(g_hiZ[i]) + " | " + EdPlain(g_hiT[i]));
           }
        }
      TEnd();
     }
   else
     {
      W("<p class='muted'>Nessun risultato delle altre aree (sessioni, livelli, direzione, R/R, ORB, persistenza, alto-basso) sopravvive al controllo FDR.</p>");
      R(g_repEdge, "  Nessun risultato delle altre aree (sessioni, livelli, direzione, R/R, ORB, persistenza, alto-basso) sopravvive al controllo FDR.");
     }
   SecEnd();
   //--- bias del momento, profilo e bias robusti
   EdNow();
   EdProfile();
   if(g_bxNT > 0)
     {
      SecStart("Bias del calendario e degli impulsi: i robusti",
               "I bias (ora, giorno, mese, trimestre, semestre, ora x giorno, giorno del massimo e minimo della settimana, ora dell'impulso pi&ugrave; forte e " +
               "cosa lo precede) che superano il controllo FDR e sono stabili nelle due met&agrave; dello storico, per tipo. La <b>direzione</b> &egrave; " +
               "quella che pu&ograve; diventare un edge; la <b>volatilit&agrave;</b> dice solo quando il prezzo si muove. Tutti i dati sono nella scheda " +
               "Bias e impulsi.");
      R(g_repEdge, "");
      R(g_repEdge, "[Bias robusti per tipo (FDR 5% e stabili nelle due meta')]");
      EdBiasKind(0, 12);
      EdBiasKind(3, 8);
      EdBiasKind(2, 6);
      EdBiasKind(1, 5);
      SecEnd();
     }
   //--- numeri di base
   if(g_bxDig != "")
     {
      SecStart("Numeri di base per cercare da soli", "Spostamento tipico, direzione e persistenza per timeframe. Per i bias di ora, giorno, mese, " +
               "trimestre e semestre: scheda Bias e impulsi; per il rischio/rendimento di ogni contesto: schede R/R.");
      THead("Timeframe|Periodi|Spostamento mediano %|&asymp; prezzo|% rialzisti|% Trend|% Mean rev.|Restituito medio %|Periodo dopo nella stessa direzione");
      W(g_bxDig);
      TEnd();
      SecEnd();
      R(g_repEdge, "");
      R(g_repEdge, "[Numeri di base per timeframe]");
      R(g_repEdge, g_bxDigTx);
     }
   //--- come procedere
   SecStart("Cosa fare con questi risultati",
            "<ol><li>Parti dalle strategie <b>promettenti</b> e <b>robuste</b>, non dai singoli z pi&ugrave; alti: lo z pi&ugrave; alto di migliaia di prove &egrave; quasi sempre fortuna.</li>" +
            "<li>Verifica fuori campione: esporta le regole (schede Strategie e ORB) e provale con MPRuleTester sui tick reali del broker, su un periodo " +
            "successivo a quello dei dati analizzati. Una regola vera deve restare positiva l&igrave;.</li>" +
            "<li>Guarda il costo: un vantaggio con costo di pareggio sotto il costo del broker non &egrave; operabile. Se i costi non sono stati misurati " +
            "(InpCostsOnly = true sul terminale del broker, oppure InpEdRefCostBp), i livelli qui sopra sono al lordo e vanno letti cos&igrave;.</li>" +
            "<li>Un bias del calendario (ora, giorno, mese) &egrave; un'ipotesi, non una regola: traducilo in una regola semplice, con stop e obiettivo, " +
            "e sottoponilo agli stessi controlli.</li>" +
            "<li>Se nessuna area supera i controlli, il risultato utile &egrave; questo: non c'&egrave; un edge semplice in questi dati con questi costi. " +
            "Cambia strumento, timeframe o ipotesi, non la soglia.</li></ol>");
   SecEnd();
   R(g_repEdge, "");
   R(g_repEdge, "COSA FARE: partire dalle strategie promettenti e robuste; verificare fuori campione con MPRuleTester (tick reali, periodo successivo ai dati); " +
     "controllare che il costo di pareggio superi il costo del broker; trattare i bias del calendario come ipotesi da tradurre in regole e ritestare; " +
     "se nessuna area supera i controlli non c'e' un edge semplice in questi dati: cambiare strumento, timeframe o ipotesi, non la soglia.");
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
   //--- nei primi anni di alcuni storici mancano ore della giornata: segnalati e, solo se chiesto dal parametro, esclusi
   g_covInfo = "";
   datetime cov = CoverageStart(h1);
   if(InpSkipIncomplete && cov > 0)
     {
      TrimFrom(m1, cov);
      TrimFrom(m5, cov);
      TrimFrom(m15, cov);
      TrimFrom(h1, cov);
      TrimFrom(h4, cov);
      TrimFrom(d1, cov);
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
   g_covInfo = CoverageText(InpSkipIncomplete);
   if(g_covInfo != "")
      PrintFormat("[MarketProfiler] %s: %s", sym, g_covInfo);
   ResolveNewsCur(sym);
   g_hiN = 0;
   ArrayInitialize(g_hiCnt, 0);
   g_hiA = "";
   g_hiB = "";
   EdgeReset();
   Comment("MarketProfiler ", sym, ": costi dei broker ...");
   CostSetup(sym);
   for(int p = 1; p < NPRF; p++)
     {
      g_buf = true;
      g_bufS = "";
      CostHtml(p);
      g_buf = false;
      g_rrHtml[p] = g_bufS;
      g_bufS = "";
     }
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
   W("<button data-tab='edge'>Sintesi edge</button><button data-tab='overview'>Panoramica</button><button data-tab='sum'>Riepilogo</button>");
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
   R(g_repHead, RollTxt());
   for(int k = 0; k < NTF; k++)
      W("<button data-tab='" + TF_KEY[k] + "'>" + TF_LABEL[k] + "</button>");
   W("<button data-tab='sess'>Sessioni</button><button data-tab='orb'>ORB</button><button data-tab='lev'>Livelli</button><button data-tab='dir'>Direzione</button>" +
     "<button data-tab='pers'>Persistenza</button><button data-tab='mtf'>Alto &rarr; basso</button><button data-tab='bias'>Bias e impulsi</button>" +
     "<button data-tab='rr'>R/R lordo</button><button data-tab='rrb1'>R/R " + g_cp[1].name + "</button><button data-tab='rrb2'>R/R " +
     g_cp[2].name + "</button><button data-tab='combo'>Coppie di contesti</button><button data-tab='seq'>Strategie</button>" +
     "<button data-tab='swing'>Swing</button><button data-tab='break'>Rotture</button><button data-tab='imp'>Impulsi</button>" +
     "<button data-tab='news'>Notizie</button><button data-tab='gap'>Gap</button>");
   W("<button data-tab='volume'>Volume</button></nav>");
   W("<nav class='tx'><span>Testi da copiare:</span><button data-tab='report'>Rapporto completo</button><button data-tab='txedge'>Sintesi edge</button><button data-tab='txsum'>Riepilogo</button>" +
     "<button data-tab='txtf'>Timeframe</button><button data-tab='txev'>Eventi e sessioni</button><button data-tab='txorb'>ORB</button><button data-tab='txlv'>Livelli</button>" +
     "<button data-tab='txdir'>Direzione</button><button data-tab='txpers'>Persistenza</button><button data-tab='txmtf'>Alto &rarr; basso</button><button data-tab='txbias'>Bias e impulsi</button><button data-tab='txrr'>R/R lordo</button><button data-tab='txb1'>R/R " + g_cp[1].name +
     "</button><button data-tab='txb2'>R/R " + g_cp[2].name + "</button><button data-tab='txcb'>Coppie</button><button data-tab='txsq'>Strategie e regole</button>" +
     "<button data-tab='txvol'>Volume</button></nav>" +
     "<nav class='tx'><span>Tutti i risultati:</span><button data-tab='txhia'>Riepilogo (tutti gli z oltre 2)</button>" +
     "<button data-tab='txrr'>R/R lordo: tutti i contesti</button><button data-tab='txb1'>R/R " + g_cp[1].name + ": tutti i contesti</button>" +
     "<button data-tab='txb2'>R/R " + g_cp[2].name + ": tutti i contesti</button><button data-tab='txorba'>ORB: tutte le combinazioni</button>" +
     "<button data-tab='txcba'>Coppie: tutte</button><button data-tab='txmtfa'>Alto &rarr; basso: tutte le coppie di stati</button></nav></header><main>");

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
     {
      DeadHours(m1, 60);
      SessionTab(m1, 60);
     }
   else
     {
      DeadHours(m5, 300);
      SessionTab(m5, 300);
     }
   W("</div>");
   Comment("MarketProfiler ", sym, ": ORB a tutti gli orari ...");
   W("<div class='tab' id='tab-orb' hidden>");
   if(m1.n > 5000)
      OrbTab(m1, 60, clean);
   else
      OrbTab(m5, 300, clean);
   W("</div>");
   PrintFormat("[MarketProfiler] %s: ORB fatto", sym);
   Comment("MarketProfiler ", sym, ": livelli chiave e direzione ...");
   g_repLv = "";
   g_repDir = "";
   if(m1.n > 5000)
      PerAll(m1);
   else
      PerAll(m5);
   W("<div class='tab' id='tab-lev' hidden>");
   if(m1.n > 5000)
      LevelTab(m1, 60);
   else
      LevelTab(m5, 300);
   W("</div><div class='tab' id='tab-dir' hidden>");
   if(m1.n > 5000)
      DirTab(m1);
   else
      DirTab(m5);
   W("</div>");
   Comment("MarketProfiler ", sym, ": persistenza ...");
   W("<div class='tab' id='tab-pers' hidden>");
   if(m1.n > 5000)
      PersTab(m1, 60);
   else
      PersTab(m5, 300);
   W("</div>");
   PrintFormat("[MarketProfiler] %s: persistenza fatta", sym);
   Comment("MarketProfiler ", sym, ": timeframe alto -> basso ...");
   W("<div class='tab' id='tab-mtf' hidden>");
   if(m1.n > 5000)
      MtfTab(m1, 60);
   else
      MtfTab(m5, 300);
   W("</div>");
   Comment("MarketProfiler ", sym, ": bias e impulsi ...");
   W("<div class='tab' id='tab-bias' hidden>");
   BiasTab(h1, d1);
   W("</div>");
   Comment("MarketProfiler ", sym, ": rischio/rendimento ...");
   W("<div class='tab' id='tab-rr' hidden>");
   if(m1.n > 5000)
      RRTab(m1, 60, sym, clean);
   else
      RRTab(m5, 300, sym, clean);
   W("</div>");
   for(int p = 1; p < NPRF; p++)
     {
      W("<div class='tab' id='tab-rrb" + I2S(p) + "' hidden>");
      W(g_rrHtml[p]);
      W("</div>");
      g_rrHtml[p] = "";
     }
   W("<div class='tab' id='tab-combo' hidden>");
   W(g_cbHtml);
   W("</div><div class='tab' id='tab-seq' hidden>");
   W(g_sqHtml);
   W("</div>");
   g_cbHtml = "";
   g_sqHtml = "";
   PerFree();
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
   W("</div><div class='tab' id='tab-sum' hidden>");
   HiTab();
   W("</div><div class='tab' id='tab-edge' hidden>");
   EdgeTab(sym);
   W("</div><div class='tab' id='tab-report' hidden>");
   SecStart("Rapporto completo", "Tutti i risultati in forma di testo, in ordine: indice e legenda, la parte principale (riepilogo, " +
            "timeframe, eventi e sessioni, ORB, livelli, direzione, rischio/rendimento lordo e netto, strategie e regole, coppie, volume, " +
            "persistenza, timeframe alto -> basso) e le appendici con tutti i risultati per esteso (tutti gli z oltre 2, tutti i contesti " +
            "lordi e netti, tutte le combinazioni ORB, tutte le coppie, tutte le coppie di stati). Premi 'Copia tutto'. Il testo &egrave; molto lungo: per l'analisi in chat incolla la parte principale (fino " +
            "alle appendici) e le appendici solo quando serve cercare un risultato; ogni parte &egrave; anche nelle schede 'Testi da " +
            "copiare' e 'Tutti i risultati'.");
   W("<button class='cp' onclick='cp(this)'>Copia tutto</button><textarea id='rep' readonly>");
   W(g_repHead);
   W(RepIndex());
   W("\n=== 0. SINTESI EDGE: verdetto, candidati, test multipli, bias del momento, profilo e bias robusti ===\n");
   W(g_repEdge);
   W("\n=== 1. RIEPILOGO: i risultati piu' lontani dal caso di tutte le analisi (tutti nell'appendice A) ===\n");
   W(g_repHi);
   W("\n=== 2. PERIODO IN CORSO ===\n");
   W(g_repCur);
   W("\n=== 3. TIMEFRAME: dal minuto all'anno ===\n");
   W(g_rep);
   W("\n=== 4. EVENTI E SESSIONI: swing, rotture, impulsi, notizie, gap, ore buche e rollover, orari chiave e sessioni ===\n");
   W(g_repEv);
   W("\n=== 5. ORB: rottura del range iniziale a tutti gli orari, conferme ed eventi (tutte le combinazioni nell'appendice D) ===\n");
   W(g_repOrb);
   W("\n=== 6. LIVELLI CHIAVE (massimo, minimo, chiusura del periodo precedente e apertura del periodo; dopo il tocco, dalla chiusura " +
     "della barra che tocca: prosegue di r oltre o respinto di r, r = " + F(InpLevelR * 100, 0) + "% del range mediano; livello finto = " +
     "massimo/minimo spostati di +/-25% del range mediano, stessa misura; effetto del livello = (prosegue - respinto) vero meno finto; " +
     "z = deviazioni standard dal caso, entro +/-2 compatibile con il caso) ===\n");
   W(g_repLv);
   W("\n=== 7. DIREZIONE: movimenti forti, cosa li precede, quando si formano, cosa succede dopo ===\n");
   W(g_repDir);
   W("\n=== 8. RISCHIO/RENDIMENTO LORDO: buy e sell a ogni apertura di candela, obiettivi 1:1 - 1:5 (tutti i contesti nell'appendice B) ===\n");
   W(g_rrTxS[0]);
   W(g_rrTxT[0]);
   for(int p = 1; p < NPRF; p++)
     {
      W("\n=== 9." + I2S(p) + " RISCHIO/RENDIMENTO NETTO " + g_cp[p].name + ": costi, riepilogo, contesti migliori e peggiori (tutti " +
        "nell'appendice C." + I2S(p) + ") ===\n");
      W(g_rbHead[p]);
      W(g_rrTxS[p]);
      W(g_rrTxT[p]);
     }
   W("\n=== 10. STRATEGIE: una posizione alla volta, serie di perdite e drawdown; regole per lo Strategy Tester ===\n");
   W(g_sqTx);
   W("\n");
   W(g_ruTx);
   W("\n=== 11. COPPIE DI CONTESTI: le piu' solide e le piu' negative (tutte nell'appendice E) ===\n");
   W(g_cbTx);
   W("\n=== 12. VOLUME ===\n");
   W(g_repVol);
   W("\n=== 13. PERSISTENZA: dove il prezzo continua e dove torna indietro (per timeframe e per ora del giorno) ===\n");
   W(g_repPers);
   W("\n=== 14. DAL TIMEFRAME ALTO AL BASSO: stato della candela H4, D1 e settimanale e cosa fanno al suo interno i timeframe " +
     "inferiori (tutte le coppie di stati nell'appendice F) ===\n");
   W(g_repMtf);
   W("\n=== 15. BIAS E IMPULSI: ora, giorno, mese, trimestre, semestre; massimo e minimo della settimana; impulso piu' forte, massimo e minimo del giorno e cosa li precede ===\n");
   W(g_repBias);
   W("\n\n############################## APPENDICI: TUTTI I RISULTATI ##############################\n");
   W("\n=== APPENDICE A. RIEPILOGO: tutti i risultati oltre |z| 2 di ogni analisi, ordinati per |z| ===\n");
   WT(g_txHiAll);
   W("\n=== APPENDICE B. RISCHIO/RENDIMENTO LORDO: tutti i contesti ===\n");
   W(g_rrTxA[0]);
   for(int p = 1; p < NPRF; p++)
     {
      W("\n=== APPENDICE C." + I2S(p) + " RISCHIO/RENDIMENTO NETTO " + g_cp[p].name + ": tutti i contesti ===\n");
      W(g_rrTxA[p]);
     }
   W("\n=== APPENDICE D. ORB: tutte le combinazioni (orario, range, finestra; una riga per candela di conferma) ===\n");
   W(OrbAllHead());
   WT(g_txOrbAll);
   W("\n=== APPENDICE E. COPPIE DI CONTESTI: tutte quelle con almeno 30 casi ===\n");
   WT(g_txCbAll);
   W("\n=== APPENDICE F. DAL TIMEFRAME ALTO AL BASSO: tutte le coppie di stati con almeno 30 candele ===\n");
   WT(g_txMtfAll);
   W("</textarea>");
   SecEnd();
   W("</div>");
   //--- testi separati da copiare
   string lvHead = "LIVELLI CHIAVE - " + sym + " (massimo, minimo, chiusura del periodo precedente e apertura del periodo; r = " +
                   F(InpLevelR * 100, 0) + "% del range mediano; livello finto = livello spostato di +/-25% del range mediano; " +
                   "z = deviazioni standard dal caso)\n";
   TxTab("txsum", "Testo: riepilogo", "I risultati lontani dal caso di tutte le schede, con il numero di confronti.", g_repHead + "\n" + g_repHi);
   TxTab("txtf", "Testo: timeframe e periodo in corso", "Le schede dei timeframe (da 1 minuto a 1 anno) e lo stato del periodo in corso.",
         g_repHead + "\n=== PERIODO IN CORSO ===\n" + g_repCur + g_rep);
   TxTab("txev", "Testo: eventi e sessioni", "Swing, rotture, impulsi, notizie, gap, ore buche e rollover, orari chiave e sessioni.", "EVENTI E SESSIONI - " + sym + "\n" + g_repEv);
   TxTab("txorb", "Testo: ORB a tutti gli orari", "Rottura del range iniziale a ogni orario, durata e finestra: anomalie, dettagli, " +
         "cosa capita a ogni orario (tutte le combinazioni nel CSV).", "ORB - " + sym + "\n" + g_repOrb);
   TxTab("txlv", "Testo: livelli", "Livelli chiave, vita del livello e lettura sui timeframe inferiori.", lvHead + g_repLv);
   TxTab("txdir", "Testo: direzione", "Movimenti forti, cosa li precede, quando si formano, cosa succede dopo.", "DIREZIONE - " + sym + "\n" + g_repDir);
   TxTab("txrr", "Testo: rischio/rendimento lordo", "Riepilogo di ogni timeframe, contesti migliori e peggiori e tutti i contesti, senza costi.",
         "RISCHIO/RENDIMENTO LORDO - " + sym + " - buy e sell a ogni apertura di candela, obiettivi 1:1 - 1:5\n" + g_rrTxS[0] + g_rrTxT[0] + g_rrTxA[0]);
   for(int p = 1; p < NPRF; p++)
      TxTab("txb" + I2S(p), "Testo: rischio/rendimento netto " + g_cp[p].name, "Costi di " + g_cp[p].name + ", spread per ora, riepilogo " +
            "netto di ogni timeframe, contesti migliori e peggiori e tutti i contesti.", "RISCHIO/RENDIMENTO NETTO " + g_cp[p].name + " - " + sym +
            "\n" + g_rbHead[p] + g_rrTxS[p] + g_rrTxT[p] + g_rrTxA[p]);
   TxTab("txcb", "Testo: coppie di contesti", "Le coppie pi&ugrave; solide e pi&ugrave; negative di ogni timeframe (tutte nel file CSV).",
         "COPPIE DI CONTESTI - " + sym + "\n" + g_cbTx);
   TxTab("txsq", "Testo: strategie e regole", "Simulazione una posizione alla volta dei contesti migliori (serie di perdite, drawdown) e " +
         "regole esportate per lo Strategy Tester.", "STRATEGIE - " + sym + " - una posizione alla volta\n" + g_sqTx + "\n" + g_ruTx);
   TxTab("txedge", "Testo: sintesi edge", "Verdetto, candidati con tutti i controlli, test multipli, bias del momento, profilo di ore e giorni e bias robusti.", "SINTESI EDGE - " + sym + "\n" + g_repEdge);
   TxTab("txbias", "Testo: bias e impulsi", "Bias di ora, giorno, mese, trimestre e semestre; ora x giorno; massimo e minimo della settimana; impulso piu' forte del giorno e cosa lo precede.", "BIAS E IMPULSI - " + sym + "\n" + g_repBias);
   TxTab("txvol", "Testo: volume", "Volume per ora, giorno e periodo.", "VOLUME - " + sym + "\n" + g_repVol);
   TxTab("txpers", "Testo: persistenza", "Rapporto di varianza per timeframe e continuazione del movimento a ogni mezz'ora.",
         "PERSISTENZA - " + sym + "\n" + g_repPers);
   TxTab("txmtf", "Testo: timeframe alto -> basso", "Stato della candela H4, D1 e settimanale, cosa fanno al suo interno i timeframe " +
         "inferiori, stato attuale e coppie di stati pi&ugrave; lontane dalle altre candele.", "TIMEFRAME ALTO -> BASSO - " + sym + "\n" + g_repMtf);
   TxTabT("txhia", "Tutti i risultati: riepilogo", "Tutti i risultati oltre |z| 2 di ogni analisi, senza limiti, ordinati per |z| (nella scheda " +
          "Riepilogo solo i primi di ogni sezione).", "RIEPILOGO - TUTTI I RISULTATI OLTRE |z| 2 - " + sym + "\n" + RepLegend(), g_txHiAll);
   TxTabT("txorba", "Tutti i risultati: ORB", "Tutte le combinazioni ORB (orario, range, finestra) con una riga per ogni candela di conferma: " +
          "operazioni, costi, continuazione ed eventi. Orari equivalenti e orari a mercato chiuso sono solo nel CSV.",
          "ORB - TUTTE LE COMBINAZIONI - " + sym + "\n" + OrbAllHead(), g_txOrbAll);
   TxTabT("txcba", "Tutti i risultati: coppie di contesti", "Tutte le coppie di contesti con almeno 30 casi, ogni timeframe, tutte le " +
          "operazioni (lorde e nette del broker peggiore).", "COPPIE DI CONTESTI - TUTTE - " + sym + "\n", g_txCbAll);
   TxTabT("txmtfa", "Tutti i risultati: timeframe alto -> basso", "Tutte le coppie di stati della candela H4, D1 e settimanale con almeno " +
          "30 candele, con tutte le misure.", "TIMEFRAME ALTO -> BASSO - TUTTE LE COPPIE DI STATI - " + sym + "\n", g_txMtfAll);
   W("</main><script>" + Js() + "</script></body></html>");
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
   if(InpCostsOnly)  // solo i costi del broker di questo terminale: profilo salvato nella cartella comune per gli altri terminali
     {
      for(int i = 0; i < n; i++)
        {
         string s = syms[i];
         StringTrimLeft(s);
         StringTrimRight(s);
         if(s == "" || !SymbolSelect(s, true))
            continue;
         g_digits = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
         g_last = SymbolInfoDouble(s, SYMBOL_BID);
         CostSetup(s);
        }
      Comment("");
      Print("[MarketProfiler] misura dei costi finita: i profili misurati sono in Common\\Files (MarketProfiler_costi_*.txt)");
      return;
     }
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
