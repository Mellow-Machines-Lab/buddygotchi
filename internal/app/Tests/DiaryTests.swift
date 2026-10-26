import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// Boop's diary (`DiaryOutput`, `MemoryStore`): a line a day about
/// yesterday, from the pack's lines that fit its counts.
final class DiaryTests: XCTestCase {
    let utc = LocalTime(timeZone: TimeZone(identifier: "UTC")!)

    func testTheLinesReadWithTheirTags() {
        let t = TaggedLine.parse("<!-- -->\n- [failed long] {weekday}. Broke.\n- Plain {turns}.\nnot a line\n")
        XCTAssertEqual(t, [.init(tags: ["failed", "long"], text: "{weekday}. Broke."), .init(tags: [], text: "Plain {turns}.")])
    }

    /// A day's counts come from its raw events: turns, failures, the
    /// longest turn, the thread with the most turns, pokes; and its tags.
    func testADaysCountsAndTags() {
        func e(_ type: Event.Kind, _ phase: Event.Phase?, at minute: Int64, session: String = "s1", cwd: String = "/x/api",
               failed: Bool = false) -> Event {
            Event(at: minute * 60_000, source: .claude, type: type, phase: phase, specificType: "x", session: session, cwd: cwd,
                  data: failed ? ["outcome": "failed"] : ["outcome": "done"])
        }
        let events = [e(.turn, .start, at: 0), e(.turn, .end, at: 40, failed: true), e(.turn, .start, at: 50, session: "s2", cwd: "/x/web"),
                      e(.turn, .end, at: 52, session: "s2", cwd: "/x/web"), e(.turn, .start, at: 60), e(.turn, .end, at: 61)]
            + (0..<5).map { e(.poke, nil, at: 70 + Int64($0)) }
        let day = DiaryOutput.count(events, day: "2026-10-20", weekday: "Tuesday", tags: ["friday"])
        XCTAssertEqual([day.turns, day.failed, day.longestMinutes, day.pokes], [3, 1, 40, 5])
        XCTAssertEqual(day.thread, "api")
        XCTAssertEqual(day.tags, ["failed", "long", "poked", "friday"])
        XCTAssertEqual(day.fill("{weekday}: {failed} of {turns} on \"{thread}\""), "Tuesday: 1 of 3 on \"api\"")
        // One of a thing is said in the singular: "1 turns" read as broken.
        var one = day
        (one.turns, one.failed, one.pokes) = (1, 1, 1)
        XCTAssertEqual(one.fill("{turns} turns, none broken. Fell {failed} times. Poked {pokes} times."),
                       "1 turn, none broken. Fell once. Poked once.")
        XCTAssertEqual(one.fill("{failed} of {turns} turns broke."), "1 of 1 turn broke.")
        XCTAssertEqual(one.fill("fell {failed} times, once {longest} minutes in."), "fell once, 40 minutes in.")
        XCTAssertEqual(day.fill("{turns} turns, poked {pokes} times"), "3 turns, poked 5 times")
        XCTAssertTrue(one.words.hasPrefix("1 turn, 1 failed"))
        let quiet = DiaryOutput.count([e(.poke, nil, at: 1)], day: "2026-10-20", weekday: "Tuesday", tags: [])
        XCTAssertEqual(quiet.tags, ["quiet"])
    }

    /// Only the lines whose tags the day has all of, those with tags
    /// first, at most `DiaryOutput.maxOffered`.
    func testTheLinesOfferedFitTheDay() {
        let out = DiaryOutput(templates: TaggedLine.parse("""
            - [failed] Broke.
            - [clean] All good.
            - [failed long] Long and broken.
            - Plain.
            """), time: utc, creature: "Pip") { _, _ in }
        var day = DiaryOutput.Day(day: "2026-10-20", weekday: "Tuesday")
        day.tags = ["failed"]
        XCTAssertEqual(out.offered(day), ["Broke.", "Plain."])
        day.tags = ["failed", "long"]
        XCTAssertEqual(out.offered(day), ["Broke.", "Long and broken.", "Plain."])
        XCTAssertLessThanOrEqual(DiaryOutput.maxOffered, 8)
    }

    /// The popover names a diary's day as a person says it: Yesterday, its
    /// weekday up to six days back, so no weekday stands for two days, and
    /// its date before that. Its line drops the weekday the pack's lines
    /// start with, which the name already says.
    func testThePopoverNamesTheDiarysDays() {
        let today = "2026-10-22"
        XCTAssertEqual(["2026-10-22", "2026-10-21", "2026-10-20", "2026-10-16", "2026-10-15", "2025-12-30"]
            .map { LocalTime.spoken($0, today: today) }, ["Today", "Yesterday", "Tuesday", "Friday", "Oct 15", "Dec 30"])
        XCTAssertEqual(LocalTime.weekday(of: "1970-01-01"), "Thursday")
        XCTAssertEqual(LocalTime.weekday(of: "1969-12-25"), "Thursday")
        let line = Runtime.Status.DiaryLine(day: "2026-10-21", line: "Wednesday. \"api\" fell over.", today: today)
        XCTAssertEqual([line.when, line.line], ["Yesterday", "\"api\" fell over."])
        // Only its own weekday goes: another day's stays, as words.
        XCTAssertEqual(Runtime.Status.DiaryLine(day: "2026-10-21", line: "Friday. Odd.", today: today).line, "Friday. Odd.")
    }

    /// The memory store keeps a line a day, the first one written, and
    /// reads the last days back newest first.
    func testTheDiaryIsALineADay() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try MemoryStore(directory: dir, today: "2026-10-01")
        try store.setUp(name: "Pip", seed: 1, today: "2026-10-01")
        try store.appendDiary(day: "2026-10-19", line: "Monday. Fine.")
        try store.appendDiary(day: "2026-10-20", line: "Tuesday. Broke.")
        try store.appendDiary(day: "2026-10-20", line: "Tuesday again.")
        XCTAssertEqual(store.diary(last: 7).map { "\($0.day) \($0.line)" }, ["2026-10-20 Tuesday. Broke.", "2026-10-19 Monday. Fine."])
        XCTAssertEqual(store.diary(last: 1).map(\.line), ["Tuesday. Broke."])
        let text = try String(contentsOf: dir.appendingPathComponent(MemoryStore.diaryFile), encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# Pip's diary\n"), text)
    }
}
