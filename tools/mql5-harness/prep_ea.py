#!/usr/bin/env python3
"""Traduce l'EA reale in C++ per l'harness e inserisce gli hook che registrano segnali e valutazioni."""
import os, re, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
ea = os.path.join(here, "..", "..", "MQL5", "Experts", "VolumeProfile_v1.0_EA_ULTIMATE_ML_Sydney.mq5")
subprocess.check_call([sys.executable, os.path.join(here, "prep.py"), ea, "ea_tmp.cpp"])
t = open("ea_tmp.cpp", encoding="utf-8").read()
# RecordMLSignal viene chiamata per OGNI segnale tecnico prima del filtro ML
t = re.sub(r"(void RecordMLSignal\([^)]*\)\s*\n\{)", r"\1\n    HarnessRecord(is_long, time);", t, count=1)
t = re.sub(r"(void EvaluateSignal\(int shift, SSessionProfile &profile\)\s*\n\{)",
           r"\1\n    HarnessEval(iTime(_Symbol,_Period,shift), profile.start, profile.end, profile.poc, profile.vah, profile.val, g_HullValue);", t, count=1)
open("ea_pp.cpp", "w", encoding="utf-8").write(t)
print("hook RecordMLSignal:", "HarnessRecord" in t, "| hook EvaluateSignal:", "HarnessEval(" in t)
