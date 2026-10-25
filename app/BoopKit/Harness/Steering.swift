import Foundation
import MellowHarness

/// Boop's steering: MellowHarness's
/// folder of Markdown files, a copy of
/// `characters/boop/steering/`: `guide.md`, which opens the state with no heading,
/// `personality/*.md`, `nature/*.md` (optional) and `mood/*.md`. A
/// personality's front matter goes to the core, not to Jev.
extension Steering {
    public struct PersonalityFile: Equatable, Sendable {
        public var rules: Personality.Rules
        /// The PERSONALITY section.
        public var text: String
    }

    /// Reads a steering folder, and throws if the guide or any personality
    /// its character pack has is missing (the active pack's, unless another
    /// is given). A mood's file is optional: a mood without one reads as
    /// the resting mood's (`mood(_:)`).
    public init(directory: URL, pack: CharacterPack = .active) throws {
        try self.init(folder: directory)
        let needed = ["guide"] + pack.personalities.map { "personality/\($0)" }
        for path in needed where files[path] == nil {
            throw SteeringError("\(path).md is missing from \(directory.path)")
        }
    }

    /// The guide, which opens the state with no heading.
    public var guide: String { self["guide"] }

    public func personality(_ p: Personality) -> PersonalityFile {
        let path = "personality/\(p.rawValue)"
        return PersonalityFile(rules: Personality.Rules(frontMatter: frontMatter[path] ?? ""), text: self[path])
    }

    /// What the nature chosen at setup adds, right after PERSONALITY:
    /// `nature/sweet.md` or `nature/cheeky.md`, or nil for a pack with no
    /// file for it.
    public func nature(_ nature: LongTerm.Nature) -> String? { files["nature/\(nature.rawValue)"] }

    /// The diary's lines (`diary.md`, optional): none for a pack with no
    /// file, which keeps no diary.
    public var diary: [TaggedLine] { files["diary"].map(TaggedLine.parse) ?? [] }

    /// The captions a sign may show (`signs.md`, optional): none for a
    /// pack with no file, whose buddy holds up no signs.
    public var signs: [TaggedLine] { files["signs"].map(TaggedLine.parse) ?? [] }

    /// The MOOD section for a mood, or the resting mood's for one Boop
    /// doesn't know: `pack`'s, whose steering this is.
    public func mood(_ name: String, in pack: CharacterPack = .active) -> String {
        files["mood/\(name)"] ?? self["mood/\(pack.defaultMood)"]
    }

    /// Budgets in tokens.
    public enum Budget {
        public static let guide = 400
        public static let personality = 2200
        public static let nature = 250
        public static let mood = 225
    }

    /// About four bytes a token, which overestimates for English prose.
    public static func tokens(_ text: String) -> Int { (text.utf8.count + 3) / 4 }

    /// Parts over their budget, as `part: N > budget`; empty when all fit.
    public func overBudget(in pack: CharacterPack = .active) -> [String] {
        var parts = [("guide", Steering.tokens(guide), Budget.guide)]
        for p in pack.personalities.map({ Personality($0, in: pack) }) {
            parts.append(("personality/\(p.rawValue)", Steering.tokens(personality(p).text), Budget.personality))
        }
        for n in [LongTerm.Nature.sweet, .cheeky] {
            if let text = nature(n) { parts.append(("nature/\(n.rawValue)", Steering.tokens(text), Budget.nature)) }
        }
        for name in pack.moods.map(\.id).sorted() {
            parts.append(("mood/\(name)", Steering.tokens(mood(name, in: pack)), Budget.mood))
        }
        return parts.filter { $0.1 > $0.2 }.map { "\($0.0): \($0.1) > \($0.2)" }
    }
}
