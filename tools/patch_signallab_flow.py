#!/usr/bin/env python3
"""
patch_signallab_flow.py - aggiunge a SignalLab_MultiTF (file standalone generato da tools/build_standalone.py)
il modo InpMode = SDM_FLOW: gli eventi di Flow Z di SyntheticDelta v3 diventano un segnale come gli altri, e
tutto l'apparato del lab (clock M1, costi, ADX, regimi, gestione simulata, filtri, classifiche) lavora su di essi.

  python3 patch_signallab_flow.py SignalLab_MultiTF_standalone.mq5            # scrive ..._Flow.mq5 accanto
  python3 patch_signallab_flow.py IN.mq5 -o OUT.mq5 --include SD_CoreFlow.mqh
  python3 patch_signallab_flow.py --selftest

Fa 8 sostituzioni mirate. Se anche UNA non trova il suo punto d'innesto (o ne trova piu' di uno) si ferma
SENZA scrivere nulla e dice quale: il tuo file potrebbe essere una versione diversa da quella che ho letto.
Conserva codifica (UTF-8, UTF-8 con BOM, UTF-16) e fine riga del file originale. Non e' idempotente di
proposito: se il file e' gia' patchato lo dice e si ferma.
Il file prodotto NON e' stato compilato: compilalo in MetaEditor e controlla gli Errors.
Con InpMode = SDM_FLOW metti InpSweep = false: la scansione dei parametri e' fatta per il solo Delta.
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_INC = os.path.join(HERE, "..", "MQL5", "Include", "SD_CoreFlow.mqh")

INPUT_BLOCK = '''input group "=== FLOW Z (solo con InpMode = SDM_FLOW: SyntheticDelta v3, evento = primo attraversamento di +-soglia) ==="
input int      InpFlowN             = 12;     // N: barre di aggregazione del flusso
input int      InpFlowM             = 500;    // M: finestra dello z-score
input double   InpFlowThr           = 1.5;    // soglia |Z| dell'evento
input int      InpFlowDays          = 20;     // D: sedute di storia per la fascia oraria (volume stagionale)
input int      InpFlowMinSess       = 5;      // campioni minimi per fascia
input bool     InpFlowBvc           = false;  // false = CLV, true = BVC
input bool     InpFlowWeights       = true;   // false = ogni barra pesa uguale (A/B)

'''

FILL_BLOCK = '''
   g_fpar.flowMode    = InpFlowBvc ? 1 : 0;
   g_fpar.flowBars    = MathMax(2, InpFlowN);
   g_fpar.zWindow     = MathMax(50, InpFlowM);
   g_fpar.threshold   = InpFlowThr;
   g_fpar.seasonDays  = MathMax(3, InpFlowDays);
   g_fpar.minSessions = MathMax(1, MathMin(InpFlowMinSess, g_fpar.seasonDays));
   g_fpar.weightCap   = 3.0;
   g_fpar.atrPeriod   = 14;
   g_fpar.bvcBars     = 50;
   g_fpar.useWeights  = InpFlowWeights;
   g_fpar.runGapBars  = MathMax(0, InpRunGapBars);'''

INTRO_FLOW = '''if(InpMode == SDM_FLOW)
      W("<tr><th>Segnale</th><td>FLOW (SyntheticDelta v3) | " + string(InpFlowBvc ? "BVC" : "CLV") + " | N " + IS(InpFlowN) + " | M " + IS(InpFlowM) +
        " | soglia |Z| " + F2(InpFlowThr) + " | sedute stagionali " + IS(InpFlowDays) + " | pesi di volume " + string(InpFlowWeights ? "si" : "no") +
        " | RunGapBars " + IS(InpRunGapBars) + "</td></tr>");
   else
      '''


def read_text(path):
    raw = open(path, "rb").read()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        enc = "utf-16"
    elif raw[:3] == b"\xef\xbb\xbf":
        enc = "utf-8-sig"
    else:
        enc = "utf-8"
    text = raw.decode(enc)
    nl = "\r\n" if "\r\n" in text else "\n"
    return text.replace("\r\n", "\n"), enc, nl


def build_edits(include_text):
    inc = include_text if include_text.endswith("\n") else include_text + "\n"
    bar = "//--- " + "=" * 60 + "\n"
    inline = ("\n" + bar + "//--- INIZIO SD_CoreFlow.mqh (incorporato dalla patch Flow Z)\n" + bar + inc +
              bar + "//--- FINE SD_CoreFlow.mqh\n" + bar)
    return [
        ("enum ENUM_SD_MODE: aggiunge SDM_FLOW",
         r"(SDM_DELTA_ADDED[ \t]*=[ \t]*5)([ \t]*//[^\n]*)",
         lambda m: m.group(1) + "," + m.group(2) + "\n   SDM_FLOW = 6  // Flow Z di SyntheticDelta v3: evento = primo attraversamento di +-soglia"),
        ("ModeName(): case SDM_FLOW",
         r'(case[ \t]+SDM_DELTA_ADDED:[ \t]*return[ \t]*"DELTA_E_EXP_ADDED";)',
         lambda m: m.group(1) + '\n      case SDM_FLOW: return "FLOW";'),
        ("input del gruppo FLOW Z",
         r"""input[ \t]+group[ \t]+"=== STATO DI VOLATILITA'""",
         lambda m: INPUT_BLOCK + m.group(0)),
        ("variabile globale g_fpar",
         r"SDParams[ \t]+g_par;",
         lambda m: m.group(0) + "\nSDFlowParams g_fpar;"),
        ("riempimento di g_fpar in SetupInputs",
         r"g_par\.runGapBars[ \t]*=[ \t]*MathMax\(0,[ \t]*InpRunGapBars\);",
         lambda m: m.group(0) + FILL_BLOCK),
        ("ProcessTF: costruzione dei segnali",
         r"int[ \t]+warm[ \t]*=[ \t]*SD_BuildSignals\(r,[ \t]*n,[ \t]*g_par,[ \t]*dir,[ \t]*bur\);",
         lambda m: ("int   warm = (g_par.mode == SD_MODE_FLOW)\n"
                    "                ? SD_BuildSignalsFlow(r, n, g_fpar, (int)g_tfSec[t], dir, bur)\n"
                    "                : SD_BuildSignals(r, n, g_par, dir, bur);")),
        ("riga Segnale del report (cosmetica)",
         r"""W\("<tr><th>Segnale</th><td>"[ \t]*\+[ \t]*ModeName\(\)[ \t]*\+[ \t]*" \| EMA \"""",
         lambda m: INTRO_FLOW + m.group(0)),
        # ULTIMA: l'intestazione di SD_CoreFlow cita righe del lab che altrimenti diventerebbero punti d'innesto doppi
        ("inclusione di SD_CoreFlow dopo SD_Core",
         r"//--- FINE SD_Core\.mqh[ \t]*\n//--- =+[ \t]*\n",
         lambda m: m.group(0) + inline),
    ]


