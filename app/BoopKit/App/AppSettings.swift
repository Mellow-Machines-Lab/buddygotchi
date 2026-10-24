import Darwin
import Foundation

/// The app's own settings, in `settings.json` next to the memory files. Name
/// and nature live in `long-term.md`; the API key lives in the Keychain.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Who Boop is: the personality file it reads.
    public var personality = Personality.default
    public var volume = 6
    /// Several buddies side by side, each its own board and pack: empty, or
    /// one, for the one Boop.
    public var buddies: [BuddySetting] = []
    /// The one Boop's board, by its `hello.id`, remembered the first time
    /// it's tapped over Bluetooth: from then on Boop takes only it, until
    /// Settings forgets it.
    public var board: String?
    /// The onboarding act a quit left off at, after Boop was named; none
    /// once it's finished (`Onboarding.resume`).
    public var onboarding: Onboarding.Act?

    public init() {}

    public init(from decoder: Decoder) throws {
        // Missing keys keep their defaults, so older files still load; keys
        // this version doesn't know are ignored: `moodGraph` from before the
        // one mood graph (2026-10-15), `mode` from before the
        // personalities (2026-09-27), `classifier`, `writer` and `brain` from
        // before the modes, and `focus`, `away`, `awaySince`, `finished` and
        // `projects` from before 2026-09-26. A personality the pack doesn't have is its default.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let raw = try? c.decodeIfPresent(String.self, forKey: .personality), let p = Personality(rawValue: raw) {
            personality = p
        }
        volume = max(0, min(10, try c.decodeIfPresent(Int.self, forKey: .volume) ?? volume))
        buddies = (try? c.decodeIfPresent([BuddySetting].self, forKey: .buddies)) ?? []
        board = try? c.decodeIfPresent(String.self, forKey: .board)
        onboarding = try? c.decodeIfPresent(Onboarding.Act.self, forKey: .onboarding)
    }

    enum CodingKeys: String, CodingKey { case personality, volume, buddies, board, onboarding }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(personality.rawValue, forKey: .personality)
        try c.encode(volume, forKey: .volume)
        if !buddies.isEmpty { try c.encode(buddies, forKey: .buddies) }
        try c.encodeIfPresent(board, forKey: .board)
        try c.encodeIfPresent(onboarding, forKey: .onboarding)
    }

    public static let file = "settings.json"

    public static func load(from directory: URL) -> AppSettings {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: directory.appendingPathComponent(Self.file), options: .atomic)
    }

    /// `~/Library/Application Support/Boop`: the everyday app's memory files,
    /// settings and hook socket.
    public static func defaultStateDir(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Boop")
    }

    /// Whether `dir` is the everyday Boop's folder. Only that Boop installs
    /// or repairs hooks: they report to its socket.
    public static func isEveryday(_ dir: URL, home: String = NSHomeDirectory()) -> Bool {
        func canonical(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
        return canonical(dir) == canonical(defaultStateDir(home: home))
    }
}

/// One app per state directory: a second copy would fight over the memory
/// files and the hook socket. The lock goes away with the process.
public final class InstanceLock {
    let fd: Int32

    public init?(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent("boop.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        self.fd = fd
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }
}
