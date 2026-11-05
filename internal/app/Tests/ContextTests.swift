import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// CONTEXT: how things stand, for Jev on every pass. Each row shows only
/// past its threshold; events stay in their lines.
final class ContextTests: XCTestCase {
    let hour: Int64 = 3_600_000, minute: Int64 = 60_000
    let t0: Int64 = 1_793_102_400_000

    func company(here: Int64? = nil, touched: Int64? = nil, away: Int64? = nil, lonelyEnded: Int64? = nil) -> MemoryReader.Tallies {
        var c = MemoryReader.Tallies()
        c.hereSince = here
        c.touchedAt = touched
        c.awaySince = away
        c.lonelyEndedAt = lonelyEnded
        return c
    }

    /// Pins ContextSection.hereShownMs and untouchedShownMs (1 h each):
    /// facts only, no lonely threshold; away, nothing shows.
    func testTheYouRowsFacts() {
        XCTAssertEqual([ContextSection.hereShownMs, ContextSection.untouchedShownMs], [hour, hour])
        let name = "Boop"
        XCTAssertNil(ContextSection.you(company(here: t0), at: t0 + hour - 1, name: name))
        XCTAssertEqual(ContextSection.you(company(here: t0), at: t0 + hour, name: name),
                       "You: at the Mac for 1 h; you haven't touched or talked to Boop in 1 h.")
        XCTAssertEqual(ContextSection.you(company(here: t0, touched: t0 + hour), at: t0 + 2 * hour - 1, name: name), "You: at the Mac for 1 h.")
        XCTAssertNil(ContextSection.you(company(here: nil, touched: t0, away: t0 + minute), at: t0 + 5 * hour, name: name))
        XCTAssertNil(ContextSection.untouchedMs(company(), at: t0), "nothing to count from")
    }

    /// Pins ContextSection.lastLonelyShownMs (3 h): how long ago Boop was
    /// last lonely, a fact the steering reads; untouched still counts.
    func testLastLonelyIsAFact() {
        let faded = t0 + 3 * hour
        let c = company(here: t0, lonelyEnded: faded)
        XCTAssertEqual(ContextSection.lastLonelyShownMs, 3 * hour)
        XCTAssertEqual(ContextSection.you(c, at: faded + 40 * minute, name: "Boop"),
                       "You: at the Mac for 3 h; you haven't touched or talked to Boop in 3 h; Boop was last lonely 40 min ago.")
        XCTAssertFalse(ContextSection.you(c, at: faded + 3 * hour, name: "Boop")!.contains("lonely"))
        XCTAssertEqual(ContextSection.untouchedMs(c, at: faded + hour), 4 * hour, "no code rule against lonely again")
    }

    /// The Talk row only when it isn't normal, or silent for a hush's
    /// minutes left, then back to the setting; the Boop row: its stage and
    /// age, and no hush.
    /// The When row, first: the time, the weekday, the part of the day,
    /// and the calendar's occasions in words, which NOW's heading no
    /// longer holds.
    func testTheWhenRow() {
        let utc = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
        let halloween: Int64 = 1_793_437_320_000  // 2026-10-31 09:02 UTC, a Saturday
        XCTAssertEqual(ContextSection.when(at: halloween, specialDays: ["Halloween"], time: utc), "When: 09:02, Saturday, morning; Halloween.")
        XCTAssertEqual(ContextSection.when(at: halloween + 12 * 3_600_000, specialDays: [], time: utc), "When: 21:02, Saturday, evening.")
        let section = ContextSection.section(when: "When: 09:02, Saturday, morning.", company: nil, agents: [], at: halloween, name: "Boop")
        XCTAssertEqual(section, ContextSection.heading + "\nWhen: 09:02, Saturday, morning.")
    }

    func testTheTalkAndBoopRows() {
        XCTAssertNil(ContextSection.talk(.normal, name: "Boop"))
        XCTAssertEqual(ContextSection.talk(.chatty, name: "Boop"),
                       "Talk: chatty. You asked Boop to say something at every face; this outranks PERSONALITY's silent Examples.")
        XCTAssertEqual(ContextSection.talk(.quiet, name: "Boop"),
                       "Talk: quiet. You asked Boop to say less: nothing at small moments, and never a swear.")
        XCTAssertEqual(ContextSection.talk(.quiet, silentMs: 8 * minute - 1000, name: "Boop"),
                       "Talk: silent for 8 more min, then quiet again: Boop says nothing till then, but its faces and replies go on, each answering what you said.")
        XCTAssertEqual(ContextSection.talk(.normal, silentMs: 0, name: "Boop"), nil)
        XCTAssertEqual(ContextSection.buddy(.init(stage: "Sprout", daysOld: 40), name: "Boop"), "Boop: a Sprout, 40 days old.")
        XCTAssertEqual(ContextSection.buddy(.init(stage: "Hatchling", daysOld: 0), name: "Boop"), "Boop: a Hatchling, hatched today.")
    }

