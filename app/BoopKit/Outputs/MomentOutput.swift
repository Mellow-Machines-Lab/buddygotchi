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
public final class MomentOutput: Output {
    public static let outputName = "react"
    public let name = MomentOutput.outputName
    /// Whose reactions: its character, and the buddy's voice when there
    /// are several.
    let pack: CharacterPack
    public let voice: String?
    /// The questions' keys.
    public static let emotionKey = "react.face", moveKey = "react.move", sizeKey = "react.intensity", sayKey = "say"
    /// Its questions, built once: none of them changes. What you said gets
    /// its own moves (`talkQuestions`).
    let asked: [Question]
    let askedOfTalk: [Question]
    /// Sends a brain reaction, which waits in the device's queue behind
    /// whatever is playing, with the handle to end once the device says how
    /// it ended, or once it never will.
    let queue: (Moment, Pending) -> Void
    /// Why a reaction can't play now (something needs you), or nil.
    let blocked: () -> String?
    /// Why a reply to what you said can't play now, or nil: it shows over
    /// needs you, as listening does. `blocked`'s when not given.
    let replyBlocked: (() -> String?)?
    /// The agent and thread the event the brain answers is about, or nil
    /// (a poke, an idle check-in): a finish, or a face for a finished
    /// turn, names it on the device.
    let who: (Event?) -> Moment.Who?
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
    /// Why it reacts to the event the brain answered, in plain words
    /// (`Narration`), or nil: its fact goes to the board's lane, and its
    /// sentence to the transcript.
    let reason: (Event?) -> Narration?
    /// The board's caption for a mood this pass really moved, or nil
    /// (`MoodOutput.boardFact`): used when the reason has no fact of its own.
    let moodMoved: (Event?, LogView) -> String?
    /// A caption with no Moment, for that mood when the pass plays nothing.
    let note: (String, Int64) -> Void
    /// The line Jev read for an event, whose facts say what it was to the
    /// view (`told`, `firstToday`, `fixed`).
    let line: (Event) -> Line?
    /// The pack's dream signs (`dreams.md`), and the tags of the dream an
    /// event's line tells, or nil when it tells none: the telling holds up
    /// one of the signs those tags fit.
    let dreams: [TaggedLine]
    func told(_ e: Event) -> [String]? {
        guard case .array(let tags)? = line(e)?.facts["dream_tags"] else { return nil }
        return tags.compactMap(\.string)
    }
    /// Whether an event is the first time you show up today, and the sign
    /// for today's occasion, once, if it hasn't been shown: code's, whatever
    /// the brain picks of feeling and words.
    func firstToday(_ e: Event) -> Bool { line(e)?.facts[TranscriptView.firstTodayFact] != nil }
    let occasion: (Int64) -> String?
    /// The pack's asks (`asks.md`), and those of its questions it may ask
    /// at an event, by the moment and the caps (`Asks.askable`).
    let asks: [TaggedLine]
    let askable: (Event, LogView, [Asks.Question]) -> [Asks.Question]
    /// The wishes it may make at an event, at an ask's moment and within
    /// the core's caps; and making one, when its sign is picked.
    let wishable: (Event, LogView) -> [Core.WishKind]
    let makeWish: (Core.WishKind, Int64) -> Void
    /// Whether you've met a kind of wish once: until then its sign shows how.
    let wishDone: (Core.WishKind) -> Bool
    /// The face of its mood now, for something held up with no face.
    let moodFace: (LogView) -> String?
    /// The Boop day's number at a time, which picks among a wish's signs.
    let dayNumber: (Int64) -> Int
    /// What Boop may bring up about you at a time (`Memory.felt`).
    let felt: (Int64) -> [Memory.Felt]
    /// What it noticed that's due at an event (`Notices.due`), if it may
    /// make a Moment of it there: only ever at an idle check-in.
    let notice: (Event, LogView) -> Notices.Notice?
    /// Why a wish made at a time fits (`Notices.wishReason`).
    let wishWhy: (Int64) -> String?
    /// The day so far, for the idle musings' blanks.
    let today: () -> MemoryReader.Tallies?
    /// Whether the turn an event finished got past a failed check: only
    /// then may Boop say a word that claims a fix (`CharacterPack.claimsAFix`).
    func fixed(_ e: Event) -> Bool { (line(e)?.facts["checks_failed"]?.int ?? 0) > 0 }

    /// Whether `e` is an idle check-in.
    static func isCheckIn(_ e: Event) -> Bool { e.type == .checkIn && e.specificType == "check_in" }

    /// Whether it held up a musing in the last `Signs.musingEveryMs`.
    static func mused(_ log: LogView, at now: Int64) -> Bool {
        log.events.contains { $0.kind == Event.did && $0.action == outputName && $0["musing"]?.bool == true && now - $0.at < Signs.musingEveryMs }
    }

    /// The questions it may ask at `about`, offered as signs: at the
    /// moments asks belong to (`Asks.moment`), never at the dream's
    /// telling.
    /// The wishes on offer at `about`, each with the pack's sign for it.
    func wishOptions(_ about: Event?, _ log: LogView) -> [(kind: Core.WishKind, sign: String)] {
        guard let about, !asks.isEmpty, told(about) == nil else { return [] }
        return wishable(about, log).compactMap { kind in Asks.wishSign(asks, kind, showsHow: !wishDone(kind), day: dayNumber(about.at)).map { (kind, $0) } }
    }

    /// The notes on offer at `about`: at an idle check-in, as the musings
    /// are, never on Quiet.
    func feltOptions(_ about: Event?) -> [Memory.Felt] {
        guard let about, Self.isCheckIn(about), talk() != .quiet, !hushed(about.at) else { return [] }
        return felt(about.at)
    }

    /// The sign question's answer for a notice with no sign: only its look
    /// and its reason. `waiting` has none.
    public static let noticeLook = "a look"

