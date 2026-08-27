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

input group "=== LA DOMANDA ==="
input int      InpTPpoints      = 2000;   // punti da raggiungere dopo il segnale
input int      InpMaxBars       = 300;    // entro quante barre
input int      InpEntryDelay    = 1;      // 1 = entra all'open della barra dopo il segnale

input group "=== PERIODO ==="
input datetime InpFrom          = D'2025.01.01 00:00';
input datetime InpTo            = D'2026.12.31 00:00';
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
int      s_tSL[];        // [s*g_nSL + k] primo tocco livello SL k
int      g_n = 0;

//--- prototipi
void   WriteReport();
void   WriteCSV();

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
int EvalSignal(int i)
  {
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

   if(delta >  SignalThreshold) return  1;
   if(delta < -SignalThreshold) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   g_pt = _Point;
   for(int v = InpSLfrom; v <= InpSLto; v += InpSLstep)
     { ArrayResize(g_sl, g_nSL + 1); g_sl[g_nSL++] = v; }

   ArraySetAsSeries(g_r, false);
   g_bars = CopyRates(_Symbol, _Period, 0, TerminalInfoInteger(TERMINAL_MAXBARS), g_r);
   if(g_bars <= 0) { Print("CopyRates fallita: ", GetLastError()); return; }

   int hE = iMA(_Symbol, _Period, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   int hA = iATR(_Symbol, _Period, ATR_Period);
   int hD = UseADXFilter ? iADX(_Symbol, _Period, ADX_Period) : INVALID_HANDLE;
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
   Print("=== ", _Symbol, " ", EnumToString((ENUM_TIMEFRAMES)_Period),
         " | Digits=", _Digits, " | Point=", DoubleToString(g_pt, 8));
   Print("1 punto x 1 lotto = ", DoubleToString(g_ptValue, 4), " ", AccountInfoString(ACCOUNT_CURRENCY),
         " | ATR(", ATR_Period, ") M1 mediano = ", DoubleToString(g_atrMed, 1), " pt");
   Print("TP richiesto = ", InpTPpoints, " pt = ", DoubleToString(InpTPpoints * g_pt, _Digits),
         " in prezzo = ", DoubleToString(g_atrMed > 0 ? InpTPpoints / g_atrMed : 0, 1), " x ATR M1");

//--- scansione
   int minBars = MathMax(MathMax(EmaPeriod, VolAvgPeriod), MathMax(ATR_Period, SR_Lookback)) + 2;
   int cap = 8192;
   ArrayResize(s_time, cap); ArrayResize(s_dir, cap); ArrayResize(s_tTP, cap);
   ArrayResize(s_maeAtTP, cap); ArrayResize(s_maeFull, cap); ArrayResize(s_mfe, cap);
   ArrayResize(s_endPts, cap); ArrayResize(s_tSL, cap * g_nSL);

   int lastB = -1000000, lastS = -1000000;
   uint t0 = GetTickCount();

   for(int i = minBars; i < g_bars - InpEntryDelay - 1; i++)
     {
      if(g_r[i].time < InpFrom || g_r[i].time > InpTo) continue;
      int dir = EvalSignal(i);
      if(dir == 0) continue;
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
         ArrayResize(s_endPts, cap); ArrayResize(s_tSL, cap * g_nSL);
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
void HitRow(string &html, string label, int n, int hits, double sumBars)
  {
   double hr = (n > 0) ? 100.0 * hits / n : 0;
   double ab = (hits > 0) ? sumBars / hits : 0;
   // errore standard della proporzione -> quanto e' affidabile
   double se = (n > 0) ? 100.0 * MathSqrt((hr/100.0) * (1 - hr/100.0) / n) : 0;
   string cls = (n < InpMinPerBucket) ? " class='thin'" : "";
   html += StringFormat("<tr%s><td>%s</td><td>%d</td><td>%d</td><td><b>%.1f%%</b></td><td>&plusmn;%.1f</td><td>%.0f</td></tr>\n",
                        cls, label, n, hits, hr, se, ab);
  }

//+------------------------------------------------------------------+
void WriteReport()
  {
   int    hN[24], hH[24];  double hB[24];
   int    mN[60], mH[60];  double mB[60];
   int    dN[7],  dH[7];   double dB[7];
   ArrayInitialize(hN,0); ArrayInitialize(hH,0); ArrayInitialize(hB,0);
   ArrayInitialize(mN,0); ArrayInitialize(mH,0); ArrayInitialize(mB,0);
   ArrayInitialize(dN,0); ArrayInitialize(dH,0); ArrayInitialize(dB,0);

   int totHit = 0, nBuy = 0, nSell = 0, hBuy = 0, hSell = 0;
   double sumBars = 0;
   double maeWin[]; int nWin = 0; ArrayResize(maeWin, g_n);
   double barsArr[]; int nBA = 0; ArrayResize(barsArr, g_n);

   for(int s = 0; s < g_n; s++)
     {
      MqlDateTime dt; TimeToStruct(s_time[s], dt);
      bool hit = (s_tTP[s] != BIG);
      double bt = hit ? (double)s_tTP[s] : 0;

      hN[dt.hour]++; mN[dt.min]++; dN[dt.day_of_week]++;
      if(hit)
        {
         totHit++; sumBars += bt;
         hH[dt.hour]++; mH[dt.min]++; dH[dt.day_of_week]++;
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
   h += "<div style='color:#7b8794'>" + _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period)
      + " | orizzonte " + IntegerToString(InpMaxBars) + " barre | "
      + TimeToString(s_time[0], TIME_DATE) + " &rarr; " + TimeToString(s_time[g_n-1], TIME_DATE)
      + " | offset ore " + IntegerToString(InpTimeOffsetH) + "</div>";

   h += "<h2>Risposta</h2>";
   h += StringFormat("<div class='kpi'><span>Segnali</span><b>%d</b></div>", g_n);
   h += StringFormat("<div class='kpi'><span>Raggiungono il TP</span><b>%.1f%%</b>%d su %d</div>", hrTot, totHit, g_n);
   h += StringFormat("<div class='kpi'><span>Barre mediane al TP</span><b>%.0f</b>%s</div>",
                     Pctl(barsArr, nBA, 0.50), "minuti su M1");
   h += StringFormat("<div class='kpi'><span>TP in prezzo</span><b>%s</b>%.1f x ATR M1</div>",
                     DoubleToString(InpTPpoints * g_pt, _Digits), g_atrMed > 0 ? InpTPpoints / g_atrMed : 0);
   h += StringFormat("<div class='kpi'><span>TP per 1 lotto</span><b>%.0f %s</b></div>",
                     InpTPpoints * g_ptValue, AccountInfoString(ACCOUNT_CURRENCY));
   h += StringFormat("<div class='kpi'><span>Buy hit / Sell hit</span><b>%.1f%% / %.1f%%</b>%d / %d segnali</div>",
                     nBuy > 0 ? 100.0*hBuy/nBuy : 0, nSell > 0 ? 100.0*hSell/nSell : 0, nBuy, nSell);

   h += "<div class='note'><b>&plusmn;</b> e' l'errore standard della percentuale. Se due ore differiscono di meno di "
        "2 volte il loro &plusmn;, <b>non sono diverse</b>: e' rumore. Le righe grigie hanno meno di "
        + IntegerToString(InpMinPerBucket) + " segnali e vanno ignorate.</div>";

   h += "<h2>Per ORA del segnale</h2><table><tr><th>Ora</th><th>Segnali</th><th>Hit</th><th>Hit rate</th><th>&plusmn;</th><th>Barre medie al TP</th></tr>";
   for(int i = 0; i < 24; i++) HitRow(h, StringFormat("%02d:00", i), hN[i], hH[i], hB[i]);
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

//--- MAE sui vincenti: quanto SL serve per non farsi buttare fuori
   h += "<h2>Quanto SL serve? Sofferenza massima PRIMA di toccare il TP</h2>";
   h += "<div class='note'>Calcolato solo sui " + IntegerToString(nWin) + " segnali che il TP lo raggiungono. "
        "Uno SL sotto il 90&deg; percentile ti butta fuori da almeno il 10% dei trade che sarebbero andati a target.</div>";
   h += "<table><tr><th>Percentile</th><th>MAE (punti)</th><th>in prezzo</th><th>x ATR M1</th></tr>";
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
   FileWriteString(f, "time;dir;hour;minute;dow;hit;bars_to_tp;mae_at_tp;mae_full;mfe;end_pts\n");
   for(int s = 0; s < g_n; s++)
     {
      MqlDateTime dt; TimeToStruct(s_time[s], dt);
      bool hit = (s_tTP[s] != BIG);
      FileWriteString(f, StringFormat("%s;%d;%d;%d;%d;%d;%s;%s;%.1f;%.1f;%.1f\n",
         TimeToString(s_time[s], TIME_DATE|TIME_MINUTES), s_dir[s], dt.hour, dt.min, dt.day_of_week,
         hit ? 1 : 0, hit ? IntegerToString(s_tTP[s]) : "", hit ? DoubleToString(s_maeAtTP[s],1) : "",
         s_maeFull[s], s_mfe[s], s_endPts[s]));
     }
   FileClose(f);
   Print("CSV: MQL5/Files/", fn);
  }
//+------------------------------------------------------------------+
