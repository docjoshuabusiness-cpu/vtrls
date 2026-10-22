//+------------------------------------------------------------------+
//|                                            FlowLab_MultiTF.mq5   |
//|  Banco di prova di SyntheticDelta v3 (Flow Z) su TUTTI i         |
//|  timeframe del simbolo del grafico, in PUNTI, con costi reali.   |
//|  File unico: nessun include. Stessa impostazione di SignalLab:   |
//|  M1 come orologio comune, ingresso all'open dopo il segnale,     |
//|  spread M1 reale + commissione sempre inclusi, split in-sample / |
//|  out-of-sample per giorni, errore standard raggruppato per       |
//|  giorno, Bonferroni su TUTTI i test.                             |
//|                                                                  |
//|  Cosa misura                                                      |
//|   1. REGRESSIONE CONTINUA: su ogni barra del TF il valore della  |
//|      feature contro il rendimento futuro (da M1) a ogni          |
//|      orizzonte. Usa tutte le barre, quindi ha piu' potenza degli |
//|      eventi. Feature: Flow Z (CLV e BVC, con e senza peso di     |
//|      volume stagionale), assorbimento, il VECCHIO delta, e due   |
//|      riferimenti banali (momentum e C-EMA13): se Z non li batte  |
//|      non aggiunge informazione.                                  |
//|   2. POTENZA: l'IC minimo che il campione riesce a vedere (da    |
//|      2.8 volte l'errore standard osservato).                     |
//|   3. PLACEBO: per le celle promettenti, lo stesso test con Z     |
//|      spostato di giorni interi (conserva autocorrelazione e      |
//|      orario): p-value empirico.                                  |
//|   4. EVENTI: primo attraversamento di +-soglia, SEGUI e INVERTI, |
//|      costo incluso; la miglior cella in-sample per TF e il suo   |
//|      risultato fuori campione, con la t dell'abilita' (cov fra   |
//|      verso e rendimento, che toglie la deriva del prezzo).       |
//|                                                                  |
//|  Come leggerlo: un risultato conta solo se supera Bonferroni su  |
//|  tutti i test E regge fuori campione E il placebo concorda.      |
//|  "Nessuna evidenza" NON e' "nessun effetto": guarda la potenza.  |
//|                                                                  |
//|  Uso: apri il grafico del simbolo (anche personalizzato QDM) e   |
//|  trascina lo script. Output in MQL5/Files:                       |
//|    FlowLab_MultiTF_<simbolo>.html            (report)            |
//|    FlowLab_MultiTF_riepilogo_<simbolo>.txt   (testo da copiare)  |
//|    FlowLab_MultiTF_digest_<simbolo>.txt      (tutte le celle)    |
//|                                                                  |
//|  La logica di Flow Z e' quella di SyntheticDelta_v3.1 e di       |
//|  research/syntheticdelta_ref.py. NON compilato in ambiente di    |
//|  sviluppo: compila in MetaEditor e controlla gli Errors.         |
//+------------------------------------------------------------------+
#property copyright "FlowLab"
#property version   "1.00"
#property script_show_inputs
#property strict

input group "=== FLOW Z (stessi parametri di SyntheticDelta v3.x) ==="
input int      InpFlowN         = 12;     // N: barre di aggregazione del flusso
input int      InpFlowM         = 500;    // M: finestra dello z-score
input int      InpFlowDays      = 20;     // D: sedute di storia per la fascia oraria (volume stagionale)
input int      InpFlowMinSess   = 5;      // campioni minimi per fascia
input string   InpEventThr      = "1.0,1.5,2.0"; // soglie |Z| degli eventi (primo attraversamento)

input group "=== DATI ==="
input datetime InpFrom          = D'2015.01.01 00:00';
input datetime InpTo            = D'2030.01.01 00:00';
input string   InpTFs           = "ALL";  // ALL = M1..D1 oppure elenco, es. M5,M15,H1,H4
input int      InpTimeOffsetH   = 0;      // ore da sommare al server time per giorni e fasce
input int      InpMaxGapMin     = 90;     // scarta finestre con un buco di dati oltre N minuti
input int      InpMaxEntryGapMin = 5;     // scarta segnali se l'ingresso e' oltre N minuti dopo la chiusura

input group "=== MISURA (tutto in PUNTI, orologio M1) ==="
input string   InpHorizons      = "1,2,3,5,10,15,30,45,60,120,240,1440"; // orizzonti in minuti, uguali per tutti i TF
input int      InpEntryLagMin   = 0;      // ritardo d'ingresso in minuti (prova di stress)
input double   InpCostPoints    = 0;      // 0 = spread reale della barra M1 d'ingresso
input double   InpExtraCostPts  = 0;      // costo extra in punti

input group "=== DENARO ==="
input double   InpLotSize       = 0.01;   // lotto ipotetico (solo per le colonne in denaro)
input double   InpCommissionPerLotSide = 3.0; // commissione per 1.00 lotto e per lato, in valuta del conto: SEMPRE inclusa nel costo (due lati, in punti)
input double   InpPointValuePerLot = 0;   // valore di 1 punto per 1.00 lotto; 0 = automatico (come SignalLab)
input string   InpPointValueSymbol = "";  // facoltativo: simbolo REALE del broker da cui leggere il valore del tick

input group "=== TEST ==="
input int      InpSplitPct      = 70;     // % iniziale del periodo per SCEGLIERE; il resto serve solo a verificare
input int      InpMinEvents     = 30;     // eventi minimi in-sample perche' una cella evento possa essere scelta
input int      InpPlaceboB      = 200;    // estrazioni del placebo a traslazione
input double   InpPlaceboMinT   = 3.0;    // il placebo si fa per le celle con |t| almeno cosi' (costa tempo)
input int      InpPlaceboPerTF  = 3;      // celle con placebo per ogni TF: le prime per |t| (0 = nessun placebo)
input int      InpClusterDays   = 1;      // giorni minimi per cluster; con orizzonti lunghi salgono da soli
input int      InpTopK          = 15;     // righe della classifica per |t|

//--- ================================================================
#define NFEAT  8
#define MAXTHR 6

const ENUM_TIMEFRAMES g_allTF[19] =
  {PERIOD_M1, PERIOD_M2, PERIOD_M3, PERIOD_M4, PERIOD_M5, PERIOD_M6, PERIOD_M10, PERIOD_M12,
   PERIOD_M15, PERIOD_M20, PERIOD_M30, PERIOD_H1, PERIOD_H2, PERIOD_H3, PERIOD_H4, PERIOD_H6,
   PERIOD_H8, PERIOD_H12, PERIOD_D1};
const string g_allName[19] =
  {"M1","M2","M3","M4","M5","M6","M10","M12","M15","M20","M30","H1","H2","H3","H4","H6","H8","H12","D1"};

struct SDFlowParams
  {
   int    flowMode;      // 0 = CLV, 1 = BVC
   int    flowBars;      // N
   int    zWindow;       // M
   double threshold;     // non usata qui
   int    seasonDays;    // D
   int    minSessions;
   double weightCap;
   int    atrPeriod;
   int    bvcBars;
   bool   useWeights;
   int    runGapBars;
  };

struct RegRes
  {
   double n, beta, t, ic, icse;
  };

struct CellRes
  {
   int    tf, feat, hm;
   double n, beta, t, ic, icse, tIS, tOOS, icOOS, p;
  };

struct EvRes
  {
   int    tf, hm, side;
   double thr, nIS, netIS, tIS, nOOS, gOOS, netOOS, tOOS, skillT, buyPct;
  };

struct Clu
  {
   double n, sum, A, B, C, cs, cn;
   int    day;
  };

//--- parametri e dati
string   g_featName[NFEAT];
int      g_nT = 0;
ENUM_TIMEFRAMES g_tf[];
string   g_tfName[];
long     g_tfSec[];
int      g_nH = 0;
int      g_hor[];
int      g_nThr = 0;
double   g_thr[];
double   g_pt = 0.0;
long     g_off = 0;

MqlRates g_r1[];
int      g_n1 = 0;
datetime g_m1Time[];
double   g_m1Open[], g_m1Close[];
int      g_m1Spr[];
int      g_m1Day[];
int      g_nextBrk[];
long     g_day0 = 0;
int      g_nDays = 1;
datetime g_tStart = 0;
bool     g_histWarn = false;
int      g_splitDay = 0;
double   g_medSpr = 0.0, g_zeroSprPct = 0.0;

double   g_fCl[];
uchar    g_okF[];
double   g_F[];
char     g_evd[];
ulong    g_seed = 88172645463325252;

//--- denaro
double   g_pv = 0.0, g_commPts = 0.0, g_extraPts = 0.0;
bool     g_money = false, g_pvWarn = false;
string   g_ccy = "EUR", g_pvInfo = "";

//--- risultati
CellRes  g_cells[];
int      g_nCells = 0;
EvRes    g_ev[];
int      g_nEv = 0;
int      g_infoBars[], g_infoZ[];
double   g_infoAc[];
double   g_zB = 3.0;

int      g_fh = INVALID_HANDLE;
string   g_dg = "";

//+------------------------------------------------------------------+
//| Utilita'                                                          |
//+------------------------------------------------------------------+
string F0(const double v) { return DoubleToString(v, 0); }
string F1(const double v) { return DoubleToString(v, 1); }
string F2(const double v) { return DoubleToString(v, 2); }
string F3(const double v) { return DoubleToString(v, 3); }
string IS(const long v)   { return IntegerToString(v); }
string Sg(const double v, const int dg = 1) { return string(v > 0.0 ? "+" : "") + DoubleToString(v, dg); }

string HtmlEsc(const string src)
  {
   string o = src;
   StringReplace(o, "&", "&amp;");
   StringReplace(o, "<", "&lt;");
   StringReplace(o, ">", "&gt;");
   return o;
  }

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
   const double a = MathAbs(t);
   if(a >= g_zB) return (t > 0.0) ? "#a3be8c" : "#bf616a";
   if(a >= 1.96) return "#ebcb8b";
   return "#7b8794";
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

string LotTxt()
  {
   string t = DoubleToString(InpLotSize, 3);
   while(StringLen(t) > 4 && StringSubstr(t, StringLen(t) - 1, 1) == "0") t = StringSubstr(t, 0, StringLen(t) - 1);
   if(StringSubstr(t, StringLen(t) - 1, 1) == ".") t = StringSubstr(t, 0, StringLen(t) - 1);
   return t;
  }

