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

    /// Pins a back's break: an hour when the script doesn't say, and more
    /// than none when it does.
    func testABackIsABreakOfSomeMinutes() throws {
        try XCTAssertEqual(DemoScript(#"{"you": "back"}"#).steps[0].what, .back(ms: 3_600_000))
        try XCTAssertEqual(DemoScript(#"{"you": "back", "minutes": 600}"#).steps[0].what, .back(ms: 36_000_000))
        try XCTAssertThrowsError(try DemoScript(#"{"you": "back", "minutes": 0}"#))
        try XCTAssertThrowsError(try DemoScript(#"{"you": "back", "minutes": "lots"}"#))
        try XCTAssertThrowsError(try DemoScript(#"{"you": "wave"}"#)) { XCTAssertTrue("\($0)".contains("you is poke, press, hold, talk, back or wait")) }
    }

    /// A hold is a finger kept on the needs-you screen, which a recording
    /// replays on the board as one (`input`); a wait is minutes passing at
    /// once, which it says.
    func testAHoldDismissesAndAWaitPassesTime() throws {
        let hold = try DemoScript(#"{"you": "hold"}"#).steps[0]
        XCTAssertEqual(hold.what, .hold)
        XCTAssertEqual(hold.input, "hold")
        XCTAssertEqual(hold.cause(creature: "Pip", agent: "claude")?.text, "You hold a finger on Pip's needs-you screen")
        let wait = try DemoScript(#"{"you": "wait", "minutes": 8}"#).steps[0]
        XCTAssertEqual(wait.what, .wait(ms: 480_000))
        XCTAssertNil(wait.input)
        XCTAssertEqual(wait.cause(creature: "Pip", agent: "claude")?.text, "8 minutes later")
        XCTAssertEqual(DemoScript.Step.minutes(90 * 60_000), "1 hour 30 minutes")
        XCTAssertEqual(DemoScript.Step.minutes(60_000), "1 minute")
        try XCTAssertThrowsError(try DemoScript(#"{"you": "wait"}"#)) { XCTAssertTrue("\($0)".contains("a wait's minutes are more than 0")) }
        // A request to hold a finger on: it waits while the next steps play.
        let asks = try DemoScript(#"{"agent": "run", "cmd": "npm i", "about": "Install the packages", "ask": 30, "waits": true}"#).steps[0]
        XCTAssertEqual(asks.cause(creature: "Pip", agent: "claude")?.text, "Claude asks to install the packages, and waits for you")
        try XCTAssertThrowsError(try DemoScript(#"{"agent": "run", "cmd": "npm i", "waits": true}"#)) { XCTAssertTrue("\($0)".contains("only a run that asks waits")) }
    }

    /// A todo is the agent writing its to-do list: done of all.
    func testATodoIsTheAgentsList() throws {
        let step = try DemoScript(#"{"agent": "todo", "todos": "2/4"}"#).steps[0]
        guard case .agent(let a) = step.what else {
            XCTFail("\(step.what)")
            return
        }
        XCTAssertEqual(a.todos, StateSnapshot.Todo(done: 2, total: 4))
        XCTAssertEqual(step.cause(creature: "Pip", agent: "claude")?.text, "Claude ticks off its to-do list: 2 of 4 done")
        for bad in [#"{"agent": "todo"}"#, #"{"agent": "todo", "todos": "5/4"}"#, #"{"agent": "todo", "todos": "2 of 4"}"#,
                    #"{"agent": "read", "file": "a.js", "todos": "1/2"}"#] {
            try XCTAssertThrowsError(try DemoScript(bad)) { XCTAssertTrue("\($0)".contains("todo"), "\($0)") }
        }
    }

    /// A press is BOOT: the board hands you the next agent, which a
    /// recording replays on the board as a press (`input`).
    func testAPressIsBOOT() throws {
        let step = try DemoScript(#"{"you": "press"}"#).steps[0]
        XCTAssertEqual(step.what, .press)
        XCTAssertEqual(step.input, "press")
        XCTAssertEqual(step.cause(creature: "Pip", agent: "claude")?.text, "You press Pip's button")
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

    /// A compact is the agent's context filling up mid-turn: its summary
    /// is optional, it takes 2 s when the script doesn't say, and it comes
    /// after the prompt, before the reply, with more of the turn after it.
    /// The model says nothing at the wall, and only the main thread has one.
    func testACompactIsTheContextFillingUpInATurn() throws {
        let script = try DemoScript("""
            {"agent": "prompt", "text": "Go"}
            {"agent": "compact", "summary": "The tax is in; the tests are next.", "note": "The wall"}
            {"agent": "compact", "summary": "Where it was."}
            {"agent": "run", "cmd": "npm test"}
            {"agent": "reply", "text": "Done."}
            """)
        guard case .agent(let wall) = script.steps[1].what else { XCTFail("an agent step"); return }
        XCTAssertEqual(wall.does, .compact)
        XCTAssertEqual(wall.summary, "The tax is in; the tests are next.")
        XCTAssertEqual([script.steps[2].after, script.steps[2].takes], [1, 2])
        func problem(_ text: String) -> String {
            do {
                _ = try DemoScript(text, named: "demo.jsonl")
                return "no problem"
            } catch {
                return "\(error)"
            }
        }
        let prompt = #"{"agent": "prompt", "text": "Go"}"#, reply = #"{"agent": "reply", "text": "Done."}"#
        let compact = #""agent": "compact", "summary": "Where it was.""#
        XCTAssertTrue(problem("\(prompt)\n{\"agent\": \"compact\"}\n\(reply)").contains("demo.jsonl:2: a compact needs the summary"))
        XCTAssertTrue(problem("\(prompt)\n{\(compact), \"say\": \"Full!\"}\n\(reply)").contains("a compact says nothing"))
        XCTAssertTrue(problem("\(prompt)\n{\(compact), \"by\": \"reviewer\"}\n\(reply)").contains("a compact is the main thread's"))
        XCTAssertTrue(problem("\(prompt)\n{\"agent\": \"compact\", \"summary\": 3}\n\(reply)").contains("summary is a string"))
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
        try XCTAssertEqual(cause(#"{"you": "back", "minutes": 600}"#), .init(kind: "back", text: "You come back to the Mac after a very long break"))
        try XCTAssertEqual(cause(#"{"you": "back", "minutes": 20}"#), .init(kind: "back", text: "You come back to the Mac after a long break"))
        try XCTAssertEqual(cause(#"{"agent": "prompt", "text": "Fix it"}"#), .init(kind: "prompt", text: "You ask Claude: “Fix it”"))
        try XCTAssertEqual(cause(#"{"agent": "read", "file": "a.js"}"#, agent: "codex"), .init(kind: "tool", text: "Codex reads a.js"))
        try XCTAssertEqual(cause(#"{"agent": "run", "cmd": "npm test", "about": "Run the tests", "fails": true}"#),
                           .init(kind: "tool_failed", text: "Claude: run the tests, and it fails"))
        try XCTAssertEqual(cause(#"{"agent": "run", "cmd": "npm run setup", "about": "Install the runner", "ask": 3}"#),
                           .init(kind: "needs_you", text: "Claude asks to install the runner, and you allow it"))
        try XCTAssertEqual(cause(#"{"agent": "review", "task": "Review the diff"}"#), .init(kind: "tool", text: "Claude sends a reviewer: Review the diff"))
        try XCTAssertEqual(DemoScript("{\"agent\": \"prompt\", \"text\": \"Go\"}\n{\"agent\": \"compact\", \"summary\": \"S\"}\n{\"agent\": \"reply\", \"text\": \"Done.\"}")
            .steps[1].cause(creature: "Pip", agent: "codex"), .init(kind: "compact", text: "Codex's context is full: it compacts the conversation"))
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
            #"{"t":"do","id":6,"name":"listening"}"#,
            #"{"t":"do","id":7,"name":"starting"}"#,
            #"{"t":"do","id":8,"name":"starting","args":{"ctx":"compacted"}}"#,
            #"{"t":"do","id":9,"name":"wake_up","args":{"mood":"happy"}}"#,
        ] { recorder.sent(message) }
        XCTAssertEqual(recorder.recording(character: "pixel", face: "pixel").events.map(\.effect), [
            nil, nil, "Pip makes an excited face and says “Go”", "Pip makes a curious face",
            "Pip shows that it needs you", "Pip's mood is now proud", "Pip celebrates", "Pip slumps", "Pip listens", nil,
            "Pip shows that the context was compacted",
            "Pip stretches and yawns",
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

    /// characters/DEMOS.md: a header's `start` is when the demo's clock
    /// starts, on this Mac's clock; an agent step's `session` is another
    /// of its threads; a reply that `fails` is a failed turn, and only a
    /// run or a reply fails.
    func testAStartSessionsAndAFailedTurn() throws {
        let script = try DemoScript("""
            {"demo": 1, "title": "Two at once", "start": "2026-10-31T09:00"}
            {"agent": "prompt", "text": "Go"}
            {"agent": "prompt", "text": "And you", "session": "docs"}
            {"agent": "reply", "text": "Oops", "fails": true}
            """)
        let local = DateComponents(calendar: Calendar.current, year: 2026, month: 10, day: 31, hour: 9).date!
        XCTAssertEqual(script.start, Int64(local.timeIntervalSince1970 * 1000))
        guard case .agent(let second) = script.steps[1].what, case .agent(let reply) = script.steps[2].what else {
            XCTFail("agent steps")
            return
        }
        XCTAssertEqual(second.session, "docs")
        XCTAssertTrue(reply.fails)
        XCTAssertEqual(script.steps[2].cause(creature: "Pip", agent: "claude")?.text, "Claude's turn fails")
        try XCTAssertThrowsError(try DemoScript(#"{"agent": "read", "file": "a", "fails": true}"#)) { error in
            XCTAssertTrue("\(error)".contains("only a run or a reply fails"))
        }
        try XCTAssertThrowsError(try DemoScript(#"{"demo": 1, "start": "soon"}"#)) { error in
            XCTAssertTrue("\(error)".contains("start is a date and time"))
        }
    }
}
