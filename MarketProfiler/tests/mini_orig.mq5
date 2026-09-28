#define HI_NMOD 18
string HI_NAME[HI_NMOD] = {"Sessioni",
                           "Timeframe alto -> basso: stati singoli della candela alta (stato contro tutte le altre candele)",
                           "Timeframe alto -> basso: coppie di stati della candela alta (coppia contro tutte le altre candele)"};
void HiTab(void)
  {
   THead("Analisi|Confronti|Oltre |z| 3|Attesi per caso|Tra |z| 2 e 3|Attesi per caso");
  }
      string ctl = (MathIsValidNumber(g_ckZh[c]) ? ", rispetto " + (g_rrIntra ? "alla stessa ora" : "a tutte le candele") + " z " +
                    ZS(g_ckZh[c]) : "") + ", contro il placebo z " + ZS(g_ckZp[c]) + ", pareggio " + BpTxt(g_ckBe[c]);
string Js(void)
  {
   return "function cp(b,id){}" +
          "function show(id){if(!document.getElementById('tab-'+id))id='overview';" +
          "show(location.hash.slice(1)||'overview');";
  }
//+------------------------------------------------------------------+
//| Analisi di un simbolo                                             |
//+------------------------------------------------------------------+
bool Analyze(const string sym)
  {
   g_hiN = 0;
   ArrayInitialize(g_hiCnt, 0);
   Comment("MarketProfiler ", sym, ": costi dei broker ...");
   W("<button data-tab='overview'>Panoramica</button><button data-tab='sum'>Riepilogo</button>");
   W("<button data-tab='sess'>Sessioni</button>" +
     "<button data-tab='pers'>Persistenza</button><button data-tab='mtf'>Alto &rarr; basso</button>" +
     "<button data-tab='volume'>Volume</button>");
   W("<nav class='tx'><span>Testi da copiare:</span><button data-tab='report'>Rapporto completo</button><button data-tab='txsum'>Riepilogo</button>" +
     "<button data-tab='txdir'>Direzione</button><button data-tab='txpers'>Persistenza</button><button data-tab='txmtf'>Alto &rarr; basso</button><button data-tab='txrr'>R/R lordo</button>");
   W("<nav class='tx'><span>Tutti i risultati:</span><button data-tab='txmtfa'>Alto &rarr; basso: tutte le coppie di stati</button>");
   Comment("MarketProfiler ", sym, ": timeframe alto -> basso ...");
   W("<div class='tab' id='tab-mtf' hidden>");
   if(m1.n > 5000)
      MtfTab(m1, 60);
   else
      MtfTab(m5, 300);
   W("</div>");
   W("</div><div class='tab' id='tab-sum' hidden>");
   HiTab();
   W("</div><div class='tab' id='tab-report' hidden>");
   W(RepIndex());
   W(g_repMtf);
   TxTab("txvol", "Testo: volume", "Volume per ora, giorno e periodo.", "VOLUME - " + sym + "\n" + g_repVol);
  }
