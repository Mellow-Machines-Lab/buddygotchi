import Foundation
import MellowHarness

// The hush: you told Boop to be quiet, and for a while it says nothing.
// Its faces, moves and signs go on; only what it says stops, which
// `ReactOutput` holds to. The core keeps when it ends, records it starting
// and ending in the transcript, and reads it back on launch.
extension Core {
    /// While Boop is hushed: who hushed it, and until when.
    public struct Hush: Equatable, Sendable {
        public var by: By
        public var until: Int64
    }

    /// Who hushed Boop, or ended a hush: the app's button, what you said
    /// (the brain's `hush` or `unhush` reply), or the time running out.
    public enum By: String, Sendable { case app, talk, timer }

    /// The app's hush, and one said to Boop by the reply's intensity, small
    /// to huge: 15 minutes, 30, an hour, two hours.
    public static let hushMs: Int64 = 30 * 60_000
    public static let hushMsBySize: [Int64] = [15, 30, 60, 120].map { $0 * 60_000 }

    /// Boop's hush at `now`, or nil when it may talk.
    public func hushed(at now: Int64) -> Hush? {
        hush.flatMap { now < $0.until ? $0 : nil }
    }

    /// Hushes Boop for `ms` from `now`, a hush going on included,
    /// recorded as `hush_start`.
    @discardableResult
    public func hush(forMs ms: Int64, by: By, at now: Int64) -> [CoreEffect] {
        hushInput(now) { fx in
            hush = Hush(by: by, until: now + ms)
            fx.append(.record(Event(at: now, source: .boop, type: .hush, phase: .start, specificType: by.rawValue,
                                    data: ["until": .int(now + ms), "minutes": .int(ms / 60_000)])))
        }
    }

    /// Lets Boop talk again before its hush runs out, recorded as
    /// `hush_end`; nothing when it isn't hushed.
    @discardableResult
    public func unhush(by: By, at now: Int64) -> [CoreEffect] {
        hushInput(now) { fx in endHush(by, now, &fx) }
    }

    func endHush(_ why: By, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard hushed(at: now) != nil else { return }
        hush = nil
        fx.append(.record(Event(at: now, source: .boop, type: .hush, phase: .end, specificType: why.rawValue)))
    }

    /// A hush whose time ran out ends, recorded as the timer's, at the
    /// time it ran out.
    func expireHush(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard let h = hush, now >= h.until else { return }
        hush = nil
        fx.append(.record(Event(at: h.until, source: .boop, type: .hush, phase: .end, specificType: By.timer.rawValue)))
    }

    /// A hush's start or end read back from the transcript: what a launch
    /// keeps.
    func replayHush(_ e: Event) {
        if e.phase == .start, let by = By(rawValue: e.specificType), let until = e["until"]?.int {
            hush = Hush(by: by, until: until)
        } else if e.phase == .end {
            hush = nil
        }
    }

    private func hushInput(_ now: Int64, _ body: (inout [CoreEffect]) -> Void) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        expireHush(now, &fx)
        body(&fx)
        publish(now, &fx)
        return fx
    }
}
