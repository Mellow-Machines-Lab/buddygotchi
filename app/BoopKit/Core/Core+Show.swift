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

    /// The board holds a show up this long once its turn has ended (or
    /// from when it came, when its turn had already ended), counting only
    /// the time the board is free to hold it up: not while a Moment of the
    /// Mac's plays or waits there (`boardBusy`), something needs you or
    /// `listening` shows, which all cover it. And at least
    /// `boardShowLeastMs` before the next one waiting takes its place.
    public static let boardShowMs: Int64 = 30_000, boardShowLeastMs: Int64 = 8_000
    /// A show whose turn never ends goes after this long anyway.
    public static let boardShowMostMs: Int64 = 10 * 60_000

    /// A show for the board: whose it is, when it came, how long it has
    /// left up (nil while its turn still works), when its clock last ran,
    /// and since when it's been the one up (nil while it waits behind
    /// another).
    public struct BoardShow: Equatable, Sendable {
        public var id: Int
        public var key: String
        public var show: Show
        public var agent: String
        public var at: Int64
        public var leftMs: Int64?
        public var clockAt: Int64
        public var frontAt: Int64?
    }

    /// The shows for the board, the one up first.
    func queueBoardShow(_ show: Show, key: String, agent: String, working: Bool, at now: Int64) {
        nextBoardShow += 1
        boardShows.append(BoardShow(id: nextBoardShow, key: key, show: show, agent: agent, at: now,
                                    leftMs: working ? nil : Self.boardShowMs, clockAt: now))
    }

    /// A turn of `key` ended: its shows get their 30 s up from now.
    func boardShowsTurnEnded(_ key: String, at now: Int64) {
        for i in boardShows.indices where boardShows[i].key == key && boardShows[i].leftMs == nil {
            boardShows[i].leftMs = Self.boardShowMs
        }
    }

    /// Whether the board can hold a show up now: nothing of the Mac's
    /// covers it. The Moments are the runtime's to say (`boardBusy`), the
    /// rest is here.
    func boardFreeForShow(at now: Int64) -> Bool {
        !boardBusy && !needsYouShowing && !showsListening(at: now)
    }

    /// Runs the shows' clocks, puts down the ones that have had their time,
    /// and one that has been up its 8 s while another waits; the next one
    /// up starts its time. Only the one up spends its time, and only while
    /// the board is free to hold it up (`boardFreeForShow`): behind a
    /// finish and its invite it would otherwise go unseen.
    func tidyBoardShows(at now: Int64) {
        // A session that has gone keeps its show its 30 s: the agent that
        // drew it may quit right after its last turn.
        for i in boardShows.indices where sessions[boardShows[i].key] == nil && boardShows[i].leftMs == nil {
            boardShows[i].leftMs = Self.boardShowMs
        }
        let free = boardFreeForShow(at: now)
        for i in boardShows.indices {
            if i == 0, free, let left = boardShows[i].leftMs { boardShows[i].leftMs = left - (now - boardShows[i].clockAt) }
            boardShows[i].clockAt = now
        }
        boardShows.removeAll { show in (show.leftMs.map { $0 <= 0 } ?? false) || now - show.at >= Self.boardShowMostMs }
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