    /// A notice's options: `waiting`, being of use to you, its sign alone,
    /// and any other mostly the look, its sign now and then.
    static func noticeOptions(_ noticing: (notice: Notices.Notice, lines: [String])?) -> [Option] {
        guard let noticing else { return [] }
        if noticing.notice.kind == .waiting { return noticing.lines.map { Option($0, "CONTEXT's Noticed, said on a sign: usually this.") } }
        return noticing.lines.map { Option($0, "CONTEXT's Noticed, said on a sign, now and then.") }
            + [Option(noticeLook, "CONTEXT's Noticed, no sign: it looks up at you. Usually this.")]
    }

    /// What it may hold up for a notice at `about`: only at an idle check-in.
    func noticeOptions(_ about: Event?, _ log: LogView) -> (notice: Notices.Notice, lines: [String])? {
        guard let about, Self.isCheckIn(about), let n = notice(about, log) else { return nil }
        let lines = Signs.notice(signs, n.kind.rawValue, agent: n.agent, avoiding: lastSign)
        return lines.isEmpty ? nil : (n, lines)
    }

    func askOptions(_ about: Event?, _ log: LogView) -> [Asks.Question] {
        guard let about, !asks.isEmpty, told(about) == nil else { return [] }
        return askable(about, log, Asks.questions(asks))
    }

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
    /// Boop goes to sleep now, at your lock at night (`Core.nap`).
    let nap: (Int64) -> Void
    /// How much it says, chosen in Settings: on Quiet, `say` offers no
    /// topic and no swear, and a small moment or a finish says nothing.
    let talk: () -> Talk
    /// Picks among the takes that fit, and remembers the last
    /// `recentSays` says' words, the newest first, which aren't said again
    /// while another fits: a quiet face has few takes, and "Cozy" three
    /// check-ins of five read as a loop. The seed is the caller's: a launch's
    /// is its own (`Runtime.Mind`), so no two launches say the same order,
    /// and the words said before a launch are read back from the log.
    var takes: SplitMix64
    var recentWords: [[String]] = []
    var lastWords: [String] { recentWords.reversed().flatMap { $0 } }
    public static let recentSays = 12
    /// The last sign it held up, of any kind, which the next doesn't hold up
    /// again while another fits, and when the last `ouch` not yet made up was.
    var lastSign: String?
    var ouchAt: Int64?
    /// Whether it has read back what it said before this launch.
    var recalled = false

