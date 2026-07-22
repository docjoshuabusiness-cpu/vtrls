//+------------------------------------------------------------------+
//|          VolumeProfile_v9.2_ULTIMATE_ML_Sydney.mq5                |
//|    ENSEMBLE ML + DASHBOARD + EXPORT + MULTI-SYMBOL LEARNING       |
//|    v9.1: sessione Sydney + auto-DST FP Markets (EET/EEST)         |
//|    v9.2: fix bug indicizzazione ML outcomes (iBarShift vs array   |
//|    non-series), fix alert flood al primo load, ATR percentile     |
//|    reale (non piu' stub), multi-symbol learning agganciato,       |
//|    CountTouches corretto, filtro direzionale Hull MA embedded     |
//|    v9.2b: fix deadlock training ML — i segnali venivano registrati|
//|    per il training SOLO se gia' approvati dalla soglia ML; se lo  |
//|    score a freddo restava sotto soglia, l'ensemble non riceveva   |
//|    mai dati e non poteva mai allenarsi (Approved: 0% per sempre). |
//|    Ora si registra ogni segnale tecnicamente valido, approvato o  |
//|    no; solo la FRECCIA resta condizionata all'approvazione.       |
//|    v9.2c: fix oggetti grafici orfani — ID istanza ora stabile     |
//|    (non piu' basato su GetTickCount64) e pulizia oggetti eseguita |
//|    ad OGNI OnDeinit, non solo su REASON_REMOVE/CHARTCLOSE/        |
//|    CHARTCHANGE: prima, cambiando un qualunque input o riavviando  |
//|    il terminale, gli oggetti della sessione precedente restavano  |
//|    orfani per sempre (ID diverso ad ogni init) e andavano tolti a |
//|    mano.                                                          |
//+------------------------------------------------------------------+
#property copyright "Advanced Quant Systems - ULTIMATE v9.2"
#property version   "9.22"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   3

#property indicator_label1  "Long ML"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  4

#property indicator_label2  "Short ML"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  4

#property indicator_label3  "Hull Direction"
#property indicator_type3   DRAW_COLOR_LINE
#property indicator_color3  clrGray, clrLime, clrRed
#property indicator_width3  2

//=== PROFILE MODE ===
input group "═══ 📊 PROFILE MODE ═══"
enum ENUM_PROFILE_MODE {
    MODE_DAILY,
    MODE_WEEKLY,
    MODE_MONTHLY,
    MODE_SESSIONS
};
input ENUM_PROFILE_MODE InpProfileMode = MODE_DAILY; // Tipo di profilo: Daily/Weekly/Monthly/Sessions (Sydney+Asian+London+NY)

//=== DISPLAY ===
input group "═══ 🎨 DISPLAY ═══"
input bool InpShowOnlySignals = false;   // Se true nasconde il disegno del Volume Profile e mostra solo le frecce dei segnali
input bool InpShowPOC = true;            // Mostra la linea del Point of Control (prezzo a volume massimo)
input bool InpShowVAH = true;            // Mostra la linea Value Area High (bordo superiore area 70% volume)
input bool InpShowVAL = true;            // Mostra la linea Value Area Low (bordo inferiore area 70% volume)
input bool InpExtendLines = true;        // Estende POC/VAH/VAL fino al punto di mitigazione (primo tocco successivo)

//=== ULTIMATE ML SYSTEM ===
input group "═══ 🤖 ULTIMATE ML ═══"
input bool   InpEnableML = true;             // Abilita il filtro Machine Learning sui segnali
input double InpMLThreshold = 65.0;          // Soglia minima probabilità ensemble (%) per approvare un segnale
input int    InpMLTrainingPeriod = 500;      // Numero massimo di segnali storici mantenuti per il training
input bool   InpMLAdaptive = true;           // Se true riallena i modelli automaticamente ogni N segnali
input int    InpMLRetrainInterval = 100;     // Ogni quanti segnali chiusi forzare il retraining
input bool   InpShowMLScore = true;          // Mostra lo score ML negli alert
input bool   InpEnableEnsemble = true;       // Usa i 3 modelli in votazione invece di un solo modello
input bool   InpEnableMultiSymbol = true;    // Traccia accuratezza storica per simbolo (cross-asset learning)
input bool   InpAutoExportWeights = true;    // Esporta automaticamente i pesi ML su file
input int    InpExportInterval = 500;        // Ogni quanti segnali esportare i pesi

//=== ML DASHBOARD ===
input group "═══ 📊 ML DASHBOARD ═══"
input bool   InpShowMLDashboard = true;         // Mostra il pannello statistiche ML a schermo
input int    InpMLDashboardCorner = 1;          // Angolo pannello: 0=Alto Sx, 1=Alto Dx, 2=Basso Sx, 3=Basso Dx
input int    InpMLDashboardFontSize = 8;        // Dimensione font del pannello
input bool   InpShowFeatureImportance = true;   // Mostra il ranking delle feature più importanti
input bool   InpShowModelComparison = true;     // Mostra il confronto accuratezza tra i 3 modelli

//=== VOLUME PROFILE ===
input group "═══ 📈 VOLUME PROFILE ═══"
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT; // Timeframe usato per costruire il profilo volumi
input int InpPriceLevels = 100;          // Numero di livelli di prezzo (righe) del profilo, 50-200
input int InpHistoryPeriods = 20;        // Numero di profili storici da calcolare/disegnare
input double InpMaxWidthPercent = 50.0;  // Larghezza massima del profilo in % della durata della sessione
input double InpValueAreaPercent = 70.0; // % di volume incluso nella Value Area (standard 70%)
input bool InpUseRealVolume = true;      // Usa volume reale se il broker lo fornisce, altrimenti tick volume
input int InpBarGap = 1;                 // Spaziatura verticale tra le barre del profilo

//=== SESSION TIMES (FP Markets, ora SERVER — base ora SOLARE/inverno UTC+2) ===
input group "═══ 🕐 SESSIONS — FP Markets server time (base ora solare UTC+2) ═══"
input bool   InpAutoDST      = true;      // Se true, sposta automaticamente +1h tutte le sessioni durante l'ora legale EU (fine mar-fine ott), come fa il server FP Markets
input string InpSydneyStart  = "00:00";   // Apertura sessione Sydney (ora server, base inverno). Sessione a liquidità bassa, valuta AUD/NZD
input string InpSydneyEnd    = "09:00";   // Chiusura sessione Sydney (ora server, base inverno)
input string InpAsianStart   = "02:00";   // Apertura sessione Tokyo/Asian (ora server, base inverno)
input string InpAsianEnd     = "11:00";   // Chiusura sessione Tokyo/Asian (ora server, base inverno)
input string InpLondonStart  = "10:00";   // Apertura sessione London (ora server, base inverno). Sessione a liquidità più alta
input string InpLondonEnd    = "19:00";   // Chiusura sessione London (ora server, base inverno)
input string InpNewYorkStart = "15:00";   // Apertura sessione New York (ora server, base inverno). Overlap con London = massima volatilità
input string InpNewYorkEnd   = "00:00";   // Chiusura sessione New York (ora server, base inverno) — attraversa la mezzanotte

//=== SIGNAL LOGIC ===
input group "═══ 🎯 SIGNALS ═══"
input bool   InpEnableSignals = true;        // Abilita la generazione dei segnali long/short
input bool   InpStrictMode = true;           // Se true richiede prezzo sotto/sopra il POC oltre alla vicinanza a VAL/VAH
input double InpVADistance = 15.0;           // Distanza massima (in "pip" adattivi) dal livello VAL/VAH per considerare un tocco
input int    InpMinTouchBars = 3;            // Numero minimo di tocchi del livello richiesti prima di validare il segnale
input bool   InpRequireRejection = true;     // Richiede una candela di rigetto (wick) per validare il segnale
input double InpMinWickRatio = 0.3;          // Rapporto minimo wick/range della candela di rigetto (0-1)
input bool   InpOneSignalPerSession = true;  // Limita a un solo segnale long e uno short per sessione/profilo

//=== HULL MA DIRECTION FILTER ===
input group "═══ 🌊 HULL MA DIRECTION FILTER ═══"
input bool InpUseHullFilter = false;    // Se true, approva LONG solo se il prezzo del segnale è sopra la Hull MA e SHORT solo se è sotto (embedded, no iCustom)
input int  InpHullPeriod    = 20;       // Periodo della Hull MA usata come filtro di direzione (minimo 2)
input bool InpHullShowLine  = true;     // Disegna la linea Hull MA sul grafico (verde=salita, rosso=discesa)

//=== ADAPTIVE ===
input group "═══ 🧠 ADAPTIVE ═══"
input bool   InpAutoAdaptDistance = true;    // Adatta automaticamente la distanza di segnale in base all'ATR corrente
input bool   InpAutoAdaptArrows = true;      // Adatta automaticamente l'offset di disegno delle frecce in base all'ATR

//=== COLORS ===
input group "═══ 🎨 COLORS ═══"
input color InpDailyColor = clrDodgerBlue;      // Colore profilo modalità Daily
input color InpWeeklyColor = clrMediumPurple;   // Colore profilo modalità Weekly
input color InpMonthlyColor = clrGoldenrod;     // Colore profilo modalità Monthly
input color InpSydneyColor = C'70,130,180';     // Colore profilo sessione Sydney (SteelBlue)
input color InpAsianColor = C'138,43,226';      // Colore profilo sessione Asian/Tokyo
input color InpLondonColor = clrLimeGreen;      // Colore profilo sessione London
input color InpNewYorkColor = clrGold;          // Colore profilo sessione New York
input color InpPOCColor = clrRed;               // Colore linea POC
input color InpVAColor = clrOrange;             // Colore linee VAH/VAL
input int InpLineWidth = 2;                     // Spessore linee POC/VAH/VAL

//=== PERFORMANCE ===
input group "═══ ⚡ PERFORMANCE ═══"
input int    InpUpdateInterval = 60;   // Secondi minimi tra due ricalcoli completi dei profili
input bool   InpShowAlerts = true;     // Mostra un Alert() popup quando scatta un segnale approvato (solo su barra live, non in backfill storico)
input bool   InpDebugMode = false;     // Stampa log dettagliati nel tab Experts (usare solo in test)

//--- Constants
#define EPSILON 0.0000001
#define ARROW_LONG 233
#define ARROW_SHORT 234
#define MIN_BARS_REQUIRED 100
#define MAX_PROFILES 400
#define ML_FEATURES 12
#define NUM_MODELS 3  // Ensemble size
#define SESSIONS_PER_DAY 4  // Sydney + Asian + London + NewYork

//--- Buffers
double g_LongBuffer[];
double g_ShortBuffer[];
double g_HullBuffer[];
double g_HullColorBuffer[];

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
    datetime poc_mitigated;
    datetime vah_mitigated;
    datetime val_mitigated;
    int id;
    bool is_valid;

    void Reset() {
        start = 0; end = 0;
        high = 0; low = DBL_MAX;
        poc = 0; vah = 0; val = 0;
        total_vol = 0;
        poc_mitigated = 0; vah_mitigated = 0; val_mitigated = 0;
        is_valid = false;
        ArrayFree(nodes);
    }
    ~SSessionProfile() { ArrayFree(nodes); }
};

struct SSignalTracker {
    datetime session_start;
    bool long_fired;
    bool short_fired;
    void Reset() {
        session_start = 0;
        long_fired = false;
        short_fired = false;
    }
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
    datetime time;
    double entry_price;
    double atr_at_signal;  // ATR al momento del segnale (non l'ATR corrente) per un TP/SL coerente col regime di volatilità storico
    string symbol;  // For multi-symbol learning

