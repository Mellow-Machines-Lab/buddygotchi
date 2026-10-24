import Foundation
import MellowHarness

/// Where your prompt leaves a turn start, and the agent's last message a
/// turn end, and each becomes its reading: the text goes no further than
/// `read`, which hands on only the reading.
enum PromptIntake {
    /// What a hook brought to read.
    enum Text: Equatable, Sendable {
        case prompt(String), message(String)
    }

    /// A reading as its event will hold it: the event's kind, and its
    /// facts, never the text.
    struct Heard: Equatable, Sendable {
        var kind: Event.Kind
        var facts: [String: JSONValue]

        init<Of>(_ reading: Reading<Of>) {
            kind = Of.event
            facts = reading.facts
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

    /// `text`'s reading at once, labelled with `labels` or `messageLabels`
    /// if given: your prompt as the buddies called `names` hear it.
    static func heard(_ text: Text, names: [String], labels: PromptReading.Labels? = nil,
                      messageLabels: MessageReading.Labels? = nil) -> Heard {
        switch text {
        case .prompt(let prompt): Heard(PromptReading(text: prompt, names: names, labels: labels))
        case .message(let message): Heard(MessageReading(text: message, names: [], labels: messageLabels))
        }
    }

    /// Reads `text` and hands on its reading: at once with no labeler,
    /// else on `home` once the labeler answers or gives up.
    static func read(_ text: Text, names: [String], labeler: (any PromptLabeler)?, home: DispatchQueue,
                     deliver: @escaping @Sendable (Heard) -> Void) {
        guard let labeler else { return deliver(heard(text, names: names)) }
        Task {
            let reading = switch text {
            case .prompt(let prompt): Heard(await PromptReading.read(prompt, names: names, labeler: labeler))
            case .message(let message): Heard(await MessageReading.read(message, names: [], labeler: labeler))
            }
            home.async { deliver(reading) }
        }
    }
}
