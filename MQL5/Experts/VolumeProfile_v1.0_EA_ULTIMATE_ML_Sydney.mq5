//+------------------------------------------------------------------+
//|      VolumeProfile_v1.0_EA_ULTIMATE_ML_Sydney.mq5                 |
//|  Expert Advisor autonomo — stessa logica dell'indicatore          |
//|  VolumeProfile_v9.2_ULTIMATE_ML_Sydney (Volume Profile per        |
//|  sessioni FP Markets con auto-DST, ensemble ML a 3 modelli,       |
//|  filtro di direzione Hull MA), riscritta interamente dentro       |
//|  l'EA — NESSUNA chiamata a iCustom, nessuna dipendenza esterna.   |
//|                                                                    |
//|  Differenze volute rispetto all'indicatore:                       |
//|  - Esegue ordini reali (market) nella direzione del segnale       |
//|    approvato dall'ensemble ML, invece di disegnare una freccia.   |
//|  - L'esito usato per allenare l'ensemble ML e' quello REALE del   |
//|    trade (posizione chiusa via SL/TP), non una scansione forward  |
//|    nella storia — elimina in radice la classe di bug di           |
//|    indicizzazione trovata nell'indicatore.                        |
//|  - Tutte le funzioni feature/segnale usano SHIFT diretto           |
//|    (iOpen/iHigh/iLow/iClose, 0=barra corrente) invece di array     |
//|    misti series/non-series.                                       |
//|                                                                    |
//|  v1.01: fix deadlock training ML — ogni segnale tecnicamente       |
//|  valido viene registrato per il training (record "shadow" con      |
//|  esito simulato via ATR), indipendentemente dall'approvazione ML.  |
//|  Se registrasse solo i segnali approvati, un ensemble che parte    |
//|  sotto soglia non riceverebbe mai dati per allenarsi e resterebbe  |
//|  bloccato a 0 trade per sempre. I segnali REALMENTE eseguiti        |
//|  vengono "promossi" da shadow a reali e il loro esito arriva dal   |
//|  trade vero (OnTradeTransaction), non dalla simulazione.           |
//|                                                                    |
//|  v1.02: aggiunto il toggle InpUseATRStops per scegliere tra SL/TP/ |
//|  trailing basati su ATR (adattivi) o su punti fissi (InpSLPoints/  |
//|  InpTPPoints/InpTrailing*Points). La stessa modalita' viene usata  |
//|  anche dalla simulazione ML dei segnali "shadow" (UpdateShadowOutcomes)|
//|  cosi' l'etichetta di training resta coerente con l'esecuzione reale.|
//+------------------------------------------------------------------+
#property copyright "Advanced Quant Systems - EA v1.02"
#property version   "1.02"
#property strict

//=== PROFILE MODE ===
input group "═══ 📊 PROFILE MODE ═══"
enum ENUM_PROFILE_MODE { MODE_DAILY, MODE_WEEKLY, MODE_MONTHLY, MODE_SESSIONS };
input ENUM_PROFILE_MODE InpProfileMode = MODE_SESSIONS; // Tipo di profilo: Daily/Weekly/Monthly/Sessions (Sydney+Asian+London+NY)

//=== VOLUME PROFILE ===
input group "═══ 📈 VOLUME PROFILE ═══"
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT; // Timeframe usato per costruire il profilo volumi
input int    InpPriceLevels = 100;          // Numero di livelli di prezzo del profilo, 50-200
input int    InpHistoryPeriods = 20;        // Numero di profili storici da calcolare
input double InpValueAreaPercent = 70.0;    // % di volume incluso nella Value Area (standard 70%)
input bool   InpUseRealVolume = true;       // Usa volume reale se il broker lo fornisce, altrimenti tick volume

//=== SESSION TIMES (FP Markets, ora SERVER — base ora SOLARE/inverno UTC+2) ===
input group "═══ 🕐 SESSIONS — FP Markets server time (base ora solare UTC+2) ═══"
input bool   InpAutoDST      = true;      // Sposta automaticamente +1h le sessioni durante l'ora legale EU (fine mar-fine ott)
input string InpSydneyStart  = "00:00";
input string InpSydneyEnd    = "09:00";
input string InpAsianStart   = "02:00";
input string InpAsianEnd     = "11:00";
input string InpLondonStart  = "10:00";
input string InpLondonEnd    = "19:00";
input string InpNewYorkStart = "15:00";
input string InpNewYorkEnd   = "00:00";   // attraversa la mezzanotte

//=== SIGNAL LOGIC ===
input group "═══ 🎯 SIGNALS ═══"
input bool   InpStrictMode = true;           // Richiede prezzo sotto/sopra il POC oltre alla vicinanza a VAL/VAH
input double InpVADistance = 15.0;           // Distanza massima (pip adattivi) dal livello VAL/VAH per considerare un tocco
input int    InpMinTouchBars = 3;            // Numero minimo di tocchi richiesti prima di validare il segnale
input bool   InpRequireRejection = true;     // Richiede una candela di rigetto (wick)
input double InpMinWickRatio = 0.3;          // Rapporto minimo wick/range della candela di rigetto (0-1)
input bool   InpOneSignalPerSession = true;  // Un solo trade long e uno short per sessione/profilo

//=== HULL MA DIRECTION FILTER ===
input group "═══ 🌊 HULL MA DIRECTION FILTER ═══"
input bool InpUseHullFilter = true;     // Approva LONG solo se il prezzo e' sopra la Hull MA, SHORT solo se sotto (embedded, no iCustom)
input int  InpHullPeriod    = 20;       // Periodo della Hull MA (minimo 2)

//=== ADAPTIVE ===
input group "═══ 🧠 ADAPTIVE ═══"
input bool InpAutoAdaptDistance = true;    // Adatta automaticamente la distanza di segnale in base all'ATR corrente

//=== ULTIMATE ML SYSTEM ===
input group "═══ 🤖 ULTIMATE ML ═══"
input bool   InpEnableML = true;             // Abilita il filtro ML sui segnali
input double InpMLThreshold = 65.0;          // Soglia minima probabilita' ensemble (%) per approvare un segnale
input int    InpMLTrainingPeriod = 500;      // Numero massimo di segnali storici mantenuti per il training
input bool   InpMLAdaptive = true;           // Riallena i modelli automaticamente ogni N segnali chiusi
input int    InpMLRetrainInterval = 100;     // Ogni quanti segnali chiusi forzare il retraining
input bool   InpEnableEnsemble = true;       // Usa i 3 modelli in votazione invece di uno solo
input bool   InpEnableMultiSymbol = true;    // Traccia accuratezza storica per simbolo (cross-asset learning)
input bool   InpAutoExportWeights = true;    // Esporta/salva automaticamente i pesi ML su file
input int    InpExportInterval = 500;        // Ogni quanti segnali esportare i pesi

//=== RISK MANAGEMENT ===
input group "═══ 💰 RISK MANAGEMENT ═══"
input double LotSize = 0.1;                  // Lotti fissi (usati se UseFixedRisk = false)
input bool   UseFixedRisk = false;           // Se true calcola i lotti in base a RiskPercent
input double RiskPercent = 1.0;              // % di equity rischiata per trade (se UseFixedRisk = true)
input bool   InpUseATRStops = true;          // Se true SL/TP/trailing sono basati su ATR (adattivi), se false su punti fissi
input double InpSLATRMultiplier = 1.0;       // Stop Loss = ATR * questo moltiplicatore (solo se InpUseATRStops=true)
input double InpTPATRMultiplier = 2.0;       // Take Profit = ATR * questo moltiplicatore (solo se InpUseATRStops=true)
input int    InpSLPoints = 500;              // Stop Loss fisso in punti (solo se InpUseATRStops=false; 0=nessuno SL)
input int    InpTPPoints = 1000;             // Take Profit fisso in punti (solo se InpUseATRStops=false; 0=nessun TP)

//=== TRAILING STOP ===
input group "═══ 🎯 TRAILING STOP ═══"
input bool   UseTrailing = true;                  // Abilita trailing stop
input double InpTrailingActivationATR = 1.0;      // Attiva il trailing dopo profitto >= ATR * questo valore (solo se InpUseATRStops=true)
input double InpTrailingStopATR = 0.6;            // Distanza dello stop trailing = ATR * questo valore (solo se InpUseATRStops=true)
input double InpTrailingStepATR = 0.1;            // Step minimo per aggiornare lo stop = ATR * questo valore (solo se InpUseATRStops=true)
input int    InpTrailingActivationPoints = 400;   // Attiva il trailing dopo profitto >= questi punti (solo se InpUseATRStops=false)
input int    InpTrailingStopPoints = 300;         // Distanza dello stop trailing in punti (solo se InpUseATRStops=false)
input int    InpTrailingStepPoints = 50;          // Step minimo in punti per aggiornare lo stop (solo se InpUseATRStops=false)

//=== POSITION MANAGEMENT ===
input group "═══ 📊 POSITION MANAGEMENT ═══"
input int MaxPositionsPerDirection = 1;      // Massimo posizioni aperte per direzione (enforced davvero)
input int MaxTotalPositions = 2;             // Massimo posizioni totali aperte (enforced davvero)

//=== TRADE MANAGEMENT ===
input group "═══ 🔧 TRADE MANAGEMENT ═══"
input int    MagicNumber = 800200;
input string TradeComment = "VP_ML_EA";
input int    MaxSlippagePoints = 30;         // Deviation per gli ordini a mercato (points)

//=== TIME FILTER ===
input group "═══ ⏰ TIME FILTER ═══"
input bool   UseTimeFilter = false;
input string StartHour = "00:00";
input string EndHour = "23:59";

//=== DASHBOARD ===
input group "═══ 📊 DASHBOARD ═══"
input bool ShowPanel = true;
input int  InpDashboardCorner = 1;           // 0=Alto Sx 1=Alto Dx 2=Basso Sx 3=Basso Dx
input int  InpDashboardFontSize = 8;
input bool InpShowFeatureImportance = true;
input bool InpShowModelComparison = true;
input bool InpDrawActiveLevels = true;       // Disegna POC/VAH/VAL del profilo attivo (solo quello corrente, non tutto lo storico)

//=== PERFORMANCE / DEBUG ===
input group "═══ ⚡ PERFORMANCE / DEBUG ═══"
input int  InpUpdateInterval = 60;           // Secondi minimi tra due ricalcoli completi dei profili
input bool SendNotifications = false;        // Invia push notification su apertura/chiusura posizioni
input bool InpDebugMode = false;             // Log dettagliati nel tab Experts

