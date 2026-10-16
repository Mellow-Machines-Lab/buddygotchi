import AgentHooks
import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// Demos: the script a character pack carries, what each beat is called
/// for whoever watches, and the recording the simulator's page plays back.
final class DemoTests: XCTestCase {
    func testAScriptIsLinesInOrder() throws {
        let script = try DemoScript("""
            {"demo": 1, "title": "Keyboard shortcuts", "agent": "codex"}
            // A comment, and a blank line.

            {"agent": "prompt", "text": "Add shortcuts"}
            {"brain": {"react.mood": "curious"}, "mood": "curious", "after": 0.5}
            {"you": "talk", "text": "how's it going?", "hold": 2}
            {"agent": "run", "cmd": "npm test", "about": "Run the tests", "fails": true, "takes": 3}
            {"agent": "run", "cmd": "npm run setup", "ask": 4}
            {"agent": "reply", "text": "Done.", "by": "reviewer"}
            {"you": "poke"}
            """)
        XCTAssertEqual(script.title, "Keyboard shortcuts")
        XCTAssertEqual(script.agent, "codex")
        XCTAssertEqual(script.steps.map(\.number), [4, 5, 6, 7, 8, 9, 10], "in the file's order")
        XCTAssertEqual(script.steps[1].what, .brain(["react.mood": "curious"], mood: "curious"))
        XCTAssertEqual(script.steps[1].after, 0.5)
        XCTAssertEqual(script.steps[2].what, .talk("how's it going?", hold: 2))
        guard case .agent(let run) = script.steps[3].what else { XCTFail("an agent step"); return }
        XCTAssertEqual([run.cmd, run.about], ["npm test", "Run the tests"])
        XCTAssertTrue(run.fails)
        XCTAssertEqual(script.steps[3].takes, 3)
        guard case .agent(let asks) = script.steps[4].what, case .agent(let report) = script.steps[5].what else { XCTFail("agent steps"); return }
        XCTAssertEqual(asks.ask, 4)
        XCTAssertTrue(report.byReviewer)
        XCTAssertEqual(script.steps[6].what, .poke)
        XCTAssertEqual(script.steps[6].input, "tap", "a finger on the device's own screen")
    }

    /// Pins how long a step waits after the one before, and an agent step
    /// takes, when the script doesn't say: about as long as each takes.
    func testWhatALineWaitsWhenTheScriptDoesntSay() throws {
        let script = try DemoScript("""
            {"agent": "prompt", "text": "Go"}
            {"brain": {}}
            {"you": "poke"}
            {"agent": "read", "file": "a.js"}
            {"agent": "run", "cmd": "make"}
            """)
        XCTAssertEqual(script.steps.map(\.after), [1, 0.3, 0.8, 1, 1])
        XCTAssertEqual(script.steps.map(\.takes), [0, 0, 0, 0.6, 2])
    }