double MnyV(const double pts) { return pts * g_pv * InpLotSize; }
string MnyU(const double pts) { return g_money ? (DoubleToString(MnyV(pts), 3) + " " + g_ccy) : string("n.d."); }

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
      bool dup = false;
      for(int q = 0; q < k; q++) if(MathAbs(out[q] - v) < 1.0e-9) { dup = true; break; }
      if(dup) continue;
      ArrayResize(out, k + 1);
      out[k] = v;
     }
   if(ArraySize(out) > 1) ArraySort(out);
   return ArraySize(out);
  }

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
     { for(int i = 0; i < 19; i++) AddTF(i); }
   else
     {
      string parts[];
      int np = StringSplit(s, ',', parts);
      for(int q = 0; q < np; q++)
        {
         string pp = parts[q];
         StringTrimLeft(pp); StringTrimRight(pp);
         bool known = false;
         for(int i = 0; i < 19; i++)
            if(g_allName[i] == pp) { AddTF(i); known = true; break; }
         if(!known && pp != "") Print("Timeframe sconosciuto in InpTFs: '", pp, "' (ignorato; W1 e MN1 non sono supportati).");
        }
     }
   g_nT = ArraySize(g_tf);
   ArrayResize(g_tfSec, g_nT);
   for(int t = 0; t < g_nT; t++) g_tfSec[t] = (long)PeriodSeconds(g_tf[t]);
   return (g_nT > 0);
  }

bool SetupInputs()
  {
   if(InpFrom >= InpTo) { Print("InpFrom deve precedere InpTo."); return false; }
   if(InpEntryLagMin < 0) { Print("InpEntryLagMin deve essere >= 0."); return false; }
   if(InpFlowN < 2 || InpFlowM < 50 || InpFlowDays < 3 || InpFlowMinSess < 1 || InpFlowMinSess > InpFlowDays)
     { Print("Parametri Flow non validi (N>=2, M>=50, D>=3, 1<=MinSess<=D)."); return false; }
   if(!ParseTFs()) { Print("Nessun timeframe valido in InpTFs"); return false; }
   g_nH = ParseIntList(InpHorizons, g_hor);
   if(g_nH < 1) { Print("Nessun orizzonte valido in InpHorizons"); return false; }
   g_nThr = ParseDoubleList(InpEventThr, g_thr);
   if(g_nThr < 1) { Print("Nessuna soglia valida in InpEventThr: uso 1.5"); ArrayResize(g_thr, 1); g_thr[0] = 1.5; g_nThr = 1; }
   if(g_nThr > MAXTHR) { g_nThr = MAXTHR; ArrayResize(g_thr, MAXTHR); }
   g_featName[0] = "Z_clv_pesato";
   g_featName[1] = "Z_clv_piatto";
   g_featName[2] = "Z_bvc_pesato";
   g_featName[3] = "Z_bvc_piatto";
   g_featName[4] = "assorbimento";
   g_featName[5] = "vecchio_delta";
   g_featName[6] = "momentum";
   g_featName[7] = "trend_EMA13";
   return true;
  }

//+------------------------------------------------------------------+
//| Caricamento storico (come SignalLab)                              |
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
      Print("!!! Il terminale espone solo ", maxb, " barre su ", sb, ". Opzioni > Grafici > Max barre = Illimitato, poi riavvia il terminale.");
   if(got < 1000) { Print("Storico M1 insufficiente (", got, ")."); return false; }
   g_n1 = got;
   ArrayResize(g_m1Time, g_n1);
   ArrayResize(g_m1Open, g_n1);
   ArrayResize(g_m1Close, g_n1);
   ArrayResize(g_m1Spr, g_n1);
   ArrayResize(g_m1Day, g_n1);
   ArrayResize(g_nextBrk, g_n1);
   g_day0 = (((long)g_r1[0].time) + g_off) / 86400L;
   for(int i = 0; i < g_n1; i++)
     {
      g_m1Time[i]  = g_r1[i].time;
      g_m1Open[i]  = g_r1[i].open;
      g_m1Close[i] = g_r1[i].close;
      g_m1Spr[i]   = g_r1[i].spread;
      g_m1Day[i]   = (int)((((long)g_r1[i].time + g_off) / 86400L) - g_day0);
     }
   g_nDays = g_m1Day[g_n1 - 1] + 1;
   if(g_nDays < 1) g_nDays = 1;
   g_tStart = g_m1Time[g_n1 - 1];
   for(int i = 0; i < g_n1; i++)
      if(g_m1Time[i] >= InpFrom) { g_tStart = g_m1Time[i]; break; }
   g_histWarn = ((long)g_tStart > (long)InpFrom + 7L * 86400L);
   Print("Storico M1 dal ", TimeToString(g_m1Time[0], TIME_DATE | TIME_MINUTES), " al ",
         TimeToString(g_m1Time[g_n1 - 1], TIME_DATE | TIME_MINUTES), " | inizio effettivo del periodo ", TimeToString(g_tStart, TIME_DATE));
   if(g_histWarn)
      Print("!!! Lo storico M1 disponibile inizia dopo InpFrom: il periodo analizzato e' piu' corto di quello richiesto.");
   //--- buchi di dati: nextBrk[j] = primo k >= j con un buco dopo k (altrimenti l'ultimo indice)
   const long gmax = (long)InpMaxGapMin * 60L;
   int nb = g_n1 - 1;
   g_nextBrk[g_n1 - 1] = g_n1 - 1;
   for(int j = g_n1 - 2; j >= 0; j--)
     {
      if((long)(g_m1Time[j + 1] - g_m1Time[j]) > gmax) nb = j;
      g_nextBrk[j] = nb;
     }
   //--- contesto: spread M1 mediano e quota di spread nullo nel periodo
   int stride = MathMax(1, g_n1 / 200000);
   double sp[];
   ArrayResize(sp, g_n1 / stride + 1);
   int cnt = 0, zero = 0;
   for(int i = 0; i < g_n1; i += stride)
     {
      if(g_m1Time[i] < InpFrom || g_m1Time[i] > InpTo) continue;
      sp[cnt] = (double)g_m1Spr[i];
      if(g_m1Spr[i] == 0) zero++;
      cnt++;
     }
   if(cnt > 0)
     {
      ArrayResize(sp, cnt);
      ArraySort(sp);
      g_medSpr = sp[cnt / 2];
      g_zeroSprPct = 100.0 * zero / cnt;
     }
   //--- primo giorno out-of-sample
   int dFrom = (int)((((long)g_tStart + g_off) / 86400L) - g_day0);
   if(dFrom < 0) dFrom = 0;
   int pct = MathMin(95, MathMax(5, InpSplitPct));
   g_splitDay = dFrom + (int)((double)(g_nDays - dFrom) * pct / 100.0);
   Print("Split IS/OOS: giorni ", dFrom, "-", g_nDays - 1, " | OOS dal giorno ", g_splitDay, " (", pct, "% in-sample)");
   return true;
  }

//+------------------------------------------------------------------+
//| Valore del punto e commissione (identico a SignalLab)             |
//+------------------------------------------------------------------+
double PvTickValue(const string name)
  {
   for(int w = 0; w < 10; w++)
     {
      double tv = SymbolInfoDouble(name, SYMBOL_TRADE_TICK_VALUE_PROFIT);
      if(tv <= 0.0) tv = SymbolInfoDouble(name, SYMBOL_TRADE_TICK_VALUE);
      if(tv > 0.0) return tv;
      Sleep(100);
     }
   return 0.0;
  }

string PvCandidates()
  {
   const string base = StringSubstr(_Symbol, 0, 6);
   string out = "";
   int found = 0;
   const int n = SymbolsTotal(false);
   for(int i = 0; i < n && found < 8; i++)
     {
      const string nm = SymbolName(i, false);
      if(StringFind(nm, base) < 0 || nm == _Symbol) continue;
      out += string(found > 0 ? ", " : "") + nm;
      found++;
     }
   return out;
  }

void PvAdd(string &arr[], const string v)
  {
   if(v == "") return;
   for(int i = 0; i < ArraySize(arr); i++) if(arr[i] == v) return;
   const int k = ArraySize(arr);
   ArrayResize(arr, k + 1);
   arr[k] = v;
  }

string PvCleanName(const string name)
  {
   string clean = name;
   if(StringLen(clean) > 4 && StringSubstr(clean, StringLen(clean) - 4) == "_QDM") clean = StringSubstr(clean, 0, StringLen(clean) - 4);
   return clean;
  }

int PvReal(const string key, string &out[])
  {
   ArrayResize(out, 0);
   if(StringLen(key) < 6) return 0;
   const int n = SymbolsTotal(false);
   for(int i = 0; i < n && ArraySize(out) < 8; i++)
     {
      const string nm = SymbolName(i, false);
      if(StringLen(nm) < 6 || StringSubstr(nm, 0, 6) != key || nm == _Symbol) continue;
      if(SymbolInfoInteger(nm, SYMBOL_CUSTOM) != 0) continue;
      PvAdd(out, nm);
     }
   return ArraySize(out);
  }

double PvBid(const string name)
  {
   if(!SymbolSelect(name, true)) return 0.0;
   for(int w = 0; w < 10; w++)
     {
      const double b = SymbolInfoDouble(name, SYMBOL_BID);
      if(b > 0.0) return b;
      Sleep(100);
     }
   return 0.0;
  }

double PvPairRate(const string a, const string b, const string sfx, string &src)
  {
   src = "";
   if(a == b) return 1.0;
   for(int dr = 0; dr < 2; dr++)
     {
      const string k = (dr == 0) ? (a + b) : (b + a);
      string cand[];
      ArrayResize(cand, 0);
      PvAdd(cand, k + sfx);
      PvAdd(cand, k);
      string real[];
      const int nr = PvReal(k, real);
      for(int q = 0; q < nr; q++) PvAdd(cand, real[q]);
      for(int c = 0; c < ArraySize(cand); c++)
        {
         const double bid = PvBid(cand[c]);
         if(bid <= 0.0) continue;
         src = cand[c] + " = " + DoubleToString(bid, 5);
         return (dr == 0) ? bid : 1.0 / bid;
        }
     }
   return 0.0;
  }

double PvRate(const string acc, const string pc, const string sfx, string &src)
  {
   double r = PvPairRate(acc, pc, sfx, src);
   if(r > 0.0) return r;
   if(acc != "USD" && pc != "USD")
     {
      string s1, s2;
      const double r1 = PvPairRate(acc, "USD", sfx, s1);
      const double r2 = PvPairRate("USD", pc, sfx, s2);
      if(r1 > 0.0 && r2 > 0.0)
        {
         src = s1 + " e " + s2;
         return r1 * r2;
        }
     }
   src = "";
   return 0.0;
  }

bool PvIsFxKey(const string key)
  {
   const string cur = "USD,EUR,GBP,JPY,CHF,CAD,AUD,NZD,SEK,NOK,DKK,PLN,CZK,HUF,TRY,ZAR,MXN,SGD,HKD,CNH";
   if(StringLen(key) != 6) return false;
   return (StringFind(cur, StringSubstr(key, 0, 3)) >= 0 && StringFind(cur, StringSubstr(key, 3, 3)) >= 0);
  }

