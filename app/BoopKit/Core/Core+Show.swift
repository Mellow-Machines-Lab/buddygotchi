import AgentHooks
import MellowHarness
import Foundation

// The show (documentation/design/screen-guide.md, "The show"): a result as a
// picture an agent drew (`Show`), which the popover holds up with its
// headline. Its words and its picture are the agent's: they go to the
// screen and the transcript's headline, never to the brain.
extension Core {
    /// How long the popover keeps the latest show.
    public static let showKeptMs: Int64 = 30 * 60_000

    /// The latest show, whose it is and when it came.
    public struct Shown: Equatable, Sendable {
        public var show: Show
        public var agent: String
        public var project: String
        public var slot: Int?
        public var at: Int64

        public init(show: Show, agent: String, project: String, slot: Int?, at: Int64) {
            (self.show, self.agent, self.project, self.slot, self.at) = (show, agent, project, slot, at)
        }
    }

    /// A show from the tool server, for its process's session, else the
    /// only one at work; nobody's is dropped.
    @discardableResult
    public func show(_ show: Show, process: AgentProcess?, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        let (_, _, working, _) = groups(at: now)
        guard let session = owner(of: process, working: working) else { return fx }
        lastShow = Shown(show: show, agent: session.agent.rawValue, project: session.project,
                         slot: slot(of: session.key), at: now)
        queueBoardShow(show, key: session.key, agent: session.agent.rawValue,
                       working: working.contains(where: { $0.key == session.key }), at: now)
        let data: [String: JSONValue] = ["agent": .string(session.agent.rawValue), "text": .string(show.headline),
                                         "picture": .bool(true), "link": .bool(show.link != nil)]
        fx.append(.record(Event(at: now, source: Event.Source(session.agent), type: .card, phase: .end,
                                specificType: "show", session: session.id, data: data)))
        publish(now, &fx)
        return fx
    }

    /// The board holds a show up this long after its turn ends (or after
    /// it came, when its turn had already ended), and at least this long
    /// before the next one waiting takes its place.
    public static let boardShowMs: Int64 = 30_000, boardShowLeastMs: Int64 = 8_000
    /// A show whose turn never ends goes after this long anyway.
    public static let boardShowMostMs: Int64 = 10 * 60_000

    /// A show for the board: whose it is, when it came, when it goes, and
    /// since when it's been the one up (nil while it waits behind another).
    public struct BoardShow: Equatable, Sendable {
        public var id: Int
        public var key: String
        public var show: Show
        public var agent: String
        public var at: Int64
        public var endsAt: Int64?
        public var frontAt: Int64?
    }

    /// The shows for the board, the one up first.
    func queueBoardShow(_ show: Show, key: String, agent: String, working: Bool, at now: Int64) {
        nextBoardShow += 1
        boardShows.append(BoardShow(id: nextBoardShow, key: key, show: show, agent: agent, at: now,
                                    endsAt: working ? nil : now + Self.boardShowMs))
    }

    /// A turn of `key` ended: its shows go 30 s from now.
    func boardShowsTurnEnded(_ key: String, at now: Int64) {
        for i in boardShows.indices where boardShows[i].key == key && boardShows[i].endsAt == nil {
            boardShows[i].endsAt = now + Self.boardShowMs
        }
    }

    /// Puts down the shows that are over, and one that has been up its 8 s
    /// while another waits; the next one up starts its time.
    func tidyBoardShows(at now: Int64) {
        boardShows.removeAll { show in
            sessions[show.key] == nil || (show.endsAt.map { now >= $0 } ?? false) || now - show.at >= Self.boardShowMostMs
        }
        while boardShows.count > 1, let front = boardShows[0].frontAt, now - front >= Self.boardShowLeastMs {
            boardShows.removeFirst()
        }
        if !boardShows.isEmpty, boardShows[0].frontAt == nil { boardShows[0].frontAt = now }
    }

    /// The show the board holds up now, or nil.
    public var boardShow: BoardShow? { boardShows.first }

    /// The show the popover holds up now, or nil once it's old.
    public func shown(at now: Int64) -> Shown? {
        lastShow.flatMap { now - $0.at < Self.showKeptMs ? $0 : nil }
    }
}