    /// Reads back what it said and held up last, before this launch.
    func recall(_ log: LogView) {
        guard !recalled else { return }
        recalled = true
        let mine = log.events.filter { $0.kind == Event.did && $0.action == Self.outputName && $0["voice"]?.string == voice }
        let texts = Dictionary(Take.all(in: pack).map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        recentWords = mine.compactMap { d in
            let said = d["takes"]?.array?.compactMap(\.string).compactMap { texts[$0] } ?? []
            return said.isEmpty ? nil : said
        }.suffix(Self.recentSays) + recentWords
        lastSign = lastSign ?? mine.last { $0["sign"] != nil }?["sign"]?.string
    }

    /// With a `voice`, a buddy's: its picks are its own, so two buddies
    /// don't say the same words.
    public init(queue: @escaping (Moment, Pending) -> Void, blocked: @escaping () -> String?,
                replyBlocked: (() -> String?)? = nil, who: @escaping (Event?) -> Moment.Who? = { _ in nil },
                turnMs: @escaping (Event?) -> Int64? = { _ in nil }, speaks: @escaping () -> Bool = { true },
                pack: CharacterPack = .active, voice: String? = nil, signs: [TaggedLine] = [],
                calendar: @escaping (Event) -> [String] = { _ in [] }, replies: [TaggedLine] = [],
                status: @escaping (Event) -> StatusReply.Answer? = { _ in nil }, moment: @escaping (Event) -> [String] = { _ in [] },
                hushed: @escaping (Int64) -> Bool = { _ in false }, hush: @escaping (_ ms: Int64?, _ at: Int64) -> Void = { _, _ in },
                nap: @escaping (Int64) -> Void = { _ in },
                talk: @escaping () -> Talk = { .default }, reason: @escaping (Event?) -> Narration? = { _ in nil },
                moodMoved: @escaping (Event?, LogView) -> String? = { _, _ in nil }, note: @escaping (String, Int64) -> Void = { _, _ in },
                dreams: [TaggedLine] = [], line: @escaping (Event) -> Line? = { _ in nil },
                occasion: @escaping (Int64) -> String? = { _ in nil },
                asks: [TaggedLine] = [],
                askable: @escaping (Event, LogView, [Asks.Question]) -> [Asks.Question] = { _, _, _ in [] },
                wishable: @escaping (Event, LogView) -> [Core.WishKind] = { _, _ in [] },
                makeWish: @escaping (Core.WishKind, Int64) -> Void = { _, _ in },
                wishDone: @escaping (Core.WishKind) -> Bool = { _ in false },
                dayNumber: @escaping (Int64) -> Int = { _ in 0 },
                moodFace: @escaping (LogView) -> String? = { _ in nil },
                today: @escaping () -> MemoryReader.Tallies? = { nil },
                felt: @escaping (Int64) -> [Memory.Felt] = { _ in [] },
                notice: @escaping (Event, LogView) -> Notices.Notice? = { _, _ in nil },
                wishWhy: @escaping (Int64) -> String? = { _ in nil }, seed: UInt64 = 0x7A4E) {
        self.today = today
        self.felt = felt
        self.notice = notice
        self.dayNumber = dayNumber
        self.moodFace = moodFace
        self.wishWhy = wishWhy
        let own = voice.map(SplitMix64.seed(of:)) ?? 0
        takes = SplitMix64(seed: seed ^ own)
        self.pack = pack
        self.voice = voice
        asked = Self.asked(in: pack)
        askedOfTalk = Self.talkQuestions(Self.asked(in: pack), in: pack)
        self.queue = queue
        self.blocked = blocked
        self.replyBlocked = replyBlocked
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
        self.nap = nap
        self.talk = talk
        self.reason = reason
        self.moodMoved = moodMoved
        self.note = note
        self.dreams = dreams
        self.line = line
        self.occasion = occasion
        self.asks = asks
        self.askable = askable
        self.wishable = wishable
        self.makeWish = makeWish
        self.wishDone = wishDone
    }

    static func article(_ word: String) -> String { "aeiou".contains(word.first ?? "x") ? "an" : "a" }

    /// How Boop can feel about NOW, the first of what `say` offers. Every
    /// feeling take has one, and every face has takes of each: tests check
    /// both. A pack's `say` offers those its voice has takes of: `shaken`
    /// is newer than some packs' copies of the voice.
    public static var feelings: [Option] { feelings(of: CharacterPack.active.name) }
    static func feelings(in pack: CharacterPack) -> [Option] {
        let has = Set(Take.all(in: pack).filter { $0.part == .feeling }.map(\.meaning))
        return feelings(of: pack.name).filter { has.contains($0.name) }
    }
    static func feelings(of name: String) -> [Option] { [
        Option("upset", "Something went wrong or let \(name) down: a check or a turn failing, the agent stuck or giving up, a rude prompt."),
        Option("glad", "Something went right: a turn done and working, a check passing, a big win, a kind prompt.", notFor: "A failure."),
        Option("tickled", "Playful words: poked or teased with MOOD at ease, a poke, a tap, or a playful prompt."),
        Option("shaken", "Had enough: shaken, again and again, the desk thumped, or poked with MOOD annoyed, irritated or grumpy."),
    ] }

    /// What NOW can be about, the rest of what `say` offers: each a topic
    /// NOW's line shows. Every topic take has one, and every face has takes
    /// of each, as for `feelings`.
    public static var topics: [Option] { topics(of: CharacterPack.active.name) }
    static func topics(of name: String) -> [Option] { [
        Option("start", "A turn starting, or a push going off: off it goes."),
        Option("helpers", "The agent starting a subagent: helpers sent off."),
        Option("helper back", "A subagent finishing: a helper back with its report."),
        Option("retry", "The same thing again: a retry, a check run again after failing, or the person saying it's still broken."),
        Option("work", "Work going on: edits, steady progress, a long or hard turn."),
        Option("tests", "Tests: running, failing or passing."),
        Option("command", "A command or a build running in the terminal."),
        Option("tool", "A tool: the web, an MCP tool, something fetched or looked up."),
        Option("looking", "Searching or reading: the agent looking through files, or something puzzling."),
        Option("planning", "Planning: the agent in plan mode, or thinking before it acts."),
        Option("done", "A long turn finished, done and working."),
        Option("answer", "A turn that only answered something or asked something back."),
        Option("stopped", "A turn stopped: interrupted, or the agent giving up."),
        Option("waiting", "Waiting: a long command, or the agent waiting on something slow."),
        Option("quiet", "Content words, rarely: a long quiet at a check-in with MOOD calm, comfy or lazy."),
        Option("hello", "The person back at the Mac after a break, or greeting \(name): a hello."),
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
            Option("bye", "Bye: goodbye, good night, or you saying you're off for a while. It waves you off."),
            Option("thanks", "Thanks: something good: praise or thanks for \(name) or the work (\"good job\", \"nice one\"), your good news (\"we shipped it\"), or wishing you luck. It puffs up, proud."),
            Option("love", "Love: affection for \(name), or making up with it: \"I love you\", \"good boy\", \"you're cute\", \"sorry, \(name)\". It snuggles up."),
            Option("ouch", "Ouch: rude words or an insult to \(name). It flinches."),
            Option("comfort", "Comfort: you sound tired, sad or stressed, or tell it bad news. It leans in close."),
            Option("hehe", "Hehe: a joke, teasing or something silly. It giggles."),
            Option("status", "Status: a question about the agents or their work: done yet, how long, how many are running, what they're doing (\"what are you doing?\" too, asked of \(name) at its desk), anyone need me, how's the work going, did it work, how long you've been at it. It holds up the answer on a sign, from what it knows.",
                   notFor: "A question about \(name) itself, which is yes, no or huh; a greeting, which is hello."),
            Option("nap", "Nap: asked to sleep or rest: \"go to sleep\", \"nap time\". It yawns and settles down for a nap."),
            Option("hush", "Hush: asked to stop talking: \"shh\", \"be quiet\", \"shut up\", \"stop talking\". It zips its lips and says nothing for a while, as long as the moment is big: 15 min small, 30 medium, an hour big, two hours huge.",
                   notFor: "Asked to go to sleep or take a nap, which is nap, even at night; rude words that aren't asking for quiet, which is ouch."),
            Option("dance", "Dance: asked to dance or wiggle. It dances."),
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

    /// `react.move`'s answer at your lock or unlock for a wave, and the board's
    /// reply for one that's small: a slighter motion than `bye` or `hello`,
    /// the pack's `reply-wave` clip.
    public static let wave = "wave"

    /// What it plays at any other notice: it looks up at you.
    public static let noticeScene = "notice"

    /// What it plays at a rough hour's notice: it leans in close.
    public static let roughReply = "comfort"

    /// The clip it plays bringing up what it remembers: the pack's
    /// `reply-remember`.
    public static let rememberClip = "remember"

    /// The questions at your lock or unlock, from `asked`: a face always, as
    /// you did something it answers; the move is a wave or none, and at a
    /// lock at night (`mayNap`) the nap.
    static func lockQuestions(_ asked: [Question], lock: Bool, mayNap: Bool, in pack: CharacterPack) -> [Question] {
        let name = pack.name
        return asked.map { q in
            switch q.key {
            case emotionKey:
                return Question(key: q.key, text: "Which emotion does \(name) show as you \(lock ? "lock" : "unlock") the Mac? It always shows one.",
                                about: q.about, judgeBy: q.judgeBy, options: q.options.filter { $0.name != "none" })
            case moveKey:
                return Question(key: q.key, text: "Does \(name) wave as you \(lock ? "lock" : "unlock") the Mac? The wave is as big as the moment.",
                                about: "the NOW section", judgeBy: "PERSONALITY and MOOD",
                                options: [Option("none", "No wave: MOOD is grumpy, irritated or annoyed, so \(name) is cross with you, and turns away or huffs."),
                                          Option(wave, lock ? "MOOD isn't cross: it waves you off, slight when the moment is small." : "MOOD isn't cross: it waves hello, slight when the moment is small.")]
                                    + (mayNap ? [Option("nap", "It says good night and falls asleep at once, until you're back.")] : []))
            case sayKey:
                // Any answer but none says the wave's own word; these say so.
                return Question(key: q.key, text: "What does \(name) say aloud \(lock ? "as you go" : "as you're back"), in the emotion it shows?",
                                about: q.about, judgeBy: q.judgeBy,
                                options: q.options.map { o in
                                    switch o.name {
                                    case "none": Option("none", "Nothing: a routine lock or unlock, the wave in silence, MOOD grumpy, irritated or annoyed, or wherever CONTEXT's Talk row asks for silence.")
                                    case "hello": Option("hello", lock ? "MOOD isn't cross: a word for your going, goodbye or good night." : "MOOD isn't cross: a word for your being back, hello.")
                                    default: o
                                    }
                                })
            default: return q
            }
        }
    }

    /// Whether `about`, your lock, may put Boop to sleep: at night, with no
    /// agent working for it to watch.
    func mayNap(_ about: Event) -> Bool {
        about.phase == .start && calendar(about).contains("night") && !moment(about).contains("working")
    }

    /// What a move at your lock or unlock is, as a reply's lines and words
    /// know it: `bye`, `hello` or `nap`; nil at any other event, or for no
    /// wave.
    static func waved(_ answers: Answers, about: Event?, size: Size) -> Reply? {
        guard let about, about.type == .lock else { return nil }
        switch answers[moveKey]?.choice {
        case wave?:
            let word = about.phase == .start ? "bye" : "hello"
            return Reply(word: word, played: size.name == "small" ? wave : word, did: ", waving")
        case "nap"? where about.phase == .start:
            return Reply(word: "nap", played: "nap", did: ", going to sleep", naps: true)
        default: return nil
        }
    }

    /// A move as a reply: to what you said, or at your lock or unlock.
    struct Reply {
        /// Its name, which picks its lines and words.
        var word: String
        /// What the board plays: a small wave is the slighter motion; the
        /// nap and what you said are as they are.
        var played: String
        /// How HISTORY's line says it.
        var did: String
        /// Whether Boop goes for its nap.
        var naps = false
    }

    /// How long after an `ouch` a reply is making up (`makeup`, a tag its
    /// sign may have).
    public static let makeupMs: Int64 = 10 * 60_000
    /// The moment's tags a reply's sign may have, beside the calendar's:
    /// `nobrain` is the shrug's with no brain to answer (`Core.shrug`).
    public static let momentTags = ["working", "waiting", "makeup", Core.noBrain]

    /// Whether `e` is something you said on push-to-talk, which a reply
    /// answers.
    static func isTalk(_ e: Event?) -> Bool { e?.type == .said }

    /// What a pass is about: its event, or for one forced from outside
    /// (a demo's), the latest that happened, but for push-to-talk's own
    /// listening after what you said, and the harness's.
    static func about(_ now: Event?, _ log: LogView) -> Event? {
        now ?? log.events.last { !$0.fromHarness && $0.type != .listen }
    }

    /// How big a moment is, the smallest first: how long the face holds,
    /// a loop more each step, and how big what it says is (`Size`).
    public static let sizeOptions = [
        Option("small", "A small moment: the usual. The face holds once, and what it says is a sound."),
        Option("medium", "A moment that stands out. It holds twice, and says a word."),
        Option("big", "A big moment, such as a long turn's hard-won work done or the top of a streak. It holds three times, and says a phrase."),
        Option("huge", "The biggest moments: a very long turn that failed, a hard-won finish (a long turn done after failed checks), or a long turn that failed after failed checks or turns before it. It holds four times, and says a phrase.",
               notFor: "A check failing mid-turn, or a finish when HISTORY shows the reaction to its fix just now: that's small."),
    ]

    /// What an intensity sets: how many loops the face holds and the kind
    /// of take it says.
    public struct Size: Equatable, Sendable {
        public let name: String
        public let loops: Int
        public let kind: Take.Kind
    }

    /// Each intensity, in `sizeOptions`' order: once a sound, twice a
    /// word, three and four times a phrase.
    public static let sizes: [Size] = zip(sizeOptions, [(1, Take.Kind.sound), (2, .word), (3, .phrase), (4, .phrase)])
        .map { Size(name: $0.name, loops: $1.0, kind: $1.1) }

    /// The intensity `react.intensity` picked, or small when it's missing.
    public static func size(_ answers: Answers) -> Size {
        sizes.first { $0.name == answers[sizeKey]?.choice } ?? sizes[0]
    }

    /// What Boop says, `say`'s options: nothing, a feeling, a swear, or
    /// what NOW is about.
    public static var says: [Option] { says(in: .active) }
    static func says(in pack: CharacterPack) -> [Option] {
        let name = pack.name
        return
        [Option("none", "Nothing: the face in silence. The routine (a plain prompt, a quick finish, a check-in where nothing has happened), a prompt soon after another reaction, its wish \"waiting 1 h\" or more, and wherever CONTEXT's Talk row asks for silence."),
         Option("swear", "A swear, upset: a failed turn that really stings, in an irritated or grumpy face.",
                notFor: "A win, a poke, words to \(name), or anything about the person.")]
            + feelings(in: pack)
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
               notFor: "A check that passed while the turn goes on, a turn that finished failed, one saying it couldn't finish, or one asking you something, only answering or only fawning with no tool calls."),
        Option("failure", "NOW's line says a turn finished, failed; or finished done, but saying it couldn't finish.",
               notFor: "A check that failed while the turn goes on, or a turn that finished done, saying it's done."),
        Option("reply", "NOW's line says a turn finished, done, asking you something, only answering or only fawning, often with no tool calls: no task finished.",
               notFor: "Work done, a turn that finished failed, or anything but a turn that finished."),
        Option("wake up", "NOW's line says you came back to the Mac after an hour or more away. \(name) stretches, yawns and wakes up for you."),
        Option("notice", "NOW's line says you said \(name)'s name in your prompt: it looks up at you, as if it heard."),
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
        if answers[moveKey]?.choice == wave { return wave }
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
        // Growing always gets a moment, and what it holds up says what grew.
        if let about, about.type == .grew {
            let asked = Self.speech(asked, hushed: hushedNow, talk: talk(), in: pack).map { q in
                q.key == Self.emotionKey ? Question(key: q.key, text: q.text, about: q.about, judgeBy: q.judgeBy,
                                                    options: q.options.filter { $0.name != "none" }) : q
            }
            let captions = offered(now, log)
            guard !captions.isEmpty else { return asked }
            return asked + [Question(key: Signs.questionKey,
                                     text: "\(pack.name) has just grown, as NOW says. Which sign does it hold up? The one that says best, as \(pack.name) would, what grew.",
                                     about: "what NOW says grew", judgeBy: "PERSONALITY and MOOD",
                                     options: captions.map { Option($0, "A sign that says this.") })]
        }
        if let about, about.type == .lock {
            let lock = about.phase == .start
            let asked = Self.speech(Self.lockQuestions(asked, lock: lock, mayNap: mayNap(about), in: pack), hushed: hushedNow, talk: talk(), in: pack)
            let captions = offered(now, log)
            guard !captions.isEmpty else { return asked }
            return asked + [Question(key: Signs.questionKey,
                                     text: "If \(pack.name) waves, does it hold up a sign as you \(lock ? "go" : "come back")? PERSONALITY says when.",
                                     about: "NOW and CONTEXT", judgeBy: "PERSONALITY and MOOD",
                                     options: [Option("none", "No sign: the wave alone, or no wave, with MOOD grumpy, irritated or annoyed.")] + captions.map { Option($0, "MOOD isn't cross: a sign that says this.") })]
        }
        let speech = Self.speech(asked, hushed: hushedNow, talk: talk(), in: pack)
        // A question it may ask, the sign being the ask; at an idle
        // check-in, a musing beside it.
        let questions = askOptions(about, log)
        let musings = about.map(Self.isCheckIn) == true ? offered(now, log) : []
        let wishes = wishOptions(about, log)
        let notes = feltOptions(about)
        let noticing = noticeOptions(about, log)
        if !questions.isEmpty || !musings.isEmpty || !wishes.isEmpty || !notes.isEmpty || noticing != nil {
            return speech + [Question(key: Signs.questionKey,
                                       text: "Does \(pack.name) hold up something: a question for you to answer with a tap (picking one asks it), a musing, something it remembers about you, \(noticing == nil ? "" : "something it noticed, ")or a wish? PERSONALITY says when; now and then, not every time."
                                           + (wishes.isEmpty ? "" : " With no wish yet today and half an hour or more of quiet, a wish fits best. Once CONTEXT says how today's wish ended, another doesn't fit."),
                                       about: "NOW, CONTEXT and HISTORY", judgeBy: "PERSONALITY and what fits the moment",
                                       // The caps are a ceiling, not a schedule: "none" on every level.
                                       options: [Option("none", "Nothing: \(pack.name) doesn't ask, muse or wish now.")]
                                           + musings.map { Option($0, "A musing to hold up, asking nothing.") }
                                           + notes.map { Option($0.line, "Something it remembers, from MEMORY: \($0.note)") }
                                           + wishes.map { w in
                                               Option(w.sign, "A wish: \(pack.name) wants \(w.kind.words) from you, and shows it until you give it.")
                                           }
                                           + Self.noticeOptions(noticing)
                                           + questions.map { q in
                                               Option(q.question, "Ask: \"\(q.question)\", \(q.a) or \(q.b)."
                                                   + (q.tags.isEmpty ? "" : " For a moment that's \(q.tags.joined(separator: ", ")).")
                                                   + (q.keeps ? " Its answer becomes part of \(pack.name)." : ""))
                                           })]
        }
        // How much it says, held in code at your prompt: Chatty always
        // makes a face; Quiet holds up a sign only for one that sounds like
        // something or says its name.
        let prompt = about.flatMap { $0.type == .prompt ? PromptReading(facts: $0.data) : nil }
        let asked = talk() == .chatty && prompt != nil ? speech.map { q in
            q.key == Self.emotionKey ? Question(key: q.key, text: q.text, about: q.about, judgeBy: q.judgeBy,
                                             options: q.options.filter { $0.name != "none" }) : q
        } : speech
        if talk() == .quiet, let prompt, prompt.named.isEmpty, prompt.tone == nil || prompt.tone == .calm { return asked }
        let captions = offered(now, log)
        guard !captions.isEmpty else { return asked }
        if let about, about.type == .ask {
            return asked + [Question(key: Signs.questionKey,
                                     text: "You answered \(pack.name)'s question, as NOW says. Which sign does it hold up back? The one for your answer, in \(pack.name)'s way.",
                                     about: "the answer NOW quotes", judgeBy: "the answer, then PERSONALITY and MOOD",
                                     options: [Option("none", "No sign: none of these fits.")]
                                         + captions.map { Option($0, "A sign for your answer.") })]
        }
        if let about, told(about) != nil {
            return asked + [Question(key: Signs.questionKey,
                                     text: "\(pack.name) tells its dream, under NOW's line. Which sign does it hold up? The one that fits what it dreamed of best, the person's part of it first.",
                                     about: "the dream NOW tells", judgeBy: "the dream, then PERSONALITY and MOOD",
                                     options: [Option("none", "No sign: none of these fits what it dreamed of.")]
                                         + captions.map { Option($0, "A sign for the dream.") })]
        }
        return asked + [Question(key: Signs.questionKey,
                                 text: "If \(pack.name) reacts, does it hold up a sign about your prompt, as PERSONALITY says? Your own words played back in \(pack.name)'s way are the best of these, when they fit the face.",
                                 about: "the NOW section and the words under it", judgeBy: "PERSONALITY and MOOD, how the person sounds, and CONTEXT's Talk row when it's there",
                                 // Chatty holds up a sign at every prompt.
                                 options: (talk() == .chatty ? [] : [Option("none", "No sign: PERSONALITY gives this prompt none, or nothing in it is worth holding up.")])
                                     + captions.map { Option($0, "A sign that says this.") })]
    }

    /// The captions a sign may show for `now`, if it's a prompt's reading;
    /// with no event (a pass forced from outside, such as a demo's), for
    /// a prompt's reading only when it's the latest thing that happened.
    func offered(_ now: Event?, _ log: LogView) -> [String] {
        guard let about = Self.about(now, log) else { return [] }
        // The line that tells the dream: a sign the dream's tags fit.
        recall(log)
        return Self.unrepeated(offering(about, log), last: lastSign)
    }

    /// `captions` without the last sign held up, while another fits.
    static func unrepeated(_ captions: [String], last: String?) -> [String] {
        captions.count > 1 ? captions.filter { $0 != last } : captions
    }

    func offering(_ about: Event, _ log: LogView) -> [String] {
        if let tags = told(about) { return Signs.dreams(dreams, tags: tags + calendar(about)) }
        // Growing: the lines for the stage it reached, and for any.
        if about.type == .grew { return Signs.grew(signs, stage: about.specificType) }
        // Your lock or unlock: the lines for its goodbye or hello, by the
        // moment: `bye working` while an agent works.
        if about.type == .lock {
            return Signs.replies(replies, about.phase == .start ? "bye" : "hello", calendar: replyTags(about), turns: today()?.turns ?? 0)
        }
        // An ask answered: what it holds up after that answer.
        if about.type == .ask, let q = about["q"]?.string, let answer = about["answer"]?.string {
            return Asks.followUps(asks, id: q, answer: answer)
        }
        // An idle check-in: a musing, at most once an hour, never on Quiet.
        if Self.isCheckIn(about) {
            guard talk() != .quiet, !Self.mused(log, at: about.at) else { return [] }
            let t = today()
            return Signs.musings(signs, tags: calendar(about), turns: t?.turns ?? 0, thread: t?.thread ?? "")
        }
        guard about.type == .prompt, let reading = PromptReading(facts: about.data) else { return [] }
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
            for text in Signs.replies(replies, reply, calendar: tags, phrases: phrases, avoiding: lastSign, turns: today()?.turns ?? 0) {
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
                // Chatty says something at every face.
                if talk == .chatty {
                    return Question(key: q.key, text: q.text, about: q.about, judgeBy: q.judgeBy, options: q.options.filter { $0.name != "none" })
                }
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
            case emotionKey:
                return Question(key: q.key, text: "Which emotion does \(name) show at what you said? It always shows one.", about: q.about,
                                judgeBy: q.judgeBy, options: q.options.filter { $0.name != "none" })
            case moveKey:
                return Question(key: q.key, text: "What does \(name) reply to what you said? It answers what you meant with its body and a sign, never with words of its own.",
                                about: "the words NOW quotes", judgeBy: "what the person meant, then PERSONALITY and MOOD",
                                options: replies(of: name))
            case sayKey:
                return Question(key: q.key, text: "What does \(name) say back aloud as it replies, in the emotion it shows? Talked to, it mostly says something, a sound at least; now and then nothing.",
                                about: "the words NOW quotes", judgeBy: q.judgeBy,
                                options: q.options.map { $0.name == "none" ? talkSilence(of: name) : $0 })
            default: return q
            }
        }
    }

    /// `say`'s nothing for what you said: now and then, never the rule.
    static func talkSilence(of name: String) -> Option {
        Option("none", "Nothing: the reply and its sign answer alone, now and then, or where CONTEXT's Talk row asks for silence.",
               notFor: "A greeting, praise, affection, a joke, rudeness or a question to \(name) itself, which get a sound at least.")
    }

    /// The one topic a reply may say: comfort's, rooting for another try.
    static let comfortTopic = "retry"

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
        let byBoth = "PERSONALITY and MOOD"
        // What it says is CONTEXT's Talk row's to steer first, when the setting isn't normal.
        let byTalk = "CONTEXT's Talk row first, when it's there, over everything else on how much \(name) says; then PERSONALITY and MOOD"
        return [
            Question(key: emotionKey, text: "How should \(name) react to NOW, if at all? A moment: it shows one emotion in this mood's way, with its move, and may say something.",
                     about: "the NOW section", judgeBy: byBoth,
                     options: [Option("none", "Stay quiet: most check-ins where nothing has happened; nothing in NOW is worth a moment, "
                                          + "or HISTORY shows \(name) still having the one it calls for, about the same thing (in progress).",
                                      notFor: "Something new said to \(name), which always gets a moment of its own, even while one plays; "
                                          + "a turn that finished done or failed, which always gets a moment and its finish; "
                                          + "or anything PERSONALITY reacts to that \(name) isn't already doing.")]
                         + pack.faces),
            Question(key: moveKey, text: "If \(name) reacts, does its body make a move: a turn that finished, and how it ended, you back after an hour or more away, or your prompt saying \(name)'s name?",
                     about: "the NOW section", judgeBy: "NOW's line, and what it says the agent's last message said",
                     options: [Option("none", "Just the face: NOW's line isn't a turn that finished done or failed, you back after an hour or more away, or a prompt that says \(name)'s name. A turn starting, a prompt that doesn't say its name, a check passing or failing (tests, a build, a deploy), a poke, a check-in, a short break and a stopped turn all get none.")]
                         + MomentOutput.animations(of: name)),
            Question(key: sizeKey, text: "If \(name) reacts, how big is the moment? The bigger, the longer it holds its emotion and the more it says.",
                     about: "the NOW section", judgeBy: byBoth, options: MomentOutput.sizeOptions),
            Question(key: sayKey, text: "If \(name) reacts, what does it say aloud, in the emotion it shows: nothing, as the routine often gets, how it feels, or what NOW is about?",
                     about: "the NOW section", judgeBy: byTalk, options: MomentOutput.says(in: pack)),
        ]
    }

