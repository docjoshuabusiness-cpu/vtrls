//+------------------------------------------------------------------+
//|      SessionOpen_v1.0_H4Anchor_Probe.mq5                          |
//|                                                                    |
//|  EA di RICERCA + ESECUZIONE sui primi minuti dopo l'apertura di   |
//|  una candela H4 (o di un qualsiasi orario ancora configurabile).  |
//|                                                                    |
//|  PROBLEMA CHE RISOLVE                                              |
//|  L'operativita' reale e' su futures MT5 (feed CME): li' la griglia |
//|  H4 e' ancorata all'apertura sessione CME, quindi i confini utili  |
//|  cadono alle 09:00 e 13:00 ET (= 15:00 e 19:00 Roma). Il banco di  |
//|  prova e' FP Markets, dove quegli stessi istanti cadono alle 17:00 |
//|  e 21:00 ora server MA NON sono confini di candela H4 (MT5 taglia  |
//|  le H4 da mezzanotte server: 00/04/08/12/16/20).                   |
//|                                                                    |
//|  Di conseguenza NON si puo' usare iTime(PERIOD_H4,0) per rilevare  |
//|  l'evento: sul banco di prova sparerebbe un'ora prima. L'ancoraggio|
//|  e' quindi su ORARIO ESPLICITO, con due modalita':                  |
//|                                                                    |
//|   - TZ_SERVER   : gli orari in InpAnchorTimes sono letti cosi' come|
//|                   sono, in ora server. Su FP Markets -> "17:00,21:00"|
//|   - TZ_NEWYORK  : gli orari sono espressi in ora di New York (ET)  |
//|                   e convertiti in ora server a runtime, gestendo   |
//|                   SEPARATAMENTE il DST USA e il DST del broker.    |
//|                   Su qualunque piattaforma -> "09:00,13:00".       |
//|                   E' la modalita' che rende i due test confrontabili|
//|                   senza ritoccare gli orari a mano.                |
//|                                                                    |
//|  SIZING CONFRONTABILE CFD vs FUTURE                                |
//|  Su FP il NAS100 e' un CFD (1 pt = 1 unita' indice); su CME il NQ  |
//|  ha tick 0.25 a $5 (MNQ $0.50). Con lotti fissi le due curve equity|
//|  sono incomparabili. Il sizing e' quindi a RISCHIO % dell'equity,  |
//|  derivato da SYMBOL_TRADE_TICK_VALUE / TICK_SIZE, cosi' la curva in|
//|  percentuale e' confrontabile tra strumenti diversi.               |
//|                                                                    |
//|  DUE MODI D'USO                                                    |
//|   1) MODE_PROBE : nessun ordine. Scrive un CSV con la microstruttura|
//|      di ogni evento (spostamento a +1/+2/+3/+5/+10/+15/+30/+60 min,|
//|      MFE/MAE, range di apertura, spread, volume, contesto). Serve  |
//|      a MISURARE prima di decidere cosa tradare.                    |
//|   2) MODE_TRADE : esegue una delle 4 ipotesi di entrata (breakout  |
//|      o fade dell'opening range, continuazione o fade della prima   |
//|      barra M1). Il CSV continua a essere scritto.                  |
//|                                                                    |
//|  ORARI DI CONTROLLO                                                |
//|  InpControlTimes registra eventi "placebo" a orari non speciali.   |
//|  Servono da gruppo di controllo: se le 17:00 non spiccano contro i |
//|  controlli, l'effetto non e' nell'apertura di candela ma nella     |
//|  volatilita' di fondo di quella fascia oraria. Senza controlli si  |
//|  trova "qualcosa" ogni volta. Non vengono mai tradati, solo loggati.|
//|                                                                    |
//|  ATTENZIONE ALL'USO NEL TESTER                                     |
//|  Va attaccato a un grafico M1 e testato in "Ogni tick basato su    |
//|  tick reali" (per spread e percorso intrabar realistici) oppure, se|
//|  serve solo la statistica OHLC, in "1 minuto OHLC". Con modalita'  |
//|  piu' grezze i primi minuti non esistono e il test e' privo di     |
//|  significato.                                                      |
//+------------------------------------------------------------------+
#property copyright "Advanced Quant Systems - SessionOpen Probe v1.0"
#property version   "1.00"
#property strict

//=== MODALITA' ===
input group "═══ MODALITA' ═══"
enum ENUM_RUN_MODE { MODE_PROBE, MODE_TRADE };
input ENUM_RUN_MODE InpRunMode = MODE_PROBE;         // PROBE = solo misura e log CSV | TRADE = esegue anche gli ordini
input int    MagicNumber       = 800300;             // Magic number (distinto dagli altri EA del repo)

