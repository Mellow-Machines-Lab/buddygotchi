import AgentHooks
import Foundation

// Several agents (documentation/design/screen-guide.md, "Who wins the
// space"): the screen follows one agent at a time, the watched one, and the
// pips on the strip's line show every agent. A plain rule on the Mac; the
// board only draws it, and a swipe across the desk asks for the next.
extension Core {
    /// How long a pill says news from an agent you aren't watching.
    public static let pillMs: Int64 = 4000
    /// The most pips the strip draws; more agents count in the drawer.
    public static let maxPips = 6

    /// The sessions the pips show, in the popover's order.
    func pipOrder(at now: Int64) -> [String] { Array(cardOrder(at: now).prefix(Self.maxPips)) }

    /// The session the screen follows now, by the rule: a show while it's
    /// up; your swipe, kept
    /// while that agent still works or holds a card; else the one Boop
    /// holds a card for (a picture beats plain work); else the working one
    /// you last prompted; else the one whose turn ended last.
    func watched(at now: Int64) -> String? {
        let (shown, dismissed, working, idle) = groups(at: now)
        let all = shown + dismissed + working + idle
        guard !all.isEmpty else { return nil }
        // A show takes the screen while it's up, once, then the screen returns.
        if let up = boardShow?.key, all.contains(where: { $0.key == up }) { return up }
        if let swiped = watchSwiped, all.contains(where: { $0.key == swiped }),
           working.contains(where: { $0.key == swiped }) || cards.focus == swiped || watchSwipedAt.map({ now - $0 < 60_000 }) == true {
            return swiped
        }
        if let focus = cards.focus, all.contains(where: { $0.key == focus }) { return focus }
        if let prompted = working.max(by: { ($0.turn.startedAt ?? 0, $0.order) < ($1.turn.startedAt ?? 0, $1.order) }) {
            return prompted.key
        }
        return all.max { ($0.turn.lastEndedAt ?? $0.lastEventAt, $0.order) < ($1.turn.lastEndedAt ?? $1.lastEventAt, $1.order) }?.key
    }

    /// Your swipe across the desk: the next agent (`by` 1) or the one
    /// before (-1), among the pips, kept as yours.
    @discardableResult
    public func swipeAgent(by: Int, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        let order = pipOrder(at: now)
        guard order.count > 1 else { return fx }
        let at = watched(at: now).flatMap { order.firstIndex(of: $0) } ?? 0
        let next = order[(at + by % order.count + order.count) % order.count]
        watchSwiped = next
        watchSwipedAt = now
        unseen[next] = nil
        if cards.showing(in: cardOrder(at: now), at: now).contains(next) {
            cards.hold(next, at: now)
        }
        publish(now, &fx)
        return fx
    }

    /// A turn of `key` ended: news for you if you aren't watching it, a pill
    /// for `pillMs` and its pip pulsing until you look.
    func turnEndedElsewhere(_ key: String, chat: Bool, at now: Int64) {
        guard sessions[key] != nil, pipOrder(at: now).count > 1, watched(at: now) != key else { return }
        unseen[key] = now
        let name = label(of: key)
        pill = (key, chat ? "\(name) waits for you" : "\(name) finished", now)
    }

    /// The longest name the board gives an agent in a pill, in bytes.
    static let maxLabelBytes = 12
    /// The longest name the board's line gives the agent the screen
    /// follows, in its pip, in bytes: about what the line holds beside one
    /// other pip (the gel's `fitPips`), which cuts it shorter, with "…",
    /// beside more.
    static let maxWatchNameBytes = 28

    /// What the board calls the agent `key` in a pill: its project, else
    /// its agent. When another live agent works in the same project (every
    /// thread in one folder), its thread's name, so the two can be told
    /// apart.
    func label(of key: String) -> String {
        guard let (name, thread) = name(of: key) else { return "" }
        return StateSnapshot.clip(name, marked: thread, max: Self.maxLabelBytes)
    }

    /// The same name, as the pip on the board's line shows the agent the
    /// screen follows: up to `maxWatchNameBytes`, and a longer one cut at a
    /// word where that keeps half of it, ending in "…", never a bare cut.
    func watchLabel(of key: String) -> String {
        guard let (name, _) = name(of: key) else { return "" }
        let text = StateSnapshot.drawable(name)
        guard text.utf8.count > Self.maxWatchNameBytes else { return text }
        let ellipsis = "\u{2026}"
        let cut = WorkStream.clip(text, Self.maxWatchNameBytes - ellipsis.utf8.count)
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " -_.·")) + ellipsis
    }

    /// `key`'s name, uncut, and whether it's its thread's.
    private func name(of key: String) -> (String, Bool)? {
        guard let s = sessions[key] else { return nil }
        if let name = s.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
           sessions.contains(where: { $0.key != key && $0.value.project == s.project }) {
            return (name, true)
        }
        return (s.project.isEmpty ? s.agent.rawValue : s.project, false)
    }

    /// The colour `key` is drawn in: its lane's while it has one, else its
    /// own, given the first time Boop sees it and kept while it lives, so
    /// an agent that has only rested still has a colour of its own.
    func slot(of key: String) -> Int {
        if let slot = stream.lanes[key]?.slot { return slot }
        return colour(key)
    }

    /// The session's own colour: the one it has, else the one the fewest
    /// other live sessions have, the lowest first.
    @discardableResult
    func colour(_ key: String) -> Int {
        if let c = stream.colours[key] { return c }
        for k in stream.colours.keys where sessions[k] == nil { stream.colours[k] = nil }
        var uses = [Int](repeating: 0, count: WorkStream.maxLanes)
        for c in stream.colours.values where c < uses.count { uses[c] += 1 }
        for lane in stream.lanes.values where lane.slot < uses.count { uses[lane.slot] += 1 }
        let c = uses.indices.min { (uses[$0], $0) < (uses[$1], $1) } ?? 0
        stream.colours[key] = c
        return c
    }

    /// The pips, the watched one and the pill for the `state`.
    func watchFields(into snapshot: inout StateSnapshot, at now: Int64) {
        let order = pipOrder(at: now)
        // Needs you takes the whole screen: no pips under it.
        guard order.count > 1, snapshot.attn == nil else { return }
        let (shown, dismissed, working, _) = groups(at: now)
        let waiting = Set((shown + dismissed).map(\.key)), busy = Set(working.map(\.key))
        let showing = Set(cards.showing(in: cardOrder(at: now), at: now))
        let watching = watched(at: now)
        if let w = watching { unseen[w] = nil }
        for key in unseen.keys where sessions[key] == nil || now - (unseen[key] ?? now) > 120_000 { unseen[key] = nil }
        snapshot.pips = order.map { key in
            let kind: Character = waiting.contains(key) || unseen[key] != nil ? "a"
                : showing.contains(key) ? "c" : busy.contains(key) ? "w" : "i"
            return StateSnapshot.Pip(kind: kind, slot: slot(of: key))
        }
        if let w = watching, let at = order.firstIndex(of: w), sessions[w] != nil {
            snapshot.watch = at
            snapshot.watchName = watchLabel(of: w)
        }
        if let p = pill, now - p.at < Self.pillMs, p.key != watching, let at = order.firstIndex(of: p.key) {
            snapshot.pill = StateSnapshot.Pill(at: at, text: p.text)
        } else {
            pill = nil
        }
    }
}
