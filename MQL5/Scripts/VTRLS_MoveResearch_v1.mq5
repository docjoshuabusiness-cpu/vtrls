//+------------------------------------------------------------------+
//|  VTRLS_MoveResearch_v1.mq5                                        |
//|  Motore di ricerca statistica per costruire condizioni operative.  |
//|                                                                    |
//|  NON e' un EA e non fa trading: e' uno SCRIPT di ricerca che       |
//|  legge lo storico di uno o piu' simboli e produce 6 tabelle CSV    |
//|  in MQL5/Files/<InpOutDir>/ :                                      |
//|                                                                    |
//|   1) <SYM>_daily.csv        - una riga per giornata: blocco D-1    |
//|                               (giorno precedente) + blocco D       |
//|                               (tutto cio' che il prezzo ha fatto   |
//|                               PRIMA dell'inizio del Largest Move)  |
//|                               + il Largest Move stesso.            |
//|   2) <SYM>_largest.csv      - dettaglio del movimento maggiore:    |
//|                               ora inizio/fine, direzione, punti,   |
//|                               durata, ATR, sessione, news.         |
//|   3) <SYM>_timedist.csv     - distribuzione oraria dei Largest     |
//|                               Move: bucket H1 e bucket M15.        |
//|   4) <SYM>_scan.csv         - griglia POINT-IN-TIME: per ogni      |
//|                               istante t della giornata, lo stato   |
//|                               del mercato costruito SOLO con barre |
//|                               t' < t, e l'esito nelle N ore        |
//|                               successive (first touch target/stop).|
//|   5) <SYM>_conditions.csv   - tabella delle CONDIZIONI: incrocio   |
//|                               di piu' bin (range D-1, direzione    |
//|                               D-1, punti mossi pre-evento, net,    |
//|                               sessione, news) con probabilita' di  |
//|                               movimento oltre ogni soglia.         |
//|   6) <SYM>_conditions_marg.csv - stessa cosa ma una dimensione     |
//|                               per volta (piu' robusto: molti piu'  |
//|                               campioni per cella).                 |
//|                                                                    |
//|  DISCIPLINA ANTI-BIAS (il punto piu' importante del progetto)      |
//|  ------------------------------------------------------------      |
//|  Il "Largest Move" e' per definizione noto solo A POSTERIORI: e'    |
//|  utile come descrizione ma NON e' un target su cui si costruisce    |
//|  una strategia, perche' al momento in cui il movimento parte tu     |
//|  non sai che sara' il piu' grande della giornata.                   |
//|                                                                    |
//|  Per questo il file 4 (scan) e le tabelle 5/6 non usano il Largest  |
//|  Move come etichetta, ma la domanda realmente operativa:            |
//|      "date queste condizioni all'istante t, qual e' la probabilita' |
//|       che nelle prossime N ore il prezzo faccia +X punti PRIMA di   |
//|       fare -X*AdverseRatio punti?"                                 |
//|  cioe' un vero first-touch target/stop, che e' esattamente cio' che |
//|  succederebbe a un ordine reale. Le feature a t sono costruite solo |
//|  con barre chiuse prima di t; l'entrata e' all'open della barra t.  |
//|  Nessun dato successivo a t entra MAI nelle condizioni.             |
//|                                                                    |
//|  Nel file 1 la stessa regola vale per il blocco "pre-evento": tutte |
//|  le colonne pre_* usano esclusivamente le barre che precedono la    |
//|  barra di inizio del Largest Move.                                 |
//|                                                                    |
//|  NORMALIZZAZIONE CROSS-SIMBOLO                                      |
//|  ------------------------------------------------------------      |
//|  Le soglie in punti non sono confrontabili tra XAUUSD, US30 ed      |
//|  EURUSD. Ogni metrica e' quindi esportata sia in punti sia in       |
//|  multipli di ATR(D-1). Le tabelle delle condizioni usano bin in     |
//|  ATR: cosi' la stessa condizione ha senso su qualunque simbolo.     |
//|                                                                    |
//|  STATISTICA                                                         |
//|  ------------------------------------------------------------      |
//|  Ogni cella riporta N, probabilita', LIMITE INFERIORE di Wilson al  |
//|  95% e LIFT rispetto alla baseline incondizionata. Una cella con    |
//|  p=40%, baseline 38% e Wilson-low 31% NON e' un edge: e' rumore.    |
//|  Guarda il Wilson-low e il lift, mai la probabilita' nuda.          |
//|  Con centinaia di celle testate il multiple testing e' garantito:   |
//|  lo script stampa anche la soglia di lift/N minima consigliata.     |
//+------------------------------------------------------------------+
#property copyright "vtrls"
#property version   "1.00"
#property script_show_inputs
#property description "Motore di ricerca condizioni operative: esporta 6 tabelle CSV point-in-time."

//==================================================================
//  INPUT
//==================================================================
input string          InpSymbols        = "";              // Simboli separati da virgola ("" = grafico, "*" = Market Watch)
input ENUM_TIMEFRAMES InpBaseTF         = PERIOD_M1;       // TF base del percorso intraday (M1..H1)
input datetime        InpFrom           = D'2019.01.01 00:00';  // Data inizio
input datetime        InpTo             = D'2026.01.01 00:00';  // Data fine
input int             InpATRPeriod      = 14;              // Periodo ATR (su daily)
input int             InpMinBarsDay     = 30;              // Barre minime perche' la giornata sia valida

input string          s1                = "=== LARGEST MOVE ===";
input bool            InpCleanLeg       = false;           // true = gamba "pulita" (chiude su ritracciamento)
input double          InpMaxRetracePct  = 33.0;            // % ritracciamento che chiude la gamba (se CleanLeg)

input string          s2                = "=== SCAN POINT-IN-TIME ===";
input bool            InpDoScan         = true;            // Genera griglia point-in-time + tabelle condizioni
input bool            InpWriteScanRows  = true;            // Scrive anche il CSV grezzo dello scan (file grande)
input int             InpScanStepMin    = 15;              // Passo della griglia in minuti
input int             InpScanHorizonMin = 240;             // Orizzonte forward in minuti
input double          InpAdverseRatio   = 0.5;             // Stop = ratio * target (first touch)
input string          InpThrPoints      = "50,100,150,200,300,500";  // Soglie in punti
input string          InpThrATR         = "0.5,1.0,1.5,2.0,3.0";     // Soglie in multipli di ATR(D-1)
input int             InpMinSamples     = 30;              // Campioni minimi per stampare una cella

input string          s3                = "=== NEWS ===";
input bool            InpUseCalendar    = true;            // Usa il calendario economico MQL5
input int             InpMinImportance  = 2;               // Importanza minima (1=low 2=medium 3=high)
input int             InpNewsWindowMin  = 60;              // Finestra +/- minuti per il flag "news presente"

input string          s4                = "=== SESSIONI (ora server) ===";
input int             InpLondonStart    = 8;               // Inizio London
input int             InpNYStart        = 13;              // Inizio NY (overlap)
input int             InpNYLateStart    = 17;              // Inizio NY late

input string          s5                = "=== DEBUG ===";
input int             InpDebug          = 1;               // 0=minimo 1=normale 2=verboso 3=dump giornaliero
input int             InpSyncTimeoutSec = 300;             // Timeout massimo per il download dello storico (s)
input int             InpDebugDays      = 5;               // giornate da dumpare in dettaglio (debug>=3)

input string          s6                = "=== OUTPUT ===";
input string          InpOutDir         = "VTRLS_Research";// Sottocartella in MQL5/Files
input bool            InpWriteCsv       = true;            // Scrive i CSV (dati grezzi, per Excel/Python)
input bool            InpWriteHtml      = true;            // Scrive il report HTML (doppio clic, si apre nel browser)

//==================================================================
//  GLOBALI
//==================================================================
double   g_thrPt[];        // soglie in punti
double   g_thrAtr[];       // soglie in ATR
int      g_nPt=0, g_nAtr=0;
double   g_point=0.0;
string   g_sym="";
int      g_tfMin=1;

// calendario
datetime g_newsTime[];
string   g_newsName[];
int      g_newsImp[];
int      g_nNews=0;
bool     g_calOk=false;

// bin edges (in multipli di ATR salvo prevDir/sessione/news)
double   g_edgePrevRange[4] = {0.60,0.90,1.20,1.60};
double   g_edgePreTotal[4]  = {0.20,0.40,0.60,0.90};
double   g_edgePreNet[4]    = {-0.50,-0.15,0.15,0.50};

//------------------------------------------------------------------
// riga della griglia point-in-time (una per istante t analizzato)
//------------------------------------------------------------------
struct SScan
{
   datetime t;
   int      dow, hour, minute, sess;
   // blocco D-1
   double   prevRangeAtr, prevBodyAtr, prevClosePos;
   int      prevDir;
   double   atrPt;
   // blocco D pre-t (solo barre < t)
   double   preUpAtr, preDnAtr, preTotAtr, preNetAtr, preRangeAtr;
   double   prePctPrevRange;      // range percorso / range D-1  (%)
   double   preExtUpAtr, preExtDnAtr;   // estensione oltre high/low D-1
   double   dToPrevHighAtr, dToPrevLowAtr;
   double   preUpPt, preDnPt, preTotPt, preNetPt;
   int      preMin;
   // news
   int      newsFlag;             // 1 se evento entro finestra (passato o futuro)
   int      newsAheadMin;         // minuti al prossimo evento (-1 = nessuno/na)
   // esito forward (first touch), -1 = non raggiunto
   int      hitUpPt[8],  hitDnPt[8];
   int      hitUpAtr[8], hitDnAtr[8];
   double   mfeUpAtr, mfeDnAtr, mfeMaxAtr;
   double   mfeUpPt,  mfeDnPt;
};
SScan g_scan[];
int   g_nScan=0;

//------------------------------------------------------------------
// cella della tabella condizioni
//------------------------------------------------------------------
struct SCell
{
   string key;
   string label;
   int    n;
   int    hitPt[8];
   int    hitAtr[8];
   double sumMfe;
   double mfe[];
};
SCell g_cell[];
int   g_nCell=0;
int   g_slot[];
int   g_slotMask=0;

//==================================================================
//  UTILITY
//==================================================================
// log a livelli: 1=normale, 2=verboso, 3=dump per giornata
void DBG(int lvl, string msg){ if(InpDebug>=lvl) Print(msg); }
string MS(uint t0){ return "["+DoubleToString((GetTickCount()-t0)/1000.0,2)+"s]"; }

int TFMinutes(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 1;
      case PERIOD_M2:  return 2;
      case PERIOD_M3:  return 3;
      case PERIOD_M4:  return 4;
      case PERIOD_M5:  return 5;
      case PERIOD_M6:  return 6;
      case PERIOD_M10: return 10;
      case PERIOD_M12: return 12;
      case PERIOD_M15: return 15;
      case PERIOD_M20: return 20;
      case PERIOD_M30: return 30;
      case PERIOD_H1:  return 60;
   }
   return -1;
}

string DowIT(int d)
{
   string a[7]={"Dom","Lun","Mar","Mer","Gio","Ven","Sab"};
   if(d<0 || d>6) return "?";
   return a[d];
}
string MonIT(int m)
{
   string a[13]={"","Gen","Feb","Mar","Apr","Mag","Giu","Lug","Ago","Set","Ott","Nov","Dic"};
   if(m<1 || m>12) return "?";
   return a[m];
}
string SessName(int s)
{
   switch(s)
   {
      case 0: return "Asia";
      case 1: return "London";
      case 2: return "NY-overlap";
      case 3: return "NY-late";
   }
   return "?";
}
int SessOf(int hour)
{
   if(hour < InpLondonStart)  return 0;
   if(hour < InpNYStart)      return 1;
   if(hour < InpNYLateStart)  return 2;
   return 3;
}
string D2(int v){ return (v<10 ? "0"+IntegerToString(v) : IntegerToString(v)); }
string HM(datetime t)
{
   MqlDateTime s; TimeToStruct(t,s);
   return D2(s.hour)+":"+D2(s.min);
}
string DateStr(datetime t)
{
   MqlDateTime s; TimeToStruct(t,s);
   return IntegerToString(s.year)+"-"+D2(s.mon)+"-"+D2(s.day);
}
string M15Label(int hour,int minute)
{
   int q = (minute/15)*15;
   int e = q+15; int eh = hour;
   if(e>=60){ e=0; eh=(hour+1)%24; }
   return D2(hour)+":"+D2(q)+"-"+D2(eh)+":"+D2(e);
}
string F(double v,int d=2){ return DoubleToString(v,d); }

