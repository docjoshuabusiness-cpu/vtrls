// Harness: MDRB_Study su dati sintetici; esporta piazzamenti e trade eseguiti con le uscite dell'EA per il confronto con l'EA reale.
#include "mql5_mock.h"
bool g_quiet = false; datetime g_now = 0; ENUM_TIMEFRAMES g__Period = PERIOD_M15; string g__Symbol = "EURUSD";
double g_pointval = 0.00001; int g_spreadval = 12; string g_datapath = "out"; std::map<int, std::vector<MqlRates>> g_store; std::vector<FILE*> g_files;
struct PlRow { datetime day, t; double buy, sell; datetime exp; };
static std::vector<PlRow> g_pl;
inline void HarnessPlace(datetime day, datetime t, double buy, double sell, datetime exp) { g_pl.push_back({day, t, buy, sell, exp}); }
#include "study_mdrb_pp.cpp"
#include "gen.h"
#include "ovr.h"

static void applyOverrides() {
   string o = envs("VPINP", "");
   std::stringstream ss(o); string kv;
   while(std::getline(ss, kv, ',')) {
      size_t eq = kv.find('='); if(eq == string::npos) continue;
      string k = kv.substr(0, eq); double v = atof(kv.substr(eq + 1).c_str());
#define OV(n) else if(k == #n) n = (decltype(n))v;
      if(false) {}
      OV(RangeMode) OV(RangeDaysBack) OV(RangeBarsLookback) OV(RangeHourStart) OV(RangeMinuteStart) OV(RangeHourEnd) OV(RangeMinuteEnd) OV(RangeDaySpan)
      OV(RequireRangeConfirmation) OV(MinRangePoints) OV(MaxRangePoints) OV(TradeHourStart) OV(TradeMinuteStart) OV(TradeHourEnd) OV(TradeMinuteEnd)
      OV(ExpireExtraMinutes) OV(PendingOrderOffsetPoints) OV(ChaseIfBroken) OV(StopLossPoints) OV(TakeProfitPoints) OV(UseTakeProfit)
      OV(UsaBreakEven) OV(BreakEvenAttivazione) OV(BreakEvenOffset) OV(UsaTrailingStop) OV(TrailingStartProfit) OV(TrailingStep) OV(TrailingOffset)
      OV(InpMaxHoldHours) OV(InpOptimistic) OV(InpMonthsBack) OV(InpAuto) OV(InpFastPath) OV(InpSpreadPoints) OV(InpCommissionPoints) OV(InpISPercent) OV(InpMinTrades)
      else if(k == "Timeframe") Timeframe = (ENUM_TIMEFRAMES)(int)v;
      else if(k == "InpSimTF") InpSimTF = (ENUM_TIMEFRAMES)(int)v;
      else if(k == "StopsLevel") g_stopsLevel = (long)v;
      else if(k == "TickSize") { g_ticksize = v; }
      else if(k == "Digits") g_digitsval = (int)v;
   }
   string tf = envs("VPTF", "M15");
   g__Period = tf == "M5" ? PERIOD_M5 : (tf == "H1" ? PERIOD_H1 : PERIOD_M15);
}

int main(int argc, char** argv) {
   int days = argc > 1 ? atoi(argv[1]) : 260;
   double kappa = argc > 2 ? atof(argv[2]) : 0.002;
   int scenario = argc > 3 ? atoi(argv[3]) : 0;
   system("mkdir -p out/MQL5/Files");
   applyOverrides();
   gen(days, kappa, sigma_default(), 88172645463325252ULL + 7919ULL * (unsigned long long)scenario);
   InpMonthsBack = 0;
   if(envs("MDRB_QUIET", "0") == "1") g_quiet = true;
   if(envs("MDRB_DUMP_M1", "0") == "1") {
      FILE* fm = fopen("m1.csv", "w");
      for(auto& b : g_store[(int)PERIOD_M1]) fprintf(fm, "%lld,%.8f,%.8f,%.8f,%.8f,%d\n", b.time, b.open, b.high, b.low, b.close, b.spread);
      fclose(fm);
   }
   OnStart();
   // piazzamenti
   FILE* f = fopen("mdrb_sc_orders.csv", "w");
   fprintf(f, "t,buy,sell,exp\n");
   for(auto& p : g_pl) fprintf(f, "%s,%.8f,%.8f,%s\n", TimeToString(p.t, TIME_DATE | TIME_MINUTES).c_str(), p.buy, p.sell, TimeToString(p.exp, TIME_DATE | TIME_MINUTES).c_str());
   fclose(f);
   // trade eseguiti con le uscite dell'EA (cfg di riferimento): regola "nessuna coppia con posizione aperta" + ripiazzamento a meta' finestra
   f = fopen("mdrb_sc_trades.csv", "w");
   fprintf(f, "tfill,dir,R,tplace\n");
   int C = ArraySize(g_cfg);
   int nex = 0;
   for(int e = 0; e < ArraySize(g_ev); e++) {
      int off = e * C + g_refIdx;
      if(g_xR[off] == XR_SKIP) continue;
      nex++;
      fprintf(f, "%s,%d,%.6f,%s\n", TimeToString(g_xT[off], TIME_DATE | TIME_MINUTES).c_str(), g_xD[off], (double)g_xR[off], TimeToString(g_ev[e].tPlace, TIME_DATE | TIME_MINUTES).c_str());
   }
   fclose(f);
   f = fopen("mdrb_meta.txt", "w");
   fprintf(f, "%s\n", TimeToString(g_dataLast - (datetime)((InpMaxHoldHours / 24.0 * 7.0 / 5.0 + 3.0) * 86400.0), TIME_DATE | TIME_MINUTES).c_str());
   fclose(f);
   fprintf(stderr, "Studio: piazzamenti %zu, sfondamenti %d, eseguiti con uscite EA %d\n", g_pl.size(), ArraySize(g_ev), nex);
   return 0;
}
