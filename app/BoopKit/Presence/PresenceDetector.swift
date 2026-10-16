import Foundation
import MellowHarness

/// The only code that decides whether you're at the Mac.
/// It hears the Mac's raw signals (locks, sleeps, wakes) and, on
/// every tick, its idle time, and makes the `presence` events: a start when
/// you stepped away, an end when you're back. Nothing after it decides
/// again. Plain state with no clock or OS calls of its own, so tests drive
/// it; the runtime keeps one on `home`.
public struct PresenceDetector {
    public struct Config: Sendable {
        /// A lock or sleep this long is an away; a shorter one is nothing,
        /// so a minute away to fetch a coffee isn't worth a hello.
        public var lockAwayMs: Int64 = 10 * 60_000
        /// No key or mouse for this long is an away. Idle alone can be a
        /// video or a long read, so it waits much longer than a lock.
        public var idleAwayMs: Int64 = 30 * 60_000
        /// While away, a key or mouse within this long is you, back.
        public var backInputMs: Int64 = 5_000

        public init() {}
    }

    /// What the Mac says, as macOS's notifications do. Switching to another
    /// user counts as a lock, and the displays sleeping as sleep.
    public enum Signal: String, Sendable, CaseIterable {
        case locked, unlocked, asleep, woke
    }

    public let config: Config
    /// Whether you're away: an away recorded and its back not yet.
    public private(set) var away: Bool
    /// Since when the screen has been locked, and the Mac or its displays
    /// asleep; nil when not.
    var lockedAt: Int64?
    var asleepAt: Int64?
    /// The last unlock or wake since the away, which names the back.
    var cleared: Signal?

    /// `away` is where the last launch left it: whether the transcript's
    /// last `presence` is a start (`TranscriptView.away`).
    public init(config: Config = Config(), away: Bool = false) {
        self.config = config
        self.away = away
    }

    /// A signal from the Mac at `now`. An unlock or a wake after a lock or
    /// sleep that lasted `lockAwayMs` makes the away it was, if no tick
    /// saw it first: the Mac doesn't tick while it sleeps.
    public mutating func signal(_ signal: Signal, at now: Int64) -> Event? {
        switch signal {
        case .locked:
            if lockedAt == nil { lockedAt = now }
            return nil
        case .asleep:
            if asleepAt == nil { asleepAt = now }
            return nil
        case .unlocked, .woke:
            let since = signal == .unlocked ? lockedAt : asleepAt
            let why: Signal = signal == .unlocked ? .locked : .asleep
            var out: Event?
            if !away, let since, now - since >= config.lockAwayMs {
                out = goAway(why.rawValue, since: since, at: now)
            }
            if signal == .unlocked { lockedAt = nil } else { asleepAt = nil }
            if away { cleared = signal }
            return out
        }
    }

    /// Every tick, with the Mac's idle time: an away once a lock or sleep
    /// has lasted `lockAwayMs` or you've been idle long enough, and a back
    /// once you touch the Mac while it's unlocked and awake. At most one.
    public mutating func tick(at now: Int64, idleMs: Int64) -> Event? {
        let lastInput = now - max(0, idleMs)
        if away {
            guard lockedAt == nil, asleepAt == nil, idleMs <= config.backInputMs else { return nil }
            away = false
            let why = cleared?.rawValue ?? "input"
            cleared = nil
            return Self.backEvent(why: why, at: now)
        }
        if let at = lockedAt, now - at >= config.lockAwayMs {
            return goAway(Signal.locked.rawValue, since: min(at, lastInput), at: now)
        }
        if let at = asleepAt, now - at >= config.lockAwayMs {
            return goAway(Signal.asleep.rawValue, since: min(at, lastInput), at: now)
        }
        if idleMs >= config.idleAwayMs {
            return goAway("idle", since: lastInput, at: now)
        }
        return nil
    }

    mutating func goAway(_ why: String, since: Int64, at now: Int64) -> Event {
        away = true
        cleared = nil
        return Self.awayEvent(why: why, since: since, at: now)
    }

    /// The `presence` events: you away since `since`, for `why`, as decided
    /// at `now`; and you back at `now`, `why` naming what showed it.
    public static func awayEvent(why: String, since: Int64, at now: Int64) -> Event {
        Event(at: now, source: .mac, type: .presence, phase: .start, specificType: why, data: ["since": .int(since)])
    }

    public static func backEvent(why: String, at now: Int64) -> Event {
        Event(at: now, source: .mac, type: .presence, phase: .end, specificType: why)
    }
}
