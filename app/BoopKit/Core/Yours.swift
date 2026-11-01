import Foundation
import MellowHarness

/// What counts as you: an event is yours only if you did it. The hourly
/// heartbeat fires all day on a Mac left awake, and agents log events
/// overnight, so reading those as you would make an empty room look
/// lived in. The view's company and the memory both ask here.
public enum Yours {
    /// The gestures that are care, the person touching the buddy itself:
    /// never BOOT's hand-off, holding the needs-you screen, the drawer's
    /// swipe, putting it down, a thump on the desk or turning it over.
    public static let careGestures: Set<String> = ["stroke", "nose", "tickle", "pickup", "ruffle", "dizzy"]

    /// Whether `e` is the person's own doing: a poke, a care gesture, what
    /// they said to the buddy, a prompt to an agent, or coming back to the
    /// Mac, or answering an ask.
    public static func did(_ e: Event) -> Bool {
        switch e.type {
        case .poke?, .said?, .prompt?: return true
        case .gesture?: return careGestures.contains(e.specificType)
        case .presence?: return e.phase == .end
        case .ask?: return e.specificType != Asks.ignored
        default: return false
        }
    }

    /// Whether `e` is a touch on the buddy itself: a poke or a care gesture.
    public static func touch(_ e: Event) -> Bool {
        e.type == .poke || (e.type == .gesture && careGestures.contains(e.specificType))
    }

    /// Whether `e` touched or talked to the buddy itself: a poke, a care
    /// gesture or what was said to it. A prompt is yours, but it's to an
    /// agent.
    public static func touched(_ e: Event) -> Bool {
        switch e.type {
        case .poke?, .said?: return true
        case .gesture?: return careGestures.contains(e.specificType)
        case .ask?: return e.specificType != Asks.ignored
        default: return false
        }
    }
}
