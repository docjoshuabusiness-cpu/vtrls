// Runtime minimale che imita le parti di MQL5 usate dal codice (solo per il banco di prova)
#pragma once
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <cstdint>
#include <climits>
#include <cfloat>
#include <string>
#include <vector>
#include <algorithm>
#include <initializer_list>
#include <ctime>

typedef long long datetime;
typedef unsigned char uchar;
typedef unsigned short ushort;
typedef unsigned int uint;
#define LONG_MAX_ 9223372036854775807LL
#define INVALID_HANDLE (-1)
#define M_PI 3.14159265358979323846
#define TIME_DATE 1
#define TIME_MINUTES 2
#define TIME_SECONDS 4

// stringa MQL5: std::string con operator+ che restituisce sempre string
struct string : std::string
  {
   string() : std::string() {}
   string(const std::string &s) : std::string(s) {}
   string(const char *s) : std::string(s) {}
  };
inline string operator+(const string &a, const string &b) { return string(static_cast<const std::string &>(a) + static_cast<const std::string &>(b)); }
inline string S(const char *s) { return string(s); }

// array MQL5 con controllo dei limiti
template<class T>
struct Arr
  {
   T *p; int n, cap;
   Arr() : p(nullptr), n(0), cap(0) {}
   explicit Arr(int m) : p(nullptr), n(0), cap(0) { Resize(m); }
   Arr(int m, std::initializer_list<T> il) : p(nullptr), n(0), cap(0) { Resize(m < 0 ? (int)il.size() : m); int i = 0; for(auto &x : il) { if(i < n) p[i] = x; i++; } }
   Arr(const Arr &o) : p(nullptr), n(0), cap(0) { Resize(o.n); for(int i = 0; i < n; i++) p[i] = o.p[i]; }
   Arr &operator=(const Arr &o) { if(this != &o) { Resize(o.n); for(int i = 0; i < n; i++) p[i] = o.p[i]; } return *this; }
   ~Arr() { delete[] p; }
   void Resize(int m, int reserve = 0)
     {
      if(m < 0) m = 0;
      int need = m > reserve ? m : reserve;
      if(need > cap || (p == nullptr && need > 0))
        {
         int nc = need > cap ? need : cap;
         if(nc < 1) nc = 1;
         T *q = new T[nc]();
         for(int i = 0; i < n && i < m; i++) q[i] = p[i];
         delete[] p; p = q; cap = nc;
        }
      else if(m > n)
        {
         for(int i = n; i < m; i++) p[i] = T();
        }
      n = m;
     }
   T &operator[](long i) { if(i < 0 || i >= n) { fprintf(stderr, "FUORI LIMITI: indice %ld, dimensione %d\n", i, n); abort(); } return p[i]; }
   const T &operator[](long i) const { if(i < 0 || i >= n) { fprintf(stderr, "FUORI LIMITI: indice %ld, dimensione %d\n", i, n); abort(); } return p[i]; }
  };

template<class T> int ArraySize(const Arr<T> &a) { return a.n; }
template<class T> int ArrayResize(Arr<T> &a, int m, int reserve = 0) { a.Resize(m, reserve); return m; }
template<class T> void ArrayFree(Arr<T> &a) { a.Resize(0); }
template<class T, class V> int ArrayInitialize(Arr<T> &a, V v) { for(int i = 0; i < a.n; i++) a.p[i] = (T)v; return a.n; }
template<class T> bool ArraySort(Arr<T> &a) { std::sort(a.p, a.p + a.n); return true; }
template<class T, class U>
int ArrayCopy(Arr<T> &dst, const Arr<U> &src, int ds = 0, int ss = 0, int cnt = -1)
  {
   if(cnt < 0) cnt = src.n - ss;
   if(ss + cnt > src.n) cnt = src.n - ss;
   if(ds + cnt > dst.n) dst.Resize(ds + cnt);
   std::vector<T> tmp(cnt);
   for(int i = 0; i < cnt; i++) tmp[i] = (T)src[ss + i];
   for(int i = 0; i < cnt; i++) dst[ds + i] = tmp[i];
   return cnt;
  }
template<class T> void ZeroMemory(T &x) { memset((void *)&x, 0, sizeof(T)); }

// matematica
inline double MathSqrt(double x) { return std::sqrt(x); }
inline double MathLog(double x) { return std::log(x); }
inline double MathExp(double x) { return std::exp(x); }
inline double MathPow(double x, double y) { return std::pow(x, y); }
inline double MathFloor(double x) { return std::floor(x); }
inline double MathCeil(double x) { return std::ceil(x); }
inline double MathRound(double x) { return std::round(x); }
inline double MathCos(double x) { return std::cos(x); }
inline double MathArcsin(double x) { return std::asin(x); }
inline bool MathIsValidNumber(double x) { return std::isfinite(x); }
template<class T> T MathAbs(T x) { return x < 0 ? -x : x; }
template<class A, class B> auto MathMax(A a, B b) -> decltype(a + b) { return a > b ? a : b; }
template<class A, class B> auto MathMin(A a, B b) -> decltype(a + b) { return a < b ? a : b; }
static unsigned int g_rs = 1;
inline int MathRand() { g_rs = g_rs * 1103515245u + 12345u; return (int)((g_rs >> 16) & 0x7fff); }
inline void MathSrand(int s) { g_rs = (unsigned int)s; }