def patch(text, include_text):
    if "SD_BuildSignalsFlow" in text:
        raise SystemExit("il file contiene gia' la patch Flow Z: niente da fare.")
    for name, pat, rep in build_edits(include_text):
        ms = list(re.finditer(pat, text))
        if len(ms) != 1:
            raise SystemExit("PUNTO D'INNESTO NON TROVATO/AMBIGUO: '%s' (%d corrispondenze). Nessun file scritto.\n"
                             "Il tuo file e' una versione diversa da quella letta: mandami quel punto." % (name, len(ms)))
        m = ms[0]
        text = text[:m.start()] + rep(m) + text[m.end():]
    return "// PATCH Flow Z applicata da tools/patch_signallab_flow.py: modo InpMode = SDM_FLOW (SD_CoreFlow.mqh incorporato).\n" + text


def apply_file(src, dst, inc_path):
    text, enc, nl = read_text(src)
    inc, _, _ = read_text(inc_path)
    out = patch(text, inc).replace("\n", nl)
    with open(dst, "wb") as f:
        f.write(out.encode(enc))
    print("scritto %s (%s, fine riga %s)" % (dst, enc, "CRLF" if nl == "\r\n" else "LF"))


# --------------------------------------------------------------------------- selftest
FIXTURE = '''//+------------------------------------------------------------------+
//| FILE GENERATO da tools/build_standalone.py: non modificarlo a mano.|
//+------------------------------------------------------------------+
#property strict
SDParams g_x;
#endif
//--- ============================================================
//--- FINE SD_Core.mqh
//--- ============================================================

enum ENUM_SD_MODE
  {
   SDM_DELTA = 0,  // Solo Synthetic Delta
   SDM_ADDED = 4,  // Solo i segnali che l'Expansion AGGIUNGE a Delta (Expansion accesa, Delta spento)
   SDM_DELTA_ADDED = 5  // IN UN SOLO LANCIO: serie DELTA e serie EXP_ADDED, in tabelle distinte + confronto
  };

input group "=== SEGNALE (stessi parametri dell'EA) ==="
input ENUM_SD_MODE InpMode          = SDM_DELTA_ADDED;
input int      InpRunGapBars        = 0;      // Inp_RunGapBars

input group "=== STATO DI VOLATILITA' (indicatore Ferro: TR/ATR e percentile) ==="
input bool     InpUseVolState       = true;

//--- parametri derivati
SDParams g_par;
SDVolParams g_vpar;

string ModeName()
  {
   switch(InpMode)
     {
      case SDM_DELTA: return "DELTA";
      case SDM_DELTA_ADDED: return "DELTA_E_EXP_ADDED";
     }
   return "?";
  }

void RepIntro()
  {
   W("<h1>x</h1>");
   W("<tr><th>Segnale</th><td>" + ModeName() + " | EMA " + IS(InpEmaPeriod) + " | volume " + IS(InpVolAvgPeriod) +
     " | soglia " + F2(InpThreshold) + " | Exp TR/ATR &gt; " + F2(InpExpThreshold) + " (ATR " + IS(InpExpAtrPeriod) +
     ", conferma +" + IS(InpExpConfirmOffset) + ") | RunGapBars " + IS(InpRunGapBars) + "</td></tr>");
  }

bool SetupInputs()
  {
   g_par.mode             = g_setMode[0];
   g_par.runGapBars       = MathMax(0, InpRunGapBars);
   return true;
  }

void ProcessTF(const int t, const MqlRates &r[], const int n)
  {
   char  dir[];
   uchar bur[];
   int   warm = SD_BuildSignals(r, n, g_par, dir, bur);
   char  dir2[];
   SD_BuildSignals(r, n, p2, dir2, bur2);
  }
'''


