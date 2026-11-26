import Foundation

/// Where Boop sits beside your screen: the spot on a display nearest it,
/// which you show it once in Settings ("Show Boop where it sits") by
/// pointing there and tapping Boop. In the Mac's global display
/// coordinates, points, y down from the top of the main display, as
/// CoreGraphics gives them, with the display the spot is on.
///
/// From it the Mac knows the side of Boop the screen is on, where Boop
/// turns when something needs you (`side`), and the way from Boop to your
/// pointer (`pointer(at:)`).
public struct Anchor: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    /// The display it's on: its top-left corner and size.
    public var display: Rect

    public struct Rect: Codable, Equatable, Sendable {
        public var x: Double, y: Double, width: Double, height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    public init(x: Double, y: Double, display: Rect) {
        self.x = x
        self.y = y
        self.display = display
    }

    /// Where the screen is from Boop, as you look at Boop: to its left, to
    /// its right, or up (Boop sits under or in front of it).
    public enum Side: String, Sendable {
        case left, right, up

        /// The board's tag: `macleft`, `macright` or `macup`.
        public var tag: String { "mac" + rawValue }
    }

    /// Where the screen is from Boop, from how far across its display the
    /// anchor is: in its left third, Boop sits on the screen's left, so the
    /// screen is on Boop's right; in its right third, on Boop's left; in
    /// the middle third, Boop sits under the screen, which is up.
    public var side: Side? {
        guard display.width > 0 else { return nil }
        let across = (x - display.x) / display.width
        return across < Self.sideThird ? .right : across > 1 - Self.sideThird ? .left : .up
    }
    public static let sideThird = 1.0 / 3

    /// Where Boop itself is taken to be: this far out from the display's
    /// edge nearest the anchor, so the way to a pointer at the anchor
    /// points into the screen, and one far up the screen is mostly up.
    public static let standOffPt = 120.0
    /// The pointer within this of the anchor is at the edge nearest Boop:
    /// it looks right at it and leans in a little.
    public static let nearPt = 100.0
    /// How far away the pointer is when the eyes are half way out: past
    /// it they go on further, more and more slowly, to `Pointer.reach`.
    public static let kneePt = 400.0

    /// Boop, `standOffPt` out from the edge of the display nearest the anchor.
    var boop: (x: Double, y: Double) {
        let d = display
        let edges = [(x - d.x, -1.0, 0.0), (d.x + d.width - x, 1.0, 0.0), (y - d.y, 0.0, -1.0), (d.y + d.height - y, 0.0, 1.0)]
        let nearest = edges.min { $0.0 < $1.0 }!
        return (x + nearest.1 * Self.standOffPt, y + nearest.2 * Self.standOffPt)
    }

    /// The way from Boop to the pointer at (`px`, `py`), as you see the
    /// board beside the screen: to your left of Boop is left on the board,
    /// above it is up. Its size grows with the distance and levels off at
    /// `Pointer.reach`.
    public func pointer(at px: Double, _ py: Double) -> Pointer {
        let b = boop
        let dx = px - b.x, dy = py - b.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let near = ((px - x) * (px - x) + (py - y) * (py - y)).squareRoot() < Self.nearPt
        guard distance > 0 else { return Pointer(x: 0, y: 0, near: near) }
        let size = Double(Pointer.reach) * distance / (distance + Self.kneePt)
        func step(_ v: Double) -> Int { max(-Pointer.reach, min(Pointer.reach, Int((v / distance * size).rounded()))) }
        return Pointer(x: step(dx), y: step(dy), near: near)
    }
}

/// The way from Boop to your pointer, for its eyes to follow (`Anchor`):
/// each of `x` (right) and `y` (down) in -`reach`…`reach`, and whether the
/// pointer is at the edge of the screen nearest Boop. The wire's `ptr`.
public struct Pointer: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var near: Bool

    public static let reach = 10

    public init(x: Int, y: Int, near: Bool = false) {
        self.x = x
        self.y = y
        self.near = near
    }
}

