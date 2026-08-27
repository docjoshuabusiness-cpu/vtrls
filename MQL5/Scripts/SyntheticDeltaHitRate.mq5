//+------------------------------------------------------------------+
//|                                      SyntheticDeltaHitRate.mq5   |
//|  Domanda singola: dopo il segnale, il prezzo raggiunge X punti    |
//|  entro Y barre? E a che ora succede piu' spesso?                  |
//|  In piu': quanta sofferenza (MAE) c'e' stata prima di arrivarci   |
//|  -> serve a scegliere lo SL dopo, non prima.                      |
//+------------------------------------------------------------------+
#property copyright "SyntheticDelta HitRate"
#property version   "1.00"
#property script_show_inputs
#property strict

input group "=== DATI ==="
input ENUM_TIMEFRAMES InpTF = PERIOD_M1;  // timeframe ANALIZZATO (indipendente dal grafico su cui trascini lo script)

input group "=== LA DOMANDA ==="
input int      InpTPpoints      = 2000;   // punti da raggiungere dopo il segnale
input int      InpMaxBars       = 60;     // entro quante barre (scalping M1: 15-60, NON 300)
input int      InpEntryDelay    = 1;      // 1 = entra all'open della barra dopo il segnale

input group "=== PERIODO ==="
input datetime InpFrom          = D'2015.01.01 00:00';
input datetime InpTo            = D'2026.07.15 00:00';
input int      InpTimeOffsetH   = 0;      // shift ore server -> fuso desiderato

input group "=== COSTI ==="
input double   InpCostPoints    = 0;      // 0 = spread reale della barra
input double   InpExtraCostPts  = 0;      // commissione/slippage extra in punti

input group "=== SWEEP STOP LOSS (tabella finale) ==="
input int      InpSLfrom        = 100;
input int      InpSLto          = 3000;
input int      InpSLstep        = 100;

input group "=== PARAMETRI INDICATORE ==="
input int      EmaPeriod        = 13;
input int      VolAvgPeriod     = 20;
input double   SignalThreshold  = 0.15;
input bool     UseADXFilter     = true;
input int      ADX_Period       = 14;
input double   ADX_MinLevel     = 20.0;
input bool     UseSRFilter      = true;
input int      SR_Lookback      = 15;
input double   SR_Proximity     = 0.5;
input int      ATR_Period       = 14;

input group "=== CLASSIFICA ORARI ==="
input int      InpRefSL         = 0;      // SL di riferimento per la classifica (0 = usa il migliore dello sweep)
input int      InpBucketMin     = 30;     // ampiezza bucket in minuti per la classifica fine (15/30/60)

input group "=== SCANSIONE SOGLIA ==="
input bool     InpThresholdScan = true;   // ignora SignalThreshold e produce la curva edge-vs-soglia
input double   InpScanMinDelta  = 0.05;   // delta minimo catturato durante la scansione
input double   InpScanMaxDelta  = 0.80;   // estremo alto della curva
input int      InpScanSteps     = 16;     // punti della curva

input group "=== TEST DEL SEGNALE ==="
input bool     InpInvertSignals = false;  // inverte ogni segnale (per testare se l'edge e' al contrario)
input int      InpOnlyDir       = 0;      // 0 = entrambi, 1 = solo buy, -1 = solo sell

input group "=== ALTRO ==="
input int      InpCooldownBars  = 0;      // scarta segnali stessa direzione entro N barre
input int      InpMinPerBucket  = 30;     // sotto questa soglia il bucket e' rumore
input bool     InpExportCSV     = true;

#define BIG 2147483647

//--- dati
MqlRates g_r[];
double   g_ema[], g_atr[], g_adx[];
int      g_bars = 0;
double   g_pt;
double   g_atrMed = 0, g_ptValue = 0;

//--- livelli SL per lo sweep
int      g_sl[];
int      g_nSL = 0;

//--- record per segnale
datetime s_time[];
int      s_dir[];
int      s_tTP[];        // barra di primo tocco del TP (BIG = mai)
double   s_maeAtTP[];    // MAE (punti) accumulato fino al tocco del TP
double   s_maeFull[];    // MAE su tutto l'orizzonte
double   s_mfe[];        // MFE su tutto l'orizzonte
double   s_endPts[];     // P/L a scadenza orizzonte
double   s_cost[];       // costo (spread+extra) in punti pagato all'ingresso
double   s_delta[];      // normalizedDelta al segnale
int      s_tSL[];        // [s*g_nSL + k] primo tocco livello SL k
int      g_n = 0;

//--- prototipi
void   WriteReport();
void   WriteCSV();

//+------------------------------------------------------------------+
//| Carica le barre forzando la sincronizzazione dello storico       |
//+------------------------------------------------------------------+
int LoadRates()
  {
   int maxb = (int)TerminalInfoInteger(TERMINAL_MAXBARS);
   int got = 0;
   for(int attempt = 0; attempt < 60; attempt++)
     {
      got = CopyRates(_Symbol, InpTF, 0, maxb, g_r);
      if(got > 0 && SeriesInfoInteger(_Symbol, InpTF, SERIES_SYNCHRONIZED)) break;
      Sleep(500);   // il terminale sta scaricando lo storico dal server
     }
   long serverBars = SeriesInfoInteger(_Symbol, InpTF, SERIES_BARS_COUNT);
   datetime first  = (datetime)SeriesInfoInteger(_Symbol, InpTF, SERIES_FIRSTDATE);
   Print("Storico ", EnumToString(InpTF), ": disponibili ", serverBars,
         " barre da ", first, " | caricate ", got, " | TERMINAL_MAXBARS=", maxb);
   if(serverBars > maxb)
      Print("!!! LIMITE: il terminale espone solo ", maxb, " barre su ", serverBars,
            ". Strumenti > Opzioni > Grafici > 'Max barre nel grafico' = Illimitato, poi riavvia MT5.");
   return got;
  }

//+------------------------------------------------------------------+
bool WaitH(int h, string nm)
  {
   if(h == INVALID_HANDLE) { Print("Handle nullo: ", nm); return false; }
   for(int k = 0; k < 300; k++) { if(BarsCalculated(h) >= g_bars) return true; Sleep(50); }
   Print("Timeout indicatore ", nm); return false;
  }