def _balanced(s):
    t = re.sub(r"//[^\n]*", "", s)
    t = re.sub(r'"(\\.|[^"\\])*"', '""', t)
    return all(t.count(a) == t.count(b) for a, b in ("()", "{}", "[]"))


def selftest():
    inc, _, _ = read_text(DEFAULT_INC)
    ok = True

    def check(name, cond):
        nonlocal ok
        ok &= bool(cond)
        print("[%s] %s" % ("OK" if cond else "FAIL", name))

    out = patch(FIXTURE, inc)
    for needle in ("SDM_FLOW = 6", 'case SDM_FLOW: return "FLOW";', "InpFlowN", "SDFlowParams g_fpar;", "g_fpar.flowMode",
                   "SD_BuildSignalsFlow(r, n, g_fpar, (int)g_tfSec[t], dir, bur)", "INIZIO SD_CoreFlow.mqh", "void SD_FlowSeries(",
                   "if(InpMode == SDM_FLOW)"):
        check("contiene: " + needle, needle in out)
    check("SDM_DELTA_ADDED ha la virgola prima di SDM_FLOW", re.search(r"SDM_DELTA_ADDED = 5,[^\n]*\n   SDM_FLOW = 6", out))
    check("SD_BuildSignals(r, n, p2, ...) non toccata", "SD_BuildSignals(r, n, p2, dir2, bur2);" in out)
    check("parentesi, graffe e quadre bilanciate (senza commenti e stringhe)", _balanced(out))
    try:
        patch(out, inc)
        check("seconda applicazione rifiutata", False)
    except SystemExit:
        check("seconda applicazione rifiutata", True)
    try:
        patch(FIXTURE.replace("SDM_DELTA_ADDED = 5", "SDM_DELTA_ADDED = 7"), inc)
        check("anchor mancante: errore senza scrivere", False)
    except SystemExit as e:
        check("anchor mancante: errore senza scrivere (%s)" % str(e).splitlines()[0][:60], True)
    # round trip su file reale: UTF-16 con CRLF, come li salva MetaEditor
    import tempfile
    d = tempfile.mkdtemp()
    src, dst = os.path.join(d, "in.mq5"), os.path.join(d, "out.mq5")
    with open(src, "wb") as f:
        f.write(FIXTURE.replace("\n", "\r\n").encode("utf-16"))
    apply_file(src, dst, DEFAULT_INC)
    raw = open(dst, "rb").read()
    txt = raw.decode("utf-16")
    check("UTF-16 con BOM conservata", raw[:2] in (b"\xff\xfe", b"\xfe\xff"))
    check("fine riga CRLF conservata (nessun LF isolato)", "\r\n" in txt and "\n" not in txt.replace("\r\n", ""))
    check("contenuto identico al caso in memoria", txt.replace("\r\n", "\n") == out)
    print("\nPATCHER:", "OK" if ok else "FALLITO")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="?")
    ap.add_argument("-o", "--out")
    ap.add_argument("--include", default=DEFAULT_INC)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(selftest())
    if not a.src:
        ap.error("serve il file standalone di SignalLab_MultiTF (oppure --selftest)")
    dst = a.out or re.sub(r"(\.mq5)?$", "_Flow.mq5", a.src, count=1)
    apply_file(a.src, dst, a.include)


if __name__ == "__main__":
    main()
