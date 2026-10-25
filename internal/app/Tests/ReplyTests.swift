import AgentHooks
import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// What Boop replies to what you said on push-to-talk: the reply the brain
/// picks, and what's looked up from it, the board's clip, the takes and the
/// sign, the agents' facts for a question about them (`StatusReply`).
final class ReplyTests: XCTestCase {
    static let log = Transcript.log().view(now: 0)
    func a(_ choice: String, _ p: Double = 0.9) -> Answer { Answer(choice: choice, probabilities: [choice: p]) }
    let said = Event(at: 0, source: .mic, type: .talk, specificType: "device", data: ["words": "is claude done yet?"])
    let poke = Event(at: 0, source: .device, type: .poke, specificType: "input")
    let lines = TaggedLine.parse("""
        - [hello] hi hi!
        - [hello] oh, hi!
        - [bye] bye bye
        - [bye night] nite nite
        - [yes] yep!
        - [night bye] not first
        """)

    /// The twelve replies, in the order the question offers them; what
    /// you said is asked the face, the reply, how long and how big, in
    /// place of the feeling, the topic and the animation, and anything
    /// else what it always was.
    func testWhatYouSaidIsAskedForAReply() {
        XCTAssertEqual(ReactOutput.replies.map(\.name),
                       ["yes", "no", "dunno", "huh", "hello", "bye", "thanks", "love", "ouch", "comfort", "hehe", "status"])
        let react = ReactOutput(queue: { _, _ in }, blocked: { nil })
        let voiced = Take.all.isEmpty ? ["react.mood", "react.reply", "react.loops"] : ["react.mood", "react.reply", "react.loops", "say.kind"]
        XCTAssertEqual(react.questions(now: said, log: Self.log).map(\.key), voiced)
        XCTAssertEqual(react.questions(now: said, log: Self.log)[1].options.map(\.name), ReactOutput.replies.map(\.name), "no none: talk gets a reply")
        XCTAssertEqual(react.questions(now: said, log: Self.log)[0].options.map(\.name), MoodOutput.moods.map(\.name), "and a face, never none")
        XCTAssertEqual(react.questions(now: poke, log: Self.log).map(\.key), askedKeys.filter { $0 != MoodOutput.outputName })
        for reply in ReactOutput.replies where ["yes", "no"].contains(reply.name) {
            XCTAssertTrue(reply.option.notFor?.contains("status") == true, "yes and no are never about the agents")
        }
    }

    /// A pass forced from outside (a demo's) is about what you said when
    /// that's the latest thing, push-to-talk's listening after it aside.
    func testAForcedPassAfterWhatYouSaidAsksForAReply() {
        let log = Transcript.log()
        log.append(said, now: 1)
        log.append(Event(at: 1, source: .boop, type: .listen, phase: .end, specificType: "device"), now: 1)
        let react = ReactOutput(queue: { _, _ in }, blocked: { nil })
        XCTAssertTrue(react.questions(now: nil, log: log.view(now: 1)).contains { $0.key == "react.reply" })
        log.append(poke, now: 2)
        XCTAssertFalse(react.questions(now: nil, log: log.view(now: 2)).contains { $0.key == "react.reply" })
    }

    /// Pins `sayFloor` for a reply: a missing pick, one below the floor or
    /// one that isn't a reply is `huh`, never silence or a guess.
    func testAnUnsureReplyIsHuh() {
        XCTAssertEqual(ReactOutput.reply(["react.reply": a("love")]).name, "love")
        XCTAssertEqual(ReactOutput.reply(["react.reply": a("love", 0.3)]).name, "huh", "below the floor of 0.35")
        XCTAssertEqual(ReactOutput.reply(["react.reply": a("dance")]).name, "huh")
        XCTAssertEqual(ReactOutput.reply([:]).name, "huh")
    }

