import Foundation

/// Who the character is: its pack's one personality, `steering/personality.md`
/// (characters/CHARACTER.md §7). Its front matter's settings drive the
/// view's rules (`Rules`); its text is the PERSONALITY section of Jev's
/// state. How much it says is `Talk`'s.
public enum Personality {
    /// The settings a personality file's front matter sets for the core.
    public struct Rules: Equatable, Sendable {
        /// The working heartbeat's wait, in milliseconds, or none.
        public var workBeatMs: ClosedRange<Int>?
        /// The idle check-in's wait, in milliseconds, or none: only the
        /// hourly heartbeat, as before there were check-ins.
        public var idleBeatMs: ClosedRange<Int>?

        public init(workBeatMs: ClosedRange<Int>? = 90_000...180_000, idleBeatMs: ClosedRange<Int>? = nil) {
            self.workBeatMs = workBeatMs
            self.idleBeatMs = idleBeatMs
        }

        /// Reads `working_heartbeat` and `idle_heartbeat` from a
        /// front-matter block; anything missing or unreadable keeps its
        /// default.
        public init(frontMatter: String) {
            self.init()
            for line in frontMatter.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "working_heartbeat": workBeatMs = Rules.seconds(parts[1], else: workBeatMs)
                case "idle_heartbeat": idleBeatMs = Rules.seconds(parts[1], else: idleBeatMs)
                default: break
                }
            }
        }

        /// A range of seconds (`90-180`) in milliseconds, nil for `none`,
        /// or `old` for anything unreadable.
        static func seconds(_ text: String, else old: ClosedRange<Int>?) -> ClosedRange<Int>? {
            if text == "none" { return nil }
            let bounds = text.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard bounds.count == 2, bounds[0] > 0, bounds[0] <= bounds[1] else { return old }
            return bounds[0] * 1000...bounds[1] * 1000
        }
    }
}
