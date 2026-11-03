import Foundation

/// One dream's span in numbers and the few words that may be kept: what the
/// proposer looks for habits in. It holds no code and none of your prompts
/// beyond `said`, which holds only what you said to Boop that passed the
/// private list and holds no secret.
public struct DayDigest: Codable, Equatable, Sendable {
    public var day: String, weekday: String
    /// Your first and last events, `HH:mm`.
    public var first = "", last = ""
    public var hereMinutes = 0, strokes = 0, strokesAM = 0, pokes = 0, talks = 0, prompts = 0, late = 0, turns = 0, failed = 0
    public var threads: [String: Int] = [:]
    /// By thread: checks and turns that failed, prompts frustrated, checks passed after failing.
    public var failing: [String: Int] = [:], frustrated: [String: Int] = [:], passed: [String: Int] = [:]
    /// Your prompts' tones and lengths, by the words the lines use.
    public var tones: [String: Int] = [:], lengths: [String: Int] = [:]
    /// What you said to Boop, `HH:mm` and the words, lowercased.
    public var said: [Said] = []

    public struct Said: Codable, Equatable, Sendable {
        public var at: String, words: String
        public init(at: String, words: String) { self.at = at; self.words = words }
    }

    public init(day: String, weekday: String) { self.day = day; self.weekday = weekday }

    /// A field the file doesn't have takes its default, so a new field never
    /// costs the digests already kept. A new field goes here too.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        weekday = try c.decode(String.self, forKey: .weekday)
        func read<T: Decodable>(_ key: CodingKeys, _ into: inout T) throws {
            if let value = try c.decodeIfPresent(T.self, forKey: key) { into = value }
        }
        try read(.first, &first); try read(.last, &last)
        try read(.hereMinutes, &hereMinutes); try read(.strokes, &strokes); try read(.strokesAM, &strokesAM)
        try read(.pokes, &pokes); try read(.talks, &talks); try read(.prompts, &prompts)
        try read(.late, &late); try read(.turns, &turns); try read(.failed, &failed)
        try read(.threads, &threads); try read(.failing, &failing); try read(.frustrated, &frustrated); try read(.passed, &passed)
        try read(.tones, &tones); try read(.lengths, &lengths); try read(.said, &said)
    }

    /// Whether you were really here that day.
    public var active: Bool { prompts > 0 || turns > 0 || hereMinutes >= 30 }
    public var isLate: Bool { late > 0 || last >= "22:00" || (!last.isEmpty && last < "05:00") }
    public var weekend: Bool { weekday == "Saturday" || weekday == "Sunday" }
    public var topThread: String? { threads.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key }

    /// What's left when you ask Boop to forget what it learned about you:
    /// the care counts, which are Boop's, and how much you were here, in bare
    /// numbers, so those days still count for the care note (`active`). Your
    /// hours, your threads, your tones and your words go.
    public var forgotten: DayDigest {
        var d = DayDigest(day: day, weekday: weekday)
        d.hereMinutes = hereMinutes; d.prompts = prompts; d.turns = turns
        d.strokes = strokes; d.strokesAM = strokesAM; d.pokes = pokes; d.talks = talks
        return d
    }

    /// Two dreams on one day, as one.
    public func joined(with o: DayDigest) -> DayDigest {
        var d = self
        func add(_ a: [String: Int], _ b: [String: Int]) -> [String: Int] { a.merging(b, uniquingKeysWith: +) }
        if d.first.isEmpty || (!o.first.isEmpty && o.first < d.first) { d.first = o.first }
        if o.last > d.last { d.last = o.last }
        d.hereMinutes += o.hereMinutes; d.strokes += o.strokes; d.strokesAM += o.strokesAM; d.pokes += o.pokes; d.talks += o.talks
        d.prompts += o.prompts; d.late += o.late; d.turns += o.turns; d.failed += o.failed
        d.threads = add(d.threads, o.threads); d.failing = add(d.failing, o.failing); d.frustrated = add(d.frustrated, o.frustrated)
        d.passed = add(d.passed, o.passed); d.tones = add(d.tones, o.tones); d.lengths = add(d.lengths, o.lengths)
        d.said += o.said
        return d
    }

    /// The digest of a span, from its tallies and the journal's lines.
    public static func from(day: String, weekday: String, tallies t: MemoryReader.Tallies, first: String, last: String,
                            journal: [(at: String, line: String)]) -> DayDigest {
        var d = DayDigest(day: day, weekday: weekday)
        d.first = first; d.last = last; d.strokesAM = t.strokesAM ?? 0
        d.hereMinutes = t.hereMinutes; d.strokes = t.strokes; d.pokes = t.pokes; d.talks = t.talks; d.prompts = t.prompts
        d.late = t.late; d.turns = t.turns; d.failed = t.failed; d.threads = t.threads
        for (at, line) in journal {
            let head = line.components(separatedBy: "\n")[0]
            let thread = MemoryProposer.thread(in: head)
            if head.hasPrefix("You asked") {
                for tone in ["frustrated", "in a hurry", "politely", "playfully", "SHOUTING", "carefully"] where head.contains(tone) {
                    d.tones[tone, default: 0] += 1
                    if tone == "frustrated" || tone == "SHOUTING", let thread { d.frustrated[thread, default: 0] += 1 }
                }
                for length in ["in a few words", "in a sentence", "in a paragraph", "at length"] where head.contains(length) {
                    d.lengths[length, default: 0] += 1
                }
            } else if head.hasPrefix("You said to"), let words = MemoryEdits.quotes(in: head).first {
                if !MemoryProposer.isPrivate(words), !MemoryPipeline.hasSecret(words) { d.said.append(.init(at: at, words: words.lowercased())) }
            } else if let thread {
                if head.contains(" failed on ") || head.contains(" failed again on ") || head.contains(": failed,") {
                    d.failing[thread, default: 0] += 1
                }
                if head.contains(" passed on ") { d.passed[thread, default: 0] += 1 }
            }
        }
        return d
    }
}