int ParseDoubles(string src, double &out[])
{
   string parts[];
   int k = StringSplit(src, StringGetCharacter(",",0), parts);
   ArrayResize(out,0);
   int n=0;
   for(int i=0;i<k;i++)
   {
      string p = parts[i];
      StringTrimLeft(p); StringTrimRight(p);
      if(StringLen(p)==0) continue;
      double v = StringToDouble(p);
      if(v<=0) continue;
      if(n>=8) break;                 // hard cap: 8 soglie per tipo
      ArrayResize(out,n+1); out[n]=v; n++;
   }
   return n;
}

double Median(double &a[])
{
   int n=ArraySize(a);
   if(n<=0) return 0.0;
   ArraySort(a);
   if(n%2==1) return a[n/2];
   return 0.5*(a[n/2-1]+a[n/2]);
}

// limite inferiore dell'intervallo di Wilson al 95%
double WilsonLow(int k,int n)
{
   if(n<=0) return 0.0;
   double z=1.959964;
   double p=(double)k/(double)n;
   double den=1.0+z*z/n;
   double c=(p+z*z/(2.0*n))/den;
   double m=z*MathSqrt(p*(1.0-p)/n + z*z/(4.0*n*n))/den;
   double lo=c-m;
   return (lo<0.0?0.0:lo);
}

// decomposizione del percorso di una barra OHLC in punti UP e punti DOWN.
// Barra rialzista: open->low->high->close ; ribassista: open->high->low->close.
// Per costruzione (up-down) == (close-open), quindi Net e' sempre coerente.
void BarPath(const MqlRates &r, double &up, double &dn)
{
   if(r.close>=r.open)
   {
      up = (r.high-r.low);
      dn = (r.open-r.low) + (r.high-r.close);
   }
   else
   {
      up = (r.high-r.open) + (r.close-r.low);
      dn = (r.high-r.low);
   }
   if(up<0) up=0;
   if(dn<0) dn=0;
}

//==================================================================
//  CALENDARIO ECONOMICO
//==================================================================
void LoadCalendar(string sym, datetime from, datetime to)
{
   g_nNews=0; g_calOk=false;
   ArrayResize(g_newsTime,0); ArrayResize(g_newsName,0); ArrayResize(g_newsImp,0);
   if(!InpUseCalendar) return;

   string cur[2];
   cur[0]=SymbolInfoString(sym,SYMBOL_CURRENCY_BASE);
   cur[1]=SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT);

   for(int c=0;c<2;c++)
   {
      if(StringLen(cur[c])==0) continue;
      if(c==1 && cur[1]==cur[0]) continue;

      MqlCalendarValue vals[];
      int nv = CalendarValueHistory(vals, from, to, NULL, cur[c]);
      if(nv<=0) continue;
      g_calOk=true;

      for(int i=0;i<nv;i++)
      {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id, ev)) continue;
         if((int)ev.importance < InpMinImportance) continue;
         int k=g_nNews;
         ArrayResize(g_newsTime,k+1); ArrayResize(g_newsName,k+1); ArrayResize(g_newsImp,k+1);
         g_newsTime[k]=vals[i].time;
         g_newsName[k]=ev.name;
         g_newsImp[k]=(int)ev.importance;
         g_nNews++;
      }
   }

   // ordinamento per tempo (insertion sort: il numero di eventi filtrati e' basso)
   for(int i=1;i<g_nNews;i++)
   {
      datetime kt=g_newsTime[i]; string kn=g_newsName[i]; int ki=g_newsImp[i];
      int j=i-1;
      while(j>=0 && g_newsTime[j]>kt)
      {
         g_newsTime[j+1]=g_newsTime[j]; g_newsName[j+1]=g_newsName[j]; g_newsImp[j+1]=g_newsImp[j];
         j--;
      }
      g_newsTime[j+1]=kt; g_newsName[j+1]=kn; g_newsImp[j+1]=ki;
   }
   PrintFormat("[%s] calendario: %d eventi (imp>=%d) tra %s e %s%s",
               sym, g_nNews, InpMinImportance, TimeToString(from,TIME_DATE), TimeToString(to,TIME_DATE),
               (g_calOk?"":" - CALENDARIO NON DISPONIBILE"));
}

// evento piu' vicino a t; ritorna indice o -1. dist = minuti con segno (>0 = evento nel futuro)
int NearestNews(datetime t, int &distMin)
{
   distMin=999999;
   if(g_nNews<=0) return -1;
   int best=-1;
   int lo=0, hi=g_nNews-1;
   while(lo<=hi)                       // ricerca binaria del primo evento >= t
   {
      int mid=(lo+hi)/2;
      if(g_newsTime[mid]<t) lo=mid+1; else hi=mid-1;
   }
   for(int i=lo-1;i<=lo;i++)
   {
      if(i<0 || i>=g_nNews) continue;
      int d=(int)((g_newsTime[i]-t)/60);
      if(MathAbs(d)<MathAbs(distMin)){ distMin=d; best=i; }
   }
   return best;
}
// minuti al PROSSIMO evento (solo futuro) - usabile point-in-time
int MinutesToNextNews(datetime t)
{
   if(g_nNews<=0) return -1;
   int lo=0, hi=g_nNews-1;
   while(lo<=hi)
   {
      int mid=(lo+hi)/2;
      if(g_newsTime[mid]<t) lo=mid+1; else hi=mid-1;
   }
   if(lo>=g_nNews) return -1;
   return (int)((g_newsTime[lo]-t)/60);
}

//==================================================================
//  LARGEST MOVE
//  dir=+1 -> massima escursione al rialzo, dir=-1 -> al ribasso.
//  Senza CleanLeg e' il classico max run-up:  max_i ( high_i - min_{j<=i} low_j ).
//  Con CleanLeg la gamba viene chiusa quando ritraccia oltre X% del run
//  corrente: serve a isolare movimenti "puliti" invece di escursioni
//  che al loro interno contengono ore di chop.
//==================================================================
void MaxRun(const MqlRates &r[], int n, int dir, bool clean, double retrPct,
            int &sIdx, int &eIdx, double &best)
{
   sIdx=-1; eIdx=-1; best=0.0;
   if(n<=0) return;

   double anchor = (dir>0 ? r[0].low : r[0].high);
   int    aIdx   = 0;
   double peak   = (dir>0 ? r[0].high : r[0].low);
   int    pIdx   = 0;

   for(int i=0;i<n;i++)
   {
      if(dir>0)
      {
         if(r[i].low<anchor && !clean){ anchor=r[i].low; aIdx=i; peak=r[i].high; pIdx=i; }
         if(r[i].high>peak){ peak=r[i].high; pIdx=i; }
         double run=peak-anchor;
         if(run>best){ best=run; sIdx=aIdx; eIdx=pIdx; }
         if(clean)
         {
            if(run>0 && (peak-r[i].low) > retrPct/100.0*run)
            { anchor=r[i].low; aIdx=i; peak=r[i].high; pIdx=i; }
            else if(r[i].low<anchor){ anchor=r[i].low; aIdx=i; peak=r[i].high; pIdx=i; }
         }
      }
      else
      {
         if(r[i].high>anchor && !clean){ anchor=r[i].high; aIdx=i; peak=r[i].low; pIdx=i; }
         if(r[i].low<peak){ peak=r[i].low; pIdx=i; }
         double run=anchor-peak;
         if(run>best){ best=run; sIdx=aIdx; eIdx=pIdx; }
         if(clean)
         {
            if(run>0 && (r[i].high-peak) > retrPct/100.0*run)
            { anchor=r[i].high; aIdx=i; peak=r[i].low; pIdx=i; }
            else if(r[i].high>anchor){ anchor=r[i].high; aIdx=i; peak=r[i].low; pIdx=i; }
         }
      }
   }
   if(sIdx<0){ sIdx=0; eIdx=0; best=0.0; }
}

//==================================================================
//  ESITO FORWARD (first touch) - PASSATA UNICA
//  Per ogni soglia (in punti e in ATR) e per entrambe le direzioni
//  determina se il target viene raggiunto PRIMA dello stop, con una
//  sola scansione delle barre.
//  La versione precedente ripeteva una scansione completa per ogni
//  soglia e per ogni direzione: fino a 22 passate su 240 barre per
//  ogni punto della griglia, cioe' ~900 milioni di iterazioni su 7
//  anni di M1. Questo era il collo di bottiglia dello script.
//  Se target e stop cadono nella stessa barra si conta STOP (ipotesi
//  conservativa: senza tick non si conosce l'ordine intrabar).
//==================================================================
void ResolveForward(const MqlRates &r[], int g, int endIdx, double entry, double atrPt, SScan &s)
{
   int nT = g_nPt + g_nAtr;
   double tgt[16];                                   // target in PUNTI
   for(int k=0;k<g_nPt;k++)  tgt[k]       = g_thrPt[k];
   for(int k=0;k<g_nAtr;k++) tgt[g_nPt+k] = g_thrAtr[k]*atrPt;

   int  outUp[16],  outDn[16];
   bool openUp[16], openDn[16];
   for(int k=0;k<nT;k++){ outUp[k]=-1; outDn[k]=-1; openUp[k]=true; openDn[k]=true; }
   int openCnt=2*nT;

   double mfeU=0, mfeD=0;
   for(int i=g;i<=endIdx;i++)
   {
      double u=(r[i].high-entry)/g_point;
      double d=(entry-r[i].low)/g_point;
      if(u>mfeU) mfeU=u;
      if(d>mfeD) mfeD=d;
      if(openCnt<=0) continue;                       // l'MFE va comunque completato

      int mins=(int)((r[i].time-r[g].time)/60);
      for(int k=0;k<nT;k++)
      {
         double T=tgt[k];
         double S=T*InpAdverseRatio;
         if(openUp[k])
         {
            if(d>=S){ openUp[k]=false; openCnt--; }
            else if(u>=T){ outUp[k]=mins; openUp[k]=false; openCnt--; }
         }
         if(openDn[k])
         {
            if(u>=S){ openDn[k]=false; openCnt--; }
            else if(d>=T){ outDn[k]=mins; openDn[k]=false; openCnt--; }
         }
      }
   }

   s.mfeUpPt=mfeU; s.mfeDnPt=mfeD;
   s.mfeUpAtr=mfeU/atrPt; s.mfeDnAtr=mfeD/atrPt;
   s.mfeMaxAtr=MathMax(s.mfeUpAtr,s.mfeDnAtr);

   ArrayInitialize(s.hitUpPt,-1);  ArrayInitialize(s.hitDnPt,-1);
   ArrayInitialize(s.hitUpAtr,-1); ArrayInitialize(s.hitDnAtr,-1);
   for(int k=0;k<g_nPt;k++) { s.hitUpPt[k] =outUp[k];        s.hitDnPt[k] =outDn[k];        }
   for(int k=0;k<g_nAtr;k++){ s.hitUpAtr[k]=outUp[g_nPt+k];  s.hitDnAtr[k]=outDn[g_nPt+k];  }
}

