import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The eval runner (internal/EVALS.md), with a scripted brain: the scenarios
/// read, each step reaches the core, and each pass is checked. The evals
/// themselves ask Jev (`boopdev eval`).
final class EvalTests: XCTestCase {

    /// Boop's eval scenarios, which these tests read: Boop's pack's own.
    static func scenarios() throws -> URL {
        try requirePack("boop")
        return CharacterPack.active.directory.appendingPathComponent("evals")
    }

    func testEveryScenarioReads() throws {
        // Pixel's own, which make -C internal eval-pixel runs, read too.
        let pixels = try Scenario.load(directory: CharacterPackTests.repo.appendingPathComponent("characters/pixel/evals"))
        XCTAssertEqual(pixels.count, 5)
        let all = try Scenario.load(directory: try Self.scenarios())
        XCTAssertGreaterThanOrEqual(all.count, 7)
        XCTAssertTrue(all.allSatisfy { !$0.story.isEmpty }, "every scenario says its case in plain words")
        XCTAssertTrue(all.contains { $0.always }, "some scenarios are Boop's character")
        XCTAssertTrue(all.contains { $0.steps.contains { $0.session == "s2" } }, "a step can be another session's")
    }

    func testRangesAndDurationsRead() {
        let counts = 0...Int.max, shares = 0...1.0
        XCTAssertEqual(Scenario.range("1-3", within: counts), 1...3)
        XCTAssertEqual(Scenario.range("2-", within: counts), 2...Int.max)
        XCTAssertEqual(Scenario.range("-4", within: counts), 0...4)
        XCTAssertEqual(Scenario.range("3", within: counts), 3...3)
        XCTAssertNil(Scenario.range("3-1", within: counts))
        XCTAssertNil(Scenario.range("-", within: counts))
        XCTAssertEqual(Scenario.range("0.5-", within: shares), 0.5...1)
        XCTAssertEqual(Scenario.range("-0.3", within: shares), 0...0.3)
        XCTAssertNil(Scenario.range("0.5-1.5", within: shares), "a share is 1 at most")
        XCTAssertEqual(Scenario.ms("2m30s"), 150_000)
        XCTAssertEqual(Scenario.ms("1h5m"), 3_900_000)
        XCTAssertNil(Scenario.ms("5x"))
    }

    /// EVALS.md §1: the cases that start in a mood off the 13 load, reach
    /// real questions, and pass with an offline brain that always keeps
    /// the mood they start in. This is not a Jev evaluation.
    func testTheQuietScenariosPassWithABrainThatStays() async throws {
        let names = ["68-quiet-recovery-from-fear", "69-new-work-from-comfy"]
        let scenarios = try Scenario.load(directory: try Self.scenarios()).filter { s in names.contains { s.file.hasPrefix($0) } }
        XCTAssertEqual(scenarios.count, 2)
        for scenario in scenarios {
            let brain = ScriptedBrain(always: ["mood": scenario.mood, "react.mood": "none"].mapValues { Answer(choice: $0, probabilities: [$0: 1]) })
            let result = try await Eval(brain: brain, steering: RuntimeTests.steering).run(scenario)
            XCTAssertTrue(result.passed, result.checks.filter { !$0.passed }.map(\.summary).joined(separator: "\n"))
        }
    }

    /// A brain that answers the way the scenario wants passes it, which
    /// checks that every expected step wakes the brain and that the mood and
    /// what Boop said are read as the outputs leave them. A reaction goes
    /// nowhere and counts as played at once, so HISTORY shows it plainly
    /// (EVALS.md §1).
    func testTheTestsFightBackWithAnAgreeableBrain() async throws {
        let states = Lines()
        let brain = ScriptedBrain { state, _ in
            states.add(state)
            let now = state.components(separatedBy: "\nNOW (").last ?? ""
            let mood = MoodGraph.moods.first { state.contains("MOOD\n\($0.prefix(1).uppercased())\($0.dropFirst()).") } ?? "calm"
            func a(_ c: String) -> Answer { Answer(choice: c, probabilities: [c: 0.9]) }
            if now.contains("passed") {
                return ["mood": a("proud"), "react.mood": a("proud"), "say.feeling": a("glad")]
            }
            if now.contains("failed") {
                return ["mood": a(mood == "calm" ? "annoyed" : "determined"), "react.mood": a("determined"),
                        "say.about": a("tests"), "say.kind": a("word")]
            }
            return ["mood": a(mood), "react.mood": a("none"), "say.feeling": a("none")]
        }
        let scenario = try Scenario(file: try Self.scenarios().appendingPathComponent("04-tests-fight-back.json"))
        let result = try await Eval(brain: brain, steering: RuntimeTests.steering).run(scenario)
        XCTAssertEqual(result.checks.count, 4)
        XCTAssertTrue(result.passed, result.checks.filter { !$0.passed }.map(\.summary).joined(separator: "\n"))
        XCTAssertEqual(result.checks[0].mood, "annoyed", "calm moves a step, to annoyed")
        XCTAssertEqual(result.checks[2].about, "tests")
        let said = try XCTUnwrap(result.checks[2].said)
        XCTAssertTrue(Take.all.contains { $0.text == said && $0.meaning == "tests" && $0.moods.contains("determined") }, "determined's: \(said)")
        XCTAssertEqual(result.checks[2].mood, "determined")
        XCTAssertEqual(result.checks[3].mood, "proud", "2 minutes after the last failure: no rule holds a mood")
        let last = try XCTUnwrap(states.all.last)
        XCTAssertTrue(last.contains("\n  Boop made a determined face, held once, and said \"\(said)\".\n"), last)
    }