//=== ANCORAGGIO TEMPORALE ===
input group "═══ ANCORAGGIO TEMPORALE ═══"
enum ENUM_ANCHOR_TZ { TZ_SERVER, TZ_NEWYORK };
input ENUM_ANCHOR_TZ InpAnchorTZ = TZ_SERVER;        // TZ_SERVER = orari letti in ora server | TZ_NEWYORK = orari in ora ET, convertiti a runtime
input string InpAnchorTimes  = "17:00,21:00";        // Orari evento, separati da virgola. TZ_SERVER su FP: "17:00,21:00" — TZ_NEWYORK ovunque: "09:00,13:00"
input string InpControlTimes = "18:00,22:00";        // Orari di CONTROLLO (solo log, mai tradati). Vuoto per disattivarli
input int    InpServerGMTOffsetWinter = 2;           // Offset GMT del server in ORA SOLARE (FP Markets = 2). Usato solo in TZ_NEWYORK
input bool   InpServerUsesEUDST = true;              // true = il server segue il DST europeo (FP Markets) | false = offset fisso tutto l'anno
input int    InpAnchorToleranceMin = 3;              // Se manca la barra M1 esatta (festivi/illiquidita'), accetta la prima barra entro N minuti

//=== FINESTRA DI MISURA ===
input group "═══ FINESTRA DI MISURA ═══"
input int    InpTrackMinutes = 60;                   // Per quanti minuti seguire ogni evento nel CSV

//=== LOGICA DI ENTRATA (solo MODE_TRADE) ═══
input group "═══ LOGICA DI ENTRATA ═══"
enum ENUM_ENTRY_MODE
{
    ENTRY_OR_BREAKOUT,      // Rottura dell'opening range dei primi K minuti
    ENTRY_OR_FADE,          // Fade: si vende la rottura alta, si compra la rottura bassa
    ENTRY_FIRSTBAR_CONT,    // Continuazione nella direzione della prima barra M1
    ENTRY_FIRSTBAR_FADE     // Fade della direzione della prima barra M1
};
input ENUM_ENTRY_MODE InpEntryMode = ENTRY_OR_BREAKOUT;  // Ipotesi di entrata da testare
input int    InpORMinutes     = 3;                   // Durata dell'opening range in minuti (K)
input int    InpEntryWindowMin= 30;                  // Entro quanti minuti dall'evento e' ancora lecito entrare
input bool   InpOnePerEvent   = true;                // Massimo una posizione per evento

//=== USCITE ===
input group "═══ USCITE ═══"
enum ENUM_STOP_MODE { STOP_FIXED_POINTS, STOP_ATR, STOP_OR_MULTIPLE };
input ENUM_STOP_MODE InpStopMode = STOP_OR_MULTIPLE; // Base per SL/TP: punti fissi | ATR | multiplo del range di apertura
input double InpSLValue       = 1.0;                 // SL: punti se FIXED, moltiplicatore se ATR/OR
input double InpTPValue       = 2.0;                 // TP: punti se FIXED, moltiplicatore se ATR/OR
input int    InpATRPeriod     = 14;                  // Periodo ATR (su M1) se InpStopMode = STOP_ATR
input int    InpTimeStopMin   = 60;                  // Chiusura forzata dopo N minuti dall'entrata (0 = disattivo)

//=== RISCHIO ===
input group "═══ RISCHIO ═══"
input double InpRiskPercent   = 0.5;                 // Rischio per trade in % dell'equity. Rende confrontabili CFD e future
input double InpMaxLot        = 10.0;                // Tetto di sicurezza al volume calcolato
input int    InpMaxSpreadPts  = 0;                   // Salta l'evento se lo spread supera N punti (0 = nessun filtro). CRITICO in apertura

//=== LOG ===
input group "═══ LOG ═══"
input bool   InpWriteCSV      = true;                // Scrive il CSV di ricerca
input string InpCSVPrefix     = "SessionOpenProbe";  // Prefisso del file CSV (cartella Common\Files)

//+------------------------------------------------------------------+
//| Checkpoint di misura, in minuti dall'apertura dell'evento         |
//+------------------------------------------------------------------+
#define CP_COUNT 8
const int g_Checkpoints[CP_COUNT] = {1, 2, 3, 5, 10, 15, 30, 60};

//+------------------------------------------------------------------+
//| Stato di un evento in corso                                       |
//+------------------------------------------------------------------+
enum ENUM_EV_STATE { EV_FREE, EV_TRACKING, EV_CLOSED };

struct SEvent
{
    ENUM_EV_STATE state;
    bool     is_control;        // evento di controllo: si misura ma non si trada mai
    string   label;             // etichetta oraria, es. "17:00"
    datetime t0;                // ora della barra M1 di apertura evento
    double   open;              // prezzo di apertura evento
    int      minutes_seen;      // barre M1 osservate dall'apertura