//==================================================================
//  HASH MAP DELLE CONDIZIONI
//==================================================================
uint Hash(string s)
{
   uint h=2166136261;
   int n=StringLen(s);
   for(int i=0;i<n;i++){ h ^= (uint)StringGetCharacter(s,i); h *= 16777619; }
   return h;
}
void CellsInit()
{
   g_nCell=0; ArrayResize(g_cell,0);
   g_slotMask=8191;                       // 8192 slot
   ArrayResize(g_slot,g_slotMask+1);
   ArrayInitialize(g_slot,-1);
}
int CellGet(string key,string label)
{
   uint h=Hash(key);
   int idx=(int)(h & (uint)g_slotMask);
   for(int probe=0; probe<=g_slotMask; probe++)
   {
      int at=(idx+probe) & g_slotMask;
      int ci=g_slot[at];
      if(ci<0)
      {
         ArrayResize(g_cell,g_nCell+1,512);
         g_cell[g_nCell].key=key;
         g_cell[g_nCell].label=label;
         g_cell[g_nCell].n=0;
         g_cell[g_nCell].sumMfe=0.0;
         ArrayInitialize(g_cell[g_nCell].hitPt,0);
         ArrayInitialize(g_cell[g_nCell].hitAtr,0);
         ArrayResize(g_cell[g_nCell].mfe,0);
         g_slot[at]=g_nCell;
         g_nCell++;
         return g_nCell-1;
      }
      if(g_cell[ci].key==key) return ci;
   }
   return -1;                              // tabella piena
}
void CellAdd(string key,string label,const SScan &s)
{
   int ci=CellGet(key,label);
   if(ci<0) return;
   g_cell[ci].n++;
   for(int k=0;k<g_nPt;k++)
      if(s.hitUpPt[k]>=0 || s.hitDnPt[k]>=0) g_cell[ci].hitPt[k]++;
   for(int k=0;k<g_nAtr;k++)
      if(s.hitUpAtr[k]>=0 || s.hitDnAtr[k]>=0) g_cell[ci].hitAtr[k]++;
   g_cell[ci].sumMfe += s.mfeMaxAtr;
   int m=ArraySize(g_cell[ci].mfe);
   ArrayResize(g_cell[ci].mfe,m+1,512);
   g_cell[ci].mfe[m]=s.mfeMaxAtr;
}

int BinOf(double v, const double &edges[])
{
   int n=ArraySize(edges);
   for(int i=0;i<n;i++) if(v<edges[i]) return i;
   return n;
}
string BinLabel(int b, const double &edges[], string unit)
{
   int n=ArraySize(edges);
   if(b<=0)    return "<"+F(edges[0],2)+unit;
   if(b>=n)    return ">"+F(edges[n-1],2)+unit;
   return F(edges[b-1],2)+".."+F(edges[b],2)+unit;
}

//--- prototipi (le definizioni sono piu' avanti nel file)
void   BuildConditions(string sym,string dir);
void   WriteCells(string path,string keyHeader,const int &basePt[],const int &baseAtr[],
                  string title,string note,string tid);

//------------------------------------------------------------------
// CopyRates con retry: alla prima chiamata lo storico puo' non essere
// ancora scaricato dal server; MT5 lo richiede in modo asincrono.
//------------------------------------------------------------------
int SafeCopyRates(string sym, ENUM_TIMEFRAMES tf, datetime from, datetime to, MqlRates &out[])
{
   for(int attempt=0; attempt<20; attempt++)
   {
      int n = CopyRates(sym, tf, from, to, out);
      if(n > 0) return n;
      if(IsStopped()) return -1;
      Sleep(200);
   }
   return -1;
}

//------------------------------------------------------------------
// Prepara lo storico del TF base e restituisce l'intervallo REALMENTE
// analizzabile.
//
// Tre cose diverse limitano quanti dati ottieni, e vanno distinte:
//  1. SERIES_SERVER_FIRSTDATE  - da dove parte lo storico SUL SERVER del
//     broker. Se l'intervallo richiesto e' tutto prima di questa data,
//     nessuna attesa servira' a niente: quei dati non esistono.
//  2. TERMINAL_MAXBARS - il tetto di barre che il terminale accetta di
//     tenere. Se e' inferiore alle barre del periodo, MT5 tronca la
//     storia a prescindere dal broker (Strumenti > Opzioni > Grafici >
//     Barre massime nel grafico).
//  3. SERIES_FIRSTDATE - da dove parte lo storico gia' scaricato in
//     locale. E' l'unico dei tre che il download puo' far arretrare.
//
// La versione precedente guardava solo il punto 3 e restava in attesa
// anche quando il conteggio era fermo a zero, cioe' proprio nel caso in
// cui l'attesa era inutile per definizione.
//------------------------------------------------------------------
bool PrepareHistory(string sym, ENUM_TIMEFRAMES tf, datetime from, datetime to, datetime &effFrom)
{
   effFrom=from;

   long maxbars = TerminalInfoInteger(TERMINAL_MAXBARS);
   long needed  = (long)((to-from)/(60*g_tfMin));
   PrintFormat("[%s] limite barre terminale: %d | barre teoriche nel periodo richiesto: %d",
               sym,maxbars,needed);
   if(maxbars>0 && maxbars<needed)
   {
      // barre -> giorni di trading -> giorni di calendario (5 sessioni su 7)
      long dCal=(long)((double)maxbars*g_tfMin/1440.0*7.0/5.0);
      PrintFormat("[%s] ATTENZIONE: 'Barre massime nel grafico' = %d, inferiore alle %d barre del periodo. "
                  "Con questo tetto e TF %s copri circa %d giorni di calendario, non di piu', "
                  "qualunque sia lo storico del broker.",
                  sym,maxbars,needed,EnumToString(tf),dCal);
      PrintFormat("[%s] RIMEDIO: Strumenti > Opzioni > Grafici > 'Barre massime nel grafico' = Illimitato, "
                  "riavvia il terminale, riapri il grafico %s e tieni premuto Home. "
                  "In alternativa alza InpBaseTF: con %d barre M5 copri ~%d giorni, M15 ~%d, H1 ~%d.",
                  sym,EnumToString(tf),maxbars,
                  (long)((double)maxbars*5/1440.0*7.0/5.0),
                  (long)((double)maxbars*15/1440.0*7.0/5.0),
                  (long)((double)maxbars*60/1440.0*7.0/5.0));
   }

   // sollecita il download della zona richiesta
   MqlRates kick[];
   CopyRates(sym,tf,from,2,kick);

   uint t0=GetTickCount();
   uint tLast=t0;
   uint timeoutMs=(uint)MathMax(10,InpSyncTimeoutSec)*1000;
   int  lastBars=-1, stable=0;
   datetime srvFirst=0, locFirst=0;

   while(GetTickCount()-t0 < timeoutMs)
   {
      if(IsStopped()){ Print("[",sym,"] sincronizzazione interrotta dall'utente."); return false; }

      long synced=0;
      int  b   = Bars(sym,tf,from,to);
      bool ok  = (SeriesInfoInteger(sym,tf,SERIES_SYNCHRONIZED,synced) && synced!=0);
      srvFirst = (datetime)SeriesInfoInteger(sym,tf,SERIES_SERVER_FIRSTDATE);
      locFirst = (datetime)SeriesInfoInteger(sym,tf,SERIES_FIRSTDATE);

      // il broker non ha proprio questi dati: inutile aspettare
      if(srvFirst>0 && srvFirst>=to)
      {
         PrintFormat("[%s] STOP: il server ha storico %s solo dal %s, mentre InpTo e' %s. "
                     "L'intervallo richiesto non esiste sul broker.",
                     sym,EnumToString(tf),TimeToString(srvFirst,TIME_DATE),TimeToString(to,TIME_DATE));
         return false;
      }

      if(b>0 && ok) break;

      if(b==lastBars) stable++; else { stable=0; lastBars=b; }

      // conteggio fermo da ~5s: il download ha dato tutto quello che aveva,
      // che siano barre o zero barre
      if(stable>=10)
      {
         if(b>0){ DBG(1,"["+sym+"] download fermo a "+IntegerToString(b)+" barre da 5s: procedo."); break; }
         PrintFormat("[%s] STOP: 0 barre %s nel periodo e il download non avanza da 5s. "
                     "Storico locale dal %s, storico server dal %s.",
                     sym,EnumToString(tf),
                     (locFirst>0?TimeToString(locFirst,TIME_DATE):"n/d"),
                     (srvFirst>0?TimeToString(srvFirst,TIME_DATE):"n/d"));
         break;
      }

      if(GetTickCount()-tLast>=3000)
      {
         tLast=GetTickCount();
         PrintFormat("[%s] download %s: %d barre nel periodo | locale dal %s | server dal %s (%.0fs)",
                     sym,EnumToString(tf),b,
                     (locFirst>0?TimeToString(locFirst,TIME_DATE):"n/d"),
                     (srvFirst>0?TimeToString(srvFirst,TIME_DATE):"n/d"),
                     (GetTickCount()-t0)/1000.0);
      }
      Sleep(500);
   }

   srvFirst=(datetime)SeriesInfoInteger(sym,tf,SERIES_SERVER_FIRSTDATE);
   locFirst=(datetime)SeriesInfoInteger(sym,tf,SERIES_FIRSTDATE);
   datetime avail=locFirst;
   if(srvFirst>0 && (avail==0 || srvFirst>avail)) avail=srvFirst;

   // restringe l'analisi a cio' che esiste davvero, invece di fallire
   if(avail>0 && avail>effFrom)
   {
      PrintFormat("[%s] intervallo richiesto %s-%s, ma lo storico %s parte dal %s: "
                  "l'analisi viene ristretta a %s-%s.",
                  sym,TimeToString(from,TIME_DATE),TimeToString(to,TIME_DATE),
                  EnumToString(tf),TimeToString(avail,TIME_DATE),
                  TimeToString(avail,TIME_DATE),TimeToString(to,TIME_DATE));
      effFrom=avail;
   }

   if(effFrom>=to)
   {
      PrintFormat("[%s] STOP: lo storico %s disponibile parte dal %s, cioe' DOPO InpTo (%s): "
                  "l'intervallo da analizzare sarebbe vuoto. "
                  "Sposta InpTo a una data successiva al %s, oppure scarica piu' storia.",
                  sym,EnumToString(tf),TimeToString(effFrom,TIME_DATE),TimeToString(to,TIME_DATE),
                  TimeToString(effFrom,TIME_DATE));
      return false;
   }

   int bFinal=Bars(sym,tf,effFrom,to);
   PrintFormat("[%s] barre %s utilizzabili: %d nel periodo effettivo %s-%s",
               sym,EnumToString(tf),bFinal,TimeToString(effFrom,TIME_DATE),TimeToString(to,TIME_DATE));
   if(bFinal<=0)
   {
      PrintFormat("[%s] NESSUN DATO UTILIZZABILE. Rimedi, in ordine: "
                  "(1) apri il grafico %s del simbolo e tieni premuto Home; "
                  "(2) Strumenti > Opzioni > Grafici > Barre massime = Illimitato e riavvia; "
                  "(3) usa un TF base piu' alto (M5/M15), che il broker conserva molto piu' a lungo; "
                  "(4) sposta InpFrom dopo il %s.",
                  sym,EnumToString(tf),(avail>0?TimeToString(avail,TIME_DATE):"(data non nota)"));
      return false;
   }
   return true;
}

//------------------------------------------------------------------
// ripulisce il nome del simbolo per usarlo come nome file
//------------------------------------------------------------------
string SafeName(string s)
{
   string bad = "\\/:*?\"<>|";
   string r = s;
   for(int i=0;i<StringLen(bad);i++)
      StringReplace(r, ShortToString(StringGetCharacter(bad,i)), "_");
   return r;
}


