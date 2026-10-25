import Foundation
import MellowHarness

/// Where your prompt leaves a turn start, and the agent's last message a
/// turn end, and each becomes its reading: the text goes no further than
/// `heard`, which hands on only the reading.
public enum PromptIntake {
    /// What a hook brought to read.
    public enum Text: Equatable, Sendable {
        case prompt(String), message(String)
    }

    /// A labeler's answer for a text, from that text's own lists: what
    /// the tools, tests and evals give in place of Apple Intelligence's.
    public enum Labels: Equatable, Sendable {
        case prompt(PromptReading.Labels), message(MessageReading.Labels)

        public var prompt: PromptReading.Labels? { if case .prompt(let labels) = self { labels } else { nil } }
        public var message: MessageReading.Labels? { if case .message(let labels) = self { labels } else { nil } }
    }

    /// A text's reading, as its event holds it: never the text.
    public enum Heard: Equatable, Sendable {
        case prompt(PromptReading), message(MessageReading)

        /// Its event's kind.
        public var kind: Event.Kind {
            switch self {
            case .prompt: .prompt
            case .message: .lastMessage
            }
        }

        /// Its event's facts.
        public var facts: [String: JSONValue] {
            switch self {
            case .prompt(let reading): reading.facts
            case .message(let reading): reading.facts
            }
        }
    }

    /// `event` without its text, and the text, if it brought one: your
    /// prompt, or a finish's last message with words in it. The event says
    /// its text is being read (`readingFollows`), so the reading, not the
    /// event, wakes the brain.
    static func split(_ event: Event) -> (Event, Text?) {
        var event = event
        if let prompt = event.data.removeValue(forKey: "prompt")?.string {
            event.data[readingFollows] = true
            return (event, .prompt(prompt))
        }
        guard event.type == .turn, event.phase == .end, let message = event.data.removeValue(forKey: "message")?.string,
              !message.allSatisfy(\.isWhitespace) else { return (event, nil) }
        event.data[readingFollows] = true
        return (event, .message(message))
    }

    /// The fact on a turn start or end whose text's reading comes next.
    static let readingFollows = "reading_follows"

    /// `text`'s reading at once, labelled with `labels` if they're its
    /// own: your prompt as the buddies called `names` hear it.
    static func heard(_ text: Text, names: [String], labels: Labels? = nil) -> Heard {
        switch text {
        case .prompt(let prompt): .prompt(PromptReading(text: prompt, names: names, labels: labels?.prompt))
        case .message(let message): .message(MessageReading(text: message, labels: labels?.message))
        }
    }

    /// The same, labelled by `labeler` if there is one: as the app hears it.
    public static func heard(_ text: Text, names: [String], labeler: (any PromptLabeler)?) async -> Heard {
        switch text {
        case .prompt(let prompt): .prompt(await PromptReading(text: prompt, names: names, labeler: labeler))
        case .message(let message): .message(await MessageReading(text: message, labeler: labeler))
        }
    }

    /// Reads `text` and hands on its reading: at once with no labeler,
    /// else on `home` once the labeler answers or gives up.
    static func read(_ text: Text, names: [String], labeler: (any PromptLabeler)?, home: DispatchQueue,
                     deliver: @escaping @Sendable (Heard) -> Void) {
        guard let labeler else { return deliver(heard(text, names: names)) }
        Task {
            let reading = await heard(text, names: names, labeler: labeler)
            home.async { deliver(reading) }
        }
    }
}
