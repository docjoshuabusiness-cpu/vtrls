//+------------------------------------------------------------------+
//|                                        SyntheticDelta_EA_v2.0.mq5 |
//+------------------------------------------------------------------+
//| SCOPO                                                             |
//| -----                                                             |
//| Riscrittura dell'EA SyntheticDelta v1.13 con due obiettivi:       |
//|  1) ESECUZIONE SEMPLICE: lotto fisso, SL / TP / trailing tutti    |
//|     espressi in multipli di ATR, un solo trade alla volta.        |
//|  2) MISURARE I SEGNALI UNO PER UNO: ogni segnale riceve una       |
//|     "classe" (sorgente, verso, posizione nella raffica, fascia     |
//|     oraria, ...). L'EA puo' operare UNA SOLA classe per volta, e  |
//|     con Inp_ClassID >= 0 l'ottimizzatore MT5 scorre tutte le      |
//|     classi cambiando solo Inp_ClassID: ogni passata = una classe. |
//|                                                                    |
//| IMPOSTAZIONI DELL'INDICATORE: restano quelle di v1.13 (EMA 13,     |
//| VolAvg 20, soglia 0.15, ADX 20, S/R 15 x 0.5 ATR). In questa fase |
//| NON si ottimizzano. ADX e S/R non sono piu' filtri rigidi ma       |
//| ETICHETTE: si puo' misurare se una classe con filtro "passato"     |
//| rende piu' di una con filtro "fallito" (Inp_ADXReq / Inp_SRReq).   |
//|                                                                    |
//| CLASSE DEL SEGNALE                                                 |
//|  sorgente : DELTA (Synthetic Delta) | EXP_ADDED (Expansion Candle  |
//|             sulle barre in cui il Delta NON da' segnale)           |
//|  verso    : BUY | SELL (verso del SEGNALE, prima di Inp_Invert)    |
//|  raffica  : posizione nella serie di segnali consecutivi nello     |
//|             stesso verso: 1, 2, 3, 4+ (stessa definizione di        |
//|             SignalLab: calcolata sul flusso grezzo, prima dei      |
//|             filtri)                                                |
//|  fascia   : fascia oraria d'ingresso (server + Inp_TimeOffsetH)    |
//|                                                                    |
//| CODIFICA Inp_ClassID (-1 = nessuna classe, solo filtri manuali).   |
//| Per ID >= 0 e' un numero in sistema misto, ogni cifra ha ANY=0:    |
//|  ID = ((src*3 + dir)*5 + burst) * (nB+1) + hour                    |
//|  src   : 0 ANY, 1 DELTA, 2 EXP_ADDED                               |
//|  dir   : 0 ANY, 1 BUY,   2 SELL                                    |
//|  burst : 0 ANY, 1, 2, 3, 4 (= 4 o piu')                            |
//|  hour  : 0 ANY, 1..nB = fascia (nB = 1440 / Inp_BucketMin)         |
//|  Totale classi = 45 * (nB + 1). La tabella ID -> etichetta viene   |
//|  scritta in Common\Files\SDv2_classmap_<bucket>m.csv (test singolo)|
//|  Scorciatoia: start 0, step (nB+1), stop max = solo classi con     |
//|  ora = ANY (45 classi).                                            |
//|                                                                    |
//| NOTE TECNICHE                                                      |
//|  - R (rendimento in multipli del rischio iniziale) e' calcolato    |
//|    in PREZZO: (uscita - entrata) / distanza SL, meno il costo      |
//|    extra in punti (Inp_ExtraCostPts). Non dipende da tick value,   |
//|    valuta del conto o dalla modalita' "profitto in pips" del       |
//|    tester. Lo spread e' gia' nei prezzi di riempimento.            |
//|  - Funziona su conti NETTING e HEDGING: una sola posizione per     |
//|    volta (in netting un segnale opposto chiuderebbe la posizione   |
//|    invece di aprirne una, falsando le statistiche).                |
//|  - Tutto il segnale e' calcolato sulla barra CHIUSA (shift 1); si  |
//|    entra al primo tick della barra successiva.                     |
//|  - Lo stato (raffica, expansion pending) e' ricostruito all'avvio  |
//|    rielaborando le ultime barre, quindi sopravvive ai riavvii.     |
//+------------------------------------------------------------------+
#property copyright "SyntheticDelta EA v2.0"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| COSTANTI ED ENUM                                                  |
//+------------------------------------------------------------------+
#define SD_SRC_DELTA 0
#define SD_SRC_EXP   1

enum ENUM_SD_SRCSEL { SDE_SRC_ANY = 0, SDE_SRC_DELTA = 1, SDE_SRC_EXPADDED = 2 };
enum ENUM_SD_DIRSEL { SDE_DIR_ANY = 0, SDE_DIR_BUY = 1, SDE_DIR_SELL = 2 };
enum ENUM_SD_REQ    { SDE_REQ_IGNORE = 0, SDE_REQ_PASS = 1, SDE_REQ_FAIL = 2 };
enum ENUM_SD_EXPREL { SDE_EXPREL_ANY = 0, SDE_EXPREL_NONE = 1, SDE_EXPREL_AGREE = 2, SDE_EXPREL_NOCONFLICT = 3 };
enum ENUM_SD_FIT    { SDE_FIT_T_R = 0, SDE_FIT_EXPECT_R = 1, SDE_FIT_RECOVERY_PF = 2 };

//+------------------------------------------------------------------+
//| INPUT                                                             |
//+------------------------------------------------------------------+
input group "=== CLASSE DI SEGNALE: SCANSIONE (ottimizzare SOLO Inp_ClassID) ==="
input int    Inp_ClassID        = -1;     // -1 = nessuna classe (valgono solo i filtri manuali). >= 0 = opera solo quella classe: start 0, step 1, stop 45*(nB+1)-1
input int    Inp_BucketMin      = 240;    // ampiezza fascia oraria in minuti (valori validi: 5,10,15,20,30,60,120,180,240,360,480,720,1440)
input int    Inp_TimeOffsetH    = 0;      // ore da sommare al server time per fasce e giorni

input group "=== CLASSE DI SEGNALE: FILTRI MANUALI (si sommano in AND alla scansione) ==="
input ENUM_SD_SRCSEL Inp_SrcSel = SDE_SRC_ANY;   // sorgente del segnale
input ENUM_SD_DIRSEL Inp_DirSel = SDE_DIR_ANY;   // verso del segnale (prima di Inp_Invert)
input int    Inp_BurstMin       = 1;      // posizione minima nella raffica
input int    Inp_BurstMax       = 255;    // posizione massima nella raffica
input string Inp_Hours          = "";     // ore ammesse (0-23, server+offset), es. "7-11,13,15-17". Vuoto = tutte. "22-3" = a cavallo di mezzanotte
input string Inp_Days           = "";     // giorni ammessi (0=Dom..6=Sab), es. "1-5". Vuoto = tutti
input ENUM_SD_EXPREL Inp_ExpRel = SDE_EXPREL_ANY; // solo segnali DELTA: relazione con l'Expansion nella stessa barra (nessuna / concorde / discorde)
input ENUM_SD_REQ Inp_ADXReq    = SDE_REQ_IGNORE; // ADX >= soglia: ignora / richiedi PASSATO / richiedi FALLITO
input ENUM_SD_REQ Inp_SRReq     = SDE_REQ_IGNORE; // filtro S/R: ignora / richiedi PASSATO / richiedi FALLITO
input bool   Inp_SRDirAware     = false;  // S/R direzionale (BUY vicino a supporto o sopra resistenza, SELL il contrario) invece che simmetrico
input int    Inp_IntensityMin   = 0;      // intensita' minima candela (TR/ATR): 0..5, vedi Inp_CompTh e Inp_ExpThreshold
input int    Inp_IntensityMax   = 5;      // intensita' massima candela
input bool   Inp_Invert         = false;  // true = opera il verso OPPOSTO a quello del segnale (lettura INVERTI)

