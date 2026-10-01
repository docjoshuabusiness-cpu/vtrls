// Prove di MultiDayRangeBreakout contro il finto MT5 (ea_rt.h). Una prova per esecuzione: ./t_v3 <prova>   (./t_v2 per l'originale)
#include "ea_rt.h"
#ifdef EA_V2
#include "gen_v2.cpp"
#else
#include "gen_v3.cpp"
#endif
#include <random>
#include <cstdint>

static const datetime T0 = 1704067200;   // lunedi' 2024-01-01 00:00, ora server
static int t_fail = 0, t_checks = 0;
#define CHECK(c, ...) do { t_checks++; if(!(c)) { t_fail++; printf("  FALLITO riga %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while(0)

struct Tick { datetime t; double bid; double spr; };

//--- versione sotto prova
#ifdef EA_V2
static const char *VER = "v2.00 (originale)";
static const bool IS_V3 = false;
static void cfgReset()
  {
   LotSize = 0.01; UseBarRange = true; RangeBarsLookback = 25; UseTimeRange = false; RangeHourStart = 16; RangeMinuteStart = 0; RangeHourEnd = 0; RangeMinuteEnd = 0;
   Timeframe = PERIOD_CURRENT; EnableMultiDayTrading = true; UsePreviousDayRange = true; RangeDaysBack = 1; RequireRangeConfirmation = true; MinRangePoints = 50; MaxRangePoints = 5000;
   OneTradePerRange = true; ResetOnNewDay = true; AllowNewTradeIfPositionHeld = true; MaxTradesPerDay = 1; TradeHourStart = 10; TradeMinuteStart = 0; TradeHourEnd = 11; TradeMinuteEnd = 0;
   TradeSameDayOnly = false; AvoidMidnightHours = true; StopLossPoints = 100; TakeProfitPoints = 200; UseTakeProfit = true; PendingOrderOffsetPoints = 20;
   UsaBreakEven = true; BreakEvenAttivazione = 100; BreakEvenOffset = 10; UsaTrailingStop = true; TrailingStartProfit = 150; TrailingStep = 20; TrailingOffset = 30;
   Slippage = 10; MagicNumber = 123456;
  }
static bool ea_valid() { return isRangeValid; }
static double ea_up() { return upperRange; }
static double ea_lo() { return lowerRange; }
#else
static const char *VER = "v3.00";
static const bool IS_V3 = true;
static void cfgReset()
  {
   LotSize = 0.01; RangeMode = RANGE_BARS; Timeframe = PERIOD_CURRENT; RangeDaysBack = 1; RangeBarsLookback = 25; RangeHourStart = 16; RangeMinuteStart = 0; RangeHourEnd = 0; RangeMinuteEnd = 0;
   RangeDaySpan = 1; RequireRangeConfirmation = true; MinRangePoints = 50; MaxRangePoints = 5000; TradeHourStart = 10; TradeMinuteStart = 0; TradeHourEnd = 11; TradeMinuteEnd = 0;
   ExpireExtraMinutes = 0; MaxTradesPerDay = 1; PendingOrderOffsetPoints = 20; ChaseIfBroken = false; StopLossPoints = 100; TakeProfitPoints = 200; UseTakeProfit = true;
   MaxSpreadPoints = 0; MaxSpreadPctOfSL = 15; UsaBreakEven = true; BreakEvenAttivazione = 100; BreakEvenOffset = 10; UsaTrailingStop = true; TrailingStartProfit = 150; TrailingStep = 20;
   TrailingOffset = 30; Slippage = 10; MagicNumber = 123456; OrderComment = "MDRB3"; ShowPanel = true; ShowRangeLines = true;
  }
static bool ea_valid() { return g_rangeDone && g_rangeOK; }
static double ea_up() { return g_upper; }
static double ea_lo() { return g_lower; }
#endif

//--- motore
static void engineReset(int chartTF, int digits = 5)
  {
   mk_resetBroker(); mk_initSeries(); mk_sym = MkSym();
   mk_sym.digits = digits; mk_sym.point = mk_sym.tick = std::pow(10.0, -digits);
   _Point = mk_sym.point; _Digits = mk_sym.digits; mk_chartTF = chartTF; mk_now = 0; mk_bid = mk_ask = 0;
  }
static void feed(const Tick &k)
  {
   mk_now = k.t;
   mk_bid = NormalizeDouble(k.bid, _Digits);
   mk_ask = NormalizeDouble(mk_bid + k.spr * _Point, _Digits);
   mk_updateSeries(k.t, mk_bid);
   mk_brokerTick();
  }
struct Hooks { std::function<void(const Tick &)> pre, post; };
static void play(const std::function<bool(Tick &)> &next, Hooks &h)
  {
   Tick k;
   while(next(k))
     {
      feed(k);
      if(h.pre) h.pre(k);
      OnTick();
      if(h.post) h.post(k);
     }
  }

//--- generatori di tick: lunedi'-venerdi', 1440 minuti al giorno, 4 tick al minuto
static double hourWeight(int h) { return (h >= 9 && h < 17) ? 1.6 : ((h >= 7 && h < 9) || (h >= 17 && h < 20)) ? 1.0 : 0.4; }
struct RandGen
  {
   std::mt19937_64 rng;
   std::normal_distribution<double> nd{0.0, 1.0};
   int weeks, w = 0, d = 0, m = 0, k = 0;
   double px, kv, gapSig, drift;
   std::function<double(datetime)> sprFn;
   RandGen(uint64_t seed, int weeks_, double dailyVol = 0.0055, double gap = 0.0011, double drift_ = 0.0) : rng(seed), weeks(weeks_), px(_Digits == 5 ? 1.10000 : 150.000), gapSig(gap), drift(drift_)
     {
      double S = 0;
      for(int h = 0; h < 24; h++) S += 60.0 * hourWeight(h) * hourWeight(h);
      kv = dailyVol / std::sqrt(S);
     }
   bool next(Tick &t)
     {
      if(w >= weeks) return false;
      t.t = T0 + (datetime)w * 604800 + (datetime)d * 86400 + m * 60 + k * 15;
      int h = m / 60;
      if(d == 0 && m == 0 && k == 0 && w > 0) px *= 1.0 + gapSig * nd(rng);
      px *= 1.0 + kv * hourWeight(h) * 0.5 * nd(rng) + drift;
      t.bid = std::round(px / _Point) * _Point;
      t.spr = sprFn ? sprFn(t.t) : ((h == 23 || h == 0) ? 30.0 : (h >= 9 && h < 17) ? 8.0 : 12.0);
      if(++k == 4) { k = 0; if(++m == 1440) { m = 0; if(++d == 5) { d = 0; w++; } } }
      return true;
     }
  };