    // microstruttura
    double   hi;                // massimo dall'apertura
    double   lo;                // minimo dall'apertura
    double   cp_close[CP_COUNT];// prezzo di chiusura a ogni checkpoint (0 = non ancora raggiunto)
    double   cp_mfe[CP_COUNT];  // massima escursione favorevole al rialzo (hi-open) al checkpoint
    double   cp_mae[CP_COUNT];  // massima escursione al ribasso (lo-open) al checkpoint
    long     volume;            // volume tick cumulato
    int      spread_open;       // spread in punti alla barra di apertura

    // contesto misurato a t0
    double   atr0;              // ATR(M1) al momento dell'apertura
    double   prev_h4_open, prev_h4_close, prev_h4_high, prev_h4_low;

    // opening range
    double   or_hi, or_lo;
    bool     or_done;

    // esecuzione
    bool     traded;
    int      dir;               // +1 long, -1 short, 0 nessuno
    double   entry_price;
    datetime entry_time;
};

#define MAX_EVENTS 8
SEvent   g_Events[MAX_EVENTS];

// orari ancora e controllo, parsati
struct SAnchor { int hh; int mm; string label; bool is_control; };
#define MAX_ANCHORS 16
SAnchor  g_Anchors[MAX_ANCHORS];
int      g_AnchorCount = 0;

datetime g_LastM1Bar   = 0;
datetime g_LastFired[MAX_ANCHORS];   // ultimo giorno in cui ogni ancora ha sparato (evita doppi scatti)
int      g_ATRHandle   = INVALID_HANDLE;
int      g_CSVHandle   = INVALID_HANDLE;
double   g_TickSize = 0, g_TickValue = 0, g_Point = 0;
int      g_Digits = 0;

//+------------------------------------------------------------------+
//| Prototipi                                                         |
//+------------------------------------------------------------------+
void   OpenCSV();
void   WriteEventRow(SEvent &e);
void   OpenEvent(int anchor_idx, datetime bar_t);
void   UpdateEvents(datetime bar_t);
void   DetectAnchors(datetime bar_t);
void   RecordCheckpoints(SEvent &e, double close_px);
void   TryEntry(SEvent &e, double c);
bool   OpenPosition(SEvent &e, int dir);
double ReadATR();
double StopDistance(SEvent &e);
double TakeDistance(SEvent &e);
double CalcLots(double stop_dist);
void   ManageTimeStop();
void   ClosePosition(ulong ticket);
ENUM_ORDER_TYPE_FILLING PickFilling();

//+------------------------------------------------------------------+
//| DST — n-esima domenica del mese (n=1..5), a mezzanotte            |
//+------------------------------------------------------------------+
datetime NthSundayOfMonth(int year, int month, int n)
{
    MqlDateTime dt;
    dt.year = year; dt.mon = month; dt.day = 1;
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    datetime t = StructToTime(dt);
    TimeToStruct(t, dt);
    int first_sunday = 1 + ((7 - dt.day_of_week) % 7);
    dt.year = year; dt.mon = month; dt.day = first_sunday + 7 * (n - 1);
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    return StructToTime(dt);
}

datetime LastSundayOfMonth(int year, int month)
{
    // si parte dal 1 del mese successivo e si torna indietro alla domenica
    MqlDateTime dt;
    int y = (month == 12) ? year + 1 : year;
    int m = (month == 12) ? 1 : month + 1;
    dt.year = y; dt.mon = m; dt.day = 1;
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    datetime t = StructToTime(dt);
    TimeToStruct(t, dt);
    int back = (dt.day_of_week == 0) ? 7 : dt.day_of_week;
    return t - back * 86400;
}

//| DST europeo: ultima domenica di marzo -> ultima domenica di ottobre
bool IsEUDST(datetime t)
{
    MqlDateTime dt; TimeToStruct(t, dt);
    return (t >= LastSundayOfMonth(dt.year, 3) && t < LastSundayOfMonth(dt.year, 10));
}

//| DST USA: 2a domenica di marzo -> 1a domenica di novembre
bool IsUSDST(datetime t)
{
    MqlDateTime dt; TimeToStruct(t, dt);
    return (t >= NthSundayOfMonth(dt.year, 3, 2) && t < NthSundayOfMonth(dt.year, 11, 1));
}

