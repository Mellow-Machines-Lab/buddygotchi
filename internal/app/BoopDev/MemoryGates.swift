import BoopKit
import Foundation

/// `boopdev memory gates`: how well the model answers each small question the
/// dream's write asks, on labeled sentences. A gate is only as good as these
/// numbers; a held-out set stays apart from what the wordings were tuned on.
@available(macOS 26.0, *)
func memoryGates(_ file: URL) async {
    guard let data = try? Data(contentsOf: file), let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        fail("boopdev memory gates: can't read \(file.path)")
    }
    let model = AppleIntelligenceMemoryModel()
    typealias Item = (prompt: String, truth: Bool)
    func score(_ name: String, _ question: String, _ items: [Item]) async {
        var right = 0, unanswered = 0
        var wrong: [String] = []
        for item in items {
            guard let yes = await model.yes(question, item.prompt) else { unanswered += 1; continue }
            if yes == item.truth { right += 1 } else { wrong.append(item.prompt) }
        }
        print("\(name): \(right) of \(items.count) right, \(unanswered) unanswered")
        for w in wrong { print("    wrong: \(w)") }
    }
    func said(_ yes: [String], _ no: [String]) -> [Item] {
        (yes.map { ($0, true) } + no.map { ($0, false) }).map { (prompt: "They said: \"\($0.0)\"", truth: $0.1) }
    }
    func stories(_ rows: Any?) -> [Item] {
        (rows as? [[String: Any]] ?? []).flatMap { row in
            (row["words"] as? [String] ?? []).map { (prompt: "\"\($0)\"", truth: row["label"] as? String == "changed") }
        }
    }
    func set(_ key: String) -> (yes: [String], no: [String]) {
        let s = root[key] as? [String: [String]] ?? [:]
        return (s["yes"] ?? [], s["no"] ?? [])
    }
    let held = root["heldout"] as? [String: Any] ?? [:]
    func strings(_ key: String) -> [String] { held[key] as? [String] ?? [] }
    await score("worth", MemoryPipeline.worth, said(set("worth").yes, set("worth").no))
    await score("private", MemoryPipeline.isPrivate, said(set("private").yes, set("private").no))
    await score("story", MemoryPipeline.storyOver, stories(root["story"]))
    await score("worth, held out", MemoryPipeline.worth, said(strings("worth_yes"), strings("worth_no")))
    await score("private, held out", MemoryPipeline.isPrivate, said(strings("private_yes"), strings("private_no")))
    await score("story, held out", MemoryPipeline.storyOver, stories(held["story"]))
}