//==================================================================
//  REPORT HTML
//  Un unico file autonomo per simbolo: nessuna libreria esterna,
//  nessuna connessione. Contiene le stesse tabelle dei CSV, con
//  ordinamento per colonna, filtro testuale e evidenziazione delle
//  celle statisticamente interessanti.
//  I CSV restano la fonte per l'analisi seria (Excel, Python): l'HTML
//  serve a guardare i numeri senza importare niente.
//==================================================================
int g_html=INVALID_HANDLE;

void H(string x){ if(g_html!=INVALID_HANDLE) FileWriteString(g_html,x); }
void W(int h,string x){ if(h!=INVALID_HANDLE) FileWriteString(h,x); }

string HE(string x)                       // escape HTML
{
   StringReplace(x,"&","&amp;");
   StringReplace(x,"<","&lt;");
   StringReplace(x,">","&gt;");
   StringReplace(x,"\"","&quot;");
   return x;
}

void HtmlHead(string sym)
{
   H("<!DOCTYPE html><html lang=\"it\"><head><meta charset=\"windows-1252\">");
   H("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">");
   H("<title>VTRLS - "+HE(sym)+"</title><style>");
   H(":root{--bg:#0f1216;--pan:#171b21;--ln:#232a33;--tx:#dfe5ec;--mut:#8b97a6;--acc:#5aa9e6;--good:#3fb950;--bad:#f85149;--warn:#d29922}");
   H("*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:13px/1.45 -apple-system,Segoe UI,Roboto,Arial,sans-serif}");
   H("header{padding:16px 22px;background:var(--pan);border-bottom:1px solid var(--ln)}");
   H("h1{margin:0 0 3px;font-size:17px}h2{font-size:14px;margin:20px 0 6px}.sub{color:var(--mut);font-size:12px}");
   H("nav{display:flex;gap:6px;padding:10px 22px;background:var(--pan);border-bottom:1px solid var(--ln);flex-wrap:wrap;position:sticky;top:0;z-index:4}");
   H("nav button{background:#1e242c;color:var(--tx);border:1px solid var(--ln);padding:6px 12px;border-radius:6px;cursor:pointer;font-size:12px}");
   H("nav button.on{background:var(--acc);color:#06121f;border-color:var(--acc);font-weight:600}");
   H("main{padding:14px 22px 60px}section{display:none}section.on{display:block}");
   H(".sum{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:10px;margin:12px 0}");
   H(".card{background:var(--pan);border:1px solid var(--ln);border-radius:8px;padding:10px 12px}");
   H(".card b{display:block;font-size:18px;font-variant-numeric:tabular-nums}");
   H(".card span{color:var(--mut);font-size:11px;text-transform:uppercase;letter-spacing:.04em}");
   H(".tools{margin:10px 0}.tools input{background:#0c0f13;border:1px solid var(--ln);color:var(--tx);padding:6px 10px;border-radius:6px;width:320px;max-width:100%}");
   H(".wrap{overflow:auto;max-height:72vh;border:1px solid var(--ln);border-radius:8px;background:var(--pan)}");
   H("table{border-collapse:collapse;width:100%;font-size:12px}");
   H("th,td{padding:5px 8px;border-bottom:1px solid var(--ln);white-space:nowrap;text-align:right}");
   H("th{position:sticky;top:0;background:#1b212a;cursor:pointer;user-select:none;font-weight:600}");
   H("th:first-child,td:first-child{text-align:left}td{font-variant-numeric:tabular-nums}");
   H("tbody tr:hover{background:#1d232c}.up{color:var(--good)}.dn{color:var(--bad)}");
   H(".hi{color:var(--good);font-weight:600}.lo{color:var(--bad)}.nz{color:var(--mut)}");
   H(".bw{background:#0c0f13;border-radius:3px;height:9px;width:110px;display:inline-block;vertical-align:middle}");
   H(".bf{background:var(--acc);height:9px;border-radius:3px;display:block}");
   H(".note{color:var(--mut);font-size:12px;margin:6px 0 14px;max-width:95ch}");
   H(".note b{color:var(--tx)}");
   H("</style></head><body>");
   H("<header><h1>VTRLS Move Research - "+HE(sym)+"</h1><div class=\"sub\">TF base "+EnumToString(InpBaseTF)+
     " | periodo "+TimeToString(InpFrom,TIME_DATE)+" - "+TimeToString(InpTo,TIME_DATE)+
     " | generato "+TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES)+"</div></header>");
   H("<nav>");
   H("<button class=\"on\" onclick=\"tab(0)\">Riepilogo</button>");
   H("<button onclick=\"tab(1)\">Giornaliero</button>");
   H("<button onclick=\"tab(2)\">Largest Move</button>");
   H("<button onclick=\"tab(3)\">Orari</button>");
   H("<button onclick=\"tab(4)\">Condizioni incrociate</button>");
   H("<button onclick=\"tab(5)\">Condizioni marginali</button>");
   H("</nav><main>");
   H("<section class=\"on\"><div id=\"sum\" class=\"sum\"></div>");
   H("<h2>Come leggere questo report</h2><div class=\"note\">");
   H("<b>Largest Move</b> e' la massima escursione direzionale della giornata. E' nota solo a posteriori: descrive, non predice. ");
   H("Le tabelle <b>Condizioni</b> non la usano come obiettivo: partono da una griglia point-in-time in cui le feature ");
   H("all'istante t sono costruite solo con barre chiuse prima di t, l'ingresso e' all'apertura della barra t e l'esito e' ");
   H("un first touch target/stop entro l'orizzonte. Nessun dato successivo a t entra nelle condizioni.<br><br>");
   H("<b>p</b> e' la probabilita' grezza, <b>wlow</b> il limite inferiore di Wilson al 95%, <b>lift</b> il rapporto con la ");
   H("baseline incondizionata. Una cella e' interessante solo se <b>lift &gt; 1.20</b> E <b>wlow &gt; baseline</b>: le celle ");
   H("che soddisfano entrambe sono in verde, quelle sotto baseline in rosso, il resto in grigio perche' e' rumore. ");
   H("Con centinaia di celle testate qualcuna sembrera' ottima per puro caso: verifica sempre su un secondo periodo e un ");
   H("secondo simbolo prima di crederci.</div></section>");
}

void HtmlFoot()
{
   H("</main><script>");
   H("function tab(i){var s=document.querySelectorAll('section'),b=document.querySelectorAll('nav button');");
   H("for(var k=0;k<s.length;k++){s[k].className=(k==i?'on':'');}");
   H("for(var k=0;k<b.length;k++){b[k].className=(k==i?'on':'');}}");
   H("function srt(th){var t=th.closest('table'),i=0,c=th.parentNode.children;");
   H("for(var k=0;k<c.length;k++){if(c[k]==th)i=k;}");
   H("var b=t.tBodies[0],r=[];for(var k=0;k<b.rows.length;k++)r.push(b.rows[k]);");
   H("var d=(th.getAttribute('d')=='1')?-1:1;th.setAttribute('d',d==1?'1':'0');");
   H("r.sort(function(x,y){var a=x.cells[i].innerText.trim(),e=y.cells[i].innerText.trim();");
   H("var na=parseFloat(a),ne=parseFloat(e);");
   H("if(!isNaN(na)&&!isNaN(ne)&&a!=''&&e!='')return (na-ne)*d;return a.localeCompare(e)*d;});");
   H("for(var k=0;k<r.length;k++)b.appendChild(r[k]);}");
   H("function flt(el){var t=document.getElementById(el.getAttribute('t')),q=el.value.toLowerCase(),b=t.tBodies[0];");
   H("for(var k=0;k<b.rows.length;k++){var r=b.rows[k];r.style.display=(r.innerText.toLowerCase().indexOf(q)>=0)?'':'none';}}");
   H("var sc=document.getElementById('sumsrc');if(sc){document.getElementById('sum').appendChild(sc);sc.style.display='contents';}");
   H("</script></body></html>");
}

// intestazione di tabella da una lista separata da ';'
void HtmlTableHead(string id, string cols, bool withFilter)
{
   if(withFilter)
      H("<div class=\"tools\"><input placeholder=\"filtra righe...\" t=\""+id+"\" oninput=\"flt(this)\"></div>");
   H("<div class=\"wrap\"><table id=\""+id+"\"><thead><tr>");
   string c[]; int n=StringSplit(cols,StringGetCharacter(";",0),c);
   for(int i=0;i<n;i++) H("<th onclick=\"srt(this)\">"+HE(c[i])+"</th>");
   H("</tr></thead><tbody>");
}
void HtmlTableEnd(){ H("</tbody></table></div>"); }

// una cella "probabilita' (lift)" colorata: verde solo se il lift supera 1.20
// E il limite inferiore di Wilson resta sopra la baseline. Tutto il resto e'
// grigio, perche' statisticamente non distinguibile dal caso.
string CondCell(int hits,int n,int base)
{
   if(n<=0) return "<td>-</td>";
   double p =(double)hits/n;
   double bp=(g_nScan>0 ? (double)base/g_nScan : 0.0);
   double wl=WilsonLow(hits,n);
   double lift=(bp>0 ? p/bp : 0.0);
   string cls="nz";
   if(bp>0 && lift>1.20 && wl>bp)      cls="hi";
   else if(bp>0 && lift<0.80)          cls="lo";
   return "<td class=\""+cls+"\">"+F(100.0*p,1)+"% <span class=\"nz\">x"+F(lift,2)+"</span></td>";
}