    /// The agents: what needs you, working and resting, in the core's
    /// order, at most three and "and N more", names clipped.
    func testTheAgentsRow() {
        let agents = [StatusReply.Agent(agent: "claude", places: ["landing", "api"], needsYou: true),
                      StatusReply.Agent(agent: "claude", places: ["landing", "web"], workingSince: t0 - 12 * minute),
                      StatusReply.Agent(agent: "codex", places: ["blog"], restingSince: t0 - 40 * minute),
                      StatusReply.Agent(agent: "codex", places: ["docs"]),
                      StatusReply.Agent(agent: "codex", places: ["cli"])]
        XCTAssertEqual(ContextSection.agents(agents, at: t0),
                       #"Agents: claude waiting on you on "api"; claude working on "web" for 12 min; codex idle on "blog" for 40 min; and 2 more."#)
        XCTAssertNil(ContextSection.agents([], at: t0))
        let long = String(repeating: "x", count: 80)
        let clipped = ContextSection.agents([StatusReply.Agent(agent: "codex", places: [long])], at: t0)!
        XCTAssertLessThan(clipped.count, 60)
    }

    /// The day so far, once a turn finished or you touched or talked to
    /// Boop since 5:00.
    func testTheTodayRow() {
        var c = MemoryReader.Tallies()
        XCTAssertNil(ContextSection.today(c, name: "Boop"))
        c.turns = 7
        c.failed = 3
        c.touches = 6
        c.talks = 2
        XCTAssertEqual(ContextSection.today(c, name: "Boop"), "Today: 7 turns, 3 failed; you touched Boop 6 times and talked to it twice.")
        c.turns = 0
        c.touches = 0
        c.talks = 1
        XCTAssertEqual(ContextSection.today(c, name: "Boop"), "Today: you talked to Boop once.")
    }

    /// Pins ContextSection.maxTokens: every row, three agents with long
    /// names and "and 2 more" stay within 190 tokens.
    func testTheSectionHasACeiling() {
        var c = company(here: t0, lonelyEnded: t0 + 10 * hour)
        c.turns = 23
        c.failed = 11
        c.touches = 14
        c.talks = 12
        let long = String(repeating: "w", count: 80)
        let agents = (0..<5).map { StatusReply.Agent(agent: "codex", places: [long + "\($0)"], workingSince: t0) }
        let section = ContextSection.section(talk: .chatty, silentMs: 119 * minute, buddy: .init(stage: "Hatchling", daysOld: 400),
                                             company: c, agents: agents, noticed: Notices.whileAway([("claude", "\"wwwwwwwwwwwwwwww\"", false), ("codex", "\"wwwwwwwwwwwwwwww\"", true), ("codex", "\"w\"", true)]),
                                             at: t0 + 11 * hour, name: "Boop")!
        XCTAssertEqual(section.components(separatedBy: "\n").count, 7)
        XCTAssertLessThanOrEqual(Steering.tokens(section), ContextSection.maxTokens, section)
        XCTAssertEqual(ContextSection.maxTokens, 190)
    }

    /// The prompt's order: PERSONALITY, MEMORY, MOOD, CONTEXT, then HISTORY
    /// and NOW; no TALK.
    func testTheSectionsPlaceInThePrompt() throws {
        let rig = CoreRig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: rig.time)
        let (h, _) = Runtime.harness(pipeline: rig.pipeline, steering: RuntimeTests.steering,
                                     queue: { _, _ in }, memory: { "MEMORY (what Boop remembers.)\nYou\n- a note" },
                                     remembers: memory)
        memory.attach(to: rig.pipeline)
        rig.send(.sessionStart)
        rig.poke()
        rig.now += 2 * hour
        rig.send(.turnStart, prompt: "go")
        let prompt = h.prompt(for: h.log.events.last { $0.type == .turn }!)
        let marks = ["\nPERSONALITY", "\nMEMORY (", "\nMOOD", "\nCONTEXT (", "\nHISTORY", "\nNOW"]
        let at = try marks.map { try XCTUnwrap(prompt.range(of: $0)?.lowerBound, $0) }
        XCTAssertEqual(at, at.sorted(), prompt)
        XCTAssertTrue(prompt.contains("Agents: claude working on"), prompt)
        XCTAssertFalse(prompt.contains("\nTALK"), "the setting is CONTEXT's row")
    }
}
