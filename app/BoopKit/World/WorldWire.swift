import Foundation

/// The world server's wire format (internal/world/fixtures/), as the Mac
/// sends and reads it. The fixtures pin it: the server's tests check them,
/// and the Mac's decode them.
public enum World {
    /// The six things a buddy can be doing, as the world sees it.
    public enum Activity: String, Codable, Sendable, CaseIterable {
        case coding, testing, shipping, waiting, idle, asleep

        /// How a person says it: "coding", "waiting on its person".
        public var words: String {
            switch self {
            case .waiting: "waiting on its person"
            default: rawValue
            }
        }
    }

    /// A gesture one buddy sends another.
    public enum GestureKind: String, Codable, Sendable, CaseIterable {
        case boop, wave, heart, cheer
    }

    /// Where on Earth a buddy is, from its UTC offset: the server's
    /// `regions.ts`, whose boundaries this repeats for "you" on the band.
    public enum Region: String, Codable, Sendable, CaseIterable {
        case americas, europeAfrica = "europe_africa", asiaOceania = "asia_oceania"

        /// The World tab's name for it.
        public var name: String {
            switch self {
            case .americas: "Americas"
            case .europeAfrica: "Europe and Africa"
            case .asiaOceania: "Asia and Oceania"
            }
        }

        /// Where someone is, in a sentence: "in the Americas".
        public var within: String {
            switch self {
            case .americas: "in the Americas"
            case .europeAfrica: "in Europe or Africa"
            case .asiaOceania: "in Asia or Oceania"
            }
        }

        /// The region of a UTC offset in minutes, as the server works it out.
        public init?(offset: Int?) {
            guard let offset else { return nil }
            switch offset {
            case -720 ... -120: self = .americas
            case -105 ... 180: self = .europeAfrica
            case 195 ... 840: self = .asiaOceania
            default: return nil
            }
        }
    }

    /// The counts a buddy adds since its last send.
    public struct Counts: Codable, Equatable, Sendable {
        public var turns = 0, testsPassed = 0, ships = 0, linesChanged = 0

        public init(turns: Int = 0, testsPassed: Int = 0, ships: Int = 0, linesChanged: Int = 0) {
            self.turns = turns
            self.testsPassed = testsPassed
            self.ships = ships
            self.linesChanged = linesChanged
        }

        public var isEmpty: Bool { self == Counts() }

        public static func + (a: Counts, b: Counts) -> Counts {
            Counts(turns: a.turns + b.turns, testsPassed: a.testsPassed + b.testsPassed, ships: a.ships + b.ships,
                   linesChanged: a.linesChanged + b.linesChanged)
        }

        /// What's left of `a` once `b` is sent, never under 0: `b` may be a
        /// send kept over a quit, which counted what this launch never had.
        public static func - (a: Counts, b: Counts) -> Counts {
            Counts(turns: max(0, a.turns - b.turns), testsPassed: max(0, a.testsPassed - b.testsPassed),
                   ships: max(0, a.ships - b.ships), linesChanged: max(0, a.linesChanged - b.linesChanged))
        }

        enum CodingKeys: String, CodingKey {
            case turns, testsPassed = "tests_passed", ships, linesChanged = "lines_changed"
        }
    }

    /// What a buddy sends (`PUT /v1/buddies/me`): this, and nothing else,
    /// leaves the Mac. A test fails if a key is added.
    public struct State: Codable, Equatable, Sendable {
        public var seq: Int
        public var name: String
        public var level: Int
        public var utcOffset: Int
        public var activity: Activity
        public var day: String
        public var xpToday: Int
        public var added: Counts
        /// The days in a row with a full ring, and the buddy's colour, 0 to 7:
        /// what its card shows others.
        public var daysInARow: Int = 0
        public var color: Int = 0

        enum CodingKeys: String, CodingKey {
            case seq, name, level, utcOffset = "utc_offset", activity, day, xpToday = "xp_today", added
            case daysInARow = "days_in_a_row", color
        }
    }

    /// A gesture waiting for this buddy.
    public struct Gesture: Codable, Equatable, Sendable {
        public var kind: GestureKind
        public var fromRegion: Region?
        public var at: String

