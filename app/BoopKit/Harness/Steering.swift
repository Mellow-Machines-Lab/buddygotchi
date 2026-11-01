import Foundation
import MellowHarness

/// Boop's steering: MellowHarness's
/// folder of Markdown files, a copy of
/// `characters/boop/steering/`: `guide.md`, which opens the state with no heading,
/// `personality.md` and
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
        // Its files' paths are read from where they are: through a link (a
        // pack fetched into characters/), the folder's resolved path.
        try self.init(folder: directory.resolvingSymlinksInPath())
        let needed = ["guide", "personality"]
        for path in needed where files[path] == nil {
            throw SteeringError("\(path).md is missing from \(directory.path)")
        }
    }

    /// The guide, which opens the state with no heading.
    public var guide: String { self["guide"] }

    /// The pack's one personality.
    public var personality: PersonalityFile {
        PersonalityFile(rules: Personality.Rules(frontMatter: frontMatter["personality"] ?? ""), text: self["personality"])
    }

    /// The view's rules for a personality and how much it says: the
    /// personality's front matter, with the talk setting's pace laid over
    /// it (`Talk.pace`).
    public func rules(talk: Talk) -> Personality.Rules {
        let own = frontMatter["personality"] ?? ""
        return Personality.Rules(frontMatter: own + "\n" + talk.pace)
    }

    /// The signs a dream may hold up (`dreams.md`, optional), each with the
    /// tags the day must have: none for a pack with no file, whose dreams
    /// are told with no sign.
    public var dreams: [TaggedLine] { files["dreams"].map(TaggedLine.parse) ?? [] }

    /// The questions it may ask you, and what it holds up after your
    /// answer (`asks.md`, optional): none for a pack with no file, which
    /// never asks.
    public var asks: [TaggedLine] { files["asks"].map(TaggedLine.parse) ?? [] }

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
        public static let personality = 2850
        public static let mood = 250
        /// MEMORY, the written memory as Jev reads it on every pass.
        public static let memory = 300
        /// `replies.md`, whose lines are offered as the sign for what you said.
        public static let replies = 325
        /// `dreams.md` and `asks.md`, offered as signs a few at a time.
        public static let dreams = 150
        public static let asks = 325
    }

    /// About four bytes a token, which overestimates for English prose.
    public static func tokens(_ text: String) -> Int { (text.utf8.count + 3) / 4 }

    /// Parts over their budget, as `part: N > budget`; empty when all fit.
    public func overBudget(in pack: CharacterPack = .active) -> [String] {
        var parts = [("guide", Steering.tokens(guide), Budget.guide)]
        parts.append(("personality", Steering.tokens(personality.text), Budget.personality))
        for name in pack.lasting.map(\.id).sorted() {
            parts.append(("mood/\(name)", Steering.tokens(mood(name, in: pack)), Budget.mood))
        }
        for (name, budget) in [("dreams", Budget.dreams), ("asks", Budget.asks)] {
            if let text = files[name] { parts.append((name, Steering.tokens(text), budget)) }
        }
        return parts.filter { $0.1 > $0.2 }.map { "\($0.0): \($0.1) > \($0.2)" }
    }
}
