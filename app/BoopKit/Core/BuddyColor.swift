import Foundation

/// The buddy's colour (plan/xp-league.md §8): eight, picked in Settings, at
/// any level. 0 is the gel's own blue. Each is the gel's material turned in
/// hue, saturation and brightness (the gel's `bodyColor`); `hex` is the blue
/// turned the same way, for the Mac's swatches and faces. All are dark or
/// pale, away from the agents' lane inks, amber and the outcomes' colours.
public struct BuddyColor: Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    /// The swatch: the gel's blue as this colour turns it.
    public let hex: String
    /// The turn: degrees of hue, saturation and brightness (1 as made).
    public let degrees: Double, saturation: Double, brightness: Double

    public static let all: [BuddyColor] = [
        .init(id: 0, name: "Blue", hex: "#4AA8F0", degrees: 0, saturation: 1, brightness: 1),
        .init(id: 1, name: "Indigo", hex: "#6481E2", degrees: 25, saturation: 1, brightness: 0.85),
        .init(id: 2, name: "Slate", hex: "#7F95A6", degrees: 0, saturation: 0.25, brightness: 0.95),
        .init(id: 3, name: "Pearl", hex: "#BFD2E0", degrees: 0, saturation: 0.15, brightness: 1.35),
        .init(id: 4, name: "Graphite", hex: "#505559", degrees: 0, saturation: 0.1, brightness: 0.55),
        .init(id: 5, name: "Berry", hex: "#B85D82", degrees: 120, saturation: 0.8, brightness: 0.75),
        .init(id: 6, name: "Forest", hex: "#326C36", degrees: -90, saturation: 0.8, brightness: 0.6),
        .init(id: 7, name: "Ocean", hex: "#207487", degrees: -20, saturation: 1, brightness: 0.65),
    ]

    /// The colour `index`, or blue for one this Mac doesn't know.
    public static func of(_ index: Int) -> BuddyColor { all.indices.contains(index) ? all[index] : all[0] }
}
