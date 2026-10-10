#!/usr/bin/env python3
"""Genera MQL5/Scripts/SignalLab_MultiTF_Standalone.mq5: lo script con SD_Core.mqh incorporato.

Uso:  python3 tools/build_standalone.py
Il file generato non dipende da MQL5/Include e va rigenerato dopo ogni modifica
a SignalLab_MultiTF.mq5 o a SD_Core.mqh.
"""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
script = (root / "MQL5/Scripts/SignalLab_MultiTF.mq5").read_text(encoding="utf-8")
inc    = (root / "MQL5/Include/SD_Core.mqh").read_text(encoding="utf-8")

# dentro lo script non serve una seconda #property copyright
inc = re.sub(r'(?m)^#property copyright "SignalLab"\r?\n', "", inc)

marker = "#include <SD_Core.mqh>"
if script.count(marker) != 1:
    sys.exit("marker #include non trovato esattamente una volta")

banner = ("//--- ============================================================\n"
          "//--- INIZIO SD_Core.mqh (incorporato: questo file non richiede MQL5/Include)\n"
          "//--- ============================================================\n")
footer = ("\n//--- ============================================================\n"
          "//--- FINE SD_Core.mqh\n"
          "//--- ============================================================")
out = script.replace(marker, banner + inc.rstrip() + footer)
out = ("//+------------------------------------------------------------------+\n"
       "//| FILE GENERATO da tools/build_standalone.py: non modificarlo a mano.|\n"
       "//| Contiene SignalLab_MultiTF.mq5 + SD_Core.mqh in un solo file.     |\n"
       "//+------------------------------------------------------------------+\n") + out

dst = root / "MQL5/Scripts/SignalLab_MultiTF_Standalone.mq5"
dst.write_text(out, encoding="utf-8")
print("scritto", dst, len(out.splitlines()), "righe")
