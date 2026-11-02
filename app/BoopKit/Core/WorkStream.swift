import AgentHooks
import Foundation
import LinkKit

/// The work stream: every tool call as a word that falls behind Boop from
/// its agent's lane, and the few that come forward and hit it: a failure,
/// a helper, a big edit, a turn's end. A plain rule, as "needs you" is: it
/// reads each call's tool, topic, program, glimpse, size and result, never
/// what the call said, and decides which word each call is and which calls
/// come forward, one at a time, in which style. The board flies the words and
/// plays each style; the brain hears none of it but the moments that hit
/// (`TranscriptView`).
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
    enum Priority {
        /// A failure: always.
        case always
        /// A big edit, a helper: when nothing else is forward.
        case notable
    }

    /// A word that comes forward: the `call` the board plays.
    struct Forward: Equatable {
        var slot: Int
        var word: String
        /// The style, one the board's `render::CallStyle` knows.
        var style: String
        var priority: Priority

        /// The `do`'s `args`.
        var args: JSONObject { BoopDevice.call(word, style: style, slot: slot) }
    }

    /// The styles of a moment that hits Boop that the brain hears of: not a
    /// check's failure, which is a line of its own already.
    static let hits: Set<String> = ["bonk", "bonk2", "bonk3", "throw", "timeout", "no"]
    /// The failure ladder's rungs: one agent's failures within `ladderMs`.
    static let ladder = ["bonk", "bonk2", "bonk3", "throw"]

    /// The `did`'s action for a word that came forward.
    static let action = BoopDevice.call

    /// A word forward holds the board this long; a notable or a sure one
    /// may wait this long for it.
    static let showMs: Int64 = 2500
    static let waitMs: Int64 = 1500
    /// One session's failures within this climb the ladder.
    static let ladderMs: Int64 = 120_000

    /// Whether a call's end climbs the failure ladder: a failure, but not
    /// a lookup that found nothing, a timeout, a request you denied, or a
    /// check's, which have styles of their own.
    static func climbs(_ e: AgentEvent) -> Bool {
        guard e.failed == true else { return false }
        switch e.error {
        case ToolError.exitCode where e.topic == Topic.inspect: return false
        case ToolError.timeout, ToolError.denied: return false
        default: return e.topic.map(TranscriptView.checks.contains) != true
        }
    }
    /// An edit of this many lines or more is notable.
    static let bigEdit = 100
    /// The most lanes the board shows, and the longest word it gets, in
    /// bytes: the whole `state` stays well under the board's 512.
    static let maxLanes = 4
    static let maxWordBytes = 14
    /// The `state` carries a lane's new word at most this often.
    static let sendEveryMs: Int64 = 250

    /// A work act: a command Boop plays out for as long as it runs, by a
    /// plain rule, with a low sign saying what's running. The board draws
    /// it from `state` and times nothing but its own beats; the result ends
    /// it. What Boop says over it is Jev's (`Event.Kind.act`).
    struct Act: Equatable {
        /// `push`, `tests` or `build`.
        var kind: String
        /// What its sign says now.
        var words: String
        /// Its session, and the call it plays out.
        var session: String
        var callID: String?
        /// The full scene, or only the prop and the sign: see `isFull`.
        var full: Bool
        var startedAt: Int64
        /// How it ended, once it has, and until when `state` holds that.
        var passed: Bool?
        var until: Int64?
    }
    /// The full act plays when its kind hasn't played fully in this long, or
    /// it's the first of the day; otherwise the small version.
    static let fullEveryMs: Int64 = 30 * 60_000
    /// How long an act's opening plays, however soon its command ends, and
    /// how long its result shows: `actLeadMs` and `actResultMs` on the board.
    static func leadMs(_ kind: String, full: Bool) -> Int64 { !full ? 900 : kind == "push" ? 3400 : 1800 }
    static func resultMs(full: Bool) -> Int64 { full ? 6000 : 2600 }
    /// What each act's sign says at a pass; a failure's says `FAIL`.
    static let passWords = ["push": "shipped!", "tests": "PASS", "build": "BUILT"]
    /// A failure after this long gets the full ending, whichever version
    /// started: not a push's, whose crash needs its rocket's start.
    static let longRunMs: Int64 = 60_000

    var act: Act?
    /// When each kind last played fully.
    var fullAt: [String: Int64] = [:]

    var lanes: [String: Lane] = [:]
    var heldUntil: Int64 = .min
    var heldPriority = Priority.notable
    var failures: [String: [Int64]] = [:]
    /// The sessions whose turn has had a call since it started.
    var called: Set<String> = []

    // MARK: Words

    /// The word for a call, which its styles read:
    /// its program, or a check's topic for a program alone (`make`,
    /// `tests`); with a subcommand the program says more (`make fw-test`).
    static func word(_ e: AgentEvent, program: String?) -> String {
        let word: String
        switch e.toolKind ?? .other {
        case .shell:
            let check = e.topic.flatMap { TranscriptView.checks.contains($0) ? $0 : nil }
            word = program.flatMap { $0.contains(" ") || check == nil ? $0 : nil } ?? check ?? program ?? "bash"
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

    /// What the board shows for a call: its word, or one of the pieces of
    /// its glimpse (`Core.swift`, `maxWordBytes`), each as likely, picked
    /// by the call's ID so its start and end show the same. An edit shows
    /// its file with its lines added when they fit (`Core +12`).
    static func shown(_ e: AgentEvent, word: String) -> String {
        var pieces = (e.glimpse ?? "").split(separator: " ").map { fit(String($0)) }.filter { !$0.isEmpty }
        if e.toolKind == .edit, let added = e.linesAdded, added > 0 {
            pieces = pieces.map { piece in
                let bare = (piece as NSString).deletingPathExtension, stem = bare.isEmpty ? piece : bare
                let both = "\(stem) +\(added)"
                return both.utf8.count <= maxWordBytes ? both : piece
            }
        }
        guard !pieces.isEmpty else { return word }
        let options = [word] + pieces
        return options[Int(pick(e.toolUseID ?? "\(e.key)\(e.at)") % UInt64(options.count))]
    }

    /// A glimpse's piece cut to fit a word: without its extension when
    /// it's too long with it (`TranscriptView.swift` is `TranscriptView`),
    /// then clipped.
    static func fit(_ piece: String) -> String {
        guard piece.utf8.count > maxWordBytes else { return piece }
        let stem = (piece as NSString).deletingPathExtension
        return clip(stem.isEmpty ? piece : stem, maxWordBytes)
    }

    /// A number from `text` that's the same on every launch (FNV-1a), to
    /// pick by.
    static func pick(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037 as UInt64) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
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

    // MARK: Acts

    /// The act a shell call plays out, and its sign's words, by its topic and
    /// program: never its text, but a pull request's verb, which is its
    /// glimpse's first piece.
    static func actFor(_ e: AgentEvent, program: String?) -> (kind: String, words: String)? {
        guard e.toolKind == .shell else { return nil }
        if e.topic == "tests" { return ("tests", "running tests") }
        if e.topic == "build" { return ("build", "building") }
        if e.topic == "deploy" { return ("push", "deploy") }
        if program == "git push" { return ("push", "git push") }
        if program == "gh pr", let verb = e.glimpse?.split(separator: " ").first, verb == "create" || verb == "merge" {
            return ("push", "pull request")
        }
        return nil
    }

    /// Whether an act of `kind` starting at `now` plays fully: it hasn't for
    /// `fullEveryMs`, or it's the first of `day`.
    func isFull(_ kind: String, at now: Int64, sameDay: (Int64) -> Bool) -> Bool {
        guard let last = fullAt[kind] else { return true }
        return now - last >= Self.fullEveryMs || !sameDay(last)
    }

    /// A shell call starting may begin an act: one at a time, so another
    /// agent's call while one runs is only its word.
    mutating func startAct(_ e: AgentEvent, program: String?, at now: Int64, sameDay: (Int64) -> Bool) -> Act? {
        guard let (kind, words) = Self.actFor(e, program: program), act == nil || act?.passed != nil else { return nil }
        let full = isFull(kind, at: now, sameDay: sameDay)
        if full { fullAt[kind] = now }
        act = Act(kind: kind, words: words, session: e.key, callID: e.toolUseID, full: full, startedAt: now)
        return act
    }

    /// A call ending ends the act it plays out, by its result. A timeout or
    /// a request you denied isn't a result: those have words of their own,
    /// and the act just stops.
    mutating func endAct(_ e: AgentEvent, at now: Int64) -> Act? {
        guard var running = act, running.passed == nil, running.session == e.key,
              running.callID == nil || e.toolUseID == nil || running.callID == e.toolUseID else { return nil }
        if e.error == ToolError.timeout || e.error == ToolError.denied || e.failed == nil {
            act = nil
            return nil
        }
        let passed = e.failed == false
        running.passed = passed
        running.words = passed ? Self.passWords[running.kind] ?? "PASS" : "FAIL"
        if !passed, running.kind != "push", now - running.startedAt >= Self.longRunMs { running.full = true }
        running.until = max(now, running.startedAt + Self.leadMs(running.kind, full: running.full))
            + Self.resultMs(full: running.full)
        act = running
        return running
    }

    /// An act goes when its result has shown, or, with no end heard, when
    /// its session is no longer in `alive`: working, or waiting on you.
    mutating func keepAct(alive: Set<String>, at now: Int64) {
        guard let running = act else { return }
        if let until = running.until {
            if now >= until { act = nil }
        } else if !alive.contains(running.session) {
            act = nil
        }
    }

    // MARK: Calls

    /// A tool call starting in session `key`: its word joins its lane, and
    /// a helper going off may come forward.
    mutating func started(_ e: AgentEvent, program: String?, at now: Int64) -> Forward? {
        let key = e.key, word = Self.word(e, program: program), shown = Self.shown(e, word: word)
        // A lane of its own while one is free: a fifth session gets none,
        // and no other's slot, until one frees; its words still come forward.
        let slot: Int
        if var lane = lanes[key] ?? openSlot().map({ Lane(slot: $0, count: 0, word: shown) }) {
            lane.count = (lane.count + 1) % 1000
            lane.word = shown
            lanes[key] = lane
            slot = lane.slot
        } else {
            slot = freeSlot()
        }
        // The act it plays out is what shows, not a word forward.
        if let act, act.passed == nil, act.session == key, act.callID == e.toolUseID { return nil }
        called.insert(key)
        if e.toolKind == .subagent {
            return offer(Forward(slot: slot, word: word, style: "helper", priority: .notable), at: now)
        }
        return nil
    }

    /// A tool call ending: a failure or a big edit comes forward. Anything else is only its word, falling.
    mutating func ended(_ e: AgentEvent, program: String?, at now: Int64) -> Forward? {
        let key = e.key, word = Self.word(e, program: program)
        let slot = lanes[key]?.slot ?? freeSlot()
        if Self.climbs(e) {
            let recent = (failures[key] ?? []).filter { now - $0 < Self.ladderMs } + [now]
            failures[key] = recent
            let style = Self.ladder[min(recent.count, Self.ladder.count) - 1]
            return offer(Forward(slot: slot, word: word, style: style, priority: .always), at: now)
        }
        if e.failed == true {
            switch e.error {
            case ToolError.exitCode where e.topic == Topic.inspect:
                // A lookup that exits 1 found nothing.
                return offer(Forward(slot: slot, word: word, style: "shrug", priority: .always), at: now)
            case ToolError.timeout:
                return offer(Forward(slot: slot, word: "timeout", style: "timeout", priority: .always), at: now)
            case ToolError.denied:
                return offer(Forward(slot: slot, word: "NO", style: "no", priority: .always), at: now)
            default:
                // A check's act has its own ending, and another agent's act its word.
                return nil
            }
        }
        let added = e.linesAdded ?? 0, removed = e.linesRemoved ?? 0
        if e.toolKind == .edit, added + removed >= Self.bigEdit {
            let style = removed > added ? "shatter" : "land"
            let shown = removed > added ? "-\(removed)" : Self.shown(e, word: word)
            return offer(Forward(slot: slot, word: shown, style: style, priority: .notable), at: now)
        }
        return nil
    }

    /// A helper coming back to its turn: "back", never the "done" a
    /// finished turn falls as.
    mutating func helperBack(_ key: String, at now: Int64) -> Forward? {
        guard let lane = lanes[key] else { return nil }
        return offer(Forward(slot: lane.slot, word: "back", style: "back", priority: .notable), at: now)
    }

    /// A turn of session `e.key` ending, if it called a tool: done, it
    /// gathers its words up; failed, by why (a full context buries it, a rate
    /// limit or an overload freezes them, anything else drops them); stopped,
    /// they drop. Always forward: the turn's end is news.
    mutating func turnEnded(_ e: AgentEvent, at now: Int64) -> Forward? {
        let key = e.key
        guard called.contains(key) else { return nil }
        called.remove(key)
        let shown: (word: String, style: String)
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
        return offer(Forward(slot: lanes[key]?.slot ?? freeSlot(), word: shown.word, style: shown.style, priority: .always),
                     at: now)
    }

    /// The context of session `key` compacted while it works: its words
    /// squashed into a cube.
    mutating func compacted(_ key: String, at now: Int64) -> Forward? {
        guard let lane = lanes[key] else { return nil }
        return offer(Forward(slot: lane.slot, word: "context", style: "compact", priority: .always), at: now)
    }

    /// A turn starting in `key`: it has called no tool yet, so `turnEnded`
    /// waits for its first; and an act of its still running had its end lost.
    mutating func turnStarted(_ key: String) {
        called.remove(key)
        if act?.session == key, act?.passed == nil { act = nil }
    }

    /// Keeps the lanes of the sessions in `working` only, freeing the
    /// rest's slots.
    mutating func keep(_ working: Set<String>) {
        for key in lanes.keys where !working.contains(key) { lanes[key] = nil }
    }

    /// Whether `f` comes forward now: one at a time, held for `showMs`. A
    /// sure one cuts any other and waits up to `waitMs` behind another
    /// sure one; a notable one waits as long for the board to free. A word
    /// that waits plays when the board frees; the board times it.
    mutating func offer(_ f: Forward, at now: Int64) -> Forward? {
        var starts = now
        let cuts = f.priority == .always && heldPriority != .always
        if now < heldUntil, !cuts {
            guard heldUntil - now <= Self.waitMs else { return nil }
            starts = heldUntil
        }
        heldUntil = starts + Self.showMs
        heldPriority = f.priority
        return f
    }

    /// The lowest slot no lane holds, or nil when all are taken.
    func openSlot() -> Int? {
        let taken = Set(lanes.values.map(\.slot))
        return (0..<Self.maxLanes).first { !taken.contains($0) }
    }

    /// Where a word with no lane comes forward from: the lowest free
    /// slot, or the last when all are taken.
    func freeSlot() -> Int { openSlot() ?? Self.maxLanes - 1 }

    /// The lanes of the sessions in `working` for `state`, by slot.
    func calls(_ working: Set<String>) -> [StateSnapshot.Call] {
        lanes.filter { working.contains($0.key) }.values.sorted { $0.slot < $1.slot }.prefix(Self.maxLanes)
            .map { StateSnapshot.Call(slot: $0.slot, count: $0.count, word: $0.word) }
    }
}
