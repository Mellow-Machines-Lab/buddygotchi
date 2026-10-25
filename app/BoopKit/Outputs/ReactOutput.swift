import Foundation
import MellowHarness

/// Whether Boop reacts to NOW: with which mood's face, which animation,
/// for how long, and what it says. A reaction
/// is a mood × a visual for a while: the device draws that mood's design
/// of whatever look is showing, or of the animation picked (a turn's
/// finish: task_complete for its outcome, or reply_ready; wake_up, you
/// back after a long break; or notice, its name in your prompt), for a
/// number of its loops. Jev picks what Boop says as a feeling, a
/// topic and a kind, and Voice finds a recorded take of each in the face's
/// mood and joins them into a `say`, or finds none, and then the face plays
/// in silence. To what you said on push-to-talk, Jev picks a reply in
/// their place (`Reply`), and the rest is looked up from it: the board's
/// clip, the takes and the sign. It waits in the device's queue until whatever plays there
/// has finished. It's started, not done,
/// until whoever plays it ends its handle.
public final class ReactOutput: Output {
    public static let outputName = "react"
    public let name = ReactOutput.outputName
    /// Whose reactions: its character, and the buddy's voice when there
    /// are several.
    let pack: CharacterPack
    public let voice: String?
    /// Its questions, built once: none of them changes. What you said gets
    /// its own (`talkQuestions`).
    let asked: [Question]
    let askedOfTalk: [Question]
    /// Sends a brain reaction, which waits in the device's queue behind
    /// whatever is playing, with the handle to end once the device says how
    /// it ended, or once it never will.
    let queue: (DeviceReaction, Pending) -> Void
    /// Why a reaction can't play now (something needs you), or nil.
    let blocked: () -> String?
    /// The agent and thread the event the brain answers is about, or nil
    /// (a poke, an idle heartbeat): a finish, or a face for a finished
    /// turn, names it on the device.
    let who: (Event?) -> DeviceReaction.Who?
    /// How long the turn that event finished ran, in ms, or nil when it
    /// finished none: a finish sends the tier it reached as its `turn`,
    /// which the device may size it by.
    let turnMs: (Event?) -> Int64?
    /// Whether the device plays the takes Voice picks from: false while its
    /// card has another pack, or none, and then Boop says
    /// nothing.
    let speaks: () -> Bool
    /// The pack's sign captions (`signs.md`), and the calendar's tags at an
    /// event: a prompt's reading may get a sign (`Signs`).
    let signs: [TaggedLine]
    let calendar: (Event) -> [String]
    /// What a reply holds up (`replies.md`), and for a `status` one about
    /// what you said, the agents' facts that answer it and where the board
    /// shows the rest (`StatusReply`), or nil for none.
    let replies: [TaggedLine]
    let status: (Event) -> StatusReply.Answer?
    /// Picks among the takes that fit, and remembers the last `say`'s
    /// words, which aren't said again while another fits.
    var takes = SplitMix64(seed: 0x7A4E)
    var lastWords: Set<String> = []
    /// The last reply's sign, which the next reply doesn't hold up again
    /// while another fits.
    var lastReplySign: String?
    /// With a `voice`, a buddy's: its picks are its own, so two buddies
    /// don't say the same words.
    public init(queue: @escaping (DeviceReaction, Pending) -> Void, blocked: @escaping () -> String?,
                who: @escaping (Event?) -> DeviceReaction.Who? = { _ in nil },
                turnMs: @escaping (Event?) -> Int64? = { _ in nil }, speaks: @escaping () -> Bool = { true },
                pack: CharacterPack = .active, voice: String? = nil, signs: [TaggedLine] = [],
                calendar: @escaping (Event) -> [String] = { _ in [] }, replies: [TaggedLine] = [],
                status: @escaping (Event) -> StatusReply.Answer? = { _ in nil }) {
        let seed = voice.map { $0.utf8.reduce(UInt64(0)) { $0 &* 31 &+ UInt64($1) } } ?? 0
        takes = SplitMix64(seed: 0x7A4E ^ seed)
        self.pack = pack
        self.voice = voice
        asked = Self.asked(in: pack)
        askedOfTalk = Self.talkQuestions(Self.asked(in: pack), in: pack)
        self.queue = queue
        self.blocked = blocked
        self.who = who
        self.turnMs = turnMs
        self.speaks = speaks
        self.signs = signs
        self.calendar = calendar
        self.replies = replies
        self.status = status
    }

    static func article(_ word: String) -> String { "aeiou".contains(word.first ?? "x") ? "an" : "a" }

