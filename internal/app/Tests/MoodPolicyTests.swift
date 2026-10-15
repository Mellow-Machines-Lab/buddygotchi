import Foundation
import MellowHarness
import LinkKit
import XCTest
@testable import BoopDevKit
@testable import BoopKit

final class MoodPolicyTests: XCTestCase {
    // The mood policy, on Boop's graph.
    override func setUpWithError() throws { try requirePack("boop") }

    /// Boop's graph is the slime design's host graph (slimegen writes it),
    /// and every mood but the resting one has a recovery step that is one
    /// of its ordinary moves.
    func testBoopsGraphMatchesTheSource() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../characters/boop/design/slime-blob/emotion-graph.json")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let nodes = try XCTUnwrap(json["nodes"] as? [String: [String: Any]])
        XCTAssertEqual(Set(nodes.keys), Set(MoodGraph.moods))
        let graph = MoodGraph.moves
        XCTAssertEqual(graph.values.map(\.all.count).reduce(0, +), 295)
        for (id, n) in nodes {
            XCTAssertEqual(graph[id]?.ordinary, n["ordinary"] as? [String])
            XCTAssertEqual(graph[id]?.dramatic, n["dramatic"] as? [String])
            XCTAssertEqual(MoodGraph.mood(id)?.brief, n["brief"] as? Bool)
            if id != MoodAction.initial { XCTAssertTrue(graph[id]!.ordinary.contains(MoodPolicy.recovery(from: id)!)) }
        }
    }

    /// The mood question offers staying, then exactly the moves the
    /// policy allows now, whatever the mood.
    func testTheMoodQuestionOffersThePolicysMoves() {
        let log = Transcript.log()
        for from in MoodGraph.moods {
            let mood = MoodAction.choice()
            log.append(Event(source: Event.harness, kind: Event.did,
                             data: ["action": "mood", "ok": true, "to": .string(from)]), now: 1)
            let view = log.view(now: 100_000)
            let allowed = MoodPolicy.destinations(from: from, event: nil, log: view)
            XCTAssertEqual(mood.questions(now: nil, log: view)[0].options, MoodAction.options(from: from, allowed: allowed))
            XCTAssertEqual(MoodAction.options(from: from, allowed: allowed).map(\.name), [from] + allowed.all)
            XCTAssertEqual(MoodAction.options(from: from).map(\.name), [from] + MoodGraph.moves[from]!.all)
        }
    }

    func changed(_ log: Log, from: String, to: String, at: Int64) {
        log.append(Event(source: Event.harness, kind: Event.did,
                         data: ["action": "mood", "ok": true, "from": .string(from), "to": .string(to)]), now: at)
    }

    /// Boop's pacing (its pack's `pacing`): 30 s dwell, 60 s before a
    /// reverse, 5 s before a brief mood leaves, evidence fresh for 15 s.
    func testPacingBoundariesAndBriefExitExemption() {
        XCTAssertEqual(MoodGraph.pacing.ordinaryDwellMs, 30_000)
        XCTAssertEqual(MoodGraph.pacing.reverseCooldownMs, 60_000)
        XCTAssertEqual(MoodGraph.pacing.briefExitMs, 5_000)
        XCTAssertEqual(MoodGraph.pacing.freshEvidenceMs, 15_000)
        let log = Transcript.log()
        changed(log, from: "calm", to: "curious", at: 1)
        XCTAssertTrue(MoodPolicy.destinations(from: "curious", event: nil, log: log.view(now: 30_000)).all.isEmpty)
        let fresh = log.append(Event(source: "claude", kind: "tool_end", data: ["tool_use_id": "dwell"]), now: 30_000)
        XCTAssertTrue(MoodPolicy.destinations(from: "curious", event: fresh, log: log.view(now: 30_000)).all.isEmpty)
        XCTAssertFalse(MoodPolicy.destinations(from: "curious", event: fresh, log: log.view(now: 30_001)).ordinary.isEmpty)
        // The reverse to calm is withheld through 59,999 ms of age.
        XCTAssertFalse(MoodPolicy.destinations(from: "curious", event: nil, log: log.view(now: 60_000)).ordinary.contains("calm"))
        XCTAssertEqual(MoodPolicy.destinations(from: "curious", event: nil, log: log.view(now: 60_001)).ordinary, ["calm"])
        for brief in MoodGraph.moods where MoodGraph.mood(brief)!.brief {
            let log = Transcript.log(), exit = MoodPolicy.recovery(from: brief)!
            changed(log, from: exit, to: brief, at: 1)
            XCTAssertTrue(MoodPolicy.destinations(from: brief, event: nil, log: log.view(now: 5_000)).all.isEmpty)
            XCTAssertEqual(MoodPolicy.destinations(from: brief, event: nil, log: log.view(now: 5_001)).ordinary, [exit])
        }
    }

    func testRoutineFailureAndClockNeverJustifyDramaticEdges() {
        let log = Transcript.log()
        let e = log.append(Event(source: "claude", kind: "tool_end", data: ["failed": true, "tool_use_id": "t1"]), now: 100_000)
        for mood in MoodGraph.moods {
            let options = MoodPolicy.destinations(from: mood, event: e, log: log.view(now: e.at))
            XCTAssertTrue(options.dramatic.isEmpty)
            XCTAssertFalse(options.ordinary.contains("frightened"))
            XCTAssertTrue(Set(options.all).isSubset(of: MoodGraph.moves[mood]!.all))
            XCTAssertLessThanOrEqual(options.all.count, 8)
        }
        for kind in ["heartbeat", "frame", "loop", "timer", "needs_you_start"] {
            let tick = log.append(Event(source: "clock", kind: kind), now: 100_001)
            let moves = MoodPolicy.destinations(from: "grumpy", event: tick, log: log.view(now: tick.at))
            XCTAssertEqual(moves.ordinary, [MoodPolicy.recovery(from: "grumpy")!])
            XCTAssertTrue(moves.dramatic.isEmpty)
        }
    }

    func testEvidenceExpiresAndIsConsumedByIdentityEvenWhenStaying() {
        let log = Transcript.log()
        let e = log.append(Event(source: "claude", kind: "tool_end", data: ["session": "s1", "tool_use_id": "t1"]), now: 1)
        XCTAssertGreaterThan(MoodPolicy.destinations(from: "calm", event: e, log: log.view(now: 15_001)).all.count, 0)
        XCTAssertTrue(MoodPolicy.destinations(from: "calm", event: e, log: log.view(now: 15_002)).all.isEmpty)
        log.append(Event(source: Event.harness, kind: Event.pass, data: ["for": .int(Int64(e.seq))]), now: 2)
        // A transport replay gets a new log seq but the same upstream identity.
        let replay = log.append(Event(source: "claude", kind: "tool_end", data: e.data), now: 3)
        XCTAssertTrue(MoodPolicy.destinations(from: "calm", event: replay, log: log.view(now: 3)).all.isEmpty)
        let next = log.append(Event(source: "claude", kind: "tool_end", data: ["session": "s1", "tool_use_id": "t2"]), now: 4)
        XCTAssertFalse(MoodPolicy.destinations(from: "calm", event: next, log: log.view(now: 4)).all.isEmpty)
    }

    func testStrongLongFailureIsBranchSpecificAndCannotBeReplayed() {
        let log = Transcript.log()
        log.append(Event(source: "claude", kind: "turn_start", data: ["session": "s1"]), now: 1)
        let e = log.append(Event(source: "claude", kind: "turn_end", data: ["session": "s1", "outcome": "failed"]), now: 300_001)
        XCTAssertTrue(MoodPolicy.destinations(from: "grumpy", event: e, log: log.view(now: e.at)).dramatic.contains("sad"))
        XCTAssertFalse(MoodPolicy.destinations(from: "uneasy", event: e, log: log.view(now: e.at)).dramatic.contains("frightened"))
        log.append(Event(source: Event.harness, kind: Event.pass, data: ["for": .int(Int64(e.seq))]), now: e.at)
        // Validation during MellowHarness's current pass still sees what it asked.
        XCTAssertTrue(MoodPolicy.destinations(from: "grumpy", event: e, log: log.view(now: e.at)).dramatic.contains("sad"))
        changed(log, from: "grumpy", to: "sad", at: e.at)
        let replay = log.append(Event(source: "claude", kind: "turn_end", data: e.data), now: e.at + 1)
        XCTAssertTrue(MoodPolicy.destinations(from: "grumpy", event: replay, log: log.view(now: replay.at)).dramatic.isEmpty)
    }

    /// The pass for the event being
    /// decided never consumes it, so validation keeps the jump asking
    /// offered though an earlier output's `did` and a rule's event land
    /// after that pass; a replay of the turn end decided later finds it used.
    func testTheDecisionsOwnPassNeverConsumesItsEvidence() async throws {
        let log = Transcript.log(), clock = VirtualClock(1), queue = DispatchQueue(label: "mood-policy")
        var options = Harness.Options()
        options.loop = false
        let h = Harness(name: "Boop", brain: ScriptedBrain(always: ["mood": Answer(choice: "sad")]), log: log,
                        clock: Harness.Clock(now: { clock.now }), queue: queue, options: options)
        let mood = MoodAction.choice()
        h.input("turn_end", wake: 1)
        h.output(MoodPolicyNoter())
        h.output(mood)
        h.on(Event.pass) { [unowned h] _ in h.emit(Event(source: "test", kind: "noted")) }
        let e = queue.sync {
            h.force(mood, by: "test") { MoodAction.change(mood, to: "grumpy", log: log.view(now: clock.now)) }
            h.emit(Event(source: "claude", kind: "turn_start", data: ["session": "s1"]))
            clock.now = 300_001
            return h.emit(Event(source: "claude", kind: "turn_end", line: "A very long turn failed.",
                                data: ["session": "s1", "outcome": "failed"]))
        }
        let pass = await h.respond(to: e)
        XCTAssertEqual(pass?.questions.first { $0.key == MoodAction.actionName }?.options.map(\.name).contains("sad"), true)
        queue.sync {
            let after = log.events.drop { $0.seq <= pass!.seq }.map(\.kind)
            XCTAssertEqual(after, ["noted", Event.did, Event.did], "the rule's event and the noter's did, then the mood's")
            XCTAssertEqual(MoodAction.value(mood, log.view(now: clock.now)), "sad")
            let replay = log.append(Event(source: "claude", kind: "turn_end", data: e.data), now: clock.now)
            XCTAssertNil(MoodPolicy.fresh(replay, log.view(now: clock.now)))
        }
    }

    /// `fresh` as it was before it looked at copies only: the whole log
    /// scanned, each candidate's identity worked out again, and the pass
    /// deciding the event exempt only as the log's last event.
    static func wholeLogFresh(_ e: Event, _ log: LogView) -> Event? {
        guard e.seq > 0, e.at <= log.now, log.now - e.at <= MoodGraph.pacing.freshEvidenceMs,
              ["turn_start", "turn_end", "tool_end", "subagent_end", "poke", "talk", "presence_end"].contains(e.kind) else { return nil }
        func identity(_ e: Event) -> String {
            let prefix = [e.source, e.session ?? "", e.subagent ?? "", e.kind]
            func key(_ id: String) -> String { JSONLine.encode(prefix + [id]) }
            if let id = e["tool_use_id"]?.string { return key(id) }
            if e.kind == "turn_end", let start = log.events.last(where: {
                $0.seq < e.seq && $0.kind == "turn_start" && $0.source == e.source && $0.session == e.session && $0.subagent == e.subagent
            }) { return key(String(start.seq)) }
            return key(String(e.seq))
        }
        let id = identity(e)
        let consumed = log.events.contains { p in
            if p.kind == Event.pass && p.about == e.seq && p.seq == log.events.last?.seq { return false }
            guard p.kind == Event.pass || (p.kind == Event.did && p.action == MoodAction.actionName),
                  let seq = p.about, let prior = log.event(seq),
                  prior.source == e.source, prior.session == e.session, prior.subagent == e.subagent, prior.kind == e.kind else { return false }
            return identity(prior) == id
        }
        return consumed ? nil : e
    }

    /// Looking at the evidence's copies only finds what
    /// scanning the whole log did, on a long log of three threads with
    /// replayed tool calls and turn ends, asked and then validated with
    /// the pass logged last, as Boop's harness does.
    func testCopiesFindWhatTheWholeLogScanFound() {
        let log = Transcript.log()
        var rng = SplitMix64(seed: 53)
        let threads: [[String: JSONValue]] = [["session": "s1"], ["session": "s2"], ["session": "s1", "subagent": "a1"]]
        var evidence: [Event] = [], t: Int64 = 1, used = 0, unused = 0
        for i in 0..<1500 {
            t += Int64(rng.int(in: 0...4000))
            var event = Event(source: "claude", kind: "heartbeat", data: threads[rng.int(in: 0...2)])
            switch rng.int(in: 0...9) {
            case 0: event.kind = "turn_start"
            case 1: event.kind = "turn_end"; event.data["outcome"] = rng.chance(50) ? "done" : "failed"
            case 2...4: event.kind = "tool_end"; event.data["tool_use_id"] = .string("toolu_\(i)")
            case 5: event.kind = "poke"
            case 6...7 where !evidence.isEmpty:
                let copy = evidence[rng.int(in: 0...(evidence.count - 1))]
                event = Event(source: copy.source, kind: copy.kind, data: copy.data)
            default: break
            }
            let e = log.append(event, now: t)
            if e.kind != "heartbeat" { evidence.append(e) }
            let asked = MoodPolicy.fresh(e, log.view(now: t))
            XCTAssertEqual(asked?.seq, Self.wholeLogFresh(e, log.view(now: t))?.seq, "\(e.kind) \(e.seq), asking")
            if e.kind != "heartbeat" { if asked == nil { used += 1 } else { unused += 1 } }
            guard rng.chance(70) else { continue }
            log.append(Event(source: Event.harness, kind: Event.pass, data: ["for": .int(Int64(e.seq))]), now: t)
            XCTAssertEqual(MoodPolicy.fresh(e, log.view(now: t))?.seq, Self.wholeLogFresh(e, log.view(now: t))?.seq,
                           "\(e.kind) \(e.seq), validating")
            if rng.chance(25) {
                log.append(Event(source: Event.harness, kind: Event.did,
                                 data: ["for": .int(Int64(e.seq)), "action": "mood", "ok": true, "to": "calm"]), now: t)
            }
        }
        XCTAssertGreaterThan(used, 100, "replays found used")
        XCTAssertGreaterThan(unused, 500, "evidence found fresh")
    }

    /// A reaction in any mood speaks in that mood's own takes: every mood
    /// has takes (characters/CHARACTER.md §8), so nothing stands in for
    /// another; its moment and state carry the mood itself.
    func testEveryMoodsReactionSpeaksInItsOwnTakes() {
        func a(_ choice: String) -> Answer { Answer(choice: choice, probabilities: [choice: 0.9]) }
        var queued: [DeviceMoment] = []
        let react = ReactAction(queue: { moment, _ in queued.append(moment) }, blocked: { nil })
        XCTAssertEqual(ReactAction.expressions.map(\.name), MoodGraph.moods)
        for mood in MoodGraph.moods {
            _ = react.run(["react.mood": a(mood), "say.feeling": a("upset"), "say.about": a("tests"), "say.kind": a("word")],
                          now: nil, log: Transcript.log().view(now: 1))
            XCTAssertEqual(queued.last?.mood, mood)
            XCTAssertEqual(queued.last?.args["mood"], .string(mood))
            let takes = queued.last?.say?.takes ?? []
            XCTAssertFalse(takes.isEmpty, mood)
            XCTAssertTrue(takes.allSatisfy { $0.moods.contains(mood) }, mood)
            let state = StateSnapshot(base: "working", act: "testing", mood: mood, attn: nil, busy: 1, vol: 6)
            XCTAssertEqual(state.fields["mood"], .string(mood))
            var rng = SplitMix64(seed: 53)
            XCTAssertGreaterThan(Core.pickVariant(mood: mood, state: "idle", avoiding: nil, &rng), 0)
        }
        XCTAssertEqual(queued.count, MoodGraph.moods.count)
        XCTAssertTrue(RuntimeTests.steering.overBudget().isEmpty)
    }

    /// A settings file from before the one graph still loads, its
    /// `moodGraph` ignored.
    func testAnOldSettingsFilesGraphIsIgnored() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"moodGraph":"v3","volume":4}"#.utf8))
        XCTAssertEqual(old.volume, 4)
        let saved = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        XCTAssertFalse(saved.contains("moodGraph"))
    }
}

/// An output that runs before the mood, as react would if registered
/// first: its `did` lands after the pass, before the mood validates. At
/// file scope: the test runner's generator reads a class inside a test
/// case as the case's end.
final class MoodPolicyNoter: Action {
    let name = "noter"
    func questions(now: Event?, log: LogView) -> [Question] { [] }
    func run(_ answers: Answers, now: Event?, log: LogView) -> ActionResult? { .done("Noted.") }
}
