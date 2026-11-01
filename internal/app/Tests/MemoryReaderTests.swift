import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// Boop's memory: its day, the checkpointed reader that runs it, the day's
/// tallies, and the dream told the first time you show up after it.
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
        _ = reader.read(Event(seq: 3, at: morning + hour, source: .clock, type: .heartbeat, specificType: "check_in"), line: nil, into: &t)
        XCTAssertNil(t.touchedAt, "a prompt or a heartbeat isn't touching Boop")
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

    /// The day's tallies count only what's yours (Yours): a heartbeat, an
    /// agent's turn or BOOT's hand-off is never you; the care gestures are
    /// the allow-list's. An away counts from when it began.
    func testTheTalliesCountWhatsYours() throws {
        let reader = MemoryReader(store: try KeyValueStore(directory: nil), time: utc)
        var t = reader.open(day: "2026-10-26", carry: nil)
        let nine = at(2026, 10, 26, 9)
        let read = { (e: Event) in _ = reader.read(e, line: nil, into: &t) }
        read(event(.heartbeat, "idle", at: nine - hour))
        XCTAssertEqual(t.yours, 0, "a heartbeat isn't you")
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
        XCTAssertEqual(t.hereMinutes, 120, "from the first stroke to when the away began")
        XCTAssertEqual(t.back, 1)
        XCTAssertEqual([t.turns, t.failed, t.longestMinutes], [1, 1, 40])
        XCTAssertEqual(t.thread, "api")
        XCTAssertEqual(t.late, 1)
        XCTAssertEqual(MemoryReader.tags(t), ["fond", "late", "failed", "long"])
        XCTAssertEqual(MemoryReader.sentence(t), "you stroked it 2 times; 1 turn on \"api\", 1 failed")
        XCTAssertEqual(MemoryReader.fact(t), "stroked x2")
    }

    /// A day closes into a dream only if you were there; twice for one day,
    /// the same dream.
    func testADayNobodyWasThereHasNoDream() throws {
        let store = try KeyValueStore(directory: nil)
        let reader = MemoryReader(store: store, time: utc)
        var dreams: [Dream] = []
        reader.wrote = { dreams.append($0) }
        var t = reader.open(day: "2026-10-26", carry: nil)
        _ = reader.read(event(.heartbeat, "idle", at: at(2026, 10, 26, 9)), line: nil, into: &t)
        reader.close(day: "2026-10-26", state: t, live: true)
        XCTAssertEqual(dreams, [], "nobody was there")
        _ = reader.read(event(.poke, "input", at: at(2026, 10, 26, 10)), line: nil, into: &t)
        reader.close(day: "2026-10-26", state: t, live: true)
        XCTAssertEqual(dreams.map(\.weekday), ["Monday"])
        try dreams[0].save(in: store)
        reader.close(day: "2026-10-26", state: t, live: true)
        XCTAssertEqual(dreams.count, 1, "closed twice, the same dream, written once")
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
        let react = ReactOutput(queue: { _, _ in }, blocked: { nil }, speaks: { false }, dreams: lines, told: { _ in ["distant"] })
        let sign = try XCTUnwrap(react.questions(now: poke, log: Transcript.log().view(now: 0)).first { $0.key == Signs.questionKey })
        XCTAssertEqual(sign.options.map(\.name), ["none", "where were u?", "had a dream"])
        XCTAssertTrue(sign.text.contains("dream"))
    }

    /// TranscriptView.told: the dream is told on your first coming back
    /// after the day closes: never an agent's event or while you're away,
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
        let dream = try XCTUnwrap(memory.dream, "the day closed at 5:00")
        XCTAssertFalse(dream.told)
        let told = { (fx: Fx) in events(fx).compactMap { $0.facts["dream_day"]?.string } }
        XCTAssertEqual(told(rig.turn(60_000)), [], "an agent's turn while you're away tells nothing")
        let back = rig.note(Fx(rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .end,
                                                               specificType: "unlocked"))))
        XCTAssertEqual(told(back), [dream.day])
        let line = try XCTUnwrap(events(back).first)
        XCTAssertEqual(line.notes.last, "\(rig.pipeline.buddies[0].name) dreamed about \(dream.weekday): \(dream.sentence).")
        XCTAssertEqual(Reason.of(rig.pipeline.transcript.event(line.seq)!, line: Line(line.line, facts: line.facts))?.fact,
                       dream.fact, "the dream is the reason")
        XCTAssertTrue(memory.dream?.told == true)
        XCTAssertEqual(told(rig.poke()), [], "told once")
    }

    /// With no coming back since the close (the Mac stayed awake), your
    /// first touch tells it; a prompt or a word to Boop never does.
    func testWithNoBackTheFirstTouchTellsTheDream() throws {
        let rig = CoreRig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: rig.time)
        memory.attach(to: rig.pipeline)
        rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now)))
        rig.turn(60_000)
        rig.wait(16 * hour, every: 60_000)
        let dream = try XCTUnwrap(memory.dream, "the day closed at 5:00")
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
