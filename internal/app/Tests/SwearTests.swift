import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// The swear switch in Settings: off by default, and off, Boop never
/// swears. The evals keep it on, so their prompts stay as they were.
final class SwearTests: XCTestCase {
    static let log = Transcript.log().view(now: 0)
    func a(_ choice: String) -> Answer { Answer(choice: choice, probabilities: [choice: 0.9]) }

    func testSwearingIsOffUntilTurnedOn() throws {
        XCTAssertFalse(AppSettings().swearing)
        let off = try JSONEncoder().encode(AppSettings())
        XCTAssertFalse(String(decoding: off, as: UTF8.self).contains("swearing"), "off isn't written")
        let older = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(older.swearing, "older files: off")
        var on = AppSettings()
        on.swearing = true
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on))
        XCTAssertTrue(back.swearing)
    }

    /// Off, no skit swears, at any talk; on, the upset skit swears where
    /// its rule says (`Skits.play`). The brain is never asked.
    func testOffNoSkitSwears() {
        let piled: [String: JSONValue] = ["checks_failed": 2]
        XCTAssertEqual(Skits.play(slot: .failed, facts: piled, swears: false, in: CharacterPack.active.skits)?.swears, false)
        XCTAssertEqual(Skits.play(slot: .failed, facts: piled, swears: true, in: CharacterPack.active.skits)?.swears, true)
        XCTAssertFalse(MomentOutput(queue: { _, _ in }, blocked: { nil }).questions(now: nil, log: Self.log)
            .contains { $0.options.contains { $0.name == "swear" } })
    }

    /// Off, a failed turn whose checks piled up plays no swear take: the
    /// upset skit's plain words. On, a swear.
    func testOffNoSwearTakePlays() throws {
        try requireVoice()
        for swears in [false, true] {
            var queued: [Moment] = []
            // NOW is a failed turn, after two failed checks.
            let react = MomentOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, swears: { swears },
                                     line: { _ in Line("", facts: ["outcome": "failed", "length_ms": 0, "checks_failed": 2]) })
            let failed = Event(at: 0, source: .claude, type: .turn, phase: .end, specificType: "StopFailure")
            _ = react.run(["react.face": a("grumpy")], now: failed, log: Self.log)
            let kind = queued.last?.say?.takes.last?.kind
            if swears {
                XCTAssertEqual(kind, .swear)
            } else {
                XCTAssertNotNil(kind, "it still says how it feels")
                XCTAssertNotEqual(kind, .swear)
            }
        }
    }
}
