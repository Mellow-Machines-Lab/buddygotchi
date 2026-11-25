import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The one brain (`SeatedBrain`): the rules always answer, and Jev, here a
/// scripted brain standing in for it, may replace an answer in a seat, in
/// time and with one of the question's options, or changes nothing.
final class SeatedBrainTests: XCTestCase {
    typealias Facts = [String: JSONValue]

    /// A long turn done, as its line's facts say.
    static let finish: Facts = ["outcome": "done", "length": "long", "tools": 3, "length_ms": 120_000]
    static let end: Event = {
        var e = Event(at: 0, source: .claude, type: .turn, phase: .end, specificType: "Stop")
        e.seq = 1
        return e
    }()

    func rules(_ facts: Facts = SeatedBrainTests.finish) -> RulesBrain {
        RulesBrain(seed: 7, facts: { _ in facts }, mood: { _ in ("calm", 1) })
    }

    func question(_ key: String, _ names: [String]) -> Question {
        Question(key: key, text: "?", about: "the NOW section", judgeBy: "x", options: names.map { Option($0, $0) })
    }

    /// One question for each seat, and one that isn't.
    var questions: [Question] {
        [question(MoodOutput.outputName, ["calm", "happy", "proud"]), question(MomentOutput.emotionKey, ["none", "pleased", "proud"]),
         question(MomentOutput.replyKey, ["huh", "yes", "no"]), question(Signs.questionKey, ["none", "yay!", "phew"]),
         question(MomentOutput.takeKey, ["Nice.", "Done!", "Phew."]), question("other", ["a", "b"])]
    }

    func answers(_ brain: any ReadingBrain, _ questions: [Question], deadline: Duration = .seconds(1)) async throws -> Answers {
        try await brain.reading(now: Self.end, log: Log().view(now: 0)).answer(state: "", questions: questions, deadline: deadline)
    }

    /// The choices, by key.
    func choices(_ a: Answers) -> [String: String] { a.mapValues(\.choice) }

    /// A Jev that answers every question with its last option.
    nonisolated static let last = ScriptedBrain(id: "jev-test") { _, questions in
        Dictionary(uniqueKeysWithValues: questions.map { q in (q.key, Answer(choice: q.options.last!.name, probabilities: [q.options.last!.name: 0.8])) })
    }

    /// The seats, pinned: the mood, the face, the reply and its sign, and
    /// which take a skit says.
    func testTheSeats() {
        XCTAssertEqual(SeatedBrain.seats, ["mood", "react.face", "react.reply", "react.sign", "skit.take"])
    }

    /// Jev in time takes every seat with its own answer, probabilities and
    /// all, and a question that isn't a seat stays the rules'.
    func testJevInTimeReplacesEachSeat() async throws {
        let reports = Lines()
        let seated = SeatedBrain(rules: rules(), jev: Self.last) { reports.add($0?.description ?? "answered") }
        let got = try await answers(seated, questions)
        let alone = try await answers(rules(), questions)
        for q in questions where q.key != "other" {
            XCTAssertEqual(got[q.key]?.choice, q.options.last?.name, q.key)
            XCTAssertEqual(got[q.key]?.probabilities, [q.options.last!.name: 0.8], q.key)
        }
        XCTAssertEqual(got["other"], alone["other"], "not a seat: the rules'")
        XCTAssertEqual(reports.all, ["answered"])
        XCTAssertEqual(seated.id, "jev-test")
    }