        public init(kind: GestureKind, fromRegion: Region?, at: String) {
            self.kind = kind
            self.fromRegion = fromRegion
            self.at = at
        }

        enum CodingKeys: String, CodingKey { case kind, fromRegion = "from_region", at }

        /// A region this Mac doesn't know yet is no region.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decode(GestureKind.self, forKey: .kind)
            fromRegion = try? c.decodeIfPresent(Region.self, forKey: .fromRegion)
            at = try c.decode(String.self, forKey: .at)
        }
    }

    /// The reply to a send: how the name shows, and the gestures waiting.
    public struct Reply: Decodable, Sendable {
        public var name: String?
        public var nameHidden: Bool?
        public var gestures: [Gesture]?
        /// The seq was counted before: the server kept that send's body, not this one's.
        public var duplicate: Bool?
        /// The buddy's place last week, or none.
        public var lastWeek: Place?
        /// The buddy's own medals.
        public var medals: Profile.Medals?

        enum CodingKeys: String, CodingKey { case name, nameHidden = "name_hidden", gestures, duplicate, lastWeek = "last_week", medals }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            nameHidden = try c.decodeIfPresent(Bool.self, forKey: .nameHidden)
            gestures = try c.lenient(Gesture.self, forKey: .gestures)
            duplicate = try c.decodeIfPresent(Bool.self, forKey: .duplicate)
            lastWeek = try? c.decodeIfPresent(Place.self, forKey: .lastWeek)
            medals = try? c.decodeIfPresent(Profile.Medals.self, forKey: .medals)
        }
    }

    /// The reply to joining: the buddy's id and its key, shown only here.
    public struct Joined: Decodable, Sendable {
        public var id: String
        public var key: String
        public var name: String
    }

    /// The week's league (`GET /v1/league`): the top rows by the week's
    /// XP, and with this buddy's key, its own place and last week's.
    public struct League: Decodable, Equatable, Sendable {
        public var week: String
        public var endsAt: String
        public var total: Int
        public var awake: Int
        public var withXP: Int
        public var rows: [Row]
        public var me: Me?
        public var lastWeek: Place?

        public struct Row: Codable, Equatable, Sendable, Identifiable {
            public var place: Int
            public var id: String
            public var name: String
            public var level: Int
            public var color: Int
            public var activity: Activity
            public var xpWeek: Int
            enum CodingKeys: String, CodingKey { case place, id, name, level, color, activity, xpWeek = "xp_week" }
            public init(place: Int, id: String, name: String, level: Int, color: Int, activity: Activity, xpWeek: Int) {
                (self.place, self.id, self.name, self.level, self.color, self.activity, self.xpWeek) = (place, id, name, level, color, activity, xpWeek)
            }
        }
        public struct Me: Codable, Equatable, Sendable {
            public var place: Int
            public var xpWeek: Int
            public var topPercent: Int?
            public var ahead: Other?
            public var behind: Other?
            enum CodingKeys: String, CodingKey { case place, xpWeek = "xp_week", topPercent = "top_percent", ahead, behind }
            public init(place: Int, xpWeek: Int, topPercent: Int?, ahead: Other?, behind: Other?) {
                (self.place, self.xpWeek, self.topPercent, self.ahead, self.behind) = (place, xpWeek, topPercent, ahead, behind)
            }
        }
        /// The buddy just ahead or behind, and by how much XP.
        public struct Other: Codable, Equatable, Sendable {
            public var id: String
            public var name: String
            public var by: Int
            public init(id: String, name: String, by: Int) { (self.id, self.name, self.by) = (id, name, by) }
        }

        enum CodingKeys: String, CodingKey {
            case week, endsAt = "ends_at", total, awake, withXP = "with_xp", rows, me, lastWeek = "last_week"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            week = try c.decode(String.self, forKey: .week)
            endsAt = try c.decode(String.self, forKey: .endsAt)
            total = try c.decode(Int.self, forKey: .total)
            awake = try c.decode(Int.self, forKey: .awake)
            withXP = try c.decodeIfPresent(Int.self, forKey: .withXP) ?? 0
            rows = try c.lenient(Row.self, forKey: .rows) ?? []
            me = try c.decodeIfPresent(Me.self, forKey: .me)
            lastWeek = try c.decodeIfPresent(Place.self, forKey: .lastWeek)
        }

        public init(week: String, endsAt: String, total: Int, awake: Int, withXP: Int, rows: [Row], me: Me? = nil, lastWeek: Place? = nil) {
            (self.week, self.endsAt, self.total, self.awake, self.withXP, self.rows, self.me, self.lastWeek) =
                (week, endsAt, total, awake, withXP, rows, me, lastWeek)
        }

        /// When the week ends, as a date.
        public var ends: Date? { ISO8601DateFormatter().date(from: endsAt) }
    }

    /// A buddy's place in a closed week: its Monday, the place, the XP and how many had a place.
    public struct Place: Codable, Equatable, Sendable {
        public var week: String
        public var place: Int
        public var xp: Int
        public var of: Int
        public init(week: String, place: Int, xp: Int, of: Int) { (self.week, self.place, self.xp, self.of) = (week, place, xp, of) }
    }

    /// One buddy's public profile (`GET /v1/buddies/:id`).
    public struct Profile: Decodable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var level: Int
        public var color: Int
        public var region: Region?
        public var utcOffset: Int?
        public var activity: Activity
        public var daysInARow: Int
        public var medals: Medals
        public var week: Week
        public var bestWeek: Int
        public var today: Today
        public var between: Between?

        public struct Medals: Codable, Equatable, Sendable {
            public var gold, silver, bronze: Int
            public init(gold: Int = 0, silver: Int = 0, bronze: Int = 0) { (self.gold, self.silver, self.bronze) = (gold, silver, bronze) }
            public var any: Bool { gold + silver + bronze > 0 }
        }
        public struct Week: Codable, Equatable, Sendable {
            public var xp: Int
            public var place: Int
            public init(xp: Int, place: Int) { (self.xp, self.place) = (xp, place) }
        }
        public struct Today: Codable, Equatable, Sendable {
            public var turns, ships, testsPassed: Int
            enum CodingKeys: String, CodingKey { case turns, ships, testsPassed = "tests_passed" }
            public init(turns: Int, ships: Int, testsPassed: Int) { (self.turns, self.ships, self.testsPassed) = (turns, ships, testsPassed) }
        }
        /// What's between this buddy and the one asking.
        public struct Between: Codable, Equatable, Sendable {
            public var fromThem: Sent?
            public var fromYou: Sent?
            public var youBeatThem: String?
            enum CodingKeys: String, CodingKey { case fromThem = "from_them", fromYou = "from_you", youBeatThem = "you_beat_them" }
            public init(fromThem: Sent?, fromYou: Sent?, youBeatThem: String?) {
                (self.fromThem, self.fromYou, self.youBeatThem) = (fromThem, fromYou, youBeatThem)
            }
        }
        public struct Sent: Codable, Equatable, Sendable {
            public var kind: String
            public var at: String
            public init(kind: String, at: String) { (self.kind, self.at) = (kind, at) }
        }

        enum CodingKeys: String, CodingKey {
            case id, name, level, color, region, utcOffset = "utc_offset", activity, daysInARow = "days_in_a_row", medals, week,
                 bestWeek = "best_week", today, between
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            level = try c.decode(Int.self, forKey: .level)
            color = try c.decodeIfPresent(Int.self, forKey: .color) ?? 0
            region = try? c.decodeIfPresent(Region.self, forKey: .region)
            utcOffset = try c.decodeIfPresent(Int.self, forKey: .utcOffset)
            activity = (try? c.decode(Activity.self, forKey: .activity)) ?? .idle
            daysInARow = try c.decodeIfPresent(Int.self, forKey: .daysInARow) ?? 0
            medals = try c.decodeIfPresent(Medals.self, forKey: .medals) ?? Medals()
            week = try c.decode(Week.self, forKey: .week)
            bestWeek = try c.decodeIfPresent(Int.self, forKey: .bestWeek) ?? 0
            today = try c.decode(Today.self, forKey: .today)
            between = try c.decodeIfPresent(Between.self, forKey: .between)
        }

        public init(id: String, name: String, level: Int, color: Int = 0, region: Region?, utcOffset: Int?, activity: Activity,
                    daysInARow: Int, medals: Medals, week: Week, bestWeek: Int, today: Today, between: Between? = nil) {
            (self.id, self.name, self.level, self.color, self.region, self.utcOffset, self.activity) = (id, name, level, color, region, utcOffset, activity)
            (self.daysInARow, self.medals, self.week, self.bestWeek, self.today, self.between) = (daysInARow, medals, week, bestWeek, today, between)
        }
    }
}