/// What Boop notices of you at the Mac, besides your hands' typing and
/// reading (`Hands`): which way you scroll, typing fast, music playing, on
/// a call, and where your pointer is. Each is a plain fact read from the
/// Mac's state, never content: key timing from idle times, never keys;
/// only the sign of a scroll, never how far or where; whether an app plays
/// or records sound and whether a camera runs, never what it plays; the
/// pointer's place. They go to the board as tags (`Tags.along`) and the
/// pointer as `state`'s `ptr`, and the board decides what the body does
/// with them. No event, nothing in the transcript, nothing the brain, the
/// world or the daily counts read.
///
/// One of these is fed the facts every hands tick (`Runtime.handsTick`),
/// at any pace: every rule here is timed by the clock, not by readings.
public struct Along: Sendable {
    /// The Mac's raw facts at one instant. Nil for a reader there isn't
    /// (headless, before a dev line says one).
    public struct Facts: Equatable, Sendable {
        public var keyIdleMs: Int64?
        public var idleMs: Int64 = 0
        public var scrollIdleMs: Int64?
        /// Which way the last scroll went: toward the end of the page
        /// (down) or the top. Nil when not known.
        public var scrollDown: Bool?
        public var clickIdleMs: Int64?
        /// The pointer, in the anchor's coordinates (`Anchor`).
        public var pointerX: Double?
        public var pointerY: Double?
        /// The display the pointer is on, for a new anchor.
        public var display: Anchor.Rect?
        /// An app plays sound, any app but Boop itself.
        public var sound = false
        /// A camera runs, for any app.
        public var camera = false
        /// Another app records sound: any input device, never Boop's own
        /// push-to-talk.
        public var otherInput = false

        public init() {}
    }

    /// What's true now.
    public struct Now: Equatable, Sendable {
        public var hands: Hands?
        /// While you scroll, which way, when the Mac knows.
        public var scroll: Scroll?
        public var fast = false
        /// Music plays: any sound, held `soundOnMs`.
        public var music = false
        public var onCall = false
        /// You're speaking: another app records with no camera running
        /// (dictation, a voice prompt). Boop leans in and nods along.
        public var speaking = false
        public var pointer: Pointer?

        public init() {}

        /// The board's tags for them: your hands', then `Tags.along`'s.
        public var tags: [String] {
            var on: [String] = hands.map { [$0.rawValue] } ?? []
            if let scroll { on.append(scroll.rawValue) }
            if fast { on.append("typingfast") }
            if music { on.append("music") }
            if onCall { on.append("oncall") }
            if speaking { on.append("speaking") }
            return on
        }

        /// The same, but where the pointer is.
        var placeless: Now {
            var n = self
            n.pointer = nil
            return n
        }
    }

    /// Which way you scroll: the board looks straight that way.
    public enum Scroll: String, Sendable {
        case up = "scrollup", down = "scrolldown"
    }

    /// Typing fast: keys in at least `fastSlots` of the last `windowSlots`
    /// quarter seconds. A steady typist at 60 words a minute or more (5
    /// keys a second) leaves a key in nearly every quarter second; at 30
    /// or with pauses to think (2 to 3 a second), a third or more of them
    /// pass without one. Three in four is between the two. Once fast, it
    /// stays fast until keys come in only `slowSlots` of them or fewer, or
    /// for `slowMs` below `fastSlots`, so a flicker at the edge isn't seen.
    public static let slotMs: Int64 = 250
    public static let windowSlots = 8
    public static let fastSlots = 6
    public static let slowSlots = 3
    public static let slowMs: Int64 = 1000

    /// Sound is music once it's run this long, whatever plays it: a music
    /// app, a browser's tab in front or not, a video. An app keeps its
    /// sound output running for seconds after a sound effect of one second,
    /// a system sound or an alert, so a short wait lets those through. It
    /// stops once it's been off this long, so a gap between tracks, an ad's
    /// or the next video's loading doesn't stop it.
    public static let soundOnMs: Int64 = 10_000
    public static let soundOffMs: Int64 = 8000

