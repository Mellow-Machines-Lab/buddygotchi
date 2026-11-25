import AgentHooks
import Foundation
import LinkKit
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The remarks: Boop compares now with your usual (`Normals`) and says the
/// difference, as text on a skit that plays anyway (`Remarks`).
final class RemarksTests: XCTestCase {
    typealias Facts = [String: JSONValue]

    /// A usual: `turns` turns of 20 minutes, `firsts` days you first came at
    /// 9:00 (240 minutes after 5:00), `breaks` breaks of an hour, each past
    /// day's wins, today's, your best run, and the skits since a remark.
    func usual(turns: Int = 10, firsts: Int = 5, breaks: Int = 5, days: [Int] = [2, 2, 2, 2, 2], today: Int = 1, best: Int64 = 0,
               since: Int? = nil) -> Normals.Usual {
        var u = Normals.Usual()
        u.turnsMs = Array(repeating: 20 * 60_000, count: turns)
        u.firstMinutes = Array(repeating: 240, count: firsts)
        u.breaksMs = Array(repeating: 60 * 60_000, count: breaks)
        u.winsADay = days
        u.winsToday = today
        u.bestRun = best
        u.skitsSinceRemark = since
        return u
    }

    func win(minutes: Int64 = 20, tools: Int64 = 3, inARow: Int64 = 0) -> Facts {
        let ms = minutes * 60_000
        return ["outcome": "done", "length_ms": .int(ms), "length": .string(Band.length(ms: ms)), "tools": .int(tools),
                "wins_in_a_row": .int(inARow)]
    }

    func back(minutes: Int64 = 60, first: Bool = false) -> Facts {
        var f: Facts = ["away_ms": .int(minutes * 60_000), "away": .string(Band.away(ms: minutes * 60_000))]
        if first { f[TranscriptView.firstTodayFact] = true }
        return f
    }

    func pick(_ skit: String, _ facts: Facts, _ usual: Normals.Usual, minutes: Int = 240, quiet: Bool = false) -> String? {
        Remarks.pick(skit: skit, facts: facts, usual: usual, minutes: minutes, quiet: quiet)
    }

    /// The remark on a `win`.
    func pick(_ facts: Facts, _ usual: Normals.Usual, quiet: Bool = false) -> String? { pick("win", facts, usual, quiet: quiet) }

    // MARK: Each row

    /// Pins `fast` and `slow`: a win under half your median turn, or over
    /// twice it, with 10 turns kept; only a turn your usual counts, a
    /// success with tools.
    func testFastAndSlow() {
        XCTAssertEqual(Remarks.turnsNeeded, 10)
        XCTAssertEqual(pick(win(minutes: 9), usual()), "fast")
        XCTAssertNil(pick(win(minutes: 10), usual()), "half is no less")
        XCTAssertEqual(pick(win(minutes: 41), usual()), "slow")
        XCTAssertNil(pick(win(minutes: 40), usual()), "twice is no more")
        XCTAssertNil(pick(win(minutes: 9), usual(turns: 9)), "9 turns kept")
        XCTAssertNil(pick(win(minutes: 41), usual(turns: 9)))
        XCTAssertNil(pick(win(minutes: 9, tools: 0), usual()), "no calls: not a turn your usual counts")
    }

    /// Pins `run`: the 3rd win in a row, or a new best run of 4 or more.
    func testRun() {
        XCTAssertEqual([Remarks.runAt, Remarks.bestRunFrom], [3, 4])
        XCTAssertEqual(pick(win(inARow: 3), usual(best: 9)), "run")
        XCTAssertNil(pick(win(inARow: 2), usual()))
        XCTAssertEqual(pick(win(inARow: 4), usual(best: 3)), "run", "a new best")
        XCTAssertNil(pick(win(inARow: 4), usual(best: 4)), "the same best isn't new")
        XCTAssertNil(pick(win(inARow: 5), usual(best: 6)))
        XCTAssertEqual(pick(win(inARow: 7), usual(best: 6)), "run")
        XCTAssertEqual(pick(win(inARow: 3), usual(turns: 2, firsts: 0, breaks: 0, days: [])), "run", "it needs nothing kept but a usual")
    }