    public func run(_ answers: Answers, now: Event?, log: LogView) -> OutputResult? {
        // 1. Does Jev want a reaction at all, and with which face? Something
        // held up at an idle check-in with no face takes the mood's, small.
        var answers = answers
        if answers[Self.emotionKey]?.choice == "none", let about = Self.about(now, log), Self.isCheckIn(about),
           let held = answers[Signs.questionKey]?.choice, held != "none", let face = moodFace(log) {
            answers[Self.emotionKey] = Answer(choice: face)
            answers[Self.sizeKey] = Answer(choice: Self.sizes[0].name)
        }
        guard let choice = answers[Self.emotionKey]?.choice, pack.faces.contains(where: { $0.name == choice }) else {
            // No Moment, but a mood that moved still says so.
            if let now, let moved = moodMoved(now, log) { note(moved, now.at) }
            return nil
        }
        // 2. This output's own rules: a reply to what you said shows over
        // needs you, nothing else does.
        let about = Self.about(now, log)
        let talk = Self.isTalk(about)
        if let why = (talk ? replyBlocked ?? blocked : blocked)() { return .failed(why) }
        // 3. The effect: the face, its move, held as long as the moment is
        // big, and the `say`, if Voice has a take of what it says, as big,
        // in this face's mood. To what you said, the move is the reply.
        let size = Self.size(answers)
        let replied: Reply?
        if talk {
            let word = Self.played(Self.reply(answers), words: about?["words"]?.string ?? "")
            replied = Reply(word: word, played: word, did: ", replying \(word)")
        } else {
            replied = Self.waved(answers, about: about, size: size)
        }
        let reply = replied?.word
        let moved = talk ? nil : Self.animation(answers)
        let at = about?.at ?? 0
        // What the brain held up, when it's for code to place.
        let holding = talk ? nil : (answers[Signs.questionKey]?.choice).flatMap { $0 == "none" ? nil : $0 }
        // A wish the brain picked, its sign being the wish.
        let wishing = holding.flatMap { c in wishOptions(about, log).first { $0.sign == c } }
        // Something it remembers, its line being the sign.
        let remembering = holding.flatMap { c in feltOptions(about).first { $0.line == c } }
        // Something it noticed, its line being the sign, or the look alone.
        // Late at night it stays gentle: no word with it.
        let noticing = holding.flatMap { c in
            noticeOptions(about, log).flatMap { o -> (notice: Notices.Notice, line: String?)? in
                c == Self.noticeLook && o.notice.kind != .waiting ? (o.notice, nil) : o.lines.contains(c) ? (o.notice, c) : nil
            }
        }
        // It looks up at you first, so it's no quiet face; a rough hour's
        // lean is its own look.
        let pick = noticing.map { $0.notice.kind == .rough ? nil : Self.noticeScene } ?? moved
        // What it says: nothing while hushed, unless this is you letting it
        // talk; on Quiet, nothing at a small moment or a finish, or with a
        // wish, which shows as its icon and sign.
        let silent = (hushed(at) && reply != "unhush")
            || (self.talk() == .quiet && (size.name == "small" || pick != nil || wishing != nil))
            || noticing?.notice.kind == .late
        // To what you said, with no words of the reply's own in this face, a
        // feeling `say` picked, else the one the reply borrows; never a
        // topic, but a comfort's "again": rooting for the retry when you
        // say it still doesn't work.
        var saying = Self.said(answers)
        if let reply {
            if saying?.part == .about, !(reply == "comfort" && saying?.meaning == Self.comfortTopic) { saying = nil }
            if saying == nil, let own = Self.leaned(reply, answers) { saying = (.feeling, own, false) }
        }
        // To what you said, `say` says whether and the reply says what: its
        // own words, in this face, when `say` answered anything but none.
        var said: [Take] = []
        recall(log)
        let never: Set<String> = about.map(fixed) == true ? [] : pack.claimsAFix
        if speaks(), !silent {
            if let reply, let a = answers[Self.sayKey], a.choice != "none",
               let own = Voice.take(.reply, meaning: reply, kind: size.kind, face: choice, finish: nil, avoiding: lastWords,
                                    never: never, in: pack, rng: &takes) {
                said = [own]
            } else {
                said = saying.flatMap {
                    Voice.take($0.part, meaning: $0.meaning, kind: $0.swear ? .swear : size.kind, face: choice, finish: pick,
                              avoiding: lastWords, never: never, in: pack, rng: &takes)
                }.map { [$0] } ?? []
            }
        }
        // Bringing up what it remembers, what it says is its own word.
        if remembering != nil, !said.isEmpty {
            said = pack.rememberWord.flatMap { Voice.word($0, face: choice, in: pack) }.map { [$0] } ?? []
        }
        // A word may get a sound of the same before it, but not at a small
        // moment, nor on Quiet.
        if let word = said.first, size.name != "small", self.talk() != .quiet, remembering == nil,
           let lead = Voice.lead(before: word, face: choice, finish: pick, avoiding: lastWords, in: pack, rng: &takes) {
            said.insert(lead, at: 0)
        }
        if !said.isEmpty { recentWords = Array((recentWords + [said.map(\.text)]).suffix(Self.recentSays)) }
        let say = Moment.Say(takes: said)
        var sign: String?
        var show: String?
        // Your first showing up today, or the telling: the day's greeting.
        let greeting = about.map { firstToday($0) || told($0) != nil } == true
        if talk, let reply, let about {
            (sign, show) = replySign(reply, about, answers)
            // The board opens no drawer over the needs-you screen: the
            // sign answers alone then.
            if blocked() != nil { show = nil }
        } else if about?.type == .lock, reply == nil {
            // A snub holds up nothing.
            sign = nil
        } else {
            let picked = answers[Signs.questionKey]?.choice
            sign = wishing?.sign ?? remembering?.line ?? noticing?.line ?? picked.flatMap { offered(now, log).contains($0) ? $0 : nil }
        }
        // A special day's sign is code's, over the brain's.
        if about.map(firstToday) == true, let day = occasion(at) { sign = day }
        var reaction = Moment(say: say, mood: choice, loops: size.loops, sign: sign)
        if let sign { lastSign = sign }
        // An ask: the question the brain held up, as the sign, its answers
        // as the lane's targets. It was offered when asked; the mood may
        // have moved since, so it isn't asked again.
        var asking: Asks.Question?
        if reply == nil, sign == nil, let picked = answers[Signs.questionKey]?.choice {
            asking = Asks.questions(asks).first { $0.question == picked }
            reaction.sign = asking?.question
            reaction.ask = asking
        }
        // A rough hour: it scoots close and leans.
        reaction.reply = replied?.played ?? (noticing?.notice.kind == .rough ? Self.roughReply : nil)
        reaction.show = show
        reaction.greeting = greeting
        if remembering != nil {
            reaction.low = true
            reaction.clip = Self.rememberClip
        }
        if let pick, let scene = Self.scenes[pick] {
            let (anim, outcome) = scene
            // Its scene and a finish's outcome, whose variation the device
            // picks: a turn's finish names whose turn it was, and says how
            // long it ran.
            reaction.anim = anim
            reaction.outcome = outcome
            // A notice isn't a turn's: it keeps its sign and reason.
            if noticing == nil { reaction.who = who(about) }
            if outcome != nil { reaction.turn = turnMs(about).map { Moment.turn(lengthMs: $0) } }
        } else if turnMs(about) != nil {
            // A face for a finished turn names it too: the device marks
            // the turn it's about while it plays.
            reaction.who = who(about)
        }
        // A finish that names its thread holds up nothing of the brain's:
        // the face holds up that name.
        if reaction.who != nil {
            reaction.sign = nil
            reaction.ask = nil
            asking = nil
        }
        // Why, for the person: the board shows the fact in its lane, unless
        // the strip already names the finished turn it's about.
        // Bringing up a note, the note is why, on the Mac: the board shows the line.
        let why = remembering.map { Narration(cause: Narration.remembers($0.note, name: pack.name)) }
            ?? noticing.map { Narration(cause: Narration.noticed($0.notice.fact), fact: $0.notice.short) }
            ?? wishing.map { Narration.wish($0.kind, name: pack.name, because: wishWhy(at)) } ?? reason(about)
        if reaction.who == nil, asking == nil, remembering == nil { reaction.reason = why?.fact ?? moodMoved(now, log) }
        let pending = Pending()
        queue(reaction, pending)
        // Hushed for as long as the moment is big, or let talk again.
        if reply == "hush" { hush(Core.hushMsBySize[Self.sizes.firstIndex(of: size) ?? 1], at) }
        if reply == "unhush" { hush(nil, at) }
        if replied?.naps == true { nap(at) }
        if let wishing { makeWish(wishing.kind, at) }
        // 4. What it started, as its line in HISTORY: in progress until
        // the device says how the reaction ended.
        let did = "\(pack.name) had \(Self.article(choice)) \(choice) moment (\(size.name))"
            + (pick.map { ", playing \(Self.article($0)) \($0)" }
                ?? replied?.did ?? "")
        // The takes' ids in order, and the reply as it played, for the
        // tools to say what it did.
        let held: String = (asking.map { ", asking \"\($0.question)\": \($0.a) or \($0.b)" }
            ?? sign.map { ", holding up a sign: \"\($0)\"" } ?? "")
            + (show == StatusReply.drawer ? " and showing every agent" : "")
        let spoke: String = say.text.map { ", and said \"\($0)\"." } ?? "."
        var facts: [String: JSONValue] = ["takes": .array(said.map { .string($0.id) })]
        if let reply { facts["reply"] = .string(reply) }
        if let sign { facts["sign"] = .string(sign) }
        if let why { facts["reason"] = .string(why.reaction(face: choice, name: pack.name)) }
        if asking == nil, wishing == nil, remembering == nil, noticing == nil, sign != nil, about.map(Self.isCheckIn) == true { facts["musing"] = true }
        if let noticing {
            facts["notice"] = .string(noticing.notice.kind.rawValue)
            facts["notice_key"] = .string(noticing.notice.key)
        }
        if let remembering { facts["felt"] = .string(remembering.line) }
        if let wishing { facts["wish"] = .string(wishing.kind.rawValue) }
        if let asking {
            facts["ask"] = .string(asking.id)
            facts["keeps"] = .bool(asking.keeps)
            facts["question"] = .string(asking.question)
            facts["answers"] = .array([.string(asking.a), .string(asking.b)])
        }
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
            : liked ?? Signs.reply(replies, reply, calendar: tags, avoiding: lastSign, rng: &takes)
        return (sign, answer?.show)
    }
}
