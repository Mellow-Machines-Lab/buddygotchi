import Foundation
import MellowHarness

/// What becomes of the gestures other buddies send: each a `world` event
/// in the transcript, which plays on the board as Jev's answer, within
/// limits. What one reply brings is one moment. At most `perHour` moments of
/// boops, waves and hearts play in an hour; the rest are logged as not
/// playing, and the World tab counts them. Cheers
/// that come within `cheerWindowMs` of the last are one moment. At night or
/// while you're away, or while something needs you, they wait, and come
/// back as one line when you're free. The waiting ones are kept across a
/// quit (`WorldLink.saveWaiting`); the hour's count isn't.
public struct WorldGestures: Sendable {
    /// The boops, waves and hearts that play in an hour.
    public static let perHour = 3
    public static let hourMs: Int64 = 60 * 60_000
    /// Cheers this close after the last are counted with it, not played:
    /// one ship's cheers come over a few minutes.
    public static let cheerWindowMs: Int64 = 30 * 60_000

    /// When each boop, wave or heart played, the last hour's.
    var played: [Int64] = []
    var lastCheerAt: Int64?
    /// What waits for you to be here in the day, in order.
    public private(set) var waiting: [World.Gesture] = []

    /// `waiting`: what waited when the app last quit.
    public init(waiting: [World.Gesture] = []) { self.waiting = waiting }

    /// `gestures` arrived at `now`. `quiet`: it's night, or you're away, so
    /// they wait. Returns the events to log now.
    public mutating func arrived(_ gestures: [World.Gesture], quiet: Bool, at now: Int64) -> [Event] {
        guard !gestures.isEmpty else { return [] }
        if quiet {
            waiting += gestures
            return []
        }
        played.removeAll { now - $0 >= Self.hourMs }
        // One reply's gestures are one moment: the brain answers only the
        // newest of events that come together, so each its own would leave
        // all but the last unplayed. What doesn't play is logged before it,
        // for the World tab to count.
        var out: [Event] = [], playing: [World.Gesture] = []
        let cheers = gestures.filter { $0.kind == .cheer }, others = gestures.filter { $0.kind != .cheer }
        if !cheers.isEmpty {
            // The window starts at the cheer that played, so steady cheers
            // can't keep a later ship's from playing.
            if lastCheerAt.map({ now - $0 >= Self.cheerWindowMs }) ?? true {
                lastCheerAt = now
                playing += cheers
            } else {
                out.append(Self.event(Self.counted(cheers), from: cheers[0].fromRegion, plays: false, at: now))
            }
        }
        if !others.isEmpty {
            if played.count < Self.perHour {
                played.append(now)
                playing += others
            } else {
                out.append(Self.event(Self.counted(others), from: others.count == 1 ? others[0].fromRegion : nil, plays: false, at: now))
            }
        }
        if !playing.isEmpty {
            out.append(Self.event(Self.counted(playing), from: playing.count == 1 || Set(playing.map(\.kind)) == [.cheer]
                                      ? playing[0].fromRegion : nil, sender: Self.one(playing), at: now))
        }
        return out
    }

    /// `gestures` counted by kind, in the kinds' order.
    static func counted(_ gestures: [World.Gesture]) -> [(World.GestureKind, Int)] {
        World.GestureKind.allCases.compactMap { kind in
            let n = gestures.filter { $0.kind == kind }.count
            return n > 0 ? (kind, n) : nil
        }
    }

    /// You left the world: what waited goes with it.
    public mutating func drop() { waiting = [] }

    /// You're here in the day: what waited, as one event, which plays.
    public mutating func release(at now: Int64) -> [Event] {
        guard !waiting.isEmpty else { return [] }
        defer { waiting = [] }
        let counts = Self.counted(waiting)
        if counts.contains(where: { $0.0 == .cheer }) { lastCheerAt = now }
        return [Self.event(counts, from: waiting.count == 1 ? waiting[0].fromRegion : nil, sender: Self.one(waiting), held: true, at: now)]
    }

    /// The `world` event for `counts` of gestures, by kind, the first the
    /// event's kind: `from` the region of a single one, `held` if they
    /// waited, and whether it `plays` on the board.
    /// The sender, when one buddy sent them all.
    static func one(_ gestures: [World.Gesture]) -> World.Gesture.Sender? {
        guard let first = gestures.first?.from, gestures.allSatisfy({ $0.from == first }) else { return nil }
        return first
    }

    public static func event(_ counts: [(World.GestureKind, Int)], from region: World.Region? = nil, sender: World.Gesture.Sender? = nil,
                             held: Bool = false, plays: Bool = true, at now: Int64) -> Event {
        var data: [String: JSONValue] = ["count": .int(Int64(counts.first?.1 ?? 1))]
        if let sender, counts.count == 1, counts[0].1 == 1 {
            data["from_id"] = .string(sender.id)
            data["from_name"] = .string(sender.name)
        }
        if counts.count > 1 { data["counts"] = .object(Dictionary(uniqueKeysWithValues: counts.map { ($0.0.rawValue, JSONValue.int(Int64($0.1))) })) }
        if let region { data["from_region"] = .string(region.rawValue) }
        if held { data["held"] = .bool(true) }
        if !plays { data["plays"] = .bool(false) }
        return Event(at: now, source: .world, type: .world, specificType: (counts.first?.0 ?? .boop).rawValue, data: data)
    }

    /// One kind of gesture, `count` of them together.
    public static func event(_ kind: World.GestureKind, count: Int = 1, from region: World.Region? = nil, at now: Int64) -> Event {
        event([(kind, count)], from: region, at: now)
    }

    /// A `world` event's gestures by kind, as `event` wrote them.
    public static func counts(of e: Event) -> [(World.GestureKind, Int)] {
        if let all = e["counts"]?.object {
            return World.GestureKind.allCases.compactMap { k in all[k.rawValue]?.int.map { (k, Int($0)) } }
        }
        return World.GestureKind(rawValue: e.specificType).map { [($0, e["count"]?.int.map { Int($0) } ?? 1)] } ?? []
    }
}
