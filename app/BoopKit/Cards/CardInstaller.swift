import AgentHooks
import Foundation

/// Registers `boop-cards`, the tool server agents hand Boop cards through,
/// with each agent, beside the hooks: an agent whose hooks Boop installs
/// gets the server too, and loses it with them. The entry is Boop's alone,
/// named `boop-cards`, and runs the copy in the state directory, as the
/// hooks run theirs, so a rebuilt or moved app doesn't break it.
///
/// - Claude Code: `mcpServers.boop-cards` in `~/.claude.json`, which is
///   what `claude mcp add --scope user` writes.
/// - Codex: a `[mcp_servers.boop-cards]` table in `~/.codex/config.toml`.
///
/// Each change rewrites only the file it must, and only when the entry
/// isn't already as it should be. Every other key stays as it was.
public struct CardInstaller: Sendable {
    public static let name = "boop-cards"
    public let home: URL
    /// The `boop-cards` the entries run.
    public let serverPath: String

    public init(home: URL, serverPath: String) {
        self.home = home
        self.serverPath = serverPath
    }

    var claudeURL: URL { home.appendingPathComponent(".claude.json") }
    var codexURL: URL { home.appendingPathComponent(".codex/config.toml") }

    public var serverInPlace: Bool { FileManager.default.isExecutableFile(atPath: serverPath) }

    /// Whether `agent` has the entry, running this server for that agent.
    public func installed(_ agent: Agent) -> Bool {
        switch agent {
        case .claude:
            let servers = (try? readClaude())?["mcpServers"] as? [String: Any]
            return (servers?[Self.name] as? NSDictionary)?.isEqual(to: claudeEntry) == true
        case .codex:
            return ((try? readCodex()) ?? "").contains(codexTable)
        }
    }

    /// Adds the entry, or puts it right. Refuses while the server isn't in
    /// place, so an agent never starts one that isn't there.
    public func install(_ agent: Agent) throws {
        guard serverInPlace else { throw HookInstaller.Refusal("there's no \(Self.name) at \(serverPath)") }
        guard !installed(agent) else { return }
        switch agent {
        case .claude:
            var root = try readClaude()
            var servers = root["mcpServers"] as? [String: Any] ?? [:]
            servers[Self.name] = claudeEntry
            root["mcpServers"] = servers
            try writeClaude(root)
        case .codex:
            try write(Self.removingTable(from: readCodex()).withTable(codexTable), to: codexURL)
        }
    }

    /// Takes the entry out, wherever it points, and nothing else. True when
    /// there was one.
    @discardableResult
    public func remove(_ agent: Agent) throws -> Bool {
        switch agent {
        case .claude:
            var root = try readClaude()
            guard var servers = root["mcpServers"] as? [String: Any], servers[Self.name] != nil else { return false }
            servers[Self.name] = nil
            root["mcpServers"] = servers
            try writeClaude(root)
        case .codex:
            let toml = try readCodex()
            let out = Self.removingTable(from: toml)
            guard out != toml else { return false }
            try write(out, to: codexURL)
        }
        return true
    }

    // MARK: Claude Code

    var claudeEntry: [String: Any] { ["type": "stdio", "command": serverPath, "args": ["claude"], "env": [String: Any]()] }

    func readClaude() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: claudeURL), !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstaller.Refusal(".claude.json isn't a JSON object")
        }
        return root
    }

    func writeClaude(_ root: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
        data.append(0x0A)
        try data.write(to: claudeURL.resolvingSymlinksInPath(), options: .atomic)
    }

    // MARK: Codex

    static let codexHeader = "[mcp_servers.\(name)]"

    /// The table, as it's written: a TOML basic string, with `"` and `\`
    /// escaped.
    var codexTable: String {
        let quoted = { (s: String) in "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return "\(Self.codexHeader)\ncommand = \(quoted(serverPath))\nargs = [\"codex\"]\n"
    }

    func readCodex() throws -> String {
        do { return try String(contentsOf: codexURL, encoding: .utf8) } catch CocoaError.fileReadNoSuchFile { return "" }
    }

    /// `toml` without Boop's table: from its header to the next table's.
    static func removingTable(from toml: String) -> String {
        var out: [String] = [], inside = false
        for line in toml.components(separatedBy: "\n") {
            let bare = line.trimmingCharacters(in: .whitespaces)
            if bare.hasPrefix("[") { inside = bare.filter { !$0.isWhitespace } == codexHeader }
            if !inside { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url.resolvingSymlinksInPath(), atomically: true, encoding: .utf8)
    }
}

private extension String {
    /// With `table` at the end, a blank line before it.
    func withTable(_ table: String) -> String {
        var out = self
        while out.hasSuffix("\n\n") { out.removeLast() }
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        return out + (out.isEmpty ? "" : "\n") + table
    }
}
