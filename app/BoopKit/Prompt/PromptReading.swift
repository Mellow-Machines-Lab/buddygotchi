import Foundation
import MellowHarness

/// What Boop takes from your prompt, in place of the prompt: how long it
/// is, whether you said the buddy's name and the tone its words plainly
/// show, which are counted, and, when a labeler can, what kind of work it
/// asks for, how you sound, and up to three short phrases of yours for a
/// sign. Only this reaches the transcript and the brain.
public struct PromptReading: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case fix, feature, cleanup, refactor, tests, deploy, docs, question, other
        case carryOn = "carry_on"
    }

    public enum Tone: String, CaseIterable, Sendable {
        case calm, frustrated, rushed, polite, playful, shouting, careful
    }

    /// By characters: a few words under 25, a sentence under 150, a
    /// paragraph under 600, and an essay beyond.
    public enum Length: String, CaseIterable, Sendable {
        case words, sentence, paragraph, essay

        public static let bounds: [(Length, Int)] = [(.words, 25), (.sentence, 150), (.paragraph, 600)]

        public init(_ text: String) {
            let n = text.trimmingCharacters(in: .whitespacesAndNewlines).count
            self = Self.bounds.first { n < $0.1 }?.0 ?? .essay
        }
    }

    /// A labeler's answer, before it's checked against the prompt.
    public struct Labels: Equatable, Sendable {
        public var kind: Kind?
        public var tone: Tone?
        public var phrases: [String]

        public init(kind: Kind? = nil, tone: Tone? = nil, phrases: [String] = []) {
            self.kind = kind
            self.tone = tone
            self.phrases = phrases
        }
    }

    /// The most phrases kept, and the longest, in characters: what fits
    /// on a sign.
    public static let maxPhrases = 3, maxPhrase = 18

    public var length: Length
    public var named: Bool
    public var kind: Kind?
    public var tone: Tone?
    public var phrases: [String] = []

    public init(length: Length, named: Bool = false, kind: Kind? = nil, tone: Tone? = nil, phrases: [String] = []) {
        self.length = length
        self.named = named
        self.kind = kind
        self.tone = tone
        self.phrases = phrases
    }

    /// The tones a prompt's own words show, first match first: capitals
    /// are shouting (most of its letters, and at least `shoutingLetters`),
    /// and these words the rest.
    public static let toneCues: [(Tone, [String])] = [
        (.careful, ["ultrathink", "think hard", "careful", "double-check", "check with me"]),
        (.rushed, ["asap", "quickly", "hurry", "right now"]),
        (.playful, ["lol", "haha", "lmao", "😂", "🙃", "😅", "🤣"]),
        (.polite, ["please", "thank you", "thanks", "sorry", "appreciate"]),
    ]
    public static let shoutingLetters = 8

    /// What needs no model: the length, whether `text` says one of `names`
    /// as a word, in any case, and the tone its words show (`toneCues`).
    public init(counting text: String, names: [String]) {
        let lower = text.lowercased()
        let words = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let letters = text.filter(\.isLetter)
        let shouting = letters.count >= Self.shoutingLetters && letters.filter(\.isUppercase).count * 4 >= letters.count * 3
        let cue = shouting ? .shouting : Self.toneCues.first { _, cues in
            cues.contains { $0.contains(" ") || !$0.allSatisfy(\.isLetter) ? lower.contains($0) : words.contains($0) }
        }?.0
        self.init(length: Length(text), named: names.contains { words.contains($0.lowercased()) }, tone: cue)
    }

    /// Takes a labeler's kind and tone, and the phrases that really are in
    /// `text` (in any case, its own spelling kept) and fit a sign, at most
    /// `maxPhrases`, without a secret. Shouting is counted, never heard:
    /// the labeler's is dropped, and a counted one stays. Any other counted
    /// tone stands where the labeler hears nothing more than calm.
    public mutating func label(_ labels: Labels, in text: String) {
        kind = labels.kind
        let heard = labels.tone == .shouting ? nil : labels.tone
        if tone != .shouting { tone = heard == nil || heard == .calm ? tone ?? heard : heard }
        // Searched where the secrets are blanked out, so none is ever a phrase.
        let searchable = text.replacingOccurrences(of: Scrubber.secret, with: String(repeating: "\u{1}", count: Scrubber.secret.count))
        var kept: [String] = []
        for p in labels.phrases {
            let phrase = p.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard kept.count < Self.maxPhrases, !phrase.isEmpty, phrase.count <= Self.maxPhrase,
                  let range = searchable.range(of: phrase, options: .caseInsensitive),
                  !kept.contains(where: { $0.caseInsensitiveCompare(phrase) == .orderedSame }) else { continue }
            kept.append(String(searchable[range]))
        }
        phrases = kept
    }

    /// As an event's facts.
    public var facts: [String: JSONValue] {
        var out: [String: JSONValue] = ["length": .string(length.rawValue), "named": .bool(named)]
        if let kind { out["kind"] = .string(kind.rawValue) }
        if let tone { out["tone"] = .string(tone.rawValue) }
        if !phrases.isEmpty { out["phrases"] = .array(phrases.map(JSONValue.string)) }
        return out
    }

    /// From an event's facts, or nil if they aren't a reading's.
    public init?(facts: [String: JSONValue]) {
        guard let length = facts["length"]?.string.flatMap(Length.init(rawValue:)) else { return nil }
        self.init(length: length, named: facts["named"]?.bool ?? false,
                  kind: facts["kind"]?.string.flatMap(Kind.init(rawValue:)), tone: facts["tone"]?.string.flatMap(Tone.init(rawValue:)),
                  phrases: facts["phrases"]?.array?.compactMap(\.string) ?? [])
    }
}
