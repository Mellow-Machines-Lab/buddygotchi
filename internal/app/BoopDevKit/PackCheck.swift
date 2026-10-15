import BoopKit
import Foundation
import MellowHarness

/// Checks a character pack the way the engine reads it
/// (characters/CHARACTER.md), so a pack that passes plugs in: `boopdev
/// check`, and a test for every pack in the repo. `problems` stop the pack
/// from working; `notes` are allowed, but worth knowing.
public struct PackCheck {
    public var problems: [String] = []
    public var notes: [String] = []

    public init(_ directory: URL) {
        let pack: CharacterPack
        do { pack = try CharacterPack(directory: directory) } catch {
            problems.append("\(error)")
            return
        }
        func has(_ path: String) -> Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path) }

        // Steering: the guide and each personality, within the budgets.
        do {
            let steering = try Steering(directory: directory.appendingPathComponent("steering"), pack: pack)
            for mood in pack.v2Names where steering.files["mood/\(mood)"] == nil {
                notes.append("steering/mood/\(mood).md is missing: \(mood) reads as \(pack.defaultMood)'s")
            }
            for (path, text) in steering.files.sorted(by: { $0.key < $1.key }) {
                let budget = path.hasPrefix("guide") ? Steering.Budget.guide
                    : path.hasPrefix("personality/") ? Steering.Budget.personality : Steering.Budget.mood
                if Steering.tokens(text) > budget { notes.append("steering/\(path).md is over its budget: \(Steering.tokens(text)) > \(budget) tokens") }
            }
        } catch {
            problems.append("\(error)")
        }

        // Faces: what the firmware compiles in, and what the Mac reads.
        for path in ["firmware/include/moods.h", "firmware/src/render/make_face.cpp", "mac/faces.json"] where !has(path) {
            problems.append("\(path) is missing")
        }

        // Voice: both files or neither, the table readable, and of the same version as the card's pack.
        switch (has("mac/takes.tsv"), has("voice/voice.bin")) {
        case (true, false): problems.append("mac/takes.tsv has no voice/voice.bin: keep both, or neither for no voice")
        case (false, true): problems.append("voice/voice.bin has no mac/takes.tsv: keep both, or neither for no voice")
        case (true, true):
            let table = (try? String(contentsOf: directory.appendingPathComponent("mac/takes.tsv"), encoding: .utf8)) ?? ""
            let rows = table.split(separator: "\n").filter { !$0.hasPrefix("#") }
            for (i, row) in rows.dropFirst().enumerated() where Take(parsing: row) == nil {
                problems.append("mac/takes.tsv: take \(i + 1) isn't id, text, part, meaning, kind, mood, finish and ms")
            }
            let card = (try? Data(contentsOf: directory.appendingPathComponent("voice/voice.bin"))) ?? Data()
            if rows.first.map(String.init) != Self.voicePackVersion(card) {
                problems.append("mac/takes.tsv is version \(rows.first ?? "none"), and voice/voice.bin \(Self.voicePackVersion(card))")
            }
        case (false, false): break
        }

        // Demos: every line one the pack can play.
        for demo in pack.demos {
            do {
                problems += try DemoScript(contentsOf: demo).problems(for: pack).map { "demo/\(demo.lastPathComponent): \($0)" }
            } catch {
                problems.append("demo/\(error)")
            }
        }

    }

    /// The version in a voice pack's header (`voice/voice.bin`): its 16
    /// bytes after the magic, NUL-padded.
    public static func voicePackVersion(_ pack: Data) -> String {
        pack.count < 24 ? "" : String(decoding: pack[8..<24].prefix { $0 != 0 }, as: UTF8.self)
    }
}
