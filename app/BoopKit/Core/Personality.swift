import Foundation

/// Who the character is: one of its pack's personalities, a file in the
/// pack's `steering/personality/`, chosen in Settings
/// (characters/CHARACTER.md §4). Its settings
/// drive the view's rules; its text is the PERSONALITY section of Jev's
/// state. Boop's are `boop` and `chatter`, which reacts to everything for
/// debugging.
public struct Personality: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    /// One of the pack's personalities, or nil for a name it doesn't have.
    public init?(rawValue: String) {
        guard CharacterPack.active.personalities.contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    private init(named name: String) { rawValue = name }

    /// `name` if `pack` has it, else `pack`'s first: a buddy of another
    /// pack speaks its own personality of the same name.
    public init(_ name: String, in pack: CharacterPack) {
        rawValue = pack.personalities.contains(name) ? name : pack.personalities.first ?? "default"
    }

    /// The pack's personalities, in its order.
    public static var allCases: [Personality] { CharacterPack.active.personalities.map(Personality.init(named:)) }

    /// The pack's first personality: what a new Boop starts with, and what
    /// a saved one the pack no longer has reads as.
    public static var `default`: Personality { Personality(named: CharacterPack.active.personalities.first ?? "default") }

    /// What it does, in one line, for Settings: the pack's `about` for it.
    public var about: String? { CharacterPack.active.personalityAbout[rawValue] }

    /// The settings a personality file's front matter sets for the core.
    public struct Rules: Equatable, Sendable {
        /// Which finished tool calls the view keeps.
        public enum ToolUses: String, Sendable { case notable, all }

        /// The working heartbeat's wait, in milliseconds, or none.
        public var workBeatMs: ClosedRange<Int>?
        public var toolUses: ToolUses

        public init(workBeatMs: ClosedRange<Int>? = 90_000...180_000, toolUses: ToolUses = .notable) {
            self.workBeatMs = workBeatMs
            self.toolUses = toolUses
        }

        /// Reads `working_heartbeat` and `tool_uses` from a front-matter block;
        /// anything missing or unreadable keeps its default.
        public init(frontMatter: String) {
            self.init()
            for line in frontMatter.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "tool_uses": if let t = ToolUses(rawValue: parts[1]) { toolUses = t }
                case "working_heartbeat":
                    if parts[1] == "none" {
                        workBeatMs = nil
                    } else {
                        let bounds = parts[1].split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                        if bounds.count == 2, bounds[0] > 0, bounds[0] <= bounds[1] {
                            workBeatMs = bounds[0] * 1000...bounds[1] * 1000
                        }
                    }
                default: break
                }
            }
        }
    }
}
