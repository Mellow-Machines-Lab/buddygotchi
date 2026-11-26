import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// Boop's line (`Lines`): one short sentence about what just happened,
/// held low, and said whole when the board has its recorded sentence
/// (`SentencesTests`).
final class AsidesTests: XCTestCase {
    typealias Facts = [String: JSONValue]
    var rows: [TaggedLine] { RuntimeTests.steering.signs }

    static let finish = RemarksTests.finish()
    static var check: Event {
        var e = Event(at: 1000, source: .claude, type: .tool, phase: .end, specificType: "PostToolUse")
        e.seq = 100
        return e
    }
    static let thread: JSONValue = ["name": "buddygotchi", "agent": "claude"]

    func win(minutes: Int64 = 20, checksFailed: Int64 = 0) -> Facts {
        var f = RemarksTests().win(minutes: minutes)
        f["checks_failed"] = .int(checksFailed)
        f["thread"] = Self.thread
        return f
    }
    func failed(minutes: Int64 = 20) -> Facts {
        ["outcome": "failed", "length_ms": .int(minutes * 60_000), "length": .string(Band.length(ms: minutes * 60_000)),
         "tools": 3, "thread": Self.thread]
    }
    func check(_ result: String, before: Int64, topic: String = "tests") -> Facts {
        ["topic": .string(topic), "result": .string(result), "failed_before": .int(before), "thread": Self.thread]
    }

    func pool(_ moment: String, _ slot: RulesBrain.Slot, _ facts: Facts, work: String? = nil, mood: String = "calm",
              swears: Bool = false) -> [String] {
        Asides.pool(rows, moment: moment, slot: slot, facts: facts, work: work, mood: mood, swears: swears, quiet: false).map(\.text)
    }

    /// Pins `Asides.moment`: the skits' but `back`, and a failed check
    /// before its skit.
    func testWhichMomentsHaveAnAside() {
        func skit(_ id: String, swears: Bool = false) -> Skits.Play { Skits.Play(skit: Skit(id: id, slots: []), swears: swears) }
        XCTAssertEqual(Asides.moment(skit: skit("win"), slot: .doneLong), "win")
        XCTAssertEqual(Asides.moment(skit: skit("upset"), slot: .failed), "upset")
        XCTAssertEqual(Asides.moment(skit: skit("upset"), slot: .checkFailing), "upset")
        XCTAssertEqual(Asides.moment(skit: skit("fix"), slot: .checkFixed), "fix")
        XCTAssertEqual(Asides.moment(skit: skit("back"), slot: .back), "back", "a sentence only")
        XCTAssertEqual(Asides.moment(skit: nil, slot: .other, pushed: true), "ship", "a sentence only")
        XCTAssertEqual(Asides.moment(skit: nil, slot: .checkFailed), "oops")
        XCTAssertEqual(Asides.moment(skit: nil, slot: .checkFailing), "oops", "the 2nd in a row, before the skit")
        XCTAssertNil(Asides.moment(skit: nil, slot: .doneShort), "a short win: none")
        XCTAssertNil(Asides.moment(skit: nil, slot: .other))
    }

    /// Pins `Asides.work`: what a turn was, the first there is.
    func testWhatATurnWas() {
        XCTAssertEqual(Asides.work(doing: "writing the report", headline: "Fix Safari export", act: "tests", thread: "t", project: "p"),
                       "writing the report", "its status first")
        XCTAssertEqual(Asides.work(doing: nil, headline: "Fix Safari export", act: "tests", thread: "t", project: "p"), "Fix Safari export")
        XCTAssertEqual(Asides.work(doing: " ", headline: "nav overflow fixed", act: "tests", thread: "t", project: "p"), "the tests",
                       "a headline that says how it came out isn't the work")
        XCTAssertEqual(Asides.work(doing: nil, headline: "2.1x faster", act: "push", thread: nil, project: "p"), "the push")
        XCTAssertEqual(Asides.work(doing: nil, headline: nil, act: nil, thread: "Fix Safari export", project: "buddygotchi"), "Fix Safari export")
        XCTAssertEqual(Asides.work(doing: nil, headline: nil, act: nil, thread: nil, project: "buddygotchi"), "buddygotchi")
        XCTAssertEqual(Asides.work(doing: "fixing the nav overflow in Safari", headline: nil, act: nil, thread: nil, project: nil),
                       "fixing the nav overflow", "cut at a word to 24")
    }