//--- Constants
#define EPSILON 0.0000001
#define MIN_BARS_REQUIRED 100
#define MAX_PROFILES 400
#define ML_FEATURES 12
#define NUM_MODELS 3
#define SESSIONS_PER_DAY 4

//--- Structures
struct SVolumeNode {
    double price;
    double volume;
    void Init(double p) { price = p; volume = 0.0; }
};

struct SSessionProfile {
    datetime start;
    datetime end;
    double high;
    double low;
    double poc;
    double vah;
    double val;
    double total_vol;
    SVolumeNode nodes[];
    int id;
    bool is_valid;

    void Reset() {
        start = 0; end = 0;
        high = 0; low = DBL_MAX;
        poc = 0; vah = 0; val = 0;
        total_vol = 0;
        is_valid = false;
        ArrayFree(nodes);
    }
    ~SSessionProfile() { ArrayFree(nodes); }
};

struct SSignalTracker {
    datetime session_start;
    bool long_fired;
    bool short_fired;
    void Reset() { session_start = 0; long_fired = false; short_fired = false; }
};

struct SMLFeatures {
    double distance_normalized;
    double touch_count;
    double rejection_strength;
    double poc_distance_ratio;
    double atr_percentile;
    double time_of_day;
    double volume_quality;
    double price_momentum;
    double edge_distance;
    double consecutive_touches;
    double wick_asymmetry;
    double va_width_ratio;
};

struct SMLRecord {
    SMLFeatures features;
    bool is_long;
    bool is_winner;
    bool is_closed;
    bool is_shadow;        // true = segnale MAI eseguito (rifiutato dall'ML o bloccato da limiti/
                            // one-per-session): l'esito viene simulato via ATR solo per il training,
                            // non conta nelle statistiche di trading reali (g_Stats.wins/losses).
    datetime time;
    double entry_price;
    double atr_at_signal;  // ATR al momento del segnale, usato per classificare l'esito shadow
    long   position_id;    // per i segnali REALI: riconcilia l'esito effettivo alla chiusura
    string symbol;

    void Reset() {
        ZeroMemory(features);
        is_long = false; is_winner = false; is_closed = false; is_shadow = true;
        time = 0; entry_price = 0; atr_at_signal = 0; position_id = 0; symbol = "";
    }
};

struct SMLModel {
    string name;
    double feature_weights[ML_FEATURES];
    double bias;
    int    training_count;
    double accuracy;
    double precision;
    double recall;
    datetime last_train_time;

    void Reset() {
        name = "";
        ArrayInitialize(feature_weights, 0);
        bias = 0; training_count = 0; accuracy = 0; precision = 0; recall = 0;
        last_train_time = 0;
    }
};

struct SFeatureImportance {
    string name;
    double importance;
    double contribution;
};

struct SEnsembleVote {
    double model1_prob, model2_prob, model3_prob, ensemble_prob;
    int    model1_vote, model2_vote, model3_vote, consensus;
};

struct SAdaptiveParams {
    double atr_value;
    double pip_value;
    double distance_multiplier;
    int    decimals;

    void Calculate(string symbol, int atr_handle) {
        if(atr_handle != INVALID_HANDLE) {
            double atr[];
            ArraySetAsSeries(atr, true);
            if(CopyBuffer(atr_handle, 0, 0, 1, atr) > 0) atr_value = atr[0];
        }
        pip_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
        decimals  = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

        if(InpAutoAdaptDistance && atr_value > EPSILON) {
            distance_multiplier = NormalizeDouble(atr_value / (pip_value * 10), 2);
            distance_multiplier = MathMax(0.5, MathMin(distance_multiplier, 3.0));
        } else {
            distance_multiplier = 1.0;
        }
    }
};

struct SSymbolCache {
    double point;
    int    digits;
    double tick_value;
    double tick_size;
    double lot_step;
    double min_lot;
    double max_lot;
    long   filling_mode;
};

struct STimeFilter {
    bool enabled;
    int  start_minutes;
    int  end_minutes;
    bool overnight;
};

struct SMultiSymbolData {
    string symbol;
    double avg_accuracy;
    int    signal_count;
};

struct SStats {
    int total_signals;
    int ensemble_approved;
    int ensemble_rejected;
    int unanimous_votes;
    int majority_votes;
    int split_votes;
    double avg_ensemble_score;
    int total_trades;
    int long_trades;
    int short_trades;
    int wins;
    int losses;
    double total_profit;
    double best_accuracy;
    string best_model;
    int order_errors;
};

//--- Global Variables
SSessionProfile   g_Profiles[];
SSignalTracker    g_Signals[];
SMLRecord         g_MLHistory[];
SMLModel          g_MLModels[NUM_MODELS];
SFeatureImportance g_FeatureRanking[ML_FEATURES];
SAdaptiveParams   g_Adaptive;
SSymbolCache      g_SymbolCache;
STimeFilter       g_TimeFilter;
SMultiSymbolData  g_MultiSymbolDB[];
SStats            g_Stats;

string   g_FeatureNames[ML_FEATURES] = {
    "Distance", "Touches", "Rejection", "POC_Dist",
    "ATR", "TimeOfDay", "Volume", "Momentum",
    "EdgeDist", "Consecutive", "WickAsym", "VAWidth"
};

datetime g_LastUpdate = 0;
datetime g_LastBarTime = 0;
bool     g_UseRealVolume = false;
string   g_UniqueID = "";
int      g_TotalProfiles = 0;
bool     g_IsInitialized = false;
int      g_MLRecordCount = 0;
int      g_SignalsSinceRetrain = 0;
int      g_SignalsSinceExport = 0;
int      g_MultiSymbolCount = 0;
int      g_ATRHandle = INVALID_HANDLE;
double   g_HullValue = EMPTY_VALUE;

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!ValidateInputs()) return INIT_PARAMETERS_INCORRECT;

    g_UniqueID = StringFormat("VPEA_%s_%d_", _Symbol, MagicNumber);

    InitializeSymbolCache();
    InitializeTimeFilter();

    g_ATRHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
    if(g_ATRHandle == INVALID_HANDLE) {
        Print("❌ Errore creazione handle ATR: ", GetLastError());
        return INIT_FAILED;
    }
    g_Adaptive.Calculate(_Symbol, g_ATRHandle);

    g_UseRealVolume = false;
    if(InpUseRealVolume) {
        long vol  = iVolume(_Symbol, PERIOD_CURRENT, 0);
        long tick = iTickVolume(_Symbol, PERIOD_CURRENT, 0);
        g_UseRealVolume = (vol > 0 && vol != tick);
    }

    g_TotalProfiles = InpHistoryPeriods;
    if(InpProfileMode == MODE_SESSIONS) g_TotalProfiles *= SESSIONS_PER_DAY;
    if(g_TotalProfiles > MAX_PROFILES) g_TotalProfiles = MAX_PROFILES;

    ArrayResize(g_Profiles, g_TotalProfiles);
    ArrayResize(g_Signals, g_TotalProfiles * 2);
    ArrayResize(g_MLHistory, InpMLTrainingPeriod);
    ArrayResize(g_MultiSymbolDB, 50);

    for(int i = 0; i < g_TotalProfiles; i++) { g_Profiles[i].Reset(); g_Profiles[i].id = i; }
    for(int i = 0; i < ArraySize(g_Signals); i++) g_Signals[i].Reset();
    for(int i = 0; i < InpMLTrainingPeriod; i++) g_MLHistory[i].Reset();

    InitializeEnsembleModels();
    for(int i = 0; i < ML_FEATURES; i++) {
        g_FeatureRanking[i].name = g_FeatureNames[i];
        g_FeatureRanking[i].importance = 0;
        g_FeatureRanking[i].contribution = 0;
    }

    g_MLRecordCount = 0;
    g_SignalsSinceRetrain = 0;
    g_SignalsSinceExport = 0;
    g_MultiSymbolCount = 0;
    ZeroMemory(g_Stats);

    if(InpEnableML) LoadWeightsFromFile();

    g_LastUpdate = 0;
    g_LastBarTime = 0;

    EventSetTimer(5);

    g_IsInitialized = true;
    PrintInitInfo();

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Validate inputs                                                   |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
    bool valid = true;
    if(InpPriceLevels < 50 || InpPriceLevels > 200) { Print("❌ Price Levels: 50-200"); valid = false; }
    if(InpMLThreshold < 50 || InpMLThreshold > 95) { Print("❌ ML Threshold: 50-95%"); valid = false; }
    if(InpMLTrainingPeriod < 50 || InpMLTrainingPeriod > 2000) { Print("❌ ML Training Period: 50-2000"); valid = false; }
    if(InpHullPeriod < 2) { Print("❌ Hull Period: minimo 2"); valid = false; }
    if(InpValueAreaPercent <= 0 || InpValueAreaPercent > 100) { Print("❌ Value Area Percent: 1-100"); valid = false; }
    if(InpMinTouchBars < 1) { Print("❌ Min Touch Bars: minimo 1"); valid = false; }
    if(MaxPositionsPerDirection <= 0 || MaxTotalPositions <= 0) { Print("❌ Limiti posizioni non validi"); valid = false; }
    if(InpUseATRStops && InpSLATRMultiplier <= 0) { Print("❌ SL ATR multiplier deve essere > 0"); valid = false; }
    if(!InpUseATRStops && InpSLPoints < 0) { Print("❌ SL Points non puo' essere negativo"); valid = false; }
    if(!InpUseATRStops && InpTPPoints < 0) { Print("❌ TP Points non puo' essere negativo"); valid = false; }
    if(!UseFixedRisk && LotSize <= 0) { Print("❌ LotSize deve essere > 0"); valid = false; }
    return valid;
}

void InitializeSymbolCache()
{
    g_SymbolCache.point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    g_SymbolCache.digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    g_SymbolCache.tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    g_SymbolCache.tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    g_SymbolCache.lot_step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    g_SymbolCache.min_lot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    g_SymbolCache.max_lot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) g_SymbolCache.filling_mode = ORDER_FILLING_FOK;
    else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) g_SymbolCache.filling_mode = ORDER_FILLING_IOC;
    else g_SymbolCache.filling_mode = ORDER_FILLING_RETURN;
}

