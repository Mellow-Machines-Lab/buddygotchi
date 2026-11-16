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

    /// Off, `say` offers no swear, at any talk; on, as before.
    func testOffTheBrainIsNeverOfferedASwear() {
        let asked = MomentOutput.asked(in: .active)
        func says(_ swears: Bool, _ talk: Talk) -> [String] {
            MomentOutput.speech(asked, hushed: false, talk: talk, swears: swears, in: .active)
                .first { $0.key == MomentOutput.sayKey }?.options.map(\.name) ?? []
        }
        for talk in Talk.allCases {
            XCTAssertFalse(says(false, talk).contains("swear"), "\(talk)")
        }
        XCTAssertTrue(says(true, .normal).contains("swear"))
        XCTAssertTrue(says(true, .chatty).contains("swear"))
        XCTAssertEqual(says(false, .normal), says(true, .normal).filter { $0 != "swear" }, "only the swear goes")
        // The default, as the evals and every caller that doesn't say, swears.
        XCTAssertEqual(MomentOutput.speech(asked, hushed: false, talk: .normal, in: .active).first { $0.key == MomentOutput.sayKey }?.options.map(\.name),
                       says(true, .normal))
    }

    /// Off, even a swear answered plays no swear take: the upset feeling
    /// in a plainer kind. On, a failed turn's swear is a swear.
    func testOffNoSwearTakePlays() throws {
        try requireVoice()
        for swears in [false, true] {
            var queued: [Moment] = []
            let react = MomentOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, swears: { swears })
            let asked = react.questions(now: nil, log: Self.log).first { $0.key == MomentOutput.sayKey }?.options.map(\.name) ?? []
            XCTAssertEqual(asked.contains("swear"), swears)
            _ = react.run(["react.face": a("grumpy"), "react.move": a("failure"), "say": a("swear")], now: nil, log: Self.log)
            let kind = queued.last?.say?.takes.first?.kind
            if swears {
                XCTAssertEqual(kind, .swear)
            } else {
                XCTAssertNotNil(kind, "it still says how it feels")
                XCTAssertNotEqual(kind, .swear)
            }
        }
    }
}