    /// Every win and upset row reads well with the three kinds of fill: a
    /// gerund (small inside a sentence, a capital starting one), a noun,
    /// and a name; and each kind leaves a few rows to pick from.
    func testTurnAsidesReadWithEveryKindOfFill() throws {
        try requirePack("boop")
        for work in ["writing the report", "Writing the report", "the tests", "Fix Safari export"] {
            let wins = pool("win", .doneLong, win(), work: work), upsets = pool("upset", .failed, failed(), work: work)
            XCTAssertGreaterThanOrEqual(wins.count, 5, work)
            XCTAssertGreaterThanOrEqual(upsets.count, 4, work)
            XCTAssertGreaterThanOrEqual(pool("upset", .gaveUp, failed(), work: work).count, 2, work)
            XCTAssertGreaterThanOrEqual(pool("win", .doneVeryLong, win(minutes: 90, checksFailed: 2), work: work).count, 2, work)
            for text in wins + upsets {
                XCTAssertTrue(text.lowercased().contains(work.lowercased()), text)
                XCTAssertFalse(text.contains(" is ") || text.contains(" was "), "no verb that agrees with one kind only: \(text)")
            }
        }
        let gerund = pool("win", .doneLong, win(), work: "Writing the report")
        XCTAssertTrue(gerund.contains("Yay, writing the report, done!"), "\(gerund)")
        XCTAssertTrue(pool("upset", .failed, failed(), work: "writing the report").contains("Aw. Writing the report hit a wall."))
        XCTAssertTrue(pool("win", .doneLong, win(), work: "Fix Safari export").contains("Yay, Fix Safari export, done!"))
        XCTAssertTrue(pool("upset", .failed, failed(), work: "the tests").contains("Ouch. The tests fell over."))
        // No work: the thread's name.
        XCTAssertTrue(pool("win", .doneLong, win()).contains("Yay, buddygotchi, done!"))
        // A check names the check, whatever the turn's work.
        XCTAssertTrue(pool("oops", .checkFailed, check("failed", before: 0), work: "writing the report").allSatisfy { $0.lowercased().contains("the tests") })
    }

    /// Each moment's asides, filled from the facts, by what's true.
    func testEachMomentsAsidesSayWhatHappened() throws {
        try requirePack("boop")
        let w = "writing the report"
        // A very long win, a hard-won one: their own rows.
        let long = pool("win", .doneVeryLong, win(minutes: 90), work: w)
        XCTAssertTrue(long.contains("Phew. Writing the report, done at last!"), "\(long)")
        XCTAssertFalse(long.contains("Yay, writing the report, done!"))
        XCTAssertTrue(pool("win", .doneLong, win(checksFailed: 2), work: w).contains("2 fails, then writing the report: done."))
        // A cross or sad mood doesn't cheer.
        for mood in ["cross", "sad"] {
            let glum = pool("win", .doneLong, win(checksFailed: 2), work: w, mood: mood)
            XCTAssertFalse(glum.isEmpty)
            XCTAssertTrue(glum.allSatisfy { !$0.contains("!") && !$0.contains("Yay") }, "\(mood): \(glum)")
        }
        // The 3rd failed check in a row: "again".
        let again = pool("upset", .checkFailing, check("failed", before: 2))
        XCTAssertTrue(again.contains("Oh man, the tests failed again."), "\(again)")
        XCTAssertTrue(again.contains("The tests, 3 in a row. Ugh."), "\(again)")
        XCTAssertTrue(pool("upset", .gaveUp, failed(), work: w).contains("Aw. Writing the report: stuck."))
        // A fix, and the 1st and 2nd failed check.
        XCTAssertTrue(pool("fix", .checkFixed, check("ok", before: 1)).contains("Phew. The tests, fixed."))
        XCTAssertTrue(pool("fix", .checkFixed, check("ok", before: 3)).contains("3 tries. The tests, fixed!"))
        XCTAssertTrue(pool("fix", .checkFixed, check("ok", before: 3)).contains("Took 3 goes. The tests, fixed!"))
        let first = pool("oops", .checkFailed, check("failed", before: 0, topic: "build"))
        XCTAssertTrue(first.contains("Uh oh. The build failed."), "\(first)")
        XCTAssertFalse(first.contains("The build failed again."))
        XCTAssertTrue(pool("oops", .checkFailing, check("failed", before: 1)).contains("The tests failed again."))
    }