    /// Each expression: a mood's name, in `MoodOutput.moods`' order, and
    /// what the face means for this reaction, from the
    /// pack's moods' `face`, else their meaning (characters/CHARACTER.md
    /// §5). It's the
    /// reaction's face only, never the lasting mood. What it says is a take
    /// performed in that mood (`Voice`).
    public static var expressions: [Option] { CharacterPack.active.faces }

    /// How Boop can feel about NOW, in the order `say.feeling` offers them.
    /// Every feeling take has one, and every face has
    /// takes of each: tests check both, so all are offered.
    public static var feelings: [Option] { feelings(of: CharacterPack.active.name) }
    static func feelings(of name: String) -> [Option] { [
        Option("upset", "Something went wrong or let \(name) down: a check or a turn failing, the agent stuck or giving up, a rude prompt.",
               notFor: "A win, a poke, or work going on, however long."),
        Option("glad", "Something went right: a turn done and working, a check passing, a big win, a kind prompt.",
               notFor: "A failure, or work still going on."),
        Option("tickled", "Poked or teased: a poke, a tap, or a playful prompt.",
               notFor: "A failure, or the agent's work."),
    ] }

    /// What NOW can be about, in the order `say.about` offers them:
    /// each a topic NOW's line shows. Every topic take
    /// has one, and every face has takes of each, as for `feelings`.
    public static var topics: [Option] { topics(of: CharacterPack.active.name) }
    static func topics(of name: String) -> [Option] { [
        Option("start", "A turn starting: off it goes.", notFor: "Work going on, or a turn that finished."),
        Option("helpers", "The agent starting a subagent: helpers sent off."),
        Option("helper back", "A subagent finishing: a helper back with its report."),
        Option("retry", "The same thing again: a retry, a check run again after failing, or the person saying it's still broken.",
               notFor: "A first failure."),
        Option("work", "Work going on: edits, steady progress, a long or hard turn.", notFor: "A turn that finished."),
        Option("tests", "Tests: running, failing or passing."),
        Option("command", "A command or a build running in the terminal.", notFor: "Tests: they're tests."),
        Option("tool", "A tool: the web, an MCP tool, something fetched or looked up."),
        Option("looking", "Searching or reading: the agent looking through files, or something puzzling."),
        Option("planning", "Planning: the agent in plan mode, or thinking before it acts."),
        Option("done", "A long turn finished, done and working.", notFor: "Anything but a success, or a short turn's finish, whose feeling says it."),
        Option("answer", "A turn that only answered something or asked something back.", notFor: "Work done, a failure, or a quick answer, whose feeling says it."),
        Option("stopped", "A turn stopped: interrupted, or the agent giving up.", notFor: "A turn that finished done."),
        Option("waiting", "Waiting: a long command, or the agent waiting on something slow.",
               notFor: "Something that needs the person: the ding says that."),
        Option("quiet", "Nothing going on: a quiet check-in."),
        Option("hello", "The person back at the Mac after a break: a hello.",
               notFor: "Anything else: a poke, a turn starting."),
    ] }

    /// What Boop replies to what you said on push-to-talk: what you meant,
    /// answered. The board plays the pack's clip for it
    /// (`reply-<name>`, characters/CHARACTER.md §15), Voice says the
    /// feeling or the topic it borrows, since no take is recorded for a
    /// reply, and the sign is the pack's line for it (`replies.md`), or for
    /// `status` the agents' facts (`StatusReply`).
    public struct Reply: Sendable {
        public let option: Option
        public let feeling: String?
        public let about: String?
        public var name: String { option.name }
    }

