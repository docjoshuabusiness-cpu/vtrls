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

//--- generato da dash/build_dash_mqh.py da dash.css e dash.js: non modificare a mano
string DashCss(void)
  {
   string s = "";
   s += ".cxd{color:var(--c-fg,#e5e7eb);font:14px/1.5 system-ui,-apple-system,\"Segoe UI\",Roboto,sans-serif;position:relative;min-width:0}\n.cxd *{box-sizing:border-box}\n.cxd h3{font-size:15px;margin:0 0 4px;font-weight:600}\n.cxd .cmuted{color:var(--c-mut,#9ca3af)}\n.cxd .bar{display:flex;flex-wrap:wrap;gap:10px 14px;align-items:flex-end;padding:0 0 12px;border-bottom:1px solid var(--c-line,#1f2937);margin-bottom:14px}\n.cxd .fld{display:flex;flex-direction:column;gap:3px;min-width:0}\n.cxd .fld>span{font-size:11px;letter-spacing:.04em;text-transform:uppercase;color:var(--c-mut,#9ca3af)}\n.cxd select,.cxd input[type=text],.cxd textarea{font:inherit;color:var(--c-fg,#e5e7eb);background:var(--c-card,#111827);border:1px solid var(--c-axis,#374151);border-radius:8px;padding:7px 10px;min-width:0;max-width:100%}\n.cxd select:focus-visible,.cxd button:focus-visible,.cxd textarea:focus-visible,.cxd [tabindex]:focus-visible{outline:2px solid var(--c-s1,#3987e5);outline-offset:2px}\n.cxd button{font:inherit;font-weight:600;color:var(--c-fg,#e5e7eb);background:var(--c-card,#111827);border:1px solid var(--c-axis,#374151);border-radius:8px;padding:7px 12px;cursor:pointer}\n.cxd button.main{background:var(--c-s1,#3987e5);border-color:var(--c-s1,#3987e5);color:var(--c-on-s1,#08121f)}\n.cxd button.seg{border-radius:0;padding:5px 11px;font-weight:500}\n.cxd button.seg:first-child{border-radius:8px 0 ";
   s += "0 8px}\n.cxd button.seg:last-child{border-radius:0 8px 8px 0;border-left:0}\n.cxd button.seg.on{background:var(--c-s1,#3987e5);border-color:var(--c-s1,#3987e5);color:var(--c-on-s1,#08121f)}\n.cxd .say{background:var(--c-card,#111827);border:1px solid var(--c-line,#1f2937);border-radius:10px;padding:12px 14px;margin:0 0 14px}\n.cxd .say ul{margin:6px 0 0;padding-left:18px;display:flex;flex-direction:column;gap:3px;max-width:88ch}\n.cxd .say b{font-weight:600}\n.cxd .ckpis{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px;margin:0 0 14px}\n.cxd .ckpi{border:1px solid var(--c-line,#1f2937);border-radius:10px;padding:9px 12px;background:var(--c-card,#111827);min-width:0}\n.cxd .ckpi span{display:block;font-size:12px;color:var(--c-mut,#9ca3af)}\n.cxd .ckpi b{display:block;font-size:20px;font-weight:600;line-height:1.25}\n.cxd .ckpi small{display:block;font-size:11px;color:var(--c-mut,#9ca3af)}\n.cxd .grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr));gap:14px}\n.cxd figure{margin:0;border:1px solid var(--c-line,#1f2937);border-radius:10px;padding:12px 14px;background:var(--c-card,#111827);min-width:0}\n.cxd figcaption{display:flex;flex-wrap:wrap;justify-content:space-between;gap:6px 12px;align-items:flex-start;margin-bottom:8px}\n.cxd figcaption .t{font-weight:600}\n.cxd figcaption .s{font-size:12px;color:var(--c-mut,#";
   s += "9ca3af);flex-basis:100%;order:3}\n.cxd .segs{display:inline-flex}\n.cxd .plot{overflow-x:auto;min-width:0}\n.cxd svg{display:block}\n.cxd svg text{fill:var(--c-mut,#9ca3af);font-size:11px;font-family:inherit}\n.cxd svg text.v{fill:var(--c-fg,#e5e7eb);font-weight:600}\n.cxd .chb{display:flex;flex-direction:column;gap:6px}\n.cxd .hbr{display:grid;grid-template-columns:minmax(110px,38%) minmax(0,1fr) auto;gap:4px 10px;align-items:center}\n.cxd .hbr.g{grid-template-columns:1fr;margin-top:8px;font-size:11px;letter-spacing:.04em;text-transform:uppercase;color:var(--c-mut,#9ca3af)}\n.cxd .hbr .l{min-width:0;overflow-wrap:anywhere;line-height:1.3}\n.cxd .hbr .l small{display:block;color:var(--c-mut,#9ca3af);font-size:11px}\n.cxd .hbr .v{font-variant-numeric:tabular-nums;text-align:right;white-space:nowrap;font-size:12.5px}\n.cxd .hbr .tr{position:relative;height:14px;min-width:0;background:transparent}\n.cxd .hbr .tr i{position:absolute;top:1px;bottom:1px;border-radius:0 4px 4px 0;background:var(--c-s1,#3987e5)}\n.cxd .hbr .tr i.dim{background:var(--c-s1-dim,#274a75)}\n.cxd .hbr .tr i.neg{background:var(--c-neg,#e66767);border-radius:4px 0 0 4px}\n.cxd .hbr .tr i.negdim{background:var(--c-neg-dim,#6b3a3a);border-radius:4px 0 0 4px}\n.cxd .hbr .tr u{position:absolute;top:-1px;bottom:-1px;width:2px;background:var(--c-fg,#e5e7eb);text-decoration:none;border-radius:1px}\n.cxd .hbr .tr b.mi";
   s += "d{position:absolute;top:-2px;bottom:-2px;left:50%;width:1px;background:var(--c-axis,#374151)}\n.cxd .hbr:hover .l{color:var(--c-fg,#e5e7eb)}\n.cxd table{border-collapse:collapse;width:100%;font-size:12.5px;font-variant-numeric:tabular-nums}\n.cxd th,.cxd td{padding:5px 8px;border-bottom:1px solid var(--c-line,#1f2937);text-align:right;white-space:nowrap}\n.cxd th:first-child,.cxd td:first-child{text-align:left;white-space:normal;min-width:130px}\n.cxd th{color:var(--c-mut,#9ca3af);font-weight:600}\n.cxd td.tl,.cxd th.tl{text-align:left}.cxd td.tl{white-space:normal}\n.cxd .ctw{overflow-x:auto}\n.cxd .pos{color:var(--c-pos-t,#8ab4f8)}\n.cxd .negt{color:var(--c-neg-t,#f28b82)}\n.cxd .chip{display:inline-flex;gap:6px;align-items:center;border:1px solid var(--c-axis,#374151);border-radius:999px;padding:2px 10px;font-size:12px}\n.cxd .box{border-left:4px solid var(--c-axis,#374151);background:var(--c-card,#111827);border-radius:0 10px 10px 0;padding:10px 14px;margin:0 0 12px}\n.cxd .box.good{border-color:var(--c-good,#0ca30c)}\n.cxd .box.info{border-color:var(--c-s1,#3987e5)}\n.cxd .box.warn{border-color:var(--c-warn,#fab219)}\n.cxd .box.bad{border-color:var(--c-crit,#d03b3b)}\n.cxd .hm{border-collapse:separate;border-spacing:2px;width:100%;min-width:560px;table-layout:fixed;font-size:11px}\n.cxd .hm th{padding:2px 3px;text-align:center;font-weight:500}\n.cxd .hm th:first-child,.cxd";
   s += " .hm td:first-child{width:44px;min-width:0;text-align:left;padding-right:8px;position:sticky;left:0;background:var(--c-card,#111827)}\n.cxd .hm td{height:22px;padding:0;border:0;border-radius:3px;background:var(--c-heat0,#1c2230)}\n.cxd .lgd{display:flex;align-items:center;gap:8px;font-size:12px;color:var(--c-mut,#9ca3af);margin-top:8px}\n.cxd .lgd i{display:block;width:140px;height:8px;border-radius:4px;background:linear-gradient(90deg,var(--c-heat0,#1c2230),var(--c-s1,#3987e5))}\n.cxd .lgd i.dv{background:linear-gradient(90deg,var(--c-neg,#e66767),var(--c-heat0,#1c2230),var(--c-s1,#3987e5))}\n.cxd textarea.dg{width:100%;height:200px;font:12px/1.4 ui-monospace,Consolas,monospace;white-space:pre;resize:vertical}\n.cxd .chk{display:flex;flex-wrap:wrap;gap:6px 14px}\n.cxd .chk label{display:inline-flex;gap:5px;align-items:center;font-size:13px}\n.cxd .tip{position:absolute;z-index:20;pointer-events:none;background:var(--c-tip,#0b0f17);color:var(--c-fg,#e5e7eb);border:1px solid var(--c-axis,#374151);border-radius:8px;padding:6px 9px;font-size:12px;line-height:1.35;max-width:300px;box-shadow:0 4px 14px rgba(0,0,0,.25)}\n.cxd .tip b{display:block;font-size:14px;font-weight:600}\n.cxd .tip span{display:block;color:var(--c-mut,#9ca3af)}\n.cxd .cst{font-size:13px;color:var(--c-mut,#9ca3af)}\n.cxd .cst.ok{color:var(--c-good-t,#34d399);font-weight:600}\n@media (max-width:560px){.cxd .hbr";
   s += "{grid-template-columns:minmax(0,1fr) auto}.cxd .hbr .tr{grid-column:1/-1;order:3}}\n@media (prefers-reduced-motion:no-preference){.cxd .hbr .tr i{transition:width .2s}}";
   return s;
  }