    /// A swear row only when the skit swears (Settings' swearing on, and
    /// the failures piled up: `Skits.play`).
    func testASwearOnlyWhenTheSkitSwears() throws {
        try requirePack("boop")
        let swear = Set(rows.filter { $0.tags.contains("swear") }.map(\.text))
        XCTAssertFalse(swear.isEmpty)
        for (slot, facts) in [(RulesBrain.Slot.failed, failed()), (.checkFailing, check("failed", before: 2))] {
            let mild = Asides.pool(rows, moment: "upset", slot: slot, facts: facts, mood: "calm", swears: false, quiet: false).map(\.row)
            XCTAssertTrue(Set(mild).isDisjoint(with: swear), "\(slot): \(mild)")
            let sworn = Asides.pool(rows, moment: "upset", slot: slot, facts: facts, mood: "calm", swears: true, quiet: false).map(\.row)
            XCTAssertFalse(Set(sworn).isDisjoint(with: swear), "\(slot)")
        }
    }

    /// On Quiet, no aside.
    func testQuietHasNoAside() throws {
        try requirePack("boop")
        var rng = SplitMix64(seed: 1)
        XCTAssertNil(Asides.pick(rows, moment: "upset", slot: .failed, facts: failed(), mood: "calm", swears: false, quiet: true, rng: &rng))
        XCTAssertNotNil(Asides.pick(rows, moment: "upset", slot: .failed, facts: failed(), mood: "calm", swears: false, quiet: false, rng: &rng))
    }

    /// Never the same row twice running, while another fits.
    func testNeverTheSameRowTwiceRunning() throws {
        try requirePack("boop")
        var rng = SplitMix64(seed: 7)
        var last: String?
        for _ in 0..<40 {
            let row = try XCTUnwrap(Asides.pick(rows, moment: "oops", slot: .checkFailed, facts: check("failed", before: 0), mood: "calm",
                                                    swears: false, quiet: false, avoiding: last, rng: &rng)).row
            XCTAssertNotEqual(row, last)
            last = row
        }
    }

    /// Pins `Asides.maxLength` and the low sign's rows: every row of the
    /// pack fits two rows of 26 with a short fill and a two-digit `{n}`,
    /// and a row too long for a long fill is left out, never cut.
    func testEveryAsideFitsTheLowSign() throws {
        try requirePack("boop")
        XCTAssertEqual(Asides.maxLength, 40)
        XCTAssertEqual(Asides.rowLength, 26)
        XCTAssertEqual(Asides.whatLength, 24)
        let asides = rows.filter { $0.tags.first == "aside" }
        XCTAssertGreaterThan(asides.count, 40)
        let moments: Set<String> = ["win", "upset", "fix", "oops", "back", "ship"]
        let tags = Set<String>(["long", "hard", "glum", "check", "stuck", "swear", "again", "hour", "days", "night"])
            .union(TranscriptView.checks)
        for aside in asides {
            XCTAssertTrue(moments.contains(aside.tags[1]), aside.text)
            XCTAssertTrue(Set(aside.tags.dropFirst(2)).isSubset(of: tags), aside.text)
            XCTAssertFalse(aside.text.contains("?"), "no questions: \(aside.text)")
            for what in ["the deploy", "writing the report"] {
                XCTAssertNotNil(Asides.filled(aside.text, what: what, n: 10), "\(aside.text) with \(what)")
            }
            if let long = Asides.filled(aside.text, what: String(repeating: "w", count: Asides.whatLength), n: 10) {
                XCTAssertTrue(Asides.fits(long), long)
            }
        }
        XCTAssertFalse(Asides.fits(String(repeating: "a", count: 27)))
        // A long thread's name is cut to fit.
        var f = win()
        f["thread"] = ["name": "a-very-long-workspace-name-indeed"]
        XCTAssertFalse(pool("win", .doneLong, f).isEmpty)
    }

    // MARK: In the Moment

    @MainActor func rig(talk: Talk = .normal) -> InviteRig {
        let rig = InviteRig()
        rig.talk = talk
        return rig
    }