input group "=== MOTORE DEL SEGNALE (impostazioni indicatore: NON ottimizzare ora) ==="
input int    Inp_EmaPeriod      = 13;     // EmaPeriod
input int    Inp_VolAvgPeriod   = 20;     // VolAvgPeriod
input double Inp_Threshold      = 0.15;   // SignalThreshold
input int    Inp_ATRPeriod      = 14;     // ATR: validita' dato, prossimita' S/R e distanze SL/TP/trailing
input int    Inp_ADXPeriod      = 14;     // ADX_Period
input double Inp_ADXMin         = 20.0;   // ADX_MinLevel
input int    Inp_SRLookback     = 15;     // SR_Lookback
input double Inp_SRProximity    = 0.5;    // SR_Proximity (moltiplicatore ATR)
input int    Inp_ExpATRPeriod   = 14;     // ATR dedicato al rapporto TR/ATR dell'Expansion
input double Inp_ExpThreshold   = 1.8;    // soglia TR/ATR di espansione
input int    Inp_ExpConfirmOffset = 0;    // barre di conferma dopo l'espansione (0 = colore della candela di espansione)
input double Inp_CompTh         = 0.5;    // soglia TR/ATR di compressione (solo per le classi di intensita')
input int    Inp_RunGapBars     = 0;      // barre senza segnale che chiudono la raffica (0 = solo segnale opposto)

input group "=== ESECUZIONE: LOTTO FISSO, TUTTO IN ATR ==="
input double Inp_Lot            = 0.01;   // lotto fisso
input double Inp_TrailStep      = 0.05;   // aggiorna lo SL solo se migliora di almeno questi ATR
input double Inp_MaxSpreadATR   = 0.0;    // 0 = off. Salta il segnale se spread > questa frazione di ATR (es. 0.15)
input int    Inp_MaxSpreadPts   = 0;      // 0 = off. Salta il segnale se spread > N punti
input int    Inp_Slippage       = 30;     // deviazione massima in punti
input int    Inp_Magic          = 20202;  // magic number

input group "=== PROFILO ESECUZIONE: segnali DELTA (0 = disattivato per TP, trailing, tempo) ==="
input double Inp_D_SL           = 1.5;    // SL in ATR (> 0)
input double Inp_D_TP           = 3.0;    // TP in ATR (0 = nessun TP)
input bool   Inp_D_TrailOn      = true;   // trailing attivo
input double Inp_D_TrailStart   = 1.0;    // profitto in ATR da cui parte il trailing
input double Inp_D_TrailDist    = 0.75;   // distanza del trailing dal prezzo, in ATR
input int    Inp_D_MaxBars      = 0;      // chiudi dopo N barre (0 = off): terza barriera, stop a tempo

input group "=== PROFILO ESECUZIONE: segnali EXP_ADDED ==="
input double Inp_E_SL           = 1.5;    // SL in ATR (> 0)
input double Inp_E_TP           = 3.0;    // TP in ATR (0 = nessun TP)
input bool   Inp_E_TrailOn      = true;   // trailing attivo
input double Inp_E_TrailStart   = 1.0;    // profitto in ATR da cui parte il trailing
input double Inp_E_TrailDist    = 0.75;   // distanza del trailing dal prezzo, in ATR
input int    Inp_E_MaxBars      = 0;      // chiudi dopo N barre (0 = off)

input group "=== OTTIMIZZAZIONE / MISURA ==="
input ENUM_SD_FIT Inp_FitMode   = SDE_FIT_T_R;    // metrica restituita a OnTester
input int    Inp_FitMinTrades   = 30;     // sotto questo numero di trade la metrica positiva viene ridotta (quadraticamente)
input double Inp_ExtraCostPts   = 0.0;    // costo extra per trade in PUNTI (commissione + slippage) sottratto da R. Lo spread e' gia' nei prezzi

input group "=== LOG / REPORT (solo test singolo, mai in ottimizzazione) ==="
input bool   Inp_LogSignals     = false;  // scrive ogni segnale con le sue etichette in Common\Files\SDv2_signals_*.csv
input bool   Inp_LogTrades      = true;   // scrive i trade con R e etichette in Common\Files\SDv2_trades_*.csv
input bool   Inp_WriteClassMap  = true;   // scrive la tabella ID -> etichetta delle classi
input bool   Inp_Debug          = false;  // log a video

//+------------------------------------------------------------------+
//| STRUTTURE E GLOBALI                                               |
//+------------------------------------------------------------------+
struct SigTag
  {
   datetime time;     // apertura della barra d'ingresso (shift s-1)
   int      src;      // SD_SRC_DELTA / SD_SRC_EXP
   int      dir;      // +1 BUY / -1 SELL (verso del segnale)
   int      exprel;   // solo DELTA: 0 nessuna, 1 Expansion concorde, 2 discorde
   int      burst;    // posizione nella raffica (>=1, max 255)
   int      bucket;   // fascia oraria
   int      hour;     // ora (server + offset)
   int      dow;      // giorno settimana (0 = Dom)
   int      intens;   // classe di intensita' TR/ATR 0..5
   double   nd;       // delta normalizzato
   double   adx;      // valore ADX
   bool     adxPass;  // ADX >= soglia
   bool     srSym;    // filtro S/R simmetrico passato
   bool     srDir;    // filtro S/R direzionale passato
   double   atr;      // ATR (prezzo) alla chiusura della barra del segnale
  };

int    g_hEma = INVALID_HANDLE;
int    g_hAtr = INVALID_HANDLE;
int    g_hAdx = INVALID_HANDLE;
int    g_hAtrExp = INVALID_HANDLE;

double g_point = 0.0;
int    g_digits = 5;
long   g_stopsLevel = 0;
double g_lotMin = 0.01, g_lotMax = 100.0, g_lotStep = 0.01;
int    g_lotDigits = 2;
bool   g_isOptim = false, g_isTester = false;
long   g_offSec = 0;

int    g_bucketMin = 240, g_nB = 6, g_nClasses = 0;
int    g_cSrc = 0, g_cDir = 0, g_cBurst = 0, g_cHour = 0;   // classe decodificata (0 = ANY)
bool   g_hourMask[];
bool   g_dowMask[];
double g_ibEdge[5];

//--- dati barre (serie: indice 0 = barra in formazione, 1 = ultima chiusa)
MqlRates g_rates[];
double g_ema[], g_atr[], g_adx[], g_atrExp[];
int    g_n = 0, g_nb = 0, g_reach = 0;

