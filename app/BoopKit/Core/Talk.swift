import Foundation

/// How much the character says, chosen in Settings: quiet, normal or
/// chatty; and a fourth level, silent for a while, which "shh", the
/// popover's Hush button and the hush reply set, and which drops back to
/// the setting when its time runs out (the hush: `Core.Hush` holds it in
/// code, saying nothing while its faces go on). CONTEXT's Talk row
/// (`ContextSection.talk`) tells the brain the level, which
/// outranks what PERSONALITY and MOOD say of words, with each level's
/// check-in pace (`pace`). It steers the brain, and on Quiet `ReactOutput` holds
/// to it in code: `say` offers no topic and no swear, and a small moment or
/// a finish says nothing. Nothing in code holds a reaction back.
public enum Talk: String, CaseIterable, Codable, Sendable {
    case quiet, normal, chatty

    public static let `default` = Talk.normal

    /// How often it checks in, over the personality's pace, in its front
    /// matter's keys: quiet looks in less often, chatty more, normal as the
    /// personality says.
    public var pace: String {
        switch self {
        case .quiet: "working_heartbeat: 480-720\nidle_heartbeat: 1800-3600"
        case .normal: ""
        case .chatty: "working_heartbeat: 120-180\nidle_heartbeat: 600-900"
        }
    }

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
