import Foundation
import MellowHarness

/// Whether Boop reacts to NOW, in four answers, the same four every pass:
/// its face (`react.face`), what its body does (`react.move`), how big the
/// moment is (`react.intensity`) and what it says (`say`). A reaction is a
/// mood × a visual for a while: the device draws that mood's design of
/// whatever look is showing, or of the move picked (a turn's finish:
/// task_complete for its outcome, or reply_ready; wake_up, you back after
/// a long break; notice, its name in your prompt; or to what you said on
/// push-to-talk, its reply's clip), for as many loops as the intensity
/// holds. Voice finds a recorded take of what it says, as big as the
/// intensity, in the face's mood, or finds none, and then the face plays
/// in silence; to what you said, the reply's own words, when it has some
/// in that face. A word at a medium moment or bigger sometimes gets a
/// sound of the same meaning before it (`Voice.lead`). A reply's sign is one of the pack's lines for it, which
/// may play back your words, and a status reply's the agents' facts,
/// never guessed. It waits in the
/// device's queue until whatever plays there has finished. It's started,
/// not done, until whoever plays it ends its handle.
public final class ReactOutput: Output {
    public static let outputName = "react"
    public let name = ReactOutput.outputName
    /// Whose reactions: its character, and the buddy's voice when there
    /// are several.
    let pack: CharacterPack
    public let voice: String?
    /// The questions' keys.
    public static let faceKey = "react.face", moveKey = "react.move", intensityKey = "react.intensity", sayKey = "say"
    /// Its questions, built once: none of them changes. What you said gets
    /// its own moves (`talkQuestions`).
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
    /// The moment's tags for a reply's sign at an event: `working` while an
    /// agent works, `waiting` while something waits on you.
    let moment: (Event) -> [String]
    /// Whether Boop is hushed at a time (`Core.Hush`): it says nothing, and
    /// may be let talk again. `hush` hushes it for so many ms from a time,
    /// or with nil lets it talk.
    let hushed: (Int64) -> Bool
    let hush: (_ ms: Int64?, _ at: Int64) -> Void
    /// How much it says, chosen in Settings: on Quiet, `say` offers no
    /// topic and no swear, and a small moment or a finish says nothing.
    let talk: () -> Talk
    /// Picks among the takes that fit, and remembers the last `say`'s
    /// words, which aren't said again while another fits.
    var takes = SplitMix64(seed: 0x7A4E)
    var lastWords: Set<String> = []
    /// The last reply's sign, which the next reply doesn't hold up again
    /// while another fits, and when the last `ouch` not yet made up was.
    var lastReplySign: String?
    var ouchAt: Int64?
    /// With a `voice`, a buddy's: its picks are its own, so two buddies
    /// don't say the same words.
    public init(queue: @escaping (DeviceReaction, Pending) -> Void, blocked: @escaping () -> String?,
                who: @escaping (Event?) -> DeviceReaction.Who? = { _ in nil },
                turnMs: @escaping (Event?) -> Int64? = { _ in nil }, speaks: @escaping () -> Bool = { true },
                pack: CharacterPack = .active, voice: String? = nil, signs: [TaggedLine] = [],
                calendar: @escaping (Event) -> [String] = { _ in [] }, replies: [TaggedLine] = [],
                status: @escaping (Event) -> StatusReply.Answer? = { _ in nil }, moment: @escaping (Event) -> [String] = { _ in [] },
                hushed: @escaping (Int64) -> Bool = { _ in false }, hush: @escaping (_ ms: Int64?, _ at: Int64) -> Void = { _, _ in },
                talk: @escaping () -> Talk = { .default }) {
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
        self.moment = moment
        self.hushed = hushed
        self.hush = hush
        self.talk = talk
    }

    static func article(_ word: String) -> String { "aeiou".contains(word.first ?? "x") ? "an" : "a" }