struct PathGen
  {
   int weeks, w = 0, d = 0, m = 0, k = 0;
   std::function<double(datetime)> f, sprFn;
   PathGen(int weeks_, std::function<double(datetime)> f_, std::function<double(datetime)> s_) : weeks(weeks_), f(f_), sprFn(s_) {}
   bool next(Tick &t)
     {
      if(w >= weeks) return false;
      t.t = T0 + (datetime)w * 604800 + (datetime)d * 86400 + m * 60 + k * 15;
      t.bid = std::round(f(t.t) / 0.00001) * 0.00001;
      t.spr = sprFn(t.t);
      if(++k == 4) { k = 0; if(++m == 1440) { m = 0; if(++d == 5) { d = 0; w++; } } }
      return true;
     }
  };
__attribute__((unused)) static datetime dayT(int week, int dow, int hh = 0, int mm = 0) { return T0 + (datetime)week * 604800 + (datetime)dow * 86400 + hh * 3600 + mm * 60; }
__attribute__((unused)) static double lerp(datetime t, datetime a, datetime b, double va, double vb) { if(t <= a) return va; if(t >= b) return vb; return va + (vb - va) * (double)(t - a) / (double)(b - a); }
__attribute__((unused)) static double calmPx(datetime t) { return 1.10200 + 0.00200 * std::sin(2.0 * M_PI * (double)(t - T0) / 10800.0); }   // oscilla tra 1.1000 e 1.1040 (periodo 3 ore)
__attribute__((unused)) static double flatSpr(datetime) { return 12.0; }

//--- finestra di entrata, uguale per le due versioni (tol = minuti di tolleranza oltre la fine)
static bool inWin(datetime t, int tol)
  {
   int s = TradeHourStart * 60 + TradeMinuteStart, e = TradeHourEnd * 60 + TradeMinuteEnd;
   int len = (e - s + 1440) % 1440;
   int off = (int)((t % 86400) / 60 - s + 1440) % 1440;
   int extra = 0;
#ifndef EA_V2
   extra = ExpireExtraMinutes;
#endif
   return off < len + extra + tol;
  }

//--- monitor delle invarianti, comune alle due versioni
struct Mon
  {
   int tol = 0;
   long ticks = 0, stale = 0, twoPos = 0, fillsOutside = 0, slViol = 0, fills = 0;
   long maxOco = 0;
   size_t dealsSeen = 0;
   std::map<ulong, double> lastSL;
   std::map<datetime, int> perDay;
   void post(const Tick &k)
     {
      ticks++;
      if(!mk_ord.empty() && !inWin(k.t, tol)) stale++;
      if(mk_pos.size() > 1) twoPos++;
      for(; dealsSeen < mk_deals.size(); dealsSeen++)
        {
         const MkDeal &d = mk_deals[dealsSeen];
         if(d.entry != DEAL_ENTRY_IN) continue;
         fills++;
         perDay[d.time - d.time % 86400]++;
         if(!inWin(d.time, tol)) fillsOutside++;
        }
      if(!mk_pos.empty() && !mk_ord.empty())
        {
         long dl = (long)(k.t - mk_pos.back().time);
         if(dl > maxOco) maxOco = dl;
        }
      for(auto &p : mk_pos)
        {
         auto it = lastSL.find(p.ticket);
         if(it != lastSL.end())
           {
            bool buy = (p.type == POSITION_TYPE_BUY);
            if(buy ? p.sl < it->second - 1e-9 : p.sl > it->second + 1e-9) slViol++;
           }
         lastSL[p.ticket] = p.sl;
        }
     }
   int daysOver(int maxPerDay) const { int n = 0; for(auto &kv : perDay) if(kv.second > maxPerDay) n++; return n; }
  };
static long totalRejects() { long n = 0; for(auto &kv : mk_rejects) n += kv.second; return n; }
static void tradeStats(double &mean, double &se, int &n, int &wins, int &sl, int &tp)
  {
   n = (int)mk_posHist.size(); wins = sl = tp = 0;
   double s = 0, s2 = 0;
   for(auto &p : mk_posHist)
     {
      double pts = ((p.type == POSITION_TYPE_BUY) ? (p.cprice - p.price) : (p.price - p.cprice)) / _Point;
      s += pts; s2 += pts * pts;
      if(pts > 0) wins++;
      if(p.reason == 0) sl++; else tp++;
     }
   mean = n ? s / n : 0;
   double var = n > 1 ? (s2 - s * s / n) / (n - 1) : 0;
   se = n > 1 ? std::sqrt(var / n) : 0;
  }

//--- range atteso, calcolato in modo indipendente dalle serie (stesse regole descritte nell'intestazione dell'EA)
struct Exp { bool ok; double hi, lo; };
static Exp expBars(int tf, int daysBack, int n)
  {
   MkSeries *s = mk_get(tf), *d1 = mk_get(PERIOD_D1);
   Exp e{false, 0, 0};
   int last;   // indice dell'ultima barra da includere
   if(daysBack == 0)
      last = (int)s->b.size() - 2;
   else
     {
      int di = (int)d1->b.size() - daysBack;
      if(di < 0) return e;
      datetime endT = d1->b[di].t;
      last = -1;
      for(int i = (int)s->b.size() - 1; i >= 0; i--) if(s->b[i].t < endT) { last = i; break; }
     }
   if(last - n + 1 < 0) return e;
   e.hi = -1e9; e.lo = 1e9;
   for(int i = last - n + 1; i <= last; i++) { e.hi = std::max(e.hi, s->b[i].h); e.lo = std::min(e.lo, s->b[i].l); }
   e.ok = true;
   return e;
  }
__attribute__((unused)) static Exp expTime(int tf, int daysBack, int hs, int ms, int he, int me, datetime now)
  {
   MkSeries *s = mk_get(tf), *d1 = mk_get(PERIOD_D1);
   Exp e{false, 0, 0};
   int di = (int)d1->b.size() - 1 - daysBack;
   if(di < 0) return e;
   datetime ws = d1->b[di].t + hs * 3600 + ms * 60, we = d1->b[di].t + he * 3600 + me * 60;
   if(we <= ws) we += 86400;
   if(we > now) return e;
   e.hi = -1e9; e.lo = 1e9;
   int n = 0;
   for(auto &b : s->b) if(b.t >= ws && b.t < we) { e.hi = std::max(e.hi, b.h); e.lo = std::min(e.lo, b.l); n++; }
   e.ok = n > 0;
   return e;
  }
__attribute__((unused)) static Exp expD1(int daysBack, int span)
  {
   MkSeries *d1 = mk_get(PERIOD_D1);
   Exp e{false, 0, 0};
   int a = (int)d1->b.size() - 1 - daysBack;   // indice del giorno di riferimento
   if(a - span + 1 < 0) return e;
   e.hi = -1e9; e.lo = 1e9;
   for(int i = a - span + 1; i <= a; i++) { e.hi = std::max(e.hi, d1->b[i].h); e.lo = std::min(e.lo, d1->b[i].l); }
   e.ok = true;
   return e;
  }