void SetupMoney()
  {
   g_ccy = AccountInfoString(ACCOUNT_CURRENCY);
   if(g_ccy == "") g_ccy = "EUR";
   g_pv = 0.0;
   g_commPts = 0.0;
   g_pvInfo = "";
   g_pvWarn = false;
   const bool custom = (SymbolInfoInteger(_Symbol, SYMBOL_CUSTOM) != 0);
   const string clean = PvCleanName(_Symbol);
   const string key = (StringLen(clean) >= 6) ? StringSubstr(clean, 0, 6) : clean;
   const string sfx = (StringLen(clean) > 6) ? StringSubstr(clean, 6) : "";
   string pcOwn = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   StringToUpper(pcOwn);
   if(InpPointValuePerLot > 0.0)
     {
      g_pv = InpPointValuePerLot;
      g_pvInfo = "valore del punto impostato a mano";
     }
   else
     {
      //--- 1) valore del tick letto da un simbolo reale
      string cand[];
      ArrayResize(cand, 0);
      if(InpPointValueSymbol != "") PvAdd(cand, InpPointValueSymbol);
      if(!custom || (pcOwn != "" && pcOwn == g_ccy)) PvAdd(cand, _Symbol);
      PvAdd(cand, clean);
      string real[];
      const int nr = PvReal(key, real);
      for(int q = 0; q < nr; q++) PvAdd(cand, real[q]);
      double csReal = 0.0;
      string pcReal = "";
      for(int c = 0; c < ArraySize(cand) && g_pv <= 0.0; c++)
        {
         const string src = cand[c];
         if(!SymbolSelect(src, true))
           {
            if(src == InpPointValueSymbol) g_pvInfo = "il simbolo '" + src + "' non esiste nel terminale (controlla il nome con Ctrl+U); ";
            continue;
           }
         if(SymbolInfoInteger(src, SYMBOL_CUSTOM) != 0 && src != InpPointValueSymbol && !(src == _Symbol && pcOwn != "" && pcOwn == g_ccy)) continue;
         const double cs0 = SymbolInfoDouble(src, SYMBOL_TRADE_CONTRACT_SIZE);
         string pc0 = SymbolInfoString(src, SYMBOL_CURRENCY_PROFIT);
         StringToUpper(pc0);
         if(csReal <= 0.0 && cs0 > 0.0) csReal = cs0;
         if(pcReal == "" && pc0 != "") pcReal = pc0;
         const double tv = PvTickValue(src);
         const double ts = SymbolInfoDouble(src, SYMBOL_TRADE_TICK_SIZE);
         if(tv > 0.0 && ts > 0.0)
           {
            g_pv = tv / ts * g_pt;
            g_pvInfo += string(src == _Symbol ? "valore letto dal simbolo " : "valore letto dal simbolo reale ") + src + ": valore del tick " + DoubleToString(tv, 5) + " " + g_ccy;
           }
        }
      //--- 2) dal cambio
      if(g_pv <= 0.0)
        {
         double cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         if(cs <= 0.0) cs = csReal;
         bool csGuess = false;
         if(cs <= 0.0 && PvIsFxKey(key)) { cs = 100000.0; csGuess = true; }
         string pc = (pcOwn != "") ? pcOwn : pcReal;
         if(pc == "" && PvIsFxKey(key)) pc = StringSubstr(key, 3, 3);
         if(cs > 0.0 && pc != "")
           {
            string rsrc = "";
            double rate = PvRate(g_ccy, pc, sfx, rsrc);
            if(rate <= 0.0 && g_n1 > 0 && g_m1Close[g_n1 - 1] > 0.0 && StringLen(key) == 6)
              {
               if(key == g_ccy + pc) { rate = g_m1Close[g_n1 - 1]; rsrc = "ultimo prezzo di " + key + " nello storico = " + DoubleToString(rate, 5); }
              }
            if(rate > 0.0)
              {
               g_pv = cs * g_pt / rate;
               g_pvInfo += "valore calcolato: contratto " + F0(cs) + string(csGuess ? " (ipotizzato)" : "") + " x " + DoubleToString(g_pt, _Digits) + " " + pc + string(pc == g_ccy ? "" : (", convertito in " + g_ccy + " con il cambio " + rsrc));
               if(csGuess) g_pvWarn = true;
              }
           }
        }
      //--- 3) valore del tick del simbolo analizzato anche se personalizzato (non verificabile)
      if(g_pv <= 0.0)
        {
         const double tv = PvTickValue(_Symbol);
         const double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tv > 0.0 && ts > 0.0)
           {
            g_pv = tv / ts * g_pt;
            g_pvWarn = true;
            g_pvInfo += "ATTENZIONE: valore del tick del simbolo personalizzato " + _Symbol + " (" + DoubleToString(tv, 5) + " " + g_ccy + ") non verificabile con un simbolo reale";
           }
        }
      //--- 4) ultima ipotesi
      if(g_pv <= 0.0)
        {
         double cs = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         if(cs <= 0.0) cs = csReal;
         if(cs <= 0.0) cs = PvIsFxKey(key) ? 100000.0 : 1.0;
         g_pv = cs * g_pt;
         g_pvWarn = true;
         g_pvInfo += "ATTENZIONE: valore stimato con contratto " + F0(cs) + " x punto " + DoubleToString(g_pt, _Digits) + " ipotizzando che la valuta di profitto sia " + g_ccy;
        }
      if(g_pvWarn)
        {
         const string cd = PvCandidates();
         if(cd != "") g_pvInfo += ". Simboli simili nel terminale: " + cd + " (puoi indicarne uno in InpPointValueSymbol)";
        }
     }
   g_money = (g_pv > 0.0 && InpLotSize > 0.0);
   if(g_pv > 0.0 && InpCommissionPerLotSide > 0.0) g_commPts = 2.0 * InpCommissionPerLotSide / g_pv;
   g_extraPts = InpExtraCostPts + g_commPts;
   Print("Denaro: 1 punto per 1.00 lotto = ", DoubleToString(g_pv, 4), " ", g_ccy, " (", g_pvInfo, ") | commissione ",
         DoubleToString(InpCommissionPerLotSide, 2), " per lato e per lotto = ", DoubleToString(g_commPts, 2), " pt a/r (sempre inclusa nel costo)");
  }

//+------------------------------------------------------------------+
//| Flow Z: identico a SyntheticDelta_v3.x / SD_CoreFlow.mqh          |
//+------------------------------------------------------------------+
double SD_ErfAS(const double x)
  {
   const double p  = 0.3275911;
   const double a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741;
   const double a4 = -1.453152027, a5 = 1.061405429;
   double s  = (x < 0.0) ? -1.0 : 1.0;
   double ax = MathAbs(x);
   double t  = 1.0 / (1.0 + p * ax);
   return s * (1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * MathExp(-ax * ax));
  }

double SD_NormCdf(const double z)
  {
   return 0.5 * (1.0 + SD_ErfAS(z / 1.4142135623730951));
  }

double SD_FlowMedian(const double &hist[], const int base, const int n, double &tmp[])
  {
   for(int k = 0; k < n; k++)
     {
      double v = hist[base + k];
      int m = k - 1;
      while(m >= 0 && tmp[m] > v)
        {
         tmp[m + 1] = tmp[m];
         m--;
        }
      tmp[m + 1] = v;
     }
   if((n & 1) == 1)
      return tmp[n / 2];
   return 0.5 * (tmp[n / 2 - 1] + tmp[n / 2]);
  }

void SD_FlowSeries(const MqlRates &r[], const int n, const SDFlowParams &p, const int periodSec,
                   double &z[], double &ab[])
  {
   ArrayResize(z, n);
   ArrayInitialize(z, EMPTY_VALUE);
   ArrayResize(ab, n);
   ArrayInitialize(ab, EMPTY_VALUE);
   const int N     = MathMax(2, p.flowBars);
   const int M     = MathMax(50, p.zWindow);
   const int D     = MathMax(3, p.seasonDays);
   const int atrP  = MathMax(2, p.atrPeriod);
   const int bvcB  = MathMax(5, p.bvcBars);
   const int first = MathMax(MathMax(atrP, bvcB), N) + 2;
   const int slots = MathMax(1, 86400 / MathMax(1, periodSec));
   if(n < first + 2)
      return;

   double hist[], tmp[], wv[], fb[], cF[], cF2[], cFn[], cA[], cA2[], cAn[];
   int    cnt[], head[];
   ArrayResize(hist, slots * D);
   ArrayResize(tmp, D);
   ArrayResize(cnt, slots);
   ArrayResize(head, slots);
   ArrayInitialize(cnt, 0);
   ArrayInitialize(head, 0);
   ArrayResize(wv, n);
   ArrayResize(fb, n);
   ArrayResize(cF, n);
   ArrayResize(cF2, n);
   ArrayResize(cFn, n);
   ArrayResize(cA, n);
   ArrayResize(cA2, n);
   ArrayResize(cAn, n);

   for(int i = 0; i < n; i++)
     {
      cF[i]  = (i > 0) ? cF[i - 1]  : 0.0;
      cF2[i] = (i > 0) ? cF2[i - 1] : 0.0;
      cFn[i] = (i > 0) ? cFn[i - 1] : 0.0;
      cA[i]  = (i > 0) ? cA[i - 1]  : 0.0;
      cA2[i] = (i > 0) ? cA2[i - 1] : 0.0;
      cAn[i] = (i > 0) ? cAn[i - 1] : 0.0;
      wv[i]  = -1.0;
      fb[i]  = 0.0;

      int slot = (int)(((long)r[i].time % 86400) / periodSec);
      if(slot >= slots) slot = slots - 1;
      if(slot < 0)      slot = 0;
      const double vol = (double)r[i].tick_volume;

      if(i >= first && i < n - 1)
        {
         double w = -1.0;
         if(cnt[slot] >= p.minSessions)
           {
            double med = SD_FlowMedian(hist, slot * D, cnt[slot], tmp);
            if(med > 0.0)
               w = MathMin(vol / med, p.weightCap);
           }
         if(w >= 0.0)
           {
            if(!p.useWeights)
               w = 1.0;
            const double range = r[i].high - r[i].low;
            double dir = 0.0;
            if(p.flowMode == 0)
               dir = (range > 0.0) ? ((r[i].close - r[i].low) - (r[i].high - r[i].close)) / range : 0.0;
            else
              {
               double s2 = 0.0;
               for(int j = i - bvcB + 1; j <= i; j++)
                 {
                  double dd = r[j].close - r[j - 1].close;
                  s2 += dd * dd;
                 }
               double sg = MathSqrt(s2 / bvcB);
               dir = (sg > 0.0) ? 2.0 * SD_NormCdf((r[i].close - r[i - 1].close) / sg) - 1.0 : 0.0;
              }
            wv[i] = w;
            fb[i] = w * dir;
            double sf = 0.0, sw = 0.0;
            bool   full = true;
            for(int k = 0; k < N; k++)
              {
               int j = i - k;
               if(wv[j] < 0.0)
                 {
                  full = false;
                  break;
                 }
               sf += fb[j];
               sw += wv[j];
              }
            if(full && sw > 0.0)
              {
               const double F      = sf / sw;
               const double effort = sw / N;
               const int hi = i - 1;
               const int lo = hi - M;
               double s1 = cF[hi]  - ((lo >= 0) ? cF[lo]  : 0.0);
               double s2 = cF2[hi] - ((lo >= 0) ? cF2[lo] : 0.0);
               double nn = cFn[hi] - ((lo >= 0) ? cFn[lo] : 0.0);
               if(nn >= 0.5 * M)
                 {
                  double mu = s1 / nn;
                  double vr = s2 / nn - mu * mu;
                  if(vr > 1e-12)
                     z[i] = (F - mu) / MathSqrt(vr);
                 }
               cF[i]  += F;
               cF2[i] += F * F;
               cFn[i] += 1.0;
               double sTR = 0.0;
               for(int j = i - atrP + 1; j <= i; j++)
                  sTR += MathMax(r[j].high, r[j - 1].close) - MathMin(r[j].low, r[j - 1].close);
               double atr = sTR / atrP;
               if(atr > 0.0)
                 {
                  double res = MathAbs(r[i].close - r[i - N].close) / (atr * MathSqrt((double)N));
                  double A   = MathLog(MathMax(effort, 0.05)) - MathLog(res + 0.1);
                  double a1  = cA[hi]  - ((lo >= 0) ? cA[lo]  : 0.0);
                  double a2  = cA2[hi] - ((lo >= 0) ? cA2[lo] : 0.0);
                  double an  = cAn[hi] - ((lo >= 0) ? cAn[lo] : 0.0);
                  if(an >= 0.5 * M)
                    {
                     double mu = a1 / an;
                     double vr = a2 / an - mu * mu;
                     if(vr > 1e-12)
                        ab[i] = (A - mu) / MathSqrt(vr);
                    }
                  cA[i]  += A;
                  cA2[i] += A * A;
                  cAn[i] += 1.0;
                 }
              }
           }
        }
      if(i < n - 1)
        {
         int h = head[slot];
         hist[slot * D + h] = vol;
         head[slot] = (h + 1) % D;
         if(cnt[slot] < D)
            cnt[slot]++;
        }
     }
  }

