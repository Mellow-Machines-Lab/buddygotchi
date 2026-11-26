import Foundation
import MellowHarness

/// Whether Boop reacts to NOW, in one answer every pass: its face
/// (`react.face`); to what you said, its reply too (`react.reply`). What
/// its body does, how big the moment is and what it says are code's
/// (`MomentRule`, `Skits`). A reaction is a mood × a visual for a while:
/// the device draws that mood's design of whatever look is showing, or of
/// the move the rule picked (a turn's finish: task_complete for its
/// outcome, or reply_ready; wake_up, you back after a long break; notice,
/// its name in your prompt; or to what you said on push-to-talk, its
/// reply's clip), for as many loops as its size holds. It speaks only
/// where a rule says: at a skit (a long win, a failure, a fix, you back),
/// which the brain can't veto, a take of the skit's own; to what you said,
/// the reply's own words; at a lock's real wave, its hello's or bye's. Voice
/// finds a take as big as the moment, in the face's mood, or finds none,
/// and then the face plays in silence. A word at a medium moment or bigger
/// sometimes gets a sound of the same meaning
/// before it (`Voice.lead`). A reply's sign is one of the pack's lines for
/// it, which may play back your words, and a status reply's the agents'
/// facts, never guessed. At an idle check-in the one thing it may hold up
/// is dealt by code (`IdleBeat`), and the sign's question is only whether.
/// A skit's Moment plays the skit's clip as its face starts, if it has one.
/// After a skit it may invite one touch, on the last Moment it queues, as
/// the invite ledger allows (`invite(for:)`, `InviteLedger`). A skit
/// may carry a remark too, as text: how now differs from your usual
/// (`remark(for:about:facts:)`, `Remarks`). A Moment queued behind a
/// finish (the agent's line, or the remark) has its own record, right
/// after the finish's (`following`).
/// The Moments with no pass (your lock or unlock, a working check-in, a
/// boop from the world) are made here too, from the rule's picks (`ruled`,
/// `play`). It waits in the device's queue until
/// whatever plays there has finished. It's started, not done, until
/// whoever plays it ends its handle.
public final class MomentOutput: Output {
    public static let outputName = "react"
    public let name = MomentOutput.outputName
    /// Whose reactions: its character.
    let pack: CharacterPack
    /// The questions' keys.
    public static let emotionKey = "react.face", replyKey = "react.reply", takeKey = "skit.take"
    /// The most takes a skit's question offers.
    public static let takesOffered = 6
    /// Its questions, built once: none of them changes. What you said gets
    /// its reply's too (`talkQuestions`).
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
    /// What the event a moment is about earned, and for what: a finish
    /// shows it on its sign, a ship or a fix on a low sign of its own.
    public var earned: (Event?) -> (source: Growth.Source, xp: Int)? = { _ in nil }
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
    /// view (`hello`, `fixed`).
    let line: (Event) -> Line?
    /// The pack's dream signs (`dreams.md`): a hello that tells the dream
    /// holds up one of those its tags fit.
    let dreams: [TaggedLine]
    /// Your hello at an event, by its line (`MomentRule.hello`), or nil.
    func hello(_ e: Event, mood: String? = nil) -> MomentRule.Hello? {
        MomentRule.hello(e, facts: line(e)?.facts ?? [:], mood: mood)
    }
    /// The tags of the dream an event's hello tells, or nil when it tells none.
    func told(_ e: Event) -> [String]? {
        if case .telling(let tags)? = hello(e)?.extra { return tags }
        return nil
    }
    /// The pack's asks (`asks.md`), for an answered ask's follow-ups.
    let asks: [TaggedLine]
    /// The idle beat due at an event (`IdleBeat.due`), if any: the one
    /// thing it may hold up at an idle check-in; for a pass forced from
    /// outside, every one there is, due or not (`IdleBeat.every`). And
    /// making a wish, when the beat is one and it's held up.
    let idleBeat: (Event, LogView, _ forced: Bool) -> [IdleBeat.Candidate]
    let makeWish: (Core.WishKind, Int64) -> Void
    /// The face of its mood now, for something held up with no face.
    let moodFace: (LogView) -> String?
    /// Its lasting mood now, which the rules read (`MomentRule`).
    let moodID: (LogView) -> String?
    /// The day so far, for `{turns}` in a reply's line.
    let today: () -> MemoryReader.Tallies?
    /// Its lasting mood's level now (from 1; `MoodLevel`), for the face a
    /// skit plays in when the brain picked none.
    let moodLevel: (LogView) -> Int
    /// Whether the turn an event finished got past a failed check: only
    /// then, or at the check passing again, may Boop say a word that claims
    /// a fix (`CharacterPack.claimsAFix`).
    func fixed(_ e: Event) -> Bool { (line(e)?.facts["checks_failed"]?.int ?? 0) > 0 }

    /// The replies that say your words to it were rude, and that ask it
    /// to be quiet for a while.
    static let rudeReply = "ouch", hushReply = "hush"

    /// Whether `e` is an idle check-in, or a working one.
    static func isCheckIn(_ e: Event) -> Bool { e.type == .checkIn && e.specificType == "check_in" }
    static func isWorkingCheckIn(_ e: Event) -> Bool { e.type == .checkIn && e.specificType == "working" }

    /// The idle beat at `about` as it's offered: the one dealt, with the
    /// signs the question shows: one, or for a musing a few, never the
    /// last sign held up while another fits. A pass `forced` from outside
    /// is offered every beat there is, with all its signs, to name one. At
    /// a working check-in, the one the rules hold up (`ruled`).
    func beats(_ about: Event?, _ log: LogView, forced: Bool = false) -> [IdleBeat.Candidate] {
        guard let about, Self.isCheckIn(about) || Self.isWorkingCheckIn(about) else { return [] }
        let all = idleBeat(about, log, forced)
        if forced { return all }
        recall(log)
        return all.prefix(1).compactMap { beat in
            var beat = beat
            beat.signs = Array(Self.unrepeated(beat.signs, last: lastSign).prefix(beat.kind == .musing ? IdleBeat.musingsOffered : 1))
            return beat.signs.isEmpty ? nil : beat
        }
    }

    /// What the sign's question says of an idle beat's sign, by its kind.
    static func option(_ sign: String, for beat: IdleBeat.Candidate, name: String) -> Option {
        switch beat.kind {
        case .waiting, .notice:
            Option(sign, "Something \(name) noticed, true now: \(beat.notice?.fact ?? "")\(beat.kind == .waiting ? ". Of use to the person." : ". For caring, never to scold.")")
        case .wish: Option(sign, "\(name)'s wish for today: it wants \(beat.wish?.words ?? "something") from the person, and shows it until they give it. Due now: usually this.")
        case .ask: Option(sign, "A question for the person to answer with a tap: \(beat.ask.map { "\($0.a) or \($0.b)" } ?? ""). Due now: usually this.")
        case .remembered: Option(sign, "Something it remembers, from MEMORY: \(beat.remembered?.note ?? "") Due now, if it fits the hour.")
        case .musing: Option(sign, "A musing to hold up, asking nothing.")
        }
    }

