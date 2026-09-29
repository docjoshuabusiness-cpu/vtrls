// Banco di prova: serie sintetiche con effetti piantati + chiamata dei moduli nuovi
#include "gen.cpp"
#include <random>
#include <fstream>
#include <iostream>

static std::mt19937_64 rng(getenv("SEED") ? atoll(getenv("SEED")) : 20240607);
static double gauss() { static std::normal_distribution<double> nd(0.0, 1.0); return nd(rng); }
static double unif() { static std::uniform_real_distribution<double> u(0.0, 1.0); return u(rng); }

struct Cfg { bool plant; int years; bool pure; bool gaps = false; bool sunday = false; bool novol = false; double persist = 0.0; };

static void makeSeries(CSeries &h1, CSeries &d1, const Cfg &cfg)
  {
   MqlDateTime st; st.year = 2005; st.mon = 1; st.day = 3; st.hour = 0; st.min = 0; st.sec = 0;
   datetime t0 = StructToTime(st);
   long ndays = cfg.years > 0 ? cfg.years * 365 : -cfg.years;
   std::vector<datetime> T; std::vector<double> O, H, L, C, V;
   double price = 1000.0;
   const double seas[24] = {0.5,0.5,0.5,0.5,0.5,0.6,0.7,0.9,1.0,1.0,1.0,1.0,1.0,1.1,1.2,1.8,1.5,1.2,0.8,0.7,0.6,0.6,0.5,0.5};
   for(long d = 0; d < ndays; d++)
     {
      datetime day0 = t0 + d * 86400;
      int dow = (int)(((day0 / 86400) + 3) % 7);  // 0 = lunedi'
      if(dow >= 5 && !(cfg.sunday && dow == 6)) continue;
      if(cfg.gaps && unif() < 0.05) continue;
      // giorno: ora dell'evento (piantato) e regime
      int ev = -1;
      if(cfg.plant)
        {
         if(unif() < 0.5) ev = 14; else ev = 9 + (int)(unif() * 12);
        }
      static double lv = 0.0;
      lv = cfg.persist * lv + 0.25 * std::sqrt(1.0 - cfg.persist * cfg.persist) * gauss();
      double dayVol = cfg.pure ? 0.0008 : 0.0008 * std::exp(lv);
      for(int h = 0; h < 24; h++)
        {
         if(cfg.sunday && dow == 6 && h < 22) continue;
         if(cfg.sunday && dow == 4 && h >= 22) continue;
         if(cfg.gaps && unif() < 0.02) continue;
         double s = (cfg.pure ? 1.0 : seas[h]) * dayVol;
         double drift = 0.000004;
         if(cfg.plant)
           {
            if(ev >= 0)
              {
               if(h == ev) s *= 4.0;
               if(h < ev && h >= ev - 3) s *= 0.4;
              }
            if(dow == 0) drift += 0.00005;             // lunedi' rialzista
            if(dow == 2 && h == 10) drift += 0.0006;   // mercoledi' alle 10: forte rialzo
            if(dow >= 2) drift -= 0.00002;             // mercoledi'-venerdi' in calo: massimo settimanale presto
           }
         double r = drift + s * gauss();
         double o = price, c = price * std::exp(r);
         double hi = std::max(o, c) * (1.0 + std::fabs(gauss()) * s * 0.4);
         double lo = std::min(o, c) * (1.0 - std::fabs(gauss()) * s * 0.4);
         T.push_back(day0 + h * 3600); O.push_back(o); H.push_back(hi); L.push_back(lo); C.push_back(c);
         V.push_back(1000 * seas[h] * (1 + 0.3 * std::fabs(gauss())));
         price = c;
        }
     }
   int n = (int)T.size();
   ArrayResize(h1.t, n); ArrayResize(h1.o, n); ArrayResize(h1.h, n); ArrayResize(h1.l, n); ArrayResize(h1.c, n); ArrayResize(h1.v, n); ArrayResize(h1.sp, n);
   for(int i = 0; i < n; i++) { h1.t[i] = T[i]; h1.o[i] = O[i]; h1.h[i] = H[i]; h1.l[i] = L[i]; h1.c[i] = C[i]; h1.v[i] = V[i]; h1.sp[i] = 0; }
   h1.n = n; h1.hasVol = !cfg.novol;
   // D1
   std::vector<int> ds;
   for(int i = 0; i < n; i++) if(i == 0 || T[i] / 86400 != T[i - 1] / 86400) ds.push_back(i);
   int nd = (int)ds.size();
   ArrayResize(d1.t, nd); ArrayResize(d1.o, nd); ArrayResize(d1.h, nd); ArrayResize(d1.l, nd); ArrayResize(d1.c, nd); ArrayResize(d1.v, nd); ArrayResize(d1.sp, nd);
   for(int k = 0; k < nd; k++)
     {
      int a = ds[k], e = k + 1 < nd ? ds[k + 1] : n;
      double hi = -1e300, lo = 1e300, vv = 0;
      for(int i = a; i < e; i++) { hi = std::max(hi, H[i]); lo = std::min(lo, L[i]); vv += V[i]; }
      d1.t[k] = T[a]; d1.o[k] = O[a]; d1.h[k] = hi; d1.l[k] = lo; d1.c[k] = C[e - 1]; d1.v[k] = vv; d1.sp[k] = 0;
     }
   d1.n = nd; d1.hasVol = !cfg.novol;
  }