//+------------------------------------------------------------------+
//| Riferimenti: ATR, EMA, z-score mobile, vecchio delta, momentum    |
//+------------------------------------------------------------------+
void FL_Atr(const MqlRates &r[], const int n, const int p, double &atr[])
  {
   ArrayResize(atr, n);
   ArrayInitialize(atr, EMPTY_VALUE);
   if(n <= p + 1) return;
   double cs[];
   ArrayResize(cs, n + 1);
   cs[0] = 0.0;
   for(int i = 0; i < n; i++)
     {
      double tr = (i > 0) ? MathMax(r[i].high, r[i - 1].close) - MathMin(r[i].low, r[i - 1].close) : 0.0;
      cs[i + 1] = cs[i] + tr;
     }
   for(int i = p; i < n; i++)
     {
      double a = (cs[i + 1] - cs[i + 1 - p]) / p;
      if(a > 0.0) atr[i] = a;
     }
  }

void FL_Ema(const MqlRates &r[], const int n, const int period, double &ema[])
  {
   ArrayResize(ema, n);
   if(n <= 0) return;
   const double a = 2.0 / (period + 1.0);
   ema[0] = r[0].close;
   for(int i = 1; i < n; i++)
      ema[i] = ema[i - 1] + a * (r[i].close - ema[i - 1]);
  }

//--- z-score di x rispetto alle M barre PRECEDENTI (corrente esclusa), come RollZ dell'indicatore
void FL_RollZ(const double &x[], const int n, const int M, double &out[])
  {
   ArrayResize(out, n);
   ArrayInitialize(out, EMPTY_VALUE);
   double cs[], cs2[], cn[];
   ArrayResize(cs, n + 1);
   ArrayResize(cs2, n + 1);
   ArrayResize(cn, n + 1);
   cs[0] = 0.0; cs2[0] = 0.0; cn[0] = 0.0;
   for(int i = 0; i < n; i++)
     {
      const bool ok = (x[i] != EMPTY_VALUE && MathIsValidNumber(x[i]));
      const double v = ok ? x[i] : 0.0;
      cs[i + 1]  = cs[i] + v;
      cs2[i + 1] = cs2[i] + v * v;
      cn[i + 1]  = cn[i] + (ok ? 1.0 : 0.0);
     }
   for(int i = 1; i < n; i++)
     {
      if(x[i] == EMPTY_VALUE || !MathIsValidNumber(x[i])) continue;
      const int lo = MathMax(0, i - M);
      const double c = cn[i] - cn[lo];
      if(c < 0.5 * M) continue;
      const double mu = (cs[i] - cs[lo]) / c;
      const double vr = (cs2[i] - cs2[lo]) / c - mu * mu;
      if(vr <= 1e-12) continue;
      out[i] = (x[i] - mu) / MathSqrt(vr);
     }
  }

//--- normalizedDelta del vecchio indicatore / dell'EA (SD_Core.mqh), senza soglia
void FL_Legacy(const MqlRates &r[], const int n, double &out[])
  {
   ArrayResize(out, n);
   ArrayInitialize(out, EMPTY_VALUE);
   const int emaP = 13, volP = 20, atrP = 14;
   const int warm = MathMax(MathMax(emaP, volP), MathMax(atrP, atrP)) + 3;
   double ema[];
   FL_Ema(r, n, emaP, ema);
   double vsum = 0.0;
   for(int i = 0; i < n; i++)
     {
      vsum += (double)r[i].tick_volume;
      if(i >= volP) vsum -= (double)r[i - volP].tick_volume;
      if(i < warm) continue;
      const double range = r[i].high - r[i].low;
      const double tv = (double)r[i].tick_volume;
      if(range <= 0.0 || tv <= 0.0 || i < atrP) continue;
      const double fracBuy  = (r[i].close - r[i].low) / range;
      const double fracSell = (r[i].high - r[i].close) / range;
      const double bulls    = (r[i].high - ema[i]) / range;
      const double bears    = (ema[i] - r[i].low) / range;
      const int cnt = MathMin(i + 1, volP);
      const double va = (cnt > 0) ? vsum / cnt : tv;
      const double vw = (va > 0.0) ? MathMin(tv / va, 3.0) : 1.0;
      out[i] = (fracBuy * (1.0 + bulls) * vw - fracSell * (1.0 + bears) * vw) / 6.0;
     }
  }

//+------------------------------------------------------------------+
//| Mappa barra del TF -> barra M1 d'ingresso (come SignalLab)        |
//+------------------------------------------------------------------+
void FL_Entries(const int t, const MqlRates &r[], const int n, int &ent[])
  {
   ArrayResize(ent, n);
   ArrayInitialize(ent, -1);
   const long xs     = g_tfSec[t];
   const long maxGap = (long)InpMaxEntryGapMin * 60L;
   int p = 0;
   for(int i = 0; i < n - 1; i++)
     {
      const datetime tNext = r[i + 1].time;
      if(tNext < InpFrom || tNext > InpTo) continue;
      const long spacing = (long)(tNext - r[i].time);
      if((spacing - xs) > maxGap) continue;
      while(p < g_n1 && g_m1Time[p] < tNext) p++;
      if(p >= g_n1) break;
      if((long)(g_m1Time[p] - tNext) > maxGap) continue;
      ent[i] = p;
     }
  }

//--- prezzo di chiusura a H minuti dall'ingresso su ogni barra M1 (finestra basata sul TEMPO, stesse regole di SignalLab)
void FL_FwdClose(const int hMin)
  {
   const long Hs = (long)hMin * 60L;
   int e = 0;
   for(int j = 0; j < g_n1; j++)
     {
      const long tEnd = (long)g_m1Time[j] + Hs;
      while(e < g_n1 && (long)g_m1Time[e] < tEnd) e++;
      const bool ok = (e < g_n1 && e > j && (g_nextBrk[j] >= e || (g_nextBrk[j] == e - 1 && (long)g_m1Time[e - 1] + 60L >= tEnd)));
      g_okF[j] = ok ? (uchar)1 : (uchar)0;
      if(ok) g_fCl[j] = g_m1Close[e - 1];
     }
  }

//--- rendimento futuro (punti), costo, giorno e periodo di ogni barra del TF
void FL_BuildY(const int n, const int hMin, const int &ent[], double &yv[], double &cv[], int &dv[], uchar &sm[])
  {
   //--- cluster = blocco di giorni lungo almeno 3 volte l'orizzonte: finestre sovrapposte non sono indipendenti fra giorni vicini
   //--- (simulazione: con cluster di 1 giorno e orizzonte 1440m i falsi positivi al 5% salgono all'8%, con 3 giorni tornano al 5.5%)
   const int blk = MathMax(MathMax(1, InpClusterDays), (3 * hMin + 1439) / 1440);
   for(int i = 0; i < n; i++)
     {
      yv[i] = EMPTY_VALUE; cv[i] = 0.0; dv[i] = 0; sm[i] = 0;
      const int p0 = ent[i];
      if(p0 < 0) continue;
      int j = p0;
      if(InpEntryLagMin > 0)
        {
         j = p0 + InpEntryLagMin;
         if(j >= g_n1 || (long)(g_m1Time[j] - g_m1Time[p0]) != (long)InpEntryLagMin * 60L) continue;
        }
      if(g_okF[j] == 0) continue;
      yv[i] = (g_fCl[j] - g_m1Open[j]) / g_pt;
      cv[i] = ((InpCostPoints > 0.0) ? InpCostPoints : (double)g_m1Spr[j]) + g_extraPts;
      dv[i] = g_m1Day[j] / blk;
      sm[i] = (g_m1Day[j] >= g_splitDay) ? (uchar)1 : (uchar)0;
     }
  }

