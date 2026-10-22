import Foundation

// Push-to-talk, as the app carries out what the core decides: the
// Mac's mic and what it heard.
extension Runtime {
    /// What push-to-talk heard, after `by`'s button, or nil for whoever's
    /// turned the mic on last: an event that may wake the brain, whose
    /// pass replies or ends `listening` (`passed`). `who` is `mic` for
    /// the app's own.
    /// With several buddies, a board's button says it to that buddy, and
    /// the app's to them all.
    func heard(_ words: String, by: Core.Talker?, who: String = "dev", to buddy: String? = nil) {
        let now = options.clock()
        let by = by ?? core(listener ?? rigs[0]).talk.by
        let to = buddy.map(rig) ?? (by == .device ? listener : nil)
        let step = pipeline.said(words, by: by, buddy: to?.tag, at: now)
        run(step)
        for rig in to.map({ [$0] }) ?? rigs {
            run(core(rig).heard(replyTo: step.waking.first?.seq, at: now), on: rig)
        }
        options.log("\(who): said \(words.count) characters")
    }

    /// The app's mic button, which every buddy listens to: `who` is `app`
    /// for the app's own.
    func listen(_ on: Bool, who: String = "dev", buddy: String? = nil) {
        listener = nil
        for rig in buddy.map({ [rig($0)] }) ?? rigs { run(core(rig).listen(on, by: .app, at: options.clock()), on: rig) }
        options.log("\(who): listen \(on)")
    }

    /// The core turned the Mac's mic on or off, after `by`'s button. On:
    /// the device's own button already shows `listening`, which the mirror
    /// shows too. Off: what the mic heard comes back to `said` or
    /// `heardNothing`.
    func mic(_ on: Bool, by: Core.Talker) {
        // Several buddies listening to the app's button turn it on once.
        guard on != micOn else { return }
        micOn = on
        options.log("talk: mic \(on ? "on" : "off") (\(by.rawValue))")
        guard on else {
            if onListen != nil { onListen?(false) } else { heardNothing() }
            return
        }
        if by == .device { onReaction?(0, DeviceReaction(anim: BoopDevice.listening)) }
        onListen?(true)
    }

    /// The app's mic button: start or stop listening.
    public func setListening(_ on: Bool) {
        home.async { [self] in listen(on, who: "app") }
    }

    /// What push-to-talk heard, once the mic is off.
    public func said(_ words: String) {
        home.async { [self] in heard(words, by: nil, who: "mic") }
    }

    /// The mic went off and heard nothing: no reply is coming.
    public func heardNothing() {
        home.async { [self] in
            options.log("talk: heard nothing")
            for rig in rigs { run(core(rig).heardNothing(at: options.clock()), on: rig) }
        }
    }

    /// The mic or speech recognition couldn't start, and why, for the
    /// popover: `listening` ends at once, after either button.
    public func micFailed(_ why: String) {
        home.async { [self] in
            options.log("talk: \(why)")
            for rig in rigs { run(core(rig).micFailed(why, at: options.clock()), on: rig) }
            changed()
        }
    }

    /// The popover's "can't hear you" notice was dismissed.
    public func dismissMicTrouble() {
        home.async { [self] in
            for rig in rigs { core(rig).dismissMicTrouble() }
            changed()
        }
    }
}