//--- prova 1: il range e' quello giusto?
struct RangeCase { const char *name; int chart; int mode; int tf; int back; int n; int hs, ms, he, me; int span; };
static void runRange()
  {
   printf("PROVA range (%s): il range calcolato contro il range atteso, 10 settimane di serie casuali\n", VER);
#ifdef EA_V2
   RangeCase cases[] = {{"barre: 25 barre H1, 1 giorno indietro", PERIOD_H1, 0, 0, 1, 25, 0, 0, 0, 0, 1}};
#else
   RangeCase cases[] = {
      {"barre: 25 barre H1, 1 giorno indietro", PERIOD_H1, RANGE_BARS, 0, 1, 25, 0, 0, 0, 0, 1},
      {"barre: 10 barre M15, 2 giorni indietro", PERIOD_M15, RANGE_BARS, 0, 2, 10, 0, 0, 0, 0, 1},
      {"barre: 25 barre H1, ultime chiuse (0 giorni)", PERIOD_H1, RANGE_BARS, 0, 0, 25, 0, 0, 0, 0, 1},
      {"barre: 6 barre H4, 1 giorno indietro", PERIOD_H4, RANGE_BARS, 0, 1, 6, 0, 0, 0, 0, 1},
      {"orario: 16:00-24:00 H1, 1 giorno indietro", PERIOD_H1, RANGE_TIME, 0, 1, 0, 16, 0, 0, 0, 1},
      {"orario: 20:00-02:00 M15 (passa la mezzanotte), 1 giorno", PERIOD_M15, RANGE_TIME, 0, 1, 0, 20, 0, 2, 0, 1},
      {"orario: 00:00-08:00 H1 oggi (range asiatico)", PERIOD_H1, RANGE_TIME, 0, 0, 0, 0, 0, 8, 0, 1},
      {"giorni D1: ieri", PERIOD_H1, RANGE_PREV_D1, 0, 1, 0, 0, 0, 0, 0, 1},
      {"giorni D1: ultimi 3", PERIOD_H1, RANGE_PREV_D1, 0, 1, 0, 0, 0, 0, 0, 3},
      {"giorni D1: 2 giorni dal terzultimo", PERIOD_H1, RANGE_PREV_D1, 0, 3, 0, 0, 0, 0, 0, 2}};
#endif
   for(auto &c : cases)
     {
      cfgReset();
      engineReset(c.chart);
#ifdef EA_V2
      RangeBarsLookback = c.n; RangeDaysBack = c.back;
#else
      RangeMode = (ENUM_RANGE_MODE)c.mode; RangeDaysBack = c.back; RangeBarsLookback = c.n; RangeHourStart = c.hs; RangeMinuteStart = c.ms; RangeHourEnd = c.he; RangeMinuteEnd = c.me; RangeDaySpan = c.span;
      TradeHourStart = (c.mode == RANGE_TIME && c.back == 0) ? 10 : 10;
#endif
      OnInit();
      RandGen g(11, 10);
      int events = 0, okEq = 0, bad = 0, badValid = 0, noData = 0, skipped = 0;
      long lastDay = -1;
      std::map<int, int> badByDow;
      Hooks h;
      h.post = [&](const Tick &k)
        {
         long day = (long)(k.t / 86400);
         if(day == lastDay || (k.t % 86400) < 36000) return;   // primo tick dopo le 10:00 di ogni giorno
         lastDay = day;
         events++;
         Exp e;
#ifdef EA_V2
         e = expBars(mk_chartTF, 1, 25);
#else
         if(c.mode == RANGE_BARS) e = expBars(c.chart, c.back, c.n);
         else if(c.mode == RANGE_TIME) e = expTime(c.chart, c.back, c.hs, c.ms, c.he, c.me, k.t);
         else e = expD1(c.back, c.span);
#endif
         bool expValid = e.ok && e.hi > e.lo && (!RequireRangeConfirmation || ((e.hi - e.lo) / _Point >= MinRangePoints && (e.hi - e.lo) / _Point <= MaxRangePoints));
         if(!e.ok) { noData++; return; }
#ifndef EA_V2
         if(!g_rangeDone) { skipped++; return; }   // posizione ancora aperta da ieri: nessun nuovo setup
#endif
         if(ea_valid() != expValid) { badValid++; return; }
         if(!expValid) { okEq++; return; }
         if(std::fabs(ea_up() - e.hi) < 1e-9 && std::fabs(ea_lo() - e.lo) < 1e-9) okEq++;
         else { bad++; MqlDateTime dt; TimeToStruct(k.t, dt); badByDow[dt.day_of_week]++; }
        };
      play([&](Tick &t) { return g.next(t); }, h);
      printf("  %-58s giorni verificati %3d  esatti %3d  sbagliati %3d  validita' diversa %d  (dati non pronti %d, saltati %d)", c.name, events - noData - skipped, okEq, bad, badValid, noData, skipped);
      if(bad) { printf("  per giorno (1=lun..5=ven):"); for(auto &kv : badByDow) printf(" %d:%d", kv.first, kv.second); }
      printf("\n");
      if(IS_V3) CHECK(bad == 0 && badValid == 0 && okEq >= 25, "range diverso dall'atteso in '%s'", c.name);
      OnDeinit(0);
     }
#ifndef EA_V2
   // filtro Min/Max
   {
      cfgReset(); engineReset(PERIOD_H1);
      MaxRangePoints = 100;   // i range delle barre H1 sono molto piu' larghi
      OnInit();
      RandGen g(11, 4);
      long orders = 0;
      Hooks h;
      h.post = [&](const Tick &) { orders = (long)(mk_ordHist.size() + mk_ord.size()); };
      play([&](Tick &t) { return g.next(t); }, h);
      CHECK(orders == 0, "con un massimo di 100 punti non doveva piazzare ordini (%ld)", orders);
      printf("  filtro MaxRangePoints=100: ordini piazzati %ld (atteso 0)\n", orders);
      OnDeinit(0);
   }
#endif
  }

