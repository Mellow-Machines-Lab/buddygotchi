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

    /// Scenarios with exact checks, kept here: these tests pin the runner, and
    /// a pack's scenarios can go to the judge.
    static var fixtures: URL { CharacterPackTests.repo.appendingPathComponent("internal/app/Tests/Fixtures/evals") }

    func testEveryScenarioReads() throws {
        // Pixel's own, which PixelBuddy's make eval runs, read too.
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
            let brain = ScriptedBrain(always: ["mood": scenario.mood, "react.face": "none"].mapValues { Answer(choice: $0, probabilities: [$0: 1]) })
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
                return ["mood": a("proud"), "react.face": a("proud"), "say": a("glad")]
            }
            if now.contains("failed") {
                return ["mood": a(mood == "calm" ? "annoyed" : "determined"), "react.face": a("determined"),
                        "say": a("tests"), "react.intensity": a("medium")]
            }
            return ["mood": a(mood), "react.face": a("none"), "say": a("none")]
        }
        let scenario = try Scenario(file: Self.fixtures.appendingPathComponent("04-tests-fight-back.json"))
        let result = try await Eval(brain: brain, steering: RuntimeTests.steering).run(scenario)
        XCTAssertEqual(result.checks.count, 4)
        XCTAssertTrue(result.passed, result.checks.filter { !$0.passed }.map(\.summary).joined(separator: "\n"))
        XCTAssertEqual(result.checks[0].mood, "annoyed", "calm moves a step, to annoyed")
        XCTAssertEqual(result.checks[2].say, "tests")
        let said = try XCTUnwrap(result.checks[2].said)
        XCTAssertTrue(Take.all.contains { $0.text == said && $0.meaning == "tests" && $0.moods.contains("determined") }, "determined's: \(said)")
        XCTAssertEqual(result.checks[2].mood, "determined")
        XCTAssertEqual(result.checks[3].mood, "proud", "2 minutes after the last failure: no rule holds a mood")
        let last = try XCTUnwrap(states.all.last)
        XCTAssertTrue(last.contains("\n  Boop had a determined moment (medium), and said \"\(said)\".\n"), last)
    }

    /// EVALS.md §3: a step's `reaction` says how the reactions its passes
    /// start end, so HISTORY can show one still in progress, or leave out
    /// one that didn't happen; any other value doesn't load.
    func testAStepSaysHowItsReactionEnds() async throws {
        let states = Lines()
        let brain = ScriptedBrain { state, _ in
            states.add(state)
            let proud = Answer(choice: "proud", probabilities: ["proud": 1])
            return ["react.face": proud, "mood": proud]
        }
        let eval = Eval(brain: brain, steering: RuntimeTests.steering)
        for (file, shown) in [("11-comeback-still-showing.json", true), ("12-comeback-that-didnt-happen.json", false)] {
            _ = try await eval.run(try Scenario(file: try Self.scenarios().appendingPathComponent(file)))
            let finish = try XCTUnwrap(states.all.last)
            XCTAssertEqual(finish.contains("\n  Boop had a proud moment (small). (in progress)\n"), shown, finish)
            XCTAssertEqual(finish.contains("after failing.\n  Boop had"), shown, "one that didn't happen isn't shown: \(finish)")
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
    /// Jev as their readings, never their words but the phrases kept
    /// (`27-agent-gives-up`); on any other step they don't load, and nor
    /// does a finish's `reading` with no message.
    func testAStepCarriesThePromptAndLastMessage() async throws {
        let states = Lines()
        let brain = ScriptedBrain { state, _ in
            states.add(state)
            return [:]
        }
        _ = try await Eval(brain: brain, steering: RuntimeTests.steering)
            .run(try Scenario(file: Self.fixtures.appendingPathComponent("27-agent-gives-up.json")))
        XCTAssertTrue(states.all.first?.contains("\nYou asked claude on \"landing\" for a fix, in a few words.") == true, states.all.first ?? "no pass")
        XCTAssertFalse(states.all.joined().contains("fix the login redirect"), "the prompt's words never reach Jev")
        XCTAssertTrue(states.all.last?.contains(#"\#nclaude finished turn 1 on "landing": done, a long turn, no tool calls, giving up, saying it couldn't finish.\#n  Its words: "I'm stuck"."#) == true,
                      states.all.last ?? "no pass")
        XCTAssertFalse(states.all.joined().contains("login working"), "nor the message's")
        for (json, why) in [(#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","prompt":"hi","expect":{"react":"none"}}]}"#, "step 1: prompt is only"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"turn failed","at":"0s","message":"hi","expect":{"react":"none"}}]}"#, "step 1: message is only"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"turn finished","at":"0s","reading":{"kind":"done"},"expect":{"react":"none"}}]}"#, "step 1: a finish's reading is its message's"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"turn finished","at":"0s","message":"ok","reading":{"kind":"fix"},"expect":{"react":"none"}}]}"#, "kind is one of done, stuck")] {
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
        let scenario = try Scenario(file: Self.fixtures.appendingPathComponent("05-pokes-glad-miffed-grumpy.json"))
        let result = try await Eval(brain: ScriptedBrain(always: [:]), steering: RuntimeTests.steering).run(scenario)
        XCTAssertFalse(result.passed)
        let report = Eval.report([result])
        XCTAssertEqual(report.first, "FAIL  05-pokes-glad-miffed-grumpy.json  Pokes make Boop curious, then miffed, then fed up")
        XCTAssertTrue(report[1].contains("wanted react amused|curious|excited|happy|mischievous, move none, said some, mood curious|happy, offered "), report[1])
        XCTAssertTrue(report[1].contains("; got react none, move none, intensity none, say none, said none, mood calm, offered "), report[1])
        XCTAssertEqual(Eval.summary([[result]]), "0/1 passed")
    }

    /// EVALS.md §3: a scenario without a case doesn't load, nor one with a
    /// check it doesn't know.
    func testAScenarioNeedsItsCaseAndKnownChecks() throws {
        for (json, why) in [(#"{"name":"n","why":"w","steps":[{"event":"pokes","at":"0s","expect":{"react":"none"}}]}"#, "needs name, case"),
                            (#"{"name":"n","case":"c","why":"w","checks":{"max_fun":2},"steps":[{"event":"pokes","at":"0s"}]}"#, "checks has only"),
                            (#"{"name":"n","case":"c","why":"w","checks":{"reactions":"lots"},"steps":[{"event":"pokes","at":"0s"}]}"#, "checks.reactions"),
                            (#"{"name":"n","case":"c","why":"w","runs":0,"steps":[{"event":"pokes","at":"0s","expect":{"react":"none"}}]}"#, "runs is a count"),
                            (#"{"name":"n","case":"c","why":"w","nature":"sweet","steps":[{"event":"pokes","at":"0s","expect":{"react":"none"}}]}"#, "unknown key nature"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"turn failed","at":"0s","agent":"codex","expect":{"react":"none"}}]}"#, "Codex has no hook"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","count":0,"expect":{"react":"none"}}]}"#, "count is for pokes"),
                            (#"{"name":"n","case":"c","why":"w","checks":{"words_said":"half"},"steps":[{"event":"pokes","at":"0s"}]}"#, "checks.words_said"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"to-do list","at":"0s","expect":{"todo":"1/4"}}]}"#, "to-do list needs todos"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"to-do list","at":"0s","todos":"5/4","expect":{"todo":"1/4"}}]}"#, "to-do list needs todos"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"command","at":"0s","todos":"1/4","expect":{"todo":"1/4"}}]}"#, "todos is only for to-do list"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"needs you","at":"0s","expect":{"needs":"yes"}}]}"#, "expect.needs is shown or none"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"wait","at":"0s","expect":{"todo":"lots"}}]}"#, "expect.todo is like 3/7")] {
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

    /// EVALS.md §1: a run's prompt has the TALK the scenario says, after
    /// MOOD, as the app's does: normal unless it says.
    func testAScenarioRunsWithItsTalk() async throws {
        try requirePack("boop")  // its steering
        for (talk, words) in [(nil, ""), ("quiet", "\nTalk: quiet."), ("chatty", "\nTalk: chatty.")] {
            let states = Lines()
            let brain = ScriptedBrain { state, _ in
                states.add(state)
                return [:]
            }
            let field = talk.map { #","talk":"\#($0)""# } ?? ""
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("talk-\(UUID().uuidString).json")
            try Data(#"{"name":"t","case":"c","why":"w"\#(field),"steps":[{"event":"poke","at":"0s","expect":{"mood":"calm"}}]}"#.utf8).write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            let scenario = try Scenario(file: file)
            XCTAssertEqual(scenario.talk.rawValue, talk ?? "normal")
            _ = try await Eval(brain: brain, steering: RuntimeTests.steering).run(scenario)
            let state = try XCTUnwrap(states.all.first)
            let mood = try XCTUnwrap(state.range(of: "\nMOOD\n"), state)
            XCTAssertFalse(state.contains("\nTALK"), "no TALK section")
            guard !words.isEmpty else {
                XCTAssertFalse(state.contains("Talk:"), "normal shows no Talk row")
                continue
            }
            let row = try XCTUnwrap(state.range(of: words), state)
            XCTAssertLessThan(mood.lowerBound, row.lowerBound, "CONTEXT's Talk row follows MOOD")
        }
    }

    /// EVALS.md §2: an always scenario runs 3 times at the full level and
    /// once below it, the rest once, unless the file says; and what a run
    /// costs is its passes, counted with the expect brain before Jev is
    /// asked anything.
    func testRunsAndTheirCost() async throws {
        let all = try Scenario.load(directory: try Self.scenarios())
        let always = try XCTUnwrap(all.first { $0.always && $0.runs == nil })
        let tuning = try XCTUnwrap(all.first { !$0.always && $0.runs == nil })
        XCTAssertEqual(Eval.plan(always, level: .full, named: false)?.runs, 3)
        XCTAssertEqual(Eval.plan(always, level: .standard, named: false)?.runs, 1)
        XCTAssertEqual(Eval.plan(always, level: .quick, named: false)?.runs, 1)
        XCTAssertEqual(Eval.plan(tuning, level: .full, named: false)?.runs, 1)
        var busy = try XCTUnwrap(all.first { $0.file.hasPrefix("53-") })
        busy.always = true
        busy.scripted = false
        XCTAssertEqual(Eval.plan(busy, level: .full, named: false)?.runs, 1, "a scenario's own runs win: 53 says 1, the code already holds its moves to the graph")
        // 05's four pokes, a second apart then a turn start: a pass each.
        let pokes = try Scenario(file: Self.fixtures.appendingPathComponent("05-pokes-glad-miffed-grumpy.json"))
        let price = try await Eval.price(pokes, steering: RuntimeTests.steering)
        XCTAssertEqual(price.all, 4)
    }

    /// EVALS.md §2: which scenarios each level runs, and which brain answers
    /// which pass.
    func testLevelsSayWhoAnswers() async throws {
        let all = try Scenario.load(directory: try Self.scenarios())
        let feel = try XCTUnwrap(all.first { $0.brief != nil })
        let must = try XCTUnwrap(all.first { $0.brief == nil && $0.checks == nil && !$0.scripted })
        let checked = try XCTUnwrap(all.first { $0.brief == nil && $0.checks != nil && !$0.scripted })
        let rules = try XCTUnwrap(all.first(where: \.scripted))
        XCTAssertNil(Eval.plan(feel, level: .quick, named: false), "quick runs the musts")
        XCTAssertNotNil(Eval.plan(feel, level: .quick, named: true), "and a feel scenario --only names")
        XCTAssertEqual(Eval.plan(feel, level: .quick, named: true)?.scriptsSetup, false, "in full, for the judge")
        XCTAssertNotNil(Eval.plan(feel, level: .standard, named: false))
        XCTAssertNotNil(Eval.plan(checked, level: .quick, named: false), "a must with whole-run checks runs at quick")
        XCTAssertEqual(Eval.plan(checked, level: .quick, named: true)?.scriptsSetup, false, "and plays in full: they read every pass")
        XCTAssertEqual(Eval.plan(must, level: .quick, named: true)?.scriptsSetup, true)
        XCTAssertEqual(Eval.plan(must, level: .standard, named: true)?.scriptsSetup, false)
        XCTAssertEqual(Eval.plan(must, level: .full, named: true)?.scriptsSetup, false)
        XCTAssertNil(Eval.plan(rules, level: .full, named: true), "a scripted scenario never goes to Jev")
        XCTAssertEqual(Eval.plan(must, level: .quick, named: false)?.rerunsOnFailure, true, "a must's failure gets one re-run")
        XCTAssertEqual(Eval.plan(feel, level: .quick, named: true)?.rerunsOnFailure, false, "a feel scenario's is the judge's call")
        XCTAssertEqual(Eval.plan(must, level: .quick, named: false, given: 3)?.rerunsOnFailure, false, "--runs says how many")

        // A setup step and a checked step: each pass says who answered.
        let scenario = try XCTUnwrap(all.first { s in
            s.brief == nil && s.checks == nil && !s.scripted && s.steps.contains(where: \.asksJev) && s.steps.contains { !$0.asksJev && $0.event != "session started" }
        })
        let quick = try await whoAnswers(scenario, steering: RuntimeTests.steering, scriptsSetup: true)
        XCTAssertFalse(quick.isEmpty)
        for pass in quick {
            XCTAssertEqual(pass.brain, scenario.steps[pass.step - 1].asksJev ? "stand-in" : "expect", "step \(pass.step)")
        }
        XCTAssertTrue(quick.contains { $0.brain == "expect" }, "a setup pass costs nothing")
        let full = try await whoAnswers(scenario, steering: RuntimeTests.steering, scriptsSetup: false)
        XCTAssertTrue(full.allSatisfy { $0.brain == "stand-in" })
    }

    /// EVALS.md §1: a feel scenario has a brief, checks none of Jev's choices,
    /// and its run goes to the judge as a trajectory that says who answered.
    func testAFeelScenarioIsForTheJudge() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("feel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ text: String) throws -> URL {
            let file = dir.appendingPathComponent("\(UUID().uuidString).json")
            try text.write(to: file, atomically: true, encoding: .utf8)
            return file
        }
        let head = #""name":"n","judge":"j","reasonable":"r","unreasonable":"u","steps":"#
        let step = #"{"event":"pokes","at":"0s","brain":{"mood":"curious"}}"#
        let scenario = try Scenario(file: try write("{\(head)[\(step)]}"))
        XCTAssertEqual(scenario.brief?.judge, "j")
        let result = try await Eval(brain: ExpectBrain(), steering: RuntimeTests.steering).run(scenario)
        XCTAssertTrue(result.passed, "no exact checks to fail")
        let line = Eval.trajectory(result, scenario: scenario)
        XCTAssertEqual(line["group"] as? String, "feel")
        let pass = try XCTUnwrap((line["passes"] as? [[String: Any]])?.first)
        XCTAssertEqual(pass["brain"] as? String, "expect")
        XCTAssertEqual(pass["mood"] as? String, "curious", "a step's brain answers still play")
        XCTAssertNotNil((line["brief"] as? [String: String])?["unreasonable"])
        XCTAssertThrowsNoShim { _ = try Scenario(file: try write(#"{\#(head)[{"event":"pokes","at":"0s","expect":{"mood":"curious"}}]}"#)) }
        XCTAssertThrowsNoShim { _ = try Scenario(file: try write(#"{"always":true,\#(head)[\#(step)]}"#)) }
    }

    private func XCTAssertThrowsNoShim(_ body: () throws -> Void, line: UInt = #line) {
        do {
            try body()
            XCTFail("should have refused it", line: line)
        } catch {}
    }

    /// EVALS.md §2: the day's limit adds up across commands, refuses a run
    /// over it, gives way to the override, and starts again the next day.
    func testTheDailyLimit() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("limit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("count.json")
        final class Day: @unchecked Sendable { var name = "2026-11-01" }
        let day = Day()
        func allowance(overridden: Bool = false) -> JevAllowance {
            JevAllowance(file: file, limit: 3, overridden: overridden, today: { day.name })
        }
        XCTAssertEqual(JevAllowance.dailyLimit, 2500, "the owner's limit")

        // Two commands share the file.
        let echo = ScriptedBrain(always: [:])
        let first = CountedBrain(echo, allowance: allowance())
        _ = try await first.answer(state: "", questions: [], deadline: .seconds(1))
        _ = try await first.answer(state: "", questions: [], deadline: .seconds(1))
        XCTAssertEqual(first.requests, 2)
        try XCTAssertEqual(try allowance().used(), 2)

        // Over what's left, the run is refused and says the numbers.
        let refusal = try XCTUnwrap(try allowance().refusal(estimate: 2))
        XCTAssertTrue(refusal.contains("2 used"), refusal)
        XCTAssertTrue(refusal.contains("1 left"), refusal)
        try XCTAssertNil(try allowance().refusal(estimate: 1))

        // A whole full run needs the override, even when it fits.
        try XCTAssertNotNil(try allowance().refusal(estimate: 1, wholeFullRun: true))
        try XCTAssertNil(try allowance(overridden: true).refusal(estimate: 1, wholeFullRun: true))

        // Reaching it partway stops the brain, which asks nothing more.
        let second = CountedBrain(echo, allowance: allowance())
        _ = try await second.answer(state: "", questions: [], deadline: .seconds(1))
        XCTAssertNil(second.stopped)
        do {
            _ = try await second.answer(state: "", questions: [], deadline: .seconds(1))
            XCTFail("past the limit")
        } catch {}
        XCTAssertNotNil(second.stopped)
        XCTAssertEqual(second.requests, 1)
        try XCTAssertEqual(try allowance().used(), 3)

        // The override goes past it, and still counts.
        try XCTAssertNil(try allowance(overridden: true).refusal(estimate: 50))
        let over = CountedBrain(echo, allowance: allowance(overridden: true))
        _ = try await over.answer(state: "", questions: [], deadline: .seconds(1))
        try XCTAssertEqual(try allowance().used(), 4)

        day.name = "2026-11-02"
        try XCTAssertEqual(try allowance().used(), 0)
        day.name = "2026-11-01"

        // With no count to trust, no requests.
        try Data("not a count".utf8).write(to: file)
        do {
            _ = try allowance().used()
            XCTFail("a count that doesn't read")
        } catch {}
    }

    /// EVALS.md §3's whole-run checks, against a brain that makes the same
    /// excited face, saying nothing, at every pass and never changes the mood, over
    /// five quick wins: it's the same reaction ten times running (starts
    /// and finishes), of one kind, and the mood never moves.
    func testWholeRunChecksCatchTheSameReactionAgainAndAgain() async throws {
        let brain = ScriptedBrain(always: ["react.face": Answer(choice: "excited", probabilities: ["excited": 0.9]),
                                           "say": Answer(choice: "none", probabilities: ["none": 0.9])])
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
        XCTAssertTrue(Eval.timeline(result).contains { $0.contains("→ excited, small  [calm]") },
                      Eval.timeline(result).joined(separator: "\n"))
    }

    /// The quiet and mood checks, on a made-up run: a turn from 0 to 20
    /// minutes with reactions at 1 and 9 minutes is quiet for 11 minutes
    /// at the end; happy → determined → happy inside 40 s is a bounce.
    func testQuietAndBounceChecks() {
        func pass(_ s: Int64, _ face: String?, _ mood: String) -> Eval.Pass {
            Eval.Pass(atMs: s * 1000, line: "l", reaction: face.map { Eval.Reaction(face: $0, move: "none", said: "none") },
                      intensity: face == nil ? nil : "small", mood: mood, dropped: nil)
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

    /// `moods_seen`: a mood that came and went between two steps counts;
    /// one never reached fails, saying what was.
    func testMoodsSeenCountsAMoodThatCameAndWent() {
        let pass = { (s: Int64, mood: String) in Eval.Pass(atMs: s * 1000, line: "l", reaction: nil, intensity: nil, mood: mood, dropped: nil) }
        var checks = Scenario.Checks()
        checks.moodsSeen = ["lonely", "sad"]
        let out = Eval.judge(checks, timeline: [pass(60, "calm"), pass(120, "lonely"), pass(180, "calm")], working: [])
        XCTAssertEqual(out.map(\.passed), [true, false])
        XCTAssertEqual(out[0].detail, "lonely from 2m00s")
        XCTAssertEqual(out[1].detail, "never sad: calm, lonely")
    }

    /// EVALS.md §3: a scenario may start in any mood (`mood`, as the
    /// dashboard would set it just before), and a step may check exactly
    /// what its pass's mood question offered (`offered`): staying, and the
    /// mood's moves on the graph.
    func testAScenarioStartsInItsMoodAndChecksWhatWasOffered() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("start-mood-\(UUID().uuidString).json")
        let grumpy = (["grumpy"] + MoodGraph.neighbours["grumpy"]!.all).joined(separator: "|")
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
        XCTAssertEqual(result.checks[1].offered, ["irritated"] + MoodGraph.neighbours["irritated"]!.all)
        XCTAssertFalse(result.checks[1].passed)
        XCTAssertTrue(result.checks[1].summary.hasSuffix(", offered " + (["irritated"] + MoodGraph.neighbours["irritated"]!.all).sorted().joined(separator: "|")),
                      result.checks[1].summary)
        XCTAssertTrue(result.checks[1].summary.contains("wanted offered calm|happy; got react none"), result.checks[1].summary)
        for (json, why) in [(#"{"name":"n","case":"c","why":"w","mood":"sulky","steps":[{"event":"pokes","at":"0s","expect":{"react":"none"}}]}"#, "mood is one of"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","expect":{"offered":"calm|sulky"}}]}"#, "expect.offered has sulky"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","expect":{"move":"cheer"}}]}"#, "expect.move has cheer"),
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

    /// EVALS.md §1: a leading `!` takes values away from everything a
    /// key may be: `!none` is every face, `!lonely` every lasting mood but
    /// lonely, `!swear` every say but a swear; on another key, or taking
    /// away a value the key hasn't, the scenario doesn't load.
    func testAnExpectationCanBeAnythingBut() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("but-\(UUID().uuidString).json")
        try Data(#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","expect":{"react":"!none","mood":"!lonely","say":"!swear"}}]}"#.utf8)
            .write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let expect = try XCTUnwrap(try Scenario(file: file).steps.first?.expect)
        XCTAssertEqual(expect.react, Set(CharacterPack.active.moods.map(\.id)))
        XCTAssertEqual(expect.mood, Set(MoodGraph.moods).subtracting(["lonely"]))
        XCTAssertEqual(expect.say, Set(MomentOutput.says.map(\.name) + ["none"]).subtracting(["swear"]))
        for (json, why) in [(#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","expect":{"move":"!none"}}]}"#, "expect.move can't take !"),
                            (#"{"name":"n","case":"c","why":"w","steps":[{"event":"pokes","at":"0s","expect":{"mood":"!sulky"}}]}"#, "expect.mood takes away sulky")] {
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
            let pick = options.contains("curious") && options[0] == "calm" ? "curious" : options.contains("happy") ? "happy" : options[0]
            return ["mood": Answer(choice: pick, probabilities: [pick: 1])]
        }
        let right = try await Eval(brain: steps, steering: RuntimeTests.steering).run(scenario)
        XCTAssertTrue(right.passed, right.runChecks.map(\.summary).joined(separator: "\n"))
        XCTAssertEqual(right.runChecks.first?.detail, "2 passes: calm → curious → happy")
    }

    /// EVALS.md §2: every scenario passes with the expect brain, which
    /// answers each pass as its step expects (its own `brain`, else the
    /// first of each `expect` set, the mood a move at a time toward what a
    /// step wants). What it checks is everything but Jev: that each step
    /// wakes the brain as it says, that the moods it expects lie on the
    /// graph's paths, and the whole-run checks a run can fail without Jev.
    func testEveryScenarioPassesWithTheExpectBrain() async throws {
        for scenario in try Scenario.load(directory: try Self.scenarios()) {
            let result = try await Eval(brain: ExpectBrain(), steering: RuntimeTests.steering).run(scenario)
            XCTAssertTrue(result.passed, "\(scenario.file):\n" + (result.checks.filter { !$0.passed }.map(\.summary)
                + result.runChecks.filter { !$0.passed }.map(\.summary)).joined(separator: "\n"))
        }
    }

    /// An eval's hooks say which process the agent is, as a real agent's
    /// do, and its agent runs all through it: a request waits past the 10
    /// silent minutes (SessionFold.safetyNetMs) that clear one from a hook
    /// that doesn't say. A held finger (`dismiss`) hides it, and the
    /// session's next request shows.
    func testARequestWaitsAsLongAsItsAgentRuns() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lunch-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try (#"{"name":"n","case":"c","why":"w","steps":[{"event":"turn started","at":"0s"},"#
            + #"{"event":"needs you","at":"1m","expect":{"needs":"shown"}},"#
            + #"{"event":"wait","at":"11m1s","expect":{"needs":"shown"}},"#
            + #"{"event":"gesture","at":"12m","kind":"dismiss","expect":{"needs":"none","idle":"1"}},"#
            + #"{"event":"needs you","at":"13m","expect":{"needs":"shown","todo":"none"}}]}"#)
            .write(to: file, atomically: true, encoding: .utf8)
        let result = try await Eval(brain: ExpectBrain(), steering: RuntimeTests.steering).run(try Scenario(file: file))
        XCTAssertTrue(result.passed, result.checks.filter { !$0.passed }.map(\.summary).joined(separator: "\n"))
    }

    /// EVALS.md §3: a scenario's `start` sets the virtual clock, in UTC,
    /// which CONTEXT's When row shows; a step's `brain` answers for the
    /// expect brain ahead of its `expect`.
    func testAScenarioStartsAtItsStartAndAStepMayAnswer() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("start-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("s.json")
        try #"{"name":"n","case":"c","why":"w","start":"2026-10-31T09:00","steps":[{"event":"poke","at":"0s","brain":{"react.face":"amused"},"expect":{"react":"curious|amused"}}]}"#
            .write(to: file, atomically: true, encoding: .utf8)
        let scenario = try Scenario(file: file)
        XCTAssertEqual(scenario.start, 1_793_437_200_000, "2026-10-31 09:00 UTC")
        let states = Lines()
        final class Seeing: Brain, @unchecked Sendable {
            let id = "seeing"
            let inner = ExpectBrain()
            let states: Lines
            init(_ states: Lines) { self.states = states }
            func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
                states.add(state)
                return try await inner.answer(state: state, questions: questions, deadline: deadline)
            }
        }
        let expect = ExpectBrain()
        let result = try await Eval(brain: expect, steering: RuntimeTests.steering).run(scenario)
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.checks.first?.react, "amused", "the step's own answer comes first")
        _ = try await Eval(brain: Seeing(states), steering: RuntimeTests.steering).run(scenario)
        XCTAssertTrue(states.all.first?.contains("\nWhen: 09:00, Saturday, morning; Halloween.\n") == true,
                      "CONTEXT's When row says the occasion: " + (states.all.first ?? ""))
        XCTAssertTrue(states.all.first?.contains("\nNOW (09:00)\n") == true,
                      "and NOW's heading only the moment's time: " + (states.all.first ?? ""))
        try #"{"name":"n","case":"c","why":"w","start":"Halloween","steps":[{"event":"poke","at":"0s","expect":{"react":"none"}}]}"#
            .write(to: file, atomically: true, encoding: .utf8)
        try XCTAssertThrowsError(try Scenario(file: file)) { XCTAssertTrue("\($0)".contains("start is a UTC date and time")) }
    }
}

/// Each pass of a run and the brain that answered it, with a stand-in for Jev.
private func whoAnswers(_ scenario: Scenario, steering: Steering, scriptsSetup: Bool) async throws -> [(step: Int, brain: String?)] {
    struct StandIn: Brain {
        let id = "stand-in"
        func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
            try await ExpectBrain().answer(state: state, questions: questions, deadline: deadline)
        }
    }
    final class Heard: @unchecked Sendable { var passes: [(step: Int, brain: String?)] = [] }
    let heard = Heard()
    var runner = Eval(brain: StandIn(), steering: steering)
    runner.scriptsSetup = scriptsSetup
    runner.onPass = { step, pass in heard.passes.append((step, pass.brain)) }
    _ = try await runner.run(scenario)
    return heard.passes
}
