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
        XCTAssertEqual([Show.wordsMost, Show.headlineMost], [16, 28])
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
        // Text that runs off the side, as an agent's did on the board: 36
        // characters at 18 px from x 40 reach about 429 px.
        let long = ##"<text x="40" y="100" font-size="18" fill="#e8e6e0">2 slug tests fail (pre-existing bug)</text>"##
        XCTAssertTrue(problems(good.replacingOccurrences(of: "</svg>", with: long + "</svg>")).contains("runs off"))
        let fits = ##"<text x="210" y="100" font-size="18" text-anchor="middle" fill="#e8e6e0">2 old slug tests fail</text>"##
        XCTAssertEqual(problems(good.replacingOccurrences(of: "</svg>", with: fits + "</svg>")), "")
        let wordy = good.replacingOccurrences(of: "p95 ms", with: String(repeating: "word ", count: 17))
        XCTAssertTrue(problems(wordy).contains("16 words"))
        XCTAssertTrue(problems(String(repeating: " ", count: 5000) + good).contains("4096"))
    }

    /// Every agent sees the tool, and is told firmly to use it.
    func testTheToolSaysItsRules() {
        let description = CardTool.showTool["description"] as? String ?? ""
        for rule in ["0 0 420 190", "14 px", "3 px", "#5fae5a", "currentColor", "16 words", "28 characters"] {
            XCTAssertTrue(description.contains(rule), rule)
        }
        XCTAssertTrue(CardTool.tools.contains { $0["name"] as? String == "show" })
        XCTAssertTrue(CardTool.instructions.contains("call `show` once"))
    }

    /// A show goes over the socket checked, and checked again; the core
    /// keeps the latest for the popover 30 minutes, and records only its
    /// headline.
    func testAShowReachesThePopover() throws {
        XCTAssertEqual(Core.showKeptMs, 1_800_000)
        let made = Show.make(["headline": "search is 2.1x faster", "svg": good, "link": "https://example.com/r"])
        let show = try XCTUnwrap(made.show)
        XCTAssertEqual(made.problems, [])
        let line = try XCTUnwrap(JSONSerialization.jsonObject(with: CardTool.line(show, process: nil)) as? [String: Any])
        XCTAssertEqual(CardTool.readShow(line)?.show, show)
        XCTAssertNil(CardTool.readShow(["show": ["headline": "x", "svg": "<svg"]]), "checked again as it's read")
        XCTAssertNil(Show.make(["headline": "x"]).show, "a picture is needed")
        let rig = CoreRig()
        rig.pipeline.show(show, process: nil, at: rig.now)
        XCTAssertNil(rig.core.shown(at: rig.now), "nobody's: dropped")
        rig.send(.turnStart)
        rig.pipeline.show(show, process: nil, at: rig.now)
        XCTAssertEqual(rig.core.shown(at: rig.now)?.show.headline, "search is 2.1x faster")
        let recorded = rig.pipeline.transcript.events.last { $0.type == .card }
        XCTAssertEqual(recorded?["text"]?.string, "search is 2.1x faster")
        XCTAssertFalse(recorded?.jsonLine.contains("<svg") ?? true, "the picture stays out of the log")
        rig.wait(Core.showKeptMs, every: 60_000)
        XCTAssertNil(rig.core.shown(at: rig.now))
    }
}
