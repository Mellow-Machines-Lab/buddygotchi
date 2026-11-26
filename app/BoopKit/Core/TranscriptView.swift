import AgentHooks
import Foundation
import MellowHarness

/// One event with its line, as Boop's pipeline reports what an input made:
/// for `debug.jsonl`'s `view` lines, replays and
/// tests. MellowHarness keeps the line itself; this
/// adds what Boop worked out about it.
public struct ViewEvent: Equatable, Sendable {
    /// What the rules did about it by the end of the input that made it.
    public struct Did: Equatable, Sendable {
        public var message: String
        /// `rule`, `brain` or `dashboard`.
        public var by: String
        public var seq: Int
    }

    /// The `seq` of the event it is.
    public var id: Int
    public var type: Event.Kind
    public var phase: Event.Phase?
    /// The raw events it came from; the last is the one that made it.
    public var from: [Int]
    public var ts: Int64
    public var line: String
    public var notes: [String] = []
    /// Whether it wakes the brain: its kind's `wake`, a brain, and nothing
    /// holding it back when it came.
    public var wakesBrain: Bool
    /// The thread it's about, as the view keys threads; nil for pokes,
    /// what you said and idle check-ins.
    public var about: String?
    /// For logs, evals and tests; the brain never sees them.
    public var facts: [String: JSONValue] = [:]
    public var did: [Did] = []

    /// The raw event that made it.
    public var seq: Int { from.last ?? 0 }

    /// `turn end`, `tool wait`, `poke`: its type and phase.
    public var name: String { phase.map { "\(type.rawValue) \($0.rawValue)" } ?? type.rawValue }

    /// The view event as one JSON object, for `debug.jsonl`.
    public var json: [String: Any] {
        var o: [String: Any] = ["id": id, "type": type.rawValue, "from": from, "line": line, "notes": notes,
                                "wakes_brain": wakesBrain, "facts": facts.mapValues(\.foundation)]
        if let phase { o["phase"] = phase.rawValue }
        return o
    }

    /// `turn end · claude finished …`, for debug mode and replays.
    public var summary: String {
        "\(name)\(wakesBrain ? "" : " (no pass)") · \(line)" + notes.map { " · \($0)" }.joined()
    }
}

/// Boop's lines: MellowHarness's transforms for the
/// kinds the brain hears of, their wakes and holds, and the check-ins'
/// timed checks, registered on MellowHarness's `Harness` (`register`). Each line
/// is a function of the log up to its event: the agents' lines need each
/// thread's turn so far (which turn, how long, its tool calls, failure
/// runs), which a fold of the log keeps (`Fold`), caught up to whatever
/// event it's asked about, so its answer depends on the log alone. Its
/// sessions are agent-hooks' `SessionTracker`, as the core's are, fed the
/// same events and run to the same times, so the two agree; the fold adds
/// only what each turn did. The rest look back at the log. Touched only on
/// the runtime's queue.
public final class TranscriptView {
    /// What a thread's turn did, which the session table doesn't keep:
    /// its tool calls, topics and checks, and each check's failures in a
    /// row.
    struct Counts {
        /// This turn's tool calls, how many failed, and how many only
        /// looked: a read, a search, the web, a command that only inspects.
        var tools = 0
        var toolsFailed = 0
        var looks = 0
        /// The lines this turn's edits added and removed: counts, never
        /// the text.
        var linesAdded = 0, linesRemoved = 0
        /// This turn's topics, in the order first seen, with their last state.
        var topicStates: [(topic: String, state: String)] = []
        /// A topic that passed after failing this turn.
        var comeback: String?
        /// The latest such pass: its event, when, and the Moment that
        /// answered it, while that Moment hasn't failed to play.
        var fix: (seq: Int, at: Int64, did: Int?)?
        /// This turn's latest topic, and its last check and whether it failed.
        var topic: String?
        var check: (topic: String, failed: Bool)?
        /// Failures in a row of each check topic, across turns.
        var failRuns: [String: InARow] = [:]
        /// This turn's failed checks, which a failed finish counts.
        var checksFailed = 0
        /// Quick wins in a row on the thread, across turns: finishes done
        /// in under `quickWinMs`.
        var wins = InARow()
        /// The calls that climb the work stream's failure ladder.
        var failing = InARow()
        /// This turn's working check-ins.
        var checkIns = 0
        /// The work stream's moments that hit Boop this turn
        /// (`WorkStream.hits`), and how many of them a line has said.
        var hits: [String] = []
        var hitsSaid = 0
    }

    /// A thread as the lines name it: its session's agent, project and
    /// workspace, and the turn it's on.
    struct Thread {
        var agent: Agent
        var id: String
        var project = "unknown"
        var workspace: String?
        var turn = 0

        var name: String { workspace ?? project }

        init(_ s: SessionTracker.Session) {
            self.init(agent: s.agent, id: s.id)
            project = s.project
            workspace = s.workspace
            turn = s.turn.number
        }

        /// A session the fold doesn't hold.
        init(agent: Agent, id: String) {
            self.agent = agent
            self.id = id
        }
    }

    /// Everything the lines need from the log so far, folded in order:
    /// a cache of a function of the log, never saved.
    struct Fold {
        /// The sessions, and what each one's turn did.
        var sessions: SessionTracker
        var counts: [String: Counts] = [:]
        /// The runs of pokes and of shakes going on.
        var pokes = InARow(), shakes = InARow()
        /// The away you haven't come back from, paired as the memory
        /// reader pairs it.
        var away = AwayAndBack()
        /// The newest dream not yet told (a `dream` event): the first line
        /// that's yours while you're at the Mac tells it.
        var untold: Event?
        /// The line that's telling it, until the moment it brought has
        /// played: its event, when it came, and the moment's `did`, once one
        /// started.
        var telling: (seq: Int, at: Int64, did: Int?)?
        /// The Boop day you last showed up on.
        var shownUp: String?
        /// Since when it lies face down, from the touch until anything
        /// that says it doesn't (`faceDown(_:)`); nil face up.
        var faceDownSince: Int64?
        /// The last agent event, poke, thing you said or coming back.
        var lastActivityAt: Int64?
        /// When the screen last locked, for the next lock's line.
        var lastLockAt: Int64?
        /// The last event folded, and whether the last agent event had a
        /// line: a request it answered says so only when it didn't.
        var at = 0
        var lastAgentLined = false
        /// The finishes whose last message's reading comes next, by
        /// session: its line, which the reading's adds to.
        var unread: [String: Line] = [:]
        /// The sessions whose "needs you" shows, and the latest finish of
        /// another while one did, with its session: nothing reacted to it
        /// then, so the request's clearing brings it back.
        var showing: Set<String> = []
        var missed: (key: String, line: Line)?
        /// The latest finish that could wake the brain, by the events that
        /// carry it, and its moment once made (`finishPlayed`): cut or
        /// refused while another's request shows, it's `missed` too.
        var finish: (seqs: Set<Int>, did: Int?, key: String, line: Line)?
        /// The turns that finished while you were away, for your coming back
        /// (`Notices.whileAway`).
        var whileAway: [(agent: String, thread: String, failed: Bool)] = []
        /// When things failed lately (a check, a turn), your last sharp
        /// prompt, and the threads with a prompt on Boop's day
        /// `promptedDay`: for `Notices`.
        var failures: [Int64] = []
        var sharpAt: Int64?
        var promptedDay: String?
        var promptedToday: Set<String> = []
        /// Each session's latest check or finished turn, by how it came
        /// out, for what Boop says when you ask (`StatusReply`).
        var results: [String: StatusReply.Result] = [:]
        /// What your latest prompt to each session asked for, its reading's
        /// kind, for "what's it doing?" (`StatusReply`).
        var asked: [String: PromptReading.Kind] = [:]