//+------------------------------------------------------------------+
//| Regressione continua del rendimento su una feature: pendenza, IC   |
//| e t con errore standard raggruppato per giorno, su tutto il        |
//| periodo (ra), in-sample (ri) e fuori campione (ro). Due passate:   |
//| la seconda ha bisogno di pendenza e medie della prima.             |
//+------------------------------------------------------------------+
void FL_Reg(const double &F[], const int off, const int n, const double &yv[], const int &dv[], const uchar &sm[],
            RegRes &ra, RegRes &ri, RegRes &ro)
  {
   double sn[3], sx[3], sy[3], sxx[3], sxy[3], syy[3];
   for(int k = 0; k < 3; k++) { sn[k] = 0.0; sx[k] = 0.0; sy[k] = 0.0; sxx[k] = 0.0; sxy[k] = 0.0; syy[k] = 0.0; }
   for(int i = 0; i < n; i++)
     {
      const double x = F[off + i];
      const double y = yv[i];
      if(x == EMPTY_VALUE || y == EMPTY_VALUE) continue;
      const int s = 1 + (int)sm[i];
      sn[0] += 1.0; sx[0] += x; sy[0] += y; sxx[0] += x * x; sxy[0] += x * y; syy[0] += y * y;
      sn[s] += 1.0; sx[s] += x; sy[s] += y; sxx[s] += x * x; sxy[s] += x * y; syy[s] += y * y;
     }
   double xb[3], yb[3], sxxc[3], sxyc[3], syyc[3], beta[3];
   bool ok[3];
   for(int k = 0; k < 3; k++)
     {
      ok[k] = (sn[k] >= 20.0);
      xb[k] = 0.0; yb[k] = 0.0; sxxc[k] = 0.0; sxyc[k] = 0.0; syyc[k] = 0.0; beta[k] = 0.0;
      if(!ok[k]) continue;
      xb[k] = sx[k] / sn[k];
      yb[k] = sy[k] / sn[k];
      sxxc[k] = sxx[k] - sn[k] * xb[k] * xb[k];
      sxyc[k] = sxy[k] - sn[k] * xb[k] * yb[k];
      syyc[k] = syy[k] - sn[k] * yb[k] * yb[k];
      if(sxxc[k] <= 1.0e-18 || syyc[k] <= 1.0e-18) { ok[k] = false; continue; }
      beta[k] = sxyc[k] / sxxc[k];
     }
   double curS[3], ssq[3];
   int    curD[3];
   for(int k = 0; k < 3; k++) { curS[k] = 0.0; ssq[k] = 0.0; curD[k] = -1; }
   for(int i = 0; i < n; i++)
     {
      const double x = F[off + i];
      const double y = yv[i];
      if(x == EMPTY_VALUE || y == EMPTY_VALUE) continue;
      const int s = 1 + (int)sm[i];
      for(int q = 0; q < 2; q++)
        {
         const int k = (q == 0) ? 0 : s;
         if(!ok[k]) continue;
         const double xc = x - xb[k];
         const double yc = y - yb[k];
         if(dv[i] != curD[k])
           {
            ssq[k] += curS[k] * curS[k];
            curS[k] = 0.0;
            curD[k] = dv[i];
           }
         curS[k] += xc * (yc - beta[k] * xc);
        }
     }
   for(int k = 0; k < 3; k++) ssq[k] += curS[k] * curS[k];
   RegRes rr[3];
   for(int k = 0; k < 3; k++)
     {
      rr[k].n = 0.0; rr[k].beta = 0.0; rr[k].t = 0.0; rr[k].ic = 0.0; rr[k].icse = 0.0;
      if(!ok[k]) continue;
      const double se = MathSqrt(ssq[k]) / sxxc[k];
      rr[k].n    = sn[k];
      rr[k].beta = beta[k] * MathSqrt(sxxc[k] / sn[k]);        // punti per 1 dev.std della feature
      rr[k].t    = (se > 0.0) ? beta[k] / se : 0.0;
      rr[k].ic   = sxyc[k] / MathSqrt(sxxc[k] * syyc[k]);
      rr[k].icse = se * MathSqrt(sxxc[k] / syyc[k]);
     }
   ra = rr[0]; ri = rr[1]; ro = rr[2];
  }

//--- IC con la feature spostata di k barre (circolare): per il placebo
double FL_IcShift(const double &F[], const int off, const int n, const double &yv[], const int k)
  {
   double sn = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0;
   for(int i = 0; i < n; i++)
     {
      int j = i - k;
      if(j < 0) j += n;
      const double x = F[off + j];
      const double y = yv[i];
      if(x == EMPTY_VALUE || y == EMPTY_VALUE) continue;
      sn += 1.0; sx += x; sy += y; sxx += x * x; sxy += x * y; syy += y * y;
     }
   if(sn < 20.0) return 0.0;
   const double cxx = sxx - sx * sx / sn, cyy = syy - sy * sy / sn, cxy = sxy - sx * sy / sn;
   if(cxx <= 1.0e-18 || cyy <= 1.0e-18) return 0.0;
   return cxy / MathSqrt(cxx * cyy);
  }

//--- p-value empirico: quota di spostamenti di giorni interi con |IC| almeno pari a quello osservato
double FL_PlaceboP(const double &F[], const int off, const int n, const double &yv[], const int bpd, const double icObs, const int B)
  {
   const int maxk = n / bpd - 2;
   if(maxk < 5) return -1.0;
   int ge = 0, draws = 0;
   for(int b = 0; b < B && !IsStopped(); b++)
     {
      g_seed ^= (g_seed << 13); g_seed ^= (g_seed >> 7); g_seed ^= (g_seed << 17);
      const int kk = 2 + (int)(g_seed % (ulong)(maxk - 2));
      const double ic = FL_IcShift(F, off, n, yv, kk * bpd);
      draws++;
      if(MathAbs(ic) >= MathAbs(icObs)) ge++;
     }
   if(draws < 20) return -1.0;
   return (1.0 + (double)ge) / ((double)draws + 1.0);
  }

//+------------------------------------------------------------------+
//| Accumulo con errore standard raggruppato per giorno (in streaming) |
//+------------------------------------------------------------------+
void CluInit(Clu &c)
  {
   c.n = 0.0; c.sum = 0.0; c.A = 0.0; c.B = 0.0; c.C = 0.0; c.cs = 0.0; c.cn = 0.0; c.day = -1;
  }

void CluAdd(Clu &c, const int day, const double v)
  {
   if(day != c.day)
     {
      if(c.cn > 0.0) { c.A += c.cs * c.cs; c.B += c.cs * c.cn; c.C += c.cn * c.cn; }
      c.cs = 0.0; c.cn = 0.0; c.day = day;
     }
   c.cs += v; c.cn += 1.0; c.n += 1.0; c.sum += v;
  }

void CluEnd(Clu &c)
  {
   if(c.cn > 0.0) { c.A += c.cs * c.cs; c.B += c.cs * c.cn; c.C += c.cn * c.cn; }
   c.cs = 0.0; c.cn = 0.0;
  }

double CluT(const Clu &c)
  {
   if(c.n < 3.0) return 0.0;
   const double mu = c.sum / c.n;
   const double v = c.A - 2.0 * mu * c.B + mu * mu * c.C;
   if(v <= 0.0) return 0.0;
   const double se = MathSqrt(v) / c.n;
   return (se > 0.0) ? mu / se : 0.0;
  }

