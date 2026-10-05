#!/usr/bin/env python3
"""Traduce MDRB_Study e l'EA MultiDayRangeBreakout per l'harness (inserisce l'hook dei piazzamenti nello studio)."""
import os, re, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, "..", "..", "MQL5")
subprocess.check_call([sys.executable, os.path.join(here, "prep.py"), os.path.join(root, "Scripts", "MDRB_AutoStudy.mq5"), "study_mdrb_tmp.cpp"])
t = open("study_mdrb_tmp.cpp", encoding="utf-8").read()
# in C++ "a" + "b" non compila (in MQL5 si): letterale + letterale diventa letterali adiacenti
def merge_literals(text):
    out = []; i = 0; n = len(text); toks = []
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i); j = n if j < 0 else j; toks.append(("cm", i, j)); i = j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); j = n if j < 0 else j + 2; toks.append(("cm", i, j)); i = j; continue
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"': j += 2 if text[j] == "\\" else 1
            toks.append(("str", i, j + 1)); i = j + 1; continue
        if c == "'":
            j = i + 1
            while j < n and text[j] != "'": j += 2 if text[j] == "\\" else 1
            toks.append(("chr", i, j + 1)); i = j + 1; continue
        if c.isspace(): i += 1; continue
        j = i
        while j < n and not text[j].isspace() and text[j] not in "\"'" and not text.startswith("//", j) and not text.startswith("/*", j): j += 1
        toks.append(("oth", i, max(j, i + 1))); i = max(j, i + 1)
    cut = [toks[k + 1][1] for k in range(len(toks) - 2)
           if toks[k][0] == "str" and toks[k + 1][0] == "oth" and text[toks[k + 1][1]:toks[k + 1][2]] == "+" and toks[k + 2][0] == "str"]
    for pos in sorted(cut, reverse=True):
        text = text[:pos] + text[pos + 1:]
    return text
t = merge_literals(t)
t = t.replace("      placed = true;\n      prevExpiry = pX[p];\n",
              "      placed = true;\n      prevExpiry = pX[p];\n      if(tMin == 0) HarnessPlace(D, g_rs[jp].time, buyPx, sellPx, pX[p]);\n")
assert "HarnessPlace(" in t
open("study_mdrb_pp.cpp", "w", encoding="utf-8").write(t)
subprocess.check_call([sys.executable, os.path.join(here, "prep.py"), os.path.join(root, "Experts", "MultiDayRangeBreakout.mq5"), "ea_mdrb_tmp.cpp"])
e = open("ea_mdrb_tmp.cpp", encoding="utf-8").read()
e = re.sub(r"#include <Trade\\Trade.mqh>", "", e)
open("ea_mdrb_pp.cpp", "w", encoding="utf-8").write(e)
print("hooks ok")