//+------------------------------------------------------------------+
//| Converte un istante SERVER nel fuso in cui sono espresse le ancore|
//| In TZ_SERVER e' l'identita'. In TZ_NEWYORK torna l'ora di New York|
//| calcolando separatamente il DST del broker e quello USA: i due    |
//| cambi d'ora NON coincidono (marzo/novembre divergono per settimane)|
//+------------------------------------------------------------------+
datetime ToAnchorTZ(datetime server_t)
{
    if(InpAnchorTZ == TZ_SERVER) return server_t;

    int srv_off = InpServerGMTOffsetWinter + ((InpServerUsesEUDST && IsEUDST(server_t)) ? 1 : 0);
    datetime utc = server_t - (datetime)(srv_off * 3600);
    int et_off = IsUSDST(utc) ? -4 : -5;
    return utc + (datetime)(et_off * 3600);
}

//+------------------------------------------------------------------+
//| Parsing della lista "HH:MM,HH:MM,..."                             |
//+------------------------------------------------------------------+
void ParseAnchorList(string csv, bool is_control)
{
    string parts[];
    int n = StringSplit(csv, ',', parts);
    for(int i = 0; i < n; i++)
    {
        string s = parts[i];
        StringTrimLeft(s); StringTrimRight(s);
        if(StringLen(s) == 0) continue;

        string hm[];
        if(StringSplit(s, ':', hm) != 2) { Print("Orario non valido, ignorato: ", s); continue; }
        int hh = (int)StringToInteger(hm[0]);
        int mm = (int)StringToInteger(hm[1]);
        if(hh < 0 || hh > 23 || mm < 0 || mm > 59) { Print("Orario fuori range, ignorato: ", s); continue; }
        if(g_AnchorCount >= MAX_ANCHORS) { Print("Troppe ancore, ignorata: ", s); continue; }

        g_Anchors[g_AnchorCount].hh = hh;
        g_Anchors[g_AnchorCount].mm = mm;
        g_Anchors[g_AnchorCount].label = StringFormat("%02d:%02d", hh, mm);
        g_Anchors[g_AnchorCount].is_control = is_control;
        g_AnchorCount++;
    }
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
    g_TickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    g_TickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    g_Point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    g_Digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

    if(g_TickSize <= 0 || g_TickValue <= 0)
    {
        Print("ERRORE: tick size/value non disponibili per ", _Symbol, ". Il sizing a rischio %% non e' calcolabile.");
        return INIT_FAILED;
    }

    g_AnchorCount = 0;
    ParseAnchorList(InpAnchorTimes,  false);
    ParseAnchorList(InpControlTimes, true);
    if(g_AnchorCount == 0) { Print("ERRORE: nessun orario ancora valido."); return INIT_FAILED; }

    for(int i = 0; i < MAX_ANCHORS; i++) g_LastFired[i] = 0;
    for(int i = 0; i < MAX_EVENTS; i++)  g_Events[i].state = EV_FREE;

    if(InpStopMode == STOP_ATR)
    {
        g_ATRHandle = iATR(_Symbol, PERIOD_M1, InpATRPeriod);
        if(g_ATRHandle == INVALID_HANDLE) { Print("ERRORE: creazione handle ATR fallita."); return INIT_FAILED; }
    }
    else
    {
        // serve comunque come variabile di contesto nel CSV
        g_ATRHandle = iATR(_Symbol, PERIOD_M1, InpATRPeriod);
    }

    // --- Coerenza della configurazione ---------------------------------
    // Meglio urlare in init che scoprire dopo 5 anni di backtest che il test
    // misurava un'altra cosa. Nessuna di queste combinazioni da' errore a
    // runtime: danno risultati silenziosamente sbagliati, che e' peggio.
    if(InpRunMode == MODE_TRADE)
    {
        bool firstbar = (InpEntryMode == ENTRY_FIRSTBAR_CONT || InpEntryMode == ENTRY_FIRSTBAR_FADE);

        if(firstbar && InpStopMode == STOP_OR_MULTIPLE && InpORMinutes > 2)
            Print("CONFIG: le entrate FIRSTBAR scattano al minuto 2, ma con InpORMinutes=",
                  InpORMinutes, " l'opening range non e' ancora completo: lo stop verrebbe " +
                  "dimensionato su un range parziale. Usa InpORMinutes<=2 oppure STOP_ATR/STOP_FIXED_POINTS.");

        if(!firstbar && InpEntryWindowMin <= InpORMinutes)
            Print("CONFIG: InpEntryWindowMin (", InpEntryWindowMin, ") <= InpORMinutes (", InpORMinutes,
                  "): non si trada dentro il range in formazione, quindi non entrerebbe MAI. " +
                  "Alza InpEntryWindowMin.");

        if(InpMaxSpreadPts == 0)
            Print("CONFIG: filtro spread disattivato. Nei primi minuti dopo l'apertura lo spread " +
                  "e' il costo dominante: senza filtro il backtest sara' ottimista.");
    }

    if(InpTrackMinutes < g_Checkpoints[CP_COUNT - 1])
        Print("CONFIG: InpTrackMinutes=", InpTrackMinutes, " < ultimo checkpoint (",
              g_Checkpoints[CP_COUNT - 1], " min): quelle colonne resteranno vuote nel CSV.");

    if(InpWriteCSV) OpenCSV();

    PrintFormat("SessionOpen Probe v1.0 | %s | modo=%s | TZ=%s | ancore=%s | controlli=%s",
                _Symbol,
                (InpRunMode == MODE_PROBE ? "PROBE" : "TRADE"),
                (InpAnchorTZ == TZ_SERVER ? "SERVER" : "NEW_YORK"),
                InpAnchorTimes, InpControlTimes);
    PrintFormat("tick_size=%.5f tick_value=%.5f point=%.5f digits=%d",
                g_TickSize, g_TickValue, g_Point, g_Digits);
    if(InpAnchorTZ == TZ_NEWYORK)
        PrintFormat("Offset server assunto: GMT+%d (solare), DST EU=%s | DST attivo ora: server=%s USA=%s",
                    InpServerGMTOffsetWinter, InpServerUsesEUDST ? "SI" : "NO",
                    IsEUDST(TimeCurrent()) ? "SI" : "NO", IsUSDST(TimeCurrent()) ? "SI" : "NO");

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    if(g_CSVHandle != INVALID_HANDLE) { FileClose(g_CSVHandle); g_CSVHandle = INVALID_HANDLE; }
    if(g_ATRHandle != INVALID_HANDLE) IndicatorRelease(g_ATRHandle);
}

