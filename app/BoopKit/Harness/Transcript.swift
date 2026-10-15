import Foundation
import MellowHarness

/// Boop's record of what happened and what it did:
/// MellowHarness's log in the state directory's
/// `transcript/`, one file a day, named for the day in Boop's time zone.
public enum Transcript {
    /// Days of files kept; older ones are deleted at launch and each new day.
    public static let keptDays = 14
    /// The folder in the state directory.
    public static let folderName = "transcript"

    /// The log in `folder`, or in memory only with none (tests, the evals).
    public static func log(folder: URL? = nil, time: LocalTime = LocalTime(), note: @escaping (String) -> Void = { _ in }) -> Log {
        var options = Log.Options()
        options.keptDays = keptDays
        options.day = { time.day($0) }
        return Log(folder: folder, options: options, note: note)
    }
}
