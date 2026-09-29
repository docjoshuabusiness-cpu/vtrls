//+------------------------------------------------------------------+
//| MarketProfilerDash.mqh - modulo aggiunto a MarketProfiler.mq5     |
//| Scheda 'Cruscotto': sezioni scelte da menu a tendina, grafici,    |
//| riassunti in poche parole e file compatto da copiare in chat.     |
//| Usa i dati dei moduli Edge e Candele (vanno inseriti prima).      |
//+------------------------------------------------------------------+
string DashCss(void);   // fogli di stile e programma del cruscotto: funzioni generate da dash/build_dash_mqh.py
string DashJs(void);

// 0 nessun segno, 1 solo controllo dei falsi positivi (FDR), 2 robusto (FDR e stesso verso nelle due meta')
string DbMk(const int id)
  {
   if(id < 0 || id >= g_cxNT)
      return "0";
   if(g_cxTfd[id] && g_cxTst[id])
      return "2";
   return g_cxTfd[id] ? "1" : "0";
  }

// riga di profilo di una categoria di tempo: [etichetta, casi, %rialziste, rendimento ATR, range pb, %grandi, %impulsi, z x5, segni x5]
string DbRowK(const int ti, const int u, const string lab)
  {
   int b = (ti * CX_NCU + u) * CX_NFK;
   string r = "[" + EdJq(lab) + "," + EdJn(g_cxK[b], 0) + "," + EdJn(g_cxK[b + 1] * 100.0, 2) + "," + EdJn(g_cxK[b + 2], 4) + "," + EdJn(g_cxK[b + 3], 3) + "," +
              EdJn(g_cxK[b + 4] * 100.0, 2) + "," + EdJn(g_cxK[b + 5] * 100.0, 3);
   for(int m = 0; m < CX_NMK; m++)
      r += "," + EdJn(g_cxK[b + 6 + m], 1);
   for(int m = 0; m < CX_NMK; m++)
      r += "," + DbMk(CxIdx(g_cxK[b + 11 + m]));
   return r + "]";
  }

// profili: ora, minuto, giorno, settimana del mese, mese, trimestre, anno
string DbProf(const int ti)
  {
   string dk[7] = {"hour", "min", "dow", "wom", "mon", "qtr", "yr"};
   int bA = (ti * CX_NCU + CX_K_ALL) * CX_NFK;
   string all = "[" + EdJn(g_cxK[bA], 0) + "," + EdJn(g_cxK[bA + 1] * 100.0, 2) + "," + EdJn(g_cxK[bA + 2], 4) + "," + EdJn(g_cxK[bA + 3], 3) + "," +
                EdJn(g_cxK[bA + 4] * 100.0, 2) + "," + EdJn(g_cxK[bA + 5] * 100.0, 3) + "]";
   string r = "{";
   string sep = "";
   for(int d = 0; d < 7; d++)
     {
      int cnt = CxDimN(ti, d);
      if(cnt <= 0)
         continue;
      int u0 = CxDimBase(d), nr = 0;
      string rows = "";
      for(int k = 0; k < cnt; k++)
        {
         int u = u0 + k;
         double nn = g_cxK[(ti * CX_NCU + u) * CX_NFK];
         if(!MathIsValidNumber(nn) || nn <= 0)
            continue;
         rows += (nr > 0 ? "," : "") + DbRowK(ti, u, CxKLabel(ti, u));
         nr++;
        }
      if(nr == 0)
         continue;
      r += sep + "\"" + dk[d] + "\":{\"all\":" + all + ",\"r\":[" + rows + "]}";
      sep = ",";
     }
   return r + "}";
  }

