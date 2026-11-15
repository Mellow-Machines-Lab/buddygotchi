import Foundation

// Push-to-talk, as the app carries out what the core decides: the
// Mac's mic and what it heard.
extension Runtime {
    /// What push-to-talk heard, after `by`'s button, or nil for whoever's
    /// turned the mic on last: an event that may wake the brain, whose
    /// pass replies or ends `listening` (`passed`). `who` is `mic` for
    /// the app's own.
    func heard(_ words: String, by: Core.Talker?, who: String = "dev") {
        let now = options.clock()
        let by = by ?? core.pushToTalk.by
        let step = pipeline.said(words, by: by, at: now)
        run(step)
        run(core.heard(replyTo: step.waking.first?.seq, at: now))
        // No brain, no answer: a shrug and a sign that says why. A
        // demo's brain steps answer for it.
        if !pipeline.brain, !playingDemo {
            var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: now))
            let sign = Signs.reply(rig.steering.replies, Core.noBrainReply, calendar: core.calendar(at: now) + [Core.noBrain],
                                   rng: &rng)
            run(core.shrug(sign: sign, at: now))
        }
        options.log("\(who): said \(words.count) characters")
        onHeard?(words)
    }

    /// The app's mic button: `who` is `app` for the app's own.
    func listen(_ on: Bool, who: String = "dev") {
        run(core.listen(on, by: .app, at: options.clock()))
        options.log("\(who): listen \(on)")
    }

    /// The core turned the Mac's mic on or off, after `by`'s button. On:
    /// the device's own button already shows `listening`, which the mirror
    /// shows too. Off: what the mic heard comes back to `said` or
    /// `heardNothing`.
    func mic(_ on: Bool, by: Core.Talker) {
        guard on != micOn else { return }
        micOn = on
        options.log("talk: mic \(on ? "on" : "off") (\(by.rawValue))")
        guard on else {
            if let heard = wordsOnRelease {
                wordsOnRelease = nil
                home.async { [self] in self.heard(heard, by: .app, who: Runtime.demoBy) }
            } else if onListen != nil {
                onListen?(false)
            } else {
                heardNothing()
            }
            return
        }
        if by == .device { onBoardListening?() }
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
            run(core.heardNothing(at: options.clock()))
            onHeard?(nil)
        }
    }

    /// The mic or speech recognition couldn't start, and why, for the
    /// popover: `listening` ends at once, after either button.
    public func micFailed(_ why: String) {
        home.async { [self] in
            options.log("talk: \(why)")
            run(core.micFailed(why, at: options.clock()))
            changed()
        }
    }

    /// The popover's "can't hear you" notice was dismissed.
    public func dismissMicTrouble() {
        home.async { [self] in
            core.dismissMicTrouble()
            changed()
        }
    }
}
