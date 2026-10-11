import Foundation
import MellowHarness

/// The character pack the engine runs (characters/CHARACTER.md): who the
/// creature is, its moods and how they connect. The engine takes every mood
/// from here and names none itself. There's one per process, chosen at
/// start (§2):
/// - The app loads its bundled pack with `use(_:)`.
/// - Anything that reads `active` before that (the tests, `boopdev`) gets
///   the pack at `BOOP_CHARACTER`, else the one the repo last staged.
public struct CharacterPack: Sendable {
    /// One mood (CHARACTER.md §5).
    public struct Mood: Sendable, Equatable {
        public let id: String
        /// When the creature is in it: the `mood` question's option.
        public let meaning: String
        public let notFor: String?
        /// What its face means for one moment: the reaction's face option.
        public let face: String?
        public let faceNotFor: String?
        public let moves: MoodGraph.Moves
        /// The mood a face or voice that lacks this one uses instead.
        public let fallback: String?
        public let family: String?
        /// Only passes through, and leaves for its fallback soon after.
        public let brief: Bool
        /// Never reached from routine work, only from a fresh, strong event.
        public let quietNever: Bool
    }

    /// The mood policy's timings, in ms (CHARACTER.md §5).
    public struct Pacing: Sendable, Equatable {
        public var ordinaryDwellMs: Int64 = 30_000
        public var reverseCooldownMs: Int64 = 60_000
        public var briefExitMs: Int64 = 5_000
        public var freshEvidenceMs: Int64 = 15_000
    }

    /// The pack's folder: its steering, and what the app reads at run time.
    public let directory: URL
    public let id: String
    public let name: String
    public let version: String
    /// The resting mood: a new state folder starts in it, every mood fades
    /// toward it, and a word that isn't a mood reads as it.
    public let defaultMood: String
    /// What the board shows before the Mac sends a mood (CHARACTER.md §4):
    /// the pack's `startup_mood`, else its default mood.
    public let startupMood: String
    /// The personalities' names, in order: the first is the default.
    public let personalities: [String]
    /// What each personality does, in one line, for Settings.
    public let personalityAbout: [String: String]
    /// Old names for moods, read as the mood (Boop's `cheerful` is happy).
    public let aliases: [String: String]
    /// The moods a very long turn's finish may jump to: `big_success` and
    /// `big_failure`.
    public let outcomes: [String: [String]]
    public let pacing: Pacing
    /// The moods in the pack's order: v3's graph for Boop.
    public let moods: [Mood]
    /// v2's 13 moods, with their faces' wording. They stay until Boop's
    /// pack takes v3 alone.
    public let moodsV2: [Mood]

    // Derived once, since the mood action reads them on every pass.
    let v2Names: [String]
    let v2Options: [Option]
    let v3Options: [Option]
    let faces: [Option]
    let movesV2: [String: MoodGraph.Moves]
    let nodesV3: [String: MoodGraphV3.Node]
    let quietNever: Set<String>
}

public struct CharacterPackError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

extension CharacterPack {
    /// Reads `character.json` from a pack's folder, and throws if it isn't
    /// a pack: a key missing, a move, fallback or outcome to a mood that
    /// isn't one, or a default mood that isn't one. A pack stands alone:
    /// everything it has is in its own folder.
    public init(directory: URL) throws {
        let file = directory.appendingPathComponent("character.json")
        let data: Data
        do { data = try Data(contentsOf: file) } catch { throw CharacterPackError("\(file.path) can't be read: \(error)") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CharacterPackError("\(file.path) isn't a JSON object")
        }
        try self.init(json: json, from: file.path, directory: directory)
    }

