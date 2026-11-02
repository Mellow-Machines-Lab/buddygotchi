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
    /// One mood (CHARACTER.md §5): a face, and, for the lasting moods the
    /// creature settles into, a meaning and its moves. A face-only mood
    /// settles into a lasting one.
    public struct Mood: Sendable, Equatable {
        public let id: String
        /// When the creature is in it: the `mood` question's option. Nil for
        /// a face-only mood.
        public let meaning: String?
        public let notFor: String?
        /// What its face means for one reaction: the reaction's face option.
        public let face: String
        public let faceNotFor: String?
        public let neighbours: MoodGraph.Neighbours
        /// The lasting mood a face-only one settles into; nil for a lasting one.
        public let settles: String?

        /// One the creature settles into, with a meaning and moves.
        public var lasting: Bool { meaning != nil }
    }

    /// The pack's folder: its steering, and what the app reads at run time.
    public let directory: URL
    public let id: String
    /// What the creature is called: the pack's name, or a buddy's own
    /// (`named(_:)`).
    public internal(set) var name: String
    public let version: String
    /// The resting mood: a new state folder starts in it, every mood fades
    /// toward it, and a word that isn't a mood reads as it.
    public let defaultMood: String
    /// What the board shows before the Mac sends a mood (CHARACTER.md §4):
    /// the pack's `startup_mood`, else its default mood.
    public let startupMood: String
    /// Every universal mood (`universalMoods`), in the pack's order: each a
    /// face, the lasting ones (`lasting`) moods too.
    public let moods: [Mood]
    /// The moods the creature settles into, in the pack's order: the mood
    /// question's options and the graph's nodes.
    public let lasting: [Mood]
    /// What the pack draws for each work act, by kind and by `start`, `pass`
    /// or `fail`, as Jev reads it, with `{name}` for the creature's name
    /// (CHARACTER.md §4). Empty for a pack that draws none.
    public let acts: [String: [String: String]]

    // Derived once, since the mood output reads them on every pass.
    let options: [Option]
    let faces: [Option]
    let byId: [String: Mood]
}

extension CharacterPack {
    /// The pack's demo, if it has one: `demo/demo.jsonl` (`DemoScript`,
    /// characters/DEMOS.md).
    public var demo: URL? { demo(named: "demo") }

