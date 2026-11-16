import AgentHooks
import Foundation
import MellowHarness

// The cards agents hand Boop (`Card`, `Cards`): taking one in, which
// session it's for, and what the `state` says of the one Boop holds.
extension Core {
    /// A card from the tool server, for the session whose agent's process
    /// is `process`: with none that matches, the only session at work, and
    /// with neither, nobody's, and it's dropped. A status needs its session
    /// in a turn; so does a result, which then waits for the turn's end.
    /// Logged with its words, which no line for the brain ever carries.
    @discardableResult
    public func card(_ card: Card, process: AgentProcess?, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        let (_, _, working, _) = groups(at: now)
        let owner = process.flatMap { p in sessions.values.first { $0.process == p } } ?? (working.count == 1 ? working[0] : nil)
        guard let session = owner, session.turn.startedAt != nil, working.contains(where: { $0.key == session.key }) else { return fx }
        switch card.kind {
        case .status: cards.status(card, for: session.key, at: now)
        case .result: cards.result(card, for: session.key, at: now)
        }
        if let slot = stream.lanes[session.key]?.slot { cards.held[session.key]?.slot = slot }
        var data: [String: JSONValue] = ["agent": .string(session.agent.rawValue), "text": .string(card.text)]
        if let step = card.step, let of = card.of { data["step"] = .int(Int64(step)); data["of"] = .int(Int64(of)) }
        if let minutes = card.minutes { data["minutes"] = .int(Int64(minutes)) }
        if let detail = card.detail { data["detail"] = .string(detail) }
        if card.link != nil { data["link"] = true }
        fx.append(.record(Event(at: now, source: Event.Source(session.agent), type: .card,
                                phase: card.kind == .status ? .start : .end, specificType: card.kind.rawValue,
                                session: session.id, data: data)))
        publish(now, &fx)
        return fx
    }

    /// The sessions in the order their cards are swiped through: as the
    /// popover lists them.
    func cardOrder(at now: Int64) -> [String] {
        let (shown, dismissed, working, idle) = groups(at: now)
        return (shown + dismissed + working + idle).map(\.key)
    }

    /// Before each `state`: results that have had their time go, and Boop
    /// holds the card the rules pick (`Cards.refocus`).
    func tidyCards(_ now: Int64) {
        cards.tidy(at: now)
        for key in cards.held.keys where sessions[key] == nil { cards.gone(key) }
        cards.refocus(cards.showing(in: cardOrder(at: now), at: now), at: now)
    }

    /// The card Boop holds now, for the `state`.
    func cardShow(at now: Int64) -> StateSnapshot.CardShow? {
        let showing = cards.showing(in: cardOrder(at: now), at: now)
        guard let key = cards.focus, let index = showing.firstIndex(of: key), let shown = cards.shown(key, at: now) else { return nil }
        return StateSnapshot.CardShow(slot: stream.lanes[key]?.slot ?? cards.held[key]?.slot ?? -1, result: shown.kind == .result,
                                      text: StateSnapshot.clip(shown.text, marked: true, max: StateSnapshot.maxSignBytes),
                                      small: shown.small, over: shown.over,
                                      index: index + 1, count: showing.count)
    }

    /// Your swipe on the card: the next (`by` 1) or the one before (-1).
    @discardableResult
    public func swipeCard(by: Int, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        cards.swipe(by: by, among: cards.showing(in: cardOrder(at: now), at: now), at: now)
        publish(now, &fx)
        return fx
    }

    /// Your tap on the card, recorded as `seq`: its result's link opens on
    /// the Mac, or else its session's thread, as a row picked in the drawer
    /// does. The link itself stays out of the log.
    @discardableResult
    public func tapCard(at now: Int64, seq: Int? = nil) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        if let key = cards.focus, let s = sessions[key], cards.showing(in: cardOrder(at: now), at: now).contains(key) {
            let thread = TranscriptView.Thread(s).name
            let link = cards.shown(key, at: now)?.link
            let message = "\(config.pack.name) opened \(link == nil ? "" : "what ")\(s.agent.rawValue) "
                + (link == nil ? "on " : "made on ") + "\(EventLine.thread(name: thread, project: s.project)) from its card."
            fx.append(.record(Event.did(message, for: seq, action: link == nil ? Core.openThread : Core.openLink, by: Core.cardTap,
                                        facts: ["agent": .string(s.agent.rawValue), "thread": .string(thread)], at: now)))
            fx.append(link.map { .openLink($0) } ?? .open(s.thread))
        }
        publish(now, &fx)
        return fx
    }

    /// What taps a card: the `press` event's specific type, and who opened
    /// the thread or the link.
    public static let cardTap = "card"
    public static let openLink = "open_link"
}
