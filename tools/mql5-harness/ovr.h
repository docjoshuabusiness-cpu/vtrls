
#include <cstdlib>
static string envs(const char* n, const char* d) { const char* v = getenv(n); return v ? string(v) : string(d); }
