import Foundation
import MellowHarness

/// What Boop takes from your prompt, in place of the prompt: how long it
/// is, which buddies' names you said and the tone its words plainly show,
/// which are counted, and, when a labeler can, what kind of work it asks
/// for, how you sound, and up to three short phrases of yours for a sign.
/// Only this reaches the transcript and the brain.
public struct PromptReading: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case fix, feature, cleanup, refactor, tests, deploy, docs, question, other
        case carryOn = "carry_on"

        /// What you asked for, after `You asked claude on "api"`.
        public var words: String {
            switch self {
            case .fix: "for a fix"
            case .feature: "for something new"
            case .cleanup: "to clean up"
            case .refactor: "for a refactor"
            case .tests: "about tests"
            case .deploy: "to ship it"
            case .docs: "for docs"
            case .question: "a question"
            case .carryOn: "to carry on"
            case .other: "for something else"
            }
        }
    }

    public enum Tone: String, CaseIterable, Sendable {
        case calm, frustrated, rushed, polite, playful, shouting, careful

        /// How you sound, in the line; nil for calm, which says nothing.
        public var words: String? {
            switch self {
            case .calm: nil
            case .frustrated: "frustrated"
            case .rushed: "in a hurry"
            case .polite: "politely"
            case .playful: "playfully"
            case .shouting: "SHOUTING"
            case .careful: "carefully"
            }
        }
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

        public var words: String {
            switch self {
            case .words: "in a few words"
            case .sentence: "in a sentence"
            case .paragraph: "in a paragraph"
            case .essay: "at length"
            }
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

        /// As a demo's or an eval's step writes them: `{"kind": "fix",
        /// "tone": "frustrated", "phrases": ["still broken"]}`, each
        /// optional; anything else, or a kind or tone off its list, is a
        /// mistake that names the lists.
        public init(json: [String: Any]) throws {
            guard Set(json.keys).subtracting(["kind", "tone", "phrases"]).isEmpty else {
                throw LabelsError("a reading has only kind, tone, phrases")
            }
            let kind = (json["kind"] as? String).flatMap(Kind.init(rawValue:)), tone = (json["tone"] as? String).flatMap(Tone.init(rawValue:))
            guard (json["kind"] == nil) == (kind == nil), (json["tone"] == nil) == (tone == nil) else {
                throw LabelsError("a reading's kind is one of \(Kind.choices), and its tone one of \(Tone.choices)")
            }
            self.init(kind: kind, tone: tone, phrases: json["phrases"] as? [String] ?? [])
        }

        /// The same, to write.
        public var json: [String: Any] {
            var out: [String: Any] = [:]
            if let kind { out["kind"] = kind.rawValue }
            if let tone { out["tone"] = tone.rawValue }
            if !phrases.isEmpty { out["phrases"] = phrases }
            return out
        }
    }

    public struct LabelsError: Error, CustomStringConvertible {
        public var description: String
        init(_ description: String) { self.description = description }
    }

    /// The most phrases kept, and the longest, in characters: what fits
    /// on a sign.
    public static let maxPhrases = 3, maxPhrase = Signs.maxLength

    public var length: Length
    /// The buddies' names you said, as they're called: with several, each
    /// buddy hears whether you said its own.
    public var named: [String]
    public var kind: Kind?
    public var tone: Tone?
    /// As a sign draws them (`Signs.drawn`).
    public var phrases: [String]

    public init(length: Length, named: [String] = [], kind: Kind? = nil, tone: Tone? = nil, phrases: [String] = []) {
        self.length = length
        self.named = named
        self.kind = kind
        self.tone = tone
        self.phrases = phrases
    }

    /// Your prompt's reading: scrubbed before anything reads it, counted,
    /// and labelled with `labels` if given.
    public init(prompt: String, names: [String], labels: Labels? = nil) {
        let text = Scrubber.scrub(prompt)
        self.init(counting: text, names: names)
        if let labels { label(labels, in: text) }
    }

    /// The same, labelled by `labeler`, if there is one.
    public static func read(_ prompt: String, names: [String], labeler: (any PromptLabeler)?) async -> PromptReading {
        let text = Scrubber.scrub(prompt)
        var reading = PromptReading(counting: text, names: names)
        if let labels = await labeler?.label(text) { reading.label(labels, in: text) }
        return reading
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

    /// What needs no model: the length, which of `names` `text` says as a
    /// word, in any case, and the tone its words show (`toneCues`), with
    /// the cue itself as a phrase, as you spelled it, if a sign can draw it.
    public init(counting text: String, names: [String]) {
        let lower = text.lowercased()
        let words = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let letters = text.filter(\.isLetter)
        let shouting = letters.count >= Self.shoutingLetters && letters.filter(\.isUppercase).count * 4 >= letters.count * 3
        let cue = shouting ? nil : Self.toneCues.lazy.compactMap { tone, cues in
            cues.first { $0.contains(" ") || !$0.allSatisfy(\.isLetter) ? lower.contains($0) : words.contains($0) }.map { (tone, $0) }
        }.first
        let said = cue.flatMap { text.range(of: $0.1, options: .caseInsensitive) }.flatMap { Signs.drawn(String(text[$0])) }
        self.init(length: Length(text), named: names.filter { words.contains($0.lowercased()) }, tone: shouting ? .shouting : cue?.0,
                  phrases: said.map { [$0] } ?? [])
    }

    /// Takes a labeler's kind and tone, and the phrases that really are in
    /// `text` (in any case, its own spelling kept) and fit a sign, then the
    /// counted cue if there's room and its tone is still the reading's: at
    /// most `maxPhrases`, none a secret or a part of one already kept.
    /// Shouting is counted, never heard: the labeler's is dropped, and a
    /// counted one stays. Any other counted tone stands where the labeler
    /// hears nothing more than calm.
    public mutating func label(_ labels: Labels, in text: String) {
        kind = labels.kind
        let counted = tone
        if tone != .shouting {
            switch labels.tone {
            case nil, .shouting?: break
            case .calm?: tone = tone ?? .calm
            case let heard?: tone = heard
            }
        }
        // Searched where the secrets are blanked out, so none is ever a phrase.
        let searchable = text.replacingOccurrences(of: Scrubber.secret, with: String(repeating: "\u{1}", count: Scrubber.secret.count))
        let found = labels.phrases.compactMap { p -> String? in
            let phrase = p.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !phrase.isEmpty, let range = searchable.range(of: phrase, options: .caseInsensitive) else { return nil }
            return Signs.drawn(String(searchable[range]))
        }
        var kept: [String] = []
        for phrase in found + (tone == counted ? phrases : [])
        where kept.count < Self.maxPhrases && phrase.count <= Self.maxPhrase
            && !kept.contains(where: { $0.range(of: phrase, options: .caseInsensitive) != nil }) {
            kept.append(phrase)
        }
        phrases = kept
    }

    /// As an event's facts.
    public var facts: [String: JSONValue] {
        var out: [String: JSONValue] = ["length": .string(length.rawValue)]
        if !named.isEmpty { out["named"] = .array(named.map(JSONValue.string)) }
        if let kind { out["kind"] = .string(kind.rawValue) }
        if let tone { out["tone"] = .string(tone.rawValue) }
        if !phrases.isEmpty { out["phrases"] = .array(phrases.map(JSONValue.string)) }
        return out
    }

    /// From an event's facts, or nil if they aren't a reading's.
    public init?(facts: [String: JSONValue]) {
        guard let length = facts["length"]?.string.flatMap(Length.init(rawValue:)) else { return nil }
        self.init(length: length, named: facts["named"]?.array?.compactMap(\.string) ?? [],
                  kind: facts["kind"]?.string.flatMap(Kind.init(rawValue:)), tone: facts["tone"]?.string.flatMap(Tone.init(rawValue:)),
                  phrases: facts["phrases"]?.array?.compactMap(\.string) ?? [])
    }
}

extension CaseIterable where Self: RawRepresentable, RawValue == String {
    /// Every case's name, `fix, feature, …`, for a list to choose from.
    public static var choices: String { allCases.map(\.rawValue).joined(separator: ", ") }
}
