import Foundation
import XCTest
@testable import BoopKit

/// Boop's energy (`Energy`, documentation/design/screen-guide.md, "Energy"):
/// one plain rule on the Mac, sent as the `state`'s `energy`, which the
/// popover says in words.
final class EnergyTests: XCTestCase {
    /// Pins the rule: bright for an hour after the first showing up of a
    /// Boop day, tired at night or after 15 minutes' working stretch, else
    /// normal, which sends nothing.
    func testTheDial() {
        XCTAssertEqual(Core.brightForMs, 3_600_000)
        XCTAssertEqual(Core.tiredAfterWorkMs, 900_000)
        let rig = CoreRig()
        func hour() -> Int {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            return utc.component(.hour, from: Date(timeIntervalSince1970: Double(rig.core.wall(rig.now)) / 1000))
        }
        let start = hour()
        XCTAssertTrue((11..<16).contains(start), "the rig starts in the day: \(start)")
        XCTAssertNil(rig.state.energy, "no showing up yet: normal")
        rig.poke()
        XCTAssertEqual(rig.state.energy, "bright", "the day's first showing up")
        XCTAssertTrue(rig.state.jsonLine.contains(#""energy":"bright""#))
        rig.wait(59 * 60_000, every: 60_000)
        XCTAssertEqual(rig.state.energy, "bright")
        rig.wait(2 * 60_000, every: 60_000)
        XCTAssertNil(rig.state.energy, "an hour on")
        rig.poke()
        XCTAssertNil(rig.state.energy, "only the first of the day")
        rig.send(.turnStart)
        rig.wait(14 * 60_000, every: 60_000)
        XCTAssertNil(rig.state.energy)
        rig.wait(2 * 60_000, every: 60_000)
        XCTAssertEqual(rig.state.energy, "tired", "a long stretch of work")
        rig.send(.turnEnd)
        XCTAssertNil(rig.state.energy, "rested")
        let hoursToNight = Int64((22 - hour() + 24) % 24)
        rig.wait(hoursToNight * 3_600_000, every: 600_000)
        XCTAssertEqual(rig.state.energy, "tired", "night")
    }

    func testThePopoversWords() {
        XCTAssertEqual(Narration.energy("tired", name: "Boop"), "Boop's getting sleepy.")
        XCTAssertEqual(Narration.energy("bright", name: "Mochi"), "Mochi's wide awake.")
        XCTAssertNil(Narration.energy(nil, name: "Boop"))
    }
}
