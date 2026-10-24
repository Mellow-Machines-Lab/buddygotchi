import Foundation

/// The first launch's walkthrough, in acts: hello, what Boop does, a name
/// and a nature, the board, how to use it, the agents, a few small things,
/// and the finale. The app shows it once: until it's finished, there's no
/// menu-bar icon.
public enum Onboarding {
    public enum Act: String, CaseIterable, Codable, Sendable {
        case hello, whatIDo, makeMeYours, body, howTo, agents, smallThings, finale

        /// Its place, from 0.
        public var index: Int { Self.allCases.firstIndex(of: self)! }
        public var next: Act? { index + 1 < Self.allCases.count ? Self.allCases[index + 1] : nil }
        /// The act Back goes to, if any. Once Boop is named (makeMeYours
        /// saves its memory), the name is for keeps, so nothing goes back
        /// past the board.
        public var back: Act? {
            guard index > 0, self != .body else { return nil }
            return Self.allCases[index - 1]
        }
        /// The acts after naming, which need Boop's memory and its runtime.
        public var afterNaming: Bool { index > Act.makeMeYours.index }
    }

    /// Where a launch starts: from the top when Boop hasn't been named; at
    /// the act saved in `settings.json` (`AppSettings.onboarding`) when one
    /// is, after a quit partway; and nowhere (nil, onboarding is done) when
    /// Boop is named and none is saved, which includes every Boop named
    /// before onboarding existed. Before the name nothing is kept, so a quit
    /// there starts again.
    public static func resume(isSetUp: Bool, saved: Act?) -> Act? {
        guard isSetUp else { return .hello }
        guard let saved, saved.afterNaming else { return nil }
        return saved
    }
}