    /// The replies, in the order `react.reply` offers them. Yes and no are
    /// never about the agents: `status` answers those from what the core
    /// knows, so the brain never guesses a fact.
    public static var replies: [Reply] { replies(of: CharacterPack.active.name) }
    static func replies(of name: String) -> [Reply] {
        let agents = "A question about the agents or their work, which is status."
        func reply(_ n: String, _ what: String, notFor: String, feeling: String? = nil, about: String? = nil) -> Reply {
            Reply(option: Option(n, what, notFor: notFor), feeling: feeling, about: about)
        }
        return [
            reply("yes", "Yes: agreeing, or yes to a question about \(name) itself (\"are you awake?\"). It nods.",
                  notFor: agents, feeling: "glad"),
            reply("no", "No: disagreeing, refusing, or no to a question about \(name) itself (\"are you sleepy?\"). It shakes its head.",
                  notFor: agents, feeling: "upset"),
            reply("dunno", "Dunno: a question \(name) can't know the answer to, about the world, the weather or dinner. It shrugs.",
                  notFor: agents + " Words that make no sense, which is huh.", about: "looking"),
            reply("huh", "Huh: what it heard makes no sense, is cut off, or isn't meant for \(name). It tilts its head.",
                  notFor: "Anything it can answer, a question it can't included, which is dunno.", about: "looking"),
            reply("hello", "Hello: a greeting, even one that asks how it's going (\"hey, how's it going?\", \"what's up?\"), or you saying you're back. It waves.",
                  notFor: "Goodbye or good night, which is bye; a question about the agents' work, which is status.",
                  about: "hello"),
            reply("bye", "Bye: goodbye, good night, or you saying you're off for a while. It waves you off.",
                  notFor: "A greeting, which is hello.", feeling: "glad"),
            reply("thanks", "Thanks: praise or thanks for \(name) or the work: \"good job\", \"nice one\". It puffs up, proud.",
                  notFor: "Affection for \(name) itself, which is love.", feeling: "glad"),
            reply("love", "Love: affection for \(name): \"I love you\", \"good boy\", \"you're cute\". It snuggles up.",
                  notFor: "Praise for work done, which is thanks.", feeling: "glad"),
            reply("ouch", "Ouch: rude words or an insult to \(name). It flinches.",
                  notFor: "Teasing, which is hehe; you feeling low or bad news, which is comfort.", feeling: "upset"),
            // Quiet: the upset takes it could borrow are as often cross as kind.
            reply("comfort", "Comfort: you sound tired, sad or stressed, or tell it bad news. It leans in close.",
                  notFor: "Rude words to \(name), which is ouch."),
            reply("hehe", "Hehe: a joke, teasing or something silly. It giggles.", notFor: "Rude words meant to hurt, which is ouch.",
                  feeling: "tickled"),
            reply("status", "Status: a question about the agents or their work: done yet, how long, how many are running, anyone need me, how's the work going, did it work. It holds up the answer on a sign, from what it knows.",
                  notFor: "A question about \(name) itself, which is yes, no or dunno; a greeting, which is hello.", about: "work"),
        ]
    }

    /// The reply `react.reply` picked: `huh` when its answer is missing,
    /// below the floor or not a reply, since Boop answers what you said
    /// with something, and a guess at what you meant is worse.
    public static func reply(_ answers: Answers) -> Reply {
        let all = replies
        let picked = pick(answers, "react.reply", all.map(\.option))
        return all.first { $0.name == picked } ?? all.first { $0.name == "huh" }!
    }

    /// Whether `e` is something you said on push-to-talk, which a reply
    /// answers.
    static func isTalk(_ e: Event?) -> Bool { e?.type == .talk }

    /// What a pass is about: its event, or for one forced from outside
    /// (a demo's), the latest that happened, but for push-to-talk's own
    /// listening after what you said, and the harness's.
    static func about(_ now: Event?, _ log: LogView) -> Event? {
        now ?? log.events.last { !$0.fromHarness && $0.type != .listen }
    }

    /// How big what it says is, plainest first, from nothing at all, the
    /// face in silence: with none of the kind asked for, Voice takes the
    /// nearest one, but never a swear unless one was asked for.
    public static var kinds: [Option] { kinds(of: CharacterPack.active.name) }
    static func kinds(of name: String) -> [Option] { [
        Option("none", "Nothing: the face in silence, for the routine PERSONALITY meets so.",
               notFor: "Anything PERSONALITY gives words to: what stands out, a failure, a poke."),
        Option("sound", "A noise with no word: a huff, a grunt, a gasp. The usual."),
        Option("word", "One word that names the moment.", notFor: "A routine check-in."),
        Option("phrase", "A little catchphrase, for a moment worth remembering, now and then.",
               notFor: "Routine work, or a small win or failure."),
        Option("swear", "A swear, at a failure that really stings.",
               notFor: "A win, a poke, words to \(name), or anything about the person."),
    ] }

