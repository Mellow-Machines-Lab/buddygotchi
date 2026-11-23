import Foundation
import MellowHarness

/// Boop's buddy in the world, on the runtime's `home` queue: it joins,
/// sends the buddy's state on a change, batches the counts, heartbeats,
/// turns the gestures that come back into `world` events
/// (`WorldGestures`), and fetches the world while the World tab is open.
/// Nothing is sent while the world is off, or before onboarding's world
/// screen was answered. What's sent is `World.State`, and only that. The
/// gestures waiting come back in every send's reply, the heartbeat's
/// included, and are asked for when you unlock.
public final class WorldLink {
    /// A send at most this often: the server's own limit.
    public static let minGapMs: Int64 = 10_000
    /// Counts wait at most this long for a change to go with.
    public static let countsWaitMs: Int64 = 3 * 60_000
    /// With nothing else to send, a heartbeat this often keeps the buddy
    /// awake and brings the gestures waiting.
    public static let heartbeatMs: Int64 = 10 * 60_000
    /// The most the app's quit waits for "asleep" to go, in seconds.
    public static let quitWait: TimeInterval = 2
    /// The world is fetched this often while the World tab is open.
    public static let fetchEveryMs: Int64 = 30_000
    /// After a failure, the next try waits this long, doubling to `maxBackoffMs`.
    public static let backoffMs: Int64 = 30_000, maxBackoffMs: Int64 = 15 * 60_000

    /// What the buddy is now, from the runtime: what a send says.
    public struct Now: Equatable, Sendable {
        public var name: String
        public var level: Int
        public var utcOffset: Int
        public var activity: World.Activity
        public var day: String
        public var xpToday: Int
        public var daysInARow: Int
        public var color: Int
        public var ringClosed: Bool { xpToday >= Growth.perDay }

        public init(name: String, level: Int, utcOffset: Int, activity: World.Activity, day: String, xpToday: Int,
                    daysInARow: Int = 0, color: Int = 0) {
            self.daysInARow = daysInARow
            self.color = color
            self.name = name
            self.level = level
            self.utcOffset = utcOffset
            self.activity = activity
            self.day = day
            self.xpToday = xpToday
        }

        /// Whether `self`, sent after `last`, is a change worth sending at once:
        /// what it's doing, a level, the ring closing, its name.
        func changes(from last: Now) -> Bool {
            activity != last.activity || level != last.level || name != last.name || utcOffset != last.utcOffset
                || color != last.color
                || (ringClosed && !last.ringClosed)
        }
    }

    /// The buddy's id and key, kept in the state folder, readable only by
    /// you, with the last `seq` sent, and a send that got no answer, sent
    /// again as it was, its `seq` and counts, so the server counts it once.
    /// Leaving, it's kept until the server says the buddy is gone, so a
    /// failed leave is tried again, never lost.
    struct Identity: Codable {
        var id: String
        var key: String
        var seq = 0
        var leaving: Bool? = nil
        var unanswered: Unanswered? = nil
        /// The last league week whose place was told on the board.
        var toldWeek: String? = nil

        struct Unanswered: Codable {
            var seq: Int
            var added: World.Counts
        }
    }

    /// The buddy in the world: joined, and not leaving.
    var member: Identity? { identity?.leaving == true ? nil : identity }

    /// What the popover shows of the world.
    public struct Status: Equatable, Sendable {
        /// In the world: joined, and the world on.
        public var joined = false
        /// The buddy's own id in the world, so its own dot isn't sent to.
        public var id: String?
        /// How the world shows the buddy's name, and whether it hid it.
        public var shownName: String?
        public var nameHidden = false
        /// The world, as the World tab last fetched it.
        public var league: World.League?
        /// The buddy card open now, as the server last said.
        public var profile: World.Profile?
        /// Last week's place, from a send's reply: Monday's moment.
        public var lastWeek: World.Place?
        /// The buddy's own medals, from a send's reply.
        public var medals: World.Profile.Medals?
        /// Why the world can't be reached now, in plain words.
        public var trouble: String?
        /// What other buddies did today, newest first.
        public var today: [Arrival] = []

        public init(joined: Bool = false, shownName: String? = nil, league: World.League? = nil, today: [Arrival] = []) {
            self.joined = joined
            self.shownName = shownName
            self.league = league
            self.today = today
        }
    }