    /// Pins `count`: today's wins just reached 5 or 10, or just passed your
    /// best day of the last 14, with 5 days kept for that.
    func testCount() {
        XCTAssertEqual(Remarks.winCounts, [5, 10])
        XCTAssertEqual(pick(win(), usual(days: [], today: 5)), "count")
        XCTAssertEqual(pick(win(), usual(days: [], today: 10)), "count")
        XCTAssertNil(pick(win(), usual(days: [], today: 6)))
        XCTAssertEqual(pick(win(), usual(days: [2, 1, 2, 0, 2], today: 3)), "count", "past your best day")
        XCTAssertNil(pick(win(), usual(days: [2, 1, 2, 0, 2], today: 4)), "past it already")
        XCTAssertNil(pick(win(), usual(days: [2, 2, 2, 2], today: 3)), "4 days kept")
        XCTAssertNil(pick(win(tools: 0), usual(days: [], today: 5)), "a turn that isn't counted reached nothing")
        XCTAssertEqual(Remarks.number("count", facts: win(), usual: usual(today: 5)), 5)
        XCTAssertEqual(Remarks.number("run", facts: win(inARow: 3), usual: usual()), 3)
        XCTAssertNil(Remarks.number("fast", facts: win(), usual: usual()))
    }

    /// Pins `early` and `late`: the first time you show up today, 45
    /// minutes or more before or after your median first hour, with 5 days kept.
    func testEarlyAndLate() {
        XCTAssertEqual([Remarks.earlyLateMinutes, Remarks.daysNeeded], [45, 5])
        XCTAssertEqual(pick("back", back(first: true), usual(), minutes: 195), "early")
        XCTAssertNil(pick("back", back(first: true), usual(), minutes: 196))
        XCTAssertEqual(pick("back", back(first: true), usual(), minutes: 285), "late")
        XCTAssertNil(pick("back", back(first: true), usual(), minutes: 284))
        XCTAssertNil(pick("back", back(), usual(), minutes: 60), "not the first time today")
        XCTAssertNil(pick("back", back(first: true), usual(firsts: 4), minutes: 60), "4 days kept")
    }

    /// Pins `soon` and `longBreak`: away under half your median break, or
    /// over twice it and under 4 hours, with 5 breaks kept.
    func testSoonAndALongBreak() {
        XCTAssertEqual(Remarks.breaksNeeded, 5)
        XCTAssertEqual(pick("back", back(minutes: 29), usual()), "soon")
        XCTAssertNil(pick("back", back(minutes: 30), usual()))
        XCTAssertEqual(pick("back", back(minutes: 121), usual()), "longBreak")
        XCTAssertNil(pick("back", back(minutes: 120), usual()))
        XCTAssertNil(pick("back", back(minutes: 240), usual()), "4 hours is no break")
        XCTAssertNil(pick("back", back(minutes: 29), usual(breaks: 4)), "4 breaks kept")
    }

    /// Pins the order: when two fit, the first in the table wins.
    func testTheFirstThatFitsWins() {
        XCTAssertEqual(Remarks.all, ["fast", "slow", "run", "count", "early", "late", "soon", "longBreak"])
        XCTAssertEqual(pick(win(minutes: 9, inARow: 3), usual(today: 5)), "fast")
        XCTAssertEqual(pick(win(minutes: 41, inARow: 3), usual(today: 5)), "slow")
        XCTAssertEqual(pick(win(inARow: 3), usual(today: 5)), "run")
        XCTAssertEqual(pick("back", back(minutes: 29, first: true), usual(), minutes: 60), "early")
        XCTAssertEqual(pick("back", back(minutes: 121, first: true), usual(), minutes: 400), "late")
    }

    /// Pins one skit in three: none on the two skits after one that carried
    /// a remark; any before the first remark.
    func testOneSkitInThree() {
        XCTAssertEqual(Remarks.every, 3)
        let fast = win(minutes: 9)
        XCTAssertEqual(pick(fast, usual(since: nil)), "fast")
        XCTAssertNil(pick(fast, usual(since: 0)))
        XCTAssertNil(pick(fast, usual(since: 1)))
        XCTAssertEqual(pick(fast, usual(since: 2)), "fast")
        XCTAssertEqual(pick(fast, usual(since: 7)), "fast")
    }

    /// Pins the rest: on Quiet, none; `upset` and `fix` never carry one,
    /// nor does a skit the remark isn't for; nor a new buddy's empty usual,
    /// not even the run, which needs nothing more.
    func testQuietAndTheOtherSkits() {
        XCTAssertNil(pick(win(minutes: 9), usual(), quiet: true))
        XCTAssertNil(pick("back", back(minutes: 29), usual(), quiet: true))
        for skit in ["upset", "fix"] {
            XCTAssertNil(pick(skit, win(minutes: 9, inARow: 3), usual(today: 5)), skit)
            XCTAssertNil(pick(skit, back(minutes: 29, first: true), usual(), minutes: 60), skit)
        }
        XCTAssertNil(pick("back", win(minutes: 9, inARow: 3), usual(today: 5)), "a win's are the win's")
        XCTAssertNil(pick("win", back(minutes: 29, first: true), usual(), minutes: 60), "and a back's the back's")
        let empty = Normals().usual(before: 100, minutes: { _ in 0 })
        XCTAssertTrue(empty.isEmpty)
        for facts in [win(minutes: 1), win(minutes: 99), win(inARow: 3), win(inARow: 4)] { XCTAssertNil(pick(facts, empty)) }
        for facts in [back(minutes: 1, first: true), back(minutes: 200, first: true)] { XCTAssertNil(pick("back", facts, empty, minutes: 0)) }
    }

