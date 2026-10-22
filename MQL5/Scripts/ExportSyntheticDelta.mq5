//+------------------------------------------------------------------+
//|                                      ExportSyntheticDelta.mq5    |
//|   Salva in CSV le ultime N barre + i valori di SyntheticDelta    |
//+------------------------------------------------------------------+
//  Uso: compila, trascina lo script sul grafico (stesso simbolo e
//  timeframe che vuoi analizzare). Il file viene scritto in
//      <cartella dati>\MQL5\Files\SIMBOLO_PERIOD_XX_SyntheticDelta.csv
//  (MT5: File -> Apri cartella dati). Il CSV contiene, per ogni barra:
//  time (epoch, ora del server), OHLC, tick_volume, spread, e i valori
//  dell'indicatore: flow_z, absorption_z, legacy_x10 (vuoto = non calcolato).
//
//  L'indicatore deve essere compilato in MQL5\Indicators con il nome
//  "SyntheticDelta_v3.1" (cambia IndicatorName se l'hai messo in una
//  sottocartella, es. "Mie\\SyntheticDelta_v3.1"). Con la v3.0 metti
//  ExportEvents = false: la v3.0 non ha il buffer degli eventi.
//
//  I parametri passati a iCustom seguono l'ORDINE degli input
//  dell'indicatore: se modifichi gli input di SyntheticDelta_v3.0,
//  aggiorna anche la chiamata qui sotto.
//+------------------------------------------------------------------+
#property copyright "SyntheticDelta"
#property version   "1.00"
#property script_show_inputs

input string IndicatorName = "SyntheticDelta_v3.1"; // File dell'indicatore (senza estensione)
input bool   ExportEvents  = true;                  // Colonna "event" (+1 BUY, -1 SELL): solo v3.1
input int    BarsToExport  = 5000;                  // Ultime N barre da esportare
input int    InpFlowMode   = 0;                     // 0 = CLV, 1 = BVC
input int    InpFlowBars   = 12;                    // N (barre di aggregazione)
input int    InpBvcBars    = 50;                    // BVC: barre per la sigma
input int    InpZWindow    = 500;                   // M (finestra z-score)
input int    InpSeasonDays = 20;                    // D (giorni di storia stagionale)
input string OutName       = "";                    // Vuoto = nome automatico

//--- numero vuoto se l'indicatore non ha calcolato la barra
string Fmt(const double v)
  {
   if(v == EMPTY_VALUE || !MathIsValidNumber(v))
      return "";
   return DoubleToString(v, 8);
  }

void OnStart()
  {
   int want = MathMax(100, BarsToExport);

   //--- stessi default dell'indicatore, ShowLegacy acceso per esportare anche la linea v2.1
   int h = iCustom(_Symbol, _Period, IndicatorName,
                   InpFlowMode, InpFlowBars, InpBvcBars, InpZWindow, 1.5,   // FlowMode, FlowBars, BvcBars, ZWindow, Threshold
                   InpSeasonDays, 5, 3.0,                                   // SeasonDays, MinSessions, WeightCap
                   true, 14,                                                // ShowAbsorption, AtrPeriod
                   true,                                                    // ClosedBarsOnly
                   true, 13, 20, 10.0);                                     // ShowLegacy, LegacyEma, LegacyVolAvg, LegacyScale
   if(h == INVALID_HANDLE)
     {
      Print("ExportSyntheticDelta: iCustom fallito per '", IndicatorName, "', errore ", GetLastError(),
            " (l'indicatore e' compilato in MQL5\\Indicators?)");
      return;
     }

   //--- attende il calcolo dell'indicatore su tutta la storia (max 20 s)
   int total = Bars(_Symbol, _Period);
   for(int t = 0; t < 200 && BarsCalculated(h) < total && !IsStopped(); t++)
      Sleep(100);
   if(BarsCalculated(h) < total)
     {
      Print("ExportSyntheticDelta: l'indicatore non ha finito di calcolare (", BarsCalculated(h), "/", total,
            "). Riprova fra qualche secondo.");
      IndicatorRelease(h);
      return;
     }

   MqlRates rt[];
   double   z[], ab[], lg[], su[], sd[];
   ArraySetAsSeries(rt, false);
   ArraySetAsSeries(z,  false);
   ArraySetAsSeries(ab, false);
   ArraySetAsSeries(lg, false);
   ArraySetAsSeries(su, false);
   ArraySetAsSeries(sd, false);

   int got = CopyRates(_Symbol, _Period, 0, want, rt);
   if(got <= 0)
     {
      Print("ExportSyntheticDelta: CopyRates fallito, errore ", GetLastError());
      IndicatorRelease(h);
      return;
     }
   if(CopyBuffer(h, 0, 0, got, z)  != got ||
      CopyBuffer(h, 2, 0, got, ab) != got ||
      CopyBuffer(h, 3, 0, got, lg) != got ||
      (ExportEvents && (CopyBuffer(h, 4, 0, got, su) != got || CopyBuffer(h, 5, 0, got, sd) != got)))
     {
      Print("ExportSyntheticDelta: CopyBuffer fallito, errore ", GetLastError(), ". Riprova fra qualche secondo.");
      IndicatorRelease(h);
      return;
     }

   string fname = (OutName == "") ? StringFormat("%s_%s_SyntheticDelta.csv", _Symbol, EnumToString(_Period)) : OutName;
   int fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(fh == INVALID_HANDLE)
     {
      Print("ExportSyntheticDelta: FileOpen fallito per '", fname, "', errore ", GetLastError());
      IndicatorRelease(h);
      return;
     }

   FileWrite(fh, "time", "open", "high", "low", "close", "tick_volume", "spread",
             "flow_z", "absorption_z", "legacy_x10", "event");
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   for(int i = 0; i < got; i++)
      FileWrite(fh,
                (string)(long)rt[i].time,
                DoubleToString(rt[i].open,  dg),
                DoubleToString(rt[i].high,  dg),
                DoubleToString(rt[i].low,   dg),
                DoubleToString(rt[i].close, dg),
                (string)rt[i].tick_volume,
                (string)rt[i].spread,
                Fmt(z[i]), Fmt(ab[i]), Fmt(lg[i]),
                ExportEvents ? (su[i] != EMPTY_VALUE ? "1" : (sd[i] != EMPTY_VALUE ? "-1" : "0")) : "");
   FileClose(fh);
   IndicatorRelease(h);

   Print("ExportSyntheticDelta: scritte ", got, " barre in ",
         TerminalInfoString(TERMINAL_DATA_PATH), "\\MQL5\\Files\\", fname);
  }
//+------------------------------------------------------------------+
