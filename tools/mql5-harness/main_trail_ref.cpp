// Riferimento denso per il trailing: esegue la ProcessTrailing() REALE dell'EA VP (estratta verbatim) tick per tick
// su un percorso di prezzo continuo dentro ogni barra (open -> adverse -> favorable -> adverse) e confronta
// il risultato con SimTrail() dello script. Passo tick molto piccolo: l'errore di discretizzazione e' ~passo*gradini.
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>

typedef std::string string;
enum { POSITION_PRICE_OPEN = 1, POSITION_SL, POSITION_TP, POSITION_TYPE, SYMBOL_BID, SYMBOL_ASK, TRADE_ACTION_SLTP };
enum ENUM_POSITION_TYPE { POSITION_TYPE_BUY = 0, POSITION_TYPE_SELL = 1 };
struct MqlTradeRequest { int action = 0; string symbol; ulong position = 0; double sl = 0, tp = 0; };
struct MqlTradeResult { int retcode = 0; };
struct { int digits = 8; } g_SymbolCache;
struct { int order_errors = 0; } g_Stats;
static bool InpDebugMode = false;
inline void PrintFormat(const char*, ...) {}
static const int TRADE_RETCODE_DONE = 10009;
static string _Symbol = "X";
static double cur_bid = 0, pos_sl = 0, pos_tp = 0, pos_open = 0;
inline bool PositionSelectByTicket(ulong) { return true; }
inline double PositionGetDouble(int p) { return p == POSITION_PRICE_OPEN ? pos_open : (p == POSITION_SL ? pos_sl : pos_tp); }
inline long PositionGetInteger(int) { return POSITION_TYPE_BUY; }
inline double SymbolInfoDouble(const string&, int) { return cur_bid; }
inline double NormalizeDouble(double x, int d) { double m = std::pow(10.0, d); return std::round(x * m) / m; }
inline bool OrderSend(const MqlTradeRequest& r, MqlTradeResult& res) { pos_sl = r.sl; res.retcode = TRADE_RETCODE_DONE; return true; }
#include "ea_trailing_fn.inc"

// ritorna classe (1 TP, -1 stop, 0 fine) e R; percorso pessimista; entry a prezzo 0 (u gia' al netto spread)
static int run(const std::vector<std::vector<double>>& bars, double comm, double SL, double TP, double act, double dist, double step, double eps, double& R) {
   pos_open = 0; pos_sl = -SL; pos_tp = 0; const bool hasTP = TP > 0;
   auto tick = [&](double p, bool& done, int& cls) {
      cur_bid = p;
      if(p <= pos_sl + 1e-12) { R = (std::min(p, pos_sl) - comm) / SL; done = true; cls = -1; return; }
      if(hasTP && p >= TP - 1e-12) { R = (std::max(p, TP) - comm) / SL; done = true; cls = 1; return; }
      ProcessTrailing(1, act, dist, step);
   };
   // gap/uscita all'apertura: con p = open il prezzo "salta" -> uscita a open (come SimTrail)
   for(auto& b : bars) {
      double o = b[0], f = b[1], a = b[2];
      bool done = false; int cls = 0;
      // open: stop o TP gappati escono al prezzo di apertura
      cur_bid = o;
      if(o <= pos_sl + 1e-12) { R = (o - comm) / SL; return -1; }
      if(hasTP && o >= TP - 1e-12) { R = (o - comm) / SL; return 1; }
      ProcessTrailing(1, act, dist, step);
      auto seg = [&](double from, double to) {            // ticks da 'from' (escluso) a 'to' (incluso) ogni eps
         int n = std::max(1, (int)std::ceil(std::fabs(to - from) / eps));
         for(int i = 1; i <= n; i++) { double p = from + (to - from) * i / n; tick(p, done, cls); if(done) return; }
      };
      seg(o, a); if(done) return cls;
      seg(a, f); if(done) return cls;
      seg(f, a); if(done) return cls;
   }
   R = (bars.back()[3] - comm) / SL;
   return 0;
}
int main(int argc, char** argv) {
   int maxCases = argc > 1 ? atoi(argv[1]) : 300;
   double eps = argc > 2 ? atof(argv[2]) : 2e-6;
   std::ifstream in("simcases.txt");
   std::string line; int L = 40, n = 0, bad = 0, used = 0, tight = 0; double maxdR = 0;
   while(std::getline(in, line) && n < maxCases * 3) {
      if(line.empty() || line[0] != 'C') continue;
      std::istringstream h(line); std::string tmp; int opt, c1, fl1, c2, fl2; double S, comm, SL, TP, act, dist, step, R1, R2; char bar;
      h >> tmp >> opt >> S >> comm >> SL >> TP >> act >> dist >> step >> bar >> c1 >> R1 >> fl1 >> bar >> c2 >> R2 >> fl2;
      std::vector<std::vector<double>> bars(L, std::vector<double>(4));
      for(int j = 0; j < L; j++) { std::getline(in, line); std::istringstream b(line); b >> tmp >> bars[j][0] >> bars[j][1] >> bars[j][2] >> bars[j][3]; }
      n++;
      if(opt) continue;                                    // ordine ottimista = convenzione, non un percorso
      if(used >= maxCases) break;
      used++;
      // u-space: sottrai lo spread
      for(auto& b : bars) for(int k = 0; k < 4; k++) b[k] -= S;
      double R; int cls = run(bars, comm, SL, TP, act, dist, step, eps, R);
      double dR = std::fabs(R - R2);
      bool ok = (cls == c2) && dR < 4e-3;
      if(dR < 4e-3 && cls != c2) ok = false;
      maxdR = std::max(maxdR, dR);
      if(!ok) { bad++; if(bad <= 8) printf("MISMATCH caso %d: ref cls %d R %.6f | script cls %d R %.6f | SL %.3f TP %.3f act %.3f dist %.3f step %.3f\n", n, cls, R, c2, R2, SL, TP, act, dist, step); }
   }
   printf("trailing: casi %d, mismatch %d, max|dR| %.2e (passo tick %.0e)\n", used, bad, maxdR, eps);
   return bad ? 1 : 0;
}
