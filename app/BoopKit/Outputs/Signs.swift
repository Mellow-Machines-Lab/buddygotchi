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

    /// The signs a dream may hold up (`dreams.md`): the lines whose tags
    /// the day's `tags` (and the calendar's) all have, those with tags
    /// first, in the file's order, so the lines about the person come
    /// first, each once, at most `maxOffered`.
    public static func dreams(_ lines: [TaggedLine], tags: [String]) -> [String] {
        let on = Set(tags)
        let fit = lines.filter { $0.fits(on) && $0.text.count <= maxLength }
        var seen: Set<String> = []
        return (fit.filter { !$0.tags.isEmpty } + fit.filter { $0.tags.isEmpty }).map(\.text)
            .filter { seen.insert($0).inserted }.prefix(maxOffered).map { $0 }
    }

    /// The tags a reading has for the buddy called `name`: its kind, tone
    /// and length, `named` when you said its name, and the calendar's
    /// (`Tags`, `night`, `friday`…). A `{words}` line needs no tag: it
    /// yields nothing without a phrase of yours.
    public static func tags(_ r: PromptReading, name: String, calendar: [String]) -> Set<String> {
        Set([r.kind?.rawValue, r.tone?.rawValue, r.length.rawValue, r.named.contains(name) ? "named" : nil].compactMap { $0 } + calendar)
    }

    /// The captions that fit `reading`, for the buddy called `name`,
    /// filled in, that fit a sign: your words in a tagged line first, then
    /// your words as they are, at most `maxYourWords` of them, then the
    /// tagged captions, then the rest, each once, at most `maxOffered`.
    /// A musing is held up at most this often.
    public static let musingEveryMs: Int64 = 60 * 60_000

    /// The idle musings: `signs.md`'s `[idle]` lines whose other tags the
    /// calendar and the kept answers (`tags`) all have, their blanks filled
    /// from the day so far, `{turns}` with its turns (a line that needs
    /// them is left out under 2) and `{thread}` with its busiest thread;
    /// at most `maxOffered`, each at most `maxLength`.
    public static func musings(_ lines: [TaggedLine], tags: [String], turns: Int, thread: String) -> [String] {
        let on = Set(tags + ["idle"])
        return lines.filter { $0.tags.contains("idle") && $0.fits(on) }.compactMap { line -> String? in
            if line.text.contains("{turns}"), turns < 2 { return nil }
            if line.text.contains("{thread}"), thread.isEmpty { return nil }
            let text = line.text.replacingOccurrences(of: "{turns}", with: String(turns)).replacingOccurrences(of: "{thread}", with: thread)
            return drawn(text).flatMap { $0.count <= maxLength ? $0 : nil }
        }.prefix(maxOffered).map { $0 }
    }

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

    /// What a buddy may hold up replying `reply` to what you said: the
    /// pack's lines for it (`replies.md`) that fit the calendar's and the
    /// moment's tags, only those with the most of the moment's
    /// (`MomentOutput.momentTags`: a `nap` while an agent works beats a
    /// plain one), the calendar's joining the plain ones (a night `bye`
    /// among the rest, so it's not the only one all night), a line with
    /// `{words}` once for each of `phrases`, and not `avoiding` (the last
    /// reply's) while another fits.
    public static func replies(_ lines: [TaggedLine], _ reply: String, calendar: [String], phrases: [String] = [],
                               avoiding: String? = nil) -> [String] {
        let on = Set([reply] + calendar)
        let fit = lines.filter { $0.tags.first == reply && $0.fits(on) }
        func moment(_ line: TaggedLine) -> Int { line.tags.filter(MomentOutput.momentTags.contains).count }
        guard let most = fit.map(moment).max() else { return [] }
        var pool: [String] = []
        for line in fit where moment(line) == most {
            let texts = line.hasWords ? phrases.map { line.text.replacingOccurrences(of: "{words}", with: $0) } : [line.text]
            for text in texts.compactMap(drawn) where text.count <= maxLength && !pool.contains(text) { pool.append(text) }
        }
        if pool.count > 1 { pool.removeAll { $0 == avoiding } }
        return pool
    }

    /// What a buddy holds up replying `reply` to what you said, with no
    /// brain to pick: one of `replies`' lines at random, never one with
    /// your words. Nil when none fits.
    public static func reply(_ lines: [TaggedLine], _ reply: String, calendar: [String], avoiding: String? = nil,
                             rng: inout SplitMix64) -> String? {
        let pool = replies(lines, reply, calendar: calendar, avoiding: avoiding)
        return pool.isEmpty ? nil : pool[rng.int(in: 0...(pool.count - 1))]
    }

    /// The longest phrase of what you said that a reply's sign plays back.
    public static let maxPhrase = 12

    /// What you said, as phrases a reply's line may play back (`{words}`):
    /// the whole of it and each of its parts between marks, lowercased, with
    /// the buddy's name taken out, each at most `maxPhrase` characters.
    /// "Hello!" gives `hello`, and "thanks, boop" gives `thanks`.
    public static func phrases(of said: String, name: String = CharacterPack.active.name) -> [String] {
        let marks = CharacterSet(charactersIn: ",.?!;:")
        let parts = [said] + said.components(separatedBy: marks)
        var out: [String] = []
        for part in parts {
            let words = part.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }
                .map(String.init).filter { $0 != name.lowercased() }
            let phrase = words.joined(separator: " ")
            if !phrase.isEmpty, phrase.count <= maxPhrase, drawn(phrase) == phrase, !out.contains(phrase) { out.append(phrase) }
        }
        return out
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