    /// What a reply holds up (`replies.md`), and for a `status` one about
    /// what you said, the agents' facts that answer it and where the board
    /// shows the rest (`StatusReply`), or nil for none.
    let replies: [TaggedLine]
    let status: (Event) -> StatusReply.Answer?
    /// The moment's tags for a reply's sign at an event: `working` while an
    /// agent works, `waiting` while something waits on you.
    let moment: (Event) -> [String]
    /// Makes it quiet for a while from a time (`Core.quiet`): the hush
    /// reply's doing.
    let quiet: (_ at: Int64) -> Void
    /// Boop goes to sleep now, at your lock at night (`Core.nap`).
    let nap: (Int64) -> Void
    /// How much it says now, the setting's or quiet for a while: on Quiet,
    /// a small moment or a finish says nothing, and nothing swears.
    let talk: () -> Talk
    /// Whether it may swear, chosen in Settings: off, no skit swears
    /// (`Skits.play`) and no swear take plays. The evals keep it on.
    let swears: () -> Bool
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
    /// again while another fits.
    var lastSign: String?
    /// Whether it has read back what it said before this launch.
    var recalled = false

    /// Reads back what it said and held up last, before this launch.
    func recall(_ log: LogView) {
        guard !recalled else { return }
        recalled = true
        let mine = log.events.filter { $0.kind == Event.did && $0.action == Self.outputName }
        let texts = Dictionary(Take.all(in: pack).map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        recentWords = mine.compactMap { d in
            let said = d["takes"]?.array?.compactMap(\.string).compactMap { texts[$0] } ?? []
            return said.isEmpty ? nil : said
        }.suffix(Self.recentSays) + recentWords
        lastSign = lastSign ?? mine.last { $0["sign"] != nil }?["sign"]?.string
    }

    public init(queue: @escaping (Moment, Pending) -> Void, blocked: @escaping () -> String?,
                replyBlocked: (() -> String?)? = nil, who: @escaping (Event?) -> Moment.Who? = { _ in nil },
                turnMs: @escaping (Event?) -> Int64? = { _ in nil }, speaks: @escaping () -> Bool = { true },
                pack: CharacterPack = .active, signs: [TaggedLine] = [],
                calendar: @escaping (Event) -> [String] = { _ in [] }, replies: [TaggedLine] = [],
                status: @escaping (Event) -> StatusReply.Answer? = { _ in nil }, moment: @escaping (Event) -> [String] = { _ in [] },
                quiet: @escaping (_ at: Int64) -> Void = { _ in },
                nap: @escaping (Int64) -> Void = { _ in },
                talk: @escaping () -> Talk = { .default }, swears: @escaping () -> Bool = { true }, reason: @escaping (Event?) -> Narration? = { _ in nil },
                moodMoved: @escaping (Event?, LogView) -> String? = { _, _ in nil }, note: @escaping (String, Int64) -> Void = { _, _ in },
                dreams: [TaggedLine] = [], line: @escaping (Event) -> Line? = { _ in nil },
                asks: [TaggedLine] = [],
                idleBeat: @escaping (Event, LogView, Bool) -> [IdleBeat.Candidate] = { _, _, _ in [] },
                makeWish: @escaping (Core.WishKind, Int64) -> Void = { _, _ in },
                moodFace: @escaping (LogView) -> String? = { _ in nil },
                moodID: @escaping (LogView) -> String? = { _ in nil },
                moodLevel: @escaping (LogView) -> Int = { _ in 1 },
                today: @escaping () -> MemoryReader.Tallies? = { nil }, seed: UInt64 = 0x7A4E) {
        self.today = today
        self.idleBeat = idleBeat
        self.moodFace = moodFace
        self.moodID = moodID
        self.moodLevel = moodLevel
        takes = SplitMix64(seed: seed)
        asideRng = SplitMix64(seed: seed ^ 0x11E5)
        self.pack = pack
        asked = Self.questions(in: pack)
        askedOfTalk = Self.talkQuestions(asked, in: pack)
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
        self.quiet = quiet
        self.nap = nap
        self.talk = talk
        self.swears = swears
        self.reason = reason
        self.moodMoved = moodMoved
        self.note = note
        self.dreams = dreams
        self.line = line
        self.asks = asks
        self.makeWish = makeWish
    }

    static func article(_ word: String) -> String { "aeiou".contains(word.first ?? "x") ? "an" : "a" }

    /// What Boop replies to what you said on push-to-talk: what you meant,
    /// answered (`react.reply`). The board plays the pack's clip for it
    /// (`reply-<name>`, characters/CHARACTER.md §15), and the sign is the
    /// pack's line for it that answers what you said best (`replies.md`,
    /// `react.sign`), or for `status` the agents' facts (`StatusReply`).
    /// Yes and no are never about the agents, and never a promise:
    /// `status` answers a question about them from what the core knows, so
    /// the brain never guesses a fact, and a request is turned down.
    public static var replies: [Option] { replies(of: CharacterPack.active.name) }
    static func replies(of name: String) -> [Option] {
        let agents = "A question about the agents or their work, which is status."
        return [
            Option("yes", "Yes: agreeing, or yes to a question about \(name) itself (\"are you awake?\", \"are you okay?\"). It nods.",
                   notFor: agents + " Asking \(name) to do something, which is no."),
            Option("no", "No: disagreeing, no to a question about \(name) itself, or turning down something it's asked to do: a trick (\"roll over\", \"dance\"), \"go away\", or anything for an agent (\"tell claude yes\", \"approve it\"), which \(name) never does. It shakes its head.",
                   notFor: agents),
            Option("huh", "Huh: \(name) can't answer it: words that make no sense, are cut off or aren't meant for it, or a question it can't know, about the world, the weather or dinner. It shrugs, or tilts its head.",
                   notFor: agents + " A question about \(name) itself, which is yes or no."),
            Option("hello", "Hello: a greeting, even one that asks how it's going (\"hey, how's it going?\", \"what's up?\"), calling out for \(name) (\"where are you?\"), or you saying you're back. It waves.",
                   notFor: "Goodbye or good night, which is bye; a question about the agents' work, which is status."),
            Option("bye", "Bye: goodbye, good night, or you saying you're off for a while. It waves you off."),
            Option("thanks", "Thanks: something good or fond: praise or thanks for \(name) or the work (\"good job\", \"nice one\"), affection or making up (\"I love you\", \"you're cute\", \"sorry, \(name)\"), your good news (\"we shipped it\"), or wishing you luck. It puffs up, proud."),
            Option("ouch", "Ouch: rude words or an insult to \(name). It flinches."),
            Option("comfort", "Comfort: you sound tired, sad or stressed, or tell it bad news. It leans in close."),
            Option("hehe", "Hehe: a joke, teasing or something silly. It giggles."),
            Option("status", "Status: a question about the agents or their work: done yet, how long, how many are running, what they're doing (\"what are you doing?\" too, asked of \(name) at its desk), anyone need me, how's the work going, did it work, how long you've been at it. It holds up the answer on a sign, from what it knows.",
                   notFor: "A question about \(name) itself, which is yes, no or huh; a greeting, which is hello."),
            Option(hushReply, "Hush: asked to stop talking: \"shh\", \"be quiet\", \"shut up\", \"stop talking\". It zips its lips, and is quiet for half an hour.",
                   notFor: "Rude words that aren't asking for quiet, which is ouch."),
        ]
    }

    /// The reply `react.reply` picked of what you said: `huh` when its
    /// answer is missing, below the floor or not a reply, since Boop
    /// answers what you said with something, and a guess at what you meant
    /// is worse.
    public static func reply(_ answers: Answers) -> String {
        pick(answers, replyKey, replies) ?? "huh"
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

    /// The board's reply for a slight wave, a small hello or bye: a
    /// slighter motion than `bye` or `hello`, the pack's `reply-wave` clip.
    public static let wave = "wave"

    /// What it plays at a notice: it looks up at you.
    public static let noticeScene = "notice"

    /// What it plays at a rough hour's notice: it leans in close.
    public static let roughReply = "comfort"

    /// The clip it plays bringing up what it remembers: the pack's
    /// `reply-remember`.
    public static let rememberClip = "remember"
    /// The low signs a ship and a fix hold up, with what they earned.
    public static let shippedSign = "shipped", fixedSign = "tests fixed"

    /// A move as a reply: to what you said, or a hello's or a bye's wave.
    struct Reply {
        /// Its name, which picks its lines and words.
        var word: String
        /// What the board plays: a slight wave is the slighter motion; what
        /// you said is as it is.
        var played: String
        /// How HISTORY's line says it.
        var did: String
        /// Whether Boop goes for its nap.
        var naps = false
    }

    /// The moment's tags a reply's sign may have, beside the calendar's.
    public static let momentTags = ["working", "waiting"]

    /// Whether `e` is something you said on push-to-talk, which a reply
    /// answers.
    static func isTalk(_ e: Event?) -> Bool { e?.type == .said }

    /// What a pass is about: its event, or for one forced from outside
    /// (a demo's), the latest that happened, but for push-to-talk's own
    /// listening after what you said, and the harness's.
    static func about(_ now: Event?, _ log: LogView) -> Event? {
        now ?? log.events.last { !$0.fromHarness && $0.type != .listen }
    }

    /// What a size sets: how many loops the face holds and the kind of
    /// take it says.
    public struct Size: Equatable, Sendable {
        public let name: String
        public let loops: Int
        public let kind: Take.Kind
    }

    /// Each size, the smallest first (`MomentRule.small`…): once a sound,
    /// twice a word, three times a phrase.
    public static let sizes: [Size] = [
        Size(name: "small", loops: 1, kind: .sound), Size(name: "medium", loops: 2, kind: .word),
        Size(name: "big", loops: 3, kind: .phrase),
    ]

    /// The size of a Moment as it played, by its loops.
    public static func size(loops: Int?) -> Size { sizes.first { $0.loops == loops } ?? sizes[0] }

    /// The moves a Moment can play at an event (`MomentRule.move`): a
    /// turn's finish, a wake-up when you come back from a long break, or
    /// a notice when your prompt says its name.
    public static let moves = ["success", "failure", "wake up", "notice"]

    /// The move a Moment played, as the tools name it: its scene's, else
    /// its reply, or nil for none.
    public static func move(of m: Moment) -> String? {
        scenes.first { $0.value.anim == m.anim && $0.value.outcome == m.outcome }?.key ?? m.reply
    }

    /// What the device plays for each of `moves`: the face's
    /// task_complete scene for a success or a failure, with that outcome,
    /// its wake_up for a wake up, and its notice for a notice. A chat
    /// turn plays none (`MomentRule.move`).
    /// What a chat turn holds low (`MomentRule.Finish.reply`).
    public static let yourTurn = "your turn"

    public static let scenes: [String: (anim: String, outcome: String?)] = [
        "success": ("task_complete", "success"), "failure": ("task_complete", "failure"),
        "wake up": ("wake_up", nil), "notice": ("notice", nil),
    ]

    /// A reaction still in progress this long after it started is ended as
    /// failed: past the longest reaction, held three times (`big`) in the
    /// design with the longest loop. The longest hold of the longest design
    /// must end on the device before the link stops waiting for its
    /// `ended` (its `ttl` plus 60 s, linkkit/SPEC.md §5), or a reaction that
    /// played would read as failed: `testAReactionEndsBeforeTheHarnessCeiling`
    /// holds it so.
    public static let openForMs: Int64 = 90_000

    /// The result card an agent handed in for the turn `now` finished, if
    /// any: its offered lines play after the finish (`MomentRule.offeredLine`).
    public var offered: (Event?) -> Card? = { _ in nil }

    /// What a skit's invite is asked by, or nil for none ever (the evals',
    /// and most tests'): whether the board plays invites (its `hello`'s
    /// `invites`), whether you're on a call, the ledger (`InviteLedger`, nil
    /// for none), and what care would add today for the touch (`Growth.adds`):
    /// what the payoff shows. It's paid as the touch comes, by what fits
    /// then, so a finish filling the day during the wait may leave less.
    public struct Inviting {
        public var board: () -> Bool
        public var onCall: () -> Bool
        public var ledger: () -> InviteLedger?
        public var care: () -> Int

        public init(board: @escaping () -> Bool, onCall: @escaping () -> Bool = { false }, ledger: @escaping () -> InviteLedger?,
                    care: @escaping () -> Int = { 0 }) {
            self.board = board
            self.onCall = onCall
            self.ledger = ledger
            self.care = care
        }
    }
    public var inviting: Inviting?

    /// What `skit`'s invite comes to: none unless the board plays invites,
    /// nothing blocks the Moment and you're not on a call; else the
    /// ledger's (`InviteLedger.asking`), with the pack's word for the touch
    /// (`Signs.invite`) and the XP care would add now, none with no room.
    func invite(for skit: Skit) -> InviteLedger.Asking {
        guard skit.invite != nil, let inviting, inviting.board(), blocked() == nil, !inviting.onCall(),
              let ledger = inviting.ledger() else { return .nothing }
        let care = inviting.care()
        return ledger.asking(skit, label: { Signs.invite(self.signs, touch: $0) }, xp: care > 0 ? care : nil)
    }

    /// The record of the low Moment queued behind the last finish, still to
    /// be written: its line for HISTORY, its facts and its handle. The
    /// brain's rules write it right after the finish's own record, so each
    /// Moment's record ends as the board says that one ended
    /// (`Runtime.brain`); nil when nothing was queued behind it.
    public internal(set) var following: (message: String, facts: [String: JSONValue], pending: Pending)?

    /// What a skit's remark is picked by, or nil for none ever (the evals',
    /// and most tests'): your usual (`Normals`, nil for none) and a time's
    /// minutes after 5:00, when Boop's day starts.
    public struct Remarking {
        public var normals: () -> Normals?
        public var minutes: (Int64) -> Int

        public init(normals: @escaping () -> Normals?, minutes: @escaping (Int64) -> Int) {
            self.normals = normals
            self.minutes = minutes
        }
    }
    public var remarking: Remarking?

    /// The last of the pack's aside rows said, which the next doesn't say
    /// again while another fits.
    var lastAsideRow: String?
    /// Picks the pack's asides, apart from `takes`, so an aside never
    /// moves which take or sign comes next.
    var asideRng = SplitMix64(seed: 0x11E5)

    /// The pack's aside for `skit`, a failed check or a push at `slot`,
    /// if any (`Asides`): none on Quiet; it swears only when the skit
    /// does. Of those the board can say whole (`voiced`), the one whose
    /// sentence says `preferring` (Jev's pick), if it's one.
    func packAside(skit: Skits.Play?, slot: RulesBrain.Slot?, about: Event, facts: [String: JSONValue], log: LogView,
                   voiced: (String) -> Bool = { _ in false }, preferring: String? = nil) -> Asides.Pick? {
        guard let slot, let moment = Asides.moment(skit: skit, slot: slot, pushed: Self.pushed(about)) else { return nil }
        let mood = moodID(log) ?? pack.defaultMood, work = work(about, facts: facts, log: log), calendar = calendar(about)
        if let preferring,
           let liked = Asides.pool(signs, moment: moment, slot: slot, facts: facts, work: work, calendar: calendar, mood: mood,
                                   swears: skit?.swears ?? false, quiet: talk() == .quiet, voiced: voiced)
               .first(where: { pick in pick.take.map { sentences(of: $0).contains(preferring) } ?? false }) {
            lastAsideRow = liked.row
            return liked
        }
        guard let pick = Asides.pick(signs, moment: moment, slot: slot, facts: facts, work: work, calendar: calendar, mood: mood,
                                     swears: skit?.swears ?? false, quiet: talk() == .quiet, voiced: voiced,
                                     avoiding: lastAsideRow, rng: &asideRng)
        else { return nil }
        lastAsideRow = pick.row
        return pick
    }

    /// Whether `e` is a push that went out.
    static func pushed(_ e: Event) -> Bool { e.type == .act && e.specificType == "push" && e["passed"]?.bool == true }

    /// The texts the voice's takes of the sentence `id` say, in any face.
    func sentences(of id: String) -> [String] {
        Take.all(in: pack).filter { $0.part == .sentence && $0.meaning == id }.map(\.text)
    }

    /// Whether the board can say the sentence `id` whole in `face`: a
    /// board that speaks, with a take of it in that face. Nil `face`: in any.
    func voices(_ id: String, face: String?) -> Bool {
        speaks()
            && Take.all(in: pack).contains { $0.part == .sentence && $0.meaning == id && (face.map($0.moods.contains) ?? true) }
    }

    /// What the turn `about` finished was, as its agent put it
    /// (`Asides.work`): its last status card's `doing` this turn, its
    /// result's headline, its last work act, the thread's name, the
    /// project's. Nil for anything but a finish.
    func work(_ about: Event, facts: [String: JSONValue], log: LogView) -> String? {
        guard MomentRule.finish(facts) != nil, let key = TranscriptView.about(about, facts: facts) else { return nil }
        var doing: String?, act: String?
        for e in log.events.reversed() where e.seq < about.seq {
            if e.type == .turn, e.phase == .start, TranscriptView.about(e, facts: nil) == key { break }
            if doing == nil, e.type == .card, e.phase == .start, TranscriptView.about(e, facts: nil) == key { doing = e["text"]?.string }
            if act == nil, e.type == .act, e["session"]?.string == key { act = e.specificType }
            if doing != nil { break }
        }
        let project = facts["thread"]?.object?["name"]?.string
        let thread = who(about)?.thread
        return Asides.work(doing: doing, headline: offered(about)?.text, act: act, thread: thread == project ? nil : thread, project: project)
    }

    /// The remark on `skit` at `about`, whose line has `facts`, and its
    /// words, or nil: the rule's pick against your usual before it
    /// (`Remarks.pick`), in one of the pack's lines for it (`Signs.remark`),
    /// not the last sign held up while another fits.
    /// Of the lines the board can say whole (`voiced`: the row names a
    /// sentence recorded for the face), only those, so what it says and
    /// what it shows are one choice; the sentence comes back with it.
    func remark(for skit: Skit, about: Event, facts: [String: JSONValue],
                voiced: (String) -> Bool = { _ in false }) -> (id: String, words: String, take: String?)? {
        guard let remarking, let normals = remarking.normals() else { return nil }
        let usual = normals.usual(before: about.seq, minutes: remarking.minutes)
        guard let id = Remarks.pick(skit: skit.id, facts: facts, usual: usual, minutes: remarking.minutes(about.at), quiet: talk() == .quiet)
        else { return nil }
        let rows = Signs.remarkRows(signs, id, n: Remarks.number(id, facts: facts, usual: usual))
        let said = rows.filter { $0.take.map(voiced) ?? false }
        let pool = said.isEmpty ? rows.map { ($0.text, nil as String?) } : said.map { ($0.text, $0.take) }
        let fresh = pool.count > 1 ? pool.filter { $0.0 != lastSign } : pool
        guard !fresh.isEmpty else { return nil }
        let (words, take) = fresh[takes.int(in: 0...(fresh.count - 1))]
        return (id, words, take)
    }

    /// Below this, Jev is guessing at what you meant, and a `huh` beats a
    /// guessed reply.
    public static let replyFloor = 0.35

    /// A question's pick: its answer if it isn't `none`, reaches the floor
    /// and is one of `options`, else nil.
    static func pick(_ answers: Answers, _ key: String, _ options: [Option]) -> String? {
        guard let a = answers[key], a.choice != "none", a.p >= replyFloor,
              options.contains(where: { $0.name == a.choice }) else { return nil }
        return a.choice
    }

    /// Its questions, the sign's where there's one to pick, and at a skit
    /// which take it says (`takeQuestion`).
    public func questions(now: Event?, log: LogView) -> [Question] {
        let meme = self.meme(Self.about(now, log))
        return faceAndSign(now: now, log: log).map { q in
            guard q.key == Self.emotionKey, let meme else { return q }
            return Question(key: q.key, text: q.text, about: q.about, judgeBy: q.judgeBy, options: q.options + [meme])
        } + (takeQuestion(now, log).map { [$0] } ?? [])
    }

    /// The meme face `about` calls for, as an option of the emotion
    /// question: offered there alone (`RulesBrain.meme`), never at your
    /// words, nor where the rules make the Moment whole.
    func meme(_ about: Event?) -> Option? {
        guard let about, !Self.isTalk(about) else { return nil }
        let facts = line(about)?.facts ?? [:]
        return RulesBrain.meme(RulesBrain.read(about, facts: facts), facts: facts).flatMap { pack.memes[$0] }
    }

    /// The face, and the sign's where there's one to pick: for what you
    /// said, a prompt's reading, an answered ask or a dream's telling, a
    /// caption that fits; at an idle check-in, whether to hold up the one
    /// thing that's due (`IdleBeat`).
    func faceAndSign(now: Event?, log: LogView) -> [Question] {
        let about = Self.about(now, log)
        if let about, Self.isTalk(about) {
            let asked = askedOfTalk
            let captions = replyCaptions(about)
            guard !captions.isEmpty else { return asked }
            return asked + [Question(key: Signs.questionKey,
                                     text: "Which sign does \(pack.name) hold up with its reply? The one that answers what you said best, of those for the reply it makes. Your own words played back are the best of these, when they fit.",
                                     about: "the words NOW quotes", judgeBy: "what the person said and meant, then PERSONALITY and MOOD",
                                     options: [Option("facts", "With a status reply: the agents' facts, none of these.")]
                                         + captions.map { Option($0.text, "With \(Self.article($0.replies[0])) \($0.replies.joined(separator: " or ")) reply"
                                                                 + ($0.replies.contains("dunno") ? " (dunno, a huh to a question)." : ".")) })]
        }
        // An idle check-in: the one thing that's due, held up or not.
        let beats = beats(about, log, forced: now == nil)
        if !beats.isEmpty {
            return asked + [Question(key: Signs.questionKey,
                                     text: "Does \(pack.name) hold this up now, or nothing? It's the one thing due, already timed for it (an hour apart at most), whatever face it makes or none: hold it up, unless the moment is wrong for it.",
                                     about: "NOW, CONTEXT and HISTORY", judgeBy: "PERSONALITY and MOOD",
                                     options: [Option("none", "Nothing, now and then: MOOD is cross or low and this is playful, or NOW isn't a quiet moment.")]
                                         + beats.flatMap { beat in beat.signs.map { Self.option($0, for: beat, name: pack.name) } })]
        }
        // On Quiet a sign is held up only for a prompt that sounds like
        // something or says its name.
        let prompt = about.flatMap { $0.type == .prompt ? PromptReading(facts: $0.data) : nil }
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
                                 options: [Option("none", "No sign: PERSONALITY gives this prompt none, or nothing in it is worth holding up.")]
                                     + captions.map { Option($0, "A sign that says this.") })]
    }

