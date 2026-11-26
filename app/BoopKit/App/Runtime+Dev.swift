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
                devIdleSet = true
                options.log("dev: idle \(devIdleMs) ms")
            }
            if let ms = (object["key_idle_ms"] as? NSNumber)?.int64Value {
                devKeyIdleMs = max(0, ms)
                options.log("dev: key idle \(ms) ms")
                handsTick()
            }
            if let signal = (object["signal"] as? String).flatMap(PresenceDetector.Signal.init(rawValue:)) {
                options.log("dev: presence \(signal.rawValue)")
                presenceSignal(signal)
            }
        case "along":
            // The rest of you at the Mac, headless only (`Along.Facts`):
            // each field a raw fact, the rules run on them as on the Mac's.
            guard options.along == nil else { return }
            alongLine(object)
        case "anchor":
            // Settings' "Show Boop where it sits" (`place`), or an anchor
            // set at once (`at`, with its `display`), or none (`clear`).
            if object["place"] as? Bool == true { showWhereBoopSits() }
            if let at = object["at"] as? [NSNumber], at.count == 2 {
                let display = rect(object["display"]) ?? devAlong.display ?? Self.devDisplay
                setAnchor(Anchor(x: at[0].doubleValue, y: at[1].doubleValue, display: display))
            }
            if object["clear"] as? Bool == true { setAnchor(nil) }
        case "report":
            saveReport { _ in }
        case "dream_now":
            dreamNow()
        case "dream_preview":
            previewDream()
        case "world":
            // The popover's world doors, headless: onboarding's screen shown,
            // the switch, the World tab, and a gesture for another buddy.
            if object["shown"] as? Bool == true { worldScreenShown() }
            if let on = object["on"] as? Bool { setWorld(on) }
            if let open = object["tab"] as? Bool { worldTab(open: open) }
            if let to = object["to"] as? String, let kind = (object["gesture"] as? String).flatMap(World.GestureKind.init(rawValue:)) {
                sendGesture(kind, to: to) { [log = options.log] ok in log("dev: the \(kind.rawValue) \(ok ? "went" : "didn't go")") }
            }
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

    /// A forced pass: the outputs keep their own rules. `by` is who the pass is by, in the
    /// transcript.
    func forcePass(_ choices: [String: String], by: String, who: String = "dev") {
        let ran = harness.force(choices, by: by)
        options.log("\(who): forced pass → " + Harness.OutputRecord.names(ran))
        changed()
    }

    /// The mood output's own change, which tells the device too.
    func forceMood(_ to: String, by: String, who: String = "dev") {
        let result = harness.force(rig.mood, by: by) { MoodOutput.change(rig.mood, to: to, log: harness.log.view(now: options.clock())) }
        options.log("\(who): mood \(to)" + (result.map { $0.ok ? "" : ": \($0.message)" } ?? ""))
        changed()
    }

    /// A tap on the device, without one.
    func tapped(who: String = "dev") {
        options.log("\(who): tap")
        if placing != nil { return placeHere(at: options.clock()) }
        run(pipeline.poke(at: options.clock()))
        changed()
    }

    /// BOOT pressed, as the board reports it (a `tap` from the button).
    func pressed(who: String = "dev") {
        options.log("\(who): press")
        run(pipeline.press(at: options.clock()))
        changed()
    }

    /// What you did to the device, as it reports it
    /// (`ev gesture`): `dismiss`, a finger held on the needs-you screen, names
    /// the request its last state showed, as the board does.
    func gestured(_ kind: String, who: String = "dev") {
        options.log("\(who): gesture \(kind)")
        if places(gesture: kind) { return placeHere(at: options.clock()) }
        run(pipeline.gesture(kind, request: rig.latest?.attn?.id, at: options.clock()))
        changed()
    }

    /// The question the buddy asked last answered, as its board would say
    /// it (`ev ask`): `pick` "a", "b", "touch" (its first answer) or
    /// "ignored". Nothing when it has asked nothing.
    func answered(_ pick: String, who: String = "dev") {
        options.log("\(who): answer \(pick)")
        guard let step = pipeline.answerLast(pick, at: options.clock()) else {
            options.log("\(who): nothing was asked")
            return
        }
        run(step)
        changed()
    }

    /// Dreams now, the dashboard's `d`: the dream, then its write
    /// (`Memory.dreamNow`).
    func dreamNow(who: String = "dev") {
        guard let remembers else { return options.log("\(who): no memory, so no dream") }
        options.log("\(who): dreaming now")
        remembers.dreamNow(at: pipeline.harness.clock.now())
        remembers.tick(wall: options.wallClock())
        changed()
    }

    /// What dreaming now would do, the dashboard's `D`, with nothing
    /// committed (`Memory.preview`): one `dream_preview` line in
    /// debug.jsonl, and nothing in the transcript.
    func previewDream(who: String = "dev") {
        guard let remembers else { return options.log("\(who): no memory, so no dream") }
        options.log("\(who): previewing a dream")
        let now = pipeline.harness.clock.now(), home = self.home
        Task { [weak self] in
            let p = await remembers.preview(at: now)
            home.async { self?.debugWriter?.line(DebugLog.dreamPreview(p, at: now)) }
        }
    }

    /// Who forces passes and outputs, for no event: the dashboard's.
    public static let forcedBy = "dashboard"
}

// The `{"dev":"along"}` line's facts.
extension Runtime {
    /// The display a dev line's pointer is on when it names none: a
    /// MacBook's, at the top left of the desktop.
    static let devDisplay = Anchor.Rect(x: 0, y: 0, width: 1512, height: 982)

    func rect(_ value: Any?) -> Anchor.Rect? {
        guard let r = value as? [NSNumber], r.count == 4 else { return nil }
        return Anchor.Rect(x: r[0].doubleValue, y: r[1].doubleValue, width: r[2].doubleValue, height: r[3].doubleValue)
    }

    /// `{"dev":"along",…}`: `scroll_idle_ms`, `scroll` (the way: "up" or
    /// "down"), `click_idle_ms`, `pointer`
    /// ([x, y]) and its `display` ([x, y, w, h]), `sound` (who plays it:
    /// "front", the frontmost app, "other", another, or "none"), `front` (a
    /// bundle id, or "" for none), and `camera` and `mic` (another app
    /// records: true or false). Each stays as set until the next says
    /// otherwise.
    func alongLine(_ object: [String: Any]) {
        var r = devAlong
        if let ms = (object["scroll_idle_ms"] as? NSNumber)?.int64Value { r.scrollIdleMs = max(0, ms) }
        if let way = object["scroll"] as? String { r.scrollDown = way == "down" }
        if let ms = (object["click_idle_ms"] as? NSNumber)?.int64Value { r.clickIdleMs = max(0, ms) }
        if let p = object["pointer"] as? [NSNumber], p.count == 2 {
            r.pointerX = p[0].doubleValue
            r.pointerY = p[1].doubleValue
            r.display = r.display ?? Self.devDisplay
        }
        if let display = rect(object["display"]) { r.display = display }
        if let who = object["sound"] as? String { (r.frontSound, r.otherSound) = (who == "front", who == "other") }
        if let front = object["front"] as? String { r.front = front.isEmpty ? nil : front }
        if let on = object["camera"] as? Bool { r.camera = on }
        if let on = object["mic"] as? Bool { r.otherInput = on }
        devAlong = r
        options.log("dev: along " + object.keys.filter { $0 != "dev" }.sorted().joined(separator: " "))
        handsTick()
    }
}
