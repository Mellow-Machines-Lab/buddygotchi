import Foundation
import MellowHarness

/// The only code that holds your prompt. It scrubs it, counts it at once,
/// and has the labeler read it if there is one; then it hands on the
/// reading and lets the text go. With no labeler the reading goes on at
/// once, in order; with one, on `home` once the labeler answers or gives up.
final class PromptIntake {
    let labeler: (any PromptLabeler)?
    let home: DispatchQueue
    /// The buddies' names, any of which in a prompt is its name said.
    let names: @Sendable () -> [String]
    /// Takes the reading for the turn start it's about.
    let deliver: @Sendable (PromptReading, Event) -> Void

    init(labeler: (any PromptLabeler)?, home: DispatchQueue, names: @escaping @Sendable () -> [String],
         deliver: @escaping @Sendable (PromptReading, Event) -> Void) {
        self.labeler = labeler
        self.home = home
        self.names = names
        self.deliver = deliver
    }

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

    /// Reads `prompt`, the one `turn` brought, and hands on its reading.
    func read(_ prompt: String, about turn: Event) {
        let text = Scrubber.scrub(prompt)
        var reading = PromptReading(counting: text, names: names())
        guard let labeler else { return deliver(reading, turn) }
        let deliver = deliver, home = home
        Task {
            if let labels = await labeler.label(text) { reading.label(labels, in: text) }
            home.async { deliver(reading, turn) }
        }
    }
}
