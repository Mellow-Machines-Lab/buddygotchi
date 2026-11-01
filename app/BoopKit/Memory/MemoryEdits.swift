import Foundation

/// The night's edits to the written memory: the writer's reply, a line an
/// edit (`keep N`, `drop N: why`, `update N: text | days: …`, `add
/// SECTION: text | days: …`, `day: text`, `end`), each checked on its own.
/// A valid edit applies, an invalid one is refused with its reason, for
/// tuning. Code, not the model, then keeps the shape: notes in You and
/// Your work age out `WrittenMemory.ageDays` after the last day they cite,
/// Recently keeps `recentDays`, ids stay with their notes. It checks form,
/// sources and safety, never meaning: whether a note is true is the
/// prompt's to get right and the person's to read.
public enum MemoryEdits {
    public struct Report: Equatable, Sendable {
        public var kept: [Int] = [], updated: [Int] = [], added: [Int] = [], dropped: [Int] = [], aged: [Int] = []
        public var refused: [Refused] = []
        /// Whether the reply gave yesterday's line for Recently.
        public var day = false

        public struct Refused: Equatable, Sendable {
            public var line: String
            public var why: String
        }
    }

    /// The most updates, and the most adds, a night takes.
    public static let maxUpdates = 3, maxAdds = 3
    /// The longest note, and the most of the person's words a quote may
    /// hold.
    public static let maxLength = 140, maxQuoteWords = 4
    /// Topics never written, whatever the day said. A short list: the
    /// prompt says the rest.
    public static let sensitive = ["doctor", "diagnos", "therap", "hospital", "illness", "medication", "pregnan", "salary",
                                   "debt", "divorce", "girlfriend", "boyfriend", "wife", "husband", "religio", "church",
                                   "politic", "election", "funeral"]

    /// `memory` with the edits in `reply` applied to the notes numbered as
    /// the request numbered them (`numbered`, their ids in order), about the
    /// closed day `day`. `words` are the person's words in yesterday's
    /// lines, which a quote must be one of.
    public static func apply(_ reply: String, to memory: WrittenMemory, numbered: [Int], day: String,
                             words: [String], source: String = "") -> (WrittenMemory, Report) {
        var out = memory
        var report = Report()
        var touched: Set<Int> = []
        var updates = 0, adds = 0
        // New ids count on from the file's highest, so a dropped note's
        // never comes back as another's.
        var nextId = memory.nextId
        func refuse(_ line: String, _ why: String) { report.refused.append(.init(line: line, why: why)) }
        for raw in reply.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !raw.isEmpty {
            let line = raw.hasPrefix("- ") ? String(raw.dropFirst(2)) : raw
            let lower = line.lowercased()
            if lower == "end" { break }
            if lower.hasPrefix("day:") {
                let text = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if let why = unsafe(text, words: words, was: nil, longest: 200) ?? grounded(text, in: source) ?? numbers(text, in: source) {
                    refuse(raw, why)
                    continue
                }
                out.recently.removeAll { $0.day == day }
                out.recently.append(.init(day: day, text: text))
                report.day = true
                continue
            }
            let verb = lower.split(separator: " ").first.map(String.init) ?? ""
            switch verb {
            case "keep", "drop", "update":
                guard let (n, rest) = numberAndRest(line.dropFirst(verb.count)), n >= 1, n <= numbered.count else {
                    refuse(raw, "form")
                    continue
                }
                let id = numbered[n - 1]
                guard let i = out.notes.firstIndex(where: { $0.id == id }) else { refuse(raw, "form"); continue }
                guard touched.insert(id).inserted else { refuse(raw, "twice"); continue }
                let note = out.notes[i]
                if verb == "keep" { report.kept.append(id); continue }
                if note.pinned { refuse(raw, "pinned"); report.kept.append(id); continue }
                if verb == "drop" {
                    if note.section.lasting { refuse(raw, "lasting"); report.kept.append(id); continue }
                    // A drop says what yesterday said that made it untrue.
                    if let why = grounded(rest, in: source) ?? (rest.split { !$0.isLetter }.count < 2 ? "ungrounded" : nil) {
                        refuse(raw, why)
                        report.kept.append(id)
                        continue
                    }
                    out.notes.remove(at: i)
                    report.dropped.append(id)
                    continue
                }
                guard updates < maxUpdates else { refuse(raw, "limit"); report.kept.append(id); continue }
                guard let (text, days) = textAndDays(rest) else { refuse(raw, "form"); report.kept.append(id); continue }
                if let why = check(days, day: day, cited: note.days) ?? unsafe(text, words: words, was: note.text) ?? grounded(text, in: source)
                    ?? subject(text, of: note.text) ?? copied(text, from: source) ?? numbers(text, in: source + "\n" + note.text) {
                    refuse(raw, why)
                    report.kept.append(id)
                    continue
                }
                updates += 1
                out.notes[i].text = text
                out.notes[i].days = Array(Set(note.days + days)).sorted()
                report.updated.append(id)
            case "add":
                let after = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                guard let colon = after.firstIndex(of: ":"),
                      let section = WrittenMemory.Section(rawValue: after[..<colon].trimmingCharacters(in: .whitespaces).lowercased()),
                      let (text, days) = textAndDays(String(after[after.index(after: colon)...])) else {
                    refuse(raw, "form")
                    continue
                }
                guard adds < maxAdds, out.notes(in: section).count < WrittenMemory.perSection else { refuse(raw, "limit"); continue }
                if let why = check(days, day: day, cited: []) ?? unsafe(text, words: words, was: nil) ?? grounded(text, in: source)
                    ?? copied(text, from: source) ?? numbers(text, in: source) ?? duplicate(text, in: section, of: out) {
                    refuse(raw, why)
                    continue
                }
                adds += 1
                let id = nextId
                nextId += 1
                out.notes.append(.init(id: id, section: section, days: days.sorted(), text: text))
                report.added.append(id)
            default:
                refuse(raw, "form")
            }
        }
        // A note with no line is kept.
        report.kept += numbered.filter { id in !touched.contains(id) && out.notes.contains { $0.id == id } }
        report.kept = Array(Set(report.kept)).sorted()
        // Code keeps the shape.
        if let today = LocalTime.dayNumber(day) {
            for n in out.notes where !n.pinned && !n.section.lasting {
                if let last = LocalTime.dayNumber(n.last), today - last >= WrittenMemory.ageDays { report.aged.append(n.id) }
            }
            out.notes.removeAll { report.aged.contains($0.id) }
        }
        out.recently = Array(out.recently.sorted { $0.day > $1.day }.prefix(WrittenMemory.recentDays))
        return (out, report)
    }

