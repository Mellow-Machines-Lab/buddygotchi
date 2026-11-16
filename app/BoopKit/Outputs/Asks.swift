import Foundation
import MellowHarness

/// What the buddy may ask you, from its pack's `asks.md`: a question
/// with two answers you tap, and what it holds up after you answer. Boop
/// can ask a thing; it never needs an answer, and the agents never wait
/// on one. A line with parts (`question | a | b`) is a question, its first
/// tag its id and the rest the moment's tags it needs and `keeps` (asked
/// once, ever: its answer becomes part of Boop); a line with none is a
/// follow-up, tagged with the question's id and the answer.
public enum Asks {
    public struct Question: Equatable, Sendable {
        public var id: String
        public var question: String
        public var a: String
        public var b: String
        /// The moment's tags it needs.
        public var tags: [String]
        public var keeps: Bool
    }

    /// How an ask ended with nobody answering.
    public static let ignored = "ignored"
    /// The longest question and answer, in characters: a sign's width, and
    /// half the lane for each answer.
    public static let maxQuestion = Signs.maxLength, maxAnswer = 7
    /// How long one answered stays off, and one ignored; a `keeps` one
    /// answered never comes back.
    public static let answeredOffDays = 30, ignoredOffDays = 1
    /// The pack's questions, in the file's order.
    public static func questions(_ lines: [TaggedLine]) -> [Question] {
        lines.compactMap { line in
            let p = line.parts
            guard p.count == 3, let id = line.tags.first else { return nil }
            let rest = Array(line.tags.dropFirst())
            return Question(id: id, question: p[0], a: p[1], b: p[2], tags: rest.filter { $0 != "keeps" },
                            keeps: rest.contains("keeps"))
        }
    }

    /// What it may hold up after `answer` to the question `id`.
    public static func followUps(_ lines: [TaggedLine], id: String, answer: String) -> [String] {
        lines.filter { $0.parts.count == 1 && $0.tags.count >= 2 && $0.tags[0] == id && $0.tags[1] == answer.lowercased() }
            .map(\.text).filter { $0.count <= Signs.maxLength }
    }

    /// A wish's words from the pack's lines: `[wish pet] pet me?`, the sign
    /// that makes it, and `[wish pet met] <3`, the sign as it's met. A
    /// kind's plain lines take turns by `day`, the Boop day's number, so a
    /// day's sign stays put and the next day's differs.
    public static func wishSign(_ lines: [TaggedLine], _ kind: Core.WishKind, day: Int = 0) -> String? {
        let plain = lines.filter { $0.tags == ["wish", kind.rawValue] }
        return plain.isEmpty ? nil : plain[((day % plain.count) + plain.count) % plain.count].text
    }
    public static func wishMetSign(_ lines: [TaggedLine], _ kind: Core.WishKind) -> String? {
        lines.first { $0.tags == ["wish", kind.rawValue, "met"] }?.text
    }

    /// What's kept of a question asked: the day, and the answer once
    /// there is one (`ask.<id>` in the key-value store).
    public struct Record: Codable, Equatable, Sendable {
        public var asked: String
        public var answer: String?
        public var keeps: Bool
        public var ignored: Bool

        public init(asked: String, answer: String? = nil, keeps: Bool, ignored: Bool = false) {
            self.asked = asked
            self.answer = answer
            self.keeps = keeps
            self.ignored = ignored
        }
    }

    /// Whether the question may be asked on `today`, by its record: one
    /// that keeps, answered, never again; another answered, after 30 days;
    /// one ignored or still unanswered, after a day.
    public static func off(_ record: Record?, today: String) -> Bool {
        guard let record, let asked = LocalTime.dayNumber(record.asked), let now = LocalTime.dayNumber(today) else { return false }
        if record.answer != nil { return record.keeps || now - asked < answeredOffDays }
        return now - asked < ignoredOffDays
    }

    /// The questions it may ask now: those whose tags the moment has
    /// (`tags`), not off by their records, the file's order kept, so the
    /// ones that shape Boop, written first, are offered first.
    public static func offered(_ questions: [Question], tags: Set<String>, record: (String) -> Record?, today: String) -> [Question] {
        questions.filter { Set($0.tags).isSubset(of: tags) && !off(record($0.id), today: today) }
    }

    /// The tag every ask's moment has: an idle check-in, where asks are
    /// dealt (`IdleBeat`).
    public static let moment = "idle"

    /// The questions it may ask at an idle check-in at `now`, of
    /// `questions`: those whose tags the moment's, the calendar's and the
    /// answers kept all cover, and that aren't off (`offered`). When, and
    /// how often, is the idle beat's (`IdleBeat`).
    public static func due(_ questions: [Question], core: Core, memory: Memory?, at now: Int64, wall: Int64) -> [Question] {
        guard let memory, !questions.isEmpty else { return [] }
        let tags = Set([moment] + core.calendar(at: now) + memory.answerTags(at: wall))
        return offered(questions, tags: tags, record: memory.askRecord, today: core.config.time.boopDay(wall))
    }

    /// The answers kept as tags on `today`: a kept answer for good,
    /// another for 30 days.
    public static func answerTags(_ records: [String: Record], today: String) -> [String] {
        guard let now = LocalTime.dayNumber(today) else { return [] }
        return records.values.compactMap { r in
            guard let answer = r.answer, let day = LocalTime.dayNumber(r.asked) else { return nil }
            return r.keeps || now - day < answeredOffDays ? answer.lowercased() : nil
        }.sorted()
    }
}
