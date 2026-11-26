import AgentHooks
import Foundation
import LinkKit
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The invite: after a skit, Boop asks for one touch, and the touch pays
/// off (the pack's skit `invite`, `Moment.invite`, `InviteLedger`, the
/// board's `ev invite`).
final class InviteTests: XCTestCase {
    typealias Facts = [String: JSONValue]
    static let win = Skit(id: "win", slots: [.doneLong, .doneVeryLong], invite: .init(pose: .palm, touch: .tap, payoff: .highfive))
    static let upset = Skit(id: "upset", slots: [.failed, .failedVeryLong, .gaveUp, .checkFailing],
                            invite: .init(pose: .back, touch: .stroke, payoff: .sigh))
    static let back = Skit(id: "back", slots: [.back, .backDays, .backAfterADay], invite: .init(pose: .lean, touch: .stroke, payoff: .purr))
    nonisolated static let day: Int64 = 86_400_000

    // MARK: The pack

    /// Boop's pack: the win holds up a palm for a tap and high-fives, the
    /// upset turns its back for a stroke and sighs, the back leans in for a
    /// stroke and purrs, and the fix invites nothing.
    func testThePacksInvitesParse() throws {
        let pack = try SkitTests.pack()
        let invites = Dictionary(uniqueKeysWithValues: pack.skits.map { ($0.id, $0.invite) })
        XCTAssertEqual(invites["win"], Self.win.invite, pack.id)
        XCTAssertEqual(invites["upset"], Self.upset.invite, pack.id)
        XCTAssertEqual(invites["back"], Self.back.invite, pack.id)
        XCTAssertEqual(invites["fix"], .some(nil), "\(pack.id): the fix invites nothing")
        // The words by the place to touch are the pack's.
        let signs = try Steering(directory: pack.directory.appendingPathComponent("steering")).signs
        XCTAssertEqual(Signs.invite(signs, touch: .tap), "tap", pack.id)
        XCTAssertEqual(Signs.invite(signs, touch: .stroke), "pet", pack.id)
    }

    /// An invite that isn't one doesn't load: a pose, a touch or a payoff
    /// the board doesn't play, one missing, or no object.
    func testABadInviteDoesntLoad() throws {
        func pack(_ invite: Any) throws -> CharacterPack {
            try CharacterPack(json: ["id": "t", "name": "T", "version": "1", "default_mood": "calm",
                                     "moods": [["id": "calm", "face": "Calm."]], "lasting": [["id": "calm", "meaning": "Settled."]],
                                     "skits": [["id": "win", "slots": ["doneLong"], "invite": invite]]], from: "t.json")
        }
        let fine = try pack(["pose": "palm", "touch": "tap", "payoff": "highfive"])
        XCTAssertEqual(fine.skits.first?.invite, Self.win.invite)
        for (invite, why): (Any, String) in [
            (["pose": "wave", "touch": "tap", "payoff": "highfive"], "t.json: skit win's invite has pose wave, which isn't one"),
            (["pose": "palm", "touch": "poke", "payoff": "highfive"], "t.json: skit win's invite has touch poke, which isn't one"),
            (["pose": "palm", "touch": "tap", "payoff": "cheer"], "t.json: skit win's invite has payoff cheer, which isn't one"),
            (["pose": "palm", "touch": "tap"], "t.json: skit win's invite has payoff none, which isn't one"),
            ("palm", "t.json: skit win's invite isn't an object"),
        ] {
            do {
                _ = try pack(invite)
                XCTFail("loaded: \(why)")
            } catch {
                XCTAssertEqual((error as? CharacterPackError)?.description, why)
            }
        }
    }

    // MARK: The ledger

    /// A reaction's record that asked an invite of `pose`.
    func asked(_ pose: Skit.Invite.Pose, at: Int64 = 0) -> Event {
        Event.did("Boop had a happy moment", for: 1, action: MomentOutput.outputName, by: "brain",
                  facts: [InviteLedger.askedFact: .string(pose.rawValue)], at: at)
    }

    /// A reaction's record that let an invite of `pose` go by for the misses.
    func skipped(_ pose: Skit.Invite.Pose, at: Int64 = 0) -> Event {
        Event.did("Boop had a happy moment", for: 1, action: MomentOutput.outputName, by: "brain",
                  facts: [InviteLedger.skippedFact: .string(pose.rawValue)], at: at)
    }

    /// The board's end of an invite of `skit`.
    func ended(_ end: Moment.Invite.End, _ skit: Skit = InviteTests.win, at: Int64 = 0) -> Event {
        Event(at: at, source: .device, type: .invite, specificType: end.rawValue,
              data: ["skit": .string(skit.id), "touch": .string(skit.invite!.touch.rawValue), "pose": .string(skit.invite!.pose.rawValue),
                     "ms": 1300])
    }

    func fold(_ events: [Event], into ledger: InviteLedger = InviteLedger()) -> InviteLedger {
        events.reduce(ledger) { InviteLedger.adding($1, to: $0) }
    }

    /// What the win's invite comes to.
    func asking(_ ledger: InviteLedger, _ skit: Skit = InviteTests.win, xp: Int? = 3) -> InviteLedger.Asking {
        ledger.asking(skit, label: { $0 == .tap ? "tap" : "pet" }, xp: xp)
    }

    /// `e` as the harness logs a reaction's record, in progress (`open`)
    /// until its `ended`, numbered `seq`.
    func open(_ e: Event, _ seq: Int) -> Event {
        var e = e
        e.seq = seq
        e.data["open"] = true
        return e
    }

