// Finto MT5 per il banco di prova di MultiDayRangeBreakout: mercato (barre da tick), broker (ordini stop, posizioni,
// SL/TP, scadenze, storia) e le API di trading usate dall'EA. Imita le regole di MT5 che contano per questo EA;
// non e' MT5: serve a provare la logica di controllo, non a misurare la redditivita'.
#pragma once
#define Print MQLRT_Print_
#define Comment MQLRT_Comment_
#define PrintFormat MQLRT_PrintFormat_
#include "../../../MarketProfiler/tests/mql_rt.h"
#undef Print
#undef Comment
#undef PrintFormat
#include <functional>
#include <map>
#include <type_traits>

typedef unsigned int color;
static const color clrDodgerBlue = 0xFF901E, clrTomato = 0x4763FF;
#define INIT_SUCCEEDED 0
#define INIT_PARAMETERS_INCORRECT 2
#define ULONG_MAX_ 18446744073709551615ULL

//--- log
static long long mk_printCount = 0;
static long long mk_commentCount = 0;
static std::vector<std::string> mk_log;
template<class T> std::string mk_ts(const T &x)
  {
   if constexpr(std::is_floating_point<T>::value)
     { char b[64]; snprintf(b, sizeof b, "%.8g", (double)x); return b; }
   else if constexpr(std::is_convertible<T, std::string>::value)
      return std::string(x);
   else
      return std::to_string((long long)x);
  }
template<class... A> void Print(A... a)
  {
   mk_printCount++;
   if(mk_log.size() < 200000)
     {
      std::string s;
      ((s += mk_ts(a)), ...);
      mk_log.push_back(s);
     }
  }
template<class... A> void Comment(A...) { mk_commentCount++; }
template<class T> string EnumToString(T x) { return string(std::to_string((long long)x)); }
inline int StringCompare(const string &a, const string &b) { int c = a.compare(b); return c < 0 ? -1 : (c > 0 ? 1 : 0); }
inline double NormalizeDouble(double v, int d) { double p = std::pow(10.0, d); return std::round(v * p) / p; }
inline int GetLastError() { return 0; }
inline void ResetLastError() {}

//--- costanti MQL5
enum ENUM_TIMEFRAMES { PERIOD_CURRENT = 0, PERIOD_M1 = 1, PERIOD_M5 = 5, PERIOD_M15 = 15, PERIOD_M30 = 30, PERIOD_H1 = 16385, PERIOD_H4 = 16388, PERIOD_D1 = 16408, PERIOD_W1 = 32769 };
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY = 0, ORDER_TYPE_SELL = 1, ORDER_TYPE_BUY_LIMIT = 2, ORDER_TYPE_SELL_LIMIT = 3, ORDER_TYPE_BUY_STOP = 4, ORDER_TYPE_SELL_STOP = 5 };
enum ENUM_POSITION_TYPE { POSITION_TYPE_BUY = 0, POSITION_TYPE_SELL = 1 };
enum ENUM_ORDER_TYPE_TIME { ORDER_TIME_GTC = 0, ORDER_TIME_DAY = 1, ORDER_TIME_SPECIFIED = 2, ORDER_TIME_SPECIFIED_DAY = 3 };
enum ENUM_ORDER_TYPE_FILLING { ORDER_FILLING_FOK = 0, ORDER_FILLING_IOC = 1, ORDER_FILLING_RETURN = 2 };
enum ENUM_TRADE_REQUEST_ACTIONS { TRADE_ACTION_DEAL = 1, TRADE_ACTION_PENDING = 5, TRADE_ACTION_SLTP = 6, TRADE_ACTION_MODIFY = 7, TRADE_ACTION_REMOVE = 8 };
enum { TRADE_RETCODE_PLACED = 10008, TRADE_RETCODE_DONE = 10009, TRADE_RETCODE_INVALID = 10013, TRADE_RETCODE_INVALID_VOLUME = 10014, TRADE_RETCODE_INVALID_PRICE = 10015,
       TRADE_RETCODE_INVALID_STOPS = 10016, TRADE_RETCODE_TRADE_DISABLED = 10017, TRADE_RETCODE_INVALID_EXPIRATION = 10022, TRADE_RETCODE_NO_CHANGES = 10025, TRADE_RETCODE_INVALID_FILL = 10030 };
