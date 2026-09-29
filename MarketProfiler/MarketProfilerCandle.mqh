//+------------------------------------------------------------------+
//| MarketProfilerCandle.mqh - modulo aggiunto a MarketProfiler.mq5   |
//| Scheda 'Candele': tutti i 21 timeframe MT5, da M1 a MN1.          |
//| Anatomia delle candele, pattern con nome, sequenze di 2 e 3       |
//| candele, stati (ADX, VWAP, z-score, volume all'ora, volatilita'), |
//| posizione rispetto ad alti e bassi precedenti, orari, giorni,     |
//| settimane del mese, mesi, anni, impulsi e cosa li precede.        |
//+------------------------------------------------------------------+
input bool   InpCand = true;   // Candele: forme, sequenze, stati e orari di tutti i timeframe M1-MN1 (scheda Candele)
input int    InpCandYears = 0; // Candele: anni di storico per i timeframe fino a H1 (0 = tutto lo storico; M1 con molti anni e' lento)

#define CX_NTF   21
#define CX_NFAM  6      // famiglie di confronti per il controllo FDR
#define CX_NM    11     // metriche per osservazione delle classi
#define CX_NF    19     // campi dei risultati per classe
#define CX_NMK   5      // metriche per osservazione delle categorie
#define CX_NFK   17     // campi dei risultati per categoria
#define CX_NPS   30     // stati precedenti l'impulso
#define CX_NSD   7      // gruppi di stati precedenti

//--- classi: ogni candela appartiene a piu' classi (una per famiglia, piu' i pattern con nome e gli stati)
#define CX_C_ALL 0
#define CX_C_SH  1      // 20 forme x direzione: 1 + forma * 2 + direzione (1 = rialzista)
#define CX_C_S2  21     // 36 coppie di simboli
#define CX_C_S3  57     // 216 terne di simboli
#define CX_C_NP  273    // pattern con nome
#define CX_NNP   22
#define CX_C_ST  295    // serie di candele nella stessa direzione: 295 + (0 rialzista, 1 ribassista) * 6 + (lunghezza - 1)
#define CX_C_SV  307    // struttura rispetto alla candela precedente
#define CX_NSV   10
#define CX_C_AD  317    // ADX 4
#define CX_C_VW  321    // VWAP 5
#define CX_C_ZS  326    // z-score 5
#define CX_C_RV  331    // volume all'ora 4
#define CX_C_VO  335    // volatilita' 3
#define CX_C_SZ  338    // ampiezza 5
#define CX_C_DN  343    // posizione nelle ultime 20 candele 5
#define CX_C_PD  348    // giorno precedente 3
#define CX_C_PW  351    // settimana precedente 3
#define CX_C_PM  354    // mese precedente 3
#define CX_C_PH  357    // ora precedente (H1) 3
#define CX_C_P4  360    // 4 ore precedenti (H4) 3
#define CX_C_IU  363    // impulso rialzista
#define CX_C_ID  364    // impulso ribassista
#define CX_NCL   365

//--- categorie di tempo
#define CX_K_TOD 0      // ora del giorno (24)
#define CX_K_MOH 24     // minuto dell'ora (fino a 60)
#define CX_K_DOW 84     // giorno della settimana (7)
#define CX_K_WOM 91     // settimana del mese (5)
#define CX_K_MON 96     // mese (12)
#define CX_K_QTR 108    // trimestre (4)
#define CX_K_YR  112    // anno (fino a 40)
#define CX_K_ALL 152
#define CX_NCU   153

int    CX_SEC[CX_NTF]  = {60, 120, 180, 240, 300, 360, 600, 720, 900, 1200, 1800, 3600, 7200, 10800, 14400, 21600, 28800, 43200, 86400, 604800, 2592000};
string CX_NAME[CX_NTF] = {"M1", "M2", "M3", "M4", "M5", "M6", "M10", "M12", "M15", "M20", "M30", "H1", "H2", "H3", "H4", "H6", "H8", "H12", "D1", "W1", "MN1"};

string CX_SHN[10] = {"Doji", "Doji libellula", "Doji lapide", "Doji a gambe lunghe", "Pin inferiore (martello)", "Pin superiore (stella cadente)",
                     "Trottola", "Corpo medio", "Corpo lungo", "Marubozu"};
string CX_NPN[CX_NNP] = {"Engulfing rialzista", "Engulfing ribassista", "Harami rialzista", "Harami ribassista", "Tweezer al minimo", "Tweezer al massimo",
                         "Morning star", "Evening star", "Tre soldati bianchi", "Tre corvi neri", "Pin rialzista al minimo di 10 candele",
                         "Pin ribassista al massimo di 10 candele", "NR4: range minimo delle ultime 4", "NR7: range minimo delle ultime 7",
                         "Chiusura sopra il massimo di 20 candele", "Chiusura sotto il minimo di 20 candele", "Inside bar dopo una candela ampia",
                         "Due inside bar di fila", "Tre rialziste con range crescente", "Tre ribassiste con range crescente",
                         "Outside bar rialzista (chiude sopra il massimo precedente)", "Outside bar ribassista (chiude sotto il minimo precedente)"};
string CX_SVN[CX_NSV] = {"Inside bar (dentro la candela precedente)", "Outside bar (oltre massimo e minimo precedenti)", "Solo massimo piu' alto",
                         "Solo minimo piu' basso", "Falsa rottura del massimo (rompe e chiude sotto)", "Falsa rottura del minimo (rompe e chiude sopra)",
                         "Chiude sopra il massimo precedente", "Chiude sotto il minimo precedente", "Apre sopra il massimo precedente (gap)",
                         "Apre sotto il minimo precedente (gap)"};
string CX_STL[46] = {"ADX sotto 20 (laterale)", "ADX 20-30", "ADX 30-40 (trend)", "ADX oltre 40 (trend forte)",
                     "Sotto il VWAP di oltre 1,5 sigma", "Sotto il VWAP di 0,5-1,5 sigma", "Vicino al VWAP (entro 0,5 sigma)", "Sopra il VWAP di 0,5-1,5 sigma",
                     "Sopra il VWAP di oltre 1,5 sigma",
                     "Z-score del prezzo sotto -2", "Z-score tra -2 e -1", "Z-score tra -1 e +1", "Z-score tra +1 e +2", "Z-score sopra +2",
                     "Volume all'ora sotto 0,7", "Volume all'ora 0,7-1,3", "Volume all'ora 1,3-2", "Volume all'ora oltre 2",
                     "Volatilita' in compressione (ATR14/ATR100 sotto 0,8)", "Volatilita' normale (0,8-1,2)", "Volatilita' in espansione (oltre 1,2)",
                     "Ampiezza sotto 0,5 ATR", "Ampiezza 0,5-0,8 ATR", "Ampiezza 0,8-1,2 ATR", "Ampiezza 1,2-2 ATR", "Ampiezza oltre 2 ATR",
                     "Chiude nel decimo basso delle ultime 20 candele", "Chiude nel 10-35% delle ultime 20", "Chiude nel 35-65% delle ultime 20",
                     "Chiude nel 65-90% delle ultime 20", "Chiude nel decimo alto delle ultime 20",
                     "Sotto il minimo del periodo precedente (giorno)", "Dentro il range del periodo precedente (giorno)", "Sopra il massimo del periodo precedente (giorno)",
                     "Sotto il minimo del periodo precedente (settimana)", "Dentro il range del periodo precedente (settimana)", "Sopra il massimo del periodo precedente (settimana)",
                     "Sotto il minimo del periodo precedente (mese)", "Dentro il range del periodo precedente (mese)", "Sopra il massimo del periodo precedente (mese)",
                     "Sotto il minimo del periodo precedente (ora)", "Dentro il range del periodo precedente (ora)", "Sopra il massimo del periodo precedente (ora)",
                     "Sotto il minimo del periodo precedente (4 ore)", "Dentro il range del periodo precedente (4 ore)", "Sopra il massimo del periodo precedente (4 ore)"};
string CX_PSL[CX_NPS] = {"Volume all'ora sotto 0,7", "Volume all'ora 0,7-1,3", "Volume all'ora 1,3-2", "Volume all'ora oltre 2",
                         "ADX sotto 20", "ADX 20-30", "ADX 30-40", "ADX oltre 40",
                         "Sotto il VWAP di oltre 1,5 sigma", "Sotto il VWAP di 0,5-1,5 sigma", "Vicino al VWAP", "Sopra il VWAP di 0,5-1,5 sigma", "Sopra il VWAP di oltre 1,5 sigma",
                         "Z-score sotto -2", "Z-score tra -2 e -1", "Z-score tra -1 e +1", "Z-score tra +1 e +2", "Z-score sopra +2",
                         "Ultime 3 candele compresse (range sotto 1 ATR)", "Ultime 3 candele range 1-2 ATR", "Ultime 3 candele ampie (range oltre 2 ATR)",
                         "Ultime 3 candele in calo (oltre 1 ATR)", "Ultime 3 candele laterali", "Ultime 3 candele in rialzo (oltre 1 ATR)",
                         "Candela prima: doji", "Candela prima: pin", "Candela prima: trottola", "Candela prima: corpo medio", "Candela prima: corpo lungo",
                         "Candela prima: marubozu"};
int    CX_PSG[CX_NSD]  = {0, 4, 8, 13, 18, 21, 24};   // primo stato di ogni gruppo
int    CX_PSN[CX_NSD]  = {4, 4, 5, 5, 3, 3, 6};       // numero di stati di ogni gruppo
string CX_KDN[7] = {"Ora del giorno", "Minuto dell'ora", "Giorno della settimana", "Settimana del mese", "Mese", "Trimestre", "Anno"};
string CX_DOWN[7] = {"Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"};

//--- risultati per timeframe
int      g_cxN[CX_NTF];          // candele analizzate
datetime g_cxT0[CX_NTF], g_cxT1[CX_NTF];
double   g_cxThr[CX_NTF];        // soglia dell'impulso in ATR
double   g_cxImpP[CX_NTF];       // quota di impulsi
double   g_cxMedR[CX_NTF];       // range mediano in % del prezzo
double   g_cxBull[CX_NTF];       // quota di candele rialziste
double   g_cxBody[CX_NTF];       // corpo mediano in % del range
int      g_cxNimp[CX_NTF];       // impulsi
int      g_cxNrob[CX_NTF];       // test robusti
int      g_cxNtst[CX_NTF];       // test registrati con |z| >= 2
double   g_cxC[];                // classi: (ti * CX_NCL + cls) * CX_NF + campo
                                 //   0 n; 1 su dopo 1; 2 z; 3 test; 4 rendimento 1 (ATR); 5 z; 6 test; 7 range successivo; 8 rompe il massimo; 9 rompe il minimo;
                                 //   10 rendimento 3; 11 su dopo 3; 12 escursione max 3; 13 escursione min 3; 14 corsa +1/-1 ATR; 15 ampiezza propria; 16 quota; 17 z rend. 3; 18 test
double   g_cxK[];                // categorie: (ti * CX_NCU + unita') * CX_NFK + campo
                                 //   0 n; 1-5 medie (rialzista, rendimento in ATR, range in punti base, % oltre 1,5 ATR, % impulsi); 6-10 z; 11-15 indice del test (-1 nessuno); 16 quota
double   g_cxP[];                // precursori: ((ti * 2 + direzione dell'impulso) * CX_NPS + stato) * 4 + (osservati, attesi, z, test)
double   g_cxComp[];             // composizione: (ti * 3 + gruppo) * 8 + (famiglie 0-5, rialzisti, somma ampiezza); gruppo 0 tutte, 1 impulsi rialzisti, 2 ribassisti
datetime g_cxTopT[];             // i 5 movimenti maggiori: ti * 5 + i
double   g_cxTopR[], g_cxTopP[];
int      g_cxTopD[];
int      g_cxKY0[CX_NTF];        // primo anno
int      g_cxSkip[CX_NTF];       // 0 calcolato, 1 serie base troppo grossa, 2 dati insufficienti
int      g_cxNimpD[];            // impulsi per timeframe e direzione (0 rialzista, 1 ribassista): ti * 2 + d

//--- test registrati (solo |z| >= 2) per il controllo FDR
long   g_cxNAll = 0;
long   g_cxNFam[CX_NFAM];   // confronti per famiglia (vedi CxFamily)
int    g_cxNT = 0;
double g_cxTz[];
int    g_cxTtf[], g_cxTk[], g_cxTu[];
bool   g_cxTst[], g_cxTfd[];
string g_cxTtx[];

string  g_cxTxt = "", g_cxTxtTf = "";   // testo principale (riepiloghi) e testo dei singoli timeframe
int     g_cxCsv = INVALID_HANDLE, g_cxCsvK = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Motore statistico: somme per cluster (settimana) di ogni unita'   |
//| Per ogni unita': n, somma dei quadrati dei numeri di osservazioni |
//| per cluster, numero di cluster. Per ogni metrica: A = somma dei   |
//| valori, AA = somma dei quadrati delle somme di cluster, AB =      |
//| somma dei prodotti tra somma di cluster e numero di osservazioni  |
//| del cluster, SS = somma dei quadrati dei valori. In piu' i        |
//| prodotti incrociati tra cluster distanti 1..CX_NLAG, per la       |
//| correzione di Newey-West (la volatilita' persiste da una          |
//| settimana all'altra: senza correzione gli z dei confronti sul     |
//| ritmo dell'attivita' sarebbero gonfiati).                         |
//+------------------------------------------------------------------+
#define CX_NLAG 8

class CClu
  {
public:
   int               nu, nm, nt, fs, hs, rp, ne;
   double            S[], H[], tB[], tA[], L[], hA[], hB[];
   int               tl[], ev[];
   bool              tin[], sn[];
                     CClu(void) { nu = 0; nm = 0; nt = 0; fs = 0; hs = 0; rp = 0; ne = 0; }
   void              Init(const int units, const int metrics)
     {
      nu = units;
      nm = metrics;
      fs = 3 + 4 * nm;
      hs = 1 + nm;
      nt = 0;
      rp = 0;
      ne = 0;
      ArrayResize(S, nu * fs);
      ArrayResize(H, nu * 2 * hs);
      ArrayResize(tB, nu);
      ArrayResize(tA, nu * nm);
      ArrayResize(L, nu * nm * CX_NLAG * 3);
      ArrayResize(hA, nu * nm * CX_NLAG);
      ArrayResize(hB, nu * CX_NLAG);
      ArrayResize(tl, nu);
      ArrayResize(ev, nu);
      ArrayResize(tin, nu);
      ArrayResize(sn, nu);
      ArrayInitialize(S, 0.0);
      ArrayInitialize(H, 0.0);
      ArrayInitialize(tB, 0.0);
      ArrayInitialize(tA, 0.0);
      ArrayInitialize(L, 0.0);
      ArrayInitialize(hA, 0.0);
      ArrayInitialize(hB, 0.0);
      ArrayInitialize(tin, false);
      ArrayInitialize(sn, false);
     }
   void              Add(const int u, const double &v[], const int hf)
     {
      if(!tin[u])
        {
         tin[u] = true;
         tl[nt] = u;
         nt++;
         if(!sn[u])
           {
            sn[u] = true;
            ev[ne] = u;
            ne++;
           }
        }
      tB[u] += 1.0;
      int b = u * nm, h = (u * 2 + hf) * hs, s = u * fs;
      H[h] += 1.0;
      for(int m = 0; m < nm; m++)
        {
         tA[b + m] += v[m];
         H[h + 1 + m] += v[m];
         S[s + 6 + 4 * m] += v[m] * v[m];
        }
     }
   // chiude il cluster: aggiorna le somme delle unita' toccate e i prodotti incrociati con i cluster precedenti di tutte le unita' viste
   void              Flush(void)
     {
      for(int j = 0; j < nt; j++)
        {
         int u = tl[j];
         double B = tB[u];
         int s = u * fs, b = u * nm;
         S[s] += B;
         S[s + 1] += B * B;
         S[s + 2] += 1.0;
         for(int m = 0; m < nm; m++)
           {
            double A = tA[b + m];
            int q = s + 3 + 4 * m;
            S[q] += A;
            S[q + 1] += A * A;
            S[q + 2] += A * B;
           }
        }
      for(int j = 0; j < ne; j++)
        {
         int u = ev[j];
         double B = tin[u] ? tB[u] : 0.0;
         for(int k = 1; k <= CX_NLAG; k++)
           {
            int sl = (rp - k + 2 * CX_NLAG) % CX_NLAG;
            double Bp = hB[u * CX_NLAG + sl];
            for(int m = 0; m < nm; m++)
              {
               double A = tin[u] ? tA[u * nm + m] : 0.0;
               double Ap = hA[(u * nm + m) * CX_NLAG + sl];
               int li = ((u * nm + m) * CX_NLAG + k - 1) * 3;
               L[li] += A * Ap;
               L[li + 1] += A * Bp + B * Ap;
               L[li + 2] += B * Bp;
              }
           }
         hB[u * CX_NLAG + rp] = B;
         for(int m = 0; m < nm; m++)
            hA[(u * nm + m) * CX_NLAG + rp] = tin[u] ? tA[u * nm + m] : 0.0;
        }
      rp = (rp + 1) % CX_NLAG;
      for(int j = 0; j < nt; j++)
        {
         int u = tl[j];
         for(int m = 0; m < nm; m++)
            tA[u * nm + m] = 0.0;
         tB[u] = 0.0;
         tin[u] = false;
        }
      nt = 0;
     }
   double            N(const int u) { return S[u * fs]; }
   double            Clusters(const int u) { return S[u * fs + 2]; }
   double            Sum(const int u, const int m) { return S[u * fs + 3 + 4 * m]; }
   double            Mean(const int u, const int m)
     {
      double b = S[u * fs];
      return b > 0 ? S[u * fs + 3 + 4 * m] / b : Nan();
     }
  };

// varianza di Wald della somma dei valori dell'unita' u (metrica m): residui per cluster centrati sulla media dell'unita', con la correzione di
// Newey-West per l'autocorrelazione tra settimane vicine (la volatilita' persiste); mai sotto la somma dei quadrati dei residui
double CxWald(CClu &c, const int u, const int m)
  {
   int s = u * c.fs, q = s + 3 + 4 * m;
   double B = c.S[s];
   if(!(B > 0))
      return Nan();
   double mu = c.S[q] / B;
   double vs = c.S[q + 1] - 2.0 * mu * c.S[q + 2] + mu * mu * c.S[s + 1];
   double lrv = vs;
   for(int k = 1; k <= CX_NLAG; k++)
     {
      int li = ((u * c.nm + m) * CX_NLAG + k - 1) * 3;
      double cross = c.L[li] - mu * c.L[li + 1] + mu * mu * c.L[li + 2];
      lrv += 2.0 * (1.0 - (double)k / (CX_NLAG + 1.0)) * cross;
     }
   return MathMax(vs, lrv);
  }

