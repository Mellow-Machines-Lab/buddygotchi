import Foundation
import MellowHarness

/// Boop's mood: MellowHarness's `Choice`, its value the latest change in the log. MOOD in
/// Jev's state is the mood's file from the next pass, and the device gets
/// it in the next `state` (the runtime's rule on the change). Jev can only
/// keep the mood or move it one step along the mood graph (`MoodGraph`):
/// those are all it's offered. How long a mood lasts, and which move fits
/// NOW, is the steering's to say under v2; v3 first gates options in MoodPolicy.
public enum MoodAction {
    public static let actionName = "mood"

    /// How long Boop has been in its mood, for the line that closes HISTORY:
    /// `Boop has been proud for 7 min.`, so
    /// the mood files' minutes need no sums. Nil while calm, the resting
    /// mood every other fades toward, and before any change in the log.
    public static func sinceLine(_ mood: Choice, _ log: LogView, at now: Int64, version: MoodGraph.Version = .v2) -> String? {
        let current = value(mood, log, version: version)
        guard current != initial, let latest = mood.latest(log) else { return nil }
        let at = latest.at
        let ms = now - at
        let span = ms < 60_000 ? "under a minute" : ms < 60 * 60_000 ? "\(ms / 60_000) min" : "\(ms / 3_600_000) h"
        return "\(CharacterPack.active.name) has been \(current) for \(span)."
    }

    /// Each of v2's moods and its meaning, the `mood` question's criterion,
    /// in the device's order (`MoodGraph.moods`), from the character pack's
    /// `moods_v2` (characters/CHARACTER.md §5). Each also has a file in
    /// the steering's mood/, and a set of faces on the device.
    public static var moods: [Option] { CharacterPack.active.v2Options }

    /// The resting mood, the pack's `default_mood`: a new state directory
    /// starts in it, a saved word Boop doesn't know reads as it, and every
    /// mood fades toward it.
    public static var initial: String { CharacterPack.active.defaultMood }

    /// A dramatic move's "not for": it's a jump
    /// only a fresh, big event earns.
    public static let jump = "A check failing or passing, routine work, or a fade: this jump needs a fresh, big event in NOW, such as a turn that finished failed, the agent giving up, a barrage of pokes, a long turn finishing, thanks, rude words or sad news."

    /// The `mood` question's options for `mood`: stay, then each of its
    /// neighbours with its meaning, the dramatic ones also saying they're a
    /// jump. Nothing else: Jev never sees a move the graph doesn't have.
    public static func catalog(_ version: MoodGraph.Version) -> [Option] {
        version == .v2 ? moods : CharacterPack.active.v3Options
    }

    public static func options(from mood: String, version: MoodGraph.Version = .v2,
                               allowed: MoodGraph.Moves? = nil) -> [Option] {
        let moods = catalog(version)
        let meaning = { (name: String) in moods.first { $0.name == name }! }
        let graph = MoodGraph.moves(for: version)
        let moves = allowed ?? graph[mood] ?? graph[initial]!
        return [Option(mood, "Stay \(mood): NOW is no reason MOOD gives to leave it, nor are its minutes up. No change is fine.")]
            + moves.ordinary.map(meaning)
            + moves.dramatic.map(meaning).map { o in
                Option(o.name, o.what, notFor: [o.notFor, jump].compactMap { $0 }.joined(separator: " "))
            }
    }

    /// Boop's mood as MellowHarness's `Choice`: its question, offered stay and
    /// the mood graph's moves from the mood it has (`options(from:)`), and
    /// the line a change shows.
    public static func choice(version: MoodGraph.Version = .v2) -> Choice {
        Choice(name: actionName, start: initial, question: "After NOW, what is \(CharacterPack.active.name)'s mood?",
               about: "the NOW and HISTORY sections", judgeBy: "the MOOD section, its reason to leave",
               said: { from, to in "\(CharacterPack.active.name)'s mood changed: \(from) → \(to)." },
               options: { current, event, log in
                   let current = known(current, version: version)
                   return options(from: current, version: version, allowed: version == .v3
                       ? MoodPolicy.destinations(from: current, event: event, log: log) : nil)
               })
    }

    /// The mood as the log has it: the choice's value, read as the resting
    /// mood if it isn't one of the moods.
    public static func value(_ mood: Choice, _ log: LogView, version: MoodGraph.Version = .v2) -> String { known(mood.value(log), version: version) }

    static func known(_ word: String, version: MoodGraph.Version = .v2) -> String { catalog(version).contains { $0.name == word } ? word : initial }

    /// Changes the mood now to any of the moods, off the graph, with a
    /// result for the current mood or one that isn't a mood: the dashboard
    /// sets one through here.
    public static func change(_ mood: Choice, to: String, log: LogView, version: MoodGraph.Version = .v2) -> ActionResult {
        guard catalog(version).contains(where: { $0.name == to }) else { return .failed("\(to) isn't a mood") }
        let from = value(mood, log, version: version)
        guard to != from else { return .failed("already \(to)") }
        return mood.set(to, log: log) ?? .failed("already \(to)")
    }
}
