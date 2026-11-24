import AgentHooks
import Foundation
import LinkKit

/// The work stream: every tool call as what its agent is doing, its lane's
/// latest, which the board shows first in the strip as the work's term, and
/// the few that come forward and hit Boop: a failure, a helper, a big
/// edit, a turn's end. A plain rule, as "needs you" is: it
/// reads each call's tool, topic, program, glimpse, size and result, never
/// what the call said, and decides which word each call is and which calls
/// come forward, one at a time, in which style. The board shows the newest word,
/// flies those that come forward and plays each style; the brain hears none of it but the moments that hit
/// (`TranscriptView`).
struct WorkStream {
    /// A working session's lane on the board: its slot, which picks its
    /// column and colour, how many calls it has made since it got the
    /// lane, and its latest word. No name: the colours tell the agents
    /// apart, and the screen has no room for whose is whose.
    struct Lane: Equatable {
        var slot: Int
        var count: Int
        /// What it's doing, as the strip shows it now.
        var word: String
        /// When `word` began to show, and the next one waiting for it to
        /// have shown `holdMs`: the words never flicker.
        var since: Int64 = 0
        var next: String?
        /// Its calls still running, when the latest started, and when the
        /// last one ended: a long call says how long, and a quiet spell
        /// says "thinking".
        var open: Int = 0
        var callStart: Int64 = 0
        var lastEnd: Int64 = 0

        /// What the strip says for it at `now`: its word, the one waiting
        /// once it may show, the time a long call has run, or "thinking"
        /// when no call has run for `thinkingMs`.
        func shown(at now: Int64) -> String {
            if open == 0, lastEnd > 0, now - lastEnd >= WorkStream.thinkingMs { return "thinking" }
            let phrase = next.flatMap { now - since >= WorkStream.holdMs ? $0 : nil } ?? word
            guard open > 0, now - callStart >= WorkStream.longCallMs else { return phrase }
            let tail = " · \((now - callStart) / 60_000) min"
            return WorkStream.clip(phrase, WorkStream.maxDoingBytes - tail.utf8.count) + tail
        }

        /// Takes `phrase` as its word: at once when the last has shown
        /// `holdMs`, else as the next, which shows when it has.
        mutating func say(_ phrase: String, at now: Int64) {
            if let next, now - since >= WorkStream.holdMs { (word, since, self.next) = (next, since + WorkStream.holdMs, nil) }
            if now - since >= WorkStream.holdMs {
                (word, since, next) = (phrase, now, nil)
            } else if phrase != word {
                next = phrase
            }
        }
    }

    /// A phrase in the strip shows this long at least, however fast the
    /// calls come; a call running this long says how long; a turn with
    /// no call running for this long is "thinking".
    static let holdMs: Int64 = 1000
    static let longCallMs: Int64 = 60_000
    static let thinkingMs: Int64 = 4000

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
    /// Each session's own colour, a slot it keeps from when Boop first sees
    /// it (`Core.colour`): its lane takes that slot when it's free, so its
    /// pip, monitor, card and drawer row stay one colour across turns.
    var colours: [String: Int] = [:]
    static let maxWordBytes = 14
    /// The `state` carries a lane's new word at most this often.
    static let sendEveryMs: Int64 = 250

    /// A work act: a command worth naming, for as long as it runs, by a
    /// plain rule: a low sign says what's running, then how it ended, and
    /// Boop hops at a pass and flinches at a fail. The board draws it from
    /// `state`; the result ends it. What Boop says at a push's result is
    /// Jev's (`Event.Kind.act`).
    struct Act: Equatable {
        /// `push`, `tests` or `build`.
        var kind: String
        /// What its sign says now.
        var words: String
        /// Its session, and the call it plays out.
        var session: String
        var callID: String?
        var startedAt: Int64
        /// How it ended, once it has, and until when `state` holds that.
        var passed: Bool?
        var until: Int64?
    }
    /// How long an act's sign says what's running, however soon its command
    /// ends, and how long its result shows: `kActLeadMs` and `kActResultMs`
    /// on the board.
    static let leadMs: Int64 = 900, resultMs: Int64 = 2600
    /// What each act's sign says at a pass; a failure's says `fail`. Lower
    /// case, as everything Boop holds is.
    static let passWords = ["push": "shipped!", "tests": "pass", "build": "built"]

