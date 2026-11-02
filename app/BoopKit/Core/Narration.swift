import Foundation
import MellowHarness

/// Why the buddy does what it does, in plain words for the person: the
/// cause of a reaction or a mood, rendered on the Mac from the event the
/// brain answered and its line's facts. The brain never writes it, so it
/// says only what the brain saw. Two lengths: the sentence, for the Mac
/// (the popover, the debug log), and the fact, short enough for the
/// board's lane, or none when the board shows the cause already (a
/// finish's strip) or a sentence is all it has.
public struct Narration: Equatable, Sendable {
    /// What happened, as a sentence: "You stroked it.", "You came back
    /// after 12 hours away."
    public var cause: String
    /// The same for the board, at most `maxFact` characters: "stroked",
    /// "away 12 h". Nil for none.
    public var fact: String?

    /// The longest fact, a sign's width on the board (firmware
    /// `kSignGlyphs`).
    public static let maxFact = Signs.maxLength

    public init(cause: String, fact: String? = nil) {
        self.cause = cause
        self.fact = fact.flatMap { $0.count <= Self.maxFact ? $0 : nil }
    }

    /// The sentence for a reaction in `face`: "Boop is happy. You stroked it."
    public func reaction(face: String, name: String) -> String { "\(name) is \(face). \(cause)" }

    /// The sentence for the mood: "Boop is lonely. You came back after a
    /// day away."
    public func mood(_ mood: String, name: String) -> String { "\(name) is \(mood). \(cause)" }

    /// What a care gesture did, as the cause and the board's fact, by the
    /// gesture's name (render::Gesture's, and the app's `facedown`). Nil
    /// for one that isn't the person's doing to the buddy itself.
    static let gestures: [String: (cause: String, fact: String)] = [
        "stroke": ("You stroked it.", "stroked"),
        "ruffle": ("You stroked it the wrong way.", "ruffled"),
        "nose": ("You booped its nose.", "booped"),
        "tickle": ("You tickled it.", "tickled"),
        "dizzy": ("You shook it.", "shaken"),
        "pickup": ("You picked it up.", "picked up"),
        "startle": ("You thumped the desk.", "thump!"),
        "facedown": ("You turned it face down.", "face down"),
        "peekaboo": ("You turned it back up.", "peekaboo"),
    ]

    /// The cause of NOW's event `e`, from its line, `line` (nil when the
    /// line isn't known: the reason is then the event's kind alone). One
    /// row per kind of line: a kind with no row says its line, and gives
    /// the board nothing.
    public static func of(_ e: Event, line: Line?, untouchedMs: Int64? = nil) -> Narration? {
        let facts = line?.facts ?? [:]
        // The line that tells the dream: the dream is the reason.
        if let told = facts["dream_told"]?.string { return Narration(cause: told, fact: facts["dream_fact"]?.string) }
        switch e.type {
        case .presence? where e.phase == .end:
            guard case .int(let ms)? = facts["away_ms"] else { return line.map { Narration(cause: $0.text) } }
            let span = Self.span(ms: ms)
            return Narration(cause: "You came back after \(span.words) away.", fact: "away \(span.short)")
        case .poke?:
            let count = facts["in_a_row"]?.int ?? 1
            if facts["asleep"]?.bool == true { return Narration(cause: "You poked it while it slept.", fact: "woken up") }
            return count > 1 ? Narration(cause: "You poked it \(count) times in a row.", fact: "poked x\(count)")
                : Narration(cause: "You poked it.", fact: "poked")
        case .gesture?:
            guard let g = gestures[e.specificType] else { return line.map { Narration(cause: $0.text) } }
            return Narration(cause: g.cause, fact: g.fact)
        case .ask? where e.specificType != Asks.ignored:
            guard let answer = facts["answer"]?.string else { return line.map { Narration(cause: $0.text) } }
            return facts["keeps"]?.bool == true ? Narration(cause: "It will remember: \(answer).", fact: "remembered!")
                : Narration(cause: "You answered: \(answer).", fact: "\(answer)!")
        case .checkIn? where e.specificType == "check_in":
            // A check-in after hours with no touch or word: how long, from
            // CONTEXT's company.
            guard let ms = untouchedMs, ms >= ContextSection.untouchedShownMs else { return line.map { Narration(cause: $0.text) } }
            let hours = ms / 3_600_000
            return Narration(cause: "You've been here \(hours) hour\(hours == 1 ? "" : "s") and haven't touched it.", fact: "untouched \(hours) h")
        case .said?:
            // The sign answers what you said: the board needs no fact.
            guard let words = facts["words"]?.string, !words.isEmpty else { return line.map { Narration(cause: $0.text) } }
            return Narration(cause: "You said \"\(words)\".")
        default:
            return line.map { Narration(cause: $0.text) }
        }
    }