//--- stato dei motori
bool     g_expPending = false;
int      g_expAge = 0;
int      g_runDirD = 0, g_runCntD = 0, g_gapD = 0;   // raffica del flusso Delta
int      g_runDirO = 0, g_runCntO = 0, g_gapO = 0;   // raffica del flusso Delta+Expansion (OR)
datetime g_lastBar = 0;

//--- profili di esecuzione: indice 0 = DELTA, 1 = EXP_ADDED
double g_pSL[2], g_pTP[2], g_pTrS[2], g_pTrD[2];
int    g_pMax[2];
bool   g_pTrOn[2];

//--- posizione corrente
bool   g_hasPos = false;
double g_posAtr = 0.0;
int    g_posProf = 0;
int    g_posBars = 0;

//--- registro dei trade aperti (array paralleli, un elemento per trade)
int      g_nRec = 0;
ulong    g_rPos[];
double   g_rSlDist[];
double   g_rAtr[];
double   g_rSpr[];
int      g_rSrc[], g_rDir[], g_rTdir[], g_rBucket[], g_rBurst[], g_rHour[], g_rDow[];
datetime g_rTime[];

//--- risultati calcolati da CollectResults
double g_stN = 0.0, g_stS = 0.0, g_stS2 = 0.0, g_stW = 0.0;

