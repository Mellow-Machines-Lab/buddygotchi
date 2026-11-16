import Foundation

/// Your hands at the Mac, for the board to be with you (the gel types
/// along, reads along and watches the work with you): `typing` while keys
/// are going down, `scrolling` while you scroll, `reading` while you're
/// there with them still. It's worked out from idle times, how long since
/// any key, since any scroll and since any input at all, never from the
/// keys or the page themselves: Boop knows that you type or scroll, not
/// what.
///
/// It's a fact true now, sent to the board as a tag (`Tags.hands`,
/// `Tags.along`), like the time of day: no event, nothing in the
/// transcript, and nothing the brain reads.
public enum Hands: String, CaseIterable, Sendable {
    case typing, reading, scrolling

    /// Typing until this long after the last key: a pause between words
    /// isn't a stop.
    public static let typingMs: Int64 = 2000
    /// Scrolling until this long after the last scroll: the pause as you
    /// read a screenful isn't a stop.
    public static let scrollingMs: Int64 = 1500
    /// Reading until this long after the last input of any kind: after it
    /// you may have looked away.
    public static let readingMs: Int64 = 20_000

    /// Your hands now, from the time since the last key, since the last
    /// scroll (nil: not known) and since the last input of any kind; nil
    /// when you've been still too long to say. Typing beats scrolling,
    /// which beats reading.
    public static func now(keyIdleMs: Int64, scrollIdleMs: Int64? = nil, idleMs: Int64) -> Hands? {
        if keyIdleMs < typingMs { return .typing }
        if let scrollIdleMs, scrollIdleMs < scrollingMs { return .scrolling }
        return min(keyIdleMs, idleMs) < readingMs ? .reading : nil
    }
}
