#!/usr/bin/env python3
"""Estrae ProcessTrailing() dall'EA VP reale (testo verbatim) per compilarla nell'harness."""
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^void ProcessTrailing\(.*?^\}", src, flags=re.S | re.M)
if not m:
    sys.exit("ProcessTrailing non trovata")
open(sys.argv[2], "w", encoding="utf-8").write(m.group(0) + "\n")
print(sys.argv[2], len(m.group(0).splitlines()), "righe")
