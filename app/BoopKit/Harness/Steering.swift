import Foundation
import MellowHarness

/// Boop's steering: MellowHarness's
/// folder of Markdown files, a copy of
/// `characters/boop/steering/`: `guide.md`, which opens the state with no heading,
/// `personality/*.md` and `mood/*.md`. A personality's front matter goes
/// to the core, not to Jev.
extension Steering {
    public struct PersonalityFile: Equatable, Sendable {
        public var rules: Personality.Rules
        /// The PERSONALITY section.
        public var text: String
    }

    /// Reads a steering folder, and throws if the guide or any personality
    /// its character pack has is missing (the active pack's, unless another
    /// is given). A mood's file is optional: a mood without one reads as
    /// the resting mood's (`mood(_:)`). v3 also needs `guide-v3` and, for a
    /// pack with `moods_v2` (Boop's), a `mood-v3/` file for each of those.
    public init(directory: URL, version: MoodGraph.Version = .v2, pack: CharacterPack = .active) throws {
        try self.init(folder: directory)
        let needed = ["guide"] + (version == .v3 ? ["guide-v3"] : []) + pack.personalities.map { "personality/\($0)" }
        let overrides = version == .v3 && !pack.moodsV2.isEmpty ? pack.moodsV2.map { "mood-v3/\($0.id)" } : []
        for path in needed + overrides where files[path] == nil {
            throw SteeringError("\(path).md is missing from \(directory.path)")
        }
    }

    /// The guide, which opens the state with no heading.
    public var guide: String { self["guide"] }
    public func guide(for version: MoodGraph.Version) -> String { version == .v3 ? self["guide-v3"] : guide }

    public func personality(_ p: Personality) -> PersonalityFile {
        let path = "personality/\(p.rawValue)"
        return PersonalityFile(rules: Personality.Rules(frontMatter: frontMatter[path] ?? ""), text: self[path])
    }

    /// The MOOD section for a mood, or the resting mood's for one Boop doesn't know.
    public func mood(_ name: String, version: MoodGraph.Version = .v2) -> String {
        if version == .v3, let override = files["mood-v3/\(name)"] { return override }
        return files["mood/\(name)"] ?? self["mood/\(MoodAction.initial)"]
    }

    /// Budgets in tokens.
    public enum Budget {
        public static let guide = 300
        public static let personality = 750
        public static let mood = 175
    }

    /// About four bytes a token, which overestimates for English prose.
    public static func tokens(_ text: String) -> Int { (text.utf8.count + 3) / 4 }

    /// Parts over their budget, as `part: N > budget`; empty when all fit.
    public func overBudget(version: MoodGraph.Version = .v2) -> [String] {
        var parts = [("guide", Steering.tokens(guide(for: version)), Budget.guide)]
        for p in Personality.allCases {
            parts.append(("personality/\(p.rawValue)", Steering.tokens(personality(p).text), Budget.personality))
        }
        for name in MoodAction.catalog(version).map(\.name).sorted() {
            parts.append(("mood/\(name)", Steering.tokens(mood(name, version: version)), Budget.mood))
        }
        return parts.filter { $0.1 > $0.2 }.map { "\($0.0): \($0.1) > \($0.2)" }
    }
}
