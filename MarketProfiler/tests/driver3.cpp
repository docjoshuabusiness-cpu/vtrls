// Controllo degli indicatori del modulo Candele contro implementazioni indipendenti (M15 costruito da M1)
#include "gen.cpp"
#include <random>
#include <vector>
#include <cmath>

static std::mt19937_64 rng(4242);
static double gauss() { static std::normal_distribution<double> nd(0.0, 1.0); return nd(rng); }

int main()
  {
   InpRollSkip = false;   // niente rollover: confronto pulito
   CSeries b;
   MqlDateTime st; st.year = 2020; st.mon = 3; st.day = 2; st.hour = 0; st.min = 0; st.sec = 0;   // lunedi'
   datetime t0 = StructToTime(st);
   std::vector<double> O, H, L, C, V; std::vector<long> T;
   double p = 1.2;
   for(int d = 0; d < 46; d++)
     {
      if(d % 7 >= 5) continue;
      for(int m = 0; m < 1440; m++)
        {
         double o = p, c = p * std::exp(0.0004 * gauss() * (1 + 0.5 * std::sin(m / 200.0)));
         double h = std::max(o, c) * (1 + std::fabs(gauss()) * 0.0002), l = std::min(o, c) * (1 - std::fabs(gauss()) * 0.0002);
         T.push_back(t0 + d * 86400L + m * 60L); O.push_back(o); H.push_back(h); L.push_back(l); C.push_back(c);
         V.push_back(100 + 50 * std::fabs(gauss()) + 40 * (m / 60));
         p = c;
        }
     }
   int n = (int)T.size();
   ArrayResize(b.t, n); ArrayResize(b.o, n); ArrayResize(b.h, n); ArrayResize(b.l, n); ArrayResize(b.c, n); ArrayResize(b.v, n); ArrayResize(b.sp, n);
   for(int i = 0; i < n; i++) { b.t[i] = T[i]; b.o[i] = O[i]; b.h[i] = H[i]; b.l[i] = L[i]; b.c[i] = C[i]; b.v[i] = V[i]; b.sp[i] = 0; }
   b.n = n; b.hasVol = true;
   const int SEC = 900;
   CCx q;
   bool ok = CxBuild(b, 0, 60, SEC, q);
   CxFeatures(q, true);
   printf("build ok %d, candele %d\n", (int)ok, q.n);
   // 1) candele contro aggregazione a forza bruta
   int bad = 0;
   {
      long cur = -1; int x = -1;
      std::vector<double> co, ch, cl, cc, cv; std::vector<long> ct; std::vector<int> cn;
      for(int i = 0; i < n; i++)
        {
         long k = T[i] / SEC;
         if(k != cur) { cur = k; ct.push_back(k * SEC); co.push_back(O[i]); ch.push_back(H[i]); cl.push_back(L[i]); cc.push_back(C[i]); cv.push_back(V[i]); cn.push_back(1); x++; }
         else { ch[x] = std::max(ch[x], H[i]); cl[x] = std::min(cl[x], L[i]); cc[x] = C[i]; cv[x] += V[i]; cn[x]++; }
        }
      if((int)ct.size() != q.n) { printf("NUMERO CANDELE DIVERSO %zu %d\n", ct.size(), q.n); bad++; }
      for(int i = 0; i < q.n && i < (int)ct.size(); i++)
         if(q.t[i] != ct[i] || std::fabs(q.o[i] - co[i]) > 1e-12 || std::fabs(q.h[i] - ch[i]) > 1e-12 || std::fabs(q.l[i] - cl[i]) > 1e-12 || std::fabs(q.c[i] - cc[i]) > 1e-12 || std::fabs(q.v[i] - cv[i]) > 1e-9 || q.nb[i] != cn[i]) bad++;
      printf("candele: %d differenze\n", bad);
      // 2) indicatori (catena: tutte le candele valide consecutive della stessa serie; l'ultima puo' essere invalida)
      int m = q.n;
      std::vector<double> tr(m), atrc(m, NAN), atrp(m, NAN);
      for(int i = 0; i < m; i++)
        {
         bool adj = i > 0 && q.ok[i] && q.ok[i - 1] && q.t[i] - q.t[i - 1] == SEC;
         tr[i] = adj ? std::max(ch[i], cc[i - 1]) - std::min(cl[i], cc[i - 1]) : ch[i] - cl[i];
        }
      // le candele non valide (primo e ultimo per copertura, weekend) sono fuori dal flusso: ricostruisco il flusso ok
      std::vector<int> idx; for(int i = 0; i < m; i++) if(q.ok[i]) idx.push_back(i);
      int nk = (int)idx.size();
      printf("candele valide %d su %d\n", nk, m);
      double maxErr[10] = {0}; int nchk[10] = {0};
      // flusso ok
      std::vector<double> trs(nk);
      for(int j = 0; j < nk; j++) trs[j] = tr[idx[j]];
      // ADX di Wilder indipendente
      std::vector<double> pdm(nk, 0), mdm(nk, 0);
      for(int j = 0; j < nk; j++)
        {
         int i = idx[j];
         bool adj = i > 0 && q.ok[i - 1] && q.t[i] - q.t[i - 1] == SEC;
         if(adj) { double up = ch[i] - ch[i - 1], dn = cl[i - 1] - cl[i]; pdm[j] = (up > dn && up > 0) ? up : 0; mdm[j] = (dn > up && dn > 0) ? dn : 0; }
        }
      std::vector<double> adxr(nk, NAN);
      {
         double sT = 0, sP = 0, sM = 0, aS = 0, av = 0; int nS = 0, nD = 0;
         for(int j = 0; j < nk; j++)
           {
            nS++;
            if(nS <= 14) { sT += trs[j]; sP += pdm[j]; sM += mdm[j]; }
            else { sT = sT - sT / 14 + trs[j]; sP = sP - sP / 14 + pdm[j]; sM = sM - sM / 14 + mdm[j]; }
            if(nS >= 14)
              {
               double di1 = 100 * sP / sT, di2 = 100 * sM / sT, dx = (di1 + di2) > 0 ? 100 * std::fabs(di1 - di2) / (di1 + di2) : 0;
               nD++;
               if(nD <= 14) { aS += dx; if(nD == 14) av = aS / 14; } else av = (av * 13 + dx) / 14;
               if(nD >= 14) adxr[j] = av;
              }
           }
      }
      for(int j = 0; j < nk; j++)
        {
         int i = idx[j];
         // ATR
         if(j >= 13) { double s = 0; for(int k = j - 13; k <= j; k++) s += trs[k]; double a = s / 14; double e = std::fabs(q.ac[i] - a) / a; maxErr[0] = std::max(maxErr[0], e); nchk[0]++; }
         if(j >= 14) { double s = 0; for(int k = j - 14; k <= j - 1; k++) s += trs[k]; double a = s / 14; double e = std::fabs(q.ap[i] - a) / a; maxErr[1] = std::max(maxErr[1], e); nchk[1]++; }
         if(j >= 99) { double s14 = 0, s100 = 0; for(int k = j - 13; k <= j; k++) s14 += trs[k]; for(int k = j - 99; k <= j; k++) s100 += trs[k]; double r = (s14 / 14) / (s100 / 100); double e = std::fabs(q.vr[i] - r) / r; maxErr[2] = std::max(maxErr[2], e); nchk[2]++; }
         if(!std::isnan(adxr[j])) { double e = std::fabs(q.adx[i] - adxr[j]); maxErr[3] = std::max(maxErr[3], e); nchk[3]++; }
         else if(!std::isnan(q.adx[i])) { printf("ADX definito troppo presto j=%d\n", j); bad++; }
         // z-score su 20 chiusure
         if(j >= 19)
           {
            double mu = 0; for(int k = j - 19; k <= j; k++) mu += cc[idx[k]]; mu /= 20;
            double vv = 0; for(int k = j - 19; k <= j; k++) vv += (cc[idx[k]] - mu) * (cc[idx[k]] - mu); vv /= 19;
            double z = (cc[i] - mu) / std::sqrt(vv);
            int code = z < -2 ? 0 : (z < -1 ? 1 : (z <= 1 ? 2 : (z <= 2 ? 3 : 4)));
            if(q.zsc[i] != code) { bad++; if(bad < 5) printf("zsc differente j=%d z=%f codice %d contro %d\n", j, z, code, (int)q.zsc[i]); }
            nchk[4]++;
           }
         // posizione nelle 20 candele (con la corrente) e flag; servono 20 candele precedenti
         if(j >= 20)
           {
            double hh = -1e300, ll = 1e300; for(int k = j - 20; k <= j - 1; k++) { hh = std::max(hh, ch[idx[k]]); ll = std::min(ll, cl[idx[k]]); }
            int f = 0; if(cc[i] > hh) f |= 1; if(cc[i] < ll) f |= 2;
            double h9 = -1e300, l9 = 1e300; for(int k = j - 9; k <= j - 1; k++) { h9 = std::max(h9, ch[idx[k]]); l9 = std::min(l9, cl[idx[k]]); }
            if(cl[i] <= l9) f |= 4; if(ch[i] >= h9) f |= 8;
            double rg = ch[i] - cl[i]; double r3 = 1e300, r6 = 1e300; for(int k = j - 6; k <= j - 1; k++) { double r = ch[idx[k]] - cl[idx[k]]; r6 = std::min(r6, r); if(k >= j - 3) r3 = std::min(r3, r); }
            if(rg < r3) f |= 16; if(rg < r6) f |= 32;
            if(q.fl[i] != f) { bad++; if(bad < 8) printf("flag differenti j=%d %d contro %d\n", j, f, (int)q.fl[i]); }
            double h2 = std::max(hh, ch[i]), l2 = std::min(ll, cl[i]); double pos = (cc[i] - l2) / (h2 - l2);
            int pc = pos <= 0.10 ? 0 : (pos <= 0.35 ? 1 : (pos <= 0.65 ? 2 : (pos <= 0.90 ? 3 : 4)));
            if(q.dnc[i] != pc) { bad++; if(bad < 8) printf("dnc differente j=%d\n", j); }
            nchk[5]++;
           }
         // volume all'ora: media delle 20 candele precedenti alla stessa ora (stessa fascia di 15 minuti)
         {
            int slot = (int)((q.t[i] % 86400) / SEC); double s = 0; int c = 0;
            for(int k = j - 1; k >= 0 && c < 20; k--) if((q.t[idx[k]] % 86400) / SEC == slot) { s += cv[idx[k]]; c++; }
            if(c == 20) { double r = cv[i] / (s / 20); double e = std::fabs(q.rv[i] - r) / r; maxErr[6] = std::max(maxErr[6], e); nchk[6]++; }
            else if(!std::isnan(q.rv[i])) { printf("RVOL definito troppo presto\n"); bad++; }
         }
         // VWAP ancorato al giorno: prezzo tipico per volume dei minuti dall'inizio del giorno alla fine della candela
         {
            long dayStart = (long)(q.t[i] / 86400) * 86400; double sw = 0, sp = 0, sp2 = 0; int cnt = 0, e0 = 0;
            for(int k = 0; k < n; k++) if(T[k] >= dayStart && T[k] < q.t[i] + SEC) { double tp = (H[k] + L[k] + C[k]) / 3; sw += V[k]; sp += V[k] * tp; sp2 += V[k] * tp * tp; cnt++; }
            (void)e0;
            if(cnt >= 15)
              {
               double vw = sp / sw, var = sp2 / sw - vw * vw;
               double e = std::fabs(q.vw[i] - vw) / vw; maxErr[7] = std::max(maxErr[7], e);
               double e2 = std::fabs(q.vs[i] - std::sqrt(std::max(0.0, var))) / std::sqrt(std::max(1e-30, var)); maxErr[8] = std::max(maxErr[8], e2); nchk[7]++;
              }
         }
        }
      const char *nm[9] = {"ATR14 (incl.)", "ATR14 (prima)", "ATR14/ATR100", "ADX", "z-score (codici)", "20 candele (flag e posizione)", "RVOL", "VWAP", "sigma VWAP"};
      for(int k = 0; k < 9; k++) printf("  %-30s controlli %6d, errore massimo %.3e\n", nm[k], nchk[k < 8 ? k : 7], maxErr[k]);
      printf("differenze totali %d\n", bad);
   }
   // 3) esiti della classe 'tutte le candele' contro il calcolo a forza bruta
   {
      CxAlloc();
      for(int ti = 0; ti < CX_NTF; ti++) g_cxSkip[ti] = 0;
      CxBuild(b, 0, 60, 86400, g_cxLvD); CxBuild(b, 0, 60, 604800, g_cxLvW); CxBuild(b, 0, 60, 2592000, g_cxLvM);
      CxBuild(b, 0, 60, 14400, g_cxLvQ); CxBuild(b, 0, 60, 3600, g_cxLvH);
      int ti = 8;   // M15
      // la soglia e la classe ALL non dipendono da 60 candele minime: forzo l'esecuzione diretta delle parti
      CCx q2; CxBuild(b, 0, 60, SEC, q2); CxFeatures(q2, true);
      double thr = CxThreshold(q2);
      datetime tMid = q2.t[q2.n / 2];
      CClu cl, ck;
      CxPass(q2, ti, thr, tMid, cl, ck);
      CxExtract(ti, cl, ck);
      int bA = (ti * CX_NCL + CX_C_ALL) * CX_NF;
      double N = 0, up1 = 0, r1 = 0, rng1 = 0, bh = 0, bl = 0, r3 = 0, up3 = 0, mfe = 0, mae = 0, race = 0, amp = 0;
      auto clip = [](double x, double lo, double hi) { return x < lo ? lo : (x > hi ? hi : x); };
      for(int i = 0; i + 3 < q2.n; i++)
        {
         if(!q2.ok[i] || std::isnan(q2.amp[i]) || std::isnan(q2.ap[i]) || !(q2.ap[i] > 0) || q2.chn[i + 3] < 4 || !(q2.ac[i] > 0)) continue;
         double ac = q2.ac[i], c = q2.c[i];
         N++;
         up1 += q2.c[i + 1] > c ? 1.0 : (q2.c[i + 1] == c ? 0.5 : 0.0);
         r1 += clip((q2.c[i + 1] - c) / ac, -8, 8);
         rng1 += clip((q2.h[i + 1] - q2.l[i + 1]) * q2.fa[i + 1] / ac, 0, 12);
         bh += q2.h[i + 1] > q2.h[i] ? 1 : 0; bl += q2.l[i + 1] < q2.l[i] ? 1 : 0;
         r3 += clip((q2.c[i + 3] - c) / ac, -8, 8);
         up3 += q2.c[i + 3] > c ? 1.0 : (q2.c[i + 3] == c ? 0.5 : 0.0);
         double mx = std::max(q2.h[i + 1], std::max(q2.h[i + 2], q2.h[i + 3])), mn = std::min(q2.l[i + 1], std::min(q2.l[i + 2], q2.l[i + 3]));
         mfe += clip((mx - c) / ac, 0, 12); mae += clip((c - mn) / ac, 0, 12);
         double rc = 0;
         for(int j = i + 1; j <= i + 12 && j < q2.n; j++)
           {
            if(q2.chn[j] < j - i + 1) break;
            bool hu = q2.h[j] - c >= ac, hd = c - q2.l[j] >= ac;
            if(hu && hd) break; if(hu) { rc = 1; break; } if(hd) { rc = -1; break; }
           }
         race += rc; amp += clip(q2.amp[i], 0, 12);
        }
      printf("esiti ALL M15: N %g (modulo %g)\n", N, g_cxC[bA]);
      const char *nm[11] = {"su dopo 1", "rend 1", "range dopo", "rompe max", "rompe min", "rend 3", "su dopo 3", "escursione su", "escursione giu", "corsa", "ampiezza"};
      double ref[11] = {up1 / N, r1 / N, rng1 / N, bh / N, bl / N, r3 / N, up3 / N, mfe / N, mae / N, race / N, amp / N};
      int fld[11] = {1, 4, 7, 8, 9, 10, 11, 12, 13, 14, 15};
      double worst = 0;
      for(int k = 0; k < 11; k++) { double e = std::fabs(g_cxC[bA + fld[k]] - ref[k]); worst = std::max(worst, e); printf("  %-16s modulo %.6f, forza bruta %.6f\n", nm[k], g_cxC[bA + fld[k]], ref[k]); }
      printf("errore massimo sugli esiti %.3e, differenza N %g\n", worst, g_cxC[bA] - N);
   }
   return 0;
  }