    /// The slot the rules read `about` as, whose line has `facts`, for its
    /// skit: none for your words, nor for a Moment the rules make whole.
    func slot(_ about: Event?, facts: [String: JSONValue], ruled: Bool) -> RulesBrain.Slot? {
        guard let about, !Self.isTalk(about), !ruled else { return nil }
        return RulesBrain.read(about, facts: facts).slot
    }

    /// The skit that plays at `slot`, if any (`Skits.play`). On Quiet
    /// nothing swears.
    func skit(at slot: RulesBrain.Slot, facts: [String: JSONValue]) -> Skits.Play? {
        Skits.play(slot: slot, facts: facts, swears: swears() && talk() != .quiet, in: pack.skits)
    }

    /// The words it never says at `about`: one that claims a fix, unless
    /// the turn got past a failed check or the check passes again.
    func never(_ about: Event?, slot: RulesBrain.Slot?) -> Set<String> {
        about.map(fixed) == true || slot == .checkFixed ? [] : pack.claimsAFix
    }

    /// Whether it says nothing at a Moment this big, with this move: on
    /// Quiet, nothing at a small moment or a finish, or with a wish, which
    /// shows as its icon and sign. Late at night a notice stays gentle: no
    /// word with it.
    func silent(_ size: Size, move: String?, wishing: Bool = false, late: Bool = false) -> Bool {
        (talk() == .quiet && (size.name == "small" || move != nil || wishing)) || late
    }

