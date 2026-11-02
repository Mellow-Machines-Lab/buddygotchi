import Foundation
import MellowHarness

/// Why the buddy does what it does, in plain words for the person: the
/// cause of a reaction or a mood, rendered on the Mac from the event the
/// brain answered and its line's facts. The brain never writes it, so it
/// says only what the brain saw. Two lengths: the sentence, for the Mac
/// (the popover, the debug log), and the fact, short enough for the
/// board's lane, or none when the board shows the cause already (a
/// finish's strip) or a sentence is all it has.
public struct Reason: Equatable, Sendable {
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
    public static func of(_ e: Event, line: Line?, untouchedMs: Int64? = nil) -> Reason? {
        let facts = line?.facts ?? [:]
        // The line that tells the dream: the dream is the reason.
        if let told = facts["dream_told"]?.string { return Reason(cause: told, fact: facts["dream_fact"]?.string) }
        switch e.type {
        case .presence? where e.phase == .end:
            guard case .int(let ms)? = facts["away_ms"] else { return line.map { Reason(cause: $0.text) } }
            let span = Self.span(ms: ms)
            return Reason(cause: "You came back after \(span.words) away.", fact: "away \(span.short)")
        case .poke?:
            let count = facts["in_a_row"]?.int ?? 1
            if facts["asleep"]?.bool == true { return Reason(cause: "You poked it while it slept.", fact: "woken up") }
            return count > 1 ? Reason(cause: "You poked it \(count) times in a row.", fact: "poked x\(count)")
                : Reason(cause: "You poked it.", fact: "poked")
        case .gesture?:
            guard let g = gestures[e.specificType] else { return line.map { Reason(cause: $0.text) } }
            if let count = facts["in_a_row"]?.int, count > 1 {
                return Reason(cause: "You shook it \(count) times in a row.", fact: "shaken x\(count)")
            }
            return Reason(cause: g.cause, fact: g.fact)
        case .ask? where e.specificType != Asks.ignored:
            guard let answer = facts["answer"]?.string else { return line.map { Reason(cause: $0.text) } }
            return facts["keeps"]?.bool == true ? Reason(cause: "It will remember: \(answer).", fact: "remembered!")
                : Reason(cause: "You answered: \(answer).", fact: "\(answer)!")
        case .heartbeat? where e.specificType == "check_in":
            // A check-in after hours with no touch or word: how long, from
            // CONTEXT's company.
            guard let ms = untouchedMs, ms >= ContextSection.untouchedShownMs else { return line.map { Reason(cause: $0.text) } }
            let hours = ms / 3_600_000
            return Reason(cause: "You've been here \(hours) hour\(hours == 1 ? "" : "s") and haven't touched it.", fact: "untouched \(hours) h")
        case .said?:
            // The sign answers what you said: the board needs no fact.
            guard let words = facts["words"]?.string, !words.isEmpty else { return line.map { Reason(cause: $0.text) } }
            return Reason(cause: "You said \"\(words)\".")
        default:
            return line.map { Reason(cause: $0.text) }
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