//--- file
int    g_fhSig = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| UTILITA'                                                          |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING PickFilling()
  {
   long modes = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((modes & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((modes & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

int SnapBucket(const int req)
  {
   int valid[] = {5, 10, 15, 20, 30, 60, 120, 180, 240, 360, 480, 720, 1440};
   int best = 240, bestDiff = 1000000;
   for(int i = 0; i < ArraySize(valid); i++)
     {
      int d = MathAbs(valid[i] - req);
      if(d < bestDiff) { bestDiff = d; best = valid[i]; }
     }
   return best;
  }

//--- maschera da lista tipo "7-11,13,15-17" sull'intervallo [lo, hi]; stringa vuota = tutto ammesso
void ParseMask(const string src, bool &mask[], const int lo, const int hi)
  {
   ArrayResize(mask, hi - lo + 1);
   string s = src;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(s == "")
     {
      ArrayInitialize(mask, true);
      return;
     }
   ArrayInitialize(mask, false);
   string parts[];
   int np = StringSplit(s, ',', parts);
   for(int i = 0; i < np; i++)
     {
      string p = parts[i];
      StringTrimLeft(p);
      StringTrimRight(p);
      if(p == "") continue;
      int dash = StringFind(p, "-");
      if(dash > 0)
        {
         int a = (int)StringToInteger(StringSubstr(p, 0, dash));
         int b = (int)StringToInteger(StringSubstr(p, dash + 1));
         if(a < lo || a > hi || b < lo || b > hi) continue;
         if(a <= b)
           {
            for(int v = a; v <= b; v++) mask[v - lo] = true;
           }
         else
           {
            for(int v = a; v <= hi; v++) mask[v - lo] = true;
            for(int v = lo; v <= b; v++) mask[v - lo] = true;
           }
        }
      else
        {
         int v1 = (int)StringToInteger(p);
         if(v1 >= lo && v1 <= hi) mask[v1 - lo] = true;
        }
     }
  }

bool MaskHasAny(const bool &mask[])
  {
   for(int i = 0; i < ArraySize(mask); i++)
      if(mask[i]) return true;
   return false;
  }

double NormalizeLots(double lots)
  {
   lots = MathFloor(lots / g_lotStep) * g_lotStep;
   lots = MathMax(g_lotMin, MathMin(g_lotMax, lots));
   return NormalizeDouble(lots, g_lotDigits);
  }

string BucketLabel(const int b)
  {
   int s = b * g_bucketMin;
   int e = s + g_bucketMin;
   return StringFormat("%02d:%02d-%02d:%02d", s / 60, s % 60, e / 60, e % 60);
  }

string SrcName(const int src) { return (src == SD_SRC_DELTA) ? "DELTA" : "EXP_ADDED"; }

int ColorDir(const double o, const double c)
  {
   if(c > o) return 1;
   if(c < o) return -1;
   return 0;
  }

//--- classe di intensita' della candela (TR/ATR) rispetto a 5 soglie crescenti
int IntensityBin(const double ratio)
  {
   int b = 0;
   while(b < 5 && ratio >= g_ibEdge[b]) b++;
   return b;
  }

//+------------------------------------------------------------------+
//| CLASSI                                                            |
//+------------------------------------------------------------------+
void DecodeClass(int id, int &src, int &dir, int &burst, int &hour)
  {
   const int nh = g_nB + 1;
   hour  = id % nh;  id /= nh;
   burst = id % 5;   id /= 5;
   dir   = id % 3;   id /= 3;
   src   = id % 3;
  }

string ClassLabel(const int id)
  {
   int s, d, b, h;
   DecodeClass(id, s, d, b, h);
   string ss = (s == 0) ? "ANY" : ((s == 1) ? "DELTA" : "EXP_ADDED");
   string ds = (d == 0) ? "ANY" : ((d == 1) ? "BUY" : "SELL");
   string bs = (b == 0) ? "ANY" : ((b == 4) ? "4+" : IntegerToString(b));
   string hs = (h == 0) ? "ANY" : BucketLabel(h - 1);
   return "src=" + ss + " dir=" + ds + " burst=" + bs + " hour=" + hs;
  }

void WriteClassMap()
  {
   int fh = FileOpen("SDv2_classmap_" + IntegerToString(g_bucketMin) + "m.csv",
                     FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(fh == INVALID_HANDLE)
     {
      Print("Class map non scrivibile, errore ", GetLastError());
      return;
     }
   FileWrite(fh, "ClassID", "Source", "Direction", "Burst", "Hour");
   for(int id = 0; id < g_nClasses; id++)
     {
      int s, d, b, h;
      DecodeClass(id, s, d, b, h);
      FileWrite(fh, id,
                (s == 0) ? "ANY" : ((s == 1) ? "DELTA" : "EXP_ADDED"),
                (d == 0) ? "ANY" : ((d == 1) ? "BUY" : "SELL"),
                (b == 0) ? "ANY" : ((b == 4) ? "4+" : IntegerToString(b)),
                (h == 0) ? "ANY" : BucketLabel(h - 1));
     }
   FileClose(fh);
   Print("Class map scritta: Common\\Files\\SDv2_classmap_", g_bucketMin, "m.csv (", g_nClasses, " classi)");
  }

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_isOptim  = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_isTester = (bool)MQLInfoInteger(MQL_TESTER);
   g_offSec   = (long)Inp_TimeOffsetH * 3600;

   g_bucketMin = SnapBucket(Inp_BucketMin);
   g_nB        = 1440 / g_bucketMin;
   g_nClasses  = 45 * (g_nB + 1);

   //--- validazione input: in ottimizzazione un return INIT_PARAMETERS_INCORRECT salta la passata
   if(Inp_Lot <= 0.0 || Inp_D_SL <= 0.0 || Inp_E_SL <= 0.0)
     { Print("Input non validi: Inp_Lot e SL (ATR) devono essere > 0."); return INIT_PARAMETERS_INCORRECT; }
   if(Inp_EmaPeriod < 1 || Inp_VolAvgPeriod < 1 || Inp_ATRPeriod < 1 || Inp_ADXPeriod < 1 || Inp_ExpATRPeriod < 1)
     { Print("Input non validi: i periodi devono essere >= 1."); return INIT_PARAMETERS_INCORRECT; }
   if(Inp_ClassID >= g_nClasses)
     {
      if(!g_isOptim) Print("Inp_ClassID ", Inp_ClassID, " fuori range -1..", g_nClasses - 1, " per bucket ", g_bucketMin, " min.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(Inp_ClassID >= 0) DecodeClass(Inp_ClassID, g_cSrc, g_cDir, g_cBurst, g_cHour);
   else { g_cSrc = 0; g_cDir = 0; g_cBurst = 0; g_cHour = 0; }

   //--- costanti di simbolo
   g_point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   g_lotMin     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_lotMax     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_lotStep    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(g_lotStep <= 0.0) g_lotStep = 0.01;
   g_lotDigits  = (int)MathRound(-MathLog10(g_lotStep));
   if(g_lotDigits < 0) g_lotDigits = 0;
   if(g_point <= 0.0) { Print("Errore: SYMBOL_POINT non valido"); return INIT_FAILED; }

   //--- profili
   g_pSL[0] = Inp_D_SL; g_pTP[0] = Inp_D_TP; g_pTrOn[0] = Inp_D_TrailOn;
   g_pTrS[0] = Inp_D_TrailStart; g_pTrD[0] = Inp_D_TrailDist; g_pMax[0] = Inp_D_MaxBars;
   g_pSL[1] = Inp_E_SL; g_pTP[1] = Inp_E_TP; g_pTrOn[1] = Inp_E_TrailOn;
   g_pTrS[1] = Inp_E_TrailStart; g_pTrD[1] = Inp_E_TrailDist; g_pMax[1] = Inp_E_MaxBars;

   //--- maschere ore / giorni
   ParseMask(Inp_Hours, g_hourMask, 0, 23);
   ParseMask(Inp_Days,  g_dowMask,  0, 6);
   if(!MaskHasAny(g_hourMask) || !MaskHasAny(g_dowMask))
      Print("ATTENZIONE: Inp_Hours o Inp_Days non contengono nessun valore valido: l'EA non operera' mai.");

   //--- soglie di intensita' (ordinate)
   g_ibEdge[0] = Inp_CompTh;
   g_ibEdge[1] = 1.0;
   g_ibEdge[2] = 0.5 * (1.0 + Inp_ExpThreshold);
   g_ibEdge[3] = Inp_ExpThreshold;
   g_ibEdge[4] = 1.4 * Inp_ExpThreshold;
   ArraySort(g_ibEdge);

   //--- trade
   trade.SetExpertMagicNumber(Inp_Magic);
   trade.SetDeviationInPoints(Inp_Slippage);
   trade.SetTypeFilling(PickFilling());
   trade.SetAsyncMode(false);
   trade.LogLevel((Inp_Debug && !g_isOptim) ? LOG_LEVEL_ERRORS : LOG_LEVEL_NO);

   //--- indicatori
   g_hEma = iMA(_Symbol, PERIOD_CURRENT, Inp_EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hAtr = iATR(_Symbol, PERIOD_CURRENT, Inp_ATRPeriod);
   g_hAdx = iADX(_Symbol, PERIOD_CURRENT, Inp_ADXPeriod);
   g_hAtrExp = iATR(_Symbol, PERIOD_CURRENT, Inp_ExpATRPeriod);
   if(g_hEma == INVALID_HANDLE || g_hAtr == INVALID_HANDLE || g_hAdx == INVALID_HANDLE || g_hAtrExp == INVALID_HANDLE)
     { Print("Errore creazione handle indicatori: ", GetLastError()); return INIT_FAILED; }

   ArraySetAsSeries(g_rates,  true);
   ArraySetAsSeries(g_ema,    true);
   ArraySetAsSeries(g_atr,    true);
   ArraySetAsSeries(g_adx,    true);
   ArraySetAsSeries(g_atrExp, true);

   g_reach = MathMax(Inp_VolAvgPeriod, Inp_SRLookback + 1) + 2;

   //--- stato
   g_expPending = false; g_expAge = 0;
   g_runDirD = 0; g_runCntD = 0; g_gapD = 0;
   g_runDirO = 0; g_runCntO = 0; g_gapO = 0;
   g_hasPos = false; g_posAtr = 0.0; g_posProf = 0; g_posBars = 0;
   g_nRec = 0;
   g_lastBar = 0;

   AdoptPosition();
   PrimeState();
   g_lastBar = iTime(_Symbol, PERIOD_CURRENT, 0);   // la barra in formazione non va rielaborata

   //--- file
   if(!g_isOptim)
     {
      if(Inp_WriteClassMap) WriteClassMap();
      if(Inp_LogSignals) OpenSignalLog();
     }

   if(!g_isOptim)
     {
      ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      Print("============================================================");
      Print("SyntheticDelta EA v2.0 | ", _Symbol, " ", EnumToString((ENUM_TIMEFRAMES)Period()),
            " | conto ", (mm == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) ? "HEDGING" : "NETTING/EXCHANGE");
      if(Inp_ClassID >= 0)
         Print("Classe ", Inp_ClassID, " di ", g_nClasses, ": ", ClassLabel(Inp_ClassID));
      else
         Print("Nessuna classe (ID -1): filtri manuali Src=", EnumToString(Inp_SrcSel), " Dir=", EnumToString(Inp_DirSel),
               " Burst=", Inp_BurstMin, "-", Inp_BurstMax);
      Print("Fasce orarie: ", g_nB, " da ", g_bucketMin, " min | invert=", Inp_Invert ? "SI" : "no",
            " | StopsLevel=", g_stopsLevel, " pt | lotto ", DoubleToString(NormalizeLots(Inp_Lot), g_lotDigits));
      Print("DELTA: SL ", Inp_D_SL, " TP ", Inp_D_TP, " trail ", Inp_D_TrailOn ? "ON" : "off",
            " | EXP_ADDED: SL ", Inp_E_SL, " TP ", Inp_E_TP, " trail ", Inp_E_TrailOn ? "ON" : "off");
      Print("============================================================");
     }
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_hEma    != INVALID_HANDLE) IndicatorRelease(g_hEma);
   if(g_hAtr    != INVALID_HANDLE) IndicatorRelease(g_hAtr);
   if(g_hAdx    != INVALID_HANDLE) IndicatorRelease(g_hAdx);
   if(g_hAtrExp != INVALID_HANDLE) IndicatorRelease(g_hAtrExp);
   if(g_fhSig != INVALID_HANDLE) { FileClose(g_fhSig); g_fhSig = INVALID_HANDLE; }
  }

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(g_hasPos) ManagePosition();

   const datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur == g_lastBar) return;
   g_lastBar = cur;

   if(g_hasPos) OnNewBarPosition();

   if(!PrepareData(g_reach + 8, 5)) return;

   SigTag tag;
   if(!EvalBar(1, tag)) return;

   int reason = GateReason(tag);
   if(reason == 0) reason = TryEnter(tag);

   if(g_fhSig != INVALID_HANDLE) LogSignal(tag, reason);
  }

//+------------------------------------------------------------------+
//| PrepareData - copia barre e buffer (serie)                        |
//+------------------------------------------------------------------+
bool PrepareData(const int nRates, const int nBuf)
  {
   g_n = CopyRates(_Symbol, PERIOD_CURRENT, 0, nRates, g_rates);
   if(g_n <= 0) { g_n = 0; return false; }
   const int c1 = CopyBuffer(g_hAtr,    0, 0, nBuf, g_atr);
   const int c2 = CopyBuffer(g_hEma,    0, 0, nBuf, g_ema);
   const int c3 = CopyBuffer(g_hAdx,    0, 0, nBuf, g_adx);
   const int c4 = CopyBuffer(g_hAtrExp, 0, 0, nBuf, g_atrExp);
   g_nb = MathMin(MathMin(c1, c2), MathMin(c3, c4));
   return (g_nb > 1 && g_n > 5);
  }

//+------------------------------------------------------------------+
//| PrimeState - rielabora le ultime barre per ricostruire raffica e  |
//| stato dell'Expansion (utile ai riavvii in live; nel tester parte  |
//| dalla storia precedente la data iniziale, se presente).           |
//+------------------------------------------------------------------+
void PrimeState()
  {
   const int primeBars = 300;
   if(!PrepareData(primeBars + g_reach + 5, primeBars + 5)) return;
   SigTag tmp;
   for(int s = primeBars; s >= 1; s--)
      EvalBar(s, tmp);
  }

//+------------------------------------------------------------------+
//| UpdateRun - raffica: segnali consecutivi nello stesso verso       |
//+------------------------------------------------------------------+
void UpdateRun(const int d, int &runDir, int &runCnt, int &gap)
  {
   if(d == 0)
     {
      gap++;
      if(Inp_RunGapBars > 0 && gap >= Inp_RunGapBars) { runDir = 0; runCnt = 0; }
     }
   else
     {
      gap = 0;
      if(d == runDir) runCnt++;
      else { runDir = d; runCnt = 1; }
     }
  }

void ClearTag(SigTag &t)
  {
   t.time = 0; t.src = -1; t.dir = 0; t.exprel = 0; t.burst = 0;
   t.bucket = 0; t.hour = 0; t.dow = 0; t.intens = 0;
   t.nd = 0.0; t.adx = 0.0; t.adxPass = false; t.srSym = false; t.srDir = false;
   t.atr = 0.0;
  }

//+------------------------------------------------------------------+
//| EvalBar - calcola il segnale della barra CHIUSA a shift s.        |
//| Aggiorna SEMPRE gli stati (Expansion pending, raffiche), anche    |
//| quando non c'e' segnale. Ritorna true se c'e' un segnale emesso.  |
//| Logica Delta / Expansion identica a v1.13 e a SD_Core (SignalLab).|
//+------------------------------------------------------------------+
bool EvalBar(const int s, SigTag &tag)
  {
   ClearTag(tag);
   if(s < 1) return false;
   if(s + g_reach >= g_n) return false;
   if(s >= g_nb) return false;

   const double hi = g_rates[s].high;
   const double lo = g_rates[s].low;
   const double cl = g_rates[s].close;
   const double op = g_rates[s].open;
   const double range = hi - lo;
   const double atr  = g_atr[s];
   const double atrE = g_atrExp[s];

   //--- 1) Synthetic Delta
   int dD = 0;
   double nd = 0.0;
   const double tv = (double)g_rates[s].tick_volume;
   if(range > 0.0 && tv > 0.0 && atr > 0.0 && g_ema[s] > 0.0)
     {
      const double ema = g_ema[s];
      const double fracBuy   = (cl - lo) / range;
      const double fracSell  = (hi - cl) / range;
      const double bullsNorm = (hi - ema) / range;
      const double bearsNorm = (ema - lo) / range;
      double volSum = 0.0;
      int volCount = 0;
      for(int j = s; j < s + Inp_VolAvgPeriod && j < g_n; j++)
        { volSum += (double)g_rates[j].tick_volume; volCount++; }
      const double volAvg    = (volCount > 0) ? volSum / volCount : tv;
      const double volWeight = (volAvg > 0.0) ? MathMin(tv / volAvg, 3.0) : 1.0;
      const double synDelta  = fracBuy * (1.0 + bullsNorm) * volWeight - fracSell * (1.0 + bearsNorm) * volWeight;
      nd = synDelta / 6.0;
      if(nd > Inp_Threshold)       dD = 1;
      else if(nd < -Inp_Threshold) dD = -1;
     }

   //--- 2) Expansion Candle (macchina a stati: va avanzata ad OGNI barra)
   int dE = 0;
   int intens = 0;
   double trAtr = 0.0;
   if(atrE > 0.0)
     {
      const double prevClose = g_rates[s + 1].close;
      const double tr = MathMax(range, MathMax(MathAbs(hi - prevClose), MathAbs(lo - prevClose)));
      trAtr  = tr / atrE;
      intens = IntensityBin(trAtr);
     }
   if(g_expPending)
     {
      g_expAge++;
      if(g_expAge == Inp_ExpConfirmOffset)
        { g_expPending = false; dE = ColorDir(op, cl); }
      else if(g_expAge > Inp_ExpConfirmOffset)
         g_expPending = false;
     }
   else if(atrE > 0.0 && trAtr > Inp_ExpThreshold)
     {
      if(Inp_ExpConfirmOffset == 0) dE = ColorDir(op, cl);
      else { g_expPending = true; g_expAge = 0; }
     }

   //--- 3) raffiche (flusso Delta, e flusso Delta+Expansion: discordi = annullato)
   int flowO = 0;
   if(dD != 0 && dE != 0 && dD != dE) flowO = 0;
   else flowO = (dD != 0) ? dD : dE;
   UpdateRun(dD,    g_runDirD, g_runCntD, g_gapD);
   UpdateRun(flowO, g_runDirO, g_runCntO, g_gapO);

   //--- 4) segnale emesso: Delta, altrimenti Expansion (serie EXP_ADDED)
   int src = -1;
   int dir = 0;
   if(dD != 0)      { src = SD_SRC_DELTA; dir = dD; }
   else if(dE != 0) { src = SD_SRC_EXP;   dir = dE; }
   if(src < 0) return false;
   if(atr <= 0.0) return false;

   tag.src    = src;
   tag.dir    = dir;
   tag.nd     = nd;
   tag.intens = intens;
   tag.atr    = atr;
   tag.exprel = (src == SD_SRC_DELTA) ? ((dE == 0) ? 0 : ((dE == dD) ? 1 : 2)) : 0;
   tag.burst  = (src == SD_SRC_DELTA) ? g_runCntD : g_runCntO;
   if(tag.burst > 255) tag.burst = 255;
   if(tag.burst < 1)   tag.burst = 1;

   //--- 5) etichette ADX e S/R (non filtrano: si misurano)
   tag.adx     = g_adx[s];
   tag.adxPass = (tag.adx >= Inp_ADXMin);

   double res = g_rates[s + 1].high;
   double sup = g_rates[s + 1].low;
   for(int k = s + 1; k <= s + Inp_SRLookback && k < g_n; k++)
     {
      if(g_rates[k].high > res) res = g_rates[k].high;
      if(g_rates[k].low  < sup) sup = g_rates[k].low;
     }
   const double prox = atr * Inp_SRProximity;
   const bool nearR  = (MathAbs(cl - res) <= prox);
   const bool nearS  = (MathAbs(cl - sup) <= prox);
   const bool aboveR = (cl > res);
   const bool belowS = (cl < sup);
   tag.srSym = (nearR || nearS || aboveR || belowS);
   tag.srDir = (dir > 0) ? (nearS || aboveR) : (nearR || belowS);

   //--- 6) tempo (server + offset) della barra d'ingresso
   tag.time = g_rates[s - 1].time;
   MqlDateTime dt;
   TimeToStruct((datetime)((long)tag.time + g_offSec), dt);
   tag.hour   = dt.hour;
   tag.dow    = dt.day_of_week;
   tag.bucket = (dt.hour * 60 + dt.min) / g_bucketMin;
   if(tag.bucket >= g_nB) tag.bucket = g_nB - 1;
   return true;
  }

//+------------------------------------------------------------------+
//| GateReason - 0 se il segnale appartiene alla classe operata.      |
//| 1 = sorgente/verso/raffica/fascia, 2 = ore o giorni, 3 = filtri.  |
//+------------------------------------------------------------------+
int GateReason(const SigTag &t)
  {
   //--- classe da scansione
   if(g_cSrc != 0 && t.src != g_cSrc - 1) return 1;
   if(g_cDir != 0 && t.dir != ((g_cDir == 1) ? 1 : -1)) return 1;
   if(g_cBurst != 0)
     {
      if(g_cBurst < 4) { if(t.burst != g_cBurst) return 1; }
      else             { if(t.burst < 4) return 1; }
     }
   if(g_cHour != 0 && t.bucket != g_cHour - 1) return 1;

   //--- filtri manuali
   if(Inp_SrcSel != SDE_SRC_ANY && t.src != (int)Inp_SrcSel - 1) return 1;
   if(Inp_DirSel != SDE_DIR_ANY && t.dir != ((Inp_DirSel == SDE_DIR_BUY) ? 1 : -1)) return 1;
   if(t.burst < Inp_BurstMin || t.burst > Inp_BurstMax) return 1;

   if(!g_hourMask[t.hour] || !g_dowMask[t.dow]) return 2;

   if(t.src == SD_SRC_DELTA)
     {
      if(Inp_ExpRel == SDE_EXPREL_NONE      && t.exprel != 0) return 3;
      if(Inp_ExpRel == SDE_EXPREL_AGREE     && t.exprel != 1) return 3;
      if(Inp_ExpRel == SDE_EXPREL_NOCONFLICT && t.exprel == 2) return 3;
     }
   if(Inp_ADXReq == SDE_REQ_PASS && !t.adxPass) return 3;
   if(Inp_ADXReq == SDE_REQ_FAIL &&  t.adxPass) return 3;
   const bool srOk = Inp_SRDirAware ? t.srDir : t.srSym;
   if(Inp_SRReq == SDE_REQ_PASS && !srOk) return 3;
   if(Inp_SRReq == SDE_REQ_FAIL &&  srOk) return 3;
   if(t.intens < Inp_IntensityMin || t.intens > Inp_IntensityMax) return 3;
   return 0;
  }

//+------------------------------------------------------------------+
//| Posizioni                                                         |
//+------------------------------------------------------------------+
ulong FindOurPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_Magic) continue;
      return t;
     }
   return 0;
  }

bool HavePosition() { return (FindOurPosition() != 0); }

void ClosePosition()
  {
   const ulong t = FindOurPosition();
   if(t == 0) { g_hasPos = false; return; }
   if(!trade.PositionClose(t) && !g_isOptim)
      Print("Errore chiusura posizione: ", trade.ResultRetcode(), " - ", trade.ResultRetcodeDescription());
  }

void AdoptPosition()
  {
   const ulong t = FindOurPosition();
   if(t == 0) return;
   g_hasPos = true;
   const string cm = PositionGetString(POSITION_COMMENT);
   g_posProf = (StringFind(cm, "_E") >= 0) ? 1 : 0;
   const long ps = PeriodSeconds(PERIOD_CURRENT);
   const datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
   g_posBars = (ps > 0) ? (int)(((long)TimeCurrent() - (long)ot) / ps) : 0;
   g_posAtr = 0.0;   // ricalcolato al primo tick (ATR corrente: approssimazione)
   if(!g_isOptim) Print("Posizione esistente adottata (profilo ", g_posProf == 0 ? "DELTA" : "EXP_ADDED", ", barre ", g_posBars, ")");
  }

void LazyAtr()
  {
   double a[];
   ArraySetAsSeries(a, true);
   if(CopyBuffer(g_hAtr, 0, 1, 1, a) > 0) g_posAtr = a[0];
  }

//--- chiamata alla prima tick di ogni nuova barra con posizione aperta: stop a tempo
void OnNewBarPosition()
  {
   if(!HavePosition()) { g_hasPos = false; return; }
   g_posBars++;
   const int mb = g_pMax[g_posProf];
   if(mb > 0 && g_posBars >= mb) ClosePosition();
  }

//--- trailing in ATR (distanze congelate all'ingresso), ad ogni tick
void ManagePosition()
  {
   const ulong ticket = FindOurPosition();
   if(ticket == 0) { g_hasPos = false; return; }
   if(!g_pTrOn[g_posProf]) return;
   if(g_posAtr <= 0.0) { LazyAtr(); if(g_posAtr <= 0.0) return; }

   const ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   const double openPx = PositionGetDouble(POSITION_PRICE_OPEN);
   const double oldSL  = PositionGetDouble(POSITION_SL);
   const double curTP  = PositionGetDouble(POSITION_TP);
   const double startD = g_pTrS[g_posProf] * g_posAtr;
   const double stepD  = Inp_TrailStep * g_posAtr;
   const double minStop = (double)g_stopsLevel * g_point;
   const double distD  = MathMax(g_pTrD[g_posProf] * g_posAtr, minStop);

   if(ptype == POSITION_TYPE_BUY)
     {
      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid - openPx < startD) return;
      const double newSL = NormalizeDouble(bid - distD, g_digits);
      if(oldSL == 0.0 || newSL - oldSL >= stepD)
         trade.PositionModify(ticket, newSL, curTP);
     }
   else
     {
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(openPx - ask < startD) return;
      const double newSL = NormalizeDouble(ask + distD, g_digits);
      if(oldSL == 0.0 || oldSL - newSL >= stepD)
         trade.PositionModify(ticket, newSL, curTP);
     }
  }

//+------------------------------------------------------------------+
//| TryEnter - gate di esecuzione e apertura. 0 = trade aperto.       |
//| 4 = posizione gia' aperta, 5 = spread, 6 = ordine rifiutato,      |
//| 7 = ATR non valido.                                               |
//+------------------------------------------------------------------+
int TryEnter(const SigTag &tag)
  {
   if(HavePosition()) return 4;

   const double atr = tag.atr;
   if(atr <= 0.0) return 7;

   const long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(Inp_MaxSpreadPts > 0 && spreadPts > Inp_MaxSpreadPts) return 5;
   if(Inp_MaxSpreadATR > 0.0 && (double)spreadPts * g_point > Inp_MaxSpreadATR * atr) return 5;

   const int  tdir  = Inp_Invert ? -tag.dir : tag.dir;
   const bool isBuy = (tdir > 0);
   const int  pi    = (tag.src == SD_SRC_DELTA) ? 0 : 1;

   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return 6;
   const double price = isBuy ? ask : bid;

   //--- distanze: SL almeno stops level + spread (lo SL si misura dal lato opposto)
   const double minStop = (double)g_stopsLevel * g_point;
   double slDist = g_pSL[pi] * atr;
   slDist = MathMax(slDist, minStop + (ask - bid));
   double tpDist = g_pTP[pi] * atr;
   if(tpDist > 0.0) tpDist = MathMax(tpDist, minStop);

   const double sl = NormalizeDouble(isBuy ? price - slDist : price + slDist, g_digits);
   double tp = 0.0;
   if(tpDist > 0.0) tp = NormalizeDouble(isBuy ? price + tpDist : price - tpDist, g_digits);
   const double slReal = MathAbs(price - sl);
   if(slReal <= 0.0) return 6;

   const double lots = NormalizeLots(Inp_Lot);
   const string comment = (pi == 0) ? "SDv2_D" : "SDv2_E";

   const bool ok = isBuy ? trade.Buy(lots, _Symbol, price, sl, tp, comment)
                         : trade.Sell(lots, _Symbol, price, sl, tp, comment);
   const uint rc = trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_DONE_PARTIAL && rc != TRADE_RETCODE_PLACED))
     {
      if(!g_isOptim && Inp_Debug)
         Print("Errore apertura: ", rc, " - ", trade.ResultRetcodeDescription());
      return 6;
     }

   //--- position id dal deal di apertura (come v1.13)
   ulong posId = 0;
   const ulong dealTicket = trade.ResultDeal();
   if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      posId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   if(posId == 0) posId = trade.ResultOrder();

   g_hasPos  = true;
   g_posAtr  = atr;
   g_posProf = pi;
   g_posBars = 0;

   AddRec(posId, slReal, tag, tdir, (double)spreadPts);

   if(Inp_Debug && !g_isOptim)
      Print("APERTURA ", isBuy ? "BUY" : "SELL", " ", SrcName(tag.src), " burst=", tag.burst,
            " @", DoubleToString(price, g_digits), " SL=", DoubleToString(sl, g_digits),
            " TP=", (tp > 0.0) ? DoubleToString(tp, g_digits) : "OFF", " ATR=", DoubleToString(atr, g_digits));
   return 0;
  }