    // MARK: The pack

    /// Both packs have words for every remark `Remarks` can return, each
    /// fitting a sign once `{n}` is filled in.
    func testThePacksHaveEveryRemarksWords() throws {
        for pack in try SkitTests.packs() {
            let signs = try Steering(directory: pack.directory.appendingPathComponent("steering")).signs
            for id in Remarks.all {
                let lines = Signs.remark(signs, id, n: 10)
                XCTAssertFalse(lines.isEmpty, "\(pack.id): no words for \(id)")
                for line in lines { XCTAssertLessThanOrEqual(line.count, Signs.maxLength, "\(pack.id): \(line)") }
            }
            XCTAssertEqual(Signs.remark(signs, "run", n: 3).first, "3 in a row", pack.id)
            XCTAssertEqual(Signs.remark(signs, "count", n: nil), [], "\(pack.id): a {n} line with no number is left out")
        }
    }

    // MARK: The Moment

    /// The usual the react output reads in these: 10 turns of 20 minutes,
    /// 5 days you first came at 9:00, 5 breaks of an hour, all before seq 100.
    static var kept: Normals {
        var n = Normals()
        n.turns = (1...10).map { Normals.Kept(seq: $0, value: 20 * 60_000) }
        n.breaks = (11...15).map { Normals.Kept(seq: $0, value: 60 * 60_000) }
        n.days = (1...5).map { Normals.Day(day: "2026-12-\(18 + $0)", firstAt: 240 * 60_000, wins: 2) } + [Normals.Day(day: "2026-12-24")]
        return n
    }

    /// The rig, remarking by `normals`, minutes after 5:00 being the time's minutes.
    func rig(_ normals: Normals? = RemarksTests.kept) -> InviteRig {
        let rig = InviteRig()
        rig.react.remarking = MomentOutput.Remarking(normals: { normals }, minutes: { Int($0 / 60_000) % 1440 })
        return rig
    }

    static func finish() -> Event {
        var e = Event(at: 1000, source: .claude, type: .turn, phase: .end, specificType: "Stop")
        e.seq = 100
        return e
    }

    static func cameBack() -> Event {
        var e = Event(at: 60 * 60_000, source: .mac, type: .presence, phase: .end, specificType: "input")
        e.seq = 100
        return e
    }