    /// The animations a reaction can play in its face: a turn's finish,
    /// judged from what NOW says, a wake-up when you come back from a long
    /// break, or a notice when your prompt says its name. No rule plays
    /// any of them, so the brain judges each one.
    public static var animations: [Option] { animations(of: CharacterPack.active.name) }
    static func animations(of name: String) -> [Option] { [
        Option("success", "NOW's line says a turn finished, done, and doesn't say the agent couldn't finish, asks you something or only answers.",
               notFor: "A check that passed while the turn goes on, a turn that finished failed, one saying it couldn't finish, or one asking you something or only answering."),
        Option("failure", "NOW's line says a turn finished, failed; or finished done, but saying it couldn't finish.",
               notFor: "A check that failed while the turn goes on, or a turn that finished done, saying it's done."),
        Option("reply", "NOW's line says a turn finished, done, asking you something or only answering, often with no tool calls: no task finished.",
               notFor: "Work done, a turn that finished failed, or anything but a turn that finished."),
        Option("wake up", "NOW's line says you came back to the Mac after a long or very long break: \(name) stretches, yawns and wakes up for you.",
               notFor: "A short break, a turn or a poke."),
        Option("notice", "NOW's line says you said \(name)'s name in your prompt: it looks up at you, as if it heard.",
               notFor: "A prompt that doesn't say its name, or anything but a prompt."),
    ] }

    /// The animation `react.animation` picked, or nil for none, a missing
    /// answer or one the device doesn't play.
    public static func animation(_ answers: Answers) -> String? {
        let pick = answers["react.animation"]?.choice
        return animations.contains { $0.name == pick } ? pick : nil
    }

    /// What the device plays for each of `animations`: the face's
    /// task_complete scene for a success or a failure, with that outcome,
    /// its reply_ready for a reply, its wake_up for a wake up, and its
    /// notice for a notice.
    public static let scenes: [String: (anim: String, outcome: String?)] = [
        "success": ("task_complete", "success"), "failure": ("task_complete", "failure"),
        "reply": ("reply_ready", nil), "wake up": ("wake_up", nil), "notice": ("notice", nil),
    ]

    /// How long the face holds, in loops of the design it's drawn in: the
    /// first holds once, and each one after a loop more.
    /// The longest hold of the longest design must end on the device
    /// before the link stops waiting for its `ended` (its `ttl` plus 60 s,
    /// linkkit/SPEC.md §5), or a reaction that played would read as
    /// failed: `testAReactionEndsBeforeTheHarnessCeiling` holds it so.
    public static let holds = [
        Option("once", "A small moment: the usual."),
        Option("twice", "A moment that stands out.", notFor: "Routine work."),
        Option("three times", "A big moment, such as a check passing after failing."),
        Option("four times", "The biggest moments: a very long turn that failed, a hard-won finish, or a failure that keeps coming back.",
               notFor: "A single check, or a single turn short of very long."),
    ]

    /// How many loops the face holds: `react.loops`' pick, or once when
    /// it's missing.
    public static func loops(_ answers: Answers) -> Int {
        (holds.firstIndex { $0.name == answers["react.loops"]?.choice } ?? 0) + 1
    }

    /// A reaction still in progress this long after it started is ended as
    /// failed: past the longest reaction, held
    /// four times in the design with the longest loop.
    public static let openForMs: Int64 = 90_000

    /// Below this, Jev is guessing, and silence beats a guessed meaning.
    public static let sayFloor = 0.35

    /// A `say` question's pick: its answer if it isn't
    /// `none`, reaches the floor and is one of `options`, else nil.
    static func pick(_ answers: Answers, _ key: String, _ options: [Option]) -> String? {
        guard let a = answers[key], a.choice != "none", a.p >= sayFloor,
              options.contains(where: { $0.name == a.choice }) else { return nil }
        return a.choice
    }

    /// How Boop feels, `say.feeling`'s pick, or nil.
    public static func feeling(_ answers: Answers) -> String? { pick(answers, "say.feeling", feelings) }
    /// What NOW is about, `say.about`'s pick, or nil.
    public static func about(_ answers: Answers) -> String? { pick(answers, "say.about", topics) }

    /// How big the feeling's take is: `say.kind`'s pick, or a sound when
    /// it's missing.
    public static func kind(_ answers: Answers) -> Take.Kind {
        answers["say.kind"].flatMap { Take.Kind(rawValue: $0.choice) } ?? .sound
    }

    /// Whether `say.kind` picked saying nothing: the face plays in silence.
    public static func silent(_ answers: Answers) -> Bool { answers["say.kind"]?.choice == "none" }