        /// Its tracker never asks whether an agent's process runs or its
        /// thread was archived: the core records a session that's gone as
        /// its end (`Core.sessionGone`), and one whose agent is gone as its
        /// turn stopping (`Core.agentGone`), so the fold depends on the log
        /// alone.
        init(place: @escaping (String) -> Place) {
            sessions = SessionTracker(place: place, isRunning: { _ in true }, archive: { _ in .open })
        }
    }

    /// The personality's settings: how often the working check-in comes
    /// and which tool uses wake the brain.
    public private(set) var rules: Personality.Rules
    let place: (String) -> Place
    var fold: Fold
    /// How many times the fold started over, asked about an event it had
    /// already folded (tests): never in the loop, whose transforms come in
    /// order, and a start over would miss what has aged out of memory.
    var refolds = 0

    /// The working check-in's schedule, Boop's own timer:
    /// when it's next due, nil until work starts and again once Boop starts
    /// a reaction (the newest `react` start it has seen), with its random
    /// waits.
    var nextWorkBeatAt: Int64?
    /// The idle check-in's schedule: the activity it follows, and when it's
    /// next due, drawn after that activity and after each check-in.
    var idleBeat: (after: Int64, due: Int64)?
    var reactSeen = 0
    var rng: SplitMix64

    public init(rules: Personality.Rules = Personality.Rules(), seed: UInt64 = 1,
                place: @escaping (String) -> Place = { Place.at(cwd: $0) }) {
        self.rules = rules
        self.place = place
        fold = Fold(place: place)
        rng = SplitMix64(seed: seed)
    }

    /// The topics whose failing command fails a turn.
    static let checks: Set<String> = ["tests", "build", "deploy"]

    /// A failed call that takes the work stream's failure ladder to this
    /// rung or the next (the third bonk, then the throw) is a line that wakes
    /// the brain: a stray failure is only a bonk, and past the top rung
    /// the bonks go quiet again.
    public static let wakingRungs = 3...4

    /// A finish done in under this is a quick win, which its line counts
    /// in a row (`InARow`).
    public static let quickWinMs: Int64 = 5 * 60_000

    /// A poke within this of the one before is another in a row.
    public static let inARowMs: Int64 = InARow.Kind.pokes.gapMs!
    /// The brain's reaction to this many pokes in a row or more answers the
    /// run; to fewer, the pokes after it still wake the brain, so Boop can
    /// go from glad to miffed to grumpy.
    public static let answersRunFrom = 3
    /// For this long after the last agent event, poke, thing you said or
    /// coming back, while a session is open and you're at the Mac, the
    /// idle check-in comes at the personality's `idle_heartbeat` pace
    /// instead: an idle check-in, so Boop has something to fidget at
    /// while you're around.
    public static let idleWindowMs: Int64 = 2 * 60 * 60 * 1000
    /// A new personality's settings, from the next event on. The working
    /// check-in starts its wait again at the new pace.
    public func setRules(_ rules: Personality.Rules) {
        self.rules = rules
        nextWorkBeatAt = nil
        idleBeat = nil
    }

    // MARK: - Registration

    /// Each kind's `wake`: what you said goes ahead
    /// of a finished turn, which goes ahead of the rest. A finish whose
    /// last message is being read keeps its line but waits for its
    /// reading to wake the brain (`hold`). Of the check-ins only the idle
    /// one wakes it: the working one is the rules' (`ruled`).
    public static let wakes: [String: Int] = [
        "prompt": 0, "turn_end": 1, "last_message": 1, "tool_end": 0, "poke": 0, "talk": 2, "presence_end": 0,
        "heartbeat": 0, "needs_you_end": 0, "gesture": 0, "ask": 2, "wish_end": 0, "act_start": 0, "act_end": 0,
    ]

    /// The kinds with lines that never wake the brain: a turn's start,
    /// which its prompt's reading speaks for; a BOOT press that opens an
    /// agent, the board's own reaction, as a tap that opens a thread is; an
    /// invite's end, whose payoff the board already played; and with
    /// `ruled`, what the rules answer whole.
    public static let quiet = ["turn_start", "presence_start", "needs_you_start", "press", "wish_start", "growth", "invite"] + ruled

    /// The kinds the rules answer with a Moment of their own and no pass
    /// (`MomentOutput.ruled`): your lock and unlock, and another buddy's
    /// gesture. The working check-in is theirs too, of a kind the idle
    /// one shares (`ruledCheckIn`).
    public static let ruled = ["lock_start", "lock_end", "world"]
    public static let ruledCheckIn = "heartbeat"

    /// Whether `e` is the rules' to answer, never the brain's.
    public static func isRuled(_ e: Event) -> Bool {
        e.type == .lock || e.type == .world || (e.type == .checkIn && e.specificType == "working")
    }

    /// Registers Boop's lines, wakes, holds and check-ins on `h`. Weakly:
    /// a harness its runtime let go of may still tick once, and does nothing.
    /// `needsYou` says why nothing but what you said may wake the brain now
    /// (something needs you on the board), or nil.
    public func register(on h: Harness, needsYou: @escaping () -> String?) {
        for (kind, wake) in Self.wakes {
            h.input(kind, wake: wake) { [weak self] e, log in self?.line(e, log) }
            h.hold(kind) { [weak self] e, log in self?.hold(e, log, needsYou: needsYou) }
        }
        for kind in Self.quiet {
            h.input(kind) { [weak self] e, log in self?.line(e, log) }
        }
        h.tick { [weak self] now, log in self?.checkIn(at: now, log) }
    }

    /// Why `e` may not wake the brain now, or nil if it may:
    /// nothing but what you said while something needs you; not a tap that
    /// opened a thread; and not a poke while the brain's reaction to its
    /// run is in progress, with the mood unchanged; and nothing but what
    /// you said while the buddy lies face
    /// down, which is do not disturb: the board would refuse a reaction.
    public func hold(_ e: Event, _ log: LogView, needsYou: () -> String?) -> String? {
        if e.type == .checkIn, e.specificType == "working" { return "the rules answer a working check-in" }
        return held(e, log, needsYou: needsYou)
    }

    /// Why nothing may answer `e` now, the brain or a rule's Moment
    /// (`MomentOutput.ruled`), or nil.
    public func held(_ e: Event, _ log: LogView, needsYou: () -> String?) -> String? {
        // What you say to Boop wakes the brain even while something needs
        // you; nothing else does, a poke included: then a tap opens the
        // waiting thread.
        if let type = e.type, type != .said, let why = needsYou() { return why }
        if Touch(e) == .facedown { return "\(name) is face down" }
        // An act's voice is for a push's result: a start only shows its
        // low sign, and a check's result has a line of its own when it
        // matters (a failure, a pass after one).
        if e.type == .act, e.phase == .start { return "the low sign names the command" }
        if e.type == .act, e.specificType != "push" { return "a check's result is its own line" }
        if e.type == .act, e["passed"]?.bool == false, e["topic"]?.string.map(Self.checks.contains) == true {
            return "the check's failure is its own line"
        }
        if e.type == .ask, e.specificType == Asks.ignored { return "nobody answered \(name)'s question" }
        if e.type == .world, e["plays"]?.bool == false { return "past the hour's world moments: the World tab counts it" }
        if e.type == .wish, e.specificType == Core.WishEnd.closed.rawValue { return "the day ended: \(name)'s wish closes quietly" }
        if e[PromptIntake.readingFollows]?.bool == true { return "its reading wakes the brain" }
        // Folded up to `e`, `e` included: a touch on the screen, a new
        // link or face down's age says it isn't face down now.
        for x in log.events(after: fold.at) where x.seq <= e.seq { _ = take(x) }
        if fold.faceDownSince != nil, e.type != .said { return "\(name) is face down" }
        guard e.type == .poke else { return nil }
        if log.dids(for: e.seq).contains(where: { $0.action == Core.openThread }) { return "the tap opened a thread" }
        if pokesAnswered(e, log) { return "\(name) is answering these pokes" }
        return nil
    }

