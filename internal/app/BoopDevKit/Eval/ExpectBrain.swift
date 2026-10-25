import BoopKit
import Foundation
import MellowHarness

/// A brain that plays a scenario's own answers: an eval tells it each step
/// as it runs (nil between steps) and the moods a later step wants, and
/// judges none of its choices, which are the scenario's.
public protocol ScenarioBrain: AnyObject {
    func willRun(_ step: Scenario.Step?, ahead: [String])
}

/// The brain a scenario implies: each pass answered from the step it
/// belongs to, so a run with no key plays as the scenario says Boop should
/// (internal/EVALS.md §2). A question gets the step's own `brain` answer,
/// else the first of its `expect` set that the question offers, else what
/// the pipeline check would answer. It prices scenarios, and turns them
/// into demos (`DemoFromScenario`).
public final class ExpectBrain: Brain, ScenarioBrain, @unchecked Sendable {
    public let id = "expect"
    /// The step being run; nil between steps.
    public var step: Scenario.Step?
    /// The moods a later step wants, which a step that says none heads
    /// toward, as Jev must to get there a step a pass.
    public var ahead: [String] = []

    public init() {}

    public func willRun(_ step: Scenario.Step?, ahead: [String]) {
        self.step = step
        self.ahead = ahead
    }

    /// Which question each `expect` field answers.
    public static let questions = ["react": ReactOutput.faceKey, "move": ReactOutput.moveKey, "intensity": ReactOutput.intensityKey,
                                   "say": ReactOutput.sayKey, "mood": MoodOutput.outputName, "sign": Signs.questionKey]

    /// What `step` answers for each question, in the order to try:
    /// its `brain`'s, then its `expect`'s.
    public static func wanted(_ step: Scenario.Step) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (field, values) in step.expectOrder {
            if let key = questions[field] { out[key] = values }
        }
        for (key, choice) in step.brain ?? [:] { out[key] = [choice] + (out[key] ?? []) }
        return out
    }

    public func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
        var out = try await ScriptedBrain.pipelineCheck.answer(state: state, questions: questions, deadline: deadline)
        guard let step else { return out }
        let wanted = Self.wanted(step)
        // A later step's mood a move away waits for that step; one further
        // starts on its way now.
        if wanted[MoodOutput.outputName] == nil, !ahead.isEmpty,
           let q = questions.first(where: { $0.key == MoodOutput.outputName }), let stay = q.options.first?.name,
           !ahead.contains(stay), !q.options.contains(where: { ahead.contains($0.name) }),
           let pick = Self.toward(ahead, from: stay, offered: q.options.map(\.name)) {
            out[q.key] = Answer(choice: pick, probabilities: [pick: 1])
        }
        for q in questions {
            guard let want = wanted[q.key] else { continue }
            let offered = q.options.map(\.name)
            // The mood moves a step a pass: toward the nearest wanted mood
            // when none is a step away. Its first option is staying.
            // A sign is wanted by its words: the first caption that says one,
            // and any for `some`.
            let sign = q.key == Signs.questionKey ? offered.first { $0 != "none" && Scenario.Expectation.sign(want, says: $0) } : nil
            let pick = want.first(where: offered.contains) ?? sign
                ?? (q.key == MoodOutput.outputName ? Self.toward(want, from: offered.first ?? "", offered: offered) : nil)
            guard let pick else { continue }
            out[q.key] = Answer(choice: pick, probabilities: [pick: 1])
        }
        return out
    }

    /// The offered move on a shortest path from `mood` to any of `targets`
    /// on the mood graph, or nil when none leads there.
    static func toward(_ targets: [String], from mood: String, offered: [String]) -> String? {
        let moves = MoodGraph.moves
        var first: [String: String] = [:]  // each mood reached, by the move it started with
        var frontier: [String] = []
        for m in offered.dropFirst() where first[m] == nil {
            first[m] = m
            frontier.append(m)
        }
        while !frontier.isEmpty {
            if let hit = frontier.first(where: targets.contains) { return first[hit] }
            var next: [String] = []
            for m in frontier {
                for n in moves[m]?.all ?? [] where first[n] == nil && n != mood {
                    first[n] = first[m]
                    next.append(n)
                }
            }
            frontier = next
        }
        return nil
    }
}
