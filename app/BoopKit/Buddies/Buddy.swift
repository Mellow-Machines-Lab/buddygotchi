import AgentHooks
import Foundation
import MellowHarness

/// One buddy: a board running one character pack, with its own name, mood,
/// face, rules and agents. Boop runs one, or several side by side, all
/// equals, on one transcript and one brain. With several, each event about
/// a buddy is tagged with it (`Event.buddy`), and the brain answers for
/// each buddy in a pass of its own (MellowHarness's voices), so a buddy
/// hears what the others did and can react to it.
public struct Buddy: Sendable {
    /// Which buddy it is: where it sits (`left`, `right`) when there are
    /// several, its pack's id when it's the only one.
    public let id: String
    /// Its character, under the buddy's own name.
    public let pack: CharacterPack
    /// The agents it watches first (`claude`, `codex`); with none, a new
    /// session goes to the buddy watching the fewest.
    public let agents: [String]

    public init(id: String, pack: CharacterPack, agents: [String] = []) {
        self.id = id
        self.pack = pack
        self.agents = agents
    }

    /// The only buddy: the process's character, as Boop always ran.
    public static func only(_ pack: CharacterPack = .active) -> Buddy { Buddy(id: pack.id, pack: pack) }

    /// What it's called.
    public var name: String { pack.name }

    /// The most replies one chain may run to: a buddy's reaction to
    /// another's reaction is one more in its chain (`reacted`'s `chain`),
    /// and past this many it no longer wakes the others. A failsafe, not a
    /// limit on the fun.
    public static let maxRepliesInARow = 10

    /// The section that opens a buddy's prompt when there are several:
    /// whom this pass answers for, loudly, and who else is on the desk.
    public static func header(for me: Buddy, among all: [Buddy]) -> String {
        var lines = ["YOU ARE \(me.name.uppercased()), THE BUDDY ON THE \(me.id.uppercased()). Answer every question for \(me.name) only."]
        for o in all where o.id != me.id {
            lines.append("\(o.name) (on the \(o.id)) is another buddy on the same desk. It watches its own agents and answers for itself. "
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
        guard let agent = e.agent, let session = e.session else { return e.buddy }
        let key = SessionFold.key(agent, session)
        if let tagged = e.buddy { bound[key] = tagged }
        if let id = bound[key], buddies.contains(where: { $0.id == id }) { return id }
        let id = buddies.first { $0.agents.contains(agent.rawValue) }?.id ?? buddies.min { watching($0.id) < watching($1.id) }?.id
        bound[key] = id
        return id
    }
}

/// A buddy as settings, flags and demo scripts give it: where it sits, its
/// pack, the agents it watches first, its own name, and its board's
/// `hello.id` (`b00p-54fe`), for Bluetooth to take that board alone.
public struct BuddySetting: Codable, Equatable, Sendable {
    public var place: String
    public var pack: String
    public var agents: [String]?
    public var name: String?
    public var board: String?

    public init(place: String, pack: String, agents: [String]? = nil, name: String? = nil, board: String? = nil) {
        self.place = place
        self.pack = pack
        self.agents = agents
        self.name = name
        self.board = board
    }

    /// `left:pixel:claude,right:boop:codex:Bo`: each buddy's place, pack,
    /// then optionally the agent it watches first and its name. Nil for
    /// one that doesn't read, or a list with a `problem`.
    public static func parse(_ text: String) -> [BuddySetting]? {
        var out: [BuddySetting] = []
        for item in text.split(separator: ",") {
            let f = item.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard (2...4).contains(f.count) else { return nil }
            out.append(BuddySetting(place: f[0], pack: f[1], agents: f.count > 2 && !f[2].isEmpty ? [f[2]] : nil,
                                    name: f.count > 3 ? f[3] : nil))
        }
        return problem(out) == nil ? out : nil
    }

    /// What's wrong with a list of buddies, or nil: two or more, each with
    /// a place and a pack, each place once, and agents Boop knows.
    public static func problem(_ all: [BuddySetting]) -> String? {
        if all.count < 2 { return "buddies are two or more" }
        if all.contains(where: { $0.place.isEmpty || $0.pack.isEmpty }) { return "each buddy has a place and a pack" }
        if Set(all.map(\.place)).count < all.count { return "each place is one buddy's" }
        if let agent = all.flatMap({ $0.agents ?? [] }).first(where: { Agent(rawValue: $0) == nil }) {
            return "\(agent) isn't an agent: claude or codex"
        }
        return nil
    }

    /// The buddy, its pack loaded from `bundled` or the repo, named its own
    /// name, else the pack's; two buddies of one pack get their places
    /// after it.
    public func buddy(bundled: URL?, among all: [BuddySetting]) throws -> Buddy {
        var pack = try CharacterPack.named(id: self.pack, bundled: bundled)
        if let name { pack = pack.named(name) } else if all.filter({ $0.pack == self.pack && $0.name == nil }).count > 1 {
            pack = pack.named("\(pack.name) \(place.prefix(1).uppercased() + place.dropFirst())")
        }
        return Buddy(id: place, pack: pack, agents: agents ?? [])
    }
}
