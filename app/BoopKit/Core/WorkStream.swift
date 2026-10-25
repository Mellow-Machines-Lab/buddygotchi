import AgentHooks
import Foundation
import LinkKit

/// The work stream: every tool call as a word that falls past Boop from
/// its agent's lane, and now and then one that comes forward and hits it.
/// A plain rule, as "needs you" is: it reads each call's tool, topic,
/// program, size and result, never what the call said, and decides which
/// word each call is and which calls come forward, one at a time, as
/// which gag. The board flies the words and plays the gags; the brain
/// hears none of it but the moments that hit (`TranscriptView`).
struct WorkStream {
    /// A working session's lane on the board: its slot, which picks its
    /// column and colour, how many calls it has made since it got the
    /// lane, and its latest word. No name: the colours tell the agents
    /// apart, and the screen has no room for whose is whose.
    struct Lane: Equatable {
        var slot: Int
        var count: Int
        var word: String
    }

    /// How sure a call is to come forward.
    enum Priority: Int, Comparable {
        /// A failure, a check's result: always.
        case always
        /// A check starting, a big edit, a helper, a turn's first call, a
        /// combo: when nothing else is forward.
        case notable
        /// Anything else: now and then.
        case ambient

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// A word that comes forward: the `call` the board plays.
    struct Forward: Equatable {
        var slot: Int
        var word: String
        /// The gag, one of `gags`.
        var gag: String
        var priority: Priority
        /// A combo's count, else nil.
        var count: Int?

        /// The `do`'s `args`.
        var args: JSONObject {
            var args: JSONObject = ["a": .int(slot), "w": .string(word), "as": .string(gag)]
            if let count { args["n"] = .int(count) }
            return args
        }
    }

    /// The gags the board knows for a word that comes forward.
    static let gags = [
        "arrive", "look", "land", "stir", "stamp", "launch", "poof", "plane", "phone", "page", "helper", "back",
        "shatter", "cross", "stack", "pass", "built", "hail", "bonk", "bonk2", "helmet", "throw", "shrug",
        "timeout", "no", "combo", "topple", "compact", "buried", "freeze", "drop", "gather",
    ]
    /// The gags of a moment that hits Boop that the brain hears of: not a
    /// check's failure, which is a line of its own already.
    static let hits: Set<String> = ["bonk", "bonk2", "helmet", "throw", "timeout", "no"]
    /// The failure ladder's rungs: one agent's failures within `ladderMs`.
    static let ladder = ["bonk", "bonk2", "helmet", "throw"]

    /// The `did`'s action for a word that came forward.
    static let action = "call"

    /// A word forward holds the board this long; a notable or a sure one
    /// may wait this long for it; an ambient one needs this long since
    /// any word came forward, and this long since its word did.
    static let holdMs: Int64 = 2500
    static let waitMs: Int64 = 1500
    static let ambientGapMs: Int64 = 8000
    static let sameWordGapMs: Int64 = 30_000
    /// A combo is the same word from one session, each within this of the
    /// last, and comes forward at these counts.
    static let comboGapMs: Int64 = 3000
    static let combos: Set<Int> = [5, 10, 20]
    /// One session's failures within this climb the ladder.
    static let ladderMs: Int64 = 120_000
    /// An edit of this many lines or more is notable.
    static let bigEdit = 100
    /// The most lanes the board shows, and the longest word it gets, in
    /// bytes: the whole `state` stays well under the board's 512.
    static let maxLanes = 4
    static let maxWordBytes = 14
    /// The `state` carries a lane's new word at most this often.
    static let sendEveryMs: Int64 = 250

    var lanes: [String: Lane] = [:]
    var heldUntil: Int64 = .min
    var heldPriority = Priority.ambient
    var lastForwardAt: Int64?
    var lastWordAt: [String: Int64] = [:]
    var failures: [String: [Int64]] = [:]
    var combo: [String: (word: String, count: Int, at: Int64)] = [:]
    /// The sessions whose turn has had a call since it started.
    var called: Set<String> = []

    // MARK: Words

    /// The word for a call: what the board shows falling.
    static func word(_ e: AgentEvent, program: String?) -> String {
        let word: String
        switch e.toolKind ?? .other {
        case .shell:
            word = e.topic.flatMap { TranscriptView.checks.contains($0) ? $0 : nil } ?? program ?? "bash"
        case .edit:
            if e.topic == "docs" {
                word = "docs"
            } else {
                let added = e.linesAdded ?? 0, removed = e.linesRemoved ?? 0
                word = (["edit"] + (added > 0 ? ["+\(added)"] : []) + (removed > 0 ? ["-\(removed)"] : [])).joined(separator: " ")
            }
        case .read: word = "read"
        case .search: word = (e.tool ?? "grep").lowercased()
        case .web: word = "web"
        case .subagent: word = "helper"
        case .planning: word = "plan"
        case .mcp:
            // `mcp__linear__create_issue`: the server you named.
            let parts = (e.tool ?? "").components(separatedBy: "__")
            word = parts.count > 1 && !parts[1].isEmpty ? parts[1] : "mcp"
        case .other: word = spaced(e.tool ?? "tool")
        }
        return clip(word, WorkStream.maxWordBytes)
    }

