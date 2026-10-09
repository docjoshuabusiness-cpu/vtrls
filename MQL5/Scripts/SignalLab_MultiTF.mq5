//+------------------------------------------------------------------+
//|                                          SignalLab_MultiTF.mq5   |
//|  Studio statistico del Synthetic Delta / Expansion dell'EA su    |
//|  TUTTI i timeframe MT5 contemporaneamente, misurato in PUNTI.    |
//|                                                                  |
//|  Cosa fa                                                          |
//|   1. Calcola i segnali a candela chiusa su ogni timeframe con la |
//|      stessa logica dell'EA (SD_Core.mqh).                         |
//|   2. Entra all'open della prima barra M1 dopo la chiusura (+     |
//|      spread reale). M1 e' l'orologio comune: tutti i TF sono     |
//|      misurati sugli stessi istanti e con la stessa risoluzione.  |
//|   3. Per ogni segnale e per ogni orizzonte (minuti) registra     |
//|      MFE, MAE e rendimento a fine orizzonte, in punti.           |
//|   4. Confronta con una BASE abbinata: entrate in direzione       |
//|      casuale, stesso TF, stessa fascia oraria. Cosi' la          |
//|      stagionalita' della volatilita' non passa per edge.         |
//|   5. Tabelle: per TF x orizzonte, superamento di livelli (spunte |
//|      sui target in punti), fascia oraria, candela nel TF         |
//|      superiore, posizione nella raffica, direzione, giorno,      |
//|      classifica delle run piu' lunghe.                           |
//|   6. CLASSIFICA: ipotetica posizione una per volta, tenuta N     |
//|      minuti con target opzionale e senza stop, per TF x fascia   |
//|      oraria x tenuta x target x verso (SEGUI/INVERTI). Si        |
//|      classifica sul primo 70% del periodo e si verifica sul      |
//|      resto. Con segnali senza informazione il netto medio e'     |
//|      -costo per qualunque tenuta e target.                       |
//|                                                                  |
//|  Metrica principale: NETTO MEDIO = rendimento a fine orizzonte   |
//|  nella direzione del segnale meno il costo. MFE/MAE crescono con |
//|  la volatilita': da soli non dimostrano nulla.                   |
//|  Errore standard raggruppato per giorno (cluster) perche' i      |
//|  segnali sono sovrapposti.                                       |
//|                                                                  |
//|  Esegui su un simbolo alla volta (quello del grafico).           |
//|  Output: MQL5/Files/SignalLab_MultiTF_<simbolo>_<modo>.html e    |
//|          SignalLab_MultiTF_digest_<simbolo>_<modo>.txt           |
//+------------------------------------------------------------------+
#property copyright "SignalLab"
#property version   "1.00"
#property script_show_inputs
#property strict

#include <SD_Core.mqh>

//--- ================================================================
enum ENUM_SD_MODE
  {
   SDM_DELTA = 0,  // Solo Synthetic Delta
   SDM_EXP   = 1,  // Solo Expansion Candle
   SDM_AND   = 2,  // Entrambi concordi sulla stessa barra (AND)
   SDM_OR    = 3   // Basta uno dei due (OR)
  };

enum ENUM_NOISE_SORT
  {
   NS_TOTAL = 0,  // Profitto totale in punti sull'intero storico
   NS_MEAN  = 1,  // Netto medio per posizione
   NS_T     = 2   // t-statistic
  };

input group "=== SEGNALE (stessi parametri dell'EA) ==="
input ENUM_SD_MODE InpMode          = SDM_DELTA;
input int      InpEmaPeriod         = 13;     // EmaPeriod
input int      InpVolAvgPeriod      = 20;     // VolAvgPeriod
input double   InpThreshold         = 0.15;   // SignalThreshold
input int      InpAtrPeriod         = 14;     // ATR_Period (solo validita' dato)
input int      InpExpAtrPeriod      = 14;     // Inp_ExpATRPeriod
input double   InpExpThreshold      = 1.8;    // Inp_ExpThreshold (TR/ATR)
input int      InpExpConfirmOffset  = 0;      // Inp_ExpConfirmOffset
input int      InpRunGapBars        = 0;      // Inp_RunGapBars (0 = raffica chiusa solo da segnale opposto)

input group "=== DATI ==="
input datetime InpFrom              = D'2015.01.01 00:00';
input datetime InpTo                = D'2030.01.01 00:00';
input string   InpTFs               = "ALL";  // ALL oppure lista, es. M1,M5,M15,H1
input int      InpTimeOffsetH       = 0;      // ore da sommare al server time per fasce e giorni
input int      InpMaxGapMin         = 90;     // scarta finestre che contengono un buco di dati > N minuti (weekend, festivi)
input int      InpMaxEntryGapMin    = 5;      // scarta segnali se l'ingresso e' oltre N minuti dopo la chiusura (pausa di sessione)

input group "=== MISURA (tutto in PUNTI) ==="
input string   InpHorizons          = "1,2,3,5,10,15,30,45,60,120,240,1440"; // orizzonti = tempo di tenuta in minuti, uguali per tutti i TF
input int      InpRefHorizon        = 60;     // orizzonte di riferimento per le tabelle di dettaglio
input string   InpLevels            = "50,100,150,200,250,300,350,400,450,500,550,600"; // livelli/target in punti (le spunte e i take profit della classifica)
input double   InpCostPoints        = 0;      // 0 = spread reale della barra M1 d'ingresso
input double   InpExtraCostPts      = 0;      // commissione/slippage extra in punti

input group "=== TABELLE ==="
input int      InpBucketMin         = 15;     // fasce orarie: 1,2,3,4,5,6,10,12,15,20,30,60
input ENUM_TIMEFRAMES InpParentTF   = PERIOD_H1; // TF "contenitore" per la posizione della candela (es. 5a M1 dentro l'H1)
input int      InpTopRuns           = 100;    // quante run piu' lunghe elencare
input int      InpMinPerBucket      = 30;     // sotto questa soglia la riga e' grigia (rumore)
input bool     InpDigestTOD         = false;  // include le fasce orarie nel digest (lungo)

input group "=== CLASSIFICA (ipotetica posizione, in-sample / out-of-sample) ==="
input int      InpSplitPct          = 70;     // % iniziale del periodo usata per CLASSIFICARE; il resto serve solo a verificare
input int      InpRankMinN          = 100;    // posizioni minime in-sample perche' una combinazione entri in classifica
input int      InpRankTop           = 30;     // quante righe mostrare nella classifica
input ENUM_NOISE_SORT InpNoiseSort  = NS_TOTAL; // ordinamento della tabella B (con rumore, senza protezione: intero storico)
input ENUM_TIMEFRAMES InpEventTF    = PERIOD_M5; // TF dell'elenco segnali con le spunte
input int      InpEventRows         = 120;    // quanti segnali elencare (campione uniforme su tutto il periodo)

//--- ================================================================
#define ACCN 8       // campi per accumulatore: n, mfe, mae, retNet, retNet^2, costo, win, lose
#define BCAP 8       // posizione raffica: 1..7, 8+
#define RKN  5       // campi classifica: n, somma pnl, somma pnl^2, hit, somma MAE

const ENUM_TIMEFRAMES g_allTF[21] =
  {PERIOD_M1, PERIOD_M2, PERIOD_M3, PERIOD_M4, PERIOD_M5, PERIOD_M6, PERIOD_M10, PERIOD_M12,
   PERIOD_M15, PERIOD_M20, PERIOD_M30, PERIOD_H1, PERIOD_H2, PERIOD_H3, PERIOD_H4, PERIOD_H6,
   PERIOD_H8, PERIOD_H12, PERIOD_D1, PERIOD_W1, PERIOD_MN1};
const string g_allName[21] =
  {"M1","M2","M3","M4","M5","M6","M10","M12","M15","M20","M30","H1","H2","H3","H4","H6",
   "H8","H12","D1","W1","MN1"};

//--- parametri derivati
SDParams g_par;
int      g_nT = 0;
ENUM_TIMEFRAMES g_tf[];
string   g_tfName[];
long     g_tfSec[];
bool     g_slotOK[];
int      g_slotCnt[];
int      g_maxSlots = 1;
int      g_nH = 0;
int      g_hor[];
int      g_refH = 0;
int      g_nL = 0;
double   g_lev[];
int      g_bMin = 15;
int      g_nB = 96;
long     g_parentSec = 3600;
long     g_off = 0;
double   g_pt = 0.0;
double   g_zB = 3.0;
double   g_minN = 100.0;                // minimo posizioni (>= 1)
datetime g_tStart = 0;                  // primo istante M1 effettivamente disponibile nel periodo
bool     g_histWarn = false;            // lo storico M1 inizia molto dopo InpFrom
int      g_rbMin = 15, g_nRB = 96;   // fasce della classifica
int      g_splitDay = 0;             // primo giorno out-of-sample
int      g_evT = -1;                 // indice TF dell'elenco segnali

//--- orologio M1
MqlRates g_r1[];
int      g_n1 = 0;
datetime g_m1Time[];
double   g_m1Open[], g_m1High[], g_m1Low[], g_m1Close[];
int      g_m1Spr[];
ushort   g_m1Bkt[];
int      g_m1Day[];
uchar    g_m1Dow[];
int      g_nextBrk[];
int      g_nDays = 1;
long     g_day0 = 0;
double   g_medRange = 0.0, g_medSpr = 0.0, g_zeroSprPct = 0.0;

//--- finestre forward per l'orizzonte corrente
double   g_fHi[], g_fLo[], g_fCl[];
uchar    g_ok[];
int      g_dqH[], g_dqL[];

//--- barre di ogni TF con ingresso valido (appese in sequenza)
int      g_tfOff[], g_tfCnt[], g_tfBars[], g_tfEv[], g_tfRejGap[], g_tfRejM1[];
int      g_ent[];
char     g_dir[];
uchar    g_bur[];
ushort   g_slot[];
int      g_used = 0;

//--- accumulatori
double   g_accTH[];       // [t][h][ACCN]
int      g_exFav[], g_exAdv[];   // [t][h][nL+1] istogramma: n. di livelli <= valore
int      g_evBN[];        // [t][h][b] eventi per fascia
int      g_bsN[];         // [t][h][b] barre base per fascia
double   g_bsSum[];       // [t][h][b] somma MFE medio (buy+sell)/2
int      g_bsHist[];      // [t][h][b][nL+1]
double   g_dayS[], g_dayN[];     // [t][h][giorno] cluster del netto
double   g_accBkt[];      // [t][b][ACCN]   (orizzonte di riferimento)
double   g_accSlot[];     // [t][slot][ACCN]
double   g_accBur[];      // [t][BCAP][ACCN]
double   g_accDir[];      // [t][2][ACCN]
double   g_accDow[];      // [t][7][ACCN]

//--- classifica ipotetica posizione: [t][fascia][h][kk][dd][smp][RKN]
//    kk: 0 = uscita a solo tempo, 1..nL = target; dd: 0 = segui, 1 = inverti; smp: 0 = IS, 1 = OOS
double   g_rk[];          // una posizione per volta PER FASCIA
double   g_rg[];          // una posizione per volta per TF, tutto il giorno: [t][h][kk][dd][smp][RKN]
long     g_lockB[], g_lockG[];

//--- elenco segnali con spunte
int      g_evCap = 0, g_evCount = 0, g_evSeen = 0, g_evStride = 1;
datetime g_evTime[];
int      g_evDir[], g_evSlot[], g_evBur[], g_evJ[];
double   g_evMfe[], g_evMae[], g_evRet[];
int      g_evMin[];       // [evento][livello] minuti al raggiungimento, -1 = non raggiunto

//--- classifica run piu' lunghe
int      g_topCap = 0, g_topN = 0, g_topMinIdx = 0;
datetime g_tpTime[];
int      g_tpTF[], g_tpDir[], g_tpBur[], g_tpSlot[];
double   g_tpMfe[], g_tpMae[], g_tpRet[], g_tpCost[];

//--- output
int      g_fh = INVALID_HANDLE;
string   g_dg = "";

struct CellStat
  {
   double n, mfe, mae, ret, sd, tNaive, tCl, cost, win, lose, zSign, baseMfe;
  };

//+------------------------------------------------------------------+
//| Utilita'                                                          |
//+------------------------------------------------------------------+
string F0(const double v) { return DoubleToString(v, 0); }
string F1(const double v) { return DoubleToString(v, 1); }
string F2(const double v) { return DoubleToString(v, 2); }
string IS(const long v)   { return IntegerToString(v); }

void W(const string s) { if(g_fh != INVALID_HANDLE) FileWriteString(g_fh, s); }

string Td(const string txt, const string col = "")
  {
   if(col == "") return "<td>" + txt + "</td>";
   return "<td style='color:" + col + "'>" + txt + "</td>";
  }

string ColSign(const double v)
  {
   if(v > 0.0) return "#a3be8c";
   if(v < 0.0) return "#bf616a";
   return "#7b8794";
  }

string ColT(const double t)
  {
   double a = MathAbs(t);
   if(a >= g_zB) return (t > 0.0) ? "#a3be8c" : "#bf616a";
   if(a >= 2.0)  return "#ebcb8b";
   return "#7b8794";
  }

//--- t naive (campioni sovrapposti, nessuna correzione per test multipli): al massimo giallo
string ColTNaive(const double t)
  {
   return (MathAbs(t) >= 2.0) ? "#ebcb8b" : "#7b8794";
  }

double NormSf(const double z)
  {
   double t = 1.0 / (1.0 + 0.2316419 * MathAbs(z));
   double d = 0.3989422804 * MathExp(-z * z / 2.0);
   double p = d * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
   return (z >= 0.0) ? p : 1.0 - p;
  }

//--- soglia |z| bilaterale al 5% con correzione di Bonferroni su m test
double ZCrit(const int m)
  {
   double alpha = 0.05 / (double)MathMax(1, m);
   double lo = 0.0, hi = 10.0;
   for(int k = 0; k < 60; k++)
     {
      double mid = 0.5 * (lo + hi);
      if(2.0 * NormSf(mid) > alpha) lo = mid; else hi = mid;
     }
   return 0.5 * (lo + hi);
  }

int SnapBucket(const int req)
  {
   int valid[] = {1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60};
   int best = 60, bd = 100000;
   for(int i = 0; i < ArraySize(valid); i++)
     {
      int d = MathAbs(valid[i] - req);
      if(d < bd) { bd = d; best = valid[i]; }
     }
   return best;
  }

string SafeTag(const string src)
  {
   string out = src;
   for(int i = 0; i < StringLen(out); i++)
     {
      ushort c = StringGetCharacter(out, i);
      bool ok = ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '.' || c == '-' || c == '_');
      if(!ok) StringSetCharacter(out, i, '_');
     }
   return out;
  }

