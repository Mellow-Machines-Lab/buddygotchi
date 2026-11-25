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

    /// CHARACTER.md §5, §9: every face has its wording, in the pack's
    /// order, and every lasting mood an option for the mood question.
    func testEveryMoodHasAFace() throws {
        XCTAssertEqual(CharacterPack.active.faces.map(\.name), CharacterPack.active.moods.map(\.id))
        XCTAssertEqual(MoodOutput.moods.map(\.name), CharacterPack.active.lasting.map(\.id))
    }

    /// The popover's still face cross-fades into a new one over the board's dissolve between pictures
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

    /// CHARACTER.md §5, and the owner's cut of 2026-11-15: Boop settles
    /// into 7 lasting moods and draws 18 faces. Each mood rests in its own
    /// face but cross, whose three levels' faces code picks; each fades
    /// after its minutes, calm never; and a face that's no mood's own
    /// settles into one, which a word for it (a log from before) reads as.
    func testBoopHasSevenMoodsAndEighteenFaces() throws {
        try requirePack("boop")
        let pack = CharacterPack.active
        XCTAssertEqual(pack.lasting.map(\.id), ["calm", "happy", "focused", "proud", "cross", "sad", "lonely"])
        XCTAssertEqual(pack.moods.map(\.id), ["calm", "focused", "happy", "excited", "pleased", "proud", "amused", "affectionate", "mischievous",
                                              "curious", "determined", "surprised", "annoyed", "grumpy", "angry", "sad", "wounded", "lonely"])
        typealias Fade = CharacterPack.Fade
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: pack.lasting.map { ($0.id, $0.fade) }), [
            "calm": nil, "happy": Fade(minutes: 10, to: nil, holds: nil), "focused": Fade(minutes: 3, to: nil, holds: .working),
            "proud": Fade(minutes: 5, to: "happy", holds: nil), "cross": Fade(minutes: 3, to: nil, holds: nil),
            "sad": Fade(minutes: 10, to: nil, holds: nil), "lonely": Fade(minutes: 20, to: nil, holds: .away),
        ])
        for l in pack.lasting where l.id != "cross" {
            XCTAssertEqual(l.faces, [l.id], "\(l.id) rests in its own face")
            XCTAssertFalse(l.levelled)
        }
        let cross = try XCTUnwrap(pack.lasting("cross"))
        XCTAssertEqual(cross.faces, ["annoyed", "grumpy", "angry"], "the cross ladder")
        XCTAssertEqual([0, 1, 2, 3, 9].map { pack.restingFace("cross", level: $0) }, ["annoyed", "annoyed", "grumpy", "angry", "angry"])
        XCTAssertEqual(pack.restingFace("focused"), "focused")
        for m in pack.moods { XCTAssertEqual(pack.settled(m.id), pack.lasting(m.id) != nil ? m.id : m.settles, m.id) }
        XCTAssertEqual(pack.settled("grumpy"), "cross")
        XCTAssertEqual(pack.settled("wounded"), "sad")
        XCTAssertEqual(pack.settled("excited"), "happy")
        XCTAssertEqual(pack.settled("cross"), "cross")
        XCTAssertNil(pack.settled("sleepy"), "not one of its faces")
    }

    /// CHARACTER.md §6: the pack stands alone, in a repository of its
    /// own: every file the engine reads is in its own folder, its voice
    /// (the table and its pack) included. The mirror of the board that the
    /// popover shows is built into it (`firmware/tools/mirror.sh`).
    func testThePackStandsAlone() throws {
        try requirePack("boop")
        let folder = Self.repo.appendingPathComponent("characters/boop")
        for path in ["mac/takes.tsv", "voice/voice.bin", "mac/mirror/index.html"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path), path)
        }
        let pack = try CharacterPack(directory: folder)
        XCTAssertEqual(pack.id, "boop")
    }

    /// Boop's pack plugs in, as `boopdev check` sees it: its files, its
    /// steering, its voice and its demos.
    func testThePackPassesTheCheck() throws {
        XCTAssertEqual(PackCheck(Self.repo.appendingPathComponent("characters/boop")).problems, [])
    }

    /// A pack that's missing what the engine needs says what, and a mood
    /// with no steering file is only a note: it reads as the resting mood's.
    func testTheCheckSaysWhatAPackLacks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pack-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let boop = Self.repo.appendingPathComponent("characters/boop")
        for path in ["character.json", "steering", "firmware", "mac"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: boop.appendingPathComponent(path), to: dir.appendingPathComponent(path))
        }
        var check = PackCheck(dir)
        XCTAssertEqual(check.problems, ["mac/takes.tsv has no voice/voice.bin: keep both, or neither for no voice"])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("mac/takes.tsv"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("steering/mood/sad.md"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("steering/guide.md"))
        check = PackCheck(dir)
        XCTAssertEqual(check.problems.count, 1)
        XCTAssertTrue(check.problems[0].hasPrefix("guide.md is missing"), "\(check.problems)")
        try FileManager.default.copyItem(at: boop.appendingPathComponent("steering/guide.md"), to: dir.appendingPathComponent("steering/guide.md"))
        check = PackCheck(dir)
        XCTAssertEqual(check.problems, [])
        XCTAssertTrue(check.notes.contains("steering/mood/sad.md is missing: sad reads as calm's"), "\(check.notes)")
    }

    /// CHARACTER.md §4, §5: a pack that names a face or a mood twice, whose
    /// mood rests in a face it doesn't draw, fades to a word that isn't a
    /// mood, whose face settles into none, or that has no `lasting`, is
    /// refused.
    func testABrokenPackSaysWhy() {
        let moods: [[String: Any]] = [["id": "calm", "face": "A calm face."], ["id": "happy", "face": "A happy face."],
                                      ["id": "annoyed", "face": "An annoyed face.", "settles": "cross"],
                                      ["id": "grumpy", "face": "A grumpy face.", "settles": "cross"]]
        let lasting: [[String: Any]] = [["id": "calm", "meaning": "Calm."], ["id": "happy", "meaning": "Happy.", "fade": ["minutes": 10]],
                                        ["id": "cross", "meaning": "Cross.", "levels": ["annoyed", "grumpy"], "fade": ["minutes": 3]]]
        let json: [String: Any] = ["id": "test", "name": "Test", "version": "1", "default_mood": "calm", "lasting": lasting, "moods": moods]
        XCTAssertNil(refusal(json))
        func with(_ key: String, _ value: Any) -> [String: Any] { json.merging([key: value]) { _, new in new } }
        XCTAssertEqual(refusal(with("moods", moods + [moods[0]])), "test: moods names a face twice")
        XCTAssertEqual(refusal(with("moods", [[String: Any]]())), "test: moods names no face")
        XCTAssertEqual(refusal(with("lasting", lasting + [lasting[0]])), "test: lasting names a mood twice")
        XCTAssertEqual(refusal(with("default_mood", "sulky")), "test: default_mood sulky isn't a lasting mood")
        XCTAssertEqual(refusal(with("default_mood", "happy")), "test: default_mood happy fades after 10 min, and it's where moods settle")
        XCTAssertEqual(refusal(with("lasting", Array(lasting.dropLast()) + [["id": "cross", "meaning": "Cross.", "levels": ["annoyed", "furious"]]])),
                       "test: cross rests in furious, which isn't one of the pack's faces")
        XCTAssertEqual(refusal(with("lasting", lasting + [["id": "sulky", "meaning": "Sulky."]])),
                       "test: sulky rests in sulky, which isn't one of the pack's faces")
        XCTAssertEqual(refusal(with("lasting", [lasting[0], ["id": "happy", "meaning": "Happy.", "fade": ["minutes": 10, "to": "sulky"]], lasting[2]])),
                       "test: happy fades to sulky, which isn't another lasting mood")
        XCTAssertEqual(refusal(with("lasting", [lasting[0], ["id": "happy", "meaning": "Happy.", "fade": ["minutes": 10, "holds": "asleep"]], lasting[2]])),
                       "test: happy's fade holds asleep, not working or away")
        XCTAssertEqual(refusal(with("lasting", [lasting[0], ["id": "happy", "meaning": "Happy.", "fade": ["to": "calm"]], lasting[2]])),
                       "test: happy's fade has no minutes")
        XCTAssertEqual(refusal(with("moods", moods.map { $0["id"] as? String == "grumpy" ? ["id": "grumpy", "face": "A grumpy face."] : $0 })),
                       "test: grumpy is no lasting mood, and settles into none")
        var old = json
        old["lasting"] = nil
        XCTAssertEqual(refusal(old), "test: lasting is missing")
        var noFace = json
        noFace["moods"] = [["id": "calm"]] + Array(moods.dropFirst())
        XCTAssertEqual(refusal(noFace), "test: a face without an id or a face")
    }

    private func refusal(_ json: [String: Any]) -> String? {
        do { _ = try CharacterPack(json: json, from: "test"); return nil } catch { return "\(error)" }
    }
}
