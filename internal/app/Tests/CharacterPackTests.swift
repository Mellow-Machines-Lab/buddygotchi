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
        XCTAssertEqual(CharacterPack.active.moods, pack.moods)
    }

    /// CHARACTER.md §5, §9: every mood has a face's wording and designs on
    /// the pixel face, which draws all of them (the Pixel pack's
    /// mac/faces.json names the moods its faces.h does), and every lasting
    /// one an option for the mood question.
    func testEveryMoodHasAFaceAndDesigns() throws {
        XCTAssertEqual(MomentOutput.expressions.map(\.name), CharacterPack.active.moods.map(\.id))
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

    /// CHARACTER.md §5: Boop settles into 16 lasting moods, each with its
    /// meaning and moves; the other 26 are faces, each settling into one of
    /// them, which a word for it (a log from before) reads as.
    func testBoopSettlesIntoSixteenLastingMoods() throws {
        try requirePack("boop")
        let pack = CharacterPack.active
        XCTAssertEqual(Set(MoodGraph.moods), ["calm", "comfy", "lazy", "happy", "proud", "annoyed", "irritated", "grumpy", "sad", "wounded",
                                              "engaged", "curious", "surprised", "determined", "excited", "lonely"])
        XCTAssertEqual(pack.moods.count, 42)
        for m in pack.moods where !m.lasting {
            XCTAssertNil(MoodGraph.mood(m.id), m.id)
            XCTAssertTrue(m.neighbours.all.isEmpty, m.id)
            XCTAssertEqual(pack.settled(m.id), m.settles, m.id)
        }
        XCTAssertEqual(pack.settled("tired"), "lazy")
        XCTAssertEqual(pack.settled("calm"), "calm")
        XCTAssertNil(pack.settled("sleepy"))
        // Lonely is reached only from the settled, quiet moods.
        XCTAssertEqual(Set(pack.lasting.filter { $0.neighbours.all.contains("lonely") }.map(\.id)), ["calm", "comfy", "lazy"])
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
            for path in ["mac/takes.tsv", "voice/voice.bin"] {
                XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path), "\(folder.lastPathComponent) \(path)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: pixelFolder.appendingPathComponent("mac/faces.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: boopFolder.appendingPathComponent("mac/mirror/board.js").path))
        // Pixel's moves are Boop's, for now.
        for m in pixel.moods { XCTAssertEqual(m.neighbours, boop.byId[m.id]?.neighbours, m.id) }
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
        XCTAssertTrue(steering.guide.contains("Pixel"))
        for (path, text) in steering.files {
            XCTAssertFalse(text.contains("Boop"), path)
            let budget = path == "guide" ? Steering.Budget.guide : path == "personality" ? Steering.Budget.personality : Steering.Budget.mood
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
    /// universal ones, that leads to a word that isn't a lasting mood, or
    /// whose face-only mood settles into none, is refused.
    func testABrokenPackSaysWhy() {
        let every = CharacterPack.universalMoods.map { ["id": $0, "meaning": "\($0).", "face": "A \($0) face."] as [String: Any] }
        let json: [String: Any] = ["id": "test", "name": "Test", "version": "1", "default_mood": "calm",
                                   "moods": every]
        XCTAssertNil(refusal(json))
        var short = json
        short["moods"] = Array(every.dropLast()) + [["id": "sulky", "meaning": "Sulky.", "face": "A sulky face."]]
        XCTAssertEqual(refusal(short), "test: moods aren't the universal ones (missing [\"disgusted\"], extra [\"sulky\"])")
        var twice = json
        twice["moods"] = every + [every[0]]
        XCTAssertEqual(refusal(twice), "test: moods names a mood twice")
        var badMove = json
        badMove["moods"] = [["id": "calm", "meaning": "Calm.", "face": "A calm face.", "moves": ["ordinary": ["sulky"], "dramatic": []]]] + every.dropFirst()
        XCTAssertEqual(refusal(badMove), "test: calm leads to sulky, which isn't a lasting mood")
        var noDefault = json
        noDefault["default_mood"] = "sulky"
        XCTAssertEqual(refusal(noDefault), "test: default_mood sulky isn't a lasting mood")
        // A face-only mood: no meaning, and the lasting mood it settles into.
        var faceOnly = json
        faceOnly["moods"] = every.map { $0["id"] as? String == "tired" ? ["id": "tired", "face": "A tired face.", "settles": "lazy"] : $0 }
        XCTAssertNil(refusal(faceOnly))
        faceOnly["moods"] = every.map { $0["id"] as? String == "tired" ? ["id": "tired", "face": "A tired face."] : $0 }
        XCTAssertEqual(refusal(faceOnly), "test: tired has no meaning, and settles into no lasting mood")
        var toFaceOnly = json
        toFaceOnly["moods"] = every.map { m -> [String: Any] in
            switch m["id"] as? String {
            case "tired": ["id": "tired", "face": "A tired face.", "settles": "lazy"]
            case "calm": ["id": "calm", "meaning": "Calm.", "face": "A calm face.", "moves": ["ordinary": ["tired"], "dramatic": []]]
            default: m
            }
        }
        XCTAssertEqual(refusal(toFaceOnly), "test: calm leads to tired, which isn't a lasting mood")
        var noFace = json
        noFace["moods"] = [["id": "calm", "meaning": "Calm."]] + every.dropFirst()
        XCTAssertEqual(refusal(noFace), "test: a mood without an id or a face")
    }

    private func refusal(_ json: [String: Any]) -> String? {
        do { _ = try CharacterPack(json: json, from: "test"); return nil } catch { return "\(error)" }
    }
}
