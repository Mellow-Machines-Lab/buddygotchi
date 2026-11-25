import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// Your usual (`Normals`): the numbers Boop compares now with, a fold of
/// the transcript and the lines Jev read.
final class NormalsTests: XCTestCase {
    typealias Facts = [String: JSONValue]
    static let utc = LocalTime(timeZone: TimeZone(identifier: "UTC")!)

    /// `minute` past `hour` on the `day`th day after 2026-11-02, in UTC.
    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Int64 {
        1_793_577_600_000 + Int64(day) * 86_400_000 + Int64(hour) * 3_600_000 + Int64(minute) * 60_000
    }

    /// A finish's event and line: a success with `tools` calls, after `minutes`.
    static func won(_ seq: Int, minutes: Int64, tools: Int64 = 3, inARow: Int64 = 0, at: Int64 = 0, outcome: String = "done")
        -> (Event, Line) {
        var e = Event(at: at, source: .claude, type: .turn, phase: .end, specificType: "Stop")
        e.seq = seq
        let ms = minutes * 60_000
        return (e, Line("", facts: ["outcome": .string(outcome), "length_ms": .int(ms), "length": .string(Band.length(ms: ms)),
                                    "tools": .int(tools), "wins_in_a_row": .int(inARow)]))
    }

    /// You back after `minutes` away, the first time today or not.
    static func back(_ seq: Int, minutes: Int64, first: Bool = false, at: Int64 = 0) -> (Event, Line) {
        var e = Event(at: at, source: .mac, type: .presence, phase: .end, specificType: "input")
        e.seq = seq
        var facts: Facts = ["away_ms": .int(minutes * 60_000), "away": .string(Band.away(ms: minutes * 60_000))]
        if first { facts[TranscriptView.firstTodayFact] = true }
        return (e, Line("", facts: facts))
    }

    /// A reaction's record, with the facts given.
    static func record(_ seq: Int, _ facts: Facts, ok: Bool = true, at: Int64 = 0) -> (Event, Line?) {
        var e = Event.did("Boop had a happy moment", for: 1, action: MomentOutput.outputName, by: "brain", ok: ok, facts: facts, at: at)
        e.seq = seq
        return (e, nil)
    }

    func fold(_ run: [(Event, Line?)], into n: Normals = Normals.opening(day: "2026-11-02", Normals())) -> Normals {
        run.reduce(n) { Normals.adding($1.0, line: $1.1, to: $0) }
    }

    // MARK: Each row

    /// Pins the turns' row: a finish that's a success with tools, its
    /// length, the last 50. A failure, a stop, a chat turn, a turn with no
    /// calls and an event with no line add none; its last message's line
    /// counts as the finish it carries.
    func testHowLongYourTurnsTake() {
        XCTAssertEqual(Normals.turnsKept, 50)
        var n = fold([Self.won(1, minutes: 3), Self.won(2, minutes: 9, outcome: "failed"), Self.won(3, minutes: 9, outcome: "stopped"),
                      Self.won(4, minutes: 9, tools: 0), (Self.won(5, minutes: 9).0, nil)])
        XCTAssertEqual(n.turns, [Normals.Kept(seq: 1, value: 180_000)])
        var unsaid = Self.won(8, minutes: 9)
        unsaid.1.facts["length_ms"] = nil
        XCTAssertNil(Normals.win(unsaid.1.facts), "no length: no turn of 0 ms")
        XCTAssertEqual(fold([unsaid], into: n).turns, n.turns)
        var chat = Self.won(6, minutes: 9)
        chat.1.facts["message"] = .object(["kind": "question"])
        var message = Event(at: 0, source: .claude, type: .lastMessage, specificType: "Stop")
        message.seq = 7
        n = fold([chat, (message, Self.won(7, minutes: 4).1)], into: n)
        XCTAssertEqual(n.turns.map(\.value), [180_000, 240_000], "the last message carries the finish; a chat turn isn't one")
        n = fold((10..<70).map { Self.won($0, minutes: Int64($0)) }, into: n)
        XCTAssertEqual(n.turns.count, 50)
        XCTAssertEqual(n.turns.first?.seq, 20, "the last 50")
    }

