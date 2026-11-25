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

    /// Pins that a seat takes Jev's answer only as sure as its output
    /// needs: you say "thanks!", the rules reply thanks, sure; a Jev
    /// guessing at 0.3, under `MomentOutput.replyFloor`, leaves the rules'
    /// reply, which plays, where taking it would have played a `huh`. At
    /// the floor it's Jev's. Every other seat takes any probability.
    func testAnUnsureJevLeavesTheRulesSureReply() async throws {
        XCTAssertEqual(MomentOutput.replyFloor, 0.35)
        var said = Event(at: 0, source: .mic, type: .said, specificType: "said", data: ["words": "thanks!"])
        said.seq = 1
        let replies = question(MomentOutput.replyKey, MomentOutput.replies.map(\.name))
        func jev(_ p: Double) -> ScriptedBrain {
            ScriptedBrain(id: "jev-test") { _, _ in
                [MomentOutput.replyKey: Answer(choice: "hehe", probabilities: ["hehe": p, "thanks": p]),
                 MoodOutput.outputName: Answer(choice: "proud", probabilities: ["proud": 0.1])]
            }
        }
        func reply(_ jev: (any Brain)?) async throws -> Answers {
            let seated = SeatedBrain(rules: rules([:]), jev: jev)
            return try await seated.reading(now: said, log: Log().view(now: 0))
                .answer(state: "", questions: [replies, questions[0]], deadline: .seconds(1))
        }
        let alone = try await reply(nil)
        XCTAssertEqual(MomentOutput.reply(alone), "thanks", "the rules, sure")
        let unsure = try await reply(jev(0.3))
        XCTAssertEqual(unsure[MomentOutput.replyKey], alone[MomentOutput.replyKey], "under the floor: the rules' reply")
        XCTAssertEqual(MomentOutput.reply(unsure), "thanks", "not a huh")
        XCTAssertEqual(unsure[MoodOutput.outputName]?.choice, "proud", "the mood has no floor")
        let sure = try await reply(jev(0.35))
        XCTAssertEqual(MomentOutput.reply(sure), "hehe", "at the floor: Jev's")
    }

    /// Pins the pass's brain as the transcript keeps it: whose answers the
    /// pass played. `rules` when Jev was absent, late or failing, or took
    /// no seat; else `rules+` Jev's id and the seats it took. Through the
    /// harness, each pass of a run says the same.
    func testThePassSaysWhoseAnswersItPlayed() async throws {
        func id(_ jev: (any Brain)?, deadline: Duration = .seconds(1)) async throws -> String {
            let call = SeatedBrain(rules: rules(), jev: jev, margin: .milliseconds(100)).reading(now: Self.end, log: Log().view(now: 0))
            _ = try await call.answer(state: "", questions: questions, deadline: deadline)
            return call.id
        }
        let absent = try await id(nil)
        let late = try await id(Sleepy(answering: Self.last, for: .seconds(5)), deadline: .milliseconds(150))
        let failing = try await id(ScriptedBrain(id: "jev-test") { _, _ in throw BrainError("jev: HTTP 503", status: 503) })
        let none = try await id(ScriptedBrain(id: "jev-test") { _, _ in [MomentOutput.emotionKey: Answer(choice: "elated", probabilities: ["elated": 1])] })
        XCTAssertEqual([absent, late, failing, none], ["rules", "rules", "rules", "rules"])
        let all = try await id(Self.last)
        XCTAssertEqual(all, "rules+jev-test:mood,react.face,react.reply,react.sign,skit.take")
        let one = try await id(ScriptedBrain(id: "jev-test") { _, _ in [MoodOutput.outputName: Answer(choice: "proud", probabilities: ["proud": 1])] })
        XCTAssertEqual(one, "rules+jev-test:mood", "only the seat it took")

        try requirePack("boop")
        let scenario = try XCTUnwrap(try Scenario.load(directory: try EvalTests.scenarios()).first { $0.file.hasPrefix("04-") })
        let timedOut = try await Self.brains(scenario, jev: Sleepy(answering: Self.last, for: .seconds(5)), margin: .milliseconds(1480),
                                             steering: RuntimeTests.steering)
        XCTAssertEqual(timedOut, ["rules"], "Jev late: every pass is the rules'")
        let inTime = try await Self.brains(scenario, jev: Self.last, margin: .milliseconds(100), steering: RuntimeTests.steering)
        XCTAssertFalse(inTime.isEmpty)
        XCTAssertTrue(inTime.allSatisfy { $0.hasPrefix("rules+jev-test:") && $0.contains("mood") }, "\(inTime)")
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
    /// The brains every pass of `scenario` says it played, with Jev seated.
    nonisolated static func brains(_ scenario: Scenario, jev: any Brain, margin: Duration, steering: Steering) async throws -> Set<String> {
        let seen = Lines()
        var eval = Eval(brain: ScriptedBrain { _, _ in [:] }, steering: steering)
        eval.rules = true
        eval.seated = { rules in SeatedBrain(rules: rules, jev: jev, margin: margin) }
        eval.onPass = { _, pass in if let brain = pass.brain { seen.add(brain) } }
        _ = try await eval.run(scenario)
        return Set(seen.all)
    }

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

extension SeatedBrainTests {
    /// Jev is timed from the pass's start, which the harness times from
    /// just after it reads the event: a call answered a while after that
    /// still ends by the pass's deadline, less the margin, and no later.
    func testJevIsTimedFromThePassesStart() async throws {
        let never = Sleepy(answering: Self.last, for: .seconds(5))
        let call = SeatedBrain(rules: rules(), jev: never).reading(now: Self.end, log: Log().view(now: 0))
        let read = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(600))
        _ = try await call.answer(state: "", questions: questions, deadline: .milliseconds(1500))
        let took = ContinuousClock.now - read
        // Timed from the call it would take 2000 ms. The bound leaves a busy
        // machine (CI's) room to wake late; the harness test below holds
        // the deadline itself.
        XCTAssertLessThan(took, .milliseconds(1800), "from the pass's start, not from the call")
        XCTAssertGreaterThanOrEqual(took, .milliseconds(1400), "Jev had the time the pass gave it")
    }

    /// Through the harness's own loop, its 1500 ms deadline and the
    /// default margin: a Jev that never answers changes nothing, and the
    /// pass plays the rules' answers, never dropped as late.
    func testWithTheDefaultMarginAJevThatNeverAnswersDropsNoPass() async throws {
        let queue = DispatchQueue(label: "seated.test")
        let seated = SeatedBrain(rules: rules(), jev: Sleepy(answering: Self.last, for: .seconds(5)))
        XCTAssertEqual(seated.margin, SeatedBrain.margin)
        let output = Played(questions: questions)
        let harness = Harness(name: "Pip", brain: seated, log: Log(), queue: queue)
        queue.sync {
            XCTAssertEqual(harness.options.deadlineMs, 1500)
            harness.input("turn", wake: 1) { _, _ in "A turn ended." }
            harness.output(output)
            _ = harness.emit(source: "claude", kind: "turn")
        }
        func pass() -> Event? { queue.sync { harness.log.events.last { $0.kind == Event.pass } } }
        let started = ContinuousClock.now
        while pass() == nil, ContinuousClock.now - started < .seconds(5) { try await Task.sleep(for: .milliseconds(20)) }
        let got = try XCTUnwrap(pass())
        XCTAssertEqual(got["dropped"], .null, "not dropped as late")
        XCTAssertEqual(got["brain"]?.string, "rules", "the rules' answers")
        XCTAssertEqual(queue.sync { output.got.count }, 1, "the Moment's output ran")
    }
}

/// An output that asks `questions` and keeps the answers it's handed.
final class Played: Output, @unchecked Sendable {
    let name = "played"
    let asked: [Question]
    var got: [Answers] = []
    init(questions: [Question]) { asked = questions }
    func questions(now: Event?, log: LogView) -> [Question] { asked }
    func run(_ answers: Answers, now: Event?, log: LogView) -> OutputResult? {
        got.append(answers)
        return OutputResult(ok: true, message: "played")
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
