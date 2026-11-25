import Foundation
import MellowHarness

/// The character pack the engine runs (characters/CHARACTER.md): who the
/// creature is, its faces and its lasting moods. The engine takes every mood
/// from here and names none itself. There's one per process, chosen at
/// start (§2):
/// - The app loads its bundled pack with `use(_:)`.
/// - Anything that reads `active` before that (the tests, `boopdev`) gets
///   the pack at `BOOP_CHARACTER`, else the one the repo last staged.
public struct CharacterPack: Sendable {
    /// One face the board draws (CHARACTER.md §5), under the name the wire
    /// calls a mood: the emotion of a Moment, or a lasting mood's look.
    public struct Mood: Sendable, Equatable {
        public let id: String
        /// What its face means for one reaction: the reaction's face option.
        public let face: String
        public let faceNotFor: String?
        /// The lasting mood a word for this face reads as; nil for a
        /// lasting mood's own face.
        public let settles: String?
    }

    /// One mood the creature settles into (CHARACTER.md §5): the `mood`
    /// question's option, with the faces it rests in and how it fades.
    public struct Lasting: Sendable, Equatable {
        public let id: String
        /// When the creature is in it.
        public let meaning: String
        public let notFor: String?
        /// The faces it rests in, one for each level, mildest first: its own
        /// for most; a levelled mood's `levels`, which code counts
        /// (`MoodLevel`).
        public let faces: [String]
        public let fade: Fade?

        /// Whether code counts a level for it.
        public var levelled: Bool { faces.count > 1 }
        /// Its resting face at `level`, from 1.
        public func face(level: Int) -> String { faces[max(0, min(faces.count - 1, level - 1))] }
    }

    /// How a lasting mood settles by itself, on the Mac's clock (`MoodFade`):
    /// after `minutes` in it, to `to` (the resting mood for none); a
    /// levelled mood a level down first. `holds` stops the clock: it
    /// starts again once that's over.
    public struct Fade: Sendable, Equatable {
        public enum Hold: String, Sendable { case working, away }
        public let minutes: Int
        public let to: String?
        public let holds: Hold?
    }

    /// The pack's folder: its steering, and what the app reads at run time.
    public let directory: URL
    public let id: String
    /// What the creature is called: the pack's name, or a buddy's own
    /// (`named(_:)`).
    public internal(set) var name: String
    /// The name the pack itself gives it, which the firmware it's built into
    /// knows: `name` differs when you've given it one of your own.
    public let ownName: String
    /// What its face does to pass the time and between Doings, by the name
    /// the face says (`Face::passing`), from its `mac/passing.tsv`, for the
    /// popover alone. `ofDoing` for a change of Doing, with no "to pass the
    /// time" after it. Empty for a pack with none.
    public let passing: [String: Passing]
    public struct Passing: Equatable, Sendable {
        public var words: String
        public var ofDoing: Bool
    }
    public let version: String
    /// The resting mood: a new state folder starts in it, every mood fades
    /// toward it, and a word that isn't a mood reads as it.
    public let defaultMood: String
    /// The words of its voice that say a fix: never where no failed check
    /// came first (`claims_a_fix`).
    public let claimsAFix: Set<String>
    /// The few moments that always speak, each from takes of its own
    /// (`skits`, `Skits.play`): none for a pack without, whose Moments are
    /// silent. A skit may invite one touch after it.
    public let skits: [Skit]
    /// What the board shows before the Mac sends a mood (CHARACTER.md §4):
    /// the pack's `startup_mood`, else its default mood.
    public let startupMood: String
    /// Every face the pack draws, in its order: the emotion question's
    /// options, and the names the board knows.
    public let moods: [Mood]
    /// The moods the creature settles into, in the pack's order: the mood
    /// question's options.
    public let lasting: [Lasting]
    /// What the pack draws for each work act, by kind and by `start`, `pass`
    /// or `fail`, as Jev reads it, with `{name}` for the creature's name
    /// (CHARACTER.md §4). Empty for a pack that draws none.
    public let acts: [String: [String: String]]

