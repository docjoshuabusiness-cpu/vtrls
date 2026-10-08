// Mini-broker per far girare MultiDayRangeBreakout (EA reale) in C++: ordini stop pendenti, riempimenti con gap,
// SL/TP, storia di ordini e deal, CTrade. Tick generati da barre M1 con l'ordine intrabarra "pessimista".
#pragma once
#include "mql5_mock.h"

#define TRADE_RETCODE_DONE 10009
#define TRADE_RETCODE_PLACED 10008
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY = 0, ORDER_TYPE_SELL = 1, ORDER_TYPE_BUY_STOP = 4, ORDER_TYPE_SELL_STOP = 5 };
enum ENUM_ORDER_TYPE_TIME { ORDER_TIME_GTC = 0, ORDER_TIME_DAY = 1, ORDER_TIME_SPECIFIED = 2 };
enum { ORDER_SYMBOL = 1, ORDER_MAGIC, ORDER_TYPE };
enum { POSITION_SYMBOL = 1, POSITION_MAGIC, POSITION_TYPE, POSITION_PRICE_OPEN, POSITION_SL, POSITION_TP };
enum ENUM_POSITION_TYPE { POSITION_TYPE_BUY = 0, POSITION_TYPE_SELL = 1 };
enum { DEAL_SYMBOL = 1, DEAL_MAGIC, DEAL_ENTRY };
enum ENUM_DEAL_ENTRY { DEAL_ENTRY_IN = 0, DEAL_ENTRY_OUT = 1 };
enum { MQL_TESTER = 1, MQL_VISUAL_MODE, MQL_OPTIMIZATION };
inline long MQLInfoInteger(int p) { return p == MQL_TRADE_ALLOWED ? 1 : (p == MQL_TESTER ? 1 : 0); }
enum ENUM_LINE_STYLE { STYLE_SOLID, STYLE_DASH };
enum { OBJ_HLINE = 1 };
enum { OBJPROP_COLOR = 1, OBJPROP_STYLE, OBJPROP_SELECTABLE, OBJPROP_PRICE };
#define clrDodgerBlue 1
#define clrTomato 2
inline int ObjectFind(int, const string&) { return -1; }
template<typename... A> bool ObjectCreate(A...) { return true; }
template<typename... A> bool ObjectSetInteger(A...) { return true; }
template<typename... A> bool ObjectSetDouble(A...) { return true; }
inline bool ObjectDelete(int, const string&) { return true; }

struct MOrder { ulong ticket; int type; double price, sl, tp; datetime exp; long magic; string symbol; };
struct MPos { ulong ticket; int type; double price, sl, tp; long magic; string symbol; datetime topen; double slNominal; double lastBid; };
struct MDeal { ulong ticket; datetime t; string symbol; long magic; int entry; };
struct MHistOrder { ulong ticket; datetime t; string symbol; long magic; int type; double price; };
struct MClosed { ulong ticket; int dir; datetime topen, tclose; double entry, exit, R; };
static std::vector<MOrder> g_orders;
static std::vector<MPos> g_pos;
static std::vector<MDeal> g_deals;
static std::vector<MHistOrder> g_horders;
static std::vector<MClosed> g_closed;
struct MPlacement { datetime t; double buy, sell, sl, tp; datetime exp; };
static std::vector<MPlacement> g_placements;
static ulong g_nextTicket = 1000;
static int g_selOrder = -1, g_selPos = -1;
static std::vector<MDeal> g_selDeals;
static std::vector<MHistOrder> g_selHOrders;