// z della media dell'unita' u contro la media generale (unita' ua) per la metrica m.
// Metriche continue: z di Wald con errore robusto ai cluster (CxWald), non sotto la varianza dei valori dell'unita' per il numero di osservazioni.
// Metriche 0/1 (candele grandi, impulsi): varianza del modello nullo B p (1-p) per l'effetto di disegno misurato su tutte le candele (rapporto
// tra varianza di Wald e binomiale): con eventi rari la varianza di Wald si azzererebbe. Servono 10 cluster e 30 osservazioni; per le metriche 0/1
// almeno 2 eventi attesi e 2 non eventi attesi (con correzione di continuita'). Correzione G/(G-1).
double CxScore(CClu &c, const int u, const int ua, const int m)
  {
   int s = u * c.fs, q = s + 3 + 4 * m, sa = ua * c.fs, qa = sa + 3 + 4 * m;
   double B = c.S[s], Ba = c.S[sa], G = c.S[s + 2];
   if(B < 30 || Ba < 30 || G < 10)
      return Nan();
   double pa = c.S[qa] / Ba, v = 0;
   if(c.S[qa + 3] == c.S[qa])   // metrica 0/1
     {
      double e = pa * B;
      if(e < 2.0 || B - e < 2.0)
         return Nan();
      double vmA = Ba * pa * (1.0 - pa), vwA = CxWald(c, ua, m);
      double deff = (vmA > 0 && MathIsValidNumber(vwA)) ? MathMax(1.0, vwA / vmA) : 1.0;
      v = deff * B * pa * (1.0 - pa);
     }
   else
     {
      double mu = c.S[q] / B, sig2 = c.S[q + 3] / B - mu * mu;
      v = MathMax(CxWald(c, u, m), B * sig2);
     }
   if(!(v > 1e-300))
      return Nan();
   v *= G / (G - 1.0);
   double num = c.S[q] - pa * B;
   if(c.S[qa + 3] == c.S[qa])   // metrica 0/1: correzione di continuita'
      num = num > 0 ? MathMax(0.0, num - 0.5) : MathMin(0.0, num + 0.5);
   return num / MathSqrt(v);
  }

// stesso verso della differenza (unita' contro media generale) nelle due meta' del campione
bool CxStab(CClu &c, const int u, const int ua, const int m, const double z)
  {
   if(!MathIsValidNumber(z) || z == 0)
      return false;
   double d[2];
   for(int hf = 0; hf < 2; hf++)
     {
      int hu = (u * 2 + hf) * c.hs, ha = (ua * 2 + hf) * c.hs;
      double n = c.H[hu], na = c.H[ha];
      d[hf] = (n >= 15 && na >= 15) ? c.H[hu + 1 + m] / n - c.H[ha + 1 + m] / na : Nan();
     }
   return BxStable(z, d[0], d[1]);
  }

int CxUnitDim(const int u)
  {
   if(u < CX_K_MOH)
      return 0;
   if(u < CX_K_DOW)
      return 1;
   if(u < CX_K_WOM)
      return 2;
   if(u < CX_K_MON)
      return 3;
   if(u < CX_K_QTR)
      return 4;
   if(u < CX_K_YR)
      return 5;
   if(u < CX_K_ALL)
      return 6;
   return -1;
  }

// famiglia di un confronto: il controllo FDR si fa dentro ogni famiglia (le stagionalita' della volatilita' sono vere e numerose: nello stesso
// gruppo abbasserebbero la soglia delle ipotesi di direzione e dei giorni o mesi)
// 0 classi di candele (esito dopo), 1 direzione per ora e minuto, 2 direzione per giorno, settimana del mese, mese, trimestre, anno,
// 3 ritmo dell'attivita' (range, candele grandi, impulsi) per ora e minuto, 4 ritmo per giorno, settimana del mese, mese, trimestre, anno,
// 5 precursori degli impulsi
int CxFamily(const int kind, const int unit)
  {
   if(kind == 6)
      return 5;
   if(kind == 0 || kind == 1 || kind == 8)
      return 0;
   bool hm = CxUnitDim(unit) <= 1;
   if(kind == 2 || kind == 3)
      return hm ? 1 : 2;
   return hm ? 3 : 4;
  }

// tipi di confronto: 0 classe su, 1 classe rendimento 1, 2 categoria su, 3 categoria rendimento, 4 categoria % grandi, 5 categoria % impulsi,
// 6 precursore, 7 categoria range, 8 classe rendimento 3
// registra un confronto: contato sempre, memorizzato solo se |z| >= 2. Ritorna l'indice del test (-1 se non memorizzato)
int CxTestAdd(const int tf, const int kind, const int unit, const double z, const bool st)
  {
   if(!MathIsValidNumber(z))
      return -1;
   g_cxNAll++;
   g_cxNFam[CxFamily(kind, unit)]++;
   if(!HiKeep(ED_MC, z))
      return -1;
   int i = g_cxNT++;
   ArrayResize(g_cxTz, g_cxNT, 4096);
   ArrayResize(g_cxTtf, g_cxNT, 4096);
   ArrayResize(g_cxTk, g_cxNT, 4096);
   ArrayResize(g_cxTu, g_cxNT, 4096);
   ArrayResize(g_cxTst, g_cxNT, 4096);
   ArrayResize(g_cxTfd, g_cxNT, 4096);
   ArrayResize(g_cxTtx, g_cxNT, 4096);
   g_cxTtx[i] = "";
   g_cxTz[i] = z;
   g_cxTtf[i] = tf;
   g_cxTk[i] = kind;
   g_cxTu[i] = unit;
   g_cxTst[i] = st;
   g_cxTfd[i] = false;
   g_cxNtst[tf]++;
   return i;
  }

// testo del confronto memorizzato (anche nel riepilogo generale)
void CxSetTxt(const int id, const double z, const string txt)
  {
   if(id < 0 || id >= g_cxNT)
      return;
   g_cxTtx[id] = txt;
   HiAdd(ED_MC, z, txt);
  }

//+------------------------------------------------------------------+
//| Etichette                                                         |
//+------------------------------------------------------------------+
string CxSym(const int s) { return (s / 3 == 1 ? "+" : "-") + (s % 3 == 0 ? "P" : (s % 3 == 1 ? "N" : "G")); }

string CxLabel(const int cls)
  {
   if(cls == CX_C_ALL)
      return "Tutte le candele";
   if(cls < CX_C_S2)
     {
      int x = cls - CX_C_SH;
      return CX_SHN[x / 2] + ((x % 2) == 1 ? " rialzista" : " ribassista");
     }
   if(cls < CX_C_S3)
     {
      int x = cls - CX_C_S2;
      return CxSym(x / 6) + " " + CxSym(x % 6);
     }
   if(cls < CX_C_NP)
     {
      int x = cls - CX_C_S3;
      return CxSym(x / 36) + " " + CxSym((x / 6) % 6) + " " + CxSym(x % 6);
     }
   if(cls < CX_C_ST)
      return CX_NPN[cls - CX_C_NP];
   if(cls < CX_C_SV)
     {
      int x = cls - CX_C_ST;
      return (x < 6 ? "Serie rialzista di " : "Serie ribassista di ") + I2S(x % 6 + 1) + (x % 6 == 5 ? " o piu'" : "");
     }
   if(cls < CX_C_AD)
      return CX_SVN[cls - CX_C_SV];
   if(cls < CX_C_IU)
      return CX_STL[cls - CX_C_AD];
   return cls == CX_C_IU ? "Impulso rialzista" : "Impulso ribassista";
  }

// etichetta di una categoria di tempo (unita' globale)
string CxKLabel(const int ti, const int u)
  {
   if(u == CX_K_ALL)
      return "Tutte le candele";
   int sec = CX_SEC[ti];
   if(u < CX_K_MOH)
     {
      int h = u - CX_K_TOD;
      if(sec < 3600)
         return StringFormat("%02dh", h);
      int sl = 86400 / sec;
      int s0 = (86400 / sl) * h;
      if(sec <= 3600)
         return StringFormat("%02dh", h);
      return StringFormat("%02d-%02dh", s0 / 3600, (s0 + sec) / 3600);
     }
   if(u < CX_K_DOW)
      return StringFormat(":%02d", (u - CX_K_MOH) * (sec / 60));
   if(u < CX_K_WOM)
      return CX_DOWN[u - CX_K_DOW];
   if(u < CX_K_MON)
     {
      string w[5] = {"giorni 1-7", "giorni 8-14", "giorni 15-21", "giorni 22-28", "giorni 29-31"};
      return w[u - CX_K_WOM];
     }
   if(u < CX_K_QTR)
      return MON[u - CX_K_MON];
   if(u < CX_K_YR)
      return "Q" + I2S(u - CX_K_QTR + 1);
   return I2S(g_cxKY0[ti] + u - CX_K_YR);
  }

// numero di categorie di ogni dimensione per un timeframe (0 = dimensione non applicabile)
int CxDimN(const int ti, const int d)
  {
   int sec = CX_SEC[ti];
   if(d == 0)
      return sec >= 86400 ? 0 : (sec < 3600 ? 24 : 86400 / sec);
   if(d == 1)
      return sec < 3600 ? 3600 / sec : 0;
   if(d == 2)
      return sec <= 86400 ? 7 : 0;
   if(d == 3)
      return sec <= 604800 ? 5 : 0;
   if(d == 4)
      return 12;
   if(d == 5)
      return 4;
   return 40;
  }

int CxDimBase(const int d)
  {
   int b[7] = {CX_K_TOD, CX_K_MOH, CX_K_DOW, CX_K_WOM, CX_K_MON, CX_K_QTR, CX_K_YR};
   return b[d];
  }

// forma della candela (0-9) da corpo, ombre e range; direzione a parte
int CxShape(const double o, const double h, const double l, const double c)
  {
   double R = h - l;
   if(!(R > 0))
      return 6;
   double B = MathAbs(c - o), U = h - MathMax(o, c), L = MathMin(o, c) - l;
   double b = B / R, u = U / R, w = L / R;
   if(b <= 0.10)
     {
      if(w >= 0.60 && u <= 0.10)
         return 1;
      if(u >= 0.60 && w <= 0.10)
         return 2;
      if(u >= 0.30 && w >= 0.30)
         return 3;
      return 0;
     }
   if(b <= 0.35)
     {
      if(w >= 0.55 && u <= 0.20)
         return 4;
      if(u >= 0.55 && w <= 0.20)
         return 5;
      return 6;
     }
   if(b < 0.60)
      return 7;
   if(b < 0.85)
      return 8;
   return 9;
  }

int CxShapeFam(const int sh)   // 0 doji, 1 pin, 2 trottola, 3 corpo medio, 4 corpo lungo, 5 marubozu
  {
   if(sh <= 3)
      return 0;
   if(sh <= 5)
      return 1;
   return sh - 4;
  }

//+------------------------------------------------------------------+
//| Candele di un timeframe, costruite dalla serie base (M1 o M5)     |
//| Orologio dei dati; settimana da domenica; le barre nella finestra |
//| del rollover sono escluse dalle candele piu' lunghe di H1, mentre |
//| fino a H1 le candele che la toccano sono invalide.                |
//+------------------------------------------------------------------+
#define CX_NA 255   // stato non definito (pochi dati)

class CCx
  {
public:
   int               n, sec;
   long              key[];
   datetime          t[];
   double            o[], h[], l[], c[], v[], vw[], vs[];
   int               dy[], nb[], chn[];
   float             fa[];
   uchar             ok[];
   float             ap[], ac[], vr[], adx[], rv[], amp[];
   uchar             shp[], upd[], sym[], adc[], vwc[], zsc[], rvc[], voc[], szc[], dnc[], pdc[], pwc[], pmc[], phc[], p4c[], fl[];
                     CCx(void) { n = 0; sec = 0; }
   void              Alloc(const int m)
     {
      n = m;
      ArrayResize(key, m); ArrayResize(t, m);
      ArrayResize(o, m); ArrayResize(h, m); ArrayResize(l, m); ArrayResize(c, m); ArrayResize(v, m); ArrayResize(vw, m); ArrayResize(vs, m);
      ArrayResize(dy, m); ArrayResize(nb, m); ArrayResize(chn, m); ArrayResize(ok, m); ArrayResize(fa, m);
     }
   void              AllocFe(const int m)
     {
      ArrayResize(ap, m); ArrayResize(ac, m); ArrayResize(vr, m); ArrayResize(adx, m); ArrayResize(rv, m); ArrayResize(amp, m);
      ArrayResize(shp, m); ArrayResize(upd, m); ArrayResize(sym, m); ArrayResize(adc, m); ArrayResize(vwc, m); ArrayResize(zsc, m);
      ArrayResize(rvc, m); ArrayResize(voc, m); ArrayResize(szc, m); ArrayResize(dnc, m); ArrayResize(pdc, m); ArrayResize(pwc, m);
      ArrayResize(pmc, m); ArrayResize(phc, m); ArrayResize(p4c, m); ArrayResize(fl, m);
      if(m > 0)
        {
         float nf = (float)Nan();
         ArrayInitialize(ap, nf); ArrayInitialize(ac, nf); ArrayInitialize(vr, nf); ArrayInitialize(adx, nf); ArrayInitialize(rv, nf);
         ArrayInitialize(amp, nf);
         ArrayInitialize(shp, CX_NA); ArrayInitialize(upd, CX_NA); ArrayInitialize(sym, CX_NA); ArrayInitialize(adc, CX_NA);
         ArrayInitialize(vwc, CX_NA); ArrayInitialize(zsc, CX_NA); ArrayInitialize(rvc, CX_NA); ArrayInitialize(voc, CX_NA);
         ArrayInitialize(szc, CX_NA); ArrayInitialize(dnc, CX_NA); ArrayInitialize(pdc, CX_NA); ArrayInitialize(pwc, CX_NA);
         ArrayInitialize(pmc, CX_NA); ArrayInitialize(phc, CX_NA); ArrayInitialize(p4c, CX_NA); ArrayInitialize(fl, 0);
        }
     }
   void              Free(void)
     {
      Alloc(0);
      AllocFe(0);
      n = 0;
     }
  };

//--- livelli dei periodi piu' grandi: giorno, settimana, mese
CCx g_cxLvD, g_cxLvW, g_cxLvM, g_cxLvH, g_cxLvQ;   // giorno, settimana, mese, ora (H1) e 4 ore (H4)

// giorno, chiave della settimana (da domenica) e del mese, con cache per giorno
void CxDay(const long tt, long &cd, long &kW, long &kM)
  {
   long d = tt / 86400;
   if(d == cd)
      return;
   cd = d;
   kW = (d + 4) / 7;
   MqlDateTime s;
   TimeToStruct((datetime)(d * 86400), s);
   kM = (long)s.year * 12 + s.mon - 1;
  }

long CxKeyOf(const long tt, const int sec, const long kW, const long kM)
  {
   if(sec >= 2592000)
      return kM;
   if(sec >= 604800)
      return kW;
   return tt / sec;
  }

// ancora del VWAP: il giorno per i timeframe sotto D1, la settimana per D1, il mese per W1, l'anno per MN1
long CxAnchorOf(const long tt, const int sec, const long kW, const long kM)
  {
   if(sec < 86400)
      return tt / 86400;
   if(sec == 86400)
      return kW;
   if(sec < 2592000)
      return kM;
   return kM / 12;
  }

datetime CxStartOf(const long key, const int sec)
  {
   if(sec >= 2592000)
     {
      MqlDateTime s;
      ZeroMemory(s);
      s.year = (int)(key / 12);
      s.mon = (int)(key % 12) + 1;
      s.day = 1;
      return StructToTime(s);
     }
   if(sec >= 604800)
      return (datetime)((key * 7 - 4) * 86400);
   return (datetime)(key * sec);
  }

void CxVwapAt(CCx &q, const int x, const double sw, const double sp, const double sp2, const double ref, const int nAn)
  {
   if(nAn >= 15 && sw > 0)
     {
      double m = sp / sw, var = sp2 / sw - m * m;
      q.vw[x] = ref + m;
      q.vs[x] = var > 0 ? MathSqrt(var) : 0.0;
     }
   else
     {
      q.vw[x] = Nan();
      q.vs[x] = Nan();
     }
  }

// secondi della finestra del rollover (attorno a ogni mezzanotte New York + 7) dentro [a7, a7 + sec)
long CxRollOverlap(const long a7, const int sec)
  {
   long b7 = a7 + sec, tot = 0;
   long pre = (long)RollPre() * 60, post = (long)RollPost() * 60;
   for(long k = a7 / 86400; k <= b7 / 86400 + 1; k++)
     {
      long lo = MathMax(a7, k * 86400 - pre), hi = MathMin(b7, k * 86400 + post);
      if(hi > lo)
         tot += hi - lo;
     }
   return tot;
  }

// candele del timeframe sec dalle barre b[i0..]; false se ne servono piu' di due
bool CxBuild(CSeries &b, const int i0, const int baseSec, const int sec, CCx &q)
  {
   q.Free();
   q.sec = sec;
   bool drop = InpRollSkip && sec > 3600;    // barre nella finestra del rollover escluse dalle candele piu' lunghe di H1
   bool flag = InpRollSkip && sec <= 3600;   // candele che toccano la finestra: invalide
   int n = 0;
   long cur = LONG_MIN, cd = -1, kW = 0, kM = 0, rD = -1, rOff = 0;
   for(int i = i0; i < b.n; i++)
     {
      bool inRoll = RollInC(b.t[i], rD, rOff);
      if(drop && inRoll)
         continue;
      CxDay((long)b.t[i], cd, kW, kM);
      long k = CxKeyOf((long)b.t[i], sec, kW, kM);
      if(k != cur)
        {
         n++;
         cur = k;
        }
     }
   if(n < 3)
      return false;
   q.Alloc(n);
   cur = LONG_MIN;
   cd = -1;
   rD = -1;
   long an = LONG_MIN;
   double ref = b.c[i0], sw = 0, sp = 0, sp2 = 0;
   int nAn = 0, x = -1;
   datetime firstBar = 0, lastBar = 0;
   for(int i = i0; i < b.n; i++)
     {
      long tt = (long)b.t[i];
      bool inRoll = RollInC(b.t[i], rD, rOff);
      if(drop && inRoll)
         continue;
      CxDay(tt, cd, kW, kM);
      long k = CxKeyOf(tt, sec, kW, kM);
      if(k != cur)
        {
         if(x >= 0)
            CxVwapAt(q, x, sw, sp, sp2, ref, nAn);
         long a = CxAnchorOf(tt, sec, kW, kM);
         if(a != an)
           {
            an = a;
            sw = 0;
            sp = 0;
            sp2 = 0;
            nAn = 0;
           }
         x++;
         cur = k;
         q.key[x] = k;
         q.t[x] = CxStartOf(k, sec);
         q.o[x] = b.o[i];
         q.h[x] = b.h[i];
         q.l[x] = b.l[i];
         q.c[x] = b.c[i];
         q.v[x] = b.v[i];
         q.nb[x] = 1;
         q.dy[x] = (int)(tt / 86400);
         q.chn[x] = 0;
         q.fa[x] = 1.0f;
         q.ok[x] = 1;
         if(flag)
           {
            long a7 = (long)q.t[x] + rOff;
            if(RollHit7(a7, a7 + sec - 1))
               q.ok[x] = 0;
           }
         if(x == 0)
            firstBar = b.t[i];
        }
      else
        {
         if(b.h[i] > q.h[x])
            q.h[x] = b.h[i];
         if(b.l[i] < q.l[x])
            q.l[x] = b.l[i];
         q.c[x] = b.c[i];
         q.v[x] += b.v[i];
         q.nb[x]++;
        }
      lastBar = b.t[i];
      if(!inRoll)
        {
         double w = b.hasVol ? b.v[i] : 1.0;
         if(w > 0)
           {
            double tp = (b.h[i] + b.l[i] + b.c[i]) / 3.0 - ref;
            sw += w;
            sp += w * tp;
            sp2 += w * tp * tp;
            nAn++;
           }
        }
     }
   if(x >= 0)
      CxVwapAt(q, x, sw, sp, sp2, ref, nAn);
   q.n = x + 1;
   //--- completezza: meta' del numero tipico di barre base per candela; prima e ultima candela devono essere coperte
   int nbMin = 1;
   if(sec > baseSec)
     {
      int step = MathMax(1, q.n / 20000);
      double smp[];
      int m = 0;
      ArrayResize(smp, q.n / step + 2);
      for(int i = 0; i < q.n; i += step)
        {
         smp[m] = (double)q.nb[i];
         m++;
        }
      double med = MedianOf(smp, m);
      nbMin = (int)MathMax(1.0, MathFloor(0.5 * med));
     }
   for(int i = 0; i < q.n; i++)
     {
      if(q.nb[i] < nbMin || !(q.l[i] > 0) || q.h[i] < q.l[i] || !(q.o[i] > 0) || !(q.c[i] > 0))
         q.ok[i] = 0;
     }
   if(sec < 604800)
     {
      if((long)firstBar - (long)q.t[0] > 2 * (long)baseSec)
         q.ok[0] = 0;
      if((long)q.t[q.n - 1] + sec - (long)lastBar > 3 * (long)baseSec)
         q.ok[q.n - 1] = 0;
     }
   else
     {
      long end = (long)CxStartOf(q.key[q.n - 1] + 1, sec);
      if(end - (long)lastBar > (sec >= 2592000 ? 4 : 2) * 86400)
         q.ok[q.n - 1] = 0;
     }
   //--- H2-H12: la finestra del rollover tolta dalla candela ne accorcia la durata. Oltre il 25% la candela e' invalida; altrimenti il range si riporta
   //--- alla durata nominale (radice del rapporto), altrimenti i confronti del range tra fasce orarie sarebbero falsati
   if(drop && sec <= 43200)
      for(int i = 0; i < q.n; i++)
        {
         long ov = CxRollOverlap((long)DataToNY7(q.t[i]), sec);
         if(ov > sec / 4)
            q.ok[i] = 0;
         else
            if(ov > 0)
               q.fa[i] = (float)MathSqrt((double)sec / (double)(sec - ov));
        }
   //--- adiacenza: catena di candele valide consecutive che finisce in ogni candela
   for(int i = 0; i < q.n; i++)
     {
      if(q.ok[i] == 0)
        {
         q.chn[i] = 0;
         continue;
        }
      bool adj = false;
      if(i > 0 && q.ok[i - 1] != 0)
        {
         long d = (long)q.t[i] - (long)q.t[i - 1];
         if(sec < 86400)
            adj = d == sec;
         else
            if(sec == 86400)
              {
               int w = DowMon(q.t[i - 1]);
               adj = d == 86400 || (w == 4 && d <= 3 * 86400) || (w == 5 && d <= 2 * 86400);
              }
            else
               adj = q.key[i] - q.key[i - 1] == 1;
        }
      q.chn[i] = adj ? q.chn[i - 1] + 1 : 1;
     }
   return true;
  }