    /// A tool's name as words: `SendMessage` and `send_message` are `send
    /// message`.
    static func spaced(_ name: String) -> String {
        var out = ""
        for ch in name {
            if ch == "_" || ch == "-" {
                out.append(" ")
            } else if ch.isUppercase, let last = out.last, last != " " {
                out += " " + ch.lowercased()
            } else {
                out += ch.lowercased()
            }
        }
        return out
    }

    /// `text` cut to at most `max` bytes at a word's end when it can be.
    static func clip(_ text: String, _ max: Int) -> String {
        guard text.utf8.count > max else { return text }
        let cut = StateSnapshot.clip(text, max: max)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= max / 2 {
            return String(cut[..<space])
        }
        return cut
    }

    /// The gag a word that comes forward now and then plays: its program's
    /// family's.
    static func ambientGag(_ e: AgentEvent, word: String) -> String {
        switch e.toolKind ?? .other {
        case .read, .search: return "look"
        case .edit: return e.topic == "docs" ? "page" : "land"
        case .web: return "plane"
        case .mcp: return "phone"
        case .subagent: return "helper"
        default: break
        }
        if e.topic == Topic.inspect { return "look" }
        switch word {
        case "python", "node", "ruby", "perl", "deno", "bun", "loop", "osascript": return "stir"
        case "git commit", "git tag": return "stamp"
        case "git push", "vercel", "fly", "flyctl", "wrangler": return "launch"
        case "rm", "rmdir", "git clean", "git rm": return "poof"
        case "curl", "wget", "gh", "gh pr", "gh issue", "gh run", "gh api", "ssh", "scp", "rsync": return "plane"
        default: return "land"
        }
    }

    // MARK: Calls

    /// A tool call starting in session `key`: its word joins its lane, and
    /// a turn's first call, a check starting or a helper going off may
    /// come forward.
    mutating func started(_ e: AgentEvent, program: String?, at now: Int64) -> Forward? {
        let key = e.key, word = Self.word(e, program: program)
        var lane = lanes[key] ?? Lane(slot: freeSlot(), count: 0, word: word)
        lane.count = (lane.count + 1) % 1000
        lane.word = word
        lanes[key] = lane
        if !called.contains(key) {
            called.insert(key)
            return offer(Forward(slot: lane.slot, word: word, gag: "arrive", priority: .notable), at: now)
        }
        if let topic = e.topic, TranscriptView.checks.contains(topic) {
            let gag = topic == "tests" ? "cross" : topic == "build" ? "stack" : "launch"
            return offer(Forward(slot: lane.slot, word: word, gag: gag, priority: .notable), at: now)
        }
        if e.toolKind == .subagent {
            return offer(Forward(slot: lane.slot, word: word, gag: "helper", priority: .notable), at: now)
        }
        return nil
    }

    /// A tool call ending: a failure, a check's result, a big edit, a
    /// combo, or now and then any call, comes forward.
    mutating func ended(_ e: AgentEvent, program: String?, at now: Int64) -> Forward? {
        let key = e.key, word = Self.word(e, program: program)
        let slot = lanes[key]?.slot ?? freeSlot()
        let check = e.topic.flatMap { TranscriptView.checks.contains($0) ? $0 : nil }
        if e.failed == true {
            combo[key] = nil
            switch e.error {
            case ToolError.exitCode where e.topic == Topic.inspect:
                // A lookup that exits 1 found nothing.
                return offer(Forward(slot: slot, word: word, gag: "shrug", priority: .always), at: now)
            case ToolError.timeout:
                return offer(Forward(slot: slot, word: "timeout", gag: "timeout", priority: .always), at: now)
            case ToolError.denied:
                return offer(Forward(slot: slot, word: "NO", gag: "no", priority: .always), at: now)
            default:
                if let check {
                    // A failing build's tower falls on it; failing tests or a
                    // deploy rain on it.
                    return offer(Forward(slot: slot, word: "FAIL", gag: check == "build" ? "topple" : "hail",
                                         priority: .always), at: now)
                }
                let recent = (failures[key] ?? []).filter { now - $0 < Self.ladderMs } + [now]
                failures[key] = recent
                let gag = Self.ladder[min(recent.count, Self.ladder.count) - 1]
                return offer(Forward(slot: slot, word: word, gag: gag, priority: .always), at: now)
            }
        }
        if let check, e.failed == false {
            let (shown, gag) = check == "tests" ? ("PASS", "pass") : check == "build" ? ("built", "built") : ("shipped", "launch")
            return offer(Forward(slot: slot, word: shown, gag: gag, priority: .always), at: now)
        }
        let added = e.linesAdded ?? 0, removed = e.linesRemoved ?? 0
        if e.toolKind == .edit, added + removed >= Self.bigEdit {
            let gag = removed > added ? "shatter" : "land"
            let shown = removed > added ? "-\(removed)" : word
            return offer(Forward(slot: slot, word: shown, gag: gag, priority: .notable), at: now)
        }
        var run = combo[key].flatMap { $0.word == word && now - $0.at <= Self.comboGapMs ? $0 : nil }
            ?? (word: word, count: 0, at: now)
        run.count += 1
        run.at = now
        combo[key] = run
        if Self.combos.contains(run.count) {
            return offer(Forward(slot: slot, word: word, gag: "combo", priority: .notable, count: run.count), at: now)
        }
        return offer(Forward(slot: slot, word: word, gag: Self.ambientGag(e, word: word), priority: .ambient), at: now)
    }