// riga di classe: [etichetta, casi, %candele, %sale dopo, rendimento 1, rendimento 3, z sale, z r1, z r3, segni x3, range dopo, %rompe max, %rompe min, ampiezza, corsa]
string DbRowC(const int ti, const int u)
  {
   int b = (ti * CX_NCL + u) * CX_NF;
   return "[" + EdJq(CxLabel(u)) + "," + EdJn(g_cxC[b], 0) + "," + EdJn(g_cxC[b + 16] * 100.0, 2) + "," + EdJn(g_cxC[b + 1] * 100.0, 2) + "," + EdJn(g_cxC[b + 4], 4) + "," +
          EdJn(g_cxC[b + 10], 4) + "," + EdJn(g_cxC[b + 2], 1) + "," + EdJn(g_cxC[b + 5], 1) + "," + EdJn(g_cxC[b + 17], 1) + "," + DbMk(CxIdx(g_cxC[b + 3])) + "," +
          DbMk(CxIdx(g_cxC[b + 6])) + "," + DbMk(CxIdx(g_cxC[b + 18])) + "," + EdJn(g_cxC[b + 7], 3) + "," + EdJn(g_cxC[b + 8] * 100.0, 1) + "," +
          EdJn(g_cxC[b + 9] * 100.0, 1) + "," + EdJn(g_cxC[b + 15], 2) + "," + EdJn(g_cxC[b + 14], 3) + "]";
  }

void DbGroup(string &o, const string name, const int ti, const int u0, const int cnt, const double minN)
  {
   string rows = "";
   int nr = 0;
   for(int k = 0; k < cnt; k++)
     {
      double nn = g_cxC[(ti * CX_NCL + u0 + k) * CX_NF];
      if(!MathIsValidNumber(nn) || nn < minN)
         continue;
      rows += (nr > 0 ? "," : "") + DbRowC(ti, u0 + k);
      nr++;
     }
   if(nr == 0)
      return;
   o += (o != "" ? "," : "") + EdJq(name) + ":[" + rows + "]";
  }

// classi di candele: gruppi come nella scheda Candele; coppie e terne solo le piu' lontane dal caso (almeno 100 casi)
string DbCls(const int ti)
  {
   string o = "";
   DbGroup(o, "Forme di candela", ti, CX_C_SH, 20, 30);
   DbGroup(o, "Pattern con nome", ti, CX_C_NP, CX_NNP, 30);
   DbGroup(o, "Serie nella stessa direzione", ti, CX_C_ST, 12, 30);
   DbGroup(o, "Posizione rispetto alla candela precedente", ti, CX_C_SV, CX_NSV, 30);
   double sc[];
   int idx[];
   int m = 0;
   ArrayResize(sc, CX_C_NP - CX_C_S2);
   ArrayResize(idx, CX_C_NP - CX_C_S2);
   for(int u = CX_C_S2; u < CX_C_NP; u++)
     {
      int b = (ti * CX_NCL + u) * CX_NF;
      if(!MathIsValidNumber(g_cxC[b]) || g_cxC[b] < 100)
         continue;
      double z = 0;
      if(MathIsValidNumber(g_cxC[b + 2]))
         z = MathMax(z, MathAbs(g_cxC[b + 2]));
      if(MathIsValidNumber(g_cxC[b + 5]))
         z = MathMax(z, MathAbs(g_cxC[b + 5]));
      if(MathIsValidNumber(g_cxC[b + 17]))
         z = MathMax(z, MathAbs(g_cxC[b + 17]));
      sc[m] = z;
      idx[m] = u;
      m++;
     }
   if(m > 0)
     {
      int ord[];
      EdOrder(sc, m, ord);
      string rows = "";
      int nr = 0;
      for(int k = 0; k < m && k < 40; k++)
        {
         if(sc[ord[k]] < 2.0)
            break;
         rows += (nr > 0 ? "," : "") + DbRowC(ti, idx[ord[k]]);
         nr++;
        }
      if(nr > 0)
         o += (o != "" ? "," : "") + EdJq("Coppie e terne di candele") + ":[" + rows + "]";
     }
   string gn[13] = {"ADX", "Prezzo rispetto al VWAP", "Z-score del prezzo (20 candele)", "Volume all'ora", "Volatilita' (ATR14 / ATR100)", "Ampiezza della candela",
                    "Posizione nelle ultime 20 candele", "Rispetto al giorno prima", "Rispetto alla settimana prima", "Rispetto al mese prima",
                    "Rispetto all'ora prima (H1)", "Rispetto alle 4 ore prima (H4)", "Impulsi"};
   int gu[13] = {CX_C_AD, CX_C_VW, CX_C_ZS, CX_C_RV, CX_C_VO, CX_C_SZ, CX_C_DN, CX_C_PD, CX_C_PW, CX_C_PM, CX_C_PH, CX_C_P4, CX_C_IU};
   int gc[13] = {4, 5, 5, 4, 3, 5, 5, 3, 3, 3, 3, 3, 2};
   for(int g = 0; g < 13; g++)
      DbGroup(o, gn[g], ti, gu[g], gc[g], 30);
   int bA = (ti * CX_NCL + CX_C_ALL) * CX_NF;
   o += (o != "" ? "," : "") + "\"__all\":[" + EdJq("Tutte le candele") + "," + EdJn(g_cxC[bA], 0) + ",100," + EdJn(g_cxC[bA + 1] * 100.0, 2) + "," + EdJn(g_cxC[bA + 4], 4) + "," +
        EdJn(g_cxC[bA + 10], 4) + "]";
   return "{" + o + "}";
  }