static void writeHtml(const char *fn, const string &title)
  {
   std::ifstream cf("css.txt"); std::string css((std::istreambuf_iterator<char>(cf)), std::istreambuf_iterator<char>());
   std::ofstream f(fn);
   f << "<!doctype html><html><head><meta charset='utf-8'><title>" << title << "</title><style>" << css
     << "</style></head><body><main>" << g_out << "</main></body></html>";
  }

static void testMath()
  {
   // erfc contro std::erfc
   double worst = 0;
   for(double x = -6; x <= 6; x += 0.05)
     {
      double a = EdErfc(x), b = std::erfc(x);
      double rel = std::fabs(a - b) / std::max(b, 1e-300);
      if(rel > worst) worst = rel;
     }
   printf("EdErfc: errore relativo massimo %.3e\n", worst);
   printf("EdP2(1.96)=%.5f  EdP2(3)=%.6f  EdP2(5)=%.3e\n", EdP2(1.96), EdP2(3.0), EdP2(5.0));
   printf("EdZCrit(0.05,1)=%.4f  (0.05,100)=%.4f  (0.05,10000)=%.4f\n", EdZCrit(0.05, 1), EdZCrit(0.05, 100), EdZCrit(0.05, 10000));
   // BH: 1000 test nulli + 5 effetti veri
   Arr<double> z = Arr<double>(1005);
   for(int i = 0; i < 1000; i++) z[i] = gauss();
   for(int i = 0; i < 5; i++) z[1000 + i] = 6.0 + i;
   Arr<bool> fl;
   EdBhFlags(z, 1005, 1005.0, 0.05, fl);
   int nf = 0, nTrue = 0;
   for(int i = 0; i < 1005; i++) if(fl[i]) { nf++; if(i >= 1000) nTrue++; }
   printf("BH: sopravvissuti %d, di cui veri %d su 5 (attesi falsi <= 5%%)\n", nf, nTrue);
  }

