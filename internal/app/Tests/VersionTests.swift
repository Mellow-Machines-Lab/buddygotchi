import Foundation
import XCTest
@testable import BoopKit

final class VersionTests: XCTestCase {
    /// The rule: VERSION is the only place the version is written, and the
    /// app reports exactly what it says.
    func testTheAppReportsTheVersionFile() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../VERSION").standardizedFileURL
        let written = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(BoopVersion.current, written)
        XCTAssertNotNil(BoopVersion.current.wholeMatch(of: /\d+\.\d+\.\d+/), "VERSION is MAJOR.MINOR.PATCH")
    }

    /// The Info.plist the binary carries has no version of its own to
    /// drift from VERSION.
    func testInfoPlistHasNoVersionOfItsOwn() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../app/Boop/Info.plist").standardizedFileURL
        let keys = try XCTUnwrap(NSDictionary(contentsOf: plist) as? [String: Any])
        XCTAssertNil(keys["CFBundleShortVersionString"])
        XCTAssertNil(keys["CFBundleVersion"])
    }

    /// The oldest macOS is written twice, in Package.swift for the build
    /// and in the Info.plist for macOS: they must agree.
    func testTheMinimumMacOSAgrees() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..")
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift").standardizedFileURL, encoding: .utf8)
        let built = try XCTUnwrap(manifest.firstMatch(of: /platforms: \[\.macOS\(\.v(\d+)\)\]/)).1
        let plist = root.appendingPathComponent("app/Boop/Info.plist").standardizedFileURL
        let keys = try XCTUnwrap(NSDictionary(contentsOf: plist) as? [String: Any])
        XCTAssertEqual(keys["LSMinimumSystemVersion"] as? String, "\(built).0")
    }
}
