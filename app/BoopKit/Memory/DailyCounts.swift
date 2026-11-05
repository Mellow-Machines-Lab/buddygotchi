import Foundation
import MellowHarness

/// One Boop day in numbers, a row of `daily-counts.jsonl`, on this Mac: how
/// you and Boop got on, for the "This week" view and a summary you may choose
/// to send (`DayCounts.summary`). It holds only numbers and the date: no
/// words, threads or notes. Nothing sends it anywhere.
public struct DayCounts: Codable, Equatable, Sendable {
    public var day: String
    /// Your touches, and those with no wish open.
    public var touches = 0, touchesNoWish = 0
    /// Wishes made, met and given up, and how long those ended waited.
    public var wishesMade = 0, wishesMet = 0, wishesGaveUp = 0, wishWaitMs: Int64 = 0
    /// Threads opened from the board.
    public var threadsOpened = 0
    /// Requests shown, those you answered, and how long those took.
    public var needsYou = 0, answered = 0, answerMs: Int64 = 0
    /// Moments that said something, and your time at the Mac, for spoken per hour.
    public var spoken = 0, hereMinutes = 0
    public var hushes = 0, faceDown = 0
    /// The board's link dropping, and the minutes it stayed down that Boop
    /// saw: at least this many, as nothing is logged while it isn't running.
    public var disconnects = 0, unpluggedMinutes = 0
    /// Turns and work acts that failed.
    public var failures = 0
    /// Settings and growth as they last stood that day; nil on a day only
    /// read back from the transcript.
    public var quiet: Bool?, volume: Int?, stage: Int?

    public init(day: String) { self.day = day }

    /// A field the file doesn't have takes its default, so a new field never
    /// costs the rows already kept. A new field goes here too.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        func read<T: Decodable>(_ key: CodingKeys, _ into: inout T) throws {
            if let value = try c.decodeIfPresent(T.self, forKey: key) { into = value }
        }
        try read(.touches, &touches); try read(.touchesNoWish, &touchesNoWish)
        try read(.wishesMade, &wishesMade); try read(.wishesMet, &wishesMet); try read(.wishesGaveUp, &wishesGaveUp); try read(.wishWaitMs, &wishWaitMs)
        try read(.threadsOpened, &threadsOpened); try read(.needsYou, &needsYou); try read(.answered, &answered); try read(.answerMs, &answerMs)
        try read(.spoken, &spoken); try read(.hereMinutes, &hereMinutes); try read(.hushes, &hushes); try read(.faceDown, &faceDown)
        try read(.disconnects, &disconnects); try read(.unpluggedMinutes, &unpluggedMinutes); try read(.failures, &failures)
        quiet = try c.decodeIfPresent(Bool.self, forKey: .quiet)
        volume = try c.decodeIfPresent(Int.self, forKey: .volume)
        stage = try c.decodeIfPresent(Int.self, forKey: .stage)
    }

    /// `rows`' last `days` in plain numbers, for a person to read and choose
    /// to send: a total for the week, then a row a day. Numbers and dates
    /// only, whatever the transcript held.
    public static func summary(_ rows: [DayCounts], days: Int = 7) -> String {
        let week = Array(rows.suffix(days))
        func sum<T: Numeric>(_ key: KeyPath<DayCounts, T>) -> T { week.reduce(0) { $0 + $1[keyPath: key] } }
        func minutes(_ ms: Int64, of n: Int) -> String { n == 0 ? "-" : "\(ms / Int64(n) / 60_000) min" }
        let ended = sum(\.wishesMet) + sum(\.wishesGaveUp), hours = Double(sum(\.hereMinutes)) / 60
        var out = [
            "Boop's counts, \(week.count == 1 ? "the last day" : "the last \(week.count) days"). Numbers only: no words, threads or notes. Nothing sends this: it's yours to send or not.",
            "",
            "days touched: \(week.filter { $0.touches > 0 }.count) of \(week.count)",
            "touches: \(sum(\.touches)), \(sum(\.touchesNoWish)) with no wish open",
            "wishes: \(sum(\.wishesMade)) made, \(sum(\.wishesMet)) met, \(sum(\.wishesGaveUp)) given up, waiting \(minutes(sum(\.wishWaitMs), of: ended)) on average",
            "threads opened from the board: \(sum(\.threadsOpened))",
            "needs you: \(sum(\.needsYou)), \(sum(\.answered)) answered, in \(minutes(sum(\.answerMs), of: sum(\.answered))) on average",
            "spoken: \(hours > 0 ? String(format: "%.1f", Double(sum(\.spoken)) / hours) : "-") an hour at the Mac (\(sum(\.spoken)) in \(sum(\.hereMinutes)) min)",
            "hushes: \(sum(\.hushes)); days on Quiet: \(week.filter { $0.quiet == true }.count); volume: \(week.last?.volume.map(String.init) ?? "-")",
            "face down: \(sum(\.faceDown))",
            "unplugged: \(sum(\.unpluggedMinutes)) min, on \(week.filter { $0.unpluggedMinutes > 0 }.count) day(s); disconnects: \(sum(\.disconnects))",
            "failures: \(sum(\.failures))",
            "stage: \(week.last?.stage.map(String.init) ?? "-")",
            "",
            "day         touches  no-wish  made  met  gaveup  opened  needs  answered  spoken  here-min  hushes  facedown  unplugged  drops  failed",
        ]
        for r in week {
            func cell(_ n: Int, _ width: Int) -> String { String(repeating: " ", count: max(0, width - String(n).count)) + String(n) }
            out.append(r.day + "  " + [(r.touches, 7), (r.touchesNoWish, 7), (r.wishesMade, 4), (r.wishesMet, 3), (r.wishesGaveUp, 6), (r.threadsOpened, 6),
                                       (r.needsYou, 5), (r.answered, 8), (r.spoken, 6), (r.hereMinutes, 8), (r.hushes, 6), (r.faceDown, 8),
                                       (r.unpluggedMinutes, 9), (r.disconnects, 5), (r.failures, 6)].map { cell($0.0, $0.1) }.joined(separator: "  "))
        }
        return out.joined(separator: "\n")
    }
}

