// Banco di prova del modulo Candele: serie M1 sintetiche con effetti piantati e puro rumore
#include "gen.cpp"
#include <random>
#include <fstream>
#include <iostream>

static std::mt19937_64 rng(getenv("SEED") ? atoll(getenv("SEED")) : 20240607);
static double gauss() { static std::normal_distribution<double> nd(0.0, 1.0); return nd(rng); }
static double unif() { static std::uniform_real_distribution<double> u(0.0, 1.0); return u(rng); }

struct Cfg { bool plant; int days; bool pure; bool sunday = false; bool novol = false; bool gaps = false; bool m5 = false; bool volreg = false; };

// M1 (o M5) su orologio New York + 7: lunedi'-venerdi', 24 ore
static void makeSeries(CSeries &b, const Cfg &cfg)
  {
   MqlDateTime st; st.year = 2018; st.mon = 1; st.day = 1; st.hour = 0; st.min = 0; st.sec = 0;
   datetime t0 = StructToTime(st);
   std::vector<datetime> T; std::vector<double> O, H, L, C, V;
   double price = 1.1000;
   int prevPin = 0;   // 1 = pin inferiore, -1 = pin superiore sulla barra precedente
   const double seas[24] = {0.4,0.4,0.5,0.5,0.6,0.7,0.9,1.1,1.3,1.2,1.1,1.0,1.0,1.2,1.5,1.4,1.2,1.0,0.8,0.7,0.6,0.5,0.4,0.4};
   int step = cfg.m5 ? 5 : 1;
   long ndays = cfg.days;
   bool impNext = false;
   double lv = 0;
   for(long d = 0; d < ndays; d++)
     {
      datetime day0 = t0 + d * 86400;
      int dow = (int)(((day0 / 86400) + 3) % 7);
      if(dow >= 5 && !(cfg.sunday && dow == 6)) continue;
      if(cfg.gaps && unif() < 0.03) continue;
      lv = 0.9 * lv + 0.2 * gauss();
      double dayVol = cfg.pure ? 0.00006 : 0.00006 * std::exp(lv * 0.5);
      if(cfg.volreg) dayVol = 0.00006 * std::exp(lv * 0.8);
      for(int mi = 0; mi < 1440; mi += step)
        {
         int h = mi / 60;
         if(cfg.sunday && dow == 6 && h < 22) continue;
         if(cfg.gaps && unif() < 0.01) continue;
         double s = (cfg.pure ? 1.0 : seas[h]) * dayVol * std::sqrt((double)step);
         double drift = 0.0;
         bool imp = false;
         if(cfg.plant)
           {
            if(h == 14) s *= 1.8;
            if(dow == 2 && h == 10) drift += 0.02 * s;             // mercoledi' alle 10: rialzista
            if(dow == 2) drift += 0.02 * s;                        // mercoledi' rialzista
            if(prevPin == 1) drift += 0.35 * s;                    // dopo un pin inferiore rialzo
            if(prevPin == -1) drift -= 0.35 * s;                   // dopo un pin superiore ribasso
            imp = unif() < 0.004;
           }
         double rr = drift + s * gauss();
         if(imp) rr = (unif() < 0.5 ? 1 : -1) * s * (4.0 + std::fabs(gauss()));
         double o = price, c = price * std::exp(rr);
         double wu = std::fabs(gauss()) * s * 0.5, wl = std::fabs(gauss()) * s * 0.5;
         double hi = std::max(o, c) * (1.0 + wu), lo = std::min(o, c) * (1.0 - wl);
         double vol = 100 * (cfg.pure ? 1.0 : seas[h]) * (1 + 0.3 * std::fabs(gauss()));
         if(cfg.plant && impNext) vol *= 3.0;   // volume alto prima dell'impulso (piantato)
         impNext = false;
         if(cfg.plant)
           {
            // decide ora se la prossima barra sara' un impulso: pianta il volume alto nella barra corrente non ancora scritta
           }
         {
            double R = hi - lo, B = std::fabs(c - o), U = hi - std::max(o, c), Lw = std::min(o, c) - lo;
            prevPin = 0;
            if(R > 0 && B / R <= 0.35) { if(Lw / R >= 0.55 && U / R <= 0.20) prevPin = 1; else if(U / R >= 0.55 && Lw / R <= 0.20) prevPin = -1; }
         }
         T.push_back(day0 + mi * 60); O.push_back(o); H.push_back(hi); L.push_back(lo); C.push_back(c); V.push_back(vol);
         price = c;
         (void)imp;
        }
     }
   // secondo passaggio: volume alto nella barra prima di ogni impulso (barra con range enorme)
   if(cfg.plant)
     {
      for(size_t i = 1; i < T.size(); i++)
        {
         double rg = (H[i] - L[i]) / C[i - 1];
         if(rg > 0.00006 * 4.5) V[i - 1] *= 3.0;
        }
     }
   int n = (int)T.size();
   ArrayResize(b.t, n); ArrayResize(b.o, n); ArrayResize(b.h, n); ArrayResize(b.l, n); ArrayResize(b.c, n); ArrayResize(b.v, n); ArrayResize(b.sp, n);
   for(int i = 0; i < n; i++) { b.t[i] = T[i]; b.o[i] = O[i]; b.h[i] = H[i]; b.l[i] = L[i]; b.c[i] = C[i]; b.v[i] = V[i]; b.sp[i] = 0; }
   b.n = n; b.hasVol = !cfg.novol;
  }