void InitializeTimeFilter()
{
    g_TimeFilter.enabled = UseTimeFilter;
    if(!UseTimeFilter) return;

    string ps[], pe[];
    if(StringSplit(StartHour, ':', ps) == 2 && StringSplit(EndHour, ':', pe) == 2) {
        g_TimeFilter.start_minutes = (int)StringToInteger(ps[0]) * 60 + (int)StringToInteger(ps[1]);
        g_TimeFilter.end_minutes   = (int)StringToInteger(pe[0]) * 60 + (int)StringToInteger(pe[1]);
        g_TimeFilter.overnight     = (g_TimeFilter.start_minutes > g_TimeFilter.end_minutes);
    } else {
        g_TimeFilter.enabled = false;
    }
}

void InitializeEnsembleModels()
{
    g_MLModels[0].name = "Conservative";
    g_MLModels[0].feature_weights[0]=0.12; g_MLModels[0].feature_weights[1]=0.10; g_MLModels[0].feature_weights[2]=0.25;
    g_MLModels[0].feature_weights[3]=0.12; g_MLModels[0].feature_weights[4]=0.08; g_MLModels[0].feature_weights[5]=0.06;
    g_MLModels[0].feature_weights[6]=0.07; g_MLModels[0].feature_weights[7]=0.06; g_MLModels[0].feature_weights[8]=0.05;
    g_MLModels[0].feature_weights[9]=0.04; g_MLModels[0].feature_weights[10]=0.03; g_MLModels[0].feature_weights[11]=0.02;
    g_MLModels[0].bias = 0.3;

    g_MLModels[1].name = "Balanced";
    for(int i=0;i<ML_FEATURES;i++) g_MLModels[1].feature_weights[i] = 1.0/ML_FEATURES;
    g_MLModels[1].bias = 0.5;

    g_MLModels[2].name = "Aggressive";
    g_MLModels[2].feature_weights[0]=0.20; g_MLModels[2].feature_weights[1]=0.18; g_MLModels[2].feature_weights[2]=0.10;
    g_MLModels[2].feature_weights[3]=0.12; g_MLModels[2].feature_weights[4]=0.10; g_MLModels[2].feature_weights[5]=0.08;
    g_MLModels[2].feature_weights[6]=0.06; g_MLModels[2].feature_weights[7]=0.08; g_MLModels[2].feature_weights[8]=0.04;
    g_MLModels[2].feature_weights[9]=0.02; g_MLModels[2].feature_weights[10]=0.01; g_MLModels[2].feature_weights[11]=0.01;
    g_MLModels[2].bias = 0.6;

    for(int i=0;i<NUM_MODELS;i++) {
        g_MLModels[i].training_count = 0;
        g_MLModels[i].accuracy = 0; g_MLModels[i].precision = 0; g_MLModels[i].recall = 0;
        g_MLModels[i].last_train_time = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| OnDeinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();

    if(InpAutoExportWeights && InpEnableML) {
        ExportWeightsToFile();
        BackupWeights();
    }

    if(g_ATRHandle != INVALID_HANDLE) { IndicatorRelease(g_ATRHandle); g_ATRHandle = INVALID_HANDLE; }

    if(ShowPanel) DeletePanelObjects();

    PrintStats();

    for(int i = 0; i < g_TotalProfiles; i++) g_Profiles[i].Reset();
    ArrayFree(g_Profiles);
    ArrayFree(g_Signals);
    ArrayFree(g_MLHistory);
    ArrayFree(g_MultiSymbolDB);

    g_IsInitialized = false;
}

//+------------------------------------------------------------------+
//| OnTick                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!g_IsInitialized) return;
    if(Bars(_Symbol, _Period) < MIN_BARS_REQUIRED) return;

    datetime current = TimeCurrent();
    bool is_new_bar = IsNewBar();

    if(is_new_bar || (current - g_LastUpdate >= InpUpdateInterval)) {
        UpdateProfiles();
        g_LastUpdate = current;
    }

    if(InpUseHullFilter) UpdateHullLatest();

    if(UseTrailing) ManageTrailingStops();

    if(!is_new_bar) return;

    g_Adaptive.Calculate(_Symbol, g_ATRHandle);

    if(!(g_TimeFilter.enabled && !IsTimeAllowedFast())) {
        CheckForSignal();
    }

    UpdateShadowOutcomes();
    UpdateMLTraining();

    if(ShowPanel) UpdateDashboard();
}

void OnTimer()
{
    if(!g_IsInitialized) return;
    if(ShowPanel) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Helpers: new bar / time filter                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime t = iTime(_Symbol, _Period, 0);
    if(t != g_LastBarTime) { g_LastBarTime = t; return true; }
    return false;
}

bool IsTimeAllowedFast()
{
    if(!g_TimeFilter.enabled) return true;
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int m = dt.hour * 60 + dt.min;
    if(g_TimeFilter.overnight) return (m >= g_TimeFilter.start_minutes || m <= g_TimeFilter.end_minutes);
    return (m >= g_TimeFilter.start_minutes && m <= g_TimeFilter.end_minutes);
}

//+------------------------------------------------------------------+
//| DST helper — regola EU/EET (stessa logica dell'indicatore)        |
//+------------------------------------------------------------------+
datetime LastSundayOfMonth(int year, int month)
{
    MqlDateTime dt;
    ZeroMemory(dt);
    dt.year = year; dt.mon = month; dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;

    int days_in_month;
    if(month == 12) days_in_month = 31;
    else {
        MqlDateTime next;
        ZeroMemory(next);
        next.year = year; next.mon = month + 1; next.day = 1;
        datetime next_month = StructToTime(next);
        days_in_month = (int)((next_month - StructToTime(dt)) / 86400);
    }

    dt.day = days_in_month;
    datetime last_day = StructToTime(dt);
    TimeToStruct(last_day, dt);
    int offset = dt.day_of_week; // 0=Domenica
    return last_day - (offset * 86400);
}

bool IsEEST_DST(datetime t)
{
    MqlDateTime dt;
    TimeToStruct(t, dt);
    datetime dst_start = LastSundayOfMonth(dt.year, 3);
    datetime dst_end   = LastSundayOfMonth(dt.year, 10);
    return (t >= dst_start && t < dst_end);
}

//+------------------------------------------------------------------+
//| HULL MOVING AVERAGE — embedded (no iCustom).                      |
//| Stessa formula del filtro dell'indicatore: HMA = WMA_sqrt(N)(      |
//| 2*WMA_N/2(price) - WMA_N(price)), qui riscritta a SHIFT diretto    |
//| (iClose) invece di array — serve solo il valore sull'ultima barra  |
//| chiusa (shift=1), non l'intera serie storica come nell'indicatore  |
//| (che doveva disegnare la linea sul grafico).                       |
//| Filtro posizionale: Hull sotto il prezzo -> solo LONG; Hull sopra  |
//| il prezzo -> solo SHORT.                                           |
//+------------------------------------------------------------------+
double HullWMA(int start_shift, int period)
{
    double sum = 0; int wsum = 0;
    for(int i = 0; i < period; i++) {
        int shift = start_shift + i; // shift crescente = barra piu' vecchia
        double price = iClose(_Symbol, _Period, shift);
        int weight = period - i;
        sum += price * weight;
        wsum += weight;
    }
    return (wsum == 0) ? 0 : sum / wsum;
}

void UpdateHullLatest()
{
    int period = InpHullPeriod;
    if(period < 2) { g_HullValue = EMPTY_VALUE; return; }
    int halfPeriod = period / 2;
    int sqrtPeriod = (int)MathSqrt(period);

    if(Bars(_Symbol, _Period) < period + sqrtPeriod + 5) { g_HullValue = EMPTY_VALUE; return; }

    double sum = 0; int wsum = 0;
    for(int j = 0; j < sqrtPeriod; j++) {
        int shift = 1 + j; // valutato sull'ultima barra chiusa (shift=1) e le precedenti
        double wmaHalf = HullWMA(shift, halfPeriod);
        double wmaFull = HullWMA(shift, period);
        double diff = 2.0 * wmaHalf - wmaFull;
        int weight = sqrtPeriod - j;
        sum += diff * weight;
        wsum += weight;
    }
    g_HullValue = (wsum == 0) ? EMPTY_VALUE : sum / wsum;
}

//+------------------------------------------------------------------+
//| PROFILE MANAGEMENT (identico all'indicatore, senza disegno)       |
//+------------------------------------------------------------------+
void UpdateProfiles()
{
    if(InpProfileMode == MODE_SESSIONS) UpdateSessionProfiles();
    else UpdateStandardProfiles();

    if(InpDrawActiveLevels) DrawActiveLevels();
}

void UpdateSessionProfiles()
{
    int idx = 0;
    for(int i = 0; i < InpHistoryPeriods && idx < g_TotalProfiles - (SESSIONS_PER_DAY - 1); i++) {

        SSessionProfile sydney; sydney.id = idx; sydney.Reset();
        if(GetSessionTime(InpSydneyStart, InpSydneyEnd, i, sydney.start, sydney.end)) {
            BuildProfile(sydney);
            if(sydney.is_valid) { CalculateKeyLevels(sydney); g_Profiles[idx++] = sydney; }
        }

        SSessionProfile asian; asian.id = idx; asian.Reset();
        if(GetSessionTime(InpAsianStart, InpAsianEnd, i, asian.start, asian.end)) {
            BuildProfile(asian);
            if(asian.is_valid) { CalculateKeyLevels(asian); g_Profiles[idx++] = asian; }
        }

        SSessionProfile london; london.id = idx; london.Reset();
        if(GetSessionTime(InpLondonStart, InpLondonEnd, i, london.start, london.end)) {
            BuildProfile(london);
            if(london.is_valid) { CalculateKeyLevels(london); g_Profiles[idx++] = london; }
        }

        SSessionProfile ny; ny.id = idx; ny.Reset();
        if(GetSessionTime(InpNewYorkStart, InpNewYorkEnd, i, ny.start, ny.end)) {
            BuildProfile(ny);
            if(ny.is_valid) { CalculateKeyLevels(ny); g_Profiles[idx++] = ny; }
        }
    }
}

void UpdateStandardProfiles()
{
    ENUM_TIMEFRAMES tf;
    switch(InpProfileMode) {
        case MODE_DAILY:   tf = PERIOD_D1;  break;
        case MODE_WEEKLY:  tf = PERIOD_W1;  break;
        case MODE_MONTHLY: tf = PERIOD_MN1; break;
        default: return;
    }

    for(int i = 0; i < InpHistoryPeriods && i < g_TotalProfiles; i++) {
        SSessionProfile profile; profile.id = i; profile.Reset();
        profile.start = iTime(_Symbol, tf, i + 1);
        profile.end   = iTime(_Symbol, tf, i);
        if(profile.start <= 0 || profile.end <= 0) continue;
        if(i == 0) profile.end = TimeCurrent();

        BuildProfile(profile);
        if(profile.is_valid) { CalculateKeyLevels(profile); g_Profiles[i] = profile; }
    }
}