//--- prova 2: ciclo di vita degli ordini e invarianti
static void reportMon(const Mon &m, int weeks)
  {
   double mean, se; int n, wins, sl, tp;
   tradeStats(mean, se, n, wins, sl, tp);
   printf("  tick %ld  posizioni aperte %ld (giorni con piu' di %d: %d)  chiuse %d (SL %d, TP %d, in utile %d)\n", m.ticks, m.fills, MaxTradesPerDay, m.daysOver(MaxTradesPerDay), n, sl, tp, wins);
   printf("  ordini pendenti fuori finestra (tick): %ld   posizioni aperte fuori finestra: %ld   due posizioni insieme (tick): %ld\n", m.stale, m.fillsOutside, m.twoPos);
   printf("  ritardo massimo tra un'esecuzione e la cancellazione dell'ordine gemello: %ld s   SL arretrati: %ld   richieste rifiutate dal broker: %ld\n", m.maxOco, m.slViol, totalRejects());
   printf("  righe di log: %lld in %d settimane (%.1f al giorno)\n", mk_printCount, weeks, (double)mk_printCount / (weeks * 5.0));
   printf("  profitto medio per posizione: %.1f punti (errore standard %.1f)\n", mean, se);
  }
static void runLife()
  {
   const int WEEKS = 26;
   printf("PROVA life (%s): %d settimane di serie casuali, parametri come da file (range massimo alzato a 5000 punti)\n", VER, WEEKS);
   cfgReset(); engineReset(PERIOD_H1);
   OnInit();
   RandGen g(7, WEEKS);
   Mon m;
   m.tol = IS_V3 ? 0 : 1;
   Hooks h;
   h.post = [&](const Tick &k) { m.post(k); };
   play([&](Tick &t) { return g.next(t); }, h);
   reportMon(m, WEEKS);
   if(IS_V3)
     {
      CHECK(m.fills >= 10, "troppe poche posizioni per un test sensato: %ld", m.fills);
      CHECK(m.stale == 0, "ordini pendenti fuori dalla finestra: %ld tick", m.stale);
      CHECK(m.fillsOutside == 0, "posizioni aperte fuori dalla finestra: %ld", m.fillsOutside);
      CHECK(m.twoPos == 0, "due posizioni insieme: %ld", m.twoPos);
      CHECK(m.maxOco == 0, "ordine gemello cancellato in ritardo: %ld s", m.maxOco);
      CHECK(m.slViol == 0, "stop loss arretrati: %ld", m.slViol);
      CHECK(totalRejects() == 0, "richieste rifiutate: %ld", totalRejects());
      CHECK(m.daysOver(MaxTradesPerDay) == 0, "giorni oltre il massimo di posizioni");
     }
   OnDeinit(0);
  }

//--- prova 3: break even e trailing su un percorso costruito a mano
#ifndef EA_V2
struct SlChange { datetime t; double sl; double bid; double profitPts; };
static void runManage()
  {
   printf("PROVA manage (%s): break even e trailing su un rialzo e un ribasso costruiti a mano\n", VER);
   cfgReset(); engineReset(PERIOD_H1);
   MaxRangePoints = 500; UseTakeProfit = false;
   OnInit();
   datetime up0 = dayT(0, 3, 10, 5), up1 = dayT(0, 3, 10, 45), up2 = dayT(0, 3, 12, 0);     // giovedi': su di 800 punti in 40 minuti, poi giu'
   datetime dn0 = dayT(1, 2, 10, 5), dn1 = dayT(1, 2, 10, 45), dn2 = dayT(1, 2, 12, 0);     // mercoledi' della settimana dopo: giu'
   auto f = [&](datetime t) -> double
     {
      if(t >= up0 && t < dayT(0, 4))
        {
         if(t < up1) return lerp(t, up0, up1, calmPx(up0), 1.11000);
         if(t < up2) return lerp(t, up1, up2, 1.11000, 1.10200);
         return 1.10200;
        }
      if(t >= dn0 && t < dayT(1, 3))
        {
         if(t < dn1) return lerp(t, dn0, dn1, calmPx(dn0), 1.09400);
         if(t < dn2) return lerp(t, dn1, dn2, 1.09400, 1.10200);
         return 1.10200;
        }
      return calmPx(t);
     };
   PathGen g(2, f, flatSpr);
   Mon m;
   std::vector<SlChange> ch[2];
   double lastSl = 0;
   ulong tk = 0;
   int which = -1;
   Hooks h;
   h.post = [&](const Tick &k)
     {
      m.post(k);
      if(mk_pos.empty()) { tk = 0; return; }
      MkPos &p = mk_pos[0];
      if(p.ticket != tk) { tk = p.ticket; lastSl = p.sl; which = (p.type == POSITION_TYPE_BUY) ? 0 : 1; SlChange c; c.t = k.t; c.sl = p.sl; c.bid = mk_bid; c.profitPts = 0; ch[which].push_back(c); return; }
      if(std::fabs(p.sl - lastSl) > 1e-9)
        {
         SlChange c; c.t = k.t; c.sl = p.sl; c.bid = (p.type == POSITION_TYPE_BUY) ? mk_bid : mk_ask;
         c.profitPts = ((p.type == POSITION_TYPE_BUY) ? (c.bid - p.price) : (p.price - c.bid)) / _Point;
         ch[which].push_back(c); lastSl = p.sl;
        }
     };
   play([&](Tick &t) { return g.next(t); }, h);
   CHECK(mk_posHist.size() == 2, "attese 2 posizioni (una lunga, una corta), trovate %d", (int)mk_posHist.size());
   for(int side = 0; side < 2 && side < (int)mk_posHist.size(); side++)
     {
      const MkPos *pp = nullptr;
      for(auto &p : mk_posHist) if(p.type == (side == 0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL)) pp = &p;
      CHECK(pp != nullptr, "manca la posizione %s", side == 0 ? "lunga" : "corta");
      if(!pp) continue;
      double sgn = side == 0 ? 1.0 : -1.0;
      auto &c = ch[side];
      printf("  %s: ingresso %.5f, SL iniziale %.5f, %d modifiche dello SL, chiusa a %.5f (%s)\n", side == 0 ? "lunga" : "corta", pp->price, c.empty() ? 0.0 : c[0].sl, (int)c.size() - 1, pp->cprice, pp->reason == 0 ? "stop" : "target");
      CHECK(c.size() >= 4, "poche modifiche dello SL (%d)", (int)c.size());
      if(c.size() < 4) continue;
      double ordPx = 0;
      for(auto &o : mk_ordHist) if(o.state == 1 && o.type == (side == 0 ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP)) ordPx = o.price;
      CHECK(std::fabs(c[0].sl - (ordPx - sgn * 100 * _Point)) < 1e-9, "SL iniziale %.5f invece di prezzo dell'ordine %.5f -+ 100 punti", c[0].sl, ordPx);
      CHECK(std::fabs(c[1].sl - (pp->price + sgn * 10 * _Point)) < 1e-9, "primo spostamento %.5f, atteso break even a ingresso +10 punti = %.5f", c[1].sl, pp->price + sgn * 10 * _Point);
      CHECK(c[1].profitPts >= 100 - 1e-6 && c[1].profitPts < 150, "break even con profitto %.0f punti (atteso fra 100 e 150)", c[1].profitPts);
      for(size_t i = 2; i < c.size(); i++)
        {
         CHECK(sgn * (c[i].sl - c[i - 1].sl) >= 20 * _Point - 1e-9, "passo del trailing %.1f punti (< 20)", sgn * (c[i].sl - c[i - 1].sl) / _Point);
         CHECK(std::fabs(c[i].sl - (c[i].bid - sgn * 30 * _Point)) < 1e-9 || sgn * (c[i].bid - sgn * 30 * _Point - c[i].sl) > 0, "trailing %.5f non e' prezzo -+ 30 punti (%.5f)", c[i].sl, c[i].bid - sgn * 30 * _Point);
         CHECK(c[i].profitPts >= 150 - 1e-6, "trailing attivato con profitto %.0f (< 150)", c[i].profitPts);
        }
      CHECK(pp->reason == 0 && sgn * (pp->cprice - pp->price) > 0, "la posizione doveva chiudersi in utile sullo SL trascinato");
      CHECK(sgn * (c.back().sl - pp->price) > 100 * _Point, "SL finale troppo vicino all'ingresso");
     }
   long mods = 0;
   for(auto &s : mk_log) if(s.find("Posizione ") == 0 && s.find("SL ") != std::string::npos) mods++;
   CHECK(mods <= 60, "troppe richieste di modifica: %ld", mods);
   CHECK(totalRejects() == 0, "richieste rifiutate: %ld", totalRejects());
   CHECK(m.stale == 0 && m.maxOco == 0 && m.slViol == 0, "invarianti violate (fuori finestra %ld, ritardo OCO %ld s, SL arretrati %ld)", m.stale, m.maxOco, m.slViol);
   printf("  modifiche dello SL inviate: %ld, rifiutate: %ld\n", mods, totalRejects());
   OnDeinit(0);
  }