    /// A Jev slower than the pass's deadline, less the margin, changes
    /// nothing, isn't waited for, and is reported late once.
    func testJevTooSlowChangesNothing() async throws {
        let reports = Lines()
        let slow = ScriptedBrain(id: "jev-test") { _, _ in [:] }
        let sleepy = Sleepy(answering: slow, for: .seconds(5))
        let seated = SeatedBrain(rules: rules(), jev: sleepy, margin: .milliseconds(100)) { reports.add($0?.description ?? "answered") }
        let started = ContinuousClock.now
        let got = try await answers(seated, questions, deadline: .milliseconds(150))
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1), "Jev isn't waited for")
        let alone = try await answers(rules(), questions)
        XCTAssertEqual(choices(got), choices(alone))
        XCTAssertEqual(reports.all, ["late: no answer within 50 ms"])
    }

    /// A Jev that throws changes nothing, and is reported once, with its
    /// error.
    func testJevThrowingChangesNothingAndIsReportedOnce() async throws {
        let reports = Lines()
        let failing = ScriptedBrain(id: "jev-test") { _, _ in throw BrainError("jev: HTTP 402", status: 402) }
        let seated = SeatedBrain(rules: rules(), jev: failing) { reports.add($0?.description ?? "answered") }
        let got = try await answers(seated, questions)
        let alone = try await answers(rules(), questions)
        XCTAssertEqual(got, alone)
        XCTAssertEqual(reports.all, ["jev: HTTP 402"])
    }

    /// An answer that isn't one of its question's options is ignored for
    /// that question alone; the rest of Jev's answers stand. A question Jev
    /// leaves out keeps the rules' answer.
    func testAnAnswerNotOfferedIsIgnoredForThatQuestionOnly() async throws {
        let odd = ScriptedBrain(id: "jev-test") { _, _ in
            [MomentOutput.emotionKey: Answer(choice: "elated", probabilities: ["elated": 1]),
             MoodOutput.outputName: Answer(choice: "proud", probabilities: ["proud": 1])]
        }
        let got = try await answers(SeatedBrain(rules: rules(), jev: odd), questions)
        let alone = try await answers(rules(), questions)
        XCTAssertEqual(got[MoodOutput.outputName]?.choice, "proud", "offered: Jev's")
        XCTAssertEqual(got[MomentOutput.emotionKey], alone[MomentOutput.emotionKey], "not offered: the rules'")
        XCTAssertEqual(got[MomentOutput.replyKey], alone[MomentOutput.replyKey], "left out: the rules'")
    }

    /// With no Jev it is the rules brain alone, answer for answer, over
    /// many passes of every kind of event, and says nothing of Jev.
    func testNoJevIsTheRulesAlone() async throws {
        let facts: [Facts] = [Self.finish, ["outcome": "failed", "length": "short"], ["in_a_row": 3], [:], ["away_ms": 4_000_000]]
        let events: [Event] = [Self.end, Self.end, Event(at: 0, source: .device, type: .poke, specificType: "input"),
                               Event(at: 0, source: .mic, type: .said, specificType: "said", data: ["words": "hi there"]),
                               Event(at: 0, source: .mac, type: .presence, phase: .end, specificType: "presence")]
        let reports = Lines()
        for (e, f) in zip(events, facts) {
            let seated = SeatedBrain(rules: rules(f), jev: nil) { reports.add($0?.description ?? "answered") }
            let alone = rules(f)
            XCTAssertEqual(seated.id, "rules")
            for _ in 0..<6 {
                let a = try await seated.reading(now: e, log: Log().view(now: 0)).answer(state: "", questions: questions, deadline: .seconds(1))
                let b = try await alone.reading(now: e, log: Log().view(now: 0)).answer(state: "", questions: questions, deadline: .seconds(1))
                XCTAssertEqual(a, b, "\(e.kind)")
            }
        }
        XCTAssertEqual(reports.all, [], "no Jev, no reports")
    }
}

extension SeatedBrainTests {
    /// What every pass of `scenario` did, with each run's rules brain put
    /// in `seated`: its line, its answers and each output's message and
    /// facts, the Moments included.
    nonisolated static func passes(_ scenario: Scenario, seated: (@Sendable (RulesBrain) -> any Brain)?, steering: Steering) async throws -> [String] {
        let passes = Lines()
        var eval = Eval(brain: ScriptedBrain { _, _ in [:] }, steering: steering)
        eval.rules = true
        eval.seated = seated
        eval.onPass = { step, pass in
            let answers = pass.answers.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.choice)" }.joined(separator: ",")
            let outputs = pass.outputs.map { o in
                o.name + ": " + o.result.message + " " + o.result.facts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            }
            passes.add(([String(step), pass.line ?? "-", pass.dropped ?? "", answers] + outputs).joined(separator: " | "))
        }
        _ = try await eval.run(scenario)
        return passes.all
    }

    /// The same recorded run of events gives the same Moments, answers and
    /// moods with no Jev as with a Jev that never answers in time: a few
    /// eval scenarios with failing checks, pokes, your words, you back and
    /// a workday.
    func testAJevThatAlwaysTimesOutChangesNoMoment() async throws {
        try requirePack("boop")
        let picked: Set<String> = ["04", "05", "63", "126", "173"]
        let scenarios = try Scenario.load(directory: try EvalTests.scenarios()).filter { picked.contains(String($0.file.prefix { $0 != "-" })) }
        XCTAssertEqual(scenarios.count, picked.count)
        let reports = Lines()
        // The pass's deadline is the harness's 1500 ms: Jev gets 20 of them.
        let late: @Sendable (RulesBrain) -> any Brain = { rules in
            SeatedBrain(rules: rules, jev: Sleepy(answering: SeatedBrainTests.last, for: .seconds(5)), margin: .milliseconds(1480)) {
                reports.add($0?.description ?? "answered")
            }
        }
        var moments = 0
        for scenario in scenarios {
            let alone = try await Self.passes(scenario, seated: nil, steering: RuntimeTests.steering)
            let seated = try await Self.passes(scenario, seated: late, steering: RuntimeTests.steering)
            XCTAssertEqual(seated, alone, scenario.file)
            moments += alone.filter { $0.contains("react: ") }.count
        }
        XCTAssertGreaterThan(moments, 20, "the scenarios play Moments")
        XCTAssertFalse(reports.all.isEmpty)
        XCTAssertTrue(reports.all.allSatisfy { $0.hasPrefix("late") }, "\(Set(reports.all))")
    }
}

/// A brain that answers as another, after a while: a sleep that a
/// cancelled task cuts short.
struct Sleepy: Brain {
    let answering: any Brain
    let wait: Duration
    var id: String { answering.id }

    init(answering: any Brain, for wait: Duration) {
        self.answering = answering
        self.wait = wait
    }

    func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
        try await Task.sleep(for: wait)
        return try await answering.answer(state: state, questions: questions, deadline: deadline)
    }
}
