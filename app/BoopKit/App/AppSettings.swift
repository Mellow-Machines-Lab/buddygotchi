import Darwin
import Foundation

/// The app's own settings, in `settings.json` next to the memory files. Name
/// lives in `long-term.md`; the API key lives in the Keychain.
public struct AppSettings: Codable, Equatable, Sendable {
    /// How much it says (`Talk`).
    public var talk = Talk.default
    /// Whether Boop may swear when a turn fails badly: off unless you turn
    /// it on. Off, the brain is never offered a swear and no swear take
    /// plays (`MomentOutput.speech`).
    public var swearing = false
    /// When Boop was last renamed in Settings, in ms since 1970: a rename
    /// waits a week after it (`BuddyName.nextRename`). Nil for never.
    public var renamed: Int64?
    public var volume = 6
    /// The one Boop's board, by its `hello.id`, remembered the first time
    /// it's tapped over Bluetooth: from then on Boop takes only it, until
    /// Settings forgets it.
    public var board: String?
    /// The onboarding act a quit left off at, after Boop was named; none
    /// once it's finished (`Onboarding.resume`).
    public var onboarding: Onboarding.Act?
    /// Whether the board shows the agents' calls falling past Boop, and
    /// the ones that hit it (`WorkStream`): on unless you turn it off.
    public var workStream = true
    /// Boop's body is the simulator, in a window of the app's own (the
    /// debug and internal builds), rather than its board: chosen in onboarding or Settings, and
    /// kept from launch to launch. Off, the board, unless chosen.
    public var simulator = false
    /// Boop types along with you and watches the work with you (`Hands`):
    /// on unless you turn it off. Off, the Mac's key and input idle times
    /// aren't read for it.
    public var typesAlong = true
    /// The side of Boop your Mac is on, where Boop turns when something
    /// needs you; not set, it doesn't turn.
    public var macSide: MacSide?
    /// Boop lives in the world of buddies: on unless you keep it private.
    public var world = true
    /// Onboarding's world screen has been shown: nothing goes to the world
    /// before it, even with `world` on.
    public var worldShown = false

    public init() {}

    public init(from decoder: Decoder) throws {
        // Missing keys keep their defaults, so older files still load; keys
        // this version doesn't know are ignored: `moodGraph` from before the
        // one mood graph (2026-10-15), `mode` from before the
        // personalities (2026-09-27), `personality` from before each pack
        // had one (2026-11-01), `classifier`, `writer` and `brain` from
        // before the modes, and `focus`, `away`, `awaySince`, `finished` and
        // `projects` from before 2026-09-26.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let saved = try? c.decodeIfPresent(String.self, forKey: .personality)
        // Chatter, the debugging personality before Talk (2026-10-25), was
        // the chatty one.
        talk = (try? c.decodeIfPresent(Talk.self, forKey: .talk)) ?? (saved == "chatter" ? .chatty : .default)
        swearing = (try? c.decodeIfPresent(Bool.self, forKey: .swearing)) ?? false
        renamed = try? c.decodeIfPresent(Int64.self, forKey: .renamed)
        volume = max(0, min(10, try c.decodeIfPresent(Int.self, forKey: .volume) ?? volume))
        board = try? c.decodeIfPresent(String.self, forKey: .board)
        onboarding = try? c.decodeIfPresent(Onboarding.Act.self, forKey: .onboarding)
        workStream = (try? c.decodeIfPresent(Bool.self, forKey: .workStream)) ?? true
        simulator = (try? c.decodeIfPresent(Bool.self, forKey: .simulator)) ?? false
        typesAlong = (try? c.decodeIfPresent(Bool.self, forKey: .typesAlong)) ?? true
        macSide = try? c.decodeIfPresent(MacSide.self, forKey: .macSide)
        world = (try? c.decodeIfPresent(Bool.self, forKey: .world)) ?? true
        worldShown = (try? c.decodeIfPresent(Bool.self, forKey: .worldShown)) ?? false
    }

    enum CodingKeys: String, CodingKey { case personality, talk, swearing, renamed, volume, board, onboarding, workStream, typesAlong, macSide, simulator, world, worldShown }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(talk, forKey: .talk)
        if swearing { try c.encode(swearing, forKey: .swearing) }
        try c.encodeIfPresent(renamed, forKey: .renamed)
        try c.encode(volume, forKey: .volume)
        try c.encodeIfPresent(board, forKey: .board)
        try c.encodeIfPresent(onboarding, forKey: .onboarding)
        if !workStream { try c.encode(workStream, forKey: .workStream) }
        if !typesAlong { try c.encode(typesAlong, forKey: .typesAlong) }
        try c.encodeIfPresent(macSide, forKey: .macSide)
        if simulator { try c.encode(simulator, forKey: .simulator) }
        if !world { try c.encode(world, forKey: .world) }
        if worldShown { try c.encode(worldShown, forKey: .worldShown) }
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

    /// Reads the settings in `directory`, changes them and writes them
    /// back, under one lock: the app's two writers, onboarding's window
    /// and the runtime on its queue, each change only what's theirs, so
    /// neither undoes the other's change. Returns them as written.
    @discardableResult
    public static func update(in directory: URL, _ change: (inout AppSettings) -> Void) throws -> AppSettings {
        try writing.withLock {
            var settings = load(from: directory)
            change(&settings)
            try settings.save(to: directory)
            return settings
        }
    }

    private static let writing = NSLock()

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

    /// What a copy on another folder than the everyday one is called where
    /// the everyday Boop's names are shared: its hook socket's listing
    /// (`dev-boop-onboarding.sock`) and its Jev key's Keychain entry. Made
    /// of its folder's name, letters, digits and dashes only.
    public static func copyName(_ dir: URL) -> String {
        copyPrefix + dir.lastPathComponent.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// What every copy's name starts with.
    public static let copyPrefix = "dev-"
}

/// One app per state directory: a second copy would fight over the memory
/// files and the hook socket. The lock goes away with the process.
public final class InstanceLock {
    let fd: Int32
    private var released = false
    private let releasing = NSLock()

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

    /// Lets the folder go before this lock goes away: a runtime that
    /// stopped hands the folder to the next one at once, as a rename's
    /// restart needs. Safe to call twice.
    public func release() {
        releasing.withLock {
            guard !released else { return }
            released = true
            flock(fd, LOCK_UN)
            close(fd)
        }
    }

    deinit { release() }
}
