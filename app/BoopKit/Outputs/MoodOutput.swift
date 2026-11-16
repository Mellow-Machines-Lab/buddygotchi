import Foundation
import MellowHarness

/// Boop's mood: MellowHarness's `Choice`, its value the latest change in the log. MOOD in
/// Jev's state is the mood's file from the next pass, and the device gets
/// its face in the next `state` (the runtime's rule on the change). Jev may
/// keep the mood or move it to any other lasting mood of the pack: which
/// fits NOW is the steering's to say. Two things are code's, never Jev's:
/// a mood fading once it has lasted its minutes (`fade`), and how cross a
/// levelled mood is (`level`).
public enum MoodOutput {
    public static let outputName = "mood"

    /// How long Boop has been in its mood, for the line that closes HISTORY:
    /// `Boop has been proud for 7 min.`. Nil while in the resting mood, and
    /// before any change in the log. `name` is whose mood it is.
    public static func sinceLine(_ mood: Choice, _ log: LogView, at now: Int64, name: String = CharacterPack.active.name) -> String? {
        let current = value(mood, log)
        guard current != mood.start, let at = entered(mood, log)?.at else { return nil }
        let ms = now - at
        let span = ms < 60_000 ? "under a minute" : ms < 60 * 60_000 ? "\(ms / 60_000) min" : "\(ms / 3_600_000) h"
        return "\(name) has been \(current) for \(span)."
    }

    /// The change that brought the mood it has: its latest from another
    /// mood, a level's steps aside.
    static func entered(_ mood: Choice, _ log: LogView) -> Event? {
        log.lastDid(mood.name) {
            $0["ok"]?.bool == true && $0["to"]?.string != nil && $0["voice"]?.string == mood.voice && $0["from"]?.string != $0["to"]?.string
        }
    }

    /// Why the mood is what it is, for the person: its latest change's
    /// cause, from the event that change answered (`for`) and that event's
    /// line, `line`. `Narration.mood` makes the sentence ("Boop is lonely. You
    /// came back after 26 hours away."). A fade says so. Nil before any
    /// change, for a change nothing caused (the dashboard's), or once that
    /// event has left the log.
    public static func reason(_ mood: Choice, _ log: LogView, line: (Int) -> Line?) -> Narration? {
        guard let latest = mood.latest(log) else { return nil }
        if latest[fadeFact]?.bool == true { return Narration(cause: "It settled by itself after a while.") }
        guard let seq = latest.about ?? entered(mood, log)?.about, let cause = log.event(seq) else { return nil }
        return Narration.of(cause, line: line(seq))
    }

    /// The board's caption when the pass answering `now` really moved the
    /// mood: nil for no move, or a move this pass didn't make (a fade, a
    /// level's step).
    public static func boardFact(_ mood: Choice, _ log: LogView, now: Event?, pack: CharacterPack) -> String? {
        guard let now, let latest = mood.latest(log), latest.about == now.seq, latest["level"] == nil,
              let to = latest["to"]?.string, let settled = pack.settled(to) else { return nil }
        return Narration.moodMoved(pack.restingFace(settled), name: pack.name)
    }

    /// Each lasting mood and its meaning, the `mood` question's criterion,
    /// in the pack's order, from the character pack's `lasting`
    /// (characters/CHARACTER.md §5). Each also has a file in the
    /// steering's mood/.
    public static var moods: [Option] { CharacterPack.active.options }

    /// The resting mood, the pack's `default_mood`: a new state directory
    /// starts in it, a saved word Boop doesn't know reads as it, and every
    /// mood fades toward it.
    public static var initial: String { CharacterPack.active.defaultMood }

    /// Staying in `mood`: when NOW is no reason MOOD gives to leave it.
    static func stay(_ mood: String) -> Option {
        Option(mood, "Stay \(mood): NOW is no reason MOOD gives to leave it, whatever face it gets. No change is fine.")
    }

    /// The mood that's offered only when `mayMiss` says so: missing you is
    /// rare, and never for a quiet spell.
    public static let missing = "lonely"