//+------------------------------------------------------------------+
//| CSV — una riga per evento. Cartella Common\Files cosi' il file e' |
//| ritrovabile anche quando gira negli agent del tester.             |
//+------------------------------------------------------------------+
void OpenCSV()
{
    string fname = StringFormat("%s_%s_%s.csv", InpCSVPrefix, _Symbol,
                                (InpRunMode == MODE_PROBE ? "probe" : "trade"));
    g_CSVHandle = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
    if(g_CSVHandle == INVALID_HANDLE)
    {
        PrintFormat("ATTENZIONE: apertura CSV fallita (%d). Log disattivato.", GetLastError());
        return;
    }

    string hdr = "t0;anchor;is_control;dow;server_hour;open;spread_open;atr0;" +
                 "prev_h4_open;prev_h4_high;prev_h4_low;prev_h4_close;" +
                 "or_hi;or_lo;or_range;vol_tot;hi;lo;range_tot";
    for(int c = 0; c < CP_COUNT; c++)
        hdr += StringFormat(";ret_%dm_bps;mfe_%dm_bps;mae_%dm_bps", g_Checkpoints[c], g_Checkpoints[c], g_Checkpoints[c]);
    hdr += ";traded;dir;entry_price;entry_time";
    FileWrite(g_CSVHandle, hdr);
    PrintFormat("CSV di ricerca: <Common>\\Files\\%s", fname);
}

//| Rendimento in punti base: rende confrontabili NQ a 7.000 e a 25.000
double ToBps(double delta, double base) { return (base > 0.0) ? (delta / base) * 10000.0 : 0.0; }

void WriteEventRow(SEvent &e)
{
    if(g_CSVHandle == INVALID_HANDLE) return;

    MqlDateTime dt; TimeToStruct(e.t0, dt);

    string row = TimeToString(e.t0, TIME_DATE | TIME_MINUTES) + ";" + e.label + ";" +
                 IntegerToString(e.is_control ? 1 : 0) + ";" +
                 IntegerToString(dt.day_of_week) + ";" +
                 IntegerToString(dt.hour) + ";" +
                 DoubleToString(e.open, g_Digits) + ";" +
                 IntegerToString(e.spread_open) + ";" +
                 DoubleToString(e.atr0, g_Digits) + ";" +
                 DoubleToString(e.prev_h4_open,  g_Digits) + ";" +
                 DoubleToString(e.prev_h4_high,  g_Digits) + ";" +
                 DoubleToString(e.prev_h4_low,   g_Digits) + ";" +
                 DoubleToString(e.prev_h4_close, g_Digits) + ";" +
                 DoubleToString(e.or_hi, g_Digits) + ";" +
                 DoubleToString(e.or_lo, g_Digits) + ";" +
                 DoubleToString(e.or_hi - e.or_lo, g_Digits) + ";" +
                 IntegerToString(e.volume) + ";" +
                 DoubleToString(e.hi, g_Digits) + ";" +
                 DoubleToString(e.lo, g_Digits) + ";" +
                 DoubleToString(e.hi - e.lo, g_Digits);

    for(int c = 0; c < CP_COUNT; c++)
    {
        if(e.cp_close[c] > 0.0)
            row += ";" + DoubleToString(ToBps(e.cp_close[c] - e.open, e.open), 2) +
                   ";" + DoubleToString(ToBps(e.cp_mfe[c],            e.open), 2) +
                   ";" + DoubleToString(ToBps(e.cp_mae[c],            e.open), 2);
        else
            row += ";;;";   // checkpoint non raggiunto: celle VUOTE, non zero.
                            // Uno zero verrebbe letto come "nessun movimento" e
                            // sporcherebbe le medie in analisi.
    }

    row += ";" + IntegerToString(e.traded ? 1 : 0) +
           ";" + IntegerToString(e.dir) +
           ";" + DoubleToString(e.entry_price, g_Digits) +
           ";" + (e.entry_time > 0 ? TimeToString(e.entry_time, TIME_DATE | TIME_MINUTES) : "");

    FileWrite(g_CSVHandle, row);
}