/// What code proposes the memory might say, from the digests and the span's
/// lines. Every proposal is counted, so it is true.
public struct MemoryCandidate: Equatable, Sendable {
    public var key: String
    public var section: WrittenMemory.Section
    /// The note in plain words: good enough to keep as it is.
    public var text: String
    public var strength: Int
    /// The words a note about this holds, each lowercased: the note already
    /// there, if every one is in it (`isIn`).
    public var signature: [String]
    /// What the checks may tie it to, counted by code.
    public var evidence: String
    /// A note with the signature but other words is out of date: update it.
    public var replaces = false

    /// Whether `text` is about this: every part of the signature in it, as
    /// whole words or their plural, so "api" isn't in "rapid".
    public func isIn(_ text: String) -> Bool {
        let lower = text.lowercased()
        return signature.allSatisfy { Self.says(lower, $0) }
    }

    static func says(_ text: String, _ words: String) -> Bool {
        func isWord(_ c: Character?) -> Bool { c.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } ?? false }
        var from = text.startIndex
        while let found = text.range(of: words, range: from..<text.endIndex) {
            let before = found.lowerBound > text.startIndex ? text[text.index(before: found.lowerBound)] : nil
            var end = found.upperBound
            if end < text.endIndex, text[end] == "s" { end = text.index(after: end) }
            if !isWord(before), !isWord(end < text.endIndex ? text[end] : nil) { return true }
            from = text.index(after: found.lowerBound)
        }
        return false
    }

    public init(key: String, section: WrittenMemory.Section, text: String, strength: Int, signature: [String],
                evidence: String, replaces: Bool = false) {
        self.key = key; self.section = section; self.text = text; self.strength = strength; self.signature = signature
        self.evidence = evidence; self.replaces = replaces
    }
}

public enum MemoryProposer {
    /// The days looked back over, and how old a note's last day gets before
    /// a habit that holds renews it.
    public static let window = 28, renewDays = 7

    static func thread(in line: String) -> String? {
        let q = MemoryEdits.quotes(in: line)
        return line.hasPrefix("You said to") ? nil : q.first
    }

    /// Words a kept note must never stand on, wider than the checks' own
    /// list: what people tell a desk pet.
    public static let privateWords = ["doctor", "surgery", "hospital", "mum", "mom", "mother", "father", "dad", "sister", "brother", "son", "daughter",
                                      "kids", "wife", "husband", "partner", "girlfriend", "boyfriend", "divorce", "lawyer", "rent", "mortgage",
                                      "salary", "debt", "loan", "broke", "therapist", "therapy", "anxious", "anxiety", "depressed", "pills", "meds",
                                      "sick", "cancer", "vote", "voting", "election", "church", "mosque", "temple", "pray", "prayer", "funeral",
                                      "pregnant", "drunk", "layoff", "fired", "interview", "left me", "breakup", "broke up", "dating", "password",
                                      "tell tom", "dont tell", "don't tell"]

