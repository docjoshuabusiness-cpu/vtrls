#!/usr/bin/env python3
# Traduttore MQL5 -> C++ per il banco di prova (sottoinsieme di MQL5 usato dal codice)
import re, sys

BUILTIN = ['double', 'int', 'long', 'bool', 'string', 'datetime', 'char', 'uchar', 'short', 'ushort', 'uint', 'ulong', 'float']


def strip_and_placeholder(src):
    """Toglie i commenti e sostituisce le stringhe con segnaposto."""
    out = []
    lits = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.index('*/', i + 2)
            out.append('\n' * src[i:j].count('\n'))
            i = j + 2
            continue
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                if src[j] == '\\':
                    j += 1
                j += 1
            lits.append(src[i:j + 1])
            out.append('\x01%d\x02' % (len(lits) - 1))
            i = j + 1
            continue
        if c == "'":
            # letterale carattere: 'x' o '\n'
            m = re.match(r"'(\\.|[^'\\])'", src[i:i + 4])
            if m:
                out.append(m.group(0))
                i += len(m.group(0))
                continue
        out.append(c)
        i += 1
    return ''.join(out), lits


def split_top(s, sep=','):
    parts, depth, cur = [], 0, []
    for ch in s:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        if ch == sep and depth == 0:
            parts.append(''.join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append(''.join(cur))
    return parts


def convert_decls(code, types):
    tpat = '|'.join(sorted(map(re.escape, types), key=len, reverse=True))
    pat = re.compile(r'(?m)(^|(?<=[;{}]))([ \t]*)((?:const[ \t]+|static[ \t]+)*)(' + tpat + r')[ \t]+([A-Za-z_]\w*)[ \t]*\[')
    res = []
    pos = 0
    while True:
        m = pat.search(code, pos)
        if not m:
            res.append(code[pos:])
            break
        res.append(code[pos:m.start()])
        # trova la fine dell'istruzione
        j = m.end(4) if False else m.start(4)
        depth = 0
        k = j
        while k < len(code):
            ch = code[k]
            if ch in '([{':
                depth += 1
            elif ch in ')]}':
                depth -= 1
            elif ch == ';' and depth == 0:
                break
            k += 1
        body = code[m.end(4):k]
        typ = m.group(4)
        indent = m.group(2)
        decls = split_top(body)
        stm = []
        for d in decls:
            d = d.strip()
            mm = re.match(r'^(\w+)\s*((?:\[[^\]]*\]\s*)*)\s*(?:=\s*(.*))?$', d, re.S)
            if not mm:
                raise SystemExit('dichiarazione non riconosciuta: ' + d[:80])
            name, dims, init = mm.group(1), mm.group(2), mm.group(3)
            dl = re.findall(r'\[([^\]]*)\]', dims)
            if len(dl) > 1:
                raise SystemExit('array multidimensionale non supportato: ' + name)
            if dl:
                size = dl[0].strip()
                if init is not None:
                    if not init.strip().startswith('{'):
                        raise SystemExit('init array non valido: ' + name)
                    n = size if size else '-1'
                    stm.append('Arr<%s> %s = Arr<%s>(%s, %s);' % (typ, name, typ, n, init.strip()))
                elif size:
                    stm.append('Arr<%s> %s = Arr<%s>(%s);' % (typ, name, typ, size))
                else:
                    stm.append('Arr<%s> %s;' % (typ, name))
            else:
                stm.append('%s %s%s;' % (typ, name, (' = ' + init.strip()) if init is not None else ''))
        pre = m.group(1)
        res.append(pre + indent + ' '.join(stm))
        pos = k + 1
    return ''.join(res)


def convert_params(code):
    return re.sub(r'((?:const\s+)?)([A-Za-z_]\w*)\s*&\s*(\w+)\s*\[\s*\]', lambda m: '%sArr<%s> &%s' % (m.group(1), m.group(2), m.group(3)), code)


def units(code):
    """Divide il codice in unita' di primo livello: (tipo, testo)."""
    out = []
    depth = 0
    cur = []
    for line in code.split('\n'):
        s = line.strip()
        if depth == 0 and not cur and s.startswith('#'):
            out.append(('pp', line))
            continue
        if depth == 0 and not cur and s == '':
            out.append(('blank', line))
            continue
        cur.append(line)
        depth += line.count('{') - line.count('}')
        # parentesi graffe dentro le liste di inizializzazione contano gia'
        if depth == 0 and (s.endswith(';') or s.endswith('}')):
            out.append(('code', '\n'.join(cur)))
            cur = []
    if cur:
        out.append(('code', '\n'.join(cur)))
    return out


def main():
    files = sys.argv[2:]
    src = ''
    for f in files:
        src += open(f).read() + '\n'
    code, lits = strip_and_placeholder(src)
    # direttive
    code = re.sub(r'(?m)^\s*#(property|include|import)[^\n]*\n', '\n', code)
    code = re.sub(r'(?m)^input\s+', '', code)
    # tipi definiti dal codice
    types = list(BUILTIN)
    for m in re.finditer(r'(?m)^\s*(?:class|struct|enum)\s+(\w+)', code):
        types.append(m.group(1))
    code = convert_decls(code, types)
    code = convert_params(code)
    # prototipi e dichiarazioni anticipate
    fwd = []
    protos = []
    for kind, txt in units(code):
        if kind != 'code':
            continue
        t = txt.strip()
        mm = re.match(r'^(class|struct)\s+(\w+)', t)
        if mm:
            fwd.append('%s %s;' % (mm.group(1), mm.group(2)))
            continue
        if re.match(r'^(enum|typedef)\b', t):
            continue
        head = t.split('{')[0]
        if '(' in head and '=' not in head.split('(')[0] and not head.rstrip().endswith(';'):
            mh = re.match(r'^((?:const\s+)?[A-Za-z_][\w<>:, ]*?[\s&*]+)(\w+)\s*\((.*)\)\s*$', head.strip(), re.S)
            if mh:
                protos.append(head.strip() + ';')
    # ripristina le stringhe
    def restore(s):
        return re.sub('\x01(\\d+)\x02', lambda m: 'S(%s)' % lits[int(m.group(1))], s)
    body = restore(code)
    pro = restore('\n'.join(protos))
    with open(sys.argv[1], 'w') as fo:
        fo.write('#include "mql_rt.h"\n')
        fo.write('\n'.join(fwd) + '\n')
        fo.write(pro + '\n')
        fo.write(body)


main()
