import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

private let t0: Int64 = 1_790_000_000_000
private let minute: Int64 = 60_000

/// Every lock and unlock of the Mac: the detector makes the events, the view
/// their lines, and Jev picks a wave, a snub or the nap.
final class LockTests: XCTestCase {
    static func a(_ choice: String) -> Answer { Answer(choice: choice, probabilities: [choice: 1]) }

    /// Every lock and unlock is an event, once however many of the Mac's
    /// notifications say so, and a lock too short to be an away is one too.
    func testEveryLockAndUnlockIsAnEventOnce() {
        var d = PresenceDetector()
        XCTAssertEqual(d.signal(.locked, at: t0).map(\.kind), ["lock_start"])
        XCTAssertEqual(d.signal(.locked, at: t0 + 1), [], "a fast-user-switch's notification says so again")
        let unlock = d.signal(.unlocked, at: t0 + minute)
        XCTAssertEqual(unlock.map(\.kind), ["lock_end"])
        XCTAssertEqual(unlock.first?["since"]?.int, t0)
        XCTAssertEqual(d.signal(.unlocked, at: t0 + minute + 1), [])
        XCTAssertFalse(d.away)
    }

    /// The away's 10 minutes are unchanged by the lock's events: an unlock
    /// past them with no tick seen makes the away first, then the unlock.
    func testALongLockStaysAnAwayAfterTenMinutes() {
        XCTAssertEqual(PresenceDetector.Config().lockAwayMs, 10 * minute)
        var d = PresenceDetector()
        _ = d.signal(.locked, at: t0)
        XCTAssertEqual(d.signal(.unlocked, at: t0 + 10 * minute - 1).map(\.kind), ["lock_end"])
        _ = d.signal(.locked, at: t0 + 20 * minute)
        XCTAssertEqual(d.signal(.unlocked, at: t0 + 30 * minute).map(\.kind), ["presence_start", "lock_end"])
    }

    /// The lines give facts only: a lock says how long since the last, in
    /// minutes under an hour (`lockWhileMs`), and an unlock how long it was
    /// locked.
    func testTheLinesSayHowLong() {
        XCTAssertEqual(EventLine.lockWhileMs, 60 * minute)
        XCTAssertEqual(EventLine.locked(sinceLastMs: nil), "You locked the Mac, first time in a while.")
        XCTAssertEqual(EventLine.locked(sinceLastMs: 3 * 60 * minute), "You locked the Mac, first time in 3 h.")
        XCTAssertEqual(EventLine.locked(sinceLastMs: 60 * minute), "You locked the Mac, first time in 1 h.")
        XCTAssertEqual(EventLine.locked(sinceLastMs: 59 * minute), "You locked the Mac again, 59 min after the last time.")
        XCTAssertEqual(EventLine.locked(sinceLastMs: 1000), "You locked the Mac again, under a minute after the last time.")
        XCTAssertEqual(EventLine.unlocked(afterMs: 2 * minute), "You unlocked the Mac after 2 min.")
    }

    /// Each short lock and unlock wakes a pass. One reaction at a long
    /// unlock: the unlock ending an away has no line, so no pass, and the
    /// back is the only one.
    func testALongUnlockIsOneReaction() throws {
        let rig = CoreRig()
        func lock(_ e: Event) -> [ViewEvent] { events(rig.note(Fx(rig.pipeline.lock(e)))) }
        let first = try XCTUnwrap(lock(PresenceDetector.lockEvent(at: rig.now)).first)
        XCTAssertEqual(first.line, "You locked the Mac, first time in a while.")
        XCTAssertEqual(first.name, "lock start")
        let locked = rig.now
        rig.now += 2 * minute
        let short = try XCTUnwrap(lock(PresenceDetector.unlockEvent(since: locked, at: rig.now)).first)
        XCTAssertEqual(short.line, "You unlocked the Mac after 2 min.")

        rig.now += 3 * minute
        let again = rig.now
        XCTAssertEqual(lock(PresenceDetector.lockEvent(at: again)).first?.line, "You locked the Mac again, 5 min after the last time.")
        rig.now += 3 * 60 * minute
        rig.note(Fx(rig.pipeline.presence(PresenceDetector.awayEvent(why: "locked", since: again, at: again + 10 * minute))))
        XCTAssertEqual(lock(PresenceDetector.unlockEvent(since: again, at: rig.now)), [], "the unlock ending an away has no line of its own")
        rig.now += 1000
        let back = events(rig.note(Fx(rig.pipeline.presence(PresenceDetector.backEvent(why: "unlocked", at: rig.now)))))
        XCTAssertEqual(back.map(\.line), ["You came back to the Mac after 3 hours away."])
        XCTAssertTrue(back[0].wakesBrain)
    }