    // Derived once, since the mood output reads them on every pass.
    let options: [Option]
    let faces: [Option]
    let byId: [String: Mood]
    let lastingById: [String: Lasting]
}

extension CharacterPack {
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
    /// a pack: a key missing, a face or a mood named twice, a lasting mood
    /// with no face to rest in, a default mood or a fade's end that isn't a
    /// lasting one, a face that settles into none, or a skit with no id, a
    /// slot that isn't one, a slot another skit has too, or an invite whose
    /// pose, touch or payoff isn't one. Everything the
    /// pack has is in the one folder.
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
        ownName = name
        var passing: [String: Passing] = [:]
        if let rows = try? String(contentsOf: directory.appendingPathComponent("mac/passing.tsv"), encoding: .utf8) {
            for row in rows.split(separator: "\n") where !row.hasPrefix("#") {
                let cols = row.split(separator: "\t")
                if cols.count == 3 { passing[String(cols[1])] = Passing(words: String(cols[2]), ofDoing: cols[0] == "doing") }
            }
        }
        self.passing = passing
        version = try string("version")
        defaultMood = try string("default_mood")
        startupMood = json["startup_mood"] as? String ?? defaultMood
        claimsAFix = Set(json["claims_a_fix"] as? [String] ?? [])
        skits = try CharacterPack.skits(json["skits"] as? [[String: Any]] ?? [], in: source)
        moods = try (json["moods"] as? [[String: Any]] ?? []).map { try CharacterPack.mood($0, in: source) }
        acts = json["acts"] as? [String: [String: String]] ?? [:]
        // The board reports the id, and the firmware names each mood in code.
        guard id.wholeMatch(of: /[a-z0-9-]+/) != nil else { throw CharacterPackError("\(source): id \(id) isn't lower case, digits and -") }
        let names = Set(moods.map(\.id))
        guard !moods.isEmpty else { throw CharacterPackError("\(source): moods names no face") }
        guard names.count == moods.count else { throw CharacterPackError("\(source): moods names a face twice") }
        guard let rows = json["lasting"] as? [[String: Any]] else { throw CharacterPackError("\(source): lasting is missing") }
        lasting = try rows.map { try CharacterPack.lasting($0, in: source) }
        let lastingNames = Set(lasting.map(\.id))
        guard lastingNames.count == lasting.count else { throw CharacterPackError("\(source): lasting names a mood twice") }
        for l in lasting {
            for face in l.faces where !names.contains(face) {
                throw CharacterPackError("\(source): \(l.id) rests in \(face), which isn't one of the pack's faces")
            }
            if let fade = l.fade {
                guard fade.minutes > 0 else { throw CharacterPackError("\(source): \(l.id) fades after no minutes") }
                if let to = fade.to, !lastingNames.contains(to) || to == l.id {
                    throw CharacterPackError("\(source): \(l.id) fades to \(to), which isn't another lasting mood")
                }
            }
        }
        for m in moods where !lastingNames.contains(m.id) {
            guard let settles = m.settles, lastingNames.contains(settles) else {
                throw CharacterPackError("\(source): \(m.id) is no lasting mood, and settles into none")
            }
        }
        guard lastingNames.contains(defaultMood) else { throw CharacterPackError("\(source): default_mood \(defaultMood) isn't a lasting mood") }
        guard lastingNames.contains(startupMood) else { throw CharacterPackError("\(source): startup_mood \(startupMood) isn't a lasting mood") }
        let resting = defaultMood
        if let fade = lasting.first(where: { $0.id == resting })?.fade {
            throw CharacterPackError("\(source): default_mood \(resting) fades after \(fade.minutes) min, and it's where moods settle")
        }

