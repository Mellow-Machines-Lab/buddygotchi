import Foundation
import MellowHarness

// The brain: Jev's key, the brain it builds, and each pass's outcome.
extension Runtime {
    /// Boop's mood now, as the log has it.
    var moodNow: String { MoodOutput.value(mood, harness.log.view(now: options.clock())) }

    /// Every pass the harness made: its app log line
    /// (the brain's only), whether the brain is in trouble, its
    /// `debug.jsonl` lines, and what it means for push-to-talk's reply.
    func passed(_ pass: Harness.Pass) {
        let now = options.clock()
        if let line = Runtime.logLine(pass) { options.log(line) }
        if pass.prompt != nil, pass.current {
            // Only a pass that asked the brain in use says how it's doing.
            (droppedInARow, trouble) = BrainTrouble.after(pass.error, previous: droppedInARow)
        }
        // The head is logged only when it changes; the pass, HISTORY and NOW.
        debugWriter?.pass(pass, launchOptions: launchOptions, at: now)
        // Push-to-talk's reply: a reaction is one, and a pass on what you
        // said without one means none is coming.
        let rig = rig(pass.voice)
        let reaction = pass.outputs.first { $0.name == ReactOutput.outputName && $0.result.ok }
        run(core(rig).passed(about: pass.event?.seq, reacted: reaction != nil, at: now), on: rig)
        changed()
    }

    /// The app log's line for a pass the brain was asked, or held back for:
    /// its event's type and phase, the time and which outputs returned
    /// a result, never their messages. Nil for a forced pass.
    static func logLine(_ pass: Harness.Pass) -> String? {
        guard let e = pass.event else { return nil }
        let result = pass.dropped.map { "dropped: \($0)" } ?? pass.held.map { "held: \($0)" }
            ?? Harness.OutputRecord.names(pass.outputs)
        return "brain \(e.name) \(pass.latencyMs) ms → " + result
    }

    /// Jev's key as Settings just saved it (nil when it was cleared);
    /// `BOOP_JEV_KEY` still wins. Used from the next event.
    public func reloadBrain(jevKey key: String?) {
        home.async { [self] in
            jevKey = .some(options.readJevKey { key })
            useBrain()
            changed()
        }
    }

    /// The brain for Jev's key as far as it's been read. On `home`.
    func useBrain() {
        let brain = options.brain(jevKey ?? nil)
        harness.use(brain)
        pipeline.brain = brain != nil
        trouble = nil
        droppedInARow = 0
        options.log("brain \(brain?.id ?? "none")" + (brain == nil ? ": no Jev key, so Boop does only its rule reactions" : ""))
    }

    /// Reads Jev's key off `home`: a Keychain prompt
    /// there would stall every hook, tick and device message until it's
    /// answered. Then the brain is built with it. On `home`.
    func readJevKey() {
        guard jevKey == nil else { return }
        let read = options.readJevKey, stateDir = options.stateDir
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let key = read { Keychain.jevKey(account: Keychain.account(for: stateDir)) }
            self?.home.async { [weak self] in
                // Settings may already have installed a brain while the
                // startup read waited. Keep that brain too: rebuilding it
                // would discard any pass it has in flight.
                guard let self, jevKey == nil else { return }
                jevKey = .some(key)
                useBrain()
                changed()
            }
        }
    }
}
