import Foundation
import MellowHarness

/// What becomes of the gestures other buddies send: each a `world` event
/// in the transcript, which plays on the board as Jev's answer, within
/// limits. At most `perHour` boops, waves and hearts play in an hour; the
/// rest are logged as not playing, and the World tab counts them. Cheers
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
        var out: [Event] = []
        let cheers = gestures.filter { $0.kind == .cheer }
        if let first = cheers.first {
            // The window starts at the cheer that played, so steady cheers
            // can't keep a later ship's from playing.
            let plays = lastCheerAt.map { now - $0 >= Self.cheerWindowMs } ?? true
            if plays { lastCheerAt = now }
            out.append(Self.event([(.cheer, cheers.count)], from: first.fromRegion, plays: plays, at: now))
        }
        for g in gestures where g.kind != .cheer {
            let plays = played.count < Self.perHour
            if plays { played.append(now) }
            out.append(Self.event([(g.kind, 1)], from: g.fromRegion, plays: plays, at: now))
        }
        return out
    }

    /// You're here in the day: what waited, as one event, which plays.
    public mutating func release(at now: Int64) -> [Event] {
        guard !waiting.isEmpty else { return [] }
        defer { waiting = [] }
        let counts = World.GestureKind.allCases.compactMap { kind in
            let n = waiting.filter { $0.kind == kind }.count
            return n > 0 ? (kind, n) : nil
        }
        if counts.contains(where: { $0.0 == .cheer }) { lastCheerAt = now }
        return [Self.event(counts, from: waiting.count == 1 ? waiting[0].fromRegion : nil, held: true, at: now)]
    }

    /// The `world` event for `counts` of gestures, by kind, the first the
    /// event's kind: `from` the region of a single one, `held` if they
    /// waited, and whether it `plays` on the board.
    public static func event(_ counts: [(World.GestureKind, Int)], from region: World.Region? = nil, held: Bool = false,
                             plays: Bool = true, at now: Int64) -> Event {
        var data: [String: JSONValue] = ["count": .int(Int64(counts.first?.1 ?? 1))]
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
