import Foundation
import XCTest
@testable import BoopKit

/// The show's check (`Show.problems`, documentation/design/screen-guide.md,
/// "The show"): what's wrong goes back to the agent in words it can act on.
final class ShowTests: XCTestCase {
    let good = """
        <svg viewBox="0 0 420 190" xmlns="http://www.w3.org/2000/svg">\
        <text x="0" y="16" font-size="14" fill="#9aa0a8">p95 ms</text>\
        <rect x="20" y="40" width="60" height="126" fill="#9aa0a8"/>\
        <rect x="84" y="106" width="60" height="60" fill="currentColor"/>\
        <line x1="0" y1="166" x2="420" y2="166" stroke="#e8e6e0" stroke-width="3"/>\
        </svg>
        """

    /// Pins the rules: 420 by 190, 4 kB, text 14 px, lines 3 px, 12 words.
    func testTheRules() {
        XCTAssertEqual([Show.width, Show.height, Show.svgMost], [420, 190, 4096])
        XCTAssertEqual([Show.textLeast, Show.lineLeast], [14, 3])
        XCTAssertEqual([Show.wordsMost, Show.headlineMost], [12, 28])
        XCTAssertEqual(Show.problems(svg: good), [])
    }

    func testWhatsWrongIsSaid() {
        func problems(_ svg: String) -> String { Show.problems(svg: svg).joined(separator: "; ") }
        XCTAssertTrue(problems(good.replacingOccurrences(of: "0 0 420 190", with: "0 0 100 100")).contains("viewBox"))
        XCTAssertTrue(problems(good.replacingOccurrences(of: "#9aa0a8", with: "#123456")).contains("#123456"))
        XCTAssertTrue(problems(good.replacingOccurrences(of: "font-size=\"14\"", with: "font-size=\"10\"")).contains("14 px"))
        XCTAssertTrue(problems(good.replacingOccurrences(of: "stroke-width=\"3\"", with: "stroke-width=\"1\"")).contains("3 px"))
        XCTAssertTrue(problems(good.replacingOccurrences(of: "</svg>", with: "<image href=\"x.png\"/></svg>")).contains("image"))
        XCTAssertTrue(problems(good.replacingOccurrences(of: "</svg>", with: "<script>x</script></svg>")).contains("script"))
        XCTAssertTrue(problems("<svg").contains("well-formed"))
        let wordy = good.replacingOccurrences(of: "p95 ms", with: String(repeating: "word ", count: 13))
        XCTAssertTrue(problems(wordy).contains("12 words"))
        XCTAssertTrue(problems(String(repeating: " ", count: 5000) + good).contains("4096"))
    }

    /// The tool is offered only while the show is tried.
    func testTheToolSaysItsRules() {
        let description = CardTool.showTool["description"] as? String ?? ""
        for rule in ["0 0 420 190", "14 px", "3 px", "#5fae5a", "currentColor", "12 words", "28 characters"] {
            XCTAssertTrue(description.contains(rule), rule)
        }
        XCTAssertFalse(CardTool.tools.contains { $0["name"] as? String == "show" }, "not yet among the tools every agent sees")
    }
}
