// Harness: run the REAL EA (preprocessed) bar-by-bar on synthetic data and dump its technical signals.
#include "mql5_mock.h"
bool g_quiet = true; datetime g_now = 0; ENUM_TIMEFRAMES g__Period = PERIOD_M15; string g__Symbol = "EURUSD";
double g_pointval = 0.00001; int g_spreadval = 12; string g_datapath = "out"; std::map<int, std::vector<MqlRates>> g_store; std::vector<FILE*> g_files;

// ---- extra API used by the EA
#define INIT_SUCCEEDED 0
#define INIT_FAILED 1
#define INIT_PARAMETERS_INCORRECT 2
enum { ACCOUNT_BALANCE = 1, ACCOUNT_CURRENCY };
inline double AccountInfoDouble(int) { return 10000.0; }
inline string AccountInfoString(int) { return "USD"; }
enum { MQL_TESTER = 1, MQL_VISUAL_MODE };
inline long MQLInfoInteger(int p) { return p == MQL_TESTER ? 1 : 0; }
#define clrAqua 1
#define clrLime 2
#define clrOrange 3
#define clrRed 4
#define clrSilver 5
#define clrWhite 6
#define clrYellow 7
enum ENUM_LINE_STYLE { STYLE_SOLID, STYLE_DASH };
enum { OBJ_TREND = 1, OBJ_LABEL };
enum { OBJPROP_COLOR = 1, OBJPROP_CORNER, OBJPROP_FONT, OBJPROP_FONTSIZE, OBJPROP_HIDDEN, OBJPROP_PRICE, OBJPROP_RAY_RIGHT, OBJPROP_SELECTABLE, OBJPROP_STYLE, OBJPROP_TEXT, OBJPROP_TIME, OBJPROP_WIDTH, OBJPROP_XDISTANCE, OBJPROP_YDISTANCE };
inline int ObjectFind(int, const string&) { return -1; }
template<typename... A> bool ObjectCreate(A...) { return true; }
template<typename... A> bool ObjectSetInteger(A...) { return true; }
template<typename... A> bool ObjectSetDouble(A...) { return true; }
template<typename... A> bool ObjectSetString(A...) { return true; }
inline bool ObjectDelete(int, const string&) { return true; }
inline int ObjectsTotal(int, int, int) { return 0; }
inline string ObjectName(int, int, int, int) { return ""; }
inline void ChartRedraw() {}
inline bool EventSetTimer(int) { return true; }
inline void EventKillTimer() {}
inline bool SendNotification(const string&) { return true; }
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY, ORDER_TYPE_SELL };
enum ENUM_ORDER_TYPE_FILLING { ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN };
enum ENUM_POSITION_TYPE { POSITION_TYPE_BUY, POSITION_TYPE_SELL };
enum { POSITION_MAGIC = 1, POSITION_PRICE_OPEN, POSITION_SL, POSITION_SYMBOL, POSITION_TP, POSITION_TYPE };
enum { DEAL_COMMISSION = 1, DEAL_ENTRY, DEAL_MAGIC, DEAL_POSITION_ID, DEAL_PROFIT, DEAL_SWAP, DEAL_SYMBOL };
enum ENUM_DEAL_ENTRY { DEAL_ENTRY_IN, DEAL_ENTRY_OUT, DEAL_ENTRY_OUT_BY };
enum { TRADE_ACTION_DEAL = 1, TRADE_ACTION_SLTP };
#define TRADE_RETCODE_DONE 10009
enum { TRADE_TRANSACTION_DEAL_ADD = 1 };
struct MqlTradeRequest { int action; string symbol; double volume; int type; double price; double sl; double tp; int deviation; long magic; string comment; int type_filling; ulong position; };
struct MqlTradeResult { int retcode; ulong deal; string comment; };
struct MqlTradeTransaction { int type; ulong deal; };
inline int PositionsTotal() { return 0; }
inline ulong PositionGetTicket(int) { return 0; }
inline string PositionGetString(int) { return ""; }
inline long PositionGetInteger(int) { return 0; }
inline double PositionGetDouble(int) { return 0; }
inline bool PositionSelectByTicket(ulong) { return false; }
inline bool OrderSend(const MqlTradeRequest&, MqlTradeResult& r) { r.retcode = 10006; return false; }
inline bool HistoryDealSelect(ulong) { return false; }
inline long HistoryDealGetInteger(ulong, int) { return 0; }
inline double HistoryDealGetDouble(ulong, int) { return 0; }
inline string HistoryDealGetString(ulong, int) { return ""; }
inline bool FileIsExist(const string&, int = 0) { return false; }
template<typename... A> unsigned FileWriteInteger(A...) { return 0; }
template<typename... A> unsigned FileWriteDouble(A...) { return 0; }
template<typename... A> int FileReadInteger(A...) { return 0; }
template<typename... A> double FileReadDouble(A...) { return 0; }
template<typename... A> string FileReadString(A...) { return ""; }