    /// A call starts once a camera has run this long, and ends once it has
    /// been off this long.
    public static let callOnMs: Int64 = 5000
    public static let callOffMs: Int64 = 5000
    /// Speaking starts once another app has recorded, with no camera, this
    /// long, and ends once it has stopped this long: soon, as dictation is
    /// short.
    public static let speakOnMs: Int64 = 600
    public static let speakOffMs: Int64 = 1500

    /// The pointer counts as moving for this long after it last moved.
    public static let pointerStillMs: Int64 = 3000
    /// It's moved when it's gone at least this far, in points.
    public static let movedPt = 2.0

    /// A value that changes once the facts have said another for long
    /// enough: `onMs` to leave `rest`, `offMs` to come back to it, and a
    /// change between two others after `onMs` too.
    struct Held<Value: Equatable & Sendable>: Sendable {
        var value: Value
        let rest: Value
        var next: Value?
        var since: Int64 = 0

        init(_ rest: Value) {
            value = rest
            self.rest = rest
        }

        mutating func update(_ raw: Value, at now: Int64, onMs: Int64, offMs: Int64) -> Value {
            guard raw != value else {
                next = nil
                return value
            }
            if next != raw { next = raw; since = now }
            if now - since >= (raw == rest ? offMs : onMs) { value = raw; next = nil }
            return value
        }
    }

    var keySlots: [Int64] = []
    var fast = false
    var slowSince: Int64?
    var sound = Held(false), call = Held(false), speech = Held(false)
    var pointerAt: (x: Double, y: Double)?
    var movedAt: Int64?

    public init() {}

    /// What's true at `now`, from `f`, with Boop's anchor (nil: none set,
    /// or its display is gone, and the pointer isn't followed).
    public mutating func read(_ f: Facts, anchor: Anchor?, at now: Int64) -> Now {
        var out = Now()
        out.hands = f.keyIdleMs.flatMap { Hands.now(keyIdleMs: $0, scrollIdleMs: f.scrollIdleMs, idleMs: f.idleMs) }
        if out.hands == .scrolling { out.scroll = f.scrollDown.map { $0 ? .down : .up } }
        out.fast = typingFast(f, at: now) && out.hands == .typing
        // A camera is a call; another app recording with none is you speaking
        // (documentation/design/screen-guide.md, "Going with you").
        out.onCall = call.update(f.camera, at: now, onMs: Self.callOnMs, offMs: Self.callOffMs)
        out.speaking = speech.update(f.otherInput && !f.camera, at: now, onMs: Self.speakOnMs, offMs: Self.speakOffMs)
        let music = sound.update(f.sound, at: now, onMs: Self.soundOnMs, offMs: Self.soundOffMs)
        out.music = music && !out.onCall
        out.pointer = pointer(f, anchor: anchor, at: now)
        return out
    }

    /// Whether keys went down in most of the last quarter seconds. Each
    /// reading shows only the last key, so one a quarter second is all it
    /// can see: readings that often see each.
    mutating func typingFast(_ f: Facts, at now: Int64) -> Bool {
        let slot = now / Self.slotMs
        if let key = f.keyIdleMs, key < Self.slotMs {
            let keySlot = (now - key) / Self.slotMs
            if !keySlots.contains(keySlot) { keySlots.append(keySlot) }
        }
        keySlots.removeAll { $0 <= slot - Int64(Self.windowSlots) }
        let n = keySlots.count
        if n >= Self.fastSlots {
            fast = true
            slowSince = nil
        } else if fast {
            if slowSince == nil { slowSince = now }
            if n <= Self.slowSlots || now - slowSince! >= Self.slowMs { fast = false; slowSince = nil }
        }
        return fast
    }

    mutating func pointer(_ f: Facts, anchor: Anchor?, at now: Int64) -> Pointer? {
        guard let px = f.pointerX, let py = f.pointerY else { return nil }
        if let p = pointerAt {
            if abs(px - p.x) >= Self.movedPt || abs(py - p.y) >= Self.movedPt { movedAt = now }
        }
        pointerAt = (px, py)
        guard let anchor, let moved = movedAt, now - moved < Self.pointerStillMs else { return nil }
        return anchor.pointer(at: px, py)
    }
}