static void writeHtml(const char *fn, const std::string &title)
  {
   std::ifstream cf("css.txt"); std::string css((std::istreambuf_iterator<char>(cf)), std::istreambuf_iterator<char>());
   std::ofstream f(fn);
   f << "<!doctype html><html><head><meta charset='utf-8'><title>" << title << "</title><style>" << css
     << "</style></head><body><main>" << g_out << "</main></body></html>";
  }

static void runCase(const char *name, const Cfg &cfg)
  {
   printf("\n===== CASO %s =====\n", name);
   g_out = ""; g_buf = false; g_bufS = "";
   g_hiN = 0; ArrayInitialize(g_hiCnt, 0);
   g_ref = 1; g_refOffA = 0; g_refOffB = 0;
   g_digits = 5;
   CSeries b;
   makeSeries(b, cfg);
   printf("barre base %d (%s)\n", b.n, cfg.m5 ? "M5" : "M1");
   clock_t c0 = clock();
   CandTab(b, cfg.m5 ? 300 : 60, S("TEST"));
   printf("CandTab: %.2f s, output %zu byte, testo %zu byte\n", (double)(clock() - c0) / CLOCKS_PER_SEC, g_out.size(), g_cxTxt.size() + g_cxTxtTf.size());
   printf("confronti %lld, memorizzati (|z|>=2) %d, Hi %d, attesi |z|>=2 per caso %.0f\n", (long long)g_cxNAll, g_cxNT, g_hiN, g_cxNAll * 0.0455);
   int nfd = 0, nrob = 0, n3 = 0;
   for(int i = 0; i < g_cxNT; i++) { if(g_cxTfd[i]) nfd++; if(g_cxTfd[i] && g_cxTst[i]) nrob++; if(std::fabs(g_cxTz[i]) >= 3) n3++; }
   printf("oltre |z| 3: %d (attesi per caso %.1f), FDR %d, robusti %d\n", n3, g_cxNAll * 0.0027, nfd, nrob);
   int byk[9] = {0}, byt[9] = {0};
   for(int i = 0; i < g_cxNT; i++) { byt[g_cxTk[i]]++; if(g_cxTfd[i] && g_cxTst[i]) byk[g_cxTk[i]]++; }
   printf("robusti per tipo (0 classe su, 1 classe rend1, 2 cat su, 3 cat rend, 4 cat grandi, 5 cat impulsi, 6 precursori, 7 cat range, 8 classe rend3):\n");
   for(int k = 0; k < 9; k++) printf("  tipo %d: %d robusti su %d con |z|>=2\n", k, byk[k], byt[k]);
   {
      int rbf[CX_NFAM] = {0}, ttf[CX_NFAM] = {0};
      for(int i = 0; i < g_cxNT; i++)
        {
         int f = CxFamily(g_cxTk[i], g_cxTu[i]);
         ttf[f]++; if(g_cxTfd[i] && g_cxTst[i]) rbf[f]++;
        }
      const char *fn2[CX_NFAM] = {"classi", "dir.ora/minuto", "dir.calendario", "ritmo ora/minuto", "ritmo calendario", "precursori"};
      for(int f = 0; f < CX_NFAM; f++)
         printf("  famiglia %-16s: confronti %6lld, |z|>=2 %4d, robusti %4d\n", fn2[f], (long long)g_cxNFam[f], ttf[f], rbf[f]);
     }
   for(int ti = 0; ti < CX_NTF; ti++)
      printf("  %-3s n %8d soglia %5.2f impulsi %6d (%.2f%%) test %5d robusti %4d skip %d\n", CX_NAME[ti].c_str(), g_cxN[ti], g_cxThr[ti], g_cxNimp[ti],
             g_cxN[ti] > 0 ? 100.0 * g_cxNimp[ti] / g_cxN[ti] : 0.0, g_cxNtst[ti], g_cxNrob[ti], g_cxSkip[ti]);
   {
      // distribuzione degli z (classi: 3 misure; categorie: 5 misure) sui timeframe calcolati
      double s1 = 0, s2 = 0; long nz = 0; long over2 = 0;
      for(int ti = 0; ti < CX_NTF; ti++)
        {
         for(int u = 1; u < CX_NCL; u++)
            for(int k = 0; k < 3; k++)
              {
               double z = g_cxC[(ti * CX_NCL + u) * CX_NF + (k == 0 ? 2 : (k == 1 ? 5 : 17))];
               if(MathIsValidNumber(z)) { s1 += z; s2 += z * z; nz++; if(std::fabs(z) >= 2) over2++; }
              }
        }
      printf("z delle classi: n %ld, media %.3f, sd %.3f, |z|>=2 %.2f%% (attesa 4.55%% sotto H0)\n", nz, nz ? s1 / nz : 0.0, nz ? std::sqrt(s2 / nz - (s1 / nz) * (s1 / nz)) : 0.0, nz ? 100.0 * over2 / nz : 0.0);
   }
   if(getenv("DBGZ"))
     {
      int ti = 0;
      for(int u = CX_K_TOD + 12; u <= CX_K_TOD + 16; u++)
        {
         int b = (ti * CX_NCU + u) * CX_NFK;
         printf("  M1 ora %d: n %.0f range %.3f z %.2f | up %.3f z %.2f | grandi %.4f z %.2f | imp %.4f z %.2f\n", u - CX_K_TOD, g_cxK[b], g_cxK[b + 3], g_cxK[b + 8], g_cxK[b + 1], g_cxK[b + 6], g_cxK[b + 4], g_cxK[b + 9], g_cxK[b + 5], g_cxK[b + 10]);
        }
     }
   if(getenv("SHOWALL"))
      for(int i = 0; i < g_cxNT; i++)
         if(g_cxTfd[i])
            printf("  FDR z %+.1f st %d kind %d: %s\n", g_cxTz[i], (int)g_cxTst[i], g_cxTk[i], g_cxTtx[i].c_str());
   if(getenv("SHOWROB"))
      for(int i = 0; i < g_cxNT; i++)
         if(g_cxTfd[i] && g_cxTst[i] && g_cxTk[i] != 4 && g_cxTk[i] != 5 && g_cxTk[i] != 7)
            printf("  ROB z %+.1f kind %d: %s\n", g_cxTz[i], g_cxTk[i], g_cxTtx[i].c_str());
   char fn[128]; snprintf(fn, sizeof fn, "out_%s_cand.html", name);
   writeHtml(fn, name);
   std::ofstream t1(std::string("out_") + name + "_cand.txt"); t1 << g_cxTxt << g_cxTxtTf;
   printf("scritti %s\n", fn);
  }