string ModeName()
  {
   switch(InpMode)
     {
      case SDM_DELTA: return "DELTA";
      case SDM_EXP:   return "EXPANSION";
      case SDM_AND:   return "AND";
      case SDM_OR:    return "OR";
     }
   return "?";
  }

string BktLabel(const int b)
  {
   int s = b * g_bMin, e = s + g_bMin;
   return StringFormat("%02d:%02d-%02d:%02d", s / 60, s % 60, e / 60, e % 60);
  }

string DowName(const int d)
  {
   string n[7] = {"Dom", "Lun", "Mar", "Mer", "Gio", "Ven", "Sab"};
   return (d >= 0 && d < 7) ? n[d] : "?";
  }

//+------------------------------------------------------------------+
//| Parsing input                                                     |
//+------------------------------------------------------------------+
void AddTF(const int idx)
  {
   for(int q = 0; q < ArraySize(g_tf); q++)
      if(g_tf[q] == g_allTF[idx]) return;
   int k = ArraySize(g_tf);
   ArrayResize(g_tf, k + 1);
   ArrayResize(g_tfName, k + 1);
   g_tf[k]     = g_allTF[idx];
   g_tfName[k] = g_allName[idx];
  }

bool ParseTFs()
  {
   string s = InpTFs;
   StringTrimLeft(s); StringTrimRight(s); StringToUpper(s);
   ArrayResize(g_tf, 0);
   ArrayResize(g_tfName, 0);
   if(s == "ALL" || s == "")
     { for(int i = 0; i < 21; i++) AddTF(i); }
   else
     {
      string parts[];
      int np = StringSplit(s, ',', parts);
      for(int q = 0; q < np; q++)
        {
         string pp = parts[q];
         StringTrimLeft(pp); StringTrimRight(pp);
         bool known = false;
         for(int i = 0; i < 21; i++)
            if(g_allName[i] == pp) { AddTF(i); known = true; break; }
         if(!known && pp != "") Print("Timeframe sconosciuto in InpTFs: '", pp, "' (ignorato).");
        }
     }
   g_nT = ArraySize(g_tf);
   return (g_nT > 0);
  }

int ParseIntList(const string src, int &out[])
  {
   string parts[];
   int np = StringSplit(src, ',', parts);
   ArrayResize(out, 0);
   for(int i = 0; i < np; i++)
     {
      string pp = parts[i];
      StringTrimLeft(pp); StringTrimRight(pp);
      int v = (int)StringToInteger(pp);
      if(v < 1) continue;
      int k = ArraySize(out);
      bool dup = false;
      for(int q = 0; q < k; q++) if(out[q] == v) { dup = true; break; }
      if(dup) continue;
      ArrayResize(out, k + 1);
      out[k] = v;
     }
   if(ArraySize(out) > 1) ArraySort(out);
   return ArraySize(out);
  }

int ParseDoubleList(const string src, double &out[])
  {
   string parts[];
   int np = StringSplit(src, ',', parts);
   ArrayResize(out, 0);
   for(int i = 0; i < np; i++)
     {
      string pp = parts[i];
      StringTrimLeft(pp); StringTrimRight(pp);
      double v = StringToDouble(pp);
      if(v <= 0.0) continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k] = v;
     }
   if(ArraySize(out) > 1) ArraySort(out);
   return ArraySize(out);
  }

bool SetupInputs()
  {
   if(InpFrom >= InpTo) { Print("InpFrom deve precedere InpTo."); return false; }
   g_minN = MathMax(1.0, (double)InpRankMinN);
   if(!ParseTFs()) { Print("Nessun timeframe valido in InpTFs"); return false; }
   g_nH = ParseIntList(InpHorizons, g_hor);
   if(g_nH < 1) { Print("Nessun orizzonte valido in InpHorizons"); return false; }
   g_refH = 0;
   int bd = 1000000000;
   for(int i = 0; i < g_nH; i++)
     {
      int d = MathAbs(g_hor[i] - InpRefHorizon);
      if(d < bd) { bd = d; g_refH = i; }
     }
   if(g_hor[g_refH] != InpRefHorizon)
      Print("InpRefHorizon ", InpRefHorizon, " non e' fra gli orizzonti: uso ", g_hor[g_refH], " min.");
   g_nL = ParseDoubleList(InpLevels, g_lev);
   if(g_nL < 1)
     {
      Print("InpLevels non valido: uso 100, 500, 1000.");
      ArrayResize(g_lev, 3);
      g_lev[0] = 100; g_lev[1] = 500; g_lev[2] = 1000;
      g_nL = 3;
     }
   g_bMin = SnapBucket(InpBucketMin);
   g_nB   = 1440 / g_bMin;
   g_rbMin = SnapBucket(MathMax(g_bMin, 5));
   g_nRB   = 1440 / g_rbMin;
   g_evT = -1;
   for(int t = 0; t < g_nT; t++) if(g_tf[t] == InpEventTF) g_evT = t;
   if(g_evT < 0) Print("InpEventTF non e' fra i TF analizzati: elenco spunte disattivato.");
   g_parentSec = (long)PeriodSeconds(InpParentTF);
   ArrayResize(g_tfSec, g_nT);
   ArrayResize(g_slotOK, g_nT);
   ArrayResize(g_slotCnt, g_nT);
   g_maxSlots = 1;
   for(int t = 0; t < g_nT; t++)
     {
      g_tfSec[t] = (long)PeriodSeconds(g_tf[t]);
      bool ok = (g_tfSec[t] > 0 && g_tfSec[t] < g_parentSec && g_parentSec <= 86400L &&
                 (g_parentSec % g_tfSec[t]) == 0 && (g_parentSec / g_tfSec[t]) <= 1440);
      g_slotOK[t]  = ok;
      g_slotCnt[t] = ok ? (int)(g_parentSec / g_tfSec[t]) : 0;
      if(g_slotCnt[t] > g_maxSlots) g_maxSlots = g_slotCnt[t];
     }

   g_par.mode             = (int)InpMode;
   g_par.emaPeriod        = MathMax(1, InpEmaPeriod);
   g_par.volAvgPeriod     = MathMax(1, InpVolAvgPeriod);
   g_par.threshold        = InpThreshold;
   g_par.atrPeriod        = MathMax(1, InpAtrPeriod);
   g_par.expAtrPeriod     = MathMax(1, InpExpAtrPeriod);
   g_par.expThreshold     = InpExpThreshold;
   g_par.expConfirmOffset = MathMax(0, InpExpConfirmOffset);
   g_par.runGapBars       = MathMax(0, InpRunGapBars);
   return true;
  }

//+------------------------------------------------------------------+
//| Caricamento storico                                               |
//+------------------------------------------------------------------+
int LoadRates(const ENUM_TIMEFRAMES tf, const datetime from, const datetime to, MqlRates &out[])
  {
   ArraySetAsSeries(out, false);
   int got = -1;
   bool synced = false;
   for(int a = 0; a < 20; a++)
     {
      got = CopyRates(_Symbol, tf, from, to, out);
      if(got > 0 && (bool)SeriesInfoInteger(_Symbol, tf, SERIES_SYNCHRONIZED)) { synced = true; break; }
      if(IsStopped()) break;
      Sleep(250);
     }
   if(!synced) Print("Attenzione: serie ", EnumToString(tf), " non sincronizzata dopo i tentativi (barre ", got, "): lo storico potrebbe essere parziale.");
   return got;
  }

int LoadTF(const int t, MqlRates &r[])
  {
   long f = (long)InpFrom - 300L * g_tfSec[t];
   if(f < 86400L) f = 86400L;
   return LoadRates(g_tf[t], (datetime)f, InpTo, r);
  }

