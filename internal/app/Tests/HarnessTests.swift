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
        let keys = harness.actions.flatMap { $0.questions(now: nil, log: Self.log).map(\.key) }
        XCTAssertEqual(keys, askedKeys)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    /// The printer reads view events, passes and actions, a started action
    /// with `…` and an end by its action's name, and skips the other raw
    /// events and the dashboard's lines.
    func testThePrinterSkipsTheDashboardsLines() {
        let printer = DebugLog.Printer()
        let stateJSON = #"You are.\nPERSONALITY\nx\n\nHISTORY (oldest first)\nh\n\nNOW (14:23, Tuesday)\nn"#
        let lines: [(String, String?)] = [
            (#"{"view":{"facts":{},"from":[3],"id":1,"line":"claude finished turn 1.","notes":["Its last message: \"ok\""],"phase":"end","type":"turn","wakes_brain":true},"received_at_ms":5}"#,
             "▸ 1 turn end: claude finished turn 1.\n    Its last message: \"ok\""),
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

    // MARK: The actions

    func a(_ choice: String, _ p: Double = 0.9) -> Answer { Answer(choice: choice, probabilities: [choice: p]) }

    /// `none` does nothing; the meaning counts over 0.35,
    /// and Voice says a take of it in the face's mood, else nothing; the
    /// moment carries the expression as its `mood`, `react.loops`' pick as
    /// its loops (once to four times: 1–4, and once when it's missing) and
    /// a `say` whether or not there's a take, and goes to the queue with
    /// the handle the result is started with; a blocked reaction fails,
    /// with no handle.
    func testReact() throws {
        try requireVoice()
        XCTAssertEqual(ReactAction.sayFloor, 0.35)
        var queued: [(moment: DeviceMoment, pending: Pending)] = []
        var sent: [DeviceMoment] { queued.map(\.moment) }
        var why: String?
        let react = ReactAction(queue: { queued.append(($0, $1)) }, blocked: { why },
                                who: { _ in .init(agent: "codex", thread: "fix-nav") })
        /// Runs `answers`, and checks the result is started with `message`
        /// and the handle its moment was queued with.
        func starts(_ answers: Answers, _ message: String, line: UInt = #line) {
            let before = queued.count
            let result = react.run(answers, now: nil, log: Self.log)
            XCTAssertEqual(queued.count, before + 1, "one moment queued", line: line)
            // `SAID` stands for the line the take picked at random says.
            // The start carries the takes' ids.
            let said = queued.last?.moment.say?.text ?? "?"
            XCTAssertEqual(result, queued.last.map { q in
                .started(message.replacingOccurrences(of: "SAID", with: said), q.pending,
                         facts: ["takes": .array((q.moment.say?.takes ?? []).map { .string($0.id) })])
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
        XCTAssertTrue(grumbled.allSatisfy { $0.mood == "grumpy" }, "in the face's mood")
        XCTAssertTrue(grumbled.count == 1 || grumbled[1].meaning == "tests", "then the topic")
        XCTAssertNotNil(sent[1].say, "a reaction that says nothing still has a say")
        XCTAssertEqual(sent[1].say?.takes, [], "below the floor, Jev is guessing: nothing")
        XCTAssertNil(sent[0].anim, "it plays over the face")
        XCTAssertEqual(sent.map(\.mood), ["grumpy", "proud", "happy"], "each wears its face")
        XCTAssertEqual(sent.map(\.loops), [2, 1, 4], "for its loops")
        XCTAssertTrue(sent[0].args.json.hasSuffix(#","mood":"grumpy","loops":2}"#), sent[0].args.json)
        XCTAssertEqual(sent[0].name, "react")
        XCTAssertEqual(react.run(["react.mood": a("sulky")], now: nil, log: Self.log), nil, "not a face")
        starts(["react.mood": a("excited"), "react.loops": a("three times")], "\(creature) made an excited face, held three times.")
        XCTAssertEqual(queued.last?.moment.loops, 3)
        queued.removeLast()
        // `react.animation` judges a turn's finish, and
        // plays it in the face: a success or a failure is the face's
        // task_complete for that outcome, a reply its reply_ready; each in
        // one of its variations at random, never the last one, naming
        // whose turn it was. `none`, a missing answer or anything else is
        // just the face.
        XCTAssertEqual(ReactAction.animations.map(\.name), ["success", "failure", "reply"])
        starts(["react.mood": a("proud"), "react.animation": a("success"), "react.loops": a("twice"), "say.feeling": a("glad"),
                "say.kind": a("phrase")],
               #"\#(creature) played a success in a proud face, held twice, and said "SAID"."#)
        XCTAssertEqual(queued.last?.moment.say?.takes.first?.kind, .phrase, "a proud phrase, at a success")
        let success = try! XCTUnwrap(queued.last?.moment)
        XCTAssertEqual(success.anim, "task_complete")
        XCTAssertEqual(success.outcome, "success")
        XCTAssertTrue(FaceLoops.variants(mood: "proud", state: "task_complete", outcome: "success").contains(success.variant!))
        let line = success.line(id: 7, play: .next)
        XCTAssertTrue(line.hasPrefix(#"{"t":"do","id":7,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success","variant":"#
                                     + "\(success.variant!)" + #","who":{"agent":"codex","thread":"fix-nav"},"say":"#), line)
        XCTAssertTrue(line.hasSuffix(#","mood":"proud","loops":2}}"#), line)
        queued.removeLast()
        starts(["react.mood": a("whiny"), "react.animation": a("failure")], "\(creature) played a failure in a whiny face, held once.")
        let failure = try! XCTUnwrap(queued.last?.moment)
        XCTAssertEqual([failure.anim, failure.outcome], ["task_complete", "failure"])
        XCTAssertEqual(Set(FaceLoops.variants(mood: "whiny", state: "task_complete", outcome: "failure")), [4, 5, 6])
        XCTAssertTrue([4, 5, 6].contains(failure.variant!), "a failure's variation, never a success's")
        XCTAssertEqual(failure.who, .init(agent: "codex", thread: "fix-nav"))
        queued.removeLast()
        starts(["react.mood": a("curious"), "react.animation": a("reply"), "say.about": a("answer")],
               #"\#(creature) played a reply in a curious face, held once, and said "SAID"."#)
        XCTAssertEqual(queued.last?.moment.say?.takes.map(\.meaning), ["answer"])
        let reply = try! XCTUnwrap(queued.last?.moment)
        XCTAssertEqual(reply.anim, "reply_ready")
        XCTAssertNil(reply.outcome, "a reply has no outcome")
        XCTAssertTrue((1...FaceLoops.count(mood: "curious", state: "reply_ready")).contains(reply.variant!))
        XCTAssertEqual(reply.who, .init(agent: "codex", thread: "fix-nav"))
        queued.removeLast()
        // Each finish is one of its variations at random,
        // never the last one of its animation again.
        var finishes: [Int] = []
        for _ in 0..<30 {
            _ = react.run(["react.mood": a("calm"), "react.animation": a("success")], now: nil, log: Self.log)
            finishes.append(queued.removeLast().moment.variant!)
        }
        XCTAssertEqual(Set(finishes), Set(FaceLoops.variants(mood: "calm", state: "task_complete", outcome: "success")))
        XCTAssertTrue(zip(finishes, finishes.dropFirst()).allSatisfy { $0 != $1 }, "\(finishes)")
        for pick in ["none", "cheer", "wiggle", "confetti"] {
            starts(["react.mood": a("happy"), "react.animation": a(pick)], "\(creature) made a happy face, held once.")
            XCTAssertNil(queued.last?.moment.anim, pick)
            XCTAssertNil(queued.last?.moment.who, "only a finish names whose turn")
            queued.removeLast()
        }
        XCTAssertNil(react.run(["react.mood": a("proud-success")], now: nil, log: Self.log), "a face and an animation are separate questions")
        why = "something needs you"
        for expression in ReactAction.expressions.map(\.name) {
            XCTAssertEqual(react.run(["react.mood": a(expression)], now: nil, log: Self.log), .failed("something needs you"))
        }
        XCTAssertEqual(sent.count, 3, "no face or take while something needs you")
        why = nil
        // A success take only on a success, a swear only on a
        // failure: an irritated swear asked for at a check failing
        // mid-turn is a phrase, and at a failed turn a swear.
        starts(["react.mood": a("irritated"), "say.feeling": a("upset"), "say.kind": a("swear")],
               #"\#(creature) made an irritated face, held once, and said "SAID"."#)
        XCTAssertEqual(queued.last?.moment.say?.takes.first?.kind, .phrase)
        let swore = react.run(["react.mood": a("irritated"), "react.animation": a("failure"), "say.feeling": a("upset"),
                               "say.kind": a("swear")], now: nil, log: Self.log)
        XCTAssertEqual(queued.last?.moment.say?.takes.first?.kind, .swear, "\(String(describing: swore))")
        starts(["react.mood": a("happy"), "say.about": a("done"), "say.kind": a("word")], "\(creature) made a happy face, held once.")
        queued.removeAll()
        XCTAssertEqual(react.questions(now: nil, log: Self.log).map(\.key), ["react.mood", "react.animation", "react.loops", "say.feeling", "say.about", "say.kind"])
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[0].options.map(\.name), ["none"] + MoodAction.moods.map(\.name),
                       "the faces are the 13 moods'")
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[1].options.map(\.name), ["none", "success", "failure", "reply"])
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[2].options.map(\.name), ["once", "twice", "three times", "four times"])
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[3].options.map(\.name), ["none", "upset", "glad", "tickled"])
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[4].options.map(\.name), ["none"] + ReactAction.topics.map(\.name))
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[4].options.count, 17, "none and the 16 topics, hello included")
        XCTAssertEqual(react.questions(now: nil, log: Self.log)[5].options.map(\.name), ["sound", "word", "phrase", "swear"])
        XCTAssertEqual(ReactAction.holds.indices.map { ReactAction.loops(["react.loops": a(ReactAction.holds[$0].name)]) },
                       [1, 2, 3, 4])
        XCTAssertEqual(ReactAction.loops([:]), 1)
        XCTAssertLessThanOrEqual(ReactAction.holds.count, DeviceMoment.maxLoops, "the device plays them all")
        XCTAssertEqual(Set(ReactAction.feelings.map(\.name)), Voice.answers(.feeling), "a feeling for every take's, and none without one")
        XCTAssertEqual(Set(ReactAction.topics.map(\.name)), Voice.answers(.about), "a topic for every take's, and none without one")
    }

    /// Only the brain's reactions carry an expression; a
    /// rule's one-shot never does.
    func testRuleMomentsCarryNoExpression() throws {
        try requireVoice()
        XCTAssertEqual(DeviceMoment(anim: "starting").line(id: 1, play: .ifFree), #"{"t":"do","id":1,"name":"starting","play":"if_free"}"#)
        XCTAssertEqual(DeviceMoment(say: .go).line(id: 2, play: .next),
                       #"{"t":"do","id":2,"name":"react","play":"next","ttl":5000,"args":{"say":{"take":"new.d02"}}}"#)
        XCTAssertEqual(DeviceMoment(say: .go, mood: "grumpy").args.json, #"{"say":{"take":"new.d02"},"mood":"grumpy"}"#)
    }

    /// The 13 moods, in the device's order; a new
    /// Boop starts calm, the resting mood; the `mood` question offers, on
    /// every pass, staying in the mood the log has and exactly that mood's
    /// moves on the graph, each with its mood's meaning, the dramatic ones
    /// also saying they need a fresh, big event. Staying is nothing to do,
    /// and so is an answer the graph doesn't have from the mood; any move
    /// is a change in the log, which is the mood from then on, and MOOD with
    /// it, however recently it last changed (how long a mood lasts is the
    /// steering's call). It's MellowHarness's `Choice`.
    func testMood() throws {
        XCTAssertEqual(MoodAction.moods.map(\.name), CharacterPack.active.v2Names, "the pack's, in its order")
        XCTAssertEqual(MoodAction.moods.map(\.name), MoodGraph.moods)
        XCTAssertEqual(MoodAction.initial, "calm")
        let log = Transcript.log()
        let mood = MoodAction.choice()
        func view() -> LogView { log.view(now: 1) }
        func run(_ answers: Answers) -> ActionResult? {
            let result = mood.run(answers, now: nil, log: view())
            if let result { log.append(Event.did(result.message, for: nil, action: mood.name, by: "brain", facts: result.facts), now: 1) }
            return result
        }
        XCTAssertEqual(MoodAction.value(mood, view()), "calm", "a new Boop starts calm")
        func offered() -> [String] { mood.questions(now: nil, log: view())[0].options.map(\.name) }
        XCTAssertEqual(mood.questions(now: nil, log: view()).map(\.key), ["mood"])
        XCTAssertEqual(offered(), ["calm"] + MoodGraph.moves["calm"]!.all, "staying, then calm's moves")
        let stay = try XCTUnwrap(mood.questions(now: nil, log: view())[0].options.first)
        XCTAssertEqual(stay, Option("calm", "Stay calm: NOW is no reason MOOD gives to leave it, nor are its minutes up. No change is fine."))
        for m in MoodGraph.moods {
            let options = MoodAction.options(from: m)
            XCTAssertEqual(options.map(\.name), [m] + MoodGraph.moves[m]!.ordinary + MoodGraph.moves[m]!.dramatic, m)
            for o in options.dropFirst() {
                let meaning = MoodAction.moods.first { $0.name == o.name }!
                XCTAssertEqual(o.what, meaning.what, "\(m) → \(o.name) carries its meaning")
                let jump = MoodGraph.moves[m]!.dramatic.contains(o.name)
                XCTAssertEqual(o.notFor?.hasSuffix(MoodAction.jump) ?? false, jump, "\(m) → \(o.name): only a jump says so")
                if jump { XCTAssertEqual(o.notFor, [meaning.notFor, MoodAction.jump].compactMap { $0 }.joined(separator: " ")) }
                else { XCTAssertEqual(o.notFor, meaning.notFor) }
            }
        }

        XCTAssertNil(run(["mood": a("calm")]), "staying is nothing to do")
        XCTAssertNil(run(["mood": a("grumpy")]), "not a move from calm")
        XCTAssertNil(run(["mood": a("sulky")]), "not a mood")
        XCTAssertNil(run([:]), "no answer")
        XCTAssertEqual(MoodAction.value(mood, view()), "calm")
        XCTAssertEqual(run(["mood": a("annoyed")]),
                       .done("\(creature)'s mood changed: calm → annoyed.", facts: ["from": "calm", "to": "annoyed"]))
        XCTAssertEqual(offered(), ["annoyed", "calm", "engaged", "determined", "irritated", "whiny", "grumpy", "wounded", "sad"],
                       "the next pass is offered annoyed's moves")
        XCTAssertEqual(run(["mood": a("grumpy")])?.message, "\(creature)'s mood changed: annoyed → grumpy.", "straight after, a jump too")
        XCTAssertNil(run(["mood": a("happy")]), "grumpy never moves straight to happy")
        XCTAssertNil(run(["mood": a("excited")]), "nor to excited")
        XCTAssertEqual(MoodAction.value(mood, view()), "grumpy", "the latest change in the log")
        XCTAssertEqual(MoodAction.value(MoodAction.choice(), view()), "grumpy", "so it survives a restart")
        log.append(Event.did("Boop's mood changed: grumpy → delighted.", for: nil, action: mood.name, by: "brain",
                             facts: ["from": "grumpy", "to": "delighted"]), now: 1)
        XCTAssertEqual(MoodAction.value(mood, view()), "calm", "one that isn't a mood reads as calm")
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
        harness.on(Event.did) { e in if e.action == MoodAction.actionName, e["ok"]?.bool == true { told.append(e["to"]!.string!) } }
        func change(_ to: String) -> ActionResult? {
            harness.force(mood, by: Runtime.forcedBy) { MoodAction.change(mood, to: to, log: harness.log.view(now: 1)) }
        }
        XCTAssertEqual(change("grumpy")?.message, "\(creature)'s mood changed: calm → grumpy.", "off the graph")
        XCTAssertEqual(change("grumpy"), .failed("already grumpy"))
        XCTAssertEqual(change("sulky"), .failed("sulky isn't a mood"))
        XCTAssertEqual(MoodAction.value(mood, harness.log.view(now: 1)), "grumpy")
        XCTAssertEqual(harness.force(["mood": "proud"], by: Runtime.forcedBy).map(\.result.message),
                       ["\(creature)'s mood changed: grumpy → proud."], "Jev's, right after")
        XCTAssertEqual(told, ["grumpy", "proud"], "the device hears each change")
    }

    /// Each mood's file says where it leaves for, and
    /// names only moods it can move to.
    func testEachMoodLeavesOnlyForItsNeighbours() throws {
        try requirePack("boop")  // how Boop's mood files are written
        for version in [MoodGraph.Version.v2, .v3] {
        for mood in MoodGraph.moods(for: version) {
            let text = RuntimeTests.steering.mood(mood, version: version)
            XCTAssertTrue(text.hasPrefix("MOOD\n\(mood.prefix(1).uppercased())\(mood.dropFirst())."), mood)
            let leaves = try! XCTUnwrap(text.range(of: "Leaves for"), mood)
            let named = Set(text[leaves.lowerBound...].split { !$0.isLetter }.map(String.init)).intersection(MoodGraph.moods(for: version))
            XCTAssertTrue(named.subtracting([mood]).isSubset(of: (MoodGraph.moves(for: version)[mood]?.all ?? [])),
                          "\(mood) leaves only for its neighbours, not \(named.subtracting((MoodGraph.moves(for: version)[mood]?.all ?? []) + [mood]).sorted())")
        }
        }
    }

    // MARK: Jev

    /// Jev out of reach, as `JevBrain` says it (MellowHarness's
    /// own tests pin that), counts toward the brain failing.
    func testJevOutOfReachCountsTowardFailing() {
        XCTAssertEqual(BrainTrouble.after(BrainError("jev: can't reach the server"), previous: 2).trouble?.kind, .failing)
    }
}
