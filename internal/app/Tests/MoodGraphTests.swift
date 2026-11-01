import Foundation
import XCTest
@testable import BoopKit

/// The mood graph (characters/CHARACTER.md §5): every pack has the
/// universal moods, each a face, and its own lasting ones and moves
/// between them.
final class MoodGraphTests: XCTestCase {
    /// Each pack in characters/ has exactly the universal moods, and its
    /// moves are a graph of its lasting moods the steering can walk: no
    /// move to itself, each move once, and every lasting mood reachable
    /// from every other by ordinary moves alone, so every one, a brief one
    /// included, can fade a step at a time to the resting mood.
    func testEveryPacksGraphIsWalkable() throws {
        let folder = CharacterPackTests.repo.appendingPathComponent("characters")
        let packs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("character.json").path) }
        XCTAssertFalse(packs.isEmpty)
        for dir in packs {
            let pack = try CharacterPack(directory: dir)
            XCTAssertEqual(Set(pack.moods.map(\.id)), Set(CharacterPack.universalMoods), pack.id)
            let moves = Dictionary(uniqueKeysWithValues: pack.lasting.map { ($0.id, $0.neighbours) })
            for (mood, m) in moves {
                XCTAssertFalse(m.all.contains(mood), "\(pack.id): staying isn't a move: \(mood)")
                XCTAssertEqual(Set(m.all).count, m.all.count, "\(pack.id): each move once: \(mood)")
            }
            for from in moves.keys {
                var seen: Set<String> = [from], queue = [from]
                while let m = queue.popLast() {
                    for n in moves[m]!.ordinary where seen.insert(n).inserted { queue.append(n) }
                }
                XCTAssertEqual(seen, Set(moves.keys), "\(pack.id): every lasting mood from \(from) by ordinary moves")
            }
        }
    }

    /// The active pack's graph is what `MoodGraph` reads, and a word that
    /// isn't a mood has none.
    func testMoodGraphReadsTheActivePack() {
        XCTAssertEqual(MoodGraph.moods, CharacterPack.active.lasting.map(\.id))
        XCTAssertEqual(Set(MoodGraph.neighbours.keys), Set(MoodGraph.moods))
        for m in CharacterPack.active.lasting { XCTAssertEqual(MoodGraph.neighbours[m.id], m.neighbours) }
        XCTAssertNil(MoodGraph.mood("tired"), "a face, not a lasting mood")
        XCTAssertNil(MoodGraph.mood("sulky"), "not a mood")
        XCTAssertNil(MoodGraph.neighbours["sulky"], "not a mood")
    }

    /// The universal list is one literal of quoted names, which
    /// characters/charactergen.py reads from its file.
    func testTheUniversalListIsWhatCharactergenReads() throws {
        let file = CharacterPackTests.repo.appendingPathComponent("app/BoopKit/Character/Moods.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let body = try XCTUnwrap(text.range(of: #"universalMoods = \[([^\]]*)\]"#, options: .regularExpression).map { String(text[$0]) })
        let names = body.matches(of: /"([a-z_]+)"/).map { String($0.1) }
        XCTAssertEqual(names, CharacterPack.universalMoods)
        XCTAssertEqual(Set(names).count, 42)
    }
}