    /// Whether the kinds `keeps` names have lines: turns'
    /// starts and ends, "needs you", pokes, what you said, you stepping
    /// away and coming back, locks and unlocks, and check-ins, and tool
    /// calls' ends when notable.
    public static func keeps(_ type: Event.Kind?, _ phase: Event.Phase?, notable: Bool) -> Bool {
        switch (type, phase) {
        case (.turn?, .start?), (.turn?, .end?), (.tool?, .wait?), (.poke?, nil), (.press?, nil), (.gesture?, nil), (.said?, nil), (.prompt?, nil),
             (.lastMessage?, nil), (.checkIn?, nil),
             (.presence?, .start?), (.presence?, .end?), (.lock?, .start?), (.lock?, .end?),
             (.needsYou?, .start?), (.needsYou?, .end?): true
        case (.tool?, .end?): notable
        default: false
        }
    }

    // MARK: - Folding

    /// Folds the log's events up to (not including) `seq` that the fold
    /// hasn't: all of them from the start again if it's past there.
    func catchUp(before seq: Int, _ log: LogView) {
        if fold.at >= seq {
            fold = Fold(place: place)
            refolds += 1
        }
        for e in log.events(after: fold.at) where e.seq < seq { _ = take(e) }
    }

    /// Folds everything in `log`.
    func catchUp(_ log: LogView) {
        for e in log.events(after: fold.at) { _ = take(e) }
    }

    /// The line for `e`, from the log before it (a transform), with `e`
    /// folded in.
    public func line(_ e: Event, _ log: LogView) -> Line? {
        catchUp(before: e.seq, log)
        return take(e)
    }

    /// The clock Boop's days go by: the pipeline's, before the first event.
    var time = LocalTime()

    /// The buddy's name: the pipeline sets it, before the first event.
    var name = CharacterPack.active.name

    /// Folds one event and returns its line, if it has one, with the
    /// dream under it when it's the one that tells it (`told`).
    func take(_ e: Event) -> Line? {
        faceDown(e)
        if e.type == .dream {
            fold.at = max(fold.at, e.seq)
            fold.untold = e
            fold.telling = nil
            return nil
        }
        played(e)
        reactedToFix(e)
        finishPlayed(e)
        return hello(foldLine(e), e)
    }

    /// App log lines: the pipeline sets them.
    var note: (String) -> Void = { _ in }

    /// Face down forgotten this long after the board said it, at the next
    /// event, if nothing said so before: half a day, longer than any
    /// meeting or afternoon of do not disturb, so only an end the Mac
    /// never heard reaches it. Too late costs everything: every pass is
    /// held, and Boop goes quiet. Too early costs little: the board itself
    /// refuses every Moment while it lies face down.
    public static let faceDownForgetMs: Int64 = 12 * 60 * 60_000

    /// Follows face down, as a function of the log: from the board's
    /// `facedown` until its end, a new link or hello (the Mac no longer
    /// knows which way up the board lies, and the board says it again if
    /// it still lies face down), what the board can't do face down
    /// (`turnedUp`), or `faceDownForgetMs`.
    func faceDown(_ e: Event) {
        if e.type == .gesture, e.specificType == Touch.facedown.rawValue {
            fold.faceDownSince = e.phase == nil ? e.at : nil
        } else if e.type == .link || Self.turnedUp(e) {
            fold.faceDownSince = nil
        } else if let since = fold.faceDownSince, e.at - since > Self.faceDownForgetMs {
            fold.faceDownSince = nil
            note("view: face down since \(time.day(since)) \(time.clock(since)), over \(Self.faceDownForgetMs / 3_600_000) h with no end heard: forgotten")
        }
    }

    /// Whether `e` says the board isn't lying face down, which the board
    /// senses only face up, whatever the Mac last heard:
    /// - a pick-up and its put-down: the motion sensor finds no pick-up
    ///   while it lies face down, so it was turned up first;
    /// - a finger on the screen, which lies against the desk face down: a
    ///   poke (not BOOT's), a stroke, a hold, a swipe, a finger held on
    ///   the needs-you screen, a row picked in the drawer, an invite
    ///   answered, an ask answered.
    /// Not a shake: the Mac reads a thump on the desk as one
    /// (`Touch.read`), and the sensor feels both face down. Not BOOT, on
    /// the board's edge, nor push-to-talk on it. The board's tilt never
    /// reaches the Mac.
    static func turnedUp(_ e: Event) -> Bool {
        switch e.type {
        case .poke?: e["src"]?.string != Core.buttonSource
        case .gesture?: e.specificType != Touch.shake.rawValue
        case .press?: e.specificType == Core.drawerPick
        case .invite?: Touch.answering(e) != nil
        case .ask?: e.specificType != Asks.ignored
        default: false
        }
    }

    /// Your hello, as its line's facts: the one place that says what comes
    /// with you showing up (your coming back or, with none, a touch), which
    /// `MomentRule.hello` reads. The first time on a Boop day is marked
    /// (`firstTodayFact`): that hello plays whole, and the narration leads
    /// with the day's count. And at most one extra, the first that's there:
    /// on that first time, a special day's sign (`daySignFact`); else the
    /// dream not yet told (`told`); else what happened while you were away,
    /// which your coming back's line already carries (`noticedFact`).
    func hello(_ line: Line?, _ e: Event) -> Line? {
        guard var line, Self.showsUp(e), fold.away.since == nil else { return line }
        let today = time.boopDay(e.at)
        let first = fold.shownUp != today
        fold.shownUp = today
        if first { line.facts[Self.firstTodayFact] = true }
        if first, let sign = daySign(e.at) {
            line.facts[Self.daySignFact] = .string(sign)
            line.facts[Self.noticedFact] = nil
            return line
        }
        return told(line, e)
    }

    /// Today's special day's sign at a time, or nil: the pipeline sets it,
    /// from the core's calendar.
    var daySign: (Int64) -> String? = { _ in nil }

    /// A line's facts: it's the first time you show up today, and the
    /// special day's sign that hello holds up.
    public static let firstTodayFact = "first_today", daySignFact = "day_sign"

    /// Whether `e` is you showing up: back at the Mac, or a touch.
    static func showsUp(_ e: Event) -> Bool { (e.type == .presence && e.phase == .end) || Yours.touch(e) }

    /// How long a line that tells the dream waits for its moment to start
    /// before another may tell it: past a pass's deadline. A moment that
    /// started ends by itself, within `MomentOutput.openForMs`.
    static let tellingWaitMs: Int64 = 60_000

    /// Follows the moment that tells the dream: played through, or until
    /// your touch cut it (which `Reactions` reads as done, as you saw it
    /// begin), the dream has been told; failed (cut by a needs-you, refused,
    /// never sent), it's still to tell.
    func played(_ e: Event) {
        guard e.fromHarness, e.action == MomentOutput.outputName, let telling = fold.telling, let about = e.about else { return }
        if e.kind == Event.did, about == telling.seq {
            if e["ok"]?.bool == true { fold.telling?.did = e.seq } else { fold.telling = nil }
        } else if e.kind == Event.ended, about == telling.did {
            if e["outcome"]?.string == "done" { fold.untold = nil }
            fold.telling = nil
        }
    }

    /// How soon after a fix a finish is still the same win: the Moment that
    /// answered the fix is on the face, or only just gone.
    static let fixJustNowMs: Int64 = 60_000

    /// Follows the Moment that answers a check passing after failing, as
    /// `played` follows the telling's: made, it stands for that win, unless
    /// it failed to play (cut by a needs-you, refused, never sent).
    func reactedToFix(_ e: Event) {
        guard e.fromHarness, e.action == MomentOutput.outputName, let about = e.about else { return }
        for (key, c) in fold.counts {
            guard let fix = c.fix else { continue }
            if e.kind == Event.did, about == fix.seq {
                fold.counts[key]?.fix?.did = e["ok"]?.bool == true ? e.seq : nil
            } else if e.kind == Event.ended, about == fix.did, e["outcome"]?.string != "done" {
                fold.counts[key]?.fix?.did = nil
            }
        }
    }