// ---- series API relative to the "now" bar (index into chart-TF store); bar 0 behaves like a just-opened bar
static int g_nowIdx = 0;
static std::vector<double> g_atrClosed;
static std::vector<MqlRates>& chartBars() { return g_store[(int)g__Period]; }
static int lastAtOrBefore(std::vector<MqlRates>& v, datetime t) {
   int lo = 0, hi = (int)v.size() - 1, ans = -1;
   while(lo <= hi) { int m = (lo + hi) / 2; if(v[m].time <= t) { ans = m; lo = m + 1; } else hi = m - 1; }
   return ans;
}
static MqlRates barAt(ENUM_TIMEFRAMES tf, int shift) {
   if(tf == PERIOD_CURRENT) tf = g__Period;
   auto& v = g_store[(int)tf];
   datetime tnow = chartBars()[g_nowIdx].time;
   int idxNow = (tf == g__Period) ? g_nowIdx : lastAtOrBefore(v, tnow);
   int idx = idxNow - shift;
   MqlRates r; memset(&r, 0, sizeof r);
   if(idx < 0 || idx >= (int)v.size()) return r;
   r = v[idx];
   if(shift == 0 && r.time == tnow && PeriodSeconds(tf) <= PeriodSeconds(g__Period)) { r.high = r.open; r.low = r.open; r.close = r.open; r.tick_volume = 1; }
   return r;
}
inline datetime iTime(const string&, ENUM_TIMEFRAMES tf, int s) { return barAt(tf, s).time; }
inline double iOpen(const string&, ENUM_TIMEFRAMES tf, int s) { return barAt(tf, s).open; }
inline double iHigh(const string&, ENUM_TIMEFRAMES tf, int s) { return barAt(tf, s).high; }
inline double iLow(const string&, ENUM_TIMEFRAMES tf, int s) { return barAt(tf, s).low; }
inline double iClose(const string&, ENUM_TIMEFRAMES tf, int s) { return barAt(tf, s).close; }
inline long iVolume(const string&, ENUM_TIMEFRAMES tf, int s) { return barAt(tf, s).real_volume; }
inline long iTickVolume(const string&, ENUM_TIMEFRAMES tf, int s) { return barAt(tf, s).tick_volume; }
inline int Bars(const string&, ENUM_TIMEFRAMES) { return g_nowIdx + 1; }
inline int iBarShift(const string&, ENUM_TIMEFRAMES tf, datetime t, bool exact = false) {
   if(tf == PERIOD_CURRENT) tf = g__Period;
   auto& v = g_store[(int)tf];
   datetime tnow = chartBars()[g_nowIdx].time;
   int idxNow = (tf == g__Period) ? g_nowIdx : lastAtOrBefore(v, tnow);
   int idxT = lastAtOrBefore(v, t);
   if(idxT < 0) return -1;
   if(idxT > idxNow) idxT = idxNow;
   return idxNow - idxT;
}
inline int iATR(const string&, ENUM_TIMEFRAMES, int) { return 1; }
inline bool IndicatorRelease(int) { return true; }
inline int CopyBuffer(int, int, int start, int count, Arr<double>& out) {
   out.v.assign(count, 0.0);
   for(int i = 0; i < count; i++) {
      int idx = g_nowIdx - 1 - (start + i);     // closed-bar ATR (deliberately excludes the forming bar, as the study script does)
      if(idx < 0) return -1;
      out.v[i] = g_atrClosed[idx];
   }
   return count;
}