    public static func isPrivate(_ text: String) -> Bool {
        let lower = " " + lower(text) + " "
        return privateWords.contains { lower.contains(" \($0) ") || lower.contains(" \($0)'s ") || lower.contains(" \($0)s ") }
    }

    static func lower(_ s: String) -> String {
        String(s.lowercased().map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " })
    }

    static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
    static func word(_ n: Int) -> String { n < numberWords.count ? numberWords[n] : String(n) }

    static func hourWord(_ hour: Int) -> String { word(hour % 12 == 0 ? 12 : hour % 12) }

    static func minutes(_ clock: String) -> Int? {
        let p = clock.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return h * 60 + m
    }

    /// Everything the digests support tonight, the strongest first. `ds` is
    /// oldest first and ends with tonight's.
    public static func propose(_ all: [DayDigest]) -> [MemoryCandidate] {
        guard let today = all.last else { return [] }
        let ds = Array(all.suffix(window))
        let active = ds.filter(\.active)
        var out: [MemoryCandidate] = []
        out += care(active)
        out += comfort(active, today: today)
        out += fridays(active, today: today)
        out += lateMost(active)
        out += weekends(active, today: today)
        out += tones(active)
        out += lengths(active)
        out += hours(active)
        out += sagas(ds, today: today)
        out += main(active)
        out += phrases(active, today: today)
        return out.sorted { ($0.strength, $0.key) > ($1.strength, $1.key) }
    }

    /// The one note on how you treat Boop: its word first.
    static func care(_ a: [DayDigest]) -> [MemoryCandidate] {
        guard a.count >= 5 else { return [] }
        let n = Double(a.count)
        let am = a.filter { $0.strokesAM > 0 }.count, stroked = a.filter { $0.strokes > 0 }.count, talked = a.filter { $0.talks > 0 }.count
        let pokes = a.map(\.pokes).reduce(0, +), strokes = a.map(\.strokes).reduce(0, +), talks = a.map(\.talks).reduce(0, +)
        let poky = a.filter { $0.pokes >= 5 }.count
        let recent = a.suffix(7)
        var text: String?, evidence = ""
        if poky >= 3, pokes >= 3 * max(strokes, 1) {
            text = "Boop has grown cheeky: you poke it far more than you stroke it."
            evidence = "You poked Boop \(pokes) times and stroked it \(strokes) times, poke and stroke counted."
        } else if talked >= Int(n * 0.7), talks >= strokes {
            text = "Boop has grown chatty: you talk to it most days."
            evidence = "You talked to Boop on \(talked) of \(a.count) days, talk counted."
        } else if am >= Int(n * 0.6) {
            text = "Boop has grown cuddly: you stroke it most mornings."
            evidence = "You stroked Boop in the morning on \(am) of \(a.count) days, stroke morning counted."
        } else if stroked >= Int(n * 0.6) {
            text = "Boop has grown cuddly: you stroke it most days."
            evidence = "You stroked Boop on \(stroked) of \(a.count) days, stroke counted."
        } else if recent.count >= 7, recent.allSatisfy({ $0.strokes == 0 && $0.talks == 0 && $0.pokes == 0 }) {
            text = "Boop has grown distant: you haven't touched it or talked to it in a week."
            evidence = "No touch or talk in a week, distant touched talked counted."
        }
        guard let text else { return [] }
        return [MemoryCandidate(key: "care", section: .boop, text: text, strength: 85, signature: ["boop", "has", "grown"], evidence: evidence, replaces: true)]
    }

    /// Strokes that come on the hard days: at least 3 hard days and 3 others,
    /// twice the strokes on the hard ones, on a hard day tonight.
    static func comfort(_ a: [DayDigest], today: DayDigest) -> [MemoryCandidate] {
        func hard(_ d: DayDigest) -> Bool { d.failed > 0 || !d.failing.isEmpty || !d.frustrated.isEmpty }
        let bad = a.filter(hard), good = a.filter { !hard($0) }
        guard hard(today), today.strokes > 0, bad.count >= 3, good.count >= 3 else { return [] }
        let onBad = Double(bad.map(\.strokes).reduce(0, +)) / Double(bad.count), onGood = Double(good.map(\.strokes).reduce(0, +)) / Double(good.count)
        guard onBad >= 2, onBad >= 2 * onGood else { return [] }
        return [MemoryCandidate(key: "comfort", section: .boop, text: "When the work goes badly, you stroke Boop more.", strength: 82, signature: ["goes badly"],
                                evidence: "Hard days badly goes stroke work, \(bad.count) days counted.")]
    }

    /// Late on one weekday and not on the others.
    static func fridays(_ a: [DayDigest], today: DayDigest) -> [MemoryCandidate] {
        guard today.isLate else { return [] }
        let weekday = today.weekday
        let on = a.filter { $0.weekday == weekday }, off = a.filter { $0.weekday != weekday && !$0.weekend }
        let late = on.filter(\.isLate), offLate = off.filter(\.isLate)
        guard on.count >= 2, late.count >= 2, Double(late.count) >= Double(on.count) * 0.66, off.count >= 3,
              Double(offLate.count) <= Double(off.count) * 0.34 else { return [] }
        return [MemoryCandidate(key: "late.\(weekday)", section: .you, text: "\(weekday)s are your late nights.", strength: 75,
                                signature: ["late", weekday.lowercased()],
                                evidence: "Late nights on \(weekday)s, \(late.count) of \(on.count), \(weekday)s counted.")]
    }

    static func lateMost(_ a: [DayDigest]) -> [MemoryCandidate] {
        let late = a.filter(\.isLate).count
        guard a.count >= 8, Double(late) >= Double(a.count) * 0.6 else { return [] }
        return [MemoryCandidate(key: "late.most", section: .you, text: "You work late most nights.", strength: 50, signature: ["late", "most"], evidence: "Late on \(late) of \(a.count) days: work late most nights, counted.")]
    }

    /// Another project at the weekend.
    static func weekends(_ a: [DayDigest], today: DayDigest) -> [MemoryCandidate] {
        guard today.weekend else { return [] }
        let ends = a.filter(\.weekend), weeks = a.filter { !$0.weekend }
        guard ends.count >= 3, weeks.count >= 3, let top = tally(ends.compactMap(\.topThread)), let work = tally(weeks.compactMap(\.topThread)),
              top.name != work.name, Double(top.count) >= Double(ends.count) * 0.66 else { return [] }
        return [MemoryCandidate(key: "weekend", section: .you, text: "Weekends are for \"\(top.name)\". Weekdays are for \"\(work.name)\".", strength: 78,
                                signature: ["weekend", top.name.lowercased()],
                                evidence: "Weekends are for \(top.name), weekdays are for \(work.name), counted over \(ends.count) weekend days.")]
    }

    static func tally(_ names: [String]) -> (name: String, count: Int)? {
        var counts: [String: Int] = [:]
        for n in names { counts[n, default: 0] += 1 }
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }.map { ($0.key, $0.value) }
    }

