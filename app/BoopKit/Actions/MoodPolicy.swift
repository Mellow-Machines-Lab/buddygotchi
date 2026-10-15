import Foundation
import MellowHarness

/// Which of the mood graph's moves are offered now, by the pack's pacing
/// (characters/CHARACTER.md §5), for every pack. Pure: the options follow
/// from the mood, the event and the log view alone, never animation state.
/// Validation reads the view after its pass is logged, which doesn't use up
/// its own event (`fresh`), so it offers what asking did unless a pacing
/// boundary passed while the brain answered.
public enum MoodPolicy {
    /// A shortest ordinary path toward the resting mood supplies a justified softening
    /// edge. It never restores a remembered mood or invents an edge.
    public static func recovery(from mood: String) -> String? {
        guard mood != MoodAction.initial, let node = MoodGraph.mood(mood) else { return nil }
        var queue = node.moves.ordinary.map { ($0, $0) }, seen: Set<String> = [mood]
        while !queue.isEmpty {
            let (next, first) = queue.removeFirst()
            if next == MoodAction.initial { return first }
            if seen.insert(next).inserted {
                queue += (MoodGraph.mood(next)?.moves.ordinary ?? []).map { ($0, first) }
            }
        }
        return nil
    }

    /// Source identity, with the upstream tool-call id when present; two
    /// copies of a turn end refer to the same preceding turn start.
    public static func identity(_ e: Event, _ log: LogView) -> String {
        let prefix = [e.source, e.session ?? "", e.subagent ?? "", e.kind]
        func key(_ id: String) -> String { JSONLine.encode(prefix + [id]) }
        if let id = e["tool_use_id"]?.string { return key(id) }
        if e.kind == "turn_end", let start = start(of: e, log) { return key(String(start.seq)) }
        return key(String(e.seq))
    }

    /// The turn start a turn end closes: the newest of its thread's before it.
    static func start(of e: Event, _ log: LogView) -> Event? {
        log.last("turn_start") { $0.seq < e.seq && sameThread($0, e) }
    }

    static func sameThread(_ a: Event, _ b: Event) -> Bool {
        a.source == b.source && a.session == b.session && a.subagent == b.subagent
    }

    /// The evidence, unless a pass or a mood change already used it: one
    /// for `e`, or for a copy of it (the same thread, kind and `identity`).
    /// A pass uses it even when its answer was stay.
    static func fresh(_ e: Event?, _ log: LogView) -> Event? {
        guard let e, e.seq > 0, e.at <= log.now, log.now - e.at <= MoodGraph.pacing.freshEvidenceMs,
              ["turn_start", "turn_end", "tool_end", "subagent_end", "poke", "talk", "presence_end"].contains(e.kind) else { return nil }
        let id = identity(e, log)
        // Only the copies are looked at, through the log's indexes, never
        // the whole day's log: a tool call's by its id, a turn end's after
        // its turn's start, and an event with neither is its only copy.
        // (Another key could match only a tool-call id that is a bare log
        // seq, which none is.)
        let copies: [Event] =
            if let call = e["tool_use_id"]?.string {
                log.all(e.kind) { sameThread($0, e) && $0["tool_use_id"]?.string == call }
            } else if e.kind == "turn_end", let start = start(of: e, log) {
                log.all(e.kind, since: start) { sameThread($0, e) && identity($0, log) == id }
            } else {
                [e]
            }
        let consumed = copies.contains { c in
            // A pass for `e` itself is the one deciding it, never an
            // earlier decision: MellowHarness gives an event one pass at most,
            // logs it, then hands each output that event to validate its
            // answers. It doesn't count, wherever
            // other outputs' and rules' events land after it.
            (c.seq != e.seq && log.answered(c.seq)) || log.dids(for: c.seq).contains { $0.action == MoodAction.actionName }
        }
        return consumed ? nil : e
    }

    /// Strong evidence is branch-specific. A routine tool failure is never
    /// danger or a dramatic jump. New social/alarm branches need a future
    /// explicit appraisal, so this adapter deliberately cannot infer them.
    static func strongDestinations(_ e: Event, _ log: LogView) -> Set<String> {
        if e.kind == "turn_end", let start = start(of: e, log), Band.length(ms: e.at - start.at) == "very long" {
            if e["outcome"]?.string == "failed" { return Set(CharacterPack.active.outcomes["big_failure"] ?? []) }
            if e["outcome"]?.string == "done" { return Set(CharacterPack.active.outcomes["big_success"] ?? []) }
        }
        return []
    }

    public static func destinations(from mood: String, event: Event?, log: LogView) -> MoodGraph.Moves {
        guard let node = MoodGraph.mood(mood) else { return .init(ordinary: [], dramatic: []) }
        let last = log.lastDid(MoodAction.actionName) { $0["ok"]?.bool == true && $0["to"]?.string != nil }
        let age = last.map { max(0, log.now - $0.at) } ?? Int64.max
        let evidence = fresh(event, log)
        let recovery = recovery(from: mood)
        let exitReady = age >= (node.brief ? MoodGraph.pacing.briefExitMs : MoodGraph.pacing.ordinaryDwellMs)
        var ordinary: [String] = []
        if exitReady {
            ordinary = node.moves.ordinary.filter { to in
                if node.brief { return to == recovery }
                let reverse = last?["from"]?.string == to
                if reverse && age < MoodGraph.pacing.reverseCooldownMs { return false }
                // Quiet can soften exactly one step. It cannot escalate.
                guard evidence != nil else { return to == recovery }
                // No routine work invents fear, loneliness or affection: the
                // pack's `quiet_never` moods.
                if CharacterPack.active.quietNever.contains(to) { return false }
                return true
            }
        }
        let strong = evidence.map { strongDestinations($0, log) } ?? []
        return .init(ordinary: ordinary, dramatic: node.moves.dramatic.filter { strong.contains($0) })
    }
}