extension World {
    /// The `world` event's kind for last week's league place, told once.
    public static let leagueKind = "league"

    /// A medal's mark for a place: `gold`, `silver`, `bronze`, else nil.
    public static func medal(_ place: Int) -> String? {
        place >= 1 && place <= 3 ? ["gold", "silver", "bronze"][place - 1] : nil
    }

    /// "1st", "2nd", "23rd".
    public static func ordinal(_ n: Int) -> String {
        let tens = n % 100, ones = n % 10
        let suffix = (11...13).contains(tens) ? "th" : ones == 1 ? "st" : ones == 2 ? "nd" : ones == 3 ? "rd" : "th"
        return "\(n)\(suffix)"
    }

    /// What Boop holds low in gold for last week: "2nd, 512 XP last week".
    public static func leagueSign(place: Int, xp: Int) -> String { "\(ordinal(place)), \(xp) XP last week" }

    /// What other buddies did, as a sentence: "Someone in Europe or
    /// Africa booped Mochi.", "3 buddies cheered your ship." `counts` is how
    /// many of each kind, `region` the one buddy's, and `held` says they
    /// waited while you were away or for the morning: "While you were
    /// away, 3 buddies booped Mochi and 2 cheered your ship."
    public static func sentence(_ counts: [(GestureKind, Int)], from region: Region?, held: Bool, name: String) -> String {
        let parts = counts.enumerated().map { i, c -> String in
            let (kind, count) = c
            let who = i > 0 ? (count > 1 ? "\(count)" : "one") : count > 1 ? "\(count) buddies" : "someone" + (region.map { " " + $0.within } ?? "")
            let did = switch kind {
            case .boop: "booped \(name)"
            case .wave: "waved at \(name)"
            case .heart: count > 1 ? "sent \(name) hearts" : "sent \(name) a heart"
            case .cheer: "cheered your ship"
            }
            return "\(who) \(did)"
        }
        let s = (parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.first ?? "") + "."
        return held ? "While you were away, " + s : s.prefix(1).uppercased() + s.dropFirst()
    }

