import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

private let t0: Int64 = 1_790_000_000_000
private let minute: Int64 = 60_000

/// Every lock and unlock of the Mac: the detector makes the events, the view
/// their lines, and the rule picks a wave, a snub or the nap (`MomentRule.wave`).
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

    /// Each short lock and unlock has a line and no pass: the rules answer
    /// it. One reaction at a long unlock: the unlock ending an away has no
    /// line, so no wave, and the back is the only one, which wakes a pass.
    func testALongUnlockIsOneReaction() throws {
        let rig = CoreRig()
        func lock(_ e: Event) -> [ViewEvent] { events(rig.note(Fx(rig.pipeline.lock(e)))) }
        let first = try XCTUnwrap(lock(PresenceDetector.lockEvent(at: rig.now)).first)
        XCTAssertEqual(first.line, "You locked the Mac, first time in a while.")
        XCTAssertEqual(first.name, "lock start")
        XCTAssertFalse(first.wakesBrain, "the rules' own")
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

    /// Pins `MomentRule.wave`, the whole table: a snub when cross; good
    /// night and the nap at a night lock with no agent working; a real
    /// wave at the first lock or one an hour or more (`lockWhileMs`) after
    /// the last; a slight wave at any other lock, and at every unlock.
    func testTheWaveIsARule() {
        XCTAssertEqual(MomentRule.lockWhileMs, 60 * minute)
        func wave(lock: Bool = true, since: Int64? = nil, night: Bool = false, working: Bool = false, mood: String = "calm") -> MomentRule.Wave {
            MomentRule.wave(lock: lock, sinceLastMs: since, night: night, working: working, mood: mood)
        }
        XCTAssertEqual(wave(), .wave, "the first lock")
        XCTAssertEqual(wave(since: 60 * minute), .wave, "an hour on")
        XCTAssertEqual(wave(since: 60 * minute - 1), .slight, "within the hour")
        XCTAssertEqual(wave(lock: false), .slight, "an unlock is routine")
        XCTAssertEqual(wave(lock: false, night: true), .slight, "an unlock never naps")
        XCTAssertEqual(wave(since: minute, night: true), .nap, "a night lock naps, however soon after the last")
        XCTAssertEqual(wave(since: minute, night: true, working: true), .slight, "it keeps watching")
        XCTAssertEqual(wave(night: true, working: true), .wave)
        for mood in ["cross"] {
            XCTAssertEqual(wave(mood: mood), .snub)
            XCTAssertEqual(wave(lock: false, mood: mood), .snub)
            XCTAssertEqual(wave(night: true, mood: mood), .snub, "no nap in a huff")
        }
        XCTAssertEqual(wave(mood: "sad"), .wave, "only cross snubs")
    }

    /// The wave as it plays, with no pass: a slight one is the slighter
    /// motion in silence with no sign; a real one the `bye` with a word and
    /// one of the pack's bye lines for the moment; a snub the mood's face
    /// and nothing else; the nap a real wave, and it sleeps.
    func testTheWaveAsItPlays() throws {
        var queued: [Moment] = [], napped: [Int64] = []
        var tags = ["day"], moment: [String] = [], mood = "calm", sinceLast: Int64?
        let react = MomentOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, calendar: { _ in tags }, replies: lines,
                                 moment: { _ in moment }, nap: { napped.append($0) },
                                 moodFace: { _ in mood == "cross" ? "grumpy" : "calm" }, moodID: { _ in mood })
        let log = Transcript.log().view(now: t0)
        let lock = PresenceDetector.lockEvent(at: t0), unlock = PresenceDetector.unlockEvent(since: t0, at: t0 + 1)
        func play(_ e: Event) throws -> String {
            let facts: [String: JSONValue] = sinceLast.map { ["since_last_ms": .int($0)] } ?? [:]
            let ruled = try XCTUnwrap(react.ruled(e, facts: facts, log: log))
            return try XCTUnwrap(react.play(ruled, about: e, log: log)?.message)
        }
        let real = try play(lock)
        XCTAssertEqual(queued.last?.reply, "bye")
        XCTAssertEqual(queued.last?.sign, "see ya!")
        XCTAssertEqual(queued.last?.loops, 2, "medium")
        XCTAssertEqual(queued.last?.mood, "calm", "in the mood's own face")
        XCTAssertNil(queued.last?.anim, "no move but the wave")
        XCTAssertTrue(real.contains("moment (medium), waving, holding up a sign: \"see ya!\""), real)
        if !Take.all.isEmpty { XCTAssertEqual(queued.last?.say?.takes.isEmpty, false, "with a word") }

        sinceLast = 5 * minute
        let slight = try play(lock)
        XCTAssertEqual(queued.last?.reply, "wave")
        XCTAssertEqual(queued.last?.say?.takes, [], "in silence")
        XCTAssertNil(queued.last?.sign)
        XCTAssertEqual(queued.last?.loops, 1)
        XCTAssertTrue(slight.hasSuffix("(small), waving."), slight)
        _ = try play(unlock)
        XCTAssertEqual(queued.last?.reply, "wave", "an unlock's is slight")
        XCTAssertNil(queued.last?.sign)

        moment = ["working"]
        sinceLast = nil
        _ = try play(lock)
        XCTAssertEqual(queued.last?.sign, "i got this", "it keeps watching")
        XCTAssertEqual(napped, [])

        moment = []
        tags = ["night"]
        let night = try play(lock)
        XCTAssertEqual(queued.last?.reply, "bye", "good night is a real wave")
        XCTAssertTrue(["see ya!", "nite nite"].contains(queued.last?.sign ?? ""), "\(String(describing: queued.last?.sign))")
        XCTAssertEqual(napped, [t0], "and it sleeps")
        XCTAssertTrue(night.contains(", waving, and going to sleep"), night)

        mood = "cross"
        napped = []
        _ = try play(lock)
        XCTAssertNil(queued.last?.reply, "a snub: no wave")
        XCTAssertNil(queued.last?.sign, "and no sign")
        XCTAssertEqual(queued.last?.say?.takes, [], "nor a word")
        XCTAssertEqual(queued.last?.mood, "grumpy", "its cross face")
        XCTAssertEqual(napped, [], "nor the nap")
    }

    /// Through the pipeline, as the app runs: a lock plays its wave with
    /// no brain at all, recorded as the rule's, under the lock's line.
    func testALockPlaysWithNoBrain() throws {
        let rig = CoreRig()
        var queued: [Moment] = []
        let mind = Runtime.Mind(buddy: rig.pipeline.buddy, steering: RuntimeTests.steering, reactions: Reactions(),
                                queue: { r, p in queued.append(r); p.finish(.done) }, speaks: { false }, talk: { .normal })
        _ = Runtime.brain(rig.pipeline, mind)
        rig.pipeline.brain = false
        let step = rig.pipeline.lock(PresenceDetector.lockEvent(at: rig.now))
        XCTAssertEqual(queued.map(\.reply), ["bye"], "a first lock: a real wave")
        let did = try XCTUnwrap(step.recorded.first { $0.kind == Event.did && $0.action == MomentOutput.outputName })
        XCTAssertEqual(did["by"]?.string, "rule")
        XCTAssertEqual(step.views.map(\.wakesBrain), [false], "and no pass")
        rig.now += 2 * minute
        rig.pipeline.lock(PresenceDetector.unlockEvent(since: rig.now - 2 * minute, at: rig.now))
        XCTAssertEqual(queued.last?.reply, "wave", "the unlock: a slight one")
        // Something needs you: the screen is its, and nothing plays.
        rig.send(.needsYou, tool: "Bash")
        rig.now += minute
        rig.pipeline.lock(PresenceDetector.lockEvent(at: rig.now))
        XCTAssertEqual(queued.count, 2)
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
