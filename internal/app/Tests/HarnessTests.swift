import Foundation
import MellowHarness
import LinkKit
import XCTest
@testable import BoopKit

/// Boop's outputs on MellowHarness: react and mood,
/// their questions and how they read answers; and debug mode's printer.
/// MellowHarness itself, Jev's wire format included,
/// has its own tests (mellowharness/Tests).
final class HarnessTests: XCTestCase {

    /// An empty log's view, for outputs that don't look back.
    static let log = Transcript.log().view(now: 0)

    /// A pass held back when its event's turn came says why, and asked
    /// no brain.
    func testThePrinterSaysWhyAPassWasHeld() {
        let line = #"{"pass":{"answers":{},"brain":"jev:jev-latest","dropped":null,"for":3,"held":"something needs you","latency_ms":0},"received_at_ms":7}"#
        XCTAssertEqual(DebugLog.Printer().readable(line), "  pass jev:jev-latest 0 ms: held: something needs you")
    }

    /// Seven questions, their keys unique across Boop's
    /// outputs, as MellowHarness needs.
    func testQuestionKeysMustBeUniqueAcrossActions() {
        let pipeline = Pipeline(core: Core(config: .init()), view: TranscriptView())
        let (harness, _) = Runtime.harness(pipeline: pipeline, steering: RuntimeTests.steering,
                                           queue: { _, _ in })
        let keys = harness.outputs.flatMap { $0.questions(now: nil, log: Self.log).map(\.key) }
        XCTAssertEqual(keys, askedKeys)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    /// Only the personality says who the buddy is: MOOD follows
    /// PERSONALITY in the state, and a pack's leftover `nature/` file adds
    /// nothing.
    func testOnlyThePersonalitySaysWhoItIs() throws {
        let steering = RuntimeTests.steering
        func prompt(_ steering: Steering) throws -> String {
            let pipeline = Pipeline(core: Core(config: .init()), view: TranscriptView())
            let (harness, _) = Runtime.harness(pipeline: pipeline, steering: steering,
                                               queue: { _, _ in })
            return harness.prompt(for: try XCTUnwrap(pipeline.poke(at: 1000).recorded.first))
        }
        let whole = try prompt(steering)
        XCTAssertTrue(whole.contains(steering.personality.text + "\n\n" + steering.mood(MoodOutput.initial)), whole)
        var files = steering.files
        files["nature/sweet"] = "At heart it is sweet."
        let stray = try prompt(Steering(files: files, frontMatter: steering.frontMatter))
        XCTAssertEqual(stray, whole, "a nature file adds nothing")
    }

    /// The printer reads view events, passes and actions, a started action
    /// with `…` and an end by its action's name, and skips the other raw
    /// events and the dashboard's lines.
    func testThePrinterSkipsTheDashboardsLines() {
        let printer = DebugLog.Printer()
        let stateJSON = #"You are.\nPERSONALITY\nx\n\nHISTORY (oldest first)\nh\n\nNOW (14:23, Tuesday)\nn"#
        let lines: [(String, String?)] = [
            (#"{"view":{"facts":{},"from":[3],"id":1,"line":"claude finished turn 1.","notes":["Its words: \"ok\"."],"phase":"end","type":"turn","wakes_brain":true},"received_at_ms":5}"#,
             "▸ 1 turn end: claude finished turn 1.\n    Its words: \"ok\"."),
            (#"{"view":{"facts":{},"from":[4],"id":2,"line":"claude needs you.","notes":[],"phase":"wait","type":"tool","wakes_brain":false},"received_at_ms":6}"#,
             "▸ 2 tool wait (no pass): claude needs you."),
            (#"{"event":{"seq":4,"at":6,"source":"claude","kind":"turn_end","data":{"session":"s","specific_type":"Stop"}},"received_at_ms":6}"#, nil),
            (#"{"pass":{"answers":{"mood":{"choice":"cheerful","p":{"cheerful":0.9,"grumpy":0.1}},"react":{"choice":"excited","p":{"excited":1}}},"brain":"scripted","dropped":null,"for":3,"latency_ms":12,"questions":["mood","react"],"state":""# + stateJSON + #""},"received_at_ms":7}"#,
             "  pass scripted 12 ms: mood cheerful 0.90 · react excited 1.00\n    │ You are.\n    │ PERSONALITY\n    │ x\n    │ \n    │ HISTORY (oldest first)\n    │ h\n    │ \n    │ NOW (14:23, Tuesday)\n    │ n"),
            (#"{"pass":{"answers":{},"brain":"jev:jev-latest","dropped":"late: no answer within 1500 ms","for":3,"latency_ms":1500,"questions":["mood"],"state":""# + stateJSON + #""},"received_at_ms":8}"#,
             "  pass jev:jev-latest 1500 ms: dropped: late: no answer within 1500 ms\n    │ HISTORY (oldest first)\n    │ h\n    │ \n    │ NOW (14:23, Tuesday)\n    │ n"),
            (#"{"event":{"seq":7,"at":9,"source":"self","kind":"did","data":{"action":"react","by":"brain","for":3,"message":"Boop had an excited moment, held once, and said \"Go\".","ok":true}},"received_at_ms":9}"#,
             "  ✓ react: Boop had an excited moment, held once, and said \"Go\"."),
            (#"{"event":{"seq":8,"at":9,"source":"self","kind":"did","data":{"action":"mood","by":"brain","for":3,"message":"changed 3 min ago","ok":false}},"received_at_ms":9}"#,
             "  ✗ mood: changed 3 min ago"),
            (#"{"event":{"seq":9,"at":9,"source":"self","kind":"did","data":{"action":"wiggle","by":"rule","for":4,"message":"Boop wiggled on its own.","ok":true}},"received_at_ms":9}"#,
             "  ✓ wiggle (rule): Boop wiggled on its own."),
            ("not json", "not json"),
            (#"{"sent":{"t":"do","id":1,"name":"starting","play":"if_free"},"by":"rule","received_at_ms":9}"#, nil),
            (DebugLog.ended(Ended(id: 1, how: .skipped, why: "busy"), at: 9), nil),
            (#"{"status":{"brain":"none","connected":false,"mood":"cheerful","personality":"boop","sessions":[]},"received_at_ms":9}"#, nil),
            (#"{"questions":[],"received_at_ms":9}"#, nil),
            (#"{"pass":{"answers":{"react":{"choice":"grumpy","p":{"grumpy":1}}},"by":"dashboard","dropped":null,"for":null,"latency_ms":0,"questions":["react"]},"received_at_ms":10}"#,
             "  pass dashboard 0 ms: react grumpy 1.00"),
            (#"{"event":{"seq":10,"at":11,"source":"self","kind":"did","data":{"action":"react","by":"brain","for":3,"message":"Boop had an excited moment, held once, and said \"Go\".","ok":true,"open":true}},"received_at_ms":11}"#,
             "  … react: Boop had an excited moment, held once, and said \"Go\"."),
            (#"{"event":{"seq":11,"at":12,"source":"self","kind":"ended","data":{"action":"react","by":"brain","for":10,"outcome":"done"}},"received_at_ms":12}"#,
             "  ✓ react (10) done"),
            (#"{"event":{"seq":12,"at":13,"source":"self","kind":"ended","data":{"action":"react","by":"dashboard","for":10,"outcome":"failed","why":"waited too long"}},"received_at_ms":13}"#,
             "  ✗ react (10) didn't happen: waited too long"),
            (#"{"event":{"seq":13,"at":14,"source":"boop","kind":"needs_you_end","data":{"by":"rule","outcome":"done","session":"s","specific_type":"needs_you"}},"received_at_ms":14}"#,
             "  · needs_you (rule) ended"),
        ]
        for (line, readable) in lines { XCTAssertEqual(printer.readable(line), readable, line) }
        // How the device said each `do` ended, for the dashboard.
        XCTAssertEqual(DebugLog.ended(Ended(id: 1, how: .skipped, why: "busy"), at: 9),
                       #"{"ended":{"how":"skipped","id":1,"why":"busy"},"received_at_ms":9}"#)
        XCTAssertEqual(DebugLog.ended(Ended(id: 2, how: .done), at: 10), #"{"ended":{"how":"done","id":2},"received_at_ms":10}"#)
    }

    /// A pass line carries HISTORY and NOW, and a `head` line before
    /// it the rest whenever that changes; the printer shows the first pass
    /// whole, as it did the older logs' passes, which carry the whole
    /// state (`testThePrinterSkipsTheDashboardsLines`).
    func testThePrinterJoinsTheHeadToTheFirstPass() {
        let printer = DebugLog.Printer()
        let pass = #"{"pass":{"answers":{},"brain":"scripted","dropped":null,"for":3,"latency_ms":1,"questions":[],"state":"HISTORY (oldest first)\nh\n\nNOW (14:23, Tuesday)\nn"},"received_at_ms":7}"#
        XCTAssertNil(printer.readable(DebugLog.head("You are.\nMOOD\ncalm\n\n", at: 6)))
        XCTAssertEqual(printer.readable(pass), "  pass scripted 1 ms: \n    │ You are.\n    │ MOOD\n    │ calm\n    │ \n    │ HISTORY (oldest first)\n    │ h\n    │ \n    │ NOW (14:23, Tuesday)\n    │ n")
        XCTAssertNil(printer.readable(DebugLog.head("You are.\nMOOD\ngrumpy\n\n", at: 8)))
        XCTAssertEqual(printer.readable(pass), "  pass scripted 1 ms: \n    │ HISTORY (oldest first)\n    │ h\n    │ \n    │ NOW (14:23, Tuesday)\n    │ n")
        XCTAssertEqual(DebugLog.split("You are.\n\nHISTORY (oldest first)\nh").head, "You are.\n\n")
        XCTAssertEqual(DebugLog.split("You are.\n\n\(ContextSection.heading)\nAgents: x.\n\nHISTORY (oldest first)\nh").head, "You are.\n\n",
                       "CONTEXT goes with the pass")
    }

    // MARK: The outputs

    func a(_ choice: String, _ p: Double = 0.9) -> Answer { Answer(choice: choice, probabilities: [choice: p]) }

    /// A finish's `turn`, which the device sizes it by: the tier the turn
    /// reached, as the tags count them, 0 short of the first (a minute),
    /// then 1 to 3 (`tier1` to `tier3`: a minute, 5 and 15).
    func testAFinishSaysHowLongItsTurnRan() {
        XCTAssertEqual(Moment.turn(lengthMs: 0), 0)
        XCTAssertEqual(Moment.turn(lengthMs: 59_999), 0)
        XCTAssertEqual(Moment.turn(lengthMs: 60_000), 1)
        XCTAssertEqual(Moment.turn(lengthMs: 5 * 60_000 - 1), 1)
        XCTAssertEqual(Moment.turn(lengthMs: 5 * 60_000), 2)
        XCTAssertEqual(Moment.turn(lengthMs: 15 * 60_000 - 1), 2)
        XCTAssertEqual(Moment.turn(lengthMs: 15 * 60_000), 3)
        XCTAssertEqual(Moment.turn(lengthMs: 60 * 60_000), 3)
        XCTAssertEqual(Moment(anim: "task_complete", outcome: "success", turn: 3, variant: 1).args.json,
                       #"{"outcome":"success","turn":3,"variant":1}"#)
    }

    /// Onboarding's finishes: the first hook's stands out, held twice; the
    /// finale's is big, held three times in a happy face, its first design.
    func testOnboardingsFinishes() {
        XCTAssertEqual(Runtime.Greeting.hello.reaction.args.json, #"{"outcome":"success","loops":2}"#)
        XCTAssertEqual(Runtime.Greeting.finale.reaction.args.json,
                       #"{"outcome":"success","variant":1,"mood":"happy","loops":3}"#)
    }

    /// `none` does nothing; the meaning counts over 0.35, and Voice says a
    /// take of it in the face's mood, else nothing; the reaction carries
    /// the expression as its `mood`, the size the rule gives NOW as its
    /// loops (small to big: 1–3), the take as big as it, and a `say`
    /// whether or not there's a take, and goes to the queue with the
    /// handle the result is started with; a blocked reaction fails, with
    /// no handle. The move is the rule's too (`MomentRule.move`), played
    /// in the face.
    func testReact() throws {
        try requireVoice()
        XCTAssertEqual(MomentOutput.sayFloor, 0.35)
        var queued: [(reaction: Moment, pending: Pending)] = []
        var sent: [Moment] { queued.map(\.reaction) }
        var why: String?
        // NOW's line's facts: a finish's, or none.
        var facts: [String: JSONValue] = [:]
        let react = MomentOutput(queue: { queued.append(($0, $1)) }, blocked: { why },
                                who: { _ in .init(agent: "codex", thread: "fix-nav") },
                                turnMs: { _ in facts["length_ms"]?.int }, line: { _ in Line("", facts: facts) })
        let poke = Event(at: 0, source: .device, type: .poke, specificType: "input")
        let said = Event(at: 0, source: .mic, type: .said, specificType: "device", data: ["words": "hi"])
        let finish = Event(at: 0, source: .claude, type: .turn, phase: .end, specificType: "Stop")
        let back = Event(at: 0, source: .mac, type: .presence, phase: .end, specificType: "unlocked")
        /// A finish's facts: how it ended, after `minutes`, with `tools` calls.
        func finished(_ outcome: String, minutes: Int64, tools: Int64 = 3, kind: String? = nil) -> [String: JSONValue] {
            var f: [String: JSONValue] = ["outcome": .string(outcome), "length_ms": .int(minutes * 60_000), "tools": .int(tools)]
            if let kind { f["message"] = .object(["kind": .string(kind)]) }
            return f
        }
        /// Runs `answers` at `now`, and checks the result is started with
        /// `message` and the handle its reaction was queued with.
        func starts(_ answers: Answers, at now: Event, _ message: String, line: UInt = #line) {
            let before = queued.count
            let result = react.run(answers, now: now, log: Self.log)
            XCTAssertEqual(queued.count, before + 1, "one reaction queued", line: line)
            // `SAID` stands for the line the take picked at random says.
            // The start carries the takes' ids.
            let said = queued.last?.reaction.say?.text ?? "?"
            var expected: [String: JSONValue] = ["takes": .array((queued.last?.reaction.say?.takes ?? []).map { .string($0.id) })]
            if let reply = queued.last?.reaction.reply { expected["reply"] = .string(reply) }
            XCTAssertEqual(result, queued.last.map { q in
                .started(message.replacingOccurrences(of: "SAID", with: said), q.pending, facts: expected)
            }, line: line)
        }
        XCTAssertNil(react.run(["react.face": a("none")], now: poke, log: Self.log))
        // What you said is a medium moment: a word.
        starts(["react.face": a("grumpy"), "react.reply": a("no"), "say": a("upset", 0.57)], at: said,
               #"\#(creature) had a grumpy moment (medium), replying no, and said "SAID"."#)
        // A turn of 9 minutes that failed is a big one.
        facts = finished("failed", minutes: 9)
        starts(["react.face": a("sad"), "say": a("glad", 0.31)], at: finish, "\(creature) had a sad moment (big), playing a failure.")
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(Set(queued.map { ObjectIdentifier($0.pending) }).count, 2, "a handle each")
        let grumbled = try XCTUnwrap(sent[0].say?.takes)
        XCTAssertEqual(grumbled.last?.kind, .word, "as big as the moment: medium is a word")
        XCTAssertTrue(grumbled.allSatisfy { $0.moods.contains("grumpy") }, "in the face's mood")
        XCTAssertNotNil(sent[1].say, "a reaction that says nothing still has a say")
        XCTAssertEqual(sent[1].say?.takes, [], "below the floor, Jev is guessing: nothing")
        XCTAssertEqual(sent.map(\.mood), ["grumpy", "sad"], "each wears its face")
        XCTAssertEqual(sent.map(\.loops), [2, 3], "held as long as the moment is big")
        let failure = sent[1]
        XCTAssertEqual([failure.anim, failure.outcome], ["task_complete", "failure"])
        XCTAssertEqual(failure.who, .init(agent: "codex", thread: "fix-nav"))
        XCTAssertEqual(failure.turn, 2, "a finish says how long its turn ran: 9 minutes is tier2")
        XCTAssertEqual(react.run(["react.face": a("sulky")], now: poke, log: Self.log), nil, "not a face")
        // The moves, each a scene: a success or a failure is the face's
        // task_complete for that outcome, a reply its reply_ready, a wake
        // up its wake_up, a notice its notice, naming the thread NOW is
        // about; the device picks the variation.
        XCTAssertEqual(MomentOutput.moves, ["success", "failure", "reply", "wake up", "notice"])
        XCTAssertEqual(Set(MomentOutput.scenes.keys), Set(MomentOutput.moves), "each plays a scene")
        queued.removeAll()
        facts = finished("done", minutes: 9)
        starts(["react.face": a("proud"), "say": a("glad")], at: finish,
               #"\#(creature) had a proud moment (big), playing a success, and said "SAID"."#)
        XCTAssertEqual(queued.last?.reaction.say?.takes.first?.kind, .phrase, "a proud phrase, at a big success")
        let success = try XCTUnwrap(queued.last?.reaction)
        XCTAssertEqual(MomentOutput.move(of: success), "success")
        let line = success.line(id: 7, play: .next)
        XCTAssertTrue(line.hasPrefix(#"{"t":"do","id":7,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success","turn":2,"who":{"agent":"codex","thread":"fix-nav"},"say":"#), line)
        XCTAssertTrue(line.hasSuffix(#","mood":"proud","loops":3}}"#), line)
        // Saying nothing is `say`'s none: the face, and a finish, play in silence.
        facts = finished("done", minutes: 0)
        starts(["react.face": a("pleased"), "say": a("none")], at: finish, "\(creature) had a pleased moment (small), playing a success.")
        XCTAssertEqual(sent.last?.say?.takes, [], "a face in silence")
        facts = finished("done", minutes: 2, tools: 0, kind: "answer")
        starts(["react.face": a("curious"), "say": a("none")], at: finish, "\(creature) had a curious moment (small), playing a reply.")
        let reply = try XCTUnwrap(queued.last?.reaction)
        XCTAssertEqual(reply.anim, "reply_ready")
        XCTAssertNil(reply.outcome, "a reply has no outcome")
        XCTAssertNil(reply.turn, "nor a turn to size it by")
        XCTAssertEqual(reply.who, .init(agent: "codex", thread: "fix-nav"))
        facts = ["away_ms": .int(2 * 60 * 60_000)]
        starts(["react.face": a("happy"), "say": a("hello")], at: back,
               #"\#(creature) had a happy moment (medium), playing a wake up, and said "SAID"."#)
        let woke = try XCTUnwrap(queued.last?.reaction)
        XCTAssertEqual(woke.anim, "wake_up")
        XCTAssertNil(woke.outcome, "a wake-up has no outcome")
        // A face with no move names whose turn it was when NOW finished
        // one, and only then: the device marks the turn it's about.
        facts = finished("stopped", minutes: 9)
        starts(["react.face": a("happy")], at: finish, "\(creature) had a happy moment (small).")
        XCTAssertNil(queued.last?.reaction.anim)
        XCTAssertEqual(queued.last?.reaction.who, .init(agent: "codex", thread: "fix-nav"), "a face for a finished turn names it")
        XCTAssertNil(queued.last?.reaction.outcome, "with no outcome of its own")
        facts = [:]
        starts(["react.face": a("happy")], at: poke, "\(creature) had a happy moment (small).")
        XCTAssertNil(queued.last?.reaction.who, "a face for anything else names no turn")
        queued.removeAll()
        why = "something needs you"
        for expression in CharacterPack.active.faces.map(\.name) {
            XCTAssertEqual(react.run(["react.face": a(expression)], now: poke, log: Self.log), .failed("something needs you"))
        }
        XCTAssertEqual(sent.count, 0, "no face or take while something needs you")
        why = nil
        // A success take only on a success, a swear only on a failure: a
        // grumpy swear at a check failing mid-turn is a phrase, and at a
        // failed turn a swear, however small the moment.
        starts(["react.face": a("grumpy"), "say": a("swear")], at: poke,
               #"\#(creature) had a grumpy moment (small), and said "SAID"."#)
        XCTAssertEqual(queued.last?.reaction.say?.takes.first?.kind, .phrase)
        facts = finished("failed", minutes: 0)
        let swore = react.run(["react.face": a("grumpy"), "say": a("swear")], now: finish, log: Self.log)
        XCTAssertEqual(queued.last?.reaction.say?.takes.last?.kind, .swear, "\(String(describing: swore))")
        queued.removeAll()
        // The two questions, the same at every event; what you said adds its reply.
        XCTAssertEqual(react.questions(now: poke, log: Self.log).map(\.key), ["react.face", "say"])
        XCTAssertEqual(react.questions(now: said, log: Self.log).map(\.key), ["react.face", "react.reply", "say"])
        XCTAssertEqual(react.questions(now: poke, log: Self.log)[0].options.map(\.name), ["none"] + CharacterPack.active.moods.map(\.id),
                       "the faces are every mood's")
        XCTAssertEqual(react.questions(now: poke, log: Self.log)[1].options.map(\.name),
                       ["none", "swear", "upset", "glad", "tickled", "shaken"] + MomentOutput.topics.map(\.name))
        XCTAssertEqual(react.questions(now: poke, log: Self.log)[1].options.count, 12, "none, 4 feelings, a swear and the 6 topics")
        XCTAssertEqual(MomentOutput.topics.map(\.name), ["retry", "work", "tests", "done", "quiet", "hello"])
        XCTAssertEqual(MomentOutput.replies.map(\.name), ["yes", "no", "huh", "hello", "bye", "thanks", "ouch", "comfort", "hehe", "status", "hush"])
        XCTAssertLessThanOrEqual(MomentOutput.sizes.map(\.loops).max() ?? 0, Moment.maxLoops, "the device plays them all")
        XCTAssertEqual(Set(MomentOutput.feelings.map(\.name)), Voice.answers(.feeling), "a feeling for every take's, and none without one")
        // A pack's say offers only the feelings its voice has: Pixel's
        // older copy of the voice has no shaken takes.
        if let pixel = try? CharacterPack.named(id: "pixel") {
            XCTAssertEqual(MomentOutput.feelings(in: pixel).map(\.name), ["upset", "glad", "tickled"])
        }
        XCTAssertEqual(Set(MomentOutput.topics.map(\.name)), Voice.answers(.about), "a topic for every take's, and none without one")
    }

    /// Only the brain's reactions carry an expression; a
    /// rule's reaction never does.
    func testRuleReactionsCarryNoExpression() throws {
        try requireVoice()
        XCTAssertEqual(Moment(anim: Core.wishGone).line(id: 1, play: .ifFree), #"{"t":"do","id":1,"name":"wish_gone","play":"if_free"}"#)
        XCTAssertEqual(Moment(say: .go).line(id: 2, play: .next),
                       #"{"t":"do","id":2,"name":"react","play":"next","ttl":5000,"args":{"say":{"take":"new.d02"}}}"#)
        XCTAssertEqual(Moment(say: .go, mood: "grumpy").args.json, #"{"say":{"take":"new.d02"},"mood":"grumpy"}"#)
    }

    /// The pack's moods, in its order; a new Boop starts calm, the resting
    /// mood; the `mood` question offers, on every pass, staying in the
    /// mood the log has and every other lasting mood, each with its
    /// meaning: there's no graph. Staying is nothing to do, and so is an
    /// answer that isn't a mood; any other is a change in the log, which is
    /// the mood from then on, and MOOD with it, however recently it last
    /// changed. It's MellowHarness's `Choice`.
    func testMood() throws {
        XCTAssertEqual(MoodOutput.moods.map(\.name), CharacterPack.active.lasting.map(\.id), "the lasting moods only")
        XCTAssertEqual(MoodOutput.initial, "calm")
        let log = Transcript.log()
        let mood = MoodOutput.choice()
        func view() -> LogView { log.view(now: 1) }
        func run(_ answers: Answers) -> OutputResult? {
            let result = mood.run(answers, now: nil, log: view())
            if let result { log.append(Event.did(result.message, for: nil, action: mood.name, by: "brain", facts: result.facts), now: 1) }
            return result
        }
        XCTAssertEqual(MoodOutput.value(mood, view()), "calm", "a new Boop starts calm")
        func offered() -> [String] { mood.questions(now: nil, log: view())[0].options.map(\.name) }
        XCTAssertEqual(mood.questions(now: nil, log: view()).map(\.key), ["mood"])
        let all = MoodOutput.moods.map(\.name)
        XCTAssertEqual(offered(), ["calm"] + all.filter { $0 != "calm" }, "staying, then every other mood")
        for m in all {
            let options = MoodOutput.options(from: m)
            XCTAssertEqual(options.map(\.name), [m] + all.filter { $0 != m }, m)
            XCTAssertNil(options[0].notFor, "staying has no clock: fading is code's")
            for o in options.dropFirst() {
                let meaning = MoodOutput.moods.first { $0.name == o.name }!
                XCTAssertEqual(o.what, meaning.what, "\(m) → \(o.name) carries its meaning")
                XCTAssertEqual(o.notFor, meaning.notFor)
            }
            XCTAssertFalse(MoodOutput.options(from: m, mayMiss: false).dropFirst().contains { $0.name == MoodOutput.missing },
                           "\(m): missing you is offered only when it may begin")
        }
        XCTAssertEqual(MoodOutput.options(from: "lonely", mayMiss: false).first?.name, "lonely", "but staying in it always is")

        XCTAssertNil(run(["mood": a("calm")]), "staying is nothing to do")
        XCTAssertNil(run(["mood": a("grumpy")]), "a face, not a mood")
        XCTAssertNil(run(["mood": a("sulky")]), "not a mood")
        XCTAssertNil(run([:]), "no answer")
        XCTAssertEqual(MoodOutput.value(mood, view()), "calm")
        XCTAssertEqual(run(["mood": a("cross")]),
                       .done("\(creature)'s mood changed: calm → cross.", facts: ["from": "calm", "to": "cross"]))
        XCTAssertEqual(offered().first, "cross", "the next pass is offered staying cross first")
        XCTAssertEqual(run(["mood": a("happy")])?.message, "\(creature)'s mood changed: cross → happy.", "straight after, any mood: a strong feeling flips it")
        XCTAssertEqual(MoodOutput.value(mood, view()), "happy", "the latest change in the log")
        XCTAssertEqual(MoodOutput.value(MoodOutput.choice(), view()), "happy", "so it survives a restart")
        log.append(Event.did("\(creature)'s mood changed: happy → delighted.", for: nil, action: mood.name, by: "brain",
                             facts: ["from": "happy", "to": "delighted"]), now: 1)
        XCTAssertEqual(MoodOutput.value(mood, view()), "calm", "one that isn't a mood reads as calm")
        log.append(Event.did("\(creature)'s mood changed: happy → grumpy.", for: nil, action: mood.name, by: "brain",
                             facts: ["from": "happy", "to": "grumpy"]), now: 1)
        XCTAssertEqual(MoodOutput.value(mood, view()), "cross", "a face's name reads as the mood it settles into")
    }

    /// Missing you may begin only with no agent working: at an idle
    /// check-in once the wish has waited an hour, or at your coming back
    /// after 20 to 40 hours. A forced pass is offered none: a mood is set
    /// itself there.
    func testMissingYouMayBeginOnlyWhenItsGateAllows() {
        let checkIn = Event(at: 0, source: .clock, type: .checkIn, specificType: "check_in")
        let back = Event(at: 0, source: .mac, type: .presence, phase: .end, specificType: "active")
        let hour: Int64 = 3_600_000
        XCTAssertEqual(MoodOutput.missAfterWishMs, hour, "the wish's hour")
        XCTAssertEqual(MoodOutput.missAwayMs, (20 * hour)...(40 * hour), "back after 20 to 40 hours")
        XCTAssertFalse(MoodOutput.mayMiss(nil, facts: nil, working: false, wishWaitedMs: 2 * hour), "a forced pass")
        XCTAssertTrue(MoodOutput.mayMiss(checkIn, facts: nil, working: false, wishWaitedMs: hour))
        XCTAssertFalse(MoodOutput.mayMiss(checkIn, facts: nil, working: false, wishWaitedMs: hour - 1), "40 min is too soon")
        XCTAssertFalse(MoodOutput.mayMiss(checkIn, facts: nil, working: false, wishWaitedMs: nil), "no wish")
        XCTAssertFalse(MoodOutput.mayMiss(checkIn, facts: nil, working: true, wishWaitedMs: 2 * hour), "an agent working is company")
        XCTAssertTrue(MoodOutput.mayMiss(back, facts: ["away_ms": .int(26 * hour)], working: false, wishWaitedMs: nil))
        XCTAssertFalse(MoodOutput.mayMiss(back, facts: ["away_ms": .int(3 * hour)], working: false, wishWaitedMs: nil), "a short break")
        XCTAssertFalse(MoodOutput.mayMiss(back, facts: ["away_ms": .int(72 * hour)], working: false, wishWaitedMs: nil), "after days it's glad")
        let poke = Event(at: 0, source: .device, type: .poke, specificType: "input")
        XCTAssertFalse(MoodOutput.mayMiss(poke, facts: nil, working: false, wishWaitedMs: 2 * hour), "nor at a poke")
    }

    /// The mood the dashboard sets changes as Jev's does,
    /// device included, to any of the moods; and it's
    /// told why when it can't: the mood it already is, or one that isn't a
    /// mood.
    func testAForcedMoodChangesItAsJevsDoes() throws {
        let pipeline = Pipeline(core: Core(config: .init()), view: TranscriptView())
        let (harness, mood) = Runtime.harness(pipeline: pipeline, steering: RuntimeTests.steering,
                                              queue: { _, _ in })
        var told: [String] = []
        harness.on(Event.did) { e in if e.action == MoodOutput.outputName, e["ok"]?.bool == true { told.append(e["to"]!.string!) } }
        func change(_ to: String) -> OutputResult? {
            harness.force(mood, by: Runtime.forcedBy) { MoodOutput.change(mood, to: to, log: harness.log.view(now: 1)) }
        }
        XCTAssertEqual(change("cross")?.message, "\(creature)'s mood changed: calm → cross.")
        XCTAssertEqual(change("cross"), .failed("already cross"))
        XCTAssertEqual(change("sulky"), .failed("sulky isn't a mood"))
        XCTAssertEqual(MoodOutput.value(mood, harness.log.view(now: 1)), "cross")
        XCTAssertEqual(harness.force(["mood": "proud"], by: Runtime.forcedBy).map(\.result.message),
                       ["\(creature)'s mood changed: cross → proud."], "Jev's, right after")
        XCTAssertEqual(told, ["cross", "proud"], "the device hears each change")
        XCTAssertEqual(change("wounded")?.message, "\(creature)'s mood changed: proud → sad.", "a face's name sets the mood it settles into")
    }

    /// Each mood's file opens with its name and says what moves it, and
    /// none gives minutes: the app fades a mood by its clock.
    func testEachMoodFileOpensWithItsNameAndGivesNoMinutes() throws {
        for mood in MoodOutput.moods.map(\.name) {
            let text = RuntimeTests.steering.mood(mood)
            let opening = "MOOD\n\(mood.prefix(1).uppercased())\(mood.dropFirst())"
            XCTAssertTrue(text.hasPrefix(opening + ".") || text.hasPrefix(opening + " is "), "\(mood) opens with its name")
            XCTAssertNil(text.range(of: #"\d+ min"#, options: .regularExpression), "\(mood) gives no minutes")
            XCTAssertFalse(text.contains("Fades to"), "\(mood): fading is code's")
        }
    }

    // MARK: Jev

    /// Jev out of reach, as `JevBrain` says it (MellowHarness's
    /// own tests pin that), counts toward the brain failing.
    func testJevOutOfReachCountsTowardFailing() {
        XCTAssertEqual(BrainTrouble.after(BrainError("jev: can't reach the server"), previous: 2).trouble?.kind, .failing)
    }
}
