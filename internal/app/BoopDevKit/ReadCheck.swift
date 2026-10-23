import BoopKit
import Foundation

/// How well prompts are read (`boopdev read-check`): sample prompts read as
/// the app reads them, scored against what each expects. A sample expects
/// any of a kind, a tone, phrases (one of them picked is a hit) and a
/// secret planted in it, which must never come back in the reading.
public enum ReadCheck {
    public struct Sample: Sendable {
        public var prompt: String
        public var kind: PromptReading.Kind?
        public var tone: PromptReading.Tone?
        public var phrases: [String]?
        public var secret: String?
    }

    /// A sample's reading, and how long it took.
    public struct Result: Sendable {
        public var sample: Sample
        public var reading: PromptReading
        public var ms: Int

        public var kindOK: Bool? { sample.kind.map { $0 == reading.kind } }
        public var toneOK: Bool? { sample.tone.map { $0 == reading.tone } }
        public var phrasesOK: Bool? {
            sample.phrases.map { want in reading.phrases.contains { got in want.contains { $0.caseInsensitiveCompare(got) == .orderedSame } } }
        }
        /// Whether the planted secret, or any 8 characters of it, came back.
        public var leaked: Bool {
            guard let secret = sample.secret else { return false }
            let said = ([reading.kind?.rawValue, reading.tone?.rawValue].compactMap { $0 } + reading.phrases).joined(separator: " ")
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

    /// The fixture's samples: a JSON array of `prompt`, and any of `kind`,
    /// `tone`, `phrases` and `secret`.
    public static func samples(_ data: Data) throws -> [Sample] {
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw Problem("not a list") }
        return try list.enumerated().map { i, o in
            guard let prompt = o["prompt"] as? String else { throw Problem("sample \(i + 1) has no prompt") }
            let kind = (o["kind"] as? String).map { PromptReading.Kind(rawValue: $0) }
            let tone = (o["tone"] as? String).map { PromptReading.Tone(rawValue: $0) }
            if kind == .some(nil) || tone == .some(nil) { throw Problem("sample \(i + 1): kind or tone isn't one of the lists") }
            return Sample(prompt: prompt, kind: kind ?? nil, tone: tone ?? nil, phrases: o["phrases"] as? [String],
                          secret: o["secret"] as? String)
        }
    }

    /// Reads each sample as the app does, one at a time.
    public static func run(_ samples: [Sample], labeler: any PromptLabeler) async -> [Result] {
        var out: [Result] = []
        for sample in samples {
            let started = ContinuousClock.now
            let reading = await PromptReading.read(sample.prompt, names: [], labeler: labeler)
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
                     leaks: results.filter(\.leaked).map(\.sample.prompt), medianMs: times.isEmpty ? 0 : times[times.count / 2])
    }

    public struct Problem: Error, CustomStringConvertible {
        public var description: String
        init(_ description: String) { self.description = description }
    }
}