    /// A `win` far faster than your usual shows `fast` as a low Moment after
    /// the finish, in the face Boop shows; the record says it, and HISTORY's
    /// line holds up its sign. The invite rides that last Moment.
    func testAFastWinsRemarkIsALowMomentAfter() throws {
        try requirePack("boop", "pixel")
        let rig = rig()
        rig.inviting()
        let result = try XCTUnwrap(rig.run(Self.finish(), win(minutes: 2)))
        XCTAssertEqual(rig.sent.count, 2)
        let words = try XCTUnwrap(rig.sent.last?.sign)
        XCTAssertTrue(Signs.remark(RuntimeTests.steering.signs, "fast").contains(words), words)
        XCTAssertEqual(rig.sent.last?.low, true)
        XCTAssertEqual(rig.sent.last?.mood, rig.sent.first?.mood)
        XCTAssertNil(rig.sent.first?.sign, "the finish holds up nothing else")
        XCTAssertEqual(rig.sent.first?.outcome, "success")
        XCTAssertNil(rig.sent.first?.invite)
        XCTAssertEqual(rig.sent.last?.invite?.pose, .palm, "the invite on the last Moment queued")
        XCTAssertEqual(result.facts[Normals.remarkFact], "fast")
        XCTAssertNil(result.facts["offered_line"])
        XCTAssertTrue(result.message.contains(#", holding up a sign: "\#(words)""#), result.message)
    }

    /// The agent's offered line wins: no remark after it.
    func testTheAgentsLineWins() throws {
        try requirePack("boop", "pixel")
        let rig = rig()
        var card = Card(kind: .result, text: "shipped the nav")
        card.lines = [Card.Line(says: "all green", feeling: "happy")]
        rig.card = card
        let result = try XCTUnwrap(rig.run(Self.finish(), win(minutes: 2)))
        XCTAssertEqual(rig.sent.map(\.sign), [nil, "all green"])
        XCTAssertNil(result.facts[Normals.remarkFact])
    }

    /// A `back` holds its remark up as the Moment's sign, unless the hello
    /// has one of its own: a special day's sign, the dream told, or what
    /// happened while you were away.
    func testABacksRemarkIsItsSign() throws {
        try requirePack("boop", "pixel")
        let early = back(minutes: 600, first: true)
        let plain = rig()
        let result = try XCTUnwrap(plain.run(Self.cameBack(), early))
        XCTAssertEqual(plain.sent.count, 1)
        let words = try XCTUnwrap(plain.sent.last?.sign)
        XCTAssertTrue(Signs.remark(RuntimeTests.steering.signs, "early").contains(words), words)
        XCTAssertEqual(result.facts[Normals.remarkFact], "early")
        XCTAssertEqual(result.facts["sign"]?.string, words)
        let extras: [(String, JSONValue)] = [(TranscriptView.daySignFact, "happy holidays!"), ("dream_tags", .array(["you"])),
                                             (TranscriptView.noticedFact, "claude finished")]
        for (extra, value) in extras {
            var facts = early
            facts[extra] = value
            let rig = rig()
            let result = try XCTUnwrap(rig.run(Self.cameBack(), facts))
            XCTAssertNil(result.facts[Normals.remarkFact], extra)
            if extra == TranscriptView.daySignFact { XCTAssertEqual(rig.sent.last?.sign, "happy holidays!") }
            XCTAssertFalse(Signs.remark(RuntimeTests.steering.signs, "early").contains(rig.sent.last?.sign ?? ""), extra)
        }
    }

    /// With your usual empty, a new buddy's, or with nothing to remark by,
    /// every Moment is byte for byte as before remarks, and so is its record.
    func testAnEmptyUsualChangesNoMoment() throws {
        let finish = Self.finish()
        var failed = Event(at: 1000, source: .claude, type: .turn, phase: .end, specificType: "StopFailure")
        failed.seq = 100
        var check = Event(at: 1000, source: .claude, type: .tool, phase: .end, specificType: "PostToolUse")
        check.seq = 100
        var poke = Event(at: 1000, source: .device, type: .poke, specificType: "input")
        poke.seq = 100
        let events: [(Event, Facts, String)] = [
            (finish, win(minutes: 2, inARow: 3), "proud"), (finish, win(minutes: 90), "happy"),
            (failed, ["outcome": "failed", "length_ms": 400_000, "length": "very long", "tools": 9], "sad"),
            (check, ["topic": "tests", "result": "ok", "failed_before": 2], "pleased"),
            (Self.cameBack(), back(minutes: 15, first: true), "happy"), (Self.cameBack(), back(minutes: 200), "happy"),
            (poke, [:], "amused"),
        ]
        func played(_ normals: Normals?, remarking: Bool = true) -> [String] {
            let rig = remarking ? rig(normals) : InviteRig()
            return events.map { e, facts, face in
                let result = rig.run(e, facts, face: face)
                return (rig.sent.map(\.args.json) + [result?.message ?? "-", result.map { $0.facts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") } ?? "-"]).joined(separator: "\n")
            }
        }
        let before = played(nil, remarking: false)
        XCTAssertEqual(played(nil), before, "no usual")
        XCTAssertEqual(played(Normals.opening(day: "2026-12-24", Normals())), before, "a new buddy's: nothing kept, nothing said")
        XCTAssertNotEqual(played(Self.kept), before, "a usual kept gets remarks")
    }

    // MARK: Through the runtime

    /// `hour`:`minute` local time on December 19, 2026, plus `day` days.
    static func local(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Int64 {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: .current, year: 2026, month: 12, day: 19 + day,
                                                                              hour: hour, minute: minute))!
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    /// Through the runtime with a fake board: ten wins of 20 minutes over
    /// five days, and you first there at 9:00 each; on the sixth, a win of
    /// 2 minutes shows `fast` as a second low Moment and records it; the
    /// next two skits carry none; and you back at 7:00, early, on a special
    /// day, keeps the day's sign.
    func testThroughTheRuntime() throws {
        try requirePack("boop", "pixel")
        let dir = URL(fileURLWithPath: "/tmp/boop-rem-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = VirtualClock(Self.local(0, 8))
        let transport = FakeTransport()
        let runtime = try InviteTests().runtime(dir, transport, clock)
        var now: Int64 { clock.now }
        func hook(_ name: String, tool: String? = nil) {
            runtime.hook(HookLine(agent: "claude", hook: name, session: "s1", cwd: "/tmp/proj", tool: tool, ts: now), received: now)
        }
        func win(minutes: Int64) {
            hook("UserPromptSubmit")
            clock.now += 1000
            hook("PreToolUse", tool: "Edit")
            hook("PostToolUse", tool: "Edit")
            clock.now += minutes * 60_000 - 1000
            hook("Stop")
        }
        func pass() { _ = runtime.harness.force([MomentOutput.emotionKey: "happy"], by: Runtime.forcedBy) }
        func args(_ line: String) -> [String: Any] {
            let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            return o?["args"] as? [String: Any] ?? [:]
        }
        /// The Moments sent from the `do` numbered `from`, not the work stream's calls.
        func moments(from: Int) -> [[String: Any]] {
            transport.dos[from...].filter { !$0.contains(#""name":"call""#) }.map(args)
        }
        func record() -> Event? {
            runtime.harness.log.view(now: now).events.last { $0.kind == Event.did && $0.action == MomentOutput.outputName }
        }
        func normals() -> Normals? { runtime.remembers?.normals.state }
        runtime.home.sync {
            runtime.connection(true)
            runtime.device(FakeTransport.hello)
            for d in 0..<5 {
                clock.now = Self.local(d, 9)
                runtime.device(#"{"t":"ev","kind":"tap","did":"poked","data":{"src":"screen"}}"#)
                win(minutes: 20)
                clock.now += 60 * 60_000
                win(minutes: 20)
            }
            XCTAssertEqual(normals()?.turns.count, 10, "ten wins with calls")
            XCTAssertEqual(normals()?.days.compactMap(\.firstAt).count, 5, "five days you came")
            XCTAssertNil(normals()?.skitsSinceRemark)

            // The sixth day: a win far faster than the ten.
            clock.now = Self.local(5, 6)
            let sent = transport.dos.count
            win(minutes: 2)
            pass()
            let fast = moments(from: sent)
            XCTAssertEqual(fast.count, 2, "the finish, then the remark")
            XCTAssertNil(fast.first?["sign"])
            XCTAssertEqual(fast.last?["low"] as? Bool, true)
            let words = try? XCTUnwrap(fast.last?["sign"] as? String)
            XCTAssertTrue(Signs.remark(RuntimeTests.steering.signs, "fast").contains(words ?? ""), "\(fast)")
            XCTAssertEqual(record()?[Normals.remarkFact]?.string, "fast")
            XCTAssertEqual(normals()?.skitsSinceRemark, 0)

            // The next two skits: none, though the second just passed your best day.
            for n in 1...2 {
                clock.now += 60_000
                let before = transport.dos.count
                win(minutes: 2)
                pass()
                XCTAssertEqual(moments(from: before).count, 1, "skit \(n): the finish alone")
                XCTAssertNil(record()?[Normals.remarkFact], "skit \(n)")
                XCTAssertNotNil(record()?["skit"], "skit \(n) spoke")
            }
            XCTAssertEqual(normals()?.skitsSinceRemark, 2)
            XCTAssertEqual(normals()?.days.last?.wins, 3)

            // Away, and back at 7:00, early, on December 24: the day's sign wins.
            clock.now = Self.local(5, 6, 30)
            runtime.pipeline.presence(Event(at: now, source: .mac, type: .presence, phase: .start, specificType: "idle",
                                            data: ["since": .int(now)]))
            clock.now = Self.local(5, 7)
            let back = runtime.pipeline.presence(Event(at: now, source: .mac, type: .presence, phase: .end, specificType: "input"))
            _ = back
            let came = try? XCTUnwrap(runtime.harness.log.view(now: now).events.last { $0.type == .presence && $0.phase == .end })
            let facts = came.flatMap { runtime.harness.line($0.seq)?.facts } ?? [:]
            XCTAssertNotNil(facts[TranscriptView.firstTodayFact], "the first time today")
            let day = facts[TranscriptView.daySignFact]?.string
            XCTAssertNotNil(day, "a special day")
            // It would be early but for the day's sign.
            if let came, let n = normals() {
                let time = LocalTime()
                XCTAssertEqual(Remarks.pick(skit: "back", facts: facts, usual: n.usual(before: came.seq, minutes: time.minutesIntoBoopDay),
                                            minutes: time.minutesIntoBoopDay(came.at), quiet: false), "early")
            }
            let before = transport.dos.count
            pass()
            let backs = moments(from: before)
            XCTAssertEqual(backs.count, 1)
            XCTAssertEqual(backs.last?["sign"] as? String, day, "the day's sign wins")
            XCTAssertNil(record()?[Normals.remarkFact])
        }
    }
}
