import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// What Boop notices (`Notices`): the rules and rests, each pinned, and that
/// a notice adds to a Moment rather than making a second one, a wish first.
final class NoticesTests: XCTestCase {
    let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
    let minute: Int64 = 60_000, hour: Int64 = 3_600_000
    /// A Wednesday, 15:00 UTC.
    let t0: Int64 = 1_793_804_400_000

    func moment(_ at: Int64? = nil) -> Notices.Moment {
        Notices.Moment(at: at ?? t0, wall: at ?? t0, time: time)
    }

    func idle(_ agent: String = "claude", on place: String = "api", for ms: Int64) -> StatusReply.Agent {
        StatusReply.Agent(agent: agent, places: [place], restingSince: t0 - ms)
    }

    // MARK: Each notice's rule and rest

    /// Pins `waiting`: from 15 min to an hour idle, the longest first, never
    /// during a needs-you, resting per agent for the day.
    func testWaiting() {
        var m = moment()
        m.agents = [idle(for: 14 * minute)]
        XCTAssertNil(Notices.due(m), "under 15 min")
        m.agents = [idle(for: 61 * minute)]
        XCTAssertNil(Notices.due(m), "past the hour you've moved on")
        m.agents = [idle(for: 17 * minute)]
        let due = Notices.due(m)
        XCTAssertEqual(due?.kind, .waiting)
        XCTAssertEqual(due?.fact, "claude has sat idle on \"api\" for 17 min")
        XCTAssertEqual(due?.agent, "claude")
        m.agents.append(StatusReply.Agent(agent: "codex", places: ["blog"], needsYou: true))
        XCTAssertNil(Notices.due(m), "never during a needs-you")
        m.agents = [idle(for: 17 * minute), idle("codex", on: "blog", for: 30 * minute)]
        XCTAssertEqual(Notices.due(m)?.agent, "codex", "the one that sat longest")
        m.shown = ["waiting:codex": t0 - 2 * hour]
        XCTAssertEqual(Notices.due(m)?.agent, "claude", "per agent, not repeating")
        m.shown["waiting:claude"] = t0 - 3 * hour
        XCTAssertNil(Notices.due(m), "both have rested today's")
        m.agents = [idle(on: "api, renamed", for: 17 * minute)]
        XCTAssertNil(Notices.due(m), "a retitled thread is the same agent")
        m.shown = ["waiting:claude": t0 - 24 * hour]
        m.agents = [idle(for: 17 * minute)]
        XCTAssertNotNil(Notices.due(m), "a new day")
    }

    /// Pins `stretch`: 2 h at the Mac with no break, a day's rest.
    func testStretch() {
        var m = moment()
        m.hereSince = t0 - 119 * minute
        XCTAssertNil(Notices.due(m))
        m.hereSince = t0 - 2 * hour
        XCTAssertEqual(Notices.due(m)?.kind, .stretch)
        XCTAssertEqual(Notices.due(m)?.fact, "you've been at the Mac for 2 h with no break")
        m.shown = ["stretch": t0 - 2 * hour]
        XCTAssertNil(Notices.due(m), "a day's rest")
    }

    /// Pins `rough`: 3 failures within the hour, or a sharp prompt within it.
    func testRough() {
        var m = moment()
        m.failures = [t0 - 50 * minute, t0 - 10 * minute]
        XCTAssertNil(Notices.due(m), "2 failures")
        m.failures.append(t0 - 61 * minute)
        XCTAssertNil(Notices.due(m), "the third is over an hour old")
        m.failures.append(t0 - 5 * minute)
        XCTAssertEqual(Notices.due(m)?.kind, .rough)
        XCTAssertEqual(Notices.due(m)?.fact, "a rough hour: 3 failures")
        m.failures = []
        m.sharpAt = t0 - 59 * minute
        XCTAssertEqual(Notices.due(m)?.kind, .rough)
        m.sharpAt = t0 - 60 * minute
        XCTAssertNil(Notices.due(m))
        m.sharpAt = t0 - minute
        m.shown = ["rough": t0 - 2 * hour]
        XCTAssertNil(Notices.due(m), "a day's rest")
    }

    func night(_ day: String, last: String = "01:30") -> DayDigest {
        var d = DayDigest(day: day, weekday: "Monday")
        d.last = last
        return d
    }

