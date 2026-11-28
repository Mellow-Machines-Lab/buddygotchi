import Foundation

/// The mood map as rules: for each lasting mood, which cues move it, and to
/// which mood. It is transcribed from the pack's mood files
/// (`steering/mood/`), which stay the one place a character's moods are
/// written: each row is a move a file names, and an event no row names
/// leaves the mood where it is. How long a mood lasts and how cross it is
/// stay code's (`MoodOutput.fade`, `MoodOutput.level`); `lonely` keeps its
/// guard (`MoodOutput.mayMiss`), since it's offered only when it may begin.
/// `MoodMapTests` pins every row.
public enum MoodMap {
    /// What happened, as the mood files name it.
    public enum Cue: String, CaseIterable, Sendable {
        /// Kind words to Boop; praise or love; cheering it up.
        case kindWords = "kind words"
        /// The person saying sorry to Boop, or taking back what they said.
        case sorry
        /// The person thanking the agent.
        case thanks
        /// Rude words to Boop.
        case rudeWords = "rude words"
        /// The person sharing sad news.
        case sadNews = "sad news"
        /// Boop told to hush.
        case hush
        /// A stroke (or another soothing touch).
        case stroke
        /// A stroke while cross is only at its first level, annoyed: it ends
        /// cross. At grumpy or angry a stroke only softens it a level, which
        /// is code's (`MoodOutput.soothed`). `move` adds it from the level.
        case strokeWhileAnnoyed = "a stroke while annoyed"
        /// Any other touch or word to Boop: what ends lonely.
        case touched
        /// Two pokes in a row; three or more.
        case twoPokes = "2 pokes in a row", threePokes = "3+ pokes in a row"
        /// A check failing (while the agent works on).
        case checkFailed = "a failed check"
        /// A check passing after it failed.
        case checkFixed = "a check passing after it failed"
        /// A turn short of very long finishing failed.
        case turnFailed = "a failed turn short of very long"
        /// A very long turn failing.
        case veryLongFailed = "a very long turn failing"
        /// The agent giving up.
        case gaveUp = "the agent giving up"
        /// A long turn's hard work done.
        case longDone = "a long turn's hard work done"
        /// A very long turn finishing done.
        case veryLongDone = "a very long turn finishing done"
        /// Any turn finishing done.
        case turnDone = "a turn finishing done"
        /// A long turn working on.
        case longWorking = "a long turn working on"
        /// The person sounding frustrated.
        case frustrated = "the person sounding frustrated"
        /// You back from away.
        case back = "you back from away"
        /// You back after 20 to 40 hours away.
        case backAfterADay = "you back after 20 to 40 hours"
        /// An agent starting work for you.
        case agentStarts = "an agent starting work"
    }

    /// One move: in `from`, `cue` moves the mood `to`.
    public struct Move: Equatable, Sendable {
        public var from: String, cue: Cue, to: String
    }

    /// Every move the mood files name, mood by mood, in their order. When
    /// several cues hold at once, the first move listed for the mood wins
    /// (`move(from:cues:)`), so the stronger reason comes first.
    public static let moves: [Move] = {
        func row(_ from: String, _ pairs: [(Cue, String)]) -> [Move] { pairs.map { Move(from: from, cue: $0.0, to: $0.1) } }
        return row("calm", [
            (.backAfterADay, "lonely"),
            (.veryLongFailed, "sad"), (.gaveUp, "sad"), (.sadNews, "sad"), (.rudeWords, "sad"),
            (.checkFixed, "proud"),
            (.kindWords, "happy"), (.longDone, "happy"), (.veryLongDone, "happy"), (.thanks, "happy"), (.back, "happy"),
            (.checkFailed, "cross"), (.turnFailed, "cross"), (.twoPokes, "cross"), (.threePokes, "cross"), (.hush, "cross"),
            (.frustrated, "focused"), (.longWorking, "focused"),
        ])
        + row("happy", [
            (.veryLongFailed, "sad"), (.gaveUp, "sad"), (.sadNews, "sad"), (.rudeWords, "sad"),
            (.checkFixed, "proud"), (.longDone, "proud"), (.veryLongDone, "proud"),
            (.checkFailed, "cross"), (.turnFailed, "cross"), (.twoPokes, "cross"), (.threePokes, "cross"),
            (.frustrated, "focused"), (.longWorking, "focused"),
        ])
        + row("focused", [
            (.veryLongFailed, "sad"), (.gaveUp, "sad"), (.sadNews, "sad"),
            (.checkFixed, "proud"), (.longDone, "proud"),
            (.veryLongDone, "happy"), (.kindWords, "happy"), (.thanks, "happy"),
            (.turnFailed, "cross"), (.twoPokes, "cross"), (.threePokes, "cross"),
        ])
        + row("proud", [
            (.veryLongFailed, "sad"), (.sadNews, "sad"), (.rudeWords, "sad"),
            (.turnFailed, "cross"), (.twoPokes, "cross"), (.threePokes, "cross"),
            (.frustrated, "focused"),
        ])
        + row("cross", [
            (.sorry, "calm"), (.thanks, "calm"), (.strokeWhileAnnoyed, "calm"),
            (.gaveUp, "sad"), (.veryLongFailed, "sad"), (.sadNews, "sad"), (.rudeWords, "sad"),
            (.checkFixed, "calm"), (.turnDone, "calm"),
            (.checkFailed, "focused"), (.frustrated, "focused"),
        ])
        + row("sad", [
            (.sorry, "happy"), (.kindWords, "happy"), (.thanks, "happy"),
            (.stroke, "calm"), (.checkFixed, "calm"),
            (.threePokes, "cross"),
        ])
        + row("lonely", [
            (.veryLongFailed, "sad"), (.gaveUp, "sad"),
            (.kindWords, "happy"),
            (.stroke, "calm"), (.touched, "calm"), (.agentStarts, "calm"),
        ])
    }()

    /// The mood `cues` move `from` to, by the first move listed for it
    /// whose cue holds, or nil to stay. `level` is cross's level now: a
    /// stroke ends cross only while it's at its first.
    public static func move(from: String, cues: Set<Cue>, level: Int = 1) -> String? {
        moves(from: from, cues: cues, level: level).first
    }

    /// Every mood `cues` may move `from` to, in the order the map lists
    /// them: the first a pass may offer wins (`lonely` is offered only when
    /// it may begin).
    public static func moves(from: String, cues: Set<Cue>, level: Int = 1) -> [String] {
        var held = cues
        if from == "cross", level == 1, cues.contains(.stroke) { held.insert(.strokeWhileAnnoyed) }
        return moves.filter { $0.from == from && held.contains($0.cue) }.map(\.to).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}
