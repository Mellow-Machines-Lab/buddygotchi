import Foundation

/// The rules for the buddy's name, which onboarding gives it and Settings
/// changes: 1 to 23 characters, without "·" or ":", which `long-term.md`'s
/// line uses, and a new one at most once a week.
public enum BuddyName {
    /// The most characters a name has. The memory file counts characters;
    /// the board's field counts bytes, and `StateSnapshot.clip` cuts it.
    public static let maxLength = 23
    /// A rename waits this long after the last one: a name is who the
    /// buddy is, to you and to the world.
    public static let renameEveryMs: Int64 = 7 * 24 * 60 * 60_000

    /// What a name field keeps of `text` as it's typed: precomposed, control
    /// characters as spaces, and at most `maxLength` characters.
    public static func edited(_ text: String) -> String {
        String(StateSnapshot.clip(text, max: Int.max).prefix(maxLength))
    }

    /// The name as it's kept: without spaces at either end.
    public static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Why `text` can't be a name, in plain words, or nil when it can. An
    /// empty field is no name, not a problem to say.
    public static func issue(_ text: String) -> String? {
        let name = trimmed(text)
        if name.contains("·") || name.contains(":") { return "Names can't use “·” or “:”." }
        if name.count > maxLength { return "Names are at most \(maxLength) characters." }
        if name.contains(where: \.isNewline) { return "Names are one line." }
        return nil
    }

    /// Whether `text` can be a name: not empty, and no `issue`.
    public static func valid(_ text: String) -> Bool { !trimmed(text).isEmpty && issue(text) == nil }

    /// When a rename may next happen, given the last one, in ms since
    /// 1970: nil for now, with none yet, or a week gone.
    public static func nextRename(after last: Int64?, at now: Int64) -> Int64? {
        guard let last else { return nil }
        let next = last + renameEveryMs
        return now >= next ? nil : next
    }
}