inline int OrdersTotal() { return (int)g_orders.size(); }
inline ulong OrderGetTicket(int i) { if(i < 0 || i >= (int)g_orders.size()) return 0; g_selOrder = i; return g_orders[i].ticket; }
inline string OrderGetString(int) { return g_orders[g_selOrder].symbol; }
inline long OrderGetInteger(int p) { return p == ORDER_MAGIC ? g_orders[g_selOrder].magic : g_orders[g_selOrder].type; }
inline int PositionsTotal() { return (int)g_pos.size(); }
inline ulong PositionGetTicket(int i) { if(i < 0 || i >= (int)g_pos.size()) return 0; g_selPos = i; return g_pos[i].ticket; }
inline bool PositionSelectByTicket(ulong t) { for(size_t i = 0; i < g_pos.size(); i++) if(g_pos[i].ticket == t) { g_selPos = (int)i; return true; } return false; }
inline string PositionGetString(int) { return g_pos[g_selPos].symbol; }
inline long PositionGetInteger(int p) { return p == POSITION_MAGIC ? g_pos[g_selPos].magic : g_pos[g_selPos].type; }
inline double PositionGetDouble(int p) { return p == POSITION_PRICE_OPEN ? g_pos[g_selPos].price : (p == POSITION_SL ? g_pos[g_selPos].sl : g_pos[g_selPos].tp); }
inline bool HistorySelect(datetime from, datetime to) {
   g_selDeals.clear(); g_selHOrders.clear();
   for(auto& d : g_deals) if(d.t >= from && d.t <= to) g_selDeals.push_back(d);
   for(auto& o : g_horders) if(o.t >= from && o.t <= to) g_selHOrders.push_back(o);
   return true;
}
inline int HistoryDealsTotal() { return (int)g_selDeals.size(); }
inline ulong HistoryDealGetTicket(int i) { return (i >= 0 && i < (int)g_selDeals.size()) ? g_selDeals[i].ticket : 0; }
static MDeal* findDeal(ulong t) { for(auto& d : g_selDeals) if(d.ticket == t) return &d; return nullptr; }
inline string HistoryDealGetString(ulong t, int) { MDeal* d = findDeal(t); return d ? d->symbol : ""; }
inline long HistoryDealGetInteger(ulong t, int p) { MDeal* d = findDeal(t); if(!d) return 0; return p == DEAL_MAGIC ? d->magic : d->entry; }
inline int HistoryOrdersTotal() { return (int)g_selHOrders.size(); }
inline ulong HistoryOrderGetTicket(int i) { return (i >= 0 && i < (int)g_selHOrders.size()) ? g_selHOrders[i].ticket : 0; }
static MHistOrder* findHO(ulong t) { for(auto& o : g_selHOrders) if(o.ticket == t) return &o; return nullptr; }
inline string HistoryOrderGetString(ulong t, int) { MHistOrder* o = findHO(t); return o ? o->symbol : ""; }
inline long HistoryOrderGetInteger(ulong t, int p) { MHistOrder* o = findHO(t); if(!o) return 0; return p == ORDER_MAGIC ? o->magic : o->type; }

class CTrade {
public:
   long magic = 0; unsigned retcode = 0; ulong lastOrder = 0;
   void SetExpertMagicNumber(ulong m) { magic = (long)m; }
   void SetDeviationInPoints(ulong) {}
   void SetTypeFillingBySymbol(const string&) {}
   unsigned ResultRetcode() { return retcode; }
   string ResultRetcodeDescription() { return "ok"; }
   ulong ResultOrder() { return lastOrder; }
   bool place(int type, double vol, double price, const string& sym, double sl, double tp, int ttype, datetime exp, const string& cmt) {
      MOrder o{g_nextTicket++, type, price, sl, tp, ttype == ORDER_TIME_SPECIFIED ? exp : 0, magic, sym};
      g_orders.push_back(o);
      g_horders.push_back({o.ticket, g_now, sym, magic, type, price});
      lastOrder = o.ticket; retcode = TRADE_RETCODE_PLACED; return true;
   }
   bool BuyStop(double vol, double price, const string& sym, double sl, double tp, int ttype, datetime exp, const string& cmt) { return place(ORDER_TYPE_BUY_STOP, vol, price, sym, sl, tp, ttype, exp, cmt); }
   bool SellStop(double vol, double price, const string& sym, double sl, double tp, int ttype, datetime exp, const string& cmt) { return place(ORDER_TYPE_SELL_STOP, vol, price, sym, sl, tp, ttype, exp, cmt); }
   bool OrderDelete(ulong t) {
      for(size_t i = 0; i < g_orders.size(); i++) if(g_orders[i].ticket == t) { g_orders.erase(g_orders.begin() + i); retcode = TRADE_RETCODE_DONE; return true; }
      retcode = 10013; return false;
   }
   bool PositionModify(ulong t, double sl, double tp) {
      for(auto& p : g_pos) if(p.ticket == t) {
         if(getenv("MDRB_TRACE")) fprintf(stderr, "   EA modify %s bid %.5f ask %.5f  SL %.5f -> %.5f (entry %.5f)\n", TimeToString(g_now, TIME_DATE | TIME_MINUTES | TIME_SECONDS).c_str(), g_curBid, g_curAsk, p.sl, sl, p.price);
         p.sl = sl; p.tp = tp; retcode = TRADE_RETCODE_DONE; return true; }
      retcode = 10013; return false;
   }
};

