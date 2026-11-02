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

    /// The cause of NOW's event `e`, from its line, `line` (nil when the
    /// line isn't known). One row per kind of event, each a sentence in
    /// the person's words: never the brain's line, which names threads
    /// by their folders and turns by number. A kind with no row, or a row
    /// missing what it needs, gives no reason, and the Mac shows the mood
    /// alone. The board gets a fact only where it adds something the
    /// screen doesn't show.
    public static func of(_ e: Event, line: Line?, untouchedMs: Int64? = nil, name: String = CharacterPack.active.name) -> Narration? {
        func fit(_ options: String...) -> String? { Self.fit(options, name: name) }
        let facts = line?.facts ?? [:]
        // The line that tells the dream: the dream is the reason.
        if let told = facts["dream_told"]?.string { return Narration(cause: told, fact: facts["dream_fact"]?.string) }
        let thread = facts["thread"]?.object
        let agent = thread?["agent"]?.string ?? e.agent?.rawValue ?? "the agent"
        let on = place(thread).map { " on \($0)" } ?? ""
        // A finish, with its last message's reading if it came, whichever
        // event brought it (a turn's end, its reading, or needs you
        // clearing over a finish you missed).
        if let outcome = facts["outcome"]?.string { return finish(outcome, facts, agent: agent, on: on) }
        switch e.type {
        case .presence? where e.phase == .end:
            guard case .int(let ms)? = facts["away_ms"] else { return nil }
            let span = Self.span(ms: ms)
            return Narration(cause: "You came back after \(span.words) away.", fact: fit("you were away \(span.short)", "away \(span.short)"))
        case .presence?:
            return Narration(cause: "You stepped away.")
        case .lock?:
            return e.phase == .start ? Narration(cause: "You locked the Mac.", fact: fit("you locked the Mac", "Mac locked"))
                : Narration(cause: "You unlocked the Mac.", fact: fit("you unlocked it", "Mac unlocked"))
        case .poke?:
            let count = facts["in_a_row"]?.int ?? 1
            if facts["asleep"]?.bool == true { return Narration(cause: "You poked it while it slept.", fact: fit("you woke {name}")) }
            return count > 1 ? Narration(cause: "You poked it \(count) times in a row.", fact: fit("you poked {name} x\(count)"))
                : Narration(cause: "You poked it.", fact: fit("you poked {name}"))
        case .gesture?:
            if let count = facts["in_a_row"]?.int, count > 1 {
                return Narration(cause: "You shook it \(count) times in a row.", fact: fit("you shook {name} x\(count)"))
            }
            return Touch(e)?.narration.map { Narration(cause: $0.cause, fact: fit($0.fact)) }
        case .ask?:
            guard e.specificType != Asks.ignored else { return Narration(cause: "Nobody answered its question.") }
            guard let answer = facts["answer"]?.string else { return nil }
            return facts["keeps"]?.bool == true ? Narration(cause: "It will remember: \(answer).", fact: fit("{name} will remember"))
                : Narration(cause: "You answered: \(answer).", fact: fit("you picked \(answer)", "\(answer)!"))
        case .said?:
            // The sign answers what you said: the board needs no fact.
            guard let words = facts["words"]?.string, !words.isEmpty else { return nil }
            return Narration(cause: "You said \"\(words)\".")
        case .wish?:
            guard let how = Core.WishEnd(rawValue: e.specificType), let kind = (e["kind"]?.string).flatMap(Core.WishKind.init(rawValue:)) else { return nil }
            return how == .met ? Narration(cause: "You gave \(name) its wish: \(kind.words).", fact: fit("wish met!"))
                : how == .gaveup ? Narration(cause: "\(name) wished for \(kind.words), and you left it.", fact: fit("wish left"))
                : nil
        case .press?:
            return Narration(cause: e.specificType == Core.drawerPick ? "You opened a thread from its drawer." : "You pressed its button.")
        case .hush?:
            guard e.phase == .start else { return Narration(cause: "It may talk again.") }
            let minutes = e["minutes"]?.int ?? 0
            return Narration(cause: minutes > 0 ? "You told it to be quiet for \(minutes) minutes." : "You told it to be quiet.")
        case .prompt?:
            guard let reading = PromptReading(facts: e.data) else { return nil }
            return Narration(cause: asked(reading, agent: agent, on: on))
        case .needsYou?:
            return e.phase == .start ? Narration(cause: "\(agent) needs you\(on).") : Narration(cause: "You answered \(agent)\(on).")
        case .turn? where e.phase == .start:
            return Narration(cause: "\(agent) started work\(on).")
        case .session? where e.phase == .start:
            return Narration(cause: "\(agent)'s memory\(on) was compacted.")
        case .tool?:
            return check(facts, agent: agent, on: on, name: name)
        case .checkIn?:
            if case .int(let ms)? = facts["working_ms"] {
                let span = Self.span(ms: ms)
                return Narration(cause: "\(agent) has been working\(on) for \(span.words).", fact: "working \(span.short)")
            }
            if e.specificType == "check_in", let ms = untouchedMs, ms >= ContextSection.untouchedShownMs {
                // A check-in after hours with no touch or word: how long,
                // from CONTEXT's company.
                let hours = ms / 3_600_000
                return Narration(cause: "You've been here \(hours) hour\(hours == 1 ? "" : "s") and haven't touched it.",
                                 fact: fit("no touch in \(hours) h"))
            }
            if case .int(let minutes)? = facts["idle_minutes"] {
                return Narration(cause: "Nothing has happened for \(Self.span(ms: minutes * 60_000).words).")
            }
            if case .int(let hours)? = facts["idle_hours"] {
                return Narration(cause: "Nothing has happened for \(Self.span(ms: hours * 3_600_000).words).")
            }
            return nil
        default:
            return nil
        }
    }

    /// A turn's end: how it went, by its outcome and what its last
    /// message said. No fact: the finish's sign names the thread.
    static func finish(_ outcome: String, _ facts: [String: JSONValue], agent: String, on: String) -> Narration {
        let message = facts["message"]?.object?["kind"]?.string.flatMap(MessageReading.Kind.init(rawValue:))
        let length = facts["length_ms"]?.int.map { Band.length(ms: $0) }
        let wins = facts["wins_in_a_row"]?.int ?? 0
        switch outcome {
        case "failed": return Narration(cause: "\(agent)'s turn\(on) failed.")
        case "stopped": return Narration(cause: "\(agent)'s turn\(on) was stopped.")
        default: break
        }
        if message == .stuck { return Narration(cause: "\(agent) gave up\(on).") }
        if message == .question { return Narration(cause: "\(agent) has a question for you\(on).") }
        if let topic = facts["comeback"]?.string { return Narration(cause: "\(agent) got the \(topic) passing\(on).") }
        if wins > 1 { return Narration(cause: "\(agent) finished \(wins) quick turns in a row\(on).") }
        if length == "very long" { return Narration(cause: "\(agent) finished a long turn\(on).") }
        if length == "very short" { return Narration(cause: "\(agent) answered you\(on).") }
        return Narration(cause: "\(agent) finished a turn\(on).")
    }

    /// A tool call worth a line: a check failing or passing again, or the
    /// agent's calls failing again and again.
    static func check(_ facts: [String: JSONValue], agent: String, on: String, name: String) -> Narration? {
        func fit(_ options: String...) -> String? { Self.fit(options, name: name) }
        if case .int(let rung)? = facts["failing"] {
            return Narration(cause: "\(agent)'s calls\(on) keep failing: \(rung) times in \(WorkStream.ladderMs / 60_000) minutes.",
                             fact: fit("calls failed x\(rung)"))
        }
        guard let topic = facts["topic"]?.string, TranscriptView.checks.contains(topic) else { return nil }
        let before = facts["failed_before"]?.int ?? 0
        let subject = topic == "tests" ? "The tests\(on)" : "The \(topic)\(on)"
        switch facts["result"]?.string {
        case "failed"?:
            return before > 0 ? Narration(cause: "\(subject) failed again: \(before + 1) times in a row.", fact: fit("\(topic) failed x\(before + 1)", "\(topic) x\(before + 1)"))
                : Narration(cause: "\(subject) failed.", fact: fit("\(topic) failed"))
        case "ok"? where before > 0:
            return Narration(cause: "\(subject) \(topic == "tests" ? "pass" : "passes") again.", fact: fit(topic == "tests" ? "tests pass again" : "\(topic) passes again", "\(topic) passes"))
        default:
            return nil
        }
    }

    /// Your prompt, from its reading alone: what you asked for and how
    /// you sounded, never your words.
    static func asked(_ r: PromptReading, agent: String, on: String) -> String {
        let what: String
        switch r.kind {
        case .question?: what = "You asked \(agent) a question\(on)"
        case .carryOn?: what = "You told \(agent) to carry on\(on)"
        case let kind?: what = "You asked \(agent) \(kind.words)\(on)"
        case nil: what = "You wrote to \(agent)\(on)"
        }
        let how: String
        switch r.tone {
        case .calm?, nil: how = ""
        case .frustrated?: how = ", sounding frustrated"
        case .shouting?: how = ", shouting"
        case let tone?: how = ", " + (tone.words ?? "")
        }
        return what + how + "."
    }

    /// Where a thread works, as the person knows it: its workspace (a
    /// branch or a worktree) when that's a name, else its project. Nil
    /// for none.
    static func place(_ thread: [String: JSONValue]?) -> String? {
        guard let thread else { return nil }
        if let w = thread["workspace"]?.string, !w.isEmpty, !looksLikeAnID(w) { return w }
        return thread["project"]?.string.flatMap { $0 == "unknown" || $0.isEmpty ? nil : $0 }
    }

    /// Whether a name reads as an id, not a name: a part of it, split at
    /// dashes, underscores and dots, eight characters or more with a digit
    /// in it (`bridge-cse-01357dh6…`, `agent-a3ff514bdd7c3721f`).
    static func looksLikeAnID(_ name: String) -> Bool {
        name.split(whereSeparator: { "-_./".contains($0) })
            .contains { $0.count >= 8 && $0.contains(where: \.isNumber) }
    }

    /// The board's caption: the first of `options`, longest first, that
    /// fits a sign's width with `{name}` the buddy's name, else with "it";
    /// nil when none does.
    static func fit(_ options: [String], name: String) -> String? {
        for o in options {
            for who in [name, "it"] {
                let s = o.replacingOccurrences(of: "{name}", with: who)
                if s.count <= maxFact { return s }
            }
        }
        return nil
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