    /// The narration's two rows, and the board's words for them fit a sign.
    func testTheNarration() {
        let lock = Narration.of(PresenceDetector.lockEvent(at: t0), line: nil), unlock = Narration.of(PresenceDetector.unlockEvent(since: t0, at: t0 + 1), line: nil)
        XCTAssertEqual(lock?.cause, "You locked the Mac.")
        XCTAssertEqual(unlock?.cause, "You unlocked the Mac.")
        XCTAssertEqual(lock?.fact, "you locked the Mac")
        XCTAssertEqual(unlock?.fact, "you unlocked it")
    }

    let lines = [TaggedLine(tags: ["bye"], text: "see ya!"), TaggedLine(tags: ["bye", "night"], text: "nite nite"), TaggedLine(tags: ["bye", "working"], text: "i got this"),
                 TaggedLine(tags: ["hello"], text: "oh, hi!")]

    /// A lock's or unlock's questions: always a face, a wave or none, the
    /// nap only at night with no agent working, and the lines for it.
    func testALockIsAskedForAWave() {
        var tags = ["day"], moment: [String] = []
        let react = MomentOutput(queue: { _, _ in }, blocked: { nil }, calendar: { _ in tags }, replies: lines, moment: { _ in moment })
        let log = Transcript.log().view(now: t0)
        func options(_ e: Event, _ key: String) -> [String] {
            react.questions(now: e, log: log).first { $0.key == key }?.options.map(\.name) ?? []
        }
        let lock = PresenceDetector.lockEvent(at: t0), unlock = PresenceDetector.unlockEvent(since: t0, at: t0 + 1)
        XCTAssertFalse(options(lock, MomentOutput.emotionKey).contains("none"), "it always reacts")
        XCTAssertEqual(options(lock, MomentOutput.moveKey), ["none", "wave"])
        XCTAssertEqual(options(lock, Signs.questionKey), ["none", "see ya!"])
        XCTAssertEqual(options(unlock, MomentOutput.moveKey), ["none", "wave"])
        XCTAssertEqual(options(unlock, Signs.questionKey), ["none", "oh, hi!"])
        tags = ["night"]
        XCTAssertEqual(options(lock, MomentOutput.moveKey), ["none", "wave", "nap"])
        XCTAssertEqual(Set(options(lock, Signs.questionKey)), ["none", "see ya!", "nite nite"])
        XCTAssertEqual(options(unlock, MomentOutput.moveKey), ["none", "wave"], "an unlock never naps")
        moment = ["working"]
        XCTAssertEqual(options(lock, MomentOutput.moveKey), ["none", "wave"], "Boop keeps watching")
        XCTAssertEqual(options(lock, Signs.questionKey), ["none", "i got this"])
    }

