import Foundation
import XCTest
@testable import BoopKit

extension Take {
    /// A real take by id, for tests.
    static func named(_ id: String) -> Take { Take.all.first { $0.id == id }! }
}

/// The version in a voice pack's header: its 16 bytes after the magic,
/// NUL-padded.
func voicePackVersion(_ pack: Data) -> String {
    String(decoding: pack[8..<24].prefix { $0 != 0 }, as: UTF8.self)
}

extension DeviceMoment.Say {
    /// Excited's "Go" (new.d02): a real take for tests.
    static let go = DeviceMoment.Say(takes: [.named("new.d02")])

    /// A made-up take `ms` long, for tests that time a line.
    static func test(ms: Int) -> DeviceMoment.Say {
        .init(takes: [Take(id: "test", text: "Test", part: .about, meaning: "start", kind: .word, mood: "calm", finish: nil, ms: ms)])
    }
}

/// The recorded voice, which Boop's pack and Pixel's each have a copy of
/// (characters/CHARACTER.md §8): these run with either.
final class VoiceTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(!Take.all.isEmpty, "needs a character pack with a voice")
    }

    let moods = MoodAction.moods.map(\.name)

    /// Every take is in one of the 13 moods, answers a
    /// question the react action asks (or only the rules say it), and has
    /// a length and text the bubble can show; ids are unique.
    func testEveryTakeIsUsable() {
        let feelings = Set(ReactAction.feelings.map(\.name)), topics = Set(ReactAction.topics.map(\.name))
        XCTAssertEqual(Take.all.count, 2722)
        XCTAssertEqual(Set(Take.all.map(\.id)).count, Take.all.count)
        for t in Take.all {
            XCTAssertTrue(moods.contains(t.mood), "\(t.id) is in \(t.mood)")
            switch t.part {
            case .feeling: XCTAssertTrue(feelings.contains(t.meaning), "\(t.id) feels \(t.meaning), which say.feeling doesn't offer")
            case .about: XCTAssertTrue(topics.contains(t.meaning), "\(t.id) is about \(t.meaning), which say.about doesn't offer")
            case .attention: XCTAssertEqual(t.meaning, "attention")
            }
            XCTAssertTrue((300...3000).contains(t.ms), "\(t.id) is \(t.ms) ms")
            XCTAssertTrue(!t.text.isEmpty && t.text.utf8.count <= 35 && t.text.allSatisfy { $0.isASCII }, t.text)
            XCTAssertTrue(t.finish == nil || ["success", "failure"].contains(t.finish!), t.id)
        }
        // Swears only on a failure, and only as a feeling.
        XCTAssertTrue(Take.all.filter { $0.kind == .swear }.allSatisfy { $0.finish == "failure" && $0.part == .feeling })
        XCTAssertEqual(Take.packVersion.count, 12)
    }

    /// The owner's rule: every face has a take for every
    /// feeling and every topic, so the react action offers them all.
    /// Every feeling has one that plays whatever
    /// the finish, but glad in a bad mood, which is only relief at a
    /// success.
    func testNoFaceIsWithoutWords() {
        let bad: Set = ["annoyed", "irritated", "grumpy", "whiny", "wounded", "sad"]
        for (part, answers) in [(Take.Part.feeling, ReactAction.feelings), (.about, ReactAction.topics)] {
            for a in answers.map(\.name) {
                XCTAssertEqual(Set(Take.all.filter { $0.part == part && $0.meaning == a }.map(\.mood)), Set(moods), "\(part) \(a)")
                for face in moods where part == .feeling && !(a == "glad" && bad.contains(face)) {
                    XCTAssertTrue(Take.all.contains { $0.part == part && $0.meaning == a && $0.mood == face && $0.finish == nil },
                                  "\(face) \(a) says nothing unless the turn finished")
                }
            }
        }
    }

    /// The takes the board plays are the Mac's: voicegen writes both, and
    /// the board reports the pack's version.
    func testThePackHasEveryTake() throws {
        let pack = try Data(contentsOf: CharacterPack.active.directory.appendingPathComponent("voice/voice.bin"))
        XCTAssertEqual(pack.prefix(8), Data("BOOPVOX1".utf8))
        XCTAssertEqual(voicePackVersion(pack), Take.packVersion, "rerun voicegen")
        func u32(_ at: Int) -> Int { pack[at..<at + 4].enumerated().reduce(0) { $0 | Int($1.1) << (8 * $1.0) } }
        let count = u32(24), size = u32(28), index = u32(32)
        let ids = (0..<count).map { i in String(decoding: pack[(index + i * size)...].prefix(72).prefix { $0 != 0 }, as: UTF8.self) }
        XCTAssertEqual(ids, Take.all.map(\.id).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
    }

    /// A take of the answer, in the face's mood only, fit for
    /// the finish.
    func testATakeIsOnlyEverTheFacesMood() {
        var rng = SplitMix64(seed: 1)
        for face in moods {
            for (part, answers) in [(Take.Part.feeling, Voice.answers(.feeling)), (.about, Voice.answers(.about))] {
                for a in answers {
                    for kind in Take.Kind.allCases {
                        for finish in [nil, "success", "failure"] {
                            guard let t = Voice.take(part, meaning: a, kind: kind, face: face, finish: finish, rng: &rng) else { continue }
                            XCTAssertEqual(t.mood, face)
                            XCTAssertEqual(t.meaning, a)
                            XCTAssertEqual(t.part, part)
                            XCTAssertTrue(t.finish == nil || t.finish == finish, "\(t.id) needs a \(t.finish!)")
                            XCTAssertTrue(t.kind != .swear || kind == .swear, "\(t.id): a swear nobody asked for")
                        }
                    }
                }
            }
        }
    }

    /// A success take only on a success, a swear only on a
    /// failed turn.
    func testTheFinishGatesSuccessesAndSwears() {
        var rng = SplitMix64(seed: 2)
        // Grumpy is glad only with relief, at a success.
        XCTAssertNil(Voice.take(.feeling, meaning: "glad", kind: .sound, face: "grumpy", finish: nil, rng: &rng))
        XCTAssertEqual(Voice.take(.feeling, meaning: "glad", kind: .sound, face: "grumpy", finish: "success", rng: &rng)?.finish, "success")
        // Irritated swears at a failed turn; with no failure, the nearest
        // plainer kind: a phrase.
        XCTAssertEqual(Voice.take(.feeling, meaning: "upset", kind: .swear, face: "irritated", finish: "failure", rng: &rng)?.kind, .swear)
        XCTAssertEqual(Voice.take(.feeling, meaning: "upset", kind: .swear, face: "irritated", finish: nil, rng: &rng)?.kind, .phrase)
        // "Passed" is about tests, and only at a success.
        XCTAssertFalse(Take.all.contains { $0.text == "Passed" && ($0.meaning != "tests" || $0.finish != "success") })
    }

    /// With none of the kind asked for, the nearest kind,
    /// plainer first; never a swear nobody asked for.
    func testKindTakesTheNearest() {
        XCTAssertEqual(Voice.order(.sound), [.sound, .word, .phrase])
        XCTAssertEqual(Voice.order(.word), [.word, .sound, .phrase])
        XCTAssertEqual(Voice.order(.phrase), [.phrase, .word, .sound])
        XCTAssertEqual(Voice.order(.swear), [.swear, .phrase, .word, .sound])
        var rng = SplitMix64(seed: 3)
        // Tickled has no sounds: a sound asked for says a word.
        XCTAssertEqual(Voice.take(.feeling, meaning: "tickled", kind: .sound, face: "calm", finish: nil, rng: &rng)?.kind, .word)
        // Happy's glad words need a success: without one, a sound.
        XCTAssertEqual(Voice.take(.feeling, meaning: "glad", kind: .word, face: "happy", finish: nil, rng: &rng)?.kind, .sound)
    }

    /// The last line's words aren't said again while another
    /// fits.
    func testTheLastTakesArentRepeated() {
        var rng = SplitMix64(seed: 4)
        let sounds = Take.all.filter { $0.part == .feeling && $0.meaning == "upset" && $0.mood == "annoyed" && $0.kind == .sound }
        let avoiding = Set(sounds.dropLast().map(\.text))
        for _ in 0..<50 {
            XCTAssertEqual(Voice.take(.feeling, meaning: "upset", kind: .sound, face: "annoyed", finish: nil, avoiding: avoiding, rng: &rng)?.id,
                           sounds.last?.id)
        }
        // With every one avoided, one is said anyway.
        XCTAssertNotNil(Voice.take(.feeling, meaning: "upset", kind: .sound, face: "annoyed", finish: nil,
                                   avoiding: Set(sounds.map(\.text)), rng: &rng))
        // A word recorded twice (previous.basta and phase1.borrowed.basta__annoyed__contained)
        // isn't said again by its other recording.
        for _ in 0..<50 {
            XCTAssertNotEqual(Voice.take(.feeling, meaning: "upset", kind: .word, face: "annoyed", finish: nil,
                                         avoiding: [Take.named("previous.basta").text], rng: &rng)?.text, "Basta")
        }
        // Nor by another mood's: after calm's "Ready", a curious face
        // doesn't say its own.
        let ready = Take.named("phase1.word.begin.ready__calm__contained")
        for _ in 0..<50 {
            XCTAssertNotEqual(Voice.take(.about, meaning: "start", kind: .word, face: "curious", finish: nil,
                                         avoiding: [ready.text], rng: &rng)?.text, "Ready")
        }
    }

    /// The feeling, then the topic; a phrase alone; and a pair
    /// no longer than `maxLineMs`.
    func testALineIsTheFeelingThenTheTopic() {
        var rng = SplitMix64(seed: 5)
        for _ in 0..<50 {
            let line = Voice.line(feeling: "upset", about: "tests", kind: .sound, face: "annoyed", finish: nil, rng: &rng)
            XCTAssertFalse(line.isEmpty)
            XCTAssertEqual(line[0].part, .feeling)
            if line.count == 2 {
                XCTAssertEqual(line[1].part, .about)
                XCTAssertEqual(line[1].meaning, "tests")
                XCTAssertLessThanOrEqual(line[0].ms + Voice.joinGapMs + line[1].ms, Voice.maxLineMs)
            }
            XCTAssertLessThanOrEqual(line.count, 2)
        }
        // A phrase plays alone.
        let phrase = Voice.line(feeling: "upset", about: "tests", kind: .phrase, face: "grumpy", finish: nil, rng: &rng)
        XCTAssertEqual(phrase.map(\.kind), [.phrase])
        // A phrase asked for is the topic's when only the topic has one:
        // curious and happy have no glad phrase.
        XCTAssertEqual(Voice.line(feeling: "glad", about: "tests", kind: .phrase, face: "curious", finish: nil, rng: &rng).map(\.text),
                       ["Fingers crossed"])
        let done = Voice.line(feeling: "glad", about: "done", kind: .phrase, face: "happy", finish: "success", rng: &rng)
        XCTAssertEqual(done.map { "\($0.part) \($0.kind)" }, ["about phrase"])
        // Any other ask keeps the feeling's take, so a swear asked for with
        // none to say stays upset: the feeling's phrase in sad, and in calm
        // its word, not the topic's phrase ("Tiny steps").
        let sad = Voice.line(feeling: "upset", about: "stopped", kind: .swear, face: "sad", finish: "failure", rng: &rng)
        XCTAssertEqual(sad.map { "\($0.part) \($0.kind)" }, ["feeling phrase"])
        for _ in 0..<20 {
            let calm = Voice.line(feeling: "upset", about: "start", kind: .swear, face: "calm", finish: nil, rng: &rng)
            XCTAssertEqual(calm.map { "\($0.part) \($0.kind)" }, ["feeling word"])
        }
        // Only a topic: its take alone.
        let topic = Voice.line(feeling: nil, about: "tests", kind: .sound, face: "calm", finish: nil, rng: &rng)
        XCTAssertEqual(topic.map(\.part), [.about])
        XCTAssertEqual(Voice.line(feeling: nil, about: nil, kind: .sound, face: "calm", finish: nil, rng: &rng), [])
        // Two takes on the wire.
        let two = DeviceMoment.Say(takes: [.named("previous.tsk"), .named("phase1.word.test.test__annoyed__contained")])
        XCTAssertEqual(two.json.json, #"{"take":"previous.tsk","then":"phase1.word.test.test__annoyed__contained"}"#)
        XCTAssertEqual(two.text, "Tsk... Test")
    }

    /// Needs you's takes are in the pack, but no reaction
    /// says them.
    func testNoReactionSaysNeedsYousTakes() {
        XCTAssertFalse(Voice.answers(.feeling).union(Voice.answers(.about)).contains("attention"))
    }
}