// massimo e minimo del periodo precedente a quello che contiene 'key' (puntatore avanzante ptr)
bool CxPrevLvl(CCx &L, int &ptr, const long key, double &hi, double &lo)
  {
   if(L.n < 2)
      return false;
   while(ptr + 1 < L.n && L.key[ptr + 1] <= key)
      ptr++;
   int p = ptr;
   if(L.key[p] >= key)
      p--;
   if(p < 0 || L.ok[p] == 0)
      return false;
   hi = L.h[p];
   lo = L.l[p];
   return true;
  }

//+------------------------------------------------------------------+
//| Indicatori e stati di ogni candela                                |
//| ATR14 (media semplice del true range), ADX(14) di Wilder, volume  |
//| all'ora (RVOL su 20 occorrenze dello stesso orario), z-score del  |
//| prezzo su 20 candele, VWAP ancorato e sue bande, posizione nelle  |
//| ultime 20 candele, livelli del giorno, settimana e mese prima.    |
//| Ogni stato usa solo dati fino alla chiusura della candela.        |
//+------------------------------------------------------------------+
void CxFeatures(CCx &q, const bool hasVol)
  {
   int n = q.n, sec = q.sec;
   q.AllocFe(n);
   double trR[100], hR[20], lR[20], rR[20], cR[20];
   ArrayInitialize(trR, 0.0);
   ArrayInitialize(hR, 0.0);
   ArrayInitialize(lR, 0.0);
   ArrayInitialize(rR, 0.0);
   ArrayInitialize(cR, 0.0);
   int nTr = 0, pTr = 0, cw = 0, pw = 0;
   double s14 = 0, s100 = 0;
   double pcl = 0, ph = 0, pl = 0;
   int nS = 0, nD = 0;
   double sTR = 0, sP = 0, sM = 0, aSum = 0, adxv = 0;
   int ns = sec >= 86400 ? 1 : 86400 / sec;
   double rvBuf[], rvSum[];
   int rvCnt[], rvPos[];
   ArrayResize(rvBuf, ns * 20);
   ArrayResize(rvSum, ns);
   ArrayResize(rvCnt, ns);
   ArrayResize(rvPos, ns);
   ArrayInitialize(rvBuf, 0.0);
   ArrayInitialize(rvSum, 0.0);
   ArrayInitialize(rvCnt, 0);
   ArrayInitialize(rvPos, 0);
   long cd = -1, kW = 0, kM = 0;
   int pD = 0, pW = 0, pM = 0, pH = 0, p4 = 0;
   for(int i = 0; i < n; i++)
     {
      if(q.ok[i] == 0)
         continue;
      double fac = q.fa[i];
      double o = q.o[i], h = q.h[i], l = q.l[i], c = q.c[i], rg = (h - l) * fac;
      bool adj = q.chn[i] >= 2;
      double tr = (adj ? MathMax(h, pcl) - MathMin(l, pcl) : h - l) * fac;
      //--- ATR prima di questa candela, poi aggiornamento
      double apv = nTr >= 14 ? s14 / 14.0 : Nan();
      if(nTr >= 14)
         s14 -= trR[(pTr - 14 + 100) % 100];
      if(nTr >= 100)
         s100 -= trR[pTr];
      s14 += tr;
      s100 += tr;
      trR[pTr] = tr;
      pTr = (pTr + 1) % 100;
      nTr++;
      double acv = nTr >= 14 ? s14 / 14.0 : Nan();
      if(MathIsValidNumber(apv) && apv > 0)
         q.ap[i] = (float)apv;
      if(MathIsValidNumber(acv) && acv > 0)
         q.ac[i] = (float)acv;
      if(nTr >= 100 && s100 > 0 && MathIsValidNumber(acv))
         q.vr[i] = (float)(acv / (s100 / 100.0));
      //--- ADX
      double pdm = 0, mdm = 0;
      if(adj)
        {
         double up = h - ph, dn = pl - l;
         pdm = ((up > dn && up > 0) ? up : 0.0) * fac;
         mdm = ((dn > up && dn > 0) ? dn : 0.0) * fac;
        }
      nS++;
      if(nS <= 14)
        {
         sTR += tr;
         sP += pdm;
         sM += mdm;
        }
      else
        {
         sTR += tr - sTR / 14.0;
         sP += pdm - sP / 14.0;
         sM += mdm - sM / 14.0;
        }
      if(nS >= 14)
        {
         double dx = 0;
         if(sTR > 0)
           {
            double d1 = 100.0 * sP / sTR, d2 = 100.0 * sM / sTR;
            dx = (d1 + d2) > 0 ? 100.0 * MathAbs(d1 - d2) / (d1 + d2) : 0.0;
           }
         nD++;
         if(nD <= 14)
           {
            aSum += dx;
            if(nD == 14)
               adxv = aSum / 14.0;
           }
         else
            adxv = (adxv * 13.0 + dx) / 14.0;
         if(nD >= 14)
            q.adx[i] = (float)adxv;
        }
      //--- volume all'ora
      int sl = ns == 1 ? 0 : (int)(((long)q.t[i] % 86400) / sec);
      if(sl >= ns)
         sl = ns - 1;
      if(hasVol)
        {
         if(rvCnt[sl] >= 20 && rvSum[sl] > 0)
            q.rv[i] = (float)(q.v[i] / (rvSum[sl] / 20.0));
         int bp = sl * 20 + rvPos[sl];
         if(rvCnt[sl] >= 20)
            rvSum[sl] -= rvBuf[bp];
         else
            rvCnt[sl]++;
         rvBuf[bp] = q.v[i];
         rvSum[sl] += q.v[i];
         rvPos[sl] = (rvPos[sl] + 1) % 20;
        }
      //--- finestre di 20 candele: massimi e minimi precedenti
      int f = 0;
      double pos = Nan();
      if(cw >= 20)
        {
         double hh = -1e300, ll = 1e300, h9 = -1e300, l9 = 1e300, r3 = 1e300, r6 = 1e300;
         for(int j = 1; j <= 20; j++)
           {
            int k = (pw - j + 20) % 20;
            hh = MathMax(hh, hR[k]);
            ll = MathMin(ll, lR[k]);
            if(j <= 9)
              {
               h9 = MathMax(h9, hR[k]);
               l9 = MathMin(l9, lR[k]);
              }
            if(j <= 6)
              {
               r6 = MathMin(r6, rR[k]);
               if(j <= 3)
                  r3 = MathMin(r3, rR[k]);
              }
           }
         if(c > hh)
            f |= 1;
         if(c < ll)
            f |= 2;
         if(l <= l9)
            f |= 4;
         if(h >= h9)
            f |= 8;
         if(rg < r3)
            f |= 16;
         if(rg < r6)
            f |= 32;
         double h2 = MathMax(hh, h), l2 = MathMin(ll, l);
         pos = h2 > l2 ? (c - l2) / (h2 - l2) : 0.5;
        }
      q.fl[i] = (uchar)f;
      hR[pw] = h;
      lR[pw] = l;
      rR[pw] = rg;
      cR[pw] = c;
      pw = (pw + 1) % 20;
      if(cw < 20)
         cw++;
      double zsv = Nan();
      if(cw >= 20)
        {
         double mu = 0;
         for(int j = 0; j < 20; j++)
            mu += cR[j];
         mu /= 20.0;
         double vv = 0;
         for(int j = 0; j < 20; j++)
            vv += (cR[j] - mu) * (cR[j] - mu);
         vv /= 19.0;
         if(vv > 0)
            zsv = (c - mu) / MathSqrt(vv);
        }
      //--- forma, direzione, ampiezza
      q.shp[i] = (uchar)CxShape(o, h, l, c);
      int up = c > o ? 1 : (c < o ? 0 : ((adj && c >= pcl) ? 1 : 0));
      q.upd[i] = (uchar)up;
      double am = (MathIsValidNumber(apv) && apv > 0) ? rg / apv : Nan();
      if(MathIsValidNumber(am))
        {
         q.amp[i] = (float)am;
         q.sym[i] = (uchar)(up * 3 + (am < 0.7 ? 0 : (am < 1.3 ? 1 : 2)));
         q.szc[i] = (uchar)(am < 0.5 ? 0 : (am < 0.8 ? 1 : (am < 1.2 ? 2 : (am < 2.0 ? 3 : 4))));
        }
      double ax = q.adx[i];
      if(MathIsValidNumber(ax))
         q.adc[i] = (uchar)(ax < 20 ? 0 : (ax < 30 ? 1 : (ax < 40 ? 2 : 3)));
      double vz = Nan();
      if(MathIsValidNumber(q.vw[i]) && q.vs[i] > 0)
         vz = (c - q.vw[i]) / q.vs[i];
      if(MathIsValidNumber(vz))
         q.vwc[i] = (uchar)(vz < -1.5 ? 0 : (vz < -0.5 ? 1 : (vz <= 0.5 ? 2 : (vz <= 1.5 ? 3 : 4))));
      if(MathIsValidNumber(zsv))
         q.zsc[i] = (uchar)(zsv < -2 ? 0 : (zsv < -1 ? 1 : (zsv <= 1 ? 2 : (zsv <= 2 ? 3 : 4))));
      double rvv = q.rv[i];
      if(MathIsValidNumber(rvv))
         q.rvc[i] = (uchar)(rvv < 0.7 ? 0 : (rvv < 1.3 ? 1 : (rvv < 2.0 ? 2 : 3)));
      double vrv = q.vr[i];
      if(MathIsValidNumber(vrv))
         q.voc[i] = (uchar)(vrv < 0.8 ? 0 : (vrv <= 1.2 ? 1 : 2));
      if(MathIsValidNumber(pos))
         q.dnc[i] = (uchar)(pos <= 0.10 ? 0 : (pos <= 0.35 ? 1 : (pos <= 0.65 ? 2 : (pos <= 0.90 ? 3 : 4))));
      //--- periodo precedente: giorno, settimana, mese
      long tt = (long)q.t[i];
      CxDay(tt, cd, kW, kM);
      double lh = 0, ll2 = 0;
      if(sec < 86400 && CxPrevLvl(g_cxLvD, pD, tt / 86400, lh, ll2))
         q.pdc[i] = (uchar)(c < ll2 ? 0 : (c > lh ? 2 : 1));
      if(sec < 604800 && CxPrevLvl(g_cxLvW, pW, kW, lh, ll2))
         q.pwc[i] = (uchar)(c < ll2 ? 0 : (c > lh ? 2 : 1));
      if(sec < 2592000 && CxPrevLvl(g_cxLvM, pM, kM, lh, ll2))
         q.pmc[i] = (uchar)(c < ll2 ? 0 : (c > lh ? 2 : 1));
      if(sec < 3600 && CxPrevLvl(g_cxLvH, pH, tt / 3600, lh, ll2))
         q.phc[i] = (uchar)(c < ll2 ? 0 : (c > lh ? 2 : 1));
      if(sec < 14400 && CxPrevLvl(g_cxLvQ, p4, tt / 14400, lh, ll2))
         q.p4c[i] = (uchar)(c < ll2 ? 0 : (c > lh ? 2 : 1));
      pcl = c;
      ph = h;
      pl = l;
     }
  }

//+------------------------------------------------------------------+
//| Pattern con nome (22): maschera di bit sulla candela i            |
//| Le soglie sono in ATR14 prima della candela; le finestre di 10 e  |
//| 20 candele e gli NR4/NR7 arrivano da CxFeatures (bit di fl[]).    |
//+------------------------------------------------------------------+
int CxNamed(CCx &q, const int i)
  {
   int m = 0;
   double a = q.ap[i];
   if(!MathIsValidNumber(a) || !(a > 0))
      return 0;
   int ch = q.chn[i];
   double o0 = q.o[i], h0 = q.h[i], l0 = q.l[i], c0 = q.c[i];
   bool up0 = c0 > o0, dn0 = c0 < o0;
   double b0 = MathAbs(c0 - o0), r0 = h0 - l0;
   int f = q.fl[i], sh = q.shp[i];
   if(ch >= 2)
     {
      double o1 = q.o[i - 1], h1 = q.h[i - 1], l1 = q.l[i - 1], c1 = q.c[i - 1];
      bool up1 = c1 > o1, dn1 = c1 < o1;
      double b1 = MathAbs(c1 - o1), r1 = h1 - l1;
      double a1 = q.ap[i - 1];
      if(!MathIsValidNumber(a1) || !(a1 > 0))
         a1 = a;
      if(dn1 && up0 && o0 <= c1 && c0 >= o1 && b0 > b1 && b1 > 0)
         m |= 1 << 0;
      if(up1 && dn0 && o0 >= c1 && c0 <= o1 && b0 > b1 && b1 > 0)
         m |= 1 << 1;
      if(dn1 && b1 >= 0.5 * a && up0 && o0 > c1 && c0 < o1 && b0 < b1)
         m |= 1 << 2;
      if(up1 && b1 >= 0.5 * a && dn0 && o0 < c1 && c0 > o1 && b0 < b1)
         m |= 1 << 3;
      if(dn1 && up0 && MathAbs(l0 - l1) <= 0.05 * a)
         m |= 1 << 4;
      if(up1 && dn0 && MathAbs(h0 - h1) <= 0.05 * a)
         m |= 1 << 5;
      if(h0 <= h1 && l0 >= l1 && r1 >= 1.5 * a1)
         m |= 1 << 16;
      if(h0 > h1 && l0 < l1)
        {
         if(c0 > h1)
            m |= 1 << 20;
         else
            if(c0 < l1)
               m |= 1 << 21;
        }
      if(ch >= 3)
        {
         double o2 = q.o[i - 2], h2 = q.h[i - 2], l2 = q.l[i - 2], c2 = q.c[i - 2];
         bool up2 = c2 > o2, dn2 = c2 < o2;
         double b2 = MathAbs(c2 - o2), r2 = h2 - l2;
         if(dn2 && b2 >= 0.5 * a && b1 <= 0.3 * b2 && MathMax(o1, c1) <= c2 + 0.1 * a && up0 && c0 > (o2 + c2) / 2.0)
            m |= 1 << 6;
         if(up2 && b2 >= 0.5 * a && b1 <= 0.3 * b2 && MathMin(o1, c1) >= c2 - 0.1 * a && dn0 && c0 < (o2 + c2) / 2.0)
            m |= 1 << 7;
         if(up2 && up1 && up0 && b2 >= 0.4 * a && b1 >= 0.4 * a && b0 >= 0.4 * a && c1 > c2 && c0 > c1 && o1 > o2 && o1 <= c2 && o0 > o1 && o0 <= c1)
            m |= 1 << 8;
         if(dn2 && dn1 && dn0 && b2 >= 0.4 * a && b1 >= 0.4 * a && b0 >= 0.4 * a && c1 < c2 && c0 < c1 && o1 < o2 && o1 >= c2 && o0 < o1 && o0 >= c1)
            m |= 1 << 9;
         if(h0 <= h1 && l0 >= l1 && h1 <= h2 && l1 >= l2)
            m |= 1 << 17;
         if(up2 && up1 && up0 && r0 > r1 && r1 > r2)
            m |= 1 << 18;
         if(dn2 && dn1 && dn0 && r0 > r1 && r1 > r2)
            m |= 1 << 19;
        }
     }
   if(sh == 4 && (f & 4) != 0)
      m |= 1 << 10;
   if(sh == 5 && (f & 8) != 0)
      m |= 1 << 11;
   if((f & 16) != 0)
      m |= 1 << 12;
   if((f & 32) != 0)
      m |= 1 << 13;
   if((f & 1) != 0)
      m |= 1 << 14;
   if((f & 2) != 0)
      m |= 1 << 15;
   return m;
  }

// cluster: settimana (da domenica) per i timeframe sotto D1; blocchi di 5 candele per D1, 4 per W1, 3 per MN1
int CxCluster(CCx &q, const int i)
  {
   if(q.sec < 86400)
      return (q.dy[i] + 4) / 7;
   return i / (q.sec == 86400 ? 5 : (q.sec < 2592000 ? 4 : 3));
  }

double CxClip(const double x, const double lo, const double hi) { return x < lo ? lo : (x > hi ? hi : x); }

// soglia dell'impulso: percentile InpImpulsePct dell'ampiezza (range diviso ATR14 prima della candela), almeno 2 ATR
double CxThreshold(CCx &q)
  {
   double hist[500];
   ArrayInitialize(hist, 0.0);
   double tot = 0;
   for(int i = 0; i < q.n; i++)
     {
      if(q.ok[i] == 0 || !MathIsValidNumber(q.amp[i]))
         continue;
      int b = (int)MathFloor(q.amp[i] / 0.05);
      if(b < 0)
         b = 0;
      if(b > 499)
         b = 499;
      hist[b] += 1.0;
      tot += 1.0;
     }
   if(tot < 100)
      return Nan();
   double pc = MathMax(90.0, MathMin(99.99, InpImpulsePct));
   double target = tot * pc / 100.0, cum = 0;
   for(int b = 0; b < 500; b++)
     {
      cum += hist[b];
      if(cum >= target)
         return MathMax(2.0, (b + 1) * 0.05);
     }
   return 25.0;
  }

