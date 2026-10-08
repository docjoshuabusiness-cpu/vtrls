// Harness: fa girare l'EA reale MultiDayRangeBreakout su un broker simulato (tick da barre M1) e registra
// piazzamenti e trade chiusi, da confrontare con MDRB_Study.
#include "mock_broker.h"
bool g_quiet = true; datetime g_now = 0; ENUM_TIMEFRAMES g__Period = PERIOD_M15; string g__Symbol = "EURUSD";
double g_pointval = 0.00001; int g_spreadval = 12; string g_datapath = "out"; std::map<int, std::vector<MqlRates>> g_store; std::vector<FILE*> g_files;
#define INIT_SUCCEEDED 0
#define INIT_PARAMETERS_INCORRECT 2
#include "ea_mdrb_pp.cpp"
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
      OV(MaxTradesPerDay) OV(MaxSpreadPoints) OV(MaxSpreadPctOfSL) OV(SlotScan) OV(SlotFirstHour) OV(SlotLenHours) OV(SlotMinTrades) OV(SlotRankBy) OV(SlotSplitDate) OV(SlotCommissionPoints) OV(SlotWriteFiles)
      OV(Slot1) OV(Slot2) OV(Slot3) OV(Slot4) OV(Slot5) OV(Slot6) OV(Slot7) OV(Slot8) OV(Slot9) OV(Slot10) OV(Slot11) OV(Slot12)
      else if(k == "Timeframe") Timeframe = (ENUM_TIMEFRAMES)(int)v;
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
   MaxSpreadPoints = 0; MaxSpreadPctOfSL = 0; MaxTradesPerDay = 1;
   applyOverrides();
   gen(days, kappa, sigma_default(), 88172645463325252ULL + 7919ULL * (unsigned long long)scenario);
   auto& m1 = g_store[(int)PERIOD_M1];
   if(OnInit() != INIT_SUCCEEDED) { fprintf(stderr, "OnInit failed\n"); return 1; }
   enum Pat { FLAT, LONG, SHORT };
   for(const auto& b : m1) {
      g_spreadPrice = b.spread * g_pointval;
      datetime t0 = b.time;
      int k = 0;
      auto doTick = [&](double px, bool isOpen) {
         brokerTick(t0 + std::min(k, 59), px, isOpen); k++;
         if(getenv("MDRB_TRACE_T") && t0 >= atoll(getenv("MDRB_TRACE_T")) && t0 < atoll(getenv("MDRB_TRACE_T")) + 180)
            fprintf(stderr, "   tick %s k=%d px %.7f pos=%zu%s\n", TimeToString(t0, TIME_DATE | TIME_MINUTES).c_str(), k, px, g_pos.size(), g_pos.empty() ? "" : (" sl " + std::to_string(g_pos[0].sl)).c_str());
         OnTick();
      };
      doTick(b.open, true);
      double cur = b.open;
      // schema dei prezzi chiave in base allo stato; percorso continuo (1 punto per tick) quando serve
      std::vector<double> keys;
      bool dense = true;
      if(!g_pos.empty()) {
         if(g_pos[0].type == POSITION_TYPE_BUY) keys = {b.low, b.high, b.low, b.close}; else keys = {b.high, b.low, b.high, b.close};
      } else {
         bool hasB = false, hasS = false;
         for(auto& o : g_orders) { if(o.type == ORDER_TYPE_BUY_STOP) hasB = true; if(o.type == ORDER_TYPE_SELL_STOP) hasS = true; }
         if(hasB && hasS) {
            double buyPx = 0, sellPx = 0;
            for(auto& o : g_orders) { if(o.type == ORDER_TYPE_BUY_STOP) buyPx = o.price; else sellPx = o.price; }
            bool highFirst = (buyPx - (b.open + g_spreadPrice)) < (b.open - sellPx);
            if(highFirst) keys = {b.high, b.low, b.close}; else keys = {b.low, b.high, b.close};
         } else if(hasB) keys = {b.high, b.low, b.close};
         else if(hasS) keys = {b.low, b.high, b.close};
         else {
            // nessun ordine: se il range e' noto e il prezzo e' fuori zona, il percorso scende/sale fino al minimo/massimo
            // attraversando la zona in cui l'EA piazza la coppia
            keys = {b.close};
            dense = false;
            if(g_rangeOK && !ChaseIfBroken && InEntryWindow(g_now)) {
               double buyPx = NormPrice(g_upper + PendingOrderOffsetPoints * _Point), sellPx = NormPrice(g_lower - PendingOrderOffsetPoints * _Point);
               double upperBid = buyPx - g_spreadPrice - g_stopsLevel * _Point - TickSize() * 0.5;
               double lowerBid = sellPx + g_stopsLevel * _Point + TickSize() * 0.5;
               if(b.open >= upperBid && b.low < upperBid) { keys = {b.low, b.close}; dense = true; }
               else if(b.open <= lowerBid && b.high > lowerBid) { keys = {b.high, b.close}; dense = true; }
            }
         }
      }
      bool fixedPath = (envs("PATHMODE", "") == "fixed");
      if(fixedPath) { keys = ((b.high - b.open) <= (b.open - b.low)) ? std::vector<double>{b.high, b.low, b.close} : std::vector<double>{b.low, b.high, b.close}; dense = true; }
      size_t ki = 0;
      while(ki < keys.size()) {
         double target = keys[ki];
         double px;
         double stepPx = g_pointval * (getenv("TICKSTEP_PTS") ? atof(getenv("TICKSTEP_PTS")) : 1.0);
         if(!dense || std::fabs(target - cur) <= stepPx * 1.0000001) { px = target; ki++; }
         else px = cur + (target > cur ? 1.0 : -1.0) * stepPx;
         size_t before = g_pos.size();
         doTick(px, false);
         cur = px;
         if(fixedPath) continue;
         if(g_pos.size() < before) { keys = {b.close}; ki = 0; dense = false; }      // chiusa: resta solo la chiusura
         else if(g_pos.size() > before && !g_pos.empty()) {
            // appena aperta in questa barra: il minimo (long) / massimo (short) cade PRIMA del riempimento (modello dello studio);
            // dopo il riempimento il percorso prosegue verso l'estremo favorevole e poi alla chiusura
            keys = (g_pos.back().type == POSITION_TYPE_BUY) ? std::vector<double>{b.high, b.close} : std::vector<double>{b.low, b.close};
            ki = 0; dense = true;
         }
      }
   }
   { double ot = OnTester(); OnDeinit(0); if(envs("MDRB_TRACE_TESTER", "") == "1") fprintf(stderr, "OnTester %.6f\n", ot); }
   FILE* f = fopen("mdrb_ea_trades.csv", "w");
   fprintf(f, "ticket,dir,topen,tclose,entry,exit,R\n");
   for(auto& c : g_closed) fprintf(f, "%llu,%d,%s,%s,%.8f,%.8f,%.6f\n", (unsigned long long)c.ticket, c.dir, TimeToString(c.topen, TIME_DATE | TIME_MINUTES).c_str(), TimeToString(c.tclose, TIME_DATE | TIME_MINUTES).c_str(), c.entry, c.exit, c.R);
   fclose(f);
   f = fopen("mdrb_ea_orders.csv", "w");
   fprintf(f, "t,type,price\n");
   for(auto& o : g_horders) fprintf(f, "%s,%d,%.8f\n", TimeToString(o.t, TIME_DATE | TIME_MINUTES).c_str(), o.type, o.price);
   fclose(f);
   fprintf(stderr, "EA: ordini %zu, trade chiusi %zu, posizioni aperte a fine dati %zu\n", g_horders.size(), g_closed.size(), g_pos.size());
   return 0;
}