bool LoadM1()
  {
   datetime from = (datetime)((long)InpFrom - 300L * 60L);
   int got = LoadRates(PERIOD_M1, from, InpTo, g_r1);
   int  maxb = (int)TerminalInfoInteger(TERMINAL_MAXBARS);
   long sb   = SeriesInfoInteger(_Symbol, PERIOD_M1, SERIES_BARS_COUNT);
   Print("Storico M1: server ", sb, " barre | caricate ", got, " | MAXBARS ", maxb);
   if(sb > maxb)
      Print("!!! Il terminale espone solo ", maxb, " barre su ", sb,
            ". Opzioni > Grafici > Max barre = Illimitato, poi riavvia il terminale.");
   if(got < 1000) { Print("Storico M1 insufficiente (", got, ")."); return false; }

   g_n1 = got;
   ArrayResize(g_m1Time, g_n1);
   ArrayResize(g_m1Open, g_n1);
   ArrayResize(g_m1High, g_n1);
   ArrayResize(g_m1Low,  g_n1);
   ArrayResize(g_m1Close, g_n1);
   ArrayResize(g_m1Spr,  g_n1);
   ArrayResize(g_m1Bkt,  g_n1);
   ArrayResize(g_m1Day,  g_n1);
   ArrayResize(g_m1Dow,  g_n1);
   ArrayResize(g_nextBrk, g_n1);

   g_day0 = (((long)g_r1[0].time) + g_off) / 86400L;
   const long bsec = (long)g_bMin * 60L;
   for(int i = 0; i < g_n1; i++)
     {
      g_m1Time[i]  = g_r1[i].time;
      g_m1Open[i]  = g_r1[i].open;
      g_m1High[i]  = g_r1[i].high;
      g_m1Low[i]   = g_r1[i].low;
      g_m1Close[i] = g_r1[i].close;
      g_m1Spr[i]   = g_r1[i].spread;
      long ts = (long)g_r1[i].time + g_off;
      long dd = ts / 86400L;
      g_m1Bkt[i] = (ushort)((ts % 86400L) / bsec);
      g_m1Day[i] = (int)(dd - g_day0);
      g_m1Dow[i] = (uchar)((dd + 4L) % 7L);
     }
   g_nDays = g_m1Day[g_n1 - 1] + 1;
   if(g_nDays < 1) g_nDays = 1;

   //--- primo istante realmente disponibile nel periodo richiesto
   g_tStart = g_m1Time[g_n1 - 1];
   for(int i = 0; i < g_n1; i++)
      if(g_m1Time[i] >= InpFrom) { g_tStart = g_m1Time[i]; break; }
   g_histWarn = ((long)g_tStart > (long)InpFrom + 7L * 86400L);
   Print("Storico M1 dal ", TimeToString(g_m1Time[0], TIME_DATE | TIME_MINUTES), " al ",
         TimeToString(g_m1Time[g_n1 - 1], TIME_DATE | TIME_MINUTES), " | inizio effettivo del periodo ",
         TimeToString(g_tStart, TIME_DATE));
   if(g_histWarn)
      Print("!!! Lo storico M1 disponibile inizia dopo InpFrom: il periodo analizzato e' piu' corto di quello richiesto.",
            " Scarica piu' storico (F2 History Center) o accorcia InpFrom.");

   //--- buchi di dati: nextBrk[j] = primo k >= j con buco dopo k (altrimenti ultimo indice)
   const long gmax = (long)InpMaxGapMin * 60L;
   int nb = g_n1 - 1;
   g_nextBrk[g_n1 - 1] = g_n1 - 1;
   for(int j = g_n1 - 2; j >= 0; j--)
     {
      if((long)(g_m1Time[j+1] - g_m1Time[j]) > gmax) nb = j;
      g_nextBrk[j] = nb;
     }

   //--- contesto descrittivo (non entra nella logica): range M1 e spread mediani nel periodo
   int stride = MathMax(1, g_n1 / 200000);
   double rg[], sp[];
   ArrayResize(rg, g_n1 / stride + 1);
   ArrayResize(sp, g_n1 / stride + 1);
   int cnt = 0, zero = 0;
   for(int i = 0; i < g_n1; i += stride)
     {
      if(g_m1Time[i] < InpFrom || g_m1Time[i] > InpTo) continue;
      rg[cnt] = (g_m1High[i] - g_m1Low[i]) / g_pt;
      sp[cnt] = (double)g_m1Spr[i];
      if(g_m1Spr[i] == 0) zero++;
      cnt++;
     }
   if(cnt > 0)
     {
      ArrayResize(rg, cnt); ArrayResize(sp, cnt);
      ArraySort(rg); ArraySort(sp);
      g_medRange   = rg[cnt / 2];
      g_medSpr     = sp[cnt / 2];
      g_zeroSprPct = 100.0 * zero / cnt;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Per un TF: segnali + mappa verso l'ingresso M1                    |
//+------------------------------------------------------------------+
void ProcessTF(const int t, const MqlRates &r[], const int n)
  {
   g_tfOff[t] = g_used;
   g_tfCnt[t] = 0;
   if(n < 60) { Print("TF ", g_tfName[t], ": storico insufficiente (", n, " barre)"); return; }

   char  dir[];
   uchar bur[];
   int   warm = SD_BuildSignals(r, n, g_par, dir, bur);

   const long   xs      = g_tfSec[t];
   const long   maxGap  = (long)InpMaxEntryGapMin * 60L;
   const bool   slotOK  = g_slotOK[t];
   const bool   isMN    = (g_tf[t] == PERIOD_MN1);

   int need = g_used + n;
   ArrayResize(g_ent,  need, 2000000);
   ArrayResize(g_dir,  need, 2000000);
   ArrayResize(g_bur,  need, 2000000);
   ArrayResize(g_slot, need, 2000000);

   int u = g_used, p = 0;
   int bars = 0, rejGap = 0, rejM1 = 0, ev = 0;
   for(int i = warm; i < n - 1; i++)
     {
      datetime tNext = r[i+1].time;
      if(tNext < InpFrom || tNext > InpTo) continue;
      bars++;
      long spacing = (long)(tNext - r[i].time);
      if(!isMN && (spacing - xs) > maxGap) { rejGap++; continue; }
      while(p < g_n1 && g_m1Time[p] < tNext) p++;
      if(p >= g_n1) break;
      if((long)(g_m1Time[p] - tNext) > maxGap) { rejM1++; continue; }
      g_ent[u]  = p;
      g_dir[u]  = dir[i];
      g_bur[u]  = bur[i];
      g_slot[u] = (ushort)(slotOK ? (int)(((long)r[i].time % g_parentSec) / xs) : 0);
      if(dir[i] != 0) ev++;
      u++;
     }
   g_tfCnt[t]    = u - g_used;
   g_used        = u;
   g_tfBars[t]   = bars;
   g_tfEv[t]     = ev;
   g_tfRejGap[t] = rejGap;
   g_tfRejM1[t]  = rejM1;
   ArrayResize(g_ent,  g_used);
   ArrayResize(g_dir,  g_used);
   ArrayResize(g_bur,  g_used);
   ArrayResize(g_slot, g_used);
   Print("TF ", g_tfName[t], ": barre ", n, " | in periodo ", bars, " | segnali ", ev,
         " | scartate gap sessione ", rejGap, " | senza M1 ", rejM1);
  }

//+------------------------------------------------------------------+
//| Accumulatori                                                      |
//+------------------------------------------------------------------+
bool AllocAcc()
  {
   int cTH = g_nT * g_nH;
   ArrayResize(g_accTH, cTH * ACCN);               ArrayInitialize(g_accTH, 0.0);
   ArrayResize(g_exFav, cTH * (g_nL + 1));         ArrayInitialize(g_exFav, 0);
   ArrayResize(g_exAdv, cTH * (g_nL + 1));         ArrayInitialize(g_exAdv, 0);
   ArrayResize(g_evBN,  cTH * g_nB);               ArrayInitialize(g_evBN, 0);
   ArrayResize(g_bsN,   cTH * g_nB);               ArrayInitialize(g_bsN, 0);
   ArrayResize(g_bsSum, cTH * g_nB);               ArrayInitialize(g_bsSum, 0.0);
   ArrayResize(g_bsHist, cTH * g_nB * (g_nL + 1)); ArrayInitialize(g_bsHist, 0);
   ArrayResize(g_dayS,  cTH * g_nDays);            ArrayInitialize(g_dayS, 0.0);
   ArrayResize(g_dayN,  cTH * g_nDays);            ArrayInitialize(g_dayN, 0.0);
   ArrayResize(g_accBkt,  g_nT * g_nB * ACCN);        ArrayInitialize(g_accBkt, 0.0);
   ArrayResize(g_accSlot, g_nT * g_maxSlots * ACCN);  ArrayInitialize(g_accSlot, 0.0);
   ArrayResize(g_accBur,  g_nT * BCAP * ACCN);        ArrayInitialize(g_accBur, 0.0);
   ArrayResize(g_accDir,  g_nT * 2 * ACCN);           ArrayInitialize(g_accDir, 0.0);
   ArrayResize(g_accDow,  g_nT * 7 * ACCN);           ArrayInitialize(g_accDow, 0.0);

   g_topCap = MathMin(1000, MathMax(0, InpTopRuns));
   g_topN = 0; g_topMinIdx = 0;
   int c = MathMax(1, g_topCap);
   ArrayResize(g_tpTime, c); ArrayResize(g_tpTF, c); ArrayResize(g_tpDir, c);
   ArrayResize(g_tpBur, c);  ArrayResize(g_tpSlot, c);
   ArrayResize(g_tpMfe, c);  ArrayResize(g_tpMae, c); ArrayResize(g_tpRet, c); ArrayResize(g_tpCost, c);

   //--- classifica ipotetica posizione
   int blk = (g_nL + 1) * 4 * RKN;
   long szK = (long)g_nT * g_nRB * g_nH * blk;
   Print("Classifica: ", szK, " celle (", DoubleToString(szK * 8.0 / 1048576.0, 0), " MB)");
   if(szK > 400000000L || ArrayResize(g_rk, (int)szK) != (int)szK)
     {
      Print("Memoria insufficiente per la classifica (", szK, " celle): riduci orizzonti, livelli o TF, oppure allarga le fasce.");
      return false;
     }
   ArrayInitialize(g_rk, 0.0);
   ArrayResize(g_rg, g_nT * g_nH * blk);        ArrayInitialize(g_rg, 0.0);
   ArrayResize(g_lockB, g_nT * g_nH * g_nRB);   ArrayInitialize(g_lockB, 0);
   ArrayResize(g_lockG, g_nT * g_nH);           ArrayInitialize(g_lockG, 0);

   //--- elenco segnali con spunte
   g_evCap = (g_evT >= 0) ? MathMax(0, InpEventRows) : 0;
   g_evCount = 0; g_evSeen = 0;
   g_evStride = (g_evCap > 0) ? MathMax(1, (g_tfEv[g_evT] + g_evCap - 1) / g_evCap) : 1;
   int ce = MathMax(1, g_evCap);
   ArrayResize(g_evTime, ce); ArrayResize(g_evDir, ce); ArrayResize(g_evSlot, ce);
   ArrayResize(g_evBur, ce);  ArrayResize(g_evJ, ce);
   ArrayResize(g_evMfe, ce);  ArrayResize(g_evMae, ce); ArrayResize(g_evRet, ce);
   ArrayResize(g_evMin, ce * g_nL);
   return true;
  }

void AddAcc(double &a[], const int cell, const double fav, const double adv,
            const double retN, const double cost)
  {
   int p = cell * ACCN;
   a[p]     += 1.0;
   a[p + 1] += fav;
   a[p + 2] += adv;
   a[p + 3] += retN;
   a[p + 4] += retN * retN;
   a[p + 5] += cost;
   if(fav > adv)      a[p + 6] += 1.0;
   else if(adv > fav) a[p + 7] += 1.0;
  }

void TopInsert(const datetime tm, const int t, const int d, const double fav, const double adv,
               const double ret, const double cost, const int bur, const int slot)
  {
   if(g_topCap <= 0) return;
   int pos;
   if(g_topN < g_topCap) pos = g_topN++;
   else
     {
      if(fav <= g_tpMfe[g_topMinIdx]) return;
      pos = g_topMinIdx;
     }
   g_tpTime[pos] = tm;  g_tpTF[pos] = t;   g_tpDir[pos] = d;
   g_tpMfe[pos]  = fav; g_tpMae[pos] = adv; g_tpRet[pos] = ret;
   g_tpCost[pos] = cost; g_tpBur[pos] = bur; g_tpSlot[pos] = slot;
   if(g_topN == g_topCap)
     {
      int mi = 0;
      for(int q = 1; q < g_topN; q++) if(g_tpMfe[q] < g_tpMfe[mi]) mi = q;
      g_topMinIdx = mi;
     }
  }

//+------------------------------------------------------------------+
//| Finestre forward sull'orologio M1, basate sul TEMPO (non sul      |
//| numero di barre): max high, min low e close finale entro H minuti |
//| dall'open della barra d'ingresso. Deque monotone: O(N) per H.     |
//+------------------------------------------------------------------+
void ComputeForward(const int hMin)
  {
   const long Hs = (long)hMin * 60L;
   int hd = 0, ht = 0, ld = 0, lt = 0, e = 0;
   for(int j = 0; j < g_n1; j++)
     {
      long tEnd = (long)g_m1Time[j] + Hs;
      while(e < g_n1 && (long)g_m1Time[e] < tEnd)
        {
         while(ht > hd && g_m1High[g_dqH[ht-1]] <= g_m1High[e]) ht--;
         g_dqH[ht++] = e;
         while(lt > ld && g_m1Low[g_dqL[lt-1]] >= g_m1Low[e]) lt--;
         g_dqL[lt++] = e;
         e++;
        }
      while(ht > hd && g_dqH[hd] < j) hd++;
      while(lt > ld && g_dqL[ld] < j) ld++;
      //--- finestra completa: nessun buco dati fra le barre j..e-1 e, se un buco segue la barra e-1,
      //    quella barra deve comunque coprire tEnd (altrimenti l'orizzonte risulterebbe troncato)
      bool ok = (e < g_n1 && e > j && ht > hd && lt > ld &&
                 (g_nextBrk[j] >= e || (g_nextBrk[j] == e - 1 && (long)g_m1Time[e - 1] + 60L >= tEnd)));
      g_ok[j] = ok ? 1 : 0;
      if(ok)
        {
         g_fHi[j] = g_m1High[g_dqH[hd]];
         g_fLo[j] = g_m1Low[g_dqL[ld]];
         g_fCl[j] = g_m1Close[e - 1];
        }
     }
  }

//+------------------------------------------------------------------+
//| Ipotetica posizione: per ogni target (kk) e verso (dd) il risultato|
//| netto e': +target se il movimento favorevole NETTO raggiunge il   |
//| target entro la tenuta, altrimenti il rendimento netto a fine     |
//| tenuta. Nessuno stop. Valori gia' al netto del costo d'ingresso.  |
//+------------------------------------------------------------------+
void AddRank(double &a[], const int base, const int smp,
             const double mfeF, const double maeF, const double retF,
             const double mfeI, const double maeI, const double retI)
  {
   for(int kk = 0; kk <= g_nL; kk++)
     {
      const double lv = (kk == 0) ? 0.0 : g_lev[kk - 1];
      for(int dd = 0; dd < 2; dd++)
        {
         const double mfe = (dd == 0) ? mfeF : mfeI;
         const double mae = (dd == 0) ? maeF : maeI;
         const double ret = (dd == 0) ? retF : retI;
         const bool   hit = (kk > 0 && mfe >= lv);
         const double pnl = hit ? lv : ret;
         const int p = base + (((kk * 2 + dd) * 2 + smp) * RKN);
         a[p]     += 1.0;
         a[p + 1] += pnl;
         a[p + 2] += pnl * pnl;
         if(hit) a[p + 3] += 1.0;
         a[p + 4] += mae;
        }
     }
  }

struct RkStat
  {
   double n, mean, t, hit, mae, sum;
  };

void RkRead(const double &a[], const int base, const int kk, const int dd, const int smp, RkStat &s)
  {
   const int p = base + (((kk * 2 + dd) * 2 + smp) * RKN);
   double n = a[p];
   s.n = n; s.mean = 0.0; s.t = 0.0; s.hit = 0.0; s.mae = 0.0; s.sum = 0.0;
   if(n < 1.0) return;
   s.sum  = a[p + 1];
   s.mean = a[p + 1] / n;
   double var = (n > 1.0) ? (a[p + 2] - n * s.mean * s.mean) / (n - 1.0) : 0.0;
   double sd  = (var > 0.0) ? MathSqrt(var) : 0.0;
   s.t   = (sd > 0.0) ? s.mean / (sd / MathSqrt(n)) : 0.0;
   s.hit = 100.0 * a[p + 3] / n;
   s.mae = a[p + 4] / n;
  }

//--- statistiche sull'INTERO storico (in-sample + out-of-sample sommati)
void RkReadAll(const double &a[], const int base, const int kk, const int dd, RkStat &s)
  {
   const int p0 = base + (((kk * 2 + dd) * 2 + 0) * RKN);
   const int p1 = base + (((kk * 2 + dd) * 2 + 1) * RKN);
   double n = a[p0] + a[p1];
   s.n = n; s.mean = 0.0; s.t = 0.0; s.hit = 0.0; s.mae = 0.0; s.sum = 0.0;
   if(n < 1.0) return;
   double sm = a[p0 + 1] + a[p1 + 1];
   double s2 = a[p0 + 2] + a[p1 + 2];
   s.sum  = sm;
   s.mean = sm / n;
   double var = (n > 1.0) ? (s2 - n * s.mean * s.mean) / (n - 1.0) : 0.0;
   double sd  = (var > 0.0) ? MathSqrt(var) : 0.0;
   s.t   = (sd > 0.0) ? s.mean / (sd / MathSqrt(n)) : 0.0;
   s.hit = 100.0 * (a[p0 + 3] + a[p1 + 3]) / n;
   s.mae = (a[p0 + 4] + a[p1 + 4]) / n;
  }

//+------------------------------------------------------------------+
//| Misura di tutti i segnali e di tutte le barre-base per un         |
//| orizzonte. Convenzione dei costi come SignalLab: l'ingresso paga  |
//| lo spread, MFE/MAE/rendimento lordi sono dall'open d'ingresso.    |
//+------------------------------------------------------------------+
void AccumulateHorizon(const int hi)
  {
   const double pt  = g_pt;
   const bool isRef = (hi == g_refH);
   const int  nL1   = g_nL + 1;
   const int  rkBlk = (g_nL + 1) * 4 * RKN;
   const long Hs    = (long)g_hor[hi] * 60L;
   for(int t = 0; t < g_nT; t++)
     {
      const int cell = t * g_nH + hi;
      const int k0 = g_tfOff[t];
      const int k1 = k0 + g_tfCnt[t];
      for(int k = k0; k < k1; k++)
        {
         const int j = g_ent[k];
         if(g_ok[j] == 0) continue;
         const double o  = g_m1Open[j];
         const double mB = (g_fHi[j] - o) / pt;     // MFE se compro
         const double mS = (o - g_fLo[j]) / pt;     // MFE se vendo
         const int    b  = (int)g_m1Bkt[j];
         const int    bi = cell * g_nB + b;

         //--- base: tutte le barre, direzione casuale
         g_bsN[bi]++;
         g_bsSum[bi] += 0.5 * (mB + mS);
         int cb = 0; while(cb < g_nL && mB >= g_lev[cb]) cb++;
         int cs = 0; while(cs < g_nL && mS >= g_lev[cs]) cs++;
         g_bsHist[bi * nL1 + cb]++;
         g_bsHist[bi * nL1 + cs]++;

         //--- segnali
         const int d = (int)g_dir[k];
         if(d == 0) continue;
         const double fav  = (d > 0) ? mB : mS;
         const double adv  = (d > 0) ? mS : mB;
         const double retG = (d > 0) ? (g_fCl[j] - o) / pt : (o - g_fCl[j]) / pt;
         const double cost = ((InpCostPoints > 0.0) ? InpCostPoints : (double)g_m1Spr[j]) + InpExtraCostPts;
         const double retN = retG - cost;

         AddAcc(g_accTH, cell, fav, adv, retN, cost);
         g_evBN[bi]++;
         int cf = 0; while(cf < g_nL && fav >= g_lev[cf]) cf++;
         int ca = 0; while(ca < g_nL && adv >= g_lev[ca]) ca++;
         g_exFav[cell * nL1 + cf]++;
         g_exAdv[cell * nL1 + ca]++;
         int di = cell * g_nDays + g_m1Day[j];
         g_dayS[di] += retN;
         g_dayN[di] += 1.0;

         //--- ipotetica posizione tenuta H minuti, una per volta (per TF e per fascia)
         {
          const long   tj  = (long)g_m1Time[j];
          const int    smp = (g_m1Day[j] >= g_splitDay) ? 1 : 0;
          const double mfeF = fav - cost, maeF = adv + cost;
          const double mfeI = adv - cost, maeI = fav + cost, retI = -retG - cost;
          if(g_lockG[cell] == 0 || (tj - g_lockG[cell]) >= Hs)
            {
             g_lockG[cell] = tj;
             AddRank(g_rg, cell * rkBlk, smp, mfeF, maeF, retN, mfeI, maeI, retI);
            }
          const int rb = (int)((((long)g_m1Time[j] + g_off) % 86400L) / ((long)g_rbMin * 60L));
          const int lb = cell * g_nRB + rb;
          if(g_lockB[lb] == 0 || (tj - g_lockB[lb]) >= Hs)
            {
             g_lockB[lb] = tj;
             AddRank(g_rk, ((t * g_nRB + rb) * g_nH + hi) * rkBlk, smp, mfeF, maeF, retN, mfeI, maeI, retI);
            }
         }

         if(isRef)
           {
            if(t == g_evT && g_evCap > 0)
              {
               g_evSeen++;
               if(g_evCount < g_evCap && ((g_evSeen - 1) % g_evStride) == 0)
                 {
                  int q = g_evCount++;
                  g_evTime[q] = g_m1Time[j]; g_evDir[q] = d; g_evSlot[q] = (int)g_slot[k];
                  g_evBur[q]  = (int)g_bur[k]; g_evJ[q] = j;
                  g_evMfe[q]  = fav; g_evMae[q] = adv; g_evRet[q] = retN;
                 }
              }
            AddAcc(g_accBkt, t * g_nB + b, fav, adv, retN, cost);
            if(g_slotOK[t]) AddAcc(g_accSlot, t * g_maxSlots + (int)g_slot[k], fav, adv, retN, cost);
            int bc = MathMin((int)g_bur[k], BCAP) - 1;
            if(bc < 0) bc = 0;
            AddAcc(g_accBur, t * BCAP + bc, fav, adv, retN, cost);
            AddAcc(g_accDir, t * 2 + ((d > 0) ? 0 : 1), fav, adv, retN, cost);
            AddAcc(g_accDow, t * 7 + (int)g_m1Dow[j], fav, adv, retN, cost);
            TopInsert(g_m1Time[j], t, d, fav, adv, retN, cost, (int)g_bur[k], (int)g_slot[k]);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Statistiche di una cella (TF, orizzonte)                          |
//+------------------------------------------------------------------+
double SuffixCount(const int &arr[], const int base, const int l)
  {
   double s = 0.0;
   for(int c = l + 1; c <= g_nL; c++) s += (double)arr[base + c];
   return s;
  }

double BaseExcMatched(const int t, const int h, const int l)
  {
   const int cell = t * g_nH + h;
   double num = 0.0, den = 0.0;
   for(int b = 0; b < g_nB; b++)
     {
      int bi = cell * g_nB + b;
      int en = g_evBN[bi];
      if(en <= 0 || g_bsN[bi] <= 0) continue;
      double pr = SuffixCount(g_bsHist, bi * (g_nL + 1), l) / (2.0 * (double)g_bsN[bi]);
      num += (double)en * pr;
      den += (double)en;
     }
   return (den > 0.0) ? num / den : 0.0;
  }

bool GetCell(const int t, const int h, CellStat &s)
  {
   const int cell = t * g_nH + h;
   const int p = cell * ACCN;
   double n = g_accTH[p];
   if(n < 1.0) return false;
   s.n    = n;
   s.mfe  = g_accTH[p + 1] / n;
   s.mae  = g_accTH[p + 2] / n;
   s.ret  = g_accTH[p + 3] / n;
   s.cost = g_accTH[p + 5] / n;
   double var = (n > 1.0) ? (g_accTH[p + 4] - n * s.ret * s.ret) / (n - 1.0) : 0.0;
   s.sd     = (var > 0.0) ? MathSqrt(var) : 0.0;
   s.tNaive = (s.sd > 0.0) ? s.ret / (s.sd / MathSqrt(n)) : 0.0;

   //--- errore standard raggruppato per giorno
   double ss = 0.0;
   const int base = cell * g_nDays;
   for(int d = 0; d < g_nDays; d++)
     {
      double nn = g_dayN[base + d];
      if(nn <= 0.0) continue;
      double dev = g_dayS[base + d] - nn * s.ret;
      ss += dev * dev;
     }
   double se = MathSqrt(ss) / n;
   s.tCl = (se > 0.0) ? s.ret / se : 0.0;

   s.win  = g_accTH[p + 6];
   s.lose = g_accTH[p + 7];
   s.zSign = (s.win + s.lose > 0.0) ? (s.win - s.lose) / MathSqrt(s.win + s.lose) : 0.0;

   //--- MFE della base, pesata sulla distribuzione oraria degli eventi
   double num = 0.0, den = 0.0;
   for(int b = 0; b < g_nB; b++)
     {
      int bi = cell * g_nB + b;
      int en = g_evBN[bi];
      if(en <= 0 || g_bsN[bi] <= 0) continue;
      num += (double)en * (g_bsSum[bi] / (double)g_bsN[bi]);
      den += (double)en;
     }
   s.baseMfe = (den > 0.0) ? num / den : 0.0;
   return true;
  }

string AccCell(const double &a[], const int p)
  {
   double n = a[p];
   if(n < 1.0) return "<td>-</td>";
   double ret = a[p + 3] / n;
   double var = (n > 1.0) ? (a[p + 4] - n * ret * ret) / (n - 1.0) : 0.0;
   double tn  = (var > 0.0) ? ret / (MathSqrt(var) / MathSqrt(n)) : 0.0;
   string col = (n < InpMinPerBucket) ? "#4c566a" : ColTNaive(tn);
   return Td(F1(ret) + " <span style='color:#4c566a'>(" + F0(n) + ")</span>", col);
  }

//+------------------------------------------------------------------+
//| REPORT                                                            |
//+------------------------------------------------------------------+
void RepHead()
  {
   W("<!doctype html><html><head><meta charset='utf-8'><title>SignalLab MultiTF</title><style>");
   W("body{background:#14161a;color:#d8dee9;font:13px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;margin:24px}");
   W("h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;margin:26px 0 8px;color:#88c0d0;border-bottom:1px solid #2e3440;padding-bottom:4px}");
   W("h3{font-size:13px;margin:16px 0 4px;color:#8fbcbb}");
   W("table{border-collapse:collapse;margin:8px 0;font-size:12px}td,th{border:1px solid #2e3440;padding:3px 9px;text-align:right}");
   W("th{background:#1e222a;color:#8fbcbb}td:first-child,th:first-child{text-align:left}");
   W(".thin td,td.thin{color:#4c566a;font-style:italic}");
   W(".kpi{display:inline-block;background:#1e222a;border:1px solid #2e3440;border-radius:6px;padding:10px 16px;margin:4px 8px 4px 0;min-width:120px;font-size:11px;color:#7b8794}");
   W(".kpi b{display:block;font-size:18px;color:#eceff4}");
   W(".note{background:#1e222a;border-left:3px solid #ebcb8b;padding:10px 14px;margin:12px 0;color:#c8ccd4}");
   W(".ko{border-left-color:#bf616a}.ok{border-left-color:#a3be8c}");
   W("details{margin:6px 0}summary{cursor:pointer;color:#88c0d0;padding:3px 0}");
   W("pre{background:#0f1114;border:1px solid #2e3440;border-radius:6px;padding:14px;overflow-x:auto;font:11px/1.45 ui-monospace,Consolas,monospace;color:#d8dee9;white-space:pre}");
   W("</style></head><body>");
  }

void RepIntro()
  {
   W("<h1>SignalLab MultiTF &mdash; " + ModeName() + " &mdash; " + _Symbol + "</h1>");
   datetime tEnd = (datetime)MathMin((long)InpTo, (long)g_m1Time[g_n1 - 1]);
   W("<div style='color:#7b8794'>Tutto in punti (point = " + DoubleToString(g_pt, _Digits) + "). Periodo " +
     TimeToString(g_tStart, TIME_DATE) + " &rarr; " + TimeToString(tEnd, TIME_DATE) +
     " | orologio comune M1 | orizzonte di riferimento " + IS(g_hor[g_refH]) + " min</div>");

   if(g_histWarn)
      W("<div class='note ko'><b>Storico M1 incompleto.</b> Richiesto da " + TimeToString(InpFrom, TIME_DATE) + ", disponibile da " +
        TimeToString(g_tStart, TIME_DATE) + ". Il periodo analizzato &egrave; pi&ugrave; corto: scarica altro storico (F2, Centro cronologia) o accorcia InpFrom.</div>");
   W("<h2>Configurazione e contesto dati</h2>");
   W("<table>");
   W("<tr><th>Segnale</th><td>" + ModeName() + " | EMA " + IS(InpEmaPeriod) + " | volume " + IS(InpVolAvgPeriod) +
     " | soglia " + F2(InpThreshold) + " | Exp TR/ATR &gt; " + F2(InpExpThreshold) + " (ATR " + IS(InpExpAtrPeriod) +
     ", conferma +" + IS(InpExpConfirmOffset) + ") | RunGapBars " + IS(InpRunGapBars) + "</td></tr>");
   W("<tr><th>Costo</th><td>" + (InpCostPoints > 0.0 ? ("fisso " + F1(InpCostPoints) + " pt") : "spread reale M1") +
     " + extra " + F1(InpExtraCostPts) + " pt</td></tr>");
   W("<tr><th>Finestre</th><td>buco dati massimo " + IS(InpMaxGapMin) + " min | gap massimo all'ingresso " +
     IS(InpMaxEntryGapMin) + " min | fasce da " + IS(g_bMin) + " min | offset orario " + IS(InpTimeOffsetH) + " h</td></tr>");
   string hs = "";
   for(int i = 0; i < g_nH; i++) hs += (i > 0 ? ", " : "") + IS(g_hor[i]);
   W("<tr><th>Tenute / orizzonti (min)</th><td>" + hs + "</td></tr>");
   datetime tSplit = (datetime)((g_day0 + (long)g_splitDay) * 86400L - g_off);
   W("<tr><th>Classifica</th><td>in-sample prima del " + TimeToString(tSplit, TIME_DATE) + ", out-of-sample dal " + TimeToString(tSplit, TIME_DATE) + " | fasce da " +
     IS(g_rbMin) + " min | minimo " + IS((long)g_minN) + " posizioni in-sample | una posizione per volta, senza stop</td></tr>");
   string ls = "";
   for(int i = 0; i < g_nL; i++) ls += (i > 0 ? ", " : "") + F0(g_lev[i]);
   W("<tr><th>Livelli (pt)</th><td>" + ls + "</td></tr>");
   W("<tr><th>Barre M1</th><td>" + IS(g_n1) + " | giorni " + IS(g_nDays) + " | range M1 mediano " + F0(g_medRange) +
     " pt | spread M1 mediano " + F0(g_medSpr) + " pt | spread = 0 sul " + F1(g_zeroSprPct) + "% delle barre</td></tr>");
   W("</table>");
   if(InpCostPoints <= 0.0 && g_zeroSprPct > 20.0)
      W("<div class='note ko'><b>Spread storico spesso pari a 0.</b> Il costo &egrave; sottostimato e il netto medio &egrave; "
        "ottimista. Imposta <b>InpCostPoints</b> con lo spread tipico del simbolo o <b>InpExtraCostPts</b> con la commissione.</div>");
   if(InpCostPoints <= 0.0 && InpExtraCostPts <= 0.0)
      W("<div class='note'>Nessuna commissione inclusa. Su conti Raw (FP Markets, IC Markets) aggiungila in "
        "<b>InpExtraCostPts</b>, convertita in punti.</div>");

   W("<h2>Come leggere</h2>");
   W("<div class='note'><b>Netto medio</b> = rendimento a fine orizzonte nella direzione del segnale meno il costo, in punti. "
     "&Egrave; la metrica principale: senza informazione vale circa <b>&minus;costo</b> e non dipende dalla volatilit&agrave; (in media). "
     "<b>MFE</b> e <b>MAE</b> sono ampiezze massime: crescono con la volatilit&agrave; e con la radice dell'orizzonte, quindi un MFE grande da solo non &egrave; edge. "
     "Contano <b>MFE/MAE</b> (asimmetria dentro lo stesso evento) e il confronto con la <b>base</b> = entrate in direzione casuale, stesso TF, stessa fascia oraria.</div>");
   W("<div class='note'><b>t cluster</b> usa l'errore standard raggruppato per giorno: i segnali di barre vicine si sovrappongono, "
     "il t naive &egrave; gonfiato. Giallo = |t| &ge; 2 (debole, atteso per caso su 1 cella su 20). Verde/rosso = oltre la soglia di Bonferroni "
     "sul numero di celle TF x orizzonte di questo report: |t| &ge; <b>" + F2(g_zB) + "</b>. Non cercare la cella migliore: cerca coerenza fra TF vicini e orizzonti vicini. "
     "Il t cluster &egrave; ottimista per orizzonti di un giorno o pi&ugrave;, perch&eacute; giorni adiacenti condividono parte del percorso del prezzo.</div>");
   W("<div class='note'>Tutte le tabelle con <b>t naive</b> o z del segno (fasce orarie, candela nel TF superiore, raffica, direzione, giorno, classifiche) "
     "non sono corrette n&eacute; per la sovrapposizione n&eacute; per i test multipli: il giallo significa solo |t| &ge; 2, non esiste mai verde o rosso. "
     "Nelle classifiche la posizione occupa il suo slot per tutta la tenuta anche se il target esce prima (scelta prudente).</div>");
   W("<div class='note'>Le misure sono <b>in punti</b>: i simboli non sono confrontabili fra loro e le ore con volatilit&agrave; alta dominano i totali. "
     "Per questo le tabelle orarie sono affiancate dalla base della stessa fascia.</div>");
  }

void RepCoverage()
  {
   W("<h2>Copertura per timeframe</h2>");
   W("<div class='note'>Un segnale viene scartato se tra la chiusura della barra e la barra successiva c'&egrave; una pausa di sessione "
     "oltre <b>" + IS(InpMaxEntryGapMin) + "</b> min (weekend, chiusura giornaliera): l'ingresso non sarebbe quello del segnale. "
     "Per D1, W1 e MN1 questo scarta di fatto quasi tutto: aumenta <b>InpMaxEntryGapMin</b> se vuoi entrare comunque all'apertura successiva.</div>");
   W("<table><tr><th>TF</th><th>Barre in periodo</th><th>Scartate gap sessione</th><th>Senza M1</th><th>Barre base</th>"
     "<th>Segnali</th><th>Misurati @" + IS(g_hor[g_refH]) + "m</th><th>% misurati</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      double nref = g_accTH[(t * g_nH + g_refH) * ACCN];
      double pc = (g_tfEv[t] > 0) ? 100.0 * nref / g_tfEv[t] : 0.0;
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(IS(g_tfBars[t])) + Td(IS(g_tfRejGap[t])) + Td(IS(g_tfRejM1[t])) +
        Td(IS(g_tfCnt[t])) + Td(IS(g_tfEv[t])) + Td(F0(nref)) + Td(F1(pc)) + "</tr>");
     }
   W("</table>");
  }

void RepVerdict()
  {
   W("<h2>Verdetto per timeframe &mdash; orizzonte " + IS(g_hor[g_refH]) + " min</h2>");
   W("<table><tr><th>TF</th><th>Segnali misurati</th><th>MFE medio</th><th>MAE medio</th><th>MFE/MAE</th>"
     "<th>MFE base</th><th>MFE/base</th><th>Netto medio</th><th>t naive</th><th>t cluster</th><th>Costo medio</th>"
     "<th>MFE&gt;MAE %</th><th>z segno</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      CellStat s;
      if(!GetCell(t, g_refH, s))
        { W("<tr class='thin'><td>" + g_tfName[t] + "</td><td colspan='12'>nessun segnale misurato</td></tr>"); continue; }
      double ratio = (s.mae > 0.0) ? s.mfe / s.mae : 0.0;
      double rb    = (s.baseMfe > 0.0) ? s.mfe / s.baseMfe : 0.0;
      double wp    = (s.win + s.lose > 0.0) ? 100.0 * s.win / (s.win + s.lose) : 0.0;
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(F0(s.n)) + Td(F0(s.mfe)) + Td(F0(s.mae)) +
        Td(F2(ratio), ratio > 1.0 ? "#a3be8c" : "#bf616a") + Td(F0(s.baseMfe)) + Td(F2(rb)) +
        Td("<b>" + F1(s.ret) + "</b>", ColSign(s.ret)) + Td(F2(s.tNaive)) +
        Td("<b>" + F2(s.tCl) + "</b>", ColT(s.tCl)) + Td(F1(s.cost)) + Td(F1(wp)) +
        Td(F2(s.zSign), ColTNaive(s.zSign)) + "</tr>");
     }
   W("</table>");
  }

void RepMatrices()
  {
   W("<h2>Netto medio (punti) per TF e orizzonte &mdash; (t cluster)</h2>");
   W("<table><tr><th>TF</th>");
   for(int h = 0; h < g_nH; h++) W("<th>" + IS(g_hor[h]) + "m</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int h = 0; h < g_nH; h++)
        {
         CellStat s;
         if(!GetCell(t, h, s)) { W("<td>-</td>"); continue; }
         W(Td(F1(s.ret) + " (" + F1(s.tCl) + ")", ColT(s.tCl)));
        }
      W("</tr>");
     }
   W("</table>");

   W("<h2>MFE medio (punti) per TF e orizzonte &mdash; [MFE/MAE]</h2>");
   W("<div class='note'>Descrive per quanti punti il prezzo prosegue nella direzione del segnale, ma &egrave; confuso dalla volatilit&agrave;. "
     "Verde = MFE/MAE &gt; 1 (il movimento favorevole supera quello avverso nello stesso evento).</div>");
   W("<table><tr><th>TF</th>");
   for(int h = 0; h < g_nH; h++) W("<th>" + IS(g_hor[h]) + "m</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int h = 0; h < g_nH; h++)
        {
         CellStat s;
         if(!GetCell(t, h, s)) { W("<td>-</td>"); continue; }
         double ratio = (s.mae > 0.0) ? s.mfe / s.mae : 0.0;
         W(Td(F0(s.mfe) + " [" + F2(ratio) + "]", ratio > 1.0 ? "#a3be8c" : "#bf616a"));
        }
      W("</tr>");
     }
   W("</table>");
  }

void RepExceed()
  {
   W("<h2>Probabilit&agrave; di raggiungere un livello &mdash; orizzonte " + IS(g_hor[g_refH]) + " min</h2>");
   W("<div class='note'>Ogni cella: <b>favorevole % / avverso % / base %</b>. Favorevole = MFE &ge; livello nella direzione del segnale; "
     "avverso = MAE &ge; livello; base = stessa probabilit&agrave; con direzione casuale, stesso TF e stessa distribuzione oraria. "
     "Verde se favorevole supera sia l'avverso sia la base, rosso se &egrave; sotto entrambi.</div>");
   W("<table><tr><th>TF</th><th>n</th>");
   for(int l = 0; l < g_nL; l++) W("<th>&ge; " + F0(g_lev[l]) + " pt</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      CellStat s;
      if(!GetCell(t, g_refH, s)) continue;
      const int cell = t * g_nH + g_refH;
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(F0(s.n)));
      for(int l = 0; l < g_nL; l++)
        {
         double pf = 100.0 * SuffixCount(g_exFav, cell * (g_nL + 1), l) / s.n;
         double pa = 100.0 * SuffixCount(g_exAdv, cell * (g_nL + 1), l) / s.n;
         double pb = 100.0 * BaseExcMatched(t, g_refH, l);
         string col = "#7b8794";
         if(pf > pa && pf > pb) col = "#a3be8c";
         else if(pf < pa && pf < pb) col = "#bf616a";
         W(Td(F1(pf) + " / " + F1(pa) + " / " + F1(pb), col));
        }
      W("</tr>");
     }
   W("</table>");
  }

//+------------------------------------------------------------------+
//| SPUNTE: minuti al raggiungimento dei livelli per il campione      |
//+------------------------------------------------------------------+
void ComputeEventReach()
  {
   if(g_evCount < 1) return;
   const long Hs = (long)g_hor[g_refH] * 60L;
   for(int q = 0; q < g_evCount; q++)
     {
      for(int l = 0; l < g_nL; l++) g_evMin[q * g_nL + l] = -1;
      const int    j = g_evJ[q];
      const double o = g_m1Open[j];
      const long   tEnd = (long)g_m1Time[j] + Hs;
      int nxt = 0;
      for(int x = j; x < g_n1 && (long)g_m1Time[x] < tEnd && nxt < g_nL; x++)
        {
         double fv = (g_evDir[q] > 0) ? (g_m1High[x] - o) / g_pt : (o - g_m1Low[x]) / g_pt;
         while(nxt < g_nL && fv >= g_lev[nxt])
           {
            g_evMin[q * g_nL + nxt] = (int)(((long)g_m1Time[x] - (long)g_m1Time[j]) / 60L) + 1;
            nxt++;
           }
        }
     }
  }

void RepEvents()
  {
   if(g_evCount < 1) return;
   W("<h2>Spunte: i punti raggiunti dopo ogni segnale &mdash; " + g_tfName[g_evT] + ", entro " + IS(g_hor[g_refH]) + " min</h2>");
   W("<div class='note'>Campione uniforme di <b>" + IS(g_evCount) + "</b> segnali del TF " + g_tfName[g_evT] +
     " (uno ogni " + IS(g_evStride) + ") su tutto il periodo. <b>&#10003; N m</b> = livello raggiunto entro N minuti dall'ingresso, "
     "nella direzione del segnale, come movimento lordo dal prezzo d'ingresso (open M1, spread escluso). "
     "&laquo;-&raquo; = non raggiunto entro l'orizzonte. L'elenco &egrave; illustrativo: le percentuali da usare sono nelle tabelle aggregate.</div>");
   W("<table><tr><th>#</th><th>Entrata (server + offset)</th><th>Giorno</th><th>Verso</th><th>Candela TF sup.</th><th>Raffica</th><th>MFE</th><th>MAE</th><th>Netto</th>");
   for(int l = 0; l < g_nL; l++) W("<th>" + F0(g_lev[l]) + "</th>");
   W("</tr>");
   for(int q = 0; q < g_evCount; q++)
     {
      datetime tm = (datetime)((long)g_evTime[q] + g_off);
      int dow = (int)((((long)tm / 86400L) + 4L) % 7L);
      string sl = g_slotOK[g_evT] ? (IS(g_evSlot[q] + 1) + "/" + IS(g_slotCnt[g_evT])) : "-";
      W("<tr>" + Td(IS(q + 1)) + "<td>" + TimeToString(tm, TIME_DATE | TIME_MINUTES) + "</td>" + Td(DowName(dow)) +
        Td(g_evDir[q] > 0 ? "BUY" : "SELL", g_evDir[q] > 0 ? "#a3be8c" : "#bf616a") + Td(sl) + Td(IS(g_evBur[q])) +
        Td(F0(g_evMfe[q])) + Td(F0(g_evMae[q])) + Td(F0(g_evRet[q]), ColSign(g_evRet[q])));
      for(int l = 0; l < g_nL; l++)
        {
         int mm = g_evMin[q * g_nL + l];
         if(mm >= 0) W(Td("&#10003; " + IS(mm) + "m", "#a3be8c"));
         else        W(Td("-", "#4c566a"));
        }
      W("</tr>");
     }
   W("</table>");
  }

//+------------------------------------------------------------------+
//| Probabilita' di raggiungere il target entro la tenuta (per TF)    |
//+------------------------------------------------------------------+
void RepReach(const int t)
  {
   W("<table><tr><th>Target (pt) \\ Tieni (min)</th>");
   for(int h = 0; h < g_nH; h++) W("<th>" + IS(g_hor[h]) + "</th>");
   W("</tr>");
   for(int l = 0; l < g_nL; l++)
     {
      W("<tr><td>" + F0(g_lev[l]) + "</td>");
      for(int h = 0; h < g_nH; h++)
        {
         const int cell = t * g_nH + h;
         double n = g_accTH[cell * ACCN];
         if(n < 1.0) { W("<td>-</td>"); continue; }
         double pf = 100.0 * SuffixCount(g_exFav, cell * (g_nL + 1), l) / n;
         double pb = 100.0 * BaseExcMatched(t, h, l);
         string col = "#7b8794";
         if(pf > pb * 1.1 && pf >= 1.0) col = "#a3be8c";
         else if(pf < pb * 0.9 && pb >= 1.0) col = "#bf616a";
         W(Td(F1(pf) + " (" + F1(pb) + ")", col));
        }
      W("</tr>");
     }
   W("</table>");
  }

//+------------------------------------------------------------------+
//| Mappa tenuta x target (per TF): netto medio per posizione IS/OOS  |
//+------------------------------------------------------------------+
void RepHeat(const int t)
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   for(int dd = 0; dd < 2; dd++)
     {
      W("<h3>" + string(dd == 0 ? "SEGUI il segnale" : "INVERTI il segnale") +
        " &mdash; netto medio per posizione (punti), in-sample / out-of-sample</h3>");
      W("<table><tr><th>Target \\ Tieni (min)</th>");
      for(int h = 0; h < g_nH; h++) W("<th>" + IS(g_hor[h]) + "</th>");
      W("</tr>");
      for(int kk = 0; kk <= g_nL; kk++)
        {
         W("<tr><td>" + (kk == 0 ? string("nessuno (solo tempo)") : F0(g_lev[kk - 1]) + " pt") + "</td>");
         for(int h = 0; h < g_nH; h++)
           {
            RkStat a, b;
            const int base = (t * g_nH + h) * blk;
            RkRead(g_rg, base, kk, dd, 0, a);
            RkRead(g_rg, base, kk, dd, 1, b);
            string tip = " title='posizioni IS " + F0(a.n) + " / OOS " + F0(b.n) + "'";
            if(a.n < g_minN)
              { W("<td class='thin'" + tip + ">" + F1(a.mean) + " / " + F1(b.mean) + "</td>"); continue; }
            string col = "#ebcb8b";
            if(a.mean > 0.0 && b.mean > 0.0) col = "#a3be8c";
            else if(a.mean < 0.0 && b.mean < 0.0) col = "#bf616a";
            W("<td style='color:" + col + "'" + tip + ">" + F1(a.mean) + " / " + F1(b.mean) + "</td>");
           }
         W("</tr>");
        }
      W("</table>");
     }
  }

//+------------------------------------------------------------------+
//| CLASSIFICA                                                        |
//+------------------------------------------------------------------+
string RBktLabel(const int b)
  {
   int s0 = b * g_rbMin, e0 = s0 + g_rbMin;
   return StringFormat("%02d:%02d-%02d:%02d", s0 / 60, s0 % 60, e0 / 60, e0 % 60);
  }

string KLabel(const int kk) { return (kk == 0) ? string("nessuno") : F0(g_lev[kk - 1]); }

string EsitoCell(const RkStat &a, const RkStat &b)
  {
   if(b.n < MathMax(10.0, g_minN / 3.0)) return Td("OOS scarso", "#4c566a");
   if(b.mean > 0.0 && b.t >= 2.0)             return Td("<b>TIENE</b>", "#a3be8c");
   if(b.mean > 0.0)                           return Td("debole", "#ebcb8b");
   return Td("NO", "#bf616a");
  }

string RankHead()
  {
   return "<table><tr><th>#</th><th>TF</th><th>Fascia (entrata)</th><th>Verso</th><th>Tieni (min)</th><th>Target (pt)</th>"
          "<th>IS pos.</th><th>IS netto</th><th>IS t</th><th>Target raggiunto % (netto)</th>"
          "<th>OOS pos.</th><th>OOS netto</th><th>OOS t</th><th>Esito</th></tr>";
  }

string RankRow(const int rank, const int t, const int rb, const int h, const int kk, const int dd)
  {
   const int base = ((t * g_nRB + rb) * g_nH + h) * ((g_nL + 1) * 4 * RKN);
   RkStat a, b;
   RkRead(g_rk, base, kk, dd, 0, a);
   RkRead(g_rk, base, kk, dd, 1, b);
   string hs = (kk == 0) ? "-" : F1(a.hit);
   return "<tr>" + Td(IS(rank)) + "<td>" + g_tfName[t] + "</td><td>" + RBktLabel(rb) + "</td>" +
          Td(dd == 0 ? "SEGUI" : "INVERTI") + Td(IS(g_hor[h])) + Td(KLabel(kk)) +
          Td(F0(a.n)) + Td("<b>" + F1(a.mean) + "</b>", ColSign(a.mean)) + Td(F2(a.t)) + Td(hs) +
          Td(F0(b.n)) + Td("<b>" + F1(b.mean) + "</b>", ColSign(b.mean)) + Td(F2(b.t), ColTNaive(b.t)) +
          EsitoCell(a, b) + "</tr>";
  }

void RankDigest(const string tag, const int rank, const int t, const int rb, const int h, const int kk, const int dd)
  {
   const int base = ((t * g_nRB + rb) * g_nH + h) * ((g_nL + 1) * 4 * RKN);
   RkStat a, b;
   RkRead(g_rk, base, kk, dd, 0, a);
   RkRead(g_rk, base, kk, dd, 1, b);
   g_dg += tag + "|" + IS(rank) + "|" + g_tfName[t] + "|" + RBktLabel(rb) + "|" + (dd == 0 ? "SEGUI" : "INVERTI") +
           "|hold|" + IS(g_hor[h]) + "|tp|" + KLabel(kk) + "|isn|" + F0(a.n) + "|ismean|" + F1(a.mean) + "|ist|" + F2(a.t) +
           "|hit|" + F1(a.hit) + "|oosn|" + F0(b.n) + "|oosmean|" + F1(b.mean) + "|oost|" + F2(b.t) + "\n";
  }

//--- migliore combinazione (tenuta, target, verso) per ogni TF, su tutto il giorno
void RepBestTF()
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   W("<h2>A1 &mdash; Quanto tenere e per quanti punti: miglior combinazione per timeframe (scelta in-sample)</h2>");
   W("<div class='note'><b>Come &egrave; costruita.</b> Per ogni TF si simula una posizione per volta (tutto il giorno): si entra sul segnale, "
     "si esce al target (se indicato) oppure dopo <b>Tieni</b> minuti, senza stop. Il risultato &egrave; netto del costo. "
     "La combinazione migliore &egrave; scelta sul <b>primo " + IS(MathMin(95, MathMax(5, InpSplitPct))) + "%</b> del periodo (in-sample, IS) per t-statistic; "
     "le colonne OOS sono il restante periodo, mai usato per scegliere. <b>Solo l'OOS conta.</b> "
     "&laquo;INVERTI&raquo; = fare l'opposto del segnale: &egrave; incluso perch&eacute; un trigger pu&ograve; contenere informazione dal lato sbagliato.</div>");
   W("<table><tr><th>TF</th><th>Verso</th><th>Tieni (min)</th><th>Target (pt)</th><th>IS pos.</th><th>IS netto</th><th>IS t</th>"
     "<th>Target raggiunto % (netto)</th><th>OOS pos.</th><th>OOS netto</th><th>OOS t</th><th>Esito</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      double bt = -1.0e9; int bh = -1, bk = -1, bd = -1;
      for(int h = 0; h < g_nH; h++)
         for(int kk = 0; kk <= g_nL; kk++)
            for(int dd = 0; dd < 2; dd++)
              {
               RkStat a;
               RkRead(g_rg, (t * g_nH + h) * blk, kk, dd, 0, a);
               if(a.n < g_minN) continue;
               if(a.t > bt) { bt = a.t; bh = h; bk = kk; bd = dd; }
              }
      if(bh < 0)
        { W("<tr class='thin'><td>" + g_tfName[t] + "</td><td colspan='11'>campione in-sample insufficiente</td></tr>"); continue; }
      RkStat a, b;
      RkRead(g_rg, (t * g_nH + bh) * blk, bk, bd, 0, a);
      RkRead(g_rg, (t * g_nH + bh) * blk, bk, bd, 1, b);
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(bd == 0 ? "SEGUI" : "INVERTI") + Td(IS(g_hor[bh])) + Td(KLabel(bk)) +
        Td(F0(a.n)) + Td("<b>" + F1(a.mean) + "</b>", ColSign(a.mean)) + Td(F2(a.t)) + Td(bk == 0 ? "-" : F1(a.hit)) +
        Td(F0(b.n)) + Td("<b>" + F1(b.mean) + "</b>", ColSign(b.mean)) + Td(F2(b.t), ColTNaive(b.t)) + EsitoCell(a, b) + "</tr>");
      g_dg += "BESTTF|" + g_tfName[t] + "|" + (bd == 0 ? "SEGUI" : "INVERTI") + "|hold|" + IS(g_hor[bh]) + "|tp|" + KLabel(bk) +
              "|isn|" + F0(a.n) + "|ismean|" + F1(a.mean) + "|ist|" + F2(a.t) + "|hit|" + F1(a.hit) +
              "|oosn|" + F0(b.n) + "|oosmean|" + F1(b.mean) + "|oost|" + F2(b.t) + "\n";
     }
   W("</table>");
  }

