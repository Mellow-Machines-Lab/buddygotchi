import Foundation
import MellowHarness

/// One kind of moment that has takes of its own and always speaks: the
/// pack's `skits` in `character.json` (characters/CHARACTER.md §8), each the
/// slots of the rules' reading (`RulesBrain.Slot`) it plays at. Its takes
/// are the voice's, part `skit`, its id their meaning. It may have a clip
/// of the pack's, which its Moment plays as its face starts, and an invite:
/// after it plays, Boop asks for one touch, and the touch pays off.
public struct Skit: Equatable, Sendable {
    public let id: String
    public let slots: [RulesBrain.Slot]
    /// The pack's clip its Moment plays as its face starts (`Moment.clip`),
    /// before any invite, or nil for the face alone.
    public let clip: String?
    /// What it asks of you after it plays, or nil for nothing.
    public let invite: Invite?

    /// The most bytes a clip's name has: what the board keeps of one
    /// (firmware `kReplyBytes`, less its end).
    public static let clipBytes = 11
    /// The most bytes a skit's id has: what the board keeps of one to name
    /// the invite it ends (firmware `kSkitBytes`, less its end).
    public static let idBytes = 15

    /// Whether `name` is one the board keeps whole in `bytes`: letters,
    /// digits or dashes, so it's never escaped either.
    static func fits(_ name: String, _ bytes: Int) -> Bool {
        !name.isEmpty && name.utf8.count <= bytes && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    public init(id: String, slots: [RulesBrain.Slot], clip: String? = nil, invite: Invite? = nil) {
        self.id = id
        self.slots = slots
        self.clip = clip
        self.invite = invite
    }

    /// The pack's invite for a skit (`character.json`'s `invite`): the pose
    /// Boop turns to you in, the one touch it asks for, and what that touch
    /// pays off with. The board plays each by its name.
    public struct Invite: Equatable, Sendable {
        /// A palm held up, a lean in, or its back turned to you.
        public enum Pose: String, CaseIterable, Sendable { case palm, lean, back }
        /// A tap (on the Mac a poke) or a stroke.
        public enum Touch: String, CaseIterable, Sendable {
            case tap, stroke

            /// The touch it is on the Mac.
            public var touch: BoopKit.Touch { self == .tap ? .poke : .stroke }
        }
        /// A high five, a purr, a sigh of relief.
        public enum Payoff: String, CaseIterable, Sendable { case highfive, purr, sigh }

        public let pose: Pose
        public let touch: Touch
        public let payoff: Payoff

        public init(pose: Pose, touch: Touch, payoff: Payoff) {
            self.pose = pose
            self.touch = touch
            self.payoff = payoff
        }
    }
}

/// When a skit plays, and whether it swears: plain functions of the slot
/// an event reads as and its line's facts, the table here and nowhere else
/// (`SkitTests` pins it). The brain never vetoes one: its Moment plays,
/// in the slot's face when the brain picked none (`MomentOutput`).
public enum Skits {
    /// A skit playing: which, and whether it swears.
    public struct Play: Equatable, Sendable {
        public let skit: Skit
        public let swears: Bool
    }

    /// A check failing plays its skit from this one in a row: the first
    /// two are no drama yet.
    public static let checkFailingFrom = 3
    /// A failed turn swears with this many failed checks on the way.
    public static let swearsAtChecksFailed = 2

    /// The skit that plays at `slot`, by the event's line's `facts`, or nil
    /// for none: the one of `skits` that lists the slot, unless the table
    /// says it waits. It swears only when `swears` (Settings' swearing on)
    /// and the failures have piled up.
    ///
    /// | The slot | It plays | It swears |
    /// | --- | --- | --- |
    /// | `checkFailing` | from the 3rd failed check in a row (`failed_before` 2 or more) | always |
    /// | `failed`, `failedVeryLong`, `gaveUp` | always | with 2 or more failed checks in the turn (`checks_failed`) |
    /// | Any other the pack's skits list | always | never |
    /// | One no skit lists | no | |
    public static func play(slot: RulesBrain.Slot, facts: [String: JSONValue], swears: Bool, in skits: [Skit]) -> Play? {
        guard let skit = skits.first(where: { $0.slots.contains(slot) }) else { return nil }
        switch slot {
        case .checkFailing:
            guard (facts["failed_before"]?.int ?? 0) >= Int64(checkFailingFrom - 1) else { return nil }
            return Play(skit: skit, swears: swears)
        case .failed, .failedVeryLong, .gaveUp:
            return Play(skit: skit, swears: swears && (facts["checks_failed"]?.int ?? 0) >= Int64(swearsAtChecksFailed))
        default:
            return Play(skit: skit, swears: false)
        }
    }
}