    void Reset() {
        ZeroMemory(features);
        is_long = false;
        is_winner = false;
        is_closed = false;
        time = 0;
        entry_price = 0;
        atr_at_signal = 0;
        symbol = "";
    }
};

struct SMLModel {
    string name;
    double feature_weights[ML_FEATURES];
    double bias;
    int training_count;
    double accuracy;
    double precision;
    double recall;
    datetime last_train_time;
    int predictions_made;
    int correct_predictions;

    void Reset() {
        name = "";
        ArrayInitialize(feature_weights, 0);
        bias = 0;
        training_count = 0;
        accuracy = 0;
        precision = 0;
        recall = 0;
        last_train_time = 0;
        predictions_made = 0;
        correct_predictions = 0;
    }
};

struct SFeatureImportance {
    string name;
    double importance;
    double contribution;
};

struct SEnsembleVote {
    double model1_prob;
    double model2_prob;
    double model3_prob;
    double ensemble_prob;
    int model1_vote;
    int model2_vote;
    int model3_vote;
    int consensus;
};

struct SAdaptiveParams {
    double atr_value;
    double pip_value;
    double arrow_offset;
    double distance_multiplier;
    int decimals;

    void Calculate(string symbol, int atr_handle) {
        if(atr_handle != INVALID_HANDLE) {
            double atr[];
            ArraySetAsSeries(atr, true);
            if(CopyBuffer(atr_handle, 0, 0, 1, atr) > 0) {
                atr_value = atr[0];
            }
        }

        pip_value = SymbolInfoDouble(symbol, SYMBOL_POINT);
        decimals = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

        if(InpAutoAdaptDistance && atr_value > EPSILON) {
            distance_multiplier = NormalizeDouble(atr_value / (pip_value * 10), 2);
            distance_multiplier = MathMax(0.5, MathMin(distance_multiplier, 3.0));
        } else {
            distance_multiplier = 1.0;
        }

        if(InpAutoAdaptArrows) {
            arrow_offset = atr_value * 0.6;
        } else {
            arrow_offset = 25 * pip_value;
        }
    }
};

//--- Global Variables
SSessionProfile g_Profiles[];
SSignalTracker g_Signals[];
SMLRecord g_MLHistory[];
SMLModel g_MLModels[NUM_MODELS];  // Ensemble of 3 models
SFeatureImportance g_FeatureRanking[ML_FEATURES];
SAdaptiveParams g_Adaptive;
datetime g_LastUpdate = 0;
datetime g_LastBarTime = 0;
bool g_UseRealVolume = false;
string g_Prefix = "";
string g_UniqueID = "";
int g_TotalProfiles = 0;
bool g_IsInitialized = false;
int g_MLRecordCount = 0;
int g_SignalsSinceRetrain = 0;
int g_SignalsSinceExport = 0;
int g_ATRHandle = INVALID_HANDLE;  // Handle ATR condiviso: creato una volta in OnInit, riusato ovunque serva ATR

// Multi-symbol learning storage
struct SMultiSymbolData {
    string symbol;
    double avg_accuracy;
    int signal_count;
} g_MultiSymbolDB[];
int g_MultiSymbolCount = 0;

// ML Stats
struct SMLStats {
    int total_signals;
    int ensemble_approved;
    int ensemble_rejected;
    int unanimous_votes;
    int majority_votes;
    int split_votes;
    double avg_ensemble_score;
    int wins;
    int losses;
    double best_accuracy;
    string best_model;
} g_MLStats;

// Feature names for ranking
string g_FeatureNames[ML_FEATURES] = {
    "Distance", "Touches", "Rejection", "POC_Dist",
    "ATR", "TimeOfDay", "Volume", "Momentum",
    "EdgeDist", "Consecutive", "WickAsym", "VAWidth"
};

//+------------------------------------------------------------------+
//| Initialize                                                        |
//+------------------------------------------------------------------+
int OnInit()
{
    if(!ValidateInputs()) return INIT_PARAMETERS_INCORRECT;

    // ID STABILE (niente GetTickCount64): cosi' ogni nuova istanza puo' ritrovare e
    // ripulire gli oggetti lasciati da una precedente istanza sullo stesso grafico
    // (cambio parametri, ricompilazione, riavvio del terminale, run del tester...).
    // Con un ID casuale ad ogni init, CleanMyObjects() non trova mai gli oggetti
    // "vecchi" (prefisso diverso) e restano orfani finche' non li cancelli a mano.
    g_UniqueID = StringFormat("VP9_%s_%d_%d_", _Symbol, PeriodSeconds(_Period)/60, (int)InpProfileMode);

    SetIndexBuffer(0, g_LongBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, g_ShortBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, g_HullBuffer, INDICATOR_DATA);
    SetIndexBuffer(3, g_HullColorBuffer, INDICATOR_COLOR_INDEX);

    PlotIndexSetInteger(0, PLOT_ARROW, ARROW_LONG);
    PlotIndexSetInteger(1, PLOT_ARROW, ARROW_SHORT);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0);

    PlotIndexSetInteger(2, PLOT_DRAW_TYPE, InpHullShowLine ? DRAW_COLOR_LINE : DRAW_NONE);
    PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, InpHullPeriod);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    g_ATRHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
    if(g_ATRHandle == INVALID_HANDLE) {
        Print("❌ Errore creazione handle ATR: ", GetLastError());
        return INIT_FAILED;
    }

    g_Adaptive.Calculate(_Symbol, g_ATRHandle);

    g_UseRealVolume = false;
    if(InpUseRealVolume) {
        long vol = iVolume(_Symbol, PERIOD_CURRENT, 0);
        long tick = iTickVolume(_Symbol, PERIOD_CURRENT, 0);
        g_UseRealVolume = (vol > 0 && vol != tick);
    }

    g_TotalProfiles = InpHistoryPeriods;
    if(InpProfileMode == MODE_SESSIONS) g_TotalProfiles *= SESSIONS_PER_DAY; // 4 sessioni/giorno: Sydney+Asian+London+NY
    if(g_TotalProfiles > MAX_PROFILES) g_TotalProfiles = MAX_PROFILES;

    ArrayResize(g_Profiles, g_TotalProfiles);
    ArrayResize(g_Signals, g_TotalProfiles * 2);
    ArrayResize(g_MLHistory, InpMLTrainingPeriod);
    ArrayResize(g_MultiSymbolDB, 50);

    for(int i = 0; i < g_TotalProfiles; i++) {
        g_Profiles[i].Reset();
        g_Profiles[i].id = i;
    }

    for(int i = 0; i < ArraySize(g_Signals); i++) {
        g_Signals[i].Reset();
    }

    for(int i = 0; i < InpMLTrainingPeriod; i++) {
        g_MLHistory[i].Reset();
    }

    // Initialize ensemble models
    InitializeEnsembleModels();

    // Initialize feature ranking
    for(int i = 0; i < ML_FEATURES; i++) {
        g_FeatureRanking[i].name = g_FeatureNames[i];
        g_FeatureRanking[i].importance = 0;
        g_FeatureRanking[i].contribution = 0;
    }

    g_MLRecordCount = 0;
    g_SignalsSinceRetrain = 0;
    g_SignalsSinceExport = 0;
    g_MultiSymbolCount = 0;
    ZeroMemory(g_MLStats);

    switch(InpProfileMode) {
        case MODE_DAILY: g_Prefix = g_UniqueID + "D_"; break;
        case MODE_WEEKLY: g_Prefix = g_UniqueID + "W_"; break;
        case MODE_MONTHLY: g_Prefix = g_UniqueID + "M_"; break;
        case MODE_SESSIONS: g_Prefix = g_UniqueID + "S_"; break;
    }

    CleanMyObjects();

    // Load saved weights if available
    if(InpEnableML) {
        LoadWeightsFromFile();
    }

    g_LastUpdate = 0;
    g_LastBarTime = 0;
    g_IsInitialized = true;

    string mode_name = GetModeName();
    IndicatorSetString(INDICATOR_SHORTNAME,
        StringFormat("VP ULTIMATE %s [%s] ENS:%s DST:%s HULL:%s",
                    mode_name, _Symbol, InpEnableEnsemble ? "ON" : "OFF",
                    (InpAutoDST && IsEEST_DST(TimeCurrent())) ? "SUMMER" : "WINTER",
                    InpUseHullFilter ? "ON" : "OFF"));

    if(InpDebugMode) {
        PrintFormat("═══ VP v9.2 ULTIMATE ML INIT ═══");
        PrintFormat("Symbol: %s | Ensemble: %d models | Multi-Symbol: %s",
                   _Symbol, NUM_MODELS, InpEnableMultiSymbol ? "ON" : "OFF");
        PrintFormat("ML Threshold: %.1f%% | Auto-Export: %s",
                   InpMLThreshold, InpAutoExportWeights ? "YES" : "NO");
        PrintFormat("Auto-DST: %s | DST attivo ora: %s",
                   InpAutoDST ? "ON" : "OFF", IsEEST_DST(TimeCurrent()) ? "SI (+1h)" : "NO");
        PrintFormat("Hull Filter: %s | Period: %d | Show Line: %s",
                   InpUseHullFilter ? "ON" : "OFF", InpHullPeriod, InpHullShowLine ? "YES" : "NO");
    }

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Validate inputs                                                   |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
    bool valid = true;

    if(InpPriceLevels < 50 || InpPriceLevels > 200) {
        Print("❌ Price Levels: 50-200"); valid = false;
    }
    if(InpMLThreshold < 50 || InpMLThreshold > 95) {
        Print("❌ ML Threshold: 50-95%"); valid = false;
    }
    if(InpMLTrainingPeriod < 50 || InpMLTrainingPeriod > 2000) {
        Print("❌ ML Training Period: 50-2000"); valid = false;
    }
    if(InpHullPeriod < 2) {
        Print("❌ Hull Period: minimo 2"); valid = false;
    }
    if(InpValueAreaPercent <= 0 || InpValueAreaPercent > 100) {
        Print("❌ Value Area Percent: 1-100"); valid = false;
    }
    if(InpMinTouchBars < 1) {
        Print("❌ Min Touch Bars: minimo 1"); valid = false;
    }

    return valid;
}

