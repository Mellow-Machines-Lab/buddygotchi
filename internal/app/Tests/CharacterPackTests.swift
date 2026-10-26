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
    }

    /// CHARACTER.md §5, §9: every mood has a face's wording (its meaning
    /// when it has none), an option for the mood question, and designs on
    /// the pixel face, which draws all of them (the Pixel pack's
    /// mac/faces.json names the moods its faces.h does).
    func testEveryMoodHasAFaceAndDesigns() throws {
        XCTAssertEqual(ReactOutput.expressions.map(\.name), MoodGraph.moods)
        XCTAssertEqual(MoodOutput.moods.map(\.name), MoodGraph.moods)
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("characters/pixel/mac/faces.json"))
        let faces = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let moods = try XCTUnwrap(faces["moods"] as? [String])
        XCTAssertEqual(Set(moods), Set(CharacterPack.universalMoods))
    }

    /// The popover's still face (the pack's mac/faces.json) cross-fades
    /// into a new one over the board's dissolve between pictures
    /// (rig::kFadeMs in firmware/src/render/rig/rig.h), so the two change
    /// faces in step: changing either fails here.
    func testThePopoversFaceFadesAsLongAsTheBoards() throws {
        let rig = try String(contentsOf: Self.repo.appendingPathComponent("firmware/src/render/rig/rig.h"), encoding: .utf8)
        let face = try String(contentsOf: Self.repo.appendingPathComponent("app/Boop/Views/BoopFace.swift"), encoding: .utf8)
        let board = try XCTUnwrap(rig.firstMatch(of: /kFadeMs = ([0-9]+);/).flatMap { Int($0.1) })
        let mac = try XCTUnwrap(face.firstMatch(of: /let fade = Animation\.timingCurve\(.*duration: ([0-9.]+)\)/)
            .flatMap { Double($0.1) })
        XCTAssertEqual(board, 200)
        XCTAssertEqual(Int((mac * 1000).rounded()), board)
    }

    /// The board's finish marks, a success's sage tick and a failure's clay
    /// cross (firmware/src/render/palette.h), are the Mac's own inks for
    /// them on dark (Theme.swift's `sageInkDark` and `clayInkDark`), so the
    /// two show a result alike: changing either fails here.
    func testTheBoardsFinishMarksAreTheMacsInks() throws {
        let palette = try String(contentsOf: Self.repo.appendingPathComponent("firmware/src/render/palette.h"), encoding: .utf8)
        let theme = try String(contentsOf: Self.repo.appendingPathComponent("app/Boop/Views/Theme.swift"), encoding: .utf8)
        for (board, mac) in [("kSageRgb", "sageInkDark"), ("kClayRgb", "clayInkDark")] {
            let rgb = try XCTUnwrap(palette.firstMatch(of: try Regex("\(board) = \\{([0-9]+), ([0-9]+), ([0-9]+)\\};")), board)
            let hex = try XCTUnwrap(theme.firstMatch(of: try Regex("\(mac) = \"#([0-9A-F]{6})\"")), mac)
            let channels = (1...3).map { Int(rgb.output[$0].substring!)! }
            XCTAssertEqual(channels.map { String(format: "%02X", $0) }.joined(), String(hex.output[1].substring!), board)
        }
    }

    /// CHARACTER.md §5: Boop's moods are the slime design's host graph, in
    /// its order, with its meanings (slimegen writes them), and every edge
    /// the design draws is one of the pack's moves.
    func testBoopsMoodsAreTheSlimeDesigns() throws {
        try requirePack("boop")
        let file = Self.repo.appendingPathComponent("characters/boop/design/slime-blob/emotion-graph.json")
        let graph = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let nodes = try XCTUnwrap(graph["nodes"] as? [String: [String: Any]])
        XCTAssertEqual(MoodGraph.moods.count, 42)
        for (id, n) in nodes {
            let mood = try XCTUnwrap(MoodGraph.mood(id))
            XCTAssertEqual(mood.meaning, n["meaning"] as? String, id)
            let drawn = Set((n["ordinary"] as? [String] ?? []) + (n["dramatic"] as? [String] ?? []))
            XCTAssertTrue(drawn.isSubset(of: mood.moves.all), "\(id): \(drawn.subtracting(mood.moves.all).sorted())")
        }
    }

    /// CHARACTER.md §6: each pack stands alone, each in a repository of
    /// its own: every file the engine reads is in its own folder, its voice
    /// (the table and its pack) included, and it uses nothing of another's.
    /// Pixel's has the pixel face's mac/faces.json; Boop's, whose face is
    /// the gel, has its mirror instead.
    func testEachPackStandsAlone() throws {
        try requirePack("boop")
        let boopFolder = Self.repo.appendingPathComponent("characters/boop")
        let pixelFolder = Self.repo.appendingPathComponent("characters/pixel")
        let boop = try CharacterPack(directory: boopFolder)
        let pixel = try CharacterPack(directory: pixelFolder)
        XCTAssertEqual(pixel.moods.map(\.id), boop.moods.map(\.id))
        XCTAssertEqual(pixel.startupMood, "happy")
        for folder in [boopFolder, pixelFolder] {
            XCTAssertTrue(PackCheck.used(folder).isEmpty, folder.lastPathComponent)
            for path in ["mac/takes.tsv", "voice/voice.bin"] {
                XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path), "\(folder.lastPathComponent) \(path)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: pixelFolder.appendingPathComponent("mac/faces.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: boopFolder.appendingPathComponent("mac/mirror/board.js").path))
        // Pixel's moves are Boop's, for now.
        for m in pixel.moods { XCTAssertEqual(m.moves, boop.byId[m.id]?.moves, m.id) }
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
        XCTAssertEqual(PackCheck.voiceFileVersion(pack), String(version))
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

    /// CHARACTER.md §4, §5: a pack whose moods aren't exactly the
    /// universal ones, or that leads to a word that isn't a mood, is refused.
    func testABrokenPackSaysWhy() {
        let every = CharacterPack.universalMoods.map { ["id": $0, "meaning": "\($0)."] as [String: Any] }
        let json: [String: Any] = ["id": "test", "name": "Test", "version": "1", "default_mood": "calm", "personalities": ["test"],
                                   "moods": every]
        XCTAssertNil(refusal(json))
        var short = json
        short["moods"] = Array(every.dropLast()) + [["id": "sulky", "meaning": "Sulky."]]
        XCTAssertEqual(refusal(short), "test: moods aren't the universal ones (missing [\"disgusted\"], extra [\"sulky\"])")
        var twice = json
        twice["moods"] = every + [every[0]]
        XCTAssertEqual(refusal(twice), "test: moods names a mood twice")
        var badMove = json
        badMove["moods"] = [["id": "calm", "meaning": "Calm.", "moves": ["ordinary": ["sulky"], "dramatic": []]]] + every.dropFirst()
        XCTAssertEqual(refusal(badMove), "test: calm leads to sulky, which isn't a mood")
        var noDefault = json
        noDefault["default_mood"] = "sulky"
        XCTAssertEqual(refusal(noDefault), "test: default_mood sulky isn't a mood")
        var nobody = json
        nobody["personalities"] = [String]()
        XCTAssertEqual(refusal(nobody), "test: personalities is empty")
    }

    private func refusal(_ json: [String: Any]) -> String? {
        do { _ = try CharacterPack(json: json, from: "test"); return nil } catch { return "\(error)" }
    }
}
