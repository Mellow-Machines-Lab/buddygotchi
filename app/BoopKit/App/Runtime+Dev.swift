import Foundation
import MellowHarness

// The `{"dev":…}` lines on the hook socket, and the doors they share
// with a demo's beats. On `home`.
extension Runtime {
    /// A `{"dev":…}` line from the socket (VERIFICATION.md §2):
    /// only with `devLines`. Nothing replies; what it did shows in
    /// `debug.jsonl`.
    func dev(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        switch object["dev"] as? String {
        case "advance":
            if let ms = (object["ms"] as? NSNumber)?.int64Value { advanceClock(ms) }
        case "answer":
            if let choices = object["answers"] as? [String: String] { forcePass(choices, by: Runtime.forcedBy) }
        case "mood":
            if let to = object["mood"] as? String { forceMood(to, by: Runtime.forcedBy) }
        case "said":
            // What push-to-talk heard, without a mic (VERIFICATION.md §2).
            guard let words = object["words"] as? String else { return }
            heard(words, by: (object["by"] as? String).flatMap(Core.Talker.init(rawValue:)) ?? .app)
        case "tap":
            tapped()
        case "listen":
            if let on = object["on"] as? Bool { listen(on) }
        case "presence":
            // The Mac's signals and idle time, headless only: the app
            // reads the Mac's own.
            guard options.idleMs == nil else { return }
            if let ms = (object["idle_ms"] as? NSNumber)?.int64Value {
                devIdleMs = max(0, ms)
                options.log("dev: idle \(devIdleMs) ms")
            }
            if let signal = (object["signal"] as? String).flatMap(PresenceDetector.Signal.init(rawValue:)) {
                options.log("dev: presence \(signal.rawValue)")
                presenceSignal(signal)
            }
        case "report":
            saveReport { _ in }
        default:
            break  // a dev line it doesn't know
        }
    }

    // What the socket's dev lines do, and a demo's beats (`play`). `who`
    // is which, for the log: `dev`, or `demo`.

    /// Moves the clock on, where it can be moved (headless).
    func advanceClock(_ ms: Int64, who: String = "dev") {
        guard ms > 0, let advance = options.advance else { return }
        advance(ms)
        options.log("\(who): clock advanced \(ms) ms")
        tick()
    }

    /// A forced pass: the outputs keep their own rules. `by` is who the
    /// pass is by, in the transcript.
    func forcePass(_ choices: [String: String], by: String, who: String = "dev") {
        options.log("\(who): forced pass → " + Harness.OutputRecord.names(harness.force(choices, by: by)))
        changed()
    }

    /// The mood output's own change, which tells the device too.
    func forceMood(_ to: String, by: String, who: String = "dev") {
        let result = harness.force(mood, by: by) {
            MoodOutput.change(mood, to: to, log: harness.log.view(now: options.clock()))
        }
        options.log("\(who): mood \(to)" + (result.map { $0.ok ? "" : ": \($0.message)" } ?? ""))
        changed()
    }

    /// A tap on the device, without one.
    func tapped(who: String = "dev") {
        options.log("\(who): tap")
        run(pipeline.poke(at: options.clock()))
        changed()
    }

    /// Who forces passes and outputs, for no event: the dashboard's.
    public static let forcedBy = "dashboard"
}
