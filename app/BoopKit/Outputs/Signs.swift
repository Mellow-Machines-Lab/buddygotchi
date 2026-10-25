import Foundation

/// What a buddy may hold up on a sign about your prompt: the pack's
/// captions (`signs.md`) whose tags the prompt's reading has, each line
/// with `{words}` filled in once for each of your phrases (`{WORDS}` in
/// capitals), so your own words come back in the buddy's way: "still
/// broken :(", "'just', sure". The brain picks one, or none (`react.sign`).
public enum Signs {
    public static let questionKey = "react.sign"
    /// The most captions offered, the most of them your words, so a
    /// tagged caption (`named`, `frustrated`…) still has room, and the
    /// longest a sign shows, in characters: the board cuts a longer one
    /// (firmware `kSignGlyphs`).
    public static let maxOffered = 6, maxYourWords = 3, maxLength = 18

    /// The tags a reading has for the buddy called `name`: its kind, tone
    /// and length, `named` when you said its name, `words` when it kept a
    /// phrase of yours, and the calendar's (`Occasions`, `night`,
    /// `friday`…).
    public static func tags(_ r: PromptReading, name: String, calendar: [String]) -> Set<String> {
        Set([r.kind?.rawValue, r.tone?.rawValue, r.length.rawValue, r.named.contains(name) ? "named" : nil,
             r.phrases.isEmpty ? nil : "words"].compactMap { $0 } + calendar)
    }

    /// The captions that fit `reading`, for the buddy called `name`,
    /// filled in, that fit a sign: your words in a tagged line first, then
    /// your words as they are, at most `maxYourWords` of them, then the
    /// tagged captions, then the rest, each once, at most `maxOffered`.
    public static func offered(_ lines: [TaggedLine], reading: PromptReading, name: String = CharacterPack.active.name,
                               calendar: [String]) -> [String] {
        let on = tags(reading, name: name, calendar: calendar)
        let fit = lines.filter { $0.fits(on) }
        func filled(_ line: TaggedLine) -> [String] {
            guard line.hasWords else { return [line.text] }
            return reading.phrases.map {
                line.text.replacingOccurrences(of: "{words}", with: $0).replacingOccurrences(of: "{WORDS}", with: $0.uppercased())
            }
        }
        func rank(_ line: TaggedLine) -> Int { (line.hasWords ? 0 : 2) + (line.tags.isEmpty ? 1 : 0) }
        var seen: Set<String> = []
        func captions(_ ranks: [Int], max: Int) -> [String] {
            var out: [String] = []
            for r in ranks {
                for text in fit.filter({ rank($0) == r }).flatMap(filled).compactMap(drawn)
                where out.count < max && text.count <= maxLength && seen.insert(text.lowercased()).inserted {
                    out.append(text)
                }
            }
            return out
        }
        let words = captions([0, 1], max: maxYourWords)
        return words + captions([2, 3], max: maxOffered - words.count)
    }

    /// What a buddy holds up replying `reply` to what you said: one of the
    /// pack's lines for it (`replies.md`) that fit the calendar's tags,
    /// those with the most tags first (a night `bye` beats a plain one), at
    /// random among them, and not `avoiding` (the last reply's) while
    /// another fits. Nil when none fits.
    public static func reply(_ lines: [TaggedLine], _ reply: String, calendar: [String], avoiding: String? = nil,
                             rng: inout SplitMix64) -> String? {
        let on = Set([reply] + calendar)
        let fit = lines.filter { $0.tags.first == reply && $0.fits(on) && !$0.hasWords }
            .compactMap { line in drawn(line.text).map { (tags: line.tags.count, text: $0) } }
            .filter { $0.text.count <= maxLength }
        guard let most = fit.map(\.tags).max() else { return nil }
        var pool = fit.filter { $0.tags == most }.map(\.text)
        if pool.count > 1 { pool.removeAll { $0 == avoiding } }
        return pool[rng.int(in: 0...(pool.count - 1))]
    }

    /// Typed marks the board's fonts don't have, as the plain ones they
    /// stand for.
    static let plain: [Unicode.Scalar: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201C}": "\"", "\u{201D}": "\"", "\u{2013}": "-", "\u{2014}": "-",
        "\u{2026}": "...", "\u{00A0}": " ",
    ]

    /// `text` as a sign draws it, or nil where the board would draw any of
    /// it as "?": precomposed (an accent typed as its own mark joins its
    /// letter), with curly quotes, dashes, an ellipsis and a no-break
    /// space made plain. The fonts have printable ASCII and "·", and fold
    /// the Latin-1 letters (U+00C0 to U+00FF) to plain ones themselves
    /// (firmware `render::foldText`); nothing else draws.
    public static func drawn(_ text: String) -> String? {
        var out = ""
        for s in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            let mark = plain[s] ?? String(s)
            guard mark.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) || $0.value == 0xB7 || (0xC0...0xFF).contains($0.value) })
            else { return nil }
            out += mark
        }
        return out
    }
}