// stati prima della candela i (tutti letti fino alla chiusura della i-1); st[g] = -1 se non definito. Serve catena >= 4.
void CxPreState(CCx &q, const int i, int &st[])
  {
   for(int g = 0; g < CX_NSD; g++)
      st[g] = -1;
   int j = i - 1;
   if(q.rvc[j] != CX_NA)
      st[0] = q.rvc[j];
   if(q.adc[j] != CX_NA)
      st[1] = q.adc[j];
   if(q.vwc[j] != CX_NA)
      st[2] = q.vwc[j];
   if(q.zsc[j] != CX_NA)
      st[3] = q.zsc[j];
   double a = q.ac[j];
   if(MathIsValidNumber(a) && a > 0)
     {
      double hh = MathMax(q.h[i - 1], MathMax(q.h[i - 2], q.h[i - 3])), ll = MathMin(q.l[i - 1], MathMin(q.l[i - 2], q.l[i - 3]));
      double r3 = (hh - ll) / a;
      st[4] = r3 < 1.0 ? 0 : (r3 < 2.0 ? 1 : 2);
      double net = (q.c[i - 1] - q.o[i - 3]) / a;
      st[5] = net < -1.0 ? 0 : (net > 1.0 ? 2 : 1);
     }
   if(q.shp[j] != CX_NA)
      st[6] = CxShapeFam(q.shp[j]);
  }

//+------------------------------------------------------------------+
//| Passata sulle candele: classi (con esito), categorie di tempo,    |
//| composizione e maggiori movimenti                                 |
//+------------------------------------------------------------------+
void CxPass(CCx &q, const int ti, const double thr, const datetime tMid, CClu &cl, CClu &ck)
  {
   int n = q.n, sec = q.sec;
   cl.Init(CX_NCL, CX_NM);
   ck.Init(CX_NCU, CX_NMK);
   double v[CX_NM], kv[CX_NMK], smpR[], smpB[];
   int cls[64], ku[9];
   int stride = MathMax(1, n / 40000);
   ArrayResize(smpR, n / stride + 2);
   ArrayResize(smpB, n / stride + 2);
   int nSm = 0;
   long cd = -1, kW = 0, kM = 0, dD = -1;
   int dom = 1;
   int y0 = -1, curCl = -1, run = 0, nObs = 0, nImp = 0, nBull = 0;
   double tpR[5], tpP[5];
   datetime tpT[5];
   int tpD[5];
   for(int k = 0; k < 5; k++)
     {
      tpR[k] = -1;
      tpP[k] = -1;
      tpT[k] = 0;
      tpD[k] = 0;
     }
   for(int i = 0; i < n; i++)
     {
      if(q.ok[i] == 0)
        {
         run = 0;
         continue;
        }
      bool up = q.upd[i] == 1;
      if(q.chn[i] >= 2 && (q.upd[i - 1] == 1) == up)
         run++;
      else
         run = 1;
      double am = q.amp[i], apv = q.ap[i];
      if(!MathIsValidNumber(am) || !MathIsValidNumber(apv) || !(apv > 0))
         continue;
      double o = q.o[i], h = q.h[i], l = q.l[i], c = q.c[i], rg = h - l;
      int hf = q.t[i] < tMid ? 0 : 1;
      int cid = CxCluster(q, i);
      if(cid != curCl)
        {
         cl.Flush();
         ck.Flush();
         curCl = cid;
        }
      bool imp = am >= thr, lg = am >= 1.5;
      long tt = (long)q.t[i];
      CxDay(tt, cd, kW, kM);
      if(tt / 86400 != dD)
        {
         dD = tt / 86400;
         MqlDateTime sd;
         TimeToStruct((datetime)(dD * 86400), sd);
         dom = sd.day;
        }
      int mon = (int)(kM % 12), yr = (int)(kM / 12);
      if(y0 < 0)
        {
         y0 = yr;
         g_cxKY0[ti] = yr;
        }
      //--- categorie di tempo
      int nk = 0;
      if(sec < 86400)
        {
         ku[nk] = CX_K_TOD + (int)((tt % 86400) / MathMax(sec, 3600));
         nk++;
        }
      if(sec < 3600)
        {
         ku[nk] = CX_K_MOH + (int)((tt % 3600) / sec);
         nk++;
        }
      if(sec <= 86400)
        {
         ku[nk] = CX_K_DOW + DowMon(q.t[i]);
         nk++;
        }
      if(sec <= 604800)
        {
         ku[nk] = CX_K_WOM + MathMin(4, (dom - 1) / 7);
         nk++;
        }
      ku[nk] = CX_K_MON + mon;
      nk++;
      ku[nk] = CX_K_QTR + mon / 3;
      nk++;
      ku[nk] = CX_K_YR + MathMax(0, MathMin(39, yr - y0));
      nk++;
      ku[nk] = CX_K_ALL;
      nk++;
      kv[0] = c > o ? 1.0 : (c < o ? 0.0 : 0.5);
      kv[1] = CxClip((c - o) / apv, -8.0, 8.0);
      kv[2] = MathMin(rg * q.fa[i], 30.0 * apv) / c * 10000.0;
      kv[3] = lg ? 1.0 : 0.0;
      kv[4] = imp ? 1.0 : 0.0;
      for(int k = 0; k < nk; k++)
         ck.Add(ku[k], kv, hf);
      //--- riepilogo del timeframe
      nObs++;
      if(c > o)
         nBull++;
      if(nObs % stride == 0 && nSm < ArraySize(smpR))
        {
         smpR[nSm] = rg / c * 100.0;
         smpB[nSm] = rg > 0 ? MathAbs(c - o) / rg : 0.0;
         nSm++;
        }
      int cg = imp ? (up ? 1 : 2) : 0;
      for(int gi = 0; gi < 2; gi++)
        {
         if(gi == 1 && !imp)
            break;
         int g = gi == 0 ? 0 : cg;
         int b = (ti * 3 + g) * 8;
         g_cxComp[b + CxShapeFam(q.shp[i])] += 1.0;
         if(c > o)
            g_cxComp[b + 6] += 1.0;
         g_cxComp[b + 7] += am;
        }
      if(imp)
         nImp++;
      //--- i cinque movimenti maggiori (range in % del prezzo)
      double pr = rg / c * 100.0;
      if(pr > tpP[4])
        {
         int k = 4;
         while(k > 0 && pr > tpP[k - 1])
           {
            tpP[k] = tpP[k - 1];
            tpR[k] = tpR[k - 1];
            tpT[k] = tpT[k - 1];
            tpD[k] = tpD[k - 1];
            k--;
           }
         tpP[k] = pr;
         tpR[k] = am;
         tpT[k] = q.t[i];
         tpD[k] = up ? 1 : -1;
        }
      //--- classi: solo con l'esito delle tre candele successive e ATR valido
      double ac = q.ac[i];
      if(i + 3 >= n || q.chn[i + 3] < 4 || !MathIsValidNumber(ac) || !(ac > 0))
         continue;
      int nc = 0;
      cls[nc] = CX_C_ALL;
      nc++;
      cls[nc] = CX_C_SH + q.shp[i] * 2 + (up ? 1 : 0);
      nc++;
      if(q.chn[i] >= 2 && q.sym[i] != CX_NA && q.sym[i - 1] != CX_NA)
        {
         cls[nc] = CX_C_S2 + q.sym[i - 1] * 6 + q.sym[i];
         nc++;
         if(q.chn[i] >= 3 && q.sym[i - 2] != CX_NA)
           {
            cls[nc] = CX_C_S3 + q.sym[i - 2] * 36 + q.sym[i - 1] * 6 + q.sym[i];
            nc++;
           }
        }
      int nm = CxNamed(q, i);
      if(nm != 0)
         for(int k = 0; k < CX_NNP; k++)
            if((nm & (1 << k)) != 0)
              {
               cls[nc] = CX_C_NP + k;
               nc++;
              }
      cls[nc] = CX_C_ST + (up ? 0 : 6) + MathMin(run, 6) - 1;
      nc++;
      if(q.chn[i] >= 2)
        {
         double ph = q.h[i - 1], pl = q.l[i - 1];
         int sv[10];
         sv[0] = (h <= ph && l >= pl) ? 1 : 0;
         sv[1] = (h > ph && l < pl) ? 1 : 0;
         sv[2] = (h > ph && l >= pl) ? 1 : 0;
         sv[3] = (l < pl && h <= ph) ? 1 : 0;
         sv[4] = (h > ph && c < ph) ? 1 : 0;
         sv[5] = (l < pl && c > pl) ? 1 : 0;
         sv[6] = c > ph ? 1 : 0;
         sv[7] = c < pl ? 1 : 0;
         sv[8] = o > ph ? 1 : 0;
         sv[9] = o < pl ? 1 : 0;
         for(int k = 0; k < CX_NSV; k++)
            if(sv[k] == 1)
              {
               cls[nc] = CX_C_SV + k;
               nc++;
              }
        }
      if(q.adc[i] != CX_NA)
        {
         cls[nc] = CX_C_AD + q.adc[i];
         nc++;
        }
      if(q.vwc[i] != CX_NA)
        {
         cls[nc] = CX_C_VW + q.vwc[i];
         nc++;
        }
      if(q.zsc[i] != CX_NA)
        {
         cls[nc] = CX_C_ZS + q.zsc[i];
         nc++;
        }
      if(q.rvc[i] != CX_NA)
        {
         cls[nc] = CX_C_RV + q.rvc[i];
         nc++;
        }
      if(q.voc[i] != CX_NA)
        {
         cls[nc] = CX_C_VO + q.voc[i];
         nc++;
        }
      if(q.szc[i] != CX_NA)
        {
         cls[nc] = CX_C_SZ + q.szc[i];
         nc++;
        }
      if(q.dnc[i] != CX_NA)
        {
         cls[nc] = CX_C_DN + q.dnc[i];
         nc++;
        }
      if(q.pdc[i] != CX_NA)
        {
         cls[nc] = CX_C_PD + q.pdc[i];
         nc++;
        }
      if(q.pwc[i] != CX_NA)
        {
         cls[nc] = CX_C_PW + q.pwc[i];
         nc++;
        }
      if(q.pmc[i] != CX_NA)
        {
         cls[nc] = CX_C_PM + q.pmc[i];
         nc++;
        }
      if(q.phc[i] != CX_NA)
        {
         cls[nc] = CX_C_PH + q.phc[i];
         nc++;
        }
      if(q.p4c[i] != CX_NA)
        {
         cls[nc] = CX_C_P4 + q.p4c[i];
         nc++;
        }
      if(imp)
        {
         cls[nc] = up ? CX_C_IU : CX_C_ID;
         nc++;
        }
      double c1 = q.c[i + 1], c3 = q.c[i + 3];
      v[0] = c1 > c ? 1.0 : (c1 == c ? 0.5 : 0.0);
      v[1] = CxClip((c1 - c) / ac, -8.0, 8.0);
      v[2] = CxClip((q.h[i + 1] - q.l[i + 1]) * q.fa[i + 1] / ac, 0.0, 12.0);
      v[3] = q.h[i + 1] > h ? 1.0 : 0.0;
      v[4] = q.l[i + 1] < l ? 1.0 : 0.0;
      v[5] = CxClip((c3 - c) / ac, -8.0, 8.0);
      v[6] = c3 > c ? 1.0 : (c3 == c ? 0.5 : 0.0);
      double mx = MathMax(q.h[i + 1], MathMax(q.h[i + 2], q.h[i + 3])), mn = MathMin(q.l[i + 1], MathMin(q.l[i + 2], q.l[i + 3]));
      v[7] = CxClip((mx - c) / ac, 0.0, 12.0);
      v[8] = CxClip((c - mn) / ac, 0.0, 12.0);
      double race = 0;
      for(int j = i + 1; j <= i + 12 && j < n; j++)
        {
         if(q.chn[j] < j - i + 1)
            break;
         bool hu = q.h[j] - c >= ac, hd = c - q.l[j] >= ac;
         if(hu && hd)
            break;
         if(hu)
           {
            race = 1.0;
            break;
           }
         if(hd)
           {
            race = -1.0;
            break;
           }
        }
      v[9] = race;
      v[10] = CxClip(am, 0.0, 12.0);
      for(int k = 0; k < nc; k++)
         cl.Add(cls[k], v, hf);
     }
   cl.Flush();
   ck.Flush();
   //--- riepilogo
   g_cxN[ti] = nObs;
   g_cxNimp[ti] = nImp;
   g_cxImpP[ti] = nObs > 0 ? (double)nImp / nObs : Nan();
   g_cxBull[ti] = nObs > 0 ? (double)nBull / nObs : Nan();
   g_cxMedR[ti] = nSm > 0 ? MedianOf(smpR, nSm) : Nan();
   g_cxBody[ti] = nSm > 0 ? MedianOf(smpB, nSm) : Nan();
   for(int k = 0; k < 5; k++)
     {
      g_cxTopT[ti * 5 + k] = tpT[k];
      g_cxTopR[ti * 5 + k] = tpR[k];
      g_cxTopP[ti * 5 + k] = tpP[k];
      g_cxTopD[ti * 5 + k] = tpD[k];
     }
  }

// strato di controllo di un precursore: ora del giorno (D1: giorno della settimana) per il regime di volatilita' della candela prima
// (ATR14 / ATR100: sotto 0,8, normale, sopra 1,2, non definito)
int CxStratum(CCx &q, const int i, const long tt)
  {
   int slot = q.sec < 86400 ? (int)((tt % 86400) / 3600) : (q.sec == 86400 ? DowMon(q.t[i]) : 0);
   int v = q.voc[i - 1] == CX_NA ? 3 : q.voc[i - 1];
   return slot * 4 + v;
  }

//+------------------------------------------------------------------+
//| Cosa c'e' prima di un impulso: stati delle candele precedenti     |
//| contro le altre candele della stessa ora (non impulsi)            |
//+------------------------------------------------------------------+
void CxPre(CCx &q, const int ti, const double thr, const datetime tMid)
  {
   int n = q.n;
   double cnt[], tot[];
   ArrayResize(cnt, 24 * 4 * CX_NPS);
   ArrayResize(tot, 24 * 4 * CX_NSD);
   ArrayInitialize(cnt, 0.0);
   ArrayInitialize(tot, 0.0);
   int st[CX_NSD];
   //--- controllo: candele che non sono impulsi
   for(int i = 3; i < n; i++)
     {
      if(q.ok[i] == 0 || q.chn[i] < 4 || !MathIsValidNumber(q.amp[i]) || q.amp[i] >= thr)
         continue;
      CxPreState(q, i, st);
      long tt = (long)q.t[i];
      int slot = CxStratum(q, i, tt);
      for(int g = 0; g < CX_NSD; g++)
         if(st[g] >= 0)
           {
            cnt[slot * CX_NPS + CX_PSG[g] + st[g]] += 1.0;
            tot[slot * CX_NSD + g] += 1.0;
           }
     }
   //--- impulsi: per ogni stato il residuo x - p (x = 1 se lo stato c'era, p = quota tra le altre candele della stessa ora) come osservazione per cluster
   CClu pc;
   pc.Init(2 * CX_NPS, 1);
   double ex[], vm[], ng[], nimp[], ncl[], rv[1];
   ArrayResize(ex, 2 * CX_NPS);
   ArrayResize(vm, 2 * CX_NPS);
   ArrayResize(ng, 2 * CX_NPS);
   ArrayResize(nimp, 2);
   ArrayResize(ncl, 2);
   ArrayInitialize(ex, 0.0);
   ArrayInitialize(vm, 0.0);
   ArrayInitialize(ng, 0.0);
   ArrayInitialize(nimp, 0.0);
   ArrayInitialize(ncl, 0.0);
   double ob[];
   ArrayResize(ob, 2 * CX_NPS);
   ArrayInitialize(ob, 0.0);
   int curCl = -1, lastCl[2];
   lastCl[0] = -1;
   lastCl[1] = -1;
   for(int i = 3; i < n; i++)
     {
      if(q.ok[i] == 0 || q.chn[i] < 4 || !MathIsValidNumber(q.amp[i]) || q.amp[i] < thr)
         continue;
      int cid = CxCluster(q, i);
      if(cid != curCl)
        {
         if(curCl >= 0)
           {
            pc.Flush();
            for(int e = 1; e < cid - curCl && e <= CX_NLAG; e++)
               pc.Flush();
           }
         curCl = cid;
        }
      int d = q.upd[i] == 1 ? 0 : 1;
      if(lastCl[d] != cid)
        {
         lastCl[d] = cid;
         ncl[d] += 1.0;
        }
      nimp[d] += 1.0;
      int hf = q.t[i] < tMid ? 0 : 1;
      CxPreState(q, i, st);
      long tt = (long)q.t[i];
      int slot = CxStratum(q, i, tt);
      for(int g = 0; g < CX_NSD; g++)
        {
         if(st[g] < 0)
            continue;
         double T = tot[slot * CX_NSD + g];
         if(T < 30)
            continue;
         ng[d * CX_NSD + g] += 1.0;
         for(int s = 0; s < CX_PSN[g]; s++)
           {
            int idx = d * CX_NPS + CX_PSG[g] + s;
            double p = cnt[slot * CX_NPS + CX_PSG[g] + s] / T, x = (s == st[g]) ? 1.0 : 0.0;
            ob[idx] += x;
            ex[idx] += p;
            vm[idx] += p * (1.0 - p);
            rv[0] = x - p;
            pc.Add(idx, rv, hf);
           }
        }
     }
   pc.Flush();
   for(int d = 0; d < 2; d++)
     {
      g_cxNimpD[ti * 2 + d] = (int)nimp[d];
      for(int g = 0; g < CX_NSD; g++)
         for(int s = 0; s < CX_PSN[g]; s++)
           {
            int idx = d * CX_NPS + CX_PSG[g] + s, b = ((ti * 2 + d) * CX_NPS + CX_PSG[g] + s) * 4;
            g_cxP[b] = ob[idx];
            g_cxP[b + 1] = ex[idx];
            g_cxP[b + 2] = Nan();
            g_cxP[b + 3] = -1;
            double G = ncl[d], ngg = ng[d * CX_NSD + g];
            if(G < 10 || ex[idx] < 3 || ngg - ex[idx] < 3 || !(vm[idx] > 0))
               continue;
            // effetto di disegno: varianza di Wald dei residui (centrati sulla loro media) contro la binomiale; z sul modello nullo
            double vw = CxWald(pc, idx, 0), deff = MathIsValidNumber(vw) ? MathMax(1.0, vw / vm[idx]) : 1.0;
            double dz = ob[idx] - ex[idx];
            dz = dz > 0 ? MathMax(0.0, dz - 0.5) : MathMin(0.0, dz + 0.5);
            double z = dz / MathSqrt(deff * vm[idx] * G / (G - 1.0));
            g_cxP[b + 2] = z;
            double dh0 = pc.H[(idx * 2) * pc.hs + 1], dh1 = pc.H[(idx * 2 + 1) * pc.hs + 1];
            bool stab = BxStable(z, dh0, dh1);
            g_cxP[b + 3] = CxTestAdd(ti, 6, d * CX_NPS + CX_PSG[g] + s, z, stab);
           }
     }
  }