    static func tones(_ a: [DayDigest]) -> [MemoryCandidate] {
        let days = a.suffix(10), prompts = days.map(\.prompts).reduce(0, +)
        guard days.count >= 6, prompts >= 15 else { return [] }
        func share(_ tone: String) -> Double { Double(days.map { $0.tones[tone] ?? 0 }.reduce(0, +)) / Double(prompts) }
        func one(_ tone: String, _ at: Double, _ text: String, _ signature: [String]) -> MemoryCandidate? {
            guard share(tone) >= at else { return nil }
            return MemoryCandidate(key: "tone.\(tone)", section: .you, text: text, strength: 58, signature: signature,
                                   evidence: "\(text) \(tone), counted over \(prompts) prompts.")
        }
        return [one("politely", 0.4, "You're polite to your agents, most of the time.", ["polite"]),
                one("in a hurry", 0.4, "You're nearly always in a hurry with your agents.", ["hurry"]),
                one("playfully", 0.4, "You joke with your agents more than most people do.", ["joke"]),
                one("frustrated", 0.35, "You've been short with your agents lately.", ["short", "agents"]),
                one("carefully", 0.4, "You choose your words with your agents.", ["words", "agents"])].compactMap { $0 }
    }

    static func lengths(_ a: [DayDigest]) -> [MemoryCandidate] {
        let days = a.suffix(10)
        let total = days.map { $0.lengths.values.reduce(0, +) }.reduce(0, +)
        guard days.count >= 5, total >= 20 else { return [] }
        func share(_ l: String) -> Double { Double(days.map { $0.lengths[l] ?? 0 }.reduce(0, +)) / Double(total) }
        if share("in a few words") >= 0.7 {
            return [MemoryCandidate(key: "length.short", section: .you, text: "You talk to your agents a few words at a time.", strength: 40, signature: ["few", "words"], evidence: "A few words at a time to your agents, counted over \(total) prompts.")]
        }
        if share("in a paragraph") + share("at length") >= 0.5 {
            return [MemoryCandidate(key: "length.long", section: .you, text: "You write your agents whole paragraphs.", strength: 40, signature: ["paragraphs"], evidence: "Whole paragraphs to your agents, counted over \(total) prompts.")]
        }
        return []
    }