//+------------------------------------------------------------------+
//| OnTick — il lavoro pesante gira una volta per barra M1.           |
//| La gestione delle posizioni resta a ogni tick, perche' il time    |
//| stop deve poter chiudere anche a barra aperta.                    |
//+------------------------------------------------------------------+
void OnTick()
{
    if(InpRunMode == MODE_TRADE && InpTimeStopMin > 0) ManageTimeStop();

    datetime bar_t = iTime(_Symbol, PERIOD_M1, 0);
    if(bar_t == 0 || bar_t == g_LastM1Bar) return;
    g_LastM1Bar = bar_t;

    // si lavora sulla barra M1 appena CHIUSA (shift 1): OHLC definitivo
    datetime closed_t = iTime(_Symbol, PERIOD_M1, 1);
    if(closed_t == 0) return;

    UpdateEvents(closed_t);
    DetectAnchors(closed_t);
}

//+------------------------------------------------------------------+
//| Rilevamento ancore sulla barra M1 chiusa                          |
//+------------------------------------------------------------------+
void DetectAnchors(datetime bar_t)
{
    datetime local_t = ToAnchorTZ(bar_t);
    MqlDateTime lt; TimeToStruct(local_t, lt);

    for(int a = 0; a < g_AnchorCount; a++)
    {
        int minutes_now    = lt.hour * 60 + lt.min;
        int minutes_anchor = g_Anchors[a].hh * 60 + g_Anchors[a].mm;
        int delta = minutes_now - minutes_anchor;

        // tolleranza: la barra M1 esatta puo' mancare (festivi, illiquidita', break di sessione)
        if(delta < 0 || delta > InpAnchorToleranceMin) continue;

        // una sola accensione per giorno e per ancora
        datetime day = local_t - (datetime)(minutes_now * 60);
        if(g_LastFired[a] == day) continue;
        g_LastFired[a] = day;

        OpenEvent(a, bar_t);
    }
}

//+------------------------------------------------------------------+
//| Apertura di un nuovo evento                                       |
//+------------------------------------------------------------------+
void OpenEvent(int anchor_idx, datetime bar_t)
{
    int slot = -1;
    for(int i = 0; i < MAX_EVENTS; i++)
        if(g_Events[i].state == EV_FREE) { slot = i; break; }
    if(slot < 0) { Print("ATTENZIONE: nessuno slot evento libero, evento saltato a ", TimeToString(bar_t)); return; }

    double o = iOpen(_Symbol, PERIOD_M1, 1);
    double h = iHigh(_Symbol, PERIOD_M1, 1);
    double l = iLow(_Symbol, PERIOD_M1, 1);
    double c = iClose(_Symbol, PERIOD_M1, 1);
    if(o <= 0.0) return;

    SEvent e;
    e.state        = EV_TRACKING;
    e.is_control   = g_Anchors[anchor_idx].is_control;
    e.label        = g_Anchors[anchor_idx].label;
    e.t0           = bar_t;
    e.open         = o;
    e.minutes_seen = 1;
    e.hi           = h;
    e.lo           = l;
    e.volume       = iTickVolume(_Symbol, PERIOD_M1, 1);
    e.spread_open  = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    e.atr0         = ReadATR();
    e.or_hi        = h;
    e.or_lo        = l;
    e.or_done      = (InpORMinutes <= 1);
    e.traded       = false;
    e.dir          = 0;
    e.entry_price  = 0.0;
    e.entry_time   = 0;

    e.prev_h4_open  = iOpen(_Symbol,  PERIOD_H4, 1);
    e.prev_h4_high  = iHigh(_Symbol,  PERIOD_H4, 1);
    e.prev_h4_low   = iLow(_Symbol,   PERIOD_H4, 1);
    e.prev_h4_close = iClose(_Symbol, PERIOD_H4, 1);

    for(int c2 = 0; c2 < CP_COUNT; c2++) { e.cp_close[c2] = 0.0; e.cp_mfe[c2] = 0.0; e.cp_mae[c2] = 0.0; }

    // la prima barra e' gia' un checkpoint se g_Checkpoints[0] == 1
    RecordCheckpoints(e, c);

    g_Events[slot] = e;
}