    /// Pins the first hour's row: the hello marked the first of its Boop
    /// day, once a day, the last 14 days, as minutes after 5:00.
    func testTheHourYouFirstShowUp() {
        XCTAssertEqual(Normals.daysKept, 14)
        let reader = NormalsReader()
        var n = reader.open(day: "2026-11-02", carry: nil)
        n = fold([Self.back(1, minutes: 600, first: true, at: Self.at(0, 9, 30)), Self.back(2, minutes: 30, first: true, at: Self.at(0, 11))],
                 into: n)
        XCTAssertEqual(n.days, [Normals.Day(day: "2026-11-02", firstAt: Self.at(0, 9, 30))], "the first hello only")
        var touch = Event(at: Self.at(0, 12), source: .device, type: .poke, specificType: "input")
        touch.seq = 3
        n = fold([(touch, Line("", facts: [:]))], into: n)
        XCTAssertEqual(n.days.last?.firstAt, Self.at(0, 9, 30))
        for d in 1...20 {
            n = reader.open(day: "2026-11-\(String(format: "%02d", 2 + d))", carry: n)
            if d % 2 == 0 {
                var poke = Event(at: Self.at(d, 8), source: .device, type: .poke, specificType: "input")
                poke.seq = 10 + d
                n = fold([(poke, Line("", facts: [TranscriptView.firstTodayFact: true]))], into: n)
            }
        }
        XCTAssertEqual(n.days.count, 15, "today and the 14 before")
        XCTAssertEqual(n.days.last?.day, "2026-11-22")
        let usual = n.usual(before: 100, minutes: Self.utc.minutesIntoBoopDay)
        XCTAssertEqual(usual.firstMinutes, [180, 180, 180, 180, 180, 180, 180], "the days before today you came, at 8:00")
    }

    /// Pins the breaks' row: a coming back from 10 minutes to 4 hours
    /// away, the last 30.
    func testHowLongYourBreaksAre() {
        XCTAssertEqual(Normals.breaksKept, 30)
        XCTAssertEqual([Normals.breakFromMs, Normals.breakUntilMs], [600_000, 14_400_000])
        var n = fold([Self.back(1, minutes: 9), Self.back(2, minutes: 10), Self.back(3, minutes: 240), Self.back(4, minutes: 241),
                      (Self.back(5, minutes: 60).0, nil)])
        XCTAssertEqual(n.breaks, [Normals.Kept(seq: 2, value: 600_000), Normals.Kept(seq: 3, value: 14_400_000)])
        n = fold((10..<50).map { Self.back($0, minutes: 30) }, into: n)
        XCTAssertEqual(n.breaks.count, 30)
        XCTAssertEqual(n.breaks.first?.seq, 20)
    }

    /// Pins the wins a day: the turns that count, on each Boop day, the
    /// last 14 days before today; today's counts the event it's asked at.
    func testYourWinsADay() {
        let reader = NormalsReader()
        var n = reader.open(day: "2026-11-02", carry: nil)
        n = fold([Self.won(1, minutes: 3), Self.won(2, minutes: 3), Self.won(3, minutes: 3, outcome: "failed")], into: n)
        XCTAssertEqual(n.days.last?.wins, 2)
        for d in 1...16 {
            n = reader.open(day: "2026-11-\(String(format: "%02d", 2 + d))", carry: n)
            n = fold((0..<d).map { Self.won(100 * d + $0, minutes: 3) }, into: n)
        }
        let usual = n.usual(before: 1616, minutes: Self.utc.minutesIntoBoopDay)
        XCTAssertEqual(usual.winsADay, Array(2...15), "the 14 days before today")
        XCTAssertEqual(usual.winsToday, 16, "today's, this one too")
        XCTAssertEqual(reader.open(day: "2026-11-18", carry: n), n, "the day open opens nothing new")
    }