    /// Its questions, and for a prompt's reading the sign's, when a
    /// caption fits it.
    public func questions(now: Event?, log: LogView) -> [Question] {
        if Self.isTalk(Self.about(now, log)) { return askedOfTalk }
        let captions = offered(now, log)
        guard !captions.isEmpty else { return asked }
        return asked + [Question(key: Signs.questionKey,
                                 text: "If \(pack.name) reacts, does it hold up a sign about your prompt, as PERSONALITY says? Your own words played back in \(pack.name)'s way are the best of these, when they fit the face.",
                                 about: "the NOW section and the words under it", judgeBy: "PERSONALITY and MOOD, how the person sounds, and TALK if there is one",
                                 options: [Option("none", "No sign: PERSONALITY gives this prompt none, or nothing in it is worth holding up.")]
                                     + captions.map { Option($0, "A sign that says this.") })]
    }

    /// The captions a sign may show for `now`, if it's a prompt's reading;
    /// with no event (a pass forced from outside, such as a demo's), for
    /// a prompt's reading only when it's the latest thing that happened.
    func offered(_ now: Event?, _ log: LogView) -> [String] {
        guard let about = Self.about(now, log), about.type == .prompt,
              let reading = PromptReading(facts: about.data) else { return [] }
        return Signs.offered(signs, reading: reading, name: pack.name, calendar: calendar(about))
    }

    /// The questions asked: a character pack with no voice is never asked
    /// what to say (characters/CHARACTER.md §8), so it has no `say.*` ones.
    static func asked(in pack: CharacterPack) -> [Question] {
        Take.all(in: pack).isEmpty ? questions(in: pack).filter { !$0.key.hasPrefix("say.") } : questions(in: pack)
    }

    /// The questions asked of what you said, from `asked`: the face, never
    /// none, since what you said always gets one, the reply in place of the
    /// feeling, the topic and the animation, how long and how big.
    static func talkQuestions(_ asked: [Question], in pack: CharacterPack) -> [Question] {
        let name = pack.name
        let reply = Question(key: "react.reply", text: "If \(name) reacts, what does it reply to what you said? It answers what you meant with its body, a sound or a word, and a sign, never with words of its own.",
                             about: "the words NOW quotes", judgeBy: "what the person meant, then PERSONALITY's Examples",
                             options: replies(of: name).map(\.option))
        let kept = asked.filter { ["react.loops", "say.kind"].contains($0.key) }
        let face = asked.first { $0.key == "react.mood" }.map {
            Question(key: $0.key, text: "Which face does \(name) make at what you said? It always makes one.", about: $0.about,
                     judgeBy: $0.judgeBy, options: $0.options.filter { $0.name != "none" })
        }
        return (face.map { [$0] } ?? []) + [reply] + kept
    }

    /// Every question, for `pack`'s character.
    static func questions(in pack: CharacterPack = .active) -> [Question] {
        let name = pack.name
        let byBoth = "the PERSONALITY and MOOD sections, PERSONALITY's Examples first"
        // What it says is TALK's to size, when the pack has one.
        let bySay = "PERSONALITY's Examples, each made smaller or bigger as TALK says if there is one, then MOOD"
        return [
            Question(key: "react.mood", text: "How should \(name) react to NOW, if at all? It makes this mood's face for a moment, and may say something.",
                     about: "the NOW section", judgeBy: byBoth,
                     options: [Option("none", "Stay quiet: nothing in NOW is worth a face, "
                                          + "or HISTORY shows \(name) still making the one it calls for, about the same thing (in progress).",
                                      notFor: "Something new said to \(name), which always gets a face of its own, even while one plays; "
                                          + "or anything PERSONALITY's Examples react to that \(name) isn't already doing.")]
                         + pack.faces),
            Question(key: "react.animation", text: "If \(name) reacts, does NOW's line call for an animation: a turn that finished, and how it ended, you back after a long break, or your prompt saying \(name)'s name?",
                     about: "the NOW section", judgeBy: "NOW's line, and what it says the agent's last message said",
                     options: [Option("none", "Just the face: NOW's line isn't a turn that finished done or failed, you back after a long break, or a prompt that says \(name)'s name. A turn starting, a prompt that doesn't say its name, a check passing or failing (tests, a build, a deploy), a poke, a check-in, a short break and a stopped turn all get none.")]
                         + ReactOutput.animations(of: name)),
            Question(key: "react.loops", text: "If \(name) reacts, how long does it hold the face?", about: "the NOW section",
                     judgeBy: byBoth, options: ReactOutput.holds),
            Question(key: "say.feeling", text: "If \(name) reacts, how does it feel about NOW? It says so first, in its face's mood.",
                     about: "the NOW section", judgeBy: bySay,
                     options: [Option("none", "No feeling to say: nothing in NOW is worth a sound.")] + ReactOutput.feelings(of: name)),
            Question(key: "say.about", text: "If \(name) reacts, does it say a second word after its feeling, naming what NOW is about, and which? Most reactions say one thing, not two: add one only where PERSONALITY's Example for a moment like NOW pairs a feeling with a topic (\"glad, then done\"), or TALK asks for one.",
                     about: "the NOW section", judgeBy: bySay,
                     options: [Option("none", "No second word: the feeling says enough, as it mostly does, or NOW's line isn't about any of these.")] + ReactOutput.topics(of: name)),
            Question(key: "say.kind", text: "If \(name) reacts, how big is what it says, if anything?", about: "the NOW section",
                     judgeBy: bySay, options: ReactOutput.kinds(of: name)),
        ]
    }

