#pragma once
// ---- synthetic data
static uint64_t rs = 88172645463325252ULL;
static double urand() { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return (rs >> 11) * (1.0 / 9007199254740992.0); }
static double nrand() { double u = urand() + 1e-12, v = urand(); return std::sqrt(-2.0 * std::log(u)) * std::cos(6.283185307179586 * v); }

static double g_gridF = 1e5;
static std::vector<MqlRates> aggregate(const std::vector<MqlRates>& m1, int per, int mode) {
   std::vector<MqlRates> out;
   long long cur = -1;
   for(const auto& r : m1) {
      long long b;
      if(mode == 1) { long long days = r.time / 86400; b = (days + 3) / 7; }            // weekly (Mon)
      else if(mode == 2) { MqlDateTime d; TimeToStruct(r.time, d); b = d.year * 12 + d.mon; } // monthly
      else b = r.time / per;
      if(b != cur) {
         cur = b;
         MqlRates n = r;
         if(mode == 1) n.time = ((b * 7 - 3) * 86400);
         else if(mode == 2) { MqlDateTime d; TimeToStruct(r.time, d); d.day = 1; d.hour = 0; d.min = 0; d.sec = 0; n.time = StructToTime(d); }
         else n.time = b * per;
         out.push_back(n);
      } else {
         MqlRates& n = out.back();
         n.high = std::max(n.high, r.high); n.low = std::min(n.low, r.low); n.close = r.close; n.tick_volume += r.tick_volume;
      }
   }
   return out;
}

// drift_bias: adds a small directional drift after rejection-like situations to test edge detection (0 = pure random walk)
static void gen(int days, double kappa, double sigma, unsigned long long seed) {
   rs = seed;
   if(getenv("GEN_ROUND")) g_gridF = atof(getenv("GEN_ROUND"));
   // GEN_GAPS=p: ogni barra M1 manca con probabilita' p (come i buchi dello storico reale); GEN_BREAK=1: nessuna barra tra le 22:00 e le 23:00 (pausa giornaliera)
   double gapP = getenv("GEN_GAPS") ? atof(getenv("GEN_GAPS")) : 0.0;
   bool dayBreak = getenv("GEN_BREAK") && atoi(getenv("GEN_BREAK")) != 0;
   std::vector<MqlRates> m1;
   struct tm g; memset(&g, 0, sizeof g);
   g.tm_year = 2023 - 1900; g.tm_mon = 0; g.tm_mday = 2;     // Monday 2023-01-02
   long long t0 = timegm(&g);
   double p = 1.10000, mu = 1.10000;
   int produced = 0;
   for(int d = 0; produced < days; d++) {
      long long day0 = t0 + (long long)d * 86400;
      int dow = (int)((day0 / 86400 + 4) % 7);       // 0=Sun
      if(dow == 0 || dow == 6) continue;
      produced++;
      mu += 0.0008 * nrand();
      for(int mnt = 0; mnt < 1440; mnt++) {
         double hr = mnt / 60.0;
         double act = 0.5 + 1.2 * std::exp(-0.5 * std::pow((hr - 9.0) / 2.5, 2)) + 1.6 * std::exp(-0.5 * std::pow((hr - 16.0) / 2.5, 2));
         double o = p;
         double mv = kappa * (mu - p) + sigma * act * nrand();
         double c = o + mv;
         double h = std::max(o, c) + std::fabs(nrand()) * sigma * act * 0.6;
         double l = std::min(o, c) - std::fabs(nrand()) * sigma * act * 0.6;
         MqlRates r; r.time = day0 + mnt * 60; r.open = std::round(o * g_gridF) / g_gridF; r.high = std::round(h * g_gridF) / g_gridF; r.low = std::round(l * g_gridF) / g_gridF; r.close = std::round(c * g_gridF) / g_gridF;
         r.high = std::max(r.high, std::max(r.open, r.close)); r.low = std::min(r.low, std::min(r.open, r.close));
         r.tick_volume = (long)(40 + 260 * act * urand()); r.spread = 12; r.real_volume = 0;
         p = c;
         if(gapP > 0.0 && urand() < gapP) continue;
         if(dayBreak && mnt >= 22 * 60 && mnt < 23 * 60) continue;
         m1.push_back(r);
      }
   }
   g_store[(int)PERIOD_M1] = m1;
   g_store[(int)PERIOD_M5] = aggregate(m1, 300, 0);
   g_store[(int)PERIOD_M15] = aggregate(m1, 900, 0);
   g_store[(int)PERIOD_H1] = aggregate(m1, 3600, 0);
   g_store[(int)PERIOD_D1] = aggregate(m1, 86400, 0);
   g_store[(int)PERIOD_W1] = aggregate(m1, 0, 1);
   g_store[(int)PERIOD_MN1] = aggregate(m1, 0, 2);
   g_now = m1.back().time + 60;
}


static double sigma_default() { return 0.00005; }
