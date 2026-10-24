import Foundation
import MellowHarness

/// Where your prompt leaves a turn start and becomes its reading: the
/// prompt goes no further than `read`, which hands on only the reading.
enum PromptIntake {
    /// `event` without your prompt, and the prompt, if it brought one:
    /// the event says its prompt is being read (`readingFollows`), so the
    /// reading, not the event, wakes the brain.
    static func split(_ event: Event) -> (Event, prompt: String?) {
        var event = event
        guard let prompt = event.data.removeValue(forKey: "prompt")?.string else { return (event, nil) }
        event.data[readingFollows] = true
        return (event, prompt)
    }

    /// The fact on a turn start whose prompt's reading comes next.
    static let readingFollows = "reading_follows"

    /// Reads `prompt` and hands on its reading: at once with no labeler,
    /// else on `home` once the labeler answers or gives up.
    static func read(_ prompt: String, names: [String], labeler: (any PromptLabeler)?, home: DispatchQueue,
                     deliver: @escaping @Sendable (PromptReading) -> Void) {
        guard let labeler else { return deliver(PromptReading(prompt: prompt, names: names)) }
        Task {
            let reading = await PromptReading.read(prompt, names: names, labeler: labeler)
            home.async { deliver(reading) }
        }
    }
}