    func asks(_ asking: InviteLedger.Asking) -> Moment.Invite? {
        if case .asks(let invite) = asking { return invite }
        return nil
    }

    /// One end for one invite: the first after the record that asked it,
    /// or a `late` after its `missed`; a second, or one with no invite
    /// asked, is none, and the runtime drops it.
    func testOneEndForOneInvite() {
        let asked = asked(.palm)
        for end in Moment.Invite.End.allCases {
            XCTAssertTrue(InviteLedger.ends(end, after: [asked]), end.rawValue)
            XCTAssertFalse(InviteLedger.ends(end, after: []), "none asked: \(end.rawValue)")
            XCTAssertEqual(InviteLedger.ends(end, after: [asked, ended(.missed)]), end == .late, "after a miss: \(end.rawValue)")
            for had in [Moment.Invite.End.answered, .late, .cut] {
                XCTAssertFalse(InviteLedger.ends(end, after: [asked, ended(had)]), "\(had.rawValue) then \(end.rawValue)")
            }
            XCTAssertFalse(InviteLedger.ends(end, after: [asked, ended(.missed), ended(.late)]), "missed, late, then \(end.rawValue)")
            XCTAssertTrue(InviteLedger.ends(end, after: [asked, ended(.answered), asked]), "the next invite: \(end.rawValue)")
        }
    }

    /// Pins the ledger's first row: fewer than 10 invites asked on this
    /// Boop day. The next Boop day starts its count again, and keeps the
    /// rest; a skit with no invite asks none.
    func testTenADay() {
        XCTAssertEqual(InviteLedger.mostADay, 10)
        let reader = InviteReader()
        var l = reader.open(day: "2026-11-04", carry: nil)
        for i in 0..<9 { l = fold([asked(.palm, at: Int64(i) * 60_000), ended(.answered)], into: l) }
        XCTAssertEqual(l.askedToday, 9)
        XCTAssertNotNil(asks(asking(l)), "the 10th")
        l = fold([asked(.lean, at: 10 * 60_000)], into: l)
        XCTAssertEqual(asking(l), .nothing, "past the day's 10, of every pose")
        XCTAssertEqual(asking(l, Self.back), .nothing)
        let next = reader.open(day: "2026-11-05", carry: l)
        XCTAssertNotNil(asks(asking(next)), "the next Boop day")
        XCTAssertEqual([next.asked, next.askedToday], [10, 0])
        XCTAssertEqual(next.poses, l.poses)
        XCTAssertEqual(asking(InviteLedger(), Skit(id: "fix", slots: [.checkFixed])), .nothing, "no invite, nothing to ask")
    }

    /// An invite counts against the day's 10 as it's asked, and stays
    /// counted once the Moment that asked it played; the daily counts wait
    /// for its `ended`. One the board skipped late, or that was cut, is
    /// taken back, so the next is still the very first.
    func testOnlyAnInviteThatPlayedCounts() {
        let reader = CountsReader(time: LocalTime()) { _ in }
        var counts = reader.open(day: "2026-11-04", carry: nil)
        var l = InviteLedger()
        func read(_ events: [Event]) {
            for e in events {
                l = InviteLedger.adding(e, to: l)
                _ = reader.read(e, line: nil, into: &counts)
            }
        }
        read([open(asked(.palm), 1)])
        XCTAssertEqual([l.asked, l.askedToday, counts.counted.invitesAsked], [1, 1, 0], "still in the queue: asked")
        XCTAssertFalse(l.first)
        read([Event.ended(1, action: MomentOutput.outputName, by: "brain", failed: "waited too long")])
        XCTAssertEqual([l.asked, l.askedToday, counts.counted.invitesAsked], [0, 0, 0], "skipped late")
        XCTAssertEqual(asks(asking(l))?.ms, InviteLedger.firstWaitMs, "taken back: still the very first")
        read([open(asked(.palm), 2), Event.ended(2, action: MomentOutput.outputName, by: "brain", failed: "cut short: something needed you")])
        XCTAssertEqual(l.asked, 0, "cut")
        read([open(asked(.palm), 3), Event.ended(3, action: MomentOutput.outputName, by: "brain")])
        XCTAssertEqual([l.asked, l.askedToday, counts.counted.invitesAsked], [1, 1, 1], "played")
        XCTAssertTrue(l.playing.open.isEmpty)
        read([Event.ended(3, action: MomentOutput.outputName, by: "brain")])
        XCTAssertEqual(l.asked, 1, "one end, once")

        // With 9 asked today, a 10th still in the queue leaves none for a
        // skit close behind it; once it's skipped, there's room again.
        var nine = InviteLedger()
        for _ in 0..<9 { nine = InviteLedger.adding(asked(.palm), to: nine) }
        XCTAssertEqual(nine.askedToday, 9)
        nine = InviteLedger.adding(open(asked(.palm), 20), to: nine)
        XCTAssertEqual(asking(nine), .nothing, "the 10th in the queue")
        nine = InviteLedger.adding(Event.ended(20, action: MomentOutput.outputName, by: "brain", failed: "waited too long"), to: nine)
        XCTAssertNotNil(asks(asking(nine)), "skipped: taken back")
    }