    /// Each expression: a mood's name, in `MoodOutput.moods`' order, and
    /// what the face means for this reaction, from the
    /// pack's moods' `face`, else their meaning (characters/CHARACTER.md
    /// §5). It's the
    /// reaction's face only, never the lasting mood. What it says is a take
    /// performed in that mood (`Voice`).
    public static var expressions: [Option] { CharacterPack.active.faces }

    /// How Boop can feel about NOW, the first of what `say` offers. Every
    /// feeling take has one, and every face has takes of each: tests check
    /// both, so all are offered.
    public static var feelings: [Option] { feelings(of: CharacterPack.active.name) }
    static func feelings(of name: String) -> [Option] { [
        Option("upset", "Something went wrong or let \(name) down: a check or a turn failing, the agent stuck or giving up, a rude prompt.",
               notFor: "A win, a poke, or work going on, however long; a failed turn that really stings, which swears."),
        Option("glad", "Something went right: a turn done and working, a check passing, a big win, a kind prompt.",
               notFor: "A failure, or work still going on."),
        Option("tickled", "Poked or teased: a poke, a tap, or a playful prompt.",
               notFor: "A failure, or the agent's work."),
    ] }

    /// What NOW can be about, the rest of what `say` offers: each a topic
    /// NOW's line shows. Every topic take has one, and every face has takes
    /// of each, as for `feelings`.
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
        Option("hello", "The person back at the Mac after a break, or greeting \(name): a hello.",
               notFor: "Anything else: a goodbye, a poke, a turn starting."),
    ] }

    /// What Boop replies to what you said on push-to-talk, its move then:
    /// what you meant, answered. The board plays the pack's clip for it
    /// (`reply-<name>`, characters/CHARACTER.md §15), and the sign is the
    /// pack's line for it that answers what you said best (`replies.md`,
    /// `react.sign`), or for `status` the agents' facts (`StatusReply`).
    /// Yes and no are never about the agents, and never a promise:
    /// `status` answers a question about them from what the core knows, so
    /// the brain never guesses a fact, and a request is nap, dance, notme,
    /// or no.
    public static var replies: [Option] { replies(of: CharacterPack.active.name) }
    static func replies(of name: String) -> [Option] {
        let agents = "A question about the agents or their work, which is status."
        let request = "Asking \(name) to do something, which is nap, dance, notme or no."
        return [
            Option("yes", "Yes: agreeing, or yes to a question about \(name) itself (\"are you awake?\", \"are you okay?\"). It nods.",
                   notFor: agents + " " + request),
            Option("no", "No: disagreeing, no to a question about \(name) itself, or turning down something it's asked to do (\"roll over\", \"go away\", a trick when it isn't in the mood). It shakes its head.",
                   notFor: agents + " Asking it to do something for an agent, which is notme."),
            Option("huh", "Huh: \(name) can't answer it: words that make no sense, are cut off or aren't meant for it, or a question it can't know, about the world, the weather or dinner. It shrugs, or tilts its head.",
                   notFor: agents + " A question about \(name) itself, which is yes or no."),
            Option("hello", "Hello: a greeting, even one that asks how it's going (\"hey, how's it going?\", \"what's up?\"), calling out for \(name) (\"where are you?\"), or you saying you're back. It waves.",
                   notFor: "Goodbye or good night, which is bye; a question about the agents' work, which is status."),
            Option("bye", "Bye: goodbye, good night, or you saying you're off for a while. It waves you off.",
                   notFor: "A greeting, which is hello; asking it to sleep, which is nap."),
            Option("thanks", "Thanks: something good: praise or thanks for \(name) or the work (\"good job\", \"nice one\"), your good news (\"we shipped it\"), or wishing you luck. It puffs up, proud.",
                   notFor: "Affection for \(name) itself, which is love."),
            Option("love", "Love: affection for \(name), or making up with it: \"I love you\", \"good boy\", \"you're cute\", \"sorry, \(name)\". It snuggles up.",
                   notFor: "Praise for work done, or your good news, which is thanks."),
            Option("ouch", "Ouch: rude words or an insult to \(name). It flinches.",
                   notFor: "Teasing, which is hehe; you feeling low or bad news, which is comfort."),
            Option("comfort", "Comfort: you sound tired, sad or stressed, or tell it bad news. It leans in close.",
                   notFor: "Rude words to \(name), which is ouch."),
            Option("hehe", "Hehe: a joke, teasing or something silly. It giggles.", notFor: "Rude words meant to hurt, which is ouch."),
            Option("status", "Status: a question about the agents or their work: done yet, how long, how many are running, what they're doing (\"what are you doing?\" too, asked of \(name) at its desk), anyone need me, how's the work going, did it work, how long you've been at it. It holds up the answer on a sign, from what it knows.",
                   notFor: "A question about \(name) itself, which is yes, no or huh; a greeting, which is hello."),
            Option("nap", "Nap: asked to sleep or rest: \"go to sleep\", \"nap time\". It yawns and settles down for a nap.",
                   notFor: "Goodbye or good night, which is bye; asked to be quiet, which is hush; a nap it won't take, which is no."),
            Option("hush", "Hush: asked to stop talking: \"shh\", \"be quiet\", \"shut up\", \"stop talking\". It zips its lips and says nothing for a while, as long as the moment is big: 15 min small, 30 medium, an hour big, two hours huge.",
                   notFor: "Asked to go to sleep or take a nap, which is nap, even at night; rude words that aren't asking for quiet, which is ouch."),
            Option("dance", "Dance: asked to dance or wiggle. It dances.", notFor: "Any other trick, or a dance it won't do, which is no."),
            Option("notme", "Not me: asked to answer, approve, allow, stop or tell an agent something (\"tell claude yes\", \"approve it\", \"go ahead\"). \(name) never does: it shakes its head and looks to the Mac.",
                   notFor: "A question about the agents, which is status."),
        ]
    }

    /// Asked to talk again while hushed, offered only then.
    static func unhush(of name: String) -> Option {
        Option("unhush", "Unhush: you let \(name) talk again: \"you can talk now\", \"speak!\", \"I'm sorry, say something\". It perks up.",
               notFor: "Anything else said while it's hushed, which gets its own reply in silence.")
    }

    /// The reply `react.move` picked of what you said: `huh` when its
    /// answer is missing, below the floor or not a reply, since Boop
    /// answers what you said with something, and a guess at what you meant
    /// is worse.
    public static func reply(_ answers: Answers) -> String {
        pick(answers, moveKey, replies + [unhush(of: CharacterPack.active.name)]) ?? "huh"
    }

    /// What the board plays for `reply` to `words`: a `huh` at a question
    /// is a shrug (`dunno`), at anything else a head tilt.
    public static func played(_ reply: String, words: String) -> String {
        guard reply == "huh" else { return reply }
        let said = words.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let first = said.split { !$0.isLetter && $0 != "'" }.first.map(String.init) ?? ""
        return said.hasSuffix("?") || questionWords.contains(first) ? "dunno" : "huh"
    }

    /// Words a question starts with, for `played`.
    static let questionWords: Set<String> = [
        "what", "what's", "who", "who's", "where", "where's", "when", "why", "how", "how's", "which", "will", "would",
        "is", "are", "can", "could", "do", "does", "did", "should",
    ]

    /// How long after an `ouch` a reply is making up (`makeup`, a tag its
    /// sign may have).
    public static let makeupMs: Int64 = 10 * 60_000
    /// The moment's tags a reply's sign may have, beside the calendar's.
    public static let momentTags = ["working", "waiting", "makeup"]

    /// Whether `e` is something you said on push-to-talk, which a reply
    /// answers.
    static func isTalk(_ e: Event?) -> Bool { e?.type == .talk }

    /// What a pass is about: its event, or for one forced from outside
    /// (a demo's), the latest that happened, but for push-to-talk's own
    /// listening after what you said, and the harness's.
    static func about(_ now: Event?, _ log: LogView) -> Event? {
        now ?? log.events.last { !$0.fromHarness && $0.type != .listen }
    }

    /// How big a moment is, the smallest first: how long the face holds,
    /// a loop more each step, and how big what it says is (`Intensity`).
    public static let intensities = [
        Option("small", "A small moment: the usual. The face holds once, and what it says is a sound."),
        Option("medium", "A moment that stands out. It holds twice, and says a word.", notFor: "Routine work."),
        Option("big", "A big moment, such as a long turn's hard work done or the top of a streak. It holds three times, and says a phrase.",
               notFor: "Routine work, or a small win or failure."),
        Option("huge", "The biggest moments: a very long turn that failed, a hard-won finish (a long turn done after failed checks), or a long turn that failed after failed checks or turns before it. It holds four times, and says a phrase.",
               notFor: "A check or a command failing mid-turn, however many times, or a turn short of very long with no failure before it."),
    ]

    /// What an intensity sets: how many loops the face holds and the kind
    /// of take it says.
    public struct Intensity: Equatable, Sendable {
        public let name: String
        public let loops: Int
        public let kind: Take.Kind
    }

    /// Each intensity, in `intensities`' order: once a sound, twice a
    /// word, three and four times a phrase.
    public static let sizes: [Intensity] = zip(intensities, [(1, Take.Kind.sound), (2, .word), (3, .phrase), (4, .phrase)])
        .map { Intensity(name: $0.name, loops: $1.0, kind: $1.1) }

    /// The intensity `react.intensity` picked, or small when it's missing.
    public static func intensity(_ answers: Answers) -> Intensity {
        sizes.first { $0.name == answers[intensityKey]?.choice } ?? sizes[0]
    }

    /// What Boop says, `say`'s options: nothing, a feeling, a swear, or
    /// what NOW is about.
    public static var says: [Option] { says(of: CharacterPack.active.name) }
    static func says(of name: String) -> [Option] {
        [Option("none", "Nothing: the face in silence. The routine (a plain prompt, a quick finish) where PERSONALITY's Examples say \"in silence\", a prompt soon after another reaction, and wherever TALK asks for silence.",
                notFor: "Anything PERSONALITY gives words to: what stands out, a failure, a poke."),
         Option("swear", "A swear, upset: a failed turn that really stings, in an irritated or grumpy face, as PERSONALITY's Examples swear.",
                notFor: "A win, a poke, words to \(name), or anything about the person.")]
            + feelings(of: name)
            + topics(of: name)
    }

    /// The moves a reaction can play in its face at an event, `react.move`'s
    /// options but for what you said: a turn's finish, judged from what NOW
    /// says, a wake-up when you come back from a long break, or a notice
    /// when your prompt says its name. No rule plays any of them, so the
    /// brain judges each one.
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

    /// The animation `react.move` picked at an event, or nil for none, a
    /// missing answer or one the device doesn't play.
    public static func animation(_ answers: Answers) -> String? {
        let pick = answers[moveKey]?.choice
        return animations.contains { $0.name == pick } ? pick : nil
    }

    /// The move `react.move` picked, at an event or of what you said, or
    /// nil for none.
    public static func move(_ answers: Answers) -> String? {
        if let a = animation(answers) { return a }
        guard let choice = answers[moveKey]?.choice, (replies + [unhush(of: CharacterPack.active.name)]).contains(where: { $0.name == choice })
        else { return nil }
        return reply(answers)
    }

    /// What the device plays for each of `animations`: the face's
    /// task_complete scene for a success or a failure, with that outcome,
    /// its reply_ready for a reply, its wake_up for a wake up, and its
    /// notice for a notice.
    public static let scenes: [String: (anim: String, outcome: String?)] = [
        "success": ("task_complete", "success"), "failure": ("task_complete", "failure"),
        "reply": ("reply_ready", nil), "wake up": ("wake_up", nil), "notice": ("notice", nil),
    ]

    /// A reaction still in progress this long after it started is ended as
    /// failed: past the longest reaction, held four times (`huge`) in the
    /// design with the longest loop. The longest hold of the longest design
    /// must end on the device before the link stops waiting for its
    /// `ended` (its `ttl` plus 60 s, linkkit/SPEC.md §5), or a reaction that
    /// played would read as failed: `testAReactionEndsBeforeTheHarnessCeiling`
    /// holds it so.
    public static let openForMs: Int64 = 90_000

    /// Below this, Jev is guessing, and silence beats a guessed meaning.
    public static let sayFloor = 0.35

    /// A question's pick: its answer if it isn't `none`, reaches the floor
    /// and is one of `options`, else nil.
    static func pick(_ answers: Answers, _ key: String, _ options: [Option]) -> String? {
        guard let a = answers[key], a.choice != "none", a.p >= sayFloor,
              options.contains(where: { $0.name == a.choice }) else { return nil }
        return a.choice
    }

    /// What Boop says, `say`'s pick when it reaches the floor, or nil for
    /// nothing.
    public static func saying(_ answers: Answers) -> String? { pick(answers, sayKey, says) }

    /// What Boop says, as the take to find: a feeling, a swear (an upset
    /// take, sworn), or a topic; nil for nothing.
    public static func said(_ answers: Answers) -> (part: Take.Part, meaning: String, swear: Bool)? {
        guard let pick = saying(answers) else { return nil }
        if pick == "swear" { return (.feeling, "upset", true) }
        return (feelings.contains { $0.name == pick } ? .feeling : .about, pick, false)
    }

    /// Its questions, and for a prompt's reading or what you said the
    /// sign's, when a caption fits it.
    public func questions(now: Event?, log: LogView) -> [Question] {
        let about = Self.about(now, log)
        let hushedNow = about.map { hushed($0.at) } ?? false
        if let about, Self.isTalk(about) {
            let asked = Self.speech(askedOfTalk, hushed: hushedNow, talk: talk(), in: pack)
            let captions = replyCaptions(about)
            guard !captions.isEmpty else { return asked }
            return asked + [Question(key: Signs.questionKey,
                                     text: "Which sign does \(pack.name) hold up with its reply? The one that answers what you said best, of those for the reply it makes. Your own words played back are the best of these, when they fit.",
                                     about: "the words NOW quotes", judgeBy: "what the person said and meant, then PERSONALITY and MOOD",
                                     options: [Option("facts", "With a status reply: the agents' facts, none of these.")]
                                         + captions.map { Option($0.text, "With \(Self.article($0.replies[0])) \($0.replies.joined(separator: " or ")) reply"
                                                                 + ($0.replies.contains("dunno") ? " (dunno, a huh to a question)." : ".")) })]
        }
        let asked = Self.speech(asked, hushed: hushedNow, talk: talk(), in: pack)
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

    /// The captions a reply to `said` may hold up, each once with the
    /// replies it's for: every reply's lines that fit the moment
    /// (`Signs.replies`), with what you said played back; `dunno`'s beside
    /// `huh`'s, `unhush`'s only while hushed, and none for `status`, whose
    /// sign is the agents' facts.
    func replyCaptions(_ said: Event) -> [(text: String, replies: [String])] {
        let tags = replyTags(said)
        let phrases = Signs.phrases(of: said["words"]?.string ?? "", name: pack.name)
        let names = Self.replies(of: pack.name).map(\.name).flatMap { $0 == "huh" ? ["huh", "dunno"] : [$0] }
            + (hushed(said.at) ? ["unhush"] : [])
        var out: [(text: String, replies: [String])] = []
        for reply in names where reply != "status" {
            for text in Signs.replies(replies, reply, calendar: tags, phrases: phrases, avoiding: lastReplySign) {
                if let i = out.firstIndex(where: { $0.text == text }) { out[i].replies.append(reply) } else { out.append((text, [reply])) }
            }
        }
        return out
    }

    /// The calendar's and the moment's tags a reply's sign may have at
    /// `said`: `working`, `waiting`, and `makeup` within `makeupMs` of an
    /// `ouch`, whatever came between, until a `love` makes up.
    func replyTags(_ said: Event) -> [String] {
        calendar(said) + moment(said) + (ouchAt.map { said.at - $0 < Self.makeupMs } == true ? ["makeup"] : [])
    }

    /// The questions asked: a character pack with no voice is never asked
    /// what to say (characters/CHARACTER.md §8), so it has no `say`.
    static func asked(in pack: CharacterPack) -> [Question] {
        Take.all(in: pack).isEmpty ? questions(in: pack).filter { $0.key != sayKey } : questions(in: pack)
    }

    /// `questions` as Boop may speak: while hushed, no `say` but to what
    /// you said, whose reply may be `unhush`, letting it talk (and else says
    /// nothing, `run`); on Quiet, `say` without the topics and the swear.
    static func speech(_ questions: [Question], hushed: Bool, talk: Talk, in pack: CharacterPack) -> [Question] {
        let talking = questions.contains { $0.key == moveKey && $0.options.contains { $0.name == "hush" } }
        return questions.compactMap { q in
            if q.key == sayKey {
                if hushed, !talking { return nil }
                guard talk == .quiet else { return q }
                let quiet = Set(topics(of: pack.name).map(\.name) + ["swear"])
                return Question(key: q.key, text: q.text, about: q.about, judgeBy: q.judgeBy, options: q.options.filter { !quiet.contains($0.name) })
            }
            if q.key == moveKey, hushed, q.options.contains(where: { $0.name == "hush" }) {
                return Question(key: q.key, text: q.text, about: q.about, judgeBy: q.judgeBy, options: q.options + [unhush(of: pack.name)])
            }
            return q
        }
    }

    /// The questions asked of what you said, from `asked`: the same four,
    /// but the face is never none, since what you said always gets one, the
    /// move is the reply, and it says something back more often than not.
    static func talkQuestions(_ asked: [Question], in pack: CharacterPack) -> [Question] {
        let name = pack.name
        return asked.map { q in
            switch q.key {
            case faceKey:
                return Question(key: q.key, text: "Which face does \(name) make at what you said? It always makes one.", about: q.about,
                                judgeBy: q.judgeBy, options: q.options.filter { $0.name != "none" })
            case moveKey:
                return Question(key: q.key, text: "What does \(name) reply to what you said? It answers what you meant with its body and a sign, never with words of its own.",
                                about: "the words NOW quotes", judgeBy: "what the person meant, then PERSONALITY's Examples and MOOD",
                                options: replies(of: name))
            case sayKey:
                return Question(key: q.key, text: "What does \(name) say back as it replies, in its face's mood? Talked to, it mostly says something, a sound at least; now and then nothing.",
                                about: "the words NOW quotes", judgeBy: q.judgeBy,
                                options: q.options.map { $0.name == "none" ? talkSilence(of: name) : $0 })
            default: return q
            }
        }
    }

    /// `say`'s nothing for what you said: now and then, never the rule.
    static func talkSilence(of name: String) -> Option {
        Option("none", "Nothing: the reply and its sign answer alone, where PERSONALITY's Example for words like these is in silence, or TALK asks for silence.",
               notFor: "A greeting, praise, affection, a joke, rudeness or a question to \(name) itself, which get a sound at least.")
    }

    /// What a reply says when it has no words of its own in the face and
    /// `say` picked no feeling: a feeling it borrows, which Voice has takes
    /// of. A reply with none (huh, comfort, notme) says nothing then: never
    /// a topic, which is the agents' work, not what you said.
    static let replyWords: [String: String] = [
        "yes": "glad", "no": "upset", "bye": "glad", "thanks": "glad", "love": "glad", "ouch": "upset",
        "hehe": "tickled", "dance": "tickled", "unhush": "glad",
    ]

    /// The feeling the reply borrows (`replyWords`) when `say` leaned to
    /// words without picking a feeling past the floor; nil when it leaned
    /// to nothing.
    static func leaned(_ reply: String, _ answers: Answers) -> String? {
        guard let a = answers[sayKey], a.choice != "none" else { return nil }
        return replyWords[reply]
    }

    /// Every question, for `pack`'s character: the face, the move, how big
    /// and what it says.
    static func questions(in pack: CharacterPack = .active) -> [Question] {
        let name = pack.name
        let byBoth = "the PERSONALITY and MOOD sections, PERSONALITY's Examples first"
        // What it says is TALK's to steer first, when the pack has one.
        let byTalk = "TALK first, if there is one, over everything else on how much \(name) says; then PERSONALITY's Examples, then MOOD"
        return [
            Question(key: faceKey, text: "How should \(name) react to NOW, if at all? It makes this mood's face for a moment, with its move, and may say something.",
                     about: "the NOW section", judgeBy: byBoth,
                     options: [Option("none", "Stay quiet: nothing in NOW is worth a face, "
                                          + "or HISTORY shows \(name) still making the one it calls for, about the same thing (in progress).",
                                      notFor: "Something new said to \(name), which always gets a face of its own, even while one plays; "
                                          + "a turn that finished done or failed, which always gets a face and its finish; "
                                          + "or anything PERSONALITY's Examples react to that \(name) isn't already doing.")]
                         + pack.faces),
            Question(key: moveKey, text: "If \(name) reacts, does its body make a move: a turn that finished, and how it ended, you back after a long break, or your prompt saying \(name)'s name?",
                     about: "the NOW section", judgeBy: "NOW's line, and what it says the agent's last message said",
                     options: [Option("none", "Just the face: NOW's line isn't a turn that finished done or failed, you back after a long break, or a prompt that says \(name)'s name. A turn starting, a prompt that doesn't say its name, a check passing or failing (tests, a build, a deploy), a poke, a check-in, a short break and a stopped turn all get none.")]
                         + ReactOutput.animations(of: name)),
            Question(key: intensityKey, text: "If \(name) reacts, how big is the moment? The bigger, the longer it holds the face and the more it says.",
                     about: "the NOW section", judgeBy: byBoth, options: ReactOutput.intensities),
            Question(key: sayKey, text: "If \(name) reacts, what does it say, in its face's mood: nothing, as the routine often gets, how it feels, or what NOW is about?",
                     about: "the NOW section", judgeBy: byTalk, options: ReactOutput.says(of: name)),
        ]
    }

    public func run(_ answers: Answers, now: Event?, log: LogView) -> OutputResult? {
        // 1. Does Jev want a reaction at all, and with which face?
        guard let choice = answers[Self.faceKey]?.choice, pack.faces.contains(where: { $0.name == choice }) else {
            return nil
        }
        // 2. This output's own rules.
        if let why = blocked() { return .failed(why) }
        // 3. The effect: the face, its move, held as long as the moment is
        // big, and the `say`, if Voice has a take of what it says, as big,
        // in this face's mood. To what you said, the move is the reply.
        let about = Self.about(now, log)
        let talk = Self.isTalk(about)
        let reply = talk ? Self.played(Self.reply(answers), words: about?["words"]?.string ?? "") : nil
        let size = Self.intensity(answers)
        let pick = talk ? nil : Self.animation(answers)
        let at = about?.at ?? 0
        // What it says: nothing while hushed, unless this is you letting it
        // talk; on Quiet, nothing at a small moment or a finish.
        let silent = (hushed(at) && reply != "unhush") || (self.talk() == .quiet && (size.name == "small" || pick != nil))
        // To what you said, with no words of the reply's own in this face, a
        // feeling `say` picked, else the one the reply borrows; never a topic.
        var saying = Self.said(answers)
        if let reply {
            if saying?.part == .about { saying = nil }
            if saying == nil, let own = Self.leaned(reply, answers) { saying = (.feeling, own, false) }
        }
        // To what you said, `say` says whether and the reply says what: its
        // own words, in this face, when `say` answered anything but none.
        var said: [Take] = []
        if speaks(), !silent {
            if let reply, let a = answers[Self.sayKey], a.choice != "none",
               let own = Voice.take(.reply, meaning: reply, kind: size.kind, face: choice, finish: nil, avoiding: lastWords,
                                    in: pack, rng: &takes) {
                said = [own]
            } else {
                said = saying.flatMap {
                    Voice.take($0.part, meaning: $0.meaning, kind: $0.swear ? .swear : size.kind, face: choice, finish: pick,
                              avoiding: lastWords, in: pack, rng: &takes)
                }.map { [$0] } ?? []
            }
        }
        // A word may get a sound of the same before it, but not at a small
        // moment, nor on Quiet.
        if let word = said.first, size.name != "small", self.talk() != .quiet,
           let lead = Voice.lead(before: word, face: choice, finish: pick, avoiding: lastWords, in: pack, rng: &takes) {
            said.insert(lead, at: 0)
        }
        if !said.isEmpty { lastWords = Set(said.map(\.text)) }
        let say = DeviceReaction.Say(takes: said)
        let sign: String?
        var show: String?
        if let reply, let about {
            (sign, show) = replySign(reply, about, answers)
        } else {
            let picked = answers[Signs.questionKey]?.choice
            sign = picked.flatMap { offered(now, log).contains($0) ? $0 : nil }
        }
        var reaction = DeviceReaction(say: say, mood: choice, loops: size.loops, sign: sign)
        reaction.reply = reply
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
        // Hushed for as long as the moment is big, or let talk again.
        if reply == "hush" { hush(Core.hushMsBySize[Self.sizes.firstIndex(of: size) ?? 1], at) }
        if reply == "unhush" { hush(nil, at) }
        // 4. What it started, as its line in HISTORY: in progress until
        // the device says how the reaction ended.
        let face = "\(Self.article(choice)) \(choice) face (\(size.name))"
        let did = pick.map { "\(pack.name) played \(Self.article($0)) \($0) in \(face)" }
            ?? "\(pack.name) made \(face)" + (reply.map { ", replying \($0)" } ?? "")
        // The takes' ids in order, and the reply as it played, for the
        // tools to say what it did.
        let held: String = (sign.map { ", holding up a sign: \"\($0)\"" } ?? "")
            + (show == StatusReply.drawer ? " and showing every agent" : "")
        let spoke: String = say.text.map { ", and said \"\($0)\"." } ?? "."
        var facts: [String: JSONValue] = ["takes": .array(said.map { .string($0.id) })]
        if let reply { facts["reply"] = .string(reply) }
        return .started(did + held + spoke, pending, facts: facts)
    }

    /// What a reply holds up about `said`, what you said, and where the
    /// board shows the rest: for `status` the agents' facts, else of the
    /// reply's captions (`replyCaptions`) the one the brain likes best;
    /// with no brain's pick among them, one of the pack's lines for it at
    /// random, never your words.
    func replySign(_ reply: String, _ said: Event, _ answers: Answers) -> (sign: String?, show: String?) {
        let tags = replyTags(said)
        let mine = reply == "status" ? [] : replyCaptions(said).filter { $0.replies.contains(reply) }.map(\.text)
        if reply == "ouch" { ouchAt = said.at } else if reply == "love" { ouchAt = nil }
        let answer = reply == "status" ? status(said) : nil
        let p = answers[Signs.questionKey]?.probabilities ?? [:]
        let liked = mine.filter { (p[$0] ?? 0) > 0 }.max { p[$0]! < p[$1]! }
        let sign = reply == "status" ? answer?.sign
            : liked ?? Signs.reply(replies, reply, calendar: tags, avoiding: lastReplySign, rng: &takes)
        if sign != nil { lastReplySign = sign }
        return (sign, answer?.show)
    }
}
