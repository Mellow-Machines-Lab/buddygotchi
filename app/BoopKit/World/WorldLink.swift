import Foundation
import MellowHarness

/// Boop's buddy in the world, on the runtime's `home` queue: it joins,
/// sends the buddy's state on a change, batches the counts, heartbeats,
/// turns the gestures that come back into `world` events
/// (`WorldGestures`), and fetches the world while the World tab is open.
/// Nothing is sent while the world is off, or before onboarding's world
/// screen was shown. What's sent is `World.State`, and only that.
public final class WorldLink {
    /// A send at most this often: the server's own limit.
    public static let minGapMs: Int64 = 10_000
    /// Counts wait at most this long for a change to go with.
    public static let countsWaitMs: Int64 = 3 * 60_000
    /// With nothing else to send, a heartbeat this often keeps the buddy awake.
    public static let heartbeatMs: Int64 = 10 * 60_000
    /// With nothing sent for this long, the gestures waiting are asked for.
    public static let gesturesEveryMs: Int64 = 10 * 60_000
    /// The world is fetched this often while the World tab is open.
    public static let fetchEveryMs: Int64 = 30_000
    /// After a failure, the next try waits this long, doubling to `maxBackoffMs`.
    public static let backoffMs: Int64 = 30_000, maxBackoffMs: Int64 = 15 * 60_000

    /// What the buddy is now, from the runtime: what a send says.
    public struct Now: Equatable, Sendable {
        public var name: String
        public var level: Int
        public var stage: String
        public var utcOffset: Int
        public var activity: World.Activity
        public var day: String
        public var xpToday: Int

        public init(name: String, level: Int, stage: String, utcOffset: Int, activity: World.Activity, day: String, xpToday: Int) {
            self.name = name
            self.level = level
            self.stage = stage
            self.utcOffset = utcOffset
            self.activity = activity
            self.day = day
            self.xpToday = xpToday
        }

        /// Whether `self`, sent after `last`, is a change worth sending at once:
        /// what it's doing, a level, the ring closing, its name.
        func changes(from last: Now) -> Bool {
            activity != last.activity || level != last.level || name != last.name || utcOffset != last.utcOffset
                || (xpToday >= Growth.perDay && last.xpToday < Growth.perDay)
        }
    }

    /// The buddy's id and key, kept in the state folder, readable only by
    /// you, with the last `seq` sent.
    struct Identity: Codable {
        var id: String
        var key: String
        var seq = 0
    }

    /// What the popover shows of the world.
    public struct Status: Equatable, Sendable {
        /// In the world: joined, and the world on.
        public var joined = false
        /// How the world shows the buddy's name, and whether it hid it.
        public var shownName: String?
        public var nameHidden = false
        /// The world, while the World tab is open, and when it was fetched.
        public var snapshot: World.Snapshot?
        public var fetchedAt: Date?
        /// Why the world can't be reached now, in plain words.
        public var trouble: String?
        /// What other buddies did today, newest first.
        public var today: [Arrival] = []

        public init(joined: Bool = false, shownName: String? = nil, snapshot: World.Snapshot? = nil, fetchedAt: Date? = nil,
                    today: [Arrival] = []) {
            self.joined = joined
            self.shownName = shownName
            self.snapshot = snapshot
            self.fetchedAt = fetchedAt
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
        public var id: String { "\(at.timeIntervalSince1970)-\(counts.map(\.kind.rawValue).joined())" }

        public struct Count: Equatable, Sendable {
            public var kind: World.GestureKind
            public var n: Int

            public init(kind: World.GestureKind, n: Int) {
                self.kind = kind
                self.n = n
            }
        }

        public init(counts: [Count], region: World.Region?, held: Bool = false, plays: Bool = true, at: Date) {
            self.counts = counts
            self.region = region
            self.held = held
            self.plays = plays
            self.at = at
        }

        /// "Someone in the Americas booped Mochi."
        public func sentence(name: String) -> String {
            World.sentence(counts.map { ($0.kind, $0.n) }, from: region, held: held, name: name)
        }
    }

