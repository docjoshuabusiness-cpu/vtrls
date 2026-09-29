// Controllo dei pattern con nome su candele costruite a mano
#include <array>
#include <array>
#include "gen.cpp"
static CCx mk(std::initializer_list<std::array<double, 4>> cs)
  {
   CCx q; int n = (int)cs.size();
   q.Alloc(n); q.AllocFe(n);
   int i = 0;
   for(auto &c : cs)
     {
      q.o[i] = c[0]; q.h[i] = c[1]; q.l[i] = c[2]; q.c[i] = c[3]; q.ok[i] = 1; q.chn[i] = i + 1; q.ap[i] = 1.0f; q.fa[i] = 1.0f;
      q.shp[i] = (uchar)CxShape(c[0], c[1], c[2], c[3]);
      i++;
     }
   return q;
  }
static void chk(const char *nm, CCx &q, int bit, bool want)
  {
   int m = CxNamed(q, q.n - 1);
   bool got = (m & (1 << bit)) != 0;
   printf("  %-34s bit %2d atteso %d ottenuto %d %s\n", nm, bit, (int)want, (int)got, got == want ? "" : "  <<< ERRORE");
  }
int main()
  {
   // {open, high, low, close}
   { auto q = mk({{10, 10.5, 9, 9.2}, {9, 10.8, 8.9, 10.6}}); chk("engulfing rialzista", q, 0, true); chk("(non ribassista)", q, 1, false); }
   { auto q = mk({{9, 10.5, 8.9, 10.2}, {10.4, 10.5, 8.6, 8.8}}); chk("engulfing ribassista", q, 1, true); }
   { auto q = mk({{10.6, 10.7, 9.0, 9.2}, {9.6, 10.0, 9.5, 9.9}}); chk("harami rialzista", q, 2, true); chk("(non engulfing)", q, 0, false); }
   { auto q = mk({{9.2, 10.7, 9.0, 10.6}, {10.2, 10.3, 9.6, 9.7}}); chk("harami ribassista", q, 3, true); }
   { auto q = mk({{10.5, 10.6, 9.0, 9.2}, {9.3, 10.0, 9.0, 9.9}}); chk("tweezer al minimo", q, 4, true); }
   { auto q = mk({{9.2, 10.6, 9.1, 10.5}, {10.3, 10.6, 9.6, 9.8}}); chk("tweezer al massimo", q, 5, true); }
   { auto q = mk({{10.6, 10.7, 9.0, 9.2}, {9.1, 9.3, 8.8, 9.0}, {9.1, 10.5, 9.0, 10.3}}); chk("morning star", q, 6, true); }
   { auto q = mk({{9.2, 10.7, 9.1, 10.6}, {10.7, 11.0, 10.6, 10.8}, {10.5, 10.6, 9.0, 9.2}}); chk("evening star", q, 7, true); }
   { auto q = mk({{9.0, 9.6, 8.9, 9.5}, {9.3, 10.1, 9.2, 10.0}, {9.8, 10.7, 9.7, 10.6}}); chk("tre soldati bianchi", q, 8, true); }
   { auto q = mk({{10.6, 10.7, 9.9, 10.0}, {10.2, 10.3, 9.4, 9.5}, {9.7, 9.8, 8.9, 9.0}}); chk("tre corvi neri", q, 9, true); }
   { auto q = mk({{9.2, 11.2, 9.0, 11.0}, {10.4, 10.5, 9.9, 10.0}}); chk("inside dopo candela ampia", q, 16, true); }
   { auto q = mk({{10, 11, 9, 10.5}, {10.4, 10.8, 9.2, 10.0}, {10.1, 10.5, 9.5, 10.2}}); chk("due inside di fila", q, 17, true); }
   { auto q = mk({{10, 10.3, 9.9, 10.1}, {10.1, 10.6, 10.0, 10.5}, {10.4, 11.1, 10.3, 11.0}}); chk("tre rialziste range crescente", q, 18, true); }
   { auto q = mk({{10, 10.5, 9.8, 9.9}, {10, 10.3, 9.3, 9.4}, {9.5, 9.6, 8.2, 8.4}}); chk("tre ribassiste range crescente", q, 19, true); }
   { auto q = mk({{10, 10.5, 9.5, 10.2}, {10.1, 11.2, 9.0, 11.0}}); chk("outside rialzista", q, 20, true); }
   { auto q = mk({{10, 10.5, 9.5, 10.2}, {10.1, 11.2, 8.8, 9.0}}); chk("outside ribassista", q, 21, true); chk("(non rialzista)", q, 20, false); }
   // forme
   struct S { const char *n; double o, h, l, c; int want; };
   S ss[] = {{"doji", 10, 10.1, 9.5, 10.02, 0}, {"libellula", 10, 10.05, 8.5, 10.02, 1}, {"lapide", 10, 11.5, 9.98, 10.0, 2}, {"gambe lunghe", 10, 11, 9, 10.02, 3},
             {"pin inferiore", 10, 10.3, 8.5, 10.2, 4}, {"pin superiore", 10, 11.5, 9.9, 10.4, 5}, {"trottola", 10, 10.9, 9.2, 10.3, 6},
             {"corpo medio", 10, 10.9, 9.9, 10.5, 7}, {"corpo lungo", 10, 10.9, 9.9, 10.7, 8}, {"marubozu", 10, 10.9, 9.95, 10.85, 9}};
   for(auto &x : ss) { int g = CxShape(x.o, x.h, x.l, x.c); printf("  forma %-14s atteso %d ottenuto %d %s\n", x.n, x.want, g, g == x.want ? "" : "  <<< ERRORE"); }
   return 0;
  }
