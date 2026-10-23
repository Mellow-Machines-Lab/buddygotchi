import Foundation

/// What a buddy may hold up on a sign about your prompt: the pack's
/// captions (`signs.md`) whose tags the prompt's reading has, each line
/// with `{words}` filled in once for each of your phrases (`{WORDS}` in
/// capitals), so your own words come back in the buddy's way: "still
/// broken :(", "'just', sure". The brain picks one, or none (`react.sign`).
public enum Signs {
    public static let questionKey = "react.sign"
    /// The most captions offered, and the longest a sign shows, in
    /// characters: the board cuts a longer one.
    public static let maxOffered = 6, maxLength = 18

    /// The tags a reading has: its kind, tone and length, `named` when you
    /// said the buddy's name, `words` when it kept a phrase of yours, and
    /// the calendar's (`Occasions`, `night`, `friday`…).
    public static func tags(_ r: PromptReading, calendar: [String]) -> Set<String> {
        Set([r.kind?.rawValue, r.tone?.rawValue, r.length.rawValue, r.named ? "named" : nil, r.phrases.isEmpty ? nil : "words"]
            .compactMap { $0 } + calendar)
    }

    /// The captions that fit `reading`, filled in, that fit a sign: your
    /// words in a tagged line first, then your words as they are, then the
    /// tagged captions, then the rest, each once, at most `maxOffered`.
    public static func offered(_ lines: [TaggedLine], reading: PromptReading, calendar: [String]) -> [String] {
        let on = tags(reading, calendar: calendar)
        let fit = lines.filter { $0.fits(on) }
        func filled(_ line: TaggedLine) -> [String] {
            guard line.hasWords else { return [line.text] }
            return reading.phrases.map {
                line.text.replacingOccurrences(of: "{words}", with: $0).replacingOccurrences(of: "{WORDS}", with: $0.uppercased())
            }
        }
        func rank(_ line: TaggedLine) -> Int { (line.hasWords ? 0 : 2) + (line.tags.isEmpty ? 1 : 0) }
        let ordered = (0..<4).flatMap { r in fit.filter { rank($0) == r }.flatMap(filled) }
        var seen: Set<String> = []
        return Array(ordered.filter { $0.count <= maxLength && seen.insert($0.lowercased()).inserted }.prefix(maxOffered))
    }
}