    /// One of the pack's demos by name, `demo/<name>.jsonl`, if it has it.
    public func demo(named name: String) -> URL? {
        let url = directory.appendingPathComponent("demo/\(name).jsonl")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Every demo the pack has, `demo/*.jsonl`, by name.
    public var demos: [URL] {
        let folder = directory.appendingPathComponent("demo")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

public struct CharacterPackError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

extension CharacterPack {
    /// Reads `character.json` from a pack's folder, and throws if it isn't
    /// a pack: a key missing, moods that aren't the universal ones, a move
    /// or default mood that isn't a lasting one, or a face-only mood that
    /// settles into none. Everything the pack has is in the one folder.
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
        id = try string("id")
        name = try string("name")
        version = try string("version")
        defaultMood = try string("default_mood")
        startupMood = json["startup_mood"] as? String ?? defaultMood
        moods = try (json["moods"] as? [[String: Any]] ?? []).map { try CharacterPack.mood($0, in: source) }
        acts = json["acts"] as? [String: [String: String]] ?? [:]
        // The board reports the id, and the firmware names each mood in code.
        guard id.wholeMatch(of: /[a-z0-9-]+/) != nil else { throw CharacterPackError("\(source): id \(id) isn't lower case, digits and -") }
        let names = Set(moods.map(\.id))
        guard names.count == moods.count else { throw CharacterPackError("\(source): moods names a mood twice") }
        let universal = Set(CharacterPack.universalMoods)
        guard names == universal else {
            let missing = universal.subtracting(names).sorted(), extra = names.subtracting(universal).sorted()
            throw CharacterPackError("\(source): moods aren't the universal ones (missing \(missing), extra \(extra))")
        }
        lasting = moods.filter(\.lasting)
        let lastingNames = Set(lasting.map(\.id))
        for m in moods {
            for to in m.neighbours.all where !lastingNames.contains(to) {
                throw CharacterPackError("\(source): \(m.id) leads to \(to), which isn't a lasting mood")
            }
            if !m.lasting, !(m.settles.map(lastingNames.contains) ?? false) {
                throw CharacterPackError("\(source): \(m.id) has no meaning, and settles into no lasting mood")
            }
            if !m.lasting, !m.neighbours.all.isEmpty { throw CharacterPackError("\(source): \(m.id) has moves but no meaning") }
        }
        guard lastingNames.contains(defaultMood) else { throw CharacterPackError("\(source): default_mood \(defaultMood) isn't a lasting mood") }
        guard lastingNames.contains(startupMood) else { throw CharacterPackError("\(source): startup_mood \(startupMood) isn't a lasting mood") }

        options = lasting.map { Option($0.id, $0.meaning!, notFor: $0.notFor) }
        faces = moods.map { Option($0.id, $0.face, notFor: $0.faceNotFor) }
        byId = Dictionary(uniqueKeysWithValues: moods.map { ($0.id, $0) })
    }

    /// The lasting mood a word reads as: a lasting mood itself, a face-only
    /// one the mood it settles into, else nil.
    public func settled(_ id: String) -> String? {
        guard let m = byId[id] else { return nil }
        return m.lasting ? id : m.settles
    }

    static func mood(_ m: [String: Any], in source: String) throws -> Mood {
        guard let id = m["id"] as? String, let face = m["face"] as? String else {
            throw CharacterPackError("\(source): a mood without an id or a face")
        }
        let moves = m["moves"] as? [String: [String]] ?? [:]
        return Mood(id: id, meaning: m["meaning"] as? String, notFor: m["not_for"] as? String,
                    face: face, faceNotFor: m["face_not_for"] as? String,
                    neighbours: MoodGraph.Neighbours(ordinary: moves["ordinary"] ?? [], dramatic: moves["dramatic"] ?? []),
                    settles: m["settles"] as? String)
    }
}

extension CharacterPack {
    /// The process's character: the one `use(_:)` set, else the pack at
    /// `BOOP_CHARACTER`, else the one the repo last staged. It stops the
    /// process if that one doesn't load: nothing works without moods. A
    /// buddy of another pack is handed its own.
    public static var active: CharacterPack { store.get() }

    /// Sets the process's character. Call it once, before anything reads
    /// `active`.
    public static func use(_ character: CharacterPack) { store.set(character) }

    /// The same pack under another name: two buddies running one pack
    /// need two names.
    /// The scene of a work act at `moment` (`start`, `pass` or `fail`), if
    /// the pack draws one.
    public func actScene(_ kind: String, _ moment: String, name: String) -> String? {
        acts[kind]?[moment]?.replacingOccurrences(of: "{name}", with: name)
    }

    public func named(_ name: String) -> CharacterPack {
        var copy = self
        copy.name = name
        return copy
    }

    /// The pack with `id` beside the process's: in the app's bundle, which
    /// holds every pack, or in the repo's `characters/` (read staged when
    /// it's the one staged), for the tests and headless runs.
    public static func named(id: String, bundled: URL? = nil) throws -> CharacterPack {
        if active.id == id { return active }
        let folders = [bundled?.appendingPathComponent(id), staged(repo.appendingPathComponent("characters").appendingPathComponent(id))]
        for case let folder? in folders where FileManager.default.fileExists(atPath: folder.appendingPathComponent("character.json").path) {
            return try CharacterPack(directory: folder)
        }
        throw CharacterPackError("no character pack \(id): it isn't in the app or in characters/")
    }

    /// The pack a process uses when nothing chose one, by charactergen's
    /// rule for the pack in use (CHARACTER.md §2): `BOOP_CHARACTER`'s, else
    /// `CHARACTER`'s in `characters/`, else the one the repo this file was
    /// built from last staged (`.character-build/pack`). Every build stages
    /// first, so there's always one; without it, loading fails and says
    /// where it looked. A chosen pack that's the one staged is read staged.
    static var defaultDirectory: URL {
        let env = ProcessInfo.processInfo.environment
        if let path = env["BOOP_CHARACTER"], !path.isEmpty {
            return staged(URL(fileURLWithPath: path))
        }
        if let name = env["CHARACTER"], !name.isEmpty {
            return staged(repo.appendingPathComponent("characters").appendingPathComponent(name))
        }
        let pointer = repo.appendingPathComponent(".character-build/pack")
        guard let staged = try? String(contentsOf: pointer, encoding: .utf8) else { return pointer }
        return URL(fileURLWithPath: staged.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The repo this file was built from.
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../..").standardizedFileURL

    /// The staged pack (`.character-build/pack` names it) when it's
    /// `folder`'s, its files links into the pack's own; else `folder` as it
    /// is.
    public static func staged(_ folder: URL) -> URL {
        let pointer = repo.appendingPathComponent(".character-build/pack")
        guard let text = try? String(contentsOf: pointer, encoding: .utf8) else { return folder }
        let staged = URL(fileURLWithPath: text.trimmingCharacters(in: .whitespacesAndNewlines))
        func own(_ url: URL) -> String { url.appendingPathComponent("character.json").resolvingSymlinksInPath().path }
        return FileManager.default.fileExists(atPath: own(staged)) && own(staged) == own(folder) ? staged : folder
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

/// What's read from a pack's files, read once per pack: several buddies
/// may run different packs in one process.
final class PackCache<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Value] = [:]

    func get(_ directory: URL, _ read: (URL) -> Value) -> Value {
        lock.withLock {
            if let value = values[directory.path] { return value }
            let value = read(directory)
            values[directory.path] = value
            return value
        }
    }
}
