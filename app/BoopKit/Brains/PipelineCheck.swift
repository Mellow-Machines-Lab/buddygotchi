import Foundation
import MellowHarness

extension ScriptedBrain {
    /// For pipeline checks with no network (`Boop --headless --brain
    /// scripted`): every pass, an excited face that says something about
    /// the work (a `work` take, in excited), and the mood kept (the mood
    /// question's first option). The move and the size are the rules'
    /// (`MomentRule`), so a turn that ended gets its finish.
    /// An answer a question doesn't offer is its first option, as Jev can
    /// only pick one of each question's own.
    public static let pipelineCheck = ScriptedBrain(id: "scripted") { _, questions in
        let answers: Answers = [
            MomentOutput.emotionKey: Answer(choice: "excited", probabilities: ["excited": 1]),
            MomentOutput.sayKey: Answer(choice: "work", probabilities: ["work": 1]),
        ]
        var out: Answers = [:]
        for q in questions {
            let offered = answers[q.key].flatMap { a in q.options.contains { $0.name == a.choice } ? a : nil }
            out[q.key] = offered ?? q.options.first.map { Answer(choice: $0.name, probabilities: [$0.name: 1]) }
        }
        return out
    }
}
