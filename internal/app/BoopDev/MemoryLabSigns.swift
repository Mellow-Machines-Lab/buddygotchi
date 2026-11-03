import BoopKit
import Foundation

/// `boopdev memory signs`: a note into the pet's voice, for a sign, on
/// notes of every kind, with several ways of asking.
@available(macOS 26.0, *)
enum LabSigns {
    static let notes = [
        "You stay up late on Fridays, and not much else.",
        "You work late most nights.",
        "Weekends are for \"garden-game\". Weekdays are for \"billing\".",
        "You're polite to your agents, most of the time.",
        "You're nearly always in a hurry with your agents.",
        "You talk to your agents a few words at a time.",
        "You write your agents whole paragraphs.",
        "You've been short with your agents lately.",
        "You sit down before seven, most days.",
        "\"checkout\" fought you for four days, and you won on Friday.",
        "\"checkout\" has been fighting you for two days.",
        "\"app\" fought you for two days, and you won on Thursday.",
        "\"notes-app\" is where your days have been going.",
        "\"blog\": you said \"forget the move\" on Tuesday.",
        "\"cli\": you said \"flags are done\" on Friday.",
        "You told Boop \"we finally fixed it!\" on Friday.",
        "You told Boop \"we shipped the beta\" on Tuesday.",
        "You told Boop \"love the new theme\" on Friday.",
        "You told Boop \"search is fast now\" on Tuesday.",
        "Boop asked your fav snack, and you said cookie.",
        "You say \"morning buddy\" to Boop when you sit down.",
        "You tell Boop \"night boop\" before you go.",
        "You keep telling Boop \"you're funny\".",
        "Boop has grown cuddly: you stroke it most mornings.",
        "Boop has grown chatty: you talk to it most days.",
        "Boop has grown cheeky: you poke it far more than you stroke it.",
        "Boop has grown distant: you haven't touched it or talked to it in a week.",
    ]

    static let few = """
        You turn a note about a person into what their small cheeky pet would hold up on a tiny sign. At most 6 short words, all lowercase. Say "u" for "you". Keep it true to the note. Plain letters, no emoji. Reply with only the sign.
        """
    static let examples = """
        Note: You stay up late on Tuesdays.
        Sign: u stay up late tuesdays

        Note: "garden" fought you for three days, but on Monday you won.
        Sign: u beat garden!!

        Note: You say "hey you" to Boop when you sit down.
        Sign: hey you, every morning

        Note: Boop has grown cuddly: you stroke it most days.
        Sign: more pets pls
        """
    static let moreExamples = """
        Note: You told Boop "it finally runs" on Sunday.
        Sign: it finally runs!! i was there

        Note: You're always rushing your agents.
        Sign: slow down, boss

        Note: "game" is where your days go.
        Sign: game, game, game

        Note: Boop has grown cheeky: you poke it more than you stroke it.
        Sign: stop poking me
        """

    static func run() async {
        let m = LabModel()
        let ways: [(String, String, UInt64?)] = [
            ("rule only", few, nil),
            ("4 examples", few + "\n\n" + examples, nil),
            ("8 examples", few + "\n\n" + examples + "\n\n" + moreExamples, nil),
            ("8 examples, sampled", few + "\n\n" + examples + "\n\n" + moreExamples, 7),
        ]
        for (name, instructions, seed) in ways {
            var ok = 0
            let before = m.ms
            print("--- \(name)")
            for note in notes {
                let r = await m.text(instructions, "Note: \(note)\nSign:", temperature: seed == nil ? nil : 0.9, seed: seed, tokens: 24, tag: "sign") ?? ""
                var t = r.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\"", with: "")
                if t.hasPrefix("sign:") { t = String(t.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
                let valid = MemoryPipeline.signIsValid(t)
                if valid { ok += 1 }
                print("  \(valid ? "ok " : "BAD") \(t)   <- \(note)")
            }
            print("  valid \(ok)/\(notes.count), \((m.ms - before) / notes.count) ms a call")
        }
    }
}
