import Foundation
import MellowHarness

/// The brain in the box: Boop's mood, the emotion at each event, what it
/// says and which sign it holds up, by rules, with no key and no network
/// (documentation/design/brain.md, layer 1). It answers the questions Jev
/// is asked, so every output's code rules still apply after it. The mood
/// moves only by the pack's mood map (`MoodMap`); the move and the size
/// stay `MomentRule`'s. It reads the event and its line's facts as each
/// call is prepared (`ReadingBrain`), never the prompt's prose.
public final class RulesBrain: ReadingBrain, @unchecked Sendable {
    public let id = "rules"
    /// The facts of an event's line, by its seq.
    let facts: (Int) -> [String: JSONValue]?
    /// The lasting mood now, and cross's level.
    let mood: (LogView) -> (mood: String, level: Int)
    /// Whether an agent is working for you now.
    let working: (LogView) -> Bool
    /// How the finished turn's agent read you, from its result card.
    let seemed: (Event) -> Card.Seemed?
    private let lock = NSLock()
    private var lastFace: [Slot: String] = [:]
    private var lastAny: String?
    private var rng: SplitMix

    public init(seed: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000),
                facts: @escaping (Int) -> [String: JSONValue]?,
                seemed: @escaping (Event) -> Card.Seemed? = { _ in nil },
                mood: @escaping (LogView) -> (mood: String, level: Int),
                working: @escaping (LogView) -> Bool = { _ in false }) {
        self.facts = facts
        self.seemed = seemed
        self.mood = mood
        self.working = working
        rng = SplitMix(seed)
    }

    // MARK: Reading the event

    /// What kind of moment an event is, for its faces.
    public enum Slot: String, Sendable, CaseIterable {
        case doneVeryShort, doneShort, doneLong, doneVeryLong, chat, echo
        case failed, failedVeryLong, gaveUp
        case checkFailed, checkFailing, checkFixed
        case prompt, promptFrustrated, promptPlayful, promptPolite, promptNamed
        case poke, pokes, pokesMany, stroke, hold, shake, pickup, otherTouch
        case words, wordsKind, wordsRude, wordsSad, wordsSorry, wordsThanks, wordsHello, wordsBye, wordsQuestion
        case back, backDays, backAfterADay
        case idle, answered, wishMet, wishGone, other
    }

    /// An event as the rules read it: its slot, the mood map's cues, the
    /// reply to your words, and how many pokes in a row.
    public struct Read: Equatable, Sendable {
        public var slot: Slot
        public var cues: Set<MoodMap.Cue> = []
        public var reply: String?
        public var inARow = 1
    }

    /// A finished turn, by its line's facts: how it ended and how long it ran.
    static func finish(_ f: [String: JSONValue]) -> Read {
        let band = f["length"]?.string ?? "short"
        switch MomentRule.finish(f) {
        case .failure?:
            if f["message"]?.object?["kind"]?.string == MessageText.Kind.stuck.rawValue { return Read(slot: .gaveUp, cues: [.gaveUp]) }
            return band == "very long" ? Read(slot: .failedVeryLong, cues: [.veryLongFailed]) : Read(slot: .failed, cues: [.turnFailed])
        case .success?:
            // Just after a fix Boop already reacted to: no new win, a quiet
            // echo of that face.
            if f["reacted_to_fix"]?.bool == true { return Read(slot: .echo) }
            switch band {
            case "very long": return Read(slot: .doneVeryLong, cues: [.turnDone, .longDone, .veryLongDone])
            case "long": return Read(slot: .doneLong, cues: [.turnDone, .longDone])
            case "very short": return Read(slot: .doneVeryShort, cues: [.turnDone])
            default: return Read(slot: .doneShort, cues: [.turnDone])
            }
        default: return Read(slot: .chat)
        }
    }

    public static func read(_ e: Event, facts f: [String: JSONValue]) -> Read {
        // A finish: the turn's end, or its last message, which carries the
        // finish's facts in its place.
        if f["outcome"] != nil, e.type == .turn || e.type == .lastMessage { return finish(f) }
        switch e.type {
        case .turn? where e.phase == .end:
            return finish(f)
        case .turn? where e.phase == .start:
            return Read(slot: .other, cues: [.agentStarts])

        case .turn? where e.phase == .start:
            return Read(slot: .other, cues: [.agentStarts])
        case .tool? where e.phase == .end:
            guard let topic = f["topic"]?.string, TranscriptView.checks.contains(topic) else { return Read(slot: .other) }
            if f["result"]?.string == "failed" {
                return Read(slot: (f["failed_before"]?.int ?? 0) > 0 ? .checkFailing : .checkFailed, cues: [.checkFailed])
            }
            return (f["failed_before"]?.int ?? 0) > 0 ? Read(slot: .checkFixed, cues: [.checkFixed]) : Read(slot: .other)
        case .prompt?:
            guard let reading = PromptReading(facts: e.data) else { return Read(slot: .prompt) }
            var cues: Set<MoodMap.Cue> = []
            let said = reading.phrases.joined(separator: " ").lowercased()
            if said.contains("thank") { cues.insert(.thanks) }
            if reading.tone == .frustrated || reading.tone == .shouting { cues.insert(.frustrated) }
            let slot: Slot = !reading.named.isEmpty ? .promptNamed
                : cues.contains(.frustrated) ? .promptFrustrated
                : reading.tone == .playful ? .promptPlayful
                : reading.tone == .polite || cues.contains(.thanks) ? .promptPolite : .prompt
            return Read(slot: slot, cues: cues)
        case .poke?:
            let n = Int(f["in_a_row"]?.int ?? 1)
            var cues: Set<MoodMap.Cue> = [.touched]
            if n >= 2 { cues.insert(.twoPokes) }
            if n >= 3 { cues.insert(.threePokes) }
            return Read(slot: n >= 4 ? .pokesMany : n >= 2 ? .pokes : .poke, cues: cues, inARow: n)
        case .gesture? where e.phase == nil:
            switch Touch(e) {
            case .stroke?, .swipe?: return Read(slot: .stroke, cues: [.stroke, .touched])
            case .hold?: return Read(slot: .hold, cues: [.stroke, .touched])
            case .shake?: return Read(slot: .shake, cues: [.touched], inARow: Int(f["in_a_row"]?.int ?? 1))
            case .pickup?: return Read(slot: .pickup, cues: [.touched])
            default: return Read(slot: .otherTouch, cues: [.touched])
            }
        case .said?:
            let words = (f["words"]?.string ?? e["words"]?.string ?? "")
            return Words.read(words)
        case .presence? where e.phase == .end:
            let ms = f["away_ms"]?.int ?? 0
            if MoodOutput.missAwayMs.contains(ms) { return Read(slot: .backAfterADay, cues: [.backAfterADay, .back]) }
            return Read(slot: ms >= MomentRule.daysMs ? .backDays : .back, cues: [.back])
        case .checkIn?:
            return Read(slot: .idle)
        case .ask?:
            return Read(slot: .answered, cues: [.touched])
        case .wish?:
            return Read(slot: f["wish"]?.string == "met" ? .wishMet : .wishGone)
        default:
            return Read(slot: .other)
        }
    }

    // MARK: A call

    public func reading(now: Event, log: LogView) -> any Brain {
        let f = facts(now.seq) ?? [:]
        var read = Self.read(now, facts: f)
        // The agent read you as frustrated: a fact the mood map already
        // names, "the person sounding frustrated". It adds no move of its own.
        if f["outcome"] != nil, seemed(now) == .frustrated { read.cues.insert(.frustrated) }
        let (current, level) = mood(log)
        var moodTo = MoodMap.moves(from: current, cues: read.cues, level: level)
        // An agent starting work ends lonely only when one really works.
        if read.cues == [.agentStarts], !working(log) { moodTo = [] }
        let shown = moodTo.first { $0 != MoodOutput.missing } ?? current
        let face = pickFace(read, mood: shown, level: level)
        return Call(read: read, mood: current, moodTo: moodTo, face: face, say: say(read, face: face, mood: shown),
                    roll: lock.withLock { rng.next() })
    }

    /// Asked with no reading, as a forced pass from outside is: the mood
    /// stays, and nothing plays.
    public func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
        var out: Answers = [:]
        for q in questions {
            let pick = q.options.first { $0.name == "none" } ?? q.options.first
            if let pick { out[q.key] = Answer(choice: pick.name, probabilities: [pick.name: 1]) }
        }
        return out
    }

    /// The faces each slot may show, the likelier first. A mood colours
    /// them after (`colour`).
    public static let faces: [Slot: [String]] = [
        .doneVeryShort: ["pleased", "happy"],
        .doneShort: ["pleased", "happy", "amused"],
        .doneLong: ["proud", "pleased", "happy"],
        .doneVeryLong: ["proud", "excited"],
        .chat: [],
        .echo: [],
        .failed: ["grumpy", "annoyed"],
        .failedVeryLong: ["sad"],
        .gaveUp: ["sad", "grumpy"],
        .checkFailed: ["annoyed", "curious", "determined"],
        .checkFailing: ["determined", "grumpy"],
        .checkFixed: ["proud", "pleased"],
        .prompt: [],
        .promptFrustrated: ["determined"],
        .promptPlayful: ["mischievous", "amused"],
        .promptPolite: ["pleased", "affectionate"],
        .promptNamed: ["surprised", "curious"],
        .poke: ["mischievous", "curious"],
        .pokes: ["annoyed"],
        .pokesMany: ["grumpy", "angry"],
        .stroke: ["affectionate", "pleased"],
        .hold: ["affectionate", "calm"],
        .shake: ["surprised", "annoyed"],
        .pickup: ["happy", "curious"],
        .otherTouch: ["curious"],
        .words: ["curious", "happy"],
        .wordsKind: ["affectionate", "happy"],
        .wordsRude: ["wounded"],
        .wordsSad: ["sad"],
        .wordsSorry: ["pleased", "calm"],
        .wordsThanks: ["happy", "pleased"],
        .wordsHello: ["happy", "curious"],
        .wordsBye: ["affectionate", "calm"],
        .wordsQuestion: ["curious"],
        .back: ["happy", "affectionate"],
        .backDays: ["excited"],
        .backAfterADay: ["lonely"],
        .idle: [],
        .answered: ["happy", "amused"],
        .wishMet: ["happy", "affectionate"],
        .wishGone: ["sad"],
        .other: [],
    ]

    /// The faces a mood allows of `faces`: cross never cheers (a win is
    /// grudging, pleased or proud), sad never turns cheeky.
    static func colour(_ faces: [String], mood: String, level: Int) -> [String] {
        switch mood {
        case "cross":
            let cheer: Set = ["excited", "happy", "amused", "affectionate", "mischievous"]
            let kept = faces.map { cheer.contains($0) ? "pleased" : $0 }
            return kept.contains("pleased") || kept.contains("proud") ? kept : kept.map { $0 == "curious" ? ["annoyed", "grumpy", "angry"][min(2, level - 1)] : $0 }
        case "sad":
            let cheeky: Set = ["mischievous", "amused", "excited"]
            return faces.map { cheeky.contains($0) ? "sad" : $0 }
        default:
            return faces
        }
    }

    func pickFace(_ read: Read, mood: String, level: Int) -> String? {
        let options = Self.colour(Self.faces[read.slot] ?? [], mood: mood, level: level).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        if read.slot == .echo { return lock.withLock { lastAny ?? "pleased" } }
        guard !options.isEmpty else { return nil }
        return lock.withLock {
            // Never the face this slot showed last, nor the last face at
            // all, while another fits; the first is likelier.
            var fresh = options.filter { $0 != lastFace[read.slot] && $0 != lastAny }
            if fresh.isEmpty { fresh = options.filter { $0 != lastFace[read.slot] } }
            if fresh.isEmpty { fresh = options }
            let weights = fresh.indices.map { $0 == 0 ? 2 : 1 }
            var r = Int(rng.next() % UInt64(weights.reduce(0, +)))
            var pick = fresh[0]
            for (i, w) in weights.enumerated() { if r < w { pick = fresh[i]; break }; r -= w }
            lastFace[read.slot] = pick
            lastAny = pick
            return pick
        }
    }

    /// What Boop says at `read`, one of `say`'s option names, or nil for
    /// nothing. `MomentOutput` drops what the pack or Talk doesn't allow.
    func say(_ read: Read, face: String?, mood: String) -> String? {
        guard face != nil else { return nil }
        switch read.slot {
        case .doneVeryShort, .chat, .echo, .prompt, .idle, .other: return nil
        case .doneShort: return "glad"
        case .doneLong, .doneVeryLong: return "done"
        case .failed, .failedVeryLong, .gaveUp: return mood == "cross" ? "swear" : "upset"
        case .checkFailed: return "tests"
        case .checkFailing: return "retry"
        case .checkFixed: return "tests"
        case .promptFrustrated: return "retry"
        case .promptPlayful, .poke: return mood == "cross" ? "shaken" : "tickled"
        case .promptPolite, .promptNamed, .stroke, .hold, .pickup, .answered, .wishMet: return "glad"
        case .pokes, .pokesMany: return mood == "cross" ? "shaken" : "upset"
        case .shake: return "shaken"
        case .otherTouch: return "tickled"
        case .back, .backDays, .wordsHello: return "hello"
        case .backAfterADay, .wordsSad, .wishGone: return nil
        case .wordsRude: return "upset"
        case .words, .wordsKind, .wordsSorry, .wordsThanks, .wordsBye, .wordsQuestion: return "glad"
        }
    }

    /// One call's answers, fixed as it was prepared.
    struct Call: Brain {
        let id = "rules"
        var read: Read
        var mood: String
        var moodTo: [String]
        var face: String?
        var say: String?
        var roll: UInt64

        func answer(state: String, questions: [Question], deadline: Duration) async throws -> Answers {
            var out: Answers = [:]
            for q in questions {
                let names = q.options.map(\.name)
                let pick: String?
                switch q.key {
                case MoodOutput.outputName: pick = moodTo.first { names.contains($0) } ?? (names.contains(mood) ? mood : names.first)
                case MomentOutput.emotionKey: pick = face.flatMap { names.contains($0) ? $0 : nil } ?? (names.contains("none") ? "none" : names.first)
                case MomentOutput.sayKey: pick = say.flatMap { names.contains($0) ? $0 : nil } ?? "none"
                case MomentOutput.replyKey: pick = read.reply.flatMap { names.contains($0) ? $0 : nil } ?? (names.contains("huh") ? "huh" : names.first)
                case Signs.questionKey: pick = sign(q)
                default: pick = q.options.first { $0.name == "none" }?.name ?? names.first
                }
                if let pick { out[q.key] = Answer(choice: pick, probabilities: [pick: 1]) }
            }
            return out
        }

        /// The sign: a reply's line for the reply it makes (the agents'
        /// facts for a status), the idle beat held up unless the mood is
        /// cross or low, and a prompt's sign only when it sounds like
        /// something or says the name.
        func sign(_ q: Question) -> String? {
            let captions = q.options.filter { $0.name != "none" && $0.name != "facts" }
            let none = q.options.first { $0.name == "none" || $0.name == "facts" }?.name
            if q.options.contains(where: { $0.name == "facts" }) {
                guard let reply = read.reply, reply != "status" else { return "facts" }
                let fits = captions.filter { $0.what.contains(" \(reply) reply") || $0.what.contains(" \(reply) or") || $0.what.contains("or \(reply) reply") }
                return fits.isEmpty ? none : fits[Int(roll % UInt64(fits.count))].name
            }
            guard !captions.isEmpty else { return none }
            switch read.slot {
            case .idle: return mood == "cross" || mood == "sad" ? none : captions[Int(roll % UInt64(captions.count))].name
            case .prompt: return none
            default: return captions[Int(roll % UInt64(captions.count))].name
            }
        }
    }

    /// Your words to Boop, by plain matching: what they are to the mood
    /// map and the reply they get. With no match, a curious huh.
    public enum Words {
        static let sorry = ["sorry", "my bad", "apolog", "didn't mean", "just kidding", "jk", "it's fine", "its fine"]
        static let thanks = ["thank", "thx", "ty "]
        static let kind = ["love you", "good boy", "good girl", "good job", "you're the best", "youre the best", "best buddy",
                           "cute", "cheer up", "proud of you", "well done", "nice work", "great job", "love ya", "awesome", "great work",
                           "good work", "shipped", "we did it", "nailed it", "wish me luck", "you rock", "amazing", "thanks for"]
        static let rude = ["stupid", "idiot", "dumb", "hate you", "useless", "ugly", "shut up", "go away", "annoying", "suck"]
        static let sad = ["i'm sad", "im sad", "pretty sad", "so sad", "been sad", "bad day", "rough day", "feel down",
                          "feeling down", "depressed", "lonely", "died", "passed away", "lost my", "awful day", "terrible day", "is sick",
                          "am sick", "i'm sick", "exhausted", "so tired", "i'm tired", "stressed", "burnt out", "burned out", "hurts"]
        static let hush = ["shh", "hush", "be quiet", "quiet please", "stop talking"]
        static let hello = ["hello", "hi ", "hey", "good morning", "morning", "howdy", "yo "]
        static let bye = ["bye", "good night", "goodnight", "see you", "see ya", "later", "night night", "go to sleep", "nap time",
                          "sleep well", "sweet dreams"]
        static let laugh = ["haha", "lol", "hehe", "silly", "funny", "tickle", "joke"]
        static let status = ["claude", "codex", "agent", "working on", "how's it going", "hows it going", "how long", "how many",
                             "is it done", "are they", "status", "progress", "the tests", "test pass", "tests pass", "finished",
                             "going on", "the build", "is it working", "still working", "done yet"]
        /// Asking Boop to do something for an agent, which it never does: no.
        static let forAgent = ["tell claude", "tell codex", "tell it", "tell the agent", "approve", "say yes to", "click yes",
                               "accept it", "answer it"]
        static let allowed = ["you can talk", "talk now", "you can speak", "go ahead", "okay", "ok ", "alright", "sure", "yes", "yeah"]
        static let tricks = ["roll over", "dance", " sit ", "fetch", "do a trick", "jump", "sing", "spin"]
        /// Questions about Boop itself: yes.
        static let aboutBoop = ["are you", "you ok", "you okay", "can you hear", "can you see", "do you", "you there", "you awake"]

        public static func read(_ said: String) -> Read {
            let w = " " + said.lowercased() + " "
            func has(_ list: [String]) -> Bool { list.contains { w.contains($0) } }
            if has(forAgent) { return Read(slot: .wordsQuestion, cues: [.touched], reply: "no") }
            if has(hush), !has(["you can talk", "talk now"]) { return Read(slot: .words, cues: [.hush, .touched], reply: "hush") }
            if has(sorry) { return Read(slot: .wordsSorry, cues: [.sorry, .touched], reply: "thanks") }
            if has(rude) { return Read(slot: .wordsRude, cues: [.rudeWords, .touched], reply: "ouch") }
            if has(sad) { return Read(slot: .wordsSad, cues: [.sadNews, .touched], reply: "comfort") }
            let greets = hello.contains { w.hasPrefix(" " + $0) } || w.hasPrefix(" hi ")
            if greets { return Read(slot: .wordsHello, cues: [.touched], reply: "hello") }
            if has(status) { return Read(slot: .wordsQuestion, cues: [.touched], reply: "status") }
            if has(thanks) { return Read(slot: .wordsThanks, cues: [.kindWords, .touched], reply: "thanks") }
            if has(kind) { return Read(slot: .wordsKind, cues: [.kindWords, .touched], reply: "thanks") }
            if has(bye) { return Read(slot: .wordsBye, cues: [.touched], reply: "bye") }
            if has(hello) || w.contains("how are you") { return Read(slot: .wordsHello, cues: [.touched], reply: "hello") }
            if has(laugh) { return Read(slot: .words, cues: [.touched], reply: "hehe") }
            if has(tricks) { return Read(slot: .wordsQuestion, cues: [.touched], reply: "no") }
            if has(aboutBoop) || has(allowed) {
                return Read(slot: .wordsQuestion, cues: [.touched], reply: "yes")
            }
            return Read(slot: .words, cues: [.touched], reply: "huh")
        }
    }
}

/// A small seeded generator, so a seed repeats a run.
struct SplitMix {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