bool GetSessionTime(string start_str, string end_str, int days_back, datetime &start_out, datetime &end_out)
{
    MqlDateTime dt;
    datetime base = TimeCurrent() - (days_back * 86400);
    if(!TimeToStruct(base, dt)) return false;

    int dst_shift = (InpAutoDST && IsEEST_DST(base)) ? 1 : 0;

    string parts[];
    if(StringSplit(start_str, ':', parts) != 2) return false;
    dt.hour = (int)StringToInteger(parts[0]) + dst_shift;
    dt.min  = (int)StringToInteger(parts[1]);
    dt.sec  = 0;
    start_out = StructToTime(dt);
    if(start_out <= 0) return false;

    if(StringSplit(end_str, ':', parts) != 2) return false;
    dt.hour = (int)StringToInteger(parts[0]) + dst_shift;
    dt.min  = (int)StringToInteger(parts[1]);
    end_out = StructToTime(dt);
    if(end_out <= 0) return false;
    if(end_out <= start_out) end_out += 86400;
    return true;
}

void BuildProfile(SSessionProfile &profile)
{
    profile.is_valid = false;
    profile.high = 0;
    profile.low  = DBL_MAX;
    profile.total_vol = 0;

    int start_bar = iBarShift(_Symbol, InpTimeframe, profile.start);
    int end_bar   = iBarShift(_Symbol, InpTimeframe, profile.end);
    if(start_bar < 0 || end_bar < 0) return;
    if(start_bar < end_bar) { int t = start_bar; start_bar = end_bar; end_bar = t; }

    for(int i = end_bar; i <= start_bar; i++) {
        double h = iHigh(_Symbol, InpTimeframe, i);
        double l = iLow(_Symbol, InpTimeframe, i);
        if(h <= 0 || l <= 0) continue;
        if(h > profile.high) profile.high = h;
        if(l < profile.low)  profile.low  = l;
    }

    if(profile.high <= profile.low + EPSILON) return;

    ArrayResize(profile.nodes, InpPriceLevels);
    double step = (profile.high - profile.low) / InpPriceLevels;
    for(int i = 0; i < InpPriceLevels; i++)
        profile.nodes[i].Init(profile.low + (i * step) + (step * 0.5));

    for(int i = end_bar; i <= start_bar; i++) {
        double h = iHigh(_Symbol, InpTimeframe, i);
        double l = iLow(_Symbol, InpTimeframe, i);
        double vol = g_UseRealVolume ? (double)iVolume(_Symbol, InpTimeframe, i) : (double)iTickVolume(_Symbol, InpTimeframe, i);
        if(vol <= EPSILON) continue;

        int start_level = (int)((l - profile.low) / step);
        int end_level   = (int)((h - profile.low) / step);
        start_level = MathMax(0, MathMin(start_level, InpPriceLevels - 1));
        end_level   = MathMax(0, MathMin(end_level, InpPriceLevels - 1));

        int num_levels = end_level - start_level + 1;
        if(num_levels <= 0) num_levels = 1;
        double vol_per_level = vol / num_levels;

        for(int j = start_level; j <= end_level; j++) profile.nodes[j].volume += vol_per_level;
        profile.total_vol += vol;
    }

    profile.is_valid = (profile.total_vol > EPSILON);
}

void CalculateKeyLevels(SSessionProfile &profile)
{
    int size = ArraySize(profile.nodes);
    if(size == 0 || profile.total_vol < EPSILON || !profile.is_valid) return;

    double max_vol = 0;
    int poc_idx = 0;
    for(int i = 0; i < size; i++) {
        if(profile.nodes[i].volume > max_vol) { max_vol = profile.nodes[i].volume; poc_idx = i; }
    }
    profile.poc = profile.nodes[poc_idx].price;

    double target = profile.total_vol * (InpValueAreaPercent / 100.0);
    double accum = profile.nodes[poc_idx].volume;
    int high_idx = poc_idx, low_idx = poc_idx;

    while(accum < target && (high_idx < size - 1 || low_idx > 0)) {
        double vol_above = (high_idx < size - 1) ? profile.nodes[high_idx + 1].volume : 0;
        double vol_below = (low_idx > 0) ? profile.nodes[low_idx - 1].volume : 0;

        if(vol_above >= vol_below && high_idx < size - 1) { high_idx++; accum += profile.nodes[high_idx].volume; }
        else if(low_idx > 0) { low_idx--; accum += profile.nodes[low_idx].volume; }
        else break;
    }

    profile.vah = profile.nodes[high_idx].price;
    profile.val = profile.nodes[low_idx].price;
}

//+------------------------------------------------------------------+
//| Disegna solo POC/VAH/VAL del profilo attivo (indice 0)            |
//+------------------------------------------------------------------+
void DrawActiveLevels()
{
    if(g_TotalProfiles == 0 || !g_Profiles[0].is_valid) return;
    string prefix = g_UniqueID + "LVL_";
    datetime end = TimeCurrent();
    DrawLevelLine(prefix + "POC", g_Profiles[0].start, g_Profiles[0].poc, end, clrRed, STYLE_SOLID);
    DrawLevelLine(prefix + "VAH", g_Profiles[0].start, g_Profiles[0].vah, end, clrOrange, STYLE_DASH);
    DrawLevelLine(prefix + "VAL", g_Profiles[0].start, g_Profiles[0].val, end, clrOrange, STYLE_DASH);
}

void DrawLevelLine(string name, datetime t1, double price, datetime t2, color clr, ENUM_LINE_STYLE style)
{
    if(price <= EPSILON || t1 <= 0 || t2 <= 0) return;
    if(ObjectFind(0, name) < 0) {
        if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price)) return;
    } else {
        ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
        ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price);
    }
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| SIGNAL DETECTION — valutata solo sull'ultima barra chiusa          |
//| (shift=1), una volta per nuova barra. Nessuna ripetizione su      |
//| barre storiche come nell'indicatore (qui non serve: si allena su  |
//| esiti reali dei trade, non serve backfill sintetico).             |
//+------------------------------------------------------------------+
void CheckForSignal()
{
    int shift = 1;
    datetime bar_time = iTime(_Symbol, _Period, shift);

    for(int p = 0; p < g_TotalProfiles; p++) {
        if(!g_Profiles[p].is_valid) continue;
        if(bar_time >= g_Profiles[p].start && bar_time <= g_Profiles[p].end) {
            EvaluateSignal(shift, g_Profiles[p]);
            return;
        }
    }
}

void EvaluateSignal(int shift, SSessionProfile &profile)
{
    if(!profile.is_valid) return;

    double price = iClose(_Symbol, _Period, shift);
    double pip = g_Adaptive.pip_value * 10;
    double effective_distance = InpVADistance * g_Adaptive.distance_multiplier;

    // Filtro Hull posizionale: Hull sotto il prezzo -> BUY ammesso, Hull sopra -> SELL ammesso
    bool hull_ok_long = true, hull_ok_short = true;
    if(InpUseHullFilter) {
        if(g_HullValue == EMPTY_VALUE) { hull_ok_long = false; hull_ok_short = false; }
        else { hull_ok_long = (price > g_HullValue); hull_ok_short = (price < g_HullValue); }
    }

    // LONG: prezzo vicino a VAL, sotto il POC (se strict mode)
    double dist_val = MathAbs(price - profile.val);
    bool near_val = (dist_val <= (effective_distance * pip));
    bool below_poc = !InpStrictMode || (price < profile.poc);

    if(near_val && below_poc && hull_ok_long) {
        int touches = CountTouches(shift, profile.val, effective_distance * pip);
        double rejection = CalculateBullishRejection(shift);
        bool rejection_ok = !InpRequireRejection || rejection >= InpMinWickRatio;

        if(rejection_ok && touches >= InpMinTouchBars)
            TryFireSignal(true, shift, profile, price, dist_val, touches, rejection);
    }

    // SHORT: prezzo vicino a VAH, sopra il POC (se strict mode)
    double dist_vah = MathAbs(price - profile.vah);
    bool near_vah = (dist_vah <= (effective_distance * pip));
    bool above_poc = !InpStrictMode || (price > profile.poc);

    if(near_vah && above_poc && hull_ok_short) {
        int touches = CountTouches(shift, profile.vah, effective_distance * pip);
        double rejection = CalculateBearishRejection(shift);
        bool rejection_ok = !InpRequireRejection || rejection >= InpMinWickRatio;

        if(rejection_ok && touches >= InpMinTouchBars)
            TryFireSignal(false, shift, profile, price, dist_vah, touches, rejection);
    }
}

void TryFireSignal(bool is_long, int shift, SSessionProfile &profile, double price,
                    double distance, int touches, double rejection)
{
    datetime signal_time = iTime(_Symbol, _Period, shift);
    SMLFeatures features = ExtractFeatures(shift, is_long, profile, distance, touches, rejection);
    SEnsembleVote vote = GetEnsembleVote(features);

    g_Stats.total_signals++;
    g_Stats.avg_ensemble_score = (g_Stats.avg_ensemble_score * (g_Stats.total_signals - 1) + vote.ensemble_prob) / g_Stats.total_signals;
    if(vote.consensus == 3) g_Stats.unanimous_votes++;
    else if(vote.consensus == 2) g_Stats.majority_votes++;
    else g_Stats.split_votes++;

    // FIX: registra SEMPRE il segnale tecnicamente valido come candidato "shadow"
    // per il training, indipendentemente dall'approvazione ML. Se la registrazione
    // avvenisse solo per i segnali approvati, un ensemble che parte sotto soglia
    // (pesi iniziali hardcoded) non riceverebbe mai dati per allenarsi e resterebbe
    // bloccato per sempre a 0 approvazioni — un deadlock. L'esito dei segnali MAI
    // eseguiti viene simulato via ATR da UpdateShadowOutcomes() solo ai fini del
    // training; se invece il segnale viene eseguito, il record viene "promosso" a
    // reale e il suo esito arriva dal trade vero (OnTradeTransaction).
    RecordMLSignal(features, is_long, signal_time, price, 0, true);

    if(InpEnableML && vote.ensemble_prob < InpMLThreshold) {
        g_Stats.ensemble_rejected++;
        if(InpDebugMode) PrintFormat("❌ %s REJECTED | ENS:%.1f%%", is_long ? "LONG" : "SHORT", vote.ensemble_prob);
        return;
    }
    g_Stats.ensemble_approved++;

    if(InpOneSignalPerSession) {
        for(int i = 0; i < ArraySize(g_Signals); i++) {
            if(g_Signals[i].session_start == profile.start) {
                if(is_long && g_Signals[i].long_fired) return;
                if(!is_long && g_Signals[i].short_fired) return;
                break;
            }
        }
    }

    if(!CanOpenPosition(is_long)) {
        if(InpDebugMode) Print("⚠️ Segnale approvato ma limite posizioni raggiunto");
        return;
    }

    if(ExecuteMarketOrder(is_long, signal_time)) {
        if(InpOneSignalPerSession) UpdateSignalTracker(profile.start, is_long);
        if(InpDebugMode)
            PrintFormat("✅ %s APPROVED | ENS:%.1f%% M1:%.1f M2:%.1f M3:%.1f",
                        is_long ? "LONG" : "SHORT", vote.ensemble_prob, vote.model1_prob, vote.model2_prob, vote.model3_prob);
    }
}

