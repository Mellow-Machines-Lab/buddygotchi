import Foundation
import XCTest

/// Text in the Mac app's views wraps, and its pane makes room or scrolls:
/// nothing is cut. `Boop --snapshots` checks the Overview by laying it out
/// with long values, which these tests can't, as `Boop` isn't a library.
final class PopoverTextTests: XCTestCase {
    static let views = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../app/Boop/Views").standardizedFileURL

    func testNoViewCutsItsText() throws {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: Self.views, includingPropertiesForKeys: nil))
        var read = 0
        for case let file as URL in walker where file.pathExtension == "swift" {
            read += 1
            let source = try String(contentsOf: file, encoding: .utf8)
            for limit in [".lineLimit(", ".truncationMode(", ".minimumScaleFactor("] {
                XCTAssertFalse(source.contains(limit), "\(file.lastPathComponent) uses \(limit): let its text wrap")
            }
        }
        XCTAssertGreaterThan(read, 5, "no views found at \(Self.views.path)")
    }
}
