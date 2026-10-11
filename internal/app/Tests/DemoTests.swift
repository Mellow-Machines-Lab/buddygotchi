import AgentHooks
import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// Demos: the script a character pack carries, what each beat is called
/// for whoever watches, and the recording the simulator's page plays back.
final class DemoTests: XCTestCase {
    func testAScriptIsBeatsInOrder() throws {
        let script = try DemoScript("""
            // A comment, and a blank line.

            {"at": 9, "tap": true}
            {"at": 2, "agent": "claude", "hook": "UserPromptSubmit", "session": "demo", "prompt": "Add shortcuts", "answer": {"react.mood": "curious"}}
            {"at": 14, "talk": "how's it going?", "hold": 2, "answer": {"react.mood": "happy"}, "after": 2.5}
            {"at": 20, "mood": "proud", "note": "A good day"}
            {"at": 30, "advance": 300}
            """)
        XCTAssertEqual(script.beats.map(\.at), [2, 9, 14, 20, 30], "by time, however the file has them")
        guard case .hook(let line) = script.beats[0].what else { XCTFail("a hook"); return }
        XCTAssertEqual([line.agent, line.hook, line.session, line.prompt], ["claude", "UserPromptSubmit", "demo", "Add shortcuts"])
        XCTAssertEqual(script.beats[0].answer, ["react.mood": "curious"])
        XCTAssertEqual(script.beats[0].after, 0.3, "about as long as the brain takes")
        guard case .talk(let words, let hold) = script.beats[2].what else { XCTFail("talk"); return }
        XCTAssertEqual(words, "how's it going?")
        XCTAssertEqual(hold, 2)
        // Its last beat, and DemoScript.tail for what that starts to play out.
        XCTAssertEqual(script.length, 30 + 0.3 + 6)
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
        XCTAssertTrue(problem(#"{"tap": true}"#).contains("demo.jsonl:1: needs \"at\""))
        XCTAssertTrue(problem("{\"at\": 1, \"tap\": true}\n{\"at\": 2}").contains("demo.jsonl:2: nothing happens"))
        XCTAssertTrue(problem(#"{"at": 1, "hook": "Stop"}"#).contains("a hook needs agent, hook and session"))
        XCTAssertTrue(problem(#"{"at": 1, "tap": true, "answer": "happy"}"#).contains("answer is question keys to choices"))
    }

    /// Pins the words a watcher reads for each kind of beat.
    func testWhatABeatIsCalled() throws {
        func cause(_ json: String) throws -> DemoScript.Cause? { try DemoScript(json).beats[0].cause(creature: "Pip") }
        let hook = #""agent": "claude", "session": "demo""#
        try XCTAssertEqual(cause(#"{"at": 0, "tap": true}"#), .init(kind: "tap", text: "You poke Pip"))
        try XCTAssertEqual(cause(#"{"at": 0, "talk": "hello"}"#), .init(kind: "talk", text: "You say “hello”"))
        try XCTAssertEqual(cause("{\"at\": 0, \(hook), \"hook\": \"UserPromptSubmit\", \"prompt\": \"Fix it\"}"),
                       .init(kind: "prompt", text: "You ask Claude: “Fix it”"))
        try XCTAssertEqual(cause("{\"at\": 0, \(hook), \"hook\": \"PermissionRequest\"}"), .init(kind: "needs_you", text: "Claude needs your approval"))
        try XCTAssertEqual(cause("{\"at\": 0, \(hook), \"hook\": \"PostToolUse\", \"topic\": \"tests\"}"), .init(kind: "tool", text: "Claude ran the tests"))
        try XCTAssertEqual(cause("{\"at\": 0, \(hook), \"hook\": \"PostToolUseFailure\", \"topic\": \"deploy\"}"),
                       .init(kind: "tool_failed", text: "Claude's deploy failed"))
        try XCTAssertEqual(cause("{\"at\": 0, \"agent\": \"codex\", \"session\": \"d\", \"hook\": \"Stop\"}"), .init(kind: "done", text: "Codex finishes"))
        try XCTAssertEqual(cause("{\"at\": 0, \(hook), \"hook\": \"StopFailure\", \"error\": \"rate_limit\"}"),
                       .init(kind: "failed", text: "Claude's turn fails (rate limit)"))
        // Nothing a watcher would call something happening.
        try XCTAssertNil(cause("{\"at\": 0, \(hook), \"hook\": \"SessionStart\"}"))
        try XCTAssertNil(cause("{\"at\": 0, \(hook), \"hook\": \"PreToolUse\", \"tool\": \"Bash\"}"))
        try XCTAssertNil(cause("{\"at\": 0, \(hook), \"hook\": \"PostToolUse\", \"tool\": \"Read\"}"), "a routine call, about nothing")
        try XCTAssertNil(cause(#"{"at": 0, "advance": 60}"#))
        // A note says it in the script's words, and makes something of those.
        try XCTAssertEqual(cause("{\"at\": 0, \(hook), \"hook\": \"PreToolUse\", \"note\": \"You approve it\"}"), .init(kind: "note", text: "You approve it"))
        try XCTAssertEqual(cause(#"{"at": 0, "tap": true, "note": "A poke"}"#), .init(kind: "tap", text: "A poke"))
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

    /// The character pack's own demo plays in its own words: every answer
    /// is to a question the brain is asked, with a choice it's offered.
    func testThePacksDemoAnswersWhatTheBrainIsAsked() throws {
        try XCTSkipUnless(CharacterPack.active.demo != nil, "the pack \(CharacterPack.active.id) has no demo")
        let url = try XCTUnwrap(CharacterPack.active.demo)
        let script = try DemoScript(contentsOf: url)
        XCTAssertFalse(script.beats.isEmpty)
        var offered = Dictionary(uniqueKeysWithValues: ReactAction.asked.map { ($0.key, Set($0.options.map(\.name))) })
        offered["react.mood", default: []].formUnion(CharacterPack.active.moods.map(\.id))
        for beat in script.beats {
            for (key, choice) in beat.answer ?? [:] {
                XCTAssertTrue(offered[key]?.contains(choice) == true, "at \(beat.at) s: \(key) has no choice \(choice)")
            }
            if case .mood(let mood) = beat.what {
                XCTAssertTrue(CharacterPack.active.moods.contains { $0.id == mood }, "at \(beat.at) s: no mood \(mood)")
            }
        }
    }
}