    /// Pins the thinning: after 3 misses in a row of a pose, every second
    /// invite of that pose is skipped, until one is answered. A late answer
    /// counts as answered; a cut changes nothing; another pose goes on.
    func testMissesThinThePose() {
        XCTAssertEqual(InviteLedger.thinAfter, 3)
        var l = fold([asked(.palm), ended(.missed), asked(.palm), ended(.missed), asked(.palm), ended(.cut)])
        XCTAssertNotNil(asks(asking(l)), "two misses and a cut")
        l = fold([asked(.palm), ended(.missed)], into: l)
        XCTAssertEqual(l.poses["palm"]?.missedInARow, 3)
        XCTAssertEqual(asking(l), .skipped(.palm), "the 3rd miss in a row: the next is skipped")
        XCTAssertNotNil(asks(asking(l, Self.back)), "another pose isn't")
        l = fold([skipped(.palm)], into: l)
        XCTAssertNotNil(asks(asking(l)), "the one after is asked")
        l = fold([asked(.palm), ended(.missed)], into: l)
        XCTAssertEqual(asking(l), .skipped(.palm), "and the next skipped again")
        l = fold([skipped(.palm), asked(.palm), ended(.missed), ended(.late)], into: l)
        XCTAssertEqual(l.poses["palm"]?.missedInARow, 0, "a late answer is an answer")
        XCTAssertNotNil(asks(asking(l)), "answered: none skipped")
        XCTAssertNotNil(asks(asking(fold([asked(.palm), ended(.answered)], into: l))))
    }

    /// Pins the label: shown until the pose was answered 5 times, and
    /// again after 3 misses in a row of it, until it's answered.
    func testTheLabelUntilYouKnowIt() {
        XCTAssertEqual([InviteLedger.labelUntil, InviteLedger.labelBackAfter], [5, 3])
        var l = InviteLedger()
        for n in 0..<5 {
            XCTAssertEqual(asks(asking(l))?.label, "tap", "answered \(n) times")
            l = fold([asked(.palm), n == 4 ? ended(.missed) : ended(.answered), n == 4 ? ended(.late) : ended(.cut)], into: l)
        }
        XCTAssertNil(asks(asking(l))?.label, "answered 5 times, the last late: the glow alone")
        XCTAssertEqual(asks(asking(l, Self.back))?.label, "pet", "another pose's own")
        l = fold([asked(.palm), ended(.missed), asked(.palm), ended(.missed)], into: l)
        XCTAssertNil(asks(asking(l))?.label, "two misses")
        l = fold([asked(.palm), ended(.missed), skipped(.palm)], into: l)
        XCTAssertEqual(asks(asking(l))?.label, "tap", "back after 3 misses in a row")
        l = fold([asked(.palm), ended(.answered)], into: l)
        XCTAssertNil(asks(asking(l))?.label, "until it's answered")
    }

    /// Pins the wait: 12 s for the very first invite this buddy asks, so
    /// everyone learns the loop once, then 4 s; the XP is what's given.
    func testTheFirstInviteWaitsLonger() {
        XCTAssertEqual([InviteLedger.firstWaitMs, InviteLedger.waitMs], [12_000, 4000])
        XCTAssertTrue(InviteLedger().first)
        let first = asks(asking(InviteLedger()))
        XCTAssertEqual(first, Moment.Invite(skit: "win", Self.win.invite!, label: "tap", ms: 12_000, xp: 3))
        XCTAssertEqual(asks(asking(fold([asked(.palm), ended(.cut)])))?.ms, 4000, "one asked, however it ended")
        XCTAssertEqual(asks(asking(InviteLedger(), xp: nil))?.xp, nil)
        XCTAssertEqual(Moment.Invite(skit: "win", Self.win.invite!, label: nil, ms: 60_000, xp: nil).ms, 30_000, "the board waits 30 s at most")
    }

    /// Pins why the very first wait is 12 s and no more: the longest
    /// Moment an invite rides on the gel, the only face that draws one (the
    /// low Moment after a finish, a finish, or a `back`'s hello held three
    /// times, with its take and bubble), then the first wait and a payoff
    /// of up to `payoffMs`, end inside the link's grace for the `do` with
    /// 10 s to spare, so the link never gives it up before the board's
    /// `ended`. The grace runs from the end of the `do`'s ttl, so it starts
    /// no later than the Moment does.
    func testTheFirstInviteEndsBeforeTheLinkGivesUp() throws {
        let payoffMs: Int64 = 5000, spare: Int64 = 10_000
        let held = Int64(MomentOutput.sizes.map(\.loops).max() ?? 0)
        let loop = try FirmwareTables.gelLongestLoopMs()
        let longestLine = Int64(max(Take.all.map(\.ms).max() ?? 0, Voice.maxSayMs))
        let bubble = try FirmwareTables.bubbleReadMs()
        let longestPlay = max(held * loop, loop + longestLine + bubble)
        XCTAssertGreaterThan(longestPlay, 15_000)
        XCTAssertEqual(InviteLedger.firstWaitMs, 12_000)
        XCTAssertLessThan(longestPlay + Int64(InviteLedger.firstWaitMs) + payoffMs + spare, DeviceLink.answerGraceMs,
                          "the longest Moment, the first wait and the payoff end inside the link's grace, with room to spare")
    }

    /// The ledger is the transcript's view, not a store of its own: the
    /// memory keeps it as it reads each event, and folding the recorded
    /// run of events again gives the same; a new memory on the same store
    /// picks it up.
    func testTheLedgerIsTheTranscriptsFold() throws {
        let store = try KeyValueStore(directory: nil)
        let memory = Memory(store: store, time: LocalTime())
        let t0: Int64 = 1_792_584_000_000
        let run = [asked(.palm, at: t0), ended(.missed, at: t0 + 5000), ended(.late, at: t0 + 9000),
                   asked(.lean, at: t0 + 60_000), ended(.answered, Self.back, at: t0 + 62_000),
                   asked(.back, at: t0 + 120_000), ended(.cut, Self.upset, at: t0 + 121_000),
                   Event(at: t0 + 130_000, source: .device, type: .poke, specificType: "input"),
                   skipped(.palm, at: t0 + 200_000)]
            .enumerated().map { i, e in
                var e = e
                e.seq = i + 1
                return e
            }
        for e in run { memory.heard(e, line: nil) }
        let kept = try XCTUnwrap(memory.invites.state)
        XCTAssertEqual(kept, fold(run))
        XCTAssertEqual(kept.asked, 3)
        XCTAssertEqual(kept.poses["palm"], InviteLedger.Pose(answered: 1, missedInARow: 0, skipped: true))
        XCTAssertEqual(Memory(store: store, time: LocalTime()).invites.state, kept, "kept across a launch")
    }