    /// Something other buddies did, as the World tab lists it.
    public struct Arrival: Equatable, Sendable, Identifiable {
        public var counts: [Count]
        public var region: World.Region?
        public var held: Bool
        public var plays: Bool
        public var at: Date
        /// The buddy that sent it, when one did: its card's id and its name.
        public var fromID: String?
        public var fromName: String?
        public let id = UUID()

        public struct Count: Equatable, Sendable {
            public var kind: World.GestureKind
            public var n: Int

            public init(kind: World.GestureKind, n: Int) {
                self.kind = kind
                self.n = n
            }
        }

        public init(counts: [Count], region: World.Region?, held: Bool = false, plays: Bool = true, at: Date,
                    fromID: String? = nil, fromName: String? = nil) {
            self.fromID = fromID
            self.fromName = fromName
            self.counts = counts
            self.region = region
            self.held = held
            self.plays = plays
            self.at = at
        }

        /// "Someone in the Americas booped Mochi."
        public func sentence(name: String) -> String {
            World.sentence(counts.map { ($0.kind, $0.n) }, from: region, by: fromName, held: held, name: name)
        }
    }

    let client: WorldClient
    let file: URL
    let waitingFile: URL
    let log: (String) -> Void
    var identity: Identity?
    public private(set) var status = Status()
    /// Counts added since the last send that went through.
    var pending = World.Counts()
    var pendingSince: Int64?
    var last: Now?
    var lastSentAt: Int64?
    var busy = false
    var retryAt: Int64?
    var backoff: Int64 = 0
    /// Left while a join was on its way: the buddy it makes leaves at once.
    var leaveWanted = false
    /// The screen locked: the buddy is asleep in the world until you unlock
    /// or come back, and "asleep" goes as soon as nothing else is on its way.
    var asleepDue = false
    var tabOpen = false
    var fetching = false
    var lastFetchAt: Int64?
    var gestures: WorldGestures
    var todayDay: String?
    /// Events to log, from gestures that came (`Pipeline.world`).
    public var onEvents: ([Event]) -> Void = { _ in }
    /// Something the popover shows changed.
    public var onChange: () -> Void = {}

    public static let fileName = "world.json", waitingFileName = "world-waiting.json"