    /// The texts `skit` may say at `about` (`Voice.texts`), of the kind its
    /// size asks, a swear when it swears, in whatever face is picked, those
    /// not said lately first. None where it says nothing.
    func takeTexts(_ skit: Skits.Play, slot: RulesBrain.Slot, about: Event, facts: [String: JSONValue], log: LogView) -> [String] {
        let size = Self.sizes[MomentRule.size(about, facts: facts, mood: moodID(log))]
        let move = MomentRule.move(about, facts: facts)
        guard speaks(), !silent(size, move: move) else { return [] }
        recall(log)
        // The recorded sentences that fit, when the board can say any whole.
        let sentences = Asides.moment(skit: skit, slot: slot).map { moment in
            Asides.pool(signs, moment: moment, slot: slot, facts: facts, work: work(about, facts: facts, log: log), calendar: calendar(about),
                        mood: moodID(log) ?? pack.defaultMood, swears: skit.swears, quiet: talk() == .quiet,
                        voiced: { self.voices($0, face: nil) })
                .compactMap(\.take).filter { voices($0, face: nil) }.flatMap(self.sentences(of:))
        } ?? []
        if !sentences.isEmpty {
            let texts = sentences.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            return Array((texts.filter { !lastWords.contains($0) } + texts.filter(lastWords.contains)).prefix(Self.takesOffered))
        }
        return Voice.texts(.skit, meaning: skit.skit.id, kind: skit.swears ? .swear : size.kind, avoiding: lastWords,
                           never: never(about, slot: slot), limit: Self.takesOffered, in: pack)
    }