//==================================================================
//  ELABORAZIONE DI UN SIMBOLO
//==================================================================
bool ProcessSymbol(string sym)
{
   uint tPhase=GetTickCount();
   g_sym=sym;
   DBG(1,"=== ["+sym+"] FASE 1: selezione simbolo ===");
   if(!SymbolSelect(sym,true)){ PrintFormat("[%s] ERRORE: impossibile selezionare il simbolo (err %d)",sym,GetLastError()); return false; }
   g_point=SymbolInfoDouble(sym,SYMBOL_POINT);
   if(g_point<=0){ PrintFormat("[%s] ERRORE: point non valido (%.10f)",sym,g_point); return false; }
   int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   DBG(1,"["+sym+"] point="+DoubleToString(g_point,10)+" digits="+IntegerToString(digits)+
         " -> 1 pip = "+IntegerToString(digits==3||digits==5?10:1)+" punti | trade mode="+
         IntegerToString((int)SymbolInfoInteger(sym,SYMBOL_TRADE_MODE))+" "+MS(tPhase));

   //--- daily (serve un warm-up per l'ATR)
   DBG(1,"=== ["+sym+"] FASE 2: storico DAILY ===");
   tPhase=GetTickCount();
   datetime warm = InpFrom - (datetime)((InpATRPeriod+5)*86400);
   MqlRates d1[];
   int nd = SafeCopyRates(sym, PERIOD_D1, warm, InpTo, d1);
   if(nd<InpATRPeriod+2)
   {
      PrintFormat("[%s] ERRORE: storico daily insufficiente (%d barre, ne servono %d). "
                  "Apri il grafico D1 del simbolo e premi Home per scaricare la storia. err=%d",
                  sym,nd,InpATRPeriod+2,GetLastError());
      return false;
   }
   DBG(1,"["+sym+"] D1: "+IntegerToString(nd)+" barre da "+TimeToString(d1[0].time,TIME_DATE)+
         " a "+TimeToString(d1[nd-1].time,TIME_DATE)+" "+MS(tPhase));

   //--- ATR daily calcolato in casa (indipendente da handle/indicatori)
   double atr[];
   ArrayResize(atr,nd); ArrayInitialize(atr,0.0);
   double tr[];
   ArrayResize(tr,nd); ArrayInitialize(tr,0.0);
   for(int i=0;i<nd;i++)
   {
      double h=d1[i].high, l=d1[i].low;
      double pc=(i>0? d1[i-1].close : d1[i].open);
      tr[i]=MathMax(h-l, MathMax(MathAbs(h-pc), MathAbs(l-pc)));
   }
   for(int i=InpATRPeriod;i<nd;i++)
   {
      double s=0;
      for(int j=i-InpATRPeriod+1;j<=i;j++) s+=tr[j];
      atr[i]=s/InpATRPeriod;
   }

   //--- storico del TF base e intervallo realmente analizzabile
   DBG(1,"=== ["+sym+"] FASE 3: storico "+EnumToString(InpBaseTF)+" ===");
   tPhase=GetTickCount();
   datetime effFrom=InpFrom;
   if(!PrepareHistory(sym, InpBaseTF, InpFrom, InpTo, effFrom))
   {
      PrintFormat("[%s] elaborazione annullata: storico %s non utilizzabile.",sym,EnumToString(InpBaseTF));
      return false;
   }
   DBG(1,"["+sym+"] storico pronto "+MS(tPhase));

   DBG(1,"=== ["+sym+"] FASE 4: calendario economico ===");
   tPhase=GetTickCount();
   LoadCalendar(sym, warm, InpTo);
   DBG(2,"["+sym+"] calendario "+MS(tPhase));

   //--- file di output
   string dir = InpOutDir+"\\";
   string fn  = SafeName(sym);
   int fDaily = INVALID_HANDLE, fLm = INVALID_HANDLE;
   if(InpWriteCsv)
   {
      fDaily = FileOpen(dir+fn+"_daily.csv",   FILE_WRITE|FILE_TXT|FILE_ANSI);
      fLm    = FileOpen(dir+fn+"_largest.csv", FILE_WRITE|FILE_TXT|FILE_ANSI);
   }
   g_html = INVALID_HANDLE;
   if(InpWriteHtml)
   {
      g_html = FileOpen(dir+fn+"_report.html", FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(g_html==INVALID_HANDLE)
         PrintFormat("[%s] ATTENZIONE: report HTML non creato (err %d)",sym,GetLastError());
      else
         HtmlHead(sym);
   }
   if(InpWriteCsv && (fDaily==INVALID_HANDLE || fLm==INVALID_HANDLE))
   {
      PrintFormat("[%s] ERRORE: impossibile aprire i file di output in %s\\MQL5\\Files\\%s (err %d)",
                  sym,TerminalInfoString(TERMINAL_DATA_PATH),InpOutDir,GetLastError());
      return false;
   }
   DBG(1,"=== ["+sym+"] FASE 5: output in "+TerminalInfoString(TERMINAL_DATA_PATH)+
         "\\MQL5\\Files\\"+InpOutDir+" ===");

   W(fDaily,
      "date;dow;month;"
      "prev_open;prev_high;prev_low;prev_close;prev_range_pt;prev_body_pt;prev_upwick_pt;prev_dnwick_pt;"
      "prev_dir;prev_close_pos;atr_pt;prev_range_atr;prev_body_atr;"
      "day_open;day_high;day_low;day_close;day_range_pt;"
      "pre_bars;pre_min;pre_up_pt;pre_dn_pt;pre_total_pt;pre_net_pt;pre_range_pt;"
      "pre_total_atr;pre_net_atr;pre_range_atr;pre_pct_prev_range;"
      "pre_ext_up_pt;pre_ext_dn_pt;pre_last;d_prevhigh_pt;d_prevlow_pt;"
      "lm_start;lm_end;lm_dir;lm_pt;lm_atr;lm_dur_min;lm_sess;lm_h1;lm_m15;"
      "news_flag;news_name;news_dist_min;news_imp\r\n");

   W(fLm,
      "date;dow;lm_start;lm_end;lm_dir;lm_pt;lm_atr;lm_dur_min;lm_sess;lm_h1;lm_m15;"
      "atr_pt;news_flag;news_name;news_dist_min;news_imp\r\n");

   //--- contatori per la distribuzione oraria
   int cntH1[24];      ArrayInitialize(cntH1,0);
   double sumH1[24];   ArrayInitialize(sumH1,0.0);
   int c1AtrH1[24];    ArrayInitialize(c1AtrH1,0);
   int c2AtrH1[24];    ArrayInitialize(c2AtrH1,0);
   int cntM15[96];     ArrayInitialize(cntM15,0);
   double sumM15[96];  ArrayInitialize(sumM15,0.0);
   int c1AtrM15[96];   ArrayInitialize(c1AtrM15,0);
   int c2AtrM15[96];   ArrayInitialize(c2AtrM15,0);

   string htmlLm[];    ArrayResize(htmlLm,0);      // righe della tabella Largest Move (scritte a fine ciclo)
   double lmAtrAll[];  ArrayResize(lmAtrAll,0);
   int    lmHourAll[]; ArrayResize(lmHourAll,0);
   int    nDays=0;
   int    nSkipped=0;
   int    skNoData=0, skFewBars=0, skNoAtr=0;   // motivi di scarto, per la diagnostica

   g_nScan=0; ArrayResize(g_scan,0);

   int stepMin  = (int)MathMax(InpScanStepMin, g_tfMin);
   int stepBars = (int)MathMax(1, stepMin/g_tfMin);
   int horBars  = (int)MathMax(1, InpScanHorizonMin/g_tfMin);

   if(g_html!=INVALID_HANDLE)
   {
      H("<section><h2>Tabella giornaliera</h2><div class=\"note\">Una riga per giornata. Il blocco <b>prev_*</b> "
        "descrive il giorno precedente; il blocco <b>pre_*</b> descrive cio' che il prezzo ha fatto nel giorno corrente "
        "<b>prima</b> che il Largest Move iniziasse, senza usare un solo dato successivo. Clic sull'intestazione per ordinare. "
        "Tutte le colonne, comprese quelle omesse qui, sono nel CSV.</div>");
      HtmlTableHead("tD","data;gg;range D-1;range D-1 ATR;dir D-1;close pos;ATR pt;pre min;pre up;pre dn;pre tot;"
                         "pre net;pre range;% range D-1;LM inizio;LM fine;LM dir;LM pt;LM ATR;durata;sessione;news",true);
   }

   //--- conteggio giornate nel periodo, per la barra di avanzamento
   int totDays=0;
   for(int di=1; di<nd; di++)
      if(d1[di].time>=effFrom && d1[di].time<=InpTo) totDays++;
   PrintFormat("[%s] giornate da elaborare: %d - inizio...",sym,totDays);
   uint tSym=GetTickCount();
   int  nProc=0;

   //--- ciclo sulle giornate
   for(int di=1; di<nd; di++)
   {
      if(IsStopped()){ Print("[",sym,"] interrotto dall'utente."); break; }
      if(d1[di].time < effFrom) continue;
      if(d1[di].time > InpTo)   break;
      if(atr[di-1]<=0) continue;

      datetime dStart = d1[di].time;
      datetime dEnd   = dStart + 86400 - 1;

      MqlRates r[];
      int n = CopyRates(sym, InpBaseTF, dStart, dEnd, r);
      if(n<=0)
      {
         nSkipped++; skNoData++;
         if(skNoData<=3) DBG(2,"["+sym+"] "+DateStr(dStart)+": nessuna barra "+EnumToString(InpBaseTF)+
                               " (CopyRates="+IntegerToString(n)+", err "+IntegerToString(GetLastError())+")");
         continue;
      }
      if(n<InpMinBarsDay)
      {
         nSkipped++; skFewBars++;
         if(skFewBars<=3) DBG(2,"["+sym+"] "+DateStr(dStart)+": solo "+IntegerToString(n)+
                               " barre, minimo richiesto "+IntegerToString(InpMinBarsDay));
         continue;
      }

      double atrPt = atr[di-1]/g_point;             // ATR del giorno PRECEDENTE (point-in-time)
      if(atrPt<=0){ nSkipped++; skNoAtr++; continue; }

      nProc++;
      if(nProc%100==0)
      {
         double el =(GetTickCount()-tSym)/1000.0;
         double eta=(nProc>0 ? el*(totDays-nProc)/nProc : 0.0);
         PrintFormat("[%s] %d/%d giorni (%.1f%%) - trascorsi %.0fs, stimati %.0fs rimanenti - righe scan: %d",
                     sym,nProc,totDays,100.0*nProc/MathMax(1,totDays),el,eta,g_nScan);
      }

      //--- blocco D-1
      double pO=d1[di-1].open, pH=d1[di-1].high, pL=d1[di-1].low, pC=d1[di-1].close;
      double pRange=(pH-pL)/g_point;
      double pBody =MathAbs(pC-pO)/g_point;
      double pUpW  =(pH-MathMax(pO,pC))/g_point;
      double pDnW  =(MathMin(pO,pC)-pL)/g_point;
      int    pDir  =(pC>=pO? 1 : -1);
      double pClosePos = (pH>pL ? (pC-pL)/(pH-pL) : 0.5);

      //--- prefissi del giorno corrente (percorso cumulato barra per barra)
      double cUp[], cDn[], rHigh[], rLow[];
      ArrayResize(cUp,n); ArrayResize(cDn,n); ArrayResize(rHigh,n); ArrayResize(rLow,n);
      double au=0, ad=0, hh=-DBL_MAX, ll=DBL_MAX;
      for(int i=0;i<n;i++)
      {
         double u,dd; BarPath(r[i],u,dd);
         au+=u; ad+=dd;
         if(r[i].high>hh) hh=r[i].high;
         if(r[i].low <ll) ll=r[i].low;
         cUp[i]=au; cDn[i]=ad; rHigh[i]=hh; rLow[i]=ll;
      }

      //--- Largest Move
      int suI,euI,sdI,edI; double bu,bd;
      MaxRun(r,n,+1,InpCleanLeg,InpMaxRetracePct,suI,euI,bu);
      MaxRun(r,n,-1,InpCleanLeg,InpMaxRetracePct,sdI,edI,bd);
      int lmDir, lmS, lmE; double lmRaw;
      if(bu>=bd){ lmDir=1;  lmS=suI; lmE=euI; lmRaw=bu; }
      else      { lmDir=-1; lmS=sdI; lmE=edI; lmRaw=bd; }
      double lmPt  = lmRaw/g_point;
      double lmAtr = lmPt/atrPt;
      datetime lmStart = r[lmS].time;
      datetime lmEnd   = r[lmE].time + g_tfMin*60;
      int lmDur = (int)((lmEnd-lmStart)/60);

      //--- stato PRE-evento: SOLO barre con indice < lmS (nessun dato futuro)
      int preBars = lmS;
      double preUp=0, preDn=0, preHi=0, preLo=0, preLast=0;
      if(preBars>0)
      {
         preUp = cUp[preBars-1]/g_point;
         preDn = cDn[preBars-1]/g_point;
         preHi = rHigh[preBars-1];
         preLo = rLow[preBars-1];
         preLast = r[preBars-1].close;
      }
      else
      {
         preHi = r[0].open; preLo = r[0].open; preLast = r[0].open;
      }
      double preTot = preUp+preDn;
      double preNet = preUp-preDn;
      double preRange = (preHi-preLo)/g_point;
      double prePct = (pRange>0 ? preRange/pRange*100.0 : 0.0);
      double extUp = MathMax(0.0,(preHi-pH))/g_point;
      double extDn = MathMax(0.0,(pL-preLo))/g_point;
      double dHigh = (pH-preLast)/g_point;
      double dLow  = (preLast-pL)/g_point;

      MqlDateTime st; TimeToStruct(lmStart,st);
      int sess=SessOf(st.hour);
      int m15 = st.hour*4 + st.min/15;

      int nDist=0;
      int ni = NearestNews(lmStart,nDist);
      string nName = (ni>=0 ? g_newsName[ni] : "");
      int    nImp  = (ni>=0 ? g_newsImp[ni]  : 0);
      int    nFlag = (ni>=0 && MathAbs(nDist)<=InpNewsWindowMin ? 1 : 0);
      StringReplace(nName,";",",");

      string dayRow=
         DateStr(dStart)+";"+DowIT(st.day_of_week)+";"+MonIT(st.mon)+";"+
         F(pO,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))+";"+
         F(pH,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))+";"+
         F(pL,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))+";"+
         F(pC,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))+";"+
         F(pRange,1)+";"+F(pBody,1)+";"+F(pUpW,1)+";"+F(pDnW,1)+";"+
         (pDir>0?"UP":"DOWN")+";"+F(pClosePos,3)+";"+F(atrPt,1)+";"+
         F(pRange/atrPt,3)+";"+F(pBody/atrPt,3)+";"+
         F(r[0].open,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))+";"+
         F(rHigh[n-1],(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))+";"+
         F(rLow[n-1],(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))+";"+
         F(r[n-1].close,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))+";"+
         F((rHigh[n-1]-rLow[n-1])/g_point,1)+";"+
         IntegerToString(preBars)+";"+IntegerToString(preBars*g_tfMin)+";"+
         F(preUp,1)+";"+F(preDn,1)+";"+F(preTot,1)+";"+F(preNet,1)+";"+F(preRange,1)+";"+
         F(preTot/atrPt,3)+";"+F(preNet/atrPt,3)+";"+F(preRange/atrPt,3)+";"+F(prePct,1)+";"+
         F(extUp,1)+";"+F(extDn,1)+";"+
         F(preLast,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS))+";"+F(dHigh,1)+";"+F(dLow,1)+";"+
         HM(lmStart)+";"+HM(lmEnd)+";"+(lmDir>0?"BUY":"SELL")+";"+
         F(lmPt,1)+";"+F(lmAtr,3)+";"+IntegerToString(lmDur)+";"+SessName(sess)+";"+
         D2(st.hour)+":00;"+M15Label(st.hour,st.min)+";"+
         IntegerToString(nFlag)+";"+nName+";"+IntegerToString(nDist)+";"+IntegerToString(nImp);
      W(fDaily,dayRow+"\r\n");

      W(fLm,
         DateStr(dStart)+";"+DowIT(st.day_of_week)+";"+HM(lmStart)+";"+HM(lmEnd)+";"+
         (lmDir>0?"BUY":"SELL")+";"+F(lmPt,1)+";"+F(lmAtr,3)+";"+IntegerToString(lmDur)+";"+
         SessName(sess)+";"+D2(st.hour)+":00;"+M15Label(st.hour,st.min)+";"+F(atrPt,1)+";"+
         IntegerToString(nFlag)+";"+nName+";"+IntegerToString(nDist)+";"+IntegerToString(nImp)+"\r\n");

      if(g_html!=INVALID_HANDLE)
      {
         string cd=(lmDir>0?"up":"dn"), cn=(preNet>=0?"up":"dn");
         H("<tr><td>"+DateStr(dStart)+"</td><td>"+DowIT(st.day_of_week)+"</td><td>"+F(pRange,1)+"</td><td>"+
           F(pRange/atrPt,2)+"</td><td class=\""+(pDir>0?"up":"dn")+"\">"+(pDir>0?"UP":"DOWN")+"</td><td>"+
           F(pClosePos,2)+"</td><td>"+F(atrPt,1)+"</td><td>"+IntegerToString(preBars*g_tfMin)+"</td><td>"+
           F(preUp,1)+"</td><td>"+F(preDn,1)+"</td><td>"+F(preTot,1)+"</td><td class=\""+cn+"\">"+F(preNet,1)+
           "</td><td>"+F(preRange,1)+"</td><td>"+F(prePct,1)+"</td><td>"+HM(lmStart)+"</td><td>"+HM(lmEnd)+
           "</td><td class=\""+cd+"\">"+(lmDir>0?"BUY":"SELL")+"</td><td>"+F(lmPt,1)+"</td><td>"+F(lmAtr,2)+
           "</td><td>"+IntegerToString(lmDur)+"</td><td>"+SessName(sess)+"</td><td>"+
           (nFlag>0?HE(nName):"-")+"</td></tr>");

         int hq=ArraySize(htmlLm);
         ArrayResize(htmlLm,hq+1,512);
         htmlLm[hq]="<tr><td>"+DateStr(dStart)+"</td><td>"+DowIT(st.day_of_week)+"</td><td>"+HM(lmStart)+
           "</td><td>"+HM(lmEnd)+"</td><td class=\""+cd+"\">"+(lmDir>0?"BUY":"SELL")+"</td><td>"+F(lmPt,1)+
           "</td><td>"+F(lmAtr,2)+"</td><td>"+IntegerToString(lmDur)+"</td><td>"+SessName(sess)+"</td><td>"+
           D2(st.hour)+":00</td><td>"+M15Label(st.hour,st.min)+"</td><td>"+F(atrPt,1)+"</td><td>"+
           (nFlag>0?HE(nName):"-")+"</td><td>"+(ni>=0?IntegerToString(nDist):"")+"</td></tr>";
      }

      cntH1[st.hour]++;  sumH1[st.hour]+=lmPt;
      if(lmAtr>1.0) c1AtrH1[st.hour]++;
      if(lmAtr>2.0) c2AtrH1[st.hour]++;
      cntM15[m15]++;     sumM15[m15]+=lmPt;
      if(lmAtr>1.0) c1AtrM15[m15]++;
      if(lmAtr>2.0) c2AtrM15[m15]++;

      if(InpDebug>=3 && nDays<InpDebugDays)
         PrintFormat("[%s] DUMP %s | barre=%d ATR(D-1)=%.1fpt | D-1 range=%.1fpt dir=%s | "
                     "LM %s->%s %s %.1fpt (%.2f ATR) dur=%dmin | pre: barre=%d up=%.1f dn=%.1f net=%.1f range=%.1f (%.1f%% del range D-1)",
                     sym,DateStr(dStart),n,atrPt,pRange,(pDir>0?"UP":"DOWN"),
                     HM(lmStart),HM(lmEnd),(lmDir>0?"BUY":"SELL"),lmPt,lmAtr,lmDur,
                     preBars,preUp,preDn,preNet,preRange,prePct);

      int q=ArraySize(lmAtrAll);
      ArrayResize(lmAtrAll,q+1,512); lmAtrAll[q]=lmAtr;
      ArrayResize(lmHourAll,q+1,512); lmHourAll[q]=st.hour;
      nDays++;

      //================= GRIGLIA POINT-IN-TIME =====================
      if(InpDoScan)
      {
         for(int g=stepBars; g<n-1; g+=stepBars)
         {
            int endIdx = (int)MathMin(n-1, g+horBars);
            if(endIdx<=g) break;

            SScan s;
            s.t=r[g].time;
            MqlDateTime gt; TimeToStruct(s.t,gt);
            s.dow=gt.day_of_week; s.hour=gt.hour; s.minute=gt.min; s.sess=SessOf(gt.hour);
            s.atrPt=atrPt;
            s.prevRangeAtr=pRange/atrPt;
            s.prevBodyAtr =pBody/atrPt;
            s.prevClosePos=pClosePos;
            s.prevDir=pDir;

            // feature costruite SOLO con barre 0..g-1
            double up=cUp[g-1]/g_point, dn=cDn[g-1]/g_point;
            double hi=rHigh[g-1], lo=rLow[g-1];
            s.preUpPt=up; s.preDnPt=dn; s.preTotPt=up+dn; s.preNetPt=up-dn;
            s.preUpAtr=up/atrPt; s.preDnAtr=dn/atrPt;
            s.preTotAtr=(up+dn)/atrPt; s.preNetAtr=(up-dn)/atrPt;
            s.preRangeAtr=((hi-lo)/g_point)/atrPt;
            s.prePctPrevRange=(pRange>0 ? ((hi-lo)/g_point)/pRange*100.0 : 0.0);
            s.preExtUpAtr=(MathMax(0.0,hi-pH)/g_point)/atrPt;
            s.preExtDnAtr=(MathMax(0.0,pL-lo)/g_point)/atrPt;
            s.preMin=g*g_tfMin;

            double entry=r[g].open;
            s.dToPrevHighAtr=((pH-entry)/g_point)/atrPt;
            s.dToPrevLowAtr =((entry-pL)/g_point)/atrPt;

            int nextNews=MinutesToNextNews(s.t);
            s.newsAheadMin=nextNews;
            s.newsFlag=((nextNews>=0 && nextNews<=InpNewsWindowMin)?1:0);

            // esito forward (passata unica: MFE + first touch di tutte le soglie)
            ResolveForward(r,g,endIdx,entry,atrPt,s);

            ArrayResize(g_scan,g_nScan+1,4096);
            g_scan[g_nScan]=s;
            g_nScan++;
         }
      }
   }

   if(fDaily!=INVALID_HANDLE) FileClose(fDaily);
   if(fLm   !=INVALID_HANDLE) FileClose(fLm);

   if(g_html!=INVALID_HANDLE)
   {
      HtmlTableEnd(); H("</section>");                       // chiude la tabella giornaliera

      H("<section><h2>Largest Move per giornata</h2><div class=\"note\">Il movimento direzionale piu' ampio di ogni "
        "giornata, con orario di inizio ricavato dal timestamp della barra che lo avvia (risoluzione = TF base), "
        "non dalla chiusura daily. Ordina per <b>LM ATR</b> per isolare le giornate realmente esplosive.</div>");
      HtmlTableHead("tL","data;gg;inizio;fine;dir;punti;ATR;durata min;sessione;ora;fascia 15m;ATR pt;news;dist news min",true);
      for(int i=0;i<ArraySize(htmlLm);i++) H(htmlLm[i]);
      HtmlTableEnd(); H("</section>");
   }
   DBG(1,"["+sym+"] scritte "+IntegerToString(nDays)+" righe in "+fn+"_daily.csv e "+fn+"_largest.csv");

   //--- tabella distribuzione oraria
   int maxH1=0, maxM15=0;
   for(int h=0;h<24;h++) if(cntH1[h]>maxH1)   maxH1=cntH1[h];
   for(int b=0;b<96;b++) if(cntM15[b]>maxM15) maxM15=cntM15[b];

   if(g_html!=INVALID_HANDLE)
   {
      H("<section><h2>Quando avviene il movimento maggiore</h2><div class=\"note\">Distribuzione dell'orario di inizio "
        "del Largest Move. La granularita' a 15 minuti serve a distinguere una singola finestra realmente calda da "
        "un'intera sessione: se una fascia da 15 minuti concentra molti piu' movimenti delle vicine, e' li' che vale "
        "la pena essere presenti. <b>Ora server del broker</b>: con il cambio ora legale le fasce slittano di un'ora.</div>");
      H("<h2>Fasce orarie (H1)</h2>");
      HtmlTableHead("tH","fascia;n movimenti;distribuzione;% giornate;media pt;mediana ATR;&gt;1 ATR;&gt;2 ATR",false);
      for(int h=0;h<24;h++)
      {
         if(cntH1[h]==0) continue;
         double med[]; ArrayResize(med,0);
         for(int i=0;i<ArraySize(lmAtrAll);i++)
            if(lmHourAll[i]==h){ int m=ArraySize(med); ArrayResize(med,m+1,512); med[m]=lmAtrAll[i]; }
         int wpc=(maxH1>0? (int)(100.0*cntH1[h]/maxH1) : 0);
         H("<tr><td>"+D2(h)+":00-"+D2((h+1)%24)+":00</td><td>"+IntegerToString(cntH1[h])+
           "</td><td><span class=\"bw\"><span class=\"bf\" style=\"width:"+IntegerToString(wpc)+"%\"></span></span></td><td>"+
           F(100.0*cntH1[h]/MathMax(1,nDays),1)+"</td><td>"+F(sumH1[h]/cntH1[h],1)+"</td><td>"+F(Median(med),2)+
           "</td><td>"+IntegerToString(c1AtrH1[h])+"</td><td>"+IntegerToString(c2AtrH1[h])+"</td></tr>");
      }
      HtmlTableEnd();
      H("<h2>Fasce da 15 minuti</h2>");
      HtmlTableHead("tM","fascia;n movimenti;distribuzione;% giornate;media pt;&gt;1 ATR;&gt;2 ATR",true);
      for(int b=0;b<96;b++)
      {
         if(cntM15[b]==0) continue;
         int hh2=b/4, mm2=(b%4)*15;
         int wpc=(maxM15>0? (int)(100.0*cntM15[b]/maxM15) : 0);
         H("<tr><td>"+M15Label(hh2,mm2)+"</td><td>"+IntegerToString(cntM15[b])+
           "</td><td><span class=\"bw\"><span class=\"bf\" style=\"width:"+IntegerToString(wpc)+"%\"></span></span></td><td>"+
           F(100.0*cntM15[b]/MathMax(1,nDays),1)+"</td><td>"+F(sumM15[b]/cntM15[b],1)+"</td><td>"+
           IntegerToString(c1AtrM15[b])+"</td><td>"+IntegerToString(c2AtrM15[b])+"</td></tr>");
      }
      HtmlTableEnd(); H("</section>");
   }

   int fTd=(InpWriteCsv? FileOpen(dir+fn+"_timedist.csv",FILE_WRITE|FILE_TXT|FILE_ANSI) : INVALID_HANDLE);
   if(fTd!=INVALID_HANDLE)
   {
      W(fTd,"granularita;bucket;n_lm;pct_giornate;media_pt;mediana_atr;n_gt1atr;n_gt2atr\r\n");
      for(int h=0;h<24;h++)
      {
         if(cntH1[h]==0) continue;
         double med[]; ArrayResize(med,0);
         for(int i=0;i<ArraySize(lmAtrAll);i++)
            if(lmHourAll[i]==h){ int m=ArraySize(med); ArrayResize(med,m+1); med[m]=lmAtrAll[i]; }
         W(fTd,"H1;"+D2(h)+":00-"+D2((h+1)%24)+":00;"+IntegerToString(cntH1[h])+";"+
            F(100.0*cntH1[h]/MathMax(1,nDays),2)+";"+F(sumH1[h]/cntH1[h],1)+";"+F(Median(med),3)+";"+
            IntegerToString(c1AtrH1[h])+";"+IntegerToString(c2AtrH1[h])+"\r\n");
      }
      for(int b=0;b<96;b++)
      {
         if(cntM15[b]==0) continue;
         int hh2=b/4, mm2=(b%4)*15;
         W(fTd,"M15;"+M15Label(hh2,mm2)+";"+IntegerToString(cntM15[b])+";"+
            F(100.0*cntM15[b]/MathMax(1,nDays),2)+";"+F(sumM15[b]/cntM15[b],1)+";;"+
            IntegerToString(c1AtrM15[b])+";"+IntegerToString(c2AtrM15[b])+"\r\n");
      }
      FileClose(fTd);
   }

   //--- CSV grezzo dello scan
   if(InpDoScan && InpWriteScanRows && g_nScan>0)
   {
      int fS=(InpWriteCsv? FileOpen(dir+fn+"_scan.csv",FILE_WRITE|FILE_TXT|FILE_ANSI) : INVALID_HANDLE);
      if(fS!=INVALID_HANDLE)
      {
         string hdr="datetime;date;dow;hour;m15;sess;atr_pt;prev_dir;prev_range_atr;prev_body_atr;prev_close_pos;"
                    "pre_min;pre_up_pt;pre_dn_pt;pre_total_pt;pre_net_pt;pre_total_atr;pre_net_atr;pre_range_atr;"
                    "pre_pct_prev_range;pre_ext_up_atr;pre_ext_dn_atr;d_prevhigh_atr;d_prevlow_atr;"
                    "news_flag;news_ahead_min;mfe_up_pt;mfe_dn_pt;mfe_up_atr;mfe_dn_atr;mfe_max_atr";
         for(int k=0;k<g_nPt;k++)  hdr+=";hitup_"+F(g_thrPt[k],0)+"pt;hitdn_"+F(g_thrPt[k],0)+"pt";
         for(int k=0;k<g_nAtr;k++) hdr+=";hitup_"+F(g_thrAtr[k],2)+"atr;hitdn_"+F(g_thrAtr[k],2)+"atr";
         W(fS,hdr+"\r\n");

         for(int i=0;i<g_nScan;i++)
         {
            SScan s=g_scan[i];
            string row=TimeToString(s.t,TIME_DATE|TIME_MINUTES)+";"+DateStr(s.t)+";"+DowIT(s.dow)+";"+
               D2(s.hour)+":00;"+M15Label(s.hour,s.minute)+";"+SessName(s.sess)+";"+F(s.atrPt,1)+";"+
               (s.prevDir>0?"UP":"DOWN")+";"+F(s.prevRangeAtr,3)+";"+F(s.prevBodyAtr,3)+";"+F(s.prevClosePos,3)+";"+
               IntegerToString(s.preMin)+";"+F(s.preUpPt,1)+";"+F(s.preDnPt,1)+";"+F(s.preTotPt,1)+";"+F(s.preNetPt,1)+";"+
               F(s.preTotAtr,3)+";"+F(s.preNetAtr,3)+";"+F(s.preRangeAtr,3)+";"+F(s.prePctPrevRange,1)+";"+
               F(s.preExtUpAtr,3)+";"+F(s.preExtDnAtr,3)+";"+F(s.dToPrevHighAtr,3)+";"+F(s.dToPrevLowAtr,3)+";"+
               IntegerToString(s.newsFlag)+";"+IntegerToString(s.newsAheadMin)+";"+
               F(s.mfeUpPt,1)+";"+F(s.mfeDnPt,1)+";"+F(s.mfeUpAtr,3)+";"+F(s.mfeDnAtr,3)+";"+F(s.mfeMaxAtr,3);
            for(int k=0;k<g_nPt;k++)  row+=";"+IntegerToString(s.hitUpPt[k])+";"+IntegerToString(s.hitDnPt[k]);
            for(int k=0;k<g_nAtr;k++) row+=";"+IntegerToString(s.hitUpAtr[k])+";"+IntegerToString(s.hitDnAtr[k]);
            W(fS,row+"\r\n");
         }
         FileClose(fS);
      }
   }

   //--- tabelle delle condizioni
   if(InpDoScan && g_nScan>0) BuildConditions(sym,dir);
   else if(g_html!=INVALID_HANDLE)
   {
      H("<section><h2>Condizioni incrociate</h2><div class=\"note\">Non generate: "
        "InpDoScan disattivato oppure zero righe nella griglia point-in-time.</div></section>");
      H("<section><h2>Condizioni marginali</h2><div class=\"note\">Non generate.</div></section>");
   }

   if(g_html!=INVALID_HANDLE)
   {
      double avgLm=0, medLm=0;
      double cp[]; ArrayCopy(cp,lmAtrAll);
      for(int i=0;i<ArraySize(lmAtrAll);i++) avgLm+=lmAtrAll[i];
      if(ArraySize(lmAtrAll)>0) avgLm/=ArraySize(lmAtrAll);
      medLm=Median(cp);
      int nBig=0; for(int i=0;i<ArraySize(lmAtrAll);i++) if(lmAtrAll[i]>1.0) nBig++;

      H("<div id=\"sumsrc\" style=\"display:none\">");
      H("<div class=\"card\"><span>giornate</span><b>"+IntegerToString(nDays)+"</b></div>");
      H("<div class=\"card\"><span>scartate</span><b>"+IntegerToString(nSkipped)+"</b></div>");
      H("<div class=\"card\"><span>righe point-in-time</span><b>"+IntegerToString(g_nScan)+"</b></div>");
      H("<div class=\"card\"><span>largest move medio</span><b>"+F(avgLm,2)+" ATR</b></div>");
      H("<div class=\"card\"><span>largest move mediano</span><b>"+F(medLm,2)+" ATR</b></div>");
      H("<div class=\"card\"><span>giornate &gt; 1 ATR</span><b>"+
        F(100.0*nBig/MathMax(1,nDays),1)+"%</b></div>");
      H("<div class=\"card\"><span>orizzonte forward</span><b>"+IntegerToString(InpScanHorizonMin)+" min</b></div>");
      H("<div class=\"card\"><span>stop / target</span><b>"+F(InpAdverseRatio,2)+"</b></div>");
      H("</div>");
      HtmlFoot();
      FileClose(g_html);
      g_html=INVALID_HANDLE;
      PrintFormat("[%s] report HTML: %s\\MQL5\\Files\\%s\\%s_report.html",
                  sym,TerminalInfoString(TERMINAL_DATA_PATH),InpOutDir,fn);
   }

   PrintFormat("[%s] RIEPILOGO: giornate analizzate %d | scartate %d (senza dati %d, poche barre %d, ATR nullo %d) | righe scan %d | TF %s",
               sym,nDays,nSkipped,skNoData,skFewBars,skNoAtr,g_nScan,EnumToString(InpBaseTF));
   if(nDays==0)
      PrintFormat("[%s] NESSUNA GIORNATA ANALIZZATA. Cause tipiche: storico %s non scaricato "
                  "(apri il grafico e premi Home), InpFrom/InpTo fuori dalla storia disponibile, "
                  "oppure InpMinBarsDay troppo alto (ora %d).",
                  sym,EnumToString(InpBaseTF),InpMinBarsDay);
   else if(InpDoScan && g_nScan==0)
      PrintFormat("[%s] ATTENZIONE: 0 righe di scan. InpScanHorizonMin (%d) o InpScanStepMin (%d) "
                  "sono probabilmente troppo grandi rispetto alla lunghezza della giornata.",
                  sym,InpScanHorizonMin,InpScanStepMin);
   return true;
}