    /// Tells the dream not yet told the first time you show up after it
    /// was dreamed: your coming back or, with none, your first touch (a
    /// poke or a care gesture). Never a prompt (it has its own sign), a
    /// word to the buddy (its reply's sign), an agent's event or a
    /// check-in, so it never plays to an empty room. It stays untold until
    /// the moment has played (`played`): a brain that failed or a needs-you
    /// doesn't lose it, and your next showing up tells it. Its facts say
    /// which dream, for the memory to mark it told, the reason and the
    /// dream's signs.
    func told(_ line: Line, _ e: Event) -> Line {
        var line = line
        guard let dream = fold.untold,
              let about = (dream["about"] ?? dream["weekday"])?.string, let sentence = dream["sentence"]?.string else { return line }
        if let telling = fold.telling, telling.did != nil || e.at - telling.at < Self.tellingWaitMs { return line }
        fold.telling = (e.seq, e.at, nil)
        let told = EventLine.dreamed(about: about, sentence: sentence, name: name)
        line.notes.append(told)
        line.facts["dream_day"] = dream["day"] ?? .null
        line.facts["dream_tags"] = dream["tags"] ?? .array([])
        line.facts["dream_told"] = .string(told)
        line.facts["dream_fact"] = dream["fact"] ?? .null
        line.facts[Self.noticedFact] = nil
        return line
    }

    /// Folds one event and returns its line, if it has one. The sessions'
    /// timers run to every event's time first, as the core's replay runs
    /// them.
    func foldLine(_ e: Event) -> Line? {
        fold.at = max(fold.at, e.seq)
        if e.kind == Event.did, e.action == WorkStream.action {
            // A word of the work stream that came forward: no line, and
            // counted for the turn's lines when it hit Boop.
            if let style = e["as"]?.string, WorkStream.hits.contains(style), let key = e["session"]?.string,
               fold.counts[key] != nil || fold.sessions.sessions[key] != nil {
                fold.counts[key, default: Counts()].hits.append(style)
            }
            return nil
        }
        if let a = AgentEvent(e) {
            let line = agentEvent(a)
            fold.lastAgentLined = line != nil
            // A finish whose last message is being read keeps its line for
            // its reading's to add to, and shows none of its own: HISTORY
            // has the one line for the finish, not the same twice.
            if let line, a.kind == .turn, a.phase == .end, e[PromptIntake.readingFollows]?.bool == true {
                fold.unread[a.key] = line
                return nil
            }
            // Its session's next turn: that finish is old news.
            if a.kind == .turn, a.phase == .start, fold.missed?.key == a.key { fold.missed = nil }
            if a.kind == .turn, a.phase == .start, fold.finish?.key == a.key { fold.finish = nil }
            if let line, a.kind == .turn, a.phase == .end { noteMissed(line, key: a.key, seq: e.seq) }
            return line
        }
        advance(to: e.at)
        switch e.type {
        case .session?, .turn?, .tool?, .subagent?: return nil
        case .poke?: return poke(e)
        case .press?:
            noteActivity(e.at)
            return Line(e.specificType == Core.drawerPick ? EventLine.picked(name: name) : EventLine.pressed(name: name))
        case .prompt?:
            return promptRead(e)
        case .lastMessage?:
            return messageRead(e)
        case .gesture?:
            noteActivity(e.at)
            if e.specificType == Core.dismissGesture { return Line(EventLine.dismissed(name: name), facts: ["gesture": .string(e.specificType)]) }
            if Touch(e) == .shake { return shake(e) }
            return Touch(e)?.line(name: name).map { Line($0, facts: ["gesture": .string(e.specificType)]) }
        case .said?: return talk(e)
        case .ask?:
            let question = e["question"]?.string ?? ""
            guard e.specificType != Asks.ignored, let answer = e["answer"]?.string else {
                return Line(EventLine.unanswered(question, name: name), facts: ["q": e["q"] ?? .null, "pick": .string(Asks.ignored)])
            }
            noteActivity(e.at)
            return Line(EventLine.answered(question, answer: answer, name: name),
                        facts: ["q": e["q"] ?? .null, "answer": .string(answer), "pick": .string(e.specificType),
                                "keeps": e["keeps"] ?? .bool(false)])
        case .invite?:
            guard let end = Moment.Invite.End(rawValue: e.specificType),
                  let pose = Skit.Invite.Pose(rawValue: e["pose"]?.string ?? ""),
                  let touch = Skit.Invite.Touch(rawValue: e["touch"]?.string ?? "") else { return nil }
            if end.isYours { noteActivity(e.at) }
            return Line(EventLine.invite(end, pose, touch, name: name), facts: ["invite": .string(end.rawValue)])
        case .presence?: return presence(e)
        case .lock?: return lock(e)
        case .checkIn?: return checkIn(e)
        case .needsYou?: return needs(e)
        case .growth?:
            let level = e["level"]?.int.map(Int.init), ring = e["ring"]?.bool == true
            return Line(EventLine.grew(level: level, ring: ring, name: name), facts: level.map { ["level": .int(Int64($0))] } ?? [:])
        case .world? where e.specificType == World.leagueKind:
            guard let place = e["place"]?.int, let xp = e["xp"]?.int else { return nil }
            return Line("Last week \(name) came \(World.ordinal(Int(place))) in the league, with \(xp) XP.",
                        facts: ["world": .string(World.leagueKind), "place": .int(place), "xp": .int(xp)])
        case .world?:
            let counts = WorldGestures.counts(of: e)
            guard let (kind, count) = counts.first else { return nil }
            return Line(World.sentence(counts, from: (e["from_region"]?.string).flatMap(World.Region.init(rawValue:)),
                                       by: e["from_name"]?.string, held: e["held"]?.bool == true, name: name),
                        facts: ["world": .string(kind.rawValue), "count": .int(Int64(count))])
        case .wish?:
            if e.phase == .start { return Core.WishKind(rawValue: e.specificType).map { Line(EventLine.wished($0, name: name)) } }
            guard let how = Core.WishEnd(rawValue: e.specificType), let kind = (e["kind"]?.string).flatMap(Core.WishKind.init(rawValue:)) else { return nil }
            let waited = e["waited_ms"]?.int ?? 0
            if how == .met { noteActivity(e.at) }
            return Line(EventLine.wishEnded(how, kind, waitedMs: waited, name: name),
                        facts: ["wish": .string(how.rawValue), "kind": .string(kind.rawValue), "waited_ms": .int(waited)])
        case .act?:
            guard let key = e["session"]?.string, let s = fold.sessions.sessions[key] else { return nil }
            let t = Thread(s), agent = t.agent.rawValue, thread = threadLine(t)
            let pack = CharacterPack.active
            let text = e.phase == .start
                ? EventLine.actStarted(agent: agent, kind: e.specificType, thread: thread, name: name, pack: pack)
                : EventLine.actEnded(agent: agent, kind: e.specificType, thread: thread, passed: e["passed"]?.bool ?? true, name: name, pack: pack)
            return Line(text, facts: ["act": .string(e.specificType), "thread": threadFacts(t)])
        case .listen?, .dream?, .memory?, .link?, .card?, nil: return nil
        }
    }

    // MARK: Agents

