import Foundation
import LinkKit

/// A demo as the device lived it: every line the app sent the device, with
/// when, and what was happening, for whoever watches it played back. The
/// simulator's page plays one into the firmware itself
/// (simulator/README.md), so a recording shows what a board shows, with no
/// app behind it.
public struct DemoRecording: Codable, Sendable, Equatable {
    public struct Event: Codable, Sendable, Equatable {
        /// Seconds since the demo started.
        public var at: Double
        /// A line the app sent the device, as it was sent.
        public var line: String?
        /// For a line that says something: the words, as the bubble shows them.
        public var says: String?
        /// What happened then (`DemoScript.Cause`).
        public var cause: DemoScript.Cause?
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

    private var now: Double { Double(clock() - lock.withLock { started }) / 1000 }

    /// The demo starts now. What the device was last told of how things
    /// stand is where the recording starts, as a board that just connected
    /// is told; anything else from before is left out.
    public func begin() {
        lock.withLock {
            started = clock()
            let state = events.last { $0.line?.hasPrefix(#"{"t":"state""#) == true }
            events = state.map { [DemoRecording.Event(at: 0, line: $0.line)] } ?? []
            takes = []
        }
    }

    /// A line the app sent the device.
    public func sent(_ line: String) {
        var event = DemoRecording.Event(at: now, line: line)
        // A reaction that says something names its take: `"say":{"take":"…"}`.
        if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
           let args = object["args"] as? [String: Any], let take = (args["say"] as? [String: Any])?["take"] as? String {
            event.says = texts[take]
            lock.withLock { if !takes.contains(take) { takes.append(take) } }
        }
        lock.withLock { events.append(event) }
    }

    public func happened(_ cause: DemoScript.Cause) {
        let event = DemoRecording.Event(at: now, cause: cause)
        lock.withLock { events.append(event) }
    }

    public func recording(character: String, name: String, face: String) -> DemoRecording {
        let length = now
        return lock.withLock {
            DemoRecording(character: character, name: name, face: face, length: (length * 100).rounded() / 100, takes: takes,
                          events: events.map { e in var e = e; e.at = (e.at * 1000).rounded() / 1000; return e })
        }
    }
}
