import Foundation
import MellowHarness

/// What counts as you: an event is yours only if you did it. The hourly
/// check-in fires all day on a Mac left awake, and agents log events
/// overnight, so reading those as you would make an empty room look
/// lived in. The view's company and the memory both ask here.
public enum Yours {
    /// Whether `e` is the person's own doing: a poke, a care gesture, what
    /// they said to the buddy, a prompt to an agent, or coming back to the
    /// Mac, or answering an ask.
    public static func did(_ e: Event) -> Bool {
        switch e.type {
        case .said?, .prompt?: return true
        case .poke?, .gesture?: return Touch(e)?.isCare == true
        case .presence?: return e.phase == .end
        case .ask?: return e.specificType != Asks.ignored
        default: return false
        }
    }

    /// Whether `e` is a touch on the buddy itself: a poke or a care gesture.
    public static func touch(_ e: Event) -> Bool { Touch(e)?.isCare == true }

    /// Whether `e` touched or talked to the buddy itself: a poke, a care
    /// gesture or what was said to it. A prompt is yours, but it's to an
    /// agent.
    public static func touched(_ e: Event) -> Bool {
        switch e.type {
        case .said?: return true
        case .poke?, .gesture?: return Touch(e)?.isCare == true
        case .ask?: return e.specificType != Asks.ignored
        default: return false
        }
    }
}