    /// A span of `ms` in words and as the board's few characters: "25
    /// minutes" and "25 min", "12 hours" and "12 h", "2 days" and "2 d".
    static func span(ms: Int64) -> (words: String, short: String) {
        let minutes = max(1, ms / 60_000)
        if minutes < 60 { return ("\(minutes) minute\(minutes == 1 ? "" : "s")", "\(minutes) min") }
        let hours = minutes / 60
        if hours < 48 { return ("\(hours) hour\(hours == 1 ? "" : "s")", "\(hours) h") }
        let days = hours / 24
        return ("\(days) days", "\(days) d")
    }
}

extension Narration {
    /// Why the board looks as it does now, for the popover: each reason, first
    /// every special day Boop is celebrating today, then the night or the
    /// morning and the Friday, with what the board wears or
    /// shows for it. It chooses
    /// as the board does, from the same tags (firmware/src/render/tags.cpp's
    /// outfitFor, eyewearFor and airFor): one hat, the first that fits, of a
    /// witch hat at Halloween, a party hat, a nightcap at night and a bobble
    /// hat in the winter holidays; on the gel, shades on a Friday from noon short of night (off while it
    /// shows a feeling, which the popover doesn't follow), neither while it
    /// sleeps, and pyjamas with the nightcap when it wears neither; on the
    /// gel in the morning, the sun, and a coffee while it's awake
    /// (render/gel/layers.cpp's layerContents); and in the
    /// air, confetti at a party or New Year, snow in the winter holidays and
    /// hearts on Valentine's.
    public struct Dressing: Equatable, Sendable, Identifiable {
        public enum Kind: Sendable { case specialDay, night, morning, friday }

        public var kind: Kind
        /// `Boop became a Sprout today`, `It's Friday`.
        public var why: String
        /// What the board wears or shows for it, in a few words: `a party hat
        /// and confetti`. Nil for an occasion it only plays along with.
        public var what: String?
        public var id: String { why }

        public init(kind: Kind, why: String, what: String?) {
            self.kind = kind
            self.why = why
            self.what = what
        }

        /// The reasons on for `when` (the `state`'s tags) and today's
        /// `occasions`, `asleep` when the board's look is, and `gel` for a
        /// board that draws the gel, which alone wears eyewear and pyjamas.
        public static func now(when: [String], specialDays: [Days.SpecialDay], asleep: Bool, gel: Bool) -> [Narration.Dressing] {
            let on = Set(when)
            let party = ["party", "newyear", "lunar", "programmers"].contains(where: on.contains)
            let hat = on.contains("halloween") ? "halloween" : party ? "party" : on.contains("night") ? "night" : on.contains("winter") ? "winter" : nil
            let shades = gel && !asleep && on.contains("friday") && !on.contains("night") && !on.contains("morning")

            var out: [Narration.Dressing] = specialDays.map { o in
                var things: [String] = []
                switch o.tag {
                case "halloween"?: if hat == "halloween" { things.append("a witch hat") }
                case "winter"?:
                    if hat == "winter" { things.append("a bobble hat") }
                    things.append("snow")
                case "valentines"?: things.append("hearts")
                case nil, "newyear"?, "lunar"?, "programmers"?:
                    if hat == "party" { things.append("a party hat") }
                    if o.tag == nil || o.tag == "newyear" { things.append("confetti") }
                default: break
                }
                return Narration.Dressing(kind: .specialDay, why: o.why, what: list(things))
            }
            if hat == "night" {
                out.append(Narration.Dressing(kind: .night, why: "It's night", what: gel && !shades ? "a nightcap and pyjamas" : "a nightcap"))
            }
            if gel && on.contains("morning") && !on.contains("night") {
                out.append(Narration.Dressing(kind: .morning, why: "It's morning", what: asleep ? "the sun" : "the sun and a coffee"))
            }
            if shades { out.append(Narration.Dressing(kind: .friday, why: "It's Friday", what: "shades")) }
            return out
        }

        /// `a`, `a and b`, `a, b and c`; nil for none.
        static func list(_ things: [String]) -> String? {
            guard let last = things.last else { return nil }
            return things.count == 1 ? last : things.dropLast().joined(separator: ", ") + " and " + last
        }
    }
}