    var act: Act?

    var lanes: [String: Lane] = [:]
    var heldUntil: Int64 = .min
    var heldPriority = Priority.notable
    var failures: [String: [Int64]] = [:]
    /// The sessions whose turn has had a call since it started that did
    /// more than look.
    var called: Set<String> = []

    // MARK: Words

    /// The word for a call that comes forward from the monitor: what it's
    /// doing, cut at a word to `maxWordBytes`, so the words that fly say
    /// the same as the strip and never a bare tool's name.
    /// A command's "running" goes, so a failure that hits Boop names what
    /// failed ("make", "tests").
    static func word(_ e: AgentEvent, program: String?) -> String { word(doing: doing(e, program: program)) }

    /// The word for a call whose `doing` is known.
    static func word(doing: String) -> String {
        var phrase = doing
        for lead in ["running the ", "running "] where phrase.hasPrefix(lead) && phrase.count > lead.count {
            phrase = String(phrase.dropFirst(lead.count))
            break
        }
        return clip(phrase, maxWordBytes)
    }

    /// What a big edit says as it lands: its file and its lines added
    /// when they fit (`Core +12`), else its word.
    static func shown(_ e: AgentEvent, word: String) -> String {
        guard e.toolKind == .edit, let added = e.linesAdded, added > 0,
              let piece = (e.glimpse ?? "").split(separator: " ").first.map(String.init) else { return word }
        let stem = (piece as NSString).deletingPathExtension, both = "\(stem.isEmpty ? piece : stem) +\(added)"
        return both.utf8.count <= maxWordBytes ? both : word
    }

    /// The longest a lane's doing may be, in bytes: what the strip shows
    /// first, in its own font, with the counts as marks after it.
    static let maxDoingBytes = 24

    /// What the agent is doing in a call, for its lane: always a verb and
    /// what it's done to, in plain words, never a bare tool's or file's
    /// name ("searching TODO", "reading Core.swift", "editing Core.swift
    /// +12", "running the tests", "committing"), cut to `maxDoingBytes`,
    /// the object before the verb. A search names its pattern, never the
    /// tool (documentation/design/screen-guide.md, "The strip's words").
    static func doing(_ e: AgentEvent, program: String?) -> String {
        let (verb, what) = phrase(e, program: program)
        guard let what, !what.isEmpty else { return clip(verb, maxDoingBytes) }
        let room = maxDoingBytes - verb.utf8.count - 1
        guard room >= 4 else { return clip(verb, maxDoingBytes) }
        // Cut at a word's end when it has words ("unittest discover" is
        // "unittest", never "unittest discove").
        return "\(verb) \(fit(what, room: room))"
    }

