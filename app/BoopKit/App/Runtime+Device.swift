import Foundation
import LinkKit
import MellowHarness

// The device: its link coming and going, its messages and events, and
// what the rules and the brain send it, each on a buddy's board, the
// first's by default. On `home`, but `reconnectDevice`.
extension Runtime {
    /// The transport connected or dropped. On a drop the link fails every
    /// reaction still waiting for its `ended`, which HISTORY then says
    /// didn't happen, since that may never come. The
    /// device plays on, though, and the link may be back a second later,
    /// so a tap on a finish still playing still opens its thread.
    func connection(_ up: Bool, on rig: Rig? = nil) {
        let rig = rig ?? rigs[0]
        let now = options.clock()
        rig.link.connection(up, now: now)
        if !up { run(core(rig).linkDown(at: now), on: rig) }
        changed()
    }

    /// A message from the device: its `hello`, answered by the link with the
    /// latest `state`; an `ev` (`deviceEvent`); how a `do` ended, which
    /// the link hands to whoever asked for it, and which is logged here.
    func device(_ line: String, on rig: Rig? = nil) {
        let rig = rig ?? rigs[0]
        let now = options.clock()
        switch rig.link.receive(line, now: now) {
        case .hello(let hello):
            remember(hello, on: rig)
        case .ended(let ended):
            options.log("device\(Runtime.whose(rig)): do \(ended.id) ended \(ended.how.rawValue)" + (ended.why.map { " (\($0))" } ?? ""))
            emit(DebugLog.ended(ended, at: now))
            rig.reactions.ended(ended.id)
        default:
            break
        }
        changed()
    }

    /// The first board that fits and says hello over Bluetooth is the one
    /// Boop takes from then on (`AppSettings.board`). Only for one Boop:
    /// several buddies name their boards in their settings.
    func remember(_ hello: Hello, on rig: Rig) {
        guard settings.board == nil, !pipeline.several, rig.transport?.name == "ble", rig.link.trouble == nil else { return }
        saveSettings { $0.board = hello.id }
        options.log("device: remembering \(hello.id); Boop takes only it over Bluetooth until Settings forgets it")
        options.chooseBoard?(BoopDevice.advertised(hello.id))
    }

    /// A tap, or BOOT's push-to-talk, on `rig`'s board.
    func deviceEvent(_ ev: DeviceEvent, on rig: Rig? = nil) {
        let rig = rig ?? rigs[0]
        let now = options.clock()
        switch ev.kind {
        case "tap":
            if rig === rigs[0], ev.did == "poked" || ev.did == "tap_spam" { onReaction?(0, DeviceReaction(anim: ev.did)) }
            let finish = BoopDevice.finish(tapped: ev)
            options.log("device\(Runtime.whose(rig)): tap" + (ev.did.map { " (\($0))" } ?? "") + (finish.map { " on do \($0)" } ?? ""))
            let opens = finish.flatMap { rig.reactions.opens(finish: $0) }
            // Onboarding hears every tap and BOOT press, after the core
            // takes it (onTap is called on `home`, after this returns).
            if rig === rigs[0] { home.async { [weak self] in self?.onTap?() } }
            // BOOT: the core decides whether it hands you the next agent;
            // the board has played its guess (its hand-off, or a poke).
            if BoopDevice.button(tapped: ev) { return run(pipeline.press(at: now, finish: opens, buddy: rig.tag)) }
            // A poke. The device has already poked,
            // cutting the animation playing but not a reaction's `say` or face;
            // on the brain's finish that names whose turn it was it only
            // dipped, and the tap opens that thread.
            run(pipeline.poke(at: now, finish: opens, buddy: rig.tag))
        case "gesture":
            options.log("device\(Runtime.whose(rig)): gesture \(ev.did ?? "?")")
            if let kind = ev.did { run(pipeline.gesture(kind, request: BoopDevice.request(held: ev), at: now, buddy: rig.tag)) }
        case "talk_on", "talk_off":
            options.log("device\(Runtime.whose(rig)): \(ev.kind)")
            listener = rig
            // The device already shows `listening`.
            run(core(rig).listen(ev.kind == "talk_on", by: .device, at: now), on: rig)
        default:
            break
        }
    }

    /// A snapshot for `rig`'s device.
    func show(_ snapshot: StateSnapshot, on rig: Rig? = nil) {
        let rig = rig ?? rigs[0]
        rig.latest = snapshot
        rig.link.update(state: snapshot.fields, now: options.clock())
    }

    /// A rule's reaction: sent at once, after the
    /// `state` of the same input. It plays only if nothing plays on the
    /// device, or what plays is resting (`if_free`): a brain reaction's
    /// `say` playing would be cut, and a late rule reaction is worse than none, so the device
    /// skips it then. The core has already left it out while something
    /// needs you or `listening` shows. Push-to-talk's `listening` plays at
    /// once (`BoopDevice.play`), and drops the reactions waiting there.
    func playRule(_ reaction: DeviceReaction, on rig: Rig? = nil) {
        let rig = rig ?? rigs[0]
        if let id = rig.link.do(reaction.name, args: reaction.args, play: BoopDevice.play(reaction.name), by: .rule,
                                now: options.clock(), { _ in }), rig === rigs[0] {
            onReaction?(id, reaction)
        }
    }

    /// A reaction from the brain, sent at once to wait in the device's
    /// queue (`next`, for up to 5 s), and its handle, ended once it's
    /// known how it went (read Boop's way by `Reactions`): at once when it
    /// can't be sent. On `home`.
    func queue(_ reaction: DeviceReaction, _ pending: Pending, on rig: Rig? = nil) {
        let rig = rig ?? rigs[0]
        let now = options.clock(), reactions = rig.reactions
        let id = rig.link.do(reaction.name, args: reaction.args, play: .next, ttl: BoopDevice.reactionTTL, by: .brain,
                             now: now) { outcome in
            if let end = reactions.read(outcome, pending) { pending.finish(end) }
        }
        if let id, rig === rigs[0] { onReaction?(id, reaction) }
        if let id, let thread = reaction.who?.opens { reactions.sent(id, opens: thread, ttl: BoopDevice.reactionTTL, now: now) }
    }

    /// Drops the device links and looks for the devices again now.
    public func reconnectDevice() {
        for rig in rigs { rig.link.transport?.reconnect() }
    }
}