static void runCase(const char *name, bool plant, int years, bool withFake, bool pure = false, bool gaps = false, bool sunday = false, bool novol = false)
  {
   printf("\n===== CASO %s =====\n", name);
   g_out = ""; g_buf = false; g_bufS = "";
   g_hiN = 0; ArrayInitialize(g_hiCnt, 0);
   g_ref = 1; g_refOffA = 0; g_refOffB = 0;
   g_digits = 2;
   CSeries h1, d1;
   makeSeries(h1, d1, Cfg{plant, years, pure, gaps, sunday, novol, getenv("PERSIST") ? atof(getenv("PERSIST")) : 0.0});
   g_last = h1.c[h1.n - 1];
   printf("H1 %d barre, D1 %d barre\n", h1.n, d1.n);
   EdgeReset();
   clock_t c0 = clock();
   BiasTab(h1, d1);
   { char fb[128]; snprintf(fb, sizeof fb, "out_%s_bias.html", name); writeHtml(fb, S(name)); g_out = ""; }
   printf("BiasTab: %.2f s, test %d, righe %d, Hi %d\n", (double)(clock() - c0) / CLOCKS_PER_SEC, g_bxNT, g_bxRN, g_hiN);
   {
      int c2 = 0, c3 = 0, fdr = 0, rob = 0;
      for(int t = 0; t < g_bxNT; t++) { if(std::fabs(g_bxTz[t]) >= 2) c2++; if(std::fabs(g_bxTz[t]) >= 3) c3++; if(g_bxTfd[t]) fdr++; if(g_bxTfd[t] && g_bxTst[t]) rob++; }
      printf("test %d: |z|>=2 %d (attesi %.0f), |z|>=3 %d (attesi %.1f), FDR %d, robusti %d\n", g_bxNT, c2, g_bxNT * 0.0455, c3, g_bxNT * 0.0027, fdr, rob);
      { int nw = 0, nwRaw = 0; for(int r = 0; r < g_bxRN; r++) if(g_bxRTf[r] == 6 && g_bxRCat[r] >= 0 && MathIsValidNumber(g_bxRZ[r * BX_NM + 2])) { double z = g_bxRZ[r * BX_NM + 2]; if(std::fabs(z) >= 3) nw++; if(std::fabs(z * std::sqrt(g_bxInfl[6])) >= 3) nwRaw++; }
        printf("range per giorno della settimana: |z|>=3 corretto %d, grezzo %d (fattore %.2f)\n", nw, nwRaw, g_bxInfl[6]); }
      int byk[4] = {0,0,0,0}, byt[4] = {0,0,0,0};
      for(int t = 0; t < g_bxNT; t++) { byt[g_bxTk[t]]++; if(g_bxTfd[t] && g_bxTst[t]) byk[g_bxTk[t]]++; }
      printf("robusti per tipo: direzione %d/%d, volatilita' %d/%d, timing %d/%d, precedenti %d/%d\n", byk[0], byt[0], byk[1], byt[1], byk[2], byt[2], byk[3], byt[3]);
   }
   if(withFake)
     {
      // costi: COSTMODE = broker (default, spread 0.5), none (nessun profilo: costo n/d), zero (profilo con spread nullo), ref (solo InpEdRefCostBp = 0.5 pb)
      const char *cmEnv = getenv("COSTMODE");
      std::string costMode = cmEnv ? cmEnv : "broker";
      printf("COSTMODE %s\n", costMode.c_str());
      if(costMode == "broker" || costMode == "zero")
        {
         g_cp[1].on = true; g_cp[1].name = S("FP Markets"); g_cp[1].comm = 0; g_cp[1].slip = 0;
         for(int h = 0; h < 24; h++) { g_cp[1].sp[h] = costMode == "zero" ? 0.0 : 0.5; g_cp[1].spOk[h] = true; }
        }
      if(costMode == "ref") InpEdRefCostBp = 0.5;
      // candidati R/R finti
      ArrayResize(g_ckKind, 4); ArrayResize(g_ckNn, 4); ArrayResize(g_ckZ, 4); ArrayResize(g_ckE, 4); ArrayResize(g_ckSt, 4);
      ArrayResize(g_ckZh, 4); ArrayResize(g_ckZp, 4); ArrayResize(g_ckBe, 4); ArrayResize(g_ckLab, 4); ArrayResize(g_ckI, 4);
      double zs[4] = {1.2, 5.1, 3.4, 8.9};
      int kd[4] = {0, 1, 2, 1};
      for(int c = 0; c < 4; c++)
        {
         g_ckKind[c] = kd[c]; g_ckNn[c] = 800 + c * 100; g_ckZ[c] = zs[c]; g_ckE[c] = 0.04 + 0.01 * c; g_ckSt[c] = c != 2;
         g_ckZh[c] = c == 1 ? 3.0 : 1.0; g_ckZp[c] = 2.5; g_ckBe[c] = c == 3 ? 0.2 : 2.0; g_ckLab[c] = S("Ora: 16h &agrave; test"); g_ckI[c] = c;
        }
      for(int c = 0; c < 4; c++)
        {
         Arr<SqR> rs = Arr<SqR>(NPRF); Arr<bool> ok = Arr<bool>(NPRF);
         for(int p = 0; p < NPRF; p++)
           {
            ok[p] = p <= 1; ZeroMemory(rs[p]);
            rs[p].n = 300; rs[p].nY = 10; rs[p].posY = c == 1 ? 8 : 5; rs[p].yrs = 10; rs[p].e = 0.03 + 0.01 * c - 0.005 * p; rs[p].pf = 1.2;
            rs[p].dd = 10; rs[p].dd95 = 12;
           }
         EdgeAddRR(S("H1"), c, c, rs, ok);
        }
      // ORB finto
      g_obNF = 2; g_obMinDay = 30;
      ArrayResize(g_osDay, 10); ArrayInitialize(g_osDay, 120);
      int ntr = 10 * 2 * OB_NT * 3;
      ArrayResize(g_otN, ntr); ArrayResize(g_otEw, ntr); ArrayResize(g_otZw, ntr); ArrayResize(g_otZp, ntr); ArrayResize(g_otBe, ntr); ArrayResize(g_otSt, ntr);
      for(int i = 0; i < ntr; i++) { g_otN[i] = 150; g_otZw[i] = gauss(); g_otEw[i] = 0.01 * g_otZw[i]; g_otZp[i] = g_otZw[i]; g_otBe[i] = 2.0; g_otSt[i] = unif() < 0.5; }
      g_otZw[7] = 4.2; g_otEw[7] = 0.06; g_otSt[7] = true; g_otZp[7] = 3.5; g_otBe[7] = 1.0;
      g_otZw[100] = 3.3; g_otEw[100] = 0.04; g_otSt[100] = true; g_otZp[100] = 1.0; g_otBe[100] = 0.2;
      g_orN = 2; ArrayResize(g_orX, 2); g_orX[0] = 7; g_orX[1] = 100;
     }
   c0 = clock();
   EdgeTab(S("TEST"));
   printf("EdgeTab: %.2f s, candidati %d\n", (double)(clock() - c0) / CLOCKS_PER_SEC, g_edNC);
   char fn[128]; snprintf(fn, sizeof fn, "out_%s_edge.html", name);
   writeHtml(fn, S(name));
   std::ofstream t1(std::string("out_") + name + "_bias.txt"); t1 << g_repBias;
   std::ofstream t2(std::string("out_") + name + "_edge.txt"); t2 << g_repEdge;
   printf("scritti %s (%zu byte) e testi\n", fn, g_out.size());
  }

int main(int argc, char **argv)
  {
   testMath();
   std::string which = argc > 1 ? argv[1] : "all";
   if(which == "all" || which == "plant") runCase("plant", true, 12, true);
   if(which == "all" || which == "null") runCase("null", false, 12, false);
   if(which == "all" || which == "pure") runCase("pure", false, 12, false, true);
   if(which == "all" || which == "gaps") runCase("gaps", true, 8, true, false, true, false, false);
   if(which == "all" || which == "sunday") runCase("sunday", true, 6, true, false, true, true, false);
   if(which == "all" || which == "novol") runCase("novol", true, 5, true, false, false, false, true);
   if(which == "all" || which == "short") runCase("short", true, 1, true, false, false, false, false);
   if(which == "all" || which == "tiny") runCase("tiny", true, -40, false, false, false, false, false);
   if(which == "all" || which == "small") runCase("small", true, -300, false, false, false, false, false);
   return 0;
  }
