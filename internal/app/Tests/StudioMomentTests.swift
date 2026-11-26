import AgentHooks
import Foundation
import LinkKit
import MellowHarness
import XCTest

@testable import BoopKit

/// The Character Studio plays each of the pack's skits as the Mac would
/// send it (characters/studio/logic.js's `momentOf`). Both are pinned to
/// one file, characters/studio/tests/moments.json: here, what MomentOutput
/// sends for each skit; in the studio's tests, what the page sends.
final class StudioMomentTests: XCTestCase {
    /// Pins each skit's `do`, but its takes, to the studio's file: the
    /// finish names its thread and tier and a win its XP, a fix holds its
    /// sign low with its XP and its clip, you back is the wake-up, and each
    /// invite has the pack's word, the wait after the very first and care's
    /// XP. Every skit of the pack is in the file, and each Moment speaks.
    @MainActor func testTheStudiosMomentsAreTheMacs() throws {
        try requirePack("boop")
        let file = CharacterPackTests.repo.appendingPathComponent("characters/studio/tests/moments.json")
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let moments = try XCTUnwrap(fixture["moments"] as? [[String: Any]])
        XCTAssertEqual(Set(moments.compactMap { $0["skit"] as? String }), Set(CharacterPack.active.skits.map(\.id)), "every skit, once")

        var sent: [Moment] = []
        var facts: InviteTests.Facts = [:]
        var earned: (source: Growth.Source, xp: Int)?
        let react = MomentOutput(queue: { m, _ in sent.append(m) }, blocked: { nil },
                                 who: { $0?.type == .turn ? Moment.Who(agent: "claude", thread: "Studio") : nil },
                                 turnMs: { $0?.type == .turn ? 180_000 : nil },
                                 // The skit's own `do`, without Boop's line (`LinesTests`).
                                 signs: RuntimeTests.steering.signs.filter { $0.tags.first != "line" }, line: { _ in Line("", facts: facts) })
        react.earned = { _ in earned }
        // Not the very first invite, which waits longer, and care has room.
        var ledger = InviteLedger()
        ledger.asked = 1
        react.inviting = MomentOutput.Inviting(board: { true }, onCall: { false }, ledger: { ledger }, care: { Growth.careXP })
        let failed = Event(at: 1000, source: .claude, type: .turn, phase: .end, specificType: "StopFailure")
        let check = Event(at: 1000, source: .claude, type: .tool, phase: .end, specificType: "PostToolUse")
        let events: [String: (Event, InviteTests.Facts, (source: Growth.Source, xp: Int)?)] = [
            "win": (InviteTests.finish, InviteTests.won, (.turns, Growth.turnXP)),
            "upset": (failed, ["outcome": "failed", "length_ms": 180_000, "length": "long", "tools": 3], nil),
            "fix": (check, ["topic": "tests", "result": "ok", "failed_before": 2], (.fixes, Growth.fixXP)),
            "back": (RemarksTests.cameBack(), ["away_ms": 3_600_000], nil),
        ]
        for expected in moments {
            let skit = try XCTUnwrap(expected["skit"] as? String), mood = try XCTUnwrap(expected["mood"] as? String)
            let (event, f, xp) = try XCTUnwrap(events[skit], "an event for \(skit)")
            facts = f
            earned = xp
            sent = []
            react.run([MomentOutput.emotionKey: Answer(choice: mood, probabilities: [mood: 1])], now: event,
                      log: Transcript.log().view(now: event.at))
            let m = try XCTUnwrap(sent.last, skit)
            var args = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(m.args.json.utf8)) as? [String: Any])
            XCTAssertNotNil(args.removeValue(forKey: "say"), "\(skit) speaks")
            XCTAssertEqual(m.name, expected["name"] as? String, skit)
            let want = try XCTUnwrap(expected["args"] as? [String: Any])
            XCTAssertEqual(args as NSDictionary, want as NSDictionary, skit)
        }
    }
}
