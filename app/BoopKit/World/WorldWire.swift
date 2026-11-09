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

        public static func - (a: Counts, b: Counts) -> Counts {
            Counts(turns: a.turns - b.turns, testsPassed: a.testsPassed - b.testsPassed, ships: a.ships - b.ships,
                   linesChanged: a.linesChanged - b.linesChanged)
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
        public var stage: String
        public var utcOffset: Int
        public var activity: Activity
        public var day: String
        public var xpToday: Int
        public var added: Counts

        enum CodingKeys: String, CodingKey {
            case seq, name, level, stage, utcOffset = "utc_offset", activity, day, xpToday = "xp_today", added
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
    }

    /// The reply to a send: how the name shows, and the gestures waiting.
    public struct Reply: Decodable, Sendable {
        public var name: String?
        public var nameHidden: Bool?
        public var gestures: [Gesture]?

        enum CodingKeys: String, CodingKey { case name, nameHidden = "name_hidden", gestures }
    }

    /// The reply to joining: the buddy's id and its key, shown only here.
    public struct Joined: Decodable, Sendable {
        public var id: String
        public var key: String
        public var name: String
    }

    /// One buddy in the world's snapshot.
    public struct Buddy: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var level: Int
        public var stage: String?
        public var utcOffset: Int?
        public var activity: Activity

        public init(id: String, name: String, level: Int, stage: String? = nil, utcOffset: Int?, activity: Activity) {
            self.id = id
            self.name = name
            self.level = level
            self.stage = stage
            self.utcOffset = utcOffset
            self.activity = activity
        }

        enum CodingKeys: String, CodingKey { case id, name, level, stage, utcOffset = "utc_offset", activity }
    }

    /// A region's buddies awake now.
    public struct RegionCount: Codable, Equatable, Sendable {
        public var region: Region
        public var awake: Int
    }

    /// The world now (`GET /v1/world`). Its goal and rewards aren't read:
    /// the Mac shows no world goal for now.
    public struct Snapshot: Codable, Equatable, Sendable {
        public var at: String
        public var awake: Int
        public var total: Int
        public var doing: [String: Int]
        public var today: Counts
        public var regions: [RegionCount]
        public var buddies: [Buddy]

        public init(at: String, awake: Int, total: Int, doing: [String: Int], today: Counts, regions: [RegionCount], buddies: [Buddy]) {
            self.at = at
            self.awake = awake
            self.total = total
            self.doing = doing
            self.today = today
            self.regions = regions
            self.buddies = buddies
        }
    }
}

extension World {
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
