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

    /// The side of Boop the screen is on, as you look at Boop.
    public enum Side: String, Sendable {
        case left, right

        /// The board's tag: `macleft` or `macright`.
        public var tag: String { "mac" + rawValue }
    }

    /// The side of Boop the screen is on, from how far across its display
    /// the anchor is: in its left third, Boop sits on the screen's left, so
    /// the screen is on Boop's right; in its right third, on Boop's left;
    /// in the middle (Boop under or over the screen), neither, and it
    /// doesn't turn.
    public var side: Side? {
        guard display.width > 0 else { return nil }
        let across = (x - display.x) / display.width
        return across < Self.sideThird ? .right : across > 1 - Self.sideThird ? .left : nil
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
/// reading (`Hands`): typing fast, music playing or a video, a call, a
/// copy held, and where your pointer is. Each is a plain fact read from
/// the Mac's state, never content: key timing from idle times, never keys;
/// whether sound or a camera is on, never what it plays; the pasteboard's
/// change count, never what's on it; the pointer's place. They go to the
/// board as tags (`Tags.along`) and the pointer as `state`'s `ptr`, and
/// the board decides what the body does with them. No event, nothing in
/// the transcript, nothing the brain, the world or the daily counts read.
///
/// One of these is fed a reading every hands tick (`Runtime.handsTick`),
/// at any pace: every rule here is timed by the clock, not by readings.
public struct Along: Sendable {
    /// The Mac's raw facts at one instant. Nil for a reader there isn't
    /// (headless, before a dev line says one).
    public struct Reading: Equatable, Sendable {
        public var keyIdleMs: Int64?
        public var idleMs: Int64 = 0
        public var scrollIdleMs: Int64?
        public var clickIdleMs: Int64?
        /// The pointer, in the anchor's coordinates (`Anchor`).
        public var pointerX: Double?
        public var pointerY: Double?
        /// The display the pointer is on, for a new anchor.
        public var display: Anchor.Rect?
        /// The default output device is running somewhere: something plays.
        public var sound = false
        /// The frontmost app's bundle id.
        public var front: String?
        /// A camera is running somewhere.
        public var camera = false
        /// The default input device is running somewhere.
        public var mic = false
        /// The general pasteboard's change count.
        public var copies: Int?
        /// Boop's own push-to-talk is listening: its mic isn't a call.
        public var listening = false

        public init() {}
    }

    /// What's true now.
    public struct Now: Equatable, Sendable {
        public var hands: Hands?
        public var fast = false
        public var sound: Sound?
        public var call = false
        public var holding = false
        public var pointer: Pointer?

        public init() {}

        /// The board's tags for them, in `Tags.along`'s order, but your
        /// hands' `typing` and `reading`, which are `Tags.hands`.
        public var tags: [String] {
            var on: [String] = []
            if hands == .scrolling { on.append("scrolling") }
            if fast { on.append("typingfast") }
            if let sound { on.append(sound.rawValue) }
            if call { on.append("call") }
            if holding { on.append("holding") }
            return on
        }
    }

    /// What's playing: music, or a video you're watching.
    public enum Sound: String, Sendable {
        case music, watching
    }

    /// Typing fast: keys in at least `fastSlots` of the last `windowSlots`
    /// quarter seconds. A steady typist at 60 words a minute or more (5
    /// keys a second) leaves a key in nearly every quarter second; at 30
    /// or with pauses to think (2 to 3 a second), a third or more of them
    /// pass without one. Three in four is between the two.
    public static let slotMs: Int64 = 250
    public static let windowSlots = 8
    public static let fastSlots = 6

    /// Sound counts once it's run this long, so a system sound or an alert
    /// doesn't, and stops once it's been off this long, so a gap between
    /// tracks doesn't stop it.
    public static let soundOnMs: Int64 = 5000
    public static let soundOffMs: Int64 = 3000
    /// What's playing turns from music to watching, or back, once the
    /// frontmost app has said so this long: a glance at another window
    /// doesn't turn it.
    public static let kindMs: Int64 = 3000
    /// The apps a video plays in, by bundle id: sound while one of them is
    /// frontmost is watching; with any other, music, which plays behind.
    public static let players: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.microsoft.edgemac", "com.apple.QuickTimePlayerX", "com.apple.TV", "com.colliderli.iina",
        "org.videolan.vlc",
    ]

    /// A call starts once a camera or the mic has run this long, and ends
    /// once both have been off this long.
    public static let callOnMs: Int64 = 5000
    public static let callOffMs: Int64 = 5000

    /// A copy is held until your next key or click after it, or this long.
    public static let holdMs: Int64 = 10_000
    /// A copy this soon after the one before is the same copying: no new
    /// hold.
    public static let copyGapMs: Int64 = 2000

    /// The pointer counts as moving for this long after it last moved.
    public static let pointerStillMs: Int64 = 3000
    /// It's moved when it's gone at least this far, in points.
    public static let movedPt = 2.0

    /// A fact that comes on once its reading has held `onMs` and goes off
    /// once it's been off `offMs`.
    struct Held: Sendable {
        var on = false
        var since: Int64?

        mutating func update(_ raw: Bool, at now: Int64, onMs: Int64, offMs: Int64) -> Bool {
            if raw == on {
                since = nil
            } else if let s = since {
                if now - s >= (raw ? onMs : offMs) { on = raw; since = nil }
            } else {
                since = now
                if (raw ? onMs : offMs) <= 0 { on = raw; since = nil }
            }
            return on
        }
    }

    var keySlots: [Int64] = []
    var sound = Held(), call = Held()
    var kind: Sound?
    var kindSince: Int64?
    var copies: Int?
    var lastCopyAt: Int64?
    var heldAt: Int64?
    var pointerAt: (x: Double, y: Double)?
    var movedAt: Int64?

    public init() {}

    /// What's true at `now`, from `r`, with Boop's anchor (nil: none set,
    /// and the pointer isn't followed).
    public mutating func read(_ r: Reading, anchor: Anchor?, at now: Int64) -> Now {
        var out = Now()
        out.hands = r.keyIdleMs.flatMap { Hands.now(keyIdleMs: $0, scrollIdleMs: r.scrollIdleMs, idleMs: r.idleMs) }
        out.fast = typingFast(r, at: now) && out.hands == .typing
        out.call = call.update(r.camera || (r.mic && !r.listening), at: now, onMs: Self.callOnMs, offMs: Self.callOffMs)
        let playing = sound.update(r.sound, at: now, onMs: Self.soundOnMs, offMs: Self.soundOffMs)
        out.sound = playing && !out.call ? soundKind(r.front, at: now) : nil
        if !playing { kind = nil; kindSince = nil }
        out.holding = holding(r, at: now)
        out.pointer = pointer(r, anchor: anchor, at: now)
        return out
    }

    /// Whether keys went down in most of the last quarter seconds. Each
    /// reading shows only the last key, so one a quarter second is all it
    /// can see: readings that often see each.
    mutating func typingFast(_ r: Reading, at now: Int64) -> Bool {
        let slot = now / Self.slotMs
        if let key = r.keyIdleMs, key < Self.slotMs {
            let keySlot = (now - key) / Self.slotMs
            if !keySlots.contains(keySlot) { keySlots.append(keySlot) }
        }
        keySlots.removeAll { $0 <= slot - Int64(Self.windowSlots) }
        return keySlots.count >= Self.fastSlots
    }

    mutating func soundKind(_ front: String?, at now: Int64) -> Sound {
        let shown: Sound = front.map(Self.players.contains) == true ? .watching : .music
        guard let k = kind else {
            kind = shown
            return shown
        }
        if shown == k {
            kindSince = nil
        } else if let s = kindSince {
            if now - s >= Self.kindMs { kind = shown; kindSince = nil }
        } else {
            kindSince = now
        }
        return kind ?? shown
    }

    mutating func holding(_ r: Reading, at now: Int64) -> Bool {
        if let c = r.copies {
            if let was = copies, c != was {
                if lastCopyAt.map({ now - $0 >= Self.copyGapMs }) ?? true, heldAt == nil { heldAt = now }
                lastCopyAt = now
            }
            copies = c
        }
        guard let at = heldAt else { return false }
        let since = now - at
        // A key or a click after the copy (the copy's own came before it
        // was seen) lets it go: the paste, or moving on.
        let input = min(r.keyIdleMs ?? .max, r.clickIdleMs ?? .max)
        if since >= Self.holdMs || input + 50 < since {
            heldAt = nil
            return false
        }
        return true
    }

    mutating func pointer(_ r: Reading, anchor: Anchor?, at now: Int64) -> Pointer? {
        guard let px = r.pointerX, let py = r.pointerY else { return nil }
        if let p = pointerAt {
            if abs(px - p.x) >= Self.movedPt || abs(py - p.y) >= Self.movedPt { movedAt = now }
        }
        pointerAt = (px, py)
        guard let anchor, let moved = movedAt, now - moved < Self.pointerStillMs else { return nil }
        return anchor.pointer(at: px, py)
    }
}
