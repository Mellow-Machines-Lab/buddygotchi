import Foundation
import MellowHarness

// Push-to-talk, as the core keeps it: when the mic goes on and off and
// when `listening` ends.
extension Core {
    /// Who turned the Mac's mic on: the device's BOOT button or the app's
    /// mic button.
    public enum Talker: String, Sendable { case device, app }
    /// The mic is never on longer than this, whatever happens to the release.
    public static let listenLimitMs: Int64 = 30_000
    /// After the mic goes off, the device holds `listening` this long at
    /// most for the reply (firmware `kListenHoldMs`).
    public static let replyWaitMs: Int64 = 8000

    /// Push-to-talk as the core keeps it, its one owner: the runtime turns
    /// the mic on and off and plays what the core says, and the popover
    /// shows a copy.
    public struct Talk: Equatable, Sendable {
        /// While the Mac's mic is on: who turned it on, and when.
        public struct Mic: Equatable, Sendable {
            public var by: Talker
            public var since: Int64
        }

        public var mic: Mic?
        /// Whose button turned the mic on last: what it hears is theirs.
        public var by: Talker = .app
        /// Once the mic is off, until when the device still shows
        /// `listening` waiting for the reply; nil once it's over.
        public var replyUntil: Int64?
        /// The `seq` of what you said, while its reply may still come: the
        /// first pass on it or on anything newer ends `listening` unless
        /// it reacted, which is the reply.
        public var replyFor: Int?
        /// Why push-to-talk couldn't hear you, until the next try.
        public var trouble: String?
    }

    /// While the Mac's mic is on: who turned it on, and when.
    public var listening: Talk.Mic? { talk.mic }

    /// Why listening started, waited or ended, as its records say.
    public enum ListenWhy {
        public static let released = "released", limit = "limit", linkDown = "link down", replied = "replied",
                          noReply = "no reply", heardNothing = "heard nothing", micFailed = "mic failed",
                          timedOut = "timed out"
    }

    /// Push-to-talk: start or stop listening, after the device's BOOT
    /// button (`talk_on`, `talk_off`), which already shows `listening`, or
    /// the app's mic button, for which the device is told to show it.
    @discardableResult
    public func listen(_ on: Bool, by talker: Talker = .app, at now: Int64) -> [CoreEffect] {
        talkInput(now) { fx in
            if on { startListening(by: talker, now, &fx) } else { stopListening(ListenWhy.released, now, &fx) }
        }
    }

    /// The link to the device dropped, so its button's release can't
    /// arrive: stop listening now. The app's mic button carries on.
    @discardableResult
    public func linkDown(at now: Int64) -> [CoreEffect] {
        talkStep { fx in
            if talk.mic?.by == .device { stopListening(ListenWhy.linkDown, now, &fx) }
        }
    }

    /// What the mic heard was recorded as said, the event `seq` if it
    /// wakes the brain: its reply may come. With nothing to wake, none is
    /// coming, so `listening` ends now.
    @discardableResult
    public func heard(replyTo seq: Int?, at now: Int64) -> [CoreEffect] {
        talkStep { fx in
            if let seq { talk.replyFor = seq } else { endListening(ListenWhy.noReply, now, &fx) }
        }
    }

    /// The mic went off and heard nothing: no reply is coming.
    @discardableResult
    public func heardNothing(at now: Int64) -> [CoreEffect] {
        talkStep { fx in endListening(ListenWhy.heardNothing, now, &fx) }
    }

    /// The mic or speech recognition couldn't start: `listening` ends at
    /// once, and `why` stays for the popover until the next try.
    @discardableResult
    public func micFailed(_ why: String, at now: Int64) -> [CoreEffect] {
        talkStep { fx in
            talk.trouble = why
            endListening(ListenWhy.micFailed, now, &fx, facts: ["trouble": .string(why)])
        }
    }

    /// The popover's "can't hear you" notice was dismissed.
    public func dismissMicTrouble() { talk.trouble = nil }