enum { SYMBOL_TRADE_MODE_FULL = 4 };
enum { SYMBOL_EXPIRATION_GTC = 1, SYMBOL_EXPIRATION_DAY = 2, SYMBOL_EXPIRATION_SPECIFIED = 4, SYMBOL_EXPIRATION_SPECIFIED_DAY = 8 };
enum { SYMBOL_FILLING_FOK = 1, SYMBOL_FILLING_IOC = 2 };
enum { DEAL_ENTRY_IN = 0, DEAL_ENTRY_OUT = 1 };
enum { OBJ_HLINE = 1, OBJPROP_COLOR = 1, OBJPROP_STYLE = 2, OBJPROP_SELECTABLE = 3, OBJPROP_PRICE = 4, STYLE_DASH = 1 };
enum { MQL_TRADE_ALLOWED = 1, MQL_TESTER = 2, MQL_VISUAL_MODE = 3, TERMINAL_TRADE_ALLOWED = 4, ACCOUNT_TRADE_ALLOWED = 5 };
enum MkProp
  {
   SYMBOL_ASK = 100, SYMBOL_BID, SYMBOL_POINT, SYMBOL_TRADE_TICK_SIZE, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL,
   SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX, SYMBOL_VOLUME_STEP, SYMBOL_TRADE_MODE, SYMBOL_EXPIRATION_MODE, SYMBOL_FILLING_MODE,
   ORDER_MAGIC = 200, ORDER_TYPE, ORDER_TICKET, ORDER_TIME_SETUP, ORDER_TIME_EXPIRATION, ORDER_TYPE_TIME, ORDER_STATE, ORDER_SYMBOL, ORDER_COMMENT,
   ORDER_PRICE_OPEN, ORDER_SL, ORDER_TP, ORDER_VOLUME_CURRENT,
   POSITION_MAGIC = 300, POSITION_TYPE, POSITION_TICKET, POSITION_SYMBOL, POSITION_PRICE_OPEN, POSITION_SL, POSITION_TP, POSITION_VOLUME, POSITION_TIME,
   DEAL_MAGIC = 400, DEAL_ENTRY, DEAL_SYMBOL, DEAL_TYPE, DEAL_TIME, DEAL_PRICE, DEAL_VOLUME
  };

//--- simbolo
struct MkSym
  {
   double point = 0.00001, tick = 0.00001, vmin = 0.01, vmax = 100.0, vstep = 0.01;
   int digits = 5;
   long stops = 0, freeze = 0, expMode = 15, fillMode = 3, tradeMode = 4;
  };
static MkSym mk_sym;
static string _Symbol("EURUSD");
static double _Point = 0.00001;
static int _Digits = 5;
static double mk_bid = 0.0, mk_ask = 0.0;
static datetime mk_now = 0;
static int mk_chartTF = PERIOD_H1;
inline datetime TimeCurrent() { return mk_now; }
inline datetime TimeTradeServer() { return mk_now; }
inline unsigned int GetTickCount() { return (unsigned int)(mk_now * 1000); }
inline int MQLInfoInteger(int p) { return p == MQL_TRADE_ALLOWED ? 1 : (p == MQL_TESTER ? 1 : 0); }
inline int TerminalInfoInteger(int) { return 1; }
inline int AccountInfoInteger(int) { return 1; }
inline double SymbolInfoDouble(const string &, int p)
  {
   switch(p)
     {
      case SYMBOL_ASK: return mk_ask;
      case SYMBOL_BID: return mk_bid;
      case SYMBOL_POINT: return mk_sym.point;
      case SYMBOL_TRADE_TICK_SIZE: return mk_sym.tick;
      case SYMBOL_VOLUME_MIN: return mk_sym.vmin;
      case SYMBOL_VOLUME_MAX: return mk_sym.vmax;
      case SYMBOL_VOLUME_STEP: return mk_sym.vstep;
     }
   return 0.0;
  }
