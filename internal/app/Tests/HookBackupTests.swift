import AgentHooks
import Foundation
import XCTest
@testable import BoopKit

final class HookBackupTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// The rule: the copy is of the agent's settings before Boop first
    /// changed them, made once and never replaced; an agent that isn't
    /// on this Mac has nothing copied.
    func testTheBackupIsTheFileFromBeforeBoopAndIsMadeOnce() throws {
        let state = home.appendingPathComponent("state")
        let settings = home.appendingPathComponent(".claude/settings.json")
        try Data(#"{"theirs":true}"#.utf8).write(to: settings)
        let installer = HookInstaller.boop(home: home, hookPath: "/nowhere/agent-hook")
        let made = HookBackup.once(installer, .claude, stateDir: state)
        XCTAssertEqual(made.map(\.lastPathComponent), ["claude-settings.json"])
        try Data(#"{"changed":true}"#.utf8).write(to: settings)
        XCTAssertEqual(HookBackup.once(installer, .claude, stateDir: state), [], "once only")
        let kept = try String(contentsOf: state.appendingPathComponent("backups/claude-settings.json"), encoding: .utf8)
        XCTAssertEqual(kept,
                       #"{"theirs":true}"#)
        XCTAssertEqual(HookBackup.once(installer, .codex, stateDir: state), [], "no Codex here")
    }
}