    /// At a skit with more than one thing it may say, which it says: only
    /// Jev answers it. With no answer, Voice picks, as it does with no key.
    func takeQuestion(_ now: Event?, _ log: LogView) -> Question? {
        let about = Self.about(now, log)
        let facts = about.flatMap { line($0)?.facts } ?? [:]
        guard let about, let slot = self.slot(about, facts: facts, ruled: false), let skit = self.skit(at: slot, facts: facts) else { return nil }
        let texts = takeTexts(skit, slot: slot, about: about, facts: facts, log: log)
        guard texts.count > 1 else { return nil }
        return Question(key: Self.takeKey, text: "\(pack.name) speaks at this moment. Which of these does it say, in its mood?",
                        about: "the NOW section", judgeBy: "what NOW says happened, then PERSONALITY and MOOD",
                        options: texts.map { Option($0, "It says this.") })
    }

    /// What Jev picked for `skit` to say, if it's one of the texts offered now.
    func pickedTake(_ answers: Answers, _ skit: Skits.Play, slot: RulesBrain.Slot, about: Event, facts: [String: JSONValue],
                    log: LogView) -> String? {
        guard let choice = answers[Self.takeKey]?.choice else { return nil }
        return takeTexts(skit, slot: slot, about: about, facts: facts, log: log).contains(choice) ? choice : nil
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
        // An ask answered: what it holds up after that answer.
        if about.type == .ask, let q = about["q"]?.string, let answer = about["answer"]?.string {
            return Asks.followUps(asks, id: q, answer: answer)
        }
        guard about.type == .prompt, let reading = PromptReading(facts: about.data) else { return [] }
        return Signs.offered(signs, reading: reading, name: pack.name, calendar: calendar(about))
    }

    /// The captions a reply to `said` may hold up, each once with the
    /// replies it's for: every reply's lines that fit the moment
    /// (`Signs.replies`), with what you said played back; `dunno`'s beside
    /// `huh`'s, and none for `status`, whose sign is the agents' facts.
    func replyCaptions(_ said: Event) -> [(text: String, replies: [String])] {
        let tags = replyTags(said)
        let phrases = Signs.phrases(of: said["words"]?.string ?? "", name: pack.name)
        let names = Self.replies(of: pack.name).map(\.name).flatMap { $0 == "huh" ? ["huh", "dunno"] : [$0] }
        var out: [(text: String, replies: [String])] = []
        for reply in names where reply != "status" {
            for text in Signs.replies(replies, reply, calendar: tags, phrases: phrases, avoiding: lastSign, turns: today()?.turns ?? 0) {
                if let i = out.firstIndex(where: { $0.text == text }) { out[i].replies.append(reply) } else { out.append((text, [reply])) }
            }
        }
        return out
    }

    /// The calendar's and the moment's tags a reply's sign may have at
    /// `said`: `working` and `waiting`.
    func replyTags(_ said: Event) -> [String] { calendar(said) + moment(said) }