//--- percorso con rottura al rialzo (o al ribasso) in un giorno scelto: dal prezzo calmo alle 10:05 fino a 'top' alle 10:45, poi ritorno
static double breakDay(datetime t, int week, int dow, double top, double backAt, datetime holdUntil)
  {
   datetime a = dayT(week, dow, 10, 5), b = dayT(week, dow, 10, 45), c = dayT(week, dow, 12, 0);
   if(t < a || t >= dayT(week, dow + 1)) return calmPx(t);
   if(t < b) return lerp(t, a, b, calmPx(a), top);
   if(t < holdUntil) return top;
   if(t < c) return lerp(t, holdUntil, c, top, backAt);
   return backAt;
  }
static long ordersOnDay(datetime d0, long &buys, long &sells)
  {
   buys = sells = 0;
   for(int pass = 0; pass < 2; pass++)
     {
      const std::vector<MkOrder> &v = pass ? mk_ord : mk_ordHist;
      for(auto &o : v)
         if(o.setup >= d0 && o.setup < d0 + 86400) { if(o.type == ORDER_TYPE_BUY_STOP) buys++; else sells++; }
     }
   return buys + sells;
  }
static long countLog(const char *needle) { long n = 0; for(auto &l : mk_log) if(l.find(needle) != std::string::npos) n++; return n; }

//--- prova 4: riavvio dell'EA a meta' giornata
static void runRestart()
  {
   printf("PROVA restart (%s): l'EA viene fermato e riavviato a meta' giornata (giovedi' alle 10:20 o 10:40)\n", VER);
   const datetime thu = dayT(0, 3);
   // a) la coppia e' viva
   {
      cfgReset(); engineReset(PERIOD_H1); MaxRangePoints = 500;
      OnInit();
      bool done = false;
      long ordBefore = -1, pairsAfter = -1;
      PathGen g(1, calmPx, flatSpr);
      Hooks h;
      h.pre = [&](const Tick &k) { if(!done && k.t >= dayT(0, 3, 10, 20)) { done = true; ordBefore = (long)mk_ord.size(); OnDeinit(0); OnInit(); } };
      h.post = [&](const Tick &k) { if(done && pairsAfter < 0 && k.t >= dayT(0, 3, 10, 20)) pairsAfter = g_pairsToday; };
      play([&](Tick &t) { return g.next(t); }, h);
      long b, s2;
      ordersOnDay(thu, b, s2);
      printf("  a) riavvio con la coppia viva: prima %ld ordini, coppie lette dopo %ld, ordini piazzati giovedi' %ld BuyStop + %ld SellStop\n", ordBefore, pairsAfter, b, s2);
      CHECK(ordBefore == 2 && pairsAfter == 1 && b == 1 && s2 == 1, "dopo il riavvio non doveva piazzare una seconda coppia");
      OnDeinit(0);
   }
   // b) la posizione e' gia' stata aperta e chiusa al target
   // c) la posizione e' ancora aperta e va gestita dopo il riavvio
   for(int c = 0; c < 2; c++)
     {
      cfgReset(); engineReset(PERIOD_H1); MaxRangePoints = 500;
      UseTakeProfit = (c == 0);
      OnInit();
      bool done = false;
      int posAtRestart = -1, tradesAfter = -1;
      long modsBefore = 0, modsAfter = 0;
      double top = 1.11000;
      datetime hold = dayT(0, 3, 11, 30);
      PathGen g(1, [&](datetime t) { return breakDay(t, 0, 3, top, 1.10200, hold); }, flatSpr);
      Hooks h;
      h.pre = [&](const Tick &k)
        {
         if(!done && k.t >= dayT(0, 3, 10, 40))
           {
            done = true; posAtRestart = (int)mk_pos.size();
            modsBefore = countLog("Posizione ");
            OnDeinit(0); OnInit();
           }
        };
      h.post = [&](const Tick &k) { if(done && tradesAfter < 0 && k.t >= dayT(0, 3, 10, 40)) tradesAfter = g_tradesToday; };
      play([&](Tick &t) { return g.next(t); }, h);
      modsAfter = countLog("Posizione ") - modsBefore;
      long b, s2;
      ordersOnDay(thu, b, s2);
      printf("  %c) %s al riavvio: posizioni aperte %d, trade letti dopo il riavvio %d, ordini piazzati giovedi' %ld+%ld, modifiche dello SL dopo il riavvio %ld, posizioni chiuse %d\n",
             'b' + c, c == 0 ? "posizione chiusa al target" : "posizione ancora aperta", posAtRestart, tradesAfter, b, s2, modsAfter, (int)mk_posHist.size());
      CHECK(tradesAfter == 1, "dopo il riavvio i trade del giorno dovevano risultare 1, risultano %d", tradesAfter);
      CHECK(b == 1 && s2 == 1, "giovedi' doveva esserci una sola coppia (trovati %ld+%ld)", b, s2);
      CHECK(mk_posHist.size() == 1 && mk_pos.empty(), "attesa una posizione, chiusa a fine prova");
      if(c == 0) CHECK(posAtRestart == 0 && mk_posHist[0].reason == 1, "doveva essere gia' chiusa al target");
      else CHECK(posAtRestart == 1 && modsAfter > 3 && mk_posHist[0].cprice > mk_posHist[0].price, "la posizione aperta doveva essere ancora gestita e chiudersi in utile");
      OnDeinit(0);
     }
  }