// ---- serie relative a "adesso" (g_now) per qualsiasi TF
static int lastAtOrBeforeTF(std::vector<MqlRates>& v, datetime t) {
   int lo = 0, hi = (int)v.size() - 1, ans = -1;
   while(lo <= hi) { int m = (lo + hi) / 2; if(v[m].time <= t) { ans = m; lo = m + 1; } else hi = m - 1; }
   return ans;
}
static std::vector<MqlRates>& tfBars(ENUM_TIMEFRAMES tf) { if(tf == PERIOD_CURRENT) tf = g__Period; return g_store[(int)tf]; }
inline datetime iTime(const string&, ENUM_TIMEFRAMES tf, int s) { auto& v = tfBars(tf); int i = lastAtOrBeforeTF(v, g_now) - s; return (i >= 0 && i < (int)v.size()) ? v[i].time : 0; }
inline double iHigh(const string&, ENUM_TIMEFRAMES tf, int s) { auto& v = tfBars(tf); int i = lastAtOrBeforeTF(v, g_now) - s; return (i >= 0 && i < (int)v.size()) ? v[i].high : 0; }
inline double iLow(const string&, ENUM_TIMEFRAMES tf, int s) { auto& v = tfBars(tf); int i = lastAtOrBeforeTF(v, g_now) - s; return (i >= 0 && i < (int)v.size()) ? v[i].low : 0; }
inline int iBarShift(const string&, ENUM_TIMEFRAMES tf, datetime t, bool exact = false) {
   auto& v = tfBars(tf);
   int idxNow = lastAtOrBeforeTF(v, g_now);
   int idxT = lastAtOrBeforeTF(v, t);
   if(idxT < 0) return -1;
   if(idxT > idxNow) idxT = idxNow;
   return idxNow - idxT;
}

// ---- motore del broker
static double g_spreadPrice = 0.0;
static std::vector<MPlacement>* g_dummyPlacementSink = nullptr;

static void closePos(size_t i, double exitPx, datetime t) {
   MPos p = g_pos[i];
   double R = (p.type == POSITION_TYPE_BUY ? (exitPx - p.price) : (p.price - exitPx)) / p.slNominal;
   g_closed.push_back({p.ticket, p.type == POSITION_TYPE_BUY ? 1 : -1, p.topen, t, p.price, exitPx, R});
   g_pos.erase(g_pos.begin() + i);
}

// elabora un tick: scadenze, riempimenti degli ordini, SL/TP. isOpen = primo tick della barra (i gap si riempiono al prezzo del tick)
static void brokerTick(datetime t, double bid, bool isOpen) {
   g_now = t; g_curBid = bid; g_curAsk = bid + g_spreadPrice;
   for(size_t i = 0; i < g_orders.size();) { if(g_orders[i].exp > 0 && t >= g_orders[i].exp) g_orders.erase(g_orders.begin() + i); else i++; }
   // SL/TP delle posizioni
   for(size_t i = 0; i < g_pos.size();) {
      MPos& p = g_pos[i];
      bool closed = false;
      if(p.type == POSITION_TYPE_BUY) {
         if(p.sl > 0 && g_curBid <= p.sl + 1e-9) { closePos(i, isOpen ? g_curBid : p.sl, t); closed = true; }
         else if(p.tp > 0 && g_curBid >= p.tp - 1e-9) { closePos(i, isOpen ? g_curBid : p.tp, t); closed = true; }
      } else {
         if(p.sl > 0 && g_curAsk >= p.sl - 1e-9) { closePos(i, isOpen ? g_curAsk : p.sl, t); closed = true; }
         else if(p.tp > 0 && g_curAsk <= p.tp + 1e-9) { closePos(i, isOpen ? g_curAsk : p.tp, t); closed = true; }
      }
      if(!closed) i++;
   }
   // riempimenti
   for(size_t i = 0; i < g_orders.size();) {
      MOrder o = g_orders[i];
      bool fill = false; double fp = 0.0; int ptype = 0;
      if(o.type == ORDER_TYPE_BUY_STOP && g_curAsk >= o.price - 1e-9) { fill = true; fp = isOpen ? g_curAsk : o.price; ptype = POSITION_TYPE_BUY; }
      if(o.type == ORDER_TYPE_SELL_STOP && g_curBid <= o.price + 1e-9) { fill = true; fp = isOpen ? g_curBid : o.price; ptype = POSITION_TYPE_SELL; }
      if(fill) {
         double slNom = std::fabs(o.price - o.sl);
         g_pos.push_back({g_nextTicket++, ptype, fp, o.sl, o.tp, o.magic, o.symbol, t, slNom, bid});
         g_deals.push_back({g_nextTicket++, t, o.symbol, o.magic, DEAL_ENTRY_IN});
         g_orders.erase(g_orders.begin() + i);
      } else i++;
   }
}
