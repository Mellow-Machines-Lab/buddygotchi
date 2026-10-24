import Foundation
import SQLite3

/// Small values Boop keeps across launches, as text by key, in one SQLite
/// table in the state directory: `boop.sqlite`'s
/// `kv`. Growth's XP and stage are the first; anything
/// else that needs a value or two kept goes here too, under a prefix of its
/// own (`growth.`). Each `set` replaces its keys in one transaction, so a
/// crash keeps all of them or none. Touched only on `home`.
public final class KeyValueStore {
    public static let fileName = "boop.sqlite"
    /// The shape of the file, in SQLite's `user_version`: 1 is the one
    /// `kv` table. A release that changes the shape raises it and moves an
    /// older file over when it opens one; a file from a newer release than
    /// this one is left alone (`init` refuses it, and the runtime keeps its
    /// values in memory for the launch).
    public static let schema = 1

    var db: OpaquePointer?

    /// Opens `boop.sqlite` in `directory`, making it and its table if
    /// they're missing; with none, a store in memory, kept only while it's
    /// open (tests, and a launch whose file won't open).
    public init(directory: URL?) throws {
        let path = directory.map { $0.appendingPathComponent(Self.fileName).path } ?? ":memory:"
        if let directory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let why = db.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close(db)
            db = nil
            throw Refusal("can't open \(path): \(why)")
        }
        let version = try userVersion()
        guard version <= Self.schema else {
            sqlite3_close(db)
            db = nil
            throw Refusal("\(path) is from a newer Boop (schema \(version), this one knows \(Self.schema)), so it's left alone")
        }
        try exec("PRAGMA journal_mode=WAL")
        try exec("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        // A file from before the version was kept (0) has schema 1's shape.
        if version < Self.schema { try exec("PRAGMA user_version = \(Self.schema)") }
    }

    deinit { sqlite3_close(db) }

    /// The value kept for `key`, or nil.
    public func string(_ key: String) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM kv WHERE key = ?", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, Self.transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }

    public func int(_ key: String) -> Int? { string(key).flatMap { Int($0) } }

    /// Keeps every value, replacing what each key had, all at once.
    public func set(_ values: [String: String]) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            for (key, value) in values.sorted(by: { $0.key < $1.key }) {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)", -1, &statement, nil)
                        == SQLITE_OK else { throw error() }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_text(statement, 1, key, -1, Self.transient)
                sqlite3_bind_text(statement, 2, value, -1, Self.transient)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw error() }
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// The file's `user_version`: 0 for a new file, or one from before it was kept.
    func userVersion() throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw error() }
        return Int(sqlite3_column_int(statement, 0))
    }

    func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    func error() -> Refusal { Refusal("sqlite: " + String(cString: sqlite3_errmsg(db))) }

    /// SQLite copies the text before the call returns.
    static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
