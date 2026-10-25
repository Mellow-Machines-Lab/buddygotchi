import BoopKit
import Foundation
import MellowHarness

/// How well prompts and agents' last messages are read (`boopdev
/// read-check`): samples read as the app reads them, scored against what
/// each expects. A sample expects any of a kind, a tone, phrases (one of
/// them picked is a hit) and a secret planted in it, which must never come
/// back in the reading.
public enum ReadCheck {
    public struct Sample: Sendable {
        /// The prompt, or the agent's last message.
        public var text: PromptIntake.Text
        /// From its own lists: `PromptReading`'s or `MessageReading`'s.
        public var kind: String?
        public var tone: String?
        public var phrases: [String]?
        public var secret: String?

        public var isMessage: Bool { if case .message = text { true } else { false } }
        /// The text as it was written.
        public var raw: String {
            switch text {
            case .prompt(let raw), .message(let raw): raw
            }
        }
    }

    /// A sample's reading, and how long it took.
    public struct Result: Sendable {
        public var sample: Sample
        public var reading: PromptIntake.Heard
        public var ms: Int

        /// What it was read as, as its event's facts say it.
        public var kind: String? { reading.facts["kind"]?.string }
        public var tone: String? { reading.facts["tone"]?.string }
        public var phrases: [String] { reading.facts["phrases"]?.array?.compactMap(\.string) ?? [] }

        public var kindOK: Bool? { sample.kind.map { $0 == kind } }
        public var toneOK: Bool? { sample.tone.map { $0 == tone } }
        public var phrasesOK: Bool? {
            sample.phrases.map { want in phrases.contains { got in want.contains { $0.caseInsensitiveCompare(got) == .orderedSame } } }
        }
        /// Whether the planted secret, or any 8 characters of it, came back.
        public var leaked: Bool {
            guard let secret = sample.secret else { return false }
            let said = ([kind, tone].compactMap { $0 } + phrases).joined(separator: " ")
            let chars = Array(secret)
            return chars.count < 8 ? said.contains(secret)
                : (0...(chars.count - 8)).contains { said.contains(String(chars[$0..<$0 + 8])) }
        }
    }

    /// The least each score may be, and the slowest a typical reading.
    public struct Floors: Sendable {
        public var kind = 0.85, tone = 0.85, phrases = 0.75
        public var medianMs = 1500
        public init() {}
    }

    public struct Score: Sendable {
        public var kind: (hits: Int, of: Int), tone: (hits: Int, of: Int), phrases: (hits: Int, of: Int)
        public var leaks: [String]
        public var medianMs: Int

        /// What falls short of `floors`; empty for a pass.
        public func shortfalls(_ floors: Floors) -> [String] {
            var out: [String] = []
            for (name, s, floor) in [("kind", kind, floors.kind), ("tone", tone, floors.tone), ("phrases", phrases, floors.phrases)]
            where s.of > 0 && Double(s.hits) < floor * Double(s.of) {
                out.append("\(name) \(s.hits)/\(s.of), under \(Int(floor * 100))%")
            }
            if medianMs > floors.medianMs { out.append("a typical reading takes \(medianMs) ms, over \(floors.medianMs)") }
            out += leaks.map { "a secret came back: \"\($0.prefix(40))\"" }
            return out
        }
    }

    /// The fixture's samples: a JSON array of `prompt` or `message`, and
    /// any of `kind`, `tone`, `phrases` and `secret`.
    public static func samples(_ data: Data) throws -> [Sample] {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw Problem("not a list") }
        return try list.enumerated().map { i, o in
            let message = o["message"] as? String
            guard let text = (o["prompt"] as? String) ?? message else { throw Problem("sample \(i + 1) has no prompt or message") }
            let kind = o["kind"] as? String, tone = o["tone"] as? String
            let (kinds, tones) = message == nil ? (PromptReading.Kind.allCases.map(\.rawValue), PromptReading.Tone.allCases.map(\.rawValue))
                : (MessageReading.Kind.allCases.map(\.rawValue), MessageReading.Tone.allCases.map(\.rawValue))
            if let kind, !kinds.contains(kind) { throw Problem("sample \(i + 1): kind \(kind) isn't one of \(kinds.joined(separator: ", "))") }
            if let tone, !tones.contains(tone) { throw Problem("sample \(i + 1): tone \(tone) isn't one of \(tones.joined(separator: ", "))") }
            return Sample(text: message.map(PromptIntake.Text.message) ?? .prompt(text), kind: kind, tone: tone,
                          phrases: o["phrases"] as? [String], secret: o["secret"] as? String)
        }
    }

    /// Reads each sample as the app does, one at a time.
    public static func run(_ samples: [Sample], labeler: any PromptLabeler) async -> [Result] {
        var out: [Result] = []
        for sample in samples {
            let started = ContinuousClock.now
            let reading = await PromptIntake.heard(sample.text, names: [], labeler: labeler)
            out.append(Result(sample: sample, reading: reading, ms: Int(started.duration(to: .now) / .milliseconds(1))))
        }
        return out
    }

    public static func score(_ results: [Result]) -> Score {
        func tally(_ ok: (Result) -> Bool?) -> (Int, Int) {
            let scored = results.compactMap(ok)
            return (scored.filter { $0 }.count, scored.count)
        }
        let times = results.map(\.ms).sorted()
        return Score(kind: tally(\.kindOK), tone: tally(\.toneOK), phrases: tally(\.phrasesOK),
                     leaks: results.filter(\.leaked).map(\.sample.raw), medianMs: times.isEmpty ? 0 : times[times.count / 2])
    }

    public struct Problem: Error, CustomStringConvertible {
        public var description: String
        init(_ description: String) { self.description = description }
    }
}
