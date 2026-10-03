#!/usr/bin/env python3
"""Translate an .mq5 file into C++17 that compiles against mql5_mock.h (test harness only)."""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
lines = text.split("\n")
out = []
for ln in lines:
    s = ln.strip()
    if s.startswith("#property"):
        continue
    if re.match(r"^input\s+group\b", s):
        continue
    ln = re.sub(r"^(sinput|input)\s+", "", ln)
    out.append(ln)
text = "\n".join(out)

# dynamic array declarations: "type a[], b[];"  (also inside structs)
def dyn(m):
    indent, const, typ, names = m.group(1), m.group(2) or "", m.group(3), m.group(4)
    ns = [n.strip()[:-2] for n in names.split(",")]
    return f"{indent}{const}Arr<{typ}> " + ", ".join(ns) + ";"

text = re.sub(r"^([ \t]*)(const\s+)?(\w+)\s+((?:\w+\[\]\s*,\s*)*\w+\[\])\s*;[ \t]*(//.*)?$", dyn, text, flags=re.M)

# array params: "const T &name[]" / "T &name[]"
text = re.sub(r"(const\s+)?(\w+)\s*&\s*(\w+)\s*\[\]", lambda m: f"{m.group(1) or ''}Arr<{m.group(2)}> &{m.group(3)}", text)

# prototypes for forward references (MQL5 allows calling functions defined later)
lines = text.split("\n")
protos = []
first_fn = None
i = 0
kw = {"if", "for", "while", "switch", "else", "return", "struct", "enum", "do"}
while i < len(lines):
    ln = lines[i]
    m = re.match(r"^([A-Za-z_][\w:<>\*&\s]*?)\s+\**&?(\w+)\s*\(", ln)
    if m and not ln.startswith((" ", "\t", "#", "//")) and m.group(2) not in kw and m.group(1).split()[0] not in kw:
        j = i
        sig = ln
        depth = sig.count("(") - sig.count(")")
        while depth > 0 and j + 1 < len(lines):
            j += 1
            sig += " " + lines[j].strip()
            depth = sig.count("(") - sig.count(")")
        k = j + 1
        while k < len(lines) and lines[k].strip() == "":
            k += 1
        if k < len(lines) and lines[k].strip().startswith("{") and not sig.rstrip().endswith(";"):
            if first_fn is None:
                first_fn = i
            sig2 = re.sub(r"//.*$", "", sig).strip()
            sig2 = re.sub(r"\s*=\s*[^,)]+(?=[,)])", "", sig2)  # drop default args in prototype
            protos.append(sig2 + ";")
            i = k
    i += 1

if first_fn is not None:
    lines[first_fn:first_fn] = ["// ---- auto prototypes"] + protos + ["// ---- end prototypes"]
text = "\n".join(lines)
text = text.replace("      if(!okp) continue;\n", "      if(!okp) continue;\n      HarnessEvalS(g_rc[k].time, P.start, P.end, P.poc, P.vah, P.val, g_hull[k]);\n")
open(dst, "w", encoding="utf-8").write(text)
print(f"{dst}: {len(protos)} prototypes")