    /// The questions asked of what you said, from `asked`: the face, but
    /// never none, since what you said always gets one, and its reply.
    static func talkQuestions(_ asked: [Question], in pack: CharacterPack) -> [Question] {
        let name = pack.name
        return asked.flatMap { q -> [Question] in
            switch q.key {
            case emotionKey:
                return [Question(key: q.key, text: "Which emotion does \(name) show at what you said? It always shows one.", about: q.about,
                                 judgeBy: q.judgeBy, options: q.options.filter { $0.name != "none" }),
                        Question(key: replyKey, text: "What does \(name) reply to what you said? It answers what you meant with its body and a sign, never with words of its own.",
                                 about: "the words NOW quotes", judgeBy: "what the person meant, then PERSONALITY and MOOD",
                                 options: replies(of: name))]
            default: return [q]
            }
        }
    }

    /// Every question, for `pack`'s character: the face.
    static func questions(in pack: CharacterPack = .active) -> [Question] {
        let name = pack.name
        let byBoth = "PERSONALITY and MOOD"
        return [
            Question(key: emotionKey, text: "How should \(name) react to NOW, if at all? A moment: it shows one emotion in this mood's way.",
                     about: "the NOW section", judgeBy: byBoth,
                     options: [Option("none", "Stay quiet: most check-ins where nothing has happened; nothing in NOW is worth a moment, "
                                          + "or HISTORY shows \(name) still having the one it calls for, about the same thing (in progress).",
                                      notFor: "Something new said to \(name), which always gets a moment of its own, even while one plays; "
                                          + "a turn that finished done or failed, which always gets a moment; "
                                          + "or anything PERSONALITY reacts to that \(name) isn't already doing.")]
                         + pack.faces),
        ]
    }

    /// A Moment the rules make whole, with no pass (`ruled`): its face,
    /// its size, its sign, and its wave, and whether it says the wave's
    /// word (its hello's or bye's own take).
    public struct Ruled {
        var face: String
        var size: Int
        var sign: String?
        var wave: Reply?
        var saysWave = false
        /// Words held low in gold, and what's before them (`Moment.mark`).
        var gold: String?
        var mark: String?
        /// The idle beat it holds up, `sign` its sign (a working check-in's).
        var beat: IdleBeat.Candidate?
    }

    /// The Moment the rules make at `e`, whose line has `facts`, or nil
    /// where they make none: at your lock its bye and at your unlock its
    /// hello (`MomentRule.bye`, `hello`), at a working check-in its face in
    /// silence (`MomentRule.checkIn`), or in its mood's face the beat due
    /// there, held up (`IdleBeat.atWork`), and at another buddy's gesture a
    /// warm face and a sign that answers it (`MomentRule.world`).
    public func ruled(_ e: Event, facts: [String: JSONValue], log: LogView) -> Ruled? {
        recall(log)
        let mood = moodID(log) ?? pack.defaultMood
        let face = moodFace(log) ?? pack.restingFace(mood)
        switch e.type {
        case .lock?:
            let lock = e.phase == .start
            let wave = lock ? MomentRule.bye(sinceLastMs: facts["since_last_ms"]?.int, night: calendar(e).contains("night"),
                                             working: moment(e).contains("working"), mood: mood)
                : MomentRule.hello(e, facts: facts, mood: mood)?.wave ?? .slight
            let word = lock ? "bye" : "hello"
            switch wave {
            case .snub: return Ruled(face: face, size: MomentRule.small)
            case .slight:
                return Ruled(face: face, size: MomentRule.small, wave: Reply(word: word, played: Self.wave, did: ", waving"))
            case .wave, .nap:
                let sign = Signs.reply(replies, word, calendar: replyTags(e), avoiding: lastSign, turns: today()?.turns ?? 0, rng: &takes)
                return Ruled(face: face, size: MomentRule.medium, sign: sign,
                             wave: Reply(word: word, played: word, did: wave == .nap ? ", waving, and going to sleep" : ", waving",
                                         naps: wave == .nap), saysWave: true)
            }
        case .checkIn? where e.specificType == "working":
            if let beat = beats(e, log).first, let sign = beat.signs.first {
                return Ruled(face: face, size: MomentRule.small, sign: sign, beat: beat)
            }
            let rung = EventLine.rung(Int(facts["check_in"]?.int ?? 1), of: EventLine.round)
            return Ruled(face: MomentRule.checkIn(rung: rung, mood: mood, face: face), size: MomentRule.small)
        case .world? where e.specificType == World.leagueKind:
            // Last week's place, told once: a medal's cheer, or a small hello.
            guard let place = facts["place"]?.int.map(Int.init), let xp = facts["xp"]?.int.map(Int.init) else { return nil }
            let medal = place <= 3
            return Ruled(face: medal ? "proud" : face, size: medal ? MomentRule.big : MomentRule.small,
                         gold: World.leagueSign(place: place, xp: xp), mark: World.medal(place) ?? "star")
        case .world?:
            let kind = facts["world"]?.string ?? e.specificType
            let pick = MomentRule.world(kind: kind, mood: mood)
            let lines = Self.unrepeated(Signs.world(signs, kind: kind), last: lastSign)
            return Ruled(face: pick.face, size: pick.size,
                         sign: lines.isEmpty ? nil : lines[takes.int(in: 0...(lines.count - 1))])
        default: return nil
        }
    }

    /// Plays a Moment the rules made at `about`, as a pass's is played:
    /// its voice, its sign and its line in HISTORY are worked out the same.
    public func play(_ ruled: Ruled, about: Event, log: LogView) -> OutputResult? {
        run([Self.emotionKey: Answer(choice: ruled.face, probabilities: [ruled.face: 1])], now: about, log: log, ruled: ruled)
    }

    public func run(_ answers: Answers, now: Event?, log: LogView) -> OutputResult? {
        run(answers, now: now, log: log, ruled: nil)
    }

