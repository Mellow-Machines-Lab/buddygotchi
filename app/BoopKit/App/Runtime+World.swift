import Foundation
import MellowHarness

/// The world of buddies, on `home`: the runtime tells `WorldLink` what the
/// buddy is now, and logs the gestures that come back as `world` events.
extension Runtime {
    /// What the popover shows of the world.
    public struct WorldStatus: Equatable, Sendable {
        /// The switch in Settings: Boop lives in the world.
        public var on: Bool
        /// In the world now: on, told of in onboarding, and joined.
        public var inWorld: Bool
        /// Your UTC offset now, in minutes: "you" on the band.
        public var utcOffset: Int
        public var link: WorldLink.Status

        public init(on: Bool, inWorld: Bool, utcOffset: Int, link: WorldLink.Status = .init()) {
            self.on = on
            self.inWorld = inWorld
            self.utcOffset = utcOffset
            self.link = link
        }
    }

    func startWorld() {
        guard let url = options.worldURL else { return }
        let world = WorldLink(client: WorldClient(base: url, queue: home), stateDir: options.stateDir, log: options.log)
        world.onEvents = { [weak self] events in
            guard let self else { return }
            run(pipeline.world(events, at: options.clock()))
        }
        world.onChange = { [weak self] in self?.changed() }
        self.world = world
        options.log("world: \(url.absoluteString)\(settings.world ? "" : ", off")")
    }

    /// The UTC offset now, in minutes, rounded to the quarter hour the server takes.
    var utcOffset: Int { (options.time.timeZone.secondsFromGMT(for: options.time.date(options.wallClock())) / 60 / 15) * 15 }

    /// What the world sees the buddy doing, one of six, from the first
    /// buddy's board: asleep or away, waiting on you, a push or a test run
    /// playing, working, or idle.
    func worldActivity(at now: Int64) -> World.Activity {
        let core = core, snapshot = latest ?? core.snapshot(at: now)
        if snapshot.doing == "asleep" || core.awayFromMac { return .asleep }
        if snapshot.attn != nil { return .waiting }
        if let act = snapshot.workAct, act.result == nil {
            if act.kind == "push" { return .shipping }
            if act.kind == "tests" { return .testing }
        }
        if snapshot.activity == "testing" { return .testing }
        return snapshot.doing == "working" ? .coding : .idle
    }

    func worldNow(at now: Int64, day: String) -> WorldLink.Now {
        let g = growth.growth(on: day)
        return WorldLink.Now(name: name, level: g.level, stage: g.stageName, utcOffset: utcOffset,
                             activity: worldActivity(at: now), day: day, xpToday: g.today)
    }

    func worldNow(at now: Int64) -> WorldLink.Now { worldNow(at: now, day: options.time.boopDay(options.wallClock())) }

    /// Whether the world may hear from this Mac: switched on, and told of
    /// in onboarding.
    var worldOn: Bool { settings.world && settings.worldShown }

    /// Night, the screen is locked, you're away, or something needs you
    /// (whose events are held from Jev): gestures wait for you to be free
    /// in the day. A lock counts from its start, well before it's an away:
    /// its own "asleep" send brings gestures, to an empty chair.
    func worldQuiet(at now: Int64) -> Bool {
        core.calendar(at: now).contains("night") || presence.lockedAt != nil || core.awayFromMac || core.needsYouBlock != nil
    }

    func worldTick(at now: Int64) {
        guard let world else { return }
        let day = options.time.boopDay(options.wallClock())
        world.tick(worldNow(at: now, day: day), on: worldOn, quiet: worldQuiet(at: now), today: day, at: now)
    }

    /// An event as it's logged: its counts, and the screen locking (asleep
    /// at once) or you coming back (what's waiting, asked for).
    func worldHeard(_ e: Event) {
        guard let world else { return }
        let now = options.clock()
        world.heard(e, at: now)
        if e.kind == Event.kind(.lock, .start) { world.sleep(worldNow(at: now), on: worldOn, at: now) }
        if e.kind == Event.kind(.lock, .end) || e.kind == Event.kind(.presence, .end) {
            world.checkGestures(on: worldOn, quiet: worldQuiet(at: now), at: now)
        }
    }

    /// The app quits: the buddy goes to sleep in the world, waiting a
    /// moment for it to go.
    func worldSleep() {
        world?.quit(worldNow(at: options.clock()), on: worldOn)
    }

    func worldStatus() -> WorldStatus? {
        guard let world else { return nil }
        return WorldStatus(on: settings.world, inWorld: worldOn && world.status.joined, utcOffset: utcOffset, link: world.status)
    }

    // MARK: From the popover and onboarding (any thread)

    /// Onboarding's world screen was shown: from now on the buddy may join.
    public func worldScreenShown() {
        home.async { [self] in
            guard !settings.worldShown else { return }
            saveSettings { $0.worldShown = true }
            changed()
        }
    }

    /// The world switched on or off. Off leaves it: the buddy is deleted
    /// on the server, so nobody can boop it, and you can still look.
    public func setWorld(_ on: Bool) {
        home.async { [self] in
            saveSettings { $0.world = on }
            options.log("world \(on ? "on" : "off")")
            if !on { world?.leave(at: options.clock()) }
            changed()
        }
    }

    /// The World tab opened or closed.
    public func worldTab(open: Bool) {
        home.async { [self] in world?.tab(open: open, at: options.clock()) }
    }

    /// A gesture for another buddy, from its card. `done`, on the main
    /// thread, says whether it went.
    public func sendGesture(_ kind: World.GestureKind, to buddy: String, done: @escaping @Sendable (Bool) -> Void) {
        home.async { [self] in
            guard let world, worldOn else { return DispatchQueue.main.async { done(false) } }
            options.log("world: sent a \(kind.rawValue)")
            world.gesture(kind, to: buddy) { ok in DispatchQueue.main.async { done(ok) } }
        }
    }
}
