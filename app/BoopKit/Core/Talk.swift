import Foundation

/// How much the character says, chosen in Settings: quiet or normal.
/// "Shh", the hush reply and the popover's button make it quiet for half
/// an hour, and then it's the setting's again (`Core.quiet`). CONTEXT's
/// Talk row (`ContextSection.talk`) tells the brain when it's quiet, which
/// outranks what PERSONALITY and MOOD say of words, and the setting has
/// its check-in pace (`pace`). On Quiet `MomentOutput` holds to it in
/// code: `say` offers no topic and no swear, a small moment or a finish
/// says nothing, and no idle beat comes but an agent waiting on you
/// (`IdleBeat`). Nothing in code holds a reaction back.
public enum Talk: String, CaseIterable, Codable, Sendable {
    case quiet, normal

    public static let `default` = Talk.normal

    /// How often it checks in, over the personality's pace, in its front
    /// matter's keys: quiet looks in less often, normal as the personality
    /// says.
    public var pace: String {
        switch self {
        case .quiet: "working_heartbeat: 480-720\nidle_heartbeat: 1800-3600"
        case .normal: ""
        }
    }

    /// Its name in Settings.
    public var title: String { rawValue.capitalized }

    /// What it does, in one line, for Settings.
    public func about(_ name: String) -> String {
        switch self {
        case .quiet: "\(name) shows what stands out on its face, and says a little only when something big happens."
        case .normal: "\(name) reacts to what stands out, mostly with a sound or a word."
        }
    }
}