//--- classifica congiunta: TF x fascia x tenuta x target x verso
void RepRank()
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   const int rankTop = MathMin(200, MathMax(1, InpRankTop));
   const int P = MathMax(300, rankTop * 5);
   double pT[]; int pTf[], pB[], pH[], pK[], pD[];
   ArrayResize(pT, P); ArrayResize(pTf, P); ArrayResize(pB, P);
   ArrayResize(pH, P); ArrayResize(pK, P);  ArrayResize(pD, P);
   int pn = 0;
   long m = 0;
   for(int t = 0; t < g_nT; t++)
      for(int rb = 0; rb < g_nRB; rb++)
         for(int h = 0; h < g_nH; h++)
           {
            const int base = ((t * g_nRB + rb) * g_nH + h) * blk;
            if(g_rk[base] < g_minN) continue;
            for(int kk = 0; kk <= g_nL; kk++)
               for(int dd = 0; dd < 2; dd++)
                 {
                  RkStat a;
                  RkRead(g_rk, base, kk, dd, 0, a);
                  m++;
                  int pos;
                  if(pn < P) { pos = pn; pn++; }
                  else
                    {
                     if(a.t <= pT[P - 1]) continue;
                     pos = P - 1;
                    }
                  while(pos > 0 && pT[pos - 1] < a.t)
                    {
                     pT[pos] = pT[pos - 1]; pTf[pos] = pTf[pos - 1]; pB[pos] = pB[pos - 1];
                     pH[pos] = pH[pos - 1]; pK[pos] = pK[pos - 1];   pD[pos] = pD[pos - 1];
                     pos--;
                    }
                  pT[pos] = a.t; pTf[pos] = t; pB[pos] = rb; pH[pos] = h; pK[pos] = kk; pD[pos] = dd;
                 }
           }

   W("<h2>A2 &mdash; Classifica: quando osservare il segnale e come gestire la posizione (scelta in-sample)</h2>");
   if(pn < 1 || m < 1)
     { W("<div class='note ko'>Nessuna combinazione con almeno " + IS(InpRankMinN) + " posizioni in-sample. Riduci <b>InpRankMinN</b> o allarga il periodo.</div>"); return; }

   //--- diagnostica sull'insieme dei migliori in-sample
   int posOOS = 0, strong = 0, usable = 0;
   for(int i = 0; i < pn; i++)
     {
      RkStat b;
      RkRead(g_rk, ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk, pK[i], pD[i], 1, b);
      if(b.n < MathMax(10.0, g_minN / 3.0)) continue;
      usable++;
      if(b.mean > 0.0) posOOS++;
      if(b.mean > 0.0 && b.t >= 2.0) strong++;
     }
   double chanceT = (m > 1) ? MathSqrt(2.0 * MathLog((double)m)) : 0.0;
   double bestT = pT[0];
   bool noisy = (bestT < chanceT + 1.0 || usable == 0 || posOOS * 2 < usable);
   W("<div class='note " + string(noisy ? "ko" : "ok") + "'><b>Diagnostica della classifica.</b> Combinazioni valutate in-sample: <b>" + IS(m) +
     "</b>. Il miglior t in-sample trovato &egrave; <b>" + F2(bestT) + "</b>; per puro caso, su " + IS(m) +
     " tentativi indipendenti, ci si aspetta un massimo intorno a <b>" + F2(chanceT) + "</b> (stima per eccesso: le combinazioni vicine sono correlate, quindi i test davvero indipendenti sono meno). "
     "Fra le prime <b>" + IS(pn) + "</b> in-sample, <b>" + IS(posOOS) + "</b> su " + IS(usable) + " con campione OOS sufficiente restano positive fuori campione, <b>" +
     IS(strong) + "</b> con OOS t &ge; 2. " +
     string(noisy ? "Se questi numeri sono vicini a zero la classifica &egrave; rumore di selezione: non operare nessuna di queste righe."
                  : "Il risultato regge la prima verifica, ma resta da confermare su dati mai visti (forward o altro simbolo).") + "</div>");

   const int K = MathMin(rankTop, pn);
   W("<h3>Prime " + IS(K) + " in-sample (ordinate per t in-sample)</h3>");
   W(RankHead());
   for(int i = 0; i < K; i++)
     {
      W(RankRow(i + 1, pTf[i], pB[i], pH[i], pK[i], pD[i]));
      RankDigest("RANK", i + 1, pTf[i], pB[i], pH[i], pK[i], pD[i]);
     }
   W("</table>");
   g_dg += "DIAG|combos|" + IS(m) + "|bestt|" + F2(bestT) + "|chance|" + F2(chanceT) + "|pool|" + IS(pn) +
           "|poosn|" + IS(usable) + "|pos|" + IS(posOOS) + "|strong|" + IS(strong) + "\n";

   //--- candidati che reggono fuori campione (seconda selezione: usa l'OOS)
   int sv[]; ArrayResize(sv, pn);
   double svT[]; ArrayResize(svT, pn);
   int ns = 0;
   for(int i = 0; i < pn; i++)
     {
      if(pT[i] < 2.0) continue;
      RkStat b;
      RkRead(g_rk, ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk, pK[i], pD[i], 1, b);
      if(b.n < MathMax(10.0, g_minN / 3.0)) continue;
      if(b.mean > 0.0 && b.t >= 2.0) { sv[ns] = i; svT[ns] = b.t; ns++; }
     }
   for(int i = 0; i < ns - 1; i++)
      for(int j2 = i + 1; j2 < ns; j2++)
         if(svT[j2] > svT[i]) { double tt = svT[i]; svT[i] = svT[j2]; svT[j2] = tt; int ti = sv[i]; sv[i] = sv[j2]; sv[j2] = ti; }
   W("<h3>Fra le prime " + IS(pn) + " in-sample: quelle con IS t &ge; 2 che reggono anche fuori campione (OOS netto &gt; 0 e OOS t &ge; 2)</h3>");
   if(ns == 0)
      W("<div class='note ko'>Nessuna combinazione fra le migliori in-sample ha OOS positivo e significativo. &Egrave; il risultato atteso se il segnale non ha edge netto dei costi.</div>");
   else
     {
      W("<div class='note'>Attenzione: questa lista usa l'OOS per selezionare, quindi l'OOS non &egrave; pi&ugrave; incontaminato. "
        "Sono candidati da confermare in forward test o su un altro periodo/simbolo, non risultati.</div>");
      W(RankHead());
      int shown = MathMin(ns, 20);
      for(int i = 0; i < shown; i++)
        {
         W(RankRow(i + 1, pTf[sv[i]], pB[sv[i]], pH[sv[i]], pK[sv[i]], pD[sv[i]]));
         RankDigest("SURV", i + 1, pTf[sv[i]], pB[sv[i]], pH[sv[i]], pK[sv[i]], pD[sv[i]]);
        }
      W("</table>");
     }
  }