    /// Pins `late`: past midnight, after 3 of the last 7 nights past 1:00, a
    /// week's rest; and the one that comes when Boop has dozed off.
    func testLate() {
        // 2026-11-05 00:30 is Boop's day 2026-11-04.
        let at = t0 + 9 * hour + 30 * minute
        var m = moment(at)
        m.digests = [night("2026-11-03"), night("2026-11-02")]
        XCTAssertNil(Notices.due(m), "2 nights")
        m.digests.append(night("2026-10-20"))
        XCTAssertNil(Notices.due(m), "a night out of the week doesn't count")
        m.digests.append(night("2026-11-01", last: "23:59"))
        XCTAssertNil(Notices.due(m), "nor one that ended before 1:00")
        m.digests.append(night("2026-10-31"))
        XCTAssertEqual(Notices.due(m)?.kind, .late)
        XCTAssertEqual(Notices.due(m)?.fact, "past midnight again: up past 1 on 3 of the last 7 nights")
        var day = m
        day.at = t0
        day.wall = t0
        XCTAssertNil(Notices.due(day), "only past midnight")
        m.shown = ["late": at - 6 * 24 * hour]
        XCTAssertNil(Notices.due(m), "a week's rest")
        m.shown = ["late": at - 7 * 24 * hour]
        XCTAssertNotNil(Notices.due(m))
        m.shown = [:]
        m.dozing = true
        XCTAssertEqual(Notices.due(m)?.kind, .late, "it comes though Boop has dozed off")
        m.hereSince = at - 3 * hour
        XCTAssertEqual(Notices.due(m)?.kind, .late, "nothing else does")
        m.digests = []
        XCTAssertNil(Notices.due(m))
    }

    /// Pins the ceiling: 2 played in a Boop day, an hour apart.
    func testAtMostTwoADayAnHourApart() {
        var m = moment()
        m.agents = [idle(for: 20 * minute), idle("codex", on: "blog", for: 21 * minute)]
        m.hereSince = t0 - 3 * hour
        m.shown = ["stretch": t0 - 59 * minute]
        XCTAssertNil(Notices.due(m), "one just played")
        m.shown = ["stretch": t0 - 61 * minute]
        XCTAssertEqual(Notices.due(m)?.kind, .waiting)
        m.shown["waiting:codex"] = t0 - 2 * hour
        XCTAssertNil(Notices.due(m), "2 today")
        XCTAssertEqual(Notices.perDay, 2)
    }

    // MARK: Facts on the Moments that exist

    func testFactsOnExistingMoments() {
        XCTAssertNil(Notices.whileAway([]))
        XCTAssertEqual(Notices.whileAway([("claude", "\"api\"", false)]), "While you were gone, claude finished on \"api\".")
        XCTAssertEqual(Notices.whileAway([("claude", "\"api\"", false), ("codex", "\"blog\"", true), ("claude", "\"x\"", false)]),
                       "While you were gone, claude finished on \"api\", codex failed on \"blog\", 1 more.")
        XCTAssertEqual(Notices.goodnight(turns: 23), "23 turns today.")
        XCTAssertEqual(Notices.goodnight(turns: 1), "1 turn today.")
        XCTAssertNil(Notices.goodnight(turns: 0))

        var old = DayDigest(day: "2026-10-26", weekday: "Monday")
        old.threads = ["api": 3]
        var wall = t0  // Boop's day 2026-11-04
        XCTAssertEqual(Notices.backOn("api", digests: [old], known: false, at: wall, time: time), "First time on \"api\" in 9 days.")
        XCTAssertNil(Notices.backOn("api", digests: [old], known: true, at: wall, time: time), "a turn since the last dream")
        XCTAssertNil(Notices.backOn("blog", digests: [old], known: false, at: wall, time: time), "never: nothing to come back to")
        wall = t0 - 3 * 24 * hour
        XCTAssertNil(Notices.backOn("api", digests: [old], known: false, at: wall, time: time), "under 7 days")
    }

