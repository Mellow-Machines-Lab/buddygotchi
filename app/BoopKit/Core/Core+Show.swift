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
        let data: [String: JSONValue] = ["agent": .string(session.agent.rawValue), "text": .string(show.headline),
                                         "picture": .bool(true), "link": .bool(show.link != nil)]
        fx.append(.record(Event(at: now, source: Event.Source(session.agent), type: .card, phase: .end,
                                specificType: "show", session: session.id, data: data)))
        publish(now, &fx)
        return fx
    }

    /// The show the popover holds up now, or nil once it's old.
    public func shown(at now: Int64) -> Shown? {
        lastShow.flatMap { now - $0.at < Self.showKeptMs ? $0 : nil }
    }
}