    public func run(_ answers: Answers, now: Event?, log: LogView) -> OutputResult? {
        // 1. Does Jev want a reaction at all, and with which face?
        guard let choice = answers["react.mood"]?.choice, pack.faces.contains(where: { $0.name == choice }) else {
            return nil
        }
        // 2. This output's own rules.
        if let why = blocked() { return .failed(why) }
        // 3. The effect: the face, and the `say`, if Voice has takes
        // for the feeling and the topic in this face's mood and the
        // animation. To what you said, the reply's.
        let about = Self.about(now, log)
        let reply = Self.isTalk(about) ? Self.reply(answers) : nil
        let loops = Self.loops(answers)
        let pick = reply == nil ? Self.animation(answers) : nil
        let feeling = reply.map(\.feeling) ?? Self.feeling(answers), topic = reply.map(\.about) ?? Self.about(answers)
        let said = !speaks() || Self.silent(answers) ? [] : Voice.say(feeling: feeling, about: topic, kind: Self.kind(answers),
                                               face: choice, finish: pick, avoiding: lastWords, in: pack, rng: &takes)
        if !said.isEmpty { lastWords = Set(said.map(\.text)) }
        let say = DeviceReaction.Say(takes: said)
        let sign: String?
        var show: String?
        if let reply, let about {
            (sign, show) = replySign(reply, about)
        } else {
            let picked = answers[Signs.questionKey]?.choice
            sign = picked.flatMap { offered(now, log).contains($0) ? $0 : nil }
        }
        var reaction = DeviceReaction(say: say, mood: choice, loops: loops, sign: sign)
        reaction.reply = reply?.name
        reaction.show = show
        if let pick, let scene = Self.scenes[pick] {
            let (anim, outcome) = scene
            // Its scene and a finish's outcome, whose variation the device
            // picks: a turn's finish names whose turn it was, and says how
            // long it ran.
            reaction.anim = anim
            reaction.outcome = outcome
            reaction.who = who(about)
            if outcome != nil { reaction.turn = turnMs(about).map { DeviceReaction.turn(lengthMs: $0) } }
        } else if turnMs(about) != nil {
            // A face for a finished turn names it too: the device marks
            // the turn it's about while it plays.
            reaction.who = who(about)
        }
        let pending = Pending()
        queue(reaction, pending)
        // 4. What it started, as its line in HISTORY: in progress until
        // the device says how the reaction ended.
        let did = (pick.map { "\(pack.name) played \(Self.article($0)) \($0) in \(Self.article(choice)) \(choice) face" }
            ?? "\(pack.name) made \(Self.article(choice)) \(choice) face") + (reply.map { ", replying \($0.name)" } ?? "")
        // The takes' ids in order, for the tools to say what it said.
        let held: String = (sign.map { ", holding up a sign: \"\($0)\"" } ?? "")
            + (show == StatusReply.drawer ? " and showing every agent" : "")
        let spoke: String = say.text.map { ", and said \"\($0)\"." } ?? "."
        return .started(did + ", held \(Self.holds[loops - 1].name)" + held + spoke, pending,
                        facts: ["takes": .array(said.map { .string($0.id) })])
    }

    /// What a reply holds up about `said`, what you said, and where the
    /// board shows the rest: for `status` the agents' facts, else the
    /// pack's line for the reply, and not the last reply's sign while
    /// another fits.
    func replySign(_ reply: Reply, _ said: Event) -> (sign: String?, show: String?) {
        let answer = reply.name == "status" ? status(said) : nil
        let sign = reply.name == "status" ? answer?.sign
            : Signs.reply(replies, reply.name, calendar: calendar(said), avoiding: lastReplySign, rng: &takes)
        if sign != nil { lastReplySign = sign }
        return (sign, answer?.show)
    }
}
