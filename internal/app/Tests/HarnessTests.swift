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
        let (harness, _) = Runtime.harness(pipeline: pipeline, steering: RuntimeTests.steering, personality: { .default },
                                           queue: { _, _ in })
        let keys = harness.outputs.flatMap { $0.questions(now: nil, log: Self.log).map(\.key) }
        XCTAssertEqual(keys, askedKeys)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    /// The nature chosen at setup steers the brain: the pack's
    /// `steering/nature/<nature>.md` follows PERSONALITY in the state, and
    /// a pack with no file for it, or no nature, adds nothing.
    func testTheNatureFollowsThePersonality() throws {
        let steering = RuntimeTests.steering
        func prompt(_ nature: LongTerm.Nature?, _ steering: Steering) throws -> String {
            let pipeline = Pipeline(core: Core(config: .init()), view: TranscriptView())
            let (harness, _) = Runtime.harness(pipeline: pipeline, steering: steering, personality: { .default },
                                               queue: { _, _ in }, nature: nature)
            return harness.prompt(for: try XCTUnwrap(pipeline.poke(at: 1000).recorded.first))
        }
        let personality = steering.personality(.default).text
        for nature in [LongTerm.Nature.sweet, .cheeky] {
            let text = try XCTUnwrap(steering.nature(nature), "every pack here has both")
            let whole = try prompt(nature, steering)
            XCTAssertTrue(whole.contains(personality + "\n\n" + text + "\n\n"), nature.rawValue)
            XCTAssertFalse(text.contains("<!--"), "comments are left out")
        }
        let none = try prompt(nil, steering)
        XCTAssertTrue(none.contains(personality + "\n\n"))
        let bare = Steering(files: steering.files.filter { !$0.key.hasPrefix("nature/") }, frontMatter: steering.frontMatter)
        let missing = try prompt(.cheeky, bare)
        XCTAssertEqual(missing, none, "a missing file adds nothing")
        XCTAssertEqual(steering.overBudget().filter { $0.hasPrefix("nature/") }, [], "within \(Steering.Budget.nature) tokens")
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
            (#"{"event":{"seq":7,"at":9,"source":"self","kind":"did","data":{"action":"react","by":"brain","for":3,"message":"Boop made an excited face, held once, and said \"Go\".","ok":true}},"received_at_ms":9}"#,
             "  ✓ react: Boop made an excited face, held once, and said \"Go\"."),
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
            (#"{"event":{"seq":10,"at":11,"source":"self","kind":"did","data":{"action":"react","by":"brain","for":3,"message":"Boop made an excited face, held once, and said \"Go\".","ok":true,"open":true}},"received_at_ms":11}"#,
             "  … react: Boop made an excited face, held once, and said \"Go\"."),
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
    }

    // MARK: The outputs

    func a(_ choice: String, _ p: Double = 0.9) -> Answer { Answer(choice: choice, probabilities: [choice: p]) }

    /// `none` does nothing; the meaning counts over 0.35,
    /// and Voice says a take of it in the face's mood, else nothing; the
    /// reaction carries the expression as its `mood`, `react.loops`' pick as
    /// its loops (once to four times: 1–4, and once when it's missing) and
    /// a `say` whether or not there's a take, and goes to the queue with
    /// the handle the result is started with; a blocked reaction fails,
    /// with no handle.
    /// A finish's `turn`, which the device sizes it by: the tier the turn
    /// reached, as the tags count them, 0 short of the first (30 s), then 1
    /// to 5 (`tier1` to `tier5`: 30 s, a minute, 2, 5 and 10). The gel's
    /// finish is at most medium below 2, at least big from 4 and biggest
    /// at 5.
    func testAFinishSaysHowLongItsTurnRan() {
        XCTAssertEqual(DeviceReaction.turn(lengthMs: 0), 0)
        XCTAssertEqual(DeviceReaction.turn(lengthMs: 29_999), 0)
        XCTAssertEqual(DeviceReaction.turn(lengthMs: 30_000), 1)
        XCTAssertEqual(DeviceReaction.turn(lengthMs: 59_999), 1)
        XCTAssertEqual(DeviceReaction.turn(lengthMs: 60_000), 2)
        XCTAssertEqual(DeviceReaction.turn(lengthMs: 2 * 60_000), 3)
        XCTAssertEqual(DeviceReaction.turn(lengthMs: 5 * 60_000 - 1), 3)
        XCTAssertEqual(DeviceReaction.turn(lengthMs: 5 * 60_000), 4)
        XCTAssertEqual(DeviceReaction.turn(lengthMs: 10 * 60_000), 5)
        XCTAssertEqual(DeviceReaction.turn(lengthMs: 60 * 60_000), 5)
        XCTAssertEqual(DeviceReaction(anim: "task_complete", outcome: "success", turn: 5, variant: 1).args.json,
                       #"{"outcome":"success","turn":5,"variant":1}"#)
    }

    /// Onboarding's finishes: the first hook's stands out, held twice; the
    /// finale's is big, held three times in a happy face, its first design.
    func testOnboardingsFinishes() {
        XCTAssertEqual(Runtime.Greeting.hello.reaction.args.json, #"{"outcome":"success","loops":2}"#)
        XCTAssertEqual(Runtime.Greeting.finale.reaction.args.json,
                       #"{"outcome":"success","variant":1,"mood":"happy","loops":3}"#)
    }

    func testReact() throws {
        try requireVoice()
        XCTAssertEqual(ReactOutput.sayFloor, 0.35)
        var queued: [(reaction: DeviceReaction, pending: Pending)] = []
        var sent: [DeviceReaction] { queued.map(\.reaction) }
        var why: String?
        // NOW finished a turn of 9 minutes, or (nil) none.
        var turnMs: Int64? = 9 * 60_000
        let react = ReactOutput(queue: { queued.append(($0, $1)) }, blocked: { why },
                                who: { _ in .init(agent: "codex", thread: "fix-nav") }, turnMs: { _ in turnMs })
        /// Runs `answers`, and checks the result is started with `message`
        /// and the handle its reaction was queued with.
        func starts(_ answers: Answers, _ message: String, line: UInt = #line) {
            let before = queued.count
            let result = react.run(answers, now: nil, log: Self.log)
            XCTAssertEqual(queued.count, before + 1, "one reaction queued", line: line)
            // `SAID` stands for the line the take picked at random says.
            // The start carries the takes' ids.
            let said = queued.last?.reaction.say?.text ?? "?"
            XCTAssertEqual(result, queued.last.map { q in
                .started(message.replacingOccurrences(of: "SAID", with: said), q.pending,
                         facts: ["takes": .array((q.reaction.say?.takes ?? []).map { .string($0.id) })])
            }, line: line)
        }
        XCTAssertNil(react.run(["react.mood": a("none")], now: nil, log: Self.log))
        starts(["react.mood": a("grumpy"), "say.feeling": a("upset", 0.57), "say.about": a("tests", 0.8), "say.kind": a("sound"),
                "react.loops": a("twice")],
               #"\#(creature) made a grumpy face, held twice, and said "SAID"."#)
        starts(["react.mood": a("proud"), "say.feeling": a("glad", 0.31), "say.about": a("none"), "say.kind": a("phrase")],
               "\(creature) made a proud face, held once.")
        starts(["react.mood": a("happy"), "say.feeling": a("none"), "react.loops": a("four times")],
               "\(creature) made a happy face, held four times.")
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(Set(queued.map { ObjectIdentifier($0.pending) }).count, 3, "a handle each")
        let grumbled = try! XCTUnwrap(sent[0].say?.takes)
        XCTAssertEqual(grumbled.first?.part, .feeling, "the feeling first")
        XCTAssertEqual(grumbled.first?.meaning, "upset")
        XCTAssertTrue(grumbled.allSatisfy { $0.moods.contains("grumpy") }, "in the face's mood")
        XCTAssertTrue(grumbled.count == 1 || grumbled[1].meaning == "tests", "then the topic")
        XCTAssertNotNil(sent[1].say, "a reaction that says nothing still has a say")
        XCTAssertEqual(sent[1].say?.takes, [], "below the floor, Jev is guessing: nothing")
        XCTAssertNil(sent[0].anim, "it plays over the face")
        XCTAssertEqual(sent.map(\.mood), ["grumpy", "proud", "happy"], "each wears its face")
        // Saying nothing is a kind: the face, and a finish, play in silence
        // however sure the feeling and the topic are.
        starts(["react.mood": a("pleased"), "say.feeling": a("glad"), "say.about": a("done"), "say.kind": a("none"),
                "react.animation": a("success")],
               "\(creature) played a success in a pleased face, held once.")
        XCTAssertEqual(sent.last?.say?.takes, [], "a face in silence")
        XCTAssertEqual(sent.last?.anim, "task_complete", "with its finish")
        queued.removeLast()
        XCTAssertEqual(sent.map(\.loops), [2, 1, 4], "for its loops")
        XCTAssertTrue(sent[0].args.json.hasSuffix(#","mood":"grumpy","loops":2}"#), sent[0].args.json)
        XCTAssertEqual(sent[0].name, "react")
        XCTAssertEqual(react.run(["react.mood": a("sulky")], now: nil, log: Self.log), nil, "not a face")
        starts(["react.mood": a("excited"), "react.loops": a("three times")], "\(creature) made an excited face, held three times.")
        XCTAssertEqual(queued.last?.reaction.loops, 3)
        queued.removeLast()
        // `react.animation` judges a turn's finish, you back after a long
        // break, or your prompt saying its name, and plays it in the face:
        // a success or a failure is the face's task_complete for that
        // outcome, a reply its reply_ready, a wake up its wake_up, a notice
        // its notice, naming the thread NOW is about; the device picks the
        // variation. `none`, a missing answer or anything else is just the
        // face. The question and its `none` name every case, so neither
        // argues against one.
        XCTAssertEqual(ReactOutput.animations.map(\.name), ["success", "failure", "reply", "wake up", "notice"])
        XCTAssertEqual(Set(ReactOutput.scenes.keys), Set(ReactOutput.animations.map(\.name)), "each plays a scene")
        let animation = try! XCTUnwrap(ReactOutput.questions().first { $0.key == "react.animation" })
        XCTAssertTrue(animation.text.contains("or your prompt saying \(creature)'s name?"), animation.text)
        XCTAssertTrue(animation.options[0].what.contains("or a prompt that says \(creature)'s name."), animation.options[0].what)
        starts(["react.mood": a("proud"), "react.animation": a("success"), "react.loops": a("twice"), "say.feeling": a("glad"),
                "say.kind": a("phrase")],
               #"\#(creature) played a success in a proud face, held twice, and said "SAID"."#)
        XCTAssertEqual(queued.last?.reaction.say?.takes.first?.kind, .phrase, "a proud phrase, at a success")
        let success = try! XCTUnwrap(queued.last?.reaction)
        XCTAssertEqual(success.anim, "task_complete")
        XCTAssertEqual(success.outcome, "success")
        let line = success.line(id: 7, play: .next)
        XCTAssertTrue(line.hasPrefix(#"{"t":"do","id":7,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success","turn":4,"who":{"agent":"codex","thread":"fix-nav"},"say":"#), line)
        XCTAssertTrue(line.hasSuffix(#","mood":"proud","loops":2}}"#), line)
        queued.removeLast()
        starts(["react.mood": a("whiny"), "react.animation": a("failure")], "\(creature) played a failure in a whiny face, held once.")
        let failure = try! XCTUnwrap(queued.last?.reaction)
        XCTAssertEqual([failure.anim, failure.outcome], ["task_complete", "failure"])
        XCTAssertEqual(failure.who, .init(agent: "codex", thread: "fix-nav"))
        XCTAssertEqual(failure.turn, 4, "a finish says how long its turn ran: 9 minutes is tier4")
        queued.removeLast()
        starts(["react.mood": a("curious"), "react.animation": a("reply"), "say.about": a("answer")],
               #"\#(creature) played a reply in a curious face, held once, and said "SAID"."#)
        XCTAssertEqual(queued.last?.reaction.say?.takes.map(\.meaning), ["answer"])
        let reply = try! XCTUnwrap(queued.last?.reaction)
        XCTAssertEqual(reply.anim, "reply_ready")
        XCTAssertNil(reply.outcome, "a reply has no outcome")
        XCTAssertNil(reply.turn, "nor a turn to size it by")
        XCTAssertEqual(reply.who, .init(agent: "codex", thread: "fix-nav"))
        queued.removeLast()
        starts(["react.mood": a("happy"), "react.animation": a("wake up"), "say.about": a("hello")],
               #"\#(creature) played a wake up in a happy face, held once, and said "SAID"."#)
        let woke = try! XCTUnwrap(queued.last?.reaction)
        XCTAssertEqual(woke.anim, "wake_up")
        XCTAssertNil(woke.outcome, "a wake-up has no outcome")
        XCTAssertEqual(woke.who, .init(agent: "codex", thread: "fix-nav"), "the thread NOW is about, which a back never is (PresenceTests)")
        queued.removeLast()
        // A face with no animation names whose turn it was when NOW
        // finished one, and only then: the device marks the turn it's about.
        for pick in ["none", "cheer", "wiggle", "confetti"] {
            starts(["react.mood": a("happy"), "react.animation": a(pick)], "\(creature) made a happy face, held once.")
            XCTAssertNil(queued.last?.reaction.anim, pick)
            XCTAssertEqual(queued.last?.reaction.who, .init(agent: "codex", thread: "fix-nav"), "a face for a finished turn names it")
            XCTAssertNil(queued.last?.reaction.outcome, "with no outcome of its own")
            queued.removeLast()
        }
        turnMs = nil
        starts(["react.mood": a("happy")], "\(creature) made a happy face, held once.")
        XCTAssertNil(queued.last?.reaction.who, "a face for anything else names no turn")
        queued.removeLast()
        turnMs = 9 * 60_000
        XCTAssertNil(react.run(["react.mood": a("proud-success")], now: nil, log: Self.log), "a face and an animation are separate questions")
        why = "something needs you"
        for expression in ReactOutput.expressions.map(\.name) {
            XCTAssertEqual(react.run(["react.mood": a(expression)], now: nil, log: Self.log), .failed("something needs you"))
        }
        XCTAssertEqual(sent.count, 3, "no face or take while something needs you")
        why = nil
        // A success take only on a success, a swear only on a
        // failure: an irritated swear asked for at a check failing
        // mid-turn is a phrase, and at a failed turn a swear.
        starts(["react.mood": a("irritated"), "say.feeling": a("upset"), "say.kind": a("swear")],
               #"\#(creature) made an irritated face, held once, and said "SAID"."#)
        XCTAssertEqual(queued.last?.reaction.say?.takes.first?.kind, .phrase)
        let swore = react.run(["react.mood": a("irritated"), "react.animation": a("failure"), "say.feeling": a("upset"),
                               "say.kind": a("swear")], now: nil, log: Self.log)
        XCTAssertEqual(queued.last?.reaction.say?.takes.first?.kind, .swear, "\(String(describing: swore))")
        starts(["react.mood": a("happy"), "say.about": a("done"), "say.kind": a("word")], "\(creature) made a happy face, held once.")
        queued.removeAll()
        XCTAssertEqual(react.questions(now: nil, log: Self.log).map(\.key), ["react.mood", "react.animation", "react.loops", "say.feeling", "say.about", "say.kind"])
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[0].options.map(\.name), ["none"] + MoodOutput.moods.map(\.name),
                       "the faces are every mood's")
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[1].options.map(\.name), ["none", "success", "failure", "reply", "wake up", "notice"])
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[2].options.map(\.name), ["once", "twice", "three times", "four times"])
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[3].options.map(\.name), ["none", "upset", "glad", "tickled"])
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[4].options.map(\.name), ["none"] + ReactOutput.topics.map(\.name))
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[4].options.count, 17, "none and the 16 topics, hello included")
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[5].options.map(\.name), ["none", "sound", "word", "phrase", "swear"], "none: the face in silence")
        XCTAssertEqual(ReactOutput.holds.indices.map { ReactOutput.loops(["react.loops": a(ReactOutput.holds[$0].name)]) },
                       [1, 2, 3, 4])
        XCTAssertEqual(ReactOutput.loops([:]), 1)
        XCTAssertLessThanOrEqual(ReactOutput.holds.count, DeviceReaction.maxLoops, "the device plays them all")
        XCTAssertEqual(Set(ReactOutput.feelings.map(\.name)), Voice.answers(.feeling), "a feeling for every take's, and none without one")
        XCTAssertEqual(Set(ReactOutput.topics.map(\.name)), Voice.answers(.about), "a topic for every take's, and none without one")
    }

    /// Only the brain's reactions carry an expression; a
    /// rule's reaction never does.
    func testRuleReactionsCarryNoExpression() throws {
        try requireVoice()
        XCTAssertEqual(DeviceReaction(anim: "starting").line(id: 1, play: .ifFree), #"{"t":"do","id":1,"name":"starting","play":"if_free"}"#)
        XCTAssertEqual(DeviceReaction(say: .go).line(id: 2, play: .next),
                       #"{"t":"do","id":2,"name":"react","play":"next","ttl":5000,"args":{"say":{"take":"new.d02"}}}"#)
        XCTAssertEqual(DeviceReaction(say: .go, mood: "grumpy").args.json, #"{"say":{"take":"new.d02"},"mood":"grumpy"}"#)
    }

    /// The pack's moods, in its order; a new Boop starts calm, the resting
    /// mood; the `mood` question offers, on every pass, staying in the
    /// mood the log has and exactly that mood's moves on the graph, each
    /// with its mood's meaning, the dramatic ones also saying they need a
    /// fresh, big event. Staying is nothing to do, and so is an answer the
    /// graph doesn't have from the mood; any move is a change in the log,
    /// which is the mood from then on, and MOOD with it, however recently it
    /// last changed (how long a mood lasts is the steering's call). It's
    /// MellowHarness's `Choice`.
    func testMood() throws {
        XCTAssertEqual(MoodOutput.moods.map(\.name), CharacterPack.active.moods.map(\.id))
        XCTAssertEqual(MoodOutput.moods.map(\.name), MoodGraph.moods)
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
        XCTAssertEqual(offered(), ["calm"] + MoodGraph.moves["calm"]!.all, "staying, then calm's moves, with nothing fresh too")
        let stay = try XCTUnwrap(mood.questions(now: nil, log: view())[0].options.first)
        XCTAssertEqual(stay, Option("calm", "Stay calm: NOW is no reason MOOD gives to leave it, whatever face it gets. No change is fine."),
                       "the resting mood never fades")
        XCTAssertEqual(MoodOutput.options(from: "grumpy").first,
                       Option("grumpy", "Stay grumpy: NOW is no reason MOOD gives to leave it, whatever face it gets, and \(creature) hasn't been grumpy as long as MOOD says it lasts. No change is fine.",
                              notFor: "\(creature) grumpy for as long as MOOD says it lasts, or longer, as HISTORY's last line says: then it fades, as MOOD says."),
                       "any other mood stays only until its minutes are up")
        for m in MoodGraph.moods {
            let options = MoodOutput.options(from: m)
            XCTAssertEqual(options.map(\.name), [m] + MoodGraph.moves[m]!.ordinary + MoodGraph.moves[m]!.dramatic, m)
            for o in options.dropFirst() {
                let meaning = MoodOutput.moods.first { $0.name == o.name }!
                XCTAssertEqual(o.what, meaning.what, "\(m) → \(o.name) carries its meaning")
                let jump = MoodGraph.moves[m]!.dramatic.contains(o.name)
                XCTAssertEqual(o.notFor?.hasSuffix(MoodOutput.jump) ?? false, jump, "\(m) → \(o.name): only a jump says so")
                if jump { XCTAssertEqual(o.notFor, [meaning.notFor, MoodOutput.jump].compactMap { $0 }.joined(separator: " ")) }
                else { XCTAssertEqual(o.notFor, meaning.notFor) }
            }
        }

        XCTAssertNil(run(["mood": a("calm")]), "staying is nothing to do")
        XCTAssertNil(run(["mood": a("grumpy")]), "not a move from calm")
        XCTAssertNil(run(["mood": a("sulky")]), "not a mood")
        XCTAssertNil(run([:]), "no answer")
        XCTAssertEqual(MoodOutput.value(mood, view()), "calm")
        XCTAssertEqual(run(["mood": a("annoyed")]),
                       .done("\(creature)'s mood changed: calm → annoyed.", facts: ["from": "calm", "to": "annoyed"]))
        XCTAssertEqual(offered(), ["annoyed"] + MoodGraph.moves["annoyed"]!.all, "the next pass is offered annoyed's moves")
        XCTAssertEqual(run(["mood": a("grumpy")])?.message, "\(creature)'s mood changed: annoyed → grumpy.", "straight after, a jump too")
        XCTAssertNil(run(["mood": a("happy")]), "grumpy never moves straight to happy")
        XCTAssertNil(run(["mood": a("excited")]), "nor to excited")
        XCTAssertEqual(MoodOutput.value(mood, view()), "grumpy", "the latest change in the log")
        XCTAssertEqual(MoodOutput.value(MoodOutput.choice(), view()), "grumpy", "so it survives a restart")
        log.append(Event.did("\(creature)'s mood changed: grumpy → delighted.", for: nil, action: mood.name, by: "brain",
                             facts: ["from": "grumpy", "to": "delighted"]), now: 1)
        XCTAssertEqual(MoodOutput.value(mood, view()), "calm", "one that isn't a mood reads as calm")
    }

    /// The mood the dashboard sets changes as Jev's does,
    /// device included, to any of the moods, off the graph too; and it's
    /// told why when it can't: the mood it already is, or one that isn't a
    /// mood.
    func testAForcedMoodChangesItAsJevsDoes() throws {
        let pipeline = Pipeline(core: Core(config: .init()), view: TranscriptView())
        let (harness, mood) = Runtime.harness(pipeline: pipeline, steering: RuntimeTests.steering, personality: { .default },
                                              queue: { _, _ in })
        var told: [String] = []
        harness.on(Event.did) { e in if e.action == MoodOutput.outputName, e["ok"]?.bool == true { told.append(e["to"]!.string!) } }
        func change(_ to: String) -> OutputResult? {
            harness.force(mood, by: Runtime.forcedBy) { MoodOutput.change(mood, to: to, log: harness.log.view(now: 1)) }
        }
        XCTAssertEqual(change("grumpy")?.message, "\(creature)'s mood changed: calm → grumpy.", "off the graph")
        XCTAssertEqual(change("grumpy"), .failed("already grumpy"))
        XCTAssertEqual(change("sulky"), .failed("sulky isn't a mood"))
        XCTAssertEqual(MoodOutput.value(mood, harness.log.view(now: 1)), "grumpy")
        XCTAssertEqual(harness.force(["mood": "proud"], by: Runtime.forcedBy).map(\.result.message),
                       ["\(creature)'s mood changed: grumpy → proud."], "Jev's, right after")
        XCTAssertEqual(told, ["grumpy", "proud"], "the device hears each change")
    }

    /// Each mood's file says where it leaves for, and
    /// names only moods it can move to, in every pack.
    func testEachMoodLeavesOnlyForItsNeighbours() throws {
        for mood in MoodGraph.moods {
            let text = RuntimeTests.steering.mood(mood)
            XCTAssertTrue(text.hasPrefix("MOOD\n\(mood.prefix(1).uppercased())\(mood.dropFirst())."), mood)
            let leaves = try! XCTUnwrap(text.range(of: "Leaves for"), mood)
            let named = Set(text[leaves.lowerBound...].split { !$0.isLetter }.map(String.init)).intersection(MoodGraph.moods)
            XCTAssertTrue(named.subtracting([mood]).isSubset(of: (MoodGraph.moves[mood]?.all ?? [])),
                          "\(mood) leaves only for its neighbours, not \(named.subtracting((MoodGraph.moves[mood]?.all ?? []) + [mood]).sorted())")
        }
    }

    // MARK: Jev

    /// Jev out of reach, as `JevBrain` says it (MellowHarness's
    /// own tests pin that), counts toward the brain failing.
    func testJevOutOfReachCountsTowardFailing() {
        XCTAssertEqual(BrainTrouble.after(BrainError("jev: can't reach the server"), previous: 2).trouble?.kind, .failing)
    }
}