//+------------------------------------------------------------------+
//| Elaborazione di un TF                                             |
//+------------------------------------------------------------------+
void ProcessTF(const int t, const MqlRates &r[], const int n)
  {
   if(n < 600) { Print("TF ", g_tfName[t], ": storico insufficiente (", n, " barre), saltato."); return; }
   const int xs = (int)g_tfSec[t];
   int bpd = (int)(86400L / g_tfSec[t]);
   if(bpd < 1) bpd = 1;
   int ent[];
   FL_Entries(t, r, n, ent);

   const int k0 = g_nCells;

   //--- feature
   SDFlowParams p;
   p.flowMode = 0; p.flowBars = InpFlowN; p.zWindow = InpFlowM; p.threshold = 0.0; p.seasonDays = InpFlowDays;
   p.minSessions = InpFlowMinSess; p.weightCap = 3.0; p.atrPeriod = 14; p.bvcBars = 50; p.useWeights = true; p.runGapBars = 0;
   double zA[], zB[], zC[], zD[], ab[], dum[];
   SD_FlowSeries(r, n, p, xs, zA, ab);
   p.useWeights = false;
   SD_FlowSeries(r, n, p, xs, zB, dum);
   p.flowMode = 1; p.useWeights = true;
   SD_FlowSeries(r, n, p, xs, zC, dum);
   p.useWeights = false;
   SD_FlowSeries(r, n, p, xs, zD, dum);
   double leg[], atr[], ema[], raw[], mom[], trd[];
   FL_Legacy(r, n, leg);
   FL_Atr(r, n, 14, atr);
   FL_Ema(r, n, 13, ema);
   ArrayResize(raw, n);
   ArrayInitialize(raw, EMPTY_VALUE);
   for(int i = InpFlowN; i < n; i++)
      if(atr[i] != EMPTY_VALUE) raw[i] = (r[i].close - r[i - InpFlowN].close) / (atr[i] * MathSqrt((double)InpFlowN));
   FL_RollZ(raw, n, InpFlowM, mom);
   for(int i = 0; i < n; i++)
      raw[i] = (atr[i] != EMPTY_VALUE) ? (r[i].close - ema[i]) / atr[i] : EMPTY_VALUE;
   FL_RollZ(raw, n, InpFlowM, trd);
   ArrayResize(g_F, NFEAT * n);
   for(int i = 0; i < n; i++)
     {
      g_F[0 * n + i] = zA[i];
      g_F[1 * n + i] = zB[i];
      g_F[2 * n + i] = zC[i];
      g_F[3 * n + i] = zD[i];
      g_F[4 * n + i] = ab[i];
      g_F[5 * n + i] = leg[i];
      g_F[6 * n + i] = mom[i];
      g_F[7 * n + i] = trd[i];
     }

   //--- informazioni sul TF: barre, Z validi, autocorrelazione a ritardo 1
   int zv = 0;
   double sn = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, syy = 0.0;
   for(int i = 0; i < n; i++)
     {
      if(zA[i] == EMPTY_VALUE) continue;
      zv++;
      if(i > 0 && zA[i - 1] != EMPTY_VALUE)
        {
         const double a = zA[i - 1], b = zA[i];
         sn += 1.0; sx += a; sy += b; sxx += a * a; sxy += a * b; syy += b * b;
        }
     }
   double ac1 = 0.0;
   if(sn > 20.0)
     {
      const double cxx = sxx - sx * sx / sn, cyy = syy - sy * sy / sn, cxy = sxy - sx * sy / sn;
      if(cxx > 0.0 && cyy > 0.0) ac1 = cxy / MathSqrt(cxx * cyy);
     }
   g_infoBars[t] = n;
   g_infoZ[t]    = zv;
   g_infoAc[t]   = ac1;

   //--- direzione degli eventi (primo attraversamento di +-soglia) del Z principale
   ArrayResize(g_evd, g_nThr * n);
   ArrayInitialize(g_evd, 0);
   for(int ti = 0; ti < g_nThr; ti++)
      for(int i = 1; i < n - 1; i++)
        {
         const double z = zA[i];
         if(z == EMPTY_VALUE) continue;
         const bool pUp = (zA[i - 1] != EMPTY_VALUE && zA[i - 1] >=  g_thr[ti]);
         const bool pDn = (zA[i - 1] != EMPTY_VALUE && zA[i - 1] <= -g_thr[ti]);
         if(z >= g_thr[ti] && !pUp)       g_evd[ti * n + i] = 1;
         else if(z <= -g_thr[ti] && !pDn) g_evd[ti * n + i] = -1;
        }

   //--- tabelle degli eventi per questo TF: [soglia][orizzonte][k] con k = 0 SEGUI-IS, 1 SEGUI-OOS, 2 INVERTI-IS, 3 INVERTI-OOS
   const int nCell = g_nThr * g_nH * 4;
   double evN[], evG[], evNet[], evT[], evSk[], evBuy[];
   ArrayResize(evN, nCell); ArrayResize(evG, nCell); ArrayResize(evNet, nCell); ArrayResize(evT, nCell);
   ArrayResize(evSk, g_nThr * g_nH * 2); ArrayResize(evBuy, g_nThr * g_nH * 2);
   ArrayInitialize(evN, 0.0); ArrayInitialize(evG, 0.0); ArrayInitialize(evNet, 0.0); ArrayInitialize(evT, 0.0);
   ArrayInitialize(evSk, 0.0); ArrayInitialize(evBuy, 0.0);

   double yv[], cv[];
   int    dv[];
   uchar  sm[];
   ArrayResize(yv, n); ArrayResize(cv, n); ArrayResize(dv, n); ArrayResize(sm, n);

   for(int h = 0; h < g_nH; h++)
     {
      if(IsStopped()) return;
      FL_FwdClose(g_hor[h]);
      FL_BuildY(n, g_hor[h], ent, yv, cv, dv, sm);

      //--- regressione continua per ogni feature
      for(int f = 0; f < NFEAT; f++)
        {
         RegRes ra, ri, ro;
         FL_Reg(g_F, f * n, n, yv, dv, sm, ra, ri, ro);
         if(ra.n < 200.0) continue;
         CellRes c;
         c.tf = t; c.feat = f; c.hm = g_hor[h];
         c.n = ra.n; c.beta = ra.beta; c.t = ra.t; c.ic = ra.ic; c.icse = ra.icse;
         c.tIS = ri.t; c.tOOS = ro.t; c.icOOS = ro.ic; c.p = -2.0;     // -2 = placebo non ancora fatto
         const int k = g_nCells;
         ArrayResize(g_cells, k + 1);
         g_cells[k] = c;
         g_nCells = k + 1;
        }

      //--- eventi del Z principale: conteggi, poi costo e abilita' (serve la quota di acquisti)
      Clu cnet[], csk[];
      double gsum[], nb[], ns[];
      ArrayResize(cnet, g_nThr * 4); ArrayResize(csk, g_nThr * 2);
      ArrayResize(gsum, g_nThr * 4); ArrayResize(nb, g_nThr * 2); ArrayResize(ns, g_nThr * 2);
      for(int q = 0; q < g_nThr * 4; q++) { CluInit(cnet[q]); gsum[q] = 0.0; }
      for(int q = 0; q < g_nThr * 2; q++) { CluInit(csk[q]); nb[q] = 0.0; ns[q] = 0.0; }
      for(int i = 0; i < n; i++)
        {
         if(yv[i] == EMPTY_VALUE) continue;
         for(int ti = 0; ti < g_nThr; ti++)
           {
            const int d = (int)g_evd[ti * n + i];
            if(d == 0) continue;
            const int q = ti * 2 + (int)sm[i];
            if(d > 0) nb[q] += 1.0; else ns[q] += 1.0;
           }
        }
      for(int i = 0; i < n; i++)
        {
         if(yv[i] == EMPTY_VALUE) continue;
         for(int ti = 0; ti < g_nThr; ti++)
           {
            const int d = (int)g_evd[ti * n + i];
            if(d == 0) continue;
            const int smp = (int)sm[i];
            const double gF = (double)d * yv[i];
            const int kf = ti * 4 + smp;
            const int ki = ti * 4 + 2 + smp;
            CluAdd(cnet[kf], dv[i], gF - cv[i]);          gsum[kf] += gF;
            CluAdd(cnet[ki], dv[i], -gF - cv[i]);         gsum[ki] += -gF;
            const double nbb = nb[ti * 2 + smp], nss = ns[ti * 2 + smp];
            const double sbar = (nbb - nss) / (nbb + nss);
            CluAdd(csk[ti * 2 + smp], dv[i], ((double)d - sbar) * yv[i]);
           }
        }
      for(int ti = 0; ti < g_nThr; ti++)
        {
         for(int kk = 0; kk < 4; kk++)
           {
            CluEnd(cnet[ti * 4 + kk]);
            const int ix = (ti * g_nH + h) * 4 + kk;
            evN[ix]   = cnet[ti * 4 + kk].n;
            evG[ix]   = (cnet[ti * 4 + kk].n > 0.0) ? gsum[ti * 4 + kk] / cnet[ti * 4 + kk].n : 0.0;
            evNet[ix] = (cnet[ti * 4 + kk].n > 0.0) ? cnet[ti * 4 + kk].sum / cnet[ti * 4 + kk].n : 0.0;
            evT[ix]   = CluT(cnet[ti * 4 + kk]);
           }
         for(int smp = 0; smp < 2; smp++)
           {
            CluEnd(csk[ti * 2 + smp]);
            const int ix = (ti * g_nH + h) * 2 + smp;
            evSk[ix]  = CluT(csk[ti * 2 + smp]);
            const double tot = nb[ti * 2 + smp] + ns[ti * 2 + smp];
            evBuy[ix] = (tot > 0.0) ? 100.0 * nb[ti * 2 + smp] / tot : 0.0;
           }
        }
     }

   //--- placebo a traslazione: per questo TF, le InpPlaceboPerTF celle con |t| piu' alto (non le prime in ordine di calcolo)
   for(int pz = 0; pz < InpPlaceboPerTF && InpPlaceboB >= 20 && !IsStopped(); pz++)
     {
      int bi = -1;
      double bv = InpPlaceboMinT;
      for(int k = k0; k < g_nCells; k++)
         if(g_cells[k].p == -2.0 && g_cells[k].n >= 500.0 && MathAbs(g_cells[k].t) >= bv)
           { bv = MathAbs(g_cells[k].t); bi = k; }
      if(bi < 0) break;
      FL_FwdClose(g_cells[bi].hm);
      FL_BuildY(n, g_cells[bi].hm, ent, yv, cv, dv, sm);
      g_cells[bi].p = FL_PlaceboP(g_F, g_cells[bi].feat * n, n, yv, bpd, g_cells[bi].ic, InpPlaceboB);
     }

   //--- miglior cella evento in-sample (soglia x orizzonte x verso) e suo risultato fuori campione
   int bt = -1, bh = -1, bs = -1;
   double bT = -1.0e18;
   for(int ti = 0; ti < g_nThr; ti++)
      for(int h = 0; h < g_nH; h++)
         for(int side = 0; side < 2; side++)
           {
            const int ix = (ti * g_nH + h) * 4 + side * 2;
            if(evN[ix] < (double)InpMinEvents) continue;
            if(evT[ix] > bT) { bT = evT[ix]; bt = ti; bh = h; bs = side; }
           }
   if(bt >= 0)
     {
      const int iI = (bt * g_nH + bh) * 4 + bs * 2;
      const int iO = iI + 1;
      EvRes e;
      e.tf = t; e.hm = g_hor[bh]; e.side = bs; e.thr = g_thr[bt];
      e.nIS = evN[iI]; e.netIS = evNet[iI]; e.tIS = evT[iI];
      e.nOOS = evN[iO]; e.gOOS = evG[iO]; e.netOOS = evNet[iO]; e.tOOS = evT[iO];
      e.skillT = (bs == 0 ? 1.0 : -1.0) * evSk[(bt * g_nH + bh) * 2 + 1];
      e.buyPct = evBuy[(bt * g_nH + bh) * 2 + 1];
      const int k = g_nEv;
      ArrayResize(g_ev, k + 1);
      g_ev[k] = e;
      g_nEv = k + 1;
     }
   Print("TF ", g_tfName[t], ": barre ", n, " | Z validi ", zv, " | ac(1) ", DoubleToString(ac1, 2), " | celle totali ", g_nCells);
   Comment("FlowLab: TF ", g_tfName[t], " completato");
  }

//+------------------------------------------------------------------+
//| Report                                                            |
//+------------------------------------------------------------------+
void RepHead()
  {
   W("<!doctype html><html><head><meta charset='utf-8'><title>FlowLab MultiTF</title><style>");
   W("body{background:#14161a;color:#d8dee9;font:13px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;margin:24px}");
   W("h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;margin:26px 0 8px;color:#88c0d0;border-bottom:1px solid #2e3440;padding-bottom:4px}");
   W("table{border-collapse:collapse;margin:8px 0;font-size:12px}td,th{border:1px solid #2e3440;padding:3px 9px;text-align:right}");
   W("th{background:#1e222a;color:#8fbcbb}td:first-child,th:first-child{text-align:left}");
   W(".note{background:#1e222a;border-left:3px solid #ebcb8b;padding:10px 14px;margin:12px 0;color:#c8ccd4}.ko{border-left-color:#bf616a}.ok{border-left-color:#a3be8c}");
   W("pre{background:#0f1114;border:1px solid #2e3440;border-radius:6px;padding:14px;overflow-x:auto;font:11px/1.45 ui-monospace,Consolas,monospace;color:#d8dee9;white-space:pre-wrap}");
   W("</style></head><body>");
  }

string Pad(const string s, const int w)
  {
   string o = s;
   while(StringLen(o) < w) o += " ";
   return o;
  }

string PadL(const string s, const int w)
  {
   string o = s;
   while(StringLen(o) < w) o = " " + o;
   return o;
  }

string VerdFlag(const CellRes &c)
  {
   const bool same = (c.tIS * c.tOOS > 0.0) && MathAbs(c.tOOS) >= 1.96;
   const bool cand = (MathAbs(c.t) >= g_zB && c.p >= 0.0 && c.p < 0.05 && same);
   if(cand) return "CANDIDATO";
   if(MathAbs(c.t) >= g_zB) return "supera Bonferroni, non regge";
   if(MathAbs(c.t) >= 1.96) return "*";
   return "";
  }

//--- indici delle prime InpTopK celle per |t|
int TopCells(int &idx[])
  {
   ArrayResize(idx, 0);
   bool used[];
   ArrayResize(used, MathMax(1, g_nCells));
   ArrayInitialize(used, false);
   for(int z = 0; z < InpTopK; z++)
     {
      int bi = -1;
      double bv = -1.0;
      for(int i = 0; i < g_nCells; i++)
         if(!used[i] && MathAbs(g_cells[i].t) > bv) { bv = MathAbs(g_cells[i].t); bi = i; }
      if(bi < 0) break;
      used[bi] = true;
      const int k = ArraySize(idx);
      ArrayResize(idx, k + 1);
      idx[k] = bi;
     }
   return ArraySize(idx);
  }

