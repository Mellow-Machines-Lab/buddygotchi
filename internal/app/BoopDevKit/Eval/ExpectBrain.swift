import BoopKit
import Foundation
import MellowHarness

/// A brain that plays a scenario's own answers: an eval tells it each step
/// as it runs (nil between steps), and judges none of its choices, which
/// are the scenario's.
public protocol ScenarioBrain: AnyObject {
    func willRun(_ step: Scenario.Step?)
}

/// The brain a scenario implies: each pass answered from the step it
/// belongs to, so a run with no key plays as the scenario says Boop should
/// (internal/EVALS.md §2). A question gets the step's own `brain` answer,
/// else the first of its `expect` set that the question offers, else what
/// the pipeline check would answer. It prices scenarios and runs
/// `--scripted`.
public final class ExpectBrain: Brain, ScenarioBrain, @unchecked Sendable {
    public let id = "expect"
    /// The step being run; nil between steps.
    public var step: Scenario.Step?

    public init() {}

    public func willRun(_ step: Scenario.Step?) { self.step = step }

    /// Which question each `expect` field answers.
    public static let questions = ["react": MomentOutput.emotionKey, "move": MomentOutput.moveKey, "intensity": MomentOutput.sizeKey,
                                   "say": MomentOutput.sayKey, "mood": MoodOutput.outputName, "sign": Signs.questionKey]

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
        for q in questions {
            guard let want = wanted[q.key] else { continue }
            let offered = q.options.map(\.name)
            // A sign is wanted by its words: the first caption that says one,
            // and any for `some`.
            let sign = q.key == Signs.questionKey ? offered.first { $0 != "none" && Scenario.Expectation.sign(want, says: $0) } : nil
            let pick = want.first(where: offered.contains) ?? sign
            guard let pick else { continue }
            out[q.key] = Answer(choice: pick, probabilities: [pick: 1])
        }
        return out
    }
}
