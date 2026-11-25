import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The skits: the few moments that always speak, each from takes of its
/// own (`Skits.play`, the pack's `skits`, voicegen's `SKIT_OF`).
final class SkitTests: XCTestCase {
    let skits = [Skit(id: "win", slots: [.doneLong, .doneVeryLong]),
                 Skit(id: "upset", slots: [.failed, .failedVeryLong, .gaveUp, .checkFailing]),
                 Skit(id: "fix", slots: [.checkFixed]), Skit(id: "back", slots: [.back, .backDays, .backAfterADay])]
    /// The same, with the clip and the invites the pack gives them (`InviteTests`).
    let invited = [InviteTests.win, InviteTests.upset, Skit(id: "fix", slots: [.checkFixed], clip: "flop"), InviteTests.back]

    func play(_ slot: RulesBrain.Slot, _ facts: [String: JSONValue] = [:], swears: Bool = true) -> String? {
        Skits.play(slot: slot, facts: facts, swears: swears, in: skits).map { $0.skit.id + ($0.swears ? " swearing" : "") }
    }

    /// Pins every row of `Skits.play`'s table: when each skit plays.
    func testWhenEachSkitPlays() {
        XCTAssertEqual(play(.doneLong), "win")
        XCTAssertEqual(play(.doneVeryLong), "win")
        XCTAssertEqual(play(.failed), "upset")
        XCTAssertEqual(play(.failedVeryLong), "upset")
        XCTAssertEqual(play(.gaveUp), "upset")
        XCTAssertEqual(play(.checkFixed), "fix")
        XCTAssertEqual(play(.back), "back")
        XCTAssertEqual(play(.backDays), "back")
        XCTAssertEqual(play(.backAfterADay), "back")
        // A check failing: from the 3rd in a row.
        XCTAssertEqual(Skits.checkFailingFrom, 3)
        XCTAssertNil(play(.checkFailing, ["failed_before": 1]), "the 2nd in a row: no drama yet")
        XCTAssertNil(play(.checkFailing), "no count: none")
        XCTAssertEqual(play(.checkFailing, ["failed_before": 2], swears: false), "upset")
        XCTAssertEqual(play(.checkFailing, ["failed_before": 5], swears: false), "upset")
        // Every slot no skit lists: none.
        let listed = Set(skits.flatMap(\.slots))
        for slot in RulesBrain.Slot.allCases where !listed.contains(slot) {
            XCTAssertNil(play(slot, ["failed_before": 3, "checks_failed": 3]), "\(slot)")
        }
        XCTAssertNil(Skits.play(slot: .doneLong, facts: [:], swears: true, in: []), "a pack with none: silent")
    }

    /// Pins the swear rule: only with swearing on, and only once the
    /// failures pile up: from the 3rd failed check in a row, or a failed
    /// turn with 2 or more failed checks.
    func testWhenTheUpsetSkitSwears() {
        XCTAssertEqual(Skits.swearsAtChecksFailed, 2)
        XCTAssertEqual(play(.checkFailing, ["failed_before": 2]), "upset swearing")
        XCTAssertEqual(play(.checkFailing, ["failed_before": 2], swears: false), "upset")
        for slot: RulesBrain.Slot in [.failed, .failedVeryLong, .gaveUp] {
            XCTAssertEqual(play(slot), "upset", "\(slot): no failed checks")
            XCTAssertEqual(play(slot, ["checks_failed": 1]), "upset", "\(slot): one failed check")
            XCTAssertEqual(play(slot, ["checks_failed": 2]), "upset swearing", "\(slot)")
            XCTAssertEqual(play(slot, ["checks_failed": 4]), "upset swearing", "\(slot)")
            XCTAssertEqual(play(slot, ["checks_failed": 2], swears: false), "upset", "\(slot): swearing off")
        }
        for slot: RulesBrain.Slot in [.doneLong, .doneVeryLong, .checkFixed, .back, .backDays, .backAfterADay] {
            XCTAssertEqual(play(slot, ["checks_failed": 3, "failed_before": 3]).map { $0.hasSuffix("swearing") }, false, "\(slot)")
        }
    }

