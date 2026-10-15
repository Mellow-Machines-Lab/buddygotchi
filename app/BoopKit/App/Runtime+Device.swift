import Foundation
import LinkKit
import MellowHarness

// The device: its link coming and going, its messages and events, and
// what the rules and the brain send it. On `home`, but `reconnectDevice`.
extension Runtime {
    /// The transport connected or dropped. On a drop the link fails every
    /// reaction still waiting for its `ended`, which HISTORY then says
    /// didn't happen, since that may never come. The
    /// device plays on, though, and the link may be back a second later,
    /// so a tap on a finish still playing still opens its thread.
    func connection(_ up: Bool) {
        let now = options.clock()
        link.connection(up, now: now)
        if !up { run(core.linkDown(at: now)) }
        changed()
    }

    /// A message from the device: its `hello`, answered by the link with the
    /// latest `state`; an `ev` (`deviceEvent`); how a `do` ended, which
    /// the link hands to whoever asked for it, and which is logged here.
    func device(_ line: String) {
        let now = options.clock()
        switch link.receive(line, now: now) {
        case .ended(let ended):
            options.log("device: do \(ended.id) ended \(ended.how.rawValue)" + (ended.why.map { " (\($0))" } ?? ""))
            emit(DebugLog.ended(ended, at: now))
            reactions.ended(ended.id)
        default:
            break
        }
        changed()
    }

    /// A tap, or BOOT's push-to-talk.
    func deviceEvent(_ ev: DeviceEvent) {
        let now = options.clock()
        switch ev.kind {
        case "tap":
            if ev.did == "poked" || ev.did == "tap_spam" { onReaction?(0, DeviceReaction(anim: ev.did)) }
            let finish = BoopDevice.finish(tapped: ev)
            options.log("device: tap" + (ev.did.map { " (\($0))" } ?? "") + (finish.map { " on do \($0)" } ?? ""))
            // A poke. The device has already poked,
            // cutting the animation playing but not a reaction's `say` or face;
            // on the brain's finish that names whose turn it was it only
            // dipped, and the tap opens that thread.
            run(pipeline.poke(at: now, finish: finish.flatMap { reactions.opens(finish: $0) }))
        case "talk_on", "talk_off":
            options.log("device: \(ev.kind)")
            // The device already shows `listening`.
            run(core.listen(ev.kind == "talk_on", by: .device, at: now))
        default:
            break
        }
    }

    /// A snapshot for the device.
    func show(_ snapshot: StateSnapshot) {
        latest = snapshot
        link.update(state: snapshot.fields, now: options.clock())
    }

    /// A rule's reaction: sent at once, after the
    /// `state` of the same input. It plays only if nothing plays on the
    /// device, or what plays is resting (`if_free`): a brain reaction's
    /// `say` playing would be cut, and a late rule reaction is worse than none, so the device
    /// skips it then. The core has already left it out while something
    /// needs you or `listening` shows. Push-to-talk's `listening` plays at
    /// once (`BoopDevice.play`), and drops the reactions waiting there.
    func playRule(_ reaction: DeviceReaction) {
        if let id = link.do(reaction.name, args: reaction.args, play: BoopDevice.play(reaction.name), by: .rule,
                            now: options.clock(), { _ in }) {
            onReaction?(id, reaction)
        }
    }

    /// A reaction from the brain, sent at once to wait in the device's
    /// queue (`next`, for up to 5 s), and its handle, ended once it's
    /// known how it went (read Boop's way by `Reactions`): at once when it
    /// can't be sent. On `home`.
    func queue(_ reaction: DeviceReaction, _ pending: Pending) {
        let now = options.clock(), reactions = reactions
        let id = link.do(reaction.name, args: reaction.args, play: .next, ttl: BoopDevice.reactionTTL, by: .brain,
                         now: now) { outcome in
            if let end = reactions.read(outcome, pending) { pending.finish(end) }
        }
        if let id { onReaction?(id, reaction) }
        if let id, let thread = reaction.who?.opens { reactions.sent(id, opens: thread, ttl: BoopDevice.reactionTTL, now: now) }
    }

    /// Drops the device link and looks for the device again now.
    public func reconnectDevice() {
        link.transport?.reconnect()
    }
}
