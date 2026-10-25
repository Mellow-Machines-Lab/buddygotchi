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
        /// Why the link can't look for the device (Bluetooth off): the
        /// transport's cause and words, for the popover.
        public var linkTrouble: TransportTrouble?
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
        /// Why push-to-talk couldn't hear you, until the next try.
        public var micTrouble: String?
        /// Boop's XP and stage.
        public var growth: Growth?
        /// How many days since Boop hatched, and its diary's last week,
        /// newest first.
        public var daysOld: Int?
        public var diary: [DiaryLine] = []
        /// Sweet or cheeky, chosen at setup for keeps.
        public var nature: LongTerm.Nature?

        /// A day's line, as the popover shows it.
        public struct DiaryLine: Sendable, Equatable, Identifiable {
            /// `2026-10-21`.
            public var day: String
            /// The day as a person says it: Yesterday, Tuesday, Oct 14.
            public var when: String
            /// What Boop wrote, without the weekday its lines start with,
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
                    device: DeviceInfo?, linkTrouble: TransportTrouble? = nil, deviceTrouble: String? = nil, personality: Personality,
                    brain: String, keyRead: Bool = true, brainTrouble: BrainTrouble? = nil, listening: Bool = false,
                    micTrouble: String? = nil, growth: Growth? = nil) {
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
                            micTrouble: core.talk.trouble, growth: growth.growth)
        let wall = options.wallClock()
        status.daysOld = memory.longTerm.map { options.time.days(from: $0.hatched, to: wall) }
        status.diary = diary(today: options.time.day(wall))
        status.nature = memory.longTerm?.nature
        status.uncleanExit = uncleanExit
        status.board = settings.board
        if pipeline.several {
            status.buddies = rigs.map { rig in
                Status.BuddyStatus(id: rig.buddy.id, name: rig.buddy.name, snapshot: rig.latest ?? core(rig).snapshot(at: now),
                                   connected: rig.link.connected, device: rig.link.hello.map(DeviceInfo.init))
            }
        }
        grew = false
        if let line = DebugLog.status(status, at: now, last: &lastStatus) { emit(line) }
        onChange?(status)
    }

    /// The diary's last week, newest first, as it reads on `today`: built
    /// again only once the diary or the day changes.
    func diary(today: String) -> [Status.DiaryLine] {
        let week = memory.diary(last: 7)
        if let shown = shownDiary, shown.today == today, shown.week.elementsEqual(week, by: { $0.day == $1.day && $0.line == $1.line }) {
            return shown.lines
        }
        let lines = week.map { Status.DiaryLine(day: $0.day, line: $0.line, today: today) }
        shownDiary = (week, today, lines)
        return lines
    }
}