    /// Boop's pack has the four skits, each at the slots the skits' table
    /// names, three of them an invite, and the fix the flop of relief, a
    /// clip of the pack's rig.
    func testThePacksSkitsParse() throws {
        let pack = try Self.pack()
        XCTAssertEqual(pack.skits, invited)
        XCTAssertEqual(pack.skits.map(\.slots), skits.map(\.slots))
        for skit in pack.skits {
            guard let clip = skit.clip else { continue }
            let rig = pack.directory.appendingPathComponent("rig/clips/\(clip).json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: rig.path), "\(skit.id)'s clip \(clip) is the rig's")
        }
    }

    /// Pins a clip's name to what the board keeps of one: its `kReplyBytes`
    /// less the end.
    func testAClipsNameFitsTheBoard() throws {
        let behaviour = try String(contentsOf: FirmwareTables.root.appendingPathComponent("firmware/src/app/behaviour.h"), encoding: .utf8)
        let bytes = try XCTUnwrap(behaviour.firstMatch(of: /kReplyBytes = (\d+);/).flatMap { Int($0.1) })
        XCTAssertEqual(Skit.clipBytes, bytes - 1)
    }

    /// A skit's clip is its Moment's, sent in its `do`'s args, as its face
    /// starts: the fix's flop. A skit with none sends none, nor does a
    /// Moment that's no skit, and a Moment's own clip stays its own. A
    /// skit with an invite as well keeps it, on the same Moment.
    @MainActor func testASkitsClipIsItsMoments() throws {
        try requirePack("boop")
        let check = Event(at: 1000, source: .claude, type: .tool, phase: .end, specificType: "PostToolUse")
        let fixed: InviteTests.Facts = ["topic": "tests", "result": "ok", "failed_before": 2]
        let rig = InviteRig()
        rig.run(check, fixed, face: "pleased")
        XCTAssertEqual(rig.sent.last?.clip, "flop")
        XCTAssertEqual(rig.sent.last?.args["clip"], "flop")
        rig.run(InviteTests.finish, InviteTests.won, face: "proud")
        XCTAssertNil(rig.sent.last?.args["clip"], "a win has none")
        rig.run(Event(at: 1000, source: .device, type: .poke, specificType: "input"), [:], face: "amused")
        XCTAssertNil(rig.sent.last?.args["clip"], "no skit, none")
        // A skit with a clip and an invite: both, on the one Moment.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: CharacterPack.active.directory
                .appendingPathComponent("character.json"))) as? [String: Any])
        var rows = try XCTUnwrap(json["skits"] as? [[String: Any]])
        rows[0]["clip"] = "flop"
        json["skits"] = rows
        let invited = InviteRig()
        invited.pack = try CharacterPack(json: json, from: "character.json", directory: CharacterPack.active.directory)
        invited.inviting()
        invited.run(InviteTests.finish, InviteTests.won, face: "proud")
        XCTAssertEqual(invited.sent.last?.clip, "flop")
        XCTAssertEqual(invited.sent.last?.invite?.pose, .palm)
    }

    /// A pack's `skits` that isn't one doesn't load: a skit with no id, a
    /// slot that isn't the rules', a slot in two skits, a clip whose name
    /// the board can't keep. With none, it has no skits.
    func testABadSkitDoesntLoad() throws {
        func pack(_ skits: Any?) throws -> CharacterPack {
            var json: [String: Any] = ["id": "t", "name": "T", "version": "1", "default_mood": "calm",
                                       "moods": [["id": "calm", "face": "Calm."]], "lasting": [["id": "calm", "meaning": "Settled."]]]
            json["skits"] = skits
            return try CharacterPack(json: json, from: "t.json")
        }
        let none = try pack(nil), one = try pack([["id": "win", "slots": ["doneLong"]]])
        XCTAssertEqual(none.skits, [])
        XCTAssertEqual(one.skits, [Skit(id: "win", slots: [.doneLong])])
        let flops = try pack([["id": "fix", "slots": ["checkFixed"], "clip": "flop"]])
        XCTAssertEqual(flops.skits, [Skit(id: "fix", slots: [.checkFixed], clip: "flop")])
        for (skits, why): ([[String: Any]], String) in [([["slots": ["doneLong"]]], "t.json: a skit without an id"),
                             ([["id": "", "slots": ["doneLong"]]], "t.json: a skit without an id"),
                             ([["id": "win", "slots": ["doneAtLast"]]], "t.json: skit win plays at doneAtLast, which isn't a slot"),
                             ([["id": "win", "slots": ["doneLong"]], ["id": "yay", "slots": ["doneLong"]]],
                              "t.json: skit yay plays at doneLong, which another skit has"),
                             ([["id": "fix", "slots": ["checkFixed"], "clip": ""]],
                              "t.json: skit fix's clip  isn't a clip's name, 11 letters, digits or dashes at most"),
                             ([["id": "fix", "slots": ["checkFixed"], "clip": "flop of relief"]],
                              "t.json: skit fix's clip flop of relief isn't a clip's name, 11 letters, digits or dashes at most"),
                             ([["id": "fix", "slots": ["checkFixed"], "clip": "flop-of-relief"]],
                              "t.json: skit fix's clip flop-of-relief isn't a clip's name, 11 letters, digits or dashes at most"),
                             ([["id": "fix", "slots": ["checkFixed"], "clip": 3]],
                              "t.json: skit fix's clip 3 isn't a clip's name, 11 letters, digits or dashes at most")] {
            do {
                _ = try pack(skits)
                XCTFail("loaded: \(why)")
            } catch {
                XCTAssertEqual((error as? CharacterPackError)?.description, why)
            }
        }
    }

    /// A skit is never silent for want of a take: for Boop's pack, every
    /// face the rules brain gives a skit's slots, as the moods colour it
    /// (cross at each level, and sad), has a take of the skit; the upset
    /// skit's plain ones too, as it says them with no swear asked for or
    /// none in the face. The fix skit has every word that claims a fix.
    func testEverySkitHasATakeInEveryFaceItPlaysIn() throws {
        let pack = try Self.pack()
        let takes = Take.all(in: pack).filter { $0.part == .skit }
        XCTAssertFalse(takes.isEmpty, pack.id)
        for skit in pack.skits {
            let own = takes.filter { $0.meaning == skit.id }
            XCTAssertTrue((8...16).contains(Set(own.map(\.text)).count), "\(pack.id) \(skit.id): \(Set(own.map(\.text)).sorted())")
            XCTAssertTrue(own.contains { $0.kind == .word } && own.contains { $0.kind == .phrase }, "\(pack.id) \(skit.id): words and phrases")
            for slot in skit.slots {
                for mood in [pack.defaultMood, "cross", "sad"] {
                    for level in 1...3 {
                        for face in RulesBrain.colour(RulesBrain.faces[slot] ?? [], mood: mood, level: level) {
                            XCTAssertTrue(own.contains { $0.kind != .swear && $0.moods.contains(face) },
                                          "\(pack.id): \(skit.id) at \(slot) says nothing in \(face)")
                        }
                    }
                }
            }
        }
        let fix = Set(takes.filter { $0.meaning == "fix" }.map(\.text))
        XCTAssertTrue(pack.claimsAFix.isSubset(of: fix), "\(pack.id): \(pack.claimsAFix) in fix")
        XCTAssertEqual(Set(takes.filter { $0.kind == .swear }.map(\.meaning)), ["upset"], "\(pack.id): only upset swears")
    }

    /// Through the pipeline, with the rules brain: three failed checks in
    /// a row say nothing, nothing, then a swear (a plain take with swearing
    /// off); the check passing, a fix take; a long turn done, a win take;
    /// each record naming its skit. Ten routine calls before say nothing.
    func testSkitsThroughThePipeline() async throws {
        try requireVoice()
        let calls = (0..<10).map { i in i % 2 == 0 ? #"{"event": "edit", "at": "\#(i * 5)s"}"# : #"{"event": "command", "at": "\#(i * 5)s"}"# }
        // Its name seeds the rules brain's faces, so a run repeats.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("skits-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("skits.json")
        try Data(("""
            {"name": "skits", "case": "the skits", "why": "a skit always speaks",
             "steps": [{"event": "turn started", "at": "0s", "workspace": "skits"},
            """ + calls.joined(separator: ",") + """
            ,
              {"event": "command", "at": "1m", "topic": "tests", "failed": true, "expect": {"said": "none"}},
              {"event": "command", "at": "2m", "topic": "tests", "failed": true, "expect": {"said": "none"}},
              {"event": "command", "at": "3m", "topic": "tests", "failed": true, "expect": {"said": "some"}},
              {"event": "command", "at": "4m", "topic": "tests", "failed": false, "expect": {"said": "some"}},
              {"event": "turn finished", "at": "10m", "expect": {"said": "some"}}]}
            """).utf8).write(to: file)
        let scenario = try Scenario(file: file)
        let texts = { (meaning: String) in Set(Take.all.filter { $0.part == .skit && $0.meaning == meaning }.map(\.text)) }
        for swears in [true, false] {
            let records = try await Self.records(scenario, swears: swears, steering: RuntimeTests.steering)
            // Each record: its line, its message, its skit, what it said and
            // the skit's takes' kinds.
            let all = records.map { $0.components(separatedBy: " | ") }
            let shown = all.map { $0.joined(separator: " | ") }.joined(separator: "\n")
            // What spoke: only the skits, each naming itself; the rest,
            // the two failed checks before the third included, nothing.
            let spoke = all.filter { !$0[3].isEmpty }
            XCTAssertEqual(spoke.map { $0[2] }, ["upset", "fix", "win"], shown)
            XCTAssertTrue(all.filter { $0[2] == "-" }.allSatisfy { $0[3].isEmpty }, shown)
            XCTAssertEqual(all.filter { $0[0].contains("tests failed") }.count, 3, "each failed check a Moment: \(shown)")
            guard spoke.count == 3 else { continue }
            let (upset, fix, win) = (spoke[0], spoke[1], spoke[2])
            XCTAssertTrue(upset[0].contains("failed"), upset[0])
            XCTAssertTrue(texts("upset").contains(upset[3]), upset[3])
            XCTAssertEqual(upset[4] == Take.Kind.swear.rawValue, swears, "the 3rd in a row swears only with swearing on: \(upset)")
            XCTAssertTrue(fix[0].contains("passed"), fix[0])
            XCTAssertTrue(fix[3].split(separator: "+").allSatisfy { texts("fix").contains(String($0)) }, fix[3])
            XCTAssertTrue(win[0].contains("finished"), win[0])
            XCTAssertTrue(texts("win").contains(win[3]), win[3])
        }
    }

    /// Each Moment a run of `scenario` played, with the rules brain: its
    /// line, its message, its skit (or -), what it said, and the skit's
    /// takes' kinds, " | " between.
    nonisolated static func records(_ scenario: Scenario, swears: Bool, steering: Steering) async throws -> [String] {
        let records = Lines()
        var eval = Eval(brain: ScriptedBrain { _, _ in [:] }, steering: steering)
        eval.rules = true
        eval.swears = swears
        eval.onPass = { _, pass in
            for out in pass.outputs where out.name == MomentOutput.outputName {
                let said = (out.result.facts["takes"]?.array ?? []).compactMap(\.string)
                let texts = said.compactMap { id in Take.all.first { $0.id == id }?.text }
                let kinds = said.compactMap { id in Take.all.first { $0.id == id && $0.part == .skit }?.kind.rawValue }
                records.add([pass.line ?? "", out.result.message, out.result.facts["skit"]?.string ?? "-",
                             texts.joined(separator: "+"), kinds.joined(separator: "+")].joined(separator: " | "))
            }
        }
        let result = try await eval.run(scenario)
        XCTAssertTrue(result.passed, result.checks.filter { !$0.passed }.map(\.summary).joined(separator: "\n"))
        return records.all
    }

    /// Boop's pack, from the repository.
    static func pack() throws -> CharacterPack {
        try CharacterPack(directory: CharacterPackTests.repo.appendingPathComponent("characters/boop"))
    }
}
