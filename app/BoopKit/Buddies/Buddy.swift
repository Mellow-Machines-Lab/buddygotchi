import AgentHooks
import Foundation
import MellowHarness

/// One buddy: a board running one character pack, with its own name, mood,
/// face, rules and agents. Boop runs one, or several side by side, all
/// equals, on one transcript and one brain: each event is tagged with the
/// buddy it's about (`data.buddy`), and the brain answers for each buddy in
/// a pass of its own (MellowHarness's voices), so a buddy hears what the
/// others did and can react to it.
public struct Buddy: Sendable, Equatable {
    /// Which buddy it is, in the transcript and the settings: where it sits
    /// (`left`, `right`), or the pack's id when it's the only one.
    public let id: String
    /// Its character, under the buddy's own name.
    public let pack: CharacterPack
    /// Where it sits on the desk (`left`, `right`), which the brain hears;
    /// nil for the only one.
    public let place: String?
    /// The agents it watches first (`claude`, `codex`); with none, a new
    /// session goes to the buddy watching the fewest.
    public let agents: [String]

    public init(id: String, pack: CharacterPack, place: String? = nil, agents: [String] = []) {
        self.id = id
        self.pack = pack
        self.place = place
        self.agents = agents
    }

    /// What it's called.
    public var name: String { pack.name }

    /// `Pixel (on the left)`, or its name alone where it sits nowhere.
    public var called: String { place.map { "\(name) (on the \($0))" } ?? name }

    public static func == (a: Buddy, b: Buddy) -> Bool {
        a.id == b.id && a.pack.directory == b.pack.directory && a.name == b.name && a.place == b.place && a.agents == b.agents
    }

    /// The buddy an event is about, by its tag.
    public static func of(_ e: Event) -> String? { e["buddy"]?.string }

    /// The most buddies one chain of replies may run to: past this many
    /// buddy reactions in a row with nothing else waking the brain, a
    /// reaction no longer wakes the others. A failsafe, not a limit on the
    /// fun: they may answer each other this often.
    public static let maxRepliesInARow = 10

    /// The section that opens a buddy's prompt when there's more than one:
    /// whom this pass answers for, loudly, and who else is on the desk.
    public static func header(for me: Buddy, among all: [Buddy]) -> String {
        let others = all.filter { $0.id != me.id }
        let where_ = me.place.map { ", THE BUDDY ON THE \($0.uppercased())" } ?? ""
        var lines = ["YOU ARE \(me.name.uppercased())\(where_). Answer every question for \(me.name) only."]
        for o in others {
            lines.append("\(o.called) is another buddy on the same desk. It watches its own agents and answers for itself. "
                         + "\(me.name) can hear what it does and react to it, or not.")
        }
        lines.append("Lines about an agent say whose agent it is. A buddy's reaction is a line of its own.")
        return lines.joined(separator: "\n")
    }
}

/// Which buddy watches each agent session: the buddy whose agents name it
/// first, else the one watching the fewest sessions. A session keeps its
/// buddy; the transcript's tags keep it across launches.
public final class BuddyBinding {
    private var bound: [String: String] = [:]

    public init() {}

    /// The buddy for an agent's event, binding its session on its first
    /// event. `watching` is how many sessions each buddy watches now.
    public func buddy(for e: Event, among buddies: [Buddy], watching: (String) -> Int) -> String? {
        if let tagged = Buddy.of(e) {
            if let key = BuddyBinding.key(e) { bound[key] = tagged }
            return tagged
        }
        guard let key = BuddyBinding.key(e), let agent = e.agent?.rawValue else { return nil }
        if let id = bound[key], buddies.contains(where: { $0.id == id }) { return id }
        let id = buddies.first { $0.agents.contains(agent) }?.id
            ?? buddies.min { watching($0.id) < watching($1.id) }?.id
        bound[key] = id
        return id
    }

    static func key(_ e: Event) -> String? {
        guard let agent = e.agent, let session = e.session else { return nil }
        return SessionFold.key(agent, session)
    }
}

/// A buddy as settings and flags give it: where it sits, its pack, the
/// agents it watches first, its own name, and its board's id over
/// Bluetooth.
public struct BuddySetting: Codable, Equatable, Sendable {
    public var place: String
    public var pack: String
    public var agents: [String]
    public var name: String?
    /// Its board's `hello.id` (`b00p-54fe`), for Bluetooth to take that
    /// board alone; nil takes the first it finds.
    public var board: String?

    public init(place: String, pack: String, agents: [String] = [], name: String? = nil, board: String? = nil) {
        self.place = place
        self.pack = pack
        self.agents = agents
        self.name = name
        self.board = board
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        place = try c.decode(String.self, forKey: .place)
        pack = try c.decode(String.self, forKey: .pack)
        agents = try c.decodeIfPresent([String].self, forKey: .agents) ?? []
        name = try c.decodeIfPresent(String.self, forKey: .name)
        board = try c.decodeIfPresent(String.self, forKey: .board)
    }

    /// `left:pixel:claude,right:boop:codex:Bo`: each buddy's place, pack,
    /// then optionally the agent it watches first and its name. Nil for
    /// one that doesn't read, or a place given twice.
    public static func parse(_ text: String) -> [BuddySetting]? {
        var out: [BuddySetting] = []
        for item in text.split(separator: ",") {
            let f = item.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard (2...4).contains(f.count), !f[0].isEmpty, !f[1].isEmpty, !out.contains(where: { $0.place == f[0] }) else { return nil }
            let agents = f.count > 2 && !f[2].isEmpty ? [f[2]] : []
            out.append(BuddySetting(place: f[0], pack: f[1], agents: agents, name: f.count > 3 ? f[3] : nil))
        }
        return out.isEmpty ? nil : out
    }

    /// The buddy, its pack loaded from `bundled` or the repo, named its own
    /// name, else the pack's; two buddies of one pack get their places
    /// after it.
    public func buddy(bundled: URL?, among all: [BuddySetting]) throws -> Buddy {
        var pack = try CharacterPack.named(id: self.pack, bundled: bundled)
        if let name { pack = pack.named(name) } else if all.filter({ $0.pack == self.pack && $0.name == nil }).count > 1 {
            pack = pack.named("\(pack.name) \(place.prefix(1).uppercased() + place.dropFirst())")
        }
        return Buddy(id: place, pack: pack, place: place, agents: agents)
    }

    /// The name its board advertises over Bluetooth for its `board` id:
    /// `b00p-54fe` advertises as `Boop-54FE`.
    public var advertised: String? {
        guard let board, let dash = board.firstIndex(of: "-") else { return nil }
        return BoopDevice.blePrefix + "-" + board[board.index(after: dash)...].uppercased()
    }
}
