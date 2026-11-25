import Foundation
import MellowHarness

/// Why the buddy does what it does, in plain words for the person: the
/// cause of a reaction or a mood, rendered on the Mac from the event the
/// brain answered and its line's facts. The brain never writes it, so it
/// says only what the brain saw. Two lengths: the sentence, for the Mac
/// (the popover, the debug log), and the fact, short enough for the
/// board's lane, or none when the board shows the cause already (a
/// finish's strip) or a sentence is all it has. Every kind of event has a
/// reason or is listed in `silent`, which a test holds to.
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

    /// Led by Boop's age, on the first time you show up today: "Day 41. Boop
    /// dreamed about Tuesday: …", and with nothing else to say, "Day 41."
    public static func day(_ count: Int, leading why: Narration?) -> Narration {
        let day = "day \(count)"
        let fact = why?.fact.map { "\(day): \($0)" }.flatMap { $0.count <= maxFact ? $0 : nil } ?? day
        return Narration(cause: "Day \(count)." + (why.map { " " + $0.cause } ?? ""), fact: fact)
    }

    /// Why it brings up `note`: "Boop remembers you stay up late on Fridays."
    public static func remembers(_ note: String, name: String) -> String {
        guard note.hasPrefix("You ") else { return "\(name) remembers: \(note)" }
        return "\(name) remembers y" + note.dropFirst()
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
            return Narration(cause: "You stepped away.", fact: fit("you stepped away"))
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
            if e.specificType == Core.dismissGesture { return Narration(cause: "You held a finger on the needs-you screen, to stop it showing.") }
            return Touch(e)?.narration.map { n in Narration(cause: n.cause, fact: n.fact.flatMap { fit($0) }) }
        case .ask?:
            guard e.specificType != Asks.ignored else { return Narration(cause: "Nobody answered its question.") }
            guard let answer = facts["answer"]?.string else { return nil }
            return facts["keeps"]?.bool == true ? Narration(cause: "It will remember: \(answer).", fact: fit("{name} will remember"))
                : Narration(cause: "You answered: \(answer).", fact: fit("you picked \(answer)", "\(answer)!"))
        case .said?:
            // The sign answers what you said: the board needs no fact.
            guard let words = facts["words"]?.string, !words.isEmpty else { return nil }
            return Narration(cause: "You said \"\(Self.keep(words))\".")
        case .growth?:
            guard let level = e["level"]?.int else {
                return Narration(cause: "Today's ring is full. Nice work.", fact: fit("\(Growth.perDay) XP today"))
            }
            return Narration(cause: EventLine.grew(level: Int(level), ring: e["ring"]?.bool == true, name: name), fact: fit("level \(level)!"))
        case .world? where e.specificType == World.leagueKind:
            guard let place = e["place"]?.int, let xp = e["xp"]?.int else { return nil }
            return Narration(cause: "Last week \(name) came \(World.ordinal(Int(place))) in the league, with \(xp) XP.",
                             fact: fit(World.leagueSign(place: Int(place), xp: Int(xp))))
        case .world?:
            let counts = WorldGestures.counts(of: e)
            guard let (kind, count) = counts.first else { return nil }
            return Narration(cause: World.sentence(counts, from: (e["from_region"]?.string).flatMap(World.Region.init(rawValue:)),
                                                   by: e["from_name"]?.string, held: e["held"]?.bool == true, name: name),
                             fact: Self.fit(World.facts(kind, count: count), name: name))
        case .wish? where e.phase == .start:
            return (Core.WishKind(rawValue: e.specificType)).map { wish($0, name: name) }
        case .wish?:
            guard let how = Core.WishEnd(rawValue: e.specificType), let kind = (e["kind"]?.string).flatMap(Core.WishKind.init(rawValue:)) else { return nil }
            return how == .met ? Narration(cause: "You gave \(name) its wish: \(kind.words).", fact: fit("wish met!"))
                : how == .gaveup ? Narration(cause: "\(name) wished for \(kind.words), and you left it.", fact: fit("wish left"))
                : nil
        case .press?:
            return Narration(cause: e.specificType == Core.drawerPick ? "You opened a thread from its drawer." : "You pressed its button.")
        case .prompt?:
            guard let reading = PromptReading(facts: e.data) else { return nil }
            return Narration(cause: asked(reading, agent: agent, on: on),
                             fact: fit(reading.kind == .carryOn ? "you told \(agent) go" : "you asked \(agent)", "you asked"))
        case .needsYou?:
            return e.phase == .start ? Narration(cause: "\(agent) needs you\(on).") : Narration(cause: "You answered \(agent)\(on).")
        case .turn? where e.phase == .start:
            return Narration(cause: "\(agent) started work\(on).", fact: fit("\(agent) started", "new task"))
        case .session? where e.phase == .end:
            return Narration(cause: "\(agent)'s thread\(on) ended.")
        case .subagent?:
            return e.phase == .start ? Narration(cause: "\(agent) started a helper\(on).") : Narration(cause: "A helper of \(agent)'s finished\(on).")
        case .act?:
            return e.phase == .start ? act(e.specificType, agent: agent, on: on, name: name)
                : actEnded(e.specificType, passed: e["passed"]?.bool ?? true, on: on, name: name)
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
            return nil
        default:
            return nil
        }
    }

    /// The events no reason is ever given for, each named as `Event.name`
    /// says it, and why: a new reaction with no reason fails its test unless
    /// it says here why it has none.
    public static let silent: [String: String] = [
        "listen start": "log-only: its own LISTENING shows", "listen wait": "log-only", "listen end": "log-only",
        "link start": "log-only: the board's own screen shows it", "link end": "log-only",
        "dream": "Boop's own, and wakes no pass: the telling has its reason",
        "memory": "Boop's own, and wakes no pass",
        "last_message": "its finish says how the turn went (`outcome`)",
        "tool start": "the work stream: the strip's word, never a Moment",
        "session start": "a thread opening is no news, and has no line",
        "tool wait": "the needs-you screen says it",
        "card start": "log-only: Boop holds the card up, part of Doing", "card end": "log-only: the finish plays, then the card shows",
        "invite": "the board's own: it played the payoff or a shrug, and it wakes no pass",
    ]

    /// Why it holds up something it noticed: "It noticed a rough hour: 3
    /// failures."
    public static func noticed(_ fact: String) -> String { "It noticed \(fact)." }

    /// With what's noticed at its moment after the cause, on the Mac; the
    /// board's words stay as they were.
    public func noting(_ noticed: String?) -> Narration {
        guard let noticed else { return self }
        return Narration(cause: cause + " " + noticed, fact: fact)
    }

    /// A wish being made: "Boop wants a pet.", or "Boop wants a pet: you
    /// haven't said hi today."
    public static func wish(_ kind: Core.WishKind, name: String, because: String? = nil) -> Narration {
        Narration(cause: "\(name) wants \(kind.words)" + (because.map { ": \($0)." } ?? "."),
                  fact: fit(["{name} wants \(kind.words)", "wants \(kind.words)", "a wish"], name: name))
    }

    /// A work act starting: "claude is running the tests on api."
    static func act(_ kind: String, agent: String, on: String, name: String) -> Narration {
        switch kind {
        case "tests": Narration(cause: "\(agent) is running the tests\(on).", fact: fit(["\(agent) runs tests", "tests running"], name: name))
        case "build": Narration(cause: "\(agent) is building\(on).", fact: fit(["\(agent) builds", "building"], name: name))
        default: Narration(cause: "\(agent) is pushing\(on).", fact: fit(["\(agent) pushes", "pushing"], name: name))
        }
    }

    /// A work act's result.
    static func actEnded(_ kind: String, passed: Bool, on: String, name: String) -> Narration {
        switch (kind, passed) {
        case ("tests", true): Narration(cause: "The tests\(on) pass.", fact: fit(["tests pass"], name: name))
        case ("tests", false): Narration(cause: "The tests\(on) failed.", fact: fit(["tests failed"], name: name))
        case ("build", true): Narration(cause: "The build\(on) passes.", fact: fit(["build passes"], name: name))
        case ("build", false): Narration(cause: "The build\(on) failed.", fact: fit(["build failed"], name: name))
        case (_, true): Narration(cause: "The push\(on) went out.", fact: fit(["push went out", "pushed"], name: name))
        default: Narration(cause: "The push\(on) failed.", fact: fit(["push failed"], name: name))
        }
    }

    /// The board's caption for a mood that really moved, with no other reason
    /// to show: "Boop's grumpy now".
    static func moodMoved(_ mood: String, name: String) -> String? {
        fit(["{name}'s \(mood) now", "\(mood) now"], name: name)
    }

    /// Why Boop went to sleep, by what's true at that moment: no agent open,
    /// the nap, or a quiet that lasted `dozeMs`.
    public static func sleeping(noAgents: Bool, napping: Bool, away: Bool = false, dozeMs: Int64, name: String) -> Narration {
        if noAgents { return Narration(cause: "No agents are open, so \(name) went to sleep.", fact: fit(["no agents open"], name: name)) }
        if napping { return Narration(cause: "\(name) went for a nap, and you haven't been back.") }
        if away { return Narration(cause: "You stepped away, so \(name) went to sleep.", fact: fit(["you stepped away"], name: name)) }
        let long = span(ms: dozeMs)
        let words = dozeMs == 3_600_000 ? "an hour" : long.words
        return Narration(cause: "Nothing's happened for \(words), so \(name) dozed off.", fact: fit(["quiet for \(long.short)"], name: name))
    }

    /// Why Boop woke: an agent got to work.
    static func woken(by agent: String, on: String, name: String) -> Narration {
        Narration(cause: "\(agent) got to work\(on), so \(name) woke up.", fact: fit(["\(agent) woke {name}", "\(agent) woke it"], name: name))
    }

    /// What it's doing to pass the time, for the popover alone, from the pack's
    /// words for what the face says (`CharacterPack.passing`):
    /// "Boop's stretching to pass the time."
    public static func passing(_ id: String, in pack: CharacterPack) -> String? {
        pack.passing[id].map { $0.ofDoing ? "\(pack.name)'s \($0.words)." : "\(pack.name)'s \($0.words) to pass the time." }
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
        case "ok"?:
            return Narration(cause: "\(subject) \(topic == "tests" ? "pass" : "passes").", fact: fit(topic == "tests" ? "tests pass" : "\(topic) passes"))
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

    /// The most of what you said that a reason quotes, in characters: a
    /// reason says why, so a few lines of your words make the point.
    public static let maxQuote = 160

    /// `words` on one line, at most `maxQuote` characters and a "…", ending
    /// at a word (the board's rule for its own text, `StateSnapshot.cutAt`).
    static func keep(_ words: String) -> String {
        let flat = Array(words.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        guard flat.count > maxQuote else { return String(flat) }
        return String(flat[..<StateSnapshot.cutAt(flat, maxQuote)]) + "…"
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
    /// Boop's energy in a few warm words for the popover, under its mood,
    /// when it isn't normal (`Energy`, the `state`'s `energy`): what the
    /// board's lids and tempo show.
    public static func energy(_ energy: String?, name: String) -> String? {
        switch energy.flatMap(Energy.init(rawValue:)) {
        case .tired?: "\(name)'s getting sleepy."
        case .bright?: "\(name)'s wide awake."
        default: nil
        }
    }
}

extension Narration {
    /// What Boop is celebrating today, for the popover: every special day.
    /// Only the popover says it: the gel wears nothing for one and has
    /// nothing in the air.
    public struct Celebrating: Equatable, Sendable, Identifiable {
        /// `Pip is 50 days old today`.
        public var why: String
        public var id: String { why }

        public init(why: String) {
            self.why = why
        }

        /// The reasons on for today's `specialDays`.
        public static func now(specialDays: [Days.SpecialDay]) -> [Narration.Celebrating] {
            specialDays.map { Narration.Celebrating(why: $0.why) }
        }
    }
}
