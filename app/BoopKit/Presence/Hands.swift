import Foundation

/// Your hands at the Mac, for the board to be with you (the gel types
/// along and watches the work with you): `typing` while keys are going
/// down, `reading` while you're there with them still. It's worked out from
/// two idle times, how long since any key and since any input at all, never
/// from the keys themselves: Boop knows that you type, not what.
///
/// It's a fact true now, sent to the board as a tag (`Tags.hands`), like the
/// time of day: no event, nothing in the transcript, and nothing the brain
/// reads.
public enum Hands: String, CaseIterable, Sendable {
    case typing, reading

    /// Typing until this long after the last key: a pause between words
    /// isn't a stop.
    public static let typingMs: Int64 = 2000
    /// Reading until this long after the last input of any kind: after it
    /// you may have looked away.
    public static let readingMs: Int64 = 20_000

    /// Your hands now, from the time since the last key and since the last
    /// input of any kind; nil when you've been still too long to say.
    public static func now(keyIdleMs: Int64, idleMs: Int64) -> Hands? {
        keyIdleMs < typingMs ? .typing : min(keyIdleMs, idleMs) < readingMs ? .reading : nil
    }
}

/// The side of Boop your Mac is on, as you look at Boop: where it turns
/// when something needs you (`Tags.macSides`). Not set, it doesn't turn.
public enum MacSide: String, CaseIterable, Codable, Sendable {
    case left, right

    public var tag: String { "mac" + rawValue }
}