//+------------------------------------------------------------------+
//| Initialize ensemble models                                        |
//+------------------------------------------------------------------+
void InitializeEnsembleModels()
{
    // Model 1: Conservative (high rejection weight)
    g_MLModels[0].name = "Conservative";
    g_MLModels[0].feature_weights[0] = 0.12;  // distance
    g_MLModels[0].feature_weights[1] = 0.10;  // touches
    g_MLModels[0].feature_weights[2] = 0.25;  // rejection (HIGH)
    g_MLModels[0].feature_weights[3] = 0.12;  // poc_distance
    g_MLModels[0].feature_weights[4] = 0.08;  // atr
    g_MLModels[0].feature_weights[5] = 0.06;  // time
    g_MLModels[0].feature_weights[6] = 0.07;  // volume
    g_MLModels[0].feature_weights[7] = 0.06;  // momentum
    g_MLModels[0].feature_weights[8] = 0.05;  // edge
    g_MLModels[0].feature_weights[9] = 0.04;  // consecutive
    g_MLModels[0].feature_weights[10] = 0.03; // wick_asym
    g_MLModels[0].feature_weights[11] = 0.02; // va_width
    g_MLModels[0].bias = 0.3;

    // Model 2: Balanced (equal weights)
    g_MLModels[1].name = "Balanced";
    for(int i = 0; i < ML_FEATURES; i++) {
        g_MLModels[1].feature_weights[i] = 1.0 / ML_FEATURES;
    }
    g_MLModels[1].bias = 0.5;

    // Model 3: Aggressive (distance + touches)
    g_MLModels[2].name = "Aggressive";
    g_MLModels[2].feature_weights[0] = 0.20;  // distance (HIGH)
    g_MLModels[2].feature_weights[1] = 0.18;  // touches (HIGH)
    g_MLModels[2].feature_weights[2] = 0.10;  // rejection
    g_MLModels[2].feature_weights[3] = 0.12;  // poc_distance
    g_MLModels[2].feature_weights[4] = 0.10;  // atr
    g_MLModels[2].feature_weights[5] = 0.08;  // time
    g_MLModels[2].feature_weights[6] = 0.06;  // volume
    g_MLModels[2].feature_weights[7] = 0.08;  // momentum
    g_MLModels[2].feature_weights[8] = 0.04;  // edge
    g_MLModels[2].feature_weights[9] = 0.02;  // consecutive
    g_MLModels[2].feature_weights[10] = 0.01; // wick_asym
    g_MLModels[2].feature_weights[11] = 0.01; // va_width
    g_MLModels[2].bias = 0.6;

    for(int i = 0; i < NUM_MODELS; i++) {
        g_MLModels[i].training_count = 0;
        g_MLModels[i].accuracy = 0;
        g_MLModels[i].precision = 0;
        g_MLModels[i].recall = 0;
        g_MLModels[i].last_train_time = TimeCurrent();
        g_MLModels[i].predictions_made = 0;
        g_MLModels[i].correct_predictions = 0;
    }

    if(InpDebugMode) {
        Print("✓ Initialized 3-model ensemble: Conservative, Balanced, Aggressive");
    }
}