    /// EVALS.md §3: a step's `reaction` says how the reactions its passes
    /// start end, so HISTORY can show one still in progress, or leave out
    /// one that didn't happen; any other value doesn't load.
    func testAStepSaysHowItsReactionEnds() async throws {
        let states = Lines()
        let brain = ScriptedBrain { state, _ in
            states.add(state)
            let proud = Answer(choice: "proud", probabilities: ["proud": 1])
            return ["react.mood": proud, "mood": proud]
        }
        let eval = Eval(brain: brain, steering: RuntimeTests.steering)
        for (file, shown) in [("11-comeback-still-showing.json", true), ("12-comeback-that-didnt-happen.json", false)] {
            _ = try await eval.run(try Scenario(file: try Self.scenarios().appendingPathComponent(file)))
            let finish = try XCTUnwrap(states.all.last)
            XCTAssertEqual(finish.contains("\n  Boop made a proud face, held once. (in progress)\n"), shown, finish)
            XCTAssertEqual(finish.contains("after failing.\n  Boop made"), shown, "one that didn't happen isn't shown: \(finish)")
        }
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("bad-reaction-\(UUID().uuidString).json")
        try Data(#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","reaction":"maybe","expect":{"react":"none"}}]}"#.utf8)
            .write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }
        do {
            _ = try Scenario(file: bad)
            XCTFail("a reaction of \"maybe\" loaded")
        } catch {
            XCTAssertTrue("\(error)".contains("step 1: reaction is"), "\(error)")
        }
    }

    /// EVALS.md §3: a turn start's `prompt` and a finish's `message` reach
    /// Jev as NOW's notes (`27-agent-gives-up`); on any other step they
    /// don't load.
    func testAStepCarriesThePromptAndLastMessage() async throws {
        let states = Lines()
        let brain = ScriptedBrain { state, _ in
            states.add(state)
            return [:]
        }
        _ = try await Eval(brain: brain, steering: RuntimeTests.steering)
            .run(try Scenario(file: try Self.scenarios().appendingPathComponent("27-agent-gives-up.json")))
        XCTAssertTrue(states.all.first?.contains("\n  You asked: \"fix the login redirect\"") == true, states.all.first ?? "no pass")
        XCTAssertTrue(states.all.last?.contains("\n  Its last message: \"I couldn't get the login working.") == true, states.all.last ?? "no pass")
        for (json, why) in [(#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","prompt":"hi","expect":{"react":"none"}}]}"#, "step 1: prompt is only"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"turn failed","at":"0s","message":"hi","expect":{"react":"none"}}]}"#, "step 1: message is only")] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("bad-note-\(UUID().uuidString).json")
            try Data(json.utf8).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                _ = try Scenario(file: file)
                XCTFail("loaded: \(json)")
            } catch {
                XCTAssertTrue("\(error)".contains(why), "\(error)")
            }
        }
    }

    /// A brain that stays quiet fails what should react, and the report
    /// says what was wanted and what came.
    func testAQuietBrainFailsAndTheReportSaysWhy() async throws {
        let scenario = try Scenario(file: try Self.scenarios().appendingPathComponent("05-pokes-glad-miffed-grumpy.json"))
        let result = try await Eval(brain: ScriptedBrain(always: [:]), steering: RuntimeTests.steering).run(scenario)
        XCTAssertFalse(result.passed)
        let report = Eval.report([result])
        XCTAssertEqual(report.first, "FAIL  05-pokes-glad-miffed-grumpy.json  Pokes make Boop curious, then miffed, then fed up")
        XCTAssertTrue(report[1].contains("wanted react amused|curious|excited|happy|mischievous, animation none, said some, mood curious|happy; got react none, animation none, feeling none, about none, kind none, said none, loops none, mood calm"), report[1])
        XCTAssertEqual(Eval.summary([[result]]), "0/1 passed")
    }

