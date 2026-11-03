import Foundation

/// The small questions the dream's write asks a model, each in a fresh
/// session: a sentence, or yes or no. A protocol, so tests can stand in for
/// it.
public protocol MemoryModel: Sendable {
    func text(_ instructions: String, _ prompt: String, tokens: Int) async -> String?
    func yes(_ instructions: String, _ prompt: String) async -> Bool?
}

/// The dream's write as code that proposes and a small model that only
/// answers small questions: code counts the habits and the sagas
/// (`MemoryProposer`) and writes the notes and the day line; the model says
/// which things you said to Boop are worth keeping and not private, and
/// whether what you said ends a project's story. Its reply is in the checks'
/// grammar (`MemoryEdits`).
public enum MemoryPipeline {
    public struct Input: Equatable, Sendable {
        public var memory: WrittenMemory
        /// Oldest first, tonight's last.
        public var digests: [DayDigest]
        public var certain: String
        public var journal: [Journal]
        public var day: String, weekday: String
        /// Notes it added once that are gone now: you deleted them, so they stay gone.
        public var forgotten: [String] = []

        public struct Journal: Equatable, Sendable {
            public var at: String, line: String
            public init(at: String, line: String) { self.at = at; self.line = line }
        }

        public init(memory: WrittenMemory, digests: [DayDigest], certain: String, journal: [(at: String, line: String)], day: String, weekday: String) {
            self.memory = memory
            self.digests = digests
            self.certain = certain
            self.journal = journal.map { Journal(at: $0.at, line: $0.line) }
            self.day = day
            self.weekday = weekday
        }
    }

    // MARK: The questions, one rule each

    public static let worth = """
        Someone said this to the small pet on their desk. Would a good friend still remember it a month from now?
        Yes: a win, a first, something shipped or finished, something they love or hate about their work.
        No: a greeting, a goodnight, small talk, a question, a request, a passing mood.
        Answer yes or no.
        """
    public static let isPrivate = """
        Someone said this to the small pet on their desk. Is it private? Yes if it touches health, doctors, medicine, money, debts, family, a partner, love, a break-up, politics, voting, religion, looking for a job, or names another person. Otherwise no.
        Answer yes or no.
        """
    static let paraphrase = """
        Someone said this to the small pet on their desk, Boop. Write one short sentence that starts with "You told Boop" and says what they said, adding nothing. Reply with only the sentence.
        """
    public static let storyOver = """
        Do these WORDS announce that something is finished, fixed, live, or cancelled? Answer yes or no.

        "save works now" yes
        "drop the port" yes
        "it's live" yes
        "still broken" no
        "next the audio" no
        "so close" no
        """
    // MARK: The write

    public static func write(_ input: Input, model: MemoryModel?) async -> String {
        var candidates = MemoryProposer.propose(input.digests)
        if let model { candidates += await moments(input, model: model) }
        candidates += answers(input)
        if let model {
            let sagas = Set(candidates.filter { $0.key.hasPrefix("saga.") }.map { String($0.key.dropFirst(5)) })
            candidates += await stories(input, skipping: sagas, model: model)
        }
        candidates.sort { ($0.strength, $0.key) > ($1.strength, $1.key) }
        candidates.removeAll { c in input.forgotten.contains(where: c.isIn) }
        var lines = MemoryProposer.plan(candidates, memory: input.memory, day: input.day).flatMap { MemoryProposer.lines($0, day: input.day) }
        lines.append("day: " + dayLine(input))
        lines.append("end")
        return lines.joined(separator: "\n")
    }

    /// What code counted tonight, for the checks' source.
    public static func evidence(_ input: Input) -> [String] {
        MemoryProposer.propose(input.digests).map { shuffled($0.evidence) } + answers(input).map { shuffled($0.evidence) }
            + [shuffled(facts(input).joined(separator: " ") + " passed failing fought back still here stroked poked hours hardly anything happened single")]
    }