static std::vector<std::pair<datetime, int>> g_signals;
struct EvalRow { datetime t, ps, pe; double poc, vah, val, hull; };
static std::vector<EvalRow> g_evals;
inline void HarnessEval(datetime t, datetime ps, datetime pe, double poc, double vah, double val, double hull) { g_evals.push_back({t, ps, pe, poc, vah, val, hull}); }
inline void HarnessRecord(bool is_long, datetime t) { g_signals.push_back({t, is_long ? 1 : -1}); }

#include "ea_pp.cpp"
#include "gen.h"

#include "ovr.h"
static void applyOverrides() {
   string tf = envs("VPTF", "M15");
   g__Period = tf == "M5" ? PERIOD_M5 : (tf == "H1" ? PERIOD_H1 : (tf == "M30" ? PERIOD_M30 : PERIOD_M15));
   string o = envs("VPINP", "");
   std::stringstream ss(o); string kv;
   while(std::getline(ss, kv, ',')) {
      size_t eq = kv.find('='); if(eq == string::npos) continue;
      string k = kv.substr(0, eq); double v = atof(kv.substr(eq + 1).c_str());
      if(k == "InpStrictMode") InpStrictMode = v != 0;
      else if(k == "InpUseHullFilter") InpUseHullFilter = v != 0;
      else if(k == "InpRequireRejection") InpRequireRejection = v != 0;
      else if(k == "InpMinTouchBars") InpMinTouchBars = (int)v;
      else if(k == "InpProfileMode") InpProfileMode = (ENUM_PROFILE_MODE)(int)v;
      else if(k == "InpAutoDST") InpAutoDST = v != 0;
      else if(k == "InpVADistance") InpVADistance = v;
      else if(k == "InpMinWickRatio") InpMinWickRatio = v;
      else if(k == "InpHullPeriod") InpHullPeriod = (int)v;
      else if(k == "InpTimeframe") InpTimeframe = (ENUM_TIMEFRAMES)(int)v;
   }
}
int main(int argc, char** argv) {
   int days = argc > 1 ? atoi(argv[1]) : 260;
   double kappa = argc > 2 ? atof(argv[2]) : 0.002;
   int scenario = argc > 3 ? atoi(argv[3]) : 0;
   system("mkdir -p out/MQL5/Files");
   applyOverrides();
   gen(days, kappa, sigma_default(), 88172645463325252ULL + 7919ULL * (unsigned long long)scenario);
   auto& bars = chartBars();
   int n = (int)bars.size();
   // ATR (SMA of TR) on closed bars
   g_atrClosed.assign(n, 0.0);
   { std::vector<double> tr(n, 0.0); double sum = 0; int p = 14;
     for(int i = 1; i < n; i++) { tr[i] = std::max(bars[i].high, bars[i-1].close) - std::min(bars[i].low, bars[i-1].close); sum += tr[i]; if(i > p) sum -= tr[i-p]; if(i >= p) g_atrClosed[i] = sum / p; } }
   if(OnInit() != INIT_SUCCEEDED) { fprintf(stderr, "OnInit failed\n"); return 1; }
   for(int N = 1; N < n - 1; N++) {
      g_nowIdx = N; g_now = bars[N].time;
      OnTick();
   }
   FILE* f = fopen("ea_signals.csv", "w");
   fprintf(f, "time,dir\n");
   for(auto& s : g_signals) fprintf(f, "%s,%d\n", TimeToString(s.first, TIME_DATE | TIME_MINUTES).c_str(), s.second);
   fclose(f);
   FILE* fe = fopen("ea_evals.csv", "w");
   fprintf(fe, "time,pstart,pend,poc,vah,val,hull\n");
   for(auto& e : g_evals) fprintf(fe, "%s,%s,%s,%.8f,%.8f,%.8f,%.8f\n", TimeToString(e.t).c_str(), TimeToString(e.ps).c_str(), TimeToString(e.pe).c_str(), e.poc, e.vah, e.val, e.hull == EMPTY_VALUE ? 0.0 : e.hull);
   fclose(fe);
   fprintf(stderr, "EA technical signals: %zu\n", g_signals.size());
   return 0;
}