double ReadATR()
{
    if(g_ATRHandle == INVALID_HANDLE) return 0.0;
    double buf[];
    if(CopyBuffer(g_ATRHandle, 0, 1, 1, buf) != 1) return 0.0;
    return buf[0];
}

//+------------------------------------------------------------------+
//| Aggiornamento degli eventi in corso sulla barra M1 chiusa         |
//+------------------------------------------------------------------+
void UpdateEvents(datetime bar_t)
{
    double h = iHigh(_Symbol,  PERIOD_M1, 1);
    double l = iLow(_Symbol,   PERIOD_M1, 1);
    double c = iClose(_Symbol, PERIOD_M1, 1);
    long   v = iTickVolume(_Symbol, PERIOD_M1, 1);

    for(int i = 0; i < MAX_EVENTS; i++)
    {
        if(g_Events[i].state != EV_TRACKING) continue;
        if(bar_t <= g_Events[i].t0) continue;   // e' la barra di apertura, gia' contata

        g_Events[i].minutes_seen++;
        if(h > g_Events[i].hi) g_Events[i].hi = h;
        if(l < g_Events[i].lo) g_Events[i].lo = l;
        g_Events[i].volume += v;

        // costruzione dell'opening range
        if(!g_Events[i].or_done)
        {
            if(h > g_Events[i].or_hi) g_Events[i].or_hi = h;
            if(l < g_Events[i].or_lo) g_Events[i].or_lo = l;
            if(g_Events[i].minutes_seen >= InpORMinutes) g_Events[i].or_done = true;
        }

        RecordCheckpoints(g_Events[i], c);

        if(InpRunMode == MODE_TRADE && !g_Events[i].is_control)
            TryEntry(g_Events[i], c);

        if(g_Events[i].minutes_seen >= InpTrackMinutes)
        {
            g_Events[i].state = EV_CLOSED;
            WriteEventRow(g_Events[i]);
            g_Events[i].state = EV_FREE;
        }
    }
}

void RecordCheckpoints(SEvent &e, double close_px)
{
    for(int c = 0; c < CP_COUNT; c++)
    {
        if(g_Checkpoints[c] != e.minutes_seen) continue;
        e.cp_close[c] = close_px;
        e.cp_mfe[c]   = e.hi - e.open;   // positivo
        e.cp_mae[c]   = e.lo - e.open;   // negativo
    }
}

//+------------------------------------------------------------------+
//| Logica di entrata                                                 |
//+------------------------------------------------------------------+
void TryEntry(SEvent &e, double c)
{
    if(e.traded && InpOnePerEvent) return;
    if(e.minutes_seen > InpEntryWindowMin) return;

    if(InpMaxSpreadPts > 0)
    {
        int spr = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        if(spr > InpMaxSpreadPts) return;   // in apertura lo spread esplode: qui si perde piu' che altrove
    }

    int dir = 0;

    switch(InpEntryMode)
    {
        case ENTRY_OR_BREAKOUT:
        case ENTRY_OR_FADE:
        {
            if(!e.or_done) return;
            if(e.minutes_seen <= InpORMinutes) return;   // non si trada dentro il range che si sta ancora formando
            if(c > e.or_hi)      dir = +1;
            else if(c < e.or_lo) dir = -1;
            if(InpEntryMode == ENTRY_OR_FADE) dir = -dir;
            break;
        }
        case ENTRY_FIRSTBAR_CONT:
        case ENTRY_FIRSTBAR_FADE:
        {
            if(e.minutes_seen != 2) return;              // si entra sulla barra successiva alla prima
            double first_close = e.cp_close[0];          // chiusura del minuto 1
            if(first_close <= 0.0) return;
            if(first_close > e.open)      dir = +1;
            else if(first_close < e.open) dir = -1;
            if(InpEntryMode == ENTRY_FIRSTBAR_FADE) dir = -dir;
            break;
        }
    }

    if(dir == 0) return;
    if(OpenPosition(e, dir)) { e.traded = true; e.dir = dir; }
}

//+------------------------------------------------------------------+
//| Distanza di stop in prezzo, secondo la modalita' scelta           |
//+------------------------------------------------------------------+
double StopDistance(SEvent &e)
{
    switch(InpStopMode)
    {
        case STOP_FIXED_POINTS:  return InpSLValue * g_Point;
        case STOP_ATR:           return InpSLValue * e.atr0;
        case STOP_OR_MULTIPLE:   return InpSLValue * (e.or_hi - e.or_lo);
    }
    return 0.0;
}

