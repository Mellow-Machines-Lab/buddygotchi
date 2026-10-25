#include "render/font.h"

#include <algorithm>

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

constexpr int kDot = 95;  // "·", the first extra after '~'

// The bytes of `text`'s first `glyphs` glyphs.
int bytesOf(const char* text, int glyphs) {
  const char* p = text;
  for (int i = 0; i < glyphs && nextGlyph(p) >= 0; ++i) {
  }
  return int(p - text);
}

}  // namespace

int nextGlyph(const char*& p) {
  unsigned char c = static_cast<unsigned char>(*p);
  if (!c) return -1;
  ++p;
  unsigned char next = static_cast<unsigned char>(*p);
  if (c == 0xC2 && next == 0xB7) {
    ++p;
    return kDot;
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

// The palette index of each of a font's 16 coverages in an ink, worked out
// once for a string: 0 for none, since no ink's ramp starts at black.
struct Inked {
  uint8_t at[16];
  explicit Inked(int ink) {
    for (int v = 0; v < 16; ++v) {
      const int level = (v * kLevels + 7) / 15;
      at[v] = level > 0 ? textAt(ink, level) : 0;
    }
  }
};
static_assert(textAt(kInkEye, 1) != kBlack && textAt(kInkOnAmber, 1) != kBlack, "an ink's first step isn't black");

void drawGlyph(Canvas& c, const Font& f, int x, int y, int g, const Inked& ink) {
  const int rowBytes = (f.w + 1) / 2;
  const uint8_t* src = f.data + size_t(g) * rowBytes * f.h;
  const int row0 = std::max(0, -y), row1 = std::min<int>(f.h, kHeight - y);
  const int col0 = std::max(0, -x), col1 = std::min<int>(f.w, kWidth - x);
  // Drawn whole, the mask is no test.
  const bool whole = c.mask().all();
  for (int row = row0; row < row1; ++row) {
    const uint8_t* bits = src + row * rowBytes;
    uint8_t* line = c.pixels() + (y + row) * kWidth;
    for (int col = col0; col < col1; ++col) {
      const uint8_t color = ink.at[(col & 1) ? (bits[col / 2] & 15) : (bits[col / 2] >> 4)];
      if (!color) continue;
      if (whole)
        line[x + col] = color;
      else
        c.plot(x + col, y + row, color);
    }
  }
}

}  // namespace

int drawString(Canvas& c, const Font& f, int x, int y, const char* text, int ink) {
  const Inked inked(ink);
  for (int g; (g = nextGlyph(text)) >= 0; x += f.w) drawGlyph(c, f, x, y, g, inked);
  return x;
}

int stringWidth(const Font& f, const char* text) { return glyphCount(text) * f.w; }

int drawStringFit(Canvas& c, const Font& f, int x, int y, const char* text, int ink, int maxWidth) {
  if (stringWidth(f, text) <= maxWidth) return drawString(c, f, x, y, text, ink);
  const Inked inked(ink);
  for (int keep = cutAt(text, maxWidth / f.w - 2), g; keep > 0 && (g = nextGlyph(text)) >= 0; --keep, x += f.w)
    drawGlyph(c, f, x, y, g, inked);
  for (int i = 0; i < 2; ++i, x += f.w) drawGlyph(c, f, x, y, '.' - 0x20, inked);
  return x;
}

int glyphCount(const char* text) {
  int n = 0;
  while (nextGlyph(text) >= 0) ++n;
  return n;
}

int cutAt(const char* text, int most) {
  int word = 0, solid = 0, prev = 0;
  const char* p = text;
  for (int i = 0; i <= most; ++i) {
    const int g = nextGlyph(p);
    if (g == kDot)
      word = 0;  // the cut stays in what follows the last "·"
    else if (g <= 0 && prev > 0 && prev != kDot)
      word = i;  // a word ends before glyph i
    if (g < 0) break;
    if (g > 0 && g != kDot && i < most) solid = i + 1;
    prev = g;
  }
  return word > 0 && 2 * word >= most ? word : solid;
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
  bool spaced = false;  // a space comes before the next piece
  while (*p && !cut) {
    // The next piece: a word, or a word's part up to and with its hyphen,
    // after which a line may break.
    const char* end = p;
    while (*end && *end != ' ' && *end != '-') ++end;
    while (*end == '-') ++end;
    int wg = 0;
    for (const char* q = p; q < end; ++wg) nextGlyph(q);
    if (n == 0 || g + spaced + wg > cols) {
      if (!next()) cut = true;
    } else if (spaced) {
      line[b++] = ' ', line[b] = 0, ++g;
    }
    // The piece, a glyph at a time, onto more lines when it's longer than one.
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
    spaced = *p == ' ';
    while (*p == ' ') ++p;
  }
  if (cut && n > 0) {  // the last line ends "..", within its columns and bytes, where cutAt cuts it
    int most = cols - 2, keep = g <= most ? g : cutAt(line, most);
    while (keep > 0 && bytesOf(line, keep) + 3 > lineBytes) keep = cutAt(line, --most);
    const int at = bytesOf(line, keep);
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
  // Folded: all of them when they fit, else a cut's room and the glyph
  // after it, which says whether a word ends there (cutAt).
  const bool cut = last > maxGlyphs;
  size_t b = 0;
  int written = 0;
  p = text;
  for (int g; written < (cut ? maxGlyphs - 1 : last) && (g = glyphOf(p)) >= 0;) {
    if (g == 0 && written == 0) continue;
    const size_t len = g == kDot ? 2 : 1;  // "·", the one glyph of two bytes
    if (b + len >= n) break;
    if (len == 2)
      out[b] = '\xC2', out[b + 1] = '\xB7';
    else
      out[b] = char(g + 0x20);
    b += len, ++written;
  }
  out[b] = 0;
  if (!cut || n < 3) return written;
  int most = std::min(maxGlyphs - 2, written), keep = cutAt(out, most);
  while (keep > 0 && size_t(bytesOf(out, keep)) + 3 > n) keep = cutAt(out, --most);
  b = size_t(bytesOf(out, keep));
  out[b] = '.', out[b + 1] = '.', out[b + 2] = 0;
  return keep + 2;
}

}  // namespace render
