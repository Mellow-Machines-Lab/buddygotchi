import Foundation
import MellowHarness

// The brain: the rules, Jev in their seats for its key, and how Jev does.
extension Runtime {
    /// Boop's mood now, as the log has it.
    var moodNow: String { MoodOutput.value(mood, harness.log.view(now: options.clock())) }

    /// Every pass the harness made: its app log line
    /// (the brain's only), its `debug.jsonl` lines, and what it means for
    /// push-to-talk's reply.
    func passed(_ pass: Harness.Pass) {
        let now = options.clock()
        if let line = Runtime.logLine(pass) { options.log(line) }
        // The head is logged only when it changes; the pass, HISTORY and NOW.
        debugWriter?.pass(pass, launchOptions: launchOptions, at: now)
        // Push-to-talk's reply: a reaction is one, and a pass on what you
        // said without one means none is coming.
        let reaction = pass.outputs.first { $0.name == MomentOutput.outputName && $0.result.ok }
        run(core.passed(about: pass.event?.seq, reacted: reaction != nil, at: now))
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

    /// The brain for Jev's key as far as it's been read: the rules, with
    /// Jev in their seats when there's a key; with `alone`, the options'
    /// brain alone, or none. On `home`.
    func useBrain() {
        let key = jevKey ?? nil
        brainUses += 1
        let use = brainUses
        let brain: (any Brain)?
        let said: String
        if options.alone {
            brain = options.brain(key)
            said = brain?.id ?? "none: nothing wakes it"
        } else {
            let rules = self.rules ?? rulesBrain()
            self.rules = rules
            let jev = options.brain(key)
            brain = SeatedBrain(rules: rules, jev: jev) { [weak self] error in
                self?.home.async { [weak self] in self?.jevAnswered(error, use: use) }
            }
            said = rules.id + (jev.map { ", \($0.id) in its seats" } ?? "")
        }
        harness.use(brain)
        pipeline.brain = brain != nil
        trouble = nil
        jevFailedInARow = 0
        options.log("brain " + said)
    }

    /// How Jev did at a pass of the brain `use` installed: nil in time,
    /// else why not. Only Jev's trouble is shown, and only a key has any
    /// (`BrainTrouble`). On `home`.
    func jevAnswered(_ error: BrainError?, use: Int) {
        guard use == brainUses else { return }
        let before = trouble
        (jevFailedInARow, trouble) = BrainTrouble.after(error, previous: jevFailedInARow)
        if trouble != before { changed() }
    }

    /// The brain in the box, for this buddy: it reads each event's line
    /// and the mood as a call is prepared. On `home`.
    func rulesBrain() -> RulesBrain {
        let h = harness, view = view, mood = rig.mood!, pack = core.config.pack
        let core = core
        return RulesBrain(facts: { [weak h] in h?.line($0)?.facts },
                          seemed: { [weak h] e in
                              // How the finished turn's agent read you, from its result card.
                              guard let h, let key = TranscriptView.about(e, facts: h.line(e.seq)?.facts) else { return nil }
                              return core.result(for: key)?.seemed
                          },
                          mood: { log in (MoodOutput.value(mood, log, pack: pack), MoodOutput.level(mood, log)) },
                          working: { [weak h] log in view.isWorking(at: h?.clock.now() ?? 0, log) })
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
