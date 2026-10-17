import Foundation
import MellowHarness

/// Boop's mood: MellowHarness's `Choice`, its value the latest change in the log. MOOD in
/// Jev's state is the mood's file from the next pass, and the device gets
/// it in the next `state` (the runtime's rule on the change). Jev can only
/// keep the mood or move it one step along the mood graph (`MoodGraph`):
/// those are all it's offered. Which offered move fits NOW, and how soon,
/// is the steering's to say.
public enum MoodOutput {
    public static let outputName = "mood"

    /// How long Boop has been in its mood, for the line that closes HISTORY:
    /// `Boop has been proud for 7 min.`, so
    /// the mood files' minutes need no sums. Nil while calm, the resting
    /// mood every other fades toward, and before any change in the log.
    /// `name` is whose mood it is.
    public static func sinceLine(_ mood: Choice, _ log: LogView, at now: Int64, name: String = CharacterPack.active.name) -> String? {
        let current = value(mood, log)
        guard current != mood.start, let latest = mood.latest(log) else { return nil }
        let at = latest.at
        let ms = now - at
        let span = ms < 60_000 ? "under a minute" : ms < 60 * 60_000 ? "\(ms / 60_000) min" : "\(ms / 3_600_000) h"
        return "\(name) has been \(current) for \(span)."
    }

    /// Each mood and its meaning, the `mood` question's criterion, in the
    /// pack's order (`MoodGraph.moods`), from the character pack's `moods`
    /// (characters/CHARACTER.md §5). Each also has a file in the steering's
    /// mood/, and a set of faces on the device.
    public static var moods: [Option] { CharacterPack.active.options }

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
    public static func options(from mood: String, in pack: CharacterPack = .active) -> [Option] {
        let moods = pack.options
        let meaning = { (name: String) in moods.first { $0.name == name }! }
        let moves = MoodGraph.mood(mood, in: pack)?.moves ?? MoodGraph.mood(pack.defaultMood, in: pack)!.moves
        return [Option(mood, "Stay \(mood): NOW is no reason MOOD gives to leave it, nor are its minutes up. No change is fine.")]
            + moves.ordinary.map(meaning)
            + moves.dramatic.map(meaning).map { o in
                Option(o.name, o.what, notFor: [o.notFor, jump].compactMap { $0 }.joined(separator: " "))
            }
    }

    /// Boop's mood as MellowHarness's `Choice`: its question, offered stay and
    /// every move from the mood it has (`options(from:)`), and the line a
    /// change shows. With a `voice`, it's that buddy's, in its `pack`.
    public static func choice(voice: String? = nil, pack: CharacterPack = .active) -> Choice {
        Choice(name: outputName, start: pack.defaultMood, voice: voice, question: "After NOW, what is \(pack.name)'s mood?",
                      about: "the NOW and HISTORY sections", judgeBy: "the MOOD section, its reason to leave",
                      said: { from, to in "\(pack.name)'s mood changed: \(from) → \(to)." },
                      options: { current, _, _ in options(from: MoodGraph.mood(current) != nil ? current : pack.defaultMood, in: pack) })
    }

    /// The mood as the log has it: the choice's value, read as its resting
    /// mood (the choice's start) if it isn't one of the moods.
    public static func value(_ mood: Choice, _ log: LogView) -> String {
        let word = mood.value(log)
        return MoodGraph.mood(word) != nil ? word : mood.start
    }

    /// Changes the mood now to any of the moods, off the graph, with a
    /// result for the current mood or one that isn't a mood: the dashboard
    /// sets one through here.
    public static func change(_ mood: Choice, to: String, log: LogView) -> OutputResult {
        guard MoodGraph.mood(to) != nil else { return .failed("\(to) isn't a mood") }
        let from = value(mood, log)
        guard to != from else { return .failed("already \(to)") }
        return mood.set(to, log: log) ?? .failed("already \(to)")
    }
}
