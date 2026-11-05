#include "app/touch_reason.h"

#include <cstdio>
#include <cstring>

#include "render/font.h"

namespace app {

namespace {
// `fact` with {name} as `who`, then `tail`.
void fill(const char* fact, const char* who, const char* tail, char* out, size_t n) {
  const char* at = std::strstr(fact, "{name}");
  if (at) std::snprintf(out, n, "%.*s%s%s%s", int(at - fact), fact, who, at + 6, tail);
  else std::snprintf(out, n, "%s%s", fact, tail);
}
void fit(const char* fact, const char* name, const char* tail, int most, char* out, size_t n) {
  fill(fact, name, tail, out, n);
  if (render::glyphCount(out) > most) fill(fact, "it", tail, out, n);
}
}  // namespace

bool touchReason(const char* gesture, const char* name, int most, char* out, size_t n) {
  for (const TouchReason& r : kTouchReasons)
    if (!std::strcmp(r.gesture, gesture)) return fit(r.fact, name, "", most, out, n), true;
  return false;
}

void pokeReason(int run, bool asleep, const char* name, int most, char* out, size_t n) {
  char tail[12] = "";
  if (!asleep && run > 1) std::snprintf(tail, sizeof(tail), " x%d", run);
  fit(asleep ? "you woke {name}" : "you poked {name}", name, tail, most, out, n);
}

}  // namespace app