//==================================================================
//  TABELLE DELLE CONDIZIONI (costruite dallo scan point-in-time)
//==================================================================
void BuildConditions(string sym,string dir)
{
   string fn=SafeName(sym);
   //--- baseline incondizionata
   int basePt[8], baseAtr[8];
   ArrayInitialize(basePt,0); ArrayInitialize(baseAtr,0);
   for(int i=0;i<g_nScan;i++)
   {
      for(int k=0;k<g_nPt;k++)  if(g_scan[i].hitUpPt[k]>=0  || g_scan[i].hitDnPt[k]>=0)  basePt[k]++;
      for(int k=0;k<g_nAtr;k++) if(g_scan[i].hitUpAtr[k]>=0 || g_scan[i].hitDnAtr[k]>=0) baseAtr[k]++;
   }

   //--- 1) tabella incrociata (tutte le dimensioni insieme)
   CellsInit();
   for(int i=0;i<g_nScan;i++)
   {
      SScan s=g_scan[i];
      int bR=BinOf(s.prevRangeAtr,g_edgePrevRange);
      int bT=BinOf(s.preTotAtr,   g_edgePreTotal);
      int bN=BinOf(s.preNetAtr,   g_edgePreNet);
      string key="R"+IntegerToString(bR)+"|D"+IntegerToString(s.prevDir>0?1:0)+
                 "|T"+IntegerToString(bT)+"|N"+IntegerToString(bN)+
                 "|S"+IntegerToString(s.sess)+"|W"+IntegerToString(s.newsFlag);
      string lab="prevRange "+BinLabel(bR,g_edgePrevRange,"ATR")+";"+
                 (s.prevDir>0?"UP":"DOWN")+";"+
                 "preTotal "+BinLabel(bT,g_edgePreTotal,"ATR")+";"+
                 "preNet "+BinLabel(bN,g_edgePreNet,"ATR")+";"+
                 SessName(s.sess)+";"+(s.newsFlag>0?"NEWS":"NO-NEWS");
      CellAdd(key,lab,s);
   }
   WriteCells(dir+fn+"_conditions.csv",
              "prev_range;prev_dir;pre_total;pre_net;sessione;news",
              basePt,baseAtr,
              "Condizioni incrociate",
              "Ogni riga e' una combinazione di sei condizioni misurate <b>prima</b> dell'ingresso. "
              "Le colonne delle soglie mostrano la probabilita' che il prezzo faccia quel movimento entro l'orizzonte "
              "prima di subire lo stop, e tra parentesi il <b>lift</b> sulla baseline. Verde = lift &gt; 1.20 e Wilson-low "
              "sopra la baseline, cioe' l'unico caso in cui vale la pena guardare. Rosso = sotto baseline. Grigio = rumore. "
              "Molte celle qui hanno pochi campioni: incrociare sei dimensioni frammenta i dati, quindi usa questa tabella "
              "per generare ipotesi e la tabella marginale per verificarle.",
              "tC");

   //--- 2) tabella marginale (una dimensione per volta)
   CellsInit();
   for(int i=0;i<g_nScan;i++)
   {
      SScan s=g_scan[i];
      int bR=BinOf(s.prevRangeAtr,g_edgePrevRange);
      int bT=BinOf(s.preTotAtr,   g_edgePreTotal);
      int bN=BinOf(s.preNetAtr,   g_edgePreNet);
      CellAdd("A|"+IntegerToString(bR),"prev_range_atr;"+BinLabel(bR,g_edgePrevRange,"ATR"),s);
      CellAdd("B|"+IntegerToString(s.prevDir>0?1:0),"prev_dir;"+(s.prevDir>0?"UP":"DOWN"),s);
      CellAdd("C|"+IntegerToString(bT),"pre_total_atr;"+BinLabel(bT,g_edgePreTotal,"ATR"),s);
      CellAdd("D|"+IntegerToString(bN),"pre_net_atr;"+BinLabel(bN,g_edgePreNet,"ATR"),s);
      CellAdd("E|"+IntegerToString(s.sess),"sessione;"+SessName(s.sess),s);
      CellAdd("F|"+IntegerToString(s.newsFlag),"news;"+(s.newsFlag>0?"NEWS":"NO-NEWS"),s);
      CellAdd("G|"+IntegerToString(s.hour),"ora;"+D2(s.hour)+":00",s);
      CellAdd("H|"+IntegerToString(s.hour*4+s.minute/15),"m15;"+M15Label(s.hour,s.minute),s);
      CellAdd("I|"+IntegerToString(s.dow),"giorno;"+DowIT(s.dow),s);
   }
   WriteCells(dir+fn+"_conditions_marg.csv","dimensione;valore",basePt,baseAtr,
              "Condizioni marginali",
              "La stessa statistica con una sola dimensione per volta. Molti piu' campioni per cella, quindi molto piu' "
              "affidabile: e' qui che si vede se una condizione regge davvero. Se un effetto e' visibile nella tabella "
              "incrociata ma sparisce qui, quasi sempre era rumore.",
              "tG");
}