    /// Runs the sessions' timers due by `now` (`sparing`'s Codex request
    /// isn't shown: its event comes first), and lets go of what the turns
    /// of the sessions they forgot did.
    func advance(to now: Int64, sparing: String? = nil) {
        fold.sessions.advance(to: now, sparing: sparing)
        if fold.counts.keys.contains(where: { fold.sessions.sessions[$0] == nil }) {
            fold.counts = fold.counts.filter { fold.sessions.sessions[$0.key] != nil }
            fold.unread = fold.unread.filter { fold.sessions.sessions[$0.key] != nil }
            fold.results = fold.results.filter { fold.sessions.sessions[$0.key] != nil }
        }
        if fold.asked.keys.contains(where: { fold.sessions.sessions[$0] == nil }) {
            fold.asked = fold.asked.filter { fold.sessions.sessions[$0.key] != nil }
        }
    }

    func agentEvent(_ a: AgentEvent) -> Line? {
        let step = SessionFold.step(a)
        let now = a.at
        let key = a.key
        advance(to: now, sparing: key)
        let before = fold.sessions.sessions[key]
        // A hook that landed after its session ended, or a stale idle
        // notice, doesn't count.
        guard let change = fold.sessions.handle(a) else { return nil }
        // An agent gone stops its turn, and a session gone ends it, but
        // nobody did anything.
        let gone = a.hook == Core.agentGone || a.hook == Core.sessionGone
        if !gone { noteActivity(now) }
        guard let s = fold.sessions.sessions[key] else {
            fold.counts[key] = nil
            return nil
        }
        // A request, and a subagent's start, end or its own turn-level
        // hook, don't move the thread's turn; only the rules care.
        if step == .needsYou || SessionFold.subagentsOwn(a, step) { return nil }
        let t = Thread(s)
        var c = fold.counts[key] ?? Counts()
        defer { fold.counts[key] = c }

        switch step {
        case .turnStart:
            c.topic = nil
            resetCounts(&c)
            // The last finish's reading, if it's still to come, is too late:
            // the finish, which showed no line waiting for it, is heard
            // here, its plain line under this one.
            let missed = fold.unread.removeValue(forKey: key)
            return Line(EventLine.turnStart(agent: t.agent.rawValue, turn: t.turn, thread: threadLine(t)),
                        notes: missed.map { [$0.text] } ?? [], facts: ["thread": threadFacts(t)])
        case .activity:
            var topic = a.topic
            var line: Line?
            if case .callEnded = change {
                // A result may come without its call's topic: it's the
                // `PreToolUse`'s. One that landed after its turn ended
                // counts, but the turn stays over.
                let started = before?.turn.callStart(for: a)
                if topic == nil { topic = started?.topic }
                line = toolDone(&c, t, a, topic: topic, started: started?.at)
            }
            // A turn a call opens has counts of its own.
            if before?.turn.startedAt == nil, s.turn.startedAt != nil { resetCounts(&c) }
            if let topic { c.topic = topic }
            if let topic, let failed = a.failed, TranscriptView.checks.contains(topic) {
                c.check = (topic, failed)
                fold.results[key] = StatusReply.Result(topic: topic, outcome: failed ? "failed" : "passed", at: now)
            }
            return line
        case .turnEnd, .turnFailed, .turnStopped:
            // A finish with no turn open (a second `Stop`, one after the
            // turn stopped, or the first Boop hears from a session)
            // finishes nothing the fold saw.
            guard case .turnEnded(_, endedTurn: true) = change, let started = before?.turn.startedAt else { return nil }
            // An agent gone finished nothing: its turn just stops.
            if gone {
                c.check = nil
                return nil
            }
            let check = c.check
            c.check = nil
            // A turn the fold joined partway (it never saw a prompt) isn't
            // told: it can't say how long it ran or what it did.
            guard t.turn > 0 else { return nil }
            let outcome: String
            switch step {
            case .turnFailed: outcome = "failed"
            case .turnStopped: outcome = "stopped"
            default: outcome = check?.failed == true ? "failed" : "done"
            }
            fold.results[key] = StatusReply.Result(topic: nil, outcome: outcome, at: now)
            if outcome == "failed" { noteFailure(now) }
            if fold.away.since != nil { fold.whileAway.append((t.agent.rawValue, threadLine(t), outcome == "failed")) }
            if outcome == "done", now - started < Self.quickWinMs { c.wins.add(.quickWins, at: now) } else { c.wins.reset() }
            var line = turnEnded(t, c, outcome: outcome, error: step == .turnFailed ? a.error : nil, lengthMs: max(0, now - started), at: now)
            if let hits = newHits(&c, name: name) { line.notes.append(hits) }
            return line
        case .sessionStart, .sessionEnd, .needsYou, .subagentStart, .subagentEnd:
            return nil
        }
    }

    /// A turn starting, with a prompt or opened by a call: what it did
    /// starts from nothing, so a check from before it, such as a
    /// background helper's after the last `Stop`, isn't its outcome.
    func resetCounts(_ c: inout Counts) {
        c.tools = 0
        c.toolsFailed = 0
        c.looks = 0
        c.linesAdded = 0
        c.linesRemoved = 0
        c.topicStates = []
        c.comeback = nil
        c.fix = nil
        c.check = nil
        c.checksFailed = 0
        c.checkIns = 0
        c.hits = []
        c.hitsSaid = 0
    }

    /// A finished tool call: counted for the turn, and a line when it's
    /// notable.
    func toolDone(_ c: inout Counts, _ t: Thread, _ a: AgentEvent, topic: String?, started: Int64?) -> Line? {
        let failed = a.failed
        let tookMs = started.map { max(0, a.at - $0) }
        c.tools += 1
        if failed == true { c.toolsFailed += 1 }
        if Self.onlyLooks(a, topic: topic) { c.looks += 1 }
        if failed != true { c.linesAdded += a.linesAdded ?? 0; c.linesRemoved += a.linesRemoved ?? 0 }

        var failedBefore = 0
        var notable = false
        var rung = 0
        if WorkStream.climbs(a) {
            rung = c.failing.add(.failedCalls, at: a.at)
            notable = Self.wakingRungs.contains(rung)
        }
        if let topic {
            if TranscriptView.checks.contains(topic), let failed {
                failedBefore = c.failRuns[topic]?.count ?? 0
                if failed {
                    c.failRuns[topic, default: InARow()].add(.failedChecks, at: a.at)
                    c.checksFailed += 1
                    notable = true
                } else {
                    c.failRuns[topic] = nil
                    if failedBefore > 0 {
                        notable = true
                        c.comeback = topic
                        c.fix = (fold.at, a.at, nil)
                    }
                }
                setTopic(&c, topic, failed ? "failing" : "passing")
            } else if topic == "docs" {
                setTopic(&c, topic, "edited")
            }
        }
        guard TranscriptView.keeps(.tool, .end, notable: notable) else { return nil }
        let category = EventLine.category(ToolKind.of(a.tool))
        let result = failed.map { $0 ? "failed" : "ok" } ?? "unknown"
        let text = rung > 0
            ? EventLine.failing(agent: t.agent.rawValue, thread: threadLine(t), count: rung, name: name)
            : EventLine.check(agent: t.agent.rawValue, topic: topic!, thread: threadLine(t), failed: failed!,
                              inARow: failedBefore + 1)
        var facts: [String: JSONValue] = [
            "thread": threadFacts(t), "tool": .string(category), "tool_name": .of(a.tool),
            "tool_use_id": .of(a.toolUseID), "topic": .of(topic), "result": .string(result),
            "error": .of(a.error), "failed_before": .int(Int64(failedBefore)),
        ]
        if rung > 0 { facts["failing"] = .int(Int64(rung)) }
        if let tookMs {
            facts["took"] = .string(Band.length(ms: tookMs))
            facts["took_ms"] = .int(tookMs)
        }
        if a.subagent != nil, let type = a.subagentType { facts["subagent"] = .string(type) }
        return Line(text, facts: facts)
    }

