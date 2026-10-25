import Foundation

/// The first launch's walkthrough, in acts: hello, what Boop does, a name
/// and a nature, the board, how to use it, the agents, a few small things,
/// and the finale. The app shows it once: until it's finished, there's no
/// menu-bar icon.
public enum Onboarding {
    public enum Act: String, CaseIterable, Codable, Sendable {
        case hello, whatIDo, makeMeYours, body, howTo, agents, smallThings, finale

        /// Its place, from 0.
        public var index: Int { Self.allCases.firstIndex(of: self)! }
        public var next: Act? { index + 1 < Self.allCases.count ? Self.allCases[index + 1] : nil }
        /// The act Back goes to, if any. Once Boop is named (makeMeYours
        /// saves its memory), the name is for keeps, so nothing goes back
        /// past the board.
        public var back: Act? {
            guard index > 0, self != .body else { return nil }
            return Self.allCases[index - 1]
        }
        /// The acts after naming, which need Boop's memory and its runtime.
        public var afterNaming: Bool { index > Act.makeMeYours.index }
    }

    /// Where a launch starts: from the top when Boop hasn't been named; at
    /// the act saved in `settings.json` (`AppSettings.onboarding`) when one
    /// is, after a quit partway; and nowhere (nil, onboarding is done) when
    /// Boop is named and none is saved, which includes every Boop named
    /// before onboarding existed. Before the name nothing is kept, so a quit
    /// there starts again.
    public static func resume(isSetUp: Bool, saved: Act?) -> Act? {
        guard isSetUp else { return .hello }
        guard let saved, saved.afterNaming else { return nil }
        return saved
    }

    /// What the walkthrough has heard and done so far, and the rules for
    /// what a tap on the board or an agent's hook does in each act. The
    /// window shows it; nothing here touches the board or the Mac.
    public struct Progress: Equatable, Sendable {
        /// Act 4's board.
        public enum Body: Equatable, Sendable {
            /// Plug me in, and why macOS will ask about Bluetooth.
            case intro
            /// "Look for me" was pressed: the runtime is looking.
            case looking
            /// The board was tapped while found: paired.
            case joined
            /// "I don't have my Boop yet", or past act 4 at launch. Nothing
            /// to show: Back into act 4 makes it `intro` again.
            case skipped
        }

        /// Act 5's lessons done on the board: the fourth, `amber`, is a tap
        /// on the practice request the board shows once the first three
        /// are done (`practiceDue`).
        public enum Lesson: Hashable, Sendable { case tap, button, talk, amber }

        /// What a tap on the board did.
        public enum Tap: Equatable, Sendable {
            /// It paired the board: Boop wakes up in it.
            case paired
            /// It did a lesson.
            case lesson(Lesson)
            case nothing
        }

        public private(set) var act: Act
        public var body: Body
        public var lessons: Set<Lesson> = []
        /// Act 6's hooks are installed.
        public var connected: Bool
        /// The agent whose first hook was heard in act 6.
        public var heard: String?

        /// At `act`, as a launch starts there: past the board, it's
        /// skipped (a quit forgets whether it was paired; the board is
        /// remembered anyway); past the agents, they're connected.
        public init(act: Act) {
            self.act = act
            body = act.index > Act.body.index ? .skipped : .intro
            connected = act.index > Act.agents.index
        }

        /// Moves to `act`. Back into the board's act after it was skipped,
        /// it starts again from "Plug me in", which has buttons to go on.
        public mutating func move(to act: Act) {
            self.act = act
            if act == .body, body == .skipped { body = .intro }
        }

        /// Whether act 5's practice request is due on the board: the
        /// first three lessons done, the amber one not yet.
        public var practiceDue: Bool {
            act == .howTo && lessons.isSuperset(of: [.tap, .button, .talk]) && !lessons.contains(.amber)
        }

        /// A tap on the board: its screen, or its button when `button`. In
        /// act 4, while looking and with a board found, either pairs it,
        /// and counts as its lesson; in act 5 each does its own lesson,
        /// once, and once the first three are done either answers the
        /// practice request, the amber lesson; anywhere else it's only a
        /// poke.
        public mutating func tapped(boardFound: Bool, button: Bool) -> Tap {
            let lesson: Lesson = button ? .button : .tap
            switch act {
            case .body where body == .looking && boardFound:
                body = .joined
                lessons.insert(lesson)
                return .paired
            case .howTo where practiceDue:
                lessons.insert(.amber)
                return .lesson(.amber)
            case .howTo where !lessons.contains(lesson):
                lessons.insert(lesson)
                return .lesson(lesson)
            default:
                return .nothing
            }
        }

        /// Push-to-talk ended, and the Mac heard words or nothing. In act 5,
        /// words do "Hold my button and talk", once; nothing heard leaves it
        /// to try again. True when it's done now.
        public mutating func talked(heardWords: Bool) -> Bool {
            guard act == .howTo, heardWords, !lessons.contains(.talk) else { return false }
            lessons.insert(.talk)
            return true
        }

        /// An agent's hook. Only in act 6, once connected, and only the
        /// first: true when it's the hello to celebrate.
        public mutating func heard(_ agent: String) -> Bool {
            guard act == .agents, connected, heard == nil else { return false }
            heard = agent
            return true
        }
    }

    /// Saves where onboarding stands (`AppSettings.onboarding`), or that
    /// it's done (nil), straight into `stateDir`'s settings, whether the
    /// runtime runs or not (`AppSettings.update`), so a quit comes back to
    /// the act, and a finish stays finished.
    public static func save(_ act: Act?, stateDir: URL) throws {
        try AppSettings.update(in: stateDir) { $0.onboarding = act }
    }
}