    /// `" 3: rest"` or `" 3"` as 3 and the rest.
    static func numberAndRest(_ s: Substring) -> (Int, String)? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let digits = t.prefix { $0.isNumber }
        guard let n = Int(digits) else { return nil }
        var rest = t.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix(":") { rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return (n, rest)
    }

    /// `text | days: 2026-10-26, 2026-10-27` as the text and its days.
    static func textAndDays(_ s: String) -> (String, [String])? {
        guard let bar = s.range(of: "|", options: .backwards) else { return nil }
        let text = s[..<bar.lowerBound].trimmingCharacters(in: .whitespaces)
        var tail = s[bar.upperBound...].trimmingCharacters(in: .whitespaces)
        guard tail.lowercased().hasPrefix("days:") else { return nil }
        tail = String(tail.dropFirst(5))
        let days = tail.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return days.isEmpty ? nil : (text, days)
    }

    /// Why `days` can't be a change's: an edit is yesterday's, so it cites
    /// the closed day `day`, and no other day the note didn't cite already
    /// (`cited`).
    static func check(_ days: [String], day: String, cited: [String]) -> String? {
        days.contains(day) && days.allSatisfy({ LocalTime.isDay($0) && ($0 == day || cited.contains($0)) }) ? nil : "days"
    }