// stringhe
inline string DoubleToString(double x, int d = 8) { char b[512]; snprintf(b, sizeof b, "%.*f", d, x); return string(b); }
inline string IntegerToString(long long x) { return string(std::to_string(x)); }
inline int StringLen(const string &s) { return (int)s.size(); }
inline string StringSubstr(const string &s, int a, int n = -1) { if(a >= (int)s.size()) return string(""); return string(s.substr(a, n < 0 ? std::string::npos : n)); }
inline int StringFind(const string &s, const string &f, int a = 0) { size_t p = s.find(f, a); return p == std::string::npos ? -1 : (int)p; }
inline int StringReplace(string &s, const string &f, const string &t)
  {
   int c = 0; size_t p = 0;
   if(f.empty()) return 0;
   while((p = s.find(f, p)) != std::string::npos) { s.replace(p, f.size(), t); p += t.size(); c++; }
   return c;
  }
inline void StringToUpper(string &s) { for(auto &c : s) c = (char)toupper(c); }
inline void StringTrimLeft(string &s) { size_t p = 0; while(p < s.size() && isspace((unsigned char)s[p])) p++; s.erase(0, p); }
inline void StringTrimRight(string &s) { while(!s.empty() && isspace((unsigned char)s.back())) s.pop_back(); }
inline int StringSplit(const string &s, ushort sep, Arr<string> &out)
  {
   std::vector<string> v; std::string cur;
   for(char c : s) { if((unsigned char)c == sep) { v.push_back(string(cur)); cur.clear(); } else cur += c; }
   v.push_back(string(cur));
   out.Resize((int)v.size());
   for(size_t i = 0; i < v.size(); i++) out[i] = v[i];
   return (int)v.size();
  }
inline long long StringToInteger(const string &s) { return atoll(s.c_str()); }
inline double StringToDouble(const string &s) { return atof(s.c_str()); }
inline ushort StringGetCharacter(const string &s, int i) { return i >= 0 && i < (int)s.size() ? (unsigned char)s[i] : 0; }
inline string ShortToString(ushort c) { return string(std::string(1, (char)c)); }
template<class T> inline auto _fa(const T &x) { return x; }
inline const char *_fa(const string &x) { return x.c_str(); }
template<class... A> string StringFormat(const string &f, A... a) { char b[8192]; snprintf(b, sizeof b, f.c_str(), _fa(a)...); return string(b); }
template<class... A> void Print(A...) {}
template<class... A> void PrintFormat(A...) {}
template<class... A> void Comment(A...) {}
inline bool IsStopped() { return false; }
inline void Sleep(int) {}

// date
struct MqlDateTime { int year, mon, day, hour, min, sec, day_of_week, day_of_year; };
inline long long _days_from_civil(long long y, unsigned m, unsigned d)
  {
   y -= m <= 2; long long era = (y >= 0 ? y : y - 399) / 400; unsigned yoe = (unsigned)(y - era * 400);
   unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1; unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
   return era * 146097 + (long long)doe - 719468;
  }
inline void _civil_from_days(long long z, int &y, int &m, int &d)
  {
   z += 719468; long long era = (z >= 0 ? z : z - 146096) / 146097; unsigned doe = (unsigned)(z - era * 146097);
   unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; long long yy = (long long)yoe + era * 400;
   unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100); unsigned mp = (5 * doy + 2) / 153;
   d = (int)(doy - (153 * mp + 2) / 5 + 1); m = (int)(mp < 10 ? mp + 3 : mp - 9); y = (int)(yy + (m <= 2));
  }
inline void TimeToStruct(datetime t, MqlDateTime &dt)
  {
   long long days = t >= 0 ? t / 86400 : -((-t + 86399) / 86400); long long sec = t - days * 86400;
   _civil_from_days(days, dt.year, dt.mon, dt.day);
   dt.hour = (int)(sec / 3600); dt.min = (int)((sec % 3600) / 60); dt.sec = (int)(sec % 60);
   dt.day_of_week = (int)(((days % 7) + 11) % 7);  // 1970-01-01 = giovedi' (4)
   dt.day_of_year = (int)(days - _days_from_civil(dt.year, 1, 1));
  }
inline datetime StructToTime(MqlDateTime &dt)
  {
   return _days_from_civil(dt.year, dt.mon, dt.day) * 86400LL + dt.hour * 3600LL + dt.min * 60LL + dt.sec;
  }
inline string TimeToString(datetime t, int fl = TIME_DATE | TIME_MINUTES)
  {
   MqlDateTime d; TimeToStruct(t, d); char b[64]; std::string r;
   if(fl & TIME_DATE) { snprintf(b, sizeof b, "%04d.%02d.%02d", d.year, d.mon, d.day); r += b; }
   if(fl & TIME_MINUTES) { snprintf(b, sizeof b, "%s%02d:%02d", r.empty() ? "" : " ", d.hour, d.min); r += b; }
   return string(r);
  }