    init(json: [String: Any], from source: String, directory: URL = URL(fileURLWithPath: "/")) throws {
        self.directory = directory
        func string(_ key: String) throws -> String {
            guard let s = json[key] as? String, !s.isEmpty else { throw CharacterPackError("\(source): \(key) is missing") }
            return s
        }
        func moodList(_ key: String) throws -> [Mood] {
            try (json[key] as? [[String: Any]] ?? []).map { try CharacterPack.mood($0, in: source) }
        }
        id = try string("id")
        name = try string("name")
        version = try string("version")
        defaultMood = try string("default_mood")
        startupMood = json["startup_mood"] as? String ?? defaultMood
        // A personality is a name, or {"id": name, "about": one line}.
        let listed = json["personalities"] as? [Any] ?? []
        personalities = listed.compactMap { ($0 as? String) ?? ($0 as? [String: Any])?["id"] as? String }
        personalityAbout = Dictionary(listed.compactMap { item -> (String, String)? in
            guard let p = item as? [String: Any], let id = p["id"] as? String, let about = p["about"] as? String else { return nil }
            return (id, about)
        }, uniquingKeysWith: { a, _ in a })
        aliases = json["aliases"] as? [String: String] ?? [:]
        outcomes = json["outcomes"] as? [String: [String]] ?? [:]
        var pacing = Pacing()
        if let p = json["pacing"] as? [String: Any] {
            func ms(_ key: String) -> Int64? { (p[key] as? NSNumber)?.int64Value }
            pacing.ordinaryDwellMs = ms("ordinary_dwell_ms") ?? pacing.ordinaryDwellMs
            pacing.reverseCooldownMs = ms("reverse_cooldown_ms") ?? pacing.reverseCooldownMs
            pacing.briefExitMs = ms("brief_exit_ms") ?? pacing.briefExitMs
            pacing.freshEvidenceMs = ms("fresh_evidence_ms") ?? pacing.freshEvidenceMs
        }
        self.pacing = pacing
        moods = try moodList("moods")
        moodsV2 = try moodList("moods_v2")
        guard !moods.isEmpty else { throw CharacterPackError("\(source): moods is empty") }

        for (key, list) in [("moods", moods), ("moods_v2", moodsV2)] {
            let names = Set(list.map(\.id))
            guard names.count == list.count else { throw CharacterPackError("\(source): \(key) names a mood twice") }
            for m in list {
                for to in m.moves.all + [m.fallback].compactMap({ $0 }) where !names.contains(to) {
                    throw CharacterPackError("\(source): \(m.id) in \(key) leads to \(to), which isn't a mood")
                }
            }
        }
        let names = Set(moods.map(\.id))
        guard names.contains(defaultMood) else { throw CharacterPackError("\(source): default_mood \(defaultMood) isn't a mood") }
        guard names.contains(startupMood) else { throw CharacterPackError("\(source): startup_mood \(startupMood) isn't a mood") }
        for (kind, list) in outcomes {
            for m in list where !names.contains(m) { throw CharacterPackError("\(source): outcomes.\(kind) names \(m), which isn't a mood") }
        }
        for (old, new) in aliases where !names.contains(new) {
            throw CharacterPackError("\(source): alias \(old) is for \(new), which isn't a mood")
        }

        // A pack without `moods_v2` (all but Boop's for now) keeps its one
        // list for both.
        let v2 = moodsV2.isEmpty ? moods : moodsV2
        v2Names = v2.map(\.id)
        v2Options = v2.map { Option($0.id, $0.meaning, notFor: $0.notFor) }
        v3Options = moods.map { Option($0.id, $0.meaning, notFor: $0.notFor) }
        faces = v2.compactMap { m in m.face.map { Option(m.id, $0, notFor: m.faceNotFor) } }
        movesV2 = Dictionary(uniqueKeysWithValues: v2.map { ($0.id, $0.moves) })
        let resting = defaultMood
        nodesV3 = Dictionary(uniqueKeysWithValues: moods.map {
            ($0.id, MoodGraphV3.Node(meaning: $0.meaning, family: $0.family ?? "", fallback: $0.fallback ?? resting,
                                     brief: $0.brief, moves: $0.moves))
        })
        quietNever = Set(moods.filter(\.quietNever).map(\.id))
    }

    static func mood(_ m: [String: Any], in source: String) throws -> Mood {
        guard let id = m["id"] as? String, let meaning = m["meaning"] as? String else {
            throw CharacterPackError("\(source): a mood without an id or a meaning")
        }
        let moves = m["moves"] as? [String: [String]] ?? [:]
        return Mood(id: id, meaning: meaning, notFor: m["not_for"] as? String,
                    face: m["face"] as? String, faceNotFor: m["face_not_for"] as? String,
                    moves: MoodGraph.Moves(ordinary: moves["ordinary"] ?? [], dramatic: moves["dramatic"] ?? []),
                    fallback: m["fallback"] as? String, family: m["family"] as? String,
                    brief: m["brief"] as? Bool ?? false, quietNever: m["quiet_never"] as? Bool ?? false)
    }
}

extension CharacterPack {
    /// The process's character: the one `use(_:)` set, else the pack at
    /// `BOOP_CHARACTER`, else the one the repo last staged. It stops the
    /// process if that one doesn't load: nothing works without moods.
    public static var active: CharacterPack { store.get() }

    /// Sets the process's character. Call it once, before anything reads
    /// `active`.
    public static func use(_ character: CharacterPack) { store.set(character) }

    /// The pack a process uses when nothing chose one: `BOOP_CHARACTER`'s,
    /// else the one the repo this file was built from last staged
    /// (`.character-build/pack`, CHARACTER.md §2), else its Pixel pack.
    static var defaultDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["BOOP_CHARACTER"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardizedFileURL
        if let staged = try? String(contentsOf: repo.appendingPathComponent(".character-build/pack"), encoding: .utf8) {
            return URL(fileURLWithPath: staged.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return repo.appendingPathComponent("characters/pixel")
    }

    private static let store = Store()

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var character: CharacterPack?

        func get() -> CharacterPack {
            lock.withLock {
                if let character { return character }
                do {
                    let loaded = try CharacterPack(directory: CharacterPack.defaultDirectory)
                    character = loaded
                    return loaded
                } catch {
                    fatalError("no character: \(error)")
                }
            }
        }

        func set(_ c: CharacterPack) { lock.withLock { character = c } }
    }
}