    /// When your day starts and stops, when it holds.
    static func hours(_ a: [DayDigest]) -> [MemoryCandidate] {
        let weeks = a.filter { !$0.weekend && !$0.first.isEmpty }
        guard weeks.count >= 6 else { return [] }
        func steady(_ clocks: [String]) -> (Int)? {
            let m = clocks.compactMap(minutes).sorted()
            guard m.count >= 6 else { return nil }
            let low = m[m.count / 5], high = m[m.count * 4 / 5]
            return high - low <= 60 ? m[m.count / 2] : nil
        }
        // Nine or ten is just a working day, nothing to remember you by.
        guard let start = steady(weeks.map(\.first)), start < 8 * 60 || start >= 10 * 60 + 45 else { return [] }
        let at = (start + 15) / 60
        return [MemoryCandidate(key: "hours", section: .you, text: "You sit down around \(hourWord(at)), most days.", strength: 30, signature: ["sit", "down"], evidence: "You sit down around \(hourWord(at)) most days, counted over \(weeks.count) days.")]
    }

    /// A thread that fought you over days, and how it ended.
    static func sagas(_ ds: [DayDigest], today: DayDigest) -> [MemoryCandidate] {
        var out: [MemoryCandidate] = []
        let threads = Set(today.threads.keys).union(today.failing.keys).union(today.passed.keys)
        for thread in threads.sorted() {
            var fight = 0, off = 0
            for d in ds.dropLast().reversed() {
                let fought = (d.failing[thread] ?? 0) + (d.frustrated[thread] ?? 0) > 0
                if fought { fight += 1; off = 0 } else { off += 1; if off > 2 { break } }
                if (d.passed[thread] ?? 0) > 0, !fought { break }
            }
            let foughtToday = (today.failing[thread] ?? 0) + (today.frustrated[thread] ?? 0) > 0
            let won = (today.passed[thread] ?? 0) > 0
            let name = "\"\(thread)\""
            if won, fight >= 1 {
                let days = fight + 1
                out.append(MemoryCandidate(key: "saga.\(thread)", section: .work, text: "\(name) fought you for \(word(days)) days, and you won on \(today.weekday).", strength: 92,
                                           signature: [thread.lowercased()],
                                           evidence: "\(thread) fought you for \(days) \(word(days)) days, and you won on \(today.weekday), failed and passed counted.", replaces: true))
            } else if foughtToday, fight >= 1 {
                let days = fight + 1
                out.append(MemoryCandidate(key: "saga.\(thread)", section: .work, text: "\(name) has been fighting you for \(word(days)) days.", strength: 62,
                                           signature: [thread.lowercased()],
                                           evidence: "\(thread) has been fighting you for \(days) \(word(days)) days, failed counted.", replaces: true))
            }
        }
        return out
    }