//+------------------------------------------------------------------+
//| TABELLA B - CON RUMORE                                            |
//| Ordinata sull'INTERO storico, senza separare in-sample e          |
//| out-of-sample: e' quello che vedrebbe chi ottimizza senza         |
//| protezione. Le due parti del periodo sono affiancate solo per     |
//| mostrare se il risultato e' stabile; la riga pero' e' stata       |
//| scelta guardando entrambe, quindi non sono indipendenti.          |
//+------------------------------------------------------------------+
string NoiseSortName()
  {
   switch(InpNoiseSort)
     {
      case NS_TOTAL: return "profitto totale in punti";
      case NS_MEAN:  return "netto medio per posizione";
      case NS_T:     return "t-statistic";
     }
   return "profitto totale in punti";
  }

double NoiseKey(const RkStat &s)
  {
   switch(InpNoiseSort)
     {
      case NS_TOTAL: return s.sum;
      case NS_MEAN:  return s.mean;
      case NS_T:     return s.t;
     }
   return s.sum;
  }

string CoerenzaCell(const RkStat &a, const RkStat &b)
  {
   if(a.n < 1.0 || b.n < MathMax(10.0, g_minN / 3.0)) return Td("2a parte scarsa", "#4c566a");
   if(a.mean > 0.0 && b.mean > 0.0) return Td("coerente +", "#a3be8c");
   if(a.mean < 0.0 && b.mean < 0.0) return Td("coerente -", "#7b8794");
   return Td("INCOERENTE", "#bf616a");
  }