//+------------------------------------------------------------------+
//| Risultati: allocazione, estrazione, timeframe, test multipli      |
//+------------------------------------------------------------------+
string CX_KMN[CX_NMK] = {"% rialziste", "rendimento medio (ATR)", "range (punti base)", "% candele oltre 1,5 ATR", "% impulsi"};

void CxAlloc(void)
  {
   ArrayResize(g_cxC, CX_NTF * CX_NCL * CX_NF);
   ArrayResize(g_cxK, CX_NTF * CX_NCU * CX_NFK);
   ArrayResize(g_cxP, CX_NTF * 2 * CX_NPS * 4);
   ArrayResize(g_cxComp, CX_NTF * 3 * 8);
   ArrayResize(g_cxTopT, CX_NTF * 5);
   ArrayResize(g_cxTopR, CX_NTF * 5);
   ArrayResize(g_cxTopP, CX_NTF * 5);
   ArrayResize(g_cxTopD, CX_NTF * 5);
   ArrayResize(g_cxNimpD, CX_NTF * 2);
   double nn = Nan();
   ArrayInitialize(g_cxC, nn);
   ArrayInitialize(g_cxK, nn);
   ArrayInitialize(g_cxP, nn);
   ArrayInitialize(g_cxComp, 0.0);
   ArrayInitialize(g_cxTopT, 0);
   ArrayInitialize(g_cxTopR, -1.0);
   ArrayInitialize(g_cxTopP, -1.0);
   ArrayInitialize(g_cxTopD, 0);
   ArrayInitialize(g_cxNimpD, 0);
   for(int ti = 0; ti < CX_NTF; ti++)
     {
      g_cxN[ti] = 0;
      g_cxT0[ti] = 0;
      g_cxT1[ti] = 0;
      g_cxThr[ti] = nn;
      g_cxImpP[ti] = nn;
      g_cxMedR[ti] = nn;
      g_cxBull[ti] = nn;
      g_cxBody[ti] = nn;
      g_cxNimp[ti] = 0;
      g_cxNrob[ti] = 0;
      g_cxNtst[ti] = 0;
      g_cxKY0[ti] = 2000;
      for(int u = 0; u < CX_NCL; u++)
        {
         int b = (ti * CX_NCL + u) * CX_NF;
         g_cxC[b + 3] = -1;
         g_cxC[b + 6] = -1;
         g_cxC[b + 18] = -1;
        }
      for(int u = 0; u < CX_NCU; u++)
        {
         int b = (ti * CX_NCU + u) * CX_NFK;
         for(int m = 0; m < CX_NMK; m++)
            g_cxK[b + 11 + m] = -1;
        }
      for(int x = 0; x < 2 * CX_NPS; x++)
         g_cxP[(ti * 2 * CX_NPS + x) * 4 + 3] = -1;
     }
   g_cxNAll = 0;
   ArrayInitialize(g_cxNFam, 0);
   g_cxNT = 0;
   ArrayResize(g_cxTz, 0);
   ArrayResize(g_cxTtf, 0);
   ArrayResize(g_cxTk, 0);
   ArrayResize(g_cxTu, 0);
   ArrayResize(g_cxTst, 0);
   ArrayResize(g_cxTfd, 0);
   ArrayResize(g_cxTtx, 0);
  }

string CxMetricTxt(const int m, const double x)
  {
   if(m == 0 || m == 3 || m == 4)
      return FP(x, 1) + "%";
   if(m == 1)
      return F(x, 3);
   return F(x, 2);
  }

int CxIdx(const double x) { return MathIsValidNumber(x) ? (int)x : -1; }

// segno di robustezza: &dagger; = FDR 5% e stesso verso nelle due meta'; &sect; = solo FDR
string CxMk(const int id)
  {
   if(id < 0 || id >= g_cxNT)
      return "";
   if(g_cxTfd[id] && g_cxTst[id])
      return "&dagger;";
   if(g_cxTfd[id])
      return "&sect;";
   return "";
  }

void CxExtract(const int ti, CClu &cl, CClu &ck)
  {
   string tf = CX_NAME[ti];
   double nAll = cl.N(CX_C_ALL);
   int ms[3] = {0, 1, 5}, kd[3] = {0, 1, 8}, fz[3] = {2, 5, 17}, ft[3] = {3, 6, 18};
   int bA = (ti * CX_NCL + CX_C_ALL) * CX_NF;
   for(int u = 0; u < CX_NCL; u++)
     {
      double nn = cl.N(u);
      if(nn <= 0)
         continue;
      int b = (ti * CX_NCL + u) * CX_NF;
      g_cxC[b] = nn;
      g_cxC[b + 1] = cl.Mean(u, 0);
      g_cxC[b + 4] = cl.Mean(u, 1);
      g_cxC[b + 7] = cl.Mean(u, 2);
      g_cxC[b + 8] = cl.Mean(u, 3);
      g_cxC[b + 9] = cl.Mean(u, 4);
      g_cxC[b + 10] = cl.Mean(u, 5);
      g_cxC[b + 11] = cl.Mean(u, 6);
      g_cxC[b + 12] = cl.Mean(u, 7);
      g_cxC[b + 13] = cl.Mean(u, 8);
      g_cxC[b + 14] = cl.Mean(u, 9);
      g_cxC[b + 15] = cl.Mean(u, 10);
      g_cxC[b + 16] = nAll > 0 ? nn / nAll : Nan();
      if(u == CX_C_ALL)
         continue;
      for(int k = 0; k < 3; k++)
        {
         double z = CxScore(cl, u, CX_C_ALL, ms[k]);
         g_cxC[b + fz[k]] = z;
         bool st = CxStab(cl, u, CX_C_ALL, ms[k], z);
         int id = CxTestAdd(ti, kd[k], u, z, st);
         g_cxC[b + ft[k]] = id;
         if(id >= 0)
           {
            string what = "";
            if(k == 0)
               what = "la candela dopo sale nel " + FP(g_cxC[b + 1], 1) + "% dei casi contro " + FP(g_cxC[bA + 1], 1) + "% di tutte";
            else
               if(k == 1)
                  what = "rendimento della candela dopo " + F(g_cxC[b + 4], 3) + " ATR contro " + F(g_cxC[bA + 4], 3) + " di tutte";
               else
                  what = "rendimento delle 3 candele dopo " + F(g_cxC[b + 10], 3) + " ATR contro " + F(g_cxC[bA + 10], 3) + " di tutte";
            CxSetTxt(id, z, "Candele " + tf + ": dopo '" + CxLabel(u) + "' (" + I2S((long)nn) + " casi), " + what);
           }
        }
     }
   int bK = (ti * CX_NCU + CX_K_ALL) * CX_NFK;
   double nAllK = ck.N(CX_K_ALL);
   int kk[5] = {2, 3, 7, 4, 5};
   double spanY = ((double)g_cxT1[ti] - (double)g_cxT0[ti]) / (365.25 * 86400.0);
   for(int uu = 0; uu < CX_NCU; uu++)
     {
      int u = uu == 0 ? CX_K_ALL : uu - 1;   // prima 'tutte le candele': serve al testo degli altri
      double nn = ck.N(u);
      if(nn <= 0)
         continue;
      int b = (ti * CX_NCU + u) * CX_NFK;
      g_cxK[b] = nn;
      g_cxK[b + 16] = nAllK > 0 ? nn / nAllK : Nan();
      for(int m = 0; m < CX_NMK; m++)
         g_cxK[b + 1 + m] = ck.Mean(u, m);
      if(u == CX_K_ALL)
         continue;
      int dim = CxUnitDim(u);
      // anno per anno: descrizione, senza test (ogni anno e' un solo periodo). Mese e trimestre: test solo con almeno 3 anni di storico
      bool testable = dim != 6 && (dim < 4 || spanY >= 3.0);
      for(int m = 0; m < CX_NMK; m++)
        {
         double z = testable ? CxScore(ck, u, CX_K_ALL, m) : Nan();
         g_cxK[b + 6 + m] = z;
         bool st = CxStab(ck, u, CX_K_ALL, m, z);
         int id = CxTestAdd(ti, kk[m], u, z, st);
         g_cxK[b + 11 + m] = id;
         if(id >= 0)
            CxSetTxt(id, z, "Candele " + tf + ": " + CX_KDN[dim] + " " + CxKLabel(ti, u) + " (" + I2S((long)nn) + " candele), " + CX_KMN[m] + " " +
                     CxMetricTxt(m, g_cxK[b + 1 + m]) + " contro " + CxMetricTxt(m, g_cxK[bK + 1 + m]) + " di tutte");
        }
     }
   //--- testi del riepilogo per i precursori (registrati in CxPre)
   for(int d = 0; d < 2; d++)
      for(int s = 0; s < CX_NPS; s++)
        {
         int b = ((ti * 2 + d) * CX_NPS + s) * 4;
         int id = CxIdx(g_cxP[b + 3]);
         if(id >= 0)
            CxSetTxt(id, g_cxP[b + 2], "Candele " + tf + ": prima di un impulso " + (d == 0 ? "rialzista" : "ribassista") + " (" + I2S(g_cxNimpD[ti * 2 + d]) +
                     " casi), stato '" + CX_PSL[s] + "': " + F(g_cxP[b], 0) + " volte contro " + F(g_cxP[b + 1], 1) + " attese nelle stesse ore");
        }
  }

// esegue un timeframe; false se non ci sono abbastanza candele
bool CxRunTf(CSeries &b, const int i0, const int baseSec, const int ti)
  {
   CCx q;
   int sec = CX_SEC[ti];
   if(!CxBuild(b, i0, baseSec, sec, q))
      return false;
   CxFeatures(q, b.hasVol);
   int f = -1, l = -1;
   for(int i = 0; i < q.n; i++)
      if(q.ok[i] != 0 && MathIsValidNumber(q.amp[i]))
        {
         if(f < 0)
            f = i;
         l = i;
        }
   if(f < 0 || l - f < (sec >= 2592000 ? 30 : (sec >= 604800 ? 40 : 60)))
     {
      q.Free();
      return false;
     }
   datetime tMid = (datetime)((long)q.t[f] + ((long)q.t[l] - (long)q.t[f]) / 2);
   double thr = CxThreshold(q);
   if(!MathIsValidNumber(thr))
     {
      q.Free();
      return false;
     }
   g_cxThr[ti] = thr;
   g_cxT0[ti] = q.t[f];
   g_cxT1[ti] = q.t[l];
   CClu cl, ck;
   CxPass(q, ti, thr, tMid, cl, ck);
   CxPre(q, ti, thr, tMid);
   CxExtract(ti, cl, ck);
   q.Free();
   return true;
  }

// controllo dei test multipli (Benjamini-Hochberg 5%) dentro ogni famiglia di confronti
void CxFdr(void)
  {
   ArrayResize(g_cxTfd, g_cxNT);
   if(g_cxNT > 0)
      ArrayInitialize(g_cxTfd, false);
   for(int f = 0; f < CX_NFAM && g_cxNT > 0; f++)
     {
      int idx[];
      double zz[];
      int k = 0;
      ArrayResize(idx, g_cxNT);
      ArrayResize(zz, g_cxNT);
      for(int i = 0; i < g_cxNT; i++)
         if(CxFamily(g_cxTk[i], g_cxTu[i]) == f)
           {
            idx[k] = i;
            zz[k] = g_cxTz[i];
            k++;
           }
      if(k == 0)
         continue;
      bool fl[];
      EdBhFlags(zz, k, (double)g_cxNFam[f], 0.05, fl);
      for(int j = 0; j < k; j++)
         g_cxTfd[idx[j]] = fl[j];
     }
   for(int ti = 0; ti < CX_NTF; ti++)
      g_cxNrob[ti] = 0;
   for(int i = 0; i < g_cxNT; i++)
      if(g_cxTfd[i] && g_cxTst[i])
         g_cxNrob[g_cxTtf[i]]++;
  }

// unita' con il valore piu' alto (sg = 1) o piu' basso (sg = -1) della metrica m nella dimensione d (almeno minN candele); -1 se nessuna
int CxBestUnit(const int ti, const int d, const int m, const double minN, const int sg)
  {
   int u0 = CxDimBase(d), cnt = d == 0 ? 24 : (d == 1 ? 60 : (d == 2 ? 7 : (d == 3 ? 5 : (d == 4 ? 12 : (d == 5 ? 4 : 40)))));
   int best = -1;
   double bv = -1e300;
   for(int k = 0; k < cnt; k++)
     {
      int b = (ti * CX_NCU + u0 + k) * CX_NFK;
      double nn = g_cxK[b];
      double x = g_cxK[b + 1 + m] * sg;
      if(!MathIsValidNumber(nn) || nn < minN || !MathIsValidNumber(x))
         continue;
      if(x > bv)
        {
         bv = x;
         best = u0 + k;
        }
     }
   return best;
  }

//+------------------------------------------------------------------+
//| Resa: HTML per timeframe, testo, CSV                              |
//+------------------------------------------------------------------+
string CxTDl(const string s) { return "<td style='text-align:left;white-space:normal;min-width:220px'>" + s + "</td>"; }

string CxZc(const string val, const double z, const int id)
  {
   if(!MathIsValidNumber(z))
      return TD(val);
   return TDc(val + " <small>z " + ZS(z) + CxMk(id) + "</small>", PCol(z, 0, 5));
  }

string CxZt(const double z, const int id) { return MathIsValidNumber(z) ? " (z " + ZS(z) + CxMk(id) + ")" : ""; }

bool CxRob(const int id) { return id >= 0 && id < g_cxNT && g_cxTfd[id] && g_cxTst[id]; }

string CxReadC(const int ti, const int u)
  {
   int b = (ti * CX_NCL + u) * CX_NF;
   int i1 = CxIdx(g_cxC[b + 3]), i2 = CxIdx(g_cxC[b + 6]), i3 = CxIdx(g_cxC[b + 18]);
   string s = "";
   bool rob = false;
   if(i1 >= 0)
     {
      s += g_cxC[b + 2] > 0 ? "dopo sale piu' spesso" : "dopo scende piu' spesso";
      rob = rob || CxRob(i1);
     }
   if(i2 >= 0)
     {
      s += (s != "" ? "; " : "") + (g_cxC[b + 5] > 0 ? "rendimento a 1 candela sopra la media" : "rendimento a 1 candela sotto la media");
      rob = rob || CxRob(i2);
     }
   if(i3 >= 0)
     {
      s += (s != "" ? "; " : "") + (g_cxC[b + 17] > 0 ? "rendimento a 3 candele sopra la media" : "rendimento a 3 candele sotto la media");
      rob = rob || CxRob(i3);
     }
   if(s == "")
      return "nessuno scostamento";
   return s + (rob ? " [robusto]" : " [indizio]");
  }

string CxReadK(const int ti, const int u)
  {
   int b = (ti * CX_NCU + u) * CX_NFK;
   string s = "";
   bool rob = false;
   for(int m = 0; m < CX_NMK; m++)
     {
      int id = CxIdx(g_cxK[b + 11 + m]);
      if(id < 0)
         continue;
      bool pos = g_cxK[b + 6 + m] > 0;
      string t = "";
      if(m == 0)
         t = pos ? "sale piu' spesso" : "scende piu' spesso";
      else
         if(m == 1)
            t = pos ? "rendimento sopra la media" : "rendimento sotto la media";
         else
            if(m == 2)
               t = pos ? "muove di piu'" : "muove di meno";
            else
               if(m == 3)
                  t = pos ? "piu' candele grandi" : "meno candele grandi";
               else
                  t = pos ? "piu' impulsi" : "meno impulsi";
      s += (s != "" ? "; " : "") + t;
      rob = rob || CxRob(id);
     }
   if(s == "")
      return "nessuno scostamento";
   return s + (rob ? " [robusto]" : " [indizio]");
  }

// una riga di classe (HTML e testo); ALL e' il riferimento
void CxClassRow(const int ti, string &tx, const int u, const double minN)
  {
   int b = (ti * CX_NCL + u) * CX_NF;
   double nn = g_cxC[b];
   if(!MathIsValidNumber(nn) || nn < minN)
      return;
   string lab = CxLabel(u);
   int i1 = CxIdx(g_cxC[b + 3]), i2 = CxIdx(g_cxC[b + 6]), i3 = CxIdx(g_cxC[b + 18]);
   string ex = F(g_cxC[b + 12], 2) + " / " + F(g_cxC[b + 13], 2);
   if(u == CX_C_ALL)
     {
      W("<tr class='base'>" + TD(lab) + TD(I2S((long)nn)) + TD("100%") + TD(FP(g_cxC[b + 1], 1) + "%") + TD(F(g_cxC[b + 4], 3)) + TD(F(g_cxC[b + 10], 3)) +
        TD(F(g_cxC[b + 7], 2)) + TD(FP(g_cxC[b + 8], 1) + "%") + TD(FP(g_cxC[b + 9], 1) + "%") + TD(ex) + TD(F(g_cxC[b + 14], 3)) + TD(F(g_cxC[b + 15], 2)) +
        TD("riferimento") + "</tr>");
      R(tx, "  " + lab + " (N " + I2S((long)nn) + "): sale dopo " + FP(g_cxC[b + 1], 1) + "%, rendimento 1 candela " + F(g_cxC[b + 4], 3) + " ATR, 3 candele " +
        F(g_cxC[b + 10], 3) + " ATR, range dopo " + F(g_cxC[b + 7], 2) + " ATR, rompe il massimo " + FP(g_cxC[b + 8], 1) + "%, il minimo " + FP(g_cxC[b + 9], 1) + "%");
      return;
     }
   string rd = CxReadC(ti, u);
   W("<tr>" + TD(lab) + TD(I2S((long)nn)) + TD(FP(g_cxC[b + 16], 2) + "%") + CxZc(FP(g_cxC[b + 1], 1) + "%", g_cxC[b + 2], i1) +
     CxZc(F(g_cxC[b + 4], 3), g_cxC[b + 5], i2) + CxZc(F(g_cxC[b + 10], 3), g_cxC[b + 17], i3) + TD(F(g_cxC[b + 7], 2)) +
     TD(FP(g_cxC[b + 8], 1) + "%") + TD(FP(g_cxC[b + 9], 1) + "%") + TD(ex) + TD(F(g_cxC[b + 14], 3)) + TD(F(g_cxC[b + 15], 2)) + CxTDl(rd) + "</tr>");
   R(tx, "  " + lab + " (N " + I2S((long)nn) + ", " + FP(g_cxC[b + 16], 2) + "% delle candele): sale dopo " + FP(g_cxC[b + 1], 1) + "%" +
     CxZt(g_cxC[b + 2], i1) + ", rendimento 1 candela " + F(g_cxC[b + 4], 3) + " ATR" + CxZt(g_cxC[b + 5], i2) + ", 3 candele " + F(g_cxC[b + 10], 3) + " ATR" +
     CxZt(g_cxC[b + 17], i3) + ", range dopo " + F(g_cxC[b + 7], 2) + " ATR, rompe il massimo " + FP(g_cxC[b + 8], 1) + "%, il minimo " + FP(g_cxC[b + 9], 1) +
     "%, escursione 3 candele " + ex + " ATR, corsa +1/-1 ATR " + F(g_cxC[b + 14], 3) + ", ampiezza propria " + F(g_cxC[b + 15], 2) + " ATR -> " + rd);
  }