    func testABadLineSaysWhere() {
        func problem(_ text: String) -> String {
            do {
                _ = try DemoScript(text, named: "demo.jsonl")
                return "no problem"
            } catch {
                return "\(error)"
            }
        }
        XCTAssertTrue(problem(#"{"tap": true}"#).contains("demo.jsonl:1: a step is by the agent, you or the brain"))
        XCTAssertTrue(problem("{\"you\": \"poke\"}\n{\"agent\": \"dance\"}").contains("demo.jsonl:2: agent is one of"))
        XCTAssertTrue(problem(#"{"agent": "edit", "file": "a.js"}"#).contains("an edit needs a file, old and new"))
        XCTAssertTrue(problem(#"{"brain": "happy"}"#).contains("brain is question keys to choices"))
        XCTAssertTrue(problem("{\"you\": \"poke\"}\n{\"demo\": 1}").contains("the header comes first"))
        // A mistyped key or a value of the wrong type would otherwise be left out quietly.
        XCTAssertTrue(problem(#"{"agent": "prompt", "text": "Go", "afer": 2}"#).contains("demo.jsonl:1: an agent step has no key afer"))
        XCTAssertTrue(problem(#"{"you": "poke", "after": "2"}"#).contains("demo.jsonl:1: after is a number"))
        XCTAssertTrue(problem(#"{"agent": "run", "cmd": "make", "fails": "yes"}"#).contains("fails is true or false"))
        XCTAssertTrue(problem(#"{"mood": "calm", "say": "hi"}"#).contains("a brain step has no key say"))
    }

    /// A mood alone is the brain's step: `{"mood": "proud"}`.
    func testAMoodAloneIsTheBrainsLine() throws {
        XCTAssertEqual(try DemoScript(#"{"mood": "proud"}"#).steps[0].what, .brain([:], mood: "proud"))
    }

    /// Pins the words a watcher reads for each kind of step.
    func testWhatALineIsCalled() throws {
        func cause(_ json: String, agent: String = "claude") throws -> DemoScript.Cause? {
            try DemoScript(json).steps[0].cause(creature: "Pip", agent: agent)
        }
        try XCTAssertEqual(cause(#"{"you": "poke"}"#), .init(kind: "tap", text: "You poke Pip"))
        try XCTAssertEqual(cause(#"{"you": "talk", "text": "hello"}"#), .init(kind: "talk", text: "You say “hello”"))
        try XCTAssertEqual(cause(#"{"agent": "prompt", "text": "Fix it"}"#), .init(kind: "prompt", text: "You ask Claude: “Fix it”"))
        try XCTAssertEqual(cause(#"{"agent": "read", "file": "a.js"}"#, agent: "codex"), .init(kind: "tool", text: "Codex reads a.js"))
        try XCTAssertEqual(cause(#"{"agent": "run", "cmd": "npm test", "about": "Run the tests", "fails": true}"#),
                           .init(kind: "tool_failed", text: "Claude: run the tests, and it fails"))
        try XCTAssertEqual(cause(#"{"agent": "run", "cmd": "npm run setup", "about": "Install the runner", "ask": 3}"#),
                           .init(kind: "needs_you", text: "Claude asks to install the runner, and you allow it"))
        try XCTAssertEqual(cause(#"{"agent": "review", "task": "Review the diff"}"#), .init(kind: "tool", text: "Claude sends a reviewer: Review the diff"))
        try XCTAssertEqual(cause(#"{"agent": "reply", "text": "ok", "by": "reviewer"}"#), .init(kind: "tool", text: "The reviewer reports back"))
        try XCTAssertEqual(cause(#"{"agent": "reply", "text": "Done."}"#), .init(kind: "done", text: "Claude finishes"))
        try XCTAssertNil(cause(#"{"brain": {"react.mood": "happy"}}"#), "the brain's answers show in what the creature does")
        try XCTAssertEqual(cause(#"{"you": "poke", "note": "A poke"}"#), .init(kind: "tap", text: "A poke"))
    }

    func testARecordingStartsWithHowThingsStood() {
        let clock = SoakClock(1000)
        let takes = [Take(row: "t.go\tGo\tabout\tstart\tword\texcited\t\t400"), Take(row: "t.now\tnow\tabout\tstart\tword\texcited\t\t300")]
        let recorder = DemoRecorder(clock: { clock.now }, takes: takes)
        recorder.sent(#"{"t":"hello"}"#)
        recorder.sent(#"{"t":"state","base":"asleep","mood":"calm"}"#)
        recorder.sent(#"{"t":"do","id":1,"name":"react","args":{"say":{"take":"t.old"}}}"#)
        clock.now = 5000
        recorder.begin(name: "Pip")
        clock.now = 7000
        recorder.happened(.init(kind: "tap", text: "You poke Pip"), input: "tap")
        recorder.happened(nil)  // a beat nobody would see is no event
        clock.now = 7250
        recorder.sent(#"{"t":"do","id":2,"name":"react","play":"next","args":{"say":{"take":"t.go","then":"t.now"},"mood":"excited"}}"#)
        clock.now = 9000
        let recording = recorder.recording(character: "pixel", face: "pixel")
        XCTAssertEqual(recording.events.map(\.at), [0, 2, 2.25])
        XCTAssertEqual(recording.events[0].line, #"{"t":"state","base":"asleep","mood":"calm"}"#, "the device's picture, as a board that just connected is told")
        XCTAssertEqual(recording.events[1].cause?.text, "You poke Pip")
        XCTAssertEqual(recording.events[1].input, "tap", "a finger on the device's own screen, for whoever replays it")
        XCTAssertEqual(recording.takes, ["t.go", "t.now"], "only what the demo itself says, both takes of a `say`")
        XCTAssertEqual(recording.name, "Pip")
        XCTAssertEqual(recording.length, 4)
        XCTAssertEqual(recording.version, 1)
    }

    /// Pins the words for what the creature does at each kind of step.
    func testWhatTheCreatureDoesIsRecordedInWords() {
        let recorder = DemoRecorder(takes: [Take(row: "t.go\tGo\tabout\tstart\tword\texcited\t\t400")])
        recorder.begin(name: "Pip")
        for message in [
            #"{"t":"state","base":"working","mood":"calm","busy":1}"#,
            #"{"t":"state","base":"working","mood":"calm","busy":1}"#,
            #"{"t":"do","id":1,"name":"react","args":{"say":{"take":"t.go"},"mood":"excited"}}"#,
            #"{"t":"do","id":2,"name":"react","args":{"mood":"curious"}}"#,
            #"{"t":"state","base":"working","mood":"happy","attn":{"agent":"claude"}}"#,
            #"{"t":"state","base":"working","mood":"proud"}"#,
            #"{"t":"do","id":3,"name":"task_complete","args":{"outcome":"success"}}"#,
            #"{"t":"do","id":4,"name":"task_complete","args":{"outcome":"failure"}}"#,
            #"{"t":"do","id":5,"name":"error"}"#,
            #"{"t":"do","id":6,"name":"listening"}"#,
            #"{"t":"do","id":7,"name":"starting"}"#,
        ] { recorder.sent(message) }
        XCTAssertEqual(recorder.recording(character: "pixel", face: "pixel").events.map(\.effect), [
            nil, nil, "Pip makes an excited face and says “Go”", "Pip makes a curious face",
            "Pip shows that it needs you", "Pip's mood is now proud", "Pip celebrates", "Pip slumps", "Pip winces", "Pip listens", nil,
        ])
    }

    /// Every pack's demos are checked against their pack by PackCheck
    /// (CharacterPackTests); this is what it finds in a bad one.
    func testAScriptThePackCantPlaySaysWhere() throws {
        let script = try DemoScript("""
            {"agent": "prompt", "text": "Go"}
            {"brain": {"react.mood": "jolly", "say.kind": "word", "react.dance": "yes"}}
            {"mood": "ecstatic"}
            {"brain": {"react.mood": "none", "say.kind": "wrod"}, "mood": "calm"}
            """)
        let pack = try CharacterPack(directory: CharacterPackTests.repo.appendingPathComponent("characters/pixel"))
        let problems = script.problems(for: pack)
        XCTAssertEqual(problems.count, 4, "\(problems)")
        XCTAssertTrue(problems[0].hasPrefix("line 2: the brain is never asked react.dance"))
        XCTAssertTrue(problems[1].hasPrefix("line 2: react.mood has no choice jolly; it has none, \(pack.moods[0].id)"))
        XCTAssertTrue(problems[2].hasPrefix("line 3: pixel has no mood ecstatic"))
        XCTAssertTrue(problems[3].hasPrefix("line 4: say.kind has no choice wrod"))
    }
}