    /// A long win's aside is a low Moment behind the finish, its record's
    /// `aside`; the finish keeps its take, and the aside's words never go
    /// to HISTORY.
    @MainActor func testAWinsAsideFollowsTheFinish() throws {
        try requirePack("boop")
        let rig = rig()
        let result = try XCTUnwrap(rig.run(Self.finish, win()))
        XCTAssertEqual(rig.sent.count, 2)
        let aside = try XCTUnwrap(rig.sent.last?.sign)
        XCTAssertTrue(aside.lowercased().contains("buddygotchi"), aside)
        XCTAssertEqual(rig.sent.last?.low, true)
        XCTAssertFalse(rig.sent.first?.say?.takes.isEmpty ?? true, "the board plays its take")
        let after = try XCTUnwrap(rig.react.following)
        XCTAssertEqual(after.facts["aside"]?.string, aside)
        XCTAssertFalse(after.message.contains(aside), after.message)
        XCTAssertFalse(result.message.contains(aside))
    }

    /// The agent's offered line is the aside.
    @MainActor func testTheAgentsLineIsTheAside() throws {
        try requirePack("boop")
        let rig = rig()
        var card = Card(kind: .result, text: "shipped the nav")
        card.lines = [Card.Line(says: "nav, shipped. nice", feeling: "happy")]
        rig.card = card
        rig.run(Self.finish, win())
        XCTAssertEqual(rig.sent.last?.sign, "nav, shipped. nice")
        XCTAssertEqual(rig.react.following?.facts["aside"]?.string, "nav, shipped. nice")
        XCTAssertEqual(rig.react.following?.facts["offered_line"], true)
    }

    /// A failed check's aside is the Moment's own low sign, over a fix's;
    /// HISTORY says only that it held one up.
    @MainActor func testACheckHoldsItsAsideLow() throws {
        try requirePack("boop")
        let rig = rig()
        let result = try XCTUnwrap(rig.run(Self.check, check("failed", before: 0), face: "annoyed"))
        XCTAssertEqual(rig.sent.count, 1)
        let aside = try XCTUnwrap(rig.sent.first?.sign)
        XCTAssertTrue(aside.lowercased().contains("the tests"), aside)
        XCTAssertEqual(rig.sent.first?.low, true)
        XCTAssertEqual(result.facts["aside"]?.string, aside)
        XCTAssertFalse(result.message.contains(aside), result.message)
        let fixed = try XCTUnwrap(rig.run(Self.check, check("ok", before: 2), face: "proud"))
        XCTAssertNotNil(fixed.facts["aside"])
    }

    /// On Quiet, no aside.
    @MainActor func testQuietShowsNoAside() throws {
        try requirePack("boop")
        let rig = rig(talk: .quiet)
        rig.run(Self.check, check("failed", before: 0), face: "annoyed")
        XCTAssertNil(rig.sent.first?.sign)
    }

    /// A finished turn's aside says what the agent said it was doing: its
    /// last status card this turn, before the thread's name.
    @MainActor func testAFinishSaysWhatTheAgentWasDoing() throws {
        try requirePack("boop")
        let log = Transcript.log()
        _ = log.append(Event(at: 100, source: .claude, type: .turn, phase: .start, specificType: "UserPromptSubmit", session: "s1"), now: 100)
        _ = log.append(Event(at: 200, source: .claude, type: .card, phase: .start, specificType: "status", session: "s1",
                             data: ["agent": "claude", "text": "drafting the outline"]), now: 200)
        _ = log.append(Event(at: 300, source: .claude, type: .card, phase: .start, specificType: "status", session: "s1",
                             data: ["agent": "claude", "text": "Writing the report"]), now: 300)
        var finish = Event(at: 1000, source: .claude, type: .turn, phase: .end, specificType: "Stop", session: "s1")
        finish = log.append(finish, now: 1000)
        let rig = rig()
        rig.facts = win()
        rig.react.run([MomentOutput.emotionKey: Answer(choice: "happy", probabilities: ["happy": 1])], now: finish, log: log.view(now: 1000))
        let aside = try XCTUnwrap(rig.sent.last?.sign)
        XCTAssertTrue(aside.lowercased().contains("writing the report"), aside)
    }
}