// gli eventi piu' frequenti: [evento, gruppo, casi, % delle candele, al giorno (o all'anno)]
string DbFreq(const int ti, string &fu)
  {
   int cid[], m = 0;
   double fr[];
   int tot = 20 + CX_NNP + 12 + CX_NSV;
   ArrayResize(cid, tot);
   ArrayResize(fr, tot);
   int g0[4] = {CX_C_SH, CX_C_NP, CX_C_ST, CX_C_SV}, gn[4] = {20, CX_NNP, 12, CX_NSV};
   for(int g = 0; g < 4; g++)
      for(int k = 0; k < gn[g]; k++)
        {
         int u = g0[g] + k, b = (ti * CX_NCL + u) * CX_NF;
         if(!MathIsValidNumber(g_cxC[b]) || g_cxC[b] < 30)
            continue;
         cid[m] = u;
         fr[m] = g_cxC[b];
         m++;
        }
   bool perYear = CX_SEC[ti] >= 604800;
   fu = perYear ? "anno" : "giorno di mercato";
   double days = perYear ? MathMax(1.0, ((double)g_cxT1[ti] - (double)g_cxT0[ti]) / (365.25 * 86400.0)) :
                 MathMax(1.0, ((double)g_cxT1[ti] - (double)g_cxT0[ti]) / 86400.0 * 5.0 / 7.0);
   string r = "[";
   if(m > 0)
     {
      int ord[];
      EdOrder(fr, m, ord);
      for(int k = 0; k < m && k < 15; k++)
        {
         int u = cid[ord[k]], b = (ti * CX_NCL + u) * CX_NF;
         r += (k > 0 ? "," : "") + "[" + EdJq(CxLabel(u)) + "," + EdJq(CxGroup(u)) + "," + EdJn(g_cxC[b], 0) + "," + EdJn(g_cxC[b + 16] * 100.0, 3) + "," +
              EdJn(g_cxC[b] / days, 3) + "]";
        }
     }
   return r + "]";
  }

// cosa c'e' prima di un impulso: [stato, gruppo, osservati, attesi, z, segno]
string DbPre(const int ti)
  {
   string o = "";
   for(int d = 0; d < 2; d++)
     {
      int nd = g_cxNimpD[ti * 2 + d];
      if(nd < 30)
         continue;
      string rows = "";
      int nr = 0;
      for(int g = 0; g < CX_NSD; g++)
         for(int s = 0; s < CX_PSN[g]; s++)
           {
            int st = CX_PSG[g] + s, b = ((ti * 2 + d) * CX_NPS + st) * 4;
            if(!MathIsValidNumber(g_cxP[b]))
               continue;
            rows += (nr > 0 ? "," : "") + "[" + EdJq(CX_PSL[st]) + "," + I2S(g) + "," + EdJn(g_cxP[b], 0) + "," + EdJn(g_cxP[b + 1], 2) + "," + EdJn(g_cxP[b + 2], 1) + "," +
                    DbMk(CxIdx(g_cxP[b + 3])) + "]";
            nr++;
           }
      o += (o != "" ? "," : "") + (d == 0 ? "\"up\"" : "\"dn\"") + ":{\"n\":" + I2S(nd) + ",\"r\":[" + rows + "]}";
     }
   return "{" + o + "}";
  }