    public init(client: WorldClient, stateDir: URL, log: @escaping (String) -> Void = { _ in }) {
        self.client = client
        file = stateDir.appendingPathComponent(Self.fileName)
        waitingFile = stateDir.appendingPathComponent(Self.waitingFileName)
        self.log = log
        identity = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Identity.self, from: $0) }
        gestures = WorldGestures(waiting: (try? Data(contentsOf: waitingFile)).flatMap { try? JSONDecoder().decode([World.Gesture].self, from: $0) } ?? [])
        status.joined = member != nil
        status.id = member?.id
    }

    /// The key, readable only by you from the moment it's written; gone
    /// with the identity.
    func save() {
        guard let identity else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        guard let data = try? JSONEncoder().encode(identity) else { return }
        let next = file.appendingPathExtension("new")
        try? FileManager.default.removeItem(at: next)
        guard FileManager.default.createFile(atPath: next.path, contents: data, attributes: [.posixPermissions: 0o600]),
              rename(next.path, file.path) == 0 else {
            return log("world: can't keep the buddy's key")
        }
    }

    /// The gestures waiting for you, kept so a quit doesn't lose them.
    func saveWaiting() {
        if gestures.waiting.isEmpty { try? FileManager.default.removeItem(at: waitingFile); return }
        try? JSONEncoder().encode(gestures.waiting).write(to: waitingFile, options: .atomic)
    }

    /// An event as it's logged: an agent's turn, a check that passed, a
    /// push, the lines an edit changed, which the next send adds.
    public func heard(_ e: Event, at now: Int64) {
        var add = World.Counts()
        if e.from == .claude || e.from == .codex {
            if e.kind == Event.kind(.turn, .end) { add.turns = 1 }
            if e.kind == Event.kind(.tool, .end) {
                add.linesChanged = Int((e["lines_added"]?.int ?? 0) + (e["lines_removed"]?.int ?? 0))
            }
        }
        if e.type == .act, e.phase == .end, e["passed"]?.bool == true {
            if e.specificType == "tests" { add.testsPassed = 1 }
            if e.specificType == "push" { add.ships = 1 }
        }
        guard !add.isEmpty, member != nil else { return }
        pending = pending + add
        if pendingSince == nil { pendingSince = now }
    }

    /// Every tick: what to send or fetch at `now`, on Boop day `today`.
    /// `on`: the world's switch, and onboarding's world screen answered.
    /// `quiet`: night, or you're away, so gestures wait. `me` is worked out
    /// only when something may be sent.
    public func tick(_ me: @autoclosure () -> Now, on: Bool, quiet: Bool, today: String, at now: Int64) {
        if todayDay != today {
            todayDay = today
            status.today = []
        }
        if on, !quiet { record(gestures.release(at: now)) }
        fetchIfDue(at: now)
        guard !busy, retryAt.map({ now >= $0 }) ?? true else { return }
        if let leaving = identity, leaving.leaving == true { return goodbye(leaving, at: now) }
        guard on else { return }
        var me = me()
        if asleepDue { me.activity = .asleep }
        guard let identity else { return join(me, at: now) }
        if asleepDue, last?.activity != .asleep { return send(me, identity: identity, quiet: true, at: now) }
        let gap = lastSentAt.map { now - $0 } ?? .max
        let due = identity.unanswered != nil || last.map { me.changes(from: $0) } ?? true
            || pendingSince.map { now - $0 >= Self.countsWaitMs } == true
            || gap >= Self.heartbeatMs
        if due, gap >= Self.minGapMs { send(me, identity: identity, quiet: quiet, at: now) }
    }

    /// You came back or unlocked: you're awake, and what's waiting is asked
    /// for now, with the world on and nothing to wait for.
    public func checkGestures(on: Bool, quiet: Bool, at now: Int64) {
        asleepDue = false
        guard on, let member, !busy, retryAt.map({ now >= $0 }) ?? true else { return }
        ask(member, quiet: quiet, at: now)
    }

    func join(_ me: Now, at now: Int64) {
        busy = true
        client.join(name: me.name, utcOffset: me.utcOffset) { [weak self] result in
            guard let self else { return }
            busy = false
            switch result {
            case .success(let joined):
                identity = Identity(id: joined.id, key: joined.key)
                backoff = 0
                retryAt = nil
                status.trouble = nil
                if leaveWanted {
                    // Kept private while it joined: it leaves straight away.
                    leaveWanted = false
                    log("world: joined as you left; leaving")
                    return leave(at: now)
                }
                save()
                status.joined = true
                status.id = joined.id
                status.shownName = joined.name
                log("world: joined as \(joined.name)")
                onChange()
            case .failure(let failure):
                leaveWanted = false
                failed(failure, at: now)
            }
        }
    }

    func send(_ me: Now, identity: Identity, quiet: Bool, at now: Int64) {
        var identity = identity
        // One the server may have counted goes again as it was; else a new seq.
        let sending = identity.unanswered ?? Identity.Unanswered(seq: identity.seq + 1, added: pending)
        identity.seq = sending.seq
        identity.unanswered = sending
        self.identity = identity
        save()
        let state = World.State(seq: sending.seq, name: me.name, level: me.level,
                                utcOffset: me.utcOffset, activity: me.activity, day: me.day, xpToday: me.xpToday, added: sending.added,
                                daysInARow: me.daysInARow, color: me.color)
        busy = true
        client.send(state, key: identity.key) { [weak self] result in
            guard let self else { return }
            busy = false
            guard self.identity?.key == identity.key, self.identity?.leaving != true else { return }  // left meanwhile
            switch result {
            case .success(let reply):
                self.identity?.unanswered = nil
                save()
                // A retry the server had counted kept the first try's body:
                // this one's state goes again with the next seq.
                last = reply.duplicate == true ? nil : me
                lastSentAt = now
                // What arrived since the send was made stays for the next.
                pending = pending - sending.added
                pendingSince = pending.isEmpty ? nil : now
                backoff = 0
                let shown = reply.name ?? status.shownName
                if shown != status.shownName || (reply.nameHidden ?? false) != status.nameHidden || status.trouble != nil {
                    status.shownName = shown
                    status.nameHidden = reply.nameHidden ?? false
                    status.trouble = nil
                    onChange()
                }
                if reply.lastWeek != status.lastWeek || (reply.medals != nil && reply.medals != status.medals) {
                    status.lastWeek = reply.lastWeek
                    status.medals = reply.medals ?? status.medals
                    onChange()
                }
                tellLastWeek(reply.lastWeek, quiet: quiet, at: now)
                arrived(reply.gestures ?? [], quiet: quiet, at: now)
            case .failure(let failure):
                failed(failure, at: now)
            }
        }
    }

    func ask(_ identity: Identity, quiet: Bool, at now: Int64) {
        busy = true
        client.gestures(key: identity.key) { [weak self] result in
            guard let self else { return }
            busy = false
            guard member?.key == identity.key else { return }  // left meanwhile: they're dropped
            switch result {
            case .success(let came): arrived(came, quiet: quiet, at: now)
            case .failure(let failure): failed(failure, at: now)
            }
        }
    }

    func arrived(_ came: [World.Gesture], quiet: Bool, at now: Int64) {
        record(gestures.arrived(came, quiet: quiet, at: now))
        if !came.isEmpty { saveWaiting() }
    }

    /// Last week's place, once a week: a `world` event of its own, which the
    /// rules turn into Monday's moment. While quiet (night, away, needs you)
    /// it waits for a later send's reply, which carries it again.
    func tellLastWeek(_ place: World.Place?, quiet: Bool, at now: Int64) {
        guard let place, !quiet, identity?.toldWeek != place.week else { return }
        identity?.toldWeek = place.week
        save()
        onEvents([Event(at: now, source: .world, type: .world, specificType: World.leagueKind,
                        data: ["place": .int(Int64(place.place)), "xp": .int(Int64(place.xp)), "of": .int(Int64(place.of)),
                               "week": .string(place.week)])])
    }

    func record(_ events: [Event]) {
        guard !events.isEmpty else { return }
        for e in events {
            status.today.insert(Arrival(counts: WorldGestures.counts(of: e).map { Arrival.Count(kind: $0.0, n: $0.1) },
                                        region: (e["from_region"]?.string).flatMap(World.Region.init(rawValue:)),
                                        held: e["held"]?.bool == true, plays: e["plays"]?.bool != false,
                                        at: Date(), fromID: e["from_id"]?.string, fromName: e["from_name"]?.string), at: 0)
        }
        if status.today.count > Self.arrivalsKept { status.today.removeLast(status.today.count - Self.arrivalsKept) }
        if events.contains(where: { $0["held"]?.bool == true }) { saveWaiting() }
        onEvents(events)
        onChange()
    }

    func failed(_ failure: WorldClient.Failure, at now: Int64) {
        if case .status(429, let after?, _) = failure {
            // Too soon: the same send goes again then, as it was.
            retryAt = now + Int64(after) * 1000
            return
        }
        backoff = min(Self.maxBackoffMs, max(Self.backoffMs, backoff * 2))
        retryAt = now + backoff
        if case .status(400, _, _) = failure, identity?.unanswered != nil {
            // The server won't take that body, so it can't go again as it
            // was: the next send is a new one, with what's waiting now.
            log("world: the server refused a send (\(failure)); the next one starts afresh")
            identity?.unanswered = nil
            save()
        }
        if failure.forgotten, identity?.leaving != true {
            // The world forgot this buddy (30 days unseen, or left
            // elsewhere): it joins again as new, after the backoff.
            log("world: the server doesn't know this buddy; joining again in \(backoff / 1000) s")
            identity = nil
            save()
            last = nil
            status.joined = false
            status.id = nil
            onChange()
            return
        }
        if status.trouble != Self.troubleWords {
            status.trouble = Self.troubleWords
            log("world: \(failure); trying again in \(backoff / 1000) s")
            onChange()
        }
    }

    /// The World tab opened or closed: the world is fetched only while it's open.
    public func tab(open: Bool, at now: Int64) {
        tabOpen = open
        guard open else {
            // Fetched afresh next time: nothing stale shows, or is kept.
            lastFetchAt = nil
            if status.league != nil || status.profile != nil {
                status.league = nil
                status.profile = nil
                onChange()
            }
            return
        }
        fetchIfDue(at: now)
    }

    /// The day's arrivals the World tab keeps, newest first.
    static let arrivalsKept = 50

    /// Why the world can't be reached, as the World tab says it.
    static let troubleWords = "Can't reach the world right now."

    func fetchIfDue(at now: Int64) {
        guard tabOpen, !fetching, lastFetchAt.map({ now - $0 >= Self.fetchEveryMs }) ?? true else { return }
        fetching = true
        lastFetchAt = now
        client.league(key: member?.key) { [weak self] result in
            guard let self else { return }
            fetching = false
            guard tabOpen else { return }
            switch result {
            case .success(let league):
                status.league = league
                if identity == nil || !busy { status.trouble = nil }
            case .failure:
                status.trouble = Self.troubleWords
            }
            onChange()
        }
    }

    /// Opens a buddy's card: its profile, fetched; nil closes it.
    public func open(_ id: String?) {
        guard let id else {
            if status.profile != nil { status.profile = nil; onChange() }
            return
        }
        client.profile(id, key: member?.key) { [weak self] result in
            guard let self, tabOpen, case .success(let profile) = result else { return }
            status.profile = profile
            onChange()
        }
    }

    /// A boop, wave, heart or cheer for another buddy. `done` says whether it went.
    public func gesture(_ kind: World.GestureKind, to buddy: String, _ done: @escaping (Bool) -> Void) {
        guard let member else { return done(false) }
        client.gesture(kind, to: buddy, key: member.key) { done((try? $0.get()) != nil) }
    }

    /// The screen locked: "asleep", at once, even within `minGapMs` of the
    /// last send, or as soon as one on its way has its answer.
    public func sleep(_ me: Now, on: Bool, at now: Int64) {
        guard on, let identity = member, last?.activity != .asleep else { return }
        asleepDue = true
        guard !busy else { return }
        var asleep = me
        asleep.activity = .asleep
        send(asleep, identity: identity, quiet: true, at: now)
    }

    /// The app quits: "asleep", waiting at most `quitWait` for it to go, so
    /// the world needn't wait 15 minutes to see it. A new seq, with the
    /// counts not yet sent; a send with no answer's are given up rather
    /// than counted twice. Counts aren't kept across a quit.
    public func quit(_ me: Now, on: Bool) {
        guard on, var identity = member, last?.activity != .asleep || !pending.isEmpty else { return }
        let added = identity.unanswered.map { pending - $0.added } ?? pending
        identity.seq = max(identity.seq, identity.unanswered?.seq ?? 0) + 1
        identity.unanswered = nil
        self.identity = identity
        save()
        let state = World.State(seq: identity.seq, name: me.name, level: me.level,
                                utcOffset: me.utcOffset, activity: .asleep, day: me.day, xpToday: me.xpToday, added: added,
                                daysInARow: me.daysInARow, color: me.color)
        guard client.sendNow(state, key: identity.key, timeout: Self.quitWait) else {
            return log("world: asleep didn't go before the quit")
        }
        // Gone: a second stop (a restart's, then the quit's) has nothing to send.
        var asleep = me
        asleep.activity = .asleep
        last = asleep
        pending = World.Counts()
    }

    /// Leaves the world: the buddy is deleted on the server, and its key
    /// here once it's gone. Nothing more is sent until the world is
    /// switched on again; gestures still on their way, or waiting for you,
    /// are dropped. Left
    /// while it was joining, it leaves as the join comes back.
    public func leave(at now: Int64) {
        guard var leaving = identity, leaving.leaving != true else {
            if identity == nil, busy { leaveWanted = true }
            return
        }
        leaving.leaving = true
        identity = leaving
        save()
        status = Status(league: status.league)
        last = nil
        pending = World.Counts()
        pendingSince = nil
        asleepDue = false
        retryAt = nil
        gestures.drop()
        saveWaiting()
        onChange()
        if !busy { goodbye(leaving, at: now) }
    }

    /// Deletes the buddy on the server, and its key here once the server
    /// says it's gone (or never knew it); a failure tries again later.
    func goodbye(_ leaving: Identity, at now: Int64) {
        busy = true
        client.leave(key: leaving.key) { [weak self] result in
            guard let self else { return }
            busy = false
            switch result {
            case .success, .failure(.status(401, _, "unauthorized")):
                if identity?.key == leaving.key { identity = nil }
                save()
                backoff = 0
                log("world: left")
            case .failure(let failure):
                backoff = min(Self.maxBackoffMs, max(Self.backoffMs, backoff * 2))
                retryAt = now + backoff
                log("world: leaving: \(failure); trying again in \(backoff / 1000) s")
            }
        }
    }
}