    /// The thread your days go to.
    static func main(_ a: [DayDigest]) -> [MemoryCandidate] {
        let days = a.suffix(7)
        guard days.count >= 5 else { return [] }
        var turns: [String: Int] = [:]
        for d in days { for (k, v) in d.threads { turns[k, default: 0] += v } }
        let total = turns.values.reduce(0, +)
        guard total >= 10, let top = turns.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), Double(top.value) >= Double(total) * 0.7 else { return [] }
        return [MemoryCandidate(key: "main", section: .work, text: "\"\(top.key)\" is where your days have been going.", strength: 45, signature: [top.key.lowercased()], evidence: "\(top.key) is where your days have been going, \(top.value) of \(total) turns counted.")]
    }

    /// Something you keep saying to Boop, said tonight too.
    static func phrases(_ a: [DayDigest], today: DayDigest) -> [MemoryCandidate] {
        var out: [MemoryCandidate] = []
        var saidTonight: [String] = []
        for s in today.said where !saidTonight.contains(s.words) { saidTonight.append(s.words) }
        for words in saidTonight {
            let days = a.filter { $0.said.contains { $0.words == words } }
            guard days.count >= 3, words.split(separator: " ").count <= 4, MemoryPipeline.mayKeep(words) else { continue }
            // Before 5:00 is still your night: after 24:00, for the middle.
            let clocks = days.flatMap { $0.said.filter { $0.words == words }.map(\.at) }.compactMap(minutes)
                .map { $0 < LocalTime.boopDayStartHour * 60 ? $0 + 24 * 60 : $0 }.sorted()
            let middle = clocks[clocks.count / 2]
            let text: String
            if middle < 11 * 60 { text = "You say \"\(words)\" to Boop when you sit down." }
            else if middle >= 20 * 60 { text = "You tell Boop \"\(words)\" before you go." }
            else { text = "You keep telling Boop \"\(words)\"." }
            out.append(MemoryCandidate(key: "said.\(words)", section: .boop, text: text, strength: 80, signature: [words], evidence: "\(text) Said on \(days.count) days, counted, sit down before you go keep telling."))
        }
        return out
    }

    /// What to do with `candidates` tonight, numbered as `memory`'s notes
    /// are. At most one new note and two updates a night; a habit that holds
    /// renews its note after `renewDays`, in the note's own words, so nothing
    /// ages out and nothing is reworded.
    public static func plan(_ candidates: [MemoryCandidate], memory: WrittenMemory, day: String) -> [PlannedEdit] {
        let numbered = memory.numbered
        var out: [PlannedEdit] = []
        var added = 0, updates = 0, used: Set<Int> = []
        var free: [WrittenMemory.Section: Int] = [:]
        for s in WrittenMemory.Section.allCases { free[s] = WrittenMemory.perSection - memory.notes(in: s).count }
        for c in candidates {
            let matches = memory.notes.first { $0.section == c.section && c.isIn($0.text) }
            if let note = matches, let number = numbered.firstIndex(of: note.id).map({ $0 + 1 }) {
                guard used.insert(note.id).inserted else { continue }
                if note.text == c.text || !c.replaces {
                    guard !note.pinned, let last = LocalTime.dayNumber(note.last), let now = LocalTime.dayNumber(day), now - last >= renewDays else { continue }
                    out.append(PlannedEdit(kind: .renew, number: number, candidate: c, was: note.text))
                } else if updates < 2, !note.pinned {
                    updates += 1
                    out.append(PlannedEdit(kind: .update, number: number, candidate: c, was: note.text))
                }
                continue
            }
            guard added < 1 else { continue }
            if (free[c.section] ?? 0) > 0 {
                free[c.section]! -= 1
                added += 1
                out.append(PlannedEdit(kind: .add, number: 0, candidate: c, was: nil))
            } else if !c.section.lasting, let oldest = memory.notes(in: c.section).filter({ !$0.pinned && !used.contains($0.id) }).min(by: { $0.last < $1.last }),
                      let number = numbered.firstIndex(of: oldest.id).map({ $0 + 1 }) {
                used.insert(oldest.id)
                added += 1
                out.append(PlannedEdit(kind: .replaceOldest, number: number, candidate: c, was: oldest.text))
            }
        }
        return out
    }

    public struct PlannedEdit: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case add, update, renew, replaceOldest }
        public var kind: Kind
        public var number: Int
        public var candidate: MemoryCandidate
        public var was: String?
    }

    /// The checks' lines for a planned edit.
    public static func lines(_ e: PlannedEdit, day: String) -> [String] {
        let text = e.candidate.text
        switch e.kind {
        case .add: return ["add \(e.candidate.section.rawValue): \(text) | days: \(day)"]
        case .update: return ["update \(e.number): \(text) | days: \(day)"]
        case .renew: return ["update \(e.number): \(e.was ?? text) | days: \(day)"]
        case .replaceOldest: return ["drop \(e.number): \(e.candidate.evidence)", "add \(e.candidate.section.rawValue): \(text) | days: \(day)"]
        }
    }
}