#define CX_CH "Classe|Casi|% delle candele|Sale dopo 1 candela|Rendimento dopo 1 (ATR)|Rendimento dopo 3 (ATR)|Range dopo (ATR)|Rompe il massimo|Rompe il minimo|Escursione su / giu in 3 (ATR)|Corsa +1/-1 ATR|Ampiezza propria (ATR)|Lettura"

void CxClassTable(const int ti, string &tx, const string title, const string desc, const int u0, const int cnt, const double minN)
  {
   R(tx, "");
   R(tx, "[" + CX_NAME[ti] + " - " + title + "]");
   W("<h3>" + title + "</h3><p class='desc'>" + desc + "</p>");
   int nr = 0;
   for(int k = 0; k < cnt; k++)
     {
      double nn = g_cxC[(ti * CX_NCL + u0 + k) * CX_NF];
      if(MathIsValidNumber(nn) && nn >= minN)
         nr++;
     }
   if(nr == 0)
     {
      W("<p class='muted'>Nessuna classe con almeno " + F(minN, 0) + " casi in questo timeframe.</p>");
      R(tx, "  Nessuna classe con almeno " + F(minN, 0) + " casi.");
      return;
     }
   THead(CX_CH);
   CxClassRow(ti, tx, CX_C_ALL, 0);
   for(int k = 0; k < cnt; k++)
      CxClassRow(ti, tx, u0 + k, minN);
   TEnd();
  }

// categorie di tempo di una dimensione
void CxCatTable(const int ti, string &tx, const int d)
  {
   int cnt = CxDimN(ti, d);
   if(cnt <= 0)
      return;
   int u0 = CxDimBase(d), bA = (ti * CX_NCU + CX_K_ALL) * CX_NFK;
   string desc = "";
   if(d == 0)
      desc = CX_SEC[ti] < 3600 ? "Ora del giorno (orologio dei dati; tra parentesi l'ora della piazza di riferimento)." : "Fascia oraria della candela (orologio dei dati).";
   else
      if(d == 1)
         desc = "Minuto dell'ora in cui apre la candela.";
      else
         if(d == 3)
            desc = "Settimana del mese dal giorno del mese: 1-7, 8-14, 15-21, 22-28, 29-31.";
         else
            desc = CX_KDN[d] + ".";
   R(tx, "");
   R(tx, "[" + CX_NAME[ti] + " - " + CX_KDN[d] + "]");
   W("<h3>" + CX_KDN[d] + "</h3><p class='desc'>" + desc + " Ogni riga contro tutte le candele del timeframe (z con errore robusto alle settimane e all'autocorrelazione).</p>");
   THead(CX_KDN[d] + "|Candele|% rialziste|Rendimento medio (ATR)|Range (punti base)|% oltre 1,5 ATR|% impulsi|Lettura");
   W("<tr class='base'>" + TD("Tutte le candele") + TD(I2S((long)g_cxK[bA])) + TD(FP(g_cxK[bA + 1], 1) + "%") + TD(F(g_cxK[bA + 2], 3)) + TD(F(g_cxK[bA + 3], 2)) +
     TD(FP(g_cxK[bA + 4], 1) + "%") + TD(FP(g_cxK[bA + 5], 2) + "%") + TD("riferimento") + "</tr>");
   R(tx, "  Tutte le candele (N " + I2S((long)g_cxK[bA]) + "): rialziste " + FP(g_cxK[bA + 1], 1) + "%, rendimento " + F(g_cxK[bA + 2], 3) + " ATR, range " +
     F(g_cxK[bA + 3], 2) + " pb, oltre 1,5 ATR " + FP(g_cxK[bA + 4], 1) + "%, impulsi " + FP(g_cxK[bA + 5], 2) + "%");
   string empty = "";
   for(int k = 0; k < cnt; k++)
     {
      int u = u0 + k, b = (ti * CX_NCU + u) * CX_NFK;
      double nn = g_cxK[b];
      string lab = (d == 0 && CX_SEC[ti] <= 3600) ? HourLab(k) : CxKLabel(ti, u);
      if(!MathIsValidNumber(nn) || nn <= 0)
        {
         empty += (empty != "" ? ", " : "") + lab;
         continue;
        }
      string rd = CxReadK(ti, u);
      string ratio = (MathIsValidNumber(g_cxK[bA + 3]) && g_cxK[bA + 3] > 0) ? " (x" + F(g_cxK[b + 3] / g_cxK[bA + 3], 2) + ")" : "";
      W("<tr>" + TD(lab) + TD(I2S((long)nn)) + CxZc(FP(g_cxK[b + 1], 1) + "%", g_cxK[b + 6], CxIdx(g_cxK[b + 11])) +
        CxZc(F(g_cxK[b + 2], 3), g_cxK[b + 7], CxIdx(g_cxK[b + 12])) + CxZc(F(g_cxK[b + 3], 2) + ratio, g_cxK[b + 8], CxIdx(g_cxK[b + 13])) +
        CxZc(FP(g_cxK[b + 4], 1) + "%", g_cxK[b + 9], CxIdx(g_cxK[b + 14])) + CxZc(FP(g_cxK[b + 5], 2) + "%", g_cxK[b + 10], CxIdx(g_cxK[b + 15])) +
        CxTDl(rd) + "</tr>");
      R(tx, "  " + lab + " (N " + I2S((long)nn) + "): rialziste " + FP(g_cxK[b + 1], 1) + "%" + CxZt(g_cxK[b + 6], CxIdx(g_cxK[b + 11])) + ", rendimento " +
        F(g_cxK[b + 2], 3) + " ATR" + CxZt(g_cxK[b + 7], CxIdx(g_cxK[b + 12])) + ", range " + F(g_cxK[b + 3], 2) + " pb" + ratio +
        CxZt(g_cxK[b + 8], CxIdx(g_cxK[b + 13])) + ", oltre 1,5 ATR " + FP(g_cxK[b + 4], 1) + "%" + CxZt(g_cxK[b + 9], CxIdx(g_cxK[b + 14])) + ", impulsi " +
        FP(g_cxK[b + 5], 2) + "%" + CxZt(g_cxK[b + 10], CxIdx(g_cxK[b + 15])) + " -> " + rd);
     }
   TEnd();
   double spanY = ((double)g_cxT1[ti] - (double)g_cxT0[ti]) / (365.25 * 86400.0);
   if(d == 6 || (d >= 4 && spanY < 3.0))
     {
      string nt = d == 6 ? "Anno per anno: descrizione senza test (ogni anno &egrave; un solo periodo)." : "Meno di 3 anni di storico: mesi e trimestri sono descritti senza test (ogni mese o trimestre sarebbe uno o due periodi soli).";
      W("<p class='muted'>" + nt + "</p>");
      R(tx, "  " + Plain(nt));
     }
   if(empty != "" && d <= 1)
     {
      W("<p class='muted'>Senza candele valide: " + empty + " (rollover o mercato chiuso).</p>");
      R(tx, "  Senza candele valide: " + empty + " (rollover o mercato chiuso).");
     }
  }

// gli eventi piu' frequenti: forme, pattern con nome, serie e posizione rispetto alla candela precedente, per frequenza
void CxFreqTable(const int ti, string &tx)
  {
   int cid[], m = 0;
   double fr[];
   int tot = 20 + CX_NNP + 12 + CX_NSV;
   ArrayResize(cid, tot);
   ArrayResize(fr, tot);
   int g0[4] = {CX_C_SH, CX_C_NP, CX_C_ST, CX_C_SV}, gn[4] = {20, CX_NNP, 12, CX_NSV};
   for(int g = 0; g < 4; g++)
      for(int k = 0; k < gn[g]; k++)
        {
         int u = g0[g] + k, b = (ti * CX_NCL + u) * CX_NF;
         if(!MathIsValidNumber(g_cxC[b]) || g_cxC[b] < 30)
            continue;
         cid[m] = u;
         fr[m] = g_cxC[b];
         m++;
        }
   R(tx, "");
   R(tx, "[" + CX_NAME[ti] + " - Gli eventi piu' frequenti]");
   W("<h3>Gli eventi pi&ugrave; frequenti</h3><p class='desc'>I 15 eventi (forme, pattern con nome, serie, posizione rispetto alla candela precedente) che capitano pi&ugrave; spesso, " +
     "con la frequenza in candele e in giorni di mercato. Le altre frequenze sono nelle tabelle sotto e nel CSV.</p>");
   if(m == 0)
     {
      W("<p class='muted'>Campione insufficiente.</p>");
      return;
     }
   bool perYear = CX_SEC[ti] >= 604800;
   double days = perYear ? MathMax(1.0, ((double)g_cxT1[ti] - (double)g_cxT0[ti]) / (365.25 * 86400.0)) :
                 MathMax(1.0, ((double)g_cxT1[ti] - (double)g_cxT0[ti]) / 86400.0 * 5.0 / 7.0);
   string per = perYear ? "all'anno" : "al giorno di mercato";
   int ord[];
   EdOrder(fr, m, ord);
   THead("Evento|Casi|% delle candele|Una volta ogni (candele)|" + (perYear ? "All'anno" : "Al giorno di mercato"));
   for(int k = 0; k < m && k < 15; k++)
     {
      int u = cid[ord[k]], b = (ti * CX_NCL + u) * CX_NF;
      double nn = g_cxC[b], sh = g_cxC[b + 16];
      W("<tr>" + TD(CxLabel(u)) + TD(I2S((long)nn)) + TD(FP(sh, 2) + "%") + TD(sh > 0 ? F(1.0 / sh, 1) : "-") + TD(F(nn / days, 2)) + "</tr>");
      R(tx, "  " + CxLabel(u) + ": " + I2S((long)nn) + " casi, " + FP(sh, 2) + "% delle candele, una volta ogni " + (sh > 0 ? F(1.0 / sh, 1) : "-") + " candele, " +
        F(nn / days, 2) + " " + per);
     }
   TEnd();
  }

// numero minimo di candele di una categoria per entrare nei confronti 'dove si muove di piu'
double CxMinN(const int ti) { return CX_SEC[ti] >= 604800 ? 8.0 : (CX_SEC[ti] >= 86400 ? 30.0 : 100.0); }

// dove si muove di piu': le unita' con il valore massimo e minimo di ogni dimensione
void CxWhenTable(const int ti, string &tx)
  {
   R(tx, "");
   R(tx, "[" + CX_NAME[ti] + " - Dove si muove di piu' e di meno]");
   W("<h3>Dove si muove di pi&ugrave; e di meno</h3><p class='desc'>Per ogni dimensione del tempo, la categoria con il range medio (in punti base) pi&ugrave; alto e pi&ugrave; basso, " +
     "con la quota di impulsi pi&ugrave; alta e bassa, e la pi&ugrave; e la meno rialzista (almeno 100 candele per categoria, 30 per D1, 8 per W1 e MN1).</p>");
   THead("Dimensione|Range maggiore|Range minore|Pi&ugrave; impulsi|Meno impulsi|Pi&ugrave; rialzista|Pi&ugrave; ribassista");
   int bA = (ti * CX_NCU + CX_K_ALL) * CX_NFK;
   for(int d = 0; d < 7; d++)
     {
      if(CxDimN(ti, d) <= 0)
         continue;
      int nv = 0, u0v = CxDimBase(d), cv = d == 0 ? 24 : (d == 1 ? 60 : (d == 2 ? 7 : (d == 3 ? 5 : (d == 4 ? 12 : (d == 5 ? 4 : 40)))));
      for(int k = 0; k < cv; k++)
         if(MathIsValidNumber(g_cxK[(ti * CX_NCU + u0v + k) * CX_NFK]) && g_cxK[(ti * CX_NCU + u0v + k) * CX_NFK] >= CxMinN(ti))
            nv++;
      if(nv < 2)
         continue;
      int sg[6] = {1, -1, 1, -1, 1, -1};
      string cell[6];
      int uu[6];
      int mm[6] = {2, 2, 4, 4, 0, 0};
      for(int k = 0; k < 6; k++)
        {
         uu[k] = CxBestUnit(ti, d, mm[k], CxMinN(ti), sg[k]);
         if(uu[k] < 0)
           {
            cell[k] = "-";
            continue;
           }
         int b = (ti * CX_NCU + uu[k]) * CX_NFK;
         string lab = (d == 0 && CX_SEC[ti] <= 3600) ? HourLab(uu[k] - CX_K_TOD) : CxKLabel(ti, uu[k]);
         string val = mm[k] == 2 ? F(g_cxK[b + 3], 2) + " pb" : (mm[k] == 4 ? FP(g_cxK[b + 5], 2) + "%" : FP(g_cxK[b + 1], 1) + "%");
         cell[k] = lab + " <small>" + val + "</small>";
        }
      W("<tr>" + TD(CX_KDN[d]) + TD(cell[0]) + TD(cell[1]) + TD(cell[2]) + TD(cell[3]) + TD(cell[4]) + TD(cell[5]) + "</tr>");
      string t = "  " + CX_KDN[d] + ": ";
      string nm[6] = {"range maggiore ", "range minore ", "piu' impulsi ", "meno impulsi ", "piu' rialzista ", "piu' ribassista "};
      for(int k = 0; k < 6; k++)
        {
         string c = cell[k];
         StringReplace(c, "<small>", "(");
         StringReplace(c, "</small>", ")");
         t += nm[k] + c + (k < 5 ? "; " : "");
        }
      R(tx, t + " [range di tutte " + F(g_cxK[bA + 3], 2) + " pb, impulsi " + FP(g_cxK[bA + 5], 2) + "%, rialziste " + FP(g_cxK[bA + 1], 1) + "%]");
     }
   TEnd();
  }

// pattern a due e tre candele: i piu' lontani dalle altre (almeno 100 casi)
void CxPairTable(const int ti, string &tx)
  {
   double sc[];
   int idx[];
   int m = 0;
   ArrayResize(sc, CX_C_NP - CX_C_S2);
   ArrayResize(idx, CX_C_NP - CX_C_S2);
   for(int u = CX_C_S2; u < CX_C_NP; u++)
     {
      int b = (ti * CX_NCL + u) * CX_NF;
      if(!MathIsValidNumber(g_cxC[b]) || g_cxC[b] < 100)
         continue;
      double z = 0;
      if(MathIsValidNumber(g_cxC[b + 2]))
         z = MathMax(z, MathAbs(g_cxC[b + 2]));
      if(MathIsValidNumber(g_cxC[b + 5]))
         z = MathMax(z, MathAbs(g_cxC[b + 5]));
      if(MathIsValidNumber(g_cxC[b + 17]))
         z = MathMax(z, MathAbs(g_cxC[b + 17]));
      sc[m] = z;
      idx[m] = u;
      m++;
     }
   R(tx, "");
   R(tx, "[" + CX_NAME[ti] + " - Coppie e terne di candele]");
   W("<h3>Coppie e terne di candele</h3><p class='desc'>Ogni candela &egrave; rialzista (+) o ribassista (-) e piccola (P, range sotto 0,7 ATR), normale (N) o grande (G, oltre 1,3 ATR). " +
     "Le 36 coppie e le 216 terne consecutive: qui le 30 pi&ugrave; lontane dalle altre candele (almeno 100 casi, per il massimo |z| tra le tre misure); " +
     "tutte nel file CSV.</p>");
   THead(CX_CH);
   CxClassRow(ti, tx, CX_C_ALL, 0);
   if(m > 0)
     {
      int ord[];
      EdOrder(sc, m, ord);
      for(int k = 0; k < m && k < 30; k++)
        {
         if(sc[ord[k]] < 2.0)
            break;
         CxClassRow(ti, tx, idx[ord[k]], 100);
        }
     }
   TEnd();
  }

string CX_PGN[CX_NSD] = {"Volume all'ora della candela prima", "ADX della candela prima", "Prezzo rispetto al VWAP alla chiusura della candela prima",
                         "Z-score del prezzo alla chiusura della candela prima", "Range delle 3 candele prima", "Movimento delle 3 candele prima", "Forma della candela prima"};

void CxImpulseTables(const int ti, string &tx)
  {
   double thr = g_cxThr[ti];
   R(tx, "");
   R(tx, "[" + CX_NAME[ti] + " - Impulsi]");
   W("<h3>Impulsi</h3><p class='desc'>Impulso = candela con range pari ad almeno " + F(thr, 2) + " ATR14 (il percentile " + F(InpImpulsePct, 1) +
     " dell'ampiezza di questo timeframe, almeno 2 ATR). Rialzista o ribassista secondo il corpo. Sono " + I2S(g_cxNimp[ti]) + " su " + I2S(g_cxN[ti]) +
     " candele (" + FP(g_cxImpP[ti], 2) + "%). Le righe 'Impulso rialzista/ribassista' nelle tabelle degli stati dicono cosa fa il prezzo dopo.</p>");
   R(tx, "  Soglia " + F(thr, 2) + " ATR14; " + I2S(g_cxNimp[ti]) + " impulsi su " + I2S(g_cxN[ti]) + " candele (" + FP(g_cxImpP[ti], 2) + "%)");
   //--- composizione
   string fam[6] = {"Doji", "Pin", "Trottola", "Corpo medio", "Corpo lungo", "Marubozu"};
   double tot[3];
   for(int g = 0; g < 3; g++)
     {
      tot[g] = 0;
      for(int k = 0; k < 6; k++)
         tot[g] += g_cxComp[(ti * 3 + g) * 8 + k];
     }
   W("<h3>Come sono fatti gli impulsi</h3>");
   THead("Forma|Tutte le candele|Impulsi rialzisti|Impulsi ribassisti");
   for(int k = 0; k < 6; k++)
     {
      string r = "<tr>" + TD(fam[k]);
      string t = "  " + fam[k] + ":";
      string sep = " ";
      for(int g = 0; g < 3; g++)
        {
         double p = tot[g] > 0 ? g_cxComp[(ti * 3 + g) * 8 + k] / tot[g] : Nan();
         r += TD(FP(p, 1) + "%");
         t += sep + (g == 0 ? "tutte " : (g == 1 ? "rialzisti " : "ribassisti ")) + FP(p, 1) + "%";
         sep = ", ";
        }
      W(r + "</tr>");
      R(tx, t);
     }
   string r2 = "<tr class='base'>" + TD("Ampiezza media (ATR)");
   string t2 = "  Ampiezza media:";
   string sep2 = " ";
   for(int g = 0; g < 3; g++)
     {
      double a = tot[g] > 0 ? g_cxComp[(ti * 3 + g) * 8 + 7] / tot[g] : Nan();
      r2 += TD(F(a, 2));
      t2 += sep2 + F(a, 2);
      sep2 = ", ";
     }
   W(r2 + "</tr>");
   R(tx, t2);
   TEnd();
   //--- cosa precede
   for(int d = 0; d < 2; d++)
     {
      int nd = g_cxNimpD[ti * 2 + d];
      string dn = d == 0 ? "rialzista" : "ribassista";
      R(tx, "");
      R(tx, "[" + CX_NAME[ti] + " - Cosa c'e' prima di un impulso " + dn + " (" + I2S(nd) + " casi)]");
      W("<h3>Cosa c'&egrave; prima di un impulso " + dn + " (" + I2S(nd) + " casi)</h3><p class='desc'>Stato letto alla chiusura della candela che precede l'impulso, " +
        "confrontato con le altre candele (non impulsi) della stessa ora del giorno e dello stesso regime di volatilit&agrave; (ATR14 / ATR100 sotto 0,8, normale, sopra 1,2): 'Attesi' = quante volte ci si aspetterebbe lo stato se l'impulso non dipendesse da esso. " +
        "z con errore robusto alle settimane e all'autocorrelazione; con pochi eventi attesi il modello nullo (binomiale) e la correzione di continuit&agrave;.</p>");
      if(nd < 30)
        {
         W("<p class='muted'>Troppo pochi impulsi per una lettura.</p>");
         R(tx, "  Troppo pochi impulsi per una lettura.");
         continue;
        }
      THead("Stato prima dell'impulso|Osservati|Attesi|Rapporto|z|Lettura");
      for(int g = 0; g < CX_NSD; g++)
        {
         Grp(CX_PGN[g], 6);
         R(tx, "  " + CX_PGN[g] + ":");
         for(int s = 0; s < CX_PSN[g]; s++)
           {
            int st = CX_PSG[g] + s, b = ((ti * 2 + d) * CX_NPS + st) * 4;
            double ob = g_cxP[b], ex = g_cxP[b + 1], z = g_cxP[b + 2];
            int id = CxIdx(g_cxP[b + 3]);
            if(!MathIsValidNumber(ob))
               continue;
            string rd = "compatibile con il caso";
            if(id >= 0)
               rd = (z > 0 ? "piu' frequente del normale" : "meno frequente del normale") + (CxRob(id) ? " [robusto]" : " [indizio]");
            else
               if(!MathIsValidNumber(z))
                  rd = "campione insufficiente";
            string ratio = ex > 0 ? F(ob / ex, 2) : "-";
            W("<tr>" + TD(CX_PSL[st]) + TD(F(ob, 0)) + TD(F(ex, 1)) + TDc(ratio, MathIsValidNumber(z) ? PCol(z, 0, 5) : "") +
              TDc(ZS(z) + CxMk(id), MathIsValidNumber(z) ? PCol(z, 0, 5) : "") + CxTDl(rd) + "</tr>");
            R(tx, "    " + CX_PSL[st] + ": " + F(ob, 0) + " contro " + F(ex, 1) + " attesi (x" + ratio + ", z " + ZS(z) + CxMk(id) + ") -> " + rd);
           }
        }
      TEnd();
     }
   //--- maggiori movimenti
   R(tx, "");
   R(tx, "[" + CX_NAME[ti] + " - I 5 movimenti maggiori]");
   W("<h3>I 5 movimenti maggiori</h3><p class='desc'>Le candele con il range pi&ugrave; ampio in percentuale del prezzo (orologio dei dati).</p>");
   THead("Quando|Direzione|Range % del prezzo|Range in ATR14");
   for(int k = 0; k < 5; k++)
     {
      int i = ti * 5 + k;
      if(g_cxTopP[i] < 0)
         continue;
      string when = TimeToString(g_cxTopT[i], TIME_DATE | TIME_MINUTES);
      W("<tr>" + TD(when) + TD(g_cxTopD[i] > 0 ? "rialzista" : "ribassista") + TD(F(g_cxTopP[i], 3) + "%") + TD(F(g_cxTopR[i], 1)) + "</tr>");
      R(tx, "  " + when + " " + (g_cxTopD[i] > 0 ? "rialzista" : "ribassista") + ": range " + F(g_cxTopP[i], 3) + "% del prezzo, " + F(g_cxTopR[i], 1) + " ATR");
     }
   TEnd();
  }

