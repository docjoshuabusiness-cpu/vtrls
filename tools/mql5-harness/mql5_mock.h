// Minimal MQL5 API mock — enough to compile and run the study script (and the EA signal path) in C++17.
#pragma once
#include <vector>
#include <string>
#include <map>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <ctime>
#include <chrono>
#include <iostream>
#include <sstream>
#include <algorithm>
#include <type_traits>
#include <functional>

typedef std::string string;
typedef long long datetime;
typedef unsigned char uchar;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned int color;

#define DBL_MAX_ 1.7976931348623158e+308
#ifndef DBL_MAX
#define DBL_MAX 1.7976931348623158e+308
#endif
#define EMPTY_VALUE DBL_MAX
#define INVALID_HANDLE (-1)
#define WHOLE_ARRAY (-1)

// ---- dynamic arrays with bounds checking
template<typename T> struct Arr {
   typedef typename std::conditional<std::is_same<T, bool>::value, unsigned char, T>::type Store;
   std::vector<Store> v;
   bool series = false;
   Arr() {}
   template<size_t N> Arr(const T (&a)[N]) : v(a, a + N) {}
   T& operator[](long long i) {
      if(i < 0 || i >= (long long)v.size()) { fprintf(stderr, "ARRAY OUT OF RANGE idx=%lld size=%zu\n", i, v.size()); abort(); }
      return reinterpret_cast<T&>(v[(size_t)i]);
   }
   const T& operator[](long long i) const {
      if(i < 0 || i >= (long long)v.size()) { fprintf(stderr, "ARRAY OUT OF RANGE idx=%lld size=%zu\n", i, v.size()); abort(); }
      return reinterpret_cast<const T&>(v[(size_t)i]);
   }
};

template<typename T> int ArrayResize(Arr<T>& a, int n, int reserve = 0) { a.v.resize((size_t)n); return n; }
template<typename T> int ArraySize(const Arr<T>& a) { return (int)a.v.size(); }
template<typename T, size_t N> int ArraySize(const T (&)[N]) { return (int)N; }
template<typename T> void ArrayFree(Arr<T>& a) { a.v.clear(); a.v.shrink_to_fit(); }
template<typename T, typename V> void ArrayInitialize(Arr<T>& a, V val) { for(auto& x : a.v) x = (T)val; }
template<typename T, size_t N, typename V> void ArrayInitialize(T (&a)[N], V val) { for(size_t i = 0; i < N; i++) a[i] = (T)val; }
template<typename T> bool ArraySetAsSeries(Arr<T>& a, bool s) { a.series = s; return true; }
template<typename T> void ArraySort(Arr<T>& a) { std::sort(a.v.begin(), a.v.end()); }
template<typename T> int ArrayCopy(Arr<T>& dst, const Arr<T>& src) { dst.v = src.v; return (int)src.v.size(); }
template<typename T> void ZeroMemory(T& x) { x = T(); }

// ---- math
template<typename A, typename B> auto MathMax(A a, B b) -> typename std::common_type<A, B>::type { return a > b ? a : b; }
template<typename A, typename B> auto MathMin(A a, B b) -> typename std::common_type<A, B>::type { return a < b ? a : b; }
inline double MathAbs(double x) { return std::fabs(x); }
inline int MathAbs(int x) { return std::abs(x); }
inline double MathSqrt(double x) { return std::sqrt(x); }
inline double MathExp(double x) { return std::exp(x); }
inline double MathLog(double x) { return std::log(x); }
inline double MathPow(double x, double y) { return std::pow(x, y); }
inline double MathFloor(double x) { return std::floor(x); }
inline double MathCeil(double x) { return std::ceil(x); }
inline double MathRound(double x) { return std::round(x); }
inline datetime TimeTradeServer();
inline datetime TimeGMT();
inline double NormalizeDouble(double x, int d) { double m = std::pow(10.0, d); return std::round(x * m) / m; }