void WriteCells(string path,string keyHeader,const int &basePt[],const int &baseAtr[],
                string title,string note,string tid)
{
   int f=FileOpen(path,FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f==INVALID_HANDLE){ PrintFormat("impossibile scrivere %s (err %d)",path,GetLastError()); return; }

   string hdr=keyHeader+";n";
   for(int k=0;k<g_nPt;k++)
      hdr+=";n_"+F(g_thrPt[k],0)+"pt;p_"+F(g_thrPt[k],0)+"pt;wlow_"+F(g_thrPt[k],0)+"pt;lift_"+F(g_thrPt[k],0)+"pt";
   for(int k=0;k<g_nAtr;k++)
      hdr+=";n_"+F(g_thrAtr[k],2)+"atr;p_"+F(g_thrAtr[k],2)+"atr;wlow_"+F(g_thrAtr[k],2)+"atr;lift_"+F(g_thrAtr[k],2)+"atr";
   hdr+=";media_mfe_atr;mediana_mfe_atr";
   W(f,hdr+"\r\n");

   //--- stessa tabella in HTML, in forma compatta: per ogni soglia una sola
   //--- cella "probabilita' (lift)", colorata secondo il criterio di rilevanza
   if(g_html!=INVALID_HANDLE)
   {
      H("<section><h2>"+HE(title)+"</h2><div class=\"note\">"+note+"</div>");
      string hcols=keyHeader+";n";
      for(int k=0;k<g_nPt;k++)  hcols+=";"+F(g_thrPt[k],0)+"pt";
      for(int k=0;k<g_nAtr;k++) hcols+=";"+F(g_thrAtr[k],2)+" ATR";
      hcols+=";MFE medio ATR;MFE mediano ATR";
      HtmlTableHead(tid,hcols,true);
   }

   for(int c=0;c<g_nCell;c++)
   {
      if(g_cell[c].n<InpMinSamples) continue;
      int n=g_cell[c].n;
      string row=g_cell[c].label+";"+IntegerToString(n);
      for(int k=0;k<g_nPt;k++)
      {
         int hits=g_cell[c].hitPt[k];
         double p=(double)hits/n;
         double bp=(g_nScan>0 ? (double)basePt[k]/g_nScan : 0.0);
         row+=";"+IntegerToString(hits)+";"+F(100.0*p,2)+";"+F(100.0*WilsonLow(hits,n),2)+";"+
              (bp>0? F(p/bp,3) : "");
      }
      for(int k=0;k<g_nAtr;k++)
      {
         int hits=g_cell[c].hitAtr[k];
         double p=(double)hits/n;
         double bp=(g_nScan>0 ? (double)baseAtr[k]/g_nScan : 0.0);
         row+=";"+IntegerToString(hits)+";"+F(100.0*p,2)+";"+F(100.0*WilsonLow(hits,n),2)+";"+
              (bp>0? F(p/bp,3) : "");
      }
      double med[]; ArrayCopy(med,g_cell[c].mfe);
      double mMean=g_cell[c].sumMfe/n, mMed=Median(med);
      row+=";"+F(mMean,3)+";"+F(mMed,3);
      W(f,row+"\r\n");

      if(g_html!=INVALID_HANDLE)
      {
         string h="<tr>";
         string lab[]; int nl=StringSplit(g_cell[c].label,StringGetCharacter(";",0),lab);
         for(int i=0;i<nl;i++) h+="<td>"+HE(lab[i])+"</td>";
         h+="<td>"+IntegerToString(n)+"</td>";
         for(int k=0;k<g_nPt;k++)  h+=CondCell(g_cell[c].hitPt[k], n, basePt[k]);
         for(int k=0;k<g_nAtr;k++) h+=CondCell(g_cell[c].hitAtr[k],n, baseAtr[k]);
         h+="<td>"+F(mMean,2)+"</td><td>"+F(mMed,2)+"</td></tr>";
         H(h);
      }
   }

   // riga baseline in coda: serve per leggere il lift in modo onesto
   string bl[];
   string b="BASELINE (tutte le righe);"+IntegerToString(g_nScan);
   for(int k=0;k<g_nPt;k++)
      b+=";"+IntegerToString(basePt[k])+";"+F(100.0*basePt[k]/MathMax(1,g_nScan),2)+";;1.000";
   for(int k=0;k<g_nAtr;k++)
      b+=";"+IntegerToString(baseAtr[k])+";"+F(100.0*baseAtr[k]/MathMax(1,g_nScan),2)+";;1.000";
   b+=";;";
   W(f,b+"\r\n");
   if(f!=INVALID_HANDLE) FileClose(f);

   if(g_html!=INVALID_HANDLE)
   {
      string hb="<tr class=\"nz\">";
      int nk=StringSplit(keyHeader,StringGetCharacter(";",0),bl);
      hb+="<td><b>BASELINE</b></td>";
      for(int i=1;i<nk;i++) hb+="<td>-</td>";
      hb+="<td>"+IntegerToString(g_nScan)+"</td>";
      for(int k=0;k<g_nPt;k++)
         hb+="<td>"+F(100.0*basePt[k]/MathMax(1,g_nScan),1)+"%</td>";
      for(int k=0;k<g_nAtr;k++)
         hb+="<td>"+F(100.0*baseAtr[k]/MathMax(1,g_nScan),1)+"%</td>";
      hb+="<td>-</td><td>-</td></tr>";
      H(hb);
      HtmlTableEnd(); H("</section>");
   }
   PrintFormat("scritto %s (%d celle, %d sopra soglia campioni)",path,g_nCell,InpMinSamples);
}

