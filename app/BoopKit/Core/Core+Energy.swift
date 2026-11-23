import Foundation

/// Boop's energy: one dial, shown on its lids and in its tempo, which the
/// time of day and a long stretch of work turn (documentation/design/
/// screen-guide.md, "Energy"). A plain rule on the Mac, so the board and
/// the popover always agree; the board only draws it.
public enum Energy: String, Sendable {
    /// Wide eyes and a quick sway: the first hour after you first show up
    /// on a Boop day.
    case bright
    case normal
    /// Heavy lids, a slow tempo, a yawn now and then: at night, or after a
    /// long stretch of work with no rest.
    case tired
}

extension Core {
    /// Bright lasts this long after the day's first showing up.
    public static let brightForMs: Int64 = 60 * 60_000
    /// Tired after a working stretch this long, with no rest
    /// (`Tags.stretchRestMs`): `tier3`'s 15 minutes.
    public static let tiredAfterWorkMs: Int64 = 15 * 60_000

    /// Boop's energy at `now`: tired at night or after a long working
    /// stretch (since `workingSince`), else bright within `brightForMs` of
    /// your first showing up today, else normal.
    func energy(at now: Int64, workingSince: Int64?) -> Energy {
        if calendar(at: now).contains("night") { return .tired }
        if let since = workingSince, now - since >= Self.tiredAfterWorkMs { return .tired }
        if let first = firstShownUp, first.day == config.time.boopDay(wall(now)), now - first.at < Self.brightForMs {
            return .bright
        }
        return .normal
    }

    /// You showed up (a touch, an unlock, coming back): the first time on a
    /// Boop day starts bright.
    func shownUp(at now: Int64) {
        let today = config.time.boopDay(wall(now))
        if firstShownUp?.day != today { firstShownUp = (today, now) }
    }
}