//--- prova 5: filtro di spread
static void runSpread()
  {
   printf("PROVA spread (%s): spread largo alle 10:00-10:30\n", VER);
   const datetime thu = dayT(0, 3);
   {
      cfgReset(); engineReset(PERIOD_H1); MaxRangePoints = 500;
      OnInit();
      PathGen g(1, calmPx, [](datetime t) { return (t >= dayT(0, 3, 10, 0) && t < dayT(0, 3, 10, 30)) ? 40.0 : 12.0; });
      Hooks h;
      play([&](Tick &t) { return g.next(t); }, h);
      long b, s2;
      ordersOnDay(thu, b, s2);
      datetime first = 0;
      for(auto &o : mk_ordHist) if(o.setup >= thu && o.setup < thu + 86400 && (first == 0 || o.setup < first)) first = o.setup;
      printf("  limite 15%% dello SL (15 punti), spread 40 punti fino alle 10:30: coppia piazzata alle %s, righe di log sullo spread %ld\n", TimeToString(first, TIME_DATE | TIME_MINUTES).c_str(), countLog("Spread"));
      CHECK(b == 1 && s2 == 1, "doveva piazzare una coppia (%ld+%ld)", b, s2);
      CHECK(first >= dayT(0, 3, 10, 30) && first < dayT(0, 3, 10, 31), "coppia piazzata all'ora sbagliata");
      CHECK(countLog("Spread") == 1, "il messaggio sullo spread doveva comparire una volta, %ld", countLog("Spread"));
      OnDeinit(0);
   }
   {
      cfgReset(); engineReset(PERIOD_H1); MaxRangePoints = 500; MaxSpreadPoints = 5;
      OnInit();
      PathGen g(1, calmPx, flatSpr);
      Hooks h;
      play([&](Tick &t) { return g.next(t); }, h);
      printf("  limite assoluto 5 punti con spread 12: ordini piazzati %d (atteso 0)\n", (int)(mk_ordHist.size() + mk_ord.size()));
      CHECK(mk_ordHist.size() + mk_ord.size() == 0, "con spread sopra il limite non doveva piazzare nulla");
      OnDeinit(0);
   }
  }

//--- prova 6: prezzo gia' oltre il livello alle 10:00
static void runChase()
  {
   printf("PROVA chase (%s): alle 10:00 il prezzo e' gia' sopra il massimo del range\n", VER);
   const datetime thu = dayT(0, 3);
   for(int chase = 0; chase < 2; chase++)
     {
      cfgReset(); engineReset(PERIOD_H1); MaxRangePoints = 500;
      ChaseIfBroken = (chase == 1);
      OnInit();
      auto f = [](datetime t) -> double
        {
         if(t >= dayT(0, 3, 9, 50) && t < dayT(0, 3, 10, 0)) return lerp(t, dayT(0, 3, 9, 50), dayT(0, 3, 10, 0), calmPx(dayT(0, 3, 9, 50)), 1.11000);
         if(t >= dayT(0, 3, 10, 0) && t < dayT(0, 3, 11, 0)) return 1.11000;
         if(t >= dayT(0, 3, 11, 0) && t < dayT(0, 3, 12, 0)) return lerp(t, dayT(0, 3, 11, 0), dayT(0, 3, 12, 0), 1.11000, 1.10200);
         return calmPx(t);
        };
      PathGen g(1, f, flatSpr);
      double upSeen = 0, loSeen = 0;
      Hooks h;
      h.post = [&](const Tick &k) { if(k.t >= dayT(0, 3, 10, 0) && k.t < dayT(0, 3, 10, 1)) { upSeen = g_upper; loSeen = g_lower; } };
      play([&](Tick &t) { return g.next(t); }, h);
      long b, s2;
      ordersOnDay(thu, b, s2);
      printf("  ChaseIfBroken=%s: ordini piazzati giovedi' %ld BuyStop + %ld SellStop, righe 'prezzo fuori dai livelli' %ld\n", chase ? "true" : "false", b, s2, countLog("Prezzo fuori"));
      if(!chase)
        {
         CHECK(b == 0 && s2 == 0, "senza chase non doveva piazzare ordini con il prezzo gia' fuori (%ld+%ld)", b, s2);
         CHECK(countLog("Prezzo fuori") == 1, "il messaggio doveva comparire una volta");
        }
      else
        {
         CHECK(b == 1 && s2 == 1, "con chase doveva piazzare la coppia (%ld+%ld)", b, s2);
         for(auto &o : mk_ordHist)
            if(o.setup >= thu && o.setup < thu + 86400)
              {
               if(o.type == ORDER_TYPE_BUY_STOP)
                 {
                  CHECK(std::fabs(o.price - 1.11022) < 1e-9, "BuyStop a %.5f invece di ask + 10 punti = 1.11022", o.price);
                  CHECK(std::fabs(o.sl - (o.price - 100 * _Point)) < 1e-9, "SL calcolato dal prezzo corretto");
                 }
               else
                  CHECK(std::fabs(o.price - (loSeen - 20 * _Point)) < 1e-9, "SellStop a %.5f invece di minimo - 20 punti = %.5f", o.price, loSeen - 20 * _Point);
              }
        }
      (void)upSeen;
      OnDeinit(0);
     }
  }

