// The three anti-aliased fonts (the v1 build plan's F2, and the needs-you screen's): Geist Mono, generated into
// firmware/assets/fonts.h by internal/tools/fontgen. Monospaced, printable ASCII plus
// "·" (UTF-8 C2 B7). Accented Latin letters (U+00C0 to U+00FF) show as their
// plain letter and anything else as "?". Text is drawn over black with an
// ink ramp, or in black over the needs-you screen's amber (kInkOnAmber).
#pragma once
#include <cstddef>
#include <cstdint>

#include "render/canvas.h"

namespace render {

struct Font {
  uint8_t w, h, baseline, count;
  const uint8_t* data;  // 4-bit coverage, high nibble first, row by row
};

extern const Font& kSmall;  // 8 × 18 cells, for the strip
extern const Font& kLarge;  // 13 × 30 cells, for the bubble's text
extern const Font& kSign;   // 17 × 38 cells, for a reaction's sign, the needs-you screen's thread and the gel's lane

// Draws `text` with its cell's top-left at (x, y). Returns the x after it.
int drawString(Canvas& c, const Font& f, int x, int y, const char* text, int ink);
// Width in pixels; glyphs are counted, not bytes.
int stringWidth(const Font& f, const char* text);
// Draws at most `maxWidth` pixels of text, cut as cutAt cuts it if it
// doesn't fit.
int drawStringFit(Canvas& c, const Font& f, int x, int y, const char* text, int ink, int maxWidth);
// Characters (glyphs, not bytes) in `text`.
int glyphCount(const char* text);
// The glyph index of the character at `p` (UTF-8: "·" and accented Latin
// letters as above, anything else "?"), advancing `p` past it; -1 at the
// end. For drawing text elsewhere than the canvas (the gel's lane).
int nextGlyph(const char*& p);
// The one rule for text that doesn't fit, on every face: how many of its
// glyphs to keep when it's cut to at most `most` and ".." after them (the
// fonts have no "…"). At the end of the last word that ends within them
// after the last "·" (a separator: "claude · a-long-project" is cut in
// the project's name), when that keeps at least half of them; else
// `most`, mid-word. Never ending on a space or a "·".
int cutAt(const char* text, int most);
// Splits `text` into at most `maxLines` lines of at most `cols` glyphs,
// breaking at spaces and after hyphens where it can and inside a word
// only when the word is longer than a line; the last line ends "..", cut
// as cutAt cuts it, when the text doesn't fit. Each line is written,
// NUL-terminated, into `out` (`lineBytes` per line). Returns how many
// lines.
int wrapText(const char* text, int cols, int maxLines, char* out, int lineBytes);
// `text` as the fonts draw it, into `out` (`n` bytes): accented letters as
// their plain letter, "·" kept, anything else unknown "?", a line break or
// tab a space, and no spaces at either end. More than `maxGlyphs` glyphs
// are cut as cutAt cuts them to maxGlyphs - 2, and "..", so it's at most
// maxGlyphs. Returns its glyphs.
int foldText(const char* text, int maxGlyphs, char* out, size_t n);

}  // namespace render