    /// The commands whose verb says what they do: by the program and its
    /// subcommand, as `program` gives them, else by the program alone.
    /// Those that take an object take the glimpse's first piece.
    static let commandVerbs: [String: (verb: String, object: Bool)] = [
        "git commit": ("committing", false), "git push": ("pushing", false), "git pull": ("pulling", false),
        "git fetch": ("fetching", false), "git merge": ("merging", false), "git rebase": ("rebasing", false),
        "git checkout": ("switching branch", false), "git switch": ("switching branch", false),
        "git clone": ("cloning", false), "git add": ("staging files", false), "git stash": ("stashing", false),
        "git status": ("checking git", false), "git diff": ("reading the diff", false),
        "git log": ("reading git history", false), "git show": ("reading a commit", false),
        "git reset": ("resetting git", false), "git restore": ("restoring files", false),
        "gh pr": ("on a pull request", false), "gh": ("using GitHub", false),
        "npm install": ("installing packages", false), "npm i": ("installing packages", false),
        "npm ci": ("installing packages", false), "yarn add": ("installing packages", false),
        "yarn install": ("installing packages", false), "pnpm install": ("installing packages", false),
        "pnpm add": ("installing packages", false), "bun install": ("installing packages", false),
        "bun add": ("installing packages", false), "pip install": ("installing packages", false),
        "pip3 install": ("installing packages", false), "uv add": ("installing packages", false),
        "uv sync": ("installing packages", false), "uv pip": ("installing packages", false),
        "poetry install": ("installing packages", false), "brew install": ("installing packages", false),
        "cargo add": ("installing packages", false), "swift package": ("resolving packages", false),
        "swiftc": ("compiling", true), "clang": ("compiling", true), "clang++": ("compiling", true),
        "gcc": ("compiling", true), "g++": ("compiling", true), "cc": ("compiling", true),
        "javac": ("compiling", true), "rustc": ("compiling", true),
        "curl": ("downloading", false), "wget": ("downloading", false), "sleep": ("waiting", false),
        "mkdir": ("making a folder", false), "rm": ("deleting", true), "mv": ("moving files", false),
        "cp": ("copying files", false), "chmod": ("changing permissions", false), "open": ("opening", true),
        "kill": ("stopping a process", false), "pkill": ("stopping a process", false),
        "killall": ("stopping a process", false), "cat": ("reading", true), "head": ("reading", true),
        "tail": ("reading", true), "less": ("reading", true), "ls": ("listing", true), "tree": ("listing", true),
        "wc": ("counting", true), "diff": ("comparing", true),
    ]
    /// Programs that run a script: they name the script when the glimpse
    /// starts with one.
    static let interpreters: Set<String> = ["python", "python3", "node", "ruby", "bash", "sh", "zsh", "deno", "bun",
                                            "tsx", "ts-node", "perl", "php", "swift", "uv run"]
    /// Programs that search: they name what they look for.
    static let searchPrograms: Set<String> = ["rg", "grep", "ag", "ack", "find", "fd", "git grep"]
    /// What a check runs, in plain words.
    static let checkVerbs = ["tests": "running the tests", "build": "building", "deploy": "deploying"]

    /// The verb for a call and what it's done to, if anything.
    static func phrase(_ e: AgentEvent, program: String?) -> (verb: String, what: String?) {
        let first = (e.glimpse ?? "").split(separator: " ").first.map(String.init)
        switch e.toolKind ?? .other {
        case .shell:
            if let check = e.topic.flatMap({ checkVerbs[$0] }) { return (check, nil) }
            guard let program else { return ("running a command", nil) }
            if searchPrograms.contains(program) { return ("searching", first) }
            let base = program.split(separator: " ").first.map(String.init) ?? program
            if let known = commandVerbs[program] ?? commandVerbs[base] { return (known.verb, known.object ? first : nil) }
            if interpreters.contains(program) || interpreters.contains(base) {
                if let script = first, script.contains("."), !script.hasPrefix("-") {
                    return ("running", (script as NSString).lastPathComponent)
                }
                return ("running", base)
            }
            if e.topic == Topic.inspect, let first { return ("looking at", first) }
            return ("running", program)
        case .edit:
            guard let piece = first else {
                if let added = e.linesAdded, added > 0, e.topic != "docs" { return ("editing", "+\(added)") }
                return ("editing", e.topic == "docs" ? "docs" : nil)
            }
            guard let added = e.linesAdded, added > 0 else { return ("editing", piece) }
            let tail = " +\(added)", room = maxDoingBytes - "editing ".utf8.count - tail.utf8.count
            let stem = (piece as NSString).deletingPathExtension
            let name = piece.utf8.count <= room ? piece : StateSnapshot.clip(stem.isEmpty ? piece : stem, max: max(room, 4))
            return ("editing", name + tail)
        case .read: return ("reading", first)
        case .search: return ("searching", first)
        case .web: return (e.tool?.lowercased().contains("search") == true ? "searching" : "reading", first)
        case .subagent: return ("sending a helper", nil)
        case .planning: return ("planning", nil)
        case .mcp:
            let parts = (e.tool ?? "").components(separatedBy: "__")
            return ("using", parts.count > 1 && !parts[1].isEmpty ? parts[1] : "a tool")
        case .other: return ("using", spaced(e.tool ?? "a tool"))
        }
    }