// i 5 movimenti maggiori: [quando, 1 rialzista / 0 ribassista, range % del prezzo, range in ATR]
string DbTop(const int ti)
  {
   string r = "[";
   int nr = 0;
   for(int k = 0; k < 5; k++)
     {
      int i = ti * 5 + k;
      if(!MathIsValidNumber(g_cxTopP[i]) || g_cxTopP[i] < 0)
         continue;
      r += (nr > 0 ? "," : "") + "[" + EdJq(TimeToString(g_cxTopT[i], TIME_DATE | TIME_MINUTES)) + "," + (g_cxTopD[i] > 0 ? "1" : "0") + "," + EdJn(g_cxTopP[i], 3) + "," +
           EdJn(g_cxTopR[i], 1) + "]";
      nr++;
     }
   return r + "]";
  }

// confronti robusti di un timeframe, per |z|: [testo, z, famiglia]
string DbRob(const int ti, const int cap)
  {
   int ids[];
   double zz[];
   int m = 0;
   ArrayResize(ids, MathMax(1, g_cxNT));
   ArrayResize(zz, MathMax(1, g_cxNT));
   for(int i = 0; i < g_cxNT; i++)
      if(g_cxTtf[i] == ti && g_cxTfd[i] && g_cxTst[i])
        {
         ids[m] = i;
         zz[m] = MathAbs(g_cxTz[i]);
         m++;
        }
   string r = "[";
   if(m > 0)
     {
      int ord[];
      EdOrder(zz, m, ord);
      for(int k = 0; k < m && k < cap; k++)
        {
         int id = ids[ord[k]];
         r += (k > 0 ? "," : "") + "[" + EdJq(g_cxTtx[id]) + "," + EdJn(g_cxTz[id], 1) + "," + I2S(CxFamily(g_cxTk[id], g_cxTu[id])) + "]";
        }
     }
   return r + "]";
  }

// composizione delle candele per forma (Doji, Pin, Trottola, Corpo medio, Corpo lungo, Marubozu, in %) e ampiezza media: tutte, impulsi rialzisti, impulsi ribassisti
string DbComp(const int ti)
  {
   string r = "[";
   for(int g = 0; g < 3; g++)
     {
      double tot = 0;
      for(int k = 0; k < 6; k++)
         tot += g_cxComp[(ti * 3 + g) * 8 + k];
      r += (g > 0 ? "," : "") + "[";
      for(int k = 0; k < 6; k++)
         r += EdJn(tot > 0 ? g_cxComp[(ti * 3 + g) * 8 + k] / tot * 100.0 : Nan(), 1) + ",";
      r += EdJn(tot > 0 ? g_cxComp[(ti * 3 + g) * 8 + 7] / tot : Nan(), 2) + "]";
     }
   return r + "]";
  }

string DbTf(const int ti)
  {
   double spanY = ((double)g_cxT1[ti] - (double)g_cxT0[ti]) / (365.25 * 86400.0);
   string fu = "";
   string fq = DbFreq(ti, fu);
   return "{\"id\":" + EdJq(CX_NAME[ti]) + ",\"sec\":" + I2S(CX_SEC[ti]) + ",\"n\":" + I2S(g_cxN[ti]) + ",\"t0\":" + EdJq(TimeToString(g_cxT0[ti], TIME_DATE)) + ",\"t1\":" +
          EdJq(TimeToString(g_cxT1[ti], TIME_DATE)) + ",\"span\":" + EdJn(spanY, 1) + ",\"bull\":" + EdJn(g_cxBull[ti] * 100.0, 1) + ",\"medR\":" + EdJn(g_cxMedR[ti], 3) +
          ",\"body\":" + EdJn(g_cxBody[ti] * 100.0, 0) + ",\"thr\":" + EdJn(g_cxThr[ti], 2) + ",\"nimp\":" + I2S(g_cxNimp[ti]) + ",\"impP\":" + EdJn(g_cxImpP[ti] * 100.0, 2) +
          ",\"nrob\":" + I2S(g_cxNrob[ti]) + ",\"tst\":" + I2S(g_cxNtst[ti]) + ",\"fu\":" + EdJq(fu) + ",\"prof\":" + DbProf(ti) + ",\"freq\":" + fq + ",\"cls\":" + DbCls(ti) +
          ",\"pre\":" + DbPre(ti) + ",\"top\":" + DbTop(ti) + ",\"rob\":" + DbRob(ti, 25) + ",\"comp\":" + DbComp(ti) + "}";
  }