    // MARK: The Moment

    /// Pins the `do`'s `invite`, after the ask, as the wire contract has it.
    func testTheMomentsArgs() {
        var m = Moment(mood: "happy", loops: 2, sign: "done")
        m.invite = Moment.Invite(skit: "win", Self.win.invite!, label: "tap", ms: 4000, xp: 3)
        XCTAssertEqual(m.args.json, #"{"sign":"done","invite":{"skit":"win","pose":"palm","touch":"tap","payoff":"highfive","label":"tap","ms":4000,"xp":3},"mood":"happy","loops":2}"#)
        m.invite = Moment.Invite(skit: "upset", Self.upset.invite!, label: nil, ms: 30_000, xp: nil)
        XCTAssertEqual(m.args["invite"]?.object?.json, #"{"skit":"upset","pose":"back","touch":"stroke","payoff":"sigh","ms":30000}"#)
    }

    static let finish = Event(at: 1000, source: .claude, type: .turn, phase: .end, specificType: "Stop")
    static let won: Facts = ["outcome": "done", "length_ms": 180_000, "length": "long", "tools": 3]

    /// A win invites, on its Moment, when the board plays invites: the
    /// skit's pose, touch and payoff, the pack's word, care's XP while it
    /// has room, and the record says the pose, and HISTORY reads it.
    func testAWinInvites() throws {
        try requirePack("boop")
        let rig = InviteRig()
        rig.inviting()
        let result = try XCTUnwrap(rig.run(Self.finish, Self.won))
        XCTAssertEqual(rig.sent.count, 1)
        XCTAssertEqual(rig.sent.last?.invite, Moment.Invite(skit: "win", Self.win.invite!, label: "tap", ms: 12_000, xp: 3))
        XCTAssertEqual(result.facts[InviteLedger.askedFact], "palm")
        XCTAssertTrue(result.message.hasSuffix(", then held up a palm for a poke."), result.message)
        rig.care = Growth(xp: 0, today: Growth.dayMost - 2, care: 0).adds(.care)
        rig.run(Self.finish, Self.won)
        XCTAssertEqual(rig.sent.last?.invite?.xp, 2, "two short of the day's most: what will be paid")
        rig.care = 0
        rig.run(Self.finish, Self.won)
        XCTAssertNil(rig.sent.last?.invite?.xp, "care is full today: no XP shown")
        // A failed turn and you back: their own.
        let failed = Event(at: 1000, source: .claude, type: .turn, phase: .end, specificType: "StopFailure")
        rig.run(failed, ["outcome": "failed", "length_ms": 180_000, "length": "long", "tools": 3], face: "sad")
        XCTAssertEqual(rig.sent.last.flatMap(\.invite).map { [$0.skit, $0.pose.rawValue, $0.touch.rawValue, $0.payoff.rawValue] },
                       ["upset", "back", "stroke", "sigh"])
        XCTAssertEqual(rig.sent.last?.invite?.label, "pet")
        // A fix invites nothing; nor does a Moment that's no skit.
        let check = Event(at: 1000, source: .claude, type: .tool, phase: .end, specificType: "PostToolUse")
        let fixed = try XCTUnwrap(rig.run(check, ["topic": "tests", "result": "ok", "failed_before": 2]))
        XCTAssertNil(rig.sent.last?.invite)
        XCTAssertNil(fixed.facts[InviteLedger.askedFact])
        rig.run(Event(at: 1000, source: .device, type: .poke, specificType: "input"), [:])
        XCTAssertNil(rig.sent.last?.invite)
    }

    /// No invite without the board's `invites`, on a call, past the day's
    /// 10, with no ledger, or with nothing to ask it by; one blocked plays
    /// nothing at all. The Moment is then as it was.
    func testWhenNoInviteIsAsked() throws {
        try requirePack("boop")
        // A rig of its own each time: the same takes, from the same seed.
        func played(_ setUp: (InviteRig) -> Void) -> (Moment?, OutputResult?) {
            let rig = InviteRig()
            rig.inviting()
            setUp(rig)
            let result = rig.run(Self.finish, Self.won)
            return (rig.sent.last, result)
        }
        let plain = try XCTUnwrap(played { $0.react.inviting = nil }.0)
        XCTAssertNil(plain.invite, "nothing to ask it by")
        XCTAssertNotNil(played { _ in }.0?.invite)
        var full = InviteLedger()
        full.askedToday = InviteLedger.mostADay
        full.asked = InviteLedger.mostADay
        for (why, setUp): (String, (InviteRig) -> Void) in [
            ("no invites in the board's hello", { $0.board = false }), ("on a call", { $0.onCall = true }),
            ("no ledger", { $0.ledger = nil }), ("past the day's 10", { $0.ledger = full }),
        ] {
            let (m, result) = played(setUp)
            XCTAssertEqual(m, plain, why)
            XCTAssertNil(result?.facts[InviteLedger.askedFact], why)
        }
        let (blocked, failed) = played { $0.blocked = "something needs you" }
        XCTAssertNil(blocked, "blocked: no Moment, no invite")
        XCTAssertEqual(failed?.ok, false)
        // Skipped for the misses: the record says so, for the ledger.
        var missed = InviteLedger()
        missed.poses["palm"] = InviteLedger.Pose(answered: 0, missedInARow: 3)
        let (thinned, result) = played { $0.ledger = missed }
        XCTAssertEqual(thinned, plain)
        XCTAssertEqual(result?.facts[InviteLedger.skippedFact], "palm")
        XCTAssertNil(result?.facts[InviteLedger.askedFact])
    }

    /// The invite rides the last Moment queued: after the agent's offered
    /// line, so the pose comes after the line. That Moment waits behind the
    /// finish as long as the finish may wait and play, and has a record of
    /// its own, which says the invite and the line; the finish's says
    /// neither, and HISTORY's line for the agent's has none of its words.
    func testTheInviteFollowsTheAgentsLine() throws {
        try requirePack("boop")
        let rig = InviteRig()
        rig.inviting()
        var card = Card(kind: .result, text: "shipped the nav")
        card.lines = [Card.Line(says: "all green", feeling: "happy")]
        rig.card = card
        let result = try XCTUnwrap(rig.run(Self.finish, Self.won))
        XCTAssertEqual(rig.sent.map(\.sign), [nil, "all green"], "the finish, then the agent's line")
        XCTAssertNil(rig.sent[0].invite)
        XCTAssertEqual(rig.sent[1].invite?.pose, .palm)
        XCTAssertEqual(rig.sent.map(BoopDevice.ttl), [BoopDevice.finishTTL, BoopDevice.behindFinishTTL])
        XCTAssertNil(result.facts[InviteLedger.askedFact])
        XCTAssertNil(result.facts["offered_line"])
        XCTAssertFalse(result.message.contains("palm"), result.message)
        let after = try XCTUnwrap(rig.react.following)
        XCTAssertEqual(after.facts[InviteLedger.askedFact], "palm")
        XCTAssertEqual(after.facts["offered_line"], true)
        XCTAssertEqual(after.message, "After it, \(rig.react.pack.name) held up the agent's words, then held up a palm for a poke.")
        XCTAssertFalse(after.message.contains("all green"))
    }

    /// Pins how long a Moment behind a finish may wait: the finish's own
    /// 15 s, then 10 s for the gel's finish to play, its longest recipe,
    /// its take and its bubble inside that; and the link still waits for
    /// its `ended` within what the harness holds a reaction open.
    func testBehindAFinishWaitsForIt() throws {
        XCTAssertEqual(BoopDevice.behindFinishTTL, BoopDevice.finishTTL + 10_000)
        let gel = try FirmwareTables.gelLongestLoopMs(), bubble = try FirmwareTables.bubbleReadMs()
        XCTAssertLessThan(gel + Int64(Voice.maxSayMs) + bubble,
                          Int64(BoopDevice.behindFinishTTL - BoopDevice.finishTTL))
        XCTAssertLessThan(Int64(BoopDevice.behindFinishTTL) + DeviceLink.answerGraceMs, MomentOutput.openForMs)
        var m = Moment(mood: "happy", loops: 1, sign: "all green")
        XCTAssertEqual(BoopDevice.ttl(m), BoopDevice.reactionTTL)
        m.behindFinish = true
        XCTAssertEqual(BoopDevice.ttl(m), BoopDevice.behindFinishTTL)
        XCTAssertFalse(m.args.json.contains("behind"), "not sent")
    }

    /// With no `invites` in the board's hello, every Moment's `args` are
    /// byte for byte what they are with no invites at all, as before them:
    /// a run of every skit and more, with the board saying none, on a call,
    /// and with nothing to ask by.
    func testNoInvitesMeansTheSameArgs() throws {
        let events: [(Event, Facts, String)] = [
            (Self.finish, Self.won, "proud"),
            (Event(at: 1000, source: .claude, type: .turn, phase: .end, specificType: "StopFailure"),
             ["outcome": "failed", "length_ms": 400_000, "length": "very long", "tools": 9, "checks_failed": 2], "sad"),
            (Event(at: 1000, source: .claude, type: .tool, phase: .end, specificType: "PostToolUse"),
             ["topic": "tests", "result": "ok", "failed_before": 2], "pleased"),
            (Event(at: 1000, source: .claude, type: .tool, phase: .end, specificType: "PostToolUse"),
             ["topic": "tests", "result": "failed", "failed_before": 2], "grumpy"),
            (Event(at: 1000, source: .mac, type: .presence, phase: .end, specificType: "input"),
             ["away_ms": .int(3 * 3_600_000), "away": "very long"], "happy"),
            (Event(at: 1000, source: .device, type: .poke, specificType: "input"), [:], "amused"),
            (Event(at: 1000, source: .device, type: .gesture, specificType: "stroke"), [:], "affectionate"),
        ]
        func args(_ setUp: (InviteRig) -> Void) -> [String] {
            let rig = InviteRig()
            setUp(rig)
            for (e, facts, face) in events { rig.run(e, facts, face: face) }
            return rig.sent.map(\.args.json)
        }
        let before = args { _ in }
        XCTAssertEqual(before.count, events.count)
        XCTAssertFalse(before.contains { $0.contains(#""invite""#) })
        XCTAssertEqual(args { $0.inviting(); $0.board = false }, before, "no invites in hello")
        XCTAssertEqual(args { $0.inviting(); $0.onCall = true }, before, "on a call")
        XCTAssertNotEqual(args { $0.inviting() }, before, "a board that plays them gets them")
    }

    // MARK: Growth

    /// An answered invite is your time with Boop, in time or late, a tap
    /// as much as a stroke; a missed or cut one is nothing; and care's 30 a
    /// day still caps it.
    func testAnAnsweredInviteIsCare() throws {
        for end in Moment.Invite.End.allCases {
            XCTAssertEqual(Growth.source(of: ended(end), facts: nil), end.isYours ? .care : nil, end.rawValue)
            XCTAssertEqual(Growth.source(of: ended(end, Self.upset), facts: nil), end.isYours ? .care : nil, end.rawValue)
        }
        XCTAssertEqual(Touch.answering(ended(.answered)), .poke)
        XCTAssertEqual(Touch.answering(ended(.late, Self.back)), .stroke)
        XCTAssertNil(Touch.answering(ended(.missed)))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("boop-invite-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        for seq in 1...11 {
            var e = ended(.answered)
            e.seq = seq
            growth.count(e, Growth.source(of: e, facts: nil), today: "2026-10-22")
        }
        XCTAssertEqual(growth.growth.care, Growth.careMost, "care stops at 30")
        XCTAssertEqual(growth.todayBy[.care], .init(n: 10, xp: 30))
    }

    /// The daily counts: invites asked, answered, late and missed; a cut is
    /// none of them; an answer is a touch.
    func testTheDailyCounts() {
        let reader = CountsReader(time: LocalTime()) { _ in }
        var s = reader.open(day: "2026-11-04", carry: nil)
        for e in [asked(.palm), ended(.answered), asked(.palm), ended(.missed), ended(.late), asked(.lean), ended(.cut, Self.back),
                  asked(.back), ended(.missed, Self.upset)] {
            _ = reader.read(e, line: nil, into: &s)
        }
        let r = s.counted
        XCTAssertEqual([r.invitesAsked, r.invitesAnswered, r.invitesLate, r.invitesMissed], [4, 1, 1, 2])
        XCTAssertEqual(r.touches, 2, "an answer in time and a late one")
        XCTAssertTrue(DayCounts.summary([r]).contains("invites: 4 asked, 1 answered, 1 late, 2 missed"))
    }

    /// HISTORY reads how an invite ended as one plain line, whoever decided it.
    func testHistorysLine() {
        let view = TranscriptView()
        view.name = "Pip"
        let log = Transcript.log().view(now: 0)
        XCTAssertEqual(view.line(ended(.answered), log)?.text, "Pip held up a palm for a poke, and you gave it.")
        XCTAssertEqual(view.line(ended(.late, Self.back), log)?.text, "Pip leaned in for a stroke, and you gave it, late.")
        XCTAssertEqual(view.line(ended(.missed, Self.upset), log)?.text, "Pip turned its back to you for a stroke, and you didn't.")
        XCTAssertEqual(view.line(ended(.cut), log)?.text, "Pip held up a palm for a poke, and something cut it short.")
        XCTAssertNil(TranscriptView.wakes["invite"], "it never wakes the brain")
        XCTAssertTrue(TranscriptView.quiet.contains("invite"), "but has its line")
    }

    // MARK: Through the runtime

    /// A board that plays invites.
    static let hello = String(FakeTransport.hello.dropLast()) + #","invites":1}"#

    /// A runtime on a fake board, with no brain: each Moment is a pass
    /// forced as a turn finishes, as the dashboard forces one.
    func runtime(_ dir: URL, _ transport: FakeTransport, _ clock: VirtualClock) throws -> Runtime {
        try Runtime.setUp(stateDir: dir, name: "Pip")
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("b.sock").path, link: transport,
                                      steering: RuntimeTests.steering)
        options.alone = true
        options.devLines = true
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        options.readJevKey = { _ in nil }
        return try Runtime(options)
    }

    /// Through the runtime with a fake board: a win invites; the board's
    /// answer is recorded and earns care's 3 XP once; the next win's invite
    /// has the ledger's count moved; a miss then a late answer earns once;
    /// a stroke answering an invite soothes cross a level.
    func testThroughTheRuntime() throws {
        try requirePack("boop")
        let dir = URL(fileURLWithPath: "/tmp/boop-inv-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = VirtualClock(1_793_000_000_000)
        let transport = FakeTransport()
        let runtime = try runtime(dir, transport, clock)
        var now: Int64 { clock.now }
        // The board says each `do` played.
        var answered: Set<Int> = []
        func played() {
            for id in transport.dos.map(FakeTransport.id) where answered.insert(id).inserted { runtime.device(FakeTransport.ended(id, "done")) }
        }
        func win() {
            runtime.hook(HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
            clock.now += 120_000
            runtime.hook(HookLine(agent: "claude", hook: "Stop", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
            _ = runtime.harness.force([MomentOutput.emotionKey: "happy"], by: Runtime.forcedBy)
            played()
            clock.now += 60_000
        }
        func invite(_ line: String) -> [String: Any]? {
            let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            return (o?["args"] as? [String: Any])?["invite"] as? [String: Any]
        }
        func events() -> [Event] { runtime.harness.log.view(now: now).events.filter { $0.type == .invite } }
        func ledger() -> InviteLedger? { runtime.remembers?.invites.state }
        runtime.home.sync {
            runtime.connection(true)
            runtime.device(FakeTransport.hello)
            win()
            XCTAssertNil(transport.dos.compactMap(invite).first, "a board that doesn't say invites gets none")

            runtime.device(Self.hello)
            win()
            let first = transport.dos.compactMap(invite)
            XCTAssertEqual(first.count, 1)
            XCTAssertEqual(first.first?["skit"] as? String, "win")
            XCTAssertEqual(first.first?["ms"] as? Int, 12_000, "the very first")
            XCTAssertEqual(first.first?["xp"] as? Int, 3)
            XCTAssertEqual(ledger()?.asked, 1)

            let care = runtime.growth.growth.care
            runtime.device(#"{"t":"ev","kind":"invite","did":"answered","data":{"skit":"win","touch":"tap","ms":1300}}"#)
            runtime.device(#"{"t":"ev","kind":"invite","did":"answered","data":{"skit":"win","touch":"tap","ms":1400}}"#)
            XCTAssertEqual(events().map(\.specificType), ["answered"], "a second end of the one invite is dropped")
            XCTAssertEqual(events().last?["pose"]?.string, "palm")
            XCTAssertEqual(events().last?["ms"]?.int, 1300)
            XCTAssertEqual(runtime.growth.growth.care, care + 3, "care's 3, once")
            XCTAssertEqual(ledger()?.poses["palm"]?.answered, 1)
            XCTAssertEqual(runtime.remembers?.counts.state?.row.invitesAnswered, 1)

            win()
            let second = transport.dos.compactMap(invite)
            XCTAssertEqual(second.count, 2)
            XCTAssertEqual(second.last?["ms"] as? Int, 4000, "the count moved: no longer the first")
            XCTAssertEqual(second.last?["label"] as? String, "tap", "answered once: the word still shows")
            XCTAssertEqual(ledger()?.asked, 2)

            runtime.device(#"{"t":"ev","kind":"invite","did":"missed","data":{"skit":"win","touch":"tap","ms":4000}}"#)
            XCTAssertEqual(runtime.growth.growth.care, care + 3, "a miss earns nothing")
            runtime.device(#"{"t":"ev","kind":"invite","did":"late","data":{"skit":"win","touch":"tap","ms":9000}}"#)
            XCTAssertEqual(runtime.growth.growth.care, care + 6, "a late answer earns, once")
            XCTAssertEqual(ledger()?.poses["palm"], InviteLedger.Pose(answered: 2, missedInARow: 0))

            // A failed turn invites a stroke; cross a level up, the stroke
            // answering it soothes it a level.
            runtime.hook(HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
            clock.now += 120_000
            runtime.hook(HookLine(agent: "claude", hook: "StopFailure", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
            _ = runtime.harness.force([MomentOutput.emotionKey: "sad"], by: Runtime.forcedBy)
            XCTAssertEqual(transport.dos.compactMap(invite).last?["skit"] as? String, "upset")
            played()
            runtime.forceMood("cross", by: Runtime.forcedBy)
            runtime.device(#"{"t":"ev","kind":"gesture","did":"shake"}"#)
            func level() -> Int { MoodOutput.level(runtime.rig.mood, runtime.harness.log.view(now: now)) }
            let crossed = level()
            XCTAssertGreaterThan(crossed, 1)
            clock.now += 1000
            runtime.device(#"{"t":"ev","kind":"invite","did":"answered","data":{"skit":"upset","touch":"stroke","ms":2000}}"#)
            XCTAssertEqual(level(), crossed - 1, "the stroke soothes it")
            XCTAssertEqual(events().last?["pose"]?.string, "back")
            XCTAssertEqual(runtime.growth.growth.care, care + 9)
        }
    }
}

extension InviteTests {
    /// Through the runtime with a board that skips a Moment late: a win
    /// whose invite rides the finish, skipped, then one that plays. The
    /// record ends as the board says the Moment ended; the one skipped late
    /// asked no invite, for the ledger and the daily counts, and HISTORY
    /// leaves it out, so the next is still the very first. (A Moment behind
    /// a finish, with its own record, is `RemarksTests.testThroughTheRuntime`'s.)
    func testASkippedMomentAsksNoInvite() throws {
        try requirePack("boop")
        let dir = URL(fileURLWithPath: "/tmp/boop-skp-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = VirtualClock(1_793_000_000_000)
        let transport = FakeTransport()
        let runtime = try runtime(dir, transport, clock)
        var now: Int64 { clock.now }
        var answered: Set<Int> = []
        /// The board ends each `do` not ended yet, the last ones as `last`.
        func ended(last: Int = 0, _ how: String = "done", why: String? = nil) {
            let ids = transport.dos.map(FakeTransport.id).filter { !answered.contains($0) }
            for (i, id) in ids.enumerated() {
                answered.insert(id)
                runtime.device(i >= ids.count - last ? FakeTransport.ended(id, how, why) : FakeTransport.ended(id, "done"))
            }
        }
        func win() {
            runtime.hook(HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
            clock.now += 120_000
            runtime.hook(HookLine(agent: "claude", hook: "Stop", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
            _ = runtime.harness.force([MomentOutput.emotionKey: "happy"], by: Runtime.forcedBy)
        }
        func records() -> [Event] {
            runtime.harness.log.view(now: now).events.filter { $0.kind == Event.did && $0.action == MomentOutput.outputName }
        }
        func object(_ line: String) -> [String: Any]? { try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] }
        func ttl(_ line: String) -> Int? { object(line)?["ttl"] as? Int }
        func invite(_ line: String) -> [String: Any]? { (object(line)?["args"] as? [String: Any])?["invite"] as? [String: Any] }
        func ledger() -> InviteLedger? { runtime.remembers?.invites.state }
        runtime.home.sync {
            runtime.connection(true)
            runtime.device(Self.hello)
            ended()
            win()
            // The invite rides the last Moment queued: the line behind the finish.
            XCTAssertNotNil(transport.dos.last.flatMap(invite), "the invite rides the line after the finish")
            XCTAssertEqual(records().last?[InviteLedger.askedFact]?.string, "palm")
            ended(last: 1, "skipped", why: "late")
            let log = runtime.harness.log.view(now: now)
            let skipped = try? XCTUnwrap(records().last)
            XCTAssertEqual(skipped.flatMap { log.ended($0.seq) }?["why"]?.string, "waited too long")
            XCTAssertNil(skipped.flatMap(log.shown), "HISTORY leaves it out")
            XCTAssertEqual(ledger()?.asked, 0, "skipped late: no invite asked")
            XCTAssertEqual(runtime.remembers?.counts.state?.counted.invitesAsked, 0)

            // The next win's invite is still the very first, and plays.
            clock.now += 60_000
            win()
            XCTAssertEqual(transport.dos.last.flatMap(invite)?["ms"] as? Int, InviteLedger.firstWaitMs, "still the very first")
            ended()
            XCTAssertEqual(ledger()?.asked, 1, "played: asked")
            XCTAssertEqual(runtime.remembers?.counts.state?.counted.invitesAsked, 1)
            let played = try? XCTUnwrap(records().last)
            XCTAssertNotNil(played.flatMap(runtime.harness.log.view(now: now).shown), "HISTORY shows it")
        }
    }
}

extension InviteTests {
    /// A Moment queued while an invite is in flight waits until the invite
    /// is over, as the pose holds the board's queue to its payoff or shrug:
    /// the ring's gold after a win that invites isn't skipped late. Once
    /// the inviting `do` ends, a rule's Moment waits its own ttl again.
    func testAMomentQueuedBehindAnInviteWaitsForIt() throws {
        try requirePack("boop")
        let face = try String(contentsOf: FirmwareTables.root.appendingPathComponent("firmware/src/render/face.h"), encoding: .utf8)
        let payoff = try XCTUnwrap(face.firstMatch(of: /kPayoffMs = (\d+), kShrugMs = (\d+)/))
        XCTAssertEqual(BoopDevice.payoffMs, Int(payoff.1), "the board's payoff")
        let shrug = try XCTUnwrap(Int(payoff.2))
        XCTAssertGreaterThan(BoopDevice.payoffMs, shrug, "longer than the shrug")
        XCTAssertLessThanOrEqual(BoopDevice.behindFinishTTL + BoopDevice.inviteHoldsMs(InviteLedger.firstWaitMs), Wire.maxTTL)

        let dir = URL(fileURLWithPath: "/tmp/boop-bhi-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = VirtualClock(1_793_000_000_000)
        let transport = FakeTransport()
        let runtime = try runtime(dir, transport, clock)
        var now: Int64 { clock.now }
        func object(_ line: String) -> [String: Any]? { try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] }
        func ttl(_ line: String?) -> Int? { line.flatMap(object)?["ttl"] as? Int }
        runtime.home.sync {
            runtime.connection(true)
            runtime.device(Self.hello)
            runtime.hook(HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
            clock.now += 120_000
            runtime.hook(HookLine(agent: "claude", hook: "Stop", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
            _ = runtime.harness.force([MomentOutput.emotionKey: "happy"], by: Runtime.forcedBy)
            let inviting = try? XCTUnwrap(transport.dos.last)
            XCTAssertNotNil((inviting.flatMap(object)?["args"] as? [String: Any])?["invite"], "the win invites, on its line")
            XCTAssertEqual(ttl(inviting), BoopDevice.behindFinishTTL)

            clock.now += 1000
            var gold = Moment(mood: "happy", loops: 1)
            gold.gold = Core.ringSign(daysInARow: 1)
            runtime.playRule(gold)
            XCTAssertEqual(ttl(transport.dos.last), BoopDevice.behindFinishTTL + BoopDevice.inviteHoldsMs(InviteLedger.firstWaitMs) - 1000,
                           "the gold waits out the invite")

            if let id = inviting.map(FakeTransport.id) { runtime.device(FakeTransport.ended(id, "done")) }
            runtime.playRule(gold)
            XCTAssertEqual(ttl(transport.dos.last), BoopDevice.reactionTTL, "the invite is over")
        }
    }
}

/// Plays the react output on its own, the board's say about invites,
/// your call, needs you, the ledger and the agent's card as given.
@MainActor final class InviteRig {
    var sent: [Moment] = []
    var board = true, onCall = false, blocked: String?
    var ledger: InviteLedger? = InviteLedger()
    var care = Growth.careXP
    var facts: InviteTests.Facts = [:]
    var card: Card?
    var pack: CharacterPack = .active
    var talk = Talk.normal
    lazy var react: MomentOutput = {
        let react = MomentOutput(queue: { [unowned self] m, _ in sent.append(m) }, blocked: { [unowned self] in blocked }, pack: pack,
                                 signs: RuntimeTests.steering.signs, talk: { [unowned self] in talk },
                                 line: { [unowned self] _ in Line("", facts: facts) })
        react.offered = { [unowned self] _ in card }
        return react
    }()

    func inviting() {
        react.inviting = MomentOutput.Inviting(board: { [unowned self] in board }, onCall: { [unowned self] in onCall },
                                               ledger: { [unowned self] in ledger },
                                               care: { [unowned self] in care })
    }

    /// The react output's answer to `e`, whose line has `facts`, in `face`.
    @discardableResult
    func run(_ e: Event, _ facts: InviteTests.Facts, face: String = "happy") -> OutputResult? {
        self.facts = facts
        return react.run([MomentOutput.emotionKey: Answer(choice: face, probabilities: [face: 1])], now: e, log: Transcript.log().view(now: e.at))
    }
}
