import Foundation

/// How long each of the pixel face's designs takes to play once through,
/// in ms: its longest animation, leaving out the blink, which the device
/// times on its own. A moment's `loops` count these, and the device's
/// faces.h has the same numbers. And each design's voice
/// window, when a line over its animation starts, as the device's sfx.h has
/// it. They're the face's `mac/faces.json`
/// (characters/CHARACTER.md §9), which facegen writes into the Pixel
/// pack.
public enum FaceLoops {
    /// The moods the pixel designs draw, in faces.h's order.
    public static var moods: [String] { table.moods }

    /// The designs' states, in the device's order (`render::SceneState`).
    public static var states: [String] { table.states }

    /// One design: its loop length, its voice window's start (a line
    /// that comes with its animation starts no sooner), and the host fact
    /// it's for, if any: task_complete's `outcome` (success or failure),
    /// starting's `ctx` (new_task, session or continuation).
    public struct Design: Equatable, Sendable {
        public let ms: Int64
        public let voiceMs: Int64
        public let outcome: String?
        public let ctx: String?
    }

    /// By mood, each state's designs in `states`' order, one a variation:
    /// a mood and state's variations are numbered from 1.
    public static var designs: [String: [[Design]]] { table.designs }

    private struct Table: Sendable {
        var moods: [String] = []
        var states: [String] = []
        var designs: [String: [[Design]]] = [:]
    }

    /// The face's table, read the first time it's used; empty for a pack
    /// with no pixel face.
    private static let table: Table = {
        guard let data = try? Data(contentsOf: CharacterPack.active.directory.appendingPathComponent("mac/faces.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Table() }
        var t = Table()
        t.moods = json["moods"] as? [String] ?? []
        t.states = json["states"] as? [String] ?? []
        for (mood, rows) in json["designs"] as? [String: [[[String: Any]]]] ?? [:] {
            t.designs[mood] = rows.map { row in
                row.map { d in
                    Design(ms: (d["ms"] as? NSNumber)?.int64Value ?? 0, voiceMs: (d["voice_ms"] as? NSNumber)?.int64Value ?? 0,
                           outcome: d["outcome"] as? String, ctx: d["ctx"] as? String)
                }
            }
        }
        return t
    }()

    /// `mood`'s designs for `state`, as the device reads them: the first
    /// mood's (happy's) for a mood it doesn't know, idle's for a state it
    /// doesn't; one empty design for a pack with no pixel face.
    static func row(mood: String, state: String) -> [Design] {
        guard let first = moods.first, let row = designs[mood] ?? designs[first], !row.isEmpty else {
            return [Design(ms: 0, voiceMs: 0, outcome: nil, ctx: nil)]
        }
        let designs = row[states.firstIndex(of: state) ?? 0]
        return designs.isEmpty ? [Design(ms: 0, voiceMs: 0, outcome: nil, ctx: nil)] : designs
    }

    /// How many variations `mood` has for `state`.
    public static func count(mood: String, state: String) -> Int {
        row(mood: mood, state: state).count
    }

    /// The variations (from 1) of `mood`'s `state` for an outcome and a
    /// context, nil matching any; all of them when none match.
    public static func variants(mood: String, state: String, outcome: String? = nil, ctx: String? = nil) -> [Int] {
        let row = row(mood: mood, state: state)
        let fit = row.indices.filter { i in
            (outcome == nil || row[i].outcome == outcome) && (ctx == nil || row[i].ctx == ctx)
        }.map { $0 + 1 }
        return fit.isEmpty ? Array(1...row.count) : fit
    }

    /// A design's loop length: `mood`'s design for `state`, variation
    /// `variant` (from 1), the first variation for one out of range.
    public static func ms(mood: String, state: String, variant: Int = 1) -> Int64 {
        let row = row(mood: mood, state: state)
        return row[(1...row.count).contains(variant) ? variant - 1 : 0].ms
    }

    /// When a line that comes with the animation of `mood`'s design for
    /// `state`, variation `variant` (from 1), starts: its voice window, in
    /// ms from the design's start; the first variation's for one out of
    /// range.
    public static func voiceMs(mood: String, state: String, variant: Int = 1) -> Int64 {
        let row = row(mood: mood, state: state)
        return row[(1...row.count).contains(variant) ? variant - 1 : 0].voiceMs
    }
}