void UpdateSignalTracker(datetime session_start, bool is_long)
{
    for(int i = 0; i < ArraySize(g_Signals); i++) {
        if(g_Signals[i].session_start == 0 || g_Signals[i].session_start == session_start) {
            g_Signals[i].session_start = session_start;
            if(is_long) g_Signals[i].long_fired = true; else g_Signals[i].short_fired = true;
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| FEATURE EXTRACTION — a shift diretto (0=corrente)                 |
//+------------------------------------------------------------------+
int CountTouches(int shift, double level, double threshold)
{
    int touches = 0;
    int lookback = MathMax(InpMinTouchBars * 4, 12);
    for(int i = 1; i <= lookback; i++) {
        double c = iClose(_Symbol, _Period, shift + i);
        if(MathAbs(c - level) <= threshold * 1.5) touches++;
    }
    return touches;
}

int CountConsecutiveTouches(int shift, double level, double threshold)
{
    int count = 0;
    for(int i = 1; i <= 10; i++) {
        double c = iClose(_Symbol, _Period, shift + i);
        if(MathAbs(c - level) <= threshold) count++; else break;
    }
    return count;
}

double CalculateMomentum(int shift, int period)
{
    double c0 = iClose(_Symbol, _Period, shift);
    double c1 = iClose(_Symbol, _Period, shift + period);
    if(MathAbs(c1) < EPSILON) return 0;
    double roc = (c0 - c1) / c1;
    return MathMin(MathMax(roc * 100, -1.0), 1.0);
}

double CalculateWickAsymmetry(int shift)
{
    double o = iOpen(_Symbol, _Period, shift), h = iHigh(_Symbol, _Period, shift);
    double l = iLow(_Symbol, _Period, shift), c = iClose(_Symbol, _Period, shift);
    double total = h - l;
    if(total < EPSILON) return 0;
    double upper = h - MathMax(o, c), lower = MathMin(o, c) - l;
    return (upper - lower) / total;
}

double CalculateBullishRejection(int shift)
{
    double o = iOpen(_Symbol, _Period, shift), h = iHigh(_Symbol, _Period, shift);
    double l = iLow(_Symbol, _Period, shift), c = iClose(_Symbol, _Period, shift);
    double total = h - l;
    if(total < EPSILON) return 0;
    return (MathMin(o, c) - l) / total;
}

double CalculateBearishRejection(int shift)
{
    double o = iOpen(_Symbol, _Period, shift), h = iHigh(_Symbol, _Period, shift);
    double l = iLow(_Symbol, _Period, shift), c = iClose(_Symbol, _Period, shift);
    double total = h - l;
    if(total < EPSILON) return 0;
    return (h - MathMax(o, c)) / total;
}

//+------------------------------------------------------------------+
//| Time score — allineato all'overlap London/NY, DST-aware.          |
//+------------------------------------------------------------------+
double CalculateTimeScore(datetime dt)
{
    MqlDateTime mdt;
    TimeToStruct(dt, mdt);
    int hour = mdt.hour;

    bool dst = InpAutoDST && IsEEST_DST(dt);
    int london_start  = dst ? 11 : 10;
    int overlap_start = dst ? 16 : 15;
    int overlap_end   = dst ? 20 : 19;
    int ny_end        = dst ? 1  : 0;

    if(hour >= overlap_start && hour < overlap_end) return 1.0;
    if(hour >= london_start && hour < overlap_start) return 0.85;
    if(hour >= overlap_end || hour < ny_end) return 0.70;
    return 0.35;
}

double CalculateATRPercentileAdvanced(int shift)
{
    if(g_ATRHandle == INVALID_HANDLE || shift < 0) return 0.5;
    double atr_array[];
    ArraySetAsSeries(atr_array, true);
    int lookback = 100;
    if(CopyBuffer(g_ATRHandle, 0, shift, lookback, atr_array) != lookback) return 0.5;

    double current_atr = atr_array[0];
    int below_count = 0;
    for(int i = 1; i < lookback; i++) if(atr_array[i] < current_atr) below_count++;
    return (double)below_count / (lookback - 1);
}

SMLFeatures ExtractFeatures(int shift, bool is_long, SSessionProfile &profile,
                             double distance, int touches, double rejection)
{
    SMLFeatures f;
    double pip = g_Adaptive.pip_value * 10;

    double max_distance = InpVADistance * g_Adaptive.distance_multiplier * pip * 2;
    f.distance_normalized = 1.0 - MathMin(distance / max_distance, 1.0);
    f.touch_count = touches;
    f.rejection_strength = rejection;

    double target_price = is_long ? profile.val : profile.vah;
    double poc_dist = MathAbs(target_price - profile.poc);
    double va_range = MathAbs(profile.vah - profile.val);
    f.poc_distance_ratio = (va_range > EPSILON) ? MathMin(poc_dist / va_range, 1.0) : 0.5;

    f.atr_percentile = CalculateATRPercentileAdvanced(shift);
    f.time_of_day = CalculateTimeScore(iTime(_Symbol, _Period, shift));
    f.volume_quality = (profile.total_vol > 0) ? MathMin(profile.total_vol / 1000000.0, 1.0) : 0.5;
    f.price_momentum = CalculateMomentum(shift, 3);

    double close_shift = iClose(_Symbol, _Period, shift);
    double dist_high = MathAbs(close_shift - profile.high);
    double dist_low  = MathAbs(close_shift - profile.low);
    double profile_range = profile.high - profile.low;
    f.edge_distance = (profile_range > EPSILON) ? MathMin(MathMin(dist_high, dist_low) / profile_range, 1.0) : 0.5;

    f.consecutive_touches = CountConsecutiveTouches(shift, target_price, pip * 20);
    f.wick_asymmetry = CalculateWickAsymmetry(shift);
    f.va_width_ratio = (profile_range > EPSILON) ? MathMin((profile.vah - profile.val) / profile_range, 1.0) : 0.5;

    return f;
}

//+------------------------------------------------------------------+
//| ML ENSEMBLE                                                        |
//+------------------------------------------------------------------+
double PredictProbability(SMLFeatures &features, int model_idx)
{
    if(model_idx < 0 || model_idx >= NUM_MODELS) model_idx = 0;
    double score = g_MLModels[model_idx].bias;

    score += features.distance_normalized * g_MLModels[model_idx].feature_weights[0];
    score += (features.touch_count / 10.0) * g_MLModels[model_idx].feature_weights[1];
    score += features.rejection_strength * g_MLModels[model_idx].feature_weights[2];
    score += features.poc_distance_ratio * g_MLModels[model_idx].feature_weights[3];
    score += features.atr_percentile * g_MLModels[model_idx].feature_weights[4];
    score += features.time_of_day * g_MLModels[model_idx].feature_weights[5];
    score += features.volume_quality * g_MLModels[model_idx].feature_weights[6];
    score += (features.price_momentum + 1.0) / 2.0 * g_MLModels[model_idx].feature_weights[7];
    score += features.edge_distance * g_MLModels[model_idx].feature_weights[8];
    score += (features.consecutive_touches / 5.0) * g_MLModels[model_idx].feature_weights[9];
    score += (features.wick_asymmetry + 1.0) / 2.0 * g_MLModels[model_idx].feature_weights[10];
    score += features.va_width_ratio * g_MLModels[model_idx].feature_weights[11];

    double probability = 1.0 / (1.0 + MathExp(-score));
    return probability * 100.0;
}

SEnsembleVote GetEnsembleVote(SMLFeatures &features)
{
    SEnsembleVote vote;

    if(InpEnableEnsemble) {
        vote.model1_prob = PredictProbability(features, 0);
        vote.model2_prob = PredictProbability(features, 1);
        vote.model3_prob = PredictProbability(features, 2);

        vote.model1_vote = (vote.model1_prob >= InpMLThreshold) ? 1 : 0;
        vote.model2_vote = (vote.model2_prob >= InpMLThreshold) ? 1 : 0;
        vote.model3_vote = (vote.model3_prob >= InpMLThreshold) ? 1 : 0;
        vote.consensus = vote.model1_vote + vote.model2_vote + vote.model3_vote;

        vote.ensemble_prob = (vote.model1_prob * 0.35 + vote.model2_prob * 0.30 + vote.model3_prob * 0.35);
    } else {
        vote.model1_prob = PredictProbability(features, 0);
        vote.model2_prob = 0; vote.model3_prob = 0;
        vote.ensemble_prob = vote.model1_prob;
        vote.model1_vote = (vote.model1_prob >= InpMLThreshold) ? 1 : 0;
        vote.model2_vote = 0; vote.model3_vote = 0;
        vote.consensus = vote.model1_vote;
    }

    if(InpEnableMultiSymbol) {
        double sym_weight = GetSymbolWeight(_Symbol);
        double adj = 0.85 + 0.30 * sym_weight;
        vote.ensemble_prob = MathMin(vote.ensemble_prob * adj, 100.0);
    }

    return vote;
}

void TrainEnsembleModels()
{
    int closed_signals = 0;
    for(int i = 0; i < g_MLRecordCount; i++) if(g_MLHistory[i].is_closed) closed_signals++;

    if(closed_signals < 20) {
        if(InpDebugMode) Print("⚠️ ML: segnali chiusi insufficienti (", closed_signals, "/20)");
        return;
    }

    double learning_rate = 0.01;

    for(int m = 0; m < NUM_MODELS; m++) {
        int correct = 0, tp = 0, fp = 0, fn = 0;

        for(int i = 0; i < g_MLRecordCount; i++) {
            if(!g_MLHistory[i].is_closed) continue;

            double predicted = PredictProbability(g_MLHistory[i].features, m) / 100.0;
            double actual = g_MLHistory[i].is_winner ? 1.0 : 0.0;
            double error = actual - predicted;

            g_MLModels[m].feature_weights[0]  += learning_rate * error * g_MLHistory[i].features.distance_normalized;
            g_MLModels[m].feature_weights[1]  += learning_rate * error * (g_MLHistory[i].features.touch_count / 10.0);
            g_MLModels[m].feature_weights[2]  += learning_rate * error * g_MLHistory[i].features.rejection_strength;
            g_MLModels[m].feature_weights[3]  += learning_rate * error * g_MLHistory[i].features.poc_distance_ratio;
            g_MLModels[m].feature_weights[4]  += learning_rate * error * g_MLHistory[i].features.atr_percentile;
            g_MLModels[m].feature_weights[5]  += learning_rate * error * g_MLHistory[i].features.time_of_day;
            g_MLModels[m].feature_weights[6]  += learning_rate * error * g_MLHistory[i].features.volume_quality;
            g_MLModels[m].feature_weights[7]  += learning_rate * error * ((g_MLHistory[i].features.price_momentum + 1.0) / 2.0);
            g_MLModels[m].feature_weights[8]  += learning_rate * error * g_MLHistory[i].features.edge_distance;
            g_MLModels[m].feature_weights[9]  += learning_rate * error * (g_MLHistory[i].features.consecutive_touches / 5.0);
            g_MLModels[m].feature_weights[10] += learning_rate * error * ((g_MLHistory[i].features.wick_asymmetry + 1.0) / 2.0);
            g_MLModels[m].feature_weights[11] += learning_rate * error * g_MLHistory[i].features.va_width_ratio;
            g_MLModels[m].bias += learning_rate * error;

            bool predicted_win = (predicted >= 0.5);
            bool actual_win = g_MLHistory[i].is_winner;
            if(predicted_win == actual_win) correct++;
            if(predicted_win && actual_win) tp++;
            if(predicted_win && !actual_win) fp++;
            if(!predicted_win && actual_win) fn++;
        }

        g_MLModels[m].accuracy  = (closed_signals > 0) ? (double)correct / closed_signals * 100.0 : 0;
        g_MLModels[m].precision = (tp + fp > 0) ? (double)tp / (tp + fp) * 100.0 : 0;
        g_MLModels[m].recall    = (tp + fn > 0) ? (double)tp / (tp + fn) * 100.0 : 0;
        g_MLModels[m].training_count++;
        g_MLModels[m].last_train_time = TimeCurrent();
    }

    double best_acc = 0;
    for(int m = 0; m < NUM_MODELS; m++) {
        if(g_MLModels[m].accuracy > best_acc) {
            best_acc = g_MLModels[m].accuracy;
            g_Stats.best_accuracy = best_acc;
            g_Stats.best_model = g_MLModels[m].name;
        }
    }

    if(InpDebugMode) {
        PrintFormat("✅ ENSEMBLE RETRAINED su ESITI REALI | Closed: %d", closed_signals);
        for(int m = 0; m < NUM_MODELS; m++)
            PrintFormat("  %s: Acc=%.1f%% Pre=%.1f%% Rec=%.1f%%", g_MLModels[m].name, g_MLModels[m].accuracy, g_MLModels[m].precision, g_MLModels[m].recall);
    }
}

void UpdateFeatureImportance()
{
    for(int f = 0; f < ML_FEATURES; f++) {
        double avg_weight = 0;
        for(int m = 0; m < NUM_MODELS; m++) avg_weight += MathAbs(g_MLModels[m].feature_weights[f]);
        g_FeatureRanking[f].importance = avg_weight / NUM_MODELS;
        g_FeatureRanking[f].contribution = g_FeatureRanking[f].importance * 100;
    }
    for(int i = 0; i < ML_FEATURES - 1; i++) {
        for(int j = 0; j < ML_FEATURES - i - 1; j++) {
            if(g_FeatureRanking[j].importance < g_FeatureRanking[j + 1].importance) {
                SFeatureImportance tmp = g_FeatureRanking[j];
                g_FeatureRanking[j] = g_FeatureRanking[j + 1];
                g_FeatureRanking[j + 1] = tmp;
            }
        }
    }
}

void UpdateMLTraining()
{
    if(InpEnableML && InpMLAdaptive && g_SignalsSinceRetrain >= InpMLRetrainInterval) {
        TrainEnsembleModels();
        UpdateFeatureImportance();
        g_SignalsSinceRetrain = 0;
    }
    if(InpAutoExportWeights && g_SignalsSinceExport >= InpExportInterval) {
        ExportWeightsToFile();
        BackupWeights();
        g_SignalsSinceExport = 0;
    }
}

//+------------------------------------------------------------------+
//| MULTI-SYMBOL LEARNING                                              |
//+------------------------------------------------------------------+
void UpdateMultiSymbolDB(string symbol, bool is_winner)
{
    if(!InpEnableMultiSymbol) return;

    int idx = -1;
    for(int i = 0; i < g_MultiSymbolCount; i++) if(g_MultiSymbolDB[i].symbol == symbol) { idx = i; break; }

    if(idx < 0 && g_MultiSymbolCount < 50) {
        idx = g_MultiSymbolCount;
        g_MultiSymbolDB[idx].symbol = symbol;
        g_MultiSymbolDB[idx].signal_count = 0;
        g_MultiSymbolDB[idx].avg_accuracy = 0;
        g_MultiSymbolCount++;
    }

    if(idx >= 0) {
        int prev_count = g_MultiSymbolDB[idx].signal_count;
        double prev_acc = g_MultiSymbolDB[idx].avg_accuracy;
        g_MultiSymbolDB[idx].signal_count++;
        g_MultiSymbolDB[idx].avg_accuracy = (prev_acc * prev_count + (is_winner ? 100.0 : 0.0)) / g_MultiSymbolDB[idx].signal_count;
    }
}

double GetSymbolWeight(string symbol)
{
    if(!InpEnableMultiSymbol) return 1.0;
    for(int i = 0; i < g_MultiSymbolCount; i++) {
        if(g_MultiSymbolDB[i].symbol == symbol) {
            if(g_MultiSymbolDB[i].signal_count < 10) return 1.0;
            return g_MultiSymbolDB[i].avg_accuracy / 100.0;
        }
    }
    return 1.0;
}

//+------------------------------------------------------------------+
//| TRADE EXECUTION                                                    |
//+------------------------------------------------------------------+
bool CanOpenPosition(bool is_long)
{
    int buy = 0, sell = 0, total = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        total++;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) buy++; else sell++;
    }
    if(total >= MaxTotalPositions) return false;
    if(is_long && buy >= MaxPositionsPerDirection) return false;
    if(!is_long && sell >= MaxPositionsPerDirection) return false;
    return true;
}

double CalculateLotSize(double stopLossPoints)
{
    if(!UseFixedRisk) return LotSize;
    if(stopLossPoints <= 0) return LotSize; // evita divisione per zero se l'ATR fosse anomalo

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (RiskPercent / 100.0);
    double stopLossInPrice = stopLossPoints * g_SymbolCache.point;

    if(stopLossInPrice < EPSILON || g_SymbolCache.tick_value < EPSILON) return LotSize;

    double lots = (riskAmount * g_SymbolCache.tick_size) / (stopLossInPrice * g_SymbolCache.tick_value);
    lots = MathFloor(lots / g_SymbolCache.lot_step) * g_SymbolCache.lot_step;
    if(lots < g_SymbolCache.min_lot) lots = g_SymbolCache.min_lot;
    if(lots > g_SymbolCache.max_lot) lots = g_SymbolCache.max_lot;
    return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Distanze SL/TP in prezzo, ATR-based o a punti fissi a seconda di   |
//| InpUseATRStops. Usata sia per l'esecuzione reale (ExecuteMarketOrder)|
//| sia per la classificazione sintetica dei segnali "shadow"          |
//| (UpdateShadowOutcomes), cosi' l'esito simulato riflette sempre     |
//| esattamente cosa avrebbe fatto un trade vero con la stessa          |
//| configurazione. Ritorna false solo se in modalita' ATR l'ATR non   |
//| e' ancora disponibile (dati insufficienti).                        |
//+------------------------------------------------------------------+
bool GetStopDistances(double &sl_distance, double &tp_distance)
{
    if(InpUseATRStops) {
        double atr = g_Adaptive.atr_value;
        if(atr < EPSILON) return false;
        sl_distance = InpSLATRMultiplier * atr;
        tp_distance = InpTPATRMultiplier * atr;
    } else {
        sl_distance = InpSLPoints * g_SymbolCache.point;
        tp_distance = InpTPPoints * g_SymbolCache.point;
    }
    return true;
}

bool ExecuteMarketOrder(bool is_long, datetime signal_time)
{
    double sl_distance, tp_distance;
    if(!GetStopDistances(sl_distance, tp_distance)) return false;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double entry = is_long ? ask : bid;

    double sl = 0, tp = 0;
    if(sl_distance > 0) sl = NormalizeDouble(is_long ? entry - sl_distance : entry + sl_distance, g_SymbolCache.digits);
    if(tp_distance > 0) tp = NormalizeDouble(is_long ? entry + tp_distance : entry - tp_distance, g_SymbolCache.digits);

    double sl_points = sl_distance / g_SymbolCache.point;
    double lots = CalculateLotSize(sl_points);

    MqlTradeRequest request = {};
    MqlTradeResult  result  = {};
    request.action       = TRADE_ACTION_DEAL;
    request.symbol        = _Symbol;
    request.volume        = lots;
    request.type          = is_long ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    request.price         = entry;
    request.sl             = sl;
    request.tp             = tp;
    request.deviation      = MaxSlippagePoints;
    request.magic          = MagicNumber;
    request.comment        = TradeComment;
    request.type_filling   = (ENUM_ORDER_TYPE_FILLING)g_SymbolCache.filling_mode;

    if(!OrderSend(request, result)) {
        g_Stats.order_errors++;
        if(InpDebugMode) PrintFormat("❌ ORDINE FALLITO | %d - %s", result.retcode, result.comment);
        return false;
    }
    if(result.retcode != TRADE_RETCODE_DONE) {
        g_Stats.order_errors++;
        if(InpDebugMode) PrintFormat("❌ ORDINE NON ESEGUITO | retcode:%d", result.retcode);
        return false;
    }

    long position_id = 0;
    if(HistoryDealSelect(result.deal)) position_id = HistoryDealGetInteger(result.deal, DEAL_POSITION_ID);

    // Il segnale e' gia' stato registrato come "shadow" in TryFireSignal prima
    // ancora di sapere se sarebbe stato approvato/eseguito. Ora che l'ordine e'
    // stato eseguito davvero, promuoviamo quel record a "reale": il suo esito
    // arrivera' dal trade vero (OnTradeTransaction), non da una simulazione ATR.
    UpgradeShadowToReal(is_long, signal_time, position_id, entry);

    g_Stats.total_trades++;
    if(is_long) g_Stats.long_trades++; else g_Stats.short_trades++;

    if(SendNotifications)
        SendNotification(StringFormat("%s %s %.2f lot @ %.5f SL:%.5f TP:%.5f", is_long ? "BUY" : "SELL", _Symbol, lots, entry, sl, tp));

    return true;
}

void RecordMLSignal(SMLFeatures &features, bool is_long, datetime time, double price, long position_id, bool is_shadow)
{
    if(g_MLRecordCount >= InpMLTrainingPeriod) {
        for(int i = 0; i < InpMLTrainingPeriod - 1; i++) g_MLHistory[i] = g_MLHistory[i + 1];
        g_MLRecordCount = InpMLTrainingPeriod - 1;
    }

    g_MLHistory[g_MLRecordCount].features = features;
    g_MLHistory[g_MLRecordCount].is_long = is_long;
    g_MLHistory[g_MLRecordCount].time = time;
    g_MLHistory[g_MLRecordCount].entry_price = price;
    g_MLHistory[g_MLRecordCount].atr_at_signal = g_Adaptive.atr_value;
    g_MLHistory[g_MLRecordCount].position_id = position_id;
    g_MLHistory[g_MLRecordCount].is_shadow = is_shadow;
    g_MLHistory[g_MLRecordCount].is_closed = false;
    g_MLHistory[g_MLRecordCount].symbol = _Symbol;

    g_MLRecordCount++;
    g_SignalsSinceRetrain++;
    g_SignalsSinceExport++;
}

//+------------------------------------------------------------------+
//| Promuove un record "shadow" (mai eseguito) a "reale" appena         |
//| l'ordine corrispondente viene effettivamente riempito. Match per   |
//| direzione+orario del segnale invece di un indice salvato, per      |
//| restare corretto anche se nel frattempo il buffer circolare ha     |
//| fatto scorrere gli elementi.                                       |
//+------------------------------------------------------------------+
void UpgradeShadowToReal(bool is_long, datetime signal_time, long position_id, double entry_price)
{
    for(int i = g_MLRecordCount - 1; i >= 0; i--) {
        if(g_MLHistory[i].is_shadow && !g_MLHistory[i].is_closed &&
           g_MLHistory[i].is_long == is_long && g_MLHistory[i].time == signal_time) {
            g_MLHistory[i].is_shadow = false;
            g_MLHistory[i].position_id = position_id;
            g_MLHistory[i].entry_price = entry_price;
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Esito SINTETICO (via ATR) per i segnali "shadow" mai eseguiti —    |
//| serve solo a dare dati al training ML quando l'ensemble rifiuta    |
//| (o non puo' eseguire) un segnale tecnicamente valido; senza questo |
//| l'ensemble non riceverebbe mai feedback sui segnali che scarta e   |
//| non potrebbe mai correggere la propria soglia di rigetto. Non      |
//| tocca g_Stats.wins/losses/total_profit, riservate ai trade reali.  |
//| Shift-based e coerente (niente mix series/non-series).             |
//+------------------------------------------------------------------+
void UpdateShadowOutcomes()
{
    for(int i = 0; i < g_MLRecordCount; i++) {
        if(g_MLHistory[i].is_closed || !g_MLHistory[i].is_shadow) continue;

        // Stessa logica SL/TP (ATR o punti fissi) che userebbe un trade vero, cosi'
        // l'esito simulato resta coerente con InpUseATRStops. In modalita' ATR si usa
        // l'ATR REGISTRATO al momento del segnale (non quello attuale), per non
        // etichettare vecchi segnali con la volatilita' di oggi.
        double sl_distance, tp_distance;
        if(InpUseATRStops) {
            double atr = g_MLHistory[i].atr_at_signal;
            if(atr < EPSILON) continue;
            sl_distance = InpSLATRMultiplier * atr;
            tp_distance = InpTPATRMultiplier * atr;
        } else {
            sl_distance = InpSLPoints * g_SymbolCache.point;
            tp_distance = InpTPPoints * g_SymbolCache.point;
        }
        if(sl_distance <= 0 && tp_distance <= 0) continue;

        int signal_shift = iBarShift(_Symbol, _Period, g_MLHistory[i].time);
        if(signal_shift < 0) continue;

        double entry = g_MLHistory[i].entry_price;
        bool is_long = g_MLHistory[i].is_long;

        for(int j = signal_shift; j >= MathMax(0, signal_shift - 50); j--) {
            double h = iHigh(_Symbol, _Period, j);
            double l = iLow(_Symbol, _Period, j);
            if(h <= 0 || l <= 0) continue;
            bool hit = false;

            if(is_long) {
                if(tp_distance > 0 && h >= entry + tp_distance) { g_MLHistory[i].is_winner = true; hit = true; }
                else if(sl_distance > 0 && l <= entry - sl_distance) { g_MLHistory[i].is_winner = false; hit = true; }
            } else {
                if(tp_distance > 0 && l <= entry - tp_distance) { g_MLHistory[i].is_winner = true; hit = true; }
                else if(sl_distance > 0 && h >= entry + sl_distance) { g_MLHistory[i].is_winner = false; hit = true; }
            }

            if(hit) {
                g_MLHistory[i].is_closed = true;
                if(InpEnableMultiSymbol) UpdateMultiSymbolDB(g_MLHistory[i].symbol, g_MLHistory[i].is_winner);
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| TRADE OUTCOME TRACKING — esito REALE della posizione, non una      |
//| scansione forward nella storia dei prezzi. Riconciliazione        |
//| deterministica via DEAL_POSITION_ID (niente finestre temporali    |
//| fragili).                                                          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
    if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
    if(!HistoryDealSelect(trans.deal)) return;

    if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
    if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;

    ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
    if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

    long position_id = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
    double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                   + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                   + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

    for(int i = g_MLRecordCount - 1; i >= 0; i--) {
        if(g_MLHistory[i].is_closed) continue;
        if(g_MLHistory[i].position_id != position_id) continue;

        g_MLHistory[i].is_closed = true;
        g_MLHistory[i].is_winner = (profit > 0);
        if(g_MLHistory[i].is_winner) g_Stats.wins++; else g_Stats.losses++;
        g_Stats.total_profit += profit;

        if(InpEnableMultiSymbol) UpdateMultiSymbolDB(g_MLHistory[i].symbol, g_MLHistory[i].is_winner);

        if(SendNotifications)
            SendNotification(StringFormat("Posizione chiusa %s | P/L: %.2f", g_MLHistory[i].is_winner ? "WIN" : "LOSS", profit));

        break;
    }
}

//+------------------------------------------------------------------+
//| TRAILING STOP (ATR o punti fissi a seconda di InpUseATRStops,      |
//| scansione live delle posizioni)                                    |
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
    static datetime last_check = 0;
    datetime current = TimeCurrent();
    if(current == last_check) return;
    last_check = current;

    double activation, stop_dist, step_dist;
    if(InpUseATRStops) {
        double atr = g_Adaptive.atr_value;
        if(atr < EPSILON) return;
        activation = InpTrailingActivationATR * atr;
        stop_dist  = InpTrailingStopATR * atr;
        step_dist  = InpTrailingStepATR * atr;
    } else {
        activation = InpTrailingActivationPoints * g_SymbolCache.point;
        stop_dist  = InpTrailingStopPoints * g_SymbolCache.point;
        step_dist  = InpTrailingStepPoints * g_SymbolCache.point;
    }
    if(stop_dist <= 0) return; // trailing disabilitato di fatto (distanza nulla)

    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        ProcessTrailing(ticket, activation, stop_dist, step_dist);
    }
}

void ProcessTrailing(ulong ticket, double activation, double stop_dist, double step_dist)
{
    if(!PositionSelectByTicket(ticket)) return;

    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double posSL = PositionGetDouble(POSITION_SL);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double current = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    double profit = (type == POSITION_TYPE_BUY) ? (current - openPrice) : (openPrice - current);
    if(profit < activation) return;

    double newSL; bool shouldModify;
    if(type == POSITION_TYPE_BUY) {
        newSL = NormalizeDouble(current - stop_dist, g_SymbolCache.digits);
        shouldModify = (newSL > posSL + step_dist || posSL == 0);
    } else {
        newSL = NormalizeDouble(current + stop_dist, g_SymbolCache.digits);
        shouldModify = (newSL < posSL - step_dist || posSL == 0);
    }

    if(shouldModify) {
        MqlTradeRequest request = {};
        MqlTradeResult  result  = {};
        request.action   = TRADE_ACTION_SLTP;
        request.symbol    = _Symbol;
        request.position   = ticket;
        request.sl          = newSL;
        request.tp          = PositionGetDouble(POSITION_TP);
        if(!OrderSend(request, result)) g_Stats.order_errors++;
        else if(InpDebugMode && result.retcode == TRADE_RETCODE_DONE)
            PrintFormat("✅ Trailing aggiornato | Ticket:%I64u | New SL:%.5f", ticket, newSL);
    }
}

//+------------------------------------------------------------------+
//| WEIGHT PERSISTENCE (nome file stabile per simbolo)                 |
//+------------------------------------------------------------------+
void ExportWeightsToFile()
{
    string filename = StringFormat("VPEA_Weights_%s_%s.txt", _Symbol, TimeToString(TimeCurrent(), TIME_DATE));
    int handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_COMMON);
    if(handle == INVALID_HANDLE) {
        if(InpDebugMode) PrintFormat("❌ Export pesi fallito: %d", GetLastError());
        return;
    }

    FileWriteString(handle, "═══ VP EA v1.0 ML WEIGHTS EXPORT ═══\n");
    FileWriteString(handle, StringFormat("Symbol: %s | Date: %s\n", _Symbol, TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES)));
    FileWriteString(handle, StringFormat("Total Signals: %d | Best Accuracy: %.1f%%\n\n", g_Stats.total_signals, g_Stats.best_accuracy));

    for(int m = 0; m < NUM_MODELS; m++) {
        FileWriteString(handle, StringFormat("═══ MODEL: %s ═══\n", g_MLModels[m].name));
        FileWriteString(handle, StringFormat("Accuracy: %.1f%% | Precision: %.1f%% | Recall: %.1f%%\n", g_MLModels[m].accuracy, g_MLModels[m].precision, g_MLModels[m].recall));
        FileWriteString(handle, StringFormat("Bias: %.6f\n\n", g_MLModels[m].bias));
        for(int f = 0; f < ML_FEATURES; f++)
            FileWriteString(handle, StringFormat("%s: %.6f\n", g_FeatureNames[f], g_MLModels[m].feature_weights[f]));
        FileWriteString(handle, "\n");
    }

    FileClose(handle);
    if(InpDebugMode) PrintFormat("✅ Pesi esportati: %s", filename);
}

void BackupWeights()
{
    string filename = StringFormat("VPEA_Backup_%s.dat", _Symbol);
    int handle = FileOpen(filename, FILE_WRITE | FILE_BIN | FILE_COMMON);
    if(handle == INVALID_HANDLE) return;

    FileWriteInteger(handle, NUM_MODELS);
    for(int m = 0; m < NUM_MODELS; m++) {
        FileWriteString(handle, g_MLModels[m].name);
        for(int f = 0; f < ML_FEATURES; f++) FileWriteDouble(handle, g_MLModels[m].feature_weights[f]);
        FileWriteDouble(handle, g_MLModels[m].bias);
        FileWriteInteger(handle, g_MLModels[m].training_count);
        FileWriteDouble(handle, g_MLModels[m].accuracy);
        FileWriteDouble(handle, g_MLModels[m].precision);
        FileWriteDouble(handle, g_MLModels[m].recall);
    }
    FileClose(handle);
    if(InpDebugMode) PrintFormat("💾 Pesi salvati: %s", filename);
}

bool RestoreWeights(string filename)
{
    int handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
    if(handle == INVALID_HANDLE) return false;

    int num_models = FileReadInteger(handle);
    if(num_models != NUM_MODELS) { FileClose(handle); return false; }

    for(int m = 0; m < NUM_MODELS; m++) {
        g_MLModels[m].name = FileReadString(handle);
        for(int f = 0; f < ML_FEATURES; f++) g_MLModels[m].feature_weights[f] = FileReadDouble(handle);
        g_MLModels[m].bias = FileReadDouble(handle);
        g_MLModels[m].training_count = FileReadInteger(handle);
        g_MLModels[m].accuracy = FileReadDouble(handle);
        g_MLModels[m].precision = FileReadDouble(handle);
        g_MLModels[m].recall = FileReadDouble(handle);
    }
    FileClose(handle);
    return true;
}

void LoadWeightsFromFile()
{
    string filename = StringFormat("VPEA_Backup_%s.dat", _Symbol);
    if(FileIsExist(filename, FILE_COMMON)) {
        if(RestoreWeights(filename) && InpDebugMode) Print("✅ Pesi ML ricaricati da: ", filename);
    } else if(InpDebugMode) {
        Print("ℹ️ Nessun backup pesi trovato, parto dai pesi di default");
    }
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                          |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, int font_size, color clr, int corner)
{
    if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void UpdateDashboard()
{
    string prefix = g_UniqueID + "DASH_";
    int x = 10, y = 20, line_h = InpDashboardFontSize + 3, corner = InpDashboardCorner, line = 0;

    CreateLabel(prefix + "title", "═══ VP EA ML ENSEMBLE v1.0 ═══", x, y + (line++ * line_h), InpDashboardFontSize + 2, clrAqua, corner);
    line++;

    CreateLabel(prefix + "dst", StringFormat("DST:%s | Hull:%s(P%d)",
               (InpAutoDST && IsEEST_DST(TimeCurrent())) ? "ESTATE" : "INVERNO",
               InpUseHullFilter ? "ON" : "OFF", InpHullPeriod),
               x, y + (line++ * line_h), InpDashboardFontSize, clrSilver, corner);

    CreateLabel(prefix + "stopsmode", InpUseATRStops ?
               StringFormat("Stops: ATR (SL x%.1f / TP x%.1f)", InpSLATRMultiplier, InpTPATRMultiplier) :
               StringFormat("Stops: Punti (SL %d / TP %d)", InpSLPoints, InpTPPoints),
               x, y + (line++ * line_h), InpDashboardFontSize, clrSilver, corner);

    int buy = 0, sell = 0, total = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong t = PositionGetTicket(i);
        if(t <= 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
        total++;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) buy++; else sell++;
    }
    CreateLabel(prefix + "pos", StringFormat("Pos: %d/%d (B:%d S:%d)", total, MaxTotalPositions, buy, sell),
               x, y + (line++ * line_h), InpDashboardFontSize, clrWhite, corner);
    line++;

    double approval = (g_Stats.total_signals > 0) ? (double)g_Stats.ensemble_approved / g_Stats.total_signals * 100 : 0;
    CreateLabel(prefix + "sig", StringFormat("Signals:%d Approved:%d(%.1f%%) Rejected:%d",
               g_Stats.total_signals, g_Stats.ensemble_approved, approval, g_Stats.ensemble_rejected),
               x, y + (line++ * line_h), InpDashboardFontSize, clrWhite, corner);

    int closed = g_Stats.wins + g_Stats.losses;
    double wr = (closed > 0) ? (double)g_Stats.wins / closed * 100 : 0;
    color wr_c = (wr >= 65) ? clrLime : (wr >= 55 ? clrYellow : clrRed);
    CreateLabel(prefix + "wr", StringFormat("Win Rate:%.1f%% (%d/%d) | P/L:%.2f", wr, g_Stats.wins, closed, g_Stats.total_profit),
               x, y + (line++ * line_h), InpDashboardFontSize, wr_c, corner);
    line++;

    if(InpShowModelComparison) {
        CreateLabel(prefix + "mt", "MODEL COMPARISON:", x, y + (line++ * line_h), InpDashboardFontSize, clrOrange, corner);
        for(int m = 0; m < NUM_MODELS; m++)
            CreateLabel(prefix + "m" + IntegerToString(m), StringFormat("  %s: %.1f%%", g_MLModels[m].name, g_MLModels[m].accuracy),
                       x, y + (line++ * line_h), InpDashboardFontSize - 1, (g_MLModels[m].name == g_Stats.best_model) ? clrLime : clrWhite, corner);
        line++;
    }

    if(InpShowFeatureImportance) {
        CreateLabel(prefix + "ft", "TOP FEATURES:", x, y + (line++ * line_h), InpDashboardFontSize, clrOrange, corner);
        for(int f = 0; f < 5; f++)
            CreateLabel(prefix + "f" + IntegerToString(f), StringFormat("  %d.%s(%.1f%%)", f + 1, g_FeatureRanking[f].name, g_FeatureRanking[f].contribution),
                       x, y + (line++ * line_h), InpDashboardFontSize - 1, clrWhite, corner);
    }

    ChartRedraw();
}

void DeletePanelObjects()
{
    int total = ObjectsTotal(0, 0, -1);
    for(int i = total - 1; i >= 0; i--) {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, g_UniqueID) == 0) ObjectDelete(0, name);
    }
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| LOG                                                                 |
//+------------------------------------------------------------------+
void PrintInitInfo()
{
    Print("═══════════════════════════════════════════════════");
    Print("✅ VP EA ULTIMATE ML v1.0 INIZIALIZZATO (self-contained, no iCustom)");
    Print("═══════════════════════════════════════════════════");
    Print("Symbol: ", _Symbol, " | Period: ", EnumToString(_Period), " | Profile Mode: ", EnumToString(InpProfileMode));
    Print("Ensemble ML: ", InpEnableEnsemble ? "ON (3 modelli)" : "OFF (single model)", " | Threshold: ", InpMLThreshold, "%");
    Print("Hull Filter: ", InpUseHullFilter ? "ON" : "OFF", " (periodo ", InpHullPeriod, ")");
    if(InpUseATRStops)
        Print("SL/TP: ATR x", InpSLATRMultiplier, " / ATR x", InpTPATRMultiplier, " | Trailing: ATR x", InpTrailingStopATR, " (attiva a +", InpTrailingActivationATR, " ATR)");
    else
        Print("SL/TP: ", InpSLPoints, " / ", InpTPPoints, " punti | Trailing: ", InpTrailingStopPoints, " punti (attiva a +", InpTrailingActivationPoints, " punti)");
    Print("Lots: ", LotSize, UseFixedRisk ? " (Risk: " + DoubleToString(RiskPercent, 1) + "%)" : "");
    Print("Position Limits: Totale ", MaxTotalPositions, " | Per direzione ", MaxPositionsPerDirection);
    Print("Auto-DST: ", InpAutoDST ? "ON" : "OFF", " | DST attivo ora: ", IsEEST_DST(TimeCurrent()) ? "SI" : "NO");
    Print("═══════════════════════════════════════════════════");
}

void PrintStats()
{
    Print("═══════════════════════════════════════════════════");
    Print("📊 STATISTICHE FINALI — VP EA v1.0");
    Print("═══════════════════════════════════════════════════");
    Print("Segnali totali: ", g_Stats.total_signals, " | Approvati: ", g_Stats.ensemble_approved, " | Rifiutati: ", g_Stats.ensemble_rejected);
    Print("Trade eseguiti: ", g_Stats.total_trades, " (Long: ", g_Stats.long_trades, " | Short: ", g_Stats.short_trades, ")");
    int closed = g_Stats.wins + g_Stats.losses;
    if(closed > 0) Print("Win Rate: ", DoubleToString((double)g_Stats.wins / closed * 100, 1), "% (", g_Stats.wins, "W/", g_Stats.losses, "L)");
    Print("P/L totale: ", DoubleToString(g_Stats.total_profit, 2), " ", AccountInfoString(ACCOUNT_CURRENCY));
    Print("Best Model: ", g_Stats.best_model, " (", DoubleToString(g_Stats.best_accuracy, 1), "%)");
    Print("Errori ordine: ", g_Stats.order_errors);
    Print("═══════════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| END OF FILE                                                        |
//+------------------------------------------------------------------+