//+------------------------------------------------------------------+
//| Registro dei trade                                                |
//+------------------------------------------------------------------+
void AddRec(const ulong posId, const double slDist, const SigTag &tag, const int tdir, const double spr)
  {
   const int k = g_nRec + 1;
   ArrayResize(g_rPos,    k, 512);
   ArrayResize(g_rSlDist, k, 512);
   ArrayResize(g_rAtr,    k, 512);
   ArrayResize(g_rSpr,    k, 512);
   ArrayResize(g_rSrc,    k, 512);
   ArrayResize(g_rDir,    k, 512);
   ArrayResize(g_rTdir,   k, 512);
   ArrayResize(g_rBucket, k, 512);
   ArrayResize(g_rBurst,  k, 512);
   ArrayResize(g_rHour,   k, 512);
   ArrayResize(g_rDow,    k, 512);
   ArrayResize(g_rTime,   k, 512);
   g_rPos[g_nRec]    = posId;
   g_rSlDist[g_nRec] = slDist;
   g_rAtr[g_nRec]    = tag.atr;
   g_rSpr[g_nRec]    = spr;
   g_rSrc[g_nRec]    = tag.src;
   g_rDir[g_nRec]    = tag.dir;
   g_rTdir[g_nRec]   = tdir;
   g_rBucket[g_nRec] = tag.bucket;
   g_rBurst[g_nRec]  = tag.burst;
   g_rHour[g_nRec]   = tag.hour;
   g_rDow[g_nRec]    = tag.dow;
   g_rTime[g_nRec]   = TimeCurrent();
   g_nRec = k;
  }

