import AgentHooks
import Foundation
import XCTest
@testable import BoopKit

/// Registering the card server with each agent (`CardInstaller`), in a
/// throwaway home: Boop's entry goes in and out, and nothing else changes.
final class CardInstallerTests: XCTestCase {
    var home: URL!
    var cards: CardInstaller!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("cards-\(UUID().uuidString)")
        let server = home.appendingPathComponent("Library/Application Support/Boop/bin/boop-cards")
        try FileManager.default.createDirectory(at: server.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: server.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        cards = CardInstaller(home: home, serverPath: server.path)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// Claude Code: Boop's entry under `mcpServers` in `~/.claude.json`, as
    /// `claude mcp add --scope user` writes it, beside the person's own
    /// servers and every other key; installing twice writes nothing; taking
    /// it out leaves the rest.
    func testClaudeGetsItsEntryAndKeepsEverythingElse() throws {
        let url = home.appendingPathComponent(".claude.json")
        let theirs: [String: Any] = ["numStartups": 12, "mcpServers": ["notes": ["type": "stdio", "command": "/bin/notes"]]]
        try JSONSerialization.data(withJSONObject: theirs).write(to: url)
        XCTAssertFalse(cards.installed(.claude))
        try cards.install(.claude)
        XCTAssertTrue(cards.installed(.claude))
        let after = try json(url)
        XCTAssertEqual(after["numStartups"] as? Int, 12)
        let servers = try XCTUnwrap(after["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["notes"])
        let ours = try XCTUnwrap(servers["boop-cards"] as? [String: Any])
        XCTAssertEqual(ours["command"] as? String, cards.serverPath)
        XCTAssertEqual(ours["args"] as? [String], ["claude"])
        let written = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        try cards.install(.claude)
        try XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, written,
                       "already in: nothing written")
        try XCTAssertTrue(try cards.remove(.claude))
        try XCTAssertFalse(try cards.remove(.claude))
        let removed = try json(url)
        XCTAssertEqual((removed["mcpServers"] as? [String: Any])?.keys.sorted(), ["notes"])
        XCTAssertEqual(removed["numStartups"] as? Int, 12)
    }

    /// An entry left by a Boop that ran from elsewhere is put right.
    func testAnEntryPointingElsewhereIsPutRight() throws {
        let moved = CardInstaller(home: home, serverPath: "/Applications/Old.app/boop-cards")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["mcpServers": ["boop-cards": ["command": moved.serverPath]]])
            .write(to: home.appendingPathComponent(".claude.json"))
        XCTAssertFalse(cards.installed(.claude))
        try cards.install(.claude)
        XCTAssertTrue(cards.installed(.claude))
    }

    /// Codex: a `[mcp_servers.boop-cards]` table at the end of
    /// `config.toml`, the person's tables and comments kept; put right in
    /// place rather than declared twice, which Codex refuses to load; and
    /// taken out alone.
    func testCodexGetsItsTableAndKeepsEverythingElse() throws {
        let url = home.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let theirs = "model = \"o4\"\n\n[features]\nhooks = true # for Boop\n\n[mcp_servers.notes]\ncommand = \"/bin/notes\"\n"
        try theirs.write(to: url, atomically: true, encoding: .utf8)
        try cards.install(.codex)
        XCTAssertTrue(cards.installed(.codex))
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.hasPrefix(theirs), after)
        XCTAssertTrue(after.hasSuffix("\n[mcp_servers.boop-cards]\ncommand = \"\(cards.serverPath)\"\nargs = [\"codex\"]\n"), after)

        let moved = CardInstaller(home: home, serverPath: home.appendingPathComponent("elsewhere/boop-cards").path)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("elsewhere"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: moved.serverPath, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        try moved.install(.codex)
        let twice = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(twice.components(separatedBy: "[mcp_servers.boop-cards]").count, 2, "declared once")
        XCTAssertTrue(twice.contains(moved.serverPath))

        try XCTAssertTrue(try cards.remove(.codex))
        try XCTAssertEqual(try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .newlines),
                       theirs.trimmingCharacters(in: .newlines))
    }

    /// Nothing is registered while the server isn't in place, and a file
    /// that isn't JSON is left alone.
    func testItRefusesWithoutItsServerOrAFileItCantRead() throws {
        let missing = CardInstaller(home: home, serverPath: home.appendingPathComponent("nowhere").path)
        try XCTAssertThrowsError(try missing.install(.claude))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude.json").path))
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: home.appendingPathComponent(".claude.json"))
        try XCTAssertThrowsError(try cards.install(.claude))
        try XCTAssertEqual(try String(contentsOf: home.appendingPathComponent(".claude.json"), encoding: .utf8), "not json")
    }

    /// Uninstalling takes the entries and the server's copy out too.
    func testUninstallTakesTheCardsOut() throws {
        try cards.install(.claude)
        try cards.install(.codex)
        let state = home.appendingPathComponent("Library/Application Support/Boop")
        let result = Uninstall.run(installer: HookInstaller.boop(home: home, hookPath: state.appendingPathComponent("bin/agent-hook").path),
                                   cards: cards, stateDir: state, loginItem: LoginSwitch(on: false).item,
                                   environment: ["AGENT_HOOKS_DIR": home.appendingPathComponent(".agent-hooks").path])
        XCTAssertEqual(result.problems, [])
        XCTAssertTrue(result.removed.contains("claude's cards"), "\(result.removed)")
        XCTAssertTrue(result.removed.contains("codex's cards"), "\(result.removed)")
        XCTAssertFalse(cards.installed(.claude) || cards.installed(.codex))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cards.serverPath))
    }
}
