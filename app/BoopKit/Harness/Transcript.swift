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

    /// The events in `folder`'s files after `seq`, in order, from the file
    /// of the day `from` (`yyyy-MM-dd`) on: what a reader that stopped at
    /// `seq` on that day missed. The log in memory holds only a day; the
    /// files hold `keptDays`.
    public static func events(in folder: URL, after seq: Int, from day: String = "") -> [Event] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".jsonl") && String($0.dropLast(6)) >= day }.sorted()
        var out: [Event] = []
        for name in names {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { continue }
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                if let e = Event(jsonLine: line), e.seq > seq { out.append(e) }
            }
        }
        return out.sorted { $0.seq < $1.seq }
    }

    /// The log in `folder`, or in memory only with none (tests, the evals).
    public static func log(folder: URL? = nil, time: LocalTime = LocalTime(), note: @escaping (String) -> Void = { _ in }) -> Log {
        var options = Log.Options()
        options.keptDays = keptDays
        options.day = { time.day($0) }
        return Log(folder: folder, options: options, note: note)
    }
}
