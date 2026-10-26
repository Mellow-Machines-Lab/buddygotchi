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

    /// The fifteen replies, in the order the question offers them, and
    /// `unhush` while hushed (`HushTests`); what
    /// you said is asked the same four questions as anything, but its face
    /// is never none and its move is the reply.
    func testWhatYouSaidIsAskedForAReply() {
        XCTAssertEqual(ReactOutput.replies.map(\.name),
                       ["yes", "no", "huh", "hello", "bye", "thanks", "love", "ouch", "comfort", "hehe", "status", "nap", "hush", "dance", "notme"])
        let react = ReactOutput(queue: { _, _ in }, blocked: { nil })
        XCTAssertEqual(react.questions(now: said, log: Self.log).map(\.key), askedKeys.filter { $0 != MoodOutput.outputName })
        XCTAssertEqual(react.questions(now: said, log: Self.log)[1].options.map(\.name), ReactOutput.replies.map(\.name), "no none: talk gets a reply")
        XCTAssertEqual(react.questions(now: said, log: Self.log)[0].options.map(\.name), MoodOutput.moods.map(\.name), "and a face, never none")
        XCTAssertEqual(react.questions(now: poke, log: Self.log).map(\.key), askedKeys.filter { $0 != MoodOutput.outputName })
        for reply in ReactOutput.replies where ["yes", "no"].contains(reply.name) {
            XCTAssertTrue(reply.notFor?.contains("status") == true, "yes and no are never about the agents")
        }
        let yes = try! XCTUnwrap(ReactOutput.replies.first { $0.name == "yes" })
        XCTAssertTrue(yes.notFor?.contains("nap, dance, notme or no") == true, "and yes is never a promise to do something")
    }

    /// A pass forced from outside (a demo's) is about what you said when
    /// that's the latest thing, push-to-talk's listening after it aside.
    func testAForcedPassAfterWhatYouSaidAsksForAReply() {
        let log = Transcript.log()
        log.append(said, now: 1)
        log.append(Event(at: 1, source: .boop, type: .listen, phase: .end, specificType: "device"), now: 1)
        let react = ReactOutput(queue: { _, _ in }, blocked: { nil })
        let move = { (now: Int64) in react.questions(now: nil, log: log.view(now: now)).first { $0.key == ReactOutput.moveKey } }
        XCTAssertTrue(move(1)?.options.contains { $0.name == "status" } == true)
        log.append(poke, now: 2)
        XCTAssertFalse(move(2)?.options.contains { $0.name == "status" } == true)
    }

    /// Pins `sayFloor` for a reply: a missing pick, one below the floor or
    /// one that isn't a reply is `huh`, never silence or a guess; and a
    /// `huh` at a question plays as a shrug (`dunno`).
    func testAnUnsureReplyIsHuh() {
        XCTAssertEqual(ReactOutput.reply(["react.move": a("love")]), "love")
        XCTAssertEqual(ReactOutput.reply(["react.move": a("love", 0.3)]), "huh", "below the floor of 0.35")
        XCTAssertEqual(ReactOutput.reply(["react.move": a("success")]), "huh")
        XCTAssertEqual(ReactOutput.reply([:]), "huh")
        XCTAssertEqual(ReactOutput.played("huh", words: "will it rain tomorrow?"), "dunno")
        XCTAssertEqual(ReactOutput.played("huh", words: "what's the capital of France"), "dunno", "a question word")
        XCTAssertEqual(ReactOutput.played("huh", words: "glorp fizzle banana sprocket"), "huh")
        XCTAssertEqual(ReactOutput.played("love", words: "do you love me?"), "love", "only huh shrugs")
    }

    /// A reply rides on the reaction as `reply`, which the board plays its
    /// pack's clip for, holds up its line, says what `say` picked in the
    /// face's mood, and says so in HISTORY's line; a status reply holds up
    /// the agents' facts.
    func testAReplyPlaysItsClipSignAndTakes() throws {
        var queued: [DeviceReaction] = []
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, replies: lines,
                                status: { e in
                                    StatusReply.Answer(sign: "facts for \(e["words"]?.string ?? "")".prefix(18).description, show: "drawer")
                                })
        func run(_ answers: [String: String], _ now: Event) -> String? {
            react.run(answers.mapValues { a($0) }, now: now, log: Self.log)?.message
        }
        let hello = try XCTUnwrap(run(["react.face": "happy", "react.move": "hello", "say": "hello", "react.intensity": "medium"], said))
        XCTAssertTrue(hello.hasPrefix("\(creature) made a happy face (medium), replying hello, holding up a sign: "), hello)
        XCTAssertEqual(queued.last?.reply, "hello")
        XCTAssertEqual(queued.last?.loops, 2)
        XCTAssertNil(queued.last?.anim, "it plays over the face")
        XCTAssertTrue(["hi hi!", "oh, hi!"].contains(queued.last?.sign ?? ""), "its line")
        XCTAssertTrue(queued.last?.args.json.contains(#""reply":"hello""#) == true)
        if !Take.all.isEmpty {
            let takes = try XCTUnwrap(queued.last?.say?.takes)
            XCTAssertEqual(Set(takes.map(\.meaning)), ["hello"], "its own words")
            XCTAssertTrue(takes.allSatisfy { $0.moods.contains("happy") })
        }
        _ = run(["react.face": "engaged", "react.move": "status"], said)
        XCTAssertEqual(queued.last?.sign, "facts for is claud", "the status closure's, about what you said")
        XCTAssertEqual(queued.last?.show, "drawer", "and where the board shows the rest")
        XCTAssertTrue(queued.last?.args.json.contains(#""show":"drawer""#) == true)
        XCTAssertEqual(queued.last?.say?.takes, [], "say nothing: it says nothing")
        _ = run(["react.face": "curious", "react.move": "huh"], said)
        XCTAssertNil(queued.last?.sign, "a reply with no line holds up nothing")
        XCTAssertEqual(queued.last?.reply, "dunno", "a huh to a question shrugs")
        XCTAssertNil(queued.last?.show, "only status shows the drawer")
        _ = run(["react.face": "happy", "react.move": "success"], poke)
        XCTAssertNil(queued.last?.reply, "only what you said gets a reply")
        XCTAssertEqual(queued.last?.anim, "task_complete")
    }

    /// Pins a reply's sign by the moment: a nap while an agent works, a
    /// notme while something waits on you, and a love within `makeupMs`
    /// of an ouch, each its own line when the pack has one.
    func testAReplysSignKnowsTheMoment() throws {
        var queued: [DeviceReaction] = []
        var moment: [String] = []
        let lines = TaggedLine.parse("""
            - [nap] zzz
            - [nap working] after this
            - [notme] ask them!
            - [notme waiting] that's ur job
            - [love] <3
            - [love makeup] ...fine
            - [ouch] :(
            """)
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, replies: lines, moment: { _ in moment })
        func reply(_ move: String, at: Int64 = 0) -> String? {
            let e = Event(at: at, source: .mic, type: .talk, specificType: "device", data: ["words": "hey"])
            _ = react.run(["react.face": a("happy"), "react.move": a(move)], now: e, log: Self.log)
            return queued.last?.sign
        }
        XCTAssertEqual(reply("nap"), "zzz")
        moment = ["working"]
        XCTAssertEqual(reply("nap"), "after this")
        moment = ["waiting", "working"]
        XCTAssertEqual(reply("notme"), "that's ur job")
        moment = []
        XCTAssertEqual(reply("notme"), "ask them!")
        XCTAssertEqual(ReactOutput.makeupMs, 10 * min)
        XCTAssertEqual(reply("love", at: 0), "<3")
        XCTAssertEqual(reply("ouch", at: 0), ":(")
        XCTAssertEqual(reply("love", at: 9 * min), "...fine", "making up")
        XCTAssertEqual(reply("love", at: 9 * min + 1), "<3", "made up once")
        _ = reply("ouch", at: 20 * min)
        _ = reply("hehe", at: 21 * min)
        XCTAssertEqual(reply("love", at: 22 * min), "...fine", "a laugh between doesn't make up")
        _ = reply("ouch", at: 40 * min)
        XCTAssertEqual(reply("love", at: 40 * min + ReactOutput.makeupMs - 1), "...fine", "just inside ten minutes")
        _ = reply("ouch", at: 60 * min)
        XCTAssertEqual(reply("love", at: 60 * min + ReactOutput.makeupMs), "<3", "ten minutes on, it's forgotten")
    }

    /// Pins `Signs.reply`: only lines whose first tag is the reply, the
    /// most of the moment's tags that fit first, the calendar's among the
    /// plain ones, never the last one shown while another fits.
    func testAReplysSign() {
        var rng = SplitMix64(seed: 3)
        XCTAssertEqual(Signs.replies(lines, "bye", calendar: ["night"]), ["bye bye", "nite nite"], "the night's joins the plain one")
        let moments = TaggedLine.parse("""
            - [comfort] there there
            - [comfort night] bed time?
            - [nap] zzz
            - [nap working] after this
            """)
        XCTAssertEqual(Signs.replies(moments, "comfort", calendar: ["night", "working"]), ["there there", "bed time?"],
                       "not bed time alone all night, at work too")
        XCTAssertEqual(Signs.replies(moments, "nap", calendar: ["night", "working"]), ["after this"], "the moment's beats the plain one")
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

    /// What Boop says isn't said again within its last
    /// `ReactOutput.recentSays` says while another take fits: a happy face's
    /// glad sounds go round before any comes back.
    func testItDoesntRepeatItselfSoon() throws {
        guard !Take.all.isEmpty else { return }
        var queued: [DeviceReaction] = []
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil })
        let fits = Set(Take.all.filter { $0.part == .feeling && $0.meaning == "glad" && $0.moods.contains("happy") && $0.finish == nil }
            .map(\.text))
        let window = Swift.min(ReactOutput.recentSays, fits.count - 1)
        XCTAssertGreaterThan(window, 1)
        var said: [String] = []
        for _ in 0..<12 {
            _ = react.run(["react.face": a("happy"), "react.intensity": a("small"), "say": a("glad")], now: poke, log: Self.log)
            said.append(try XCTUnwrap(queued.last?.say?.takes.last?.text))
        }
        for i in window..<said.count {
            XCTAssertFalse(said[(i - window)..<i].contains(said[i]), "\(said)")
        }
    }

    /// A reply to what you said plays while something needs you (the
    /// board shows its face and sign over the needs-you screen): "tell
    /// claude yes" gets its "that's ur job". Nothing else does, and the mic
    /// still on blocks a reply too.
    func testAReplyShowsOverNeedsYou() {
        var queued: [DeviceReaction] = []
        var mic: String?
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { "something needs you" }, replyBlocked: { mic })
        let answers = ["react.face": a("skeptical"), "react.move": a("notme"), "react.intensity": a("small")]
        _ = react.run(answers, now: poke, log: Self.log)
        XCTAssertEqual(queued.count, 0, "not a poke's")
        _ = react.run(answers, now: said, log: Self.log)
        XCTAssertEqual(queued.last?.reply, "notme", "the reply plays")
        mic = "the mic is on"
        _ = react.run(answers, now: said, log: Self.log)
        XCTAssertEqual(queued.count, 1, "not while the mic is on")
        // A status reply holds up its count, but asks for no drawer: the
        // board opens none over the needs-you screen.
        let status = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { "something needs you" }, replyBlocked: { nil },
                                 status: { _ in .init(sign: "2 need you", show: StatusReply.drawer) })
        _ = status.run(["react.face": a("engaged"), "react.move": a("status"), "react.intensity": a("small")], now: said, log: Self.log)
        XCTAssertEqual(queued.last?.sign, "2 need you")
        XCTAssertNil(queued.last?.show)
    }

    /// With no brain (no key), what you said gets a shrug, the `huh`
    /// reply in Boop's mood, holding up the pack's no-brain line, never
    /// over the needs-you screen; the brain's own replies never offer it.
    func testWithNoBrainItShrugs() throws {
        let rig = CoreRig()
        let shrug = try XCTUnwrap(deviceReactions(rig.core.shrug(sign: "no brain yet :(", at: rig.now)).first)
        XCTAssertEqual(shrug.reply, "huh")
        XCTAssertEqual(shrug.sign, "no brain yet :(")
        XCTAssertNotNil(shrug.mood, "a face, so the board plays the reply's clip")
        XCTAssertEqual(BoopDevice.play(shrug), .next)
        rig.send(.turnStart)
        rig.send(.needsYou, tool: "Bash")
        XCTAssertTrue(rig.core.shrug(sign: "no brain yet :(", at: rig.now).isEmpty, "not over needs you")

        let pack = TaggedLine.parse("""
            - [huh] huh?
            - [huh nobrain] no brain yet :(
            """)
        XCTAssertEqual(Signs.replies(pack, Core.noBrainReply, calendar: ["night", Core.noBrain]), ["no brain yet :("])
        XCTAssertEqual(Signs.replies(pack, "huh", calendar: ["night"]), ["huh?"], "the brain's huh never says it has none")
    }

    /// Talked to, Boop mostly says something back, but never has to: `say`
    /// asks it so, a `none` is kept, and anything else says the reply's
    /// own words. With none in the face, a feeling `say` picked, else the
    /// one the reply borrows (`replyWords`); never a topic, and a reply that
    /// borrows none says nothing.
    func testTalkedToItMostlySaysSomething() throws {
        let react = ReactOutput(queue: { _, _ in }, blocked: { nil })
        let say = try XCTUnwrap(react.questions(now: said, log: Self.log).first { $0.key == ReactOutput.sayKey })
        XCTAssertTrue(say.text.contains("mostly says something"), say.text)
        XCTAssertEqual(say.options.first, ReactOutput.talkSilence(of: creature), "nothing, now and then")
        let poked = try XCTUnwrap(react.questions(now: poke, log: Self.log).first { $0.key == ReactOutput.sayKey })
        XCTAssertNotEqual(poked.options.first, ReactOutput.talkSilence(of: creature), "only what you said")

        guard !Take.all.isEmpty else { return }
        var queued: [DeviceReaction] = []
        var talk = Talk.normal
        let speaking = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, talk: { talk })
        // What it says, as each take's part and meaning: a sound before a
        // word is of the same, so each says one thing.
        func meanings(_ move: String, _ say: Answer?, size: String = "medium", face: String = "happy") -> [String] {
            var answers = ["react.face": a(face), "react.move": a(move), "react.intensity": a(size)]
            answers["say"] = say
            _ = speaking.run(answers, now: said, log: Self.log)
            return Set(queued.last?.say?.takes.map { "\($0.part) \($0.meaning)" } ?? []).sorted()
        }
        XCTAssertEqual(meanings("hello", a("glad")), ["reply hello"], "the reply's own words, whatever say picked")
        XCTAssertEqual(meanings("hello", a("none")), [], "nothing, when it picks nothing")
        XCTAssertEqual(meanings("hello", nil), [])
        XCTAssertEqual(meanings("hello", a("glad", 0.3)), ["reply hello"], "leaning to words, the same")
        XCTAssertEqual(meanings("thanks", a("work", 0.3)), ["reply thanks"])
        // A huh to a question shrugs, dunno, which has no words in a grumpy face.
        XCTAssertEqual(meanings("huh", a("upset"), face: "grumpy"), ["feeling upset"], "none of its own in the face: say's pick")
        XCTAssertEqual(meanings("huh", a("start"), face: "grumpy"), [], "never a topic: dunno borrows no feeling")
        XCTAssertEqual(meanings("huh", a("upset", 0.3), face: "grumpy"), [])
        XCTAssertEqual(meanings("comfort", a("glad", 0.3), face: "grumpy"), [], "comfort borrows none")
        XCTAssertEqual(meanings("comfort", a("retry"), face: "determined"), ["about retry"],
                       "but roots for the retry when you say it still doesn't work")
        XCTAssertEqual(meanings("comfort", a("start"), face: "determined"), [], "and no other topic")
        XCTAssertEqual(meanings("no", a("start")), ["feeling upset"], "no has none in a happy face: a topic picked, the feeling it borrows")
        talk = .quiet
        XCTAssertEqual(meanings("thanks", a("glad", 0.3)), ["reply thanks"])
        XCTAssertEqual(meanings("thanks", a("glad", 0.3), size: "small"), [], "and nothing at a small moment")
    }

    /// A reply says its own words wherever it has some in the face, as big
    /// as the moment: "roll over" gets a no ("Tsk", "Not quite"), never an
    /// upset word ("Failed", "Broken"); "I love you" a love, never a laugh.
    func testAReplySaysItsOwnWords() throws {
        guard !Take.all.isEmpty else { return }
        var queued: [DeviceReaction] = []
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil })
        let rollOver = Event(at: 0, source: .mic, type: .talk, specificType: "device", data: ["words": "roll over"])
        for reply in ReactOutput.replies.map(\.name) + ["unhush"] where reply != "huh" {
            for face in MoodOutput.moods.map(\.name) where Take.all.contains(where: { $0.part == .reply && $0.meaning == reply && $0.moods.contains(face) }) {
                for size in ReactOutput.sizes.map(\.name) {
                    _ = react.run(["react.face": a(face), "react.move": a(reply), "react.intensity": a(size), "say": a("glad")],
                                  now: rollOver, log: Self.log)
                    let takes = try XCTUnwrap(queued.last?.say?.takes)
                    XCTAssertFalse(takes.isEmpty, "\(reply) in \(face) says something")
                    XCTAssertTrue(takes.allSatisfy { $0.part == .reply && $0.meaning == reply && $0.moods.contains(face) },
                                  "\(reply) in \(face): \(takes.map(\.id))")
                }
            }
        }
        // The owner's examples, at every size.
        for size in ReactOutput.sizes.map(\.name) {
            for _ in 0..<20 {
                _ = react.run(["react.face": a("annoyed"), "react.move": a("no"), "react.intensity": a(size), "say": a("upset")],
                              now: rollOver, log: Self.log)
                XCTAssertTrue(Set(queued.last?.say?.takes.map(\.text) ?? []).isDisjoint(with: ["Failed", "Broken", "Trouble"]))
            }
        }
        // Every reply has words of its own.
        let has = Set(Take.all.filter { $0.part == .reply }.map(\.meaning))
        XCTAssertEqual(Set(ReactOutput.replies.map(\.name) + ["dunno", "unhush"]).subtracting(has), [])
    }

    /// Pins how a reply's sign answers what you said: every reply's
    /// captions are offered (`react.sign`), with your words played back,
    /// and of those for the reply it makes, a caption two replies share
    /// counting for both, the brain's likeliest is held up; with none of them liked, one of its lines at random, never your
    /// words.
    func testAReplysSignAnswersWhatYouSaid() throws {
        XCTAssertEqual(Signs.phrases(of: "Hello!", name: "Boop"), ["hello"])
        XCTAssertEqual(Signs.phrases(of: "thanks, Boop", name: "Boop"), ["thanks"])
        XCTAssertEqual(Signs.phrases(of: "good night boop", name: "Boop"), ["good night"])
        XCTAssertEqual(Signs.phrases(of: "Hey how are you today", name: "Boop"), [], "too long to play back")
        XCTAssertEqual(Signs.phrases(of: "why? why!", name: "Boop"), ["why why", "why"], "the whole, then its parts, each once")

        let lines = TaggedLine.parse("""
            - [hello] hi hi!
            - [hello] good, u?
            - [hello] {words} 2 u!
            - [dunno] no idea!
            - [dunno] {words}? idk
            - [huh] huh?
            - [yes] yep!
            - [bye] {words} 2 u!
            """)
        var queued: [DeviceReaction] = []
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, replies: lines)
        let hello = Event(at: 0, source: .mic, type: .talk, specificType: "device", data: ["words": "Hello!"])
        let sign = try XCTUnwrap(react.questions(now: hello, log: Self.log).first { $0.key == Signs.questionKey })
        XCTAssertEqual(sign.options.map(\.name), ["facts", "yep!", "huh?", "no idea!", "hello? idk", "hi hi!", "good, u?", "hello 2 u!"])
        XCTAssertEqual(sign.options.last?.what, "With a hello or bye reply.", "one caption, both its replies")
        XCTAssertEqual(sign.options[3].what, "With a dunno reply (dunno, a huh to a question).")
        XCTAssertNil(react.questions(now: poke, log: Self.log).first { $0.key == Signs.questionKey }, "a poke holds up no reply")

        func held(_ move: String, _ p: [String: Double], _ e: Event? = nil) -> String? {
            let pick = p.max { $0.value < $1.value }?.key ?? "facts"
            _ = react.run(["react.face": a("happy"), "react.move": a(move), Signs.questionKey: Answer(choice: pick, probabilities: p)],
                          now: e ?? hello, log: Self.log)
            return queued.last?.sign
        }
        XCTAssertEqual(held("hello", ["hello 2 u!": 0.6, "good, u?": 0.3]), "hello 2 u!", "your words, played back")
        XCTAssertEqual(held("hello", ["good, u?": 0.4, "yep!": 0.5]), "good, u?", "the likeliest of the reply's own")
        XCTAssertEqual(held("hello", ["yep!": 0.9]), "hi hi!", "none of the reply's: a line at random, not the last one")
        XCTAssertEqual(held("bye", ["hello 2 u!": 0.7]), "hello 2 u!", "a caption bye shares")
        let why = Event(at: 0, source: .mic, type: .talk, specificType: "device", data: ["words": "why?"])
        XCTAssertEqual(held("huh", ["why? idk": 0.8], why), "why? idk", "a huh to a question shrugs with dunno's")
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
        func sign(_ s: [Agent], _ words: String = "how's it going?") -> String { StatusReply.answer(s, words: words, at: now).sign }
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
        let waiting = Agent(agent: "codex", places: ["api"], needsYou: true)
        XCTAssertEqual(sign([working, waiting], "how's the landing going?"), "claude: 4 min in")
        XCTAssertEqual(sign([working, waiting], "is anyone on landing or api?"), "codex needs you", "waiting on you comes first")
        XCTAssertEqual(sign([waiting, waiting], "how's the api?"), "2 need you")
        let more = Agent(agent: "claude", places: ["api"], workingSince: now)
        XCTAssertEqual(sign([working, more], "is claude done?"), "2 claude working", "the agent you named, counted")

        XCTAssertEqual(StatusReply.recentMs, 10 * min)
        let done = Agent(agent: "claude", places: [], result: Result(topic: nil, outcome: "done", at: now - 9 * min))
        XCTAssertEqual(sign([done]), "claude: done!")
        var failed = done
        failed.result = Result(topic: nil, outcome: "failed", at: now - 2 * min)
        XCTAssertEqual(sign([done, failed], "is claude done?"), "claude: failed :(", "the latest")
        var old = done
        old.result?.at = now - 10 * min
        XCTAssertEqual(sign([old]), "all quiet", "ten minutes on, it's no news")
        XCTAssertEqual(sign([]), "all quiet")
    }

    /// Name no agent or place with several sessions open and the answer
    /// counts them and shows them all in the board's drawer: who needs you,
    /// else how many work and how many rest. Asked how many, one session is
    /// counted too, with no drawer; else one session, or a name, gets one
    /// fact and no drawer.
    func testAQuestionAboutThemAllShowsTheDrawer() {
        let now: Int64 = 100 * min
        let working = Agent(agent: "claude", places: ["landing"], workingSince: now - 4 * min)
        let done = Agent(agent: "claude", places: ["api"], result: Result(topic: nil, outcome: "done", at: now - min))
        let idle = Agent(agent: "codex", places: ["nav"])
        func answer(_ s: [Agent], _ words: String = "how many agents are running?") -> StatusReply.Answer {
            StatusReply.answer(s, words: words, at: now)
        }
        XCTAssertEqual(answer([done, idle]), StatusReply.Answer(sign: "2 resting", show: "drawer"), "a count, not the last result")
        XCTAssertEqual(answer([working, done, idle]).sign, "1 working, 2 idle")
        XCTAssertEqual(answer([working, working]).sign, "2 working")
        var waiting = idle
        waiting.needsYou = true
        XCTAssertEqual(answer([working, waiting]).sign, "codex needs you")
        XCTAssertEqual(answer([waiting, waiting, working]).sign, "2 need you")
        XCTAssertEqual(StatusReply.drawer, "drawer")
        XCTAssertEqual(answer([working]), StatusReply.Answer(sign: "1 working"), "asked how many: one session, counted")
        XCTAssertEqual(answer([done], "how many agents do I have"), StatusReply.Answer(sign: "1 resting"))
        XCTAssertEqual(answer([working], "are the agents working?"), StatusReply.Answer(sign: "claude: 4 min in"),
                       "one session: its fact is the answer")
        XCTAssertEqual(answer([]), StatusReply.Answer(sign: "all quiet"))
        XCTAssertNil(answer([working, done, idle], "is codex done?").show, "named: its fact alone")
        XCTAssertNil(answer([working, done, idle], "how's the api going?").show)
        XCTAssertEqual(answer([working, done, idle], "is codex done?").sign, "codex: resting")
        let many = (0..<120).map { Agent(agent: "claude", places: [], workingSince: $0 < 100 ? now : nil) }
        XCTAssertLessThanOrEqual(answer(many).sign.count, Signs.maxLength)
        XCTAssertEqual(answer(many).sign, "100 working", "both won't fit: the work alone")
    }

    /// Say an agent or a place and only those sessions count, the places
    /// matched as you'd say them; an agent that isn't there says so; and
    /// every sign fits `Signs.maxLength`.
    func testNamingAnAgentOrAPlace() {
        let now: Int64 = 100 * min
        let claude = Agent(agent: "claude", places: ["landing-page"], workingSince: now - 4 * min)
        let codex = Agent(agent: "codex", places: ["api", "fix-nav"], result: Result(topic: nil, outcome: "done", at: now - min))
        func sign(_ words: String) -> String { StatusReply.answer([claude, codex], words: words, at: now).sign }
        XCTAssertEqual(sign("is codex done?"), "codex: done!")
        XCTAssertEqual(sign("Is Claude done yet?"), "claude: 4 min in")
        XCTAssertEqual(sign("how's the api going"), "codex: done!")
        XCTAssertEqual(sign("how's the landing page coming along"), "claude: 4 min in", "its words in a row")
        XCTAssertEqual(sign("is landingpage done"), "claude: 4 min in", "run together")
        XCTAssertEqual(sign("is fix nav done"), "codex: done!")
        XCTAssertEqual(sign("how's it going"), "1 working, 1 idle", "nothing named: all of them, counted")
        XCTAssertEqual(StatusReply.answer([claude], words: "what about codex?", at: now).sign, "no codex around")
        XCTAssertEqual(StatusReply.answer([Agent(agent: "codex", places: ["api"])], words: "is codex busy?", at: now).sign, "codex: resting")
        XCTAssertEqual(StatusReply.shortestPlace, 3)
        XCTAssertFalse(StatusReply.mentions(StatusReply.tokens("a b c"), "ab"), "too short to match")
        XCTAssertFalse(StatusReply.mentions(StatusReply.tokens("rapid"), "api"), "a word, not part of one")
        let long = Agent(agent: "claude", places: [], workingSince: now, result: Result(topic: "deploy", outcome: "passed", at: now))
        XCTAssertLessThanOrEqual(StatusReply.answer([long], words: "", at: now).sign.count, Signs.maxLength)
        XCTAssertEqual(StatusReply.answer([long], words: "", at: now).sign, "deploy passed", "the agent left off when it won't fit")
    }

    /// Ask what it's doing and the work going on says what you asked it
    /// for; ask how long you've been at it and the working stretch
    /// answers; something waiting on you still comes first.
    func testWhatItsDoingAndHowLongYouveBeenAtIt() {
        let now: Int64 = 100 * min
        let fixing = Agent(agent: "claude", places: ["api"], workingSince: now - 4 * min, asked: .fix)
        XCTAssertEqual(StatusReply.answer([fixing], words: "what's claude doing?", at: now).sign, "claude: a fix")
        XCTAssertEqual(StatusReply.answer([fixing], words: "what is it working on", at: now).sign, "claude: a fix")
        XCTAssertEqual(StatusReply.answer([fixing], words: "what are you building", at: now).sign, "claude: a fix")
        XCTAssertEqual(StatusReply.answer([fixing], words: "is claude done?", at: now).sign, "claude: 4 min in", "not asked what")
        var other = fixing
        other.asked = .other
        XCTAssertEqual(StatusReply.answer([other], words: "what's claude doing?", at: now).sign, "claude: 4 min in", "nothing to say it in")
        XCTAssertEqual(StatusReply.answer([fixing], words: "how long have I been at it?", at: now, stretchSince: now - 80 * min).sign, "at it 1 h 20")
        XCTAssertEqual(StatusReply.answer([fixing], words: "how long have we been working", at: now, stretchSince: now - 25 * min).sign, "at it 25 min")
        XCTAssertEqual(StatusReply.answer([fixing], words: "how long have I been at it?", at: now, stretchSince: now - 20_000).sign, "just started")
        // Under a minute in, it has just started (`justStartedMs`).
        XCTAssertEqual(StatusReply.justStartedMs, 60_000)
        XCTAssertEqual(StatusReply.answer([fixing], words: "how long have I been at it?", at: now,
                                          stretchSince: now - StatusReply.justStartedMs + 1).sign, "just started")
        XCTAssertEqual(StatusReply.answer([fixing], words: "how long have I been at it?", at: now,
                                          stretchSince: now - StatusReply.justStartedMs).sign, "at it 1 min")
        XCTAssertEqual(StatusReply.answer([fixing], words: "how long've we been coding", at: now, stretchSince: now - 25 * min).sign, "at it 25 min")
        XCTAssertEqual(StatusReply.answer([fixing], words: "how long has claude been going? I'm curious", at: now, stretchSince: now - 80 * min).sign,
                       "claude: 4 min in", "you're not its subject")
        XCTAssertEqual(StatusReply.answer([fixing], words: "how long until we're done?", at: now, stretchSince: now - 80 * min).sign,
                       "claude: 4 min in", "about the work, not you")
        XCTAssertEqual(StatusReply.answer([fixing], words: "how's claude doing?", at: now).sign, "claude: 4 min in", "how it's going, not what")
        XCTAssertEqual(StatusReply.answer([fixing], words: "how long has claude been going?", at: now, stretchSince: now - 80 * min).sign,
                       "claude: 4 min in", "about the agent, not you")
        XCTAssertEqual(StatusReply.answer([fixing], words: "how long have I been at it?", at: now).sign, "claude: 4 min in", "no stretch on")
        let waiting = Agent(agent: "codex", places: [], needsYou: true)
        XCTAssertEqual(StatusReply.answer([fixing, waiting], words: "how long have I been at it?", at: now, stretchSince: now - min).sign,
                       "codex needs you")
        let resting = Agent(agent: "codex", places: [])
        XCTAssertEqual(StatusReply.answer([fixing, resting], words: "how long have I been at it?", at: now, stretchSince: now - 80 * min),
                       .init(sign: "at it 1 h 20"), "about you, so no count and no drawer")
        XCTAssertEqual(StatusReply.duration(2 * 60 * min), "2 h")
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
        XCTAssertEqual(StatusReply.answer([s], words: "", at: rig.now).sign, "claude: 4 min in")
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