    /// A small wave is the slighter motion, a bigger one the real `bye` or
    /// `hello`; none holds up nothing; the nap sleeps.
    func testTheWaveIsAsBigAsTheMoment() throws {
        var queued: [Moment] = [], napped: [Int64] = []
        let react = MomentOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, calendar: { _ in ["night"] }, replies: lines,
                                 nap: { napped.append($0) })
        let log = Transcript.log().view(now: t0)
        let lock = PresenceDetector.lockEvent(at: t0), unlock = PresenceDetector.unlockEvent(since: t0, at: t0 + 1)
        func run(_ answers: [String: String], _ e: Event) -> String? {
            react.run(answers.mapValues { Self.a($0) }, now: e, log: log)?.message
        }
        let slight = try XCTUnwrap(run(["react.face": "calm", "react.move": "wave", "react.intensity": "small"], lock))
        XCTAssertEqual(queued.last?.reply, "wave")
        XCTAssertEqual(queued.last?.say?.takes, [], "no say, silent")
        XCTAssertNil(queued.last?.sign)
        XCTAssertTrue(slight.contains(", waving"), slight)

        _ = run(["react.face": "happy", "react.move": "wave", "react.intensity": "medium", Signs.questionKey: "see ya!", "say": "glad"], lock)
        XCTAssertEqual(queued.last?.reply, "bye")
        XCTAssertEqual(queued.last?.sign, "see ya!")
        _ = run(["react.face": "happy", "react.move": "wave", "react.intensity": "medium"], unlock)
        XCTAssertEqual(queued.last?.reply, "hello")
        _ = run(["react.face": "happy", "react.move": "wave", "react.intensity": "small"], unlock)
        XCTAssertEqual(queued.last?.reply, "wave")

        _ = run(["react.face": "grumpy", "react.move": "none", Signs.questionKey: "see ya!"], lock)
        XCTAssertNil(queued.last?.reply, "a snub: no wave")
        XCTAssertNil(queued.last?.sign, "and no sign")
        XCTAssertEqual(napped, [])

        _ = run(["react.face": "happy", "react.move": "nap", "react.intensity": "small", Signs.questionKey: "nite nite"], lock)
        XCTAssertEqual(queued.last?.reply, "nap", "the nap is the nap at any size")
        XCTAssertEqual(queued.last?.sign, "nite nite")
        XCTAssertEqual(napped, [t0])
        XCTAssertEqual(MomentOutput.move(["react.move": Self.a("wave")]), "wave")
    }

    /// The nap sleeps at once with an agent's session open; work or a request
    /// shows over it; and you showing up ends it.
    func testTheNapSleepsUntilYouShowUp() {
        let rig = CoreRig()
        let doing = { rig.core.snapshot(at: rig.now).doing }
        rig.note(Fx(rig.pipeline.agent(Event(at: rig.now, source: .claude, type: .session, phase: .start, specificType: "SessionStart", session: "s", data: ["agent": "claude"]))))
        XCTAssertEqual(doing(), "idle")
        rig.core.nap(at: rig.now)
        XCTAssertEqual(doing(), "asleep")
        rig.now += 1000
        rig.pipeline.poke(at: rig.now)
        XCTAssertEqual(doing(), "idle", "a touch wakes it")
        rig.core.nap(at: rig.now)
        rig.pipeline.lock(PresenceDetector.unlockEvent(since: rig.now, at: rig.now))
        XCTAssertEqual(doing(), "idle", "an unlock wakes it")
        rig.core.nap(at: rig.now)
        rig.pipeline.presence(PresenceDetector.backEvent(why: "input", at: rig.now))
        XCTAssertEqual(doing(), "idle", "and so does your coming back")
        rig.core.nap(at: rig.now)
        XCTAssertTrue(rig.pipeline.asleepAndIdle(at: rig.now), "the dream follows by itself")
        rig.pipeline.said("hey", by: .device, at: rig.now)
        XCTAssertEqual(doing(), "idle", "and your words")
        // BOOT with someone in the line is you showing up too: once they're
        // answered it stays awake, not back to its nap.
        rig.send(.needsYou, tool: "Bash")
        rig.core.nap(at: rig.now)
        XCTAssertFalse(rig.core.line(at: rig.now).isEmpty)
        rig.pipeline.press(at: rig.now)
        XCTAssertFalse(rig.core.napping, "and BOOT")
    }
}
