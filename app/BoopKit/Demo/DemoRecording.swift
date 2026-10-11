import Foundation

/// A demo as the device lived it: every line the app sent the device, with
/// when, and what was happening, for whoever watches it played back. The
/// simulator's page plays one into the firmware itself
/// (simulator/README.md), so a recording shows what a board shows, with no
/// app behind it, and needs to know nothing of what the lines mean.
public struct DemoRecording: Codable, Sendable, Equatable {
    public struct Event: Codable, Sendable, Equatable {
        /// Seconds since the demo started.
        public var at: Double
        /// A line the app sent the device, as it was sent.
        public var line: String?
        /// What the creature does at that line, in words, when it's something to see.
        public var effect: String?
        /// What happened then (`DemoScript.Cause`).
        public var cause: DemoScript.Cause?
        /// What to do to the device itself then: `tap`, a finger on its screen.
        public var input: String?
    }

    public static let version = 1
    public var version = DemoRecording.version
    /// The character pack it was played with, and what the creature is called.
    public var character: String
    public var name: String
    /// The device's face it was recorded on: `pixel` or `gel`.
    public var face: String
    /// How long it runs, in seconds.
    public var length: Double
    /// The takes it says, for a voice pack with only those.
    public var takes: [String]
    public var events: [Event]
}

/// Makes a `DemoRecording` as a demo plays.
public final class DemoRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DemoRecording.Event] = []
    private var takes: [String] = []
    private var started: Int64
    /// How things last stood, to say what changed.
    private var mood = "", needsYou = false
    private var name = ""
    private let clock: @Sendable () -> Int64
    private let texts: [String: String]

    /// `clock` is a steady one, in ms, that nothing moves: a demo's
    /// `advance` jumps the runtime's, and a recording plays in real time.
    public init(clock: @escaping @Sendable () -> Int64 = { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) },
                takes: [Take] = Take.all) {
        self.clock = clock
        started = clock()
        texts = Dictionary(takes.map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
    }

    /// The demo starts now, for the creature called `name`. What the device
    /// was last told of how things stand is where the recording starts, as
    /// a board that just connected is told; anything else from before is
    /// left out.
    public func begin(name: String) {
        lock.withLock {
            self.name = name
            started = clock()
            let state = events.last { $0.line?.hasPrefix(#"{"t":"state""#) == true }
            events = state.map { [DemoRecording.Event(at: 0, line: $0.line)] } ?? []
            takes = []
        }
    }

    /// A line the app sent the device.
    public func sent(_ line: String) {
        let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
        lock.withLock { events.append(.init(at: now, line: line, effect: effect(of: message))) }
    }

    /// A beat of the demo: what it was, and what it does to the device.
    public func happened(_ cause: DemoScript.Cause?, input: String? = nil) {
        guard cause != nil || input != nil else { return }
        lock.withLock { events.append(.init(at: now, cause: cause, input: input)) }
    }

    public func recording(character: String, face: String) -> DemoRecording {
        lock.withLock {
            DemoRecording(character: character, name: name, face: face, length: (now * 100).rounded() / 100, takes: takes,
                          events: events.map { e in var e = e; e.at = (e.at * 1000).rounded() / 1000; return e })
        }
    }

    // Under the lock.
    private var now: Double { Double(clock() - started) / 1000 }

    /// What the creature does at a line, in words: a reaction's face and
    /// what it says, a finish, and the looks that mean something changed.
    private func effect(of message: [String: Any]) -> String? {
        let args = message["args"] as? [String: Any] ?? [:]
        switch message["t"] as? String {
        case "state":
            let (was, before) = (needsYou, mood)
            needsYou = message["attn"] != nil
            mood = message["mood"] as? String ?? ""
            if needsYou, !was { return "\(name) shows that it needs you" }
            return !before.isEmpty && !mood.isEmpty && mood != before ? "\(name)'s mood is now \(mood)" : nil
        case "do":
            // A line names its take, and the one after it: `"say":{"take":"…","then":"…"}`.
            let say = args["say"] as? [String: Any] ?? [:]
            let said = ["take", "then"].compactMap { say[$0] as? String }
            for take in said where !takes.contains(take) { takes.append(take) }
            let words = said.compactMap { texts[$0] }.joined(separator: " ")
            let says = words.isEmpty ? "" : " and says “\(words)”"
            switch message["name"] as? String {
            case DeviceMoment.react:
                guard let face = args["mood"] as? String else { return "\(name) reacts\(says)" }
                return "\(name) makes \("aeiou".contains(face.prefix(1)) ? "an" : "a") \(face) face\(says)"
            case "task_complete": return "\(name) \(args["outcome"] as? String == "failure" ? "slumps" : "celebrates")\(says)"
            case "reply_ready": return "\(name) perks up\(says)"
            case "error": return "\(name) winces"
            case BoopDevice.listening: return "\(name) listens"
            default: return nil
            }
        default:
            return nil
        }
    }
}