    /// The `mood` question's options for `mood`: stay, then every other
    /// lasting mood with its meaning, `missing` only when `mayMiss`.
    public static func options(from mood: String, in pack: CharacterPack = .active, mayMiss: Bool = true) -> [Option] {
        [stay(mood)] + pack.options.filter { $0.name != mood && (mayMiss || $0.name != missing) }
    }

    /// Whether Boop may start to miss you at `now`, with no agent
    /// `working` for you: an idle check-in once its wish has waited
    /// `missAfterWishMs` (`wishWaitedMs`), or your coming back after
    /// `missAwayMs` (its line's `away_ms`). A forced pass (no `now`)
    /// never offers it: the dashboard and a demo set a mood itself
    /// (`change`).
    public static func mayMiss(_ now: Event?, facts: [String: JSONValue]?, working: Bool, wishWaitedMs: Int64?) -> Bool {
        guard let now, !working else { return false }
        if MomentOutput.isCheckIn(now) { return (wishWaitedMs ?? 0) >= missAfterWishMs }
        if now.type == .presence, now.phase == .end, case .int(let ms)? = facts?["away_ms"] { return missAwayMs.contains(ms) }
        return false
    }

    public static let missAfterWishMs: Int64 = 60 * 60_000
    public static let missAwayMs: ClosedRange<Int64> = (20 * 3_600_000)...(40 * 3_600_000)

    /// Boop's mood as MellowHarness's `Choice`: its question, offered stay
    /// and every other lasting mood (`options(from:)`), and the line a
    /// change shows, in `pack`. `mayMiss` is whether `missing` is offered,
    /// from the event answered and the log.
    public static func choice(pack: CharacterPack = .active, mayMiss: @escaping (Event?, LogView) -> Bool = { _, _ in true }) -> Choice {
        Choice(name: outputName, start: pack.defaultMood, question: "After NOW, what is \(pack.name)'s mood?",
                      about: "the NOW and HISTORY sections", judgeBy: "the MOOD section, its reason to leave",
                      said: { from, to in "\(pack.name)'s mood changed: \(from) → \(to)." },
                      options: { current, now, log in
                          options(from: pack.settled(current) ?? pack.defaultMood, in: pack, mayMiss: mayMiss(now, log))
                      })
    }

    /// The mood as the log has it: the choice's value, a face's name
    /// (a log from before the lasting moods were these) read as the one it
    /// settles into, and anything else as its resting mood (the choice's
    /// start).
    public static func value(_ mood: Choice, _ log: LogView, pack: CharacterPack = .active) -> String {
        pack.settled(mood.value(log)) ?? mood.start
    }

    /// Changes the mood now to any of the moods, with a result for the
    /// current mood or one that isn't a mood: the dashboard sets one
    /// through here. A face's name sets the mood it settles into.
    public static func change(_ mood: Choice, to asked: String, log: LogView) -> OutputResult {
        guard let to = CharacterPack.active.settled(asked) else { return .failed("\(asked) isn't a mood") }
        let from = value(mood, log)
        guard to != from else { return .failed("already \(to)") }
        return mood.set(to, log: log) ?? .failed("already \(to)")
    }

    // MARK: The level, which code counts

    /// How far a levelled mood has gone, from 1: its latest change's
    /// `level`, which only a rule writes (`levelled`). 1 for any other mood.
    public static func level(_ mood: Choice, _ log: LogView) -> Int {
        mood.latest(log)?["level"]?.int.map(Int.init) ?? 1
    }

    /// The face the mood rests in now: what the board and the popover show
    /// between Moments. A levelled mood's is its level's.
    public static func face(_ mood: Choice, _ log: LogView, pack: CharacterPack = .active) -> String {
        pack.restingFace(value(mood, log, pack: pack), level: level(mood, log))
    }

    /// The line MOOD ends with for a levelled mood, so Jev knows the face
    /// it rests in without ever picking the level.
    public static func levelLine(_ mood: Choice, _ log: LogView, pack: CharacterPack) -> String? {
        let id = value(mood, log, pack: pack)
        guard let l = pack.lasting(id), l.levelled else { return nil }
        let level = min(l.faces.count, level(mood, log))
        return "Right now \(pack.name) is \(l.face(level: level)): \(id), level \(level) of \(l.faces.count). The app counts the level."
    }