void BuildReport()
  {
   const string tag = SafeTag(_Symbol);
   const string fHtml = "FlowLab_MultiTF_" + tag + ".html";
   const string fSum  = "FlowLab_MultiTF_riepilogo_" + tag + ".txt";
   const string fDg   = "FlowLab_MultiTF_digest_" + tag + ".txt";
   const int nt = g_nCells;
   g_zB = ZCrit(MathMax(1, nt));
   const double costTot = ((InpCostPoints > 0.0) ? InpCostPoints : g_medSpr) + g_extraPts;
   int npass = 0, ncand = 0, ncandZ = 0, nplac = 0;
   for(int i = 0; i < g_nCells; i++)
     {
      if(MathAbs(g_cells[i].t) >= g_zB) npass++;
      if(g_cells[i].p >= 0.0) nplac++;
      if(VerdFlag(g_cells[i]) == "CANDIDATO") { ncand++; if(g_cells[i].feat <= 3) ncandZ++; }
     }
   int evPos = 0;
   for(int i = 0; i < g_nEv; i++)
      if(g_ev[i].nOOS >= 30.0 && g_ev[i].netOOS > 0.0 && g_ev[i].tOOS >= 2.0) evPos++;

   //--- Z contro i riferimenti banali (momentum, trend EMA13, vecchio delta), per ogni coppia (TF, orizzonte)
   double bz[], br[];
   ArrayResize(bz, MathMax(1, g_nT * g_nH));
   ArrayResize(br, MathMax(1, g_nT * g_nH));
   ArrayInitialize(bz, -1.0);
   ArrayInitialize(br, -1.0);
   for(int i = 0; i < g_nCells; i++)
     {
      int hi = -1;
      for(int h = 0; h < g_nH; h++)
         if(g_hor[h] == g_cells[i].hm) { hi = h; break; }
      if(hi < 0) continue;
      const int ix = g_cells[i].tf * g_nH + hi;
      const double a = MathAbs(g_cells[i].t);
      const int ff = g_cells[i].feat;
      if(ff <= 3) { if(a > bz[ix]) bz[ix] = a; }
      else if(ff >= 5) { if(a > br[ix]) br[ix] = a; }
     }
   int nCmp = 0, nZwin = 0;
   for(int i = 0; i < g_nT * g_nH; i++)
      if(bz[i] >= 0.0 && br[i] >= 0.0 && MathMax(bz[i], br[i]) >= g_zB)
        { nCmp++; if(bz[i] > br[i]) nZwin++; }

   int top[];
   const int nTop = TopCells(top);

   string sum = "FlowLab MultiTF - " + _Symbol + "\n";
   const datetime tEnd = (datetime)MathMin((long)InpTo, (long)g_m1Time[g_n1 - 1]);
   sum += "Periodo " + TimeToString(g_tStart, TIME_DATE) + " - " + TimeToString(tEnd, TIME_DATE) + " | " + IS(g_nT) + " TF | " + IS(g_nH) + " orizzonti | split " + IS(InpSplitPct) + "% | offset " + IS(InpTimeOffsetH) + " h\n";
   sum += "Flow Z: N " + IS(InpFlowN) + ", M " + IS(InpFlowM) + ", sedute " + IS(InpFlowDays) + ", soglie eventi " + InpEventThr + "\n";
   sum += "Costo: " + string(InpCostPoints > 0.0 ? ("fisso " + F1(InpCostPoints) + " pt") : ("spread M1 reale (mediano " + F0(g_medSpr) + " pt)")) + " + commissione " + F1(g_commPts) + " pt a/r (" + F2(InpCommissionPerLotSide) + " " + g_ccy + " per lato e per lotto) = circa " + F1(costTot) + " pt per operazione" +
          string(g_commPts <= 0.0 ? " [ATTENZIONE: commissione zero, risultati ottimisti su un conto Raw]" : "") + string(g_pvWarn ? " [valore del punto STIMATO]" : "") + "\n";
   if(g_zeroSprPct > 20.0 && InpCostPoints <= 0.0) sum += "ATTENZIONE: spread M1 = 0 sul " + F1(g_zeroSprPct) + "% delle barre: il costo e' sottostimato. Imposta InpCostPoints.\n";
   if(g_histWarn) sum += "ATTENZIONE: lo storico M1 e' piu' corto del periodo richiesto.\n";
   sum += "\nREGRESSIONI (rendimento LORDO, senza costi): " + IS(nt) + " test (TF x feature x orizzonte). Bonferroni 5%: |t| >= " + F2(g_zB) + ". Superano Bonferroni: " + IS(npass) + " (" + F1(100.0 * npass / MathMax(1, nt)) + "%).\n";
   sum += "Placebo calcolato su " + IS(nplac) + " celle (le " + IS(InpPlaceboPerTF) + " con |t| piu' alto di ogni TF). CANDIDATI (Bonferroni + placebo p<0.05 + stesso segno e |t|>=1.96 sul fuori campione): " + IS(ncand) + ", di cui su Z: " + IS(ncandZ) + ".\n";
   if(nCmp > 0)
      sum += "Z contro i riferimenti (momentum, trend EMA13, vecchio delta): fra le " + IS(nCmp) + " coppie (TF, orizzonte) in cui qualcuno supera Bonferroni, la migliore delle 4 varianti di Z ha |t| maggiore del miglior riferimento in " + IS(nZwin) + " (" + F0(100.0 * nZwin / nCmp) + "%).\n";
   sum += "EVENTI (con costi, fuori campione): su " + IS(g_nEv) + " TF la cella scelta in-sample e' positiva al netto con t>=2 in " + IS(evPos) + " (per caso se ne attendono circa " + F1(0.0228 * (double)g_nEv) + ").\n";
   string rd = "";
   if(evPos == 0) rd += "Con i costi nessuna cella evento e' positiva fuori campione. ";
   if(ncandZ == 0) rd += "Nessun candidato su Z. ";
   else if(nCmp > 0 && nZwin * 2 < nCmp) rd += "Su Z ci sono candidati, ma i riferimenti banali fanno uguale o meglio: l'effetto non e' specifico di Z. ";
   else rd += "Z ha candidati e batte i riferimenti piu' spesso che no: da CONFERMARE su altri simboli e su un periodo successivo, la scelta fra tante celle gonfia il migliore. ";
   rd += "Le regressioni sono al LORDO dei costi: un legame statistico non e' un vantaggio operativo. NON e' una prova di assenza di effetto: guarda l'IC minimo rilevabile (tabella 2).";
   sum += "LETTURA: " + rd + "\n";

   //--- medie per feature
   sum += "\n|t| per feature (senza alcun legame |t| medio atteso circa 0.8; l'assorbimento fa da controllo negativo):\n";
   for(int f = 0; f < NFEAT; f++)
     {
      double s = 0.0, mx = 0.0;
      int c = 0, up = 0, dn = 0;
      for(int i = 0; i < g_nCells; i++)
         if(g_cells[i].feat == f)
           {
            const double a = MathAbs(g_cells[i].t);
            s += a;
            if(a > mx) mx = a;
            c++;
            if(g_cells[i].t >= g_zB) up++;
            if(g_cells[i].t <= -g_zB) dn++;
           }
      if(c > 0) sum += "  " + Pad(g_featName[f], 14) + " medio " + F2(s / c) + ", massimo " + F2(mx) + " | oltre Bonferroni: " + IS(up) + " positivi, " + IS(dn) + " negativi su " + IS(c) + "\n";
     }

   //--- prime celle (testo, da incollare)
   sum += "\nPrime " + IS(nTop) + " celle per |t| (beta = punti per 1 dev.std della feature; |beta|/costo confronta con i " + F1(costTot) + " pt di costo):\n";
   sum += Pad("TF", 4) + Pad("feature", 15) + PadL("oriz", 6) + PadL("barre", 9) + PadL("beta", 8) + PadL("|b|/costo", 10) + PadL("t", 8) + PadL("IC", 8) + PadL("tIS", 7) + PadL("tOOS", 7) + PadL("plac", 7) + "  giudizio\n";
   for(int z = 0; z < nTop; z++)
     {
      CellRes c;
      c = g_cells[top[z]];
      sum += Pad(g_tfName[c.tf], 4) + Pad(g_featName[c.feat], 15) + PadL(IS(c.hm) + "m", 6) + PadL(F0(c.n), 9) + PadL(Sg(c.beta, 2), 8) + PadL((costTot > 0.0 ? F2(MathAbs(c.beta) / costTot) : string("-")), 10) +
             PadL(Sg(c.t, 1), 8) + PadL(Sg(c.ic, 3), 8) + PadL(F1(c.tIS), 7) + PadL(F1(c.tOOS), 7) + PadL((c.p >= 0.0 ? F3(c.p) : string("-")), 7) + "  " + VerdFlag(c) + "\n";
     }

   //--- eventi (testo, da incollare)
   sum += "\nEVENTI di Z_clv_pesato: miglior cella in-sample per TF e suo risultato fuori campione (punti, costo incluso):\n";
   sum += Pad("TF", 4) + Pad("verso", 8) + PadL("soglia", 7) + PadL("tenuta", 8) + PadL("nIS", 7) + PadL("netIS", 8) + PadL("tIS", 7) + PadL("nOOS", 7) + PadL("lordo", 8) + PadL("netto", 8) + PadL("tOOS", 7) + PadL("abil.t", 8) + PadL("%BUY", 6) + "\n";
   for(int i = 0; i < g_nEv; i++)
     {
      EvRes e;
      e = g_ev[i];
      sum += Pad(g_tfName[e.tf], 4) + Pad((e.side == 0 ? "SEGUI" : "INVERTI"), 8) + PadL(F1(e.thr), 7) + PadL(IS(e.hm) + "m", 8) + PadL(F0(e.nIS), 7) + PadL(Sg(e.netIS, 1), 8) + PadL(F1(e.tIS), 7) +
             PadL(F0(e.nOOS), 7) + PadL(Sg(e.gOOS, 1), 8) + PadL(Sg(e.netOOS, 1), 8) + PadL(F1(e.tOOS), 7) + PadL(F1(e.skillT), 8) + PadL(F0(e.buyPct) + "%", 6) + "\n";
     }

   g_fh = FileOpen(fHtml, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(g_fh == INVALID_HANDLE) Print("HTML non scrivibile (errore ", GetLastError(), "): salvo solo riepilogo e digest.");
   RepHead();
   W("<h1>FlowLab MultiTF &mdash; " + _Symbol + "</h1>");
   W("<div class='note " + string((ncandZ == 0 && evPos == 0) ? "ko" : "ok") + "'><pre>" + HtmlEsc(sum) + "</pre></div>");
   W("<div class='note'>Denaro: " + (g_money ? ("lotto " + LotTxt() + " | 1 punto per 1.00 lotto = " + DoubleToString(g_pv, 4) + " " + g_ccy + " | " + HtmlEsc(g_pvInfo)) : string("non disponibile")) + "</div>");

   //--- tabella 1: TF
   W("<h2>1. Timeframe: barre, Z validi, autocorrelazione di Z</h2>");
   W("<div class='note'>L'autocorrelazione a ritardo 1 di Z e' alta (le finestre di N barre si sovrappongono): barre vicine non sono osservazioni indipendenti. Per questo gli errori standard sono raggruppati per giorno (per blocchi di piu' giorni con gli orizzonti lunghi).</div>");
   W("<table><tr><th>TF</th><th>Barre</th><th>Z validi</th><th>ac(1)</th></tr>");
   for(int t = 0; t < g_nT; t++)
      W("<tr><td>" + g_tfName[t] + "</td>" + Td(IS(g_infoBars[t])) + Td(IS(g_infoZ[t])) + Td(F2(g_infoAc[t])) + "</tr>");
   W("</table>");

   //--- tabella 2: potenza
   W("<h2>2. Potenza: IC minimo che il campione riesce a vedere (80% di potenza, 5%), Z_clv_pesato, intero periodo</h2>");
   W("<div class='note'>Calcolato come 2.8 volte l'errore standard osservato dell'IC. Se l'IC vero e' sotto questo valore il test non lo vede: l'assenza di risultati NON dimostra l'assenza di un effetto. Sul solo periodo di verifica i valori sono circa 1.7 volte piu' alti.</div>");
   W("<table><tr><th>TF</th>");
   for(int h = 0; h < g_nH; h++) W("<th>" + IS(g_hor[h]) + "m</th>");
   W("</tr>");
   for(int t = 0; t < g_nT; t++)
     {
      W("<tr><td>" + g_tfName[t] + "</td>");
      for(int h = 0; h < g_nH; h++)
        {
         string cell = "-";
         for(int i = 0; i < g_nCells; i++)
            if(g_cells[i].tf == t && g_cells[i].feat == 0 && g_cells[i].hm == g_hor[h]) { cell = F3(2.8 * g_cells[i].icse); break; }
         W(Td(cell));
        }
      W("</tr>");
     }
   W("</table>");

   //--- tabella 3: classifica per |t|
   W("<h2>3. Regressione: le prime " + IS(nTop) + " celle per |t| (t con errore standard raggruppato)</h2>");
   W("<div class='note'>Giudizio: <b>CANDIDATO</b> solo se supera Bonferroni (|t| &ge; " + F2(g_zB) + " su " + IS(nt) + " test), il placebo a traslazione ha p &lt; 0.05 e in entrambe le meta' del periodo il segno e' lo stesso con |t| &ge; 1.96 sul fuori campione. "
     "Il placebo si calcola per le " + IS(InpPlaceboPerTF) + " celle con |t| piu' alto di ogni TF (almeno " + F1(InpPlaceboMinT) + "). IC e t sono sull'intero periodo; IS = primo periodo, OOS = resto. Il rendimento e' LORDO: confronta la pendenza con il costo.</div>");
   W("<table><tr><th>TF</th><th>Feature</th><th>Orizzonte</th><th>Barre</th><th>Pendenza (pt per 1 dev.std)</th><th>|pend.|/costo</th><th>t</th><th>IC</th><th>t IS</th><th>t OOS</th><th>IC OOS</th><th>Placebo p</th><th>Giudizio</th></tr>");
   for(int z = 0; z < nTop; z++)
     {
      CellRes c;
      c = g_cells[top[z]];
      W("<tr><td>" + g_tfName[c.tf] + "</td><td>" + g_featName[c.feat] + "</td>" + Td(IS(c.hm) + "m") + Td(F0(c.n)) + Td(F2(c.beta)) + Td(costTot > 0.0 ? F2(MathAbs(c.beta) / costTot) : string("-")) + Td(F2(c.t), ColT(c.t)) + Td(F3(c.ic)) +
        Td(F2(c.tIS)) + Td(F2(c.tOOS)) + Td(F3(c.icOOS)) + Td(c.p >= 0.0 ? F3(c.p) : string("-")) + Td(VerdFlag(c)) + "</tr>");
     }
   W("</table>");

   //--- tabella 4: eventi
   W("<h2>4. Eventi: primo attraversamento di +-soglia di Z_clv_pesato, costo incluso</h2>");
   W("<div class='note'>Per ogni TF la cella (soglia x orizzonte x verso) con il t del netto piu' alto sul primo periodo (almeno " + IS(InpMinEvents) + " eventi), e il suo risultato sul resto. "
     "SEGUI = compra su Z alto, vendi su Z basso; INVERTI = il contrario. Il netto e' al netto di spread e commissione. <b>t abilita'</b> = cov(verso, rendimento), che toglie la deriva del prezzo: "
     "un netto positivo con abilita' vicina a zero e' deriva, non informazione. % BUY = quota di acquisti fra gli eventi fuori campione.</div>");
   W("<table><tr><th>TF</th><th>Soglia</th><th>Tenuta</th><th>Verso</th><th>IS eventi</th><th>IS netto</th><th>IS t</th><th>OOS eventi</th><th>OOS lordo</th><th>OOS netto</th><th>OOS t</th><th>t abilita'</th><th>% BUY</th></tr>");
   for(int i = 0; i < g_nEv; i++)
     {
      EvRes e;
      e = g_ev[i];
      W("<tr><td>" + g_tfName[e.tf] + "</td>" + Td(F1(e.thr)) + Td(IS(e.hm) + "m") + Td(e.side == 0 ? "SEGUI" : "INVERTI") + Td(F0(e.nIS)) + Td(F1(e.netIS), ColSign(e.netIS)) + Td(F2(e.tIS)) +
        Td(F0(e.nOOS)) + Td(F1(e.gOOS), ColSign(e.gOOS)) + Td("<b>" + F1(e.netOOS) + "</b>", ColSign(e.netOOS)) + Td(F2(e.tOOS), ColT(e.tOOS)) + Td(F2(e.skillT)) + Td(F0(e.buyPct) + "%") + "</tr>");
     }
   W("</table>");
   W("<h2>Riepilogo da copiare</h2><div class='note'><pre>" + HtmlEsc(sum) + "</pre></div></body></html>");
   if(g_fh != INVALID_HANDLE) { FileClose(g_fh); g_fh = INVALID_HANDLE; Print("Report: MQL5/Files/", fHtml); }

   int sf = FileOpen(fSum, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(sf != INVALID_HANDLE) { FileWriteString(sf, sum); FileClose(sf); Print("Riepilogo: MQL5/Files/", fSum); }

   //--- digest: tutte le celle
   string dg = "### FLOWLAB DIGEST v1\n";
   dg += "CFG|" + _Symbol + "|N|" + IS(InpFlowN) + "|M|" + IS(InpFlowM) + "|D|" + IS(InpFlowDays) + "|minsess|" + IS(InpFlowMinSess) + "|thr|" + InpEventThr + "|split|" + IS(InpSplitPct) +
         "|costfix|" + F1(InpCostPoints) + "|commpts|" + F1(g_commPts) + "|extra|" + F1(InpExtraCostPts) + "|lag|" + IS(InpEntryLagMin) + "|medspr|" + F0(g_medSpr) + "|tests|" + IS(nt) + "|bonf|" + F2(g_zB) + "\n";
   for(int t = 0; t < g_nT; t++)
      dg += "TF|" + g_tfName[t] + "|bars|" + IS(g_infoBars[t]) + "|zvalid|" + IS(g_infoZ[t]) + "|ac1|" + F2(g_infoAc[t]) + "\n";
   for(int i = 0; i < g_nCells; i++)
     {
      CellRes c;
      c = g_cells[i];
      dg += "CELL|" + g_tfName[c.tf] + "|" + g_featName[c.feat] + "|" + IS(c.hm) + "|n|" + F0(c.n) + "|beta|" + F2(c.beta) + "|t|" + F2(c.t) + "|ic|" + F3(c.ic) + "|minic|" + F3(2.8 * c.icse) +
            "|tis|" + F2(c.tIS) + "|toos|" + F2(c.tOOS) + "|icoos|" + F3(c.icOOS) + "|p|" + (c.p >= 0.0 ? F3(c.p) : string("-")) + "\n";
     }
   for(int i = 0; i < g_nEv; i++)
     {
      EvRes e;
      e = g_ev[i];
      dg += "EV|" + g_tfName[e.tf] + "|thr|" + F1(e.thr) + "|hold|" + IS(e.hm) + "|" + string(e.side == 0 ? "SEGUI" : "INVERTI") + "|isn|" + F0(e.nIS) + "|isnet|" + F1(e.netIS) + "|ist|" + F2(e.tIS) +
            "|oosn|" + F0(e.nOOS) + "|oosgross|" + F1(e.gOOS) + "|oosnet|" + F1(e.netOOS) + "|oost|" + F2(e.tOOS) + "|skillt|" + F2(e.skillT) + "|buy|" + F0(e.buyPct) + "\n";
     }
   dg += "READ|candidati|" + IS(ncand) + "|candidatiZ|" + IS(ncandZ) + "|bonferroni|" + IS(npass) + "|eventi_positivi|" + IS(evPos) + "\n### END\n";
   int df = FileOpen(fDg, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(df != INVALID_HANDLE) { FileWriteString(df, dg); FileClose(df); Print("Digest: MQL5/Files/", fDg); }
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   uint t0 = GetTickCount();
   g_pt  = _Point;
   g_off = (long)InpTimeOffsetH * 3600L;
   if(!SetupInputs()) return;
   if(!LoadM1()) return;
   SetupMoney();
   ArrayResize(g_infoBars, g_nT); ArrayResize(g_infoZ, g_nT); ArrayResize(g_infoAc, g_nT);
   ArrayInitialize(g_infoBars, 0); ArrayInitialize(g_infoZ, 0); ArrayInitialize(g_infoAc, 0.0);
   ArrayResize(g_fCl, g_n1);
   ArrayResize(g_okF, g_n1);
   Print("=== FlowLab MultiTF | ", _Symbol, " | ", g_nT, " TF | ", g_nH, " orizzonti | ", g_nThr, " soglie");

   for(int t = 0; t < g_nT; t++)
     {
      if(IsStopped()) { Print("Interrotto dall'utente."); Comment(""); return; }
      if(g_tf[t] == PERIOD_M1)
         ProcessTF(t, g_r1, g_n1);
      else
        {
         MqlRates r[];
         int n = LoadTF(t, r);
         if(n < 600) { Print("TF ", g_tfName[t], ": storico non disponibile (", n, ")"); continue; }
         ProcessTF(t, r, n);
         ArrayFree(r);
        }
      Print("... ", (GetTickCount() - t0) / 1000.0, " s");
     }
   if(g_nCells < 1) { Print("Nessuna cella calcolata: controlla periodo e storico."); Comment(""); return; }
   BuildReport();
   Comment("");
   Print("Fatto in ", (GetTickCount() - t0) / 1000.0, " s");
  }
//+------------------------------------------------------------------+