    let client: WorldClient
    let file: URL
    let log: (String) -> Void
    var identity: Identity?
    public private(set) var status = Status()
    /// Counts added since the last send that went through.
    var pending = World.Counts()
    var pendingSince: Int64?
    var last: Now?
    var lastSentAt: Int64?
    var lastAskedAt: Int64?
    var busy = false
    var joining = false
    var retryAt: Int64?
    var backoff: Int64 = 0
    var tabOpen = false
    var fetching = false
    var lastFetchAt: Int64?
    var gestures = WorldGestures()
    var todayDay: String?
    /// Events to log, from gestures that came (`Pipeline.world`).
    public var onEvents: ([Event]) -> Void = { _ in }
    /// Something the popover shows changed.
    public var onChange: () -> Void = {}

    public static let fileName = "world.json"

    public init(client: WorldClient, stateDir: URL, log: @escaping (String) -> Void = { _ in }) {
        self.client = client
        file = stateDir.appendingPathComponent(Self.fileName)
        self.log = log
        identity = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Identity.self, from: $0) }
        status.joined = identity != nil
    }

    func save() {
        guard let identity else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        do {
            try JSONEncoder().encode(identity).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            log("world: can't keep the buddy's key: \(error)")
        }
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
        guard !add.isEmpty, identity != nil else { return }
        pending = pending + add
        if pendingSince == nil { pendingSince = now }
    }

    /// Every tick: what to send, ask for or fetch at `now`. `on`: the world's
    /// switch, and onboarding's world screen shown. `quiet`: night, or you're
    /// away, so gestures wait.
    public func tick(_ me: Now, on: Bool, quiet: Bool, today: String, at now: Int64) {
        if todayDay != today {
            todayDay = today
            status.today = []
        }
        if !quiet { record(gestures.release(at: now), at: now) }
        if tabOpen, !fetching, lastFetchAt.map({ now - $0 >= Self.fetchEveryMs }) ?? true { fetch(at: now) }
        guard on, !busy, retryAt.map({ now >= $0 }) ?? true else { return }
        guard let identity else {
            join(me, at: now)
            return
        }
        let gap = lastSentAt.map { now - $0 } ?? .max
        let due = last.map { me.changes(from: $0) } ?? true
            || pendingSince.map { now - $0 >= Self.countsWaitMs } == true
            || gap >= Self.heartbeatMs
        if due, gap >= Self.minGapMs {
            send(me, identity: identity, quiet: quiet, at: now)
        } else if (lastAskedAt.map { now - $0 >= Self.gesturesEveryMs } ?? true), gap >= Self.gesturesEveryMs {
            ask(identity, quiet: quiet, at: now)
        }
    }

    /// You came back or unlocked: what's waiting is asked for now.
    public func checkGestures(quiet: Bool, at now: Int64) {
        guard let identity, !busy else { return }
        ask(identity, quiet: quiet, at: now)
    }

    func join(_ me: Now, at now: Int64) {
        guard !joining else { return }
        joining = true
        busy = true
        client.join(name: me.name, utcOffset: me.utcOffset) { [weak self] result in
            guard let self else { return }
            busy = false
            joining = false
            switch result {
            case .success(let joined):
                identity = Identity(id: joined.id, key: joined.key)
                save()
                status.joined = true
                status.shownName = joined.name
                status.trouble = nil
                backoff = 0
                log("world: joined as \(joined.name)")
                onChange()
            case .failure(let failure):
                failed(failure, at: now)
            }
        }
    }

    func send(_ me: Now, identity: Identity, quiet: Bool, at now: Int64) {
        var identity = identity
        identity.seq += 1
        self.identity = identity
        save()
        let added = pending
        let state = World.State(seq: identity.seq, name: me.name, level: me.level, stage: me.stage.lowercased(),
                                utcOffset: me.utcOffset, activity: me.activity, day: me.day, xpToday: me.xpToday, added: added)
        busy = true
        client.send(state, key: identity.key) { [weak self] result in
            guard let self else { return }
            busy = false
            switch result {
            case .success(let reply):
                last = me
                lastSentAt = now
                lastAskedAt = now
                // What arrived since the send was made stays for the next.
                pending = World.Counts(turns: pending.turns - added.turns, testsPassed: pending.testsPassed - added.testsPassed,
                                       ships: pending.ships - added.ships, linesChanged: pending.linesChanged - added.linesChanged)
                pendingSince = pending.isEmpty ? nil : now
                backoff = 0
                let shown = reply.name ?? status.shownName
                if shown != status.shownName || (reply.nameHidden ?? false) != status.nameHidden || status.trouble != nil {
                    status.shownName = shown
                    status.nameHidden = reply.nameHidden ?? false
                    status.trouble = nil
                    onChange()
                }
                arrived(reply.gestures ?? [], quiet: quiet, at: now)
            case .failure(let failure):
                failed(failure, at: now)
            }
        }
    }

    func ask(_ identity: Identity, quiet: Bool, at now: Int64) {
        busy = true
        lastAskedAt = now
        client.gestures(key: identity.key) { [weak self] result in
            guard let self else { return }
            busy = false
            switch result {
            case .success(let came): arrived(came, quiet: quiet, at: now)
            case .failure(let failure): failed(failure, at: now)
            }
        }
    }

    func arrived(_ came: [World.Gesture], quiet: Bool, at now: Int64) {
        guard !came.isEmpty else { return }
        record(gestures.arrived(came, quiet: quiet, at: now), at: now)
    }

    func record(_ events: [Event], at now: Int64) {
        guard !events.isEmpty else { return }
        for e in events {
            status.today.insert(Arrival(counts: WorldGestures.counts(of: e).map { Arrival.Count(kind: $0.0, n: $0.1) },
                                        region: (e["from_region"]?.string).flatMap(World.Region.init(rawValue:)),
                                        held: e["held"]?.bool == true, plays: e["plays"]?.bool != false,
                                        at: Date()), at: 0)
        }
        onEvents(events)
        onChange()
    }

    func failed(_ failure: WorldClient.Failure, at now: Int64) {
        switch failure {
        case .status(429, let after?):
            retryAt = now + Int64(after) * 1000
            return
        case .status(401, _), .status(404, _):
            // The world forgot this buddy (30 days unseen, or left
            // elsewhere): it joins again as new.
            log("world: the server doesn't know this buddy; joining again")
            identity = nil
            save()
            last = nil
            retryAt = nil
            return
        default: break
        }
        backoff = min(Self.maxBackoffMs, max(Self.backoffMs, backoff * 2))
        retryAt = now + backoff
        let trouble = "Can't reach the world right now."
        if status.trouble != trouble {
            status.trouble = trouble
            log("world: \(failure); trying again in \(backoff / 1000) s")
            onChange()
        }
    }

    /// The World tab opened or closed: the world is fetched only while it's open.
    public func tab(open: Bool, at now: Int64) {
        tabOpen = open
        if open, !fetching, lastFetchAt.map({ now - $0 >= Self.fetchEveryMs }) ?? true { fetch(at: now) }
    }

    func fetch(at now: Int64) {
        fetching = true
        lastFetchAt = now
        client.world { [weak self] result in
            guard let self else { return }
            fetching = false
            switch result {
            case .success(let snapshot):
                status.snapshot = snapshot
                status.fetchedAt = Date()
                if identity == nil || !busy { status.trouble = nil }
            case .failure:
                status.trouble = "Can't reach the world right now."
            }
            onChange()
        }
    }

    /// A boop, wave, heart or cheer for another buddy. `done` says whether it went.
    public func gesture(_ kind: World.GestureKind, to buddy: String, _ done: @escaping (Bool) -> Void) {
        guard let identity else { return done(false) }
        client.gesture(kind, to: buddy, key: identity.key) { done((try? $0.get()) != nil) }
    }

    /// "Asleep", at once: the screen locked, or the app quits. Sent even
    /// within `minGapMs` of the last; a 429 drops it.
    public func sleep(_ me: Now, on: Bool, at now: Int64) {
        guard on, let identity, last?.activity != .asleep, !busy else { return }
        var asleep = me
        asleep.activity = .asleep
        send(asleep, identity: identity, quiet: true, at: now)
    }

    /// Leaves the world: the buddy is deleted on the server, and its key
    /// here. Nothing more is sent until the world is switched on again.
    public func leave(_ done: @escaping () -> Void = {}) {
        guard let identity else {
            status.joined = false
            return done()
        }
        self.identity = nil
        save()
        status = Status(snapshot: status.snapshot, fetchedAt: status.fetchedAt)
        last = nil
        pending = World.Counts()
        pendingSince = nil
        onChange()
        client.leave(key: identity.key) { [weak self] result in
            if case .failure(let failure) = result { self?.log("world: leaving: \(failure); the server forgets it in 30 days") }
            done()
        }
    }
}