    /// A helper coming back to its turn.
    mutating func helperBack(_ key: String, at now: Int64) -> Forward? {
        guard let lane = lanes[key] else { return nil }
        return offer(Forward(slot: lane.slot, word: "done", gag: "back", priority: .notable), at: now)
    }

    /// A turn of session `e.key` ending, if it called a tool: done, it
    /// gathers its words up; failed, by why (a full context buries it, a rate
    /// limit or an overload freezes them, anything else drops them); stopped,
    /// they drop. Always forward: the turn's end is news.
    mutating func turnEnded(_ e: AgentEvent, at now: Int64) -> Forward? {
        let key = e.key
        guard called.contains(key) else { return nil }
        called.remove(key)
        combo[key] = nil
        let shown: (word: String, gag: String)
        switch e.outcome {
        case .done?: shown = ("done", "gather")
        case .failed?:
            switch e.error {
            case "context_limit": shown = ("context full", "buried")
            case "rate_limit": shown = ("rate limit", "freeze")
            case "overloaded": shown = ("overloaded", "freeze")
            default: shown = ("failed", "drop")
            }
        case .stopped?: shown = ("stopped", "drop")
        case nil: return nil
        }
        return offer(Forward(slot: lanes[key]?.slot ?? freeSlot(), word: shown.word, gag: shown.gag, priority: .always),
                     at: now)
    }

    /// The context of session `key` compacted while it works: its words
    /// squashed into a cube.
    mutating func compacted(_ key: String, at now: Int64) -> Forward? {
        guard let lane = lanes[key] else { return nil }
        return offer(Forward(slot: lane.slot, word: "context", gag: "compact", priority: .always), at: now)
    }

    /// A turn starting in `key`: its next call is its first.
    mutating func turnStarted(_ key: String) {
        called.remove(key)
        combo[key] = nil
    }

    /// Keeps the lanes of the sessions in `working` only, freeing the
    /// rest's slots.
    mutating func keep(_ working: Set<String>) {
        for key in lanes.keys where !working.contains(key) { lanes[key] = nil }
    }

    /// Whether `f` comes forward now: one at a time, held for `holdMs`. A
    /// sure one cuts any other and waits up to `waitMs` behind another
    /// sure one; a notable one waits as long for the board to free; an
    /// ambient one needs the board free, `ambientGapMs` since anything
    /// came forward and `sameWordGapMs` since its word did. A word that
    /// waits plays when the board frees; the board times it.
    mutating func offer(_ f: Forward, at now: Int64) -> Forward? {
        var starts = now
        if now < heldUntil {
            if f.priority == .always, heldPriority != .always {
                starts = now
            } else if f.priority <= .notable, heldUntil - now <= Self.waitMs {
                starts = heldUntil
            } else {
                return nil
            }
        }
        if f.priority == .ambient {
            if let last = lastForwardAt, starts - last < Self.ambientGapMs { return nil }
            if let last = lastWordAt[f.word], starts - last < Self.sameWordGapMs { return nil }
        }
        heldUntil = starts + Self.holdMs
        heldPriority = f.priority
        lastForwardAt = starts
        lastWordAt[f.word] = starts
        return f
    }

    /// The lowest slot no lane holds, or the last when all are taken.
    func freeSlot() -> Int {
        let taken = Set(lanes.values.map(\.slot))
        return (0..<Self.maxLanes).first { !taken.contains($0) } ?? Self.maxLanes - 1
    }

    /// The lanes of the sessions in `working` for `state`, by slot.
    func calls(_ working: Set<String>) -> [StateSnapshot.Call] {
        lanes.filter { working.contains($0.key) }.values.sorted { $0.slot < $1.slot }.prefix(Self.maxLanes)
            .map { StateSnapshot.Call(slot: $0.slot, count: $0.count, word: $0.word) }
    }
}
