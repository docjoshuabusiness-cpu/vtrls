// Harness for VP_RR_Study: synthetic M1 data -> aggregated TFs -> run OnStart().
#include "mql5_mock.h"

bool g_quiet = false;
datetime g_now = 0;
ENUM_TIMEFRAMES g__Period = PERIOD_M15;
string g__Symbol = "EURUSD";
double g_pointval = 0.00001;
int g_spreadval = 12;
string g_datapath = ".";
std::map<int, std::vector<MqlRates>> g_store;
std::vector<FILE*> g_files;

struct EvalRowS { datetime t, ps, pe; double poc, vah, val, hull; };
static std::vector<EvalRowS> g_evalsS;
inline void HarnessEvalS(datetime t, datetime ps, datetime pe, double poc, double vah, double val, double hull) { g_evalsS.push_back({t, ps, pe, poc, vah, val, hull}); }
#include "study_pp.cpp"

#include "gen.h"

#include "ovr.h"
static void applyOverrides() {
   string tf = envs("VPTF", "M15");
   g__Period = tf == "M5" ? PERIOD_M5 : (tf == "H1" ? PERIOD_H1 : (tf == "M30" ? PERIOD_M30 : PERIOD_M15));
   string o = envs("VPINP", "");
   std::stringstream ss(o); string kv;
   while(std::getline(ss, kv, ',')) {
      size_t e = kv.find('='); if(e == string::npos) continue;
      string k = kv.substr(0, e); double v = atof(kv.substr(e + 1).c_str());
      if(k == "InpStrictMode") InpStrictMode = v != 0;
      else if(k == "InpUseHullFilter") InpUseHullFilter = v != 0;
      else if(k == "InpRequireRejection") InpRequireRejection = v != 0;
      else if(k == "InpMinTouchBars") InpMinTouchBars = (int)v;
      else if(k == "InpProfileMode") InpProfileMode = (ENUM_PROFILE_MODE)(int)v;
      else if(k == "InpAutoDST") InpAutoDST = v != 0;
      else if(k == "InpVADistance") InpVADistance = v;
      else if(k == "InpMinWickRatio") InpMinWickRatio = v;
      else if(k == "InpIncludeOpenTick") InpIncludeOpenTick = v != 0;
      else if(k == "InpHullPeriod") InpHullPeriod = (int)v;
      else if(k == "InpTimeframe") InpTimeframe = (ENUM_TIMEFRAMES)(int)v;
      else if(k == "InpSimTF") InpSimTF = v == 0 ? PERIOD_CURRENT : PERIOD_M1;
   }
}
int main(int argc, char** argv) {
   int days = 260;
   double kappa = 0.002, sigma = 0.00005;
   int scenario = 0;
   if(argc > 1) scenario = atoi(argv[1]);
   if(argc > 2) days = atoi(argv[2]);
   if(argc > 3) kappa = atof(argv[3]);
   g_datapath = "out";
   system("mkdir -p out/MQL5/Files");
   applyOverrides();
   gen(days, kappa, sigma, 88172645463325252ULL + 7919ULL * (unsigned long long)scenario);
   InpMonthsBack = 0;
   if(scenario == 1) { InpSimTF = PERIOD_CURRENT; }                     // simulate on chart TF
   if(scenario == 2) { InpProfileMode = MODE_DAILY; }
   if(scenario == 3) { InpOneSignalPerSession = false; }
   if(scenario == 4) { InpSpreadPoints = 0; InpCommissionPoints = 0; }   // zero cost sanity
   if(scenario == 5) { InpOptimistic = true; }
   OnStart();
   FILE* fe = fopen("sc_evals.csv", "w");
   fprintf(fe, "time,pstart,pend,poc,vah,val,hull\n");
   for(auto& e : g_evalsS) fprintf(fe, "%s,%s,%s,%.8f,%.8f,%.8f,%.8f\n", TimeToString(e.t).c_str(), TimeToString(e.ps).c_str(), TimeToString(e.pe).c_str(), e.poc, e.vah, e.val, e.hull == EMPTY_VALUE ? 0.0 : e.hull);
   fclose(fe);
   return 0;
}
