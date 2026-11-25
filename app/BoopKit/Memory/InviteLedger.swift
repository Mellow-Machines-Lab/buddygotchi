import Foundation
import MellowHarness

/// How an invite ended, as the board says (`ev invite`'s `did`): touched
/// in time, the wait run out, touched within 30 s after that (the board
/// plays the payoff then), or cut short by needs you, face down, listening
/// or a reaction played at once. A `missed` may be followed by one `late`.
extension Moment.Invite {
    public enum End: String, CaseIterable, Sendable {
        case answered, missed, late, cut

        /// Your touch answered it: in time or late.
        public var isYours: Bool { self == .answered || self == .late }
    }
}

/// What Boop knows of its invites: a view over the transcript, never a
/// store of its own. It's a pure fold of the transcript's events
/// (`adding`): the reaction records that asked one (their `invite` fact,
/// the pose), counted as they're asked and taken back if the board didn't
/// play them, or let one go by (`invite_skipped`), and the board's `invite`
/// events, by the pose they name. The memory keeps it as it keeps the daily counts
/// (`InviteReader`), and catches it up from the transcript at launch.
///
/// | Question | Rule | Constant |
/// | --- | --- | --- |
/// | May Boop invite now? | Fewer than 10 invites asked on this Boop day, each counted as it's asked and taken back if the board didn't play it, so two skits close together can't both be the 10th | `mostADay` |
/// | ... | After 3 misses in a row of a pose, every second invite of that pose is skipped, until one is answered | `thinAfter` |
/// | Is the label shown? | Until that pose was answered 5 times; and again after 3 misses in a row of it, until answered | `labelUntil`, `labelBackAfter` |
/// | Is this the very first invite ever? | None asked before | |
///
/// A `late` counts as answered. A `cut` changes nothing. The wait is
/// `waitMs`, and `firstWaitMs` for the very first, so everyone learns the
/// loop once: no longer, so the longest Moment, the wait and the payoff
/// end inside the link's grace for a `do` (`DeviceLink.answerGraceMs`).
public struct InviteLedger: Codable, Equatable, Sendable {
    public static let mostADay = 10, thinAfter = 3, labelUntil = 5, labelBackAfter = 3
    public static let waitMs = 4000, firstWaitMs = 12_000

    /// The facts of a reaction's record that say it asked an invite, or
    /// let one go by for the misses, each with the pose.
    public static let askedFact = "invite", skippedFact = "invite_skipped"

    /// Every invite asked, and those asked on the Boop day open
    /// (`InviteReader.open(day:carry:)` starts it again).
    public var asked = 0, askedToday = 0
    /// The records that asked one, by `seq`, with the pose, until the board
    /// says how they ended.
    public var playing = Played<String>()
    /// Each pose's, by its name.
    public var poses: [String: Pose] = [:]

    /// One pose's: how often it was answered, how many misses in a row it
    /// has now, and whether its last invite was skipped for them.
    public struct Pose: Codable, Equatable, Sendable {
        public var answered = 0
        public var missedInARow = 0
        public var skipped = false
    }

    public init() {}

    /// `ledger` with `e` read into it.
    public static func adding(_ e: Event, to ledger: InviteLedger) -> InviteLedger {
        var l = ledger
        if e.kind == Event.did, e.action == MomentOutput.outputName, e["ok"]?.bool != false, let pose = e[askedFact]?.string {
            l.asked += 1
            l.askedToday += 1
            if e["open"]?.bool == true { l.playing.open[e.seq] = pose } else { l.poses[pose, default: Pose()].skipped = false }
            return l
        }
        if e.kind == Event.ended, let seq = e.about, let pose = l.playing.open.removeValue(forKey: seq) {
            if e["outcome"]?.string == "done" {
                l.poses[pose, default: Pose()].skipped = false
            } else {
                l.asked = max(0, l.asked - 1)
                l.askedToday = max(0, l.askedToday - 1)
            }
            return l
        }
        if e.kind == Event.did, e.action == MomentOutput.outputName, e["ok"]?.bool != false, let pose = e[skippedFact]?.string {
            l.poses[pose, default: Pose()].skipped = true
            return l
        }
        guard e.type == .invite, let pose = e["pose"]?.string, let end = Moment.Invite.End(rawValue: e.specificType) else { return l }
        switch end {
        case .answered, .late:
            l.poses[pose, default: Pose()].answered += 1
            l.poses[pose, default: Pose()].missedInARow = 0
        case .missed:
            l.poses[pose, default: Pose()].missedInARow += 1
        case .cut:
            break
        }
        return l
    }

    /// Whether the board's `end` may end the invite asked last, by the
    /// transcript's `events`: one end for one invite, and a `late` only
    /// after its `missed`. A board that ends one twice is heard once, so a
    /// touch is never paid twice; an end with no invite asked is none.
    public static func ends<Events: BidirectionalCollection<Event>>(_ end: Moment.Invite.End, after events: Events) -> Bool {
        for e in events.reversed() {
            if e.type == .invite, let had = Moment.Invite.End(rawValue: e.specificType) { return had == .missed && end == .late }
            if e.kind == Event.did, e.action == MomentOutput.outputName, e["ok"]?.bool != false, e[askedFact] != nil { return true }
        }
        return false
    }

    func pose(_ pose: Skit.Invite.Pose) -> Pose { poses[pose.rawValue] ?? Pose() }

    /// Whether the misses skip this invite of `pose`: from the 3rd in a
    /// row, every second one.
    public func thins(_ pose: Skit.Invite.Pose) -> Bool {
        let p = self.pose(pose)
        return p.missedInARow >= Self.thinAfter && !p.skipped
    }

    /// Whether an invite of `pose` shows its word by the place to touch.
    public func showsLabel(_ pose: Skit.Invite.Pose) -> Bool {
        let p = self.pose(pose)
        return p.answered < Self.labelUntil || p.missedInARow >= Self.labelBackAfter
    }

    /// Whether the next invite is the very first this buddy asks.
    public var first: Bool { asked == 0 }

    /// What a skit's invite comes to now.
    public enum Asking: Equatable, Sendable {
        /// Nothing: the skit has no invite, or the day has had its most.
        case nothing
        /// Skipped for the misses: the reaction's record says so.
        case skipped(Skit.Invite.Pose)
        case asks(Moment.Invite)
    }

    /// What `skit`'s invite comes to: its word by the place to touch is
    /// the pack's for the touch (`label`), and `xp` what the touch will earn.
    public func asking(_ skit: Skit, label: (Skit.Invite.Touch) -> String?, xp: Int?) -> Asking {
        guard let invite = skit.invite, askedToday < Self.mostADay else { return .nothing }
        if thins(invite.pose) { return .skipped(invite.pose) }
        return .asks(Moment.Invite(skit: skit.id, invite, label: showsLabel(invite.pose) ? label(invite.touch) : nil,
                                   ms: first ? Self.firstWaitMs : Self.waitMs, xp: xp))
    }
}

/// The invite ledger as a reader of the transcript (`TranscriptReader`):
/// kept in the memory's store, so a launch catches up on what it missed.
/// Each Boop day starts the day's count again.
public final class InviteReader: TranscriptReader {
    public let name = "invites"

    public init() {}

    public func open(day: String, carry: InviteLedger?) -> InviteLedger {
        var l = carry ?? InviteLedger()
        l.askedToday = 0
        return l
    }

    public func read(_ e: Event, line: Line?, into ledger: inout InviteLedger) -> Bool {
        let next = InviteLedger.adding(e, to: ledger)
        defer { ledger = next }
        return next != ledger
    }

    public func close(day: String, state: InviteLedger, live: Bool) {}
}
