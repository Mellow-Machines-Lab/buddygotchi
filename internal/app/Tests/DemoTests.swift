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
        XCTAssertEqual(script.lines.map(\.number), [4, 5, 6, 7, 8, 9, 10], "in the file's order")
        XCTAssertEqual(script.lines[1].what, .brain(["react.mood": "curious"], mood: "curious"))
        XCTAssertEqual(script.lines[1].after, 0.5)
        XCTAssertEqual(script.lines[2].what, .talk("how's it going?", hold: 2))
        guard case .agent(let run) = script.lines[3].what else { XCTFail("an agent line"); return }
        XCTAssertEqual([run.cmd, run.about], ["npm test", "Run the tests"])
        XCTAssertTrue(run.fails)
        XCTAssertEqual(script.lines[3].takes, 3)
        guard case .agent(let asks) = script.lines[4].what, case .agent(let report) = script.lines[5].what else { XCTFail("agent lines"); return }
        XCTAssertEqual(asks.ask, 4)
        XCTAssertTrue(report.byReviewer)
        XCTAssertEqual(script.lines[6].what, .poke)
        XCTAssertEqual(script.lines[6].input, "tap", "a finger on the device's own screen")
    }

    /// Pins how long a line waits after the one before, and an agent line
    /// takes, when the script doesn't say: about as long as each takes.
    func testWhatALineWaitsWhenTheScriptDoesntSay() throws {
        let script = try DemoScript("""
            {"agent": "prompt", "text": "Go"}
            {"brain": {}}
            {"you": "poke"}
            {"agent": "read", "file": "a.js"}
            {"agent": "run", "cmd": "make"}
            """)
        XCTAssertEqual(script.lines.map(\.after), [1, 0.3, 0.8, 1, 1])
        XCTAssertEqual(script.lines.map(\.takes), [0, 0, 0, 0.6, 2])
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
        XCTAssertTrue(problem(#"{"tap": true}"#).contains("demo.jsonl:1: a line is by the agent, you or the brain"))
        XCTAssertTrue(problem("{\"you\": \"poke\"}\n{\"agent\": \"dance\"}").contains("demo.jsonl:2: agent is one of"))
        XCTAssertTrue(problem(#"{"agent": "edit", "file": "a.js"}"#).contains("an edit needs a file, old and new"))
        XCTAssertTrue(problem(#"{"brain": "happy"}"#).contains("brain is question keys to choices"))
        XCTAssertTrue(problem("{\"you\": \"poke\"}\n{\"demo\": 1}").contains("the header comes first"))
    }

    /// Pins the words a watcher reads for each kind of line.
    func testWhatALineIsCalled() throws {
        func cause(_ json: String, agent: String = "claude") throws -> DemoScript.Cause? {
            try DemoScript(json).lines[0].cause(creature: "Pip", agent: agent)
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
        XCTAssertEqual(recording.takes, ["t.go", "t.now"], "only what the demo itself says, both takes of a line")
        XCTAssertEqual(recording.name, "Pip")
        XCTAssertEqual(recording.length, 4)
        XCTAssertEqual(recording.version, 1)
    }

    /// Pins the words for what the creature does at each kind of line.
    func testWhatTheCreatureDoesIsRecordedInWords() {
        let recorder = DemoRecorder(takes: [Take(row: "t.go\tGo\tabout\tstart\tword\texcited\t\t400")])
        recorder.begin(name: "Pip")
        for line in [
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
        ] { recorder.sent(line) }
        XCTAssertEqual(recorder.recording(character: "pixel", face: "pixel").events.map(\.effect), [
            nil, nil, "Pip makes an excited face and says “Go”", "Pip makes a curious face",
            "Pip shows that it needs you", "Pip's mood is now proud", "Pip celebrates", "Pip slumps", "Pip winces", "Pip listens", nil,
        ])
    }

    /// The character pack's own demos play in its own words: every answer
    /// is to a question the brain is asked, with a choice it's offered, and
    /// every mood is one the pack has.
    func testThePacksDemosAnswerWhatTheBrainIsAsked() throws {
        try XCTSkipUnless(!CharacterPack.active.demos.isEmpty, "the pack \(CharacterPack.active.id) has no demo")
        var offered = Dictionary(uniqueKeysWithValues: ReactAction.asked.map { ($0.key, Set($0.options.map(\.name))) })
        offered["react.mood", default: []].formUnion(CharacterPack.active.moods.map(\.id))
        for url in CharacterPack.active.demos {
            let name = url.lastPathComponent
            let script = try DemoScript(contentsOf: url)
            XCTAssertFalse(script.lines.isEmpty, name)
            for line in script.lines {
                guard case .brain(let answers, let mood) = line.what else { continue }
                for (key, choice) in answers {
                    XCTAssertTrue(offered[key]?.contains(choice) == true, "\(name):\(line.number): \(key) has no choice \(choice)")
                }
                if let mood {
                    XCTAssertTrue(CharacterPack.active.moods.contains { $0.id == mood }, "\(name):\(line.number): no mood \(mood)")
                }
            }
        }
    }
}