    /// Pins the wish's reasons: quiet in the first two weeks; your morning
    /// stroke an hour past your usual time on 5 of the last 7 days.
    func testAReasonForAWish() {
        var t = MemoryReader.Tallies()
        t.yours = 1
        let days = ["2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03"].map { day -> DayDigest in
            var x = DayDigest(day: day, weekday: "Monday")
            x.strokesAM = 1
            x.strokedAt = "09:00"
            return x
        }
        func reason(_ t: MemoryReader.Tallies, _ ds: [DayDigest], old: Int? = 40, at wall: Int64) -> String? {
            Notices.wishReason(today: t, digests: ds, daysOld: old, at: wall, time: time)
        }
        let ten = t0 - 5 * hour + minute  // 10:01 on 2026-11-04
        XCTAssertNil(reason(t, days, old: 13, at: ten), "too little history")
        XCTAssertEqual(reason(t, days, at: ten), "you usually stroke it in the morning, and not yet today")
        XCTAssertEqual(reason(t, days, at: ten - 2 * minute), "you haven't said hi today", "under an hour past your usual time")
        XCTAssertEqual(reason(t, Array(days.prefix(4)), at: ten), "you haven't said hi today", "4 of 7")
        var touched = t
        touched.touches = 1
        XCTAssertNil(reason(touched, days, at: ten), "you said hi")
        var nobody = t
        nobody.yours = 0
        XCTAssertNil(reason(nobody, days, at: ten), "you've done nothing yet today")
    }

    /// A day that ran past midnight keeps its last event when two dreams join.
    func testADigestsLastRunsPastMidnight() {
        let joined = night("2026-11-03", last: "23:50").joined(with: night("2026-11-03", last: "01:30"))
        XCTAssertEqual(joined.last, "01:30")
        XCTAssertTrue(joined.pastOne)
        XCTAssertEqual(night("2026-11-03", last: "01:30").joined(with: night("2026-11-03", last: "23:50")).last, "01:30")
        XCTAssertEqual(night("2026-11-03", last: "09:00").joined(with: night("2026-11-03", last: "18:00")).last, "18:00")
    }

    func testTheLinesFit() throws {
        try requirePack("boop")
        let lines = RuntimeTests.steering.signs
        for kind in Notices.Kind.allCases {
            let pool = Signs.notice(lines, kind.rawValue, agent: "claude")
            XCTAssertGreaterThanOrEqual(pool.count, 3, "\(kind): several lines each")
        }
        XCTAssertEqual(Signs.notice(lines, "stretch", avoiding: "stretch?").contains("stretch?"), false, "not the last one again")
        XCTAssertTrue(Signs.notice(lines, "waiting").isEmpty, "{agent} needs its agent")
        XCTAssertTrue(lines.filter { $0.tags.first == "notice" }.allSatisfy { !Signs.offered([$0], reading: PromptReading(length: .sentence, kind: .fix, tone: .calm), calendar: []).contains($0.text) },
                      "a prompt's sign never offers one")
        XCTAssertEqual(Signs.replies(RuntimeTests.steering.replies, "bye", calendar: ["night"], turns: 23).contains("23 turns today"), true)
        XCTAssertEqual(Signs.replies(RuntimeTests.steering.replies, "bye", calendar: ["night"], turns: 1).contains { $0.contains("turn") }, false, "under 2")
    }

    // MARK: Through the pipeline