//--- prova 7: parametri casuali e vincoli del broker casuali
static void runRandom()
  {
   const int SEEDS = 24, WEEKS = 12;
   printf("PROVA random (%s): %d combinazioni casuali di parametri e vincoli del broker, %d settimane ciascuna\n", VER, SEEDS, WEEKS);
   long totFills = 0, totTicks = 0, skipped = 0, worstLogsPerDay = 0;
   int perMode[3] = {0, 0, 0};
   for(int seed = 1; seed <= SEEDS; seed++)
     {
      std::mt19937_64 r(5000 + seed);
      auto ri = [&](int a, int b) { return a + (int)(r() % (uint64_t)(b - a + 1)); };
      cfgReset();
      int tfs[3] = {PERIOD_M15, PERIOD_H1, PERIOD_H4};
      int digits = (ri(0, 3) == 0) ? 3 : 5;
      engineReset(tfs[ri(0, 2)], digits);
      long stopsC[3] = {0, 20, 50};
      mk_sym.stops = stopsC[ri(0, 2)];
      mk_sym.freeze = ri(0, 2) == 2 ? 10 : 0;
      mk_sym.expMode = ri(0, 2) == 0 ? 1 : 15;
      mk_sym.fillMode = ri(1, 3);
      mk_sym.vstep = ri(0, 1) ? 0.01 : 0.1;
      mk_sym.vmin = mk_sym.vstep;
      RangeMode = (ENUM_RANGE_MODE)ri(0, 2);
      perMode[RangeMode]++;
      Timeframe = ri(0, 1) ? PERIOD_CURRENT : PERIOD_H1;
      RangeDaysBack = RangeMode == RANGE_PREV_D1 ? ri(1, 3) : ri(0, 3);
      RangeBarsLookback = ri(4, 40);
      RangeHourStart = ri(0, 23); RangeMinuteStart = ri(0, 3) * 15; RangeHourEnd = ri(0, 24); RangeMinuteEnd = RangeHourEnd == 24 ? 0 : ri(0, 3) * 15;
      RangeDaySpan = ri(1, 3);
      MinRangePoints = ri(0, 1) ? 30 : 100; MaxRangePoints = ri(0, 2) == 0 ? 600 : 3000;
      TradeHourStart = ri(0, 22); TradeMinuteStart = ri(0, 3) * 15;
      int lenMin = ri(1, 5) * 60 + ri(0, 3) * 15;
      int endMin = (TradeHourStart * 60 + TradeMinuteStart + lenMin) % 1440;
      TradeHourEnd = endMin / 60; TradeMinuteEnd = endMin % 60;
      ExpireExtraMinutes = ri(0, 2) == 0 ? ri(0, 45) : 0;
      MaxTradesPerDay = ri(1, 3);
      PendingOrderOffsetPoints = ri(0, 50);
      ChaseIfBroken = ri(0, 3) == 0;
      double minDist = (double)mk_sym.stops + 10.0;
      StopLossPoints = std::max(minDist, (double)ri(40, 300));
      UseTakeProfit = ri(0, 3) != 0;
      TakeProfitPoints = std::max(minDist, (double)ri(40, 600));
      MaxSpreadPoints = ri(0, 3) == 0 ? ri(10, 30) : 0;
      MaxSpreadPctOfSL = ri(0, 2) == 0 ? 0 : 15;
      UsaBreakEven = ri(0, 1); BreakEvenAttivazione = ri(50, 200); BreakEvenOffset = ri(0, 30);
      UsaTrailingStop = ri(0, 1); TrailingStartProfit = ri(80, 300); TrailingStep = ri(5, 50); TrailingOffset = ri(20, 100);
      LotSize = mk_sym.vmin * ri(1, 4) + (ri(0, 1) ? 0.003 : 0.0);   // anche lotti non multipli del passo
      if(OnInit() != INIT_SUCCEEDED) { skipped++; continue; }
      bool coversOpen = false;
      {
         int s = TradeHourStart * 60 + TradeMinuteStart, e = TradeHourEnd * 60 + TradeMinuteEnd;
         coversOpen = (s == 0) || (s > e);   // la finestra contiene il primo tick della settimana (salto sul lunedi')
      }
      RandGen g(seed, WEEKS);
      Mon m;
      Hooks h;
      h.post = [&](const Tick &k) { m.post(k); };
      play([&](Tick &t) { return g.next(t); }, h);
      long logsPerDay = mk_printCount / (WEEKS * 5);
      worstLogsPerDay = std::max(worstLogsPerDay, logsPerDay);
      totFills += m.fills; totTicks += m.ticks;
      bool ok = m.stale == 0 && m.fillsOutside == 0 && (coversOpen || m.twoPos == 0) && m.maxOco == 0 && m.slViol == 0 && totalRejects() == 0 && m.daysOver(MaxTradesPerDay) == 0 && logsPerDay <= 60;
      if(!ok)
        {
         printf("  seed %d (modo %d, stops %ld, exp %ld, fill %ld, passo %.2f, cifre %d): ordini fuori finestra %ld, posizioni fuori finestra %ld, due posizioni %ld, ritardo OCO %ld s, SL arretrati %ld, rifiuti %ld, giorni oltre il massimo %d, log/giorno %ld\n",
                seed, (int)RangeMode, mk_sym.stops, mk_sym.expMode, mk_sym.fillMode, mk_sym.vstep, digits, m.stale, m.fillsOutside, m.twoPos, m.maxOco, m.slViol, totalRejects(), m.daysOver(MaxTradesPerDay), logsPerDay);
         for(auto &kv : mk_rejects) printf("    rifiuto %d x %lld\n", kv.first, kv.second);
         int shown = 0;
         for(auto &l : mk_log) if((l.find("Errore") != std::string::npos) && shown++ < 4) printf("    log: %s\n", l.c_str());
        }
      CHECK(ok, "invarianti violate nel caso %d", seed);
      OnDeinit(0);
     }
   printf("  %d casi eseguiti (%ld saltati per parametri non validi), modi: barre %d, orario %d, D1 %d; posizioni aperte in tutto %ld su %ld tick; massimo di righe di log al giorno %ld\n",
          SEEDS - (int)skipped, skipped, perMode[0], perMode[1], perMode[2], totFills, totTicks, worstLogsPerDay);
   CHECK(totFills >= 150, "troppo poche posizioni per essere un test significativo: %ld", totFills);
  }

//--- prova 8: serie senza tendenza, nessun vantaggio nascosto
static void runPnl()
  {
   const int WEEKS = 104, SEEDS = 6;
   printf("PROVA pnl (%s): %d serie senza tendenza da %d settimane, parametri come da file: non deve esserci un vantaggio\n", VER, SEEDS, WEEKS);
   double s = 0, s2 = 0; long n = 0; long sl = 0, tp = 0;
   for(int seed = 1; seed <= SEEDS; seed++)
     {
      cfgReset(); engineReset(PERIOD_H1);
      OnInit();
      RandGen g(900 + seed, WEEKS);
      Hooks h;
      play([&](Tick &t) { return g.next(t); }, h);
      for(auto &p : mk_posHist)
        {
         double pts = ((p.type == POSITION_TYPE_BUY) ? (p.cprice - p.price) : (p.price - p.cprice)) / _Point;
         s += pts; s2 += pts * pts; n++;
         if(p.reason == 0) sl++; else tp++;
        }
      OnDeinit(0);
     }
   double mean = s / n, se = std::sqrt((s2 - s * s / n) / (n - 1) / n);
   printf("  %ld posizioni (SL %ld, TP %ld): profitto medio %.1f punti per posizione, errore standard %.1f; con SL di 100 punti sono %.2f R per posizione\n", n, sl, tp, mean, se, mean / 100.0);
   CHECK(mean < 3.0 * se, "profitto medio %.1f positivo in modo significativo su una serie senza tendenza: errore nel simulatore o guardata nel futuro", mean);
  }
