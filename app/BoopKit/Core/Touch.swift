import Foundation
import MellowHarness

/// What you do to the board with a finger or a hand, which it answers at
/// once: a poke (the `poke` event) or one of the gestures (the `gesture`
/// event, by its `specific_type`, render::Gesture's names, and the app's
/// `facedown` and `dismiss`). One table for each touch: whether it's
/// care, the line the brain reads and the narration.
public enum Touch: String, CaseIterable, Sendable {
    case poke, stroke, ruffle, swipe, nose, tickle, dizzy, pickup, putdown, startle, facedown, peekaboo, dismiss

    /// The touch `e` is, or nil for an event that isn't one.
    public init?(_ e: Event) {
        switch e.type {
        case .poke?: self = .poke
        case .gesture?: self.init(rawValue: e.specificType)
        default: return nil
        }
    }

    /// Care: the person touching the buddy itself. Never BOOT's hand-off,
    /// holding the needs-you screen, the drawer's swipe, putting it down,
    /// a thump on the desk or turning it over.
    public var isCare: Bool {
        switch self {
        case .poke, .stroke, .nose, .tickle, .pickup, .ruffle, .dizzy: true
        case .swipe, .putdown, .startle, .facedown, .peekaboo, .dismiss: false
        }
    }

    /// A touch on the buddy itself, which meets a pet wish: anything you do
    /// by hand to its face, the wrong-way stroke too. Not a shake, a pick-up
    /// or turning it over, nor the drawer's swipe.
    public var meetsPetWish: Bool {
        switch self {
        case .poke, .stroke, .ruffle, .nose, .tickle: true
        case .swipe, .dizzy, .pickup, .putdown, .startle, .facedown, .peekaboo, .dismiss: false
        }
    }

    /// The brain's line for it, which the board already answered; a poke's
    /// is its own, by the run (`EventLine.poke`).
    public func line(name: String = CharacterPack.active.name) -> String? {
        switch self {
        case .poke: nil
        case .stroke: "You stroked \(name)."
        case .ruffle: "You stroked \(name) the wrong way."
        case .swipe: "You swiped \(name), a quick stroke."
        case .nose: "You booped \(name)'s nose."
        case .tickle: "You tickled \(name)."
        case .dizzy: "You shook \(name)."
        case .pickup: "You picked \(name) up."
        case .putdown: "You put \(name) down."
        case .startle: "You thumped the desk next to \(name)."
        case .facedown: "You turned \(name) face down."
        case .peekaboo: "You turned \(name) back up."
        case .dismiss: "You held a finger on \(name)'s needs-you screen, to stop it showing; the agent still waits."
        }
    }

    /// The narration's cause and the board's caption, `{name}` where the
    /// buddy's name goes (`Narration.fit`); nil for a touch that isn't the
    /// person's doing to the buddy itself, and for a poke, whose narration
    /// counts the run (`Narration.of`).
    public var narration: (cause: String, fact: String)? {
        switch self {
        case .stroke: ("You stroked it.", "you stroked {name}")
        case .ruffle: ("You stroked it the wrong way.", "you ruffled {name}")
        case .nose: ("You booped its nose.", "you booped {name}")
        case .tickle: ("You tickled it.", "you tickled {name}")
        case .dizzy: ("You shook it.", "you shook {name}")
        case .pickup: ("You picked it up.", "you picked {name} up")
        case .startle: ("You thumped the desk.", "a thump nearby")
        case .facedown: ("You turned it face down.", "you turned {name} over")
        case .peekaboo: ("You turned it back up.", "you flipped {name} up")
        case .poke, .swipe, .putdown, .dismiss: nil
        }
    }
}