    /// A pass is over, about the event `seq` (nil for a forced one), and
    /// whether it started a reaction. A reaction ends `listening`: it's
    /// the reply, and the device ends it as it plays. The first pass on
    /// what you said or on anything newer that didn't react means none is
    /// coming, so `listening` ends now.
    @discardableResult
    public func passed(about seq: Int?, reacted: Bool, at now: Int64) -> [CoreEffect] {
        talkStep { fx in
            let answered = talk.replyFor.map { r in seq.map { $0 >= r } ?? false } ?? false
            if answered { talk.replyFor = nil }
            if reacted {
                endListening(ListenWhy.replied, now, &fx, stop: false)
            } else if answered {
                endListening(ListenWhy.noReply, now, &fx)
            }
        }
    }

    /// Whether the device shows `listening` at `now`: the mic is on, or it
    /// went off and the reply hasn't come yet.
    public func showsListening(at now: Int64) -> Bool {
        talk.mic != nil || talk.replyUntil.map { now < $0 } == true
    }

    /// One push-to-talk input: the timers first, then `body`'s rules,
    /// then what the device shows.
    private func talkInput(_ now: Int64, _ body: (inout [CoreEffect]) -> Void) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        startDayIfNew(now, &fx)
        body(&fx)
        publish(now, &fx)
        return fx
    }

    /// The rest of push-to-talk's steps change nothing the device's
    /// `state` shows: only their records and reactions.
    private func talkStep(_ body: (inout [CoreEffect]) -> Void) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        body(&fx)
        return fx
    }

    /// Turns the mic on, if it's off, recorded as `listen_start`. After the
    /// app's button the device is told to show `listening` at once (its own
    /// button already does), which drops the reactions waiting there,
    /// since one would end it.
    func startListening(by talker: Talker, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard talk.mic == nil else { return }
        talk = Talk(mic: Talk.Mic(by: talker, since: now), by: talker)
        recordListen(.start, now, &fx)
        if talker == .app { fx.append(.reaction(DeviceReaction(anim: BoopDevice.listening))) }
        fx.append(.listen(true, by: talker))
    }

    /// Turns the mic off, if it's on, recorded as `listen_wait`: the device
    /// holds `listening` for the reply until the core ends it
    /// (`endListening`), or `replyWaitMs` at most.
    func stopListening(_ why: String, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard let mic = talk.mic else { return }
        talk.mic = nil
        talk.replyUntil = now + Self.replyWaitMs
        recordListen(.wait, now, &fx, data: ["why": .string(why)])
        fx.append(.listen(false, by: mic.by))
    }

    /// Ends `listening`: with `stop`, the device is told so with
    /// `stop_listening`, which ends nothing else and does nothing where
    /// `listening` already ended. Recorded as `listen_end` only when it
    /// hadn't ended yet: as timed out once the reply's wait is over.
    func endListening(_ why: String, _ now: Int64, _ fx: inout [CoreEffect], stop: Bool = true,
                      facts: [String: JSONValue] = [:]) {
        if talk.mic != nil || talk.replyUntil != nil {
            let late = talk.mic == nil && talk.replyUntil.map { now >= $0 } == true
            var data = facts
            data["why"] = .string(late ? ListenWhy.timedOut : why)
            recordListen(.end, now, &fx, data: data)
        }
        talk.mic = nil
        talk.replyUntil = nil
        if stop { fx.append(.reaction(DeviceReaction(anim: BoopDevice.stopListening))) }
    }

    /// A `listen_start`, `listen_wait` or `listen_end` record: the core's,
    /// by rule, for whose button (`device` or `app`). Log-only: no line.
    func recordListen(_ phase: Event.Phase, _ now: Int64, _ fx: inout [CoreEffect], data: [String: JSONValue] = [:]) {
        var data = data
        data["by"] = "rule"
        fx.append(.record(Event(at: now, source: .boop, type: .listen, phase: phase, specificType: talk.by.rawValue,
                                data: data)))
    }
}