    func run(_ answers: Answers, now: Event?, log: LogView, ruled: Ruled?) -> OutputResult? {
        // 1. Does Jev want a reaction at all, and with which face? Something
        // held up at an idle check-in with no face takes the mood's, small.
        var answers = answers
        let about = Self.about(now, log)
        let talk = Self.isTalk(about)
        let lineFacts = about.flatMap { line($0)?.facts } ?? [:]
        if answers[Self.emotionKey]?.choice == "none", let about, Self.isCheckIn(about),
           let held = answers[Signs.questionKey]?.choice, held != "none", let face = moodFace(log) {
            answers[Self.emotionKey] = Answer(choice: face)
        }
        // A skit, at a pass that's neither your words nor the rules' own
        // Moment: it always plays, so with no face picked it takes the
        // slot's first, as the mood colours it (`RulesBrain.faces`).
        let slot = self.slot(about, facts: lineFacts, ruled: ruled != nil)
        let skit = slot.flatMap { self.skit(at: $0, facts: lineFacts) }
        if let slot, skit != nil, !pack.isFace(answers[Self.emotionKey]?.choice ?? ""),
           let face = RulesBrain.colour(RulesBrain.faces[slot] ?? [], mood: moodID(log) ?? pack.defaultMood, level: moodLevel(log)).first {
            answers[Self.emotionKey] = Answer(choice: face)
        }
        guard let choice = answers[Self.emotionKey]?.choice, pack.isFace(choice) else {
            // No Moment, but a mood that moved still says so.
            if let now, let moved = moodMoved(now, log) { note(moved, now.at) }
            return nil
        }
        // 2. This output's own rules: a reply to what you said shows over
        // needs you, nothing else does.
        if let why = (talk ? replyBlocked ?? blocked : blocked)() { return .failed(why) }
        // 3. The effect: the face, its move, held as long as the moment is
        // big, and what a rule says it says, if Voice has a take of it, as
        // big, in this face's mood. The move and the size are the rule's
        // (`MomentRule`); to what you said, the move is the reply.
        let size = Self.sizes[ruled?.size ?? about.map { MomentRule.size($0, facts: lineFacts, mood: moodID(log)) } ?? MomentRule.small]
        let kind = size.kind
        let replied: Reply?
        if talk {
            let word = Self.played(Self.reply(answers), words: about?["words"]?.string ?? "")
            replied = Reply(word: word, played: word, did: ", replying \(word)")
        } else {
            replied = ruled?.wave
        }
        let reply = replied?.word
        let moved = talk || ruled != nil ? nil : about.flatMap { MomentRule.move($0, facts: lineFacts) }
        let at = about?.at ?? 0
        // What the brain held up at an idle check-in: the beat that was
        // dealt, if it's still the one due.
        let holding = talk || ruled != nil ? nil : (answers[Signs.questionKey]?.choice).flatMap { $0 == "none" ? nil : $0 }
        // A pass forced from outside names what it holds up itself; a
        // rule's Moment brings its own.
        let beat = ruled?.beat ?? holding.flatMap { held in beats(about, log, forced: now == nil).first { $0.signs.contains(held) } }
        let noticing = beat?.notice, wishing = beat?.wish, remembering = beat?.remembered
        // At a notice it looks up at you first, so it's no quiet face; a
        // rough hour's lean is its own look.
        let pick = noticing.map { $0.kind == .rough ? nil : Self.noticeScene } ?? moved
        let silent = self.silent(size, move: pick, wishing: wishing != nil, late: noticing?.kind == .late)
        // What it says, only where a rule says so: to what you said, and at
        // a lock's real wave, the reply's own words, in this face; at a
        // skit, one of the skit's takes, a swear when it swears: the one
        // the brain picked, if this face has it.
        var said: [Take] = []
        recall(log)
        let never = self.never(about, slot: slot)
        if speaks(), !silent {
            let take: Take?
            if let reply, talk || ruled?.saysWave == true {
                take = Voice.take(.reply, meaning: reply, kind: kind, face: choice, avoiding: lastWords, never: never,
                                  in: pack, rng: &takes)
            } else if let skit, let slot, let about {
                let text = pickedTake(answers, skit, slot: slot, about: about, facts: lineFacts, log: log)
                take = Voice.take(.skit, meaning: skit.skit.id, kind: skit.swears ? .swear : kind, face: choice,
                                  avoiding: lastWords, never: never, text: text, in: pack, rng: &takes)
            } else {
                take = nil
            }
            said = take.map { [$0] } ?? []
        }
        // A word may get a sound of the same before it, but not at a small
        // moment, nor on Quiet.
        if let word = said.first, size.name != "small", self.talk() != .quiet,
           let lead = Voice.lead(before: word, face: choice, avoiding: lastWords, in: pack, rng: &takes) {
            said.insert(lead, at: 0)
        }
        let say = Moment.Say(takes: said)
        var sign: String?
        var show: String?
        // Your hello, if this is one: it may play whole, and a special
        // day's sign is code's, over the brain's.
        let hello = ruled == nil ? about.flatMap { self.hello($0) } : nil
        if talk, let reply, let about {
            (sign, show) = replySign(reply, about, answers)
            // The board opens no drawer over the needs-you screen: the
            // sign answers alone then.
            if blocked() != nil { show = nil }
        } else if let ruled {
            // The rule's own sign, or none: a snub holds up nothing.
            sign = ruled.sign
        } else {
            // The idle beat's sign, or a caption the brain picked of those offered.
            sign = beat != nil ? holding : holding.flatMap { offered(now, log).contains($0) ? $0 : nil }
        }
        if case .day(let day)? = hello?.extra { sign = day }
        var reaction = Moment(say: say, mood: choice, loops: size.loops, sign: sign)
        reaction.answersTouch = about.flatMap(Touch.init) != nil
        reaction.gold = ruled?.gold
        reaction.mark = ruled?.mark
        if let sign { lastSign = sign }
        // An ask: the question is the sign, its answers the lane's targets.
        var asking = beat?.ask
        reaction.ask = asking
        // A rough hour: it scoots close and leans.
        reaction.reply = replied?.played ?? (noticing?.kind == .rough ? Self.roughReply : nil)
        reaction.show = show
        reaction.greeting = hello?.whole == true
        if remembering != nil {
            reaction.low = true
            reaction.clip = Self.rememberClip
        }
        // A skit's own clip, as its face starts, when the Moment has none:
        // any invite comes after it.
        if reaction.clip == nil { reaction.clip = skit?.skit.clip }
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
        } else if turnMs(about) != nil, MomentRule.namesTurn(lineFacts) {
            // A face for a finished turn names it too: the device marks
            // the turn it's about while it plays. A chat turn's doesn't.
            reaction.who = who(about)
        }
        // A chat turn: a look up at you and "your turn" low, where the
        // strip is, and nothing of the brain's; no thread named.
        if MomentRule.finish(lineFacts) == .reply, noticing == nil, ruled == nil, !talk {
            reaction.who = nil
            reaction.turn = nil
            reaction.sign = Self.yourTurn
            reaction.low = true
            reaction.ask = nil
            asking = nil
        }
        // A finish that names its thread holds up nothing of the brain's:
        // the face holds up that name.
        if reaction.who != nil {
            reaction.sign = nil
            reaction.ask = nil
            asking = nil
        }
        // What it earned, on the sign that names it.
        if let (source, xp) = earned(about) {
            switch source {
            case .turns where reaction.who != nil:
                reaction.xp = xp
            case .ships where reaction.who == nil && !reaction.low, .fixes where reaction.who == nil && !reaction.low:
                reaction.low = true
                reaction.sign = source == .ships ? Self.shippedSign : Self.fixedSign
                reaction.ask = nil
                asking = nil
                reaction.xp = xp
            default:
                break
            }
        }
        // Why, for the person: the board shows the fact in its lane, unless
        // the strip already names the finished turn it's about.
        // Bringing up a note, the note is why, on the Mac: the board shows the line.
        let why = remembering.map { Narration(cause: Narration.remembers($0.note, name: pack.name)) }
            ?? noticing.map { Narration(cause: Narration.noticed($0.fact), fact: $0.short) }
            ?? wishing.map { Narration.wish($0, name: pack.name, because: beat?.because) } ?? reason(about)
        if reaction.who == nil, asking == nil, remembering == nil { reaction.reason = why?.fact ?? moodMoved(now, log) }
        let pending = Pending()
        // The agent's line, after its finish: Boop's pick of what it offered,
        // held low in the face Boop shows, with the narration saying whose
        // words they were. Never in HISTORY: the brain never reads them.
        // What's behind the finish is a low Moment of its own, queued after
        // it to wait as long as it does, with a record of its own
        // (`following`): its facts, and its words for HISTORY.
        var spoken: Moment?
        var after: [String: JSONValue] = ["takes": .array([])]
        var afterSaid = ""
        func behind(_ words: String) -> Moment {
            var m = Moment(say: Moment.Say(takes: []), mood: choice, loops: 1, sign: words)
            m.low = true
            m.behindFinish = true
            return m
        }
        if reaction.outcome != nil, ruled == nil, blocked() == nil, let card = offered(now),
           let line = MomentRule.offeredLine(card.lines, facts: lineFacts, face: choice, mood: moodID(log) ?? pack.defaultMood,
                                             room: MemoryPipeline.signMax) {
            spoken = behind(line.says)
            spoken?.reason = reaction.who.map { "\($0.agent) offered it" }
            after["offered_line"] = true
            after["aside"] = .string(line.says)
            afterSaid = "After it, \(pack.name) held up the agent's words"
        }
        // A remark on the skit, as text: a finish names its thread and holds
        // up nothing else, so it's a low Moment after it, unless the agent
        // offered a line; any other skit holds it up as its sign, over the
        // dream's or with what happened while you were away, but not over
        // a special day's, an ask or anything held low.
        var remarked: String?
        let finishing = reaction.outcome != nil
        let room = finishing ? spoken == nil
            : (reaction.sign == nil || about.flatMap(told) != nil) && asking == nil && !reaction.low
        let voiced = { (id: String) in self.voices(id, face: choice) && !silent }
        var sentence: String?
        if let skit, let about, room, let (id, words, take) = remark(for: skit.skit, about: about, facts: lineFacts, voiced: voiced) {
            sentence = take
            if finishing {
                spoken = behind(words)
                after[Normals.remarkFact] = .string(id)
                after["sign"] = .string(words)
                afterSaid = "After it, \(pack.name) held up a sign: \"\(words)\""
            } else {
                remarked = id
                reaction.sign = words
                sign = words
            }
            lastSign = words
        }
        // The pack's aside, where neither took the place (`Asides`): a
        // finish's behind it, held low; a check's as the Moment's own low
        // sign, over a fix's. Its words never go to HISTORY, nor does a
        // check's: its record has them.
        var asided: String?
        let jev = answers[Self.takeKey]?.choice
        if ruled == nil, !talk, let about, finishing ? spoken == nil : (asking == nil && beat == nil && remembering == nil),
           let pick = packAside(skit: skit, slot: slot, about: about, facts: lineFacts, log: log,
                                voiced: voiced, preferring: jev) {
            let aside = pick.text
            if sentence == nil, let take = pick.take, voiced(take) { sentence = take }
            if Asides.moment(skit: skit, slot: slot ?? .other) == Asides.back {
                // You back: the sentence only; its sign stays the remark's or the dream's.
            } else if finishing {
                spoken = behind(aside)
                after["aside"] = .string(aside)
                after["sign"] = .string(aside)
                afterSaid = "After it, \(pack.name) held up an aside about it"
            } else {
                reaction.low = true
                reaction.sign = aside
                reaction.ask = nil
                sign = aside
                asided = aside
            }
            if Asides.moment(skit: skit, slot: slot ?? .other) != Asides.back { lastSign = aside }
        }
        // The sentence the Moment shows, said whole by the board in its
        // skit's word's place (or, at a failed check or a push, where it
        // said nothing): voice and text are one choice.
        if let sentence, let take = Voice.take(.sentence, meaning: sentence, kind: .phrase, face: choice, avoiding: lastWords,
                                               text: jev, in: pack, rng: &takes) {
            said = [take]
            reaction.say = Moment.Say(takes: said)
        }
        if !said.isEmpty { recentWords = Array((recentWords + [said.map(\.text)]).suffix(Self.recentSays)) }
        // A skit's invite, on the last Moment queued, so the pose comes
        // after the agent's line or the remark; the record of the Moment
        // that carries it says so, and what HISTORY reads.
        let invited = skit.map { invite(for: $0.skit) } ?? .nothing
        if case .asks(let invite) = invited {
            if spoken != nil { spoken?.invite = invite } else { reaction.invite = invite }
        }
        var invitedFacts: [String: JSONValue] = [:]
        switch invited {
        case .asks(let invite): invitedFacts[InviteLedger.askedFact] = .string(invite.pose.rawValue)
        case .skipped(let pose): invitedFacts[InviteLedger.skippedFact] = .string(pose.rawValue)
        case .nothing: break
        }
        let inviting = { (m: Moment) in m.invite.map { ", then " + EventLine.inviting($0.pose, $0.touch) } ?? "" }
        queue(reaction, pending)
        following = nil
        if let spoken {
            let next = Pending()
            queue(spoken, next)
            following = (afterSaid + inviting(spoken) + ".", after.merging(invitedFacts) { _, new in new }, next)
        }
        // Asked to hush: quiet for a while, from here on.
        if reply == Self.hushReply { quiet(at) }
        if replied?.naps == true { nap(at) }
        if let wishing { makeWish(wishing, at) }
        // 4. What it started, as its line in HISTORY: in progress until
        // the device says how the reaction ended.
        let did = "\(pack.name) had \(Self.article(choice)) \(choice.replacingOccurrences(of: "_", with: " ")) moment (\(size.name))"
            + (pick.map { ", playing \(Self.article($0)) \($0)" }
                ?? replied?.did ?? "")
        // The takes' ids in order, and the reply as it played, for the
        // tools to say what it did.
        let held: String = (asking.map { ", asking \"\($0.question)\": \($0.a) or \($0.b)" }
            ?? (asided != nil ? "" : nil)
            ?? sign.map { ", holding up a sign: \"\($0)\"" } ?? "")
            + (show == StatusReply.drawer ? " and showing every agent" : "")
        let spoke: String = (reaction.say?.text.map { ", and said \"\($0)\"" } ?? "") + inviting(reaction) + "."
        var facts: [String: JSONValue] = ["takes": .array(said.map { .string($0.id) })]
        // A skit that played, whether it spoke or not (`takes` says): what
        // your usual counts the skits since a remark by.
        if let skit { facts["skit"] = .string(skit.skit.id) }
        if let reply { facts["reply"] = .string(reply) }
        if let sign { facts["sign"] = .string(sign) }
        if let why { facts["reason"] = .string(why.reaction(face: choice, name: pack.name)) }
        // An idle beat that showed counts against the cap, by its kind;
        // what the memory keeps of each kind's rest reads the rest.
        if let beat, sign != nil { facts[IdleBeat.fact] = .string(beat.kind.rawValue) }
        if let noticing {
            facts["notice"] = .string(noticing.kind.rawValue)
            facts["notice_key"] = .string(noticing.key)
        }
        if let remembering { facts["felt"] = .string(remembering.line) }
        // A remark this Moment showed: what your usual counts the skits since by.
        if let remarked { facts[Normals.remarkFact] = .string(remarked) }
        // An aside it held up: what the counts read.
        if let asided { facts["aside"] = .string(asided) }
        // An invite this Moment asked, or skipped for the misses: what the
        // ledger reads.
        if spoken == nil { facts.merge(invitedFacts) { _, new in new } }
        if let wishing { facts["wish"] = .string(wishing.rawValue) }
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
        let answer = reply == "status" ? status(said) : nil
        let p = answers[Signs.questionKey]?.probabilities ?? [:]
        let liked = mine.filter { (p[$0] ?? 0) > 0 }.max { p[$0]! < p[$1]! }
        let sign = reply == "status" ? answer?.sign
            : liked ?? Signs.reply(replies, reply, calendar: tags, avoiding: lastSign, rng: &takes)
        return (sign, answer?.show)
    }
}
