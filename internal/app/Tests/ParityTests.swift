import AgentHooks
import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// What Boop did before its brain moved onto MellowHarness (main at 4bea7b21)
/// and still does: a reaction your tap cut short held however long the
/// pokes go on.
final class ParityTests: XCTestCase {
    static let steering = try! Steering(directory: CharacterPack.active.directory.appendingPathComponent("steering"))

    /// A reaction your tap cut short stays in progress while the pokes go
    /// on, however long, as main's view held it:
    /// past react's 90 s `openFor` a run of pokes neither drops it from
    /// HISTORY nor lets the next poke wake the brain again, and the pokes
    /// stopping for minutes with nothing else happening keeps it too.
    /// Anything else happening lets it go, and the ceiling ends a reaction
    /// no tap cut as before. On the app's own outputs (`Runtime.harness`),
    /// so it's react's `keepOpen` there that holds it.
    func testATapCutReactionOutlastsReactsOpenForWhileThePokesGoOn() {
        XCTAssertEqual(ReactAction.openForMs, 90_000)
        let rig = CoreRig()
        let (h, _) = Runtime.harness(pipeline: rig.pipeline, steering: Self.steering, personality: { .default }, queue: { _, _ in })
        func poke() -> Event {
            rig.poke()
            return h.log.events.last { $0.type == .poke }!
        }
        _ = poke()
        rig.now += 1000
        _ = poke()
        rig.now += 1000
        let third = poke()
        // The brain's reaction to the third poke in a row, as the harness logs it.
        let open = h.emit(Event.did("Boop made a grumpy face, held twice.", for: third.seq, action: ReactAction.actionName,
                                    by: "brain", open: true))
        rig.now += 1500
        _ = poke()  // the tap that cut it
        for _ in 0..<60 {
            rig.wait(2000)
            let p = poke()
            XCTAssertTrue(rig.view.pokesAnswered(p, h.log.view(now: rig.now)), "Boop is answering these pokes")
        }
        XCTAssertGreaterThan(rig.now - open.at, ReactAction.openForMs)
        XCTAssertTrue(h.log.openDids.contains(open.seq), "in progress past 90 s of pokes")
        XCTAssertEqual(h.log.view(now: rig.now).shown(open)?.inProgress, true)
        rig.wait(5 * 60_000)
        XCTAssertTrue(h.log.openDids.contains(open.seq), "the pokes stopped, and nothing else has happened")
        rig.send(.turnStart)
        XCTAssertFalse(TranscriptView.heldByPokes(open, h.log.view(now: rig.now)), "something else happened")
        rig.wait(1000)
        XCTAssertEqual(h.log.ended(open.seq)?["why"]?.string, Harness.noWord, "nothing ended it, so the ceiling does")

        let uncut = h.emit(Event.did("Boop made a happy face.", for: nil, action: ReactAction.actionName, by: "brain", open: true))
        rig.wait(ReactAction.openForMs - 1000)
        XCTAssertNil(h.log.ended(uncut.seq))
        rig.wait(1000)
        XCTAssertEqual(h.log.ended(uncut.seq)?["why"]?.string, Harness.noWord, "no poke came after it: 90 s, as before")
    }
}
