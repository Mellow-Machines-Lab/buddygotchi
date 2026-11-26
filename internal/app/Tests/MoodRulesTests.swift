import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// What code does to the mood, never Jev (`Runtime.moodRules`): a mood
/// fades on the clock by its pack's `fade`, and cross's level is counted
/// from what provokes it. Each is a change of the mood in the transcript,
/// by `rule`. Boop's pack: its numbers are pinned here.
final class MoodRulesTests: XCTestCase {
    private let minute: Int64 = 60_000

    private func rig() throws -> (rig: CoreRig, harness: Harness, mood: Choice) {
        try requirePack("boop")
        let rig = CoreRig()
        let (harness, mood) = Runtime.harness(pipeline: rig.pipeline, steering: RuntimeTests.steering, queue: { _, _ in })
        rig.wait(1000)  // the pipeline's clock is its inputs': one, so a change is logged at the rig's time
        return (rig, harness, mood)
    }

    private func changes(_ harness: Harness) -> [Event] {
        harness.log.events.filter { $0.kind == Event.did && $0.action == MoodOutput.outputName }
    }

    /// character.json's fades, long enough to be seen when you look up:
    /// happy settles into calm after 30 minutes, sad after 20, proud into
    /// happy after 15; calm never fades. The fade is the mood's change in
    /// the transcript, by `rule`, for no event.
    func testAMoodFadesByTheClock() throws {
        let (rig, harness, mood) = try rig()
        func now() -> String { MoodOutput.value(mood, harness.log.view(now: rig.now)) }
        func set(_ to: String) { harness.force(mood, by: Runtime.forcedBy) { MoodOutput.change(mood, to: to, log: harness.log.view(now: rig.now)) } }
        rig.wait(3 * 60 * minute, every: minute)
        XCTAssertEqual(changes(harness).count, 0, "calm never fades")
        set("happy")
        rig.wait(30 * minute - 1000)
        XCTAssertEqual(now(), "happy", "not before its 30 minutes")
        rig.wait(1000)
        XCTAssertEqual(now(), "calm")
        let fade = try XCTUnwrap(changes(harness).last)
        XCTAssertEqual(fade["message"]?.string, "\(creature)'s mood settled: happy → calm.")
        XCTAssertEqual(fade["by"]?.string, "rule")
        XCTAssertEqual(fade[MoodOutput.fadeFact], true)
        XCTAssertNil(fade.about, "for no event")
        XCTAssertEqual(MoodOutput.reason(mood, harness.log.view(now: rig.now), line: { _ in nil })?.cause, "It settled by itself after a while.")

        set("proud")
        rig.wait(15 * minute)
        XCTAssertEqual(now(), "happy", "proud is shorter: into happy after 15 minutes")
        rig.wait(30 * minute)
        XCTAssertEqual(now(), "calm", "and happy into calm after its own 30")

        set("sad")
        rig.wait(20 * minute - 1000)
        XCTAssertEqual(now(), "sad")
        rig.wait(1000)
        XCTAssertEqual(now(), "calm")
    }