/// The day's counts, a reader of the transcript (`TranscriptReader`), so a
/// launch catches up on what it missed. Each day's row goes to the file when
/// it closes, and today's as it goes (`Memory.tick`).
public final class CountsReader: TranscriptReader {
    public let name = "counts"

    public struct State: Codable, Equatable, Sendable {
        public var row: DayCounts
        var wishOpen = false
        /// Requests showing, by session, since when.
        var needs: [String: Int64] = [:]
        var hereSince: Int64?
        var away: Int64?
        var downSince: Int64?
        /// The last event read.
        var lastAt: Int64?

        /// Your time at the Mac ends at the last event read.
        mutating func leftTheMac() {
            if let hereSince, let lastAt { row.hereMinutes += Int(max(0, lastAt - hereSince) / 60_000) }
            hereSince = nil
        }

        /// `row` with your time at the Mac and the link's down time up to
        /// the last event read.
        public var counted: DayCounts {
            var r = row
            if let lastAt {
                if let hereSince { r.hereMinutes += Int(max(0, lastAt - hereSince) / 60_000) }
                if let downSince { r.unpluggedMinutes += Int(max(0, lastAt - downSince) / 60_000) }
            }
            return r
        }
    }

    /// Where a closed day's row goes.
    let keep: (DayCounts) -> Void

    public init(keep: @escaping (DayCounts) -> Void) { self.keep = keep }

    /// A day starts counting afresh, but for what runs across 5:00.
    public func open(day: String, carry: State?) -> State {
        var s = State(row: DayCounts(day: day))
        s.wishOpen = carry?.wishOpen ?? false
        s.needs = carry?.needs ?? [:]
        s.away = carry?.away
        s.hereSince = carry?.hereSince == nil ? nil : carry?.lastAt
        s.downSince = carry?.downSince == nil ? nil : carry?.lastAt
        s.row.volume = carry?.row.volume
        s.row.stage = carry?.row.stage
        return s
    }

    public func read(_ e: Event, line: Line?, into s: inout State) -> Bool {
        let before = s
        Self.count(e, into: &s)
        let changed = s != before
        s.lastAt = e.at
        return changed
    }

    static func count(_ e: Event, into s: inout State) {
        if e.type != .presence, let last = s.lastAt, e.at - last >= MemoryReader.breakGapMs { s.leftTheMac() }
        if Yours.touch(e) {
            s.row.touches += 1
            if !s.wishOpen { s.row.touchesNoWish += 1 }
        }
        if Yours.did(e), s.hereSince == nil, s.away == nil { s.hereSince = e.at }
        if e.kind == Event.did {
            if e.action == Core.openThread, e["ok"]?.bool != false { s.row.threadsOpened += 1 }
            if e.action == MomentOutput.outputName, e["ok"]?.bool != false, case .array(let takes)? = e["takes"], !takes.isEmpty { s.row.spoken += 1 }
        }
        switch e.type {
        case .wish?:
            if e.phase == .start {
                s.row.wishesMade += 1
                s.wishOpen = true
            } else {
                s.wishOpen = false
                let how = Core.WishEnd(rawValue: e.specificType)
                if how == .met { s.row.wishesMet += 1 }
                if how == .gaveup { s.row.wishesGaveUp += 1 }
                if how == .met || how == .gaveup { s.row.wishWaitMs += e["waited_ms"]?.int ?? 0 }
            }
        case .needsYou?:
            guard let session = e.session else { break }
            if e.phase == .start {
                s.row.needsYou += 1
                s.needs[session] = e.at
            } else if let from = s.needs.removeValue(forKey: session), e["outcome"]?.string == "done" {
                s.row.answered += 1
                s.row.answerMs += max(0, e.at - from)
            }
        case .hush? where e.phase == .start: s.row.hushes += 1
        case .gesture? where e.specificType == "facedown": s.row.faceDown += 1
        case .turn? where e.phase == .end && e["outcome"]?.string == "failed": s.row.failures += 1
        case .act? where e.phase == .end && e["passed"]?.bool == false: s.row.failures += 1
        case .grew?:
            if let stage = Growth.stages.firstIndex(where: { $0.name == e.specificType }) { s.row.stage = stage + 1 }
        case .presence?:
            var away = AwayAndBack(since: s.away)
            switch away.fold(e) {
            case .away(let since)?:
                if let here = s.hereSince { s.row.hereMinutes += Int(max(0, since - here) / 60_000) }
                s.hereSince = nil
            case .back?:
                s.hereSince = e.at
            case nil:
                break
            }
            s.away = away.since
        case .link?:
            if e.phase == .end {
                s.row.disconnects += 1
                if s.downSince == nil { s.downSince = e.at }
            } else if let down = s.downSince {
                // Up again: only the time Boop saw. A gap with no event
                // may be Boop not running, which says nothing of the board.
                s.row.unpluggedMinutes += Int(max(0, (s.lastAt ?? down) - down) / 60_000)
                s.downSince = nil
            }
        default:
            break
        }
    }

    public func close(day: String, state: State, live: Bool) { keep(state.counted) }
}
