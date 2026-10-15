import Foundation
import XCTest
@testable import BoopKit
import BoopDevKit
import MellowHarness

/// The character pack (characters/CHARACTER.md): Boop's own loads, holds
/// its sources' moods, and a broken pack says what's wrong.
final class CharacterPackTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardizedFileURL

    func testBoopsPackIsTheOneInUse() throws {
        try requirePack("boop")
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
        try requirePack("boop")
        XCTAssertEqual(MoodGraph.moods, FaceLoops.moods)
        XCTAssertEqual(ReactAction.expressions.map(\.name), MoodGraph.moods)
        XCTAssertEqual(MoodAction.moods.map(\.name), MoodGraph.moods)
    }

    /// A pixel face draws each mood it has as itself, whatever the pack:
    /// one with no `moods_v2` (Pixel's) once sent every mood as calm.
    func testAPixelFaceDrawsItsOwnMoodsAsThemselves() {
        for mood in FaceLoops.moods { XCTAssertEqual(MoodGraph.pixelFallback(mood), mood) }
    }

    /// CHARACTER.md §9: a mood the face doesn't draw draws its fallback,
    /// or its fallback's, and the resting mood when none of them is drawn.
    /// A new mood in a pack that keeps Pixel's face once drew the board's
    /// startup mood instead.
    func testAMoodTheFaceDoesntDrawDrawsItsFallback() throws {
        func mood(_ id: String, fallback: String? = nil) -> [String: Any] {
            ["id": id, "meaning": id, "moves": ["ordinary": [String](), "dramatic": [String]()]].merging(
                fallback.map { ["fallback": $0] } ?? [:]) { a, _ in a }
        }
        let pack = try CharacterPack(json: [
            "id": "pal", "name": "Pal", "version": "1", "default_mood": "calm", "personalities": ["pal"],
            "moods": [mood("calm"), mood("happy"), mood("dozy", fallback: "sleepy"), mood("sleepy", fallback: "calm"),
                      mood("loop", fallback: "lap"), mood("lap", fallback: "loop")],
        ], from: "test")
        let drawn = ["happy", "calm"]
        XCTAssertEqual(pack.mood("happy", drawnFrom: drawn), "happy")
        XCTAssertEqual(pack.mood("sleepy", drawnFrom: drawn), "calm")
        XCTAssertEqual(pack.mood("dozy", drawnFrom: drawn), "calm", "a fallback's fallback")
        XCTAssertEqual(pack.mood("loop", drawnFrom: drawn), "calm", "fallbacks in a circle end at the resting mood")
        XCTAssertEqual(pack.mood("nonsense", drawnFrom: drawn), "calm")
    }

    /// CHARACTER.md §5: v3's moods are the slime design's host graph, in its
    /// order, with its timings (slimegen writes them), and each falls back
    /// to one of the 13 a pixel face draws.
    func testV3sMoodsAreTheSlimeDesigns() throws {
        try requirePack("boop")
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
        try requirePack("boop")
        XCTAssertEqual(Set(CharacterPack.active.outcomes["big_success"] ?? []), ["happy", "excited", "proud", "relieved"])
        XCTAssertEqual(Set(CharacterPack.active.outcomes["big_failure"] ?? []), ["sad", "wounded", "disappointed"])
        XCTAssertEqual(CharacterPack.active.quietNever, ["scared", "frightened", "lonely", "affectionate"])
    }

    /// CHARACTER.md §3: a pack stands alone. Boop's and Pixel's each have
    /// every file the engine reads in their own folder: the pixel face's
    /// mac/faces.json, the voice's table and its pack.
    func testEachPackStandsAlone() throws {
        try requirePack("boop")
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
        XCTAssertEqual(PackCheck.voicePackVersion(pack), String(version))
    }

    /// Every pack in the repo plugs in, as `boopdev check` sees it: its
    /// files, its steering, its voice and its demos.
    func testEveryPackPassesTheCheck() throws {
        let folder = Self.repo.appendingPathComponent("characters")
        let packs = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("character.json").path) }
        XCTAssertFalse(packs.isEmpty)
        for pack in packs { XCTAssertEqual(PackCheck(pack).problems, [], pack.lastPathComponent) }
    }

    /// A pack that's missing what the engine needs says what, and a mood
    /// with no steering file is only a note: it reads as the resting mood's.
    func testTheCheckSaysWhatAPackLacks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pack-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let pixel = Self.repo.appendingPathComponent("characters/pixel")
        for path in ["character.json", "steering", "firmware", "mac"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: pixel.appendingPathComponent(path), to: dir.appendingPathComponent(path))
        }
        var check = PackCheck(dir)
        XCTAssertEqual(check.problems, ["mac/takes.tsv has no voice/voice.bin: keep both, or neither for no voice"])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("mac/takes.tsv"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("steering/mood/sad.md"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("steering/guide.md"))
        check = PackCheck(dir)
        XCTAssertEqual(check.problems.count, 1)
        XCTAssertTrue(check.problems[0].hasPrefix("guide.md is missing"), "\(check.problems)")
        try FileManager.default.copyItem(at: pixel.appendingPathComponent("steering/guide.md"), to: dir.appendingPathComponent("steering/guide.md"))
        check = PackCheck(dir)
        XCTAssertEqual(check.problems, [])
        XCTAssertTrue(check.notes.contains("steering/mood/sad.md is missing: sad reads as calm's"), "\(check.notes)")
    }

    /// CHARACTER.md §4: a pack that leads to a mood it doesn't have is refused.
    func testABrokenPackSaysWhy() {
        let json: [String: Any] = [
            "id": "test", "name": "Test", "version": "1", "default_mood": "calm", "personalities": ["test"],
            "moods": [["id": "calm", "meaning": "Calm.", "moves": ["ordinary": ["happy"], "dramatic": []]]],
        ]
        XCTAssertEqual(refusal(json), "test: calm in moods leads to happy, which isn't a mood")
        var noDefault = json
        noDefault["moods"] = [["id": "happy", "meaning": "Happy."]]
        XCTAssertEqual(refusal(noDefault), "test: default_mood calm isn't a mood")
        var badName = json
        badName["moods"] = [["id": "calm", "meaning": "Calm."], ["id": "very-happy", "meaning": "Happy."]]
        XCTAssertEqual(refusal(badName), "test: mood very-happy isn't a lower-case letter, then lower case, digits and _")
        badName["personalities"] = [String]()
        XCTAssertEqual(refusal(badName), "test: personalities is empty")
    }

    private func refusal(_ json: [String: Any]) -> String? {
        do { _ = try CharacterPack(json: json, from: "test"); return nil } catch { return "\(error)" }
    }
}
