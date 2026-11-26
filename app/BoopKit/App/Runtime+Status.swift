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
        /// The brain as it runs: `rules`, Jev's id (`jev:jev-latest`) once a
        /// key gives it the rules' seats, or `none` with no brain at all.
        public var brain: String
        /// Jev failing, for the popover's notice: only with a key.
        public var brainTrouble: BrainTrouble?
        /// The Mac's mic is on for push-to-talk.
        public var listening: Bool
        /// Why push-to-talk couldn't hear you, until the next try.
        public var micTrouble: String?
        /// Boop's XP, level and today's ring.
        public var growth: Growth?
        /// Today's XP by what earned it.
        public var todayBy: [Growth.Source: GrowthStore.Earned] = [:]
        /// The days in a row with a full ring, as they stand today.
        public var daysInARow = 0
        /// The last days' rings, oldest first, today's last: the Boop tab's week.
        public var week: [DayRing] = []
        /// The world of buddies; nil with no world server (tests).
        public var world: WorldStatus?
        /// How many days since Boop hatched, and its memory's recent days,
        /// a line each, newest first (`memory.md`'s Recently).
        public var daysOld: Int?
        public var recently: [DayLine] = []
        /// The written memory's notes, for "What Boop remembers".
        public var notes: [WrittenMemory.Note] = []
        /// How much it says, chosen in Settings, and whether the pack
        /// offers a choice: none when its steering has no talk file.
        public var talk = Talk.default
        /// While Boop is quiet for a while, when that ends, for the
        /// popover's countdown.
        public var quietUntil: Date?
        /// Why Boop feels as it does: what moved its mood last, in words
        /// ("You came back after 26 hours away."). Nil when nothing in the
        /// log says.
        public var moodReason: Narration?
        /// Why it's doing what it's doing: "Nothing's happened for an hour,
        /// so Boop dozed off.", "claude is running the tests on api."
        public var doingReason: Narration?
        /// The wish waiting, for the popover: "Boop wishes for a pet (40 min)."
        public var wishing: String?
        /// What Boop celebrates today.
        public var celebrating: [Narration.Celebrating] = []
        /// The latest picture an agent showed, for the popover to hold up.
        public var show: Core.Shown?

        /// A day's line, as the popover shows it.
        /// One day's ring: its XP, whether it's today, and its short name,
        /// `Today` or `Mon`.
        public struct DayRing: Sendable, Equatable, Identifiable {
            public var day: String
            public var xp: Int
            public var isToday: Bool
            public var name: String
            public var id: String { day }

            public init(day: String, xp: Int, today: String) {
                self.day = day
                self.xp = xp
                isToday = day == today
                name = isToday ? "Today" : String((LocalTime.weekday(of: day) ?? "").prefix(3))
            }
        }

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
        /// Whether Boop notices what you do at the Mac; whether it knows
        /// where it sits (`Anchor`), and the side the Mac is on from it; and
        /// whether it waits for the tap that shows it.
        public var noticesYou = true
        public var anchored = false
        public var macSide: Anchor.Side?
        public var placing = false
        /// The display Boop was shown it sits by is gone or moved: it wants
        /// showing again.
        public var anchorGone = false
        /// Whether Boop may swear (`AppSettings.swearing`).
        public var swearing = false
        /// Whether your own agent helps Boop think (`AppSettings.agentsThink`).
        public var agentsThink = true
        /// When Boop may next be renamed, or nil for now
        /// (`BuddyName.nextRename`).
        public var nextRename: Date?

        public init(name: String, snapshot: StateSnapshot, sessions: [SessionSummary], connected: Bool,
                    device: DeviceInfo?, linkTrouble: TransportTrouble? = nil, deviceTrouble: String? = nil,
                    brain: String, brainTrouble: BrainTrouble? = nil, listening: Bool = false,
                    micTrouble: String? = nil, growth: Growth? = nil) {
            self.name = name
            self.snapshot = snapshot
            self.sessions = sessions
            self.connected = connected
            self.device = device
            self.linkTrouble = linkTrouble
            self.deviceTrouble = deviceTrouble
            self.brain = brain
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

    /// The most often a status is built: every board line and many hooks
    /// change something it shows, nearly always while nothing shows it.
    static let statusEveryMs = 100

    /// Something the status shows changed: one is built within
    /// `statusEveryMs`, with every change until then.
    func changed() {
        guard !statusDue else { return }
        statusDue = true
        home.asyncAfter(deadline: .now() + .milliseconds(Self.statusEveryMs)) { [weak self] in
            if self?.statusDue == true { self?.status() }
        }
    }

    /// The status now, to the menu bar and the popover.
    func status() {
        statusDue = false
        let now = options.clock()
        var status = Status(name: name, snapshot: latest ?? core.snapshot(at: now), sessions: core.sessionList(at: now),
                            connected: link.connected, device: link.hello.map(DeviceInfo.init), linkTrouble: linkTrouble,
                            deviceTrouble: link.trouble.map(Self.words), brain: harness.brain?.id ?? "none",
                            brainTrouble: trouble, listening: core.listening != nil,
                            micTrouble: core.pushToTalk.trouble, growth: growthNow)
        let wall = options.wallClock()
        status.daysOld = memory.longTerm.map { options.time.days(from: $0.hatched, to: wall) }
        let written = memory.written(), today = options.time.boopDay(wall)
        status.todayBy = growth.todayBy(on: today)
        status.daysInARow = growth.daysInARow(on: today)
        status.week = growth.week(to: today).map { Status.DayRing(day: $0.day, xp: $0.xp, today: today) }
        status.world = worldStatus()
        status.notes = written.notes
        status.recently = written.recently.map { Status.DayLine(day: $0.day, line: $0.text, today: today) }
        status.wishing = core.wish.map { "\(name) wishes for \($0.kind.words) (\(ContextSection.span($0.waitedMs)))." }
        status.moodReason = MoodOutput.reason(mood, harness.log.view(now: now), line: { [harness] in harness.line($0) })
        status.doingReason = core.doingReason(at: now)
        let config = core.config
        status.show = core.shown(at: now)
        status.celebrating = Narration.Celebrating.now(specialDays: Days.special(at: wall, hatched: config.hatched, name: name, time: options.time))
        status.talk = talk
        // To the second: the wall and the monotonic clock are read apart, and a
        // millisecond's wobble would make every status a new one.
        status.quietUntil = core.quietUntil(at: now).map { Date(timeIntervalSince1970: (Double(wall + $0 - now) / 1000).rounded()) }
        status.uncleanExit = uncleanExit
        status.board = settings.board
        status.noticesYou = settings.noticesYou
        status.anchored = settings.anchor != nil
        status.macSide = anchor?.side
        status.placing = placing != nil
        status.anchorGone = anchorGone
        status.swearing = options.swearing ?? settings.swearing
        status.agentsThink = settings.agentsThink
        status.nextRename = BuddyName.nextRename(after: settings.renamed, at: wall).map { Date(timeIntervalSince1970: Double($0) / 1000) }
        status.misfit = link.misfit.flatMap { $0.id.isEmpty ? nil : $0.id }
        grew = false
        if let line = DebugLog.status(status, at: now, last: &lastStatus) { emit(line) }
        onChange?(status)
    }
}