inline long SymbolInfoInteger(const string &, int p)
  {
   switch(p)
     {
      case SYMBOL_TRADE_STOPS_LEVEL: return mk_sym.stops;
      case SYMBOL_TRADE_FREEZE_LEVEL: return mk_sym.freeze;
      case SYMBOL_TRADE_MODE: return mk_sym.tradeMode;
      case SYMBOL_EXPIRATION_MODE: return mk_sym.expMode;
      case SYMBOL_FILLING_MODE: return mk_sym.fillMode;
     }
   return 0;
  }

//--- serie di barre costruite dai tick (indice 0 = barra in formazione)
struct MkBar { datetime t; double o, h, l, c; };
struct MkSeries { int sec; std::vector<MkBar> b; };
static std::vector<MkSeries> mk_series;
inline int mk_tfsec(int tf)
  {
   switch(tf)
     {
      case PERIOD_M1: return 60;
      case PERIOD_M5: return 300;
      case PERIOD_M15: return 900;
      case PERIOD_M30: return 1800;
      case PERIOD_H1: return 3600;
      case PERIOD_H4: return 14400;
      case PERIOD_D1: return 86400;
     }
   return 0;
  }
inline MkSeries *mk_get(int tf)
  {
   if(tf == 0)
      tf = mk_chartTF;
   int s = mk_tfsec(tf);
   for(auto &x : mk_series)
      if(x.sec == s)
         return &x;
   return nullptr;
  }
