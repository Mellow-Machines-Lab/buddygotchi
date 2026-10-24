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
        // With several buddies, which one a line is for: the first's by default.
        let buddy = object["buddy"] as? String
        switch object["dev"] as? String {
        case "advance":
            if let ms = (object["ms"] as? NSNumber)?.int64Value { advanceClock(ms) }
        case "answer":
            if let choices = object["answers"] as? [String: String] { forcePass(choices, by: Runtime.forcedBy, buddy: buddy) }
        case "mood":
            if let to = object["mood"] as? String { forceMood(to, by: Runtime.forcedBy, buddy: buddy) }
        case "said":
            // What push-to-talk heard, without a mic (VERIFICATION.md §2).
            guard let words = object["words"] as? String else { return }
            heard(words, by: (object["by"] as? String).flatMap(Core.Talker.init(rawValue:)) ?? .app)
        case "tap":
            tapped(buddy: buddy)
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

    /// A forced pass, for the buddy `buddy` (the first's by default): the
    /// outputs keep their own rules. `by` is who the pass is by, in the
    /// transcript.
    func forcePass(_ choices: [String: String], by: String, who: String = "dev", buddy: String? = nil) {
        let rig = rig(buddy)
        let ran = harness.force(choices, by: by, voice: rig.tag)
        options.log("\(who): forced pass\(Runtime.whose(rig)) → " + Harness.OutputRecord.names(ran))
        changed()
    }

    /// The mood output's own change, the buddy `buddy`'s, which tells its
    /// device too.
    func forceMood(_ to: String, by: String, who: String = "dev", buddy: String? = nil) {
        let rig = rig(buddy)
        let result = harness.force(rig.mood, by: by) { MoodOutput.change(rig.mood, to: to, log: harness.log.view(now: options.clock())) }
        options.log("\(who): mood\(Runtime.whose(rig)) \(to)" + (result.map { $0.ok ? "" : ": \($0.message)" } ?? ""))
        changed()
    }

    /// A tap on the device, the buddy `buddy`'s, without one.
    func tapped(who: String = "dev", buddy: String? = nil) {
        let rig = rig(buddy)
        options.log("\(who): tap\(Runtime.whose(rig))")
        run(pipeline.poke(at: options.clock(), buddy: rig.tag))
        changed()
    }

    /// BOOT pressed, as the board reports it (a `tap` from the button).
    func pressed(who: String = "dev", buddy: String? = nil) {
        let rig = rig(buddy)
        options.log("\(who): press\(Runtime.whose(rig))")
        run(pipeline.press(at: options.clock(), buddy: rig.tag))
        changed()
    }

    /// What you did to the device, the buddy `buddy`'s, as it reports it
    /// (`ev gesture`): `dismiss`, a finger held on the needs-you screen, names
    /// the request its last state showed, as the board does.
    func gestured(_ kind: String, who: String = "dev", buddy: String? = nil) {
        let rig = rig(buddy)
        options.log("\(who): gesture \(kind)\(Runtime.whose(rig))")
        run(pipeline.gesture(kind, request: rig.latest?.attn?.id, at: options.clock(), buddy: rig.tag))
        changed()
    }

    /// Who forces passes and outputs, for no event: the dashboard's.
    public static let forcedBy = "dashboard"
}
