import Foundation
import MellowHarness

extension Runtime {
    /// Where `saveReport` puts its folders, in the state directory.
    public static let reportsDir = "bug-reports"
    /// The newest reports kept: saving one deletes those past it, oldest
    /// first, as the logs are capped.
    public static let reportsKept = 20
    /// How much of the end of `boop.log` a report copies.
    static let reportLogBytes = 1 << 20
    /// The newest of macOS's crash reports for Boop a report copies, from
    /// this many days.
    static let reportCrashes = 3, reportCrashDays = 7

    /// A bug report: everything needed to work out
    /// afterwards what Boop saw and did, in a new folder under
    /// `bug-reports/`. `debug.jsonl` is this launch's debug lines, debug
    /// mode or not (`recent`, or in debug mode the file's end, up to
    /// `DebugLog.Recent.maxBytes`); `boop.log`
    /// is the log's end; `settings.json` is copied;
    /// `about.json` is the versions and the status now. Calls `done` on
    /// `home` with the folder, or nil if it couldn't be made.
    public func saveReport(_ done: @escaping @Sendable (URL?) -> Void) {
        home.async { [self] in
            let format = DateFormatter()
            format.dateFormat = "yyyy-MM-dd-HHmmss"
            let base = options.stateDir.appendingPathComponent(Self.reportsDir)
                .appendingPathComponent(format.string(from: Date(timeIntervalSince1970: Double(options.wallClock()) / 1000)))
            let fm = FileManager.default
            // Repeated clicks in one second (or a clock set back) must
            // never overwrite an earlier report with a mixture of files.
            var dir = base, suffix = 2
            while fm.fileExists(atPath: dir.path) {
                dir = base.appendingPathExtension(String(suffix))
                suffix += 1
            }
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let lines = dir.appendingPathComponent(DebugLog.fileName)
                if options.debug {
                    try Self.write(Self.debugLines(debugLogURL), to: lines)
                } else {
                    try Self.write(recent.pieces, to: lines)
                }
                try? Self.end(of: options.stateDir.appendingPathComponent("boop.log"), bytes: Self.reportLogBytes)?
                    .write(to: dir.appendingPathComponent("boop.log"))
                try? fm.copyItem(at: options.stateDir.appendingPathComponent(AppSettings.file),
                                 to: dir.appendingPathComponent(AppSettings.file))
                let crashes = Self.crashReports(in: options.crashReports, since: Date().addingTimeInterval(-Double(Self.reportCrashDays) * 86_400))
                if !crashes.isEmpty {
                    let folder = dir.appendingPathComponent("crashes")
                    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    for crash in crashes { try? fm.copyItem(at: crash, to: folder.appendingPathComponent(crash.lastPathComponent)) }
                }
                let now = options.clock()
                let about: [String: Any] = [
                    "app": BoopVersion.current, "build": AboutThisMac.build, "macos": AboutThisMac.macOS,
                    "mac": AboutThisMac.model, "arch": AboutThisMac.arch, "unclean_exit": uncleanExit, "crashes": crashes.count,
                    "firmware": link.hello?.fw ?? NSNull(), "device": link.hello?.id ?? NSNull(),
                    "device_reset": link.hello.flatMap { DeviceInfo($0).reset } ?? NSNull(),
                    // Why the device connected gets no `do`: its firmware
                    // doesn't fit, and boop.log says whose it is.
                    "device_trouble": link.trouble?.description ?? NSNull(),
                    "link": options.link?.name ?? "none", "connected": link.connected, "debug": options.debug,
                    "personality": personality.rawValue, "mood": moodNow, "brain": harness.brain?.id ?? "none",
                    "taken_at_ms": now, "taken_at_wall_ms": options.wallClock(),
                    "sessions": core.sessionList(at: now).map { ["agent": $0.agent, "project": $0.project, "status": $0.status.rawValue] },
                ]
                try Data(Event.json(about).utf8).write(to: dir.appendingPathComponent("about.json"))
                Self.pruneReports(in: options.stateDir.appendingPathComponent(Self.reportsDir))
                options.log("report: saved \(dir.path)")
                done(dir)
            } catch {
                options.log("report: can't save: \(error)")
                done(nil)
            }
        }
    }

    /// Deletes all but the newest `reportsKept` reports in `folder`. Their
    /// names are when they were taken, so the oldest sort first, a second
    /// one in the same second (`.2`) after its first.
    static func pruneReports(in folder: URL) {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }
            .sorted { a, b in
                let (x, y) = (a.split(separator: ".", maxSplits: 1), b.split(separator: ".", maxSplits: 1))
                return x[0] != y[0] ? x[0] < y[0] : (Int(x.dropFirst().first ?? "1") ?? 1) < (Int(y.dropFirst().first ?? "1") ?? 1)
            }
        for name in names.dropLast(reportsKept) { try? fm.removeItem(at: folder.appendingPathComponent(name)) }
    }

    /// macOS's crash reports for Boop in `folder` (`Boop-….ips`, or the
    /// older `.crash`) changed since `since`, the newest `reportCrashes`.
    static func crashReports(in folder: URL, since: Date) -> [URL] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let dated: [(URL, Date)] = names.compactMap { name in
            guard name.hasPrefix("Boop-") || name.hasPrefix("Boop_"), name.hasSuffix(".ips") || name.hasSuffix(".crash") else { return nil }
            let url = folder.appendingPathComponent(name)
            guard let at = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date, at >= since else { return nil }
            return (url, at)
        }
        return dated.sorted { $0.1 > $1.1 }.prefix(reportCrashes).map(\.0)
    }

    /// The last `bytes` of the file at `url`, from the start of a line;
    /// nil when there's no file. Mapped, not read, so a copy of megabytes
    /// leaves no memory behind.
    static func end(of url: URL, bytes: Int) -> Data? {
        (try? Data(contentsOf: url, options: .alwaysMapped)).map { end(of: $0, bytes: bytes) }
    }

    static func end(of data: Data, bytes: Int) -> Data {
        guard data.count > bytes else { return data }
        let end = data.suffix(bytes)
        guard data[end.startIndex - 1] != 0x0A else { return end }
        return end.firstIndex(of: 0x0A).map { end[end.index(after: $0)...] } ?? Data()
    }

    /// Debug mode's `debug.jsonl` for a report, as `recent` would have it:
    /// its end, after the launch's `questions` line and the `head` line in
    /// force where the end starts, when those come before it.
    static func debugLines(_ url: URL) -> [Data] {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return [] }
        let end = end(of: data, bytes: DebugLog.Recent.maxBytes)
        let before = data[..<end.startIndex]
        func line(from start: Data.Index) -> Data { before[start...(before[start...].firstIndex(of: 0x0A) ?? before.endIndex - 1)] }
        var pieces: [Data] = []
        if before.starts(with: DebugLog.questionsLine) { pieces.append(line(from: before.startIndex)) }
        if let head = before.range(of: Data([0x0A] + DebugLog.headLine), options: .backwards) { pieces.append(line(from: head.lowerBound + 1)) }
        return pieces + [end]
    }

    /// Writes `pieces` one after another to a new file at `url`, without
    /// joining them first.
    static func write<Piece: DataProtocol>(_ pieces: [Piece], to url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        for piece in pieces { try file.write(contentsOf: piece) }
    }
}