int main(int argc, char **argv)
  {
   std::string which = argc > 1 ? argv[1] : "all";
   if(getenv("ROLL")) InpRollSkip = atoi(getenv("ROLL")) != 0;
   if(getenv("TZ7")) InpDataTZ = (ENUM_DATA_TZ)atoi(getenv("TZ7"));
   if(which == "all" || which == "cplant") runCase("cplant", Cfg{true, 260, false});
   if(which == "all" || which == "cnull") runCase("cnull", Cfg{false, 260, true});
   if(which == "cnullv") runCase("cnullv", Cfg{false, 900, false, false, false, false, false, true});
   if(which == "cnull2") runCase("cnull2", Cfg{false, 2000, true});
   if(which == "cbig2") runCase("cbig2", Cfg{true, 3700, false});
   if(which == "cbig") runCase("cbig", Cfg{true, 900, false});
   if(which == "csun") runCase("csun", Cfg{true, 200, false, true});
   if(which == "cgap") runCase("cgap", Cfg{true, 200, false, false, false, true});
   if(which == "cnovol") runCase("cnovol", Cfg{true, 200, false, false, true});
   if(which == "cm5") runCase("cm5", Cfg{true, 400, false, false, false, false, true});
   if(which == "ctiny") runCase("ctiny", Cfg{true, 12, false});
   return 0;
  }