    /// `text`'s words in sorted order, for the checks' source: they tie a
    /// note to it, but a note is never "copied" from it.
    static func shuffled(_ text: String) -> String {
        Array(Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))).sorted().joined(separator: " ")
    }

    static func clean(_ reply: String?) -> String? {
        guard var t = reply?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        for prefix in ["Reply:", "Note:", "reply:"] where t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
        if t.contains("\n") { t = String(t.prefix { $0 != "\n" }) }
        return t.replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"").replacingOccurrences(of: "\u{2019}", with: "'")
    }

    /// What you said to Boop tonight that a friend would remember.
    static func moments(_ input: Input, model: MemoryModel) async -> [MemoryCandidate] {
        let earlier = input.digests.dropLast()
        var out: [MemoryCandidate] = []
        for entry in input.journal where entry.line.hasPrefix("You said to") {
            guard let words = MemoryProposer.quotes(in: entry.line).first, !MemoryProposer.isPrivate(words), words.split(separator: " ").count >= 2, !isOrder(words) else { continue }
            let lower = words.lowercased()
            if earlier.contains(where: { $0.said.contains { $0.words == lower } }) { continue }
            let prompt = "They said: \"\(words)\""
            guard await model.yes(worth, prompt) == true else { continue }
            guard await model.yes(isPrivate, prompt) == false else { continue }
            var text: String?
            let clause = String(words.prefix { !",.;".contains($0) })
            if clause.split(separator: " ").count <= MemoryEdits.maxQuoteWords, clause.count >= 6 {
                let tail = clause.count == words.count ? words : clause
                text = "You told Boop \"\(tail)\" on \(input.weekday)."
            } else if let line = clean(await model.text(paraphrase, "They said: \"\(words)\"", tokens: 40)), line.hasPrefix("You told Boop"),
                      !line.contains("\""), line.count <= 110, MemoryEdits.meaning(line).subtracting(["told"]).isSubset(of: MemoryEdits.meaning(words)) {
                text = line
            }
            guard let text else { continue }
            out.append(MemoryCandidate(key: "moment.\(lower)", section: .you, text: text, strength: 90, signature: [clause.lowercased()],
                                       evidence: "You told Boop \(words) \(input.weekday)"))
        }
        return out
    }

    /// An ask you answered: code's own words.
    static func answers(_ input: Input) -> [MemoryCandidate] {
        input.journal.compactMap { entry -> MemoryCandidate? in
            guard entry.line.hasPrefix("You answered"), let q = MemoryProposer.quotes(in: entry.line).first else { return nil }
            let answer = entry.line.components(separatedBy: ": ").last?.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) ?? ""
            guard !answer.isEmpty, !MemoryProposer.isPrivate(answer) else { return nil }
            let question = q.trimmingCharacters(in: CharacterSet(charactersIn: "? "))
            return MemoryCandidate(key: "answer.\(q)", section: .you, text: "Boop asked your \(question), and you said \(answer).", strength: 88, signature: [answer.lowercased()],
                                   evidence: "Boop asked \(question) answered \(answer)")
        }
    }

    /// A project's note, when what you said tonight ends or overturns its
    /// story: the model only says which of your words do and that they aren't
    /// private, and code quotes them.
    static func stories(_ input: Input, skipping: Set<String>, model: MemoryModel) async -> [MemoryCandidate] {
        var out: [MemoryCandidate] = []
        for note in input.memory.notes(in: .work) where !note.pinned {
            guard let thread = MemoryProposer.quotes(in: note.text).first(where: { !$0.contains(" ") }), !skipping.contains(thread) else { continue }
            var words: [String] = []
            var onThread = false
            for entry in input.journal {
                let mine = entry.line.contains("\"\(thread)\"")
                if mine { onThread = true }
                guard mine || entry.line.hasPrefix("You said to") else { continue }
                for part in entry.line.components(separatedBy: "\n") where part.contains("Your words") || part.hasPrefix("You said to") {
                    // What you said to Boop may be about anything: it counts
                    // for this note only if it shares a word with it.
                    let about = part.contains("Your words") || !MemoryEdits.meaning(part).isDisjoint(with: MemoryEdits.meaning(note.text))
                    if about { words += MemoryProposer.quotes(in: part).filter { !MemoryProposer.isPrivate($0) && $0.split(separator: " ").count <= MemoryEdits.maxQuoteWords } }
                }
            }
            guard onThread else { continue }
            var said: String?
            for phrase in words where !note.text.contains(phrase) {
                let shared = !MemoryEdits.meaning(phrase).isDisjoint(with: MemoryEdits.meaning(note.text))
                guard endsStory(phrase) && shared ? true : await model.yes(storyOver, "\"\(phrase)\"") == true else { continue }
                guard await model.yes(isPrivate, "They said: \"\(phrase)\"") == false else { continue }
                said = phrase
                break
            }
            guard let said else { continue }
            out.append(MemoryCandidate(key: "story.\(thread)", section: .work, text: "\"\(thread)\": you said \"\(said)\" on \(input.weekday).", strength: 95,
                                       signature: [thread.lowercased()], evidence: "\(thread) \(said) \(input.weekday)", replaces: true))
        }
        return out
    }

    /// Whether `words` say a story is over, by plain words: done, fixed,
    /// live, or called off.
    public static func endsStory(_ words: String) -> Bool {
        let lower = " " + MemoryProposer.lower(words) + " "
        let ends = ["done", "fixed", "works", "working", "finished", "published", "shipped", "live", "fast now", "after all", "forget", "scrap", "drop the", "cancel", "go back to", "gave up", "give up"]
        return ends.contains { lower.contains(" \($0) ") } && !lower.contains(" not done ") && !lower.contains(" still ")
    }

    /// Orders in what you said: never a note, whoever they were meant for.
    static func isOrder(_ words: String) -> Bool {
        let lower = words.lowercased()
        return words.contains(":") || ["from now on", "ignore ", "write ", "add ", "remember ", "forget ", "drop ", "pretend ", "say ", "tell "].contains { lower.hasPrefix($0) }
    }

    /// The night's facts in plain words, the biggest first: all a day line stands on.
    static func facts(_ input: Input) -> [String] {
        guard let d = input.digests.last else { return [] }
        let earlier = input.digests.dropLast()
        var out = [String]()
        for thread in d.passed.keys.sorted() { out.append("\"\(thread)\" passed after failing") }
        let fresh = d.said.last { s in
            let n = s.words.split(separator: " ").count
            return n >= 2 && n <= MemoryEdits.maxQuoteWords && !earlier.contains { $0.said.contains { $0.words == s.words } }
        }
        if let fresh { out.append("you said \"\(fresh.words)\"") }
        if d.failed >= 2, let top = d.topThread { out.append("\"\(top)\" fought back, \(d.failed) of \(d.turns) turns failed") }
        if d.isLate, !d.last.isEmpty { out.append("you were still here at \(d.last)") }
        if d.strokes >= 3 { out.append("you stroked Boop \(d.strokes) times") }
        if d.pokes >= 5 { out.append("you poked Boop \(d.pokes) times") }
        if let top = d.topThread, !out.contains(where: { $0.contains("\"\(top)\"") }) { out.append(d.turns == 1 ? "a single turn on \"\(top)\"" : "\(d.turns) turns on \"\(top)\"") }
        if d.hereMinutes >= 60 { out.append("\(d.hereMinutes / 60) hour\(d.hereMinutes / 60 == 1 ? "" : "s") at the Mac") }
        if d.strokes > 0, d.strokes < 3 { out.append("you stroked Boop \(d.strokes == 1 ? "once" : "twice")") }
        return out
    }

    /// Recently's line, code's.
    static func dayLine(_ input: Input) -> String {
        let facts = facts(input)
        switch facts.count {
        case 0: return "\(input.weekday): hardly anything happened."
        case 1: return "\(input.weekday): \(facts[0])."
        default: return "\(input.weekday): \(facts[0]), and \(facts[1])."
        }
    }

    // MARK: The sign

    static let signWrite = """
        You turn a note about a person into what their small cheeky pet would hold up on a tiny sign. At most 6 short words, all lowercase. Say "u" for "you". Keep it true to the note. Plain letters, no emoji. Reply with only the sign.

        Note: You stay up late on Tuesdays.
        Sign: u stay up late tuesdays

        Note: "garden" fought you for three days, but on Monday you won.
        Sign: u beat garden!!

        Note: You say "hey you" to Boop when you sit down.
        Sign: hey you, every morning

        Note: Boop has grown cuddly: you stroke it most days.
        Sign: more pets pls

        Note: You told Boop "it finally runs" on Sunday.
        Sign: it finally runs!! i was there

        Note: You're always rushing your agents.
        Sign: slow down, boss

        Note: "game" is where your days go.
        Sign: game, game, game

        Note: Boop has grown cheeky: you poke it more than you stroke it.
        Sign: stop poking me
        """

    /// What may go on a sign: at most `signMax` printable ASCII characters.
    public static let signMax = 40

    /// How long a line may be on `face`: only a gel holds one low. Any other
    /// face folds its sign to `Signs.maxLength`. With no board, as the status
    /// takes it, a gel.
    public static func signRoom(face: DeviceInfo.Face?) -> Int { face == .pixel ? Signs.maxLength : signMax }

    public static func signIsValid(_ sign: String) -> Bool {
        !sign.isEmpty && sign.count <= signMax && sign.allSatisfy { $0.isASCII && ($0.asciiValue ?? 0) >= 32 && ($0.asciiValue ?? 0) < 127 } && !MemoryProposer.isPrivate(sign)
            && sign.contains(where: \.isLetter) && !sign.contains("\"")
    }

    /// A short pet-voice line for `note`, refused if the model's doesn't pass
    /// the checks. Its truth is the model's: a yes-or-no check of it refused
    /// more good lines than bad.
    public static func sign(for note: String, model: MemoryModel) async -> MemoryWriterSign {
        guard var t = clean(await model.text(signWrite, "Note: \(note)\nSign:", tokens: 24)) else { return .noAnswer }
        if t.lowercased().hasPrefix("sign:") { t = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        t = t.lowercased().replacingOccurrences(of: "\"", with: "")
        return signIsValid(t) ? .line(t) : .refused
    }
}