// ---- strings
inline int StringLen(const string& s) { return (int)s.size(); }
inline double StringToDouble(const string& s) { return atof(s.c_str()); }
inline long StringToInteger(const string& s) { return atol(s.c_str()); }
inline int StringTrimLeft(string& s) { size_t i = 0; while(i < s.size() && isspace((unsigned char)s[i])) i++; s.erase(0, i); return 0; }
inline int StringTrimRight(string& s) { while(!s.empty() && isspace((unsigned char)s.back())) s.pop_back(); return 0; }
inline void StringAdd(string& s, const string& a) { s += a; }
inline int StringReplace(string& s, const string& a, const string& b) {
   int n = 0; size_t p = 0;
   while((p = s.find(a, p)) != string::npos) { s.replace(p, a.size(), b); p += b.size(); n++; }
   return n;
}
inline int StringFind(const string& s, const string& f, int start = 0) { size_t p = s.find(f, (size_t)start); return p == string::npos ? -1 : (int)p; }
inline int StringSplit(const string& s, int sep, Arr<string>& out) {
   out.v.clear();
   string cur;
   for(char c : s) { if((int)(unsigned char)c == sep) { out.v.push_back(cur); cur.clear(); } else cur += c; }
   out.v.push_back(cur);
   return (int)out.v.size();
}
inline string DoubleToString(double v, int d = 8) { char b[64]; snprintf(b, sizeof b, "%.*f", d, v); return b; }
inline string IntegerToString(long long v, int = 0, ushort = ' ') { return std::to_string(v); }

template<typename T> inline T fmtarg(T v) { return v; }
inline const char* fmtarg(const std::string& s) { return s.c_str(); }
inline const char* fmtarg(std::string& s) { return s.c_str(); }
inline const char* fmtarg(const char* s) { return s; }

template<typename... Args> string StringFormat(const string& fmt, Args... args) {
   string f = fmt;
   StringReplace(f, "%I64d", "%lld"); StringReplace(f, "%I64u", "%llu");
   char buf[8192];
   snprintf(buf, sizeof buf, f.c_str(), fmtarg(args)...);
   return buf;
}

inline void prt_one(std::ostream& o, const string& s) { o << s; }
inline void prt_one(std::ostream& o, const char* s) { o << s; }
template<typename T> inline void prt_one(std::ostream& o, T v) { o << v; }
inline void prt_one(std::ostream& o, double v) { char b[64]; snprintf(b, sizeof b, "%.8g", v); o << b; }
extern bool g_quiet;
template<typename... Args> void Print(Args... args) {
   if(g_quiet) return;
   std::ostringstream o; (prt_one(o, args), ...); std::cout << o.str() << std::endl;
}
template<typename... Args> void PrintFormat(const string& fmt, Args... args) {
   if(g_quiet) return;
   std::cout << StringFormat(fmt, args...) << std::endl;
}
template<typename... Args> void Comment(Args... args) {}

