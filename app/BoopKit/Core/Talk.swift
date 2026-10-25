import Foundation

/// How much the character says, chosen in Settings: quiet, normal or
/// chatty, each the pack's `steering/talk/<level>.md`, a TALK section
/// after MOOD that outranks what PERSONALITY and MOOD say of words
/// (characters/CHARACTER.md §7), whose front matter may also set the
/// check-ins' pace. It steers the brain, and on Quiet `ReactOutput` holds
/// to it in code: `say` offers no topic and no swear, and a small moment or
/// a finish says nothing. Nothing in code holds a reaction back.
public enum Talk: String, CaseIterable, Codable, Sendable {
    case quiet, normal, chatty

    public static let `default` = Talk.normal

    /// Its name in Settings.
    public var title: String { rawValue.capitalized }

    /// What it does, in one line, for Settings.
    public func about(_ name: String) -> String {
        switch self {
        case .quiet: "\(name) shows what stands out on its face, and says a little only when something big happens."
        case .normal: "\(name) reacts to what stands out, mostly with a sound or a word."
        case .chatty: "\(name) says more, and checks in more often while agents work."
        }
    }
}