    /// Focused lasts while an agent works: its 3 minutes count from the
    /// turn's end. Lonely lasts while you're away: its 20 minutes count
    /// from your coming back.
    func testAFadeWaitsForWhatHoldsIt() throws {
        let (rig, harness, mood) = try rig()
        func now() -> String { MoodOutput.value(mood, harness.log.view(now: rig.now)) }
        func set(_ to: String) { harness.force(mood, by: Runtime.forcedBy) { MoodOutput.change(mood, to: to, log: harness.log.view(now: rig.now)) } }
        rig.send(.turnStart)
        set("focused")
        rig.wait(40 * minute, every: 30_000)
        XCTAssertEqual(now(), "focused", "while the turn works")
        rig.send(.turnEnd)
        rig.wait(3 * minute - 1000)
        XCTAssertEqual(now(), "focused", "3 minutes from the turn's end")
        rig.wait(1000)
        XCTAssertEqual(now(), "calm")

        rig.pipeline.presence(PresenceDetector.awayEvent(why: "locked", since: rig.now, at: rig.now))
        set("lonely")
        rig.wait(5 * 60 * minute, every: minute)
        XCTAssertEqual(now(), "lonely", "while you're away")
        rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .end, specificType: "input"))
        rig.wait(20 * minute - 1000)
        XCTAssertEqual(now(), "lonely", "20 minutes from your coming back")
        rig.wait(1000)
        XCTAssertEqual(now(), "calm")
    }

    /// Cross has three levels, which code counts and Jev never picks: its
    /// face is annoyed, then grumpy, then angry. In it, a poke in a row, a
    /// shake, a failed check or a failed turn takes it a level up; a stroke
    /// takes it one down; and it cools a level every 6 minutes, then to calm.
    func testCrossIsCountedALevelAtATime() throws {
        let (rig, harness, mood) = try rig()
        func log() -> LogView { harness.log.view(now: rig.now) }
        func face() -> String { MoodOutput.face(mood, log()) }
        func set(_ to: String) { harness.force(mood, by: Runtime.forcedBy) { MoodOutput.change(mood, to: to, log: log()) } }
        set("cross")
        XCTAssertEqual(MoodOutput.level(mood, log()), 1)
        XCTAssertEqual(face(), "annoyed")
        XCTAssertEqual(MoodOutput.levelLine(mood, log(), pack: .active),
                       "Right now \(creature) is annoyed: cross, level 1 of 3. The app counts the level.")
        rig.poke()
        XCTAssertEqual(face(), "annoyed", "one poke provokes nothing")
        rig.wait(1000)
        rig.poke()
        XCTAssertEqual(face(), "grumpy", "the second in a row")
        let up = try XCTUnwrap(changes(harness).last)
        XCTAssertEqual(up["message"]?.string, "\(creature) is more cross: grumpy now.")
        XCTAssertEqual([up["from"]?.string, up["to"]?.string, up["by"]?.string], ["cross", "cross", "rule"])
        XCTAssertEqual(up["level"]?.int, 2)
        XCTAssertNotNil(up.about, "for the poke that did it")
        XCTAssertEqual(MoodOutput.value(mood, log()), "cross", "the mood is the same")
        rig.wait(1000)
        rig.poke()
        XCTAssertEqual(face(), "angry")
        rig.wait(1000)
        rig.poke()
        XCTAssertEqual(face(), "angry", "never past its last face")

        rig.gesture("stroke")
        XCTAssertEqual(face(), "grumpy", "a stroke soothes it a level")
        XCTAssertEqual(changes(harness).last?["message"]?.string, "\(creature) is less cross: grumpy now.")
        rig.gesture("shake")
        XCTAssertEqual(face(), "angry", "a shake provokes it")

        // It cools a level every 6 minutes since its last change, then to calm.
        rig.wait(6 * minute - 1000)
        XCTAssertEqual(face(), "angry")
        rig.wait(1000)
        XCTAssertEqual(face(), "grumpy")
        XCTAssertEqual(changes(harness).last?[MoodOutput.fadeFact], true)
        XCTAssertEqual(MoodOutput.sinceLine(mood, log(), at: rig.now), "\(creature) has been cross for 6 min.", "since it turned cross, whatever its level")
        rig.wait(6 * minute)
        XCTAssertEqual(face(), "annoyed")
        rig.wait(6 * minute)
        XCTAssertEqual(MoodOutput.value(mood, log()), "calm")
        XCTAssertEqual(changes(harness).last?["message"]?.string, "\(creature)'s mood settled: cross → calm.")

        // A failed check and a failed turn provoke it too; at annoyed, a
        // stroke leaves the level be: only Jev or the fade ends it.
        set("cross")
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests", failed: true)
        XCTAssertEqual(face(), "grumpy", "a failed check")
        rig.send(.turnFailed)
        XCTAssertEqual(face(), "angry", "a failed turn")
        rig.gesture("stroke")
        rig.gesture("swipe")
        rig.gesture("stroke")
        XCTAssertEqual(face(), "annoyed")
        XCTAssertEqual(MoodOutput.value(mood, log()), "cross")
    }

    /// Jev turning it cross at something that provokes it starts it as cross
    /// as that was: the third poke in a row, at grumpy. Rude words, as its
    /// reply says they were, take it a level up.
    func testCrossStartsAsCrossAsWhatCausedIt() throws {
        let (rig, harness, mood) = try rig()
        func log() -> LogView { harness.log.view(now: rig.now) }
        var poke: Event?
        for _ in 0..<3 {
            poke = rig.pipeline.poke(at: rig.now).recorded.first { $0.type == .poke }
            rig.wait(1000)
        }
        XCTAssertEqual(MoodOutput.level(mood, log()), 1, "calm has no level")
        harness.emit(Event.did("\(creature)'s mood changed: calm → cross.", for: poke?.seq, action: mood.name, by: "brain",
                               facts: ["from": "calm", "to": "cross"]))
        XCTAssertEqual(MoodOutput.face(mood, log()), "grumpy")
        harness.emit(Event.did("", for: nil, action: MomentOutput.outputName, by: "brain", facts: ["reply": .string(MomentOutput.rudeReply)]))
        XCTAssertEqual(MoodOutput.face(mood, log()), "angry", "rude words")
    }

    /// The count each thing that provokes it carries, and the level it
    /// makes: pokes from the second in a row, shakes from the first, a
    /// check failing in a row, a failed turn.
    func testWhatProvokesAndHowMuch() {
        let poke = Event(at: 0, source: .device, type: .poke, specificType: "input")
        let shake = Event(at: 0, source: .device, type: .gesture, specificType: "shake")
        let check = Event(at: 0, source: .claude, type: .tool, phase: .end, specificType: "PostToolUseFailure")
        let failed = Event(at: 0, source: .claude, type: .turn, phase: .end, specificType: "StopFailure")
        XCTAssertNil(MoodOutput.provocation(poke, facts: ["in_a_row": 1]))
        XCTAssertEqual([2, 3, 4, 9].map { MoodOutput.provocation(poke, facts: ["in_a_row": .int($0)]) }, [1, 2, 3, 8])
        XCTAssertEqual([1, 2, 3].map { MoodOutput.provocation(shake, facts: ["in_a_row": .int($0)]) }, [1, 2, 3])
        XCTAssertEqual(MoodOutput.provocation(check, facts: ["result": "failed", "topic": "tests", "failed_before": 2]), 3)
        XCTAssertNil(MoodOutput.provocation(check, facts: ["result": "ok", "topic": "tests", "failed_before": 2]), "a pass")
        XCTAssertNil(MoodOutput.provocation(check, facts: ["result": "failed", "topic": "docs"]), "not a check")
        XCTAssertEqual(MoodOutput.provocation(failed, facts: ["outcome": "failed"]), 1)
        XCTAssertNil(MoodOutput.provocation(failed, facts: ["outcome": "done"]))
        // Entering: the count itself. In it: a level up, or the count if more.
        XCTAssertEqual([1, 2, 3, 8].map { MoodOutput.provoked(nil, by: $0, of: 3) }, [1, 2, 3, 3])
        XCTAssertEqual([1, 2, 3].map { MoodOutput.provoked($0, by: 1, of: 3) }, [2, 3, 3])
        XCTAssertEqual(MoodOutput.provoked(1, by: 3, of: 3), 3)
        XCTAssertEqual([1, 2, 3].map(MoodOutput.soothed), [1, 1, 2])
        XCTAssertEqual(Touch.allCases.filter(\.soothes), [.stroke, .hold, .swipe])
    }
}
