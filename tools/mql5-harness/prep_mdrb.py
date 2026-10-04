#!/usr/bin/env python3
"""Traduce MDRB_Study e l'EA MultiDayRangeBreakout per l'harness (inserisce l'hook dei piazzamenti nello studio)."""
import os, re, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, "..", "..", "MQL5")
subprocess.check_call([sys.executable, os.path.join(here, "prep.py"), os.path.join(root, "Scripts", "MDRB_AutoStudy.mq5"), "study_mdrb_tmp.cpp"])
t = open("study_mdrb_tmp.cpp", encoding="utf-8").read()
t = t.replace("      placed = true;\n      prevExpiry = pX[p];\n",
              "      placed = true;\n      prevExpiry = pX[p];\n      if(tMin == 0) HarnessPlace(D, g_rs[jp].time, buyPx, sellPx, pX[p]);\n")
assert "HarnessPlace(" in t
open("study_mdrb_pp.cpp", "w", encoding="utf-8").write(t)
subprocess.check_call([sys.executable, os.path.join(here, "prep.py"), os.path.join(root, "Experts", "MultiDayRangeBreakout.mq5"), "ea_mdrb_tmp.cpp"])
e = open("ea_mdrb_tmp.cpp", encoding="utf-8").read()
e = re.sub(r"#include <Trade\\Trade.mqh>", "", e)
open("ea_mdrb_pp.cpp", "w", encoding="utf-8").write(e)
print("hooks ok")
