import Foundation
import LinkKit

// What the menu bar shows, built after every change.
extension Runtime {
    /// What the menu bar shows.
    public struct Status: Sendable {
        /// Boop's name, from `long-term.md`.
        public var name: String
        /// What the device shows, and Boop's mood.
        public var snapshot: StateSnapshot
        /// Every session, for the popover's list.
        public var sessions: [SessionSummary]
        public var connected: Bool
        /// What the device said of itself in its `hello`.
        public var device: DeviceInfo?
        /// Why the link can't look for the device (Bluetooth off), in the
        /// transport's words, for the popover.
        public var linkTrouble: String?
        /// Why the device connected gets no reactions: its firmware doesn't
        /// fit the app (linkkit/SPEC.md §6), in the link's words.
        public var deviceTrouble: String?
        public var personality: Personality
        /// The brain as it runs: `jev:jev-latest`, or `none` without a key.
        public var brain: String
        /// Jev's key has been read, whether there was one or not. Until
        /// then `brain` is `none` only because it isn't known yet.
        public var keyRead: Bool
        /// The brain failing, for the popover's notice.
        public var brainTrouble: BrainTrouble?
        /// The Mac's mic is on for push-to-talk.
        public var listening: Bool
        /// The face holds listening through the reply wait, after the mic stops.
        public var faceListening: Bool
        /// Why push-to-talk couldn't hear you, until the next try.
        public var micTrouble: String?
        /// Boop's XP and stage.
        public var growth: Growth?
        /// Each buddy, when there are several; empty for one, which the
        /// fields above are.
        public var buddies: [BuddyStatus] = []

        /// One of several buddies, as the popover lists it.
        public struct BuddyStatus: Sendable, Equatable {
            /// Where it sits.
            public var id: String
            public var name: String
            /// What its device shows, and its mood.
            public var snapshot: StateSnapshot
            public var connected: Bool
            public var device: DeviceInfo?
            /// Its own XP and stage.
            public var growth: Growth
        }

        public init(name: String, snapshot: StateSnapshot, sessions: [SessionSummary], connected: Bool,
                    device: DeviceInfo?, linkTrouble: String? = nil, deviceTrouble: String? = nil, personality: Personality,
                    brain: String, keyRead: Bool = true, brainTrouble: BrainTrouble? = nil, listening: Bool = false,
                    micTrouble: String? = nil, growth: Growth? = nil, faceListening: Bool? = nil) {
            self.name = name
            self.snapshot = snapshot
            self.sessions = sessions
            self.connected = connected
            self.device = device
            self.linkTrouble = linkTrouble
            self.deviceTrouble = deviceTrouble
            self.personality = personality
            self.brain = brain
            self.keyRead = keyRead
            self.brainTrouble = brainTrouble
            self.listening = listening
            self.faceListening = faceListening ?? listening
            self.micTrouble = micTrouble
            self.growth = growth
        }
    }

    func changed() {
        let now = options.clock()
        var status = Status(name: name, snapshot: latest ?? core.snapshot(at: now), sessions: rigs.flatMap { core($0).sessionList(at: now) },
                            connected: link.connected, device: link.hello.map(DeviceInfo.init), linkTrouble: linkTrouble,
                            deviceTrouble: link.trouble?.description, personality: personality, brain: harness.brain?.id ?? "none",
                            keyRead: jevKey != nil, brainTrouble: trouble, listening: core.listening != nil,
                            micTrouble: core.talk.trouble, growth: growth.growth, faceListening: core.showsListening(at: now))
        if pipeline.several {
            status.buddies = rigs.map { rig in
                Status.BuddyStatus(id: rig.buddy.id, name: rig.buddy.name, snapshot: rig.latest ?? core(rig).snapshot(at: now),
                                   connected: rig.link.connected, device: rig.link.hello.map(DeviceInfo.init), growth: rig.growth.growth)
            }
        }
        grew = false
        if let line = DebugLog.status(status, at: now, last: &lastStatus) { emit(line) }
        onChange?(status)
    }
}