string DashJs(void)
  {
   string s = "";
   s += "/* Cruscotto candele: legge i dati JSON (#cxd-data) e mostra sezioni scelte da menu a tendina, con grafici SVG/HTML e una tabella gemella.\nServe anche a preparare il file compatto da incollare in chat (sezione \"File per l'analisi\"). Nessuna libreria esterna. */\n(function () {\n'use strict';\nvar root = document.getElementById('cxd');\nif (!root) return;\nvar DATA = null, ST = {}, TIP = null, LASTW = 0;\nvar TFORD = ['M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M10', 'M12', 'M15', 'M20', 'M30', 'H1', 'H2', 'H3', 'H4', 'H6', 'H8', 'H12', 'D1', 'W1', 'MN1'];\nvar DIMS = [['hour', 'Ora del giorno'], ['min', \"Minuto dell'ora\"], ['dow', 'Giorno della settimana'], ['wom', 'Settimana del mese'], ['mon', 'Mese'], ['qtr', 'Trimestre'], ['yr', 'Anno']];\nvar METS = [\n{ k: 'rng', i: 4, z: 9, m: 14, n: 'Range medio (punti base)', u: ' pb', d: 2, kind: 'mag', all: 3 },\n{ k: 'imp', i: 6, z: 11, m: 16, n: '% di impulsi', u: '%', d: 2, kind: 'mag', all: 5 },\n{ k: 'big', i: 5, z: 10, m: 15, n: '% di candele oltre 1,5 ATR', u: '%', d: 1, kind: 'mag', all: 4 },\n{ k: 'bull', i: 2, z: 7, m: 12, n: '% di candele rialziste', u: '%', d: 1, kind: 'pol', all: 1 },\n{ k: 'ret', i: 3, z: 8, m: 13, n: 'Rendimento medio (ATR)', u: ' ATR', d: 3, kind: 'pol', all: 2 }\n];\nvar SECS = [\n['sintesi', 'Sintesi del timeframe'], ['quando', 'Quando si muove (ora, giorno, mese...)'], ['eventi', 'Eventi pi\\u00f9 fr";
   s += "equenti'],\n['pattern', 'Pattern, forme e stati'], ['pre', 'Cosa c\\u2019\\u00e8 prima di un impulso'], ['rob', 'Confronti robusti'],\n['conf', 'Confronto tra timeframe'], ['edge', 'Edge e strategie'], ['file', 'File per l\\u2019analisi (da copiare in chat)']\n];\nvar MK = ['', '\\u00a7', '\\u2020'];\nfunction h(tag, cls, kids, attrs) {\nvar e = document.createElement(tag);\nif (cls) e.className = cls;\nif (attrs) for (var k in attrs) e.setAttribute(k, attrs[k]);\nadd(e, kids);\nreturn e;\n}\nfunction add(e, kids) {\nif (kids == null) return;\nif (!Array.isArray(kids)) kids = [kids];\nkids.forEach(function (c) { if (c == null || c === false) return; e.appendChild(typeof c === 'object' ? c : document.createTextNode(String(c))); });\n}\nfunction svg(tag, attrs, kids) {\nvar e = document.createElementNS('http://www.w3.org/2000/svg', tag);\nif (attrs) for (var k in attrs) e.setAttribute(k, attrs[k]);\nif (kids) add(e, kids);\nreturn e;\n}\nfunction ent(s) { if (s == null) return ''; var t = document.createElement('textarea'); t.innerHTML = String(s); return t.value; }\nfunction nf(x, d) {\nif (x == null || !isFinite(x)) return '\\u2013';\nreturn Number(x).toLocaleString('it-IT', { minimumFractionDigits: d, maximumFractionDigits: d });\n}\nfunction sg(x, d) { if (x == null || !isFinite(x)) return '\\u2013'; return (x >= 0 ? '+' : '') + nf(x, d); }\nfunction zt(z, mk) { return z == n";
   s += "ull ? '' : 'z ' + sg(z, 1) + (mk ? ' ' + MK[mk] : ''); }\nfunction byId(id) { for (var i = 0; i < DATA.tfs.length; i++) if (DATA.tfs[i].id === id) return DATA.tfs[i]; return null; }\nfunction cur() { return byId(ST.tf) || DATA.tfs[0]; }\nfunction hlab(l) {\nvar m = /^(\\d\\d)h$/.exec(l);\nif (!m || !DATA.ref) return l;\nvar hh = +m[1], a = (hh + DATA.ref.a + 24) % 24, b = (hh + DATA.ref.b + 24) % 24;\nreturn l + ' (' + DATA.ref.s + ' ' + ('0' + a).slice(-2) + 'h' + (a !== b ? '/' + ('0' + b).slice(-2) + 'h' : '') + ')';\n}\nfunction nice(min, max, cnt) {\nif (max === min) { max = min + 1; }\nvar span = max - min, step = Math.pow(10, Math.floor(Math.log10(span / cnt))), err = span / cnt / step;\nstep *= err >= 7 ? 10 : err >= 3 ? 5 : err >= 1.5 ? 2 : 1;\nvar lo = Math.floor(min / step) * step, hi = Math.ceil(max / step) * step, t = [];\nfor (var v = lo; v <= hi + step * 0.001; v += step) t.push(+v.toFixed(10));\nreturn t;\n}\nfunction px(x) { return Math.round(x * 10) / 10; }\nfunction tipShow(el, ev) {\nvar raw = el.getAttribute('data-tip');\nif (!raw) return;\nif (!TIP) { TIP = h('div', 'tip'); root.appendChild(TIP); }\nwhile (TIP.firstChild) TIP.removeChild(TIP.firstChild);\nvar parts = raw.split('\\n');\nTIP.appendChild(h('b', null, parts[0]));\nparts.slice(1).forEach(function (p) { TIP.appendChild(h('span', null, p)); });\nTIP.style.display = 'block';\nvar r = root.getBound";
   s += "ingClientRect(), x = (ev ? ev.clientX : el.getBoundingClientRect().left) - r.left + 12, y = (ev ? ev.clientY : el.getBoundingClientRect().top) - r.top + 14;\nvar w = TIP.offsetWidth;\nif (x + w > root.clientWidth) x = Math.max(0, root.clientWidth - w - 4);\nTIP.style.left = px(x) + 'px';\nTIP.style.top = px(y) + 'px';\n}\nfunction tipHide() { if (TIP) TIP.style.display = 'none'; }\nroot.addEventListener('pointermove', function (ev) { var t = ev.target.closest ? ev.target.closest('[data-tip]') : null; if (t && root.contains(t)) tipShow(t, ev); else tipHide(); });\nroot.addEventListener('pointerleave', tipHide);\nroot.addEventListener('focusin', function (ev) { var t = ev.target.closest ? ev.target.closest('[data-tip]') : null; if (t) tipShow(t, null); });\nroot.addEventListener('focusout', tipHide);\nfunction select(id, label, opts, val, onchange) {\nvar s = h('select', null, null, { id: 'cxd-' + id });\nopts.forEach(function (o) {\nif (o.g) { var og = h('optgroup', null, null, { label: o.g }); o.o.forEach(function (p) { og.appendChild(h('option', null, p[1], { value: p[0] })); }); s.appendChild(og); }\nelse s.appendChild(h('option', null, o[1], { value: o[0] }));\n});\ns.value = val;\ns.addEventListener('change', function () { onchange(s.value); });\nreturn h('label', 'fld', [h('span', null, label), s]);\n}\nfunction kpi(l, v, s) { return h('div', 'ckpi', [h('span', null, l), h";
   s += "('b', null, v), s ? h('small', null, s) : null]); }\nfunction table(cols, rows, left) {\nleft = left || [];\nvar t = h('table'), th = h('thead'), tr = h('tr');\ncols.forEach(function (c, i) { tr.appendChild(h('th', left.indexOf(i) >= 0 ? 'tl' : null, c)); });\nth.appendChild(tr); t.appendChild(th);\nvar tb = h('tbody');\nrows.forEach(function (r) { var q = h('tr'); r.forEach(function (c, i) { q.appendChild(h('td', left.indexOf(i) >= 0 || (typeof c === 'string' && c.length > 40) ? 'tl' : null, c)); }); tb.appendChild(q); });\nt.appendChild(tb);\nreturn h('div', 'ctw', t);\n}\nfunction panel(title, sub, drawChart, drawTable) {\nvar body = h('div'), on = 'g';\nvar bg = h('button', 'seg on', 'Grafico', { type: 'button' }), bt = h('button', 'seg', 'Tabella', { type: 'button' });\nfunction show(w) {\non = w; bg.className = 'seg' + (w === 'g' ? ' on' : ''); bt.className = 'seg' + (w === 't' ? ' on' : '');\nwhile (body.firstChild) body.removeChild(body.firstChild);\nbody.appendChild(w === 'g' ? drawChart() : drawTable());\n}\nbg.addEventListener('click', function () { show('g'); });\nbt.addEventListener('click', function () { show('t'); });\nvar cap = h('figcaption', null, [h('span', 't', title), drawTable ? h('span', 'segs', [bg, bt]) : null, sub ? h('span', 's', sub) : null]);\nshow('g');\nreturn h('figure', null, [cap, body]);\n}\nfunction plotWidth() { var w = root.clientWidth; ret";
   s += "urn Math.max(300, (w || 720) - 30); }\nfunction halfWidth() { var w = plotWidth(); return w >= 860 ? 560 : w; }\nfunction bars(rows, o) {\nvar W = o.w || plotWidth(), H = o.h || 230, m = { l: 46, r: 10, t: 16, b: 30 };\nvar pw = W - m.l - m.r, ph = H - m.t - m.b;\nvar vs = rows.map(function (r) { return r.v; }).filter(function (v) { return v != null; });\nif (o.ref != null) vs.push(o.ref);\nvar lo = Math.min.apply(null, vs.concat([0])), hi = Math.max.apply(null, vs.concat([0]));\nvar tk = nice(lo, hi, 4); lo = tk[0]; hi = tk[tk.length - 1];\nvar y = function (v) { return m.t + ph * (1 - (v - lo) / (hi - lo)); };\nvar base = y(0);\nvar s = svg('svg', { width: W, height: H, viewBox: '0 0 ' + W + ' ' + H, role: 'img', 'aria-label': o.aria || 'Grafico', style: 'width:100%;height:auto;max-width:' + px(W * 1.3) + 'px' });\ntk.forEach(function (t) {\ns.appendChild(svg('line', { x1: m.l, x2: W - m.r, y1: px(y(t)), y2: px(y(t)), stroke: 'var(--c-line,#1f2937)', 'stroke-width': 1 }));\ns.appendChild(svg('text', { x: m.l - 6, y: px(y(t)) + 4, 'text-anchor': 'end' }, o.yf ? o.yf(t) : nf(t, 0)));\n});\ns.appendChild(svg('line', { x1: m.l, x2: W - m.r, y1: px(base), y2: px(base), stroke: 'var(--c-axis,#374151)', 'stroke-width': 1 }));\nvar n = rows.length, band = pw / n, bw = Math.min(24, band * 0.72), step = Math.max(1, Math.ceil(n * (o.lw || 26) / pw));\nvar imax = -1, imin = -1;\nrows.for";
   s += "Each(function (r, i) { if (r.v == null) return; if (imax < 0 || r.v > rows[imax].v) imax = i; if (imin < 0 || r.v < rows[imin].v) imin = i; });\nrows.forEach(function (r, i) {\nvar cx = m.l + band * (i + 0.5), x0 = cx - bw / 2;\nif (r.v != null) {\nvar yy = y(r.v), up = r.v >= 0, top = Math.min(yy, base), hgt = Math.abs(base - yy);\nvar col = r.hi === 'neg' ? 'var(--c-neg,#e66767)' : r.hi === 'negdim' ? 'var(--c-neg-dim,#6b3a3a)' : r.hi === 'dim' ? 'var(--c-s1-dim,#274a75)' : 'var(--c-s1,#3987e5)';\nif (hgt > 0.5) {\nvar rr = Math.min(4, hgt), d;\nif (up) d = 'M' + px(x0) + ',' + px(base) + 'L' + px(x0) + ',' + px(top + rr) + 'Q' + px(x0) + ',' + px(top) + ' ' + px(x0 + rr) + ',' + px(top) + 'L' + px(x0 + bw - rr) + ',' + px(top) + 'Q' + px(x0 + bw) + ',' + px(top) + ' ' + px(x0 + bw) + ',' + px(top + rr) + 'L' + px(x0 + bw) + ',' + px(base) + 'Z';\nelse d = 'M' + px(x0) + ',' + px(base) + 'L' + px(x0) + ',' + px(top + hgt - rr) + 'Q' + px(x0) + ',' + px(top + hgt) + ' ' + px(x0 + rr) + ',' + px(top + hgt) + 'L' + px(x0 + bw - rr) + ',' + px(top + hgt) + 'Q' + px(x0 + bw) + ',' + px(top + hgt) + ' ' + px(x0 + bw) + ',' + px(top + hgt - rr) + 'L' + px(x0 + bw) + ',' + px(base) + 'Z';\ns.appendChild(svg('path', { d: d, fill: col }));\n}\nif ((i === imax || i === imin) && n > 6 && (o.lab !== false)) {\nvar above = up ? top - 4 : top + hgt + 11;\ns.appendChild(svg('text', { x: px(c";
   s += "x), y: px(above), 'text-anchor': 'middle', 'class': 'v' }, (o.vf || nf)(r.v)));\n}\nif (r.mk === 2) s.appendChild(svg('text', { x: px(cx), y: px(up ? top - (i === imax || i === imin ? 16 : 4) : top + hgt + (i === imax || i === imin ? 24 : 11)), 'text-anchor': 'middle' }, '\\u2020'));\n}\nif (i % step === 0) s.appendChild(svg('text', { x: px(cx), y: H - 10, 'text-anchor': 'middle' }, r.l));\nvar hit = svg('rect', { x: px(m.l + band * i), y: m.t, width: px(band), height: ph, fill: 'transparent', tabindex: 0, 'data-tip': r.tip || '', 'aria-label': (r.l || '') + ': ' + (r.v == null ? 'n/d' : (o.vf || nf)(r.v)) });\ns.appendChild(hit);\n});\nif (o.ref != null) {\ns.appendChild(svg('line', { x1: m.l, x2: W - m.r, y1: px(y(o.ref)), y2: px(y(o.ref)), stroke: 'var(--c-fg,#e5e7eb)', 'stroke-width': 1, opacity: 0.55 }));\ns.appendChild(svg('text', { x: W - m.r, y: px(y(o.ref)) - 4, 'text-anchor': 'end' }, o.refl || 'media'));\n}\nreturn h('div', 'plot', s);\n}\nfunction hbars(rows, o) {\no = o || {};\nvar mx = 0;\nrows.forEach(function (r) { if (r.g) return; mx = Math.max(mx, Math.abs(r.v || 0), r.tick || 0); });\nif (o.max) mx = o.max;\nif (!(mx > 0)) mx = 1;\nvar box = h('div', 'chb');\nrows.forEach(function (r) {\nif (r.g) { box.appendChild(h('div', 'hbr g', r.g)); if (r.gmax !== undefined) mx = r.gmax || 1; return; }\nvar tr = h('div', 'tr');\nif (o.div) {\ntr.appendChild(h('b', 'mid'";
   s += "));\nvar w = Math.min(50, Math.abs(r.v || 0) / mx * 50);\nvar i = h('i', r.cls || (r.v >= 0 ? '' : 'neg'));\ni.style.width = px(w) + '%';\ni.style.left = r.v >= 0 ? '50%' : px(50 - w) + '%';\ntr.appendChild(i);\n} else {\nvar i2 = h('i', r.cls || '');\ni2.style.left = '0';\ni2.style.width = px(Math.min(100, Math.abs(r.v || 0) / mx * 100)) + '%';\ntr.appendChild(i2);\nif (r.tick != null) { var u = h('u'); u.style.left = 'calc(' + px(Math.min(100, r.tick / mx * 100)) + '% - 1px)'; tr.appendChild(u); }\n}\nvar row = h('div', 'hbr', [h('div', 'l', [r.l, r.sub ? h('small', null, r.sub) : null]), tr, h('div', 'v', r.txt)], { tabindex: 0, 'data-tip': r.tip || '' });\nbox.appendChild(row);\n});\nreturn box;\n}\nfunction profRows(t, dim, met) {\nvar P = t.prof && t.prof[dim];\nif (!P) return null;\nreturn P.r.filter(function (r) { return r[1] > 0; });\n}\nfunction shortLab(dim, l) { if (dim === 'hour') { var m = /^(\\d\\d)h$/.exec(l); return m ? m[1] : l; } return l; }\nfunction bestWorst(t, dim, met) {\nvar R = profRows(t, dim); if (!R || R.length < 2) return null;\nvar a = R.filter(function (r) { return r[met.i] != null; }).slice().sort(function (x, y) { return y[met.i] - x[met.i]; });\nreturn { hi: a[0], lo: a[a.length - 1], all: a };\n}\nfunction fuTxt(t) { return t.fu === 'anno' ? 'all\\u2019anno' : 'al giorno di mercato'; }\nfunction nfm(met, x) { return nf(x, met.d) + met.u; }\nf";
   s += "unction secSintesi(box, t) {\nvar k = h('div', 'ckpis', [\nkpi('Candele analizzate', nf(t.n, 0), t.t0 + ' \\u2192 ' + t.t1), kpi('Rialziste', nf(t.bull, 1) + '%', 'corpo mediano ' + nf(t.body, 0) + '% del range'),\nkpi('Range mediano', nf(t.medR, 3) + '%', 'del prezzo'), kpi('Soglia dell\\u2019impulso', nf(t.thr, 1) + ' ATR', nf(t.nimp, 0) + ' impulsi, ' + nf(t.impP, 2) + '%'),\nkpi('Confronti robusti', nf(t.nrob, 0), 'su ' + nf(t.tst, 0) + ' con |z| \\u2265 2')\n]);\nbox.appendChild(k);\nvar say = [];\nvar bw = bestWorst(t, 'hour', METS[0]);\nif (bw) say.push([h('b', null, 'Quando si muove: '), 'il range \\u00e8 massimo alle ' + hlab(bw.hi[0]) + ' (' + nf(bw.hi[4], 2) + ' pb, \\u00d7' + nf(bw.hi[4] / (t.prof.hour.all[3] || 1), 2) + ' la media) e minimo alle ' + hlab(bw.lo[0]) + ' (\\u00d7' + nf(bw.lo[4] / (t.prof.hour.all[3] || 1), 2) + ').']);\nvar bi = bestWorst(t, 'hour', METS[1]);\nif (bi && bi.hi[6] > 0) say.push([h('b', null, 'Impulsi: '), 'sono lo ' + nf(t.impP, 2) + '% delle candele; il ' + nf(bi.hi[6], 2) + '% cade alle ' + hlab(bi.hi[0]) + '.']);\nvar dw = bestWorst(t, 'dow', METS[0]);\nif (dw) say.push([h('b', null, 'Giorno: '), 'pi\\u00f9 mosso ' + dw.hi[0] + ' (' + nf(dw.hi[4], 2) + ' pb), meno mosso ' + dw.lo[0] + '.']);\nvar mw = bestWorst(t, 'mon', METS[0]);\nif (mw) say.push([h('b', null, 'Mese: '), 'pi\\u00f9 mosso ' + mw.hi[0] + ', meno mosso ' + mw.lo[0] + ";
   s += "(t.span < 3 ? ' (meno di 3 anni di dati: solo descrizione)' : '') + '.']);\nif (t.freq && t.freq.length) say.push([h('b', null, 'Evento pi\\u00f9 frequente: '), ent(t.freq[0][0]) + ' (' + nf(t.freq[0][3], 1) + '% delle candele, ' + nf(t.freq[0][4], 1) + ' ' + fuTxt(t) + ').']);\nif (t.rob && t.rob.length) say.push([h('b', null, 'Confronto pi\\u00f9 solido: '), ent(t.rob[0][0]) + ' (z ' + sg(t.rob[0][1], 1) + ').']);\nvar pu = topPre(t, 'up'), pd = topPre(t, 'dn');\nif (pu) say.push([h('b', null, 'Prima di un impulso rialzista: '), preTxt(pu) + '.']);\nif (pd) say.push([h('b', null, 'Prima di un impulso ribassista: '), preTxt(pd) + '.']);\nvar ul = h('ul');\nsay.forEach(function (s) { ul.appendChild(h('li', null, s)); });\nbox.appendChild(h('div', 'say', [h('b', null, 'In poche parole \\u2013 ' + t.id), ul]));\nvar g = h('div', 'grid2');\nif (t.prof && t.prof.hour) g.appendChild(quandoPanel(t, 'hour', METS[0], true));\nelse if (t.prof && t.prof.dow) g.appendChild(quandoPanel(t, 'dow', METS[0], true));\nif (t.freq && t.freq.length) g.appendChild(eventiPanel(t, 10, 'n', true));\nbox.appendChild(g);\nif (t.top && t.top.length) {\nbox.appendChild(h('div', 'say', [h('b', null, 'I 5 movimenti maggiori'), table(['Quando', 'Direzione', 'Range % del prezzo', 'Range in ATR'],\nt.top.map(function (r) { return [r[0], r[1] ? 'rialzista' : 'ribassista', nf(r[2], 3) + '%', nf(r[3], 1)]; }))]))";
   s += ";\n}\n}\nfunction topPre(t, d) {\nvar P = t.pre && t.pre[d]; if (!P || !P.r) return null;\nvar byz = function (x, y) { return y[4] - x[4]; };\nvar a = P.r.filter(function (r) { return r[4] != null && r[4] > 0 && r[5] === 2; }).sort(byz);\nif (a.length) return { r: a[0], lv: 2 };\na = P.r.filter(function (r) { return r[4] != null && r[4] >= 2; }).sort(byz);\nreturn a.length ? { r: a[0], lv: 1 } : null;\n}\nfunction preTxt(b) {\nreturn ent(b.r[0]) + ' (' + nf(b.r[2], 0) + ' volte contro ' + nf(b.r[3], 1) + ' attese, ' + zt(b.r[4], b.r[5]) + (b.lv === 2 ? ', robusto' : ', indizio non robusto: con molti confronti capita per caso') + ')';\n}\nfunction quandoPanel(t, dim, met, compact) {\nvar R = profRows(t, dim);\nvar all = t.prof[dim].all;\nvar refV = all[met.all];\nvar ranked = R.filter(function (r) { return r[met.i] != null; }).slice().sort(function (a, b) { return b[met.i] - a[met.i]; });\nvar top = {}; ranked.slice(0, 3).forEach(function (r) { top[r[0]] = 1; });\nvar pol = met.kind === 'pol';\nvar rows = R.map(function (r) {\nvar v = r[met.i], z = r[met.z], mk = r[met.m], hi;\nif (!pol) hi = top[r[0]] ? 'top' : 'dim';\nelse hi = z == null || Math.abs(z) < 2 ? (v >= refV ? 'dim' : 'negdim') : (v >= refV ? 'pos' : 'neg');\nvar lab = dim === 'hour' ? hlab(r[0]) : r[0];\nreturn { l: shortLab(dim, r[0]), v: pol ? v - refV : v, hi: hi, mk: mk, tip: nfm(met, v) + '\\n' + lab + ' ";
   s += "\\u00b7 ' + nf(r[1], 0) + ' candele' + (z != null ? '\\n' + zt(z, mk) : '') + '\\nMedia del timeframe ' + nfm(met, refV) };\n});\nvar dn = DIMS.filter(function (d) { return d[0] === dim; })[0][1];\nreturn panel(met.n + ' per ' + dn.toLowerCase() + (pol ? ': scostamento dalla media (' + nfm(met, refV) + ')' : ''), pol ? 'Barre = differenza dalla media del timeframe; blu sopra, rosso sotto, colore pieno se |z| \\u2265 2. \\u2020 = robusto. Il valore vero \\u00e8 nel suggerimento.' : 'Barre evidenziate: le 3 pi\\u00f9 alte. \\u2020 = robusto. Riga = media del timeframe.', function () {\nvar pd = met.k === 'ret' ? 3 : 1;\nreturn pol ? bars(rows, { w: compact ? halfWidth() : undefined, lw: 18, vf: function (v) { return sg(v, pd); }, yf: function (v) { return sg(v, pd); }, aria: met.n }) :\nbars(rows, { w: compact ? halfWidth() : undefined, lw: 18, ref: refV, refl: 'media ' + nfm(met, refV), vf: function (v) { return nf(v, met.d); }, yf: function (v) { return nf(v, met.d > 1 ? 1 : 0); }, aria: met.n });\n}, function () {\nreturn table([dn, 'Candele', met.n, 'z', 'Segno'], R.map(function (r) { return [dim === 'hour' ? hlab(r[0]) : r[0], nf(r[1], 0), nfm(met, r[met.i]), r[met.z] == null ? '\\u2013' : sg(r[met.z], 1), MK[r[met.m] || 0] || '']; }));\n});\n}\nfunction secQuando(box, t) {\nvar dims = DIMS.filter(function (d) { return t.prof && t.prof[d[0]] && t.prof[d[0]].r.length > 1; });";
   s += "\nif (!dims.length) { box.appendChild(h('p', 'cmuted', 'Questo file non contiene i profili di tempo per questo timeframe (livello del file troppo basso).')); return; }\nif (!dims.some(function (d) { return d[0] === ST.dim; })) ST.dim = dims[0][0];\nvar met = METS.filter(function (m) { return m.k === ST.met; })[0] || METS[0];\nvar top = h('div', 'bar', [\nselect('dim', 'Dimensione del tempo', dims, ST.dim, function (v) { ST.dim = v; render(); }),\nselect('met', 'Misura', METS.map(function (m) { return [m.k, m.n]; }), met.k, function (v) { ST.met = v; render(); })]);\nbox.appendChild(top);\nvar bw = bestWorst(t, ST.dim, met), dn = dims.filter(function (d) { return d[0] === ST.dim; })[0][1];\nif (bw) {\nvar refV = t.prof[ST.dim].all[met.all], nsig = bw.all.filter(function (r) { return r[met.z] != null && Math.abs(r[met.z]) >= 2; }).length, nrob = bw.all.filter(function (r) { return r[met.m] === 2; }).length;\nvar L = function (r) { return (ST.dim === 'hour' ? hlab(r[0]) : r[0]) + ' (' + nfm(met, r[met.i]) + ')'; };\nvar s = met.kind === 'mag' ?\n'Massimo: ' + L(bw.hi) + ', \\u00d7' + nf(bw.hi[met.i] / (refV || 1), 2) + ' la media del timeframe (' + nfm(met, refV) + '). Minimo: ' + L(bw.lo) + ', \\u00d7' + nf(bw.lo[met.i] / (refV || 1), 2) + '. Seconda e terza: ' + bw.all.slice(1, 3).map(L).join(', ') + '.' :\n'Pi\\u00f9 alto: ' + L(bw.hi) + '; pi\\u00f9 basso: ' + L(bw.lo) + '; me";
   s += "dia ' + nfm(met, refV) + '. ' + nsig + ' categorie su ' + bw.all.length + ' si scostano dal caso di oltre 2 z' + (nrob ? ' (' + nrob + ' robuste \\u2020)' : '') + '.';\nbox.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), s]));\n}\nbox.appendChild(quandoPanel(t, ST.dim, met, false));\n}\nfunction eventiPanel(t, n, sort, compact) {\nvar F = t.freq.slice();\nif (sort === 'day') F.sort(function (a, b) { return b[4] - a[4]; }); else F.sort(function (a, b) { return b[3] - a[3]; });\nF = F.slice(0, n);\nvar rows = F.map(function (r) { return { l: ent(r[0]), sub: r[1], v: r[3], txt: nf(r[3], 1) + '%', cls: '', tip: nf(r[3], 2) + '% delle candele\\n' + ent(r[0]) + ' \\u00b7 ' + nf(r[2], 0) + ' casi\\nUna volta ogni ' + nf(100 / r[3], 1) + ' candele \\u00b7 ' + nf(r[4], 2) + ' ' + fuTxt(t) }; });\nreturn panel('Gli eventi pi\\u00f9 frequenti (' + n + ')', 'Quota delle candele del timeframe in cui l\\u2019evento capita.', function () { return hbars(rows); }, function () {\nreturn table(['Evento', 'Gruppo', 'Casi', '% delle candele', 'Una volta ogni (candele)', t.fu === 'anno' ? 'All\\u2019anno' : 'Al giorno di mercato'], F.map(function (r) { return [ent(r[0]), r[1], nf(r[2], 0), nf(r[3], 2) + '%', nf(100 / r[3], 1), nf(r[4], 2)]; }));\n});\n}\nfunction secEventi(box, t) {\nif (!t.freq || !t.freq.length) { box.appendChild(h('p', 'cmuted', 'Nessun evento con almeno 30 casi i";
   s += "n questo timeframe.')); return; }\nbox.appendChild(h('div', 'bar', [\nselect('en', 'Quanti eventi', [[5, 'Primi 5'], [10, 'Primi 10'], [15, 'Primi 15']], String(ST.en || 10), function (v) { ST.en = +v; render(); }),\nselect('es', 'Ordina per', [['n', 'Quota delle candele'], ['day', 'Frequenza al giorno']], ST.es || 'n', function (v) { ST.es = v; render(); })]));\nvar F = t.freq[0];\nbox.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), 'su ' + t.id + ' capita pi\\u00f9 spesso \\u201c' + ent(F[0]) + '\\u201d (' + nf(F[3], 1) + '% delle candele, ' + nf(F[4], 1) + ' ' + fuTxt(t) + '). ' +\n'I primi ' + Math.min(5, t.freq.length) + ' eventi coprono ' + nf(t.freq.slice(0, 5).reduce(function (a, r) { return a + r[3]; }, 0), 0) + '% delle candele (gli eventi si sovrappongono).']));\nbox.appendChild(eventiPanel(t, ST.en || 10, ST.es || 'n', false));\n}\nvar CAND_G = ['Forme di candela', 'Pattern con nome', 'Serie nella stessa direzione', 'Posizione rispetto alla candela precedente', 'Coppie e terne di candele'];\nfunction clsGroups(t) {\nvar g = t.cls || {}, out = [];\nObject.keys(g).forEach(function (k) { if (k !== '__all') out.push(k); });\nreturn out;\n}\nfunction grpOpts(gs) {\nvar a = gs.filter(function (g) { return CAND_G.indexOf(g) >= 0; }), b = gs.filter(function (g) { return CAND_G.indexOf(g) < 0; }), o = [];\nif (a.length) o.push({ g: 'Candele', o: a.map(functio";
   s += "n (g) { return [g, g]; }) });\nif (b.length) o.push({ g: 'Stati della candela', o: b.map(function (g) { return [g, g]; }) });\nreturn o;\n}\nfunction secPattern(box, t) {\nvar gs = clsGroups(t);\nif (!gs.length) { box.appendChild(h('p', 'cmuted', 'Questo file non contiene le classi di candele per questo timeframe.')); return; }\nif (gs.indexOf(ST.grp) < 0) ST.grp = gs[0];\nvar meas = ST.pm || 'up', sort = ST.ps || 'z', N = ST.pn || 15;\nbox.appendChild(h('div', 'bar', [\nselect('grp', 'Gruppo', grpOpts(gs), ST.grp, function (v) { ST.grp = v; render(); }),\nselect('pm', 'Misura del grafico', [['up', 'Sale dopo (punti % sopra/sotto la media)'], ['r1', 'Rendimento della candela dopo (ATR)'], ['r3', 'Rendimento delle 3 candele dopo (ATR)']], meas, function (v) { ST.pm = v; render(); }),\nselect('ps', 'Ordina per', [['z', 'Distanza dal caso (|z|)'], ['n', 'Frequenza'], ['hi', 'Valore pi\\u00f9 alto'], ['lo', 'Valore pi\\u00f9 basso']], sort, function (v) { ST.ps = v; render(); }),\nselect('pn', 'Quante righe', [[10, 'Prime 10'], [15, 'Prime 15'], [30, 'Prime 30'], [999, 'Tutte']], String(N), function (v) { ST.pn = +v; render(); })]));\nvar all = t.clsAll || t.cls.__all || [null, 0, 100, 50, 0, 0];\nvar rows = t.cls[ST.grp].slice();\nvar ix = { up: [3, 6, 9], r1: [4, 7, 10], r3: [5, 8, 11] }[meas], ref = meas === 'up' ? all[3] : (meas === 'r1' ? all[4] : all[5]);\nvar maxz = function";
   s += " (r) { var m = 0; [6, 7, 8].forEach(function (i) { if (r[i] != null && Math.abs(r[i]) > m) m = Math.abs(r[i]); }); return m; };\nvar val = function (r) { return r[ix[0]]; };\nif (sort === 'z') rows.sort(function (a, b) { return maxz(b) - maxz(a); });\nelse if (sort === 'n') rows.sort(function (a, b) { return b[1] - a[1]; });\nelse if (sort === 'hi') rows.sort(function (a, b) { return val(b) - val(a); });\nelse rows.sort(function (a, b) { return val(a) - val(b); });\nrows = rows.slice(0, N);\nvar lead = rows.filter(function (r) { return r[ix[1]] != null && Math.abs(r[ix[1]]) >= 2; });\nbox.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), rows.length + ' righe del gruppo \\u201c' + ST.grp + '\\u201d su ' + t.id + '. ' +\n(lead.length ? lead.length + (lead.length === 1 ? ' si scosta' : ' si scostano') + ' dal caso di oltre 2 z; la pi\\u00f9 lontana \\u00e8 \\u201c' + ent(lead.sort(function (a, b) { return Math.abs(b[ix[1]]) - Math.abs(a[ix[1]]); })[0][0]) + '\\u201d (' + (meas === 'up' ? nf(lead[0][3], 1) + '% sale dopo' : nf(lead[0][ix[0]], 3) + ' ATR') + ', ' + zt(lead[0][ix[1]], lead[0][ix[2]]) + ').' : 'nessuna si scosta dal caso in modo netto.') +\n' Riferimento: tutte le candele ' + (meas === 'up' ? nf(ref, 1) + '% sale dopo' : nf(ref, 3) + ' ATR') + '.']));\nvar drows = rows.map(function (r) {\nvar v = r[ix[0]] - ref, z = r[ix[1]], sig = z != null && Math.abs";
   s += "(z) >= 2;\nvar cls = v >= 0 ? (sig ? '' : 'dim') : (sig ? 'neg' : 'negdim');\nreturn { l: ent(r[0]), sub: nf(r[1], 0) + ' casi \\u00b7 ' + nf(r[2], 2) + '% delle candele', v: v, cls: cls, txt: (meas === 'up' ? sg(v, 1) + ' pt' : sg(v, 3)) + (z != null ? ' \\u00b7 ' + zt(z, r[ix[2]]) : ''),\ntip: (meas === 'up' ? nf(r[3], 1) + '% sale dopo' : nf(r[ix[0]], 3) + ' ATR') + '\\n' + ent(r[0]) + ' \\u00b7 ' + nf(r[1], 0) + ' casi\\n' + zt(z, r[ix[2]]) + '\\nRiferimento ' + (meas === 'up' ? nf(ref, 1) + '%' : nf(ref, 3) + ' ATR') };\n});\nbox.appendChild(panel(ST.grp + ': ' + { up: 'quanto sale dopo, rispetto alla media', r1: 'rendimento a 1 candela, rispetto alla media', r3: 'rendimento a 3 candele, rispetto alla media' }[meas], 'Blu = sopra la media, rosso = sotto; colore pieno se |z| \\u2265 2, tenue se compatibile con il caso. \\u2020 robusto, \\u00a7 solo FDR.',\nfunction () { return hbars(drows, { div: true }); },\nfunction () {\nreturn table(['Classe', 'Casi', '% candele', 'Sale dopo %', 'Rend. 1 (ATR)', 'Rend. 3 (ATR)', 'z sale', 'z r1', 'z r3', 'Range dopo', 'Rompe max %', 'Rompe min %'],\nrows.map(function (r) { return [ent(r[0]) + (r[17] ? ' [' + r[17] + ']' : ''), nf(r[1], 0), nf(r[2], 2), nf(r[3], 1), nf(r[4], 3), nf(r[5], 3), r[6] == null ? '\\u2013' : sg(r[6], 1) + (MK[r[9] || 0] || ''), r[7] == null ? '\\u2013' : sg(r[7], 1) + (MK[r[10] || 0] || ''), r[8] == null ? '";
   s += "\\u2013' : sg(r[8], 1) + (MK[r[11] || 0] || ''), nf(r[12], 2), nf(r[13], 1), nf(r[14], 1)]; }));\n}));\n}\nfunction secPre(box, t) {\nif (!t.pre || (!t.pre.up && !t.pre.dn)) { box.appendChild(h('p', 'cmuted', 'Questo file non contiene i precursori degli impulsi per questo timeframe.')); return; }\nvar d = ST.pd || 'up';\nif (!t.pre[d]) d = d === 'up' ? 'dn' : 'up';\nbox.appendChild(h('div', 'bar', [\nselect('pd', 'Impulso', [['up', 'Rialzista'], ['dn', 'Ribassista']], d, function (v) { ST.pd = v; render(); }),\nselect('po', 'Mostra', [['all', 'Tutti gli stati'], ['sig', 'Solo quelli lontani dal caso (|z| \\u2265 2)']], ST.po || 'all', function (v) { ST.po = v; render(); })]));\nvar P = t.pre[d], only = (ST.po || 'all') === 'sig';\nvar rows = [], lastg = -1, best = topPre(t, d);\nP.r.forEach(function (r) {\nif (only && !(r[4] != null && Math.abs(r[4]) >= 2)) return;\nif (r[1] !== lastg) { lastg = r[1]; rows.push({ g: (DATA.pg && DATA.pg[r[1]]) || 'Stato' }); }\nvar sig = r[4] != null && Math.abs(r[4]) >= 2;\nrows.push({ l: ent(r[0]), v: r[2], tick: r[3], cls: sig ? (r[4] > 0 ? '' : 'neg') : 'dim', txt: nf(r[2], 0) + ' vs ' + nf(r[3], 1) + ' \\u00b7 ' + (r[4] == null ? 'n/d' : zt(r[4], r[5])),\ntip: nf(r[2], 0) + ' volte prima di un impulso\\n' + ent(r[0]) + '\\nAttese ' + nf(r[3], 1) + ' nelle stesse ore\\n' + (r[4] == null ? 'campione insufficiente' : zt(r[4], r[5])) });\n});\n";
   s += "box.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), 'su ' + t.id + ' ci sono ' + nf(P.n, 0) + ' impulsi ' + (d === 'up' ? 'rialzisti' : 'ribassisti') + '. ' +\n(best ? 'Lo stato pi\\u00f9 sopra il normale \\u00e8 ' + preTxt(best) + '.' : 'nessuno stato \\u00e8 pi\\u00f9 frequente del normale in modo netto (|z| < 2).') +\n' Confronto con le candele non impulso della stessa ora e dello stesso regime di volatilit\\u00e0.']));\nbox.appendChild(panel('Stato della candela prima dell\\u2019impulso ' + (d === 'up' ? 'rialzista' : 'ribassista'), 'Barra = quante volte prima dell\\u2019impulso; tacca = quante ne aspetteremmo. Blu = pi\\u00f9 del normale, rosso = meno, tenue = compatibile con il caso.', function () {\nvar blocks = h('div', 'chb'), grp = [], all = [];\nrows.forEach(function (r) { if (r.g) { grp = []; all.push({ g: r.g, rows: grp }); } else grp.push(r); });\nall.forEach(function (b) {\nvar mx = 0; b.rows.forEach(function (r) { mx = Math.max(mx, r.v, r.tick || 0); });\nvar part = hbars([{ g: b.g }].concat(b.rows), { max: mx * 1.1 });\nArray.prototype.slice.call(part.childNodes).forEach(function (c) { blocks.appendChild(c); });\n});\nreturn blocks;\n}, function () {\nreturn table(['Stato', 'Osservati', 'Attesi', 'Rapporto', 'z', 'Segno'], P.r.filter(function (r) { return !only || (r[4] != null && Math.abs(r[4]) >= 2); }).map(function (r) { return [ent(r[0]), nf";
   s += "(r[2], 0), nf(r[3], 1), r[3] > 0 ? nf(r[2] / r[3], 2) : '\\u2013', r[4] == null ? '\\u2013' : sg(r[4], 1), MK[r[5] || 0] || '']; }));\n}));\nif (t.comp && t.comp.length === 3) {\nvar fam = ['Doji', 'Pin', 'Trottola', 'Corpo medio', 'Corpo lungo', 'Marubozu'];\nvar rowsC = fam.map(function (f, k) { return [f, nf(t.comp[0][k], 1) + '%', nf(t.comp[1][k], 1) + '%', nf(t.comp[2][k], 1) + '%']; });\nrowsC.push(['Ampiezza media (ATR)', nf(t.comp[0][6], 2), nf(t.comp[1][6], 2), nf(t.comp[2][6], 2)]);\nbox.appendChild(h('figure', null, [h('figcaption', null, [h('span', 't', 'Come sono fatti gli impulsi'), h('span', 's', 'Forma della candela: quota tra tutte le candele e tra gli impulsi rialzisti e ribassisti.')]), table(['Forma', 'Tutte le candele', 'Impulsi rialzisti', 'Impulsi ribassisti'], rowsC)]));\n}\n}\nfunction secRob(box, t) {\nvar R = (t.rob || []).slice();\nif (!R.length) { box.appendChild(h('p', 'cmuted', 'Nessun confronto robusto in questo timeframe (o non incluso nel file).')); return; }\nvar fam = ST.rf || 'all', N = ST.rn || 15;\nbox.appendChild(h('div', 'bar', [\nselect('rf', 'Famiglia', [['all', 'Tutte'], ['dir', 'Direzione (dopo la candela, per fascia di tempo)'], ['rit', 'Ritmo dell\\u2019attivit\\u00e0 (range, candele grandi, impulsi)'], ['pre', 'Precursori degli impulsi']], fam, function (v) { ST.rf = v; render(); }),\nselect('rn', 'Quanti', [[5, 'Primi 5'], [10, '";
   s += "Primi 10'], [15, 'Primi 15'], [25, 'Primi 25']], String(N), function (v) { ST.rn = +v; render(); })]));\nvar map = { dir: [0, 1, 2], rit: [3, 4], pre: [5] };\nif (fam !== 'all') R = R.filter(function (r) { return map[fam].indexOf(r[2]) >= 0; });\nR = R.slice(0, N);\nvar fc = [0, 0, 0];\n(t.rob || []).forEach(function (r) { fc[r[2] <= 2 ? 0 : (r[2] <= 4 ? 1 : 2)]++; });\nbox.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), 'su ' + t.id + ' i confronti che superano il controllo dei falsi positivi e hanno lo stesso verso nelle due met\\u00e0 dello storico sono ' + nf(t.nrob, 0) + '. ' +\n'Tra i ' + nf((t.rob || []).length, 0) + ' pi\\u00f9 forti del file: direzione ' + nf(fc[0], 0) + ', ritmo dell\\u2019attivit\\u00e0 ' + nf(fc[1], 0) + ', precursori degli impulsi ' + nf(fc[2], 0) + '. I confronti di ritmo sono in gran parte la stagionalit\\u00e0 della volatilit\\u00e0 (nota); quelli di direzione sono i pi\\u00f9 rari.']));\nvar rows = R.map(function (r) { return { l: ent(r[0]), v: Math.abs(r[1]), txt: 'z ' + sg(r[1], 1), cls: r[1] >= 0 ? '' : 'neg', tip: 'z ' + sg(r[1], 1) + '\\n' + ent(r[0]) }; });\nbox.appendChild(panel('Confronti robusti di ' + t.id, 'Lunghezza della barra = |z|; blu = sopra il riferimento, rosso = sotto. Descrivono l\\u2019andamento del prezzo, non un guadagno: nessun costo \\u00e8 considerato.', function () { return hbars(rows); },\nfunction (";
   s += ") { return table(['Confronto', 'z', 'Famiglia'], R.map(function (r) { return [ent(r[0]), sg(r[1], 1), ['classi', 'direzione ora/minuto', 'direzione calendario', 'ritmo ora/minuto', 'ritmo calendario', 'precursori'][r[2]] || '']; })); }));\n}\nfunction secConf(box) {\nvar tfs = DATA.tfs.filter(function (t) { return t.prof && t.prof.hour && t.prof.hour.r.length > 3; });\nif (!tfs.length) { box.appendChild(h('p', 'cmuted', 'Nessun timeframe con profilo orario nel file.')); return; }\nvar mk = ST.cm || 'rng';\nbox.appendChild(h('div', 'bar', [select('cm', 'Misura', [['rng', 'Range rispetto alla media del timeframe'], ['imp', '% di impulsi'], ['bull', '% di candele rialziste']], mk, function (v) { ST.cm = v; render(); })]));\nvar vals = {}, mx = 0, mn = 1e9;\ntfs.forEach(function (t) {\nvar all = t.prof.hour.all;\nt.prof.hour.r.forEach(function (r) {\nvar v = mk === 'rng' ? (all[3] ? r[4] / all[3] : null) : (mk === 'imp' ? r[6] : r[2]);\nif (v == null) return;\nvar m = /^(\\d\\d)-(\\d\\d)h$/.exec(r[0]), a, b;\nif (m) { a = +m[1]; b = +m[2]; } else { m = /^(\\d\\d)h$/.exec(r[0]); if (!m) return; a = +m[1]; b = a + 1; }\nfor (var k = a; k < b && k < 24; k++) vals[t.id + '|' + ('0' + k).slice(-2) + 'h'] = v;\nmx = Math.max(mx, v); mn = Math.min(mn, v);\n});\n});\nvar lines = tfs.map(function (t) {\nvar b = bestWorst(t, 'hour', mk === 'rng' ? METS[0] : (mk === 'imp' ? METS[1] : METS[3])";
   s += ");\nreturn b ? t.id + ': ' + hlab(b.hi[0]) : null;\n}).filter(Boolean);\nbox.appendChild(h('div', 'say', [h('b', null, 'In poche parole: '), (mk === 'rng' ? 'ora con il range maggiore' : mk === 'imp' ? 'ora con pi\\u00f9 impulsi' : 'ora pi\\u00f9 rialzista') + ' per timeframe \\u2013 ' + lines.join('; ') + '.']));\nvar hours = []; for (var i = 0; i < 24; i++) hours.push(('0' + i).slice(-2) + 'h');\npanelHeat(box, tfs, hours, vals, mk, mn, mx);\n}\nfunction panelHeat(box, tfs, hours, vals, mk, mn, mx) {\nvar pol = mk === 'bull', fm = function (v) { return mk === 'rng' ? '\\u00d7' + nf(v, 2) : nf(v, mk === 'imp' ? 2 : 1) + '%'; };\nbox.appendChild(panel('Ora del giorno \\u00d7 timeframe (ora dei dati)', 'Ogni casella \\u00e8 una fascia oraria di un timeframe; pi\\u00f9 scuro/intenso = valore pi\\u00f9 alto' + (pol ? '; blu sopra il 50%, rosso sotto' : '') + '. Passa il puntatore per il valore.', function () {\nvar t = h('table', 'hm'), th = h('thead'), tr = h('tr', null, [h('th')]);\nhours.forEach(function (x) { tr.appendChild(h('th', null, x.slice(0, 2))); });\nth.appendChild(tr); t.appendChild(th);\nvar tb = h('tbody');\ntfs.forEach(function (tf) {\nvar row = h('tr', null, [h('td', null, tf.id)]);\nhours.forEach(function (hx) {\nvar v = vals[tf.id + '|' + hx], td = h('td');\nif (v != null) {\nvar a;\nif (pol) { var dv = (v - 50) / Math.max(1, Math.max(mx - 50, 50 - mn)); a = Ma";
   s += "th.min(1, Math.abs(dv)) * 100; td.style.background = 'color-mix(in srgb,' + (dv >= 0 ? 'var(--c-s1,#3987e5)' : 'var(--c-neg,#e66767)') + ' ' + px(Math.max(4, a)) + '%,var(--c-heat0,#1c2230))'; }\nelse { a = (v - 0) / (mx || 1) * 100; td.style.background = 'color-mix(in srgb,var(--c-s1,#3987e5) ' + px(Math.max(4, a)) + '%,var(--c-heat0,#1c2230))'; }\ntd.setAttribute('data-tip', fm(v) + '\\n' + tf.id + ' \\u00b7 ' + hlab(hx)); td.setAttribute('tabindex', '0');\n}\nrow.appendChild(td);\n});\ntb.appendChild(row);\n});\nt.appendChild(tb);\nreturn h('div', 'plot', [t, h('div', 'lgd', [pol ? 'sotto il 50%' : 'meno', h('i', pol ? 'dv' : null), pol ? 'sopra il 50%' : 'pi\\u00f9 (max ' + fm(mx) + ')'])]);\n}, function () {\nreturn table(['Timeframe'].concat(hours), tfs.map(function (tf) { return [tf.id].concat(hours.map(function (hx) { var v = vals[tf.id + '|' + hx]; return v == null ? '\\u2013' : fm(v); })); }));\n}));\n}\nfunction secEdge(box) {\nvar e = DATA.edge;\nif (!e) { box.appendChild(h('p', 'cmuted', 'Il file non contiene la sintesi edge.')); return; }\nif (e.warn) box.appendChild(h('div', 'box bad', [h('b', null, '\\u26a0 Costi del broker non disponibili. '), ent(e.warn)]));\nbox.appendChild(h('div', 'box ' + (e.col || 'info'), [h('b', null, 'Verdetto. '), ent(e.head), h('div', 'cmuted', ent(e.stat))]));\nbox.appendChild(h('div', 'ckpis', [kpi('Robuste', nf(e.cnt[3], 0), 'supe";
   s += "rano tutti i controlli'), kpi('Promettenti', nf(e.cnt[2], 0), 'tutto tranne i test multipli'), kpi('Indizi', nf(e.cnt[1], 0), 'positive e stabili'),\nkpi('Scartate', nf(e.cnt[0], 0), 'senza vantaggio'), kpi('Costo del broker', e.cost || 'n/d', e.costsrc || ''),\ne.tests != null ? kpi('Confronti in tutte le schede', nf(e.tests, 0), 'oltre z 3: ' + nf(e.n3, 0) + ' (attesi per caso ' + nf(e.exp3, 0) + ')') : null]));\nif (DATA.cxr) box.appendChild(h('div', 'say', [h('b', null, 'Scheda Candele, 21 timeframe: '), nf(DATA.cxr.all, 0) + ' confronti; robusti (controllo dei falsi positivi e stesso verso nelle due met\\u00e0) \\u2013 direzione ' + nf(DATA.cxr.r[0], 0) + ' su ' + nf(DATA.cxr.t[0], 0) +\n', ritmo dell\\u2019attivit\\u00e0 ' + nf(DATA.cxr.r[1], 0) + ' su ' + nf(DATA.cxr.t[1], 0) + ' (in gran parte stagionalit\\u00e0 della volatilit\\u00e0), precursori degli impulsi ' + nf(DATA.cxr.r[2], 0) + ' su ' + nf(DATA.cxr.t[2], 0) + '. Sono misure descrittive, senza costi.']));\nif (e.bs) box.appendChild(h('div', 'say', [h('b', null, 'Bias del calendario e degli impulsi: '), ent(e.bs)]));\nif (e.top && e.top.length) box.appendChild(h('figure', null, [h('figcaption', null, [h('span', 't', 'Le strategie candidate migliori'), h('span', 's', 'Scelte tra R/R e ORB; livello dopo i controlli (su quelli applicabili). Il dettaglio dei 7 controlli \\u00e8 nella scheda Sintesi edge.')]),\ntable";
   s += "(['Livello', 'Fonte', 'Timeframe', 'Operazione', 'Contesto', 'Trade', 'Netta peggiore (R)', 'z netto', 'Controlli'], e.top.map(function (r) { return [r[0], ent(r[1]), r[2], ent(r[3]), ent(r[4]), nf(r[5], 0), sg(r[6], 3), sg(r[7], 1), r[8] + '/' + r[9]]; }), [0, 1, 2, 3, 4])]));\n(e.bias || []).forEach(function (b) {\nif (!b[2] || !b[2].length) return;\nbox.appendChild(h('figure', null, [h('figcaption', null, [h('span', 't', ent(b[0])), h('span', 's', nf(b[1], 0) + ' robusti; qui i primi ' + b[2].length)]),\nhbars(b[2].map(function (r) { return { l: ent(r[1]), v: Math.abs(r[0]), txt: 'z ' + sg(r[0], 1), cls: r[0] >= 0 ? '' : 'neg', tip: 'z ' + sg(r[0], 1) + '\\n' + ent(r[1]) }; }))]));\n});\n}\nvar LV = { min: 'Minimo (qualche riga per timeframe)', ess: 'Essenziale (profili e classi migliori)', full: 'Completo (tutto)' };\nfunction trimTf(t, lv) {\nif (lv === 'full') return t;\nvar o = {}, keep = ['id', 'sec', 'n', 't0', 't1', 'span', 'bull', 'medR', 'body', 'thr', 'nimp', 'impP', 'nrob', 'tst', 'fu'];\nkeep.forEach(function (k) { if (t[k] != null) o[k] = t[k]; });\nvar dims = lv === 'min' ? ['hour', 'dow', 'mon'] : ['hour', 'min', 'dow', 'wom', 'mon', 'qtr', 'yr'], cols = lv === 'min' ? 7 : 17;\no.prof = {};\ndims.forEach(function (d) { if (t.prof && t.prof[d]) o.prof[d] = { all: t.prof[d].all.slice(0, cols - 1), r: t.prof[d].r.filter(function (r) { return r[1] > 0; }).map(func";
   s += "tion (r) { return r.slice(0, cols); }) }; });\no.freq = (t.freq || []).slice(0, lv === 'min' ? 10 : 15);\no.clsAll = t.clsAll || (t.cls && t.cls.__all);\nvar groups = t.cls || {}, cand = [];\nvar mz = function (r) { var m = 0; [6, 7, 8].forEach(function (i) { if (r[i] != null && Math.abs(r[i]) > m) m = Math.abs(r[i]); }); return m; };\nif (lv === 'min') {\nObject.keys(groups).forEach(function (g) { if (g !== '__all') groups[g].forEach(function (r) { if (r[1] >= 100) cand.push(r.slice(0, 12).concat([null, null, null, null, null, g])); }); });\ncand.sort(function (a, b) { return mz(b) - mz(a); });\no.cls = { 'Le pi\\u00f9 lontane dal caso': cand.slice(0, 12) };\n} else {\no.cls = {};\nObject.keys(groups).forEach(function (g) {\nif (g === '__all') return;\nvar rows = groups[g].slice().sort(function (a, b) { return mz(b) - mz(a); }).filter(function (r) { return mz(r) >= 1.5; }).slice(0, 5).map(function (r) { return r.slice(0, 12); });\nif (rows.length) o.cls[g] = rows;\n});\n}\no.pre = {};\n['up', 'dn'].forEach(function (d) {\nvar P = t.pre && t.pre[d]; if (!P) return;\nvar r = P.r.filter(function (q) { return q[4] != null; }).sort(function (a, b) { return Math.abs(b[4]) - Math.abs(a[4]); }).slice(0, lv === 'min' ? 6 : 12).sort(function (a, b) { return a[1] - b[1]; });\no.pre[d] = { n: P.n, r: r };\n});\no.top = t.top; o.rob = (t.rob || []).slice(0, lv === 'min' ? 8 : 20);\nif (lv ";
   s += "!== 'min' && t.comp) o.comp = t.comp;\nreturn o;\n}\nfunction trimEdge(e) {\nif (!e) return e;\nvar o = {};\nObject.keys(e).forEach(function (k) { o[k] = e[k]; });\no.top = (e.top || []).slice(0, 4);\no.bias = (e.bias || []).map(function (b) { return [b[0], b[1], b[2].slice(0, 4)]; });\nreturn o;\n}\nfunction makeDigest(ids, lv) {\nvar o = { v: 1, app: 'MarketProfiler-cruscotto', level: lv, sym: DATA.sym, gen: DATA.gen, tz: DATA.tz, roll: DATA.roll, ref: DATA.ref, pg: DATA.pg, cxr: DATA.cxr, skip: DATA.skip, tfs: [], edge: lv === 'min' ? trimEdge(DATA.edge) : DATA.edge };\nids.forEach(function (id) { var t = byId(id); if (t) o.tfs.push(trimTf(t, lv)); });\nreturn o;\n}\nfunction secFile(box) {\nvar ids = DATA.tfs.map(function (t) { return t.id; });\nvar presets = { main: ['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1', 'W1'], all: ids, low: ids.filter(function (i) { return ['D1', 'W1', 'MN1'].indexOf(i) < 0; }), one: [ST.tf] };\nif (!ST.fp) { ST.fp = 'main'; ST.fl = 'min'; ST.sel = presets.main.filter(function (i) { return ids.indexOf(i) >= 0; }); }\nbox.appendChild(h('div', 'say', [h('b', null, 'Come si usa: '), 'scegli i timeframe e il livello di dettaglio, controlla la dimensione, premi \\u201cCopia\\u201d e incolla il testo in chat: lo metto in un cruscotto come questo, con grafici e riassunti. ' +\n'Il livello \\u201cMinimo\\u201d tiene per ogni timeframe i profili di ora, gio";
   s += "rno e mese, gli eventi pi\\u00f9 frequenti, le classi e i precursori pi\\u00f9 lontani dal caso e i confronti robusti.']));\nvar ta = h('textarea', 'dg', null, { readonly: 'readonly', spellcheck: 'false', 'aria-label': 'File per l\\u2019analisi' });\nvar info = h('span', 'cst'), stt = h('span', 'cst');\nvar chk = h('div', 'chk');\nfunction refresh() {\nvar sel = ids.filter(function (i) { return ST.sel.indexOf(i) >= 0; });\nvar txt = JSON.stringify(makeDigest(sel, ST.fl));\nta.value = txt;\nvar kb = txt.length / 1024;\ninfo.textContent = nf(sel.length, 0) + ' timeframe \\u00b7 ' + nf(txt.length, 0) + ' caratteri (' + nf(kb, 0) + ' KB) \\u00b7 circa ' + nf(Math.round(txt.length / 3 / 100) * 100, 0) + ' token';\nstt.textContent = '';\n}\nfunction boxes() {\nwhile (chk.firstChild) chk.removeChild(chk.firstChild);\nids.forEach(function (i) {\nvar c = h('input', null, null, { type: 'checkbox', id: 'cxd-c-' + i }); c.checked = ST.sel.indexOf(i) >= 0;\nc.addEventListener('change', function () { ST.sel = c.checked ? ST.sel.concat([i]) : ST.sel.filter(function (x) { return x !== i; }); ST.fp = 'custom'; refresh(); });\nchk.appendChild(h('label', null, [c, i]));\n});\n}\nbox.appendChild(h('div', 'bar', [\nselect('fp', 'Timeframe', [['main', 'Principali (M1 M5 M15 M30 H1 H4 D1 W1)'], ['low', 'Tutti sotto il D1'], ['all', 'Tutti'], ['one', 'Solo quello scelto in alto'], ['custom', 'Scelta l";
   s += "ibera']], ST.fp, function (v) {\nST.fp = v; if (v !== 'custom') ST.sel = presets[v].filter(function (i) { return ids.indexOf(i) >= 0; }); render();\n}),\nselect('fl', 'Dettaglio', Object.keys(LV).map(function (k) { return [k, LV[k]]; }), ST.fl, function (v) { ST.fl = v; refresh(); })]));\nbox.appendChild(chk); boxes();\nvar cp = h('button', 'main', 'Copia', { type: 'button' });\ncp.addEventListener('click', function () {\nfunction done() { stt.className = 'cst ok'; stt.textContent = 'Copiato (' + nf(ta.value.length, 0) + ' caratteri). Incollalo in chat.'; }\nfunction fb() { ta.focus(); ta.select(); var ok = false; try { ok = document.execCommand('copy'); } catch (e) { } if (ok) done(); else { stt.className = 'cst'; stt.textContent = 'Testo selezionato: premi Ctrl+C.'; } }\nif (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(ta.value).then(done, fb); else fb();\n});\nbox.appendChild(h('div', 'bar', [cp, info, stt]));\nbox.appendChild(ta);\nrefresh();\n}\nfunction render() {\nif (!DATA) return;\nLASTW = root.clientWidth;\nwhile (root.firstChild) root.removeChild(root.firstChild);\nTIP = null;\nvar tfOpts = TFORD.filter(function (i) { return byId(i); }).map(function (i) { var t = byId(i); return [i, i + ' \\u00b7 ' + nf(t.n, 0) + ' candele']; });\nif (!byId(ST.tf)) ST.tf = byId('H1') ? 'H1' : (tfOpts.length ? tfOpts[0][0] : null);\nvar t = ST.tf";
   s += " ? byId(ST.tf) : null;\nvar head = h('div', 'bar', [\nselect('tf', 'Timeframe', tfOpts, ST.tf, function (v) { ST.tf = v; render(); }),\nselect('sec', 'Cosa vedere', SECS, ST.sec, function (v) { ST.sec = v; render(); })]);\nroot.appendChild(head);\nroot.appendChild(h('p', 'cst', [h('b', null, DATA.sym || ''), ' \\u00b7 ' + (DATA.gen || '') + (DATA.roll ? ' \\u00b7 rollover ' + DATA.roll : '') + ' \\u00b7 ' + ent(DATA.tz || '') + '. \\u2020 = robusto (controllo dei falsi positivi e stesso verso nelle due met\\u00e0), \\u00a7 = solo controllo dei falsi positivi. Misure descrittive, senza costi.']));\nvar sk = DATA.skip ? Object.keys(DATA.skip) : [];\nif (sk.length) root.appendChild(h('p', 'cst', 'Non calcolati: ' + sk.map(function (k) { return k + (DATA.skip[k] === 1 ? ' (servono dati M1)' : ' (dati insufficienti)'); }).join(', ') + '.'));\nvar box = h('div');\nroot.appendChild(box);\nif (ST.sec === 'edge') secEdge(box);\nelse if (ST.sec === 'conf') secConf(box);\nelse if (!t) box.appendChild(h('p', 'cmuted', 'Nessun timeframe nei dati.'));\nelse if (ST.sec === 'sintesi') secSintesi(box, t);\nelse if (ST.sec === 'quando') secQuando(box, t);\nelse if (ST.sec === 'eventi') secEventi(box, t);\nelse if (ST.sec === 'pattern') secPattern(box, t);\nelse if (ST.sec === 'pre') secPre(box, t);\nelse if (ST.sec === 'rob') secRob(box, t);\nelse if (ST.sec === 'file') secFile(box);\n}\nfunctio";
   s += "n load(obj) {\nDATA = obj;\nDATA.tfs = (DATA.tfs || []);\nDATA.tfs.forEach(function (t) { if (t.cls && t.cls.__all) { t.clsAll = t.cls.__all; delete t.cls.__all; } });\nvar keep = { tf: ST.tf, sec: ST.sec };\nST = { tf: keep.tf, sec: keep.sec || 'sintesi' };\nrender();\n}\nwindow.CXD = { load: load, digest: function (ids, lv) { return makeDigest(ids, lv); } };\nvar el = document.getElementById('cxd-data');\nif (el && el.textContent.trim()) { try { load(JSON.parse(el.textContent)); } catch (e) { root.appendChild(h('p', 'cst', 'Dati non leggibili: ' + e.message)); } }\nif (window.ResizeObserver) { var to = null; new ResizeObserver(function () { if (Math.abs(root.clientWidth - LASTW) > 24 && root.clientWidth > 0) { clearTimeout(to); to = setTimeout(render, 120); } }).observe(root); }\n})();";
   return s;
  }
