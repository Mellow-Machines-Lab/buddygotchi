import Foundation
import XCTest
@testable import BoopKit

final class LoginItemTests: XCTestCase {
    /// Only an app bundle can be a login item: `make run`'s bare binary,
    /// in a folder, gets a switch that says why it's off.
    func testOnlyAnAppBundleCanOpenAtLogin() throws {
        let bare = LoginItem.system(bundleURL: URL(fileURLWithPath: "/tmp/boop/.build/debug"))
        XCTAssertEqual(bare.state(), .unavailable)
        try bare.set(true)
        XCTAssertEqual(bare.state(), .unavailable)
    }
}
