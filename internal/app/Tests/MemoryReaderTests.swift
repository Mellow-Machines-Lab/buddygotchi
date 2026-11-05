import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// Boop's memory: its day, the checkpointed readers that run it, the
/// day's tallies, the dream of everything since the last (when it comes,
/// what it covers, its preview), and its telling the first time you show
/// up after it.
final class MemoryReaderTests: XCTestCase {
    let utc = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
    let hour: Int64 = 3_600_000

    /// `y-m-d h:m` in `zone`, in ms.
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, zone: String = "UTC") -> Int64 {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return Int64(c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!.timeIntervalSince1970 * 1000)
    }

    /// LocalTime.boopDayStartHour: Boop's day runs from 5:00 to 5:00, named
    /// for the date it starts on, by the calendar, so the 23- and 25-hour
    /// days of summer time are one day each.
    func testBoopsDayRunsFromFiveToFive() {
        XCTAssertEqual(LocalTime.boopDayStartHour, 5)
        XCTAssertEqual(utc.boopDay(at(2026, 10, 27, 4, 59)), "2026-10-26", "work until before 5:00 is the day before")
        XCTAssertEqual(utc.boopDay(at(2026, 10, 27, 5, 0)), "2026-10-27")
        XCTAssertEqual(utc.boopDay(at(2026, 10, 27, 0, 30)), "2026-10-26", "a night owl's evening stays whole")
        let london = LocalTime(timeZone: TimeZone(identifier: "Europe/London")!)
        // Summer time starts on 29 March 2026 and ends on 25 October.
        XCTAssertEqual(london.boopDay(at(2026, 3, 29, 4, 59, zone: "Europe/London")), "2026-03-28")
        XCTAssertEqual(london.boopDay(at(2026, 3, 29, 5, 0, zone: "Europe/London")), "2026-03-29")
        XCTAssertEqual(london.boopDay(at(2026, 10, 25, 4, 59, zone: "Europe/London")), "2026-10-24")
        XCTAssertEqual(london.boopDay(at(2026, 10, 25, 5, 0, zone: "Europe/London")), "2026-10-25")
        XCTAssertEqual(utc.weekday(of: "2026-10-26"), "Monday")
    }

    func poke(_ seq: Int, _ ms: Int64) -> Event {
        Event(seq: seq, at: ms, source: .device, type: .poke, specificType: "input")
    }

    /// Your company: only your touches and words count as touching Boop
    /// (a prompt is yours, but it's to an agent); coming back is kept; a
    /// mood leaving lonely is kept; all of it carried across 5:00.
    func testTheCompanyCountsOnlyYoursAndCarries() throws {
        let reader = MemoryReader(store: try KeyValueStore(directory: nil), time: utc)
        var t = reader.open(day: "2026-10-27", carry: nil)
        let morning = at(2026, 10, 27, 9)
        _ = reader.read(Event(seq: 1, at: morning, source: .mac, type: .presence, phase: .end, specificType: "unlocked"), line: nil, into: &t)
        _ = reader.read(Event(seq: 2, at: morning + hour, source: .claude, type: .prompt, specificType: "UserPromptSubmit"), line: nil, into: &t)
        _ = reader.read(Event(seq: 3, at: morning + hour, source: .clock, type: .checkIn, specificType: "check_in"), line: nil, into: &t)
        XCTAssertNil(t.touchedAt, "a prompt or a check-in isn't touching Boop")
        XCTAssertEqual(t.backAt, morning)
        _ = reader.read(Event(seq: 4, at: morning + 2 * hour, source: .device, type: .gesture, specificType: "stroke"), line: nil, into: &t)
        _ = reader.read(Event(seq: 5, at: morning + 2 * hour, source: .device, type: .gesture, specificType: "facedown"), line: nil, into: &t)
        XCTAssertEqual(t.touchedAt, morning + 2 * hour)
        _ = reader.read(Event.did("Boop's mood changed: lonely → affectionate.", for: 4, action: MoodOutput.outputName, by: "brain",
                                  facts: ["from": "lonely", "to": "affectionate"], at: morning + 2 * hour), line: nil, into: &t)
        XCTAssertEqual(t.lonelyEndedAt, morning + 2 * hour)
        let next = reader.open(day: "2026-10-28", carry: t)
        XCTAssertEqual([next.touchedAt, next.backAt, next.lonelyEndedAt], [t.touchedAt, t.backAt, t.lonelyEndedAt])
        XCTAssertEqual(next.turns, 0, "the tallies start again")
    }

    /// Checkpointed: in order and once; the day closes before an event of a
    /// later day is read, and on the tick once the wall clock is past it;
    /// the checkpoint, kept in the store, carries on in a new launch, and
    /// follows a transcript that starts again.
    func testACheckpointedReaderReadsInOrderOnceAndClosesItsDays() throws {
        let store = try KeyValueStore(directory: nil)
        let reader = CountingReader()
        let runner = Checkpointed(reader, store: store, time: utc)
        let monday = at(2026, 10, 26, 9)
        runner.feed(poke(1, monday), line: nil)
        runner.feed(poke(2, monday + hour), line: nil)
        runner.feed(poke(2, monday + hour), line: nil)  // again: skipped
        XCTAssertEqual(runner.state, 2)
        XCTAssertEqual(runner.seq, 2)
        runner.feed(poke(3, at(2026, 10, 27, 6)), line: nil)
        XCTAssertEqual(reader.closed, ["2026-10-26 2 live"])
        XCTAssertEqual(runner.day, "2026-10-27")
        runner.tick(wall: at(2026, 10, 28, 4, 59))
        XCTAssertEqual(reader.closed.count, 1, "not yet")
        runner.tick(wall: at(2026, 10, 28, 5))
        XCTAssertEqual(reader.closed.last, "2026-10-27 1 live")
        runner.feed(poke(4, at(2026, 10, 28, 7)), line: nil, live: false)
        // A new launch reads the checkpoint back.
        let again = Checkpointed(CountingReader(), store: store, time: utc)
        XCTAssertEqual(again.seq, 4)
        XCTAssertEqual(again.day, "2026-10-28")
        XCTAssertEqual(again.state, 1)
        again.follow(transcriptAt: 2)
        XCTAssertEqual(again.seq, 2, "the transcript started again: it reads from there")
    }

    func event(_ type: Event.Kind, _ specific: String = "", phase: Event.Phase? = nil, at ms: Int64,
               data: [String: JSONValue] = [:], session: String? = nil, cwd: String? = nil) -> Event {
        Event(at: ms, source: type == .turn ? .claude : .device, type: type, phase: phase, specificType: specific,
              session: session, cwd: cwd, data: data)
    }

    /// The day's tallies count only what's yours (Yours): a check-in, an
    /// agent's turn or BOOT's hand-off is never you; the care gestures are
    /// the allow-list's. An away counts from when it began.
    func testTheTalliesCountWhatsYours() throws {
        let reader = MemoryReader(store: try KeyValueStore(directory: nil), time: utc)
        var t = reader.open(day: "2026-10-26", carry: nil)
        let nine = at(2026, 10, 26, 9)
        let read = { (e: Event) in _ = reader.read(e, line: nil, into: &t) }
        read(event(.checkIn, "idle", at: nine - hour))
        XCTAssertEqual(t.yours, 0, "a check-in isn't you")
        read(event(.gesture, "stroke", at: nine))
        read(event(.gesture, "stroke", at: nine + 60_000))
        read(event(.gesture, "handoff", at: nine + 120_000))
        read(event(.poke, "input", at: nine + 180_000))
        read(event(.presence, "locked", phase: .start, at: nine + 3 * hour, data: ["since": .int(nine + 2 * hour)]))
        read(event(.presence, "unlocked", phase: .end, at: nine + 4 * hour))
        read(event(.turn, "UserPromptSubmit", phase: .start, at: nine + 4 * hour, session: "s1", cwd: "/x/api"))
        read(event(.turn, "Stop", phase: .end, at: nine + 4 * hour + 40 * 60_000, data: ["outcome": "failed"], session: "s1", cwd: "/x/api"))
        read(event(.prompt, "reading", at: at(2026, 10, 26, 23)))
        XCTAssertEqual(t.strokes, 2)
        XCTAssertEqual(t.touches, 3, "two strokes and a poke; the hand-off isn't care")
        XCTAssertEqual(t.hereMinutes, 160, "from the first stroke to when the away began, then from the back to the last event before the long gap")
        XCTAssertEqual(t.back, 1)
        XCTAssertEqual([t.turns, t.failed, t.longestMinutes], [1, 1, 40])
        XCTAssertEqual(t.thread, "api")
        XCTAssertEqual(t.late, 1)
        XCTAssertEqual(MemoryReader.tags(t), ["fond", "late", "failed", "long"])
        XCTAssertEqual(MemoryReader.sentence(t), "you stroked it 2 times; 1 turn on \"api\", 1 failed")
        XCTAssertEqual(MemoryReader.fact(t), "stroked x2")
    }

    func stroke(_ seq: Int, _ ms: Int64) -> Event {
        Event(seq: seq, at: ms, source: .device, type: .gesture, specificType: "stroke")
    }

    /// A dream covers exactly the span since the last one, whatever its
    /// length: across 5:00 (the day's tallies start again; the span
    /// doesn't) and across a relaunch (the span's checkpoint is read back);
    /// then the span starts again at the dream.
    func testADreamCoversItsSpanAcrossDaysAndARelaunch() throws {
        let store = try KeyValueStore(directory: nil)
        var memory = Memory(store: store, time: utc)
        let thursday = at(2026, 10, 29, 10)
        memory.heard(poke(1, thursday), line: nil)
        memory.heard(stroke(2, at(2026, 10, 30, 9)), line: nil)
        memory.heard(poke(3, at(2026, 10, 31, 20)), line: nil)
        XCTAssertEqual(memory.span?.tallies.touches, 3, "the span carries across 5:00")
        XCTAssertEqual(memory.today?.touches, 1, "the day's are today's")
        memory = Memory(store: store, time: utc)
        XCTAssertEqual(memory.span?.since, thursday, "read back after a relaunch")
        let night = at(2026, 10, 31, 22)
        memory.dream(at: night, why: "test")
        let dream = try XCTUnwrap(memory.dream)
        XCTAssertEqual(dream.about, "Thursday to Saturday")
        XCTAssertEqual(dream.range, "Thursday 2026-10-29 to Saturday 2026-10-31")
        XCTAssertEqual(dream.sentence, "you stroked it once")
        XCTAssertEqual(memory.span?.since, night, "the span starts again at the dream")
        XCTAssertEqual(memory.span?.new, false)
        memory.heard(poke(4, at(2026, 10, 31, 23)), line: nil)
        memory.dream(at: at(2026, 10, 31, 23, 30), why: "test")
        XCTAssertEqual(memory.dream?.sentence, "you poked it once", "only what came since")
        XCTAssertEqual(memory.dream?.about, "Saturday night")
    }

    /// How the telling says a span (DreamReader.about), in words true
    /// whenever it's told: the part of a day under 8 hours, the day, two
    /// days, a run of them, past a week how many.
    func testTheTellingSaysTheSpan() {
        func about(_ a: Int64, _ b: Int64) -> String { DreamReader.about(since: a, until: b, time: utc) }
        XCTAssertEqual(about(at(2026, 10, 31, 8), at(2026, 10, 31, 11)), "Saturday morning")
        XCTAssertEqual(about(at(2026, 10, 31, 13), at(2026, 10, 31, 17)), "Saturday afternoon")
        XCTAssertEqual(about(at(2026, 10, 31, 18), at(2026, 10, 31, 21)), "Saturday evening")
        XCTAssertEqual(about(at(2026, 10, 31, 22), at(2026, 10, 31, 23)), "Saturday night")
        XCTAssertEqual(about(at(2026, 10, 31, 7), at(2026, 10, 31, 22)), "Saturday")
        XCTAssertEqual(about(at(2026, 10, 30, 22), at(2026, 10, 31, 9)), "Friday and Saturday")
        XCTAssertEqual(about(at(2026, 10, 29, 9), at(2026, 10, 31, 22)), "Thursday to Saturday")
        XCTAssertEqual(about(at(2026, 10, 20, 9), at(2026, 10, 31, 9)), "the 12 days to Saturday")
    }

    /// Pins Memory's trigger asleep and idle: after `nightSleepMs` of it at
    /// night, once a sleep, only with something new, and again only after
    /// waking; while you're away it's one sleep, an agent's turn waking Boop
    /// in it or not.
    func testAsleepAndIdleDreamsOnceASleep() throws {
        let memory = Memory(store: try KeyValueStore(directory: nil), time: utc)
        var sleeping = false, away = false, t = at(2026, 10, 31, 22), seq = 0
        memory.asleep = { sleeping }
        memory.away = { away }
        let sleep = Int(Memory.nightSleepMs / 60_000)
        // Ticks a minute at a time for `minutes`.
        func pass(_ minutes: Int) { for _ in 0..<minutes { t += 60_000; memory.tick(wall: t) } }
        func stroke() { seq += 1; memory.heard(self.stroke(seq, t), line: nil) }
        sleeping = true
        pass(5)
        XCTAssertNil(memory.dream, "asleep with nothing new")
        sleeping = false
        stroke()
        pass(5)
        XCTAssertNil(memory.dream, "awake")
        sleeping = true
        pass(sleep)  // from the first tick asleep: a minute short
        XCTAssertNil(memory.dream, "asleep, not yet settled")
        pass(1)
        let first = try XCTUnwrap(memory.dream)
        XCTAssertEqual(first.sentence, "you stroked it once")
        stroke()
        pass(5)
        XCTAssertEqual(memory.dream, first, "once a sleep")
        stroke()
        sleeping = false
        pass(1)
        sleeping = true
        pass(sleep + 1)
        XCTAssertEqual(memory.dream?.sentence, "you stroked it 2 times", "the next sleep: the strokes since")
        // Away, an agent's turn wakes Boop: still the same sleep.
        sleeping = false
        pass(1)
        stroke()
        away = true
        sleeping = true
        pass(sleep + 1)
        let kept = try XCTUnwrap(memory.dream)
        sleeping = false
        pass(5)
        stroke()
        sleeping = true
        pass(5)
        XCTAssertEqual(memory.dream, kept, "away: an agent woke Boop, but it's the same sleep")
    }

    /// Pins Memory.daySleepMs: by day, a sleep over your lunch dreams nothing,
    /// so a dream is never told at a lunch hello; a long one does, and so
    /// does the night.
    func testALunchDreamsNothing() throws {
        let memory = Memory(store: try KeyValueStore(directory: nil), time: utc)
        var sleeping = false, t = at(2026, 10, 31, 12), seq = 0
        memory.asleep = { sleeping }
        func pass(_ minutes: Int) { for _ in 0..<minutes { t += 60_000; memory.tick(wall: t) } }
        seq += 1
        memory.heard(stroke(seq, t), line: nil)
        sleeping = true
        pass(55)
        XCTAssertNil(memory.dream, "55 min at lunch")
        sleeping = false
        pass(1)
        sleeping = true
        pass(Int(Memory.daySleepMs / 60_000) - 1)
        XCTAssertNil(memory.dream, "not yet a real sleep")
        pass(2)
        XCTAssertNotNil(memory.dream, "a long sleep by day")
        XCTAssertEqual(Memory.daySleepMs, 5 * 3_600_000)
        XCTAssertEqual(Days.dayPart(at: at(2026, 10, 31, 22), time: utc), "night")
    }

    /// Pins Memory.nightSleepMs: a coffee break at 22:05 is night by the
    /// clock, not a sleep, so no dream comes of it to be told at your return.
    func testACoffeeBreakAtNightDreamsNothing() throws {
        let memory = Memory(store: try KeyValueStore(directory: nil), time: utc)
        var sleeping = false, t = at(2026, 10, 31, 22) + 5 * 60_000
        memory.asleep = { sleeping }
        func pass(_ minutes: Int) { for _ in 0..<minutes { t += 60_000; memory.tick(wall: t) } }
        memory.heard(stroke(1, t), line: nil)
        sleeping = true
        pass(25)
        XCTAssertNil(memory.dream, "a coffee break")
        pass(115)
        XCTAssertNotNil(memory.dream, "two hours at night is a sleep")
        XCTAssertEqual(Memory.nightSleepMs, 2 * hour)
    }

    /// Pins the part of the day a dream's gate reads: when the sleep began,
    /// not the hour of the check. A night that ends by day still dreams, and
    /// an evening that runs past 22:00 isn't a night.
    func testTheGateReadsWhenTheSleepBegan() throws {
        func dreams(asleepAt start: Int64, checkAt end: Int64) throws -> Bool {
            let memory = Memory(store: try KeyValueStore(directory: nil), time: utc)
            memory.asleep = { true }
            memory.heard(stroke(1, start), line: nil)
            memory.tick(wall: start)
            memory.tick(wall: end)
            return memory.dream != nil
        }
        func clock(_ hour: Int, _ minute: Int) -> Int64 { at(2026, 10, 31, hour, minute) }
        try XCTAssertTrue(dreams(asleepAt: clock(3, 30), checkAt: clock(8, 0)), "to bed at 3:30, up at 8:00")
        try XCTAssertTrue(dreams(asleepAt: clock(2, 0), checkAt: clock(6, 50)), "the lid shut 2:00 to 6:50: one tick each side")
        try XCTAssertFalse(dreams(asleepAt: clock(20, 0), checkAt: clock(22, 10)), "away 20:00 to 22:10")
        try XCTAssertFalse(dreams(asleepAt: clock(12, 0), checkAt: clock(14, 30)), "a long lunch")
        try XCTAssertTrue(dreams(asleepAt: clock(20, 0), checkAt: at(2026, 11, 1, 1)), "5 h from the evening is a real sleep")
    }

    /// Pins Memory.fallbackMs: two days since the last dream with
    /// something new, it dreams at once, awake or not; 5:00 closes nothing.
    func testTwoDaysWithoutADreamDreamsAndFiveClosesNothing() throws {
        let memory = Memory(store: try KeyValueStore(directory: nil), time: utc)
        memory.asleep = { false }
        let t0 = at(2026, 10, 29, 10)
        memory.heard(stroke(1, t0), line: nil)
        memory.tick(wall: at(2026, 10, 30, 6))
        XCTAssertNil(memory.dream, "5:00 passed: no dream")
        memory.tick(wall: t0 + Memory.fallbackMs - 1)
        XCTAssertNil(memory.dream)
        memory.tick(wall: t0 + Memory.fallbackMs)
        XCTAssertEqual(memory.dream?.about, "Thursday to Saturday")
        XCTAssertEqual(Memory.fallbackMs, 48 * hour)
    }

    /// Pipeline.asleepAndIdle: you away with no agent working, or every
    /// buddy dozed off with agents to watch; never while an agent works,
    /// nor asleep with no agents yet while you're here.
    func testAsleepAndIdleIsAwayOrDozedOffWithNoWork() {
        let rig = CoreRig()
        XCTAssertFalse(rig.pipeline.asleepAndIdle(at: rig.now), "no agents yet, and you're here")
        rig.send(.turnStart, prompt: "fix the tests")
        rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .start, specificType: "locked",
                                    data: ["since": .int(rig.now)]))
        XCTAssertFalse(rig.pipeline.asleepAndIdle(at: rig.now), "away, but an agent works")
        rig.send(.turnEnd)
        XCTAssertTrue(rig.pipeline.asleepAndIdle(at: rig.now), "away, and no agent works")
        rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .end, specificType: "unlocked"))
        XCTAssertFalse(rig.pipeline.asleepAndIdle(at: rig.now), "back, and awake")
        rig.wait(2 * hour, every: 60_000)
        XCTAssertTrue(rig.pipeline.asleepAndIdle(at: rig.now), "dozed off")
    }

    /// The preview (`D`) commits nothing: the checkpoint, the key-value
    /// store, memory.md and the transcript are as they were; and the dream
    /// it previews is the one `d` then makes.
    func testThePreviewChangesNothing() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-memory-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir, today: "2026-10-31")
        let store = try KeyValueStore(directory: nil)
        let queue = DispatchQueue(label: "memory-test")
        let memory = Memory(store: store, time: utc,
                            writer: StubWriter(reply: "add boop: You stroke Boop most mornings. | days: 2026-10-31\nday: you stroked Boop.\nend"),
                            files: files, queue: queue)
        let t0 = at(2026, 10, 31, 9)
        queue.sync { memory.heard(stroke(1, t0), line: nil) }
        let rows = store.prefixed(""), file = files.written().markdown, span = memory.span, seq = memory.dreams.seq
        let preview = await memory.preview(at: t0 + hour)
        XCTAssertEqual(preview.dream?.sentence, "you stroked it once")
        XCTAssertEqual(preview.report?.added, [1])
        XCTAssertNotEqual(preview.after, preview.before)
        XCTAssertEqual(store.prefixed(""), rows, "the key-value store")
        XCTAssertEqual(files.written().markdown, file, "memory.md")
        XCTAssertEqual(memory.span, span, "the span")
        XCTAssertEqual(memory.dreams.seq, seq, "the checkpoint")
        XCTAssertNil(memory.dream, "no dream kept")
        queue.sync { memory.dreamNow(at: t0 + hour) }
        for _ in 0..<150 where queue.sync(execute: { memory.dreaming }) { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(files.written().markdown, preview.after, "d makes what D showed")
    }

    /// A morning stroke is from 5:00 to 11:00: 02:00 is still your night.
    func testAMorningStrokeIsAfterFive() throws {
        let memory = Memory(store: try KeyValueStore(directory: nil), time: utc)
        memory.heard(stroke(1, at(2026, 10, 31, 2)), line: nil)
        XCTAssertNil(memory.span?.tallies.strokesAM, "02:00")
        memory.heard(stroke(2, at(2026, 10, 31, 4, 59)), line: nil)
        XCTAssertNil(memory.span?.tallies.strokesAM, "04:59")
        memory.heard(stroke(3, at(2026, 10, 31, 5)), line: nil)
        XCTAssertEqual(memory.span?.tallies.strokesAM, 1, "05:00")
        memory.heard(stroke(4, at(2026, 10, 31, 11)), line: nil)
        XCTAssertEqual(memory.span?.tallies.strokesAM, 1, "11:00")
    }

    /// The event that tips Boop into a new stage stays in the dream's span:
    /// its reader earns the XP, whose `grew` is logged and heard inside that
    /// read, with a later seq.
    func testTheEventThatGrewBoopIsDreamedOf() throws {
        let memory = Memory(store: try KeyValueStore(directory: nil), time: utc)
        let t0 = at(2026, 10, 31, 9)
        memory.reader.earned = { [unowned memory] e, _ in
            guard e.seq == 1 else { return }
            var grew = Event(at: t0, source: .boop, type: .grew, specificType: "Sprout")
            grew.seq = 2
            memory.heard(grew, line: nil)
        }
        memory.heard(stroke(1, t0), line: nil)
        XCTAssertEqual(memory.span?.tallies.strokes, 1)
        XCTAssertEqual(memory.dreams.seq, 2)
    }

    /// A dream's write still being made when you ask Boop to forget doesn't
    /// land: it was asked from what you've just forgotten.
    func testAForgetDuringADreamDropsItsWrite() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-memory-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir, today: "2026-10-31")
        let queue = DispatchQueue(label: "memory-test")
        let gate = WriterGate()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: utc,
                            writer: GatedWriter(gate: gate, reply: "add boop: You stroke Boop most mornings. | days: 2026-10-31\nday: you stroked Boop.\nend"),
                            files: files, queue: queue)
        let t0 = at(2026, 10, 31, 9)
        queue.sync {
            memory.heard(stroke(1, t0), line: nil)
            memory.dreamNow(at: t0 + hour)
        }
        queue.sync { memory.forgetAboutYou() }
        gate.open()
        for _ in 0..<150 where queue.sync(execute: { memory.dreaming }) { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(queue.sync { memory.dreaming })
        XCTAssertEqual(files.written().notes, [], "the night is dropped")
        XCTAssertEqual(files.written().recently, [])
    }

    /// A dream resets its span at once, so its digest is kept at once: a
    /// quit before the writer answers loses no counts, and the reply adds
    /// only its notes, counting nothing twice.
    func testADreamKeepsItsDigestBeforeTheWriterAnswers() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-memory-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir, today: "2026-10-31")
        let queue = DispatchQueue(label: "memory-test")
        let gate = WriterGate()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: utc,
                            writer: GatedWriter(gate: gate, reply: "add boop: You stroke Boop most mornings. | days: 2026-10-31\nend"),
                            files: files, queue: queue)
        let t0 = at(2026, 10, 31, 9)
        queue.sync {
            memory.heard(stroke(1, t0), line: nil)
            memory.dreamNow(at: t0 + hour)
        }
        XCTAssertEqual(files.days().digests.map(\.strokes), [1], "kept before any answer")
        gate.open()
        for _ in 0..<150 where queue.sync(execute: { memory.dreaming }) { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(files.days().digests.map(\.strokes), [1], "once")
        XCTAssertEqual(files.days().added, ["You stroke Boop most mornings."])
    }

    /// The telling offers `dreams.md`'s signs the dream's tags fit, the
    /// tagged ones first in the file's order (the person's first), then
    /// the plain ones; a line whose tags the day lacks never.
    func testTheTellingOffersTheDreamsSigns() throws {
        let lines = TaggedLine.parse("""
            - [fond] dreamt of u
            - [distant] where were u?
            - [failed] bad dream
            - [halloween] spooky dreams
            - had a dream
            """)
        XCTAssertEqual(Signs.dreams(lines, tags: ["fond", "failed"]), ["dreamt of u", "bad dream", "had a dream"])
        XCTAssertEqual(Signs.dreams(lines, tags: ["fond", "halloween"]), ["dreamt of u", "spooky dreams", "had a dream"])
        let poke = Event(at: 0, source: .device, type: .poke, specificType: "input")
        let react = MomentOutput(queue: { _, _ in }, blocked: { nil }, speaks: { false }, dreams: lines, line: { _ in Line("", facts: ["dream_tags": .array([.string("distant")])]) })
        let sign = try XCTUnwrap(react.questions(now: poke, log: Transcript.log().view(now: 0)).first { $0.key == Signs.questionKey })
        XCTAssertEqual(sign.options.map(\.name), ["none", "where were u?", "had a dream"])
        XCTAssertTrue(sign.text.contains("dream"))
    }

    /// The moment that tells the dream starting, for the event `seq`, as
    /// the react output's would; and its end, `failed` why or done.
    private func moment(_ rig: CoreRig, for seq: Int, failed why: String? = nil) {
        let h = rig.pipeline.harness
        let did = h.emit(Event.did("Boop had a happy moment.", for: seq, action: MomentOutput.outputName, by: "brain", open: true, at: rig.now))
        h.emit(Event.ended(did.seq, action: MomentOutput.outputName, by: "brain", failed: why, at: rig.now))
    }

    /// A line counts as shown once its moment has played: one a needs-you cut
    /// is offered again, as a dream that was cut is told again.
    func testALineCountsAsShownOnceItsMomentHasPlayed() throws {
        let rig = CoreRig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: rig.time)
        memory.attach(to: rig.pipeline)
        let h = rig.pipeline.harness
        func started() -> Event {
            h.emit(Event.did("Boop had a moment.", for: nil, action: MomentOutput.outputName, by: "brain", open: true, facts: ["felt": "u stay up late"], at: rig.now))
        }
        let cut = started()
        XCTAssertEqual(memory.feltShown(), [:], "not yet played")
        h.emit(Event.ended(cut.seq, action: MomentOutput.outputName, by: "brain", failed: "cut short: something needed you", at: rig.now))
        XCTAssertEqual(memory.feltShown(), [:], "a needs-you cut it")
        let played = started()
        h.emit(Event.ended(played.seq, action: MomentOutput.outputName, by: "brain", failed: nil, at: rig.now))
        XCTAssertEqual(memory.feltShown().keys.sorted(), ["u stay up late"])
    }

    /// TranscriptView.played: a dream counts as told only once its moment
    /// has played. A needs-you that cuts it, or a brain that never answers,
    /// leaves it to tell at your next showing up; a second touch while the
    /// first's pass is out doesn't tell it twice.
    func testADreamIsToldOnlyOnceItsMomentHasPlayed() throws {
        let rig = CoreRig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: rig.time)
        memory.attach(to: rig.pipeline)
        rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now)))
        rig.turn(60_000)
        rig.wait(16 * hour, every: 60_000)
        let dream = try XCTUnwrap(memory.dream)
        let told = { (fx: Fx) in events(fx).filter { $0.facts["dream_day"] != nil } }
        let stroke = { rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now))) }

        let first = try XCTUnwrap(told(stroke()).first, "the first touch tells it")
        XCTAssertEqual(told(stroke()).count, 0, "its pass is still out")
        XCTAssertFalse(memory.dream?.told == true)
        rig.wait(TranscriptView.tellingWaitMs, every: TranscriptView.tellingWaitMs)
        let again = try XCTUnwrap(told(stroke()).first, "the brain never answered: the next touch tells it")
        XCTAssertGreaterThan(again.seq, first.seq)

        moment(rig, for: again.seq, failed: "cut short: something needed you")
        XCTAssertFalse(memory.dream?.told == true, "a needs-you cut it")
        let third = try XCTUnwrap(told(stroke()).first, "so the next touch tells it")

        moment(rig, for: third.seq)
        XCTAssertEqual(memory.dream?.day, dream.day)
        XCTAssertTrue(memory.dream?.told == true, "it played through")
        XCTAssertEqual(told(stroke()).count, 0, "told once")
    }

    /// With several buddies one dream is told once: by the first you touch,
    /// and on your coming back by the first of them, who answers it.
    func testSeveralBuddiesTellOneDreamOnce() throws {
        let rig = CoreRig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: rig.time)
        memory.attach(to: rig.pipeline)
        rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now)))
        rig.turn(60_000)
        rig.wait(16 * hour, every: 60_000)
        XCTAssertNotNil(memory.dream)
        rig.pipeline.view.buddies = [Buddy(id: "left", pack: CharacterPack.active.named("Mochi")),
                                     Buddy(id: "right", pack: CharacterPack.active.named("Pix"))]
        let h = rig.pipeline.harness
        func poke(_ buddy: String) -> (seq: Int, told: String?) {
            let e = h.emit(Event(at: rig.now, source: .device, type: .poke, specificType: "input", buddy: buddy))
            return (e.seq, h.line(e.seq)?.facts["dream_told"]?.string)
        }
        let first = poke("right")
        XCTAssertTrue(first.told?.hasPrefix("Pix dreamed") == true, "\(first)")
        XCTAssertNil(poke("left").told, "its moment is still out")
        moment(rig, for: first.seq)
        XCTAssertTrue(memory.dream?.told == true)
        XCTAssertNil(poke("left").told, "the other buddy doesn't tell it again")
    }

    func testYourComingBackTellsTheDreamInTheFirstBuddysName() throws {
        let rig = CoreRig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: rig.time)
        memory.attach(to: rig.pipeline)
        rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now)))
        rig.turn(60_000)
        rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .start, specificType: "locked",
                                    data: ["since": .int(rig.now)]))
        rig.wait(16 * hour, every: 60_000)
        rig.pipeline.view.buddies = [Buddy(id: "left", pack: CharacterPack.active.named("Mochi")),
                                     Buddy(id: "right", pack: CharacterPack.active.named("Pix"))]
        let back = rig.note(Fx(rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .end, specificType: "unlocked"))))
        XCTAssertTrue(events(back).first?.facts["dream_told"]?.string?.hasPrefix("Mochi dreamed") == true)
    }

    /// TranscriptView.told: the dream is told on your first coming back
    /// after it was dreamed: never an agent's event or while you're away,
    /// and once.
    func testTheDreamIsToldTheFirstTimeYouShowUp() throws {
        let rig = CoreRig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: rig.time)
        memory.attach(to: rig.pipeline)
        rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now)))
        rig.turn(60_000)
        rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .start, specificType: "locked",
                                    data: ["since": .int(rig.now)]))
        rig.wait(16 * hour, every: 60_000)
        let dream = try XCTUnwrap(memory.dream, "away, with no agent working: it dreamed")
        XCTAssertFalse(dream.told)
        let told = { (fx: Fx) in events(fx).compactMap { $0.facts["dream_day"]?.string } }
        XCTAssertEqual(told(rig.turn(60_000)), [], "an agent's turn while you're away tells nothing")
        let back = rig.note(Fx(rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .end,
                                                               specificType: "unlocked"))))
        XCTAssertEqual(told(back), [dream.day])
        let line = try XCTUnwrap(events(back).first)
        XCTAssertEqual(line.notes.last, "\(rig.pipeline.buddies[0].name) dreamed about \(dream.about ?? ""): \(dream.sentence).")
        XCTAssertEqual(Narration.of(rig.pipeline.transcript.event(line.seq)!, line: Line(line.line, facts: line.facts))?.fact,
                       dream.fact, "the dream is the reason")
        moment(rig, for: line.seq)
        XCTAssertTrue(memory.dream?.told == true)
        XCTAssertEqual(told(rig.poke()), [], "told once")
    }

    /// With no coming back since the dream (the Mac stayed awake, and Boop
    /// dozed off), your first touch tells it; a prompt or a word to Boop
    /// never does.
    func testWithNoBackTheFirstTouchTellsTheDream() throws {
        let rig = CoreRig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: rig.time)
        memory.attach(to: rig.pipeline)
        rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now)))
        rig.turn(60_000)
        rig.wait(16 * hour, every: 60_000)
        let dream = try XCTUnwrap(memory.dream, "dozed off, with no agent working: it dreamed")
        let told = { (fx: Fx) in events(fx).compactMap { $0.facts["dream_day"]?.string } }
        rig.send(.turnStart, prompt: "good morning, fix the tests")
        XCTAssertEqual(told(rig.note(Fx(rig.pipeline.said("morning boop", by: .device, at: rig.now)))), [], "a word to Boop")
        XCTAssertFalse(memory.dream?.told == true, "nor a prompt")
        XCTAssertEqual(told(rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now)))), [dream.day], "the first touch")
    }
}

/// A reader that counts what it reads, and remembers its closes. Not
/// nested in a test: the shim's runner generator would take it for the
/// test class.
final class CountingReader: TranscriptReader {
    let name = "count"
    var closed: [String] = []
    func open(day: String, carry: Int?) -> Int { 0 }
    func read(_ e: Event, line: Line?, into n: inout Int) -> Bool {
        n += 1
        return true
    }
    func close(day: String, state: Int, live: Bool) { closed.append("\(day) \(state) \(live ? "live" : "catching up")") }
}

final class WriterGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    func open() { lock.withLock { isOpen = true } }
    var opened: Bool { lock.withLock { isOpen } }
}

/// A writer that answers once the test lets it.
struct GatedWriter: MemoryWriter {
    let gate: WriterGate, reply: String
    func write(_ request: MemoryRequest) async -> MemoryWriterReply {
        while !gate.opened { try? await Task.sleep(nanoseconds: 2_000_000) }
        return .reply(reply)
    }
}