int FindRec(const ulong pid, int &hint)
  {
   if(hint < g_nRec && g_rPos[hint] == pid) { const int r = hint; hint++; return r; }
   for(int i = 0; i < g_nRec; i++)
      if(g_rPos[i] == pid) { hint = i + 1; return i; }
   return -1;
  }

//+------------------------------------------------------------------+
//| Log dei segnali                                                   |
//+------------------------------------------------------------------+
void OpenSignalLog()
  {
   const string name = "SDv2_signals_" + _Symbol + "_" + EnumToString((ENUM_TIMEFRAMES)Period()) + ".csv";
   g_fhSig = FileOpen(name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(g_fhSig == INVALID_HANDLE) { Print("Signal log non scrivibile, errore ", GetLastError()); return; }
   FileWrite(g_fhSig, "time", "source", "dir", "exprel", "burst", "bucket", "hour", "dow", "nd",
             "adx", "adxPass", "srSym", "srDir", "intensity", "atrPts", "spreadPts", "reason");
  }

void LogSignal(const SigTag &t, const int reason)
  {
   FileWrite(g_fhSig, TimeToString(t.time, TIME_DATE | TIME_MINUTES), SrcName(t.src), t.dir, t.exprel, t.burst,
             BucketLabel(t.bucket), t.hour, t.dow, DoubleToString(t.nd, 4), DoubleToString(t.adx, 1),
             (int)t.adxPass, (int)t.srSym, (int)t.srDir, t.intens, DoubleToString(t.atr / g_point, 0),
             (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD), reason);
  }

//+------------------------------------------------------------------+
//| CollectResults - R di ogni trade chiuso, dallo storico deal.      |
//| R = (uscita - entrata) * verso / distanza SL - costo extra / SL.  |
//| I trade sono sequenziali (uno per volta): l'i-esimo deal di       |
//| ingresso corrisponde all'i-esimo record, verificato col position  |
//| id.                                                               |
//+------------------------------------------------------------------+
void CollectResults(const bool detail)
  {
   g_stN = 0.0; g_stS = 0.0; g_stS2 = 0.0; g_stW = 0.0;

   double bN[], bS[];
   ArrayResize(bN, g_nB);
   ArrayResize(bS, g_nB);
   ArrayInitialize(bN, 0.0);
   ArrayInitialize(bS, 0.0);
   double sdN[4], sdS[4];
   ArrayInitialize(sdN, 0.0);
   ArrayInitialize(sdS, 0.0);

   int fh = INVALID_HANDLE;
   if(detail && Inp_LogTrades)
     {
      const string name = "SDv2_trades_" + _Symbol + "_" + EnumToString((ENUM_TIMEFRAMES)Period()) + ".csv";
      fh = FileOpen(name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
      if(fh == INVALID_HANDLE) Print("Trade log non scrivibile, errore ", GetLastError());
      else FileWrite(fh, "openTime", "closeTime", "source", "signalDir", "tradeDir", "burst", "bucket", "hour", "dow",
                     "atrPts", "slPts", "spreadPts", "entry", "exit", "R", "moneyProfit");
     }

   if(!HistorySelect(0, TimeCurrent())) { if(fh != INVALID_HANDLE) FileClose(fh); return; }
   const int total = HistoryDealsTotal();

   int    cur = -1, hint = 0;
   double entryPx = 0.0;
   datetime entryTime = 0;

   for(int i = 0; i < total; i++)
     {
      const ulong dt = HistoryDealGetTicket(i);
      if(dt == 0) continue;
      if(HistoryDealGetString(dt, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(dt, DEAL_MAGIC) != Inp_Magic) continue;
      const ENUM_DEAL_ENTRY en = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt, DEAL_ENTRY);
      const ulong pid = (ulong)HistoryDealGetInteger(dt, DEAL_POSITION_ID);

      if(en == DEAL_ENTRY_IN)
        {
         cur = FindRec(pid, hint);
         entryPx = HistoryDealGetDouble(dt, DEAL_PRICE);
         entryTime = (datetime)HistoryDealGetInteger(dt, DEAL_TIME);
        }
      else if(en == DEAL_ENTRY_OUT || en == DEAL_ENTRY_OUT_BY)
        {
         if(cur < 0) continue;
         const double exitPx = HistoryDealGetDouble(dt, DEAL_PRICE);
         const double sl = g_rSlDist[cur];
         if(sl <= 0.0) { cur = -1; continue; }
         const double move = (g_rTdir[cur] > 0) ? (exitPx - entryPx) : (entryPx - exitPx);
         const double r = move / sl - (Inp_ExtraCostPts * g_point) / sl;

         g_stN += 1.0; g_stS += r; g_stS2 += r * r;
         if(r > 0.0) g_stW += 1.0;
         const int b = g_rBucket[cur];
         if(b >= 0 && b < g_nB) { bN[b] += 1.0; bS[b] += r; }
         const int q = g_rSrc[cur] * 2 + ((g_rDir[cur] > 0) ? 0 : 1);
         sdN[q] += 1.0; sdS[q] += r;

         if(fh != INVALID_HANDLE)
           {
            const double money = HistoryDealGetDouble(dt, DEAL_PROFIT) + HistoryDealGetDouble(dt, DEAL_SWAP)
                               + HistoryDealGetDouble(dt, DEAL_COMMISSION);
            FileWrite(fh, TimeToString(entryTime, TIME_DATE | TIME_MINUTES),
                      TimeToString((datetime)HistoryDealGetInteger(dt, DEAL_TIME), TIME_DATE | TIME_MINUTES),
                      SrcName(g_rSrc[cur]), g_rDir[cur], g_rTdir[cur], g_rBurst[cur], BucketLabel(g_rBucket[cur]),
                      g_rHour[cur], g_rDow[cur], DoubleToString(g_rAtr[cur] / g_point, 0), DoubleToString(sl / g_point, 0),
                      DoubleToString(g_rSpr[cur], 0), DoubleToString(entryPx, g_digits), DoubleToString(exitPx, g_digits),
                      DoubleToString(r, 4), DoubleToString(money, 2));
           }
         cur = -1;
        }
     }
   if(fh != INVALID_HANDLE) FileClose(fh);

   if(detail) PrintReport(bN, bS, sdN, sdS);
  }

void PrintReport(const double &bN[], const double &bS[], const double &sdN[], const double &sdS[])
  {
   Print("============================================================");
   if(g_stN < 1.0) { Print("Nessun trade chiuso."); Print("============================================================"); return; }
   const double mean = g_stS / g_stN;
   const double var  = (g_stN > 1.0) ? (g_stS2 - g_stN * mean * mean) / (g_stN - 1.0) : 0.0;
   const double sd   = (var > 0.0) ? MathSqrt(var) : 0.0;
   const double t    = (sd > 0.0) ? mean / (sd / MathSqrt(g_stN)) : 0.0;
   Print("R PER TRADE: n=", (int)g_stN, " | media ", DoubleToString(mean, 4), " R | dev.std ", DoubleToString(sd, 3),
         " | t ", DoubleToString(t, 2), " | win ", DoubleToString(100.0 * g_stW / g_stN, 1), "% | somma R ", DoubleToString(g_stS, 1));
   Print("Il t va confrontato con la soglia di Bonferroni sul numero di classi provate, NON con 2.");

   string names[4] = {"DELTA  BUY ", "DELTA  SELL", "EXP_AD BUY ", "EXP_AD SELL"};
   for(int q = 0; q < 4; q++)
      if(sdN[q] > 0.0)
         Print(names[q], " | n=", (int)sdN[q], " | media ", DoubleToString(sdS[q] / sdN[q], 4), " R | somma ", DoubleToString(sdS[q], 1), " R");

   Print("--- per fascia oraria (ingresso, server + offset) ---");
   for(int b = 0; b < g_nB; b++)
      if(bN[b] > 0.0)
         Print(BucketLabel(b), " | n=", (int)bN[b], " | media ", DoubleToString(bS[b] / bN[b], 4), " R | somma ", DoubleToString(bS[b], 1), " R");
   Print("============================================================");
  }

//+------------------------------------------------------------------+
//| OnTester                                                          |
//| SDE_FIT_T_R (default): t-statistic della media di R. Confrontabile |
//|   fra classi con numero di trade diverso; negativa se la classe   |
//|   perde. Sotto Inp_FitMinTrades la parte positiva e' ridotta.     |
//| SDE_FIT_EXPECT_R: media di R per radice di n.                      |
//| SDE_FIT_RECOVERY_PF: RecoveryFactor * min(PF,3) (in denaro).       |
//+------------------------------------------------------------------+
double OnTester()
  {
   CollectResults(!g_isOptim);

   if(g_stN < 1.0) return 0.0;
   const double minT = (double)MathMax(1, Inp_FitMinTrades);
   const double pen  = (g_stN >= minT) ? 1.0 : MathPow(g_stN / minT, 2.0);
   const double mean = g_stS / g_stN;
   const double var  = (g_stN > 1.0) ? (g_stS2 - g_stN * mean * mean) / (g_stN - 1.0) : 0.0;
   const double sd   = (var > 0.0) ? MathSqrt(var) : 0.0;
   const double t    = (sd > 0.0) ? mean / (sd / MathSqrt(g_stN)) : 0.0;

   switch(Inp_FitMode)
     {
      case SDE_FIT_EXPECT_R:
        {
         const double v = mean * MathSqrt(g_stN);
         return (v > 0.0) ? v * pen : v;
        }
      case SDE_FIT_RECOVERY_PF:
        {
         const double profit = TesterStatistics(STAT_PROFIT);
         double maxDD = TesterStatistics(STAT_BALANCE_DD);
         const double pf = TesterStatistics(STAT_PROFIT_FACTOR);
         if(maxDD <= 0.0) maxDD = 1.0;
         if(profit <= 0.0) return profit / 1.0e9;
         return (profit / maxDD) * MathMin((pf > 0.0) ? pf : 1.0, 3.0) * pen;
        }
      case SDE_FIT_T_R:
      default:
         return (t > 0.0) ? t * pen : t;
     }
   return 0.0;
  }
//+------------------------------------------------------------------+
