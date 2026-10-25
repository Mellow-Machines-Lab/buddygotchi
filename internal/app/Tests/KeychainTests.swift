import Foundation
import XCTest
@testable import BoopKit

/// Jev's key lives in the login Keychain, read and written
/// through `/usr/bin/security`. A fake `security` stands in, so the real
/// Keychain is never touched.
final class KeychainTests: XCTestCase {
    func testReadsTheKeyWithoutTheNewlineSecurityPrints() {
        let security = FakeSecurity(entry: "jev-123")
        XCTAssertEqual(Keychain.jevKey(account: "jev", security: security.tool), "jev-123")
        XCTAssertEqual(security.calls.map { $0.arguments },
                       [["find-generic-password", "-s", "com.boopcomputer.boop", "-a", "jev", "-w"]])
    }

    func testNoEntryIsNoKey() {
        XCTAssertNil(Keychain.jevKey(account: "jev", security: FakeSecurity(entry: nil).tool))
    }

    func testTheKeyGoesOnStdinAsHexAndNeverInTheArguments() {
        let security = FakeSecurity(entry: "old")
        XCTAssertTrue(Keychain.setJevKey("sk-new key", account: "jev", security: security.tool))
        XCTAssertEqual(security.entry, "sk-new key")
        XCTAssertEqual(security.calls.first?.arguments.first, "delete-generic-password", "the old entry goes first")
        for call in security.calls {
            XCTAssertFalse(call.arguments.joined(separator: " ").contains("sk-new"), "\(call.arguments)")
            XCTAssertFalse(call.input?.contains("sk-new") ?? false, "stdin carries it hex-encoded")
        }
    }

    func testSavingNothingRemovesTheEntry() {
        let security = FakeSecurity(entry: "old")
        XCTAssertTrue(Keychain.setJevKey("", account: "jev", security: security.tool))
        XCTAssertNil(security.entry)
        XCTAssertFalse(security.calls.contains { $0.arguments == ["-i"] }, "nothing is added")
    }

    func testASaveThatDidntLandIsReported() {
        let security = FakeSecurity(entry: nil)
        security.refusesToAdd = true
        XCTAssertFalse(Keychain.setJevKey("sk-new", account: "jev", security: security.tool))
    }

    /// A copy on another folder (`make dev`) reads and writes an
    /// entry of its own, named for its folder, never the everyday `jev`.
    func testACopyOnAnotherFolderKeepsAKeyOfItsOwn() {
        XCTAssertEqual(AppSettings.copyName(URL(fileURLWithPath: "/tmp/boop-onboarding")), "dev-boop-onboarding")
        XCTAssertEqual(AppSettings.copyName(URL(fileURLWithPath: "/tmp/my boop: 2-b")), "dev-myboop2-b")
        let home = "/tmp/someone"
        XCTAssertEqual(Keychain.account(for: AppSettings.defaultStateDir(home: home), home: home), "jev")
        let account = Keychain.account(for: URL(fileURLWithPath: "/tmp/boop-onboarding"), home: home)
        XCTAssertEqual(account, "dev-boop-onboarding")
        let security = FakeSecurity(entry: nil)
        XCTAssertTrue(Keychain.setJevKey("sk-new", account: account, security: security.tool))
        for call in security.calls {
            let words = call.arguments == ["-i"] ? (call.input ?? "").split(separator: " ").map(String.init) : call.arguments
            XCTAssertEqual(words.firstIndex(of: "-a").map { words[$0 + 1] }, "dev-boop-onboarding", "\(words)")
        }
    }
}

/// A `security` that keeps one entry in memory and records every call.
final class FakeSecurity: @unchecked Sendable {
    var entry: String?
    var refusesToAdd = false
    var calls: [(arguments: [String], input: String?)] = []
    private let lock = NSLock()

    init(entry: String?) { self.entry = entry }

    var tool: SecurityTool {
        SecurityTool { [self] arguments, input in
            lock.lock()
            defer { lock.unlock() }
            calls.append((arguments, input))
            switch arguments.first {
            case "find-generic-password":
                return entry.map { (0, $0 + "\n") } ?? (44, "")
            case "delete-generic-password":
                defer { entry = nil }
                return entry == nil ? (44, "") : (0, "")
            case "-i":
                // "add-generic-password -s … -a … -X <hex>\n"
                guard !refusesToAdd, let words = input?.split(separator: " "),
                      let at = words.firstIndex(of: "-X"), at + 1 < words.count else { return (0, "") }
                let hex = Array(words[at + 1].trimmingCharacters(in: .newlines))
                let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { UInt8(String(hex[$0...$0 + 1]), radix: 16) }
                entry = String(decoding: bytes, as: UTF8.self)
                return (0, "")
            default:
                return (1, "")
            }
        }
    }
}