string DbJson(const string sym)
  {
   string refj = "null";
   if(g_ref >= 0)
      refj = "{\"a\":" + I2S(g_refOffA) + ",\"b\":" + I2S(g_refOffB) + ",\"s\":" + EdJq(MKT_SHORT[g_ref]) + "}";
   string pg = "[";
   for(int g = 0; g < CX_NSD; g++)
      pg += (g > 0 ? "," : "") + EdJq(CX_PGN[g]);
   pg += "]";
   string tfs = "[", skip = "{";
   int nt = 0, ns = 0;
   for(int ti = 0; ti < CX_NTF; ti++)
     {
      if(g_cxN[ti] > 0)
        {
         tfs += (nt > 0 ? "," : "") + DbTf(ti);
         nt++;
        }
      else
        {
         skip += (ns > 0 ? "," : "") + EdJq(CX_NAME[ti]) + ":" + I2S(g_cxSkip[ti]);
         ns++;
        }
     }
   tfs += "]";
   skip += "}";
   int nr[3], nq[3];
   ArrayInitialize(nr, 0);
   ArrayInitialize(nq, 0);
   for(int i = 0; i < g_cxNT; i++)
     {
      int k = g_cxTk[i], ty = (k == 0 || k == 1 || k == 2 || k == 3 || k == 8) ? 0 : (k == 6 ? 2 : 1);
      nq[ty]++;
      if(g_cxTfd[i] && g_cxTst[i])
         nr[ty]++;
     }
   return "{\"v\":1,\"app\":\"MarketProfiler-cruscotto\",\"sym\":" + EdJq(sym) + ",\"gen\":" + EdJq(TimeToString(TimeLocal(), TIME_DATE | TIME_MINUTES)) + ",\"tz\":" + EdJq(TZName()) +
          ",\"roll\":" + EdJq(InpRollSkip ? "escluso" : "incluso") + ",\"ref\":" + refj + ",\"pg\":" + pg + ",\"cxr\":{\"all\":" + I2S((long)g_cxNAll) + ",\"r\":[" +
          I2S(nr[0]) + "," + I2S(nr[1]) + "," + I2S(nr[2]) + "],\"t\":[" + I2S(nq[0]) + "," + I2S(nq[1]) + "," + I2S(nq[2]) + "]},\"skip\":" + skip + ",\"tfs\":" + tfs +
          ",\"edge\":" + (g_edJson != "" ? g_edJson : "null") + "}";
  }

// scheda Cruscotto: pagina del cruscotto con i dati incorporati
void DashTab(const string sym)
  {
   bool any = false;
   for(int ti = 0; ti < CX_NTF; ti++)
      if(g_cxN[ti] > 0)
         any = true;
   if(!InpCand || g_cxNAll <= 0 || !any)
     {
      SecStart("Cruscotto", "");
      W("<p class='muted'>Il cruscotto usa i dati della scheda Candele: attiva il parametro 'Candele' e servono dati M1 o M5.</p>");
      SecEnd();
      return;
     }
   Comment("MarketProfiler ", sym, ": cruscotto ...");
   W("<style>" + DashCss() + "</style>");
   W("<div class='cxd' id='cxd'><p class='st'>Caricamento del cruscotto...</p></div>");
   W("<script type='application/json' id='cxd-data'>" + DbJson(sym) + "</" + "script>");
   W("<script>" + DashJs() + "</" + "script>");
   Comment("");
  }