    /// A reply rides on the reaction as `reply`, which the board plays its
    /// pack's clip for, holds up its line, says the topic it
    /// borrows in the face's mood, and says so in HISTORY's line; a status
    /// reply holds up the agents' facts.
    func testAReplyPlaysItsClipSignAndTakes() throws {
        var queued: [DeviceReaction] = []
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, replies: lines,
                                status: { e in "facts for \(e["words"]?.string ?? "")".prefix(18).description })
        func run(_ answers: [String: String], _ now: Event) -> String? {
            react.run(answers.mapValues { a($0) }, now: now, log: Self.log)?.message
        }
        let hello = try XCTUnwrap(run(["react.mood": "happy", "react.reply": "hello", "say.kind": "word"], said))
        XCTAssertTrue(hello.hasPrefix("\(creature) made a happy face, replying hello, held once, holding up a sign: "), hello)
        XCTAssertEqual(queued.last?.reply, "hello")
        XCTAssertNil(queued.last?.anim, "it plays over the face")
        XCTAssertTrue(["hi hi!", "oh, hi!"].contains(queued.last?.sign ?? ""), "its line")
        XCTAssertTrue(queued.last?.args.json.contains(#""reply":"hello""#) == true)
        if !Take.all.isEmpty {
            let takes = try XCTUnwrap(queued.last?.say?.takes)
            XCTAssertEqual(takes.map(\.meaning), ["hello"], "the topic it borrows")
            XCTAssertTrue(takes.allSatisfy { $0.moods.contains("happy") })
        }
        _ = run(["react.mood": "engaged", "react.reply": "status"], said)
        XCTAssertEqual(queued.last?.sign, "facts for is claud", "the status closure's, about what you said")
        _ = run(["react.mood": "curious", "react.reply": "dunno"], said)
        XCTAssertNil(queued.last?.sign, "a reply with no line holds up nothing")
        XCTAssertEqual(queued.last?.reply, "dunno")
        _ = run(["react.mood": "happy", "react.reply": "hello", "react.animation": "success"], poke)
        XCTAssertNil(queued.last?.reply, "only what you said gets a reply")
        XCTAssertEqual(queued.last?.anim, "task_complete")
    }

    /// Pins `Signs.reply`: only lines whose first tag is the reply, the
    /// most tags that fit first, never the last one shown while another
    /// fits.
    func testAReplysSign() {
        var rng = SplitMix64(seed: 3)
        XCTAssertEqual(Signs.reply(lines, "bye", calendar: ["night"], rng: &rng), "nite nite", "the night's beats the plain one")
        XCTAssertEqual(Signs.reply(lines, "bye", calendar: ["day"], rng: &rng), "bye bye")
        XCTAssertNil(Signs.reply(lines, "ouch", calendar: [], rng: &rng))
        for _ in 0..<10 {
            let first = Signs.reply(lines, "hello", calendar: [], rng: &rng)
            XCTAssertNotEqual(Signs.reply(lines, "hello", calendar: [], avoiding: first, rng: &rng), first)
        }
        XCTAssertEqual(Signs.reply(lines, "yes", calendar: [], avoiding: "yep!", rng: &rng), "yep!", "the only one, again")
        for _ in 0..<10 {
            XCTAssertNotEqual(Signs.reply(lines, "bye", calendar: ["night"], rng: &rng), "not first", "its reply comes first")
        }
    }

    // MARK: - The agents' facts

    typealias Agent = StatusReply.Agent
    typealias Result = StatusReply.Result
    let min: Int64 = 60_000

    /// Pins the order: something waiting on you, then the work going on
    /// (the latest check of its turn, else its to-do list, else how long),
    /// then how the last of it came out within `recentMs`, else all quiet.
    func testTheFactThatAnswers() {
        let now: Int64 = 100 * min
        let working = Agent(agent: "claude", places: ["landing"], workingSince: now - 4 * min)
        func sign(_ s: [Agent], _ words: String = "how's it going?") -> String { StatusReply.sign(s, words: words, at: now) }
        XCTAssertEqual(sign([working]), "claude: 4 min in")
        XCTAssertEqual(sign([Agent(agent: "claude", places: [], workingSince: now - 20_000)]), "just started", "the agent left off: it won't fit")
        var checked = working
        checked.result = Result(topic: "build", outcome: "failed", at: now - min)
        XCTAssertEqual(sign([checked]), "build failed", "a result of its turn, whatever it checks")
        checked.result = Result(topic: "tests", outcome: "failed", at: now - 5 * min)
        XCTAssertEqual(sign([checked]), "claude: 4 min in", "a check from before its turn isn't its own")
        var listed = working
        listed.todo = StateSnapshot.Todo(done: 3, total: 5)
        XCTAssertEqual(sign([listed]), "claude: 3/5 done")
        XCTAssertEqual(sign([working, Agent(agent: "codex", places: [], workingSince: now)]), "2 working")
        let waiting = Agent(agent: "codex", places: ["api"], needsYou: true)
        XCTAssertEqual(sign([working, waiting]), "codex needs you", "waiting on you comes first")
        XCTAssertEqual(sign([waiting, waiting]), "2 need you")

        XCTAssertEqual(StatusReply.recentMs, 10 * min)
        let done = Agent(agent: "claude", places: [], result: Result(topic: nil, outcome: "done", at: now - 9 * min))
        XCTAssertEqual(sign([done]), "claude: done!")
        var failed = done
        failed.result = Result(topic: nil, outcome: "failed", at: now - 2 * min)
        XCTAssertEqual(sign([done, failed]), "claude: failed :(", "the latest")
        var old = done
        old.result?.at = now - 10 * min
        XCTAssertEqual(sign([old]), "all quiet", "ten minutes on, it's no news")
        XCTAssertEqual(sign([]), "all quiet")
    }

    /// Say an agent or a place and only those sessions count, the places
    /// matched as you'd say them; an agent that isn't there says so; and
    /// every sign fits `Signs.maxLength`.
    func testNamingAnAgentOrAPlace() {
        let now: Int64 = 100 * min
        let claude = Agent(agent: "claude", places: ["landing-page"], workingSince: now - 4 * min)
        let codex = Agent(agent: "codex", places: ["api", "fix-nav"], result: Result(topic: nil, outcome: "done", at: now - min))
        func sign(_ words: String) -> String { StatusReply.sign([claude, codex], words: words, at: now) }
        XCTAssertEqual(sign("is codex done?"), "codex: done!")
        XCTAssertEqual(sign("Is Claude done yet?"), "claude: 4 min in")
        XCTAssertEqual(sign("how's the api going"), "codex: done!")
        XCTAssertEqual(sign("how's the landing page coming along"), "claude: 4 min in", "its words in a row")
        XCTAssertEqual(sign("is landingpage done"), "claude: 4 min in", "run together")
        XCTAssertEqual(sign("is fix nav done"), "codex: done!")
        XCTAssertEqual(sign("how's it going"), "claude: 4 min in", "nothing named: all of them")
        XCTAssertEqual(StatusReply.sign([claude], words: "what about codex?", at: now), "no codex around")
        XCTAssertEqual(StatusReply.sign([Agent(agent: "codex", places: ["api"])], words: "is codex busy?", at: now), "codex: resting")
        XCTAssertEqual(StatusReply.shortestPlace, 3)
        XCTAssertFalse(StatusReply.mentions(StatusReply.tokens("a b c"), "ab"), "too short to match")
        XCTAssertFalse(StatusReply.mentions(StatusReply.tokens("rapid"), "api"), "a word, not part of one")
        let long = Agent(agent: "claude", places: [], workingSince: now, result: Result(topic: "deploy", outcome: "passed", at: now))
        XCTAssertLessThanOrEqual(StatusReply.sign([long], words: "", at: now).count, Signs.maxLength)
        XCTAssertEqual(StatusReply.sign([long], words: "", at: now), "deploy passed", "the agent left off when it won't fit")
    }

    /// The transcript keeps each session's latest check or finished turn,
    /// and the core hands status its sessions: what a status reply reads
    /// in the app.
    func testTheCoreAndTheTranscriptKnowTheFacts() throws {
        let rig = CoreRig()
        func status() -> [Agent] {
            rig.core.status(at: rig.now, results: rig.view.results(rig.pipeline.transcript.view(now: rig.now)))
        }
        rig.send(.turnStart, .claude, session: "s1", workspace: "fix-nav", prompt: "fix it")
        rig.wait(4 * min)
        var s = try XCTUnwrap(status().first)
        XCTAssertEqual(s.agent, "claude")
        XCTAssertEqual(Set(s.places), ["landing", "fix-nav"])
        XCTAssertEqual(StatusReply.sign([s], words: "", at: rig.now), "claude: 4 min in")
        rig.send(.activity, .claude, session: "s1", workspace: "fix-nav", tool: "Bash", topic: "tests", id: "t1")
        rig.send(.activity, .claude, session: "s1", workspace: "fix-nav", tool: "Bash", topic: "tests", failed: true, id: "t1", done: true,
                 error: "exit_code")
        s = try XCTUnwrap(status().first)
        XCTAssertEqual(s.result?.topic, "tests")
        XCTAssertEqual(s.result?.outcome, "failed")
        rig.send(.turnEnd, .claude, session: "s1", workspace: "fix-nav", message: "Done.")
        s = try XCTUnwrap(status().first)
        XCTAssertNil(s.workingSince)
        XCTAssertEqual(s.result, Result(topic: nil, outcome: "failed", at: rig.now), "a turn whose last check failed failed")
    }
}
