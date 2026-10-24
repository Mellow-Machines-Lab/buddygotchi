import Foundation
import MellowHarness

/// What a reading reads, and the closed lists it reads it by: your prompt
/// (`PromptText`) or an agent's last message (`MessageText`).
public protocol ReadingText: Sendable {
    associatedtype Kind: RawRepresentable, CaseIterable, Hashable, Sendable where Kind.RawValue == String
    associatedtype Tone: RawRepresentable, CaseIterable, Hashable, Sendable where Tone.RawValue == String
    /// The tone that says nothing: a counted tone stands over the
    /// labeler's.
    static var calm: Tone { get }
    /// The tone capitals show, counted and never heard, if it has one.
    static var shouting: Tone? { get }
    /// The tones its words plainly show, first match first: the cue is a
    /// phrase, as it's spelled.
    static var toneCues: [(Tone, [String])] { get }
    /// The kind its words plainly show, if any.
    static func kind(counting text: String) -> Kind?
    /// The event its reading is.
    static var event: Event.Kind { get }
    /// `labeler`'s answer for `text`, scrubbed.
    static func label(_ text: String, by labeler: any PromptLabeler) async -> Reading<Self>.Labels?
}

extension ReadingText {
    public static func kind(counting text: String) -> Kind? { nil }
}

/// By characters: a few words under 25, a sentence under 150, a
/// paragraph under 600, and an essay beyond.
public enum ReadingLength: String, CaseIterable, Sendable {
    case words, sentence, paragraph, essay

    public static let bounds: [(ReadingLength, Int)] = [(.words, 25), (.sentence, 150), (.paragraph, 600)]

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

/// What Boop takes from a text, in place of the text: how long it is,
/// which buddies' names it says and the tone (and, for a message, the
/// kind) its words plainly show, which are counted, and, when a labeler
/// can, its kind from `Of`'s list, how it sounds, and up to three short
/// phrases of it for a sign. Only this reaches the transcript and the
/// brain.
public struct Reading<Of: ReadingText>: Equatable, Sendable {
    public typealias Kind = Of.Kind
    public typealias Tone = Of.Tone
    public typealias Length = ReadingLength

    /// A labeler's answer, before it's checked against the text.
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
    public static var maxPhrases: Int { 3 }
    public static var maxPhrase: Int { Signs.maxLength }
    /// Capitals are shouting when most of the letters are, and at least
    /// this many.
    public static var shoutingLetters: Int { 8 }

    public var length: Length
    /// The buddies' names it says, as they're called: with several, each
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

    /// `text`'s reading: scrubbed before anything reads it, counted, and
    /// labelled with `labels` if given.
    public init(text: String, names: [String], labels: Labels? = nil) {
        let text = Scrubber.scrub(text)
        self.init(counting: text, names: names)
        if let labels { label(labels, in: text) }
    }

    /// The same, labelled by `labeler`, if there is one.
    public static func read(_ text: String, names: [String], labeler: (any PromptLabeler)?) async -> Reading {
        let text = Scrubber.scrub(text)
        var reading = Reading(counting: text, names: names)
        if let labeler, let labels = await Of.label(text, by: labeler) { reading.label(labels, in: text) }
        return reading
    }

    /// The first of `cues` whose words `text` says, with the cue: one with
    /// a space or a mark anywhere in it, a word as a word, in any case.
    static func cue<T>(in text: String, _ cues: [(T, [String])]) -> (T, String)? {
        let lower = text.lowercased()
        let words = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return cues.lazy.compactMap { value, cues in
            cues.first { $0.contains(" ") || !$0.allSatisfy(\.isLetter) ? lower.contains($0) : words.contains($0) }.map { (value, $0) }
        }.first
    }

    /// What needs no model: the length, which of `names` `text` says as a
    /// word, in any case, the kind `Of` counts, and the tone its words
    /// show (`toneCues`; capitals are shouting, for a text that has it),
    /// with the cue itself as a phrase, as it's spelled, if a sign can
    /// draw it.
    public init(counting text: String, names: [String]) {
        let words = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let letters = text.filter(\.isLetter)
        let shouting = Of.shouting.flatMap { shouted in
            letters.count >= Self.shoutingLetters && letters.filter(\.isUppercase).count * 4 >= letters.count * 3 ? shouted : nil
        }
        let cue = shouting == nil ? Self.cue(in: text, Of.toneCues) : nil
        let said = cue.flatMap { text.range(of: $0.1, options: .caseInsensitive) }.flatMap { Signs.drawn(String(text[$0])) }
        self.init(length: Length(text), named: names.filter { words.contains($0.lowercased()) }, kind: Of.kind(counting: text),
                  tone: shouting ?? cue?.0, phrases: said.map { [$0] } ?? [])
    }

    /// Takes a labeler's kind, if it has one, and tone, and the phrases
    /// that really are in `text` (in any case, its own spelling kept) and
    /// fit a sign, then the counted cue if there's room and its tone is
    /// still the reading's: at most `maxPhrases`, none a secret or a part
    /// of one already kept. Shouting is counted, never heard: the
    /// labeler's is dropped, and a counted one stays. Any other counted
    /// tone stands where the labeler hears nothing more than calm.
    public mutating func label(_ labels: Labels, in text: String) {
        kind = labels.kind ?? kind
        let counted = tone
        if Of.shouting == nil || tone != Of.shouting {
            switch labels.tone {
            case nil: break
            case let heard? where heard == Of.shouting: break
            case let heard? where heard == Of.calm: tone = tone ?? heard
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
