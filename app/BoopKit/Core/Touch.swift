import Foundation
import MellowHarness

/// What you do to the board with a finger or a hand, which it answers at
/// once: seven touches. A poke is the `poke` event; the rest are the
/// `gesture` event, by its `specific_type`. The board finds more kinds than
/// these and plays each its own way; the Mac reads them as the seven
/// (`read`). One table for each touch: whether it's care, the line the
/// brain reads and the narration.
public enum Touch: String, CaseIterable, Sendable {
    case poke, stroke, hold, shake, pickup, swipe, facedown

    /// The touch the board's gesture `wire` is (`ev gesture`'s `did`,
    /// render::Gesture's names and the app's `lean`, `swipe` and
    /// `facedown`), and whether it's that touch ending; nil for none.
    ///
    /// | The board says | The touch |
    /// | --- | --- |
    /// | `stroke`, `ruffle` (a stroke the wrong way) | stroke |
    /// | `lean` (a finger kept still) | hold |
    /// | `nose`, `tickle` (a poke with a place) | poke |
    /// | `dizzy`, `startle` (a thump on the desk) | shake |
    /// | `pickup`; `putdown` | pick-up; its end |
    /// | `swipe` | swipe |
    /// | `facedown`; `peekaboo` | face down; its end |
    ///
    /// A touch's own name reads as itself (the evals and demos say `hold`
    /// and `shake`).
    public static func read(_ wire: String) -> (touch: Touch, ended: Bool)? {
        switch wire {
        case "ruffle": (.stroke, false)
        case "lean": (.hold, false)
        case "nose", "tickle": (.poke, false)
        case "dizzy", "startle": (.shake, false)
        case "putdown": (.pickup, true)
        case "peekaboo": (.facedown, true)
        default: Touch(rawValue: wire).map { ($0, false) }
        }
    }

    /// The touch `e` is, or nil for an event that isn't one: a touch's end
    /// (a put-down, turned back up) is none.
    public init?(_ e: Event) {
        switch e.type {
        case .poke?: self = .poke
        case .gesture? where e.phase == nil: self.init(rawValue: e.specificType)
        default: return nil
        }
    }

    /// The touch that answered an invite (an `invite` event that ended
    /// `answered` or `late`): its tap a poke, its stroke a stroke; nil for
    /// any other event. It does what that touch does, once: its care XP
    /// (`Growth.source`), a pet wish met, a stroke's soothing, you showing
    /// up and a touch in the daily counts. It's no `poke` or `gesture`
    /// event, so it plays nothing more and wakes no pass.
    public static func answering(_ e: Event) -> Touch? {
        guard e.type == .invite, Moment.Invite.End(rawValue: e.specificType)?.isYours == true else { return nil }
        return Skit.Invite.Touch(rawValue: e["touch"]?.string ?? "")?.touch
    }

    /// Care: the person touching the buddy itself. Never the drawer's
    /// swipe or turning it over.
    public var isCare: Bool {
        switch self {
        case .poke, .stroke, .hold, .pickup, .shake: true
        case .swipe, .facedown: false
        }
    }

    /// Rough handling: a shake. Still your touch, so it's company, but it
    /// earns no XP (`Growth.xp`).
    public var isRough: Bool { self == .shake }

    /// A touch on the buddy's face, which meets a pet wish. Not a shake, a
    /// pick-up or turning it over, nor the drawer's swipe.
    public var meetsPetWish: Bool { self == .poke || self == .stroke || self == .hold }

    /// A gentle touch, which takes a levelled mood a level down
    /// (`MoodOutput.soothed`): a stroke, a swipe, a finger at rest.
    public var soothes: Bool { self == .stroke || self == .swipe || self == .hold }

    /// The brain's line for it, which the board already answered; a poke's
    /// and a shake's are their own, by the run (`EventLine.poke`, `shake`).
    public func line(name: String = CharacterPack.active.name) -> String? {
        switch self {
        case .poke, .shake: nil
        case .stroke: "You stroked \(name)."
        case .hold: "You held a finger still on \(name), and it leaned into it."
        case .swipe: "You swiped \(name), a quick stroke."
        case .pickup: "You picked \(name) up."
        case .facedown: "You turned \(name) face down."
        }
    }

    /// The narration's cause and the board's caption, `{name}` where the
    /// buddy's name goes (`Narration.fit`), or none where the screen says it
    /// already; nil for a poke, whose narration counts the run
    /// (`Narration.of`). The board says its own words as it plays a touch,
    /// before the Mac has heard of it (firmware's `app/touch_reason.h`): a
    /// test holds these to the board's for the touches it names the same way.
    public var narration: (cause: String, fact: String?)? {
        switch self {
        case .stroke: ("You stroked it.", "you stroked {name}")
        case .hold: ("You held a finger on it.", "you held {name}")
        case .shake: ("You shook it.", "you shook {name}")
        case .pickup: ("You picked it up.", "you picked {name} up")
        case .facedown: ("You turned it face down.", "you turned {name} over")
        case .swipe: ("You swiped it.", nil)
        case .poke: nil
        }
    }
}
