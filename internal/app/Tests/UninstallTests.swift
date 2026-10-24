import AgentHooks
import Foundation
import XCTest
@testable import BoopKit

final class UninstallTests: XCTestCase {
    var home: URL!
    var state: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-\(UUID().uuidString)")
        state = home.appendingPathComponent("Library/Application Support/Boop")
        try? FileManager.default.createDirectory(at: state.appendingPathComponent("bin"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// Uninstalling takes out Boop's hooks, its socket's listing, its copy
    /// of agent-hook and its login item, and nothing of anyone else's; and
    /// keeps Boop's memory, so a Boop installed again is the same one.
    func testUninstallTakesBoopOutAndKeepsItsMemory() throws {
        let fm = FileManager.default
        let client = state.appendingPathComponent("bin/agent-hook")
        fm.createFile(atPath: client.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        // Claude has a hook of the person's own beside Boop's; Codex isn't on this Mac.
        let claude = home.appendingPathComponent(".claude/settings.json")
        try fm.createDirectory(at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        let theirs: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
        try JSONSerialization.data(withJSONObject: theirs).write(to: claude)
        let installer = HookInstaller.boop(home: home, hookPath: client.path)
        try installer.install(.claude)
        XCTAssertEqual(installer.health(.claude), .installed)
        let environment = ["AGENT_HOOKS_DIR": home.appendingPathComponent(".agent-hooks").path]
        try HookSocket.register(state.appendingPathComponent("boop.sock").path, as: "boop", environment: environment)
        // Another app's listing stays.
        let other = HookSocket.directory(environment: environment) + "/other.sock"
        try fm.createSymbolicLink(atPath: other, withDestinationPath: "/tmp/other.sock")
        try Data("name: Mochi\n".utf8).write(to: state.appendingPathComponent(MemoryStore.longTermFile))
        let login = LoginSwitch(on: true)

        let result = Uninstall.run(installer: installer, stateDir: state, loginItem: login.item, environment: environment)

        XCTAssertEqual(result.problems, [])
        XCTAssertEqual(result.removed, ["claude's hooks", "the socket's listing", "agent-hook", "opening at login"])
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: claude)) as? [String: Any])
        let stop = try XCTUnwrap((after["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 1, "only the person's own Stop hook is left")
        XCTAssertFalse(fm.fileExists(atPath: home.appendingPathComponent(".codex").path), "nothing written for an agent that isn't here")
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: HookSocket.directory(environment: environment) + "/boop.sock"))
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: other))
        XCTAssertFalse(fm.fileExists(atPath: client.path))
        XCTAssertFalse(fm.fileExists(atPath: state.appendingPathComponent("bin").path))
        XCTAssertFalse(login.on)
        XCTAssertTrue(fm.fileExists(atPath: state.appendingPathComponent(MemoryStore.longTermFile).path), "the memory stays")
    }

    /// Run again, with everything gone already, it finds nothing to do.
    func testUninstallingTwiceChangesNothing() {
        let installer = HookInstaller.boop(home: home, hookPath: state.appendingPathComponent("bin/agent-hook").path)
        let environment = ["AGENT_HOOKS_DIR": home.appendingPathComponent(".agent-hooks").path]
        let result = Uninstall.run(installer: installer, stateDir: state, loginItem: LoginSwitch(on: false).item,
                                   environment: environment)
        XCTAssertEqual(result, Uninstall.Result())
    }
}

/// A login item that's only a switch.
final class LoginSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool
    init(on: Bool) { value = on }
    var on: Bool { lock.withLock { value } }
    var item: LoginItem {
        LoginItem(state: { [self] in on ? .on : .off }, set: { [self] new in lock.withLock { value = new } })
    }
}
