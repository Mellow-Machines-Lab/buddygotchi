import Foundation
import LinkKit

// What the menu bar shows, built after every change.
extension Runtime {
    /// What the menu bar shows.
    public struct Status: Sendable, Equatable {
        /// Boop's name, from `long-term.md`.
        public var name: String
        /// What the device shows, and Boop's mood.
        public var snapshot: StateSnapshot
        /// Every session, for the popover's list.
        public var sessions: [SessionSummary]
        public var connected: Bool
        /// What the device said of itself in its `hello`.
        public var device: DeviceInfo?
        /// Why the link can't look for the device (Bluetooth off): the
        /// transport's cause and words, for the popover.
        public var linkTrouble: TransportTrouble?
        /// Why the device connected gets no reactions: its firmware doesn't
        /// fit the app (linkkit/SPEC.md §6), in the link's words.
        public var deviceTrouble: String?
        /// That device's `hello.id`, when it gave one: the board its
        /// firmware update is for.
        public var misfit: String?
        /// The brain as it runs: `jev:jev-latest`, or `none` without a key.
        public var brain: String
        /// Jev's key has been read, whether there was one or not. Until
        /// then `brain` is `none` only because it isn't known yet.
        public var keyRead: Bool
        /// The brain failing, for the popover's notice.
        public var brainTrouble: BrainTrouble?
        /// The Mac's mic is on for push-to-talk.
        public var listening: Bool
        /// Why push-to-talk couldn't hear you, until the next try.
        public var micTrouble: String?
        /// Boop's XP and stage.
        public var growth: Growth?
        /// How many days since Boop hatched, and its memory's recent days,
        /// a line each, newest first (`memory.md`'s Recently).
        public var daysOld: Int?
        public var recently: [DayLine] = []
        /// The written memory's notes, for "What Boop remembers".
        public var notes: [WrittenMemory.Note] = []
        /// How much it says, chosen in Settings, and whether the pack
        /// offers a choice: none when its steering has no talk file.
        public var talk = Talk.default
        /// While Boop is hushed, when it may talk again, for the popover's
        /// countdown.
        public var hushedUntil: Date?
        /// Why Boop feels as it does: what moved its mood last, in words
        /// ("You came back after 26 hours away."). Nil when nothing in the
        /// log says.
        public var moodReason: Narration?
        /// The wish waiting, for the popover: "Boop wishes for a pet (40 min)."
        public var wishing: String?
        /// Why the board looks as it does: what Boop celebrates today, and
        /// what it wears or shows for each.
        public var dressing: [Narration.Dressing] = []

        /// A day's line, as the popover shows it.
        public struct DayLine: Sendable, Equatable, Identifiable {
            /// `2026-10-21`.
            public var day: String
            /// The day as a person says it: Yesterday, Tuesday, Oct 14.
            public var when: String
            /// What happened, without the weekday a line may start with,
            /// which `when` says.
            public var line: String
            public var id: String { day }

            /// `line`, about `day`, read on `today` (both `yyyy-MM-dd`).
            public init(day: String, line: String, today: String) {
                self.day = day
                when = LocalTime.spoken(day, today: today)
                let lead = LocalTime.weekday(of: day).map { $0 + ". " }
                self.line = lead.map { line.hasPrefix($0) ? String(line.dropFirst($0.count)) : line } ?? line
            }
        }
        /// The last run crashed or was killed, until the notice is closed.
        public var uncleanExit = false
        /// The one board Boop takes over Bluetooth, by its `hello.id`.
        public var board: String?
        /// Whether the board shows the work stream.
        public var workStream = true
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
        }

        public init(name: String, snapshot: StateSnapshot, sessions: [SessionSummary], connected: Bool,
                    device: DeviceInfo?, linkTrouble: TransportTrouble? = nil, deviceTrouble: String? = nil,
                    brain: String, keyRead: Bool = true, brainTrouble: BrainTrouble? = nil, listening: Bool = false,
                    micTrouble: String? = nil, growth: Growth? = nil) {
            self.name = name
            self.snapshot = snapshot
            self.sessions = sessions
            self.connected = connected
            self.device = device
            self.linkTrouble = linkTrouble
            self.deviceTrouble = deviceTrouble
            self.brain = brain
            self.keyRead = keyRead
            self.brainTrouble = brainTrouble
            self.listening = listening
            self.micTrouble = micTrouble
            self.growth = growth
        }
    }

    /// A board's firmware that doesn't fit, in a buyer's words: what's
    /// wrong, not how to flash it, which the popover's fix says.
    static func words(_ trouble: DeviceLink.Trouble) -> String {
        switch trouble {
        case .tooOld: "its firmware is older than this app's"
        case .tooNew: "its firmware is newer than this app: update the app"
        case .otherApp(let device, _): "its firmware is another app's (\(device.isEmpty ? "unnamed" : device))"
        }
    }

    func changed() {
        let now = options.clock()
        var status = Status(name: name, snapshot: latest ?? core.snapshot(at: now), sessions: rigs.flatMap { core($0).sessionList(at: now) },
                            connected: link.connected, device: link.hello.map(DeviceInfo.init), linkTrouble: linkTrouble,
                            deviceTrouble: link.trouble.map(Self.words), brain: harness.brain?.id ?? "none",
                            keyRead: jevKey != nil, brainTrouble: trouble, listening: core.listening != nil,
                            micTrouble: core.pushToTalk.trouble, growth: growth.growth)
        let wall = options.wallClock()
        status.daysOld = memory.longTerm.map { options.time.days(from: $0.hatched, to: wall) }
        let written = memory.written(), today = options.time.boopDay(wall)
        status.notes = written.notes
        status.recently = written.recently.map { Status.DayLine(day: $0.day, line: $0.text, today: today) }
        status.wishing = core.wish.map { "\(name) wishes for \($0.kind.words) (\(ContextSection.span($0.waitedMs)))." }
        status.moodReason = MoodOutput.reason(mood, harness.log.view(now: now), line: { [harness] in harness.line($0) })
        let config = core.config
        status.dressing = Narration.Dressing.now(when: status.snapshot.when,
                                       specialDays: Days.special(at: wall, hatched: config.hatched, name: name,
                                                                      stage: config.stageReached, time: options.time),
                                       asleep: status.snapshot.doing == "asleep", gel: status.device?.face != .pixel)
        if let words = growth.shrankWords(today: options.time.day(wall), name: name) {
            status.dressing.insert(Narration.Dressing(kind: .shrank, why: words, what: nil), at: 0)
        }
        status.talk = talk
        status.hushedUntil = core.hushed(at: now).map { Date(timeIntervalSince1970: Double(wall + $0.until - now) / 1000) }
        status.uncleanExit = uncleanExit
        status.board = settings.board
        status.workStream = settings.workStream
        status.misfit = link.misfit.flatMap { $0.id.isEmpty ? nil : $0.id }
        if pipeline.several {
            status.buddies = rigs.map { rig in
                Status.BuddyStatus(id: rig.buddy.id, name: rig.buddy.name, snapshot: rig.latest ?? core(rig).snapshot(at: now),
                                   connected: rig.link.connected, device: rig.link.hello.map(DeviceInfo.init))
            }
        }
        grew = false
        if let line = DebugLog.status(status, today: remembers?.today, at: now, last: &lastStatus) { emit(line) }
        onChange?(status)
    }
}