inline void mk_initSeries()
  {
   mk_series.clear();
   int tfs[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   for(int tf : tfs)
     {
      MkSeries s;
      s.sec = mk_tfsec(tf);
      mk_series.push_back(s);
     }
  }
inline void mk_updateSeries(datetime t, double bid)
  {
   for(auto &s : mk_series)
     {
      datetime o = t - (t % s.sec);
      if(s.b.empty() || s.b.back().t != o)
        {
         MkBar b;
         b.t = o; b.o = b.h = b.l = b.c = bid;
         s.b.push_back(b);
        }
      else
        {
         MkBar &b = s.b.back();
         if(bid > b.h) b.h = bid;
         if(bid < b.l) b.l = bid;
         b.c = bid;
        }
     }
  }
inline double iHigh(const string &, int tf, int sh) { MkSeries *s = mk_get(tf); if(!s || sh < 0 || sh >= (int)s->b.size()) return 0.0; return s->b[s->b.size() - 1 - sh].h; }
inline double iLow(const string &, int tf, int sh) { MkSeries *s = mk_get(tf); if(!s || sh < 0 || sh >= (int)s->b.size()) return 0.0; return s->b[s->b.size() - 1 - sh].l; }
inline double iOpen(const string &, int tf, int sh) { MkSeries *s = mk_get(tf); if(!s || sh < 0 || sh >= (int)s->b.size()) return 0.0; return s->b[s->b.size() - 1 - sh].o; }
inline double iClose(const string &, int tf, int sh) { MkSeries *s = mk_get(tf); if(!s || sh < 0 || sh >= (int)s->b.size()) return 0.0; return s->b[s->b.size() - 1 - sh].c; }
inline datetime iTime(const string &, int tf, int sh) { MkSeries *s = mk_get(tf); if(!s || sh < 0 || sh >= (int)s->b.size()) return 0; return s->b[s->b.size() - 1 - sh].t; }
inline int Bars(const string &, int tf) { MkSeries *s = mk_get(tf); return s ? (int)s->b.size() : 0; }
// indice della barra la cui apertura e' <= time (la piu' vicina precedente se non esiste una barra a quell'istante con exact=false)
inline int iBarShift(const string &, int tf, datetime time, bool exact = false)
  {
   MkSeries *s = mk_get(tf);
   if(!s || s->b.empty()) return -1;
   int lo = 0, hi = (int)s->b.size() - 1, found = -1;
   while(lo <= hi)
     {
      int m = (lo + hi) / 2;
      if(s->b[m].t <= time) { found = m; lo = m + 1; } else hi = m - 1;
     }
   if(found < 0) return -1;
   if(exact && !(time < s->b[found].t + s->sec)) return -1;
   return (int)s->b.size() - 1 - found;
  }

//--- richieste e risultati di trading
struct MqlTradeRequest
  {
   int action = 0; ulong magic = 0; ulong order = 0; std::string symbol; double volume = 0, price = 0, stoplimit = 0, sl = 0, tp = 0;
   ulong deviation = 0; int type = 0, type_filling = 0, type_time = 0; datetime expiration = 0; std::string comment; ulong position = 0, position_by = 0;
  };
struct MqlTradeResult
  {
   unsigned int retcode = 0; ulong deal = 0, order = 0; double volume = 0, price = 0, bid = 0, ask = 0; std::string comment; unsigned int request_id = 0; int retcode_external = 0;
  };
inline void ZeroMemory(MqlTradeRequest &r) { r = MqlTradeRequest(); }
inline void ZeroMemory(MqlTradeResult &r) { r = MqlTradeResult(); }

struct MkOrder { ulong ticket; int type; double price, sl, tp, vol; datetime setup, expiry, done; int ttype; long magic; std::string sym, comment; int state; };   // state: 0 attivo, 1 eseguito, 2 cancellato, 3 scaduto
struct MkPos { ulong ticket; int type; double price, sl, tp, vol; datetime time; long magic; std::string sym; double cprice; datetime ctime; int reason; double maxfav; };   // reason: 0 SL 1 TP
struct MkDeal { ulong ticket, order; int entry, type; long magic; std::string sym; datetime time; double price, vol; };
static std::vector<MkOrder> mk_ord, mk_ordHist;
static std::vector<MkPos> mk_pos, mk_posHist;
static std::vector<MkDeal> mk_deals;
static ulong mk_nextTicket = 1000;
static int mk_selOrd = -1, mk_selPos = -1;
static long long mk_sendCount = 0;
static std::map<int, long long> mk_rejects;
static std::vector<MkOrder> hs_ord;
static std::vector<MkDeal> hs_deals;

inline void mk_resetBroker()
  {
   mk_ord.clear(); mk_ordHist.clear(); mk_pos.clear(); mk_posHist.clear(); mk_deals.clear();
   mk_nextTicket = 1000; mk_selOrd = mk_selPos = -1; mk_sendCount = 0; mk_rejects.clear(); hs_ord.clear(); hs_deals.clear();
   mk_printCount = 0; mk_commentCount = 0; mk_log.clear();
  }

//--- esecuzione
inline bool OrderSend(const MqlTradeRequest &rq, MqlTradeResult &rs)
  {
   rs = MqlTradeResult();
   rs.bid = mk_bid; rs.ask = mk_ask;
   mk_sendCount++;
   auto fail = [&](int rc) { rs.retcode = (unsigned int)rc; rs.comment = "rifiutato"; mk_rejects[rc]++; return false; };
   double pt = mk_sym.point, stopsD = mk_sym.stops * pt, ts = mk_sym.tick;
   if(rq.action == TRADE_ACTION_PENDING)
     {
      if(rq.symbol != std::string(_Symbol)) return fail(TRADE_RETCODE_INVALID);
      if(rq.type != ORDER_TYPE_BUY_STOP && rq.type != ORDER_TYPE_SELL_STOP) return fail(TRADE_RETCODE_INVALID);
      double q = rq.volume / mk_sym.vstep;
      if(rq.volume < mk_sym.vmin - 1e-12 || rq.volume > mk_sym.vmax + 1e-12 || std::fabs(q - std::round(q)) > 1e-6) return fail(TRADE_RETCODE_INVALID_VOLUME);
      bool buy = (rq.type == ORDER_TYPE_BUY_STOP);
      if(buy ? !(rq.price - mk_ask >= stopsD + ts * 0.5) : !(mk_bid - rq.price >= stopsD + ts * 0.5)) return fail(TRADE_RETCODE_INVALID_PRICE);
      if(std::fabs(rq.price / ts - std::round(rq.price / ts)) > 1e-6) return fail(TRADE_RETCODE_INVALID_PRICE);
      if(rq.sl > 0 && (buy ? !(rq.sl <= rq.price - stopsD - ts * 0.5) : !(rq.sl >= rq.price + stopsD + ts * 0.5))) return fail(TRADE_RETCODE_INVALID_STOPS);
      if(rq.tp > 0 && (buy ? !(rq.tp >= rq.price + stopsD + ts * 0.5) : !(rq.tp <= rq.price - stopsD - ts * 0.5))) return fail(TRADE_RETCODE_INVALID_STOPS);
      if(rq.type_time == ORDER_TIME_SPECIFIED)
        {
         if(!(mk_sym.expMode & SYMBOL_EXPIRATION_SPECIFIED) || rq.expiration <= mk_now) return fail(TRADE_RETCODE_INVALID_EXPIRATION);
        }
      else if(rq.type_time == ORDER_TIME_GTC && !(mk_sym.expMode & SYMBOL_EXPIRATION_GTC)) return fail(TRADE_RETCODE_INVALID_EXPIRATION);
      if(rq.type_filling == ORDER_FILLING_FOK && !(mk_sym.fillMode & SYMBOL_FILLING_FOK)) return fail(TRADE_RETCODE_INVALID_FILL);
      if(rq.type_filling == ORDER_FILLING_IOC && !(mk_sym.fillMode & SYMBOL_FILLING_IOC)) return fail(TRADE_RETCODE_INVALID_FILL);
      MkOrder o;
      o.ticket = mk_nextTicket++; o.type = rq.type; o.price = rq.price; o.sl = rq.sl; o.tp = rq.tp; o.vol = rq.volume;
      o.setup = mk_now; o.expiry = rq.expiration; o.done = 0; o.ttype = rq.type_time; o.magic = (long)rq.magic; o.sym = rq.symbol; o.comment = rq.comment; o.state = 0;
      mk_ord.push_back(o);
      rs.order = o.ticket; rs.retcode = TRADE_RETCODE_DONE;
      return true;
     }
   if(rq.action == TRADE_ACTION_REMOVE)
     {
      for(size_t i = 0; i < mk_ord.size(); i++)
         if(mk_ord[i].ticket == rq.order)
           {
            MkOrder o = mk_ord[i];
            o.state = 2; o.done = mk_now;
            mk_ordHist.push_back(o);
            mk_ord.erase(mk_ord.begin() + i);
            rs.order = rq.order; rs.retcode = TRADE_RETCODE_DONE;
            return true;
           }
      return fail(TRADE_RETCODE_INVALID);
     }
   if(rq.action == TRADE_ACTION_SLTP)
     {
      for(auto &p : mk_pos)
         if(p.ticket == rq.position)
           {
            bool buy = (p.type == POSITION_TYPE_BUY);
            if(std::fabs(rq.sl - p.sl) < ts * 0.5 && std::fabs(rq.tp - p.tp) < ts * 0.5) return fail(TRADE_RETCODE_NO_CHANGES);
            if(rq.sl > 0 && (buy ? !(rq.sl <= mk_bid - stopsD - ts * 0.5) : !(rq.sl >= mk_ask + stopsD + ts * 0.5))) return fail(TRADE_RETCODE_INVALID_STOPS);
            if(rq.tp > 0 && (buy ? !(rq.tp >= mk_bid + stopsD + ts * 0.5) : !(rq.tp <= mk_ask - stopsD - ts * 0.5))) return fail(TRADE_RETCODE_INVALID_STOPS);
            p.sl = rq.sl; p.tp = rq.tp;
            rs.retcode = TRADE_RETCODE_DONE;
            return true;
           }
      return fail(TRADE_RETCODE_INVALID);
     }
   return fail(TRADE_RETCODE_INVALID);
  }

class CTrade
  {
   ulong m_magic, m_dev;
   int m_fill;
   MqlTradeRequest m_rq;
   MqlTradeResult m_rs;
   bool Pend(int type, double volume, double price, const string &symbol, double sl, double tp, int tt, datetime exp, const string &comment)
     {
      m_rq = MqlTradeRequest();
      m_rq.action = TRADE_ACTION_PENDING; m_rq.symbol = symbol.empty() ? std::string(_Symbol) : std::string(symbol); m_rq.volume = volume; m_rq.type = type; m_rq.price = price;
      m_rq.sl = sl; m_rq.tp = tp; m_rq.type_time = tt; m_rq.expiration = exp; m_rq.comment = comment; m_rq.magic = m_magic; m_rq.deviation = m_dev; m_rq.type_filling = m_fill;
      return OrderSend(m_rq, m_rs);
     }
public:
   CTrade() : m_magic(0), m_dev(0), m_fill(ORDER_FILLING_FOK) {}
   void SetExpertMagicNumber(ulong m) { m_magic = m; }
   void SetDeviationInPoints(ulong d) { m_dev = d; }
   void SetTypeFilling(int f) { m_fill = f; }
   bool SetTypeFillingBySymbol(const string &)
     {
      if(mk_sym.fillMode & SYMBOL_FILLING_FOK) m_fill = ORDER_FILLING_FOK;
      else if(mk_sym.fillMode & SYMBOL_FILLING_IOC) m_fill = ORDER_FILLING_IOC;
      else m_fill = ORDER_FILLING_RETURN;
      return true;
     }
   bool BuyStop(double volume, double price, const string &symbol = "", double sl = 0.0, double tp = 0.0, int tt = ORDER_TIME_GTC, datetime exp = 0, const string &comment = "")
     { return Pend(ORDER_TYPE_BUY_STOP, volume, price, symbol, sl, tp, tt, exp, comment); }
   bool SellStop(double volume, double price, const string &symbol = "", double sl = 0.0, double tp = 0.0, int tt = ORDER_TIME_GTC, datetime exp = 0, const string &comment = "")
     { return Pend(ORDER_TYPE_SELL_STOP, volume, price, symbol, sl, tp, tt, exp, comment); }
   bool OrderDelete(ulong ticket)
     {
      m_rq = MqlTradeRequest();
      m_rq.action = TRADE_ACTION_REMOVE; m_rq.order = ticket;
      return OrderSend(m_rq, m_rs);
     }
   bool PositionModify(ulong ticket, double sl, double tp)
     {
      m_rq = MqlTradeRequest();
      m_rq.action = TRADE_ACTION_SLTP; m_rq.position = ticket; m_rq.sl = sl; m_rq.tp = tp; m_rq.symbol = std::string(_Symbol);
      return OrderSend(m_rq, m_rs);
     }
   unsigned int ResultRetcode() const { return m_rs.retcode; }
   ulong ResultOrder() const { return m_rs.order; }
   string ResultRetcodeDescription() const { return string(m_rs.comment); }
  };

//--- motore del broker: chiamato a ogni nuova quotazione, prima di OnTick
inline void mk_closePos(size_t i, double price, int reason)
  {
   MkPos p = mk_pos[i];
   p.cprice = price; p.ctime = mk_now; p.reason = reason;
   MkDeal d;
   d.ticket = mk_nextTicket++; d.order = 0; d.entry = DEAL_ENTRY_OUT; d.type = (p.type == POSITION_TYPE_BUY ? 1 : 0); d.magic = p.magic; d.sym = p.sym; d.time = mk_now; d.price = price; d.vol = p.vol;
   mk_deals.push_back(d);
   mk_posHist.push_back(p);
   mk_pos.erase(mk_pos.begin() + i);
  }
inline void mk_brokerTick()
  {
   // scadenze
   for(size_t i = 0; i < mk_ord.size();)
     {
      if(mk_ord[i].ttype == ORDER_TIME_SPECIFIED && mk_now >= mk_ord[i].expiry)
        {
         MkOrder o = mk_ord[i];
         o.state = 3; o.done = mk_now;
         mk_ordHist.push_back(o);
         mk_ord.erase(mk_ord.begin() + i);
        }
      else
         i++;
     }
   // stop loss e take profit
   for(size_t i = 0; i < mk_pos.size();)
     {
      MkPos &p = mk_pos[i];
      bool buy = (p.type == POSITION_TYPE_BUY);
      double px = buy ? mk_bid : mk_ask;
      double fav = buy ? (px - p.price) : (p.price - px);
      if(fav > p.maxfav) p.maxfav = fav;
      if(p.sl > 0 && (buy ? mk_bid <= p.sl : mk_ask >= p.sl)) { mk_closePos(i, px, 0); continue; }
      if(p.tp > 0 && (buy ? mk_bid >= p.tp : mk_ask <= p.tp)) { mk_closePos(i, px, 1); continue; }
      i++;
     }
   // ordini stop che scattano (fill al prezzo corrente di mercato: se c'e' un salto, c'e' slittamento)
   for(size_t i = 0; i < mk_ord.size();)
     {
      MkOrder &o = mk_ord[i];
      bool buy = (o.type == ORDER_TYPE_BUY_STOP);
      if(buy ? mk_ask >= o.price : mk_bid <= o.price)
        {
         MkPos p;
         p.ticket = mk_nextTicket++; p.type = buy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL; p.price = buy ? mk_ask : mk_bid; p.sl = o.sl; p.tp = o.tp; p.vol = o.vol;
         p.time = mk_now; p.magic = o.magic; p.sym = o.sym; p.cprice = 0; p.ctime = 0; p.reason = -1; p.maxfav = 0;
         mk_pos.push_back(p);
         MkDeal d;
         d.ticket = mk_nextTicket++; d.order = o.ticket; d.entry = DEAL_ENTRY_IN; d.type = buy ? 0 : 1; d.magic = o.magic; d.sym = o.sym; d.time = mk_now; d.price = p.price; d.vol = o.vol;
         mk_deals.push_back(d);
         MkOrder oo = o;
         oo.state = 1; oo.done = mk_now;
         mk_ordHist.push_back(oo);
         mk_ord.erase(mk_ord.begin() + i);
        }
      else
         i++;
     }
  }

//--- interrogazione di ordini e posizioni
inline int OrdersTotal() { return (int)mk_ord.size(); }
inline ulong OrderGetTicket(int i) { if(i < 0 || i >= (int)mk_ord.size()) return 0; mk_selOrd = i; return mk_ord[i].ticket; }
inline bool OrderSelect(ulong tk) { for(size_t i = 0; i < mk_ord.size(); i++) if(mk_ord[i].ticket == tk) { mk_selOrd = (int)i; return true; } return false; }
inline long OrderGetInteger(int p)
  {
   if(mk_selOrd < 0 || mk_selOrd >= (int)mk_ord.size()) return 0;
   const MkOrder &o = mk_ord[mk_selOrd];
   switch(p) { case ORDER_MAGIC: return o.magic; case ORDER_TYPE: return o.type; case ORDER_TICKET: return (long)o.ticket; case ORDER_TIME_SETUP: return o.setup; case ORDER_TIME_EXPIRATION: return o.expiry; case ORDER_TYPE_TIME: return o.ttype; case ORDER_STATE: return o.state; }
   return 0;
  }
inline double OrderGetDouble(int p)
  {
   if(mk_selOrd < 0 || mk_selOrd >= (int)mk_ord.size()) return 0;
   const MkOrder &o = mk_ord[mk_selOrd];
   switch(p) { case ORDER_PRICE_OPEN: return o.price; case ORDER_SL: return o.sl; case ORDER_TP: return o.tp; case ORDER_VOLUME_CURRENT: return o.vol; }
   return 0;
  }
inline string OrderGetString(int p)
  {
   if(mk_selOrd < 0 || mk_selOrd >= (int)mk_ord.size()) return string("");
   const MkOrder &o = mk_ord[mk_selOrd];
   if(p == ORDER_SYMBOL) return string(o.sym);
   if(p == ORDER_COMMENT) return string(o.comment);
   return string("");
  }
inline int PositionsTotal() { return (int)mk_pos.size(); }
inline ulong PositionGetTicket(int i) { if(i < 0 || i >= (int)mk_pos.size()) return 0; mk_selPos = i; return mk_pos[i].ticket; }
inline string PositionGetSymbol(int i) { if(i < 0 || i >= (int)mk_pos.size()) return string(""); mk_selPos = i; return string(mk_pos[i].sym); }
inline bool PositionSelect(const string &sym)
  {
   int best = -1;
   for(size_t i = 0; i < mk_pos.size(); i++)
      if(mk_pos[i].sym == std::string(sym) && (best < 0 || mk_pos[i].ticket < mk_pos[best].ticket)) best = (int)i;   // hedging: la piu' vecchia
   if(best < 0) return false;
   mk_selPos = best;
   return true;
  }
inline bool PositionSelectByTicket(ulong tk) { for(size_t i = 0; i < mk_pos.size(); i++) if(mk_pos[i].ticket == tk) { mk_selPos = (int)i; return true; } return false; }
inline long PositionGetInteger(int p)
  {
   if(mk_selPos < 0 || mk_selPos >= (int)mk_pos.size()) return 0;
   const MkPos &o = mk_pos[mk_selPos];
   switch(p) { case POSITION_MAGIC: return o.magic; case POSITION_TYPE: return o.type; case POSITION_TICKET: return (long)o.ticket; case POSITION_TIME: return o.time; }
   return 0;
  }
inline double PositionGetDouble(int p)
  {
   if(mk_selPos < 0 || mk_selPos >= (int)mk_pos.size()) return 0;
   const MkPos &o = mk_pos[mk_selPos];
   switch(p) { case POSITION_PRICE_OPEN: return o.price; case POSITION_SL: return o.sl; case POSITION_TP: return o.tp; case POSITION_VOLUME: return o.vol; }
   return 0;
  }
inline string PositionGetString(int p)
  {
   if(mk_selPos < 0 || mk_selPos >= (int)mk_pos.size()) return string("");
   if(p == POSITION_SYMBOL) return string(mk_pos[mk_selPos].sym);
   return string("");
  }

//--- storia
inline bool HistorySelect(datetime from, datetime to)
  {
   hs_ord.clear(); hs_deals.clear();
   for(auto &o : mk_ordHist) if(o.done >= from && o.done <= to) hs_ord.push_back(o);
   for(auto &d : mk_deals) if(d.time >= from && d.time <= to) hs_deals.push_back(d);
   return true;
  }
inline int HistoryDealsTotal() { return (int)hs_deals.size(); }
inline ulong HistoryDealGetTicket(int i) { return (i >= 0 && i < (int)hs_deals.size()) ? hs_deals[i].ticket : 0; }
inline const MkDeal *mk_findDeal(ulong tk) { for(auto &d : hs_deals) if(d.ticket == tk) return &d; return nullptr; }
inline long HistoryDealGetInteger(ulong tk, int p)
  {
   const MkDeal *d = mk_findDeal(tk);
   if(!d) return 0;
   switch(p) { case DEAL_MAGIC: return d->magic; case DEAL_ENTRY: return d->entry; case DEAL_TYPE: return d->type; case DEAL_TIME: return d->time; }
   return 0;
  }
inline string HistoryDealGetString(ulong tk, int p) { const MkDeal *d = mk_findDeal(tk); return (d && p == DEAL_SYMBOL) ? string(d->sym) : string(""); }
inline int HistoryOrdersTotal() { return (int)hs_ord.size(); }
inline ulong HistoryOrderGetTicket(int i) { return (i >= 0 && i < (int)hs_ord.size()) ? hs_ord[i].ticket : 0; }
inline const MkOrder *mk_findHOrd(ulong tk) { for(auto &o : hs_ord) if(o.ticket == tk) return &o; return nullptr; }
inline long HistoryOrderGetInteger(ulong tk, int p)
  {
   const MkOrder *o = mk_findHOrd(tk);
   if(!o) return 0;
   switch(p) { case ORDER_MAGIC: return o->magic; case ORDER_TYPE: return o->type; case ORDER_STATE: return o->state; case ORDER_TIME_SETUP: return o->setup; }
   return 0;
  }
inline string HistoryOrderGetString(ulong tk, int p) { const MkOrder *o = mk_findHOrd(tk); return (o && p == ORDER_SYMBOL) ? string(o->sym) : string(""); }

//--- oggetti grafici (non servono al test)
inline int ObjectFind(int, const string &) { return -1; }
inline bool ObjectCreate(int, const string &, int, int, datetime, double) { return true; }
inline bool ObjectSetInteger(int, const string &, int, long) { return true; }
inline bool ObjectSetDouble(int, const string &, int, double) { return true; }
inline bool ObjectDelete(int, const string &) { return true; }