    /// EVALS.md §3: a scenario without a case doesn't load, nor one with a
    /// check it doesn't know.
    func testAScenarioNeedsItsCaseAndKnownChecks() throws {
        for (json, why) in [(#"{"name":"n","why":"w","steps":[{"event":"pokes","at":"0s","expect":{"react":"none"}}]}"#, "needs name, case"),
                            (#"{"name":"n","case":"c","why":"w","checks":{"max_fun":2},"steps":[{"event":"pokes","at":"0s"}]}"#, "checks has only"),
                            (#"{"name":"n","case":"c","why":"w","checks":{"reactions":"lots"},"steps":[{"event":"pokes","at":"0s"}]}"#, "checks.reactions"),
                            (#"{"name":"n","case":"c","why":"w","runs":0,"steps":[{"event":"pokes","at":"0s","expect":{"react":"none"}}]}"#, "runs is a count"),
                            (#"{"name":"n","case":"c","why":"w","nature":"grumpy","steps":[{"event":"pokes","at":"0s","expect":{"react":"none"}}]}"#, "nature is sweet or cheeky"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"turn failed","at":"0s","agent":"codex","expect":{"react":"none"}}]}"#, "Codex has no hook"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","count":0,"expect":{"react":"none"}}]}"#, "count is for pokes"),
                            (#"{"name":"n","case":"c","why":"w","checks":{"words_said":"half"},"steps":[{"event":"pokes","at":"0s"}]}"#, "checks.words_said")] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID().uuidString).json")
            try Data(json.utf8).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            do {
                _ = try Scenario(file: file)
                XCTFail("loaded: \(json)")
            } catch {
                XCTAssertTrue("\(error)".contains(why), "\(error)")
            }
        }
    }

    /// EVALS.md §1: a run's prompt has the NATURE the person chose at
    /// setup, as the app's always does: cheeky unless the scenario says
    /// sweet.
    func testAScenarioRunsWithItsNature() async throws {
        for (nature, words) in [(nil, "At heart Boop is cheeky."), ("sweet", "At heart Boop is sweet.")] {
            let states = Lines()
            let brain = ScriptedBrain { state, _ in
                states.add(state)
                return [:]
            }
            let field = nature.map { #","nature":"\#($0)""# } ?? ""
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("nature-\(UUID().uuidString).json")
            try Data(#"{"name":"n","case":"c","why":"w"\#(field),"steps":[{"event":"poke","at":"0s","expect":{"mood":"calm"}}]}"#.utf8).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            let scenario = try Scenario(file: file)
            XCTAssertEqual(scenario.nature.rawValue, nature ?? "cheeky")
            _ = try await Eval(brain: brain, steering: RuntimeTests.steering).run(scenario)
            XCTAssertTrue(states.all.first?.contains(words) ?? false, states.all.first ?? "no state")
        }
    }

    /// EVALS.md §2: an always scenario runs 3 times, the rest once, unless
    /// the file says; and what a run costs is its passes, counted with the
    /// scripted brain before Jev is asked anything.
    func testRunsAndTheirCost() async throws {
        let all = try Scenario.load(directory: try Self.scenarios())
        let always = try XCTUnwrap(all.first { $0.always && $0.runs == nil })
        let tuning = try XCTUnwrap(all.first { !$0.always && $0.runs == nil })
        XCTAssertEqual(Eval.runs(always), 3)
        XCTAssertEqual(Eval.runs(tuning), 1)
        let busy = try XCTUnwrap(all.first { $0.file.hasPrefix("53-") })
        XCTAssertEqual(Eval.runs(busy), 1, "53 says runs 1: the code already holds its moves to the graph")
        // 05's four pokes, a second apart then a turn start: a pass each.
        let pokes = try Scenario(file: try Self.scenarios().appendingPathComponent("05-pokes-glad-miffed-grumpy.json"))
        let requests = try await Eval.requests(pokes, steering: RuntimeTests.steering)
        XCTAssertEqual(requests, 4)
    }

    /// EVALS.md §3's whole-run checks, against a brain that makes the same
    /// excited face, saying nothing, at every pass and never changes the mood, over
    /// five quick wins: it's the same reaction ten times running (starts
    /// and finishes), of one kind, and the mood never moves.
    func testWholeRunChecksCatchTheSameReactionAgainAndAgain() async throws {
        let brain = ScriptedBrain(always: ["react.mood": Answer(choice: "excited", probabilities: ["excited": 0.9]),
                                           "say.feeling": Answer(choice: "none", probabilities: ["none": 0.9])])
        let steps = (0..<5).map { i in
            #"{"event":"turn started","at":"\#(i)m"},{"event":"command","at":"\#(i)m20s","topic":"tests","failed":false},"#
                + #"{"event":"turn finished","at":"\#(i)m30s"}"#
        }.joined(separator: ",")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("19-same-win-again.json")
        try Data(#"{"name":"n","case":"c","why":"w","checks":{"max_same_in_a_row":2,"min_variety":2,"reactions":"2-","mood_changes":"-2","words_said":"0.5-"},"steps":[\#(steps)]}"#.utf8)
            .write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let scenario = try Scenario(file: file)
        let result = try await Eval(brain: brain, steering: RuntimeTests.steering).run(scenario)
        XCTAssertFalse(result.passed)
        let failed = Dictionary(uniqueKeysWithValues: result.runChecks.map { ($0.name, $0) })
        XCTAssertEqual(failed["max_same_in_a_row 2"]?.passed, false)
        XCTAssertTrue(failed["max_same_in_a_row 2"]?.detail.hasSuffix("in a row (excited)") ?? false,
                      failed["max_same_in_a_row 2"]?.detail ?? "")
        XCTAssertEqual(failed["min_variety 2"]?.passed, false)
        XCTAssertEqual(failed["reactions 2 or more"]?.passed, true)
        XCTAssertEqual(failed["mood_changes 0-2"]?.passed, true)
        XCTAssertEqual(failed["words_said 0.5-1.0"]?.passed, false, "it never says anything")
        XCTAssertEqual(failed["words_said 0.5-1.0"]?.detail, "0 of 10 reactions said something")
        let report = Eval.report([result], story: scenario.story)
        XCTAssertEqual(report[1], "  case: " + scenario.story)
        let asGap = Eval.report([result], story: scenario.story, gap: "why")
        XCTAssertTrue(asGap[0].hasPrefix("GAP   19-same-win-again.json"), asGap[0])
        XCTAssertEqual(asGap[1], "  gap: why")
        XCTAssertEqual(Eval.summary([[result]], gaps: 1), "0/1 passed (1 known gaps failed)")
        XCTAssertTrue(report.contains { $0.hasPrefix("  whole run: max_same_in_a_row 2: ") }, report.joined(separator: "\n"))
        XCTAssertTrue(Eval.timeline(result).contains { $0.contains("→ excited, once  [calm]") },
                      Eval.timeline(result).joined(separator: "\n"))
    }

    /// The quiet and mood checks, on a made-up run: a turn from 0 to 20
    /// minutes with reactions at 1 and 9 minutes is quiet for 11 minutes
    /// at the end; happy → determined → happy inside 40 s is a bounce.
    func testQuietAndBounceChecks() {
        func pass(_ s: Int64, _ face: String?, _ mood: String) -> Eval.Pass {
            Eval.Pass(atMs: s * 1000, line: "l", reaction: face.map { Eval.Reaction(face: $0, animation: "none", said: "none") },
                      loops: face == nil ? nil : "once", mood: mood, dropped: nil)
        }
        var checks = Scenario.Checks()
        checks.quietWorkingMs = 360_000
        checks.bounceMs = 60_000
        checks.moodChanges = 1...3
        let out = Eval.judge(checks, timeline: [pass(60, "happy", "happy"), pass(540, "determined", "determined"),
                                                pass(580, nil, "happy")], working: [(0, 1_200_000)], start: "happy")
        XCTAssertEqual(out.map(\.passed), [false, true, false])
        XCTAssertEqual(out[0].detail, "the longest quiet stretch of work was 11m00s, from 9m00s")
        XCTAssertEqual(out[1].detail, "2: happy → determined → happy")
        XCTAssertEqual(out[2].detail, "happy → determined at 9m00s, back at 9m40s")
    }

    /// EVALS.md §3: a scenario may start in any mood (`mood`, as the
    /// dashboard would set it just before), and a step may check exactly
    /// what its pass's mood question offered (`offered`): staying, and the
    /// mood's moves on the graph.
    func testAScenarioStartsInItsMoodAndChecksWhatWasOffered() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("start-mood-\(UUID().uuidString).json")
        let grumpy = (["grumpy"] + MoodGraph.moves["grumpy"]!.all).joined(separator: "|")
        try Data(#"{"name":"n","case":"c","why":"w","mood":"grumpy","steps":[{"event":"turn started","at":"2m","expect":{"offered":"\#(grumpy)","mood":"irritated"}},{"event":"turn finished","at":"3m","expect":{"offered":"calm|happy"}}]}"#.utf8)
            .write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let scenario = try Scenario(file: file)
        XCTAssertEqual(scenario.mood, "grumpy")
        let states = Lines()
        let brain = ScriptedBrain { state, _ in
            states.add(state)
            return ["mood": Answer(choice: "irritated", probabilities: ["irritated": 1])]
        }
        let result = try await Eval(brain: brain, steering: RuntimeTests.steering).run(scenario)
        XCTAssertTrue(states.all.first?.contains("MOOD\nGrumpy.") == true, "the first pass reads grumpy's file")
        XCTAssertTrue(states.all.first?.contains("\n\(creature) has been grumpy for 2 min.\n") == true,
                      "and knows how long, as if the dashboard set it at the start: \(states.all.first ?? "")")
        XCTAssertTrue(result.checks[0].passed, result.checks[0].summary)
        XCTAssertEqual(result.checks[1].offered, ["irritated"] + MoodGraph.moves["irritated"]!.all)
        XCTAssertFalse(result.checks[1].passed)
        XCTAssertTrue(result.checks[1].summary.hasSuffix(", offered " + (["irritated"] + MoodGraph.moves["irritated"]!.all).sorted().joined(separator: "|")),
                      result.checks[1].summary)
        XCTAssertTrue(result.checks[1].summary.contains("wanted offered calm|happy; got react none"), result.checks[1].summary)
        for (json, why) in [(#"{"name":"n","case":"c","why":"w","mood":"sulky","steps":[{"event":"pokes","at":"0s","expect":{"react":"none"}}]}"#, "mood is one of"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","expect":{"offered":"calm|sulky"}}]}"#, "expect.offered has sulky"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","expect":{"animation":"cheer"}}]}"#, "expect.animation is one of"),
                            (#"{"name":"n","case":"c","why":"w","checks":{"moves_on_graph":false},"steps":[{"event":"pokes","at":"0s"}]}"#, "moves_on_graph is true")] {
            let bad = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID().uuidString).json")
            try Data(json.utf8).write(to: bad)
            defer { try? FileManager.default.removeItem(at: bad) }
            do {
                _ = try Scenario(file: bad)
                XCTFail("loaded: \(json)")
            } catch {
                XCTAssertTrue("\(error)".contains(why), "\(error)")
            }
        }
    }

    /// EVALS.md §3: `moves_on_graph` fails a run whose mood answer wasn't
    /// one it was offered, and passes one that only stays or moves along
    /// the graph; the mood output takes nothing else, so the mood itself
    /// never leaves the graph.
    func testMovesOnGraphCatchesAnAnswerThatWasntOffered() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("on-graph-\(UUID().uuidString).json")
        try Data(#"{"name":"n","case":"c","why":"w","checks":{"moves_on_graph":true},"steps":[{"event":"poke","at":"0s"},{"event":"poke","at":"1s"}]}"#.utf8)
            .write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let scenario = try Scenario(file: file)
        let offGraph = ScriptedBrain(always: ["mood": Answer(choice: "grumpy", probabilities: ["grumpy": 1])])
        let wrong = try await Eval(brain: offGraph, steering: RuntimeTests.steering).run(scenario)
        XCTAssertFalse(wrong.passed)
        XCTAssertEqual(wrong.timeline.map(\.mood), ["calm", "calm"], "the mood output took nothing off the graph")
        XCTAssertTrue(wrong.runChecks.first?.detail.hasPrefix("at 0m00s: answered grumpy, offered calm|comfy|curious") == true,
                      wrong.runChecks.first?.detail ?? "")
        let steps = ScriptedBrain { _, questions in
            let options = questions.first { $0.key == "mood" }!.options.map(\.name)
            let pick = options.contains("curious") && options[0] == "calm" ? "curious" : options.contains("skeptical") ? "skeptical" : options[0]
            return ["mood": Answer(choice: pick, probabilities: [pick: 1])]
        }
        let right = try await Eval(brain: steps, steering: RuntimeTests.steering).run(scenario)
        XCTAssertTrue(right.passed, right.runChecks.map(\.summary).joined(separator: "\n"))
        XCTAssertEqual(right.runChecks.first?.detail, "2 passes: calm → curious → skeptical")
    }
}