    /// Pins the run of wins: the wins your usual counts (a success with
    /// tools) in a row, whatever the view's quick wins in a row say; a
    /// failed turn ends it, and a chat turn, a turn with no calls or a stop
    /// neither counts nor ends it. The run now is the latest win's; the
    /// best is the most ever, and at the win that set it, the best before it.
    func testYourRunOfWins() {
        var chat = Self.won(3, minutes: 1, inARow: 9)
        chat.1.facts["message"] = .object(["kind": "question"])
        var n = fold([Self.won(1, minutes: 3, inARow: 0), Self.won(2, minutes: 3, inARow: 0), chat, Self.won(4, minutes: 3, tools: 0, inARow: 9),
                      Self.won(5, minutes: 9, outcome: "stopped"), Self.won(6, minutes: 3, inARow: 0)])
        XCTAssertEqual(n.run, Normals.Kept(seq: 6, value: 3), "three wins; the turns between count nothing")
        XCTAssertEqual(n.usual(before: 6, minutes: { _ in 0 }).run, 3, "at the win that made it")
        XCTAssertEqual(n.usual(before: 7, minutes: { _ in 0 }).run, 0, "at an event that's no win")
        XCTAssertEqual(n.usual(before: 6, minutes: { _ in 0 }).bestRun, 2, "the best before the win that set it")
        n = fold([Self.won(7, minutes: 3, inARow: 7, outcome: "failed")], into: n)
        XCTAssertNil(n.run, "a failed turn ends it")
        n = fold([Self.won(8, minutes: 3), Self.won(9, minutes: 3)], into: n)
        XCTAssertEqual(n.run?.value, 2)
        XCTAssertEqual(n.bestRun, Normals.Kept(seq: 6, value: 3), "the most ever")
        XCTAssertEqual(n.usual(before: 9, minutes: { _ in 0 }).bestRun, 3)
    }

    /// Pins the skits since the last remark: none counted before the first
    /// remark; a remark starts again from 0; each skit after it adds one; a
    /// record with neither, or one that failed, changes nothing.
    func testSkitsSinceTheLastRemark() {
        var n = fold([Self.record(1, ["skit": "win"]), Self.record(2, ["skit": "back"])])
        XCTAssertNil(n.skitsSinceRemark, "no remark yet")
        n = fold([Self.record(3, ["skit": "win", Normals.remarkFact: "fast"])], into: n)
        XCTAssertEqual(n.skitsSinceRemark, 0)
        n = fold([Self.record(4, ["skit": "upset"]), Self.record(5, ["takes": .array([])]), Self.record(6, ["skit": "win"], ok: false)], into: n)
        XCTAssertEqual(n.skitsSinceRemark, 1)
        n = fold([Self.record(7, [Normals.remarkFact: "early"])], into: n)
        XCTAssertEqual(n.skitsSinceRemark, 0, "a remark on a skit that didn't speak")
    }

    /// Pins that a record counts once the board played it: one in progress
    /// counts at its `ended` done; one skipped late or cut, never.
    func testOnlyWhatPlayedCounts() {
        func open(_ seq: Int, _ facts: Facts) -> (Event, Line?) {
            var r = Self.record(seq, facts)
            r.0.data["open"] = true
            return r
        }
        func ended(_ seq: Int, failed: String? = nil) -> (Event, Line?) {
            (Event.ended(seq, action: MomentOutput.outputName, by: "brain", failed: failed), nil)
        }
        var n = fold([Self.record(1, ["skit": "win", Normals.remarkFact: "fast"])])
        XCTAssertEqual(n.skitsSinceRemark, 0)
        n = fold([open(2, ["skit": "win"]), open(3, [Normals.remarkFact: "fast"])], into: n)
        XCTAssertEqual(n.skitsSinceRemark, 0, "neither has played yet")
        n = fold([ended(2), ended(3, failed: "waited too long")], into: n)
        XCTAssertEqual(n.skitsSinceRemark, 1, "the skit played, its remark was skipped late")
        n = fold([open(4, ["skit": "back"]), ended(4, failed: "cut short: something needed you")], into: n)
        XCTAssertEqual(n.skitsSinceRemark, 1, "cut")
        n = fold([open(5, ["skit": "win", Normals.remarkFact: "run"]), ended(5)], into: n)
        XCTAssertEqual(n.skitsSinceRemark, 0)
        XCTAssertTrue(n.playing.open.isEmpty)
    }

