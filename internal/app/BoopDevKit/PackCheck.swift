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
        // A file of the pack's: each pack stands alone (CHARACTER.md §6).
        func file(_ path: String) -> URL { directory.appendingPathComponent(path) }
        func has(_ path: String) -> Bool { FileManager.default.fileExists(atPath: file(path).path) }

        // Steering: the guide and each mood's file, within the budgets, and
        // the asks.
        do {
            let steering = try Steering(directory: directory.appendingPathComponent("steering"), pack: pack)
            for mood in pack.lasting.map(\.id) where steering.files["mood/\(mood)"] == nil {
                notes.append("steering/mood/\(mood).md is missing: \(mood) reads as \(pack.defaultMood)'s")
            }
            for (path, text) in steering.files.sorted(by: { $0.key < $1.key }) {
                let budget = path.hasPrefix("guide") ? Steering.Budget.guide
                    : path == "personality" ? Steering.Budget.personality
                    : path == "replies" ? Steering.Budget.replies : path == "dreams" ? Steering.Budget.dreams
                    : path == "asks" ? Steering.Budget.asks : Steering.Budget.mood
                if Steering.tokens(text) > budget { notes.append("steering/\(path).md is over its budget: \(Steering.tokens(text)) > \(budget) tokens") }
            }
            problems += Self.asks(steering.asks)
        } catch {
            problems.append("\(error)")
        }

        // Faces: what the firmware compiles in, and what the Mac reads of
        // the pixel face, for a pack that has it (a gel pack's popover shows
        // its mirror of the board).
        if !has("firmware/src/render/make_face.cpp") { problems.append("firmware/src/render/make_face.cpp is missing") }
        let boards = (try? Data(contentsOf: directory.appendingPathComponent("character.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["faces"] as? [String: String] ?? [:]
        if boards.values.contains("pixel") && !has("mac/faces.json") { problems.append("mac/faces.json is missing") }

        // Voice: both files or neither, the table readable, and of the same version as the card's pack.
        switch (has("mac/takes.tsv"), has("voice/voice.bin")) {
        case (true, false): problems.append("mac/takes.tsv has no voice/voice.bin: keep both, or neither for no voice")
        case (false, true): problems.append("voice/voice.bin has no mac/takes.tsv: keep both, or neither for no voice")
        case (true, true):
            let table = (try? String(contentsOf: file("mac/takes.tsv"), encoding: .utf8)) ?? ""
            let rows = table.split(separator: "\n").filter { !$0.hasPrefix("#") }
            for (i, row) in rows.dropFirst().enumerated() where Take(parsing: row) == nil {
                problems.append("mac/takes.tsv: take \(i + 1) isn't id, text, part, meaning, kind, mood, finish and ms")
            }
            let card = (try? Data(contentsOf: file("voice/voice.bin"))) ?? Data()
            if rows.first.map(String.init) != Self.voiceFileVersion(card) {
                problems.append("mac/takes.tsv is version \(rows.first ?? "none"), and voice/voice.bin \(Self.voiceFileVersion(card))")
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

    /// What's wrong with a pack's asks: a line neither a question with two
    /// answers nor a follow-up, a question or answer too long for the
    /// board, or a follow-up to a question or answer the file hasn't.
    static func asks(_ lines: [TaggedLine]) -> [String] {
        var found: [String] = []
        // A wish's lines: its sign, what it holds up as it's met, and its sign
        // until you've met that kind once.
        let wishes = lines.filter { $0.tags.first == "wish" }
        for line in wishes {
            let form = line.parts.count == 1 && Core.WishKind(rawValue: line.tags.dropFirst().first ?? "") != nil
                && (line.tags.count == 2 || (line.tags.count == 3 && ["met", "how"].contains(line.tags[2])))
            if !form { found.append("steering/asks.md: \"\(line.text)\" is no wish: tag it [wish pet|chat|work], with met or how after the kind if it's that") }
            if line.text.count > Signs.maxLength { found.append("steering/asks.md: \"\(line.text)\" is over \(Signs.maxLength) characters") }
        }
        let lines = lines.filter { $0.tags.first != "wish" }
        let questions = Asks.questions(lines)
        for line in lines where line.parts.count != 1 && line.parts.count != 3 {
            found.append("steering/asks.md: \"\(line.text)\" isn't a question with two answers, nor a follow-up")
        }
        for q in questions {
            if q.question.count > Asks.maxQuestion {
                found.append("steering/asks.md: \"\(q.question)\" is over \(Asks.maxQuestion) characters")
            }
            for answer in [q.a, q.b] where answer.count > Asks.maxAnswer {
                found.append("steering/asks.md: \"\(answer)\" is over \(Asks.maxAnswer) characters")
            }
        }
        for line in lines where line.parts.count == 1 {
            guard line.tags.count >= 2, let q = questions.first(where: { $0.id == line.tags[0] }),
                  [q.a, q.b].map({ $0.lowercased() }).contains(line.tags[1]) else {
                found.append("steering/asks.md: \"\(line.text)\" follows no question's answer: tag it [id answer]")
                continue
            }
            if line.text.count > Signs.maxLength {
                found.append("steering/asks.md: \"\(line.text)\" is over \(Signs.maxLength) characters")
            }
        }
        return found
    }

    /// The version in a voice file's header (`voice/voice.bin`): its 16
    /// bytes after the magic, NUL-padded.
    public static func voiceFileVersion(_ pack: Data) -> String {
        pack.count < 24 ? "" : String(decoding: pack[8..<24].prefix { $0 != 0 }, as: UTF8.self)
    }
}
