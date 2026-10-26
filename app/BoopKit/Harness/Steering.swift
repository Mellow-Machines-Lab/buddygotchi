import Foundation
import MellowHarness

/// Boop's steering: MellowHarness's
/// folder of Markdown files, a copy of
/// `characters/boop/steering/`: `guide.md`, which opens the state with no heading,
/// `personality/*.md`, `talk/*.md` (optional) and
/// `mood/*.md`. A personality's front matter, and a talk file's over it,
/// go to the core, not to Jev.
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

    /// What how much it says adds, after MOOD: `talk/quiet.md`,
    /// `talk/normal.md` or `talk/chatty.md`, or nil for a level the pack
    /// has no file for, which leaves the personality as written.
    public func talk(_ talk: Talk) -> String? { files["talk/\(talk.rawValue)"] }

    /// Whether the pack has a talk file at all: without one, Settings
    /// offers no choice.
    public var talks: Bool { Talk.allCases.contains { talk($0) != nil } }

    /// The view's rules for a personality and how much it says: the
    /// personality's front matter, with the talk file's laid over it.
    public func rules(_ p: Personality, talk: Talk) -> Personality.Rules {
        let own = frontMatter["personality/\(p.rawValue)"] ?? ""
        return Personality.Rules(frontMatter: own + "\n" + (frontMatter["talk/\(talk.rawValue)"] ?? ""))
    }

    /// The diary's lines (`diary.md`, optional): none for a pack with no
    /// file, which keeps no diary.
    public var diary: [TaggedLine] { files["diary"].map(TaggedLine.parse) ?? [] }

    /// What a reply to what you said may hold up (`replies.md`,
    /// optional): none for a pack with no file, whose replies hold up
    /// nothing but the agents' facts.
    public var replies: [TaggedLine] { files["replies"].map(TaggedLine.parse) ?? [] }

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
        public static let personality = 2600
        public static let talk = 250
        public static let mood = 225
        /// `replies.md`, whose lines are offered as the sign for what you said.
        public static let replies = 325
    }

    /// About four bytes a token, which overestimates for English prose.
    public static func tokens(_ text: String) -> Int { (text.utf8.count + 3) / 4 }

    /// Parts over their budget, as `part: N > budget`; empty when all fit.
    public func overBudget(in pack: CharacterPack = .active) -> [String] {
        var parts = [("guide", Steering.tokens(guide), Budget.guide)]
        for p in pack.personalities.map({ Personality($0, in: pack) }) {
            parts.append(("personality/\(p.rawValue)", Steering.tokens(personality(p).text), Budget.personality))
        }
        for t in Talk.allCases {
            if let text = talk(t) { parts.append(("talk/\(t.rawValue)", Steering.tokens(text), Budget.talk)) }
        }
        for name in pack.moods.map(\.id).sorted() {
            parts.append(("mood/\(name)", Steering.tokens(mood(name, in: pack)), Budget.mood))
        }
        return parts.filter { $0.1 > $0.2 }.map { "\($0.0): \($0.1) > \($0.2)" }
    }
}
