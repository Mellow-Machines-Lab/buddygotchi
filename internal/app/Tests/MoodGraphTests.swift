import Foundation
import XCTest
@testable import BoopKit

/// The mood graph: the owner's approved moves
/// between Boop's 13 moods.
final class MoodGraphTests: XCTestCase {
    // Pixel's graph, which Boop's pack keeps as its v2.
    override func setUpWithError() throws { try requirePack("pixel", "boop") }
    /// `MoodGraph` is the owner's approved graph,
    /// characters/pixel/design/boop-mood-spectrum-v2/mood-graph.json, move for
    /// move and in its order: 13 moods in the device's order, 98 moves, at
    /// most eight from any mood, and every mood reachable from every other
    /// by ordinary moves alone.
    func testTheMoodGraphIsTheOwnersGraph() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../characters/pixel/design/boop-mood-spectrum-v2/mood-graph.json").standardizedFileURL
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let nodes = try XCTUnwrap(json["nodes"] as? [String: [String: [String]]])
        XCTAssertEqual(Set(nodes.keys), Set(MoodGraph.moods))
        for (mood, moves) in nodes {
            XCTAssertEqual(MoodGraph.moves[mood], MoodGraph.Moves(ordinary: moves["ordinary"]!, dramatic: moves["dramatic"]!), mood)
        }
        XCTAssertEqual(Set(MoodGraph.moves.keys), Set(MoodGraph.moods))
        XCTAssertEqual(Set((json["retainedArtMoods"] as? [String] ?? []) + (json["newArtMoods"] as? [String] ?? [])),
                       Set(MoodGraph.moods))
        XCTAssertEqual(MoodGraph.moves.values.map(\.all.count).reduce(0, +), 98)
        XCTAssertLessThanOrEqual(MoodGraph.moves.values.map(\.all.count).max()!, 8)
        for (mood, moves) in MoodGraph.moves {
            XCTAssertFalse(moves.all.contains(mood), "staying isn't a move: \(mood)")
            XCTAssertEqual(Set(moves.all).count, moves.all.count, "each move once: \(mood)")
        }
        // Strongly connected on ordinary moves.
        for from in MoodGraph.moods {
            var seen: Set<String> = [from], queue = [from]
            while let m = queue.popLast() {
                for n in MoodGraph.moves[m]!.ordinary where seen.insert(n).inserted { queue.append(n) }
            }
            XCTAssertEqual(seen, Set(MoodGraph.moods), "every mood from \(from) by ordinary moves")
        }
        XCTAssertTrue(MoodGraph.moves["grumpy"]!.all.contains("sad"))
        XCTAssertTrue(MoodGraph.moves["grumpy"]!.dramatic.contains("sad"))
        XCTAssertFalse(MoodGraph.moves["grumpy"]!.dramatic.contains("irritated"))
        XCTAssertFalse(MoodGraph.moves["excited"]!.all.contains("calm"), "excited goes through happy")
        XCTAssertFalse(MoodGraph.moves["grumpy"]!.all.contains("grumpy"), "staying isn't a move")
        XCTAssertNil(MoodGraph.moves["sulky"], "not a mood")
    }
}