// i confronti robusti di un timeframe (FDR 5% e stabili nelle due meta'), ordinati per |z|
void CxRobustList(const int ti, string &tx, const int maxRows)
  {
   int ids[];
   double zz[];
   int m = 0;
   ArrayResize(ids, MathMax(1, g_cxNT));
   ArrayResize(zz, MathMax(1, g_cxNT));
   for(int i = 0; i < g_cxNT; i++)
      if(g_cxTtf[i] == ti && g_cxTfd[i] && g_cxTst[i])
        {
         ids[m] = i;
         zz[m] = MathAbs(g_cxTz[i]);
         m++;
        }
   R(tx, "");
   R(tx, "[" + CX_NAME[ti] + " - Confronti robusti (FDR 5% e stesso verso nelle due meta')]");
   W("<h3>Confronti robusti</h3><p class='desc'>Superano il controllo dei test multipli (FDR 5% sui confronti della stessa famiglia: direzione, ritmo dell'attivit&agrave;, precursori) e hanno lo stesso verso " +
     "nelle due met&agrave; dello storico. Descrivono l'andamento del prezzo, non un guadagno: costi e slittamento non sono considerati.</p>");
   if(m == 0)
     {
      W("<p class='muted'>Nessun confronto robusto in questo timeframe.</p>");
      R(tx, "  Nessun confronto robusto.");
      return;
     }
   int ord[];
   EdOrder(zz, m, ord);
   THead("Confronto|z");
   for(int k = 0; k < m && k < maxRows; k++)
     {
      int id = ids[ord[k]];
      W("<tr>" + TD(g_cxTtx[id]) + TDc(ZS(g_cxTz[id]), PCol(g_cxTz[id], 0, 8)) + "</tr>");
      R(tx, "  z " + ZS(g_cxTz[id]) + ": " + g_cxTtx[id]);
     }
   TEnd();
   if(m > maxRows)
     {
      W("<p class='muted'>Altri " + I2S(m - maxRows) + " confronti robusti nel rapporto testuale completo e nel CSV.</p>");
      R(tx, "  (altri " + I2S(m - maxRows) + " confronti robusti nel CSV)");
     }
  }

void CxRenderTf(const int ti)
  {
   string tf = CX_NAME[ti], tx = "";
   if(g_cxN[ti] <= 0)
      return;
   string per = TimeToString(g_cxT0[ti], TIME_DATE) + " &rarr; " + TimeToString(g_cxT1[ti], TIME_DATE);
   W("<details id='cx-" + tf + "'><summary><b>" + tf + "</b> &middot; " + I2S(g_cxN[ti]) + " candele (" + per + ") &middot; rialziste " + FP(g_cxBull[ti], 1) +
     "% &middot; range mediano " + F(g_cxMedR[ti], 3) + "% &middot; soglia impulso " + F(g_cxThr[ti], 1) + " ATR &middot; confronti robusti " + I2S(g_cxNrob[ti]) +
     " su " + I2S(g_cxNtst[ti]) + " con |z| 2 o pi&ugrave;</summary>");
   R(tx, "############ " + tf + " ############");
   R(tx, "Periodo " + TimeToString(g_cxT0[ti], TIME_DATE) + " -> " + TimeToString(g_cxT1[ti], TIME_DATE) + ", " + I2S(g_cxN[ti]) + " candele, rialziste " +
     FP(g_cxBull[ti], 1) + "%, range mediano " + F(g_cxMedR[ti], 3) + "% del prezzo, corpo mediano " + FP(g_cxBody[ti], 0) + "% del range, soglia impulso " +
     F(g_cxThr[ti], 2) + " ATR14, impulsi " + I2S(g_cxNimp[ti]) + " (" + FP(g_cxImpP[ti], 2) + "%), confronti robusti " + I2S(g_cxNrob[ti]) + " su " +
     I2S(g_cxNtst[ti]) + " con |z| 2 o piu'.");
   W("<div class='kpi'>");
   Kpi("Candele analizzate", I2S(g_cxN[ti]), per);
   Kpi("Rialziste", FP(g_cxBull[ti], 1) + "%", "");
   Kpi("Range mediano", F(g_cxMedR[ti], 3) + "%", "del prezzo");
   Kpi("Corpo mediano", FP(g_cxBody[ti], 0) + "%", "del range");
   Kpi("Soglia dell'impulso", F(g_cxThr[ti], 1) + " ATR", "percentile " + F(InpImpulsePct, 1));
   Kpi("Impulsi", I2S(g_cxNimp[ti]), FP(g_cxImpP[ti], 2) + "% delle candele");
   Kpi("Confronti robusti", I2S(g_cxNrob[ti]), "su " + I2S(g_cxNtst[ti]) + " con |z| 2 o pi&ugrave;");
   W("</div>");
   CxRobustList(ti, tx, 25);
   CxWhenTable(ti, tx);
   CxFreqTable(ti, tx);
   for(int d = 0; d < 7; d++)
      CxCatTable(ti, tx, d);
   CxClassTable(ti, tx, "Forme di candela", "Forma dal rapporto tra corpo e range e dalle ombre: doji (corpo fino al 10%; libellula, lapide e gambe lunghe), " +
                "pin (corpo fino al 35% con ombra lunga da un lato: martello o stella cadente), trottola, corpo medio (35-60%), corpo lungo (60-85%), marubozu (oltre 85%). " +
                "Ogni forma per direzione della candela.", CX_C_SH, 20, 30);
   CxClassTable(ti, tx, "Pattern con nome", "Definiti su ATR14 prima della candela; il pattern si chiude sulla candela indicata e i risultati contano da quella chiusura. " +
                "Engulfing e harami (corpo), tweezer (massimi o minimi uguali entro 0,05 ATR), morning e evening star, tre soldati e tre corvi (corpi di almeno 0,4 ATR), " +
                "pin al massimo o minimo di 10 candele, NR4 e NR7, chiusura oltre il massimo o il minimo di 20 candele, inside bar, outside bar.", CX_C_NP, CX_NNP, 30);
   CxClassTable(ti, tx, "Serie nella stessa direzione", "Da 1 a 6 o pi&ugrave; candele consecutive rialziste o ribassiste che finiscono su questa candela.", CX_C_ST, 12, 30);
   CxClassTable(ti, tx, "Posizione rispetto alla candela precedente", "Massimi e minimi della candela precedente: inside e outside bar, rotture, false rotture (rompe e chiude dentro), " +
                "chiusura oltre il massimo o il minimo precedente, gap di apertura.", CX_C_SV, CX_NSV, 30);
   R(tx, "");
   R(tx, "[" + tf + " - Stati]");
   W("<h3>Stati: ADX, VWAP, z-score, volume all'ora, volatilit&agrave;, ampiezza, posizione rispetto ad alti e bassi precedenti</h3><p class='desc'>" +
     "ADX(14) di Wilder. VWAP ancorato all'inizio del giorno (D1: della settimana; W1: del mese; MN1: dell'anno) e distanza dalla chiusura in sigma (deviazione standard " +
     "dei prezzi tipici pesati per volume dall'ancora; senza volume: media semplice). Z-score = distanza della chiusura dalla media delle ultime 20 chiusure in deviazioni standard. " +
     "Volume all'ora = volume della candela diviso la media delle 20 candele precedenti allo stesso orario. Volatilit&agrave; = ATR14 / ATR100. Ampiezza = range / ATR14 prima della candela. " +
     "Posizione = dove chiude la candela nel range delle ultime 20 candele. Ora, 4 ore, giorno, settimana e mese prima = la chiusura contro il massimo e il minimo del periodo precedente (solo per i timeframe pi&ugrave; piccoli del periodo).</p>");
   THead(CX_CH);
   CxClassRow(ti, tx, CX_C_ALL, 0);
   string gn[13] = {"ADX", "Prezzo rispetto al VWAP", "Z-score del prezzo (20 candele)", "Volume all'ora", "Volatilita' (ATR14 / ATR100)", "Ampiezza della candela",
                    "Posizione nelle ultime 20 candele", "Rispetto al giorno prima", "Rispetto alla settimana prima", "Rispetto al mese prima",
                    "Rispetto all'ora prima (H1)", "Rispetto alle 4 ore prima (H4)", "Impulsi"};
   int gu[13] = {CX_C_AD, CX_C_VW, CX_C_ZS, CX_C_RV, CX_C_VO, CX_C_SZ, CX_C_DN, CX_C_PD, CX_C_PW, CX_C_PM, CX_C_PH, CX_C_P4, CX_C_IU};
   int gc[13] = {4, 5, 5, 4, 3, 5, 5, 3, 3, 3, 3, 3, 2};
   for(int g = 0; g < 13; g++)
     {
      bool any = false;
      for(int k = 0; k < gc[g]; k++)
         if(MathIsValidNumber(g_cxC[(ti * CX_NCL + gu[g] + k) * CX_NF]) && g_cxC[(ti * CX_NCL + gu[g] + k) * CX_NF] >= 30)
            any = true;
      if(!any)
         continue;
      Grp(gn[g], 13);
      R(tx, "  " + gn[g] + ":");
      for(int k = 0; k < gc[g]; k++)
         CxClassRow(ti, tx, gu[g] + k, 30);
     }
   TEnd();
   CxPairTable(ti, tx);
   CxImpulseTables(ti, tx);
   W("<h3>Testo di " + tf + "</h3><button class='cp' onclick=\"cp(this,'cxta-" + tf + "')\">Copia il testo di " + tf + "</button><textarea id='cxta-" + tf +
     "' readonly style='height:40vh'>");
   W(tx);
   W("</textarea></details>");
   g_cxTxtTf += "\n" + tx;
  }

// riga di riepilogo di ogni timeframe
void CxSummaryTable(void)
  {
   W("<h3>Riepilogo dei timeframe</h3>");
   THead("Timeframe|Periodo|Candele|Rialziste|Range mediano|Corpo mediano|Soglia impulso (ATR)|Impulsi|Confronti robusti|Test con z oltre 2");
   R(g_cxTxt, "RIEPILOGO DEI TIMEFRAME");
   for(int ti = 0; ti < CX_NTF; ti++)
     {
      if(g_cxN[ti] <= 0)
        {
         string why = g_cxSkip[ti] == 1 ? "servono dati M1: la serie base e' M5" : "candele o storico insufficienti";
         W("<tr>" + TD(CX_NAME[ti]) + "<td colspan='9' style='text-align:left'>non calcolato (" + why + ")</td></tr>");
         R(g_cxTxt, "  " + CX_NAME[ti] + ": non calcolato (" + why + ")");
         continue;
        }
      W("<tr>" + TD("<a style='color:#93c5fd' href='#cx-" + CX_NAME[ti] + "' onclick=\"var e=document.getElementById('cx-" + CX_NAME[ti] + "');e.open=true;\">" + CX_NAME[ti] + "</a>") +
        TD(TimeToString(g_cxT0[ti], TIME_DATE) + " &rarr; " + TimeToString(g_cxT1[ti], TIME_DATE)) + TD(I2S(g_cxN[ti])) + TD(FP(g_cxBull[ti], 1) + "%") +
        TD(F(g_cxMedR[ti], 3) + "%") + TD(FP(g_cxBody[ti], 0) + "%") + TD(F(g_cxThr[ti], 2)) + TD(I2S(g_cxNimp[ti])) + TD(I2S(g_cxNrob[ti])) + TD(I2S(g_cxNtst[ti])) + "</tr>");
      R(g_cxTxt, "  " + CX_NAME[ti] + ": " + TimeToString(g_cxT0[ti], TIME_DATE) + " -> " + TimeToString(g_cxT1[ti], TIME_DATE) + ", " + I2S(g_cxN[ti]) +
        " candele, rialziste " + FP(g_cxBull[ti], 1) + "%, range mediano " + F(g_cxMedR[ti], 3) + "%, corpo mediano " + FP(g_cxBody[ti], 0) + "%, soglia impulso " +
        F(g_cxThr[ti], 2) + " ATR, impulsi " + I2S(g_cxNimp[ti]) + ", robusti " + I2S(g_cxNrob[ti]) + " su " + I2S(g_cxNtst[ti]));
     }
   TEnd();
  }

// tabella incrociata: dove si muove di piu' su ogni timeframe
void CxCrossTable(void)
  {
   W("<h3>Quando si muove di pi&ugrave;, timeframe per timeframe</h3><p class='desc'>Per ogni timeframe la fascia con il range medio pi&ugrave; alto, la fascia con la quota di impulsi pi&ugrave; alta, " +
     "il giorno della settimana e il mese pi&ugrave; mossi (almeno 100 candele per categoria; 30 per D1, 8 per W1 e MN1). L'ora &egrave; quella dei dati.</p>");
   THead("Timeframe|Ora con il range maggiore|Ora con pi&ugrave; impulsi|Giorno con il range maggiore|Giorno con pi&ugrave; impulsi|Settimana del mese con il range maggiore|Mese con il range maggiore|Mese con pi&ugrave; impulsi");
   R(g_cxTxt, "");
   R(g_cxTxt, "QUANDO SI MUOVE DI PIU', TIMEFRAME PER TIMEFRAME");
   int dm[7] = {0, 0, 2, 2, 3, 4, 4}, mm[7] = {2, 4, 2, 4, 2, 2, 4};
   for(int ti = 0; ti < CX_NTF; ti++)
     {
      if(g_cxN[ti] <= 0)
         continue;
      string row = "<tr>" + TD(CX_NAME[ti]), t = "  " + CX_NAME[ti] + ": ";
      string nm[7] = {"ora range ", "ora impulsi ", "giorno range ", "giorno impulsi ", "settimana del mese range ", "mese range ", "mese impulsi "};
      for(int k = 0; k < 7; k++)
        {
         int d = dm[k];
         if(d == 0 && CX_SEC[ti] >= 86400)
            d = -1;
         string cell = "-";
         if(d >= 0 && CxDimN(ti, d) > 0)
           {
            int u = CxBestUnit(ti, d, mm[k], CxMinN(ti), 1);
            if(u >= 0)
              {
               int b = (ti * CX_NCU + u) * CX_NFK;
               cell = ((d == 0 && CX_SEC[ti] <= 3600) ? HourLab(u - CX_K_TOD) : CxKLabel(ti, u)) + " <small>" +
                      (mm[k] == 2 ? F(g_cxK[b + 3], 2) + " pb" : FP(g_cxK[b + 5], 2) + "%") + "</small>";
              }
           }
         row += TD(cell);
         string c = cell;
         StringReplace(c, "<small>", "(");
         StringReplace(c, "</small>", ")");
         t += nm[k] + c + (k < 6 ? "; " : "");
        }
      W(row + "</tr>");
      R(g_cxTxt, t);
     }
   TEnd();
  }

// i confronti robusti di tutti i timeframe
void CxRobustAll(const int maxRows)
  {
   int ids[];
   double zz[];
   int m = 0;
   ArrayResize(ids, MathMax(1, g_cxNT));
   ArrayResize(zz, MathMax(1, g_cxNT));
   for(int i = 0; i < g_cxNT; i++)
      if(g_cxTfd[i] && g_cxTst[i])
        {
         ids[m] = i;
         zz[m] = MathAbs(g_cxTz[i]);
         m++;
        }
   W("<h3>I confronti pi&ugrave; solidi di tutti i timeframe</h3><p class='desc'>Su " + I2S((long)g_cxNAll) + " confronti (classi di candele, fasce di tempo, precursori degli impulsi, tutti i timeframe), " +
     I2S(m) + " superano il controllo FDR 5% (per famiglia: direzione, ritmo dell'attivit&agrave;, precursori) e hanno lo stesso verso nelle due met&agrave; dello storico. Qui i primi " + I2S(maxRows) + " per |z|. " +
     "I confronti sul range e sugli impulsi per ora sono in gran parte la stagionalit&agrave; della volatilit&agrave; (nota e prevedibile); quelli sulla direzione sono i pi&ugrave; rari.</p>");
   R(g_cxTxt, "");
   R(g_cxTxt, "I CONFRONTI PIU' SOLIDI DI TUTTI I TIMEFRAME (" + I2S(m) + " robusti su " + I2S((long)g_cxNAll) + " confronti)");
   if(m == 0)
     {
      W("<p class='muted'>Nessun confronto robusto.</p>");
      R(g_cxTxt, "  Nessuno.");
      return;
     }
   int ord[];
   EdOrder(zz, m, ord);
   THead("Confronto|z");
   for(int k = 0; k < m && k < maxRows; k++)
     {
      int id = ids[ord[k]];
      W("<tr>" + TD(g_cxTtx[id]) + TDc(ZS(g_cxTz[id]), PCol(g_cxTz[id], 0, 8)) + "</tr>");
      R(g_cxTxt, "  z " + ZS(g_cxTz[id]) + ": " + g_cxTtx[id]);
     }
   TEnd();
  }

