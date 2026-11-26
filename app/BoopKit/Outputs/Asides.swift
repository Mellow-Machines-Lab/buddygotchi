import Foundation
import MellowHarness

/// An aside: the one short sentence Boop says about what just happened,
/// with the context in it ("Yay, writing the report, done!", "Oh man, the
/// tests failed again."), in its own voice. It's the agent's offered line
/// when it gave one that fits (`MomentRule.offeredLine`), else one of the
/// pack's (`signs.md`'s `[aside …]` rows), picked here by plain rules,
/// never by the brain, and it never goes to the brain. It shows as text,
/// low; with Settings' Voice set to speak, the Mac says it aloud too
/// (`AppSettings.Voice`). The table here and nowhere else (`AsidesTests`
/// pins it).
public enum Asides {
    /// The longest an aside is: what the low sign holds, in two rows of
    /// `rowLength` at most.
    public static let maxLength = MemoryPipeline.signMax, rowLength = 26, rows = 2
    /// The longest `{what}` is: a status card's `doing` whole.
    public static let whatLength = 24
    /// The moment a failed check has its aside at before its skit plays.
    public static let oops = "oops"

    /// The moment an aside is for, by the skit playing (`Skits.play`) at
    /// `slot`, or nil for none.
    ///
    /// | The moment | When | `{what}` | `{n}` | Its tags, when true |
    /// | --- | --- | --- | --- | --- |
    /// | `win` | the `win` skit: a long turn done | the work (`work`) | failed checks on the way | `long` a very long turn, `hard` a check failed on the way; in a cross or sad mood only `glum` |
    /// | `upset` | the `upset` skit: a turn failed or gave up, or a check failing the 3rd time in a row | the work, or the check | the check's failures in a row | `check` a check, `stuck` gave up, `long` a very long turn, `swear` when the skit swears |
    /// | `fix` | the `fix` skit: a check passing after it failed | the check | its failures before | `hard` after 2 or more |
    /// | `oops` | a check failing the 1st or 2nd time in a row, no skit | the check | its failures in a row | `again` the 2nd |
    ///
    /// Of the rows whose tags are all true, those with the most tags are
    /// the pool, as replies' are (`Signs.replies`); a row that doesn't fit
    /// the low sign filled in is left out, and so is the last row said
    /// while another fits. None on Quiet. `back` has no aside.
    public static func moment(skit: Skits.Play?, slot: RulesBrain.Slot) -> String? {
        if let skit { return ["win", "upset", "fix"].contains(skit.skit.id) ? skit.skit.id : nil }
        return slot == .checkFailed || slot == .checkFailing ? oops : nil
    }

    /// What a finished turn was, in plain words, as the agent itself put
    /// it, the first there is: its last status card's `doing` this turn
    /// ("writing the report"); its result card's headline, unless it says
    /// an outcome ("nav fixed"); its last work act ("the tests"); the
    /// thread's name; or its project's.
    public static func work(doing: String?, headline: String?, act: String?, thread: String?, project: String?) -> String? {
        if let doing = plain(doing) { return doing }
        if let headline = plain(headline), !saysOutcome(headline) { return headline }
        if let act { return act == "push" ? "the push" : "the \(act)" }
        return plain(thread) ?? plain(project)
    }

    /// Whether a headline already says how it came out ("nav overflow
    /// fixed", "all green"): then "done" after it says it twice.
    static func saysOutcome(_ text: String) -> Bool {
        let last = text.lowercased().split(separator: " ").last.map(String.init) ?? ""
        return last.hasSuffix("ed") || ["done", "green", "ok", "passing", "works", "shipped", "up"].contains(last)
            || text.contains(where: \.isNumber)
    }

    /// `text` trimmed, drawable and cut to `whatLength` at a word, or nil.
    static func plain(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, let drawn = Signs.drawn(text) else { return nil }
        return WorkStream.clip(drawn, whatLength)
    }

    /// The tags true of the moment `moment` at `slot`, its event's line
    /// having `facts`, in the lasting `mood`.
    static func tags(_ moment: String, slot: RulesBrain.Slot, facts: [String: JSONValue], mood: String, swears: Bool) -> Set<String> {
        let checksFailed = facts["checks_failed"]?.int ?? 0, before = facts["failed_before"]?.int ?? 0
        var on: Set<String> = []
        switch moment {
        case "win":
            if mood == MomentRule.cross || mood == MomentRule.sad { return ["glum"] }
            if slot == .doneVeryLong { on.insert("long") }
            if checksFailed > 0 { on.insert("hard") }
        case "upset":
            if slot == .checkFailing { on.insert("check") }
            if slot == .gaveUp { on.insert("stuck") }
            if slot == .failedVeryLong { on.insert("long") }
            if swears { on.insert("swear") }
        case "fix":
            if before >= 2 { on.insert("hard") }
        case oops:
            if before == 1 { on.insert("again") }
        default: break
        }
        return on
    }