// ---- time
struct MqlDateTime { int year; int mon; int day; int hour; int min; int sec; int day_of_week; int day_of_year; };
#define TIME_DATE 1
#define TIME_MINUTES 2
#define TIME_SECONDS 4
inline bool TimeToStruct(datetime t, MqlDateTime& d) {
   time_t tt = (time_t)t; struct tm g; gmtime_r(&tt, &g);
   d.year = g.tm_year + 1900; d.mon = g.tm_mon + 1; d.day = g.tm_mday; d.hour = g.tm_hour; d.min = g.tm_min; d.sec = g.tm_sec;
   d.day_of_week = g.tm_wday; d.day_of_year = g.tm_yday; return true;
}
inline datetime StructToTime(MqlDateTime& d) {
   struct tm g; memset(&g, 0, sizeof g);
   g.tm_year = d.year - 1900; g.tm_mon = d.mon - 1; g.tm_mday = d.day; g.tm_hour = d.hour; g.tm_min = d.min; g.tm_sec = d.sec;
   return (datetime)timegm(&g);
}
inline string TimeToString(datetime t, int flags = TIME_DATE | TIME_MINUTES) {
   MqlDateTime d; TimeToStruct(t, d); char b[64]; string s;
   if(flags & TIME_DATE) { snprintf(b, sizeof b, "%04d.%02d.%02d", d.year, d.mon, d.day); s += b; }
   if(flags & TIME_MINUTES) { if(!s.empty()) s += " "; snprintf(b, sizeof b, "%02d:%02d", d.hour, d.min); s += b; }
   if(flags & TIME_SECONDS) { snprintf(b, sizeof b, ":%02d", d.sec); s += b; }
   return s;
}
extern datetime g_now;
inline datetime TimeCurrent() { return g_now; }
inline uint GetTickCount() { return (uint)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
inline void Sleep(int) {}
inline bool IsStopped() { return false; }
inline void ResetLastError() {}
inline int GetLastError() { return 0; }

// ---- timeframes
enum ENUM_TIMEFRAMES { PERIOD_CURRENT = 0, PERIOD_M1 = 1, PERIOD_M5 = 5, PERIOD_M15 = 15, PERIOD_M30 = 30, PERIOD_H1 = 16385, PERIOD_H4 = 16388, PERIOD_D1 = 16408, PERIOD_W1 = 32769, PERIOD_MN1 = 49153 };
extern ENUM_TIMEFRAMES g__Period;
#define _Period (g__Period)
inline int PeriodSeconds(ENUM_TIMEFRAMES tf) {
   if(tf == PERIOD_CURRENT) tf = g__Period;
   switch(tf) {
      case PERIOD_M1: return 60; case PERIOD_M5: return 300; case PERIOD_M15: return 900; case PERIOD_M30: return 1800;
      case PERIOD_H1: return 3600; case PERIOD_H4: return 14400; case PERIOD_D1: return 86400; case PERIOD_W1: return 604800;
      case PERIOD_MN1: return 2592000; default: return 60;
   }
}
inline string EnumToString(ENUM_TIMEFRAMES tf) {
   switch(tf) {
      case PERIOD_CURRENT: return "PERIOD_CURRENT"; case PERIOD_M1: return "PERIOD_M1"; case PERIOD_M5: return "PERIOD_M5"; case PERIOD_M15: return "PERIOD_M15";
      case PERIOD_M30: return "PERIOD_M30"; case PERIOD_H1: return "PERIOD_H1"; case PERIOD_H4: return "PERIOD_H4"; case PERIOD_D1: return "PERIOD_D1";
      case PERIOD_W1: return "PERIOD_W1"; default: return "PERIOD_MN1";
   }
}
template<typename E> inline string EnumToString(E e) { return "ENUM_" + std::to_string((int)e); }

// ---- symbol/terminal
#define _Symbol (g__Symbol)
extern string g__Symbol;
extern double g_pointval;
extern int g_spreadval;
enum { SYMBOL_POINT = 1, SYMBOL_SPREAD, SYMBOL_DIGITS, SYMBOL_TRADE_TICK_VALUE, SYMBOL_TRADE_TICK_SIZE, SYMBOL_VOLUME_STEP, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX,
       SYMBOL_FILLING_MODE, SYMBOL_ASK, SYMBOL_BID, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL, SYMBOL_EXPIRATION_MODE, SYMBOL_TRADE_MODE,
       SYMBOL_FILLING_FOK = 1, SYMBOL_FILLING_IOC = 2, SYMBOL_EXPIRATION_SPECIFIED = 4, SYMBOL_TRADE_MODE_FULL = 4 };
inline double g_ticksize = 0.00001;
inline int g_digitsval = 5;
inline long g_stopsLevel = 0;
inline double g_curBid = 0.0, g_curAsk = 0.0;
#define _Point (g_pointval)
#define _Digits (g_digitsval)
inline double SymbolInfoDouble(const string&, int prop) {
   switch(prop) { case SYMBOL_POINT: return g_pointval; case SYMBOL_TRADE_TICK_VALUE: return 1.0; case SYMBOL_TRADE_TICK_SIZE: return g_ticksize;
                  case SYMBOL_ASK: return g_curAsk; case SYMBOL_BID: return g_curBid;
                  case SYMBOL_VOLUME_STEP: return 0.01; case SYMBOL_VOLUME_MIN: return 0.01; case SYMBOL_VOLUME_MAX: return 100; default: return 0; }
}
inline long SymbolInfoInteger(const string&, int prop) {
   if(prop == SYMBOL_SPREAD) return g_spreadval; if(prop == SYMBOL_DIGITS) return g_digitsval; if(prop == SYMBOL_FILLING_MODE) return 1;
   if(prop == SYMBOL_TRADE_STOPS_LEVEL) return g_stopsLevel; if(prop == SYMBOL_TRADE_FREEZE_LEVEL) return 0;
   if(prop == SYMBOL_EXPIRATION_MODE) return 1 | 2 | 4 | 8; if(prop == SYMBOL_TRADE_MODE) return SYMBOL_TRADE_MODE_FULL; return 0; }
enum { TERMINAL_MAXBARS = 1, TERMINAL_DATA_PATH, TERMINAL_TRADE_ALLOWED };
inline long TerminalInfoInteger(int p) { return p == TERMINAL_TRADE_ALLOWED ? 1 : 100000000; }
enum { ACCOUNT_TRADE_ALLOWED = 100 };
inline long AccountInfoInteger(int) { return 1; }
enum { MQL_TRADE_ALLOWED = 100 };
extern string g_datapath;
inline string TerminalInfoString(int) { return g_datapath; }
enum { SERIES_SYNCHRONIZED = 1, SERIES_SERVER_FIRSTDATE, SERIES_BARS_COUNT };

// ---- rates
struct MqlRates { datetime time; double open; double high; double low; double close; long tick_volume; int spread; long real_volume; };
extern std::map<int, std::vector<MqlRates>> g_store;   // per timeframe
inline long SeriesInfoInteger(const string&, ENUM_TIMEFRAMES tf, int prop) {
   if(tf == PERIOD_CURRENT) tf = g__Period;
   auto it = g_store.find((int)tf);
   if(prop == SERIES_SYNCHRONIZED) return 1;
   if(it == g_store.end() || it->second.empty()) return 0;
   if(prop == SERIES_SERVER_FIRSTDATE) return it->second.front().time;
   return (long)it->second.size();
}
inline int CopyRates(const string&, ENUM_TIMEFRAMES tf, datetime from, datetime to, Arr<MqlRates>& out) {
   if(tf == PERIOD_CURRENT) tf = g__Period;
   auto it = g_store.find((int)tf);
   out.v.clear();
   if(it == g_store.end()) return -1;
   for(const auto& r : it->second) if(r.time >= from && r.time <= to) out.v.push_back(r);
   return (int)out.v.size();
}
inline int CopyTime(const string&, ENUM_TIMEFRAMES tf, datetime from, datetime to, Arr<datetime>& out) {
   if(tf == PERIOD_CURRENT) tf = g__Period;
   auto it = g_store.find((int)tf);
   out.v.clear();
   if(it == g_store.end()) return -1;
   for(const auto& r : it->second) if(r.time >= from && r.time <= to) out.v.push_back(r.time);
   return (int)out.v.size();
}

// ---- files
#define FILE_WRITE 1
#define FILE_READ 2
#define FILE_TXT 4
#define FILE_ANSI 8
#define FILE_BIN 16
#define FILE_COMMON 32
extern std::vector<FILE*> g_files;
inline int FileOpen(const string& name, int flags) {
   string path = g_datapath + "/MQL5/Files/" + name;
   FILE* f = fopen(path.c_str(), (flags & FILE_WRITE) ? "wb" : "rb");
   if(!f) return INVALID_HANDLE;
   g_files.push_back(f);
   return (int)g_files.size() - 1;
}
inline unsigned FileWriteString(int h, const string& s) { if(h < 0) return 0; fwrite(s.data(), 1, s.size(), g_files[h]); return (unsigned)s.size(); }
inline void FileClose(int h) { if(h >= 0 && g_files[h]) { fclose(g_files[h]); g_files[h] = nullptr; } }

inline datetime TimeTradeServer() { extern datetime g_now; return g_now; }
inline datetime TimeGMT() { extern datetime g_now; return g_now - 7200; }