    /// The same, in the few characters of the board's lane, `{name}` for
    /// the buddy's name: the first that fits is shown.
    public static func facts(_ kind: GestureKind, count: Int) -> [String] {
        switch kind {
        case .boop: count > 1 ? ["\(count) boops for {name}", "\(count) boops"] : ["someone booped {name}", "a boop from afar"]
        case .wave: count > 1 ? ["\(count) waves for {name}", "\(count) waves"] : ["{name} got a wave", "a wave from afar"]
        case .heart: count > 1 ? ["\(count) hearts for {name}", "\(count) hearts"] : ["a heart for {name}", "a heart from afar"]
        case .cheer: count > 1 ? ["\(count) cheers for you!", "\(count) cheers!"] : ["a cheer for you!"]
        }
    }
}

extension KeyedDecodingContainer {
    /// An array from the world server, leaving out each element that won't
    /// decode (a gesture, activity or region this Mac doesn't know yet)
    /// instead of failing the whole reply; nil when it's missing or null.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T]? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        var array = try nestedUnkeyedContainer(forKey: key)
        var out: [T] = []
        while !array.isAtEnd {
            if let value = try? array.decode(T.self) { out.append(value) } else { _ = try array.decode(Skipped.self) }
        }
        return out
    }
}

/// Any JSON value, read past.
private struct Skipped: Decodable {
    init(from decoder: Decoder) throws {}
}
