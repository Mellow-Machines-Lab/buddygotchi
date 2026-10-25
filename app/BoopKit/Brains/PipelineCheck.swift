import Foundation
import MellowHarness

extension ScriptedBrain {
    /// For pipeline checks with no network (`Boop --headless --brain
    /// scripted`): every pass, an excited face that names a start (a
    /// `start` take, in excited: "Go" or the like), small, and the mood
    /// kept (the mood question's first option); and a turn's finish in it
    /// when NOW is a turn that ended, success when done and failure when
    /// failed, since no rule plays one.
    /// An answer a question doesn't offer is its first option, as Jev can
    /// only pick one of each question's own.
    public static let pipelineCheck = ScriptedBrain(id: "scripted") { state, questions in
        let now = state.components(separatedBy: "\nNOW (").last ?? ""
        let finish = !now.contains(" finished turn ") ? "none"
            : now.contains(": done, a ") ? "success" : now.contains(": failed, a ") ? "failure" : "none"
        let answers: Answers = [
            ReactOutput.faceKey: Answer(choice: "excited", probabilities: ["excited": 1]),
            ReactOutput.moveKey: Answer(choice: finish, probabilities: [finish: 1]),
            ReactOutput.intensityKey: Answer(choice: "small", probabilities: ["small": 1]),
            ReactOutput.sayKey: Answer(choice: "start", probabilities: ["start": 1]),
        ]
        var out: Answers = [:]
        for q in questions {
            let offered = answers[q.key].flatMap { a in q.options.contains { $0.name == a.choice } ? a : nil }
            out[q.key] = offered ?? q.options.first.map { Answer(choice: $0.name, probabilities: [$0.name: 1]) }
        }
        return out
    }
}