//--- prova 9: broker senza scadenza specifica degli ordini: deve cancellarli l'EA
static void runExpiry()
  {
   printf("PROVA expiry (%s): il simbolo accetta solo ordini GTC (niente scadenza dal broker), vita extra di 20 minuti\n", VER);
   cfgReset(); engineReset(PERIOD_H1);
   mk_sym.expMode = SYMBOL_EXPIRATION_GTC;
   ExpireExtraMinutes = 20;
   OnInit();
   RandGen g(31, 12);
   Mon m;
   Hooks h;
   h.post = [&](const Tick &k) { m.post(k); };
   play([&](Tick &t) { return g.next(t); }, h);
   long expired = 0, byEa = countLog("fuori dalla finestra");
   for(auto &o : mk_ordHist) if(o.state == 3) expired++;
   printf("  ordini scaduti dal broker %ld, cancellati dall'EA %ld, ordini pendenti fuori finestra (tick) %ld, posizioni %ld\n", expired, byEa, m.stale, m.fills);
   CHECK(expired == 0, "il broker non doveva far scadere nulla");
   CHECK(byEa > 20, "l'EA doveva cancellare gli ordini rimasti (%ld)", byEa);
   CHECK(m.stale == 0 && m.fillsOutside == 0, "ordini o posizioni fuori finestra (%ld, %ld)", m.stale, m.fillsOutside);
   OnDeinit(0);
  }
#endif

//--- prove sul confronto con la v2 (girano su tutte e due)
static void runHeld()
  {
   printf("PROVA held (%s): posizione ancora aperta da ieri (nessun TP, BE e trailing spenti), cosa succede il giorno dopo\n", VER);
   cfgReset(); engineReset(PERIOD_H1);
   UseTakeProfit = false; UsaBreakEven = false; UsaTrailingStop = false; MaxRangePoints = 5000;
   OnInit();
   datetime a = dayT(0, 3, 10, 5), b = dayT(0, 3, 10, 45);
   PathGen g(1, [&](datetime t) { return t < a ? calmPx(t) : lerp(t, a, b, calmPx(a), 1.11000); }, flatSpr);
   Hooks h;
   play([&](Tick &t) { return g.next(t); }, h);
   long fb = 0, fs = 0;
   for(int pass = 0; pass < 2; pass++)
      for(auto &o : (pass ? mk_ord : mk_ordHist))
         if(o.setup >= dayT(0, 4) && o.setup < dayT(0, 5)) { if(o.type == ORDER_TYPE_BUY_STOP) fb++; else fs++; }
   double minLife = 1e9, maxLife = 0;
   for(auto &o : mk_ordHist)
      if(o.setup >= dayT(0, 4) && o.setup < dayT(0, 5) && o.done > 0) { minLife = std::min(minLife, (double)(o.done - o.setup)); maxLife = std::max(maxLife, (double)(o.done - o.setup)); }
   printf("  posizioni ancora aperte a fine prova %d; ordini piazzati venerdi' mentre la posizione di giovedi' e' aperta: %ld BuyStop + %ld SellStop", (int)mk_pos.size(), fb, fs);
   if(fb + fs > 0) printf(", vita %.0f-%.0f s", minLife, maxLife);
   printf("\n");
   if(IS_V3) CHECK(fb + fs == 0 && mk_pos.size() == 1, "con una posizione aperta non doveva piazzare nulla");
  }
static void runStops()
  {
   printf("PROVA stops (%s): livello minimo degli stop del broker a 50 punti, 26 settimane\n", VER);
   cfgReset(); engineReset(PERIOD_H1);
   mk_sym.stops = 50;
   OnInit();
   RandGen g(7, 26);
   Hooks h;
   play([&](Tick &t) { return g.next(t); }, h);
   printf("  richieste inviate al broker %lld, rifiutate %ld", mk_sendCount, totalRejects());
   for(auto &kv : mk_rejects) printf(" (codice %d: %lld)", kv.first, kv.second);
   printf("; posizioni aperte %d\n", (int)(mk_posHist.size() + mk_pos.size()));
   if(IS_V3) CHECK(totalRejects() == 0, "richieste rifiutate: %ld", totalRejects());
  }
static void runSpam()
  {
   printf("PROVA spam (%s): range sempre scartato (massimo 100 punti), 4 settimane: righe di log e richieste\n", VER);
   cfgReset(); engineReset(PERIOD_H1);
   MaxRangePoints = 100;
   OnInit();
   RandGen g(7, 4);
   Hooks h;
   play([&](Tick &t) { return g.next(t); }, h);
   printf("  righe di log %lld in 20 giorni (%.1f al giorno)\n", mk_printCount, mk_printCount / 20.0);
   if(IS_V3) CHECK(mk_printCount / 20.0 < 10, "troppe righe di log");
  }
#ifdef EA_V2
static void runLogs()
  {
   cfgReset(); engineReset(PERIOD_H1);
   OnInit();
   RandGen g(7, 26);
   Hooks h;
   play([&](Tick &t) { return g.next(t); }, h);
   std::map<std::string, long> cnt;
   for(auto &l : mk_log) cnt[l.substr(0, 28)]++;
   std::vector<std::pair<long, std::string>> v;
   for(auto &kv : cnt) v.push_back({kv.second, kv.first});
   std::sort(v.rbegin(), v.rend());
   printf("PROVA logs (v2): messaggi piu' frequenti su 26 settimane (%lld righe in tutto)\n", mk_printCount);
   for(size_t i = 0; i < v.size() && i < 8; i++) printf("  %6ld  %s\n", v[i].first, v[i].second.c_str());
  }
#endif

int main(int argc, char **argv)
  {
   const char *what = argc > 1 ? argv[1] : "life";
   if(!strcmp(what, "range")) runRange();
   else if(!strcmp(what, "held")) runHeld();
   else if(!strcmp(what, "stops")) runStops();
   else if(!strcmp(what, "spam")) runSpam();
#ifdef EA_V2
   else if(!strcmp(what, "logs")) runLogs();
#endif
   else if(!strcmp(what, "life")) runLife();
#ifndef EA_V2
   else if(!strcmp(what, "manage")) runManage();
   else if(!strcmp(what, "restart")) runRestart();
   else if(!strcmp(what, "spread")) runSpread();
   else if(!strcmp(what, "chase")) runChase();
   else if(!strcmp(what, "random")) runRandom();
   else if(!strcmp(what, "pnl")) runPnl();
   else if(!strcmp(what, "expiry")) runExpiry();
#endif
   else { printf("prova sconosciuta: %s\n", what); return 2; }
   printf("%s: %d controlli, %d falliti\n", what, t_checks, t_fail);
   return t_fail ? 1 : 0;
  }
