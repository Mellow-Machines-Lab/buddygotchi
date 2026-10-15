import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// Every state the eval scenarios build, pinned (internal/VERIFICATION.md §5, L0):
/// each scenario runs with a scripted brain that answers from NOW alone, and
/// every state it's sent must match Boop's pack's `tests/golden-states/<scenario>.txt`
/// byte for byte. Nothing here needs Jev, so a change to how Boop's prompt
/// is built, rather than to what it says, can't slip past: the steering
/// evals, which would catch a wording change, need the owner's key. A
/// deliberate change to the prompt rewrites the files:
/// `BOOP_GOLDEN_RECORD=1 BOOP_TEST_FILTER=Golden .build/debug/BoopTests`,
/// and the diff shows what changed.
final class GoldenStateTests: XCTestCase {
    override func setUpWithError() throws { try requirePack("boop") }

    static let folder = CharacterPack.active.directory.appendingPathComponent("tests/golden-states")

    /// Answers from NOW's line alone, the same every time: a failure moves
    /// the mood a step and gets an annoyed face, a win a happy one, a poke a
    /// curious one, words to Boop a proud one, anything else an engaged one
    /// or, for a turn starting, none. So HISTORY fills with every kind of
    /// line Boop writes: moods changing, faces with and without an
    /// animation, takes said.
    nonisolated static let brain = ScriptedBrain(id: "golden") { state, questions in
        let now = state.components(separatedBy: "\nNOW (").last ?? ""
        let failed = now.contains("failed") || now.contains("gave up")
        let won = now.contains("passed") || now.contains(": done, ")
        let poked = now.contains("poked")
        let said = now.contains("You said to Boop")
        func pick(_ q: Question, _ name: String) -> Answer {
            let choice = q.options.contains { $0.name == name } ? name : q.options[0].name
            return Answer(choice: choice, probabilities: [choice: 0.9])
        }
        var out: Answers = [:]
        for q in questions {
            switch q.key {
            case "mood":
                let i = failed || poked ? 1 : won ? 2 : 0
                out[q.key] = pick(q, q.options[min(i, q.options.count - 1)].name)
            case "react.mood":
                out[q.key] = pick(q, now.contains(" started turn ") ? "none" : failed ? "annoyed" : won ? "happy"
                                  : poked ? "curious" : said ? "proud" : "engaged")
            case "react.animation":
                out[q.key] = pick(q, !now.contains(" finished turn ") ? "none" : failed ? "failure" : "success")
            case "react.loops":
                out[q.key] = pick(q, failed ? "twice" : "once")
            case "say.feeling":
                out[q.key] = pick(q, failed ? "upset" : won ? "glad" : poked ? "tickled" : "none")
            case "say.about":
                out[q.key] = pick(q, now.contains("tests") ? "tests" : now.contains(" finished turn ") ? "done"
                                  : now.contains(" started turn ") ? "start" : "work")
            case "say.kind":
                out[q.key] = pick(q, failed ? "word" : "sound")
            default:
                out[q.key] = pick(q, q.options[0].name)
            }
        }
        return out
    }

    /// A scenario's states as the fixture keeps them: each pass's state,
    /// its head (everything before HISTORY) only when it differs from the
    /// last pass's, as `debug.jsonl` logs it.
    static func text(_ states: [String]) -> String {
        var out = ""
        var lastHead: String?
        for (i, state) in states.enumerated() {
            let (head, rest) = DebugLog.split(state)
            out += "=== pass \(i + 1)\n"
            if head != lastHead {
                out += "--- head\n" + head
                lastHead = head
            }
            out += rest + "\n"
        }
        return out
    }

    func testEveryScenarioBuildsTheStatesItDid() async throws {
        let record = ProcessInfo.processInfo.environment["BOOP_GOLDEN_RECORD"] == "1"
        let states = Lines()
        let brain = ScriptedBrain(id: "golden") { state, questions in
            states.add(state)
            return try GoldenStateTests.brain.script(state, questions)
        }
        let eval = Eval(brain: brain, steering: RuntimeTests.steering)
        let scenarios = try Scenario.load(directory: try EvalTests.scenarios())
        XCTAssertGreaterThanOrEqual(scenarios.count, 60)
        if record { try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true) }
        var passes = 0
        for scenario in scenarios {
            let before = states.all.count
            _ = try await eval.run(scenario)
            let built = Array(states.all[before...])
            passes += built.count
            let file = Self.folder.appendingPathComponent(scenario.file.replacingOccurrences(of: ".json", with: ".txt"))
            let text = Self.text(built)
            if record {
                try text.write(to: file, atomically: true, encoding: .utf8)
                continue
            }
            let pinned = try String(contentsOf: file, encoding: .utf8)
            guard text != pinned else { continue }
            // BOOP_GOLDEN_OUT=DIR keeps what it built, to diff by hand.
            if let out = ProcessInfo.processInfo.environment["BOOP_GOLDEN_OUT"] {
                try? text.write(to: URL(fileURLWithPath: out).appendingPathComponent(file.lastPathComponent), atomically: true,
                                encoding: .utf8)
            }
            // The first line that differs, so a failure says where.
            let a = text.components(separatedBy: "\n"), b = pinned.components(separatedBy: "\n")
            let at = Array(zip(a, b)).firstIndex { $0 != $1 } ?? min(a.count, b.count)
            XCTFail("\(scenario.file): line \(at + 1) differs\n  now:    \(at < a.count ? a[at] : "(end)")\n  pinned: \(at < b.count ? b[at] : "(end)")")
        }
        XCTAssertGreaterThan(passes, 300, "the scenarios build states")
    }
}
