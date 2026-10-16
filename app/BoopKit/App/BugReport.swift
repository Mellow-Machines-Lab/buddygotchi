import Foundation
import MellowHarness

extension Runtime {
    /// Where `saveReport` puts its folders, in the state directory.
    public static let reportsDir = "bug-reports"
    /// How much of the end of `boop.log`, and of today's transcript file,
    /// a report copies.
    static let reportLogBytes = 1 << 20
    /// How far back a report's `timeline.txt` reaches: about what you saw
    /// before you opened the popover and clicked.
    public static let reportTimelineMs: Int64 = 120_000
    /// The note you write about what you saw, in a report's folder.
    public static let reportNote = "note.md"

    /// A bug report: everything needed to work out afterwards what Boop
    /// saw and did, in a new folder under `bug-reports/`, which
    /// `README.md` there lists for whoever reads it. `debug.jsonl` is this
    /// launch's debug lines, debug mode or not (`recent`, or in debug mode
    /// the file's end, up to `DebugLog.Recent.maxBytes`); `timeline.txt`
    /// is their last `reportTimelineMs`, readably; `boop.log` and
    /// `transcript.jsonl` are the ends of the log and today's transcript
    /// file; `settings.json` and `long-term.md` are copied; `about.json`
    /// is the versions and what's true now. `addNote` adds what you saw.
    /// Calls `done` on `home` with the folder, or nil if it couldn't be
    /// made.
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
                let state = options.stateDir
                try? Self.end(of: state.appendingPathComponent("boop.log"), bytes: Self.reportLogBytes)?
                    .write(to: dir.appendingPathComponent("boop.log"))
                try? Self.end(of: state.appendingPathComponent(Transcript.folderName)
                    .appendingPathComponent(options.time.day(options.wallClock()) + ".jsonl"), bytes: Self.reportLogBytes)?
                    .write(to: dir.appendingPathComponent("transcript.jsonl"))
                for file in [AppSettings.file, MemoryStore.longTermFile] {
                    try? fm.copyItem(at: state.appendingPathComponent(file), to: dir.appendingPathComponent(file))
                }
                let now = options.clock()
                let device = link.hello.map(DeviceInfo.init)
                let about: [String: Any] = [
                    "app": BoopVersion.current, "app_path": Bundle.main.executablePath ?? NSNull(),
                    "pack": CharacterPack.active.id,
                    "firmware": device?.fw ?? NSNull(), "device": device?.id ?? NSNull(),
                    "device_pack": device?.pack ?? NSNull(), "device_voice": device?.voice ?? NSNull(),
                    // Why the device connected gets no `do`: its firmware
                    // doesn't fit, and boop.log says whose it is.
                    "device_trouble": link.trouble?.description ?? NSNull(),
                    "link": options.link?.name ?? "none", "connected": link.connected, "debug": options.debug,
                    "personality": personality.rawValue, "mood": moodNow, "brain": harness.brain?.id ?? "none",
                    "brain_trouble": trouble?.why ?? NSNull(),
                    // The last `state` sent: what the device was told to show.
                    "screen": latest.flatMap { try? JSONSerialization.jsonObject(with: Data($0.jsonLine.utf8)) } ?? NSNull(),
                    "needs_you": core.needsYouShowing, "listening": core.listening != nil, "away": presence.away,
                    "finishes_a_tap_opens": reactions.opens.keys.sorted(), "cut_by_tap": reactions.cutByTap.count,
                    "growth": ["xp": growth.growth.xp, "stage": growth.growth.stage],
                    "taken_at_ms": now, "taken_at_wall_ms": options.wallClock(),
                    "sessions": core.sessionList(at: now).map { ["agent": $0.agent, "project": $0.project, "status": $0.status.rawValue] },
                ]
                try Data(Event.json(about).utf8).write(to: dir.appendingPathComponent("about.json"))
                let timeline = (try? Data(contentsOf: lines, options: .alwaysMapped)).map { Self.timeline($0, at: now) } ?? ""
                try Data(timeline.utf8).write(to: dir.appendingPathComponent("timeline.txt"))
                try Data(Self.reportReadme(taken: format.string(from: Date(timeIntervalSince1970: Double(options.wallClock()) / 1000)))
                    .utf8).write(to: dir.appendingPathComponent("README.md"))
                options.log("report: saved \(dir.path)")
                done(dir)
            } catch {
                options.log("report: can't save: \(error)")
                done(nil)
            }
        }
    }

    /// Adds what you saw to the report in `dir`, as `note.md`, replacing
    /// any note there. An empty note removes it.
    public static func addNote(_ note: String, to dir: URL) throws {
        let url = dir.appendingPathComponent(reportNote)
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try Data((text + "\n").utf8).write(to: url)
    }

    /// What to hand an agent: the report's folder, and the note.
    public static func reportPrompt(_ dir: URL, note: String) -> String {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Boop bug report: \(dir.path)\n" + (text.isEmpty ? "" : "\n\(text)\n")
            + "\nStart with README.md there. Work out what Boop did and why, and what to change."
    }

    /// The report's `README.md`: what each file holds and where to start.
    static func reportReadme(taken: String) -> String {
        """
        # Boop bug report, \(taken)

        Saved by the popover's ladybug button while Boop was running. `note.md`,
        if there is one, says in the owner's words what they saw or missed,
        shortly before `about.json`'s `taken_at_ms`.

        Start with `note.md`, then `timeline.txt`, then look up what you need
        in `debug.jsonl`. Every time is the runtime's clock in ms: lines'
        `received_at_ms` and `taken_at_ms` compare directly.

        | File | What it holds |
        | --- | --- |
        | `note.md` | What the owner saw, or thinks is missing |
        | `timeline.txt` | The last \(reportTimelineMs / 1000) s before the click, readably: what the brain heard, each pass's answers, what the outputs did, every message sent to the device and how each `do` ended |
        | `about.json` | What was true at the click: the versions, the app's path, the pack, the device and its link, the personality, the mood, the brain and its trouble, the last `state` sent (`screen`), needs you, listening, away, growth and the sessions |
        | `debug.jsonl` | This launch's debug lines: `questions`, `event`, `view`, `head`, `pass` (with HISTORY and NOW), `sent`, `ended` and `status` |
        | `transcript.jsonl` | The end of today's transcript file: every event Boop recorded today, earlier launches' included |
        | `boop.log` | The end of the app's log |
        | `settings.json`, `long-term.md` | The settings and who this Boop is |

        """
    }

    /// The end of `lines`, debug lines, from `reportTimelineMs` before `now`,
    /// readably, each with how long before `now` it came. Passes leave out
    /// their state, which `debug.jsonl` has.
    static func timeline(_ lines: Data, at now: Int64) -> String {
        let from = now - reportTimelineMs
        var rows: [(ms: Int64, line: Substring)] = []
        for line in String(decoding: lines, as: UTF8.self).split(separator: "\n").reversed() {
            guard let ms = receivedAt(line) else { continue }
            if ms < from { break }
            rows.append((ms, line))
        }
        let printer = DebugLog.Printer()
        var out = ""
        for (ms, line) in rows.reversed() {
            let readable: String?
            if line.hasPrefix(#"{"sent":"#) {
                readable = (line.contains(#""by":"brain""#) ? "→ device (brain) " : "→ device (rule) ") + clipped(line, upTo: #","by":"#)
            } else if line.hasPrefix(#"{"ended":"#) {
                readable = "← device ended " + clipped(line)
            } else if line.hasPrefix(#"{"status":"#) {
                readable = "status " + clipped(line)
            } else {
                readable = printer.readable(String(line))?.split(separator: "\n").filter { !$0.hasPrefix("    │") }
                    .joined(separator: "\n")
            }
            guard let readable, !readable.isEmpty else { continue }
            let at = String(format: "%7.1fs ", Double(ms - now) / 1000)
            out += at + readable.replacingOccurrences(of: "\n", with: "\n" + String(repeating: " ", count: at.count)) + "\n"
        }
        return out
    }

    /// A debug line's `received_at_ms`, which ends every one.
    static func receivedAt(_ line: Substring) -> Int64? {
        guard line.hasSuffix("}"), let r = line.range(of: #""received_at_ms":"#, options: .backwards) else { return nil }
        return Int64(line[r.upperBound...].dropLast())
    }

    /// A `sent`, `ended` or `status` line's value, up to `end` (from the
    /// line's end) without it, cut short for the timeline.
    static func clipped(_ line: Substring, upTo end: String = #","received_at_ms":"#) -> String {
        guard let colon = line.firstIndex(of: ":"), let r = line.range(of: end, options: .backwards)
        else { return String(line) }
        let value = line[line.index(after: colon)..<r.lowerBound]
        return value.count > 300 ? value.prefix(300) + "…" : String(value)
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