    /// How much an event provokes a levelled mood, from the facts of its
    /// line, or nil when it doesn't: pokes in a row (the second is 1, the
    /// third 2…), shakes in a row (the first is 1), a check failing in a
    /// row (the first is 1), and a turn that failed (1).
    public static func provocation(_ e: Event, facts: [String: JSONValue]) -> Int? {
        let inARow = facts["in_a_row"]?.int.map(Int.init) ?? 1
        if e.type == .poke { return inARow >= 2 ? inARow - 1 : nil }
        if e.type == .gesture, e.specificType == TranscriptView.shake { return inARow }
        if facts["result"]?.string == "failed", let topic = facts["topic"]?.string, TranscriptView.checks.contains(topic) {
            return (facts["failed_before"]?.int.map(Int.init) ?? 0) + 1
        }
        if e.type == .turn, e.phase == .end, facts["outcome"]?.string == "failed" { return 1 }
        return nil
    }

    /// The level a levelled mood has after being provoked by `count`
    /// (`provocation`) at `level`: on entering it (`level` nil), the count
    /// itself; in it, a level up, or the count if that's more. Never past
    /// its last face.
    public static func provoked(_ level: Int?, by count: Int, of levels: Int) -> Int {
        max(1, min(levels, level.map { max($0 + 1, count) } ?? count))
    }

    /// The level a levelled mood has after a gentle touch (`Touch.soothes`)
    /// at `level`: one down, never below its first, which only Jev or a
    /// fade leaves.
    public static func soothed(_ level: Int) -> Int { max(1, level - 1) }

    /// The rule's change of a levelled mood's level to `to`: nil for a mood
    /// with no levels, or one already there. The mood stays; its resting
    /// face changes.
    public static func levelled(_ mood: Choice, to: Int, log: LogView, pack: CharacterPack, fade: Bool = false) -> OutputResult? {
        let id = value(mood, log, pack: pack)
        guard let l = pack.lasting(id), l.levelled else { return nil }
        let from = min(l.faces.count, level(mood, log)), to = max(1, min(l.faces.count, to))
        guard to != from else { return nil }
        var facts: [String: JSONValue] = ["from": .string(id), "to": .string(id), "level": .int(Int64(to))]
        if fade { facts[fadeFact] = true }
        return .done("\(pack.name) is \(to > from ? "more" : "less") \(id): \(l.face(level: to)) now.", facts: facts)
    }

    // MARK: The fade, which code runs

    /// A fade's change says so, in its facts.
    public static let fadeFact = "fade"

    /// What the mood's fade does at `now`, if it's due: once the mood has
    /// lasted its pack's `fade.minutes` since its latest change, or since
    /// what holds its fade was last so (`heldAt`, for the mood's own
    /// `holds`), a levelled mood goes a level down, and any mood at its
    /// first level goes to the fade's `to`, the resting mood for none. Nil
    /// while it isn't due, and for a mood that doesn't fade.
    public static func fade(_ mood: Choice, _ log: LogView, at now: Int64, pack: CharacterPack,
                            heldAt: (CharacterPack.Fade.Hold) -> Int64?) -> OutputResult? {
        let id = value(mood, log, pack: pack)
        guard let l = pack.lasting(id), let fade = l.fade, let latest = mood.latest(log) else { return nil }
        let since = max(latest.at, fade.holds.flatMap(heldAt) ?? 0)
        guard now - since >= Int64(fade.minutes) * 60_000 else { return nil }
        let level = level(mood, log)
        if l.levelled, level > 1 { return levelled(mood, to: level - 1, log: log, pack: pack, fade: true) }
        let to = fade.to ?? pack.defaultMood
        return .done("\(pack.name)'s mood settled: \(id) → \(to).", facts: ["from": .string(id), "to": .string(to), fadeFact: true])
    }
}