double TakeDistance(SEvent &e)
{
    switch(InpStopMode)
    {
        case STOP_FIXED_POINTS:  return InpTPValue * g_Point;
        case STOP_ATR:           return InpTPValue * e.atr0;
        case STOP_OR_MULTIPLE:   return InpTPValue * (e.or_hi - e.or_lo);
    }
    return 0.0;
}

//+------------------------------------------------------------------+
//| Sizing a rischio % — derivato da tick value/size, non da lotti    |
//| fissi. E' cio' che rende confrontabile un test su CFD NAS100 con  |
//| l'operativita' reale su future NQ/MNQ.                            |
//+------------------------------------------------------------------+
double CalcLots(double stop_dist)
{
    if(stop_dist <= 0.0) return 0.0;

    double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
    double risk_money = equity * InpRiskPercent / 100.0;

    double ticks = stop_dist / g_TickSize;
    double loss_per_lot = ticks * g_TickValue;
    if(loss_per_lot <= 0.0) return 0.0;

    double lots = risk_money / loss_per_lot;

    double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if(lot_step > 0.0) lots = MathFloor(lots / lot_step) * lot_step;
    lots = MathMin(lots, MathMin(max_lot, InpMaxLot));

    // se il rischio richiesto non copre nemmeno il lotto minimo, NON si arrotonda in su:
    // si salta il trade. Arrotondare vorrebbe dire rischiare piu' del dichiarato.
    if(lots < min_lot) return 0.0;

    return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Invio ordine a mercato                                            |
//+------------------------------------------------------------------+
bool OpenPosition(SEvent &e, int dir)
{
    double sl_dist = StopDistance(e);
    double tp_dist = TakeDistance(e);
    if(sl_dist <= 0.0) return false;

    double lots = CalcLots(sl_dist);
    if(lots <= 0.0) return false;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(ask <= 0.0 || bid <= 0.0) return false;

    double price = (dir > 0) ? ask : bid;
    double sl    = (dir > 0) ? price - sl_dist : price + sl_dist;
    double tp    = (dir > 0) ? price + tp_dist : price - tp_dist;

    // rispetto della distanza minima imposta dal broker
    long   stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double min_dist    = stops_level * g_Point;
    if(min_dist > 0.0)
    {
        if(MathAbs(price - sl) < min_dist) sl = (dir > 0) ? price - min_dist : price + min_dist;
        if(tp_dist > 0.0 && MathAbs(tp - price) < min_dist) tp = (dir > 0) ? price + min_dist : price - min_dist;
    }

    MqlTradeRequest  req;  ZeroMemory(req);
    MqlTradeResult   res;  ZeroMemory(res);

    req.action       = TRADE_ACTION_DEAL;
    req.symbol       = _Symbol;
    req.volume       = lots;
    req.type         = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    req.price        = price;
    req.sl           = NormalizeDouble(sl, g_Digits);
    req.tp           = (tp_dist > 0.0) ? NormalizeDouble(tp, g_Digits) : 0.0;
    req.deviation    = 20;
    req.magic        = MagicNumber;
    req.comment      = "SOP " + e.label;
    req.type_filling = PickFilling();

    if(!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
    {
        PrintFormat("OrderSend fallito: retcode=%d comment=%s", res.retcode, res.comment);
        return false;
    }

    e.entry_price = res.price > 0.0 ? res.price : price;
    e.entry_time  = TimeCurrent();
    return true;
}

//| Filling mode compatibile: i future e i CFD non espongono gli stessi
ENUM_ORDER_TYPE_FILLING PickFilling()
{
    long mode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if((mode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
    if((mode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
    return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Time stop — chiude le posizioni piu' vecchie di N minuti          |
//+------------------------------------------------------------------+
void ManageTimeStop()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

        datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
        if((TimeCurrent() - opened) < (datetime)(InpTimeStopMin * 60)) continue;

        ClosePosition(ticket);
    }
}

void ClosePosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;

    long   ptype  = PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);

    MqlTradeRequest  req;  ZeroMemory(req);
    MqlTradeResult   res;  ZeroMemory(res);

    req.action       = TRADE_ACTION_DEAL;
    req.symbol       = _Symbol;
    req.position     = ticket;
    req.volume       = volume;
    req.type         = (ptype == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    req.price        = (ptype == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                    : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    req.deviation    = 20;
    req.magic        = MagicNumber;
    req.comment      = "SOP timestop";
    req.type_filling = PickFilling();

    if(!OrderSend(req, res) || (res.retcode != TRADE_RETCODE_DONE && res.retcode != TRADE_RETCODE_PLACED))
        PrintFormat("Chiusura time-stop fallita: retcode=%d comment=%s", res.retcode, res.comment);
}
//+------------------------------------------------------------------+
