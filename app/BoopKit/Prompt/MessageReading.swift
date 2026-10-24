import Foundation
import MellowHarness

/// An agent's last message's reading: what it says of its turn, and how
/// it sounds.
public typealias MessageReading = Reading<MessageText>

/// The agent's last message, as a reading reads it: only what the brain
/// judges a finish by.
public enum MessageText: ReadingText {
    public enum Kind: String, CaseIterable, Sendable {
        case done, stuck, question, answer, other

        /// What it says, after the finish's line; nil for other, which
        /// says nothing.
        public var words: String? {
            switch self {
            case .done: "saying it's done"
            case .stuck: "giving up, saying it couldn't finish"
            case .question: "asking you something"
            case .answer: "only answering"
            case .other: nil
            }
        }
    }

    public enum Tone: String, CaseIterable, Sendable {
        case calm, upbeat, apologetic, fawning

        /// How it sounds, after what it says; nil for calm.
        public var words: String? {
            switch self {
            case .calm: nil
            case .upbeat: "cheerful"
            case .apologetic: "apologetic"
            case .fawning: "fawning"
            }
        }
    }

    public static let calm = Tone.calm
    public static let shouting: Tone? = nil

    /// The tones its own words show, first match first: an agent's stock
    /// lines, then an apology.
    public static let toneCues: [(Tone, [String])] = [
        (.fawning, ["absolutely right", "you're right", "you are right", "great question", "good catch", "great catch"]),
        (.apologetic, ["sorry", "apologize", "apologies", "my mistake", "my bad"]),
    ]

    /// What it plainly claims, first match first, so a message that
    /// couldn't finish isn't done for the tests it mentions.
    public static let kindCues: [(Kind, [String])] = [
        (.stuck, ["couldn't get", "could not get", "wasn't able", "was unable", "unable to", "i'm stuck", "still failing", "still broken"]),
        (.done, ["all done", "done:", "done!", "all set", "tests pass", "all green", "is green", "works now", "now works", "is working",
                 "everything passes"]),
    ]

    /// Its claim (`kindCues`), else a question when it ends with one.
    public static func kind(counting text: String) -> Kind? {
        MessageReading.cue(in: text, kindCues)?.0
            ?? (text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?") ? .question : nil)
    }

    public static let event = Event.Kind.lastMessage

    public static func label(_ text: String, by labeler: any PromptLabeler) async -> MessageReading.Labels? {
        await labeler.label(message: text)
    }
}
