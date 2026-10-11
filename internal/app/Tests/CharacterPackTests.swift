import Foundation
import XCTest
@testable import BoopKit
import MellowHarness

/// The character pack (characters/CHARACTER.md): Boop's own loads, holds
/// its sources' moods, and a broken pack says what's wrong.
final class CharacterPackTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardizedFileURL

    func testBoopsPackIsTheOneInUse() throws {
        try requireBoopsPack()
        let pack = try CharacterPack(directory: Self.repo.appendingPathComponent("characters/boop"))
        XCTAssertEqual(pack.id, "boop")
        XCTAssertEqual(pack.name, "Boop")
        XCTAssertEqual(pack.defaultMood, "calm")
        XCTAssertEqual(pack.personalities, Personality.allCases.map(\.rawValue))
        XCTAssertEqual(CharacterPack.active.moods, pack.moods)
        XCTAssertEqual(CharacterPack.active.moodsV2, pack.moodsV2)
    }

    /// CHARACTER.md §5: v2's 13 moods are the faces facegen draws, in the
    /// device's order, and every one has a face's wording.
    func testV2sMoodsAreTheFacesTheDeviceDraws() throws {
        try requireBoopsPack()
        XCTAssertEqual(MoodGraph.moods, FaceLoops.moods)
        XCTAssertEqual(ReactAction.expressions.map(\.name), MoodGraph.moods)
        XCTAssertEqual(MoodAction.moods.map(\.name), MoodGraph.moods)
    }

    /// CHARACTER.md §5: v3's moods are the slime design's host graph, in its
    /// order, with its timings (slimegen writes them), and each falls back
    /// to one of the 13 a pixel face draws.
    func testV3sMoodsAreTheSlimeDesigns() throws {
        try requireBoopsPack()
        let file = Self.repo.appendingPathComponent("characters/boop/design/slime-blob/emotion-graph.json")
        let graph = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let nodes = try XCTUnwrap(graph["nodes"] as? [String: [String: Any]])
        XCTAssertEqual(Set(MoodGraphV3.moods), Set(nodes.keys))
        XCTAssertEqual(MoodGraphV3.moods.count, 42)
        for (id, n) in nodes {
            let node = try XCTUnwrap(MoodGraphV3.nodes[id])
            XCTAssertEqual(node.meaning, n["meaning"] as? String, id)
            XCTAssertEqual(node.fallback, n["fallback"] as? String, id)
            XCTAssertEqual(node.moves.ordinary, n["ordinary"] as? [String], id)
            XCTAssertEqual(node.moves.dramatic, n["dramatic"] as? [String], id)
            XCTAssertTrue(MoodGraph.moods.contains(node.fallback), "\(id) falls back to a pixel mood")
        }
        let policy = try XCTUnwrap(graph["hostPolicy"] as? [String: Any])
        XCTAssertEqual(MoodGraphV3.ordinaryDwellMs, (policy["ordinaryDwellMs"] as? NSNumber)?.int64Value)
        XCTAssertEqual(MoodGraphV3.freshEvidenceMs, (policy["freshEvidenceMs"] as? NSNumber)?.int64Value)
    }

    /// A very long turn's finish may jump to these, and
    /// routine work never leads to fear, loneliness or affection.
    func testBoopsOutcomesAndQuietMoods() throws {
        try requireBoopsPack()
        XCTAssertEqual(Set(CharacterPack.active.outcomes["big_success"] ?? []), ["happy", "excited", "proud", "relieved"])
        XCTAssertEqual(Set(CharacterPack.active.outcomes["big_failure"] ?? []), ["sad", "wounded", "disappointed"])
        XCTAssertEqual(CharacterPack.active.quietNever, ["scared", "frightened", "lonely", "affectionate"])
        XCTAssertEqual(CharacterPack.active.aliases, ["cheerful": "happy"])
    }

    /// CHARACTER.md §3: a pack stands alone. Boop's and Pixel's each have
    /// every file the engine reads in their own folder: the pixel face's
    /// mac/faces.json, the voice's table and its pack.
    func testEachPackStandsAlone() throws {
        try requireBoopsPack()
        let boop = try CharacterPack(directory: Self.repo.appendingPathComponent("characters/boop"))
        let pixel = try CharacterPack(directory: Self.repo.appendingPathComponent("characters/pixel"))
        XCTAssertEqual(pixel.moods.map(\.id), MoodGraph.moods)
        XCTAssertEqual(pixel.startupMood, "happy")
        for pack in [boop, pixel] {
            for path in ["mac/faces.json", "mac/takes.tsv", "voice/voice.bin"] {
                XCTAssertTrue(FileManager.default.fileExists(atPath: pack.directory.appendingPathComponent(path).path), "\(pack.id) \(path)")
            }
        }
        XCTAssertEqual(FaceLoops.moods, pixel.moods.map(\.id))
        // The graph Pixel keeps is v2's.
        for m in pixel.moods { XCTAssertEqual(m.moves, MoodGraph.moves[m.id], m.id) }
    }

    /// CHARACTER.md §7, §8: Pixel stands on its own. Its steering has the
    /// guide, its personality and a file for each of its moods, every one
    /// within the budgets, it names the creature
    /// Pixel and never Boop, and it has a voice: the table and the pack
    /// it's the table of.
    func testPixelsSteeringIsComplete() throws {
        let folder = Self.repo.appendingPathComponent("characters/pixel")
        let pixel = try CharacterPack(directory: folder)
        let steering = try Steering(directory: folder.appendingPathComponent("steering"), pack: pixel)
        XCTAssertEqual(pixel.personalities, ["pixel"])
        XCTAssertNotNil(pixel.personalityAbout["pixel"])
        XCTAssertTrue(steering.guide.contains("Pixel"))
        for (path, text) in steering.files {
            XCTAssertFalse(text.contains("Boop"), path)
            let budget = path == "guide" ? Steering.Budget.guide : path.hasPrefix("personality/") ? Steering.Budget.personality : Steering.Budget.mood
            XCTAssertLessThanOrEqual(Steering.tokens(text), budget, path)
        }
        let table = try String(contentsOf: folder.appendingPathComponent("mac/takes.tsv"), encoding: .utf8)
        let version = try XCTUnwrap(table.split(separator: "\n").first { !$0.hasPrefix("#") })
        let pack = try Data(contentsOf: folder.appendingPathComponent("voice/voice.bin"))
        XCTAssertEqual(voicePackVersion(pack), String(version))
    }

    /// CHARACTER.md §4: a pack that leads to a mood it doesn't have is refused.
    func testABrokenPackSaysWhy() {
        let json: [String: Any] = [
            "id": "test", "name": "Test", "version": "1", "default_mood": "calm",
            "moods": [["id": "calm", "meaning": "Calm.", "moves": ["ordinary": ["happy"], "dramatic": []]]],
        ]
        XCTAssertEqual(refusal(json), "test: calm in moods leads to happy, which isn't a mood")
        var noDefault = json
        noDefault["moods"] = [["id": "happy", "meaning": "Happy."]]
        XCTAssertEqual(refusal(noDefault), "test: default_mood calm isn't a mood")
    }

    private func refusal(_ json: [String: Any]) -> String? {
        do { _ = try CharacterPack(json: json, from: "test"); return nil } catch { return "\(error)" }
    }
}
