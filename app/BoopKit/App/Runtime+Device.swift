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
        rig.link.connection(up, now: now)
        pipeline.harness.emit(Event(at: now, source: .device, type: .link, phase: up ? .start : .end, specificType: "board"))
        if !up { run(core.linkDown(at: now)) }
        changed()
    }

    /// A message from the device: its `hello`, answered by the link with the
    /// latest `state`; an `ev` (`deviceEvent`); how a `do` ended, which
    /// the link hands to whoever asked for it, and which is logged here.
    func device(_ line: String) {
        let now = options.clock()
        switch rig.link.receive(line, now: now) {
        case .ended(let ended):
            options.log("device: do \(ended.id) ended \(ended.how.rawValue)" + (ended.why.map { " (\($0))" } ?? ""))
            emit(DebugLog.ended(ended, at: now))
        default:
            break
        }
        changed()
    }

    /// The first board that fits and is tapped over Bluetooth, on
    /// onboarding's pairing tap or any later, is the one Boop takes from
    /// then on (`AppSettings.board`): saying hello isn't enough, since any
    /// board in range does.
    func remember() {
        guard settings.board == nil, rig.transport?.name == "ble", let hello = rig.link.hello else { return }
        saveSettings { $0.board = hello.id }
        options.log("device: remembering \(hello.id); Boop takes only it over Bluetooth until Settings forgets it")
        options.chooseBoard?(BoopDevice.advertised(hello.id))
        changed()
    }

    /// A tap, or BOOT's push-to-talk, on the board.
    func deviceEvent(_ ev: DeviceEvent) {
        let now = options.clock()
        switch ev.kind {
        case "tap":
            let finish = BoopDevice.finish(tapped: ev), button = BoopDevice.button(tapped: ev)
            onBoardTap?(button)
            options.log("device: tap" + (ev.did.map { " (\($0))" } ?? "") + (finish.map { " on do \($0)" } ?? "")
                + (BoopDevice.was(tapped: ev).map { " was \($0)" } ?? ""))
            remember()
            let opens = finish.flatMap { rig.reactions.opens(finish: $0) }
            // Onboarding hears every tap and BOOT press, which it was, and
            // whether it was on a finish, after the core takes it (onTap
            // is called on `home`, after this returns).
            home.async { [weak self] in self?.onTap?(button, opens != nil) }
            // BOOT: the core decides whether it hands you the next agent;
            // the board has played its guess (its hand-off, or a poke).
            if button { return run(pipeline.press(at: now, finish: opens)) }
            // Waiting to be shown where it sits: this tap is that, not a poke.
            if placing != nil { return placeHere(at: now) }
            // A poke. The device has already poked,
            // cutting the animation playing but not a reaction's `say` or face;
            // on the brain's finish that names whose turn it was it only
            // dipped, and the tap opens that thread.
            run(pipeline.poke(at: now, finish: opens))
        case "gesture":
            options.log("device: gesture \(ev.did ?? "?")")
            // Waiting to be shown where it sits: a touch on its face is that.
            if let kind = ev.did, places(gesture: kind) { return placeHere(at: now) }
            if let kind = ev.did { run(pipeline.gesture(kind, request: BoopDevice.request(held: ev), at: now)) }
        case "drawer":
            // The agents' drawer, the board's own: open (from the row it
            // has scrolled to), shut, or a row picked in it, by its number.
            options.log("device: drawer \(ev.did ?? "?")" + (BoopDevice.row(picked: ev).map { " \($0)" } ?? ""))
            // Onboarding's tour hears it open, and a row picked.
            if let did = ev.did, did != "closed" { home.async { [weak self] in self?.onDrawer?(did) } }
            switch ev.did {
            case "open", "closed":
                run(pipeline.drawer(open: ev.did == "open", from: BoopDevice.rows(from: ev), at: now))
            case "pick": if let row = BoopDevice.row(picked: ev) { run(pipeline.pick(row: row, at: now)) }
            default: break
            }
        case "card":
            // The card Boop holds: swiped to the next or the one before,
            // or tapped, which opens it on the Mac.
            options.log("device: card \(ev.did ?? "?")")
            switch ev.did {
            case "next": run(pipeline.swipeCard(by: 1, at: now))
            case "prev": run(pipeline.swipeCard(by: -1, at: now))
            case "open": run(pipeline.tapCard(at: now))
            default: break
            }
        case "ask":
            // An ask's end, which the board decides: the question, its
            // words and the answer come back with it; whether Boop keeps
            // it is the record's.
            guard let q = ev.data["q"]?.string else { break }
            let pick = ev.did ?? Asks.ignored
            let keeps = remembers?.askRecord(q)?.keeps ?? false
            options.log("device: ask \(q) \(pick)")
            run(pipeline.ask(q, question: ev.data["question"]?.string ?? "", pick: pick,
                             answer: pick == Asks.ignored ? nil : ev.data["answer"]?.string, keeps: keeps, at: now))
        case "talk_on", "talk_off":
            options.log("device: \(ev.kind)")
            // The device already shows `listening`.
            run(core.listen(ev.kind == "talk_on", by: .device, at: now))
        default:
            break
        }
    }

    /// On a call every Moment is small (`MomentRule.small`): played once,
    /// and a finish not sized by its turn, so nothing dances while your
    /// camera is on.
    func calmed(_ reaction: Moment) -> Moment {
        guard core.along.onCall else { return reaction }
        var m = reaction
        if let loops = m.loops { m.loops = min(loops, MomentOutput.sizes[MomentRule.small].loops) }
        if m.turn != nil { m.turn = 0 }
        return m
    }

    /// A snapshot for `rig`'s device.
    func show(_ snapshot: StateSnapshot) {
        rig.latest = snapshot
        rig.link.update(state: snapshot.fields, now: options.clock())
    }

    /// A rule's reaction: sent at once, after the
    /// `state` of the same input. It plays only if nothing plays on the
    /// device, or what plays is resting (`if_free`): a brain reaction's
    /// `say` playing would be cut, and a late rule reaction is worse than none, so the device
    /// skips it then. One holding up a sign waits its turn instead
    /// (`BoopDevice.play`). The core has already left it out while something
    /// needs you or `listening` shows. Push-to-talk's `listening` plays at
    /// once (`BoopDevice.play`), and drops the reactions waiting there.
    func playRule(_ reaction: Moment, _ ended: @escaping (DeviceLink.Outcome) -> Void = { _ in }) {
        let reaction = calmed(reaction)
        rig.link.do(reaction.name, args: reaction.args, play: BoopDevice.play(reaction), ttl: BoopDevice.reactionTTL, by: .rule,
                    now: options.clock(), ended)
    }

    /// A word of the work stream that comes forward: it waits in the
    /// device's queue for up to `BoopDevice.callTTL`, and a board that
    /// doesn't play the stream refuses it.
    func playCall(_ args: JSONObject) {
        rig.link.do(WorkStream.action, args: args, play: .next, ttl: BoopDevice.callTTL, by: .rule, now: options.clock()) { _ in }
    }

    /// A reaction from the brain, sent at once to wait in the device's
    /// queue (`next`, for up to 5 s), and its handle, ended once it's
    /// known how it went (read Boop's way by `Reactions`): at once when it
    /// can't be sent. On `home`.
    func queue(_ reaction: Moment, _ pending: Pending) {
        let reaction = calmed(reaction)
        let now = options.clock(), reactions = rig.reactions
        let id = rig.link.do(reaction.name, args: reaction.args, play: .next, ttl: BoopDevice.ttl(reaction), by: .brain,
                             now: now) { outcome in
            if let end = reactions.read(outcome, pending) { pending.finish(end) }
        }
        if let id, let thread = reaction.who?.opens { reactions.sent(id, opens: thread, ttl: BoopDevice.ttl(reaction), now: now) }
    }

    /// Drops the device links and looks for the devices again now.
    public func reconnectDevice() {
        rig.link.transport?.reconnect()
    }
}