    func setTopic(_ c: inout Counts, _ topic: String, _ state: String) {
        if let i = c.topicStates.firstIndex(where: { $0.topic == topic }) {
            c.topicStates[i].state = state
        } else {
            c.topicStates.append((topic, state))
        }
    }

    /// The note on the moments of the work stream that hit Boop since a
    /// line last said them, at most once a line: the brain hears of them
    /// at a pass it has anyway, never one each.
    func newHits(_ c: inout Counts, name: String) -> String? {
        guard c.hits.count > c.hitsSaid else { return nil }
        defer { c.hitsSaid = c.hits.count }
        return EventLine.hits(Array(c.hits[c.hitsSaid...]), name: name)
    }

    /// A finish: what the turn did, never the agent's words, which only
    /// its message's reading tells (`messageRead`).
    func turnEnded(_ t: Thread, _ c: Counts, outcome: String, error: String?, lengthMs: Int64, at now: Int64) -> Line {
        var topicFacts: [String: JSONValue] = [:]
        for (topic, state) in c.topicStates { topicFacts[topic] = .string(state) }
        let reactedToFix = outcome == "done" && c.fix?.did != nil && now - (c.fix?.at ?? now) < Self.fixJustNowMs
        let text = EventLine.turnEnd(agent: t.agent.rawValue, turn: t.turn, thread: threadLine(t), outcome: outcome,
                                     lengthMs: lengthMs, tools: c.tools, failedChecks: c.checksFailed,
                                     quickWins: c.wins.count,
                                     linesGone: c.linesRemoved - c.linesAdded, reactedToFix: reactedToFix ? name : nil)
        return Line(text, facts: ["thread": threadFacts(t), "outcome": .string(outcome), "error": .of(error),
                            "length": .string(Band.length(ms: lengthMs)), "length_ms": .int(lengthMs),
                            "tools": .int(Int64(c.tools)), "tools_failed": .int(Int64(c.toolsFailed)),
                            "looks": .int(Int64(c.looks)), "lines_added": .int(Int64(c.linesAdded)), "lines_removed": .int(Int64(c.linesRemoved)),
                            "checks_failed": .int(Int64(c.checksFailed)), "wins_in_a_row": .int(Int64(c.wins.count)),
                            "topics": .object(topicFacts), "comeback": .of(c.comeback), "reacted_to_fix": .bool(reactedToFix)])
    }

    /// Whether a call only looked: a read, a search, the web, or a command
    /// that only inspects. A turn of these alone answered you; it made nothing.
    static func onlyLooks(_ a: AgentEvent, topic: String?) -> Bool {
        switch a.toolKind {
        case .read?, .search?, .web?: return true
        case .shell?: return topic == Topic.inspect
        default: return false
        }
    }

    /// The thread's facts.
    func threadFacts(_ t: Thread) -> JSONValue {
        [
            "name": .string(t.name), "agent": .string(t.agent.rawValue), "turn": .int(Int64(t.turn)),
            "project": .string(t.project), "workspace": .of(t.workspace), "session": .string(t.id),
        ]
    }

    func threadLine(_ t: Thread) -> String { EventLine.thread(name: t.name, project: t.project) }

    func noteActivity(_ now: Int64) {
        fold.lastActivityAt = now
    }

    // MARK: Your prompt

    /// A prompt's fact: your first on its thread today.
    public static let firstHereTodayFact = "first_here_today"

    func noteFailure(_ at: Int64) {
        fold.failures = fold.failures.filter { at - $0 < Notices.roughWithinMs } + [at]
    }

    /// What's been failing lately and your last sharp prompt, for `Notices`.
    public func rough(_ log: LogView) -> (failures: [Int64], sharpAt: Int64?) {
        catchUp(log)
        return (fold.failures, fold.sharpAt)
    }

    /// Your prompt's reading, under its turn's thread: what you asked for,
    /// how long and how you sound, and your words for a sign as a note.
    func promptRead(_ e: Event) -> Line? {
        guard let reading = PromptReading(facts: e.data) else { return nil }
        noteActivity(e.at)
        let key = Self.about(e, facts: nil)
        if let key { fold.asked[key] = reading.kind }
        let t = key.flatMap { fold.sessions.sessions[$0] }.map(Thread.init)
        if reading.tone == .frustrated || reading.tone == .shouting { fold.sharpAt = e.at }
        var facts = e.data.merging(["thread": t.map(threadFacts) ?? .null]) { a, _ in a }
        if let t {
            let today = time.boopDay(e.at)
            if fold.promptedDay != today { (fold.promptedDay, fold.promptedToday) = (today, []) }
            if fold.promptedToday.insert(t.workspace ?? t.project).inserted { facts[Self.firstHereTodayFact] = true }
        }
        return Line(EventLine.asked(reading, agent: e.agent?.rawValue ?? "the agent", thread: t.map(threadLine)),
                    notes: EventLine.yourWords(reading.phrases).map { [$0] } ?? [], facts: facts)
    }

    // MARK: The agent's last message

    /// The agent's last message's reading: its finish's line, saying what
    /// the message claims and how it sounds, with its words for a sign
    /// added to its notes. None for a finish the fold didn't line.
    func messageRead(_ e: Event) -> Line? {
        guard let key = Self.about(e, facts: nil), let finish = fold.unread.removeValue(forKey: key),
              let reading = MessageReading(facts: e.data) else { return nil }
        let line = Line(EventLine.finished(finish.text, saying: reading),
                        notes: finish.notes + (EventLine.itsWords(reading.phrases).map { [$0] } ?? []),
                        facts: finish.facts.merging(["message": .object(reading.facts)]) { _, b in b })
        noteMissed(line, key: key, seq: e.seq)
        return line
    }

    /// A finish `line` of the session `key`, from the event `seq`: kept if
    /// another's "needs you" shows, as it can't wake the brain now; else
    /// followed until its moment has played (`finishPlayed`).
    func noteMissed(_ line: Line, key: String, seq: Int) {
        if !fold.showing.subtracting([key]).isEmpty {
            fold.missed = (key, line)
            fold.finish = nil
        } else {
            fold.finish = ((fold.finish?.key == key ? fold.finish?.seqs ?? [] : []).union([seq]), nil, key, line)
        }
    }

    /// Follows the moment for the latest finish, as `played` follows the
    /// telling's: refused, or cut on the board, while another's request
    /// shows (the request came after the finish), nothing celebrated it, so
    /// the request's clearing brings it back as it does one that came
    /// under the request.
    func finishPlayed(_ e: Event) {
        guard e.fromHarness, e.action == MomentOutput.outputName, let finish = fold.finish, let about = e.about else { return }
        let failed: Bool
        if e.kind == Event.did, finish.seqs.contains(about) {
            if e["ok"]?.bool == true {
                fold.finish?.did = e.seq
                return
            }
            failed = true
        } else if e.kind == Event.ended, about == finish.did {
            failed = e["outcome"]?.string != "done"
        } else {
            return
        }
        if failed, !fold.showing.subtracting([finish.key]).isEmpty { fold.missed = (finish.key, finish.line) }
        fold.finish = nil
    }

    // MARK: Pokes

    /// A poke, with how many came in a row.
    func poke(_ e: Event) -> Line {
        let now = e.at
        noteActivity(now)
        let count = fold.pokes.add(.pokes, at: now)
        // The first poke of a run wakes Boop; the rest find it awake.
        let asleep = count == 1 && (e["asleep"]?.bool ?? fold.sessions.sessions.isEmpty)
        return Line(EventLine.poke(inARow: count, name: name, asleep: asleep),
                    facts: ["in_a_row": .int(Int64(count)), "seconds": .int(Int64(fold.pokes.seconds)), "asleep": .bool(asleep)])
    }

    /// A shake, with how many came in a row.
    func shake(_ e: Event) -> Line {
        let count = fold.shakes.add(.shakes, at: e.at)
        return Line(EventLine.shake(inARow: count, name: name),
                    facts: ["gesture": .string(Touch.shake.rawValue), "in_a_row": .int(Int64(count)),
                            "seconds": .int(Int64(fold.shakes.seconds))])
    }

