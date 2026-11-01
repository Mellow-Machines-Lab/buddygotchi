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

    /// Pins ContextSection.hereShownMs (1 h), untouchedMs (2 h) and
    /// afterLonelyMs (2 h).
    func testTheThresholds() {
        XCTAssertEqual([ContextSection.hereShownMs, ContextSection.untouchedMs, ContextSection.afterLonelyMs], [hour, 2 * hour, 2 * hour])
        let name = "Boop"
        XCTAssertNil(ContextSection.you(company(here: t0), at: t0 + hour - 1, name: name))
        XCTAssertEqual(ContextSection.you(company(here: t0), at: t0 + hour, name: name), "You: at the Mac for 1 h.")
        XCTAssertEqual(ContextSection.you(company(here: t0), at: t0 + 2 * hour, name: name),
                       "You: at the Mac for 2 h; you haven't touched or talked to Boop in 2 h.")
        // A touch restarts the span; away, nothing shows.
        XCTAssertEqual(ContextSection.you(company(here: t0, touched: t0 + hour), at: t0 + 2 * hour, name: name), "You: at the Mac for 2 h.")
        XCTAssertNil(ContextSection.you(company(here: nil, touched: t0, away: t0 + minute), at: t0 + 5 * hour, name: name))
        XCTAssertNil(ContextSection.untouchedMs(company(), at: t0), "nothing to count from")
    }

    /// After a lonely spell ends with no touch, untouched stays hidden for
    /// two hours, so lonely can't come straight back; a touch since counts
    /// from the touch.
    func testNoLonelyAgainRightAfterOneFades() {
        let faded = t0 + 3 * hour
        let c = company(here: t0, lonelyEnded: faded)
        XCTAssertNil(ContextSection.untouchedMs(c, at: faded + 2 * hour - 1))
        XCTAssertEqual(ContextSection.untouchedMs(c, at: faded + 2 * hour), 5 * hour)
        let touched = company(here: t0, touched: faded + minute, lonelyEnded: faded)
        XCTAssertEqual(ContextSection.untouchedMs(touched, at: faded + hour), hour - minute)
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
    /// names and "and 2 more" stay within 120 tokens.
    func testTheSectionHasACeiling() {
        var c = company(here: t0, lonelyEnded: nil)
        c.turns = 23
        c.failed = 11
        c.touches = 14
        c.talks = 12
        let long = String(repeating: "w", count: 80)
        let agents = (0..<5).map { StatusReply.Agent(agent: "codex", places: [long + "\($0)"], workingSince: t0) }
        let section = ContextSection.section(company: c, agents: agents, at: t0 + 11 * hour, name: "Boop")!
        XCTAssertEqual(section.components(separatedBy: "\n").count, 4)
        XCTAssertLessThanOrEqual(Steering.tokens(section), ContextSection.maxTokens, section)
        XCTAssertEqual(ContextSection.maxTokens, 120)
    }

    /// The prompt's order: PERSONALITY, MEMORY, MOOD, CONTEXT, TALK, then
    /// HISTORY and NOW.
    func testTheSectionsPlaceInThePrompt() throws {
        let rig = CoreRig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: rig.time)
        let (h, _) = Runtime.harness(pipeline: rig.pipeline, steering: RuntimeTests.steering, personality: { .default },
                                     queue: { _, _ in }, memory: { "MEMORY (what Boop remembers.)\nYou\n- a note" },
                                     remembers: memory)
        memory.attach(to: rig.pipeline)
        rig.send(.sessionStart)
        rig.poke()
        rig.now += 2 * hour
        rig.send(.turnStart, prompt: "go")
        let prompt = h.prompt(for: h.log.events.last { $0.type == .turn }!)
        let marks = ["\nPERSONALITY", "\nMEMORY (", "\nMOOD", "\nCONTEXT (", "\nTALK", "\nHISTORY", "\nNOW"]
        let at = try marks.map { try XCTUnwrap(prompt.range(of: $0)?.lowerBound, $0) }
        XCTAssertEqual(at, at.sorted(), prompt)
        XCTAssertTrue(prompt.contains("Agents: claude working on"), prompt)
    }

    /// A mood with `only_when` is offered as a move only when NOW has one
    /// of its cues: lonely at an idle check-in two hours untouched, or a
    /// day away; staying in it needs none.
    func testLonelyIsOfferedOnlyWithItsCue() throws {
        try requirePack("boop")
        XCTAssertEqual(MoodGraph.mood("lonely")?.onlyWhen, ["untouched", "a day away"])
        func offered(_ cues: Set<String>) -> [String] { MoodOutput.options(from: "calm", cues: cues).map(\.name) }
        XCTAssertFalse(offered([]).contains("lonely"))
        XCTAssertTrue(offered(["untouched"]).contains("lonely"))
        XCTAssertTrue(MoodOutput.options(from: "calm").map(\.name).contains("lonely"), "with no cues given, every move")
        XCTAssertEqual(MoodOutput.options(from: "lonely", cues: []).first?.name, "lonely", "staying needs no cue")
        let check = Event(at: t0, source: .clock, type: .heartbeat, specificType: "check_in")
        XCTAssertEqual(MoodOutput.cues(check, facts: [:], untouchedMs: 2 * hour), ["untouched"])
        XCTAssertEqual(MoodOutput.cues(check, facts: [:], untouchedMs: 2 * hour - 1), [])
        let back = Event(at: t0, source: .mac, type: .presence, phase: .end, specificType: "unlocked")
        XCTAssertEqual(MoodOutput.cues(back, facts: ["away": "a day"], untouchedMs: nil), ["a day away"])
        XCTAssertEqual(MoodOutput.cues(back, facts: ["away": "days"], untouchedMs: nil), [])
    }
}