string NoiseHead(const bool withBucket)
  {
   return "<table><tr><th>#</th><th>TF</th>" + string(withBucket ? "<th>Fascia (entrata)</th>" : "") +
          "<th>Verso</th><th>Tieni (min)</th><th>Target (pt)</th><th>Posizioni</th><th>Profitto totale (pt)</th>"
          "<th>Netto medio</th><th>t</th><th>Target raggiunto % (netto)</th>"
          "<th>Netto 1a parte</th><th>Netto 2a parte</th><th>Fra le due parti</th></tr>";
  }

string NoiseCells(const RkStat &all, const RkStat &a, const RkStat &b, const int kk)
  {
   return Td(F0(all.n)) + Td("<b>" + F0(all.sum) + "</b>", ColSign(all.sum)) + Td(F1(all.mean), ColSign(all.mean)) +
          Td(F2(all.t), ColTNaive(all.t)) + Td(kk == 0 ? "-" : F1(all.hit)) +
          Td(F1(a.mean), ColSign(a.mean)) + Td(F1(b.mean), ColSign(b.mean)) + CoerenzaCell(a, b);
  }

void RepNoiseIntro()
  {
   int pct = MathMin(95, MathMax(5, InpSplitPct));
   W("<h2>Due letture della stessa classifica</h2>");
   W("<div class='note'><b>Tabelle A</b> (sopra): le combinazioni sono scelte guardando solo il primo " + IS(pct) +
     "% del periodo e poi verificate sul resto, che non ha mai partecipato alla scelta. "
     "<b>Tabelle B</b> (sotto): le combinazioni sono scelte guardando <b>tutto</b> lo storico, ordinate per <b>" + NoiseSortName() +
     "</b>, senza alcuna protezione: &egrave; quello che vedrebbe chi ottimizza sull'intero storico. "
     "Con migliaia di combinazioni la prima riga di B &egrave; positiva per costruzione, anche se il segnale non ha informazione. "
     "Serve per confrontare quanto B promette rispetto a quanto A conferma, non per scegliere cosa operare.</div>");
  }