//+------------------------------------------------------------------+
//| Get mode name                                                     |
//+------------------------------------------------------------------+
string GetModeName()
{
    switch(InpProfileMode) {
        case MODE_DAILY: return "DAILY";
        case MODE_WEEKLY: return "WEEKLY";
        case MODE_MONTHLY: return "MONTHLY";
        case MODE_SESSIONS: return "SESSIONS";
        default: return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| DST helper — regola EU/EET: ora legale da ultima domenica di      |
//| marzo a ultima domenica di ottobre. FP Markets (Athens/Bucharest) |
//| segue questa regola, quindi qui replichiamo la logica del server. |
//| NB: approssimazione a livello di giorno (non all'ora esatta di    |
//| transizione, 01:00 UTC) — sufficiente per l'uso operativo.        |
//| ATTENZIONE: verifica comunque il calendario DST reale del tuo     |
//| server (non tutti i broker seguono il calendario EU).             |
//+------------------------------------------------------------------+
datetime LastSundayOfMonth(int year, int month)
{
    MqlDateTime dt;
    ZeroMemory(dt);
    dt.year = year; dt.mon = month; dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;

    // Ultimo giorno del mese
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
    int day_of_week = dt.day_of_week; // 0=Domenica
    int offset = day_of_week; // giorni da sottrarre per arrivare alla domenica precedente/coincidente
    return last_day - (offset * 86400);
}

bool IsEEST_DST(datetime t)
{
    MqlDateTime dt;
    TimeToStruct(t, dt);

    datetime dst_start = LastSundayOfMonth(dt.year, 3);   // ultima domenica di marzo
    datetime dst_end   = LastSundayOfMonth(dt.year, 10);  // ultima domenica di ottobre

    return (t >= dst_start && t < dst_end);
}

//+------------------------------------------------------------------+
//| HULL MOVING AVERAGE — embedded direttamente (NO iCustom).         |
//| Stessa logica del Triple Hull MA fornito: HMA = WMA_sqrt(N)(       |
//| 2*WMA_N/2(price) - WMA_N(price)). Usata come filtro di direzione   |
//| POSIZIONALE (non di pendenza): quando scatta un segnale VP si      |
//| guarda dove sta il prezzo rispetto alla Hull in quel preciso bar — |
//| Hull sotto il prezzo → solo LONG ammessi, Hull sopra il prezzo →   |
//| solo SHORT ammessi (quando InpUseHullFilter=true).                 |
//+------------------------------------------------------------------+
double HullWMA(const double &data[], int pos, int period)
{
    double sum = 0;
    int weightSum = 0;
    for(int i = 0; i < period; i++) {
        int idx = pos - i;
        if(idx < 0) break;
        int weight = period - i;
        sum += data[idx] * weight;
        weightSum += weight;
    }
    return (weightSum == 0) ? 0 : sum / weightSum;
}

void CalculateHullSeries(const double &price[], int rates_total, int start, int period,
                        double &hmaBuf[], double &colorBuf[])
{
    if(period < 2) return;
    int halfPeriod = period / 2;
    int sqrtPeriod = (int)MathSqrt(period);

    for(int i = start; i < rates_total; i++) {
        if(i - period + 1 < 0) {
            hmaBuf[i] = EMPTY_VALUE;
            colorBuf[i] = 0;
            continue;
        }

        // WMA di lunghezza sqrtPeriod applicata alla serie "2*WMA_half - WMA_full"
        double sum = 0;
        int wsum = 0;
        for(int j = 0; j < sqrtPeriod; j++) {
            int idx = i - j;
            if(idx - period + 1 < 0) break;
            double wmaHalf_j = HullWMA(price, idx, halfPeriod);
            double wmaFull_j = HullWMA(price, idx, period);
            double diff_j = 2.0 * wmaHalf_j - wmaFull_j;

            int weight = sqrtPeriod - j;
            sum += diff_j * weight;
            wsum += weight;
        }
        hmaBuf[i] = (wsum == 0) ? EMPTY_VALUE : sum / wsum;

        if(i > 0 && hmaBuf[i] != EMPTY_VALUE && hmaBuf[i - 1] != EMPTY_VALUE)
            colorBuf[i] = (hmaBuf[i] > hmaBuf[i - 1]) ? 1 : 2;
        else
            colorBuf[i] = 0;
    }
}

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    if(!g_IsInitialized || rates_total < MIN_BARS_REQUIRED) return 0;

    datetime current = TimeCurrent();
    bool is_new_bar = (time[rates_total - 1] != g_LastBarTime);
    bool is_first_run = (prev_calculated == 0);

    if(is_first_run || is_new_bar || (current - g_LastUpdate >= InpUpdateInterval)) {
        UpdateProfiles();
        g_LastUpdate = current;
        if(is_new_bar) g_LastBarTime = time[rates_total - 1];
    }

    int start = prev_calculated - 1;
    if(is_first_run) {
        ArrayInitialize(g_LongBuffer, 0);
        ArrayInitialize(g_ShortBuffer, 0);
        ArrayInitialize(g_HullBuffer, EMPTY_VALUE);
        ArrayInitialize(g_HullColorBuffer, 0);
        start = MIN_BARS_REQUIRED;
    }

    if(start < MIN_BARS_REQUIRED) start = MIN_BARS_REQUIRED;

    if(InpUseHullFilter || InpHullShowLine) {
        CalculateHullSeries(close, rates_total, start, InpHullPeriod, g_HullBuffer, g_HullColorBuffer);
    }

    if(InpEnableSignals) {
        for(int i = start; i < rates_total; i++) {
            g_LongBuffer[i] = 0;
            g_ShortBuffer[i] = 0;
            // Alert() solo sulla barra corrente/appena chiusa: evita flood di popup
            // storici quando l'indicatore viene caricato per la prima volta su un
            // grafico con anni di storico (i segnali vengono comunque registrati
            // per il training ML anche in backfill, solo l'Alert() viene silenziato).
            bool allow_alert = (i >= rates_total - 2);
            ProcessSignals(i, time, open, high, low, close, rates_total, allow_alert);
        }
    }

    // Update ML outcomes
    UpdateMLOutcomes();

    // Retrain if needed
    if(InpEnableML && InpMLAdaptive && g_SignalsSinceRetrain >= InpMLRetrainInterval) {
        TrainEnsembleModels();
        UpdateFeatureImportance();
        g_SignalsSinceRetrain = 0;
    }

    // Export weights if needed
    if(InpAutoExportWeights && g_SignalsSinceExport >= InpExportInterval) {
        ExportWeightsToFile();
        g_SignalsSinceExport = 0;
    }

    // Draw ML dashboard
    if(InpShowMLDashboard) {
        DrawMLDashboard();
    }

    return rates_total;
}

//+------------------------------------------------------------------+
//| Process signals WITH ENSEMBLE ML                                 |
//+------------------------------------------------------------------+
void ProcessSignals(int bar, const datetime &time[], const double &open[],
                   const double &high[], const double &low[], const double &close[],
                   int rates_total, bool allow_alert)
{
    if(bar >= rates_total - 1 || bar < InpMinTouchBars) return;

    for(int p = 0; p < g_TotalProfiles; p++) {
        if(!g_Profiles[p].is_valid) continue;
        if(time[bar] >= g_Profiles[p].start && time[bar] <= g_Profiles[p].end) {
            CheckSignalEnsemble(bar, time, open, high, low, close, g_Profiles[p], rates_total, allow_alert);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Check signal with ENSEMBLE voting                                |
//+------------------------------------------------------------------+
void CheckSignalEnsemble(int bar, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[],
                SSessionProfile &profile, int rates_total, bool allow_alert)
{
    if(!profile.is_valid || bar < InpMinTouchBars) return;

    double price = close[bar];
    double pip = g_Adaptive.pip_value * 10;
    double effective_distance = InpVADistance * g_Adaptive.distance_multiplier;

    // Filtro di direzione Hull MA (posizionale, valutato sul bar del segnale):
    // Hull sotto il prezzo → solo LONG ammessi; Hull sopra il prezzo → solo SHORT ammessi.
    bool hull_ok_long = true;
    bool hull_ok_short = true;
    if(InpUseHullFilter) {
        int hsz = ArraySize(g_HullBuffer);
        if(bar < 0 || bar >= hsz || g_HullBuffer[bar] == EMPTY_VALUE) {
            hull_ok_long = false;
            hull_ok_short = false;
        } else {
            hull_ok_long = (price > g_HullBuffer[bar]);   // Hull sotto il prezzo -> BUY
            hull_ok_short = (price < g_HullBuffer[bar]);  // Hull sopra il prezzo -> SELL
        }
    }

    // Check LONG
    double dist_val = MathAbs(price - profile.val);
    bool near_val = (dist_val <= (effective_distance * pip));
    bool below_poc = !InpStrictMode || (price < profile.poc);

    if(near_val && below_poc && hull_ok_long) {
        int touches = CountTouches(bar, close, profile.val, effective_distance * pip);
        double rejection = CalculateBullishRejection(bar, open, high, low, close);

        if(InpRequireRejection && rejection < InpMinWickRatio) return;
        if(touches < InpMinTouchBars) return;

        SMLFeatures features = ExtractFeatures(bar, true, time, open, high, low, close,
                                              profile, dist_val, touches, rejection, rates_total);

        // ENSEMBLE VOTING
        SEnsembleVote vote = GetEnsembleVote(features);

        g_MLStats.total_signals++;
        g_MLStats.avg_ensemble_score = (g_MLStats.avg_ensemble_score * (g_MLStats.total_signals - 1) + vote.ensemble_prob) / g_MLStats.total_signals;

        // Track vote type
        if(vote.consensus == 3) g_MLStats.unanimous_votes++;
        else if(vote.consensus == 2) g_MLStats.majority_votes++;
        else g_MLStats.split_votes++;

        // FIX v9.2b: registra SEMPRE il segnale tecnicamente valido per il training,
        // indipendentemente dall'approvazione ML. Prima RecordMLSignal veniva chiamato
        // solo per i segnali APPROVATI: se lo score iniziale (pesi hardcoded, mai
        // allenati) resta sotto soglia, nessun segnale viene mai registrato, quindi
        // TrainEnsembleModels() non parte mai (richiede >=20 chiusi), i pesi non
        // cambiano mai e lo score medio resta bloccato sotto soglia per sempre —
        // un deadlock che impedisce all'ensemble di imparare. Registrando comunque,
        // il training può avvenire anche sui segnali rifiutati.
        RecordMLSignal(features, true, time[bar], price);

        // ML Filter
        if(vote.ensemble_prob < InpMLThreshold) {
            g_MLStats.ensemble_rejected++;
            if(InpDebugMode) {
                PrintFormat("❌ LONG REJECTED | ENS: %.1f%% | Votes: %d/%d/%d",
                           vote.ensemble_prob, vote.model1_vote, vote.model2_vote, vote.model3_vote);
            }
            return;
        }

        g_MLStats.ensemble_approved++;

        bool can_fire = true;
        if(InpOneSignalPerSession) {
            for(int i = 0; i < ArraySize(g_Signals); i++) {
                if(g_Signals[i].session_start == profile.start && g_Signals[i].long_fired) {
                    can_fire = false;
                    break;
                }
            }
        }

        if(can_fire) {
            g_LongBuffer[bar] = low[bar] - g_Adaptive.arrow_offset;

            if(InpShowAlerts && allow_alert) {
                string alert_msg = StringFormat("🟢 LONG | %s | %.5f", _Symbol, price);
                if(InpShowMLScore) {
                    alert_msg += StringFormat(" | ENS: %.1f%% [%d-%d-%d]",
                                            vote.ensemble_prob, vote.model1_vote, vote.model2_vote, vote.model3_vote);
                }
                Alert(alert_msg);
            }

            if(InpOneSignalPerSession) UpdateSignalTracker(profile.start, true, false);

            if(InpDebugMode) {
                PrintFormat("✅ LONG APPROVED | ENS: %.1f%% | M1: %.1f | M2: %.1f | M3: %.1f",
                           vote.ensemble_prob, vote.model1_prob, vote.model2_prob, vote.model3_prob);
            }
        }
    }

    // Check SHORT
    double dist_vah = MathAbs(price - profile.vah);
    bool near_vah = (dist_vah <= (effective_distance * pip));
    bool above_poc = !InpStrictMode || (price > profile.poc);

    if(near_vah && above_poc && hull_ok_short) {
        int touches = CountTouches(bar, close, profile.vah, effective_distance * pip);
        double rejection = CalculateBearishRejection(bar, open, high, low, close);

        if(InpRequireRejection && rejection < InpMinWickRatio) return;
        if(touches < InpMinTouchBars) return;

        SMLFeatures features = ExtractFeatures(bar, false, time, open, high, low, close,
                                              profile, dist_vah, touches, rejection, rates_total);

        SEnsembleVote vote = GetEnsembleVote(features);

        g_MLStats.total_signals++;
        g_MLStats.avg_ensemble_score = (g_MLStats.avg_ensemble_score * (g_MLStats.total_signals - 1) + vote.ensemble_prob) / g_MLStats.total_signals;

        // Track vote type
        if(vote.consensus == 3) g_MLStats.unanimous_votes++;
        else if(vote.consensus == 2) g_MLStats.majority_votes++;
        else g_MLStats.split_votes++;

        // FIX v9.2b: vedi commento nel blocco LONG — registra sempre, indipendentemente
        // dall'approvazione, per evitare il deadlock di training.
        RecordMLSignal(features, false, time[bar], price);

        // ML Filter per SHORT
        if(vote.ensemble_prob < InpMLThreshold) {
            g_MLStats.ensemble_rejected++;
            if(InpDebugMode) {
                PrintFormat("❌ SHORT REJECTED | ENS: %.1f%% | Votes: %d/%d/%d",
                           vote.ensemble_prob, vote.model1_vote, vote.model2_vote, vote.model3_vote);
            }
            return;
        }

        g_MLStats.ensemble_approved++;

        bool can_fire = true;
        if(InpOneSignalPerSession) {
            for(int i = 0; i < ArraySize(g_Signals); i++) {
                if(g_Signals[i].session_start == profile.start && g_Signals[i].short_fired) {
                    can_fire = false;
                    break;
                }
            }
        }

        if(can_fire) {
            g_ShortBuffer[bar] = high[bar] + g_Adaptive.arrow_offset;

            if(InpShowAlerts && allow_alert) {
                string alert_msg = StringFormat("🔴 SHORT | %s | %.5f", _Symbol, price);
                if(InpShowMLScore) {
                    alert_msg += StringFormat(" | ENS: %.1f%% [%d-%d-%d]",
                                            vote.ensemble_prob, vote.model1_vote, vote.model2_vote, vote.model3_vote);
                }
                Alert(alert_msg);
            }

            if(InpOneSignalPerSession) UpdateSignalTracker(profile.start, false, true);

            if(InpDebugMode) {
                PrintFormat("✅ SHORT APPROVED | ENS: %.1f%% | M1: %.1f | M2: %.1f | M3: %.1f",
                           vote.ensemble_prob, vote.model1_prob, vote.model2_prob, vote.model3_prob);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get ensemble vote                                                 |
//+------------------------------------------------------------------+
SEnsembleVote GetEnsembleVote(SMLFeatures &features)
{
    SEnsembleVote vote;

    if(InpEnableEnsemble) {
        // Get probability from each model
        vote.model1_prob = PredictProbability(features, 0);
        vote.model2_prob = PredictProbability(features, 1);
        vote.model3_prob = PredictProbability(features, 2);

        // Binary votes (1 = approve, 0 = reject)
        vote.model1_vote = (vote.model1_prob >= InpMLThreshold) ? 1 : 0;
        vote.model2_vote = (vote.model2_prob >= InpMLThreshold) ? 1 : 0;
        vote.model3_vote = (vote.model3_prob >= InpMLThreshold) ? 1 : 0;

        // Consensus count
        vote.consensus = vote.model1_vote + vote.model2_vote + vote.model3_vote;

        // Ensemble probability (weighted average)
        vote.ensemble_prob = (vote.model1_prob * 0.35 +  // Conservative has more weight
                             vote.model2_prob * 0.30 +
                             vote.model3_prob * 0.35);
    } else {
        // Single model fallback
        vote.model1_prob = PredictProbability(features, 0);
        vote.model2_prob = 0;
        vote.model3_prob = 0;
        vote.ensemble_prob = vote.model1_prob;
        vote.model1_vote = (vote.model1_prob >= InpMLThreshold) ? 1 : 0;
        vote.model2_vote = 0;
        vote.model3_vote = 0;
        vote.consensus = vote.model1_vote;
    }

    // Cross-asset learning: pesa leggermente l'ensemble in base all'accuratezza storica
    // di QUESTO simbolo (se ne abbiamo abbastanza dati). Effetto limitato a ±15% per non
    // far dominare una singola metrica di poche osservazioni.
    if(InpEnableMultiSymbol) {
        double sym_weight = GetSymbolWeight(_Symbol);
        double adj = 0.85 + 0.30 * sym_weight;
        vote.ensemble_prob = MathMin(vote.ensemble_prob * adj, 100.0);
    }

    return vote;
}

//+------------------------------------------------------------------+
//| Predict probability using specific model                         |
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

//+------------------------------------------------------------------+
//| Count touches — finestra di lookback svincolata da InpMinTouchBars|
//| (prima la finestra coincideva col minimo richiesto, rendendo il   |
//| filtro quasi impossibile da soddisfare: serviva che OGNI barra    |
//| della finestra toccasse il livello).                              |
//+------------------------------------------------------------------+
int CountTouches(int bar, const double &close[], double level, double threshold)
{
    int touches = 0;
    int lookback = MathMax(InpMinTouchBars * 4, 12);
    for(int i = 1; i <= lookback && (bar - i) >= 0; i++) {
        if(MathAbs(close[bar - i] - level) <= threshold * 1.5) touches++;
    }
    return touches;
}

//+------------------------------------------------------------------+
//| Extract features                                                  |
//+------------------------------------------------------------------+
SMLFeatures ExtractFeatures(int bar, bool is_long, const datetime &time[],
                           const double &open[], const double &high[],
                           const double &low[], const double &close[],
                           SSessionProfile &profile, double distance,
                           int touches, double rejection, int rates_total)
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

    // bar è indice non-series (0=più vecchio) di OnCalculate; le funzioni basate su
    // CopyBuffer/iBarShift lavorano in shift (0=corrente), quindi va convertito.
    f.atr_percentile = CalculateATRPercentileAdvanced(rates_total - 1 - bar);
    f.time_of_day = CalculateTimeScore(time[bar]);
    f.volume_quality = (profile.total_vol > 0) ? MathMin(profile.total_vol / 1000000.0, 1.0) : 0.5;
    f.price_momentum = CalculateMomentum(bar, close, 3);

    double dist_high = MathAbs(close[bar] - profile.high);
    double dist_low = MathAbs(close[bar] - profile.low);
    double profile_range = profile.high - profile.low;
    double min_edge_dist = MathMin(dist_high, dist_low);
    f.edge_distance = (profile_range > EPSILON) ? min_edge_dist / profile_range : 0.5;

    f.consecutive_touches = CountConsecutiveTouches(bar, close, target_price, pip * 20);
    f.wick_asymmetry = CalculateWickAsymmetry(bar, open, high, low, close);
    f.va_width_ratio = (profile_range > EPSILON) ?
                       MathMin((profile.vah - profile.val) / profile_range, 1.0) : 0.5;

    return f;
}

//+------------------------------------------------------------------+
//| Time score — allineato all'overlap London/NY, DST-aware.          |
//| L'overlap London-NY (massima liquidità storicamente documentata)  |
//| in ora server FP Markets è: 16:00-20:00 (estate) / 15:00-19:00    |
//| (inverno). Fuori overlap ma dentro London/NY = buono. Sydney/     |
//| Asian = liquidità strutturalmente più bassa.                      |
//+------------------------------------------------------------------+
double CalculateTimeScore(datetime dt) {
    MqlDateTime mdt;
    TimeToStruct(dt, mdt);
    int hour = mdt.hour;

    bool dst = InpAutoDST && IsEEST_DST(dt);
    int london_start   = dst ? 11 : 10;
    int overlap_start  = dst ? 16 : 15;
    int overlap_end    = dst ? 20 : 19;
    int ny_end          = dst ? 1  : 0;  // NY chiude dopo mezzanotte

    if(hour >= overlap_start && hour < overlap_end) return 1.0;              // overlap London-NY: massima liquidità
    if(hour >= london_start && hour < overlap_start) return 0.85;            // solo London
    if(hour >= overlap_end || hour < ny_end)          return 0.70;           // solo NY (post overlap, con wrap mezzanotte)
    return 0.35;                                                              // Sydney/Asian: liquidità bassa
}

double CalculateMomentum(int bar, const double &close[], int period) {
    if(bar < period) return 0;
    double roc = (close[bar] - close[bar - period]) / close[bar - period];
    return MathMin(MathMax(roc * 100, -1.0), 1.0);
}

int CountConsecutiveTouches(int bar, const double &close[], double level, double threshold) {
    int count = 0;
    for(int i = 1; i <= 10 && (bar - i) >= 0; i++) {
        if(MathAbs(close[bar - i] - level) <= threshold) count++;
        else break;
    }
    return count;
}

double CalculateWickAsymmetry(int bar, const double &open[], const double &high[],
                             const double &low[], const double &close[]) {
    double total = high[bar] - low[bar];
    if(total < EPSILON) return 0;
    double upper_wick = high[bar] - MathMax(open[bar], close[bar]);
    double lower_wick = MathMin(open[bar], close[bar]) - low[bar];
    return (upper_wick - lower_wick) / total;
}

double CalculateBullishRejection(int bar, const double &open[], const double &high[],
                          const double &low[], const double &close[]) {
    if(bar < 1) return 0;
    double total = high[bar] - low[bar];
    if(total < EPSILON) return 0;
    return (MathMin(open[bar], close[bar]) - low[bar]) / total;
}

double CalculateBearishRejection(int bar, const double &open[], const double &high[],
                          const double &low[], const double &close[]) {
    if(bar < 1) return 0;
    double total = high[bar] - low[bar];
    if(total < EPSILON) return 0;
    return (high[bar] - MathMax(open[bar], close[bar])) / total;
}

//+------------------------------------------------------------------+
//| Record ML signal                                                  |
//+------------------------------------------------------------------+
void RecordMLSignal(SMLFeatures &features, bool is_long, datetime time, double price)
{
    if(g_MLRecordCount >= InpMLTrainingPeriod) {
        for(int i = 0; i < InpMLTrainingPeriod - 1; i++) {
            g_MLHistory[i] = g_MLHistory[i + 1];
        }
        g_MLRecordCount = InpMLTrainingPeriod - 1;
    }

    g_MLHistory[g_MLRecordCount].features = features;
    g_MLHistory[g_MLRecordCount].is_long = is_long;
    g_MLHistory[g_MLRecordCount].time = time;
    g_MLHistory[g_MLRecordCount].entry_price = price;
    g_MLHistory[g_MLRecordCount].atr_at_signal = g_Adaptive.atr_value;
    g_MLHistory[g_MLRecordCount].is_closed = false;
    g_MLHistory[g_MLRecordCount].symbol = _Symbol;

    g_MLRecordCount++;
    g_SignalsSinceRetrain++;
    g_SignalsSinceExport++;
}

//+------------------------------------------------------------------+
//| Update ML outcomes                                                |
//| FIX v9.2: la versione precedente usava iBarShift() (convenzione   |
//| "shift", indice 0 = barra corrente) per indicizzare direttamente  |
//| gli array high[]/low[] di OnCalculate, che invece sono non-series |
//| (indice 0 = barra più vecchia). I due indici puntavano a barre    |
//| completamente diverse: il win/loss di ogni segnale veniva         |
//| etichettato su prezzo storico casuale, corrompendo il training.   |
//| Ora si usano iHigh()/iLow() con shift esplicito (stessa            |
//| convenzione di iBarShift), coerente e corretto.                   |
//+------------------------------------------------------------------+
void UpdateMLOutcomes()
{
    for(int i = 0; i < g_MLRecordCount; i++) {
        if(g_MLHistory[i].is_closed) continue;

        double atr = g_MLHistory[i].atr_at_signal;
        if(atr < EPSILON) continue;

        int signal_shift = iBarShift(_Symbol, _Period, g_MLHistory[i].time);
        if(signal_shift < 0) continue;

        double entry = g_MLHistory[i].entry_price;
        bool is_long = g_MLHistory[i].is_long;

        for(int j = signal_shift; j >= MathMax(0, signal_shift - 50); j--) {
            double h = iHigh(_Symbol, _Period, j);
            double l = iLow(_Symbol, _Period, j);
            bool hit = false;

            if(is_long) {
                if(h >= entry + (atr * 2.0)) { g_MLHistory[i].is_winner = true; hit = true; }
                else if(l <= entry - atr) { g_MLHistory[i].is_winner = false; hit = true; }
            } else {
                if(l <= entry - (atr * 2.0)) { g_MLHistory[i].is_winner = true; hit = true; }
                else if(h >= entry + atr) { g_MLHistory[i].is_winner = false; hit = true; }
            }

            if(hit) {
                g_MLHistory[i].is_closed = true;
                if(g_MLHistory[i].is_winner) g_MLStats.wins++; else g_MLStats.losses++;
                if(InpEnableMultiSymbol) UpdateMultiSymbolDB(g_MLHistory[i].symbol, g_MLHistory[i].is_winner);
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Train ensemble models                                             |
//| NB metodologico: singolo passaggio SGD (learning_rate=0.01) su    |
//| tutto il dataset chiuso, senza train/test split. L'accuracy        |
//| riportata è quindi in-sample e va presa come indicatore di         |
//| tendenza, non come stima affidabile di edge reale. Per validazione |
//| seria serve walk-forward su dati out-of-sample.                    |
//+------------------------------------------------------------------+
void TrainEnsembleModels()
{
    int closed_signals = 0;
    for(int i = 0; i < g_MLRecordCount; i++) {
        if(g_MLHistory[i].is_closed) closed_signals++;
    }

    if(closed_signals < 20) {
        if(InpDebugMode) Print("⚠️ ML: Not enough closed signals (", closed_signals, "/20)");
        return;
    }

    double learning_rate = 0.01;

    // Train each model independently
    for(int m = 0; m < NUM_MODELS; m++) {
        int correct = 0;
        int tp = 0, fp = 0, fn = 0;

        for(int i = 0; i < g_MLRecordCount; i++) {
            if(!g_MLHistory[i].is_closed) continue;

            double predicted = PredictProbability(g_MLHistory[i].features, m) / 100.0;
            double actual = g_MLHistory[i].is_winner ? 1.0 : 0.0;
            double error = actual - predicted;

            // Update weights
            g_MLModels[m].feature_weights[0] += learning_rate * error * g_MLHistory[i].features.distance_normalized;
            g_MLModels[m].feature_weights[1] += learning_rate * error * (g_MLHistory[i].features.touch_count / 10.0);
            g_MLModels[m].feature_weights[2] += learning_rate * error * g_MLHistory[i].features.rejection_strength;
            g_MLModels[m].feature_weights[3] += learning_rate * error * g_MLHistory[i].features.poc_distance_ratio;
            g_MLModels[m].feature_weights[4] += learning_rate * error * g_MLHistory[i].features.atr_percentile;
            g_MLModels[m].feature_weights[5] += learning_rate * error * g_MLHistory[i].features.time_of_day;
            g_MLModels[m].feature_weights[6] += learning_rate * error * g_MLHistory[i].features.volume_quality;
            g_MLModels[m].feature_weights[7] += learning_rate * error * ((g_MLHistory[i].features.price_momentum + 1.0) / 2.0);
            g_MLModels[m].feature_weights[8] += learning_rate * error * g_MLHistory[i].features.edge_distance;
            g_MLModels[m].feature_weights[9] += learning_rate * error * (g_MLHistory[i].features.consecutive_touches / 5.0);
            g_MLModels[m].feature_weights[10] += learning_rate * error * ((g_MLHistory[i].features.wick_asymmetry + 1.0) / 2.0);
            g_MLModels[m].feature_weights[11] += learning_rate * error * g_MLHistory[i].features.va_width_ratio;
            g_MLModels[m].bias += learning_rate * error;

            // Track metrics
            bool predicted_win = (predicted >= 0.5);
            bool actual_win = g_MLHistory[i].is_winner;
            if(predicted_win == actual_win) correct++;
            if(predicted_win && actual_win) tp++;
            if(predicted_win && !actual_win) fp++;
            if(!predicted_win && actual_win) fn++;
        }

        g_MLModels[m].accuracy = (closed_signals > 0) ? (double)correct / closed_signals * 100.0 : 0;
        g_MLModels[m].precision = (tp + fp > 0) ? (double)tp / (tp + fp) * 100.0 : 0;
        g_MLModels[m].recall = (tp + fn > 0) ? (double)tp / (tp + fn) * 100.0 : 0;
        g_MLModels[m].training_count++;
        g_MLModels[m].last_train_time = TimeCurrent();
    }

    // Update best model
    double best_acc = 0;
    for(int m = 0; m < NUM_MODELS; m++) {
        if(g_MLModels[m].accuracy > best_acc) {
            best_acc = g_MLModels[m].accuracy;
            g_MLStats.best_accuracy = best_acc;
            g_MLStats.best_model = g_MLModels[m].name;
        }
    }

    if(InpDebugMode) {
        PrintFormat("✅ ENSEMBLE RETRAINED | Closed: %d", closed_signals);
        for(int m = 0; m < NUM_MODELS; m++) {
            PrintFormat("  %s: Acc=%.1f%% Pre=%.1f%% Rec=%.1f%%",
                       g_MLModels[m].name, g_MLModels[m].accuracy,
                       g_MLModels[m].precision, g_MLModels[m].recall);
        }
    }
}

//+------------------------------------------------------------------+
//| Update feature importance                                         |
//+------------------------------------------------------------------+
void UpdateFeatureImportance()
{
    // Calculate average absolute weight across all models
    for(int f = 0; f < ML_FEATURES; f++) {
        double avg_weight = 0;
        for(int m = 0; m < NUM_MODELS; m++) {
            avg_weight += MathAbs(g_MLModels[m].feature_weights[f]);
        }
        g_FeatureRanking[f].importance = avg_weight / NUM_MODELS;
        g_FeatureRanking[f].contribution = g_FeatureRanking[f].importance * 100;
    }

    // Sort by importance (bubble sort)
    for(int i = 0; i < ML_FEATURES - 1; i++) {
        for(int j = 0; j < ML_FEATURES - i - 1; j++) {
            if(g_FeatureRanking[j].importance < g_FeatureRanking[j + 1].importance) {
                SFeatureImportance temp = g_FeatureRanking[j];
                g_FeatureRanking[j] = g_FeatureRanking[j + 1];
                g_FeatureRanking[j + 1] = temp;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Export weights to file                                            |
//+------------------------------------------------------------------+
void ExportWeightsToFile()
{
    string filename = StringFormat("VP9_Weights_%s_%s.txt", _Symbol, TimeToString(TimeCurrent(), TIME_DATE));
    int handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_COMMON);

    if(handle == INVALID_HANDLE) {
        if(InpDebugMode) PrintFormat("❌ Failed to export weights: %d", GetLastError());
        return;
    }

    // Write header
    FileWriteString(handle, "═══ VP v9.2 ML WEIGHTS EXPORT ═══\n");
    FileWriteString(handle, StringFormat("Symbol: %s | Date: %s\n", _Symbol, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES)));
    FileWriteString(handle, StringFormat("Total Signals: %d | Accuracy: %.1f%%\n", g_MLStats.total_signals, g_MLStats.best_accuracy));
    FileWriteString(handle, "\n");

    for(int m = 0; m < NUM_MODELS; m++) {
        FileWriteString(handle, StringFormat("═══ MODEL: %s ═══\n", g_MLModels[m].name));
        FileWriteString(handle, StringFormat("Accuracy: %.1f%% | Precision: %.1f%% | Recall: %.1f%%\n",
                 g_MLModels[m].accuracy, g_MLModels[m].precision, g_MLModels[m].recall));
        FileWriteString(handle, StringFormat("Bias: %.6f\n", g_MLModels[m].bias));
        FileWriteString(handle, "\n");

        for(int f = 0; f < ML_FEATURES; f++) {
            FileWriteString(handle, StringFormat("%s: %.6f\n", g_FeatureNames[f], g_MLModels[m].feature_weights[f]));
        }
        FileWriteString(handle, "\n");
    }

    FileWriteString(handle, "═══ FEATURE IMPORTANCE ═══\n");
    for(int f = 0; f < ML_FEATURES; f++) {
        FileWriteString(handle, StringFormat("%d. %s: %.4f (%.1f%%)\n",
                 f+1, g_FeatureRanking[f].name, g_FeatureRanking[f].importance, g_FeatureRanking[f].contribution));
    }

    FileClose(handle);

    if(InpDebugMode) {
        PrintFormat("✅ Weights exported to: %s", filename);
    }

    // Backup binario (rileggibile) in aggiunta al report testuale
    BackupWeights();
}

//+------------------------------------------------------------------+
//| Load weights from file                                            |
//+------------------------------------------------------------------+
void LoadWeightsFromFile()
{
    string filename = StringFormat("VP9_Backup_%s.dat", _Symbol);
    if(FileIsExist(filename, FILE_COMMON)) {
        if(RestoreWeights(filename) && InpDebugMode) {
            Print("✅ Pesi ML ricaricati da backup precedente: ", filename);
        }
    } else if(InpDebugMode) {
        Print("ℹ️ Nessun backup pesi trovato, si parte dai pesi iniziali di default");
    }
}

//+------------------------------------------------------------------+
//| Draw ML dashboard                                                 |
//+------------------------------------------------------------------+
void DrawMLDashboard()
{
    string prefix = g_UniqueID + "MLDASH_";
    int x = 10;
    int y = 20;
    int line_h = InpMLDashboardFontSize + 3;
    int corner = InpMLDashboardCorner;
    int line = 0;

    string hull_dir = "N/A";
    int hsz = ArraySize(g_HullBuffer);
    if(hsz > 0 && g_HullBuffer[hsz - 1] != EMPTY_VALUE) {
        double last_price = iClose(_Symbol, _Period, 0);
        hull_dir = (last_price > g_HullBuffer[hsz - 1]) ? "PREZZO SOPRA→LONG" : "PREZZO SOTTO→SHORT";
    }

    CreateLabel(prefix + "title", "═══ ML ENSEMBLE v9.2 ═══", x, y + (line++ * line_h),
               InpMLDashboardFontSize + 2, clrAqua, corner);
    line++;

    CreateLabel(prefix + "dst", StringFormat("DST: %s | Server offset: UTC+%d",
               (InpAutoDST && IsEEST_DST(TimeCurrent())) ? "ESTATE" : "INVERNO",
               (InpAutoDST && IsEEST_DST(TimeCurrent())) ? 3 : 2),
               x, y + (line++ * line_h), InpMLDashboardFontSize, clrSilver, corner);

    CreateLabel(prefix + "hull", StringFormat("Hull Filter: %s (P%d) Dir:%s",
               InpUseHullFilter ? "ON" : "OFF", InpHullPeriod, hull_dir),
               x, y + (line++ * line_h), InpMLDashboardFontSize, InpUseHullFilter ? clrAqua : clrGray, corner);
    line++;

    // Stats
    double approval_rate = (g_MLStats.total_signals > 0) ?
                          (double)g_MLStats.ensemble_approved / g_MLStats.total_signals * 100 : 0;
    CreateLabel(prefix + "signals", StringFormat("Total: %d | Approved: %d (%.1f%%)",
               g_MLStats.total_signals, g_MLStats.ensemble_approved, approval_rate),
               x, y + (line++ * line_h), InpMLDashboardFontSize, clrWhite, corner);
    CreateLabel(prefix + "rejected", StringFormat("Rejected: %d | Avg Score: %.1f%%",
               g_MLStats.ensemble_rejected, g_MLStats.avg_ensemble_score),
               x, y + (line++ * line_h), InpMLDashboardFontSize, clrGray, corner);
    line++;

    // Vote distribution
    CreateLabel(prefix + "votes", StringFormat("Votes → Una: %d | Maj: %d | Split: %d",
               g_MLStats.unanimous_votes, g_MLStats.majority_votes, g_MLStats.split_votes),
               x, y + (line++ * line_h), InpMLDashboardFontSize, clrYellow, corner);
    line++;

    // Win rate
    int total_closed = g_MLStats.wins + g_MLStats.losses;
    double win_rate = (total_closed > 0) ? (double)g_MLStats.wins / total_closed * 100 : 0;
    color wr_color = (win_rate >= 65) ? clrLime : (win_rate >= 55 ? clrYellow : clrRed);
    CreateLabel(prefix + "winrate", StringFormat("Win Rate: %.1f%% (%d/%d)",
               win_rate, g_MLStats.wins, total_closed),
               x, y + (line++ * line_h), InpMLDashboardFontSize, wr_color, corner);
    line++;

    // Model comparison
    if(InpShowModelComparison) {
        CreateLabel(prefix + "models_title", "MODEL COMPARISON:", x, y + (line++ * line_h),
                   InpMLDashboardFontSize, clrOrange, corner);
        for(int m = 0; m < NUM_MODELS; m++) {
            CreateLabel(prefix + "model" + IntegerToString(m),
                       StringFormat("  %s: %.1f%%", g_MLModels[m].name, g_MLModels[m].accuracy),
                       x, y + (line++ * line_h), InpMLDashboardFontSize - 1,
                       (g_MLModels[m].name == g_MLStats.best_model) ? clrLime : clrWhite, corner);
        }
        line++;
    }

    // Feature importance
    if(InpShowFeatureImportance) {
        CreateLabel(prefix + "feat_title", "TOP FEATURES:", x, y + (line++ * line_h),
                   InpMLDashboardFontSize, clrOrange, corner);
        for(int f = 0; f < 5; f++) {
            CreateLabel(prefix + "feat" + IntegerToString(f),
                       StringFormat("  %d. %s (%.1f%%)", f+1, g_FeatureRanking[f].name, g_FeatureRanking[f].contribution),
                       x, y + (line++ * line_h), InpMLDashboardFontSize - 1, clrWhite, corner);
        }
    }

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create label                                                      |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, int font_size, color clr, int corner)
{
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    }
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

void UpdateSignalTracker(datetime session_start, bool is_long, bool is_short) {
    for(int i = 0; i < ArraySize(g_Signals); i++) {
        if(g_Signals[i].session_start == 0 || g_Signals[i].session_start == session_start) {
            g_Signals[i].session_start = session_start;
            if(is_long) g_Signals[i].long_fired = true;
            if(is_short) g_Signals[i].short_fired = true;
            return;
        }
    }
}

void CleanMyObjects() {
    int total = ObjectsTotal(0, 0, -1);
    for(int i = total - 1; i >= 0; i--) {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, g_UniqueID) == 0) ObjectDelete(0, name);
    }
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Pulizia oggetti SEMPRE, indipendentemente dal motivo del deinit — prima
    // veniva saltata su REASON_PARAMETERS (cambio di un qualunque input) e su
    // altri motivi non elencati, lasciando gli oggetti della sessione precedente
    // a schermo anche con l'ID stabile qui sopra.
    CleanMyObjects();

    if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE || reason == REASON_CHARTCHANGE) {
        // Export final weights before exit
        if(InpAutoExportWeights && InpEnableML) {
            ExportWeightsToFile();
        }

        if(InpDebugMode) {
            PrintFormat("═══ VP v9.2 ULTIMATE REMOVED ═══");
            PrintFormat("Total Signals: %d | Approved: %d | Rejected: %d",
                       g_MLStats.total_signals, g_MLStats.ensemble_approved, g_MLStats.ensemble_rejected);
            PrintFormat("Best Model: %s | Accuracy: %.1f%%", g_MLStats.best_model, g_MLStats.best_accuracy);
            PrintFormat("Unanimous: %d | Majority: %d | Split: %d",
                       g_MLStats.unanimous_votes, g_MLStats.majority_votes, g_MLStats.split_votes);
            PrintFormat("Win Rate: %.1f%% (%d W / %d L)",
                       (g_MLStats.wins + g_MLStats.losses > 0) ?
                       (double)g_MLStats.wins / (g_MLStats.wins + g_MLStats.losses) * 100 : 0,
                       g_MLStats.wins, g_MLStats.losses);
        }
    }

    if(g_ATRHandle != INVALID_HANDLE) {
        IndicatorRelease(g_ATRHandle);
        g_ATRHandle = INVALID_HANDLE;
    }

    // Cleanup arrays
    for(int i = 0; i < g_TotalProfiles; i++) {
        g_Profiles[i].Reset();
    }

    ArrayFree(g_Profiles);
    ArrayFree(g_Signals);
    ArrayFree(g_MLHistory);
    ArrayFree(g_MultiSymbolDB);
    g_IsInitialized = false;
    Comment("");
}

//+------------------------------------------------------------------+
//| Chart event handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_KEYDOWN && lparam == 'C') {
        CleanMyObjects();
        if(InpDebugMode) Print("✓ Manual cleanup: " + g_UniqueID);
        ChartRedraw();
    }

    if(id == CHARTEVENT_KEYDOWN && lparam == 'R') {
        // Manual retrain on 'R' key
        if(InpEnableML) {
            TrainEnsembleModels();
            UpdateFeatureImportance();
            Print("🔄 Manual ensemble retraining triggered");
        }
    }

    if(id == CHARTEVENT_KEYDOWN && lparam == 'E') {
        // Manual export on 'E' key
        if(InpEnableML) {
            ExportWeightsToFile();
            Print("💾 Manual weight export triggered");
        }
    }

    if(id == CHARTEVENT_KEYDOWN && lparam == 'I') {
        // Show feature importance on 'I' key
        if(InpEnableML) {
            UpdateFeatureImportance();
            PrintFormat("═══ FEATURE IMPORTANCE ═══");
            for(int f = 0; f < ML_FEATURES; f++) {
                PrintFormat("%d. %s: %.4f (%.1f%%)",
                           f+1, g_FeatureRanking[f].name,
                           g_FeatureRanking[f].importance,
                           g_FeatureRanking[f].contribution);
            }
        }
    }

    if(id == CHARTEVENT_KEYDOWN && lparam == 'M') {
        // Show model stats on 'M' key
        if(InpEnableML) {
            PrintFormat("═══ MODEL STATISTICS ═══");
            for(int m = 0; m < NUM_MODELS; m++) {
                PrintFormat("%s:", g_MLModels[m].name);
                PrintFormat("  Accuracy: %.2f%% | Precision: %.2f%% | Recall: %.2f%%",
                           g_MLModels[m].accuracy, g_MLModels[m].precision, g_MLModels[m].recall);
                PrintFormat("  Training Count: %d | Predictions: %d | Correct: %d",
                           g_MLModels[m].training_count, g_MLModels[m].predictions_made,
                           g_MLModels[m].correct_predictions);
            }
            PrintFormat("Best Model: %s (%.1f%%)", g_MLStats.best_model, g_MLStats.best_accuracy);
        }
    }

    if(id == CHARTEVENT_CHART_CHANGE) {
        g_LastUpdate = 0;
        g_Adaptive.Calculate(_Symbol, g_ATRHandle);
        if(InpDebugMode) Print("📊 Chart changed - recalculating");
    }
}

//+------------------------------------------------------------------+
// PROFILE MANAGEMENT FUNCTIONS
//+------------------------------------------------------------------+
void UpdateProfiles() {
    if(InpProfileMode == MODE_SESSIONS) UpdateSessionProfiles();
    else UpdateStandardProfiles();
}

//+------------------------------------------------------------------+
//| Aggiorna i 4 profili di sessione: Sydney, Asian/Tokyo, London,    |
//| New York. L'ordine riflette la sequenza reale delle sessioni.     |
//+------------------------------------------------------------------+
void UpdateSessionProfiles() {
    int idx = 0;
    for(int i = 0; i < InpHistoryPeriods && idx < g_TotalProfiles - (SESSIONS_PER_DAY - 1); i++) {

        SSessionProfile sydney; sydney.id = idx; sydney.Reset();
        if(GetSessionTime(InpSydneyStart, InpSydneyEnd, i, sydney.start, sydney.end)) {
            BuildProfile(sydney);
            if(sydney.is_valid) {
                CalculateKeyLevels(sydney);
                CheckMitigation(sydney);
                if(!InpShowOnlySignals) DrawProfile(sydney, InpSydneyColor);
                g_Profiles[idx++] = sydney;
            }
        }

        SSessionProfile asian; asian.id = idx; asian.Reset();
        if(GetSessionTime(InpAsianStart, InpAsianEnd, i, asian.start, asian.end)) {
            BuildProfile(asian);
            if(asian.is_valid) {
                CalculateKeyLevels(asian);
                CheckMitigation(asian);
                if(!InpShowOnlySignals) DrawProfile(asian, InpAsianColor);
                g_Profiles[idx++] = asian;
            }
        }

        SSessionProfile london; london.id = idx; london.Reset();
        if(GetSessionTime(InpLondonStart, InpLondonEnd, i, london.start, london.end)) {
            BuildProfile(london);
            if(london.is_valid) {
                CalculateKeyLevels(london);
                CheckMitigation(london);
                if(!InpShowOnlySignals) DrawProfile(london, InpLondonColor);
                g_Profiles[idx++] = london;
            }
        }

        SSessionProfile ny; ny.id = idx; ny.Reset();
        if(GetSessionTime(InpNewYorkStart, InpNewYorkEnd, i, ny.start, ny.end)) {
            BuildProfile(ny);
            if(ny.is_valid) {
                CalculateKeyLevels(ny);
                CheckMitigation(ny);
                if(!InpShowOnlySignals) DrawProfile(ny, InpNewYorkColor);
                g_Profiles[idx++] = ny;
            }
        }
    }
}

void UpdateStandardProfiles() {
    ENUM_TIMEFRAMES tf;
    color clr;
    switch(InpProfileMode) {
        case MODE_DAILY: tf = PERIOD_D1; clr = InpDailyColor; break;
        case MODE_WEEKLY: tf = PERIOD_W1; clr = InpWeeklyColor; break;
        case MODE_MONTHLY: tf = PERIOD_MN1; clr = InpMonthlyColor; break;
        default: return;
    }

    for(int i = 0; i < InpHistoryPeriods && i < g_TotalProfiles; i++) {
        SSessionProfile profile; profile.id = i; profile.Reset();
        profile.start = iTime(_Symbol, tf, i + 1);
        profile.end = iTime(_Symbol, tf, i);
        if(profile.start <= 0 || profile.end <= 0) continue;
        if(i == 0) profile.end = TimeCurrent();

        BuildProfile(profile);
        if(profile.is_valid) {
            CalculateKeyLevels(profile);
            CheckMitigation(profile);
            if(!InpShowOnlySignals) DrawProfile(profile, clr);
            g_Profiles[i] = profile;
        }
    }
}

//+------------------------------------------------------------------+
//| Calcola l'orario di una sessione, applicando +1h automaticamente  |
//| se InpAutoDST è attivo e siamo nel periodo di ora legale EU       |
//| (replica il comportamento del server FP Markets, che passa da     |
//| EET/UTC+2 a EEST/UTC+3 e viceversa alle stesse date dell'UE).      |
//+------------------------------------------------------------------+
bool GetSessionTime(string start_str, string end_str, int days_back,
                    datetime &start_out, datetime &end_out) {
    MqlDateTime dt;
    datetime base = TimeCurrent() - (days_back * 86400);
    if(!TimeToStruct(base, dt)) return false;

    int dst_shift = (InpAutoDST && IsEEST_DST(base)) ? 1 : 0; // +1h se ora legale attiva

    string parts[];
    if(StringSplit(start_str, ':', parts) != 2) return false;
    dt.hour = (int)StringToInteger(parts[0]) + dst_shift;
    dt.min = (int)StringToInteger(parts[1]);
    dt.sec = 0;
    start_out = StructToTime(dt);
    if(start_out <= 0) return false;

    if(StringSplit(end_str, ':', parts) != 2) return false;
    dt.hour = (int)StringToInteger(parts[0]) + dst_shift;
    dt.min = (int)StringToInteger(parts[1]);
    end_out = StructToTime(dt);
    if(end_out <= 0) return false;
    if(end_out <= start_out) end_out += 86400;
    return true;
}

void BuildProfile(SSessionProfile &profile) {
    profile.is_valid = false;
    profile.high = 0;
    profile.low = DBL_MAX;
    profile.total_vol = 0;

    int start_bar = iBarShift(_Symbol, InpTimeframe, profile.start);
    int end_bar = iBarShift(_Symbol, InpTimeframe, profile.end);
    if(start_bar < 0 || end_bar < 0) return;
    if(start_bar < end_bar) { int temp = start_bar; start_bar = end_bar; end_bar = temp; }

    for(int i = end_bar; i <= start_bar; i++) {
        double h = iHigh(_Symbol, InpTimeframe, i);
        double l = iLow(_Symbol, InpTimeframe, i);
        if(h <= 0 || l <= 0) continue;
        if(h > profile.high) profile.high = h;
        if(l < profile.low) profile.low = l;
    }

    if(profile.high <= profile.low + EPSILON) return;

    ArrayResize(profile.nodes, InpPriceLevels);
    double step = (profile.high - profile.low) / InpPriceLevels;

    for(int i = 0; i < InpPriceLevels; i++) {
        profile.nodes[i].Init(profile.low + (i * step) + (step * 0.5));
    }

    for(int i = end_bar; i <= start_bar; i++) {
        double h = iHigh(_Symbol, InpTimeframe, i);
        double l = iLow(_Symbol, InpTimeframe, i);
        double vol = g_UseRealVolume ?
                    (double)iVolume(_Symbol, InpTimeframe, i) :
                    (double)iTickVolume(_Symbol, InpTimeframe, i);
        if(vol <= EPSILON) continue;

        int start_level = (int)((l - profile.low) / step);
        int end_level = (int)((h - profile.low) / step);
        start_level = MathMax(0, MathMin(start_level, InpPriceLevels - 1));
        end_level = MathMax(0, MathMin(end_level, InpPriceLevels - 1));

        int num_levels = end_level - start_level + 1;
        if(num_levels <= 0) num_levels = 1;
        double vol_per_level = vol / num_levels;

        for(int j = start_level; j <= end_level; j++) {
            profile.nodes[j].volume += vol_per_level;
        }
        profile.total_vol += vol;
    }

    profile.is_valid = (profile.total_vol > EPSILON);
}

void CalculateKeyLevels(SSessionProfile &profile) {
    int size = ArraySize(profile.nodes);
    if(size == 0 || profile.total_vol < EPSILON || !profile.is_valid) return;

    double max_vol = 0;
    int poc_idx = 0;
    for(int i = 0; i < size; i++) {
        if(profile.nodes[i].volume > max_vol) {
            max_vol = profile.nodes[i].volume;
            poc_idx = i;
        }
    }
    profile.poc = profile.nodes[poc_idx].price;

    double target = profile.total_vol * (InpValueAreaPercent / 100.0);
    double accum = profile.nodes[poc_idx].volume;
    int high_idx = poc_idx;
    int low_idx = poc_idx;

    while(accum < target && (high_idx < size - 1 || low_idx > 0)) {
        double vol_above = (high_idx < size - 1) ? profile.nodes[high_idx + 1].volume : 0;
        double vol_below = (low_idx > 0) ? profile.nodes[low_idx - 1].volume : 0;

        if(vol_above >= vol_below && high_idx < size - 1) {
            high_idx++;
            accum += profile.nodes[high_idx].volume;
        } else if(low_idx > 0) {
            low_idx--;
            accum += profile.nodes[low_idx].volume;
        } else break;
    }

    profile.vah = profile.nodes[high_idx].price;
    profile.val = profile.nodes[low_idx].price;
}

void CheckMitigation(SSessionProfile &profile) {
    if(!profile.is_valid) return;
    profile.poc_mitigated = 0;
    profile.vah_mitigated = 0;
    profile.val_mitigated = 0;
    if(!InpExtendLines) return;

    datetime current = TimeCurrent();
    if(current - profile.end < 300) return;

    int start_bar = iBarShift(_Symbol, InpTimeframe, profile.end);
    if(start_bar < 0) return;

    int max_bars = MathMin(start_bar, 1000);
    for(int i = max_bars; i >= 0; i--) {
        double h = iHigh(_Symbol, InpTimeframe, i);
        double l = iLow(_Symbol, InpTimeframe, i);
        datetime t = iTime(_Symbol, InpTimeframe, i);
        if(h <= 0 || l <= 0 || t <= 0) continue;

        if(InpShowPOC && profile.poc_mitigated == 0) {
            if(l <= profile.poc && h >= profile.poc) profile.poc_mitigated = t;
        }
        if(InpShowVAH && profile.vah_mitigated == 0) {
            if(l <= profile.vah && h >= profile.vah) profile.vah_mitigated = t;
        }
        if(InpShowVAL && profile.val_mitigated == 0) {
            if(l <= profile.val && h >= profile.val) profile.val_mitigated = t;
        }

        if((profile.poc_mitigated > 0 || !InpShowPOC) &&
           (profile.vah_mitigated > 0 || !InpShowVAH) &&
           (profile.val_mitigated > 0 || !InpShowVAL)) break;
    }

    if(InpShowPOC && profile.poc_mitigated == 0) profile.poc_mitigated = current;
    if(InpShowVAH && profile.vah_mitigated == 0) profile.vah_mitigated = current;
    if(InpShowVAL && profile.val_mitigated == 0) profile.val_mitigated = current;
}

void DrawProfile(SSessionProfile &profile, color clr) {
    if(!profile.is_valid) return;
    int size = ArraySize(profile.nodes);
    if(size == 0) return;

    string prefix = StringFormat("%s%d_", g_Prefix, profile.id);
    double max_vol = 0;
    for(int i = 0; i < size; i++) {
        if(profile.nodes[i].volume > max_vol) max_vol = profile.nodes[i].volume;
    }
    if(max_vol < EPSILON) return;

    datetime time_range = profile.end - profile.start;
    if(time_range <= 0) time_range = PeriodSeconds(PERIOD_D1);
    datetime max_width = (datetime)(time_range * (InpMaxWidthPercent / 100.0));
    double price_step = (profile.high - profile.low) / InpPriceLevels;

    for(int i = 0; i < size; i++) {
        if(profile.nodes[i].volume < EPSILON) continue;
        double ratio = profile.nodes[i].volume / max_vol;
        datetime width = (datetime)(max_width * ratio);
        if(width < 60) continue;

        double gap = InpBarGap * 0.02;
        double height = (price_step * 0.5) * (1.0 - gap);
        string obj = prefix + "VP_" + IntegerToString(i);

        if(ObjectFind(0, obj) < 0) {
            if(!ObjectCreate(0, obj, OBJ_RECTANGLE, 0,
                           profile.start, profile.nodes[i].price - height,
                           profile.start + width, profile.nodes[i].price + height)) continue;
        } else {
            ObjectSetInteger(0, obj, OBJPROP_TIME, 0, profile.start);
            ObjectSetDouble(0, obj, OBJPROP_PRICE, 0, profile.nodes[i].price - height);
            ObjectSetInteger(0, obj, OBJPROP_TIME, 1, profile.start + width);
            ObjectSetDouble(0, obj, OBJPROP_PRICE, 1, profile.nodes[i].price + height);
        }

        ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, obj, OBJPROP_FILL, true);
        ObjectSetInteger(0, obj, OBJPROP_BACK, true);
        ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
    }

    if(InpShowPOC && profile.poc > EPSILON) {
        string poc_name = prefix + "POC";
        datetime poc_end = InpExtendLines ? profile.poc_mitigated : profile.end;
        DrawLine(poc_name, profile.start, profile.poc, poc_end, profile.poc,
                InpPOCColor, InpLineWidth, STYLE_SOLID);
    }
    if(InpShowVAH && profile.vah > EPSILON) {
        string vah_name = prefix + "VAH";
        datetime vah_end = InpExtendLines ? profile.vah_mitigated : profile.end;
        DrawLine(vah_name, profile.start, profile.vah, vah_end, profile.vah,
                InpVAColor, InpLineWidth, STYLE_DASH);
    }
    if(InpShowVAL && profile.val > EPSILON) {
        string val_name = prefix + "VAL";
        datetime val_end = InpExtendLines ? profile.val_mitigated : profile.end;
        DrawLine(val_name, profile.start, profile.val, val_end, profile.val,
                InpVAColor, InpLineWidth, STYLE_DASH);
    }
}

void DrawLine(string name, datetime t1, double p1, datetime t2, double p2,
             color clr, int width, ENUM_LINE_STYLE style) {
    if(t1 <= 0 || t2 <= 0 || p1 <= 0 || p2 <= 0) return;

    if(ObjectFind(0, name) < 0) {
        if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2)) return;
    } else {
        ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
        ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
        ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
    }

    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
    ObjectSetInteger(0, name, OBJPROP_STYLE, style);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| FUNZIONI HELPER AVANZATE                                          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Get multi-symbol learning data                                    |
//+------------------------------------------------------------------+
void UpdateMultiSymbolDB(string symbol, bool is_winner)
{
    if(!InpEnableMultiSymbol) return;

    // Find or create symbol entry
    int idx = -1;
    for(int i = 0; i < g_MultiSymbolCount; i++) {
        if(g_MultiSymbolDB[i].symbol == symbol) {
            idx = i;
            break;
        }
    }

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
        g_MultiSymbolDB[idx].avg_accuracy =
            (prev_acc * prev_count + (is_winner ? 100.0 : 0.0)) / g_MultiSymbolDB[idx].signal_count;
    }
}

//+------------------------------------------------------------------+
//| Get symbol cross-correlation weight                              |
//+------------------------------------------------------------------+
double GetSymbolWeight(string symbol)
{
    if(!InpEnableMultiSymbol) return 1.0;

    for(int i = 0; i < g_MultiSymbolCount; i++) {
        if(g_MultiSymbolDB[i].symbol == symbol) {
            if(g_MultiSymbolDB[i].signal_count < 10) return 1.0;
            // Weight based on historical accuracy
            return g_MultiSymbolDB[i].avg_accuracy / 100.0;
        }
    }
    return 1.0;
}

//+------------------------------------------------------------------+
//| Advanced ATR percentile calculation — usa l'handle ATR condiviso  |
//| (creato una volta in OnInit) invece di aprirne/chiuderne uno ad   |
//| ogni chiamata. Il parametro è uno SHIFT (0=barra corrente), non   |
//| l'indice non-series di OnCalculate: il chiamante deve convertire. |
//+------------------------------------------------------------------+
double CalculateATRPercentileAdvanced(int shift)
{
    if(g_ATRHandle == INVALID_HANDLE || shift < 0) return 0.5;

    double atr_array[];
    ArraySetAsSeries(atr_array, true);

    int lookback = 100;
    if(CopyBuffer(g_ATRHandle, 0, shift, lookback, atr_array) != lookback) {
        return 0.5;
    }

    double current_atr = atr_array[0];
    int below_count = 0;

    for(int i = 1; i < lookback; i++) {
        if(atr_array[i] < current_atr) below_count++;
    }

    return (double)below_count / (lookback - 1);
}

//+------------------------------------------------------------------+
//| Validate signal quality score                                     |
//+------------------------------------------------------------------+
double CalculateSignalQuality(SMLFeatures &features)
{
    double score = 0;

    // Distance quality (30%)
    score += features.distance_normalized * 30;

    // Touch quality (20%)
    score += (MathMin(features.touch_count, 5) / 5.0) * 20;

    // Rejection quality (25%)
    score += features.rejection_strength * 25;

    // Volume quality (15%)
    score += features.volume_quality * 15;

    // Time quality (10%)
    score += features.time_of_day * 10;

    return MathMin(score, 100.0);
}

//+------------------------------------------------------------------+
//| Export detailed signal log                                        |
//+------------------------------------------------------------------+
void ExportSignalLog()
{
    string filename = StringFormat("VP9_SignalLog_%s_%s.csv", _Symbol, TimeToString(TimeCurrent(), TIME_DATE));
    int handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_COMMON);

    if(handle == INVALID_HANDLE) return;

    // CSV Header
    FileWriteString(handle, "Time,Symbol,Direction,EntryPrice,IsClosed,IsWinner,Distance,Touches,Rejection,POCDist,ATR,TimeScore,Volume,Momentum,EdgeDist,Consecutive,WickAsym,VAWidth\n");

    // Write records
    for(int i = 0; i < g_MLRecordCount; i++) {
        if(!g_MLHistory[i].is_closed) continue;

        string line = StringFormat("%s,%s,%s,%.5f,%s,%s,%.4f,%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.1f,%.4f,%.4f\n",
            TimeToString(g_MLHistory[i].time, TIME_DATE|TIME_MINUTES),
            g_MLHistory[i].symbol,
            g_MLHistory[i].is_long ? "LONG" : "SHORT",
            g_MLHistory[i].entry_price,
            "YES",
            g_MLHistory[i].is_winner ? "WIN" : "LOSS",
            g_MLHistory[i].features.distance_normalized,
            g_MLHistory[i].features.touch_count,
            g_MLHistory[i].features.rejection_strength,
            g_MLHistory[i].features.poc_distance_ratio,
            g_MLHistory[i].features.atr_percentile,
            g_MLHistory[i].features.time_of_day,
            g_MLHistory[i].features.volume_quality,
            g_MLHistory[i].features.price_momentum,
            g_MLHistory[i].features.edge_distance,
            g_MLHistory[i].features.consecutive_touches,
            g_MLHistory[i].features.wick_asymmetry,
            g_MLHistory[i].features.va_width_ratio
        );

        FileWriteString(handle, line);
    }

    FileClose(handle);

    if(InpDebugMode) {
        PrintFormat("✅ Signal log exported: %s", filename);
    }
}

//+------------------------------------------------------------------+
//| Create backup of current weights — nome file STABILE (senza tick  |
//| count) cosi' LoadWeightsFromFile() puo' ritrovarlo e ricaricarlo  |
//| ad ogni riavvio dell'indicatore (persistenza reale tra sessioni). |
//+------------------------------------------------------------------+
void BackupWeights()
{
    string filename = StringFormat("VP9_Backup_%s.dat", _Symbol);
    int handle = FileOpen(filename, FILE_WRITE | FILE_BIN | FILE_COMMON);

    if(handle == INVALID_HANDLE) return;

    // Write ensemble data
    FileWriteInteger(handle, NUM_MODELS);

    for(int m = 0; m < NUM_MODELS; m++) {
        FileWriteString(handle, g_MLModels[m].name);
        for(int f = 0; f < ML_FEATURES; f++) {
            FileWriteDouble(handle, g_MLModels[m].feature_weights[f]);
        }
        FileWriteDouble(handle, g_MLModels[m].bias);
        FileWriteInteger(handle, g_MLModels[m].training_count);
        FileWriteDouble(handle, g_MLModels[m].accuracy);
        FileWriteDouble(handle, g_MLModels[m].precision);
        FileWriteDouble(handle, g_MLModels[m].recall);
    }

    FileClose(handle);

    if(InpDebugMode) {
        PrintFormat("💾 Weights backed up: %s", filename);
    }
}

//+------------------------------------------------------------------+
//| Restore weights from backup                                      |
//+------------------------------------------------------------------+
bool RestoreWeights(string filename)
{
    int handle = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
    if(handle == INVALID_HANDLE) return false;

    int num_models = FileReadInteger(handle);
    if(num_models != NUM_MODELS) {
        FileClose(handle);
        return false;
    }

    for(int m = 0; m < NUM_MODELS; m++) {
        g_MLModels[m].name = FileReadString(handle);
        for(int f = 0; f < ML_FEATURES; f++) {
            g_MLModels[m].feature_weights[f] = FileReadDouble(handle);
        }
        g_MLModels[m].bias = FileReadDouble(handle);
        g_MLModels[m].training_count = FileReadInteger(handle);
        g_MLModels[m].accuracy = FileReadDouble(handle);
        g_MLModels[m].precision = FileReadDouble(handle);
        g_MLModels[m].recall = FileReadDouble(handle);
    }

    FileClose(handle);

    if(InpDebugMode) {
        PrintFormat("✅ Weights restored from: %s", filename);
    }

    return true;
}

//+------------------------------------------------------------------+
//| Enhanced comment display                                          |
//+------------------------------------------------------------------+
void UpdateComment()
{
    if(!InpShowMLDashboard) {
        string cmt = StringFormat(
            "═══ VP ULTIMATE v9.2 ═══\n" +
            "Symbol: %s | Mode: %s\n" +
            "DST: %s | Hull Filter: %s\n" +
            "─────────────────────────\n" +
            "Signals: %d | Approved: %d\n" +
            "Win Rate: %.1f%% (%d/%d)\n" +
            "Best Model: %s (%.1f%%)\n" +
            "Ensemble: %.1f%% avg\n" +
            "─────────────────────────\n" +
            "Press 'R' = Retrain\n" +
            "Press 'E' = Export\n" +
            "Press 'I' = Features\n" +
            "Press 'M' = Models\n" +
            "Press 'C' = Clean",
            _Symbol, GetModeName(),
            (InpAutoDST && IsEEST_DST(TimeCurrent())) ? "Estate (UTC+3)" : "Inverno (UTC+2)",
            InpUseHullFilter ? "ON" : "OFF",
            g_MLStats.total_signals, g_MLStats.ensemble_approved,
            (g_MLStats.wins + g_MLStats.losses > 0) ?
                (double)g_MLStats.wins / (g_MLStats.wins + g_MLStats.losses) * 100 : 0,
            g_MLStats.wins, (g_MLStats.wins + g_MLStats.losses),
            g_MLStats.best_model, g_MLStats.best_accuracy,
            g_MLStats.avg_ensemble_score
        );
        Comment(cmt);
    }
}

//+------------------------------------------------------------------+
//| END OF FILE                                                       |
//+------------------------------------------------------------------+