//--- CSV
string CxGroup(const int u)
  {
   if(u == CX_C_ALL)
      return "Tutte";
   if(u < CX_C_S2)
      return "Forma";
   if(u < CX_C_S3)
      return "Coppia";
   if(u < CX_C_NP)
      return "Terna";
   if(u < CX_C_ST)
      return "Pattern";
   if(u < CX_C_SV)
      return "Serie";
   if(u < CX_C_AD)
      return "Struttura";
   if(u < CX_C_VW)
      return "ADX";
   if(u < CX_C_ZS)
      return "VWAP";
   if(u < CX_C_RV)
      return "Z-score";
   if(u < CX_C_VO)
      return "Volume all'ora";
   if(u < CX_C_SZ)
      return "Volatilita'";
   if(u < CX_C_DN)
      return "Ampiezza";
   if(u < CX_C_PD)
      return "Posizione 20 candele";
   if(u < CX_C_PW)
      return "Giorno precedente";
   if(u < CX_C_PM)
      return "Settimana precedente";
   if(u < CX_C_PH)
      return "Mese precedente";
   if(u < CX_C_P4)
      return "Ora precedente";
   if(u < CX_C_IU)
      return "4 ore precedenti";
   return "Impulso";
  }

string CxFlag(const int id) { return id < 0 ? "" : (CxRob(id) ? "robusto" : (g_cxTfd[id] ? "solo FDR" : "indizio")); }

void CxCsvWrite(const string clean, string &path1, string &path2)
  {
   string n1 = "MarketProfiler_" + clean + "_candele.csv", n2 = "MarketProfiler_" + clean + "_orari_candele.csv";
   int fl = FILE_WRITE | FILE_TXT | FILE_ANSI | (InpCommonDir ? FILE_COMMON : 0);
   g_cxCsv = FileOpen(n1, fl);
   g_cxCsvK = FileOpen(n2, fl);
   string root = (InpCommonDir ? TerminalInfoString(TERMINAL_COMMONDATA_PATH) : TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5") + "\\Files\\";
   path1 = g_cxCsv != INVALID_HANDLE ? root + n1 : "";
   path2 = g_cxCsvK != INVALID_HANDLE ? root + n2 : "";
   if(g_cxCsv != INVALID_HANDLE)
      FileWriteString(g_cxCsv, "Timeframe;Gruppo;Classe;Casi;Quota delle candele;Sale dopo 1;z;Test;Rendimento dopo 1 (ATR);z;Test;Range dopo (ATR);Rompe il massimo;Rompe il minimo;" +
                      "Rendimento dopo 3 (ATR);z;Test;Sale dopo 3;Escursione su in 3 (ATR);Escursione giu in 3 (ATR);Corsa +1/-1 ATR;Ampiezza propria (ATR)\r\n");
   if(g_cxCsvK != INVALID_HANDLE)
      FileWriteString(g_cxCsvK, "Timeframe;Dimensione;Categoria;Candele;% rialziste;z;Test;Rendimento medio (ATR);z;Test;Range (punti base);z;Test;% oltre 1,5 ATR;z;Test;% impulsi;z;Test\r\n");
   for(int ti = 0; ti < CX_NTF; ti++)
     {
      if(g_cxN[ti] <= 0)
         continue;
      if(g_cxCsv != INVALID_HANDLE)
         for(int u = 0; u < CX_NCL; u++)
           {
            int b = (ti * CX_NCL + u) * CX_NF;
            if(!MathIsValidNumber(g_cxC[b]) || g_cxC[b] <= 0)
               continue;
            FileWriteString(g_cxCsv, CX_NAME[ti] + ";" + CxGroup(u) + ";" + Plain(CxLabel(u)) + ";" + CN(g_cxC[b], 0) + ";" + CN(g_cxC[b + 16], 5) + ";" + CN(g_cxC[b + 1], 4) + ";" +
                            CN(g_cxC[b + 2], 2) + ";" + CxFlag(CxIdx(g_cxC[b + 3])) + ";" + CN(g_cxC[b + 4], 4) + ";" + CN(g_cxC[b + 5], 2) + ";" + CxFlag(CxIdx(g_cxC[b + 6])) + ";" +
                            CN(g_cxC[b + 7], 3) + ";" + CN(g_cxC[b + 8], 4) + ";" + CN(g_cxC[b + 9], 4) + ";" + CN(g_cxC[b + 10], 4) + ";" + CN(g_cxC[b + 17], 2) + ";" +
                            CxFlag(CxIdx(g_cxC[b + 18])) + ";" + CN(g_cxC[b + 11], 4) + ";" + CN(g_cxC[b + 12], 3) + ";" + CN(g_cxC[b + 13], 3) + ";" + CN(g_cxC[b + 14], 4) + ";" +
                            CN(g_cxC[b + 15], 3) + "\r\n");
           }
      if(g_cxCsvK != INVALID_HANDLE)
         for(int u = 0; u < CX_NCU; u++)
           {
            int b = (ti * CX_NCU + u) * CX_NFK;
            if(!MathIsValidNumber(g_cxK[b]) || g_cxK[b] <= 0)
               continue;
            int dim = CxUnitDim(u);
            string lab = u == CX_K_ALL ? "Tutte le candele" : ((dim == 0 && CX_SEC[ti] <= 3600) ? StringFormat("%02dh", u - CX_K_TOD) : CxKLabel(ti, u));
            string ln = CX_NAME[ti] + ";" + (dim >= 0 ? CX_KDN[dim] : "Tutte") + ";" + lab + ";" + CN(g_cxK[b], 0);
            for(int m = 0; m < CX_NMK; m++)
               ln += ";" + CN(g_cxK[b + 1 + m], m == 1 ? 4 : (m == 2 ? 3 : 4)) + ";" + CN(g_cxK[b + 6 + m], 2) + ";" + CxFlag(CxIdx(g_cxK[b + 11 + m]));
            FileWriteString(g_cxCsvK, ln + "\r\n");
           }
     }
   if(g_cxCsv != INVALID_HANDLE)
      FileClose(g_cxCsv);
   if(g_cxCsvK != INVALID_HANDLE)
      FileClose(g_cxCsvK);
   g_cxCsv = INVALID_HANDLE;
   g_cxCsvK = INVALID_HANDLE;
  }

//+------------------------------------------------------------------+
//| Scheda Candele: driver                                            |
//+------------------------------------------------------------------+
string CxRollTxt(void)
  {
   if(!InpRollSkip)
      return "Rollover incluso in tutte le candele (parametro 'Rollover' = false).";
   string w = HM(1440 - RollPre()) + "-" + HM(RollPost()) + " del broker (NY " + HM(1440 - RollPre() - 420) + "-" + HM(RollPost() - 420) + ")";
   return "Rollover (NY 17:00 = mezzanotte del broker, finestra " + w + "): sui dati bid il prezzo scende senza scambi veri e lo spread si allarga. Fino a H1 le candele che " +
          "toccano la finestra sono escluse; da H2 a H12 le barre nella finestra sono tolte dalla candela (il range si riporta alla durata nominale; escluse le candele con oltre il 25% " +
          "di finestra); da D1 le barre nella finestra sono tolte.";
  }

string CxDescHtml(void)
  {
   return "Rapporto descrittivo su <b>tutti i 21 timeframe di MetaTrader 5</b>, da M1 a MN1, costruiti dai dati M1 (o M5) sull'orologio dei dati, con la settimana da domenica. " +
          "Per ogni timeframe: <b>quando</b> (ora, minuto, giorno della settimana, settimana del mese, mese, trimestre, anno: dove il prezzo si muove di pi&ugrave;, dove ci sono pi&ugrave; impulsi, " +
          "dove &egrave; pi&ugrave; rialzista o ribassista); <b>come sono fatte le candele</b> (forme, 22 pattern con nome, tutte le coppie e terne di candele rialziste/ribassiste " +
          "piccole/normali/grandi, serie nella stessa direzione); <b>dove sono rispetto agli alti e ai bassi precedenti</b> (candela prima, ultime 20 candele, giorno, settimana e mese prima); " +
          "<b>stati</b> (ADX, VWAP, z-score, volume all'ora, volatilit&agrave;, ampiezza); <b>impulsi</b> (soglia, quando avvengono, cosa c'&egrave; prima, cosa segue). " +
          "Ogni classe di candele &egrave; misurata su cosa succede dopo: probabilit&agrave; che la candela successiva salga, rendimento a 1 e 3 candele in ATR14 (ATR alla chiusura della candela), " +
          "rottura del massimo e del minimo, corsa a +1 ATR contro -1 ATR entro 12 candele. <b>z</b> = distanza dal comportamento di tutte le candele del timeframe, con errore robusto alle settimane, corretto per l'autocorrelazione " +
          "(le candele della stessa settimana non sono indipendenti e la volatilit&agrave; persiste da una settimana all'altra): entro &plusmn;2 compatibile con il caso. <b>&dagger;</b> = robusto (controllo FDR 5% dentro la famiglia di confronti &mdash; direzione, ritmo dell'attivit&agrave;, precursori degli impulsi &mdash; su tutti i timeframe, e " +
          "stesso verso nelle due met&agrave; dello storico); <b>&sect;</b> = solo FDR. Sono misure descrittive dell'andamento del prezzo: non includono spread, commissioni e slittamento, " +
          "e sui timeframe bassi il costo supera quasi sempre l'effetto. Le candele sono valide solo se complete (almeno met&agrave; delle barre attese) e consecutive; " +
          "per le sequenze contano solo candele adiacenti. " + CxRollTxt();
  }

string CxDescText(void)
  {
   return "Rapporto descrittivo su tutti i 21 timeframe di MetaTrader 5, da M1 a MN1, costruiti dai dati M1 (o M5) sull'orologio dei dati, con la settimana da domenica.\n" +
          "Per ogni timeframe: quando (ora, minuto, giorno della settimana, settimana del mese, mese, trimestre, anno), come sono fatte le candele (forme, 22 pattern con nome, " +
          "coppie e terne, serie), dove sono rispetto agli alti e bassi precedenti (candela prima, ultime 20 candele, giorno, settimana e mese prima), stati (ADX, VWAP, z-score, " +
          "volume all'ora, volatilita', ampiezza), impulsi (soglia, quando, cosa c'e' prima, cosa segue).\n" +
          "Ogni classe e' misurata su cosa succede dopo: probabilita' che la candela successiva salga, rendimento a 1 e 3 candele in ATR14, rottura del massimo e del minimo, " +
          "corsa a +1 ATR contro -1 ATR entro 12 candele. z = distanza dal comportamento di tutte le candele del timeframe con errore robusto alle settimane e corretto per l'autocorrelazione: entro +/-2 compatibile con il caso. " +
          "Segno robusto (dagger) = controllo FDR 5% sui confronti di tutti i timeframe della stessa famiglia (direzione, ritmo dell'attivita', precursori degli impulsi) e stesso verso nelle due meta' dello storico; segno sezione = solo FDR. " +
          "Sono misure descrittive: non includono spread, commissioni e slittamento.\n" + Plain(CxRollTxt());
  }

void CandTab(CSeries &b, const int baseSec, const string clean)
  {
   g_cxTxt = "";
   g_cxTxtTf = "";
   HI_NAME[ED_MC] = "Candele su tutti i timeframe: forme, pattern, sequenze, stati e orari contro tutte le candele, e cosa precede gli impulsi (z con errore robusto alle settimane)";
   if(!InpCand)
     {
      SecStart("Candele", "");
      W("<p class='muted'>Disattivata (parametro 'Candele').</p>");
      SecEnd();
      g_cxTxt = "CANDELE: disattivata.\n";
      return;
     }
   if(b.n < 5000)
     {
      SecStart("Candele", "");
      W("<p class='muted'>Servono dati M1 o M5.</p>");
      SecEnd();
      g_cxTxt = "CANDELE: non calcolato (servono dati M1 o M5).\n";
      return;
     }
   CxAlloc();
   for(int ti = 0; ti < CX_NTF; ti++)
      g_cxSkip[ti] = 0;
   //--- livelli del giorno, della settimana e del mese (sull'intero storico)
   CxBuild(b, 0, baseSec, 86400, g_cxLvD);
   CxBuild(b, 0, baseSec, 604800, g_cxLvW);
   CxBuild(b, 0, baseSec, 2592000, g_cxLvM);
   CxBuild(b, 0, baseSec, 14400, g_cxLvQ);
   CxBuild(b, 0, baseSec, 3600, g_cxLvH);
   int i0s = 0;
   if(InpCandYears > 0)
     {
      datetime from = (datetime)((long)b.t[b.n - 1] - (long)InpCandYears * 365 * 86400);
      i0s = LowerBound(b.t, b.n, from);
     }
   for(int ti = 0; ti < CX_NTF && !IsStopped(); ti++)
     {
      int sec = CX_SEC[ti];
      if(sec < baseSec || sec % baseSec != 0)
        {
         g_cxSkip[ti] = 1;
         continue;
        }
      Comment("MarketProfiler: candele ", CX_NAME[ti], " ...");
      if(!CxRunTf(b, sec <= 3600 ? i0s : 0, baseSec, ti))
         g_cxSkip[ti] = 2;
      PrintFormat("[MarketProfiler] candele %s: %d candele, %d confronti oltre |z| 2", CX_NAME[ti], g_cxN[ti], g_cxNtst[ti]);
     }
   g_cxLvD.Free();
   g_cxLvW.Free();
   g_cxLvM.Free();
   g_cxLvH.Free();
   g_cxLvQ.Free();
   CxFdr();
   string p1, p2;
   CxCsvWrite(clean, p1, p2);
   g_cxTxt = "CANDELE - TUTTI I TIMEFRAME DA M1 A MN1\n" + CxDescText() + "\n";
   if(InpCandYears > 0)
      g_cxTxt += "Timeframe fino a H1: ultimi " + I2S(InpCandYears) + " anni di storico (parametro 'Candele: anni').\n";
   g_cxTxt += "\n";
   SecStart("Candele: tutti i timeframe da M1 a MN1", CxDescHtml());
   if(p1 != "")
      W("<p class='muted'>Tutte le classi e tutte le fasce di tempo, per ogni timeframe, in CSV (punto e virgola, virgola decimale): <b>" + p1 + "</b> e <b>" + p2 + "</b>.</p>");
   CxSummaryTable();
   CxCrossTable();
   CxRobustAll(60);
   SecEnd();
   SecStart("Un timeframe alla volta", "Apri un timeframe: confronti robusti, dove si muove di pi&ugrave;, tabelle per ora/minuto/giorno/settimana del mese/mese/trimestre/anno, forme, " +
            "pattern con nome, serie, posizione rispetto alla candela precedente, stati, coppie e terne, impulsi e cosa li precede, movimenti maggiori, e il testo da copiare.");
   for(int ti = 0; ti < CX_NTF && !IsStopped(); ti++)
      CxRenderTf(ti);
   SecEnd();
   Comment("");
  }

//+------------------------------------------------------------------+
//| Blocco per la Sintesi edge                                        |
//+------------------------------------------------------------------+
void CxEdgeBlock(void)
  {
   if(g_cxNAll <= 0)
      return;
   int nr[3], nt[3];
   ArrayInitialize(nr, 0);
   ArrayInitialize(nt, 0);
   // tipo: 0 direzione (dopo la candela / categoria), 1 ritmo dell'attivita' (range, candele grandi, impulsi), 2 precursori degli impulsi
   for(int i = 0; i < g_cxNT; i++)
     {
      int k = g_cxTk[i], ty = (k == 0 || k == 1 || k == 2 || k == 3 || k == 8) ? 0 : (k == 6 ? 2 : 1);
      nt[ty]++;
      if(g_cxTfd[i] && g_cxTst[i])
         nr[ty]++;
     }
   SecStart("Candele: cosa e' robusto sui 21 timeframe",
            "Sintesi della scheda Candele. Sono misure descrittive dell'andamento del prezzo (contro tutte le candele dello stesso timeframe), senza costi: <b>direzione</b> = cosa fa il prezzo dopo una " +
            "classe di candele o in una fascia di tempo; <b>ritmo</b> = quanto si muove (range, candele grandi, impulsi), in gran parte stagionalit&agrave; della volatilit&agrave;; " +
            "<b>precursori</b> = cosa c'&egrave; prima di un impulso. Per usarle in una strategia servono costi, regola di entrata e uscita e verifica fuori campione.");
   W("<div class='kpi'>");
   Kpi("Confronti nella scheda Candele", I2S((long)g_cxNAll), "21 timeframe");
   Kpi("Direzione: robusti", I2S(nr[0]), "su " + I2S(nt[0]) + " con |z| 2 o pi&ugrave;");
   Kpi("Ritmo dell'attivit&agrave;: robusti", I2S(nr[1]), "su " + I2S(nt[1]) + " con |z| 2 o pi&ugrave;");
   Kpi("Precursori di impulsi: robusti", I2S(nr[2]), "su " + I2S(nt[2]) + " con |z| 2 o pi&ugrave;");
   W("</div>");
   R(g_repEdge, "");
   R(g_repEdge, "[Candele su 21 timeframe: " + I2S((long)g_cxNAll) + " confronti; robusti (FDR 5% e stabili): direzione " + I2S(nr[0]) + " su " + I2S(nt[0]) + ", ritmo " + I2S(nr[1]) +
     " su " + I2S(nt[1]) + ", precursori " + I2S(nr[2]) + " su " + I2S(nt[2]) + "]");
   int lim[3] = {12, 6, 8};
   string ttl[3] = {"Direzione", "Ritmo dell'attivita'", "Precursori degli impulsi"};
   for(int ty = 0; ty < 3; ty++)
     {
      int ids[];
      double zz[];
      int m = 0;
      ArrayResize(ids, MathMax(1, g_cxNT));
      ArrayResize(zz, MathMax(1, g_cxNT));
      for(int i = 0; i < g_cxNT; i++)
        {
         int k = g_cxTk[i], t2 = (k == 0 || k == 1 || k == 2 || k == 3 || k == 8) ? 0 : (k == 6 ? 2 : 1);
         if(t2 == ty && g_cxTfd[i] && g_cxTst[i])
           {
            ids[m] = i;
            zz[m] = MathAbs(g_cxTz[i]);
            m++;
           }
        }
      if(m == 0)
        {
         R(g_repEdge, "  " + ttl[ty] + ": nessun confronto robusto.");
         continue;
        }
      int ord[];
      EdOrder(zz, m, ord);
      W("<h3>" + ttl[ty] + " (" + I2S(m) + " robusti, primi " + I2S(MathMin(m, lim[ty])) + ")</h3>");
      THead("Confronto|z");
      R(g_repEdge, "  " + ttl[ty] + " (" + I2S(m) + " robusti):");
      for(int j = 0; j < m && j < lim[ty]; j++)
        {
         int id = ids[ord[j]];
         W("<tr><td style='text-align:left;white-space:normal'>" + g_cxTtx[id] + "</td>" + TDc(ZS(g_cxTz[id]), PCol(g_cxTz[id], 0, 8)) + "</tr>");
         R(g_repEdge, "    z " + ZS(g_cxTz[id]) + " | " + g_cxTtx[id]);
        }
      TEnd();
     }
   SecEnd();
  }