//==================================================================
//  ENTRY POINT
//==================================================================
void OnStart()
{
   g_tfMin=TFMinutes(InpBaseTF);
   if(g_tfMin<0)
   {
      Print("ERRORE: InpBaseTF deve essere compreso tra M1 e H1.");
      return;
   }
   g_nPt =ParseDoubles(InpThrPoints,g_thrPt);
   g_nAtr=ParseDoubles(InpThrATR,  g_thrAtr);
   if(g_nPt==0 && g_nAtr==0){ Print("ERRORE: nessuna soglia valida."); return; }
   if(InpFrom>=InpTo){ Print("ERRORE: intervallo date non valido."); return; }

   string syms[];
   if(InpSymbols=="*")
   {
      int tot=SymbolsTotal(true);
      ArrayResize(syms,tot);
      for(int i=0;i<tot;i++) syms[i]=SymbolName(i,true);
   }
   else if(StringLen(InpSymbols)==0)
   {
      ArrayResize(syms,1); syms[0]=_Symbol;
   }
   else
   {
      string parts[];
      int k=StringSplit(InpSymbols,StringGetCharacter(",",0),parts);
      ArrayResize(syms,0);
      int n=0;
      for(int i=0;i<k;i++)
      {
         string p=parts[i];
         StringTrimLeft(p); StringTrimRight(p);
         if(StringLen(p)==0) continue;
         ArrayResize(syms,n+1); syms[n]=p; n++;
      }
   }

   PrintFormat("=== VTRLS MoveResearch v1 === simboli:%d TF:%s periodo:%s -> %s",
               ArraySize(syms),EnumToString(InpBaseTF),
               TimeToString(InpFrom,TIME_DATE),TimeToString(InpTo,TIME_DATE));
   PrintFormat("Anti-bias: feature costruite solo con barre chiuse prima di t; "
               "esito = first touch target/stop (stop=%.2f*target) entro %d minuti.",
               InpAdverseRatio,InpScanHorizonMin);

   //--- dump della configurazione effettivamente in uso
   if(InpDebug>=1)
   {
      string sp="soglie punti ("+IntegerToString(g_nPt)+"):";
      for(int i=0;i<g_nPt;i++)  sp+=" "+F(g_thrPt[i],0);
      string sa="soglie ATR ("+IntegerToString(g_nAtr)+"):";
      for(int i=0;i<g_nAtr;i++) sa+=" "+F(g_thrAtr[i],2);
      Print(sp);
      Print(sa);
      PrintFormat("scan: passo %d min (%d barre), orizzonte %d min (%d barre), TF base %d min",
                  (int)MathMax(InpScanStepMin,g_tfMin),(int)MathMax(1,(int)MathMax(InpScanStepMin,g_tfMin)/g_tfMin),
                  InpScanHorizonMin,(int)MathMax(1,InpScanHorizonMin/g_tfMin),g_tfMin);
      PrintFormat("cartella dati terminale: %s",TerminalInfoString(TERMINAL_DATA_PATH));
      for(int i=0;i<ArraySize(syms);i++) Print("simbolo in coda: ",syms[i]);
      if(g_nPt>0)
         Print("PROMEMORIA: 1 punto = 1 tick del simbolo, NON 1 pip. "
               "Su un simbolo a 5 decimali 100 punti = 10 pip: taratura delle soglie in punti a tuo carico. "
               "Le soglie in ATR non hanno questo problema.");
   }

   uint t0=GetTickCount();
   for(int i=0;i<ArraySize(syms);i++)
      ProcessSymbol(syms[i]);

   PrintFormat("=== completato in %.1f s. Output in MQL5/Files/%s ===",
               (GetTickCount()-t0)/1000.0, InpOutDir);
}
//+------------------------------------------------------------------+