    /// Whether the brain's reaction to the run of pokes `e` is in (to
    /// `answersRunFrom` or more in a row, not to its first ones) is still
    /// in progress, and the mood hasn't changed since it started: then
    /// another poke of the run doesn't wake the brain. A
    /// reaction a tap cut short stays in progress while the pokes go on
    /// (held by the runtime's `Reactions` and react's `keepOpen`,
    /// `heldByPokes`).
    public func pokesAnswered(_ e: Event, _ log: LogView) -> Bool {
        var run: [Event] = [e]
        for p in log.all(Event.kind(.poke, nil)).reversed() where p.seq < e.seq {
            guard run.last!.at - p.at < Self.inARowMs else { break }
            run.append(p)
        }
        run.reverse()
        // The pokes the run's reactions can answer: from the third in a row.
        let answering = Set(run.dropFirst(Self.answersRunFrom - 1).map(\.seq))
        guard let reaction = log.lastDid(MomentOutput.outputName, where: {
            $0["open"]?.bool == true && $0.about.map(answering.contains) == true
        }) else { return false }
        guard log.ended(reaction.seq) == nil else { return false }
        return log.count(Event.did, since: reaction) { $0.action == MoodOutput.outputName && $0["ok"]?.bool == true } == 0
    }

    /// Whether `e` ends a run of pokes: anything but another poke of the
    /// run (within `inARowMs` of the one before), "needs you",
    /// push-to-talk's `listen` records, or MellowHarness's own events. Then
    /// the reactions a tap cut short end as done: `log` is the log before
    /// `e`.
    public static func stopsThePokes(_ e: Event, _ log: LogView) -> Bool {
        guard let type = e.type, !passesThePokes.contains(type) else { return false }
        guard type == .poke else { return true }
        return log.last(Event.kind(.poke, nil)).map { e.at - $0.at >= inARowMs } ?? true
    }

    /// The records that a run of pokes goes on through.
    static let passesThePokes: Set<Event.Kind> = [.needsYou, .listen, .link]

    /// Whether the reaction `did` is one your tap cut short that the pokes
    /// still hold: a poke came after it, and no
    /// event since that poke has stopped the pokes (`stopsThePokes`). While
    /// it is, MellowHarness keeps it open past react's `openFor` (react's
    /// `keepOpen`), as the app holds its handle, so a run of pokes longer
    /// than that, or the quiet after one, neither drops it from HISTORY nor
    /// gets the run a second reaction.
    public static func heldByPokes(_ did: Event, _ log: LogView) -> Bool {
        let after = log.events(after: did.seq)
        guard let cut = after.firstIndex(where: { $0.type == .poke }) else { return false }
        var lastPoke = after[cut].at
        for e in after[after.index(after: cut)...] {
            guard let type = e.type, !passesThePokes.contains(type) else { continue }
            guard type == .poke, e.at - lastPoke < inARowMs else { return false }
            lastPoke = e.at
        }
        return true
    }

    // MARK: Talk

    /// What you said to Boop on push-to-talk. Words
    /// that are only whitespace make no line.
    func talk(_ e: Event) -> Line? {
        guard let words = e["words"]?.string, let line = EventLine.said(words, to: name) else { return nil }
        noteActivity(e.at)
        return Line(line, facts: ["words": .string(words), "by": .string(e.specificType)])
    }

    // MARK: Here and away

    /// Whether you're away from the Mac, as the log has it: an away with no
    /// back yet. The presence detector starts from this at launch.
    public func away(_ log: LogView) -> Bool {
        catchUp(log)
        return fold.away.since != nil
    }

    /// You stepping away or coming back, as the presence detector decided:
    /// the view only pairs them. A back with no away
    /// before it makes no line.
    func presence(_ e: Event) -> Line? {
        switch fold.away.fold(e) {
        case .away(let since)?:
            fold.whileAway = []
            return Line(EventLine.away, facts: ["why": .string(e.specificType), "since": .int(since)])
        case .back(let ms?)?:
            noteActivity(e.at)
            var facts: [String: JSONValue] = ["away": .string(Band.away(ms: ms)), "away_ms": .int(ms)]
            if let noticed = Notices.whileAway(fold.whileAway) { facts[Self.noticedFact] = .string(noticed) }
            fold.whileAway = []
            return Line(EventLine.back(ms: ms), facts: facts)
        default:
            return nil
        }
    }

    /// The Mac's screen locked or unlocked. A lock says how long since the
    /// last, and an unlock how long it was locked; an unlock ending an away
    /// has no line, so no pass: the back that follows at your first touch is
    /// the one reaction. An unlock is you, so it's activity.
    func lock(_ e: Event) -> Line? {
        if e.phase == .start {
            let sinceLast = fold.lastLockAt.map { max(0, e.at - $0) }
            fold.lastLockAt = e.at
            return Line(EventLine.locked(sinceLastMs: sinceLast), facts: sinceLast.map { ["since_last_ms": .int($0)] } ?? [:])
        }
        noteActivity(e.at)
        guard fold.away.since == nil, let since = e["since"]?.int else { return nil }
        let ms = max(0, e.at - since)
        return Line(EventLine.unlocked(afterMs: ms), facts: ["locked_ms": .int(ms)])
    }

    // MARK: Check-ins

    /// The sessions working on a turn at `now`: working, as agent-hooks
    /// groups them and the core shows them, their timers run to then, with
    /// a turn open. A background helper working on after the main agent's
    /// `Stop` is no turn, so no working check-in speaks of it.
    func working(at now: Int64) -> [SessionTracker.Session] {
        advance(to: now)
        return fold.sessions.grouped(at: now).working.filter { $0.turn.startedAt != nil }
    }

    /// Whether any turn works at `now`, as `log` has it.
    public func isWorking(at now: Int64, _ log: LogView) -> Bool {
        catchUp(log)
        return !working(at: now).isEmpty
    }

    /// When the oldest turn still working began, or nil: HISTORY reaches
    /// back at least that far.
    public func workingSince(at now: Int64, _ log: LogView) -> Int64? {
        catchUp(log)
        return working(at: now).compactMap(\.turn.startedAt).min()
    }

    /// A check-in, if one is due at `now`, for MellowHarness to
    /// emit: while threads work, once the personality's wait has passed
    /// with no reaction from Boop; while none works and you're at the Mac,
    /// an idle one at the personality's pace, for `idleWindowMs` after the
    /// last agent event, poke, thing you said or coming back.
    public func checkIn(at now: Int64, _ log: LogView) -> Event? {
        catchUp(log)
        // Boop started a reaction: the working check-in starts its wait
        // again, so it comes after a stretch of work with no reaction,
        // however many events woke the brain in it.
        if let react = log.lastDid(MomentOutput.outputName, where: { $0["open"]?.bool == true }),
           react.seq > reactSeen {
            reactSeen = react.seq
            nextWorkBeatAt = nil
        }
        let working = !working(at: now).isEmpty
        if working, let gap = rules.workCheckInMs {
            guard let due = nextWorkBeatAt else {
                nextWorkBeatAt = now + Int64(rng.int(in: gap))
                return nil
            }
            guard now >= due else { return nil }
            nextWorkBeatAt = now + Int64(rng.int(in: gap))
            return Event(at: now, source: .clock, type: .checkIn, specificType: "working")
        }
        nextWorkBeatAt = nil
        guard !working, let last = fold.lastActivityAt else { return nil }
        // An idle check-in, at the personality's pace: you're at the Mac,
        // and it's within `idleWindowMs` of the last activity. With no
        // session open it comes `noAgentsGapTimes` as far apart, which spares
        // Jev. Once you're away, or it's been quiet longer than that, as over
        // a night or a weekend, none comes: moods fade by the clock
        // (`MoodOutput.fade`), and nothing reads the time of day.
        guard let idle = rules.idleCheckInMs, fold.away.since == nil, now - last < Self.idleWindowMs else { return nil }
        let times = fold.sessions.sessions.isEmpty ? Self.noAgentsGapTimes : 1
        let gap = (idle.lowerBound * times)...(idle.upperBound * times)
        if idleBeat?.after != last { idleBeat = (last, last + Int64(rng.int(in: gap))) }
        guard let beat = idleBeat, now >= beat.due else { return nil }
        idleBeat = (last, now + Int64(rng.int(in: gap)))
        return Event(at: now, source: .clock, type: .checkIn, specificType: "check_in")
    }