    /// Pins the median: the middle one, or the mean of the middle two.
    func testTheMedian() {
        XCTAssertNil(Normals.median([]))
        XCTAssertEqual(Normals.median([5, 1, 3]), 3)
        XCTAssertEqual(Normals.median([4, 1, 3, 10]), 3)
    }

    // MARK: The day and the transcript

    /// Pins Boop's day at 5:00: an event at 4:59 is the day before's, one
    /// at 5:00 opens a day; minutes after 5:00 run from 0 to 1439.
    func testBoopsDayStartsAtFive() throws {
        let store = try KeyValueStore(directory: nil)
        let normals = Checkpointed(NormalsReader(), store: store, time: Self.utc)
        let (late, lateLine) = Self.won(1, minutes: 3, at: Self.at(1, 4, 59))
        let (five, fiveLine) = Self.won(2, minutes: 3, at: Self.at(1, 5))
        normals.feed(late, line: lateLine)
        XCTAssertEqual(normals.state?.days.map(\.day), ["2026-11-02"])
        normals.feed(five, line: fiveLine)
        XCTAssertEqual(normals.state?.days, [Normals.Day(day: "2026-11-02", wins: 1), Normals.Day(day: "2026-11-03", wins: 1)])
        XCTAssertEqual(Self.utc.minutesIntoBoopDay(Self.at(1, 5)), 0)
        XCTAssertEqual(Self.utc.minutesIntoBoopDay(Self.at(1, 4, 59)), 1439)
        XCTAssertEqual(Self.utc.minutesIntoBoopDay(Self.at(1, 9, 30)), 270)
    }

    /// Your usual is the transcript's view, not a store of its own: the
    /// memory keeps it as it reads each event, and reading the recorded run
    /// again gives the same; a new memory on the same store picks it up.
    func testYourUsualIsTheTranscriptsFold() throws {
        let store = try KeyValueStore(directory: nil)
        let memory = Memory(store: store, time: Self.utc)
        var seq = 0
        func numbered(_ e: (Event, Line?)) -> (Event, Line?) {
            seq += 1
            var x = e.0
            x.seq = seq
            return (x, e.1)
        }
        var run: [(Event, Line?)] = []
        for d in 0..<3 {
            run.append(numbered(Self.back(0, minutes: 600, first: true, at: Self.at(d, 8 + d))))
            run.append(numbered(Self.won(0, minutes: Int64(3 + d), inARow: Int64(d), at: Self.at(d, 10))))
            run.append(numbered(Self.record(0, ["skit": "win", Normals.remarkFact: "fast"], at: Self.at(d, 10))))
            run.append(numbered(Self.back(0, minutes: 40, at: Self.at(d, 12))))
            run.append(numbered(Self.record(0, ["skit": "back"], at: Self.at(d, 12))))
        }
        for (e, line) in run { memory.heard(e, line: line) }
        let kept = try XCTUnwrap(memory.normals.state)
        let again = Checkpointed(NormalsReader(), store: try KeyValueStore(directory: nil), time: Self.utc)
        for (e, line) in run { again.feed(e, line: line) }
        XCTAssertEqual(kept, again.state)
        XCTAssertEqual(kept.days.map(\.wins), [1, 1, 1])
        XCTAssertEqual(kept.turns.count, 3)
        XCTAssertEqual(kept.breaks.count, 3)
        XCTAssertEqual(kept.skitsSinceRemark, 1)
        XCTAssertEqual(Memory(store: store, time: Self.utc).normals.state, kept, "kept across a launch")

        // A launch that missed the last day's events catches up on them,
        // with the lines the harness read them back with: the same usual.
        let early = try KeyValueStore(directory: nil), cut = run.count - 5
        let before = Memory(store: early, time: Self.utc)
        for (e, line) in run.prefix(cut) { before.heard(e, line: line) }
        let launched = Memory(store: early, time: Self.utc)
        let lines = Dictionary(uniqueKeysWithValues: run.compactMap { e, line in line.map { (e.seq, $0) } })
        launched.catchUp(run.suffix(from: cut).map(\.0), lines: { lines[$0] })
        XCTAssertEqual(launched.normals.state, kept, "caught up")
    }
}