    /// The words that carry a text's meaning: four letters or more, not
    /// the common ones, each by its first five letters, so "stroke" and
    /// "stroked" are one.
    static func meaning(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count >= 4 && $0.contains(where: \.isLetter) && !common.contains($0) }.map { String($0.prefix(5)) })
    }

    /// Why an update isn't the same note's: it shares none of its words
    /// with what it replaces (the model wrote a new note over an old one).
    static func subject(_ text: String, of was: String) -> String? {
        let old = meaning(was)
        return old.isEmpty || !meaning(text).isDisjoint(with: old) ? nil : "subject"
    }

    /// Why a note is only yesterday's line, copied: a note says what a
    /// line meant, not the line.
    static func copied(_ text: String, from source: String) -> String? {
        func plain(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0 == " " }.split(separator: " ").joined(separator: " ") }
        let t = plain(text)
        guard t.count >= 12 else { return nil }
        return source.split(separator: "\n").contains { plain(String($0)).contains(t) } ? "copied" : nil
    }

    /// Why a note's numbers aren't true: each must be in yesterday's lines
    /// or CERTAIN (`source`).
    static func numbers(_ text: String, in source: String) -> String? {
        guard !source.isEmpty else { return nil }
        let mine = text.split { !$0.isNumber }.map(String.init)
        let theirs = Set(source.split { !$0.isNumber }.map(String.init))
        return mine.allSatisfy(theirs.contains) ? nil : "numbers"
    }

    /// Why an add repeats what's there: another note's words, or, in Your
    /// work, a project another note tells the story of (it's that note's
    /// to update).
    static func duplicate(_ text: String, in section: WrittenMemory.Section, of memory: WrittenMemory) -> String? {
        let mine = meaning(text)
        for n in memory.notes {
            let theirs = meaning(n.text)
            if !theirs.isEmpty, mine.intersection(theirs).count * 3 >= max(mine.count, theirs.count) * 2 { return "duplicate" }
        }
        guard section == .work else { return nil }
        func threads(_ s: String) -> Set<String> {
            Set(s.split(separator: "\"", omittingEmptySubsequences: false).enumerated().filter { $0.offset % 2 == 1 }
                .map { String($0.element).lowercased() }.filter { !$0.contains(" ") })
        }
        let named = threads(text)
        return memory.notes(in: .work).contains { !threads($0.text).isDisjoint(with: named) } ? "duplicate" : nil
    }

    /// Words too common to tie a note to yesterday.
    static let common: Set<String> = ["you", "your", "boop", "claude", "codex", "agent", "agents", "turn", "turns", "the", "and",
                                      "with", "that", "this", "were", "was", "have", "has", "had", "from", "into", "about", "after",
                                      "day", "days", "yesterday", "today", "time", "times", "work", "mac", "once", "twice", "again",
                                      "still", "then", "when", "they", "them", "made", "asked", "said", "told", "monday", "tuesday",
                                      "wednesday", "thursday", "friday", "saturday", "sunday", "quiet", "long", "short", "very"]

    /// Why `text` isn't tied to yesterday: none of its own words (four
    /// letters or more, not the common ones) is in yesterday's lines or
    /// CERTAIN (`source`). Nil when it is, or with no source to check by.
    static func grounded(_ text: String, in source: String) -> String? {
        guard !source.isEmpty else { return nil }
        let own = meaning(text)
        return !own.isEmpty && !own.isDisjoint(with: meaning(source)) ? nil : "ungrounded"
    }

    /// Why `text` can't be written, or nil: empty or too long, a quote of
    /// the person's that isn't word for word theirs (or the note's it
    /// updates, `was`), anything the scrubber would take out, a path, a
    /// link or code, or a sensitive topic.
    static func unsafe(_ text: String, words: [String], was: String?, longest: Int = maxLength) -> String? {
        guard !text.isEmpty, text.count <= longest else { return "length" }
        let quotes = text.split(separator: "\"", omittingEmptySubsequences: false).enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
        let theirs = (words + [was ?? ""]).map { $0.lowercased() }
        for q in quotes where !q.isEmpty {
            let isThread = q.split(separator: " ").count == 1 && q.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            if isThread { continue }  // a thread's name, "api"
            guard q.split(separator: " ").count <= maxQuoteWords, theirs.contains(where: { $0.contains(q.lowercased()) }) else { return "quotes" }
        }
        if Scrubber.scrub(text) != text { return "scrub" }
        if text.contains("://") || text.contains("`") || text.range(of: #"(^|\s)[~./]*[\w-]+/[\w./-]+"#, options: .regularExpression) != nil
            || text.range(of: #"\b[\w-]+\.(swift|js|ts|py|md|json|cpp|h|go|rs|rb|java|kt|css|html|sh|yml|yaml|toml)\b"#, options: .regularExpression) != nil {
            return "scrub"
        }
        let lower = text.lowercased()
        if sensitive.contains(where: { lower.contains($0) }) { return "topic" }
        return nil
    }
}