//--- B1: miglior combinazione per TF sull'intero storico
void RepBestTFNoise()
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   W("<h2>B1 &mdash; Quanto tenere e per quanti punti: miglior combinazione per timeframe (CON RUMORE, intero storico)</h2>");
   W("<div class='note ko'>Per ogni TF si prende la combinazione con il valore pi&ugrave; alto di <b>" + NoiseSortName() +
     "</b> su tutto il periodo. Le colonne <b>1a parte</b> (primo " + IS(MathMin(95, MathMax(5, InpSplitPct))) +
     "%) e <b>2a parte</b> (resto) mostrano se il risultato &egrave; stabile nel tempo, ma non sono indipendenti: la riga &egrave; stata scelta guardandole entrambe. "
     "&laquo;INCOERENTE&raquo; = le due parti hanno segno opposto: tipico del rumore.</div>");
   W(NoiseHead(false));
   for(int t = 0; t < g_nT; t++)
     {
      double bk0 = -1.0e18; int bh = -1, bk = -1, bd = -1;
      for(int h = 0; h < g_nH; h++)
         for(int kk = 0; kk <= g_nL; kk++)
            for(int dd = 0; dd < 2; dd++)
              {
               RkStat all;
               RkReadAll(g_rg, (t * g_nH + h) * blk, kk, dd, all);
               if(all.n < g_minN) continue;
               double key = NoiseKey(all);
               if(key > bk0) { bk0 = key; bh = h; bk = kk; bd = dd; }
              }
      if(bh < 0)
        { W("<tr class='thin'><td>-</td><td>" + g_tfName[t] + "</td><td colspan='11'>campione insufficiente</td></tr>"); continue; }
      RkStat all, a, b;
      RkReadAll(g_rg, (t * g_nH + bh) * blk, bk, bd, all);
      RkRead(g_rg, (t * g_nH + bh) * blk, bk, bd, 0, a);
      RkRead(g_rg, (t * g_nH + bh) * blk, bk, bd, 1, b);
      W("<tr>" + Td("-") + "<td>" + g_tfName[t] + "</td>" + Td(bd == 0 ? "SEGUI" : "INVERTI") + Td(IS(g_hor[bh])) + Td(KLabel(bk)) +
        NoiseCells(all, a, b, bk) + "</tr>");
      g_dg += "BESTNOISE|" + g_tfName[t] + "|" + (bd == 0 ? "SEGUI" : "INVERTI") + "|hold|" + IS(g_hor[bh]) + "|tp|" + KLabel(bk) +
              "|n|" + F0(all.n) + "|total|" + F0(all.sum) + "|mean|" + F1(all.mean) + "|t|" + F2(all.t) + "|hit|" + F1(all.hit) +
              "|part1|" + F1(a.mean) + "|part2|" + F1(b.mean) + "\n";
     }
   W("</table>");
  }

//--- B2: classifica congiunta TF x fascia x tenuta x target x verso sull'intero storico
void RepRankNoise()
  {
   const int blk = (g_nL + 1) * 4 * RKN;
   const int rankTop = MathMin(200, MathMax(1, InpRankTop));
   const int P = MathMax(300, rankTop * 5);
   double pK2[]; int pTf[], pB[], pH[], pK[], pD[];
   ArrayResize(pK2, P); ArrayResize(pTf, P); ArrayResize(pB, P);
   ArrayResize(pH, P);  ArrayResize(pK, P);  ArrayResize(pD, P);
   int pn = 0;
   long m = 0;
   for(int t = 0; t < g_nT; t++)
      for(int rb = 0; rb < g_nRB; rb++)
         for(int h = 0; h < g_nH; h++)
           {
            const int base = ((t * g_nRB + rb) * g_nH + h) * blk;
            if(g_rk[base] + g_rk[base + RKN] < g_minN) continue;
            for(int kk = 0; kk <= g_nL; kk++)
               for(int dd = 0; dd < 2; dd++)
                 {
                  RkStat all;
                  RkReadAll(g_rk, base, kk, dd, all);
                  m++;
                  double key = NoiseKey(all);
                  int pos;
                  if(pn < P) { pos = pn; pn++; }
                  else
                    {
                     if(key <= pK2[P - 1]) continue;
                     pos = P - 1;
                    }
                  while(pos > 0 && pK2[pos - 1] < key)
                    {
                     pK2[pos] = pK2[pos - 1]; pTf[pos] = pTf[pos - 1]; pB[pos] = pB[pos - 1];
                     pH[pos] = pH[pos - 1];   pK[pos]  = pK[pos - 1];  pD[pos] = pD[pos - 1];
                     pos--;
                    }
                  pK2[pos] = key; pTf[pos] = t; pB[pos] = rb; pH[pos] = h; pK[pos] = kk; pD[pos] = dd;
                 }
           }

   W("<h2>B2 &mdash; Classifica (CON RUMORE): ordinata per " + NoiseSortName() + " sull'intero storico</h2>");
   if(pn < 1 || m < 1)
     { W("<div class='note ko'>Nessuna combinazione con almeno " + IS((long)g_minN) + " posizioni.</div>"); return; }

   //--- diagnostica: quanto del profitto "trovato" sopravvive nella parte piu' recente
   double sumAll = 0.0, sumLate = 0.0, nAll = 0.0, nLate = 0.0;
   int incoh = 0, bothPos = 0, usable = 0;
   const int K = MathMin(rankTop, pn);
   for(int i = 0; i < K; i++)
     {
      const int base = ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk;
      RkStat all, a, b;
      RkReadAll(g_rk, base, pK[i], pD[i], all);
      RkRead(g_rk, base, pK[i], pD[i], 0, a);
      RkRead(g_rk, base, pK[i], pD[i], 1, b);
      sumAll += all.sum; sumLate += b.sum; nAll += all.n; nLate += b.n;
     }
   for(int i = 0; i < pn; i++)
     {
      const int base = ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk;
      RkStat a, b;
      RkRead(g_rk, base, pK[i], pD[i], 0, a);
      RkRead(g_rk, base, pK[i], pD[i], 1, b);
      if(b.n < MathMax(10.0, g_minN / 3.0)) continue;
      usable++;
      if(a.mean > 0.0 && b.mean > 0.0) bothPos++;
      else if((a.mean > 0.0) != (b.mean > 0.0)) incoh++;
     }
   double chanceT = (m > 1) ? MathSqrt(2.0 * MathLog((double)m)) : 0.0;
   double shareLate = (sumAll != 0.0) ? 100.0 * sumLate / sumAll : 0.0;
   double shareN    = (nAll > 0.0) ? 100.0 * nLate / nAll : 0.0;
   RkStat top;
   RkReadAll(g_rk, ((pTf[0] * g_nRB + pB[0]) * g_nH + pH[0]) * blk, pK[0], pD[0], top);
   bool good = (usable > 0 && bothPos * 2 >= usable && shareLate >= 0.5 * shareN);
   W("<div class='note " + string(good ? "ok" : "ko") + "'><b>Cosa promette questa tabella.</b> Combinazioni valutate: <b>" + IS(m) +
     "</b>. La prima ha profitto totale <b>" + F0(top.sum) + " pt</b> su " + F0(top.n) + " posizioni (netto medio " + F1(top.mean) +
     ", t " + F2(top.t) + "); il t massimo atteso per puro caso su " + IS(m) + " tentativi &egrave; intorno a <b>" + F2(chanceT) + "</b>. "
     "Nelle prime " + IS(K) + " righe, la parte pi&ugrave; recente del periodo contiene il <b>" + F1(shareN) + "%</b> delle posizioni ma il <b>" +
     F1(shareLate) + "%</b> del profitto: se l'edge fosse stabile le due quote sarebbero simili. "
     "Fra le prime " + IS(pn) + " con campione sufficiente, <b>" + IS(bothPos) + "</b> su " + IS(usable) + " sono positive in entrambe le parti e <b>" +
     IS(incoh) + "</b> cambiano segno. " +
     string(good ? "Il profitto sembra stabile nel tempo: confrontalo con la tabella A prima di fidarti."
                 : "La distanza fra il profitto promesso e quello della parte recente &egrave; la misura del rumore di selezione.") + "</div>");

   W("<h3>Prime " + IS(K) + " per " + NoiseSortName() + " (intero storico)</h3>");
   W(NoiseHead(true));
   for(int i = 0; i < K; i++)
     {
      const int base = ((pTf[i] * g_nRB + pB[i]) * g_nH + pH[i]) * blk;
      RkStat all, a, b;
      RkReadAll(g_rk, base, pK[i], pD[i], all);
      RkRead(g_rk, base, pK[i], pD[i], 0, a);
      RkRead(g_rk, base, pK[i], pD[i], 1, b);
      W("<tr>" + Td(IS(i + 1)) + "<td>" + g_tfName[pTf[i]] + "</td><td>" + RBktLabel(pB[i]) + "</td>" +
        Td(pD[i] == 0 ? "SEGUI" : "INVERTI") + Td(IS(g_hor[pH[i]])) + Td(KLabel(pK[i])) + NoiseCells(all, a, b, pK[i]) + "</tr>");
      g_dg += "NOISE|" + IS(i + 1) + "|" + g_tfName[pTf[i]] + "|" + RBktLabel(pB[i]) + "|" + (pD[i] == 0 ? "SEGUI" : "INVERTI") +
              "|hold|" + IS(g_hor[pH[i]]) + "|tp|" + KLabel(pK[i]) + "|n|" + F0(all.n) + "|total|" + F0(all.sum) +
              "|mean|" + F1(all.mean) + "|t|" + F2(all.t) + "|hit|" + F1(all.hit) + "|part1|" + F1(a.mean) + "|part2|" + F1(b.mean) + "\n";
     }
   W("</table>");
   g_dg += "DIAGNOISE|combos|" + IS(m) + "|sort|" + NoiseSortName() + "|top_total|" + F0(top.sum) + "|top_t|" + F2(top.t) +
           "|chance_t|" + F2(chanceT) + "|late_share_n|" + F1(shareN) + "|late_share_profit|" + F1(shareLate) +
           "|pool|" + IS(pn) + "|usable|" + IS(usable) + "|both_pos|" + IS(bothPos) + "|incoherent|" + IS(incoh) + "\n";
  }

void RepStruct()
  {
   W("<h2>Posizione nella raffica (come il Sequence Filter dell'EA) &mdash; netto medio (n)</h2>");
   W("<div class='note'>1 = primo segnale dopo un segnale opposto, 2 = secondo consecutivo nella stessa direzione, ecc. "
     "&Egrave; la domanda che il Sequence Filter dell'EA tenta di sfruttare: qui la misuri senza filtrare. "
     "Celle grigie = meno di " + IS(InpMinPerBucket) + " eventi.</div>");
   W("<table><tr><th>TF</th>");
   for(int c = 1; c <= BCAP; c++) W("<th>" + IS(c) + (c == BCAP ? "+" : "") + "</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int c = 0; c < BCAP; c++) W(AccCell(g_accBur, (t * BCAP + c) * ACCN));
      W("</tr>");
     }
   W("</table>");

   W("<h2>Direzione: buy contro sell &mdash; netto medio (n)</h2>");
   W("<table><tr><th>TF</th><th>BUY</th><th>BUY MFE</th><th>BUY MAE</th><th>SELL</th><th>SELL MFE</th><th>SELL MAE</th></tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int d = 0; d < 2; d++)
        {
         int p = (t * 2 + d) * ACCN;
         W(AccCell(g_accDir, p));
         double n = g_accDir[p];
         W(Td(n > 0.0 ? F0(g_accDir[p + 1] / n) : "-"));
         W(Td(n > 0.0 ? F0(g_accDir[p + 2] / n) : "-"));
        }
      W("</tr>");
     }
   W("</table>");

   W("<h2>Giorno della settimana (server + offset) &mdash; netto medio (n)</h2>");
   W("<table><tr><th>TF</th>");
   for(int d = 0; d < 7; d++) W("<th>" + DowName(d) + "</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int d = 0; d < 7; d++) W(AccCell(g_accDow, (t * 7 + d) * ACCN));
      W("</tr>");
     }
   W("</table>");
  }

void RepTOD(const int t)
  {
   W("<table><tr><th>Fascia (ora di entrata)</th><th>Segnali</th><th>MFE medio</th><th>MAE medio</th><th>MFE base</th>"
     "<th>MFE/base</th><th>Netto medio</th><th>t naive</th><th>Costo medio</th></tr>");
   for(int b = 0; b < g_nB; b++)
     {
      int p = (t * g_nB + b) * ACCN;
      double n = g_accBkt[p];
      if(n < 1.0) continue;
      double mfe = g_accBkt[p + 1] / n, mae = g_accBkt[p + 2] / n;
      double ret = g_accBkt[p + 3] / n, cost = g_accBkt[p + 5] / n;
      double var = (n > 1.0) ? (g_accBkt[p + 4] - n * ret * ret) / (n - 1.0) : 0.0;
      double tn  = (var > 0.0) ? ret / (MathSqrt(var) / MathSqrt(n)) : 0.0;
      int bi = (t * g_nH + g_refH) * g_nB + b;
      double bm = (g_bsN[bi] > 0) ? g_bsSum[bi] / (double)g_bsN[bi] : 0.0;
      string cls = (n < InpMinPerBucket) ? " class='thin'" : "";
      W("<tr" + cls + "><td>" + BktLabel(b) + "</td>" + Td(F0(n)) + Td(F0(mfe)) + Td(F0(mae)) + Td(F0(bm)) +
        Td(bm > 0.0 ? F2(mfe / bm) : "-") + Td("<b>" + F1(ret) + "</b>", ColSign(ret)) +
        Td(F2(tn), ColTNaive(tn)) + Td(F1(cost)) + "</tr>");
      if(InpDigestTOD)
         g_dg += "TOD|" + g_tfName[t] + "|" + BktLabel(b) + "|n|" + F0(n) + "|mfe|" + F0(mfe) + "|mae|" + F0(mae) +
                 "|base|" + F0(bm) + "|ret|" + F1(ret) + "|t|" + F2(tn) + "|cost|" + F1(cost) + "\n";
     }
   W("</table>");
  }

void RepSlot(const int t)
  {
   W("<table><tr><th>Candela nel " + EnumToString(InpParentTF) + "</th><th>Segnali</th><th>MFE medio</th><th>MAE medio</th>"
     "<th>Netto medio</th><th>t naive</th><th>Costo medio</th></tr>");
   for(int s = 0; s < g_slotCnt[t]; s++)
     {
      int p = (t * g_maxSlots + s) * ACCN;
      double n = g_accSlot[p];
      if(n < 1.0) continue;
      double mfe = g_accSlot[p + 1] / n, mae = g_accSlot[p + 2] / n;
      double ret = g_accSlot[p + 3] / n, cost = g_accSlot[p + 5] / n;
      double var = (n > 1.0) ? (g_accSlot[p + 4] - n * ret * ret) / (n - 1.0) : 0.0;
      double tn  = (var > 0.0) ? ret / (MathSqrt(var) / MathSqrt(n)) : 0.0;
      string cls = (n < InpMinPerBucket) ? " class='thin'" : "";
      W("<tr" + cls + "><td>" + IS(s + 1) + " di " + IS(g_slotCnt[t]) + "</td>" + Td(F0(n)) + Td(F0(mfe)) + Td(F0(mae)) +
        Td("<b>" + F1(ret) + "</b>", ColSign(ret)) + Td(F2(tn), ColTNaive(tn)) + Td(F1(cost)) + "</tr>");
     }
   W("</table>");
  }

