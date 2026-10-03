#include "mql5_mock.h"
bool g_quiet = true; datetime g_now = 0; ENUM_TIMEFRAMES g__Period = PERIOD_M15; string g__Symbol = "EURUSD";
double g_pointval = 0.00001; int g_spreadval = 12; string g_datapath = "."; std::map<int, std::vector<MqlRates>> g_store; std::vector<FILE*> g_files;
inline void HarnessEvalS(datetime, datetime, datetime, double, double, double, double) {}
#include "study_pp.cpp"
static uint64_t rs = 12345678901234567ULL;
static double urand() { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return (rs >> 11) * (1.0 / 9007199254740992.0); }
static double nrand() { double u = urand() + 1e-12, v = urand(); return std::sqrt(-2.0 * std::log(u)) * std::cos(6.283185307179586 * v); }
int main() {
   FILE* f = fopen("simcases.txt", "w");
   int N = 6000, L = 40;
   g_L = L;
   ArrayResize(g_wO, L); ArrayResize(g_wF, L); ArrayResize(g_wA, L); ArrayResize(g_wC, L);
   for(int n = 0; n < N; n++) {
      InpOptimistic = (n % 2 == 1);
      double gap = (n % 5 == 0) ? 0.8 : 0.0;
      double prev = 0.0;
      for(int j = 0; j < L; j++) {
         double o = prev + (urand() < 0.1 ? gap * nrand() : 0.0);
         double c = o + 0.25 * nrand();
         double h = std::max(o, c) + std::fabs(nrand()) * 0.15;
         double l = std::min(o, c) - std::fabs(nrand()) * 0.15;
         g_wO[j] = o; g_wC[j] = c;
         g_wF[j] = h; g_wA[j] = l;      // g-space: favorable extreme = high, adverse = low
         prev = c;
      }
      double S = (n % 3 == 0) ? 0.0 : 0.05 * urand();
      double comm = (n % 4 == 0) ? 0.03 : 0.0;
      double SL = 0.3 + 1.5 * urand();
      double TP = (n % 6 == 0) ? 0.0 : SL * (0.5 + 3 * urand());
      double act = SL * (0.2 + 2 * urand());
      double dist = SL * (0.3 + 1.5 * urand());
      double step = dist * (urand() < 0.5 ? 0.0 : 0.15);
      double R1, R2; int fl1, fl2;
      int c1 = SimFixed(S, comm, SL, TP, R1, fl1);
      int c2 = SimTrail(S, comm, SL, TP, act, dist, step, R2, fl2);
      fprintf(f, "C %d %.10g %.10g %.10g %.10g %.10g %.10g %.10g | %d %.10g %d | %d %.10g %d\n", (int)InpOptimistic, S, comm, SL, TP, act, dist, step, c1, R1, fl1, c2, R2, fl2);
      for(int j = 0; j < L; j++) fprintf(f, "B %.10g %.10g %.10g %.10g\n", g_wO[j], g_wF[j], g_wA[j], g_wC[j]);
   }
   fclose(f);
   return 0;
}
