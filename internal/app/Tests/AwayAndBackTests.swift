import MellowHarness
import XCTest
@testable import BoopKit

/// Away and back, paired once for the transcript view and the memory
/// reader both (`AwayAndBack`).
final class AwayAndBackTests: XCTestCase {
    func presence(_ phase: Event.Phase, at: Int64, since: Int64? = nil) -> Event {
        Event(at: at, source: .mac, type: .presence, phase: phase, specificType: "locked",
              data: since.map { ["since": .int($0)] } ?? [:])
    }

    /// An away begins when the detector says it did (`since`), else at its
    /// event; a back ends it, after the time since; a back with no away
    /// ends the one the detector saved, or none; any other event is no step.
    func testAwayAndBackPair() {
        var pair = AwayAndBack()
        XCTAssertEqual(pair.fold(presence(.start, at: 10_000, since: 4_000)), .away(since: 4_000))
        XCTAssertEqual(pair.since, 4_000)
        XCTAssertEqual(pair.fold(presence(.end, at: 64_000)), .back(ms: 60_000))
        XCTAssertNil(pair.since)
        XCTAssertEqual(pair.fold(presence(.start, at: 70_000)), .away(since: 70_000))
        var relaunched = AwayAndBack()
        XCTAssertEqual(relaunched.fold(presence(.end, at: 100_000, since: 40_000)), .back(ms: 60_000))
        XCTAssertEqual(relaunched.fold(presence(.end, at: 120_000)), .back(ms: nil))
        XCTAssertNil(relaunched.fold(Event(at: 1, source: .device, type: .poke, specificType: "input")))
    }
}
