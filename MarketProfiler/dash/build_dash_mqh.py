#!/usr/bin/env python3
# Genera MarketProfilerDash.mqh: emit.mqh (emettitore JSON e scheda) + dash.css e dash.js come funzioni di stringa MQL5.
# Uso: python3 dash/build_dash_mqh.py   (scrive ../MarketProfilerDash.mqh)
import os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, '..')
LIM = 1400   # lunghezza massima di ogni letterale (dopo l'escape)


def minify(text, kind):
    out = []
    for ln in text.replace('\r\n', '\n').replace('\r', '\n').split('\n'):
        s = ln.strip()
        if not s:
            continue
        if kind == 'js' and s.startswith('//'):
            continue
        if kind == 'css' and s.startswith('/*') and s.endswith('*/'):
            continue
        if kind == 'js' and s.startswith('/*') and s.endswith('*/'):
            continue
        out.append(s.replace('\t', ' '))
    return '\n'.join(out)


def atoms(text):
    """Scompone il testo in atomi gia' escapati per il letterale MQL5 (un carattere = un atomo)."""
    res = []
    for ch in text:
        o = ord(ch)
        if ch == '\\':
            res.append('\\\\')          # un backslash del sorgente = due nel letterale MQL5
        elif ch == '"':
            res.append('\\"')
        elif ch == '\n':
            res.append('\\n')
        elif o < 32:
            res.append(' ')
        elif o < 127:
            res.append(ch)
        elif o < 0x10000:
            res.append('\\\\u%04x' % o)
        else:
            o -= 0x10000
            res.append('\\\\u%04x\\\\u%04x' % (0xD800 + (o >> 10), 0xDC00 + (o & 0x3FF)))
    return res


def as_func(name, text):
    at = atoms(text)
    lines = ['string %s(void)' % name, '  {', '   string s = "";']
    cur, n = [], 0
    for a in at:
        if n + len(a) > LIM:
            lines.append('   s += "%s";' % ''.join(cur))
            cur, n = [], 0
        cur.append(a)
        n += len(a)
    if cur:
        lines.append('   s += "%s";' % ''.join(cur))
    lines += ['   return s;', '  }', '']
    return '\n'.join(lines)


def main():
    css = open(os.path.join(here, 'dash.css'), encoding='utf-8').read()
    js = open(os.path.join(here, 'dash.js'), encoding='utf-8').read()
    emit = open(os.path.join(here, 'emit.mqh'), encoding='utf-8').read()
    css, js = minify(css, 'css'), minify(js, 'js')
    for t, nm in ((css, 'css'), (js, 'js')):
        if re.search(r'</script|<!--', t, re.I):
            sys.exit('%s contiene </script o <!--' % nm)
    out = emit.rstrip('\n') + '\n\n'
    out += '//--- generato da dash/build_dash_mqh.py da dash.css e dash.js: non modificare a mano\n'
    out += as_func('DashCss', css) + '\n' + as_func('DashJs', js)
    bad = [c for c in out if ord(c) > 126]
    if bad:
        sys.exit('caratteri non ASCII nel risultato: %r' % bad[:5])
    p = os.path.join(root, 'MarketProfilerDash.mqh')
    open(p, 'w', encoding='utf-8', newline='\n').write(out)
    print('scritto', p, len(out), 'caratteri; css', len(css), 'js', len(js))


main()
