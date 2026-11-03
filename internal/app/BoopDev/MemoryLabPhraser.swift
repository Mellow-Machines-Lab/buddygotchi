import BoopKit
import Foundation
import FoundationModels

/// The lab's model as the pipeline's: every call counted.
@available(macOS 26.0, *)
struct LabMemoryModel: MemoryModel, @unchecked Sendable {
    let m: LabModel
    func text(_ instructions: String, _ prompt: String, tokens: Int, tag: String) async -> String? {
        await m.text(instructions, prompt, tokens: tokens, tag: tag)
    }
    func yes(_ instructions: String, _ prompt: String, tag: String) async -> Bool? {
        guard let a = await m.choice(instructions, prompt, ["yes", "no"], tag: tag) else { return nil }
        return a == "yes"
    }
}

/// The approaches built on code's own proposals.
@available(macOS 26.0, *)
enum MemoryLabPhraser {
    static func digests(_ c: LabContext) -> [DayDigest] {
        (c.history + [c.night]).map { n in
            DayDigest.from(day: n.day, weekday: n.weekday, tallies: n.tallies, first: n.first, last: n.last, strokesAM: n.strokesAM, journal: n.journal)
        }
    }

    static func pipeline(_ options: MemoryPipeline.Options, model useModel: Bool = true) -> LabApproach {
        { c, m in
            let input = MemoryPipeline.Input(memory: c.memory, digests: digests(c), certain: c.night.certain, journal: c.night.journal, day: c.night.day, weekday: c.night.weekday)
            let out = await MemoryPipeline.write(input, model: useModel ? LabMemoryModel(m: m) : nil, options: options)
            c.evidence = out.evidence
            return out.reply
        }
    }

    static let weeklyAsk = """
        These are a person's last seven days at their Mac, one a line. What stayed true on most of them? A habit, not an event. One short sentence that starts with "You". If nothing did, reply none.
        """
    static let weeklyCheck = """
        Read the DAYS, then the NOTE. Is the NOTE true on most of the DAYS? Answer yes or no.
        """

    static func weekly(_ inner: @escaping LabApproach, from: @escaping @Sendable (LabContext) -> [String]) -> LabApproach {
        { c, m in
            var reply = await inner(&c, m)
            guard (c.history.count + 1) % 7 == 0 else { return reply }
            let days = from(c)
            guard days.count >= 5 else { return reply }
            let text = days.joined(separator: "\n")
            guard var note = await m.text(weeklyAsk, text, tokens: 40, tag: "weekly")?.trimmingCharacters(in: .whitespacesAndNewlines), note.hasPrefix("You") else { return reply }
            note = String(note.prefix { $0 != "\n" })
            guard await m.choice(weeklyCheck, "DAYS:\n\(text)\n\nNOTE: \(note)", ["yes", "no"], tag: "weekly-check") == "yes" else { return reply }
            reply = reply.replacingOccurrences(of: "\nend", with: "") + "\nadd you: \(note) | days: \(c.night.day)\nend"
            c.evidence.append(MemoryPipelineShuffle.words(text))
            return reply
        }
    }

    static var approaches: [String: LabApproach] {
        [
            // 5. Code proposes and words everything; no model at all.
            "code-only": pipeline(.init(phrase: false, moments: false, stories: false, dayLine: false), model: false),
            // Code words habits; the model only answers about moments and stories.
            "code+gates": pipeline(.init(phrase: false, moments: true, stories: true, dayLine: false)),
            // The model words them too.
            "phraser": pipeline(.init()),
            // The writer as the app has it, its own model and all (its calls aren't counted).
            "writer": { c, m in
                var input = MemoryPipeline.Input(memory: c.memory, digests: digests(c), certain: c.night.certain, journal: c.night.journal, day: c.night.day, weekday: c.night.weekday)
                input.forgotten = []
                var request = c.request
                request.pipeline = input
                c.evidence = MemoryPipeline.evidence(input)
                guard case .reply(let text) = await MemoryPipelineWriter().write(request) else { return "" }
                return text
            },
            // Code words everything but a day line.
            "code+day": pipeline(.init(phrase: false, moments: true, stories: true, dayLine: true)),
            // 7. A slower pass each week: the model reads the week and says what stayed true.
            "code+weekly": weekly(pipeline(.init(phrase: false, moments: true, stories: true, dayLine: false)), from: { c in
                c.memory.recently.prefix(7).reversed().map { "\($0.text)" }
            }),
            "code+weekly-table": weekly(pipeline(.init(phrase: false, moments: true, stories: true, dayLine: false)), from: { c in
                digests(c).suffix(7).map { d in
                    "\(d.weekday): from \(d.first) to \(d.last), \(d.turns) turns, most on \(d.topThread ?? "nothing"), \(d.failed) failed, stroked Boop \(d.strokes) times, poked it \(d.pokes) times, talked to it \(d.talks) times."
                }
            }),
        ]
    }
}

enum MemoryPipelineShuffle {
    static func words(_ text: String) -> String {
        Array(Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))).sorted().joined(separator: " ")
    }
}
