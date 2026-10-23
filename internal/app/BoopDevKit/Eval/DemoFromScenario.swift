import BoopKit
import Foundation

/// An eval scenario as a demo script (characters/DEMOS.md), so any eval
/// plays in the simulator: a demo is an eval with its brain's answers
/// written in. Each step becomes the demo steps that send the same hooks,
/// and each step that expects something is followed by a brain step with
/// the expect brain's answers (`ExpectBrain`). The virtual clock's gaps
/// are cut short, at most `maxGap` seconds, and a note says how long
/// really passed.
public enum DemoFromScenario {
    /// The longest a demo waits between two steps, in seconds.
    public static let maxGap = 2.5

    /// The script, one JSON object a line. A step's sign is the first of
    /// `signs`, the pack's captions, that says what it expects.
    public static func script(_ scenario: Scenario, signs: [TaggedLine] = []) -> String {
        var lines: [[String: Any]] = []
        var header: [String: Any] = ["demo": 1, "title": scenario.name]
        if scenario.steps.allSatisfy({ $0.agent == .codex }) { header["agent"] = "codex" }
        if let start = scenario.start { header["start"] = localDate(start) }
        lines.append(header)
        var lastMs: Int64 = 0
        var awayAt: Int64?
        for (i, step) in scenario.steps.enumerated() {
            let gapMs = step.atMs - lastMs
            lastMs = step.atMs
            var after = min(maxGap, Double(gapMs) / 1000)
            var note: String? = gapMs > Int64(maxGap * 1000) ? "\(minutes(gapMs)) later" : nil
            func add(_ o: [String: Any]) {
                var o = o
                o["after"] = (after * 10).rounded() / 10
                if let n = note { o["note"] = n }
                if let s = step.session, s != "s1", o["agent"] != nil { o["session"] = s }
                lines.append(o)
                after = 0.3
                note = nil
            }
            switch step.event {
            case "turn started":
                var o: [String: Any] = ["agent": "prompt", "text": step.prompt ?? "Carry on"]
                if let l = step.labels { o["reading"] = l.json }
                add(o)
            case "turn finished": add(["agent": "reply", "text": step.message ?? "Done."])
            case "turn failed": add(["agent": "reply", "text": "…", "fails": true])
            case "command":
                var o: [String: Any] = ["agent": "run", "cmd": command(step.topic)]
                if step.failed == true { o["fails"] = true }
                add(o)
            case "needs you":
                // Answered at the scenario's `answered`, else never.
                let answered = scenario.steps.dropFirst(i + 1).first { $0.event == "answered" && $0.session == step.session }
                add(["agent": "run", "cmd": "npm install", "ask": answered.map { min(20, Double($0.atMs - step.atMs) / 1000) } ?? 20])
            case "compact": add(["agent": "compact", "summary": "Where the work stands."])
            case "poke": add(["you": "poke"])
            case "pokes": for _ in 0..<(step.count ?? 4) { add(["you": "poke"]) }
            case "said": add(["you": "talk", "text": step.words ?? ""])
            case "away": awayAt = step.atMs
            case "back": add(["you": "back", "minutes": max(1, Double(step.atMs - (awayAt ?? step.atMs)) / 60_000)])
            default: break  // wait, session started, answered: nothing of their own
            }
            if step.expect != nil || step.brain != nil {
                // As the expect brain answers: the pipeline check's
                // answers, the step's own over them.
                let finish = step.event == "turn finished" ? "success" : step.event == "turn failed" ? "failure" : "none"
                let wanted = Self.playable(ExpectBrain.wanted(step))
                var brain = ["react.mood": "excited", "react.animation": finish, "react.loops": "once", "say.feeling": "none",
                             "say.about": "start", "say.kind": "word"].merging(wanted) { $1 }
                if let want = step.expectOrder["sign"], let prompt = step.prompt {
                    let reading = PromptReading(prompt: prompt, names: [CharacterPack.active.name], labels: step.labels)
                    let captions = Signs.offered(signs, reading: reading, calendar: [])
                    brain[Signs.questionKey] = captions.first { Scenario.Expectation.sign(want, says: $0) }
                }
                let mood = brain.removeValue(forKey: MoodOutput.outputName)
                var o: [String: Any] = ["brain": brain]
                if let mood { o["mood"] = mood }
                lines.append(o)
            }
        }
        return lines.map { o in
            String(decoding: (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
        }.joined(separator: "\n") + "\n"
    }

    /// The first of each question's wanted values that the brain can be
    /// asked to play (`DemoScript.problems`): `none` holds no face, so it
    /// isn't a hold.
    static func playable(_ wanted: [String: [String]], in pack: CharacterPack = .active) -> [String: String] {
        var offered = DemoScript.choices(in: pack)
        offered[MoodOutput.outputName] = pack.moods.map(\.id)
        var out: [String: String] = [:]
        for (key, values) in wanted {
            if let pick = values.first(where: { offered[key]?.contains($0) == true }) { out[key] = pick }
        }
        return out
    }

    /// A command the topic's tag reads back from (`Topic.tag`).
    static func command(_ topic: String?) -> String {
        switch topic {
        case "tests": "npm test"
        case "build": "npm run build"
        case "deploy": "npm run deploy"
        case "docs": "npx markdownlint docs"
        default: "ls"
        }
    }

    static func minutes(_ ms: Int64) -> String {
        ms >= 3_600_000 ? "\(ms / 3_600_000) h \(ms / 60_000 % 60) min" : ms >= 60_000 ? "\((ms + 30_000) / 60_000) min" : "\(ms / 1000) s"
    }

    /// A UTC start as the demo's local `start`: the same clock reading.
    static func localDate(_ ms: Int64) -> String { DemoScript.date(ms, timeZone: TimeZone(identifier: "UTC")!) }
}