    /// A glimpse's piece cut to fit `room` bytes: without its extension
    /// when it's too long with it (`TranscriptView.swift` is
    /// `TranscriptView`), then cut at a word's end when it can be.
    static func fit(_ piece: String, room: Int) -> String {
        guard piece.utf8.count > room else { return piece }
        let stem = (piece as NSString).deletingPathExtension
        return clip(stem.isEmpty ? piece : stem, room)
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

    /// A shell call starting may begin an act: one at a time, so another
    /// agent's call while one runs is only its word.
    mutating func startAct(_ e: AgentEvent, program: String?, at now: Int64) -> Act? {
        guard let (kind, words) = Self.actFor(e, program: program), act == nil || act?.passed != nil else { return nil }
        act = Act(kind: kind, words: words, session: e.key, callID: e.toolUseID, startedAt: now)
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
        running.words = passed ? Self.passWords[running.kind] ?? "pass" : "fail"
        running.until = max(now, running.startedAt + Self.leadMs) + Self.resultMs
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
        let key = e.key, shown = Self.doing(e, program: program), word = Self.word(doing: shown)
        // A lane of its own while one is free: a fifth session gets none,
        // and no other's slot, until one frees; its words still come forward.
        let slot: Int
        if var lane = lanes[key] ?? openSlot(prefer: colours[key]).map({ Lane(slot: $0, count: 0, word: shown, since: now - Self.holdMs) }) {
            lane.count = (lane.count + 1) % 1000
            lane.say(shown, at: now)
            lane.open += 1
            lane.callStart = now
            lanes[key] = lane
            slot = lane.slot
        } else {
            slot = freeSlot()
        }
        // The act it plays out is what shows, not a word forward.
        if let act, act.passed == nil, act.session == key, act.callID == e.toolUseID { return nil }
        // A turn whose calls only looked answered you, as a chat turn does.
        if !TranscriptView.onlyLooks(e, topic: e.topic) { called.insert(key) }
        if e.toolKind == .subagent {
            return offer(Forward(slot: slot, word: word, style: "helper", priority: .notable), at: now)
        }
        return nil
    }

    /// A tool call ending: a failure or a big edit comes forward. Anything else is only its word, in the strip.
    mutating func ended(_ e: AgentEvent, program: String?, at now: Int64) -> Forward? {
        let key = e.key, word = Self.word(e, program: program)
        let slot = lanes[key]?.slot ?? freeSlot()
        if var lane = lanes[key] {
            lane.open = max(0, lane.open - 1)
            lane.lastEnd = now
            lanes[key] = lane
        }
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
    /// gathers its words up; failed or stopped, they drop, under a word for
    /// why. Always forward: the turn's end is news.
    mutating func turnEnded(_ e: AgentEvent, at now: Int64) -> Forward? {
        let key = e.key
        guard called.contains(key) else { return nil }
        called.remove(key)
        let shown: (word: String, style: String)
        switch e.outcome {
        case .done?: shown = ("done", "gather")
        case .failed?:
            switch e.error {
            case "context_limit": shown = ("context full", "drop")
            case "rate_limit": shown = ("rate limit", "drop")
            case "overloaded": shown = ("overloaded", "drop")
            default: shown = ("failed", "drop")
            }
        case .stopped?: shown = ("stopped", "drop")
        case nil: return nil
        }
        return offer(Forward(slot: lanes[key]?.slot ?? freeSlot(), word: shown.word, style: shown.style, priority: .always),
                     at: now)
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

    /// The lowest slot no lane holds, or nil when all are taken; the
    /// session's own colour (`prefer`) first when it's free.
    func openSlot(prefer: Int? = nil) -> Int? {
        let taken = Set(lanes.values.map(\.slot))
        if let prefer, (0..<Self.maxLanes).contains(prefer), !taken.contains(prefer) { return prefer }
        return (0..<Self.maxLanes).first { !taken.contains($0) }
    }

    /// Where a word with no lane comes forward from: the lowest free
    /// slot, or the last when all are taken.
    func freeSlot() -> Int { openSlot() ?? Self.maxLanes - 1 }

    /// The lanes of the sessions in `working` for `state`, by slot.
    func calls(_ working: Set<String>, at now: Int64) -> [StateSnapshot.Call] {
        lanes.filter { working.contains($0.key) }.values.sorted { $0.slot < $1.slot }.prefix(Self.maxLanes)
            .map { StateSnapshot.Call(slot: $0.slot, count: $0.count, word: $0.shown(at: now)) }
    }
}
