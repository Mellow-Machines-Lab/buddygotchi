#include "render/font.h"

#include "fonts.h"
#include "render/palette.h"

namespace render {

const Font& kSmall = kFontSmall;
const Font& kLarge = kFontLarge;
const Font& kSign = kFontSign;

namespace {

// U+00C0 to U+00FF (UTF-8 C3 80 to C3 BF), each as its nearest plain
// letter, so "café" shows as "cafe" rather than "caf?".
constexpr char kLatin1[] = "AAAAAAACEEEEIIIIDNOOOOOxOUUUUYPsaaaaaaaceeeeiiiidnooooo/ouuuuypy";
static_assert(sizeof(kLatin1) == 64 + 1, "one letter per code point");

}  // namespace

int nextGlyph(const char*& p) {
  unsigned char c = static_cast<unsigned char>(*p);
  if (!c) return -1;
  ++p;
  unsigned char next = static_cast<unsigned char>(*p);
  if (c == 0xC2 && next == 0xB7) {
    ++p;
    return 95;  // "·", the first extra after '~'
  }
  if (c == 0xC3 && (next & 0xC0) == 0x80) {
    ++p;
    return kLatin1[next - 0x80] - 0x20;
  }
  if (c >= 0x80) {  // skip the rest of any other UTF-8 sequence
    while ((static_cast<unsigned char>(*p) & 0xC0) == 0x80) ++p;
    return '?' - 0x20;
  }
  return c >= 0x20 && c <= 0x7E ? c - 0x20 : '?' - 0x20;
}

namespace {

void drawGlyph(Canvas& c, const Font& f, int x, int y, int g, int ink) {
  int rowBytes = (f.w + 1) / 2;
  const uint8_t* src = f.data + size_t(g) * rowBytes * f.h;
  for (int row = 0; row < f.h; ++row) {
    int yy = y + row;
    if (yy < 0 || yy >= kHeight) continue;
    for (int col = 0; col < f.w; ++col) {
      int xx = x + col;
      if (xx < 0 || xx >= kWidth) continue;
      uint8_t b = src[row * rowBytes + col / 2];
      int v = (col & 1) ? (b & 15) : (b >> 4);
      int level = (v * kLevels + 7) / 15;
      if (level > 0) c.plot(xx, yy, textAt(ink, level));
    }
  }
}

}  // namespace

int drawString(Canvas& c, const Font& f, int x, int y, const char* text, int ink) {
  for (int g; (g = nextGlyph(text)) >= 0; x += f.w) drawGlyph(c, f, x, y, g, ink);
  return x;
}

int stringWidth(const Font& f, const char* text) { return glyphCount(text) * f.w; }

int drawStringFit(Canvas& c, const Font& f, int x, int y, const char* text, int ink, int maxWidth) {
  if (stringWidth(f, text) <= maxWidth) return drawString(c, f, x, y, text, ink);
  int room = maxWidth / f.w - 2;  // leave space for ".."
  for (int g; room > 0 && (g = nextGlyph(text)) >= 0; --room, x += f.w) drawGlyph(c, f, x, y, g, ink);
  for (int i = 0; i < 2; ++i, x += f.w) drawGlyph(c, f, x, y, '.' - 0x20, ink);
  return x;
}

int glyphCount(const char* text) {
  int n = 0;
  while (nextGlyph(text) >= 0) ++n;
  return n;
}

int wrapText(const char* text, int cols, int maxLines, char* out, int lineBytes) {
  if (cols < 3 || maxLines < 1 || lineBytes < 4) return 0;
  int n = 0, g = 0, b = 0;  // lines started, and the glyphs and bytes on the last
  char* line = out;
  bool cut = false;
  auto next = [&]() {  // starts another line; false when there's no room for one
    if (n == maxLines) return false;
    line = out + n * lineBytes, line[0] = 0, g = b = 0, ++n;
    return true;
  };
  const char* p = text;
  while (*p == ' ') ++p;
  while (*p && !cut) {
    const char* end = p;
    while (*end && *end != ' ') ++end;
    int wg = 0;
    for (const char* q = p; q < end; ++wg) nextGlyph(q);
    if (n == 0 || g + 1 + wg > cols) {
      if (!next()) cut = true;
    } else {
      line[b++] = ' ', line[b] = 0, ++g;
    }
    // The word, a glyph at a time, onto more lines when it's longer than one.
    while (!cut && p < end) {
      if (g == cols && !next()) {
        cut = true;
        break;
      }
      const char* q = p;
      nextGlyph(q);
      int nb = int(q - p);
      if (b + nb >= lineBytes) {
        cut = true;
        break;
      }
      for (int i = 0; i < nb; ++i) line[b++] = p[i];
      line[b] = 0, ++g, p = q;
    }
    while (*p == ' ') ++p;
  }
  if (cut && n > 0) {  // the last line ends "..", within its columns and bytes
    int keep = g < cols - 2 ? g : cols - 2;
    const char* q = line;
    for (int i = 0; i < keep; ++i) nextGlyph(q);
    int at = int(q - line);
    while (at > 0 && line[at - 1] == ' ') --at;
    if (at + 3 > lineBytes) at = lineBytes - 3;
    line[at] = '.', line[at + 1] = '.', line[at + 2] = 0;
  }
  return n;
}

int foldText(const char* text, int maxGlyphs, char* out, size_t n) {
  if (!n) return 0;
  out[0] = 0;
  if (!text || maxGlyphs < 3) return 0;
  // A glyph, with a line break or tab as a space (glyph 0).
  auto glyphOf = [](const char*& p) {
    if (*p == '\n' || *p == '\r' || *p == '\t') return ++p, 0;
    return nextGlyph(p);
  };
  // The glyphs after the spaces it starts with, up to the last that isn't one.
  const char* p = text;
  int total = 0, last = 0;
  for (int g; (g = glyphOf(p)) >= 0;) {
    if (g == 0 && total == 0) continue;
    ++total;
    if (g) last = total;
  }
  const bool cut = last > maxGlyphs;
  const int keep = cut ? maxGlyphs - 2 : last;
  size_t b = 0;
  int written = 0;
  p = text;
  for (int g; written < keep && (g = glyphOf(p)) >= 0;) {
    if (g == 0 && written == 0) continue;
    const size_t len = g == 95 ? 2 : 1;  // "·", the one glyph of two bytes
    if (b + len + (cut ? 2 : 0) >= n) break;
    if (len == 2)
      out[b] = '\xC2', out[b + 1] = '\xB7';
    else
      out[b] = char(g + 0x20);
    b += len, ++written;
  }
  if (cut && b + 2 < n) {
    while (b > 0 && out[b - 1] == ' ') --b, --written;  // "done.." rather than "done .."
    out[b++] = '.', out[b++] = '.', written += 2;
  }
  out[b] = 0;
  return written;
}

}  // namespace render