    /// `{what}` at a moment whose event's line has `facts`: a check's
    /// name ("the tests"); else the turn's `work`, a gerund's first letter
    /// small, so it sits inside a sentence; else the thread's.
    static func what(_ facts: [String: JSONValue], work: String?) -> String? {
        if let topic = facts["topic"]?.string, TranscriptView.checks.contains(topic) { return "the \(topic)" }
        guard let work = plain(work) ?? plain(facts["thread"]?.object?["name"]?.string) else { return nil }
        let first = work.split(separator: " ").first.map(String.init) ?? ""
        return first.lowercased().hasSuffix("ing") ? work.prefix(1).lowercased() + work.dropFirst() : work
    }

    /// `{n}`: a failing check's failures in a row, a fixed one's failures
    /// before, or a win's failed checks.
    static func number(_ moment: String, facts: [String: JSONValue]) -> Int? {
        let before = Int(facts["failed_before"]?.int ?? 0)
        switch moment {
        case "fix": return before > 0 ? before : nil
        case "win": return (facts["checks_failed"]?.int).map(Int.init).flatMap { $0 > 0 ? $0 : nil }
        default: return facts["failed_before"] != nil ? before + 1 : nil
        }
    }

    /// Whether `text` fits the low sign: `rows` rows of `rowLength` at most,
    /// broken at spaces, and `maxLength` in all.
    public static func fits(_ text: String) -> Bool {
        guard text.count <= maxLength else { return false }
        var rows = 0, row = 0
        for word in text.split(separator: " ") {
            if row > 0, row + 1 + word.count <= rowLength {
                row += 1 + word.count
            } else {
                guard word.count <= rowLength else { return false }
                rows += 1
                row = word.count
            }
        }
        return rows <= Self.rows
    }

    /// A row filled in: `{what}` and `{n}`, each sentence with a capital,
    /// or nil when it needs one it hasn't got, or doesn't fit.
    static func filled(_ row: String, what: String?, n: Int?) -> String? {
        if row.contains("{what}"), what == nil { return nil }
        if row.contains("{n}"), n == nil { return nil }
        let text = row.replacingOccurrences(of: "{what}", with: what ?? "").replacingOccurrences(of: "{n}", with: n.map(String.init) ?? "")
        guard let drawn = Signs.drawn(text), !drawn.isEmpty else { return nil }
        // Each sentence starts with a capital, a filled-in one too.
        var line = "", starts = true
        for ch in drawn {
            line += starts && ch.isLetter ? ch.uppercased() : String(ch)
            if ch.isLetter || ch.isNumber { starts = false } else if ".!".contains(ch) { starts = true }
        }
        return fits(line) ? line : nil
    }

    /// The pack's aside at `moment`, or nil for none: one of `rows`'
    /// `[aside <moment> …]` rows that fits, filled in, `{what}` the turn's
    /// `work` where it's a turn's, not `avoiding` (the last row said) while
    /// another fits, by `rng`. `row` is the row as written, to avoid next time.
    public static func pick(_ rows: [TaggedLine], moment: String, slot: RulesBrain.Slot, facts: [String: JSONValue], work: String? = nil,
                            mood: String, swears: Bool, quiet: Bool, avoiding: String? = nil,
                            rng: inout SplitMix64) -> (row: String, text: String)? {
        let pool = self.pool(rows, moment: moment, slot: slot, facts: facts, work: work, mood: mood, swears: swears, quiet: quiet)
        let fresh = pool.count > 1 ? pool.filter { $0.row != avoiding } : pool
        return fresh.isEmpty ? nil : fresh[rng.int(in: 0...(fresh.count - 1))]
    }

    /// Every aside `pick` may say at `moment`, filled in.
    public static func pool(_ rows: [TaggedLine], moment: String, slot: RulesBrain.Slot, facts: [String: JSONValue], work: String? = nil,
                            mood: String, swears: Bool, quiet: Bool) -> [(row: String, text: String)] {
        guard !quiet else { return [] }
        let on = tags(moment, slot: slot, facts: facts, mood: mood, swears: swears).union(["aside", moment])
        let what = what(facts, work: work), n = number(moment, facts: facts)
        let fit = rows.filter { $0.tags.count >= 2 && $0.tags[0] == "aside" && $0.tags[1] == moment && $0.fits(on) }
            .compactMap { row in filled(row.text, what: what, n: n).map { (row: row.text, tags: row.tags.count, text: $0) } }
        guard let most = fit.map(\.tags).max() else { return [] }
        return fit.filter { $0.tags == most }.map { ($0.row, $0.text) }
    }
}