        options = lasting.map { Option($0.id, $0.meaning, notFor: $0.notFor) }
        faces = moods.map { Option($0.id, $0.face, notFor: $0.faceNotFor) }
        byId = Dictionary(uniqueKeysWithValues: moods.map { ($0.id, $0) })
        lastingById = Dictionary(uniqueKeysWithValues: lasting.map { ($0.id, $0) })
    }

    /// The lasting mood a word reads as: a lasting mood itself, a face
    /// the mood it settles into, else nil.
    public func settled(_ id: String) -> String? {
        lastingById[id] != nil ? id : byId[id]?.settles
    }

    /// One lasting mood, or nil for a word that isn't one.
    public func lasting(_ id: String) -> Lasting? { lastingById[id] }

    /// The face the lasting mood `id` rests in at `level` (from 1; only a
    /// levelled mood's counts): what the board and the popover show.
    public func restingFace(_ id: String, level: Int = 1) -> String {
        lastingById[id]?.face(level: level) ?? id
    }

    /// The pack's skits, each with an id and slots that are the rules'
    /// (`RulesBrain.Slot`), no slot in two, and maybe an invite.
    static func skits(_ rows: [[String: Any]], in source: String) throws -> [Skit] {
        var taken: Set<RulesBrain.Slot> = []
        return try rows.map { row in
            guard let id = row["id"] as? String, !id.isEmpty else { throw CharacterPackError("\(source): a skit without an id") }
            let slots = try (row["slots"] as? [String] ?? []).map { name in
                guard let slot = RulesBrain.Slot(rawValue: name) else { throw CharacterPackError("\(source): skit \(id) plays at \(name), which isn't a slot") }
                guard taken.insert(slot).inserted else { throw CharacterPackError("\(source): skit \(id) plays at \(name), which another skit has") }
                return slot
            }
            let invite = try row["invite"].map { value in
                guard let fields = value as? [String: Any] else { throw CharacterPackError("\(source): skit \(id)'s invite isn't an object") }
                return try CharacterPack.invite(fields, of: id, in: source)
            }
            return Skit(id: id, slots: slots, invite: invite)
        }
    }

    /// A skit's invite: a pose, a touch and a payoff, each one the board
    /// plays (`Skit.Invite`).
    static func invite(_ row: [String: Any], of skit: String, in source: String) throws -> Skit.Invite {
        func read<T: RawRepresentable>(_ key: String, _: T.Type) throws -> T where T.RawValue == String {
            guard let name = row[key] as? String, let value = T(rawValue: name) else {
                throw CharacterPackError("\(source): skit \(skit)'s invite has \(key) \(row[key].map { "\($0)" } ?? "none"), which isn't one")
            }
            return value
        }
        return Skit.Invite(pose: try read("pose", Skit.Invite.Pose.self), touch: try read("touch", Skit.Invite.Touch.self),
                           payoff: try read("payoff", Skit.Invite.Payoff.self))
    }

    static func mood(_ m: [String: Any], in source: String) throws -> Mood {
        guard let id = m["id"] as? String, let face = m["face"] as? String else {
            throw CharacterPackError("\(source): a face without an id or a face")
        }
        return Mood(id: id, face: face, faceNotFor: m["face_not_for"] as? String, settles: m["settles"] as? String)
    }

    static func lasting(_ m: [String: Any], in source: String) throws -> Lasting {
        guard let id = m["id"] as? String, let meaning = m["meaning"] as? String else {
            throw CharacterPackError("\(source): a lasting mood without an id or a meaning")
        }
        var fade: Fade?
        if let f = m["fade"] as? [String: Any] {
            guard let minutes = f["minutes"] as? Int else { throw CharacterPackError("\(source): \(id)'s fade has no minutes") }
            let holds = f["holds"] as? String
            if let holds, Fade.Hold(rawValue: holds) == nil { throw CharacterPackError("\(source): \(id)'s fade holds \(holds), not working or away") }
            fade = Fade(minutes: minutes, to: f["to"] as? String, holds: holds.flatMap(Fade.Hold.init))
        }
        let levels = m["levels"] as? [String] ?? []
        return Lasting(id: id, meaning: meaning, notFor: m["not_for"] as? String, faces: levels.isEmpty ? [id] : levels, fade: fade)
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