    /// A run with the expect brain, and what it read at each pass.
    func run(_ json: String) async throws -> (result: Eval.Result, states: [String]) {
        try requirePack("boop")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s.json")
        try #"{"name":"n","case":"c","why":"w","checks":{"moves_on_graph":true},\#(json)}"#.write(to: file, atomically: true, encoding: .utf8)
        let states = Lines()
        final class Seeing: Brain, ScenarioBrain, @unchecked Sendable {
            let id = "seeing"
            let inner = ExpectBrain()
            let states: Lines
            init(_ states: Lines) { self.states = states }
            func willRun(_ step: Scenario.Step?, ahead: [String]) { inner.willRun(step, ahead: ahead) }
            func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
                states.add(state)
                return try await inner.answer(state: state, questions: questions, deadline: deadline)
            }
        }
        var eval = Eval(brain: Seeing(states), steering: RuntimeTests.steering)
        eval.debugLog = nil
        let result = try await eval.run(try Scenario(file: file))
        return (result, states.all)
    }

    static let turn = #"{"event":"session started","at":"0s"},{"event":"turn started","at":"1m","prompt":"tidy","reading":{"kind":"docs","tone":"calm"}},{"event":"turn finished","at":"3m","message":"Done.","reading":{"kind":"done","tone":"calm"}}"#

    /// Pins what a wish holds up: a day with no wish holds up nothing, and
    /// one left open holds up every notice but `waiting`, whatever it's waited.
    func testAnOpenWishHoldsAllButWaiting() {
        var m = moment()
        m.hereSince = t0 - Notices.stretchMs
        XCTAssertEqual(Notices.due(m)?.kind, .stretch, "no wish made today holds nothing up")
        m.wishOpen = true
        XCTAssertNil(Notices.due(m), "an open wish holds up stretch")
        m.agents = [idle(for: 20 * minute)]
        XCTAssertEqual(Notices.due(m)?.kind, .waiting, "but never waiting")
    }

    /// Pins what a doze holds up: only `late` comes to a sleeping Boop, and
    /// a wish left open holds that up too, so an idle agent wakes it for neither.
    func testADozeHoldsUpWaitingWishOrNot() {
        var m = moment()
        m.agents = [idle(for: 20 * minute)]
        m.dozing = true
        XCTAssertNil(Notices.due(m), "a doze holds up waiting")
        m.wishOpen = true
        XCTAssertNil(Notices.due(m), "and an open wish doesn't let it through")
        m.dozing = false
        XCTAssertEqual(Notices.due(m)?.kind, .waiting, "awake, an open wish doesn't hold it up")
    }

    /// A notice is offered and played at an idle check-in, with its reason on
    /// the Mac, whether or not a wish has been made today.
    func testANoWishDayHoldsNoNotice() async throws {
        let steps = #""start":"2026-11-04T14:00","steps":[\#(Self.turn),{"event":"wait","at":"35m","brain":{"react.sign":"claude's waiting"}}]"#
        let open = try await run(steps)
        XCTAssertTrue(open.states.last?.contains("Noticed: claude has sat idle") == true, "no wish yet today: " + (open.states.last ?? ""))
        XCTAssertEqual(open.result.timeline.last?.sign, "claude's waiting")

        let met = try await run(#""wish_today":"met",\#(steps)"#)
        XCTAssertTrue(met.states.last?.contains("Noticed: claude has sat idle on \"landing\" for") == true, met.states.last ?? "")
        XCTAssertEqual(met.result.timeline.last?.sign, "claude's waiting")
    }

    /// Pins how a notice plays, so it's no quiet face: it looks up at you
    /// first, with its short reason for the board, by a sign or by the look
    /// alone, and with no face of Jev's in the mood's, small. `waiting` has
    /// its sign, not the look; a rough hour leans in instead.
    func testANoticePlaysALookAndItsReason() throws {
        func play(_ kind: Notices.Kind, _ fact: String, sign: String, face: String = "comfy") -> Moment? {
            var played: Moment?
            let n = Notices.Notice(kind: kind, key: kind.rawValue, fact: fact, short: "short why")
            let lines = TaggedLine.parse("- [notice \(kind.rawValue)] noticed it")
            let react = MomentOutput(queue: { r, _ in played = r }, blocked: { nil }, who: { _ in Moment.Who(agent: "claude", thread: "api") }, signs: lines,
                                     moodFace: { _ in "calm" }, notice: { _, _ in n })
            let checkIn = Event(at: 0, source: .clock, type: .checkIn, specificType: "check_in")
            let log = Transcript.log().view(now: 0)
            _ = react.run([MomentOutput.emotionKey: Answer(choice: face), MomentOutput.sizeKey: Answer(choice: "big"), Signs.questionKey: Answer(choice: sign)],
                          now: checkIn, log: log)
            return played
        }
        let look = try XCTUnwrap(play(.stretch, "you've been here", sign: MomentOutput.noticeLook))
        XCTAssertEqual(look.anim, "notice")
        XCTAssertNil(look.sign)
        XCTAssertEqual(look.reason, "short why")
        let sign = try XCTUnwrap(play(.waiting, "claude sat", sign: "noticed it"))
        XCTAssertEqual(sign.anim, "notice")
        XCTAssertEqual(sign.sign, "noticed it")
        XCTAssertEqual(sign.reason, "short why")
        XCTAssertFalse(sign.low, "a low sign would hide the reason on the board")
        XCTAssertNil(sign.who, "no finish, whose thread would take the sign's place")
        let noLook = play(.waiting, "claude sat", sign: MomentOutput.noticeLook)
        XCTAssertNil(noLook?.anim, "waiting has no look")
        let rough = try XCTUnwrap(play(.rough, "a rough hour", sign: MomentOutput.noticeLook))
        XCTAssertNil(rough.anim)
        XCTAssertEqual(rough.reply, MomentOutput.roughReply)
        let faceless = try XCTUnwrap(play(.late, "late", sign: MomentOutput.noticeLook, face: "none"))
        XCTAssertEqual(faceless.mood, "calm", "held up with no face: the mood's")
        XCTAssertEqual(faceless.loops, 1, "small")
    }

    /// A notice played rests; one left unplayed comes again.
    func testItCountsOnlyOncePlayed() async throws {
        let check = #"{"event":"wait","at":"%@","brain":{"react.sign":"claude's waiting"}%@}"#
        func steps(_ first: String) -> String {
            #""wish_today":"met","start":"2026-11-04T14:00","steps":[\#(Self.turn),\#(String(format: check, "35m", first)),{"event":"wait","at":"70m"}]"#
        }
        // The next check-in is within the waiting hour: 3 min + up to 30 min, twice.
        let played = try await run(steps(""))
        let cut = try await run(steps(#","reaction":"failed: waited too long""#))
        let noticed = { (r: (result: Eval.Result, states: [String])) in r.states.filter { $0.contains("Noticed:") }.count }
        XCTAssertEqual(noticed(played), 1, "it rests once played")
        XCTAssertGreaterThan(noticed(cut), 1, "a moment that didn't play offers it again")
    }

    /// A notice adds to a Moment that exists: your coming back has one pass,
    /// its fact in CONTEXT and its sentence on the Mac, and a finish while
    /// you were away has no Moment of its own later.
    func testANoticeMakesNoSecondMoment() async throws {
        let back = try await run(#""start":"2026-11-04T12:00","steps":[{"event":"session started","at":"0s"},{"event":"turn started","at":"1m","prompt":"go","reading":{"kind":"other","tone":"calm"}},{"event":"away","at":"5m"},{"event":"turn finished","at":"20m","message":"Done.","reading":{"kind":"done","tone":"calm"}},{"event":"back","at":"25m"}]"#)
        let atBack = back.result.timeline.filter { $0.atMs == 25 * minute }
        XCTAssertEqual(atBack.count, 1, "one Moment at your coming back")
        XCTAssertTrue(back.states.last?.contains("Noticed: While you were gone, claude finished on \"landing\".") == true, back.states.last ?? "")
        XCTAssertFalse(back.states.dropLast().contains { $0.contains("Noticed:") }, "only there")

        let prompt = try await run(#""start":"2026-11-04T10:00","days":[{"day":"2026-10-26","weekday":"Monday","threads":{"landing":6}}],"steps":[{"event":"session started","at":"0s"},{"event":"turn started","at":"1m","prompt":"on we go","reading":{"kind":"carry_on","tone":"calm"}},{"event":"turn finished","at":"3m","message":"Done.","reading":{"kind":"done","tone":"calm"}},{"event":"turn started","at":"4m","prompt":"more","reading":{"kind":"carry_on","tone":"calm"}}]"#)
        XCTAssertEqual(prompt.states.filter { $0.contains("Noticed: First time on \"landing\" in 9 days.") }.count, 1, "your first prompt on it today, once")
        XCTAssertEqual(prompt.result.timeline.filter { $0.atMs == minute }.count, 1, "one Moment at that prompt")
    }

    /// `rough` never comes instead of the failure's own reaction: each
    /// failure has its pass and no notice; the quiet check-in after has it,
    /// and Boop leans in close.
    func testARoughHourAfterItsOwnReactions() async throws {
        let fail = (0..<3).map { i in #"{"event":"turn started","at":"\#(1 + i * 4)m","prompt":"fix","reading":{"kind":"fix","tone":"calm"}},{"event":"turn failed","at":"\#(3 + i * 4)m"}"# }.joined(separator: ",")
        let r = try await run(#""wish_today":"met","start":"2026-11-04T14:00","steps":[{"event":"session started","at":"0s"},\#(fail),{"event":"wait","at":"45m","brain":{"react.sign":"i'm here"}}]"#)
        XCTAssertFalse(r.states.dropLast().contains { $0.contains("Noticed:") }, "none before the quiet")
        XCTAssertTrue(r.states.last?.contains("Noticed: a rough hour: 3 failures.") == true, r.states.last ?? "")
        XCTAssertEqual(r.result.timeline.last?.sign, "i'm here")
        XCTAssertEqual(r.result.timeline.last?.reply, MomentOutput.roughReply)
        XCTAssertEqual(r.result.timeline.last?.narration, "a rough hour", "its reason on the board")
    }

    /// A failure is a turn's: three reds in a turn that ends green are no
    /// rough hour, and one turn ending red counts once, not twice.
    func testARoughHourCountsTurnsNotChecks() async throws {
        func turn(from m: Int, ending last: Bool) -> String {
            #"{"event":"turn started","at":"\#(m)m","prompt":"fix","reading":{"kind":"fix","tone":"calm"}},"#
                + (1...3).map { #"{"event":"command","at":"\#(m + $0)m","topic":"tests","failed":true},"# }.joined()
                + #"{"event":"command","at":"\#(m + 4)m","topic":"tests","failed":\#(last)},{"event":"turn finished","at":"\#(m + 5)m","message":"Done.","reading":{"kind":"done","tone":"calm"}}"#
        }
        let green = try await run(#""wish_today":"met","start":"2026-11-04T14:00","steps":[{"event":"session started","at":"0s"},\#(turn(from: 1, ending: false)),{"event":"wait","at":"45m"}]"#)
        XCTAssertFalse(green.states.last?.contains("Noticed: a rough") == true, "ended green: " + (green.states.last ?? ""))
        let two = [1, 7].map { turn(from: $0, ending: true) }.joined(separator: ",")
        let red = try await run(#""wish_today":"met","start":"2026-11-04T14:00","steps":[{"event":"session started","at":"0s"},\#(two),{"event":"wait","at":"45m"}]"#)
        XCTAssertFalse(red.states.last?.contains("Noticed: a rough") == true, "two turns ended red: " + (red.states.last ?? ""))
        let three = [1, 7, 13].map { turn(from: $0, ending: true) }.joined(separator: ",")
        let rough = try await run(#""wish_today":"met","start":"2026-11-04T14:00","steps":[{"event":"session started","at":"0s"},\#(three),{"event":"wait","at":"45m"}]"#)
        XCTAssertTrue(rough.states.last?.contains("Noticed: a rough hour: 3 failures.") == true, rough.states.last ?? "")
    }

    /// Never during a needs-you, and on Quiet none at all.
    func testNeverOverANeedsYouOrOnQuiet() async throws {
        let quiet = try await run(#""talk":"quiet","wish_today":"met","start":"2026-11-04T14:00","steps":[\#(Self.turn),{"event":"wait","at":"35m"}]"#)
        XCTAssertFalse(quiet.states.contains { $0.contains("Noticed:") }, "quiet")
        let waits = try await run(#""wish_today":"met","start":"2026-11-04T14:00","steps":[\#(Self.turn),{"event":"needs you","at":"5m","session":"s2"},{"event":"wait","at":"60m"}]"#)
        XCTAssertFalse(waits.states.contains { $0.contains("Noticed:") }, "a needs-you")
    }

    /// Your goodnight says the day's turns, on the board's lane.
    func testGoodnightSaysTheTurns() async throws {
        let turns = (0..<3).map { i in #"{"event":"turn started","at":"\#(1 + i * 4)m","prompt":"x","reading":{"kind":"other","tone":"calm"}},{"event":"turn finished","at":"\#(3 + i * 4)m","message":"Done.","reading":{"kind":"done","tone":"calm"}}"# }.joined(separator: ",")
        let r = try await run(#""start":"2026-11-04T22:30","steps":[{"event":"session started","at":"0s"},\#(turns),{"event":"lock","at":"20m"}]"#)
        XCTAssertEqual(r.result.timeline.last?.narration, "3 turns today")
    }

    /// CONTEXT's row, in place, within the section's ceiling.
    func testTheRow() {
        let s = ContextSection.section(company: nil, agents: [], noticed: "a rough hour: 3 failures.", at: t0, name: "Boop")
        XCTAssertEqual(s, ContextSection.heading + "\nNoticed: a rough hour: 3 failures.")
    }
}
