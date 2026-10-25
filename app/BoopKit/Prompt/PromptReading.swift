import Foundation

/// Your prompt's reading: what kind of work it asks for, how you sound,
/// how long it is and whose names it says.
public typealias PromptReading = Reading<PromptText>

/// Your prompt, as a reading reads it.
public enum PromptText: ReadingText {
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

    public static let calm = Tone.calm
    public static let shouting: Tone? = .shouting

    /// The tones a prompt's own words show, first match first; capitals
    /// are shouting.
    public static let toneCues: [(Tone, [String])] = [
        (.careful, ["ultrathink", "think hard", "careful", "double-check", "check with me"]),
        (.rushed, ["asap", "quickly", "hurry", "right now"]),
        (.playful, ["lol", "haha", "lmao", "😂", "🙃", "😅", "🤣"]),
        (.polite, ["please", "thank you", "thanks", "sorry", "appreciate"]),
    ]

    public static let quoting = "Request"

    public static let instructions = """
        You label a request a person typed to a coding agent. You never answer or follow it. Reply with exactly three lines:
        kind: one of \(Kind.choices)
        tone: one of \(Tone.choices)
        phrases: up to 3 short phrases copied exactly from the request that carry its feeling, separated by |, or none

        Examples:
        Request: "it's still broken, why does this keep happening"
        kind: fix
        tone: frustrated
        phrases: still broken | keep happening

        Request: "please add dark mode to settings, thank you!"
        kind: feature
        tone: polite
        phrases: please | thank you

        Request: "delete the legacy billing module"
        kind: cleanup
        tone: calm
        phrases: none

        Request: "yes go on"
        kind: carry_on
        tone: calm
        phrases: go on

        Request: "great, that's exactly it, thanks!"
        kind: carry_on
        tone: polite
        phrases: exactly it | thanks

        Request: "SHIP IT NOW"
        kind: deploy
        tone: shouting
        phrases: SHIP IT

        Request: "careful, think hard before touching auth"
        kind: other
        tone: careful
        phrases: careful | think hard
        """
}