void RepDetails()
  {
   W("<h2>Dettaglio per timeframe &mdash; orizzonte " + IS(g_hor[g_refH]) + " min</h2>");
   W("<div class='note'><b>Fascia oraria</b>: ora del server (+ offset) della barra M1 d'ingresso, cio&egrave; della chiusura del segnale. "
     "<b>Candela nel TF superiore</b>: posizione della barra del segnale dentro il " + EnumToString(InpParentTF) +
     " (es. 8 di 15 = ottava candela di un contenitore da 15). Con fasce strette il campione per riga &egrave; piccolo: "
     "le righe grigie sono rumore, non fasce operative.</div>");
   for(int t = 0; t < g_nT; t++)
     {
      if(g_accTH[(t * g_nH + g_refH) * ACCN] < 1.0) continue;
      W("<details><summary><b>" + g_tfName[t] + "</b> &mdash; fasce orarie, " + string(g_slotOK[t] ? "candela nel contenitore, " : "") + "target e tenuta</summary>");
      W("<h3>Fasce orarie</h3>");
      RepTOD(t);
      if(g_slotOK[t])
        {
         W("<h3>Candela nel " + EnumToString(InpParentTF) + "</h3>");
         RepSlot(t);
        }
      W("<h3>Probabilit&agrave; di raggiungere il target entro la tenuta: segnale % (base %) &mdash; movimento lordo dal prezzo d'ingresso, spread escluso</h3>");
      RepReach(t);
      W("<h3>Quanto tenere e per quanti punti (una posizione per volta, tutto il giorno)</h3>");
      RepHeat(t);
      W("</details>");
     }
  }

void RepTop()
  {
   if(g_topN < 1) return;
   //--- ordinamento per MFE decrescente
   int idx[];
   ArrayResize(idx, g_topN);
   for(int i = 0; i < g_topN; i++) idx[i] = i;
   for(int i = 0; i < g_topN - 1; i++)
      for(int j = i + 1; j < g_topN; j++)
         if(g_tpMfe[idx[j]] > g_tpMfe[idx[i]]) { int tmp = idx[i]; idx[i] = idx[j]; idx[j] = tmp; }

   W("<h2>Run pi&ugrave; lunghe &mdash; orizzonte " + IS(g_hor[g_refH]) + " min</h2>");
   W("<div class='note'>Classifica globale di tutti i TF per MFE lordo (punti dall'open d'ingresso nella direzione del segnale). "
     "Orologio comune M1, quindi confrontabili. Sono gli estremi della distribuzione: indicano <b>quando</b> si sono verificati, non dove c'&egrave; edge. "
     "Se si concentrano in poche giornate sono eventi di mercato, non una propriet&agrave; del segnale.</div>");
   W("<table><tr><th>#</th><th>Entrata (server + offset)</th><th>Giorno</th><th>TF</th><th>Dir</th><th>Candela TF sup.</th><th>Raffica</th>"
     "<th>MFE</th><th>MAE</th><th>Netto</th><th>Costo</th></tr>");
   for(int r = 0; r < g_topN; r++)
     {
      int q = idx[r];
      int t = g_tpTF[q];
      datetime tm = (datetime)((long)g_tpTime[q] + g_off);
      long dd = (long)tm / 86400L;
      int dow = (int)((dd + 4L) % 7L);
      string sl = g_slotOK[t] ? (IS(g_tpSlot[q] + 1) + "/" + IS(g_slotCnt[t])) : "-";
      W("<tr>" + Td(IS(r + 1)) + "<td>" + TimeToString(tm, TIME_DATE | TIME_MINUTES) + "</td>" + Td(DowName(dow)) +
        Td(g_tfName[t]) + Td(g_tpDir[q] > 0 ? "BUY" : "SELL", g_tpDir[q] > 0 ? "#a3be8c" : "#bf616a") + Td(sl) +
        Td(IS(g_tpBur[q])) + Td("<b>" + F0(g_tpMfe[q]) + "</b>") + Td(F0(g_tpMae[q])) +
        Td(F0(g_tpRet[q]), ColSign(g_tpRet[q])) + Td(F1(g_tpCost[q])) + "</tr>");
      if(r < 25)
         g_dg += "TOP|" + IS(r + 1) + "|" + TimeToString(tm, TIME_DATE | TIME_MINUTES) + "|" + g_tfName[t] + "|" +
                 IS(g_tpDir[q]) + "|slot|" + sl + "|burst|" + IS(g_tpBur[q]) + "|mfe|" + F0(g_tpMfe[q]) +
                 "|mae|" + F0(g_tpMae[q]) + "|ret|" + F0(g_tpRet[q]) + "|cost|" + F1(g_tpCost[q]) + "\n";
     }
   W("</table>");
  }

//--- digest compatto da incollare in chat
void BuildDigest()
  {
   string d = "### SIGNALLAB MULTITF DIGEST v1\n";
   d += "# tutto in punti; netto = rendimento a fine orizzonte nella direzione del segnale meno costo\n";
   d += "# tcl = t con errore standard raggruppato per giorno; base = MFE di entrate casuali, stessa fascia oraria\n";
   d += "CFG|" + _Symbol + "|digits|" + IS(_Digits) + "|point|" + DoubleToString(g_pt, 8) + "|mode|" + ModeName() +
        "|ema|" + IS(InpEmaPeriod) + "|vol|" + IS(InpVolAvgPeriod) + "|thr|" + F2(InpThreshold) +
        "|expthr|" + F2(InpExpThreshold) + "|expatr|" + IS(InpExpAtrPeriod) + "|expoff|" + IS(InpExpConfirmOffset) +
        "|rungap|" + IS(InpRunGapBars) + "\n";
   d += "RUN|costfix|" + F1(InpCostPoints) + "|extra|" + F1(InpExtraCostPts) + "|maxgap|" + IS(InpMaxGapMin) +
        "|entrygap|" + IS(InpMaxEntryGapMin) + "|bucket|" + IS(g_bMin) + "|parent|" + EnumToString(InpParentTF) +
        "|ref|" + IS(g_hor[g_refH]) + "|zbonf|" + F2(g_zB) + "\n";
   d += "DATA|m1bars|" + IS(g_n1) + "|days|" + IS(g_nDays) + "|medrange|" + F0(g_medRange) + "|medspr|" + F0(g_medSpr) +
        "|zerospr|" + F1(g_zeroSprPct) + "\n";
   for(int t = 0; t < g_nT; t++)
      d += "TF|" + g_tfName[t] + "|bars|" + IS(g_tfBars[t]) + "|base|" + IS(g_tfCnt[t]) + "|signals|" + IS(g_tfEv[t]) +
           "|rejgap|" + IS(g_tfRejGap[t]) + "|rejm1|" + IS(g_tfRejM1[t]) + "\n";
   for(int t = 0; t < g_nT; t++)
      for(int h = 0; h < g_nH; h++)
        {
         CellStat s;
         if(!GetCell(t, h, s)) continue;
         d += "TFH|" + g_tfName[t] + "|" + IS(g_hor[h]) + "|n|" + F0(s.n) + "|mfe|" + F0(s.mfe) + "|mae|" + F0(s.mae) +
              "|base|" + F0(s.baseMfe) + "|ret|" + F1(s.ret) + "|tn|" + F2(s.tNaive) + "|tcl|" + F2(s.tCl) +
              "|cost|" + F1(s.cost) + "|win|" + F0(s.win) + "|lose|" + F0(s.lose) + "|zs|" + F2(s.zSign) + "\n";
        }
   for(int t = 0; t < g_nT; t++)
     {
      CellStat s;
      if(!GetCell(t, g_refH, s)) continue;
      const int cell = t * g_nH + g_refH;
      d += "LEV|" + g_tfName[t] + "|" + IS(g_hor[g_refH]);
      for(int l = 0; l < g_nL; l++)
         d += "|" + F0(g_lev[l]) + "|" + F1(100.0 * SuffixCount(g_exFav, cell * (g_nL + 1), l) / s.n) +
              "/" + F1(100.0 * SuffixCount(g_exAdv, cell * (g_nL + 1), l) / s.n) +
              "/" + F1(100.0 * BaseExcMatched(t, g_refH, l));
      d += "\n";
     }
   for(int t = 0; t < g_nT; t++)
     {
      for(int c = 0; c < BCAP; c++)
        {
         int p = (t * BCAP + c) * ACCN; double n = g_accBur[p];
         if(n < 1.0) continue;
         d += "BURST|" + g_tfName[t] + "|" + IS(c + 1) + "|n|" + F0(n) + "|mfe|" + F0(g_accBur[p+1]/n) +
              "|mae|" + F0(g_accBur[p+2]/n) + "|ret|" + F1(g_accBur[p+3]/n) + "\n";
        }
      for(int k = 0; k < 2; k++)
        {
         int p = (t * 2 + k) * ACCN; double n = g_accDir[p];
         if(n < 1.0) continue;
         d += "DIR|" + g_tfName[t] + "|" + (k == 0 ? "BUY" : "SELL") + "|n|" + F0(n) + "|mfe|" + F0(g_accDir[p+1]/n) +
              "|mae|" + F0(g_accDir[p+2]/n) + "|ret|" + F1(g_accDir[p+3]/n) + "\n";
        }
      for(int k = 0; k < 7; k++)
        {
         int p = (t * 7 + k) * ACCN; double n = g_accDow[p];
         if(n < 1.0) continue;
         d += "DOW|" + g_tfName[t] + "|" + DowName(k) + "|n|" + F0(n) + "|ret|" + F1(g_accDow[p+3]/n) + "\n";
        }
     }
   g_dg = d + g_dg;
  }

void WriteReport()
  {
   //--- soglia di Bonferroni sul numero di celle con dati
   int m = 0;
   for(int t = 0; t < g_nT; t++)
      for(int h = 0; h < g_nH; h++)
         if(g_accTH[(t * g_nH + h) * ACCN] >= 1.0) m++;
   g_zB = ZCrit(MathMax(1, m));

   string tag = SafeTag(_Symbol) + "_" + ModeName();
   string fn  = "SignalLab_MultiTF_" + tag + ".html";
   g_fh = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(g_fh == INVALID_HANDLE) Print("HTML non scrivibile (errore ", GetLastError(), "): salvo solo il digest.");

   g_dg = "";
   RepHead();
   RepIntro();
   RepCoverage();
   RepVerdict();
   RepMatrices();
   RepExceed();
   RepEvents();
   RepNoiseIntro();
   RepBestTF();
   RepRank();
   RepBestTFNoise();
   RepRankNoise();
   RepStruct();
   RepDetails();
   RepTop();
   BuildDigest();

   string esc = g_dg;
   StringReplace(esc, "&", "&amp;");
   StringReplace(esc, "<", "&lt;");
   W("<h2>Digest da copiare</h2>");
   W("<div class='note'>Seleziona e incolla in chat. Stesso testo in <b>MQL5/Files/SignalLab_MultiTF_digest_" + tag + ".txt</b>.</div>");
   W("<pre>" + esc + "### END\n</pre>");
   W("</body></html>");
   if(g_fh != INVALID_HANDLE)
     {
      FileClose(g_fh);
      g_fh = INVALID_HANDLE;
      Print("Report: MQL5/Files/", fn);
     }

   int df = FileOpen("SignalLab_MultiTF_digest_" + tag + ".txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(df != INVALID_HANDLE)
     {
      FileWriteString(df, g_dg + "### END\n");
      FileClose(df);
      Print("Digest: MQL5/Files/SignalLab_MultiTF_digest_", tag, ".txt");
     }
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   uint t0 = GetTickCount();
   g_pt  = _Point;
   g_off = (long)InpTimeOffsetH * 3600L;
   if(!SetupInputs()) return;
   if(!LoadM1()) return;

   //--- primo giorno out-of-sample: la classifica si costruisce solo sul periodo precedente
   {
    int dFrom = (int)((((long)g_tStart + g_off) / 86400L) - g_day0);
    if(dFrom < 0) dFrom = 0;
    int pct = MathMin(95, MathMax(5, InpSplitPct));
    g_splitDay = dFrom + (int)((double)(g_nDays - dFrom) * pct / 100.0);
    Print("Split IS/OOS: giorni ", dFrom, "-", g_nDays - 1, " | OOS dal giorno ", g_splitDay, " (", pct, "% in-sample)");
   }

   ArrayResize(g_tfOff, g_nT);    ArrayInitialize(g_tfOff, 0);
   ArrayResize(g_tfCnt, g_nT);    ArrayInitialize(g_tfCnt, 0);
   ArrayResize(g_tfBars, g_nT);   ArrayInitialize(g_tfBars, 0);
   ArrayResize(g_tfEv, g_nT);     ArrayInitialize(g_tfEv, 0);
   ArrayResize(g_tfRejGap, g_nT); ArrayInitialize(g_tfRejGap, 0);
   ArrayResize(g_tfRejM1, g_nT);  ArrayInitialize(g_tfRejM1, 0);

   Print("=== SignalLab MultiTF | ", _Symbol, " | modo ", ModeName(), " | ", g_nT, " TF | ", g_nH,
         " orizzonti | riferimento ", g_hor[g_refH], " min");

   //--- segnali su ogni TF (M1 per primo se richiesto: riusa l'array gia' in memoria)
   int idxM1 = -1;
   for(int t = 0; t < g_nT; t++) if(g_tf[t] == PERIOD_M1) idxM1 = t;
   if(idxM1 >= 0) ProcessTF(idxM1, g_r1, ArraySize(g_r1));
   ArrayFree(g_r1);
   for(int t = 0; t < g_nT; t++)
     {
      if(IsStopped()) { Print("Interrotto dall'utente."); Comment(""); return; }
      if(t == idxM1) continue;
      MqlRates r[];
      int n = LoadTF(t, r);
      if(n < 60) { Print("TF ", g_tfName[t], ": storico non disponibile (", n, ")"); continue; }
      ProcessTF(t, r, n);
      ArrayFree(r);
     }
   Comment("SignalLab MultiTF: segnali pronti, misura in corso...");
   if(g_used == 0) { Print("Nessuna barra valida: controlla periodo e storico."); Comment(""); return; }

   //--- finestre forward e accumulo, un orizzonte alla volta
   if(!AllocAcc()) { Comment(""); return; }
   ArrayResize(g_fHi, g_n1); ArrayResize(g_fLo, g_n1); ArrayResize(g_fCl, g_n1);
   ArrayResize(g_ok, g_n1);  ArrayResize(g_dqH, g_n1); ArrayResize(g_dqL, g_n1);
   for(int hi = 0; hi < g_nH; hi++)
     {
      if(IsStopped()) { Print("Interrotto dall'utente."); Comment(""); return; }
      ComputeForward(g_hor[hi]);
      AccumulateHorizon(hi);
      Print("Orizzonte ", g_hor[hi], " min completato (", (GetTickCount() - t0) / 1000.0, " s)");
      Comment("SignalLab MultiTF: orizzonte ", g_hor[hi], " min completato (", hi + 1, "/", g_nH, ")");
     }

   ComputeEventReach();
   WriteReport();
   Comment("");
   Print("Fatto in ", (GetTickCount() - t0) / 1000.0, " s");
  }
//+------------------------------------------------------------------+
