import AgentHooks
import Foundation
import MellowHarness
import LinkKit

/// The brain's reactions on the device, until each ends.
/// The device decides what plays when (its queue, linkkit/SPEC.md §4):
/// each reaction goes out at once, a `do` that waits in the queue there, and the
/// link hands back how it came out, once. This
/// reads that as its handle's end, holds a reaction your tap cut short in
/// progress until the pokes stop, and keeps where a tap on the brain's
/// finish opens its thread while the finish may still
/// play or linger after, a link that drops briefly included, since the
/// device plays on. The device alone says a tap landed on a finish, so
/// this keeps each until the link would have given up on it, past its
/// `ended`.
///
/// On the runtime's queue and clock. Its bookkeeping is done before any
/// handle is finished, so what an end sets off may call back in.
public final class Reactions {
    /// How a reaction your tap cut short reads while the pokes go on, in
    /// the logs: the eval's steps say it so (EVALS.md §1).
    public static var tapCut: String { "cut short: you tapped \(CharacterPack.active.name)" }

    /// The handles of reactions your tap cut short: in progress while the
    /// pokes go on, so the pokes after it don't get it again, and done
    /// once they stop (`pokesStopped`).
    public private(set) var cutByTap: [Pending] = []
    /// Where a tap on each finish sent opens its thread, by its `do` id,
    /// until the link would have given up on it.
    public private(set) var opens: [Int: (thread: ThreadRef, until: Int64)] = [:]

    /// The invite in flight: the `do` that asks it, from when it's sent
    /// until its `ended`, and until when it may hold the device's queue.
    public private(set) var invite: (id: Int, until: Int64)?

    public init() {}

    /// The `do` sent as `id` at `now`, waiting up to `ttl` in the queue,
    /// asks an invite whose pose waits `ms`: it holds the queue up to its
    /// own wait and `BoopDevice.inviteHoldsMs` after.
    public func sent(_ id: Int, inviting ms: Int, ttl: Int, now: Int64) {
        invite = (id, now + Int64(ttl + BoopDevice.inviteHoldsMs(ms)))
    }

    /// The `do` sent as `id` ended: an invite it asked holds the queue no more.
    public func ended(_ id: Int) {
        if invite?.id == id { invite = nil }
    }

    /// How long a `do` sent at `now` may wait in the queue, `ttl` its own:
    /// while an invite is in flight, until the invite would be over, as the
    /// pose holds the queue until its payoff or shrug ends. With its own,
    /// the ring's gold after a win that invites a tap would be skipped late.
    public func ttl(_ ttl: Int, now: Int64) -> Int {
        guard let invite, invite.until > now else { return ttl }
        return max(ttl, Int(invite.until - now))
    }

    /// The finish sent as `id` at `now`, waiting up to `ttl` in the queue:
    /// a tap on it opens `thread`.
    public func sent(_ id: Int, opens thread: ThreadRef, ttl: Int, now: Int64) {
        opens[id] = (thread, now + Int64(ttl) + DeviceLink.answerGraceMs)
    }

    /// Once a second: forgets the finishes the link has given up on, and
    /// an invite past its time.
    public func tick(now: Int64) {
        opens = opens.filter { $0.value.until > now }
        if let invite, invite.until <= now { self.invite = nil }
    }

    /// The thread a tap on the finish `id` opens: the device said the tap
    /// landed on it, as it played or lingered after. Nil once the link
    /// has given up on it.
    public func opens(finish id: Int) -> ThreadRef? { opens[id]?.thread }

    /// How the reaction whose handle is `pending` came out: its end, or
    /// nil, holding it while the pokes go on, when your tap cut it.
    public func read(_ outcome: DeviceLink.Outcome, _ pending: Pending) -> Pending.End? {
        guard let end = Self.end(outcome) else {
            cutByTap.append(pending)
            return nil
        }
        return end
    }

    /// The pokes stopped, or something else happened: the reactions a tap
    /// cut short end as done, since you saw them begin.
    public func pokesStopped() {
        let held = cutByTap
        cutByTap = []
        for pending in held { pending.finish(.done) }
    }

    /// How a reaction ended, from the device's
    /// `ended` or the link's failure; nil for a cut by your tap, which is
    /// held until the pokes stop.
    public static func end(_ outcome: DeviceLink.Outcome) -> Pending.End? {
        switch outcome {
        case .ended(let ended):
            switch (ended.how, ended.why) {
            case (.done, _): return .done
            case (.cut, "tap"): return nil
            case (.cut, let why): return .failed("cut short" + (why.flatMap { cutBy[$0] }.map { ": " + $0 } ?? ""))
            case (.skipped, "late"): return .failed("waited too long")
            case (.skipped, BoopDevice.micOn): return .failed("the mic went on")
            case (.skipped, let why?): return .failed(skippedBy[why] ?? "skipped: " + why)
            case (.skipped, nil): return .failed("skipped")
            }
        case .failed(let failure):
            // No device connected, the device disconnected, or it never
            // said it ended: in the link's own words.
            return .failed(failure.description)
        }
    }

    /// What cut a reaction short, as its end says it; a tap's holds it
    /// until the pokes stop, and `reset` is a tool's.
    static let cutBy = [
        "now": "something newer played",
        "needs_you": "something needed you",
        BoopDevice.micOn: "the mic went on",
        "facedown": "it was put face down",
    ]

    /// Why the board's behaviour refused a reaction, as its end says it:
    /// HISTORY tells the brain what really happened.
    static let skippedBy = [
        "needs_you": "something needed you",
        BoopDevice.listening: "it was listening to you",
        "not_listening": "it wasn't listening",
        "no_app": "the board hadn't heard from the Mac",
        "nothing": "it had nothing it could play",
    ]
}