    /// How many times the personality's gap an idle check-in waits with no
    /// session open.
    public static let noAgentsGapTimes = 2

    /// Whether you're away from the Mac, as the presence events say.
    public var away: Bool { fold.away.since != nil }

    func checkIn(_ e: Event) -> Line? {
        let now = e.at
        let working = working(at: now)
        if let s = working.min(by: { ($0.turn.startedAt ?? now, $0.order) < ($1.turn.startedAt ?? now, $1.order) }) {
            let t = Thread(s)
            let ms = max(0, now - (s.turn.startedAt ?? now))
            // Each check-in on a turn is counted: the rule's Moment for
            // it goes by its rung of a round (`MomentRule.checkIn`).
            var c = fold.counts[s.key] ?? Counts()
            c.checkIns += 1
            let hits = newHits(&c, name: name)
            fold.counts[s.key] = c
            return Line(EventLine.working(agent: t.agent.rawValue, thread: threadLine(t), ms: ms, topic: c.topic),
                        notes: hits.map { [$0] } ?? [],
                        facts: ["thread": threadFacts(t), "working_ms": .int(ms), "topic": .of(c.topic),
                                "check_in": .int(Int64(c.checkIns))])
        }
        // An idle check-in: you're around, and no agent works. Any other
        // kind (an old transcript's hourly one) has no line.
        guard let last = fold.lastActivityAt, e.specificType == "check_in" else { return nil }
        let minutes = (now - last) / 60_000
        guard let s = fold.sessions.sessions.values.max(by: { ($0.lastEventAt, $0.order) < ($1.lastEventAt, $1.order) }) else {
            return Line(EventLine.idle(minutes: Int(minutes)), facts: ["idle_minutes": .int(minutes)])
        }
        let t = Thread(s)
        return Line(EventLine.idle(minutes: Int(minutes), agent: t.agent.rawValue, thread: threadLine(t)),
                    facts: ["thread": threadFacts(t), "idle_minutes": .int(minutes)])
    }

    // MARK: Needs you

    /// "Needs you" showing (the core's) is a line, and so is its clearing
    /// when you answered (allowed or denied it) and the agent works on,
    /// unless what answered it has a line of its own (tests failing right
    /// after you allowed them): one moment, one line. One that cleared for
    /// any other reason (forgotten, the session ended) or with the turn (a
    /// stop) isn't. Whether a
    /// session waits is the fold's own sessions', not these records'.
    func needs(_ e: Event) -> Line? {
        guard let agent = (e["agent"]?.string).flatMap(Agent.init(rawValue:)), let session = e.session else { return nil }
        let s = fold.sessions.sessions[SessionFold.key(agent, session)]
        let t = s.map(Thread.init) ?? Thread(agent: agent, id: session)
        let key = SessionFold.key(agent, session)
        if e.phase == .end {
            fold.showing.remove(key)
            // A finish nothing could react to while this showed: now that
            // nothing needs you, it's what the brain hears, so it gets its
            // finish, whose thread a tap opens.
            if fold.showing.isEmpty, let missed = fold.missed {
                fold.missed = nil
                noteActivity(e.at)
                return Line(missed.line.text, notes: missed.line.notes + [EventLine.finishedWhileYouWereBusy],
                            facts: missed.line.facts.merging([Self.missedFact: true]) { _, b in b })
            }
            guard e["outcome"]?.string == "done", s?.turn.startedAt != nil, !fold.lastAgentLined else { return nil }
            noteActivity(e.at)
            return Line(EventLine.answered(agent: agent.rawValue, thread: threadLine(t)), facts: ["thread": threadFacts(t)])
        }
        guard e.phase == .start else { return nil }
        fold.showing.insert(key)
        // The request's own event is a tool call's wait; "needs you"
        // showing is when it has a line, after Codex's grace.
        return Line(EventLine.needsYou(agent: agent.rawValue, thread: threadLine(t)), facts: ["thread": threadFacts(t)])
    }

    // MARK: Reading

    /// The thread an event is about, as the view keys threads: an agent's
    /// or "needs you"'s session, or the thread its line's facts name (a
    /// working check-in's); nil for the rest.
    public static func about(_ e: Event, facts: [String: JSONValue]?) -> String? {
        // A finish brought back by a request's clearing is its own thread's.
        if facts?[missedFact] == true, let key = thread(facts) { return key }
        if let agent = e.agent ?? (e["agent"]?.string).flatMap(Agent.init(rawValue:)), let session = e.session {
            return SessionFold.key(agent, session)
        }
        return thread(facts)
    }

    /// The session the line's `thread` fact names.
    static func thread(_ facts: [String: JSONValue]?) -> String? {
        guard let t = facts?["thread"]?.object, let agent = t["agent"]?.string.flatMap(Agent.init(rawValue:)),
              let id = t["session"]?.string else { return nil }
        return SessionFold.key(agent, id)
    }

    /// A line's fact: what's noticed at its moment (CONTEXT's Noticed row).
    public static let noticedFact = "noticed"

    /// The fact on a finish brought back once nothing needs you.
    static let missedFact = "while_needed"

    /// The thread `key` names: its agent, its name as its agent's app shows
    /// it once an event brought one, else as its lines name it (its
    /// workspace, else its project), and where it opens on the Mac.
    public func who(about key: String, _ log: LogView) -> (agent: String, thread: String, opens: ThreadRef)? {
        catchUp(log)
        return fold.sessions.sessions[key].map { ($0.agent.rawValue, StateSnapshot.boardName($0.name) ?? Thread($0).name, $0.thread) }
    }

    /// Each session's latest check or finished turn, caught up to `log`:
    /// how it came out, for what Boop says when you ask (`StatusReply`).
    public func results(_ log: LogView) -> [String: StatusReply.Result] {
        catchUp(log)
        return fold.results
    }

    /// What your latest prompt to each session asked for, caught up to
    /// `log`, by session.
    public func asked(_ log: LogView) -> [String: PromptReading.Kind] {
        catchUp(log)
        return fold.asked
    }

    /// The sessions as the fold has them, caught up to `log` (tests).
    func sessions(_ log: LogView) -> [String: SessionTracker.Session] {
        catchUp(log)
        return fold.sessions.sessions
    }

    /// A `ViewEvent` for `e` and its line, for what an input reports.
    func view(_ e: Event, _ line: Line, wakes: Bool, log: LogView) -> ViewEvent? {
        guard let type = e.type else { return nil }
        let (shownType, shownPhase) = type == .needsYou && e.phase == .start ? (Event.Kind.tool, Event.Phase.wait) : (type, e.phase)
        let from = type == .needsYou ? (e["for"]?.int.map { [Int($0), e.seq] } ?? [e.seq])
            : type == .presence && e.phase == .end ? [log.last(Event.kind(.presence, .start))?.seq, e.seq].compactMap { $0 }
            : [e.seq]
        return ViewEvent(id: e.seq, type: shownType, phase: shownPhase, from: from, ts: e.at, line: line.text, notes: line.notes,
                         wakesBrain: wakes,
                         about: Self.about(e, facts: line.facts),
                         facts: line.facts)
    }
}