//+------------------------------------------------------------------+
bool CopyAll(int h, int total, double &dst[])
  {
   ArrayResize(dst, total); ArraySetAsSeries(dst, false);
   double tmp[]; ArraySetAsSeries(tmp, false);
   int done = 0;
   while(done < total)
     {
      int n = MathMin(100000, total - done);
      int got = CopyBuffer(h, 0, total - done - n, n, tmp);
      if(got <= 0) { Print("CopyBuffer err ", GetLastError()); return false; }
      for(int k = 0; k < got; k++) dst[done + k] = tmp[k];
      done += got;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Logica identica a SyntheticDelta v2.1                            |
//+------------------------------------------------------------------+
int EvalSignal(int i, double &outDelta)
  {
   outDelta = 0.0;
   if(g_atr[i] <= 0.0) return 0;
   double range = g_r[i].high - g_r[i].low;
   if(range <= 0.0) return 0;
   double tickVol = (double)g_r[i].tick_volume;
   if(tickVol <= 0.0) return 0;

   double ema      = g_ema[i];
   double fracBuy  = (g_r[i].close - g_r[i].low)   / range;
   double fracSell = (g_r[i].high  - g_r[i].close) / range;
   double bullsN   = (g_r[i].high - ema) / range;
   double bearsN   = (ema - g_r[i].low)  / range;

   double volSum = 0; int volCnt = 0;
   for(int j = i; j > i - VolAvgPeriod && j >= 0; j--) { volSum += (double)g_r[j].tick_volume; volCnt++; }
   double volAvg = (volCnt > 0) ? volSum / volCnt : tickVol;
   double volW   = (volAvg > 0) ? MathMin(tickVol / volAvg, 3.0) : 1.0;

   double delta = (fracBuy * (1.0 + bullsN) * volW - fracSell * (1.0 + bearsN) * volW) / 6.0;
   outDelta = delta;

   if(UseADXFilter && g_adx[i] < ADX_MinLevel) return 0;

   if(UseSRFilter && i >= SR_Lookback)
     {
      double res = -DBL_MAX, sup = DBL_MAX;
      for(int j = i - SR_Lookback; j < i; j++)
        { if(g_r[j].high > res) res = g_r[j].high; if(g_r[j].low < sup) sup = g_r[j].low; }
      double prox = g_atr[i] * SR_Proximity;
      if(!(MathAbs(g_r[i].close - res) <= prox || MathAbs(g_r[i].close - sup) <= prox ||
           g_r[i].close > res || g_r[i].close < sup)) return 0;
     }

   double thr = InpThresholdScan ? InpScanMinDelta : SignalThreshold;
   if(delta >  thr) return  1;
   if(delta < -thr) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   g_pt = _Point;
   for(int v = InpSLfrom; v <= InpSLto; v += InpSLstep)
     { ArrayResize(g_sl, g_nSL + 1); g_sl[g_nSL++] = v; }

   ArraySetAsSeries(g_r, false);
   g_bars = LoadRates();
   if(g_bars <= 0) { Print("CopyRates fallita: ", GetLastError()); return; }

   int hE = iMA(_Symbol, InpTF, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   int hA = iATR(_Symbol, InpTF, ATR_Period);
   int hD = UseADXFilter ? iADX(_Symbol, InpTF, ADX_Period) : INVALID_HANDLE;
   if(!WaitH(hE, "EMA") || !WaitH(hA, "ATR")) return;
   if(UseADXFilter && !WaitH(hD, "ADX")) return;
   if(!CopyAll(hE, g_bars, g_ema) || !CopyAll(hA, g_bars, g_atr)) return;
   if(UseADXFilter) { if(!CopyAll(hD, g_bars, g_adx)) return; }
   else { ArrayResize(g_adx, g_bars); ArrayInitialize(g_adx, 100.0); }

//--- diagnostica strumento
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_ptValue = (ts > 0) ? tv * (g_pt / ts) : 0.0;
     {
      double tmp[]; int n = 0; ArrayResize(tmp, g_bars);
      for(int i = 0; i < g_bars; i++)
         if(g_r[i].time >= InpFrom && g_r[i].time <= InpTo && g_atr[i] > 0) tmp[n++] = g_atr[i] / g_pt;
      if(n > 0) { ArrayResize(tmp, n); ArraySort(tmp); g_atrMed = tmp[n/2]; }
     }
   Print("=== ", _Symbol, " ", EnumToString(InpTF),
         " | Digits=", _Digits, " | Point=", DoubleToString(g_pt, 8));
   Print("1 punto x 1 lotto = ", DoubleToString(g_ptValue, 4), " ", AccountInfoString(ACCOUNT_CURRENCY),
         " | ATR(", ATR_Period, ") mediano = ", DoubleToString(g_atrMed, 1), " pt");
   Print("TP richiesto = ", InpTPpoints, " pt = ", DoubleToString(InpTPpoints * g_pt, _Digits),
         " in prezzo = ", DoubleToString(g_atrMed > 0 ? InpTPpoints / g_atrMed : 0, 1), " x ATR");

//--- guardia timeframe
   if(InpTF >= PERIOD_D1)
      Print("!!! ATTENZIONE: TF ", EnumToString(InpTF), " - ogni barra ha timestamp 00:00. "
            "L'analisi per ora e per minuto sara' priva di significato. Usa M1/M5/M15.");
   Print("Barre analizzate: ", g_bars, " da ", g_r[0].time, " a ", g_r[g_bars-1].time);

//--- scansione
   int minBars = MathMax(MathMax(EmaPeriod, VolAvgPeriod), MathMax(ATR_Period, SR_Lookback)) + 2;
   int cap = 8192;
   ArrayResize(s_time, cap); ArrayResize(s_dir, cap); ArrayResize(s_tTP, cap);
   ArrayResize(s_maeAtTP, cap); ArrayResize(s_maeFull, cap); ArrayResize(s_mfe, cap);
   ArrayResize(s_endPts, cap); ArrayResize(s_cost, cap); ArrayResize(s_delta, cap); ArrayResize(s_tSL, cap * g_nSL);

   int lastB = -1000000, lastS = -1000000;
   uint t0 = GetTickCount();

   for(int i = minBars; i < g_bars - InpEntryDelay - 1; i++)
     {
      if(g_r[i].time < InpFrom || g_r[i].time > InpTo) continue;
      double dlt;
      int dir = EvalSignal(i, dlt);
      if(dir == 0) continue;
      if(InpInvertSignals) dir = -dir;
      if(InpOnlyDir != 0 && dir != InpOnlyDir) continue;
      if(InpCooldownBars > 0)
        {
         if(dir > 0 && i - lastB < InpCooldownBars) continue;
         if(dir < 0 && i - lastS < InpCooldownBars) continue;
        }
      if(dir > 0) lastB = i; else lastS = i;

      int eb = i + InpEntryDelay;
      if(eb >= g_bars) break;

      double cost = (InpCostPoints > 0 ? InpCostPoints : (double)g_r[eb].spread) + InpExtraCostPts;
      double E = (dir > 0) ? g_r[eb].open + cost * g_pt : g_r[eb].open - cost * g_pt;

      if(g_n >= cap)
        {
         cap = g_n + 8192;
         ArrayResize(s_time, cap); ArrayResize(s_dir, cap); ArrayResize(s_tTP, cap);
         ArrayResize(s_maeAtTP, cap); ArrayResize(s_maeFull, cap); ArrayResize(s_mfe, cap);
         ArrayResize(s_endPts, cap); ArrayResize(s_cost, cap); ArrayResize(s_delta, cap); ArrayResize(s_tSL, cap * g_nSL);
        }

      //--- walk forward
      int base = g_n * g_nSL;
      for(int k = 0; k < g_nSL; k++) s_tSL[base + k] = BIG;
      double mfe = 0, mae = 0, maeAtTP = -1;
      int tTP = BIG, pa = 0, last = eb;
      int endB = MathMin(eb + InpMaxBars, g_bars - 1);

      for(int k = eb; k <= endB; k++)
        {
         double fav, adv;
         if(dir > 0) { fav = (g_r[k].high - E) / g_pt; adv = (E - g_r[k].low)  / g_pt; }
         else        { fav = (E - g_r[k].low)  / g_pt; adv = (g_r[k].high - E) / g_pt; }
         if(fav > mfe) mfe = fav;
         if(adv > mae) mae = adv;
         while(pa < g_nSL && mae >= (double)g_sl[pa]) { s_tSL[base + pa] = k - eb; pa++; }
         if(tTP == BIG && mfe >= (double)InpTPpoints) { tTP = k - eb; maeAtTP = mae; }
         last = k;
         if(tTP != BIG && pa >= g_nSL) break;
        }

      s_time[g_n]    = g_r[i].time + InpTimeOffsetH * 3600;
      s_dir[g_n]     = dir;
      s_tTP[g_n]     = tTP;
      s_maeAtTP[g_n] = maeAtTP;
      s_maeFull[g_n] = mae;
      s_mfe[g_n]     = mfe;
      s_cost[g_n]    = cost;
      s_delta[g_n]   = dlt;
      s_endPts[g_n]  = (dir > 0) ? (g_r[last].close - E) / g_pt : (E - g_r[last].close) / g_pt;
      g_n++;
     }

   Print("Segnali: ", g_n, " | scansione ", (GetTickCount() - t0) / 1000.0, " s");
   if(g_n == 0) { Print("Nessun segnale nel periodo."); return; }

   WriteReport();
   if(InpExportCSV) WriteCSV();

   IndicatorRelease(hE); IndicatorRelease(hA);
   if(hD != INVALID_HANDLE) IndicatorRelease(hD);
  }

//+------------------------------------------------------------------+
double Pctl(double &a[], int n, double p)
  {
   if(n <= 0) return 0;
   int idx = (int)MathRound(p * (n - 1));
   idx = MathMax(0, MathMin(n - 1, idx));
   return a[idx];
  }

//+------------------------------------------------------------------+
void HitRow(string &html, string label, int n, int hits, double sumBars, double sumSpread = -1)
  {
   double hr = (n > 0) ? 100.0 * hits / n : 0;
   double ab = (hits > 0) ? sumBars / hits : 0;
   // errore standard della proporzione -> quanto e' affidabile
   double se = (n > 0) ? 100.0 * MathSqrt((hr/100.0) * (1 - hr/100.0) / n) : 0;
   string cls = (n < InpMinPerBucket) ? " class='thin'" : "";
   string sp  = "";
   if(sumSpread >= 0 && n > 0)
     {
      double av = sumSpread / n;
      sp = StringFormat("<td>%.0f</td><td style='color:%s'>%.1f%%</td>", av,
                        (InpTPpoints > 0 && av/InpTPpoints > 0.15) ? "#bf616a" : "#7b8794",
                        InpTPpoints > 0 ? 100.0*av/InpTPpoints : 0);
     }
   html += StringFormat("<tr%s><td>%s</td><td>%d</td><td>%d</td><td><b>%.1f%%</b></td><td>&plusmn;%.1f</td><td>%.0f</td>%s</tr>\n",
                        cls, label, n, hits, hr, se, ab, sp);
  }

//+------------------------------------------------------------------+
void WriteReport()
  {
   int    hN[24], hH[24];  double hB[24];
   int    mN[60], mH[60];  double mB[60];
   int    dN[7],  dH[7];   double dB[7];
   int    qN[1440], qH[1440];
   double hSpread[24]; double qSpread[1440];
   ArrayInitialize(hN,0); ArrayInitialize(hH,0); ArrayInitialize(hB,0);
   ArrayInitialize(mN,0); ArrayInitialize(mH,0); ArrayInitialize(mB,0);
   ArrayInitialize(dN,0); ArrayInitialize(dH,0); ArrayInitialize(dB,0);
   ArrayInitialize(qN,0); ArrayInitialize(qH,0);
   ArrayInitialize(hSpread,0); ArrayInitialize(qSpread,0);

   int totHit = 0, nBuy = 0, nSell = 0, hBuy = 0, hSell = 0;
   double sumBars = 0;
   double maeWin[]; int nWin = 0; ArrayResize(maeWin, g_n);
   double barsArr[]; int nBA = 0; ArrayResize(barsArr, g_n);

   for(int s = 0; s < g_n; s++)
     {
      MqlDateTime dt; TimeToStruct(s_time[s], dt);
      bool hit = (s_tTP[s] != BIG);
      double bt = hit ? (double)s_tTP[s] : 0;

      int q = dt.hour * 60 + dt.min;
      hN[dt.hour]++; mN[dt.min]++; dN[dt.day_of_week]++; qN[q]++;
      hSpread[dt.hour] += s_cost[s]; qSpread[q] += s_cost[s];
      if(hit)
        {
         totHit++; sumBars += bt;
         hH[dt.hour]++; mH[dt.min]++; dH[dt.day_of_week]++; qH[q]++;
         hB[dt.hour] += bt; mB[dt.min] += bt; dB[dt.day_of_week] += bt;
         maeWin[nWin++] = s_maeAtTP[s];
         barsArr[nBA++] = bt;
        }
      if(s_dir[s] > 0) { nBuy++;  if(hit) hBuy++;  }
      else             { nSell++; if(hit) hSell++; }
     }
   if(nWin > 0) { ArrayResize(maeWin, nWin); ArraySort(maeWin); }
   if(nBA  > 0) { ArrayResize(barsArr, nBA); ArraySort(barsArr); }

   double hrTot = 100.0 * totHit / g_n;
   string dow[7] = {"Domenica","Lunedi","Martedi","Mercoledi","Giovedi","Venerdi","Sabato"};

   string h = "";
   h += "<!doctype html><html><head><meta charset='utf-8'><title>SyntheticDelta HitRate</title><style>";
   h += "body{background:#14161a;color:#d8dee9;font:13px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;margin:24px}";
   h += "h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;margin:26px 0 8px;color:#88c0d0;border-bottom:1px solid #2e3440;padding-bottom:4px}";
   h += "table{border-collapse:collapse;margin:8px 0;font-size:12px}td,th{border:1px solid #2e3440;padding:3px 9px;text-align:right}";
   h += "th{background:#1e222a;color:#8fbcbb}td:first-child,th:first-child{text-align:left}";
   h += ".thin td{color:#4c566a;font-style:italic}";
   h += ".kpi{display:inline-block;background:#1e222a;border:1px solid #2e3440;border-radius:6px;padding:10px 16px;margin:4px 8px 4px 0;min-width:120px;font-size:11px;color:#7b8794}";
   h += ".kpi b{display:block;font-size:20px;color:#eceff4}";
   h += ".note{background:#1e222a;border-left:3px solid #ebcb8b;padding:10px 14px;margin:12px 0;color:#c8ccd4}";
   h += "</style></head><body>";

   h += "<h1>Il prezzo raggiunge " + IntegerToString(InpTPpoints) + " punti dopo il segnale?</h1>";
   h += "<div style='color:#7b8794'>" + _Symbol + " " + EnumToString(InpTF)
      + " | orizzonte " + IntegerToString(InpMaxBars) + " barre | "
      + TimeToString(s_time[0], TIME_DATE) + " &rarr; " + TimeToString(s_time[g_n-1], TIME_DATE)
      + " | offset ore " + IntegerToString(InpTimeOffsetH) + "</div>";

   h += "<h2>Dati analizzati</h2><table>";
   h += StringFormat("<tr><th>Timeframe</th><td>%s</td><th>Barre</th><td>%d</td></tr>",
                     EnumToString(InpTF), g_bars);
   h += StringFormat("<tr><th>Prima barra</th><td>%s</td><th>Ultima barra</th><td>%s</td></tr>",
                     TimeToString(g_r[0].time), TimeToString(g_r[g_bars-1].time));
   h += StringFormat("<tr><th>Digits / Point</th><td>%d / %s</td><th>1 pt x 1 lotto</th><td>%.4f %s</td></tr>",
                     _Digits, DoubleToString(g_pt,8), g_ptValue, AccountInfoString(ACCOUNT_CURRENCY));
   h += StringFormat("<tr><th>ATR(%d) mediano</th><td>%.0f pt</td><th>TP richiesto</th><td>%d pt = %s = %.1f x ATR</td></tr>",
                     ATR_Period, g_atrMed, InpTPpoints, DoubleToString(InpTPpoints*g_pt,_Digits),
                     g_atrMed > 0 ? InpTPpoints/g_atrMed : 0);
   h += "</table>";

   h += "<h2>Risposta</h2>";
   h += StringFormat("<div class='kpi'><span>Segnali</span><b>%d</b></div>", g_n);
   h += StringFormat("<div class='kpi'><span>Raggiungono il TP</span><b>%.1f%%</b>%d su %d</div>", hrTot, totHit, g_n);
   h += StringFormat("<div class='kpi'><span>Barre mediane al TP</span><b>%.0f</b>%s</div>",
                     Pctl(barsArr, nBA, 0.50), (InpTF==PERIOD_M1 ? "minuti" : "barre"));
   h += StringFormat("<div class='kpi'><span>TP in prezzo</span><b>%s</b>%.1f x ATR</div>",
                     DoubleToString(InpTPpoints * g_pt, _Digits), g_atrMed > 0 ? InpTPpoints / g_atrMed : 0);
   h += StringFormat("<div class='kpi'><span>TP per 1 lotto</span><b>%.0f %s</b></div>",
                     InpTPpoints * g_ptValue, AccountInfoString(ACCOUNT_CURRENCY));
     {
      double totCost = 0;
      for(int s2 = 0; s2 < g_n; s2++) totCost += s_cost[s2];
      double avc = totCost / g_n;
      h += StringFormat("<div class='kpi'><span>Costo medio ingresso</span><b>%.0f pt</b>%.1f%% del TP</div>",
                        avc, InpTPpoints > 0 ? 100.0*avc/InpTPpoints : 0);
     }
   h += StringFormat("<div class='kpi'><span>Buy hit / Sell hit</span><b>%.1f%% / %.1f%%</b>%d / %d segnali</div>",
                     nBuy > 0 ? 100.0*hBuy/nBuy : 0, nSell > 0 ? 100.0*hSell/nSell : 0, nBuy, nSell);

   h += "<div class='note'><b>&plusmn;</b> e' l'errore standard della percentuale. Se due ore differiscono di meno di "
        "2 volte il loro &plusmn;, <b>non sono diverse</b>: e' rumore. Le righe grigie hanno meno di "
        + IntegerToString(InpMinPerBucket) + " segnali e vanno ignorate.</div>";

//--- curva di raggiungimento: quanto in fretta arriva il target
   h += "<h2>In quanto tempo arriva il target? (curva cumulativa)</h2>";
   h += "<div class='note'>Serve a scegliere l'orizzonte. Un target raggiunto dopo 200 barre <b>non e' uno scalp</b>: "
        "e' un trade intraday che hai contato come successo. Cerca il punto in cui la curva si appiattisce: "
        "oltre quello stai solo aspettando, non guadagnando.</div>";
   h += "<table><tr><th>Entro N barre</th><th>Hit cumulati</th><th>% sul totale segnali</th><th>% degli hit totali</th><th>Guadagno marginale</th></tr>";
     {
      int hz[10] = {1,3,5,10,15,30,60,120,240,600};
      double prevPct = 0;
      for(int k = 0; k < 10; k++)
        {
         if(hz[k] > InpMaxBars && k > 0 && hz[k-1] >= InpMaxBars) break;
         int c = 0;
         for(int s2 = 0; s2 < g_n; s2++) if(s_tTP[s2] != BIG && s_tTP[s2] < hz[k]) c++;
         double pct = 100.0 * c / g_n;
         h += StringFormat("<tr><td>%d</td><td>%d</td><td><b>%.1f%%</b></td><td>%.1f%%</td><td>%+.1f pp</td></tr>",
                           MathMin(hz[k], InpMaxBars), c, pct,
                           totHit > 0 ? 100.0*c/totHit : 0, pct - prevPct);
         prevPct = pct;
         if(hz[k] >= InpMaxBars) break;
        }
     }
   h += "</table>";

   h += "<div class='note'>La colonna <b>costo</b> e' lo spread medio effettivamente pagato in quell'ora. "
        "In rosso quando supera il 15% del target: in quelle ore il broker si prende una fetta del tuo edge "
        "prima ancora che il trade inizi.</div>";
   h += "<table><tr><th>Ora</th><th>Segnali</th><th>Hit</th><th>Hit rate</th><th>&plusmn;</th><th>Barre medie al TP</th>"
        "<th>Costo medio (pt)</th><th>% del TP</th></tr>";
   for(int i = 0; i < 24; i++) HitRow(h, StringFormat("%02d:00", i), hN[i], hH[i], hB[i], hSpread[i]);
   h += "</table>";

   h += "<h2>Per GIORNO</h2><table><tr><th>Giorno</th><th>Segnali</th><th>Hit</th><th>Hit rate</th><th>&plusmn;</th><th>Barre medie</th></tr>";
   for(int i = 0; i < 7; i++) if(dN[i] > 0) HitRow(h, dow[i], dN[i], dH[i], dB[i]);
   h += "</table>";

   h += "<h2>Per MINUTO dell'ora</h2>";
   h += "<div class='note'>60 bucket sullo stesso campione: qualunque picco qui e' <b>quasi certamente rumore</b>. "
        "Guardala solo per anomalie strutturali (rollover, apertura sessione, news schedulate).</div>";
   h += "<table><tr><th>Minuto</th><th>Segnali</th><th>Hit</th><th>Hit rate</th><th>&plusmn;</th><th>Barre medie</th></tr>";
   for(int i = 0; i < 60; i++) HitRow(h, StringFormat(":%02d", i), mN[i], mH[i], mB[i]);
   h += "</table>";

//--- slot orari HH:MM
     {
      int distinctH = 0, distinctQ = 0;
      for(int i = 0; i < 24; i++)   if(hN[i] > 0) distinctH++;
      for(int i = 0; i < 1440; i++) if(qN[i] > 0) distinctQ++;

      h += "<h2>Slot orari HH:MM &mdash; classifica</h2>";
      if(distinctH <= 1)
        {
         h += "<div class='note' style='border-color:#bf616a'><b>DATI NON UTILIZZABILI PER L'ANALISI ORARIA.</b> "
              "Tutti i segnali cadono in una sola ora (" + IntegerToString(distinctH) + " ora distinta, "
              + IntegerToString(distinctQ) + " slot HH:MM distinti). "
              "Quasi certamente stai analizzando un timeframe giornaliero o superiore: imposta <b>InpTF = PERIOD_M1</b>.</div>";
        }
      else
        {
         h += StringFormat("<div class='note'>%d ore distinte, %d slot HH:MM distinti popolati. "
              "Sono mostrati solo gli slot con almeno %d segnali. <b>Attenzione al multiple testing:</b> "
              "su %d slot testati, per puro caso ~%d supereranno il 95%% di confidenza. "
              "Uno slot conta solo se (a) ha molti segnali, (b) e' affiancato da slot vicini con risultati simili, "
              "(c) ha una spiegazione strutturale (apertura sessione, news, rollover).</div>",
              distinctH, distinctQ, InpMinPerBucket, distinctQ, (int)MathRound(distinctQ*0.05));

         //--- ordina per hit rate
         int    idx[]; double key[]; int nq = 0;
         ArrayResize(idx, 1440); ArrayResize(key, 1440);
         for(int i = 0; i < 1440; i++)
            if(qN[i] >= InpMinPerBucket) { idx[nq] = i; key[nq] = 100.0*qH[i]/qN[i]; nq++; }
         for(int a = 0; a < nq - 1; a++)
            for(int b2 = a + 1; b2 < nq; b2++)
               if(key[b2] > key[a])
                 { double tk = key[a]; key[a] = key[b2]; key[b2] = tk;
                   int ti = idx[a]; idx[a] = idx[b2]; idx[b2] = ti; }

         if(nq == 0)
            h += "<div class='note'>Nessuno slot HH:MM raggiunge " + IntegerToString(InpMinPerBucket)
               + " segnali. Allunga il periodo, abbassa InpMinPerBucket, oppure aggrega su bucket piu' larghi.</div>";
         else
           {
            int show = MathMin(nq, 30);
            h += StringFormat("<h3 style='color:#a3be8c;font-size:13px'>Migliori %d slot (su %d qualificati)</h3>", show, nq);
            h += "<table><tr><th>Slot</th><th>Segnali</th><th>Hit</th><th>Hit rate</th><th>&plusmn;</th><th>Scarto vs media</th><th>Costo medio</th></tr>";
            for(int k = 0; k < show; k++)
              {
               int i = idx[k];
               double hr = 100.0*qH[i]/qN[i];
               double se = 100.0*MathSqrt((hr/100.0)*(1-hr/100.0)/qN[i]);
               double z  = (se > 0) ? (hr - hrTot)/se : 0;
               h += StringFormat("<tr><td>%02d:%02d</td><td>%d</td><td>%d</td><td><b>%.1f%%</b></td>"
                                 "<td>&plusmn;%.1f</td><td style='color:%s'>%+.1f sigma</td><td>%.0f</td></tr>",
                                 i/60, i%60, qN[i], qH[i], hr, se,
                                 MathAbs(z) > 2.5 ? "#ebcb8b" : "#7b8794", z, qSpread[i]/qN[i]);
              }
            h += "</table>";
            h += "<h3 style='color:#bf616a;font-size:13px'>Peggiori 15 slot</h3>";
            h += "<table><tr><th>Slot</th><th>Segnali</th><th>Hit</th><th>Hit rate</th><th>&plusmn;</th><th>Scarto vs media</th><th>Costo medio</th></tr>";
            for(int k = MathMax(0, nq - 15); k < nq; k++)
              {
               int i = idx[k];
               double hr = 100.0*qH[i]/qN[i];
               double se = 100.0*MathSqrt((hr/100.0)*(1-hr/100.0)/qN[i]);
               double z  = (se > 0) ? (hr - hrTot)/se : 0;
               h += StringFormat("<tr><td>%02d:%02d</td><td>%d</td><td>%d</td><td><b>%.1f%%</b></td>"
                                 "<td>&plusmn;%.1f</td><td style='color:%s'>%+.1f sigma</td><td>%.0f</td></tr>",
                                 i/60, i%60, qN[i], qH[i], hr, se,
                                 MathAbs(z) > 2.5 ? "#ebcb8b" : "#7b8794", z, qSpread[i]/qN[i]);
              }
            h += "</table>";
           }
        }
     }

//--- MAE sui vincenti: quanto SL serve per non farsi buttare fuori
   h += "<h2>Quanto SL serve? Sofferenza massima PRIMA di toccare il TP</h2>";
   h += "<div class='note'>Calcolato solo sui " + IntegerToString(nWin) + " segnali che il TP lo raggiungono. "
        "Uno SL sotto il 90&deg; percentile ti butta fuori da almeno il 10% dei trade che sarebbero andati a target.</div>";
   h += "<table><tr><th>Percentile</th><th>MAE (punti)</th><th>in prezzo</th><th>x ATR</th></tr>";
   double pc[7] = {0.50, 0.75, 0.90, 0.95, 0.99, 1.00, 0.25};
   string pn[7] = {"50&deg; (mediana)","75&deg;","90&deg;","95&deg;","99&deg;","massimo","25&deg;"};
   int order[7] = {6, 0, 1, 2, 3, 4, 5};
   for(int k = 0; k < 7; k++)
     {
      int o = order[k];
      double v = Pctl(maeWin, nWin, pc[o]);
      h += StringFormat("<tr><td>%s</td><td>%.0f</td><td>%s</td><td>%.1f</td></tr>",
                        pn[o], v, DoubleToString(v * g_pt, _Digits), g_atrMed > 0 ? v / g_atrMed : 0);
     }
   h += "</table>";

//--- sweep SL
   h += "<h2>Sweep Stop Loss (TP fisso a " + IntegerToString(InpTPpoints) + " punti)</h2>";
   h += "<table><tr><th>SL</th><th>x ATR</th><th>R (TP/SL)</th><th>TP prima</th><th>SL prima</th><th>Scaduti</th>"
        "<th>Win %</th><th>Expectancy pt</th><th>Net pt</th><th>Net " + AccountInfoString(ACCOUNT_CURRENCY) + "/lotto</th></tr>";
   double bestExp = -DBL_MAX; int bestK = -1;
   for(int k = 0; k < g_nSL; k++)
     {
      int wTP = 0, wSL = 0, wTO = 0; double net = 0;
      for(int s = 0; s < g_n; s++)
        {
         int ta = s_tSL[s * g_nSL + k], tf = s_tTP[s];
         if(tf == BIG && ta == BIG) { wTO++; net += s_endPts[s]; }
         else if(ta <= tf)          { wSL++; net -= (double)g_sl[k]; }
         else                       { wTP++; net += (double)InpTPpoints; }
        }
      double expc = net / g_n;
      if(expc > bestExp) { bestExp = expc; bestK = k; }
      h += StringFormat("<tr><td>%d</td><td>%.1f</td><td>%.2f</td><td>%d</td><td>%d</td><td>%d</td>"
                        "<td>%.1f%%</td><td style='color:%s'><b>%.1f</b></td><td>%.0f</td><td>%.0f</td></tr>",
                        g_sl[k], g_atrMed > 0 ? g_sl[k]/g_atrMed : 0, (double)InpTPpoints/g_sl[k],
                        wTP, wSL, wTO, 100.0*wTP/g_n,
                        expc > 0 ? "#a3be8c" : "#bf616a", expc, net, net * g_ptValue);
     }
   h += "</table>";
   if(bestK >= 0)
      h += StringFormat("<div class='note'>Migliore in-sample: <b>SL %d / TP %d</b> (R = %.2f), expectancy %.1f pt per segnale. "
                        "Attenzione: e' il massimo su questo campione. Fidati solo se le righe vicine hanno valori simili "
                        "(<b>plateau</b>); se e' un picco isolato circondato da valori negativi, e' overfitting.</div>",
                        g_sl[bestK], InpTPpoints, (double)InpTPpoints/g_sl[bestK], bestExp);

//--- ============================================================
//    CURVA EDGE vs SOGLIA  (un solo run, tutte le soglie)
//--- ============================================================
   if(InpThresholdScan)
     {
      int refK = -1;
      if(InpRefSL > 0)
        { int bd = BIG;
          for(int k = 0; k < g_nSL; k++)
             if(MathAbs(g_sl[k] - InpRefSL) < bd) { bd = MathAbs(g_sl[k] - InpRefSL); refK = k; } }
      else refK = bestK;
      int SLr = (refK >= 0) ? g_sl[refK] : InpTPpoints;

      //--- giorni di trading coperti, per normalizzare la frequenza
      int nDays = 0;
        {
         long prev = -1;
         for(int s2 = 0; s2 < g_n; s2++)
           {
            long day = (long)s_time[s2] / 86400;
            if(day != prev) { nDays++; prev = day; }
           }
         if(nDays < 1) nDays = 1;
        }

      h += "<h2>Curva edge vs soglia &mdash; il delta contiene informazione?</h2>";
      h += "<div class='note'><b>Come si legge, in una riga:</b> se alzando la soglia l'edge <b>cresce in modo "
           "monotono</b>, il delta misura qualcosa di reale e vale la pena filtrare. Se resta piatto o oscilla "
           "senza direzione, il delta e' rumore e nessuna soglia lo salvera'.<br><br>"
           "<b>solo-fav</b> = tocca il TP senza mai toccare la barriera opposta. <b>solo-contro</b> = viceversa. "
           "Sono mutuamente esclusivi, quindi il loro confronto e' un test pulito, indipendente da ipotesi sul "
           "tie-break. <b>z</b> = significativita' della differenza: sotto |2| non e' distinguibile da zero, e "
           "testando " + IntegerToString(InpScanSteps) + " soglie ci si aspetta qualche |z| vicino a 2 per puro caso.</div>";

      h += "<table><tr><th>Soglia |delta|</th><th>Segnali</th><th>al giorno</th><th>% del totale</th>"
           "<th>solo-fav</th><th>solo-contro</th><th>edge (pp)</th><th>z</th>"
           "<th>Exp pt (SL " + IntegerToString(SLr) + ")</th><th>t</th></tr>";

      int nst = MathMax(InpScanSteps, 2);
      for(int k = 0; k < nst; k++)
        {
         double thr = InpScanMinDelta + (InpScanMaxDelta - InpScanMinDelta) * k / (nst - 1.0);
         int n = 0, favOnly = 0, advOnly = 0;
         double sum = 0, sum2 = 0;
         for(int s2 = 0; s2 < g_n; s2++)
           {
            if(MathAbs(s_delta[s2]) < thr) continue;
            n++;
            bool fav = (s_tTP[s2] != BIG);
            bool adv = (s_maeFull[s2] >= (double)InpTPpoints);
            if(fav && !adv) favOnly++;
            if(adv && !fav) advOnly++;
            double p;
            if(refK >= 0)
              {
               int ta = s_tSL[s2 * g_nSL + refK], tf = s_tTP[s2];
               if(tf == BIG && ta == BIG) p = s_endPts[s2];
               else if(ta <= tf)          p = -(double)SLr;
               else                       p = (double)InpTPpoints;
              }
            else p = s_endPts[s2];
            sum += p; sum2 += p*p;
           }
         if(n == 0) continue;
         double mean = sum/n;
         double var  = (n > 1) ? (sum2 - n*mean*mean)/(n-1) : 0;
         double sd   = (var > 0) ? MathSqrt(var) : 0;
         double tst  = (sd > 0 && n > 1) ? mean/(sd/MathSqrt((double)n)) : 0;
         double z    = (favOnly + advOnly > 0) ? (favOnly - advOnly)/MathSqrt((double)(favOnly + advOnly)) : 0;
         double edge = 100.0*(favOnly - advOnly)/n;
         string cls  = (n < InpMinPerBucket) ? " class='thin'" : "";
         h += StringFormat("<tr%s><td><b>%.3f</b></td><td>%d</td><td>%.1f</td><td>%.1f%%</td>"
                           "<td>%.1f%%</td><td>%.1f%%</td><td style='color:%s'><b>%+.1f</b></td>"
                           "<td style='color:%s'>%+.2f</td><td style='color:%s'>%.1f</td><td>%.2f</td></tr>",
                           cls, thr, n, (double)n/nDays, 100.0*n/g_n,
                           100.0*favOnly/n, 100.0*advOnly/n,
                           edge > 0 ? "#a3be8c" : "#bf616a", edge,
                           MathAbs(z) > 2.0 ? "#ebcb8b" : "#7b8794", z,
                           mean > 0 ? "#a3be8c" : "#bf616a", mean, tst);
        }
      h += "</table>";

      //--- decili di |delta|: la stessa domanda, a campioni di uguale dimensione
      h += "<h3 style='color:#88c0d0;font-size:13px'>Stessa domanda per decili di |delta| (campioni di pari numerosita')</h3>";
      h += "<div class='note'>Le soglie cumulative sopra condividono i dati fra righe, quindi le righe non sono "
           "indipendenti. Qui invece ogni decile e' un gruppo <b>disgiunto</b> di uguale dimensione: se il delta "
           "informa, l'edge deve salire dal decile 1 al decile 10.</div>";
        {
         double sorted[]; ArrayResize(sorted, g_n);
         for(int s2 = 0; s2 < g_n; s2++) sorted[s2] = MathAbs(s_delta[s2]);
         ArraySort(sorted);
         h += "<table><tr><th>Decile |delta|</th><th>Intervallo</th><th>Segnali</th>"
              "<th>solo-fav</th><th>solo-contro</th><th>edge (pp)</th><th>z</th></tr>";
         for(int d2 = 0; d2 < 10; d2++)
           {
            double lo = sorted[(int)((d2/10.0)*(g_n-1))];
            double hi = sorted[(int)(((d2+1)/10.0)*(g_n-1))];
            int n = 0, fo = 0, ao = 0;
            for(int s2 = 0; s2 < g_n; s2++)
              {
               double a = MathAbs(s_delta[s2]);
               if(a < lo || (d2 < 9 && a >= hi)) continue;
               n++;
               bool fav = (s_tTP[s2] != BIG);
               bool adv = (s_maeFull[s2] >= (double)InpTPpoints);
               if(fav && !adv) fo++;
               if(adv && !fav) ao++;
              }
            if(n == 0) continue;
            double z = (fo + ao > 0) ? (fo - ao)/MathSqrt((double)(fo + ao)) : 0;
            double edge = 100.0*(fo - ao)/n;
            h += StringFormat("<tr><td>%d</td><td>%.3f &ndash; %.3f</td><td>%d</td><td>%.1f%%</td><td>%.1f%%</td>"
                              "<td style='color:%s'><b>%+.1f</b></td><td style='color:%s'>%+.2f</td></tr>",
                              d2+1, lo, hi, n, 100.0*fo/n, 100.0*ao/n,
                              edge > 0 ? "#a3be8c" : "#bf616a", edge,
                              MathAbs(z) > 2.0 ? "#ebcb8b" : "#7b8794", z);
           }
         h += "</table>";
        }
     }

//--- ============================================================
//    CLASSIFICA ORARI PER EXPECTANCY NETTA (non solo hit rate)
//--- ============================================================
     {
      int useK = -1;
      if(InpRefSL > 0)
        { int bd = BIG;
          for(int k = 0; k < g_nSL; k++)
             if(MathAbs(g_sl[k] - InpRefSL) < bd) { bd = MathAbs(g_sl[k] - InpRefSL); useK = k; } }
      else useK = bestK;

      if(useK >= 0)
        {
         int SLref = g_sl[useK];
         h += StringFormat("<h2>Classifica ORARI per expectancy netta (TP %d / SL %d)</h2>",
                           InpTPpoints, SLref);
         h += "<div class='note'>Questa e' la tabella che risponde a <b>&quot;in quali orari conviene operare&quot;</b>. "
              "L'hit rate da solo non basta: un'ora con hit rate alto ma spread doppio puo' rendere meno di una con "
              "hit rate mediocre e spread stretto. Qui il costo e' gia' dentro. "
              "<b>t-stat</b> sotto 2 = non distinguibile da zero, qualunque sia l'expectancy.</div>";

         //--- per ora
         double eSum[24], eSum2[24]; int eN[24];
         ArrayInitialize(eSum,0); ArrayInitialize(eSum2,0); ArrayInitialize(eN,0);
         //--- per bucket fine
         int nb = 1440 / MathMax(InpBucketMin, 1);
         double bSum[]; double bSum2[]; int bN[];
         ArrayResize(bSum, nb); ArrayResize(bSum2, nb); ArrayResize(bN, nb);
         ArrayInitialize(bSum,0); ArrayInitialize(bSum2,0); ArrayInitialize(bN,0);

         for(int s2 = 0; s2 < g_n; s2++)
           {
            int ta = s_tSL[s2 * g_nSL + useK], tf = s_tTP[s2];
            double p;
            if(tf == BIG && ta == BIG) p = s_endPts[s2];
            else if(ta <= tf)          p = -(double)SLref;
            else                       p = (double)InpTPpoints;

            MqlDateTime dt; TimeToStruct(s_time[s2], dt);
            eN[dt.hour]++; eSum[dt.hour] += p; eSum2[dt.hour] += p*p;
            int b = (dt.hour * 60 + dt.min) / MathMax(InpBucketMin, 1);
            if(b >= 0 && b < nb) { bN[b]++; bSum[b] += p; bSum2[b] += p*p; }
           }

         //--- ordina le ore per expectancy
         int oi[24]; double ok[24];
         for(int i = 0; i < 24; i++) { oi[i] = i; ok[i] = (eN[i] > 0) ? eSum[i]/eN[i] : -DBL_MAX; }
         for(int a = 0; a < 23; a++)
            for(int b3 = a + 1; b3 < 24; b3++)
               if(ok[b3] > ok[a])
                 { double t1 = ok[a]; ok[a] = ok[b3]; ok[b3] = t1;
                   int t2 = oi[a]; oi[a] = oi[b3]; oi[b3] = t2; }

         h += "<table><tr><th>#</th><th>Ora</th><th>Segnali</th><th>Expectancy pt</th><th>Net pt</th>"
              "<th>Net " + AccountInfoString(ACCOUNT_CURRENCY) + "/lotto</th><th>t-stat</th></tr>";
         for(int k = 0; k < 24; k++)
           {
            int i = oi[k];
            if(eN[i] == 0) continue;
            double mean = eSum[i]/eN[i];
            double var  = (eN[i] > 1) ? (eSum2[i] - eN[i]*mean*mean)/(eN[i]-1) : 0;
            double sd   = (var > 0) ? MathSqrt(var) : 0;
            double tst  = (sd > 0 && eN[i] > 1) ? mean/(sd/MathSqrt((double)eN[i])) : 0;
            string cls  = (eN[i] < InpMinPerBucket) ? " class='thin'" : "";
            h += StringFormat("<tr%s><td>%d</td><td>%02d:00</td><td>%d</td>"
                              "<td style='color:%s'><b>%.1f</b></td><td>%.0f</td><td>%.0f</td>"
                              "<td style='color:%s'>%.2f</td></tr>",
                              cls, k+1, i, eN[i],
                              mean > 0 ? "#a3be8c" : "#bf616a", mean, eSum[i], eSum[i]*g_ptValue,
                              MathAbs(tst) > 2.0 ? "#ebcb8b" : "#7b8794", tst);
           }
         h += "</table>";

         //--- bucket fine, solo i migliori
         int bi2[]; double bk[]; int nbq = 0;
         ArrayResize(bi2, nb); ArrayResize(bk, nb);
         for(int i = 0; i < nb; i++)
            if(bN[i] >= InpMinPerBucket) { bi2[nbq] = i; bk[nbq] = bSum[i]/bN[i]; nbq++; }
         for(int a = 0; a < nbq - 1; a++)
            for(int b3 = a + 1; b3 < nbq; b3++)
               if(bk[b3] > bk[a])
                 { double t1 = bk[a]; bk[a] = bk[b3]; bk[b3] = t1;
                   int t2 = bi2[a]; bi2[a] = bi2[b3]; bi2[b3] = t2; }

         h += StringFormat("<h2>Finestre da %d minuti &mdash; migliori e peggiori</h2>", InpBucketMin);
         h += StringFormat("<div class='note'>Bucket da %d minuti: compromesso fra risoluzione e rumore. "
              "Molto piu' affidabile della tabella HH:MM al minuto singolo, che con 1440 celle produce "
              "falsi positivi a raffica. Una finestra e' credibile se anche le finestre <b>adiacenti</b> "
              "vanno nella stessa direzione.</div>", InpBucketMin);
         if(nbq == 0)
            h += "<div class='note'>Nessuna finestra raggiunge " + IntegerToString(InpMinPerBucket) + " segnali.</div>";
         else
           {
            h += "<table><tr><th>Finestra</th><th>Segnali</th><th>Expectancy pt</th><th>Net pt</th><th>t-stat</th></tr>";
            int show2 = MathMin(nbq, 12);
            for(int k = 0; k < show2; k++)
              {
               int i = bi2[k]; int st = i * InpBucketMin, en = st + InpBucketMin - 1;
               double mean = bSum[i]/bN[i];
               double var  = (bN[i] > 1) ? (bSum2[i] - bN[i]*mean*mean)/(bN[i]-1) : 0;
               double sd   = (var > 0) ? MathSqrt(var) : 0;
               double tst  = (sd > 0 && bN[i] > 1) ? mean/(sd/MathSqrt((double)bN[i])) : 0;
               h += StringFormat("<tr><td>%02d:%02d - %02d:%02d</td><td>%d</td><td style='color:#a3be8c'><b>%.1f</b></td>"
                                 "<td>%.0f</td><td style='color:%s'>%.2f</td></tr>",
                                 st/60, st%60, en/60, en%60, bN[i], mean, bSum[i],
                                 MathAbs(tst) > 2.0 ? "#ebcb8b" : "#7b8794", tst);
              }
            for(int k = MathMax(show2, nbq - 6); k < nbq; k++)
              {
               int i = bi2[k]; int st = i * InpBucketMin, en = st + InpBucketMin - 1;
               double mean = bSum[i]/bN[i];
               double var  = (bN[i] > 1) ? (bSum2[i] - bN[i]*mean*mean)/(bN[i]-1) : 0;
               double sd   = (var > 0) ? MathSqrt(var) : 0;
               double tst  = (sd > 0 && bN[i] > 1) ? mean/(sd/MathSqrt((double)bN[i])) : 0;
               h += StringFormat("<tr><td>%02d:%02d - %02d:%02d</td><td>%d</td><td style='color:#bf616a'><b>%.1f</b></td>"
                                 "<td>%.0f</td><td style='color:%s'>%.2f</td></tr>",
                                 st/60, st%60, en/60, en%60, bN[i], mean, bSum[i],
                                 MathAbs(tst) > 2.0 ? "#ebcb8b" : "#7b8794", tst);
              }
            h += "</table>";
           }
        }
     }

   h += "<div class='note'>Nota: se SL e TP cadono nella stessa barra M1 viene contato lo <b>stop</b> (ipotesi pessimista). "
        "Ingresso all'open della barra +" + IntegerToString(InpEntryDelay) + ", costi gia' dedotti dal prezzo di ingresso. "
        "I trade \"scaduti\" sono chiusi al close dell'ultima barra dell'orizzonte.</div>";

   h += "</body></html>";

   string fn = "HitRate_" + _Symbol + "_TP" + IntegerToString(InpTPpoints) + ".html";
   int f = FileOpen(fn, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f == INVALID_HANDLE) { Print("HTML non scrivibile: ", GetLastError()); return; }
   FileWriteString(f, h);
   FileClose(f);
   Print("Report: MQL5/Files/", fn);
   Print("Hit rate globale: ", DoubleToString(hrTot, 1), "% (", totHit, "/", g_n, ")");
  }

//+------------------------------------------------------------------+
void WriteCSV()
  {
   string fn = "HitRate_" + _Symbol + "_TP" + IntegerToString(InpTPpoints) + ".csv";
   int f = FileOpen(fn, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(f == INVALID_HANDLE) return;
   FileWriteString(f, "time;dir;hour;minute;dow;hit;bars_to_tp;mae_at_tp;mae_full;mfe;end_pts;cost_pts;delta\n");
   for(int s = 0; s < g_n; s++)
     {
      MqlDateTime dt; TimeToStruct(s_time[s], dt);
      bool hit = (s_tTP[s] != BIG);
      FileWriteString(f, StringFormat("%s;%d;%d;%d;%d;%d;%s;%s;%.1f;%.1f;%.1f;%.1f\n",
         TimeToString(s_time[s], TIME_DATE|TIME_MINUTES), s_dir[s], dt.hour, dt.min, dt.day_of_week,
         hit ? 1 : 0, hit ? IntegerToString(s_tTP[s]) : "", hit ? DoubleToString(s_maeAtTP[s],1) : "",
         s_maeFull[s], s_mfe[s], s_endPts[s], s_cost[s], s_delta[s]));
     }
   FileClose(f);
   Print("CSV: MQL5/Files/", fn);
  }
//+------------------------------------------------------------------+
